--
-- Neutral network contract for compact NPC marker/simulation sync.
-- Compatibility facade: media/lua/shared/legacy NPCNet.lua
-- Keeps persistent server ModData large, but sends clients only compact marker
-- deltas and chunked snapshots to avoid GlobalModData packet overflow after
-- long map travel / many teleport checks.
--

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCLegacyContractBridge"

local NPC_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
require "NPCCore/NPCLegacySettingsBridge"
require "NPCCore/NPCModeCompatBridge"
require "NPCCore/NPCStreamingRuntimeBridge"
require "NPCCore/NPCInterestManagerBridge"

NPCNetContract = NPCNetContract or {}

NPCNetContract.Enabled = NPCNetContract.Enabled ~= false
NPCNetContract.UseDebugMapCommands = true
NPCNetContract.DisableGMDMarkers = true
NPCNetContract.DisableGMDVirtualGroups = true
NPCNetContract.MarkerChunkSize = NPCNetContract.MarkerChunkSize or 48
NPCNetContract.MaxMarkerUpdatesPerTick = NPCNetContract.MaxMarkerUpdatesPerTick or 24
NPCNetContract.MaxMarkerRemovesPerTick = NPCNetContract.MaxMarkerRemovesPerTick or 24
NPCNetContract.MaxPendingMarkerUpdates = NPCNetContract.MaxPendingMarkerUpdates or 1200
NPCNetContract.MaxPendingMarkerRemoves = NPCNetContract.MaxPendingMarkerRemoves or 400
NPCNetContract.MaxSnapshotChunksPerTick = NPCNetContract.MaxSnapshotChunksPerTick or 4
NPCNetContract.MaxSnapshotMarkers = NPCNetContract.MaxSnapshotMarkers or 5000
NPCNetContract.MaxSimStateUpdatesPerTick = NPCNetContract.MaxSimStateUpdatesPerTick or 18
NPCNetContract.SnapshotSortByImportance = NPCNetContract.SnapshotSortByImportance ~= false
NPCNetContract.QueuedSnapshotSync = NPCNetContract.QueuedSnapshotSync ~= false
NPCNetContract.SyncCooldownHours = NPCNetContract.SyncCooldownHours or (3 / 3600)
NPCNetContract.PayloadSanitizer = NPCNetContract.PayloadSanitizer ~= false
NPCNetContract.MaxMarkerStringBytes = NPCNetContract.MaxMarkerStringBytes or 96
NPCNetContract.MaxMarkerTableEntries = NPCNetContract.MaxMarkerTableEntries or 24
NPCNetContract.MinMarkerMoveDelta = NPCNetContract.MinMarkerMoveDelta or 1.25
NPCNetContract.MinMarkerIntervalHours = NPCNetContract.MinMarkerIntervalHours or 0.00085
NPCNetContract.FarMarkerIntervalHours = NPCNetContract.FarMarkerIntervalHours or 0.0011
NPCNetContract.PendingMarkerUpdates = NPCNetContract.PendingMarkerUpdates or {}
NPCNetContract.PendingMarkerRemoves = NPCNetContract.PendingMarkerRemoves or {}
NPCNetContract.PendingMarkerQueues = NPCNetContract.PendingMarkerQueues or {high={}, normal={}, low={}}
NPCNetContract.PendingSyncSessions = NPCNetContract.PendingSyncSessions or {}
NPCNetContract.PendingSimStateUpdates = NPCNetContract.PendingSimStateUpdates or {}
NPCNetContract.PendingSimStateOrder = NPCNetContract.PendingSimStateOrder or {}
NPCNetContract.PendingSimStateHead = NPCNetContract.PendingSimStateHead or 1
NPCNetContract.LastSentMarkers = NPCNetContract.LastSentMarkers or {}
NPCNetContract.LastSyncByPlayer = NPCNetContract.LastSyncByPlayer or {}
NPCNetContract.DebugMapRevision = NPCNetContract.DebugMapRevision or 0
NPCNetContract.DroppedMarkerUpdates = NPCNetContract.DroppedMarkerUpdates or 0
NPCNetContract.DroppedMarkerRemoves = NPCNetContract.DroppedMarkerRemoves or 0
NPCNetContract._tick = NPCNetContract._tick or 0
NPCNetContract.ClientPendingSync = NPCNetContract.ClientPendingSync or nil

NPCNetContract.DIRTY_POS = 1
NPCNetContract.DIRTY_STATE = 2
NPCNetContract.DIRTY_FACTION = 4
NPCNetContract.DIRTY_BASE = 8
NPCNetContract.DIRTY_STOCK = 16
NPCNetContract.DIRTY_BATTLE = 32
NPCNetContract.DIRTY_REMOVE = 64

local bnet_pendingQueueCount
local bnet_dropOneQueuedMarker
local bnet_onServerCommand

local function bnet_debugMapNPCMarkers()
    return NPCDebugMapNPCMarkersBridge or NPC_LEGACY_GLOBALS.Get("DebugMapNPCMarkers")
end

local function bnet_globalDataStore()
    return NPCGlobalDataStore or NPC_LEGACY_GLOBALS.Get("GlobalData")
end

local function bnet_priorityForMarker(lite)
    if not lite then return "normal" end
    if lite.dead or lite.inBattle or lite.virtualBattle or lite.battleId then return "high" end
    if lite.wounded or lite.woundedDowned then return "high" end
    if lite.leader or lite.isFactionLeader or lite.markerType == "leader" then return "high" end
    if lite.blackMarketDrop or lite.markerType == "black_market_drop" then return "normal" end
    if lite.blackMarket or lite.markerType == "black_market" then return "normal" end
    if lite.bounty or lite.bountyHunter or lite.markerType == "bounty" then return "high" end
    if lite.heatWanted or lite.markerType == "heat_wanted" then return "high" end
    if lite.counterIntelHunter then return "high" end
    if lite.spy or (tonumber(lite.spyCount) and tonumber(lite.spyCount) > 0) or lite.spyDefected then return "high" end
    if lite.mercenaryHired or lite.hired or lite.isPlayerGuard then return "high" end
    if lite.markerType == "base" and (lite.captureActive or lite.contested or lite.captureStatus == "capturing" or lite.captureStatus == "decapturing") then return "high" end
    if lite.markerType == "economy_mission" and (lite.missionState == "assaulting" or lite.missionType == "raid" or lite.missionType == "capture" or lite.missionType == "retake") then return "high" end
    if lite.markerType == "group" and lite.virtual and not lite.active then return "normal" end
    if lite.markerType == "base_zone" or (lite.virtual and not lite.active) then return "low" end
    return "normal"
end

local function bnet_distanceScore(lite, player)
    if not lite or not player or not player.getX then return 0 end
    local ok, px, py = pcall(function() return player:getX(), player:getY() end)
    if not ok or not px or not py then return 0 end
    local dx = (tonumber(lite.x) or 0) - px
    local dy = (tonumber(lite.y) or 0) - py
    local dist = math.sqrt(dx * dx + dy * dy)
    return math.max(0, 1200 - dist) * 0.01
end

