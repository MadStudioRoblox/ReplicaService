--[[
{Madwork}

-[MadworkScriptSignal]---------------------------------------

	WARNING: .NewArrayScriptConnection() has undefined behaviour when listeners disconnect listeners within
		"listener_table" before all listeners inside "listener_table" have been fired.

	Functions:
	
		MadworkScriptSignal.NewArrayScriptConnection(listener_table, listener, disconnect_listener, disconnect_param) --> [ScriptConnection]
			listener_table        [table]
			listener              [function]
			disconnect_listener   nil or [function]
			disconnect_param      nil or [value]
			
		MadworkScriptSignal.NewScriptSignal() --> [ScriptSignal]
		
	Methods [ScriptSignal]:
	
		ScriptSignal:Connect(listener, disconnect_listener, disconnect_param) --> [ScriptConnection] listener(...) -- (listener functions can't yield)
			listener              [function]
			disconnect_listener   nil or [function]
			disconnect_param      nil or [value]
			
		ScriptSignal:GetListenerCount() --> [number]
			
		ScriptSignal:Fire(...)
		
	Methods [ScriptConnection]:
	
		ScriptConnection:Disconnect() -- Disconnect listener from signal
	
--]]

----- Module Table -----

local MadworkScriptSignal = {
	
}

----- Public functions -----

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
		self._disconnect_listener(self._disconnect_param)
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
	--]]
}

function ScriptConnection:Disconnect()
	local listener = self._listener
	if listener ~= nil then
		local script_signal = self._script_signal
		local fire_pointer_stack = script_signal._fire_pointer_stack
		local listeners_next = script_signal._listeners_next
		local listeners_back = script_signal._listeners_back
		-- Check fire pointers:
		for i = 1, script_signal._stack_count do
			if fire_pointer_stack[i] == listener then
				fire_pointer_stack[i] = listeners_next[listener]
			end
		end
		-- Remove listener:
		if script_signal._tail_listener == listener then
			local new_tail = listeners_back[listener]
			if new_tail ~= nil then
				listeners_next[new_tail] = nil
				listeners_back[listener] = nil
			else
				script_signal._head_listener = nil -- tail was also head
			end
			script_signal._tail_listener = new_tail
		elseif script_signal._head_listener == listener then
			-- If this listener is not the tail, assume another listener is the tail:
			local new_head = listeners_next[listener]
			listeners_back[new_head] = nil
			listeners_next[listener] = nil
			script_signal._head_listener = new_head
		else
			local next_listener = listeners_next[listener]
			local back_listener = listeners_back[listener]
			if next_listener ~= nil or back_listener ~= nil then -- Catch cases when duplicate listeners are disconnected
				listeners_next[back_listener] = next_listener
				listeners_back[next_listener] = back_listener
				listeners_next[listener] = nil
				listeners_back[listener] = nil
			end
		end
		self._listener = nil
		script_signal._listener_count -= 1
	end
	if self._disconnect_listener ~= nil then
		self._disconnect_listener(self._disconnect_param)
		self._disconnect_listener = nil
	end
end

-- ScriptSignal object:

local ScriptSignal = {
	--[[
		_fire_pointer_stack = {},
		_stack_count = 0,
		_listener_count = 0,
		_listeners_next = {}, -- [listener] = next_listener
		_listeners_back = {}, -- [listener] = back_listener
		_head_listener = nil,
		_tail_listener = nil,
	--]]
}

function ScriptSignal:Connect(listener, disconnect_listener, disconnect_param) --> [ScriptConnection]
	if type(listener) ~= "function" then
		error("[MadworkScriptSignal]: Only functions can be passed to ScriptSignal:Connect()")
	end
	local tail_listener = self._tail_listener
	if tail_listener == nil then
		self._head_listener = listener
		self._tail_listener = listener
		self._listener_count += 1
	elseif tail_listener ~= listener and self._listeners_next[listener] == nil then -- Prevent connecting the same listener more than once
		self._listeners_next[tail_listener] = listener
		self._listeners_back[listener] = tail_listener
		self._tail_listener = listener
		self._listener_count += 1
	end
	return {
		_listener = listener,
		_script_signal = self,
		_disconnect_listener = disconnect_listener,
		_disconnect_param = disconnect_param,
		Disconnect = ScriptConnection.Disconnect
	}
end

function ScriptSignal:GetListenerCount()
	return self._listener_count
end

function ScriptSignal:Fire(...)
	local fire_pointer_stack = self._fire_pointer_stack
	local stack_id = self._stack_count + 1
	self._stack_count = stack_id
	
	local listeners_next = self._listeners_next
	fire_pointer_stack[stack_id] = self._head_listener
	while true do
		local pointer = fire_pointer_stack[stack_id]
		fire_pointer_stack[stack_id] = listeners_next[pointer]
		if pointer ~= nil then
			pointer(...)
		else
			break
		end
	end
	self._stack_count -= 1
end

function MadworkScriptSignal.NewScriptSignal() --> [ScriptSignal]
	return {
		_fire_pointer_stack = {},
		_stack_count = 0,
		_listener_count = 0,
		_listeners_next = {},
		_listeners_back = {},
		_head_listener = nil,
		_tail_listener = nil,
		Connect = ScriptSignal.Connect,
		GetListenerCount = ScriptSignal.GetListenerCount,
		Fire = ScriptSignal.Fire
	}
end

return MadworkScriptSignal