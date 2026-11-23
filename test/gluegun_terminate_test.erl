-module(gluegun_terminate_test).

-export([with_fixture/2, caller_death/1, with_logs/2, log/2,
    with_stalled_tls/1, guard_paths/0]).

guard_paths() ->
    Connection = spawn(fun() -> receive never -> ok end end),
    Stream = make_ref(),
    {monitors, Monitors} = process_info(self(), monitors),
    {links, Links} = process_info(self(), links),
    try
        {error, {invalid_options, _}} = gluegun_ffi:terminate(self()),
        {error, {invalid_options, _}} = gluegun_ffi:terminate(not_a_connection),
        lists:foreach(fun(Timeout) ->
            {error, {invalid_options, _}} = gluegun_ffi:ws_close(
                Connection, Stream, Timeout, gluegun_ffi:ws_peer_close()),
            true = is_process_alive(Connection),
            {messages, []} = process_info(Connection, messages)
        end, [{milliseconds, -1}, {milliseconds, 4294967296}, bad_timeout]),
        {error, {invalid_options, _}} = gluegun_ffi:ws_close(
            self(), Stream, {milliseconds, 0}, gluegun_ffi:ws_peer_close()),
        {monitors, Monitors} = process_info(self(), monitors),
        {links, Links} = process_info(self(), links),
        {ok, nil}
    after stop(Connection)
    end.

%% All callbacks and results have typed Gleam declarations. These fixtures use
%% the real installed gun:close/1, not a substitute implementation.
with_fixture(Mode, Callback) ->
    with_logs(Mode, fun() ->
        Connection = spawn(fun() -> receive never -> ok end end),
        Tag = make_ref(),
        Suspended = Mode =:= <<"timeout">> orelse Mode =:= <<"dies">>,
        case Suspended of
            true ->
                ok = sys:suspend(gun_conns_sup),
                Parent = self(),
                spawn(fun() ->
                    {Worker, Guardian} = pending_helpers(),
                    Parent ! {helpers, Tag, Worker, Guardian},
                    case Mode of
                        <<"dies">> -> exit(Connection, kill);
                        _ -> ok
                    end
                end);
            false -> ok
        end,
        case Mode of
            <<"dead">> -> stop(Connection);
            _ -> ok
        end,
        Stream = make_ref(),
        Other = self(),
        self() ! {gun_push, Connection, Stream, make_ref(), <<"GET">>, <<"/">>, []},
        self() ! {gun_ws, Connection, Stream, close},
        self() ! {gun_down, Connection, http, normal, []},
        self() ! {gun_ws, Other, Stream, ping},
        {monitors, Monitors} = process_info(self(), monitors),
        {links, Links} = process_info(self(), links),
        Start = erlang:monotonic_time(millisecond),
        try
            Result = Callback(Connection),
            Elapsed = erlang:monotonic_time(millisecond) - Start,
            false = is_process_alive(Connection),
            {monitors, Monitors} = process_info(self(), monitors),
            {links, Links} = process_info(self(), links),
            receive {gun_ws, Other, Stream, ping} -> ok
            after 0 -> error(unrelated_mail_lost)
            end,
            case Suspended of
                true ->
                    receive
                        {helpers, Tag, Worker, Guardian} ->
                            false = is_process_alive(Worker),
                            false = is_process_alive(Guardian)
                    after 1000 -> error(helper_observation_timeout)
                    end;
                false -> ok
            end,
            case Mode of
                <<"timeout">> -> true = Elapsed >= 90 andalso Elapsed < 500;
                <<"dies">> -> true = Elapsed < 500;
                _ -> ok
            end,
            assert_no_private_mail(),
            Result
        after
            case Suspended of
                true -> ok = sys:resume(gun_conns_sup);
                false -> ok
            end,
            stop(Connection),
            gun:flush(Connection),
            receive {gun_ws, Other, Stream, ping} -> ok after 0 -> ok end
        end
    end).

caller_death(Mode) ->
    with_logs(<<"timeout">>, fun() ->
        Connection = spawn(fun() -> receive never -> ok end end),
        ok = sys:suspend(gun_conns_sup),
        {Caller, CallerMonitor} = spawn_monitor(fun() ->
            process_flag(trap_exit, Mode =:= <<"trapping">>),
            gluegun_ffi:terminate(Connection)
        end),
        try
            {Worker, Guardian} = pending_helpers(),
            WorkerMonitor = monitor(process, Worker),
            GuardianMonitor = monitor(process, Guardian),
            try
                %% Freeze the caller so its 100ms timer cannot win this race.
                true = erlang:suspend_process(Caller),
                exit(Caller, kill),
                await_down(Caller, CallerMonitor),
                await_down(Worker, WorkerMonitor),
                await_down(Guardian, GuardianMonitor),
                false = is_process_alive(Worker),
                false = is_process_alive(Guardian),
                {ok, nil}
            after
                demonitor(WorkerMonitor, [flush]),
                demonitor(GuardianMonitor, [flush])
            end
        after
            stop(Caller),
            demonitor(CallerMonitor, [flush]),
            ok = sys:resume(gun_conns_sup),
            stop(Connection)
        end
    end).

