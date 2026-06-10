-- NPCTacticalFireteamBridge.lua
-- Stage 363: leader-aware fireteam tactics layered over existing combat/path code.
--
-- This module does not shoot, reload, damage, spawn, network-sync, or replace
-- legacy tasks. It only provides bounded tactical movement hints:
-- cover / overwatch / suppress / flank / bound / room-search.

NPCTacticalFireteamBridge = NPCTacticalFireteamBridge or {}
NPCTacticalFireteamBridge.VERSION = "2026-06-01-stage369-angle-aware-fireteam-cover-1"

pcall(require, "NPCCore/NPCTacticalCoverBridge")
pcall(require, "NPCCore/NPCMovementStabilityBridge")
pcall(require, "NPCCore/NPCHumanizedAIBridge")
pcall(require, "NPCCore/NPCIndoorTacticalBridge")
pcall(require, "NPCCore/NPCIndoorSweepBridge")
pcall(require, "NPCCore/NPCCombatPathDisciplineBridge")
pcall(require, "NPCCore/NPCFireteamMoraleBridge")
pcall(require, "NPCCore/NPCSquadMemoryBridge")
pcall(require, "NPCCore/NPCTacticalAngleBridge")
pcall(require, "NPCCore/NPCLegacyGlobalsBridge")

NPCTacticalFireteamBridge.Config = NPCTacticalFireteamBridge.Config or {
    enabled = true,
    humanThreatOnly = true,
    combatMemoryMs = 78000,
    roleHoldMs = 13000,
    maneuverHoldMs = 5400,
    minManeuverDist = 2.6,
    maxManeuverDist = 16.0,
    preferredCoverDist = 7.5,
    flankOffset = 5.6,
    boundOffset = 4.0,
    overwatchHoldMinDist = 4.5,
    overwatchHoldMaxDist = 16.0,
    cohesionMaxDist = 14.0,
    searchStepMs = 3200,
    searchDurationMs = 52000,
    indoorSearchRadius = 7,
    outdoorSearchRadius = 12,
    maxMembers = 18,
    indoorDoorwayDiscipline = true,
    advancedIndoorSweep = true,
    advancedAngleDiscipline = true
}

NPCTacticalFireteamBridge.Channels = NPCTacticalFireteamBridge.Channels or {}

local function bft_nowMs()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then return math.floor((getGameTime():getWorldAgeHours() or 0) * 3600000) end
    return 0
end

local function bft_rand(n)
    n = tonumber(n) or 1
    if n <= 1 then return 0 end
    if ZombRand then return ZombRand(n) end
    return math.random(0, n - 1)
end

