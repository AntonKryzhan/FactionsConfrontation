-- NPCExperienceLedgerBridge.lua
-- Bounded outcome ledger for adaptive NPC behavior without heavy ML.
-- Stage 340: records action outcomes and forwards compact rewards to Q-lite learning.

NPCExperienceLedgerBridge = NPCExperienceLedgerBridge or {}

NPCExperienceLedgerBridge.VERSION = "2026-05-31-stage345-compact-experience-ledger-1"

NPCExperienceLedgerBridge.Config = NPCExperienceLedgerBridge.Config or {
    enabled = true,
    maxBrainEvents = 36,
    maxGlobalEvents = 256,
    eventThrottleMs = 180,
    compactData = true,
    maxDataFields = 18,
    rewardMin = -1.0,
    rewardMax = 1.0,
    summaryMs = 15000
}

NPCExperienceLedgerBridge.Global = NPCExperienceLedgerBridge.Global or {events={}, counters={}, lastSummaryAt=0}

local function bexp_nowMs()
    if getTimestampMs then
        local ok, value = pcall(function() return getTimestampMs() end)
        if ok and value then return tonumber(value) or 0 end
    end
    if getGameTime then
        local ok, value = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok and value then return math.floor((tonumber(value) or 0) * 3600000) end
    end
    return os.time() * 1000
end

local function bexp_clamp(value, lo, hi)
    value = tonumber(value) or 0
    if lo ~= nil and value < lo then return lo end
    if hi ~= nil and value > hi then return hi end
    return value
end

local function bexp_brainId(brain, chr)
    if brain then
        local id = brain.id or brain.uid or brain.persistentId or brain.runtimeId
        if id ~= nil then return tostring(id) end
    end
    if chr and NPCUtils and NPCUtils.GetZombieID then
        local ok, id = pcall(function() return NPCUtils.GetZombieID(chr) end)
        if ok and id ~= nil then return tostring(id) end
    end
    return chr and tostring(chr) or "unknown"
end

local function bexp_trim(list, max)
    max = tonumber(max) or 0
    if max <= 0 then return end
    local len = #list
    if len <= max then return end
    local overflow = len - max
    for i = 1, max do
        list[i] = list[i + overflow]
    end
    for i = max + 1, len do
        list[i] = nil
    end
end

local function bexp_compactData(data)
    if NPCExperienceLedgerBridge.Config.compactData ~= true or type(data) ~= "table" then return data end
    local out = {}
    local n = 0
    local max = tonumber(NPCExperienceLedgerBridge.Config.maxDataFields) or 18
    for k, v in pairs(data) do
        local tv = type(v)
        if tv == "number" or tv == "string" or tv == "boolean" then
            n = n + 1
            out[k] = v
            if n >= max then break end
        end
    end
    return out
end

function NPCExperienceLedgerBridge.Get(brain)
    if type(brain) ~= "table" then return nil end
    brain.ai = brain.ai or {}
    brain.ai.experienceLedger = brain.ai.experienceLedger or {events={}, counters={}, lastEventAt={}, version=NPCExperienceLedgerBridge.VERSION}
    return brain.ai.experienceLedger
end

function NPCExperienceLedgerBridge.Record(brain, chr, event, data)
    if NPCExperienceLedgerBridge.Config.enabled ~= true then return nil end
    event = tostring(event or "unknown")
    local now = bexp_nowMs()
    local ledger = NPCExperienceLedgerBridge.Get(brain)
    if ledger then
        ledger.lastEventAt = ledger.lastEventAt or {}
        local last = tonumber(ledger.lastEventAt[event]) or 0
        if now - last < (tonumber(NPCExperienceLedgerBridge.Config.eventThrottleMs) or 180) then
            return nil
        end
        ledger.lastEventAt[event] = now
        ledger.counters = ledger.counters or {}
        ledger.counters[event] = (tonumber(ledger.counters[event]) or 0) + 1
        ledger.events = ledger.events or {}
        local compact = bexp_compactData(data)
        ledger.events[#ledger.events + 1] = {t=now, event=event, data=compact}
        bexp_trim(ledger.events, NPCExperienceLedgerBridge.Config.maxBrainEvents)
    end

    local g = NPCExperienceLedgerBridge.Global
    g.counters[event] = (tonumber(g.counters[event]) or 0) + 1
    local compactGlobal = bexp_compactData(data)
    g.events[#g.events + 1] = {t=now, id=bexp_brainId(brain, chr), event=event, data=compactGlobal}
    bexp_trim(g.events, NPCExperienceLedgerBridge.Config.maxGlobalEvents)
    return true
end

function NPCExperienceLedgerBridge.Context(brain, situation, data)
    data = data or {}
    if NPCAdaptiveLearningBridge and NPCAdaptiveLearningBridge.MakeContext then
        local ok, context = pcall(function() return NPCAdaptiveLearningBridge.MakeContext(brain, situation, data) end)
        if ok and context then return context end
    end
    local role = brain and (brain.role or brain.squadRole or brain.job or brain.program) or "npc"
    local faction = brain and (brain.faction or brain.clan or brain.side) or "neutral"
    return tostring(role or "npc") .. "|" .. tostring(faction or "neutral") .. "|" .. tostring(situation or "generic")
end

function NPCExperienceLedgerBridge.Outcome(brain, chr, situation, action, reward, data)
    if NPCExperienceLedgerBridge.Config.enabled ~= true then return nil end
    reward = bexp_clamp(reward, NPCExperienceLedgerBridge.Config.rewardMin, NPCExperienceLedgerBridge.Config.rewardMax)
    action = tostring(action or "unknown")
    data = data or {}
    data.reward = reward
    data.action = action
    data.situation = situation
    NPCExperienceLedgerBridge.Record(brain, chr, "outcome_" .. action, data)

    if NPCAdaptiveLearningBridge and NPCAdaptiveLearningBridge.Update then
        local context = NPCExperienceLedgerBridge.Context(brain, situation, data)
        pcall(function() NPCAdaptiveLearningBridge.Update(context, action, reward, data) end)
    end
    return true
end

function NPCExperienceLedgerBridge.RecordPath(brain, chr, task, success, reason)
    local reward = success and 0.25 or -0.35
    if reason == "stuck" or reason == "no_progress" or reason == "lease_expired" or reason == "stuck_indoor" then reward = -0.75 end
    local data = {reason=reason, x=task and task.x, y=task and task.y, z=task and task.z}
    if NPCBeliefStateBridge and NPCBeliefStateBridge.NotePathResult then
        pcall(function() NPCBeliefStateBridge.NotePathResult(brain, task, success, reason) end)
    end
    if NPCAdaptiveLearningBridge and NPCAdaptiveLearningBridge.RecordPathOutcome then
        pcall(function() NPCAdaptiveLearningBridge.RecordPathOutcome(task, success, reward, data) end)
    end
    return NPCExperienceLedgerBridge.Outcome(brain, chr, "path", success and "path_success" or "path_fail", reward, data)
end

function NPCExperienceLedgerBridge.RecordShot(brain, chr, target, hit, data)
    data = data or {}
    local reward = hit and 0.55 or -0.10
    if data.blocked == true then reward = -0.35 end
    if data.friendly == true then reward = -1.0 end
    return NPCExperienceLedgerBridge.Outcome(brain, chr, "combat", hit and "shoot_hit" or "shoot_miss", reward, data)
end
