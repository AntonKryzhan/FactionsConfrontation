-- NPCAsyncSchedulerBridge.lua
-- Neutral shared backend for async NPC scheduler/budget queues.

NPCAsyncSchedulerBridge = NPCAsyncSchedulerBridge or {}

require "NPCCore/NPCLegacyContractBridge"

NPCAsyncSchedulerBridge.VERSION = "2026-05-10-v8-async-budget-scheduler-1"

NPCAsyncSchedulerBridge.Config = NPCAsyncSchedulerBridge.Config or {
    enabled = true,
    maxQueue = 96,
    combatTTL = 10,
    recoveryTTL = 14,
    utilityTTL = 12,
    visualTTL = 18,
    lowCombatPerTick = 3,
    highCombatPerTick = 2,
    criticalCombatPerTick = 1,
    panicCombatPerTick = 1,
    lowRecoveryPerTick = 2,
    highRecoveryPerTick = 1,
    criticalRecoveryPerTick = 1,
    panicRecoveryPerTick = 1,
    lowUtilityPerTick = 2,
    highUtilityPerTick = 1,
    criticalUtilityPerTick = 1,
    panicUtilityPerTick = 0,
    lowVisualPerTick = 3,
    highVisualPerTick = 2,
    criticalVisualPerTick = 1,
    panicVisualPerTick = 0,
    deferCombatLevel = 1,
    deferRecoveryLevel = 1,
    debug = false,
    debugIntervalMs = 15000
}

NPCAsyncSchedulerBridge.Tick = NPCAsyncSchedulerBridge.Tick or 0
NPCAsyncSchedulerBridge.Seq = NPCAsyncSchedulerBridge.Seq or 0
NPCAsyncSchedulerBridge.Queues = NPCAsyncSchedulerBridge.Queues or {}
NPCAsyncSchedulerBridge.Stats = NPCAsyncSchedulerBridge.Stats or {}
NPCAsyncSchedulerBridge.LastLogMs = NPCAsyncSchedulerBridge.LastLogMs or 0

local NPC_ASYNC_LEGACY_KEYS = {
    liveFlag = NPCLegacyContractBridge.Keys.FLAG
}
local NPC_ASYNC_LOG_PREFIX = "[NPCAsync]"

local function bas_nowMs()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then
        local ok, hours = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok and hours then return math.floor((tonumber(hours) or 0) * 3600000) end
    end
    return 0
end

local function bas_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        return NPCLegacySettingsBridge.GetBool(name, defaultValue == true)
    end
    return defaultValue == true
end

local function bas_number(name, defaultValue, minValue, maxValue)
    local value = tonumber(defaultValue) or 0
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        value = NPCLegacySettingsBridge.GetNumber(name, value, minValue, maxValue)
    end
    if minValue ~= nil and value < minValue then value = minValue end
    if maxValue ~= nil and value > maxValue then value = maxValue end
    return value
end

local function bas_applySettings()
    local cfg = NPCAsyncSchedulerBridge.Config
    cfg.enabled = bas_bool("AIAsync_Enabled", cfg.enabled ~= false)
    cfg.maxQueue = bas_number("AIAsync_MaxQueue", cfg.maxQueue or 96, 16, 512)
    cfg.combatTTL = bas_number("AIAsync_CombatTTL", cfg.combatTTL or 10, 1, 120)
    cfg.recoveryTTL = bas_number("AIAsync_RecoveryTTL", cfg.recoveryTTL or 14, 1, 180)
    cfg.utilityTTL = bas_number("AIAsync_UtilityTTL", cfg.utilityTTL or 12, 1, 120)
    cfg.visualTTL = bas_number("AIAsync_VisualTTL", cfg.visualTTL or 18, 1, 240)
    cfg.deferCombatLevel = bas_number("AIAsync_DeferCombatLevel", cfg.deferCombatLevel or 1, 0, 3)
    cfg.deferRecoveryLevel = bas_number("AIAsync_DeferRecoveryLevel", cfg.deferRecoveryLevel or 1, 0, 3)
    cfg.debug = bas_bool("AIAsync_Debug", cfg.debug == true)
    cfg.debugIntervalMs = bas_number("AIAsync_DebugIntervalMs", cfg.debugIntervalMs or 15000, 1000, 120000)
end

local function bas_getTick()
    if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.GetTick then
        local ok, tick = pcall(function() return NPCWorkSchedulerBridge.GetTick() end)
        if ok and tick then return tonumber(tick) or 0 end
    end
    return NPCAsyncSchedulerBridge.Tick or 0
end

local function bas_getLoadLevel()
    if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.GetLoadState then
        local ok, state = pcall(function() return NPCWorkSchedulerBridge.GetLoadState(false) end)
        if ok and state then return tonumber(state.level) or 0, tonumber(state.zoom) or 1, tonumber(state.fps) or 60 end
    end
    return 0, 1, 60
