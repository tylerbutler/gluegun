-module(actor_peer).

-export([with_server/2, assert_owner/1, release_disconnect/0, kill_connection/1]).

%% String, (Int -> Result(Nil, GluegunError)) -> Result(Nil, GluegunError).
%% This process is only a loopback wire peer, never a Gun-message forwarder.
%% The callback owns the actor; the fixture owns the listener and peer monitor.
with_server(Name, Callback)
        when Name =:= <<"normal">>; Name =:= <<"flow_coalesced">>;
             Name =:= <<"drop">>; Name =:= <<"kill">> ->
    case gen_tcp:listen(0, [binary, {active, false}, {ip, {127, 0, 0, 1}},
            {reuseaddr, true}]) of
        {error, Reason} -> fixture_error({listen, Reason});
        {ok, Listener} ->
            try
                {ok, {_, Port}} = inet:sockname(Listener),
                Token = make_ref(),
                {Peer, Monitor} = spawn_monitor(fun() -> serve(Listener, Name, Token) end),
                Key = {?MODULE, disconnect_peer},
                Previous = put(Key, {Peer, Token}),
                try
                    case Callback(Port) of
                        {ok, nil} -> await_peer(Peer, Monitor);
                        {error, _} = Error -> Error
                    end
                after
                    try stop_peer(Peer, Monitor)
                    after
                        case Previous of
                            undefined -> erase(Key);
                            _ -> put(Key, Previous)
                        end
                    end
                end
            after
                gen_tcp:close(Listener)
            end
    end;
with_server(Name, _) ->
    {error, {invalid_options, <<"Unknown actor peer mode: ", Name/binary>>}}.

%% () -> Nil. Called by the test after installing its actor monitor.
release_disconnect() ->
    {Peer, Token} = get({?MODULE, disconnect_peer}),
    Peer ! {actor_peer_drop, Token},
    nil.

%% Pid -> Result(Nil, GluegunError). Inspect Gun's public info API rather than
%% guessing from actor mailboxes or treating the parent test as the owner.
%% gun:info uses OTP's bounded sys:get_state call. Connections that disappear
%% during inspection are ignored; unexpected process failures still propagate.
assert_owner(Actor) when is_pid(Actor) ->
    case owned_connection(Actor) of
        {ok, _} -> {ok, nil};
        {error, _} = Error -> Error
    end.

%% Pid -> Result(Nil, GluegunError). Kill only the unique Gun process owned
%% by this actor, and consume only this helper's exact connection monitor.
kill_connection(Actor) when is_pid(Actor) ->
    case owned_connection(Actor) of
        {error, _} = Error -> Error;
        {ok, Connection} ->
            Monitor = erlang:monitor(process, Connection),
            try
                exit(Connection, kill),
                receive
                    {'DOWN', Monitor, process, Connection, _} -> {ok, nil}
                after 1000 ->
                    fixture_error(connection_kill_timeout)
                end
            after
                erlang:demonitor(Monitor, [flush])
            end
    end.

owned_connection(Actor) ->
    case whereis(gun_conns_sup) of
        undefined -> fixture_error(gun_not_started);
        _ ->
            Owned = [Pid || {_, Pid, _, _} <- supervisor:which_children(gun_conns_sup),
                is_pid(Pid), owned_by(Pid, Actor)],
            case Owned of
                [Connection] -> {ok, Connection};
                _ -> fixture_error({expected_one_actor_owned_connection, length(Owned)})
            end
    end.

owned_by(Pid, Actor) ->
    try maps:get(owner, gun:info(Pid)) =:= Actor
    catch
        exit:{noproc, _} -> false;
        exit:{normal, _} -> false
    end.

await_peer(Peer, Monitor) ->
    receive
        {'DOWN', Monitor, process, Peer, normal} -> {ok, nil};
        {'DOWN', Monitor, process, Peer, Reason} -> fixture_error({peer_failed, Reason})
    after 8000 ->
        fixture_error(peer_not_released)
    end.

stop_peer(Peer, Monitor) ->
    %% Specific unlinked fixture process only; demonitor flushes its own DOWN.
    try
        case is_process_alive(Peer) of
            true ->
                exit(Peer, kill),
                receive
                    {'DOWN', Monitor, process, Peer, _} -> ok
                after 1000 ->
                    error(peer_cleanup_timeout)
                end;
            false -> ok
        end
    after
        erlang:demonitor(Monitor, [flush])
    end.

