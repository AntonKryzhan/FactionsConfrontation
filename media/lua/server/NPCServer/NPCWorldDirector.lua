--
-- Server-side world population director for NPC runtime.
--
-- This file replaces the old multiplayer "player as event initiator" spawn loop
-- with a server-owned virtual group system. The server creates lightweight
-- groups in ModData independently from player coordinates, sends their markers
-- to clients, and only materializes them into real NPCs when a player later
-- comes close enough to an already existing group.
--

if not isServer() then return end

NPCWorldDirector = NPCWorldDirector or {}

require "NPCServer/NPCWorldDirectorBridge"
require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCLegacySettingsBridge"

NPCWorldDirectorBridge.ApplyDefaults(NPCWorldDirector)

local NPC_WORLD_DIRECTOR_LEGACY_STATE = NPCLegacyContractBridge.State
local NPC_WORLD_DIRECTOR_LEGACY_MEMBERS = NPCLegacyContractBridge.Members

if NPCLegacySettingsBridge and NPCLegacySettingsBridge.ApplyWorldDirector then
    NPCLegacySettingsBridge.ApplyWorldDirector(NPCWorldDirector)
end

function NPCWorldDirector.RemoveLoadedNPCObjects(args)
    return NPCWorldDirectorBridge.RemoveLoadedNPCObjects(NPCWorldDirector, args)
end

NPCWorldDirector[NPC_WORLD_DIRECTOR_LEGACY_MEMBERS.removeLoadedObjects] = function(args)
    return NPCWorldDirector.RemoveLoadedNPCObjects(args)
end

NPCWorldDirector._removeObjectQueue = NPCWorldDirector._removeObjectQueue or {ids = {}, order = {}, head = 1, ticks = 0}

function NPCWorldDirector.FlushRemoveObjectQueue(force)
    return NPCWorldDirectorBridge.FlushRemoveObjectQueue(NPCWorldDirector, force)
end

NPCWorldDirector._formerNPCCleanupScopes = NPCWorldDirector._formerNPCCleanupScopes or NPCWorldDirector[NPC_WORLD_DIRECTOR_LEGACY_STATE.formerCleanupScopes] or {}
NPCWorldDirector[NPC_WORLD_DIRECTOR_LEGACY_STATE.formerCleanupScopes] = NPCWorldDirector._formerNPCCleanupScopes

function NPCWorldDirector.FlushFormerNPCCleanupScopes(force)
    return NPCWorldDirectorBridge.FlushFormerNPCCleanupScopes(NPCWorldDirector, force)
end

NPCWorldDirector[NPC_WORLD_DIRECTOR_LEGACY_MEMBERS.flushFormerCleanupScopes] = function(force)
    return NPCWorldDirector.FlushFormerNPCCleanupScopes(force)
end

function NPCWorldDirector.RequestNPCObjectCleanup(args)
    return NPCWorldDirectorBridge.RequestNPCObjectCleanup(NPCWorldDirector, args)
end

NPCWorldDirector[NPC_WORLD_DIRECTOR_LEGACY_MEMBERS.requestObjectCleanup] = function(args)
    return NPCWorldDirector.RequestNPCObjectCleanup(args)
end


function NPCWorldDirector.PruneBattleRemains(gmd, worldAge)
    return NPCWorldDirectorBridge.PruneBattleRemains(NPCWorldDirector, gmd, worldAge)
end

function NPCWorldDirector.CreateBattleRemains(gmd, loser, winner, battleId, membersSnapshot, worldAge)
    return NPCWorldDirectorBridge.CreateBattleRemains(NPCWorldDirector, gmd, loser, winner, battleId, membersSnapshot, worldAge)
end

function NPCWorldDirector.MaterializeBattleRemains(gmd, remainsId, record, player)
    return NPCWorldDirectorBridge.MaterializeBattleRemains(NPCWorldDirector, gmd, remainsId, record, player)
end

function NPCWorldDirector.UpdateBattleRemains()
    return NPCWorldDirectorBridge.UpdateBattleRemains(NPCWorldDirector)
end


