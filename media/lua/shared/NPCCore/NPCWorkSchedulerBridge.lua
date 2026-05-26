-- NPCWorkSchedulerBridge.lua
-- Neutral shared backend for adaptive work scheduler.

NPCWorkSchedulerBridge = NPCWorkSchedulerBridge or {}

NPCWorkSchedulerBridge.Tick = NPCWorkSchedulerBridge.Tick or 0
NPCWorkSchedulerBridge.Counters = NPCWorkSchedulerBridge.Counters or {}
NPCWorkSchedulerBridge.LastResetTick = NPCWorkSchedulerBridge.LastResetTick or -1
NPCWorkSchedulerBridge.TickJobs = NPCWorkSchedulerBridge.TickJobs or {}
NPCWorkSchedulerBridge.TickJobIndex = NPCWorkSchedulerBridge.TickJobIndex or {}
NPCWorkSchedulerBridge.VERSION = "2026-05-24-v10-optimization-governor-1"

NPCWorkSchedulerBridge.DefaultBudget = NPCWorkSchedulerBridge.DefaultBudget or {
    ai = 10,
    combat = 9,
    utility = 5,
    zombie = 8,
    persistent = 7,
    spawn = 3,
    marker = 18,
    system = 12,
    physical = 22,
    path = 2,
    zombiePath = 1,
    sense = 6,
    los = 5
}

NPCWorkSchedulerBridge.Adaptive = NPCWorkSchedulerBridge.Adaptive or {
    enabled = true,
    sampleTicks = 20,
    lowFPS = 59,
    criticalFPS = 53,
    panicFPS = 47,
    highNPC = 14,
    criticalNPC = 28,
    highZombies = 110,
    criticalZombies = 220,
    highBudgetPercent = 48,
    criticalBudgetPercent = 26,
    panicBudgetPercent = 14,
    highIntervalMultiplier = 2,
    criticalIntervalMultiplier = 5,
    panicIntervalMultiplier = 9,
    maxZombieInterval = 32,
    debug = false,
    logIntervalMs = 15000
}

NPCWorkSchedulerBridge.LoadState = NPCWorkSchedulerBridge.LoadState or {
    tick = -99999,
    fps = 60,
    npc = 0,
    zombies = 0,
    level = 0,
    name = "LOW",
    lastLogMs = 0
}

if NPCLegacySettingsBridge and NPCLegacySettingsBridge.ApplyWorkScheduler then
    NPCLegacySettingsBridge.ApplyWorkScheduler(NPCWorkSchedulerBridge)
end

local function bws_hash(value)
    local s = tostring(value or 0)
    local h = 0
    for i = 1, #s do
        h = (h * 33 + string.byte(s, i)) % 9973
    end
    return h
end

local function bws_count(tbl)
    if type(tbl) ~= "table" then return 0 end
    local n = 0
    for _ in pairs(tbl) do
        n = n + 1
    end
    return n
end

local function bws_countLimited(tbl, limit)
    if type(tbl) ~= "table" then return 0 end
    limit = tonumber(limit) or 1000
    local n = 0
    for _ in pairs(tbl) do
        n = n + 1
        if n >= limit then return n end
    end
    return n
end

local function bws_nowMs()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then
        local ok, hours = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok and hours then return math.floor((tonumber(hours) or 0) * 3600000) end
    end
    return 0
end

local function bws_averageFPS()
    if getAverageFPS then
        local ok, fps = pcall(function() return getAverageFPS() end)
        if ok and fps then return tonumber(fps) or 60 end
    end
    return 60
end


local function bws_cameraZoom()
    if getCore and getCore() and getCore().getZoom then
        local ok, zoom = pcall(function() return getCore():getZoom(0) end)
        if ok and tonumber(zoom) then return tonumber(zoom) end
    end
    return 1
end

local function bws_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        return NPCLegacySettingsBridge.GetBool(name, defaultValue == true)
    end
    return defaultValue == true
end

