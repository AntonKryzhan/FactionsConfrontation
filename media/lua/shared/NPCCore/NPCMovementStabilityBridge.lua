-- NPCMovementStabilityBridge.lua
-- Neutral shared backend for movement stability and stuck recovery.

NPCMovementStabilityBridge = NPCMovementStabilityBridge or {}

NPCMovementStabilityBridge.VERSION = "2026-06-10-stage448-deferred-path-start-queue-1"

NPCMovementStabilityBridge.Config = NPCMovementStabilityBridge.Config or {
    stuckNoMoveMs = 1350,
    stuckNoProgressMs = 2200,
    spinWindowMs = 1800,
    spinAngle = 90,
    localEscapeRadius = 5,
    targetSearchRadius = 6,
    badTargetCooldownMs = 28000,
    maxReplans = 2,
    ambientMoveMaxReplans = 0,
    combatMoveMaxReplans = 1,
    combatMoveCooldownMs = 1350,
    combatMoveSameRadius = 1.35,
    meleeCloseEnoughDist = 1.45,
    movementIntentTtlMs = 14000,
    movementIntentCriticalTtlMs = 26000,
    movementIntentOwnerHoldMs = 4200,
    movementIntentSameTargetMs = 14000,
    movementIntentSameRadius = 0.85,
    movementIntentLoopWindowMs = 26000,
    movementIntentLoopMax = 4,
    movementIntentLoopUniqueMax = 3,
    movementIntentSuppressMs = 18000,
    movementIntentHistoryMax = 10,
    personalSpaceRadius = 1.45,
    queuedRepairHoldMs = 2200,
    minPathRequestMs = 1600,
    forcedPathRequestMs = 900,
    sameTargetPathRequestMs = 6200,
    pathFailBackoffMs = 900,
    maxPathFailBackoffMs = 9000,
    obstacleTargetAdjustRadius = 3,
    obstacleTargetAdjustCooldownMs = 8500,
    obstacleDirectStepCacheMs = 350,
    playerOrderTeleportFallback = true,
    playerOrderTeleportAfterMs = 1250,
    playerOrderTeleportMaxDist = 140,
    playerOrderTeleportSearchRadius = 5,
    crossFloorOrderTeleportAfterMs = 260,
    crossFloorOrderMaxDist = 110,
    crossFloorOrderPathProbeMs = 180,
    crossFloorOrderSearchRadius = 7,
    crossFloorOrderAllowSingleProbe = false,
    b41SamePathHoldMs = 11500,
    b41MovingRetargetHoldMs = 7800,
    b41MovingRetargetRadius = 11.50,
    b41BrainPathHoldMs = 9000,
    b41BrainPathHighHoldMs = 14000,
    b41BrainPathCriticalHoldMs = 18000,
    b41BrainPathPanicHoldMs = 24000,
    b41BrainPathHoldRadius = 12.50,
    b41BrainPathPanicRadius = 18.00,
    simpleCombatPathing = true,
    simpleCombatPathDistance = 14,
    simpleCombatMinPathRequestMs = 2200,
    simpleCombatSameTargetPathRequestMs = 9800,
    simpleCombatForcedPathRequestMs = 1350
}

NPCMovementStabilityBridge._buffers = NPCMovementStabilityBridge._buffers or {}

local BMS_KEY_OFFSET = 1048576
local BMS_KEY_SPAN = 2097152
local BMS_Z_SPAN = BMS_KEY_SPAN * BMS_KEY_SPAN

local function bms_now()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then return math.floor(getGameTime():getWorldAgeHours() * 3600000) end
    return 0
end


local function bms_cameraZoom()
    if getCore and getCore() and getCore().getZoom then
        local ok, zoom = pcall(function() return getCore():getZoom(0) end)
        if ok and tonumber(zoom) then return tonumber(zoom) end
    end
    return 1
end

local function bms_perfLevel()
    local level = 0
    if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.GetLoadState then
        local ok, state = pcall(function() return NPCWorkSchedulerBridge.GetLoadState(false) end)
        if ok and state then level = tonumber(state.level) or 0 end
    end
    local zoom = bms_cameraZoom()
    if zoom >= 1.45 then level = math.max(level, 1) end
    if zoom >= 1.90 then level = math.max(level, 2) end
    if zoom >= 2.35 then level = math.max(level, 3) end
    return level, zoom
end

local function bms_dist2(x1, y1, x2, y2)
    local dx = x1 - x2
    local dy = y1 - y2
    return dx * dx + dy * dy
end

local function bms_key(x, y, z)
    local ix = math.floor(tonumber(x) or 0) + BMS_KEY_OFFSET
    local iy = math.floor(tonumber(y) or 0) + BMS_KEY_OFFSET
    local iz = math.floor(tonumber(z) or 0)
    return iz * BMS_Z_SPAN + ix * BMS_KEY_SPAN + iy
end

local function bms_getBuffer(name)
    NPCMovementStabilityBridge._buffers = NPCMovementStabilityBridge._buffers or {}
    local buf = NPCMovementStabilityBridge._buffers[name]
    if not buf then
        buf = {}
        NPCMovementStabilityBridge._buffers[name] = buf
    end
    return buf
end

local function bms_angleDelta(a, b)
    if a == nil or b == nil then return 0 end
    local d = math.abs(a - b) % 360
    if d > 180 then d = 360 - d end
    return d
end

local function bms_direction(zombie)
    if not zombie then return nil end
    local ok, angle = pcall(function()
        return zombie:getDirectionAngle()
    end)
    if ok then return tonumber(angle) end
    return nil
end

local function bms_isB41()
    if not (NPCCompatibilityBridge and NPCCompatibilityBridge.GetGameVersion) then return false end
    local ok, version = pcall(function() return NPCCompatibilityBridge.GetGameVersion() end)
    return ok and (tonumber(version) or 42) < 42
end

local function bms_isWalkToward(zombie)
    if not (zombie and zombie.getActionStateName) then return false end
    local ok, state = pcall(function() return zombie:getActionStateName() end)
    state = ok and tostring(state or ""):lower() or ""
    return state == "walktoward" or state == "walktoward-network" or state == "pathfind"
end

local function bms_sameStartedPath(task, x, y, z, tolerance)
    if not (task and task._bms and task._bms.pathStarted) then return false end
    tolerance = tonumber(tolerance) or 0.35
    local px = tonumber(task._bms.pathX)
    local py = tonumber(task._bms.pathY)
    local pz = tonumber(task._bms.pathZ)
    if not px or not py then return false end
    local dx = px - x
    local dy = py - y
    local sameZ = math.floor(pz or z or 0) == math.floor(z or pz or 0)
    return sameZ and dx * dx + dy * dy <= tolerance * tolerance
end

local function bms_shouldHoldExistingB41Path(zombie, task, x, y, z, now)
    if not bms_isB41() then return false end
    if not bms_isWalkToward(zombie) then return false end
    if not (task and task._bms and task._bms.pathStarted) then return false end

    local age = now - (tonumber(task._bms.lastPathAt) or 0)
    if age < (tonumber(NPCMovementStabilityBridge.Config.b41SamePathHoldMs) or 6500) and bms_sameStartedPath(task, x, y, z, 0.75) then return true end

    local critical = task.playerOrder == true
        or task.orderName ~= nil
        or task.orderId ~= nil
        or task.combat == true
        or task.lock == true
        or task.directorState == "MeleeFallback"
        or task.directorState == "Flee"
        or task.directorState == "KeepDistance"
    if critical then return false end

    local holdMs = tonumber(NPCMovementStabilityBridge.Config.b41MovingRetargetHoldMs) or 2200
    if age <= 0 or age > holdMs then return false end
    local px = tonumber(task._bms.pathX)
    local py = tonumber(task._bms.pathY)
    local pz = tonumber(task._bms.pathZ)
    if not px or not py then return false end
    local sameZ = math.floor(pz or z or 0) == math.floor(z or pz or 0)
    if not sameZ then return false end
    local dx = px - x
    local dy = py - y
    local radius = tonumber(NPCMovementStabilityBridge.Config.b41MovingRetargetRadius) or 5.5
    return dx * dx + dy * dy <= radius * radius
end

local bms_getBrain
local bms_moveOwner

local function bms_isMoveAction(action)
    return action == "Move" or action == "GoTo"
end

local function bms_contains(text, needle)
    if text == nil or needle == nil then return false end
    return string.find(string.lower(tostring(text)), string.lower(tostring(needle)), 1, true) ~= nil
end

local function bms_moveOwnerPriority(owner)
    if owner == "combat" then return 100 end
    if owner == "self_preserve" then return 95 end
    if owner == "player_order" then return 90 end
    if owner == "squad_rescue" then return 72 end
    if owner == "movement" then return 48 end
    if owner == "patrol" then return 42 end
    if owner == "squad_cohesion" then return 36 end
    if owner == "supply_need" then return 30 end
    if owner == "base_life" then return 24 end
    if owner == "living_move" then return 18 end
    return 35
end

local function bms_moveOwnerIsAmbient(owner)
    return owner == "living_move"
        or owner == "base_life"
        or owner == "supply_need"
        or owner == "squad_cohesion"
end


local function bms_isSimpleCombatPathingEnabled()
    return NPCMovementStabilityBridge.Config.simpleCombatPathing ~= false
end

local function bms_taskDist2(zombie, task)
    if not (zombie and task and zombie.getX and zombie.getY) then return 999999 end
    local x = tonumber(task.x)
    local y = tonumber(task.y)
    if not x or not y then return 999999 end
    local dx = (tonumber(zombie:getX()) or 0) - x
    local dy = (tonumber(zombie:getY()) or 0) - y
    return dx * dx + dy * dy
end

local function bms_sameFloorTask(zombie, task)
    if not (zombie and task and zombie.getZ) then return true end
    local zNow = math.floor(tonumber(zombie:getZ()) or 0)
    local zTask = math.floor(tonumber(task.z or zNow) or zNow)
    return zNow == zTask
end

local function bms_isSimpleCombatPathTask(zombie, task, brain)
    if not bms_isSimpleCombatPathingEnabled() then return false end
    if not (zombie and task and bms_sameFloorTask(zombie, task)) then return false end
    local owner = task._bms and task._bms.intentOwner or nil
    if owner == nil then owner = bms_moveOwner(task, brain) end
    if owner ~= "combat" then return false end
    local maxDist = tonumber(task.simpleCombatPathDistance) or tonumber(NPCMovementStabilityBridge.Config.simpleCombatPathDistance) or 14
    return bms_taskDist2(zombie, task) <= maxDist * maxDist
end

local function bms_isPlayerControlledBrain(brain)
    return type(brain) == "table"
        and (brain.master ~= nil
            or brain.mercenaryHired == true
            or brain.hired == true
            or brain.isPlayerGuard == true
            or brain.followPlayer ~= nil
            or brain.guardPlayer ~= nil)
end

local function bms_isPlayerOrderTask(task, brain)
    if type(task) ~= "table" then return false end
    if task.allowOrderTeleport == false then return false end
    if task.playerOrder == true or task.orderName ~= nil or task.orderId ~= nil then return true end
    if task._bms and task._bms.intentOwner == "player_order" then return true end
    if not bms_isPlayerControlledBrain(brain) then return false end

    local order = type(brain.order) == "table" and brain.order or nil
    if order and (order.source == "player" or order.master ~= nil or order.interrupt == true) then return true end

    local reason = tostring(task.directorReason or task.reason or task.note or "")
    local state = tostring(task.directorState or task.state or "")
    return bms_contains(reason, "order")
        or bms_contains(reason, "companion")
        or bms_contains(reason, "mercenary")
        or state == "HoldPosition"
        or state == "GuardArea"
        or state == "LootArea"
        or state == "FollowPlayer"
end


local function bms_floorZ(value)
    return math.floor(tonumber(value) or 0)
end

