-module(gluegun_ws_close_test).

-export([with_server/2, owned_connection/0, assert_released/1, timed/1,
    remember_connection/1, remembered_connection/0, error_paths/0]).

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
            exit(Server, kill),
            erlang:demonitor(Monitor, [flush]),
            receive {released, Server} -> ok after 0 -> ok end,
            receive {unrelated_ws_mail, Unrelated} -> ok after 0 -> ok end
        end
    end).

owned_connection() ->
    checked(fun() ->
        Owner = self(),
        Connections = [Pid || {_, Pid, _, _} <- supervisor:which_children(gun_conns_sup),
            is_pid(Pid), maps:get(owner, gun:info(Pid)) =:= Owner],
        [Connection] = Connections,
        {ok, Connection}
    end).

assert_released(Connection) ->
    checked(fun() ->
        false = is_process_alive(Connection),
        {messages, Messages} = process_info(self(), messages),
        [] = [Message || Message <- Messages, is_tuple(Message),
            tuple_size(Message) >= 2, element(2, Message) =:= Connection],
        %% The teardown receive must leave unrelated messages alone.
        self() ! unrelated_ws_test_message,
        {ok, nil} = gluegun_ffi:terminate(Connection),
        receive unrelated_ws_test_message -> ok after 0 -> error(unrelated_mail_lost) end,
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
        Accept = base64:encode(crypto:hash(sha,
            <<(string:trim(Key))/binary, "258EAFA5-E914-47DA-95CA-C5AB0DC85B11">>)),
        ok = gen_tcp:send(Socket, [
            <<"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n",
                "Connection: Upgrade\r\nSec-WebSocket-Accept: ">>,
            Accept, <<"\r\n\r\n">>]),
        case Name of
            <<"peer_close">> -> ok = send_frame(Socket, 8, <<>>);
            <<"peer_reason">> -> ok = send_frame(Socket, 8, <<1000:16, "bye">>);
            _ -> ok
        end,
        exchange(Socket, Name),
        Parent ! {released, self()}
    after gen_tcp:close(Socket)
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
                <<"peer_close">> -> await_closed(Socket);
                <<"peer_reason">> -> await_closed(Socket);
                <<"failure">> -> gen_tcp:close(Socket);
                <<"chatter">> -> chatter(Socket);
                <<"stall">> -> await_closed(Socket)
            end;
        {error, closed} -> ok
    end.

read_frame(Socket) ->
    case gen_tcp:recv(Socket, 2, 7000) of
        {ok, <<_Fin:1, _Rsv:3, Opcode:4, 1:1, Length:7>>} when Length < 126 ->
            {ok, <<Mask:4/binary>>} = gen_tcp:recv(Socket, 4, 2000),
            Data = case Length of
                0 -> <<>>;
                _ ->
                    {ok, Payload} = gen_tcp:recv(Socket, Length, 2000),
                    Payload
            end,
            {ok, Opcode, unmask(Data, Mask, 0, <<>>)};
        {error, closed} -> {error, closed}
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
