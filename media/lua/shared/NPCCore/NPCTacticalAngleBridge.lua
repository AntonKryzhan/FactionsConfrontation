-- NPCTacticalAngleBridge.lua
-- Stage 369: advanced cover peek / angle discipline for human NPC fireteams.
--
-- This module is intentionally advisory. It does not shoot, damage, spawn,
-- sync network commands, or change save contracts. It only scores/recommends
-- small cover-side/peek points and remembers briefly when a shot lane is bad.

NPCTacticalAngleBridge = NPCTacticalAngleBridge or {}
NPCTacticalAngleBridge.VERSION = "2026-06-01-stage369-advanced-cover-peek-angle-discipline-1"

pcall(require, "NPCCore/NPCMovementStabilityBridge")
pcall(require, "NPCCore/NPCIndoorTacticalBridge")
pcall(require, "NPCCore/NPCHumanizedAIBridge")
-- Stage 377: CombatPath is an optional runtime provider; avoid eager
-- require here to prevent recursive require warnings during boot.

NPCTacticalAngleBridge.Config = NPCTacticalAngleBridge.Config or {
    enabled = true,
    maxLineDist = 28,
    rayStep = 0.72,
    peekRadius = 2,
    peekHoldMs = 3600,
    badAngleHoldMs = 1850,
    clearLaneHoldMs = 950,
    sideSwitchHoldMs = 5200,
    doorwayPenalty = 9.0,
    chokepointPenalty = 5.5,
    sameSideBonus = 2.0,
    peekClearBonus = 5.4,
    directAngleBonus = 2.2,
    wallSideBonus = 2.0,
    crowdPenalty = 5.0,
    minPeekScore = -4.0
}

NPCTacticalAngleBridge._cache = NPCTacticalAngleBridge._cache or {}

local function bta_nowMs()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then return math.floor((getGameTime():getWorldAgeHours() or 0) * 3600000) end
    return 0
end

local function bta_rand(n)
    n = tonumber(n) or 1
    if n <= 1 then return 0 end
    if ZombRand then return ZombRand(n) end
    return math.random(0, n - 1)
end

local function bta_id(chr, brain)
    if brain then
        if brain.persistentId then return tostring(brain.persistentId) end
        if brain.uid then return tostring(brain.uid) end
        if brain.id then return tostring(brain.id) end
    end
    if chr and NPCUtils and NPCUtils.GetCharacterID then
        local ok, id = pcall(function() return NPCUtils.GetCharacterID(chr) end)
        if ok and id then return tostring(id) end
    end
    return tostring(chr or "unknown")
end

