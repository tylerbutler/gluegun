-module(gluegun_ws_close_test).
-include_lib("public_key/include/public_key.hrl").

-export([with_server/2, owned_connection/0, assert_released/1, timed/1,
    remember_connection/1, remembered_connection/0, error_paths/0, with_tls_server/1,
    assert_exception_cleanup/2, assert_scoped_exception/2,
    cleanup_guard_paths/0,
    with_control_frames/2, queue_control_frame/0]).

queue_control_frame() ->
    Connection = self(),
    Stream = make_ref(),
    self() ! {gun_ws, Connection, Stream, ping},
    {Connection, Stream}.

%% Mode is the same String as with_server ("normal" or "stall").
%% FailureCallback is fn() -> Result(Nil, GluegunError), supplied by Gleam for
%% real panic/failed-assert coverage, or by exception_paths for Erlang failures.
assert_scoped_exception(Mode, FailureCallback) ->
    with_server(Mode, fun(Port) ->
        Key = make_ref(),
        Options = gluegun@websocket:with_timeout(
            gluegun@websocket:options(), {milliseconds, 50}),
        Start = erlang:monotonic_time(millisecond),
        try
            Actual = capture_exception(fun() ->
                gluegun@websocket:with_socket(
                    <<"127.0.0.1">>, Port, <<"/echo">>, Options, fun(_) ->
                        {ok, Connection} = owned_connection(),
                        remember_connection(Connection),
                        try FailureCallback()
                        catch Class:Reason:Stack ->
                            put(Key, {Class, Reason, Stack}),
                            erlang:raise(Class, Reason, Stack)
                        end
                    end)
            end),
            Expected = erase(Key),
            case Expected of
                undefined -> error(callback_did_not_raise);
                _ -> Expected = Actual
            end,
            Elapsed = erlang:monotonic_time(millisecond) - Start,
            case Mode of
                <<"stall">> -> true = Elapsed >= 40 andalso Elapsed < 500;
                _ -> ok
            end,
            {ok, Connection} = remembered_connection(),
            assert_released(Connection)
        after
            erase(Key),
            erase(ws_test_connection)
        end
    end).

assert_exception_cleanup(Mode, Class) ->
    assert_scoped_exception(Mode, fun() ->
        case Class of
            <<"error">> -> error(deliberate_ws_error);
            <<"exit">> -> exit(deliberate_ws_exit);
            <<"throw">> -> throw(deliberate_ws_throw)
        end
    end).

cleanup_guard_paths() ->
    checked(fun() ->
        Key = make_ref(),
        try
            %% Neither an Error result nor an exception from cleanup may mask
            %% the callback exception. Check all three Erlang exception classes.
            lists:foreach(fun(CleanupFailure) ->
                put(Key, 0),
                Original = make_ref(),
                Actual = capture_exception(fun() ->
                    gluegun_ffi:ws_with_cleanup(fun() ->
                        try error(Original)
                        catch C:R:S ->
                            put({Key, original}, {C, R, S}),
                            erlang:raise(C, R, S)
                        end
                    end, fun() ->
                        put(Key, get(Key) + 1),
                        CleanupFailure()
                    end)
                end),
                Actual = erase({Key, original}),
                1 = erase(Key)
            end, [
                fun() -> {error, timeout} end,
                fun() -> error(cleanup_error) end,
                fun() -> exit(cleanup_exit) end,
                fun() -> throw(cleanup_throw) end
            ]),
            lists:foreach(fun({CallbackResult, CleanupResult}) ->
                {CallbackResult, CleanupResult} = gluegun_ffi:ws_with_cleanup(
                    fun() -> CallbackResult end, fun() -> CleanupResult end)
            end, [{{ok, nil}, {ok, nil}}, {{ok, nil}, {error, timeout}},
                {{error, {connection_down, <<"callback">>}}, {ok, nil}},
                {{error, {connection_down, <<"callback">>}}, {error, timeout}}]),
            %% A normal-path cleanup exception propagates, without retrying.
            put(Key, 0),
            {throw, cleanup_normal, _} = capture_exception(fun() ->
                gluegun_ffi:ws_with_cleanup(fun() -> {ok, nil} end, fun() ->
                    put(Key, get(Key) + 1),
                    throw(cleanup_normal)
                end)
            end),
            1 = erase(Key),
            {ok, nil}
        after
            erase(Key),
            erase({Key, original})
        end
    end).

