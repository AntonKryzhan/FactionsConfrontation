-- NPCSquadDynamicsBridge.lua
-- Dynamic squad relationships on top of tactical-radio/tactical-cover modules.
--
-- Goal:
-- 1. Fire team shares enemy coordinates.
-- 2. Some NPCs suppress while others flank.
-- 3. If pressure shifts to the flanker, roles rotate: attackers take cover,
--    covered NPCs become the next flanking wave.
-- 4. Lost contacts trigger a short area sweep.
-- 5. After a sweep, squad returns to ambient idle/duty actions.
--
-- Safety contract:
-- - Does not replace legacy Shoot/Hit/Reload actions.
-- - Does not set direct zombie targets.
-- - Only returns tactical movement/idle hints to brain-director bridge.

local legacySquadDynamics = NPCSquadDynamicsBridge
require "NPCCore/NPCTacticalCoverBridge"

NPCSquadDynamicsBridge = NPCSquadDynamicsBridge or legacySquadDynamics or {}
NPCSquadDynamicsBridge.VERSION = "2026-06-01-stage359-leader-driven-squad-locomotion-1"

NPCSquadDynamicsBridge.Config = NPCSquadDynamicsBridge.Config or {
    enabled = true,
    combatMemoryMs = 65000,
    searchDurationMs = 52000,
    searchStepMs = 6200,
    roleSwitchMs = 22000,
    flankEngageDistance = 6.0,
    pressureDistance = 10.0,
    searchRadius = 14.0,
    searchSpread = 5.0,
    cohesionRadius = 5.8,
    regroupRadius = 7.8,
    maneuverHoldMs = 2400,
    patrolAnchorMs = 16500,
    patrolArriveDist = 1.9,
    patrolStepDistance = 10.0,
    flankOffset = 3.4,
    suppressOffset = 2.2,
    ambientEnabled = true,
    ambientCooldownMs = 15000,
    ambientChance = 38,
    ambientFaceAlly = true,
    ambientMoveChance = 32,
    ambientMoveRadius = 5.0,
    dutyEnabled = true,
    dutyIntervalMs = 34000,
    dutyDurationMs = 34000,
    dutyRadius = 9.0,
    dutyObserveTime = 95,
    maxMembers = 16,
    crowdMasterSlaveEnabled = true,
    masterTimeoutMs = 9000,
    slaveIdleThinkIntervalMs = 900,
    slaveCombatThinkIntervalMs = 180,
    goldenAngleSlots = true,
    crowdSlotBaseRadius = 1.25,
    crowdSlotRadiusStep = 0.58,
    separationRadius = 1.15,
    separationPush = 0.85,
    separationSearchRadius = 4,
    leaderDrivenLocomotionEnabled = true,
    leaderFollowerHoldDistance = 1.15,
    leaderFollowerMoveDistance = 1.75,
    leaderFollowerCatchUpDistance = 6.5,
    leaderFollowerHardCatchUpDistance = 13.0,
    leaderFollowerSlotTargetDelta = 0.70,
    leaderFollowerSlotCooldownMs = 850
}

NPCSquadDynamicsBridge.Channels = NPCSquadDynamicsBridge.Channels or {}

local bsd_pushPlanThreatToBrain

local function bsd_nowMs()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then return math.floor((getGameTime():getWorldAgeHours() or 0) * 3600000) end
    return 0
end

local function bsd_rand(n)
    n = tonumber(n) or 1
    if n <= 1 then return 0 end
    if ZombRand then return ZombRand(n) end
    return math.random(0, n - 1)
end

local function bsd_id(chr)
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

local function bsd_memberKey(bandit, brain)
    if brain then
        if brain.persistentId then return tostring(brain.persistentId) end
        if brain.uid then return tostring(brain.uid) end
        if brain.id then return tostring(brain.id) end
    end
    return tostring(bsd_id(bandit) or "unknown")
end

local function bsd_groupKey(brain)
    if NPCTacticalRadioBridge and NPCTacticalRadioBridge.GroupKey then
        local ok, key = pcall(function() return NPCTacticalRadioBridge.GroupKey(brain) end)
        if ok and key then return tostring(key) end
    end
    if not brain then return "nogroup" end
    return tostring(brain.worldGroupId or brain.groupId or brain.physicalGroupId or brain.clan or "nogroup")
end

local function bsd_dist2(x1, y1, x2, y2)
    local dx = (x1 or 0) - (x2 or 0)
    local dy = (y1 or 0) - (y2 or 0)
    return dx * dx + dy * dy
end

local function bsd_dist(x1, y1, x2, y2)
    return math.sqrt(bsd_dist2(x1, y1, x2, y2))
end

local function bsd_humanKind(kind)
    kind = tostring(kind or ""):lower()
    return kind == "bandit" or kind == "player" or kind == "survivor" or kind == "npc" or kind == "human"
end

local function bsd_currentAction(bandit)
    if not bandit or not bandit.getVariableString then return nil end
    local ok, action = pcall(function() return bandit:getVariableString("NPC_TASK_ACTION") end)
    if ok and action and action ~= "" then return tostring(action) end
    return nil
end

local function bsd_channel(key)
    key = key or "nogroup"
    local ch = NPCSquadDynamicsBridge.Channels[key]
    if not ch then
        ch = {members={}, plan={mode="idle", phase=0}, createdAt=bsd_nowMs(), rev=0}
        NPCSquadDynamicsBridge.Channels[key] = ch
    end
    ch.members = ch.members or {}
    ch.plan = ch.plan or {mode="idle", phase=0}
    return ch
end

local function bsd_squareUsable(x, y, z)
    local cell = getCell()
    if not cell then return false end
    local sq = cell:getGridSquare(math.floor(x), math.floor(y), math.floor(z or 0))
    if not sq then return false end

    local ok, solid = pcall(function() return sq:isSolid() end)
    if ok and solid then return false end
    ok, solid = pcall(function() return sq:isSolidTrans() end)
    if ok and solid then return false end
    ok, solid = pcall(function()
        if IsoFlagType and IsoFlagType.water then return sq:Is(IsoFlagType.water) end
        return false
    end)
    if ok and solid then return false end
    return true
end

local function bsd_findUsableAround(x, y, z, radius)
    radius = radius or 5
    local bx = math.floor(x or 0)
    local by = math.floor(y or 0)
    local bz = math.floor(z or 0)
    if bsd_squareUsable(bx, by, bz) then return bx, by, bz end
    for r=1, radius do
        for dx=-r, r do
            for dy=-r, r do
                if math.abs(dx) == r or math.abs(dy) == r then
                    local sx = bx + dx
                    local sy = by + dy
                    if bsd_squareUsable(sx, sy, bz) then return sx, sy, bz end
                end
            end
        end
    end
    return nil
end


