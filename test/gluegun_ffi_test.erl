-module(gluegun_ffi_test).

%% Typed constructors and projections for deterministic Gleam tests.
%%
%% Every function here returns a value that a Gleam `@external` declaration can
%% describe precisely: a Gun connection handle, a Gun stream reference, a raw
%% Gun message, a `Result(_, GluegunError)`, or a plain Gleam value. No test
%% needs to fabricate a handle out of an arbitrary term.

-export([
    current_connection/0,
    invalid_connection/0,
    stream_ref/0,
    erlang_error_result/0,
    stream_error_result/0,
    timeout_error_result/0,
    invalid_utf8_websocket_result/0,
    inform_message/2,
    response_message/3,
    data_message/2,
    trailers_message/1,
    push_message/4,
    upgrade_message/2,
    websocket_frame_message/1,
    unknown_message/0,
    unknown_websocket_frame_message/0,
    mailbox_inform_message/2,
    mailbox_response_message/3,
    mailbox_data_message/2,
    mailbox_trailers_message/1,
    mailbox_push_message/4,
    mailbox_upgrade_message/2,
    mailbox_websocket_frame_message/1,
    mailbox_stream_error_result/0,
    mailbox_connection_error_result/0,
    await_body_with_fin/1,
    await_body_with_trailers/2,
    text_frame/1,
    binary_frame/1,
    ping_frame/1,
    pong_frame/1,
    close_frame/0,
    close_with_reason_frame/2,
    protocol_result/1,
    capture_stream_headers/0,
    capture_data_fin/2,
    capture_update_flow/1,
    gun_transport/1,
    gun_protocols/1,
    gun_retry/1,
    gun_connect_timeout/1,
    gun_tls_opts/1,
    secure_tls_opts_summary/2,
    secure_tls_opts_with_empty_cacerts/2,
    secure_tls_opts_with_hostname_match_failure/2,
    secure_tls_opts_caches_cacerts/2
]).

%% --- Connection and stream handles ------------------------------------------

%% A usable connection handle: Gun casts land in the test process mailbox.
current_connection() -> self().

%% A handle that is deliberately not a Gun process, used to check that Gun
%% failures surface as typed errors instead of crashing.
invalid_connection() -> <<"not-a-pid">>.

stream_ref() -> make_ref().

%% --- Typed error results ----------------------------------------------------

erlang_error_result() ->
    gluegun_ffi:request(invalid_connection(), <<"GET">>, <<"/">>, [], <<>>).

stream_error_result() ->
    gluegun_ffi:safe_decode_message({error, boom}).

timeout_error_result() ->
    gluegun_ffi:safe_decode_message({error, timeout}).

invalid_utf8_websocket_result() ->
    gluegun_ffi:safe_decode_message({ws, {text, <<255>>}}).

%% --- Raw Gun messages -------------------------------------------------------

inform_message(Status, Headers) -> {inform, Status, Headers}.

response_message(Fin, Status, Headers) -> {response, gun_fin(Fin), Status, Headers}.

data_message(Fin, Data) -> {data, gun_fin(Fin), Data}.

trailers_message(Headers) -> {trailers, Headers}.

push_message(StreamRef, Method, URI, Headers) -> {push, StreamRef, Method, URI, Headers}.

upgrade_message(Protocols, Headers) -> {upgrade, Protocols, Headers}.

websocket_frame_message(Frame) -> {ws, Frame}.

unknown_message() -> {mystery, <<"unknown">>}.

unknown_websocket_frame_message() -> {ws, {mystery, <<"unknown">>}}.

%% --- Raw Gun mailbox messages -----------------------------------------------
%%
%% The tuples Gun sends to the process that owns the stream. They carry the
%% connection pid and stream reference that `gun:await/3` strips.

mailbox_inform_message(Status, Headers) ->
    {gun_inform, current_connection(), stream_ref(), Status, Headers}.

mailbox_response_message(Fin, Status, Headers) ->
    {gun_response, current_connection(), stream_ref(), gun_fin(Fin), Status, Headers}.

mailbox_data_message(Fin, Data) ->
    {gun_data, current_connection(), stream_ref(), gun_fin(Fin), Data}.

mailbox_trailers_message(Headers) ->
    {gun_trailers, current_connection(), stream_ref(), Headers}.

mailbox_push_message(NewStreamRef, Method, URI, Headers) ->
    {gun_push, current_connection(), stream_ref(), NewStreamRef, Method, URI, Headers}.

