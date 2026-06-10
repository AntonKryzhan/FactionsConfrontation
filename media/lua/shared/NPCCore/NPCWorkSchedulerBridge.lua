-- NPCWorkSchedulerBridge.lua
-- Neutral shared backend for adaptive work scheduler.

NPCWorkSchedulerBridge = NPCWorkSchedulerBridge or {}

NPCWorkSchedulerBridge.Tick = NPCWorkSchedulerBridge.Tick or 0
NPCWorkSchedulerBridge.Counters = NPCWorkSchedulerBridge.Counters or {}
NPCWorkSchedulerBridge.LastResetTick = NPCWorkSchedulerBridge.LastResetTick or -1
NPCWorkSchedulerBridge.TickJobs = NPCWorkSchedulerBridge.TickJobs or {}
NPCWorkSchedulerBridge.TickJobIndex = NPCWorkSchedulerBridge.TickJobIndex or {}
NPCWorkSchedulerBridge.BudgetCache = NPCWorkSchedulerBridge.BudgetCache or {tick=-1, values={}}
NPCWorkSchedulerBridge.VERSION = "2026-06-10-stage454-safe-cpu-gc-micro-optimizations-1"

NPCWorkSchedulerBridge.DefaultBudget = NPCWorkSchedulerBridge.DefaultBudget or {
    ai = 8,
    combat = 12,
    utility = 6,
    zombie = 5,
    persistent = 3,
    spawn = 1,
    marker = 6,
    ui = 1,
    world = 1,
    effects = 1,
    system = 3,
    physical = 5,
    path = 1,
    zombiePath = 1,
    sense = 4,
    los = 5,
    learning = 1
}

NPCWorkSchedulerBridge.Adaptive = NPCWorkSchedulerBridge.Adaptive or {
    enabled = true,
    sampleTicks = 3,
    lowFPS = 59,
    criticalFPS = 55,
    panicFPS = 47,
    highNPC = 8,
    criticalNPC = 14,
    highZombies = 60,
    criticalZombies = 110,
    highBudgetPercent = 35,
    criticalBudgetPercent = 18,
    panicBudgetPercent = 6,
    highIntervalMultiplier = 4,
    criticalIntervalMultiplier = 9,
    panicIntervalMultiplier = 18,
    maxZombieInterval = 150,
    debug = false,
    logIntervalMs = 15000
}

NPCWorkSchedulerBridge.BattleGovernorDiagnostics = NPCWorkSchedulerBridge.BattleGovernorDiagnostics or {
    enabled = false,
    counters = {}
}

