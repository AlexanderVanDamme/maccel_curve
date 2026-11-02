-module(maccel_curve_ffi).
-export([port_in_use/1, read_speed/1]).

%% True when nothing can listen on 127.0.0.1:Port right now.
port_in_use(Port) ->
    case gen_tcp:listen(Port, [{ip, {127, 0, 0, 1}}, {reuseaddr, true}]) of
        {ok, Socket} ->
            gen_tcp:close(Socket),
            false;
        {error, _} ->
            true
    end.

%% The driver echoes the last input speed as one big-endian fixed-point
%% integer (32.32 on 64-bit kernels) on every read of /dev/maccel.
read_speed(Path) ->
    case file:open(Path, [read, binary, raw]) of
        {ok, Fd} ->
            Result = case file:read(Fd, 8) of
                {ok, <<Value:64/signed-big>>} -> {ok, Value};
                {ok, <<Value:32/signed-big>>} -> {ok, Value};
                {ok, _} -> {error, <<"short read">>};
                eof -> {error, <<"eof">>};
                {error, Reason} -> {error, list_to_binary(io_lib:format("~p", [Reason]))}
            end,
            file:close(Fd),
            Result;
        {error, Reason} ->
            {error, list_to_binary(io_lib:format("~p", [Reason]))}
    end.