mailbox_upgrade_message(Protocols, Headers) ->
    {gun_upgrade, current_connection(), stream_ref(), Protocols, Headers}.

mailbox_websocket_frame_message(Frame) ->
    {gun_ws, current_connection(), stream_ref(), Frame}.

mailbox_stream_error_result() ->
    gluegun_ffi:safe_decode_message({gun_error, current_connection(), stream_ref(), boom}).

mailbox_connection_error_result() ->
    gluegun_ffi:safe_decode_message({gun_error, current_connection(), boom}).

%% --- Collected response bodies ----------------------------------------------
%%
%% `gun:await_body/3` reads the mailbox of the calling process, so seeding it
%% with Gun messages exercises both success shapes without a live server.

await_body_with_fin(Body) ->
    StreamRef = stream_ref(),
    self() ! {gun_data, self(), StreamRef, fin, Body},
    gluegun_ffi:await_body(self(), StreamRef, {milliseconds, 100}).

%% Gun ends a trailered response with `{ok, Body, Trailers}`.
await_body_with_trailers(Body, Trailers) ->
    StreamRef = stream_ref(),
    self() ! {gun_data, self(), StreamRef, nofin, Body},
    self() ! {gun_trailers, self(), StreamRef, Trailers},
    gluegun_ffi:await_body(self(), StreamRef, {milliseconds, 100}).

%% --- Raw Gun WebSocket frames -----------------------------------------------

text_frame(Data) -> {text, Data}.

binary_frame(Data) -> {binary, Data}.

ping_frame(Data) -> {ping, Data}.

pong_frame(Data) -> {pong, Data}.

close_frame() -> close.

close_with_reason_frame(Code, Reason) -> {close, Code, Reason}.

%% --- Protocol negotiation ---------------------------------------------------

protocol_result(Name) -> gluegun_ffi:protocol_result(binary_to_atom(Name, utf8)).

%% --- Captured Gun casts -----------------------------------------------------

capture_stream_headers() ->
    receive
        {'$gen_cast', {headers, _ReplyTo, _StreamRef, Method, Path, Headers, _Flow}} ->
            {ok, {Method, Path, Headers}}
    after 0 ->
        {error, {erlang_error, <<"no headers message"/utf8>>}}
    end.

capture_data_fin(Fin, Data) ->
    StreamRef = make_ref(),
    case gluegun_ffi:data(self(), StreamRef, Fin, Data) of
        {ok, nil} ->
            receive
                {'$gen_cast', {data, _ReplyTo, StreamRef, GunFin, _Data}} ->
                    {ok, atom_to_binary(GunFin, utf8)}
            after 0 ->
                {error, {erlang_error, <<"no data message"/utf8>>}}
            end;
        Error ->
            Error
    end.

capture_update_flow(Increment) ->
    StreamRef = make_ref(),
    case gluegun_ffi:update_flow(self(), StreamRef, Increment) of
        {ok, nil} ->
            receive
                {'$gen_cast', {update_flow, _ReplyTo, StreamRef, Flow}} ->
                    {ok, Flow}
            after 0 ->
                {error, {erlang_error, <<"no update_flow message"/utf8>>}}
            end;
        Error ->
            Error
    end.

%% --- Gun connection option projections --------------------------------------

gun_transport(Options) ->
    render(maps:get(transport, gluegun_ffi:connect_options_to_gun(Options), undefined)).

gun_protocols(Options) ->
    [render(Protocol) || Protocol <- maps:get(protocols, gluegun_ffi:connect_options_to_gun(Options), [])].

gun_retry(Options) ->
    render(maps:get(retry, gluegun_ffi:connect_options_to_gun(Options), undefined)).

gun_connect_timeout(Options) ->
    render(maps:get(connect_timeout, gluegun_ffi:connect_options_to_gun(Options), undefined)).

%% Project Gun `tls_opts` to `[{Key, [Value]}]` with every value rendered as a
%% binary, so Gleam can assert on them without inspecting Erlang terms.
gun_tls_opts(Options) ->
    TlsOpts = maps:get(tls_opts, gluegun_ffi:connect_options_to_gun(Options), []),
    [{render(Key), render_values(Value)} || {Key, Value} <- TlsOpts].

render_values(Values) when is_list(Values) ->
    case io_lib:printable_unicode_list(Values) of
        true -> [render(Values)];
        false -> [render(Value) || Value <- Values]
    end;
