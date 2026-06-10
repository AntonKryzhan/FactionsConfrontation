-- NPCHitchProfilerBridge.lua
-- Stage455: ultra-light frame hitch detector for Factions Confrontation.
-- This is diagnostics-only: it does not change AI decisions, save data,
-- networking payloads, Java classes, hired mercenary orders or gameplay systems.

require "NPCCore/NPCLegacySettingsBridge"

NPCHitchProfilerBridge = NPCHitchProfilerBridge or {}
NPCHitchProfilerBridge.VERSION = "2026-06-10-stage458-hitch-profiler-safe-vehicle-scan-1"
NPCHitchProfilerBridge.Config = NPCHitchProfilerBridge.Config or {
    enabled = true,
    thresholdMs = 750,
    severeMs = 1500,
    criticalMs = 3000,
    catastrophicMs = 8000,
    minLogIntervalMs = 1200,
    vehicleRadius = 120,
    vehicleLimit = 80,
    debugConsole = false
}
NPCHitchProfilerBridge.State = NPCHitchProfilerBridge.State or {
    tick = 0,
    lastMs = 0,
    lastLogMs = 0,
    hitchCount = 0,
    severeCount = 0,
    criticalCount = 0,
    catastrophicCount = 0,
    maxDtMs = 0
}

local function nhp_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        local ok, ret = pcall(function() return NPCLegacySettingsBridge.GetBool(name, defaultValue == true) end)
        if ok and ret ~= nil then return ret == true end
    end
    return defaultValue == true
end

local function nhp_number(name, defaultValue, minValue, maxValue)
    local value = nil
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        local ok, ret = pcall(function() return NPCLegacySettingsBridge.GetNumber(name, defaultValue, minValue, maxValue) end)
        if ok then value = tonumber(ret) end
    end
    value = tonumber(value) or tonumber(defaultValue) or 0
    if minValue ~= nil and value < minValue then value = minValue end
    if maxValue ~= nil and value > maxValue then value = maxValue end
    return value
end

local function nhp_nowMs()
    if getTimestampMs then
        local ok, v = pcall(function() return getTimestampMs() end)
        if ok and v then return tonumber(v) or 0 end
    end
    if getGameTime then
        local ok, h = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok and h then return math.floor((tonumber(h) or 0) * 3600000) end
    end
    return os.time() * 1000
end

local function nhp_count(t, limit)
    if type(t) ~= "table" then return 0 end
    local n = 0
    for _, _ in pairs(t) do
        n = n + 1
        if limit and n >= limit then return n end
    end
    return n
end

local function nhp_round(v, digits)
    local n = tonumber(v)
    if not n then return v end
    local m = 10 ^ (digits or 2)
    return math.floor(n * m + 0.5) / m
end

function NPCHitchProfilerBridge.ApplySettings()
    local c = NPCHitchProfilerBridge.Config
    c.enabled = nhp_bool("HitchProfiler_Enabled", c.enabled ~= false)
    c.thresholdMs = nhp_number("HitchProfiler_ThresholdMs", c.thresholdMs or 750, 100, 60000)
    c.severeMs = nhp_number("HitchProfiler_SevereMs", c.severeMs or 1500, c.thresholdMs or 750, 120000)
    c.criticalMs = nhp_number("HitchProfiler_CriticalMs", c.criticalMs or 3000, c.severeMs or 1500, 180000)
    c.catastrophicMs = nhp_number("HitchProfiler_CatastrophicMs", c.catastrophicMs or 8000, c.criticalMs or 3000, 300000)
    c.minLogIntervalMs = nhp_number("HitchProfiler_MinLogIntervalMs", c.minLogIntervalMs or 1200, 0, 60000)
    c.vehicleRadius = nhp_number("HitchProfiler_VehicleRadius", c.vehicleRadius or 120, 20, 400)
    c.vehicleLimit = nhp_number("HitchProfiler_VehicleLimit", c.vehicleLimit or 80, 8, 400)
    c.debugConsole = nhp_bool("HitchProfiler_DebugConsole", c.debugConsole == true)
end

local function nhp_playerSnapshot()
    local p = nil
    if getSpecificPlayer then p = getSpecificPlayer(0) end
    if not p then return {} end
    local out = {}
    pcall(function()
        out.playerX = nhp_round(p:getX(), 1)
        out.playerY = nhp_round(p:getY(), 1)
        out.playerZ = p:getZ()
        out.chunkX = math.floor((tonumber(p:getX()) or 0) / 10)
        out.chunkY = math.floor((tonumber(p:getY()) or 0) / 10)
        out.inVehicle = (p.getVehicle and p:getVehicle() ~= nil) or false
    end)
    if NPCStreamingRuntimeBridge and NPCStreamingRuntimeBridge.State then
        out.maxSpeed = nhp_round(NPCStreamingRuntimeBridge.State.maxSpeed, 2)
        out.maxChunkDelta = NPCStreamingRuntimeBridge.State.maxChunkDelta
    end
    return out
end

