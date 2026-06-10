-- NPCRegressionGuardBridge.lua
-- Stage 372: regression/performance guard for the tactical AI stack.
--
-- This bridge is intentionally conservative. It does not add new orders,
-- network commands, save roots, damage, or Java hooks. It only provides
-- bounded circuit breakers, state hysteresis and task clamps so the tactical
-- layers added in Stage 363-371 cannot thrash the B41 movement/state machine.

NPCRegressionGuardBridge = NPCRegressionGuardBridge or {}
NPCRegressionGuardBridge.VERSION = "2026-06-01-stage378-locomotion-liveness-router-unblock-1"

NPCRegressionGuardBridge.Config = NPCRegressionGuardBridge.Config or {
    enabled = true,
    debug = false,
    layerErrorMuteMs = 18000,
    maxLayerErrors = 3,
    layerCooldownMs = 350,
    advisoryDecisionHoldMs = 950,
    tacticalDecisionHoldMs = 1450,
    memoryDecisionHoldMs = 2200,
    postCombatDecisionHoldMs = 2600,
    loopWindowMs = 7600,
    loopMuteMs = 2800,
    loopSwitchLimit = 4,
    taskClampEnabled = true,
    minTacticalPathThrottleMs = 1150,
    minTacticalSameTargetThrottleMs = 3600,
    minIndoorPathThrottleMs = 1450,
    minIndoorSameTargetThrottleMs = 4600,
    emergencyPathThrottleMs = 420,
    emergencySameTargetThrottleMs = 900,
    maxTacticalArriveDist = 2.25,
    minTacticalArriveDist = 0.95
}

local function brg_nowMs()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then
        local ok, hours = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok and hours then return math.floor((tonumber(hours) or 0) * 3600000) end
    end
    return 0
end

local function brg_id(brain)
    if type(brain) ~= "table" then return "nogroup" end
    return tostring(brain.persistentId or brain.uid or brain.id or brain.npcId or brain.characterId or "brain")
end

local function brg_stateName(state)
    return tostring(state or "")
end

local function brg_isPlayerControlled(brain)
    if type(brain) ~= "table" then return false end
    if brain.master ~= nil or brain.mercenaryHired == true or brain.hired == true or brain.isPlayerGuard == true then return true end
    local order = brain.order or brain.directorOrder
    if type(order) == "table" then
        local name = order.name or order.action or order.type or order.mode
        return name ~= nil and tostring(name) ~= "" and tostring(name):lower() ~= "free"
    end
    return order ~= nil and tostring(order) ~= "" and tostring(order):lower() ~= "free"
end

local function brg_isEmergency(state)
    local s = brg_stateName(state)
    return s == "Dead"
        or s == "Disabled"
        or s == "EmergencyDefense"
        or s == "MeleeFallback"
        or s == "Flee"
        or s == "Attack"
        or s == "HealSelf"
        or s == "ReloadWeapon"
        or s == "ReloadCover"
        or s == "RecoverPath"
end

local function brg_isTactical(state)
    local s = brg_stateName(state)
    return s == "SearchEnemy"
        or s == "FlankEnemy"
        or s == "TacticalCover"
        or s == "SuppressEnemy"
        or s == "HoldAngle"
        or s == "BoundForward"
        or s == "InvestigateNoise"
        or s == "LookAround"
        or s == "Regroup"
end

local function brg_layerState(brain, layer)
    if type(brain) ~= "table" then return nil end
    brain._regressionGuard = brain._regressionGuard or {}
    local g = brain._regressionGuard
    g.layers = g.layers or {}
    layer = tostring(layer or "layer")
    g.layers[layer] = g.layers[layer] or {errors = 0, lastAt = 0, mutedUntil = 0}
    return g.layers[layer]
end

local function brg_debug(msg)
    if NPCRegressionGuardBridge.Config.debug == true then
        print("[NPCRegressionGuard] " .. tostring(msg))
    end
end

function NPCRegressionGuardBridge.ShouldRunLayer(layer, brain, minIntervalMs)
    if NPCRegressionGuardBridge.Config.enabled == false then return true end
    local state = brg_layerState(brain, layer)
    if not state then return true end
    local now = brg_nowMs()
    if now < (tonumber(state.mutedUntil) or 0) then return false end
    local minMs = tonumber(minIntervalMs) or tonumber(NPCRegressionGuardBridge.Config.layerCooldownMs) or 350
    if minMs > 0 and now - (tonumber(state.lastAt) or 0) < minMs then return false end
    state.lastAt = now
    return true
