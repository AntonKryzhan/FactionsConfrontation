# Factions Confrontation — Project Map

## Bug chain checked in this patch

- `coop-console.txt`: repeated server exception `__add not defined for operands in FindNearbyWorldRoadPoint`.
- Runtime chain: `NPCCheckpointsServerBridge.bcps_everyTenMinutes` -> `EnsureCheckpoints` -> `bcps_createFromRoadPatrols` -> `bcps_findStrategicCheckpointPoint` -> `NPCWorldDirectorBridge.GetNearbyRoadPoint` -> `NPCRoadNavBridge.FindNearbyWorldRoadPoint`.
- Cause: checkpoint/road-patrol code could pass non-numeric coordinates into road navigation; `FindNearbyWorldRoadPoint` then tried to add a random offset to a non-number.
- `console.txt`: client render crash starts from stale `IsoTree` class override in `media/ProjectZomboid/zombie/...`, then cascades into OpenGL/SmartTexture errors.
- Cause: the uploaded archive accidentally contained almost the whole Project Zomboid `zombie/*.class` tree instead of only the intended engine patch files.

## Files touched by this patch

- `media/lua/shared/NPCCore/NPCRoadNavBridge.lua`
  - numeric guards for road-nav coordinates and attempts/radius;
  - invalid coordinates now return `nil`/blocked score instead of throwing Lua arithmetic errors.
- `media/lua/server/NPCServer/NPCWorldDirectorBridge.lua`
  - guards `GetNearbyRoadPoint` against invalid `x/y` and nil director radius.
- `media/lua/server/NPCServer/NPCCheckpointsServerBridge.lua`
  - sanitizes road-patrol checkpoint source coordinates before road lookup.
- `media/ProjectZomboid/...`
  - full fixed mod archive removes accidental extra game engine class overrides and keeps only the intended ProjectZomboid patch set.

## Areas intentionally not refactored

- No API rename.
- No ModData format change.
- No sendClientCommand/sendServerCommand contract change.
- No checkpoint data schema change.
- No gameplay balance changes.

## Stage 364 — Render rollback guard

Client-side OpenGL 1282 reports after Stage 363 were traced to the active render override path: `Shader.setLight` -> `Model.DrawChar` -> `SpriteRenderer.postRender/buildStateDrawBuffer`. The 2026-06-07 aggressive renderer class set and `br.render.*` VM flags are no longer used. The mod now uses the known-good 2026-06-05/STABLE renderer class set while keeping the Stage 363 Lua road-coordinate guards.


Stage366 note: `media/ProjectZomboid` is intentionally absent. The build uses vanilla Project Zomboid Java/render/runtime classes to eliminate stale class shadowing such as `IsoTree.class` and `SpriteRenderer.class`.

## Stage371 note

This build keeps the Stage366+ rule that `media/ProjectZomboid` is absent. Stage371 only refactors the Lua-side hired blue mercenary order system: shared order revisions/batches, immediate group dispatch, client-side two-phase batch application, responsive Follow task enqueue, and anti-stall Patrol/SearchHouse scan ticks. Stage371 does not change Java/classes, quests, bases, economy, loot tables, save formats, or unrelated world simulation.

## Stage372 note

Hired blue mercenary orders now use a dedicated direct order pipeline instead of the shared NPC order-contract dispatch path. Server commands send `MercenaryDirectOrderBatch`; client applies the full batch together and queues immediate mercenary tasks without the generic async `UpdateNPCPart` route. This is limited to hired mercenary command responsiveness and does not touch Java/classes, quests, bases, economy, loot tables, or save formats.


## Stage 373 - Mercenary direct order hotfix
- `media/lua/client/NPCClient/NPCUpdateBridge.lua`: predeclares and assigns `bridge_normMercenaryOrderName` before strict mercenary order functions use it. This fixes the Stage372 `Object tried to call nil in GetStrictOrderBoundaryAnchor` error during order execution.
- `PROJECT_MAP_UPDATE.md`: stage changelog.

