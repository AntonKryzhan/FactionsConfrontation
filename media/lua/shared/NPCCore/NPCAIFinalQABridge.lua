-- NPCAIFinalQABridge.lua
-- Stage 376: final AI QA / stabilization pass for the Stage 363-375 tactical stack.
--
-- This bridge is deliberately runtime-only and advisory.  It does not add save
-- roots, network commands, damage contracts, item transfers or Java hooks.  It
-- centralises small safety checks that were previously scattered across the
-- tactical layers: stale-threat decay, per-brain layer cadence, task sanity and
-- anti-oscillation clamps.

NPCAIFinalQABridge = NPCAIFinalQABridge or {}
NPCAIFinalQABridge.VERSION = "2026-06-01-stage378-locomotion-liveness-router-unblock-1"

NPCAIFinalQABridge.Config = NPCAIFinalQABridge.Config or {
    enabled = true,
    debug = false,
    staleMemoryMs = 36000,
    staleLowConfidenceMemoryMs = 18000,
    staleRadioThreatMs = 24000,
    staleCurrentThreatMs = 18000,
    staleLastKnownMs = 42000,
    minLayerIntervalMs = 180,
    highLoadLayerMultiplier = 1.55,
    criticalLayerMultiplier = 2.35,
    panicLayerMultiplier = 3.4,
    playerOrderLayerMultiplier = 0.72,
    tacticalPlanWindowMs = 12000,
    maxTacticalPlansLow = 9,
    maxTacticalPlansHigh = 6,
    maxTacticalPlansCritical = 4,
    maxTacticalPlansPanic = 2,
    stateWindowMs = 11500,
    maxStateSwitchesLow = 8,
    maxStateSwitchesHigh = 6,
    maxStateSwitchesCritical = 5,
    maxStateSwitchesPanic = 4,
    stateHoldMs = 2600,
    playerOrderStateHoldMs = 850,
    moveRepeatWindowMs = 5200,
    moveRepeatRadius = 0.75,
    moveRepeatSuppressMs = 2400,
    tacticalMinPathThrottleMs = 1350,
    tacticalSameTargetThrottleMs = 4200,
    indoorMinPathThrottleMs = 1650,
    indoorSameTargetThrottleMs = 5200,
    emergencySameTargetThrottleMs = 900,
    emergencyMinPathThrottleMs = 450,
    maxTacticalTasksPerPlan = 4,
    maxAmbientTasksPerPlan = 3,
    maxPostCombatLootTasks = 3,
    maxFaceTaskTime = 42,
    minTimeTaskTime = 6,
    maxTimeTaskTime = 90
}

local function fqa_nowMs()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then
        local ok, hours = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok and hours then return math.floor((tonumber(hours) or 0) * 3600000) end
    end
    return 0
end

local function fqa_hash(value)
    local s = tostring(value or 0)
    local h = 0
    for i = 1, #s do
        h = (h * 33 + string.byte(s, i)) % 9973
    end
    return h
end

local function fqa_id(brain)
    if type(brain) ~= "table" then return "nobrain" end
    return tostring(brain.persistentId or brain.uid or brain.id or brain.npcId or brain.characterId or "brain")
end

