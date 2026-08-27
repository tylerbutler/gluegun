-module(gluegun_ws_test).

%% Typed WebSocket helpers for deterministic Gleam tests. Gun casts are sent to
%% the test process itself, captured, and projected back into Gleam values.

-export([
    capture_ws_send_frame/1,
    capture_ws_send_frames/0,
    capture_ws_upgrade_options/1,
    current_process/0,
    invalid_ws_send_frame_result/0,
    invalid_ws_send_frame_list_result/0,
    invalid_ws_send_text_utf8_result/0,
    invalid_ws_upgrade_options_result/0,
    ws_close_message/0,
    ws_close_with_reason_message/0
]).

%% Send one frame through the real FFI, then read the frame Gun was asked to
%% write and hand it back as a raw Gun message for `gluegun/message.decode`.
capture_ws_send_frame(Frame) ->
    StreamRef = make_ref(),
    case gluegun_ffi:ws_send(self(), StreamRef, Frame) of
        {ok, nil} ->
            receive
                {'$gen_cast', {ws_send, _ReplyTo, StreamRef, GunFrame}} ->
                    {ok, {ws, GunFrame}}
            after 0 ->
                {error, {erlang_error, <<"no ws_send message"/utf8>>}}
            end;
        Error ->
            Error
    end.

capture_ws_send_frames() ->
    receive
        {'$gen_cast', {ws_send, _ReplyTo, _StreamRef, GunFrames}} when is_list(GunFrames) ->
            {ok, [gun_frame_to_pair(Frame) || Frame <- GunFrames]};
        {'$gen_cast', {ws_send, _ReplyTo, _StreamRef, GunFrame}} ->
            {ok, [gun_frame_to_pair(GunFrame)]}
    after 0 ->
        {error, nil}
    end.

%% Project the Gun `ws_opts()` map Gun was called with into a Gleam tuple of
%% `{Compress, SilencePings, Flow, Keepalive, ClosingTimeout, DefaultProtocol,
%% Protocols}`, where the first six are `gleam/option.Option` values.
capture_ws_upgrade_options(Options) ->
    case gluegun_ffi:ws_upgrade(self(), <<"/ws">>, [], Options) of
        {ok, StreamRef} ->
            receive
                {'$gen_cast', {ws_upgrade, _ReplyTo, StreamRef, _Path, _Headers, GunOpts}} ->
                    {ok, summarize_ws_opts(GunOpts)}
            after 0 ->
                {error, {erlang_error, <<"no ws_upgrade message"/utf8>>}}
            end;
        Error ->
            Error
    end.

invalid_ws_send_frame_result() ->
    gluegun_ffi:ws_send(self(), make_ref(), bad_frame).

invalid_ws_send_frame_list_result() ->
    gluegun_ffi:ws_send(self(), make_ref(), [{text, <<"ok">>}, bad_frame]).

invalid_ws_send_text_utf8_result() ->
    gluegun_ffi:ws_send(self(), make_ref(), {text, <<255>>}).

%% Bypasses the Gleam `UpgradeOption` type on purpose: checks that Gun's own
%% ws_opts validation is still surfaced as `InvalidOptions`.
invalid_ws_upgrade_options_result() ->
    gluegun_ffi:ws_upgrade(self(), <<"/ws">>, [], [{compress, <<"not-a-boolean">>}]).

current_process() ->
    self().

%% Raw Gun WebSocket close messages.
ws_close_message() ->
    {ws, close}.

ws_close_with_reason_message() ->
    {ws, {close, 1001, <<"going away">>}}.

gun_frame_to_pair({text, Data}) -> {<<"text">>, Data};
gun_frame_to_pair({binary, Data}) -> {<<"binary">>, Data};
gun_frame_to_pair({ping, Data}) -> {<<"ping">>, Data};
gun_frame_to_pair({pong, Data}) -> {<<"pong">>, Data};
gun_frame_to_pair(close) -> {<<"close">>, <<>>};
gun_frame_to_pair({close, Code, Reason}) ->
    {<<"close_with_reason">>, <<(integer_to_binary(Code))/binary, $:, Reason/binary>>}.

summarize_ws_opts(GunOpts) when is_map(GunOpts) ->
    {
        optional(maps:get(compress, GunOpts, undefined)),
        optional(maps:get(silence_pings, GunOpts, undefined)),
        optional(maps:get(flow, GunOpts, undefined)),
        optional_timeout(maps:get(keepalive, GunOpts, undefined)),
        optional_timeout(maps:get(closing_timeout, GunOpts, undefined)),
        optional_module(maps:get(default_protocol, GunOpts, undefined)),
        [{Protocol, atom_to_binary(Module, utf8)} || {Protocol, Module} <- maps:get(protocols, GunOpts, [])]
    }.

optional(undefined) -> none;
optional(Value) -> {some, Value}.

optional_timeout(undefined) -> none;
optional_timeout(infinity) -> {some, <<"infinity"/utf8>>};
optional_timeout(Milliseconds) when is_integer(Milliseconds) ->
    {some, integer_to_binary(Milliseconds)}.

optional_module(undefined) -> none;
optional_module(Module) when is_atom(Module) -> {some, atom_to_binary(Module, utf8)}.
