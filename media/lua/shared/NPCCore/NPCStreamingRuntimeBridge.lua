-- NPCStreamingRuntimeBridge.lua
-- Adaptive streaming/travel pressure controller for multiplayer city-to-city travel.
-- It does not change engine streaming; it keeps legacy NPCs runtime quiet while the
-- engine is busy loading/sending chunks, then restores normal budgets gradually.

require "NPCCore/NPCLegacyGlobalsBridge"

local NPC_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
local legacyStreamingRuntime = NPCStreamingRuntimeBridge
NPCStreamingRuntimeBridge = NPCStreamingRuntimeBridge or legacyStreamingRuntime or {}

NPCStreamingRuntimeBridge.VERSION = "2026-06-10-stage458-post-gate-burst-smoother-1"
local function bsr_worldDirector()
    return NPCWorldDirector or NPC_LEGACY_GLOBALS.Get("WorldDirector") or nil
end

local function bsr_spawnQueue()
    return NPCSpawnQueueBridge or NPC_LEGACY_GLOBALS.Get("SpawnQueue") or nil
end

local function bsr_isSinglePlayerRuntime()
    return (not (isClient and isClient())) and (not (isServer and isServer()))
end

local function bsr_isSinglePlayerGovernorEnabled()
    return bsr_isSinglePlayerRuntime() and NPCStreamingRuntimeBridge.Config and NPCStreamingRuntimeBridge.Config.singlePlayerStreetGovernor ~= false
end

NPCStreamingRuntimeBridge.Config = NPCStreamingRuntimeBridge.Config or {
    enabled = true,
    debug = false,
    sampleTicks = 30,
    fastVehicleSpeedTilesPerSecond = 8.0,
    travelCooldownSeconds = 12,
    teleportDistanceTiles = 80,
    teleportCooldownSeconds = 1,
    teleportSnapshotChunksPerTick = 6,
    deferMaterialization = true,
    deferRetrySeconds = 10,
    criticalRetrySeconds = 18,
    urbanExtraHeat = 18,
    vehicleExtraHeat = 24,
    chunkChangeExtraHeat = 14,
    npcHigh = 32,
    npcCritical = 56,
    pendingSpawnHigh = 6,
    pendingSpawnCritical = 12,
    pendingMarkerHigh = 100,
    pendingMarkerCritical = 220,
    pendingTaskHigh = 80,
    pendingTaskCritical = 180,
    mediumThreshold = 38,
    highThreshold = 68,
    criticalThreshold = 102,
    heatDecayPerSample = 11,
    unloadReliefEnabled = true,
    unloadDespawnRadius = 260,
    unloadCriticalDespawnRadius = 220,
    unloadCleanupIntervalTicks = 90,
    unloadCriticalCleanupIntervalTicks = 45,
    unloadMinAgeSeconds = 8,
    unloadPauseSpawnQueue = true,
    unloadPauseSnapshotSync = true,
    unloadSnapshotChunksPerTick = 1,
    unloadSimStateBudget = 4,
    movementExtraHeat = 10,
    singlePlayerStreetGovernor = true,
    singlePlayerRunSpeedTilesPerSecond = 3.2,
    singlePlayerRunExtraHeat = 46,
    singlePlayerChunkExtraHeat = 18,
    singlePlayerCooldownSeconds = 16,
    singlePlayerActivationDeferDistance = 75,
    singlePlayerCriticalActivationDistance = 55,
    singlePlayerSpawnDeferDistance = 70,
    singlePlayerHighSpawnSkipModulo = 4,
    singlePlayerCriticalSpawnSkipModulo = 6,
    singlePlayerActivationScanModuloHigh = 3,
    singlePlayerActivationScanModuloCritical = 6,
    -- Stage455: hard SP streaming quarantine. This does not alter core gameplay;
    -- it only defers optional world-director/marker/strategic work while the
    -- vanilla engine is already busy streaming chunks, vehicles and assets.
    singlePlayerHardQuarantine = true,
    singlePlayerWarmupQuarantineSeconds = 150,
    singlePlayerHighQuarantineSeconds = 8,
    singlePlayerCriticalQuarantineSeconds = 14,
    singlePlayerQuarantineMinLevel = 2,
    singlePlayerQuarantineTaskHigh = true,
    singlePlayerQuarantineWorldUpdate = true,
    singlePlayerQuarantineMarkerSync = true,
    singlePlayerQuarantineBootstrapSync = true,
    -- Stage456: hard-gate non-critical bootstrap/marker/task bursts during SP warmup.
    -- This only defers virtual-map/debug/strategic bootstrap work; it does not touch
    -- materialized NPCs, mercenary orders, combat, contracts, Black Market or saves.
    singlePlayerBootstrapGate = true,
    singlePlayerBootstrapHardGateSeconds = 240,
    singlePlayerGateMarkerTasks = true,
    singlePlayerGateBaseCampWork = true,
    singlePlayerQuarantineTaskBudgetClamp = true,
    singlePlayerQuarantineTaskBudgetHigh = 1,
    singlePlayerQuarantineTaskBudgetNormal = 0,
    singlePlayerQuarantineTaskBudgetLow = 0,
    -- Stage458: after hard bootstrap gate opens, release optional virtual/base/marker work in small windows.
    singlePlayerPostGateSmoothingSeconds = 180,
    singlePlayerPostGateWindowTicks = 120,
    singlePlayerPostGateTaskSoftCap = 36,
    singlePlayerPostGateMarkerSoftCap = 20,
    singlePlayerPostGateHighPerTick = 1,
    singlePlayerPostGateNormalPerTick = 1,
    singlePlayerPostGateLowPerTick = 0,
    singlePlayerPostGateBasePerWindow = 1,
    singlePlayerPostGateVirtualPerWindow = 2,
    singlePlayerPostGateBattlePerWindow = 1,
    singlePlayerPostGateMarkerPerWindow = 6,
    singlePlayerPostGateBootstrapPerWindow = 1
}

NPCStreamingRuntimeBridge.State = NPCStreamingRuntimeBridge.State or {
    tick = 0,
    level = 0,
    name = "LOW",
    heat = 0,
    score = 0,
    fastTravel = false,
    teleportBurst = false,
    urban = false,
    travelUnloading = false,
    maxSpeed = 0,
    maxChunkDelta = 0,
    teleportBurstUntilHours = 0,
    reasons = {},
    players = {},
    lastLogMs = 0,
    lastSampleTick = 0,
    singlePlayerStreet = false,
    singlePlayerStreetUntilHours = 0,
    activationScanSequence = 0,
    firstSeenAtMs = 0,
    firstSeenAtHours = 0,
    worldQuarantineUntilHours = 0,
    worldQuarantineReason = nil,
    worldQuarantineTask = nil,
    worldQuarantineCount = 0,
    worldQuarantineLastLogMs = 0,
    postGateWindowTick = -1,
    postGateCategoryUsed = {},
    postGateTaskTick = -1,
    postGateTaskUsed = {high=0, normal=0, low=0}
}

local BSR_NAMES = {"LOW", "MEDIUM", "HIGH", "CRITICAL"}

