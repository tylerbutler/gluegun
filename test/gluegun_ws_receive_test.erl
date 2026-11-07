-module(gluegun_ws_receive_test).
-export([empty_ping_frame/0, empty_pong_frame/0,
    assert_cleanup_success/0, assert_cleanup_callback_failure/0]).

%% Typed constructors for the opaque raw GunFrame used by Gleam tests.
%% Cowlib emits atoms, rather than tuples, for empty control payloads.
%% Gleam: () -> GunFrame (the same type as gluegun_ffi_test:ping_frame/1).
empty_ping_frame() -> ping.
empty_pong_frame() -> pong.

%% Gleam: () -> Nil. These run in the caller's process, just like Unitest
%% wire tests, and raise on leaked connection messages or a lost sentinel.
assert_cleanup_success() -> assert_cleanup(success).
assert_cleanup_callback_failure() -> assert_cleanup(callback_failure).

assert_cleanup(Outcome) ->
    Ref = make_ref(),
    self() ! {Ref, sentinel},
    Callback = fun(Conn, Stream) ->
        self() ! {Ref, connection, Conn},
        Socket = gluegun@websocket:socket(Conn, Stream, {milliseconds, 5000}),
        {ok, {text, <<"hello">>}} = gluegun@websocket:receive_app_frame(Socket),
        {ok, {binary, <<1, 2, 3>>}} = gluegun@websocket:receive_app_frame(Socket),
        {ok, nil} = gluegun@websocket:send_text(Socket, <<"controls received">>),
        {ok, {text, <<"one pong">>}} = gluegun@websocket:receive_app_frame(Socket),
        %% Wait for the peer's actual disconnect and put its notification
        %% back. Cleanup must remove this deterministically queued gun_down.
        receive
            {gun_down, Conn, _, _, _} = Down -> self() ! Down
        after 5000 ->
            error(cleanup_regression_peer_did_not_disconnect)
        end,
        case Outcome of
            success -> nil;
            callback_failure -> error({cleanup_regression_callback_failed, Ref})
        end
    end,
    try
        case Outcome of
            success ->
                nil = gluegun_ws_control_test:with_incoming_controls(
                    false, <<>>, Callback);
            callback_failure ->
                try gluegun_ws_control_test:with_incoming_controls(
                    false, <<>>, Callback) of
                    _ -> error(cleanup_regression_callback_did_not_fail)
                catch
                    error:{cleanup_regression_callback_failed, Ref} -> ok
                end
        end,
        Conn = receive
            {Ref, connection, Connection} -> Connection
        after 0 ->
            error(cleanup_regression_missing_connection)
        end,
        false = erlang:is_process_alive(Conn),
        {messages, Messages} = process_info(self(), messages),
        [] = [Message || Message <- Messages, belongs_to_connection(Message, Conn)],
        receive
            {Ref, sentinel} -> nil
        after 0 ->
            error(cleanup_regression_lost_sentinel)
        end
    after
        %% Only this regression's private bookkeeping is removed on failure.
        receive {Ref, sentinel} -> ok after 0 -> ok end,
        receive {Ref, connection, _} -> ok after 0 -> ok end
    end.

belongs_to_connection({'DOWN', _, process, Conn, _}, Conn) -> true;
belongs_to_connection(Message, Conn)
    when is_tuple(Message), tuple_size(Message) >= 2, element(2, Message) =:= Conn ->
    true;
belongs_to_connection(_, _) -> false.
