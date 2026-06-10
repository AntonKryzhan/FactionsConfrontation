-- NPCActionRouterBridge.lua
-- Thin action/task router for NPC task lanes, movement leases and indoor slot reservations.
-- Stages 337-342: action protocol, battlefield memory and adaptive belief/learning hooks.

NPCActionRouterBridge = NPCActionRouterBridge or {}

pcall(require, "NPCCore/NPCBeliefStateBridge")
pcall(require, "NPCCore/NPCExperienceLedgerBridge")
pcall(require, "NPCCore/NPCAdaptiveLearningBridge")
pcall(require, "NPCCore/NPCInfluenceFieldBridge")

NPCActionRouterBridge.VERSION = "2026-05-31-stage344-tactical-influence-router-1"

NPCActionRouterBridge.Config = NPCActionRouterBridge.Config or {
    movementLeaseMs = 5600,
    movementIndoorLeaseMs = 3200,
    movementCriticalLeaseMs = 4200,
    movementSameTargetMs = 2600,
    movementCooldownMs = 650,
    movementIndoorCooldownMs = 450,
    movementNearCooldownMs = 300,
    movementSameRadius = 1.10,
    movementNearRadius = 1.85,
    generatedBatchMax = 8,
    indoorReserveMs = 4200,
    indoorReserveRadius = 3,
    indoorSlotSearchRadius = 4,
    indoorSlotCandidateMax = 28,
    indoorSlotMinSeparation = 1.35,
    indoorSlotSameRoomBonus = 8.0,
    indoorSlotChokepointPenalty = 9.0,
    doorStairStaggerMs = 650,
    doorStairReserveMs = 1250,
    chokepointSearchRadius = 1,
    ambientBlockWhileMovingMs = 900,
    traceMax = 32,
    staleTaskMs = 16000,
    stuckGraceMs = 2100,
    stuckIndoorGraceMs = 1500,
    stuckMoveEpsilon = 0.18,
    stuckProgressEpsilon = 0.35,
    preemptPruneQueuedMovement = true,
    protocolTraceSummaryMs = 12000,
    protocolRejectSpamMs = 900,
    protocolGenerationStaleMs = 9000,
    combatMemoryMinConfidence = 0.22,
    combatMemoryBlockAmbientMs = 1800,
    indoorSlotSoftSeparation = 1.35,
    squadSlaveMovePriorityPenalty = 2,
    tacticalInfluenceEnabled = true,
    tacticalInfluenceSoftReject = -28,
    tacticalInfluenceDeflect = -7,
    tacticalInfluenceSlotWeight = 0.32,
    tacticalInfluenceCongestionOnReserve = 1.6
}

NPCActionRouterBridge.Reservations = NPCActionRouterBridge.Reservations or {}
NPCActionRouterBridge.Chokepoints = NPCActionRouterBridge.Chokepoints or {}

local function bar_now()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then return math.floor(getGameTime():getWorldAgeHours() * 3600000) end
    return 0
end

local function bar_brain(chr)
    if NPCBrainDataBridge and NPCBrainDataBridge.Get then
        local ok, brain = pcall(function() return NPCBrainDataBridge.Get(chr) end)
        if ok then return brain end
    end
    if NPCBrainData and NPCBrainData.Get then
        local ok, brain = pcall(function() return NPCBrainData.Get(chr) end)
        if ok then return brain end
    end
    return nil
end

local function bar_id(chr, brain)
    if brain then
        local id = brain.id or brain.uid or brain.persistentId or brain.runtimeId
        if id ~= nil then return tostring(id) end
    end
    if NPCUtils and NPCUtils.GetZombieID then
        local ok, id = pcall(function() return NPCUtils.GetZombieID(chr) end)
        if ok and id ~= nil then return tostring(id) end
    end
    return tostring(chr)
end

local function bar_group(brain)
    if not brain then return nil end
    return tostring(brain.groupId or brain.groupID or brain.group or brain.squadId or brain.teamId or brain.faction or "solo")
end

local function bar_side(brain)
    if not brain then return nil end
    local side = brain.patrolColor or brain.faction or brain.side or brain.clan
    side = tostring(side or "")
    if side == "red" or side == "green" or side == "blue" or side == "black" then return side end
    return nil
end

local function bar_influenceBias(x, y, brain, context)
    if not (NPCInfluenceFieldBridge and NPCInfluenceFieldBridge.GetMovementBias) then return 0 end
    local ok, score = pcall(function()
        return NPCInfluenceFieldBridge.GetMovementBias(x, y, bar_side(brain), context)
    end)
    if ok then return tonumber(score) or 0 end
    return 0
end

local function bar_state(chr)
    if not (chr and chr.getActionStateName) then return nil end
    local ok, state = pcall(function() return chr:getActionStateName() end)
    if not ok or state == nil then return nil end
    return tostring(state):lower()
end

local function bar_isEngineMoving(chr)
    local state = bar_state(chr)
    return state == "walktoward" or state == "walktoward-network" or state == "pathfind"
end

local function bar_x(chr)
    if chr and chr.getX then
        local ok, v = pcall(function() return chr:getX() end)
        if ok and tonumber(v) then return tonumber(v) end
    end
    return 0
end

local function bar_y(chr)
    if chr and chr.getY then
        local ok, v = pcall(function() return chr:getY() end)
        if ok and tonumber(v) then return tonumber(v) end
    end
    return 0
end

local function bar_z(chr)
    if chr and chr.getZ then
        local ok, v = pcall(function() return chr:getZ() end)
        if ok and tonumber(v) then return tonumber(v) end
    end
    return 0
end

local function bar_isMove(action)
    return action == "Move" or action == "GoTo"
end

local function bar_isCombat(action)
    return action == "Shoot" or action == "Aim" or action == "Hit" or action == "Shove" or action == "Reload"
end

local function bar_isCleanup(action)
    return action == "Die" or action == "Zombify"
end

local function bar_isPlayerOrder(task)
    return task and (task.playerOrder == true or task.allowOrderTeleport == true or task.orderName ~= nil or task.manualOrder == true)
end

local function bar_isRecovery(task)
    return task and (task.recovery == true or task.pathRecovery == true or task.watchdogResolvedTarget == true or task.directorState == "RecoverPath")
end

local function bar_isHighPriority(task)
    if not task then return false end
    return bar_isCleanup(task.action) or bar_isCombat(task.action) or bar_isPlayerOrder(task) or bar_isRecovery(task) or task.combatMove == true or task.force == true
