# PROJECT_MAP_UPDATE

## 2026-05-05 — localization menu cleanup patch

Changed files:
- `Translate/EN/Sandbox_EN.txt`
- `Translate/RU/Sandbox_RU.txt`
- `Translate/EN/IG_UI_EN.txt`

Summary:
- Normalized Bandits Remaster sandbox category labels so `Bases` and `Factions` use the same short numbered style as other server menu sections.
- Russian sandbox translation now covers the old/vanilla Bandits menu block: general settings, clan entries, AI behaviour options, spawn parameters, weapon chances and group descriptions.
- English NPC speech lines were rewritten into clean tactical callouts based on the Russian tactical speech set; old profanity/taunt lines and malformed speech assignment were removed.

Compatibility notes:
- Translation keys were not renamed.
- Lua logic, network commands and sandbox option IDs were not changed.
- Only visible localization text was changed.

## 2026-05-09 — door/equip log-spam guard patch

Changed files:
- `PROJECT_MAP.md`
- `media/lua/client/BanditUpdate.lua`
- `media/lua/server/BanditClientCommands.lua`
- `media/lua/shared/Bandit.lua`
- `media/lua/shared/ZombieActions/ZAEquip.lua`

Summary:
- Added method-existence guards before door/barricade checks so missing Java/Lua exposed methods are not called through `pcall` and logged as runtime errors.
- Guarded `UpdateZombies` execution so a single bad zombie state cannot spam the whole `OnZombieUpdate` path.
- Secondary hand equip now clears impossible secondary items when the primary item requires both hands instead of logging every update.
- Magazine death-drop ammo setup now uses the magazine's existing max ammo and avoids calling `setMaxAmmo`, which could log Java `IllegalArgumentException` with some firearm mods.

Compatibility notes:
- No API or data format changes.
- Door opening, weapon selection, persistence and network command names are unchanged.
- Changes only suppress invalid/impossible operations that were already failing in logs.

## BlackMarket static hard-fix
- Black market contacts are static service markers/interaction points, not IsoZombie/IsoGameCharacter entities.
- Added guarded static sprite overlay using `media/ui/black_market_service.png`; if UI base classes are missing, only the overlay is skipped.
- Server cleanup now removes legacy black-market NPC bodies and stale black-market Queue brains.
- `ZPBlackMarket.lua` is a no-op for stale saves only.

## 2026-05-09 - Black market static click + faction guard

- Static black market context menu now falls back to player proximity, because the drawn sprite is not a real world object and right-click hit squares can be shifted.
- Wrapped static contact lookup in context-menu handler to prevent UI error windows from blocking the menu.
- Added service-brain guard in BanditFaction so legacy black market brains cannot be treated as enemy faction targets.
- Hardened BanditUtils.GetZombieID against non-zombie/world-object context menu inputs.

## BlackMarket Static Overlay Click Fix
- BanditBlackMarketClient now shares one menu builder between vanilla world context and static overlay context.
- Added overlay right-click fallback: if the UI sprite receives the click before world context menu, it opens the Black Market menu by proximity.
- Kept server-side distance validation unchanged; visual sprite remains non-NPC/non-IsoZombie.
- Added duplicate-menu guard on the context object.
- Added optional global OnRightMouseUp fallback where available, so the market menu can open even if the overlay or another UI layer prevents the vanilla world-object context event from firing.
- Added short duplicate-open guard to avoid duplicate Black Market root entries when both paths fire on the same click.

## BlackMarket static click admin/accesslevel guard
- Removed persistent `context.__BanditBlackMarketAdded` guard from the static black-market menu path; PZ can reuse the same `ISContextMenu` after admin/access-level changes, which could make the menu silently skip adding the option.
- Added current-options scan to prevent duplicate Black Market entries without poisoning reused context objects.
- Manual overlay right-click now explicitly makes the created context menu visible and brings it to front.
- Added a light access-level watcher that clears the short click throttle and refreshes contacts after `/setaccesslevel` changes.


## BlackMarket static virtual movement
- Kept the working static black-market overlay/context-menu path unchanged.
- Black-market contacts now freeze while any player is close enough to render/interact with the static service sprite.
- When no players are near, the contact switches to virtual state and advances its saved x/y position on a slow server tick.
- Virtual movement prefers BanditRoadNav road targets when available and remains bounded around the original contact area.
- No NPC, IsoZombie, faction, combat, mercenary, or persistent-NPC logic is reintroduced.

## 2026-05-09 — Black Market admin click hardening

- Fixed static black-market click handling after `/setaccesslevel ... admin`.
- Manual overlay/global right-click fallback now clears stale pooled `ISContextMenu` options only after a valid nearby black-market contact is found.
- Added a short access-level transition refresh window and overlay recreation so admin promotion/demotion does not leave a stale UI element.
- Added last-known nearby contact fallback for the static service object; server-side distance/contact validation remains authoritative.


## 2026-05-09 — Black Market admin top-overlay click repair

- Fixed the remaining `/setaccesslevel ... admin` click-loss path by making the static overlay handle direct sprite hit-testing before admin/debug UI can consume the right-click.
- Overlay now consumes right-click only when the cursor is over the drawn black-market sprite; all other mouse events pass through to normal UI/world handling.
- Added screen-space contact hit-test shared by overlay and global fallback, including last-known contact fallback.
- Menu creation can now use the exact clicked contact instead of relying only on world-object/proximity context after access-level UI rebuilds.
- Server-side deals, virtual movement, prices, commands, and contact data format were not changed.

## 2026-05-10 — pathfinding FPS guard patch

Changed files:
- `media/lua/client/BanditUpdate.lua`
- `media/lua/shared/BanditMovementStability.lua`
- `media/lua/shared/PROJECT_MAP.md`
- `media/lua/shared/PROJECT_MAP_UPDATE.md`

Summary:
- Added per-zombie cooldown for normal zombie path requests toward bandit NPCs, preventing every nearby zombie from reissuing the same `pathToLocationF` request every update.
- Hardened zombie-vs-bandit targeting against missing/invalid closest-bandit results before reading `enemy.dist`.
- Changed bandit movement path throttling so `force=true` no longer bypasses same-target cooldowns completely.
- Added same-target path cooldown and failed-path backoff to reduce repeated `PathFindBehavior2` / `pathToLocationF` requests after path failures.
- Reset path failure backoff when a bandit path succeeds or real movement progress is observed.
- Added `PROJECT_MAP.md` with the current performance/pathing navigation map for future debugging.

Compatibility notes:
- No task names, network commands, ModData persistence formats, faction logic or spawn formats were changed.
- Existing `Move` and `GoTo` actions still delegate to `BanditMovementStability`; this patch only limits repeated equivalent path requests.
- Normal zombies can still target and attack bandits; only repeated explicit path requests to the same bandit/location are throttled.

## 2026-05-10 — merged pathfinding FPS guard with black-market world-prop UI patch

Changed files:
- `media/lua/client/BanditBlackMarketClient.lua`
- `media/lua/client/BanditUpdate.lua`
- `media/lua/shared/BanditMovementStability.lua`
- `media/lua/shared/PROJECT_MAP.md`
- `media/lua/shared/PROJECT_MAP_UPDATE.md`
- `media/ui/black_market_world_prop*.png`

