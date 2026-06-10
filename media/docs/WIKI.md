# Factions Confrontation - Mod Wiki

> User-facing and developer-facing wiki page for the **Factions Confrontation** Project Zomboid mod.

<p align="center">
  <img src="../ENGINE_STAT/ead07461-e8f6-4018-bdfc-7983be54e8a7.png" alt="Factions Confrontation architecture map" width="960">
</p>

---

## Languages

- [Russian version](WIKI_RU.md)

---

## Table of Contents

- [What Is Factions Confrontation?](#what-is-factions-confrontation)
- [Quick Start](#quick-start)
- [Core Gameplay Loop](#core-gameplay-loop)
- [NPC Factions](#npc-factions)
- [Mercenaries and Orders](#mercenaries-and-orders)
- [Black Market and Contracts](#black-market-and-contracts)
- [Bases, Patrols, Raids, and Global Squads](#bases-patrols-raids-and-global-squads)
- [Persistence and COOP / Multiplayer](#persistence-and-coop--multiplayer)
- [Performance Systems](#performance-systems)
- [Recommended Server Checks](#recommended-server-checks)
- [Troubleshooting](#troubleshooting)
- [Development File Map](#development-file-map)
- [FAQ](#faq)

---

## What Is Factions Confrontation?

**Factions Confrontation** is a Project Zomboid mod that adds a persistent NPC faction layer to Knox Country.

The mod is built around living survivor groups, hostile factions, faction bases, patrols, contracts, black market activity, tactical NPC behavior, loot/rearm systems, and background world simulation.

The main design goal is to make the world feel contested. Factions should not exist only as isolated encounters: they can occupy areas, defend bases, send patrols, generate contracts, fight enemies, interact with world systems, and create pressure around the player.

---

## Quick Start

### Installation

Place the mod folder here:

```text
C:\Users\<YourUser>\Zomboid\Workshop\FactionsConfrontation\Contents\mods\FactionsConfrontation
```

Expected structure:

```text
FactionsConfrontation/
├── media/
├── mod.info
├── poster.png
└── README.md
```

Then enable **Factions Confrontation** in the Project Zomboid mod list.

### First In-Game Check

After enabling the mod, start a new world or COOP session and verify:

- the game loads without console errors;
- faction/NPC systems initialize;
- NPC groups can appear or be spawned by mod systems;
- world markers, bases, contracts, or black market systems are available depending on current gameplay state;
- server logs remain clean in COOP or dedicated-server testing.

---

## Core Gameplay Loop

The mod is centered on a few connected gameplay loops:

1. Explore the world and encounter NPC factions, bases, patrols, enemies, contracts, or black market activity.
2. Interact with faction systems through orders, contracts, loot, markers, bases, and events.
3. Fight, avoid, recruit, or command NPCs depending on faction state and available systems.
4. Loot and rearm NPCs or mercenaries so they can continue operating.
5. Persist important state so the world can continue across saves and COOP/server restarts.

The player acts locally through UI and orders, while the server remains authoritative for command validation, NPC ownership, world state, persistence, and synchronization.

---

## NPC Factions

Factions are designed to give the world a sense of territorial pressure and conflict.

Typical faction-related systems include:

- faction identities and hostility profiles;
- faction bases, camps, checkpoints, and patrol routes;
- leaders, loyalty, wanted/heat logic, and disguise-related gameplay;
- faction documents, radio intercepts, signals, and intel-style systems;
- raids, convoys, bounty systems, and black market events.

Faction systems are handled across shared, client, and server Lua layers. The server-side layer is responsible for authoritative world state and persistence, while the client layer focuses on UI, visualization, markers, and command input.

---

## Mercenaries and Orders

The current architecture includes a dedicated **Mercenary Direct Pipeline**.

This pipeline keeps hired mercenaries separate from the generic NPC order channel and helps avoid command conflicts between normal NPC systems and player-controlled hired groups.

### Supported Order Concepts

Mercenary and NPC order systems can include:

- Follow me;
- Move here;
- Guard;
- Patrol;
- Loot;
- Search;
- Rearm;
- Return;
- Fire mode;
- Formation behavior.

### Follow Orders

Follow orders are bound to the player. The mercenary should track the player rather than a static cursor point.

### Point-Based Orders

Point-based commands use a **cursor world anchor**. The player chooses a point in the world, and that point becomes the target anchor for orders such as move, guard, return, or advance.

### Server Authority

The client can request an order, but the server validates:

- the player;
- ownership;
- hired group identity;
- command batch;
- order revision;
- current mercenary state.

After validation, the server broadcasts or applies the authoritative order state.

---

## Black Market and Contracts

The Black Market system is one of the major gameplay layers of the mod.

It can include:

- Black Market world objects;
- contract interactions;
- reward containers;
- defense or event hooks;
- faction-related mission flow;
- persistence across server restarts;
- integration with bounty, convoy, checkpoint, counter-intel, heat/wanted, and intel dossier systems.

Important design note: reward containers and contract-related state should be handled carefully in COOP/server sessions so that useful loot is not deleted unexpectedly during persistence cleanup.

---

## Bases, Patrols, Raids, and Global Squads

The server strategic layer manages high-level world activity.

Main concepts:

- **Bases and camps** - faction-controlled areas with garrisons, supplies, and activity.
- **Checkpoints** - strategic points that can support patrol or faction presence.
- **Patrols and raids** - moving faction groups that create conflict and pressure.
- **Virtual groups / global squads** - lightweight global-map groups that can later materialize near the player.
- **Materialization / dematerialization** - NPCs near the player become active entities, while distant groups can be represented more cheaply.

This split is important for performance. The mod should not keep every global group fully active all the time.

---

## Persistence and COOP / Multiplayer

The mod uses persistent state for key systems.

Persistence can include:

- ModData save roots;
- persistent NPC snapshots;
- runtime inventory state;
- death-loot snapshots;
- base and faction state;
- global squad state;
- mercenary order revisions;
- equipment state, including weapons, ammo, clothing, and armor.

### COOP / Dedicated Server Expectations

In COOP/server play, the server is responsible for world simulation and authoritative state. The client should not be trusted as the final source of truth for persistent NPC state, ownership, contracts, or global faction activity.

After a restart, important nearby or materialized NPCs, base state, and selected world systems should restore consistently if they are part of the current persistence design.

---

## Performance Systems

Factions Confrontation uses several optimization-oriented systems to reduce CPU spikes and keep NPC-heavy scenes more stable.

Key systems include:

- **AI LOD** - less important or distant NPCs can use reduced thinking depth.
- **Spatial indexing** - nearby NPC, zombie, and world queries should use indexed lookup where possible.
- **Work scheduling** - heavy work should be budgeted across ticks instead of running in one large spike.
- **Runtime caches** - repeated expensive queries should be cached when safe.
- **Influence fields** - world threat/control/noise-style data can be reused by strategic logic.
- **Telemetry and regression guards** - development systems help identify performance and stability issues.
- **Java class overrides** - selected `media/ProjectZomboid` class patches are bundled for pathfinding, rendering, and runtime support.

Development rule: avoid adding heavy unthrottled `OnTick` or `OnUpdate` logic. Expensive systems should use scheduling, caching, throttling, spatial queries, or LOD gates.

---

## Recommended Server Checks

After updating the mod, especially after large NPC/server changes, test the following:

1. Start a fresh COOP or dedicated server.
2. Confirm that the mod loads without client or server console errors.
3. Spawn or encounter NPC groups.
4. Verify combat behavior with zombies and enemy NPCs.
5. Issue mercenary orders: follow, move, guard, loot, rearm, and return.
6. Restart the server and verify persistent state.
7. Check Black Market reward containers after restart.
8. Verify faction bases, checkpoints, world markers, and contracts.
9. Test scenes with multiple NPCs and monitor FPS/server tick stability.
10. Review both client and server logs for repeated errors or spam.

---

## Troubleshooting

### The mod does not appear in the mod list

Check the folder structure:

```text
FactionsConfrontation/
├── media/
├── mod.info
└── poster.png
```

The `mod.info` file must be inside the root mod folder, not one directory too deep.

### NPCs do not respond to orders

Check:

- whether the NPC is actually a hired mercenary;
- whether the order was sent through the correct UI/context menu;
- whether the client sent the command batch;
- whether the server accepted the owner/group validation;
- whether the server or client console contains command errors.

### Follow works incorrectly

Follow should track the player, not a cursor anchor. If follow behaves like a point order, inspect the Mercenary Direct Pipeline and order normalization logic.

### Point orders go to the wrong place

Point orders depend on the cursor world anchor. Check map/cursor targeting and whether the server receives the correct world position.

### Severe FPS drops with many NPCs

Check for:

- unthrottled `OnTick` / `OnUpdate` logic;
- repeated full-world scans;
- too many active NPCs near the player;
- excessive debug markers or UI updates;
- pathfinding spikes;
- server console spam.

Recommended systems for optimization work:

- `NPCSpatialIndexBridge`
- `NPCAILODTraderBridge`
- `NPCWorkSchedulerBridge`
- `NPCAsyncSchedulerBridge`
- `NPCInfluenceFieldBridge`
- `NPCCrowdBudgetBridge`
- `NPCPerformanceTelemetryBridge`

### State is lost after server restart

Check whether the system is expected to persist. Not every runtime-only object should be saved.

For persistent systems, inspect:

- ModData roots;
- NPC snapshots;
- base/faction state;
- mercenary order revisions;
- black market reward containers;
- server-side save/load hooks.

---

## Development File Map

Important project areas:

```text
media/lua/client/       # Client UI, commands, markers, local NPC updates
media/lua/server/       # Server commands, persistence, world simulation
media/lua/shared/       # Shared NPC core, contracts, behavior, utilities
media/ProjectZomboid/   # Bundled Java class overrides
media/ENGINE_STAT/      # Diagrams, audit notes, development reference files
```

Important navigation/changelog files:

```text
media/lua/shared/PROJECT_MAP.md
media/lua/shared/PROJECT_MAP_UPDATE.md
```

High-value systems for future optimization work:

```text
media/lua/shared/NPCCore/NPCSpatialIndexBridge.lua
media/lua/shared/NPCCore/NPCAILODTraderBridge.lua
media/lua/shared/NPCCore/NPCWorkSchedulerBridge.lua
media/lua/shared/NPCCore/NPCAsyncSchedulerBridge.lua
media/lua/shared/NPCCore/NPCInfluenceFieldBridge.lua
media/lua/shared/NPCCore/NPCCrowdBudgetBridge.lua
media/lua/server/NPCServer/NPCWorldDirectorBridge.lua
media/lua/client/NPCClient/NPCUpdateBridge.lua
media/lua/shared/NPCBehavior/NPCBrainDirectorBridge.lua
```

---

## FAQ

### Is this a single-player mod or a multiplayer mod?

The mod is designed with separate client, server, and shared layers, so COOP/server support is part of the architecture. Single-player behavior should also work because Project Zomboid still uses client/server-style Lua separation internally.

### Are all NPCs fully simulated all the time?

No. The architecture is designed to support active NPCs near the player and cheaper background/global simulation for distant groups where possible.

### Why does the mod use bridge files?

Bridge modules keep compatibility with the Project Zomboid Lua loading model and make it easier to separate client, server, and shared responsibilities without breaking existing APIs.

### Why are there Java class files inside `media/ProjectZomboid`?

The current build includes selected Project Zomboid runtime class overrides for pathfinding, rendering, and runtime support. These should be changed carefully because they can affect engine-level behavior.

### Should every bug fix include refactoring?

No. Bug fixes should be minimal and controlled. Avoid renaming functions, changing APIs, or touching unrelated systems unless it is directly required.

---

## Credits

Created and maintained by **CARL REAPER SHEPPARDS** and **Error 404 | Skill not found**.

Built for the Project Zomboid modding community.

---

## Disclaimer

This is an unofficial Project Zomboid mod. It is not affiliated with, endorsed by, or sponsored by The Indie Stone.