local function bnet_markerImportance(lite, player)
    if not lite then return 0 end
    local score = 0
    if lite.dead then score = score + 10000 end
    if lite.inBattle or lite.virtualBattle or lite.battleId then score = score + 9000 end
    if lite.wounded or lite.woundedDowned then score = score + 8600 end
    if lite.leader or lite.isFactionLeader or lite.markerType == "leader" then score = score + 8500 end
    if lite.bounty or lite.bountyHunter or lite.markerType == "bounty" then score = score + 8400 end
    if lite.heatWanted or lite.markerType == "heat_wanted" then score = score + 8380 end
    if lite.counterIntelHunter then score = score + 8350 end
    if lite.blackMarketDrop or lite.markerType == "black_market_drop" then score = score + 7700 end
    if lite.blackMarket or lite.markerType == "black_market" then score = score + 7600 end
    if lite.spy or (tonumber(lite.spyCount) and tonumber(lite.spyCount) > 0) or lite.spyDefected then score = score + 8200 end
    if lite.mercenaryHired or lite.hired or lite.isPlayerGuard then score = score + 7600 end
    if lite.markerType == "base" then
        score = score + 4200
        if lite.captureActive or lite.contested or lite.captureStatus == "capturing" or lite.captureStatus == "decapturing" then score = score + 3600 end
    elseif lite.markerType == "economy_mission" then
        score = score + 2400
        if lite.missionState == "assaulting" or lite.missionType == "raid" or lite.missionType == "capture" or lite.missionType == "retake" then score = score + 3000 end
    elseif lite.markerType == "group" then
        score = score + 1800
        if lite.active then score = score + 1000 end
        score = score + math.min(800, (tonumber(lite.count) or 0) * 40)
    elseif lite.markerType == "black_market_drop" then
        score = score + 1800
    elseif lite.markerType == "base_zone" then
        score = score + 900
        if lite.zoneType == "command" then score = score + 500 end
    else
        score = score + 700
    end
    if lite.roadPatrol then score = score + 250 end
    return score + bnet_distanceScore(lite, player)
end

local function bnet_clearQueuedMarker(id)
    if not id or not NPCNetContract.PendingMarkerQueues then return end
    id = tostring(id)
    for _, q in pairs(NPCNetContract.PendingMarkerQueues) do
        if type(q) == "table" then q[id] = nil end
    end
    NPCNetContract.PendingMarkerUpdates[id] = nil
end

local function bnet_queueMarker(lite, priority)
    if not lite or not lite.id then return end
    priority = priority or bnet_priorityForMarker(lite)
    if priority ~= "high" and priority ~= "low" then priority = "normal" end

    local maxPending = tonumber(NPCNetContract.MaxPendingMarkerUpdates) or 1200
    if maxPending > 0 and bnet_pendingQueueCount() >= maxPending then
        if priority == "low" then
            NPCNetContract.DroppedMarkerUpdates = (NPCNetContract.DroppedMarkerUpdates or 0) + 1
            return
        end
        bnet_dropOneQueuedMarker(true)
    end

    bnet_clearQueuedMarker(lite.id)
    NPCNetContract.PendingMarkerQueues[priority][lite.id] = lite
    NPCNetContract.PendingMarkerUpdates[lite.id] = lite
end

if NPCLegacySettingsBridge and NPCLegacySettingsBridge.ApplyNet then
    NPCLegacySettingsBridge.ApplyNet(NPCNetContract)
end

local function bnet_nowHours()
    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then
            return gt:getWorldAgeHours()
        end
    end
    return 0
end

local function bnet_isServerRuntime()
    if NPCModeCompatBridge and NPCModeCompatBridge.IsServerRuntime then
        return NPCModeCompatBridge.IsServerRuntime()
    end
    if isClient then
        local ok, value = pcall(function() return isClient() end)
        if ok and value == true then return false end
    end
    if isServer then
        local ok, value = pcall(function() return isServer() end)
        if ok and value == true then return true end
    end
    return true
end

local function bnet_isSinglePlayerRuntime()
    return NPCModeCompatBridge and NPCModeCompatBridge.IsSinglePlayerRuntime and NPCModeCompatBridge.IsSinglePlayerRuntime() == true
end

local function bnet_safeString(value, maxLen)
    if value == nil then return nil end
    value = tostring(value)
    maxLen = tonumber(maxLen) or 96
    if string.len(value) > maxLen then
        return string.sub(value, 1, maxLen)
    end
    return value
end

local function bnet_safeNumber(value, fallback)
    local n = tonumber(value)
    if n == nil or n ~= n then return fallback end
    if n > 1000000000 then return 1000000000 end
    if n < -1000000000 then return -1000000000 end
    return n
end

local function bnet_sanitizeTable(tbl, maxEntries)
    if type(tbl) ~= "table" then return nil end
    local out = {}
    local count = 0
    maxEntries = tonumber(maxEntries) or NPCNetContract.MaxMarkerTableEntries or 24
    for k, v in pairs(tbl) do
        count = count + 1
        if count > maxEntries then break end
        local keyType = type(k)
        local valueType = type(v)
        if keyType == "string" or keyType == "number" then
            local key = k
            if keyType == "string" then key = bnet_safeString(k, 48) end
            if valueType == "number" then
                out[key] = bnet_safeNumber(v, 0)
            elseif valueType == "boolean" then
                out[key] = v == true
            elseif valueType == "string" then
                out[key] = bnet_safeString(v, 64)
            end
        end
    end
    return out
end

function NPCNetContract.SanitizeMarker(lite)
    if type(lite) ~= "table" then return nil end
    if not NPCNetContract.PayloadSanitizer then return lite end

    local maxString = tonumber(NPCNetContract.MaxMarkerStringBytes) or 96
    for k, v in pairs(lite) do
        local vt = type(v)
        if vt == "string" then
            lite[k] = bnet_safeString(v, maxString)
        elseif vt == "number" then
            lite[k] = bnet_safeNumber(v, 0)
        elseif vt == "table" then
            lite[k] = bnet_sanitizeTable(v, NPCNetContract.MaxMarkerTableEntries)
        elseif vt ~= "boolean" and vt ~= "nil" then
            lite[k] = nil
        end
    end
    lite.id = bnet_safeString(lite.id, 80)
    if not lite.id or lite.id == "" then return nil end
    return lite
end

local function bnet_playerKey(player)
    if not player then return "broadcast" end
    if player.getOnlineID then
        local ok, id = pcall(function() return player:getOnlineID() end)
        if ok and id ~= nil then return tostring(id) end
    end
    if player.getUsername then
        local ok, name = pcall(function() return player:getUsername() end)
        if ok and name then return tostring(name) end
    end
    return tostring(player)
end

local function bnet_canStartSync(player)
    local cooldown = tonumber(NPCNetContract.SyncCooldownHours) or 0
    if cooldown <= 0 then return true end
    local key = bnet_playerKey(player)
    local now = bnet_nowHours()
    local last = tonumber(NPCNetContract.LastSyncByPlayer[key]) or -999999
    if now - last < cooldown then return false end
    NPCNetContract.LastSyncByPlayer[key] = now
    return true
end

bnet_pendingQueueCount = function()
    local count = 0
    local queues = NPCNetContract.PendingMarkerQueues or {}
    for _, q in pairs(queues) do
        if type(q) == "table" then
            for _, _ in pairs(q) do count = count + 1 end
        end
    end
    return count
end

bnet_dropOneQueuedMarker = function(preferLow)
    local order = preferLow and {"low", "normal", "high"} or {"normal", "low", "high"}
    for _, name in ipairs(order) do
        local q = NPCNetContract.PendingMarkerQueues and NPCNetContract.PendingMarkerQueues[name]
        if type(q) == "table" then
            for id, _ in pairs(q) do
                q[id] = nil
                NPCNetContract.PendingMarkerUpdates[id] = nil
                NPCNetContract.DroppedMarkerUpdates = (NPCNetContract.DroppedMarkerUpdates or 0) + 1
                return true
            end
        end
    end
    return false
