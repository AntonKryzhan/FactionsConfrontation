-- NPCIntentArbitrationBridge.lua
-- Runtime intent arbitration and event-driven liveness guard.
-- This bridge does not replace existing programs. It provides one bounded
-- decision gate per NPC so movement, aiming, cover, retreat, loot and ambient
-- tasks do not fight for the same action window.

NPCIntentArbitrationBridge = NPCIntentArbitrationBridge or {}
NPCIntentArbitrationBridge.VERSION = "2026-06-02-stage383-intent-liveness-1"

NPCIntentArbitrationBridge.Config = NPCIntentArbitrationBridge.Config or {
    defaultTtlMs = 1400,
    movementTtlMs = 2200,
    combatTtlMs = 1200,
    playerOrderTtlMs = 3600,
    ambientTtlMs = 900,
    minStateHoldMs = 420,
    samePriorityHoldMs = 520,
    taskConflictHoldMs = 1800,
    pathDeferredWakeMs = 720,
    nearPlayerRadius = 110,
    eventTtlMs = 2600,
    priorities = {
        hard_safety = 100,
        player_order = 90,
        melee_emergency = 84,
        combat = 78,
        combat_move = 72,
        wounded = 68,
        regroup = 62,
        active_movement = 58,
        current_plan = 52,
        squad_memory = 46,
        post_combat = 40,
        loot = 34,
        world_routine = 28,
        ambient = 18
    }
}

local function nia_nowMs()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then
        local ok, hours = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok and hours then return math.floor((tonumber(hours) or 0) * 3600000) end
    end
    return 0
end

local function nia_lower(value)
    return tostring(value or ""):lower()
end

local function nia_priority(name, fallback)
    local p = NPCIntentArbitrationBridge.Config.priorities or {}
    return tonumber(p[name]) or tonumber(fallback) or tonumber(p.ambient) or 18
end

local function nia_ttl(name)
    local cfg = NPCIntentArbitrationBridge.Config
    if name == "player_order" then return tonumber(cfg.playerOrderTtlMs) or 3600 end
    if name == "combat" or name == "melee_emergency" then return tonumber(cfg.combatTtlMs) or 1200 end
    if name == "combat_move" or name == "active_movement" or name == "regroup" then return tonumber(cfg.movementTtlMs) or 2200 end
    if name == "ambient" or name == "world_routine" then return tonumber(cfg.ambientTtlMs) or 900 end
    return tonumber(cfg.defaultTtlMs) or 1400
end

local function nia_ensure(brain)
    if type(brain) ~= "table" then return nil end
    brain.ai = brain.ai or {}
    brain.ai.intentArbitration = brain.ai.intentArbitration or {}
    return brain.ai.intentArbitration
end

local function nia_id(character)
    if not character then return nil end
    if NPCUtils and NPCUtils.GetCharacterID then
        local ok, id = pcall(function() return NPCUtils.GetCharacterID(character) end)
        if ok and id then return tostring(id) end
    end
    return tostring(character)
end

local function nia_orderName(brain)
    if type(brain) ~= "table" then return nil end
    local order = brain.order or brain.directorOrder
    if type(order) == "table" then order = order.name or order.action or order.type or order.mode end
    order = tostring(order or "")
    if order == "" or order:lower() == "free" then return nil end
    return order:lower()
end

local function nia_hasPlayerAuthority(brain)
    if type(brain) ~= "table" then return false end
    if brain.master ~= nil or brain.mercenaryHired == true or brain.hired == true or brain.isPlayerGuard == true or brain.playerControlled == true then return true end
    local order = brain.order or brain.directorOrder
    if type(order) == "table" then
        if order.source == "player" or order.master ~= nil or order.interrupt == true or order.manual == true then return true end
    end
    return nia_orderName(brain) ~= nil and (brain.follow == true or brain.followPlayer == true or brain.companion == true)
end

local function nia_taskAction(task)
    return tostring(type(task) == "table" and task.action or "")
end

local function nia_isMoveAction(action)
    return action == "Move" or action == "GoTo"
