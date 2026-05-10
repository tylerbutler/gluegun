-module(gluegun_ffi).

-export([
    open/3,
    await_up/2,
    close/1,
    shutdown/1,
    request/6,
    data/4,
    await/3,
    await_body/3,
    cancel/2,
    flush/1,
    safe_message_to_map/1
]).

open(Host, Port, Options) ->
    try gun:open(normalize_host(Host), Port, options_to_gun(Options)) of
        {ok, Pid} -> {ok, Pid};
        {error, Reason} -> {error, normalize_connection_error(Reason)}
    catch
        error:{options, Reason}:_Stack -> {error, {invalid_options, Reason}};
        error:{invalid_options, Reason}:_Stack -> {error, {invalid_options, Reason}};
        Class:Reason:_Stack -> {error, {erlang_error, {Class, Reason}}}
    end.

await_up(ConnPid, Timeout) ->
    try gun:await_up(ConnPid, timeout_to_gun(Timeout)) of
        {ok, Protocol} -> {ok, Protocol};
        {error, timeout} -> {error, timeout};
        {error, Reason} -> {error, normalize_connection_error(Reason)}
    catch
        Class:Reason:_Stack -> {error, {erlang_error, {Class, Reason}}}
    end.

close(ConnPid) ->
    try gun:close(ConnPid) of
        ok -> {ok, nil};
        Other -> {error, normalize_connection_error(Other)}
    catch
        Class:Reason:_Stack -> {error, {connection_error, {Class, Reason}}}
    end.

shutdown(ConnPid) ->
    try gun:shutdown(ConnPid) of
        ok -> {ok, nil};
        Other -> {error, normalize_connection_error(Other)}
    catch
        Class:Reason:_Stack -> {error, {connection_error, {Class, Reason}}}
    end.

request(ConnPid, Method, Path, Headers, Body, ReqOpts) ->
    try gun:request(
        ConnPid,
        to_binary(Method),
        to_binary(Path),
        normalize_headers(Headers),
        Body,
        req_opts_to_gun(ReqOpts)
    ) of
        StreamRef -> {ok, StreamRef}
    catch
        Class:Reason:_Stack -> {error, {erlang_error, {Class, Reason}}}
    end.

data(ConnPid, StreamRef, Fin, Data) ->
    try gun:data(ConnPid, StreamRef, fin_to_gun(Fin), Data) of
        ok -> {ok, nil};
        {error, Reason} -> {error, normalize_stream_error(Reason)};
        Other -> {error, normalize_stream_error(Other)}
    catch
        Class:Reason:_Stack -> {error, {stream_error, {Class, Reason}}}
    end.

await(ConnPid, StreamRef, Timeout) ->
    try gun:await(ConnPid, StreamRef, timeout_to_gun(Timeout)) of
        {error, timeout} -> {error, timeout};
        {error, Reason} -> {error, normalize_stream_error(Reason)};
        Message -> safe_message_to_map(Message)
    catch
        Class:Reason:_Stack -> {error, {erlang_error, {Class, Reason}}}
    end.

await_body(ConnPid, StreamRef, Timeout) ->
    try gun:await_body(ConnPid, StreamRef, timeout_to_gun(Timeout)) of
        {ok, Body} -> {ok, iolist_to_binary(Body)};
        {error, timeout} -> {error, timeout};
        {error, Reason} -> {error, normalize_stream_error(Reason)}
    catch
        Class:Reason:_Stack -> {error, {erlang_error, {Class, Reason}}}
    end.

cancel(ConnPid, StreamRef) ->
    try gun:cancel(ConnPid, StreamRef) of
        ok -> {ok, nil};
        {error, Reason} -> {error, normalize_stream_error(Reason)};
        Other -> {error, normalize_stream_error(Other)}
    catch
        Class:Reason:_Stack -> {error, {stream_error, {Class, Reason}}}
    end.

flush(ConnPid) ->
    try gun:flush(ConnPid) of
        ok -> {ok, nil};
        {error, Reason} -> {error, normalize_connection_error(Reason)};
        Other -> {error, normalize_connection_error(Other)}
    catch
        Class:Reason:_Stack -> {error, {connection_error, {Class, Reason}}}
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
    WithRetry = case maps:get(<<"retry">>, Options, undefined) of
        undefined -> WithProtocols;
        Retry -> WithProtocols#{retry => timeout_to_gun(Retry)}
    end,
    case maps:get(<<"connect_timeout">>, Options, undefined) of
        undefined -> WithRetry;
        Timeout -> WithRetry#{connect_timeout => timeout_to_gun(Timeout)}
    end;
options_to_gun(Options) ->
    error({invalid_options, Options}).

req_opts_to_gun(ReqOpts) when is_map(ReqOpts) -> ReqOpts;
req_opts_to_gun(_) -> #{}.

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
fin_to_gun(nofin) -> nofin;
fin_to_gun(<<"nofin">>) -> nofin;
fin_to_gun(Other) -> error({invalid_fin, Other}).

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
    DataBin = iolist_to_binary(Data),
    case unicode:characters_to_binary(DataBin, utf8, utf8) of
        ValidText when is_binary(ValidText) ->
            #{<<"type">> => <<"text">>, <<"data">> => ValidText};
        {error, _Encoded, _Rest} ->
            error({invalid_message, {ws, {text, invalid_utf8}}});
        {incomplete, _Encoded, _Rest} ->
            error({invalid_message, {ws, {text, invalid_utf8}}})
    end;
frame_to_map({binary, Data}) -> #{<<"type">> => <<"binary">>, <<"data">> => iolist_to_binary(Data)};
frame_to_map({close, Code, Reason}) -> #{<<"type">> => <<"close">>, <<"code">> => Code, <<"reason">> => to_binary(Reason)};
frame_to_map({ping, Data}) -> #{<<"type">> => <<"ping">>, <<"data">> => iolist_to_binary(Data)};
frame_to_map({pong, Data}) -> #{<<"type">> => <<"pong">>, <<"data">> => iolist_to_binary(Data)};
frame_to_map(close) -> #{<<"type">> => <<"close">>, <<"code">> => 1000, <<"reason">> => <<>>};
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
