-- NPCHumanizedAIBridge.lua
-- Neutral shared backend for Humanized movement/search awareness.

NPCHumanizedAIBridge = NPCHumanizedAIBridge or {}

NPCHumanizedAIBridge.VERSION = "2026-05-03-humanized-search-movement-1"

NPCHumanizedAIBridge.Config = NPCHumanizedAIBridge.Config or {
    personalSpaceRadius = 1.45,
    formationSpaceRadius = 2.10,
    reservationMs = 2400,
    targetOffsetRadius = 2,
    searchPointRadius = 5,
    searchStageMs = 2400,
    searchMaxStages = 5,
    suspicionDecayMs = 18000,
    suspicionSeenGain = 0.58,
    suspicionHeardGain = 0.34,
    suspicionMemoryGain = 0.18,
    suspiciousThreshold = 0.22,
    investigatingThreshold = 0.38,
    alertThreshold = 0.62,
    combatThreshold = 0.78
}

NPCHumanizedAIBridge.Reservations = NPCHumanizedAIBridge.Reservations or {}

local function bha_now()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then return math.floor(getGameTime():getWorldAgeHours() * 3600000) end
    return 0
end

local function bha_dist2(x1, y1, x2, y2)
    local dx = x1 - x2
    local dy = y1 - y2
    return dx * dx + dy * dy
end

local function bha_key(x, y, z)
    return tostring(math.floor(tonumber(x) or 0)) .. ":" .. tostring(math.floor(tonumber(y) or 0)) .. ":" .. tostring(math.floor(tonumber(z) or 0))
end

local function bha_ownerId(brain, chr)
    if brain then
        return tostring(brain.persistentId or brain.uid or brain.id or brain.name or "")
    end
    if chr and NPCUtils and NPCUtils.GetCharacterID then
        local ok, id = pcall(function()
            return NPCUtils.GetCharacterID(chr)
        end)
        if ok and id then return tostring(id) end
    end
    return tostring(chr or "unknown")
end

local function bha_brain(chr)
    if not chr or not NPCBrainData or not NPCBrainData.Get then return nil end
    local ok, brain = pcall(function()
        return NPCBrainData.Get(chr)
    end)
    if ok then return brain end
    return nil
end

local function bha_square(x, y, z)
    local cell = getCell()
    if not cell then return nil end
    return cell:getGridSquare(math.floor(x), math.floor(y), math.floor(z or 0))
end

local function bha_cleanup(now)
    now = now or bha_now()
    for key, entry in pairs(NPCHumanizedAIBridge.Reservations) do
        if not entry or not entry.untilMs or now > entry.untilMs then
            NPCHumanizedAIBridge.Reservations[key] = nil
        end
    end
end

function NPCHumanizedAIBridge.IsReserved(x, y, z, owner)
    bha_cleanup()
    local entry = NPCHumanizedAIBridge.Reservations[bha_key(x, y, z)]
    if not entry then return false end
    if owner and entry.owner == owner then return false end
    return true
end

function NPCHumanizedAIBridge.ReserveMoveCell(brain, chr, x, y, z, state, reason)
    if not x or not y then return end
    local now = bha_now()
    bha_cleanup(now)
    local owner = bha_ownerId(brain, chr)
    NPCHumanizedAIBridge.Reservations[bha_key(x, y, z)] = {
        owner = owner,
        x = math.floor(x),
        y = math.floor(y),
        z = math.floor(z or 0),
        state = state,
        reason = reason,
        untilMs = now + (NPCHumanizedAIBridge.Config.reservationMs or 2400)
    }
end