Summary:
- Merged the black-market world-prop UI patch with the pathfinding FPS guard patch.
- Verified there are no direct file overlaps between the UI changes and the pathfinding throttle changes.
- Kept black-market visuals client-side: world props are created from client contact data, tagged as black-market visual props, and cleaned on save/disconnect.
- Kept pathfinding throttles independent from UI state: zombie-vs-bandit cooldowns use `BanditZombieBanditPath*` ModData keys, while bandit path backoff remains under `brain.ai.pathThrottle`.
- Added project-map notes for the black-market world-prop client path.

Compatibility notes:
- No network command names, server handlers, saved contact format, task names or faction data were changed by the merge.
- The UI patch does not call bandit movement/path APIs, and the FPS patch does not read or mutate black-market UI/world-prop state.
- Existing black-market context menu behavior remains event-driven through `OnFillWorldObjectContextMenu` and global right-click fallback; the old always-on-top overlay is reset instead of recreated.

## 2026-05-10 — adaptive scheduler and global path budget patch

Changed files:
- `media/lua/client/BanditUpdate.lua`
- `media/lua/shared/BanditLegacySettings.lua`
- `media/lua/shared/BanditMovementStability.lua`
- `media/lua/shared/BanditWorkScheduler.lua`
- `media/lua/shared/PROJECT_MAP.md`
- `media/lua/shared/PROJECT_MAP_UPDATE.md`

Summary:
- Added an adaptive FPS/crowd pressure layer to `BanditWorkScheduler` so optional AI, utility, zombie reaction, spawn and path budgets shrink when FPS is low or physical NPC/zombie counts are high.
- Added separate global per-tick budgets for bandit path requests and normal-zombie path requests toward bandits.
- Routed bandit `Move`/`GoTo` path starts through the global path budget after the existing per-NPC same-target cooldown/backoff passes.
- Routed normal zombie pathing toward bandits through the global zombie-path budget before recording the per-zombie path timestamp.
- Added sandbox/default keys for path budgets and adaptive scheduler thresholds without changing existing task, brain, ModData or network command formats.
- Kept debug performance summary disabled by default; if enabled, it logs one aggregated `[BanditsPerf]` line per configured interval instead of per-NPC spam.

Compatibility notes:
- Existing AI programs, task names, movement actions and save data remain unchanged.
- Combat work is protected from the harshest budget cuts; idle/zombie reaction work is throttled first.
- If `AIWork_Enabled` is disabled by settings, existing AI bypass behavior remains unchanged.

## 2026-05-10 — perception/LOS budget patch

Changed files:
- `media/lua/shared/BanditAIVision.lua`
- `media/lua/shared/BanditLegacySettings.lua`
- `media/lua/shared/BanditWorkScheduler.lua`
- `media/lua/shared/PROJECT_MAP.md`
- `media/lua/shared/PROJECT_MAP_UPDATE.md`

Summary:
- Added separate adaptive budgets for AI perception scans and LOS/`CanSee` checks.
- Added a short in-memory LOS cache in `BanditAIVision` so repeated observer-target checks within a small window reuse the previous result instead of calling `CanSee` again.
- Added a per-scan cap for expensive threat candidates in `FindNearestThreat(...)`; cheap distance/faction filtering still runs before the cap is consumed.
- Kept current threat and remembered threat fallback when the sense budget is exhausted, so NPCs do not forget enemies just because optional scanning was deferred.
- Added sandbox/default keys for sense budget, LOS budget, threat scan cooldown, candidate cap and LOS cache size/time.

Compatibility notes:
- No task names, brain save format, ModData keys, network commands, UI files or spawn formats were changed.
- LOS cache is session-local under `BanditAIVision._LOSCache`; it is not written to persistent brain data.
- Close-range checks can still bypass the LOS budget to avoid making melee/combat feel unresponsive.

## 2026-05-10 — soft physical LOD and adaptive zombie cache patch

Changed files:
- `media/lua/client/BanditUpdate.lua`
- `media/lua/client/BanditZombie.lua`
- `media/lua/shared/BanditLegacySettings.lua`
- `media/lua/shared/BanditWorkScheduler.lua`
- `media/lua/shared/PROJECT_MAP.md`
- `media/lua/shared/PROJECT_MAP_UPDATE.md`

Summary:
- Connected the existing `BanditAILODTrader` distance/importance logic to the physical NPC update path through `BanditWorkScheduler.AllowPhysicalUpdate(...)`.
- Added a soft frame gate for far, non-critical materialized bandits so they skip full visual/utility/task maintenance on some `OnZombieUpdate` calls instead of running the complete AI stack every time.
- Critical NPCs bypass the LOD gate: active combatants, targeted/attacked bandits, companions/guards/hired NPCs, black-market/non-combat service NPCs and locked combat/recovery tasks keep immediate updates.
- Added a dedicated physical-update budget that also shrinks under adaptive low-FPS/high-crowd pressure.
- Made `BanditZombie.CacheLight*` rebuild interval adaptive under high zombie counts or low FPS, reducing repeated loaded-zombie-list scans during heavy scenes.
- Added default tuning keys for physical LOD intervals and adaptive zombie-cache rebuild intervals.

Compatibility notes:
- No NPCs are deleted, dematerialized, teleported or converted to virtual state by this patch.
- No task names, brain save format, ModData keys, network commands, UI files or spawn formats were changed.
- The LOD gate only skips optional per-frame maintenance for non-critical far physical NPCs; close/combat/important NPCs keep old responsiveness.

## 2026-05-10 — adaptive physical dematerialization patch

Changed files:
- `media/lua/server/BanditWorldDirector.lua`
- `media/lua/shared/BanditLegacySettings.lua`
- `media/lua/shared/PROJECT_MAP.md`
- `media/lua/shared/PROJECT_MAP_UPDATE.md`

Summary:
- Added adaptive physical-group dematerialization using the existing `BanditWorldDirector.DematerializeFarPhysicalGroup(...)` path instead of introducing a new save format.
- Reduced default non-critical physical despawn radius from 520 to 420 tiles, with high-load and critical-load radii of 360 and 300 tiles.
- Preserved important groups longer: active battles, bounty/leader groups and economy convoys use a separate important radius.
- Added a short minimum physical age before dematerialization so a freshly materialized group is not immediately converted back to virtual state.
- Split physical cleanup cadence from activation cadence: far-group cleanup can run more often under load without increasing new group activations.
- Recorded `group.materializedAt` when a group becomes physical so the dematerialization age guard is stable across updates.

Compatibility notes:
- No brain task format, network command name, persistent NPC profile format or marker schema was changed.
- The patch only uses existing virtual-group and object-cleanup paths; it does not add a new runtime object type.
- Groups with pending spawn batches are not dematerialized until their queued materialization completes.
- Reactivation radius remains lower than dematerialization radius, preserving hysteresis and avoiding rapid physical/virtual ping-pong.
## 2026-05-10 — spawn queue retry/backoff patch

Changed files:
- `media/lua/server/BanditSpawnQueue.lua`
- `media/lua/shared/BanditLegacySettings.lua`
- `media/lua/shared/PROJECT_MAP.md`
- `media/lua/shared/PROJECT_MAP_UPDATE.md`