end

local function bas_getQueue(kind)
    kind = tostring(kind or "generic")
    local q = NPCAsyncSchedulerBridge.Queues[kind]
    if not q then
        q = {items={}, first=1, last=0, pending={}}
        NPCAsyncSchedulerBridge.Queues[kind] = q
    end
    return q
end

local function bas_queueSize(q)
    return math.max(0, (tonumber(q.last) or 0) - (tonumber(q.first) or 1) + 1)
end

local function bas_stat(name, delta)
    NPCAsyncSchedulerBridge.Stats[name] = (tonumber(NPCAsyncSchedulerBridge.Stats[name]) or 0) + (tonumber(delta) or 1)
end

local function bas_budgetFor(kind)
    local cfg = NPCAsyncSchedulerBridge.Config
    local level = bas_getLoadLevel()
    if kind == "combat" then
        if level >= 3 then return tonumber(cfg.panicCombatPerTick) or 1 end
        if level >= 2 then return tonumber(cfg.criticalCombatPerTick) or 1 end
        if level >= 1 then return tonumber(cfg.highCombatPerTick) or 2 end
        return tonumber(cfg.lowCombatPerTick) or 3
    elseif kind == "recovery" then
        if level >= 3 then return tonumber(cfg.panicRecoveryPerTick) or 1 end
        if level >= 2 then return tonumber(cfg.criticalRecoveryPerTick) or 1 end
        if level >= 1 then return tonumber(cfg.highRecoveryPerTick) or 1 end
        return tonumber(cfg.lowRecoveryPerTick) or 2
    elseif kind == "utility" then
        if level >= 3 then return tonumber(cfg.panicUtilityPerTick) or 0 end
        if level >= 2 then return tonumber(cfg.criticalUtilityPerTick) or 1 end
        if level >= 1 then return tonumber(cfg.highUtilityPerTick) or 1 end
        return tonumber(cfg.lowUtilityPerTick) or 2
    elseif kind == "visual" then
        if level >= 3 then return tonumber(cfg.panicVisualPerTick) or 0 end
        if level >= 2 then return tonumber(cfg.criticalVisualPerTick) or 1 end
        if level >= 1 then return tonumber(cfg.highVisualPerTick) or 2 end
        return tonumber(cfg.lowVisualPerTick) or 3
    end
    return 1
end

local function bas_useGlobalBudget(kind)
    if not NPCWorkSchedulerBridge or not NPCWorkSchedulerBridge.UseBudget then return true end
    local budgetKind = kind == "recovery" and "path" or kind
    if budgetKind ~= "combat" and budgetKind ~= "path" and budgetKind ~= "utility" and budgetKind ~= "visual" then
        return true
    end
    local budget = nil
    if NPCWorkSchedulerBridge.GetBudget then
        local ok, ret = pcall(function() return NPCWorkSchedulerBridge.GetBudget(budgetKind) end)
        if ok then budget = ret end
    end
    local ok, ret = pcall(function() return NPCWorkSchedulerBridge.UseBudget(budgetKind, budget) end)
    return (not ok) or ret ~= false
end

local function bas_defaultValidate(task)
    if task.validate then
        local ok, ret = pcall(task.validate)
        return ok and ret ~= false
    end
    return true
end

local function bas_enqueue(kind, key, ttlTicks, runFn, applyFn, validateFn, flags)
    local cfg = NPCAsyncSchedulerBridge.Config
    if cfg.enabled == false then return false end
    if type(runFn) ~= "function" then return false end

    kind = tostring(kind or "generic")
    key = tostring(key or (kind .. ":" .. tostring(bas_nowMs())))
    local q = bas_getQueue(kind)
    local pending = q.pending[key]
    local tick = bas_getTick()

    if pending then
        pending.expires = math.max(tonumber(pending.expires) or tick, tick + (tonumber(ttlTicks) or 8))
        pending.run = runFn
        pending.apply = applyFn
        pending.validate = validateFn
        pending.flags = flags or pending.flags
        bas_stat("deduped")
        return true
    end

    if bas_queueSize(q) >= (tonumber(cfg.maxQueue) or 96) then
        bas_stat("dropped_full")
        return false
    end

    NPCAsyncSchedulerBridge.Seq = (NPCAsyncSchedulerBridge.Seq or 0) + 1
    local task = {
        seq = NPCAsyncSchedulerBridge.Seq,
        kind = kind,
        key = key,
        created = tick,
        expires = tick + (tonumber(ttlTicks) or 8),
        run = runFn,
        apply = applyFn,
        validate = validateFn,
        flags = flags
    }

    q.last = (q.last or 0) + 1
    q.items[q.last] = task
    q.pending[key] = task
    bas_stat("queued")
    return true
