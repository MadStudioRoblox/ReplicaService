# Home
ReplicaService is a selective state replication system. ReplicaService helps you make server code which changes and replicates any state to select clients.

Assume that a [state (Wikipedia)](https://en.wikipedia.org/wiki/State_(computer_science)) is any kind of data that has a present version and may also change at any time in the future, as many times as necessary. The data about a player which you load up during gameplay or save to the DataStore is a state. The color of a part, text shown on a users screen and furniture placed in a player owned house are all states - ReplicaService helps you make server-side code to control and replicate any state to all clients at once or only a select few.

A state (in layman’s terms, a lua table that may contain almost anything) is wrapped with a Replica - like the name implies, it creates a [replica (identical copy)](https://en.wikipedia.org/wiki/Replica) of the wrapped state on the client-side of users you want to see that state. You may define clients who will see that replica, call mutator functions on the Replica to change the state (will change contents of the wrapped table) and make the clients listen to those changes or simply read the state whenever necessary. Furthermore, a Replica can be parented to another Replica (with a few exceptions discussed later), unloaded for select clients and, of course, destroyed.

What's good about ReplicaService:

- **Just replication, whatever you need replicated** - The goal of ReplicaService is to streamline custom Roblox object replication from server to client. ReplicaService avoids being redundant and tackles as few concerns as possible.

- **Chunks & player houses** - Selective replication allows you to make a "custom [StreamingEnabled](https://developer.roblox.com/en-us/articles/content-streaming) implementation" with full server-side control - load in nearby chunks, load in interiors and furniture only when the player enters those areas!

- **"It don't go brrrrr"** - ReplicaService is completely event-based and only tells the client the data that changes - it keeps the network usage low and conserves computer resources.

- **Go big, go small** - Use custom mutators for minimal bandwith and gain access to client-side listeners that react to bulk changes instead of individual values. Use built-in mutators for rapid implementations while still keeping your network use very low.

If anything is missing or broken, [file an issue on GitHub](https://github.com/MadStudioRoblox/ReplicaService/issues).

If you need help integrating ReplicaService into your project, [join the discussion](https://devforum.roblox.com/t/replicate-your-states-with-replicaservice-networking-system/894736).