Summary:
- Added per-group duplicate protection for queued materialization batches so one virtual group cannot accumulate multiple follow-up spawn entries.
- Added retry backoff for queued spawn batches that return zero spawns or throw during `SpawnGroup`, preventing repeated attempts every tick when the target area unloads mid-materialization.
- Added configurable retry limits and delay bounds for the spawn queue.
- When a queued follow-up batch is dropped after repeated failures, the owning group now clears `spawnPending` / `spawnQueued` and returns to `physical` state instead of staying permanently stuck as a half-spawned group.
- Reworked queue compaction/counting to count only live entries, keeping skipped delayed retries from being lost when later entries complete.

Compatibility notes:
- The materialization event format, group member format, brain data and network commands are unchanged.
- Already-spawned physical NPCs are kept; only the missing queued tail of a repeatedly failing batch is dropped after the configured retry limit.
- This patch does not change initial group activation rules or black-market UI behavior.


## 2026-05-10 - Ultra pathfinding + zoom FPS optimization

- Изменён `media/lua/client/BanditUpdate.lua`:
  - `ApplyVisuals()` больше не пересобирает модель NPC каждый `OnZombieUpdate`; визуалы применяются один раз на сигнатуру внешности и не чаще 1 раза за 5 секунд.
  - `ManageTorch()` получил throttling по FPS/zoom-load, чтобы NPC с факелами не добавляли пачку light-source объектов каждый update.
  - `BanditUtilityAI.Update()` защищён от повторного запуска в один scheduler tick.
  - `ManageCombat()` теперь сначала собирает дешёвый ограниченный список ближайших кандидатов, а дорогие `CanDetect/CanSee/LOS` вызывает только для лимитированного набора.
  - Лимит кандидатов автоматически ужимается при низком FPS и при сильном zoom-out.
- Изменён `media/lua/shared/BanditWorkScheduler.lua`:
  - Добавлен учёт camera zoom в load-state.
  - При zoom-out scheduler переводится в HIGH/CRITICAL режим даже при небольшом числе NPC.
  - Снижены бюджеты `combat/utility/zombie/marker/physical/path/zombiePath/sense/los`.
  - Critical combat NPC теперь тоже может получать физический frame-throttle при zoom-out/critical FPS, кроме black market/non-combat NPC.
- Изменён `media/lua/shared/BanditMovementStability.lua`:
  - Усилены path cooldown/backoff и уменьшен target-search radius.
  - При zoom-out/critical load path-запросы дополнительно разрежаются.
- Добавлен builder `BanditsJavaPathfinding_B41_builder_v5_ULTRA`:
  - заменяет только `PathFindBehavior2.class`, без `PolygonalMap2.class`;
  - усиливает pending/active path dedupe;
  - расширяет direct-line shortcut;
  - добавляет dedupe/direct для `pathToCharacter`;
  - добавляет micro-cooldown постановки zombie path request в queue.

## 2026-05-10 - v6 cumulative pathfinding/memory optimization

Changed files:
- `media/lua/client/BanditUpdate.lua`
- `media/lua/shared/BanditMovementStability.lua`
- `media/lua/shared/BanditSpatialIndex.lua`
- `media/lua/shared/BanditWorkScheduler.lua`
- `media/lua/shared/PROJECT_MAP_UPDATE.md`
- `BanditsJavaPathfinding_B41_builder_v6_CUMULATIVE/*`

Summary:
- Kept all v5 ULTRA changes and added v6 memory/buffer optimizations on top.
- Added reusable temporary buffers for combat candidate scans, escape scans and local zombie-attack crowd checks to reduce short-lived Lua table allocation during dense fights.
- Changed `ManageCombat()` candidate storage from per-candidate `{id, kind, d2}` tables to reusable parallel arrays stored on `brain.ai.combatCandidateBuffer`.
- Added `BanditSpatialIndex.GetNearby*Into(...)` APIs so hot callers can reuse caller-owned arrays instead of allocating a fresh result list every scan.
- Replaced spatial bucket string keys with packed numeric keys to reduce string concatenation and hash cost in the spatial index.
- Replaced `BanditMovementStability` path/memory keys with packed numeric keys and rewrote `FindReachableAround()` to use reusable queue/depth/seen buffers instead of allocating BFS node tables.
- Cached mover brain lookup inside `FindFreeAround()` instead of resolving it for every checked square.
- Added a scheduler PANIC state for severe FPS/zoom-out pressure; it further reduces budgets and increases intervals to prioritize frame stability over full AI responsiveness.

Compatibility notes:
- No task action names, ModData command formats, save schema, brain format or network command names were changed.
- Existing `BanditSpatialIndex.GetNearbyAll/GetNearbyBandits/GetNearbyZombies` APIs remain available; the new `*Into` APIs are additive.
- The Java builder still replaces only `PathFindBehavior2.class`; `PolygonalMap2.class` remains untouched.
- PANIC mode intentionally makes some NPC decisions less frequent under heavy load/zoom-out. If behavior feels too slow, tune `AIWork_PanicFPS`, `AIWork_PanicBudgetPercent` or restore the v5 scheduler.

## 2026-05-10 - v7 worker/governor cumulative optimization

Changed files:
- `media/lua/client/BanditUpdate.lua`
- `media/lua/shared/BanditWorkScheduler.lua`
- `media/lua/shared/BanditMovementStability.lua`
- `media/lua/shared/PROJECT_MAP_UPDATE.md`
- `BanditsJavaPathfinding_B41_builder_v7_WORKER_GOVERNOR/src/zombie/vehicles/PathFindBehavior2.java`
- `BanditsJavaPathfinding_B41_builder_v7_WORKER_GOVERNOR/tools/make_pathfinding_patch.ps1`
- `BanditsJavaPathfinding_B41_builder_v7_WORKER_GOVERNOR/build_pathfinding_patch.bat`
- `BanditsJavaPathfinding_B41_builder_v7_WORKER_GOVERNOR/README_RU.txt`
- `BanditsJavaPathfinding_B41_builder_v7_WORKER_GOVERNOR/docs/PROJECT_MAP_UPDATE.md`

Summary:
- Adds a bounded Java worker queue inside the patched `PathFindBehavior2` for local IsoZombie location paths on snapshot data only.
- The worker uses primitive arrays and a small 4-neighbor BFS grid; it never touches IsoZombie/IsoCell/IsoGridSquare from the background thread.
- Main thread captures a small standability grid, submits the local path task, polls the result for a short bounded window and falls back to the original engine queue when unavailable.
- Tightens the stable-60 governor: earlier HIGH/CRITICAL/PANIC thresholds, lower path/LOS/combat budgets, stricter zoom-out LOD, and gated visual/torch/combat scans.
- Keeps `PolygonalMap2.class`, ModData formats, task actions and network protocol unchanged.

Validation notes:
- Java builder still compiles only `PathFindBehavior2.java` against the local Project Zomboid runtime.
- If local worker behavior is too conservative or causes path hesitation, restore the previous generated `PathFindBehavior2.class` backup and keep the Lua governor if it improves zoom-out FPS.

## 2026-05-10 - v8 async budget scheduler cumulative patch

Changed files:
- `media/lua/client/BanditUpdate.lua`
- `media/lua/shared/BanditAsyncScheduler.lua`
- `media/lua/shared/BanditWorkScheduler.lua`
- `media/lua/shared/BanditMovementStability.lua`
- `media/lua/shared/PROJECT_MAP_UPDATE.md`
- `BanditsJavaPathfinding_B41_builder_v8_ASYNC_GOVERNOR/*`