end

local function bnet_count(tbl)
    local count = 0
    if type(tbl) ~= "table" then return 0 end
    for _, _ in pairs(tbl) do count = count + 1 end
    return count
end

local function bnet_markerId(marker)
    if not marker then return nil end
    return marker.id or marker.uid or marker.groupId
end

function NPCNetContract.LiteMarker(marker)
    if type(marker) ~= "table" then return nil end

    local x = tonumber(marker.x)
    local y = tonumber(marker.y)
    if not x or not y then return nil end

    local id = tostring(bnet_markerId(marker) or (tostring(math.floor(x)) .. "_" .. tostring(math.floor(y))))
    local lite = {
        id = id,
        uid = marker.uid,
        groupId = marker.groupId,
        markerType = marker.markerType,
        x = x,
        y = y,
        z = tonumber(marker.z) or 0,
        name = marker.name,
        count = marker.count,
        hostile = marker.hostile,
        friendly = marker.friendly,
        factionSide = marker.factionSide,
        faction = marker.faction,
        side = marker.side,
        factionState = marker.factionState,
        program = marker.program,
        virtual = marker.virtual,
        active = marker.active,
        dead = marker.dead,
        state = marker.state,
        spawnClass = marker.spawnClass,
        urbanAffinity = marker.urbanAffinity,
        roadPatrol = marker.roadPatrol,
        patrolColor = marker.patrolColor,
        encounterId = marker.encounterId,
        inBattle = marker.inBattle,
        virtualBattle = marker.virtualBattle,
        battleId = marker.battleId,
        enemyGroupId = marker.enemyGroupId,
        battleCasualties = marker.battleCasualties,
        targetKind = marker.targetKind,
        targetId = marker.targetId,
        targetX = marker.targetX,
        targetY = marker.targetY,
        preciseX = marker.preciseX,
        preciseY = marker.preciseY,
        mapMotion = marker.mapMotion,
        mapSourceX = marker.mapSourceX,
        mapSourceY = marker.mapSourceY,
        mapTargetX = marker.mapTargetX,
        mapTargetY = marker.mapTargetY,
        mapMoveSpeed = marker.mapMoveSpeed,
        mapUpdatedAt = marker.mapUpdatedAt,
        mapPathKey = marker.mapPathKey,
        mapPathCount = marker.mapPathCount,
        mapPathX1 = marker.mapPathX1,
        mapPathY1 = marker.mapPathY1,
        mapPathX2 = marker.mapPathX2,
        mapPathY2 = marker.mapPathY2,
        mapPathX3 = marker.mapPathX3,
        mapPathY3 = marker.mapPathY3,
        mapPathX4 = marker.mapPathX4,
        mapPathY4 = marker.mapPathY4,
        mapPathX5 = marker.mapPathX5,
        mapPathY5 = marker.mapPathY5,
        mapPathX6 = marker.mapPathX6,
        mapPathY6 = marker.mapPathY6,
        spawnFailed = marker.spawnFailed,
        spawnFailCount = marker.spawnFailCount,
        spawnFailReason = marker.spawnFailReason,
        baseId = marker.baseId,
        baseType = marker.baseType,
        owner = marker.owner,
        captureTeam = marker.captureTeam,
        progress = marker.progress,
        captureProgress = marker.captureProgress,
        captureStatus = marker.captureStatus,
        captureActive = marker.captureActive,
        contested = marker.contested,
        radius = marker.radius,
        redCount = marker.redCount,
        greenCount = marker.greenCount,
        homeGroupId = marker.homeGroupId,
        zoneVersion = marker.zoneVersion,
        zoneCount = marker.zoneCount,
        zoneSummary = marker.zoneSummary,
        parentBaseId = marker.parentBaseId,
        zoneId = marker.zoneId,
        baseZoneId = marker.baseZoneId,
        zoneType = marker.zoneType,
        zoneIndex = marker.zoneIndex,
        zoneLabel = marker.zoneLabel,
        duty = marker.duty,
        capacity = marker.capacity,
        assignedCount = marker.assignedCount,
        presentCount = marker.presentCount,
        stockFood = marker.stockFood,
        stockWater = marker.stockWater,
        stockMedical = marker.stockMedical,
        stockAmmo = marker.stockAmmo,
        stockFuel = marker.stockFuel,
        stockMaterials = marker.stockMaterials,
        stockTools = marker.stockTools,
        stockWeapons = marker.stockWeapons,
        stockSpareParts = marker.stockSpareParts,
        stockSupplies = marker.stockSupplies,
        garrisonReadiness = marker.garrisonReadiness,
        defenseReadiness = marker.defenseReadiness,
        logisticsReadiness = marker.logisticsReadiness,
        medicalReadiness = marker.medicalReadiness,
        foodReadiness = marker.foodReadiness,
        ammoReadiness = marker.ammoReadiness,
        operationalZones = marker.operationalZones,
        overloadedZones = marker.overloadedZones,
        lowZones = marker.lowZones,
        zoneNeedSummary = marker.zoneNeedSummary,
        economyStatus = marker.economyStatus,
        needSummary = marker.needSummary,
        missionCount = marker.missionCount,
        economyMissionId = marker.economyMissionId,
        missionType = marker.missionType,
        missionState = marker.missionState,
        missionReason = marker.missionReason,
        resource = marker.resource,
        originBaseId = marker.originBaseId,
        targetBaseId = marker.targetBaseId,
        convoyFaction = marker.convoyFaction,
        cargo = marker.cargo,
        spy = marker.spy,
        spyCount = marker.spyCount,
        spyPlayerId = marker.spyPlayerId,
        spyDefected = marker.spyDefected,
        mercenaryHired = marker.mercenaryHired,
        hired = marker.hired,
        isPlayerGuard = marker.isPlayerGuard,
        mercenarySquadLeader = marker.mercenarySquadLeader,
        mercenarySquadLeaderName = marker.mercenarySquadLeaderName,
        checkpointId = marker.checkpointId,
        checkpointSide = marker.checkpointSide,
        checkpointStatus = marker.checkpointStatus,
        tollResource = marker.tollResource,
        tollType = marker.tollType,
        tollLabel = marker.tollLabel,
        tollAmount = marker.tollAmount,
        signalId = marker.signalId,
        signalAction = marker.signalAction,
        signalLabel = marker.signalLabel,
        signalOwnerId = marker.signalOwnerId,
        signalExpiresAt = marker.signalExpiresAt,
        signalOrder = marker.signalOrder,
        signalFireMode = marker.signalFireMode,
        wounded = marker.wounded,
        woundedDowned = marker.woundedDowned,
        woundedState = marker.woundedState,
        woundedForPlayerId = marker.woundedForPlayerId,
        woundedExpiresAt = marker.woundedExpiresAt,
        loyalty = marker.loyalty,
        mercenaryLoyalty = marker.mercenaryLoyalty,
        loyaltyState = marker.loyaltyState,
        loyaltyForPlayerId = marker.loyaltyForPlayerId,
        loyaltyUpdatedAt = marker.loyaltyUpdatedAt,
        bounty = marker.bounty,
        bountyHunter = marker.bountyHunter,
        bountySide = marker.bountySide,
        bountyState = marker.bountyState,
        bountyAmount = marker.bountyAmount,
        bountyPlayerId = marker.bountyPlayerId,
        bountyPlayerName = marker.bountyPlayerName,
        bountyExpiresAt = marker.bountyExpiresAt,
        bountyTargetPlayerId = marker.bountyTargetPlayerId,
        bountyTargetPlayerName = marker.bountyTargetPlayerName,
        heatWanted = marker.heatWanted,
        heatWantedLevel = marker.heatWantedLevel,
        heatWantedState = marker.heatWantedState,
        heatWantedValue = marker.heatWantedValue,
        heatWantedReason = marker.heatWantedReason,
        heatWantedSide = marker.heatWantedSide,
        heatWantedPlayerId = marker.heatWantedPlayerId,
        heatWantedPlayerName = marker.heatWantedPlayerName,
        counterIntelHunter = marker.counterIntelHunter,
        counterIntelWave = marker.counterIntelWave,
        counterIntelState = marker.counterIntelState,
        counterIntelSide = marker.counterIntelSide,
        counterIntelHeat = marker.counterIntelHeat,
        counterIntelElite = marker.counterIntelElite,
        counterIntelTargetPlayerId = marker.counterIntelTargetPlayerId,
        counterIntelTargetPlayerName = marker.counterIntelTargetPlayerName,
        unitLevel = marker.unitLevel,
        unitStars = marker.unitStars,
        eliteUnit = marker.eliteUnit,
        worldNameplate = marker.worldNameplate,
        displayTitle = marker.displayTitle,
        leader = marker.leader,
        isFactionLeader = marker.isFactionLeader,
        leaderId = marker.leaderId,
        leaderName = marker.leaderName,
        leaderRole = marker.leaderRole,
        leaderTitle = marker.leaderTitle,
        leaderSide = marker.leaderSide,
        leaderState = marker.leaderState,
        leaderInfluence = marker.leaderInfluence,
        homeBaseId = marker.homeBaseId,
        strategicPower = marker.strategicPower,
        combatReadiness = marker.combatReadiness,
        supplyReadiness = marker.supplyReadiness,
        ammoReadiness = marker.ammoReadiness,
        moraleReadiness = marker.moraleReadiness,
        strategicActivityType = marker.strategicActivityType,
        strategicActivityState = marker.strategicActivityState,
        strategicActivityTargetBaseId = marker.strategicActivityTargetBaseId,
        strategicActivityTargetGroupId = marker.strategicActivityTargetGroupId,
        strategicActivityLogisticsSupply = marker.strategicActivityLogisticsSupply,
        strategicActivityLogisticsAmmo = marker.strategicActivityLogisticsAmmo,
        strategicActivityLogisticsMorale = marker.strategicActivityLogisticsMorale,
        directorRetargetReason = marker.directorRetargetReason,
        commanderId = marker.commanderId,
        commanderName = marker.commanderName,
        commanderSide = marker.commanderSide,
        commanderState = marker.commanderState,
        commanderInfluence = marker.commanderInfluence,
        blackMarket = marker.blackMarket,
        blackMarketId = marker.blackMarketId,
        blackMarketSide = marker.blackMarketSide,
        blackMarketStatus = marker.blackMarketStatus,
        blackMarketServices = marker.blackMarketServices,
        blackMarketSourceId = marker.blackMarketSourceId,
        blackMarketSourceType = marker.blackMarketSourceType,
        blackMarketDrop = marker.blackMarketDrop,
        blackMarketDeadDrop = marker.blackMarketDeadDrop,
        blackMarketDropId = marker.blackMarketDropId,
        blackMarketDropType = marker.blackMarketDropType,
        blackMarketDropStatus = marker.blackMarketDropStatus,
        blackMarketDropLabel = marker.blackMarketDropLabel,
        blackMarketContactId = marker.blackMarketContactId,
        blackMarketPlayerId = marker.blackMarketPlayerId,
        blackMarketPlayerName = marker.blackMarketPlayerName,
        blackMarketCompromised = marker.blackMarketCompromised,
        radioIntel = marker.radioIntel,
        intelType = marker.intelType,
        intelFalse = marker.intelFalse,
        radioWorldEvent = marker.radioWorldEvent,
        radioSourceKind = marker.radioSourceKind,
        supplyCache = marker.supplyCache,
        physicalStash = marker.physicalStash,
        stashRevealDistance = marker.stashRevealDistance,
        stashMarkerOverhead = marker.stashMarkerOverhead,
        stashCacheId = marker.stashCacheId,
        supplyCacheStatus = marker.supplyCacheStatus,
        supplyCacheTier = marker.supplyCacheTier,
        supplyCacheItems = marker.supplyCacheItems,
        updatedAt = marker.updatedAt
    }

    return NPCNetContract.SanitizeMarker(lite)
