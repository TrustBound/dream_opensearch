%% Helpers for the output files of the guides.
-module(guide_output_ffi).
-export([read_file/1, without_keys/2]).

%% The bytes of the file at Path as a string, or an error.
read_file(Path) ->
    case file:read_file(Path) of
        {ok, Bytes} -> {ok, Bytes};
        {error, _Reason} -> {error, nil}
    end.

%% Term with every map key in Keys removed, at every depth.
without_keys(Term, Keys) when is_map(Term) ->
    maps:map(fun(_Key, Value) -> without_keys(Value, Keys) end,
             maps:without(Keys, Term));
without_keys(Term, Keys) when is_list(Term) ->
    [without_keys(Element, Keys) || Element <- Term];
without_keys(Term, _Keys) ->
    Term.