Summary:
- Kept the v5/v6/v7 cumulative optimizations and added a Lua-side asynchronous budget scheduler on top.
- Added `BanditAsyncScheduler`, a bounded queue/slicing layer for expensive main-thread AI jobs. It is asynchronous by ticks, not unsafe native threading.
- Combat scans can be deferred under HIGH/CRITICAL/PANIC load instead of executing immediately inside every `OnZombieUpdate` pass.
- Movement recovery searches can be queued under load so multiple stuck NPCs do not all run expensive local recovery searches in the same frame.
- Queue tasks use TTL, key deduplication, stale NPC/task validation and bounded capacity to avoid runaway backlog.
- `BanditWorkScheduler.OnTick()` now processes async queue budgets after resetting per-tick counters.
- The Java builder remains the v7 worker/governor `PathFindBehavior2.class` patch; it still does not replace `PolygonalMap2.class`.

Compatibility notes:
- No ModData schema, network command, brain/task data format, action names or save data format was changed.
- Deferred combat results are applied only when the NPC is still valid and has no current action/task conflict.
- Deferred recovery results are applied only if the original movement task is still current.
- Async is disabled/tunable through `AIAsync_Enabled`, `AIAsync_MaxQueue`, `AIAsync_DeferCombatLevel` and related `AIAsync_*` legacy settings if present.


## 2026-05-10 - v9 OpenGL render relief cumulative patch

Changed files:
- `media/lua/client/BanditUpdate.lua`
- `media/lua/shared/BanditRenderRelief.lua`
- `media/lua/shared/BanditWorkScheduler.lua`
- `media/lua/shared/PROJECT_MAP.md`
- `media/lua/shared/PROJECT_MAP_UPDATE.md`
- `BanditsJavaRenderPath_B41_builder_v9_OPENGL_RELIEF/*`

Summary:
- Studied the `meshing-main` OpenGL sample and applied the parts that are safe for Project Zomboid Build 41: larger reusable buffers, fewer runtime allocations, fewer render flushes, and drawing less during zoom-out pressure.
- Added `BanditRenderRelief`, a reversible zoom/FPS render governor that feeds an additional render-load level into `BanditWorkScheduler`.
- Bandit shadows can be disabled under render pressure and restored when pressure clears.
- Bandit torch light spawning is skipped in critical/panic render pressure to avoid adding many dynamic light sources during zoom-out.
- Added optional temporary zoom-level capping under critical render pressure; original zoom level strings are cached and restored after stability returns.
- Added Java builder `BanditsJavaRenderPath_B41_builder_v9_OPENGL_RELIEF` that keeps the v8 PathFindBehavior2 optimization and additionally compiles patched `SpriteRenderer` / `GenericSpriteRenderState` classes.
- `GenericSpriteRenderState` now preallocates more `TextureDraw` slots and grows arrays by 2x to reduce zoom-out realloc/copy spikes.
- `SpriteRenderer.RingBuffer` uses a larger mapped VBO segment and larger preallocated state-run array to reduce batch flush/growth pressure.

Compatibility notes:
- This does not replace PZ's tile renderer with greedy meshing; that would require a large renderer rewrite and is not safe as a mod patch.
- `Core.class`, `PolygonalMap2.class`, `IsoZombie.class`, ModData, task data, save format and network protocol are unchanged.
- Java render patch is manual/no-rebuild-for-users after local compilation, like the previous Java pathfinding builder.
- If the dynamic zoom cap feels intrusive, disable it through `RenderRelief_ZoomCapEnabled=false` in legacy settings if available, or remove `BanditRenderRelief.lua` while keeping the Java buffer patch.


## 2026-05-10 - v9.1 RenderRelief Lua field hotfix

Changed files:
- `media/lua/shared/BanditRenderRelief.lua`
- `media/lua/shared/PROJECT_MAP_UPDATE.md`

Summary:
- Fixed repeated client log spam from `BanditRenderRelief.ApplyCharacterRelief()` on Build 41.78.19.
- Removed direct Lua assignment to `IsoGameCharacter.doRenderShadow`, because Kahlua treats the Java object as non-table for field writes and logs `attempted index of non-table`.
- Kept the safe parts of v9 render relief: zoom/FPS governor integration, torch-light throttling and Java renderer/path builder remain unchanged.

Compatibility notes:
- No ModData schema, network command, task data, save format, Java builder, `PathFindBehavior2`, `SpriteRenderer` or `GenericSpriteRenderState` changes.
- This hotfix intentionally disables the Lua-side bandit-shadow toggle instead of touching `IsoGameCharacter.class`.

## 2026-05-10 - v9.2 zoom wheel hotfix

Changed files:
- `media/lua/shared/BanditRenderRelief.lua`

Reason:
- v9 OpenGL Render Relief changed Core zoom-level option strings while the player was using the mouse wheel.
- In Build 41 this can make mouse-wheel zoom snap/reset to a middle zoom level instead of stepping normally.

Fix:
- Hard-disabled runtime zoom-list rewriting.
- Added one guarded restore pass: if the current zoom list still exactly equals the old capped v9 list (`50;75;100;125;150;175`), restore it to `50;75;100;125;150;175;200;250`.
- Kept safe RenderRelief parts: FPS/zoom load-state, scheduler integration, torch-light throttling.

Compatibility:
- Does not change ModData, network commands, save data, AI task schema, or Java classes.



## 2026-05-11 - v13 zombie-to-NPC damage mechanics patch

Changed files:
- `media/lua/client/BanditUpdate.lua`
- `media/lua/shared/BanditHealthRegen.lua`
- `media/lua/shared/BanditLegacySettings.lua`
- `media/sandbox-options.txt`
- `media/lua/shared/PROJECT_MAP_UPDATE.md`

Reason:
- Subscribers reported that vanilla zombies can visually grab/bite bandit NPCs but do not remove NPC HP, regardless of HP regeneration settings.
- The code path intentionally suppressed vanilla zombie bite damage to avoid bodydamage/moodle crashes on bandit actors, but the existing `Health_ZombieDamageToNPC` sandbox option was not applied by the custom bite handler.

Fix:
- Added a safe custom zombie bite damage path in `BanditUpdate.UpdateZombies()` for close-range zombie vs bandit attacks.
- The damage path is controlled by `BanditsLegacyExt.Health_ZombieDamageToNPC`; it is enabled by default for new configs.
- Damage is applied only by the controlling client in MP to avoid duplicate HP loss.
- Keeps vanilla bite/bodydamage suppressed, but manually lowers bandit HP, marks the NPC as damaged for AI/regen, optionally adds infection pressure when the existing infection option is enabled, and kills the NPC through the existing death path when HP reaches zero.
- `BanditHealthRegen.Update()` now respects `Health_AutoRegenEnabled=false`; it still records damage state but does not snap/regenerate HP while disabled.

Compatibility:
- No ModData schema, network commands, save format, task/action names, Java classes or brain data format changed.
- Existing servers that already wrote `Health_ZombieDamageToNPC=false` in their sandbox config must switch that option to `true` to enable zombie damage.

## 2026-05-11 - v14 mercenary jewelry hire and tactical formation orders