end

local function bnet_sendNow(player, module, command, args)
    args = args or {}
    if bnet_isSinglePlayerRuntime() then
        if NPCModeCompatBridge and NPCModeCompatBridge.DispatchServerCommand then
            local ok, delivered = pcall(function() return NPCModeCompatBridge.DispatchServerCommand(module, command, args) end)
            if ok and delivered then return end
        end
        if bnet_onServerCommand and NPCLegacyContractBridge.IsModule(module, 'NPCDebugMap', 'debugMap') then
            local ok = pcall(function() bnet_onServerCommand(module, command, args) end)
            if ok then return end
        end
    end
    if isServer and isServer() and player then
        local ok = pcall(function()
            sendServerCommand(player, module, command, args)
        end)
        if ok then return end
    end
    if sendServerCommand then
        sendServerCommand(module, command, args)
    end
end

local function bnet_shouldSendMarker(lite)
    if not lite or not lite.id then return false end

    local now = bnet_nowHours()
    local last = NPCNetContract.LastSentMarkers[lite.id]
    if not last then return true end

    if lite.dead then return true end
    if last.markerType ~= lite.markerType then return true end
    if last.state ~= lite.state then return true end
    if last.virtual ~= lite.virtual then return true end
    if last.active ~= lite.active then return true end
    if last.count ~= lite.count then return true end
    if last.inBattle ~= lite.inBattle then return true end
    if last.battleId ~= lite.battleId then return true end
    if last.enemyGroupId ~= lite.enemyGroupId then return true end
    if last.spawnFailed ~= lite.spawnFailed then return true end
    if lite.markerType == "base" then
        if last.owner ~= lite.owner then return true end
        if last.captureTeam ~= lite.captureTeam then return true end
        if last.captureStatus ~= lite.captureStatus then return true end
        if last.contested ~= lite.contested then return true end
        if math.abs((tonumber(last.progress) or 0) - (tonumber(lite.progress or lite.captureProgress) or 0)) >= 2 then return true end
        if last.redCount ~= lite.redCount then return true end
        if last.greenCount ~= lite.greenCount then return true end
        if last.zoneCount ~= lite.zoneCount then return true end
        if math.abs((tonumber(last.stockFood) or 0) - (tonumber(lite.stockFood) or 0)) >= 1 then return true end
        if math.abs((tonumber(last.stockWater) or 0) - (tonumber(lite.stockWater) or 0)) >= 1 then return true end
        if math.abs((tonumber(last.stockMedical) or 0) - (tonumber(lite.stockMedical) or 0)) >= 1 then return true end
        if math.abs((tonumber(last.stockAmmo) or 0) - (tonumber(lite.stockAmmo) or 0)) >= 1 then return true end
        if math.abs((tonumber(last.stockSupplies) or 0) - (tonumber(lite.stockSupplies) or 0)) >= 1 then return true end
        if math.abs((tonumber(last.foodReadiness) or 0) - (tonumber(lite.foodReadiness) or 0)) >= 1 then return true end
        if math.abs((tonumber(last.ammoReadiness) or 0) - (tonumber(lite.ammoReadiness) or 0)) >= 1 then return true end
    elseif lite.markerType == "group" then
        if last.groupId ~= lite.groupId then return true end
        if last.roadPatrol ~= lite.roadPatrol then return true end
        if last.patrolColor ~= lite.patrolColor then return true end
        if last.homeBaseId ~= lite.homeBaseId then return true end
        if last.targetBaseId ~= lite.targetBaseId then return true end
        if last.targetX ~= lite.targetX then return true end
        if last.targetY ~= lite.targetY then return true end
        if last.mapTargetX ~= lite.mapTargetX then return true end
        if last.mapTargetY ~= lite.mapTargetY then return true end
        if last.mapPathKey ~= lite.mapPathKey then return true end
        if last.strategicActivityType ~= lite.strategicActivityType then return true end
        if last.strategicActivityState ~= lite.strategicActivityState then return true end
        if last.strategicActivityTargetBaseId ~= lite.strategicActivityTargetBaseId then return true end
        if last.strategicActivityTargetGroupId ~= lite.strategicActivityTargetGroupId then return true end
        if last.directorRetargetReason ~= lite.directorRetargetReason then return true end
        if math.abs((tonumber(last.strategicPower) or 0) - (tonumber(lite.strategicPower) or 0)) >= 1 then return true end
        if math.abs((tonumber(last.combatReadiness) or 0) - (tonumber(lite.combatReadiness) or 0)) >= 1 then return true end
        if math.abs((tonumber(last.supplyReadiness) or 0) - (tonumber(lite.supplyReadiness) or 0)) >= 1 then return true end
        if math.abs((tonumber(last.ammoReadiness) or 0) - (tonumber(lite.ammoReadiness) or 0)) >= 1 then return true end
        if math.abs((tonumber(last.moraleReadiness) or 0) - (tonumber(lite.moraleReadiness) or 0)) >= 1 then return true end
    elseif lite.markerType == "base_zone" then
        if last.owner ~= lite.owner then return true end
        if last.captureStatus ~= lite.captureStatus then return true end
        if last.zoneType ~= lite.zoneType then return true end
        if last.assignedCount ~= lite.assignedCount then return true end
        if last.presentCount ~= lite.presentCount then return true end
        if math.abs((tonumber(last.stockFood) or 0) - (tonumber(lite.stockFood) or 0)) >= 5 then return true end
        if math.abs((tonumber(last.stockMedical) or 0) - (tonumber(lite.stockMedical) or 0)) >= 5 then return true end
        if math.abs((tonumber(last.stockAmmo) or 0) - (tonumber(lite.stockAmmo) or 0)) >= 5 then return true end
        if math.abs((tonumber(last.stockSupplies) or 0) - (tonumber(lite.stockSupplies) or 0)) >= 5 then return true end
    elseif lite.markerType == "economy_mission" then
        if last.missionType ~= lite.missionType then return true end
        if last.missionState ~= lite.missionState then return true end
        if last.resource ~= lite.resource then return true end
        if last.groupId ~= lite.groupId then return true end
        if last.targetBaseId ~= lite.targetBaseId then return true end
    elseif lite.markerType == "checkpoint" then
        if last.checkpointSide ~= lite.checkpointSide then return true end
        if last.checkpointStatus ~= lite.checkpointStatus then return true end
        if last.tollResource ~= lite.tollResource then return true end
        if last.tollAmount ~= lite.tollAmount then return true end
    elseif lite.markerType == "signal" then
        if last.signalAction ~= lite.signalAction then return true end
        if last.signalLabel ~= lite.signalLabel then return true end
        if last.signalExpiresAt ~= lite.signalExpiresAt then return true end
    elseif lite.markerType == "bounty" then
        if last.bountyState ~= lite.bountyState then return true end
        if last.bountyAmount ~= lite.bountyAmount then return true end
        if last.bountyExpiresAt ~= lite.bountyExpiresAt then return true end
    elseif lite.markerType == "heat_wanted" then
        if last.heatWantedLevel ~= lite.heatWantedLevel then return true end
        if last.heatWantedValue ~= lite.heatWantedValue then return true end
        if last.heatWantedState ~= lite.heatWantedState then return true end
    elseif lite.markerType == "leader" then
        if last.leaderState ~= lite.leaderState then return true end
        if last.leaderInfluence ~= lite.leaderInfluence then return true end
        if last.leaderSide ~= lite.leaderSide then return true end
    elseif lite.markerType == "black_market" then
        if last.blackMarketStatus ~= lite.blackMarketStatus then return true end
        if last.blackMarketSide ~= lite.blackMarketSide then return true end
        if last.blackMarketServices ~= lite.blackMarketServices then return true end
    elseif lite.markerType == "black_market_drop" then
        if last.blackMarketDropStatus ~= lite.blackMarketDropStatus then return true end
        if last.blackMarketDropType ~= lite.blackMarketDropType then return true end
        if last.blackMarketCompromised ~= lite.blackMarketCompromised then return true end
    elseif lite.counterIntelHunter or last.counterIntelHunter then
        if last.counterIntelState ~= lite.counterIntelState then return true end
        if last.counterIntelWave ~= lite.counterIntelWave then return true end
        if last.counterIntelHeat ~= lite.counterIntelHeat then return true end
        if last.counterIntelTargetPlayerId ~= lite.counterIntelTargetPlayerId then return true end
    elseif lite.radioIntel or last.radioIntel then
        if last.intelType ~= lite.intelType then return true end
        if last.intelFalse ~= lite.intelFalse then return true end
        if last.supplyCache ~= lite.supplyCache then return true end
        if last.physicalStash ~= lite.physicalStash then return true end
        if last.supplyCacheStatus ~= lite.supplyCacheStatus then return true end
        if last.supplyCacheTier ~= lite.supplyCacheTier then return true end
        if last.supplyCacheItems ~= lite.supplyCacheItems then return true end
    elseif lite.wounded or last.wounded then
        if last.wounded ~= lite.wounded then return true end
        if last.woundedState ~= lite.woundedState then return true end
        if last.woundedExpiresAt ~= lite.woundedExpiresAt then return true end
    end

    if last.spy ~= lite.spy then return true end
    if last.spyCount ~= lite.spyCount then return true end
    if last.spyDefected ~= lite.spyDefected then return true end
    if last.mercenaryHired ~= lite.mercenaryHired then return true end
    if last.hired ~= lite.hired then return true end
    if last.isPlayerGuard ~= lite.isPlayerGuard then return true end
    if last.mercenarySquadLeader ~= lite.mercenarySquadLeader then return true end
    if last.mercenaryLoyalty ~= lite.mercenaryLoyalty then return true end
    if last.loyaltyState ~= lite.loyaltyState then return true end
    if last.bountyHunter ~= lite.bountyHunter then return true end
    if last.heatWanted ~= lite.heatWanted then return true end
    if last.heatWantedLevel ~= lite.heatWantedLevel then return true end
    if last.counterIntelHunter ~= lite.counterIntelHunter then return true end
    if last.counterIntelState ~= lite.counterIntelState then return true end
    if last.bountyState ~= lite.bountyState then return true end
    if last.bountyAmount ~= lite.bountyAmount then return true end
    if last.leader ~= lite.leader then return true end
    if last.leaderState ~= lite.leaderState then return true end
    if last.leaderInfluence ~= lite.leaderInfluence then return true end
    if last.commanderState ~= lite.commanderState then return true end
    if last.blackMarket ~= lite.blackMarket then return true end
    if last.blackMarketStatus ~= lite.blackMarketStatus then return true end

    if last.economyMissionId ~= lite.economyMissionId then return true end
    if last.missionType ~= lite.missionType then return true end
    if last.economyStatus ~= lite.economyStatus then return true end
    if last.needSummary ~= lite.needSummary then return true end

    local dx = math.abs((tonumber(last.x) or 0) - (tonumber(lite.x) or 0))
    local dy = math.abs((tonumber(last.y) or 0) - (tonumber(lite.y) or 0))
    local moveDelta = NPCNetContract.MinMarkerMoveDelta
    if lite.markerType == "group" and lite.virtual and not lite.active then
        moveDelta = math.min(tonumber(moveDelta) or 1.25, 0.5)
    end
    if NPCStreamingRuntimeBridge and NPCStreamingRuntimeBridge.AdjustMarkerMoveDelta then
        moveDelta = NPCStreamingRuntimeBridge.AdjustMarkerMoveDelta(moveDelta)
    end
    local moved = dx >= moveDelta or dy >= moveDelta
    local interval = NPCNetContract.MinMarkerIntervalHours
    local isVirtual = lite.virtual and not lite.inBattle and not lite.active
    if isVirtual then
        interval = NPCNetContract.FarMarkerIntervalHours
    end
    if NPCStreamingRuntimeBridge and NPCStreamingRuntimeBridge.AdjustMarkerHours then
        interval = NPCStreamingRuntimeBridge.AdjustMarkerHours(interval, isVirtual)
    end

    return moved or (now - (tonumber(last.t) or 0)) >= interval
