-module(gluegun_ws_control_test).
-export([with_echo_connection/1, with_incoming_controls/3,
    with_incoming_controls_default/2]).

%% A loopback peer for control-frame tests. No external server or fixed port.
with_echo_connection(Callback) ->
    with_connection(#{silence_pings => false}, fun echo_frames/1, echo, Callback).

%% Gleam: (Bool, BitArray, fn(Connection, Stream) -> Nil) -> Nil.
%% Payload must be byte-aligned and at most 125 bytes (a control-frame limit).
%% The callback receives Text("hello") then Binary(<<1,2,3>>) via
%% receive_app_frame, sends Text("controls received"), and receives
%% Text("one pong"). The marker fences all automatic/application pong sends.
with_incoming_controls(SilencePings, Payload, Callback)
    when is_boolean(SilencePings), is_binary(Payload), byte_size(Payload) =< 125 ->
    with_connection(#{silence_pings => SilencePings},
        fun(Socket) -> incoming_controls(Socket, Payload) end, incoming, Callback).

%% Gleam: (BitArray, fn(Connection, Stream) -> Nil) -> Nil.
%% Deliberately omit silence_pings to exercise Gun's default handler options.
with_incoming_controls_default(Payload, Callback)
    when is_binary(Payload), byte_size(Payload) =< 125 ->
    with_connection(#{}, fun(Socket) -> incoming_controls(Socket, Payload) end,
        incoming, Callback).

with_connection(WsOptions, ServeFrames, Mode, Callback) ->
    {ok, Listen} = gen_tcp:listen(0, [binary, {active, false}, {packet, raw},
        {ip, {127, 0, 0, 1}}]),
    {ok, {_, Port}} = inet:sockname(Listen),
    {Server, Monitor} = spawn_monitor(fun() -> serve(Listen, ServeFrames) end),
    try
        {ok, Conn} = gun:open("127.0.0.1", Port,
            #{transport => tcp, protocols => [http], retry => 0}),
        ConnMonitor = erlang:monitor(process, Conn),
        try
            {ok, http} = gun:await_up(Conn, 5000),
            Stream = gun:ws_upgrade(Conn, <<"/ws">>, [], WsOptions),
            {upgrade, [<<"websocket">>], _} = gun:await(Conn, Stream, 5000),
            nil = Callback(Conn, Stream)
        after
            close_connection(Conn, ConnMonitor)
        end
    after
        gen_tcp:close(Listen),
        stop_server(Server, Monitor, Mode)
    end.

%% Establish termination before flushing: otherwise a late gun_down can
%% arrive after the helper has returned to the shared Unitest process.
close_connection(Conn, Monitor) ->
    try
        case gun:close(Conn) of
            ok -> ok;
            {error, not_found} -> ok;
            Other -> error({control_connection_close_failed, Other})
        end,
        receive
            {'DOWN', Monitor, process, Conn, _} -> ok
        after 1000 ->
            exit(Conn, kill),
            receive
                {'DOWN', Monitor, process, Conn, _} -> ok
            after 1000 ->
                error(control_connection_did_not_stop)
            end
        end,
        gun:flush(Conn)
    after
        erlang:demonitor(Monitor, [flush])
    end.

stop_server(Server, Monitor, Mode) ->
    receive
        {'DOWN', Monitor, process, Server, normal} -> ok;
        {'DOWN', Monitor, process, Server, Reason} -> error({echo_server_failed, Reason})
    after 1000 ->
        exit(Server, shutdown),
        receive
            {'DOWN', Monitor, process, Server, shutdown} ->
                case Mode of
                    echo -> ok;
                    incoming -> error(incoming_control_server_did_not_complete)
                end;
            {'DOWN', Monitor, process, Server, Reason} -> error({echo_server_failed, Reason})
        after 1000 ->
            error(echo_server_did_not_stop)
        end
    end.

serve(Listen, ServeFrames) ->
    {ok, Socket} = gen_tcp:accept(Listen, 5000),
    try
        handshake(Socket),
        ServeFrames(Socket)
    after
        gen_tcp:close(Socket)
    end.

handshake(Socket) ->
    ok = inet:setopts(Socket, [{packet, http_bin}]),
    {ok, {http_request, 'GET', _, _}} = gen_tcp:recv(Socket, 0, 5000),
    Key = handshake_headers(Socket, undefined),
    true = is_binary(Key),
    Accept = base64:encode(crypto:hash(sha,
        <<Key/binary, "258EAFA5-E914-47DA-95CA-C5AB0DC85B11">>)),
    ok = gen_tcp:send(Socket, [
        <<"HTTP/1.1 101 Switching Protocols\r\n",
          "Upgrade: websocket\r\nConnection: Upgrade\r\n",
          "Sec-WebSocket-Accept: ">>, Accept, <<"\r\n\r\n">>
    ]),
    ok = inet:setopts(Socket, [{packet, raw}]).

handshake_headers(Socket, Key) ->
    case gen_tcp:recv(Socket, 0, 5000) of
        {ok, http_eoh} -> Key;
        {ok, {http_header, _, Name, _, Value}} ->
            case string:lowercase(header_name(Name)) of
                <<"sec-websocket-key">> -> handshake_headers(Socket, Value);
                _ -> handshake_headers(Socket, Key)
            end;
        Other -> error({invalid_handshake, Other})
    end.

header_name(Name) when is_atom(Name) -> atom_to_binary(Name);
header_name(Name) -> Name.

echo_frames(Socket) ->
    case recv_client_frame(Socket, deadline()) of
        {error, closed} -> ok;
        {ok, Opcode, Payload} ->
            ReplyOpcode = case Opcode of 9 -> 10; _ -> Opcode end,
            ok = gen_tcp:send(Socket, server_frame(ReplyOpcode, Payload)),
            case Opcode of
                8 -> ok;
                _ -> echo_frames(Socket)
            end;
        Other -> error({invalid_client_frame, Other})
    end.

incoming_controls(Socket, Payload) ->
    ok = gen_tcp:send(Socket, [
        server_frame(9, Payload),
        server_frame(10, Payload),
        server_frame(1, <<"hello">>),
        server_frame(2, <<1, 2, 3>>)
    ]),
    count_pongs_until_marker(Socket, Payload, 0, deadline()).

count_pongs_until_marker(Socket, Payload, Count, Deadline) ->
    case recv_client_frame(Socket, Deadline) of
        {ok, 10, Payload} ->
            count_pongs_until_marker(Socket, Payload, Count + 1, Deadline);
        {ok, 1, <<"controls received">>} when Count =:= 1 ->
            ok = gen_tcp:send(Socket, server_frame(1, <<"one pong">>));
        {ok, 1, <<"controls received">>} ->
            error({unexpected_pong_count, Count});
        Other ->
            error({unexpected_incoming_control_reply, Other})
    end.

server_frame(Opcode, Payload) when byte_size(Payload) =< 125 ->
    Length = byte_size(Payload),
    <<1:1, 0:3, Opcode:4, 0:1, Length:7, Payload/binary>>.

%% One absolute deadline bounds the entire incoming-control exchange, even
%% when a broken client keeps sending pongs instead of the ordering marker.
deadline() -> erlang:monotonic_time(millisecond) + 5000.

remaining(Deadline) ->
    max(0, Deadline - erlang:monotonic_time(millisecond)).

recv_client_frame(Socket, Deadline) ->
    case remaining(Deadline) of
        0 -> {error, timeout};
        Timeout -> recv_client_frame_header(Socket, Deadline, Timeout)
    end.

recv_client_frame_header(Socket, Deadline, Timeout) ->
    case gen_tcp:recv(Socket, 2, Timeout) of
        {ok, <<1:1, 0:3, Opcode:4, 1:1, Length:7>>} when Length =< 125 ->
            case gen_tcp:recv(Socket, Length + 4, remaining(Deadline)) of
                {ok, <<Mask:4/binary, Masked:Length/binary>>} ->
                    {ok, Opcode, unmask(Masked, Mask, 0, [])};
                Other -> error({invalid_client_payload, Other})
            end;
        {error, _} = Error -> Error;
        Other -> error({invalid_client_frame, Other})
    end.

unmask(<<>>, _Mask, _Index, Acc) ->
    list_to_binary(lists:reverse(Acc));
unmask(<<Byte, Rest/binary>>, Mask, Index, Acc) ->
    Key = binary:at(Mask, Index rem 4),
    unmask(Rest, Mask, Index + 1, [Byte bxor Key | Acc]).