## Stage375_MERCENARY_CURSOR_SEMANTICS_ROLLBACK (2026-06-09)
- Mercenary order execution stabilization based on Stage373 hotfix, not Stage374 direct-controller.
- Cursor point orders are treated as exact world-point orders before any tactical/delegated behavior.
- Follow is kept as a separate player-follow order.
- Modified runtime file: media/lua/client/NPCClient/NPCUpdateBridge.lua.

## Stage376 note

Hired mercenary order semantics were hardened without touching other systems. `Follow` is a player-targeted order and clears stale cursor anchors. Point orders use the right-clicked cursor square as `targetType="point"` / `cursorAnchor=true`. FireMode and Formation remain overlay updates. Changed files are limited to the mercenary order menu/client/server/contract/runtime path.

## Stage377 note

Mercenary ownership validation was hardened. Explicit group-targeted mercenary orders are accepted only if the requested group is hired by the requesting player. Stale/non-owned group ids no longer redirect to the player's active squad. Client menu selection no longer substitutes a nearby hired mercenary when the cursor is directly on another NPC.

## Stage378 note

Mercenary hire validation was hardened on the server side only. `HireMercenaryGroup` now verifies server-side blue/mercenary/hireable state and server-side proximity to the target before taking payment or hiring. Client `args.mercenary` / `args.brainSide` are no longer trusted as authorization. Scope is limited to mercenary hire/order validation; payment fallback behavior is unchanged.

### Stage379 mercenary command guard note
- `NPCClientCommandsServerBridge.lua` owns the Stage379 server-side guard for hired mercenary order input: stale active group ids are ignored, empty commands are rejected, and no-anchor point orders are rejected before throttle accounting.
- Scope is command validation only; no runtime AI/controller changes.

## Stage380 note
- Latest narrow hardening pass: mercenary client-side command preflight and status ownership guard only.
- Point-order payloads require a real world/cursor square and mark `cursorAnchor=true`; no `player_fallback` anchor is sent for point orders.
- Explicit squad menus/orders/status now require the group to be locally/server-side owned by the requesting player.
- No non-mercenary systems changed.


### Stage381 note
- Active project navigation/changelog is now also mirrored under `media/PROJECT_MAP.md` and `media/PROJECT_MAP_UPDATE.md` because files outside `FactionsConfrontation/media` may not be included/loaded in some mod distribution flows.
- Mercenary hire now rejects target brains already hired by another player even when group resolution is stale.
## Stage382 note

Mercenary point orders now have a server-side world-anchor guard: cursor-based commands are accepted only when the anchor is reasonably near the issuing player and on a compatible z-level. This rejects fake/map-wide payloads before throttle and before orderRevision creation. Explicit mercenary status requests no longer fall back to another squad when the requested group is empty/stale. Scope is limited to mercenary command validation.


## Stage383 note

Mercenary order telemetry was added to the hired-mercenary command path only. Client order/hire/status packets now carry `clientTraceId`, `clientSendMs`, and `clientOrderSeq`; the server logs receive/accept/flush timing and forwards telemetry with `MercenaryDirectOrderBatch`; the client logs batch receive and immediate-task queue timing. This is diagnostics only: no AI movement, order semantics, hire/payment, Black Market, bases, persistence format, Java, graphics, or `media/ProjectZomboid` changes.
### Stage384 menu consistency note
- `media/lua/client/NPCClient/NPCMenuBridge.lua`: keeps mercenary context-menu commands scoped to owned/hired mercenary squads. Generic bodyguard orders are suppressed when the click target is an unowned blue mercenary to prevent UI confusion.
- Project map/changelog is mirrored inside `media/` so it remains in the loaded mod tree.

## Stage385 note

Final narrow safety pass for the hired mercenary command layer. `NPCClientCommandsServerBridge.lua` now normalizes/whitelists mercenary fire modes and formations on the server, and clamps `followDistance` to a safe range before creating an order revision. This blocks malformed overlay payloads from creating unusable order state without changing normal UI commands. Scope is limited to mercenary command validation plus project-map/changelog updates inside `media/`.

## Stage386 note

