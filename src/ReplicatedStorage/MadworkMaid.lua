--[[
{Madwork}

-[MadworkMaid]---------------------------------------
	Madwork implementation of Maid.lua
	
	Functions:
	
		MadworkMaid.NewMaid() --> [Maid]
		MadworkMaid.Cleanup(task, params...)
	
	Members [Maid]:
	
		Maid:AddCleanupTask(task)
		Maid:RemoveCleanupTask(task)
		Maid:Cleanup(params...)
		
	Notice: "params..." argument is optional and can be used to pass arguments to cleanup functions
	
--]]

----- Module Table -----

local MadworkMaid = {
	
}

----- Private functions -----

local function PerformCleanupTask(task, ...)
	if type(task) == "function" then
		task(...)
	elseif typeof(task) == "RBXScriptConnection" then
		task:Disconnect()
	elseif typeof(task) == "Instance" then
		task:Destroy()
	elseif type(task) == "table" then
		if type(task.Destroy) == "function" then
			task:Destroy()
		elseif type(task.Disconnect) == "function" then
			task:Disconnect()
		end
	end
end

----- Public functions -----

-- Maid object:

local Maid = {
	-- _cleanup_tasks = {},
	-- _is_cleaned = false,
}
Maid.__index = Maid

function Maid:AddCleanupTask(task)
	if self._is_cleaned == true then
		PerformCleanupTask(task)
	end
	if type(task) == "function" then
		table.insert(self._cleanup_tasks, task)
	elseif typeof(task) == "RBXScriptConnection" then
		table.insert(self._cleanup_tasks, task)
	elseif typeof(task) == "Instance" then
		table.insert(self._cleanup_tasks, task)
	elseif type(task) == "table" then
		if type(task.Destroy) == "function" then
			table.insert(self._cleanup_tasks, task)
		elseif type(task.Disconnect) == "function" then
			table.insert(self._cleanup_tasks, task)
		else
			error("[MadworkMaid]: Received object table as cleanup task, but couldn't detect a :Destroy() method")
		end
	else
		error("[MadworkMaid]: Cleanup task of type \"" .. typeof(task) .. "\" not supported")
	end
end

function Maid:RemoveCleanupTask(task)
	local cleanup_tasks = self._cleanup_tasks
	for i = 1, #cleanup_tasks do
		if cleanup_tasks[i] == task then
			table.remove(cleanup_tasks, i)
			break
		end
	end
end

function Maid:Cleanup(...)
	for _, task in ipairs(self._cleanup_tasks) do
		PerformCleanupTask(task, ...)
	end
	self._cleanup_tasks = {}
	self._is_cleaned = true
end

-- New maid object:

function MadworkMaid.NewMaid() --> [Maid]
	local maid = {
		_cleanup_tasks = {},
		_is_cleaned = false,
	}
	setmetatable(maid, Maid)
	return maid
end

MadworkMaid.Cleanup = PerformCleanupTask

return MadworkMaid