function NPCWorldDirector.EnsureData()
    return NPCWorldDirectorBridge.EnsureData(NPCWorldDirector)
end

function NPCWorldDirector.RevirtualizePersistedRuntimeState()
    return NPCWorldDirectorBridge.RevirtualizePersistedRuntimeState(NPCWorldDirector)
end

function NPCWorldDirector.GetWaveDataAll()
    return NPCWorldDirectorBridge.GetWaveDataAll(NPCWorldDirector)
end

function NPCWorldDirector.GetWaveDataForDay(day)
    return NPCWorldDirectorBridge.GetWaveDataForDay(NPCWorldDirector, day)
end

function NPCWorldDirector.GetProgramForWave(wave)
    return NPCWorldDirectorBridge.GetProgramForWave(NPCWorldDirector, wave)
end

function NPCWorldDirector.MakeFallbackNPC(wave)
    return NPCWorldDirectorBridge.MakeFallbackNPC(NPCWorldDirector, wave)
end

NPCWorldDirector[NPC_WORLD_DIRECTOR_LEGACY_MEMBERS.makeFallback] = function(wave)
    return NPCWorldDirector.MakeFallbackNPC(wave)
end

function NPCWorldDirector.MakeNPCFromWave(wave)
    return NPCWorldDirectorBridge.MakeNPCFromWave(NPCWorldDirector, wave)
end

NPCWorldDirector[NPC_WORLD_DIRECTOR_LEGACY_MEMBERS.makeFromWave] = function(wave)
    return NPCWorldDirector.MakeNPCFromWave(wave)
end

function NPCWorldDirector.GetWorldBounds()
    return NPCWorldDirectorBridge.GetWorldBounds(NPCWorldDirector)
end
function NPCWorldDirector.IsTooCloseToPlayer(x, y, radius)
    return NPCWorldDirectorBridge.IsTooCloseToPlayer(x, y, radius)
end

function NPCWorldDirector.GetZoneTypesAt(x, y)
    return NPCWorldDirectorBridge.GetZoneTypesAt(x, y)
end
function NPCWorldDirector.ScoreWorldPoint(x, y)
    return NPCWorldDirectorBridge.ScoreWorldPoint(NPCWorldDirector, x, y)
end
function NPCWorldDirector.IsZoneAllowed(x, y)
    return NPCWorldDirectorBridge.IsZoneAllowed(NPCWorldDirector, x, y)
end

function NPCWorldDirector.IsUrbanWorldPoint(x, y)
    return NPCWorldDirectorBridge.IsUrbanWorldPoint(NPCWorldDirector, x, y)
end
function NPCWorldDirector.GetUrbanAffinityAt(x, y, radius)
    return NPCWorldDirectorBridge.GetUrbanAffinityAt(NPCWorldDirector, x, y, radius)
end
function NPCWorldDirector.ScoreRoadPatrolPoint(x, y)
    return NPCWorldDirectorBridge.ScoreRoadPatrolPoint(NPCWorldDirector, x, y)
end
function NPCWorldDirector.IsUrbanRoadPatrolPoint(x, y)
    return NPCWorldDirectorBridge.IsUrbanRoadPatrolPoint(NPCWorldDirector, x, y)
end
function NPCWorldDirector.GetRandomUrbanPoint(attempts, avoidPlayerRadius)
    return NPCWorldDirectorBridge.GetRandomUrbanPoint(NPCWorldDirector, attempts, avoidPlayerRadius)
end
function NPCWorldDirector.GetRandomWorldPoint()
    return NPCWorldDirectorBridge.GetRandomWorldPoint(NPCWorldDirector)
end
function NPCWorldDirector.GetNearbyPreferredPoint(x, y, radius)
    return NPCWorldDirectorBridge.GetNearbyPreferredPoint(NPCWorldDirector, x, y, radius)
end
function NPCWorldDirector.GetRandomRoadPoint()
    return NPCWorldDirectorBridge.GetRandomRoadPoint(NPCWorldDirector)
end
function NPCWorldDirector.GetNearbyRoadPoint(x, y, radius)
    return NPCWorldDirectorBridge.GetNearbyRoadPoint(NPCWorldDirector, x, y, radius)
