-- NPCTacticalRetreatBridge.lua
-- Stage 375: bounded tactical retreat / reinforcement / surrender-discipline layer.
--
-- Runtime-only advisory layer. It does not add network commands, task names,
-- damage contracts or save roots. The bridge selects safer existing states and
-- produces short movement/hold tasks only when pressure is high, so squads can
-- fall back, regroup, call help or stop fighting without path spam.

NPCTacticalRetreatBridge = NPCTacticalRetreatBridge or {}
NPCTacticalRetreatBridge.VERSION = "2026-06-01-stage375-tactical-retreat-1"

pcall(require, "NPCCore/NPCTacticalCoverBridge")
pcall(require, "NPCCore/NPCFireteamMoraleBridge")
pcall(require, "NPCCore/NPCSquadMemoryBridge")
pcall(require, "NPCCore/NPCTacticalRadioBridge")
pcall(require, "NPCCore/NPCTacticalFireteamBridge")
pcall(require, "NPCCore/NPCIndoorTacticalBridge")
pcall(require, "NPCCore/NPCMovementStabilityBridge")

NPCTacticalRetreatBridge.Config = NPCTacticalRetreatBridge.Config or {
    enabled = true,
    lowHealth = 0.38,
    criticalHealth = 0.20,
    surrenderHealth = 0.16,
    surrenderEnabled = true,
    surrenderMs = 9000,
    surrenderCooldownMs = 45000,
    retreatCooldownMs = 7600,
    regroupCooldownMs = 4800,
    reinforcementCooldownMs = 18000,
    pressureMemoryMs = 9000,
    maxRegroupDist = 18,
    fallbackStep = 6.5,
    criticalFallbackStep = 9.5,
    minAlliesForRegroup = 2,
    outnumberedRatio = 1.65,
    noSurrenderForPlayerHired = true,
    noSurrenderForBaseGuards = false,
    indoorWalkRetreat = true,
    debug = false
}

local function btr_nowMs()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then
        local ok, hours = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok and hours then return math.floor((tonumber(hours) or 0) * 3600000) end
    end
    return 0
end

local function btr_debug(msg)
    if NPCTacticalRetreatBridge.Config.debug == true then
        print("[NPCTacticalRetreat] " .. tostring(msg))
    end
end

local function btr_health01(chr, brain)
    local h = tonumber(brain and brain.health)
    if h then return math.max(0, math.min(1, h)) end
    if chr and chr.getHealth then
        local ok, v = pcall(function() return chr:getHealth() end)
        if ok and tonumber(v) then
            v = tonumber(v)
            if v > 1 then v = v / 100 end
            return math.max(0, math.min(1, v))
        end
    end
    return 1
end

