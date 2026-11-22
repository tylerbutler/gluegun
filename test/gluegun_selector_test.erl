-module(gluegun_selector_test).

%% Typed GunMessage constructors: callers never need Dynamic or unsafe casts.
%% Protocol/reason inputs are Gleam Strings; unknown protocol strings remain
%% invalid wire values instead of creating atoms.
-export([
    connection/0, other_connection/0, stream/0, send_message/1,
    up/2, down/4, tunnel_up/3, stream_error/3, connection_error/2,
    frame/3, response/2, invalid_identity/0, malformed_frame/2,
    tunnel_stream/1, malformed_killed_streams/1,
    malformed_protocol/1, malformed_response/2,
    with_unselected/1, with_http_disconnect/1, isolated/1, assert_alive/1
]).

connection() -> self().

%% An unlinked, immediately exiting process supplies a distinct valid pid.
%% No monitor, mailbox traffic, or live resource remains to clean up.
other_connection() -> spawn(fun() -> ok end).

stream() -> make_ref().

assert_alive(Pid) ->
    true = is_process_alive(Pid),
    nil.

%% (() -> Nil) -> Nil. Give selector regressions a fresh mailbox, not a
%% forwarding process. Transfer only the callback outcome with an exact ref.
%% On callback failure the worker exits abnormally to tear down linked
%% resources, then the parent re-raises the original exception and stack.
isolated(Callback) ->
    Parent = self(),
    Ref = make_ref(),
    {Worker, Monitor} = spawn_monitor(fun() ->
        try
            nil = Callback(),
            Parent ! {Ref, {ok, nil}}
        catch Class:Reason:Stack ->
            Parent ! {Ref, {exception, Class, Reason, Stack}},
            exit({isolated_callback_failed, Ref})
        end
    end),
    try
        receive
            {'DOWN', Monitor, process, Worker, ExitReason} ->
                %% The worker's reply precedes its DOWN signal.
                receive
                    {Ref, {ok, nil}} when ExitReason =:= normal -> nil;
                    {Ref, {exception, Class, Reason, Stack}} ->
                        erlang:raise(Class, Reason, Stack)
                after 0 ->
                    error({isolated_process_failed, ExitReason})
                end
        after 5000 ->
            error(isolated_callback_timeout)
        end
    after
        try stop_fixture_process(Worker, Monitor)
        after
            receive {Ref, _} -> ok after 0 -> ok end
        end
    end.

send_message(Raw) ->
    self() ! Raw,
    nil.

up(Pid, Protocol) -> {gun_up, Pid, gun_protocol(Protocol)}.

down(Pid, Protocol, Reason, Killed) ->
    {gun_down, Pid, gun_protocol(Protocol), Reason, Killed}.

tunnel_up(Pid, Stream, Protocol) ->
    {gun_tunnel_up, Pid, Stream, gun_protocol(Protocol)}.

stream_error(Pid, Stream, Reason) -> {gun_error, Pid, Stream, Reason}.

connection_error(Pid, Reason) -> {gun_error, Pid, Reason}.

%% Input is message.Frame, not an opaque raw GunFrame. Inbound Gun uses a
%% different constructor for CloseWithReason, so convert that tag explicitly.
frame(Pid, Stream, {close_with_reason, Code, Reason}) ->
    {gun_ws, Pid, Stream, {close, Code, Reason}};
frame(Pid, Stream, Frame) ->
    {gun_ws, Pid, Stream, Frame}.

response(Pid, Stream) ->
    gluegun_ffi_test:mailbox_response_message(Pid, Stream, fin, 200, []).

invalid_identity() -> {gun_ws, not_a_pid, make_ref(), close}.

malformed_frame(Pid, Stream) -> {gun_ws, Pid, Stream, {text, <<255>>}}.

%% Reports retention and consumes the fixture so no mailbox residue remains.
message_retained(Raw) ->
    receive
        Raw -> true
    after 0 ->
        false
    end.

cleanup_message(Raw) ->
    receive
        Raw -> cleanup_message(Raw)
    after 0 ->
        nil
    end.

