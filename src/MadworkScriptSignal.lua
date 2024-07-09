--[[
{Madwork}

-[MadworkScriptSignal]---------------------------------------

	WARNING: .NewArrayScriptConnection() has undefined behaviour when listeners disconnect listeners within
		"listener_table" before all listeners inside "listener_table" have been fired.
		
	WARNING #2: Always assume undefined listener invocation order for [ScriptSignal] class; Current implementation invokes
		In the backwards order of connection time.

	Functions:
	
		MadworkScriptSignal.NewArrayScriptConnection(listener_table, listener, disconnect_listener, disconnect_param) --> [ScriptConnection]
			listener_table        [table]
			listener              [function]
			disconnect_listener   nil or [function] -- Yield-safe
			disconnect_param      nil or [value]
			
		MadworkScriptSignal.NewScriptSignal() --> [ScriptSignal]
		
	Methods [ScriptSignal]:
	
		ScriptSignal:Connect(listener, disconnect_listener, disconnect_param) --> [ScriptConnection] listener(...) -- (listener functions can't yield)
			listener              [function]
			disconnect_listener   nil or [function] -- Yield-safe
			disconnect_param      nil or [value]
			
		ScriptSignal:GetListenerCount() --> [number]
			
		ScriptSignal:Fire(...) -- Yield-safe
		
		ScriptSignal:FireUntil(continue_callback, ...) -- NOT YIELF-SAFE
		
	Methods [ScriptConnection]:
	
		ScriptConnection:Disconnect() -- Disconnect listener from signal
	
--]]

----- Module Table -----

local MadworkScriptSignal = {

}

----- Private variables -----

local FreeRunnerThread = nil

----- Private functions -----

--[[
	Yield-safe coroutine reusing by stravant;
	Sources:
	https://devforum.roblox.com/t/lua-signal-class-comparison-optimal-goodsignal-class/1387063
	https://gist.github.com/stravant/b75a322e0919d60dde8a0316d1f09d2f
--]]

local function AcquireRunnerThreadAndCallEventHandler(fn, ...)
	local acquired_runner_thread = FreeRunnerThread
	FreeRunnerThread = nil
	fn(...)
	-- The handler finished running, this runner thread is free again.
	FreeRunnerThread = acquired_runner_thread
end

local function RunEventHandlerInFreeThread(...)
	AcquireRunnerThreadAndCallEventHandler(...)
	while true do
		AcquireRunnerThreadAndCallEventHandler(coroutine.yield())
	end
end

----- Public -----

-- ArrayScriptConnection object:

local ArrayScriptConnection = {
	--[[
		_listener = function -- [function]
		_listener_table = {} -- [table] -- Table from which the function entry will be removed
		_disconnect_listener -- [function / nil]
		_disconnect_param    -- [value / nil]
	--]]
}

function ArrayScriptConnection:Disconnect()
	local listener = self._listener
	if listener ~= nil then
		local listener_table = self._listener_table
		local index = table.find(listener_table, listener)
		if index ~= nil then
			table.remove(listener_table, index)
		end
		self._listener = nil
	end
	if self._disconnect_listener ~= nil then
		if not FreeRunnerThread then
			FreeRunnerThread = coroutine.create(RunEventHandlerInFreeThread)
		end
		task.spawn(FreeRunnerThread, self._disconnect_listener, self._disconnect_param)
		self._disconnect_listener = nil
	end
end

function MadworkScriptSignal.NewArrayScriptConnection(listener_table, listener, disconnect_listener, disconnect_param) --> [ScriptConnection]
	return {
		_listener = listener,
		_listener_table = listener_table,
		_disconnect_listener = disconnect_listener,
		_disconnect_param = disconnect_param,
		Disconnect = ArrayScriptConnection.Disconnect
	}
end

-- ScriptConnection object:

local ScriptConnection = {
	--[[
		_listener = listener,
		_script_signal = script_signal,
		_disconnect_listener = disconnect_listener,
		_disconnect_param = disconnect_param,
		
		_next = next_script_connection,
		_is_connected = is_connected,
	--]]
}
ScriptConnection.__index = ScriptConnection

function ScriptConnection:Disconnect()

	if self._is_connected == false then
		return
	end

	self._is_connected = false
	self._script_signal._listener_count -= 1

	if self._script_signal._head == self then
		self._script_signal._head = self._next
	else
		local prev = self._script_signal._head
		while prev ~= nil and prev._next ~= self do
			prev = prev._next
		end
		if prev ~= nil then
			prev._next = self._next
		end
	end

	if self._disconnect_listener ~= nil then
		if not FreeRunnerThread then
			FreeRunnerThread = coroutine.create(RunEventHandlerInFreeThread)
		end
		task.spawn(FreeRunnerThread, self._disconnect_listener, self._disconnect_param)
		self._disconnect_listener = nil
	end

end

-- ScriptSignal object:

local ScriptSignal = {
	--[[
		_head = nil,
		_listener_count = 0,
	--]]
}
ScriptSignal.__index = ScriptSignal

function ScriptSignal:Connect(listener, disconnect_listener, disconnect_param) --> [ScriptConnection]

	local script_connection = {
		_listener = listener,
		_script_signal = self,
		_disconnect_listener = disconnect_listener,
		_disconnect_param = disconnect_param,

		_next = self._head,
		_is_connected = true,
	}
	setmetatable(script_connection, ScriptConnection)

	self._head = script_connection
	self._listener_count += 1

	return script_connection

end

function ScriptSignal:GetListenerCount() --> [number]
	return self._listener_count
end

function ScriptSignal:Fire(...)
	local item = self._head
	while item ~= nil do
		if item._is_connected == true then
			if not FreeRunnerThread then
				FreeRunnerThread = coroutine.create(RunEventHandlerInFreeThread)
			end
			task.spawn(FreeRunnerThread, item._listener, ...)
		end
		item = item._next
	end
end

function ScriptSignal:FireUntil(continue_callback, ...)
	local item = self._head
	while item ~= nil do
		if item._is_connected == true then
			item._listener(...)
			if continue_callback() ~= true then
				return
			end
		end
		item = item._next
	end
end

function MadworkScriptSignal.NewScriptSignal() --> [ScriptSignal]
	return {
		_head = nil,
		_listener_count = 0,
		Connect = ScriptSignal.Connect,
		GetListenerCount = ScriptSignal.GetListenerCount,
		Fire = ScriptSignal.Fire,
		FireUntil = ScriptSignal.FireUntil,
	}
end

return MadworkScriptSignal