%% Observe the blocked real supervisor call. The calling worker is linked only
%% to its guardian; observing that link avoids production-only testing seams.
pending_helpers() ->
    pending_helpers(erlang:monotonic_time(millisecond) + 1000).

pending_helpers(Deadline) ->
    {messages, Messages} = process_info(whereis(gun_conns_sup), messages),
    case [Worker || {'$gen_call', {Worker, _}, {terminate_child, _}} <- Messages,
            is_pid(Worker), is_process_alive(Worker)] of
        [Worker | _] ->
            {links, [Guardian]} = process_info(Worker, links),
            {Worker, Guardian};
        [] ->
            true = erlang:monotonic_time(millisecond) < Deadline,
            receive after 1 -> pending_helpers(Deadline) end
    end.

with_stalled_tls(Callback) ->
    with_logs(<<"clean">>, fun() ->
        {ok, _} = application:ensure_all_started(ssl),
        {ok, Listener} = gen_tcp:listen(0, [binary, {active, false},
            {ip, {127, 0, 0, 1}}, {reuseaddr, true}]),
        {ok, {_, Port}} = inet:sockname(Listener),
        {Server, Monitor} = spawn_monitor(fun() ->
            {ok, Socket} = gen_tcp:accept(Listener, 2000),
            try
                %% ClientHello proves Gun reached a blocking TLS handshake.
                {ok, _} = gen_tcp:recv(Socket, 0, 2000),
                {error, closed} = gen_tcp:recv(Socket, 0, 2000)
            after gen_tcp:close(Socket)
            end
        end),
        Before = supervisor:which_children(gun_conns_sup),
        try
            Result = Callback(Port),
            receive
                {'DOWN', Monitor, process, Server, normal} -> ok;
                {'DOWN', Monitor, process, Server, Reason} -> error({tls_peer, Reason})
            after 2000 -> error(stalled_tls_not_released)
            end,
            Before = supervisor:which_children(gun_conns_sup),
            Result
        after
            gen_tcp:close(Listener),
            stop(Server),
            demonitor(Monitor, [flush])
        end
    end).

%% A synchronous logger handler captures supervisor reports and warnings.
%% The supervisor call after cleanup is a barrier for its queued exit reports.
with_logs(Mode, Callback) ->
    Tag = make_ref(),
    {monitors, Monitors} = process_info(self(), monitors),
    {links, Links} = process_info(self(), links),
    {trap_exit, TrapExit} = process_info(self(), trap_exit),
    ok = logger:add_handler(gluegun_terminate_capture, ?MODULE,
        #{level => all, config => #{owner => self(), tag => Tag}}),
    try
        Result = Callback(),
        supervisor:which_children(gun_conns_sup),
        {monitors, Monitors} = process_info(self(), monitors),
        {links, Links} = process_info(self(), links),
        {trap_exit, TrapExit} = process_info(self(), trap_exit),
        Events = drain_logs(Tag, []),
        Killed = [Report || #{msg := {report,
                #{label := {supervisor, child_terminated}, report := Report}}} <- Events,
            proplists:get_value(reason, Report) =:= killed],
        [] = Killed,
        Warnings = [Args || #{level := warning, msg := {Format, Args}} <- Events,
            Format =:= "Gluegun connection supervisor-stop cleanup failed: ~p"],
        case Mode of
            <<"failure">> -> [[{stopped, {error, not_found}}]] = Warnings;
            _ -> [] = Warnings
        end,
        Result
    after
        logger:remove_handler(gluegun_terminate_capture),
        drain_logs(Tag, [])
    end.

log(Event, #{config := #{owner := Owner, tag := Tag}}) ->
    Owner ! {terminate_log, Tag, Event},
    ok.

drain_logs(Tag, Acc) ->
    receive {terminate_log, Tag, Event} -> drain_logs(Tag, [Event | Acc])
    after 0 -> Acc
    end.

assert_no_private_mail() ->
    {messages, Messages} = process_info(self(), messages),
    [] = [Message || Message <- Messages, is_tuple(Message),
        lists:member(element(1, Message), ['DOWN', 'EXIT', dispose, helpers,
            gun_ws, gun_down, gun_push])],
    ok.

stop(Pid) ->
    Monitor = monitor(process, Pid),
    exit(Pid, kill),
    await_down(Pid, Monitor).

await_down(Pid, Monitor) ->
    receive {'DOWN', Monitor, process, Pid, _} -> ok
    after 1000 -> error({process_not_reaped, Pid})
    end.
