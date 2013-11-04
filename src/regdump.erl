%%%-------------------------------------------------------------------
%%% @author Frank Hunleth <fhunleth@troodon-software.com>
%%% @copyright (C) 2013, Frank Hunleth
%%% @doc
%%%
%%% @end
%%% Created :  3 Nov 2013 by Frank Hunleth
%%%-------------------------------------------------------------------
-module(regdump).

-behaviour(gen_server).

%% API
-export([start_link/0]).
-export([dump/1, dump/2, dump/3, read/1, read/2, read/3, write/3, write/4]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3]).

-export([register_list/0, find_by_name/4]).

-define(SERVER, ?MODULE).

-record(state,
	{
	  port,
	  registers
	}).

%%%===================================================================
%%% API
%%%===================================================================
read(Module, Instance, Register) ->
    gen_server:call(?SERVER, {read, Module, Instance, Register}).

read(Address, Width) ->
    gen_server:call(?SERVER, {read, Address, Width}).

read(Address) ->
    read(Address, 32).

write(Module, Instance, Register, Value) ->
    gen_server:call(?SERVER, {write, Module, Instance, Register, Value}).

write(Address, Width, Value) ->
    gen_server:call(?SERVER, {write, Address, Width, Value}).

dump(Module, Instance, Register) ->
    gen_server:cast(?SERVER, {dump, Module, Instance, Register}).
dump(Module, Instance) ->
    gen_server:cast(?SERVER, {dump, Module, Instance}).
dump(Module) ->
    gen_server:cast(?SERVER, {dump, Module}).


