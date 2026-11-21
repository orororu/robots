-module(tournament_ffi).
-export([parallel_map/2]).

%% Map F over List (argument order matches the Gleam declaration) using one Erlang process per element; results keep order.
parallel_map(List, F) ->
    Parent = self(),
    Refs = [begin
                Ref = make_ref(),
                spawn_link(fun() -> Parent ! {Ref, F(X)} end),
                Ref
            end || X <- List],
    [receive {Ref, Result} -> Result end || Ref <- Refs].