end

function NPCRegressionGuardBridge.RecordLayerError(layer, brain, err)
    if NPCRegressionGuardBridge.Config.enabled == false then return end
    local state = brg_layerState(brain, layer)
    if not state then return end
    local now = brg_nowMs()
    state.errors = (tonumber(state.errors) or 0) + 1
    state.lastErrorAt = now
    state.lastError = tostring(err or "unknown")
    if state.errors >= (tonumber(NPCRegressionGuardBridge.Config.maxLayerErrors) or 3) then
        state.mutedUntil = now + (tonumber(NPCRegressionGuardBridge.Config.layerErrorMuteMs) or 18000)
        brg_debug(tostring(layer) .. " muted for " .. tostring(state.lastError))
    end
end

function NPCRegressionGuardBridge.SafeCall(layer, brain, fn, fallbackA, fallbackB, fallbackC)
    if type(fn) ~= "function" then return false, fallbackA, fallbackB, fallbackC end
    if NPCRegressionGuardBridge.Config.enabled ~= false then
        local state = brg_layerState(brain, layer)
        local now = brg_nowMs()
        if state and now < (tonumber(state.mutedUntil) or 0) then
            return false, fallbackA, fallbackB, fallbackC
        end
    end
    local ok, a, b, c = pcall(fn)
    if ok then
        local state = brg_layerState(brain, layer)
        if state then
            state.errors = 0
            state.lastError = nil
        end
        return true, a, b, c
    end
    NPCRegressionGuardBridge.RecordLayerError(layer, brain, a)
    return false, fallbackA, fallbackB, fallbackC
end

local function brg_holdForState(state, reason)
    local cfg = NPCRegressionGuardBridge.Config
    local s = brg_stateName(state)
    local r = tostring(reason or ""):lower()
    if s == "SearchEnemy" or r:find("memory", 1, true) or r:find("investigate", 1, true) then
        return tonumber(cfg.memoryDecisionHoldMs) or 2200
    end
    if r:find("post%-combat") or r:find("recovery", 1, true) then
        return tonumber(cfg.postCombatDecisionHoldMs) or 2600
    end
    if brg_isTactical(s) then
        return tonumber(cfg.tacticalDecisionHoldMs) or 1450
    end
    return tonumber(cfg.advisoryDecisionHoldMs) or 950
end

function NPCRegressionGuardBridge.StabilizeState(director, brain, state, reason, opts)
    if NPCRegressionGuardBridge.Config.enabled == false then return state, reason end
    if type(brain) ~= "table" or not state then return state, reason end
    if brg_isEmergency(state) then
        brain._regressionGuardState = {state = state, reason = reason, at = brg_nowMs(), switches = 0, windowAt = brg_nowMs()}
        return state, reason
    end

    opts = opts or {}
    local now = tonumber(opts.now) or brg_nowMs()
    local g = brain._regressionGuardState or {}
    local oldState = g.state
    local oldReason = g.reason
    local oldAt = tonumber(g.at) or 0

    if oldState == nil or oldState == state then
        g.state = state
        g.reason = reason
        g.at = now
        g.switches = tonumber(g.switches) or 0
        g.windowAt = tonumber(g.windowAt) or now
        brain._regressionGuardState = g
        return state, reason
    end

    if now - (tonumber(g.windowAt) or now) > (tonumber(NPCRegressionGuardBridge.Config.loopWindowMs) or 7600) then
        g.windowAt = now
        g.switches = 0
        g.loopHoldUntil = nil
    end
    g.switches = (tonumber(g.switches) or 0) + 1

    if now < (tonumber(g.loopHoldUntil) or 0) and brg_isTactical(oldState) and brg_isTactical(state) then
        brain._regressionGuardState = g
        return oldState, oldReason or reason or "stabilized tactical loop"
    end

    local holdMs = brg_holdForState(oldState, oldReason)
    if brg_isPlayerControlled(brain) then holdMs = math.min(holdMs, 900) end
    if brg_isTactical(oldState) and brg_isTactical(state) and now - oldAt < holdMs then
        brain._regressionGuardState = g
        return oldState, oldReason or reason or "stabilized tactical state"
    end

    if (tonumber(g.switches) or 0) >= (tonumber(NPCRegressionGuardBridge.Config.loopSwitchLimit) or 4)
        and brg_isTactical(oldState)
        and brg_isTactical(state) then
        g.loopHoldUntil = now + (tonumber(NPCRegressionGuardBridge.Config.loopMuteMs) or 2800)
        brain._regressionGuardState = g
        return oldState, oldReason or reason or "stabilized tactical oscillation"
    end

    g.state = state
    g.reason = reason
    g.at = now
    brain._regressionGuardState = g
    return state, reason
