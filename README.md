# Madwork - ReplicaService

ReplicaService is a selective state replication system.

ReplicaService helps you make server-side code to control and replicate any state to all
clients or only a select few.

A state (in layman's terms, a lua table that may contain almost anything) is wrapped with a `Replica` - like the name inplies,
it creates a replica of the wrapped state which is sent to desired clients. You may define clients who will see that replica,
call mutator functions on the `Replica` to change the state (will change contents of the wrapped table) and make the clients
listen to those changes or simply read the state whenever necessary. Furthermore, a `Replica` can be parented to another
`Replica` (with a few exceptions discussed later), unloaded for select clients and, of course, destroyed.

What's good about ReplicaService:

- **Go big and go small** - Create powerful replication systems with WriteLibs (state mutation functions) or
use built-in mutators to change any value within a state.
- **Go MMO** - ReplicaService selective replication allows you to easily subscribe users to game chunks / player owned houses
that they are currently nearby / inside - You can make the client automatically load in the assets making up the replicated area
as soon as it receives the Replica object.
- **Low network usage** - ReplicaService only sends the whole state when the player first receives a replica.
Afterwards only individual changes are sent.
- **Just replication, whatever you need replicated** - ReplicaService does very little runtime typechecking which might be
desirable for projects pushing the limits of the Roblox engine and convenient for people who want to get their hands dirty quick.
Testing is still important - write your own type checking as you see fit.

If anything is missing or broken, [file an issue on GitHub](https://github.com/MadStudioRoblox/ReplicaService/issues).

If you need help integrating ReplicaService into your project, [join the discussion]().

---
*ReplicaService is part of the **Madwork** framework*
*Developed by [loleris](https://twitter.com/LM_loleris)*

***It's documented:***
**[ReplicaService wiki](https://madstudioroblox.github.io/ReplicaService/)**

***It's open source:***
[Roblox library](https://www.roblox.com/library/6015318619/ReplicaService)