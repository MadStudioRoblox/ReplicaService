# Madwork - ReplicaService

ReplicaService is a selective state replication system. ReplicaService helps you make server code which changes and replicates any state to select clients.

A state (in layman’s terms, a lua table that may contain almost anything) is wrapped with a Replica - like the name implies, it creates a [replica (identical copy)](https://en.wikipedia.org/wiki/Replica) of the wrapped state on the client-side of users you want to see that state. You may define clients who will see that replica, call mutator functions on the Replica to change the state (will change contents of the wrapped table) and make the clients listen to those changes or simply read the state whenever necessary. Furthermore, a Replica can be parented to another Replica (with a few exceptions discussed later), unloaded for select clients and, of course, destroyed.

What's good about ReplicaService:

- **Go big, go small** - Create powerful replication systems with WriteLibs (state mutation functions) or use built-in mutators to change any value within a state.
- **Chunks & player houses** - ReplicaService selective replication allows you to easily subscribe users to game chunks / player owned houses that they are currently nearby / inside - You can make the client automatically load in the assets needed for a replicated area as soon as the Replica object is received.
- **Low network usage** - ReplicaService only sends the whole state when the player first receives a replica. Afterwards only individual changes are sent. Custom mutator functions can replicate infinitely massive changes to the state with just a few bytes of data sent.
- **Just replication, whatever you need replicated** - The goal of ReplicaService is to truly streamline custom Roblox object replication without having it’s method list obscured with redundant features or features that give the module one too many concerns to tackle.

If anything is missing or broken, [file an issue on GitHub](https://github.com/MadStudioRoblox/ReplicaService/issues).

If you need help integrating ReplicaService into your project, [join the discussion](https://devforum.roblox.com/t/replicate-your-states-with-replicaservice-networking-system/894736).

---
*ReplicaService is part of the **Madwork** framework*
*Developed by [loleris](https://twitter.com/LM_loleris)*

***It's documented:***
**[ReplicaService wiki](https://madstudioroblox.github.io/ReplicaService/)**

***It's open source:***
[Roblox library](https://www.roblox.com/library/6015318619/ReplicaService)