end

local function bar_isHardInterrupt(task)
    if not task then return false end
    return bar_isCleanup(task.action) or bar_isCombat(task.action) or bar_isPlayerOrder(task) or bar_isRecovery(task) or task.force == true
end

local function bar_isAmbient(task)
    if not task then return false end
    local action = task.action
    if action == "FaceLocation" then
        local anim = tostring(task.anim or ""):lower()
        return anim == "" or anim == "idle" or anim == "shiftweight" or anim == "smoke" or anim == "shrug" or anim == "sitaction" or anim == "sitrubhands" or anim == "chewnails" or anim == "wipebrow" or anim == "pullatcollar" or anim == "forage" or anim == "loot" or anim == "lootlow"
    end
    if action == "Time" or action == "Single" then
        local anim = tostring(task.anim or ""):lower()
        if anim == "" then return true end
        return anim == "idle" or anim == "shiftweight" or anim == "smoke" or anim == "sitaction" or anim == "sitrubhands" or anim == "cough" or anim == "shrug" or anim == "chewnails" or anim == "wipebrow" or anim == "pullatcollar" or anim == "forage" or anim == "loot" or anim == "lootlow"
    end
    return false
end

local function bar_dist2(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return dx * dx + dy * dy
end

local function bar_hash(x, y, z)
    return tostring(math.floor(tonumber(x) or 0)) .. ":" .. tostring(math.floor(tonumber(y) or 0)) .. ":" .. tostring(math.floor(tonumber(z) or 0))
end

local function bar_targetHash(task)
    if not task then return nil end
    if task.x == nil or task.y == nil then return nil end
    return bar_hash(task.x, task.y, task.z or 0)
end

local function bar_taskLane(task)
    if not task then return "interaction" end
    local action = task.action
    if bar_isCleanup(action) then return "cleanup" end
    if bar_isMove(action) then return "movement" end
    if bar_isCombat(action) then return "combat" end
    if bar_isAmbient(task) then return "animation" end
    return "interaction"
end

local function bar_taskSource(task, context)
    if context and context.source then return tostring(context.source) end
    if not task then return "unknown" end
    if bar_isCleanup(task.action) then return "cleanup" end
    if task.force == true then return "force" end
    if task.combatMove == true or bar_isCombat(task.action) then return "combat" end
    if bar_isPlayerOrder(task) then return "player_order" end
    if bar_isRecovery(task) then return "stuck_recovery" end
    if task.directorReason then return tostring(task.directorReason) end
    if task.orderName then return tostring(task.orderName) end
    return "ai"
end

local function bar_taskPriority(task, context)
    if not task then return 0 end
    if task.routerPriority ~= nil then return tonumber(task.routerPriority) or 0 end
    if bar_isCleanup(task.action) then return 100 end
    if bar_isCombat(task.action) or task.combatMove == true then return 90 end
    if bar_isPlayerOrder(task) then return 80 end
    if bar_isRecovery(task) then return 70 end
    if task.director == true then return 55 end
    if bar_isMove(task.action) then return 50 end
    if bar_isAmbient(task) then return 10 end
    return 40
end

local function bar_getState(brain)
    if not brain then return nil end
    brain.actionRouter = brain.actionRouter or {}
    local state = brain.actionRouter
    state.lanes = state.lanes or {}
    state.trace = state.trace or {}
    state.stats = state.stats or {}
    state.protocolSeq = tonumber(state.protocolSeq) or 0
    state.protocolGeneration = tonumber(state.protocolGeneration) or 1
    return state
end

local function bar_trace(brain, event, task, detail)
    local state = bar_getState(brain)
    if not state then return end
    local trace = state.trace
    trace[#trace + 1] = {
        t = bar_now(),
        event = event,
        action = task and task.action or nil,
        detail = detail,
        target = task and bar_targetHash(task) or nil
    }
    local max = tonumber(NPCActionRouterBridge.Config.traceMax) or 32
    while #trace > max do table.remove(trace, 1) end
end

local function bar_stat(brain, name, amount)
    local state = bar_getState(brain)
    if not state then return end
    local stats = state.stats
    name = tostring(name or "unknown")
    stats[name] = (tonumber(stats[name]) or 0) + (tonumber(amount) or 1)
end

local function bar_protocolSummary(brain, now)
    local state = bar_getState(brain)
    if not state then return end
    now = now or bar_now()
    local summaryMs = tonumber(NPCActionRouterBridge.Config.protocolTraceSummaryMs) or 12000
    if (tonumber(state.lastProtocolSummaryAt) or 0) + summaryMs > now then return end
    state.lastProtocolSummaryAt = now
    local stats = state.stats or {}
    local total = 0
    for _, value in pairs(stats) do total = total + (tonumber(value) or 0) end
    if total <= 0 then return end
    bar_trace(brain, "summary", nil, "accept=" .. tostring(stats.accept or 0) .. ";reject=" .. tostring(stats.reject or 0) .. ";evict=" .. tostring(stats.evict or 0) .. ";ttl=" .. tostring(stats.ttl or 0) .. ";stuck=" .. tostring(stats.stuck or 0) .. ";blockedIdle=" .. tostring(stats.blockedIdle or 0))
end

local function bar_ensureProtocol(brain, task, context, now)
    local state = bar_getState(brain)
    if not (state and task) then return task end
    now = now or bar_now()
    if task.routerSeq == nil then
        state.protocolSeq = (tonumber(state.protocolSeq) or 0) + 1
        task.routerSeq = state.protocolSeq
    end
    task.routerGeneration = task.routerGeneration or state.protocolGeneration or 1
    task.routerSource = task.routerSource or bar_taskSource(task, context)
    if task.routerPriority == nil then
        local basePriority = bar_taskPriority(task, context)
        local beliefMod = 0
        local learningMod = 0
        if NPCBeliefStateBridge and NPCBeliefStateBridge.TaskReliabilityModifier then
            local ok, mod = pcall(function() return NPCBeliefStateBridge.TaskReliabilityModifier(brain, task) end)
            if ok then beliefMod = tonumber(mod) or 0 end
        end
        if NPCAdaptiveLearningBridge and NPCAdaptiveLearningBridge.GetTaskPriorityModifier then
            local ok, mod = pcall(function() return NPCAdaptiveLearningBridge.GetTaskPriorityModifier(brain, task, context) end)
            if ok then learningMod = tonumber(mod) or 0 end
        end
        local squadMod = 0
        if brain and brain.squad and brain.squad.isSlave == true and bar_isMove(task.action) and not bar_isHighPriority(task) then
            squadMod = -(tonumber(NPCActionRouterBridge.Config.squadSlaveMovePriorityPenalty) or 2)
        end
        task.routerBasePriority = basePriority
        task.routerBeliefModifier = beliefMod
        task.routerLearningModifier = learningMod
        task.routerSquadModifier = squadMod
        task.routerPriority = basePriority + beliefMod + learningMod + squadMod
    else
        task.routerPriority = tonumber(task.routerPriority) or bar_taskPriority(task, context)
    end
    task.routerLane = task.routerLane or bar_taskLane(task)
    task.routerTargetHash = task.routerTargetHash or bar_targetHash(task)
    task.routerCreatedAt = task.routerCreatedAt or now
    if not task.routerExpiresAt then
        local ttl = tonumber(task.routerTtlMs or task.ttlMs or task.movementIntentTtlMs)
        if ttl and ttl > 0 then
            task.routerExpiresAt = now + ttl + 2500
        end
    end
    return task
end

local function bar_sortTasksByProtocol(tasks)
    if not tasks or #tasks < 2 then return tasks end
    table.sort(tasks, function(a, b)
        local ap = tonumber(a and a.routerPriority) or bar_taskPriority(a)
        local bp = tonumber(b and b.routerPriority) or bar_taskPriority(b)
        if ap == bp then
            return (tonumber(a and a.routerSeq) or 0) < (tonumber(b and b.routerSeq) or 0)
        end
        return ap > bp
    end)
    return tasks
end

local function bar_currentTask(brain)
    if brain and brain.tasks and #brain.tasks > 0 then return brain.tasks[1] end
    return nil
end

local function bar_hasActiveCombatMemory(brain, now)
    if not (brain and brain.ai) then return false end
    now = now or bar_now()
    local confidence = tonumber(brain.ai.enemyConfidence) or 0
    local untilMs = tonumber(brain.ai.enemyConfidenceUntilMs) or 0
    return confidence >= (tonumber(NPCActionRouterBridge.Config.combatMemoryMinConfidence) or 0.22) and untilMs > now
end

local function bar_hasQueuedMove(brain)
    if not (brain and brain.tasks) then return false end
    for _, task in ipairs(brain.tasks) do
        if task and bar_isMove(task.action) then return true, task end
    end
    return false, nil
end

local function bar_cleanupReservations(now)
    now = now or bar_now()
    local reservations = NPCActionRouterBridge.Reservations
    for key, value in pairs(reservations) do
        if not value or (tonumber(value.untilMs) or 0) < now then
            reservations[key] = nil
        end
    end
end

local function bar_squareBlocked(square, chr)
    if not square then return true end
    if NPCMovementStabilityBridge and NPCMovementStabilityBridge.IsSquareBlocked then
        local ok, blocked = pcall(function() return NPCMovementStabilityBridge.IsSquareBlocked(square, chr) end)
        if ok then return blocked == true end
    end
    return false
end

local function bar_taskSquare(task)
    if not (task and task.x and task.y and getCell) then return nil end
    return getCell():getGridSquare(math.floor(tonumber(task.x) or 0), math.floor(tonumber(task.y) or 0), math.floor(tonumber(task.z) or 0))
end

local function bar_chrSquare(chr)
    if not (chr and getCell) then return nil end
    return getCell():getGridSquare(math.floor(bar_x(chr)), math.floor(bar_y(chr)), math.floor(bar_z(chr)))
end

local function bar_building(square)
    if not square then return nil end
    if square.getBuilding then
        local ok, building = pcall(function() return square:getBuilding() end)
        if ok then return building end
    end
    return nil
end

local function bar_room(square)
    if not square then return nil end
    if square.getRoom then
        local ok, room = pcall(function() return square:getRoom() end)
        if ok then return room end
    end
    return nil
end

local function bar_squareCoords(square)
    if not square then return 0, 0, 0 end
    local x, y, z = 0, 0, 0
    if square.getX then local ok, v = pcall(function() return square:getX() end); if ok and tonumber(v) then x = tonumber(v) end end
    if square.getY then local ok, v = pcall(function() return square:getY() end); if ok and tonumber(v) then y = tonumber(v) end end
    if square.getZ then local ok, v = pcall(function() return square:getZ() end); if ok and tonumber(v) then z = tonumber(v) end end
    return x, y, z
end

local function bar_objectText(obj)
    if not obj then return "" end
    local parts = {}
    if obj.getName then local ok, v = pcall(function() return obj:getName() end); if ok and v then parts[#parts + 1] = tostring(v) end end
    if obj.getType then local ok, v = pcall(function() return obj:getType() end); if ok and v then parts[#parts + 1] = tostring(v) end end
    if obj.getSprite then
        local ok, sprite = pcall(function() return obj:getSprite() end)
        if ok and sprite then
            if sprite.getName then local ok2, v = pcall(function() return sprite:getName() end); if ok2 and v then parts[#parts + 1] = tostring(v) end end
        end
    end
    return table.concat(parts, " "):lower()
end

local function bar_squareHasProp(square, prop)
    if not (square and square.getProperties and prop) then return false end
    local ok, result = pcall(function()
        local props = square:getProperties()
        if props and props.Is then return props:Is(prop) == true end
        return false
    end)
    return ok and result == true
end

local function bar_isChokepointSquare(square)
    if not square then return false end
    if IsoFlagType then
        local props = {"doorN", "doorW", "doorE", "doorS", "windowN", "windowW", "stairsBN", "stairsMN", "stairsTN", "stairsBW", "stairsMW", "stairsTW"}
        for _, name in ipairs(props) do
            if IsoFlagType[name] and bar_squareHasProp(square, IsoFlagType[name]) then return true end
        end
    end
    if square.getObjects then
        local ok, objects = pcall(function() return square:getObjects() end)
        if ok and objects then
            local size = 0
            if objects.size then local ok2, v = pcall(function() return objects:size() end); if ok2 and tonumber(v) then size = tonumber(v) end end
            if size > 0 then
                for i = 0, size - 1 do
                    local okObj, obj = pcall(function() return objects:get(i) end)
                    if okObj and obj then
                        local text = bar_objectText(obj)
                        if text:find("door", 1, true) or text:find("stairs", 1, true) or text:find("stair", 1, true) or text:find("window", 1, true) then
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

local function bar_isNearChokepoint(square)
    if not (square and getCell) then return false end
    if bar_isChokepointSquare(square) then return true end
    local radius = tonumber(NPCActionRouterBridge.Config.chokepointSearchRadius) or 1
    local sx, sy, sz = bar_squareCoords(square)
    for dx = -radius, radius do
        for dy = -radius, radius do
            if not (dx == 0 and dy == 0) then
                local sq = getCell():getGridSquare(math.floor(sx + dx), math.floor(sy + dy), math.floor(sz))
                if sq and bar_isChokepointSquare(sq) then return true end
            end
        end
    end
    return false
end

local function bar_chokepointKey(groupId, square)
    local x, y, z = bar_squareCoords(square)
    return tostring(groupId or "solo") .. ":cp:" .. bar_hash(x, y, z)
end

local function bar_cleanupChokepoints(now)
    now = now or bar_now()
    local locks = NPCActionRouterBridge.Chokepoints
    for key, value in pairs(locks) do
        if not value or (tonumber(value.untilMs) or 0) < now then
            locks[key] = nil
        end
    end
end

local function bar_applyChokepointStagger(chr, brain, task, now)
    if not (chr and brain and task and task.x and task.y) then return true, nil end
    if bar_isPlayerOrder(task) or task.combatMove == true or task.force == true then return true, nil end
    local square = bar_taskSquare(task)
    if not square or not bar_isNearChokepoint(square) then return true, nil end
    local groupId = bar_group(brain)
    if groupId == "solo" then return true, nil end
    local id = bar_id(chr, brain)
    local key = bar_chokepointKey(groupId, square)
    local locks = NPCActionRouterBridge.Chokepoints
    local current = locks[key]
    if current and current.id ~= id and (tonumber(current.untilMs) or 0) > now then
        local state = bar_getState(brain)
        if state then
            local wait = tonumber(NPCActionRouterBridge.Config.doorStairStaggerMs) or 650
            state.movementCooldownUntil = math.max(tonumber(state.movementCooldownUntil) or 0, now + wait)
        end
        return false, "chokepoint_stagger"
    end
    locks[key] = {
        id = id,
        group = groupId,
        untilMs = now + (tonumber(NPCActionRouterBridge.Config.doorStairReserveMs) or 1250)
    }
    task.routerChokepointKey = key
    task.routerChokepoint = true
    return true, nil
end

local function bar_reservationPressure(groupId, x, y, z, id, now)
    local minSep = tonumber(NPCActionRouterBridge.Config.indoorSlotMinSeparation) or 1.35
    local minSep2 = minSep * minSep
    local pressure = 0
    for _, rv in pairs(NPCActionRouterBridge.Reservations) do
        if rv and rv.group == groupId and rv.id ~= id and (tonumber(rv.untilMs) or 0) > now and rv.x and rv.y and (rv.z or z) == z then
            local d2 = bar_dist2(x, y, rv.x, rv.y)
            if d2 < minSep2 then pressure = pressure + (minSep2 - d2) * 5.0 end
        end
    end
    return pressure
end

local function bar_scoreIndoorSlot(chr, task, square, targetRoom, groupId, id, now)
    local sx, sy, sz = bar_squareCoords(square)
    local dNpc = bar_dist2(bar_x(chr), bar_y(chr), sx, sy)
    local dTarget = bar_dist2(task.x, task.y, sx, sy)
    local score = 100.0 - (dNpc * 0.42) - (dTarget * 0.68)
    if targetRoom and bar_room(square) == targetRoom then
        score = score + (tonumber(NPCActionRouterBridge.Config.indoorSlotSameRoomBonus) or 8.0)
    end
    if bar_isNearChokepoint(square) then
        score = score - (tonumber(NPCActionRouterBridge.Config.indoorSlotChokepointPenalty) or 9.0)
    end
    score = score - bar_reservationPressure(groupId, sx, sy, sz, id, now)
    if NPCActionRouterBridge.Config.tacticalInfluenceEnabled ~= false then
        local brain = bar_brain(chr)
        local influence = bar_influenceBias(sx, sy, brain, {indoor=true})
        score = score + influence * (tonumber(NPCActionRouterBridge.Config.tacticalInfluenceSlotWeight) or 0.32)
    end
    return score
end

local function bar_isIndoor(chr, task)
    local square = task and bar_taskSquare(task) or bar_chrSquare(chr)
    return bar_building(square) ~= nil
end

local function bar_reservationKey(groupId, x, y, z)
    return tostring(groupId or "solo") .. ":" .. bar_hash(x, y, z)
end

local function bar_releaseReservation(task, brain, chr)
    if not (task and task.routerReservationKey) then return end
    local rv = NPCActionRouterBridge.Reservations[task.routerReservationKey]
    local id = bar_id(chr, brain)
    if rv and rv.id == id then NPCActionRouterBridge.Reservations[task.routerReservationKey] = nil end
end

local function bar_pruneQueue(brain, predicate, reason)
    if not (brain and brain.tasks) then return 0 end
    local kept = {}
    local removed = 0
    for _, queued in ipairs(brain.tasks) do
        if queued and predicate(queued) and queued.lock ~= true then
            removed = removed + 1
            if queued.routerReservationKey then
                NPCActionRouterBridge.Reservations[queued.routerReservationKey] = nil
            end
        else
            kept[#kept + 1] = queued
        end
    end
    if removed > 0 then
        brain.tasks = kept
        bar_trace(brain, "prune", nil, tostring(reason or "prune") .. ":" .. tostring(removed))
    end
    return removed
end

local function bar_clearMovement(brain, chr, reason, noCooldown)
    local state = bar_getState(brain)
    if not state then return end
    local now = bar_now()
    state.movementLease = nil
    state.movementProbe = nil
    if state.lanes and state.lanes.movement then
        state.lanes.movement.active = false
        state.lanes.movement.completedAt = now
        state.lanes.movement.reason = reason
    end
    if noCooldown == true then
        state.movementCooldownUntil = nil
    else
        state.movementCooldownUntil = now + 250
    end
    bar_trace(brain, "release_movement", nil, reason or "release")
end

local function bar_hardInterrupt(brain, chr, task, reason)
    if not (brain and task) then return end
    task.routerPreempt = true
    task.routerHardInterrupt = true
    local action = task.action
    if bar_isCombat(action) or bar_isCleanup(action) or bar_isPlayerOrder(task) or bar_isRecovery(task) then
        local state = bar_getState(brain)
        if state then state.protocolGeneration = (tonumber(state.protocolGeneration) or 1) + 1 end
        bar_stat(brain, "evict", 1)
        bar_clearMovement(brain, chr, reason or "hard_interrupt", true)
        if NPCActionRouterBridge.Config.preemptPruneQueuedMovement == true then
            bar_pruneQueue(brain, function(q)
                return q and (bar_isMove(q.action) or bar_isAmbient(q))
            end, reason or "hard_interrupt")
        end
    end
end

local function bar_nearTarget(chr, task, radius)
    if not (chr and task and task.x and task.y) then return false end
    local z = tonumber(task.z or bar_z(chr)) or 0
    if math.abs((tonumber(bar_z(chr)) or 0) - z) > 0.35 then return false end
    radius = tonumber(radius) or tonumber(NPCActionRouterBridge.Config.movementNearRadius) or 1.85
    return bar_dist2(bar_x(chr), bar_y(chr), task.x, task.y) <= radius * radius
end

local function bar_updateMovementHealth(chr, brain, now)
    local state = bar_getState(brain)
    if not (state and state.movementLease) then return end
    local lease = state.movementLease
    if (tonumber(lease.untilMs) or 0) <= now then
        bar_stat(brain, "ttl", 1)
        if NPCExperienceLedgerBridge and NPCExperienceLedgerBridge.RecordPath then
            pcall(function() NPCExperienceLedgerBridge.RecordPath(brain, chr, lease, false, "lease_expired") end)
        elseif NPCBeliefStateBridge and NPCBeliefStateBridge.NotePathResult then
            pcall(function() NPCBeliefStateBridge.NotePathResult(brain, lease, false, "lease_expired") end)
        end
        bar_clearMovement(brain, chr, "lease_expired", false)
        return
    end
    if not (lease.x and lease.y) then return end

    local x = bar_x(chr)
    local y = bar_y(chr)
    local d2 = bar_dist2(x, y, lease.x, lease.y)
    local probe = state.movementProbe
    local moveEps = tonumber(NPCActionRouterBridge.Config.stuckMoveEpsilon) or 0.18
    local progressEps = tonumber(NPCActionRouterBridge.Config.stuckProgressEpsilon) or 0.35
    if not probe then
        state.movementProbe = {x=x, y=y, d2=d2, t=now, stuckSince=now}
        return
    end

    local moved = bar_dist2(x, y, probe.x, probe.y) > (moveEps * moveEps)
    local progressed = d2 < ((tonumber(probe.d2) or d2) - progressEps)
    if moved or progressed then
        probe.x = x
        probe.y = y
        probe.d2 = d2
        probe.t = now
        probe.stuckSince = now
        return
    end

    local indoor = bar_building(bar_chrSquare(chr)) ~= nil
    local grace = indoor and (tonumber(NPCActionRouterBridge.Config.stuckIndoorGraceMs) or 1500) or (tonumber(NPCActionRouterBridge.Config.stuckGraceMs) or 2100)
    if now - (tonumber(probe.stuckSince) or now) > grace then
        bar_pruneQueue(brain, function(q)
            return q and bar_isMove(q.action)
        end, "stuck_release")
        bar_stat(brain, "stuck", 1)
        if NPCExperienceLedgerBridge and NPCExperienceLedgerBridge.RecordPath then
            pcall(function() NPCExperienceLedgerBridge.RecordPath(brain, chr, lease, false, indoor and "stuck_indoor" or "stuck") end)
        elseif NPCBeliefStateBridge and NPCBeliefStateBridge.NotePathResult then
            pcall(function() NPCBeliefStateBridge.NotePathResult(brain, lease, false, indoor and "stuck_indoor" or "stuck") end)
        end
        bar_clearMovement(brain, chr, indoor and "stuck_indoor" or "stuck", false)
    end
end

local function bar_reserveTarget(chr, brain, task, now)
    if not (chr and brain and task and task.x and task.y and getCell) then return task end
    if bar_isPlayerOrder(task) or task.combatMove == true then return task end

    local z = math.floor(tonumber(task.z or bar_z(chr) or 0) or 0)
    local square = bar_taskSquare(task)
    local building = bar_building(square)
    if not building then return task end

    local groupId = bar_group(brain)
    local id = bar_id(chr, brain)
    local reservations = NPCActionRouterBridge.Reservations
    local key = bar_reservationKey(groupId, task.x, task.y, z)
    local current = reservations[key]
    local needsAlt = current and current.id ~= id and (tonumber(current.untilMs) or 0) > now
    if not needsAlt and groupId ~= "solo" then
        local minSep = tonumber(NPCActionRouterBridge.Config.indoorSlotSoftSeparation) or tonumber(NPCActionRouterBridge.Config.indoorSlotMinSeparation) or 1.35
        local minSep2 = minSep * minSep
        for _, rv in pairs(reservations) do
            if rv and rv.group == groupId and rv.id ~= id and math.floor(tonumber(rv.z) or z) == z and (tonumber(rv.untilMs) or 0) > now then
                if bar_dist2(task.x, task.y, rv.x, rv.y) < minSep2 then
                    needsAlt = true
                    task.routerCrowdSeparation = true
                    break
                end
            end
        end
    end

    if needsAlt and groupId ~= "solo" then
        local radius = tonumber(NPCActionRouterBridge.Config.indoorSlotSearchRadius) or tonumber(NPCActionRouterBridge.Config.indoorReserveRadius) or 4
        local maxCandidates = tonumber(NPCActionRouterBridge.Config.indoorSlotCandidateMax) or 28
        local tx = math.floor(tonumber(task.x) or 0)
        local ty = math.floor(tonumber(task.y) or 0)
        local targetRoom = bar_room(square)
        local candidates = {}
        for r = 1, radius do
            for dx = -r, r do
                for dy = -r, r do
                    if math.abs(dx) == r or math.abs(dy) == r then
                        local sq = getCell():getGridSquare(tx + dx, ty + dy, z)
                        if sq and bar_building(sq) == building and not bar_squareBlocked(sq, chr) then
                            local sx, sy, sz = bar_squareCoords(sq)
                            local k = bar_reservationKey(groupId, sx, sy, sz)
                            local rv = reservations[k]
                            if not rv or rv.id == id or (tonumber(rv.untilMs) or 0) <= now then
                                candidates[#candidates + 1] = {
                                    square = sq,
                                    key = k,
                                    x = sx,
                                    y = sy,
                                    z = sz,
                                    score = bar_scoreIndoorSlot(chr, task, sq, targetRoom, groupId, id, now)
                                }
                                if #candidates >= maxCandidates then break end
                            end
                        end
                    end
                end
                if #candidates >= maxCandidates then break end
            end
            if #candidates >= maxCandidates then break end
        end
        if #candidates > 1 then
            table.sort(candidates, function(a, b)
                if a.score == b.score then
                    return bar_dist2(bar_x(chr), bar_y(chr), a.x, a.y) < bar_dist2(bar_x(chr), bar_y(chr), b.x, b.y)
                end
                return a.score > b.score
            end)
        end
        local best = candidates[1]
        if best then
            task.routerOriginalX = task.routerOriginalX or task.x
            task.routerOriginalY = task.routerOriginalY or task.y
            task.routerOriginalZ = task.routerOriginalZ or task.z
            task.x = best.x
            task.y = best.y
            task.z = best.z
            task.routerReservedSlot = true
            task.routerSlotScore = best.score
            if task.routerCrowdSeparation == true then task.routerSlotReason = "soft_separation" end
            key = best.key
        end
    end

    reservations[key] = {
        id = id,
        group = groupId,
        x = math.floor(tonumber(task.x) or 0),
        y = math.floor(tonumber(task.y) or 0),
        z = math.floor(tonumber(task.z or z) or z),
        untilMs = now + (tonumber(NPCActionRouterBridge.Config.indoorReserveMs) or 4200)
    }
    task.routerReservationKey = key
    return task
end

local function bar_movementTtl(chr, task, high)
    if task.routerTtlMs or task.movementIntentTtlMs or task.ttlMs then
        return tonumber(task.routerTtlMs or task.movementIntentTtlMs or task.ttlMs) or 3000
    end
    if high then return tonumber(NPCActionRouterBridge.Config.movementCriticalLeaseMs) or 4200 end
    if bar_isIndoor(chr, task) then return tonumber(NPCActionRouterBridge.Config.movementIndoorLeaseMs) or 3200 end
    return tonumber(NPCActionRouterBridge.Config.movementLeaseMs) or 5600
end

local function bar_movementCooldown(chr, task, reason)
    if reason == "router_hard_interrupt" or (task and task.routerNoCooldownOnRemove == true) then return 0 end
    if task and bar_isIndoor(chr, task) then return tonumber(NPCActionRouterBridge.Config.movementIndoorCooldownMs) or 450 end
    return tonumber(NPCActionRouterBridge.Config.movementCooldownMs) or 650
end

function NPCActionRouterBridge.IsMoveAction(action)
    return bar_isMove(action)
end

function NPCActionRouterBridge.IsCombatAction(action)
    return bar_isCombat(action)
end

function NPCActionRouterBridge.IsAmbientAction(task)
    return bar_isAmbient(task)
end

function NPCActionRouterBridge.IsHighPriorityTask(task)
    return bar_isHighPriority(task)
end

function NPCActionRouterBridge.IsHardInterruptTask(task)
    return bar_isHardInterrupt(task)
end

function NPCActionRouterBridge.ShouldPrependTask(task)
    return task and task.routerPreempt == true
end


local function bar_applyTacticalInfluence(chr, brain, task, context, high)
    if NPCActionRouterBridge.Config.tacticalInfluenceEnabled == false then return true end
    if high or bar_isPlayerOrder(task) or task.combatMove == true or task.force == true or task.forcePath == true then return true end
    if not (task and task.x and task.y and NPCInfluenceFieldBridge and NPCInfluenceFieldBridge.GetMovementBias) then return true end
    local indoor = bar_isIndoor(chr, task)
    local bias = bar_influenceBias(task.x, task.y, brain, {indoor=indoor})
    task.routerInfluenceBias = bias
    local deflect = tonumber(NPCActionRouterBridge.Config.tacticalInfluenceDeflect) or -7
    if bias <= deflect and NPCInfluenceFieldBridge.FindSaferNeighbor then
        local ok, alt = pcall(function()
            return NPCInfluenceFieldBridge.FindSaferNeighbor(task.x, task.y, bar_side(brain), indoor and 1 or 2, {indoor=indoor})
        end)
        if ok and alt and alt.x and alt.y and (tonumber(alt.score) or 0) > bias + 2.0 then
            task.routerInfluenceOriginalX = task.routerInfluenceOriginalX or task.x
            task.routerInfluenceOriginalY = task.routerInfluenceOriginalY or task.y
            task.x = alt.x
            task.y = alt.y
            task.routerInfluenceAdjusted = true
            task.routerInfluenceAdjustedScore = alt.score
            return true
        end
    end
    local softReject = tonumber(NPCActionRouterBridge.Config.tacticalInfluenceSoftReject) or -28
    if bias <= softReject then
        if NPCExperienceLedgerBridge and NPCExperienceLedgerBridge.Outcome then
            pcall(function() NPCExperienceLedgerBridge.Outcome(brain, chr, "router", "influence_unsafe_move", -0.18, {bias=bias}) end)
        end
        return false, "influence_unsafe_move"
    end
    return true
end

function NPCActionRouterBridge.CanQueueTask(chr, brain, task, context)
    if not (chr and brain and task and task.action) then return false, "invalid_task" end
    context = context or {}
    local now = bar_now()
    bar_cleanupReservations(now)
    bar_cleanupChokepoints(now)

    local action = task.action
    local state = bar_getState(brain)
    if not state then return true end
    bar_ensureProtocol(brain, task, context, now)
    bar_protocolSummary(brain, now)
    bar_updateMovementHealth(chr, brain, now)

    if task.routerExpiresAt and tonumber(task.routerExpiresAt) and now > tonumber(task.routerExpiresAt) then
        bar_stat(brain, "reject", 1)
        bar_trace(brain, "reject", task, "expired")
        if NPCExperienceLedgerBridge and NPCExperienceLedgerBridge.Outcome then
            pcall(function() NPCExperienceLedgerBridge.Outcome(brain, chr, "router", "task_expired", -0.20, {action=task.action}) end)
        end
        return false, "expired"
    end

    if task.routerGeneration and state.protocolGeneration and tonumber(task.routerGeneration) < tonumber(state.protocolGeneration) and not bar_isHighPriority(task) then
        local age = now - (tonumber(task.routerCreatedAt) or now)
        if age > (tonumber(NPCActionRouterBridge.Config.protocolGenerationStaleMs) or 9000) then
            bar_stat(brain, "reject", 1)
            bar_trace(brain, "reject", task, "stale_generation")
            return false, "stale_generation"
        end
    end

    local current = bar_currentTask(brain)
    local currentAction = current and current.action or nil
    local high = bar_isHighPriority(task)
    local hard = bar_isHardInterrupt(task)
    local combatMemoryActive = bar_hasActiveCombatMemory(brain, now)

    if combatMemoryActive and not high and (bar_isAmbient(task) or (bar_isMove(action) and task.combatMove ~= true)) then
        bar_stat(brain, "reject", 1)
        bar_trace(brain, "reject", task, "combat_memory_wakeup")
        return false, "combat_memory_wakeup"
    end

    if hard then
        bar_hardInterrupt(brain, chr, task, "hard_interrupt")
    end

    if bar_isCleanup(action) then
        task.routerLane = "cleanup"
        task.routerPreempt = true
        return true
    end

    if current and not high then
        if bar_isCombat(currentAction) then
            bar_stat(brain, "reject", 1)
            bar_trace(brain, "reject", task, "combat_lane_busy")
            return false, "combat_lane_busy"
        end
        if bar_isMove(currentAction) and (bar_isMove(action) or bar_isAmbient(task)) then
            bar_stat(brain, "reject", 1)
            bar_trace(brain, "reject", task, "movement_lane_busy")
            return false, "movement_lane_busy"
        end
    end

    if bar_isMove(action) then
        task.z = task.z or bar_z(chr) or 0

        local influenceOk, influenceReason = bar_applyTacticalInfluence(chr, brain, task, context, high)
        if not influenceOk then
            bar_stat(brain, "reject", 1)
            bar_trace(brain, "reject", task, influenceReason or "influence")
            return false, influenceReason or "influence"
        end

        if bar_nearTarget(chr, task, NPCActionRouterBridge.Config.movementNearRadius) and not task.forcePath then
            state.movementCooldownUntil = now + (tonumber(NPCActionRouterBridge.Config.movementNearCooldownMs) or 300)
            task.routerNearTarget = true
            bar_stat(brain, "reject", 1)
            bar_trace(brain, "reject", task, "near_target")
            if NPCExperienceLedgerBridge and NPCExperienceLedgerBridge.RecordPath then
                pcall(function() NPCExperienceLedgerBridge.RecordPath(brain, chr, task, true, "near_target") end)
            end
            return false, "near_target"
        end

        local hasMove, queuedMove = bar_hasQueuedMove(brain)
        if hasMove and not high then
            local same = queuedMove and task.x and task.y and queuedMove.x and queuedMove.y and bar_dist2(task.x, task.y, queuedMove.x, queuedMove.y) <= ((tonumber(NPCActionRouterBridge.Config.movementSameRadius) or 1.10) ^ 2)
            bar_stat(brain, "reject", 1)
            bar_trace(brain, "reject", task, same and "queued_same_move" or "queued_move")
            return false, same and "queued_same_move" or "queued_move"
        end

        if state.movementCooldownUntil and now < state.movementCooldownUntil and not high then
            bar_stat(brain, "reject", 1)
            bar_trace(brain, "reject", task, "movement_cooldown")
            return false, "movement_cooldown"
        end

        local lease = state.movementLease
        if lease and (tonumber(lease.untilMs) or 0) > now then
            if high then
                bar_clearMovement(brain, chr, "movement_evicted_by_high", true)
            else
                if lease.x and lease.y and task.x and task.y then
                    local sameTarget = bar_dist2(task.x, task.y, lease.x, lease.y) <= ((tonumber(NPCActionRouterBridge.Config.movementSameRadius) or 1.10) ^ 2)
                    if sameTarget and now - (tonumber(lease.startedAt) or now) < (tonumber(NPCActionRouterBridge.Config.movementSameTargetMs) or 2600) then
                        bar_stat(brain, "reject", 1)
                        bar_trace(brain, "reject", task, "active_same_move")
                        return false, "active_same_move"
                    end
                end
                if bar_isEngineMoving(chr) then
                    bar_stat(brain, "reject", 1)
                    bar_trace(brain, "reject", task, "engine_moving")
                    return false, "engine_moving"
                end
            end
        end

        bar_reserveTarget(chr, brain, task, now)
        if NPCInfluenceFieldBridge and NPCInfluenceFieldBridge.InjectCongestion and not high and not bar_isPlayerOrder(task) then
            pcall(function() NPCInfluenceFieldBridge.InjectCongestion(task.x, task.y, tonumber(NPCActionRouterBridge.Config.tacticalInfluenceCongestionOnReserve) or 1.6, NPCInfluenceFieldBridge.Config and NPCInfluenceFieldBridge.Config.tacticalCongestionRadius or 42) end)
        end
        local passChoke, chokeReason = bar_applyChokepointStagger(chr, brain, task, now)
        if not passChoke and not high then
            bar_stat(brain, "reject", 1)
            bar_trace(brain, "reject", task, chokeReason or "chokepoint_stagger")
            return false, chokeReason or "chokepoint_stagger"
        end

        local ttl = bar_movementTtl(chr, task, high)
        task.routerLane = "movement"
        task.routerCreatedAt = task.routerCreatedAt or now
        task.routerExpiresAt = task.routerExpiresAt or (now + math.max(ttl + 2500, tonumber(NPCActionRouterBridge.Config.staleTaskMs) or 16000))
        task.routerTtlMs = ttl
        if high then task.routerPreempt = true end
        state.movementLease = {
            x = tonumber(task.x),
            y = tonumber(task.y),
            z = tonumber(task.z),
            hash = bar_targetHash(task),
            startedAt = now,
            untilMs = now + ttl,
            source = context.source or task.directorReason or task.orderName or "task"
        }
        state.movementProbe = {x=bar_x(chr), y=bar_y(chr), d2=task.x and task.y and bar_dist2(bar_x(chr), bar_y(chr), task.x, task.y) or 0, t=now, stuckSince=now}
        state.lanes.movement = {action=action, startedAt=now, untilMs=now + ttl, active=false}
        bar_stat(brain, "accept", 1)
        bar_trace(brain, "accept", task, high and "movement_preempt" or "movement")
        if NPCExperienceLedgerBridge and NPCExperienceLedgerBridge.Record then
            pcall(function() NPCExperienceLedgerBridge.Record(brain, chr, "router_accept_movement", {source=task.routerSource, priority=task.routerPriority, learning=task.routerLearningModifier, belief=task.routerBeliefModifier}) end)
        end
        return true
    end

    if bar_isCombat(action) then
        task.routerLane = "combat"
        task.routerCreatedAt = task.routerCreatedAt or now
        task.routerPreempt = true
        state.lanes.combat = {action=action, startedAt=now, untilMs=now + 3000, active=false}
        bar_stat(brain, "accept", 1)
        bar_trace(brain, "accept", task, "combat_preempt")
        return true
    end

    if bar_isAmbient(task) and not context.postMoveTask then
        local lease = state.movementLease
        if (lease and (tonumber(lease.untilMs) or 0) > now) or bar_isEngineMoving(chr) then
            if not high then
                bar_stat(brain, "reject", 1)
                bar_stat(brain, "blockedIdle", 1)
                bar_trace(brain, "reject", task, "ambient_while_moving")
                return false, "ambient_while_moving"
            end
        end
    end

    task.routerLane = bar_isAmbient(task) and "animation" or "interaction"
    task.routerCreatedAt = task.routerCreatedAt or now
    task.routerExpiresAt = task.routerExpiresAt or (now + (tonumber(NPCActionRouterBridge.Config.staleTaskMs) or 16000))
    bar_stat(brain, "accept", 1)
    bar_trace(brain, "accept", task, task.routerLane)
    return true
end

function NPCActionRouterBridge.FilterTasks(chr, brain, tasks, context)
    if not tasks or #tasks == 0 then return tasks end
    brain = brain or bar_brain(chr)
    if not brain then return tasks end
    context = context or {}
    local filtered = {}
    local acceptedMove = false
    local max = tonumber(NPCActionRouterBridge.Config.generatedBatchMax) or 8
    local now = bar_now()
    for _, task in ipairs(tasks) do
        if task and task.action then bar_ensureProtocol(brain, task, context, now) end
    end
    bar_sortTasksByProtocol(tasks)
    for _, task in ipairs(tasks) do
        if task and task.action then
            local c = context
            if acceptedMove and bar_isAmbient(task) then
                c = {}
                for k, v in pairs(context) do c[k] = v end
                c.postMoveTask = true
            end
            local ok = NPCActionRouterBridge.CanQueueTask(chr, brain, task, c)
            if ok then
                if task.routerPreempt == true then
                    local compact = {}
                    for _, old in ipairs(filtered) do
                        if not (old and (bar_isMove(old.action) or bar_isAmbient(old))) then compact[#compact + 1] = old end
                    end
                    filtered = compact
                    acceptedMove = false
                end
                filtered[#filtered + 1] = task
                if bar_isMove(task.action) then acceptedMove = true end
                if #filtered >= max and not bar_isCombat(task.action) and not bar_isCleanup(task.action) then break end
            end
        end
    end
    return filtered
end

function NPCActionRouterBridge.FilterAddTask(chr, task, source)
    if not (task and task.action) then return nil end
    local brain = bar_brain(chr)
    if not brain then return task end
    local ok = NPCActionRouterBridge.CanQueueTask(chr, brain, task, {source=source or "entity_add"})
    if ok then return task end
    return nil
end

function NPCActionRouterBridge.OnTaskStart(chr, task)
    local brain = bar_brain(chr)
    if not (brain and task and task.action) then return true end
    local state = bar_getState(brain)
    local now = bar_now()
    bar_ensureProtocol(brain, task, {source="task_start"}, now)
    bar_updateMovementHealth(chr, brain, now)
    if task.routerExpiresAt and now > tonumber(task.routerExpiresAt) then
        bar_trace(brain, "drop_start", task, "expired")
        return false
    end
    if bar_isMove(task.action) and bar_nearTarget(chr, task, NPCActionRouterBridge.Config.movementNearRadius) and not task.forcePath then
        if state then state.movementCooldownUntil = now + (tonumber(NPCActionRouterBridge.Config.movementNearCooldownMs) or 300) end
        bar_trace(brain, "drop_start", task, "near_target")
        return false
    end
    if bar_isAmbient(task) then
        local lease = state and state.movementLease or nil
        if (lease and (tonumber(lease.untilMs) or 0) > now) or bar_isEngineMoving(chr) then
            bar_stat(brain, "blockedIdle", 1)
            bar_trace(brain, "drop_start", task, "ambient_while_moving")
            return false
        end
    end
    if state and task.routerLane then
        state.lanes[task.routerLane] = state.lanes[task.routerLane] or {}
        state.lanes[task.routerLane].action = task.action
        state.lanes[task.routerLane].startedAt = now
        state.lanes[task.routerLane].active = true
    end
    return true
end

function NPCActionRouterBridge.OnTaskRemoved(chr, brain, task, reason)
    brain = brain or bar_brain(chr)
    if not (brain and task and task.action) then return end
    local state = bar_getState(brain)
    if not state then return end
    local now = bar_now()
    local lane = task.routerLane
    if lane and state.lanes and state.lanes[lane] then
        state.lanes[lane].active = false
        state.lanes[lane].completedAt = now
        state.lanes[lane].reason = reason
    end
    if bar_isMove(task.action) then
        local cd = bar_movementCooldown(chr, task, reason)
        if cd > 0 then state.movementCooldownUntil = now + cd else state.movementCooldownUntil = nil end
        if reason == "completed" or reason == "done" or reason == "near_target" or reason == nil then
            if NPCExperienceLedgerBridge and NPCExperienceLedgerBridge.RecordPath then
                pcall(function() NPCExperienceLedgerBridge.RecordPath(brain, chr, task, true, reason or "removed") end)
            elseif NPCBeliefStateBridge and NPCBeliefStateBridge.NotePathResult then
                pcall(function() NPCBeliefStateBridge.NotePathResult(brain, task, true, reason or "removed") end)
            end
        end
        state.movementLease = nil
        state.movementProbe = nil
        bar_releaseReservation(task, brain, chr)
    end
    bar_trace(brain, "removed", task, reason or "removed")
end

function NPCActionRouterBridge.OnTasksCleared(chr, brain, oldTasks, reason)
    brain = brain or bar_brain(chr)
    if not brain then return end
    local state = bar_getState(brain)
    if state then
        state.movementLease = nil
        state.movementProbe = nil
        state.lanes = {}
        state.movementCooldownUntil = bar_now() + 250
    end
    if oldTasks then
        for _, task in ipairs(oldTasks) do
            if task and task.routerReservationKey then
                NPCActionRouterBridge.Reservations[task.routerReservationKey] = nil
            end
        end
    end
    bar_trace(brain, "clear", nil, reason or "clear")
end