local function bws_number(name, defaultValue, minValue, maxValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        return NPCLegacySettingsBridge.GetNumber(name, defaultValue, minValue, maxValue)
    end
    local value = tonumber(defaultValue) or 0
    if minValue ~= nil and value < minValue then value = minValue end
    if maxValue ~= nil and value > maxValue then value = maxValue end
    return value
end

local function bws_applyAdaptiveSettings()
    local cfg = NPCWorkSchedulerBridge.Adaptive
    if not cfg then return end

    cfg.enabled = bws_bool("AIWork_AdaptiveBudget", cfg.enabled ~= false)
    cfg.sampleTicks = bws_number("AIWork_AdaptiveSampleTicks", cfg.sampleTicks or 30, 5, 600)
    cfg.lowFPS = bws_number("AIWork_LowFPS", cfg.lowFPS or 55, 5, 240)
    cfg.criticalFPS = bws_number("AIWork_CriticalFPS", cfg.criticalFPS or 42, 5, 240)
    cfg.panicFPS = bws_number("AIWork_PanicFPS", cfg.panicFPS or 34, 5, 240)
    cfg.highNPC = bws_number("AIWork_HighNPC", cfg.highNPC or 36, 1, 500)
    cfg.criticalNPC = bws_number("AIWork_CriticalNPC", cfg.criticalNPC or 58, 1, 1000)
    cfg.highZombies = bws_number("AIWork_HighZombies", cfg.highZombies or 220, 1, 2000)
    cfg.criticalZombies = bws_number("AIWork_CriticalZombies", cfg.criticalZombies or 380, 1, 3000)
    cfg.highBudgetPercent = bws_number("AIWork_HighBudgetPercent", cfg.highBudgetPercent or 65, 10, 100)
    cfg.criticalBudgetPercent = bws_number("AIWork_CriticalBudgetPercent", cfg.criticalBudgetPercent or 38, 5, 100)
    cfg.panicBudgetPercent = bws_number("AIWork_PanicBudgetPercent", cfg.panicBudgetPercent or 25, 5, 100)
    cfg.highIntervalMultiplier = bws_number("AIWork_HighIntervalMultiplier", cfg.highIntervalMultiplier or 2, 1, 12)
    cfg.criticalIntervalMultiplier = bws_number("AIWork_CriticalIntervalMultiplier", cfg.criticalIntervalMultiplier or 4, 1, 24)
    cfg.panicIntervalMultiplier = bws_number("AIWork_PanicIntervalMultiplier", cfg.panicIntervalMultiplier or 6, 1, 36)
    cfg.maxZombieInterval = bws_number("AIWork_MaxZombieInterval", cfg.maxZombieInterval or 32, 1, 120)
    cfg.debug = bws_bool("AIWork_DebugSummary", cfg.debug == true)
    cfg.logIntervalMs = bws_number("AIWork_DebugSummaryMs", cfg.logIntervalMs or 15000, 1000, 120000)
end

function NPCWorkSchedulerBridge.GetLoadState(force)
    local cfg = NPCWorkSchedulerBridge.Adaptive or {}
    local state = NPCWorkSchedulerBridge.LoadState or {}

    if not (cfg.enabled ~= false) then
        state.level = 0
        state.name = "LOW"
        NPCWorkSchedulerBridge.LoadState = state
        return state
    end

    local tick = NPCWorkSchedulerBridge.GetTick()
    local sampleTicks = tonumber(cfg.sampleTicks) or 30
    if not force and state.tick and tick - state.tick < sampleTicks then
        return state
    end

    local npc = 0
    local zombies = 0
    if NPCZombieCacheBridge then
        npc = bws_countLimited(NPCZombieCacheBridge.CacheLightB, (tonumber(cfg.criticalNPC) or 58) + 8)
        zombies = bws_countLimited(NPCZombieCacheBridge.CacheLightZ, (tonumber(cfg.criticalZombies) or 380) + 16)
    end

    local fps = bws_averageFPS()
    local zoom = bws_cameraZoom()
    local level = 0
    if fps > 0 and fps < (tonumber(cfg.lowFPS) or 55) then level = math.max(level, 1) end
    if fps > 0 and fps < (tonumber(cfg.criticalFPS) or 42) then level = math.max(level, 2) end
    if fps > 0 and fps < (tonumber(cfg.panicFPS) or 34) then level = math.max(level, 3) end
    if zoom >= 1.45 then level = math.max(level, 1) end
    if zoom >= 1.90 then level = math.max(level, 2) end
    if zoom >= 2.35 then level = math.max(level, 3) end

    if NPCRenderReliefBridge and NPCRenderReliefBridge.GetLoadState then
        local okRelief, relief = pcall(function() return NPCRenderReliefBridge.GetLoadState(false) end)
        if okRelief and relief then
            local rLevel = tonumber(relief.level) or 0
            if rLevel > level then level = rLevel end
        end
    end
    if npc >= (tonumber(cfg.highNPC) or 36) or zombies >= (tonumber(cfg.highZombies) or 220) then level = math.max(level, 1) end
    if npc >= (tonumber(cfg.criticalNPC) or 58) or zombies >= (tonumber(cfg.criticalZombies) or 380) then level = math.max(level, 2) end

    if NPCStreamingRuntimeBridge and NPCStreamingRuntimeBridge.State then
        local sLevel = tonumber(NPCStreamingRuntimeBridge.State.level) or 0
        if sLevel >= 2 then level = math.max(level, 1) end
        if sLevel >= 3 then level = math.max(level, 2) end
    end

    state.tick = tick
    state.fps = fps
    state.npc = npc
    state.zombies = zombies
    state.zoom = zoom
    state.level = level
    state.name = level >= 3 and "PANIC" or (level >= 2 and "CRITICAL" or (level >= 1 and "HIGH" or "LOW"))
    NPCWorkSchedulerBridge.LoadState = state

    if cfg.debug then
        local now = bws_nowMs()
        if now - (state.lastLogMs or 0) >= (tonumber(cfg.logIntervalMs) or 15000) then
            state.lastLogMs = now
            print("[NPCPerf] scheduler=" .. tostring(state.name) .. " fps=" .. tostring(math.floor((fps or 0) + 0.5)) .. " zoom=" .. tostring(math.floor((zoom or 1) * 100 + 0.5) / 100) .. " npc=" .. tostring(npc) .. " zombies=" .. tostring(zombies) .. " ai=" .. tostring(NPCWorkSchedulerBridge.Counters.ai or 0) .. " path=" .. tostring(NPCWorkSchedulerBridge.Counters.path or 0) .. " zombiePath=" .. tostring(NPCWorkSchedulerBridge.Counters.zombiePath or 0))
        end
    end

    return state
end

local function bws_adjustBudget(kind, budget)
    local cfg = NPCWorkSchedulerBridge.Adaptive or {}
    if not (cfg.enabled ~= false) then return budget end

    local state = NPCWorkSchedulerBridge.GetLoadState(false)
    local level = tonumber(state.level) or 0
    if level <= 0 then return budget end

    local protected = kind == "combat"
    local percent = level >= 3 and (tonumber(cfg.panicBudgetPercent) or 14) or (level >= 2 and (tonumber(cfg.criticalBudgetPercent) or 26) or (tonumber(cfg.highBudgetPercent) or 48))
    if protected then
        percent = math.min(percent, level >= 3 and 24 or (level >= 2 and 36 or 48))
    elseif kind == "path" then
        percent = math.min(percent, level >= 3 and 12 or (level >= 2 and 20 or 34))
    elseif kind == "zombiePath" then
        percent = math.min(percent, level >= 3 and 10 or (level >= 2 and 16 or 28))
    elseif kind == "spawn" then
        percent = math.min(percent, level >= 3 and 15 or (level >= 2 and 25 or 40))
    elseif kind == "sense" then
        percent = math.min(percent, level >= 3 and 12 or (level >= 2 and 22 or 38))
    elseif kind == "los" then
        percent = math.min(percent, level >= 3 and 10 or (level >= 2 and 20 or 35))
    elseif kind == "physical" then
        percent = math.min(percent, level >= 3 and 18 or (level >= 2 and 32 or 55))
    end

    return math.max(1, math.floor((tonumber(budget) or 1) * percent / 100))
end

local function bws_adjustInterval(kind, interval, brain)
    local cfg = NPCWorkSchedulerBridge.Adaptive or {}
    if not (cfg.enabled ~= false) then return interval end

    local state = NPCWorkSchedulerBridge.GetLoadState(false)
    local level = tonumber(state.level) or 0
    if level <= 0 then return interval end

    local mult = level >= 3 and (tonumber(cfg.panicIntervalMultiplier) or 6) or (level >= 2 and (tonumber(cfg.criticalIntervalMultiplier) or 4) or (tonumber(cfg.highIntervalMultiplier) or 2))
    if brain and (brain.inBattle or brain.target or brain.targetId or brain.enemy or brain.lastKnownEnemyPosition) then
        mult = math.max(1, math.floor(mult / 2))
    end

    local adjusted = math.max(1, math.floor((tonumber(interval) or 1) * mult))
    if kind == "zombie" then
        adjusted = math.min(adjusted, tonumber(cfg.maxZombieInterval) or 32)
    end
    return adjusted
end

function NPCWorkSchedulerBridge.ApplyAdaptiveSettings()
    bws_applyAdaptiveSettings()
end

function NPCWorkSchedulerBridge.ResetCounters()
    NPCWorkSchedulerBridge.Counters = {}
    NPCWorkSchedulerBridge.LastResetTick = NPCWorkSchedulerBridge.Tick
end


function NPCWorkSchedulerBridge.RegisterTickJob(name, fn, kind, interval, budget)
    if type(name) ~= "string" or name == "" or type(fn) ~= "function" then return false end

    local idx = NPCWorkSchedulerBridge.TickJobIndex[name]
    local job = nil
    if idx then
        job = NPCWorkSchedulerBridge.TickJobs[idx]
    end

    if not job then
        job = {name = name}
        table.insert(NPCWorkSchedulerBridge.TickJobs, job)
        NPCWorkSchedulerBridge.TickJobIndex[name] = #NPCWorkSchedulerBridge.TickJobs
    end

    job.fn = fn
    job.kind = tostring(kind or "utility")
    job.interval = math.max(1, tonumber(interval) or 1)
    job.budget = tonumber(budget)
    job.enabled = true
    return true
end

function NPCWorkSchedulerBridge.UnregisterTickJob(name)
    name = tostring(name or "")
    local idx = NPCWorkSchedulerBridge.TickJobIndex[name]
    if not idx then return false end

    local job = NPCWorkSchedulerBridge.TickJobs[idx]
    if job then
        job.enabled = false
        job.fn = nil
    end
    NPCWorkSchedulerBridge.TickJobIndex[name] = nil
    return true
end

local function bws_processTickJobs()
    local jobs = NPCWorkSchedulerBridge.TickJobs
    if type(jobs) ~= "table" or #jobs == 0 then return end

    local tick = NPCWorkSchedulerBridge.GetTick()
    for i = 1, #jobs do
        local job = jobs[i]
        if job and job.enabled ~= false and type(job.fn) == "function" then
            local interval = math.max(1, tonumber(job.interval) or 1)
            if interval <= 1 or NPCWorkSchedulerBridge.ShouldRun(job.name, interval, tick) then
                local kind = tostring(job.kind or "utility")
                local budget = tonumber(job.budget) or NPCWorkSchedulerBridge.GetBudget(kind)
                if NPCWorkSchedulerBridge.UseBudget(kind, budget) then
                    local ok, err = pcall(job.fn, tick)
                    if not ok then
                        print("[NPCWorkSchedulerBridge] tick job failed: " .. tostring(job.name) .. " / " .. tostring(err))
                    end
                end
            end
        end
    end
end

function NPCWorkSchedulerBridge.OnTick()
    NPCWorkSchedulerBridge.Tick = (NPCWorkSchedulerBridge.Tick or 0) + 1
    NPCWorkSchedulerBridge.ResetCounters()
    bws_processTickJobs()
    if NPCAsyncSchedulerBridge and NPCAsyncSchedulerBridge.ProcessBudget then
        pcall(function() NPCAsyncSchedulerBridge.ProcessBudget() end)
    end
end

function NPCWorkSchedulerBridge.GetTick()
    return NPCWorkSchedulerBridge.Tick or 0
end

function NPCWorkSchedulerBridge.GetBudget(kind)
    kind = tostring(kind or "ai")
    local budget = tonumber(NPCWorkSchedulerBridge.DefaultBudget[kind]) or 16
    if NPCStreamingRuntimeBridge and NPCStreamingRuntimeBridge.AdjustBudget then
        budget = NPCStreamingRuntimeBridge.AdjustBudget(kind, budget)
    end
    budget = bws_adjustBudget(kind, budget)
    return math.max(1, tonumber(budget) or 1)
end

function NPCWorkSchedulerBridge.UseBudget(kind, budget)
    kind = tostring(kind or "ai")
    budget = tonumber(budget) or NPCWorkSchedulerBridge.GetBudget(kind)

    local used = tonumber(NPCWorkSchedulerBridge.Counters[kind]) or 0
    if used >= budget then return false end

    NPCWorkSchedulerBridge.Counters[kind] = used + 1
    return true
end

function NPCWorkSchedulerBridge.ShouldRun(id, interval, tick)
    interval = tonumber(interval) or 1
    if interval <= 1 then return true end

    tick = tonumber(tick) or NPCWorkSchedulerBridge.GetTick()
    return ((tick + bws_hash(id)) % interval) == 0
end

function NPCWorkSchedulerBridge.CanRun(kind, id, interval, budget, tick)
    if not NPCWorkSchedulerBridge.ShouldRun(id, interval, tick) then return false end
    return NPCWorkSchedulerBridge.UseBudget(kind, budget)
end

function NPCWorkSchedulerBridge.GetQueueLoad()
    local gmd = nil
    if GetNPCModData then
        pcall(function() gmd = GetNPCModData() end)
    end
    local queueCount = gmd and bws_count(gmd.Queue) or 0
    local markerCount = gmd and bws_count(gmd.DebugMapMarkers) or 0
    return queueCount, markerCount
end

function NPCWorkSchedulerBridge.GetSpawnBatch()
    local queueCount = NPCWorkSchedulerBridge.GetQueueLoad()
    local batch = NPCWorkSchedulerBridge.GetBudget("spawn")
    if queueCount > 120 then batch = math.min(batch, 2) end
    if queueCount > 80 then batch = math.min(batch, 3) end
    if NPCCrowdBudgetBridge and NPCCrowdBudgetBridge.AdjustGlobalSpawnBatch then
        batch = NPCCrowdBudgetBridge.AdjustGlobalSpawnBatch(batch)
    end
    return math.max(1, tonumber(batch) or 1)
end

local function bws_nearestPlayerDistance(x, y)
    local best = nil
    local function consider(player)
        if not (player and player.getX and player.getY) then return end
        if player.isDead and player:isDead() then return end
        local dx = (tonumber(x) or 0) - (tonumber(player:getX()) or 0)
        local dy = (tonumber(y) or 0) - (tonumber(player:getY()) or 0)
        local d2 = dx * dx + dy * dy
        if not best or d2 < best then best = d2 end
    end

    if getOnlinePlayers then
        local ok, players = pcall(function() return getOnlinePlayers() end)
        if ok and players then
            for i = 0, players:size() - 1 do
                consider(players:get(i))
            end
        end
    end

    if not best and getNumActivePlayers and getSpecificPlayer then
        local ok, count = pcall(function() return getNumActivePlayers() end)
        count = ok and tonumber(count) or 1
        for i = 0, math.max(0, count - 1) do
            consider(getSpecificPlayer(i))
        end
    end

    if not best and getSpecificPlayer then
        consider(getSpecificPlayer(0))
    end

    return best and math.sqrt(best) or 999999
end

local function bws_currentTask(brain)
    if not (brain and type(brain.tasks) == "table") then return nil end
    return brain.tasks[1]
end

function NPCWorkSchedulerBridge.IsPhysicalCritical(bandit, brain)
    if brain then
        if brain.inBattle or brain.virtualBattle or brain.battleId then return true end
        if brain.target or brain.targetId or brain.enemy or brain.lastKnownEnemyPosition then return true end
        if brain.mercenaryHired or brain.hired or brain.isPlayerGuard or brain.master or brain.follow then return true end
        if brain.blackMarket == true or brain.blackMarketNPC == true or brain.nonCombatant == true then return true end

        local task = bws_currentTask(brain)
        if task then
            if task.lock == true then return true end
            local action = tostring(task.action or "")
            if action == "Shoot" or action == "Aim" or action == "Hit" or action == "Shove" or action == "Bandage" then return true end
        end
    end

    if bandit then
        local ok, target = pcall(function() return bandit.getTarget and bandit:getTarget() or nil end)
        if ok and target and (not target.isAlive or target:isAlive()) then return true end
        ok, target = pcall(function() return bandit.getAttackedBy and bandit:getAttackedBy() or nil end)
        if ok and target and (not target.isAlive or target:isAlive()) then return true end
    end

    return false
end

function NPCWorkSchedulerBridge.GetPhysicalLOD(bandit, brain)
    if NPCAILODTraderBridge and NPCAILODTraderBridge.GetNPCLOD then
        local ok, lod, score, dist = pcall(function() return NPCAILODTraderBridge.GetNPCLOD(bandit, brain, NPCWorkSchedulerBridge.IsPhysicalCritical(bandit, brain)) end)
        if ok and lod ~= nil then return tonumber(lod) or 0, tonumber(dist) or 999999, tonumber(score) or 0 end
    end

    if not (bandit and bandit.getX and bandit.getY) then return 4, 999999, 0 end
    local dist = bws_nearestPlayerDistance(bandit:getX(), bandit:getY())
    local full = bws_number("AILOD_NPCFullRadius", 42, 5, 1000)
    local high = bws_number("AILOD_NPCHighRadius", 90, full, 1500)
    local medium = bws_number("AILOD_NPCMediumRadius", 180, high, 2500)
    local low = bws_number("AILOD_NPCLowRadius", 320, medium, 5000)

    if dist <= full then return 0, dist, 100 end
    if dist <= high then return 1, dist, 70 end
    if dist <= medium then return 2, dist, 40 end
    if dist <= low then return 3, dist, 15 end
    return 4, dist, 0
end

function NPCWorkSchedulerBridge.GetPhysicalUpdateInterval(bandit, brain)
    if not bws_bool("AILOD_PhysicalFrameEnabled", true) then return 1 end
    if NPCWorkSchedulerBridge.IsPhysicalCritical(bandit, brain) then return 1 end

    local lod = NPCWorkSchedulerBridge.GetPhysicalLOD(bandit, brain)
    if lod <= 0 then return bws_number("AILOD_PhysicalFullInterval", 1, 1, 120) end
    if lod == 1 then return bws_number("AILOD_PhysicalHighInterval", 2, 1, 120) end
    if lod == 2 then return bws_number("AILOD_PhysicalMediumInterval", 4, 1, 240) end
    if lod == 3 then return bws_number("AILOD_PhysicalLowInterval", 8, 1, 480) end
    return bws_number("AILOD_PhysicalProxyInterval", 16, 1, 960)
end

function NPCWorkSchedulerBridge.AllowCriticalPhysicalUpdate(id, brain, bandit, uTick)
    local state = NPCWorkSchedulerBridge.GetLoadState(false)
    local level = tonumber(state.level) or 0
    local zoom = tonumber(state.zoom) or 1
    if level <= 0 and zoom < 1.65 then return true end

    if brain and (brain.blackMarket == true or brain.blackMarketNPC == true or brain.nonCombatant == true) then
        return true
    end

    local interval = 1
    if level >= 3 or zoom >= 2.60 then
        interval = 4
    elseif level >= 2 or zoom >= 2.15 then
        interval = 3
    elseif level >= 1 or zoom >= 1.65 then
        interval = 2
    end
    if interval <= 1 then return NPCWorkSchedulerBridge.UseBudget("physical", NPCWorkSchedulerBridge.GetBudget("physical")) end
    return NPCWorkSchedulerBridge.CanRun("physical", id, interval, NPCWorkSchedulerBridge.GetBudget("physical"), uTick)
end

function NPCWorkSchedulerBridge.AllowPhysicalUpdate(id, brain, bandit, uTick)
    if NPCLegacySettingsBridge and not NPCLegacySettingsBridge.GetBool("AIWork_Enabled", true) then
        return true
    end
    if not bws_bool("AILOD_PhysicalFrameEnabled", true) then return true end
    if NPCWorkSchedulerBridge.IsPhysicalCritical(bandit, brain) then
        return NPCWorkSchedulerBridge.AllowCriticalPhysicalUpdate(id, brain, bandit, uTick)
    end

    local interval = NPCWorkSchedulerBridge.GetPhysicalUpdateInterval(bandit, brain)
    if interval <= 1 then
        return NPCWorkSchedulerBridge.UseBudget("physical", NPCWorkSchedulerBridge.GetBudget("physical"))
    end
    return NPCWorkSchedulerBridge.CanRun("physical", id, interval, NPCWorkSchedulerBridge.GetBudget("physical"), uTick)
end

function NPCWorkSchedulerBridge.GetAIInterval(brain)
    local interval = 8

    if brain then
        if brain.inBattle or brain.virtualBattle or brain.battleId then
            interval = (NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber("AIWork_CombatThinkInterval", 2, 1, 60)) or 2
        elseif brain.target or brain.targetId or brain.enemy or brain.lastKnownEnemyPosition then
            interval = (NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber("AIWork_CombatThinkInterval", 2, 1, 60)) or 2
        elseif brain.tasks and #brain.tasks > 0 then
            interval = 4
        elseif brain.roadPatrol or brain.follow or brain.master then
            interval = 4
        else
            local program = brain.program
            if program and (program.name == "Companion" or program.name == "BaseGuard") then
                interval = 4
            else
                interval = (NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber("AIWork_IdleThinkInterval", 8, 1, 120)) or 8
            end
        end
    end

    if NPCStreamingRuntimeBridge and NPCStreamingRuntimeBridge.AdjustInterval then
        interval = NPCStreamingRuntimeBridge.AdjustInterval("ai", interval, brain)
    end
    interval = bws_adjustInterval("ai", interval, brain)

    return math.max(1, tonumber(interval) or 1)
end

function NPCWorkSchedulerBridge.AllowAI(id, brain, uTick)
    local interval = NPCWorkSchedulerBridge.GetAIInterval(brain)
    local budget = NPCWorkSchedulerBridge.GetBudget("ai")

    if brain and brain.inBattle then
        budget = NPCWorkSchedulerBridge.GetBudget("combat")
    end

    if NPCLegacySettingsBridge and not NPCLegacySettingsBridge.GetBool("AIWork_Enabled", true) then
        return true
    end

    return NPCWorkSchedulerBridge.CanRun("ai", id, interval, budget, uTick)
end

function NPCWorkSchedulerBridge.AllowUtility(id, brain, uTick)
    local interval = 4
    if brain and (brain.inBattle or brain.target or brain.targetId) then
        interval = 2
    end
    if NPCStreamingRuntimeBridge and NPCStreamingRuntimeBridge.AdjustInterval then
        interval = NPCStreamingRuntimeBridge.AdjustInterval("utility", interval, brain)
    end
    interval = bws_adjustInterval("utility", interval, brain)
    return NPCWorkSchedulerBridge.CanRun("utility", id, interval, NPCWorkSchedulerBridge.GetBudget("utility"), uTick)
end

function NPCWorkSchedulerBridge.AllowZombieUpdate(id, uTick)
    local interval = (NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber("AIWork_ZombieCheckInterval", 4, 1, 120)) or 4
    if NPCStreamingRuntimeBridge and NPCStreamingRuntimeBridge.AdjustInterval then
        interval = NPCStreamingRuntimeBridge.AdjustInterval("zombie", interval, nil)
    end
    interval = bws_adjustInterval("zombie", interval, nil)
    return NPCWorkSchedulerBridge.CanRun("zombie", id, interval, NPCWorkSchedulerBridge.GetBudget("zombie"), uTick)
end

function NPCWorkSchedulerBridge.AllowPathRequest(id, reason, kind)
    if NPCLegacySettingsBridge and not NPCLegacySettingsBridge.GetBool("AIWork_Enabled", true) then
        return true
    end

    kind = tostring(kind or "path")
    local budgetKind = kind == "zombie" and "zombiePath" or "path"
    return NPCWorkSchedulerBridge.UseBudget(budgetKind, NPCWorkSchedulerBridge.GetBudget(budgetKind))
end

function NPCWorkSchedulerBridge.AllowSense(id, brain, uTick)
    if NPCLegacySettingsBridge and not NPCLegacySettingsBridge.GetBool("AIWork_Enabled", true) then
        return true
    end

    local interval = 1
    if brain and not (brain.inBattle or brain.target or brain.targetId or brain.enemy or brain.lastKnownEnemyPosition) then
        interval = (NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber("Sense_IdleScanInterval", 2, 1, 60)) or 2
    end
    if NPCStreamingRuntimeBridge and NPCStreamingRuntimeBridge.AdjustInterval then
        interval = NPCStreamingRuntimeBridge.AdjustInterval("sense", interval, brain)
    end
    interval = bws_adjustInterval("sense", interval, brain)
    return NPCWorkSchedulerBridge.CanRun("sense", id, interval, NPCWorkSchedulerBridge.GetBudget("sense"), uTick)
end

function NPCWorkSchedulerBridge.AllowLOS(id, reason)
    if NPCLegacySettingsBridge and not NPCLegacySettingsBridge.GetBool("AIWork_Enabled", true) then
        return true
    end

    return NPCWorkSchedulerBridge.UseBudget("los", NPCWorkSchedulerBridge.GetBudget("los"))
end

function NPCWorkSchedulerBridge.AllowCombatScan(id, brain, uTick, bandit)
    if NPCLegacySettingsBridge and not NPCLegacySettingsBridge.GetBool("AIWork_Enabled", true) then
        return true
    end

    local state = NPCWorkSchedulerBridge.GetLoadState(false)
    local level = tonumber(state.level) or 0
    local interval = 1
    local critical = NPCWorkSchedulerBridge.IsPhysicalCritical(bandit, brain)

    if level >= 3 then
        interval = critical and 3 or 9
    elseif level >= 2 then
        interval = critical and 2 or 6
    elseif level >= 1 then
        interval = critical and 1 or 3
    end

    if interval <= 1 then
        return NPCWorkSchedulerBridge.UseBudget("combat", NPCWorkSchedulerBridge.GetBudget("combat"))
    end
    return NPCWorkSchedulerBridge.CanRun("combat", id, interval, NPCWorkSchedulerBridge.GetBudget("combat"), uTick)
end

function NPCWorkSchedulerBridge.AllowVisualUpdate(id, brain, uTick)
    local state = NPCWorkSchedulerBridge.GetLoadState(false)
    local level = tonumber(state.level) or 0
    local interval = level >= 3 and 96 or (level >= 2 and 48 or (level >= 1 and 24 or 12))
    return NPCWorkSchedulerBridge.ShouldRun(id, interval, uTick)
end

function NPCWorkSchedulerBridge.AllowTorchUpdate(id, brain, uTick)
    local state = NPCWorkSchedulerBridge.GetLoadState(false)
    local level = tonumber(state.level) or 0
    local interval = level >= 3 and 160 or (level >= 2 and 96 or (level >= 1 and 48 or 24))
    return NPCWorkSchedulerBridge.ShouldRun(id, interval, uTick)
end

function NPCWorkSchedulerBridge.AllowPersistent(uid, uTick)
    return NPCWorkSchedulerBridge.CanRun("persistent", uid, 16, NPCWorkSchedulerBridge.GetBudget("persistent"), uTick)
end

function NPCWorkSchedulerBridge.AllowMarker(id, uTick)
    local interval = 8
    if NPCStreamingRuntimeBridge and NPCStreamingRuntimeBridge.AdjustMarkerInterval then
        interval = NPCStreamingRuntimeBridge.AdjustMarkerInterval(interval)
    end
    return NPCWorkSchedulerBridge.CanRun("marker", id, interval, NPCWorkSchedulerBridge.GetBudget("marker"), uTick)
end

NPCWorkSchedulerBridge.ApplyAdaptiveSettings()

if Events and Events.OnTick and not NPCWorkSchedulerBridge._registered then
    NPCWorkSchedulerBridge._registered = true
    Events.OnTick.Add(NPCWorkSchedulerBridge.OnTick)
end
