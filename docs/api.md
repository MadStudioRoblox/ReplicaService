!!! warning
    [Parameter limitations (developer.roblox.com)](https://developer.roblox.com/en-us/articles/Remote-Functions-and-Events#non-replicated-instances)
    apply to `Replica.Tags`, `Replica.Data`, `Replica:FireClient()`, `Replica:FireAllClients()` and `Replica:FireServer()`

!!! error
    **DO NOT YIELD** (`wait()` or asynchronous tasks like `Instance:WaitForChild()`; Most methods / functions with `async` in their name) inside
    [write functions](#writelib) or [listener functions](#client-replicacontroller) connected via `Replica:ListenToWrite()`, `Replica:ListenToChange()`, etc.
    Yielding in these places will cause ReplicaService / ReplicaController to skip replication events and lose data synchronization.

!!! notice
    The `ReplicaController` and `ReplicaService` modules will yield on `require()` if the internally included modules are not found immediately

## Common types

**`path`** - A path defines a location of a value within a dictionary (arrays will work too).
[Built-in mutators](#built-in-mutators) use the path variable to make the server and the
client perform identical changes to their copy of the state.
```lua
-- Using [table] type paths is highly recommended - string type paths
--   will have a slightly bigger performance impact in large replica
--   implementations

path   [table] {"Currencies", "Coins"} -- Can use numeric indexes to
--   locate values in an array

path   [string] "Currencies.Coins" -- Use dots to separate multiple keys;
--   Will only work on string keys
```

**`function_name`** - Similar to `path`, locates a function within a [WriteLib](#writelib).
```lua
function_name   [string] "Currency.AddCoins" -- Use dots to separate multiple keys;
--   Functions and their categories may only have string keys

-- It's highly recommended to avoid using function categories and
--   keeping your WriteLib modules flat and short, dividing large
--   replicas into several, smaller replicas with fewer concerns
```

## Guarantees

ReplicaService and ReplicaController perform all tasks and fire all new replica signals one at
a time, one after another (sequential execution). Understanding the order of execution can help you
make more efficient decisions in solving your problems.

When a replica reference is received through `.NewReplicaSignal` or `.ReplicaOfClassCreated()`,
ReplicaController provides these guarantees:

-   Whenever any replica is received client-side, all descendants (all children & children of children)
      of that replica at the moment of replication (Parent set in `replica_params` or [:ReplicateFor()](#replicareplicatefor))
      will be accessible on the client-side!
-   When the client receives first data or receives selective replication of a top level replica,
			`.NewReplicaSignal` and `.ReplicaOfClassCreated()` will be fired for all replicas in the
      order they were created server-side from earliest to latest ([Replica.Id](#replicaid)
      reflects this order). E.g. Creating `"replica1"` and then `"replica2"` in this order
      server-side will make all clients create (and fire `.NewReplicaSignal` and `.ReplicaOfClassCreated()` for)
      these replicas in the exact order assuming they are replicated to all players or are descendants
      of the same top level replica at the moment of replication.

## ReplicaService
### ReplicaService.ActivePlayers
```lua
ReplicaService.ActivePlayers   [table] -- (read-only) {player = true, ...}
```
A reference of players that have received initial data - having received initial data means having access to
all replicas that are selectively replicated to that player.
### ReplicaService.NewActivePlayerSignal
```lua
ReplicaService.NewActivePlayerSignal   [ScriptSignal] (player)
```
A signal for new `ReplicaService.ActivePlayers` entries.
### ReplicaService.RemovedActivePlayerSignal
```lua
ReplicaService.RemovedActivePlayerSignal   [ScriptSignal] (player)
```
A signal for removed `ReplicaService.RemovedActivePlayerSignal` entries.
### ReplicaService.Temporary
```lua
ReplicaService.Temporary   [Replica]
```
A replica that is not replicated to any player and a "helper" for creating nested `Replica` objects
when immediate replication of individual nested replicas is not desirable.

***ReplicaService.Temporary Example:***

Server-side:
```lua
-- A valid use case is when it is desired for clients to receive a
--   replica structure with all children replicated together as
--   opposed to the client first receiving a parent creation signal
--   (with missing children at that moment) and child creation
--   signals coming in separately:

local UseTemporary = true -- Set to false to make the replicas be
--   replicated separately

local ContainerReplica = ReplicaService.NewReplica({
  ClassToken = ReplicaService.NewClassToken("SingletonContainerReplica"),
  Replication = "All",
})

local ReplicaClassToken1 = ReplicaService.NewClassToken("Class1")
local ReplicaClassToken2 = ReplicaService.NewClassToken("Class2")

local parent = ContainerReplica
if UseTemporary == true then
  parent = ReplicaService.Temporary
end

local nested_replica = ReplicaService.NewReplica({
  ClassToken = ReplicaClassToken1, -- "Class1"
  Parent = parent,
})
local child_replica = ReplicaService.NewReplica({
  ClassToken = ReplicaClassToken2, -- "Class2"
  Parent = nested_replica,
})

nested_replica:SetParent(ContainerReplica) -- Sets Parent to ContainerReplica
--   if it wasn't already parented to ContainerReplica
```

Client-side:
```lua
ReplicaController.ReplicaOfClassCreated("Class1", function(replica)
  print(#replica.Children) --> Will print 1 when UseTemporary is set to true
  --   or 0 when UseTemporary is set to false
  coroutine.wrap(function()
    wait()
    print(#replica.Children) --> Will always print 1 when UseTemporary
    --   is set to true and is very likely, but not guaranteed to
    --   print 1 when UseTemporary is set to false
  end)()
end)

ReplicaController.RequestData() -- Only using here for testing purposes
--   ReplicaController.RequestData() should only be called once in the
--   entire codebase!
```

### ReplicaService.NewClassToken()
```lua
ReplicaService.NewClassToken(class_name) --> [ReplicaClassToken]
```
Class tokens for a particular `class_name` can only be created once - this helps the developer avoid `Replica` class name collisions when merging codebases.
### ReplicaService.NewReplica()
```lua
ReplicaService.NewReplica(replica_params) --> [Replica]
  replica_params   [table]:
    {
      ClassToken = replica_class_token,
      -- Optional params (can be nil):
      Tags = {}, -- {TagName = tag_value, ...}
      Data = {}, -- Table to be replicated (Retains table reference)
      Replication = "All" or {[Player] = true, ...} or [Player],
      Parent = replica, -- [Replica]
      WriteLib = write_lib_module, -- [ModuleScript]
    }
```
Creates a replica and immediately replicates to select [active players](#replicaserviceactiveplayers) based on replication settings
of this `Replica` or the parent `Replica`.

-  **ClassToken** - Sets `Replica.Class` to the string provided in `ReplicaService.NewClassToken(class_name)`
-  **Tags** - (Default: `{}` empty table) A dictionary of identifiers. Use `Tags` to let the client know which
game objects the `Replica` belongs to: `Tags = {Part = part, Player = player, ...}`. Tags can't be changed after
the `Replica` is created.
-  **Data** - (Default: `{}` empty table) A table representing a state. Using `Profile.Data` from [ProfileService](https://madstudioroblox.github.io/ProfileService/)
is valid!
-  **Replication** - (Default: `{}` not replicated to anyone) Pass `"All"` to replicate to everyone in the game and everyone
who will join the game later. Pass `{Player = true, Player = true, ...}` dictionary or `Player` instance for selective
replication.
-  **Parent** - (Default: `nil`) Don't provide any value to create a **top level replica** - top level replicas can't
be parented to other replicas and force their replication settings to all descendant nested replicas. Providing a
parent creates a **nested replica** - nested replicas can be parented to any replica (except their own children),
but they can't have their own replication settings. Hence the `Replication` and `Parent` parameters are mutually
exclusive.
-  **WriteLib** - (Default: `nil`) Provide a `ModuleScript` (not the return of `require()`) to assign write functions
(mutator functions) to this replica. The `WriteLib` parameter is individual for every `Replica`.

## ReplicaController

### ReplicaController.InitialDataReceivedSignal
```lua
ReplicaController.InitialDataReceivedSignal   [ScriptSignal]()
```
Fired once after the client finishes receiving initial replica data from server.
### ReplicaController.InitialDataReceived
```lua
ReplicaController.InitialDataReceived   [bool]
```
Set to true after the client finishes receiving initial replica data from server.
### ReplicaController.ReplicaOfClassCreated()
```lua
ReplicaController.ReplicaOfClassCreated(replica_class, listener)
    --> [ScriptConnection] listener(replica)
```
Listens to creation of replicas client-side of a particular class.
```lua
ReplicaController.ReplicaOfClassCreated("Flower", function(replica)
    print("Flower replica created:", replica:Identify())
    print(replica.Class == "Flower") --> true
end)
```
This is the preferred method of grabbing references to all replicas clients-side.
### ReplicaController.NewReplicaSignal
```lua
ReplicaController.NewReplicaSignal   [ScriptSignal] (replica)
```
Fired every time a replica is created client-side.
```lua
ReplicaController.NewReplicaSignal:Connect(function(replica)
  print("Replica created:", replica:Identify())
end)
```
### ReplicaController.GetReplicaById()
```lua
ReplicaController.GetReplicaById(replica_id) --> [Replica] or nil
```
Returns a `Replica` that is loaded client-side with a `Replica.Id` that matches `replica_id`.
### ReplicaController.RequestData()
```lua
ReplicaController.RequestData()
```
Requests the server to start sending replica data.

**All `.NewReplicaSignal` and `.ReplicaOfClassCreated()` listeners**
**should be connected before calling `.RequestData()`! - refrain from connecting**
**listeners afterwards!**

If your game has local scripts that may run later during gameplay and they will need to interact with
replicas, you should create a centralized module that connects `Replica` creation listeners before `.RequestData()`
and provides those local scripts with the replica references they need.

## Replica

### Shared members

#### Replica.Data
```lua
Replica.Data   [table] -- (read-only)
```
Table representing the state wrapped by the `Replica`. Note that after wrapping a table with a `Replica` you
may no longer write directly to that table (doing so would potentially desynchronize state among clients and
in some cases even break code) - all changes must be applied through [mutators](#built-in-mutators).
```lua
local PlayerStatsReplicaClassToken = ReplicaService.NewClassToken("PlayerStats")

local player -- A Player instance
local data = {Coins = 100}
local replica = ReplicaService.NewReplica({
  ClassToken = PlayerStatsReplicaClassToken,
  Tags = {Player = player},
  Data = data, -- Replica does not create a deep copy!
  Replication = "All",
})

print(replica.Data == data) --> true
print(replica.Data.Coins) --> 100
replica:SetValue({"Coins"}, 420)
print(data.Coins, replica.Data.Coins) --> 420 420
```
#### Replica.Id
```lua
Replica.Id   [number] -- (read-only)
```
An identifier that is unique for every `Replica` within a Roblox game session.
#### Replica.Class
```lua
Replica.Class   [string] -- (read-only)
```
The `class_name` parameter that has been used for the [ReplicaClassToken](#replicaservicenewclasstoken) used
to create this `Replica`.
#### Replica.Tags
```lua
Replica.Tags   [table] -- (read-only)
```
A custom static `Replica` identifier mainly used for referencing affected game instances.
Only used for properties that will not change for the rest of the `Replica`'s lifespan.
```lua
local CharacterReplicaClassToken = ReplicaService.NewClassToken("Character")

local player -- A Player instance
local character -- A Model instance
local replica = ReplicaService.NewReplica({
  ClassToken = CharacterReplicaClassToken,
  Tags = {Player = player, Character = character, Appearance = "Ninja"},
  Replication = "All",
})
```
#### Replica.Parent
```lua
Replica.Parent   [Replica] or nil -- (read-only)
```
Reference to the parent `Replica`. All **nested replicas** *will* have a parent. All **top level replicas** will have their `Parent` property set to `nil`.
**nested replicas** will never become **top level replicas** and vice versa.
#### Replica.Children
```lua
Replica.Children   [table] -- (read-only) {replica, ...} 
```
An array of replicas parented to this `Replica`.
#### Replica:IsActive()
```lua
Replica:IsActive() --> is_active [bool]
```
Returns `false` if the `Replica` was destroyed.
#### Replica:Identify()
```lua
Replica:Identify() --> [string]
```
Creates a brief string description of a `Replica`, excluding `Replica.Data` contents. Used for debug purposes.
```lua
print(replica:Identify()) --> "[Id:7;Class:Flower;Tags:{Model=FlowerModel}]"
```
#### Replica:AddCleanupTask()
```lua
Replica:AddCleanupTask(task)
--  task   [function] or [Instance] or [Object] (with :Destroy() or :Disconnect())
```
Signs up a task, object, instance or function to be ran or destroyed when the `Replica` is destroyed.
The cleanup task is performed instantly if the `Replica` is already destroyed.
```lua
local FlowerReplicaClassToken = ReplicaService.NewClassToken("Flower")

local flower_model -- A Model instance
local replica = ReplicaService.NewReplica({
  ClassToken = FlowerReplicaClassToken,
  Tags = {Model = flower_model},
  Data = {
    HasBees = false,
    HoneyScore = 10,
  },
  Replication = "All",
})

replica:AddCleanupTask(flower_model)
replica:Destroy() -- Destroys the replica for all subscribed clients first,
--   then runs all the cleanup tasks including destroying the flower_model
```
#### Replica:RemoveCleanupTask(task)
```lua
Replica:RemoveCleanupTask(task)
```
Removes the cleanup task from the cleanup list.
### Built-in mutators

*(`path` parameter is defined in [CommonTypes](#common-types))*

Mutators can alter any value in `Replica.Data` and replicate this change to players that have this `Replica`
replicated to them. Mutators can only be used server-side or inside [WriteLibs](#writelib). Mutators will
not trigger replication when called inside [WriteLibs](#writelib) since the code is already going to be
performed both on the server and client.

!!! warning
    Just like with [RemoteEvents](https://developer.roblox.com/en-us/api-reference/class/RemoteEvent),
    passing `value` as a reference to an instance which is not replicated to the player (e.g. parented
    to ServerScriptStorage / not parented to the DataModel) will make the client receive a nil value.

#### Replica:SetValue()
```lua
Replica:SetValue(path, value)
```
Sets any individual value within `Replica.Data` to `value`. Parameter `value` can be `nil` and
will set the value located in `path` to `nil`.
#### Replica:SetValues()
```lua
Replica:SetValues(path, values) 
```
Sets multiple keys located in `path` to specified `values`
```lua
replica:SetValues({"Fruit"}, {
  -- Notice: keys can't be paths here, only direct members
  Apples = 5,
  Oranges = 2,
  -- WARNING: nil values will not work with replica:SetValues()
  Bananas = nil, -- THIS IS INVALID, USE
  --   Replica:SetValue({"Fruit", "Bananas"}, nil)
})
print(replica.Data.Fruit.Oranges) --> 2
```
#### Replica:ArrayInsert()
```lua
Replica:ArrayInsert(path, value) --> new_index [number]
```
Performs `table.insert(t, value)` where `t` is a numeric sequential array `table` located in `path`.
#### Replica:ArraySet()
```lua
Replica:ArraySet(path, index, value)
```
Performs `t[index] = value` where `t` is a numeric sequential array `table` located in `path`.
#### Replica:ArrayRemove()
```lua
Replica:ArrayRemove(path, index) --> removed_value
```
Performs `table.remove(t, index)` where `t` is a numeric sequential array `table` located in `path`.

### Custom mutators

!!! error
    Custom mutator functions **must execute identical data changes on server and client given the same function parameters** (Always assume
    `Replica.Data` of all replicated replicas are identical on server and client-side at the time of a write function execution).
    Implementing `RunService:IsServer()`, reading physical positions of parts or reading machine time (`os.clock()`, `tick()`, etc.)
    within write functions may lead to `Replica.Data` desynchronization between server and client-side and a collapse of stable behaviour from further replicated
    [delta-data](https://en.wikipedia.org/wiki/Delta_encoding).
    
    In Layman's terms, a desyncronized client can be asked
    to add `1` to a value (Within `Replica.Data`, via a [write function](#writelib)) which is equal to `100` locally, but is equal to `101` on the server,
    resulting in values `101` and `102` on client and server-side respectively. You may easily desynchronize machines by asking the server and client to add
    `os.clock()` to said value - `os.clock()` is always assumed to be a "desynchronized" value among all machinces and adding it to a synchronized value will
    desynchronize it. Due to Roblox physics being a partially locally simulated feature, desynchronization can also be done by using moving part position values.

    You may still use `os.clock()` or part positions passed as initial write function parameters on server-side so the client may repeat write function operations with
    identical function parameters.

    Keep it synchronized.


#### WriteLib
A *WriteLib* is a `ModuleScript` containing a dictionary of mutator functions. When these functions are
triggered using `Replica:Write()`, they will be called on both the server and all clients that have this
`Replica` replicated to them. ReplicaService serializes all WriteLib functions to numbers, so only a small
number is replicated as a reference to that function.

***WriteLib example structure:***

(`ModuleScript` WriteLib.lua - **Must be a descendant of a replicated instance / container (e.g. ReplicatedStorage)**)
```lua
local WriteLib = {
  -- Mutator functions will receive the first parameter as the
  --   Replica being mutated; Custom parameters passed with
  --   Replica:Write() will follow
  RestockAll = function(replica, restock_count, max_count)
    for soda_name, old_count in pairs(replica.Data.Cans) do
      -- Using mutators inside WriteLibs will trigger client-side
      --   listeners as expected:
      replica:SetValue(
        {"Cans", soda_name},
        math.min(old_count + restock_count, max_count)
      )
    end
  end,
  TakeCan = function(replica, soda_name, amount) --> amount_taken
    local old_count = replica.Data.Cans[soda_name] or 0
    local amount_taken = math.min(old_count, amount)
    if amount_taken > 0 then
       replica:SetValue({"Cans", soda_name}, old_count - amount_taken)
    end
    return amount_taken
  end,
  AddCoins = function(replica, coin_count)
    replica:SetValue({"CoinsInside"}, replica.Data.CoinsInside + coin_count)
  end,
  TakeAllCoins = function() --> coins_taken
    local coins = replica.Data.CoinsInside
    replica:SetValue({"CoinsInside"}, 0)
    replica:Write("RestockAll", 1, 10) -- WriteLibs can use their own mutators!
    return coins
  end,
  -- A note for power users:
  --   replica.Children and replica.Parent can be accessed within
  --   WriteLib mutator functions - built-in and custom mutators
  --   can be triggered for those replicas as well. Go wild!
}

return WriteLib
```

(`Script` ReplicaTest.server.lua)
```lua
local SodaMachineReplicaClassToken = ReplicaService.NewClassToken("SodaMachine")
local WriteLib = game.ReplicatedStorage:FindFirstChild("WriteLib")

local model -- A Model instance
local replica = ReplicaService.NewReplica({
  ClassToken = CoinReplicaClassToken,
  Tags = {Model = model},
  Data = {
    Cans = {
      Cola = 10,
      Lemonade = 10,
      RootBeer = 10,
    },
    CoinsInside = 0,
  }, -- Replica does not create a deep copy!
  Replication = "All",
  WriteLib = WriteLib
})

local cola_click_detector -- Assume this is a ClickDetector of a cola button
local restock_click_detector -- Assume this is a ClickDetector of a restock button

cola_click_detector.MouseClick:Connect(function()
  replica:Write("TakeCan", "Cola", 1)
end)

restock_click_detector.MouseClick:Connect(function()
  replica:Write("RestockAll", 1, 10)
end)

```

(`LocalScript` ReplicaTest.client.lua)
```lua
ReplicaController.ReplicaOfClassCreated("SodaMachine", function(replica)

  local machine_model = replica.Tags.Model

  replica:ListenToWrite("TakeCan", function(soda_name, amount)
    -- Play sound on the client?
    print(tostring(amount) .. " can(s) of " .. soda_name
      .. " have been taken from " .. tostring(machine_model))
  end)

  replica:ListenToWrite("RestockAll", function(restock_count, max_count)
    print(tostring(machine_model) .. " has been restocked! ("
      .. tostring(restock_count) .. " each)")
  end)

  replica:ListenToChange({"Cans", "Cola"}, function(new_value)
    print("Coke can count has changed:", new_value)
  end)

  -- Notice: You don't need to disconnect Replica listeners as the listeners
  --    will be forgotten when the Replica is destroyed

end)
```

!!! notice
    Be aware that things like `os.clock()` will have different values on the server and client when referenced
    inside a WriteLib. Instead you can make the server pass such values as parameters to a mutator function.

#### Replica:Write()
*(`function_name` parameter is defined in [CommonTypes](#common-types))*
```lua
Replica:Write(function_name, params...) --> params...
--    Returns anything the write function returns
```
Calls a function within a [WriteLib](#writelib) that has been assigned to this `Replica` for both the server
and all clients that have this `Replica` replicated to them.
### Server (ReplicaService)
#### Replica:SetParent()
```lua
Replica:SetParent(replica)
```
Changes the `Parent` of the `Replica`.

**Only nested replicas can have their parents changed**
**(nested replicas are replicas that were initially created with a parent).**

If a `Replica`, from a single player's perspective, is moved from a non-replicated parent to
a replicated parent, the replica will be created for the player as expected. Likewise, parenting
a replica to a non-replicated replica will destroy it for that player. This feature is useful for
controlling visible game chunks with entities that can move between those chunks.

#### Replica:ReplicateFor()
```lua
Replica:ReplicateFor("All") -- Replicates the Replica to everyone in the game and
--   everyone who will join in the future
Replica:ReplicateFor(player) -- Selectively replicates the replica to a Player;
--   Will not alter replication when the Replica is already replicated to "All"
```
Changes replication settings (subscription settings) for select players.

**Only top level replicas can have their replication settings changed**
**(top level replicas are replicas that were initially created without a parent).**
#### Replica:DestroyFor()
```lua
Replica:DestroyFor("All") -- Destroys the Replica for all clients that had
--   this replica replicated; Disables replication for future players
Replica:DestroyFor(player) -- Selectively destroys the replica for a Player
```
Changes replication settings (subscription settings) for select players.

**Only top level replicas can have their replication settings changed**
**(top level replicas are replicas that were initially created without a parent).**

!!! warning
    Selectively destroying `Replica:DestroyFor(player)` for clients when the replica is replicated to `"All"`
    will throw an error - Call `Replica:DestroyFor("All")` first.
#### Replica:ConnectOnServerEvent()
```lua
Replica:ConnectOnServerEvent(listener) --> [ScriptConnection] (player, params...)
```
Simulates the behaviour of [RemoteEvent.OnServerEvent](https://developer.roblox.com/en-us/api-reference/class/RemoteEvent#onserverevent-instance-player-tuple-arguments-).
#### Replica:FireClient()
```lua
Replica:FireClient(player, params...)
```
Simulates the behaviour of [RemoteEvent:FireClient()](https://developer.roblox.com/en-us/api-reference/class/RemoteEvent#fireclient-instance-player-tuple-arguments-).
#### Replica:FireAllClients()
```lua
Replica:FireAllClients(params...)
```
Simulates the behaviour of [RemoteEvent:FireAllClients()](https://developer.roblox.com/en-us/api-reference/class/RemoteEvent#fireallclients-tuple-arguments-).
#### Replica:Destroy()
```lua
Replica:Destroy()
```
Destroys replica and all of its descendants (Depth-first). `Replica` destruction signal is sent to the client first,
while cleanup tasks assigned with `Replica:AddCleanupTask()` will be performed after.

### Client (ReplicaController)

*(`path` and `function_name` parameters are defined in [CommonTypes](#common-types))*

#### Replica:ListenToWrite()
```lua
Replica:ListenToWrite(function_name, listener) --> [ScriptConnection]
--   listener   [function] (params...)
```
Listens to WriteLib mutator functions being triggered. See [WriteLib](#writelib) section for examples.
#### Replica:ListenToChange()
```lua
Replica:ListenToChange(path, listener) --> [ScriptConnection]
--   listener   [function] (new_value, old_value)
```
Creates a listener which gets triggered by `Replica:SetValue()` calls.
#### Replica:ListenToNewKey() 
```lua
Replica:ListenToNewKey(path, listener) --> [ScriptConnection]
--   listener   [function] (new_value, new_key)
```
Creates a listener which gets triggered by `Replica:SetValue()` calls when a new
key is created inside `path` (value previously equal to `nil`). Note that this listener
can't reference the key itself inside `path`.
#### Replica:ListenToArrayInsert()
```lua
Replica:ListenToArrayInsert(path, listener) --> [ScriptConnection]
--   listener   [function] (new_index, new_value)
```
Creates a listener which gets triggered by `Replica:ArrayInsert()` calls.
#### Replica:ListenToArraySet()
```lua
Replica:ListenToArraySet(path, listener) --> [ScriptConnection]
--   listener   [function] (index, new_value)
```
Creates a listener which gets triggered by `Replica:ArraySet()` calls.
#### Replica:ListenToArrayRemove()
```lua
Replica:ListenToArrayRemove(path, listener) --> [ScriptConnection]
--   listener   [function] (old_index, old_value)
```
Creates a listener which gets triggered by `Replica:ArrayRemove()` calls.

#### Replica:ListenToRaw()
```lua
Replica:ListenToRaw(listener) --> [ScriptConnection]
--   listener   [function] (action_name, path_array, params...)
```
Allows the developer to parse exact arguments that have been passed to any of the
[built-in mutators](#built-in-mutators).

Possible parameter reference for `Replica:ListenToRaw()`:
```lua
-- ("SetValue", path_array, value)
-- ("SetValues", path_array, values)
-- ("ArrayInsert", path_array, value)
-- ("ArraySet", path_array, index, value)
-- ("ArrayRemove", path_array, index, old_value)

-- path_array   [table] -- table type path
```
#### Replica:ListenToChildAdded()
```lua
Replica:ListenToChildAdded(listener) --> [ScriptConnection]
--   listener   [function] (replica)
```
Creates a listener which gets triggered when a new child `Replica` is created.
#### Replica:FindFirstChildOfClass()
```lua
Replica:FindFirstChildOfClass(replica_class) --> [Replica] or nil
--   replica_class   [string] -- Matches with Replica.Class
```
Returns a first child `Replica` of specified class if one exists.
#### Replica:ConnectOnClientEvent()
```lua
Replica:ConnectOnClientEvent(listener) --> [ScriptConnection]
--   listener   [function] (params...)
```
Simulates the behaviour of [RemoteEvent.OnClientEvent](https://developer.roblox.com/en-us/api-reference/class/RemoteEvent#onclientevent-tuple-arguments-).
#### Replica:FireServer()
```lua
Replica:FireServer(params...)
```
Simulates the behaviour of [RemoteEvent:FireServer()](https://developer.roblox.com/en-us/api-reference/class/RemoteEvent#fireserver-tuple-arguments-).