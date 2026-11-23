#!/usr/bin/env escript
%%! +S 2:2
-mode(compile).

%% Measurement only. Run from any directory after `gleam build` (test helpers
%% must be compiled). All peers are loopback, owned here, and time bounded.
%% No production FFI, dependencies, filesystem output, or persistent service.
-include_lib("public_key/include/public_key.hrl").
-define(LIMIT, 3000).
-define(SUITE_LIMIT, 90000).

main([]) ->
    Root = filename:dirname(filename:dirname(filename:absname(escript:script_name()))),
    true = code:add_paths(filelib:wildcard(filename:join(Root, "build/dev/erlang/*/ebin"))) =:= ok,
    try
        {ok, _} = application:ensure_all_started(gun),
        {ok, _} = application:ensure_all_started(ssl),
        Started = erlang:monotonic_time(microsecond),
        InitialMonitors = element(2, process_info(self(), monitors)),
        InitialPorts = network_ports(),
        %% Guard even synchronous OS CA loading. On expiry the isolated escript
        %% VM exits nonzero, releasing its peers/sockets; no live service exists.
        {SuiteGuard, SuiteMonitor} = spawn_monitor(fun() ->
            receive after ?SUITE_LIMIT ->
                emit(failure, #{reason => suite_timeout, limit_ms => ?SUITE_LIMIT}),
                halt(1)
            end
        end),
        emit(runtime, #{otp => erlang:system_info(otp_release),
            erts => erlang:system_info(version), system => erlang:system_info(system_version),
            schedulers => erlang:system_info(schedulers_online),
            word_bytes => erlang:system_info(wordsize), root => Root}),
        lists:foreach(fun dependency/1, [gun, cow_http, gluegun_ffi, gluegun@client,
            gluegun_client_test, runtime_regression_test]),
        emit(contract, #{suite_limit_ms => ?SUITE_LIMIT, setup_ms => ?LIMIT, barrier_guard_ms => 100,
            collection_chunks => 32, chunk_bytes => 256, backlog => 200,
            synthetic_chunks => 4000, repeats => 3, tls_connections => 3,
            note => <<"Raw samples; no inferred CA gains. Barrier orders processed events, "
                "not future delivery or socket-read recovery. No negative-credit fixture. "
                "Referenced binary bytes are not unique allocations; refcount histograms "
                "do not identify which processes share binaries.">>}),
        cancellation(),
        collection(),
        certificates(),
        headers(),
        stop(SuiteGuard, SuiteMonitor),
        InitialMonitors = element(2, process_info(self(), monitors)),
        InitialPorts = network_ports(),
        emit(result, #{status => passed, owned_network_ports_remaining => 0,
            owned_monitors_remaining => 0,
            elapsed_us => erlang:monotonic_time(microsecond) - Started})
    catch Class:Reason:Stack ->
        emit(failure, #{class => Class, reason => Reason, stack => Stack}),
        halt(1)
    end;
main(_) ->
    io:format("Usage: escript scripts/measure_beam.escript~n"),
    halt(2).

emit(Tag, Data) -> io:format("~p ~0tp.~n", [Tag, Data]).

dependency(Module) ->
    {module, Module} = code:ensure_loaded(Module),
    App = case Module of gun -> gun; cow_http -> cowlib; _ -> gluegun end,
    _ = application:load(App),
    emit(loaded, #{module => Module, beam => code:which(Module),
        md5 => Module:module_info(md5), application => App,
        version => application:get_key(App, vsn)}).

measure(Tag, Fun) ->
    {reductions, R0} = process_info(self(), reductions),
    {garbage_collection, G0} = process_info(self(), garbage_collection),
    T0 = erlang:monotonic_time(microsecond),
    Value = Fun(),
    Elapsed = erlang:monotonic_time(microsecond) - T0,
    {reductions, R1} = process_info(self(), reductions),
    {garbage_collection, G1} = process_info(self(), garbage_collection),
    emit(sample, #{workload => Tag, elapsed_us => Elapsed, reductions => R1 - R0,
        gc_minor_before => proplists:get_value(minor_gcs, G0),
        gc_minor_after => proplists:get_value(minor_gcs, G1), output => summary(Value)}),
    Value.