local function fqa_dist2(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return dx * dx + dy * dy
end

local function fqa_loadLevel()
    if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.GetLoadState then
        local ok, state = pcall(function() return NPCWorkSchedulerBridge.GetLoadState(false) end)
        if ok and state then return tonumber(state.level) or 0, state end
    end
    return 0, nil
end

local function fqa_isPlayerControlled(brain)
    if type(brain) ~= "table" then return false end
    return brain.master ~= nil
        or brain.mercenaryHired == true
        or brain.hired == true
        or brain.isPlayerGuard == true
        or brain.playerOwned == true
        or brain.playerControlled == true
        or brain.follow == true
        or brain.followPlayer == true
end

local function fqa_action(task)
    if type(task) ~= "table" then return "" end
    return tostring(task.action or "")
end

local function fqa_isMoveTask(task)
    local a = fqa_action(task)
    return a == "Move" or a == "GoTo"
end

local function fqa_isTacticalState(state)
    local s = tostring(state or "")
    return s == "SearchEnemy"
        or s == "TacticalCover"
        or s == "HoldAngle"
        or s == "FlankEnemy"
        or s == "SuppressEnemy"
        or s == "BoundForward"
        or s == "Regroup"
        or s == "Flee"
        or s == "KeepDistance"
        or s == "ReloadCover"
end

local function fqa_isEmergencyState(state)
    local s = tostring(state or "")
    return s == "Dead"
        or s == "Disabled"
        or s == "EmergencyDefense"
        or s == "MeleeFallback"
        or s == "Attack"
        or s == "HealSelf"
        or s == "ReloadWeapon"
        or s == "ReloadCover"
end


local function fqa_isEmergencyMoveTask(task)
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

local function fqa_isTacticalTask(task, layer)
    if type(task) ~= "table" then return false end
    local a = fqa_action(task)
    local layerText = tostring(layer or "")
    return task.fireteam == true
        or task.combatMove == true
        or task.combatPathShortStep == true
        or task.angleDiscipline == true
        or task.moraleMove == true
        or task.tacticalStep == true
        or task.squadMemory == true
        or task.postCombatRecovery == true
        or task.indoorSweep == true
        or task.indoorTactical == true
        or task.tacticalRetreat == true
        or task.retreatMove == true
        or task.finalQA == true
        or layerText:find("tactical", 1, true) ~= nil
        or layerText:find("fireteam", 1, true) ~= nil
        or layerText:find("indoor", 1, true) ~= nil
        or layerText:find("retreat", 1, true) ~= nil
        or layerText:find("combat", 1, true) ~= nil
        or ((a == "Move" or a == "GoTo") and (task.directorState == "SearchEnemy" or task.directorState == "TacticalCover" or task.directorState == "HoldAngle" or task.directorState == "Regroup"))
end

local function fqa_layerWeight(layer)
    layer = tostring(layer or "")
    if layer:find("path", 1, true) then return 1.15 end
    if layer:find("indoorsweep", 1, true) then return 1.35 end
    if layer:find("fireteam", 1, true) then return 1.25 end
    if layer:find("angle", 1, true) then return 1.20 end
    if layer:find("retreat", 1, true) then return 1.15 end
    if layer:find("postcombat", 1, true) then return 1.30 end
    if layer:find("squadmemory", 1, true) then return 1.10 end
    return 1.0
end

local function fqa_brainQA(brain)
    if type(brain) ~= "table" then return nil end
    brain.finalQA = brain.finalQA or {}
    return brain.finalQA
end

local function fqa_threatAge(threat, now)
    if type(threat) ~= "table" then return 0 end
    local at = tonumber(threat.at or threat.time or threat.updatedAt or threat.lastSeenAt or threat.lastKnownAt or threat.seenAt)
    if not at or at <= 0 then return 0 end
    return now - at
end

function NPCAIFinalQABridge.FilterThreat(threat, brain)
    if NPCAIFinalQABridge.Config.enabled == false then return threat end
    if type(threat) ~= "table" then return threat end
    if threat.canSee == true or threat.visible == true or threat.direct == true then return threat end
    local now = fqa_nowMs()
    local age = fqa_threatAge(threat, now)
    if age <= 0 then return threat end
    local confidence = tonumber(threat.confidence) or tonumber(threat.score) or 0.5
    if confidence < 0.35 and age > (tonumber(NPCAIFinalQABridge.Config.staleLowConfidenceMemoryMs) or 18000) then return nil end
    if (threat.memoryOnly == true or threat.radioOnly == true or threat.indirect == true) and age > (tonumber(NPCAIFinalQABridge.Config.staleMemoryMs) or 36000) then return nil end
    return threat
end

local function fqa_decayBrainThreatField(brain, field, maxAgeMs)
    local threat = brain and brain[field]
    if type(threat) ~= "table" then return end
    local now = fqa_nowMs()
    if threat.canSee == true or threat.visible == true then return end
    local age = fqa_threatAge(threat, now)
    if age > 0 and age > maxAgeMs then
        brain[field] = nil
    end
end

local function fqa_decaySquadMemory(brain)
    if type(brain) ~= "table" or type(brain.squadMemory) ~= "table" then return end
    local sm = brain.squadMemory
    local focus = sm.focus
    if type(focus) ~= "table" then return end
    if focus.canSee == true or focus.visible == true then return end
    local now = fqa_nowMs()
    local at = tonumber(focus.at or focus.updatedAt or sm.updatedAt) or 0
    if at <= 0 then return end
    local age = now - at
    local confidence = tonumber(focus.confidence) or 0.5
    if age > (tonumber(NPCAIFinalQABridge.Config.staleLowConfidenceMemoryMs) or 18000) then
        focus.confidence = math.max(0, confidence * 0.72)
    end
    if age > (tonumber(NPCAIFinalQABridge.Config.staleMemoryMs) or 36000) and (tonumber(focus.confidence) or 0) < 0.25 then
        sm.focus = nil
    end
end

local function fqa_decayLastKnown(brain)
    if type(brain) ~= "table" or type(brain.lastKnownEnemyPosition) ~= "table" then return end
    local last = brain.lastKnownEnemyPosition
    local at = tonumber(last.at or last.time or last.updatedAt) or 0
    if at > 0 and fqa_nowMs() - at > (tonumber(NPCAIFinalQABridge.Config.staleLastKnownMs) or 42000) then
        brain.lastKnownEnemyPosition = nil
    end
end

function NPCAIFinalQABridge.Update(bandit, brain, threat, runtime)
    if NPCAIFinalQABridge.Config.enabled == false or type(brain) ~= "table" then return threat end
    local qa = fqa_brainQA(brain)
    if not qa then return threat end
    local now = fqa_nowMs()
    qa.updatedAt = now
    qa.loadLevel = fqa_loadLevel()
    qa.playerControlled = fqa_isPlayerControlled(brain)

    fqa_decayBrainThreatField(brain, "radioThreat", tonumber(NPCAIFinalQABridge.Config.staleRadioThreatMs) or 24000)
    fqa_decayBrainThreatField(brain, "currentThreat", tonumber(NPCAIFinalQABridge.Config.staleCurrentThreatMs) or 18000)
    fqa_decaySquadMemory(brain)
    fqa_decayLastKnown(brain)

    if bandit and bandit.getX and bandit.getY then
        local x = tonumber(bandit:getX()) or 0
        local y = tonumber(bandit:getY()) or 0
        qa.lastSampleAt = qa.lastSampleAt or now
        qa.lastX = qa.lastX or x
        qa.lastY = qa.lastY or y
        if now - (tonumber(qa.lastSampleAt) or 0) >= 900 then
            local moved2 = fqa_dist2(x, y, qa.lastX, qa.lastY)
            qa.recentMoved2 = moved2
            qa.lastX = x
            qa.lastY = y
            qa.lastSampleAt = now
        end
    end

    return NPCAIFinalQABridge.FilterThreat(threat, brain)
end

function NPCAIFinalQABridge.ShouldRunLayer(layer, brain, requestedIntervalMs)
    if NPCAIFinalQABridge.Config.enabled == false or type(brain) ~= "table" then return true end
    local qa = fqa_brainQA(brain)
    if not qa then return true end
    qa.layers = qa.layers or {}
    layer = tostring(layer or "layer")
    local state = qa.layers[layer] or {lastAt = 0}
    qa.layers[layer] = state

    local now = fqa_nowMs()
    local level = fqa_loadLevel()
    local interval = math.max(tonumber(NPCAIFinalQABridge.Config.minLayerIntervalMs) or 180, tonumber(requestedIntervalMs) or 0)
    local mult = 1.0
    if level >= 3 then
        mult = tonumber(NPCAIFinalQABridge.Config.panicLayerMultiplier) or 3.4
    elseif level >= 2 then
        mult = tonumber(NPCAIFinalQABridge.Config.criticalLayerMultiplier) or 2.35
    elseif level >= 1 then
        mult = tonumber(NPCAIFinalQABridge.Config.highLoadLayerMultiplier) or 1.55
    end
    mult = mult * fqa_layerWeight(layer)
    if fqa_isPlayerControlled(brain) then
        mult = math.max(0.65, mult * (tonumber(NPCAIFinalQABridge.Config.playerOrderLayerMultiplier) or 0.72))
    end

    interval = math.floor(interval * mult)
    if now - (tonumber(state.lastAt) or 0) < interval then return false end
    state.lastAt = now
    return true
end

local function fqa_maxStateSwitches(level)
    if level >= 3 then return tonumber(NPCAIFinalQABridge.Config.maxStateSwitchesPanic) or 4 end
    if level >= 2 then return tonumber(NPCAIFinalQABridge.Config.maxStateSwitchesCritical) or 5 end
    if level >= 1 then return tonumber(NPCAIFinalQABridge.Config.maxStateSwitchesHigh) or 6 end
    return tonumber(NPCAIFinalQABridge.Config.maxStateSwitchesLow) or 8
end

function NPCAIFinalQABridge.StabilizeState(director, brain, state, reason, opts)
    if NPCAIFinalQABridge.Config.enabled == false or type(brain) ~= "table" or not state then return state, reason end
    if fqa_isEmergencyState(state) then return state, reason end

    opts = opts or {}
    local threat = opts.threat
    if threat and type(threat) == "table" and (threat.canSee == true or threat.visible == true) then return state, reason end

    local now = tonumber(opts.now) or fqa_nowMs()
    local level = fqa_loadLevel()
    local qa = fqa_brainQA(brain)
    if not qa then return state, reason end
    qa.state = qa.state or {state = state, reason = reason, at = now, windowAt = now, switches = 0}
    local s = qa.state

    if now - (tonumber(s.windowAt) or now) > (tonumber(NPCAIFinalQABridge.Config.stateWindowMs) or 11500) then
        s.windowAt = now
        s.switches = 0
        s.holdUntil = nil
    end

    if s.state ~= state then
        s.switches = (tonumber(s.switches) or 0) + 1
    end

    local playerControlled = fqa_isPlayerControlled(brain)
    local maxSwitches = fqa_maxStateSwitches(level)
    if playerControlled then maxSwitches = maxSwitches + 2 end

    if now < (tonumber(s.holdUntil) or 0) and fqa_isTacticalState(s.state) and fqa_isTacticalState(state) then
        return s.state, s.reason or reason or "final qa state hold"
    end

    if fqa_isTacticalState(s.state) and fqa_isTacticalState(state) and (tonumber(s.switches) or 0) > maxSwitches then
        local holdMs = playerControlled and (tonumber(NPCAIFinalQABridge.Config.playerOrderStateHoldMs) or 850) or (tonumber(NPCAIFinalQABridge.Config.stateHoldMs) or 2600)
        s.holdUntil = now + holdMs
        qa.state = s
        return s.state, s.reason or reason or "final qa tactical oscillation hold"
    end

    s.state = state
    s.reason = reason
    s.at = now
    qa.state = s
    return state, reason
end

local function fqa_recordMove(brain, task, now)
    local qa = fqa_brainQA(brain)
    if not qa or not fqa_isMoveTask(task) then return false end
    local x = tonumber(task.x)
    local y = tonumber(task.y)
    local z = tonumber(task.z) or 0
    if not x or not y then return false end
    local last = qa.lastMoveTarget
    local repeatMove = false
    if last and now - (tonumber(last.at) or 0) < (tonumber(NPCAIFinalQABridge.Config.moveRepeatWindowMs) or 5200) then
        local r = tonumber(NPCAIFinalQABridge.Config.moveRepeatRadius) or 0.75
        repeatMove = math.floor(tonumber(last.z) or z) == math.floor(z) and fqa_dist2(x, y, last.x, last.y) <= r * r
    end
    qa.lastMoveTarget = {x = x, y = y, z = z, at = now}
    return repeatMove
end

function NPCAIFinalQABridge.DecorateTask(task, brain, layer)
    if NPCAIFinalQABridge.Config.enabled == false or type(task) ~= "table" then return task end
    local now = fqa_nowMs()
    local action = fqa_action(task)

    if fqa_isMoveTask(task) then
        local x = tonumber(task.x)
        local y = tonumber(task.y)
        if not x or not y then
            task.action = "Time"
            task.anim = task.anim or "Idle"
            task.time = math.max(tonumber(NPCAIFinalQABridge.Config.minTimeTaskTime) or 6, math.min(tonumber(task.time) or 8, 16))
            task.finalQADroppedMove = true
            return task
        end

        local tactical = fqa_isTacticalTask(task, layer)
        if tactical then
            local minPath = tonumber(NPCAIFinalQABridge.Config.tacticalMinPathThrottleMs) or 1650
            local minSame = tonumber(NPCAIFinalQABridge.Config.tacticalSameTargetThrottleMs) or 6500
            if task.indoorTactical == true or task.indoorSweep == true then
                minPath = math.max(minPath, tonumber(NPCAIFinalQABridge.Config.indoorMinPathThrottleMs) or 2100)
                minSame = math.max(minSame, tonumber(NPCAIFinalQABridge.Config.indoorSameTargetThrottleMs) or 8200)
            end
            task.pathThrottleMs = math.max(tonumber(task.pathThrottleMs) or 0, minPath)
            task.sameTargetPathThrottleMs = math.max(tonumber(task.sameTargetPathThrottleMs) or 0, minSame)
            task.noHardFace = true
            task.engineAssist = task.engineAssist ~= false
            task.naturalMotion = task.naturalMotion ~= false
            task.smoothTurn = task.smoothTurn ~= false
            if task.arriveDist ~= nil then
                task.arriveDist = math.max(0.85, math.min(tonumber(task.arriveDist) or 1.25, task.indoorTactical and 1.75 or 2.35))
            else
                task.arriveDist = task.indoorTactical and 1.15 or 1.35
            end
        end

        if fqa_recordMove(brain, task, now) then
            task.finalQARepeatMove = true
            if fqa_isEmergencyMoveTask(task) then
                task.pathThrottleMs = math.max(tonumber(task.pathThrottleMs) or 0, tonumber(NPCAIFinalQABridge.Config.emergencyMinPathThrottleMs) or 450)
                task.sameTargetPathThrottleMs = math.min(math.max(tonumber(task.sameTargetPathThrottleMs) or 0, 450), tonumber(NPCAIFinalQABridge.Config.emergencySameTargetThrottleMs) or 900)
                task.finalQARepeatMoveEmergency = true
            else
                task.pathThrottleMs = math.max(tonumber(task.pathThrottleMs) or 0, tonumber(NPCAIFinalQABridge.Config.moveRepeatSuppressMs) or 2400)
                task.sameTargetPathThrottleMs = math.max(tonumber(task.sameTargetPathThrottleMs) or 0, (tonumber(NPCAIFinalQABridge.Config.moveRepeatSuppressMs) or 2400) * 2)
                if not task.playerOrder and not task.combatMove and not task.tacticalRetreat then
                    task.noRecoveryReplan = true
                end
            end
        end
        task.finalQA = true
        return task
    end

    if action == "FaceLocation" then
        task.time = math.max(tonumber(NPCAIFinalQABridge.Config.minTimeTaskTime) or 6, math.min(tonumber(task.time) or 20, tonumber(NPCAIFinalQABridge.Config.maxFaceTaskTime) or 42))
        task.finalQA = true
    elseif action == "Time" then
        task.time = math.max(tonumber(NPCAIFinalQABridge.Config.minTimeTaskTime) or 6, math.min(tonumber(task.time) or 12, tonumber(NPCAIFinalQABridge.Config.maxTimeTaskTime) or 90))
        task.finalQA = true
    end

    return task
end

function NPCAIFinalQABridge.DecorateTasks(tasks, brain, layer)
    if NPCAIFinalQABridge.Config.enabled == false or type(tasks) ~= "table" then return tasks end
    local tactical = tostring(layer or ""):find("combat", 1, true)
        or tostring(layer or ""):find("tactical", 1, true)
        or tostring(layer or ""):find("retreat", 1, true)
        or tostring(layer or ""):find("indoor", 1, true)
    local maxTasks = tactical and (tonumber(NPCAIFinalQABridge.Config.maxTacticalTasksPerPlan) or 4) or (tonumber(NPCAIFinalQABridge.Config.maxAmbientTasksPerPlan) or 3)
    if tostring(layer or ""):find("postcombat.loot", 1, true) then
        maxTasks = tonumber(NPCAIFinalQABridge.Config.maxPostCombatLootTasks) or 3
    end
    local out = tasks
    for i = #out, 1, -1 do
        local task = out[i]
        if type(task) ~= "table" then
            table.remove(out, i)
        else
            NPCAIFinalQABridge.DecorateTask(task, brain, layer)
        end
    end
    while #out > maxTasks do
        table.remove(out)
    end
    return out
end

function NPCAIFinalQABridge.AdjustBudget(kind, budget, loadState)
    if NPCAIFinalQABridge.Config.enabled == false then return budget end
    kind = tostring(kind or "ai")
    local level = tonumber(loadState and loadState.level) or fqa_loadLevel()
    budget = tonumber(budget) or 1
    if level <= 0 then return budget end
    if kind == "path" or kind == "zombiePath" then
        return math.max(1, math.min(budget, kind == "path" and 2 or 1))
    end
    if kind == "sense" or kind == "los" then
        return math.max(1, math.floor(budget * (level >= 3 and 0.78 or (level >= 2 and 0.86 or 0.94))))
    end
    if kind == "utility" or kind == "world" or kind == "persistent" or kind == "learning" then
        return math.max(1, math.floor(budget * (level >= 3 and 0.70 or (level >= 2 and 0.82 or 0.92))))
    end
    return budget
end

function NPCAIFinalQABridge.AdjustInterval(kind, interval, brain, loadState)
    if NPCAIFinalQABridge.Config.enabled == false then return interval end
    kind = tostring(kind or "ai")
    interval = tonumber(interval) or 1
    local level = tonumber(loadState and loadState.level) or fqa_loadLevel()
    if level <= 0 then return interval end
    if fqa_isPlayerControlled(brain) then return math.max(1, math.floor(interval * (level >= 3 and 1.15 or 1.0))) end
    if kind == "ai" or kind == "utility" or kind == "sense" or kind == "los" then
        return math.max(1, math.floor(interval * (level >= 3 and 1.35 or (level >= 2 and 1.22 or 1.08))))
    end
    return interval
end

function NPCAIFinalQABridge.AllowPathStart(zombie, task, brain)
    if NPCAIFinalQABridge.Config.enabled == false or type(task) ~= "table" then return true end
    if task.finalQADroppedMove == true then return false end
    if task.playerOrder == true or task.orderName ~= nil or task.orderId ~= nil then return true end
    local level = fqa_loadLevel()
    if level <= 1 then return true end
    if task.finalQARepeatMove == true and not fqa_isEmergencyMoveTask(task) then
        return false
    end
    return true
end

function NPCAIFinalQABridge.DecorateMovementTask(task, brain, layer)
    return NPCAIFinalQABridge.DecorateTask(task, brain, layer or "movement")
end

return NPCAIFinalQABridge