end

local function nia_isCombatAction(action)
    return action == "Shoot" or action == "Aim" or action == "Hit" or action == "Shove" or action == "Reload"
end

local function nia_isRuntimeInterruptClass(class)
    return class == "hard_safety" or class == "melee_emergency" or class == "combat" or class == "combat_move" or class == "wounded" or class == "regroup"
end

local function nia_canPreemptIntent(class, currentClass, priority, currentPriority, context)
    class = class or "ambient"
    currentClass = currentClass or "ambient"
    priority = tonumber(priority) or nia_priority(class)
    currentPriority = tonumber(currentPriority) or nia_priority(currentClass)

    if class == "hard_safety" or class == "melee_emergency" then return true end
    if class == "player_order" and nia_isRuntimeInterruptClass(currentClass) then return false end
    if currentClass == "player_order" and nia_isRuntimeInterruptClass(class) then return true end
    if context and context.threat and nia_isRuntimeInterruptClass(class) then return true end
    return priority > currentPriority
end

local function nia_stateClass(state, reason, brain, threat)
    local s = tostring(state or "")
    local r = nia_lower(reason)
    if s == "Dead" or s == "Disabled" then return "hard_safety" end
    if s == "EmergencyDefense" or s == "MeleeFallback" or (threat and tonumber(threat.dist) and tonumber(threat.dist) <= 1.65) then return "melee_emergency" end
    if threat or s == "Attack" or s == "SearchEnemy" or s == "ReloadCover" then return "combat" end
    if s == "TacticalCover" or s == "FlankEnemy" or s == "SuppressEnemy" or s == "HoldAngle" or s == "BoundForward" or s == "KeepDistance" then return "combat_move" end
    if s == "Flee" or s == "HealSelf" then return "wounded" end
    if s == "Regroup" or r:find("regroup", 1, true) or r:find("cohesion", 1, true) then return "regroup" end
    if s == "RecoverPath" then return "active_movement" end
    if nia_hasPlayerAuthority(brain) then return "player_order" end
    if s == "LootArea" or r:find("loot", 1, true) or r:find("supply", 1, true) then return "loot" end
    if r:find("post%-combat") or r:find("recovery", 1, true) then return "post_combat" end
    if r:find("squad memory", 1, true) or r:find("investigate", 1, true) then return "squad_memory" end
    if r:find("routine", 1, true) or r:find("patrol", 1, true) or r:find("base", 1, true) then return "world_routine" end
    if s == "FollowPlayer" or s == "GuardPlayer" or s == "HoldPosition" or s == "GuardArea" then return "current_plan" end
    return "ambient"
end

function NPCIntentArbitrationBridge.ClassifyState(state, reason, brain, threat)
    local class = nia_stateClass(state, reason, brain, threat)
    return class, nia_priority(class), nia_ttl(class)
end

function NPCIntentArbitrationBridge.ClassifyTask(task, brain, context)
    if type(task) ~= "table" then return "ambient", nia_priority("ambient") end
    local action = nia_taskAction(task)
    if task.hardSafety == true or task.action == "Remove" then return "hard_safety", nia_priority("hard_safety") end
    if action == "Hit" or action == "Shove" or task.directorState == "EmergencyDefense" or task.directorState == "MeleeFallback" or task.meleeApproach == true then return "melee_emergency", nia_priority("melee_emergency") end
    if action == "Shoot" or action == "Aim" or action == "Reload" then return "combat", nia_priority("combat") end
    if nia_isMoveAction(action) then
        if task.combatMove == true or task.tacticalStep == true or task.fireteam == true or task.tacticalRetreat == true or task.directorState == "TacticalCover" or task.directorState == "FlankEnemy" or task.directorState == "KeepDistance" then
            return "combat_move", nia_priority("combat_move")
        end
        if task.directorState == "Regroup" or task.intentOwner == "squad_cohesion" then return "regroup", nia_priority("regroup") end
        if task.playerOrder == true or task.manualOrder == true or task.orderName ~= nil or nia_hasPlayerAuthority(brain) and (task.orderIssued ~= nil or task.orderId ~= nil) then return "player_order", nia_priority("player_order") end
        if task.intentOwner == "world_routine" or task.roadPatrol == true then return "world_routine", nia_priority("world_routine") end
        return "active_movement", nia_priority("active_movement")
    end
    if action == "Bandage" or action == "Eat" or action == "Drink" then return "wounded", nia_priority("wounded") end
    if task.playerOrder == true or task.manualOrder == true or task.orderName ~= nil or nia_hasPlayerAuthority(brain) and (task.orderIssued ~= nil or task.orderId ~= nil) then return "player_order", nia_priority("player_order") end
    if action == "Loot" or action == "LootItem" or action == "TakeItem" or task.intentOwner == "supply_need" then return "loot", nia_priority("loot") end
    if action == "FaceLocation" then
        local ctxClass = context and context.currentClass or nil
        if ctxClass == "combat" or ctxClass == "combat_move" then return "combat", nia_priority("combat") end
        return "ambient", nia_priority("ambient")
    end
    return task.intentClass or "ambient", nia_priority(task.intentClass or "ambient")
