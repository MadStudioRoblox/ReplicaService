--[[
[Game]

-[ReplicaTestServer]---------------------------------------
	(ProfileServiceExample)
    Brief functionality test of ReplicaService; Server-side
    
	TO RUN THIS TEST:
		Setup ProfileService: https://madstudioroblox.github.io/ProfileService/tutorial/settingup/
		Parent:
			ReplicaTestServer -> ServerScriptService
			ReplicaTestClient -> StarterPlayerScripts
			TestWriteLib -> ReplicatedStorage
		(Only one test can be run at a time)

	What happens: 
		All players will receive a payout every 3 seconds. Cash is saved
		to the DataStore with ProfileService. We're going to replicate
		the cash state of individual players to everyone.
	
--]]

local SETTINGS = {
	ProfileTemplate = {
		Cash = 0,
	}
}

----- Module Table -----

local ReplicaTestServer = {

}

----- Loaded Modules -----

local ReplicaService = require(game:GetService("ServerScriptService").ReplicaService)
local ProfileService = require(game:GetService("ServerScriptService").ProfileService)

----- Private Variables -----

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local PlayerProfileClassToken = ReplicaService.NewClassToken("PlayerProfile")

local GameProfileStore = ProfileService.GetProfileStore(
	"PlayerData",
	SETTINGS.ProfileTemplate
)

local PlayerProfile -- PlayerProfile object
local PlayerProfiles = {} -- [player] = {Profile = profile, Replica = replica}

local LastPayout = os.clock()

----- Private functions -----

local function PlayerAdded(player)
    local profile = GameProfileStore:LoadProfileAsync(
        "Player_" .. player.UserId,
        "ForceLoad"
    )
    if profile ~= nil then
		profile:AddUserId(player.UserId)
        profile:Reconcile()
		profile:ListenToRelease(function()
			PlayerProfiles[player].Replica:Destroy()
            PlayerProfiles[player] = nil
            player:Kick()
        end)
		if player:IsDescendantOf(Players) == true then
			local player_profile = {
				Profile = profile,
				Replica = ReplicaService.NewReplica({
					ClassToken = PlayerProfileClassToken,
					Tags = {Player = player},
					Data = profile.Data,
					Replication = "All",
				}),
				_player = player,
			}
			setmetatable(player_profile, PlayerProfile)
            PlayerProfiles[player] = player_profile
        else
            profile:Release()
        end
    else
        player:Kick() 
    end
end

----- Public functions -----

-- PlayerProfile object:
PlayerProfile = {
	--[[
		_player = player,
	--]]
}
PlayerProfile.__index = PlayerProfile

function PlayerProfile:GiveCash(cash_amount)
	if self:IsActive() == false then
		return
	end
	self.Replica:SetValue({"Cash"}, self.Replica.Data.Cash + cash_amount)
end

function PlayerProfile:IsActive() --> is_active
	return PlayerProfiles[self._player] ~= nil
end

----- Initialize -----

for _, player in ipairs(Players:GetPlayers()) do
    coroutine.wrap(PlayerAdded)(player)
end

----- Connections -----

RunService.Heartbeat:Connect(function()
	if os.clock() - LastPayout > 3 then
		LastPayout = os.clock()
		print("Payout!")
		for _, player_profile in pairs(PlayerProfiles) do
			player_profile:GiveCash(100)
		end
	end
end)

Players.PlayerAdded:Connect(PlayerAdded)

Players.PlayerRemoving:Connect(function(player)
    local player_profile = PlayerProfiles[player]
    if player_profile ~= nil then
        player_profile.Profile:Release()
    end
end)