Client-side hired mercenary execution was unified with the working point-order path. `Follow` now queues a direct preemptive Move task toward a live bodyguard slot around the player, and stale follow-slot Move tasks are no longer considered compliant after the player moves. Delegated commands (`Patrol`, `Loot`, `LootHouse`, `LootBodies*`, `RearmHere`) first move the squad to the cursor anchor, then hand off to legacy patrol/search/loot/rearm behavior. This stage does not change server validation, hire/payment, bases, Black Market, global war, persistence, Java/classes, graphics, or `media/ProjectZomboid`.

## Stage387 note

Client-side hired mercenary execution now keeps direct player orders out of the old Companion/CompanionGuard program handoff. This addresses the softlock pattern where the server accepted Follow/Guard/Patrol and the client queued immediate tasks, but legacy companion movement/program state could still compete with the direct order path. `Follow` uses wider real formation slots for non-close formations; upper point commands (`Hold`, `Guard`, `Return`, `WatchSector`, `BackToBack`) use per-member anchor slots instead of driving every NPC to the exact same clicked tile. `Patrol` no longer falls back to the legacy companion director after reaching the anchor; it stays in a lightweight player-command patrol loop around the clicked point. Scope is limited to `NPCUpdateBridge.lua` and project-map documentation inside `media/`; no server validation, hire/payment, Black Market, bases, global war, persistence, Java/classes, graphics, or `media/ProjectZomboid` changes.

## Stage388 note

Narrow follow-up on the working Stage387 mercenary order lane. `LootHouse` / "search house" is now a house-only command: the client warns outside buildings and the server rejects outside-building anchors before throttle/orderRevision creation. `HoldFire` now physically clears NPC hand items/visual hand variables when the fire-mode order is applied, instead of only denying shooting tasks. Manual loot/check-corpse/rearm actions now use the loot/search bump animation rather than plain idle while scanning/looting. A direct-order animation reset was added only on new/reapplied direct mercenary orders to clear stuck movement/bumptype state before the next command takes over. Stage387 direct movement/order behavior is otherwise preserved.

## Stage389 note

Hired mercenaries now have a safe ambient idle layer. When a mercenary is settled, has no task, is not pathfinding/moving, has no active threat, and has waited after the last player order, it may play low-priority idle animations: Smoke, Shrug, ShiftWeight, SitAction, SitRubHands, ChewNails, WipeBrow, or PullAtCollar. Search/loot/rearm orders may also play search-style ambient animations such as LootLow, Loot, Forage, or SitAction after reaching the anchor if no immediate loot task is available. These are animation-lane tasks with movement/combat guards and timeouts, so they should not interfere with Follow/Guard/Hold/Patrol direct movement.


## Stage390 note

Narrow follow-up on Stage389. `LootHouse` now has a direct in-house search lane after arrival: mercenaries pick valid points inside the clicked building/room and play vanilla bump animations such as LootLow, Forage, Loot, ReadBook, WipeBrow, Shrug, Smoke, and SitAction instead of falling back to the old companion house-search program that could leave them walking crouched. Player-command time/ambient/search animations now clear crouch/sneak/aim/moving/pathfind animation variables on completion and on new direct-order reset, so Follow/Move/Guard can recover from a half-crouched search pose. Fire-mode overlays now apply equipment immediately on the client: HoldFire stores the previous hand weapon and clears hands, while FireAtWill/Defensive/ReturnFire/DangerClose/Suppress can re-equip a stored/inventory firearm. Direct mercenary orders allow nearby combat preemption for valid fire modes, so zombies/enemies can interrupt ambient/search/movement tasks for shooting/melee without changing the Stage387 movement lane when no threat exists.

## Stage391 note

Combat preemption for hired mercenaries is now hold-position by default. FireAtWill/Defensive/ReturnFire/DangerClose/Suppress may interrupt a direct player order for stationary aim/shoot/reload/equip or immediate close-contact shove/hit, but generated Move/GoTo/chase/melee-approach tasks are filtered out so the squad does not abandon Follow/Guard/Hold/Patrol/SearchHouse positions. If the combat brain wanted to chase, the NPC instead gets a short FaceLocation task to stop and face the threat. The working Stage387 direct movement lane is otherwise preserved.


## Stage392 note

