-module(gluegun_runtime_regression_test).

-export([incoming/2, flush_fixture/0, assert_flush/2, with_response/2,
    no_cast/0, monotonic_pair/0, timed_upgrade/3, with_ws_mailbox/1,
    with_connection/2, with_http1_replacement_server/1, release_remainder/1]).

%% Only resource cleanup uses the FFI here; the callback exercises public
%% Gleam operations. Clean up even if an assertion fails midway through.
with_connection(Connection, Callback) ->
    try Callback()
    after {ok, nil} = gluegun_ffi:terminate(Connection)
    end.

%% Gleam callback: fn(Int, ReplacementPeer) -> Result(Nil, GluegunError).
%% The same listener accepts a replacement only after the paused connection
%% has been closed. It never requires the cancelled HTTP/1 stream to recover.
with_http1_replacement_server(Callback) ->
    {ok, Listener} = gen_tcp:listen(0, [binary, {active, false},
        {ip, {127, 0, 0, 1}}, {reuseaddr, true}]),
    {ok, {_, Port}} = inet:sockname(Listener),
    Parent = self(),
    {Server, Monitor} = spawn_monitor(fun() ->
        serve_replacement(Listener, Parent)
    end),
    try
        Result = Callback(Port, {Server, Monitor}),
        case Result of
            {error, _} -> Result;
            {ok, nil} ->
                receive
                    {'DOWN', Monitor, process, Server, normal} -> Result;
                    {'DOWN', Monitor, process, Server, Reason} ->
                        {error, {erlang_error, gleam@string:inspect({replacement_peer_failed, Reason})}}
                after 2000 ->
                    {error, {erlang_error, <<"HTTP/1 replacement peer completion timeout">>}}
                end
        end
    after
        gen_tcp:close(Listener),
        stop_server(Server, Monitor),
        receive {remainder_sent, Server} -> ok after 0 -> ok end
    end.

release_remainder({Server, Monitor}) ->
    Server ! release_remainder,
    receive
        {remainder_sent, Server} -> {ok, nil};
        {'DOWN', Monitor, process, Server, Reason} ->
            {error, {erlang_error, gleam@string:inspect({replacement_peer_failed, Reason})}}
    after 2000 ->
        {error, {erlang_error, <<"HTTP/1 remainder release timeout">>}}
    end.

serve_replacement(Listener, Parent) ->
    {ok, Old} = gen_tcp:accept(Listener, 2000),
    try
        read_headers(Old, <<>>),
        ok = gen_tcp:send(Old, <<"HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nfirst">>),
        receive release_remainder -> ok
        after 2000 -> error(no_remainder_release) end,
        ok = gen_tcp:send(Old, <<"later">>),
        Parent ! {remainder_sent, self()},
        {error, closed} = gen_tcp:recv(Old, 0, 2000)
    after gen_tcp:close(Old)
    end,
    {ok, Replacement} = gen_tcp:accept(Listener, 2000),
    try
        read_headers(Replacement, <<>>),
        ok = gen_tcp:send(Replacement,
            <<"HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\nreplacement">>),
        {error, closed} = gen_tcp:recv(Replacement, 0, 2000)
    after gen_tcp:close(Replacement)
    end.

with_ws_mailbox(Callback) ->
    Conn = self(),
    Stream = make_ref(),
    OtherStream = make_ref(),
    OtherConn = dead_connection(),
    Sentinel = make_ref(),
    self() ! {gun_down, OtherConn, ws, unrelated_down, []},
    self() ! {gun_ws, Conn, OtherStream, {text, <<"other stream">>}},
    self() ! {ws_application_sentinel, Sentinel},
    self() ! {gun_ws, Conn, Stream, {text, <<"selected">>}},
    self() ! {gun_down, Conn, ws, selected_down, []},
    try
        nil = Callback(Conn, Stream),
        receive {gun_down, OtherConn, ws, unrelated_down, []} -> ok
        after 0 -> error(other_connection_consumed) end,
        receive {gun_ws, Conn, OtherStream, {text, <<"other stream">>}} -> ok
        after 0 -> error(other_stream_consumed) end,
        receive {ws_application_sentinel, Sentinel} -> nil
        after 0 -> error(application_message_consumed) end
    after
        gun:flush(Stream),
        gun:flush(OtherStream),
        gun:flush(OtherConn),
        receive {gun_down, Conn, ws, selected_down, []} -> ok after 0 -> ok end,
        receive {ws_application_sentinel, Sentinel} -> ok after 0 -> ok end
    end.

timed_upgrade(Conn, Stream, Timeout) ->
    Start = gluegun_ffi:monotonic_milliseconds(),
    Result = gluegun@websocket:await_upgrade(Conn, Stream, Timeout),
    {Result, gluegun_ffi:monotonic_milliseconds() - Start}.