Changed files:
- `media/lua/shared/BanditMercenary.lua`
- `media/lua/shared/BanditOrders.lua`
- `media/lua/shared/BanditFormationSlots.lua`
- `media/lua/shared/BanditBrainDirector.lua`
- `media/lua/shared/ZombiePrograms/ZPCompanion.lua`
- `media/lua/shared/ZombiePrograms/ZPCompanionGuard.lua`
- `media/lua/client/BanditMenu.lua`
- `media/lua/server/BanditClientCommands.lua`
- `media/lua/shared/BanditLegacySettings.lua`
- `media/sandbox-options.txt`
- `media/lua/shared/Translate/EN/Sandbox_EN.txt`
- `media/lua/shared/Translate/RU/Sandbox_RU.txt`
- `media/lua/shared/PROJECT_MAP_UPDATE.md`

Reason:
- Mercenary hiring still used generic resources/ammunition, while the intended gameplay economy should use valuable gold or silver jewelry.
- Hired squads already accepted orders, but anchored Hold/Guard-style commands sent all members to the same point instead of keeping a tactical spread.
- Changing formation from the context menu forced Follow mode instead of preserving the current command.

Fix:
- Replaced active mercenary hire payment with gold jewelry or, when enabled, silver jewelry.
- Added sandbox options for gold cost, silver-payment toggle and silver cost.
- Kept legacy hire resource functions/settings present for compatibility, but active payment no longer consumes bullets, fuel, bandages or first-aid kits.
- Added facing-aware anchor formation slots so Hold/Guard/Return positions can spread the squad around the ordered point.
- The order context menu now sends the player's facing angle with positional commands, preserves the current order when changing formation, and adds quick wide/line guard-position commands.
- Companion and CompanionGuard programs now move each hired mercenary to its own anchor slot instead of stacking everyone on one square.

Compatibility:
- No existing ModData schema, network module names, command names, task action names, program names or Java classes changed.
- Existing hired mercenaries keep their previous order data; new formation fields are optional and safely ignored by older data.
- Existing servers should review the new `Mercenary_GoldJewelryCost`, `Mercenary_AllowSilverPayment` and `Mercenary_SilverJewelryCost` sandbox options after installing the patch.


## 2026-05-11 - v15 mercenary hire click/payment reliability patch

Changed files:
- `media/lua/client/BanditMenu.lua`
- `media/lua/server/BanditClientCommands.lua`
- `media/lua/shared/BanditMercenary.lua`
- `media/lua/shared/PROJECT_MAP_UPDATE.md`

Reason:
- In the admin test flow a blue mercenary showed the hire option, but clicking it did not consume gold jewelry and did not switch the squad into the hired command menu.
- The hire command depended on a narrow runtime id/group lookup and the jewelry payment code depended on exact item type names only.
- In non-MP worlds the hire menu had no local fallback, unlike the older neutral companion switch path.

Fix:
- The hire menu now sends runtime id, persistent id, group id and clicked NPC coordinates to the server.
- The server hire handler now resolves the clicked mercenary by runtime id, persistent id, group id or nearby queued NPC coordinates before payment is removed.
- Added a singleplayer/local hire path so the same context menu works when no MP server command path handles the click.
- Expanded supported gold/silver jewelry ids and added inventory object scanning/removal so admin-spawned jewelry stacks and nested inventory jewelry are detected even when the exact full type differs from the old list.
- Added explicit player feedback when the target cannot be resolved instead of silently doing nothing.

Compatibility:
- No command name, ModData schema, order names, program names or formation data changed.
- The payment API remains `BanditMercenary.HasPayment()` / `BanditMercenary.TakePayment()`; only its item detection/removal is more tolerant.

## 2026-05-11 - v16 mercenary hire command delivery and physical fallback patch

Changed files:
- `media/lua/client/BanditMenu.lua`
- `media/lua/client/BanditServerCommands.lua`
- `media/lua/server/BanditClientCommands.lua`
- `media/lua/shared/BanditMercenary.lua`
- `media/lua/shared/PROJECT_MAP_UPDATE.md`

Reason:
- In hosted MP/coop the hire submenu could appear for a blue mercenary, but clicking the option still produced no hire state, no removed jewelry and no order menu.
- The previous patch still rebuilt the target brain from the live zombie object at click time, so the command could silently stop before reaching the server if that object/brain reference changed after the context menu was opened.
- Server-side resolution still depended mostly on `gmd.Queue`, while a freshly materialized/teleported-to NPC may exist physically near the player before the queue id is aligned.
- Russian/localized jewelry display names such as gold/silver rings were not matched unless their internal type also contained the English gold/silver token or was in the exact whitelist.

Fix:
- The hire menu now snapshots the selected NPC ids/group/coordinates when the context menu is built and sends that snapshot on click instead of recomputing the brain from the zombie object.
- Added a guarded client command sender and one-line `[BanditsMercenary]` click diagnostics with id/runtime/persistent/group/coords.
- The server hire command now falls back to scanning nearby physical Bandit zombies, reads their `BanditBrain`, reattaches them to `gmd.Queue` when needed, and then applies the normal hire path.
- The server returns an explicit `MercenaryHireResult` command to the hiring client; the client updates the local brain/order state for matching loaded NPCs so the command menu becomes available immediately after successful hire.
- Added `[BanditsMercenary]` server diagnostics for hire request, payment failure and hire success.
- Jewelry matching now also recognizes Russian gold/silver/jewelry words in item display/type text.

Compatibility:
- Existing command names `HireMercenaryGroup` and `MercenaryGroupOrder` remain unchanged.
- Existing ModData/order/program fields remain unchanged.
- No unrelated AI, combat, spawn, base, black market, convoy or checkpoint logic was changed.

## 2026-05-11 - v17 mercenary gold/silver inventory detection patch

Changed files:
- `media/lua/client/BanditMenu.lua`
- `media/lua/client/BanditServerCommands.lua`
- `media/lua/server/BanditClientCommands.lua`
- `media/lua/shared/BanditMercenary.lua`
- `media/lua/shared/PROJECT_MAP_UPDATE.md`

Reason:
- In hosted MP/coop the hire command could reach the payment check, but the server still answered with the gold/silver requirement even when the player had a stack of gold jewelry in the inventory.
- Some jewelry can be represented by localized display names, worn-item records or less specific internal type names that were not covered by the previous exact-type payment scan.
- Server-side inventory state can lag behind the client inventory after admin-spawned items, so a server-only payment check can reject a valid local inventory.

Fix:
- Payment scanning now calls Java item accessors explicitly, scans both inventory containers and worn items, deduplicates found item objects, and keeps exact-type fallback compatibility.
- Added broader gold/silver ring aliases and kept localized Russian matching for display names such as gold/silver rings.
- The hire click now sends a lightweight client inventory payment snapshot with detected gold/silver counts.
- The server still tries to remove payment server-side first. If that fails but the client snapshot proves enough jewelry, the server accepts the hire and asks the client to remove the payment after the successful `MercenaryHireResult`.
- Added diagnostics that include detected client gold/silver counts and client-side payment removal result.

Compatibility:
- No command names, order names, ModData schema, program names or formation data changed.
- The existing payment API remains `BanditMercenary.HasPayment()` / `BanditMercenary.TakePayment()`.
- Server-side payment removal remains the primary path; client-side removal is only used as a fallback for MP inventory desync/admin-spawned item cases.

