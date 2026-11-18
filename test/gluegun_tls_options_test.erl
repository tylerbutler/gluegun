-module(gluegun_tls_options_test).

-export([effective_ca_options/3, init/2, domain_lookup_start/2,
    domain_lookup_end/2, connect_start/2, connect_end/2, tls_handshake_start/2]).

%% Observe the real Gun handshake event, after both ensure_tls_opts passes.
%% The passive loopback listener's backlog suffices for TCP establishment.
%% Park before SSL reads the supplied fixture certificates or file paths.
effective_ca_options(Options, ExpectedCertificates, ExpectedFile) ->
    {ok, Listener} = gen_tcp:listen(0, [binary, {active, false}, {ip, {127,0,0,1}}]),
    Ref = make_ref(),
    Parent = self(),
    try
        {ok, {_, Port}} = inet:sockname(Listener),
        Prepared = gluegun_ffi:prepare_connect_options(<<"127.0.0.1">>, Port, Options, #{
            cacerts_fun => fun() -> Parent ! {ca_lookup, Ref}, [] end,
            cacerts_cache_key => Ref
        }),
        {ok, Conn} = gun:open({127,0,0,1}, Port,
            Prepared#{event_handler => {?MODULE, {Parent, Ref}}}),
        try
            receive
                {effective_tls_options, Ref, Conn, Effective} ->
                    verify_none = proplists:get_value(verify, Effective),
                    Certificates = case lists:keyfind(cacerts, 1, Effective) of
                        false -> none;
                        {cacerts, Values} -> {some, Values}
                    end,
                    File = case lists:keyfind(cacertfile, 1, Effective) of
                        false -> none;
                        {cacertfile, Path} -> {some, unicode:characters_to_binary(Path)}
                    end,
                    Unchanged = ca_options(maps:get(tls_opts, Prepared)) =:= ca_options(Effective),
                    %% OTP may load internal certificate records, not DER binaries.
                    %% Compare here rather than misrepresenting those as Gleam BitArrays.
                    Matches = {Certificates, File} =:= {ExpectedCertificates, ExpectedFile},
                    {Matches, Unchanged, lookup_count(Ref, 0)}
            after 2000 ->
                error(tls_handshake_event_timeout)
            end
        after
            {ok, nil} = gluegun_ffi:terminate(Conn),
            receive {effective_tls_options, Ref, Conn, _} -> ok after 0 -> ok end
        end
    after
        gen_tcp:close(Listener),
        persistent_term:erase(Ref),
        lookup_count(Ref, 0)
    end.

ca_options(Options) ->
    [Option || {Key, _} = Option <- Options, Key =:= cacerts orelse Key =:= cacertfile].

lookup_count(Ref, Count) ->
    receive
        {ca_lookup, Ref} -> lookup_count(Ref, Count + 1)
    after 0 -> Count
    end.

init(_Event, State) -> State.
domain_lookup_start(_Event, State) -> State.
domain_lookup_end(_Event, State) -> State.
connect_start(_Event, State) -> State.
connect_end(_Event, State) -> State.

tls_handshake_start(#{tls_opts := Options}, {Parent, Ref} = State) ->
    Parent ! {effective_tls_options, Ref, self(), Options},
    %% The owner always kills and monitors Gun in an after block.
    receive release_tls_options -> State end.