end

function NPCNetContract.SendDebugMapUpdate(marker, player)
    if not bnet_isServerRuntime() then return end
    if NPCNetContract.Enabled == false or NPCNetContract.UseDebugMapCommands == false then return end

    local lite = NPCNetContract.LiteMarker(marker)
    if not lite or not lite.id then return end

    local forceGlobalMapMarker = lite.markerType == "group" and lite.virtual and not lite.active
    if not forceGlobalMapMarker and NPCInterestManagerBridge and NPCInterestManagerBridge.ShouldSendMarker then
        local okInterest, allowed = pcall(function() return NPCInterestManagerBridge.ShouldSendMarker(lite, player, "world") end)
        if okInterest and allowed == false then return end
    end

    if player then
        bnet_sendNow(player, 'NPCDebugMap', 'Update', lite)
        return
    end

    if not bnet_shouldSendMarker(lite) then return end

    lite.netRev = (NPCNetContract.DebugMapRevision or 0) + 1
    NPCNetContract.DebugMapRevision = lite.netRev
    lite.updatedAt = lite.updatedAt or bnet_nowHours()
    bnet_queueMarker(lite)
end

function NPCNetContract.SendDebugMapRemove(id, player)
    if not bnet_isServerRuntime() then return end
    if not id then return end

    id = tostring(id)
    bnet_clearQueuedMarker(id)
    if bnet_count(NPCNetContract.PendingMarkerRemoves) >= (tonumber(NPCNetContract.MaxPendingMarkerRemoves) or 400) then
        NPCNetContract.DroppedMarkerRemoves = (NPCNetContract.DroppedMarkerRemoves or 0) + 1
    else
        NPCNetContract.PendingMarkerRemoves[id] = true
    end
    NPCNetContract.LastSentMarkers[id] = nil

    if player then
        bnet_sendNow(player, 'NPCDebugMap', 'Remove', {id=id})
    end