Hired mercenary friendly-fire rules were added without changing the working direct movement lane. The hiring player and same-owner hired mercenaries are now treated as friendly for mercenary firearm/melee damage, and player hits against owned mercenaries are restored/ignored on the client to prevent owner/squad friendly-fire punishment. If a hostile player/NPC/zombie damages a hired mercenary, all mercenaries owned by the same player receive that attacker as a priority retaliation target and may return fire from their current positions. Retaliation uses the Stage391 hold-position overlay: aim/shoot/reload/equip and face-target are allowed, but chase/move-to-enemy behavior is still blocked. The target is cleared after death/disappearance/timeout and normal zombie/enemy targeting resumes.


## Stage393 note

Hired mercenary owner-protection zombie targeting was added without changing the working Follow/Guard/Hold/Patrol/SearchHouse movement lane. Direct-combat mercenaries now bypass the generic combat-scan scheduler gate and run a small owner-threat scan when FireAtWill/Defensive/ReturnFire/DangerClose/Suppress is active. Zombies that are actively targeting the hiring player, or already inside the owner's immediate danger bubble, are treated as priority shoot-in-place targets. The Stage391 hold-position combat filter still blocks chase/Move/GoTo tasks, so mercenaries may aim/shoot/reload/face the threat but should continue following/holding position rather than pursuing zombies. Ranged hold-position combat tasks are explicitly allowed to remain compliant with strict player orders so Follow is not immediately reapplied over valid Aim/Shoot tasks.

## Stage433 note

Java pathfinding verification and B41 movement-state guard. The optional Java path patch is now distributed as `media/java/FactionsConfrontationJavaPathPatch.jar` inside the mod and is intended to be loaded first through `ProjectZomboid64.json` classpath shadowing. The jar contains only `zombie.vehicles.PathFindBehavior2*` and prints a canary line to `console.txt` when the override is actually loaded. Lua movement changes are limited to `NPCMovementStabilityBridge.lua`: B41 `WalkToward`/`PathFind` state gets a short defer window before a new path request is issued, reducing `WalkTowardState but path2 != null` bursts without changing faction/base/quest/economy/save schemas.

## Stage438 note — Java engine render+path refactor branch

Stage438 is an engine-only optimization branch. It does not modify NPC gameplay Lua, hired mercenary orders, checkpoints, faction war logic, bases, contracts, Black Market, persistence, network protocol, or save format.

The patch installs optimized Build 41 Java classes into the Project Zomboid root, BanditsJava-style, instead of using jar/classpath shadowing. This avoids the Stage433 bootstrap/classpath failure path.

Root-install classes included:
- `zombie/vehicles/PathFindBehavior2*.class`
- `zombie/core/SpriteRenderer*.class`
- `zombie/core/sprite/GenericSpriteRenderState.class`

Optimization scope:
- pathfinding request dedupe / active-path dedupe / direct-line shortcut / bounded local async worker in `PathFindBehavior2`;
- larger preallocated draw command buffers in `GenericSpriteRenderState`;
- larger SpriteRenderer mapped VBO/ring-buffer segment and larger StateRun preallocation to reduce zoom-out/dense-scene allocation/flush spikes.

Explicitly excluded:
- no `PolygonalMap2.class`;
- no `IsoZombie.class`;
- no `IsoTree.class`;
- no broad `media/ProjectZomboid` mod-folder shadow tree;
- no Lua gameplay refactor.


## Stage440 — city pressure path2 fuse v2 (2026-06-09)
- Усилен B41 `WalkToward/path2` fuse без изменения команд наёмников, блокпостов, баз, контрактов и сетевого/save-формата.
- Добавлен brain-level path2 fuse: если NPC уже находится в WalkToward/PathFind и новая не-критическая цель близка к уже активному маршруту, новый path2 не создаётся, а используется текущий активный маршрут.
- Ужесточён adaptive governor под цель 60 FPS: ниже 59 FPS система раньше входит в HIGH/CRITICAL/PANIC и сильнее режет ambient/path/marker/sense/LOS бюджеты.
- Combat/player-order/self-preserve/rescue movement оставлены вне нового fuse.
- Stage440 не включает SpriteRenderer/OpenGL и не меняет опасные gameplay-системы.


