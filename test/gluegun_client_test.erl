-module(gluegun_client_test).

-export([failure_cleanup/3, no_cleanup/1, delayed_response/1, local_failure/1,
    late_after_drain/0, push_cleanup/1, malformed_push_cleanup/0]).

failure_cleanup(Messages, Expected, InvalidConnection) ->
    check(fun() ->
        Stream = make_ref(),
        Other = make_ref(),
        Children = [make_ref(), make_ref(), make_ref()],
        [First, Second, Nested] = Children,
        Conn = case InvalidConnection of
            true -> <<"not-a-pid">>;
            false -> self()
        end,
        Next = make_ref(),
        Request = fun(_, _, _, _, _, _) ->
            lists:foreach(fun(Message) -> self() ! {Next, Message} end, Messages),
            self() ! {gun_data, self(), Stream, fin, <<"discard">>},
            queue_push(Stream, First),
            %% Cover both Gun's emitted shape and the historical flush shape.
            self() ! {gun_push, self(), Stream, Second, <<"GET">>, <<"/">>, <<"/push">>, []},
            queue_push(First, Nested),
            queue_push(Nested, First),
            lists:foreach(fun queue_body/1, Children),
            self() ! {gun_upgrade, self(), Stream, [<<"websocket">>], []},
            self() ! {gun_error, self(), Stream, reset},
            self() ! {gun_response, self(), Other, nofin, 200, []},
            self() ! {gun_data, self(), Other, fin, <<"keep">>},
            self() ! {gun_push, self(), Other, make_ref(), <<"GET">>, <<"/other-push">>, []},
            self() ! {gun_error, self(), <<"connection event">>},
            self() ! {application_message, Next},
            {ok, Stream}
        end,
        Await = fun(_, _, _) ->
            receive {Next, Message} -> Message after 0 -> {error, timeout} end
        end,
        {error, Expected} = gluegun@client:get_with(
            Conn, <<"/">>, [], {milliseconds, 1000}, Request, Await
        ),
        case InvalidConnection of
            false ->
                lists:foreach(fun assert_cancel/1, [Stream | Children]);
            true -> ok
        end,
        lists:foreach(fun assert_empty_stream/1, [Stream | Children]),
        case InvalidConnection of
            true ->
                %% Even a failed cancellation must drain every sibling; the
                %% root cancel error keeps precedence over descendant errors.
                ExpectedCancel = gluegun_ffi:cancel(Conn, Stream),
                queue_push(Stream, First),
                queue_push(Stream, Second),
                queue_push(First, Nested),
                lists:foreach(fun queue_body/1, Children),
                ExpectedCancel = gluegun_ffi:cleanup_stream(Conn, Stream),
                lists:foreach(fun assert_empty_stream/1, [Stream | Children]);
            false -> ok
        end,
        {ok, {response, no_fin, 200, []}} = gluegun_ffi:await(self(), Other, {milliseconds, 0}),
        {ok, {data, fin, <<"keep">>}} = gluegun_ffi:await(self(), Other, {milliseconds, 0}),
        receive {gun_push, OtherConn, Other, _, _, _, _} when OtherConn =:= self() -> ok
        after 0 -> error(lost_other_push) end,
        receive {gun_error, ConnEvent, <<"connection event">>} when ConnEvent =:= self() -> ok
        after 0 -> error(lost_connection_event) end,
        receive {application_message, Next} -> ok
        after 0 -> error(lost_application_message) end
    end).

