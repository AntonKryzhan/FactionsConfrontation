-- NPCPerformanceTelemetryBridge.lua
-- Stage449: lightweight runtime pressure telemetry.
-- Runtime-only diagnostics layer. It does not change NPC decisions, save data,
-- network payload formats or gameplay state. The counters are intentionally
-- sampled rarely and printed only when debug is enabled.

NPCPerformanceTelemetryBridge = NPCPerformanceTelemetryBridge or {}

NPCPerformanceTelemetryBridge.VERSION = "2026-06-10-stage455-hitch-quarantine-telemetry-1"
NPCPerformanceTelemetryBridge.Config = NPCPerformanceTelemetryBridge.Config or {
    enabled = true,
    debug = false,
    sampleTicks = 300,
    logTicks = 1800,
    retainSamples = 12
}
NPCPerformanceTelemetryBridge.State = NPCPerformanceTelemetryBridge.State or {
    tick = 0,
    samples = {},
    counters = {},
    lastLogTick = 0
}

local function npt_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        local ok, ret = pcall(function() return NPCLegacySettingsBridge.GetBool(name, defaultValue == true) end)
        if ok and ret ~= nil then return ret == true end
    end
    return defaultValue == true
end

local function npt_number(name, defaultValue, minValue, maxValue)
    local value = nil
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        local ok, ret = pcall(function() return NPCLegacySettingsBridge.GetNumber(name, defaultValue, minValue, maxValue) end)
        if ok then value = tonumber(ret) end
    end
    if value == nil then value = tonumber(defaultValue) or 0 end
    if minValue ~= nil then value = math.max(tonumber(minValue) or value, value) end
    if maxValue ~= nil then value = math.min(tonumber(maxValue) or value, value) end
    return value
end

function NPCPerformanceTelemetryBridge.ApplySettings()
    local c = NPCPerformanceTelemetryBridge.Config
    c.enabled = npt_bool("PerfTelemetry_Enabled", c.enabled ~= false)
    c.debug = npt_bool("PerfTelemetry_Debug", c.debug == true)
    c.sampleTicks = npt_number("PerfTelemetry_SampleTicks", c.sampleTicks or 300, 60, 7200)
    c.logTicks = npt_number("PerfTelemetry_LogTicks", c.logTicks or 1800, 300, 21600)
    c.retainSamples = npt_number("PerfTelemetry_RetainSamples", c.retainSamples or 12, 1, 96)
end

function NPCPerformanceTelemetryBridge.Record(name, amount)
    if not (NPCPerformanceTelemetryBridge.Config and NPCPerformanceTelemetryBridge.Config.enabled) then return end
    name = tostring(name or "unknown")
    amount = tonumber(amount) or 1
    local counters = NPCPerformanceTelemetryBridge.State.counters
    counters[name] = (tonumber(counters[name]) or 0) + amount
end

local function npt_copyTable(src)
    local out = {}
    if type(src) ~= "table" then return out end
    for k, v in pairs(src) do
        if type(v) ~= "table" then out[k] = v end
    end
    return out
end

local function npt_getPathDiagnostics()
    if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.GetPathQueueDiagnostics then
        local ok, ret = pcall(function() return NPCWorkSchedulerBridge.GetPathQueueDiagnostics(false) end)
        if ok and type(ret) == "table" then return ret end
    end
    return nil
end

local function npt_getStreamingDiagnostics()
    if NPCStreamingRuntimeBridge and NPCStreamingRuntimeBridge.GetDiagnostics then
        local ok, ret = pcall(function() return NPCStreamingRuntimeBridge.GetDiagnostics() end)
        if ok and type(ret) == "table" then return ret end
    end
    return nil
end


local function npt_getSpatialDiagnostics()
    if NPCSpatialIndexBridge and NPCSpatialIndexBridge.GetQueryDiagnostics then
        local ok, ret = pcall(function() return NPCSpatialIndexBridge.GetQueryDiagnostics(false) end)
        if ok and type(ret) == "table" then return ret end
    end
    return nil
end

local function npt_getWorldCalendarDiagnostics()
    if NPCWorldDirectorBridge and NPCWorldDirectorBridge.GetCalendarDiagnostics then
        local ok, ret = pcall(function() return NPCWorldDirectorBridge.GetCalendarDiagnostics(false) end)
        if ok and type(ret) == "table" then return ret end
    end
    return nil
