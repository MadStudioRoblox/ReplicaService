--[[
[Game]

-[ReplicaTestClient]---------------------------------------
	(ProfileServiceExample)
	Brief functionality test of ReplicaService; Client-side

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

}

----- Module Table -----

local ReplicaTestClient = {

}

----- Loaded Modules -----

local ReplicaController = require(game:GetService("ReplicatedStorage"):WaitForChild("ReplicaController"))

----- Private Variables -----

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

----- Private functions -----

----- Public functions -----

----- Initialize -----

ReplicaController.RequestData()

----- Connections -----

ReplicaController.ReplicaOfClassCreated("PlayerProfile", function(replica)
	local is_local = replica.Tags.Player == LocalPlayer
	local player_name = is_local and "your" or replica.Tags.Player.Name .. "'s"
	local replica_data = replica.Data

	print("Received " .. player_name .. " player profile; Cash:", replica_data.Cash)
	replica:ListenToChange({"Cash"}, function(new_value)
		print(player_name .. " cash changed:", replica_data.Cash)
	end)
end)