local function bft_dist2(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return dx * dx + dy * dy
end

local function bft_dist(x1, y1, x2, y2)
    return math.sqrt(bft_dist2(x1, y1, x2, y2))
end

local function bft_id(chr)
    if not chr then return nil end
    if NPCUtils and NPCUtils.GetCharacterID then
        local ok, id = pcall(function() return NPCUtils.GetCharacterID(chr) end)
        if ok and id then return tostring(id) end
    end
    if NPCUtils and NPCUtils.GetZombieID then
        local ok, id = pcall(function() return NPCUtils.GetZombieID(chr) end)
        if ok and id then return tostring(id) end
    end
    return tostring(chr)
end

local function bft_memberId(bandit, brain)
    if brain then
        if brain.persistentId then return tostring(brain.persistentId) end
        if brain.uid then return tostring(brain.uid) end
        if brain.id then return tostring(brain.id) end
    end
    return tostring(bft_id(bandit) or "unknown")
end

local function bft_groupKey(brain)
    if NPCTacticalRadioBridge and NPCTacticalRadioBridge.GroupKey then
        local ok, key = pcall(function() return NPCTacticalRadioBridge.GroupKey(brain) end)
        if ok and key then return tostring(key) end
    end
    if not brain then return "nogroup" end
    return tostring(brain.worldGroupId or brain.groupId or brain.physicalGroupId or brain.clan or "nogroup")
end

local function bft_humanThreat(kind)
    kind = tostring(kind or ""):lower()
    return kind == "bandit" or kind == "player" or kind == "survivor" or kind == "npc" or kind == "human"
end

local function bft_square(x, y, z)
    local cell = getCell and getCell() or nil
    if not cell then return nil end
    return cell:getGridSquare(math.floor(tonumber(x) or 0), math.floor(tonumber(y) or 0), math.floor(tonumber(z) or 0))
end

local function bft_squareUsable(x, y, z, mover)
    local sq = bft_square(x, y, z)
    if not sq then return false end
    if NPCMovementStabilityBridge and NPCMovementStabilityBridge.IsSquareBlocked then
        local ok, blocked = pcall(function() return NPCMovementStabilityBridge.IsSquareBlocked(sq, mover) end)
        if ok and blocked == true then return false end
    else
        local ok, solid = pcall(function() return sq:isSolid() or sq:isSolidTrans() end)
        if ok and solid == true then return false end
    end
    local okWater, water = pcall(function()
        if IsoFlagType and IsoFlagType.water and sq.Is then return sq:Is(IsoFlagType.water) end
        return false
    end)
    if okWater and water == true then return false end
    return true
end

local function bft_findUsableAround(x, y, z, radius, mover)
    radius = tonumber(radius) or 5
    local bx = math.floor(tonumber(x) or 0)
    local by = math.floor(tonumber(y) or 0)
    local bz = math.floor(tonumber(z) or 0)
    if bft_squareUsable(bx, by, bz, mover) then return bx, by, bz end
    for r = 1, radius do
        for dx = -r, r do
            for dy = -r, r do
                if math.abs(dx) == r or math.abs(dy) == r then
                    local sx = bx + dx
                    local sy = by + dy
                    if bft_squareUsable(sx, sy, bz, mover) then return sx, sy, bz end
                end
            end
        end
    end
    return nil
end

local function bft_isIndoors(x, y, z)
    local sq = bft_square(x, y, z)
    if not sq then return false end
    local ok, room = pcall(function() return sq:getRoom() end)
    return ok and room ~= nil
end

local function bft_channel(key)
    key = key or "nogroup"
    local ch = NPCTacticalFireteamBridge.Channels[key]
    if not ch then
        ch = {members = {}, plan = {mode = "idle"}, createdAt = bft_nowMs(), rev = 0}
        NPCTacticalFireteamBridge.Channels[key] = ch
    end
    ch.members = ch.members or {}
    ch.plan = ch.plan or {mode = "idle"}
    return ch
end

local function bft_trim(ch, now)
    if not ch then return end
    now = now or bft_nowMs()
    for id, m in pairs(ch.members or {}) do
        if not m or now - (tonumber(m.updatedAt) or 0) > 26000 then
            ch.members[id] = nil
        end
    end
    local p = ch.plan or {}
    if p.mode == "combat" and now - (tonumber(p.lastContactAt) or 0) > (NPCTacticalFireteamBridge.Config.combatMemoryMs or 78000) then
        p.mode = "search"
        p.searchStartedAt = now
        p.nextSearchAt = 0
        p.searchStep = 0
    elseif p.mode == "search" and now - (tonumber(p.searchStartedAt or p.lastContactAt) or 0) > (NPCTacticalFireteamBridge.Config.searchDurationMs or 52000) then
        p.mode = "idle"
        p.contact = nil
        p.roles = nil
        p.searchStep = nil
    end
    ch.plan = p
end

local function bft_sortedMemberIds(ch)
    local ids = {}
    for id, m in pairs(ch and ch.members or {}) do
        if m and m.x and m.y then ids[#ids + 1] = tostring(id) end
    end
    table.sort(ids)
    return ids
end

local function bft_memberIndex(ch, id)
    local ids = bft_sortedMemberIds(ch)
    for i, mid in ipairs(ids) do
        if tostring(mid) == tostring(id) then return i, #ids end
    end
    return 1, #ids
end

local function bft_teamCenter(ch, now)
    now = now or bft_nowMs()
    local sx, sy, sz, n = 0, 0, 0, 0
    for _, m in pairs(ch and ch.members or {}) do
        if m and m.x and m.y and now - (tonumber(m.updatedAt) or 0) < 16000 then
            sx = sx + m.x
            sy = sy + m.y
            sz = sz + (m.z or 0)
            n = n + 1
        end
    end
    if n <= 0 then return nil end
    return {x = sx / n, y = sy / n, z = sz / n, count = n}
end

local function bft_contact(threat, bandit)
    if not threat or not threat.x or not threat.y then return nil end
    local kind = tostring(threat.kind or "bandit")
    if NPCTacticalFireteamBridge.Config.humanThreatOnly ~= false and not bft_humanThreat(kind) then return nil end
    return {
        id = tostring(threat.id or threat.uid or "enemy"),
        x = tonumber(threat.x),
        y = tonumber(threat.y),
        z = tonumber(threat.z) or (bandit and bandit:getZ()) or 0,
        kind = kind,
        canSee = threat.canSee == true,
        confidence = tonumber(threat.confidence or threat.score or 0.5) or 0.5,
        dist = threat.dist
    }
end

local function bft_assignRoles(ch, now)
    local plan = ch.plan or {}
    local ids = bft_sortedMemberIds(ch)
    local count = #ids
    if count <= 0 then return end
    if plan.roles and now < (tonumber(plan.rolesUntil) or 0) then return end

    plan.roles = {}
    local phase = tonumber(plan.phase or 0) or 0
    for i, id in ipairs(ids) do
        local role = "cover"
        if count == 1 then
            role = "solo_cover"
        elseif count == 2 then
            role = (i == 1) and "suppress" or "cross_cover"
        elseif count == 3 then
            if i == 1 then role = "overwatch" elseif i == 2 then role = "suppress" else role = "flank_left" end
        else
            local shifted = ((i + phase - 1) % count) + 1
            if shifted == 1 then role = "overwatch"
            elseif shifted == 2 then role = "suppress"
            elseif shifted == 3 then role = "bound"
            elseif shifted == 4 then role = "flank_left"
            elseif shifted == 5 then role = "flank_right"
            elseif shifted % 2 == 0 then role = "cover"
            else role = "cross_cover" end
        end
        plan.roles[id] = role
    end
    plan.rolesUntil = now + (tonumber(NPCTacticalFireteamBridge.Config.roleHoldMs) or 13000)
    ch.plan = plan
end

function NPCTacticalFireteamBridge.Update(bandit, brain, threat)
    if NPCTacticalFireteamBridge.Config.enabled == false then return nil end
    if not (bandit and brain) then return nil end

    local now = bft_nowMs()
    local key = bft_groupKey(brain)
    local ch = bft_channel(key)
    bft_trim(ch, now)

    local id = bft_memberId(bandit, brain)
    local morale = nil
    if NPCFireteamMoraleBridge and NPCFireteamMoraleBridge.Update then
        local okMorale, m = pcall(function() return NPCFireteamMoraleBridge.Update(bandit, brain, threat) end)
        if okMorale then morale = m end
    end

    ch.members[id] = {
        id = id,
        x = bandit:getX(),
        y = bandit:getY(),
        z = bandit:getZ(),
        updatedAt = now,
        state = brain.state or (brain.fsm and brain.fsm.state),
        action = bandit.getVariableString and bandit:getVariableString("NPC_TASK_ACTION") or nil,
        health = morale and morale.health or nil,
        posture = morale and morale.posture or nil,
        pressure = morale and morale.pressure or nil
    }

    local contact = bft_contact(threat, bandit)
    if NPCSquadMemoryBridge and NPCSquadMemoryBridge.Update then
        pcall(function() NPCSquadMemoryBridge.Update(bandit, brain, threat) end)
    end
    if contact then
        local plan = ch.plan or {}
        plan.mode = "combat"
        plan.contact = contact
        plan.lastContactAt = now
        plan.searchStartedAt = nil
        plan.indoorContact = bft_isIndoors(contact.x, contact.y, contact.z)
        if now - (tonumber(plan.phaseAt) or 0) > (tonumber(NPCTacticalFireteamBridge.Config.roleHoldMs) or 13000) then
            plan.phase = ((tonumber(plan.phase or 0) or 0) + 1) % 3
            plan.phaseAt = now
            plan.rolesUntil = 0
        end
        ch.plan = plan
        bft_assignRoles(ch, now)
        ch.rev = (tonumber(ch.rev) or 0) + 1
    end

    local plan = ch.plan or {}
    local role = plan.roles and plan.roles[id] or nil
    brain.fireteam = brain.fireteam or {}
    brain.fireteam.groupKey = key
    brain.fireteam.memberId = id
    brain.fireteam.role = role
    brain.fireteam.mode = plan.mode or "idle"
    brain.fireteam.contact = plan.contact
    brain.fireteam.indoorContact = plan.indoorContact == true
    return brain.fireteam
end

function NPCTacticalFireteamBridge.GetRole(bandit, brain)
    if not brain then return nil end
    if brain.fireteam and brain.fireteam.role then return brain.fireteam.role end
    local ch = NPCTacticalFireteamBridge.Channels[bft_groupKey(brain)]
    if not ch or not ch.plan then return nil end
    return ch.plan.roles and ch.plan.roles[bft_memberId(bandit, brain)] or nil
end

local function bft_planContact(bandit, brain, threat)
    local contact = bft_contact(threat, bandit)
    if contact then return contact end
    local ch = NPCTacticalFireteamBridge.Channels[bft_groupKey(brain)]
    local p = ch and ch.plan or nil
    if p and p.contact and p.contact.x and p.contact.y then
        return {
            id = p.contact.id,
            x = p.contact.x,
            y = p.contact.y,
            z = p.contact.z or (bandit and bandit:getZ()) or 0,
            kind = p.contact.kind or "bandit",
            dist = bandit and bft_dist(bandit:getX(), bandit:getY(), p.contact.x, p.contact.y) or 0,
            radio = true,
            memoryOnly = threat == nil
        }
    end
    if NPCSquadMemoryBridge and NPCSquadMemoryBridge.Update then
        local okMemory, memoryThreat = pcall(function() return NPCSquadMemoryBridge.Update(bandit, brain, nil) end)
        if okMemory and memoryThreat and memoryThreat.x and memoryThreat.y then
            return {
                x = memoryThreat.x,
                y = memoryThreat.y,
                z = memoryThreat.z or (bandit and bandit:getZ()) or 0,
                kind = memoryThreat.kind or "memory",
                dist = bandit and bft_dist(bandit:getX(), bandit:getY(), memoryThreat.x, memoryThreat.y) or 0,
                radio = true,
                memoryOnly = true,
                heard = true,
                squadMemory = true,
                confidence = memoryThreat.confidence
            }
        end
    end
    return nil
end

function NPCTacticalFireteamBridge.ChooseState(bandit, brain, threat, states)
    if NPCTacticalFireteamBridge.Config.enabled == false or not states then return nil end
    if not (bandit and brain) then return nil end
    local ft = NPCTacticalFireteamBridge.Update(bandit, brain, threat)
    local contact = bft_planContact(bandit, brain, threat)
    if not contact then return nil end

    if NPCFireteamMoraleBridge and NPCFireteamMoraleBridge.ChooseState then
        local okMorale, moraleState, moraleReason = pcall(function()
            return NPCFireteamMoraleBridge.ChooseState(bandit, brain, contact, states)
        end)
        if okMorale and moraleState then
            return moraleState, moraleReason or "fireteam morale"
        end
    end

    local role = ft and ft.role or NPCTacticalFireteamBridge.GetRole(bandit, brain)
    if not role then return nil end
    if (contact.dist or bft_dist(bandit:getX(), bandit:getY(), contact.x, contact.y)) < 2.0 then return nil end

    if role == "flank_left" or role == "flank_right" then
        return states.FlankEnemy, "fireteam " .. role
    elseif role == "bound" then
        return states.BoundForward or states.FlankEnemy, "fireteam bounded advance"
    elseif role == "suppress" then
        return states.SuppressEnemy or states.TacticalCover, "fireteam suppress"
    elseif role == "overwatch" then
        return states.HoldAngle or states.TacticalCover, "fireteam overwatch"
    elseif role == "cross_cover" or role == "cover" or role == "solo_cover" then
        return states.TacticalCover, "fireteam cover"
    end
    return nil
end

local function bft_cachedPoint(brain, role, now)
    local p = brain and brain.fireteamManeuverPoint or nil
    if p and p.x and p.y and now < (tonumber(brain.fireteamManeuverUntil) or 0) and tostring(p.role or "") == tostring(role or "") then
        return p
    end
    return nil
end

local function bft_storePoint(brain, point, role, now)
    if not (brain and point and point.x and point.y) then return point end
    point.role = point.role or role
    point.fireteam = true
    brain.fireteamManeuverPoint = point
    brain.fireteamManeuverUntil = (now or bft_nowMs()) + (tonumber(NPCTacticalFireteamBridge.Config.maneuverHoldMs) or 4200)
    return point
end

local function bft_coverPoint(bandit, brain, contact, role)
    if not (NPCTacticalCoverBridge and NPCTacticalCoverBridge.Resolve) then return nil end
    local cover = NPCTacticalCoverBridge.Resolve()
    if not (cover and cover.GetPoint) then return nil end
    local ok, p = pcall(function() return cover.GetPoint(bandit, brain, contact, role) end)
    if ok and p and p.x and p.y then return p end
    return nil
end

local function bft_centerLimited(point, center)
    if not point or not center then return point end
    local limit = tonumber(NPCTacticalFireteamBridge.Config.cohesionMaxDist) or 14
    if bft_dist(point.x, point.y, center.x, center.y) <= limit then return point end
    local dx = point.x - center.x
    local dy = point.y - center.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.05 then len = 1 end
    local tx = center.x + dx / len * limit
    local ty = center.y + dy / len * limit
    local fx, fy, fz = bft_findUsableAround(tx, ty, point.z or center.z or 0, 5)
    if fx and fy then
        point.x = fx
        point.y = fy
        point.z = fz or point.z or center.z
    end
    return point
end

function NPCTacticalFireteamBridge.GetManeuverPoint(bandit, brain, threat, requestedState)
    if NPCTacticalFireteamBridge.Config.enabled == false then return nil end
    if not (bandit and brain) then return nil end

    local now = bft_nowMs()
    local contact = bft_planContact(bandit, brain, threat)
    if not contact or not contact.x or not contact.y then return nil end
    local role = NPCTacticalFireteamBridge.GetRole(bandit, brain) or "cover"
    local cached = bft_cachedPoint(brain, role, now)
    if cached then return cached end

    if NPCFireteamMoraleBridge and NPCFireteamMoraleBridge.GetManeuverPoint then
        local okMoralePoint, moralePoint = pcall(function()
            return NPCFireteamMoraleBridge.GetManeuverPoint(bandit, brain, contact, requestedState)
        end)
        if okMoralePoint and moralePoint and moralePoint.x and moralePoint.y then
            moralePoint.fireteam = true
            moralePoint.role = moralePoint.role or role
            moralePoint.mode = moralePoint.mode or "morale_cover"
            moralePoint.arriveDist = tonumber(moralePoint.arriveDist) or 1.35
            return bft_storePoint(brain, bft_centerLimited(moralePoint, bft_teamCenter(NPCTacticalFireteamBridge.Channels[bft_groupKey(brain)], now) or {x = bandit:getX(), y = bandit:getY(), z = bandit:getZ()}), role, now)
        end
    end

    if NPCCombatPathDisciplineBridge and NPCCombatPathDisciplineBridge.ShouldRequestReposition and NPCCombatPathDisciplineBridge.GetMicroRepositionPoint then
        local okNeed, need = pcall(function() return NPCCombatPathDisciplineBridge.ShouldRequestReposition(bandit, brain, contact) end)
        if okNeed and need == true then
            local okStep, step = pcall(function() return NPCCombatPathDisciplineBridge.GetMicroRepositionPoint(bandit, brain, contact, "fireteam line sidestep") end)
            if okStep and step and step.x and step.y then
                step.fireteam = true
                step.role = role
                step.mode = step.mode or "combat_path_step"
                step.arriveDist = tonumber(step.arriveDist) or 1.05
                step.combatPathDiscipline = true
                step.combatPathDisciplineShort = true
                return bft_storePoint(brain, step, role, now)
            end
        end
    end

    if NPCTacticalFireteamBridge.Config.advancedAngleDiscipline ~= false
        and NPCTacticalAngleBridge and NPCTacticalAngleBridge.ShouldRequestPeek and NPCTacticalAngleBridge.GetPeekPoint then
        local okNeedAngle, needAngle = pcall(function() return NPCTacticalAngleBridge.ShouldRequestPeek(bandit, brain, contact) end)
        if okNeedAngle and needAngle == true then
            local okAngle, anglePoint = pcall(function() return NPCTacticalAngleBridge.GetPeekPoint(bandit, brain, contact, role) end)
            if okAngle and anglePoint and anglePoint.x and anglePoint.y then
                anglePoint.fireteam = true
                anglePoint.role = role
                anglePoint.mode = anglePoint.mode or "angle_peek"
                return bft_storePoint(brain, anglePoint, role, now)
            end
        end
    end

    local key = bft_groupKey(brain)
    local ch = NPCTacticalFireteamBridge.Channels[key]
    local center = bft_teamCenter(ch, now) or {x = bandit:getX(), y = bandit:getY(), z = bandit:getZ(), count = 1}
    local bx, by, bz = bandit:getX(), bandit:getY(), bandit:getZ()
    local distThreat = bft_dist(bx, by, contact.x, contact.y)

    if NPCTacticalFireteamBridge.Config.advancedIndoorSweep ~= false
        and NPCIndoorSweepBridge and NPCIndoorSweepBridge.GetManeuverPoint then
        local okSweep, sweepPoint = pcall(function()
            return NPCIndoorSweepBridge.GetManeuverPoint(bandit, brain, contact, role)
        end)
        if okSweep and sweepPoint and sweepPoint.x and sweepPoint.y then
            sweepPoint.fireteam = true
            sweepPoint.mode = sweepPoint.mode or role
            sweepPoint.role = sweepPoint.role or role
            sweepPoint.reason = sweepPoint.reason or "advanced indoor sweep"
            sweepPoint.arriveDist = tonumber(sweepPoint.arriveDist) or 1.15
            return bft_storePoint(brain, bft_centerLimited(sweepPoint, center), role, now)
        end
    end

    if NPCTacticalFireteamBridge.Config.indoorDoorwayDiscipline ~= false and NPCIndoorTacticalBridge and NPCIndoorTacticalBridge.GetInteriorTacticalPoint then
        local okIndoor, indoorPoint = pcall(function()
            return NPCIndoorTacticalBridge.GetInteriorTacticalPoint(bandit, brain, contact, role)
        end)
        if okIndoor and indoorPoint and indoorPoint.x and indoorPoint.y then
            indoorPoint.fireteam = true
            indoorPoint.mode = indoorPoint.mode or role
            indoorPoint.role = indoorPoint.role or role
            if NPCTacticalFireteamBridge.Config.advancedAngleDiscipline ~= false
                and NPCTacticalAngleBridge and NPCTacticalAngleBridge.RefineCoverPoint then
                local okRefine, refined = pcall(function()
                    return NPCTacticalAngleBridge.RefineCoverPoint(bandit, brain, contact, indoorPoint, role)
                end)
                if okRefine and refined and refined.x and refined.y then indoorPoint = refined end
            end
            return bft_storePoint(brain, bft_centerLimited(indoorPoint, center), role, now)
        end
    end

    if (role == "overwatch" or role == "suppress")
        and distThreat >= (NPCTacticalFireteamBridge.Config.overwatchHoldMinDist or 4.5)
        and distThreat <= (NPCTacticalFireteamBridge.Config.overwatchHoldMaxDist or 16.0) then
        local hold = {
            x = bx,
            y = by,
            z = bz,
            role = role,
            mode = role,
            holdOnly = true,
            threat = contact,
            arriveDist = 1.2,
            reason = role == "overwatch" and "hold overwatch angle" or "hold suppressing angle"
        }
        return bft_storePoint(brain, hold, role, now)
    end

    local coverRole = role
    if role == "solo_cover" then coverRole = "cover" end
    if role == "cross_cover" then coverRole = "support" end
    local coverPoint = bft_coverPoint(bandit, brain, contact, coverRole)
    if coverPoint and (role == "cover" or role == "solo_cover" or role == "cross_cover" or role == "overwatch" or role == "suppress") then
        coverPoint.mode = role
        coverPoint.role = role
        coverPoint.reason = coverPoint.reason or ("fireteam " .. tostring(role))
        coverPoint.arriveDist = role == "overwatch" and 1.5 or 1.8
        if NPCTacticalFireteamBridge.Config.advancedAngleDiscipline ~= false
            and NPCTacticalAngleBridge and NPCTacticalAngleBridge.RefineCoverPoint then
            local okRefine, refined = pcall(function()
                return NPCTacticalAngleBridge.RefineCoverPoint(bandit, brain, contact, coverPoint, role)
            end)
            if okRefine and refined and refined.x and refined.y then coverPoint = refined end
        end
        return bft_storePoint(brain, bft_centerLimited(coverPoint, center), role, now)
    end

    local awayX = bx - contact.x
    local awayY = by - contact.y
    local awayLen = math.sqrt(awayX * awayX + awayY * awayY)
    if awayLen < 0.05 then awayLen = 1 end
    local ux = awayX / awayLen
    local uy = awayY / awayLen
    local px = -uy
    local py = ux
    local side = 0
    if role == "flank_left" then side = 1 elseif role == "flank_right" then side = -1 elseif role == "cross_cover" then side = (bft_rand(2) == 0) and 1 or -1 end

    local tx, ty
    if role == "flank_left" or role == "flank_right" then
        local flank = tonumber(NPCTacticalFireteamBridge.Config.flankOffset) or 6.2
        tx = bx + ux * 3.5 + px * flank * side
        ty = by + uy * 3.5 + py * flank * side
    elseif role == "bound" then
        local bound = tonumber(NPCTacticalFireteamBridge.Config.boundOffset) or 4.5
        tx = bx - ux * bound + px * ((bft_rand(2) == 0) and 1.4 or -1.4)
        ty = by - uy * bound + py * ((bft_rand(2) == 0) and 1.4 or -1.4)
    else
        local preferred = tonumber(NPCTacticalFireteamBridge.Config.preferredCoverDist) or 7.5
        tx = contact.x + ux * preferred + px * side * 2.5
        ty = contact.y + uy * preferred + py * side * 2.5
    end

    local fx, fy, fz = bft_findUsableAround(tx, ty, bz, 7, bandit)
    if not fx then return nil end
    local point = {
        x = fx,
        y = fy,
        z = fz or bz,
        role = role,
        mode = role,
        threat = contact,
        arriveDist = (role == "flank_left" or role == "flank_right" or role == "bound") and 2.0 or 1.8,
        reason = "fireteam " .. tostring(role)
    }
    return bft_storePoint(brain, bft_centerLimited(point, center), role, now)
end

local function bft_searchSeed(contact, id, step)
    local base = tonumber((tostring(id or "0"):gsub("%D", ""))) or 0
    return (base + (tonumber(step) or 0) * 53) % 360
end

function NPCTacticalFireteamBridge.GetSearchPoint(bandit, brain)
    if NPCTacticalFireteamBridge.Config.enabled == false then return nil end
    if not (bandit and brain) then return nil end
    local ch = NPCTacticalFireteamBridge.Channels[bft_groupKey(brain)]
    local plan = ch and ch.plan or nil
    if not plan or plan.mode ~= "search" then return nil end
    local contact = plan.contact
    if not contact or not contact.x or not contact.y then return nil end

    local now = bft_nowMs()
    if brain.fireteamSearchPoint and now < (tonumber(brain.fireteamNextSearchAt) or 0) then
        return brain.fireteamSearchPoint
    end

    local id = bft_memberId(bandit, brain)
    local indoor = plan.indoorContact == true or bft_isIndoors(contact.x, contact.y, contact.z)
    local radius = indoor and (NPCTacticalFireteamBridge.Config.indoorSearchRadius or 7) or (NPCTacticalFireteamBridge.Config.outdoorSearchRadius or 12)
    local step = math.floor((now - (tonumber(plan.searchStartedAt) or now)) / (tonumber(NPCTacticalFireteamBridge.Config.searchStepMs) or 3600))
    local angle = bft_searchSeed(contact, id, step) * 0.0174532925
    local ring = indoor and (2 + (step % 3) * 1.6) or (3 + (step % 4) * 2.2)

    local tx = contact.x + math.cos(angle) * math.min(radius, ring)
    local ty = contact.y + math.sin(angle) * math.min(radius, ring)
    if indoor and NPCTacticalFireteamBridge.Config.advancedIndoorSweep ~= false
        and NPCIndoorSweepBridge and NPCIndoorSweepBridge.GetSearchPoint then
        local okSweep, sweepPoint = pcall(function()
            return NPCIndoorSweepBridge.GetSearchPoint(bandit, brain, contact)
        end)
        if okSweep and sweepPoint and sweepPoint.x and sweepPoint.y then
            sweepPoint.fireteam = true
            brain.fireteamSearchPoint = sweepPoint
            brain.fireteamNextSearchAt = now + (tonumber(NPCTacticalFireteamBridge.Config.searchStepMs) or 3600) + bft_rand(700)
            return sweepPoint
        end
    end

    if indoor and NPCIndoorTacticalBridge and NPCIndoorTacticalBridge.GetRoomSearchPoint then
        local okIndoor, indoorPoint = pcall(function()
            return NPCIndoorTacticalBridge.GetRoomSearchPoint(bandit, brain, contact, step)
        end)
        if okIndoor and indoorPoint and indoorPoint.x and indoorPoint.y then
            brain.fireteamSearchPoint = indoorPoint
            brain.fireteamNextSearchAt = now + (tonumber(NPCTacticalFireteamBridge.Config.searchStepMs) or 3600) + bft_rand(700)
            return indoorPoint
        end
    end

    local fx, fy, fz = bft_findUsableAround(tx, ty, contact.z or bandit:getZ(), indoor and 5 or 7, bandit)
    if not fx then return nil end

    local anims = indoor and {"AimRifleLow", "AimPistolLow", "ShiftWeight"} or {"AimRifleLow", "Forage", "ShiftWeight"}
    local point = {
        x = fx,
        y = fy,
        z = fz or bandit:getZ(),
        role = "search",
        mode = "search",
        inspectAnim = anims[bft_rand(#anims) + 1],
        inspectTime = indoor and (50 + bft_rand(45)) or (70 + bft_rand(65)),
        reason = indoor and "fireteam room clearing sweep" or "fireteam area sweep"
    }
    brain.fireteamSearchPoint = point
    brain.fireteamNextSearchAt = now + (tonumber(NPCTacticalFireteamBridge.Config.searchStepMs) or 3600) + bft_rand(900)
    return point
end

function NPCTacticalFireteamBridge.Debug(brain)
    if not brain then return end
    if brain.fireteam and brain.fireteam.role then
        brain.debugFireteam = tostring(brain.fireteam.mode or "idle") .. ":" .. tostring(brain.fireteam.role)
    end
end
