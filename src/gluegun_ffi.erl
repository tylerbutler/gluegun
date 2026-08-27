-module(gluegun_ffi).

-export([
    open/3,
    await_up/2,
    close/1,
    shutdown/1,
    headers/4,
    request/5,
    data/4,
    await/3,
    await_body/3,
    cancel/2,
    update_flow/3,
    flush/1,
    ws_upgrade/4,
    ws_send/3,
    decode_message/1,
    safe_decode_message/1,
    protocol_result/1,
    identity/1,
    connect_options_to_gun/1,
    apply_secure_tls_defaults/2,
    apply_secure_tls_defaults/3
]).

%% Every exported entry point returns a Gleam `Result(value, GluegunError)`:
%% `{ok, Value}` or `{error, GleamError}`, where `GleamError` is the Erlang
%% representation of `gluegun/error.GluegunError`. Option arguments arrive as
%% Gleam values (`gluegun/connection.ConnectOption`, `gluegun/tls.TlsSetting`,
%% `gluegun/websocket.UpgradeOption`, `gluegun/connection.Timeout`,
%% `gluegun/fin.Fin`, `gluegun/message.Frame`) and are converted to Gun terms
%% here, so nothing crosses the boundary untyped.

open(Host, Port, Options) ->
    try
        GunOptions = apply_secure_tls_defaults(Host, connect_options_to_gun(Options)),
        with_normalize(connection, fun() ->
            gun:open(normalize_host(Host), Port, GunOptions)
        end)
    catch
        error:{options, Reason}:_Stack -> {error, gleam_error({invalid_options, Reason})};
        error:{invalid_options, Reason}:_Stack -> {error, gleam_error({invalid_options, Reason})};
        Class:Reason:_Stack -> {error, gleam_error({erlang_error, {Class, Reason}})}
    end.

await_up(ConnPid, Timeout) ->
    case
        with_normalize(connection, fun() ->
            gun:await_up(ConnPid, timeout_to_gun(Timeout))
        end)
    of
        {ok, Protocol} -> protocol_result(Protocol);
        {error, _} = Error -> Error
    end.

close(ConnPid) ->
    with_normalize(connection_error, fun() ->
        case gun:close(ConnPid) of
            {error, Reason} -> {error, {error, Reason}};
            Other -> Other
        end
    end).

shutdown(ConnPid) -> with_normalize(connection_error, fun() -> gun:shutdown(ConnPid) end).

