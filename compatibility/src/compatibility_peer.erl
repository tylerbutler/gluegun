-module(compatibility_peer).
-export([with_server/1, with_websocket_server/1]).

%% Gleam: fn(fn(Int) -> Result(Nil, GluegunError)) -> Result(Nil, GluegunError).
%% The callback owns its connection; this fixture owns only listener and peer.
with_server(Callback) ->
    with_peer(Callback, fun serve/1).

%% Same typed callback/result contract as with_server/1. Offer "chat".
%% Each text send gets an echo followed by two coalesced queued text frames:
%% "queued-one", "queued-two". Receiving only the echo with flow 1, then
%% closing, exercises negative-credit teardown through the public Socket API.
with_websocket_server(Callback) ->
    with_peer(Callback, fun serve_websocket/1).

with_peer(Callback, Serve) ->
    try
        {ok, Listener} = gen_tcp:listen(0, [binary, {active, false},
            {packet, http_bin}, {ip, {127, 0, 0, 1}}, {reuseaddr, true}]),
        try
            {ok, {_, Port}} = inet:sockname(Listener),
            {Server, Monitor} = spawn_monitor(fun() -> Serve(Listener) end),
            try
                Result = Callback(Port),
                %% Preserve callback failure over a peer/cleanup failure.
                case Result of
                    {error, _} -> Result;
                    {ok, nil} ->
                        receive
                            {'DOWN', Monitor, process, Server, normal} -> Result;
                            {'DOWN', Monitor, process, Server, PeerReason} ->
                                failure({peer_failed, PeerReason})
                        after 2000 -> failure(peer_completion_timeout)
                        end
                end
            after
                stop_peer(Server, Monitor)
            end
        after gen_tcp:close(Listener)
        end
    catch Class:Reason:Stack ->
        failure({Class, Reason, Stack})
    end.

serve(Listener) ->
    {ok, Socket} = gen_tcp:accept(Listener, 2000),
    try
        request(Socket),
        ok = gen_tcp:send(Socket, <<
            "HTTP/1.1 103 Early Hints\r\nLink: </style.css>\r\n\r\n"
            "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n"
            "Trailer: x-check\r\n\r\n5\r\nhello\r\n0\r\nx-check: done\r\n\r\n">>),
        request(Socket),
        ok = gen_tcp:send(Socket, <<"HTTP/1.1 204 No Content\r\n\r\n">>)
    after gen_tcp:close(Socket)
    end.

request(Socket) ->
    {ok, {http_request, _, _, _}} = gen_tcp:recv(Socket, 0, 2000),
    headers(Socket).

headers(Socket) ->
    case gen_tcp:recv(Socket, 0, 2000) of
        {ok, http_eoh} -> ok;
        {ok, {http_header, _, _, _, _}} -> headers(Socket);
        Other -> error({unexpected_request_headers, Other})
    end.

serve_websocket(Listener) ->
    {ok, Socket} = gen_tcp:accept(Listener, 2000),
    try
        Deadline = erlang:monotonic_time(millisecond) + 5000,
        {ok, {http_request, 'GET', _, {1, 1}}} =
            gen_tcp:recv(Socket, 0, remaining(Deadline)),
        Headers = websocket_headers(Socket, Deadline, []),
        Key = proplists:get_value(<<"sec-websocket-key">>, Headers),
        true = is_binary(Key),
        Offered = proplists:get_value(<<"sec-websocket-protocol">>, Headers, <<>>),
        true = lists:member(<<"chat">>,
            [string:trim(Token) || Token <- binary:split(Offered, <<",">>, [global])]),
        Accept = cow_ws:encode_key(Key),
        ok = gen_tcp:send(Socket, [
            <<"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n"
                "Connection: Upgrade\r\nSec-WebSocket-Protocol: chat\r\n"
                "X-Handshake: yes\r\nSec-WebSocket-Accept: ">>,
            Accept, <<"\r\n\r\n">>]),
        ok = inet:setopts(Socket, [{packet, raw}]),
        websocket_frames(Socket, Deadline)
    after gen_tcp:close(Socket)
    end.

websocket_headers(Socket, Deadline, Acc) ->
    case gen_tcp:recv(Socket, 0, remaining(Deadline)) of
        {ok, http_eoh} -> Acc;
        {ok, {http_header, _, Name, _, Value}} ->
            Binary = case Name of
                Atom when is_atom(Atom) -> atom_to_binary(Atom, latin1);
                _ -> Name
            end,
            websocket_headers(Socket, Deadline, [{string:lowercase(Binary), Value} | Acc]);
        Other -> error({unexpected_upgrade_headers, Other})
    end.

websocket_frames(Socket, Deadline) ->
    %% Compatibility consumer frames are short, final, uncompressed, masked.
    {ok, <<1:1, 0:3, Opcode:4, 1:1, Length:7>>} =
        gen_tcp:recv(Socket, 2, remaining(Deadline)),
    true = Length < 126,
    {ok, <<Mask:4/binary, Masked:Length/binary>>} =
        gen_tcp:recv(Socket, 4 + Length, remaining(Deadline)),
    Payload = unmask(Masked, Mask, 0, <<>>),
    case Opcode of
        1 ->
            ok = gen_tcp:send(Socket, [
                server_frame(1, Payload),
                server_frame(1, <<"queued-one">>),
                server_frame(1, <<"queued-two">>)]),
            websocket_frames(Socket, Deadline);
        8 ->
            ok = gen_tcp:send(Socket, server_frame(8, <<1000:16, "bye">>)),
            await_websocket_closed(Socket, Deadline);
        9 ->
            ok = gen_tcp:send(Socket, server_frame(10, Payload)),
            websocket_frames(Socket, Deadline);
        _ -> error({unexpected_client_opcode, Opcode})
    end.

unmask(<<>>, _, _, Acc) -> Acc;
unmask(<<Byte, Rest/binary>>, Mask, Index, Acc) ->
    Key = binary:at(Mask, Index rem 4),
    unmask(Rest, Mask, Index + 1, <<Acc/binary, (Byte bxor Key)>>).

server_frame(Opcode, Payload) when byte_size(Payload) < 126 ->
    <<1:1, 0:3, Opcode:4, 0:1, (byte_size(Payload)):7, Payload/binary>>.

await_websocket_closed(Socket, Deadline) ->
    case gen_tcp:recv(Socket, 0, remaining(Deadline)) of
        {error, closed} -> ok;
        {ok, _} -> await_websocket_closed(Socket, Deadline);
        Other -> error({websocket_not_released, Other})
    end.

remaining(Deadline) ->
    case Deadline - erlang:monotonic_time(millisecond) of
        Left when Left > 0 -> Left;
        _ -> error(websocket_peer_deadline)
    end.

failure(Reason) -> {error, {erlang_error, gleam@string:inspect(Reason)}}.

stop_peer(Server, Monitor) ->
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