local function nhp_vehicleCountNearPlayer(radius, limit)
    local p = getSpecificPlayer and getSpecificPlayer(0) or nil
    if not (p and p.getX and getCell) then return nil, nil, nil, "no_player_or_cell" end
    local cell = nil
    local okCell = pcall(function() cell = getCell() end)
    if not okCell or not cell or not cell.getVehicles then return nil, nil, nil, "no_vehicle_list" end
    local vehicles = nil
    local okVehicles = pcall(function() vehicles = cell:getVehicles() end)
    if not okVehicles or not vehicles then return nil, nil, nil, "vehicle_list_unavailable" end

    local px, py = 0, 0
    pcall(function() px = tonumber(p:getX()) or 0; py = tonumber(p:getY()) or 0 end)
    local r = tonumber(radius) or 120
    local r2 = r * r
    local count = 0
    local total = 0
    local maxIter = math.max(0, math.floor(tonumber(limit) or 80))
    local size = 0
    local okSize = pcall(function() size = tonumber(vehicles:size()) or 0 end)
    if not okSize then return nil, nil, nil, "vehicle_size_failed" end
    size = math.max(0, math.floor(tonumber(size) or 0))
    if size <= 0 or maxIter <= 0 then return 0, 0, size, nil end

    local lastIndex = math.min(size - 1, maxIter - 1)
    for i = 0, lastIndex do
        local okGet, v = pcall(function() return vehicles:get(i) end)
        if okGet and v and v.getX then
            total = total + 1
            local okPos, vx, vy = pcall(function() return tonumber(v:getX()) or 0, tonumber(v:getY()) or 0 end)
            if okPos then
                local dx = vx - px
                local dy = vy - py
                if dx * dx + dy * dy <= r2 then count = count + 1 end
            end
        elseif not okGet then
            return count, total, size, "vehicle_get_failed"
        end
    end
    return count, total, size, nil
end

local function nhp_pathDiagnostics(out)
    if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.GetPathQueueDiagnostics then
        local ok, d = pcall(function() return NPCWorkSchedulerBridge.GetPathQueueDiagnostics(false) end)
        if ok and type(d) == "table" then
            out.pathPending = d.pending
            if type(d.stats) == "table" then
                out.pathQueued = d.stats.queued
                out.pathProcessed = d.stats.processed
                out.pathExpired = d.stats.expired
                out.pathDropped = d.stats.dropped
            end
        end
    end
end

local function nhp_calendarDiagnostics(out)
    if NPCWorldDirectorBridge and NPCWorldDirectorBridge.GetCalendarDiagnostics then
        local ok, d = pcall(function() return NPCWorldDirectorBridge.GetCalendarDiagnostics(false) end)
        if ok and type(d) == "table" then
            out.worldCalendarTasks = d.tasks
            out.worldCalendarRan = d.ran
            out.worldCalendarDeferred = d.deferred
            out.worldCalendarQuarantined = d.quarantined
            out.worldCalendarRanThisTick = d.ranThisTick
        end
    end
end

local function nhp_streamingDiagnostics(out)
    if NPCStreamingRuntimeBridge and NPCStreamingRuntimeBridge.GetDiagnostics then
        local ok, d = pcall(function() return NPCStreamingRuntimeBridge.GetDiagnostics() end)
        if ok and type(d) == "table" then
            out.streamingPressure = d.pressure
            out.streamingLevel = d.level
            out.streamingScore = nhp_round(d.score, 1)
            out.streamingReasons = d.reasons
            out.travelUnloading = d.travelUnloading
            out.spStreet = d.singlePlayerStreet
            out.spawnQ = d.spawnQueue
            out.markerQ = d.markerQueue
            out.taskQ = d.taskQueue
            if type(d.quarantine) == "table" then
                out.worldQuarantine = d.quarantine.active
                out.worldQuarantineLeft = d.quarantine.remainingSeconds
                out.worldQuarantineWarmup = d.quarantine.warmup
                out.worldQuarantineReason = d.quarantine.reason
                out.postGateSmoothing = d.quarantine.postGateSmoothing
                out.postGateSmoothingLeft = d.quarantine.postGateSmoothingLeftSeconds
                out.postGateTaskBudget = d.quarantine.postGateTaskBudget
            end
        end
    end
end