end

local function npt_getNavDiagnostics()
    if NPCNavigationPerformanceBridge and NPCNavigationPerformanceBridge.GetDiagnostics then
        local ok, ret = pcall(function() return NPCNavigationPerformanceBridge.GetDiagnostics(false) end)
        if ok and type(ret) == "table" then return ret end
    end
    return nil
end

function NPCPerformanceTelemetryBridge.Sample()
    local s = NPCPerformanceTelemetryBridge.State
    local sample = {
        tick = tonumber(s.tick) or 0,
        streaming = npt_getStreamingDiagnostics(),
        path = npt_getPathDiagnostics(),
        nav = npt_getNavDiagnostics(),
        spatial = npt_getSpatialDiagnostics(),
        worldCalendar = npt_getWorldCalendarDiagnostics(),
        counters = npt_copyTable(s.counters)
    }

    table.insert(s.samples, sample)
    local retain = math.max(1, math.floor(tonumber(NPCPerformanceTelemetryBridge.Config.retainSamples) or 12))
    while #s.samples > retain do table.remove(s.samples, 1) end
    s.counters = {}
    return sample
end

function NPCPerformanceTelemetryBridge.GetLastSample()
    local samples = NPCPerformanceTelemetryBridge.State.samples or {}
    return samples[#samples]
end

function NPCPerformanceTelemetryBridge.GetDiagnostics()
    return {
        version = NPCPerformanceTelemetryBridge.VERSION,
        config = NPCPerformanceTelemetryBridge.Config,
        last = NPCPerformanceTelemetryBridge.GetLastSample(),
        samples = NPCPerformanceTelemetryBridge.State.samples
    }
end

local function npt_logSample(sample)
    if not (NPCPerformanceTelemetryBridge.Config and NPCPerformanceTelemetryBridge.Config.debug) then return end
    if not sample then return end
    local streaming = sample.streaming or {}
    local path = sample.path or {}
    local pathStats = path.stats or {}
    local nav = sample.nav or {}
    local navStats = nav.stats or {}
    print("[NPCPerformanceTelemetry] pressure=" .. tostring(streaming.pressure or "LOW")
        .. " level=" .. tostring(streaming.level or 0)
        .. " q=" .. tostring(path.pending or 0)
        .. " qd=" .. tostring(pathStats.queued or 0)
        .. " qp=" .. tostring(pathStats.processed or 0)
        .. " qx=" .. tostring(pathStats.expired or 0)
        .. " pd=" .. tostring(navStats.portalDenied or 0)
        .. " pw=" .. tostring(navStats.portalWait or 0)
        .. " sq=" .. tostring(sample.spatial and sample.spatial.queries or 0)
        .. " cal=" .. tostring(sample.worldCalendar and sample.worldCalendar.ran or 0)
        .. " reasons=" .. tostring(streaming.reasons or ""))
end

function NPCPerformanceTelemetryBridge.OnTick()
    local c = NPCPerformanceTelemetryBridge.Config
    if c.enabled == false then return end
    local s = NPCPerformanceTelemetryBridge.State
    s.tick = (tonumber(s.tick) or 0) + 1
    if s.tick % 600 == 1 then NPCPerformanceTelemetryBridge.ApplySettings() end

    local sampleTicks = math.max(1, math.floor(tonumber(c.sampleTicks) or 300))
    if s.tick % sampleTicks == 0 then
        local sample = NPCPerformanceTelemetryBridge.Sample()
        local logTicks = math.max(sampleTicks, math.floor(tonumber(c.logTicks) or 1800))
        if c.debug == true and (s.tick - (tonumber(s.lastLogTick) or 0)) >= logTicks then
            s.lastLogTick = s.tick
            npt_logSample(sample)
        end
    end
end

NPCPerformanceTelemetryBridge.ApplySettings()

if Events and Events.OnTick and not NPCPerformanceTelemetryBridge._registered then
    NPCPerformanceTelemetryBridge._registered = true
    Events.OnTick.Add(NPCPerformanceTelemetryBridge.OnTick)
end