end

function NPCIntentArbitrationBridge.IsOnScreenCritical(character, brain)
    if not (character and character.getX and character.getY) then return false end
    if nia_hasPlayerAuthority(brain) then return true end
    local radius = tonumber(NPCIntentArbitrationBridge.Config.nearPlayerRadius) or 110
    local best = 999999
    local function consider(player)
        if not (player and player.getX and player.getY) then return end
        if player.isDead and player:isDead() then return end
        local dx = (tonumber(character:getX()) or 0) - (tonumber(player:getX()) or 0)
        local dy = (tonumber(character:getY()) or 0) - (tonumber(player:getY()) or 0)
        local d2 = dx * dx + dy * dy
        if d2 < best then best = d2 end
    end
    if getOnlinePlayers then
        local ok, players = pcall(function() return getOnlinePlayers() end)
        if ok and players then for i = 0, players:size() - 1 do consider(players:get(i)) end end
    end
    if best == 999999 and getSpecificPlayer then consider(getSpecificPlayer(0)) end
    local near = best <= radius * radius
    local arb = nia_ensure(brain)
    if arb then
        arb.nearPlayer = near
        arb.nearPlayerAtMs = near and nia_nowMs() or arb.nearPlayerAtMs
    end
    return near
end

function NPCIntentArbitrationBridge.BeginFrame(character, brain, uTick, context)
    local arb = nia_ensure(brain)
    if not arb then return nil end
    local now = nia_nowMs()
    arb.frame = tonumber(uTick) or arb.frame or 0
    arb.frameAtMs = now
    arb.characterId = nia_id(character)
    arb.nearPlayer = NPCIntentArbitrationBridge.IsOnScreenCritical(character, brain) == true
    if context and context.threat then
        arb.lastThreatAtMs = now
        arb.lastThreatKind = context.threat.kind
    end
    return arb
end

function NPCIntentArbitrationBridge.NoteEvent(brain, eventName, ttlMs, data)
    local arb = nia_ensure(brain)
    if not arb then return false end
    local now = nia_nowMs()
    arb.events = arb.events or {}
    arb.events[tostring(eventName)] = {untilMs = now + (tonumber(ttlMs) or tonumber(NPCIntentArbitrationBridge.Config.eventTtlMs) or 2600), data = data, atMs = now}
    return true
end

function NPCIntentArbitrationBridge.HasFreshEvent(brain, eventName)
    local arb = nia_ensure(brain)
    local ev = arb and arb.events and arb.events[tostring(eventName)] or nil
    if not ev then return false end
    if nia_nowMs() > (tonumber(ev.untilMs) or 0) then
        arb.events[tostring(eventName)] = nil
        return false
    end
    return true, ev.data
end

