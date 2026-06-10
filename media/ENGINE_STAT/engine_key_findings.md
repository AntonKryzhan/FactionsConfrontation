# Engine audit key findings for Factions Confrontation

Scope: all Java files in `ИСХОДНИКИ ДВИЖКА.zip` were indexed and scanned for mod-relevant engine surfaces. This is static analysis, not runtime profiling.

## Inventory

- Java files indexed: 2104
- Total source lines: 590489
- Full per-file index: `engine_file_index.csv`
- Package summary: `engine_package_summary.csv`

## Highest-risk / highest-relevance files

| Rank | File | Lines | Risk | Why relevant |
|---:|---|---:|---:|---|
| 1 | `zombie/network/GameServer.java` | 8554 | 22077 | zombie_char:137, pathfinding:5, los_vision:13, lua_bridge:61, threads:48, cell_world:168 |
| 2 | `zombie/network/GameClient.java` | 6193 | 13101 | zombie_char:246, pathfinding:5, los_vision:10, lua_bridge:142, threads:33, cell_world:166 |
| 3 | `zombie/vehicles/PolygonalMap2.java` | 8249 | 9091 | zombie_char:52, pathfinding:1751, los_vision:47, lua_bridge:4, threads:57, cell_world:294 |
| 4 | `zombie/characters/IsoGameCharacter.java` | 13803 | 5790 | zombie_char:546, pathfinding:60, los_vision:59, lua_bridge:74, threads:10, cell_world:99 |
| 5 | `zombie/Lua/LuaManager.java` | 9102 | 5552 | zombie_char:134, pathfinding:86, los_vision:13, lua_bridge:324, threads:34, cell_world:127 |
| 6 | `zombie/network/PacketTypes.java` | 639 | 5227 | lua_bridge:6, threads:5, cell_world:4, network:1290 |
| 7 | `zombie/iso/IsoGridSquare.java` | 9245 | 4999 | zombie_char:110, pathfinding:73, los_vision:180, lua_bridge:25, threads:6, cell_world:470 |
| 8 | `zombie/iso/IsoCell.java` | 5128 | 4584 | zombie_char:110, pathfinding:8, los_vision:76, lua_bridge:30, threads:9, cell_world:540 |
| 9 | `zombie/vehicles/BaseVehicle.java` | 9391 | 3679 | zombie_char:149, pathfinding:23, los_vision:10, lua_bridge:48, threads:4, cell_world:181 |
| 10 | `zombie/iso/IsoChunk.java` | 4473 | 3323 | zombie_char:22, pathfinding:25, los_vision:6, lua_bridge:5, threads:75, cell_world:611 |
| 11 | `zombie/vehicles/VehicleManager.java` | 1651 | 2757 | zombie_char:33, los_vision:2, lua_bridge:5, cell_world:35, network:600 |
| 12 | `zombie/iso/WorldStreamer.java` | 1076 | 2600 | zombie_char:4, threads:23, cell_world:530, network:96 |
| 13 | `zombie/characters/IsoPlayer.java` | 7661 | 2531 | zombie_char:154, pathfinding:75, los_vision:49, lua_bridge:27, threads:20, cell_world:91 |
| 14 | `zombie/iso/IsoObject.java` | 4547 | 2434 | zombie_char:54, pathfinding:2, los_vision:19, lua_bridge:20, threads:2, cell_world:126 |
| 15 | `zombie/iso/IsoChunkMap.java` | 1166 | 2428 | zombie_char:16, threads:22, cell_world:551, network:11, render:8, update_methods:1 |
| 16 | `zombie/characters/IsoZombie.java` | 4626 | 2050 | zombie_char:182, pathfinding:82, los_vision:23, lua_bridge:8, cell_world:33, network:87 |
| 17 | `zombie/worldMap/WorldMapRenderer.java` | 2367 | 2048 | zombie_char:3, los_vision:13, cell_world:2, render:655 |
| 18 | `zombie/core/textures/Texture.java` | 1661 | 1759 | pathfinding:23, cell_world:4, network:4, render:543 |
| 19 | `zombie/core/SpriteRenderer.java` | 1324 | 1758 | pathfinding:3, threads:4, cell_world:10, render:564 |
| 20 | `zombie/iso/objects/IsoDoor.java` | 3143 | 1691 | zombie_char:48, pathfinding:7, los_vision:22, lua_bridge:22, threads:9, cell_world:104 |
| 21 | `zombie/network/FakeClientManager.java` | 2599 | 1599 | pathfinding:1, los_vision:5, threads:21, cell_world:21, network:355, update_methods:2 |
| 22 | `zombie/inventory/ItemContainer.java` | 3170 | 1545 | zombie_char:29, lua_bridge:146, threads:12, cell_world:31, network:70, render:16 |
| 23 | `zombie/iso/IsoWorld.java` | 2697 | 1483 | zombie_char:61, pathfinding:16, los_vision:6, lua_bridge:30, threads:6, cell_world:106 |
| 24 | `zombie/gameStates/IngameState.java` | 1401 | 1403 | zombie_char:60, pathfinding:3, los_vision:5, lua_bridge:22, threads:5, cell_world:84 |
| 25 | `zombie/network/MPStatistic.java` | 1117 | 1396 | pathfinding:1, lua_bridge:25, cell_world:11, network:299 |
| 26 | `zombie/network/PlayerDownloadServer.java` | 479 | 1362 | threads:13, cell_world:253, network:76, render:1, update_methods:1 |
| 27 | `zombie/gameStates/DebugChunkState.java` | 1276 | 1340 | zombie_char:17, pathfinding:20, los_vision:21, lua_bridge:26, threads:4, cell_world:132 |
| 28 | `zombie/iso/objects/IsoThumpable.java` | 2471 | 1324 | zombie_char:48, pathfinding:1, los_vision:31, lua_bridge:28, threads:27, cell_world:55 |
| 29 | `zombie/ai/states/SwipeStatePlayer.java` | 2266 | 1302 | zombie_char:169, pathfinding:4, los_vision:44, lua_bridge:9, cell_world:25, network:23 |
| 30 | `zombie/vehicles/PathFindBehavior2.java` | 1027 | 1283 | zombie_char:35, pathfinding:246, los_vision:4, lua_bridge:3, cell_world:12, network:2 |
| 31 | `se/krka/kahlua/vm/KahluaThread.java` | 1738 | 1219 | lua_bridge:188, threads:27 |
| 32 | `zombie/vehicles/UI3DScene.java` | 3661 | 1202 | los_vision:21, lua_bridge:12, render:345 |
| 33 | `zombie/ui/UIManager.java` | 1831 | 1163 | zombie_char:27, los_vision:40, lua_bridge:56, threads:50, cell_world:5, network:6 |
| 34 | `zombie/core/Core.java` | 3847 | 1134 | zombie_char:11, pathfinding:3, lua_bridge:35, threads:14, network:9, render:255 |
| 35 | `zombie/core/sprite/GenericSpriteRenderState.java` | 949 | 1119 | los_vision:1, render:371 |
| 36 | `zombie/inventory/ItemPickerJava.java` | 1101 | 1111 | zombie_char:11, lua_bridge:151, cell_world:28, network:8 |
| 37 | `zombie/ui/TextDrawObject.java` | 1092 | 1076 | zombie_char:2, los_vision:5, threads:15, network:2, render:330 |
| 38 | `zombie/iso/ObjectsSyncRequests.java` | 549 | 1071 | lua_bridge:5, threads:11, cell_world:139, network:112 |
| 39 | `zombie/core/skinnedmodel/model/ModelInstanceTextureCreator.java` | 654 | 1058 | zombie_char:2, los_vision:13, render:328 |
| 40 | `zombie/core/skinnedmodel/DeadBodyAtlas.java` | 1308 | 1051 | zombie_char:7, cell_world:9, render:319, update_methods:6 |