local function btr_dist(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return math.sqrt(dx * dx + dy * dy)
end

local function btr_threatPoint(threat, chr)
    if type(threat) == "table" and threat.x and threat.y then
        return {
            x = tonumber(threat.x),
            y = tonumber(threat.y),
            z = tonumber(threat.z) or (chr and chr.getZ and chr:getZ()) or 0,
            dist = tonumber(threat.dist),
            target = threat.target or threat.actor or threat.character or threat.zombie,
            kind = tostring(threat.kind or "unknown"),
            canSee = threat.canSee == true,
            memoryOnly = threat.memoryOnly == true,
            confidence = tonumber(threat.confidence) or 0.5
        }
    end
    if threat and threat.getX and threat.getY then
        return {
            x = threat:getX(),
            y = threat:getY(),
            z = threat.getZ and threat:getZ() or (chr and chr.getZ and chr:getZ()) or 0,
            dist = chr and chr.getX and btr_dist(chr:getX(), chr:getY(), threat:getX(), threat:getY()) or nil,
            target = threat,
            kind = "bandit",
            canSee = true,
            confidence = 1
        }
    end
    return nil
end

local function btr_isPlayerControlled(brain)
    if type(brain) ~= "table" then return false end
    if brain.master ~= nil or brain.mercenaryHired == true or brain.hired == true or brain.isPlayerGuard == true then return true end
    if brain.mercenaryHiredBy ~= nil or brain.relationshipToPlayer == "hired_bodyguard" or brain.relationshipToPlayer == "companion" then return true end
    local order = brain.order or brain.directorOrder or brain.mercenaryOrder
    if type(order) == "table" then
        if order.source == "player" or order.master ~= nil or order.playerId ~= nil or order.manual == true then return true end
        local name = tostring(order.name or order.orderName or order.action or order.type or order.mode or ""):lower()
        if name == "follow" or name == "guard" or name == "hold" or name == "loot" or name == "return" then return true end
    elseif order ~= nil then
        local name = tostring(order):lower()
        if name == "follow" or name == "guard" or name == "hold" or name == "loot" or name == "return" then return true end
    end
    return false
end

local function btr_groupKey(brain)
    if type(brain) ~= "table" then return nil end
    return tostring(brain.worldGroupId or brain.groupId or brain.physicalGroupId or brain.squadId or brain.clan or "")
end

local function btr_channel(brain)
    local key = btr_groupKey(brain)
    if not key or key == "" then return nil end
    if NPCTacticalFireteamBridge and NPCTacticalFireteamBridge.Channels and NPCTacticalFireteamBridge.Channels[key] then
        return NPCTacticalFireteamBridge.Channels[key]
    end
    if NPCTacticalRadioBridge and NPCTacticalRadioBridge.Channels and NPCTacticalRadioBridge.Channels[key] then
        return NPCTacticalRadioBridge.Channels[key]
    end
    return nil
end

local function btr_countFreshMembers(brain, maxAgeMs)
    local ch = btr_channel(brain)
    if not ch or type(ch.members) ~= "table" then return 1 end
    local now = btr_nowMs()
    local count = 0
    maxAgeMs = tonumber(maxAgeMs) or 12000
    for _, m in pairs(ch.members) do
        if type(m) == "table" and now - (tonumber(m.updatedAt) or 0) <= maxAgeMs then
            count = count + 1
        end
    end
    if count <= 0 then count = 1 end
    return count
end

local function btr_countFreshContacts(brain, maxAgeMs)
    local ch = btr_channel(brain)
    if not ch or type(ch.contacts) ~= "table" then return 0 end
    local now = btr_nowMs()
    local count = 0
    maxAgeMs = tonumber(maxAgeMs) or 12000
    for _, c in pairs(ch.contacts) do
        if type(c) == "table" and now - (tonumber(c.reportedAt) or 0) <= maxAgeMs then
            count = count + 1
        end
    end
    return count
end

local function btr_state(brain)
    if type(brain) ~= "table" then return nil end
    brain.tacticalRetreat = brain.tacticalRetreat or {}
    return brain.tacticalRetreat
end

local function btr_squareUsable(x, y, z, mover)
    local cell = getCell and getCell() or nil
    if not cell then return false end
    local sq = cell:getGridSquare(math.floor(x), math.floor(y), math.floor(z or 0))
    if not sq then return false end
    if NPCMovementStabilityBridge and NPCMovementStabilityBridge.IsSquareBlocked then
        local ok, blocked = pcall(function() return NPCMovementStabilityBridge.IsSquareBlocked(sq, mover) end)
        if ok and blocked == true then return false end
    end
    local ok, solid = pcall(function() return sq:isSolid() or sq:isSolidTrans() end)
    if ok and solid == true then return false end
    return true
end

local function btr_findFreeAround(x, y, z, radius, mover)
    radius = tonumber(radius) or 4
    local bx = math.floor(tonumber(x) or 0)
    local by = math.floor(tonumber(y) or 0)
    local bz = math.floor(tonumber(z) or 0)
    for r = 0, radius do
        for dx = -r, r do
            for dy = -r, r do
                if r == 0 or math.abs(dx) == r or math.abs(dy) == r then
                    local sx = bx + dx
                    local sy = by + dy
                    if btr_squareUsable(sx, sy, bz, mover) then return sx, sy, bz end
                end
            end
        end
    end
    return nil
end

local function btr_isIndoor(chr)
    local sq = chr and chr.getSquare and chr:getSquare() or nil
    if not sq then return false end
    if NPCIndoorTacticalBridge and NPCIndoorTacticalBridge.IsInteriorSquare then
        local ok, indoor = pcall(function() return NPCIndoorTacticalBridge.IsInteriorSquare(sq) end)
        if ok then return indoor == true end
    end
    local ok, room = pcall(function() return sq:getRoom() end)
    return ok and room ~= nil
end

local function btr_bestRegroupPoint(chr, brain, threat)
    local ch = btr_channel(brain)
    local now = btr_nowMs()
    local best, bestScore
    if ch and type(ch.members) == "table" then
        for _, m in pairs(ch.members) do
            if type(m) == "table" and m.x and m.y and now - (tonumber(m.updatedAt) or 0) <= 12000 then
                local dSelf = btr_dist(chr:getX(), chr:getY(), m.x, m.y)
                if dSelf <= (tonumber(NPCTacticalRetreatBridge.Config.maxRegroupDist) or 18) and dSelf > 1.2 then
                    local score = 20 - dSelf
                    if threat and threat.x and threat.y then
                        score = score + math.min(8, btr_dist(m.x, m.y, threat.x, threat.y) * 0.3)
                    end
                    if not bestScore or score > bestScore then
                        bestScore = score
                        best = m
                    end
                end
            end
        end
    end
    if best and best.x and best.y then
        local fx, fy, fz = btr_findFreeAround(best.x, best.y, best.z or chr:getZ(), 4, chr)
        if fx and fy then return {x = fx, y = fy, z = fz, reason = "regroup with fireteam"} end
    end
    return nil
end

local function btr_fallbackPoint(chr, threat, critical)
    if not (chr and threat and threat.x and threat.y) then return nil end
    local dx = chr:getX() - threat.x
    local dy = chr:getY() - threat.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.01 then len = 1 end
    local step = critical and (tonumber(NPCTacticalRetreatBridge.Config.criticalFallbackStep) or 9.5) or (tonumber(NPCTacticalRetreatBridge.Config.fallbackStep) or 6.5)
    local tx = chr:getX() + dx / len * step
    local ty = chr:getY() + dy / len * step
    local fx, fy, fz = btr_findFreeAround(tx, ty, chr:getZ(), 5, chr)
    if fx and fy then return {x = fx, y = fy, z = fz, reason = critical and "critical fallback" or "fallback under pressure"} end
    return nil
end

local function btr_canSurrender(chr, brain, health, allies, enemies, threat)
    if NPCTacticalRetreatBridge.Config.surrenderEnabled == false then return false end
    if not (chr and brain and threat) then return false end
    if health > (tonumber(NPCTacticalRetreatBridge.Config.surrenderHealth) or 0.16) then return false end
    if NPCTacticalRetreatBridge.Config.noSurrenderForPlayerHired ~= false and btr_isPlayerControlled(brain) then return false end
    if NPCTacticalRetreatBridge.Config.noSurrenderForBaseGuards == true and (brain.homeBase or brain.homeBaseZone or brain.baseZoneType) then return false end
    if brain.hostile == false and brain.factionState == "civilian" then return false end
    if allies > 1 and enemies <= allies then return false end
    local st = btr_state(brain)
    local now = btr_nowMs()
    if st and now - (tonumber(st.lastSurrenderAt) or -999999) < (tonumber(NPCTacticalRetreatBridge.Config.surrenderCooldownMs) or 45000) then return false end
    return true
end

function NPCTacticalRetreatBridge.RequestReinforcement(chr, brain, threat, reason)
    if NPCTacticalRetreatBridge.Config.enabled == false or not (chr and brain and threat) then return false end
    local st = btr_state(brain)
    if not st then return false end
    local now = btr_nowMs()
    if now - (tonumber(st.lastReinforcementRequestAt) or 0) < (tonumber(NPCTacticalRetreatBridge.Config.reinforcementCooldownMs) or 18000) then return false end
    st.lastReinforcementRequestAt = now
    st.reinforcementRequestedUntil = now + 14000
    st.reinforcementReason = reason or "under pressure"
    st.reinforcementX = tonumber(threat.x)
    st.reinforcementY = tonumber(threat.y)
    st.reinforcementZ = tonumber(threat.z) or (chr.getZ and chr:getZ()) or 0

    local ch = btr_channel(brain)
    if ch then
        ch.plan = ch.plan or {}
        ch.plan.reinforcementRequestedAt = now
        ch.plan.reinforcementX = st.reinforcementX
        ch.plan.reinforcementY = st.reinforcementY
        ch.plan.reinforcementZ = st.reinforcementZ
        ch.plan.reinforcementReason = st.reinforcementReason
        ch.plan.updatedAt = now
    end

    if NPCTacticalRadioBridge and NPCTacticalRadioBridge.ReportContact and threat.target then
        pcall(function()
            NPCTacticalRadioBridge.ReportContact(chr, brain, threat.target, threat.kind or "bandit", threat.dist or 12, 0.9)
        end)
    end

    btr_debug("reinforcement requested: " .. tostring(reason))
    return true
end

function NPCTacticalRetreatBridge.Update(chr, brain, threat, runtime)
    if NPCTacticalRetreatBridge.Config.enabled == false or not (chr and brain) then return nil end
    local st = btr_state(brain)
    if not st then return nil end
    local now = runtime and runtime.now and runtime.now() or btr_nowMs()
    local health = btr_health01(chr, brain)
    local contact = btr_threatPoint(threat, chr)
    local allies = btr_countFreshMembers(brain, 12000)
    local enemies = btr_countFreshContacts(brain, 12000)
    if contact then enemies = math.max(enemies, 1) end

    local pressure = 0
    if contact then
        local dist = tonumber(contact.dist) or btr_dist(chr:getX(), chr:getY(), contact.x, contact.y)
        pressure = pressure + math.max(0, 1 - dist / 22)
        if contact.canSee then pressure = pressure + 0.20 end
        if contact.memoryOnly then pressure = pressure - 0.15 end
        st.lastThreatAt = now
        st.lastThreatX = contact.x
        st.lastThreatY = contact.y
        st.lastThreatZ = contact.z
        st.lastThreatKind = contact.kind
    end
    if health < (NPCTacticalRetreatBridge.Config.lowHealth or 0.38) then pressure = pressure + 0.30 end
    if health < (NPCTacticalRetreatBridge.Config.criticalHealth or 0.20) then pressure = pressure + 0.35 end
    if enemies > allies then pressure = pressure + math.min(0.35, (enemies - allies) * 0.12) end

    st.health = health
    st.allies = allies
    st.enemies = enemies
    st.pressure = math.max(0, math.min(1.5, pressure))
    st.updatedAt = now

    if contact and (st.pressure >= 0.70 or enemies >= allies + 2 or health < (NPCTacticalRetreatBridge.Config.lowHealth or 0.38)) then
        NPCTacticalRetreatBridge.RequestReinforcement(chr, brain, contact, st.pressure >= 0.95 and "critical pressure" or "under pressure")
    end
    return st
end

function NPCTacticalRetreatBridge.ChooseState(chr, brain, threat, states)
    if NPCTacticalRetreatBridge.Config.enabled == false or not (chr and brain and states) then return nil end
    local contact = btr_threatPoint(threat, chr)
    if not contact then return nil end

    local now = btr_nowMs()
    local st = NPCTacticalRetreatBridge.Update(chr, brain, contact)
    if not st then return nil end

    local health = st.health or btr_health01(chr, brain)
    local allies = tonumber(st.allies) or 1
    local enemies = tonumber(st.enemies) or 1
    local pressure = tonumber(st.pressure) or 0
    local dist = tonumber(contact.dist) or btr_dist(chr:getX(), chr:getY(), contact.x, contact.y)
    local playerControlled = btr_isPlayerControlled(brain)

    if btr_canSurrender(chr, brain, health, allies, enemies, contact) then
        st.surrenderUntil = now + (tonumber(NPCTacticalRetreatBridge.Config.surrenderMs) or 9000)
        st.lastSurrenderAt = now
        st.surrenderX = contact.x
        st.surrenderY = contact.y
        st.surrenderZ = contact.z
        return states.HoldAngle or states.HoldPosition, "panic surrender discipline"
    end

    if health <= (tonumber(NPCTacticalRetreatBridge.Config.criticalHealth) or 0.20) then
        if allies >= (tonumber(NPCTacticalRetreatBridge.Config.minAlliesForRegroup) or 2) and not (dist and dist < 3.4) then
            if now - (tonumber(st.lastRegroupAt) or 0) > (tonumber(NPCTacticalRetreatBridge.Config.regroupCooldownMs) or 4800) then
                st.lastRegroupAt = now
                return states.Regroup, playerControlled and "fall back to formation" or "critical regroup with fireteam"
            end
        end
        if now - (tonumber(st.lastRetreatAt) or 0) > (tonumber(NPCTacticalRetreatBridge.Config.retreatCooldownMs) or 7600) then
            st.lastRetreatAt = now
            return states.Flee, playerControlled and "emergency tactical fallback" or "critical tactical retreat"
        end
        return states.TacticalCover or states.Flee, "critical hold cover"
    end

    if pressure >= 0.95 and enemies >= math.max(2, math.ceil(allies * (tonumber(NPCTacticalRetreatBridge.Config.outnumberedRatio) or 1.65))) then
        if not playerControlled and allies <= 1 and health <= 0.28 then
            st.surrenderUntil = now + (tonumber(NPCTacticalRetreatBridge.Config.surrenderMs) or 9000)
            st.lastSurrenderAt = now
            return states.HoldAngle or states.HoldPosition, "outnumbered surrender discipline"
        end
        return states.TacticalCover, "outnumbered fall back to cover"
    end

    if pressure >= 0.72 and health <= (tonumber(NPCTacticalRetreatBridge.Config.lowHealth) or 0.38) then
        if allies >= 2 and dist > 4.5 then
            return states.Regroup, "wounded regroup under pressure"
        end
        return states.TacticalCover, "wounded fallback to cover"
    end

    if pressure >= 0.82 and dist and dist < 5.0 then
        return states.KeepDistance or states.Flee, "danger close fallback"
    end

    return nil
end

function NPCTacticalRetreatBridge.DecorateTask(task, chr, brain, reason)
    if type(task) ~= "table" then return task end
    task.tacticalRetreat = true
    task.engineAssist = true
    task.naturalMotion = true
    task.smoothTurn = task.smoothTurn ~= false
    task.noHardFace = true
    task.arriveDist = math.max(tonumber(task.arriveDist) or 0.9, 1.25)
    task.pathThrottleMs = math.max(tonumber(task.pathThrottleMs) or 0, 1450)
    task.sameTargetPathThrottleMs = math.max(tonumber(task.sameTargetPathThrottleMs) or 0, 5200)
    task.engineAssistSoftRetargetRadius = math.max(tonumber(task.engineAssistSoftRetargetRadius) or 0, 3.2)
    task.engineAssistSoftRetargetHoldMs = math.max(tonumber(task.engineAssistSoftRetargetHoldMs) or 0, 5200)
    task.directorReason = task.directorReason or reason or "tactical retreat"
    return task
end

function NPCTacticalRetreatBridge.PlanTasks(chr, brain, runtime, context)
    if NPCTacticalRetreatBridge.Config.enabled == false or not (chr and brain and runtime and context) then return nil end
    local states = context.states or {}
    local state = context.state
    local reason = tostring(context.reason or ""):lower()
    local threat = btr_threatPoint(context.threat or brain.radioThreat, chr)
    local st = btr_state(brain)
    local now = runtime.now and runtime.now() or btr_nowMs()

    if st and now < (tonumber(st.surrenderUntil) or 0) then
        local tx = (threat and threat.x) or st.surrenderX or st.lastThreatX or (chr:getX() + 1)
        local ty = (threat and threat.y) or st.surrenderY or st.lastThreatY or chr:getY()
        return {
            {
                action = "FaceLocation",
                x = tx,
                y = ty,
                time = 24,
                director = true,
                directorState = states.HoldAngle or state or "HoldAngle",
                directorReason = "panic surrender discipline",
                tacticalRetreat = true,
                noHardFace = true
            },
            {
                action = "Time",
                anim = "Exhausted",
                time = 90,
                director = true,
                directorState = states.HoldAngle or state or "HoldAngle",
                directorReason = "panic surrender discipline",
                tacticalRetreat = true,
                noHardFace = true
            }
        }
    end

    if not threat then return nil end

    if state == states.Regroup or reason:find("regroup", 1, true) then
        local p = btr_bestRegroupPoint(chr, brain, threat) or btr_fallbackPoint(chr, threat, false)
        if p and p.x and p.y then
            local task = runtime.moveToState(chr, states.Regroup or "Regroup", p.reason or "tactical regroup", p.x, p.y, p.z or chr:getZ(), btr_isIndoor(chr) and "Walk" or "Run", true)
            NPCTacticalRetreatBridge.DecorateTask(task, chr, brain, p.reason or "tactical regroup")
            task.arriveDist = math.max(tonumber(task.arriveDist) or 1.25, 1.8)
            task.squadSupport = true
            return {task}
        end
    end

    if state == states.TacticalCover or reason:find("cover", 1, true) or reason:find("fallback", 1, true) then
        if NPCTacticalCoverBridge and NPCTacticalCoverBridge.GetPoint then
            local okCover, cover = pcall(function() return NPCTacticalCoverBridge.GetPoint(chr, brain, threat, "retreat") end)
            if okCover and cover and cover.x and cover.y then
                local task = runtime.moveToState(chr, states.TacticalCover or "TacticalCover", cover.reason or "retreat to cover", cover.x, cover.y, cover.z or chr:getZ(), "Walk", true)
                NPCTacticalRetreatBridge.DecorateTask(task, chr, brain, "retreat to cover")
                task.combatMove = true
                task.coverMove = true
                return {task}
            end
        end
        local p = btr_fallbackPoint(chr, threat, false)
        if p and p.x and p.y then
            local task = runtime.moveToState(chr, states.TacticalCover or "TacticalCover", p.reason or "fallback to cover", p.x, p.y, p.z or chr:getZ(), btr_isIndoor(chr) and "Walk" or "Run", true)
            NPCTacticalRetreatBridge.DecorateTask(task, chr, brain, p.reason or "fallback to cover")
            task.combatMove = true
            return {task}
        end
    end

    if state == states.Flee or reason:find("retreat", 1, true) or reason:find("emergency tactical fallback", 1, true) then
        local p = btr_fallbackPoint(chr, threat, true)
        if p and p.x and p.y then
            local task = runtime.moveToState(chr, states.Flee or "Flee", p.reason or "tactical retreat", p.x, p.y, p.z or chr:getZ(), "Run", false)
            NPCTacticalRetreatBridge.DecorateTask(task, chr, brain, p.reason or "tactical retreat")
            task.smoothTurn = false
            task.noHardFace = false
            return {task}
        end
    end

    return nil
end
