-- local Madwork = _G.Madwork
--[[
{Madwork}

-[ReplicaService]---------------------------------------
	(STANDALONE VERSION)
	Lua table replication achieved through write function wrapping
	
	Understanding ReplicaService requires in-depth knowledge of RemoteEvent API:
	https://developer.roblox.com/en-us/articles/Remote-Functions-and-Events
	
	WARNINGS FOR "Replica.Data" VALUES:
		! Do not create numeric tables with gaps - attempting to replicate such tables will result in an error;
		     For UserId references, convert UserIds to strings for use as keys!
		! Do not create mixed tables (some values indexed by number and others by string key), as only
		     the data indexed by number will be replicated.
		! Do not index tables by anything other than numbers and strings.
		! Do not reference functions
		! Do not reference instances that are not replicated to clients 
		+ All types of userdata (Vector3, Color3, CFrame...) and Instances that are currently replicated
		to the client will replicate through ReplicaService.
	
	Members:
	
		ReplicaService.ActivePlayers               [table] {Player = true, ...} Players that have finished a handshake with ReplicaService
		ReplicaService.NewActivePlayerSignal       [ScriptSignal] (player)
		ReplicaService.RemovedActivePlayerSignal   [ScriptSignal] (player)
		
		ReplicaService.Temporary                   [Replica] -- Non replicated replica for nested replica creation
		
		ReplicaService.PlayerRequestedData         [ScriptSignal] (player) -- Fired at the moment of player requesting data, before
			-- replicating any replicas
	
	Functions:
	
		ReplicaService.NewClassToken(class_name) --> [ReplicaClassToken]
			-- Class tokens prevent the developer from creating replica class name collisions
	
		ReplicaService.NewReplica(replica_params) --> [Replica]
			replica_params   [table]:
				{
					ClassToken = replica_class_token, -- Primary replica identifier
					-- Optional params:
					Tags = {}, -- Secondary replica identifiers: {["tag_name"] = tag_value, ...}
					Data = {}, -- Table to be replicated (Data is not deep copied - retains reference)
					Replication = "All" or {[Player] = true, ...} or [Player], -- "Replication" and "Parent" are mutually exclusive
					Parent = replica, -- If Parent is not provided, created Replica will be a top-level Replica
					WriteLib = write_lib_module,
				}
				-- "Tags" and "Data" will default to empty tables;
				-- "Replication" defaults to not replicated;
				
			write_lib_module   [ModuleScript] -- A shared write function library (ModuleScript Instance must be
				replicated to clients); Create replicas with an assigned write_lib when network resources are limited.
				Functions within write_lib receive numeric indexes and the functions themselves change the replica
				data table through given parameters - this removes the need to send clients the "path" for data
				updates thus greatly compressing packet size.
				
		ReplicaService.CheckWriteLib(module_script) -- Run-time error check
			module_script   [ModuleScript] or nil -- nil will not error
				
	Members [ReplicaClassToken]:
	
		ReplicaClassToken.Class   [string]
				
	Members [Replica]:
	
		Replica.Data       [table] (Read only) Table which is replicated
		
		Replica.Id         [number] Unique identifier
		Replica.Class      [string] Primary Replica identifier
		Replica.Tags       [table] Secondary Replica identifiers
		
		Replica.Parent     [Replica] or nil
		Replica.Children   [table]: {replica, ...}
		
	Methods [Replica]:
		
	-- Dictionaries:
		Replica:SetValue(path, value) -- !!! Avoid numeric tables with gaps
		Replica:SetValues(path, values)  -- values = {key = value, ...} !!! Avoid numeric tables with gaps
		
	-- (Numeric) Arrays:
		Replica:ArrayInsert(path, value) --> new_index -- Performs table.insert(path, value)
		Replica:ArraySet(path, index, value) -- Can only set to an already existing index within the array
		Replica:ArrayRemove(path, index) --> removed_value -- Performs table.remove(path, index)
		
			path:
				[string] = "TableMember.TableMember" -- Roblox-style path
				[table] = {"Players", 2312310, "Health"} -- Key array path (Just use this always lol - string parsing is slow)
			
	-- Write library:
		Replica:Write(function_name, params...) --> return_params... -- Run write function with given parameters
			on server and client-side; (For replicas constructed with write_lib)
		
	-- Signals:
		Replica:ConnectOnServerEvent(listener)  --> [ScriptConnection] (player, params...) -- listener functions can't yield
		Replica:FireClient(player, params...) -- Fire a signal to client-side listeners for this specific Replica
		Replica:FireAllClients(params...)
		
	-- Inheritance: (Only for descendant replicas; Can't create circular inheritance)
		Replica:SetParent(replica)
		
	-- Replication: (Only for top level replicas - child replicas inherit replication settings)
		Replica:ReplicateFor("All")
		Replica:ReplicateFor(player)
		Replica:DestroyFor("All")
		Replica:DestroyFor(player) -- WARNING: Don't selectively destroy for clients when replica is replicated to all;
			You may only selectively destroy for clients if the replica was selectively replicated to clients
			
	-- Debug:
		Replica:Identify() --> [string]
		
	-- Cleanup:
	
		Replica:IsActive() --> is_active [bool] -- Returns false if the replica was destroyed
	
		Replica:AddCleanupTask(task) -- Add cleanup task to be performed
		Replica:RemoveCleanupTask(task) -- Remove cleanup task
		
		Replica:Destroy() -- Destroys replica and all of its descendants (Depth-first)
		
			task:
				[function] -- Function to be invoked when the Replica is destroyed (function can't yield)
				[RBXScriptConnection] -- Roblox script connection to be :Disconnect()'ed when the Replica is destroyed
				[Object] -- Object with a :Destroy() method to be destroyed when the Replica is destroyed (destruction method can't yield)
		
--]]

local SETTINGS = {

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

----- Service Table -----

local ReplicaService = {

	ActivePlayers = {}, -- {Player = true, ...}
	NewActivePlayerSignal = Madwork.NewScriptSignal(), -- (player)
	RemovedActivePlayerSignal = Madwork.NewScriptSignal(), -- (player)
	
	PlayerRequestedData = Madwork.NewScriptSignal(), -- (player)

	_replicas = {
		--[[
			[replica_id] = {
				Data = {}, -- [table] Replicated Replica data table
				Id = 1 -- [integer] (Read-only) Replica id
				Class = "", -- [string] Primary Replica identifier
				Tags = {PlayerId = 2312310}, -- [table] Secondary Replica identifiers
				
				Parent = Replica, -- [Replica / nil] -- Child replicas inherit replication settings
				Children = {}, -- [table] {replica, ...}
				
				_creation_data = {["replica_id"] = {replica_class, replica_tags, data_table, parent_id / 0, write_lib_module / nil}, ...},
					-- [table] A prepared table of all data a client will receive to construct this Replica and all it's descendants client-side
					-- (Reference to top ancestor _creation_data table if child replica)

				_replication = {}, -- [table] Selective replication settings (Reference to top ancestor _replication table if child replica)
					-- Possible settings:
						-- _replication = {["All"] = true} -- Replica will be replicated to all players
						-- _replication = {Player = true, ...} -- Replica will be replicated to selected players
						-- _replication = {} -- Replica is currently not replicated to anyone
				_pending_replication = {}, -- [table] Selective replication to players who are not fully loaded in
						
				_write_lib = {["function_name"] = {func_id, function}, ...} / nil, -- [table] List of wrapped write functions
				
				_signal_listeners = {},
				_maid = maid,
			},
			...
		--]]
	},

	_top_level_replicas = { -- References to top level replicas for decreased load when handling new and leaving players
		--[[
			[replica_id] = Replica, -- [Replica]
			...
		--]]
	},

	_replica_class = nil, -- Injection hook

}

----- Loaded Services & Modules -----

local RateLimiter = require(Madwork.GetShared("Madwork", "RateLimiter"))
local MadworkMaid = require(Madwork.GetShared("Madwork", "MadworkMaid"))

----- Private Variables -----

local DefaultRateLimiter = RateLimiter.Default

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ActivePlayers = ReplicaService.ActivePlayers
local Replicas = ReplicaService._replicas
local TopLevelReplicas = ReplicaService._top_level_replicas

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

local ReplicaIndex = 0

local LoadedWriteLibs = {} -- {[ModuleScript] = {["function_name"] = {func_id, function}, ...}, ...}

local WriteFunctionFlag = false

local CreatedClassTokens = {} -- [class_name] = true

local LockReplicaMethods = {} -- A metatable to be set for destroyed replicas
LockReplicaMethods.__index = LockReplicaMethods

----- Private functions -----

local function ParseReplicaBranch(replica, func) -- func(replica)
	func(replica)
	for _, child in ipairs(replica.Children) do
		ParseReplicaBranch(child, func)
		func(child)
	end
end

local function GetWriteLibFunctionsRecursive(list_table, pointer, name_stack)
	for key, value in pairs(pointer) do
		if type(value) == "table" then
			GetWriteLibFunctionsRecursive(list_table, value, name_stack .. key .. ".")
		elseif type(value) == "function" then
			table.insert(list_table, {name_stack .. key, value})
		else
			error("[ReplicaService]: Invalid write function value \"" .. tostring(value) .. "\" (" .. typeof(value) .. "); name_stack = \"" .. name_stack .. "\"")
		end
	end
end

local function LoadWriteLib(write_lib_module)
	local get_write_lib = LoadedWriteLibs[write_lib_module]
	if get_write_lib ~= nil then
		return get_write_lib -- Write lib module was previously loaded
	end

	if write_lib_module.ClassName ~= "ModuleScript" then
		error("[ReplicaService]: Invalid write_lib_module argument")
	end

	if write_lib_module:IsDescendantOf(ReplicatedStorage) == false then
		local found_in_shared = false
		for _, dir in pairs(Madwork.Shared) do
			if write_lib_module:IsDescendantOf(dir) == true then
				found_in_shared = true
				break
			end
		end
		if found_in_shared == false then
			error("[ReplicaService]: Write library module must be a descendant of ReplicatedStorage or \"Shared\" directory")
		end
	end

	local write_lib_raw = require(write_lib_module)
	if type(write_lib_raw) ~= "table" then
		error("[ReplicaService]: A write library ModuleScript must return a table")
	end

	local function_list = {} -- func_id = {func_name, func}

	GetWriteLibFunctionsRecursive(function_list, write_lib_raw, "")
	table.sort(function_list, function(item1, item2)
		return item1[1] < item2[1] -- Sort functions by their names - this creates a consistent indexing on server and client-side
	end)

	local write_lib = {} -- {["function_name"] = {func_id, function}, ...}

	for func_id, func_params in ipairs(function_list) do
		write_lib[func_params[1]] = {func_id, func_params[2]}
	end

	LoadedWriteLibs[write_lib_module] = write_lib

	return write_lib
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
	-- Remove _creation_data entry:
	replica._creation_data[tostring(id)] = nil
	-- Clear from children table of top parent replica:
	if not_first_in_stack ~= true then -- ehhhh... Yeah.
		if replica.Parent ~= nil then
			local children = replica.Parent.Children
			table.remove(children, table.find(children, replica))
		else
			TopLevelReplicas[id] = nil
		end
	end
	-- Swap metatables:
	setmetatable(replica, LockReplicaMethods)
end

----- Public functions -----

-- Replica object:

local Replica = {}
Replica.__index = Replica
ReplicaService._replica_class = Replica

-- Dictionaries:
function Replica:SetValue(path, value)
	local path_array = (type(path) == "string") and StringPathToArray(path) or path
	-- Apply change server-side:
	local pointer = self.Data
	for i = 1, #path_array - 1 do
		pointer = pointer[path_array[i]]
	end
	pointer[path_array[#path_array]] = value
	-- Replicate change:
	if WriteFunctionFlag == false then
		local id = self.Id
		if self._replication["All"] == true then
			for player in pairs(ActivePlayers) do
				rev_ReplicaSetValue:FireClient(player, id, path_array, value)
			end
		else
			for player in pairs(self._replication) do
				rev_ReplicaSetValue:FireClient(player, id, path_array, value)
			end
		end
	end
end

function Replica:SetValues(path, values)
	local path_array = (type(path) == "string") and StringPathToArray(path) or path
	-- Apply change server-side:
	local pointer = self.Data
	for i = 1, #path_array do
		pointer = pointer[path_array[i]]
	end
	for key, value in pairs(values) do
		pointer[key] = value
	end
	-- Replicate change:
	if WriteFunctionFlag == false then
		local id = self.Id
		if self._replication["All"] == true then
			for player in pairs(ActivePlayers) do
				rev_ReplicaSetValues:FireClient(player, id, path_array, values)
			end
		else
			for player in pairs(self._replication) do
				rev_ReplicaSetValues:FireClient(player, id, path_array, values)
			end
		end
	end
end

-- (Numeric) Arrays:
function Replica:ArrayInsert(path, value) --> new_index
	local path_array = (type(path) == "string") and StringPathToArray(path) or path
	-- Apply change server-side:
	local pointer = self.Data
	for i = 1, #path_array do
		pointer = pointer[path_array[i]]
	end
	table.insert(pointer, value)
	-- Replicate change:
	if WriteFunctionFlag == false then
		local id = self.Id
		if self._replication["All"] == true then
			for player in pairs(ActivePlayers) do
				rev_ReplicaArrayInsert:FireClient(player, id, path_array, value)
			end
		else
			for player in pairs(self._replication) do
				rev_ReplicaArrayInsert:FireClient(player, id, path_array, value)
			end
		end
	end
	return #pointer
end

function Replica:ArraySet(path, index, value)
	local path_array = (type(path) == "string") and StringPathToArray(path) or path
	-- Apply change server-side:
	local pointer = self.Data
	for i = 1, #path_array do
		pointer = pointer[path_array[i]]
	end
	if pointer[index] ~= nil then
		pointer[index] = value
	else
		error("[ReplicaService]: Replica:ArraySet() can only be used for existing indexes")
	end
	-- Replicate change:
	if WriteFunctionFlag == false then
		local id = self.Id
		if self._replication["All"] == true then
			for player in pairs(ActivePlayers) do
				rev_ReplicaArraySet:FireClient(player, id, path_array, index, value)
			end
		else
			for player in pairs(self._replication) do
				rev_ReplicaArraySet:FireClient(player, id, path_array, index, value)
			end
		end
	end
end

function Replica:ArrayRemove(path, index) --> removed_value
	local path_array = (type(path) == "string") and StringPathToArray(path) or path
	-- Apply change server-side:
	local pointer = self.Data
	for i = 1, #path_array do
		pointer = pointer[path_array[i]]
	end
	local removed_value = table.remove(pointer, index)
	-- Replicate change:
	if WriteFunctionFlag == false then
		local id = self.Id
		if self._replication["All"] == true then
			for player in pairs(ActivePlayers) do
				rev_ReplicaArrayRemove:FireClient(player, id, path_array, index)
			end
		else
			for player in pairs(self._replication) do
				rev_ReplicaArrayRemove:FireClient(player, id, path_array, index)
			end
		end
	end
	return removed_value
end

-- Write library:
function Replica:Write(function_name, ...) --> return_params...
	if WriteFunctionFlag == true then -- Chained :Write()
		return self._write_lib[function_name][2](self, ...)
	end
	-- Apply change server-side:
	WriteFunctionFlag = true
	local return_params = table.pack(self._write_lib[function_name][2](self, ...))
	WriteFunctionFlag = false
	-- Replicate change:
	local id = self.Id
	local func_id = self._write_lib[function_name][1]
	if self._replication["All"] == true then
		for player in pairs(ActivePlayers) do
			rev_ReplicaWrite:FireClient(player, id, func_id, ...)
		end
	else
		for player in pairs(self._replication) do
			rev_ReplicaWrite:FireClient(player, id, func_id, ...)
		end
	end
	return table.unpack(return_params)
end

-- Signals:
function Replica:ConnectOnServerEvent(listener) --> [ScriptConnection]
	if type(listener) ~= "function" then
		error("[ReplicaService]: Only functions can be passed to Replica:ConnectOnServerEvent()")
	end
	table.insert(self._signal_listeners, listener)
	return Madwork.NewArrayScriptConnection(self._signal_listeners, listener)
end

function Replica:FireClient(player, ...)
	if (self._replication["All"] == true and ActivePlayers[player] == true)
		or self._replication[player] ~= nil then
		rev_ReplicaSignal:FireClient(player, self.Id, ...)
	end
end

function Replica:FireAllClients(...)
	local id = self.Id
	if self._replication["All"] == true then
		for player in pairs(ActivePlayers) do
			rev_ReplicaSignal:FireClient(player, id, ...)
		end
	else
		for player in pairs(self._replication) do
			rev_ReplicaSignal:FireClient(player, id, ...)
		end
	end
end

-- Inheritance:

function Replica:SetParent(new_parent)
	assert(type(new_parent) == "table", "[ReplicaService]: Invalid parent_replica")
	assert(new_parent._replication ~= nil, "[ReplicaService]: Invalid parent_replica")
	local circular_check = new_parent
	while circular_check ~= nil do
		circular_check = circular_check.Parent
		if circular_check == self then
			error("[ReplicaService]: Can't parent replica to it's descendant")
		end
	end
	local old_parent = self.Parent
	if old_parent == nil then
		error("[ReplicaService]: Can't change parent for top level replicas")
	end
	if new_parent == old_parent then
		return
	end
	local replica_id = self.Id
	self.Parent = new_parent
	table.remove(old_parent.Children, table.find(old_parent.Children, self))
	table.insert(new_parent.Children, self)
	local old_replication = old_parent._replication
	local new_replication = new_parent._replication
	if old_replication ~= new_replication then -- Top level ancestor changed:
		local old_creation_data = old_parent._creation_data
		local new_creation_data = new_parent._creation_data
		-- Create temporary creation data:
		local temporary_creation_data = {} -- [string_id] = creation_data_of_one
		ParseReplicaBranch(self, function(transfered_replica)
			local replica_id_string = tostring(transfered_replica.Id)
			temporary_creation_data[replica_id_string] = old_creation_data[replica_id_string]
			transfered_replica._replication = new_replication -- Swapping _replication reference for reparented replicas
		end)
		temporary_creation_data[tostring(replica_id)][4] = new_parent.Id
		-- Modify creation data for top replicas:
		for string_id, creation_data_of_one in pairs(temporary_creation_data) do
			old_creation_data[string_id] = nil
			new_creation_data[string_id] = creation_data_of_one
		end
		-- Inform clients about the change:
		-- 1) Clients who have this replica AND the new parent replica only need to know the new parent id
		local no_replication_check = ActivePlayers
		if new_replication.All ~= true then
			no_replication_check = new_replication
		elseif old_replication.All ~= true then
			no_replication_check = old_replication
		end
		for player in pairs(no_replication_check) do
			if (old_replication[player] == true or old_replication.All == true) and (new_replication[player] == true or new_replication.All == true) then
				rev_ReplicaSetParent:FireClient(player, replica_id, new_parent.Id)
			end
		end
		-- 2) Create for clients that have the new parent replica, but not the old parent replica
		local replicate_for_players = {}
		if old_replication.All ~= true then
			if new_replication.All ~= true then
				for player in pairs(new_replication) do
					if old_replication[player] ~= true then
						replicate_for_players[player] = true
					end
				end
			else
				for player in pairs(ActivePlayers) do
					if old_replication[player] ~= true then
						replicate_for_players[player] = true
					end
				end
			end
		end
		for player in pairs(replicate_for_players) do
			rev_ReplicaCreate:FireClient(player, replica_id, temporary_creation_data)
		end
		-- 3) Destroy for clients that do not have the new parent replica
		if new_replication.All ~= true then
			if old_replication.All ~= true then
				for player in pairs(old_replication) do
					if new_replication[player] ~= true then
						rev_ReplicaDestroy:FireClient(player, replica_id)
					end
				end
			else
				for player in pairs(ActivePlayers) do
					if new_replication[player] ~= true then
						rev_ReplicaDestroy:FireClient(player, replica_id)
					end
				end
			end
		end
	else -- Top level ancestor did not change:
		self._creation_data[tostring(replica_id)][4] = new_parent.Id
		if old_replication.All == true then
			for player in pairs(ActivePlayers) do
				rev_ReplicaSetParent:FireClient(player, replica_id, new_parent.Id)
			end
		else
			for player in pairs(old_replication) do
				rev_ReplicaSetParent:FireClient(player, replica_id, new_parent.Id)
			end
		end
	end
end

-- Replication:
function Replica:ReplicateFor(param)
	if self.Parent ~= nil then
		error("[ReplicaService]: Replica:ReplicateFor() can only be used for top level replicas")
	end
	if Replicas[self.Id] == nil then
		error("[ReplicaService]: Can't change replication settings for a destroyed replica")
	end

	local replication = self._replication
	local pending_replication = self._pending_replication
	if replication["All"] ~= true then
		if param == "All" then
			-- Create replica for clients who weren't replicated to yet:
			local id = self.Id
			for player in pairs(ActivePlayers) do
				if replication[player] == nil then
					rev_ReplicaCreate:FireClient(player, id, self._creation_data)
				end
			end
			-- Clear selective replication settings:
			for player in pairs(replication) do
				replication[player] = nil
			end
			for player in pairs(pending_replication) do
				pending_replication[player] = nil
			end
			-- Set replication to all:
			replication["All"] = true
		elseif ActivePlayers[param] == true then
			if replication[param] == nil then
				-- Create replica for client:
				replication[param] = true
				rev_ReplicaCreate:FireClient(param, self.Id, self._creation_data)
			end
		elseif typeof(param) == "Instance" then
			if param.ClassName ~= "Player" then
				error("[ReplicaService]: Invalid param argument")
			end
			pending_replication[param] = true
		end
	else
		if param ~= "All" then
			error("[ReplicaService]: Don't selectively replicate for clients when replica is replicated to All - :DestroyFor(\"All\") first")
		end
	end
end

function Replica:DestroyFor(param)
	if self.Parent ~= nil then
		error("[ReplicaService]: Replica:DestroyFor() can only be used for top level replicas")
	end
	if Replicas[self.Id] == nil then
		error("[ReplicaService]: Can't change replication settings for a destroyed replica")
	end

	local replication = self._replication
	if replication[param] ~= nil and ActivePlayers[param] == true then
		-- Destroy replica for client:
		replication[param] = nil
		rev_ReplicaDestroy:FireClient(param, self.Id)
	elseif param == "All" then
		local id = self.Id
		if replication["All"] == true then
			-- Destroy replica for all active clients:
			replication["All"] = nil
			for player in pairs(ActivePlayers) do
				rev_ReplicaDestroy:FireClient(player, id)
			end
		else
			-- Destroy replica for all clients who were replicated to:
			for player in pairs(replication) do
				replication[player] = nil
				rev_ReplicaDestroy:FireClient(player, id)
			end
		end
	elseif replication["All"] == true then -- Don't do this
		error("[ReplicaService]: Don't selectively destroy for clients when replica is replicated to All")
	elseif typeof(param) == "Instance" then
		if param.ClassName ~= "Player" then
			error("[ReplicaService]: Invalid param argument")
		end
		self._pending_replication[param] = nil
	end
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

function Replica:Destroy()
	-- Destroy replica for all clients who were replicated to:
	local id = self.Id
	if Replicas[id] == nil then
		return
	end
	if self._replication["All"] == true then
		for player in pairs(ActivePlayers) do
			rev_ReplicaDestroy:FireClient(player, id)
		end
	else
		for player in pairs(self._replication) do
			rev_ReplicaDestroy:FireClient(player, id)
		end
	end
	-- Recursive destruction
	DestroyReplicaAndDescendantsRecursive(self)
end

-- Module functions:

function ReplicaService.NewClassToken(class_name) --> [ReplicaClassToken]
	if type(class_name) ~= "string" then
		error("[ReplicaService]: class_name must be a string")
	end
	if CreatedClassTokens[class_name] == true then
		error("[ReplicaService]: Token for replica class \"" .. class_name .. "\" was already created")
	end
	CreatedClassTokens[class_name] = true
	return {
		Class = class_name
	}
end

function ReplicaService.NewReplica(replica_params) --> [Replica]
	local class_token = replica_params.ClassToken
	local replica_tags = replica_params.Tags or {}
	local data_table = replica_params.Data or {}

	local replication_settings = replica_params.Replication

	if type(class_token) ~= "table" or type(class_token.Class) ~= "string" then
		error("[ReplicaService]: missing or invalid replica_params.ClassToken argument")
	end
	if type(replica_tags) ~= "table" then
		error("[ReplicaService]: replica_params.Tags must be a table")
	end
	if type(data_table) ~= "table" then
		error("[ReplicaService]: replica_params.Data must be a table")
	end

	local replica_class = class_token.Class

	ReplicaIndex = ReplicaIndex + 1

	local parent = replica_params.Parent
	local replication
	local pending_replication
	local creation_data

	if parent ~= nil then
		if Replicas[parent.Id] == nil then
			error("[ReplicaService]: Passed replica_params.Parent replica is destroyed")
		end
	end

	if parent ~= nil and replication_settings ~= nil then
		error("[ReplicaService]: Can't set replica_params.Replication for a replica that has a parent")
	elseif replication_settings == nil then
		replication = {}
		pending_replication = {}
	else
		-- Parsing replica_params.Replication:
		if type(replication_settings) == "table" then -- Must be a player list {player = true, ...} OR an empty table {}
			if replication_settings["All"] ~= nil then
				error("[ReplicaService]: To replicate replica to all, do replica_params.Replication = \"All\"")
			end
			replication = {}
			pending_replication = {}
			for player in pairs(replication_settings) do
				if typeof(player) ~= "Instance" or player.ClassName ~= "Player" then
					error("[ReplicaService]: Invalid replica_params.Replication")
				end
				if ActivePlayers[player] == true then
					replication[player] = true
				else
					pending_replication[player] = true
				end
			end
		elseif replication_settings == "All" then
			replication = {["All"] = true}
			pending_replication = {}
		elseif typeof(replication_settings) == "Instance" then -- Must be a player
			if replication_settings.ClassName == "Player" then
				if ActivePlayers[replication_settings] == true then
					replication = {[replication_settings] = true}
					pending_replication = {}
				else
					replication = {}
					pending_replication = {[replication_settings] = true}
				end
			else
				error("[ReplicaService]: Invalid value for param1")
			end
		else
			error("[ReplicaService]: Invalid value for replica_params.Replication (" .. tostring(replication_settings) .. ")")
		end
	end

	-- Load write_lib_module if present:
	local write_lib = nil
	if replica_params.WriteLib ~= nil then
		write_lib = LoadWriteLib(replica_params.WriteLib)
	end

	-- Getting references to parent replication and creation data:
	if parent ~= nil then
		replication = parent._replication
		pending_replication = parent._pending_replication
		creation_data = parent._creation_data
	else
		creation_data = {}
	end

	local creation_data_of_one = {replica_class, replica_tags, data_table, (parent ~= nil) and parent.Id or 0, replica_params.WriteLib}
	creation_data[tostring(ReplicaIndex)] = creation_data_of_one

	-- New Replica object table:
	local replica = {
		Data = data_table,
		Id = ReplicaIndex,

		Class = replica_class,
		Tags = replica_tags,
		Parent = parent,
		Children = {},
		_creation_data = creation_data,
		_replication = replication,
		_pending_replication = pending_replication,

		_write_lib = write_lib,

		_signal_listeners = {},
		_maid = MadworkMaid.NewMaid(),
	}
	setmetatable(replica, Replica)

	if parent ~= nil then
		table.insert(parent.Children, replica)
	end

	-- Replicating new replica:
	if replication["All"] == true then
		for player in pairs(ActivePlayers) do
			rev_ReplicaCreate:FireClient(player, ReplicaIndex, creation_data_of_one)
		end
	else
		for player in pairs(replication) do
			rev_ReplicaCreate:FireClient(player, ReplicaIndex, creation_data_of_one)
		end
	end

	-- Adding replica to replica list:
	Replicas[ReplicaIndex] = replica
	if parent == nil then
		TopLevelReplicas[ReplicaIndex] = replica
	end

	return replica
end

function ReplicaService.CheckWriteLib(module_script)
	if module_script ~= nil then
		LoadWriteLib(module_script)
	end
end

----- Initialize -----

-- Creating LockReplicaMethods members:
do
	local keep_methods = {
		Identify = true,
		AddCleanupTask = true,
		RemoveCleanupTask = true,
		Destroy = true,
		IsActive = true,
	}
	for method_name, func in pairs(Replica) do
		if method_name ~= "__index" then
			if keep_methods[method_name] == true then
				LockReplicaMethods[method_name] = func
			else
				LockReplicaMethods[method_name] = function(self)
					error("[ReplicaService]: Tried to call method \"" .. method_name .. "\" for a destroyed replica; " .. self:Identify())
				end
			end
		end
	end
end

-- Temporary replica:
ReplicaService.Temporary = ReplicaService.NewReplica({
	ClassToken = ReplicaService.NewClassToken("Temporary"),
})

----- Connections -----

-- New player data replication:
rev_ReplicaRequestData.OnServerEvent:Connect(function(player)
	if ActivePlayers[player] ~= nil then
		return
	end
	
	-- Provide the client with first server time reference:
	ReplicaService.PlayerRequestedData:Fire(player)

	-- Move player from pending replication to active replication
	for replica_id, replica in pairs(TopLevelReplicas) do
		if replica._pending_replication[player] ~= nil then
			replica._pending_replication[player] = nil
			replica._replication[player] = true
		end
	end
	-- Make the client create all replicas that are initially replicated to the client;
	-- Pack up and send intially replicated replicas:
	local replica_package = {} -- {replica_id, creation_data}
	for replica_id, replica in pairs(TopLevelReplicas) do
		if replica._replication[player] ~= nil or replica._replication["All"] == true then
			table.insert(replica_package, {replica_id, replica._creation_data})
		end
	end
	rev_ReplicaCreate:FireClient(player, replica_package)
	-- Let the client know that all replica data has been sent:
	rev_ReplicaRequestData:FireClient(player)
	-- Set player to active:
	ActivePlayers[player] = true
	ReplicaService.NewActivePlayerSignal:Fire(player)
end)

-- Client-invoked replica signals:
rev_ReplicaSignal.OnServerEvent:Connect(function(player, replica_id, ...)
	-- Missing player prevention, spam prevention and exploit prevention:
	if ActivePlayers[player] == nil or DefaultRateLimiter:CheckRate(player) == false
		or type(replica_id) ~= "number" then
		return
	end

	local replica = Replicas[replica_id]
	if replica ~= nil then
		if replica._replication[player] ~= nil or replica._replication["All"] == true then
			local signal_listeners = replica._signal_listeners
			for i = 1, #signal_listeners do
				signal_listeners[i](player, ...)
			end
		end
	end
end)

-- Player leave handling:
Players.PlayerRemoving:Connect(function(player)
	-- Remove player from subscription settings:
	for _, replica in pairs(TopLevelReplicas) do
		replica._replication[player] = nil
		replica._pending_replication[player] = nil
	end
	-- Remove player from ready players list:
	ActivePlayers[player] = nil
	ReplicaService.RemovedActivePlayerSignal:Fire(player)
end)

return ReplicaService