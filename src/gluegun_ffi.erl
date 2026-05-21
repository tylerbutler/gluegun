-module(gluegun_ffi).

-export([
    open/3,
    await_up/2,
    close/1,
    shutdown/1,
    headers/5,
    request/6,
    data/4,
    await/3,
    await_body/3,
    cancel/2,
    update_flow/3,
    flush/1,
    fin_to_ffi/1,
    ws_upgrade/4,
    ws_send/3,
    safe_message_to_map/1,
    options_to_gun/1,
    apply_secure_tls_defaults/2
]).

open(Host, Port, Options) ->
    try
        GunOptions = apply_secure_tls_defaults(Host, options_to_gun(Options)),
        with_normalize(connection, fun() ->
            gun:open(normalize_host(Host), Port, GunOptions)
        end)
    catch
        error:{options, Reason}:_Stack -> {error, {invalid_options, Reason}};
        error:{invalid_options, Reason}:_Stack -> {error, {invalid_options, Reason}};
        Class:Reason:_Stack -> {error, {erlang_error, {Class, Reason}}}
    end.

await_up(ConnPid, Timeout) ->
    with_normalize(connection, fun() ->
        gun:await_up(ConnPid, timeout_to_gun(Timeout))
    end).

close(ConnPid) ->
    with_normalize(connection_error, fun() ->
        case gun:close(ConnPid) of
            {error, Reason} -> {error, {error, Reason}};
            Other -> Other
        end
    end).

shutdown(ConnPid) -> with_normalize(connection_error, fun() -> gun:shutdown(ConnPid) end).

request(ConnPid, Method, Path, Headers, Body, ReqOpts) ->
    with_normalize(stream_erlang, fun() ->
        {ok, gun:request(
            ConnPid,
            to_binary(Method),
            to_binary(Path),
            normalize_headers(Headers),
            Body,
            req_opts_to_gun(ReqOpts)
        )}
    end).

headers(ConnPid, Method, Path, Headers, ReqOpts) ->
    with_normalize(stream_erlang, fun() ->
        {ok, gun:headers(
            ConnPid,
            to_binary(Method),
            to_binary(Path),
            normalize_headers(Headers),
            req_opts_to_gun(ReqOpts)
        )}
    end).

data(ConnPid, StreamRef, Fin, Data) ->
    with_normalize(stream, fun() ->
        gun:data(ConnPid, StreamRef, fin_to_gun(Fin), Data)
    end).

await(ConnPid, StreamRef, Timeout) ->
    with_normalize(stream_erlang, fun() ->
        safe_message_to_map(gun:await(ConnPid, StreamRef, timeout_to_gun(Timeout)))
    end).

