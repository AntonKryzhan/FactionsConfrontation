-- NPCIndoorTacticalBridge.lua
-- Stage 365: indoor doorway/room discipline for human NPC movement.
--
-- This module is intentionally advisory. It does not replace pathfinding,
-- shooting, damage, tasks, commands or save contracts. It only nudges movement
-- targets away from blocked door tiles, one-cell chokepoints and crowded room
-- entries, and provides bounded room-clearing points for the fireteam layer.

NPCIndoorTacticalBridge = NPCIndoorTacticalBridge or {}
NPCIndoorTacticalBridge.VERSION = "2026-06-01-stage365-indoor-doorway-discipline-1"

NPCIndoorTacticalBridge.Config = NPCIndoorTacticalBridge.Config or {
    enabled = true,
    resolverEnabled = true,
    avoidDoorwayTargets = true,
    avoidNarrowChokepoints = true,
    avoidCrowdedInterior = true,
    doorwayPenalty = 18.0,
    chokepointPenalty = 11.0,
    crowdPenalty = 8.0,
    roomInteriorBonus = 3.0,
    wallSideBonus = 2.2,
    searchRadius = 4,
    tacticalRadius = 7,
    followIndoorSpacing = 1.35,
    followLineSpacing = 1.15,
    holdMs = 2400,
    tacticalHoldMs = 4200,
    maxScanSquares = 130
}

NPCIndoorTacticalBridge._scratch = NPCIndoorTacticalBridge._scratch or {}

local function bit_nowMs()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then return math.floor((getGameTime():getWorldAgeHours() or 0) * 3600000) end
    return 0
end

local function bit_rand(n)
    n = tonumber(n) or 1
    if n <= 1 then return 0 end
    if ZombRand then return ZombRand(n) end
    return math.random(0, n - 1)
end

local function bit_floor(v)
    return math.floor(tonumber(v) or 0)
end

