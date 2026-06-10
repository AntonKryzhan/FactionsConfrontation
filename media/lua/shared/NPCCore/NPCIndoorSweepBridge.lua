-- NPCIndoorSweepBridge.lua
-- Stage 374: advanced indoor sweep / stack-entry discipline.
--
-- Advisory layer only. It does not replace pathfinding, damage, shooting,
-- networking, save data or task names. It provides bounded entry-stack and
-- room-sweep points so squads stop flooding one doorway and start clearing
-- interiors in short, ordered movements.

NPCIndoorSweepBridge = NPCIndoorSweepBridge or {}
NPCIndoorSweepBridge.VERSION = "2026-06-01-stage374-advanced-indoor-sweep-stack-entry-1"

pcall(require, "NPCCore/NPCIndoorTacticalBridge")
pcall(require, "NPCCore/NPCMovementStabilityBridge")
pcall(require, "NPCCore/NPCHumanizedAIBridge")
pcall(require, "NPCCore/NPCSquadMemoryBridge")
pcall(require, "NPCCore/NPCTacticalAngleBridge")
pcall(require, "NPCCore/NPCLegacyGlobalsBridge")

NPCIndoorSweepBridge.Config = NPCIndoorSweepBridge.Config or {
    enabled = true,
    stackEnabled = true,
    sweepEnabled = true,
    maxMembers = 8,
    maxDoorScanSquares = 121,
    doorwaySearchRadius = 5,
    stackHoldMs = 2200,
    stackReuseMs = 5200,
    sweepReuseMs = 3600,
    roomSweepStepMs = 3000,
    maxStackDistance = 13.5,
    maxIndoorContactDistance = 22.0,
    entryReleaseDistance = 4.25,
    stackSpacing = 1.05,
    stackSideOffset = 0.35,
    sweepRadius = 7,
    roomSideBias = 2.4,
    doorwayPenalty = 22.0,
    crowdPenalty = 9.0,
    debug = false
}

NPCIndoorSweepBridge.Channels = NPCIndoorSweepBridge.Channels or {}

local function bis_nowMs()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then
        local ok, h = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok and h then return math.floor((tonumber(h) or 0) * 3600000) end
    end
    return 0
end

local function bis_rand(n)
    n = tonumber(n) or 1
    if n <= 1 then return 0 end
    if ZombRand then return ZombRand(n) end
    return math.random(0, n - 1)
end

local function bis_floor(v)
    return math.floor(tonumber(v) or 0)
end