NPCWorkSchedulerBridge.BattleGovernor = NPCWorkSchedulerBridge.BattleGovernor or {
    enabled = true,
    fullRadius = 28,
    frontlineRadius = 48,
    supportRadius = 82,
    reserveRadius = 132,
    closeTargetFullRadius = 10,
    frontlineIntervalHigh = 2,
    frontlineIntervalCritical = 3,
    supportIntervalLow = 4,
    supportIntervalHigh = 10,
    supportIntervalCritical = 18,
    reserveIntervalLow = 10,
    reserveIntervalHigh = 30,
    reserveIntervalCritical = 55,
    proxyIntervalLow = 32,
    proxyIntervalHigh = 110,
    proxyIntervalCritical = 170,
    combatScanSupportInterval = 6,
    combatScanReserveInterval = 14,
    combatScanProxyInterval = 28,
    pressureMultiplierHigh = 1.45,
    pressureMultiplierCritical = 1.95
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


-- Stage448: cooperative path-request queue. This is a Lua-side analogue of a
-- pathfinding work queue: when a non-critical NPC movement cannot acquire the
-- per-tick path budget, we defer one bounded retry instead of letting many NPCs
-- hit PathFindBehavior2 in the same frame.
NPCWorkSchedulerBridge.PathQueueConfig = NPCWorkSchedulerBridge.PathQueueConfig or {
    enabled = true,
    maxSize = 96,
    perTick = 2,
    minAgeMs = 75,
    maxAgeMs = 4500,
    highWater = 32,
    criticalWater = 64,
    stallRecoverPerTick = 1,
    debug = false
}

NPCWorkSchedulerBridge.PathRequestQueue = NPCWorkSchedulerBridge.PathRequestQueue or {
    queue = {},
    ids = {},
    stats = {queued=0, updated=0, processed=0, expired=0, dropped=0, failed=0, denied=0}
}

if NPCLegacySettingsBridge and NPCLegacySettingsBridge.ApplyWorkScheduler then
    NPCLegacySettingsBridge.ApplyWorkScheduler(NPCWorkSchedulerBridge)
end

local bws_isPlayerControlledBrain

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

function NPCWorkSchedulerBridge.IncBattleGovernorStat(name, amount)
    local diag = NPCWorkSchedulerBridge.BattleGovernorDiagnostics or {}
    if diag.enabled == false then return end
    diag.counters = diag.counters or {}
    NPCWorkSchedulerBridge.BattleGovernorDiagnostics = diag
    name = tostring(name or "unknown")
    diag.counters[name] = (tonumber(diag.counters[name]) or 0) + (tonumber(amount) or 1)
end

function NPCWorkSchedulerBridge.GetBattleGovernorDiagnostics(reset)
    local diag = NPCWorkSchedulerBridge.BattleGovernorDiagnostics or {counters={}}
    local out = {
        enabled = diag.enabled ~= false,
        counters = {},
        loadState = NPCWorkSchedulerBridge.LoadState,
        config = NPCWorkSchedulerBridge.BattleGovernor
    }
    for k, v in pairs(diag.counters or {}) do
        out.counters[k] = v
    end
    if reset == true then
        diag.counters = {}
        NPCWorkSchedulerBridge.BattleGovernorDiagnostics = diag
    end
    return out
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
    cfg.sampleTicks = bws_number("AIWork_AdaptiveSampleTicks", cfg.sampleTicks or 3, 1, 600)
    cfg.lowFPS = bws_number("AIWork_LowFPS", cfg.lowFPS or 52, 5, 240)
    cfg.criticalFPS = bws_number("AIWork_CriticalFPS", cfg.criticalFPS or 55, 5, 240)
    cfg.panicFPS = bws_number("AIWork_PanicFPS", cfg.panicFPS or 47, 5, 240)
    cfg.highNPC = bws_number("AIWork_HighNPC", cfg.highNPC or 8, 1, 500)
    cfg.criticalNPC = bws_number("AIWork_CriticalNPC", cfg.criticalNPC or 14, 1, 1000)
    cfg.highZombies = bws_number("AIWork_HighZombies", cfg.highZombies or 60, 1, 2000)
    cfg.criticalZombies = bws_number("AIWork_CriticalZombies", cfg.criticalZombies or 110, 1, 3000)
    cfg.highBudgetPercent = bws_number("AIWork_HighBudgetPercent", cfg.highBudgetPercent or 35, 3, 100)
    cfg.criticalBudgetPercent = bws_number("AIWork_CriticalBudgetPercent", cfg.criticalBudgetPercent or 18, 3, 100)
    cfg.panicBudgetPercent = bws_number("AIWork_PanicBudgetPercent", cfg.panicBudgetPercent or 6, 3, 100)
    cfg.highIntervalMultiplier = bws_number("AIWork_HighIntervalMultiplier", cfg.highIntervalMultiplier or 4, 1, 60)
    cfg.criticalIntervalMultiplier = bws_number("AIWork_CriticalIntervalMultiplier", cfg.criticalIntervalMultiplier or 9, 1, 90)
    cfg.panicIntervalMultiplier = bws_number("AIWork_PanicIntervalMultiplier", cfg.panicIntervalMultiplier or 18, 1, 160)
    cfg.maxZombieInterval = bws_number("AIWork_MaxZombieInterval", cfg.maxZombieInterval or 90, 1, 600)
    cfg.debug = bws_bool("AIWork_DebugSummary", cfg.debug == true)
    cfg.logIntervalMs = bws_number("AIWork_DebugSummaryMs", cfg.logIntervalMs or 15000, 1000, 120000)

    local pq = NPCWorkSchedulerBridge.PathQueueConfig or {}
    pq.enabled = bws_bool("PathQueue_Enabled", pq.enabled ~= false)
    pq.maxSize = bws_number("PathQueue_MaxSize", pq.maxSize or 96, 8, 500)
    pq.perTick = bws_number("PathQueue_PerTick", pq.perTick or 2, 0, 30)
    pq.minAgeMs = bws_number("PathQueue_MinAgeMs", pq.minAgeMs or 75, 0, 5000)
    pq.maxAgeMs = bws_number("PathQueue_MaxAgeMs", pq.maxAgeMs or 4500, 250, 30000)
    pq.highWater = bws_number("PathQueue_HighWater", pq.highWater or 32, 4, 500)
    pq.criticalWater = bws_number("PathQueue_CriticalWater", pq.criticalWater or 64, pq.highWater or 32, 800)
    pq.stallRecoverPerTick = bws_number("PathQueue_StallRecoverPerTick", pq.stallRecoverPerTick or 1, 0, 10)
    pq.debug = bws_bool("PathQueue_Debug", pq.debug == true)
    NPCWorkSchedulerBridge.PathQueueConfig = pq

    local battle = NPCWorkSchedulerBridge.BattleGovernor or {}
    battle.enabled = bws_bool("BattleGovernor_Enabled", battle.enabled ~= false)
    battle.fullRadius = bws_number("BattleGovernor_FullRadius", battle.fullRadius or 28, 4, 200)
    battle.frontlineRadius = bws_number("BattleGovernor_FrontlineRadius", battle.frontlineRadius or 48, battle.fullRadius or 28, 320)
    battle.supportRadius = bws_number("BattleGovernor_SupportRadius", battle.supportRadius or 82, battle.frontlineRadius or 48, 600)
    battle.reserveRadius = bws_number("BattleGovernor_ReserveRadius", battle.reserveRadius or 132, battle.supportRadius or 82, 900)
    battle.closeTargetFullRadius = bws_number("BattleGovernor_CloseTargetFullRadius", battle.closeTargetFullRadius or 10, 2, 60)
    battle.frontlineIntervalHigh = bws_number("BattleGovernor_FrontlineIntervalHigh", battle.frontlineIntervalHigh or 2, 1, 90)
    battle.frontlineIntervalCritical = bws_number("BattleGovernor_FrontlineIntervalCritical", battle.frontlineIntervalCritical or 3, 1, 120)
    battle.supportIntervalLow = bws_number("BattleGovernor_SupportIntervalLow", battle.supportIntervalLow or 4, 1, 180)
    battle.supportIntervalHigh = bws_number("BattleGovernor_SupportIntervalHigh", battle.supportIntervalHigh or 10, 1, 240)
    battle.supportIntervalCritical = bws_number("BattleGovernor_SupportIntervalCritical", battle.supportIntervalCritical or 18, 1, 360)
    battle.reserveIntervalLow = bws_number("BattleGovernor_ReserveIntervalLow", battle.reserveIntervalLow or 10, 1, 360)
    battle.reserveIntervalHigh = bws_number("BattleGovernor_ReserveIntervalHigh", battle.reserveIntervalHigh or 30, 1, 600)
    battle.reserveIntervalCritical = bws_number("BattleGovernor_ReserveIntervalCritical", battle.reserveIntervalCritical or 55, 1, 900)
    battle.proxyIntervalLow = bws_number("BattleGovernor_ProxyIntervalLow", battle.proxyIntervalLow or 32, 1, 900)
    battle.proxyIntervalHigh = bws_number("BattleGovernor_ProxyIntervalHigh", battle.proxyIntervalHigh or 110, 1, 1200)
    battle.proxyIntervalCritical = bws_number("BattleGovernor_ProxyIntervalCritical", battle.proxyIntervalCritical or 170, 1, 1800)
    battle.combatScanSupportInterval = bws_number("BattleGovernor_CombatScanSupportInterval", battle.combatScanSupportInterval or 6, 1, 360)
    battle.combatScanReserveInterval = bws_number("BattleGovernor_CombatScanReserveInterval", battle.combatScanReserveInterval or 14, 1, 720)
    battle.combatScanProxyInterval = bws_number("BattleGovernor_CombatScanProxyInterval", battle.combatScanProxyInterval or 28, 1, 1200)
    battle.pressureMultiplierHigh = bws_number("BattleGovernor_PressureMultiplierHigh", battle.pressureMultiplierHigh or 1.45, 1, 8)
    battle.pressureMultiplierCritical = bws_number("BattleGovernor_PressureMultiplierCritical", battle.pressureMultiplierCritical or 1.95, 1, 12)
    NPCWorkSchedulerBridge.BattleGovernor = battle

    if not bws_bool("Perf_AllowHighPhysicalPopulation", true) then
        cfg.lowFPS = math.min(tonumber(cfg.lowFPS) or 52, 55)
        cfg.criticalFPS = math.min(tonumber(cfg.criticalFPS) or 45, math.max(5, (tonumber(cfg.lowFPS) or 52) - 4))
        cfg.panicFPS = math.min(tonumber(cfg.panicFPS) or 36, math.max(5, (tonumber(cfg.criticalFPS) or 45) - 6))
        cfg.highNPC = math.min(tonumber(cfg.highNPC) or 14, 14)
        cfg.criticalNPC = math.min(tonumber(cfg.criticalNPC) or 26, 26)
        cfg.highZombies = math.min(tonumber(cfg.highZombies) or 110, 110)
        cfg.criticalZombies = math.min(tonumber(cfg.criticalZombies) or 190, 190)
        cfg.highBudgetPercent = math.min(tonumber(cfg.highBudgetPercent) or 55, 55)
        cfg.criticalBudgetPercent = math.min(tonumber(cfg.criticalBudgetPercent) or 32, 32)
        cfg.panicBudgetPercent = math.min(tonumber(cfg.panicBudgetPercent) or 12, 12)
        cfg.highIntervalMultiplier = math.max(tonumber(cfg.highIntervalMultiplier) or 2, 2)
        cfg.criticalIntervalMultiplier = math.max(tonumber(cfg.criticalIntervalMultiplier) or 5, 5)
        cfg.panicIntervalMultiplier = math.max(tonumber(cfg.panicIntervalMultiplier) or 12, 12)
        cfg.maxZombieInterval = math.max(tonumber(cfg.maxZombieInterval) or 90, 90)
    end
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
    if zoom >= 1.35 and (fps <= 0 or fps < 70) then level = math.max(level, 1) end
    if zoom >= 1.70 and (fps <= 0 or fps < 60) then level = math.max(level, 2) end
    if zoom >= 2.10 and (fps <= 0 or fps < 50) then level = math.max(level, 3) end

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

    local recovering = NPCWorkSchedulerBridge.IsStallRecovering and NPCWorkSchedulerBridge.IsStallRecovering()
    if recovering then level = math.max(level, 3) end

    state.tick = tick
    state.fps = fps
    state.npc = npc
    state.zombies = zombies
    state.zoom = zoom
    state.level = level
    state.stallRecovery = recovering == true
    state.lastStallMs = tonumber(NPCWorkSchedulerBridge.LastStallMs) or 0
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

function NPCWorkSchedulerBridge.GetLoadLevel(force)
    local state = NPCWorkSchedulerBridge.GetLoadState(force == true)
    return tonumber(state and state.level) or 0, state
end

function NPCWorkSchedulerBridge.IsPanic(force)
    local level = NPCWorkSchedulerBridge.GetLoadLevel(force == true)
    return level >= 3
end

function NPCWorkSchedulerBridge.IsMapUnderLoad(force)
    local level, state = NPCWorkSchedulerBridge.GetLoadLevel(force == true)
    if level >= 2 then return true, level, state end
    local fps = tonumber(state and state.fps) or 60
    local zoom = tonumber(state and state.zoom) or 1
    return (fps > 0 and fps < 52) or zoom >= 1.35, level, state
end

function NPCWorkSchedulerBridge.IsStallRecovering()
    local untilTick = tonumber(NPCWorkSchedulerBridge.StallRecoveryUntilTick) or 0
    if untilTick <= 0 then return false end
    return (tonumber(NPCWorkSchedulerBridge.Tick) or 0) <= untilTick
end

function NPCWorkSchedulerBridge.GetLastStallMs()
    return tonumber(NPCWorkSchedulerBridge.LastStallMs) or 0
end


local function bws_adjustBudget(kind, budget)
    local cfg = NPCWorkSchedulerBridge.Adaptive or {}
    if not (cfg.enabled ~= false) then return budget end

    local state = NPCWorkSchedulerBridge.GetLoadState(false)
    local level = tonumber(state.level) or 0
    if level <= 0 then return budget end

    local protected = kind == "combat"
    local percent = level >= 3 and (tonumber(cfg.panicBudgetPercent) or 8) or (level >= 2 and (tonumber(cfg.criticalBudgetPercent) or 18) or (tonumber(cfg.highBudgetPercent) or 35))
    if protected then
        percent = math.max(percent, level >= 3 and 45 or (level >= 2 and 60 or 75))
    elseif kind == "path" then
        percent = math.min(percent, level >= 3 and 12 or (level >= 2 and 20 or 34))
    elseif kind == "zombiePath" then
        percent = math.max(percent, level >= 3 and 20 or (level >= 2 and 35 or 55))
    elseif kind == "spawn" then
        percent = math.min(percent, level >= 3 and 15 or (level >= 2 and 25 or 40))
    elseif kind == "sense" then
        percent = math.max(percent, level >= 3 and 12 or (level >= 2 and 22 or 35))
    elseif kind == "los" then
        percent = math.max(percent, level >= 3 and 12 or (level >= 2 and 22 or 35))
    elseif kind == "physical" then
        percent = math.max(percent, level >= 3 and 22 or (level >= 2 and 36 or 55))
    elseif kind == "marker" then
        -- Stage 306: dense world-map overlays can be as expensive as AI. Keep
        -- one marker job alive, but do not guarantee a large budget under panic.
        percent = math.min(percent, level >= 3 and 8 or (level >= 2 and 18 or 35))
    elseif kind == "ui" then
        percent = math.min(percent, level >= 3 and 14 or (level >= 2 and 24 or 40))
    elseif kind == "learning" then
        percent = math.min(percent, level >= 3 and 8 or (level >= 2 and 15 or 30))
    elseif kind == "world" or kind == "persistent" then
        percent = math.min(percent, level >= 3 and 12 or (level >= 2 and 22 or 40))
    elseif kind == "effects" then
        percent = math.min(percent, level >= 3 and 20 or (level >= 2 and 35 or 60))
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
    if brain and NPCWorkSchedulerBridge.IsCombatCritical and NPCWorkSchedulerBridge.IsCombatCritical(nil, brain) then
        -- Critical combat should stay responsive, but it must remain inside the
        -- per-tick budget. Player-controlled guards keep a smaller multiplier;
        -- autonomous firefights are allowed to fall back to proxy cadence.
        if bws_isPlayerControlledBrain and bws_isPlayerControlledBrain(brain) then
            mult = math.max(1, math.floor(mult / 2))
        else
            mult = math.max(1, math.floor(mult * (level >= 3 and 1.25 or 0.75)))
        end
    elseif brain and (brain.inBattle or brain.target or brain.targetId or brain.enemy or brain.currentThreat or brain.radioThreat or brain.lastKnownEnemyPosition) then
        mult = math.max(1, math.floor(mult * 0.75))
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
    NPCWorkSchedulerBridge.BudgetCache = {tick=tonumber(NPCWorkSchedulerBridge.Tick) or 0, values={}}
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


local function bws_pathQueue()
    NPCWorkSchedulerBridge.PathRequestQueue = NPCWorkSchedulerBridge.PathRequestQueue or {queue={}, ids={}, stats={}}
    local q = NPCWorkSchedulerBridge.PathRequestQueue
    q.queue = q.queue or {}
    q.ids = q.ids or {}
    q.stats = q.stats or {queued=0, updated=0, processed=0, expired=0, dropped=0, failed=0, denied=0}
    return q
end

local function bws_compactPathQueue(q)
    if not q or type(q.queue) ~= "table" then return end
    local old = q.queue
    local new = {}
    local ids = {}
    for i = 1, #old do
        local entry = old[i]
        if entry and entry.fn then
            new[#new + 1] = entry
            if entry.id then ids[entry.id] = #new end
        end
    end
    q.queue = new
    q.ids = ids
end

local function bws_perfRecord(name, amount)
    if NPCPerformanceTelemetryBridge and NPCPerformanceTelemetryBridge.Record then
        pcall(function() NPCPerformanceTelemetryBridge.Record(name, amount or 1) end)
    end
end

function NPCWorkSchedulerBridge.PendingPathRequestCount()
    local q = bws_pathQueue()
    local n = 0
    for _, entry in ipairs(q.queue) do
        if entry and entry.fn then n = n + 1 end
    end
    return n
end

function NPCWorkSchedulerBridge.GetPathQueuePressure()
    local cfg = NPCWorkSchedulerBridge.PathQueueConfig or {}
    local n = NPCWorkSchedulerBridge.PendingPathRequestCount()
    if n >= (tonumber(cfg.criticalWater) or 64) then return 2, n end
    if n >= (tonumber(cfg.highWater) or 32) then return 1, n end
    return 0, n
end

local function bws_prunePathQueue(now)
    local cfg = NPCWorkSchedulerBridge.PathQueueConfig or {}
    local q = bws_pathQueue()
    local maxAge = tonumber(cfg.maxAgeMs) or 4500
    local removed = false
    for i = #q.queue, 1, -1 do
        local entry = q.queue[i]
        if not entry or not entry.fn or now > (tonumber(entry.untilMs) or 0) or now - (tonumber(entry.queuedAt) or now) > maxAge then
            if entry and entry.id then q.ids[entry.id] = nil end
            q.queue[i] = false
            removed = true
            q.stats.expired = (tonumber(q.stats.expired) or 0) + 1
            bws_perfRecord("pathQueue.expired", 1)
        end
    end
    if removed then bws_compactPathQueue(q) end
end

local function bws_dropLowestPathRequestIfNeeded(score)
    local cfg = NPCWorkSchedulerBridge.PathQueueConfig or {}
    local q = bws_pathQueue()
    local maxSize = tonumber(cfg.maxSize) or 96
    if #q.queue < maxSize then return true end
    local lowestIndex = nil
    local lowestScore = math.huge
    for i, entry in ipairs(q.queue) do
        local s = tonumber(entry and entry.score) or 0
        if s < lowestScore then
            lowestScore = s
            lowestIndex = i
        end
    end
    if lowestIndex and lowestScore < (tonumber(score) or 0) then
        local old = q.queue[lowestIndex]
        q.queue[lowestIndex] = false
        if old and old.id then q.ids[old.id] = nil end
        bws_compactPathQueue(q)
        q.stats.dropped = (tonumber(q.stats.dropped) or 0) + 1
        bws_perfRecord("pathQueue.dropped", 1)
        return true
    end
    q.stats.denied = (tonumber(q.stats.denied) or 0) + 1
    bws_perfRecord("pathQueue.denied", 1)
    return false
end

function NPCWorkSchedulerBridge.EnqueuePathRequest(id, fn, reason, priority, score, ttlMs)
    local cfg = NPCWorkSchedulerBridge.PathQueueConfig or {}
    if cfg.enabled == false then return false end
    if type(fn) ~= "function" then return false end
    local q = bws_pathQueue()
    local now = bws_nowMs()
    bws_prunePathQueue(now)
    id = tostring(id or ("path:" .. tostring(now) .. ":" .. tostring(#q.queue + 1)))
    local existingIndex = q.ids[id]
    if existingIndex and q.queue[existingIndex] then
        local entry = q.queue[existingIndex]
        entry.fn = fn
        entry.reason = reason or entry.reason
        entry.priority = priority or entry.priority or "normal"
        entry.score = math.max(tonumber(entry.score) or 0, tonumber(score) or 0)
        entry.untilMs = now + (tonumber(ttlMs) or tonumber(cfg.maxAgeMs) or 4500)
        entry.updatedAt = now
        q.stats.updated = (tonumber(q.stats.updated) or 0) + 1
        bws_perfRecord("pathQueue.updated", 1)
        return true
    end
    if not bws_dropLowestPathRequestIfNeeded(score) then return false end
    local entry = {
        id = id,
        fn = fn,
        reason = reason or "deferred_path",
        priority = priority or "normal",
        score = tonumber(score) or 0,
        queuedAt = now,
        untilMs = now + (tonumber(ttlMs) or tonumber(cfg.maxAgeMs) or 4500)
    }
    table.insert(q.queue, entry)
    q.ids[id] = #q.queue
    q.stats.queued = (tonumber(q.stats.queued) or 0) + 1
    bws_perfRecord("pathQueue.queued", 1)
    return true
end

local function bws_reindexPathQueue()
    local q = bws_pathQueue()
    q.ids = {}
    bws_compactPathQueue(q)
    for i, entry in ipairs(q.queue) do
        if entry and entry.id then q.ids[entry.id] = i end
    end
end

function NPCWorkSchedulerBridge.ProcessPathRequestQueue()
    local cfg = NPCWorkSchedulerBridge.PathQueueConfig or {}
    if cfg.enabled == false then return 0 end
    local q = bws_pathQueue()
    if #q.queue == 0 then return 0 end
    local now = bws_nowMs()
    bws_prunePathQueue(now)
    if #q.queue == 0 then return 0 end

    table.sort(q.queue, function(a, b)
        local pa = tostring(a and a.priority or "normal") == "high" and 1000 or (tostring(a and a.priority or "normal") == "low" and -1000 or 0)
        local pb = tostring(b and b.priority or "normal") == "high" and 1000 or (tostring(b and b.priority or "normal") == "low" and -1000 or 0)
        return (pa + (tonumber(a and a.score) or 0)) > (pb + (tonumber(b and b.score) or 0))
    end)
    bws_reindexPathQueue()

    local budget = tonumber(cfg.perTick) or 2
    if NPCStreamingRuntimeBridge and NPCStreamingRuntimeBridge.AdjustBudget then
        budget = NPCStreamingRuntimeBridge.AdjustBudget("path", budget)
    end
    if NPCWorkSchedulerBridge.IsStallRecovering and NPCWorkSchedulerBridge.IsStallRecovering() then
        budget = math.min(budget, tonumber(cfg.stallRecoverPerTick) or 1)
    end
    if budget <= 0 then return 0 end

    local minAge = tonumber(cfg.minAgeMs) or 75
    local processed = 0
    local i = 1
    while i <= #q.queue and processed < budget do
        local entry = q.queue[i]
        if not entry or not entry.fn then
            q.queue[i] = false
            i = i + 1
        elseif now - (tonumber(entry.queuedAt) or now) < minAge then
            i = i + 1
        elseif NPCWorkSchedulerBridge.UseBudget("path", NPCWorkSchedulerBridge.GetBudget("path")) then
            q.queue[i] = false
            if entry.id then q.ids[entry.id] = nil end
            i = i + 1
            local ok, ret = pcall(entry.fn)
            if ok and ret ~= false then
                q.stats.processed = (tonumber(q.stats.processed) or 0) + 1
                bws_perfRecord("pathQueue.processed", 1)
            else
                q.stats.failed = (tonumber(q.stats.failed) or 0) + 1
                bws_perfRecord("pathQueue.failed", 1)
            end
            processed = processed + 1
        else
            break
        end
    end
    bws_reindexPathQueue()
    return processed
end

function NPCWorkSchedulerBridge.GetPathQueueDiagnostics(reset)
    local q = bws_pathQueue()
    local out = {pending = NPCWorkSchedulerBridge.PendingPathRequestCount(), stats = {}, config = NPCWorkSchedulerBridge.PathQueueConfig}
    for k, v in pairs(q.stats or {}) do out.stats[k] = v end
    if reset == true then q.stats = {queued=0, updated=0, processed=0, expired=0, dropped=0, failed=0, denied=0} end
    return out
end

function NPCWorkSchedulerBridge.OnTick()
    local nowMs = bws_nowMs()
    local lastMs = tonumber(NPCWorkSchedulerBridge.LastTickMs) or 0
    NPCWorkSchedulerBridge.LastTickMs = nowMs

    NPCWorkSchedulerBridge.Tick = (NPCWorkSchedulerBridge.Tick or 0) + 1

    if lastMs > 0 and nowMs > lastMs then
        local deltaMs = nowMs - lastMs
        if deltaMs >= 1500 then
            NPCWorkSchedulerBridge.LastStallMs = deltaMs
            NPCWorkSchedulerBridge.StallRecoveryUntilTick = math.max(
                tonumber(NPCWorkSchedulerBridge.StallRecoveryUntilTick) or 0,
                (NPCWorkSchedulerBridge.Tick or 0) + 360
            )
        end
    end

    NPCWorkSchedulerBridge.ResetCounters()
    bws_processTickJobs()
    NPCWorkSchedulerBridge.ProcessPathRequestQueue()
    if NPCAsyncSchedulerBridge and NPCAsyncSchedulerBridge.ProcessBudget then
        pcall(function() NPCAsyncSchedulerBridge.ProcessBudget() end)
    end
end

function NPCWorkSchedulerBridge.GetTick()
    return NPCWorkSchedulerBridge.Tick or 0
end

function NPCWorkSchedulerBridge.GetBudget(kind)
    kind = tostring(kind or "ai")
    local tick = tonumber(NPCWorkSchedulerBridge.Tick) or 0
    local cache = NPCWorkSchedulerBridge.BudgetCache
    if type(cache) ~= "table" or cache.tick ~= tick then
        cache = {tick=tick, values={}}
        NPCWorkSchedulerBridge.BudgetCache = cache
    end
    if cache.values and cache.values[kind] ~= nil then
        return cache.values[kind]
    end

    local budget = tonumber(NPCWorkSchedulerBridge.DefaultBudget[kind]) or 16
    if NPCStreamingRuntimeBridge and NPCStreamingRuntimeBridge.AdjustBudget then
        budget = NPCStreamingRuntimeBridge.AdjustBudget(kind, budget)
    end
    budget = bws_adjustBudget(kind, budget)
    budget = math.max(1, tonumber(budget) or 1)
    cache.values[kind] = budget
    return budget
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

local function bws_nearestPlayerDistance2(x, y)
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

    return best or 999999999999
end

local function bws_nearestPlayerDistance(x, y)
    local d2 = bws_nearestPlayerDistance2(x, y)
    return d2 < 999999999999 and math.sqrt(d2) or 999999
end

local function bws_currentTask(brain)
    if not (brain and type(brain.tasks) == "table") then return nil end
    return brain.tasks[1]
end

bws_isPlayerControlledBrain = function(brain)
    if type(brain) ~= "table" then return false end
    return brain.mercenaryHired == true
        or brain.hired == true
        or brain.isPlayerGuard == true
        or brain.playerOwned == true
        or brain.playerControlled == true
        or brain.master ~= nil
        or brain.follow == true
        or brain.followPlayer == true
end

function NPCWorkSchedulerBridge.IsPlayerControlledBrain(brain)
    return bws_isPlayerControlledBrain and bws_isPlayerControlledBrain(brain) == true
end

local function bws_characterDist2(a, b)
    if not (a and b and a.getX and a.getY and b.getX and b.getY) then return nil end
    local okA, ax, ay = pcall(function() return a:getX(), a:getY() end)
    local okB, bx, by = pcall(function() return b:getX(), b:getY() end)
    if not (okA and okB and ax and ay and bx and by) then return nil end
    local dx = (tonumber(ax) or 0) - (tonumber(bx) or 0)
    local dy = (tonumber(ay) or 0) - (tonumber(by) or 0)
    return dx * dx + dy * dy
end

local function bws_characterDist(a, b)
    local d2 = bws_characterDist2(a, b)
    return d2 and math.sqrt(d2) or nil
end

local function bws_battleAliveTarget(target)
    if not target then return false end
    if target.isAlive then
        local ok, alive = pcall(function() return target:isAlive() end)
        if ok and alive == false then return false end
    end
    if target.isDead then
        local ok, dead = pcall(function() return target:isDead() end)
        if ok and dead == true then return false end
    end
    return true
end

local function bws_closeLiveTargetDistance2(bandit)
    if not bandit then return nil end
    local target = nil
    if bandit.getTarget then
        local okTarget, retTarget = pcall(function() return bandit:getTarget() end)
        if okTarget and bws_battleAliveTarget(retTarget) then target = retTarget end
    end
    if not target and bandit.getAttackedBy then
        local okAttacker, retAttacker = pcall(function() return bandit:getAttackedBy() end)
        if okAttacker and bws_battleAliveTarget(retAttacker) then target = retAttacker end
    end
    if not target then return nil end
    return bws_characterDist2(bandit, target)
end

local function bws_crowdPressureLevel()
    local level = 0
    if NPCCrowdBudgetBridge and NPCCrowdBudgetBridge.State and NPCCrowdBudgetBridge.State.worst then
        level = math.max(level, tonumber(NPCCrowdBudgetBridge.State.worst.level) or 0)
    end
    return level
end

local function bws_isAutonomousBattleBrain(brain)
    if type(brain) ~= "table" then return false end
    if bws_isPlayerControlledBrain and bws_isPlayerControlledBrain(brain) then return false end
    if brain.blackMarket == true or brain.blackMarketNPC == true or brain.nonCombatant == true then return false end

    local task = bws_currentTask(brain)
    if task and (task.lock == true or task.source == "player" or task.manualOrder == true) then return false end

    if brain.inBattle == true or brain.virtualBattle == true or brain.battleId ~= nil or brain.enemyGroupId ~= nil then return true end
    if brain.worldDirector == true and (brain.target ~= nil or brain.targetId ~= nil or brain.enemy ~= nil or brain.currentThreat ~= nil or brain.radioThreat ~= nil or brain.lastKnownEnemyPosition ~= nil) then return true end
    return false
end

local function bws_battleInterval(role, level)
    local cfg = NPCWorkSchedulerBridge.BattleGovernor or {}
    level = tonumber(level) or 0
    role = tostring(role or "support")
    if role == "frontline" then
        if level >= 3 then return tonumber(cfg.frontlineIntervalCritical) or 3 end
        if level >= 2 then return tonumber(cfg.frontlineIntervalCritical) or 3 end
        if level >= 1 then return tonumber(cfg.frontlineIntervalHigh) or 2 end
        return 1
    elseif role == "support" then
        if level >= 3 then return tonumber(cfg.supportIntervalCritical) or 14 end
        if level >= 2 then return tonumber(cfg.supportIntervalHigh) or 8 end
        return tonumber(cfg.supportIntervalLow) or 4
    elseif role == "reserve" then
        if level >= 3 then return tonumber(cfg.reserveIntervalCritical) or 40 end
        if level >= 2 then return tonumber(cfg.reserveIntervalHigh) or 24 end
        return tonumber(cfg.reserveIntervalLow) or 10
    end
    if level >= 3 then return tonumber(cfg.proxyIntervalCritical) or 120 end
    if level >= 2 then return tonumber(cfg.proxyIntervalHigh) or 80 end
    return tonumber(cfg.proxyIntervalLow) or 32
end

local function bws_applyBattleRole(brain, role, interval, dist, level)
    if type(brain) ~= "table" then return end
    brain.ai = brain.ai or {}
    brain.ai.physicalBattleGovernorRole = role
    brain.ai.physicalBattleGovernorInterval = interval
    brain.ai.physicalBattleGovernorDist = dist
    brain.ai.physicalBattleGovernorLevel = level
    NPCWorkSchedulerBridge.IncBattleGovernorStat("role_" .. tostring(role or "unknown"))
end

function NPCWorkSchedulerBridge.GetBattleGovernorFrame(bandit, brain)
    local cfg = NPCWorkSchedulerBridge.BattleGovernor or {}
    if cfg.enabled == false then return false, "full", 1, 999999, 0 end
    if not (bandit and bandit.getX and bandit.getY and bws_isAutonomousBattleBrain(brain)) then
        return false, "full", 1, 999999, 0
    end

    local dist2 = bws_nearestPlayerDistance2(bandit:getX(), bandit:getY())
    local fullRadius = tonumber(cfg.fullRadius) or 28
    local frontlineRadius = tonumber(cfg.frontlineRadius) or 48
    local supportRadius = tonumber(cfg.supportRadius) or 82
    local reserveRadius = tonumber(cfg.reserveRadius) or 132
    local dist = nil

    if dist2 <= fullRadius * fullRadius then
        dist = math.sqrt(dist2)
        bws_applyBattleRole(brain, "full", 1, dist, 0)
        return false, "full", 1, dist, 0
    end

    local closeTargetDist2 = bws_closeLiveTargetDistance2(bandit)
    local closeTargetFullRadius = tonumber(cfg.closeTargetFullRadius) or 10
    if closeTargetDist2 and closeTargetDist2 <= closeTargetFullRadius * closeTargetFullRadius and dist2 <= frontlineRadius * frontlineRadius then
        dist = dist or math.sqrt(dist2)
        bws_applyBattleRole(brain, "frontline", 1, dist, 0)
        return false, "frontline", 1, dist, 0
    end
    dist = dist or math.sqrt(dist2)

    local state = NPCWorkSchedulerBridge.GetLoadState(false)
    local level = math.max(tonumber(state and state.level) or 0, bws_crowdPressureLevel())
    local role = "proxy"
    if dist <= frontlineRadius then
        role = "frontline"
    elseif dist <= supportRadius then
        role = "support"
    elseif dist <= reserveRadius then
        role = "reserve"
    end

    if level >= 2 and role == "frontline" and dist > math.max(fullRadius + 4, frontlineRadius * 0.82) then
        role = "support"
    elseif level >= 1 and role == "support" and dist > supportRadius * 0.86 then
        role = "reserve"
    elseif level >= 2 and role == "reserve" and dist > reserveRadius * 0.86 then
        role = "proxy"
    end

    local interval = bws_battleInterval(role, level)
    if level >= 2 and role ~= "frontline" then
        local mult = level >= 3 and (tonumber(cfg.pressureMultiplierCritical) or 1.60) or (tonumber(cfg.pressureMultiplierHigh) or 1.25)
        interval = math.max(interval, math.floor(interval * mult))
    end

    bws_applyBattleRole(brain, role, interval, dist, level)
    return true, role, interval, dist, level
end

function NPCWorkSchedulerBridge.AllowBattlePhysicalUpdate(id, brain, bandit, uTick)
    local governed, role, interval = NPCWorkSchedulerBridge.GetBattleGovernorFrame(bandit, brain)
    if not governed then
        NPCWorkSchedulerBridge.IncBattleGovernorStat("bypass_full")
        return true
    end

    id = id or (brain and (brain.id or brain.uid or brain.persistentId)) or "battle"
    interval = math.max(1, math.floor(tonumber(interval) or 1))
    local allowed = false
    if interval <= 1 then
        allowed = NPCWorkSchedulerBridge.UseBudget("physical", NPCWorkSchedulerBridge.GetBudget("physical"))
    else
        allowed = NPCWorkSchedulerBridge.CanRun("physical", "battle:" .. tostring(role) .. ":" .. tostring(id), interval, NPCWorkSchedulerBridge.GetBudget("physical"), uTick)
    end
    NPCWorkSchedulerBridge.IncBattleGovernorStat(allowed and "physical_allowed" or "physical_denied")
    NPCWorkSchedulerBridge.IncBattleGovernorStat((allowed and "physical_allowed_" or "physical_denied_") .. tostring(role or "unknown"))
    return allowed
end

function NPCWorkSchedulerBridge.GetBattleCombatScanInterval(brain)
    if not (brain and brain.ai and brain.ai.physicalBattleGovernorRole) then return nil end
    local cfg = NPCWorkSchedulerBridge.BattleGovernor or {}
    local role = tostring(brain.ai.physicalBattleGovernorRole or "")
    if role == "support" then return tonumber(cfg.combatScanSupportInterval) or 6 end
    if role == "reserve" then return tonumber(cfg.combatScanReserveInterval) or 14 end
    if role == "proxy" then return tonumber(cfg.combatScanProxyInterval) or 28 end
    return nil
end

local function bws_isCombatTask(task)
    if type(task) ~= "table" then return false end
    local action = tostring(task.action or "")
    return action == "Shoot"
        or action == "Aim"
        or action == "Hit"
        or action == "Shove"
        or action == "Reload"
        or action == "Bandage"
        or ((action == "Move" or action == "GoTo") and (task.combatMove == true or task.closeSlow == true or task.directorState == "KeepDistance" or task.directorState == "EmergencyDefense" or task.directorState == "MeleeFallback"))
end

local function bws_aliveTarget(target)
    if not target then return false end
    if target.isAlive then
        local ok, alive = pcall(function() return target:isAlive() end)
        if ok and alive == false then return false end
    end
    if target.isDead then
        local ok, dead = pcall(function() return target:isDead() end)
        if ok and dead == true then return false end
    end
    return true
end

local function bws_activeThreat(threat)
    if not threat then return false end
    if type(threat) ~= "table" then return true end

    local untilMs = tonumber(threat.untilMs or threat.expiresMs)
    if untilMs and untilMs > 0 then
        if bws_nowMs() > untilMs then return false end
        return threat.id ~= nil or threat.x ~= nil or threat.y ~= nil or threat.canSee == true
    end

    -- Radio / memory-only threats may keep x/y for a long time. They are useful
    -- for tactical planning, but must not promote every NPC into unbudgeted
    -- full-frame combat processing.
    return threat.canSee == true and (threat.id ~= nil or threat.x ~= nil or threat.y ~= nil)
end

function NPCWorkSchedulerBridge.IsCombatCritical(bandit, brain)
    if brain then
        if brain.inBattle or brain.virtualBattle or brain.battleId then return true end
        if brain.target or brain.targetId or brain.enemy or bws_activeThreat(brain.currentThreat) then return true end

        local fsm = brain.fsm
        if type(fsm) == "table" then
            if fsm.target or fsm.targetId or fsm.enemy or bws_activeThreat(fsm.currentThreat) then return true end
            local state = tostring(fsm.state or "")
            if state == "Attack" or state == "EmergencyDefense" or state == "MeleeFallback" or state == "KeepDistance" or state == "ReloadCover" or state == "Flee" then return true end
        end

        local task = bws_currentTask(brain)
        if bws_isCombatTask(task) then return true end
    end

    if bandit then
        local ok, target = pcall(function() return bandit.getTarget and bandit:getTarget() or nil end)
        if ok and bws_aliveTarget(target) then return true end
        ok, target = pcall(function() return bandit.getAttackedBy and bandit:getAttackedBy() or nil end)
        if ok and bws_aliveTarget(target) then return true end
    end

    return false
end

function NPCWorkSchedulerBridge.IsPhysicalCritical(bandit, brain)
    if NPCWorkSchedulerBridge.IsCombatCritical and NPCWorkSchedulerBridge.IsCombatCritical(bandit, brain) then return true end

    if brain then
        local born = tonumber(brain.born)
        if brain.worldDirector == true and born and getGameTime then
            local okAge, age = pcall(function() return getGameTime():getWorldAgeHours() end)
            if okAge and age then
                age = tonumber(age) or 0
                local wakeSeconds = bws_number("AILOD_SpawnWakeSeconds", 8, 0, 60)
                local wakeUntilAge = tonumber(brain.entryWakeUntilAge) or (born + wakeSeconds / 3600)
                if wakeSeconds > 0 and age <= wakeUntilAge then return true end
            end
        end
        if brain.mercenaryHired or brain.hired or brain.isPlayerGuard or brain.master or brain.follow then return true end
        if brain.blackMarket == true or brain.blackMarketNPC == true or brain.nonCombatant == true then return true end

        local task = bws_currentTask(brain)
        if task and task.lock == true then return true end
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
    local state = NPCWorkSchedulerBridge.GetLoadState(false)
    local level = tonumber(state.level) or 0
    if lod <= 0 then return bws_number("AILOD_PhysicalFullInterval", level >= 3 and 2 or 1, 1, 120) end
    if lod == 1 then return bws_number("AILOD_PhysicalHighInterval", level >= 3 and 12 or (level >= 2 and 8 or 3), 1, 180) end
    if lod == 2 then return bws_number("AILOD_PhysicalMediumInterval", level >= 3 and 48 or (level >= 2 and 24 or 8), 1, 360) end
    if lod == 3 then return bws_number("AILOD_PhysicalLowInterval", level >= 3 and 96 or (level >= 2 and 48 or 16), 1, 720) end
    return bws_number("AILOD_PhysicalProxyInterval", level >= 3 and 160 or (level >= 2 and 96 or 32), 1, 1200)
end

function NPCWorkSchedulerBridge.AllowCriticalPhysicalUpdate(id, brain, bandit, uTick)
    local state = NPCWorkSchedulerBridge.GetLoadState(false)
    local level = tonumber(state.level) or 0
    local zoom = tonumber(state.zoom) or 1
    if level <= 0 and zoom < 1.65 then return true end

    if brain and (brain.blackMarket == true or brain.blackMarketNPC == true or brain.nonCombatant == true) then
        return true
    end
    if bws_isPlayerControlledBrain and bws_isPlayerControlledBrain(brain) then
        return true
    end

    local interval = 1
    if level >= 3 or zoom >= 2.35 then
        interval = 9
    elseif level >= 2 or zoom >= 1.90 then
        interval = 6
    elseif level >= 1 or zoom >= 1.45 then
        interval = 3
    end

    if not bws_isPlayerControlledBrain(brain) then
        local combatCritical = NPCWorkSchedulerBridge.IsCombatCritical and NPCWorkSchedulerBridge.IsCombatCritical(bandit, brain)
        local lod, dist = NPCWorkSchedulerBridge.GetPhysicalLOD(bandit, brain)
        dist = tonumber(dist) or 999999
        if combatCritical then
            if level >= 3 and dist > 55 then
                interval = math.max(interval, 12)
            elseif level >= 2 and dist > 75 then
                interval = math.max(interval, 8)
            elseif level >= 1 and dist > 110 then
                interval = math.max(interval, 4)
            end
        else
            if level >= 3 and dist > 18 then
                interval = math.max(interval, 96)
            elseif level >= 2 and dist > 26 then
                interval = math.max(interval, 48)
            elseif level >= 1 and dist > 45 then
                interval = math.max(interval, 16)
            end
        end
    end
    if interval <= 1 then return NPCWorkSchedulerBridge.UseBudget("physical", NPCWorkSchedulerBridge.GetBudget("physical")) end
    return NPCWorkSchedulerBridge.CanRun("physical", id, interval, NPCWorkSchedulerBridge.GetBudget("physical"), uTick)
end

function NPCWorkSchedulerBridge.AllowPhysicalUpdate(id, brain, bandit, uTick)
    if NPCLegacySettingsBridge and not NPCLegacySettingsBridge.GetBool("AIWork_Enabled", true) then
        return true
    end
    if not bws_bool("AILOD_PhysicalFrameEnabled", true) then return true end
    if NPCWorkSchedulerBridge.BattleGovernor and NPCWorkSchedulerBridge.BattleGovernor.enabled ~= false and bws_isAutonomousBattleBrain(brain) then
        return NPCWorkSchedulerBridge.AllowBattlePhysicalUpdate(id, brain, bandit, uTick)
    end
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
        if brain.ai and tonumber(brain.ai.reactivePulseUntilMs or 0) > bws_nowMs() then
            interval = 1
        elseif brain.ai and not (bws_isPlayerControlledBrain and bws_isPlayerControlledBrain(brain)) and brain.ai.physicalBattleGovernorRole == "proxy" then
            interval = 12
        elseif brain.ai and not (bws_isPlayerControlledBrain and bws_isPlayerControlledBrain(brain)) and brain.ai.physicalBattleGovernorRole == "reserve" then
            interval = 8
        elseif brain.ai and not (bws_isPlayerControlledBrain and bws_isPlayerControlledBrain(brain)) and brain.ai.physicalBattleGovernorRole == "support" then
            interval = 4
        elseif NPCWorkSchedulerBridge.IsCombatCritical and NPCWorkSchedulerBridge.IsCombatCritical(nil, brain) then
            interval = (NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber("AIWork_CombatThinkInterval", 2, 1, 60)) or 2
        elseif brain.inBattle or brain.virtualBattle or brain.battleId then
            interval = (NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber("AIWork_CombatThinkInterval", 2, 1, 60)) or 2
        elseif brain.target or brain.targetId or brain.enemy or brain.currentThreat or brain.radioThreat or brain.lastKnownEnemyPosition then
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
                interval = (NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber("AIWork_IdleThinkInterval", 5, 1, 120)) or 5
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

    if brain and (brain.inBattle or (NPCWorkSchedulerBridge.IsCombatCritical and NPCWorkSchedulerBridge.IsCombatCritical(nil, brain))) then
        budget = NPCWorkSchedulerBridge.GetBudget("combat")
    end

    if NPCLegacySettingsBridge and not NPCLegacySettingsBridge.GetBool("AIWork_Enabled", true) then
        return true
    end

    if bws_isPlayerControlledBrain and bws_isPlayerControlledBrain(brain) then
        local order = type(brain.order) == "table" and brain.order or nil
        if order and (order.source == "player" or order.interrupt == true or brain.ai and brain.ai.forceManualOrderNow == true) then
            return true
        end
    end

    return NPCWorkSchedulerBridge.CanRun("ai", id, interval, budget, uTick)
end

function NPCWorkSchedulerBridge.AllowUtility(id, brain, uTick)
    local interval = 4
    if brain and (brain.inBattle or brain.target or brain.targetId or brain.currentThreat or brain.radioThreat) then
        interval = 2
    end
    if NPCStreamingRuntimeBridge and NPCStreamingRuntimeBridge.AdjustInterval then
        interval = NPCStreamingRuntimeBridge.AdjustInterval("utility", interval, brain)
    end
    interval = bws_adjustInterval("utility", interval, brain)
    return NPCWorkSchedulerBridge.CanRun("utility", id, interval, NPCWorkSchedulerBridge.GetBudget("utility"), uTick)
end

function NPCWorkSchedulerBridge.AllowZombieUpdate(id, uTick)
    local interval = (NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber("AIWork_ZombieCheckInterval", 8, 1, 240)) or 8
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

    if kind == "zombie" then
        local state = NPCWorkSchedulerBridge.GetLoadState(false)
        local level = tonumber(state and state.level) or 0
        local zoom = tonumber(state and state.zoom) or 1
        local minMs = level >= 3 and 1100 or (level >= 2 and 850 or (level >= 1 and 600 or 380))
        if zoom >= 1.90 then minMs = math.max(minMs, 850) end
        local qLevel, qPending = NPCWorkSchedulerBridge.GetPathQueuePressure()
        if qLevel >= 2 then minMs = math.max(minMs, 1450) elseif qLevel >= 1 then minMs = math.max(minMs, 1100) end
        if NPCCrowdBudgetBridge and NPCCrowdBudgetBridge.State and NPCCrowdBudgetBridge.State.worst then
            local cLevel = tonumber(NPCCrowdBudgetBridge.State.worst.level) or 0
            if cLevel >= 2 then minMs = math.max(minMs, 1500) elseif cLevel >= 1 then minMs = math.max(minMs, 950) end
        end
        local now = bws_nowMs()
        if NPCWorkSchedulerBridge.LastZombiePathAt and now - NPCWorkSchedulerBridge.LastZombiePathAt < minMs then
            bws_perfRecord("pathRequest.zombie.cooldown", 1)
            return false
        end
        if not NPCWorkSchedulerBridge.UseBudget(budgetKind, NPCWorkSchedulerBridge.GetBudget(budgetKind)) then
            bws_perfRecord("pathRequest.zombie.budgetDenied", 1)
            return false
        end
        NPCWorkSchedulerBridge.LastZombiePathAt = now
        bws_perfRecord("pathRequest.zombie.allowed", 1)
        return true
    end

    if kind == "path" then
        local state = NPCWorkSchedulerBridge.GetLoadState(false)
        local level = tonumber(state and state.level) or 0
        local zoom = tonumber(state and state.zoom) or 1
        local minMs = level >= 3 and 180 or (level >= 2 and 120 or (level >= 1 and 80 or 35))
        if zoom >= 1.70 then minMs = math.max(minMs, 120) end
        if zoom >= 2.10 then minMs = math.max(minMs, 180) end
        local qLevel, qPending = NPCWorkSchedulerBridge.GetPathQueuePressure()
        if qLevel >= 2 then minMs = math.max(minMs, 300) elseif qLevel >= 1 then minMs = math.max(minMs, 220) end
        if NPCCrowdBudgetBridge and NPCCrowdBudgetBridge.State and NPCCrowdBudgetBridge.State.worst then
            local cLevel = tonumber(NPCCrowdBudgetBridge.State.worst.level) or 0
            if cLevel >= 2 then minMs = math.max(minMs, 360) elseif cLevel >= 1 then minMs = math.max(minMs, 220) end
        end
        local now = bws_nowMs()
        if NPCWorkSchedulerBridge.LastPathAt and now - NPCWorkSchedulerBridge.LastPathAt < minMs then
            bws_perfRecord("pathRequest.npc.cooldown", 1)
            return false
        end
        if not NPCWorkSchedulerBridge.UseBudget(budgetKind, NPCWorkSchedulerBridge.GetBudget(budgetKind)) then
            bws_perfRecord("pathRequest.npc.budgetDenied", 1)
            return false
        end
        NPCWorkSchedulerBridge.LastPathAt = now
        bws_perfRecord("pathRequest.npc.allowed", 1)
        return true
    end

    return NPCWorkSchedulerBridge.UseBudget(budgetKind, NPCWorkSchedulerBridge.GetBudget(budgetKind))
end

function NPCWorkSchedulerBridge.AllowSense(id, brain, uTick)
    if NPCLegacySettingsBridge and not NPCLegacySettingsBridge.GetBool("AIWork_Enabled", true) then
        return true
    end

    local interval = 1
    if brain and not (brain.inBattle or brain.target or brain.targetId or brain.enemy or brain.currentThreat or brain.radioThreat or brain.lastKnownEnemyPosition) then
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

function NPCWorkSchedulerBridge.AllowLearning(id, interval, uTick)
    if NPCLegacySettingsBridge and not NPCLegacySettingsBridge.GetBool("AIWork_Enabled", true) then
        return true
    end
    interval = tonumber(interval) or 8
    interval = bws_adjustInterval("learning", math.max(1, interval), nil)
    return NPCWorkSchedulerBridge.CanRun("learning", id or "learning", interval, NPCWorkSchedulerBridge.GetBudget("learning"), uTick)
end

function NPCWorkSchedulerBridge.GetSensingResultLimit(kind, fallback)
    local level, state = NPCWorkSchedulerBridge.GetLoadLevel(false)
    fallback = tonumber(fallback) or 96
    if level >= 3 then return math.max(12, math.floor(fallback * 0.30)) end
    if level >= 2 then return math.max(20, math.floor(fallback * 0.45)) end
    if level >= 1 then return math.max(32, math.floor(fallback * 0.65)) end
    return fallback
end

function NPCWorkSchedulerBridge.AllowCombatScan(id, brain, uTick, bandit)
    if NPCLegacySettingsBridge and not NPCLegacySettingsBridge.GetBool("AIWork_Enabled", true) then
        return true
    end

    local critical = NPCWorkSchedulerBridge.IsPhysicalCritical(bandit, brain)
    local controlled = bws_isPlayerControlledBrain(brain)

    local state = NPCWorkSchedulerBridge.GetLoadState(false)
    local level = tonumber(state.level) or 0
    local interval = 1

    if level >= 3 then
        interval = controlled and 4 or (critical and 10 or 22)
    elseif level >= 2 then
        interval = controlled and 3 or (critical and 7 or 14)
    elseif level >= 1 then
        interval = controlled and 2 or (critical and 4 or 8)
    end

    if not controlled and bandit and bandit.getX and level >= 2 then
        local dist = bws_nearestPlayerDistance(bandit:getX(), bandit:getY())
        if level >= 3 and dist > 42 then
            interval = math.max(interval, 10)
        elseif dist > 70 then
            interval = math.max(interval, 6)
        end
    end

    if not controlled and NPCWorkSchedulerBridge.GetBattleGovernorFrame then
        local governed = false
        local okBattle, role, battleInterval = false, nil, nil
        okBattle, governed, role = pcall(function()
            local g, r = NPCWorkSchedulerBridge.GetBattleGovernorFrame(bandit, brain)
            return g, r
        end)
        if okBattle and governed then
            battleInterval = NPCWorkSchedulerBridge.GetBattleCombatScanInterval(brain)
            if battleInterval then interval = math.max(interval, tonumber(battleInterval) or interval) end
        end
    end

    local allowed = false
    if interval <= 1 then
        allowed = NPCWorkSchedulerBridge.UseBudget("combat", NPCWorkSchedulerBridge.GetBudget("combat"))
    else
        allowed = NPCWorkSchedulerBridge.CanRun("combat", id, interval, NPCWorkSchedulerBridge.GetBudget("combat"), uTick)
    end
    NPCWorkSchedulerBridge.IncBattleGovernorStat(allowed and "combat_scan_allowed" or "combat_scan_denied")
    return allowed
end

function NPCWorkSchedulerBridge.AllowVisualUpdate(id, brain, uTick)
    local state = NPCWorkSchedulerBridge.GetLoadState(false)
    local level = tonumber(state.level) or 0
    local interval = level >= 3 and 240 or (level >= 2 and 120 or (level >= 1 and 48 or 18))
    return NPCWorkSchedulerBridge.ShouldRun(id, interval, uTick)
end

function NPCWorkSchedulerBridge.AllowTorchUpdate(id, brain, uTick)
    local state = NPCWorkSchedulerBridge.GetLoadState(false)
    local level = tonumber(state.level) or 0
    local interval = level >= 3 and 480 or (level >= 2 and 240 or (level >= 1 and 96 or 36))
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