end


local function brg_isEmergencyTask(task)
    if type(task) ~= "table" then return false end
    if task.playerOrder == true or task.orderName ~= nil or task.orderId ~= nil then return true end
    if task.combat == true or task.combatMove == true or task.tacticalStep == true or task.meleeApproach == true then return true end
    if task.tacticalRetreat == true or task.moraleMove == true or task.fireteam == true or task.squadSupport == true then return true end
    local s = tostring(task.directorState or task.state or "")
    return s == "Attack"
        or s == "MeleeFallback"
        or s == "EmergencyDefense"
        or s == "Flee"
        or s == "KeepDistance"
        or s == "TacticalCover"
        or s == "HoldAngle"
        or s == "SuppressEnemy"
        or s == "ReloadCover"
        or s == "Regroup"
end

function NPCRegressionGuardBridge.DecorateTask(task, brain, layer)
    if NPCRegressionGuardBridge.Config.enabled == false or NPCRegressionGuardBridge.Config.taskClampEnabled == false then return task end
    if type(task) ~= "table" then return task end
    local action = tostring(task.action or "")
    if action ~= "Move" and action ~= "GoTo" then return task end

    local tactical = task.fireteam == true
        or task.combatMove == true
        or task.combatPathShortStep == true
        or task.angleDiscipline == true
        or task.moraleMove == true
        or task.tacticalStep == true
        or task.squadMemory == true
        or task.postCombatRecovery == true
        or tostring(layer or ""):find("tactical", 1, true) ~= nil

    if not tactical then return task end

    local cfg = NPCRegressionGuardBridge.Config
    local minPath = tonumber(cfg.minTacticalPathThrottleMs) or 1150
    local minSame = tonumber(cfg.minTacticalSameTargetThrottleMs) or 3600
    if task.indoorTactical == true then
        minPath = math.max(minPath, tonumber(cfg.minIndoorPathThrottleMs) or 1450)
        minSame = math.max(minSame, tonumber(cfg.minIndoorSameTargetThrottleMs) or 4600)
    end
    if brg_isEmergencyTask(task) then
        minPath = math.min(minPath, tonumber(cfg.emergencyPathThrottleMs) or 420)
        minSame = math.min(minSame, tonumber(cfg.emergencySameTargetThrottleMs) or 900)
    end
    task.pathThrottleMs = math.max(tonumber(task.pathThrottleMs) or 0, minPath)
    local currentSame = tonumber(task.sameTargetPathThrottleMs) or 0
    if brg_isEmergencyTask(task) and currentSame > 0 then
        task.sameTargetPathThrottleMs = math.min(math.max(currentSame, minPath), minSame)
    else
        task.sameTargetPathThrottleMs = math.max(currentSame, minSame)
    end

    local arrive = tonumber(task.arriveDist)
    if arrive then
        arrive = math.max(tonumber(cfg.minTacticalArriveDist) or 0.95, arrive)
        arrive = math.min(tonumber(cfg.maxTacticalArriveDist) or 2.25, arrive)
        task.arriveDist = arrive
    end
    task.noHardFace = true
    task.regressionGuard = true
    return task
end

function NPCRegressionGuardBridge.DecorateTasks(tasks, brain, layer)
    if type(tasks) ~= "table" then return tasks end
    for _, task in ipairs(tasks) do
        NPCRegressionGuardBridge.DecorateTask(task, brain, layer)
    end
    return tasks
end

return NPCRegressionGuardBridge
