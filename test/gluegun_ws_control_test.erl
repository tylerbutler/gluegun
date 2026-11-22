-module(gluegun_ws_control_test).
-export([with_echo_connection/1, with_incoming_controls/3,
    with_incoming_controls_default/2, start_idle_peer/0, await_ping/2,
    stop_idle_peer/1, with_keepalive_peer/1]).

%% Gleam: () -> #(process.Pid, Int).
%% The peer owns both sockets; the caller must stop it (or use with_keepalive_peer).
start_idle_peer() ->
    Owner = self(),
    Ready = make_ref(),
    {Peer, Monitor} = spawn_monitor(fun() ->
        OwnerMonitor = erlang:monitor(process, Owner),
        {ok, Listen} = gen_tcp:listen(0, [binary, {active, false}, {packet, raw},
            {ip, {127, 0, 0, 1}}, {send_timeout, 1000}, {send_timeout_close, true}]),
        try
            {ok, {_, Port}} = inet:sockname(Listen),
            Owner ! {Ready, self(), Port},
            {ok, Socket} = gen_tcp:accept(Listen, 5000),
            try
                handshake(Socket),
                ok = inet:setopts(Socket, [{active, once}]),
                idle_frames(Socket, Owner, OwnerMonitor, <<>>, false, deadline())
            after
                gen_tcp:close(Socket)
            end
        after
            gen_tcp:close(Listen)
        end
    end),
    receive
        {Ready, Peer, Port} ->
            erlang:demonitor(Monitor, [flush]),
            {Peer, Port};
        {'DOWN', Monitor, process, Peer, Reason} ->
            error({idle_peer_start_failed, Reason})
    after 5000 ->
        stop_idle_peer(Peer),
        erlang:demonitor(Monitor, [flush]),
        receive {Ready, Peer, _} -> ok after 0 -> ok end,
        error(idle_peer_start_timeout)
    end.

%% Gleam: (process.Pid, Int) -> Result(Bool, GluegunError).
%% Observe the first ping ONCE, including a ping received before this call.
%% Only that first notification is queued, so a fast timer cannot flood mail.
await_ping(Peer, Milliseconds)
    when is_pid(Peer), is_integer(Milliseconds), Milliseconds >= 0,
         Milliseconds =< 4294967295 ->
    Monitor = erlang:monitor(process, Peer),
    try
        receive
            {idle_peer_ping, Peer} -> {ok, true};
            {'DOWN', Monitor, process, Peer, Reason} ->
                {error, {erlang_error, iolist_to_binary(
                    io_lib:format("idle WebSocket peer stopped: ~p", [Reason]))}}
        after Milliseconds ->
            {ok, false}
        end
    after
        erlang:demonitor(Monitor, [flush])
    end.

%% Gleam: (process.Pid) -> Nil. Safe even if no connection was established.
stop_idle_peer(Peer) ->
    Monitor = erlang:monitor(process, Peer),
    Peer ! stop,
    try
        receive
            {'DOWN', Monitor, process, Peer, _} -> ok
        after 100 ->
            %% Interrupt a bounded accept/handshake, closing owned sockets.
            exit(Peer, kill),
            receive
                {'DOWN', Monitor, process, Peer, _} -> ok
            after 1000 ->
                error(idle_peer_did_not_stop)
            end
        end
    after
        erlang:demonitor(Monitor, [flush])
    end,
    receive {idle_peer_ping, Peer} -> ok after 0 -> ok end,
    nil.

%% Gleam: (fn(Int, process.Pid) -> Result(Nil, GluegunError))
%%     -> Result(Nil, GluegunError).
with_keepalive_peer(Callback) ->
    {Peer, Port} = start_idle_peer(),
    try Callback(Port, Peer)
    after stop_idle_peer(Peer)
    end.

