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
NPCSquadDynamicsBridge.VERSION = "2026-05-03-idle-visual-actions"

NPCSquadDynamicsBridge.Config = NPCSquadDynamicsBridge.Config or {
    enabled = true,
    combatMemoryMs = 65000,
    searchDurationMs = 52000,
    searchStepMs = 6200,
    roleSwitchMs = 9500,
    flankEngageDistance = 8.0,
    pressureDistance = 14.0,
    searchRadius = 16.0,
    searchSpread = 7.0,
    ambientEnabled = true,
    ambientCooldownMs = 21000,
    ambientChance = 38,
    ambientFaceAlly = true,
    ambientMoveChance = 32,
    ambientMoveRadius = 5.0,
    dutyEnabled = true,
    dutyIntervalMs = 46000,
    dutyDurationMs = 34000,
    dutyRadius = 13.0,
    dutyObserveTime = 95,
    maxMembers = 16
}

NPCSquadDynamicsBridge.Channels = NPCSquadDynamicsBridge.Channels or {}

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
    if d <= NPCSquadDynamicsBridge.Config.flankEngageDistance and (role:find("flank") or role == "point" or role == "assault") then
        if plan.focusMemberId ~= memberId then
            plan.focusMemberId = memberId
            plan.focusAt = now
            plan.phase = ((tonumber(plan.phase or 0) or 0) + 1) % 2
            plan.phaseAt = now
            plan.reason = "enemy attention shifted to flanker"
        end
    elseif now - (plan.phaseAt or 0) > NPCSquadDynamicsBridge.Config.roleSwitchMs then
        plan.phase = ((tonumber(plan.phase or 0) or 0) + 1) % 2
        plan.phaseAt = now
        plan.reason = "timed fire team rotation"
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
    local role = bsd_baseRole(bandit, brain)
    local member = {
        id = id,
        x = bandit:getX(),
        y = bandit:getY(),
        z = bandit:getZ(),
        role = role,
        state = brain.state or (brain.fsm and brain.fsm.state),
        action = action,
        suppressing = action == "Shoot" or action == "Aim",
        updatedAt = now,
        hp = brain.fsm and brain.fsm.health or nil
    }
    ch.members[id] = member

    if threat and bsd_humanKind(threat.kind) then
        bsd_updateCombatPlan(ch, id, member, threat, now)
    end

    brain.squad = brain.squad or {}
    brain.squad.groupKey = groupKey
    brain.squad.memberId = id
    brain.squad.mode = ch.plan and ch.plan.mode or "idle"
    brain.squad.phase = ch.plan and ch.plan.phase or 0
    brain.squad.memberCount = bsd_memberCount(ch)
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
    local phase = tonumber(plan.phase or 0) or 0

    if mode == "combat" then
        if plan.focusMemberId and tostring(plan.focusMemberId) == id then
            return "cover", "enemy switched fire to this flanker"
        end

        if phase == 0 then
            if base == "flank_left" or base == "flank_right" or base == "point" then
                return base, "first wave flank"
            end
            if base == "support" or base == "overwatch" or base == "leader" or tostring(plan.suppressorId or "") == id then
                return "suppress", "covering fire for flankers"
            end
            return "cover", "hold cover while flankers move"
        else
            if base == "support" or base == "assault" or base == "leader" then
                local numeric = tonumber(bsd_id(bandit)) or bsd_rand(9999)
                return (numeric % 2 == 0) and "flank_left" or "flank_right", "second wave flank after enemy focus shift"
            end
            if base == "flank_left" or base == "flank_right" or base == "point" then
                return "cover", "flanking wave taking cover"
            end
            return "suppress", "rotated covering fire"
        end
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

function NPCSquadDynamicsBridge.GetManeuverPoint(bandit, brain, threat)
    if NPCSquadDynamicsBridge.Config.enabled == false or not bandit or not brain then return nil end
    local groupKey = bsd_groupKey(brain)
    local ch = NPCSquadDynamicsBridge.Channels[groupKey]
    if not ch then return nil end
    threat = threat or bsd_threatFromPlan(ch, bandit)
    if not threat or not threat.x or not threat.y then return nil end

    local dynRole, roleReason = NPCSquadDynamicsBridge.GetRoleOverride(bandit, brain, threat)
    if not dynRole or dynRole == "search" or dynRole == "duty" then return nil end

    local coverRole = dynRole
    if dynRole == "suppress" then coverRole = "support" end
    if dynRole == "cover" then coverRole = "support" end

    local coverProvider = NPCTacticalCoverBridge and NPCTacticalCoverBridge.Resolve and NPCTacticalCoverBridge.Resolve() or nil
    if coverProvider and coverProvider.GetPoint then
        local ok, point = pcall(function()
            return coverProvider.GetPoint(bandit, brain, threat, coverRole)
        end)
        if ok and point and point.x and point.y then
            point.reason = roleReason or point.reason or ("squad " .. tostring(dynRole))
            point.role = dynRole
            point.mode = dynRole
            brain.squadDynamicRole = dynRole
            brain.squadDynamicReason = point.reason
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

    if dynRole == "flank_left" then
        tx = threat.x + ux * 12 + px * 10
        ty = threat.y + uy * 12 + py * 10
    elseif dynRole == "flank_right" then
        tx = threat.x + ux * 12 - px * 10
        ty = threat.y + uy * 12 - py * 10
    elseif dynRole == "suppress" then
        tx = bx + ux * 4 + px * 3
        ty = by + uy * 4 + py * 3
    else
        tx = bx + ux * 6 + px * ((bsd_rand(2) == 0) and 3 or -3)
        ty = by + uy * 6 + py * ((bsd_rand(2) == 0) and 3 or -3)
    end

    local fx, fy, fz = bsd_findUsableAround(tx, ty, bz, 7)
    if not fx then return nil end
    return {x=fx, y=fy, z=fz or bz, reason=roleReason or ("squad " .. tostring(dynRole)), role=dynRole, mode=dynRole, threat=threat}
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
            local reason = "проверяет оружие"
            local inspect = (bsd_rand(3) == 0) and "ReloadRifle" or ((bsd_rand(2) == 0) and "AttachBackOut" or "AttachHolsterRightOut")
            local restore = (inspect == "AttachHolsterRightOut") and "AttachHolsterRight" or "AttachBack"
            return bsd_sequence({
                bsd_timeTask(inspect, 70 + bsd_rand(45), reason),
                bsd_timeTask("ShiftWeight", 60 + bsd_rand(50), reason),
                bsd_timeTask(restore, 55 + bsd_rand(35), reason)
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

function NPCSquadDynamicsBridge.Debug(brain)
    if not brain then return end
    if brain.squadDynamicRole then
        brain.debugSquad = tostring(brain.squadDynamicRole) .. ": " .. tostring(brain.squadDynamicReason or "")
    elseif brain.squad and brain.squad.mode then
        brain.debugSquad = tostring(brain.squad.mode)
    end
end