## 2026-05-11 - v18 mercenary stacked jewelry payment patch

Changed files:
- `media/lua/shared/BanditMercenary.lua`
- `media/lua/shared/PROJECT_MAP_UPDATE.md`

Reason:
- In hosted MP/coop the hire request reached the server and the target mercenary/group was resolved, but payment still failed with `clientGold=1 clientSilver=1` while the inventory UI showed stacked jewelry like `Золотое кольцо (10)` / `Серебряная цепочка (10)`.
- The payment scanner counted matching inventory objects, not the `InventoryItem:getCount()` stack value used by admin-added/collapsed jewelry stacks.
- Exact-type fallback removal was also skipped when the payment helper received the player object instead of the player's `ItemContainer`.

Fix:
- Added a small inventory normalizer so exact-type fallback count/removal works whether the caller passes the player or the inventory container.
- Payment counting now sums each matched jewelry item's `getCount()` / current uses when present instead of treating a stacked item as only one unit.
- Payment removal now decrements stacked jewelry with `setCount()` when possible and falls back to removing the whole item or exact type via `RemoveOneOf()`.

Compatibility:
- No command names, order names, ModData schema, program names, formation data or hire flow APIs changed.
- Existing exact gold/silver technical names and localized Russian/English display-name matching remain intact.
- The change is limited to payment counting/removal; mercenary AI, orders, factions and spawn logic were not touched.
## 2026-05-11 - v19 mercenary grouped jewelry inventory count patch

Changed files:
- `media/lua/shared/BanditMercenary.lua`
- `media/lua/shared/PROJECT_MAP_UPDATE.md`

Reason:
- After the stacked jewelry patch the hire logs still showed `gold=1 silver=1` while the inventory UI contained grouped jewelry such as `Золотое кольцо (10)`.
- The payment scanner deduplicated Java inventory objects through `tostring(item)`. For Project Zomboid InventoryItem userdata this can collapse multiple identical jewelry objects into a single counted payment item.
- Because at least one matched item was found, the exact-type fallback count was skipped, so the grouped/duplicated jewelry stack was still evaluated as only one unit.

Fix:
- Payment item deduplication now uses the actual Lua userdata reference and, when available, the item `getID()` value instead of `tostring(item)`.
- Payment counting now compares the tolerant scanned total with the exact `getItemCountFromTypeRecurse()` total and returns the larger value.
- This keeps localized/display-name matching for modded or worn jewelry, while letting exact vanilla technical names such as `Base.Ring_Right_MiddleFinger_Gold` count all duplicated inventory entries.

Compatibility:
- No command names, order names, ModData schema, program names, formation data or hire flow APIs changed.
- The patch is limited to payment counting/deduplication; mercenary AI, order execution, factions and spawn logic were not changed.


## 2026-05-11 - v20 mercenary immediate order interrupt patch

Changed files:
- `media/lua/shared/BanditOrders.lua`
- `media/lua/shared/BanditMercenary.lua`
- `media/lua/client/BanditServerCommands.lua`
- `media/lua/client/BanditUpdate.lua`
- `media/lua/shared/PROJECT_MAP_UPDATE.md`

Reason:
- Hired mercenaries accepted player orders, but if they were already in an Aim/Shoot/combat loop they continued the current combat task first and only obeyed the new order after the previous task chain ended.
- The normal AI task generation checks combat before the companion/guard program, so a visible enemy could immediately enqueue another Shoot task before the newly issued Follow/Hold/Guard/formation command had a chance to run.

Fix:
- Player-issued mercenary orders now carry a short interrupt window in the order data.
- When a synced mercenary order with an active interrupt window reaches the client, the current non-locked task queue, combat target and aim/move state are cleared immediately.
- During that interrupt window, the local AI runs the active Companion/CompanionGuard program before combat generation and suppresses new combat tasks long enough for the ordered move/hold/formation task to be queued.

Compatibility:
- Existing command names, order names, program names, group ids, ModData and formation formats remain unchanged.
- Locked safety tasks such as get-up/hit-recovery are not forcibly interrupted.
- Normal combat behaviour resumes after the short interrupt window; this only changes the first reaction to a fresh player order.

## 2026-05-11 - v21 mercenary context menu click reliability patch

Changed files:
- `media/lua/client/BanditMenu.lua`
- `media/lua/shared/PROJECT_MAP_UPDATE.md`

Reason:
- After the immediate order interrupt patch, opening the right-click/context menu near moving mercenaries could feel inconsistent.
- The context menu path trusted `BanditCompatibility.GetClickedSquare()` and immediately called `square:getGenerator()`. When the engine did not provide a clicked square for a moving character/body hit, the menu fill could abort before bandit/mercenary options were added.
- Bandit detection also depended mostly on the clicked grid square, so a small click offset on a moving NPC could miss the mercenary.

Fix:
- Added a guarded clicked-square resolver that falls back to worldobject squares and then the player's square instead of throwing on nil.
- Guarded `getGenerator()` behind a nil/pcall check.
- Let the bandit context lookup also inspect direct worldobjects and their squares.
- Slightly widened the nearby bandit lookup radius from 2.0 tiles to 2.5 tiles so right-clicking a moving mercenary is less likely to miss.

Compatibility:
- No network commands, ModData format, order names, program names, hire data or AI task schemas changed.
- This patch only affects client-side context menu discovery and nil safety.

## 2026-05-11 - v22 hired mercenary strict hold-fire aggro patch

Changed files:
- `media/lua/shared/BanditOrders.lua`
- `media/lua/shared/BanditUtilityAI.lua`
- `media/lua/shared/BanditAIVision.lua`
- `media/lua/shared/BanditBrainDirector.lua`
- `media/lua/client/BanditUpdate.lua`
- `media/lua/shared/PROJECT_MAP_UPDATE.md`

Reason:
- Hired mercenaries correctly accepted the player's `Hold fire` / `Do not shoot` fire-discipline order, but nearby enemies could still enter the melee/aggro path.
- The existing fire-mode logic suppressed firearms, while still allowing melee defense and threat memory. For normal NPCs that is acceptable, but for player-hired mercenary squads it breaks the expected strict no-aggro command.

Fix:
- Added a strict hold-fire helper for hired mercenary brains only.
- For hired mercenaries with `HoldFire`, combat target acquisition, remembered threats, tactical/radio threat state and melee engagement are suppressed.
- `HoldFire` now also locks the hired mercenary melee weapon in the utility layer while the order is active, then restores it when fire discipline changes.
- `MeleeOnly`, `Defensive`, `ReturnFire`, `DangerClose`, `Suppress` and all non-hired NPC behaviour remain unchanged.

Compatibility:
- No network command names, ModData schema, order names, formation data, hire/payment flow or normal NPC faction combat rules changed.
- The stricter no-aggro behaviour is gated by `mercenaryHired`/player-guard state and `HoldFire` only.

### 2026-05-11 - v23 mercenary strict follow formation patch
- Follow Me for hired mercenary squads now prioritizes the assigned formation slot next to the player before optional companion behaviours.
- Explicit Follow skips guardpost/loot/fishing/home-base side behaviours for hired mercenaries so the squad stays near the player in formation.
- Follow Me no longer resets the current formation to close; existing close/wide/line/wedge/ring selection is preserved.
- Scope is limited to hired mercenaries; non-hired companions and ordinary NPC logic are unchanged.

