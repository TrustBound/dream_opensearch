%% Helpers for the tests that run against a real OpenSearch.
-module(opensearch_cluster_ffi).
-export([environment_value/2, unique_suffix/0, halt/1]).

%% The value of the environment variable Name, or Default when it is not
%% set or empty.
environment_value(Name, Default) ->
    case os:getenv(binary_to_list(Name)) of
        false -> Default;
        "" -> Default;
        Value -> unicode:characters_to_binary(Value)
    end.

%% Digits that no other call returns, in this test run or in another run
%% that started at another microsecond.
unique_suffix() ->
    Time = erlang:system_time(microsecond),
    Count = erlang:unique_integer([positive, monotonic]),
    <<(integer_to_binary(Time))/binary, "_", (integer_to_binary(Count))/binary>>.

halt(Status) ->
    erlang:halt(Status).