local function bms_isCrossFloorPlayerOrder(zombie, task, brain)
    if not (zombie and task and bms_isMoveAction(task.action)) then return false end
    if not bms_isPlayerOrderTask(task, brain) then return false end

    local zNow = zombie.getZ and zombie:getZ() or 0
    local zTarget = tonumber(task.z)
    if not zTarget then return false end
    if bms_floorZ(zNow) == bms_floorZ(zTarget) then return false end

    local tx = tonumber(task.x)
    local ty = tonumber(task.y)
    if not tx or not ty then return false end

    local maxDist = tonumber(task.orderTeleportMaxDist)
        or tonumber(NPCMovementStabilityBridge.Config.crossFloorOrderMaxDist)
        or tonumber(NPCMovementStabilityBridge.Config.playerOrderTeleportMaxDist)
        or 110
    if maxDist > 0 and bms_dist2(zombie:getX(), zombie:getY(), tx, ty) > maxDist * maxDist then
        return false
    end

    return true
end

local function bms_markCrossFloorPlayerOrder(zombie, task, brain)
    if not bms_isCrossFloorPlayerOrder(zombie, task, brain) then return false end

    task._bms = task._bms or {}
    task._bms.crossFloorOrder = true
    task._bms.crossFloorFromZ = zombie.getZ and zombie:getZ() or nil
    task._bms.crossFloorTargetZ = task.z
    task._bms.crossFloorMarkedAt = task._bms.crossFloorMarkedAt or bms_now()

    local fastMs = tonumber(NPCMovementStabilityBridge.Config.crossFloorOrderTeleportAfterMs) or 260
    local currentMs = tonumber(task.orderTeleportAfterMs)
    if not currentMs or currentMs > fastMs then task.orderTeleportAfterMs = fastMs end

    local maxDist = tonumber(task.orderTeleportMaxDist)
    local cfgMaxDist = tonumber(NPCMovementStabilityBridge.Config.crossFloorOrderMaxDist) or 110
    if not maxDist or maxDist <= 0 or maxDist > cfgMaxDist then task.orderTeleportMaxDist = cfgMaxDist end

    task.arriveDist = math.max(tonumber(task.arriveDist) or 0.9, 1.05)
    task.crossFloorOrder = true
    return true
end

local function bms_crossFloorOrderReadyForFallback(zombie, task, brain, now)
    if not task or not task._bms then return false end
    if task._bms.orderTeleported == true then return false end
    if not (task._bms.crossFloorOrder == true or task.crossFloorOrder == true) then
        if not bms_markCrossFloorPlayerOrder(zombie, task, brain) then return false end
    end

    local startedAt = tonumber(task._bms.startedAt) or tonumber(task._bms.crossFloorMarkedAt) or now
    local minMs = tonumber(task.orderTeleportAfterMs)
        or tonumber(NPCMovementStabilityBridge.Config.crossFloorOrderTeleportAfterMs)
        or 260
    return now - startedAt >= minMs
end

bms_moveOwner = function(task, brain)
    if not task then return "movement", bms_moveOwnerPriority("movement") end

    local state = tostring(task.directorState or task.state or "")
    local reason = tostring(task.directorReason or task.reason or task.note or "")
    local action = tostring(task.action or "")

    if brain and (brain.master ~= nil or brain.mercenaryHired == true or brain.hired == true or brain.isPlayerGuard == true) then
        if bms_contains(reason, "order") or bms_contains(reason, "mercenary") or bms_contains(reason, "companion") or bms_contains(state, "companion") then
            return "player_order", bms_moveOwnerPriority("player_order")
        end
    end

    if task.playerOrder or task.orderId or task.orderName or bms_contains(reason, "player order") or bms_contains(reason, "ordered") then
        return "player_order", bms_moveOwnerPriority("player_order")
    end

    if task.combatMove or task.combatTask or bms_contains(reason, "combat") or bms_contains(reason, "enemy") or bms_contains(reason, "target") or bms_contains(reason, "spotted") or bms_contains(state, "attack") or bms_contains(state, "melee") or bms_contains(state, "reload") or bms_contains(action, "combat") then
        return "combat", bms_moveOwnerPriority("combat")
    end

    if task.flee or task.escape or bms_contains(reason, "flee") or bms_contains(reason, "escape") or bms_contains(reason, "danger") or bms_contains(reason, "preserve") or bms_contains(state, "flee") then
        return "self_preserve", bms_moveOwnerPriority("self_preserve")
    end

    if task.squadSupport then
        if bms_contains(reason, "wounded") or bms_contains(reason, "rescue") or bms_contains(reason, "stabilize") then
            return "squad_rescue", bms_moveOwnerPriority("squad_rescue")
        end
        return "squad_cohesion", bms_moveOwnerPriority("squad_cohesion")
    end

    if task.baseDailyLife or task.baseDuty then
        return "base_life", bms_moveOwnerPriority("base_life")
    end

    if task.supplyNeed or task.lootNeed then
        return "supply_need", bms_moveOwnerPriority("supply_need")
    end

    if task.livingIntent or task.livingMoveIntent then
        return "living_move", bms_moveOwnerPriority("living_move")
    end

    if bms_contains(reason, "patrol") or bms_contains(reason, "regroup") or bms_contains(reason, "return") or bms_contains(state, "patrol") or bms_contains(state, "regroup") then
        return "patrol", bms_moveOwnerPriority("patrol")
    end

    return "movement", bms_moveOwnerPriority("movement")
end

local function bms_sameMoveTarget(ax, ay, az, bx, by, bz, radius)
    ax = tonumber(ax); ay = tonumber(ay); bx = tonumber(bx); by = tonumber(by)
    if not ax or not ay or not bx or not by then return false end
    radius = tonumber(radius) or (NPCMovementStabilityBridge.Config.movementIntentSameRadius or 0.85)
    local sameZ = math.floor(tonumber(az) or 0) == math.floor(tonumber(bz) or 0)
    return sameZ and bms_dist2(ax, ay, bx, by) <= radius * radius
end

local function bms_getMovementIntent(brain)
    if not brain then return nil end
    brain.ai = brain.ai or {}
    brain.ai.movementIntent = brain.ai.movementIntent or {nextId = 0, history = {}}
    return brain.ai.movementIntent
end