### 2026-05-11 - v24 mercenary menu reliability and follow leash patch

Changed files:
- `media/lua/client/BanditMenu.lua`
- `media/lua/shared/BanditMercenary.lua`
- `media/lua/server/BanditClientCommands.lua`
- `media/lua/server/BanditWorldDirector.lua`
- `media/lua/shared/ZombiePrograms/ZPCompanion.lua`
- `media/lua/shared/PROJECT_MAP_UPDATE.md`

Reason:
- The hired mercenary command menu could still require several right-click attempts when the click missed a moving NPC body or when client-side world-group data was not refreshed yet.
- A hired squad following the player could be converted by the physical-group cleanup/dematerialization path while the player was travelling, especially if the virtual group position lagged behind the real physical members.

Fix:
- Context menu discovery now scans nearby loaded bandit NPCs for mercenaries hired by the current player and uses that squad even if the exact clicked square missed the moving NPC.
- `HasHiredMercenaries()` now also falls back to loaded physical bandit brains, so the generic mercenary command menu does not depend only on synced `Queue`/`VirtualGroups` snapshots.
- Hired mercenary groups are marked as player-guard/follow groups and treated as important physical groups by the world director.
- Hired/player-guard groups are excluded from far physical dematerialization; this keeps the optimization for normal NPC groups while preventing the player's squad from disappearing during travel.
- Server-side position refresh for hired groups is updated from their physical member updates, throttled through the existing group marker refresh path.
- Strict Follow clears stale threat targets and forces run-to-slot when the hired mercenary falls too far behind the player.

Compatibility:
- No command names, ModData schema, order names, formation formats, payment logic, ordinary NPC AI, ordinary physical cleanup, or non-hired group optimization are changed.
- The dematerialization protection is gated to `mercenaryHired` / `isPlayerGuard` / follow/guard-player groups only.

### 2026-05-11 - v25 mercenary follow teleport leash patch

Changed files:
- `media/lua/server/BanditWorldDirector.lua`
- `media/lua/client/BanditServerCommands.lua`
- `media/lua/shared/PROJECT_MAP_UPDATE.md`

Reason:
- Player-hired mercenaries with `Follow Me` could still disappear or stay virtualized while the player was travelling quickly, even after the v24 dematerialization guard.
- The likely cause is a streaming/cleanup/proxy edge case where the follow group is already virtual or has lost physical runtime entries before normal formation movement can pull it back.

Fix:
- Added a server-side hired-mercenary follow leash that runs on a throttled tick and during world updates.
- Only groups marked as `mercenaryHired` / `isPlayerGuard` / `followPlayer` and currently ordered to `Follow` are affected.
- If a physical hired follower is too far from its owner, its runtime brain and visible bandit object are moved back into a loaded square near the player.
- If a hired follow group is virtual/dematerialized or has no live physical runtime entries, the world director forces it to materialize near the owner instead of waiting for normal virtual activation.
- Added a client `TeleportBanditObjects` command so already-loaded client-side bandit objects visually snap to the corrected server position.

Compatibility:
- Ordinary NPC groups, enemy squads, base groups, patrols, non-hired companions and general world optimization are not changed.
- The teleport/materialize leash is gated to the current player's hired follow squad and does not disable ProxyLOD or physical cleanup globally.

### 2026-05-11 - v27 mercenary search-house resupply patch

Changed files:
- `media/lua/client/BanditMenu.lua`
- `media/lua/shared/BanditOrders.lua`
- `media/lua/shared/BanditMercenary.lua`
- `media/lua/shared/ZombiePrograms/ZPCompanion.lua`
- `media/lua/shared/Translate/EN/IG_UI_EN.txt`
- `media/lua/shared/Translate/RU/IG_UI_RU.txt`
- `media/lua/shared/PROJECT_MAP_UPDATE.md`

Reason:
- Hired mercenaries already had a player order to search/loot the local area, but there was no separate house-search order.
- The search order also did not act as a squad resupply/medical recovery command, while the requested gameplay role is to use search orders as a practical ammo and wound recovery action for the player's hired squad.

Fix:
- Added a new hired-mercenary order `LootHouse` exposed in the command menu as `Loot this house` / `Обыскать дом`.
- `LootHouse` searches for the nearest loaded building around the clicked/order anchor, moves hired mercenaries into indoor room squares, then loops search/idle-style animations such as loot, smoke, weapon reload/maintenance and idle stance.
- Added `BanditMercenary.RestockAndHealBrain()` and call it when hired mercenaries receive `Loot` or `LootHouse` orders.
- The restock path fills current weapon magazines, restores configured reserve magazine counts, clears wounded-state flags and restores custom Bandit HP/max HP through the existing health-regeneration model.

Compatibility:
- The new behaviour is limited to hired mercenaries and the explicit `Loot` / `LootHouse` orders.
- Ordinary NPC looting, faction AI, world optimization, payment, hire flow, fire modes, formation data and network command names remain unchanged.

### 2026-05-11 - v28 mercenary tactical point orders patch

Changed files:
- `media/lua/client/BanditMenu.lua`
- `media/lua/shared/BanditOrders.lua`
- `media/lua/shared/BanditMercenary.lua`
- `media/lua/shared/ZombiePrograms/ZPCompanion.lua`
- `media/lua/shared/Translate/EN/IG_UI_EN.txt`
- `media/lua/shared/Translate/RU/IG_UI_RU.txt`
- `media/lua/shared/PROJECT_MAP_UPDATE.md`

Reason:
- Hired mercenary control needed explicit point-based tactical orders beyond Follow/Hold/Guard/Loot: flank, encircle, back-to-back, cover, advance, fallback and sector watch.

Fix:
- Added a Tactical Orders submenu for hired mercenary squads.
- Added new order names in `BanditOrders`: `Flank`, `Encircle`, `BackToBack`, `TakeCover`, `Advance`, `FallBack` and `WatchSector`.
- Added a lightweight hired-mercenary-only tactical executor in `ZPCompanion`.
- `Flank` splits the squad to side positions around the clicked point and faces the point.
- `Encircle` assigns ring slots around the clicked point.
- `BackToBack` forms all-around defense near the clicked point and faces outward.
- `TakeCover` looks for nearby cover-like/indoor/free squares and otherwise spreads around the point.
- `Advance`, `FallBack` and `WatchSector` form wedge/line-style positions around the clicked point and hold sector facing.

Compatibility:
- Scope is limited to player-hired mercenaries and explicit tactical point orders.
- Ordinary NPC AI, ordinary combat, world optimization, dematerialization, hiring, payment, fire modes, formation data and existing command names are unchanged.

### 2026-05-11 - v29 single active mercenary squad replacement patch

Changed files:
- `media/lua/shared/BanditMercenary.lua`
- `media/lua/server/BanditClientCommands.lua`
- `media/lua/shared/PROJECT_MAP_UPDATE.md`

Reason:
- Multiple hired mercenary squads per player are no longer desired.
- Hiring a new blue mercenary squad should transfer command to the new squad and return the previous squad to ordinary blue mercenary behaviour so it can be hired again later.

