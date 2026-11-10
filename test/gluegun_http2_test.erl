-module(gluegun_http2_test).
-include_lib("public_key/include/public_key.hrl").

-export([run/3, with_tls_cancel_server/1]).

%% Gleam callback: fn(Int, List(BitArray)) -> Result(Nil, GluegunError).
%% A successful second response is gated on observing CANCEL on the first
%% stream, and both requests must arrive on this one TLS connection.
with_tls_cancel_server(Callback) ->
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
    {Server, Monitor} = spawn_monitor(fun() -> serve_tls_cancel(Listener) end),
    try
        Result = Callback(Port, proplists:get_value(cacerts, Certificate)),
        case Result of
            {error, _} -> Result;
            {ok, nil} ->
                receive
                    {'DOWN', Monitor, process, Server, normal} -> Result;
                    {'DOWN', Monitor, process, Server, Reason} ->
                        {error, {erlang_error, gleam@string:inspect({tls_peer_failed, Reason})}}
                after 2000 ->
                    {error, {erlang_error, <<"HTTP/2 TLS peer completion timeout">>}}
                end
        end
    after
        ssl:close(Listener),
        stop_tls_peer(Server, Monitor)
    end.

serve_tls_cancel(Listener) ->
    {ok, Transport} = ssl:transport_accept(Listener, 2000),
    {ok, Socket} = ssl:handshake(Transport, 2000),
    try
        Deadline = erlang:monotonic_time(millisecond) + 5000,
        {ok, <<"h2">>} = ssl:negotiated_protocol(Socket),
        {ok, <<"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n">>} =
            ssl:recv(Socket, 24, tls_remaining(Deadline)),
        ok = ssl:send(Socket, cow_http2:settings(#{})),
        {First, Rest0} = tls_request(Socket, <<>>, Deadline),
        {Headers, _} = cow_hpack:encode([{<<":status">>, <<"200">>}]),
        ok = ssl:send(Socket, [
            cow_http2:headers(First, nofin, Headers),
            cow_http2:data(First, nofin, <<"paused">>)]),
        Rest1 = tls_cancel(Socket, Rest0, First, Deadline),
        {Second, Rest2} = tls_request(Socket, Rest1, Deadline),
        true = Second > First,
        ok = ssl:send(Socket, [
            cow_http2:headers(Second, nofin, Headers),
            cow_http2:data(Second, fin, <<"reused">>)]),
        tls_wait_closed(Socket, Rest2, Deadline)
    after ssl:close(Socket)
    end.

tls_request(Socket, Buffer, Deadline) ->
    {Frame, Rest} = tls_next_frame(Socket, Buffer, Deadline),
    case Frame of
        {headers, StreamID, fin, head_fin, _} -> {StreamID, Rest};
        {settings, _} ->
            ok = ssl:send(Socket, cow_http2:settings_ack()),
            tls_request(Socket, Rest, Deadline);
        settings_ack -> tls_request(Socket, Rest, Deadline);
        {window_update, _} -> tls_request(Socket, Rest, Deadline);
        {window_update, _, _} -> tls_request(Socket, Rest, Deadline);
        Other -> error({unexpected_tls_request_frame, Other})
    end.

tls_cancel(Socket, Buffer, StreamID, Deadline) ->
    {Frame, Rest} = tls_next_frame(Socket, Buffer, Deadline),
    case Frame of
        %% cow_http2 maps exactly wire error code 0x8 to the atom cancel.
        {rst_stream, StreamID, cancel} -> Rest;
        {settings, _} ->
            ok = ssl:send(Socket, cow_http2:settings_ack()),
            tls_cancel(Socket, Rest, StreamID, Deadline);
        settings_ack -> tls_cancel(Socket, Rest, StreamID, Deadline);
        {window_update, _} -> tls_cancel(Socket, Rest, StreamID, Deadline);
        {window_update, _, _} -> tls_cancel(Socket, Rest, StreamID, Deadline);
        Other -> error({expected_cancel_before_reuse, StreamID, Other})
    end.

tls_next_frame(Socket, Buffer, Deadline) ->
    case cow_http2:parse(Buffer) of
        {ok, Frame, Rest} -> {Frame, Rest};
        more ->
            {ok, Data} = ssl:recv(Socket, 0, tls_remaining(Deadline)),
            tls_next_frame(Socket, <<Buffer/binary, Data/binary>>, Deadline);
        Other -> error({invalid_tls_http2_frame, Other})
    end.

tls_wait_closed(Socket, Buffer, Deadline) ->
    case cow_http2:parse(Buffer) of
        {ok, _, Rest} -> tls_wait_closed(Socket, Rest, Deadline);
        more ->
            case ssl:recv(Socket, 0, tls_remaining(Deadline)) of
                {error, closed} -> ok;
                {ok, Data} -> tls_wait_closed(Socket, <<Buffer/binary, Data/binary>>, Deadline);
                Other -> error({tls_connection_not_released, Other})
            end;
        Other -> error({invalid_tls_shutdown_frame, Other})
    end.

tls_remaining(Deadline) ->
    case Deadline - erlang:monotonic_time(millisecond) of
        Left when Left > 0 -> Left;
        _ -> error(tls_peer_deadline)
    end.

stop_tls_peer(Server, Monitor) ->
    try
        case is_process_alive(Server) of
            false -> ok;
            true ->
                exit(Server, kill),
                receive {'DOWN', Monitor, process, Server, _} -> ok
                after 1000 -> error(tls_peer_cleanup_timeout)
                end
        end
    after erlang:demonitor(Monitor, [flush])
    end.

run(Mode, ConnectOptions, RequestOptions) ->
    try
        {ok, Listener} = gen_tcp:listen(0,
            [inet, binary, {active, false}, {ip, {127,0,0,1}}, {reuseaddr, true}]),
        {ok, {_, Port}} = inet:sockname(Listener),
        Parent = self(),
        {Server, Monitor} = spawn_monitor(fun() -> serve(Listener, Parent, Mode) end),
        try
            {ok, Conn} = gluegun_ffi:open(<<"localhost">>, Port, ConnectOptions),
            try
                {ok, http2} = gluegun_ffi:await_up(Conn, {milliseconds, 1000}),
                {ok, Stream} = gluegun_ffi:request(Conn, <<"GET">>, <<"/">>,
                    [], <<>>, RequestOptions),
                await_response(Mode, Conn, Stream),
                consume(Mode, Conn, Stream, Server)
            after
                {ok, nil} = gluegun_ffi:terminate(Conn)
            end,
            receive
                {peer_closed, Server} -> ok;
                {'DOWN', Monitor, process, Server, PeerReason} ->
                    error({peer_failed, PeerReason})
            after 1000 -> error(peer_not_closed)
            end,
            {messages, Messages} = process_info(self(), messages),
            [] = [Message || Message <- Messages, is_tuple(Message),
                tuple_size(Message) >= 2, element(2, Message) =:= Conn],
            {ok, nil}
        after
            gen_tcp:close(Listener),
            exit(Server, kill),
            receive {'DOWN', Monitor, process, Server, _} -> ok after 1000 -> ok end
        end
    catch Class:Reason:Stack ->
        {error, {erlang_error, gleam@string:inspect({Class, Reason, Stack})}}
    end.

await_response(<<"cleanup">>, Conn, Stream) ->
    receive
        {gun_response, Conn, Stream, nofin, 200, _} -> ok
    after 1000 -> error(no_response_headers)
    end;
await_response(_Mode, Conn, Stream) ->
    {ok, {response, no_fin, 200, _}} =
        gluegun_ffi:await(Conn, Stream, {milliseconds, 1000}).

consume(<<"flow">>, Conn, Stream, Server) ->
    Window = receive
        {initial_window, Server, Size} -> Size
    after 1000 -> error(no_initial_window)
    end,
    Messages = drain_window(Conn, Stream, Window, 0),
    %% Frames already inside the byte window can arrive after message credit
    %% runs out. Test the actual stream WINDOW_UPDATE barrier, not queue size.
    true = Messages > 1,
    {error, timeout} = gluegun_ffi:await(Conn, Stream, {milliseconds, 50}),
    receive
        {stream_update, Server, _} -> error(premature_stream_update)
    after 50 -> ok
    end,
    {ok, nil} = gluegun_ffi:update_flow(Conn, Stream, Messages),
    receive
        {stream_update, Server, Increment} -> true = Increment >= 32
    after 1000 -> error(no_stream_update)
    end,
    {ok, {data, fin, Final}} = gluegun_ffi:await(Conn, Stream, {milliseconds, 1000}),
    Final = binary:copy(<<"y">>, 32);
consume(<<"limit">>, Conn, Stream, _Server) ->
    {ok, {data, no_fin, First}} = gluegun_ffi:await(Conn, Stream, {milliseconds, 1000}),
    32 = byte_size(First),
    {ok, {data, fin, Final}} = gluegun_ffi:await(Conn, Stream, {milliseconds, 1000}),
    true = byte_size(First) + byte_size(Final) > 64,
    {ok, nil} = gluegun_ffi:cancel(Conn, Stream);
consume(<<"cleanup">>, Conn, Stream, _Server) ->
    %% Leave the preceding real PUSH_PROMISE queued while selecting the
    %% parent's DATA. Both signals come from Gun, so receipt proves ordering.
    receive
        {gun_data, Conn, Stream, fin, <<"done">>} -> ok
    after 1000 -> error({no_parent_data, process_info(self(), messages)})
    end,
    {messages, Messages} = process_info(self(), messages),
    [{gun_push, Conn, Stream, _, <<"GET">>, <<"http://localhost/pushed">>, _}] =
        [Message || Message = {gun_push, Pid, _, _, _, _, _} <- Messages,
            Pid =:= Conn].

drain_window(_Conn, _Stream, 0, Messages) -> Messages;
drain_window(Conn, Stream, Remaining, Messages) ->
    {ok, {data, no_fin, Data}} = gluegun_ffi:await(Conn, Stream, {milliseconds, 1000}),
    Size = byte_size(Data),
    true = Size > 0 andalso Size =< Remaining,
    Data = binary:copy(<<"x">>, Size),
    drain_window(Conn, Stream, Remaining - Size, Messages + 1).

serve(Listener, Parent, Mode) ->
    {ok, Socket} = gen_tcp:accept(Listener, 1000),
    try
        {ok, <<"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n">>} = gen_tcp:recv(Socket, 24, 1000),
        ok = gen_tcp:send(Socket, cow_http2:settings(#{})),
        {StreamID, StreamWindow, Rest} = request_headers(Socket, <<>>, 65535, 65535),
        {Headers, _Encoder} = cow_hpack:encode([{<<":status">>, <<"200">>}]),
        case Mode of
            <<"cleanup">> -> ok;
            _ -> ok = gen_tcp:send(Socket, cow_http2:headers(StreamID, nofin, Headers))
        end,
        case Mode of
            <<"flow">> ->
                Parent ! {initial_window, self(), StreamWindow},
                ok = gen_tcp:send(Socket, window_frames(StreamID, StreamWindow)),
                {Increment, Buffered} = stream_update(Socket, Rest, StreamID),
                Parent ! {stream_update, self(), Increment},
                ok = gen_tcp:send(Socket,
                    cow_http2:data(StreamID, fin, binary:copy(<<"y">>, 32))),
                wait_closed(Socket, Buffered);
            <<"limit">> ->
                %% One write can deliver multiple DATA frames despite credit 1.
                ok = gen_tcp:send(Socket, [
                    cow_http2:data(StreamID, nofin, binary:copy(<<"x">>, 32)),
                    cow_http2:data(StreamID, fin, binary:copy(<<"x">>, 48))
                ]),
                wait_closed(Socket, Rest);
            <<"cleanup">> ->
                {PushHeaders, _} = cow_hpack:encode([
                    {<<":method">>, <<"GET">>}, {<<":scheme">>, <<"http">>},
                    {<<":authority">>, <<"localhost">>}, {<<":path">>, <<"/pushed">>}
                ]),
                ok = gen_tcp:send(Socket, [
                    cow_http2:push_promise(StreamID, 2, PushHeaders),
                    cow_http2:headers(StreamID, nofin, Headers),
                    cow_http2:data(StreamID, fin, <<"done">>)
                ]),
                wait_closed(Socket, Rest)
        end,
        Parent ! {peer_closed, self()}
    after
        gen_tcp:close(Socket)
    end.

request_headers(Socket, Buffer, StreamWindow, ConnectionWindow) ->
    {Frame, Rest} = next_frame(Socket, Buffer),
    case Frame of
        {settings, Settings} ->
            ok = gen_tcp:send(Socket, cow_http2:settings_ack()),
            request_headers(Socket, Rest,
                maps:get(initial_window_size, Settings, StreamWindow), ConnectionWindow);
        {window_update, Increment} ->
            request_headers(Socket, Rest, StreamWindow, ConnectionWindow + Increment);
        {headers, StreamID, fin, head_fin, _Block} ->
            true = ConnectionWindow >= StreamWindow,
            {StreamID, StreamWindow, Rest};
        settings_ack -> request_headers(Socket, Rest, StreamWindow, ConnectionWindow);
        Other -> error({unexpected_request_frame, Other})
    end.

window_frames(_StreamID, 0) -> [];
window_frames(StreamID, Remaining) ->
    Size = min(Remaining, 16384),
    [cow_http2:data(StreamID, nofin, binary:copy(<<"x">>, Size))
        | window_frames(StreamID, Remaining - Size)].

stream_update(Socket, Buffer, StreamID) ->
    {Frame, Rest} = next_frame(Socket, Buffer),
    case Frame of
        {window_update, StreamID, Increment} -> {Increment, Rest};
        {window_update, _Increment} -> stream_update(Socket, Rest, StreamID);
        settings_ack -> stream_update(Socket, Rest, StreamID);
        Other -> error({unexpected_window_frame, Other})
    end.

next_frame(Socket, Buffer) ->
    case cow_http2:parse(Buffer) of
        {ok, Frame, Rest} -> {Frame, Rest};
        more ->
            {ok, Data} = gen_tcp:recv(Socket, 0, 2000),
            next_frame(Socket, <<Buffer/binary, Data/binary>>);
        Other -> error({invalid_http2_frame, Other})
    end.

wait_closed(Socket, Buffer) ->
    case cow_http2:parse(Buffer) of
        {ok, _Frame, Rest} -> wait_closed(Socket, Rest);
        more ->
            case gen_tcp:recv(Socket, 0, 2000) of
                {error, closed} -> ok;
                {ok, Data} -> wait_closed(Socket, <<Buffer/binary, Data/binary>>);
                Other -> error({peer_close_failed, Other})
            end;
        Other -> error({invalid_shutdown_frame, Other})
    end.
