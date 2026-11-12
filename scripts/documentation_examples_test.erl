-module(documentation_examples_test).
-export([main/0, open/3, terminate/1]).

%% Test-only FFI: ConnectOptions stays opaque and goes through public builders.
%% Connection is a Gun pid, Result uses {ok, _}/{error, _}, Nil is nil,
%% Http1/Tcp/Tls are http1/tcp/tls, and GluegunError constructors use the
%% snake_case tags below. No dynamic values or casts escape into Gleam.
%%
%% Run all calls in this same owner process, not a fresh process per example.
%% The extractor should shorten the examples' 5000ms literal to 200ms (or
%% 50ms); the independent TLS handshake limit must outlive await_up.
main() ->
    {ok, _} = application:ensure_all_started(gun),
    {ok, _} = application:ensure_all_started(ssl),
    undefined = get(documentation_context),
    put(documentation_history, []),
    Baseline = children(),
    try
        lists:foreach(fun({Module, Function}) ->
            lists:foreach(fun(Mode) ->
                lists:foreach(fun(_) ->
                    Original = iteration(Module, Function, Mode, false, Baseline),
                    Injected = iteration(Module, Function, Mode, true, Baseline),
                    assert_precedence(Mode, Original, Injected)
                end, lists:seq(1, 3))
            end, [success, request_error, readiness])
        end, [{doc_basic, main}, {doc_quick_start, main},
            {doc_http2, get_over_http2}, {doc_http2_guide, get_over_http2},
            {doc_facade, fetch},
            {doc_landing, main}]),
        assert_released(get(documentation_history), Baseline),
        io:format("Documentation lifecycle: 108 calls passed in one owner.~n"),
        nil
    after
        erase(documentation_context),
        erase(documentation_history)
    end.

%% Host/port from the snippet are deliberately ignored: no public network.
open(Options, _Host, _Port) ->
    #{mode := Mode, port := Port} = get(documentation_context),
    {ok, ConnectTimeout} = gluegun@connection:milliseconds(1000),
    {ok, HandshakeTimeout} = gluegun@connection:milliseconds(10000),
    Options1 = gluegun@connection:with_protocols(Options, [http1]),
    Options2 = gluegun@connection:with_connect_timeout(Options1, ConnectTimeout),
    Options3 = case Mode of
        readiness ->
            Tls = gluegun@connection:with_transport(Options2, tls),
            Insecure = gluegun@connection:with_tls_options(Tls, gluegun@tls:insecure()),
            gluegun@connection:with_tls_handshake_timeout(Insecure, HandshakeTimeout);
        _ ->
            gluegun@connection:with_transport(Options2, tcp)
    end,
    case gluegun@connection:open(Options3, <<"127.0.0.1">>, Port) of
        {ok, Pid} = Opened ->
            put(documentation_opened, [Pid | get(documentation_opened)]),
            put(documentation_history, [Pid | get(documentation_history)]),
            Opened;
        {error, _} = Error -> Error
    end.

