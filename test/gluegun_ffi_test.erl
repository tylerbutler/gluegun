-module(gluegun_ffi_test).

-export([
    test_response_message/0,
    test_data_message/0,
    test_stream_ref/0,
    test_erlang_error/0,
    test_stream_error/0,
    test_invalid_utf8_websocket/0,
    gun_tls_opts/1,
    secure_tls_opts_summary/2,
    secure_tls_opts_with_empty_cacerts/2,
    secure_tls_opts_with_hostname_match_failure/2,
    secure_tls_opts_caches_cacerts/2
]).

test_response_message() ->
    #{<<"type">> => <<"response">>, <<"fin">> => true, <<"status">> => 200, <<"headers">> => [{<<"Content-Type">>, <<"text/plain">>}]}.

test_data_message() ->
    #{<<"type">> => <<"data">>, <<"fin">> => false, <<"data">> => <<"hello">>}.

test_stream_ref() ->
    make_ref().

test_erlang_error() ->
    {erlang_error, {error, badarg}}.

test_stream_error() ->
    {stream_error, boom}.

test_invalid_utf8_websocket() ->
    {ws, {text, <<255>>}}.

gun_tls_opts(Options) ->
    maps:get(tls_opts, gluegun_ffi:options_to_gun(Options), undefined).

%% Apply secure defaults and project the resulting tls_opts to a Gleam-friendly
%% map: `verify`, `versions`, `depth`, `sni`, plus booleans flagging the
%% presence of `cacerts` (list of binaries from public_key:cacerts_get/0) and
%% the HTTPS hostname match function.
secure_tls_opts_summary(Host, Options) ->
    Gun = gluegun_ffi:apply_secure_tls_defaults(Host, gluegun_ffi:options_to_gun(Options)),
    summarize_secure_tls_opts(Gun).

secure_tls_opts_with_empty_cacerts(Host, Options) ->
    CacheKey = make_ref(),
    try
        Gun = gluegun_ffi:apply_secure_tls_defaults(
            Host,
            gluegun_ffi:options_to_gun(Options),
            #{cacerts_fun => fun() -> [] end, cacerts_cache_key => CacheKey}
        ),
        {ok, summarize_secure_tls_opts(Gun)}
    catch
        error:{invalid_options, Reason}:_Stack -> {error, {invalid_options, Reason}};
        Class:Reason:_Stack -> {error, {erlang_error, {Class, Reason}}}
    end.

secure_tls_opts_with_hostname_match_failure(Host, Options) ->
    try
        Gun = gluegun_ffi:apply_secure_tls_defaults(
            Host,
            gluegun_ffi:options_to_gun(Options),
            #{hostname_match_fun => fun(_Protocol) -> error(test_hostname_match_failure) end}
        ),
        {ok, summarize_secure_tls_opts(Gun)}
    catch
        error:{invalid_options, Reason}:_Stack -> {error, {invalid_options, Reason}};
        Class:Reason:_Stack -> {error, {erlang_error, {Class, Reason}}}
    end.

secure_tls_opts_caches_cacerts(Host, Options) ->
    Parent = self(),
    CACertsFun = fun() ->
        Parent ! cacerts_loaded,
        [<<"fake-der-ca">>]
    end,
    GunOptions = gluegun_ffi:options_to_gun(Options),
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
    Get = fun(K) -> proplists:get_value(K, TlsOpts) end,
    Sni = case Get(server_name_indication) of
        undefined -> undefined;
        disable -> <<"disable">>;
        V when is_list(V) -> unicode:characters_to_binary(V);
        V when is_binary(V) -> V
    end,
    Versions = case Get(versions) of
        undefined -> undefined;
        Vs when is_list(Vs) -> [atom_to_binary(A, utf8) || A <- Vs]
    end,
    Verify = case Get(verify) of
        undefined -> undefined;
        Atom when is_atom(Atom) -> atom_to_binary(Atom, utf8)
    end,
    Depth = Get(depth),
    HasCACerts = case Get(cacerts) of
        undefined -> false;
        L when is_list(L), L =/= [] -> true;
        _ -> false
    end,
    HasHostnameCheck = case Get(customize_hostname_check) of
        undefined -> false;
        _ -> true
    end,
    #{
        <<"verify">> => Verify,
        <<"versions">> => Versions,
        <<"depth">> => Depth,
        <<"sni">> => Sni,
        <<"has_cacerts">> => HasCACerts,
        <<"has_hostname_check">> => HasHostnameCheck
    }.
