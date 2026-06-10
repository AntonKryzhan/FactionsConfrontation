-- NPCCombatPathDisciplineBridge.lua
-- Stage 366: combat-path gate and low-cost tactical stepping for human NPCs.
--
-- Advisory only. This module does not replace shooting, damage, tasks,
-- commands, networking or persistence. It reduces pointless combat path churn
-- by turning blocked/unsafe shots into short bounded sidesteps, by holding
-- firing lanes briefly, and by decorating combat movement tasks with safer
-- B41 path-throttle values.

NPCCombatPathDisciplineBridge = NPCCombatPathDisciplineBridge or {}
NPCCombatPathDisciplineBridge.VERSION = "2026-06-01-stage367-combat-path-morale-discipline-1"

pcall(require, "NPCCore/NPCMovementStabilityBridge")
pcall(require, "NPCCore/NPCIndoorTacticalBridge")
pcall(require, "NPCCore/NPCHumanizedAIBridge")
pcall(require, "NPCCore/NPCTacticalCoverBridge")
pcall(require, "NPCCore/NPCLegacyGlobalsBridge")

NPCCombatPathDisciplineBridge.Config = NPCCombatPathDisciplineBridge.Config or {
    enabled = true,
    holdFireMs = 1050,
    blockedShotRepositionMs = 4300,
    blockedShotCooldownMs = 1150,
    microStepHoldMs = 3000,
    microStepRadius = 3,
    microStepMaxDist = 4.25,
    lineDisciplineRadius = 26,
    sameTargetHoldMs = 5200,
    combatPathThrottleMs = 1300,
    combatSameTargetThrottleMs = 5200,
    shortStepPathThrottleMs = 1500,
    shortStepSameTargetThrottleMs = 7000,
    indoorPathThrottleMs = 1650,
    indoorSameTargetThrottleMs = 6800,
    minimumStepDist = 0.75,
    preferLateralStep = true,
    avoidDoorwayStep = true,
    avoidCrowdedStep = true
}

local function bcp_nowMs()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then return math.floor((getGameTime():getWorldAgeHours() or 0) * 3600000) end
    return 0
end

local function bcp_floor(v)
    return math.floor(tonumber(v) or 0)
end

