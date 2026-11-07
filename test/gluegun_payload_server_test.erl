-module(gluegun_payload_server_test).

-export([with_server/2, with_connection/2, await_http/1, release_pending/1, await_frame/1]).

-define(TIMEOUT, 5000).

with_server(WebSocket, Callback) ->
    {ok, Listener} = gen_tcp:listen(0, [
        binary, {active, false}, {packet, http_bin},
        {ip, {127, 0, 0, 1}}, {reuseaddr, true}
    ]),
    {ok, {_, Port}} = inet:sockname(Listener),
    Owner = self(),
    {Server, Monitor} = spawn_monitor(fun() ->
        {ok, Socket} = gen_tcp:accept(Listener, ?TIMEOUT),
        try
            case WebSocket of
                false -> http_loop(Socket, Owner);
                true -> websocket_upgrade(Socket, Owner)
            end
        after
            gen_tcp:close(Socket)
        end
    end),
    try
        Callback({Server, Monitor}, Port)
    after
        gen_tcp:close(Listener),
        exit(Server, kill),
        receive
            {'DOWN', Monitor, process, Server, _} -> ok
        after ?TIMEOUT ->
            erlang:error(server_cleanup_timeout)
        end,
        drain_observations(Server)
    end.

with_connection(Connection, Callback) ->
    Monitor = monitor(process, Connection),
    try
        {ok, http1} = gluegun_ffi:await_up(Connection, {milliseconds, ?TIMEOUT}),
        Callback()
    after
        gun:close(Connection),
        receive
            {'DOWN', Monitor, process, Connection, _} -> ok
        after ?TIMEOUT ->
            exit(Connection, kill),
            receive
                {'DOWN', Monitor, process, Connection, _} -> ok
            after ?TIMEOUT ->
                erlang:error(connection_cleanup_timeout)
            end,
            erlang:error(connection_close_timeout)
        end,
        gun:flush(Connection)
    end.

await_http(Server) -> await_observation(Server, http).
await_frame(Server) -> await_observation(Server, frame).

await_observation({Server, Monitor}, Kind) ->
    receive
        {payload_server, Server, Kind, Value} -> {ok, Value};
        {'DOWN', Monitor, process, Server, Reason} ->
            %% Leave DOWN available for fixture cleanup.
            self() ! {'DOWN', Monitor, process, Server, Reason},
            {error, iolist_to_binary(io_lib:format("server stopped: ~p", [Reason]))}
    after ?TIMEOUT ->
        {error, <<"server observation timeout">>}
    end.

release_pending({Server, _}) ->
    Server ! release_pending,
    nil.

drain_observations(Server) ->
    receive
        {payload_server, Server, _, _} -> drain_observations(Server)
    after 0 ->
        ok
    end.

http_loop(Socket, Owner) ->
    case gen_tcp:recv(Socket, 0, ?TIMEOUT) of
        {ok, {http_request, 'POST', {abs_path, Path}, {1, 1}}} ->
            Headers = headers(Socket, []),
            ok = inet:setopts(Socket, [{packet, raw}]),
            Body = body(Socket, Headers),
            Owner ! {payload_server, self(), http, {Path, Body}},
            case Path of
                <<"/pending">> ->
                    receive release_pending -> ok
                    after ?TIMEOUT -> erlang:error(pending_response_timeout)
                    end;
                _ -> ok
            end,
            ok = gen_tcp:send(Socket, [
                <<"HTTP/1.1 200 OK\r\nContent-Length: ">>,
                integer_to_binary(byte_size(Body)), <<"\r\n\r\n">>, Body
            ]),
            ok = inet:setopts(Socket, [{packet, http_bin}]),
            http_loop(Socket, Owner);
        {error, closed} -> ok;
        Other -> erlang:error({unexpected_http_request, Other})
    end.

headers(Socket, Acc) ->
    case gen_tcp:recv(Socket, 0, ?TIMEOUT) of
        {ok, {http_header, _, Name, _, Value}} ->
            Lower = string:lowercase(
                case Name of
                    Atom when is_atom(Atom) -> atom_to_binary(Atom, latin1);
                    Binary when is_binary(Binary) -> Binary
                end
            ),
            headers(Socket, [{Lower, Value} | Acc]);
        {ok, http_eoh} -> Acc;
        Other -> erlang:error({unexpected_http_header, Other})
    end.

