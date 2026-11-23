-module(gluegun_lifecycle_test).
-export([with_mailbox/2, with_down_timers/1, timed_await/2,
    with_dead_connection/1, with_retry_peer/1, close_peer/1,
    wait_lifecycle/2, lifecycle_count/1, fail_peer/1, retry_client_failure/2,
    enqueue/2, with_reconnecting_mailbox/1, with_sustained_down/1,
    with_waiting_down/1, with_late_up/1]).

%% Isolate flood tests from Unitest's mailbox. A deliberately retained prefix
%% makes consuming an open-ended queue expensive without depending on sender
%% throughput alone. The producer is still active when the callback must finish.
with_sustained_down(Callback) ->
    with_sustained_down(Callback, true).

with_waiting_down(Callback) ->
    with_sustained_down(Callback, false).

with_sustained_down(Callback, InitialDown) ->
    Parent = self(),
    Ref = make_ref(),
    {Worker, Monitor} = spawn_monitor(fun() ->
        with_mailbox([], fun(Conn) ->
            Prefix = [{application, Ref, N} || N <- lists:seq(1, 4000)],
            lists:foreach(fun(M) -> self() ! M end, Prefix),
            case InitialDown of
                true -> enqueue(Conn, lists:duplicate(4000, down));
                false -> nil
            end,
            Parent ! {Ref, ready, self(), Conn},
            receive {Ref, go} -> ok end,
            Start = gluegun_ffi:monotonic_milliseconds(),
            nil = Callback(Conn),
            Elapsed = gluegun_ffi:monotonic_milliseconds() - Start,
            Parent ! {Ref, returned, Elapsed},
            %% Stop the sender before checking the exact preserved mailbox.
            receive {Ref, stopped} -> ok end,
            gluegun_ffi:drain_lifecycle(Conn),
            lists:foreach(fun(M) ->
                receive M -> ok after 0 -> error(prefix_consumed) end
            end, Prefix),
            nil
        end)
    end),
    receive {Ref, ready, Worker, Conn} ->
        {Producer, ProducerMonitor} = spawn_monitor(fun() ->
            receive {Ref, start} ->
                down_batch(Worker, Conn),
                Parent ! {Ref, producing},
                flood_down(Worker, Conn, Ref)
            end
        end),
        try
            case InitialDown of
                true -> ok;
                false ->
                    Worker ! {Ref, go},
                    ok = wait_in_receive(Worker, gluegun_ffi:monotonic_milliseconds() + 1000)
            end,
            Producer ! {Ref, start},
            receive {Ref, producing} -> ok after 1000 -> error(producer_start_timeout) end,
            case InitialDown of true -> Worker ! {Ref, go}; false -> ok end,
            receive
                {Ref, returned, Elapsed} ->
                    true = Elapsed < 500,
                    true = is_process_alive(Producer),
                    Producer ! {Ref, stop},
                    receive {'DOWN', ProducerMonitor, process, Producer, normal} -> ok end,
                    Worker ! {Ref, stopped},
                    receive
                        {'DOWN', Monitor, process, Worker, normal} -> nil;
                        {'DOWN', Monitor, process, Worker, Reason} -> error({worker_failed, Reason})
                    after 2000 -> error(worker_cleanup_timeout)
                    end;
                {'DOWN', Monitor, process, Worker, Reason} -> error({worker_failed, Reason})
            after 500 -> error(sustained_down_did_not_return_within_500ms)
            end
        after
            exit(Producer, kill),
            erlang:demonitor(ProducerMonitor, [flush]),
            exit(Worker, kill),
            erlang:demonitor(Monitor, [flush]),
            exit(Conn, kill)
        end
    after 2000 -> error(worker_start_timeout)
    end.

wait_in_receive(Worker, Deadline) ->
    case {process_info(Worker, status), process_info(Worker, current_function)} of
        {{status, waiting}, {current_function, {gluegun_ffi, await_connection_up, 4}}} -> ok;
        _ ->
            case gluegun_ffi:monotonic_milliseconds() >= Deadline of
                true -> error(worker_did_not_enter_receive);
                false -> timer:sleep(1), wait_in_receive(Worker, Deadline)
            end
    end.

flood_down(Worker, Conn, Ref) ->
    down_batch(Worker, Conn),
    receive {Ref, stop} -> ok
    after 1 -> flood_down(Worker, Conn, Ref)
    end.

down_batch(Worker, Conn) ->
    lists:foreach(fun(_) ->
        Worker ! {gun_down, Conn, http, closed, []}
    end, lists:seq(1, 200)).