%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([]) ->
    Driver = code:priv_dir(?MODULE) ++ "/regdump",
    Port = open_port({spawn_executable, Driver}, [stream, exit_status]),
    State = #state{ port = Port,
		    registers = register_list() },
    {ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call({read, Module, Instance, Register}, _From, State) ->
    {Address, Width} = find_by_name(Module, Instance, Register, State#state.registers),
    Reply = do_read(State#state.port, Address, Width),
    {reply, Reply, State};
handle_call({read, Address, Width}, _From, State) ->
    Reply = do_read(State#state.port, Address, Width),
    {reply, Reply, State};
handle_call({write, Module, Instance, Register, Value}, _From, State) ->
    {Address, Width} = find_by_name(Module, Instance, Register, State#state.registers),
    do_write(State#state.port, Address, Width, Value),
    {reply, ok, State};
handle_call({write, Address, Width, Value}, _From, State) ->
    do_write(State#state.port, Address, Width, Value),
    {reply, ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast({dump, Module, Instance, Register}, State) ->
    {Address, Width} = find_by_name(Module, Instance, Register, State#state.registers),
    Value = do_read(State#state.port, Address, Width),
    io:format("~p.~p.~p=~p~n", [Module, Instance, Register, pp(Module, Register, Value)]),
    {noreply, State};
handle_cast({dump, _Module, _Instance}, State) ->
    io:format("Not implemented~n"),
    {noreply, State};
handle_cast({dump, _Module}, State) ->
    io:format("Not implemented~n"),
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info(Info, State) ->
    io:format("Got handle_info: ~p~n", [Info]),
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
-define(COMMAND_READ,   0).
-define(COMMAND_WRITE,  1).

make_request(Command, Address, Width, Value) ->
    <<Command:8, Width:8, Address:32, Value:32>>.
parse_response(<<Value:32>>) ->
    Value.

do_read(Port, Address, Width) ->
    true = port_command(Port, make_request(?COMMAND_READ, Address, Width, 0)),
    receive
	{Port, {data, Data}} ->
	    parse_response(Data);
	{Port, {exit_status, _}} ->
	    exit(port_crashed)
    end.
do_write(Port, Address, Width, Value) ->
    true = port_command(Port, make_request(?COMMAND_READ, Address, Width, Value)).


pp(_Module, _Register, Value) ->
    io_lib:format("~.16#", [Value]).

ecap(Instance) ->
    [{16#48300100 + Instance * 16#80 + 16#00, 32, ecap, Instance, tsctr},
     {16#48300100 + Instance * 16#80 + 16#04, 32, ecap, Instance, ctrphs},
     {16#48300100 + Instance * 16#80 + 16#08, 32, ecap, Instance, cap1},
     {16#48300100 + Instance * 16#80 + 16#0c, 32, ecap, Instance, cap2},
     {16#48300100 + Instance * 16#80 + 16#10, 32, ecap, Instance, cap3},
     {16#48300100 + Instance * 16#80 + 16#14, 32, ecap, Instance, cap4},
     {16#48300100 + Instance * 16#80 + 16#28, 16, ecap, Instance, ecctl1},
     {16#48300100 + Instance * 16#80 + 16#2a, 16, ecap, Instance, ecctl2},
     {16#48300100 + Instance * 16#80 + 16#2c, 16, ecap, Instance, eceint},
     {16#48300100 + Instance * 16#80 + 16#2e, 16, ecap, Instance, ecflg},
     {16#48300100 + Instance * 16#80 + 16#30, 16, ecap, Instance, ecclr},
     {16#48300100 + Instance * 16#80 + 16#32, 16, ecap, Instance, ecfrc},
     {16#48300100 + Instance * 16#80 + 16#5c, 32, ecap, Instance, revid}
    ].

gpio(Instance) ->
    case Instance of
	0 -> gpio(Instance, 16#44e07000);
	1 -> gpio(Instance, 16#4804c000);
	2 -> gpio(Instance, 16#481ac000);
	3 -> gpio(Instance, 16#481ae000)
    end.

gpio(Instance, Base) ->
    [{Base + 16#00, 32, gpio, Instance, gpio_revision},
     {Base + 16#10, 32, gpio, Instance, gpio_sysconfig},
     {Base + 16#20, 32, gpio, Instance, gpio_eoi},
     {Base + 16#24, 32, gpio, Instance, gpio_irqstatus_raw_0},
     {Base + 16#28, 32, gpio, Instance, gpio_irqstatus_raw_1},
     {Base + 16#2c, 32, gpio, Instance, gpio_irqstatus_0},
     {Base + 16#30, 32, gpio, Instance, gpio_irqstatus_1},
     {Base + 16#34, 32, gpio, Instance, gpio_irqstatus_set_0},
     {Base + 16#38, 32, gpio, Instance, gpio_irqstatus_set_1},
     {Base + 16#3c, 32, gpio, Instance, gpio_irqstatus_clr_0},
     {Base + 16#40, 32, gpio, Instance, gpio_irqstatus_clr_1},
     {Base + 16#44, 32, gpio, Instance, gpio_irqwaken_0},
     {Base + 16#48, 32, gpio, Instance, gpio_irqwaken_1},
     {Base + 16#114, 32, gpio, Instance, gpio_sysstatus},
     {Base + 16#130, 32, gpio, Instance, gpio_ctrl},
     {Base + 16#134, 32, gpio, Instance, gpio_oe},
     {Base + 16#138, 32, gpio, Instance, gpio_datain},
     {Base + 16#13c, 32, gpio, Instance, gpio_dataout},
     {Base + 16#140, 32, gpio, Instance, gpio_leveldetect0},
     {Base + 16#144, 32, gpio, Instance, gpio_leveldetect1},
     {Base + 16#148, 32, gpio, Instance, gpio_risingdetect},
     {Base + 16#14c, 32, gpio, Instance, gpio_fallingdetect},
     {Base + 16#150, 32, gpio, Instance, gpio_debouncenable},
     {Base + 16#154, 32, gpio, Instance, gpio_debouncetime},
     {Base + 16#190, 32, gpio, Instance, gpio_cleardataout},
     {Base + 16#194, 32, gpio, Instance, gpio_setdataout}
    ].

register_list() ->
    ecap(0) ++
	ecap(1) ++
	ecap(2) ++
	gpio(0) ++
	gpio(1) ++
	gpio(2) ++
	gpio(3).

find_by_addr(Address, [{Address, _Width, Module, Instance, Register} | _T]) ->
    { Module, Instance, Register };
find_by_addr(Address, [_|T]) ->
    find_by_addr(Address, T);
find_by_addr(_Address, []) ->
    not_found.

find_by_name(Module, Instance, Register, Registers) ->
    Found = [ {Address, Width} || {Address, Width, M, I, R} <- Registers,
				  M == Module, I == Instance, R == Register],
    case Found of
	[] -> not_found;
	[OnlyOne] -> OnlyOne
    end.
