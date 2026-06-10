-- NPCFireteamMoraleBridge.lua
-- Stage 367: bounded morale / suppression / wounded fallback layer for human NPC fireteams.
--
-- Advisory only. This module does not replace damage, shooting, reload,
-- persistence, networking, loot or task names. It supplies short-lived state and
-- movement hints so wounded/suppressed NPCs seek cover instead of cycling
-- stand-turn-aim or running in circles.

NPCFireteamMoraleBridge = NPCFireteamMoraleBridge or {}
NPCFireteamMoraleBridge.VERSION = "2026-06-01-stage367-morale-suppression-1"

pcall(require, "NPCCore/NPCTacticalCoverBridge")
pcall(require, "NPCCore/NPCCombatPathDisciplineBridge")
pcall(require, "NPCCore/NPCIndoorTacticalBridge")
pcall(require, "NPCCore/NPCMovementStabilityBridge")
pcall(require, "NPCCore/NPCHumanizedAIBridge")
pcall(require, "NPCCore/NPCLegacyGlobalsBridge")

NPCFireteamMoraleBridge.Config = NPCFireteamMoraleBridge.Config or {
    enabled = true,
    lowHealth = 0.42,
    criticalHealth = 0.22,
    suppressionMs = 4200,
    nearMissSuppressionMs = 2600,
    hitSuppressionMs = 7200,
    holdFireStressMs = 1800,
    retreatCooldownMs = 9000,
    coverHoldMs = 6200,
    maxThreatDist = 24,
    coverProbeRadius = 7,
    fallbackDist = 6.5,
    criticalFallbackDist = 9.5,
    moraleRecoverMs = 12000,
    stableAimAfterShotMs = 2400,
    sameDecisionHoldMs = 3200,
    maxCoverAgeMs = 5200,
    avoidPanicFleeWhenGrouped = true,
    indoorFallbackWalk = true
}

local function bfm_nowMs()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then return math.floor((getGameTime():getWorldAgeHours() or 0) * 3600000) end
    return 0
end

