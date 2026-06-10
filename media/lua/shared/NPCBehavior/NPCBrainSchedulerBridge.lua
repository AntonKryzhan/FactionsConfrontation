require "NPCCore/NPCAILODTraderBridge"
require "NPCCore/NPCLegacySettingsBridge"
require "NPCCore/NPCUtilityCore"

NPCBrainSchedulerBridge = NPCBrainSchedulerBridge or {}

function NPCBrainSchedulerBridge.ApplyDefaults(scheduler)
    if not scheduler then return end

    scheduler.VERSION = scheduler.VERSION or "2026-05-03-event-driven"
    scheduler.Dirty = scheduler.Dirty or {}
    scheduler.LastThink = scheduler.LastThink or {}
    scheduler.Config = scheduler.Config or {}

    local config = scheduler.Config
    if config.enabled == nil then config.enabled = true end
    if config.minThinkMs == nil then config.minThinkMs = 100 end
    if config.lowThinkMs == nil then config.lowThinkMs = 800 end
    if config.proxyThinkMs == nil then config.proxyThinkMs = 2200 end
    if config.debugLog == nil then config.debugLog = false end
end

local function nbs_now()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then return math.floor((getGameTime():getWorldAgeHours() or 0) * 3600000) end
    return 0
end

local function nbs_numberSetting(key, defaultValue, minValue, maxValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        return NPCLegacySettingsBridge.GetNumber(key, defaultValue, minValue, maxValue)
    end
    return tonumber(defaultValue) or 0
end

local function nbs_boolSetting(key, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        return NPCLegacySettingsBridge.GetBool(key, defaultValue == true)
    end
    return defaultValue == true
end

local function nbs_key(bandit, brain)
    if brain and (brain.id or brain.uid) then
        return tostring(brain.id or brain.uid)
    end
    if NPCUtilityCore and NPCUtilityCore.GetCharacterID then
        local ok, id = pcall(function() return NPCUtilityCore.GetCharacterID(bandit) end)
        if ok and id then return tostring(id) end
    end
    return tostring(bandit)
end

function NPCBrainSchedulerBridge.ApplySettings(scheduler)
    NPCBrainSchedulerBridge.ApplyDefaults(scheduler)
    if not scheduler then return end

    local config = scheduler.Config
    config.enabled = nbs_boolSetting('BrainScheduler_Enabled', config.enabled ~= false)
    config.minThinkMs = nbs_numberSetting('BrainScheduler_MinThinkMs', config.minThinkMs, 0, 10000)
    config.lowThinkMs = nbs_numberSetting('BrainScheduler_LowThinkMs', config.lowThinkMs, 0, 60000)
    config.proxyThinkMs = nbs_numberSetting('BrainScheduler_ProxyThinkMs', config.proxyThinkMs, 0, 120000)
    config.debugLog = nbs_boolSetting('BrainScheduler_DebugLog', config.debugLog == true)
end

function NPCBrainSchedulerBridge.MarkDirty(scheduler, bandit, brain, reason)
    NPCBrainSchedulerBridge.ApplyDefaults(scheduler)
    if not scheduler then return end

    scheduler.Dirty[nbs_key(bandit, brain)] = reason or true
end

function NPCBrainSchedulerBridge.ShouldThink(scheduler, bandit, brain, tick, sub, threat)
    NPCBrainSchedulerBridge.ApplyDefaults(scheduler)
    if not scheduler then return true end

    local config = scheduler.Config
    if not config.enabled then return true end

    local key = nbs_key(bandit, brain)
    if scheduler.Dirty[key] then
        scheduler.Dirty[key] = nil
        scheduler.LastThink[key] = nbs_now()
        return true
    end

    if threat or (brain and (brain.currentThreat or brain.radioThreat or brain.targetId)) then
        scheduler.LastThink[key] = nbs_now()
        return true
    end

    if brain and brain.ai and tonumber(brain.ai.reactivePulseUntilMs or 0) > nbs_now() then
        scheduler.LastThink[key] = nbs_now()
        return true
    end

    if NPCAILODTraderBridge and NPCAILODTraderBridge.ShouldRunNPC then
        local ok, allow, lod = pcall(function()
            return NPCAILODTraderBridge.ShouldRunNPC(bandit, brain, sub or 'brain', tick, threat)
        end)
        if ok and allow == false then return false, lod end
    end

    local ms = nbs_now()
    local last = tonumber(scheduler.LastThink[key]) or 0
    local interval = config.minThinkMs

    if NPCAILODTraderBridge and NPCAILODTraderBridge.GetNPCLOD then
        local ok, lod = pcall(function() return NPCAILODTraderBridge.GetNPCLOD(bandit, brain, threat) end)
        if ok and lod == NPCAILODTraderBridge.LOD_LOW then
            interval = config.lowThinkMs
        elseif ok and lod == NPCAILODTraderBridge.LOD_PROXY then
            interval = config.proxyThinkMs
        end
    end

    if ms - last >= interval then
        scheduler.LastThink[key] = ms
        return true
    end

    return false
end
