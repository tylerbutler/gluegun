-module(gluegun_socket_receive_control_test).
-export([capture_update_flow/0, no_flow_cast/0]).

%% Capture the typed payload dispatched by websocket.update_flow.
capture_update_flow() ->
    receive
        {'$gen_cast', {update_flow, ReplyTo, Stream, Increment}}
            when is_pid(ReplyTo), is_reference(Stream), is_integer(Increment) ->
            {ok, {ReplyTo, Stream, Increment}}
    after 0 ->
        {error, nil}
    end.

%% Detect and drain only flow updates, leaving unrelated messages untouched.
no_flow_cast() -> drain_flow_casts(true).

drain_flow_casts(Clean) ->
    receive
        {'$gen_cast', {update_flow, _, _, _}} ->
            drain_flow_casts(false)
    after 0 ->
        Clean
    end.