%% The same malformed payload is decoded through both public boundary paths.
incoming(Kind, Fault) ->
    Conn = self(),
    Stream = make_ref(),
    Headers = case Fault of
        <<"name">> -> [{<<255>>, <<"ok">>}];
        <<"value">> -> [{<<"x-test">>, <<255>>}];
        <<"incomplete">> -> [{<<"x-test">>, <<16#C3>>}];
        <<"shape">> -> [malformed_header];
        <<"term">> -> [{<<"x-test">>, 123}];
        <<"valid">> -> [{<<"X-Test">>, <<"caf", 16#C3, 16#A9>>}]
    end,
    Message = case Kind of
        <<"inform">> -> {gun_inform, Conn, Stream, 103, Headers};
        <<"response">> -> {gun_response, Conn, Stream, fin, 200, Headers};
        <<"trailers">> -> {gun_trailers, Conn, Stream, Headers};
        <<"push">> -> {gun_push, Conn, Stream, make_ref(), <<"GET">>, <<"/">>, Headers};
        <<"upgrade">> -> {gun_upgrade, Conn, Stream, [<<"websocket">>], Headers};
        <<"fin">> -> {gun_data, Conn, Stream, invalid_fin, <<>>};
        <<"data">> -> {gun_data, Conn, Stream, fin, invalid_data};
        <<"frame">> -> {gun_ws, Conn, Stream, {text, <<255>>}};
        <<"frame_shape">> -> {gun_ws, Conn, Stream, {binary, invalid_data}};
        <<"uri">> -> {gun_push, Conn, Stream, make_ref(), <<"GET">>, <<255>>, []};
        <<"method">> -> {gun_push, Conn, Stream, make_ref(), <<255>>, <<"/">>, []};
        <<"protocol">> -> {gun_upgrade, Conn, Stream, [<<255>>], []};
        <<"protocol_shape">> -> {gun_upgrade, Conn, Stream, invalid_protocols, []};
        <<"status">> -> {gun_response, Conn, Stream, fin, <<"200">>, []}
    end,
    self() ! Message,
    {Conn, Stream, Message}.

flush_fixture() ->
    Conn = self(),
    Other = dead_connection(),
    Stream = make_ref(),
    self() ! {gun_push, Conn, Stream, make_ref(), <<"GET">>, <<"/1">>, []},
    self() ! {gun_response, Conn, Stream, fin, 200, []},
    self() ! {gun_push, Other, Stream, make_ref(), <<"GET">>, <<"/other">>, []},
    self() ! {gun_push, Conn, Stream, make_ref(), <<"GET">>, <<"/2">>, []},
    self() ! runtime_application_sentinel,
    self() ! {gun_data, Conn, Stream, fin, <<>>},
    {Conn, Other}.

assert_flush(Conn, Other) ->
    receive {gun_push, Other, _, _, _, <<"/other">>, []} -> ok
    after 0 -> error(other_connection_drained) end,
    receive runtime_application_sentinel -> ok
    after 0 -> error(application_message_drained) end,
    {messages, Messages} = process_info(self(), messages),
    [] = [Message || Message <- Messages, is_tuple(Message),
        tuple_size(Message) >= 2, element(2, Message) =:= Conn],
    {ok, nil}.

dead_connection() ->
    {Pid, Monitor} = spawn_monitor(fun() -> ok end),
    receive {'DOWN', Monitor, process, Pid, normal} -> Pid end.

no_cast() -> not gluegun_outgoing_headers_test:has_outgoing_cast().

monotonic_pair() ->
    {gluegun_ffi:monotonic_milliseconds(), gluegun_ffi:monotonic_milliseconds()}.

%% Raw responses are intentional: Gun accepts legal HTTP obs-text that is not
%% valid UTF-8. Exercise that real wire boundary without an internet service.
with_response(Response, Callback) ->
    {ok, Listener} = gen_tcp:listen(0, [binary, {active, false},
        {ip, {127, 0, 0, 1}}, {reuseaddr, true}]),
    {ok, {_, Port}} = inet:sockname(Listener),
    {Server, Monitor} = spawn_monitor(fun() ->
        {ok, Socket} = gen_tcp:accept(Listener, 2000),
        try
            read_headers(Socket, <<>>),
            ok = gen_tcp:send(Socket, Response),
            receive stop -> ok after 3000 -> ok end
        after gen_tcp:close(Socket)
        end
    end),
    try Callback(Port)
    after
        gen_tcp:close(Listener),
        stop_server(Server, Monitor)
    end.

read_headers(Socket, Acc) when byte_size(Acc) < 16384 ->
    case binary:match(Acc, <<"\r\n\r\n">>) of
        nomatch ->
            {ok, Data} = gen_tcp:recv(Socket, 0, 2000),
            read_headers(Socket, <<Acc/binary, Data/binary>>);
        _ -> Acc
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