capture_exception(Callback) ->
    try Callback() of
        Value -> error({expected_exception, Value})
    catch Class:Reason:Stack -> {Class, Reason, Stack}
    end.

%% Duration is milliseconds. The server owns all I/O; no detached sender can
%% outlive the session or delay responding to a close during the control burst.
with_control_frames(Duration, Callback) when is_integer(Duration), Duration > 0 ->
    with_server({control_frames, Duration}, Callback).

with_tls_server(Callback) ->
    checked(fun() ->
        Certificate = public_key:pkix_test_data(#{
            root => [{digest, sha256}, {key, {rsa, 2048, 65537}}],
            intermediates => [],
            peer => [{digest, sha256}, {key, {rsa, 2048, 65537}}, {extensions, [
                #'Extension'{extnID = ?'id-ce-subjectAltName',
                    extnValue = [{dNSName, "localhost"}], critical = false}
            ]}]
        }),
        {ok, Listener} = ssl:listen(0, [binary, {active, false},
            {ip, {127, 0, 0, 1}}, {reuseaddr, true},
            {alpn_preferred_protocols, [<<"h2">>, <<"http/1.1">>]} | Certificate]),
        {ok, {_, Port}} = ssl:sockname(Listener),
        {Server, Monitor} = spawn_monitor(fun() ->
            {ok, Transport} = ssl:transport_accept(Listener, 2000),
            {ok, Socket} = ssl:handshake(Transport, 2000),
            try
                {ok, <<"http/1.1">>} = ssl:negotiated_protocol(Socket),
                tls_upgrade(Socket, <<>>),
                %% The callback closes the socket using the public API.
                {ok, <<1:1, 0:3, 8:4, 1:1, Length:7>>} = ssl:recv(Socket, 2, 2000),
                {ok, _} = ssl:recv(Socket, 4 + Length, 2000),
                ok = ssl:send(Socket, <<136, 0>>),
                {error, closed} = ssl:recv(Socket, 0, 2000)
            after ssl:close(Socket)
            end
        end),
        try
            Result = Callback(Port, proplists:get_value(cacerts, Certificate)),
            case Result of
                {error, _} -> Result;
                {ok, nil} ->
                    receive
                        {'DOWN', Monitor, process, Server, normal} -> Result;
                        {'DOWN', Monitor, process, Server, Reason} ->
                            error({tls_peer_failed, Reason})
                    after 2000 -> error(tls_peer_timeout)
                    end
            end
        after
            ssl:close(Listener),
            stop_server(Server, Monitor)
        end
    end).

tls_upgrade(Socket, Acc) when byte_size(Acc) < 16384 ->
    case binary:match(Acc, <<"\r\n\r\n">>) of
        nomatch ->
            {ok, Data} = ssl:recv(Socket, 0, 2000),
            tls_upgrade(Socket, <<Acc/binary, Data/binary>>);
        _ ->
            [KeyLine] = [Line || Line <- binary:split(Acc, <<"\r\n">>, [global]),
                string:prefix(string:lowercase(Line), <<"sec-websocket-key:">>) =/= nomatch],
            [_, Key] = binary:split(KeyLine, <<":">>),
            Accept = cow_ws:encode_key(string:trim(Key)),
            ssl:send(Socket, [
                <<"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n",
                    "Connection: Upgrade\r\nSec-WebSocket-Accept: ">>,
                Accept, <<"\r\n\r\n">>])
    end.