%% (() -> Nil) -> Result(Nil, GluegunError).
%% The callback exercises the real Gleam selector. Afterwards all three exact
%% fixtures must still be in the caller mailbox. Cleanup runs on success,
%% assertion failure, and callback exceptions without consuming other traffic.
with_unselected(Callback) ->
    Token = make_ref(),
    Unsupported = {gun_ws, self(), make_ref(), close, Token},
    Application = {selector_fixture_application, Token},
    Down = {'DOWN', Token, process, self(), normal},
    Messages = [Unsupported, Application, Down],
    lists:foreach(fun send_message/1, Messages),
    try
        nil = Callback(),
        Retained = [message_retained(Raw) || Raw <- Messages],
        case lists:all(fun(Value) -> Value end, Retained) of
            true -> {ok, nil};
            false -> {error, {invalid_message, <<"Selector consumed unrelated mailbox traffic">>}}
        end
    after
        lists:foreach(fun cleanup_message/1, Messages)
    end.

%% (Int -> Result(Nil, GluegunError)) -> Result(Nil, GluegunError).
%% The callback owns the real Gun connection, including retry/shutdown policy.
%% This fixture owns only its loopback listener, HTTP peer, and exact monitor.
with_http_disconnect(Callback) ->
    case gen_tcp:listen(0, [binary, {active, false}, {ip, {127, 0, 0, 1}},
            {reuseaddr, true}]) of
        {error, Reason} -> fixture_error({http_listen, Reason});
        {ok, Listener} ->
            try
                {ok, {_, Port}} = inet:sockname(Listener),
                {Peer, Monitor} = spawn_monitor(fun() -> http_disconnect(Listener) end),
                try
                    case Callback(Port) of
                        {error, _} = Error -> Error;
                        {ok, nil} ->
                            receive
                                {'DOWN', Monitor, process, Peer, normal} -> {ok, nil};
                                {'DOWN', Monitor, process, Peer, Reason} ->
                                    fixture_error({http_peer_failed, Reason})
                            after 3000 ->
                                fixture_error(http_peer_timeout)
                            end
                    end
                after
                    stop_http_peer(Peer, Monitor)
                end
            after
                gen_tcp:close(Listener)
            end
    end.

http_disconnect(Listener) ->
    {ok, Socket} = gen_tcp:accept(Listener, 3000),
    try
        Deadline = erlang:monotonic_time(millisecond) + 3000,
        http_headers(Socket, <<>>, Deadline),
        ok = gen_tcp:send(Socket, <<"HTTP/1.1 200 OK\r\n",
            "Connection: close\r\nContent-Length: 0\r\n\r\n">>)
    after
        gen_tcp:close(Socket)
    end.

http_headers(Socket, Acc, Deadline) when byte_size(Acc) < 16384 ->
    case binary:match(Acc, <<"\r\n\r\n">>) of
        nomatch ->
            Remaining = max(0, Deadline - erlang:monotonic_time(millisecond)),
            {ok, Data} = gen_tcp:recv(Socket, 0, Remaining),
            http_headers(Socket, <<Acc/binary, Data/binary>>, Deadline);
        _ -> ok
    end.

stop_http_peer(Peer, Monitor) ->
    stop_fixture_process(Peer, Monitor).

stop_fixture_process(Pid, Monitor) ->
    try
        case is_process_alive(Pid) of
            true ->
                exit(Pid, kill),
                receive
                    {'DOWN', Monitor, process, Pid, _} -> ok
                after 1000 ->
                    error(peer_cleanup_timeout)
                end;
            false -> ok
        end
    after
        erlang:demonitor(Monitor, [flush])
    end.

fixture_error(Reason) ->
    {error, {erlang_error, gleam@string:inspect(Reason)}}.

%% List(Stream) -> Stream, for valid and empty/malformed CONNECT identities.
tunnel_stream(Refs) -> Refs.

%% Connection -> GunMessage: lifecycle list validation cannot be bypassed.
malformed_killed_streams(Pid) -> {gun_down, Pid, http, closed, [not_a_stream]}.

malformed_protocol(Pid) -> {gun_up, Pid, unsupported_protocol}.

malformed_response(Pid, Stream) -> {gun_response, Pid, Stream, fin, bad_status, []}.

gun_protocol(<<"http">>) -> http;
gun_protocol(<<"http2">>) -> http2;
gun_protocol(<<"ws">>) -> ws;
gun_protocol(<<"raw">>) -> raw;
gun_protocol(<<"socks">>) -> socks;
gun_protocol(Other) -> Other.