function NPCHumanizedAIBridge.CountCrowdAround(chr, brain, x, y, z, radius)
    if not x or not y then return 0 end
    radius = radius or NPCHumanizedAIBridge.Config.personalSpaceRadius or 1.45
    local r2 = radius * radius
    local count = 0

    if NPCZombieCacheBridge and NPCZombieCacheBridge.CacheLightB then
        local nearby = NPCZombieCacheBridge.CacheLightB
        if NPCSpatialIndexBridge and NPCSpatialIndexBridge.GetNearbyNPCs then
            local ok, data = pcall(function()
                return NPCSpatialIndexBridge.GetNearbyNPCs(x, y, z or 0, radius + 0.8)
            end)
            if ok and data then nearby = data end
        end

        for _, data in pairs(nearby) do
            if data and data.z == (z or data.z) then
                local sameClan = true
                if brain and data.brain and brain.clan and data.brain.clan then
                    sameClan = tostring(brain.clan) == tostring(data.brain.clan)
                end
                if sameClan then
                    local d2 = bha_dist2(x, y, data.x or x, data.y or y)
                    if d2 > 0.01 and d2 <= r2 then
                        count = count + 1
                    end
                end
            end
        end
    end

    return count
end

function NPCHumanizedAIBridge.IsCrowded(chr, brain, x, y, z, radius)
    return NPCHumanizedAIBridge.CountCrowdAround(chr, brain, x, y, z, radius) > 0
end

function NPCHumanizedAIBridge.ScoreMoveSquare(chr, brain, square, targetX, targetY, state, reason)
    if not square then return -1000000 end
    local sx = square:getX()
    local sy = square:getY()
    local sz = square:getZ()
    local score = -bha_dist2(sx + 0.5, sy + 0.5, targetX, targetY)

    local owner = bha_ownerId(brain, chr)
    if NPCHumanizedAIBridge.IsReserved(sx, sy, sz, owner) then
        score = score - 18
    end

    local radius = NPCHumanizedAIBridge.Config.personalSpaceRadius or 1.45
    if state == "FollowPlayer" or state == "Regroup" then
        radius = NPCHumanizedAIBridge.Config.formationSpaceRadius or 2.10
    end
    score = score - NPCHumanizedAIBridge.CountCrowdAround(chr, brain, sx + 0.5, sy + 0.5, sz, radius) * 7

    if NPCRoadNavBridge and NPCRoadNavBridge.ScorePoint then
        local ok, navScore, class = pcall(function()
            return NPCRoadNavBridge.ScorePoint(sx, sy)
        end)
        if ok and navScore then
            if class == "road" then score = score + 2.5
            elseif class == "town" then score = score + 0.8
            elseif class == "blocked" then score = score - 20 end
        end
    end

    -- Stable tiny bias: prevents every NPC from selecting the exact same cell.
    local seed = 0
    if brain then seed = tonumber(brain.id or brain.uid or brain.persistentId or 0) or 0 end
    score = score + (((sx * 13 + sy * 7 + seed) % 11) * 0.035)

    if state == "SearchEnemy" or state == "PatrolArea" or state == "GuardArea" or state == "DefendBase" then
        local cx = chr and chr:getX() or targetX
        local cy = chr and chr:getY() or targetY
        score = score - bha_dist2(sx + 0.5, sy + 0.5, cx, cy) * 0.025
    end

    return score
end