local function bfm_dist2(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return dx * dx + dy * dy
end

local function bfm_dist(x1, y1, x2, y2)
    return math.sqrt(bfm_dist2(x1, y1, x2, y2))
end

local function bfm_floor(v)
    return math.floor(tonumber(v) or 0)
end

local function bfm_health01(actor, brain)
    local h = tonumber(brain and brain.health)
    if h then return math.max(0, math.min(1, h)) end
    if actor and actor.getHealth then
        local ok, value = pcall(function() return actor:getHealth() end)
        if ok and tonumber(value) then return math.max(0, math.min(1, tonumber(value))) end
    end
    return 1
end

local function bfm_actorId(actor, brain)
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

local function bfm_threatPoint(threat, actor)
    if threat and threat.getX and threat.getY then
        return {
            x = threat:getX(),
            y = threat:getY(),
            z = threat.getZ and threat:getZ() or (actor and actor.getZ and actor:getZ()) or 0,
            actor = threat,
            canSee = true
        }
    end
    if type(threat) == "table" and threat.x and threat.y then
        return {
            x = tonumber(threat.x),
            y = tonumber(threat.y),
            z = tonumber(threat.z) or (actor and actor.getZ and actor:getZ()) or 0,
            actor = threat.target or threat.actor or threat.zombie or threat.character,
            canSee = threat.canSee == true,
            dist = threat.dist,
            memoryOnly = threat.memoryOnly == true
        }
    end
    return nil
end

local function bfm_square(x, y, z)
    local cell = getCell and getCell() or nil
    if not cell then return nil end
    return cell:getGridSquare(bfm_floor(x), bfm_floor(y), bfm_floor(z or 0))
end

local function bfm_squareBlocked(square, mover)
    if not square then return true end
    if NPCMovementStabilityBridge and NPCMovementStabilityBridge.IsSquareBlocked then
        local ok, blocked = pcall(function() return NPCMovementStabilityBridge.IsSquareBlocked(square, mover) end)
        if ok then return blocked == true end
    end
    local ok, solid = pcall(function() return square:isSolid() or square:isSolidTrans() end)
    return ok and solid == true
end

local function bfm_canStep(mover, fromSq, toSq)
    if not (fromSq and toSq) then return false end
    if bfm_squareBlocked(toSq, mover) then return false end
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

local function bfm_isIndoor(actor, square)
    square = square or (actor and actor.getSquare and actor:getSquare()) or nil
    if not square then return false end
    if NPCIndoorTacticalBridge and NPCIndoorTacticalBridge.IsInteriorSquare then
        local ok, indoor = pcall(function() return NPCIndoorTacticalBridge.IsInteriorSquare(square) end)
        if ok then return indoor == true end
    end
    local ok, room = pcall(function() return square:getRoom() end)
    return ok and room ~= nil
end

local function bfm_countAllies(brain)
    local count = 0
    local groupKey = brain and (brain.worldGroupId or brain.groupId or brain.physicalGroupId or brain.clan) or nil
    if not groupKey or not (NPCTacticalFireteamBridge and NPCTacticalFireteamBridge.Channels) then return 0 end
    local ch = NPCTacticalFireteamBridge.Channels[tostring(groupKey)]
    if not (ch and ch.members) then return 0 end
    local now = bfm_nowMs()
    for _, m in pairs(ch.members) do
        if m and now - (tonumber(m.updatedAt) or 0) < 12000 then count = count + 1 end
    end
    return count
end

local function bfm_state(brain)
    if not brain then return nil end
    brain.fireteamMorale = brain.fireteamMorale or {}
    return brain.fireteamMorale
end

local function bfm_markSuppressed(brain, source, durationMs, reason)
    local st = bfm_state(brain)
    if not st then return nil end
    local now = bfm_nowMs()
    durationMs = tonumber(durationMs) or tonumber(NPCFireteamMoraleBridge.Config.suppressionMs) or 4200
    st.suppressedUntil = math.max(tonumber(st.suppressedUntil) or 0, now + durationMs)
    st.lastPressureAt = now
    st.lastReason = reason or "suppressed"
    if source and source.getX and source.getY then
        st.sourceX = source:getX()
        st.sourceY = source:getY()
        st.sourceZ = source.getZ and source:getZ() or st.sourceZ
    elseif type(source) == "table" and source.x and source.y then
        st.sourceX = tonumber(source.x)
        st.sourceY = tonumber(source.y)
        st.sourceZ = tonumber(source.z) or st.sourceZ
    end
    return st
end

function NPCFireteamMoraleBridge.MarkUnderFire(target, brain, source, reason, hit)
    if NPCFireteamMoraleBridge.Config.enabled == false or not brain then return end
    local duration = hit and (NPCFireteamMoraleBridge.Config.hitSuppressionMs or 7200) or (NPCFireteamMoraleBridge.Config.nearMissSuppressionMs or 2600)
    bfm_markSuppressed(brain, source, duration, reason or (hit and "hit under fire" or "near miss"))
end

function NPCFireteamMoraleBridge.MarkHoldFire(shooter, target, brain, reason)
    if NPCFireteamMoraleBridge.Config.enabled == false or not brain then return end
    local st = bfm_markSuppressed(brain, target, NPCFireteamMoraleBridge.Config.holdFireStressMs or 1800, reason or "hold fire")
    if st then
        local now = bfm_nowMs()
        st.holdFireUntil = math.max(tonumber(st.holdFireUntil) or 0, now + (NPCFireteamMoraleBridge.Config.holdFireStressMs or 1800))
        st.needsLaneChangeUntil = math.max(tonumber(st.needsLaneChangeUntil) or 0, now + 3600)
    end
end

function NPCFireteamMoraleBridge.NotifyShot(shooter, brain, target)
    if NPCFireteamMoraleBridge.Config.enabled == false or not brain then return end
    local st = bfm_state(brain)
    if not st then return end
    local now = bfm_nowMs()
    st.lastShotAt = now
    if target and target.getX and target.getY then
        st.lastShotX = target:getX()
        st.lastShotY = target:getY()
        st.lastShotZ = target.getZ and target:getZ() or (shooter and shooter.getZ and shooter:getZ()) or 0
    end
end

function NPCFireteamMoraleBridge.NotifyDamage(victim, brain, attacker)
    if NPCFireteamMoraleBridge.Config.enabled == false or not brain then return end
    local st = bfm_markSuppressed(brain, attacker, NPCFireteamMoraleBridge.Config.hitSuppressionMs or 7200, "wounded under fire")
    if st then
        local now = bfm_nowMs()
        st.woundedAt = now
        st.needCoverUntil = math.max(tonumber(st.needCoverUntil) or 0, now + (NPCFireteamMoraleBridge.Config.coverHoldMs or 6200))
    end
end

function NPCFireteamMoraleBridge.Update(bandit, brain, threat)
    if NPCFireteamMoraleBridge.Config.enabled == false or not (bandit and brain) then return nil end
    local st = bfm_state(brain)
    if not st then return nil end
    local now = bfm_nowMs()
    local health = bfm_health01(bandit, brain)
    local contact = bfm_threatPoint(threat, bandit)
    local pressure = 0

    if contact and contact.x and contact.y then
        local dist = tonumber(contact.dist) or bfm_dist(bandit:getX(), bandit:getY(), contact.x, contact.y)
        if dist <= (tonumber(NPCFireteamMoraleBridge.Config.maxThreatDist) or 24) then
            pressure = pressure + math.max(0, 1.0 - dist / 24)
            if contact.canSee == true then pressure = pressure + 0.45 end
            if contact.memoryOnly == true then pressure = pressure * 0.55 end
            st.sourceX = contact.x
            st.sourceY = contact.y
            st.sourceZ = contact.z or bandit:getZ()
        end
    end

    if health <= (tonumber(NPCFireteamMoraleBridge.Config.criticalHealth) or 0.22) then
        pressure = pressure + 1.4
        st.needCoverUntil = math.max(tonumber(st.needCoverUntil) or 0, now + (NPCFireteamMoraleBridge.Config.coverHoldMs or 6200))
    elseif health <= (tonumber(NPCFireteamMoraleBridge.Config.lowHealth) or 0.42) then
        pressure = pressure + 0.75
        st.needCoverUntil = math.max(tonumber(st.needCoverUntil) or 0, now + math.floor((NPCFireteamMoraleBridge.Config.coverHoldMs or 6200) * 0.75))
    end

    if now <= (tonumber(st.suppressedUntil) or 0) then pressure = pressure + 0.55 end
    if now <= (tonumber(st.needsLaneChangeUntil) or 0) then pressure = pressure + 0.35 end
    if now - (tonumber(st.lastShotAt) or 0) < (tonumber(NPCFireteamMoraleBridge.Config.stableAimAfterShotMs) or 2400) then pressure = math.max(0, pressure - 0.2) end

    local recoverMs = tonumber(NPCFireteamMoraleBridge.Config.moraleRecoverMs) or 12000
    if now - (tonumber(st.lastPressureAt) or 0) > recoverMs and pressure < 0.2 then
        st.posture = "steady"
        st.pressure = 0
    else
        st.pressure = math.max(0, math.min(2.4, pressure))
        if health <= (tonumber(NPCFireteamMoraleBridge.Config.criticalHealth) or 0.22) then
            st.posture = "critical"
        elseif st.pressure >= 1.25 then
            st.posture = "suppressed"
        elseif st.pressure >= 0.75 then
            st.posture = "cautious"
        else
            st.posture = "steady"
        end
        if pressure >= 0.2 then st.lastPressureAt = now end
    end

    st.health = health
    st.updatedAt = now
    st.memberId = bfm_actorId(bandit, brain)
    brain.debugMorale = st.posture ~= "steady" and ("morale:" .. tostring(st.posture)) or nil
    return st
end

local function bfm_coverPoint(bandit, brain, contact, role)
    if not (NPCTacticalCoverBridge and NPCTacticalCoverBridge.Resolve) then return nil end
    local cover = NPCTacticalCoverBridge.Resolve()
    if not (cover and cover.GetPoint) then return nil end
    local ok, point = pcall(function() return cover.GetPoint(bandit, brain, contact, role or "morale_cover") end)
    if ok and point and point.x and point.y then return point end
    return nil
end

local function bfm_fallbackPoint(bandit, brain, contact, critical)
    if not (bandit and contact and contact.x and contact.y) then return nil end
    local bx, by, bz = bandit:getX(), bandit:getY(), bandit:getZ()
    local dx = bx - contact.x
    local dy = by - contact.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.05 then len = 1 end
    local ux, uy = dx / len, dy / len
    local dist = critical and (NPCFireteamMoraleBridge.Config.criticalFallbackDist or 9.5) or (NPCFireteamMoraleBridge.Config.fallbackDist or 6.5)
    local tx = bx + ux * dist
    local ty = by + uy * dist

    local fromSq = bandit.getSquare and bandit:getSquare() or bfm_square(bx, by, bz)
    local bestSq, bestScore = nil, -9999
    local radius = tonumber(NPCFireteamMoraleBridge.Config.coverProbeRadius) or 7
    for r = 1, radius do
        for ox = -r, r do
            for oy = -r, r do
                if math.abs(ox) == r or math.abs(oy) == r then
                    local sq = bfm_square(tx + ox, ty + oy, bz)
                    if sq and not bfm_squareBlocked(sq, bandit) then
                        local okStep = true
                        if fromSq and bfm_dist2(bx, by, sq:getX() + 0.5, sq:getY() + 0.5) <= 4.2 * 4.2 then
                            okStep = bfm_canStep(bandit, fromSq, sq)
                        end
                        if okStep then
                            local score = 25 - bfm_dist2(sq:getX() + 0.5, sq:getY() + 0.5, tx, ty) * 0.15
                            score = score + bfm_dist(sq:getX() + 0.5, sq:getY() + 0.5, contact.x, contact.y) * 0.35
                            if bfm_isIndoor(bandit, sq) then score = score + 2.5 end
                            if NPCIndoorTacticalBridge and NPCIndoorTacticalBridge.ScoreSquare then
                                local okIndoor, delta = pcall(function()
                                    return NPCIndoorTacticalBridge.ScoreSquare(bandit, brain, sq, contact.x, contact.y, "MoraleFallback", "suppressed fallback")
                                end)
                                if okIndoor and tonumber(delta) then score = score + tonumber(delta) end
                            end
                            if score > bestScore then
                                bestScore = score
                                bestSq = sq
                            end
                        end
                    end
                end
            end
        end
    end
    if not bestSq then return nil end
    return {
        x = bestSq:getX(),
        y = bestSq:getY(),
        z = bestSq:getZ(),
        role = critical and "critical_fallback" or "suppressed_cover",
        mode = critical and "fallback" or "cover",
        reason = critical and "wounded fallback" or "suppressed cover fallback",
        morale = true,
        arriveDist = critical and 1.6 or 1.35,
        indoor = bfm_isIndoor(bandit, bestSq)
    }
end

function NPCFireteamMoraleBridge.GetManeuverPoint(bandit, brain, threat, requestedState)
    if NPCFireteamMoraleBridge.Config.enabled == false or not (bandit and brain) then return nil end
    local st = NPCFireteamMoraleBridge.Update(bandit, brain, threat)
    if not st then return nil end
    local now = bfm_nowMs()
    local contact = bfm_threatPoint(threat, bandit)
    if not contact and st.sourceX and st.sourceY then
        contact = {x = st.sourceX, y = st.sourceY, z = st.sourceZ or bandit:getZ(), memoryOnly = true}
    end
    if not contact then return nil end

    if brain.fireteamMoralePoint and now < (tonumber(brain.fireteamMoralePointUntil) or 0) then
        local cached = brain.fireteamMoralePoint
        if cached and cached.x and cached.y and bfm_dist2(bandit:getX(), bandit:getY(), cached.x, cached.y) > 0.75 then return cached end
    end

    local critical = st.posture == "critical"
    local needsCover = critical or st.posture == "suppressed" or now <= (tonumber(st.needCoverUntil) or 0) or now <= (tonumber(st.needsLaneChangeUntil) or 0)
    if not needsCover then return nil end

    local point = bfm_coverPoint(bandit, brain, contact, critical and "wounded_fallback" or "suppressed_cover")
    if not point then point = bfm_fallbackPoint(bandit, brain, contact, critical) end
    if not point then return nil end

    point.morale = true
    point.combatMove = true
    point.tacticalStep = true
    point.reason = point.reason or (critical and "wounded fallback" or "suppressed cover")
    point.arriveDist = tonumber(point.arriveDist) or (critical and 1.6 or 1.35)
    point.indoor = point.indoor == true or bfm_isIndoor(bandit, bfm_square(point.x, point.y, point.z or bandit:getZ()))
    brain.fireteamMoralePoint = point
    brain.fireteamMoralePointUntil = now + (tonumber(NPCFireteamMoraleBridge.Config.maxCoverAgeMs) or 5200)
    st.lastCoverAt = now
    return point
end

function NPCFireteamMoraleBridge.ChooseState(bandit, brain, threat, states)
    if NPCFireteamMoraleBridge.Config.enabled == false or not states or not (bandit and brain) then return nil end
    local st = NPCFireteamMoraleBridge.Update(bandit, brain, threat)
    if not st then return nil end
    local now = bfm_nowMs()
    local contact = bfm_threatPoint(threat, bandit)
    if not contact and st.sourceX and st.sourceY then contact = {x = st.sourceX, y = st.sourceY, z = st.sourceZ or bandit:getZ(), memoryOnly = true} end
    if not contact then return nil end
    local dist = bfm_dist(bandit:getX(), bandit:getY(), contact.x, contact.y)
    if dist > (tonumber(NPCFireteamMoraleBridge.Config.maxThreatDist) or 24) and st.posture ~= "critical" then return nil end

    if st.posture == "critical" then
        local allies = bfm_countAllies(brain)
        local last = tonumber(st.lastRetreatStateAt) or 0
        if now - last > (tonumber(NPCFireteamMoraleBridge.Config.retreatCooldownMs) or 9000) then
            st.lastRetreatStateAt = now
            if states.TacticalCover and (NPCFireteamMoraleBridge.Config.avoidPanicFleeWhenGrouped ~= false and allies > 1) then
                return states.TacticalCover, "wounded seek squad cover"
            end
            return states.Flee or states.TacticalCover, "critical wounded fallback"
        end
        return states.TacticalCover or states.HoldAngle, "wounded hold cover"
    end

    if st.posture == "suppressed" then
        return states.TacticalCover or states.HoldAngle, "suppressed seek cover"
    end

    if now <= (tonumber(st.needsLaneChangeUntil) or 0) then
        return states.TacticalCover or states.HoldAngle, "blocked lane shift"
    end

    return nil
end

function NPCFireteamMoraleBridge.DecorateTask(task, bandit, brain, threat)
    if not task then return task end
    task.moraleMove = true
    task.combatMove = true
    task.tacticalStep = true
    task.engineAssist = true
    task.naturalMotion = true
    task.smoothTurn = true
    task.arriveDist = math.max(tonumber(task.arriveDist) or 1.25, 1.25)
    task.pathThrottleMs = math.max(tonumber(task.pathThrottleMs) or 0, 1550)
    task.sameTargetPathThrottleMs = math.max(tonumber(task.sameTargetPathThrottleMs) or 0, 6500)
    task.engineAssistSoftRetargetRadius = math.max(tonumber(task.engineAssistSoftRetargetRadius) or 0, 3.1)
    task.engineAssistSoftRetargetHoldMs = math.max(tonumber(task.engineAssistSoftRetargetHoldMs) or 0, 5600)
    if task.indoorTactical == true or task.indoor == true then
        task.pathThrottleMs = math.max(tonumber(task.pathThrottleMs) or 0, 1750)
        task.sameTargetPathThrottleMs = math.max(tonumber(task.sameTargetPathThrottleMs) or 0, 7200)
        if NPCFireteamMoraleBridge.Config.indoorFallbackWalk ~= false then task.walkType = "Walk" end
    end
    return task
end

function NPCFireteamMoraleBridge.GetDebug(brain)
    local st = brain and brain.fireteamMorale or nil
    if not st then return nil end
    if st.posture and st.posture ~= "steady" then return "morale:" .. tostring(st.posture) end
    return nil
end