error_paths() ->
    checked(fun() ->
        Parent = self(),
        Stream = make_ref(),
        lists:foreach(fun({Message, Expected}) ->
            Connection = spawn(fun() ->
                receive
                    {'$gen_cast', {ws_send, Parent, Stream, [close]}} ->
                        Parent ! Message(self(), Stream),
                        receive never -> ok end
                end
            end),
            {error, Expected} = gluegun_ffi:ws_close(Connection, Stream,
                {milliseconds, 100}, gluegun_ffi:ws_peer_close()),
            false = is_process_alive(Connection)
        end, [
            {fun(Pid, Ref) -> {gun_error, Pid, Ref, send_failed} end,
                {stream_error, <<"SendFailed">>}},
            {fun(Pid, _) -> {gun_error, Pid, failed} end,
                {connection_error, <<"Failed">>}}
        ]),
        Dead = spawn(fun() -> ok end),
        Monitor = monitor(process, Dead),
        receive {'DOWN', Monitor, process, Dead, _} -> ok end,
        {ok, nil} = gluegun_ffi:ws_close(Dead, Stream,
            {milliseconds, 0}, gluegun_ffi:ws_peer_close()),
        {error, {invalid_options, _}} = gluegun_ffi:ws_close(self(), Stream,
            {milliseconds, 0}, gluegun_ffi:ws_peer_close()),
        {ok, nil}
    end).

remember_connection(Connection) ->
    put(ws_test_connection, Connection),
    nil.

remembered_connection() -> {ok, erase(ws_test_connection)}.

with_server(Name, Callback) ->
    checked(fun() ->
        {ok, Listener} = gen_tcp:listen(0, [binary, {active, false},
            {ip, {127, 0, 0, 1}}, {reuseaddr, true}]),
        {ok, {_, Port}} = inet:sockname(Listener),
        Parent = self(),
        Unrelated = make_ref(),
        self() ! {unrelated_ws_mail, Unrelated},
        {Server, Monitor} = spawn_monitor(fun() -> serve(Listener, Parent, Name) end),
        try
            Result = Callback(Port),
            receive {unrelated_ws_mail, Unrelated} -> ok
            after 0 -> error(unrelated_mail_lost)
            end,
            receive
                {released, Server} -> Result;
                {'DOWN', Monitor, process, Server, Reason} -> error({server_failed, Reason})
            after 2000 -> error(server_socket_not_released)
            end
        after
            gen_tcp:close(Listener),
            stop_server(Server, Monitor),
            receive {released, Server} -> ok after 0 -> ok end,
            receive {unrelated_ws_mail, Unrelated} -> ok after 0 -> ok end
        end
    end).

owned_connection() ->
    checked(fun() ->
        Owner = self(),
        Connections = [Pid || {_, Pid, _, _} <- supervisor:which_children(gun_conns_sup),
            is_pid(Pid), owned_by(Pid, Owner)],
        %% With retry zero Gun may already have answered a peer close and
        %% exited before this inspection. Its queued frames retain identity.
        {messages, Messages} = process_info(self(), messages),
        Queued = [Pid || Message <- Messages, is_tuple(Message),
            tuple_size(Message) >= 3,
            lists:member(element(1, Message), [gun_ws, gun_down]),
            Pid <- [element(2, Message)], is_pid(Pid)],
        [Connection] = lists:usort(Connections ++ Queued),
        {ok, Connection}
    end).

owned_by(Pid, Owner) ->
    try maps:get(owner, gun:info(Pid)) =:= Owner
    catch exit:{normal, _} -> false;
        exit:{noproc, _} -> false
    end.

assert_released(Connection) ->
    checked(fun() ->
        false = is_process_alive(Connection),
        {messages, Messages} = process_info(self(), messages),
        [] = [Message || Message <- Messages, is_tuple(Message),
            tuple_size(Message) >= 2, element(2, Message) =:= Connection],
        {ok, nil}
    end).

timed(Callback) ->
    Start = erlang:monotonic_time(millisecond),
    Result = Callback(),
    {Result, erlang:monotonic_time(millisecond) - Start}.

