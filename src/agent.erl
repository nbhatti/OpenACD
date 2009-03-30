%%	The contents of this file are subject to the Common Public Attribution
%%	License Version 1.0 (the “License”); you may not use this file except
%%	in compliance with the License. You may obtain a copy of the License at
%%	http://opensource.org/licenses/cpal_1.0. The License is based on the
%%	Mozilla Public License Version 1.1 but Sections 14 and 15 have been
%%	added to cover use of software over a computer network and provide for
%%	limited attribution for the Original Developer. In addition, Exhibit A
%%	has been modified to be consistent with Exhibit B.
%%
%%	Software distributed under the License is distributed on an “AS IS”
%%	basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
%%	License for the specific language governing rights and limitations
%%	under the License.
%%
%%	The Original Code is Spice Telephony.
%%
%%	The Initial Developers of the Original Code is 
%%	Andrew Thompson and Micah Warren.
%%
%%	All portions of the code written by the Initial Developers are Copyright
%%	(c) 2008-2009 SpiceCSM.
%%	All Rights Reserved.
%%
%%	Contributor(s):
%%
%%	Andrew Thompson <athompson at spicecsm dot com>
%%	Micah Warren <mwarren at spicecsm dot com>
%%

%% @doc A gen_fsm representing the agent's state.
-module(agent).
-behaviour(gen_fsm).

-ifdef(EUNIT).
-include_lib("eunit/include/eunit.hrl").
-endif.

-include("call.hrl").
-include("agent.hrl").

%% gen_fsm exports
-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3, terminate/3, code_change/4]).
%% defined state exports
-export([idle/3, ringing/3, precall/3, oncall/3, outgoing/3, released/3, warmtransfer/3, wrapup/3]).

%% other exports
-export([start/1, start_link/1, stop/1, query_state/1, dump_state/1, set_state/2, set_state/3, list_to_state/1, integer_to_state/1, state_to_integer/1, set_connection/2, set_remote_number/2]).