function NPCIntentArbitrationBridge.SelectState(character, brain, state, reason, context)
    local arb = nia_ensure(brain)
    if not arb then return state, reason end
    local now = nia_nowMs()
    context = context or {}
    local class, priority, ttl = NPCIntentArbitrationBridge.ClassifyState(state, reason, brain, context.threat)
    local current = arb.current
    if current and now > (tonumber(current.untilMs) or 0) then current = nil; arb.current = nil end

    if current and current.state and current.state ~= state then
        local currentPriority = tonumber(current.priority) or 0
        local currentClass = current.class or "ambient"
        local age = now - (tonumber(current.atMs) or now)
        local minHold = tonumber(NPCIntentArbitrationBridge.Config.minStateHoldMs) or 420
        local sameHold = tonumber(NPCIntentArbitrationBridge.Config.samePriorityHoldMs) or 520
        local mayPreempt = nia_canPreemptIntent(class, currentClass, priority, currentPriority, context)
        if not mayPreempt then
            if currentPriority > priority and age < (tonumber(NPCIntentArbitrationBridge.Config.taskConflictHoldMs) or 1800) then
                arb.lastSuppressedState = state
                arb.lastSuppressedReason = reason
                return current.state, current.reason or "intent hold"
            end
            if currentPriority == priority and age < sameHold then
                return current.state, current.reason or "intent same-priority hold"
            end
            if age < minHold and class ~= "combat" and class ~= "melee_emergency" then
                return current.state, current.reason or "intent min hold"
            end
        end
    end

    arb.current = {
        class = class,
        priority = priority,
        state = state,
        reason = reason,
        atMs = now,
        untilMs = now + ttl,
        threat = context.threat ~= nil
    }
    arb.lastClass = class
    arb.lastPriority = priority
    arb.lastState = state
    arb.lastReason = reason
    return state, reason
end

function NPCIntentArbitrationBridge.RequestStateIntent(character, brain, state, reason, context)
    local arb = nia_ensure(brain)
    if not arb then return true, "no arb" end
    local class, priority, ttl = NPCIntentArbitrationBridge.ClassifyState(state, reason, brain, context and context.threat)
    local now = nia_nowMs()
    local current = arb.current
    if current and now <= (tonumber(current.untilMs) or 0) and not nia_canPreemptIntent(class, current.class, priority, current.priority, context) and class ~= current.class then
        return false, current.class or "current"
    end
    arb.current = {class = class, priority = priority, state = state, reason = reason, atMs = now, untilMs = now + ttl, threat = context and context.threat ~= nil}
    return true, class
end

local function nia_highestTaskClass(tasks, brain, context)
    local bestClass = "ambient"
    local bestPriority = nia_priority("ambient")
    for _, task in pairs(tasks or {}) do
        local class, priority = NPCIntentArbitrationBridge.ClassifyTask(task, brain, context)
        if priority > bestPriority or (bestClass == "player_order" and nia_isRuntimeInterruptClass(class)) then
            bestClass = class
            bestPriority = priority
        end
    end
    return bestClass, bestPriority
end

function NPCIntentArbitrationBridge.MarkTasks(tasks, class, reason)
    if type(tasks) ~= "table" then return tasks end
    class = class or "ambient"
    local priority = nia_priority(class)
    for _, task in pairs(tasks) do
        if type(task) == "table" then
            task.intentClass = task.intentClass or class
            task.intentPriority = task.intentPriority or priority
            task.intentReason = task.intentReason or reason
            if class == "player_order" then task.playerOrder = task.playerOrder or true end
            if class == "combat" or class == "combat_move" or class == "melee_emergency" then task.combat = task.combat or (class == "combat"); task.combatMove = task.combatMove or (class ~= "combat") end
        end
    end
    return tasks
end

