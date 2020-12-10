--[[
[Game]

-[ReplicaTestClient]---------------------------------------
	(ExperimentalListenersExample)
	Brief functionality test of ReplicaService; Client-side

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

}

----- Module Table -----

local ReplicaTestClient = {

}

----- Loaded Modules -----

local ReplicaController = require(game:GetService("ReplicatedStorage"):WaitForChild("ReplicaController"))

----- Private Variables -----

----- Private functions -----

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

----- Public functions -----

----- Initialize -----

ReplicaController.RequestData()

----- Connections -----

ReplicaController.ReplicaOfClassCreated("ReplicaOne", function(replica_one)
	
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
	
end)