end

local function bas_validateNPC(bandit, brain, id)
    if not bandit then return false end
    local okDead, dead = pcall(function() return bandit:isDead() end)
    if okDead and dead then return false end
    local okAlive, alive = pcall(function() return bandit:isAlive() end)
    if okAlive and alive == false then return false end
    local okNPC, isNPC = pcall(function() return bandit:getVariableBoolean(NPC_ASYNC_LEGACY_KEYS.liveFlag) end)
    if okNPC and isNPC == false then return false end
    if NPCBrainData and NPCBrainData.Get then
        local okBrain, currentBrain = pcall(function() return NPCBrainData.Get(bandit) end)
        if okBrain and currentBrain and brain and currentBrain ~= brain then
            local currentId = currentBrain.id or currentBrain.uid or currentBrain.persistentId
            local oldId = brain.id or brain.uid or brain.persistentId or id
            if tostring(currentId) ~= tostring(oldId) then return false end
        end
    end
    return true
end

function NPCAsyncSchedulerBridge.ApplyNPCTasks(bandit, brain, tasks, reason)
    if type(tasks) ~= "table" or #tasks == 0 then return false end
    if not bas_validateNPC(bandit, brain, nil) then return false end
    if NPCMovementStabilityBridge and NPCMovementStabilityBridge.IsCombatLocked and NPCMovementStabilityBridge.IsCombatLocked(bandit) then return false end
    if NPCEntity and NPCEntity.HasActionTask then
        local okAction, hasAction = pcall(function() return NPCEntity.HasActionTask(bandit) end)
        if okAction and hasAction then return false end
    end

    local targetBrain = brain
    if NPCBrainData and NPCBrainData.Get then
        local okBrain, currentBrain = pcall(function() return NPCBrainData.Get(bandit) end)
        if okBrain and currentBrain then targetBrain = currentBrain end
    end
    if not targetBrain then return false end
    targetBrain.tasks = targetBrain.tasks or {}
    if #targetBrain.tasks > 0 then return false end

    if NPCUtilityAIBridge and NPCUtilityAIBridge.OnTasksQueued then
        pcall(function() NPCUtilityAIBridge.OnTasksQueued(bandit, targetBrain, tasks) end)
    end
    for i = 1, #tasks do
        local task = tasks[i]
        if task and task.action then table.insert(targetBrain.tasks, task) end
    end
    bas_stat("applied")
    return true
end

NPCAsyncSchedulerBridge[NPCLegacyContractBridge.Member("applyTasks")] = function(bandit, brain, tasks, reason)
    return NPCAsyncSchedulerBridge.ApplyNPCTasks(bandit, brain, tasks, reason)
end

function NPCAsyncSchedulerBridge.EnqueueCombatScan(bandit, brain, id, uTick, runFn)
    if NPCAsyncSchedulerBridge.Config.enabled == false then return false end
    local level = bas_getLoadLevel()
    if level < (tonumber(NPCAsyncSchedulerBridge.Config.deferCombatLevel) or 1) then return false end
    if not bas_validateNPC(bandit, brain, id) then return false end

    local key = "combat:" .. tostring(id or (brain and (brain.id or brain.uid or brain.persistentId)) or bandit)
    local ttl = tonumber(NPCAsyncSchedulerBridge.Config.combatTTL) or 10
    return bas_enqueue("combat", key, ttl,
        function()
            if brain then
                brain.ai = brain.ai or {}
                brain.ai.asyncCombatScanActive = true
            end
            local ok, ret = pcall(runFn)
            if brain and brain.ai then brain.ai.asyncCombatScanActive = false end
            if ok then return ret end
            return nil, ret
        end,
        function(tasks)
            return NPCAsyncSchedulerBridge.ApplyNPCTasks(bandit, brain, tasks, "async_combat")
        end,
        function()
            return bas_validateNPC(bandit, brain, id)
        end,
        {id=id, uTick=uTick})
end

function NPCAsyncSchedulerBridge.EnqueuePathRecovery(zombie, brain, task, runFn, applyFn)
    if NPCAsyncSchedulerBridge.Config.enabled == false then return false end
    local level = bas_getLoadLevel()
    if level < (tonumber(NPCAsyncSchedulerBridge.Config.deferRecoveryLevel) or 1) then return false end
    if not zombie or not task then return false end

    local id = nil
    if NPCUtils and NPCUtils.GetZombieID then
        local ok, ret = pcall(function() return NPCUtils.GetZombieID(zombie) end)
        if ok then id = ret end
    end
    local key = "recovery:" .. tostring(id or zombie)
    local ttl = tonumber(NPCAsyncSchedulerBridge.Config.recoveryTTL) or 14
    return bas_enqueue("recovery", key, ttl, runFn, applyFn,
        function()
            if not bas_validateNPC(zombie, brain, id) then return false end
            if NPCEntity and NPCEntity.GetTask then
                local okTask, currentTask = pcall(function() return NPCEntity.GetTask(zombie) end)
                if okTask and currentTask and currentTask ~= task then return false end
            end
            return true
        end,
        {id=id})