local function bsr_number(name, defaultValue, minValue, maxValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        return NPCLegacySettingsBridge.GetNumber(name, defaultValue, minValue, maxValue)
    end
    local value = tonumber(defaultValue) or 0
    if minValue ~= nil and value < minValue then value = minValue end
    if maxValue ~= nil and value > maxValue then value = maxValue end
    return value
end

local function bsr_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        return NPCLegacySettingsBridge.GetBool(name, defaultValue == true)
    end
    return defaultValue == true
end

local function bsr_nowMs()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then
        local ok, hours = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok and hours then return math.floor((tonumber(hours) or 0) * 3600000) end
    end
    return 0
end

local function bsr_nowHours()
    if getGameTime then
        local ok, hours = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok and hours then return tonumber(hours) or 0 end
    end
    return 0
end

local function bsr_count(tbl, limit)
    if type(tbl) ~= "table" then return 0 end
    local n = 0
    for _, _ in pairs(tbl) do
        n = n + 1
        if limit and n >= limit then return n end
    end
    return n
end

local function bsr_dist(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return math.sqrt(dx * dx + dy * dy)
end

local function bsr_playerKey(player, index)
    if not player then return "player:" .. tostring(index or 0) end
    local ok, value
    if player.getOnlineID then
        ok, value = pcall(function() return player:getOnlineID() end)
        if ok and value ~= nil then return "online:" .. tostring(value) end
    end
    if player.getUsername then
        ok, value = pcall(function() return player:getUsername() end)
        if ok and value ~= nil and tostring(value) ~= "" then return "user:" .. tostring(value) end
    end
    if player.getDisplayName then
        ok, value = pcall(function() return player:getDisplayName() end)
        if ok and value ~= nil and tostring(value) ~= "" then return "name:" .. tostring(value) end
    end
    return "player:" .. tostring(index or 0)
end

local function bsr_eachPlayer(callback)
    if type(callback) ~= "function" then return end

    if getOnlinePlayers then
        local ok, players = pcall(function() return getOnlinePlayers() end)
        if ok and players then
            for i = 0, players:size() - 1 do
                local player = players:get(i)
                if player and not (player.isDead and player:isDead()) then
                    callback(player, i)
                end
            end
            return
        end
    end

    if getNumActivePlayers and getSpecificPlayer then
        local ok, count = pcall(function() return getNumActivePlayers() end)
        count = ok and tonumber(count) or 1
        for i = 0, math.max(0, count - 1) do
            local player = getSpecificPlayer(i)
            if player and not (player.isDead and player:isDead()) then
                callback(player, i)
            end
        end
        return
    end

    if getSpecificPlayer then
        local player = getSpecificPlayer(0)
        if player and not (player.isDead and player:isDead()) then
            callback(player, 0)
        end
    end
end

local function bsr_zoneHeat(player)
    if not player or not player.getSquare then return 0, false end
    local square = nil
    local ok = pcall(function() square = player:getSquare() end)
    if not ok or not square then return 0, false end

    local heat = 0
    local urban = false

    local zone = nil
    pcall(function() zone = square:getZone() end)
    if zone and zone.getType then
        local ztype = tostring(zone:getType() or "")
        if ztype == "TownZone" or ztype == "Nav" or ztype == "TrailerPark" then
            heat = heat + (tonumber(NPCStreamingRuntimeBridge.Config.urbanExtraHeat) or 18)
            urban = true
        elseif string.find(string.lower(ztype), "town", 1, true) or string.find(string.lower(ztype), "city", 1, true) then
            heat = heat + (tonumber(NPCStreamingRuntimeBridge.Config.urbanExtraHeat) or 18)
            urban = true
        end
    end

    local room = nil
    pcall(function() room = square:getRoom() end)
    if room then
        heat = heat + 8
        urban = true
    end

    local building = nil
    pcall(function() building = square:getBuilding() end)
    if building then
        heat = heat + 8
        urban = true
    end

    return heat, urban
end

local function bsr_nearNPCCount(player, radius, limit)
    if not player or not player.getX then return 0 end
    local worldDirector = bsr_worldDirector()
    if worldDirector and worldDirector.CountPhysicalNPCNearPlayer then
        local ok, n = pcall(function() return worldDirector.CountPhysicalNPCNearPlayer(player, radius or 180) end)
        if ok and n then return tonumber(n) or 0 end
    end

    local gmd = nil
    if GetNPCModData then
        pcall(function() gmd = GetNPCModData() end)
    end
    if not (gmd and type(gmd.Queue) == "table") then return 0 end

    local px = tonumber(player:getX()) or 0
    local py = tonumber(player:getY()) or 0
    local r = tonumber(radius) or 180
    local r2 = r * r
    local count = 0
    for _, brain in pairs(gmd.Queue) do
        if type(brain) == "table" then
            local x = brain.debugCoords and tonumber(brain.debugCoords.x) or tonumber(brain.x)
            local y = brain.debugCoords and tonumber(brain.debugCoords.y) or tonumber(brain.y)
            if not x and brain.bornCoords then x = tonumber(brain.bornCoords.x) end
            if not y and brain.bornCoords then y = tonumber(brain.bornCoords.y) end
            if x and y then
                local dx = x - px
                local dy = y - py
                if dx * dx + dy * dy <= r2 then
                    count = count + 1
                    if limit and count >= limit then return count end
                end
            end
        end
    end
    return count
end

local function bsr_pendingSpawnCount()
    local spawnQueue = bsr_spawnQueue()
    if spawnQueue and spawnQueue.PendingCount then
        local ok, n = pcall(function() return spawnQueue.PendingCount() end)
        if ok and n then return tonumber(n) or 0 end
    end
    return 0
end

local function bsr_pendingMarkerCount()
    local n = 0
    if NPCNetContract then
        n = n + bsr_count(NPCNetContract.PendingMarkerUpdates, tonumber(NPCStreamingRuntimeBridge.Config.pendingMarkerCritical) or 220)
        n = n + bsr_count(NPCNetContract.PendingMarkerRemoves, tonumber(NPCStreamingRuntimeBridge.Config.pendingMarkerCritical) or 220)
    end
    return n
end

local function bsr_pendingTaskCount()
    if NPCTaskQueueBridge and NPCTaskQueueBridge.PendingCount then
        local ok, n = pcall(function() return NPCTaskQueueBridge.PendingCount() end)
        if ok and n then return tonumber(n) or 0 end
    end
    return 0
end

function NPCStreamingRuntimeBridge.ApplySettings()
    local c = NPCStreamingRuntimeBridge.Config
    c.enabled = bsr_bool("StreamingRuntime_Enabled", c.enabled ~= false)
    c.debug = bsr_bool("StreamingRuntime_Debug", c.debug == true)
    c.sampleTicks = bsr_number("StreamingRuntime_SampleTicks", c.sampleTicks or 30, 5, 300)
    c.fastVehicleSpeedTilesPerSecond = bsr_number("StreamingRuntime_FastVehicleSpeed", c.fastVehicleSpeedTilesPerSecond or 8.0, 1.0, 80.0)
    c.travelCooldownSeconds = bsr_number("StreamingRuntime_TravelCooldownSeconds", c.travelCooldownSeconds or 12, 0, 120)
    c.teleportDistanceTiles = bsr_number("StreamingRuntime_TeleportDistance", c.teleportDistanceTiles or 80, 20, 2000)
    c.teleportCooldownSeconds = bsr_number("StreamingRuntime_TeleportCooldownSeconds", c.teleportCooldownSeconds or 1, 0, 30)
    c.teleportSnapshotChunksPerTick = bsr_number("StreamingRuntime_TeleportSnapshotChunksPerTick", c.teleportSnapshotChunksPerTick or 6, 1, 16)
    c.deferMaterialization = bsr_bool("StreamingRuntime_DeferMaterialization", c.deferMaterialization ~= false)
    c.deferRetrySeconds = bsr_number("StreamingRuntime_DeferRetrySeconds", c.deferRetrySeconds or 10, 1, 120)
    c.criticalRetrySeconds = bsr_number("StreamingRuntime_CriticalRetrySeconds", c.criticalRetrySeconds or 18, 1, 180)
    c.npcHigh = bsr_number("StreamingRuntime_NPCHigh", c.npcHigh or 32, 0, 500)
    c.npcCritical = bsr_number("StreamingRuntime_NPCCritical", c.npcCritical or 56, c.npcHigh or 32, 1000)
    c.pendingSpawnHigh = bsr_number("StreamingRuntime_PendingSpawnHigh", c.pendingSpawnHigh or 6, 0, 1000)
    c.pendingSpawnCritical = bsr_number("StreamingRuntime_PendingSpawnCritical", c.pendingSpawnCritical or 12, c.pendingSpawnHigh or 6, 5000)
    c.pendingMarkerHigh = bsr_number("StreamingRuntime_PendingMarkerHigh", c.pendingMarkerHigh or 100, 0, 5000)
    c.pendingMarkerCritical = bsr_number("StreamingRuntime_PendingMarkerCritical", c.pendingMarkerCritical or 220, c.pendingMarkerHigh or 100, 20000)
    c.pendingTaskHigh = bsr_number("StreamingRuntime_PendingTaskHigh", c.pendingTaskHigh or 80, 0, 5000)
    c.pendingTaskCritical = bsr_number("StreamingRuntime_PendingTaskCritical", c.pendingTaskCritical or 180, c.pendingTaskHigh or 80, 20000)
    c.mediumThreshold = bsr_number("StreamingRuntime_MediumThreshold", c.mediumThreshold or 38, 1, 1000)
    c.highThreshold = bsr_number("StreamingRuntime_HighThreshold", c.highThreshold or 68, c.mediumThreshold or 38, 1200)
    c.criticalThreshold = bsr_number("StreamingRuntime_CriticalThreshold", c.criticalThreshold or 102, c.highThreshold or 68, 1600)
    c.heatDecayPerSample = bsr_number("StreamingRuntime_HeatDecay", c.heatDecayPerSample or 11, 0, 200)
    c.unloadReliefEnabled = bsr_bool("StreamingRuntime_UnloadReliefEnabled", c.unloadReliefEnabled ~= false)
    c.unloadDespawnRadius = bsr_number("StreamingRuntime_UnloadDespawnRadius", c.unloadDespawnRadius or 260, 80, 1200)
    c.unloadCriticalDespawnRadius = bsr_number("StreamingRuntime_UnloadCriticalDespawnRadius", c.unloadCriticalDespawnRadius or 220, 80, 1200)
    c.unloadCleanupIntervalTicks = bsr_number("StreamingRuntime_UnloadCleanupIntervalTicks", c.unloadCleanupIntervalTicks or 90, 15, 1200)
    c.unloadCriticalCleanupIntervalTicks = bsr_number("StreamingRuntime_UnloadCriticalCleanupIntervalTicks", c.unloadCriticalCleanupIntervalTicks or 45, 15, 1200)
    c.unloadMinAgeSeconds = bsr_number("StreamingRuntime_UnloadMinAgeSeconds", c.unloadMinAgeSeconds or 8, 0, 120)
    c.unloadPauseSpawnQueue = bsr_bool("StreamingRuntime_UnloadPauseSpawnQueue", c.unloadPauseSpawnQueue ~= false)
    c.unloadPauseSnapshotSync = bsr_bool("StreamingRuntime_UnloadPauseSnapshotSync", c.unloadPauseSnapshotSync ~= false)
    c.unloadSnapshotChunksPerTick = bsr_number("StreamingRuntime_UnloadSnapshotChunksPerTick", c.unloadSnapshotChunksPerTick or 1, 0, 8)
    c.unloadSimStateBudget = bsr_number("StreamingRuntime_UnloadSimStateBudget", c.unloadSimStateBudget or 4, 0, 64)
    c.movementExtraHeat = bsr_number("StreamingRuntime_MovementExtraHeat", c.movementExtraHeat or 10, 0, 100)
    c.singlePlayerStreetGovernor = bsr_bool("StreamingRuntime_SPStreetGovernor", c.singlePlayerStreetGovernor ~= false)
    c.singlePlayerRunSpeedTilesPerSecond = bsr_number("StreamingRuntime_SPRunSpeed", c.singlePlayerRunSpeedTilesPerSecond or 3.2, 1.0, 20.0)
    c.singlePlayerRunExtraHeat = bsr_number("StreamingRuntime_SPRunExtraHeat", c.singlePlayerRunExtraHeat or 46, 0, 200)
    c.singlePlayerChunkExtraHeat = bsr_number("StreamingRuntime_SPChunkExtraHeat", c.singlePlayerChunkExtraHeat or 18, 0, 160)
    c.singlePlayerCooldownSeconds = bsr_number("StreamingRuntime_SPCooldownSeconds", c.singlePlayerCooldownSeconds or 16, 0, 90)
    c.singlePlayerActivationDeferDistance = bsr_number("StreamingRuntime_SPActivationDeferDistance", c.singlePlayerActivationDeferDistance or 75, 20, 180)
    c.singlePlayerCriticalActivationDistance = bsr_number("StreamingRuntime_SPCriticalActivationDistance", c.singlePlayerCriticalActivationDistance or 55, 15, 160)
    c.singlePlayerSpawnDeferDistance = bsr_number("StreamingRuntime_SPSpawnDeferDistance", c.singlePlayerSpawnDeferDistance or 70, 20, 180)
    c.singlePlayerHighSpawnSkipModulo = bsr_number("StreamingRuntime_SPHighSpawnSkipModulo", c.singlePlayerHighSpawnSkipModulo or 4, 2, 12)
    c.singlePlayerCriticalSpawnSkipModulo = bsr_number("StreamingRuntime_SPCriticalSpawnSkipModulo", c.singlePlayerCriticalSpawnSkipModulo or 6, 2, 18)
    c.singlePlayerActivationScanModuloHigh = bsr_number("StreamingRuntime_SPActivationScanModuloHigh", c.singlePlayerActivationScanModuloHigh or 3, 1, 12)
    c.singlePlayerActivationScanModuloCritical = bsr_number("StreamingRuntime_SPActivationScanModuloCritical", c.singlePlayerActivationScanModuloCritical or 6, 1, 18)
    c.singlePlayerHardQuarantine = bsr_bool("StreamingRuntime_SPHardQuarantine", c.singlePlayerHardQuarantine ~= false)
    c.singlePlayerWarmupQuarantineSeconds = bsr_number("StreamingRuntime_SPWarmupQuarantineSeconds", c.singlePlayerWarmupQuarantineSeconds or 150, 0, 900)
    c.singlePlayerHighQuarantineSeconds = bsr_number("StreamingRuntime_SPHighQuarantineSeconds", c.singlePlayerHighQuarantineSeconds or 8, 0, 120)
    c.singlePlayerCriticalQuarantineSeconds = bsr_number("StreamingRuntime_SPCriticalQuarantineSeconds", c.singlePlayerCriticalQuarantineSeconds or 14, 0, 180)
    c.singlePlayerQuarantineMinLevel = bsr_number("StreamingRuntime_SPQuarantineMinLevel", c.singlePlayerQuarantineMinLevel or 2, 1, 3)
    c.singlePlayerQuarantineTaskHigh = bsr_bool("StreamingRuntime_SPQuarantineTaskHigh", c.singlePlayerQuarantineTaskHigh ~= false)
    c.singlePlayerQuarantineWorldUpdate = bsr_bool("StreamingRuntime_SPQuarantineWorldUpdate", c.singlePlayerQuarantineWorldUpdate ~= false)
    c.singlePlayerQuarantineMarkerSync = bsr_bool("StreamingRuntime_SPQuarantineMarkerSync", c.singlePlayerQuarantineMarkerSync ~= false)
    c.singlePlayerQuarantineBootstrapSync = bsr_bool("StreamingRuntime_SPQuarantineBootstrapSync", c.singlePlayerQuarantineBootstrapSync ~= false)
    c.singlePlayerBootstrapGate = bsr_bool("StreamingRuntime_SPBootstrapGate", c.singlePlayerBootstrapGate ~= false)
    c.singlePlayerBootstrapHardGateSeconds = bsr_number("StreamingRuntime_SPBootstrapHardGateSeconds", c.singlePlayerBootstrapHardGateSeconds or 240, 0, 900)
    c.singlePlayerGateMarkerTasks = bsr_bool("StreamingRuntime_SPGateMarkerTasks", c.singlePlayerGateMarkerTasks ~= false)
    c.singlePlayerGateBaseCampWork = bsr_bool("StreamingRuntime_SPGateBaseCampWork", c.singlePlayerGateBaseCampWork ~= false)
    c.singlePlayerQuarantineTaskBudgetClamp = bsr_bool("StreamingRuntime_SPQuarantineTaskBudgetClamp", c.singlePlayerQuarantineTaskBudgetClamp ~= false)
    c.singlePlayerQuarantineTaskBudgetHigh = bsr_number("StreamingRuntime_SPQuarantineTaskBudgetHigh", c.singlePlayerQuarantineTaskBudgetHigh or 1, 0, 20)
    c.singlePlayerQuarantineTaskBudgetNormal = bsr_number("StreamingRuntime_SPQuarantineTaskBudgetNormal", c.singlePlayerQuarantineTaskBudgetNormal or 0, 0, 50)
    c.singlePlayerQuarantineTaskBudgetLow = bsr_number("StreamingRuntime_SPQuarantineTaskBudgetLow", c.singlePlayerQuarantineTaskBudgetLow or 0, 0, 80)
    c.singlePlayerPostGateSmoothingSeconds = bsr_number("StreamingRuntime_SPPostGateSmoothingSeconds", c.singlePlayerPostGateSmoothingSeconds or 180, 0, 900)
    c.singlePlayerPostGateWindowTicks = bsr_number("StreamingRuntime_SPPostGateWindowTicks", c.singlePlayerPostGateWindowTicks or 120, 15, 1800)
    c.singlePlayerPostGateTaskSoftCap = bsr_number("StreamingRuntime_SPPostGateTaskSoftCap", c.singlePlayerPostGateTaskSoftCap or 36, 0, 240)
    c.singlePlayerPostGateMarkerSoftCap = bsr_number("StreamingRuntime_SPPostGateMarkerSoftCap", c.singlePlayerPostGateMarkerSoftCap or 20, 0, 240)
    c.singlePlayerPostGateHighPerTick = bsr_number("StreamingRuntime_SPPostGateHighPerTick", c.singlePlayerPostGateHighPerTick or 1, 0, 20)
    c.singlePlayerPostGateNormalPerTick = bsr_number("StreamingRuntime_SPPostGateNormalPerTick", c.singlePlayerPostGateNormalPerTick or 1, 0, 50)
    c.singlePlayerPostGateLowPerTick = bsr_number("StreamingRuntime_SPPostGateLowPerTick", c.singlePlayerPostGateLowPerTick or 0, 0, 80)
    c.singlePlayerPostGateBasePerWindow = bsr_number("StreamingRuntime_SPPostGateBasePerWindow", c.singlePlayerPostGateBasePerWindow or 1, 0, 60)
    c.singlePlayerPostGateVirtualPerWindow = bsr_number("StreamingRuntime_SPPostGateVirtualPerWindow", c.singlePlayerPostGateVirtualPerWindow or 2, 0, 80)
    c.singlePlayerPostGateBattlePerWindow = bsr_number("StreamingRuntime_SPPostGateBattlePerWindow", c.singlePlayerPostGateBattlePerWindow or 1, 0, 60)
    c.singlePlayerPostGateMarkerPerWindow = bsr_number("StreamingRuntime_SPPostGateMarkerPerWindow", c.singlePlayerPostGateMarkerPerWindow or 6, 0, 200)
    c.singlePlayerPostGateBootstrapPerWindow = bsr_number("StreamingRuntime_SPPostGateBootstrapPerWindow", c.singlePlayerPostGateBootstrapPerWindow or 1, 0, 60)
end

local function bsr_setLevel(score)
    local c = NPCStreamingRuntimeBridge.Config
    local level = 0
    if score >= (tonumber(c.criticalThreshold) or 102) then
        level = 3
    elseif score >= (tonumber(c.highThreshold) or 68) then
        level = 2
    elseif score >= (tonumber(c.mediumThreshold) or 38) then
        level = 1
    end
    NPCStreamingRuntimeBridge.State.level = level
    NPCStreamingRuntimeBridge.State.name = BSR_NAMES[level + 1] or "LOW"
end

local function bsr_addReason(reasons, name, value)
    reasons[#reasons + 1] = tostring(name) .. "=" .. tostring(value)
end

function NPCStreamingRuntimeBridge.Sample()
    local c = NPCStreamingRuntimeBridge.Config
    local s = NPCStreamingRuntimeBridge.State
    if not c.enabled then
        s.level = 0
        s.name = "LOW"
        s.fastTravel = false
        s.teleportBurst = false
        s.urban = false
        s.travelUnloading = false
        s.maxSpeed = 0
        s.maxChunkDelta = 0
        s.score = 0
        s.heat = 0
        s.singlePlayerStreet = false
        s.singlePlayerStreetUntilHours = 0
        return
    end

    local maxPlayerScore = 0
    local anyFastTravel = false
    local anyTeleportBurst = false
    local anyUrban = false
    local anySinglePlayerStreet = false
    local maxNPC = 0
    local maxSpeed = 0
    local maxChunkDelta = 0
    local reasons = {}

    bsr_eachPlayer(function(player, index)
        local key = bsr_playerKey(player, index)
        local px = tonumber(player:getX()) or 0
        local py = tonumber(player:getY()) or 0
        local pz = tonumber(player:getZ()) or 0
        local prev = s.players[key]
        local dist = 0
        local dtTicks = tonumber(c.sampleTicks) or 30
        if prev then
            dist = bsr_dist(px, py, prev.x, prev.y)
            dtTicks = math.max(1, (s.tick or 0) - (tonumber(prev.tick) or s.tick or 0))
        end
        local speed = dist / math.max(0.1, dtTicks / 60.0)
        if speed > maxSpeed then maxSpeed = speed end

        local vehicle = false
        if player.getVehicle then
            pcall(function() vehicle = player:getVehicle() ~= nil end)
        end

        local chunkX = math.floor(px / 10)
        local chunkY = math.floor(py / 10)
        local chunkDelta = 0
        if prev then
            chunkDelta = math.abs(chunkX - (tonumber(prev.chunkX) or chunkX)) + math.abs(chunkY - (tonumber(prev.chunkY) or chunkY))
            if chunkDelta > maxChunkDelta then maxChunkDelta = chunkDelta end
        end

        s.players[key] = {x=px, y=py, z=pz, tick=s.tick or 0, chunkX=chunkX, chunkY=chunkY, speed=speed, vehicle=vehicle}

        local score = 0
        local urbanHeat, urban = bsr_zoneHeat(player)
        if urban then
            score = score + urbanHeat
            anyUrban = true
        end

        if vehicle and speed >= (tonumber(c.fastVehicleSpeedTilesPerSecond) or 8.0) then
            score = score + (tonumber(c.vehicleExtraHeat) or 24)
            anyFastTravel = true
            bsr_addReason(reasons, "fastVehicle", math.floor(speed * 10) / 10)
        end

        if prev and dist >= (tonumber(c.teleportDistanceTiles) or 80) then
            anyFastTravel = true
            anyTeleportBurst = true
            bsr_addReason(reasons, "teleportBurst", math.floor(dist))
        end

        if chunkDelta >= 2 then
            score = score + (tonumber(c.chunkChangeExtraHeat) or 14) + math.min(30, chunkDelta * 3)
            bsr_addReason(reasons, "chunkDelta", chunkDelta)
        elseif chunkDelta >= 1 then
            score = score + (tonumber(c.movementExtraHeat) or 10)
            bsr_addReason(reasons, "chunkStep", chunkDelta)
        end

        if bsr_isSinglePlayerGovernorEnabled() and not vehicle then
            local spRunSpeed = tonumber(c.singlePlayerRunSpeedTilesPerSecond) or 3.2
            if speed >= spRunSpeed then
                score = score + (tonumber(c.singlePlayerRunExtraHeat) or 46)
                anyFastTravel = true
                anySinglePlayerStreet = true
                bsr_addReason(reasons, "spRun", math.floor(speed * 10) / 10)
            elseif chunkDelta >= 1 and urban then
                score = score + (tonumber(c.singlePlayerChunkExtraHeat) or 18)
                anySinglePlayerStreet = true
                bsr_addReason(reasons, "spChunk", chunkDelta)
            end
        end

        local npc = bsr_nearNPCCount(player, 180, tonumber(c.npcCritical) or 56)
        maxNPC = math.max(maxNPC, npc)
        if npc >= (tonumber(c.npcCritical) or 56) then
            score = score + 42
            bsr_addReason(reasons, "npcCritical", npc)
        elseif npc >= (tonumber(c.npcHigh) or 32) then
            score = score + 22
            bsr_addReason(reasons, "npcHigh", npc)
        end

        maxPlayerScore = math.max(maxPlayerScore, score)
    end)

    local pendingSpawn = bsr_pendingSpawnCount()
    if pendingSpawn >= (tonumber(c.pendingSpawnCritical) or 12) then
        maxPlayerScore = maxPlayerScore + 34
        bsr_addReason(reasons, "spawnCritical", pendingSpawn)
    elseif pendingSpawn >= (tonumber(c.pendingSpawnHigh) or 6) then
        maxPlayerScore = maxPlayerScore + 16
        bsr_addReason(reasons, "spawnHigh", pendingSpawn)
    end

    local pendingMarkers = bsr_pendingMarkerCount()
    if pendingMarkers >= (tonumber(c.pendingMarkerCritical) or 220) then
        maxPlayerScore = maxPlayerScore + 30
        bsr_addReason(reasons, "markerCritical", pendingMarkers)
    elseif pendingMarkers >= (tonumber(c.pendingMarkerHigh) or 100) then
        maxPlayerScore = maxPlayerScore + 12
        bsr_addReason(reasons, "markerHigh", pendingMarkers)
    end

    local pendingTasks = bsr_pendingTaskCount()
    if pendingTasks >= (tonumber(c.pendingTaskCritical) or 180) then
        maxPlayerScore = maxPlayerScore + 24
        bsr_addReason(reasons, "taskCritical", pendingTasks)
    elseif pendingTasks >= (tonumber(c.pendingTaskHigh) or 80) then
        maxPlayerScore = maxPlayerScore + 10
        bsr_addReason(reasons, "taskHigh", pendingTasks)
    end

    local nowHours = bsr_nowHours()
    if anyTeleportBurst then
        local teleportCooldown = math.max(0, tonumber(c.teleportCooldownSeconds) or 1)
        s.teleportBurstUntilHours = nowHours + (teleportCooldown / 3600)
        s.fastTravelUntilHours = nowHours + (teleportCooldown / 3600)
    elseif anyFastTravel then
        local cooldownSeconds = tonumber(c.travelCooldownSeconds) or 12
        if anySinglePlayerStreet then
            cooldownSeconds = math.max(cooldownSeconds, tonumber(c.singlePlayerCooldownSeconds) or 16)
            s.singlePlayerStreetUntilHours = nowHours + (cooldownSeconds / 3600)
        end
        s.fastTravelUntilHours = nowHours + (cooldownSeconds / 3600)
    elseif (tonumber(s.fastTravelUntilHours) or 0) > nowHours then
        anyFastTravel = true
        if bsr_isSinglePlayerGovernorEnabled() and (tonumber(s.singlePlayerStreetUntilHours) or 0) > nowHours then
            anySinglePlayerStreet = true
            bsr_addReason(reasons, "spCooldown", math.floor(((s.singlePlayerStreetUntilHours or nowHours) - nowHours) * 3600))
        else
            bsr_addReason(reasons, "travelCooldown", math.floor(((s.fastTravelUntilHours or nowHours) - nowHours) * 3600))
        end
    elseif bsr_isSinglePlayerGovernorEnabled() and (tonumber(s.singlePlayerStreetUntilHours) or 0) > nowHours then
        anySinglePlayerStreet = true
        anyFastTravel = true
        bsr_addReason(reasons, "spCooldown", math.floor(((s.singlePlayerStreetUntilHours or nowHours) - nowHours) * 3600))
    end

    local teleportBurstActive = (tonumber(s.teleportBurstUntilHours) or 0) > nowHours
    if teleportBurstActive then anyTeleportBurst = true end

    local heatDecay = tonumber(c.heatDecayPerSample) or 11
    if teleportBurstActive then heatDecay = math.max(heatDecay, 24) end
    local heat = math.max(0, (tonumber(s.heat) or 0) - heatDecay)
    if anyFastTravel then
        heat = math.max(heat, maxPlayerScore + 16)
    elseif maxPlayerScore > heat then
        heat = maxPlayerScore
    end

    s.heat = heat
    s.score = math.max(maxPlayerScore, heat)
    s.fastTravel = anyFastTravel
    s.teleportBurst = anyTeleportBurst
    s.urban = anyUrban
    s.maxSpeed = maxSpeed
    s.maxChunkDelta = maxChunkDelta
    s.singlePlayerStreet = anySinglePlayerStreet
    s.travelUnloading = (c.unloadReliefEnabled ~= false) and (anyFastTravel or anySinglePlayerStreet or maxChunkDelta >= 1 or maxSpeed >= math.max(3.0, (tonumber(c.fastVehicleSpeedTilesPerSecond) or 8.0) * 0.55)) or false
    s.maxNPCNearPlayer = maxNPC
    s.pendingSpawn = pendingSpawn
    s.pendingMarkers = pendingMarkers
    s.pendingTasks = pendingTasks
    s.reasons = reasons
    s.sampledAtMs = bsr_nowMs()
    s.sampledAtHours = bsr_nowHours()
    bsr_setLevel(s.score)

    if c.debug and s.level > 0 then
        local now = bsr_nowMs()
        if now - (tonumber(s.lastLogMs) or 0) >= 5000 then
            s.lastLogMs = now
            print("[NPCStreamingRuntimeBridge] pressure=" .. tostring(s.name) .. " score=" .. tostring(math.floor(s.score or 0)) .. " npc=" .. tostring(maxNPC) .. " spawnQ=" .. tostring(pendingSpawn) .. " markerQ=" .. tostring(pendingMarkers) .. " taskQ=" .. tostring(pendingTasks) .. " reasons=" .. table.concat(reasons, ","))
        end
    end
end

function NPCStreamingRuntimeBridge.OnTick()
    local s = NPCStreamingRuntimeBridge.State
    if (tonumber(s.firstSeenAtMs) or 0) <= 0 then
        s.firstSeenAtMs = bsr_nowMs()
        s.firstSeenAtHours = bsr_nowHours()
    end
    s.tick = (tonumber(s.tick) or 0) + 1
    local sampleTicks = tonumber(NPCStreamingRuntimeBridge.Config.sampleTicks) or 30
    if s.tick % 300 == 1 then
        NPCStreamingRuntimeBridge.ApplySettings()
    end
    if s.tick - (tonumber(s.lastSampleTick) or 0) >= sampleTicks then
        s.lastSampleTick = s.tick
        NPCStreamingRuntimeBridge.Sample()
    end
end

function NPCStreamingRuntimeBridge.GetLevel()
    if not NPCStreamingRuntimeBridge.Config.enabled then return 0 end
    return tonumber(NPCStreamingRuntimeBridge.State.level) or 0
end

function NPCStreamingRuntimeBridge.GetPressureName()
    return NPCStreamingRuntimeBridge.State.name or "LOW"
end

function NPCStreamingRuntimeBridge.IsHigh()
    return NPCStreamingRuntimeBridge.GetLevel() >= 2
end

function NPCStreamingRuntimeBridge.IsCritical()
    return NPCStreamingRuntimeBridge.GetLevel() >= 3
end
function NPCStreamingRuntimeBridge.IsTravelUnloading()
    if not NPCStreamingRuntimeBridge.Config.enabled then return false end
    if NPCStreamingRuntimeBridge.Config.unloadReliefEnabled == false then return false end
    local s = NPCStreamingRuntimeBridge.State
    local level = NPCStreamingRuntimeBridge.GetLevel()
    if s.teleportBurst then return true end
    if level >= 2 and s.travelUnloading then return true end
    if level >= 1 and s.fastTravel then return true end
    return false
end

function NPCStreamingRuntimeBridge.GetUnloadCleanupIntervalTicks(current)
    if not NPCStreamingRuntimeBridge.IsTravelUnloading() then return current end
    local c = NPCStreamingRuntimeBridge.Config
    local level = NPCStreamingRuntimeBridge.GetLevel()
    local interval = level >= 3 and (tonumber(c.unloadCriticalCleanupIntervalTicks) or 45) or (tonumber(c.unloadCleanupIntervalTicks) or 90)
    if current and tonumber(current) and tonumber(current) > 0 then
        return math.max(15, math.min(tonumber(current), interval))
    end
    return math.max(15, interval)
end

function NPCStreamingRuntimeBridge.GetUnloadDespawnRadius(group, currentRadius, activationRadius)
    if not NPCStreamingRuntimeBridge.IsTravelUnloading() then return currentRadius end
    if group and (group.mercenaryHired or group.hired or group.isPlayerGuard or group.followPlayer or group.guardPlayer or group.inBattle or group.virtualBattle or group.battleId or group.enemyGroupId or group.bountyHunter or group.leaderId or group.isFactionLeader or group.economyConvoy or group.convoyId or group.blackMarket or group.blackMarketNPC or group.blackMarketService) then
        return currentRadius
    end
    local c = NPCStreamingRuntimeBridge.Config
    local level = NPCStreamingRuntimeBridge.GetLevel()
    local radius = level >= 3 and (tonumber(c.unloadCriticalDespawnRadius) or 220) or (tonumber(c.unloadDespawnRadius) or 260)
    local activation = tonumber(activationRadius) or 190
    radius = math.max(activation + 30, radius)
    if currentRadius and tonumber(currentRadius) then
        radius = math.min(tonumber(currentRadius), radius)
    end
    return radius
end

local bsr_groupPlayerDistance

function NPCStreamingRuntimeBridge.GetUnloadMinAgeHours(current)
    if not NPCStreamingRuntimeBridge.IsTravelUnloading() then return current end
    local seconds = tonumber(NPCStreamingRuntimeBridge.Config.unloadMinAgeSeconds) or 8
    local hours = math.max(0, seconds) / 3600
    if current and tonumber(current) and tonumber(current) > 0 then
        return math.min(tonumber(current), hours)
    end
    return hours
end

function NPCStreamingRuntimeBridge.ShouldDeferQueuedSpawn(entry, group, player)
    if not NPCStreamingRuntimeBridge.Config.enabled then return false end
    if NPCStreamingRuntimeBridge.Config.unloadPauseSpawnQueue == false then return false end
    if not NPCStreamingRuntimeBridge.IsTravelUnloading() then return false end
    if group and (group.mercenaryHired or group.hired or group.isPlayerGuard or group.followPlayer or group.guardPlayer or group.inBattle or group.virtualBattle or group.battleId or group.enemyGroupId or group.bountyHunter or group.leaderId or group.isFactionLeader or group.economyConvoy or group.convoyId or group.blackMarket or group.blackMarketNPC or group.blackMarketService) then
        return false
    end

    local level = NPCStreamingRuntimeBridge.GetLevel()
    local spStreet = bsr_isSinglePlayerGovernorEnabled() and NPCStreamingRuntimeBridge.State.singlePlayerStreet
    if player and not spStreet then return false end
    if player and spStreet then
        local dist = bsr_groupPlayerDistance(group, player, entry and entry.event or nil)
        if dist and dist < (tonumber(NPCStreamingRuntimeBridge.Config.singlePlayerSpawnDeferDistance) or 70) and level < 3 then
            return false
        end
    end

    local retry = level >= 3 and (tonumber(NPCStreamingRuntimeBridge.Config.criticalRetrySeconds) or 18) or (tonumber(NPCStreamingRuntimeBridge.Config.deferRetrySeconds) or 10)
    if spStreet then
        return true, math.max(30, math.floor(retry * 60)), level >= 3 and "sp_streaming_spawn_pause_critical" or "sp_streaming_spawn_pause"
    end
    return true, math.max(30, math.floor(retry * 60)), level >= 3 and "streaming_unload_spawn_pause_critical" or "streaming_unload_spawn_pause"
end

function NPCStreamingRuntimeBridge.AdjustSnapshotBudget(budget)
    budget = tonumber(budget) or 0
    if budget <= 0 then return budget end
    if not NPCStreamingRuntimeBridge.IsTravelUnloading() then return budget end
    if NPCStreamingRuntimeBridge.State.teleportBurst then
        return math.max(1, math.min(budget, tonumber(NPCStreamingRuntimeBridge.Config.teleportSnapshotChunksPerTick) or 6))
    end
    if NPCStreamingRuntimeBridge.Config.unloadPauseSnapshotSync == false then return math.max(1, math.min(budget, tonumber(NPCStreamingRuntimeBridge.Config.unloadSnapshotChunksPerTick) or 1)) end
    local tick = tonumber(NPCStreamingRuntimeBridge.State.tick) or 0
    local level = NPCStreamingRuntimeBridge.GetLevel()
    if level >= 3 then
        if tick % 5 ~= 0 then return 0 end
        return math.max(0, math.min(budget, tonumber(NPCStreamingRuntimeBridge.Config.unloadSnapshotChunksPerTick) or 1))
    end
    if tick % 3 ~= 0 then return 0 end
    return math.max(0, math.min(budget, tonumber(NPCStreamingRuntimeBridge.Config.unloadSnapshotChunksPerTick) or 1))
end

function NPCStreamingRuntimeBridge.AdjustSimStateBudget(budget)
    budget = tonumber(budget) or 0
    if budget <= 0 then return budget end
    if not NPCStreamingRuntimeBridge.IsTravelUnloading() then return budget end
    return math.max(0, math.min(budget, tonumber(NPCStreamingRuntimeBridge.Config.unloadSimStateBudget) or 4))
end


function NPCStreamingRuntimeBridge.GetBudgetScale(kind)
    local level = NPCStreamingRuntimeBridge.GetLevel()
    if level <= 0 then return 1.0 end
    kind = tostring(kind or "ai")

    if bsr_isSinglePlayerGovernorEnabled() and NPCStreamingRuntimeBridge.State.singlePlayerStreet then
        if kind == "combat" then
            if level == 1 then return 0.85 end
            if level == 2 then return 0.70 end
            return 0.55
        end
        if level == 1 then
            if kind == "marker" then return 0.55 end
            if kind == "spawn" then return 0.55 end
            if kind == "zombie" then return 0.70 end
            return 0.65
        elseif level == 2 then
            if kind == "marker" then return 0.30 end
            if kind == "spawn" then return 0.25 end
            if kind == "zombie" then return 0.45 end
            return 0.35
        else
            if kind == "marker" then return 0.18 end
            if kind == "spawn" then return 0.15 end
            if kind == "zombie" then return 0.28 end
            return 0.25
        end
    end

    if level == 1 then
        if kind == "marker" then return 0.75 end
        if kind == "spawn" then return 0.75 end
        return 0.85
    elseif level == 2 then
        if kind == "combat" then return 0.75 end
        if kind == "marker" then return 0.45 end
        if kind == "spawn" then return 0.50 end
        if kind == "zombie" then return 0.60 end
        return 0.55
    end

    if kind == "combat" then return 0.60 end
    if kind == "marker" then return 0.25 end
    if kind == "spawn" then return 0.35 end
    if kind == "zombie" then return 0.40 end
    return 0.35
end

function NPCStreamingRuntimeBridge.AdjustBudget(kind, budget)
    budget = tonumber(budget) or 1
    local scaled = budget * NPCStreamingRuntimeBridge.GetBudgetScale(kind)
    return math.max(1, math.floor(scaled + 0.0001))
end

function NPCStreamingRuntimeBridge.AdjustTaskBudget(priority, budget)
    local level = NPCStreamingRuntimeBridge.GetLevel()
    budget = tonumber(budget) or 0
    if budget <= 0 then return budget end
    priority = tostring(priority or "normal")

    -- Stage456: during SP bootstrap/streaming quarantine, do not drain large
    -- debug/strategic queues in the same frames where the engine streams chunks.
    -- High priority keeps a tiny safety budget; normal/low marker/world tasks wait.
    if NPCStreamingRuntimeBridge.Config.singlePlayerQuarantineTaskBudgetClamp ~= false then
        local gate = false
        local okGate, gateValue = pcall(function() return NPCStreamingRuntimeBridge.ShouldGateWorldBootstrapTask("task_budget:" .. priority) end)
        if okGate and gateValue == true then gate = true end
        if not gate then
            local q = NPCStreamingRuntimeBridge.GetQuarantineDiagnostics and NPCStreamingRuntimeBridge.GetQuarantineDiagnostics() or nil
            gate = q and q.active == true
        end
        if gate then
            if priority == "high" then
                return math.max(0, math.min(budget, tonumber(NPCStreamingRuntimeBridge.Config.singlePlayerQuarantineTaskBudgetHigh) or 1))
            elseif priority == "normal" then
                return math.max(0, math.min(budget, tonumber(NPCStreamingRuntimeBridge.Config.singlePlayerQuarantineTaskBudgetNormal) or 0))
            else
                return math.max(0, math.min(budget, tonumber(NPCStreamingRuntimeBridge.Config.singlePlayerQuarantineTaskBudgetLow) or 0))
            end
        end
    end

    if level <= 0 then return budget end

    local scale = 1.0
    if level == 1 then
        scale = priority == "low" and 0.70 or 0.85
    elseif level == 2 then
        scale = priority == "high" and 0.75 or (priority == "normal" and 0.50 or 0.30)
    else
        scale = priority == "high" and 0.55 or (priority == "normal" and 0.30 or 0.15)
    end

    return math.max(priority == "high" and 1 or 0, math.floor(budget * scale + 0.0001))
end

function NPCStreamingRuntimeBridge.AdjustInterval(kind, interval, brain)
    interval = tonumber(interval) or 1
    local level = NPCStreamingRuntimeBridge.GetLevel()
    if level <= 0 then return math.max(1, math.floor(interval)) end

    if brain and (brain.inBattle or brain.target or brain.targetId or brain.enemy or brain.lastKnownEnemyPosition) then
        if level == 1 then return math.max(1, math.floor(interval * 1.10)) end
        if level == 2 then return math.max(1, math.floor(interval * 1.25)) end
        return math.max(1, math.floor(interval * 1.50))
    end

    if level == 1 then return math.max(1, math.floor(interval * 1.35)) end
    if level == 2 then return math.max(1, math.floor(interval * 2.10)) end
    return math.max(1, math.floor(interval * 3.00))
end

function NPCStreamingRuntimeBridge.AdjustMarkerInterval(interval)
    interval = tonumber(interval) or 8
    local level = NPCStreamingRuntimeBridge.GetLevel()
    if level == 1 then return math.max(1, math.floor(interval * 1.50)) end
    if level == 2 then return math.max(1, math.floor(interval * 2.50)) end
    if level >= 3 then return math.max(1, math.floor(interval * 4.00)) end
    return math.max(1, math.floor(interval))
end

function NPCStreamingRuntimeBridge.AdjustNavRepairBudget(budget)
    return NPCStreamingRuntimeBridge.AdjustBudget("zombie", budget)
end

function NPCStreamingRuntimeBridge.AdjustNetMarkerBudget(budget)
    return NPCStreamingRuntimeBridge.AdjustBudget("marker", budget)
end

function NPCStreamingRuntimeBridge.AdjustMarkerMoveDelta(delta)
    delta = tonumber(delta) or 4
    local level = NPCStreamingRuntimeBridge.GetLevel()
    if level == 1 then return math.max(delta, 6) end
    if level == 2 then return math.max(delta, 10) end
    if level >= 3 then return math.max(delta, 16) end
    return delta
end

function NPCStreamingRuntimeBridge.AdjustMarkerHours(hours, virtual)
    hours = tonumber(hours) or 0
    local level = NPCStreamingRuntimeBridge.GetLevel()
    if level == 1 then return hours * (virtual and 1.4 or 1.25) end
    if level == 2 then return hours * (virtual and 2.5 or 1.8) end
    if level >= 3 then return hours * (virtual and 4.0 or 2.8) end
    return hours
end

function NPCStreamingRuntimeBridge.AdjustSpawnEventBudget(budget)
    return NPCStreamingRuntimeBridge.AdjustBudget("spawn", budget)
end

function NPCStreamingRuntimeBridge.ShouldSkipSpawnTick(tick)
    local level = NPCStreamingRuntimeBridge.GetLevel()
    tick = tonumber(tick) or 0
    if bsr_isSinglePlayerGovernorEnabled() and NPCStreamingRuntimeBridge.State.singlePlayerStreet then
        if level >= 3 then return (tick % (tonumber(NPCStreamingRuntimeBridge.Config.singlePlayerCriticalSpawnSkipModulo) or 6)) ~= 0 end
        if level >= 2 then return (tick % (tonumber(NPCStreamingRuntimeBridge.Config.singlePlayerHighSpawnSkipModulo) or 4)) ~= 0 end
        if level >= 1 and NPCStreamingRuntimeBridge.IsTravelUnloading() then return (tick % 2) ~= 0 end
    end
    if level >= 3 then return (tick % 4) ~= 0 end
    if level >= 2 and NPCStreamingRuntimeBridge.IsTravelUnloading() then return (tick % 3) ~= 0 end
    return false
end

bsr_groupPlayerDistance = function(group, player, event)
    if not player or not player.getX then return nil end
    local gx = group and tonumber(group.x) or nil
    local gy = group and tonumber(group.y) or nil
    if (not gx or not gy) and type(event) == "table" then
        gx = gx or tonumber(event.x)
        gy = gy or tonumber(event.y)
    end
    if not gx or not gy then return nil end
    local px = nil
    local py = nil
    local ok = pcall(function()
        px = tonumber(player:getX())
        py = tonumber(player:getY())
    end)
    if not ok or not px or not py then return nil end
    local dx = gx - px
    local dy = gy - py
    return math.sqrt(dx * dx + dy * dy)
end

function NPCStreamingRuntimeBridge.ShouldSkipActivationScan(source, tick)
    if not bsr_isSinglePlayerGovernorEnabled() then return false end
    local level = NPCStreamingRuntimeBridge.GetLevel()
    if level <= 0 then return false end
    if not NPCStreamingRuntimeBridge.IsTravelUnloading() and not NPCStreamingRuntimeBridge.State.singlePlayerStreet then return false end

    local sourceName = tostring(source or "tick")
    if sourceName == "world_update" and level < 3 then return false end

    local modulo = nil
    if level >= 3 then
        modulo = tonumber(NPCStreamingRuntimeBridge.Config.singlePlayerActivationScanModuloCritical) or 6
    elseif level >= 2 then
        modulo = tonumber(NPCStreamingRuntimeBridge.Config.singlePlayerActivationScanModuloHigh) or 3
    elseif NPCStreamingRuntimeBridge.State.singlePlayerStreet then
        modulo = 2
    else
        return false
    end

    local s = NPCStreamingRuntimeBridge.State
    s.activationScanSequence = (tonumber(s.activationScanSequence) or 0) + 1
    return (s.activationScanSequence % math.max(1, math.floor(modulo))) ~= 0
end

local function bsr_importantGroup(group)
    if not group then return false end
    if group.inBattle or group.virtualBattle or group.battleId or group.enemyGroupId then return true end
    if group.bountyHunter or group.targetClass == "bounty_hunt" then return true end
    if group.mercenaryHired or group.hired or group.isPlayerGuard then return true end
    if group.leaderId or group.isFactionLeader then return true end
    return false
end

function NPCStreamingRuntimeBridge.ShouldDeferActivation(group, player, budget)
    if not NPCStreamingRuntimeBridge.Config.enabled then return nil end
    if not NPCStreamingRuntimeBridge.Config.deferMaterialization then return nil end
    if NPCStreamingRuntimeBridge.State and NPCStreamingRuntimeBridge.State.teleportBurst then return nil end

    local level = NPCStreamingRuntimeBridge.GetLevel()
    local spStreet = bsr_isSinglePlayerGovernorEnabled() and NPCStreamingRuntimeBridge.State.singlePlayerStreet
    if level < 2 and not (spStreet and level >= 1) then return nil end
    if bsr_importantGroup(group) then return nil end

    if spStreet and player then
        local dist = bsr_groupPlayerDistance(group, player, nil)
        if dist then
            if level >= 3 and dist < (tonumber(NPCStreamingRuntimeBridge.Config.singlePlayerCriticalActivationDistance) or 55) then return nil end
            if level < 3 and dist < (tonumber(NPCStreamingRuntimeBridge.Config.singlePlayerActivationDeferDistance) or 75) then return nil end
        end
    end

    local worldDirector = bsr_worldDirector()
    if worldDirector and worldDirector.IsPlayerOnDebugMarker and group and player then
        local ok, onMarker = pcall(function() return worldDirector.IsPlayerOnDebugMarker(group, player) end)
        if ok and onMarker then return nil end
    end

    local retrySeconds = level >= 3 and (tonumber(NPCStreamingRuntimeBridge.Config.criticalRetrySeconds) or 18) or (tonumber(NPCStreamingRuntimeBridge.Config.deferRetrySeconds) or 10)
    local reason
    if spStreet then
        reason = level >= 3 and "sp_streaming_runtime_critical" or (level >= 2 and "sp_streaming_runtime_high" or "sp_streaming_runtime_medium")
    else
        reason = level >= 3 and "streaming_runtime_critical" or "streaming_runtime_high"
    end
    return reason, retrySeconds / 3600
end


local function bsr_spWarmupActive()
    if not bsr_isSinglePlayerGovernorEnabled() then return false, 0 end
    local c = NPCStreamingRuntimeBridge.Config
    local seconds = tonumber(c.singlePlayerWarmupQuarantineSeconds) or 0
    if seconds <= 0 then return false, 0 end
    local s = NPCStreamingRuntimeBridge.State
    local started = tonumber(s.firstSeenAtMs) or 0
    if started <= 0 then return true, seconds end
    local elapsed = math.max(0, (bsr_nowMs() - started) / 1000)
    local left = seconds - elapsed
    return left > 0, math.max(0, left)
end

local function bsr_quarantineTaskAllowed(taskName)
    taskName = tostring(taskName or "world")
    if taskName == "mercenary_leash" or taskName == "physical_cleanup" or taskName == "proxy_lod" then return false end
    if taskName == "combat" or taskName == "player_order" or taskName == "hired_mercenary" then return false end
    return true
end

function NPCStreamingRuntimeBridge.IsSPWarmupQuarantineActive()
    local active = bsr_spWarmupActive()
    return active == true
end


local function bsr_spBootstrapGateActive()
    if not bsr_isSinglePlayerGovernorEnabled() then return false, 0 end
    local c = NPCStreamingRuntimeBridge.Config
    if c.singlePlayerBootstrapGate == false then return false, 0 end
    local seconds = tonumber(c.singlePlayerBootstrapHardGateSeconds) or 0
    if seconds <= 0 then return false, 0 end
    local s = NPCStreamingRuntimeBridge.State
    local started = tonumber(s.firstSeenAtMs) or 0
    if started <= 0 then return true, seconds end
    local elapsed = math.max(0, (bsr_nowMs() - started) / 1000)
    local left = seconds - elapsed
    return left > 0, math.max(0, left)
end

local function bsr_spPostGateSmoothingActive()
    if not bsr_isSinglePlayerGovernorEnabled() then return false, 0 end
    local c = NPCStreamingRuntimeBridge.Config
    if c.singlePlayerBootstrapGate == false then return false, 0 end
    local hard = tonumber(c.singlePlayerBootstrapHardGateSeconds) or 0
    local smooth = tonumber(c.singlePlayerPostGateSmoothingSeconds) or 0
    if smooth <= 0 then return false, 0 end
    local s = NPCStreamingRuntimeBridge.State
    local started = tonumber(s.firstSeenAtMs) or 0
    if started <= 0 then return false, smooth end
    local elapsed = math.max(0, (bsr_nowMs() - started) / 1000)
    local left = hard + smooth - elapsed
    return elapsed >= hard and left > 0, math.max(0, left)
end

local function bsr_postGateCategory(taskName)
    local lower = string.lower(tostring(taskName or ""))
    if string.find(lower, "task_budget", 1, true) then return nil end
    if string.find(lower, "mercenary", 1, true) or string.find(lower, "player_order", 1, true) or string.find(lower, "combat", 1, true) then return nil end
    if string.find(lower, "base_economy", 1, true) or string.find(lower, "base_owned_repair", 1, true) or string.find(lower, "basecamp", 1, true) or string.find(lower, "base_marker", 1, true) then return "base" end
    if string.find(lower, "road_battle", 1, true) or string.find(lower, "battle_remains", 1, true) then return "battle" end
    if string.find(lower, "virtual", 1, true) or string.find(lower, "strategic", 1, true) or string.find(lower, "leader", 1, true) then return "virtual" end
    if string.find(lower, "marker", 1, true) or string.find(lower, "base_zone", 1, true) or string.find(lower, "debug", 1, true) or string.find(lower, "world_snapshot", 1, true) then return "marker" end
    if string.find(lower, "bootstrap", 1, true) then return "bootstrap" end
    return nil
end

local function bsr_postGateCategoryLimit(category)
    local c = NPCStreamingRuntimeBridge.Config
    if category == "base" then return tonumber(c.singlePlayerPostGateBasePerWindow) or 1 end
    if category == "battle" then return tonumber(c.singlePlayerPostGateBattlePerWindow) or 1 end
    if category == "virtual" then return tonumber(c.singlePlayerPostGateVirtualPerWindow) or 2 end
    if category == "marker" then return tonumber(c.singlePlayerPostGateMarkerPerWindow) or 6 end
    if category == "bootstrap" then return tonumber(c.singlePlayerPostGateBootstrapPerWindow) or 1 end
    return 0
end

local function bsr_consumePostGateCategory(category)
    if not category then return true end
    local active = bsr_spPostGateSmoothingActive()
    if active ~= true then return true end
    local s = NPCStreamingRuntimeBridge.State
    local windowTicks = math.max(15, math.floor(tonumber(NPCStreamingRuntimeBridge.Config.singlePlayerPostGateWindowTicks) or 120))
    local tick = tonumber(s.tick) or 0
    local windowId = math.floor(tick / windowTicks)
    if tonumber(s.postGateWindowTick) ~= windowId then
        s.postGateWindowTick = windowId
        s.postGateCategoryUsed = {}
    end
    s.postGateCategoryUsed = s.postGateCategoryUsed or {}
    local limit = math.max(0, math.floor(bsr_postGateCategoryLimit(category) or 0))
    if limit <= 0 then return false end
    local used = tonumber(s.postGateCategoryUsed[category]) or 0
    if used >= limit then return false end
    s.postGateCategoryUsed[category] = used + 1
    return true
end

local function bsr_postGateTaskPriorityLimit(priority)
    local c = NPCStreamingRuntimeBridge.Config
    priority = tostring(priority or "normal")
    if priority == "high" then return tonumber(c.singlePlayerPostGateHighPerTick) or 1 end
    if priority == "low" then return tonumber(c.singlePlayerPostGateLowPerTick) or 0 end
    return tonumber(c.singlePlayerPostGateNormalPerTick) or 1
end

function NPCStreamingRuntimeBridge.IsPostGateSmoothingActive()
    local active = bsr_spPostGateSmoothingActive()
    return active == true
end

function NPCStreamingRuntimeBridge.AllowRuntimeTaskNow(label, priority)
    local category = bsr_postGateCategory(label)
    if not category then return true end
    local active, left = bsr_spPostGateSmoothingActive()
    if active ~= true then return true end
    local s = NPCStreamingRuntimeBridge.State
    local level = NPCStreamingRuntimeBridge.GetLevel()
    local pressure = (tonumber(s.pendingTasks) or 0) >= (tonumber(NPCStreamingRuntimeBridge.Config.singlePlayerPostGateTaskSoftCap) or 36)
        or (tonumber(s.pendingMarkers) or 0) >= (tonumber(NPCStreamingRuntimeBridge.Config.singlePlayerPostGateMarkerSoftCap) or 20)
        or level >= 1 or s.singlePlayerStreet == true or s.travelUnloading == true
    if not pressure then return true end

    local tick = tonumber(s.tick) or 0
    if tonumber(s.postGateTaskTick) ~= tick then
        s.postGateTaskTick = tick
        s.postGateTaskUsed = {high=0, normal=0, low=0}
    end
    s.postGateTaskUsed = s.postGateTaskUsed or {high=0, normal=0, low=0}
    priority = tostring(priority or "normal")
    if priority ~= "high" and priority ~= "low" then priority = "normal" end
    local limit = math.max(0, math.floor(bsr_postGateTaskPriorityLimit(priority) or 0))
    local used = tonumber(s.postGateTaskUsed[priority]) or 0
    if used >= limit then return false, "spPostGateTaskSmooth", math.max(30, math.min(360, math.floor((tonumber(left) or 0) * 60))) end
    s.postGateTaskUsed[priority] = used + 1
    return true
end

function NPCStreamingRuntimeBridge.ShouldGateWorldBootstrapTask(taskName)
    if not NPCStreamingRuntimeBridge.Config.enabled then return false end
    if not bsr_isSinglePlayerGovernorEnabled() then return false end
    local c = NPCStreamingRuntimeBridge.Config
    if c.singlePlayerBootstrapGate == false then return false end
    taskName = tostring(taskName or "bootstrap")

    -- Never gate player-facing critical systems from this generic helper.
    if taskName == "mercenary_leash" or taskName == "player_order" or taskName == "hired_mercenary" or taskName == "combat" then
        return false
    end

    local s = NPCStreamingRuntimeBridge.State
    local reasons = {}
    local duration = 0
    local gate, left = bsr_spBootstrapGateActive()
    if gate then
        duration = math.max(duration, left)
        bsr_addReason(reasons, "spBootstrapGate", math.floor(left))
    end

    local level = NPCStreamingRuntimeBridge.GetLevel()
    if level >= (tonumber(c.singlePlayerQuarantineMinLevel) or 2) and (NPCStreamingRuntimeBridge.IsTravelUnloading() or s.singlePlayerStreet) then
        local seconds = level >= 3 and (tonumber(c.singlePlayerCriticalQuarantineSeconds) or 14) or (tonumber(c.singlePlayerHighQuarantineSeconds) or 8)
        duration = math.max(duration, seconds)
        bsr_addReason(reasons, level >= 3 and "spCritical" or "spHigh", s.name or level)
    end

    if (tonumber(s.pendingTasks) or 0) >= (tonumber(c.pendingTaskHigh) or 80) then
        duration = math.max(duration, tonumber(c.singlePlayerHighQuarantineSeconds) or 8)
        bsr_addReason(reasons, "taskHigh", tonumber(s.pendingTasks) or 0)
    end
    if (tonumber(s.pendingMarkers) or 0) >= (tonumber(c.pendingMarkerHigh) or 100) then
        duration = math.max(duration, tonumber(c.singlePlayerHighQuarantineSeconds) or 8)
        bsr_addReason(reasons, "markerHigh", tonumber(s.pendingMarkers) or 0)
    end

    if duration <= 0 then
        local postActive, postLeft = bsr_spPostGateSmoothingActive()
        local category = bsr_postGateCategory(taskName)
        if postActive and category then
            local pressure = (tonumber(s.pendingTasks) or 0) >= (tonumber(c.singlePlayerPostGateTaskSoftCap) or 36)
                or (tonumber(s.pendingMarkers) or 0) >= (tonumber(c.singlePlayerPostGateMarkerSoftCap) or 20)
                or level >= 1 or s.singlePlayerStreet == true or s.travelUnloading == true
            if pressure and not bsr_consumePostGateCategory(category) then
                local retryTicks = math.max(30, math.min(360, math.floor(math.max(1, math.min(postLeft, tonumber(c.singlePlayerHighQuarantineSeconds) or 8)) * 60)))
                return true, retryTicks, "spPostGateSmooth:" .. tostring(category)
            end
        end
        return false
    end
    local retryTicks = math.max(30, math.min(1200, math.floor(duration * 60)))
    return true, retryTicks, table.concat(reasons, ",")
end

function NPCStreamingRuntimeBridge.ShouldDropRuntimeTask(label, priority)
    if NPCStreamingRuntimeBridge.Config.singlePlayerGateMarkerTasks == false then return false end
    label = tostring(label or "")
    priority = tostring(priority or "normal")
    local lower = string.lower(label)
    local markerLike = string.find(lower, "marker", 1, true) or string.find(lower, "base_zone", 1, true) or string.find(lower, "debug", 1, true) or string.find(lower, "world_snapshot", 1, true) or string.find(lower, "strategic", 1, true)
    local baseCampLike = string.find(lower, "basecamp", 1, true) or string.find(lower, "base_marker", 1, true) or string.find(lower, "base_zone", 1, true)
    local virtualLike = string.find(lower, "virtual_map", 1, true) or string.find(lower, "road_battle", 1, true) or string.find(lower, "bootstrap", 1, true)
    if not (markerLike or baseCampLike or virtualLike) then return false end
    local gate, retry, reason = NPCStreamingRuntimeBridge.ShouldGateWorldBootstrapTask("task:" .. label)
    if gate then return true, reason or "sp_bootstrap_task_gate", retry end
    return false
end

function NPCStreamingRuntimeBridge.ShouldQuarantineWorldTask(taskName)
    if not NPCStreamingRuntimeBridge.Config.enabled then return false end
    if not bsr_isSinglePlayerGovernorEnabled() then return false end
    local c = NPCStreamingRuntimeBridge.Config
    if c.singlePlayerHardQuarantine == false then return false end
    taskName = tostring(taskName or "world")
    if not bsr_quarantineTaskAllowed(taskName) then return false end

    local s = NPCStreamingRuntimeBridge.State
    local nowHours = bsr_nowHours()
    local level = NPCStreamingRuntimeBridge.GetLevel()
    local warmup, warmupLeft = bsr_spWarmupActive()
    local reasons = {}
    local duration = 0

    if warmup then
        duration = math.max(duration, math.min(warmupLeft, tonumber(c.singlePlayerWarmupQuarantineSeconds) or 0))
        bsr_addReason(reasons, "spWarmup", math.floor(warmupLeft))
    end

    if level >= (tonumber(c.singlePlayerQuarantineMinLevel) or 2) and (NPCStreamingRuntimeBridge.IsTravelUnloading() or s.singlePlayerStreet) then
        local seconds = level >= 3 and (tonumber(c.singlePlayerCriticalQuarantineSeconds) or 14) or (tonumber(c.singlePlayerHighQuarantineSeconds) or 8)
        duration = math.max(duration, seconds)
        bsr_addReason(reasons, level >= 3 and "spCritical" or "spHigh", s.name or level)
    end

    if c.singlePlayerQuarantineTaskHigh ~= false and (tonumber(s.pendingTasks) or 0) >= (tonumber(c.pendingTaskHigh) or 80) then
        duration = math.max(duration, tonumber(c.singlePlayerHighQuarantineSeconds) or 8)
        bsr_addReason(reasons, "taskHigh", tonumber(s.pendingTasks) or 0)
    end

    if taskName == "world_update" and c.singlePlayerQuarantineWorldUpdate == false then duration = 0 end
    if taskName == "marker_sync" and c.singlePlayerQuarantineMarkerSync == false then duration = 0 end
    if taskName == "bootstrap_sync" and c.singlePlayerQuarantineBootstrapSync == false then duration = 0 end

    if duration <= 0 and (tonumber(s.worldQuarantineUntilHours) or 0) > nowHours then
        local remain = math.floor(((tonumber(s.worldQuarantineUntilHours) or nowHours) - nowHours) * 3600)
        if remain > 0 then
            return true, math.max(30, math.min(900, math.floor(remain * 60))), s.worldQuarantineReason or "sp_world_quarantine_cooldown"
        end
    end

    if duration <= 0 then return false end

    s.worldQuarantineUntilHours = math.max(tonumber(s.worldQuarantineUntilHours) or 0, nowHours + (duration / 3600))
    s.worldQuarantineReason = table.concat(reasons, ",")
    s.worldQuarantineTask = taskName
    s.worldQuarantineCount = (tonumber(s.worldQuarantineCount) or 0) + 1

    local retryTicks = math.max(30, math.min(900, math.floor(duration * 60)))
    return true, retryTicks, s.worldQuarantineReason
end

function NPCStreamingRuntimeBridge.GetQuarantineDiagnostics()
    local s = NPCStreamingRuntimeBridge.State
    local nowHours = bsr_nowHours()
    local remaining = 0
    if (tonumber(s.worldQuarantineUntilHours) or 0) > nowHours then
        remaining = math.floor(((tonumber(s.worldQuarantineUntilHours) or nowHours) - nowHours) * 3600)
    end
    local warmup, warmupLeft = bsr_spWarmupActive()
    local postActive, postLeft = bsr_spPostGateSmoothingActive()
    return {
        active = remaining > 0 or warmup == true,
        remainingSeconds = remaining,
        warmup = warmup == true,
        warmupLeftSeconds = math.floor(tonumber(warmupLeft) or 0),
        postGateSmoothing = postActive == true,
        postGateSmoothingLeftSeconds = math.floor(tonumber(postLeft) or 0),
        postGateTaskBudget = s.postGateTaskUsed,
        reason = s.worldQuarantineReason,
        task = s.worldQuarantineTask,
        count = tonumber(s.worldQuarantineCount) or 0
    }
end

function NPCStreamingRuntimeBridge.GetDiagnostics()
    local s = NPCStreamingRuntimeBridge.State
    return {
        pressure = s.name,
        level = s.level,
        score = s.score,
        fastTravel = s.fastTravel,
        singlePlayerStreet = s.singlePlayerStreet,
        urban = s.urban,
        npc = s.maxNPCNearPlayer,
        spawnQueue = s.pendingSpawn,
        markerQueue = s.pendingMarkers,
        taskQueue = s.pendingTasks,
        travelUnloading = s.travelUnloading,
        teleportBurst = s.teleportBurst,
        maxSpeed = s.maxSpeed,
        maxChunkDelta = s.maxChunkDelta,
        quarantine = NPCStreamingRuntimeBridge.GetQuarantineDiagnostics and NPCStreamingRuntimeBridge.GetQuarantineDiagnostics() or nil,
        reasons = table.concat(s.reasons or {}, ",")
    }
end

NPCStreamingRuntimeBridge.ApplySettings()

if Events and Events.OnTick and not NPCStreamingRuntimeBridge._registered then
    NPCStreamingRuntimeBridge._registered = true
    Events.OnTick.Add(NPCStreamingRuntimeBridge.OnTick)
end