### Stage441 touched areas
- Runtime movement pressure fuse: `media/lua/shared/NPCCore/NPCMovementStabilityBridge.lua`
- Adaptive scheduler/governor: `media/lua/shared/NPCCore/NPCWorkSchedulerBridge.lua`
- Root engine install: `INSTALL_TO_PROJECTZOMBOID_ROOT/zombie/vehicles/PathFindBehavior2*.class`


### Stage442 touched areas
- Root render install: `INSTALL_TO_PROJECTZOMBOID_ROOT/zombie/core/SpriteRenderer*.class`
- Root render install: `INSTALL_TO_PROJECTZOMBOID_ROOT/zombie/core/sprite/GenericSpriteRenderState.class`
- No Lua gameplay, save/network, IsoZombie, PolygonalMap2, or ZombieGroupManager changes.


### Stage443 touched areas
- Root pathfinding install: `INSTALL_TO_PROJECTZOMBOID_ROOT/zombie/vehicles/PathFindBehavior2.class`
- Root render install: `INSTALL_TO_PROJECTZOMBOID_ROOT/zombie/core/SpriteRenderer$RingBuffer.class`
- Root render install: `INSTALL_TO_PROJECTZOMBOID_ROOT/zombie/core/sprite/GenericSpriteRenderState.class`
- No Lua gameplay, save/network, IsoZombie, PolygonalMap2, ZombieGroupManager, or ZombiePopulationManager changes.


### Stage444 touched areas
- Root pathfinding install: `INSTALL_TO_PROJECTZOMBOID_ROOT/zombie/vehicles/PathFindBehavior2.class`
- Root render install: `INSTALL_TO_PROJECTZOMBOID_ROOT/zombie/core/SpriteRenderer$RingBuffer.class`
- Root render install: `INSTALL_TO_PROJECTZOMBOID_ROOT/zombie/core/sprite/GenericSpriteRenderState.class`
- No Lua gameplay, save/network, IsoZombie, PolygonalMap2, ZombieGroupManager, or ZombiePopulationManager changes.


### Stage445 touched areas
- Root character engine install: `INSTALL_TO_PROJECTZOMBOID_ROOT/zombie/characters/IsoGameCharacter.class`
- Purpose: suppress repeated `WalkTowardState but path2 != null` warning spam while preserving the original `setPath2(null)` cleanup.
- No Lua gameplay, save/network, IsoZombie, PolygonalMap2, ZombieGroupManager, ZombiePopulationManager, attack/damage/infection/senses, or render-state logic changes.

### Stage446 touched areas
- Runtime streaming governor: `media/lua/shared/NPCCore/NPCStreamingRuntimeBridge.lua`
- SP activation scan gate: `media/lua/server/NPCServer/NPCWorldDirectorBridge.lua`
- Scope: singleplayer street/chunk streaming pressure only. No Java/classes, save/network/ModData, hired mercenary command logic, bases, contracts, checkpoints, Black Market economy, or combat/damage rules changed.

## Stage447 — Door open fallback + NPC vanilla-zombie brain guard

Date: 2026-06-10

Changed files:
- `media/lua/shared/NPCActions/NPCActionDestroyBridge.lua`
- `media/lua/server/NPCServer/NPCClientCommandsServerBridge.lua`
- `media/lua/client/NPCClient/NPCUpdateBridge.lua`
- `media/PROJECT_MAP.md`
- `media/PROJECT_MAP_UPDATE.md`

Purpose:
- make living/materialized NPCs open normal doors before using the old breach/destroy task;
- keep breach damage only for barricaded/blocked doors and generic thumpable objects;
- prevent a marked live NPC from briefly falling back into vanilla zombie target/lunge/attack behavior while still showing an NPC marker.

Implementation notes:
- `DestroyObject` now routes usable door targets through `OpenDoorObject` first on the server;
- client-side Destroy action also tries `OpenDoor` first for normal door objects;
- live NPC update now clears vanilla zombie target/aggro/lunge state through `EnforceLiveNPCNotVanillaZombie`;
- the guard is applied on mark-as-NPC, before zombie/NPC update separation, when physical LOD skips a frame, and when the NPC is outside the light cache.

