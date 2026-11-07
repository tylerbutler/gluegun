-module(gluegun_bounded_test).

-include_lib("public_key/include/public_key.hrl").

-export([capture_flow/1, project_setup/1, invalid_options/0, run_scenario/3, cleanup/0,
    verify_tls/1, init/2, domain_lookup_start/2, domain_lookup_end/2, connect_start/2]).

capture_flow(Options) ->
    checked(fun() ->
        {ok, _} = gluegun_ffi:request(self(), <<"GET">>, <<"/">>, [], <<>>, Options),
        RequestFlow = receive
            {'$gen_cast', {request, _, _, _, _, _, _, Flow1}} -> Flow1
        after 1000 -> error(no_request_cast)
        end,
        {ok, _} = gluegun_ffi:headers(self(), <<"POST">>, <<"/">>, [], Options),
        HeadersFlow = receive
            {'$gen_cast', {headers, _, _, _, _, _, Flow2}} -> Flow2
        after 1000 -> error(no_headers_cast)
        end,
        {ok, {render(RequestFlow), render(HeadersFlow)}}
    end).

project_setup(Options) ->
    Gun = gluegun_ffi:connect_options_to_gun(Options),
    Tcp = maps:get(tcp_opts, Gun, [{send_timeout, 15000}, {send_timeout_close, true}]),
    Family = case lists:member(inet, Tcp) of
        true -> inet;
        false -> case lists:member(inet6, Tcp) of true -> inet6; false -> default end
    end,
    {render(Family), render(maps:get(retry, Gun)),
        render(maps:get(connect_timeout, Gun)),
        render(maps:get(domain_lookup_timeout, Gun, infinity)),
        render(maps:get(tls_handshake_timeout, Gun, infinity)),
        proplists:get_value(send_timeout, Tcp) =:= 15000
            andalso proplists:get_value(send_timeout_close, Tcp) =:= true}.

invalid_options() ->
    checked(fun() ->
        lists:foreach(fun(Option) ->
            {error, {invalid_options, _}} =
                gluegun_ffi:open(<<"localhost">>, 80, [Option])
        end, [
            {retry_option, {retry_count, -1}},
            {retry_option, infinity},
            {address_family_option, unknown},
            {domain_lookup_timeout_option, {milliseconds, -1}},
            {tls_handshake_timeout_option, {milliseconds, -1}},
            {connect_timeout_option, {milliseconds, -1}}
        ]),
        lists:foreach(fun(Credit) ->
            {error, {invalid_options, _}} =
                gluegun_ffi:request(self(), <<"GET">>, <<"/">>, [], <<>>,
                    [{initial_flow, Credit}]),
            {error, {invalid_options, _}} =
                gluegun_ffi:headers(self(), <<"GET">>, <<"/">>, [],
                    [{initial_flow, Credit}])
        end, [0, -1, infinity]),
        {ok, nil}
    end).

run_scenario(Name, ConnectOptions, RequestOptions) ->
    checked(fun() ->
        Family = case lists:keyfind(address_family_option, 1, ConnectOptions) of
            {_, ipv4} -> inet;
            {_, ipv6} -> inet6
        end,
        Ip = case Family of inet -> {127,0,0,1}; inet6 -> {0,0,0,0,0,0,0,1} end,
        {ok, Listener} = gen_tcp:listen(0, [Family, binary, {active, false},
            {ip, Ip}, {reuseaddr, true}]),
        {ok, {_, Port}} = inet:sockname(Listener),
        Parent = self(),
        {Server, Monitor} = spawn_monitor(fun() -> serve(Listener, Parent, Name) end),
        try
            do_scenario(Name, Port, Server, ConnectOptions, RequestOptions)
        after
            gen_tcp:close(Listener),
            exit(Server, kill),
            receive {'DOWN', Monitor, process, Server, _} -> ok end,
            receive {accepted, Server} -> ok after 0 -> ok end
        end
    end).