function NPCHumanizedAIBridge.ResolveMoveTarget(chr, brain, state, reason, x, y, z)
    if not chr or not x or not y then return nil end
    z = z or chr:getZ()
    local owner = bha_ownerId(brain, chr)
    local targetSq = bha_square(x, y, z)
    local targetBlocked = false
    if NPCMovementStabilityBridge and NPCMovementStabilityBridge.IsSquareBlocked then
        targetBlocked = not targetSq or NPCMovementStabilityBridge.IsSquareBlocked(targetSq, chr)
    else
        targetBlocked = targetSq == nil
    end

    local crowded = NPCHumanizedAIBridge.IsCrowded(chr, brain, x, y, z, NPCHumanizedAIBridge.Config.personalSpaceRadius or 1.45)
    local reserved = NPCHumanizedAIBridge.IsReserved(x, y, z, owner)
    local shouldHumanize = state == "FollowPlayer"
        or state == "Regroup"
        or state == "GuardArea"
        or state == "PatrolArea"
        or state == "LootArea"
        or state == "ReturnToBase"
        or state == "SearchEnemy"
        or state == "DefendBase"
        or state == "RecoverPath"

    if not targetBlocked and not crowded and not reserved and not shouldHumanize then
        NPCHumanizedAIBridge.ReserveMoveCell(brain, chr, x, y, z, state, reason)
        return x, y, z, false
    end

    local bestSq = nil
    local bestScore = -1000000
    local cell = getCell()
    if not cell then return nil end

    local bx = math.floor(x)
    local by = math.floor(y)
    local bz = math.floor(z or 0)
    local radius = NPCHumanizedAIBridge.Config.targetOffsetRadius or 2
    if targetBlocked or state == "SearchEnemy" or state == "RecoverPath" then
        radius = math.max(radius, 5)
    elseif state == "FollowPlayer" or state == "Regroup" then
        radius = math.max(radius, 3)
    end

    for r=0, radius do
        for dx=-r, r do
            for dy=-r, r do
                if r == 0 or math.abs(dx) == r or math.abs(dy) == r then
                    local sq = cell:getGridSquare(bx + dx, by + dy, bz)
                    if sq then
                        local blocked = false
                        if NPCMovementStabilityBridge and NPCMovementStabilityBridge.IsSquareBlocked then
                            blocked = NPCMovementStabilityBridge.IsSquareBlocked(sq, chr)
                        end
                        if not blocked then
                            local score = NPCHumanizedAIBridge.ScoreMoveSquare(chr, brain, sq, x, y, state, reason)
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

    if bestSq then
        NPCHumanizedAIBridge.ReserveMoveCell(brain, chr, bestSq:getX(), bestSq:getY(), bestSq:getZ(), state, reason)
        local changed = bestSq:getX() ~= math.floor(x) or bestSq:getY() ~= math.floor(y) or bestSq:getZ() ~= math.floor(z or 0)
        return bestSq:getX(), bestSq:getY(), bestSq:getZ(), changed or crowded or reserved or targetBlocked
    end

    if not targetBlocked then
        NPCHumanizedAIBridge.ReserveMoveCell(brain, chr, x, y, z, state, reason)
        return x, y, z, crowded or reserved
    end

    return nil
end

function NPCHumanizedAIBridge.UpdateAwareness(chr, brain, threat)
    if not brain then return nil end
    brain.ai = brain.ai or {}
    brain.ai.humanized = brain.ai.humanized or {}
    local h = brain.ai.humanized
    local now = bha_now()
    local level = tonumber(h.suspicion or 0) or 0
    local lastAt = h.updatedAt or now
    local decayMs = NPCHumanizedAIBridge.Config.suspicionDecayMs or 18000
    local elapsed = math.max(0, now - lastAt)

    if elapsed > 0 then
        level = math.max(0, level - (elapsed / decayMs))
    end

    if threat then
        local gain = NPCHumanizedAIBridge.Config.suspicionMemoryGain or 0.18
        local stimulus = "memory"
        if threat.canSee == true and threat.memoryOnly ~= true then
            gain = NPCHumanizedAIBridge.Config.suspicionSeenGain or 0.58
            stimulus = "seen"
        elseif threat.heard == true then
            gain = NPCHumanizedAIBridge.Config.suspicionHeardGain or 0.34
            stimulus = "heard"
        elseif threat.memoryOnly == true then
            gain = NPCHumanizedAIBridge.Config.suspicionMemoryGain or 0.18
            stimulus = "memory"
        end
        if threat.throughWall == true then stimulus = "heard_through_wall" end
        local confidence = tonumber(threat.confidence or threat.score or 0.35) or 0.35
        level = math.min(1.0, math.max(level, gain + confidence * 0.28))
        h.lastStimulus = stimulus
        h.lastStimulusAt = now
        h.lastStimulusPos = {x=threat.x, y=threat.y, z=threat.z or (chr and chr:getZ() or 0), kind=threat.kind, confidence=confidence}
        h.memoryConfidence = confidence
    end

    h.suspicion = level
    h.updatedAt = now

    local state = "calm"
    if level >= (NPCHumanizedAIBridge.Config.combatThreshold or 0.78) then
        state = "combat"
    elseif level >= (NPCHumanizedAIBridge.Config.alertThreshold or 0.62) then
        state = "alert"
    elseif level >= (NPCHumanizedAIBridge.Config.investigatingThreshold or 0.38) then
        state = "investigating"
    elseif level >= (NPCHumanizedAIBridge.Config.suspiciousThreshold or 0.22) then
        state = "suspicious"
    end
    h.awarenessState = state
    brain.awareness = state
    brain.suspicion = level
    return h