end
function NPCWorldDirector.GetRoadPatrolCount(hostile)
    return NPCWorldDirectorBridge.GetRoadPatrolCount(NPCWorldDirector, hostile)
end

function NPCWorldDirector.GetAnyRoadPatrolCount()
    return NPCWorldDirectorBridge.GetAnyRoadPatrolCount(NPCWorldDirector)
end

function NPCWorldDirector.GetRoadPatrolEncounterCount()
    return NPCWorldDirectorBridge.GetRoadPatrolEncounterCount(NPCWorldDirector)
end

function NPCWorldDirector.CreateRoadPatrol(hostile, force, pointOverride, targetOverride, encounterId)
    return NPCWorldDirectorBridge.CreateRoadPatrol(NPCWorldDirector, hostile, force, pointOverride, targetOverride, encounterId)
end

function NPCWorldDirector.UpdateRoadPatrolMarker(gmd, group)
    return NPCWorldDirectorBridge.UpdateRoadPatrolMarker(NPCWorldDirector, gmd, group)
end

function NPCWorldDirector.CreateRoadPatrolEncounterPair(force)
    return NPCWorldDirectorBridge.CreateRoadPatrolEncounterPair(NPCWorldDirector, force)
end

function NPCWorldDirector.EnsureRoadPatrols(force)
    return NPCWorldDirectorBridge.EnsureRoadPatrols(NPCWorldDirector, force)
end

function NPCWorldDirector.CreateVirtualGroup(force)
    return NPCWorldDirectorBridge.CreateVirtualGroup(NPCWorldDirector, force)
end

function NPCWorldDirector.IsSquareUsable(square)
    return NPCWorldDirectorBridge.IsSquareUsable(NPCWorldDirector, square)
end

function NPCWorldDirector.FindLoadedSpawnSquareNear(x, y, z, radius)
    return NPCWorldDirectorBridge.FindLoadedSpawnSquareNear(NPCWorldDirector, x, y, z, radius)
end

function NPCWorldDirector.IsPointAwayFromPlayers(x, y, minDist)
    return NPCWorldDirectorBridge.IsPointAwayFromPlayers(NPCWorldDirector, x, y, minDist)
end

function NPCWorldDirector.FindOffscreenMaterializeSquare(group, player)
    return NPCWorldDirectorBridge.FindOffscreenMaterializeSquare(NPCWorldDirector, group, player)
end

function NPCWorldDirector.GetNearestPlayer(x, y, radius)
    return NPCWorldDirectorBridge.GetNearestPlayer(NPCWorldDirector, x, y, radius)
end

function NPCWorldDirector.GetPhysicalGroupCount()
    return NPCWorldDirectorBridge.GetPhysicalGroupCount(NPCWorldDirector)
end

function NPCWorldDirector.CountPhysicalNPCNearPlayer(player, radius)
    return NPCWorldDirectorBridge.CountPhysicalNPCNearPlayer(NPCWorldDirector, player, radius)
end

function NPCWorldDirector.GetGroupMemberCount(group)
    return NPCWorldDirectorBridge.GetGroupMemberCount(NPCWorldDirector, group)
end

function NPCWorldDirector.IsProxyLODEnabled()
    return NPCWorldDirectorBridge.IsProxyLODEnabled(NPCWorldDirector)
end

function NPCWorldDirector.GetProxyLODPlayerCap()
    return NPCWorldDirectorBridge.GetProxyLODPlayerCap(NPCWorldDirector)
end

function NPCWorldDirector.CountPhysicalNPCGlobal(limit)
    return NPCWorldDirectorBridge.CountPhysicalNPCGlobal(NPCWorldDirector, limit)
end

function NPCWorldDirector.GetPhysicalGroupRuntimeInfo(groupId)
    return NPCWorldDirectorBridge.GetPhysicalGroupRuntimeInfo(NPCWorldDirector, groupId)
end

function NPCWorldDirector.GetAvailablePhysicalNPCSlots(player, group, budget)
    return NPCWorldDirectorBridge.GetAvailablePhysicalNPCSlots(NPCWorldDirector, player, group, budget)