body(Socket, Headers) ->
    case proplists:get_value(<<"transfer-encoding">>, Headers) of
        <<"chunked">> -> chunks(Socket, []);
        undefined ->
            Length = binary_to_integer(
                proplists:get_value(<<"content-length">>, Headers, <<"0">>)
            ),
            bytes(Socket, Length)
    end.

bytes(_, 0) -> <<>>;
bytes(Socket, Length) ->
    {ok, Data} = gen_tcp:recv(Socket, Length, ?TIMEOUT),
    Data.

chunks(Socket, Acc) ->
    ok = inet:setopts(Socket, [{packet, line}]),
    {ok, Line} = gen_tcp:recv(Socket, 0, ?TIMEOUT),
    [Size, <<>>] = binary:split(Line, <<"\r\n">>),
    Length = binary_to_integer(Size, 16),
    ok = inet:setopts(Socket, [{packet, raw}]),
    case Length of
        0 ->
            <<"\r\n">> = bytes(Socket, 2),
            iolist_to_binary(lists:reverse(Acc));
        _ ->
            Data = bytes(Socket, Length),
            <<"\r\n">> = bytes(Socket, 2),
            chunks(Socket, [Data | Acc])
    end.

websocket_upgrade(Socket, Owner) ->
    {ok, {http_request, 'GET', {abs_path, <<"/ws">>}, {1, 1}}} =
        gen_tcp:recv(Socket, 0, ?TIMEOUT),
    Headers = headers(Socket, []),
    Key = proplists:get_value(<<"sec-websocket-key">>, Headers),
    Accept = cow_ws:encode_key(Key),
    ok = gen_tcp:send(Socket, [
        <<"HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\n"
          "Upgrade: websocket\r\nSec-WebSocket-Accept: ">>,
        Accept, <<"\r\n\r\n">>
    ]),
    ok = inet:setopts(Socket, [{packet, raw}]),
    websocket_loop(Socket, Owner, <<>>).

websocket_loop(Socket, Owner, Buffer) ->
    case cow_ws:parse_header(Buffer, #{}, undefined) of
        more ->
            case gen_tcp:recv(Socket, 0, ?TIMEOUT) of
                {ok, Data} ->
                    websocket_loop(Socket, Owner, <<Buffer/binary, Data/binary>>);
                {error, closed} -> ok;
                Other -> erlang:error({websocket_receive_failed, Other})
            end;
        {Type, undefined, Rsv, Length, Mask, Rest} when is_integer(Mask) ->
            {Payload, Tail} = frame_payload(Socket, Rest, Length),
            case cow_ws:parse_payload(Payload, Mask, 0, 0, Type, Length,
                    undefined, #{}, Rsv) of
                {ok, Data, _, <<>>} ->
                    Owner ! {payload_server, self(), frame, {Type, Data}},
                    case Type of
                        binary -> ok = gen_tcp:send(Socket, cow_ws:frame({binary, Data}, #{}));
                        text -> ok = gen_tcp:send(Socket, cow_ws:frame({text, Data}, #{}));
                        ping -> ok = gen_tcp:send(Socket, cow_ws:frame({pong, Data}, #{}));
                        pong -> ok
                    end,
                    websocket_loop(Socket, Owner, Tail);
                {ok, Code, Reason, _, <<>>} when Type =:= close ->
                    Owner ! {payload_server, self(), frame, {close_with_reason, Code, Reason}},
                    ok = gen_tcp:send(Socket, cow_ws:frame({close, Code, Reason}, #{}));
                Other -> erlang:error({unexpected_websocket_payload, Other})
            end;
        Other -> erlang:error({unexpected_websocket_header, Other})
    end.

frame_payload(Socket, Buffer, Length) when byte_size(Buffer) < Length ->
    Remaining = bytes(Socket, Length - byte_size(Buffer)),
    {<<Buffer/binary, Remaining/binary>>, <<>>};
frame_payload(_, Buffer, Length) ->
    <<Payload:Length/binary, Tail/binary>> = Buffer,
    {Payload, Tail}.