request(ConnPid, Method, Path, Headers, Body) ->
    try
        MethodBin = validate_request_method(Method),
        PathBin = validate_request_path(Path),
        HeadersOut = validate_request_headers(Headers),
        with_normalize(stream_erlang, fun() ->
            {ok, gun:request(ConnPid, MethodBin, PathBin, HeadersOut, Body, #{})}
        end)
    catch
        error:{invalid_options, Reason}:_Stack -> {error, gleam_error({invalid_options, Reason})}
    end.

headers(ConnPid, Method, Path, Headers) ->
    try
        MethodBin = validate_request_method(Method),
        PathBin = validate_request_path(Path),
        HeadersOut = validate_request_headers(Headers),
        with_normalize(stream_erlang, fun() ->
            {ok, gun:headers(ConnPid, MethodBin, PathBin, HeadersOut, #{})}
        end)
    catch
        error:{invalid_options, Reason}:_Stack -> {error, gleam_error({invalid_options, Reason})}
    end.

data(ConnPid, StreamRef, Fin, Data) ->
    with_normalize(stream, fun() ->
        gun:data(ConnPid, StreamRef, fin_to_gun(Fin), Data)
    end).

await(ConnPid, StreamRef, Timeout) ->
    case
        with_normalize(stream_erlang, fun() ->
            {ok, gun:await(ConnPid, StreamRef, timeout_to_gun(Timeout))}
        end)
    of
        {ok, Message} -> safe_decode_message(Message);
        {error, _} = Error -> Error
    end.

await_body(ConnPid, StreamRef, Timeout) ->
    with_normalize(stream_erlang, fun() ->
        case gun:await_body(ConnPid, StreamRef, timeout_to_gun(Timeout)) of
            {ok, Body} -> {ok, iolist_to_binary(Body)};
            %% Gun returns the collected body plus trailers when the response
            %% ends with a trailer frame. Only the body crosses the boundary
            %% here; use `message.await` to read trailers.
            {ok, Body, _Trailers} -> {ok, iolist_to_binary(Body)};
            Other -> Other
        end
    end).

cancel(ConnPid, StreamRef) ->
    with_normalize(stream, fun() ->
        gun:cancel(ConnPid, StreamRef)
    end).

update_flow(ConnPid, StreamRef, Increment) ->
    with_normalize(stream, fun() ->
        gun:update_flow(ConnPid, StreamRef, Increment)
    end).

flush(ConnPid) -> with_normalize(connection_error, fun() -> gun:flush(ConnPid) end).

ws_upgrade(ConnPid, Path, Headers, WsOptions) ->
    try
        GunOpts = ws_options_to_gun(WsOptions),
        PathBin = validate_request_path(Path),
        HeadersOut = validate_request_headers(Headers),
        with_normalize(stream_erlang, fun() ->
            try
                case gun:ws_upgrade(ConnPid, PathBin, HeadersOut, GunOpts) of
                    {error, {options, {ws, Opt}}} ->
                        {error, {invalid_options, {ws, invalid_ws_opt_name(Opt)}}};
                    {error, {options, Reason}} ->
                        {error, {invalid_options, Reason}};
                    StreamRef ->
                        {ok, StreamRef}
                end
            catch
                error:{options, {ws, Opt1}}:_Stack ->
                    {error, {invalid_options, {ws, invalid_ws_opt_name(Opt1)}}};
                error:{badmatch, {error, {options, {ws, Opt2}}}}:_Stack ->
                    {error, {invalid_options, {ws, invalid_ws_opt_name(Opt2)}}}
            end
        end)
    catch
        error:{invalid_options, Reason}:_Stack -> {error, gleam_error({invalid_options, Reason})};
        Class:Reason:_Stack -> {error, gleam_error({erlang_error, {Class, Reason}})}
    end.

ws_send(ConnPid, StreamRef, Frames) ->
    try
        GunFrames = [gleam_frame_to_gun(Frame) || Frame <- Frames],
        with_normalize(stream_erlang, fun() ->
            gun:ws_send(ConnPid, StreamRef, GunFrames)
        end)
    catch
        error:{invalid_frame, Reason}:_Stack ->
            {error, gleam_error({invalid_message, {invalid_frame, Reason}})};
        Class:Reason:_Stack -> {error, gleam_error({erlang_error, {Class, Reason}})}
    end.

%% Forward a value unchanged. Used to build the opaque `HandlerOptions` term
%% Gun passes to a WebSocket protocol handler module as `user_opts`.
identity(Value) -> Value.

with_normalize(Tag, Fun) ->
    try Fun() of
        ok -> {ok, nil};
        {ok, _} = Result -> Result;
        {error, timeout} -> {error, timeout};
        {error, Reason} -> {error, gleam_error(normalize_error(Tag, Reason))};
        Other -> {error, gleam_error(normalize_error(Tag, Other))}
    catch
        Class:Reason:_Stack -> {error, gleam_error(caught_error(Tag, Class, Reason))}
    end.

caught_error(connection, Class, Reason) -> {erlang_error, {Class, Reason}};
caught_error(connection_error, Class, Reason) -> {connection_error, {Class, Reason}};
caught_error(stream, Class, Reason) -> {stream_error, {Class, Reason}};
caught_error(stream_erlang, Class, Reason) -> {erlang_error, {Class, Reason}}.

normalize_error(_Tag, {invalid_options, _} = Error) -> Error;
normalize_error(_Tag, {connection_down, _} = Error) -> Error;
normalize_error(_Tag, {connection_error, _} = Error) -> Error;
normalize_error(_Tag, {stream_error, _} = Error) -> Error;
normalize_error(_Tag, {invalid_message, _} = Error) -> Error;
normalize_error(_Tag, {erlang_error, _} = Error) -> Error;
normalize_error(connection, Reason) -> normalize_connection_error(Reason);
normalize_error(connection_error, Reason) -> normalize_connection_error(Reason);
normalize_error(stream, Reason) -> normalize_stream_error(Reason);
normalize_error(stream_erlang, Reason) -> normalize_stream_error(Reason).

%% Build the Erlang representation of a Gleam `gluegun/error.GluegunError`.
%% Reasons are rendered with the same `gleam/string.inspect` used everywhere
%% else in the package, so error text is identical on both sides.
gleam_error(timeout) -> timeout;
gleam_error({connection_down, Reason}) -> {connection_down, inspect(Reason)};
gleam_error({connection_error, Reason}) -> {connection_error, inspect(Reason)};
gleam_error({stream_error, Reason}) -> {stream_error, inspect(Reason)};
gleam_error({invalid_options, Reason}) -> {invalid_options, inspect(Reason)};
gleam_error({invalid_message, Reason}) -> {invalid_message, inspect(Reason)};
gleam_error({unsupported_feature, Reason}) -> {unsupported_feature, inspect(Reason)};
gleam_error({erlang_error, Reason}) -> {erlang_error, inspect(Reason)};
gleam_error(Other) -> {erlang_error, inspect(Other)}.

inspect(Reason) -> gleam@string:inspect(Reason).

%% Convert a Gleam Frame (compiled Erlang tagged tuple) to a Gun frame term.
%% Gleam compiles:
%%   Text(S)               -> {text, S}
%%   Binary(B)             -> {binary, B}
%%   Close                 -> close  (zero-arg atom)
%%   CloseWithReason(C, R) -> {close_with_reason, C, R}
%%   Ping(B)               -> {ping, B}
%%   Pong(B)               -> {pong, B}
gleam_frame_to_gun({text, Data}) -> {text, validate_text_frame_data(Data)};
gleam_frame_to_gun({binary, Data}) -> {binary, Data};
gleam_frame_to_gun(close) -> close;
gleam_frame_to_gun({close_with_reason, Code, Reason}) -> {close, Code, Reason};
gleam_frame_to_gun({ping, Data}) -> {ping, Data};
gleam_frame_to_gun({pong, Data}) -> {pong, Data};
gleam_frame_to_gun(Other) -> error({invalid_frame, Other}).

validate_text_frame_data(Data) ->
    case validate_utf8(Data) of
        {ok, ValidText} -> ValidText;
        {error, invalid_utf8} -> error({invalid_frame, {text, invalid_utf8}})
    end.

validate_utf8(IoData) ->
    case unicode:characters_to_binary(IoData, utf8, utf8) of
        ValidText when is_binary(ValidText) -> {ok, ValidText};
        {error, _Encoded, _Rest} -> {error, invalid_utf8};
        {incomplete, _Encoded, _Rest} -> {error, invalid_utf8}
    end.

normalize_host(Host) when is_binary(Host) -> unicode:characters_to_list(Host);
normalize_host(Host) -> Host.

%% --- Connection options -----------------------------------------------------
%%
%% `Options` is a Gleam `List(gluegun/connection.ConnectOption)`.

connect_options_to_gun(Options) when is_list(Options) ->
    resolve_auto_transport(lists:foldl(fun connect_option_to_gun/2, #{}, Options));
connect_options_to_gun(Options) ->
    error({invalid_options, Options}).

%% Auto transport (`transport_option, auto`) leaves the `transport` key out of
%% `GunOptions` on purpose, so Gun falls back to its own port-based default:
%% TLS on port 443, plain TCP everywhere else. That default silently drops
%% any `tls_opts` the caller configured whenever the port is not 443.
%%
%% When TLS options were explicitly configured (`tls_opts` present) and the
%% transport is still unresolved, the caller has stated TLS intent, so force
%% `transport => tls` regardless of port. Auto connections without TLS
%% options are untouched: `transport` stays unset and Gun keeps choosing by
%% port, preserving ordinary Auto behavior.
resolve_auto_transport(GunOptions) ->
    case {maps:is_key(transport, GunOptions), maps:is_key(tls_opts, GunOptions)} of
        {false, true} -> GunOptions#{transport => tls};
        _ -> GunOptions
    end.

connect_option_to_gun({transport_option, auto}, GunOptions) -> GunOptions;
connect_option_to_gun({transport_option, tcp}, GunOptions) -> GunOptions#{transport => tcp};
connect_option_to_gun({transport_option, tls}, GunOptions) -> GunOptions#{transport => tls};
connect_option_to_gun({protocols_option, Protocols}, GunOptions) ->
    GunOptions#{protocols => [protocol_to_gun(Protocol) || Protocol <- Protocols]};
connect_option_to_gun({retry_option, Timeout}, GunOptions) ->
    GunOptions#{retry => timeout_to_gun(Timeout)};
connect_option_to_gun({connect_timeout_option, Timeout}, GunOptions) ->
    GunOptions#{connect_timeout => timeout_to_gun(Timeout)};
connect_option_to_gun({tls_option, TlsSettings}, GunOptions) ->
    GunOptions#{tls_opts => tls_settings_to_gun(TlsSettings)}.

%% --- TLS options ------------------------------------------------------------
%%
%% `TlsSettings` is a Gleam `List(gluegun/tls.TlsSetting)`.

tls_settings_to_gun(TlsSettings) when is_list(TlsSettings) ->
    [tls_setting_to_gun(Setting) || Setting <- TlsSettings].

tls_setting_to_gun({verify_setting, Verify}) -> {verify, Verify};
tls_setting_to_gun({versions_setting, Versions}) ->
    {versions, [tls_version_to_gun(Version) || Version <- Versions]};
tls_setting_to_gun({ciphers_setting, Ciphers}) ->
    {ciphers, [unicode_value_to_list(Cipher) || Cipher <- Ciphers]};
tls_setting_to_gun({cacerts_setting, CACerts}) ->
    {cacerts, [iolist_to_binary(CACert) || CACert <- CACerts]};
tls_setting_to_gun({cacertfile_setting, Path}) -> {cacertfile, file_name_to_gun(Path)};
tls_setting_to_gun({certfile_setting, Path}) -> {certfile, file_name_to_gun(Path)};
tls_setting_to_gun({keyfile_setting, Path}) -> {keyfile, file_name_to_gun(Path)};
tls_setting_to_gun({server_name_indication_setting, Value}) ->
    {server_name_indication, server_name_indication_to_gun(Value)};
tls_setting_to_gun({depth_setting, Depth}) -> {depth, Depth}.

tls_version_to_gun(tls_v12) -> 'tlsv1.2';
tls_version_to_gun(tls_v13) -> 'tlsv1.3'.

server_name_indication_to_gun(disable) -> disable;
server_name_indication_to_gun({server_name, Hostname}) -> unicode_value_to_list(Hostname).

%% --- Secure TLS defaults ----------------------------------------------------
%%
%% When a connection uses TLS (transport `tls` or `auto`), fill in any TLS
%% option fields the caller did not set with a secure baseline: peer +
%% hostname verification, the OS trust store, SNI from the target host,
%% TLS 1.2/1.3, and a hostname match function.
%%
%% User-supplied `tls_opts` always win — the merge is "add only missing
%% keys". If the caller explicitly sets `verify => verify_none` we skip the
%% rest of the baseline (no cacerts, no hostname checks).

apply_secure_tls_defaults(Host, GunOptions) ->
    apply_secure_tls_defaults(Host, GunOptions, #{}).

apply_secure_tls_defaults(_Host, GunOptions, _Deps) when not is_map(GunOptions) ->
    GunOptions;
apply_secure_tls_defaults(Host, GunOptions, Deps) ->
    case tls_defaults_apply_to_transport(GunOptions) of
        false -> GunOptions;
        true ->
            TlsOpts0 = maps:get(tls_opts, GunOptions, []),
            TlsOpts = merge_secure_tls_defaults(Host, TlsOpts0, Deps),
            GunOptions#{tls_opts => TlsOpts}
    end.

tls_defaults_apply_to_transport(GunOptions) ->
    case maps:get(transport, GunOptions, auto) of
        tls -> true;
        auto -> true;
        _ -> false
    end.

merge_secure_tls_defaults(Host, TlsOpts, Deps) when is_list(TlsOpts) ->
    case proplists:get_value(verify, TlsOpts) of
        undefined -> add_verify_peer_defaults(Host, [{verify, verify_peer} | TlsOpts], Deps);
        verify_peer -> add_verify_peer_defaults(Host, TlsOpts, Deps);
        _ -> TlsOpts
    end.

add_verify_peer_defaults(Host, TlsOpts, Deps) ->
    TlsOptsWithCACerts = maybe_add_cacerts(TlsOpts, Deps),
    TlsOptsWithVersions = maybe_add(versions, ['tlsv1.3', 'tlsv1.2'], TlsOptsWithCACerts),
    TlsOptsWithDepth = maybe_add(depth, 10, TlsOptsWithVersions),
    TlsOptsWithSni = maybe_add_sni(Host, TlsOptsWithDepth),
    maybe_add_hostname_match(TlsOptsWithSni, Deps).

maybe_add(Key, Value, TlsOpts) ->
    case proplists:is_defined(Key, TlsOpts) of
        true -> TlsOpts;
        false -> [{Key, Value} | TlsOpts]
    end.

maybe_add_cacerts(TlsOpts, Deps) ->
    case proplists:is_defined(cacerts, TlsOpts) orelse proplists:is_defined(cacertfile, TlsOpts) of
        true -> TlsOpts;
        false ->
            case system_cacerts(Deps) of
                {ok, CACerts} -> [{cacerts, CACerts} | TlsOpts];
                {error, Reason} -> error({invalid_options, {tls, {no_system_cacerts, Reason}}})
            end
    end.

system_cacerts(Deps) ->
    CACertsFun = maps:get(cacerts_fun, Deps, fun public_key:cacerts_get/0),
    CacheKey = maps:get(cacerts_cache_key, Deps, gluegun_system_cacerts),
    try cached_system_cacerts(CacheKey, CACertsFun) of
        CACerts when is_list(CACerts), CACerts =/= [] -> {ok, CACerts};
        [] -> {error, empty};
        Other -> {error, {unexpected_return, Other}}
    catch
        Class:Reason:_Stack -> {error, {Class, Reason}}
    end.

cached_system_cacerts(CacheKey, CACertsFun) ->
    case persistent_term:get(CacheKey, undefined) of
        undefined ->
            CACerts = CACertsFun(),
            case CACerts of
                List when is_list(List), List =/= [] ->
                    persistent_term:put(CacheKey, List),
                    List;
                _ ->
                    CACerts
            end;
        CACerts ->
            CACerts
    end.

maybe_add_sni(Host, TlsOpts) ->
    case proplists:is_defined(server_name_indication, TlsOpts) of
        true -> TlsOpts;
        false ->
            case sni_for_host(Host) of
                {ok, Sni} -> [{server_name_indication, Sni} | TlsOpts];
                skip -> TlsOpts
            end
    end.

sni_for_host(Host) ->
    HostStr = host_to_charlist(Host),
    case HostStr of
        [] -> skip;
        _ ->
            case inet:parse_address(strip_ipv6_brackets(HostStr)) of
                {ok, _IP} -> skip;
                {error, _} -> {ok, HostStr}
            end
    end.

strip_ipv6_brackets([$[ | Rest]) ->
    case lists:reverse(Rest) of
        [$] | RevInner] -> lists:reverse(RevInner);
        _ -> [$[ | Rest]
    end;
strip_ipv6_brackets(Host) -> Host.

host_to_charlist(Host) when is_binary(Host) -> unicode:characters_to_list(Host);
host_to_charlist(Host) when is_list(Host) -> Host;
host_to_charlist(_) -> [].

maybe_add_hostname_match(TlsOpts, Deps) ->
    case proplists:is_defined(customize_hostname_check, TlsOpts) of
        true -> TlsOpts;
        false ->
            HostnameMatchFun =
                maps:get(
                    hostname_match_fun,
                    Deps,
                    fun public_key:pkix_verify_hostname_match_fun/1
                ),
            try HostnameMatchFun(https) of
                MatchFun ->
                    [{customize_hostname_check, [{match_fun, MatchFun}]} | TlsOpts]
            catch
                Class:Reason:_Stack ->
                    error({invalid_options, {tls, {hostname_match_fun_unavailable, {Class, Reason}}}})
            end
    end.

%% ---------------------------------------------------------------------------

file_name_to_gun(Value) -> unicode_value_to_list(Value).

unicode_value_to_list(Value) when is_binary(Value) -> unicode:characters_to_list(Value);
unicode_value_to_list(Value) when is_list(Value) -> Value;
unicode_value_to_list(Value) -> Value.

%% --- WebSocket upgrade options ----------------------------------------------
%%
%% `WsOptions` is a Gleam `List(gluegun/websocket.UpgradeOption)`.

ws_options_to_gun(WsOptions) when is_list(WsOptions) ->
    maps:from_list([ws_option_to_gun(Option) || Option <- WsOptions]).

ws_option_to_gun({closing_timeout, Timeout}) -> {closing_timeout, timeout_to_gun(Timeout)};
ws_option_to_gun({compress, Compress}) -> {compress, Compress};
ws_option_to_gun({default_protocol, Module}) -> {default_protocol, module_name_to_atom(Module)};
ws_option_to_gun({flow, Flow}) -> {flow, Flow};
ws_option_to_gun({keepalive, Timeout}) -> {keepalive, timeout_to_gun(Timeout)};
ws_option_to_gun({protocols, Protocols}) ->
    {protocols, [ws_protocol_to_gun(Protocol) || Protocol <- Protocols]};
ws_option_to_gun({reply_to, ReplyTo}) -> {reply_to, ReplyTo};
ws_option_to_gun({silence_pings, SilencePings}) -> {silence_pings, SilencePings};
ws_option_to_gun({tunnel, StreamRef}) -> {tunnel, StreamRef};
ws_option_to_gun({user_options, HandlerOptions}) -> {user_opts, HandlerOptions}.

ws_protocol_to_gun({Protocol, Module}) -> {to_binary(Protocol), module_name_to_atom(Module)}.

module_name_to_atom(Module) when is_atom(Module) -> Module;
module_name_to_atom(Module) when is_binary(Module) ->
    try binary_to_existing_atom(Module, utf8) of
        Atom -> Atom
    catch
        error:badarg:_Stack -> error({invalid_options, {ws, {unknown_module, Module}}})
    end;
module_name_to_atom(Module) when is_list(Module) ->
    try list_to_existing_atom(Module) of
        Atom -> Atom
    catch
        error:badarg:_Stack -> error({invalid_options, {ws, {unknown_module, Module}}})
    end.

invalid_ws_opt_name({Key, _Value}) -> Key;
invalid_ws_opt_name(Key) -> Key.

%% --- Shared value conversions -----------------------------------------------

timeout_to_gun(infinity) -> infinity;
timeout_to_gun({milliseconds, Timeout}) when is_integer(Timeout) -> Timeout.

protocol_to_gun(http1) -> http;
protocol_to_gun(http2) -> http2.

%% Gun reports the negotiated protocol as `http` or `http2`; Gleam models them
%% as `gluegun/connection.Http1` and `Http2`.
protocol_result(http) -> {ok, http1};
protocol_result(http2) -> {ok, http2};
protocol_result(_Other) -> {error, {decode_error, <<"Invalid protocol"/utf8>>}}.

fin_to_gun(fin) -> fin;
fin_to_gun(no_fin) -> nofin.

fin_from_gun(fin) -> fin;
fin_from_gun(nofin) -> no_fin;
fin_from_gun(Other) -> error({invalid_message, {invalid_fin, Other}}).

normalize_connection_error(timeout) -> timeout;
normalize_connection_error({down, _Protocol, Reason, _KilledStreams, _UnprocessedStreams}) ->
    {connection_down, Reason};
normalize_connection_error(Reason) -> {connection_error, Reason}.

normalize_stream_error(timeout) -> timeout;
normalize_stream_error({stream_error, Reason}) -> {stream_error, Reason};
normalize_stream_error({connection_error, Reason}) -> {connection_error, Reason};
normalize_stream_error(Reason) -> {stream_error, Reason}.

%% --- Gun message decoding ---------------------------------------------------
%%
%% Builds Gleam `gluegun/message.Message` values directly, so the Gleam side
%% never has to inspect an untyped Gun term. Two shapes exist: the raw
%% mailbox tuples Gun sends to the stream owner (`{gun_response, ConnPid,
%% StreamRef, ...}`), which carry the connection and stream a message came
%% from, and the shorter terms `gun:await/3` returns (`{response, ...}`),
%% which do not. `decode_message/1` (`gluegun/message.decode`) only accepts
%% the former, so it can pair every decoded message with that identity; the
%% latter is decoded by `safe_decode_message/1` for `gluegun/message.await`,
%% whose caller already supplies the connection and stream explicitly.

%% `gluegun/message.decode`: only the raw mailbox tuples Gun sends to the
%% stream owner are accepted, because only those carry the connection pid and
%% stream reference a message came from. A process that owns several
%% concurrent streams (HTTP/2 requests, server pushes) cannot otherwise tell
%% which stream a decoded message belongs to. Every accepted shape is paired
%% with that identity as a Gleam `gluegun/message.Envelope`
%% (`{envelope, ConnPid, StreamRef, Message}`); any other shape, including a
%% `gun:await/3`-style term with no embedded identity, is a decode failure.
decode_message({gun_inform, ConnPid, StreamRef, Status, Headers}) ->
    envelope(ConnPid, StreamRef, safe_decode_message({inform, Status, Headers}));
decode_message({gun_response, ConnPid, StreamRef, Fin, Status, Headers}) ->
    envelope(ConnPid, StreamRef, safe_decode_message({response, Fin, Status, Headers}));
decode_message({gun_data, ConnPid, StreamRef, Fin, Data}) ->
    envelope(ConnPid, StreamRef, safe_decode_message({data, Fin, Data}));
decode_message({gun_trailers, ConnPid, StreamRef, Headers}) ->
    envelope(ConnPid, StreamRef, safe_decode_message({trailers, Headers}));
decode_message({gun_push, ConnPid, StreamRef, NewStreamRef, Method, URI, Headers}) ->
    envelope(ConnPid, StreamRef, safe_decode_message({push, NewStreamRef, Method, URI, Headers}));
decode_message({gun_upgrade, ConnPid, StreamRef, Protocols, Headers}) ->
    envelope(ConnPid, StreamRef, safe_decode_message({upgrade, Protocols, Headers}));
decode_message({gun_ws, ConnPid, StreamRef, Frame}) ->
    envelope(ConnPid, StreamRef, safe_decode_message({ws, Frame}));
decode_message(_Other) ->
    %% Covers `gun_error` (stream- and connection-level) and any shape that
    %% is not a recognized Gun mailbox message, including bare
    %% `gun:await/3`-style terms, which carry no identity to preserve.
    {error, {decode_error, <<"Invalid Gun message"/utf8>>}}.

%% Pairs a successfully decoded `Message` with the connection and stream Gun
%% named for it. `StreamRef` is the stream that delivered the message; for
%% `gun_push` that is the existing stream the server pushed on, not the new
%% stream carried inside the decoded `Push` message. A malformed payload
%% inside a recognized mailbox tuple (e.g. an unrecognized WebSocket frame)
%% still collapses to the same generic decode failure `decode_message/1`
%% returns for any other unrecognized shape, so `gluegun/message.decode`'s
%% error contract stays a single, stable `DecodeError`.
envelope(ConnPid, StreamRef, {ok, Decoded}) -> {ok, {envelope, ConnPid, StreamRef, Decoded}};
envelope(_ConnPid, _StreamRef, {error, _}) -> {error, {decode_error, <<"Invalid Gun message"/utf8>>}}.

%% `gluegun/message.await`: keeps Gun's own stream and message classification.
safe_decode_message(Message) ->
    try message_to_gleam(Message) of
        Decoded -> {ok, Decoded}
    catch
        error:{invalid_message, Reason}:_Stack -> {error, gleam_error({invalid_message, Reason})};
        error:{stream_error, Reason}:_Stack -> {error, gleam_error({stream_error, Reason})};
        error:{connection_error, Reason}:_Stack ->
            {error, gleam_error({connection_error, Reason})};
        error:timeout:_Stack -> {error, timeout};
        Class:Reason:_Stack -> {error, gleam_error({erlang_error, {Class, Reason}})}
    end.

%% Mailbox error tuples: the connection pid and stream reference are not
%% preserved here because there is no successfully decoded `Message` to pair
%% them with; the typed error variant (`StreamError` / `ConnectionError`) is
%% enough context on its own. `decode_message/1` extracts identity for the
%% other mailbox tuples before reaching this function; see above.
message_to_gleam({gun_error, _ConnPid, _StreamRef, Reason}) ->
    message_to_gleam({error, Reason});
message_to_gleam({gun_error, _ConnPid, Reason}) ->
    error({connection_error, Reason});
%% Await shapes: what `gun:await/3` returns after it strips the envelope.
message_to_gleam({inform, Status, Headers}) ->
    {inform, Status, normalize_headers(Headers)};
message_to_gleam({response, Fin, Status, Headers}) ->
    {response, fin_from_gun(Fin), Status, normalize_headers(Headers)};
message_to_gleam({data, Fin, Data}) ->
    {data, fin_from_gun(Fin), iolist_to_binary(Data)};
message_to_gleam({trailers, Headers}) ->
    {trailers, normalize_headers(Headers)};
message_to_gleam({push, NewStreamRef, Method, URI, Headers}) ->
    {push, NewStreamRef, method_from_gun(Method), to_binary(URI), normalize_headers(Headers)};
message_to_gleam({upgrade, Protocols, Headers}) ->
    {upgrade, [to_binary(Protocol) || Protocol <- Protocols], normalize_headers(Headers)};
message_to_gleam({ws, Frame}) ->
    {web_socket, frame_from_gun(Frame)};
message_to_gleam({error, timeout}) ->
    error(timeout);
message_to_gleam({error, Reason}) ->
    error({stream_error, Reason});
message_to_gleam(Other) ->
    error({invalid_message, Other}).

frame_from_gun({text, Data}) ->
    case validate_utf8(Data) of
        {ok, ValidText} -> {text, ValidText};
        {error, invalid_utf8} -> error({invalid_message, {ws, {text, invalid_utf8}}})
    end;
frame_from_gun({binary, Data}) -> {binary, iolist_to_binary(Data)};
frame_from_gun({close, Code, Reason}) -> {close_with_reason, Code, iolist_to_binary(Reason)};
frame_from_gun({ping, Data}) -> {ping, iolist_to_binary(Data)};
frame_from_gun({pong, Data}) -> {pong, iolist_to_binary(Data)};
frame_from_gun(close) -> close;
frame_from_gun(Other) -> error({invalid_message, {ws, Other}}).

%% Gun reports pushed request methods as binaries. Known methods map onto the
%% `gluegun/request.Method` constructors; anything else keeps its original
%% casing inside `Custom`.
method_from_gun(Method) ->
    Binary = to_binary(Method),
    case string:uppercase(Binary) of
        <<"GET">> -> get;
        <<"HEAD">> -> head;
        <<"POST">> -> post;
        <<"PUT">> -> put;
        <<"PATCH">> -> patch;
        <<"DELETE">> -> delete;
        <<"OPTIONS">> -> options;
        <<"TRACE">> -> trace;
        <<"CONNECT">> -> connect;
        _ -> {custom, Binary}
    end.

%% Header names are lowercased on both directions of the boundary; values are
%% preserved exactly. This lenient form only decodes messages Gun already
%% accepted from the wire (responses, pushes, trailers, upgrades); it must
%% never be used to build an outgoing request. Use `validate_request_headers/1`
%% for anything crossing the boundary in the request direction.
normalize_headers(Headers) ->
    [{string:lowercase(to_binary(Name)), to_binary(Value)} || {Name, Value} <- Headers].

to_binary(Value) when is_binary(Value) -> Value;
to_binary(Value) when is_atom(Value) -> atom_to_binary(Value, utf8);
to_binary(Value) when is_list(Value) -> iolist_to_binary(Value);
to_binary(Value) when is_integer(Value) -> integer_to_binary(Value);
to_binary(Value) -> error({invalid_binary, Value}).

%% --- Outgoing request validation --------------------------------------------
%%
%% `request/5`, `headers/4`, and `ws_upgrade/4` are the only places attacker-
%% or caller-controlled bytes reach Gun's request-line and header encoder.
%% Everything here rejects bytes that could split an HTTP/1.1 request into
%% more than one request (CR, LF), truncate a header at a NUL, or let a
%% caller override framing (`Transfer-Encoding`, conflicting
%% `Content-Length`) that Gluegun itself is responsible for. Validation
%% raises `error({invalid_options, {request, Reason}})`, caught by the
%% `try`/`catch` in each caller and turned into `{error, InvalidOptions}`.

%% The HTTP method is sent verbatim on the request line, so it must be a
%% valid HTTP token just like a header name.
validate_request_method(Method) ->
    MethodBin = to_binary(Method),
    case is_valid_token(MethodBin) of
        true -> MethodBin;
        false -> error({invalid_options, {request, invalid_method}})
    end.

%% The path is sent verbatim on the request line. Gluegun does not parse or
%% encode URLs, so this only rejects bytes that are never valid there: C0
%% control characters (including CR/LF) and DEL. It does not validate
%% percent-encoding or reserved characters.
validate_request_path(Path) ->
    PathBin = to_binary(Path),
    case has_control_byte(PathBin) of
        true -> error({invalid_options, {request, invalid_path}});
        false -> PathBin
    end.

%% Validate and ASCII-normalize outgoing request headers. Names must be RFC
%% 7230 tokens, values must not contain CR, LF, or NUL, and callers cannot
%% supply framing headers (`Transfer-Encoding`, duplicate or malformed
%% `Content-Length`) that would let a request be interpreted differently by
%% Gluegun and a downstream proxy or origin server.
validate_request_headers(Headers) ->
    Normalized = [
        {ascii_lowercase(validate_header_name(Name)), validate_header_value(Value)}
     || {Name, Value} <- Headers
    ],
    reject_transfer_encoding(Normalized),
    validate_content_length(Normalized),
    Normalized.

validate_header_name(Name) ->
    NameBin = to_binary(Name),
    case is_valid_token(NameBin) of
        true -> NameBin;
        false -> error({invalid_options, {request, invalid_header_name}})
    end.

validate_header_value(Value) ->
    ValueBin = to_binary(Value),
    case has_forbidden_value_byte(ValueBin) of
        true -> error({invalid_options, {request, invalid_header_value}});
        false -> ValueBin
    end.

reject_transfer_encoding(Headers) ->
    case lists:keymember(<<"transfer-encoding">>, 1, Headers) of
        true -> error({invalid_options, {request, forbidden_transfer_encoding_header}});
        false -> ok
    end.

validate_content_length(Headers) ->
    case [Value || {<<"content-length">>, Value} <- Headers] of
        [] ->
            ok;
        [Value] ->
            case is_valid_content_length(Value) of
                true -> ok;
                false -> error({invalid_options, {request, invalid_content_length_header}})
            end;
        [_ | _] ->
            error({invalid_options, {request, duplicate_content_length_header}})
    end.

is_valid_content_length(Value) ->
    byte_size(Value) > 0 andalso
        lists:all(fun(Byte) -> Byte >= $0 andalso Byte =< $9 end, binary_to_list(Value)).

%% RFC 7230 `tchar`: DIGIT / ALPHA / one of "!#$%&'*+-.^_`|~". Method and
%% header names are both HTTP tokens, so this is shared between the two.
is_valid_token(Bin) ->
    byte_size(Bin) > 0 andalso lists:all(fun is_token_byte/1, binary_to_list(Bin)).

is_token_byte(Byte) ->
    (Byte >= $A andalso Byte =< $Z) orelse
        (Byte >= $a andalso Byte =< $z) orelse
        (Byte >= $0 andalso Byte =< $9) orelse
        lists:member(Byte, "!#$%&'*+-.^_`|~").

%% C0 controls (0x00-0x1F) and DEL (0x7F). Covers CR/LF request-line and
%% header-line splitting plus other bytes that have no valid meaning there.
has_control_byte(Bin) ->
    lists:any(fun(Byte) -> Byte < 16#20 orelse Byte =:= 16#7F end, binary_to_list(Bin)).

%% CR, LF, and NUL specifically: the bytes that let a header value split a
%% message into extra header/request lines or truncate a header early.
has_forbidden_value_byte(Bin) ->
    lists:any(fun(Byte) -> Byte =:= 16#0D orelse Byte =:= 16#0A orelse Byte =:= 16#00 end,
        binary_to_list(Bin)).

%% Lowercase using the ASCII range only. Header names are already validated
%% as HTTP tokens (ASCII-only) by the time this runs, so this avoids relying
%% on Unicode-aware case folding for a security-relevant comparison.
ascii_lowercase(Bin) ->
    <<<<(ascii_lower_byte(Byte))>> || <<Byte>> <= Bin>>.

ascii_lower_byte(Byte) when Byte >= $A andalso Byte =< $Z -> Byte + 32;
ascii_lower_byte(Byte) -> Byte.
