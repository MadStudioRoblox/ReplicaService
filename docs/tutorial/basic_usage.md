This might not be the most useful, but it's the most basic implementation you can write with ReplicaService:

(`Script` ReplicaTest.server.lua)
```lua
local ReplicaService = require(game.ServerScriptService.ReplicaService)

local test_replica = ReplicaService.NewReplica({
	ClassToken = ReplicaService.NewClassToken("TestReplica"),
	Data = {Value = 0},
	Replication = "All",
})

while task.wait(1) do
	test_replica:SetValue({"Value"}, test_replica.Data.Value + 1)
end
```

(`LocalScript` ReplicaTest.client.lua)
```lua
local ReplicaController = require(game.ReplicatedStorage.ReplicaController)

ReplicaController.ReplicaOfClassCreated("TestReplica", function(replica)
	print("TestReplica received! Value:", replica.Data.Value)
	
	replica:ListenToChange({"Value"}, function(new_value)
		print("Value changed:", new_value)
	end)
end)

ReplicaController.RequestData() -- This function should only be called once
--   in the entire codebase! Read the documentation for more info.
```