local function bms_pruneMovementHistory(intent, now)
    if not intent or type(intent.history) ~= "table" then return end
    local window = tonumber(NPCMovementStabilityBridge.Config.movementIntentLoopWindowMs) or 26000
    local maxHistory = tonumber(NPCMovementStabilityBridge.Config.movementIntentHistoryMax) or 10
    local kept = {}
    for _, entry in ipairs(intent.history) do
        if entry and entry.t and now - entry.t <= window then
            kept[#kept + 1] = entry
        end
    end
    while #kept > maxHistory do
        table.remove(kept, 1)
    end
    intent.history = kept
end

local function bms_noteMovementHistory(intent, task, owner, status, now)
    if not intent or not task then return end
    now = now or bms_now()
    bms_pruneMovementHistory(intent, now)
    intent.history = intent.history or {}
    intent.history[#intent.history + 1] = {
        x = tonumber(task.x),
        y = tonumber(task.y),
        z = tonumber(task.z),
        owner = owner or (task._bms and task._bms.intentOwner) or "movement",
        status = status or "done",
        t = now
    }
    bms_pruneMovementHistory(intent, now)
end

local function bms_detectAmbientMoveLoop(intent, task, owner, now)
    if not (intent and task and task.x and task.y) then return false end
    if not bms_moveOwnerIsAmbient(owner) then return false end

    bms_pruneMovementHistory(intent, now)
    local history = intent.history or {}
    local count = 0
    local unique = {}
    local sameHits = 0
    local radius = tonumber(NPCMovementStabilityBridge.Config.movementIntentSameRadius) or 0.85

    for _, entry in ipairs(history) do
        if entry and bms_moveOwnerIsAmbient(entry.owner) then
            count = count + 1
            local qx = math.floor((tonumber(entry.x) or 0) + 0.5)
            local qy = math.floor((tonumber(entry.y) or 0) + 0.5)
            local qz = math.floor(tonumber(entry.z) or 0)
            unique[tostring(qx) .. ":" .. tostring(qy) .. ":" .. tostring(qz)] = true
            if bms_sameMoveTarget(entry.x, entry.y, entry.z, task.x, task.y, task.z, radius) then
                sameHits = sameHits + 1
            end
        end
    end

    local uniqueCount = 0
    for _ in pairs(unique) do uniqueCount = uniqueCount + 1 end

    local maxCount = tonumber(NPCMovementStabilityBridge.Config.movementIntentLoopMax) or 4
    local maxUnique = tonumber(NPCMovementStabilityBridge.Config.movementIntentLoopUniqueMax) or 3
    if sameHits >= 2 then return true end
    if count >= maxCount and uniqueCount <= maxUnique then return true end
    return false
end

local function bms_cancelMoveIntent(task, reason)
    if not task then return false end
    task._bms = task._bms or {}
    task._bms.cancelled = true
    task._bms.cancelReason = reason or "movement intent denied"
    task.arriveDist = math.max(tonumber(task.arriveDist) or 0.9, 99)
    return false
end

local function bms_acquireMovementIntent(zombie, task, actionName)
    if not zombie or not task or not bms_isMoveAction(actionName or task.action) then return true end

    local brain = bms_getBrain(zombie)
    if not brain then return true end

    local now = bms_now()
    local owner, priority = bms_moveOwner(task, brain)
    local intent = bms_getMovementIntent(brain)
    if not intent then return true end
    bms_pruneMovementHistory(intent, now)

    if intent.suppressAmbientUntil and now < intent.suppressAmbientUntil and bms_moveOwnerIsAmbient(owner) then
        if NPCDiagnosticsBridge and NPCDiagnosticsBridge.TraceMovementEvent then
            NPCDiagnosticsBridge.TraceMovementEvent("intent_denied", zombie, task, {owner=owner, priority=priority, denyReason=intent.suppressReason or "ambient movement suppressed", suppressUntil=intent.suppressAmbientUntil}, false)
        end
        return bms_cancelMoveIntent(task, intent.suppressReason or "ambient movement suppressed")
    end

    if bms_detectAmbientMoveLoop(intent, task, owner, now) then
        intent.suppressAmbientUntil = now + (tonumber(NPCMovementStabilityBridge.Config.movementIntentSuppressMs) or 18000)
        intent.suppressReason = "ambient movement loop"
        if NPCDiagnosticsBridge and NPCDiagnosticsBridge.TraceMovementEvent then
            NPCDiagnosticsBridge.TraceMovementEvent("intent_loop_suppressed", zombie, task, {owner=owner, priority=priority, suppressMs=NPCMovementStabilityBridge.Config.movementIntentSuppressMs}, true)
        end
        return bms_cancelMoveIntent(task, "ambient movement loop")
    end

    local active = intent.active
    local activeValid = active and active.untilMs and now < active.untilMs
    if activeValid then
        local sameTarget = bms_sameMoveTarget(active.x, active.y, active.z, task.x, task.y, task.z, NPCMovementStabilityBridge.Config.movementIntentSameRadius)
        local activePriority = tonumber(active.priority) or 0
        if activePriority > priority and not sameTarget then
            if NPCDiagnosticsBridge and NPCDiagnosticsBridge.TraceMovementEvent then
                NPCDiagnosticsBridge.TraceMovementEvent("intent_denied", zombie, task, {owner=owner, priority=priority, activeOwner=active.owner, activePriority=activePriority, denyReason="higher priority movement intent active"}, false)
            end
            return bms_cancelMoveIntent(task, "higher priority movement intent active")
        end
        if sameTarget and (active.owner == owner or activePriority >= priority) and now - (active.startedAt or now) < (tonumber(NPCMovementStabilityBridge.Config.movementIntentOwnerHoldMs) or 4200) then
            if NPCDiagnosticsBridge and NPCDiagnosticsBridge.TraceMovementEvent then
                NPCDiagnosticsBridge.TraceMovementEvent("intent_denied", zombie, task, {owner=owner, priority=priority, activeOwner=active.owner, activePriority=activePriority, denyReason="duplicate movement target"}, false)
            end
            return bms_cancelMoveIntent(task, "duplicate movement target")
        end
    end

    if owner == "combat" and intent.lastCombatAt and now - intent.lastCombatAt < (tonumber(NPCMovementStabilityBridge.Config.combatMoveCooldownMs) or 1350) then
        if bms_sameMoveTarget(intent.lastCombatX, intent.lastCombatY, intent.lastCombatZ, task.x, task.y, task.z, NPCMovementStabilityBridge.Config.combatMoveSameRadius or 1.35) then
            if NPCDiagnosticsBridge and NPCDiagnosticsBridge.TraceMovementEvent then
                NPCDiagnosticsBridge.TraceMovementEvent("intent_denied", zombie, task, {owner=owner, priority=priority, denyReason="combat movement cooldown"}, false)
            end
            return bms_cancelMoveIntent(task, "combat movement cooldown")
        end
    end

    if intent.lastX and intent.lastY and intent.lastAt and now - intent.lastAt < (tonumber(NPCMovementStabilityBridge.Config.movementIntentSameTargetMs) or 14000) then
        if bms_moveOwnerIsAmbient(owner) and bms_sameMoveTarget(intent.lastX, intent.lastY, intent.lastZ, task.x, task.y, task.z, NPCMovementStabilityBridge.Config.movementIntentSameRadius) then
            intent.suppressAmbientUntil = now + math.floor((tonumber(NPCMovementStabilityBridge.Config.movementIntentSuppressMs) or 18000) * 0.75)
            intent.suppressReason = "repeat movement target"
            if NPCDiagnosticsBridge and NPCDiagnosticsBridge.TraceMovementEvent then
                NPCDiagnosticsBridge.TraceMovementEvent("intent_repeat_suppressed", zombie, task, {owner=owner, priority=priority, lastX=intent.lastX, lastY=intent.lastY}, true)
            end
            return bms_cancelMoveIntent(task, "repeat movement target")
        end
    end

    intent.nextId = (tonumber(intent.nextId) or 0) + 1
    local ttl = bms_moveOwnerIsAmbient(owner) and (tonumber(NPCMovementStabilityBridge.Config.movementIntentTtlMs) or 14000) or (tonumber(NPCMovementStabilityBridge.Config.movementIntentCriticalTtlMs) or 26000)
    intent.active = {
        id = intent.nextId,
        owner = owner,
        priority = priority,
        x = tonumber(task.x),
        y = tonumber(task.y),
        z = tonumber(task.z),
        action = actionName or task.action,
        reason = task.directorReason or task.reason,
        startedAt = now,
        untilMs = now + ttl
    }
    intent.lastX = tonumber(task.x)
    intent.lastY = tonumber(task.y)
    intent.lastZ = tonumber(task.z)
    intent.lastAt = now
    intent.lastOwner = owner

    task._bms = task._bms or {}
    task._bms.intentId = intent.nextId
    task._bms.intentOwner = owner
    task._bms.intentPriority = priority
    task._bms.intentStartedAt = now
    task._bms.intentUntilMs = now + ttl
    if NPCDiagnosticsBridge and NPCDiagnosticsBridge.TraceMovementEvent then
        NPCDiagnosticsBridge.TraceMovementEvent("intent_acquired", zombie, task, {owner=owner, priority=priority, ttlMs=ttl}, false)
    end
    return true
end

local function bms_releaseMovementIntent(zombie, task, status, reason)
    if not zombie or not task then return end
    local brain = bms_getBrain(zombie)
    local intent = brain and brain.ai and brain.ai.movementIntent or nil
    if not intent then return end
    local now = bms_now()
    local owner = task._bms and task._bms.intentOwner or nil

    bms_noteMovementHistory(intent, task, owner, status or "done", now)

    if task._bms and task._bms.intentId and intent.active and intent.active.id == task._bms.intentId then
        intent.completedAt = now
        intent.completedStatus = status or "done"
        intent.completedReason = reason
        intent.active = nil
    elseif intent.active and bms_sameMoveTarget(intent.active.x, intent.active.y, intent.active.z, task.x, task.y, task.z, NPCMovementStabilityBridge.Config.movementIntentSameRadius) then
        intent.active = nil
    end

    if owner == "combat" and task.x and task.y then
        intent.lastCombatX = tonumber(task.x)
        intent.lastCombatY = tonumber(task.y)
        intent.lastCombatZ = tonumber(task.z)
        intent.lastCombatAt = now
    end

    if bms_moveOwnerIsAmbient(owner) and (status == "failed" or status == "dropped" or status == "cancelled") then
        intent.suppressAmbientUntil = math.max(tonumber(intent.suppressAmbientUntil) or 0, now + (tonumber(NPCMovementStabilityBridge.Config.movementIntentSuppressMs) or 18000))
        intent.suppressReason = reason or status or "ambient movement failed"
    end
    if NPCDiagnosticsBridge and NPCDiagnosticsBridge.TraceMovementEvent then
        NPCDiagnosticsBridge.TraceMovementEvent("intent_released", zombie, task, {owner=owner, status=status, releaseReason=reason, suppressUntil=intent.suppressAmbientUntil}, status ~= "done")
    end
end

local function bms_isAmbientMoveTask(task)
    return task and task._bms and bms_moveOwnerIsAmbient(task._bms.intentOwner)
end

local function bms_isCombatAction(action)
    return action == "Shoot"
        or action == "Aim"
        or action == "Hit"
        or action == "Shove"
        or action == "Reload"
end

bms_getBrain = function(zombie)
    if not zombie or not NPCBrainData or not NPCBrainData.Get then return nil end

    local ok, brain = pcall(function()
        return NPCBrainData.Get(zombie)
    end)

    if ok then return brain end
    return nil
end

local function bms_isCriticalB41PathTask(task)
    if not task then return false end
    if task.playerOrder == true
        or task.playerAnchorHouseOrder == true
        or task.orderName ~= nil
        or task.orderId ~= nil
        or task.combat == true
        or task.lock == true
        or task.vehiclePartArea ~= nil
        or task.forcePath == true
        or task.urgent == true then
        return true
    end

    local owner = task._bms and task._bms.intentOwner or nil
    if owner == "combat" or owner == "self_preserve" or owner == "player_order" or owner == "squad_rescue" then
        return true
    end

    local action = tostring(task.action or task.type or "")
    if bms_isCombatAction(action) then return true end

    local state = tostring(task.directorState or task.state or task.reason or task.intent or "")
    state = string.lower(state)
    return string.find(state, "flee", 1, true) ~= nil
        or string.find(state, "melee", 1, true) ~= nil
        or string.find(state, "keepdistance", 1, true) ~= nil
        or string.find(state, "reload", 1, true) ~= nil
        or string.find(state, "emergency", 1, true) ~= nil
        or string.find(state, "defense", 1, true) ~= nil
        or string.find(state, "rescue", 1, true) ~= nil
        or string.find(state, "bandage", 1, true) ~= nil
end

local function bms_noteB41BrainPath(zombie, task, x, y, z, now)
    if not bms_isB41() then return end
    local brain = bms_getBrain(zombie)
    if not brain then return end
    brain.ai = brain.ai or {}
    brain.ai.b41Path2Fuse = brain.ai.b41Path2Fuse or {}
    local fuse = brain.ai.b41Path2Fuse
    fuse.at = now or bms_now()
    fuse.x = tonumber(x)
    fuse.y = tonumber(y)
    fuse.z = tonumber(z or (zombie and zombie.getZ and zombie:getZ()) or 0)
    fuse.critical = bms_isCriticalB41PathTask(task)
end

local function bms_shouldFuseB41BrainPath(zombie, task, x, y, z, now)
    if not bms_isB41() then return false end
    if not bms_isWalkToward(zombie) then return false end
    if bms_isCriticalB41PathTask(task) then return false end

    local brain = bms_getBrain(zombie)
    if not brain or not brain.ai or not brain.ai.b41Path2Fuse then return false end
    local fuse = brain.ai.b41Path2Fuse
    local fx = tonumber(fuse.x)
    local fy = tonumber(fuse.y)
    local fz = tonumber(fuse.z or z or 0)
    local at = tonumber(fuse.at) or 0
    if not fx or not fy or at <= 0 then return false end

    now = now or bms_now()
    local age = now - at
    if age <= 0 then return false end

    local level, zoom = bms_perfLevel()
    local holdMs = tonumber(NPCMovementStabilityBridge.Config.b41BrainPathHoldMs) or 7000
    if level >= 3 then
        holdMs = tonumber(NPCMovementStabilityBridge.Config.b41BrainPathPanicHoldMs) or 18000
    elseif level >= 2 then
        holdMs = tonumber(NPCMovementStabilityBridge.Config.b41BrainPathCriticalHoldMs) or 14000
    elseif level >= 1 then
        holdMs = tonumber(NPCMovementStabilityBridge.Config.b41BrainPathHighHoldMs) or 10500
    end
    if zoom >= 1.70 then holdMs = math.max(holdMs, 11000) end
    if zoom >= 2.10 then holdMs = math.max(holdMs, 15000) end
    if age > holdMs then return false end

    local sameZ = math.floor(fz or 0) == math.floor(tonumber(z or fz or 0) or 0)
    if not sameZ then return false end

    local radius = tonumber(NPCMovementStabilityBridge.Config.b41BrainPathHoldRadius) or 10.0
    if level >= 3 then
        radius = math.max(radius, tonumber(NPCMovementStabilityBridge.Config.b41BrainPathPanicRadius) or 14.0)
    elseif level >= 2 then
        radius = math.max(radius, 12.0)
    elseif level >= 1 then
        radius = math.max(radius, 10.5)
    end
    if zoom >= 2.10 then radius = math.max(radius, 14.0) end

    local tx = tonumber(x)
    local ty = tonumber(y)
    if not tx or not ty then return false end
    local dx = fx - tx
    local dy = fy - ty
    if dx * dx + dy * dy > radius * radius then return false end

    task._bms = task._bms or {}
    task._bms.pathStarted = true
    task._bms.lastPathAt = at
    task._bms.pathX = fx
    task._bms.pathY = fy
    task._bms.pathZ = fz
    task._bms.directMove = false
    task._bms.b41Path2Fused = (tonumber(task._bms.b41Path2Fused) or 0) + 1
    task._bms.b41Path2FusedAt = now

    if NPCDiagnosticsBridge and NPCDiagnosticsBridge.TraceMovementEvent then
        NPCDiagnosticsBridge.TraceMovementEvent("b41_path2_brain_fuse", zombie, task, {age=age, level=level, radius=radius}, false)
    end
    return true
end

local function bms_getCurrentTask(zombie)
    if not zombie or not NPCEntity or not NPCEntity.GetTask then return nil end

    local ok, task = pcall(function()
        return NPCEntity.GetTask(zombie)
    end)

    if ok then return task end
    return nil
end

local function bms_isTerrainBlocked(square)
    if not square then return true end

    local ok, water = pcall(function()
        if IsoFlagType and IsoFlagType.water then
            return square:Is(IsoFlagType.water)
        end
        return false
    end)
    if ok and water then return true end

    local solid = false
    ok, solid = pcall(function()
        return square:isSolid()
    end)
    if ok and solid then return true end

    local solidTrans = false
    ok, solidTrans = pcall(function()
        return square:isSolidTrans()
    end)
    if ok and solidTrans then return true end

    return false
end

function NPCMovementStabilityBridge.IsCombatLocked(zombie)
    local task = bms_getCurrentTask(zombie)
    if task and bms_isCombatAction(task.action) then return true end

    if NPCEntity and NPCEntity.HasActionTask then
        local ok, ret = pcall(function()
            return NPCEntity.HasActionTask(zombie)
        end)
        if ok and ret then return true end
    end

    return false
end

function NPCMovementStabilityBridge.ResetPath(zombie, resetMoving)
    if not zombie then return end

    if NPCUtils and NPCUtils.IsController and NPCUtils.IsController(zombie) then
        local ok, behavior = pcall(function()
            return zombie:getPathFindBehavior2()
        end)

        if ok and behavior then
            pcall(function() behavior:cancel() end)
            pcall(function() behavior:reset() end)
        end
    end

    pcall(function() zombie:setPath2(nil) end)

    if resetMoving ~= false and NPCEntity and NPCEntity.SetMoving then
        pcall(function() NPCEntity.SetMoving(zombie, false) end)
    end
end

function NPCMovementStabilityBridge.GetSquare(x, y, z)
    local cell = getCell()
    if not cell then return nil end
    return cell:getGridSquare(math.floor(x), math.floor(y), math.floor(z or 0))
end

function NPCMovementStabilityBridge.MarkBadTarget(zombie, task, reason)
    local brain = bms_getBrain(zombie)
    if not brain or not task or not task.x or not task.y then return end

    brain.ai = brain.ai or {}
    brain.ai.pathMemory = brain.ai.pathMemory or {}
    brain.ai.pathMemory.badTargets = brain.ai.pathMemory.badTargets or {}

    local key = bms_key(task.x, task.y, task.z or (zombie and zombie:getZ()) or 0)
    local entry = brain.ai.pathMemory.badTargets[key] or {}
    entry.count = (entry.count or 0) + 1
    entry.reason = reason or "stuck"
    entry.x = math.floor(task.x)
    entry.y = math.floor(task.y)
    entry.z = math.floor(task.z or (zombie and zombie:getZ()) or 0)
    entry.untilMs = bms_now() + (NPCMovementStabilityBridge.Config.badTargetCooldownMs or 28000)
    brain.ai.pathMemory.badTargets[key] = entry
    brain.ai.pathMemory.lastBadTarget = entry
end

function NPCMovementStabilityBridge.IsBadTarget(brain, x, y, z)
    if not brain or not brain.ai or not brain.ai.pathMemory or not brain.ai.pathMemory.badTargets then return false end

    local now = bms_now()
    local bad = brain.ai.pathMemory.badTargets
    for key, entry in pairs(bad) do
        if entry and entry.untilMs and now > entry.untilMs then
            bad[key] = nil
        end
    end

    local entry = bad[bms_key(x, y, z)]
    return entry and entry.untilMs and now <= entry.untilMs
end


local function bms_obstacleAdjustmentAllowed(task, now)
    if not task then return true end
    task._bms = task._bms or {}
    local cooldown = tonumber(NPCMovementStabilityBridge.Config.obstacleTargetAdjustCooldownMs) or 8500
    if task._bms.lastObstacleAdjustAt and now - task._bms.lastObstacleAdjustAt < cooldown then
        return false
    end
    return true
end

local function bms_adjustBlockedTarget(zombie, task, now)
    if not zombie or not task or task.vehiclePartArea then return true end
    local x = tonumber(task.x)
    local y = tonumber(task.y)
    local z = tonumber(task.z or zombie:getZ())
    if not x or not y or not z then return true end

    local targetSquare = NPCMovementStabilityBridge.GetSquare(x, y, z)
    if targetSquare and not NPCMovementStabilityBridge.IsSquareBlocked(targetSquare, zombie) then
        return true
    end

    if not bms_obstacleAdjustmentAllowed(task, now or bms_now()) then
        return true
    end

    local radius = tonumber(task.obstacleTargetAdjustRadius) or tonumber(NPCMovementStabilityBridge.Config.obstacleTargetAdjustRadius) or 3
    local alt = NPCMovementStabilityBridge.FindFreeAround(x, y, z, zombie, radius)
    if alt then
        task._bms = task._bms or {}
        task._bms.lastObstacleAdjustAt = now or bms_now()
        task._bms.originalBlockedTargetX = task._bms.originalBlockedTargetX or x
        task._bms.originalBlockedTargetY = task._bms.originalBlockedTargetY or y
        task._bms.originalBlockedTargetZ = task._bms.originalBlockedTargetZ or z
        task._bms.obstacleAdjustedTarget = true
        task.x = alt:getX()
        task.y = alt:getY()
        task.z = alt:getZ()
        return true
    end

    NPCMovementStabilityBridge.MarkBadTarget(zombie, task, "blocked obstacle target")
    return bms_cancelMoveIntent(task, "blocked obstacle target")
end

local function bms_canRequestPath(zombie, task, force, reason)
    if not zombie or not task then return true end

    local x = tonumber(task.x)
    local y = tonumber(task.y)
    local z = tonumber(task.z or zombie:getZ())
    if not x or not y or not z then return true end

    local brain = bms_getBrain(zombie)
    if not brain then return true end

    brain.ai = brain.ai or {}
    brain.ai.pathThrottle = brain.ai.pathThrottle or {}

    local now = bms_now()
    local throttle = brain.ai.pathThrottle
    local minDelay = tonumber(task.pathThrottleMs) or tonumber(NPCMovementStabilityBridge.Config.minPathRequestMs) or 850
    local forcedDelay = tonumber(NPCMovementStabilityBridge.Config.forcedPathRequestMs) or 650
    local sameDelay = tonumber(task.sameTargetPathThrottleMs) or tonumber(NPCMovementStabilityBridge.Config.sameTargetPathRequestMs) or 2600
    local failBackoff = math.min(tonumber(NPCMovementStabilityBridge.Config.maxPathFailBackoffMs) or 6000, (tonumber(throttle.failCount) or 0) * (tonumber(NPCMovementStabilityBridge.Config.pathFailBackoffMs) or 500))
    if bms_isSimpleCombatPathTask(zombie, task, brain) then
        minDelay = math.max(minDelay, tonumber(task.simpleCombatMinPathRequestMs) or tonumber(NPCMovementStabilityBridge.Config.simpleCombatMinPathRequestMs) or 2200)
        sameDelay = math.max(sameDelay, tonumber(task.simpleCombatSameTargetPathRequestMs) or tonumber(NPCMovementStabilityBridge.Config.simpleCombatSameTargetPathRequestMs) or 9800)
        forcedDelay = math.max(forcedDelay, tonumber(task.simpleCombatForcedPathRequestMs) or tonumber(NPCMovementStabilityBridge.Config.simpleCombatForcedPathRequestMs) or 1350)
    end
    local level, zoom = bms_perfLevel()
    if level >= 3 or zoom >= 2.35 then
        minDelay = math.max(minDelay, 2400)
        sameDelay = math.max(sameDelay, 7600)
        forcedDelay = math.max(forcedDelay, 1500)
    elseif level >= 2 or zoom >= 1.90 then
        minDelay = math.max(minDelay, 1900)
        sameDelay = math.max(sameDelay, 6200)
        forcedDelay = math.max(forcedDelay, 1150)
    elseif level >= 1 or zoom >= 1.45 then
        minDelay = math.max(minDelay, 1500)
        sameDelay = math.max(sameDelay, 5200)
        forcedDelay = math.max(forcedDelay, 900)
    end

    if force and minDelay > forcedDelay then
        minDelay = forcedDelay
    end

    local key = bms_key(x, y, z)
    local sameTarget = throttle.key == key
    if not sameTarget and throttle.x and throttle.y then
        local dx = (tonumber(throttle.x) or x) - x
        local dy = (tonumber(throttle.y) or y) - y
        local sameZ = math.floor(tonumber(throttle.z) or z) == math.floor(z)
        sameTarget = sameZ and dx * dx + dy * dy < 2.25
    end

    local requiredDelay = minDelay + failBackoff
    if sameTarget then
        requiredDelay = math.max(requiredDelay, sameDelay + failBackoff)
    end

    if throttle.lastAt and now - throttle.lastAt < requiredDelay then
        throttle.denied = (throttle.denied or 0) + 1
        throttle.lastDeniedAt = now
        throttle.lastDeniedReason = reason or task.action or "path"
        return false
    end

    if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.AllowPathRequest then
        local pathId = brain.id or brain.uid or brain.persistentId or key
        if not NPCWorkSchedulerBridge.AllowPathRequest(pathId, reason or task.action or "path", "npc") then
            throttle.denied = (throttle.denied or 0) + 1
            throttle.globalDenied = (throttle.globalDenied or 0) + 1
            throttle.lastDeniedAt = now
            throttle.lastDeniedReason = "global_budget"
            return false
        end
    end

    throttle.lastAt = now
    throttle.x = x
    throttle.y = y
    throttle.z = z
    throttle.key = key
    throttle.reason = reason or task.action or "path"
    throttle.denied = 0
    return true
end


local function bms_enqueueDeferredStartPath(zombie, task, brain, force, reason)
    if not (NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.EnqueuePathRequest) then return false end
    if not zombie or not task then return false end
    task._bms = task._bms or {}
    local now = bms_now()
    if task._bms.deferredPathQueued and now < (tonumber(task._bms.pathDeferredUntil) or 0) then
        return true
    end

    local critical = bms_isCriticalB41PathTask(task)
    local owner = task._bms.intentOwner or bms_moveOwner(task, brain)
    if owner == "player_order" or owner == "self_preserve" then critical = true end

    local retries = tonumber(task._bms.pathDeferredRetries) or 0
    if retries >= (critical and 3 or 2) then return false end

    local tx = tonumber(task.x)
    local ty = tonumber(task.y)
    local tz = tonumber(task.z or (zombie.getZ and zombie:getZ()) or 0)
    local baseId = brain and (brain.uid or brain.id or brain.persistentId) or tostring(zombie)
    local id = tostring(baseId) .. ":" .. tostring(bms_key(tx or 0, ty or 0, tz or 0)) .. ":" .. tostring(reason or "path")
    local ttl = critical and 2600 or 4300
    local score = critical and 120 or 45
    if owner == "combat" then score = 100 end
    if task._scw or task.coarseWaypoint then score = score + 12 end

    task._bms.deferredPathQueued = true
    task._bms.pathDeferredUntil = now + ttl
    task._bms.pathDeferredReason = reason or "budget_denied"
    task._bms.pathDeferredRetries = retries + 1

    local ok = NPCWorkSchedulerBridge.EnqueuePathRequest(id, function()
        if not zombie or not task then return false end
        local current = bms_getCurrentTask(zombie)
        if current and current ~= task then return false end
        task._bms = task._bms or {}
        task._bms.deferredPathQueued = false
        task._bms.pathDeferredUntil = 0
        task._bms.lastDeferredPathRunAt = bms_now()
        return NPCMovementStabilityBridge.StartPath(zombie, task, true)
    end, reason or "deferred_start_path", critical and "high" or "normal", score, ttl)

    if not ok then
        task._bms.deferredPathQueued = false
        return false
    end
    return true
end

local function bms_notePathFailure(zombie)
    local brain = bms_getBrain(zombie)
    if not brain then return end
    brain.ai = brain.ai or {}
    brain.ai.pathThrottle = brain.ai.pathThrottle or {}
    brain.ai.pathThrottle.failCount = (brain.ai.pathThrottle.failCount or 0) + 1
    brain.ai.pathThrottle.lastFailAt = bms_now()
end

local function bms_notePathProgress(zombie)
    local brain = bms_getBrain(zombie)
    if not brain or not brain.ai or not brain.ai.pathThrottle then return end
    brain.ai.pathThrottle.failCount = 0
end

local function bms_clearPath2(zombie)
    if not zombie then return end

    if NPCUtils and NPCUtils.IsController and NPCUtils.IsController(zombie) then
        local ok, behavior = pcall(function()
            return zombie:getPathFindBehavior2()
        end)

        if ok and behavior then
            pcall(function() behavior:cancel() end)
            pcall(function() behavior:reset() end)
        end
    end

    pcall(function() zombie:setPath2(nil) end)
end

local function bms_directMoveTo(zombie, task)
    if not zombie or not task then return false end
    local x = tonumber(task.x)
    local y = tonumber(task.y)
    local z = tonumber(task.z or zombie:getZ())
    if not x or not y or not z then return false end

    bms_clearPath2(zombie)

    task._bms = task._bms or {}

    -- PZ 41 can log "WalkTowardState but path2 != null" when new path2
    -- requests are issued too often. Callers are throttled before reaching this
    -- point; keep the B41 behavior path branch so movement semantics stay close
    -- to the previous patch.
    if bms_isB41() then
        local ok, behavior = pcall(function()
            return zombie:getPathFindBehavior2()
        end)
        if ok and behavior then
            local pathOk = pcall(function()
                behavior:pathToLocation(math.floor(x), math.floor(y), math.floor(z))
            end)
            task._bms.directMove = false
            return pathOk
        end
        return false
    end

    local ok = pcall(function()
        zombie:pathToLocationF(x + 0.5, y + 0.5, z)
    end)

    task._bms.directMove = true
    return ok
end

local function bms_edgeBlocked(mover, fromSq, toSq)
    if not fromSq or not toSq then return true end

    local dx = toSq:getX() - fromSq:getX()
    local dy = toSq:getY() - fromSq:getY()
    if math.abs(dx) > 1 or math.abs(dy) > 1 then return true end
    if dx == 0 and dy == 0 then return false end

    local ok, blocked = pcall(function()
        return fromSq:testCollideAdjacent(mover, dx, dy, 0)
    end)
    if ok and blocked then return true end

    ok, blocked = pcall(function()
        return fromSq:isBlockedTo(toSq)
    end)
    if ok and blocked then return true end

    ok, blocked = pcall(function()
        return toSq:isBlockedTo(fromSq)
    end)
    if ok and blocked then return true end

    -- Door/window/thumpable state can change without the square becoming solid.
    -- testCollideAdjacent/isBlockedTo are authoritative in B41; this final probe
    -- catches closed frames from the opposite square without forcing a re-path.
    ok, blocked = pcall(function()
        return toSq:testCollideAdjacent(mover, -dx, -dy, 0)
    end)
    if ok and blocked then return true end

    return false
end

local function bms_canStepBetweenSquares(mover, fromSq, toSq)
    if not fromSq or not toSq then return false end
    if NPCMovementStabilityBridge.IsSquareBlocked(toSq, mover) then return false end

    local dx = toSq:getX() - fromSq:getX()
    local dy = toSq:getY() - fromSq:getY()
    if math.abs(dx) > 1 or math.abs(dy) > 1 then return false end
    if dx == 0 and dy == 0 then return true end

    if bms_edgeBlocked(mover, fromSq, toSq) then return false end

    if dx ~= 0 and dy ~= 0 then
        local sideX = NPCMovementStabilityBridge.GetSquare(fromSq:getX() + dx, fromSq:getY(), fromSq:getZ())
        local sideY = NPCMovementStabilityBridge.GetSquare(fromSq:getX(), fromSq:getY() + dy, fromSq:getZ())
        if not sideX or not sideY then return false end
        if NPCMovementStabilityBridge.IsSquareBlocked(sideX, mover) then return false end
        if NPCMovementStabilityBridge.IsSquareBlocked(sideY, mover) then return false end
        if bms_edgeBlocked(mover, fromSq, sideX) then return false end
        if bms_edgeBlocked(mover, fromSq, sideY) then return false end
        if bms_edgeBlocked(mover, sideX, toSq) then return false end
        if bms_edgeBlocked(mover, sideY, toSq) then return false end
    end

    -- Avoid testVisionAdjacent() here. In PZ 41 MP this Java overload may be
    -- unavailable for some IsoGridSquare implementations and opens the Lua
    -- debugger even when wrapped in pcall(). Collision checks above are enough
    -- for the bypass probe; real pathing will still reject invalid movement.

    return true
end

local function bms_canDirectStep(zombie, task)
    if not zombie or not task then return false end

    local z = tonumber(task.z or zombie:getZ())
    if not z or math.floor(zombie:getZ()) ~= math.floor(z) then return false end

    local fromSq = zombie:getSquare()
    if not fromSq then
        fromSq = NPCMovementStabilityBridge.GetSquare(zombie:getX(), zombie:getY(), z)
    end
    if not fromSq then return false end

    local toSq = NPCMovementStabilityBridge.GetSquare(task.x, task.y, z)
    if not toSq then return false end

    local dx = toSq:getX() - fromSq:getX()
    local dy = toSq:getY() - fromSq:getY()
    if math.abs(dx) > 1 or math.abs(dy) > 1 then return false end

    return bms_canStepBetweenSquares(zombie, fromSq, toSq)
end

local function bms_pathfindTo(zombie, task)
    if not zombie or not task then return false end

    local x = tonumber(task.x)
    local y = tonumber(task.y)
    local z = tonumber(task.z or zombie:getZ())
    if not x or not y or not z then return false end

    local ok, behavior = pcall(function()
        return zombie:getPathFindBehavior2()
    end)
    if not ok or not behavior then return false end

    local pathOk = pcall(function()
        behavior:pathToLocation(math.floor(x), math.floor(y), math.floor(z))
    end)

    task._bms = task._bms or {}
    task._bms.directMove = false
    return pathOk
end

local function bms_stepBlocked(zombie, sx, sy, tx, ty, z)
    local fromSq = NPCMovementStabilityBridge.GetSquare(sx, sy, z)
    local toSq = NPCMovementStabilityBridge.GetSquare(tx, ty, z)
    if not fromSq or not toSq then return true end

    return not bms_canStepBetweenSquares(zombie, fromSq, toSq)
end

function NPCMovementStabilityBridge.FindBypassAroundCurrent(zombie, task)
    if not zombie or not task then return nil end

    local z = task.z or zombie:getZ()
    local zx = zombie:getX()
    local zy = zombie:getY()
    local cx = math.floor(zx)
    local cy = math.floor(zy)
    local tx = tonumber(task.x) or cx
    local ty = tonumber(task.y) or cy
    local vx = tx - zx
    local vy = ty - zy

    if vx == 0 and vy == 0 then return nil end

    local sx = 0
    local sy = 0
    if math.abs(vx) >= math.abs(vy) then
        sx = vx >= 0 and 1 or -1
        if math.abs(vy) > 0.35 then sy = vy >= 0 and 1 or -1 end
    else
        sy = vy >= 0 and 1 or -1
        if math.abs(vx) > 0.35 then sx = vx >= 0 and 1 or -1 end
    end

    local px = -sy
    local py = sx

    local candidates = {
        {x = cx + px, y = cy + py},
        {x = cx - px, y = cy - py},
        {x = cx + px * 2, y = cy + py * 2},
        {x = cx - px * 2, y = cy - py * 2},
        {x = cx - sx, y = cy - sy},
    }

    local best = nil
    local bestScore = math.huge
    for _, c in ipairs(candidates) do
        local bx = math.floor(c.x + 0.5)
        local by = math.floor(c.y + 0.5)
        local sq = NPCMovementStabilityBridge.GetSquare(bx, by, z)
        if sq and not bms_stepBlocked(zombie, cx, cy, bx, by, z) then
            local score = bms_dist2(bx, by, tx, ty) + bms_dist2(bx, by, zx, zy) * 0.2
            if score < bestScore then
                bestScore = score
                best = sq
            end
        end
    end

    if best then return best end
    return NPCMovementStabilityBridge.FindFreeAround(cx, cy, z, zombie, 3)
end

function NPCMovementStabilityBridge.IsSquareBlocked(square, mover)
    if not square then return true end
    if bms_isTerrainBlocked(square) then return true end

    -- square:isFree(false) is often false because the NPC itself stands on it.
    -- Treat that as blocked only when the square has no moving objects at all;
    -- otherwise the moving-object test below decides whether it is a real crowd block.
    local ok, free = pcall(function()
        return square:isFree(false)
    end)
    if ok and free == false then
        local okObjects, mlist = pcall(function()
            return square:getMovingObjects()
        end)
        if not okObjects or not mlist or mlist:size() == 0 then
            return true
        end
    end

    if mover then
        local okObjects, mlist = pcall(function()
            return square:getMovingObjects()
        end)

        if okObjects and mlist and mlist:size() > 0 then
            for i=0, mlist:size() - 1 do
                local obj = mlist:get(i)
                if obj and obj ~= mover then
                    if instanceof(obj, "IsoZombie") or instanceof(obj, "IsoPlayer") then
                        return true
                    end
                end
            end
        end
    end

    return false
end

function NPCMovementStabilityBridge.FindFreeAround(x, y, z, mover, radius)
    radius = radius or 4
    local cell = getCell()
    if not cell then return nil end

    local bx = math.floor(x)
    local by = math.floor(y)
    local bz = math.floor(z or 0)

    local best = nil
    local bestScore = math.huge
    local mx = mover and mover:getX() or x
    local my = mover and mover:getY() or y
    local brain = bms_getBrain(mover)

    for r=0, radius do
        for dx=-r, r do
            for dy=-r, r do
                if r == 0 or math.abs(dx) == r or math.abs(dy) == r then
                    local square = cell:getGridSquare(bx + dx, by + dy, bz)
                    if square and not NPCMovementStabilityBridge.IsSquareBlocked(square, mover) then
                        local score = bms_dist2(mx, my, square:getX() + 0.5, square:getY() + 0.5) + (r * 0.15)
                        if NPCNavigationPerformanceBridge and NPCNavigationPerformanceBridge.GetSquareCost then
                            local okCost, navCost = pcall(function()
                                return NPCNavigationPerformanceBridge.GetSquareCost(mover, brain, square, x, y, "free square search")
                            end)
                            if okCost and navCost then
                                score = score + navCost
                            end
                        end
                        if NPCHumanizedAIBridge and NPCHumanizedAIBridge.ScoreMoveSquare then
                            local okScore, humanScore = pcall(function()
                                return NPCHumanizedAIBridge.ScoreMoveSquare(mover, brain, square, x, y, nil, "free square search")
                            end)
                            if okScore and humanScore then
                                score = score - (humanScore * 0.18)
                            end
                        end
                        if score < bestScore then
                            bestScore = score
                            best = square
                        end
                    end
                end
            end
        end
        if best then return best end
    end

    return nil
end


function NPCMovementStabilityBridge.CanStepBetween(mover, fromSq, toSq)
    return bms_canStepBetweenSquares(mover, fromSq, toSq)
end

local function bms_playerOrderTeleportToTarget(zombie, task, brain, reason)
    if not (zombie and task and bms_isMoveAction(task.action)) then return false end
    if NPCMovementStabilityBridge.Config.playerOrderTeleportFallback == false then return false end
    if NPCMovementStabilityBridge.IsCombatLocked(zombie) then return false end
    if not bms_isPlayerOrderTask(task, brain) then return false end

    task._bms = task._bms or {}
    if task._bms.orderTeleported == true then return false end

    local now = bms_now()
    local startedAt = tonumber(task._bms.startedAt) or now
    local minMs = tonumber(task.orderTeleportAfterMs) or tonumber(NPCMovementStabilityBridge.Config.playerOrderTeleportAfterMs) or 1250
    if now - startedAt < minMs and task._bms.spinLoop ~= true and (tonumber(task._bms.replans) or 0) < 1 then
        return false
    end

    local tx = tonumber(task.x)
    local ty = tonumber(task.y)
    local tz = tonumber(task.z) or (zombie.getZ and zombie:getZ()) or 0
    if not tx or not ty then return false end

    local maxDist = tonumber(task.orderTeleportMaxDist) or tonumber(NPCMovementStabilityBridge.Config.playerOrderTeleportMaxDist) or 140
    if maxDist > 0 then
        local d2 = bms_dist2(zombie:getX(), zombie:getY(), tx, ty)
        if d2 > maxDist * maxDist then return false end
    end

    local targetSquare = NPCMovementStabilityBridge.GetSquare(tx, ty, tz)
    local square = targetSquare
    if (not square) or NPCMovementStabilityBridge.IsSquareBlocked(square, zombie) then
        local searchRadius = tonumber(task.orderTeleportSearchRadius)
            or (task._bms and task._bms.crossFloorOrder and tonumber(NPCMovementStabilityBridge.Config.crossFloorOrderSearchRadius))
            or tonumber(NPCMovementStabilityBridge.Config.playerOrderTeleportSearchRadius)
            or 5
        square = NPCMovementStabilityBridge.FindFreeAround(tx, ty, tz, zombie, searchRadius)
    end
    if not square and targetSquare and not bms_isTerrainBlocked(targetSquare) then
        square = targetSquare
    end
    if not square then return false end

    NPCMovementStabilityBridge.ResetPath(zombie, true)

    local sx = square:getX()
    local sy = square:getY()
    local sz = square:getZ()
    if zombie.setTarget then pcall(function() zombie:setTarget(nil) end) end
    if zombie.setAttackedBy then pcall(function() zombie:setAttackedBy(nil) end) end
    if zombie.clearAggroList then pcall(function() zombie:clearAggroList() end) end
    if zombie.setX then pcall(function() zombie:setX(sx + 0.5) end) end
    if zombie.setY then pcall(function() zombie:setY(sy + 0.5) end) end
    if zombie.setZ then pcall(function() zombie:setZ(sz) end) end

    task.x = sx
    task.y = sy
    task.z = sz
    task.arriveDist = math.max(tonumber(task.arriveDist) or 0.9, 1.05)
    task._bms.orderTeleported = true
    task._bms.orderTeleportReason = reason or "player order path fallback"
    task._bms.lastMoveAt = now
    task._bms.lastProgressAt = now
    task._bms.lastX = sx + 0.5
    task._bms.lastY = sy + 0.5
    task._bms.spinScore = 0

    if brain then
        brain.x = sx + 0.5
        brain.y = sy + 0.5
        brain.z = sz
        brain.debugCoords = {x=sx + 0.5, y=sy + 0.5, z=sz}
        brain.watchdog = brain.watchdog or {}
        brain.watchdog.stuck = false
        brain.watchdog.lastOrderTeleportAtMs = now
        brain.watchdog.lastOrderTeleportReason = reason or "player order path fallback"
    end

    if NPCEntity and NPCEntity.SetMoving then
        pcall(function() NPCEntity.SetMoving(zombie, false) end)
    end
    if NPCDiagnosticsBridge and NPCDiagnosticsBridge.TraceMovementEvent then
        NPCDiagnosticsBridge.TraceMovementEvent("player_order_teleport_fallback", zombie, task, {reason=reason or "player_order_path_fallback"}, false)
    end
    return true
end

function NPCMovementStabilityBridge.FindReachableAround(zombie, radius, scoreFn)
    if not zombie then return nil end
    radius = radius or NPCMovementStabilityBridge.Config.localEscapeRadius or 5

    local start = zombie:getSquare()
    if not start then return nil end

    local cell = getCell()
    if not cell then return nil end

    local sx = start:getX()
    local sy = start:getY()
    local sz = start:getZ()
    local buf = bms_getBuffer("reachable")
    buf.sq = buf.sq or {}
    buf.d = buf.d or {}
    buf.seen = buf.seen or {}
    buf.seenKeys = buf.seenKeys or {}

    local queueSq = buf.sq
    local queueD = buf.d
    local seen = buf.seen
    local seenKeys = buf.seenKeys
    local oldQueueN = tonumber(buf.queueN) or #queueSq
    local oldSeenN = tonumber(buf.seenN) or #seenKeys
    for i = 1, oldQueueN do
        queueSq[i] = nil
        queueD[i] = nil
    end
    for i = 1, oldSeenN do
        seen[seenKeys[i]] = nil
        seenKeys[i] = nil
    end

    local qIndex = 1
    local qCount = 1
    local seenCount = 1
    local startKey = bms_key(sx, sy, sz)
    queueSq[1] = start
    queueD[1] = 0
    seen[startKey] = true
    seenKeys[1] = startKey

    local best = nil
    local bestScore = -1000000
    local brain = nil

    while qIndex <= qCount do
        local sq = queueSq[qIndex]
        local depth = queueD[qIndex] or 0
        qIndex = qIndex + 1

        local score = 0
        if scoreFn then
            local ok, s = pcall(function()
                return scoreFn(sq, depth)
            end)
            if ok and s then score = s end
        else
            score = -depth
        end

        if depth > 0 and not NPCMovementStabilityBridge.IsSquareBlocked(sq, zombie) then
            if NPCNavigationPerformanceBridge and NPCNavigationPerformanceBridge.GetSquareCost then
                brain = brain or bms_getBrain(zombie)
                local okCost, navCost = pcall(function()
                    return NPCNavigationPerformanceBridge.GetSquareCost(zombie, brain, sq, nil, nil, "reachable search")
                end)
                if okCost and navCost then
                    score = score - navCost
                end
            end
            if score > bestScore then
                bestScore = score
                best = sq
            end
        end

        if depth < radius then
            local baseX = sq:getX()
            local baseY = sq:getY()
            for dx=-1, 1 do
                for dy=-1, 1 do
                    if not (dx == 0 and dy == 0) then
                        local nx = baseX + dx
                        local ny = baseY + dy
                        local key = bms_key(nx, ny, sz)
                        if not seen[key] then
                            seen[key] = true
                            seenCount = seenCount + 1
                            seenKeys[seenCount] = key
                            local nsq = cell:getGridSquare(nx, ny, sz)
                            if nsq and NPCMovementStabilityBridge.CanStepBetween(zombie, sq, nsq) then
                                qCount = qCount + 1
                                queueSq[qCount] = nsq
                                queueD[qCount] = depth + 1
                            end
                        end
                    end
                end
            end
        end
    end

    buf.queueN = qCount
    buf.seenN = seenCount
    return best
end

function NPCMovementStabilityBridge.FindRecoverySquare(zombie, task)
    if not zombie then return nil end

    local zx = zombie:getX()
    local zy = zombie:getY()
    local zz = zombie:getZ()
    local tx = task and tonumber(task.x) or zx
    local ty = task and tonumber(task.y) or zy
    local replans = task and task._bms and (task._bms.replans or 0) or 0

    local vx = tx - zx
    local vy = ty - zy
    local vlen = math.sqrt(vx * vx + vy * vy)
    if vlen < 0.01 then vlen = 1 end
    vx = vx / vlen
    vy = vy / vlen

    local scoreFn = function(sq, depth)
        local sx = sq:getX() + 0.5
        local sy = sq:getY() + 0.5
        local away = ((sx - zx) * -vx + (sy - zy) * -vy) * 3.0
        local side = math.abs((sx - zx) * -vy + (sy - zy) * vx) * 1.4
        local progress = -math.sqrt(bms_dist2(sx, sy, tx, ty)) * 0.35
        local roadScore = 0
        if NPCRoadNavBridge and NPCRoadNavBridge.ScorePoint then
            local ok, score, class = pcall(function()
                return NPCRoadNavBridge.ScorePoint(sx, sy)
            end)
            if ok and score then
                if class == "road" then roadScore = 5
                elseif class == "town" then roadScore = 2
                elseif class == "blocked" then roadScore = -20 end
            end
        end
        local navPenalty = 0
        if NPCNavigationPerformanceBridge and NPCNavigationPerformanceBridge.GetSquareCost then
            local brain = bms_getBrain(zombie)
            local okCost, cost = pcall(function()
                return NPCNavigationPerformanceBridge.GetSquareCost(zombie, brain, sq, tx, ty, "recovery search")
            end)
            if okCost and cost then navPenalty = cost end
        end
        return away + side + progress + roadScore - navPenalty - (depth * 0.2)
    end

    local localEscape = NPCMovementStabilityBridge.FindReachableAround(zombie, NPCMovementStabilityBridge.Config.localEscapeRadius or 5, scoreFn)
    if localEscape then return localEscape end

    if task and task.x and task.y then
        local bypass = NPCMovementStabilityBridge.FindBypassAroundCurrent(zombie, task)
        if bypass then return bypass end

        local free = NPCMovementStabilityBridge.FindFreeAround(task.x, task.y, task.z or zz, zombie, NPCMovementStabilityBridge.Config.targetSearchRadius or 8)
        if free then return free end
    end

    if NPCRoadNavBridge and NPCRoadNavBridge.FindLoadedTownOrRoadAround then
        local ok, preferred = pcall(function()
            return NPCRoadNavBridge.FindLoadedTownOrRoadAround(zx, zy, zz, 42)
        end)
        if ok and preferred and preferred.x and preferred.y then
            return NPCMovementStabilityBridge.GetSquare(preferred.x, preferred.y, preferred.z or zz)
        end
    end

    return nil
end

function NPCMovementStabilityBridge.ResolveMoveTarget(zombie, brain, state, reason, x, y, z)
    if not zombie or not x or not y then return x, y, z, false end

    z = z or zombie:getZ()
    if NPCHumanizedAIBridge and NPCHumanizedAIBridge.ResolveMoveTarget then
        local okHuman, hx, hy, hz, hchanged = pcall(function()
            return NPCHumanizedAIBridge.ResolveMoveTarget(zombie, brain, state, reason, x, y, z)
        end)
        if okHuman and hx and hy then
            return hx, hy, hz or z, hchanged == true
        end
    end

    local targetSquare = NPCMovementStabilityBridge.GetSquare(x, y, z)
    local isBad = NPCMovementStabilityBridge.IsBadTarget(brain, x, y, z)
    local isBlocked = NPCMovementStabilityBridge.IsSquareBlocked(targetSquare, nil)
    local isBadByNavPerf = false
    if NPCNavigationPerformanceBridge and NPCNavigationPerformanceBridge.IsBadCell then
        local okBad, navBad = pcall(function()
            return NPCNavigationPerformanceBridge.IsBadCell(x, y, z)
        end)
        isBadByNavPerf = okBad and navBad == true
    end

    if not isBad and not isBlocked and not isBadByNavPerf then
        return x, y, z, false
    end

    local free = NPCMovementStabilityBridge.FindFreeAround(x, y, z, zombie, NPCMovementStabilityBridge.Config.targetSearchRadius or 8)
    if free and not NPCMovementStabilityBridge.IsBadTarget(brain, free:getX(), free:getY(), free:getZ()) then
        return free:getX(), free:getY(), free:getZ(), true
    end

    if state == "PatrolArea" or state == "ReturnToBase" or state == "RecoverPath" or state == "Regroup" then
        if NPCRoadNavBridge and NPCRoadNavBridge.FindLoadedTownOrRoadAround then
            local ok, preferred = pcall(function()
                return NPCRoadNavBridge.FindLoadedTownOrRoadAround(zombie:getX(), zombie:getY(), z, 54)
            end)
            if ok and preferred and preferred.x and preferred.y then
                return preferred.x, preferred.y, preferred.z or z, true
            end
        end
    end

    local recover = NPCMovementStabilityBridge.FindRecoverySquare(zombie, {x=x, y=y, z=z})
    if recover then
        return recover:getX(), recover:getY(), recover:getZ(), true
    end

    return x, y, z, false
end

function NPCMovementStabilityBridge.NormalizeTarget(zombie, task)
    if not zombie or not task or not bms_isMoveAction(task.action) then return task end
    if NPCMovementStabilityBridge.IsCombatLocked(zombie) then return task end

    task.z = task.z or zombie:getZ()
    task.walkType = task.walkType or "Walk"

    local brain = bms_getBrain(zombie)
    if brain and NPCRoadNavBridge and NPCRoadNavBridge.AdjustTaskTarget then
        NPCRoadNavBridge.AdjustTaskTarget(zombie, brain, task)
    end

    local rx, ry, rz, changed = NPCMovementStabilityBridge.ResolveMoveTarget(zombie, brain, task.directorState, task.directorReason, task.x, task.y, task.z)
    if changed then
        task.originalX = task.originalX or task.x
        task.originalY = task.originalY or task.y
        task.originalZ = task.originalZ or task.z
        task.x = rx
        task.y = ry
        task.z = rz
        task.adjustedTarget = true
        task.resolvedMoveTarget = true
    end

    if NPCSquadCoarseWaypointsBridge and NPCSquadCoarseWaypointsBridge.ResolveMoveTarget then
        pcall(function()
            NPCSquadCoarseWaypointsBridge.ResolveMoveTarget(zombie, brain, task)
        end)
    end

    return task
end

function NPCMovementStabilityBridge.Prepare(zombie, task, actionName)
    if not zombie or not task then return true end
    if not bms_isMoveAction(actionName or task.action) then return true end
    if NPCMovementStabilityBridge.IsCombatLocked(zombie) then return true end

    task.action = task.action or actionName
    NPCMovementStabilityBridge.NormalizeTarget(zombie, task)
    task._bms = task._bms or {}

    local brain = bms_getBrain(zombie)
    bms_markCrossFloorPlayerOrder(zombie, task, brain)

    if task.meleeApproach == true then
        local arrive = tonumber(task.arriveDist) or tonumber(NPCMovementStabilityBridge.Config.meleeCloseEnoughDist) or 1.45
        local closeEnough = math.max(arrive, tonumber(NPCMovementStabilityBridge.Config.meleeCloseEnoughDist) or 1.45)
        if bms_dist2(zombie:getX(), zombie:getY(), tonumber(task.x) or zombie:getX(), tonumber(task.y) or zombie:getY()) <= closeEnough * closeEnough then
            return bms_cancelMoveIntent(task, "close enough for melee")
        end
    end

    local now = bms_now()
    if not bms_adjustBlockedTarget(zombie, task, now) then
        return false
    end

    if not bms_acquireMovementIntent(zombie, task, actionName or task.action) then
        return false
    end

    now = bms_now()
    task._bms.startedAt = task._bms.startedAt or now
    task._bms.lastCheckAt = now
    task._bms.lastMoveAt = now
    task._bms.lastPathAt = task._bms.lastPathAt or 0
    task._bms.lastX = zombie:getX()
    task._bms.lastY = zombie:getY()
    task._bms.lastDist2 = bms_dist2(zombie:getX(), zombie:getY(), task.x or zombie:getX(), task.y or zombie:getY())
    task._bms.lastProgressAt = task._bms.lastProgressAt or now
    task._bms.replans = task._bms.replans or 0

    if NPCNavigationPerformanceBridge and NPCNavigationPerformanceBridge.OnMovePrepare then
        pcall(function() NPCNavigationPerformanceBridge.OnMovePrepare(zombie, task) end)
    end

    local square = zombie:getSquare()
    if square and NPCMovementStabilityBridge.IsSquareBlocked(square, zombie) then
        local asquare = NPCMovementStabilityBridge.FindFreeAround(square:getX(), square:getY(), square:getZ(), zombie, 2)
        if asquare then
            zombie:setX(asquare:getX() + 0.5)
            zombie:setY(asquare:getY() + 0.5)
            task._bms.unstuckTeleport = true
        end
    end

    return true
end

function NPCMovementStabilityBridge.CancelPreparedTask(zombie, task, reason)
    if task then
        task._bms = task._bms or {}
        task._bms.cancelled = true
        task._bms.cancelReason = reason or task._bms.cancelReason or "movement intent denied"
    end
    bms_releaseMovementIntent(zombie, task, "cancelled", reason or (task and task._bms and task._bms.cancelReason) or "movement intent denied")
    NPCMovementStabilityBridge.ResetPath(zombie, true)
    if NPCEntity and NPCEntity.RemoveTask then
        pcall(function() NPCEntity.RemoveTask(zombie) end)
    end
    return true
end

function NPCMovementStabilityBridge.StartPath(zombie, task, force)
    if not zombie or not task or not NPCUtils or not NPCUtils.IsController or not NPCUtils.IsController(zombie) then return true end

    task._bms = task._bms or {}
    if task._bms.cancelled then return true end
    local now = bms_now()

    if not force and task._bms.pathStarted and now - (task._bms.lastPathAt or 0) < 700 then
        local dx = math.abs((task._bms.pathX or task.x) - task.x)
        local dy = math.abs((task._bms.pathY or task.y) - task.y)
        if dx < 0.2 and dy < 0.2 and (task._bms.pathZ or task.z) == task.z then
            return true
        end
    end

    local brain = bms_getBrain(zombie)
    if bms_markCrossFloorPlayerOrder(zombie, task, brain) then
        -- Cross-floor order pathing through stairs can be extremely expensive in B41 MP.
        -- For explicit player orders, skip Java path spam and use the bounded teleport
        -- fallback almost immediately on the working tick.
        if bms_crossFloorOrderReadyForFallback(zombie, task, brain, now) then
            return bms_playerOrderTeleportToTarget(zombie, task, brain, "cross_floor_order_start")
        end
        if NPCMovementStabilityBridge.Config.crossFloorOrderAllowSingleProbe ~= true then
            return true
        end
        if task._bms.crossFloorPathProbed == true and now - (task._bms.crossFloorPathProbeAt or 0) > (tonumber(NPCMovementStabilityBridge.Config.crossFloorOrderPathProbeMs) or 180) then
            return bms_playerOrderTeleportToTarget(zombie, task, brain, "cross_floor_order_probe_timeout")
        end
        task._bms.crossFloorPathProbed = true
        task._bms.crossFloorPathProbeAt = task._bms.crossFloorPathProbeAt or now
    end

    local tx = tonumber(task.x)
    local ty = tonumber(task.y)
    local tz = tonumber(task.z or zombie:getZ())

    if bms_shouldHoldExistingB41Path(zombie, task, tx, ty, tz, now) then
        return true
    end

    if bms_shouldFuseB41BrainPath(zombie, task, tx, ty, tz, now) then
        return true
    end

    if not bms_canRequestPath(zombie, task, force, "StartPath") then
        if task.playerAnchorHouseOrder == true then
            if bms_playerOrderTeleportToTarget(zombie, task, brain, "house_order_path_denied") then
                bms_releaseMovementIntent(zombie, task, "teleported", "house order path denied")
                return true
            end
        end
        local deferred = bms_enqueueDeferredStartPath(zombie, task, brain, force, "StartPath")
        if NPCDiagnosticsBridge and NPCDiagnosticsBridge.TraceMovementEvent then
            NPCDiagnosticsBridge.TraceMovementEvent(deferred and "path_request_deferred" or "path_request_denied", zombie, task, {force=force, deferred=deferred}, false)
        end
        return true
    end

    bms_clearPath2(zombie)
    task._bms.directMove = false

    if task.vehiclePartArea then
        local ok, behavior = pcall(function()
            return zombie:getPathFindBehavior2()
        end)
        if ok and behavior then
            local square = NPCMovementStabilityBridge.GetSquare(task.x, task.y, task.z)
            local vehicle = square and square:getVehicleContainer()
            if vehicle then
                pcall(function() behavior:pathToVehicleArea(vehicle, task.vehiclePartArea) end)
                task._bms.directMove = false
            elseif bms_canDirectStep(zombie, task) then
                bms_directMoveTo(zombie, task)
            else
                bms_pathfindTo(zombie, task)
            end
        elseif bms_canDirectStep(zombie, task) then
            bms_directMoveTo(zombie, task)
        end
    elseif bms_canDirectStep(zombie, task) then
        bms_directMoveTo(zombie, task)
    else
        bms_pathfindTo(zombie, task)
    end

    task._bms.pathStarted = true
    task._bms.deferredPathQueued = false
    task._bms.pathDeferredUntil = 0
    task._bms.lastPathAt = now
    task._bms.pathX = task.x
    task._bms.pathY = task.y
    task._bms.pathZ = task.z
    bms_noteB41BrainPath(zombie, task, task._bms.pathX, task._bms.pathY, task._bms.pathZ, now)

    if NPCDiagnosticsBridge and NPCDiagnosticsBridge.TraceMovementEvent then
        NPCDiagnosticsBridge.TraceMovementEvent("path_started", zombie, task, {force=force, directMove=task._bms.directMove}, false)
    end

    return true
end

function NPCMovementStabilityBridge.UpdatePath(zombie, task)
    if not zombie or not task or not NPCUtils or not NPCUtils.IsController or not NPCUtils.IsController(zombie) then return false end

    if task._bms and task._bms.cancelled then return true end

    if task._bms and task._bms.crossFloorOrder == true and not task._bms.pathStarted then
        return false
    end

    if task._bms and task._bms.directMove then
        return false
    end

    local ok, behavior = pcall(function()
        return zombie:getPathFindBehavior2()
    end)
    if not ok or not behavior then return false end

    local result
    ok, result = pcall(function()
        return behavior:update()
    end)

    if not ok then return false end
    local failedResult = BehaviorResult and BehaviorResult.Failed or nil
    local succeededResult = BehaviorResult and BehaviorResult.Succeeded or nil
    if failedResult ~= nil and result == failedResult then
        bms_notePathFailure(zombie)
        if NPCDiagnosticsBridge and NPCDiagnosticsBridge.TraceMovementEvent then
            NPCDiagnosticsBridge.TraceMovementEvent("path_failed", zombie, task, {}, true)
        end
        return NPCMovementStabilityBridge.Recover(zombie, task)
    end
    if succeededResult ~= nil and result == succeededResult then
        bms_notePathProgress(zombie)
        if NPCDiagnosticsBridge and NPCDiagnosticsBridge.TraceMovementEvent then
            NPCDiagnosticsBridge.TraceMovementEvent("path_succeeded", zombie, task, {}, false)
        end
        return true
    end

    return false
end

function NPCMovementStabilityBridge.IsAtTarget(zombie, task)
    if not zombie or not task then return false end
    if task._bms and task._bms.cancelled then return true end
    if zombie:getZ() ~= (task.z or zombie:getZ()) then return false end

    local arrive = task.arriveDist or 0.9
    if task.closeSlow then arrive = math.max(arrive, 1.25) end
    if task.action == "GoTo" then arrive = math.max(arrive, 0.8) end

    local zx = zombie:getX()
    local zy = zombie:getY()
    local direct = bms_dist2(zx, zy, task.x, task.y)
    local centered = bms_dist2(zx, zy, task.x + 0.5, task.y + 0.5)
    return math.min(direct, centered) <= arrive * arrive
end

function NPCMovementStabilityBridge.CheckProgress(zombie, task)
    if not zombie or not task or not bms_isMoveAction(task.action) then return false end
    if NPCMovementStabilityBridge.IsCombatLocked(zombie) then return false end
    if NPCMovementStabilityBridge.IsAtTarget(zombie, task) then return false end

    local now = bms_now()
    local brain = bms_getBrain(zombie)
    if bms_markCrossFloorPlayerOrder(zombie, task, brain) and bms_crossFloorOrderReadyForFallback(zombie, task, brain, now) then
        return true
    end

    task._bms = task._bms or {
        startedAt = now,
        lastCheckAt = now,
        lastMoveAt = now,
        lastX = zombie:getX(),
        lastY = zombie:getY(),
        replans = 0
    }

    if task._bms.intentUntilMs and now > task._bms.intentUntilMs and bms_isAmbientMoveTask(task) then
        task._bms.intentExpired = true
        return true
    end

    local x = zombie:getX()
    local y = zombie:getY()
    local moved2 = bms_dist2(x, y, task._bms.lastX or x, task._bms.lastY or y)
    local dist2 = bms_dist2(x, y, task.x or x, task.y or y)
    local angle = bms_direction(zombie)
    local angleDelta = bms_angleDelta(angle, task._bms.lastAngle)
    local stuckNoMoveMs = tonumber(task.orderStuckNoMoveMs) or tonumber(NPCMovementStabilityBridge.Config.stuckNoMoveMs) or 1350
    local stuckNoProgressMs = tonumber(task.orderStuckNoProgressMs) or tonumber(NPCMovementStabilityBridge.Config.stuckNoProgressMs) or 2200

    if moved2 > 0.006 then
        task._bms.lastMoveAt = now
        task._bms.lastX = x
        task._bms.lastY = y
        task._bms.spinScore = math.max(0, (task._bms.spinScore or 0) - 1)

        if not task._bms.lastDist2 or dist2 < task._bms.lastDist2 - 0.08 then
            task._bms.lastDist2 = dist2
            task._bms.lastProgressAt = now

            local brain = bms_getBrain(zombie)
            if brain and brain.watchdog then
                brain.watchdog.stuck = false
            end
            bms_notePathProgress(zombie)
            if NPCNavigationPerformanceBridge and NPCNavigationPerformanceBridge.OnMoveProgress then
                pcall(function() NPCNavigationPerformanceBridge.OnMoveProgress(zombie, task) end)
            end
            return false
        end

        if now - (task._bms.lastProgressAt or task._bms.lastMoveAt or now) > stuckNoProgressMs then
            return true
        end

        task._bms.lastAngle = angle
        return false
    end

    if angleDelta >= (NPCMovementStabilityBridge.Config.spinAngle or 90) then
        task._bms.spinScore = (task._bms.spinScore or 0) + 1
        task._bms.lastSpinAt = now
    elseif now - (task._bms.lastSpinAt or 0) > (NPCMovementStabilityBridge.Config.spinWindowMs or 1800) then
        task._bms.spinScore = 0
    end
    task._bms.lastAngle = angle

    if (task._bms.spinScore or 0) >= 3 then
        task._bms.spinLoop = true
        return true
    end

    if now - (task._bms.lastMoveAt or now) < stuckNoMoveMs then
        return false
    end

    if task._bms.lastDist2 and dist2 > task._bms.lastDist2 - 0.05 and now - (task._bms.lastProgressAt or task._bms.startedAt or now) > stuckNoProgressMs then
        return true
    end

    return true
end

function NPCMovementStabilityBridge.Recover(zombie, task)
    if not zombie or not task or not bms_isMoveAction(task.action) then return true end
    if NPCMovementStabilityBridge.IsCombatLocked(zombie) then return false end

    task._bms = task._bms or {}
    task._bms.replans = (task._bms.replans or 0) + 1

    local brain = bms_getBrain(zombie)
    if bms_playerOrderTeleportToTarget(zombie, task, brain, task._bms.spinLoop and "spin_loop" or "path_stuck") then
        bms_releaseMovementIntent(zombie, task, "teleported", "player order path fallback")
        return true
    end

    if bms_isAmbientMoveTask(task) and (task._bms.intentExpired or task._bms.replans > (tonumber(NPCMovementStabilityBridge.Config.ambientMoveMaxReplans) or 1)) then
        bms_releaseMovementIntent(zombie, task, "dropped", task._bms.intentExpired and "movement intent expired" or "ambient replan limit")
        return true
    end
    if task._bms.intentOwner == "combat" and (task.noRecoveryReplan == true or task._bms.replans > (tonumber(NPCMovementStabilityBridge.Config.combatMoveMaxReplans) or 1)) then
        bms_releaseMovementIntent(zombie, task, "dropped", "combat movement replan limit")
        return true
    end

    if brain then
        brain.watchdog = brain.watchdog or {}
        brain.watchdog.stuck = true
        brain.watchdog.stuckTicks = (brain.watchdog.stuckTicks or 0) + 1
        brain.watchdog.lastMove = getGameTime() and getGameTime():getWorldAgeHours() or 0
        brain.watchdog.lastTarget = {x=task.x, y=task.y, z=task.z or zombie:getZ()}
        brain.debug = brain.debug or {}
        brain.debug.watchdog = true
        brain.debug.watchdogReason = task._bms.spinLoop and "spin loop" or "movement stuck"
        brain.state = "RecoverPath"
        brain.reason = brain.debug.watchdogReason
        if NPCUtilityAIBridge and NPCUtilityAIBridge.OnMovementStuck then
            pcall(function()
                NPCUtilityAIBridge.OnMovementStuck(zombie, brain, task)
            end)
        end
    end

    if NPCDiagnosticsBridge and NPCDiagnosticsBridge.TraceMovementEvent then
        NPCDiagnosticsBridge.TraceMovementEvent("recover", zombie, task, {replans=task._bms.replans, spinLoop=task._bms.spinLoop, intentExpired=task._bms.intentExpired}, true)
    end

    if NPCNavigationPerformanceBridge and NPCNavigationPerformanceBridge.RequestRepair then
        NPCMovementStabilityBridge.ResetPath(zombie, true)
        local queued = false
        local reason = task._bms.spinLoop and "spin_loop" or "movement_stuck"
        local okQueue, ret = pcall(function()
            return NPCNavigationPerformanceBridge.RequestRepair(zombie, task, reason)
        end)
        queued = okQueue and ret == true
        if queued then
            local now = bms_now()
            task._bms.lastMoveAt = now
            task._bms.lastProgressAt = now
            task._bms.lastX = zombie:getX()
            task._bms.lastY = zombie:getY()
            return false
        end
    else
        NPCMovementStabilityBridge.ResetPath(zombie, true)
    end

    local maxReplans = NPCMovementStabilityBridge.Config.maxReplans or 5
    if task._bms.replans <= maxReplans then
        local now = bms_now()
        if task._bms.asyncRecoveryQueuedUntil and now < task._bms.asyncRecoveryQueuedUntil then
            return false
        end

        local level = bms_perfLevel()
        if level >= 1 and NPCAsyncSchedulerBridge and NPCAsyncSchedulerBridge.EnqueuePathRecovery then
            task._bms.asyncRecoveryQueuedUntil = now + 900
            local queued = false
            local okAsync, retAsync = pcall(function()
                return NPCAsyncSchedulerBridge.EnqueuePathRecovery(zombie, brain, task,
                    function()
                        return NPCMovementStabilityBridge.FindRecoverySquare(zombie, task)
                    end,
                    function(recoverySquare)
                        if not zombie or not task then return false end
                        if NPCEntity and NPCEntity.GetTask then
                            local okTask, currentTask = pcall(function() return NPCEntity.GetTask(zombie) end)
                            if okTask and currentTask and currentTask ~= task then return false end
                        end
                        task._bms.asyncRecoveryQueuedUntil = nil
                        if recoverySquare then
                            task.originalX = task.originalX or task.x
                            task.originalY = task.originalY or task.y
                            task.originalZ = task.originalZ or task.z
                            task.x = recoverySquare:getX()
                            task.y = recoverySquare:getY()
                            task.z = recoverySquare:getZ()
                            task.adjustedTarget = true
                            task.recoveryTarget = true
                            task.arriveDist = math.max(task.arriveDist or 0.9, 1.2)
                            task.walkType = task._bms.replans <= 2 and "Walk" or (task.walkType or "Run")
                        end

                        task._bms.lastMoveAt = bms_now()
                        task._bms.lastProgressAt = bms_now()
                        task._bms.lastX = zombie:getX()
                        task._bms.lastY = zombie:getY()
                        task._bms.lastAngle = bms_direction(zombie)
                        task._bms.spinScore = 0
                        NPCMovementStabilityBridge.StartPath(zombie, task, true)
                        if NPCEntity and NPCEntity.SetMoving then
                            pcall(function() NPCEntity.SetMoving(zombie, true) end)
                        end
                        return true
                    end)
            end)
            queued = okAsync and retAsync == true
            if queued then return false end
            task._bms.asyncRecoveryQueuedUntil = nil
        end

        local recoverySquare = NPCMovementStabilityBridge.FindRecoverySquare(zombie, task)

        if recoverySquare then
            task.originalX = task.originalX or task.x
            task.originalY = task.originalY or task.y
            task.originalZ = task.originalZ or task.z
            task.x = recoverySquare:getX()
            task.y = recoverySquare:getY()
            task.z = recoverySquare:getZ()
            task.adjustedTarget = true
            task.recoveryTarget = true
            task.arriveDist = math.max(task.arriveDist or 0.9, 1.2)
            task.walkType = task._bms.replans <= 2 and "Walk" or (task.walkType or "Run")
        end

        task._bms.lastMoveAt = bms_now()
        task._bms.lastProgressAt = bms_now()
        task._bms.lastX = zombie:getX()
        task._bms.lastY = zombie:getY()
        task._bms.lastAngle = bms_direction(zombie)
        task._bms.spinScore = 0
        NPCMovementStabilityBridge.StartPath(zombie, task, true)
        if NPCEntity and NPCEntity.SetMoving then
            pcall(function() NPCEntity.SetMoving(zombie, true) end)
        end
        return false
    end

    NPCMovementStabilityBridge.MarkBadTarget(zombie, task, task._bms.spinLoop and "spin loop" or "replan limit")
    if brain then
        brain.fsm = brain.fsm or {}
        brain.fsm.patrol = nil
        brain.fsm.roadChain = nil
        brain.fsm.recoverCooldownUntil = bms_now() + 1500
        brain.reason = "dropped bad path target"
    end

    task._bms.droppedBadTarget = true

    -- Complete the bad move task and let the normal AI choose a fresh target.
    return true
end

function NPCMovementStabilityBridge.OnMoveWorking(zombie, task)
    if task and task._bms and task._bms.cancelled then
        return true
    end

    if zombie and task and bms_isMoveAction(task.action) then
        local brain = bms_getBrain(zombie)
        local now = bms_now()
        if bms_markCrossFloorPlayerOrder(zombie, task, brain) and bms_crossFloorOrderReadyForFallback(zombie, task, brain, now) then
            if bms_playerOrderTeleportToTarget(zombie, task, brain, "cross_floor_order_working") then
                bms_releaseMovementIntent(zombie, task, "teleported", "cross floor player order fallback")
                return true
            end
        end
    end

    if NPCMovementStabilityBridge.IsAtTarget(zombie, task) then
        return true
    end

    if NPCMovementStabilityBridge.CheckProgress(zombie, task) then
        return NPCMovementStabilityBridge.Recover(zombie, task)
    end

    return false
end

function NPCMovementStabilityBridge.OnMoveComplete(zombie, task)
    local status = "done"
    local reason = nil
    if task and task._bms then
        if task._bms.cancelled then
            status = "cancelled"
            reason = task._bms.cancelReason
        elseif task._bms.droppedBadTarget then
            status = "dropped"
            reason = "bad movement target"
        elseif task._bms.intentExpired then
            status = "dropped"
            reason = "movement intent expired"
        end
    end
    bms_releaseMovementIntent(zombie, task, status, reason)

    NPCMovementStabilityBridge.ResetPath(zombie, true)

    local brain = bms_getBrain(zombie)
    if brain and brain.watchdog then
        brain.watchdog.stuck = false
    end

    if NPCNavigationPerformanceBridge and NPCNavigationPerformanceBridge.ReleasePortal then
        pcall(function() NPCNavigationPerformanceBridge.ReleasePortal(zombie) end)
    end

    if NPCSquadCoarseWaypointsBridge and NPCSquadCoarseWaypointsBridge.ContinueMoveTask then
        local keepTask = false
        local okContinue, ret = pcall(function()
            return NPCSquadCoarseWaypointsBridge.ContinueMoveTask(zombie, task)
        end)
        keepTask = okContinue and ret == true
        if keepTask then return false end
    end

    return true
end