function NPCIntentArbitrationBridge.FilterTasks(character, brain, tasks, context)
    if not (brain and type(tasks) == "table" and #tasks > 0) then return tasks end
    local arb = nia_ensure(brain)
    if not arb then return tasks end
    context = context or {}
    local now = nia_nowMs()
    local class, priority = nia_highestTaskClass(tasks, brain, context)
    local current = arb.current
    if current and now > (tonumber(current.untilMs) or 0) then current = nil; arb.current = nil end

    local activeTask = type(brain.tasks) == "table" and brain.tasks[1] or nil
    if type(activeTask) == "table" then
        local activeClass, activePriority = NPCIntentArbitrationBridge.ClassifyTask(activeTask, brain, context)
        local activeFresh = true
        if activeTask._bms and activeTask._bms.startedAt then
            activeFresh = now - (tonumber(activeTask._bms.startedAt) or now) < (tonumber(NPCIntentArbitrationBridge.Config.taskConflictHoldMs) or 1800)
        end
        if activeFresh and activePriority > priority and not nia_canPreemptIntent(class, activeClass, priority, activePriority, context) and class ~= activeClass then
            arb.lastDroppedClass = class
            arb.lastDroppedReason = "active task " .. tostring(activeClass)
            arb.lastDroppedAtMs = now
            return {}
        end
    end

    if current and (tonumber(current.priority) or 0) > priority and not nia_canPreemptIntent(class, current.class, priority, current.priority, context) and class ~= current.class then
        arb.lastDroppedClass = class
        arb.lastDroppedReason = "current intent " .. tostring(current.class)
        arb.lastDroppedAtMs = now
        return {}
    end

    arb.current = {
        class = class,
        priority = priority,
        state = context.state or (tasks[1] and tasks[1].directorState),
        reason = context.reason or (tasks[1] and (tasks[1].directorReason or tasks[1].intentReason)),
        atMs = now,
        untilMs = now + nia_ttl(class)
    }
    return NPCIntentArbitrationBridge.MarkTasks(tasks, class, context.reason or context.source)
end

function NPCIntentArbitrationBridge.AllowMovementTask(character, brain, task)
    if not (brain and task) then return true end
    local class, priority = NPCIntentArbitrationBridge.ClassifyTask(task, brain, nil)
    if class == "player_order" or class == "melee_emergency" or class == "combat_move" or class == "regroup" or class == "wounded" then return true end
    if NPCIntentArbitrationBridge.HasFreshEvent(brain, "path_deferred") and priority < nia_priority("combat_move") then return false, "recent path deferred" end
    local arb = nia_ensure(brain)
    local current = arb and arb.current or nil
    local now = nia_nowMs()
    if current and now <= (tonumber(current.untilMs) or 0) and not nia_canPreemptIntent(class, current.class, priority, current.priority, nil) and class ~= current.class then
        return false, "higher intent " .. tostring(current.class)
    end
    return true
end

function NPCIntentArbitrationBridge.OnMovementCommitted(character, brain, task)
    local arb = nia_ensure(brain)
    if not arb then return end
    local class, priority = NPCIntentArbitrationBridge.ClassifyTask(task, brain, nil)
    local now = nia_nowMs()
    arb.current = {
        class = class,
        priority = priority,
        state = task.directorState,
        reason = task.directorReason or task.intentReason,
        atMs = now,
        untilMs = now + nia_ttl(class),
        moving = true,
        x = task.x,
        y = task.y,
        z = task.z
    }
    task.intentClass = task.intentClass or class
    task.intentPriority = task.intentPriority or priority
end

function NPCIntentArbitrationBridge.NotePathDeferred(character, brain, task, reason)
    NPCIntentArbitrationBridge.NoteEvent(brain, "path_deferred", tonumber(NPCIntentArbitrationBridge.Config.pathDeferredWakeMs) or 720, {reason = reason, action = task and task.action})
end

function NPCIntentArbitrationBridge.OnCombatTaskStart(character, brain, task)
    local arb = nia_ensure(brain)
    if not arb then return true end
    local now = nia_nowMs()
    arb.current = {
        class = "combat",
        priority = nia_priority("combat"),
        state = task and task.directorState or "Attack",
        reason = task and (task.directorReason or task.intentReason) or "combat task",
        atMs = now,
        untilMs = now + nia_ttl("combat")
    }
    if task then
        task.intentClass = task.intentClass or "combat"
        task.intentPriority = task.intentPriority or nia_priority("combat")
    end
    return true
end

return NPCIntentArbitrationBridge
