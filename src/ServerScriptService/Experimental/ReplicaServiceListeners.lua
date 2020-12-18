--[[
{Madwork}

-[ReplicaServiceListeners]---------------------------------------
	Injects listener methods to the Replica class server-side - these methods are otherwise
		only accessible client-side due to personal decisions based on code sanity.
	
	More information about the decision to opt out server-side listeners can be found here:
	https://devforum.roblox.com/t/replicate-your-states-with-replicaservice-networking-system/894736/22
	
	After this module is required it directly alters the Replica class in ReplicaService and
	wraps the setter methods to drive connected listeners.
	
	Injected methods [Replica]:
	
		Replica:ListenToChange(path, listener) --> [ScriptConnection] (new_value, old_value)
		Replica:ListenToNewKey(path, listener) --> [ScriptConnection] (new_value, new_key)
		Replica:ListenToArrayInsert(path, listener) --> [ScriptConnection] (new_index, new_value)
		Replica:ListenToArraySet(path, listener) --> [ScriptConnection] (index, new_value)
		Replica:ListenToArrayRemove(path, listener) --> [ScriptConnection] (old_index, old_value)
		Replica:ListenToWrite(function_name, listener) --> [ScriptConnection] (params...)
		Replica:ListenToRaw(listener) --> [ScriptConnection] (action_name, path_array, params...)
		
	-- NOTICE: This module returns a reference to require(ReplicaService) - if your game code execution is
		not linear then it's advised to fetch ReplicaService through this module.
--]]

local SETTINGS = {

}

----- Module Table -----

local ReplicaServiceListeners = {

}

----- Loaded Modules -----

local ReplicaService = require(game:GetService("ServerScriptService"):FindFirstChild("ReplicaService", true))

----- Private functions -----

local function StringPathToArray(path)
	local path_array = {}
	if path ~= "" then
		for s in string.gmatch(path, "[^%.]+") do
			table.insert(path_array, s)
		end
	end
	return path_array
end

local function CreateTableListenerPathIndex(replica, path_array, listener_type)
	-- Getting listener table:
	local listeners = replica._table_listeners
	-- Getting and or creating the structure nescessary to index the path for the listened key:
	for i = 1, #path_array do
		local key_listeners = listeners[1][path_array[i]]
		if key_listeners == nil then
			key_listeners = {[1] = {}}
			listeners[1][path_array[i]] = key_listeners
		end
		listeners = key_listeners
	end

	local listener_type_table = listeners[listener_type]
	if listener_type_table == nil then
		listener_type_table = {}
		listeners[listener_type] = listener_type_table
	end
	return listener_type_table
end

local function CleanTableListenerTable(disconnect_param)
	local table_listeners = disconnect_param[1]
	local path_array = disconnect_param[2]
	local pointer = table_listeners
	local pointer_stack = {pointer}
	for i = 1, #path_array do
		pointer = pointer[1][path_array[i]]
		table.insert(pointer_stack, pointer)
	end
	for i = #pointer_stack, 2, -1 do
		local listeners = pointer_stack[i]
		if next(listeners[1]) ~= nil then
			return -- Lower branches exist for this branch - this branch will not need further cleanup
		end
		for k = 2, 6 do
			if listeners[k] ~= nil then
				if #listeners[k] > 0 then
					return -- A listener exists - this branch will not need further cleanup
				end
			end
		end
		pointer_stack[i - 1][1][path_array[i - 1]] = nil -- Clearing listeners table for this branch
	end
end

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

local function NewArrayScriptConnection(listener_table, listener, disconnect_listener, disconnect_param) --> [ScriptConnection]
	return {
		_listener = listener,
		_listener_table = listener_table,
		_disconnect_listener = disconnect_listener,
		_disconnect_param = disconnect_param,
		Disconnect = ArrayScriptConnection.Disconnect
	}
end

----- Initialize -----