push_cleanup(BodyStarted) ->
    check(fun() ->
        Stream = make_ref(),
        Promised = make_ref(),
        Nested = make_ref(),
        Other = make_ref(),
        Request = fun(_, _, _, _, _, _) ->
            case BodyStarted of
                true ->
                    self() ! {gun_response, self(), Stream, nofin, 200, []},
                    self() ! {gun_data, self(), Stream, nofin, <<"part">>};
                false -> ok
            end,
            queue_push(Stream, Promised),
            queue_push(Promised, Nested),
            lists:foreach(fun queue_body/1, [Stream, Promised, Nested, Other]),
            self() ! {gun_error, self(), <<"connection event">>},
            {ok, Stream}
        end,
        {error, {invalid_message, <<"HTTP helper received push message">>}} = gluegun@client:get_with(
            self(), <<"/">>, [], {milliseconds, 1000}, Request, fun gluegun_ffi:await/3
        ),
        lists:foreach(fun assert_cancel/1, [Stream, Promised, Nested]),
        lists:foreach(fun assert_empty_stream/1, [Stream, Promised, Nested]),
        {ok, {response, no_fin, 200, []}} =
            gluegun_ffi:await(self(), Other, {milliseconds, 0}),
        {ok, {data, no_fin, <<"unfinished">>}} =
            gluegun_ffi:await(self(), Other, {milliseconds, 0}),
        receive {gun_error, Pid, <<"connection event">>} when Pid =:= self() -> ok
        after 0 -> error(lost_connection_event) end
    end).

malformed_push_cleanup() ->
    check(fun() ->
        Stream = make_ref(),
        Child = make_ref(),
        Nested = make_ref(),
        Other = make_ref(),
        BadHeaders = [{<<"x-obs-text">>, <<255>>}],
        Expected = {error, {decode_error, <<"InvalidUtf8">>}},
        Expected = gluegun_ffi:safe_decode_message(
            {push, Child, <<"GET">>, <<"/push">>, BadHeaders}),
        %% Public low-level await must still decode without cancellation.
        self() ! {gun_push, self(), Stream, Child, <<"GET">>, <<"/push">>, BadHeaders},
        Expected = gluegun_ffi:await(self(), Stream, {milliseconds, 0}),
        receive
            {'$gen_cast', {cancel, _, Cancelled}}
                when Cancelled =:= Stream; Cancelled =:= Child; Cancelled =:= Nested ->
                error(low_level_cancelled_push)
        after 0 -> ok end,
        Request = fun(_, _, _, _, _, _) ->
            self() ! {gun_push, self(), Stream, Child, <<"GET">>, <<"/push">>, BadHeaders},
            queue_push(Child, Nested),
            lists:foreach(fun queue_body/1, [Stream, Child, Nested, Other]),
            self() ! {gun_error, self(), <<"connection event">>},
            {ok, Stream}
        end,
        Expected = gluegun@client:get_with(self(), <<"/">>, [],
            {milliseconds, 1000}, Request, fun gluegun_ffi:client_await/3),
        lists:foreach(fun assert_cancel/1, [Stream, Child, Nested]),
        lists:foreach(fun assert_empty_stream/1, [Stream, Child, Nested]),
        {ok, {response, no_fin, 200, []}} =
            gluegun_ffi:await(self(), Other, {milliseconds, 0}),
        {ok, {data, no_fin, <<"unfinished">>}} =
            gluegun_ffi:await(self(), Other, {milliseconds, 0}),
        receive {gun_error, Pid, <<"connection event">>} when Pid =:= self() -> ok
        after 0 -> error(lost_connection_event) end,
        %% Also exercise the actual public get callback, not just get_with.
        {ok, nil} = gluegun_http2_test:http2_push_cleanup(<<"malformed">>)
    end).

queue_push(Stream, Promised) ->
    self() ! {gun_push, self(), Stream, Promised, <<"GET">>, <<"/push">>, []}.

queue_body(Stream) ->
    self() ! {gun_response, self(), Stream, nofin, 200, []},
    self() ! {gun_data, self(), Stream, nofin, <<"unfinished">>}.

assert_cancel(Stream) ->
    receive
        {'$gen_cast', {cancel, Owner, Stream}} when Owner =:= self() -> ok
    after 0 -> error({missing_cancellation, Stream})
    end.