end

local function bha_makePoint(x, y, z, reason)
    return {x=x, y=y, z=z, reason=reason}
end

function NPCHumanizedAIBridge.BuildInvestigationPoints(chr, brain, last)
    if not chr or not last or not last.x or not last.y then return nil end
    local z = last.z or chr:getZ()
    local bx = tonumber(last.x) or chr:getX()
    local by = tonumber(last.y) or chr:getY()
    local cx = chr:getX()
    local cy = chr:getY()
    local dx = bx - cx
    local dy = by - cy
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.01 then len = 1 end
    dx = dx / len
    dy = dy / len
    local px = -dy
    local py = dx

    local radius = NPCHumanizedAIBridge.Config.searchPointRadius or 5
    local raw = {
        bha_makePoint(bx - dx * 1.5, by - dy * 1.5, z, "approach last contact"),
        bha_makePoint(bx + px * 2.5, by + py * 2.5, z, "check left of contact"),
        bha_makePoint(bx - px * 2.5, by - py * 2.5, z, "check right of contact"),
        bha_makePoint(bx + dx * 2.0, by + dy * 2.0, z, "check beyond contact"),
        bha_makePoint(bx - dx * 3.0, by - dy * 3.0, z, "listen after lost contact")
    }

    local points = {}
    for _, p in ipairs(raw) do
        local sx, sy, sz = p.x, p.y, p.z
        if NPCMovementStabilityBridge and NPCMovementStabilityBridge.FindFreeAround then
            local sq = NPCMovementStabilityBridge.FindFreeAround(sx, sy, sz, chr, radius)
            if sq then
                sx = sq:getX()
                sy = sq:getY()
                sz = sq:getZ()
            end
        end
        points[#points + 1] = {x=sx, y=sy, z=sz, reason=p.reason}
    end

    return points
end

function NPCHumanizedAIBridge.GetInvestigationPoint(chr, brain, last)
    if not chr or not brain or not last or not last.x or not last.y then return nil end
    brain.ai = brain.ai or {}
    brain.ai.humanized = brain.ai.humanized or {}
    local h = brain.ai.humanized
    local now = bha_now()
    local key = bha_key(last.x, last.y, last.z or chr:getZ())

    if not h.search or h.search.key ~= key or now > (h.search.expiresAt or 0) then
        h.search = {
            key = key,
            stage = 1,
            points = NPCHumanizedAIBridge.BuildInvestigationPoints(chr, brain, last) or {},
            nextStageAt = now,
            expiresAt = now + (NPCHumanizedAIBridge.Config.searchStageMs or 2400) * ((NPCHumanizedAIBridge.Config.searchMaxStages or 5) + 2)
        }
    end

    local search = h.search
    if #search.points == 0 then return nil end

    local point = search.points[search.stage] or search.points[#search.points]
    local dist = math.sqrt(bha_dist2(chr:getX(), chr:getY(), point.x, point.y))
    if dist < 2.2 and now >= (search.nextStageAt or 0) then
        search.stage = math.min(#search.points, (search.stage or 1) + 1)
        search.nextStageAt = now + (NPCHumanizedAIBridge.Config.searchStageMs or 2400)
        point = search.points[search.stage] or point
        point.inspectHere = true
    end

    point.stage = search.stage
    point.totalStages = #search.points
    point.reason = point.reason or "investigate last contact"
    return point
end

function NPCHumanizedAIBridge.GetDebugReason(brain)
    if not brain or not brain.ai or not brain.ai.humanized then return nil end
    local h = brain.ai.humanized
    if h.awarenessState and h.awarenessState ~= "calm" then
        return tostring(h.awarenessState) .. " / " .. tostring(h.lastStimulus or "unknown")
    end
    return nil
end