local function bcp_dist2(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return dx * dx + dy * dy
end

local function bcp_dist(x1, y1, x2, y2)
    return math.sqrt(bcp_dist2(x1, y1, x2, y2))
end

local function bcp_square(x, y, z)
    local cell = getCell and getCell() or nil
    if not cell then return nil end
    return cell:getGridSquare(bcp_floor(x), bcp_floor(y), bcp_floor(z or 0))
end

local function bcp_squareBlocked(square, mover)
    if not square then return true end
    if NPCMovementStabilityBridge and NPCMovementStabilityBridge.IsSquareBlocked then
        local ok, blocked = pcall(function() return NPCMovementStabilityBridge.IsSquareBlocked(square, mover) end)
        if ok then return blocked == true end
    end
    local ok, solid = pcall(function() return square:isSolid() or square:isSolidTrans() end)
    return ok and solid == true
end

local function bcp_canStep(mover, fromSq, toSq)
    if not (fromSq and toSq) then return false end
    if bcp_squareBlocked(toSq, mover) then return false end
    if NPCMovementStabilityBridge and NPCMovementStabilityBridge.CanStepBetween then
        local ok, can = pcall(function() return NPCMovementStabilityBridge.CanStepBetween(mover, fromSq, toSq) end)
        if ok then return can == true end
    end
    local dx = toSq:getX() - fromSq:getX()
    local dy = toSq:getY() - fromSq:getY()
    if math.abs(dx) > 1 or math.abs(dy) > 1 then return false end
    local ok, blocked = pcall(function() return fromSq:testCollideAdjacent(mover, dx, dy, 0) end)
    if ok and blocked then return false end
    return true
end

local function bcp_actorId(actor, brain)
    if brain then
        if brain.persistentId then return tostring(brain.persistentId) end
        if brain.uid then return tostring(brain.uid) end
        if brain.id then return tostring(brain.id) end
    end
    if actor and NPCUtils and NPCUtils.GetCharacterID then
        local ok, id = pcall(function() return NPCUtils.GetCharacterID(actor) end)
        if ok and id then return tostring(id) end
    end
    return actor and tostring(actor) or "unknown"
end

local function bcp_targetFromThreat(threat)
    if type(threat) ~= "table" then return nil end
    if threat.target then return threat.target end
    if threat.actor then return threat.actor end
    if threat.zombie then return threat.zombie end
    if threat.character then return threat.character end
    return nil
end

local function bcp_contactPoint(targetOrThreat, bandit)
    if targetOrThreat and targetOrThreat.getX and targetOrThreat.getY then
        return {
            x = targetOrThreat:getX(),
            y = targetOrThreat:getY(),
            z = targetOrThreat.getZ and targetOrThreat:getZ() or (bandit and bandit:getZ()) or 0,
            target = targetOrThreat
        }
    end
    if type(targetOrThreat) == "table" and targetOrThreat.x and targetOrThreat.y then
        return {
            x = tonumber(targetOrThreat.x),
            y = tonumber(targetOrThreat.y),
            z = tonumber(targetOrThreat.z) or (bandit and bandit:getZ()) or 0,
            target = bcp_targetFromThreat(targetOrThreat)
        }
    end
    return nil
end

local function bcp_isIndoor(square)
    if not square then return false end
    if NPCIndoorTacticalBridge and NPCIndoorTacticalBridge.IsInteriorSquare then
        local ok, v = pcall(function() return NPCIndoorTacticalBridge.IsInteriorSquare(square) end)
        if ok then return v == true end
    end
    local ok, room = pcall(function() return square:getRoom() end)
    return ok and room ~= nil
end

local function bcp_scoreSquare(bandit, brain, square, contact, reason)
    if not (bandit and square) then return -9999 end
    if bcp_squareBlocked(square, bandit) then return -9999 end
    local fromSq = bandit.getSquare and bandit:getSquare() or nil
    if fromSq and not bcp_canStep(bandit, fromSq, square) then return -9999 end

    local sx, sy, sz = square:getX(), square:getY(), square:getZ()
    local bx, by = bandit:getX(), bandit:getY()
    local distSelf = bcp_dist(bx, by, sx + 0.5, sy + 0.5)
    if distSelf < (tonumber(NPCCombatPathDisciplineBridge.Config.minimumStepDist) or 0.75) then return -999 end
    if distSelf > (tonumber(NPCCombatPathDisciplineBridge.Config.microStepMaxDist) or 4.25) then return -999 end

    local score = 20 - distSelf * 2.3
    local tx = contact and contact.x or bx
    local ty = contact and contact.y or by
    local dx = tx - bx
    local dy = ty - by
    local len = math.sqrt(dx * dx + dy * dy)
    if len > 0.05 then
        local ux, uy = dx / len, dy / len
        local sxv = (sx + 0.5) - bx
        local syv = (sy + 0.5) - by
        local along = sxv * ux + syv * uy
        local lateral = math.abs(sxv * (-uy) + syv * ux)
        if NPCCombatPathDisciplineBridge.Config.preferLateralStep ~= false then
            score = score + math.min(lateral * 3.0, 7.0)
            score = score - math.max(along, 0) * 1.1
        end
        local futureDist = bcp_dist(sx + 0.5, sy + 0.5, tx, ty)
        if futureDist < 2.25 then score = score - 16 end
        if futureDist > 18 then score = score - 4 end
    end

    if NPCIndoorTacticalBridge then
        if NPCIndoorTacticalBridge.ScoreSquare then
            local okIndoor, indoorScore = pcall(function()
                return NPCIndoorTacticalBridge.ScoreSquare(bandit, brain, square, tx, ty, "CombatPath", reason or "combat path discipline")
            end)
            if okIndoor and tonumber(indoorScore) then score = score + tonumber(indoorScore) end
        end
        if NPCCombatPathDisciplineBridge.Config.avoidDoorwayStep ~= false and NPCIndoorTacticalBridge.IsDoorwaySquare then
            local okDoor, door = pcall(function() return NPCIndoorTacticalBridge.IsDoorwaySquare(square) end)
            if okDoor and door == true then score = score - 18 end
        end
    end

    if bcp_isIndoor(square) then score = score + 2.5 end
    if NPCCombatPathDisciplineBridge.Config.avoidCrowdedStep ~= false and NPCHumanizedAIBridge and NPCHumanizedAIBridge.CountCrowdAround then
        local okCrowd, crowd = pcall(function()
            return NPCHumanizedAIBridge.CountCrowdAround(bandit, brain, sx + 0.5, sy + 0.5, sz, 1.6)
        end)
        if okCrowd and tonumber(crowd) then score = score - tonumber(crowd) * 9 end
    end

    return score
end

local function bcp_cachePoint(brain, point, now)
    if not (brain and point and point.x and point.y) then return point end
    brain.combatPath = brain.combatPath or {}
    brain.combatPath.point = point
    brain.combatPath.pointUntil = (now or bcp_nowMs()) + (tonumber(NPCCombatPathDisciplineBridge.Config.microStepHoldMs) or 2400)
    return point
end

function NPCCombatPathDisciplineBridge.MarkHoldFire(shooter, target, brain, reason)
    if NPCCombatPathDisciplineBridge.Config.enabled == false then return end
    if not brain then return end
    local now = bcp_nowMs()
    brain.combat = brain.combat or {}
    brain.combat.holdFireLineUntil = math.max(tonumber(brain.combat.holdFireLineUntil) or 0, now + (tonumber(NPCCombatPathDisciplineBridge.Config.holdFireMs) or 850))
    brain.combat.blockedShotUntil = math.max(tonumber(brain.combat.blockedShotUntil) or 0, now + (tonumber(NPCCombatPathDisciplineBridge.Config.blockedShotRepositionMs) or 3600))
    brain.combat.blockedShotReason = reason or "blocked shot"
    brain.combat.blockedShotTargetId = bcp_actorId(target)
    if target and target.getX and target.getY then
        brain.combat.blockedShotX = target:getX()
        brain.combat.blockedShotY = target:getY()
        brain.combat.blockedShotZ = target.getZ and target:getZ() or (shooter and shooter:getZ()) or 0
    end
end

function NPCCombatPathDisciplineBridge.ShouldRequestReposition(bandit, brain, targetOrThreat)
    if NPCCombatPathDisciplineBridge.Config.enabled == false then return false end
    if not (bandit and brain and brain.combat) then return false end
    local now = bcp_nowMs()
    if now > (tonumber(brain.combat.blockedShotUntil) or 0) then return false end
    local last = tonumber(brain.combat.blockedShotRepositionAt) or 0
    if now - last < (tonumber(NPCCombatPathDisciplineBridge.Config.blockedShotCooldownMs) or 1150) then return false end
    local contact = bcp_contactPoint(targetOrThreat, bandit)
    if not contact and brain.combat.blockedShotX and brain.combat.blockedShotY then
        contact = {x = brain.combat.blockedShotX, y = brain.combat.blockedShotY, z = brain.combat.blockedShotZ or bandit:getZ()}
    end
    if not contact then return false end
    if bcp_dist2(bandit:getX(), bandit:getY(), contact.x, contact.y) > (NPCCombatPathDisciplineBridge.Config.lineDisciplineRadius or 26) ^ 2 then return false end
    return true
end

function NPCCombatPathDisciplineBridge.GetMicroRepositionPoint(bandit, brain, targetOrThreat, reason)
    if NPCCombatPathDisciplineBridge.Config.enabled == false then return nil end
    if not (bandit and bandit.getX and bandit.getY) then return nil end
    local now = bcp_nowMs()
    if brain and brain.combatPath and brain.combatPath.point and now < (tonumber(brain.combatPath.pointUntil) or 0) then
        local p = brain.combatPath.point
        if p.x and p.y and bcp_dist2(bandit:getX(), bandit:getY(), p.x, p.y) > 0.55 then return p end
    end

    local contact = bcp_contactPoint(targetOrThreat, bandit)
    if not contact then return nil end
    local fromSq = bandit.getSquare and bandit:getSquare() or bcp_square(bandit:getX(), bandit:getY(), bandit:getZ())
    if not fromSq then return nil end

    local bx, by, bz = bandit:getX(), bandit:getY(), bandit:getZ()
    local radius = tonumber(NPCCombatPathDisciplineBridge.Config.microStepRadius) or 3
    local best, bestScore = nil, -9999
    for r = 1, radius do
        for dx = -r, r do
            for dy = -r, r do
                if math.abs(dx) == r or math.abs(dy) == r then
                    local sq = bcp_square(bx + dx, by + dy, bz)
                    if sq then
                        local score = bcp_scoreSquare(bandit, brain, sq, contact, reason)
                        if score > bestScore then
                            bestScore = score
                            best = sq
                        end
                    end
                end
            end
        end
    end
    if not best or bestScore < -8 then return nil end
    local point = {
        x = best:getX(),
        y = best:getY(),
        z = best:getZ(),
        mode = "combat_path_step",
        role = "line_discipline",
        reason = reason or "line discipline sidestep",
        arriveDist = 1.05,
        holdOnly = false,
        combatPathDiscipline = true,
        tacticalStep = true,
        indoor = bcp_isIndoor(best)
    }
    return bcp_cachePoint(brain, point, now)
end

function NPCCombatPathDisciplineBridge.ChooseState(bandit, brain, threat, states)
    if NPCCombatPathDisciplineBridge.Config.enabled == false or not states then return nil end
    if not NPCCombatPathDisciplineBridge.ShouldRequestReposition(bandit, brain, threat) then return nil end
    local p = NPCCombatPathDisciplineBridge.GetMicroRepositionPoint(bandit, brain, threat, "blocked line reposition")
    if not p then return nil end
    if brain and brain.combat then brain.combat.blockedShotRepositionAt = bcp_nowMs() end
    if states.TacticalCover then return states.TacticalCover, "blocked firing line reposition" end
    return states.SearchEnemy, "blocked firing line reposition"
end

function NPCCombatPathDisciplineBridge.DecorateCombatMoveTask(task, bandit, brain, threat, state)
    if NPCCombatPathDisciplineBridge.Config.enabled == false or not task then return task end
    local indoor = task.indoorTactical == true or task.indoor == true
    if not indoor and NPCIndoorTacticalBridge and bandit and bandit.getSquare then
        local ok, v = pcall(function() return NPCIndoorTacticalBridge.IsInteriorSquare(bandit:getSquare()) end)
        indoor = ok and v == true
    end

    task.combatMove = true
    task.tacticalStep = true
    task.engineAssist = true
    task.naturalMotion = true
    task.smoothTurn = true
    task.combatPathDiscipline = true
    task.arriveDist = math.max(tonumber(task.arriveDist) or 1.05, 1.05)

    if task.combatPathShortStep == true or task.combatPathDisciplineShort == true then
        task.pathThrottleMs = math.max(tonumber(task.pathThrottleMs) or 0, tonumber(NPCCombatPathDisciplineBridge.Config.shortStepPathThrottleMs) or 1500)
        task.sameTargetPathThrottleMs = math.max(tonumber(task.sameTargetPathThrottleMs) or 0, tonumber(NPCCombatPathDisciplineBridge.Config.shortStepSameTargetThrottleMs) or 6200)
        task.engineAssistSoftRetargetRadius = math.max(tonumber(task.engineAssistSoftRetargetRadius) or 0, 3.0)
        task.engineAssistSoftRetargetHoldMs = math.max(tonumber(task.engineAssistSoftRetargetHoldMs) or 0, 5200)
    elseif indoor then
        task.pathThrottleMs = math.max(tonumber(task.pathThrottleMs) or 0, tonumber(NPCCombatPathDisciplineBridge.Config.indoorPathThrottleMs) or 1650)
        task.sameTargetPathThrottleMs = math.max(tonumber(task.sameTargetPathThrottleMs) or 0, tonumber(NPCCombatPathDisciplineBridge.Config.indoorSameTargetThrottleMs) or 6800)
        task.engineAssistSoftRetargetRadius = math.max(tonumber(task.engineAssistSoftRetargetRadius) or 0, 3.25)
        task.engineAssistSoftRetargetHoldMs = math.max(tonumber(task.engineAssistSoftRetargetHoldMs) or 0, 5600)
    else
        task.pathThrottleMs = math.max(tonumber(task.pathThrottleMs) or 0, tonumber(NPCCombatPathDisciplineBridge.Config.combatPathThrottleMs) or 1300)
        task.sameTargetPathThrottleMs = math.max(tonumber(task.sameTargetPathThrottleMs) or 0, tonumber(NPCCombatPathDisciplineBridge.Config.combatSameTargetThrottleMs) or 5200)
        task.engineAssistSoftRetargetRadius = math.max(tonumber(task.engineAssistSoftRetargetRadius) or 0, 3.0)
        task.engineAssistSoftRetargetHoldMs = math.max(tonumber(task.engineAssistSoftRetargetHoldMs) or 0, 5000)
    end
    return task
end

function NPCCombatPathDisciplineBridge.GetStateDebug(brain)
    if not (brain and brain.combat) then return nil end
    local now = bcp_nowMs()
    if now <= (tonumber(brain.combat.blockedShotUntil) or 0) then
        return "blocked-line"
    end
    return nil
end