serve(Listener, Name, Token) ->
    {ok, Socket} = gen_tcp:accept(Listener, 5000),
    Deadline = erlang:monotonic_time(millisecond) + 7000,
    try
        Headers = headers(Socket, <<>>, Deadline),
        [KeyLine] = [Line || Line <- binary:split(Headers, <<"\r\n">>, [global]),
            string:prefix(string:lowercase(Line), <<"sec-websocket-key:">>) =/= nomatch],
        [_, Key] = binary:split(KeyLine, <<":">>),
        Accept = cow_ws:encode_key(string:trim(Key)),
        ok = gen_tcp:send(Socket, [
            <<"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n",
                "Connection: Upgrade\r\nSec-WebSocket-Accept: ">>,
            Accept, <<"\r\n\r\n">>]),
        case Name of
            <<"drop">> ->
                receive
                    {actor_peer_drop, Token} -> ok
                after max(0, Deadline - erlang:monotonic_time(millisecond)) ->
                    error(disconnect_not_released)
                end;
            <<"flow_coalesced">> ->
                ok = gen_tcp:send(Socket, [
                    <<129, 3, "one">>, <<129, 3, "two">>, <<129, 5, "three">>]),
                exchange(Socket, Name, Deadline);
            _ -> exchange(Socket, Name, Deadline)
        end
    after
        gen_tcp:close(Socket)
    end.

headers(Socket, Acc, Deadline) when byte_size(Acc) < 16384 ->
    case binary:match(Acc, <<"\r\n\r\n">>) of
        nomatch ->
            {ok, Data} = recv(Socket, 0, Deadline),
            headers(Socket, <<Acc/binary, Data/binary>>, Deadline);
        _ -> Acc
    end.

exchange(Socket, Name, Deadline) ->
    case read_frame(Socket, Deadline) of
        {1, Data} ->
            ok = send_frame(Socket, 1, Data),
            exchange(Socket, Name, Deadline);
        {9, Data} ->
            ok = send_frame(Socket, 10, Data),
            exchange(Socket, Name, Deadline);
        {10, _} -> exchange(Socket, Name, Deadline);
        {8, _} ->
            ok = send_frame(Socket, 8, <<1000:16, "bye">>),
            await_closed(Socket, Deadline);
        {error, closed} when Name =:= <<"kill">> -> ok;
        Other -> error({unexpected_client_frame, Other})
    end.

read_frame(Socket, Deadline) ->
    %% Test clients send complete masked frames; payloads are bounded to 4KB.
    case recv(Socket, 2, Deadline) of
        {error, closed} -> {error, closed};
        {error, econnreset} -> {error, closed};
        {ok, <<1:1, 0:3, Opcode:4, 1:1, ShortLength:7>>} ->
            read_frame_payload(Socket, Opcode, ShortLength, Deadline);
        Other -> error({invalid_client_frame, Other})
    end.

read_frame_payload(Socket, Opcode, ShortLength, Deadline) ->
    Length = case ShortLength of
        126 ->
            {ok, <<Extended:16>>} = recv(Socket, 2, Deadline),
            Extended;
        N when N < 126 -> N
    end,
    true = Length =< 4096,
    {ok, Mask} = recv(Socket, 4, Deadline),
    Data = case Length of
        0 -> <<>>;
        _ ->
            {ok, Payload} = recv(Socket, Length, Deadline),
            Payload
    end,
    {Opcode, unmask(Data, Mask, 0, [])}.

unmask(<<>>, _, _, Acc) -> list_to_binary(lists:reverse(Acc));
unmask(<<Byte, Rest/binary>>, Mask, Index, Acc) ->
    Key = binary:at(Mask, Index rem 4),
    unmask(Rest, Mask, Index + 1, [(Byte bxor Key) | Acc]).

send_frame(Socket, Opcode, Data) when byte_size(Data) < 126 ->
    gen_tcp:send(Socket, <<1:1, 0:3, Opcode:4, 0:1, (byte_size(Data)):7, Data/binary>>);
send_frame(Socket, Opcode, Data) ->
    gen_tcp:send(Socket, <<1:1, 0:3, Opcode:4, 0:1, 126:7,
        (byte_size(Data)):16, Data/binary>>).

await_closed(Socket, Deadline) ->
    case recv(Socket, 0, Deadline) of
        {error, closed} -> ok;
        {ok, _} -> await_closed(Socket, Deadline);
        Other -> error({client_socket_not_released, Other})
    end.

recv(Socket, Length, Deadline) ->
    Remaining = Deadline - erlang:monotonic_time(millisecond),
    gen_tcp:recv(Socket, Length, max(0, Remaining)).

fixture_error(Reason) ->
    {error, {erlang_error, gleam@string:inspect(Reason)}}.