%% @doc Start an agent fsm for the passed in agent record `Agent' that is linked to the calling process
-spec(start_link/1 :: (Agent :: #agent{}) -> {'ok', pid()}).
start_link(Agent = #agent{}) -> 
	gen_fsm:start_link(?MODULE, [Agent], []).

%% @doc Start an agent fsm for the passed in agent record `Agent'.
-spec(start/1 :: (Agent :: #agent{}) -> {'ok', pid()}).
start(Agent = #agent{}) -> 
	gen_fsm:start(?MODULE, [Agent], []).

%% @doc Stop the passed agent fsm `Pid'.
-spec(stop/1 :: (Pid :: pid()) -> 'ok').
stop(Pid) -> 
	gen_fsm:send_all_state_event(Pid, stop).
	
%% @doc link the given agent  `Pid' to the given connection `Socket'.
-spec(set_connection/2 :: (Pid :: pid(), Socket :: pid()) -> 'ok' | 'error').
set_connection(Pid, Socket) ->
	gen_fsm:sync_send_all_state_event(Pid, {set_connection, Socket}).

set_remote_number(Pid, Number) ->
	gen_fsm:sync_send_all_state_event(Pid, {set_remote_number, Number}).

%% @private
init([State = #agent{}]) ->
	State2 = expand_magic_skills(State),
	{ok, released, State2}.

% actual functions we'll call
%% @private
-spec(expand_magic_skills/1 :: (State :: #agent{}) -> #agent{}).
expand_magic_skills(State) ->
	State#agent{skills = lists:map(
		fun('_agent') -> list_to_atom(State#agent.login);
		('_node') -> node();
		(Skill) -> Skill
	end, State#agent.skills)}.

%% @doc Returns the entire agent record for the agent at `Pid'.
-spec(dump_state/1 :: (Pid :: pid()) -> #agent{}).
dump_state(Pid) ->
	gen_fsm:sync_send_all_state_event(Pid, dump_state).

%% @doc Returns `{ok, Statename :: atom()}', where `Statename' is the current state of the agent at `Pid'.
-spec(query_state/1 :: (Pid :: pid()) -> {'ok', atom()}).
query_state(Pid) -> 
	gen_fsm:sync_send_all_state_event(Pid, query_state).

%% @doc Attempt to set the state of agent at `Pid' to `State'.
-spec(set_state/2 :: (Pid :: pid(), State :: atom()) -> 'ok' | 'invalid').
set_state(Pid, State) ->
	gen_fsm:sync_send_event(Pid, State).

%% @doc Attempt to set the state of the agent at `Pid' to `State' with data `Data'.  `Data' is related to the `State' the agent is going into.  
%% Often `Data' will be `#call{} or a callid of type `string()'.
-spec(set_state/3 :: (Pid :: pid(), State :: 'idle' | 'ringing' | 'precall' | 'oncall' | 'outgoing' | 'warmtransfer' | 'wrapup', Data :: any()) -> 'ok' | 'invalid';
                     (Pid :: pid(), State :: 'released', Data :: any()) -> 'ok' | 'invalid' | 'queued').
set_state(Pid, State, Data) ->
	gen_fsm:sync_send_event(Pid, {State, Data}).

%% @doc Translate the state `String' into the internally used atom.  `String' can either be the human readable string or a number in string form (`"1"').
-spec(list_to_state/1 :: (String :: string()) -> atom()).
list_to_state(String) ->
	try list_to_integer(String) of
		Int -> integer_to_state(Int)
	catch
		_:_ ->
			case string:to_lower(String) of
				"idle" -> idle;
				"ringing" -> ringing;
				"precall" -> precall;
				"oncall" -> oncall;
				"outgoing" -> outgoing;
				"released" -> released;
				"warmtransfer" -> warmtransfer;
				"wrapup" -> wrapup
			end
	end.

%% @doc Translate the integer `Int' to the corresponding internally used atom.
-spec(integer_to_state/1 :: (Int :: 2) -> 'idle';
                            (Int :: 3) -> 'ringing';
                            (Int :: 4) -> 'precall';
                            (Int :: 5) -> 'oncall';
                            (Int :: 6) -> 'outgoing';
                            (Int :: 7) -> 'released';
                            (Int :: 8) -> 'warmtransfer';
                            (Int :: 9) -> 'wrapup').
integer_to_state(Int) ->
	case Int of
		2 -> idle;
		3 -> ringing;
		4 -> precall;
		5 -> oncall;
		6 -> outgoing;
		7 -> released;
		8 -> warmtransfer;
		9 -> wrapup
	end.

%% @doc Translate the interally used atom `State' to the integer equivalent.
-spec(state_to_integer/1 :: (State :: 'idle') -> 2;
                            (State :: 'ringing') -> 3;
                            (State :: 'precall') -> 4;
                            (State :: 'oncall') -> 5;
                            (State :: 'outgoing') -> 6;
                            (State :: 'released') -> 7;
                            (State :: 'warmtransfer') -> 8;
                            (State :: 'wrapup') -> 9).
state_to_integer(State) ->
	case State of
		idle -> 2;
		ringing -> 3;
		precall -> 4;
		oncall -> 5;
		outgoing -> 6;
		released -> 7;
		warmtransfer -> 8;
		wrapup -> 9
	end.

%% @doc The various state changes available when an agent is idle. <ul>
%%<li>`{precall, Client :: #client{}}'</li>
%%<li>`{ringing, Call :: #call{}}'</li>
%%<li>`{released, Reason :: string()}'</li>
%%</ul>
idle({precall, Client}, _From, State) ->
	gen_server:cast(dispatch_manager, {end_avail, self()}),
	gen_server:cast(State#agent.connection, {change_state, precall, Client}),
	{reply, ok, precall, State#agent{state=precall, statedata=Client, lastchangetimestamp=now()}};
idle({ringing, Call = #call{}}, _From, State) ->
	gen_server:cast(dispatch_manager, {end_avail, self()}),
	gen_server:cast(State#agent.connection, {change_state, ringing, Call}),
	{reply, ok, ringing, State#agent{state=ringing, statedata=Call, lastchangetimestamp=now()}};
idle({released, Reason}, _From, State) ->
	gen_server:cast(dispatch_manager, {end_avail, self()}),
	gen_server:cast(State#agent.connection, {change_state, released, Reason}), % it's up to the connection to determine if this is worth listening to
	{reply, ok, released, State#agent{state=released, statedata=Reason, lastchangetimestamp=now()}};
idle(Event, From, State) ->
	?CONSOLE("Invalid event '~p' sent from ~p while in state 'idle'", [Event, From]),
	{reply, invalid, idle, State}.

%% @doc The various state changes available when an agent is ringing. <ul>
%%<li>`oncall'<br />When default ring path is `inband' and the call's ring path is not outband.</li>
%%<li>`{oncall, Call :: #call{}}'</li>
%%<li>`{released, Reason :: string()}'</li>
%%<li>`idle'</li>
%%</ul>
ringing(oncall, _From, #agent{statedata = Statecall} = State) when State#agent.defaultringpath =:= inband, Statecall#call.ring_path =/= outband ->
	?CONSOLE("default ringpath inband, ring_path not outband", []),
	gen_server:cast(State#agent.connection, {change_state, oncall, State#agent.statedata}),
	gen_server:cast(Statecall#call.cook, remove_from_queue),
	{reply, ok, oncall, State#agent{state=oncall, lastchangetimestamp=now()}};
ringing({oncall, #call{id=Callid} = Call}, _From, #agent{statedata = Statecall} = State) ->
	case Statecall#call.id of
		Callid -> 
			gen_server:cast(State#agent.connection, {change_state, oncall, Call}),
			{reply, ok, oncall, State#agent{state=oncall, statedata=Call, lastchangetimestamp=now()}};
		_Other -> 
			{reply, invalid, ringing, State}
	end;
ringing({released, Reason}, _From, #agent{statedata = Call} = State) ->
	?CONSOLE("going released from ringing", []),
	gen_server:cast(Call#call.cook, {stop_ringing_keep_state, self()}),
	gen_server:cast(State#agent.connection, {change_state, released, Reason}), % it's up to the connection to determine if this is worth listening to
	{reply, ok, released, State#agent{state=released, statedata=Reason, lastchangetimestamp=now()}};
ringing(idle, _From, State) ->
	gen_server:cast(dispatch_manager, {now_avail, self()}),
	gen_server:cast(State#agent.connection, {change_state, idle}),
	{reply, ok, idle, State#agent{state=idle, statedata={}, lastchangetimestamp=now()}};
ringing(_Event, _From, State) ->
	{reply, invalid, ringing, State}.

%% @doc The various state changes available when an agent is in precall. <ul>
%%<li>`{outgoing, Call :: #call{}'}</li>
%%<li>`idle'</li>
%%<li>`{released, Reason}'</li>
%%</ul>
precall({outgoing, Call}, _From, State) ->
	gen_server:cast(State#agent.connection, {change_state, outgoing, Call}),
	{reply, ok, outgoing, State#agent{state=outgoing, statedata=Call, lastchangetimestamp=now()}};
precall(idle, _From, State) ->
	gen_server:cast(dispatch_manager, {now_avail, self()}),
	gen_server:cast(State#agent.connection, {change_state, idle}),
	{reply, ok, idle, State#agent{state=idle, statedata={}, lastchangetimestamp=now()}};
precall({released, Reason}, _From, State) ->
	gen_server:cast(State#agent.connection, {change_state, released, Reason}),
	{reply, ok, released, State#agent{state=released, statedata=Reason, lastchangetimestamp=now()}};
precall(_Event, _From, State) -> 
	{reply, invalid, precall, State}.

%% @doc The various state changes available when an agent is oncall. <ul>
%%<li>`{released, undefined}'<br />Note this 'un-queues' a released state when the call is done.</li>
%%<li>`{released, Reason :: string()}'<br />This only queues a release, it doesn't actually change state</li>
%%<li>`wrapup'<br />When the media path of the call is `inband'</li>
%%<li>`{wrapup, Call :: #call}'<br />When the media path is `outband'</li>
%%<li>`{warmtransfer, Transferto :: any()}'</li>
%%</ul>
oncall({released, undefined}, _From, State) -> 
	{reply, ok, oncall, State#agent{queuedrelease=undefined}};
oncall({released, Reason}, _From, State) -> 
	{reply, queued, oncall, State#agent{queuedrelease=Reason}};
oncall(wrapup, _From, #agent{statedata = Call} = State) when Call#call.media_path =:= 'inband' ->
	gen_server:cast(State#agent.connection, {change_state, wrapup, Call}),
	{reply, ok, wrapup, State#agent{state=wrapup, lastchangetimestamp=now()}};
oncall({wrapup, #call{id = Callid} = Call}, _From, #agent{statedata = Currentcall} = State) ->
	case Currentcall#call.id of
		Callid -> 
			gen_server:cast(State#agent.connection, {change_state, wrapup, Call}),
			{reply, ok, wrapup, State#agent{state=wrapup, statedata=Call, lastchangetimestamp=now()}};
		_Else ->
			{reply, invalid, oncall, State}
	end;
oncall({warmtransfer, Transferto}, _From, State) ->
	gen_server:cast(State#agent.connection, {change_state, warmtransfer, Transferto}),
	{reply, ok, warmtransfer, State#agent{state=warmtransfer, statedata={onhold, State#agent.statedata, calling, Transferto}, lastchangetimestamp=now()}};
oncall(_Event, _From, State) -> 
	{reply, invalid, oncall, State}.
	
%% @doc The various state changes available when an agent is in an outgoing call. <ul>
%%<li>`{released, undefined}'<br />Note this only unsets a previously queued release.</li>
%%<li>`{released, Reason :: string()}'<br />Note this only queues a release for when the call is over.</li>
%%<li>`{wrapup, Call :: #call{}}'</li>
%%<li>`{warmtransfer, Transferto :: any()}'</li>
%%</ul>
outgoing({released, undefined}, _From, State) -> 
	{reply, ok, outgoing, State#agent{queuedrelease=undefined}};
outgoing({released, Reason}, _From, State) -> 
	{reply, queued, outgoing, State#agent{queuedrelease=Reason}};
outgoing({wrapup, #call{id = Callid} = Call}, _From, #agent{statedata = Currentcall} = State) ->
	case Currentcall#call.id of
		Callid -> 
			gen_server:cast(State#agent.connection, {change_state, wrapup, Call}),
			{reply, ok, wrapup, State#agent{state=wrapup, statedata=Call, lastchangetimestamp=now()}};
		_Else -> 
			{reply, invalid, outgoing, State}
	end;
outgoing({warmtransfer, Transferto}, _From, State) -> 
	gen_server:cast(State#agent.connection, {change_state, warmtransfer, Transferto}),
	{reply, ok, warmtransfer, State#agent{state=warmtransfer, statedata={onhold, State#agent.statedata, calling, Transferto}, lastchangetimestamp=now()}};
outgoing(_Event, _From, State) -> 
	{reply, invalid, outgoing, State}.

%% @doc The various state changes available when an agent is released. <ul>
%%<li>`{precall, Client :: #client{}}'</li>
%%<li>`idle'</li>
%%<li>`{released, Reason :: string()}'<br />Changes the released reason.</li>
%%<li>`{ringing, Call :: #call{}}'<br />While the system cannot automatically route to a released agent,
%%there is functionality for a supervisor to force it through.</li>
%%</ul>
released({precall, Client}, _From, State) ->
	gen_server:cast(State#agent.connection, {change_state, precall, Client}),
	{reply, ok, precall, State#agent{state=precall, statedata=Client, lastchangetimestamp=now()}};
released(idle, _From, State) ->	
	gen_server:cast(dispatch_manager, {now_avail, self()}),
	gen_server:cast(State#agent.connection, {change_state, idle}),
	{reply, ok, idle, State#agent{state=idle, statedata={}, lastchangetimestamp=now()}};
released({released, Reason}, _From, State) ->
	gen_server:cast(State#agent.connection, {change_state, released, Reason}),
	{reply, ok, released, State#agent{statedata=Reason, lastchangetimestamp=now()}};
released({ringing, Call}, _From, State) ->
	gen_server:cast(State#agent.connection, {change_state, ringing, Call}),
	{reply, ok, ringing, State#agent{state=ringing, statedata=Call, lastchangetimestamp=now()}};
released(_Event, _From, State) ->
	{reply, invalid, released, State}.

%% @doc The various calls available when an agent is warmtransfering. <ul>
%%<li>`{released, undefined}'<br />Unqueues a preveiouosly set release request.</li>
%%<li>`{released, Reason :: string()}'<br />Queues a reason after the call is done.</li>
%%<li>`{wrapup, Call :: #call{}}'</li>
%%<li>`{oncall, Call :: #call{}}'<br />If the agent goes back to the orignal call</li>
%%<li>`{outgoing, Call :: #call{}}'</li>
%%</ul>
warmtransfer({released, undefined}, _From, State) ->
	{reply, ok, warmtransfer, State#agent{queuedrelease=undefined}};
warmtransfer({released, Reason}, _From, State) -> 
	{reply, queued, warmtransfer, State#agent{queuedrelease=Reason}};	
warmtransfer({wrapup, #call{id = Callid} = Call}, _From, #agent{statedata = {onhold, Onhold, calling, _Calling}} = State) -> 
	case Onhold#call.id of
		 Callid -> 
			gen_server:cast(State#agent.connection, {change_state, wrapup, Call}),
			{reply, ok, wrapup, State#agent{state=wrapup,statedata=Call, lastchangetimestamp=now()}};
		_Else -> 
			{reply, invalid, warmtransfer, State}
	end;
warmtransfer({oncall, #call{id = Callid} = Call}, _From, #agent{statedata = {onhold, Onhold, calling, _Calling}} = State) -> 
	case Onhold#call.id of
		 Callid -> 
			gen_server:cast(State#agent.connection, {change_state, oncall, Call}),
			{reply, ok, oncall, State#agent{state=oncall, statedata=Call, lastchangetimestamp=now()}};
		_Else -> 
			{reply, invalid, warmtransfer, State}
	end;
warmtransfer({outgoing, Call}, _From, State) ->
	gen_server:cast(State#agent.connection, {change_state, outgoing, Call}),
	{reply, ok, outgoing, State#agent{state=outgoing, statedata=Call, lastchangetimestamp=now()}};
warmtransfer(_Event, _From, State) ->
	{reply, invalid, warmtransfer, State}.

%% @doc The various state changes available when either the agent or remote has hung-up. <ul>
%%<li>`{released, undefined}'<br />Unqueues a release.</li>
%%<li>`{released, Reason :: string()}'<br />Queues a release the next time the agent tries to go `idle'.</li>
%%<li>`idle'<br />If the agent has a release queued, that state is set instead.</li>
%%</ul>
wrapup({released, undefined}, _From, State) ->
	{reply, ok, wrapup, State#agent{queuedrelease=undefined}};
wrapup({released, Reason}, _From, State) ->
	{reply, queued, wrapup, State#agent{queuedrelease=Reason}};
wrapup(idle, _From, State= #agent{queuedrelease = undefined}) ->
	gen_server:cast(dispatch_manager, {now_avail, self()}),
	gen_server:cast(State#agent.connection, {change_state, idle}),
	{reply, ok, idle, State#agent{state=idle, statedata={}, lastchangetimestamp=now()}};
wrapup(idle, _From, State) ->
	gen_server:cast(State#agent.connection, {change_state, released, State#agent.queuedrelease}),
	{reply, ok, released, State#agent{state=released, statedata=State#agent.queuedrelease, queuedrelease=undefined, lastchangetimestamp=now()}};
wrapup(Event, From, State) ->
	?CONSOLE("Invalid event '~p' from ~p while in wrapup.", [Event, From]),
	{reply, invalid, wrapup, State}.


% generic handlers independant of state
%% @private
handle_event(stop, _StateName, State) -> 
	{stop, normal, State};
handle_event(_Event, StateName, State) ->
	{next_state, StateName, State}.

%% @private
handle_sync_event(query_state, _From, StateName, State) -> 
	{reply, {ok, StateName}, StateName, State};
handle_sync_event(dump_state, _From, StateName, State) ->
	{reply, State, StateName, State};
handle_sync_event({set_connection, Pid}, _From, StateName, #agent{connection = undefined} = State) ->
	link(Pid),
	gen_server:cast(Pid, {change_state, State#agent.state, State#agent.statedata}),
	{reply, ok, StateName, State#agent{connection=Pid}};
handle_sync_event({set_connection, _Pid}, _From, StateName, State) ->
	{reply, error, StateName, State};
handle_sync_event({set_remote_number, Number}, _From, StateName, State) ->
	{reply, ok, StateName, State#agent{remotenumber = Number}};
handle_sync_event(_Event, _From, StateName, State) ->
	{reply, ok, StateName, State}.

%% @private
handle_info(_Info, StateName, State) ->
	{next_state, StateName, State}.

% obviousness below.
%% @private
terminate(Reason, StateName, _State) ->
	?CONSOLE("Agent terminating:  ~p, State:  ~p", [Reason, StateName]),
	ok.

%% @private
code_change(_OldVsn, StateName, State, _Extra) ->
	{ok, StateName, State}.

-ifdef(EUNIT).
state_change_test() ->
	{_, Pid} = start(#agent{login="testagent"}),
	?assertMatch({ok, released}, query_state(Pid)),
	?assertEqual(ok, set_state(Pid, idle)),
	?assertMatch({ok, idle}, query_state(Pid)),
	?assertEqual(invalid, set_state(Pid, oncall)),
	?assertMatch({ok, idle}, query_state(Pid)),
	?assertEqual(ok, set_state(Pid, ringing, #call{id="foo", source=self()})),
	?assertMatch({ok, ringing}, query_state(Pid)),
	?assertEqual(ok, set_state(Pid, oncall, #call{id="foo", source=self()})),
	?assertMatch({ok, oncall}, query_state(Pid)),
	?assertMatch(queued, set_state(Pid, released, {1, 0})).
	
ring_oncall_mismatch_test() ->
	{_, Pid} = start(#agent{login="testagent"}),
	Goodcall = #call{id="Goodcall", source=self()},
	Badcall = #call{id="Badcall", source=self()},
	?assertMatch(ok, set_state(Pid, idle)),
	?assertMatch(ok, set_state(Pid, ringing, Goodcall)),
	?assertMatch(invalid, set_state(Pid, oncall, Badcall)).

idle_state_test() -> 
	{_, Pid} = start(#agent{login="testagent"}),
	?assertMatch(ok, set_state(Pid, idle)),
	Call = #call{id="testcall", source=self()},
	?assertMatch(invalid, set_state(Pid, ringing, nothing)),
	?assertMatch(invalid, set_state(Pid, oncall, nothing)),
	?assertMatch(invalid, set_state(Pid, outgoing, nothing)),
	?assertMatch(invalid, set_state(Pid, warmtransfer, nothing)),
	?assertMatch(invalid, set_state(Pid, wrapup, nothing)),
	?assertMatch(ok, set_state(Pid, ringing, Call)),
	?assertMatch({ok, ringing}, query_state(Pid)),
	?assertMatch(ok, set_state(Pid, idle)),
	?assertMatch({ok, idle}, query_state(Pid)),
	?assertMatch(ok, set_state(Pid, released, default)),
	?assertMatch({ok, released}, query_state(Pid)),
	?assertMatch(ok, set_state(Pid, idle)),
	?assertMatch({ok, idle}, query_state(Pid)).
	
ringing_state_test() -> 
	{_, Pid} = start(#agent{login="testagent"}),
	?assertMatch(ok, set_state(Pid, idle)),
	Call = #call{id="testcall", source=self()},
	?assertMatch(ok, set_state(Pid, ringing, Call)),
	?assertMatch(invalid, set_state(Pid, ringing)),
	?assertMatch(invalid, set_state(Pid, ringing, Call)),
	?assertMatch(invalid, set_state(Pid, precall)),
	?assertMatch(invalid, set_state(Pid, oncall, #call{id="invalid", source=self()})),
	?assertMatch(invalid, set_state(Pid, outgoing)),
	?assertMatch(invalid, set_state(Pid, outgoing, Call)),
	?assertMatch(invalid, set_state(Pid, warmtransfer)),
	?assertMatch(invalid, set_state(Pid, warmtransfer, Call)),
	?assertMatch(invalid, set_state(Pid, wrapup)),
	?assertMatch(invalid, set_state(Pid, wrapup, Call)),
	
	%% now the successes
	?assertMatch(ok, set_state(Pid, idle)),
	?assertMatch({ok, idle}, query_state(Pid)),
	set_state(Pid, ringing, Call),
	?assertMatch(ok, set_state(Pid, oncall, Call)),
	?assertMatch({ok, oncall}, query_state(Pid)),
	set_state(Pid, wrapup, Call),
	set_state(Pid, idle),
	set_state(Pid, ringing, Call),
	?assertMatch(ok, set_state(Pid, released, default)),
	?assertMatch({ok, released}, query_state(Pid)).
	
	
precall_state_test() ->
	{_, Pid} = start(#agent{login="testagent"}),
	Call = #call{id="testcall", source=self()},
	Client = "dummyclient",
	
	?assertMatch(ok, set_state(Pid, precall, Client)),
	
	%% first, the failures.
	?assertMatch(invalid, set_state(Pid, ringing, Call)),
	?assertMatch(invalid, set_state(Pid, precall, Client)),
	?assertMatch(invalid, set_state(Pid, oncall, Call)),
	?assertMatch(invalid, set_state(Pid, warmtransfer, Call)),
	?assertMatch(invalid, set_state(Pid, wrapup, Call)),
	
	%% now the successes.
	?assertMatch(ok, set_state(Pid, outgoing, Call)),
	?assertMatch({ok, outgoing}, query_state(Pid)),
	set_state(Pid, wrapup, Call),
	set_state(Pid, idle),
	set_state(Pid, precall, Client),
	?assertMatch(ok, set_state(Pid, released, default)),
	?assertMatch({ok, released}, query_state(Pid)),
	set_state(Pid, precall, Client),
	?assertMatch(ok, set_state(Pid, idle)),
	?assertMatch({ok, idle}, query_state(Pid)).

oncall_state_test() -> 
	{_, Pid} = start(#agent{login="testagent"}),
	Call = #call{id="testcall", source=self()},
	set_state(Pid, idle),
	set_state(Pid, ringing, Call),
	set_state(Pid, oncall, Call),
	
	% failures first
	?assertMatch(invalid, set_state(Pid, idle)),
	?assertMatch(invalid, set_state(Pid, ringing)),
	?assertMatch(invalid, set_state(Pid, precall)),
	?assertMatch(invalid, set_state(Pid, outgoing)),

	% successes
	?assertMatch(queued, set_state(Pid, released, default)),
	?assertMatch(ok, set_state(Pid, released, undefined)),
	?assertMatch({ok, oncall}, query_state(Pid)),
	?assertMatch(ok, set_state(Pid, warmtransfer, #call{id="dummycall", source=self()})),
	?assertMatch({ok, warmtransfer}, query_state(Pid)),
	set_state(Pid, oncall, Call),
	?assertMatch(ok, set_state(Pid, wrapup, Call)),
	?assertMatch({ok, wrapup}, query_state(Pid)).
	
outgoing_state_test() ->
	{_, Pid} = start(#agent{login="testagent"}),
	Call = #call{id="testcall", source=self()},
	Client = "dummyclient",
	set_state(Pid, idle),
	set_state(Pid, precall, Client),
	set_state(Pid, outgoing, Call),
	
	% failures first
	?assertMatch(invalid, set_state(Pid, idle)),
	?assertMatch(invalid, set_state(Pid, ringing)),
	?assertMatch(invalid, set_state(Pid, precall)),
	?assertMatch(invalid, set_state(Pid, oncall)),
	?assertMatch(invalid, set_state(Pid, outgoing)),
	?assertMatch(invalid, set_state(Pid, wrapup)),
	
	% successes now
	?assertMatch(queued, set_state(Pid, released, default)),
	?assertMatch({ok, outgoing}, query_state(Pid)),
	?assertMatch(ok, set_state(Pid, released, undefined)),
	?assertMatch({ok, outgoing}, query_state(Pid)),
	?assertMatch(ok, set_state(Pid, warmtransfer, #call{id="dummycall", source=self()})),
	?assertMatch({ok, warmtransfer}, query_state(Pid)),
	set_state(Pid, outgoing, Call),
	?assertMatch(ok, set_state(Pid, wrapup, Call)),
	?assertMatch({ok, wrapup}, query_state(Pid)).
	
released_state_test() -> 
	{_, Pid} = start(#agent{login="testagent"}),
	Call = #call{id="testcall", source=self()},
	Client = "dummyclient",
	
	?assertMatch({ok, released}, query_state(Pid)),
	
	% failures first
	?assertMatch(invalid, set_state(Pid, oncall, Call)),
	?assertMatch(invalid, set_state(Pid, outgoing, Call)),
	?assertMatch(invalid, set_state(Pid, warmtransfer, Call)),
	?assertMatch(invalid, set_state(Pid, wrapup, Call)),
	
	% successes
	?assertMatch(ok, set_state(Pid, idle)),
	?assertMatch({ok, idle}, query_state(Pid)),
	?assertMatch(ok, set_state(Pid, ringing, Call)),
	?assertMatch({ok, ringing}, query_state(Pid)),
	set_state(Pid, released, default),
	?assertMatch(ok, set_state(Pid, precall, Client)),
	?assertMatch({ok, precall}, query_state(Pid)),
	set_state(Pid, released, default),
	?assertMatch(ok, set_state(Pid, released, {1, 1})),
	?assertMatch({ok, released}, query_state(Pid)),
	?assertMatch(ok, set_state(Pid, ringing, Call)),
	?assertMatch({ok, ringing}, query_state(Pid)).
	
warmtransfer_state_test() ->
	{_, Pid} = start(#agent{login="testagent"}),
	Call = #call{id="testcall", source=self()},
	Callto = #call{id="callto", source=self()},
	Client = "dummyclient",
	
	set_state(Pid, ringing, Call),
	set_state(Pid, oncall, Call),
	set_state(Pid, warmtransfer, Callto),
	?assertMatch({ok, warmtransfer}, query_state(Pid)),
	
	%failures first
	?assertMatch(invalid, set_state(Pid, idle)),
	?assertMatch(invalid, set_state(Pid, ringing, Callto)),
	?assertMatch(invalid, set_state(Pid, precall, Client)),
	?assertMatch(invalid, set_state(Pid, warmtransfer, Callto)),
	
	% successes
	?assertMatch(ok, set_state(Pid, oncall, Call)),
	?assertMatch({ok, oncall}, query_state(Pid)),
	set_state(Pid, warmtransfer, Callto),
	?assertMatch(ok, set_state(Pid, outgoing, Call)),
	?assertMatch({ok, outgoing}, query_state(Pid)),
	set_state(Pid, warmtransfer, Callto),
	?assertMatch(queued, set_state(Pid, released, default)),
	?assertMatch({ok, warmtransfer}, query_state(Pid)),
	?assertMatch(ok, set_state(Pid, released, undefined)),
	?assertMatch({ok, warmtransfer}, query_state(Pid)),
	?assertMatch(ok, set_state(Pid, wrapup, Call)),
	?assertMatch({ok, wrapup}, query_state(Pid)).

wrapup_state_test() -> 
	{_, Pid} = start(#agent{login="testagent"}),
	Call = #call{id="testcall", source=self()},
	Callto = #call{id="callto", source=self()},
	Client = "dummyclient",

	set_state(Pid, ringing, Call),
	set_state(Pid, oncall, Call),
	set_state(Pid, wrapup, Call),
	?assertMatch({ok, wrapup}, query_state(Pid)),
	
	% failures first
	?assertMatch(invalid, set_state(Pid, ringing, Call)),
	?assertMatch(invalid, set_state(Pid, precall, Client)),
	?assertMatch(invalid, set_state(Pid, oncall, Call)),
	?assertMatch(invalid, set_state(Pid, outgoing, Call)),
	?assertMatch(invalid, set_state(Pid, warmtransfer, Callto)),
	?assertMatch(invalid, set_state(Pid, wrapup, Call)),
	
	% successes
	?assertMatch(ok, set_state(Pid, idle)),
	?assertMatch({ok, idle}, query_state(Pid)),
	set_state(Pid, ringing, Call),
	set_state(Pid, oncall, Call),
	set_state(Pid, wrapup, Call),
	?assertMatch(queued, set_state(Pid, released, default)),
	?assertMatch({ok, wrapup}, query_state(Pid)),
	?assertMatch(ok, set_state(Pid, released, undefined)),
	?assertMatch({ok, wrapup}, query_state(Pid)),
	set_state(Pid, released, default),
	set_state(Pid, idle),
	?assertMatch({ok, released}, query_state(Pid)).

generate_state() ->
	generate_state([{2, idle, "Idle"}, {3, ringing, "Ringing"}, {4, precall, "Precall"}, {5, oncall, "Oncall"}, {6, outgoing, "Outgoing"}, {7, released, "Released"}, {8, warmtransfer, "WarmTransfer"}, {9, wrapup, "Wrapup"}]).
generate_state([{Int, Atom, String}|T]) -> 
	[{"Automated test for " ++ integer_to_list(Int) ++ ", " ++ atom_to_list(Atom), 
		fun() -> 
			?assertEqual(Int, state_to_integer(Atom)),
			?assertEqual(Atom, integer_to_state(Int)),
			?assertEqual(Atom, list_to_state(String))
		end
		}|generate_state(T)];
generate_state([]) -> 
	[].

cross_check_state_test_() ->
	generate_state().

-endif.