await_body(ConnPid, StreamRef, Timeout) ->
    with_normalize(stream_erlang, fun() ->
        case gun:await_body(ConnPid, StreamRef, timeout_to_gun(Timeout)) of
            {ok, Body} -> {ok, iolist_to_binary(Body)};
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

ws_upgrade(ConnPid, Path, Headers, WsOpts) ->
    try
        GunOpts = ws_opts_to_gun(WsOpts),
        with_normalize(stream_erlang, fun() ->
            try
                case gun:ws_upgrade(ConnPid, Path, normalize_headers(Headers), GunOpts) of
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
        error:{invalid_options, Reason}:_Stack -> {error, {invalid_options, Reason}};
        Class:Reason:_Stack -> {error, {erlang_error, {Class, Reason}}}
    end.

ws_send(ConnPid, StreamRef, Frames) ->
    try
        GunFrames = gleam_frame_or_frames_to_gun(Frames),
        with_normalize(stream_erlang, fun() ->
            gun:ws_send(ConnPid, StreamRef, GunFrames)
        end)
    catch
        error:{invalid_frame, Reason}:_Stack -> {error, {invalid_message, {invalid_frame, Reason}}};
        Class:Reason:_Stack -> {error, {erlang_error, {Class, Reason}}}
    end.

with_normalize(Tag, Fun) ->
    try Fun() of
        ok -> {ok, nil};
        {ok, _} = Result -> Result;
        {error, timeout} -> {error, timeout};
        {error, Reason} -> {error, normalize_error(Tag, Reason)};
        Other -> {error, normalize_error(Tag, Other)}
    catch
        Class:Reason:_Stack -> {error, caught_error(Tag, Class, Reason)}
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

%% Convert a Gleam Frame (compiled Erlang tagged tuple) to a Gun frame term.
%% Gleam compiles:
%%   Text(S)               -> {text, S}
%%   Binary(B)             -> {binary, B}
%%   Close                 -> close  (zero-arg atom)
%%   CloseWithReason(C, R) -> {close_with_reason, C, R}
%%   Ping(B)               -> {ping, B}
%%   Pong(B)               -> {pong, B}
gleam_frame_or_frames_to_gun(Frames) when is_list(Frames) ->
    [gleam_frame_to_gun(Frame) || Frame <- Frames];
gleam_frame_or_frames_to_gun(Frame) ->
    gleam_frame_to_gun(Frame).

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

options_to_gun(Options) when is_map(Options) ->
    WithTransport = case maps:get(<<"transport">>, Options, auto) of
        auto -> #{};
        <<"auto">> -> #{};
        tcp -> #{transport => tcp};
        <<"tcp">> -> #{transport => tcp};
        tls -> #{transport => tls};
        <<"tls">> -> #{transport => tls}
    end,
    WithProtocols = case maps:get(<<"protocols">>, Options, undefined) of
        undefined -> WithTransport;
        Protocols -> WithTransport#{protocols => [protocol_to_gun(P) || P <- Protocols]}
    end,
    WithTls = case tls_opts_from_options(Options) of
        undefined -> WithProtocols;
        TlsOpts -> WithProtocols#{tls_opts => tls_opts_to_gun(TlsOpts)}
    end,
    WithRetry = case maps:get(<<"retry">>, Options, undefined) of
        undefined -> WithTls;
        Retry -> WithTls#{retry => timeout_to_gun(Retry)}
    end,
    case maps:get(<<"connect_timeout">>, Options, undefined) of
        undefined -> WithRetry;
        Timeout -> WithRetry#{connect_timeout => timeout_to_gun(Timeout)}
    end;
options_to_gun(Options) ->
    error({invalid_options, Options}).

tls_opts_from_options(Options) when is_map(Options) ->
    case maps:get(<<"tls_opts">>, Options, undefined) of
        undefined ->
            case maps:get(<<"transport_opts">>, Options, undefined) of
                TransportOpts when is_map(TransportOpts) -> maps:get(<<"tls_opts">>, TransportOpts, undefined);
                _ -> undefined
            end;
        TlsOpts -> TlsOpts
    end.

tls_opts_to_gun(TlsOpts) when is_list(TlsOpts) ->
    [tls_opt_to_gun(Opt) || Opt <- TlsOpts];
tls_opts_to_gun(TlsOpts) ->
    error({invalid_options, {tls_opts, TlsOpts}}).

tls_opt_to_gun([Key, Value]) ->
    GunKey = tls_opt_key_to_atom(Key),
    {GunKey, tls_opt_value_to_gun(GunKey, Value)};
tls_opt_to_gun({Key, Value}) ->
    GunKey = tls_opt_key_to_atom(Key),
    {GunKey, tls_opt_value_to_gun(GunKey, Value)};
tls_opt_to_gun(Other) ->
    error({invalid_options, {tls_opts, Other}}).

tls_opt_key_to_atom(Key) when is_atom(Key) -> Key;
tls_opt_key_to_atom(Key) when is_binary(Key) ->
    try binary_to_existing_atom(Key, utf8) of
        Atom -> Atom
    catch
        error:badarg:_Stack -> error({invalid_options, {tls, {unsupported_option, Key}}})
    end;
tls_opt_key_to_atom(Key) when is_list(Key) ->
    try list_to_existing_atom(Key) of
        Atom -> Atom
    catch
        error:badarg:_Stack -> error({invalid_options, {tls, {unsupported_option, Key}}})
    end.

tls_opt_value_to_gun(verify, Verify) -> verify_mode_to_gun(Verify);
tls_opt_value_to_gun(versions, Versions) when is_list(Versions) ->
    [tls_version_to_gun(Version) || Version <- Versions];
tls_opt_value_to_gun(ciphers, Ciphers) when is_list(Ciphers) ->
    [unicode_value_to_list(Cipher) || Cipher <- Ciphers];
tls_opt_value_to_gun(cacerts, CACerts) when is_list(CACerts) ->
    [iolist_to_binary(CACert) || CACert <- CACerts];
tls_opt_value_to_gun(cacertfile, Path) -> file_name_to_gun(Path);
tls_opt_value_to_gun(certfile, Path) -> file_name_to_gun(Path);
tls_opt_value_to_gun(keyfile, Path) -> file_name_to_gun(Path);
tls_opt_value_to_gun(server_name_indication, Value) -> server_name_indication_to_gun(Value);
tls_opt_value_to_gun(_Key, Value) -> Value.

verify_mode_to_gun(verify_peer) -> verify_peer;
verify_mode_to_gun(<<"verify_peer">>) -> verify_peer;
verify_mode_to_gun("verify_peer") -> verify_peer;
verify_mode_to_gun(verify_none) -> verify_none;
verify_mode_to_gun(<<"verify_none">>) -> verify_none;
verify_mode_to_gun("verify_none") -> verify_none;
verify_mode_to_gun(Verify) -> Verify.

tls_version_to_gun('tlsv1.2') -> 'tlsv1.2';
tls_version_to_gun(<<"tlsv1.2">>) -> 'tlsv1.2';
tls_version_to_gun("tlsv1.2") -> 'tlsv1.2';
tls_version_to_gun('tlsv1.3') -> 'tlsv1.3';
tls_version_to_gun(<<"tlsv1.3">>) -> 'tlsv1.3';
tls_version_to_gun("tlsv1.3") -> 'tlsv1.3';
tls_version_to_gun(Version) -> Version.

server_name_indication_to_gun(disable) -> disable;
server_name_indication_to_gun(Value) -> unicode_value_to_list(Value).

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

apply_secure_tls_defaults(_Host, GunOptions) when not is_map(GunOptions) ->
    GunOptions;
apply_secure_tls_defaults(Host, GunOptions) ->
    case tls_relevant_transport(GunOptions) of
        false -> GunOptions;
        true ->
            TlsOpts0 = maps:get(tls_opts, GunOptions, []),
            TlsOpts = merge_secure_tls_defaults(Host, TlsOpts0),
            GunOptions#{tls_opts => TlsOpts}
    end.

tls_relevant_transport(GunOptions) ->
    case maps:get(transport, GunOptions, auto) of
        tls -> true;
        auto -> true;
        _ -> false
    end.

merge_secure_tls_defaults(Host, TlsOpts) when is_list(TlsOpts) ->
    Verify = proplist_get(verify, TlsOpts),
    EffectiveVerify = case Verify of
        undefined -> verify_peer;
        V -> V
    end,
    Step1 = case Verify of
        undefined -> [{verify, verify_peer} | TlsOpts];
        _ -> TlsOpts
    end,
    case EffectiveVerify of
        verify_peer -> add_verify_peer_defaults(Host, Step1);
        _ -> Step1
    end.

add_verify_peer_defaults(Host, TlsOpts) ->
    TlsOpts1 = maybe_add_cacerts(TlsOpts),
    TlsOpts2 = maybe_add(versions, ['tlsv1.3', 'tlsv1.2'], TlsOpts1),
    TlsOpts3 = maybe_add(depth, 10, TlsOpts2),
    TlsOpts4 = maybe_add_sni(Host, TlsOpts3),
    maybe_add_hostname_match(TlsOpts4).

maybe_add(Key, Value, TlsOpts) ->
    case proplist_has(Key, TlsOpts) of
        true -> TlsOpts;
        false -> [{Key, Value} | TlsOpts]
    end.

maybe_add_cacerts(TlsOpts) ->
    case proplist_has(cacerts, TlsOpts) orelse proplist_has(cacertfile, TlsOpts) of
        true -> TlsOpts;
        false ->
            case system_cacerts() of
                {ok, CACerts} -> [{cacerts, CACerts} | TlsOpts];
                error -> error({invalid_options, {tls, no_system_cacerts}})
            end
    end.

system_cacerts() ->
    try public_key:cacerts_get() of
        CACerts when is_list(CACerts), CACerts =/= [] -> {ok, CACerts}
    catch
        _:_ -> error
    end.

maybe_add_sni(Host, TlsOpts) ->
    case proplist_has(server_name_indication, TlsOpts) of
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

maybe_add_hostname_match(TlsOpts) ->
    case proplist_has(customize_hostname_check, TlsOpts) of
        true -> TlsOpts;
        false ->
            try public_key:pkix_verify_hostname_match_fun(https) of
                MatchFun ->
                    [{customize_hostname_check, [{match_fun, MatchFun}]} | TlsOpts]
            catch
                _:_ -> TlsOpts
            end
    end.

proplist_has(Key, List) -> proplist_get(Key, List) =/= undefined.

proplist_get(Key, [{Key, Value} | _]) -> Value;
proplist_get(Key, [_ | Rest]) -> proplist_get(Key, Rest);
proplist_get(_Key, []) -> undefined.

%% ---------------------------------------------------------------------------

file_name_to_gun(Value) -> unicode_value_to_list(Value).

unicode_value_to_list(Value) when is_binary(Value) -> unicode:characters_to_list(Value);
unicode_value_to_list(Value) when is_list(Value) -> Value;
unicode_value_to_list(Value) -> Value.

req_opts_to_gun(ReqOpts) when is_map(ReqOpts) -> ReqOpts;
req_opts_to_gun(_) -> #{}.

ws_opts_to_gun(WsOpts) when is_map(WsOpts) ->
    maps:fold(
        fun(Key, Value, Acc) ->
            GunKey = ws_opt_key_to_atom(Key),
            Acc#{GunKey => ws_opt_value_to_gun(GunKey, Value)}
        end,
        #{},
        WsOpts
    );
ws_opts_to_gun(_) -> #{}.

ws_opt_key_to_atom(closing_timeout) -> closing_timeout;
ws_opt_key_to_atom(compress) -> compress;
ws_opt_key_to_atom(default_protocol) -> default_protocol;
ws_opt_key_to_atom(flow) -> flow;
ws_opt_key_to_atom(keepalive) -> keepalive;
ws_opt_key_to_atom(protocols) -> protocols;
ws_opt_key_to_atom(reply_to) -> reply_to;
ws_opt_key_to_atom(silence_pings) -> silence_pings;
ws_opt_key_to_atom(tunnel) -> tunnel;
ws_opt_key_to_atom(user_opts) -> user_opts;
ws_opt_key_to_atom(<<"closing_timeout">>) -> closing_timeout;
ws_opt_key_to_atom(<<"compress">>) -> compress;
ws_opt_key_to_atom(<<"default_protocol">>) -> default_protocol;
ws_opt_key_to_atom(<<"flow">>) -> flow;
ws_opt_key_to_atom(<<"keepalive">>) -> keepalive;
ws_opt_key_to_atom(<<"protocols">>) -> protocols;
ws_opt_key_to_atom(<<"reply_to">>) -> reply_to;
ws_opt_key_to_atom(<<"silence_pings">>) -> silence_pings;
ws_opt_key_to_atom(<<"tunnel">>) -> tunnel;
ws_opt_key_to_atom(<<"user_opts">>) -> user_opts;
ws_opt_key_to_atom("closing_timeout") -> closing_timeout;
ws_opt_key_to_atom("compress") -> compress;
ws_opt_key_to_atom("default_protocol") -> default_protocol;
ws_opt_key_to_atom("flow") -> flow;
ws_opt_key_to_atom("keepalive") -> keepalive;
ws_opt_key_to_atom("protocols") -> protocols;
ws_opt_key_to_atom("reply_to") -> reply_to;
ws_opt_key_to_atom("silence_pings") -> silence_pings;
ws_opt_key_to_atom("tunnel") -> tunnel;
ws_opt_key_to_atom("user_opts") -> user_opts;
ws_opt_key_to_atom(Key) -> error({invalid_options, {ws, {unsupported_option, Key}}}).

ws_opt_value_to_gun(closing_timeout, Timeout) -> timeout_to_gun(Timeout);
ws_opt_value_to_gun(keepalive, Timeout) -> timeout_to_gun(Timeout);
ws_opt_value_to_gun(default_protocol, Module) -> module_name_to_atom(Module);
ws_opt_value_to_gun(protocols, Protocols) when is_list(Protocols) ->
    [ws_protocol_to_gun(Protocol) || Protocol <- Protocols];
ws_opt_value_to_gun(_Key, Value) -> Value.

ws_protocol_to_gun([Protocol, Module]) -> {to_binary(Protocol), module_name_to_atom(Module)};
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

timeout_to_gun(infinity) -> infinity;
timeout_to_gun(<<"infinity">>) -> infinity;
timeout_to_gun({milliseconds, Timeout}) when is_integer(Timeout) -> Timeout;
timeout_to_gun(Timeout) when is_integer(Timeout) -> Timeout.

protocol_to_gun(http) -> http;
protocol_to_gun(<<"http">>) -> http;
protocol_to_gun(http2) -> http2;
protocol_to_gun(<<"http2">>) -> http2.

fin_to_gun(fin) -> fin;
fin_to_gun(<<"fin">>) -> fin;
fin_to_gun(no_fin) -> nofin;
fin_to_gun(nofin) -> nofin;
fin_to_gun(<<"nofin">>) -> nofin;
fin_to_gun(Other) -> error({invalid_fin, Other}).

fin_to_ffi(Fin) -> fin_to_gun(Fin).

normalize_connection_error(timeout) -> timeout;
normalize_connection_error({down, _Protocol, Reason, _KilledStreams, _UnprocessedStreams}) ->
    {connection_down, Reason};
normalize_connection_error(Reason) -> {connection_error, Reason}.

normalize_stream_error(timeout) -> timeout;
normalize_stream_error({stream_error, Reason}) -> {stream_error, Reason};
normalize_stream_error({connection_error, Reason}) -> {connection_error, Reason};
normalize_stream_error(Reason) -> {stream_error, Reason}.

safe_message_to_map(Message) ->
    try message_to_map(Message) of
        Map -> {ok, Map}
    catch
        error:{invalid_message, Reason}:_Stack -> {error, {invalid_message, Reason}};
        error:{stream_error, Reason}:_Stack -> {error, {stream_error, Reason}};
        error:timeout:_Stack -> {error, timeout};
        Class:Reason:_Stack -> {error, {erlang_error, {Class, Reason}}}
    end.

message_to_map({inform, Status, Headers}) ->
    #{<<"type">> => <<"inform">>, <<"status">> => Status, <<"headers">> => normalize_headers(Headers)};
message_to_map({response, Fin, Status, Headers}) ->
    #{<<"type">> => <<"response">>, <<"fin">> => fin_to_bool(Fin), <<"status">> => Status, <<"headers">> => normalize_headers(Headers)};
message_to_map({data, Fin, Data}) ->
    #{<<"type">> => <<"data">>, <<"fin">> => fin_to_bool(Fin), <<"data">> => iolist_to_binary(Data)};
message_to_map({trailers, Headers}) ->
    #{<<"type">> => <<"trailers">>, <<"headers">> => normalize_headers(Headers)};
message_to_map({push, NewStreamRef, Method, URI, Headers}) ->
    #{<<"type">> => <<"push">>, <<"stream">> => NewStreamRef, <<"method">> => to_binary(Method), <<"uri">> => to_binary(URI), <<"headers">> => normalize_headers(Headers)};
message_to_map({upgrade, Protocols, Headers}) ->
    #{<<"type">> => <<"upgrade">>, <<"protocols">> => [to_binary(P) || P <- Protocols], <<"headers">> => normalize_headers(Headers)};
message_to_map({ws, Frame}) ->
    #{<<"type">> => <<"websocket">>, <<"frame">> => frame_to_map(Frame)};
message_to_map({error, timeout}) ->
    error(timeout);
message_to_map({error, Reason}) ->
    error({stream_error, Reason});
message_to_map(Other) ->
    error({invalid_message, Other}).

frame_to_map({text, Data}) ->
    case validate_utf8(Data) of
        {ok, ValidText} ->
            #{<<"type">> => <<"text">>, <<"data">> => ValidText};
        {error, invalid_utf8} ->
            error({invalid_message, {ws, {text, invalid_utf8}}})
    end;
frame_to_map({binary, Data}) -> #{<<"type">> => <<"binary">>, <<"data">> => iolist_to_binary(Data)};
frame_to_map({close, Code, Reason}) ->
    #{<<"type">> => <<"close_with_reason">>,
      <<"code">> => Code,
      <<"reason">> => iolist_to_binary(Reason)};
frame_to_map({ping, Data}) -> #{<<"type">> => <<"ping">>, <<"data">> => iolist_to_binary(Data)};
frame_to_map({pong, Data}) -> #{<<"type">> => <<"pong">>, <<"data">> => iolist_to_binary(Data)};
frame_to_map(close) -> #{<<"type">> => <<"close">>};
frame_to_map(Other) -> error({invalid_message, {ws, Other}}).

fin_to_bool(fin) -> true;
fin_to_bool(nofin) -> false;
fin_to_bool(true) -> true;
fin_to_bool(false) -> false;
fin_to_bool(Other) -> error({invalid_fin, Other}).

normalize_headers(Headers) ->
    [{to_binary(Name), to_binary(Value)} || {Name, Value} <- Headers].

to_binary(Value) when is_binary(Value) -> Value;
to_binary(Value) when is_atom(Value) -> atom_to_binary(Value, utf8);
to_binary(Value) when is_list(Value) -> iolist_to_binary(Value);
to_binary(Value) when is_integer(Value) -> integer_to_binary(Value);
to_binary(Value) -> error({invalid_binary, Value}).