%% Suspend during the initial queue scan, then append an up after the budget.
%% That late up is outside the initial observation and must not win at expiry.
with_late_up(Callback) ->
    Parent = self(),
    Ref = make_ref(),
    {Worker, Monitor} = spawn_monitor(fun() ->
        with_mailbox([], fun(Conn) ->
            Prefix = [{application, Ref, N} || N <- lists:seq(1, 4000)],
            lists:foreach(fun(M) -> self() ! M end, Prefix),
            enqueue(Conn, lists:duplicate(4000, down)),
            Parent ! {Ref, ready, Conn},
            receive {Ref, go} -> ok end,
            nil = Callback(Conn),
            lists:foreach(fun(M) ->
                receive M -> ok after 0 -> error(prefix_consumed) end
            end, Prefix),
            nil
        end)
    end),
    try
        receive {Ref, ready, Conn} ->
            try
                Worker ! {Ref, go},
                ok = wait_in_await(Worker, gluegun_ffi:monotonic_milliseconds() + 1000),
                true = erlang:suspend_process(Worker),
                timer:sleep(120),
                Worker ! {gun_up, Conn, http2},
                true = erlang:resume_process(Worker),
                receive
                    {'DOWN', Monitor, process, Worker, normal} -> nil;
                    {'DOWN', Monitor, process, Worker, Reason} -> error({worker_failed, Reason})
                after 500 -> error(late_up_wait_did_not_return)
                end
            after exit(Conn, kill)
            end
        after 2000 -> error(worker_start_timeout)
        end
    after
        exit(Worker, kill),
        erlang:demonitor(Monitor, [flush])
    end.

wait_in_await(Worker, Deadline) ->
    case process_info(Worker, current_function) of
        {current_function, {gluegun_ffi, queued_lifecycle, _}} -> ok;
        {current_function, {gluegun_ffi, queued_lifecycle_receive, _}} -> ok;
        _ ->
            case gluegun_ffi:monotonic_milliseconds() >= Deadline of
                true -> error(worker_did_not_enter_await);
                false -> timer:sleep(1), wait_in_await(Worker, Deadline)
            end
    end.

%% Events are typed test constructors: Up(Protocol) and Down.
enqueue(Conn, Events) ->
    lists:foreach(fun
        ({up, http1}) -> self() ! {gun_up, Conn, http};
        ({up, http2}) -> self() ! {gun_up, Conn, http2};
        (down) -> self() ! {gun_down, Conn, http, closed, []};
        (unknown_up) -> self() ! {gun_up, Conn, raw}
    end, Events),
    nil.

with_mailbox(Events, Callback) ->
    {Conn, Monitor} = spawn_monitor(fun() -> receive stop -> ok end end),
    Stream = make_ref(),
    Other = self(),
    Sentinel = make_ref(),
    Preserved = [
        {application, Sentinel},
        {gluegun_lifecycle_fence, make_ref()},
        {gun_up, Other, http},
        {gun_down, Other, http, unrelated, []},
        {gun_response, Conn, Stream, fin, 200, []},
        {gun_data, Conn, Stream, fin, <<"other stream">>},
        {gun_error, Conn, Stream, unrelated},
        {gun_error, Conn, unrelated},
        {gun_tunnel_up, Conn, Stream, http},
        {'DOWN', make_ref(), process, Conn, unrelated}
    ],
    lists:foreach(fun(Message) -> self() ! Message end, Preserved),
    enqueue(Conn, Events),
    {messages, Before} = process_info(self(), messages),
    Expected = [M || M <- Before, not lifecycle(M, Conn)],
    Monitors = monitors(),
    try
        nil = Callback(Conn),
        0 = lifecycle_count(Conn),
        Monitors = monitors(),
        {messages, Expected} = process_info(self(), messages),
        nil
    after
        gluegun_ffi:drain_lifecycle(Conn),
        lists:foreach(fun(Message) ->
            receive Message -> ok after 0 -> ok end
        end, Preserved),
        exit(Conn, kill),
        receive {'DOWN', Monitor, process, Conn, _} -> ok end
    end.

monitors() ->
    {monitors, Monitors} = process_info(self(), monitors),
    lists:sort(Monitors).

with_down_timers(Callback) ->
    with_mailbox([], fun(Conn) ->
        Timers = [erlang:send_after(Delay, self(),
            {gun_down, Conn, http, closed, []}) || Delay <- [10, 40, 70, 100, 130]],
        Up = erlang:send_after(250, self(), {gun_up, Conn, http}),
        try Callback(Conn)
        after
            lists:foreach(fun erlang:cancel_timer/1, [Up | Timers]),
            gluegun_ffi:drain_lifecycle(Conn)
        end
    end).

with_reconnecting_mailbox(Callback) ->
    with_mailbox([{up, http1}, down], fun(Conn) ->
        Down = erlang:send_after(10, self(), {gun_down, Conn, http, closed, []}),
        Up = erlang:send_after(30, self(), {gun_up, Conn, http2}),
        try Callback(Conn)
        after
            erlang:cancel_timer(Down),
            erlang:cancel_timer(Up),
            gluegun_ffi:drain_lifecycle(Conn)
        end
    end).

timed_await(Conn, Timeout) ->
    Start = gluegun_ffi:monotonic_milliseconds(),
    Result = gluegun@connection:await_up(Conn, Timeout),
    {Result, gluegun_ffi:monotonic_milliseconds() - Start}.