local function bis_dist2(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return dx * dx + dy * dy
end

local function bis_dist(x1, y1, x2, y2)
    return math.sqrt(bis_dist2(x1, y1, x2, y2))
end

local function bis_len(dx, dy)
    local l = math.sqrt(dx * dx + dy * dy)
    if l < 0.001 then return 1 end
    return l
end

local function bis_square(x, y, z)
    local cell = getCell and getCell() or nil
    if not cell then return nil end
    return cell:getGridSquare(bis_floor(x), bis_floor(y), bis_floor(z or 0))
end

local function bis_squareBlocked(square, mover)
    if not square then return true end
    if NPCMovementStabilityBridge and NPCMovementStabilityBridge.IsSquareBlocked then
        local ok, blocked = pcall(function() return NPCMovementStabilityBridge.IsSquareBlocked(square, mover) end)
        if ok then return blocked == true end
    end
    local ok, solid = pcall(function() return square:isSolid() or square:isSolidTrans() end)
    return ok and solid == true
end

local function bis_isInterior(square)
    if NPCIndoorTacticalBridge and NPCIndoorTacticalBridge.IsInteriorSquare then
        local ok, inside = pcall(function() return NPCIndoorTacticalBridge.IsInteriorSquare(square) end)
        if ok then return inside == true end
    end
    if not square then return false end
    local ok, room = pcall(function() return square:getRoom() end)
    return ok and room ~= nil
end

local function bis_isDoorway(square, mover)
    if not square then return false end
    if NPCIndoorTacticalBridge and NPCIndoorTacticalBridge.IsDoorwaySquare then
        local ok, doorway = pcall(function() return NPCIndoorTacticalBridge.IsDoorwaySquare(square) end)
        if ok and doorway == true then return true end
    end
    if NPCIndoorTacticalBridge and NPCIndoorTacticalBridge.IsNarrowChokepoint then
        local ok, narrow = pcall(function() return NPCIndoorTacticalBridge.IsNarrowChokepoint(square, mover) end)
        if ok and narrow == true then return true end
    end
    return false
end

local function bis_memberId(chr, brain)
    if brain then
        if brain.persistentId then return tostring(brain.persistentId) end
        if brain.uid then return tostring(brain.uid) end
        if brain.id then return tostring(brain.id) end
    end
    if chr and NPCUtils and NPCUtils.GetCharacterID then
        local ok, id = pcall(function() return NPCUtils.GetCharacterID(chr) end)
        if ok and id then return tostring(id) end
    end
    if chr and NPCUtils and NPCUtils.GetZombieID then
        local ok, id = pcall(function() return NPCUtils.GetZombieID(chr) end)
        if ok and id then return tostring(id) end
    end
    return tostring(chr or "unknown")
end

local function bis_groupKey(brain)
    if NPCTacticalRadioBridge and NPCTacticalRadioBridge.GroupKey then
        local ok, key = pcall(function() return NPCTacticalRadioBridge.GroupKey(brain) end)
        if ok and key then return tostring(key) end
    end
    if not brain then return "nogroup" end
    return tostring(brain.worldGroupId or brain.groupId or brain.physicalGroupId or brain.clan or brain.masterId or "nogroup")
end

local function bis_channel(brain)
    local key = bis_groupKey(brain)
    local ch = NPCIndoorSweepBridge.Channels[key]
    if not ch then
        ch = {members = {}, plan = {}, createdAt = bis_nowMs(), rev = 0}
        NPCIndoorSweepBridge.Channels[key] = ch
    end
    ch.members = ch.members or {}
    ch.plan = ch.plan or {}
    return ch, key
end

local function bis_trim(ch, now)
    now = now or bis_nowMs()
    for id, m in pairs(ch.members or {}) do
        if not m or now - (tonumber(m.updatedAt) or 0) > 18000 then ch.members[id] = nil end
    end
    local p = ch.plan or {}
    if p.expiresAt and now > tonumber(p.expiresAt) then
        ch.plan = {}
    end
end

local function bis_sortedMembers(ch)
    local ids = {}
    for id, m in pairs(ch and ch.members or {}) do
        if m and m.x and m.y then ids[#ids + 1] = tostring(id) end
    end
    table.sort(ids)
    return ids
end

local function bis_memberRank(ch, id)
    local ids = bis_sortedMembers(ch)
    for i, mid in ipairs(ids) do
        if tostring(mid) == tostring(id) then return i, #ids end
    end
    return 1, math.max(#ids, 1)
end

local function bis_contactFromBrain(bandit, brain, contact)
    if contact and contact.x and contact.y then
        return {
            x = tonumber(contact.x),
            y = tonumber(contact.y),
            z = tonumber(contact.z) or (bandit and bandit:getZ()) or 0,
            dist = contact.dist,
            canSee = contact.canSee == true,
            memoryOnly = contact.memoryOnly == true,
            confidence = tonumber(contact.confidence or contact.score or 0.5) or 0.5
        }
    end
    if brain then
        local c = brain.fireteam and brain.fireteam.contact or nil
        if c and c.x and c.y then return bis_contactFromBrain(bandit, nil, c) end
        if brain.radioThreat and brain.radioThreat.x and brain.radioThreat.y then return bis_contactFromBrain(bandit, nil, brain.radioThreat) end
        if brain.fsm and brain.fsm.lastKnownEnemyPosition and brain.fsm.lastKnownEnemyPosition.x then
            return bis_contactFromBrain(bandit, nil, brain.fsm.lastKnownEnemyPosition)
        end
    end
    if NPCSquadMemoryBridge and NPCSquadMemoryBridge.Update then
        local ok, mem = pcall(function() return NPCSquadMemoryBridge.Update(bandit, brain, nil) end)
        if ok and mem and mem.x and mem.y then return bis_contactFromBrain(bandit, nil, mem) end
    end
    return nil
end

local function bis_isIndoorContact(bandit, contact)
    if not (bandit and contact and contact.x and contact.y) then return false end
    local bsq = bandit.getSquare and bandit:getSquare() or nil
    local tsq = bis_square(contact.x, contact.y, contact.z or bandit:getZ())
    if bis_isInterior(bsq) or bis_isInterior(tsq) then return true end
    if tsq and bis_isDoorway(tsq, bandit) then return true end
    return false
end

local function bis_findDoorway(bandit, contact)
    if not (bandit and contact and contact.x and contact.y) then return nil end
    local cell = getCell and getCell() or nil
    if not cell then return nil end
    local bz = contact.z or bandit:getZ()
    local bx, by = bandit:getX(), bandit:getY()
    local cx, cy = contact.x, contact.y
    local radius = tonumber(NPCIndoorSweepBridge.Config.doorwaySearchRadius) or 5
    local bestSq, bestScore = nil, -1000000
    local checked = 0
    local maxChecks = tonumber(NPCIndoorSweepBridge.Config.maxDoorScanSquares) or 121

    local midX = math.floor((bx + cx) * 0.5)
    local midY = math.floor((by + cy) * 0.5)
    for r = 0, radius do
        for dx = -r, r do
            for dy = -r, r do
                if r == 0 or math.abs(dx) == r or math.abs(dy) == r then
                    checked = checked + 1
                    if checked > maxChecks then break end
                    local sq = cell:getGridSquare(midX + dx, midY + dy, bis_floor(bz))
                    if sq and not bis_squareBlocked(sq, bandit) and bis_isDoorway(sq, bandit) then
                        local sx, sy = sq:getX() + 0.5, sq:getY() + 0.5
                        local score = -bis_dist2(sx, sy, bx, by) * 0.18 - bis_dist2(sx, sy, cx, cy) * 0.10
                        if bis_isInterior(sq) then score = score + 3 end
                        if score > bestScore then bestScore = score; bestSq = sq end
                    end
                end
            end
            if checked > maxChecks then break end
        end
        if checked > maxChecks then break end
    end

    if bestSq then return bestSq end
    local targetSq = bis_square(contact.x, contact.y, bz)
    if targetSq and bis_isDoorway(targetSq, bandit) and not bis_squareBlocked(targetSq, bandit) then return targetSq end
    return nil
end

local function bis_scoreEntryCandidate(chr, brain, sq, preferredX, preferredY, contact)
    if not sq or bis_squareBlocked(sq, chr) then return -1000000 end
    local sx, sy = sq:getX() + 0.5, sq:getY() + 0.5
    local score = -bis_dist2(sx, sy, preferredX, preferredY)
    if NPCIndoorTacticalBridge and NPCIndoorTacticalBridge.ScoreSquare then
        local ok, s = pcall(function() return NPCIndoorTacticalBridge.ScoreSquare(chr, brain, sq, contact and contact.x, contact and contact.y, "SearchEnemy", "advanced indoor stack entry") end)
        if ok and s then score = score + s end
    end
    if bis_isDoorway(sq, chr) then score = score - (tonumber(NPCIndoorSweepBridge.Config.doorwayPenalty) or 22.0) end
    if NPCHumanizedAIBridge and NPCHumanizedAIBridge.CountCrowdAround then
        local ok, crowd = pcall(function() return NPCHumanizedAIBridge.CountCrowdAround(chr, brain, sx, sy, sq:getZ(), 1.45) end)
        if ok and crowd and crowd > 0 then score = score - crowd * (tonumber(NPCIndoorSweepBridge.Config.crowdPenalty) or 9.0) end
    end
    return score
end

local function bis_bestAround(chr, brain, x, y, z, radius, contact)
    if NPCIndoorTacticalBridge and NPCIndoorTacticalBridge.FindBestAround then
        local ok, sq = pcall(function()
            return NPCIndoorTacticalBridge.FindBestAround(chr, brain, x, y, z, "SearchEnemy", "advanced indoor sweep", radius or 4, x, y)
        end)
        if ok and sq then return sq end
    end
    local cell = getCell and getCell() or nil
    if not cell then return nil end
    local bx, by, bz = bis_floor(x), bis_floor(y), bis_floor(z or 0)
    local best, bestScore = nil, -1000000
    radius = tonumber(radius) or 4
    for r = 0, radius do
        for dx = -r, r do
            for dy = -r, r do
                if r == 0 or math.abs(dx) == r or math.abs(dy) == r then
                    local sq = cell:getGridSquare(bx + dx, by + dy, bz)
                    local score = bis_scoreEntryCandidate(chr, brain, sq, x, y, contact)
                    if score > bestScore then best = sq; bestScore = score end
                end
            end
        end
    end
    return best
end

function NPCIndoorSweepBridge.Update(bandit, brain, contact)
    if NPCIndoorSweepBridge.Config.enabled == false or not (bandit and brain) then return nil end
    local c = bis_contactFromBrain(bandit, brain, contact)
    if not c or not c.x or not c.y then return nil end
    local dist = tonumber(c.dist) or bis_dist(bandit:getX(), bandit:getY(), c.x, c.y)
    if dist > (tonumber(NPCIndoorSweepBridge.Config.maxIndoorContactDistance) or 22.0) then return nil end
    if not bis_isIndoorContact(bandit, c) then return nil end

    local now = bis_nowMs()
    local ch = bis_channel(brain)
    bis_trim(ch, now)
    local id = bis_memberId(bandit, brain)
    ch.members[id] = {
        id = id,
        x = bandit:getX(),
        y = bandit:getY(),
        z = bandit:getZ(),
        updatedAt = now,
        state = brain.state or (brain.fsm and brain.fsm.state)
    }

    local p = ch.plan or {}
    local contactMoved = not p.contact or bis_dist2(p.contact.x or 0, p.contact.y or 0, c.x, c.y) > 16.0
    if contactMoved or now > (tonumber(p.expiresAt) or 0) then
        p = {
            mode = "stack",
            contact = c,
            startedAt = now,
            releaseAt = now + (tonumber(NPCIndoorSweepBridge.Config.stackHoldMs) or 2200),
            expiresAt = now + 24000,
            doorway = nil,
            step = 0,
            rev = (tonumber(ch.rev) or 0) + 1
        }
        ch.rev = p.rev
    else
        p.contact = c
    end

    if not p.doorway then
        local doorway = bis_findDoorway(bandit, c)
        if doorway then
            p.doorway = {x = doorway:getX(), y = doorway:getY(), z = doorway:getZ()}
        end
    end
    if p.mode == "stack" and now > (tonumber(p.releaseAt) or 0) then
        p.mode = "sweep"
        p.step = (tonumber(p.step) or 0) + 1
        p.sweepAt = now
    end
    ch.plan = p

    brain.indoorSweep = brain.indoorSweep or {}
    brain.indoorSweep.groupKey = bis_groupKey(brain)
    brain.indoorSweep.memberId = id
    brain.indoorSweep.mode = p.mode
    brain.indoorSweep.contact = c
    brain.indoorSweep.doorway = p.doorway
    return brain.indoorSweep
end

function NPCIndoorSweepBridge.GetStackPoint(bandit, brain, contact)
    if NPCIndoorSweepBridge.Config.enabled == false or NPCIndoorSweepBridge.Config.stackEnabled == false then return nil end
    if not (bandit and brain) then return nil end
    local c = bis_contactFromBrain(bandit, brain, contact)
    if not c then return nil end
    local sweep = NPCIndoorSweepBridge.Update(bandit, brain, c)
    if not sweep then return nil end
    local ch = NPCIndoorSweepBridge.Channels[sweep.groupKey]
    local p = ch and ch.plan or nil
    if not p or not p.doorway then return nil end

    local now = bis_nowMs()
    local id = sweep.memberId or bis_memberId(bandit, brain)
    local rank, count = bis_memberRank(ch, id)
    count = math.min(count, tonumber(NPCIndoorSweepBridge.Config.maxMembers) or 8)
    if rank > count then rank = count end

    local distDoor = bis_dist(bandit:getX(), bandit:getY(), p.doorway.x + 0.5, p.doorway.y + 0.5)
    local canRelease = p.mode == "sweep" or now > (tonumber(p.releaseAt) or 0)
    if canRelease and (rank <= 2 or count <= 2 or distDoor <= (tonumber(NPCIndoorSweepBridge.Config.entryReleaseDistance) or 4.25)) then
        return nil
    end
    if distDoor > (tonumber(NPCIndoorSweepBridge.Config.maxStackDistance) or 13.5) and p.mode ~= "stack" then return nil end

    local vx = (p.doorway.x + 0.5) - c.x
    local vy = (p.doorway.y + 0.5) - c.y
    local len = bis_len(vx, vy)
    local ux = vx / len
    local uy = vy / len
    local px = -uy
    local py = ux
    local spacing = tonumber(NPCIndoorSweepBridge.Config.stackSpacing) or 1.05
    local side = ((rank % 2 == 0) and 1 or -1) * (tonumber(NPCIndoorSweepBridge.Config.stackSideOffset) or 0.35)
    local depth = 1.0 + (rank - 1) * spacing
    local tx = p.doorway.x + 0.5 + ux * depth + px * side
    local ty = p.doorway.y + 0.5 + uy * depth + py * side
    local sq = bis_bestAround(bandit, brain, tx, ty, p.doorway.z or bandit:getZ(), 3, c)
    if not sq then return nil end

    return {
        x = sq:getX(),
        y = sq:getY(),
        z = sq:getZ(),
        mode = "stack_entry",
        role = "stack" .. tostring(rank),
        indoor = true,
        indoorSweep = true,
        stackEntry = true,
        rank = rank,
        count = count,
        arriveDist = 1.05,
        reason = "advanced indoor stack entry"
    }
end

function NPCIndoorSweepBridge.GetRoomSweepPoint(bandit, brain, contact, role)
    if NPCIndoorSweepBridge.Config.enabled == false or NPCIndoorSweepBridge.Config.sweepEnabled == false then return nil end
    if not (bandit and brain) then return nil end
    local c = bis_contactFromBrain(bandit, brain, contact)
    if not c then return nil end
    local sweep = NPCIndoorSweepBridge.Update(bandit, brain, c)
    if not sweep then return nil end

    local ch = NPCIndoorSweepBridge.Channels[sweep.groupKey]
    local p = ch and ch.plan or nil
    if not p then return nil end
    local now = bis_nowMs()
    local id = sweep.memberId or bis_memberId(bandit, brain)
    local rank, count = bis_memberRank(ch, id)
    count = math.max(count, 1)

    brain.indoorSweepPoint = brain.indoorSweepPoint or nil
    if brain.indoorSweepPoint and now < (tonumber(brain.indoorSweepPointUntil) or 0) then
        return brain.indoorSweepPoint
    end

    local step = math.floor((now - (tonumber(p.sweepAt or p.startedAt) or now)) / (tonumber(NPCIndoorSweepBridge.Config.roomSweepStepMs) or 3000))
    local seed = tonumber((tostring(id):gsub("%D", ""))) or (rank * 41)
    local baseAngle = ((rank - 1) / math.max(count, 1)) * 6.28318530718
    local angle = baseAngle + ((step * 31 + seed) % 45 - 22) * 0.0174532925
    local radius = 2.0 + ((rank + step) % 3) * (tonumber(NPCIndoorSweepBridge.Config.roomSideBias) or 2.4)
    if role == "overwatch" or role == "suppress" then radius = radius + 1.2 end
    if role == "bound" then radius = math.max(1.8, radius - 0.8) end

    local tx = c.x + math.cos(angle) * radius
    local ty = c.y + math.sin(angle) * radius
    local sq = bis_bestAround(bandit, brain, tx, ty, c.z or bandit:getZ(), tonumber(NPCIndoorSweepBridge.Config.sweepRadius) or 7, c)
    if not sq then return nil end

    local point = {
        x = sq:getX(),
        y = sq:getY(),
        z = sq:getZ(),
        mode = "room_sweep",
        role = role or "sweep",
        indoor = true,
        indoorSweep = true,
        stackEntry = false,
        arriveDist = 1.15,
        inspectAnim = ((rank + step) % 2 == 0) and "AimRifleLow" or "AimPistolLow",
        inspectTime = 36 + bis_rand(28),
        reason = "advanced indoor room sweep"
    }
    brain.indoorSweepPoint = point
    brain.indoorSweepPointUntil = now + (tonumber(NPCIndoorSweepBridge.Config.sweepReuseMs) or 3600) + bis_rand(600)
    return point
end

function NPCIndoorSweepBridge.GetManeuverPoint(bandit, brain, contact, role)
    if NPCIndoorSweepBridge.Config.enabled == false then return nil end
    local c = bis_contactFromBrain(bandit, brain, contact)
    if not c or not bis_isIndoorContact(bandit, c) then return nil end
    local stack = NPCIndoorSweepBridge.GetStackPoint(bandit, brain, c)
    if stack then return stack end
    return NPCIndoorSweepBridge.GetRoomSweepPoint(bandit, brain, c, role)
end

function NPCIndoorSweepBridge.GetSearchPoint(bandit, brain, contact)
    if NPCIndoorSweepBridge.Config.enabled == false then return nil end
    local c = bis_contactFromBrain(bandit, brain, contact)
    if not c or not bis_isIndoorContact(bandit, c) then return nil end
    local stack = NPCIndoorSweepBridge.GetStackPoint(bandit, brain, c)
    if stack then
        stack.inspectAnim = nil
        return stack
    end
    return NPCIndoorSweepBridge.GetRoomSweepPoint(bandit, brain, c, "search")
end

function NPCIndoorSweepBridge.DecorateTask(task, bandit, brain, point)
    if not task or not point then return task end
    task.indoorSweep = point.indoorSweep == true
    task.stackEntry = point.stackEntry == true
    task.indoorTactical = true
    task.tacticalStep = true
    task.engineAssist = true
    task.naturalMotion = true
    task.smoothTurn = true
    task.noHardFace = true
    task.arriveDist = tonumber(point.arriveDist) or tonumber(task.arriveDist) or 1.15
    task.pathThrottleMs = math.max(tonumber(task.pathThrottleMs) or 0, point.stackEntry and 1150 or 1350)
    task.sameTargetPathThrottleMs = math.max(tonumber(task.sameTargetPathThrottleMs) or 0, point.stackEntry and 4200 or 4800)
    task.engineAssistSoftRetargetRadius = math.max(tonumber(task.engineAssistSoftRetargetRadius) or 0, 3.0)
    task.engineAssistSoftRetargetHoldMs = math.max(tonumber(task.engineAssistSoftRetargetHoldMs) or 0, 4600)
    if brain then
        brain.ai = brain.ai or {}
        brain.ai.indoorSweepLastTaskAt = bis_nowMs()
    end
    return task
end

function NPCIndoorSweepBridge.Debug(brain)
    if not brain or not brain.indoorSweep then return nil end
    return tostring(brain.indoorSweep.mode or "idle") .. ":" .. tostring(brain.indoorSweep.memberId or "?")
end