end

function NPCNetContract.SendDebugMapClear(player)
    if not bnet_isServerRuntime() then return end
    NPCNetContract.PendingMarkerUpdates = {}
    NPCNetContract.PendingMarkerQueues = {high={}, normal={}, low={}}
    NPCNetContract.PendingMarkerRemoves = {}
    NPCNetContract.LastSentMarkers = {}
    bnet_sendNow(player, 'NPCDebugMap', 'Clear', {})
end

function NPCNetContract.StoreLastSentMarker(id, marker)
    NPCNetContract.LastSentMarkers[id] = {
        x = marker.x,
        y = marker.y,
        markerType = marker.markerType,
        state = marker.state,
        virtual = marker.virtual,
        active = marker.active,
        count = marker.count,
        inBattle = marker.inBattle,
        battleId = marker.battleId,
        enemyGroupId = marker.enemyGroupId,
        spawnFailed = marker.spawnFailed,
        owner = marker.owner,
        captureTeam = marker.captureTeam,
        captureStatus = marker.captureStatus,
        contested = marker.contested,
        progress = tonumber(marker.progress or marker.captureProgress) or 0,
        redCount = marker.redCount,
        greenCount = marker.greenCount,
        zoneCount = marker.zoneCount,
        parentBaseId = marker.parentBaseId,
        zoneId = marker.zoneId,
        baseZoneId = marker.baseZoneId,
        zoneType = marker.zoneType,
        assignedCount = marker.assignedCount,
        presentCount = marker.presentCount,
        stockFood = marker.stockFood,
        stockWater = marker.stockWater,
        stockMedical = marker.stockMedical,
        stockAmmo = marker.stockAmmo,
        stockFuel = marker.stockFuel,
        stockMaterials = marker.stockMaterials,
        stockTools = marker.stockTools,
        stockWeapons = marker.stockWeapons,
        stockSpareParts = marker.stockSpareParts,
        stockSupplies = marker.stockSupplies,
        garrisonReadiness = marker.garrisonReadiness,
        defenseReadiness = marker.defenseReadiness,
        logisticsReadiness = marker.logisticsReadiness,
        medicalReadiness = marker.medicalReadiness,
        foodReadiness = marker.foodReadiness,
        ammoReadiness = marker.ammoReadiness,
        operationalZones = marker.operationalZones,
        overloadedZones = marker.overloadedZones,
        lowZones = marker.lowZones,
        zoneNeedSummary = marker.zoneNeedSummary,
        economyStatus = marker.economyStatus,
        needSummary = marker.needSummary,
        missionCount = marker.missionCount,
        economyMissionId = marker.economyMissionId,
        missionType = marker.missionType,
        missionState = marker.missionState,
        missionReason = marker.missionReason,
        resource = marker.resource,
        originBaseId = marker.originBaseId,
        targetBaseId = marker.targetBaseId,
        convoyFaction = marker.convoyFaction,
        groupId = marker.groupId,
        homeBaseId = marker.homeBaseId,
        strategicPower = marker.strategicPower,
        combatReadiness = marker.combatReadiness,
        supplyReadiness = marker.supplyReadiness,
        ammoReadiness = marker.ammoReadiness,
        moraleReadiness = marker.moraleReadiness,
        strategicActivityType = marker.strategicActivityType,
        strategicActivityState = marker.strategicActivityState,
        strategicActivityTargetBaseId = marker.strategicActivityTargetBaseId,
        strategicActivityTargetGroupId = marker.strategicActivityTargetGroupId,
        directorRetargetReason = marker.directorRetargetReason,
        targetX = marker.targetX,
        targetY = marker.targetY,
        mapTargetX = marker.mapTargetX,
        mapTargetY = marker.mapTargetY,
        mapPathKey = marker.mapPathKey,
        roadPatrol = marker.roadPatrol,
        patrolColor = marker.patrolColor,
        spy = marker.spy,
        spyCount = marker.spyCount,
        spyDefected = marker.spyDefected,
        mercenaryHired = marker.mercenaryHired,
        hired = marker.hired,
        isPlayerGuard = marker.isPlayerGuard,
        mercenarySquadLeader = marker.mercenarySquadLeader,
        mercenarySquadLeaderName = marker.mercenarySquadLeaderName,
        mercenaryLoyalty = marker.mercenaryLoyalty,
        loyaltyState = marker.loyaltyState,
        leader = marker.leader,
        isFactionLeader = marker.isFactionLeader,
        leaderId = marker.leaderId,
        leaderState = marker.leaderState,
        commanderId = marker.commanderId,
        commanderState = marker.commanderState,
        t = bnet_nowHours()
    }
