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
