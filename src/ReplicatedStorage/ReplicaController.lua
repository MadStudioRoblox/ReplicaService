-- local Madwork = _G.Madwork
--[[
{Madwork}

-[ReplicaController]---------------------------------------
	(STANDALONE VERSION)
	Lua table replication achieved through write function wrapping
	
	LISTENER WARNING: Making listeners disconnect their own script connections may result in other listeners
		being skipped. Fix pending.
	
	WARNING: Replica update listeners are not cleaned up automatically (e.g. when their value's parent table is set to nil)
		unless the replica is destroyed. Either split one god replica into several replicas or carefully manage listeners
		with :Disconnect() to prevent memory leaks. Does not apply to destroyed replicas.
	
	Notice: Replicas are destroyed client-side when the server stops replicating the replica to the client or the
		server destroys the replica completely. This means that the exact replica that was previously destroyed
		client-side could be created again client-side (as a new object, though).
		
	Replica replication guarantees:
		- When the client receives first data, replica references received will have all nested replicas
			already loaded and accessible through Replica.Children;
		- When the client receives first data or receives selective replication of a top level replica,
			.NewReplicaSignal and .ReplicaOfClassCreated() will be fired for all replicas in the order
			they were created server-side from earliest to latest;
	
	Members:
	
		ReplicaController.NewReplicaSignal            [ScriptSignal](Replica) -- Fired every time an replica is created client-side
		ReplicaController.InitialDataReceivedSignal   [ScriptSignal]() -- Fired once after the client finishes receiving initial replica data from server
		ReplicaController.InitialDataReceived         [bool] -- Set to true after the client finishes receiving initial replica data from server
	
	Functions:
	
		ReplicaController.RequestData() -- Requests the server to start sending replica data
		
		ReplicaController.ReplicaOfClassCreated(replica_class, listener) --> [ScriptConnection] listener(replica)
		
		ReplicaController.GetReplicaById(replica_id) --> replica / nil
		
	Members [Replica]:
	
		Replica.Data       [table] (Read only) Table which is replicated
		
		Replica.Id         [number] Unique identifier
		Replica.Class      [string] Primary Replica identifier
		Replica.Tags       [table] Secondary Replica identifiers
		
		Replica.Parent     [Replica] or nil
		Replica.Children   [table]: {replica, ...}
		
	Methods [Replica]:
		
	-- Dictionary update listening: (listener functions can't yield)
		Replica:ListenToChange(path, listener) --> [ScriptConnection] (new_value, old_value)
		Replica:ListenToNewKey(path, listener) --> [ScriptConnection] (new_value, new_key)
		
		* Notice: When Replica:SetValues(path, values) is used server-side, Replica:ListenToChange() and Replica:ListenToNewKey()
			will only be invoked with changes to the top level keys in the "values" argument passed.
		
	-- (Numeric) Array update listening:
		Replica:ListenToArrayInsert(path, listener) --> [ScriptConnection] (new_index, new_value)
		Replica:ListenToArraySet(path, listener) --> [ScriptConnection] (index, new_value)
		Replica:ListenToArrayRemove(path, listener) --> [ScriptConnection] (old_index, old_value)
		
	-- Write function listening:
		Replica:ListenToWrite(function_name, listener) --> [ScriptConnection] (params...)
		
		* Parameter description for "path":
		
			[string] = "TableMember.TableMember" -- Roblox-style path
			[table] = {"Players", 2312310, "Health"} -- Key array path
			
		Replica:ListenToRaw(listener) --> [ScriptConnection] (action_name, path_array, params...)
			-- ("SetValue", path_array, value)
			-- ("SetValues", path_array, values)
			-- ("ArrayInsert", path_array, value, new_index)
			-- ("ArraySet", path_array, index, value)
			-- ("ArrayRemove", path_array, index, old_value)
		
	-- Signals:
		Replica:ConnectOnClientEvent(listener) --> [ScriptConnection] (params...) -- listener functions can't yield
		Replica:FireServer(params...) -- Fire a signal to server-side listeners for this specific Replica
		
	-- Children:
		Replica:ListenToChildAdded(listener) --> [ScriptConnection] listener(replica)
		
		Replica:FindFirstChildOfClass(replica_class) --> [Replica] or nil
			replica_class   [string]
		
	-- Debug:
		Replica:Identify() --> [string]
		
	-- Cleanup:
	
		Replica:IsActive() --> is_active [bool] -- Returns false if the replica was destroyed
	
		Replica:AddCleanupTask(task) -- Add cleanup task to be performed
		Replica:RemoveCleanupTask(task) -- Remove cleanup task
		
		* Parameter description for "Replica:AddCleanupTask()":
		
			[function] -- Function to be invoked when the Replica is destroyed (function can't yield)
			[RBXScriptConnection] -- Roblox script connection to be :Disconnect()'ed when the Replica is destroyed
			[Object] -- Object with a :Destroy() method to be destroyed when the Replica is destroyed (destruction method can't yield)
			
	-- Write function setters: (Calling outside a write function will throw an error)
	
		Replica:SetValue(path, value)
		Replica:SetValues(path, values)
		Replica:ArrayInsert(path, value) --> new_index
		Replica:ArraySet(path, index, value)
		Replica:ArrayRemove(path, index) --> removed_value
		Replica:Write(function_name, params...) --> return_params...

--]]

local SETTINGS = {
	RequestDataRepeat = 10,
	SetterError = "[ReplicaController]: Replica setters can only be called inside write functions",
}

local Madwork -- Standalone Madwork reference for portable version of ReplicaService/ReplicaController
do
	local RunService = game:GetService("RunService")
	
	local function WaitForDescendant(ancestor, instance_name, warn_name)
		local instance = ancestor:FindFirstChild(instance_name, true) -- Recursive
		if instance == nil then
			local start_time = os.clock()
			local connection
			connection = ancestor.DescendantAdded:Connect(function(descendant)
				if descendant.Name == instance_name then
					instance = descendant
				end
			end)
			while instance == nil do
				if start_time ~= nil and os.clock() - start_time > 1
					and (RunService:IsServer() == true or game:IsLoaded() == true) then
					start_time = nil
					warn("[" .. script.Name .. "]: Missing " .. warn_name .. " \"" .. instance_name
						.. "\" in " .. ancestor:GetFullName() .. "; Please check setup documentation")
				end
				task.wait()
			end
			connection:Disconnect()
			return instance
		else
			return instance
		end
	end
	
	local RemoteEventContainer
	if RunService:IsServer() == true then
		RemoteEventContainer = Instance.new("Folder")
		RemoteEventContainer.Name = "ReplicaRemoteEvents"
		RemoteEventContainer.Parent = game:GetService("ReplicatedStorage")
	else
		RemoteEventContainer = WaitForDescendant(game:GetService("ReplicatedStorage"), "ReplicaRemoteEvents", "folder")
	end
	
	Madwork = {
		GetShared = function(package_name, item_name)
			-- Ignoring package_name as we're working without Madwork framework
			return WaitForDescendant(game:GetService("ReplicatedStorage"), item_name, "module")
		end,
		GetModule = function(package_name, module_name)
			return WaitForDescendant(game:GetService("ServerScriptService"), module_name, "module")
		end,
		SetupRemoteEvent = function(remote_name)
			if RunService:IsServer() == true then
				local remote_event = Instance.new("RemoteEvent")
				remote_event.Name = remote_name
				remote_event.Parent = RemoteEventContainer
				return remote_event
			else
				return WaitForDescendant(RemoteEventContainer, remote_name, "remote event")
			end
		end,
		Shared = {}, -- A Madwork package reference - ReplicaService will try to check this table
	}
	
	local MadworkScriptSignal = require(Madwork.GetShared("Madwork", "MadworkScriptSignal"))
	Madwork.NewScriptSignal = MadworkScriptSignal.NewScriptSignal
	Madwork.NewArrayScriptConnection = MadworkScriptSignal.NewArrayScriptConnection
end

----- Controller Table -----

local ReplicaController = {

	NewReplicaSignal = Madwork.NewScriptSignal(), -- (Replica)
	InitialDataReceivedSignal = Madwork.NewScriptSignal(), -- ()
	InitialDataReceived = false,

	_replicas = {
		--[[
			[replica_id] = {
				Data = {}, -- [table] Replicated Replica data table
				Id = 1, -- [integer] Replica id
				Class = "", -- [string] Primary Replica identifier
				Tags = {UserId = 2312310}, -- [table] Secondary Replica identifiers
				
				Parent = Replica, -- [Replica / nil] -- Child replicas inherit replication settings
				Children = {}, -- [table] {replica, ...}
						
				_write_lib = {[func_id] = function, ...} / nil, -- [table] List of wrapped write functions
				_write_lib_dictionary = {["function_name"] = func_id, ...} / nil, -- [table] Dictionary of function names and their id's
				
				_table_listeners = {[1] = {}} -- [table] Listeners of specific value changes in replica data
				_function_listeners = {[func_id] = {listener, ...}, ...} -- [table] Listeners of write function calls
				_raw_listeners = {listener, ...},
				
				_signal_listeners = {},
				_maid = maid,
			}
		--]]
	},

	_class_listeners = {}, -- {["replica_class"] = script_signal, ...}
	_child_listeners = {}, -- {[replica_id] = {listener, ...}, ...}

}

--[[
	_table_listeners structure:
	
		_table_listeners = {
			[1] = {
				["key_of_table"] = {
					[1] = {["key_of_table"] = {...}, ...},
					[2] = {listener, ...} / nil, -- Change
					[3] = {listener, ...} / nil, -- NewKey
					[4] = {listener, ...} / nil, -- ArrayInsert
					[5] = {listener, ...} / nil, -- ArraySet
					[6] = {listener, ...} / nil, -- ArrayRemove
				},
			},
			[2] = {listener, ...} / nil, -- Change
			[3] = {listener, ...} / nil, -- NewKey
			[4] = {listener, ...} / nil, -- ArrayInsert
			[5] = {listener, ...} / nil, -- ArraySet
			[6] = {listener, ...} / nil, -- ArrayRemove
		}

	_function_listeners structure:
	
		_function_listeners = {
			[func_id] = {
				listening_function, ...
			},
			...
		}
--]]

----- Loaded Modules -----

local MadworkMaid = require(Madwork.GetShared("Madwork", "MadworkMaid"))

----- Private Variables -----

local Replica

local Replicas = ReplicaController._replicas
local NewReplicaSignal = ReplicaController.NewReplicaSignal

local ClassListeners = ReplicaController._class_listeners -- {["replica_class"] = script_signal, ...}
local ChildListeners = ReplicaController._child_listeners -- {[replica_id] = {listener, ...}, ...}

local rev_ReplicaRequestData = Madwork.SetupRemoteEvent("Replica_ReplicaRequestData")   -- Fired client-side when the client loads for the first time

local rev_ReplicaSetValue = Madwork.SetupRemoteEvent("Replica_ReplicaSetValue")         -- (replica_id, {path}, value)
local rev_ReplicaSetValues = Madwork.SetupRemoteEvent("Replica_ReplicaSetValues")       -- (replica_id, {path}, {values})
local rev_ReplicaArrayInsert = Madwork.SetupRemoteEvent("Replica_ReplicaArrayInsert")   -- (replica_id, {path}, value)
local rev_ReplicaArraySet = Madwork.SetupRemoteEvent("Replica_ReplicaArraySet")         -- (replica_id, {path}, index, value)
local rev_ReplicaArrayRemove = Madwork.SetupRemoteEvent("Replica_ReplicaArrayRemove")   -- (replica_id, {path}, index)
local rev_ReplicaWrite = Madwork.SetupRemoteEvent("Replica_ReplicaWrite")               -- (replica_id, func_id, params...)
local rev_ReplicaSignal = Madwork.SetupRemoteEvent("Replica_ReplicaSignal")             -- (replica_id, params...)
local rev_ReplicaSetParent = Madwork.SetupRemoteEvent("Replica_ReplicaSetParent")       -- (replica_id, parent_replica_id)
local rev_ReplicaCreate = Madwork.SetupRemoteEvent("Replica_ReplicaCreate")             -- (replica_id, {replica_data}) OR (top_replica_id, {creation_data}) or ({replica_package})
local rev_ReplicaDestroy = Madwork.SetupRemoteEvent("Replica_ReplicaDestroy")           -- (replica_id)

local DataRequestStarted = false

local LoadedWriteLibPacks = {}
--[[
	LoadedWriteLibPacks = {
		[ModuleScript] = {
			{[func_id] = function, ...}, -- Write functions
			{["function_name"] = func_id, ...}, -- Function names and their id's
		},
		...
	}
--]]

local WriteFunctionFlag = false -- Set to true when running inside a write function stack

----- Private functions -----

local function GetWriteLibFunctionsRecursive(list_table, pointer, name_stack)
	for key, value in pairs(pointer) do
		if type(value) == "table" then
			GetWriteLibFunctionsRecursive(list_table, value, name_stack .. key .. ".")
		elseif type(value) == "function" then
			table.insert(list_table, {name_stack .. key, value})
		else
			error("[ReplicaController]: Invalid write function value \"" .. tostring(value) .. "\" (" .. typeof(value) .. "); name_stack = \"" .. name_stack .. "\"")
		end
	end
end

local function LoadWriteLib(write_lib_module)
	local get_write_lib_pack = LoadedWriteLibPacks[write_lib_module]
	if get_write_lib_pack ~= nil then
		return get_write_lib_pack
	end

	local write_lib_raw = require(write_lib_module)

	local function_list = {} -- func_id = {func_name, func}

	GetWriteLibFunctionsRecursive(function_list, write_lib_raw, "")
	table.sort(function_list, function(item1, item2)
		return item1[1] < item2[1] -- Sort functions by their names - this creates a consistent indexing on server and client-side
	end)

	local write_lib = {} -- {[func_id] = function, ...}
	local write_lib_dictionary = {} -- {["function_name"] = func_id, ...}

	for func_id, func_params in ipairs(function_list) do
		write_lib[func_id] = func_params[2]
		write_lib_dictionary[func_params[1]] = func_id
	end

	local write_lib_pack = {write_lib, write_lib_dictionary}

	LoadedWriteLibPacks[write_lib_module] = write_lib_pack

	return write_lib_pack
end

local function StringPathToArray(path)
	local path_array = {}
	if path ~= "" then
		for s in string.gmatch(path, "[^%.]+") do
			table.insert(path_array, s)
		end
	end
	return path_array
end

local function DestroyReplicaAndDescendantsRecursive(replica, not_first_in_stack)
	-- Scan children replicas:
	for _, child in ipairs(replica.Children) do
		DestroyReplicaAndDescendantsRecursive(child, true)
	end

	local id = replica.Id
	-- Clear replica entry:
	Replicas[id] = nil
	-- Cleanup:
	replica._maid:Cleanup()
	-- Clear from children table of top parent replica:
	if not_first_in_stack ~= true then
		if replica.Parent ~= nil then
			local children = replica.Parent.Children
			table.remove(children, table.find(children, replica))
		end
	end
	-- Clear child listeners:
	ChildListeners[id] = nil
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

local function CreateReplicaBranch(replica_entries, created_replicas) --> created_replicas: {replica, ...}
	-- Sorting replica entries:
	-- replica_entries = {[replica_id_string] = {replica_class, replica_tags, data_table, parent_id / 0, write_lib_module / nil}, ...}
	local sorted_replica_entries = {} -- {replica_class, replica_tags, data_table, parent_id / 0, write_lib_module / nil, replica_id}, ...}
	for replica_id_string, replica_entry in pairs(replica_entries) do
		replica_entry[6] = tonumber(replica_id_string)
		table.insert(sorted_replica_entries, replica_entry)
	end
	table.sort(sorted_replica_entries, function(a, b)
		return a[6] < b[6]
	end)
	local waiting_for_parent = {} -- [parent_replica_id] = {replica, ...}
	created_replicas = created_replicas or {}
	for _, replica_entry in ipairs(sorted_replica_entries) do
		local replica_id = replica_entry[6]
		-- Fetching replica parent:
		local parent_id = replica_entry[4]
		local parent = nil
		local wait_for_parent = false
		if parent_id ~= 0 then
			parent = Replicas[parent_id]
			if parent == nil then
				wait_for_parent = true
			end
		end
		-- Fetching replica write_lib:
		local write_lib, write_lib_dictionary
		if replica_entry[5] ~= nil then
			local write_lib_pack = LoadWriteLib(replica_entry[5])
			write_lib = write_lib_pack[1]
			write_lib_dictionary = write_lib_pack[2]
		end
		-- New Replica object table:
		local replica = {
			Data = replica_entry[3],
			Id = replica_id,
			Class = replica_entry[1],
			Tags = replica_entry[2],

			Parent = parent,
			Children = {},

			_write_lib = write_lib,
			_write_lib_dictionary = write_lib_dictionary,

			_table_listeners = {[1] = {}},
			_function_listeners = {},
			_raw_listeners = {},

			_signal_listeners = {},
			_maid = MadworkMaid.NewMaid(),
		}
		setmetatable(replica, Replica)
		-- Setting as child to parent:
		if parent ~= nil then
			table.insert(parent.Children, replica)
		elseif wait_for_parent == true then
			local wait_table = waiting_for_parent[parent_id]
			if wait_table == nil then
				wait_table = {}
				waiting_for_parent[parent_id] = wait_table
			end
			table.insert(wait_table, replica)
		end
		-- Adding replica to replica list:
		Replicas[replica_id] = replica
		table.insert(created_replicas, replica)
		-- Checking replicas waiting for parent:
		local children_waiting = waiting_for_parent[replica_id]
		if children_waiting ~= nil then
			waiting_for_parent[replica_id] = nil
			for _, child_replica in ipairs(children_waiting) do
				child_replica.Parent = replica
				table.insert(replica.Children, child_replica)
			end
		end
	end
	if next(waiting_for_parent) ~= nil then
		-- An error occured while replicating an replica branch.
		local error_string = "[ReplicaService]: BRANCH REPLICATION ERROR - Missing parents: "
		for parent_replica_id, child_replicas in pairs(waiting_for_parent) do
			error_string = error_string .. "[" .. tostring(parent_replica_id) .. "]: {"
			for k, replica in ipairs(child_replicas) do
				error_string = error_string .. (k == 1 and "" or ", ") .. replica:Identify()
			end
			error_string = error_string .. "}; "
		end
		error(error_string)
	end
	return created_replicas
end

-- Write handlers:

local function ReplicaSetValue(replica_id, path_array, value)
	local replica = Replicas[replica_id]
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

local function ReplicaSetValues(replica_id, path_array, values)
	local replica = Replicas[replica_id]
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
			local key_listeners = listeners[1][key]
			if key_listeners ~= nil then
				if key_listeners[2] ~= nil then -- "Change" listeners
					for _, listener in ipairs(key_listeners[2]) do
						listener(value, old_value)
					end
				end
			end
		end
	end
	-- Raw listeners:
	for _, listener in ipairs(replica._raw_listeners) do
		listener("SetValues", path_array, values)
	end
end

local function ReplicaArrayInsert(replica_id, path_array, value) --> new_index
	local replica = Replicas[replica_id]
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
	table.insert(pointer, value)
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
		listener("ArrayInsert", path_array, value, new_index)
	end
	return new_index
end

local function ReplicaArraySet(replica_id, path_array, index, value)
	local replica = Replicas[replica_id]
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
	pointer[index] = value
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

local function ReplicaArrayRemove(replica_id, path_array, index) --> removed_value
	local replica = Replicas[replica_id]
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
	local old_value = table.remove(pointer, index)
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

----- Public functions -----

-- Replica object:

Replica = {}
Replica.__index = Replica

-- Listening:
function Replica:ListenToChange(path, listener) --> [ScriptConnection] listener(new_value)
	if type(listener) ~= "function" then
		error("[ReplicaController]: Only a function can be set as listener in Replica:ListenToChange()")
	end

	local path_array = (type(path) == "string") and StringPathToArray(path) or path
	if #path_array < 1 then
		error("[ReplicaController]: Passed empty path - a value key must be specified")
	end
	-- Getting listener table for given path:
	local listeners = CreateTableListenerPathIndex(self, path_array, 2)
	table.insert(listeners, listener)
	-- ScriptConnection which allows the disconnection of the listener:
	return Madwork.NewArrayScriptConnection(listeners, listener, CleanTableListenerTable, {self._table_listeners, path_array})
end

function Replica:ListenToNewKey(path, listener) --> [ScriptConnection] listener(new_value, new_key)
	if type(listener) ~= "function" then
		error("[ReplicaController]: Only a function can be set as listener in Replica:ListenToNewKey()")
	end

	local path_array = (type(path) == "string") and StringPathToArray(path) or path
	-- Getting listener table for given path:
	local listeners = CreateTableListenerPathIndex(self, path_array, 3)
	table.insert(listeners, listener)
	-- ScriptConnection which allows the disconnection of the listener:
	if #path_array == 0 then
		return Madwork.NewArrayScriptConnection(listeners, listener)
	else
		return Madwork.NewArrayScriptConnection(listeners, listener, CleanTableListenerTable, {self._table_listeners, path_array})
	end
end

function Replica:ListenToArrayInsert(path, listener) --> [ScriptConnection] listener(new_value, new_index)
	if type(listener) ~= "function" then
		error("[ReplicaController]: Only a function can be set as listener in Replica:ListenToArrayInsert()")
	end

	local path_array = (type(path) == "string") and StringPathToArray(path) or path
	-- Getting listener table for given path:
	local listeners = CreateTableListenerPathIndex(self, path_array, 4)
	table.insert(listeners, listener)
	-- ScriptConnection which allows the disconnection of the listener:
	if #path_array == 0 then
		return Madwork.NewArrayScriptConnection(listeners, listener)
	else
		return Madwork.NewArrayScriptConnection(listeners, listener, CleanTableListenerTable, {self._table_listeners, path_array})
	end
end

function Replica:ListenToArraySet(path, listener) --> [ScriptConnection] listener(new_value, index)
	if type(listener) ~= "function" then
		error("[ReplicaController]: Only a function can be set as listener in Replica:ListenToArraySet()")
	end

	local path_array = (type(path) == "string") and StringPathToArray(path) or path
	-- Getting listener table for given path:
	local listeners = CreateTableListenerPathIndex(self, path_array, 5)
	table.insert(listeners, listener)
	-- ScriptConnection which allows the disconnection of the listener:
	if #path_array == 0 then
		return Madwork.NewArrayScriptConnection(listeners, listener)
	else
		return Madwork.NewArrayScriptConnection(listeners, listener, CleanTableListenerTable, {self._table_listeners, path_array})
	end
end

function Replica:ListenToArrayRemove(path, listener) --> [ScriptConnection] listener(old_value, old_index)
	if type(listener) ~= "function" then
		error("[ReplicaController]: Only a function can be set as listener in Replica:ListenToArrayRemove()")
	end

	local path_array = (type(path) == "string") and StringPathToArray(path) or path
	-- Getting listener table for given path:
	local listeners = CreateTableListenerPathIndex(self, path_array, 6)
	table.insert(listeners, listener)
	-- ScriptConnection which allows the disconnection of the listener:
	if #path_array == 0 then
		return Madwork.NewArrayScriptConnection(listeners, listener)
	else
		return Madwork.NewArrayScriptConnection(listeners, listener, CleanTableListenerTable, {self._table_listeners, path_array})
	end
end

function Replica:ListenToWrite(function_name, listener) --> [ScriptConnection] listener(params...)
	if type(listener) ~= "function" then
		error("[ReplicaController]: Only a function can be set as listener in Replica:ListenToWrite()")
	end
	if self._write_lib == nil then
		error("[ReplicaController]: _write_lib was not declared for this replica")
	end

	local func_id = self._write_lib_dictionary[function_name]
	if func_id == nil then
		error("[ReplicaController]: Write function \"" .. function_name .. "\" not declared inside _write_lib of this replica")
	end

	-- Getting listener table for given path:
	local listeners = self._function_listeners[func_id]
	if listeners == nil then
		listeners = {}
		self._function_listeners[func_id] = listeners
	end
	table.insert(listeners, listener)
	-- ScriptConnection which allows the disconnection of the listener:
	return Madwork.NewArrayScriptConnection(listeners, listener)
end

function Replica:ListenToRaw(listener) --> [ScriptConnection] (action_name, params...)
	local listeners = self._raw_listeners
	table.insert(listeners, listener)
	return Madwork.NewArrayScriptConnection(listeners, listener)
end

-- Signals:
function Replica:ConnectOnClientEvent(listener) --> [ScriptConnection] listener(...)
	if type(listener) ~= "function" then
		error("[ReplicaController]: Only functions can be passed to Replica:ConnectOnClientEvent()")
	end
	table.insert(self._signal_listeners, listener)
	return Madwork.NewArrayScriptConnection(self._signal_listeners, listener)
end

function Replica:FireServer(...)
	rev_ReplicaSignal:FireServer(self.Id, ...)
end

-- Children:
function Replica:ListenToChildAdded(listener) --> [ScriptConnection] listener(replica)
	if type(listener) ~= "function" then
		error("[ReplicaController]: Only a function can be set as listener")
	end
	if Replicas[self.Id] == nil then
		return -- Replica is destroyed - listener will not be connected
	end
	-- Getting listener table for replica class:
	local listeners = ChildListeners[self.Id]
	if listeners == nil then
		listeners = {}
		ChildListeners[self.Id] = listeners
	end
	table.insert(listeners, listener)
	-- ScriptConnection which allows the disconnection of the listener:
	return Madwork.NewArrayScriptConnection(listeners, listener)
end

function Replica:FindFirstChildOfClass(replica_class) --> [Replica] or nil
	for _, child in ipairs(self.Children) do
		if child.Class == replica_class then
			return child
		end
	end
	return nil
end

-- Debug:
function Replica:Identify() --> [string]
	local tag_string = ""
	local first_tag = true
	for tag_key, tag_val in pairs(self.Tags) do
		tag_string = tag_string .. (first_tag and "" or ";") .. tostring(tag_key) .. "=" .. tostring(tag_val)
	end
	return "[Id:" .. tostring(self.Id) .. ";Class:" .. self.Class .. ";Tags:{" .. tag_string .. "}]"
end

-- Cleanup:

function Replica:IsActive() --> is_active [bool]
	return Replicas[self.Id] ~= nil
end

function Replica:AddCleanupTask(task)
	return self._maid:AddCleanupTask(task)
end

function Replica:RemoveCleanupTask(task)
	self._maid:RemoveCleanupTask(task)
end

-- Write function setters: (Calling outside a write function will throw an error)

function Replica:SetValue(path, value)
	if WriteFunctionFlag == false then
		error(SETTINGS.SetterError)
	end
	local path_array = (type(path) == "string") and StringPathToArray(path) or path
	ReplicaSetValue(self.Id, path_array, value)
end

function Replica:SetValues(path, values)
	if WriteFunctionFlag == false then
		error(SETTINGS.SetterError)
	end
	local path_array = (type(path) == "string") and StringPathToArray(path) or path
	ReplicaSetValues(self.Id, path_array, values)
end

function Replica:ArrayInsert(path, value) --> new_index
	if WriteFunctionFlag == false then
		error(SETTINGS.SetterError)
	end
	local path_array = (type(path) == "string") and StringPathToArray(path) or path
	return ReplicaArrayInsert(self.Id, path_array, value)
end

function Replica:ArraySet(path, index, value)
	if WriteFunctionFlag == false then
		error(SETTINGS.SetterError)
	end
	local path_array = (type(path) == "string") and StringPathToArray(path) or path
	ReplicaArraySet(self.Id, path_array, index, value)
end

function Replica:ArrayRemove(path, index) --> removed_value
	if WriteFunctionFlag == false then
		error(SETTINGS.SetterError)
	end
	local path_array = (type(path) == "string") and StringPathToArray(path) or path
	return ReplicaArrayRemove(self.Id, path_array, index)
end

function Replica:Write(function_name, ...) --> return_params...
	if WriteFunctionFlag == false then
		error(SETTINGS.SetterError)
	end
	local func_id = self._write_lib_dictionary[function_name]
	local return_params = table.pack(self._write_lib[func_id](self, ...))
	-- Signaling listeners:
	local listeners = self._function_listeners[func_id]
	if listeners ~= nil then
		for _, listener in ipairs(listeners) do
			listener(...)
		end
	end
	return table.unpack(return_params)
end

-- ReplicaController functions:

function ReplicaController.RequestData() -- Call after all client controllers are loaded and before CoreReadySignal is fired
	if DataRequestStarted == true then
		return
	end
	DataRequestStarted = true
	task.spawn(function() -- In case the initial rev_ReplicaRequestData signal was lost (Highly unlikely)
		while game:IsLoaded() == false do
			task.wait()
		end
		rev_ReplicaRequestData:FireServer()
		while task.wait(SETTINGS.RequestDataRepeat) do
			if ReplicaController.InitialDataReceived == true then
				break
			end
			rev_ReplicaRequestData:FireServer()
		end
	end)
end

function ReplicaController.ReplicaOfClassCreated(replica_class, listener) --> [ScriptConnection] listener(replica)
	if type(replica_class) ~= "string" then
		error("[ReplicaController]: replica_class must be a string")
	end
	if type(listener) ~= "function" then
		error("[ReplicaController]: Only a function can be set as listener in ReplicaController.ReplicaOfClassCreated()")
	end
	-- Getting listener table for replica class:
	local signal = ClassListeners[replica_class]
	if signal == nil then
		signal = Madwork.NewScriptSignal()
		ClassListeners[replica_class] = signal
	end
	return signal:Connect(listener, function()
		-- Cleanup script signals that are no longer used:
		if signal:GetListenerCount() == 0 and ClassListeners[replica_class] == signal then
			ClassListeners[replica_class] = nil
		end
	end)
end

function ReplicaController.GetReplicaById(replica_id)
	return Replicas[replica_id]
end

----- Connections -----

-- Fired from server after initial data is sent:
rev_ReplicaRequestData.OnClientEvent:Connect(function()
	ReplicaController.InitialDataReceived = true
	print("[ReplicaController]: Initial data received")
	ReplicaController.InitialDataReceivedSignal:Fire()
end)

-- Replica data changes:
rev_ReplicaSetValue.OnClientEvent:Connect(ReplicaSetValue) -- (replica_id, {path}, value)

rev_ReplicaSetValues.OnClientEvent:Connect(ReplicaSetValues) -- (replica_id, {path}, {values})

rev_ReplicaArrayInsert.OnClientEvent:Connect(ReplicaArrayInsert) -- (replica_id, {path}, value)

rev_ReplicaArraySet.OnClientEvent:Connect(ReplicaArraySet) -- (replica_id, {path}, index, value)

rev_ReplicaArrayRemove.OnClientEvent:Connect(ReplicaArrayRemove) -- (replica_id, {path}, index)

rev_ReplicaWrite.OnClientEvent:Connect(function(replica_id, func_id, ...) -- (replica_id, func_id, {params})
	local replica = Replicas[replica_id]
	-- Running function:
	WriteFunctionFlag = true
	replica._write_lib[func_id](replica, ...)
	WriteFunctionFlag = false
	-- Signaling listeners:
	local listeners = replica._function_listeners[func_id]
	if listeners ~= nil then
		for _, listener in ipairs(listeners) do
			listener(...)
		end
	end
end)

-- Replica signals:
rev_ReplicaSignal.OnClientEvent:Connect(function(replica_id, ...) -- (replica_id, params...)
	local replica = Replicas[replica_id]
	-- Signaling listeners:
	local listeners = replica._signal_listeners
	for _, listener in ipairs(listeners) do
		listener(...)
	end
end)

-- Inheritance:
rev_ReplicaSetParent.OnClientEvent:Connect(function(replica_id, parent_replica_id) -- (replica_id, parent_replica_id)
	local replica = Replicas[replica_id]
	local old_parent_children = replica.Parent.Children
	local new_parent = Replicas[parent_replica_id]
	table.remove(old_parent_children, table.find(old_parent_children, replica))
	table.insert(new_parent.Children, replica)
	replica.Parent = new_parent
	-- Trigger child added:
	local child_listener_table = ChildListeners[parent_replica_id]
	if child_listener_table ~= nil then
		for i = 1, #child_listener_table do
			child_listener_table[i](replica)
		end
	end
end)

-- Replica creation:
rev_ReplicaCreate.OnClientEvent:Connect(function(param1, param2) -- (top_replica_id, {replica_data}) OR (top_replica_id, {creation_data}) or ({replica_package})
	--[[
	param1 description:
		top_replica_id = replica_id
		OR
		replica_package = {{replica_id, creation_data}, ...}
	param2 description:
		replica_data = {replica_class, replica_tags, data_table, parent_id / 0, write_lib_module / nil}
		OR
		creation_data = {["replica_id"] = replica_data, ...}
	--]]
	local created_replicas = {}
	-- Unpacking replica data:
	if type(param1) == "table" then -- Replica package
		table.sort(param1, function(a, b) -- Sorting top level replicas by their id
			return a[1] < b[1]
		end)
		for _, replica_branch_entry in ipairs(param1) do
			CreateReplicaBranch(replica_branch_entry[2], created_replicas)
		end
	elseif param2[1] ~= nil then -- One replica data
		CreateReplicaBranch({[tostring(param1)] = param2}, created_replicas)
	else -- Creation data table
		CreateReplicaBranch(param2, created_replicas)
	end
	-- Broadcasting replica creation:
	table.sort(created_replicas, function(a, b)
		return a.Id < b.Id
	end)
	-- 1) Child added:
	for _, replica in ipairs(created_replicas) do
		local parent_replica = replica.Parent
		if parent_replica ~= nil then
			local child_listener_table = ChildListeners[parent_replica.Id]
			if child_listener_table ~= nil then
				for i = 1, #child_listener_table do
					child_listener_table[i](replica)
				end
			end
		end
	end
	-- 2) New Replica and Replica of class created:
	for _, replica in ipairs(created_replicas) do
		NewReplicaSignal:Fire(replica)
		local class_listener_signal = ClassListeners[replica.Class]
		if class_listener_signal ~= nil then
			class_listener_signal:Fire(replica)
		end
	end
end)

-- Replica destruction:
rev_ReplicaDestroy.OnClientEvent:Connect(function(replica_id) -- (replica_id)
	local replica = Replicas[replica_id]
	DestroyReplicaAndDescendantsRecursive(replica)
end)

return ReplicaController