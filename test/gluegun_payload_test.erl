-module(gluegun_payload_test).

-export([capture_request_body/0, capture_data_payload/0, has_payload_cast/0]).

capture_request_body() ->
    receive
        {'$gen_cast', {request, _ReplyTo, _StreamRef, _Method, _Path, _Headers, Body, _Flow}} ->
            {ok, Body}
    after 0 ->
        {error, {erlang_error, <<"no request message">>}}
    end.

capture_data_payload() ->
    receive
        {'$gen_cast', {data, _ReplyTo, _StreamRef, _Fin, Data}} ->
            {ok, Data}
    after 0 ->
        {error, {erlang_error, <<"no data message">>}}
    end.

has_payload_cast() ->
    receive
        {'$gen_cast', {request, _, _, _, _, _, _, _}} -> true;
        {'$gen_cast', {data, _, _, _, _}} -> true;
        {'$gen_cast', {ws_send, _, _, _}} -> true
    after 0 ->
        false
    end.