end

local function bnet_flushUpdateQueue(queue, sent, maxUpdates)
    maxUpdates = tonumber(maxUpdates) or tonumber(NPCNetContract.MaxMarkerUpdatesPerTick) or 18
    for id, marker in pairs(queue or {}) do
        bnet_sendNow(nil, 'NPCDebugMap', 'Update', marker)
        NPCNetContract.StoreLastSentMarker(id, marker)
        queue[id] = nil
        NPCNetContract.PendingMarkerUpdates[id] = nil
        sent = sent + 1
        if sent >= maxUpdates then return sent, true end
    end
    return sent, false
end

function NPCNetContract.FlushDebugMapQueue()
    if not bnet_isServerRuntime() then return end

    local sent = 0
    local removeSent = 0
    local maxUpdates = tonumber(NPCNetContract.MaxMarkerUpdatesPerTick) or 18
    if NPCStreamingRuntimeBridge and NPCStreamingRuntimeBridge.AdjustNetMarkerBudget then
        maxUpdates = NPCStreamingRuntimeBridge.AdjustNetMarkerBudget(maxUpdates)
    end
    local maxRemoves = tonumber(NPCNetContract.MaxMarkerRemovesPerTick) or tonumber(NPCNetContract.MaxMarkerUpdatesPerTick) or 18
    if NPCStreamingRuntimeBridge and NPCStreamingRuntimeBridge.AdjustNetMarkerBudget then
        maxRemoves = NPCStreamingRuntimeBridge.AdjustNetMarkerBudget(maxRemoves)
    end
    for id, _ in pairs(NPCNetContract.PendingMarkerRemoves) do
        bnet_sendNow(nil, 'NPCDebugMap', 'Remove', {id=id})
        NPCNetContract.PendingMarkerRemoves[id] = nil
        sent = sent + 1
        removeSent = removeSent + 1
        if sent >= maxUpdates or removeSent >= maxRemoves then return end
    end

    local queues = NPCNetContract.PendingMarkerQueues or {high={}, normal={}, low={}}
    local stop = false
    sent, stop = bnet_flushUpdateQueue(queues.high, sent, maxUpdates)
    if stop then return end
    sent, stop = bnet_flushUpdateQueue(queues.normal, sent, maxUpdates)
    if stop then return end
    bnet_flushUpdateQueue(queues.low, sent, maxUpdates)
end

function NPCNetContract.SendDebugMapSync(player, gmdOrMarkers)
    if not bnet_isServerRuntime() then return end
    if NPCNetContract.Enabled == false or NPCNetContract.UseDebugMapCommands == false then return end
    if not bnet_canStartSync(player) then return end

    local markers = gmdOrMarkers
    if type(gmdOrMarkers) == "table" and gmdOrMarkers.DebugMapMarkers then
        markers = gmdOrMarkers.DebugMapMarkers
    end
    if type(markers) ~= "table" then markers = {} end

    NPCNetContract.DebugMapRevision = (NPCNetContract.DebugMapRevision or 0) + 1
    local rev = NPCNetContract.DebugMapRevision
    local chunkSize = tonumber(NPCNetContract.MarkerChunkSize) or 32
    local maxMarkers = tonumber(NPCNetContract.MaxSnapshotMarkers) or 5000
    local chunks = {}
    local chunk = {}
    local chunkCount = 0
    local total = 0
    local snapshot = {}

    bnet_sendNow(player, 'NPCDebugMap', 'SyncBegin', {rev=rev})

    for id, marker in pairs(markers) do
        local lite = NPCNetContract.LiteMarker(marker)
        if lite and not lite.dead then
            local allowed = true
            local forceGlobalMapMarker = lite.markerType == "group" and lite.virtual and not lite.active
            if not forceGlobalMapMarker and NPCInterestManagerBridge and NPCInterestManagerBridge.ShouldSendMarker then
                local okInterest, ret = pcall(function() return NPCInterestManagerBridge.ShouldSendMarker(lite, player, "sync") end)
                if okInterest then allowed = ret ~= false end
            end
            if allowed then
                lite._importance = bnet_markerImportance(lite, player)
                table.insert(snapshot, lite)
            end
        end
    end

    if NPCNetContract.SnapshotSortByImportance ~= false then
        table.sort(snapshot, function(a, b)
            return (tonumber(a._importance) or 0) > (tonumber(b._importance) or 0)
        end)
    end

    local truncated = maxMarkers > 0 and #snapshot > maxMarkers

    for _, lite in ipairs(snapshot) do
        if maxMarkers <= 0 or total < maxMarkers then
            lite._importance = nil
            chunk[tostring(lite.id)] = lite
            chunkCount = chunkCount + 1
            total = total + 1
            if chunkCount >= chunkSize then
                table.insert(chunks, chunk)
                chunk = {}
                chunkCount = 0
            end
        end
    end

    if chunkCount > 0 then
        table.insert(chunks, chunk)
    end

    if not NPCNetContract.QueuedSnapshotSync then
        for _, syncChunk in ipairs(chunks) do
            bnet_sendNow(player, 'NPCDebugMap', 'SyncChunk', {rev=rev, markers=syncChunk})
        end
        bnet_sendNow(player, 'NPCDebugMap', 'SyncEnd', {rev=rev, count=total, truncated=truncated or false})
        return
    end

    if #chunks == 0 then
        bnet_sendNow(player, 'NPCDebugMap', 'SyncEnd', {rev=rev, count=0})
        return
    end

    table.insert(NPCNetContract.PendingSyncSessions, {
        player = player,
        rev = rev,
        chunks = chunks,
        index = 1,
        total = total,
        truncated = truncated or false
    })
end

function NPCNetContract.FlushSyncSessions()
    if not bnet_isServerRuntime() then return end
    local budget = tonumber(NPCNetContract.MaxSnapshotChunksPerTick) or 2
    if NPCStreamingRuntimeBridge and NPCStreamingRuntimeBridge.AdjustSnapshotBudget then
        local ok, adjusted = pcall(function() return NPCStreamingRuntimeBridge.AdjustSnapshotBudget(budget) end)
        if ok and adjusted ~= nil then budget = tonumber(adjusted) or 0 end
    end
    if budget <= 0 then return end

    local sent = 0
    local sessions = NPCNetContract.PendingSyncSessions or {}
    while sent < budget and #sessions > 0 do
        local session = sessions[1]
        if not session or type(session.chunks) ~= "table" then
            table.remove(sessions, 1)
        else
            local chunk = session.chunks[session.index or 1]
            if chunk then
                bnet_sendNow(session.player, 'NPCDebugMap', 'SyncChunk', {rev=session.rev, markers=chunk})
                session.index = (session.index or 1) + 1
                sent = sent + 1
            else
                bnet_sendNow(session.player, 'NPCDebugMap', 'SyncEnd', {rev=session.rev, count=session.total or 0, truncated=session.truncated or false})
                table.remove(sessions, 1)
            end
        end
    end
end