Safety notes:
- no Java/class changes;
- no save/network/ModData schema changes;
- no faction strategy, mercenary orders, checkpoints, bases, contracts or Black Market logic changed;
- NPC combat tasks still use the mod's own task/brain/faction checks; only vanilla zombie brain targeting is suppressed for live NPC actors.


### Stage448 touched areas
- Path budget/governor: `media/lua/shared/NPCCore/NPCWorkSchedulerBridge.lua`
- Deferred movement path start: `media/lua/shared/NPCCore/NPCMovementStabilityBridge.lua`
- Density/portal navigation cost: `media/lua/shared/NPCCore/NPCNavigationPerformanceBridge.lua`
- Squad route templates: `media/lua/shared/NPCCore/NPCSquadCoarseWaypointsBridge.lua`
- Vanilla zombie path pressure class: `media/ProjectZomboid/zombie/vehicles/PathFindBehavior2.class`

## Stage449 — Delicate Runtime Performance Governor

Added a conservative performance pass focused on diagnostics and non-gameplay throttling:

- `NPCCore/NPCPerformanceTelemetryBridge.lua` — runtime-only pressure telemetry for path queue, streaming pressure and navigation queue counters. Disabled logging by default; no save/network schema changes.
- `NPCCore/NPCWorkSchedulerBridge.lua` — records path queue/path cooldown/budget counters for telemetry. No behavior API changes.
- `NPCCore/NPCNavigationPerformanceBridge.lua` — exposes portal/repair queue diagnostics and records portal wait/release counters. No combat/pathfinding behavior changes.
- `NPCClient/NPCDebugMapMarkersBridge.lua` — prefers scheduler-driven hook maintenance instead of direct every-frame OnTick when scheduler is available.
- `NPCClient/NPCDebugMapNPCMarkersBridge.lua` — marker sync/map-open requests are load-aware and scheduler-preferred.
- `NPCServer/NPCWorldDirectorBridge.lua` — debug-map update dirty-sync suppresses duplicate marker updates for unchanged payloads with a periodic force interval. Gameplay ModData and marker formats are unchanged.

Protected systems: mercenary commands, follow/guard/hold/patrol, bases, checkpoints, contracts, Black Market, combat/damage/infection, save/ModData schema, Java classes.

## Stage452/453 — Spatial Query Hardening + World Director Calendar Queue

Date: 2026-06-10

Changed files:
- `media/lua/shared/NPCCore/NPCSpatialIndexBridge.lua`
- `media/lua/shared/NPCBehavior/NPCBrainDirectorBridge.lua`
- `media/lua/shared/NPCCore/NPCPerformanceTelemetryBridge.lua`
- `media/lua/server/NPCServer/NPCWorldDirectorBridge.lua`
- `media/ProjectZomboid/FC_STAGE452_453_CHAIN_RU.txt`

Purpose:
- reduce Lua-side nearby-threat/friend scan allocation pressure by reusing spatial-index scratch buffers;
- keep the same NPC brain decisions while making the hot spatial queries bounded and measurable;
- spread non-critical world-director maintenance jobs over time with a runtime-only calendar queue so several heavy periodic jobs do not collide in the same tick.

Implementation notes:
- `NPCBrainDirectorBridge` now uses `GetNearbyAllInto` / `GetNearbyNPCsInto` numeric-buffer loops for selected threat/friend queries;
- `NPCSpatialIndexBridge` exposes query diagnostics/reset helpers for telemetry;
- `NPCWorldDirectorBridge.CalendarDue()` gates non-critical maintenance tasks: battle remains refresh, periodic activation scan, influence refresh, battlefield clutter cleanup, urban cover props, physical bubble snapshot, strategic compact, and virtual map heartbeat;
- calendar queue is runtime-only and has a per-tick task cap/defer window;
- telemetry samples now include spatial-query and world-calendar counters.

Safety notes:
- Stage451 squad formation/leader-path steering was deliberately skipped;
- hired mercenary Follow/Guard/Hold/Patrol logic is not modified;
- no Java/class changes;
- no save/network/ModData schema changes;
- no bases, checkpoints, contracts, Black Market, combat/damage/infection, faction strategy or low-level PZ pathfinding changes.


## Stage454 — Safe CPU/GC Micro Optimizations