## Direct conclusions for the mod

1. Physical NPCs based on `IsoZombie` are expensive because they pass through vanilla character update, Lua `OnZombieUpdate`, LOS, pathfinding, animation, collision and render layers.
2. The safe multi-core surface is snapshot/queue-style work such as pathfinding jobs. Mutating `IsoCell`, live characters, Lua, ModData, animation or network state off-main-thread is high risk.
3. Best next mod patch is a Physical Battle Governor: battle LOD, battle slots, shared squad sensing, proxy/virtual casualties, and effects budgets.
4. Best next engine patch is diagnostics/kill-switch/counters and bounded pathfinding tuning, not full parallel `IsoZombie.update`.

## Key file notes

### `zombie/characters/IsoZombie.java`

- Lines: 4626
- Risk score: 2050
- Matches: pathfinding=82, LOS=23, Lua=8, threads=0, render=62, network=87, update_methods=1
- Audit note: primary physical NPC carrier; avoid engine-level parallel update; control count/update rate at mod layer.

### `zombie/characters/IsoGameCharacter.java`

- Lines: 13803
- Risk score: 5790
- Matches: pathfinding=60, LOS=59, Lua=74, threads=10, render=311, network=185, update_methods=3
- Audit note: shared character state/vision/inventory/animation surface; high main-thread coupling.