summary(B) when is_binary(B) -> #{bytes => byte_size(B), sha256 => crypto:hash(sha256, B)};
summary(T) when is_tuple(T) -> list_to_tuple([summary(V) || V <- tuple_to_list(T)]);
summary(M) when is_map(M) ->
    maps:map(fun(tls_opts, V) -> #{option_count => length(V)}; (_, V) -> summary(V) end, M);
summary(V) -> V.

%% Each regression is the existing compiled Gleam public test, so its asserts
%% check the real FFI representations as well as the native helper.
regression(Module, Function) ->
    _ = measure({regression, Module, Function}, fun() -> apply(Module, Function, []) end),
    emit(regression, #{module => Module, function => Function, status => passed}).

cancellation() ->
    {ok, nil} = gluegun_client_test:late_after_drain(),
    lists:foreach(fun(F) -> regression(client_test, F) end, [
        failed_stream_cleanup_defines_the_late_message_drain_race_test,
        rejected_push_before_headers_cancels_the_promised_stream_test,
        rejected_push_during_body_cancels_the_promised_stream_test,
        malformed_push_cancels_the_promised_stream_and_keeps_decode_error_test]),
    %% These real peers send delayed bytes after cancellation and then prove
    %% another response on the same socket completes with no failed-stream mail.
    lists:foreach(fun(B) ->
        {ok, nil} = measure({real_delayed_after_cancel, B},
            fun() -> gluegun_client_test:delayed_response(B) end)
    end, [false, true]),
    lists:foreach(fun(Mode) ->
        with_tcp(fun(Socket, Owner) -> cancel_peer(Socket, Owner) end,
            fun(Port, Peer) ->
                with_gun(Port, #{transport => tcp}, fun(Conn) ->
                    Stream = gun:get(Conn, "/"),
                    {response, nofin, 200, _} = gun:await(Conn, Stream, ?LIMIT),
                    ok = sys:suspend(Conn, ?LIMIT),
                    try
                        Peer ! send_body,
                        await_peer(Peer, sent),
                        wait_tcp_queued(Conn, deadline()),
                        case Mode of
                            immediate ->
                                {ok, nil} = measure(cancel_immediate_drain,
                                    fun() -> gluegun_ffi:cleanup_stream(Conn, Stream) end),
                                ok = sys:resume(Conn, ?LIMIT),
                                {data, fin, <<"late-real-body">>} =
                                    gun:await(Conn, Stream, ?LIMIT),
                                emit(cancel_evidence, #{mode => Mode,
                                    late_messages => 1, body => <<"late-real-body">>});
                            barrier ->
                                %% Controlled blocked Gun: guard terminates only
                                %% the call worker, never the connection.
                                timeout = measure(cancel_suspended_barrier_guard,
                                    fun() -> barrier(Conn, Stream, 100) end),
                                ok = sys:resume(Conn, ?LIMIT),
                                {ok, _} = measure(cancel_resumed_barrier,
                                    fun() -> barrier(Conn, Stream, ?LIMIT) end),
                                %% Use production drain to retain recursive
                                %% promised-stream discovery (not gun:flush/1).
                                {ok, nil} = gluegun_ffi:cleanup_stream(Conn, Stream),
                                {error, timeout} = gun:await(Conn, Stream, 0),
                                emit(cancel_evidence, #{mode => Mode,
                                    queued_body_drained => true, guarded => true})
                        end
                    after
                        %% Resume on every failure, before terminating Gun.
                        _ = sys:resume(Conn, ?LIMIT)
                    end
                end)
            end)
    end, [immediate, barrier]).