do
	
	local Replica = ReplicaService._replica_class
	
	-- Wrapping Replica creation:
	local new_replica_raw = ReplicaService.NewReplica
	
	function ReplicaService.NewReplica(replica_params)
		local replica = new_replica_raw(replica_params)
		
		-- Creating listener tables:
		replica._table_listeners = {[1] = {}}
		replica._function_listeners = {}
		replica._raw_listeners = {}
		
		return replica
	end
	
	-- Wrapping Replica listeners:
	local set_value_raw = Replica.SetValue -- (replica, path, value)
	local set_values_raw = Replica.SetValues -- (replica, path, values)
	local array_insert_raw = Replica.ArrayInsert -- (replica, path, value) --> new_index
	local array_set_raw = Replica.ArraySet -- (replica, path, index, value)
	local array_remove_raw = Replica.ArrayRemove -- (replica, path, index) --> removed_value
	local write_raw = Replica.Write -- (replica, function_name, ...) --> return_params...
	
	function Replica:SetValue(path, value)
		local path_array = (type(path) == "string") and StringPathToArray(path) or path
		local replica = self
		-- Getting path pointer and listener table:
		local pointer = replica.Data
		local listeners = replica._table_listeners
		for i = 1, #path_array - 1 do
			pointer = pointer[path_array[i]]
			if listeners ~= nil then
				listeners = listeners[1][path_array[i]]
			end
		end
		-- Setting value:
		local key = path_array[#path_array]
		local old_value = pointer[key]
		set_value_raw(replica, path_array, value)
		-- Signaling listeners:
		if old_value ~= value and listeners ~= nil then
			if old_value == nil then
				if listeners[3] ~= nil then -- "NewKey" listeners
					for _, listener in ipairs(listeners[3]) do
						listener(value, key)
					end
				end
			end
			listeners = listeners[1][path_array[#path_array]]
			if listeners ~= nil then
				if listeners[2] ~= nil then -- "Change" listeners
					for _, listener in ipairs(listeners[2]) do
						listener(value, old_value)
					end
				end
			end
		end
		-- Raw listeners:
		for _, listener in ipairs(replica._raw_listeners) do
			listener("SetValue", path_array, value)
		end
	end

	function Replica:SetValues(path, values)
		local path_array = (type(path) == "string") and StringPathToArray(path) or path
		local replica = self
		-- Getting path pointer and listener table:
		local pointer = replica.Data
		local listeners = replica._table_listeners
		for i = 1, #path_array do
			pointer = pointer[path_array[i]]
			if listeners ~= nil then
				listeners = listeners[1][path_array[i]]
			end
		end
		-- Setting values:
		for key, value in pairs(values) do
			-- Set value:
			local old_value = pointer[key]
			pointer[key] = value
			-- Signaling listeners:
			if old_value ~= value and listeners ~= nil then
				if old_value == nil then
					if listeners[3] ~= nil then -- "NewKey" listeners
						for _, listener in ipairs(listeners[3]) do
							listener(value, key)
						end
					end
				end
				listeners = listeners[1][key]
				if listeners ~= nil then
					if listeners[2] ~= nil then -- "Change" listeners
						for _, listener in ipairs(listeners[2]) do
							listener(value, old_value)
						end
					end
				end
			end
		end
		-- We end up setting values twice here, but it shouldn't bother anyone too much:
		set_values_raw(replica, path_array, values)
		-- Raw listeners:
		for _, listener in ipairs(replica._raw_listeners) do
			listener("SetValues", path_array, values)
		end
	end

	function Replica:ArrayInsert(path, value) --> new_index
		local path_array = (type(path) == "string") and StringPathToArray(path) or path
		local replica = self
		-- Getting path pointer and listener table:
		local pointer = replica.Data
		local listeners = replica._table_listeners
		for i = 1, #path_array do
			pointer = pointer[path_array[i]]
			if listeners ~= nil then
				listeners = listeners[1][path_array[i]]
			end
		end
		-- Setting value:
		array_insert_raw(replica, path_array, value)
		-- Signaling listeners:
		local new_index = #pointer
		if listeners ~= nil then
			if listeners[4] ~= nil then -- "ArrayInsert" listeners
				for _, listener in ipairs(listeners[4]) do
					listener(new_index, value)
				end
			end
		end
		-- Raw listeners:
		for _, listener in ipairs(replica._raw_listeners) do
			listener("ArrayInsert", path_array, value)
		end
		return new_index
	end

	function Replica:ArraySet(path, index, value)
		local path_array = (type(path) == "string") and StringPathToArray(path) or path
		local replica = self
		-- Getting path pointer and listener table:
		local listeners = replica._table_listeners
		for i = 1, #path_array do
			if listeners ~= nil then
				listeners = listeners[1][path_array[i]]
			end
		end
		-- Setting value:
		array_set_raw(replica, path_array, index, value)
		-- Signaling listeners:
		if listeners ~= nil then
			if listeners[5] ~= nil then -- "ArraySet" listeners
				for _, listener in ipairs(listeners[5]) do
					listener(index, value)
				end
			end
		end
		-- Raw listeners:
		for _, listener in ipairs(replica._raw_listeners) do
			listener("ArraySet", path_array, index, value)
		end
	end

	function Replica:ArrayRemove(path, index) --> removed_value
		local path_array = (type(path) == "string") and StringPathToArray(path) or path
		local replica = self
		-- Getting path pointer and listener table:
		local listeners = replica._table_listeners
		for i = 1, #path_array do
			if listeners ~= nil then
				listeners = listeners[1][path_array[i]]
			end
		end
		-- Setting value:
		local old_value = array_remove_raw(replica, path_array, index)
		-- Signaling listeners:
		if listeners ~= nil then
			if listeners[6] ~= nil then -- "ArrayRemove" listeners
				for _, listener in ipairs(listeners[6]) do
					listener(index, old_value)
				end
			end
		end
		-- Raw listeners:
		for _, listener in ipairs(replica._raw_listeners) do
			listener("ArrayRemove", path_array, index, old_value)
		end
		return old_value
	end

	function Replica:Write(function_name, ...) --> return_params...
		local return_params = table.pack(write_raw(self, function_name, ...))
		-- Signaling listeners:
		local func_id = self._write_lib[function_name]
		func_id = func_id and func_id[1]
		
		local listeners = self._function_listeners[func_id]
		if listeners ~= nil then
			for _, listener in ipairs(listeners) do
				listener(...)
			end
		end
		return table.unpack(return_params)
	end
	
	-- Listener methods:
	function Replica:ListenToChange(path, listener) --> [ScriptConnection] listener(new_value)
		if type(listener) ~= "function" then
			error("[ReplicaService]: Only a function can be set as listener in Replica:ListenToChange()")
		end

		local path_array = (type(path) == "string") and StringPathToArray(path) or path
		if #path_array < 1 then
			error("[ReplicaService]: Passed empty path - a value key must be specified")
		end
		-- Getting listener table for given path:
		local listeners = CreateTableListenerPathIndex(self, path_array, 2)
		table.insert(listeners, listener)
		-- ScriptConnection which allows the disconnection of the listener:
		return NewArrayScriptConnection(listeners, listener, CleanTableListenerTable, {self._table_listeners, path_array})
	end

	function Replica:ListenToNewKey(path, listener) --> [ScriptConnection] listener(new_value, new_key)
		if type(listener) ~= "function" then
			error("[ReplicaService]: Only a function can be set as listener in Replica:ListenToNewKey()")
		end

		local path_array = (type(path) == "string") and StringPathToArray(path) or path
		-- Getting listener table for given path:
		local listeners = CreateTableListenerPathIndex(self, path_array, 3)
		table.insert(listeners, listener)
		-- ScriptConnection which allows the disconnection of the listener:
		if #path_array == 0 then
			return NewArrayScriptConnection(listeners, listener)
		else
			return NewArrayScriptConnection(listeners, listener, CleanTableListenerTable, {self._table_listeners, path_array})
		end
	end

	function Replica:ListenToArrayInsert(path, listener) --> [ScriptConnection] listener(new_value, new_index)
		if type(listener) ~= "function" then
			error("[ReplicaService]: Only a function can be set as listener in Replica:ListenToArrayInsert()")
		end

		local path_array = (type(path) == "string") and StringPathToArray(path) or path
		-- Getting listener table for given path:
		local listeners = CreateTableListenerPathIndex(self, path_array, 4)
		table.insert(listeners, listener)
		-- ScriptConnection which allows the disconnection of the listener:
		if #path_array == 0 then
			return NewArrayScriptConnection(listeners, listener)
		else
			return NewArrayScriptConnection(listeners, listener, CleanTableListenerTable, {self._table_listeners, path_array})
		end
	end

	function Replica:ListenToArraySet(path, listener) --> [ScriptConnection] listener(new_value, index)
		if type(listener) ~= "function" then
			error("[ReplicaService]: Only a function can be set as listener in Replica:ListenToArraySet()")
		end

		local path_array = (type(path) == "string") and StringPathToArray(path) or path
		-- Getting listener table for given path:
		local listeners = CreateTableListenerPathIndex(self, path_array, 5)
		table.insert(listeners, listener)
		-- ScriptConnection which allows the disconnection of the listener:
		if #path_array == 0 then
			return NewArrayScriptConnection(listeners, listener)
		else
			return NewArrayScriptConnection(listeners, listener, CleanTableListenerTable, {self._table_listeners, path_array})
		end
	end

	function Replica:ListenToArrayRemove(path, listener) --> [ScriptConnection] listener(old_value, old_index)
		if type(listener) ~= "function" then
			error("[ReplicaService]: Only a function can be set as listener in Replica:ListenToArrayRemove()")
		end

		local path_array = (type(path) == "string") and StringPathToArray(path) or path
		-- Getting listener table for given path:
		local listeners = CreateTableListenerPathIndex(self, path_array, 6)
		table.insert(listeners, listener)
		-- ScriptConnection which allows the disconnection of the listener:
		if #path_array == 0 then
			return NewArrayScriptConnection(listeners, listener)
		else
			return NewArrayScriptConnection(listeners, listener, CleanTableListenerTable, {self._table_listeners, path_array})
		end
	end

	function Replica:ListenToWrite(function_name, listener) --> [ScriptConnection] listener(params...)
		if type(listener) ~= "function" then
			error("[ReplicaService]: Only a function can be set as listener in Replica:ListenToWrite()")
		end
		if self._write_lib == nil then
			error("[ReplicaService]: _write_lib was not declared for this replica")
		end

		local func_id = self._write_lib[function_name]
		func_id = func_id and func_id[1]
		if func_id == nil then
			error("[ReplicaService]: Write function \"" .. function_name .. "\" not declared inside _write_lib of this replica")
		end

		-- Getting listener table for given path:
		local listeners = self._function_listeners[func_id]
		if listeners == nil then
			listeners = {}
			self._function_listeners[func_id] = listeners
		end
		table.insert(listeners, listener)
		-- ScriptConnection which allows the disconnection of the listener:
		return NewArrayScriptConnection(listeners, listener)
	end

	function Replica:ListenToRaw(listener) --> [ScriptConnection] (action_name, params...)
		local listeners = self._raw_listeners
		table.insert(listeners, listener)
		return NewArrayScriptConnection(listeners, listener)
	end
	
end

return ReplicaService