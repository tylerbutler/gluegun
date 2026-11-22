-module(webprobe_protocol_test_ffi).
-export([with_listener/1, capture_client_hello/2]).

%% Like the root loopback TLS helpers, bind IPv4 loopback on an ephemeral
%% port. Unlike their completed handshakes, hello inspection needs no test
%% certificate, CA override, or HTTP server. No custom process is spawned.
%% The external HelloListener is an SSL listen socket scoped to Callback.
with_listener(Callback) ->
    case ssl:listen(0, [binary, {active, false}, {ip, {127, 0, 0, 1}},
                       {handshake, hello}]) of
        {ok, Listener} ->
            try
                case ssl:sockname(Listener) of
                    {ok, {_, Port}} -> Callback(Listener, Port);
                    {error, Reason} -> failure(sockname, Reason)
                end
            after
                ssl:close(Listener)
            end;
        {error, Reason} -> failure(listen, Reason)
    end.

%% Open is a Gleam callback returning Result(Connection, String). Register
%% cleanup immediately after it returns the connection. Exceptions/assertion
%% failures propagate, but every acquired resource is released in after.
capture_client_hello(Listener, Open) ->
    case Open() of
        {ok, Connection} ->
            try
                accept_hello(Listener)
            after
                %% Existing typed API force-stops Gun even during TLS setup,
                %% waits for exit, and flushes only this connection's messages.
                {ok, nil} = 'gluegun@connection':terminate(Connection)
            end;
        {error, _} = Error -> Error
    end.

accept_hello(Listener) ->
    case ssl:transport_accept(Listener, 2000) of
        {ok, Socket} ->
            try
                case ssl:handshake(Socket, 2000) of
                    {ok, Socket, #{alpn := Encoded}} when is_binary(Encoded) ->
                        {ok, Encoded};
                    {ok, Socket, _Extensions} ->
                        {error, <<"ClientHello has no ALPN extension">>};
                    {error, Reason} -> failure(handshake, Reason)
                end
            after
                %% OTP 27 postpones close calls while in user_hello. Cancel
                %% first, or even close/2's timeout cannot bound that call.
                %% Both calls tolerate an already-closed handshake socket.
                ssl:handshake_cancel(Socket),
                ssl:close(Socket, 1000)
            end;
        {error, Reason} -> failure(accept, Reason)
    end.

failure(Stage, Reason) ->
    {error, iolist_to_binary(io_lib:format("~p: ~p", [Stage, Reason]))}.