serve(Listener, Parent, Name) ->
    {ok, Socket} = gen_tcp:accept(Listener, 2000),
    try
        Headers = headers(Socket, <<>>),
        [KeyLine] = [Line || Line <- binary:split(Headers, <<"\r\n">>, [global]),
            string:prefix(string:lowercase(Line), <<"sec-websocket-key:">>) =/= nomatch],
        [_, Key] = binary:split(KeyLine, <<":">>),
        Accept = cow_ws:encode_key(string:trim(Key)),
        case Name of
            <<"inform">> ->
                ok = gen_tcp:send(Socket, <<"HTTP/1.1 100 Continue\r\n\r\n",
                    "HTTP/1.1 103 Early Hints\r\nLink: </style.css>\r\n\r\n">>);
            <<"deadline">> ->
                ok = gen_tcp:send(Socket, <<"HTTP/1.1 100 Continue\r\n\r\n">>),
                timer:sleep(30),
                ok = gen_tcp:send(Socket, <<"HTTP/1.1 103 Early Hints\r\n\r\n">>),
                timer:sleep(30);
            _ -> ok
        end,
        case Name of
            <<"deadline">> -> await_closed(Socket);
            _ ->
                Extra = case Name of
                    <<"subprotocols">> ->
                        true = binary:match(Headers,
                            <<"sec-websocket-protocol: chat, superchat\r\n">>) =/= nomatch,
                        <<"Sec-WebSocket-Protocol: superchat\r\nX-Handshake: retained\r\n">>;
                    <<"single_protocol">> ->
                        true = binary:match(Headers,
                            <<"sec-websocket-protocol: chat\r\n">>) =/= nomatch,
                        <<"Sec-WebSocket-Protocol: chat\r\n">>;
                    _ -> <<>>
                end,
                ok = gen_tcp:send(Socket, [
                    <<"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n",
                        "Connection: Upgrade\r\nSec-WebSocket-Accept: ">>,
                    Accept, <<"\r\n">>, Extra, <<"\r\n">>]),
                serve_frames(Socket, Name)
        end,
        Parent ! {released, self()}
    after gen_tcp:close(Socket)
    end.

serve_frames(Socket, Name) ->
    case Name of
        {control_frames, Duration} -> control_frames(Socket, Duration);
        <<"controls">> -> control_frames(Socket, 260);
        <<"controls_deadline">> -> control_frames(Socket, 260);
        _ -> serve_application_frames(Socket, Name)
    end.

control_frames(Socket, Duration) ->
    control_frames(Socket, erlang:monotonic_time(millisecond) + Duration, 0).

control_frames(Socket, Deadline, Sequence) ->
    case erlang:monotonic_time(millisecond) >= Deadline of
        true ->
            ok = send_frame(Socket, 1, <<"late text">>),
            exchange(Socket, <<"normal">>);
        false ->
            Payload = <<Sequence:32>>,
            ok = send_frame(Socket, 9, Payload),
            ok = send_frame(Socket, 10, Payload),
            %% Gun must automatically echo this exact ping payload as a pong.
            case read_frame(Socket, 1000) of
                {ok, 10, Payload} ->
                    case read_frame(Socket, 20) of
                        {error, timeout} -> control_frames(Socket, Deadline, Sequence + 1);
                        {ok, 8, _} -> reply_close(Socket);
                        Other -> error({unexpected_control_response, Other})
                    end;
                Other -> error({missing_automatic_pong, Payload, Other})
            end
    end.

serve_application_frames(Socket, Name) ->
        case Name of
            <<"peer_close">> -> ok = send_frame(Socket, 8, <<>>);
            <<"peer_reason">> -> ok = send_frame(Socket, 8, <<1000:16, "bye">>);
            <<"flow_consumed">> -> ok = send_frame(Socket, 1, <<"one">>);
            <<"flow_coalesced">> ->
                ok = gen_tcp:send(Socket, [
                    <<129, 3, "one">>, <<129, 3, "two">>, <<129, 5, "three">>]);
            _ -> ok
        end,
    case Name of
        <<"drop">> -> ok;
        _ -> exchange(Socket, Name)
    end.