%% Same worker sends cancel and call: their ordering is not dependent on
%% messages from different senders. Original stream owner remains the caller.
%% Worker owns its call mailbox; kill + DOWN removes late replies and monitors.
barrier(Conn, Stream, Timeout) ->
    Parent = self(),
    Ref = make_ref(),
    {Pid, Mon} = spawn_monitor(fun() ->
        ok = gun:cancel(Conn, Stream),
        Parent ! {Ref, gun:stream_info(Conn, Stream)}
    end),
    try
        receive
            {Ref, Result} -> Result;
            {'DOWN', Mon, process, Pid, Why} -> error({barrier_worker_failed, Why})
        after Timeout -> timeout
        end
    after
        stop(Pid, Mon),
        receive {Ref, _} -> ok after 0 -> ok end
    end.

cancel_peer(Socket, Owner) ->
    read_request(Socket),
    ok = gen_tcp:send(Socket, <<"HTTP/1.1 200 OK\r\nContent-Length: 14\r\n\r\n">>),
    receive send_body -> ok after ?LIMIT -> error(send_body_timeout) end,
    ok = gen_tcp:send(Socket, <<"late-real-body">>),
    Owner ! {self(), sent},
    receive stop -> ok after ?LIMIT -> error(peer_stop_timeout) end.

wait_tcp_queued(Conn, Deadline) ->
    {messages, Messages} = process_info(Conn, messages),
    case lists:any(fun
        ({tcp, _, _}) -> true;
        (_) -> false
    end, Messages) of
        true -> ok;
        false ->
            true = erlang:monotonic_time(millisecond) < Deadline,
            receive after 1 -> ok end,
            wait_tcp_queued(Conn, Deadline)
    end.

collection() ->
    Chunk = chunk(),
    chunk_selfcheck(Chunk),
    lists:foreach(fun(Repeat) ->
        Results = [collect_real(Mode, Repeat, Chunk) || Mode <- [per_message, shared, gluegun]],
        [Body, Body, Body] = Results,
        Synthetic = [collect_synthetic(Mode, Repeat, Chunk) || Mode <- [per_message, shared]],
        [Full, Full] = Synthetic
    end, lists:seq(1, 3)).

chunk() -> binary:copy(<<"0123456789abcdef">>, 16).
expected(N) -> binary:copy(chunk(), N).

check_chunk(Chunk, Chunk) -> ok;
check_chunk(Data, Chunk) ->
    error({unexpected_chunk, byte_size(Chunk), byte_size(Data)}).

chunk_selfcheck(Chunk) ->
    Full = binary:copy(Chunk, 2),
    <<First:128/binary, Second:384/binary>> = Full,
    Split = [First, Second],
    2 = length(Split),
    Full = iolist_to_binary(Split),
    ok = check_chunk(Chunk, Chunk),
    lists:foreach(fun(Data) ->
        Size = byte_size(Data),
        try check_chunk(Data, Chunk) of
            ok -> error(split_chunk_accepted)
        catch error:{unexpected_chunk, 256, Size} -> ok
        end
    end, Split),
    emit(selfcheck, #{workload => chunk_validation, split_bytes => [128, 384],
        equal_full_body => true, equal_count => true, rejected_chunks => 2,
        status => passed}).

collect_real(Mode, Repeat, Chunk) ->
    with_tcp(fun(Socket, Owner) -> collection_peer(Socket, Owner, 32, Chunk) end,
        fun(Port, Peer) ->
            with_gun(Port, #{transport => tcp}, fun(Conn) ->
                Token = backlog(200),
                Monitors = lists:sort(element(2, process_info(self(), monitors))),
                try
                    {Body, Count} = measure({real_collection, Mode, Repeat}, fun() ->
                        run_collection(Mode, Conn, Peer, Chunk)
                    end),
                    32 = Count,
                    Body = expected(32),
                    await_peer(Peer, completed),
                    emit(collection_evidence, #{mode => Mode, repeat => Repeat,
                        actual_data_messages => Count, body_bytes => byte_size(Body),
                        monitor_calls_known_from_source => case Mode of shared -> 1; _ -> 33 end,
                        demonitor_calls_known_from_source => case Mode of shared -> 1; _ -> 33 end,
                        instrumentation => <<"explicit known calls, not tracing">>,
                        pacing => <<"peer waits for each actual gun_data before next chunk">>}),
                    Body
                after
                    clear_backlog(Token, 200),
                    Monitors = lists:sort(element(2, process_info(self(), monitors)))
                end
            end)
        end).