local function nhp_worldSummary(out)
    local gmd = nil
    if GetNPCModData then pcall(function() gmd = GetNPCModData() end) end
    if NPCDiagnosticsBridge and NPCDiagnosticsBridge.SummarizeSystems and type(gmd) == "table" then
        local ok, summary = pcall(function() return NPCDiagnosticsBridge.SummarizeSystems(gmd) end)
        if ok and type(summary) == "table" then
            out.queue = summary.queue
            out.virtualGroups = summary.virtualGroups
            out.physicalGroups = summary.physicalGroups
            out.spawningGroups = summary.spawningGroups
            out.physicalIds = summary.physicalIds
            out.debugMarkers = summary.debugMarkers
            out.bases = summary.bases
            out.checkpointGroups = summary.checkpointGroups
            if gmd and gmd.BaseCampDirector then
                out.baseCampInitialized = gmd.BaseCampDirector.initialized == true
                out.baseCampInitGate = gmd.BaseCampDirector.initDeferredByGate == true
                out.baseCampUpdateGate = gmd.BaseCampDirector.updateDeferredByGate == true
            end
            out.convoyGroups = summary.convoyGroups
            out.contractGroups = summary.contractGroups
            out.leaderGroups = summary.leaderGroups
        end
    elseif type(gmd) == "table" then
        out.queue = nhp_count(gmd.Queue)
        out.virtualGroups = nhp_count(gmd.VirtualGroups)
        out.debugMarkers = nhp_count(gmd.DebugMapMarkers)
    end
    if type(gmd) == "table" and type(gmd.VirtualGroups) == "table" then
        local roadBattles = 0
        for _, group in pairs(gmd.VirtualGroups) do
            if type(group) == "table" and (group.inBattle == true or group.state == "road_battle" or group.battleId or group.enemyGroupId) then
                roadBattles = roadBattles + 1
            end
        end
        out.roadBattles = roadBattles
    end
end

local function nhp_severity(dt)
    local c = NPCHitchProfilerBridge.Config
    if dt >= (tonumber(c.catastrophicMs) or 8000) then return "catastrophic" end
    if dt >= (tonumber(c.criticalMs) or 3000) then return "critical" end
    if dt >= (tonumber(c.severeMs) or 1500) then return "severe" end
    return "minor"
end

function NPCHitchProfilerBridge.LogHitch(dtMs)
    local s = NPCHitchProfilerBridge.State
    local c = NPCHitchProfilerBridge.Config
    local now = nhp_nowMs()
    if (now - (tonumber(s.lastLogMs) or 0)) < (tonumber(c.minLogIntervalMs) or 0) and dtMs < (tonumber(c.criticalMs) or 3000) then
        return
    end
    s.lastLogMs = now
    s.hitchCount = (tonumber(s.hitchCount) or 0) + 1
    s.maxDtMs = math.max(tonumber(s.maxDtMs) or 0, tonumber(dtMs) or 0)
    local severity = nhp_severity(dtMs)
    if severity == "severe" then s.severeCount = (tonumber(s.severeCount) or 0) + 1 end
    if severity == "critical" then s.criticalCount = (tonumber(s.criticalCount) or 0) + 1 end
    if severity == "catastrophic" then s.catastrophicCount = (tonumber(s.catastrophicCount) or 0) + 1 end

    local out = {
        dtMs = math.floor(tonumber(dtMs) or 0),
        severity = severity,
        hitchCount = s.hitchCount,
        severeCount = s.severeCount,
        criticalCount = s.criticalCount,
        catastrophicCount = s.catastrophicCount,
        maxDtMs = math.floor(tonumber(s.maxDtMs) or 0)
    }
    local ps = nhp_playerSnapshot()
    for k, v in pairs(ps) do out[k] = v end
    nhp_streamingDiagnostics(out)
    nhp_pathDiagnostics(out)
    nhp_calendarDiagnostics(out)
    nhp_worldSummary(out)
    local nearVehicles, iterVehicles, totalVehicles, vehicleScanError = nhp_vehicleCountNearPlayer(c.vehicleRadius, c.vehicleLimit)
    out.vehiclesNear = nearVehicles
    out.vehiclesIter = iterVehicles
    out.vehiclesTotal = totalVehicles
    if vehicleScanError then
        out.vehiclesUnsafe = true
        out.vehicleScanError = vehicleScanError
    end

    if NPCPerformanceTelemetryBridge and NPCPerformanceTelemetryBridge.Record then
        pcall(function() NPCPerformanceTelemetryBridge.Record("hitch_" .. severity, 1) end)
    end
    if NPCDiagnosticsBridge and NPCDiagnosticsBridge.Log then
        NPCDiagnosticsBridge.Log("HITCH", "frame_hitch", out, "hitch:" .. tostring(s.hitchCount), true)
    end
    if c.debugConsole then
        print("[NPCHitch] dtMs=" .. tostring(out.dtMs) .. " severity=" .. tostring(severity) .. " pressure=" .. tostring(out.streamingPressure) .. " reasons=" .. tostring(out.streamingReasons))
    end
end

function NPCHitchProfilerBridge.OnTick()
    local c = NPCHitchProfilerBridge.Config
    if c.enabled == false then return end
    local s = NPCHitchProfilerBridge.State
    s.tick = (tonumber(s.tick) or 0) + 1
    if s.tick % 600 == 1 then NPCHitchProfilerBridge.ApplySettings() end
    local now = nhp_nowMs()
    local last = tonumber(s.lastMs) or 0
    s.lastMs = now
    if last <= 0 then return end
    local dt = now - last
    if dt >= (tonumber(c.thresholdMs) or 750) then
        NPCHitchProfilerBridge.LogHitch(dt)
    end
end

NPCHitchProfilerBridge.ApplySettings()

if Events and Events.OnTick and not NPCHitchProfilerBridge._registered then
    NPCHitchProfilerBridge._registered = true
    Events.OnTick.Add(NPCHitchProfilerBridge.OnTick)
end