end

function NPCWorldDirector.ShouldDeferForProxyLOD(group, player, budget)
    return NPCWorldDirectorBridge.ShouldDeferForProxyLOD(NPCWorldDirector, group, player, budget)
end

function NPCWorldDirector.GetProxySpawnLimit(group, player, budget, requested)
    return NPCWorldDirectorBridge.GetProxySpawnLimit(NPCWorldDirector, group, player, budget, requested)
end

function NPCWorldDirector.AdjustQueuedSpawnBatch(entry, requestedBatch)
    return NPCWorldDirectorBridge.AdjustQueuedSpawnBatch(NPCWorldDirector, entry, requestedBatch)
end

function NPCWorldDirector.EnforceProxyLODPhysicalCaps(reason)
    return NPCWorldDirectorBridge.EnforceProxyLODPhysicalCaps(NPCWorldDirector, reason)
end

function NPCWorldDirector.GetPhysicalDeactivationRadius(group)
    return NPCWorldDirectorBridge.GetPhysicalDeactivationRadius(NPCWorldDirector, group)
end

function NPCWorldDirector.CanDematerializePhysicalGroup(group)
    return NPCWorldDirectorBridge.CanDematerializePhysicalGroup(NPCWorldDirector, group)
end

function NPCWorldDirector.GetPhysicalCleanupIntervalTicks()
    return NPCWorldDirectorBridge.GetPhysicalCleanupIntervalTicks(NPCWorldDirector)
end

function NPCWorldDirector.GetPhysicalCleanupDematerializeBudget()
    return NPCWorldDirectorBridge.GetPhysicalCleanupDematerializeBudget(NPCWorldDirector)
end

function NPCWorldDirector.DeferGroupActivation(group, reason, retryHours)
    return NPCWorldDirectorBridge.DeferGroupActivation(NPCWorldDirector, group, reason, retryHours)
end

function NPCWorldDirector.PrepareActivationBudgets(gmd, worldAge)
    return NPCWorldDirectorBridge.PrepareActivationBudgets(NPCWorldDirector, gmd, worldAge)
end

function NPCWorldDirector.IsPlayerActivationCoolingDown(player)
    return NPCWorldDirectorBridge.IsPlayerActivationCoolingDown(NPCWorldDirector, player)
end

function NPCWorldDirector.IsPlayerOnDebugMarker(group, player)
    return NPCWorldDirectorBridge.IsPlayerOnDebugMarker(NPCWorldDirector, group, player)
end

function NPCWorldDirector.GetActivationPriority(group, player, distance)
    return NPCWorldDirectorBridge.GetActivationPriority(NPCWorldDirector, group, player, distance)
end

function NPCWorldDirector.CanActivateGroupForPlayer(group, player, budget, totalActivations)
    return NPCWorldDirectorBridge.CanActivateGroupForPlayer(NPCWorldDirector, group, player, budget, totalActivations)
end

function NPCWorldDirector.GetPhysicalMemberSnapshots(groupId)
    return NPCWorldDirectorBridge.GetPhysicalMemberSnapshots(NPCWorldDirector, groupId)
end

function NPCWorldDirector.DematerializeFarPhysicalGroup(groupId, group)
    return NPCWorldDirectorBridge.DematerializeFarPhysicalGroup(NPCWorldDirector, groupId, group)
end

function NPCWorldDirector.CountAlivePhysicalMembers(groupId)
    return NPCWorldDirectorBridge.CountAlivePhysicalMembers(NPCWorldDirector, groupId)
end

function NPCWorldDirector.RemoveWorldGroup(groupId, reason)
    return NPCWorldDirectorBridge.RemoveWorldGroup(NPCWorldDirector, groupId, reason)
end

function NPCWorldDirector.OnPhysicalGroupCleared(groupId)
    return NPCWorldDirectorBridge.OnPhysicalGroupCleared(NPCWorldDirector, groupId)
end