%% Never fake teardown: even injected failure happens AFTER real termination.
%% Preserve a real cleanup error instead of hiding it with the injected one.
terminate(Connection) ->
    put(documentation_terminated, [Connection | get(documentation_terminated)]),
    Result = gluegun@connection:terminate(Connection),
    case {Result, get(documentation_context)} of
        {{ok, nil}, #{inject := true}} -> cleanup_error();
        _ -> Result
    end.

cleanup_error() ->
    {error, {invalid_options, <<"documentation injected cleanup failure">>}}.

iteration(Module, Function, Mode, Inject, Baseline) ->
    {ok, Listener} = gen_tcp:listen(0, [binary, {active, false},
        {ip, {127, 0, 0, 1}}, {reuseaddr, true}]),
    try
        {ok, {_, Port}} = inet:sockname(Listener),
        Owner = self(),
        Ref = make_ref(),
        {Peer, Monitor} = spawn_monitor(fun() ->
            peer(Listener, Owner, Ref, Mode)
        end),
        put(documentation_context, #{mode => Mode, port => Port, inject => Inject}),
        put(documentation_opened, []),
        put(documentation_terminated, []),
        self() ! {documentation_sentinel, Ref},
        try
            Result = apply(Module, Function, []),
            %% Check BEFORE fallback cleanup, including when a snippet forgot
            %% terminate but Gun happened to exit on its own.
            [Connection] = get(documentation_opened),
            [Connection] = get(documentation_terminated),
            assert_released(get(documentation_history), Baseline),
            await_peer(Peer, Monitor),
            receive {documentation_peer, Ref, Mode} -> ok
            after 0 -> error({peer_not_exercised, Module, Mode}) end,
            receive {documentation_sentinel, Ref} -> ok
            after 0 -> error(application_message_consumed) end,
            assert_result(Mode, Inject, Result),
            Result
        catch
            Class:Reason:Stack ->
                erlang:raise(Class, {documentation_example_failed,
                    Module, Function, Mode, Inject, Reason}, Stack)
        after
            %% Failure-only safety net. Assertions above must never depend on it.
            lists:foreach(fun(Pid) ->
                {ok, nil} = gluegun@connection:terminate(Pid)
            end, get(documentation_opened)),
            stop_peer(Peer, Monitor),
            receive {documentation_peer, Ref, _} -> ok after 0 -> ok end,
            receive {documentation_sentinel, Ref} -> ok after 0 -> ok end,
            erase(documentation_context),
            erase(documentation_opened),
            erase(documentation_terminated)
        end
    after
        ok = gen_tcp:close(Listener)
    end.

assert_result(success, false, {ok, _}) -> ok;
assert_result(success, true, Result) ->
    Expected = cleanup_error(),
    Expected = Result,
    ok;
assert_result(request_error, _, {error, {decode_error, Reason}})
        when is_binary(Reason) -> ok;
assert_result(readiness, _, {error, timeout}) -> ok;
assert_result(Mode, Inject, Result) ->
    error({unexpected_result, Mode, Inject, Result}).

assert_precedence(success, {ok, _}, Injected) ->
    Expected = cleanup_error(),
    Expected = Injected,
    ok;
assert_precedence(_, Original, Injected) ->
    %% The invalid response header and readiness timeout are deterministic.
    %% Compare the WHOLE original error, not merely its constructor.
    Original = Injected,
    ok.

assert_released(Pids, Baseline) ->
    [] = [Pid || Pid <- Pids, is_process_alive(Pid)],
    await_children(Baseline, erlang:monotonic_time(millisecond) + 1000),
    {messages, Messages} = process_info(self(), messages),
    [] = [Message || Message <- Messages, connection_message(Message, Pids)],
    ok.

connection_message({'DOWN', _, process, Pid, _}, Pids) ->
    lists:member(Pid, Pids);
connection_message(Message, Pids) when is_tuple(Message), tuple_size(Message) >= 2 ->
    lists:member(element(2, Message), Pids);
connection_message(_, _) -> false.

children() ->
    %% Gun 2.2 split out gun_conns_sup; 2.1 supervises connections in gun_sup.
    Supervisor = case whereis(gun_conns_sup) of
        undefined -> gun_sup;
        _ -> gun_conns_sup
    end,
    lists:sort(supervisor:which_children(Supervisor)).

await_children(Baseline, Deadline) ->
    case children() of
        Baseline -> ok;
        Remaining ->
            case erlang:monotonic_time(millisecond) < Deadline of
                true ->
                    erlang:yield(),
                    await_children(Baseline, Deadline);
                false -> error({retained_supervisor_children, Remaining})
            end
    end.

peer(Listener, Owner, Ref, Mode) ->
    {ok, Socket} = gen_tcp:accept(Listener, 10000),
    try
        Deadline = erlang:monotonic_time(millisecond) + 10000,
        case Mode of
            readiness ->
                %% Accept TCP but never answer the actual TLS ClientHello.
                {ok, <<22, _/binary>>} = recv(Socket, Deadline);
            _ ->
                read_headers(Socket, <<>>, Deadline),
                Response = case Mode of
                    success ->
                        <<"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok">>;
                    request_error ->
                        %% Invalid UTF-8 HEADER fails collection for every
                        %% snippet, even those which swallow body_text errors.
                        <<"HTTP/1.1 200 OK\r\nX-Invalid: ", 255,
                            "\r\nContent-Length: 2\r\n\r\nok">>
                end,
                ok = gen_tcp:send(Socket, Response)
        end,
        Owner ! {documentation_peer, Ref, Mode},
        %% Keep the peer open until the example releases its connection.
        %% No success-shaped timeout: failure to close must fail the test.
        await_closed(Socket, Deadline)
    after
        ok = gen_tcp:close(Socket)
    end.

read_headers(Socket, Acc, Deadline) when byte_size(Acc) =< 16384 ->
    case binary:match(Acc, <<"\r\n\r\n">>) of
        nomatch ->
            {ok, Data} = recv(Socket, Deadline),
            read_headers(Socket, <<Acc/binary, Data/binary>>, Deadline);
        _ -> ok
    end;
read_headers(_, _, _) -> error(request_headers_too_large).

recv(Socket, Deadline) ->
    Remaining = Deadline - erlang:monotonic_time(millisecond),
    case Remaining > 0 of
        true -> gen_tcp:recv(Socket, 0, Remaining);
        false -> error(peer_deadline_exceeded)
    end.

await_closed(Socket, Deadline) ->
    case recv(Socket, Deadline) of
        {error, closed} -> ok;
        {ok, _} -> await_closed(Socket, Deadline);
        Other -> error({peer_expected_connection_close, Other})
    end.

await_peer(Peer, Monitor) ->
    receive
        {'DOWN', Monitor, process, Peer, normal} -> ok;
        {'DOWN', Monitor, process, Peer, Reason} -> error({peer_failed, Reason})
    after 2000 -> error(peer_exit_timeout)
    end.

stop_peer(Peer, Monitor) ->
    try
        case is_process_alive(Peer) of
            false -> ok;
            true ->
                exit(Peer, kill),
                receive {'DOWN', Monitor, process, Peer, _} -> ok
                after 2000 -> error(peer_cleanup_timeout) end
        end
    after
        erlang:demonitor(Monitor, [flush])
    end.