function NPCNetContract.SendSimStateUpdate(args, player)
    if not bnet_isServerRuntime() then return end
    if type(args) ~= "table" then return end

    if player then
        bnet_sendNow(player, 'NPCSim', 'StateUpdate', args)
        return
    end

    local id = args.id or args.uid or args.persistentId
    if not id then
        bnet_sendNow(nil, 'NPCSim', 'StateUpdate', args)
        return
    end

    local key = tostring(id)
    if not NPCNetContract.PendingSimStateUpdates[key] then
        table.insert(NPCNetContract.PendingSimStateOrder, key)
    end
    NPCNetContract.PendingSimStateUpdates[key] = args
end

function NPCNetContract.FlushSimStateQueue()
    if not bnet_isServerRuntime() then return end

    local budget = tonumber(NPCNetContract.MaxSimStateUpdatesPerTick) or 18
    if NPCStreamingRuntimeBridge and NPCStreamingRuntimeBridge.AdjustSimStateBudget then
        local ok, adjusted = pcall(function() return NPCStreamingRuntimeBridge.AdjustSimStateBudget(budget) end)
        if ok and adjusted ~= nil then budget = tonumber(adjusted) or 0 end
    end
    if budget <= 0 then return end

    local sent = 0
    local order = NPCNetContract.PendingSimStateOrder or {}
    local pending = NPCNetContract.PendingSimStateUpdates or {}
    local head = tonumber(NPCNetContract.PendingSimStateHead) or 1

    while sent < budget and head <= #order do
        local key = order[head]
        head = head + 1

        local args = key and pending[key] or nil
        if args then
            pending[key] = nil
            bnet_sendNow(nil, 'NPCSim', 'StateUpdate', args)
            sent = sent + 1
        end
    end

    NPCNetContract.PendingSimStateHead = head

    if head > 64 and head > (#order / 2) then
        local compact = {}
        for i = head, #order do
            if order[i] then table.insert(compact, order[i]) end
        end
        NPCNetContract.PendingSimStateOrder = compact
        NPCNetContract.PendingSimStateHead = 1
    end
end

function NPCNetContract.SendDebugMap(command, args, player, gmd)
    if not bnet_isServerRuntime() then return end

    if command == 'Update' or command == 'UpdateCompact' then
        NPCNetContract.SendDebugMapUpdate(args, player)
    elseif command == 'Remove' then
        NPCNetContract.SendDebugMapRemove(args and (args.id or args.uid or args.groupId), player)
    elseif command == 'Clear' then
        NPCNetContract.SendDebugMapClear(player)
    elseif command == 'Sync' then
        if gmd then
            NPCNetContract.SendDebugMapSync(player, gmd)
        elseif args and args.markers then
            NPCNetContract.SendDebugMapSync(player, args.markers)
        else
            NPCNetContract.SendDebugMapSync(player, args)
        end
    else
        bnet_sendNow(player, 'NPCDebugMap', command, args or {})
    end
end

local function bnet_clientApplyMarker(marker)
    local markerStore = bnet_debugMapNPCMarkers()
    if markerStore and markerStore.Set then
        markerStore.Set(marker)
    end

    local gmd = bnet_globalDataStore()
    if gmd then
        gmd.DebugMapMarkers = gmd.DebugMapMarkers or {}
        local lite = NPCNetContract.LiteMarker(marker)
        if lite and lite.id then
            if lite.dead then
                gmd.DebugMapMarkers[lite.id] = nil
            else
                gmd.DebugMapMarkers[lite.id] = lite
            end
        end
    end
end

local function bnet_clientRemoveMarker(id)
    if not id then return end
    id = tostring(id)

    local markerStore = bnet_debugMapNPCMarkers()
    if markerStore and markerStore.Remove then
        markerStore.Remove(id)
    end
    local gmd = bnet_globalDataStore()
    if gmd and gmd.DebugMapMarkers then
        gmd.DebugMapMarkers[id] = nil
    end
end

bnet_onServerCommand = function(module, command, args)
    if not NPCLegacyContractBridge.IsModule(module, 'NPCDebugMap', 'debugMap') then return end
    args = args or {}

    if command == 'Update' or command == 'UpdateCompact' then
        bnet_clientApplyMarker(args)
    elseif command == 'Remove' then
        bnet_clientRemoveMarker(args.id or args.uid or args.groupId)
    elseif command == 'Clear' then
        local markerStore = bnet_debugMapNPCMarkers()
        if markerStore and markerStore.Clear then
            markerStore.Clear()
        end
        local gmd = bnet_globalDataStore()
        if gmd then gmd.DebugMapMarkers = {} end
        NPCNetContract.ClientPendingSync = nil
    elseif command == 'SyncBegin' then
        NPCNetContract.ClientPendingSync = {rev=args.rev, markers={}}
    elseif command == 'SyncChunk' then
        if not NPCNetContract.ClientPendingSync or (args.rev and NPCNetContract.ClientPendingSync.rev ~= args.rev) then
            NPCNetContract.ClientPendingSync = {rev=args.rev, markers={}, count=0}
        end
        local markers = args.markers or {}
        for id, marker in pairs(markers) do
            NPCNetContract.ClientPendingSync.markers[tostring(id)] = marker
            NPCNetContract.ClientPendingSync.count = (tonumber(NPCNetContract.ClientPendingSync.count) or 0) + 1
        end
    elseif command == 'SyncEnd' then
        local pending = NPCNetContract.ClientPendingSync
        if pending and (not args.rev or pending.rev == args.rev) then
            local expected = tonumber(args.count)
            local partial = args.truncated == true or (expected and expected > 0 and (tonumber(pending.count) or 0) < expected)
            local markerStore = bnet_debugMapNPCMarkers()
            if partial and markerStore and markerStore.Merge then
                markerStore.Merge(pending.markers)
            elseif markerStore and markerStore.Sync then
                markerStore.Sync(pending.markers)
            end
            local gmd = bnet_globalDataStore()
            if gmd then
                if partial then
                    gmd.DebugMapMarkers = gmd.DebugMapMarkers or {}
                    for id, marker in pairs(pending.markers or {}) do
                        gmd.DebugMapMarkers[tostring(id)] = marker
                    end
                else
                    gmd.DebugMapMarkers = pending.markers
                end
            end
        end
        NPCNetContract.ClientPendingSync = nil
    elseif command == 'Sync' then
        local markers = args.markers or args or {}
        local markerStore = bnet_debugMapNPCMarkers()
        if markerStore and markerStore.Sync then
            markerStore.Sync(markers)
        end
        local gmd = bnet_globalDataStore()
        if gmd then gmd.DebugMapMarkers = markers end
    end
end

function NPCNetContract.DispatchServerCommand(module, command, args)
    return bnet_onServerCommand(module, command, args or {})
end

local function bnet_onTick()
    if bnet_isServerRuntime() then
        NPCNetContract._tick = (NPCNetContract._tick or 0) + 1
        if NPCNetContract._tick % 60 == 1 and NPCLegacySettingsBridge and NPCLegacySettingsBridge.ApplyNet then
            NPCLegacySettingsBridge.ApplyNet(NPCNetContract)
        end
        NPCNetContract.FlushDebugMapQueue()
        if NPCNetContract.FlushSyncSessions then NPCNetContract.FlushSyncSessions() end
        if NPCNetContract.FlushSimStateQueue then NPCNetContract.FlushSimStateQueue() end
    end
end

if not NPCNetContract._eventsInstalled then
    if Events and Events.OnServerCommand then
        Events.OnServerCommand.Add(bnet_onServerCommand)
    end
    if Events and Events.OnTick then
        Events.OnTick.Add(bnet_onTick)
    end
    NPCNetContract._eventsInstalled = true
end