no_cleanup(SendFailure) ->
    check(fun() ->
        Stream = make_ref(),
        Request = fun(_, _, _, _, _, _) ->
            self() ! {gun_data, self(), Stream, fin, <<"keep">>},
            case SendFailure of
                true -> {error, {invalid_options, <<"rejected">>}};
                false -> {ok, Stream}
            end
        end,
        Await = fun(_, _, _) -> {ok, {response, fin, 204, []}} end,
        Result = gluegun@client:get_with(self(), <<"/">>, [], {milliseconds, 1000}, Request, Await),
        case SendFailure of
            true -> {error, {invalid_options, <<"rejected">>}} = Result;
            false -> {ok, Response} = Result, 204 = gluegun@response:status(Response)
        end,
        receive {'$gen_cast', {cancel, _, Stream}} -> error(unexpected_cancellation)
        after 0 -> ok end,
        receive {gun_data, _, Stream, fin, <<"keep">>} -> ok
        after 0 -> error(unexpected_drain) end
    end).

late_after_drain() ->
    check(fun() ->
        Stream = make_ref(),
        {ok, nil} = gluegun_ffi:cleanup_stream(self(), Stream),
        receive {'$gen_cast', {cancel, _, Stream}} -> ok after 0 -> error(missing_cancel) end,
        %% A sender can deliver a message after the zero-time drain completes.
        self() ! {gun_data, self(), Stream, fin, <<"late">>},
        {ok, {data, fin, <<"late">>}} = gluegun_ffi:await(self(), Stream, {milliseconds, 0})
    end).

delayed_response(BodyDelay) -> local_response(BodyDelay, none).

local_failure(ReceiveFailure) -> local_response(false, {inject, ReceiveFailure}).

local_response(BodyDelay, Injection) ->
    check(fun() ->
        {ok, Listener} = gen_tcp:listen(0, [
            binary, {active, false}, {packet, http_bin}, {ip, {127, 0, 0, 1}},
            {reuseaddr, true}
        ]),
        {ok, {_, Port}} = inet:sockname(Listener),
        Owner = self(),
        {Server, Monitor} = spawn_monitor(fun() -> serve(Listener, Owner, BodyDelay) end),
        try
            Options = gluegun@connection:with_protocols(
                gluegun@connection:with_transport(gluegun@connection:options(), tcp),
                [http1]
            ),
            {ok, Conn} = gluegun@connection:open(Options, <<"127.0.0.1">>, Port),
            try
                {ok, http1} = gluegun_ffi:await_up(Conn, {milliseconds, 2000}),
                %% This stream stays active while the high-level request waits.
                {ok, Other} = gluegun@request:request(
                    Conn, get, <<"/concurrent">>, [], <<>>, gluegun@request:options()
                ),
                case Injection of
                    none ->
                        {error, timeout} = gluegun@client:get(
                            Conn, <<"/delayed">>, [], {milliseconds, 100}
                        );
                    {inject, ReceiveFailure} ->
                        Request = fun(C, Method, Path, Headers, Body, Opts) ->
                            {ok, Stream} = gluegun@request:request(C, Method, Path, Headers, Body, Opts),
                            Raw = case ReceiveFailure of
                                true -> {gun_error, C, Stream, reset};
                                false -> {gun_data, C, Stream, fin, <<"before headers">>}
                            end,
                            self() ! Raw,
                            self() ! {gun_data, C, Stream, fin, <<"discard">>},
                            {ok, Stream}
                        end,
                        Result = gluegun@client:get_with(
                            Conn, <<"/delayed">>, [], {milliseconds, 100},
                            Request, fun gluegun_ffi:await/3
                        ),
                        Expected = case ReceiveFailure of
                            true -> gluegun_ffi:safe_decode_message({error, {stream_error, reset}});
                            false -> {error, {invalid_message,
                                <<"HTTP helper received body before response">>}}
                        end,
                        Expected = Result
                end,
                receive {ready, Server} -> ok after 2000 -> error(server_not_ready) end,
                %% Test-only synchronization: ensure Gun processed the cancel
                %% before asking the server to send late bytes.
                {ok, _} = gun:stream_info(Conn, Other),
                Server ! release,
                receive {sent, Server} -> ok after 2000 -> error(server_did_not_send) end,
                {ok, {response, no_fin, 200, _}} = gluegun_ffi:await(
                    Conn, Other, {milliseconds, 2000}
                ),
                {ok, {data, fin, <<"other">>}} = gluegun_ffi:await(
                    Conn, Other, {milliseconds, 2000}
                ),
                {ok, Response} = gluegun@client:get(
                    Conn, <<"/subsequent">>, [], {milliseconds, 2000}
                ),
                <<"next">> = gluegun@response:body(Response),
                %% The subsequent response orders the earlier late bytes on
                %% this HTTP/1.1 socket; no failed-stream events should remain.
                assert_no_stream_messages(Conn)
            after
                gun:close(Conn),
                gun:flush(Conn)
            end
        after
            gen_tcp:close(Listener),
            exit(Server, kill),
            receive {'DOWN', Monitor, process, Server, _} -> ok
            after 2000 -> error(server_teardown_timeout) end
        end
    end).