function NPCWorldDirector.CleanupDeadPhysicalGroups()
    return NPCWorldDirectorBridge.CleanupDeadPhysicalGroups(NPCWorldDirector)
end

function NPCWorldDirector.MarkGroupMaterializeFailed(group, player, reason)
    return NPCWorldDirectorBridge.MarkGroupMaterializeFailed(NPCWorldDirector, group, player, reason)
end

function NPCWorldDirector.MaterializeGroup(group, player)
    return NPCWorldDirectorBridge.MaterializeGroup(NPCWorldDirector, group, player)
end

function NPCWorldDirector.ActivateGroupsNearPlayers()
    return NPCWorldDirectorBridge.ActivateGroupsNearPlayers(NPCWorldDirector)
end

function NPCWorldDirector.EnsureVirtualTarget(group)
    return NPCWorldDirectorBridge.EnsureVirtualTarget(NPCWorldDirector, group)
end

function NPCWorldDirector.IsVirtualGroupUrbanPlaced(group)
    return NPCWorldDirectorBridge.IsVirtualGroupUrbanPlaced(NPCWorldDirector, group)
end

function NPCWorldDirector.RepairVirtualGroupLocation(group)
    return NPCWorldDirectorBridge.RepairVirtualGroupLocation(NPCWorldDirector, group)
end

function NPCWorldDirector.TryDirectorRetargetGroup(group, worldAge)
    return NPCWorldDirectorBridge.TryDirectorRetargetGroup(NPCWorldDirector, group, worldAge)
end

function NPCWorldDirector.UpdateVirtualGroup(group, worldAge)
    return NPCWorldDirectorBridge.UpdateVirtualGroup(NPCWorldDirector, group, worldAge)
end

function NPCWorldDirector.UpdateVirtualGroups()
    return NPCWorldDirectorBridge.UpdateVirtualGroups(NPCWorldDirector)
end

function NPCWorldDirector.AreRoadPatrolEnemies(a, b)
    return NPCWorldDirectorBridge.AreRoadPatrolEnemies(NPCWorldDirector, a, b)
end

function NPCWorldDirector.StartRoadPatrolBattle(gmd, a, b, worldAge)
    return NPCWorldDirectorBridge.StartRoadPatrolBattle(NPCWorldDirector, gmd, a, b, worldAge)
end

function NPCWorldDirector.ClearRoadPatrolBattle(gmd, group, reason)
    return NPCWorldDirectorBridge.ClearRoadPatrolBattle(NPCWorldDirector, gmd, group, reason)
end

function NPCWorldDirector.ApplyRoadPatrolBattleDamage(group, attacker)
    return NPCWorldDirectorBridge.ApplyRoadPatrolBattleDamage(NPCWorldDirector, group, attacker)
end

function NPCWorldDirector.ProcessRoadPatrolBattlePair(gmd, a, b, worldAge, processed)
    return NPCWorldDirectorBridge.ProcessRoadPatrolBattlePair(NPCWorldDirector, gmd, a, b, worldAge, processed)
end

function NPCWorldDirector.UpdateRoadPatrolBattles()
    return NPCWorldDirectorBridge.UpdateRoadPatrolBattles(NPCWorldDirector)
end

function NPCWorldDirector.MaterializeRoadBattlePair(group, enemy, player)
    return NPCWorldDirectorBridge.MaterializeRoadBattlePair(NPCWorldDirector, group, enemy, player)
end

function NPCWorldDirector.SyncMarkers()
    return NPCWorldDirectorBridge.SyncMarkers(NPCWorldDirector)
end

function NPCWorldDirector.Bootstrap()
    return NPCWorldDirectorBridge.Bootstrap(NPCWorldDirector)
end

function NPCWorldDirector.EnforceHiredMercenaryFollowLeash(reason)
    return NPCWorldDirectorBridge.EnforceHiredMercenaryFollowLeash(NPCWorldDirector, reason)
end

function NPCWorldDirector.UpdateWorld()
    return NPCWorldDirectorBridge.UpdateWorld(NPCWorldDirector)
end

NPCWorldDirectorBridge.InstallRuntimeEvents(NPCWorldDirector)
