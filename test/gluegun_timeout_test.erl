-module(gluegun_timeout_test).
-export([unchecked_milliseconds/1, with_fixture/3, rejected_close/1,
    assert_rejected_options/1]).

%% Test-only constructor for the actual opaque Timeout representation.
%% Deliberately bypasses the public constructor to exercise FFI defenses.
unchecked_milliseconds(Value) -> {milliseconds, Value}.

%% Gleam: (Fixture, Bool, fn(Connection, Stream) -> Nil) -> Nil.
%% Runs in the calling test process, with no network or timing dependency.
with_fixture(Kind, Consumed, Callback) ->
    Conn = self(),
    Stream = make_ref(),
    Sentinel = {make_ref(), sentinel},
    Message = case Kind of
        up -> {gun_up, Conn, http};
        message -> {gun_data, Conn, Stream, fin, <<"body">>};
        body -> {gun_data, Conn, Stream, fin, <<"body">>};
        websocket -> {gun_ws, Conn, Stream, {text, <<"hello">>}}
    end,
    self() ! Sentinel,
    self() ! Message,
    {messages, Before} = process_info(self(), messages),
    Monitors = monitors(),
    try
        nil = Callback(Conn, Stream),
        Monitors = monitors(),
        Expected = case Consumed of
            true -> lists:delete(Message, Before);
            false -> Before
        end,
        {messages, Expected} = process_info(self(), messages),
        nil
    after
        receive Sentinel -> ok after 0 -> ok end,
        receive Message -> ok after 0 -> ok end
    end.

%% Gleam: (Int) -> Result(Nil, GluegunError).
%% Invalid close must not send frames, exchange credit, or kill the process.
rejected_close(Value) ->
    {Conn, Monitor} = spawn_monitor(fun() -> receive stop -> ok end end),
    Stream = make_ref(),
    PeerClose = gluegun_ffi:ws_peer_close(),
    atomics:put(PeerClose, 2, 3),
    Sentinel = {make_ref(), sentinel},
    Message = {gun_ws, Conn, Stream, close},
    self() ! Sentinel,
    self() ! Message,
    {messages, Before} = process_info(self(), messages),
    Monitors = monitors(),
    try
        Result = gluegun_ffi:ws_close(Conn, Stream, {milliseconds, Value}, PeerClose),
        Monitors = monitors(),
        {messages, Before} = process_info(self(), messages),
        true = is_process_alive(Conn),
        {messages, []} = process_info(Conn, messages),
        0 = atomics:get(PeerClose, 1),
        3 = atomics:get(PeerClose, 2),
        Result
    after
        exit(Conn, kill),
        receive {'DOWN', Monitor, process, Conn, _} -> ok end,
        receive Sentinel -> ok after 0 -> ok end,
        receive Message -> ok after 0 -> ok end
    end.

%% All option paths sharing timeout_to_gun must reject before Gun is called.
%% Gleam: (Int) -> Nil.
assert_rejected_options(Value) ->
    Timeout = {milliseconds, Value},
    with_fixture(up, false, fun(Conn, Stream) ->
        lists:foreach(fun(Key) ->
            {error, {invalid_options, Reason}} =
                gluegun_ffi:open(<<"localhost">>, 80, [{Key, Timeout}]),
            true = is_binary(Reason)
        end, [connect_timeout_option, domain_lookup_timeout_option,
            tls_handshake_timeout_option]),
        lists:foreach(fun(Key) ->
            {error, {invalid_options, Reason}} =
                gluegun_ffi:ws_upgrade(Conn, <<"/">>, [], [{Key, Timeout}]),
            true = is_binary(Reason)
        end, [closing_timeout, keepalive]),
        %% Catch an accidental Gun cast to the connection fixture too.
        true = is_reference(Stream),
        nil
    end).

monitors() ->
    {monitors, Monitors} = process_info(self(), monitors),
    lists:sort(Monitors).