do_scenario(<<"family">>, Port, Server, Options, _RequestOptions) ->
    {ok, Conn} = gluegun_ffi:open(<<"localhost">>, Port, Options),
    try
        {ok, http1} = gluegun_ffi:await_up(Conn, {milliseconds, 1000}),
        receive {accepted, Server} -> ok after 1000 -> error(not_accepted) end,
        Other = case lists:keyfind(address_family_option, 1, Options) of
            {_, ipv4} -> ipv6;
            {_, ipv6} -> ipv4
        end,
        Opposite = lists:keyreplace(address_family_option, 1, Options,
            {address_family_option, Other}),
        {ok, Failed} = gluegun_ffi:open(<<"localhost">>, Port, Opposite),
        try
            {error, _} = gluegun_ffi:await_up(Failed, {milliseconds, 1000})
        after
            {ok, nil} = gluegun_ffi:terminate(Failed)
        end
    after
        {ok, nil} = gluegun_ffi:terminate(Conn),
        assert_empty(Conn)
    end,
    {ok, nil};
do_scenario(Name, Port, _Server, Options, _RequestOptions)
    when Name =:= <<"dns_deadline">>; Name =:= <<"connect_deadline">> ->
    %% Hold the actual Gun process at a setup event, without changing DNS
    %% configuration or depending on an unroutable external address.
    GunOptions = gluegun_ffi:connect_options_to_gun(Options),
    {ok, Conn} = gun:open("localhost", Port,
        GunOptions#{event_handler => {?MODULE, {Name, self()}}}),
    try
        receive {setup_blocked, Conn} -> ok after 1000 -> error(setup_not_blocked) end,
        Start = now_ms(),
        {error, timeout} = gluegun_ffi:await_up(Conn, {milliseconds, 50}),
        true = now_ms() - Start < 500
    after
        {ok, nil} = gluegun_ffi:terminate(Conn),
        false = is_process_alive(Conn),
        assert_empty(Conn)
    end,
    {ok, nil};
do_scenario(Name, Port, Server, Options0, RequestOptions) ->
    Options = case Name of
        <<"tls_stall">> ->
            lists:keyreplace(transport_option, 1, Options0, {transport_option, tls});
        <<"setup_deadline">> ->
            lists:keyreplace(tls_handshake_timeout_option, 1,
                lists:keyreplace(transport_option, 1, Options0, {transport_option, tls}),
                {tls_handshake_timeout_option, infinity});
        _ -> Options0
    end,
    Start = now_ms(),
    {ok, Conn} = gluegun_ffi:open(<<"localhost">>, Port, Options),
    try
        case Name of
            <<"tls_stall">> ->
                {error, Reason} = gluegun_ffi:await_up(Conn, {milliseconds, 1000}),
                true = Reason =/= timeout,
                true = now_ms() - Start < 900;
            <<"setup_deadline">> ->
                {error, timeout} = gluegun_ffi:await_up(Conn, {milliseconds, 50}),
                true = now_ms() - Start < 500;
            _ ->
                {ok, http1} = gluegun_ffi:await_up(Conn, {milliseconds, 1000}),
                {ok, Stream} = gluegun_ffi:request(Conn, <<"GET">>, <<"/">>,
                    [], <<>>, RequestOptions),
                consume(Name, Conn, Stream, Server)
        end
    after
        CleanupStart = now_ms(),
        {ok, nil} = gluegun_ffi:terminate(Conn),
        true = now_ms() - CleanupStart < 500,
        false = is_process_alive(Conn),
        assert_empty(Conn)
    end,
    {ok, nil}.

consume(<<"headers_stall">>, Conn, Stream, _Server) ->
    {error, timeout} = gluegun_ffi:await(Conn, Stream, {milliseconds, 50});
consume(Name, Conn, Stream, Server) ->
    {ok, {response, no_fin, Status, Headers}} =
        gluegun_ffi:await(Conn, Stream, {milliseconds, 1000}),
    case Name of
        <<"length">> ->
            {_, Length} = lists:keyfind(<<"content-length">>, 1, Headers),
            true = binary_to_integer(Length) > 64,
            {error, timeout} = gluegun_ffi:await(Conn, Stream, {milliseconds, 30}),
            {ok, nil} = gluegun_ffi:cancel(Conn, Stream);
        <<"status">> ->
            403 = Status,
            {error, timeout} = gluegun_ffi:await(Conn, Stream, {milliseconds, 30}),
            {ok, nil} = gluegun_ffi:cancel(Conn, Stream);
        <<"body_stall">> ->
            {error, timeout} = gluegun_ffi:await(Conn, Stream, {milliseconds, 50});
        <<"deadline">> ->
            Server ! send_body,
            deadline_loop(Conn, Stream, now_ms() + 120, 0);
        _ ->
            200 = Status,
            Server ! send_body,
            {ok, {data, no_fin, First}} =
                gluegun_ffi:await(Conn, Stream, {milliseconds, 1000}),
            true = byte_size(First) > 0,
            {error, timeout} = gluegun_ffi:await(Conn, Stream, {milliseconds, 50}),
            case Name of
                <<"large">> -> finish_body(Conn, Stream, byte_size(First), 1024 * 1024);
                <<"small">> -> finish_body(Conn, Stream, byte_size(First), 4096);
                _ ->
                    true = byte_size(First) =< 64,
                    Server ! send_more,
                    enforce_limit(Conn, Stream, byte_size(First), 64)
            end
    end.

finish_body(Conn, Stream, Bytes, Expected) ->
    {ok, nil} = gluegun_ffi:update_flow(Conn, Stream, 1),
    case gluegun_ffi:await(Conn, Stream, {milliseconds, 1000}) of
        {ok, {data, no_fin, Data}} ->
            finish_body(Conn, Stream, Bytes + byte_size(Data), Expected);
        {ok, {data, fin, Data}} ->
            Expected = Bytes + byte_size(Data)
    end.

enforce_limit(Conn, Stream, Bytes, Limit) when Bytes > Limit ->
    {ok, nil} = gluegun_ffi:cancel(Conn, Stream);
enforce_limit(Conn, Stream, Bytes, Limit) ->
    {ok, nil} = gluegun_ffi:update_flow(Conn, Stream, 1),
    {ok, {data, _, Data}} = gluegun_ffi:await(Conn, Stream, {milliseconds, 1000}),
    enforce_limit(Conn, Stream, Bytes + byte_size(Data), Limit).

deadline_loop(Conn, Stream, Deadline, Bytes) ->
    Remaining = max(0, Deadline - now_ms()),
    case Remaining of
        0 -> true = Bytes > 0;
        _ ->
            case gluegun_ffi:await(Conn, Stream, {milliseconds, Remaining}) of
                {error, timeout} ->
                    true = Bytes > 0,
                    true = now_ms() - Deadline < 150;
                {ok, {data, no_fin, Data}} ->
                    {ok, nil} = gluegun_ffi:update_flow(Conn, Stream, 1),
                    deadline_loop(Conn, Stream, Deadline, Bytes + byte_size(Data))
            end
    end.

serve(Listener, Parent, Name) ->
    {ok, Socket} = gen_tcp:accept(Listener, 2000),
    Parent ! {accepted, self()},
    try
        case Name of
            <<"family">> -> receive stop -> ok end;
            <<"tls_stall">> -> receive stop -> ok end;
            <<"setup_deadline">> -> receive stop -> ok end;
            _ ->
                read_headers(Socket, <<>>),
                send_response(Socket, Name)
        end
    after
        gen_tcp:close(Socket)
    end.

read_headers(Socket, Acc) ->
    {ok, Bytes} = gen_tcp:recv(Socket, 0, 2000),
    Next = <<Acc/binary, Bytes/binary>>,
    case binary:match(Next, <<"\r\n\r\n">>) of
        nomatch -> read_headers(Socket, Next);
        _ -> ok
    end.

send_response(_Socket, <<"headers_stall">>) ->
    receive stop -> ok end;
send_response(Socket, <<"status">>) ->
    ok = gen_tcp:send(Socket, <<"HTTP/1.1 403 Forbidden\r\nContent-Length: 1048576\r\n\r\n">>),
    receive stop -> ok end;
send_response(Socket, Name)
    when Name =:= <<"length">>; Name =:= <<"body_stall">> ->
    ok = gen_tcp:send(Socket, <<"HTTP/1.1 200 OK\r\nContent-Length: 1048576\r\n\r\n">>),
    receive stop -> ok end;
send_response(Socket, Name) ->
    Header = case Name of
        <<"close">> -> <<"HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n">>;
        _ -> <<"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n">>
    end,
    ok = gen_tcp:send(Socket, Header),
    receive send_body -> ok after 2000 -> error(no_body_permission) end,
    case Name of
        <<"large">> ->
            ok = gen_tcp:send(Socket,
                [<<"100000\r\n">>, binary:copy(<<"x">>, 1024 * 1024), <<"\r\n0\r\n\r\n">>]);
        <<"small">> ->
            %% Coalesce many small HTTP chunks into one write.
            ok = gen_tcp:send(Socket,
                [lists:duplicate(4096, <<"1\r\nx\r\n">>), <<"0\r\n\r\n">>]);
        <<"chunked">> ->
            ok = gen_tcp:send(Socket, [<<"20\r\n">>, binary:copy(<<"x">>, 32), <<"\r\n">>]),
            receive send_more -> ok after 2000 -> error(no_more_permission) end,
            ok = gen_tcp:send(Socket,
                [<<"30\r\n">>, binary:copy(<<"x">>, 48), <<"\r\n0\r\n\r\n">>]);
        <<"close">> ->
            ok = gen_tcp:send(Socket, binary:copy(<<"x">>, 32)),
            receive send_more -> ok after 2000 -> error(no_more_permission) end,
            ok = gen_tcp:send(Socket, binary:copy(<<"x">>, 48)),
            gen_tcp:close(Socket);
        <<"deadline">> -> dribble(Socket)
    end,
    receive stop -> ok end.

dribble(Socket) ->
    case gen_tcp:send(Socket, <<"1\r\nx\r\n">>) of
        ok -> timer:sleep(25), dribble(Socket);
        {error, closed} -> ok
    end.

cleanup() ->
    checked(fun() ->
        Parent = self(),
        Sender = spawn(fun() ->
            Parent ! {gun_data, self(), make_ref(), nofin, <<"discard">>},
            Parent ! {gun_push, self(), make_ref(), make_ref(), <<"GET">>,
                <<"/discard">>, []},
            Parent ! {gun_push, self(), make_ref(), make_ref(), <<"GET">>,
                <<"/discard-too">>, []},
            Parent ! {ready, self()},
            receive blocked -> ok end
        end),
        receive {ready, Sender} -> ok end,
        OtherPush = {gun_push, self(), make_ref(), make_ref(), <<"GET">>,
            <<"/preserve">>, []},
        self() ! OtherPush,
        self() ! unrelated_message,
        {ok, nil} = gluegun_ffi:terminate(Sender),
        assert_empty(Sender),
        receive OtherPush -> ok after 0 -> error(lost_other_connection_push) end,
        receive unrelated_message -> ok after 0 -> error(lost_unrelated_message) end,
        {ok, nil} = gluegun_ffi:terminate(Sender),
        {error, {invalid_options, _}} = gluegun_ffi:terminate(self()),
        {error, {invalid_options, _}} = gluegun_ffi:terminate(<<"not-a-pid">>),
        {ok, nil}
    end).

verify_tls(Options0) ->
    checked(fun() ->
        Certificate = public_key:pkix_test_data(#{
            root => [{digest, sha256}, {key, {rsa, 2048, 65537}}],
            intermediates => [],
            peer => [{digest, sha256}, {key, {rsa, 2048, 65537}}, {extensions, [
                #'Extension'{extnID = ?'id-ce-subjectAltName',
                    extnValue = [{dNSName, "localhost"}], critical = false}
            ]}]
        }),
        CAs = proplists:get_value(cacerts, Certificate),
        {address_family_option, Family} = lists:keyfind(address_family_option, 1, Options0),
        {TcpFamily, Ip} = case Family of
            ipv4 -> {inet, {127,0,0,1}};
            ipv6 -> {inet6, {0,0,0,0,0,0,0,1}}
        end,
        Options = lists:keyreplace(transport_option, 1, Options0, {transport_option, tls}),
        %% Each attempt gets a fresh listener; no global CA or resolver changes.
        lists:foreach(fun({Settings, Expected}) ->
            {ok, Listener} = ssl:listen(0, [TcpFamily, {ip, Ip}, {active, false},
                {reuseaddr, true} | Certificate]),
            {ok, {_, Port}} = ssl:sockname(Listener),
            {Server, Monitor} = spawn_monitor(fun() ->
                {ok, Socket} = ssl:transport_accept(Listener, 2000),
                case ssl:handshake(Socket, 2000) of
                    {ok, Secure} ->
                        receive stop -> ok end,
                        ssl:close(Secure);
                    {error, _} -> ok
                end
            end),
            try
                {ok, Conn} = gluegun_ffi:open(<<"localhost">>, Port,
                    [{tls_option, Settings} | Options]),
                try
                    case {Expected, gluegun_ffi:await_up(Conn, {milliseconds, 1500})} of
                        {success, {ok, _}} -> ok;
                        {{failure, Marker}, {error, {connection_down, Reason}}} ->
                            true = binary:match(Reason, Marker) =/= nomatch;
                        Result -> error({unexpected_tls_result, Expected, Result})
                    end
                after
                    {ok, nil} = gluegun_ffi:terminate(Conn),
                    assert_empty(Conn)
                end
            after
                ssl:close(Listener),
                exit(Server, kill),
                receive {'DOWN', Monitor, process, Server, _} -> ok end
            end
        end, [
            {[{cacerts_setting, CAs}], success},
            {[], {failure, <<"UnknownCa">>}},
            {[{cacerts_setting, CAs},
                {server_name_indication_setting, {server_name, <<"wrong.invalid">>}}],
                {failure, <<"HandshakeFailure">>}}
        ]),
        {ok, nil}
    end).

init(_Event, State) -> State.

domain_lookup_start(_Event, State = {<<"dns_deadline">>, Parent}) ->
    Parent ! {setup_blocked, self()},
    receive release_setup -> State end;
domain_lookup_start(_Event, State) -> State.

domain_lookup_end(_Event, State) -> State.

connect_start(_Event, State = {<<"connect_deadline">>, Parent}) ->
    Parent ! {setup_blocked, self()},
    receive release_setup -> State end.

assert_empty(Conn) ->
    timer:sleep(20),
    {messages, Messages} = process_info(self(), messages),
    [] = [Message || Message <- Messages, is_tuple(Message),
        (tuple_size(Message) >= 2 andalso element(2, Message) =:= Conn)
        orelse (tuple_size(Message) =:= 5 andalso element(1, Message) =:= 'DOWN'
            andalso element(4, Message) =:= Conn)],
    ok.

now_ms() -> erlang:monotonic_time(millisecond).

render(Value) when is_atom(Value) -> atom_to_binary(Value, utf8);
render(Value) when is_integer(Value) -> integer_to_binary(Value).

checked(Fun) ->
    try Fun()
    catch Class:Reason:Stack ->
        {error, {erlang_error, gleam@string:inspect({Class, Reason, Stack})}}
    end.