%% Only client control frames are expected. Active-once reads permit stop and
%% owner-DOWN handling even while idle, without losing partial TCP frames.
%% A single absolute deadline bounds the entire fixture, not each read.
idle_frames(Socket, Owner, OwnerMonitor, Buffer, SeenPing, Deadline) ->
    case remaining(Deadline) of
        0 -> error(idle_peer_deadline);
        Wait ->
            idle_frames_wait(Socket, Owner, OwnerMonitor, Buffer, SeenPing, Deadline, Wait)
    end.

idle_frames_wait(Socket, Owner, OwnerMonitor, Buffer, SeenPing, Deadline, Wait) ->
    receive
        {tcp, Socket, Bytes} ->
            case idle_frame_buffer(Socket, Owner, <<Buffer/binary, Bytes/binary>>, SeenPing) of
                closed -> ok;
                {Rest, Seen} ->
                    ok = inet:setopts(Socket, [{active, once}]),
                    idle_frames(Socket, Owner, OwnerMonitor, Rest, Seen, Deadline)
            end;
        {tcp_closed, Socket} -> ok;
        {tcp_error, Socket, Reason} -> error({idle_peer_socket_error, Reason});
        {'DOWN', OwnerMonitor, process, Owner, _} -> ok;
        stop -> ok
    after Wait ->
        error(idle_peer_deadline)
    end.

idle_frame_buffer(_Socket, _Owner, Buffer, Seen) when byte_size(Buffer) < 2 ->
    {Buffer, Seen};
idle_frame_buffer(Socket, Owner,
    <<1:1, 0:3, Opcode:4, 1:1, Length:7, Rest/binary>> = Buffer, Seen)
    when Length =< 125, (Opcode =:= 8 orelse Opcode =:= 9 orelse Opcode =:= 10) ->
    case Rest of
        <<Mask:4/binary, Masked:Length/binary, Tail/binary>> ->
            Payload = unmask(Masked, Mask, 0, []),
            case Opcode of
                8 ->
                    ok = gen_tcp:send(Socket, server_frame(8, Payload)),
                    closed;
                9 ->
                    ok = gen_tcp:send(Socket, server_frame(10, Payload)),
                    case Seen of
                        false -> Owner ! {idle_peer_ping, self()};
                        true -> ok
                    end,
                    idle_frame_buffer(Socket, Owner, Tail, true);
                10 ->
                    idle_frame_buffer(Socket, Owner, Tail, Seen)
            end;
        _ -> {Buffer, Seen}
    end;
idle_frame_buffer(_Socket, _Owner, _Buffer, _Seen) ->
    error(idle_peer_invalid_control_frame).

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
    Deadline = deadline(),
    ok = inet:setopts(Socket, [{packet, http_bin}]),
    {ok, {http_request, 'GET', _, _}} = recv_handshake(Socket, Deadline),
    Key = handshake_headers(Socket, undefined, Deadline),
    true = is_binary(Key),
    Accept = base64:encode(crypto:hash(sha,
        <<Key/binary, "258EAFA5-E914-47DA-95CA-C5AB0DC85B11">>)),
    ok = gen_tcp:send(Socket, [
        <<"HTTP/1.1 101 Switching Protocols\r\n",
          "Upgrade: websocket\r\nConnection: Upgrade\r\n",
          "Sec-WebSocket-Accept: ">>, Accept, <<"\r\n\r\n">>
    ]),
    ok = inet:setopts(Socket, [{packet, raw}]).

handshake_headers(Socket, Key, Deadline) ->
    case recv_handshake(Socket, Deadline) of
        {ok, http_eoh} -> Key;
        {ok, {http_header, _, Name, _, Value}} ->
            case string:lowercase(header_name(Name)) of
                <<"sec-websocket-key">> -> handshake_headers(Socket, Value, Deadline);
                _ -> handshake_headers(Socket, Key, Deadline)
            end;
        Other -> error({invalid_handshake, Other})
    end.

recv_handshake(Socket, Deadline) ->
    case remaining(Deadline) of
        0 -> {error, timeout};
        Timeout -> gen_tcp:recv(Socket, 0, Timeout)
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