### `zombie/vehicles/PathFindBehavior2.java`

- Lines: 1027
- Risk score: 1283
- Matches: pathfinding=246, LOS=4, Lua=3, threads=0, render=9, network=2, update_methods=0
- Audit note: best candidate for bounded async/dedup diagnostics; already patched in current mod builder.

### `zombie/vehicles/PolygonalMap2.java`

- Lines: 8249
- Risk score: 9091
- Matches: pathfinding=1751, LOS=47, Lua=4, threads=57, render=79, network=5, update_methods=0
- Audit note: existing pathfinding queue/thread infrastructure; risky to rewrite broadly.

### `zombie/Lua/LuaEventManager.java`

- Lines: 635
- Risk score: 489
- Matches: pathfinding=0, LOS=0, Lua=62, threads=9, render=13, network=8, update_methods=0
- Audit note: Lua bridge must stay main-thread-safe; do not call Lua from worker threads.

### `zombie/iso/LosUtil.java`

- Lines: 614
- Risk score: 378
- Matches: pathfinding=0, LOS=68, Lua=0, threads=0, render=0, network=0, update_methods=0
- Audit note: LOS should be reduced by caching/shared sensing, not brute-force threaded against live world state.

### `zombie/core/SpriteRenderer.java`

- Lines: 1324
- Risk score: 1758
- Matches: pathfinding=3, LOS=0, Lua=0, threads=4, render=564, network=0, update_methods=0
- Audit note: render buffer tuning is useful; logic changes here are high risk and unrelated to AI decisions.

### `zombie/core/sprite/GenericSpriteRenderState.java`

- Lines: 949
- Risk score: 1119
- Matches: pathfinding=0, LOS=1, Lua=0, threads=0, render=371, network=0, update_methods=0
- Audit note: render buffer tuning is useful; logic changes here are high risk and unrelated to AI decisions.

### `zombie/iso/IsoCell.java`

- Lines: 5128
- Risk score: 4584
- Matches: pathfinding=8, LOS=76, Lua=30, threads=9, render=379, network=36, update_methods=1
- Audit note: world object container/mutation layer; unsafe for off-thread modification.

### `zombie/network/GameServer.java`

- Lines: 8554
- Risk score: 22077
- Matches: pathfinding=5, LOS=13, Lua=61, threads=48, render=16, network=5018, update_methods=0
- Audit note: network-sensitive; avoid changing packet/state semantics for NPC optimisation.

### `zombie/network/GameClient.java`

- Lines: 6193
- Risk score: 13101
- Matches: pathfinding=5, LOS=10, Lua=142, threads=33, render=1, network=2544, update_methods=1
- Audit note: network-sensitive; avoid changing packet/state semantics for NPC optimisation.