run_collection(gluegun, Conn, Peer, Chunk) ->
    %% Real compiled client state machine and FFI decoder, instrumented only
    %% to acknowledge each actual body message to the finite loopback peer.
    put(chunk_count, 0),
    try
        Await = fun(C, S, T) ->
            Message = gluegun_ffi:client_await(C, S, T),
            case Message of
                {ok, {data, _, Data}} ->
                    ok = check_chunk(Data, Chunk),
                    put(chunk_count, get(chunk_count) + 1),
                    Peer ! next;
                _ -> ok
            end,
            Message
        end,
        {ok, Response} = gluegun@client:get_with(Conn, <<"/">>, [],
            {milliseconds, ?LIMIT}, fun gluegun@request:request/6, Await),
        {gluegun@response:body(Response), get(chunk_count)}
    after erase(chunk_count) end;
run_collection(Mode, Conn, Peer, Chunk) ->
    Stream = gun:get(Conn, "/"),
    with_await(Mode, Conn, fun(Await) ->
        {response, nofin, 200, _} = Await(Stream),
        collect_data(Await, Stream, Peer, [], 0, Chunk)
    end).

with_await(per_message, Conn, Fun) ->
    Fun(fun(S) -> gun:await(Conn, S, ?LIMIT) end);
with_await(shared, Conn, Fun) ->
    Mon = monitor(process, Conn),
    try Fun(fun(S) -> gun:await(Conn, S, ?LIMIT, Mon) end)
    after demonitor(Mon, [flush]) end.

collect_data(Await, Stream, Peer, Acc, Count, Chunk) ->
    {data, Fin, Data} = Await(Stream),
    ok = check_chunk(Data, Chunk),
    case Peer of none -> ok; _ -> Peer ! next end,
    case Fin of
        fin -> {iolist_to_binary(lists:reverse([Data | Acc])), Count + 1};
        nofin -> collect_data(Await, Stream, Peer, [Data | Acc], Count + 1, Chunk)
    end.

collection_peer(Socket, Owner, N, Chunk) ->
    read_request(Socket),
    ok = gen_tcp:send(Socket, [<<"HTTP/1.1 200 OK\r\nContent-Length: ">>,
        integer_to_binary(N * byte_size(Chunk)), <<"\r\n\r\n">>]),
    lists:foreach(fun(_) ->
        ok = gen_tcp:send(Socket, Chunk),
        receive next -> ok after ?LIMIT -> error(chunk_ack_timeout) end
    end, lists:seq(1, N)),
    Owner ! {self(), completed},
    receive stop -> ok after ?LIMIT -> error(peer_stop_timeout) end.

collect_synthetic(Mode, Repeat, Chunk) ->
    Conn = self(),
    Stream = make_ref(),
    Token = backlog(200),
    lists:foreach(fun(N) ->
        Fin = case N of 4000 -> fin; _ -> nofin end,
        self() ! {gun_data, Conn, Stream, Fin, Chunk}
    end, lists:seq(1, 4000)),
    try
        {Body, 4000} = measure({synthetic_collection, Mode, Repeat}, fun() ->
            with_await(Mode, Conn, fun(Await) ->
                collect_data(Await, Stream, none, [], 0, Chunk)
            end)
        end),
        Body = expected(4000),
        emit(collection_evidence, #{mode => Mode, synthetic => true,
            actual_data_messages => 4000, body_bytes => byte_size(Body),
            monitor_calls_known_from_source => case Mode of shared -> 1; _ -> 4000 end}),
        Body
    after clear_backlog(Token, 200) end.

backlog(N) ->
    Token = make_ref(),
    lists:foreach(fun(I) -> self() ! {backlog, Token, I} end, lists:seq(1, N)),
    Token.