local function bta_dist2(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return dx * dx + dy * dy
end

local function bta_len(dx, dy)
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.001 then return 1 end
    return len
end

local function bta_square(x, y, z)
    local cell = getCell and getCell() or nil
    if not cell then return nil end
    return cell:getGridSquare(math.floor(tonumber(x) or 0), math.floor(tonumber(y) or 0), math.floor(tonumber(z) or 0))
end

local function bta_squareBlocked(square, mover)
    if not square then return true end
    if NPCMovementStabilityBridge and NPCMovementStabilityBridge.IsSquareBlocked then
        local ok, blocked = pcall(function() return NPCMovementStabilityBridge.IsSquareBlocked(square, mover) end)
        if ok then return blocked == true end
    end
    local ok, solid = pcall(function() return square:isSolid() or square:isSolidTrans() end)
    return ok and solid == true
end

local function bta_canStep(mover, fromSq, toSq)
    if not (fromSq and toSq) then return false end
    if bta_squareBlocked(toSq, mover) then return false end
    if NPCMovementStabilityBridge and NPCMovementStabilityBridge.CanStepBetween then
        local ok, can = pcall(function() return NPCMovementStabilityBridge.CanStepBetween(mover, fromSq, toSq) end)
        if ok then return can == true end
    end
    local dx = toSq:getX() - fromSq:getX()
    local dy = toSq:getY() - fromSq:getY()
    if math.abs(dx) > 1 or math.abs(dy) > 1 then return false end
    local ok, blocked = pcall(function() return fromSq:testCollideAdjacent(mover, dx, dy, 0) end)
    return not (ok and blocked == true)
end

local function bta_isDoorwayOrChoke(square, mover)
    if not square or not NPCIndoorTacticalBridge then return false, false end
    local doorway = false
    local choke = false
    if NPCIndoorTacticalBridge.IsDoorwaySquare then
        local ok, value = pcall(function() return NPCIndoorTacticalBridge.IsDoorwaySquare(square) end)
        doorway = ok and value == true
    end
    if NPCIndoorTacticalBridge.IsNarrowChokepoint then
        local ok, value = pcall(function() return NPCIndoorTacticalBridge.IsNarrowChokepoint(square, mover) end)
        choke = ok and value == true
    end
    return doorway, choke
end

local function bta_hasWallSide(square)
    if not square then return false end
    local ok, objects = pcall(function() return square:getObjects() end)
    if not ok or not objects then return false end
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        local name = obj and obj.getSpriteName and tostring(obj:getSpriteName() or ""):lower() or ""
        if name:find("wall", 1, true)
            or name:find("counter", 1, true)
            or name:find("shelf", 1, true)
            or name:find("crate", 1, true)
            or name:find("fence", 1, true)
            or name:find("car", 1, true) then
            return true
        end
    end
    return false
end

local function bta_rayBlockedAt(square)
    if not square then return true end
    local ok, solid = pcall(function() return square:isSolid() or square:isSolidTrans() end)
    if ok and solid == true then return true end
    local okObjs, objects = pcall(function() return square:getObjects() end)
    if not okObjs or not objects then return false end
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        local okBlock, blocked = pcall(function()
            if instanceof and (instanceof(obj, "IsoDoor") or instanceof(obj, "IsoWindow") or instanceof(obj, "IsoThumpable")) then
                if obj.IsOpen and obj:IsOpen() == true then return false end
                if obj.isSmashed and obj:isSmashed() == true then return false end
                return true
            end
            local props = obj:getProperties()
            if props and IsoFlagType then
                if IsoFlagType.solid and props:Is(IsoFlagType.solid) then return true end
                if IsoFlagType.solidtrans and props:Is(IsoFlagType.solidtrans) then return true end
                if IsoFlagType.collideN and props:Is(IsoFlagType.collideN) then return true end
                if IsoFlagType.collideW and props:Is(IsoFlagType.collideW) then return true end
            end
            return false
        end)
        if okBlock and blocked == true then return true end
    end
    return false
end

function NPCTacticalAngleBridge.LineClearFromPoint(x1, y1, z1, x2, y2, z2, ttlKey)
    if NPCTacticalAngleBridge.Config.enabled == false then return true end
    z1 = math.floor(tonumber(z1) or 0)
    z2 = math.floor(tonumber(z2) or z1)
    if z1 ~= z2 then return false end
    local dx = (tonumber(x2) or 0) - (tonumber(x1) or 0)
    local dy = (tonumber(y2) or 0) - (tonumber(y1) or 0)
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 0.05 then return true end
    if dist > (tonumber(NPCTacticalAngleBridge.Config.maxLineDist) or 28) then return false end

    local key = ttlKey
    if not key then
        key = tostring(math.floor((tonumber(x1) or 0) * 2)) .. ":" .. tostring(math.floor((tonumber(y1) or 0) * 2)) .. ":" .. tostring(z1) .. ":" .. tostring(math.floor((tonumber(x2) or 0) * 2)) .. ":" .. tostring(math.floor((tonumber(y2) or 0) * 2))
    end
    local now = bta_nowMs()
    local cache = NPCTacticalAngleBridge._cache.line or {}
    NPCTacticalAngleBridge._cache.line = cache
    local entry = cache[key]
    if entry and now - (tonumber(entry.ms) or 0) < 360 then return entry.clear == true end

    local stepLen = tonumber(NPCTacticalAngleBridge.Config.rayStep) or 0.72
    local steps = math.min(42, math.max(2, math.floor(dist / stepLen)))
    local clear = true
    for i = 1, steps - 1 do
        local t = i / steps
        local sx = (tonumber(x1) or 0) + dx * t
        local sy = (tonumber(y1) or 0) + dy * t
        local sq = bta_square(sx, sy, z1)
        if bta_rayBlockedAt(sq) then
            clear = false
            break
        end
    end
    cache[key] = {ms = now, clear = clear}
    return clear
end

local function bta_targetPoint(contact)
    if not contact then return nil end
    if contact.getX and contact.getY then
        return contact:getX(), contact:getY(), contact.getZ and contact:getZ() or 0
    end
    if contact.x and contact.y then return tonumber(contact.x), tonumber(contact.y), tonumber(contact.z) or 0 end
    return nil
end

local function bta_recentBadPenalty(brain, x, y)
    local angle = brain and brain.ai and brain.ai.angle or nil
    if not angle or not angle.badX or not angle.badY then return 0 end
    if bta_nowMs() > (tonumber(angle.badUntil) or 0) then return 0 end
    if bta_dist2(x, y, angle.badX, angle.badY) <= 4.0 then return -8.0 end
    return 0
end

local function bta_crowdPenalty(bandit, brain, x, y, z)
    if not (NPCHumanizedAIBridge and NPCHumanizedAIBridge.CountCrowdAround) then return 0 end
    local ok, crowd = pcall(function()
        return NPCHumanizedAIBridge.CountCrowdAround(bandit, brain, x, y, z, 1.45)
    end)
    if ok and crowd and crowd > 0 then return -crowd * (tonumber(NPCTacticalAngleBridge.Config.crowdPenalty) or 5.0) end
    return 0
end

function NPCTacticalAngleBridge.ScoreCoverSquare(bandit, brain, square, contact, role)
    if NPCTacticalAngleBridge.Config.enabled == false or not (square and contact) then return 0 end
    local tx, ty, tz = bta_targetPoint(contact)
    if not tx or not ty then return 0 end
    local sx = square:getX() + 0.5
    local sy = square:getY() + 0.5
    local sz = square:getZ()
    local score = 0

    local doorway, choke = bta_isDoorwayOrChoke(square, bandit)
    if doorway then score = score - (tonumber(NPCTacticalAngleBridge.Config.doorwayPenalty) or 9.0) end
    if choke then score = score - (tonumber(NPCTacticalAngleBridge.Config.chokepointPenalty) or 5.5) end
    if bta_hasWallSide(square) then score = score + (tonumber(NPCTacticalAngleBridge.Config.wallSideBonus) or 2.0) end
    score = score + bta_recentBadPenalty(brain, sx, sy)
    score = score + bta_crowdPenalty(bandit, brain, sx, sy, sz)

    local clear = NPCTacticalAngleBridge.LineClearFromPoint(sx, sy, sz, tx, ty, tz, nil)
    if clear then
        local roleText = tostring(role or "")
        if roleText == "overwatch" or roleText == "suppress" or roleText == "cross_cover" then
            score = score + (tonumber(NPCTacticalAngleBridge.Config.directAngleBonus) or 2.2)
        else
            score = score + 0.8
        end
    end

    local px, py = NPCTacticalAngleBridge.GetBestPeekOffset(square, contact, bandit, brain, role)
    if px and py then score = score + (tonumber(NPCTacticalAngleBridge.Config.peekClearBonus) or 5.4) end
    return score
end

function NPCTacticalAngleBridge.GetBestPeekOffset(square, contact, bandit, brain, role)
    if NPCTacticalAngleBridge.Config.enabled == false or not (square and contact) then return nil end
    local tx, ty, tz = bta_targetPoint(contact)
    if not tx or not ty then return nil end
    local sx = square:getX() + 0.5
    local sy = square:getY() + 0.5
    local sz = square:getZ()
    local dx = tx - sx
    local dy = ty - sy
    local len = bta_len(dx, dy)
    local ux, uy = dx / len, dy / len
    local px, py = -uy, ux
    local preferSide = nil
    local angle = brain and brain.ai and brain.ai.angle or nil
    if angle and angle.preferSide and bta_nowMs() < (tonumber(angle.sideUntil) or 0) then
        preferSide = tonumber(angle.preferSide)
    end

    local candidates = {}
    local function add(side, forward, lateralWeight)
        local cx = sx + px * side + ux * (forward or 0)
        local cy = sy + py * side + uy * (forward or 0)
        candidates[#candidates + 1] = {x = cx, y = cy, z = sz, side = side, weight = lateralWeight or 0}
    end
    if preferSide then add(preferSide, 0, tonumber(NPCTacticalAngleBridge.Config.sameSideBonus) or 2.0) end
    add(1, 0, preferSide == 1 and 1.0 or 0)
    add(-1, 0, preferSide == -1 and 1.0 or 0)
    add(1, 0.75, -0.4)
    add(-1, 0.75, -0.4)

    local best, bestScore = nil, -1000000
    local fromSq = bandit and bandit.getSquare and bandit:getSquare() or square
    for _, c in ipairs(candidates) do
        local csq = bta_square(c.x, c.y, c.z)
        if csq and not bta_squareBlocked(csq, bandit) and bta_canStep(bandit, square, csq) then
            local cx = csq:getX() + 0.5
            local cy = csq:getY() + 0.5
            local score = c.weight or 0
            if fromSq and bta_canStep(bandit, fromSq, csq) then score = score + 1.2 end
            if NPCTacticalAngleBridge.LineClearFromPoint(cx, cy, c.z, tx, ty, tz, nil) then score = score + 8.0 else score = score - 7.0 end
            local doorway, choke = bta_isDoorwayOrChoke(csq, bandit)
            if doorway then score = score - 7.0 end
            if choke then score = score - 3.5 end
            score = score + bta_crowdPenalty(bandit, brain, cx, cy, c.z)
            if score > bestScore then
                bestScore = score
                best = {x = csq:getX(), y = csq:getY(), z = csq:getZ(), side = c.side, score = score}
            end
        end
    end
    if best and bestScore >= (tonumber(NPCTacticalAngleBridge.Config.minPeekScore) or -4.0) then
        return best.x, best.y, best.z, best.side, best.score
    end
    return nil
end

function NPCTacticalAngleBridge.RefineCoverPoint(bandit, brain, contact, point, role)
    if NPCTacticalAngleBridge.Config.enabled == false or not (bandit and contact and point and point.x and point.y) then return point end
    local now = bta_nowMs()
    brain = brain or (NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(bandit) or nil)
    if brain then
        brain.ai = brain.ai or {}
        brain.ai.angle = brain.ai.angle or {}
        local hold = brain.ai.angle.coverHold
        if hold and hold.x and hold.y and now < (tonumber(hold.untilMs) or 0) and tostring(hold.role or "") == tostring(role or point.role or "") then
            return hold
        end
    end

    local sq = bta_square(point.x, point.y, point.z or (bandit and bandit:getZ()) or 0)
    if not sq then return point end
    local tx, ty, tz = bta_targetPoint(contact)
    local sx, sy, sz = sq:getX() + 0.5, sq:getY() + 0.5, sq:getZ()
    local directClear = tx and NPCTacticalAngleBridge.LineClearFromPoint(sx, sy, sz, tx, ty, tz, nil) or false
    local px, py, pz, side, peekScore = NPCTacticalAngleBridge.GetBestPeekOffset(sq, contact, bandit, brain, role)

    local refined = point
    if px and py and (not directClear or tostring(role or "") == "cover" or tostring(role or "") == "cross_cover") then
        refined = {
            x = px,
            y = py,
            z = pz or point.z,
            role = point.role or role,
            mode = "peek_" .. tostring(point.mode or role or "cover"),
            threat = point.threat or contact,
            arriveDist = math.min(tonumber(point.arriveDist) or 1.45, 1.15),
            reason = "advanced angle peek / cover side",
            fireteam = point.fireteam == true,
            indoor = point.indoor == true,
            anglePeek = true,
            peekSide = side,
            score = tonumber(point.score or 0) + (tonumber(peekScore) or 0) * 0.15
        }
    else
        refined.angleHold = directClear == true
        refined.anglePeek = false
    end

    if brain then
        brain.ai.angle.coverHold = refined
        brain.ai.angle.coverHold.untilMs = now + (tonumber(NPCTacticalAngleBridge.Config.peekHoldMs) or 3600)
        brain.ai.angle.coverHold.role = refined.role or role
        if refined.peekSide then
            brain.ai.angle.preferSide = refined.peekSide
            brain.ai.angle.sideUntil = now + (tonumber(NPCTacticalAngleBridge.Config.sideSwitchHoldMs) or 5200)
        end
    end
    return refined
end

function NPCTacticalAngleBridge.MarkLineBlocked(shooter, target, brain, reason)
    if NPCTacticalAngleBridge.Config.enabled == false or not shooter then return end
    brain = brain or (NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(shooter) or nil)
    if not brain then return end
    brain.ai = brain.ai or {}
    brain.ai.angle = brain.ai.angle or {}
    local now = bta_nowMs()
    local tx, ty, tz = bta_targetPoint(target)
    brain.ai.angle.blockedUntil = now + (tonumber(NPCTacticalAngleBridge.Config.badAngleHoldMs) or 1850)
    brain.ai.angle.blockedReason = tostring(reason or "bad angle")
    brain.ai.angle.targetX = tx
    brain.ai.angle.targetY = ty
    brain.ai.angle.targetZ = tz or (shooter.getZ and shooter:getZ()) or 0
    brain.ai.angle.badX = shooter.getX and shooter:getX() or nil
    brain.ai.angle.badY = shooter.getY and shooter:getY() or nil
    brain.ai.angle.badUntil = brain.ai.angle.blockedUntil
    brain.ai.angle.coverHold = nil
end

function NPCTacticalAngleBridge.NotifyLineClear(shooter, target, brain)
    if NPCTacticalAngleBridge.Config.enabled == false or not shooter then return end
    brain = brain or (NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(shooter) or nil)
    if not brain then return end
    brain.ai = brain.ai or {}
    brain.ai.angle = brain.ai.angle or {}
    brain.ai.angle.clearUntil = bta_nowMs() + (tonumber(NPCTacticalAngleBridge.Config.clearLaneHoldMs) or 950)
end

function NPCTacticalAngleBridge.ShouldRequestPeek(bandit, brain, contact)
    if NPCTacticalAngleBridge.Config.enabled == false or not (bandit and brain) then return false end
    local angle = brain.ai and brain.ai.angle or nil
    if not angle then return false end
    local now = bta_nowMs()
    if now < (tonumber(angle.blockedUntil) or 0) then return true end
    if contact and contact.x and contact.y and now > (tonumber(angle.clearUntil) or 0) then
        local d2 = bta_dist2(bandit:getX(), bandit:getY(), contact.x, contact.y)
        if d2 > 12 and d2 < 400 then
            local clear = NPCTacticalAngleBridge.LineClearFromPoint(bandit:getX(), bandit:getY(), bandit:getZ(), contact.x, contact.y, contact.z or bandit:getZ(), nil)
            return clear ~= true and bta_rand(100) < 38
        end
    end
    return false
end

function NPCTacticalAngleBridge.GetPeekPoint(bandit, brain, contact, role)
    if NPCTacticalAngleBridge.Config.enabled == false or not (bandit and contact and contact.x and contact.y) then return nil end
    local sq = bandit.getSquare and bandit:getSquare() or bta_square(bandit:getX(), bandit:getY(), bandit:getZ())
    if not sq then return nil end
    local px, py, pz, side, score = NPCTacticalAngleBridge.GetBestPeekOffset(sq, contact, bandit, brain, role)
    if not px or not py then return nil end
    return {
        x = px,
        y = py,
        z = pz or bandit:getZ(),
        role = role or "angle_peek",
        mode = "angle_peek",
        threat = contact,
        arriveDist = 1.0,
        anglePeek = true,
        peekSide = side,
        combatPathDisciplineShort = true,
        reason = "advanced angle discipline peek step",
        score = score
    }
end

function NPCTacticalAngleBridge.DecorateTask(task, bandit, brain, contact)
    if not task then return task end
    task.angleDiscipline = true
    task.tacticalStep = true
    task.engineAssist = true
    task.naturalMotion = true
    task.smoothTurn = true
    task.arriveDist = math.min(tonumber(task.arriveDist) or 1.2, 1.15)
    task.pathThrottleMs = math.max(tonumber(task.pathThrottleMs) or 0, 1150)
    task.sameTargetPathThrottleMs = math.max(tonumber(task.sameTargetPathThrottleMs) or 0, 4200)
    task.engineAssistSoftRetargetRadius = math.max(tonumber(task.engineAssistSoftRetargetRadius) or 0, 3.0)
    task.engineAssistSoftRetargetHoldMs = math.max(tonumber(task.engineAssistSoftRetargetHoldMs) or 0, 4200)
    return task
end

function NPCTacticalAngleBridge.Debug(brain)
    if not brain then return nil end
    local angle = brain.ai and brain.ai.angle or nil
    if not angle then return nil end
    if bta_nowMs() < (tonumber(angle.blockedUntil) or 0) then
        brain.debugAngle = "blocked:" .. tostring(angle.blockedReason or "line")
    elseif angle.coverHold and angle.coverHold.anglePeek then
        brain.debugAngle = "peek:" .. tostring(angle.coverHold.peekSide or 0)
    end
    return brain.debugAngle
end