%% The actual external monitor DOWN must survive both readiness and drain.
with_dead_connection(Callback) ->
    {Conn, External} = spawn_monitor(fun() -> ok end),
    receive {'DOWN', External, process, Conn, normal} = Down ->
        self() ! Down,
        try
            nil = Callback(Conn),
            receive Down -> nil after 0 -> error(external_down_consumed) end
        after
            erlang:demonitor(External, [flush]),
            gluegun_ffi:drain_lifecycle(Conn)
        end
    end.

lifecycle({gun_up, Conn, _}, Conn) -> true;
lifecycle({gun_down, Conn, _, _, _}, Conn) -> true;
lifecycle(_, _) -> false.

lifecycle_count(Conn) ->
    {messages, Messages} = process_info(self(), messages),
    length([M || M <- Messages, lifecycle(M, Conn)]).

%% Test-only mailbox observation: never consume lifecycle events to establish
%% readiness. The bounded poll lets Gun itself enqueue the real ordered events.
wait_lifecycle(Conn, Count) ->
    wait_lifecycle(Conn, Count, gluegun_ffi:monotonic_milliseconds() + 2000).

wait_lifecycle(Conn, Count, Deadline) ->
    case lifecycle_count(Conn) >= Count of
        true -> {ok, nil};
        false ->
            case gluegun_ffi:monotonic_milliseconds() >= Deadline of
                true -> {error, <<"Lifecycle delivery timeout">>};
                false -> timer:sleep(1), wait_lifecycle(Conn, Count, Deadline)
            end
    end.

%% Gun 2.8 sends five-field gun_down and three-field gun_up, in order.
%% Explicit retry and a controlled loopback peer avoid internet and defaults.
with_retry_peer(Callback) ->
    {ok, Listener} = gen_tcp:listen(0, [binary, {active, false},
        {ip, {127, 0, 0, 1}}, {reuseaddr, true}]),
    {ok, {_, Port}} = inet:sockname(Listener),
    {Peer, PeerMonitor} = spawn_monitor(fun() -> accept_peer(Listener) end),
    {ok, Conn} = gun:open("127.0.0.1", Port, #{transport => tcp,
        protocols => [http], retry => 10,
        %% Gun's default retry_fun reconnects immediately after disconnect,
        %% regardless of retry_timeout. Control every retry's delay explicitly.
        retry_fun => fun(Retries, _) ->
            #{retries => Retries - 1, timeout => 250}
        end}),
    try Callback(Conn, Peer)
    after
        {ok, nil} = gluegun_ffi:terminate(Conn),
        exit(Peer, kill),
        receive {'DOWN', PeerMonitor, process, Peer, _} -> ok end,
        gen_tcp:close(Listener)
    end.

close_peer(Peer) -> peer_command(Peer, close).
fail_peer(Peer) -> peer_command(Peer, fail_next).

peer_command(Peer, Command) ->
    Ref = make_ref(),
    Peer ! {Command, self(), Ref},
    receive {Ref, nil} -> {ok, nil}
    after 2000 -> {error, <<"Peer command timeout">>}
    end.

accept_peer(Listener) ->
    {ok, Socket} = gen_tcp:accept(Listener, 2000),
    try
        ok = inet:setopts(Socket, [{active, once}]),
        serve_peer(Listener, Socket, <<>>, false)
    after gen_tcp:close(Socket)
    end,
    accept_peer(Listener).

serve_peer(Listener, Socket, Buffer, Fail) ->
    receive
        {close, From, Ref} ->
            gen_tcp:close(Socket),
            From ! {Ref, nil};
        {fail_next, From, Ref} ->
            From ! {Ref, nil},
            serve_peer(Listener, Socket, Buffer, true);
        {tcp, Socket, Data} ->
            Next = <<Buffer/binary, Data/binary>>,
            case binary:match(Next, <<"\r\n\r\n">>) of
                nomatch ->
                    ok = inet:setopts(Socket, [{active, once}]),
                    serve_peer(Listener, Socket, Next, Fail);
                _ when Fail ->
                    ok = gen_tcp:send(Socket,
                        <<"HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nshort">>),
                    gen_tcp:close(Socket);
                _ ->
                    ok = gen_tcp:send(Socket,
                        <<"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok">>),
                    ok = inet:setopts(Socket, [{active, once}]),
                    serve_peer(Listener, Socket, <<>>, false)
            end;
        {tcp_closed, Socket} -> ok
    after 3000 -> error(peer_idle_timeout)
    end.

%% Exercise the common production client path. Wait for the real down to
%% reach this owner before returning the consumed stream failure, making the
%% post-cleanup mailbox assertion independent of cross-process scheduling.
retry_client_failure(Conn, Timeout) ->
    gluegun@client:get_with(Conn, <<"/fail">>, [], Timeout,
        fun gluegun@request:request/6,
        fun(C, S, T) ->
            Result = gluegun_ffi:client_await(C, S, T),
            case Result of
                {error, _} -> {ok, nil} = wait_lifecycle(C, 1);
                {ok, _} -> ok
            end,
            Result
        end).
