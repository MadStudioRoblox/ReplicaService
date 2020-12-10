--[[
[Game]

-[ReplicaTestServer]---------------------------------------
	(ExperimentalListenersExample)
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

		Same as AbstractExample, but with Experimental.ReplicaServiceListeners
		being used.
	
--]]

local SETTINGS = {
	MessageUpdateTick = 5,
}

----- Module Table -----

local ReplicaTestServer = {

}

----- Loaded Modules -----

local ReplicaService = require(game:GetService("ServerScriptService"):FindFirstChild("ReplicaServiceListeners", true))

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

do
	
	local function GetAllMessages(messages)
		if next(messages) == nil then
			return "Empty!"
		else
			local result = ""
			for message_name, text in pairs(messages) do
				result ..= message_name .. " = \"" .. text .. "\""
					.. (next(messages, message_name) ~= nil and "; " or "")
			end
			return result
		end
	end
	
	local replica_one = TestReplicaOne
	
	local messages = replica_one.Data.Messages

	print("ReplicaOne and all it's children have been replicated!")
	print("Initially received state of all replicas:")
	print("  " .. replica_one.Class .. ": " .. GetAllMessages(messages))
	for _, child in ipairs(replica_one.Children) do
		local child_data = child.Data
		print("    " .. child.Class .. ": (Tags: " .. GetAllMessages(child.Tags)
			.. "); TestValue = " .. child_data.TestValue .. "; NestedValue = " .. child_data.TestTable.NestedValue)

		child:ListenToChange({"TestValue"}, function(new_value)
			print("[" .. child.Class .. "]: (Index: " .. child.Tags.Index .. ") TestValue changed to " .. tostring(new_value))
		end)
		child:ListenToChange({"TestTable", "NestedValue"}, function(new_value)
			print("[" .. child.Class .. "]: (Index: " .. child.Tags.Index .. ") NestedValue changed to " .. child_data.TestTable.NestedValue)
		end)
	end

	print("Printing updates...")

	replica_one:ListenToWrite("SetMessage", function(message_name, text)
		print("[" .. replica_one.Class .. "]: SetMessage - (" .. message_name .. " = \"" .. text .. "\") " .. GetAllMessages(messages))
	end)

	replica_one:ListenToWrite("SetAllMessages", function(text)
		print("[" .. replica_one.Class .. "]: SetAllMessages - " .. GetAllMessages(messages))
	end)

	replica_one:ListenToWrite("DestroyAllMessages", function()
		print("[" .. replica_one.Class .. "]: DestroyAllMessages - " .. GetAllMessages(messages))
	end)
	
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