clear_backlog(Token, N) ->
    lists:foreach(fun(I) ->
        receive {backlog, Token, I} -> ok after 0 -> error(backlog_lost) end
    end, lists:seq(1, N)).

certificates() ->
    %% Fresh escript VM: production cache must be cold, never erase a live cache.
    undefined = persistent_term:get(gluegun_system_cacerts, undefined),
    Certificate = public_key:pkix_test_data(#{
        root => [{digest, sha256}, {key, {rsa, 2048, 65537}}],
        intermediates => [],
        peer => [{digest, sha256}, {key, {rsa, 2048, 65537}}, {extensions, [
            #'Extension'{extnID = {2,5,29,17},
                extnValue = [{dNSName, "localhost"}], critical = false}]}]}),
    lists:foreach(fun(N) -> tls_connection(N, Certificate) end, lists:seq(1, 3)).

tls_connection(N, Certificate) ->
    Before = processes(),
    snapshot({tls_owner, N, before_defaults}, self()),
    BaseOptions = #{transport => tls, protocols => [http], retry => 0,
        connect_timeout => ?LIMIT, tls_handshake_timeout => ?LIMIT},
    %% Callback contains only the production operation. Measurement output,
    %% CA traversal and size reporting all happen after its timer stops.
    Options = measure({tls_defaults, N, case N of 1 -> cold; _ -> warm end}, fun() ->
        gluegun_ffi:apply_secure_tls_defaults("localhost", BaseOptions)
    end),
    snapshot({tls_owner, N, after_defaults}, self()),
    %% Actual production default injection above, then explicitly append local
    %% test trust. This is NOT an unmodified default-trust handshake.
    Tls0 = maps:get(tls_opts, Options),
    CA = proplists:get_value(cacerts, Tls0),
    FlatWords = erts_debug:flat_size(CA),
    emit(ca, #{connection => N, certificates => length(CA),
        flat_words => FlatWords,
        flat_bytes => FlatWords * erlang:system_info(wordsize),
        external_bytes => erlang:external_size(CA),
        cache_equal => CA =:= persistent_term:get(gluegun_system_cacerts),
        representation => <<"decoded system store; flat_size is not allocated process memory">>}),
    Tls = lists:keyreplace(cacerts, 1, Tls0,
        {cacerts, CA ++ proplists:get_value(cacerts, Certificate)}),
    emit(tls_contract, #{connection => N,
        trust => <<"production system defaults plus explicitly appended local test CA">>,
        cache => case N of 1 -> cold; _ -> warm end}),
    {ok, Listener} = ssl:listen(0, [binary, {active, false}, {ip, {127,0,0,1}},
        {reuseaddr, true} | Certificate]),
    {ok, {_, Port}} = ssl:sockname(Listener),
    Owner = self(),
    {Peer, Mon} = spawn_monitor(fun() -> tls_peer(Listener, Owner) end),
    try
        {ok, Conn} = gun:open("localhost", Port, Options#{tls_opts => Tls}),
        try
            await_peer(Peer, accepted),
            snapshot({tls_owner, N, before_handshake}, self()),
            snapshot({tls_gun, N, before_handshake}, Conn),
            tls_snapshots(N, before_handshake, Before, Peer, Conn),
            Peer ! handshake,
            {ok, http} = measure({tls_await_up, N},
                fun() -> gun:await_up(Conn, ?LIMIT) end),
            await_peer(Peer, established),
            snapshot({tls_owner, N, established}, self()),
            snapshot({tls_gun, N, established}, Conn),
            SSLPids = tls_snapshots(N, established, Before, Peer, Conn),
            Stream = gun:get(Conn, "/"),
            {response, nofin, 200, _} = gun:await(Conn, Stream, ?LIMIT),
            {ok, <<"tls-body">>} = gun:await_body(Conn, Stream, ?LIMIT),
            await_peer(Peer, completed),
            emit(tls_evidence, #{connection => N, body => <<"tls-body">>,
                ssl_processes_observed => SSLPids})
        after close_gun(Conn) end
    after
        ssl:close(Listener),
        stop(Peer, Mon)
    end,
    %% SSL supervisors may be shared; only connection workers are required dead.
    wait_tls_gone(Before, Peer, deadline()),
    snapshot({tls_owner, N, cleaned}, self()).

