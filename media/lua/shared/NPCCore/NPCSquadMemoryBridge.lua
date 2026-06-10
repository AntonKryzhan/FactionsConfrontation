-- NPCSquadMemoryBridge.lua
-- Stage 368: bounded squad memory and threat investigation layer.
--
-- This bridge is intentionally advisory. It does not shoot, damage, spawn,
-- network-sync, or replace task names. It only keeps short-lived group memory
-- for last contact / gunfire / under-fire events and provides low-cost search
-- points so NPCs investigate like a coordinated fireteam instead of standing
-- after contact is lost.

NPCSquadMemoryBridge = NPCSquadMemoryBridge or {}
NPCSquadMemoryBridge.VERSION = "2026-06-01-stage368-squad-memory-threat-investigation-1"

pcall(require, "NPCCore/NPCMovementStabilityBridge")
pcall(require, "NPCCore/NPCIndoorTacticalBridge")
pcall(require, "NPCCore/NPCLegacyGlobalsBridge")

NPCSquadMemoryBridge.Config = NPCSquadMemoryBridge.Config or {
    enabled = true,
    contactMemoryMs = 92000,
    soundMemoryMs = 36000,
    underFireMemoryMs = 52000,
    allyHitMemoryMs = 62000,
    staleContactMs = 12000,
    searchStepMs = 3600,
    searchHoldMs = 5200,
    maxSearchRadius = 15,
    indoorRadius = 7,
    outdoorRadius = 13,
    maxEvents = 12,
    maxMembers = 20,
    minConfidenceToInvestigate = 0.28
}

NPCSquadMemoryBridge.Channels = NPCSquadMemoryBridge.Channels or {}

local function bsm_nowMs()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then return math.floor((getGameTime():getWorldAgeHours() or 0) * 3600000) end
    return 0
end

local function bsm_rand(n)
    n = tonumber(n) or 1
    if n <= 1 then return 0 end
    if ZombRand then return ZombRand(n) end
    return math.random(0, n - 1)
end