Date: 2026-06-10

Changed files:
- `media/lua/shared/NPCCore/NPCSpatialIndexBridge.lua`
- `media/lua/shared/NPCCore/NPCInterestManagerBridge.lua`
- `media/lua/shared/NPCCore/NPCWorkSchedulerBridge.lua`
- `media/lua/shared/NPCCore/NPCNavigationPerformanceBridge.lua`
- `media/lua/shared/NPCCore/NPCRoadNavBridge.lua`
- `media/ProjectZomboid/FC_STAGE454_CHAIN_RU.txt`

Purpose:
- apply low-risk CPU/GC micro-optimizations without changing gameplay rules;
- avoid unnecessary sqrt/division work in radius and road-corridor checks;
- reduce queue front-shift cost by replacing repeated `table.remove(queue, 1)` style handling with mark-and-compact processing;
- cache adjusted scheduler budgets once per tick/kind.

Safety notes:
- Stage451 squad formation/leader-path steering remains skipped;
- hired mercenary Follow/Guard/Hold/Patrol logic is not modified;
- no Java/class changes;
- no save/network/ModData schema changes;
- no bases, checkpoints, contracts, Black Market, combat/damage/infection, faction strategy or low-level PZ pathfinding changes.

## Stage455 — SP Hitch Profiler + Hard Streaming Quarantine

Added a diagnostics-only `NPCHitchProfilerBridge.lua` that records real frame gaps to `NPC_FACTIONS.log` as `HITCH/frame_hitch` events with streaming pressure, path queue, world calendar, virtual/physical group, marker, base/checkpoint and nearby vehicle context. Added a hard singleplayer streaming quarantine above the world director: optional strategic/world/marker/director-brain tasks are deferred during SP warmup or HIGH/CRITICAL streaming pressure, while hired mercenary orders, Follow/Guard/Hold/Patrol, physical cleanup, proxy LOD safety, bases/contract data, Black Market data, Java/classes and save/network schemas remain untouched.


## Stage456 — Bootstrap/Marker/Virtual World Gate
- SP warmup/streaming gate now defers virtual-world bootstrap, marker sync/heartbeat, base economy reservations, base-owned repair protection and optional director events.
- Base/zone marker tasks are not queued during the bootstrap gate.
- Normal/low runtime task queues wait during quarantine; high priority keeps only a tiny safety budget.
- No changes to mercenaries, Follow/Guard/Hold/Patrol, combat, Java/classes, Black Market, contracts, save/network/ModData schema.


## Stage457 note

Residual SP hitches after Stage456 were correlated with base-camp growth and vanilla vehicle/chunk streaming while `physicalGroups`, `pathQueue`, `spawnQ`, `taskQ` and `markerQ` stayed near zero. Stage457 closes the base-camp/bootstrap leak: base discovery, base presentation, building migration and base/zone marker bursts now obey the SP bootstrap gate. Strategic virtual-group creation/update also has an additional gate. This is a runtime deferral only; it does not alter save schemas, contracts, Black Market, Java/classes, combat, or mercenary command behavior.


## Stage458 note

Stage458 fixes a diagnostics-only `NPCHitchProfilerBridge` vehicle-list bounds issue and adds a post-gate smoother. After SP bootstrap quarantine opens, optional base/virtual/road/marker work is no longer allowed to resume in one burst; it is released by small category windows and per-tick optional task budgets. Critical player-facing systems, hired mercenary markers/orders, Black Market/contract markers, combat and physical nearby NPCs are not gated by this smoother.


## Stage459 — Optimized Defaults for SP + COOP

- Updated `media/sandbox-options.txt` defaults to match the Stage455-458 runtime governor stack.
- Updated `NPCLegacySettingsBridge.Defaults` fallback values so no-sandbox/fresh-world behavior matches the optimized profile.
- Lowered sandbox minimums for selected performance/base/spawn settings that previously produced IntegerConfigOption spam in COOP logs.
- Reduced default burst pressure from virtual world bootstrap, BaseCamp discovery, road battles, marker sync, influence maintenance, task queues and network snapshot sync.
- No mercenary/order/combat/Black Market/contract/Java/save schema changes.