local function bit_dist2(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return dx * dx + dy * dy
end

local function bit_len(dx, dy)
    local l = math.sqrt(dx * dx + dy * dy)
    if l < 0.001 then return 1 end
    return l
end

local function bit_square(x, y, z)
    local cell = getCell and getCell() or nil
    if not cell then return nil end
    return cell:getGridSquare(bit_floor(x), bit_floor(y), bit_floor(z or 0))
end

local function bit_squareBlocked(square, mover)
    if not square then return true end
    if NPCMovementStabilityBridge and NPCMovementStabilityBridge.IsSquareBlocked then
        local ok, blocked = pcall(function() return NPCMovementStabilityBridge.IsSquareBlocked(square, mover) end)
        if ok then return blocked == true end
    end
    local ok, solid = pcall(function() return square:isSolid() or square:isSolidTrans() end)
    return ok and solid == true
end

local function bit_canStep(mover, fromSq, toSq)
    if not (fromSq and toSq) then return false end
    if bit_squareBlocked(toSq, mover) then return false end
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

local function bit_isDoorObject(obj)
    if not obj then return false end
    local ok, ret = pcall(function()
        if instanceof and (instanceof(obj, "IsoDoor") or instanceof(obj, "IsoWindow") or instanceof(obj, "IsoThumpable")) then
            return true
        end
        local name = obj.getSpriteName and tostring(obj:getSpriteName() or ""):lower() or ""
        return name:find("door", 1, true) ~= nil
            or name:find("doorframe", 1, true) ~= nil
            or name:find("window", 1, true) ~= nil
            or name:find("stairs", 1, true) ~= nil
            or name:find("stair", 1, true) ~= nil
    end)
    return ok and ret == true
end

local function bit_hasWallSide(square)
    if not square then return false end
    local ok, objects = pcall(function() return square:getObjects() end)
    if not ok or not objects then return false end
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        local name = obj and obj.getSpriteName and tostring(obj:getSpriteName() or ""):lower() or ""
        if name:find("wall", 1, true) or name:find("counter", 1, true) or name:find("shelf", 1, true) or name:find("crate", 1, true) then
            return true
        end
    end
    return false
end

function NPCIndoorTacticalBridge.IsDoorwaySquare(square)
    if NPCIndoorTacticalBridge.Config.enabled == false or not square then return false end
    local ok, objects = pcall(function() return square:getObjects() end)
    if ok and objects then
        for i = 0, objects:size() - 1 do
            if bit_isDoorObject(objects:get(i)) then return true end
        end
    end

    -- Adjacent room transition without much free space behaves like a doorway
    -- even when the map tile is not an IsoDoor object.
    local room = nil
    local okRoom, r = pcall(function() return square:getRoom() end)
    if okRoom then room = r end
    local differentRoom = false
    local sx, sy, sz = square:getX(), square:getY(), square:getZ()
    local dirs = {{1,0},{-1,0},{0,1},{0,-1}}
    for _, d in ipairs(dirs) do
        local nsq = bit_square(sx + d[1], sy + d[2], sz)
        if nsq then
            local okN, nr = pcall(function() return nsq:getRoom() end)
            if okN and nr ~= room then
                differentRoom = true
                break
            end
        end
    end
    return differentRoom and NPCIndoorTacticalBridge.IsNarrowChokepoint(square, nil) == true
end

function NPCIndoorTacticalBridge.IsNarrowChokepoint(square, mover)
    if NPCIndoorTacticalBridge.Config.enabled == false or not square then return false end
    local passable = 0
    local sx, sy, sz = square:getX(), square:getY(), square:getZ()
    local dirs = {{1,0},{-1,0},{0,1},{0,-1}}
    for _, d in ipairs(dirs) do
        local nsq = bit_square(sx + d[1], sy + d[2], sz)
        if nsq and bit_canStep(mover, square, nsq) then
            passable = passable + 1
        end
    end
    return passable > 0 and passable <= 2
end

function NPCIndoorTacticalBridge.IsInteriorSquare(square)
    if not square then return false end
    local ok, room = pcall(function() return square:getRoom() end)
    return ok and room ~= nil
end

function NPCIndoorTacticalBridge.ScoreSquare(chr, brain, square, targetX, targetY, state, reason)
    if NPCIndoorTacticalBridge.Config.enabled == false or not square then return 0 end
    local score = 0
    local indoors = NPCIndoorTacticalBridge.IsInteriorSquare(square)
    local stateName = tostring(state or "")
    local reasonText = tostring(reason or ""):lower()
    local tactical = stateName == "TacticalCover"
        or stateName == "FlankEnemy"
        or stateName == "SuppressEnemy"
        or stateName == "HoldAngle"
        or stateName == "BoundForward"
        or stateName == "SearchEnemy"
        or reasonText:find("cover", 1, true) ~= nil
        or reasonText:find("fireteam", 1, true) ~= nil
        or reasonText:find("search", 1, true) ~= nil

    if indoors then score = score + (tonumber(NPCIndoorTacticalBridge.Config.roomInteriorBonus) or 3.0) end
    if bit_hasWallSide(square) then score = score + (tonumber(NPCIndoorTacticalBridge.Config.wallSideBonus) or 2.2) end
    if NPCIndoorTacticalBridge.Config.avoidDoorwayTargets ~= false and NPCIndoorTacticalBridge.IsDoorwaySquare(square) then
        score = score - (tonumber(NPCIndoorTacticalBridge.Config.doorwayPenalty) or 18.0)
        if tactical then score = score - 8 end
    end
    if NPCIndoorTacticalBridge.Config.avoidNarrowChokepoints ~= false and NPCIndoorTacticalBridge.IsNarrowChokepoint(square, chr) then
        score = score - (tonumber(NPCIndoorTacticalBridge.Config.chokepointPenalty) or 11.0)
    end
    if NPCIndoorTacticalBridge.Config.avoidCrowdedInterior ~= false and NPCHumanizedAIBridge and NPCHumanizedAIBridge.CountCrowdAround then
        local okCrowd, crowd = pcall(function()
            return NPCHumanizedAIBridge.CountCrowdAround(chr, brain, square:getX() + 0.5, square:getY() + 0.5, square:getZ(), indoors and 1.75 or 1.35)
        end)
        if okCrowd and crowd and crowd > 0 then
            score = score - crowd * (tonumber(NPCIndoorTacticalBridge.Config.crowdPenalty) or 8.0)
        end
    end

    return score
end

local function bit_memberSeed(brain, chr)
    local raw = 0
    if brain then raw = tonumber(brain.id or brain.uid or brain.persistentId or 0) or 0 end
    if raw == 0 and chr and NPCUtils and NPCUtils.GetCharacterID then
        local ok, id = pcall(function() return NPCUtils.GetCharacterID(chr) end)
        if ok and id then raw = tonumber(id) or 0 end
    end
    return math.abs(raw)
end

local function bit_candidateScore(chr, brain, sq, targetX, targetY, state, reason, preferredX, preferredY)
    if not sq or bit_squareBlocked(sq, chr) then return -1000000 end
    local sx, sy = sq:getX() + 0.5, sq:getY() + 0.5
    local score = -bit_dist2(sx, sy, preferredX or targetX or sx, preferredY or targetY or sy)
    score = score + NPCIndoorTacticalBridge.ScoreSquare(chr, brain, sq, targetX or sx, targetY or sy, state, reason)
    score = score + (((sq:getX() * 19 + sq:getY() * 23 + bit_memberSeed(brain, chr)) % 17) * 0.025)
    return score
end

function NPCIndoorTacticalBridge.FindBestAround(chr, brain, x, y, z, state, reason, radius, preferredX, preferredY)
    local cell = getCell and getCell() or nil
    if not cell or not x or not y then return nil end
    radius = tonumber(radius) or tonumber(NPCIndoorTacticalBridge.Config.searchRadius) or 4
    local bx, by, bz = bit_floor(x), bit_floor(y), bit_floor(z or (chr and chr.getZ and chr:getZ()) or 0)
    local bestSq, bestScore = nil, -1000000
    local checked = 0
    local maxChecks = tonumber(NPCIndoorTacticalBridge.Config.maxScanSquares) or 130

    for r = 0, radius do
        for dx = -r, r do
            for dy = -r, r do
                if r == 0 or math.abs(dx) == r or math.abs(dy) == r then
                    checked = checked + 1
                    if checked > maxChecks then break end
                    local sq = cell:getGridSquare(bx + dx, by + dy, bz)
                    local score = bit_candidateScore(chr, brain, sq, x, y, state, reason, preferredX, preferredY)
                    if score > bestScore then
                        bestScore = score
                        bestSq = sq
                    end
                end
            end
            if checked > maxChecks then break end
        end
        if checked > maxChecks then break end
    end
    return bestSq, bestScore
end

function NPCIndoorTacticalBridge.ResolveMoveTarget(chr, brain, state, reason, x, y, z)
    if NPCIndoorTacticalBridge.Config.enabled == false or NPCIndoorTacticalBridge.Config.resolverEnabled == false then return x, y, z, false end
    if not (chr and x and y) then return x, y, z, false end
    z = z or chr:getZ()
    local sq = bit_square(x, y, z)
    if not sq then return x, y, z, false end

    local stateName = tostring(state or "")
    local reasonText = tostring(reason or ""):lower()
    local active = stateName == "FollowPlayer" or stateName == "Regroup" or stateName == "GuardArea" or stateName == "PatrolArea"
        or stateName == "SearchEnemy" or stateName == "TacticalCover" or stateName == "FlankEnemy" or stateName == "SuppressEnemy"
        or stateName == "HoldAngle" or stateName == "BoundForward" or reasonText:find("fireteam", 1, true) ~= nil
        or reasonText:find("cover", 1, true) ~= nil or reasonText:find("follow", 1, true) ~= nil
    if not active then return x, y, z, false end

    local bad = bit_squareBlocked(sq, chr)
        or (NPCIndoorTacticalBridge.Config.avoidDoorwayTargets ~= false and NPCIndoorTacticalBridge.IsDoorwaySquare(sq))
        or (NPCIndoorTacticalBridge.Config.avoidNarrowChokepoints ~= false and NPCIndoorTacticalBridge.IsNarrowChokepoint(sq, chr))
    if not bad and NPCIndoorTacticalBridge.Config.avoidCrowdedInterior ~= false and NPCHumanizedAIBridge and NPCHumanizedAIBridge.IsCrowded then
        local okCrowd, crowded = pcall(function() return NPCHumanizedAIBridge.IsCrowded(chr, brain, x, y, z, 1.55) end)
        bad = okCrowd and crowded == true
    end
    if not bad then return x, y, z, false end

    brain = brain or (NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(chr) or nil)
    if brain then
        brain.ai = brain.ai or {}
        brain.ai.indoor = brain.ai.indoor or {}
        local hold = brain.ai.indoor.moveHold
        local now = bit_nowMs()
        if hold and hold.x and hold.y and now < (tonumber(hold.untilMs) or 0) and bit_dist2(hold.reqX or x, hold.reqY or y, x, y) <= 6.25 then
            return hold.x, hold.y, hold.z or z, true
        end
    end

    local radius = tonumber(NPCIndoorTacticalBridge.Config.searchRadius) or 4
    if stateName == "SearchEnemy" or stateName == "TacticalCover" or stateName == "FlankEnemy" then radius = math.max(radius, 5) end
    local bestSq = NPCIndoorTacticalBridge.FindBestAround(chr, brain, x, y, z, state, reason, radius, x, y)
    if not bestSq then return x, y, z, false end
    local rx, ry, rz = bestSq:getX(), bestSq:getY(), bestSq:getZ()

    if brain then
        brain.ai = brain.ai or {}
        brain.ai.indoor = brain.ai.indoor or {}
        brain.ai.indoor.moveHold = {
            reqX = x,
            reqY = y,
            reqZ = z,
            x = rx,
            y = ry,
            z = rz,
            state = stateName,
            untilMs = bit_nowMs() + (tonumber(NPCIndoorTacticalBridge.Config.holdMs) or 2400)
        }
    end
    return rx, ry, rz, true
end

function NPCIndoorTacticalBridge.AdjustFollowSlot(bandit, master, brain, x, y, z, strict)
    if NPCIndoorTacticalBridge.Config.enabled == false or not (bandit and master and x and y) then return x, y, z, false end
    local sq = bit_square(x, y, z or master:getZ())
    local masterSq = master.getSquare and master:getSquare() or nil
    local banditSq = bandit.getSquare and bandit:getSquare() or nil
    local indoors = NPCIndoorTacticalBridge.IsInteriorSquare(sq) or NPCIndoorTacticalBridge.IsInteriorSquare(masterSq) or NPCIndoorTacticalBridge.IsInteriorSquare(banditSq)
    if not indoors and not (sq and NPCIndoorTacticalBridge.IsNarrowChokepoint(sq, bandit)) then return x, y, z, false end

    local dx = master:getX() - bandit:getX()
    local dy = master:getY() - bandit:getY()
    local len = bit_len(dx, dy)
    local ux = dx / len
    local uy = dy / len
    local px = -uy
    local py = ux
    local seed = bit_memberSeed(brain, bandit)
    local rank = (seed % 5) - 2
    local spacing = strict and (tonumber(NPCIndoorTacticalBridge.Config.followLineSpacing) or 1.15) or (tonumber(NPCIndoorTacticalBridge.Config.followIndoorSpacing) or 1.35)
    local back = spacing * (1.0 + math.floor((seed % 9) / 3) * 0.75)
    local side = rank * 0.28
    local tx = master:getX() - ux * back + px * side
    local ty = master:getY() - uy * back + py * side
    local tz = z or master:getZ()

    local rx, ry, rz, changed = NPCIndoorTacticalBridge.ResolveMoveTarget(bandit, brain, "FollowPlayer", "indoor companion follow line", tx, ty, tz)
    return rx or tx, ry or ty, rz or tz, true or changed
end

function NPCIndoorTacticalBridge.GetInteriorTacticalPoint(bandit, brain, contact, role)
    if NPCIndoorTacticalBridge.Config.enabled == false or not (bandit and contact and contact.x and contact.y) then return nil end
    local bz = bandit:getZ()
    local banditSq = bandit.getSquare and bandit:getSquare() or nil
    local contactSq = bit_square(contact.x, contact.y, contact.z or bz)
    local indoors = NPCIndoorTacticalBridge.IsInteriorSquare(banditSq) or NPCIndoorTacticalBridge.IsInteriorSquare(contactSq)
    if not indoors then return nil end

    brain = brain or (NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(bandit) or nil)
    if brain then
        brain.ai = brain.ai or {}
        brain.ai.indoor = brain.ai.indoor or {}
        local p = brain.ai.indoor.tacticalPoint
        if p and p.x and p.y and p.role == role and bit_nowMs() < (tonumber(p.untilMs) or 0) then
            return p
        end
    end

    local bx, by = bandit:getX(), bandit:getY()
    local awayX = bx - contact.x
    local awayY = by - contact.y
    local len = bit_len(awayX, awayY)
    local ux = awayX / len
    local uy = awayY / len
    local px = -uy
    local py = ux
    local seed = bit_memberSeed(brain, bandit)
    local side = ((seed % 2) == 0) and 1 or -1
    if role == "flank_left" then side = 1 elseif role == "flank_right" then side = -1 end

    local preferredDist = 4.2
    if role == "overwatch" or role == "suppress" then preferredDist = 5.4 end
    if role == "bound" then preferredDist = 3.2 end
    local preferredX = contact.x + ux * preferredDist + px * side * (1.0 + (seed % 3) * 0.4)
    local preferredY = contact.y + uy * preferredDist + py * side * (1.0 + (seed % 3) * 0.4)

    local bestSq = NPCIndoorTacticalBridge.FindBestAround(bandit, brain, preferredX, preferredY, contact.z or bz, "TacticalCover", "indoor fireteam point", NPCIndoorTacticalBridge.Config.tacticalRadius or 7, preferredX, preferredY)
    if not bestSq then return nil end
    local point = {
        x = bestSq:getX(),
        y = bestSq:getY(),
        z = bestSq:getZ(),
        role = role,
        mode = role,
        indoor = true,
        arriveDist = 1.45,
        reason = "indoor doorway/room tactical point",
        untilMs = bit_nowMs() + (tonumber(NPCIndoorTacticalBridge.Config.tacticalHoldMs) or 4200)
    }
    if role == "overwatch" or role == "suppress" then point.arriveDist = 1.2 end
    if brain then brain.ai.indoor.tacticalPoint = point end
    return point
end

function NPCIndoorTacticalBridge.GetRoomSearchPoint(bandit, brain, contact, step)
    if NPCIndoorTacticalBridge.Config.enabled == false or not (bandit and contact and contact.x and contact.y) then return nil end
    local contactSq = bit_square(contact.x, contact.y, contact.z or bandit:getZ())
    local banditSq = bandit.getSquare and bandit:getSquare() or nil
    if not (NPCIndoorTacticalBridge.IsInteriorSquare(contactSq) or NPCIndoorTacticalBridge.IsInteriorSquare(banditSq)) then return nil end

    brain = brain or (NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(bandit) or nil)
    local seed = bit_memberSeed(brain, bandit)
    step = tonumber(step) or 0
    local angle = ((seed * 37 + step * 67) % 360) * 0.0174532925
    local ring = 2.0 + ((step + seed) % 3) * 1.35
    local tx = contact.x + math.cos(angle) * ring
    local ty = contact.y + math.sin(angle) * ring
    local bestSq = NPCIndoorTacticalBridge.FindBestAround(bandit, brain, tx, ty, contact.z or bandit:getZ(), "SearchEnemy", "indoor room clearing", 5, tx, ty)
    if not bestSq then return nil end
    return {
        x = bestSq:getX(),
        y = bestSq:getY(),
        z = bestSq:getZ(),
        role = "search",
        mode = "room_clear",
        indoor = true,
        arriveDist = 1.25,
        inspectAnim = (seed % 2 == 0) and "AimRifleLow" or "AimPistolLow",
        inspectTime = 42 + bit_rand(35),
        reason = "indoor room clearing / doorway discipline"
    }
end

function NPCIndoorTacticalBridge.DebugSquare(square)
    if not square then return "nil" end
    local parts = {}
    if NPCIndoorTacticalBridge.IsInteriorSquare(square) then parts[#parts + 1] = "room" end
    if NPCIndoorTacticalBridge.IsDoorwaySquare(square) then parts[#parts + 1] = "doorway" end
    if NPCIndoorTacticalBridge.IsNarrowChokepoint(square, nil) then parts[#parts + 1] = "narrow" end
    if bit_hasWallSide(square) then parts[#parts + 1] = "wallside" end
    return table.concat(parts, ",")
end