render_values(Value) ->
    [render(Value)].

render(Value) when is_atom(Value) -> atom_to_binary(Value, utf8);
render(Value) when is_binary(Value) -> Value;
render(Value) when is_integer(Value) -> integer_to_binary(Value);
render(Value) when is_list(Value) -> unicode:characters_to_binary(Value).

%% --- Secure TLS defaults ----------------------------------------------------

%% Apply secure defaults and project the resulting tls_opts to a Gleam tuple of
%% `{Verify, Versions, Depth, Sni, HasCACerts, HasHostnameCheck}`, where the
%% first four are `gleam/option.Option` values.
secure_tls_opts_summary(Host, Options) ->
    Gun = gluegun_ffi:apply_secure_tls_defaults(Host, gluegun_ffi:connect_options_to_gun(Options)),
    summarize_secure_tls_opts(Gun).

secure_tls_opts_with_empty_cacerts(Host, Options) ->
    CacheKey = make_ref(),
    try
        Gun = gluegun_ffi:apply_secure_tls_defaults(
            Host,
            gluegun_ffi:connect_options_to_gun(Options),
            #{cacerts_fun => fun() -> [] end, cacerts_cache_key => CacheKey}
        ),
        {ok, summarize_secure_tls_opts(Gun)}
    catch
        error:{invalid_options, Reason}:_Stack -> {error, {invalid_options, inspect(Reason)}};
        Class:Reason:_Stack -> {error, {erlang_error, inspect({Class, Reason})}}
    end.

secure_tls_opts_with_hostname_match_failure(Host, Options) ->
    try
        Gun = gluegun_ffi:apply_secure_tls_defaults(
            Host,
            gluegun_ffi:connect_options_to_gun(Options),
            #{hostname_match_fun => fun(_Protocol) -> error(test_hostname_match_failure) end}
        ),
        {ok, summarize_secure_tls_opts(Gun)}
    catch
        error:{invalid_options, Reason}:_Stack -> {error, {invalid_options, inspect(Reason)}};
        Class:Reason:_Stack -> {error, {erlang_error, inspect({Class, Reason})}}
    end.

secure_tls_opts_caches_cacerts(Host, Options) ->
    Parent = self(),
    CACertsFun = fun() ->
        Parent ! cacerts_loaded,
        [<<"fake-der-ca">>]
    end,
    GunOptions = gluegun_ffi:connect_options_to_gun(Options),
    CacheKey = make_ref(),
    _ = gluegun_ffi:apply_secure_tls_defaults(Host, GunOptions, #{
        cacerts_fun => CACertsFun,
        cacerts_cache_key => CacheKey
    }),
    _ = gluegun_ffi:apply_secure_tls_defaults(Host, GunOptions, #{
        cacerts_fun => CACertsFun,
        cacerts_cache_key => CacheKey
    }),
    persistent_term:erase(CacheKey),
    count_cacerts_loaded(0).

count_cacerts_loaded(Count) ->
    receive
        cacerts_loaded -> count_cacerts_loaded(Count + 1)
    after 0 ->
        Count
    end.

summarize_secure_tls_opts(Gun) ->
    TlsOpts = maps:get(tls_opts, Gun, []),
    Get = fun(Key) -> proplists:get_value(Key, TlsOpts) end,
    Sni = case Get(server_name_indication) of
        undefined -> none;
        SniValue -> {some, render(SniValue)}
    end,
    Versions = case Get(versions) of
        undefined -> none;
        Values when is_list(Values) -> {some, [render(Version) || Version <- Values]}
    end,
    Verify = case Get(verify) of
        undefined -> none;
        Atom when is_atom(Atom) -> {some, render(Atom)}
    end,
    Depth = case Get(depth) of
        undefined -> none;
        DepthValue -> {some, DepthValue}
    end,
    HasCACerts = case Get(cacerts) of
        List when is_list(List), List =/= [] -> true;
        _ -> false
    end,
    HasHostnameCheck = Get(customize_hostname_check) =/= undefined,
    {Verify, Versions, Depth, Sni, HasCACerts, HasHostnameCheck}.

%% --- Shared helpers ---------------------------------------------------------

gun_fin(fin) -> fin;
gun_fin(no_fin) -> nofin.

inspect(Reason) -> gleam@string:inspect(Reason).
