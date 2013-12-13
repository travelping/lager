%% Copyright (c) 2011-2012 Basho Technologies, Inc.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.

%% @doc Journald backend for lager. Configured with a loglevel, formatter and formatter config.

-module(lager_journald_backend).

-behaviour(gen_event).

-export([init/1, handle_call/2, handle_event/2, handle_info/2, terminate/2,
        code_change/3]).

-record(state, {level, level_num, formatter, formatter_config}).

-include("lager.hrl").

-define(JOURNALD_FORMAT, [message]).

%% @private
init(Config) ->
    [Level, Formatter, FormatterConfig] = [proplists:get_value(K, Config, Def) || {K, Def} <- 
        [{level, info}, {formatter, lager_default_formatter}, {formatter_config, ?JOURNALD_FORMAT}]],
    State = #state{formatter=Formatter, formatter_config=FormatterConfig, level_num=lager_util:level_to_num(Level), level=level_to_num(Level)},
    {ok, State}.

%% @private
handle_call(get_loglevel, #state{level_num=Level} = State) ->
    {ok, Level, State};
handle_call({set_loglevel, Level}, State) ->
    try level_to_num(Level) of
        Levels ->
            {ok, ok, State#state{level_num=lager_util:level_to_num(Level), level=Levels}}
    catch
        _:_ ->
            {ok, {error, bad_log_level}, State}
    end;
handle_call(_Request, State) ->
    {ok, ok, State}.

%% @private
handle_event({log, Message}, #state{level_num=Num, level=L} = State) ->
    case lager_util:is_loggable(Message, Num, ?MODULE) of
        true ->
            ok = write(Message, L, State),
            {ok, State};
        false ->
            {ok, State}
    end;
handle_event(_Event, State) ->
    {ok, State}.

%% @private
handle_info(_Info, State) ->
    {ok, State}.

%% @private
terminate(_Reason, _State) ->
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% Internal functions

write(Msg, Level, #state{formatter=F, formatter_config=FConf}) ->
    Text0 = F:format(Msg, FConf) -- ["\n"],
    Metadata = lager_msg:metadata(Msg),
    CodeFile = proplists:get_value(module, Metadata),
    CodeLine = proplists:get_value(line, Metadata),
    CodeFunc = proplists:get_value(function, Metadata),
    Pid      = proplists:get_value(pid, Metadata),
    ok = journald_api:sendv([
        {"MESSAGE", Text0}, 
        {"PRIORITY", Level},
        {"CODE_FILE", CodeFile},
        {"CODE_FUNC", CodeFunc},
        {"CODE_LINE", CodeLine},
        {"SYSLOG_PID", Pid}
    ]).

level_to_num(debug) -> 7;
level_to_num(info) -> 6;
level_to_num(notice) -> 5;
level_to_num(warning) -> 4;
level_to_num(error) -> 3;
level_to_num(critical) -> 2;
level_to_num(alert) -> 1;
level_to_num(emergency) -> 0.