local function bsm_dist2(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return dx * dx + dy * dy
end

local function bsm_dist(x1, y1, x2, y2)
    return math.sqrt(bsm_dist2(x1, y1, x2, y2))
end

local function bsm_id(chr)
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

local function bsm_memberId(bandit, brain)
    if brain then
        if brain.persistentId then return tostring(brain.persistentId) end
        if brain.uid then return tostring(brain.uid) end
        if brain.id then return tostring(brain.id) end
    end
    return tostring(bsm_id(bandit) or "unknown")
end

local function bsm_groupKey(brain)
    if NPCTacticalRadioBridge and NPCTacticalRadioBridge.GroupKey then
        local ok, key = pcall(function() return NPCTacticalRadioBridge.GroupKey(brain) end)
        if ok and key then return tostring(key) end
    end
    if not brain then return "nogroup" end
    return tostring(brain.worldGroupId or brain.groupId or brain.physicalGroupId or brain.squadId or brain.clan or "nogroup")
end

local function bsm_square(x, y, z)
    local cell = getCell and getCell() or nil
    if not cell then return nil end
    return cell:getGridSquare(math.floor(tonumber(x) or 0), math.floor(tonumber(y) or 0), math.floor(tonumber(z) or 0))
end

local function bsm_isIndoors(x, y, z)
    local sq = bsm_square(x, y, z)
    if not sq then return false end
    local ok, room = pcall(function() return sq:getRoom() end)
    return ok and room ~= nil
end

local function bsm_squareUsable(x, y, z, mover)
    local sq = bsm_square(x, y, z)
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

local function bsm_findUsableAround(x, y, z, radius, mover)
    radius = tonumber(radius) or 5
    local bx = math.floor(tonumber(x) or 0)
    local by = math.floor(tonumber(y) or 0)
    local bz = math.floor(tonumber(z) or 0)
    if bsm_squareUsable(bx, by, bz, mover) then return bx, by, bz end
    for r = 1, radius do
        for dx = -r, r do
            for dy = -r, r do
                if math.abs(dx) == r or math.abs(dy) == r then
                    local sx = bx + dx
                    local sy = by + dy
                    if bsm_squareUsable(sx, sy, bz, mover) then return sx, sy, bz end
                end
            end
        end
    end
    return nil
end

local function bsm_channel(key)
    key = key or "nogroup"
    local ch = NPCSquadMemoryBridge.Channels[key]
    if not ch then
        ch = {members = {}, events = {}, focus = nil, createdAt = bsm_nowMs(), rev = 0}
        NPCSquadMemoryBridge.Channels[key] = ch
    end
    ch.members = ch.members or {}
    ch.events = ch.events or {}
    return ch
end

local function bsm_trim(ch, now)
    if not ch then return end
    now = now or bsm_nowMs()
    for id, m in pairs(ch.members or {}) do
        if not m or now - (tonumber(m.updatedAt) or 0) > 30000 then
            ch.members[id] = nil
        end
    end
    local kept = {}
    local maxEvents = tonumber(NPCSquadMemoryBridge.Config.maxEvents) or 12
    for _, ev in ipairs(ch.events or {}) do
        local ttl = tonumber(ev.ttlMs) or 30000
        if ev.x and ev.y and now - (tonumber(ev.at) or 0) <= ttl then
            kept[#kept + 1] = ev
            if #kept >= maxEvents then break end
        end
    end
    ch.events = kept
    local f = ch.focus
    if f and now - (tonumber(f.at) or 0) > (tonumber(f.ttlMs) or NPCSquadMemoryBridge.Config.contactMemoryMs or 90000) then
        ch.focus = nil
    end
end

local function bsm_confidenceFor(kind, base)
    kind = tostring(kind or "contact")
    base = tonumber(base) or 0.5
    if kind == "direct" then return math.max(base, 0.92) end
    if kind == "hit" or kind == "ally_hit" then return math.max(base, 0.82) end
    if kind == "under_fire" then return math.max(base, 0.68) end
    if kind == "shot" then return math.max(base, 0.54) end
    if kind == "sound" or kind == "noise" then return math.max(base, 0.38) end
    return base
end

local function bsm_pushEvent(ch, ev)
    if not (ch and ev and ev.x and ev.y) then return nil end
    ev.at = ev.at or bsm_nowMs()
    ev.confidence = bsm_confidenceFor(ev.kind, ev.confidence)
    ev.ttlMs = ev.ttlMs or NPCSquadMemoryBridge.Config.contactMemoryMs
    table.insert(ch.events, 1, ev)
    local maxEvents = tonumber(NPCSquadMemoryBridge.Config.maxEvents) or 12
    while #ch.events > maxEvents do table.remove(ch.events) end

    local focus = ch.focus
    local shouldReplace = not focus
        or (tonumber(ev.confidence) or 0) >= (tonumber(focus.confidence) or 0) - 0.12
        or bsm_dist(ev.x, ev.y, focus.x, focus.y) > 7.0
        or ev.kind == "direct"
        or ev.kind == "hit"
        or ev.kind == "ally_hit"
    if shouldReplace then
        ch.focus = {
            x = tonumber(ev.x),
            y = tonumber(ev.y),
            z = tonumber(ev.z) or 0,
            kind = ev.kind or "contact",
            source = ev.source,
            sourceId = ev.sourceId,
            targetId = ev.targetId,
            at = ev.at,
            ttlMs = ev.ttlMs,
            confidence = tonumber(ev.confidence) or 0.5,
            heard = ev.heard == true,
            canSee = ev.canSee == true,
            indoor = ev.indoor == true
        }
        ch.rev = (tonumber(ch.rev) or 0) + 1
    end
    return ch.focus
end

function NPCSquadMemoryBridge.RememberContact(bandit, brain, threat, reason, confidence)
    if NPCSquadMemoryBridge.Config.enabled == false then return nil end
    if not (bandit and brain and threat and threat.x and threat.y) then return nil end
    local now = bsm_nowMs()
    local key = bsm_groupKey(brain)
    local ch = bsm_channel(key)
    bsm_trim(ch, now)
    local ev = {
        x = tonumber(threat.x),
        y = tonumber(threat.y),
        z = tonumber(threat.z) or (bandit and bandit:getZ()) or 0,
        kind = reason or (threat.canSee == true and "direct" or (threat.heard == true and "sound" or "contact")),
        source = "observe",
        sourceId = bsm_memberId(bandit, brain),
        targetId = threat.id,
        at = now,
        confidence = confidence or threat.confidence or threat.score or (threat.canSee == true and 0.92 or 0.48),
        ttlMs = threat.canSee == true and NPCSquadMemoryBridge.Config.contactMemoryMs or NPCSquadMemoryBridge.Config.soundMemoryMs,
        heard = threat.heard == true,
        canSee = threat.canSee == true,
        indoor = bsm_isIndoors(threat.x, threat.y, threat.z or bandit:getZ())
    }
    return bsm_pushEvent(ch, ev)
end

function NPCSquadMemoryBridge.NotifyShot(shooter, brain, target)
    if NPCSquadMemoryBridge.Config.enabled == false then return nil end
    if not (shooter and brain) then return nil end
    local now = bsm_nowMs()
    local key = bsm_groupKey(brain)
    local ch = bsm_channel(key)
    bsm_trim(ch, now)

    if target and target.getX and target.getY then
        return bsm_pushEvent(ch, {
            x = target:getX(),
            y = target:getY(),
            z = target.getZ and target:getZ() or shooter:getZ(),
            kind = "shot",
            source = "friendly_shot",
            sourceId = bsm_memberId(shooter, brain),
            targetId = bsm_id(target),
            at = now,
            confidence = 0.56,
            ttlMs = NPCSquadMemoryBridge.Config.soundMemoryMs,
            heard = true,
            indoor = bsm_isIndoors(target:getX(), target:getY(), target.getZ and target:getZ() or shooter:getZ())
        })
    end

    return bsm_pushEvent(ch, {
        x = shooter:getX(),
        y = shooter:getY(),
        z = shooter:getZ(),
        kind = "sound",
        source = "own_gunfire",
        sourceId = bsm_memberId(shooter, brain),
        at = now,
        confidence = 0.34,
        ttlMs = NPCSquadMemoryBridge.Config.soundMemoryMs,
        heard = true,
        indoor = bsm_isIndoors(shooter:getX(), shooter:getY(), shooter:getZ())
    })
end

function NPCSquadMemoryBridge.MarkUnderFire(victim, brain, attacker, reason, wasHit)
    if NPCSquadMemoryBridge.Config.enabled == false then return nil end
    if not (victim and brain and attacker and attacker.getX and attacker.getY) then return nil end
    local now = bsm_nowMs()
    local key = bsm_groupKey(brain)
    local ch = bsm_channel(key)
    bsm_trim(ch, now)
    return bsm_pushEvent(ch, {
        x = attacker:getX(),
        y = attacker:getY(),
        z = attacker.getZ and attacker:getZ() or victim:getZ(),
        kind = wasHit and "hit" or "under_fire",
        source = reason or "incoming_fire",
        sourceId = bsm_memberId(victim, brain),
        targetId = bsm_id(attacker),
        at = now,
        confidence = wasHit and 0.86 or 0.66,
        ttlMs = wasHit and NPCSquadMemoryBridge.Config.allyHitMemoryMs or NPCSquadMemoryBridge.Config.underFireMemoryMs,
        heard = true,
        indoor = bsm_isIndoors(attacker:getX(), attacker:getY(), attacker.getZ and attacker:getZ() or victim:getZ())
    })
end

function NPCSquadMemoryBridge.NotifyDamage(victim, brain, attacker)
    return NPCSquadMemoryBridge.MarkUnderFire(victim, brain, attacker, "ally_hit", true)
end

local function bsm_focusThreat(bandit, focus)
    if not (bandit and focus and focus.x and focus.y) then return nil end
    local now = bsm_nowMs()
    local age = now - (tonumber(focus.at) or 0)
    local conf = tonumber(focus.confidence) or 0.4
    if age > (tonumber(focus.ttlMs) or NPCSquadMemoryBridge.Config.contactMemoryMs or 90000) then return nil end
    conf = conf * math.max(0.15, 1.0 - age / math.max(1, tonumber(focus.ttlMs) or 90000))
    if conf < (tonumber(NPCSquadMemoryBridge.Config.minConfidenceToInvestigate) or 0.28) then return nil end
    return {
        x = focus.x,
        y = focus.y,
        z = focus.z or bandit:getZ(),
        kind = focus.kind or "memory",
        dist = bsm_dist(bandit:getX(), bandit:getY(), focus.x, focus.y),
        memoryOnly = true,
        canSee = false,
        heard = true,
        confidence = conf,
        source = focus.source or "squad_memory",
        updated = getGameTime and getGameTime():getWorldAgeHours() or 0,
        squadMemory = true
    }
end

function NPCSquadMemoryBridge.Update(bandit, brain, threat)
    if NPCSquadMemoryBridge.Config.enabled == false then return nil end
    if not (bandit and brain) then return nil end
    local now = bsm_nowMs()
    local key = bsm_groupKey(brain)
    local ch = bsm_channel(key)
    bsm_trim(ch, now)

    local id = bsm_memberId(bandit, brain)
    ch.members[id] = {
        id = id,
        x = bandit:getX(),
        y = bandit:getY(),
        z = bandit:getZ(),
        updatedAt = now,
        state = brain.state or (brain.fsm and brain.fsm.state),
        order = brain.order and (type(brain.order) == "table" and brain.order.name or brain.order) or nil
    }

    if threat and threat.x and threat.y then
        NPCSquadMemoryBridge.RememberContact(bandit, brain, threat, threat.canSee == true and "direct" or (threat.heard == true and "sound" or "contact"), threat.canSee == true and 0.96 or 0.50)
    end

    local focus = ch.focus
    brain.squadMemory = brain.squadMemory or {}
    brain.squadMemory.groupKey = key
    brain.squadMemory.focus = focus
    brain.squadMemory.rev = ch.rev
    brain.squadMemory.updatedAt = now

    if not threat then
        local memoryThreat = bsm_focusThreat(bandit, focus)
        if memoryThreat then
            brain.radioThreat = memoryThreat
            brain.fsm = brain.fsm or {}
            brain.fsm.lastKnownEnemyPosition = memoryThreat
            return memoryThreat
        end
    end
    return nil
end

local function bsm_searchSeed(contact, id, step)
    local base = tonumber((tostring(id or "0"):gsub("%D", ""))) or 0
    return (base * 17 + (tonumber(step) or 0) * 61) % 360
end

function NPCSquadMemoryBridge.GetInvestigationPoint(bandit, brain)
    if NPCSquadMemoryBridge.Config.enabled == false then return nil end
    if not (bandit and brain) then return nil end
    local ch = NPCSquadMemoryBridge.Channels[bsm_groupKey(brain)]
    local focus = ch and ch.focus or (brain.squadMemory and brain.squadMemory.focus) or nil
    local threat = bsm_focusThreat(bandit, focus)
    if not threat then return nil end

    local now = bsm_nowMs()
    local cached = brain.squadMemoryInvestigationPoint
    if cached and cached.x and cached.y and now < (tonumber(brain.squadMemoryNextSearchAt) or 0) then
        return cached
    end

    local id = bsm_memberId(bandit, brain)
    local indoor = focus.indoor == true or bsm_isIndoors(focus.x, focus.y, focus.z or bandit:getZ())
    local radius = indoor and (NPCSquadMemoryBridge.Config.indoorRadius or 7) or (NPCSquadMemoryBridge.Config.outdoorRadius or 13)
    local age = now - (tonumber(focus.at) or now)
    local step = math.floor(age / (tonumber(NPCSquadMemoryBridge.Config.searchStepMs) or 3600))

    if indoor and NPCIndoorTacticalBridge and NPCIndoorTacticalBridge.GetRoomSearchPoint then
        local okIndoor, p = pcall(function() return NPCIndoorTacticalBridge.GetRoomSearchPoint(bandit, brain, threat, step) end)
        if okIndoor and p and p.x and p.y then
            p.reason = p.reason or "squad memory room investigation"
            p.squadMemory = true
            p.inspectAnim = p.inspectAnim or "AimRifleLow"
            p.inspectTime = p.inspectTime or (55 + bsm_rand(35))
            brain.squadMemoryInvestigationPoint = p
            brain.squadMemoryNextSearchAt = now + (tonumber(NPCSquadMemoryBridge.Config.searchHoldMs) or 5200) + bsm_rand(900)
            return p
        end
    end

    local angle = bsm_searchSeed(focus, id, step) * 0.0174532925
    local ring = indoor and (2.2 + (step % 3) * 1.4) or (3.5 + (step % 4) * 2.3)
    local tx = focus.x + math.cos(angle) * math.min(radius, ring)
    local ty = focus.y + math.sin(angle) * math.min(radius, ring)
    local fx, fy, fz = bsm_findUsableAround(tx, ty, focus.z or bandit:getZ(), indoor and 5 or 7, bandit)
    if not fx then return nil end

    local point = {
        x = fx,
        y = fy,
        z = fz or bandit:getZ(),
        squadMemory = true,
        reason = indoor and "squad memory room sweep" or "squad memory area investigation",
        inspectAnim = indoor and ((bsm_rand(2) == 0) and "AimRifleLow" or "ShiftWeight") or ((bsm_rand(3) == 0) and "Forage" or "AimRifleLow"),
        inspectTime = indoor and (52 + bsm_rand(45)) or (70 + bsm_rand(65)),
        arriveDist = indoor and 1.55 or 2.1,
        memoryKind = focus.kind,
        confidence = threat.confidence
    }
    brain.squadMemoryInvestigationPoint = point
    brain.squadMemoryNextSearchAt = now + (tonumber(NPCSquadMemoryBridge.Config.searchHoldMs) or 5200) + bsm_rand(900)
    return point
end

function NPCSquadMemoryBridge.ChooseState(bandit, brain, threat, states)
    if NPCSquadMemoryBridge.Config.enabled == false or not states then return nil end
    if threat then return nil end
    local memoryThreat = NPCSquadMemoryBridge.Update(bandit, brain, nil)
    if memoryThreat and memoryThreat.dist and memoryThreat.dist > 1.35 then
        return states.SearchEnemy, "squad memory investigate contact"
    end
    return nil
end

return NPCSquadMemoryBridge
