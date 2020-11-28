--[[
[Game]

-[ReplicaTestServer]---------------------------------------
	(AbstractExample)
    Brief functionality test of ReplicaService; Server-side
    
	TO RUN THIS TEST:
		Parent:
			ReplicaTestServer -> ServerScriptService
			ReplicaTestClient -> StarterPlayerScripts
			TestWriteLib -> ReplicatedStorage
		(Only one test can be run at a time)

	What happens:
		Various data is randomly changed on the server and replicated to
		all players in the game.
	
--]]

local SETTINGS = {
	MessageUpdateTick = 5,
}

----- Module Table -----

local ReplicaTestServer = {

}

----- Loaded Modules -----

local ReplicaService = require(game:GetService("ServerScriptService").ReplicaService)

----- Private Variables -----

local RunService = game:GetService("RunService")

local LastTick = os.clock()

-- Assume TestReplicaOne is a list of messages we want to broadcast
local TestReplicaOne = ReplicaService.NewReplica({
	ClassToken = ReplicaService.NewClassToken("ReplicaOne"), -- Create the token in reference for singleton replicas
	Data = {
		Messages = {}, -- {[message_name] = text, ...}
	},
	Replication = "All",
	-- Using WaitForChild here to throw a warning if you accidentally forget to include it ;)
	-- Be aware that if you accidentally pass nil, the replica will be created without a WriteLib
	WriteLib = game:GetService("ReplicatedStorage"):WaitForChild("TestWriteLib"),
})

local InstantiatedClassToken = ReplicaService.NewClassToken("InstantiatedReplica")
local InstantiatedReplicas = {} -- {replica, ...}

----- Private functions -----

----- Public functions -----

----- Initialize -----

for i = 1, 3 do
	local replica = ReplicaService.NewReplica({
		ClassToken = InstantiatedClassToken,
		-- Optional params:
		Tags = {Index = i}, -- "Tags" is a static table that can't be changed during the lifespan of a replica;
		-- Use tags for identifying replicas with players (Tags = {Player = player}) or other parameters
		Data = {
			TestValue = 0,
			TestTable = {
				NestedValue = "-",
			},
		},
		Parent = TestReplicaOne,
	})
	InstantiatedReplicas[i] = replica
end

----- Connections -----

RunService.Heartbeat:Connect(function()
	if os.clock() - LastTick > SETTINGS.MessageUpdateTick then
		LastTick = os.clock()
		
		local lucky_letter = string.char(math.random(65, 90)) -- Random letter from A to Z
		
		if math.random(1, 2) == 1 then
			-- Do something with TestReplicaOne:
			local roll_the_dice = math.random(1, 10)
			if roll_the_dice <= 7 then
				TestReplicaOne:Write("SetMessage", lucky_letter, "Hello!")
			elseif roll_the_dice <= 9 then
				TestReplicaOne:Write("SetAllMessages", "Bye!")
			else
				TestReplicaOne:Write("DestroyAllMessages")
			end
		else
			-- Do something with InstantiatedReplicas:
			local random_replica = InstantiatedReplicas[math.random(1, #InstantiatedReplicas)]
			if math.random(1, 2) == 1 then
				random_replica:SetValue({"TestValue"}, math.random(1, 10))
			else
				random_replica:SetValue({"TestTable", "NestedValue"}, lucky_letter)
			end
		end
		
	end
end)