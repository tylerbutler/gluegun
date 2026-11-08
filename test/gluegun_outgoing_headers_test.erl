-module(gluegun_outgoing_headers_test).

%% Gun 2.2 casts are synchronous sends to self() in these tests. No processes,
%% sockets, timers, or waits are needed. Correlate captures to the returned
%% stream; unrelated mailbox messages are left untouched.
-export([capture_request/1, capture_headers/1, capture_ws_upgrade/1, has_outgoing_cast/0]).

capture_request(Stream) when is_reference(Stream) ->
    receive
        {'$gen_cast', {request, ReplyTo, Stream, Method, Path, Headers, Body, _Flow}}
            when ReplyTo =:= self(), is_binary(Method), is_binary(Path), is_binary(Body) ->
            {ok, {Method, Path, typed_headers(Headers), Body}}
    after 0 ->
        {error, nil}
    end.

capture_headers(Stream) when is_reference(Stream) ->
    receive
        {'$gen_cast', {headers, ReplyTo, Stream, Method, Path, Headers, _Flow}}
            when ReplyTo =:= self(), is_binary(Method), is_binary(Path) ->
            {ok, {Method, Path, typed_headers(Headers)}}
    after 0 ->
        {error, nil}
    end.

capture_ws_upgrade(Stream) when is_reference(Stream) ->
    receive
        {'$gen_cast', {ws_upgrade, ReplyTo, Stream, Path, Headers, Options}}
            when ReplyTo =:= self(), is_binary(Path), is_map(Options) ->
            {ok, {Path, typed_headers(Headers)}}
    after 0 ->
        {error, nil}
    end.

%% Drain all three outbound shapes, even on regression failures, without
%% swallowing unrelated messages. A rejected input must produce none of them.
has_outgoing_cast() ->
    receive
        {'$gen_cast', {request, _, _, _, _, _, _, _}} -> drain_outgoing_casts();
        {'$gen_cast', {headers, _, _, _, _, _, _}} -> drain_outgoing_casts();
        {'$gen_cast', {ws_upgrade, _, _, _, _, _}} -> drain_outgoing_casts()
    after 0 ->
        false
    end.

drain_outgoing_casts() ->
    _ = has_outgoing_cast(),
    true.

%% Assert the exact List(#(String, String)) representation, not an unsafe cast.
%% Malformed fields remain test process failures rather than fabricated values.
typed_headers([]) -> [];
typed_headers([{Name, Value} | Rest]) when is_binary(Name), is_binary(Value) ->
    [{Name, Value} | typed_headers(Rest)].
