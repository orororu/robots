-module(tournament_ffi).
-export([parallel_map/2]).

%% Map F over List (argument order matches the Gleam declaration) in parallel;
%% results keep order. At most `workers()` items run at once, leaving a couple
%% of cores free so the machine stays responsive. Override with the
%% ROBOTS_WORKERS environment variable.
parallel_map(List, F) ->
    Items = lists:zip(lists:seq(1, length(List)), List),
    Results = run(Items, F, workers(), 0, #{}),
    [maps:get(I, Results) || I <- lists:seq(1, length(List))].

workers() ->
    case os:getenv("ROBOTS_WORKERS") of
        false -> max(1, erlang:system_info(schedulers_online) - 2);
        Text -> max(1, list_to_integer(Text))
    end.

run([], _F, _Free, 0, Acc) ->
    Acc;
run([{I, X} | Rest], F, Free, Busy, Acc) when Free > 0 ->
    Parent = self(),
    spawn_link(fun() -> Parent ! {pmap_done, I, F(X)} end),
    run(Rest, F, Free - 1, Busy + 1, Acc);
run(Items, F, Free, Busy, Acc) ->
    receive
        {pmap_done, I, Result} ->
            run(Items, F, Free + 1, Busy - 1, maps:put(I, Result, Acc))
    end.