headers(Socket, Acc) when byte_size(Acc) < 16384 ->
    case binary:match(Acc, <<"\r\n\r\n">>) of
        nomatch ->
            {ok, Data} = gen_tcp:recv(Socket, 0, 2000),
            headers(Socket, <<Acc/binary, Data/binary>>);
        _ -> Acc
    end.

exchange(Socket, Name) ->
    case read_frame(Socket) of
        {ok, 1, Data} ->
            ok = send_frame(Socket, 1, Data),
            exchange(Socket, Name);
        {ok, 8, _} ->
            case Name of
                <<"normal">> ->
                    ok = send_frame(Socket, 8, <<1000:16, "bye">>),
                    await_closed(Socket);
                <<"flow_consumed">> -> reply_close(Socket);
                <<"flow_coalesced">> -> reply_close(Socket);
                <<"flow_during">> ->
                    ok = gen_tcp:send(Socket, [
                        <<129, 3, "one">>, <<129, 3, "two">>, <<129, 5, "three">>]),
                    %% Separate transport data after Gun has spent its credit.
                    timer:sleep(20),
                    reply_close(Socket);
                <<"inform">> -> reply_close(Socket);
                <<"subprotocols">> -> reply_close(Socket);
                <<"single_protocol">> -> reply_close(Socket);
                <<"peer_close">> -> await_closed(Socket);
                <<"peer_reason">> -> await_closed(Socket);
                <<"failure">> -> gen_tcp:close(Socket);
                <<"chatter">> -> chatter(Socket);
                <<"stall">> -> await_closed(Socket)
            end;
        {error, closed} -> ok
    end.

reply_close(Socket) ->
    ok = send_frame(Socket, 8, <<1000:16, "bye">>),
    await_closed(Socket).

read_frame(Socket) ->
    read_frame(Socket, 7000).

read_frame(Socket, Timeout) ->
    case gen_tcp:recv(Socket, 2, Timeout) of
        {ok, <<_Fin:1, _Rsv:3, Opcode:4, 1:1, Length:7>>} when Length < 126 ->
            {ok, <<Mask:4/binary>>} = gen_tcp:recv(Socket, 4, 2000),
            Data = case Length of
                0 -> <<>>;
                _ ->
                    {ok, Payload} = gen_tcp:recv(Socket, Length, 2000),
                    Payload
            end,
            {ok, Opcode, unmask(Data, Mask, 0, <<>>)};
        {error, closed} -> {error, closed};
        {error, timeout} -> {error, timeout}
    end.

unmask(<<>>, _, _, Acc) -> Acc;
unmask(<<Byte, Rest/binary>>, Mask, Index, Acc) ->
    Key = binary:at(Mask, Index rem 4),
    unmask(Rest, Mask, Index + 1, <<Acc/binary, (Byte bxor Key)>>).

send_frame(Socket, Opcode, Data) ->
    gen_tcp:send(Socket, <<1:1, 0:3, Opcode:4, 0:1, (byte_size(Data)):7, Data/binary>>).

await_closed(Socket) ->
    case gen_tcp:recv(Socket, 0, 7000) of
        {error, closed} -> ok;
        {ok, _} -> await_closed(Socket)
    end.

chatter(Socket) ->
    case send_frame(Socket, 1, <<"still waiting">>) of
        ok ->
            case gen_tcp:recv(Socket, 0, 1) of
                {error, timeout} -> chatter(Socket);
                {error, closed} -> ok;
                {ok, _} -> chatter(Socket)
            end;
        {error, closed} -> ok;
        {error, econnreset} -> ok
    end.

checked(Callback) ->
    try Callback()
    catch Class:Reason:Stack ->
        {error, {erlang_error, gleam@string:inspect({Class, Reason, Stack})}}
    end.

stop_server(Server, Monitor) ->
    try
        case is_process_alive(Server) of
            false -> ok;
            true ->
                exit(Server, kill),
                receive {'DOWN', Monitor, process, Server, _} -> ok
                after 1000 -> error(peer_cleanup_timeout)
                end
        end
    after erlang:demonitor(Monitor, [flush])
    end.
