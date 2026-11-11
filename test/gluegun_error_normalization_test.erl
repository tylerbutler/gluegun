-module(gluegun_error_normalization_test).

%% Typed fixtures only: real pid/reference handles, Gun mailbox messages,
%% and the existing boundary's Result(Connection, GluegunError).
-export([
    dead_connection/0,
    tunneled_stream_ref/0,
    invalid_open_options/0,
    stream_error_message/2,
    connection_error_message/1,
    down_message/1,
    nested_stream_error_message/2,
    nested_connection_error_message/1,
    malformed_stream_error_message/0,
    malformed_down_message/1,
    malformed_response_message/2,
    seed_message/1
]).

%% Consume the correlated DOWN before returning, so Gun deterministically
%% monitors a dead process and reports noproc. No process or monitor survives.
dead_connection() ->
    {Pid, Monitor} = spawn_monitor(fun() -> ok end),
    receive
        {'DOWN', Monitor, process, Pid, normal} -> Pid
    end.

tunneled_stream_ref() ->
    [make_ref(), make_ref()].

%% Duplicate protocols pass Gluegun's typed encoding but Gun rejects them
%% before creating a connection. Negative retry is rejected before Gun.
invalid_open_options() ->
    gluegun_ffi:open(<<"localhost">>, 80, [
        {transport_option, tcp},
        {protocols_option, [http1, http1]}
    ]).

stream_error_message(Connection, Stream) ->
    {gun_error, Connection, Stream, boom}.

connection_error_message(Connection) ->
    {gun_error, Connection, boom}.

down_message(Connection) ->
    {gun_down, Connection, http, boom, []}.

%% These category-like tuples belong to the reason and must not be stripped.
nested_stream_error_message(Connection, Stream) ->
    {gun_error, Connection, Stream, {stream_error, boom}}.

nested_connection_error_message(Connection) ->
    {gun_error, Connection, {connection_error, boom}}.

malformed_stream_error_message() ->
    {gun_error, <<"not-a-pid">>, <<"not-a-reference">>, boom}.

malformed_down_message(Connection) ->
    {gun_down, Connection, http, boom}.

malformed_response_message(Connection, Stream) ->
    {gun_response, Connection, Stream, invalid_fin, 200, []}.

seed_message(Message) ->
    self() ! Message,
    nil.
