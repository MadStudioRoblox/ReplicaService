--[[
{Madwork}

-[RateLimiter]---------------------------------------
	Prevents RemoteEvent spamming; Player references are automatically removed as they leave
	
	Members:
	
		RateLimiter.Default   [RateLimiter]
	
	Functions:
	
		RateLimiter.NewRateLimiter(rate) --> [RateLimiter]
			rate   [number] -- Events per second allowed; Excessive events are dropped
			
	Methods [RateLimiter]:
	
		RateLimiter:CheckRate(source) --> is_to_be_processed [bool] -- Whether event should be processed
			source   [any]
			
		RateLimiter:CleanSource(source) -- Forgets about the source - must be called for any object that
			has been passed to RateLimiter:CheckRate() after that object is no longer going to be used;
			Does not have to be called for Player instances!
			
		RateLimiter:Cleanup() -- Forgets all sources
		
		RateLimiter:Destroy() -- Make the RateLimiter module forget about this RateLimiter object
	
--]]

local SETTINGS = {
	DefaultRateLimiterRate = 120,
}

----- Service Table -----

local RateLimiter = {
	Default = nil,
}

----- Private Variables -----

local Players = game:GetService("Players")

local PlayerReference = {} -- {player = true}
local RateLimiters = {} -- {rate_limiter = true, ...}

----- Public functions -----

-- RateLimiter object:
local RateLimiterObject = {
	--[[
		_sources = {},
		_rate_period = 0,
	--]]
}
RateLimiterObject.__index = RateLimiterObject

function RateLimiterObject:CheckRate(source) --> is_to_be_processed [bool] -- Whether event should be processed
	local sources = self._sources
	local os_clock = os.clock()
	
	local rate_time = sources[source]
	if rate_time ~= nil then
		rate_time = math.max(os_clock, rate_time + self._rate_period)
		if rate_time - os_clock < 1 then
			sources[source] = rate_time
			return true
		else
			return false
		end
	else
		-- Preventing from remembering players that already left:
		if typeof(source) == "Instance" and source:IsA("Player")
			and PlayerReference[source] == nil then
			return false
		end
		sources[source] = os_clock + self._rate_period
		return true
	end
end

function RateLimiterObject:CleanSource(source) -- Forgets about the source - must be called for any object that
	self._sources[source] = nil
end

function RateLimiterObject:Cleanup() -- Forgets all sources
	self._sources = {}
end

function RateLimiterObject:Destroy() -- Make the RateLimiter module forget about this RateLimiter object
	RateLimiters[self] = nil
end

-- Module functions:
function RateLimiter.NewRateLimiter(rate) --> [RateLimiter]
	if rate <= 0 then
		error("[RateLimiter]: Invalid rate")
	end
	
	local rate_limiter = {
		_sources = {},
		_rate_period = 1 / rate,
	}
	setmetatable(rate_limiter, RateLimiterObject)
	
	RateLimiters[rate_limiter] = true
	
	return rate_limiter
end

----- Initialize -----

for _, player in ipairs(Players:GetPlayers()) do
	PlayerReference[player] = true
end

RateLimiter.Default = RateLimiter.NewRateLimiter(SETTINGS.DefaultRateLimiterRate)

----- Connections -----

Players.PlayerAdded:Connect(function(player)
	PlayerReference[player] = true
end)

Players.PlayerRemoving:Connect(function(player)
	PlayerReference[player] = nil
	-- Automatic player reference cleanup:
	for rate_limiter in pairs(RateLimiters) do
		rate_limiter._sources[player] = nil
	end
end)

return RateLimiter