local function bsd_randomPointAround(x, y, z, radius)
    radius = radius or 4
    local angle = bsd_rand(628) / 100
    local dist = 2 + bsd_rand(math.max(2, math.floor(radius)))
    return bsd_findUsableAround((x or 0) + math.cos(angle) * dist, (y or 0) + math.sin(angle) * dist, z or 0, 4)
end

local function bsd_pickAlly(ch, selfId)
    if not ch or not ch.members then return nil end
    local best = nil
    local bestAt = -1
    for id, m in pairs(ch.members) do
        if tostring(id) ~= tostring(selfId) and m and m.x and m.y then
            if (m.updatedAt or 0) > bestAt then
                best = m
                bestAt = m.updatedAt or 0
            end
        end
    end
    return best
end

local function bsd_faceTask(x, y, reason)
    if not x or not y then return nil end
    return {kind="face", x=x, y=y, time=18, reason=reason}
end

local function bsd_timeTask(anim, time, reason)
    return {kind="time", anim=anim or "ShiftWeight", time=time or 100, reason=reason}
end

local function bsd_moveTask(x, y, z, reason)
    if not x or not y then return nil end
    return {kind="move", x=x, y=y, z=z, walkType="Walk", state="Idle", reason=reason}
end

local function bsd_sequence(tasks, reason)
    local out = {}
    for _, t in ipairs(tasks or {}) do
        if t then out[#out + 1] = t end
    end
    if #out == 0 then return nil end
    return {kind="sequence", tasks=out, state="Idle", reason=reason or "squad ambient visual action"}
end

local function bsd_memberCount(ch)
    local n = 0
    if not ch or not ch.members then return 0 end
    for _, _ in pairs(ch.members) do n = n + 1 end
    return n
end

local function bsd_sortedMemberIds(ch)
    local ids = {}
    if ch and ch.members then
        for id, m in pairs(ch.members) do
            if m and m.x and m.y then ids[#ids + 1] = tostring(id) end
        end
    end
    table.sort(ids)
    return ids
end

local function bsd_memberIndex(ch, selfId)
    local ids = bsd_sortedMemberIds(ch)
    local key = tostring(selfId or "")
    for i, id in ipairs(ids) do
        if tostring(id) == key then return i, #ids, ids[1] end
    end
    return 1, #ids, ids[1]
end

local function bsd_activeMasterId(ch, now)
    if not ch or not ch.members then return nil end
    now = now or bsd_nowMs()
    local timeout = tonumber(NPCSquadDynamicsBridge.Config.masterTimeoutMs) or 12000
    local ids = bsd_sortedMemberIds(ch)
    for _, id in ipairs(ids) do
        local m = ch.members[id]
        if m and m.x and m.y and now - (tonumber(m.updatedAt) or 0) <= timeout then
            return tostring(id)
        end
    end
    return nil
end

local function bsd_orderName(brain)
    if not brain then return nil end
    local order = brain.order or brain.directorOrder
    if NPCOrderContract and NPCOrderContract.Get then
        local ok, got = pcall(function() return NPCOrderContract.Get(brain) end)
        if ok and got then order = got end
    end
    if type(order) == "table" then return tostring(order.name or order.orderName or order.action or order.type or "") end
    if order ~= nil then return tostring(order) end
    return nil
end

local function bsd_isHiredMercenaryBrain(brain)
    if not brain then return false end
    if brain.mercenaryHired == true or brain.hired == true or brain.isPlayerGuard == true then return true end
    if brain.mercenaryHiredBy ~= nil or brain.master ~= nil then return true end
    local rel = tostring(brain.relationshipToPlayer or brain.factionState or "")
    return rel == "hired_bodyguard" or rel == "companion" or rel == "hired_blue_bodyguard"
end

local function bsd_isSquadLeaderBrain(brain)
    if not brain then return false end
    return brain.mercenarySquadLeader == true or brain.squadLeader == true or brain.isSquadLeader == true
end

local function bsd_selectLeaderId(ch, now)
    if not ch or not ch.members then return nil end
    now = now or bsd_nowMs()
    local timeout = tonumber(NPCSquadDynamicsBridge.Config.masterTimeoutMs) or 12000
    local bestId = nil
    local bestScore = -1000000
    local ids = bsd_sortedMemberIds(ch)
    for _, id in ipairs(ids) do
        local m = ch.members[id]
        if m and m.x and m.y and now - (tonumber(m.updatedAt) or 0) <= timeout then
            local score = 0
            if m.isSquadLeader == true then score = score + 100000 end
            if m.isMercenary == true then score = score + 1000 end
            score = score - (tonumber(m.index) or 99)
            score = score + ((tonumber(m.updatedAt) or 0) % 997) / 99700
            if score > bestScore then
                bestScore = score
                bestId = tostring(id)
            end
        end
    end
    return bestId or bsd_activeMasterId(ch, now)
end

local function bsd_leaderMember(ch, selfId, now)
    if not ch or not ch.members then return nil, nil end
    now = now or bsd_nowMs()
    local leaderId = bsd_selectLeaderId(ch, now)
    if not leaderId or tostring(leaderId) == tostring(selfId or "") then return nil, leaderId end
    local leader = ch.members[leaderId]
    if not leader or not leader.x or not leader.y then return nil, leaderId end
    return leader, leaderId
end

local function bsd_followerOrdinal(ch, selfId, leaderId)
    local ids = bsd_sortedMemberIds(ch)
    local ord = 1
    local total = 0
    local leaderIndex = 1
    for i, id in ipairs(ids) do
        if tostring(id) == tostring(leaderId or "") then leaderIndex = i end
    end
    for _, id in ipairs(ids) do
        if tostring(id) ~= tostring(leaderId or "") then
            total = total + 1
            if tostring(id) == tostring(selfId or "") then ord = total end
        end
    end
    if total <= 0 then total = math.max(1, #ids - 1) end
    return ord, total, leaderIndex
end

local function bsd_leaderFormationOffset(ord, total, formation, distance)
    ord = math.max(1, tonumber(ord) or 1)
    total = math.max(1, tonumber(total) or 1)
    formation = tostring(formation or "close")
    local base = tonumber(distance) or 1.35
    if base < 0.9 then base = 0.9 elseif base > 2.2 then base = 2.2 end

    if formation == "ring" or formation == "bodyguard" then
        local angle = (ord - 1) * 2.399963229728653
        local radius = base + math.floor((ord - 1) / 6) * 0.55
        return math.cos(angle) * radius, math.sin(angle) * radius
    end

    if formation == "line" then
        local mid = (total + 1) / 2
        return -base * 0.75, (ord - mid) * 1.15
    end

    local row = math.floor((ord - 1) / 2) + 1
    local side = (ord % 2 == 1) and -1 or 1
    local lateral = side * (0.72 + row * 0.34)
    local back = base + row * 0.72

    if formation == "wide" then
        lateral = side * (1.10 + row * 0.68)
        back = base + row * 0.88
    elseif formation == "wedge" then
        lateral = side * (0.95 + row * 0.58)
        back = base + row * 1.05
    end

    return -back, lateral
end

local function bsd_goldenSlot(center, index, count, baseRadius, stepRadius)
    if not center or not center.x or not center.y then return nil end
    index = math.max(1, tonumber(index) or 1)
    if index == 1 then return center.x, center.y, center.z or 0 end
    local golden = 2.399963229728653
    local ring = math.floor((index - 2) / 6)
    local radius = (tonumber(baseRadius) or NPCSquadDynamicsBridge.Config.crowdSlotBaseRadius or 1.45) + ring * (tonumber(stepRadius) or NPCSquadDynamicsBridge.Config.crowdSlotRadiusStep or 0.72)
    local angle = (index - 2) * golden
    local spread = math.min(1.0, math.max(0.35, (tonumber(count) or 1) / 8.0))
    radius = radius + spread * 0.35
    return center.x + math.cos(angle) * radius, center.y + math.sin(angle) * radius, center.z or 0
end

local function bsd_pushFromReserved(ch, selfId, x, y, z, minRadius)
    if not ch or not ch.members or not x or not y then return x, y, z end
    minRadius = tonumber(minRadius) or tonumber(NPCSquadDynamicsBridge.Config.separationRadius) or 1.35
    local min2 = minRadius * minRadius
    local px, py = 0, 0
    local pressure = 0
    for id, m in pairs(ch.members) do
        if tostring(id) ~= tostring(selfId or "") and m and m.x and m.y then
            local d2 = bsd_dist2(x, y, m.x, m.y)
            if d2 > 0.001 and d2 < min2 then
                local inv = (min2 - d2) / min2
                px = px + ((x - m.x) * inv)
                py = py + ((y - m.y) * inv)
                pressure = pressure + inv
            elseif d2 <= 0.001 then
                local n = tonumber(selfId) or 1
                px = px + math.cos(n * 2.399963229728653)
                py = py + math.sin(n * 2.399963229728653)
                pressure = pressure + 1
            end
        end
    end
    if pressure <= 0 then return x, y, z end
    local len = math.sqrt(px * px + py * py)
    if len < 0.001 then return x, y, z end
    local push = tonumber(NPCSquadDynamicsBridge.Config.separationPush) or 1.15
    return x + (px / len) * push, y + (py / len) * push, z
end

local function bsd_findSeparatedUsable(ch, selfId, x, y, z, radius)
    local px, py, pz = bsd_pushFromReserved(ch, selfId, x, y, z)
    local fx, fy, fz = bsd_findUsableAround(px, py, pz or z or 0, radius or NPCSquadDynamicsBridge.Config.separationSearchRadius or 4)
    if fx and fy then return fx, fy, fz or pz or z end
    return bsd_findUsableAround(x, y, z or 0, radius or 4)
end

local function bsd_teamCenter(ch, now)
    if not ch or not ch.members then return nil end
    now = now or bsd_nowMs()
    local sx, sy, sz, n = 0, 0, 0, 0
    for _, m in pairs(ch.members) do
        if m and m.x and m.y and now - (tonumber(m.updatedAt) or 0) <= 9000 then
            sx = sx + tonumber(m.x)
            sy = sy + tonumber(m.y)
            sz = sz + tonumber(m.z or 0)
            n = n + 1
        end
    end
    if n <= 0 then return nil end
    return {x = sx / n, y = sy / n, z = sz / n, count = n}
end

local function bsd_roleByIndex(index, count, base)
    index = tonumber(index) or 1
    count = tonumber(count) or 1
    if index == 1 then return "leader" end
    if count <= 2 then return index == 2 and "support" or "leader" end
    if index == 2 then return "support" end
    if index == 3 then return "point" end
    if index == 4 then return "flank_left" end
    if index == 5 then return "flank_right" end
    if index % 3 == 0 then return "support" end
    return base or "assault"
end

local function bsd_trim(ch, now)
    if not ch then return end
    for id, m in pairs(ch.members or {}) do
        if not m or now - (m.updatedAt or 0) > 30000 then
            ch.members[id] = nil
        end
    end

    local plan = ch.plan or {}
    local lastContactAt = plan.lastContactAt or 0
    if plan.mode == "combat" and now - lastContactAt > NPCSquadDynamicsBridge.Config.combatMemoryMs then
        plan.mode = "search"
        plan.searchStartedAt = now
        plan.nextSearchAt = 0
        plan.phase = 0
        plan.phaseAt = now
    elseif plan.mode == "search" and now - (plan.searchStartedAt or lastContactAt) > NPCSquadDynamicsBridge.Config.searchDurationMs then
        plan.mode = "idle"
        plan.idleStartedAt = now
        plan.currentEnemyId = nil
        plan.contact = nil
        plan.suppressorId = nil
        plan.focusMemberId = nil
        plan.nextSearchAt = nil
    end
    ch.plan = plan
end

local function bsd_contactFromThreat(threat)
    if not threat or not threat.x or not threat.y then return nil end
    return {
        id = tostring(threat.id or "enemy"),
        x = threat.x,
        y = threat.y,
        z = threat.z or 0,
        kind = threat.kind or "bandit",
        radio = threat.radio == true,
        confidence = threat.confidence or 1.0
    }
end

local function bsd_updateCombatPlan(ch, memberId, member, threat, now)
    local contact = bsd_contactFromThreat(threat)
    if not contact or not bsd_humanKind(contact.kind) then return end

    local plan = ch.plan or {}
    plan.mode = "combat"
    plan.contact = contact
    plan.currentEnemyId = contact.id
    plan.enemyX = contact.x
    plan.enemyY = contact.y
    plan.enemyZ = contact.z
    plan.lastContactAt = now
    plan.searchStartedAt = nil

    if member and member.suppressing then
        plan.suppressorId = memberId
        plan.suppressorAt = now
    elseif not plan.suppressorId or now - (plan.suppressorAt or 0) > 6000 then
        plan.suppressorId = memberId
        plan.suppressorAt = now
    end

    local d = bsd_dist(member.x, member.y, contact.x, contact.y)
    local role = tostring(member.role or "")
    local count = bsd_memberCount(ch)
    if count >= 4 and d <= NPCSquadDynamicsBridge.Config.flankEngageDistance and (role:find("flank") or role == "point" or role == "assault") then
        if plan.focusMemberId ~= memberId and now - (plan.focusAt or 0) > 4500 then
            plan.focusMemberId = memberId
            plan.focusAt = now
            plan.reason = "enemy attention shifted to flanker"
        end
    elseif count >= 5 and now - (plan.phaseAt or 0) > NPCSquadDynamicsBridge.Config.roleSwitchMs then
        plan.phase = ((tonumber(plan.phase or 0) or 0) + 1) % 2
        plan.phaseAt = now
        plan.reason = "bounded fire team rotation"
    end

    ch.plan = plan
    ch.rev = (ch.rev or 0) + 1
end

local function bsd_baseRole(bandit, brain)
    if NPCTacticalRadioBridge and NPCTacticalRadioBridge.Role then
        local ok, role = pcall(function() return NPCTacticalRadioBridge.Role(bandit, brain) end)
        if ok and role then return tostring(role) end
    end
    return tostring((brain and brain.tacticalRole) or "assault")
end

function NPCSquadDynamicsBridge.Tick(bandit, brain, uTick, threat)
    if NPCSquadDynamicsBridge.Config.enabled == false then return end
    if not bandit or not brain then return end

    local now = bsd_nowMs()
    local groupKey = bsd_groupKey(brain)
    local ch = bsd_channel(groupKey)
    bsd_trim(ch, now)

    local id = bsd_memberKey(bandit, brain)
    local action = bsd_currentAction(bandit)
    local baseRole = bsd_baseRole(bandit, brain)
    local orderName = bsd_orderName(brain)
    local isMercenary = bsd_isHiredMercenaryBrain(brain)
    local isSquadLeader = bsd_isSquadLeaderBrain(brain)
    ch.members[id] = ch.members[id] or {id = id, x = bandit:getX(), y = bandit:getY(), z = bandit:getZ(), updatedAt = now}
    local index, count = bsd_memberIndex(ch, id)
    local role = bsd_roleByIndex(index, count, baseRole)
    local member = {
        id = id,
        x = bandit:getX(),
        y = bandit:getY(),
        z = bandit:getZ(),
        role = role,
        baseRole = baseRole,
        index = index,
        state = brain.state or (brain.fsm and brain.fsm.state),
        action = action,
        orderName = orderName,
        isMercenary = isMercenary,
        isSquadLeader = isSquadLeader,
        owner = brain.master or brain.mercenaryHiredBy,
        suppressing = action == "Shoot" or action == "Aim",
        updatedAt = now,
        hp = brain.fsm and brain.fsm.health or nil
    }
    ch.members[id] = member

    if threat and bsd_humanKind(threat.kind) then
        bsd_updateCombatPlan(ch, id, member, threat, now)
    end
    bsd_pushPlanThreatToBrain(ch, bandit, brain, now)

    brain.squad = brain.squad or {}
    brain.squad.groupKey = groupKey
    brain.squad.memberId = id
    brain.squad.mode = ch.plan and ch.plan.mode or "idle"
    brain.squad.phase = ch.plan and ch.plan.phase or 0
    brain.squad.memberCount = bsd_memberCount(ch)
    brain.squad.memberIndex = index
    brain.squad.role = role
    local masterId = NPCSquadDynamicsBridge.Config.crowdMasterSlaveEnabled ~= false and bsd_selectLeaderId(ch, now) or nil
    brain.squad.masterId = masterId
    brain.squad.isMaster = masterId ~= nil and tostring(masterId) == tostring(id)
    brain.squad.isSlave = masterId ~= nil and tostring(masterId) ~= tostring(id) and brain.squad.memberCount > 1
    local center = bsd_teamCenter(ch, now)
    if center then
        brain.squad.centerX = center.x
        brain.squad.centerY = center.y
        brain.squad.centerZ = center.z
        brain.squad.centerDist = bsd_dist(bandit:getX(), bandit:getY(), center.x, center.y)
        if NPCSquadDynamicsBridge.Config.goldenAngleSlots ~= false then
            local sx, sy, sz = bsd_goldenSlot(center, index, brain.squad.memberCount, NPCSquadDynamicsBridge.Config.crowdSlotBaseRadius, NPCSquadDynamicsBridge.Config.crowdSlotRadiusStep)
            if sx and sy then
                brain.squad.slotX = sx
                brain.squad.slotY = sy
                brain.squad.slotZ = sz or center.z
                brain.squad.slotDist = bsd_dist(bandit:getX(), bandit:getY(), sx, sy)
            end
        end
    end
end

function NPCSquadDynamicsBridge.GetRoleOverride(bandit, brain, threat)
    if NPCSquadDynamicsBridge.Config.enabled == false or not bandit or not brain then return nil end
    local groupKey = bsd_groupKey(brain)
    local ch = NPCSquadDynamicsBridge.Channels[groupKey]
    if not ch or not ch.plan then return nil end
    local plan = ch.plan
    local mode = plan.mode or "idle"
    local id = bsd_memberKey(bandit, brain)
    local base = bsd_baseRole(bandit, brain)
    local index, count = bsd_memberIndex(ch, id)
    base = bsd_roleByIndex(index, count, base)
    local phase = tonumber(plan.phase or 0) or 0
    local center = bsd_teamCenter(ch, bsd_nowMs())
    if center and count > 1 then
        local distCenter = bsd_dist(bandit:getX(), bandit:getY(), center.x, center.y)
        if distCenter > (NPCSquadDynamicsBridge.Config.regroupRadius or 11) then
            return "regroup", "return to squad spacing"
        end
    end

    if mode == "combat" then
        if plan.focusMemberId and tostring(plan.focusMemberId) == id then
            return "cover", "enemy switched fire to this flanker"
        end

        if count <= 2 then
            return index == 1 and "suppress" or "cover", "two-man team cover"
        end
        if base == "leader" or base == "support" or tostring(plan.suppressorId or "") == id then
            return "suppress", "covering fire"
        end
        if count >= 5 and (base == "flank_left" or base == "flank_right") then
            return base, phase == 0 and "bounded flank" or "hold flank cover"
        end
        if base == "point" then
            return "cover", "point man taking cover"
        end
        return "cover", "hold squad line"
    elseif mode == "search" then
        return "search", "lost contact area sweep"
    elseif mode == "idle" then
        local directive = plan.duty
        if directive and tostring(directive.memberId or "") == id and bsd_nowMs() < (directive.untilAt or 0) then
            return "duty", "squad ordered sentry round"
        end
    end

    return nil
end

function NPCSquadDynamicsBridge.ChooseState(bandit, brain, threat, states)
    if not states then return nil end
    local dynRole, reason = NPCSquadDynamicsBridge.GetRoleOverride(bandit, brain, threat)
    if not dynRole then return nil end

    if dynRole == "flank_left" or dynRole == "flank_right" then
        return states.FlankEnemy, reason or "dynamic flank"
    elseif dynRole == "suppress" then
        return states.SuppressEnemy or states.TacticalCover, reason or "dynamic suppress"
    elseif dynRole == "cover" then
        return states.TacticalCover, reason or "dynamic cover"
    elseif dynRole == "overwatch" then
        return states.HoldAngle or states.TacticalCover, reason or "dynamic overwatch"
    elseif dynRole == "search" then
        return states.SearchEnemy, reason or "squad area sweep"
    elseif dynRole == "regroup" then
        return states.Regroup, reason or "squad regroup"
    elseif dynRole == "duty" then
        return states.PatrolArea, reason or "squad sentry duty"
    end

    return nil
end

local function bsd_threatFromPlan(ch, bandit)
    local plan = ch and ch.plan or nil
    local c = plan and (plan.contact or (plan.enemyX and {id=plan.currentEnemyId, x=plan.enemyX, y=plan.enemyY, z=plan.enemyZ, kind="bandit"}))
    if not c then return nil end
    return {
        id = c.id,
        x = c.x,
        y = c.y,
        z = c.z or (bandit and bandit:getZ()) or 0,
        kind = c.kind or "bandit",
        radio = true,
        dist = bandit and bsd_dist(bandit:getX(), bandit:getY(), c.x, c.y) or 0
    }
end

function bsd_pushPlanThreatToBrain(ch, bandit, brain, now)
    if not (ch and brain and ch.plan and ch.plan.mode == "combat") then return nil end
    local threat = bsd_threatFromPlan(ch, bandit)
    if not threat or not threat.x or not threat.y then return nil end
    threat.confidence = threat.confidence or 0.72
    threat.squadBroadcast = true
    threat.updatedAt = now or bsd_nowMs()
    brain.squadPlanThreat = threat
    if not brain.currentThreat then brain.currentThreat = threat end
    if not brain.radioThreat then brain.radioThreat = threat end
    if not brain.targetId and threat.id then brain.targetId = threat.id end
    if threat.x and threat.y then
        brain.lastKnownEnemyPosition = {x = threat.x, y = threat.y, z = threat.z or 0, t = now or bsd_nowMs(), squad = true}
    end
    return threat
end

local function bsd_pointTooFarFromCenter(point, center, maxDist)
    if not point or not center then return false end
    maxDist = tonumber(maxDist) or (NPCSquadDynamicsBridge.Config.cohesionRadius or 8)
    return bsd_dist(point.x, point.y, center.x, center.y) > maxDist
end

function NPCSquadDynamicsBridge.GetRegroupPoint(bandit, brain)
    if NPCSquadDynamicsBridge.Config.enabled == false or not bandit or not brain then return nil end
    local groupKey = bsd_groupKey(brain)
    local ch = NPCSquadDynamicsBridge.Channels[groupKey]
    if not ch then return nil end
    local now = bsd_nowMs()
    local center = bsd_teamCenter(ch, now)
    if not center then return nil end
    local id = bsd_memberKey(bandit, brain)
    local index, count = bsd_memberIndex(ch, id)
    local tx, ty, tz
    if NPCSquadDynamicsBridge.Config.goldenAngleSlots ~= false then
        tx, ty, tz = bsd_goldenSlot(center, index, count, NPCSquadDynamicsBridge.Config.crowdSlotBaseRadius, NPCSquadDynamicsBridge.Config.crowdSlotRadiusStep)
    end
    if not tx or not ty then
        local angle = ((index * 57) % 360) * 0.0174532925
        local radius = 1.4 + math.floor((index - 1) / 2) * 1.15
        tx = center.x + math.cos(angle) * radius
        ty = center.y + math.sin(angle) * radius
        tz = center.z or bandit:getZ()
    end
    local fx, fy, fz = bsd_findSeparatedUsable(ch, id, tx, ty, tz or center.z or bandit:getZ(), 5)
    if not fx then return nil end
    return {x = fx, y = fy, z = fz or bandit:getZ(), mode = "regroup", role = "regroup", reason = "regroup with squad", arriveDist = 1.8}
end

function NPCSquadDynamicsBridge.GetPatrolPoint(bandit, brain, radius)
    if NPCSquadDynamicsBridge.Config.enabled == false or not bandit or not brain then return nil end
    local groupKey = bsd_groupKey(brain)
    local ch = bsd_channel(groupKey)
    local now = bsd_nowMs()
    bsd_trim(ch, now)
    local id = bsd_memberKey(bandit, brain)
    local index, count = bsd_memberIndex(ch, id)
    local center = bsd_teamCenter(ch, now) or {x = bandit:getX(), y = bandit:getY(), z = bandit:getZ(), count = 1}
    if count > 1 and bsd_dist(bandit:getX(), bandit:getY(), center.x, center.y) > (NPCSquadDynamicsBridge.Config.regroupRadius or 11) then
        return NPCSquadDynamicsBridge.GetRegroupPoint(bandit, brain)
    end

    local plan = ch.plan or {}
    local patrol = plan.patrol
    local expire = tonumber(NPCSquadDynamicsBridge.Config.patrolAnchorMs) or 16500
    local stepDist = tonumber(NPCSquadDynamicsBridge.Config.patrolStepDistance) or 15
    local reached = patrol and patrol.x and bsd_dist(center.x, center.y, patrol.x, patrol.y) < 4.0
    if not patrol or not patrol.x or reached or now - (tonumber(patrol.createdAt) or 0) > expire then
        local point = nil
        if brain.roadPatrol and NPCRoadNavBridge and NPCRoadNavBridge.FindPatrolPoint then
            local ok, ret = pcall(function() return NPCRoadNavBridge.FindPatrolPoint(bandit, brain, (tonumber(radius) or 18) + 16) end)
            if ok then point = ret end
        end
        if not point then
            local angle = ((tonumber(plan.patrolPhase or 0) or 0) * 89 + bsd_rand(90)) * 0.0174532925
            local dist = math.max(6, math.min(stepDist, tonumber(radius) or stepDist))
            point = {x = center.x + math.cos(angle) * dist, y = center.y + math.sin(angle) * dist, z = center.z or bandit:getZ()}
        end
        local fx, fy, fz = bsd_findUsableAround(point.x, point.y, point.z or bandit:getZ(), 7)
        if fx and fy then
            patrol = {x = fx, y = fy, z = fz or bandit:getZ(), createdAt = now, phase = (tonumber(plan.patrolPhase or 0) or 0) + 1}
            plan.patrol = patrol
            plan.patrolPhase = patrol.phase
            ch.plan = plan
        end
    end
    patrol = plan.patrol
    if not patrol or not patrol.x then return nil end

    local dx = patrol.x - center.x
    local dy = patrol.y - center.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.05 then len = 1 end
    local ux, uy = dx / len, dy / len
    local px, py = -uy, ux
    local tx, ty, tz
    if NPCSquadDynamicsBridge.Config.goldenAngleSlots ~= false and count > 2 then
        tx, ty, tz = bsd_goldenSlot({x=patrol.x, y=patrol.y, z=patrol.z or bandit:getZ()}, index, count, 1.25, 0.70)
    else
        local row = math.floor(math.max(0, index - 2) / 2) + 1
        local side = (index % 2 == 0) and 1 or -1
        local spacing = 1.45
        local back = index == 1 and 0 or row * 1.25
        local lateral = index == 1 and 0 or side * spacing * row
        tx = patrol.x - ux * back + px * lateral
        ty = patrol.y - uy * back + py * lateral
        tz = patrol.z or bandit:getZ()
    end
    local fx, fy, fz = bsd_findSeparatedUsable(ch, id, tx, ty, tz or patrol.z or bandit:getZ(), 5)
    if not fx then fx, fy, fz = patrol.x, patrol.y, patrol.z or bandit:getZ() end
    return {x = fx, y = fy, z = fz or bandit:getZ(), mode = "patrol", role = brain.squad and brain.squad.role or "patrol", reason = "cohesive squad patrol", arriveDist = NPCSquadDynamicsBridge.Config.patrolArriveDist or 1.9}
end

function NPCSquadDynamicsBridge.GetManeuverPoint(bandit, brain, threat)
    if NPCSquadDynamicsBridge.Config.enabled == false or not bandit or not brain then return nil end
    local groupKey = bsd_groupKey(brain)
    local ch = NPCSquadDynamicsBridge.Channels[groupKey]
    if not ch then return nil end
    threat = threat or bsd_threatFromPlan(ch, bandit)
    if not threat or not threat.x or not threat.y then return nil end

    local dynRole, roleReason = NPCSquadDynamicsBridge.GetRoleOverride(bandit, brain, threat)
    if not dynRole or dynRole == "search" or dynRole == "duty" then return nil end
    if dynRole == "regroup" then return NPCSquadDynamicsBridge.GetRegroupPoint(bandit, brain) end

    local now = bsd_nowMs()
    if brain.squadManeuverPoint and now < (tonumber(brain.squadManeuverUntil) or 0) then
        local p = brain.squadManeuverPoint
        if p and p.x and p.y then return p end
    end

    local center = nil
    local groupKey = bsd_groupKey(brain)
    local ch = NPCSquadDynamicsBridge.Channels[groupKey]
    if ch then center = bsd_teamCenter(ch, now) end

    if dynRole == "suppress" then
        local distThreat = bsd_dist(bandit:getX(), bandit:getY(), threat.x, threat.y)
        if distThreat >= 4.0 and distThreat <= 9.5 then
            local p = {x = bandit:getX(), y = bandit:getY(), z = bandit:getZ(), reason = roleReason or "hold covering angle", role = dynRole, mode = dynRole, holdOnly = true, threat = threat}
            brain.squadManeuverPoint = p
            brain.squadManeuverUntil = now + (NPCSquadDynamicsBridge.Config.maneuverHoldMs or 3400)
            brain.squadDynamicRole = dynRole
            brain.squadDynamicReason = p.reason
            return p
        end
    end

    local coverRole = dynRole
    if dynRole == "suppress" then coverRole = "support" end
    if dynRole == "cover" then coverRole = "support" end

    local coverProvider = NPCTacticalCoverBridge and NPCTacticalCoverBridge.Resolve and NPCTacticalCoverBridge.Resolve() or nil
    if coverProvider and coverProvider.GetPoint then
        local ok, point = pcall(function()
            return coverProvider.GetPoint(bandit, brain, threat, coverRole)
        end)
        if ok and point and point.x and point.y and not bsd_pointTooFarFromCenter(point, center, (NPCSquadDynamicsBridge.Config.cohesionRadius or 8) + 3) then
            point.reason = roleReason or point.reason or ("squad " .. tostring(dynRole))
            point.role = dynRole
            point.mode = dynRole
            brain.squadDynamicRole = dynRole
            brain.squadDynamicReason = point.reason
            brain.squadManeuverPoint = point
            brain.squadManeuverUntil = now + (NPCSquadDynamicsBridge.Config.maneuverHoldMs or 3400)
            return point
        end
    end

    local bx, by, bz = bandit:getX(), bandit:getY(), bandit:getZ()
    local dx = bx - threat.x
    local dy = by - threat.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.05 then len = 1 end
    local ux, uy = dx / len, dy / len
    local px, py = -uy, ux
    local tx, ty
    local flank = tonumber(NPCSquadDynamicsBridge.Config.flankOffset) or 5.5
    local sup = tonumber(NPCSquadDynamicsBridge.Config.suppressOffset) or 3.0

    if dynRole == "flank_left" then
        tx = bx + ux * 4.5 + px * flank
        ty = by + uy * 4.5 + py * flank
    elseif dynRole == "flank_right" then
        tx = bx + ux * 4.5 - px * flank
        ty = by + uy * 4.5 - py * flank
    elseif dynRole == "suppress" then
        tx = bx + ux * sup
        ty = by + uy * sup
    else
        tx = bx + ux * 4.0 + px * ((bsd_rand(2) == 0) and 2.0 or -2.0)
        ty = by + uy * 4.0 + py * ((bsd_rand(2) == 0) and 2.0 or -2.0)
    end

    if center and bsd_dist(tx, ty, center.x, center.y) > (NPCSquadDynamicsBridge.Config.cohesionRadius or 8) + 3 then
        local rg = NPCSquadDynamicsBridge.GetRegroupPoint(bandit, brain)
        if rg then return rg end
    end

    local fx, fy, fz = bsd_findSeparatedUsable(ch, id, tx, ty, bz, 6)
    if not fx then return nil end
    local point = {x=fx, y=fy, z=fz or bz, reason=roleReason or ("squad " .. tostring(dynRole)), role=dynRole, mode=dynRole, threat=threat, arriveDist = 1.8}
    brain.squadManeuverPoint = point
    brain.squadManeuverUntil = now + (NPCSquadDynamicsBridge.Config.maneuverHoldMs or 3400)
    return point
end

function NPCSquadDynamicsBridge.GetSearchPoint(bandit, brain)
    if NPCSquadDynamicsBridge.Config.enabled == false or not bandit or not brain then return nil end
    local groupKey = bsd_groupKey(brain)
    local ch = NPCSquadDynamicsBridge.Channels[groupKey]
    if not ch or not ch.plan or ch.plan.mode ~= "search" then return nil end
    local plan = ch.plan
    local c = plan.contact or (plan.enemyX and {x=plan.enemyX, y=plan.enemyY, z=plan.enemyZ})
    if not c or not c.x or not c.y then return nil end

    local now = bsd_nowMs()
    local id = bsd_memberKey(bandit, brain)
    local memberIndex = 0
    for mid, _ in pairs(ch.members or {}) do
        if tostring(mid) < tostring(id) then memberIndex = memberIndex + 1 end
    end

    if now < (brain.squadNextSearchAt or 0) and brain.squadSearchPoint then
        return brain.squadSearchPoint
    end

    local step = math.floor((now - (plan.searchStartedAt or now)) / (NPCSquadDynamicsBridge.Config.searchStepMs or 6200))
    local angle = ((memberIndex * 97 + step * 53) % 360) * 0.0174532925
    local radius = 3 + ((step + memberIndex) % 4) * ((NPCSquadDynamicsBridge.Config.searchSpread or 7) / 3)
    local tx = c.x + math.cos(angle) * radius
    local ty = c.y + math.sin(angle) * radius
    local fx, fy, fz = bsd_findUsableAround(tx, ty, c.z or bandit:getZ(), 6)
    if not fx then return nil end

    local inspectAnims = {"AimRifleLow", "AimPistolLow", "LootLow", "Forage", "ShiftWeight"}
    local point = {
        x=fx,
        y=fy,
        z=fz or bandit:getZ(),
        reason="squad sweeping last contact",
        role="search",
        inspectAnim=inspectAnims[bsd_rand(#inspectAnims) + 1],
        inspectTime=80 + bsd_rand(70)
    }
    brain.squadNextSearchAt = now + (NPCSquadDynamicsBridge.Config.searchStepMs or 6200)
    brain.squadSearchPoint = point
    brain.squadDynamicReason = point.reason
    return point
end

local function bsd_ensureDuty(ch, now)
    if not NPCSquadDynamicsBridge.Config.dutyEnabled then return nil end
    local plan = ch.plan or {}
    if plan.mode ~= "idle" then return nil end
    if plan.duty and now < (plan.duty.untilAt or 0) then return plan.duty end
    if now < (plan.nextDutyAt or 0) then return nil end

    local ids = {}
    for id, _ in pairs(ch.members or {}) do ids[#ids + 1] = id end
    if #ids == 0 then return nil end
    table.sort(ids)

    plan.dutyCursor = ((tonumber(plan.dutyCursor or 0) or 0) % #ids) + 1
    local memberId = ids[plan.dutyCursor]
    local m = ch.members[memberId]
    if not m then return nil end

    local angle = ((plan.dutyCursor * 83 + (tonumber(plan.phase or 0) or 0) * 41) % 360) * 0.0174532925
    local r = NPCSquadDynamicsBridge.Config.dutyRadius or 13
    local tx = m.x + math.cos(angle) * r
    local ty = m.y + math.sin(angle) * r
    local fx, fy, fz = bsd_findUsableAround(tx, ty, m.z or 0, 8)

    if fx and fy then
        plan.duty = {
            memberId = memberId,
            x = fx,
            y = fy,
            z = fz or m.z or 0,
            startedAt = now,
            untilAt = now + (NPCSquadDynamicsBridge.Config.dutyDurationMs or 34000),
            reason = "squad ordered sentry round"
        }
        plan.nextDutyAt = now + (NPCSquadDynamicsBridge.Config.dutyIntervalMs or 46000)
        ch.plan = plan
        return plan.duty
    end

    plan.nextDutyAt = now + 15000
    ch.plan = plan
    return nil
end

function NPCSquadDynamicsBridge.GetAmbientTask(bandit, brain, uTick)
    if NPCSquadDynamicsBridge.Config.enabled == false or NPCSquadDynamicsBridge.Config.ambientEnabled == false then return nil end
    if not bandit or not brain then return nil end

    local now = bsd_nowMs()
    local groupKey = bsd_groupKey(brain)
    local ch = bsd_channel(groupKey)
    bsd_trim(ch, now)
    if ch.plan and ch.plan.mode ~= "idle" then return nil end

    local id = bsd_memberKey(bandit, brain)
    local duty = bsd_ensureDuty(ch, now)
    if duty and tostring(duty.memberId or "") == id then
        if bsd_dist(bandit:getX(), bandit:getY(), duty.x, duty.y) > 2.2 then
            brain.squadDynamicReason = duty.reason
            return bsd_sequence({
                bsd_moveTask(duty.x, duty.y, duty.z or bandit:getZ(), duty.reason),
                bsd_faceTask((duty.x or bandit:getX()) + 6 - bsd_rand(13), (duty.y or bandit:getY()) + 6 - bsd_rand(13), duty.reason),
                bsd_timeTask((bsd_rand(2) == 0) and "AimRifleLow" or "ShiftWeight", NPCSquadDynamicsBridge.Config.dutyObserveTime or 95, duty.reason)
            }, duty.reason)
        end
        ch.plan.duty = nil
        return bsd_sequence({
            bsd_faceTask(bandit:getX() + 6 - bsd_rand(13), bandit:getY() + 6 - bsd_rand(13), "осматривает сектор после обхода"),
            bsd_timeTask((bsd_rand(2) == 0) and "AimRifleLow" or "Smoke", 90 + bsd_rand(60), "осматривает сектор после обхода")
        }, "осматривает сектор после обхода")
    end

    if now < (brain.squadNextAmbientAt or 0) then return nil end
    brain.squadNextAmbientAt = now + (NPCSquadDynamicsBridge.Config.ambientCooldownMs or 21000) + bsd_rand(8000)
    if bsd_rand(100) >= (NPCSquadDynamicsBridge.Config.ambientChance or 35) then return nil end

    local ally = bsd_pickAlly(ch, id)
    local faceAlly = ally and NPCSquadDynamicsBridge.Config.ambientFaceAlly ~= false
    local bx, by, bz = bandit:getX(), bandit:getY(), bandit:getZ()
    local rx, ry, rz = bsd_randomPointAround(bx, by, bz, NPCSquadDynamicsBridge.Config.ambientMoveRadius or 5)
    local last = ch.plan and (ch.plan.contact or (ch.plan.enemyX and {x=ch.plan.enemyX, y=ch.plan.enemyY, z=ch.plan.enemyZ})) or nil

    local function faceDefault(reason)
        if faceAlly then return bsd_faceTask(ally.x, ally.y, reason) end
        if last and last.x and last.y then return bsd_faceTask(last.x, last.y, reason) end
        return bsd_faceTask(bx + 5 - bsd_rand(11), by + 5 - bsd_rand(11), reason)
    end

    local variants = {
        function()
            local reason = "обсуждает последнюю цель"
            return bsd_sequence({
                faceDefault(reason),
                bsd_timeTask((bsd_rand(2) == 0) and "Shrug" or "PullAtCollar", 80 + bsd_rand(70), reason),
                bsd_timeTask((bsd_rand(2) == 0) and "ShiftWeight" or "WipeBrow", 80 + bsd_rand(50), reason)
            }, reason)
        end,
        function()
            local reason = "обсуждает приказ начальства"
            return bsd_sequence({
                faceDefault(reason),
                bsd_timeTask((bsd_rand(2) == 0) and "Shrug" or "ChewNails", 90 + bsd_rand(70), reason),
                bsd_timeTask("ShiftWeight", 75 + bsd_rand(55), reason)
            }, reason)
        end,
        function()
            local reason = "проверяет сектор"
            return bsd_sequence({
                faceDefault(reason),
                bsd_timeTask((bsd_rand(2) == 0) and "AimRifleLow" or "AimPistolLow", 70 + bsd_rand(45), reason),
                bsd_timeTask("ShiftWeight", 60 + bsd_rand(50), reason)
            }, reason)
        end,
        function()
            local reason = "ищет документы и пометки"
            local tasks = {}
            if rx and ry and bsd_rand(100) < (NPCSquadDynamicsBridge.Config.ambientMoveChance or 32) then
                tasks[#tasks + 1] = bsd_moveTask(rx, ry, rz or bz, reason)
            end
            tasks[#tasks + 1] = bsd_timeTask((bsd_rand(2) == 0) and "Loot" or "LootLow", 100 + bsd_rand(80), reason)
            tasks[#tasks + 1] = bsd_timeTask((bsd_rand(2) == 0) and "Forage" or "ShiftWeight", 80 + bsd_rand(70), reason)
            return bsd_sequence(tasks, reason)
        end,
        function()
            local reason = "настраивает рацию"
            return bsd_sequence({
                faceDefault(reason),
                bsd_timeTask((bsd_rand(2) == 0) and "Loot" or "LootLow", 105 + bsd_rand(80), reason),
                bsd_timeTask((bsd_rand(2) == 0) and "ShiftWeight" or "WipeHead", 75 + bsd_rand(65), reason)
            }, reason)
        end,
        function()
            local reason = "обсуждает обстановку"
            return bsd_sequence({
                faceDefault(reason),
                bsd_timeTask((bsd_rand(2) == 0) and "Smoke" or "WipeBrow", 95 + bsd_rand(90), reason),
                bsd_timeTask((bsd_rand(2) == 0) and "ShiftWeight" or "PullAtCollar", 80 + bsd_rand(70), reason)
            }, reason)
        end
    }

    local builder = variants[bsd_rand(#variants) + 1]
    local spec = builder and builder() or nil
    if spec then
        brain.squadAmbientAction = spec.reason
        brain.squadDynamicReason = spec.reason
    end
    return spec
end


function NPCSquadDynamicsBridge.GetLeaderFollowPoint(bandit, brain, master, order)
    if NPCSquadDynamicsBridge.Config.enabled == false or NPCSquadDynamicsBridge.Config.leaderDrivenLocomotionEnabled == false then return nil end
    if not (bandit and brain and master) then return nil end
    if not bsd_isHiredMercenaryBrain(brain) then return nil end
    local orderName = order and tostring(order.name or order.orderName or order.action or "") or bsd_orderName(brain)
    if orderName ~= "Follow" then return nil end

    local groupKey = bsd_groupKey(brain)
    local ch = NPCSquadDynamicsBridge.Channels[groupKey]
    if not ch or bsd_memberCount(ch) <= 1 then return nil end

    local now = bsd_nowMs()
    local selfId = bsd_memberKey(bandit, brain)
    local leader, leaderId = bsd_leaderMember(ch, selfId, now)
    if not leader then
        if leaderId and tostring(leaderId) == tostring(selfId) then
            brain.squad = brain.squad or {}
            brain.squad.leaderDrivenRole = "leader"
            return {isLeader = true}
        end
        return nil
    end

    local ord, total = bsd_followerOrdinal(ch, selfId, leaderId)
    local formation = order and order.formation or "close"
    local followDistance = order and tonumber(order.followDistance) or nil
    local ox, oy = bsd_leaderFormationOffset(ord, total, formation, followDistance or NPCSquadDynamicsBridge.Config.leaderFollowerMoveDistance)

    local lx, ly, lz = tonumber(leader.x), tonumber(leader.y), tonumber(leader.z or bandit:getZ())
    local mx, my = master:getX(), master:getY()
    local vx = mx - lx
    local vy = my - ly
    local vlen = math.sqrt(vx * vx + vy * vy)
    if vlen < 0.05 and master.getDirectionAngle then
        local ok, ang = pcall(function() return master:getDirectionAngle() end)
        if ok and ang then
            local a = math.rad(tonumber(ang) or 0)
            vx, vy = math.cos(a), math.sin(a)
            vlen = 1
        end
    end
    if vlen < 0.05 then vx, vy, vlen = 1, 0, 1 end
    local ux, uy = vx / vlen, vy / vlen
    local px, py = -uy, ux

    local tx = lx + ux * ox + px * oy
    local ty = ly + uy * ox + py * oy
    local tz = lz
    local fx, fy, fz = bsd_findSeparatedUsable(ch, selfId, tx, ty, tz, 4)
    if not fx then fx, fy, fz = tx, ty, tz end

    local leaderDist = bsd_dist(bandit:getX(), bandit:getY(), lx, ly)
    local slotDist = bsd_dist(bandit:getX(), bandit:getY(), fx, fy)
    local playerDist = bsd_dist(bandit:getX(), bandit:getY(), mx, my)
    local catchUp = leaderDist > (tonumber(NPCSquadDynamicsBridge.Config.leaderFollowerCatchUpDistance) or 6.5) or playerDist > 12
    local hardCatchUp = leaderDist > (tonumber(NPCSquadDynamicsBridge.Config.leaderFollowerHardCatchUpDistance) or 13.0) or playerDist > 22

    brain.squad = brain.squad or {}
    brain.squad.leaderDrivenRole = "follower"
    brain.squad.leaderDrivenLeaderId = leaderId
    brain.squad.leaderDrivenSlotX = fx
    brain.squad.leaderDrivenSlotY = fy
    brain.squad.leaderDrivenLeaderDist = leaderDist
    brain.squad.leaderDrivenSlotDist = slotDist

    return {
        x = fx,
        y = fy,
        z = fz or tz or bandit:getZ(),
        mode = "leader_follow",
        role = "follower",
        reason = "leader-driven mercenary locomotion",
        leaderId = leaderId,
        leaderX = lx,
        leaderY = ly,
        leaderZ = lz,
        leaderDist = leaderDist,
        slotDist = slotDist,
        playerDist = playerDist,
        arriveDist = hardCatchUp and 1.65 or (tonumber(NPCSquadDynamicsBridge.Config.leaderFollowerHoldDistance) or 1.15),
        walkType = (catchUp or hardCatchUp) and "Run" or "Walk",
        catchUp = catchUp,
        hardCatchUp = hardCatchUp
    }
end

function NPCSquadDynamicsBridge.Debug(brain)
    if not brain then return end
    local ms = ""
    if brain.squad and brain.squad.isMaster then ms = " master" elseif brain.squad and brain.squad.isSlave then ms = " slave" end
    if brain.squadDynamicRole then
        brain.debugSquad = tostring(brain.squadDynamicRole) .. ms .. ": " .. tostring(brain.squadDynamicReason or "")
    elseif brain.squad and brain.squad.mode then
        brain.debugSquad = tostring(brain.squad.mode) .. ms
    end
end
