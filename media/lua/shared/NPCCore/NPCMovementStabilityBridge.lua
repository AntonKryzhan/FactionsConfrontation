-- NPCMovementStabilityBridge.lua
-- Neutral shared backend for movement stability and stuck recovery.

NPCMovementStabilityBridge = NPCMovementStabilityBridge or {}

NPCMovementStabilityBridge.VERSION = "2026-05-10-v8-async-recovery-1"

NPCMovementStabilityBridge.Config = NPCMovementStabilityBridge.Config or {
    stuckNoMoveMs = 1350,
    stuckNoProgressMs = 2200,
    spinWindowMs = 1800,
    spinAngle = 90,
    localEscapeRadius = 5,
    targetSearchRadius = 6,
    badTargetCooldownMs = 28000,
    maxReplans = 4,
    personalSpaceRadius = 1.45,
    queuedRepairHoldMs = 2200,
    minPathRequestMs = 1600,
    forcedPathRequestMs = 1100,
    sameTargetPathRequestMs = 6200,
    pathFailBackoffMs = 900,
    maxPathFailBackoffMs = 9000
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

local function bms_isMoveAction(action)
    return action == "Move" or action == "GoTo"
end

local function bms_isCombatAction(action)
    return action == "Shoot"
        or action == "Aim"
        or action == "Hit"
        or action == "Shove"
        or action == "Reload"
end

local function bms_getBrain(zombie)
    if not zombie or not NPCBrainData or not NPCBrainData.Get then return nil end

    local ok, brain = pcall(function()
        return NPCBrainData.Get(zombie)
    end)

    if ok then return brain end
    return nil
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
    local level, zoom = bms_perfLevel()
    if level >= 3 or zoom >= 2.35 then
        minDelay = math.max(minDelay, 3200)
        sameDelay = math.max(sameDelay, 9800)
        forcedDelay = math.max(forcedDelay, 2200)
    elseif level >= 2 or zoom >= 1.90 then
        minDelay = math.max(minDelay, 2400)
        sameDelay = math.max(sameDelay, 7600)
        forcedDelay = math.max(forcedDelay, 1600)
    elseif level >= 1 or zoom >= 1.45 then
        minDelay = math.max(minDelay, 1900)
        sameDelay = math.max(sameDelay, 6800)
        forcedDelay = math.max(forcedDelay, 1300)
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
    if NPCCompatibilityBridge and NPCCompatibilityBridge.GetGameVersion and NPCCompatibilityBridge.GetGameVersion() < 42 then
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

    local now = bms_now()
    task._bms = task._bms or {}
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

function NPCMovementStabilityBridge.StartPath(zombie, task, force)
    if not zombie or not task or not NPCUtils or not NPCUtils.IsController or not NPCUtils.IsController(zombie) then return true end

    task._bms = task._bms or {}
    local now = bms_now()

    if not force and task._bms.pathStarted and now - (task._bms.lastPathAt or 0) < 700 then
        local dx = math.abs((task._bms.pathX or task.x) - task.x)
        local dy = math.abs((task._bms.pathY or task.y) - task.y)
        if dx < 0.2 and dy < 0.2 and (task._bms.pathZ or task.z) == task.z then
            return true
        end
    end

    if not bms_canRequestPath(zombie, task, force, "StartPath") then
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
    task._bms.lastPathAt = now
    task._bms.pathX = task.x
    task._bms.pathY = task.y
    task._bms.pathZ = task.z

    return true
end

function NPCMovementStabilityBridge.UpdatePath(zombie, task)
    if not zombie or not task or not NPCUtils or not NPCUtils.IsController or not NPCUtils.IsController(zombie) then return false end

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
    if result == BehaviorResult.Failed then
        bms_notePathFailure(zombie)
        return NPCMovementStabilityBridge.Recover(zombie, task)
    end
    if result == BehaviorResult.Succeeded then
        bms_notePathProgress(zombie)
        return true
    end

    return false
end

function NPCMovementStabilityBridge.IsAtTarget(zombie, task)
    if not zombie or not task then return false end
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
    task._bms = task._bms or {
        startedAt = now,
        lastCheckAt = now,
        lastMoveAt = now,
        lastX = zombie:getX(),
        lastY = zombie:getY(),
        replans = 0
    }

    local x = zombie:getX()
    local y = zombie:getY()
    local moved2 = bms_dist2(x, y, task._bms.lastX or x, task._bms.lastY or y)
    local dist2 = bms_dist2(x, y, task.x or x, task.y or y)
    local angle = bms_direction(zombie)
    local angleDelta = bms_angleDelta(angle, task._bms.lastAngle)

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

        if now - (task._bms.lastProgressAt or task._bms.lastMoveAt or now) > (NPCMovementStabilityBridge.Config.stuckNoProgressMs or 2200) then
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

    if now - (task._bms.lastMoveAt or now) < (NPCMovementStabilityBridge.Config.stuckNoMoveMs or 1350) then
        return false
    end

    if task._bms.lastDist2 and dist2 > task._bms.lastDist2 - 0.05 and now - (task._bms.lastProgressAt or task._bms.startedAt or now) > (NPCMovementStabilityBridge.Config.stuckNoProgressMs or 2200) then
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

    -- Complete the bad move task and let the normal AI choose a fresh target.
    return true
end

function NPCMovementStabilityBridge.OnMoveWorking(zombie, task)
    if NPCMovementStabilityBridge.IsAtTarget(zombie, task) then
        return true
    end

    if NPCMovementStabilityBridge.CheckProgress(zombie, task) then
        return NPCMovementStabilityBridge.Recover(zombie, task)
    end

    return false
end

function NPCMovementStabilityBridge.OnMoveComplete(zombie, task)
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