end

function NPCAsyncSchedulerBridge.Enqueue(kind, key, ttlTicks, runFn, applyFn, validateFn)
    return bas_enqueue(kind, key, ttlTicks, runFn, applyFn, validateFn, nil)
end

local function bas_processOne(kind)
    local q = bas_getQueue(kind)
    while q.first <= q.last do
        local task = q.items[q.first]
        q.items[q.first] = nil
        q.first = q.first + 1

        if task then
            if q.pending[task.key] == task then q.pending[task.key] = nil end
            local tick = bas_getTick()
            if tick > (tonumber(task.expires) or tick) then
                bas_stat("expired")
            elseif bas_defaultValidate(task) then
                if bas_useGlobalBudget(kind) then
                    local okRun, result, extra = pcall(task.run)
                    if okRun then
                        if task.apply then
                            local okApply, applied = pcall(task.apply, result, extra)
                            if not okApply then bas_stat("apply_error") end
                            if applied then bas_stat("processed") else bas_stat("skipped_apply") end
                        else
                            bas_stat("processed")
                        end
                    else
                        bas_stat("run_error")
                        if NPCAsyncSchedulerBridge.Config.debug then print(NPC_ASYNC_LOG_PREFIX .. " run error " .. tostring(kind) .. ": " .. tostring(result)) end
                    end
                    return true
                else
                    -- Global budget is exhausted. Put this task back at the end so the queue
                    -- remains bounded and no single frame takes all expensive work.
                    if bas_queueSize(q) < (tonumber(NPCAsyncSchedulerBridge.Config.maxQueue) or 96) then
                        q.last = q.last + 1
                        q.items[q.last] = task
                        q.pending[task.key] = task
                    else
                        bas_stat("dropped_budget")
                    end
                    return false
                end
            else
                bas_stat("invalid")
            end
        end
    end

    if q.first > q.last then
        q.first = 1
        q.last = 0
    end
    return false
end

function NPCAsyncSchedulerBridge.ProcessKind(kind, budget)
    budget = tonumber(budget) or bas_budgetFor(kind)
    if budget <= 0 then return 0 end
    local done = 0
    while done < budget do
        if not bas_processOne(kind) then break end
        done = done + 1
    end
    return done
end

function NPCAsyncSchedulerBridge.ProcessBudget()
    if NPCAsyncSchedulerBridge.Config.enabled == false then return end
    bas_applySettings()
    NPCAsyncSchedulerBridge.ProcessKind("combat", bas_budgetFor("combat"))
    NPCAsyncSchedulerBridge.ProcessKind("recovery", bas_budgetFor("recovery"))
    NPCAsyncSchedulerBridge.ProcessKind("utility", bas_budgetFor("utility"))
    NPCAsyncSchedulerBridge.ProcessKind("visual", bas_budgetFor("visual"))

    if NPCAsyncSchedulerBridge.Config.debug then
        local now = bas_nowMs()
        if now - (NPCAsyncSchedulerBridge.LastLogMs or 0) >= (tonumber(NPCAsyncSchedulerBridge.Config.debugIntervalMs) or 15000) then
            NPCAsyncSchedulerBridge.LastLogMs = now
            local cq = bas_queueSize(bas_getQueue("combat"))
            local rq = bas_queueSize(bas_getQueue("recovery"))
            print(NPC_ASYNC_LOG_PREFIX .. " combatQ=" .. tostring(cq) .. " recoveryQ=" .. tostring(rq) .. " queued=" .. tostring(NPCAsyncSchedulerBridge.Stats.queued or 0) .. " processed=" .. tostring(NPCAsyncSchedulerBridge.Stats.processed or 0) .. " expired=" .. tostring(NPCAsyncSchedulerBridge.Stats.expired or 0) .. " dropped=" .. tostring((NPCAsyncSchedulerBridge.Stats.dropped_full or 0) + (NPCAsyncSchedulerBridge.Stats.dropped_budget or 0)))
        end
    end
end

function NPCAsyncSchedulerBridge.OnTick()
    NPCAsyncSchedulerBridge.Tick = (NPCAsyncSchedulerBridge.Tick or 0) + 1
    NPCAsyncSchedulerBridge.ProcessBudget()
end

bas_applySettings()

