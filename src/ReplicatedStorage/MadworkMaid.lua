--[[
{Madwork}

-[MadworkMaid]---------------------------------------
	Madwork implementation of Maid.lua
	
	Functions:
	
		MadworkMaid.NewMaid() --> [Maid]
		MadworkMaid.Cleanup(task, params...)
	
	Members [Maid]:
	
		Maid:AddCleanupTask(task) --> cleanup_of_one [function] (...) -- Returned function can be called to cleanup the individual task
		Maid:RemoveCleanupTask(task)
		Maid:Cleanup(params...)
		
	Notice: "params..." argument is optional and can be used to pass arguments to cleanup functions
	
--]]

----- Module Table -----

local MadworkMaid = {
	
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

local function CleanupTask(task, ...)
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

local function PerformCleanupTask(...)
	if not FreeRunnerThread then
		FreeRunnerThread = coroutine.create(RunEventHandlerInFreeThread)
	end
	task.spawn(FreeRunnerThread, CleanupTask, ...)
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
		return function() end
	elseif type(task) == "function" then
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
	return function(...)
		self:RemoveCleanupTask(task)
		PerformCleanupTask(task, ...)
	end
end

function Maid:RemoveCleanupTask(task)
	local cleanup_tasks = self._cleanup_tasks
	local index = table.find(cleanup_tasks, task)
	if index ~= nil then
		table.remove(cleanup_tasks, index)
	end
end

function Maid:CleanupOfOne(task, ...)
	self:RemoveCleanupTask(task)
	PerformCleanupTask(task, ...)
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