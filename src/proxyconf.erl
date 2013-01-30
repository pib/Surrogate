%%% -------------------------------------------------------------------
%%% Author  : skruger
%%% Description :
%%%
%%% Created : Nov 11, 2010
%%% -------------------------------------------------------------------
-module(proxyconf).

-behaviour(gen_server).
%% --------------------------------------------------------------------
%% Include files
%% --------------------------------------------------------------------

-include("surrogate.hrl").

%% --------------------------------------------------------------------
%% External exports
-export([start_link/0]).

-export([reload/0,get/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(state, {config_terms}).

%% ====================================================================
%% External functions
%% ====================================================================

start_link() ->
    gen_server:start_link({local,?MODULE},?MODULE,
                          #state{config_terms=application:get_all_env(surrogate)},[]).

get(Prop,Def) ->
	try
		gen_server:call(?MODULE,{property,Prop,Def})
	catch
		_:Err ->
			?ERROR_MSG("Error getting settings: ~p~n",[Err]),
			Def
	end.

reload() ->
	gen_server:cast(?MODULE,reload).

%% ====================================================================
%% Server functions
%% ====================================================================

%% --------------------------------------------------------------------
%% Function: init/1
%% Description: Initiates the server
%% Returns: {ok, State}          |
%%          {ok, State, Timeout} |
%%          ignore               |
%%          {stop, Reason}
%% --------------------------------------------------------------------
init(State) ->
	?INFO_MSG("Starting ~p.",[?MODULE]),
	mnesia:create_schema([node()]),
	
	mnesia:change_table_copy_type(schema,node(),disc_copies),

	%% Create http_admin_module table so modules can register themselves with http_admin.
	mnesia:create_table(http_admin_module,[{attributes,record_info(fields,http_admin_module)},{local_content,true}]),
	mnesia:add_table_copy(http_admin_module,node(),ram_copies),
	mnesia:clear_table(http_admin_module),
	mnesia:create_table(proxy_acl,[{attributes,record_info(fields,proxy_acl)},{type,bag}]),
	mnesia:clear_table(proxy_acl),
 	mnesia:change_table_copy_type(proxy_acl,node(),disc_copies),
 	mnesia:add_table_copy(proxy_acl,node(),disc_copies),
		
	Acls = proplists:get_all_values(acl,State#state.config_terms),
	proxy_acl:clear_all_permissions(),
	[proxy_acl:set_permission(List, User) || {List,User} <- Acls],
	
	%% Start filters as specified in proxy.conf {filter_modules,[{module,ArgList}|_]}
	Filters = proplists:get_value(modules,State#state.config_terms,[]),
	spawn(proxy_mod,start_proxy_modules,[Filters]),
	
	LogLevel = proplists:get_value(log_level,State#state.config_terms,5),
	surrogate_log:log_level(LogLevel),
	?DEBUG_MSG("~p init with ~p~n",[?MODULE,State]),
	{ok, State#state{}}.

%% --------------------------------------------------------------------
%% Function: handle_call/3
%% Description: Handling call messages
%% Returns: {reply, Reply, State}          |
%%          {reply, Reply, State, Timeout} |
%%          {noreply, State}               |
%%          {noreply, State, Timeout}      |
%%          {stop, Reason, Reply, State}   | (terminate/2 is called)
%%          {stop, Reason, State}            (terminate/2 is called)
%% --------------------------------------------------------------------
handle_call({property,Key,Default},_From,State) ->
	Ret = proplists:get_value(Key,State#state.config_terms,Default),
	{reply,Ret,State};
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

%% --------------------------------------------------------------------
%% Function: handle_cast/2
%% Description: Handling cast messages
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%% --------------------------------------------------------------------
handle_cast(reload,State) ->
	{stop,reload,State};
handle_cast(_Msg, State) ->
    {noreply, State}.

%% --------------------------------------------------------------------
%% Function: handle_info/2
%% Description: Handling all non call/cast messages
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%% --------------------------------------------------------------------
handle_info(_Info, State) ->
    {noreply, State}.

%% --------------------------------------------------------------------
%% Function: terminate/2
%% Description: Shutdown the server
%% Returns: any (ignored by gen_server)
%% --------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%% --------------------------------------------------------------------
%% Func: code_change/3
%% Purpose: Convert process state when code is changed
%% Returns: {ok, NewState}
%% --------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% --------------------------------------------------------------------
%%% Internal functions
%% --------------------------------------------------------------------