Fix:
- Added `BanditMercenary.ReleaseBrain()` and `BanditMercenary.ReleaseGroup()` to safely clear hired/player-guard ownership while keeping the squad as blue mercenaries.
- `HireMercenaryGroup` now releases any other currently hired squad for the same player after payment succeeds and before the new squad is hired.
- Releasing a squad clears player ownership, follow/guard leash state, player orders, fire mode, player-guard marker state and active threat/task state.
- Releasing keeps the old squad blue, friendly and mercenary-tagged, so the chain is closed: the old squad can be hired again later, which will release the currently commanded squad.
- Group debug markers now correctly clear `mercenaryHired`, `mercenaryHiredBy` and `isPlayerGuard` when a group is released instead of preserving stale hired marker flags.

Compatibility:
- Payment, jewelry counting, hire target lookup, tactical orders, fire modes, follow leash, teleport leash and ordinary NPC optimization are unchanged.
- The replacement rule is scoped to mercenary squads hired by the same player; squads hired by another player are still protected from being stolen.

### 2026-05-11 - v30 mercenary order performance patch

Changed files:
- `media/lua/client/BanditServerCommands.lua`
- `media/lua/server/BanditClientCommands.lua`
- `media/lua/shared/BanditMercenary.lua`
- `media/lua/shared/ZombiePrograms/ZPCompanion.lua`
- `media/lua/shared/PROJECT_MAP_UPDATE.md`

Reason:
- After the mercenary order/tactics upgrades, giving orders could cause noticeable stalls in coop/server play.
- The expensive path was concentrated around hired-squad commands: full per-brain sync payloads, per-field client sync logging, repeated Queue/VirtualGroups scans and repeated tactical house/cover searches.

Fix:
- Added an active hired squad cache per player, so normal mercenary orders target the current squad instead of repeatedly resolving all squads.
- Added a lightweight order-only `UpdateBanditPart` payload for mercenary commands instead of resending inventory/loot/health/leader/prisoner/loyalty data on every order.
- Disabled noisy per-field client sync logging during `UpdateBanditPart`, which could create console I/O spikes when several mercenaries were updated at once.
- Added a short duplicate-order debounce on the server to ignore identical command spam within a small window.
- Soft updates such as changing fire mode or formation no longer force a full task/program reset unless they must immediately stop combat (`HoldFire` / `MeleeOnly`).
- Cached `LootHouse` building squares and `TakeCover` cover candidates per order anchor, so every mercenary does not rescan/sort the same area independently.

Compatibility:
- Scope is limited to player-hired mercenary order handling and tactical point order caching.
- Hiring, payment, single-active-squad replacement, fire modes, follow/teleport leash, ordinary NPC AI, ordinary combat and world optimization remain on the existing contracts.

### 2026-05-11 - v31 mercenary follow player teleport rematerialize patch

Changed files:
- `media/lua/server/BanditWorldDirector.lua`
- `media/lua/shared/PROJECT_MAP_UPDATE.md`

Summary:
- Restored reliable hired-mercenary squad relocation after player/admin teleports while `Follow Me` is active.
- The follow leash now detects large owner-player jumps and verifies that the group's physical zombie objects are actually loaded, not only present in `gmd.Queue`.
- If the active hired follow group has Queue brains but no loaded runtime objects after a teleport/streaming jump, the server snapshots the members, clears stale runtime links, cleans up old objects, moves the group anchor to the player and rematerializes the squad near the player's formation slots.
- If all runtime objects are still loaded, the existing lightweight object teleport path is kept.

Compatibility notes:
- Limited to hired/player-guard mercenary groups with `Follow` order.
- Does not disable global world optimization, ProxyLOD, virtual groups, enemy patrols, ordinary blue squads, or base/road systems.
- No network command names, ModData schema, payment logic, fire modes, tactical orders, formation names or save format changed.

### 2026-05-11 - v32 mercenary follow missing-runtime watchdog patch

Changed files:
- `media/lua/server/BanditWorldDirector.lua`
- `media/lua/shared/BanditStreamingRuntime.lua`
- `media/lua/shared/PROJECT_MAP_UPDATE.md`

Reason:
- A player-hired squad with `Follow Me` could still disappear while the player was running across streamed map cells.
- The v31 leash recovered large player teleports, but a travel/streaming edge case could leave the hired group marked as physical while some or all real zombie objects were no longer loaded.
- In that state the server could still have stale group/brain state, so normal follow movement did not recreate the missing objects immediately.

Fix:
- The hired follow leash now treats missing loaded zombie objects, partial runtime loss and empty physical follow groups as a rematerialization condition, not just large player teleports.
- If an active hired follow group has no live runtime entries, missing loaded objects, or loaded objects far from the owner, the server snapshots/restores members, clears stale runtime links, moves the group anchor to the player and rematerializes the squad near the player's follow slots.
- Empty physical cleanup no longer removes player mercenary groups; it safely revirtualizes them so the follow leash can restore them.
- Streaming unload relief now explicitly preserves hired/player-guard groups in unload despawn and queued-spawn pause checks.
- The leash interval is slightly reduced, but still throttled and scoped only to hired follow groups.

Compatibility:
- The new watchdog is gated to player-hired/player-guard mercenary groups with `Follow` ownership.
- Ordinary NPCs, enemy squads, non-hired blue squads, bases, road patrols, ProxyLOD caps and global cleanup remain on the existing optimization paths.
- No command names, ModData schema, payment logic, fire modes, tactical order names or formation data changed.

### 2026-05-26 - Stage 257 persistence reconnect and aim-stability hotfix

Changed files:
- `media/lua/client/NPCClient/NPCUpdateBridge.lua`
- `media/lua/shared/NPCActions/NPCActionAimBridge.lua`
- `media/lua/shared/NPCActions/NPCActionShootBridge.lua`
- `media/lua/shared/NPCCore/NPCEntityState.lua`

Reason:
- After a server restart/rejoin, already loaded physical NPC zombie objects could remain near the player while the server revirtualized runtime links. If those objects no longer had a fresh queue brain, the client could let vanilla zombie logic take over and the living NPC looked/acted like a normal zombie.
- Combat NPCs could repeatedly enter/leave the ready-to-fire pose between short Aim/Shoot task chains, producing a bad visual loop where hands and weapons moved up and down before shooting.

Fix:
- Added a stamped-persistent runtime guard for client-side zombie updates. Objects carrying NPC persistent/group metadata are no longer demoted into vanilla zombies while safe sync is pending.
- If safe sync is ready and the object is a stale pre-restart physical runtime with no queue/known physical marker, it is removed as stale runtime instead of becoming a zombie. The virtual group can then rematerialize through the normal world director path.
- Queue/known-physical runtime entries can still be re-marked as NPCs if valid data exists.
- Added a short aim sticky window. Aim/Shoot tasks now keep combat aim state alive across short task gaps so NPCs do not repeatedly lower and raise their weapon before firing.

Compatibility:
- No save keys, ModData field names, network command names, item IDs, sandbox IDs or Java/class files changed.
- The reconnect cleanup is limited to alive objects with existing NPC persistent/group stamps and ignores former NPC zombies/corpses.
- The aim-sticky change only affects the lightweight brain `aim` flag and does not change weapon damage, ammo or faction rules.