tls_peer(Listener, Owner) ->
    {ok, Socket0} = ssl:transport_accept(Listener, ?LIMIT),
    try
        Owner ! {self(), accepted},
        receive handshake -> ok after ?LIMIT -> error(handshake_gate_timeout) end,
        {ok, Socket} = ssl:handshake(Socket0, ?LIMIT),
        Owner ! {self(), established},
        {ok, _} = ssl:recv(Socket, 0, ?LIMIT),
        ok = ssl:send(Socket, <<"HTTP/1.1 200 OK\r\nContent-Length: 8\r\n\r\ntls-body">>),
        Owner ! {self(), completed},
        receive stop -> ok after ?LIMIT -> error(tls_stop_timeout) end
    after ssl:close(Socket0) end.

tls_workers(Before, Peer) ->
    [P || P <- processes() -- Before, P =/= Peer,
        begin
            case process_info(P, dictionary) of
                {dictionary, D} ->
                    case proplists:get_value('$initial_call', D) of
                        {ssl_gen_statem, _, _} -> true;
                        {tls_connection, _, _} -> true;
                        {tls_sender, _, _} -> true;
                        _ -> false
                    end;
                undefined -> false
            end
        end].

tls_snapshots(N, Stage, Before, Peer, Conn) ->
    Pids = tls_workers(Before, Peer),
    lists:foreach(fun(P) ->
        Role = ssl_role(P, Conn, Peer, Pids, []),
        snapshot({tls_ssl_worker, N, Stage, Role}, P)
    end, Pids),
    true = Pids =/= [],
    Pids.

%% Public process introspection only, not a cast of OTP's opaque SSL socket.
%% SSL state machines monitor their controlling owner; senders may monitor the
%% state machine. Unknown is explicit rather than attributing peer memory to Gun.
ssl_role(P, Conn, Peer, Pids, Seen) ->
    case lists:member(P, Seen) of
        true -> unknown;
        false ->
            {monitors, Monitors} = process_info(P, monitors),
            Targets = [T || {process, T} <- Monitors],
            case {lists:member(Conn, Targets), lists:member(Peer, Targets)} of
                {true, _} -> client;
                {_, true} -> local_peer;
                _ ->
                    Roles = [ssl_role(T, Conn, Peer, Pids, [P | Seen])
                        || T <- Targets, lists:member(T, Pids)],
                    case lists:usort(Roles -- [unknown]) of
                        [Role] -> Role;
                        _ -> unknown
                    end
            end
    end.

wait_tls_gone(Before, Peer, Deadline) ->
    case tls_workers(Before, Peer) of
        [] -> emit(cleanup, #{resource => ssl_connection_workers, status => gone});
        Pids ->
            true = erlang:monotonic_time(millisecond) < Deadline,
            receive after 10 -> ok end,
            _ = Pids,
            wait_tls_gone(Before, Peer, Deadline)
    end.

snapshot(Stage, Pid) ->
    Info = process_info(Pid, [heap_size, total_heap_size, memory, binary,
        reductions, message_queue_len, garbage_collection, current_function, monitors]),
    true = Info =/= undefined,
    Binaries = proplists:get_value(binary, Info),
    RefCounts = lists:foldl(fun({_, _, Count}, Acc) ->
        maps:update_with(Count, fun(N) -> N + 1 end, 1, Acc)
    end, #{}, Binaries),
    emit(memory, #{stage => Stage, pid => Pid,
        heap_words => proplists:get_value(heap_size, Info),
        total_heap_words => proplists:get_value(total_heap_size, Info),
        memory_bytes => proplists:get_value(memory, Info),
        reductions => proplists:get_value(reductions, Info),
        message_queue_len => proplists:get_value(message_queue_len, Info),
        gc_minor_gcs => proplists:get_value(minor_gcs,
            proplists:get_value(garbage_collection, Info)),
        current_function => proplists:get_value(current_function, Info),
        monitor_count => length(proplists:get_value(monitors, Info)),
        binary_reference_count => length(Binaries),
        binary_referenced_bytes => lists:sum([Size || {_, Size, _} <- Binaries]),
        binary_refcount_histogram => RefCounts}).

headers() ->
    lists:foreach(fun(F) -> regression(runtime_regression_test, F) end, [
        rejects_invalid_inbound_header_names_on_every_message_test,
        rejects_invalid_inbound_header_values_on_every_message_test,
        rejects_incomplete_inbound_utf8_on_every_message_test,
        rejects_malformed_inbound_header_pairs_on_every_message_test,
        rejects_nontext_inbound_header_values_on_every_message_test,
        preserves_valid_utf8_header_values_without_transcoding_test,
        rejects_invalid_utf8_response_headers_from_the_wire_test,
        rejects_invalid_utf8_trailers_from_the_wire_test]),
    emit(headers, #{status => resolved,
        source => <<"normalize_inbound_headers validates inbound_text(Name) before "
            "string:lowercase; no duplicate fix or timing claim">>}).