serve(Listener, Owner, BodyDelay) ->
    {ok, Socket} = gen_tcp:accept(Listener, 2000),
    try
        <<"/concurrent">> = read_request(Socket),
        <<"/delayed">> = read_request(Socket),
        ok = gen_tcp:send(Socket, response(<<"other">>)),
        case BodyDelay of
            true ->
                ok = gen_tcp:send(Socket, <<"HTTP/1.1 200 OK\r\nContent-Length: 8\r\n\r\npart">>);
            false -> ok
        end,
        Owner ! {ready, self()},
        receive release -> ok after 2000 -> error(release_timeout) end,
        Late = case BodyDelay of true -> <<"late">>; false -> response(<<"late">>) end,
        ok = gen_tcp:send(Socket, Late),
        Owner ! {sent, self()},
        <<"/subsequent">> = read_request(Socket),
        ok = gen_tcp:send(Socket, response(<<"next">>)),
        receive stop -> ok after 2000 -> ok end
    after gen_tcp:close(Socket) end.

read_request(Socket) ->
    {ok, {http_request, 'GET', {abs_path, Path}, _}} = gen_tcp:recv(Socket, 0, 2000),
    read_headers(Socket),
    Path.

read_headers(Socket) ->
    case gen_tcp:recv(Socket, 0, 2000) of
        {ok, http_eoh} -> ok;
        {ok, {http_header, _, _, _, _}} -> read_headers(Socket);
        Other -> error({invalid_headers, Other})
    end.

response(Body) ->
    [<<"HTTP/1.1 200 OK\r\nContent-Length: ">>, integer_to_binary(byte_size(Body)),
        <<"\r\n\r\n">>, Body].

assert_empty_stream(Stream) ->
    receive
        {gun_response, _, Stream, _, _, _} -> error(failed_response_not_drained);
        {gun_data, _, Stream, _, _} -> error(failed_stream_not_drained);
        {gun_push, _, Stream, _, _, _, _} -> error(failed_push_not_drained);
        {gun_push, _, Stream, _, _, _, _, _} -> error(failed_push_not_drained);
        {gun_upgrade, _, Stream, _, _} -> error(failed_upgrade_not_drained);
        {gun_error, _, Stream, _} -> error(failed_error_not_drained)
    after 0 -> ok end.

assert_no_stream_messages(Conn) ->
    receive
        {gun_response, Conn, _, _, _, _} -> error(late_response);
        {gun_data, Conn, _, _, _} -> error(late_data);
        {gun_error, Conn, _, _} -> error(late_stream_error)
    after 0 -> ok end.

check(Fun) ->
    try Fun(), {ok, nil}
    catch Class:Reason:Stack ->
        {error, iolist_to_binary(io_lib:format("~p:~p at ~p", [Class, Reason, Stack]))}
    end.
