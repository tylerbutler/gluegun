-module(gluegun_ws_control_test).
-export([with_echo_connection/1]).

%% A loopback peer for control-frame tests. No external server or fixed port.
with_echo_connection(Callback) ->
    {ok, Listen} = gen_tcp:listen(0, [binary, {active, false}, {packet, raw},
        {ip, {127, 0, 0, 1}}]),
    {ok, {_, Port}} = inet:sockname(Listen),
    {Server, Monitor} = spawn_monitor(fun() -> serve(Listen) end),
    try
        {ok, Conn} = gun:open("127.0.0.1", Port,
            #{transport => tcp, protocols => [http], retry => 0}),
        try
            {ok, http} = gun:await_up(Conn, 5000),
            Stream = gun:ws_upgrade(Conn, <<"/ws">>, [],
                #{silence_pings => false}),
            {upgrade, [<<"websocket">>], _} = gun:await(Conn, Stream, 5000),
            Callback(Conn, Stream)
        after
            gun:close(Conn)
        end
    after
        gen_tcp:close(Listen),
        stop_server(Server, Monitor)
    end.

stop_server(Server, Monitor) ->
    receive
        {'DOWN', Monitor, process, Server, normal} -> ok;
        {'DOWN', Monitor, process, Server, Reason} -> error({echo_server_failed, Reason})
    after 1000 ->
        exit(Server, shutdown),
        receive
            {'DOWN', Monitor, process, Server, shutdown} -> ok;
            {'DOWN', Monitor, process, Server, Reason} -> error({echo_server_failed, Reason})
        after 1000 ->
            error(echo_server_did_not_stop)
        end
    end.

serve(Listen) ->
    {ok, Socket} = gen_tcp:accept(Listen, 5000),
    try
        handshake(Socket),
        echo_frames(Socket)
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
    case gen_tcp:recv(Socket, 2, 5000) of
        {error, closed} -> ok;
        {ok, <<1:1, 0:3, Opcode:4, 1:1, Length:7>>} when Length =< 125 ->
            {ok, <<Mask:4/binary, Masked:Length/binary>>} =
                gen_tcp:recv(Socket, Length + 4, 5000),
            Payload = unmask(Masked, Mask, 0, []),
            ReplyOpcode = case Opcode of 9 -> 10; _ -> Opcode end,
            ok = gen_tcp:send(Socket, <<1:1, 0:3, ReplyOpcode:4, 0:1,
                Length:7, Payload/binary>>),
            case Opcode of
                8 -> ok;
                _ -> echo_frames(Socket)
            end;
        Other -> error({invalid_client_frame, Other})
    end.

unmask(<<>>, _Mask, _Index, Acc) ->
    list_to_binary(lists:reverse(Acc));
unmask(<<Byte, Rest/binary>>, Mask, Index, Acc) ->
    Key = binary:at(Mask, Index rem 4),
    unmask(Rest, Mask, Index + 1, [Byte bxor Key | Acc]).