deadline() -> erlang:monotonic_time(millisecond) + ?LIMIT.

network_ports() ->
    lists:sort([P || P <- erlang:ports(),
        lists:member(erlang:port_info(P, name),
            [{name, "tcp_inet"}, {name, "udp_inet"}, {name, "tcp_inet6"}])]).

await_peer(Peer, Event) ->
    receive {Peer, Event} -> ok
    after ?LIMIT -> error({peer_event_timeout, Peer, Event}) end.

with_tcp(Serve, Fun) ->
    {ok, Listener} = gen_tcp:listen(0, [binary, {active, false}, {packet, http_bin},
        {ip, {127,0,0,1}}, {reuseaddr, true}, {nodelay, true}]),
    {ok, {_, Port}} = inet:sockname(Listener),
    Owner = self(),
    {Peer, Mon} = spawn_monitor(fun() ->
        {ok, Socket} = gen_tcp:accept(Listener, ?LIMIT),
        try Serve(Socket, Owner) after gen_tcp:close(Socket) end
    end),
    try Fun(Port, Peer)
    after
        gen_tcp:close(Listener),
        stop(Peer, Mon),
        {error, Closed} = inet:sockname(Listener),
        true = (Closed =:= closed orelse Closed =:= einval),
        emit(cleanup, #{resource => tcp_listener_and_peer, status => closed})
    end.

with_gun(Port, Options, Fun) ->
    {ok, Conn} = gun:open({127,0,0,1}, Port, Options#{protocols => [http],
        retry => 0, connect_timeout => ?LIMIT}),
    try
        {ok, http} = gun:await_up(Conn, ?LIMIT),
        Fun(Conn)
    after close_gun(Conn) end.

close_gun(Conn) ->
    Mon = monitor(process, Conn),
    gun:close(Conn),
    receive {'DOWN', Mon, process, Conn, _} -> ok
    after ?LIMIT -> stop(Conn, Mon) end,
    false = is_process_alive(Conn),
    gun:flush(Conn),
    emit(cleanup, #{resource => gun, pid => Conn, status => gone}).

stop(Pid, Mon) ->
    exit(Pid, kill),
    receive {'DOWN', Mon, process, Pid, _} -> ok
    after ?LIMIT ->
        case is_process_alive(Pid) of
            false -> demonitor(Mon, [flush]);
            true -> error({cleanup_timeout, Pid})
        end
    end,
    false = is_process_alive(Pid).

read_request(Socket) ->
    {ok, {http_request, 'GET', _, _}} = gen_tcp:recv(Socket, 0, ?LIMIT),
    read_headers(Socket, 0).

read_headers(Socket, N) when N < 100 ->
    case gen_tcp:recv(Socket, 0, ?LIMIT) of
        {ok, http_eoh} -> ok;
        {ok, {http_header, _, _, _, _}} -> read_headers(Socket, N + 1);
        Other -> error({request_headers, Other})
    end.
