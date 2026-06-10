-- NPCAIVisionBridge.lua
-- Neutral shared backend for AI vision sensing, LOS cache and threat memory.

NPCAIVisionBridge = NPCAIVisionBridge or {}

NPCAIVisionBridge.VERSION = "2026-05-30-stage303-obstacle-aware-los-cache-1"

NPCAIVisionBridge.Config = NPCAIVisionBridge.Config or {
    playerVisionRange = 36,
    zombieVisionRange = 26,
    banditVisionRange = 32,
    hearingRange = 12,
    closeRange = 3.0,
    memorySeconds = 8.0,
    softMemorySeconds = 22.0,
    heardThroughWallPenalty = 0.18,
    staleCurrentThreatMs = 1800,
    threatScanCooldownMs = 1100,
    maxThreatCandidatesPerScan = 8,
    losCacheMs = 900,
    losCacheMaxRecords = 768,
    playerThreshold = 0.28,
    zombieThreshold = 0.22,
    banditThreshold = 0.24
}

NPCAIVisionBridge._LOSCache = NPCAIVisionBridge._LOSCache or {items={}, count=0}
NPCAIVisionBridge._nearbyScratch = NPCAIVisionBridge._nearbyScratch or {}
NPCAIVisionBridge._friendScratch = NPCAIVisionBridge._friendScratch or {}

local function bav_now()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then return math.floor(getGameTime():getWorldAgeHours() * 3600000) end
    return 0
end

local function bav_dist2(x1, y1, x2, y2)
    local dx = x1 - x2
    local dy = y1 - y2
    return dx * dx + dy * dy
end

local function bav_dist(x1, y1, x2, y2)
    return math.sqrt(bav_dist2(x1, y1, x2, y2))
end

local function bav_getLoadLevel()
    if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.GetLoadState then
        local ok, state = pcall(function() return NPCWorkSchedulerBridge.GetLoadState(false) end)
        if ok and state then return tonumber(state.level) or 0, tonumber(state.zoom) or 1 end
    end
    return 0, 1
end

local function bav_getBrain(chr)
    if not chr or not NPCBrainData or not NPCBrainData.Get then return nil end

    local ok, brain = pcall(function()
        return NPCBrainData.Get(chr)
    end)

    if ok then return brain end
    return nil
end

local function bav_isAlive(chr)
    if not chr then return false end

    local ok, dead = pcall(function()
        return chr:isDead()
    end)
    if ok and dead then return false end

    ok, dead = pcall(function()
        return chr:isAlive()
    end)
    if ok and dead == false then return false end

    return true
end

local function bav_sameZ(observer, target)
    local ok, oz, tz = pcall(function()
        return observer:getZ(), target:getZ()
    end)

    if not ok then return true end
    return oz == tz
end

local function bav_getSquareLight(target)
    if not target then return 0.5 end

    local ok, square = pcall(function()
        return target:getSquare()
    end)

    if not ok or not square then return 0.5 end

    local lightOk, light = pcall(function()
        return square:getLightLevel(0)
    end)

    if lightOk and light then return light end
    return 0.5
end

local function bav_blockedByWall(observer, target)
    local ok, osq, tsq = pcall(function()
        return observer:getSquare(), target:getSquare()
    end)

    if not ok or not osq or not tsq then return false end

    local wallOk, blocked = pcall(function()
        if osq == tsq then return false end
        local dx = tsq:getX() - osq:getX()
        local dy = tsq:getY() - osq:getY()
        if math.abs(dx) <= 1 and math.abs(dy) <= 1 then
            if osq:testCollideAdjacent(observer, dx, dy, 0) then return true end
            if osq:isBlockedTo(tsq) or tsq:isBlockedTo(osq) then return true end
        end
        return osq:isSomethingTo(tsq)
    end)

    return wallOk and blocked == true
end

local function bav_isBehind(observer, target)
    local ok, behind = pcall(function()
        return target:isBehind(observer)
    end)

    return ok and behind == true
end

local function bav_canSee(observer, target)
    local ok, canSee = pcall(function()
        return observer:CanSee(target)
    end)

    return ok and canSee == true
end

local function bav_characterKey(chr, fallback)
    if not chr then return tostring(fallback or "nil") end

    if NPCUtils and NPCUtils.GetCharacterID then
        local ok, id = pcall(function()
            return NPCUtils.GetCharacterID(chr)
        end)
        if ok and id ~= nil then return tostring(id) end
    end

    if NPCUtils and NPCUtils.GetZombieID then
        local ok, id = pcall(function()
            return NPCUtils.GetZombieID(chr)
        end)
        if ok and id ~= nil then return tostring(id) end
    end

    return tostring(fallback or chr)
end

local function bav_losCacheKey(observer, target, kind)
    return bav_characterKey(observer, "observer") .. ":" .. bav_characterKey(target, "target") .. ":" .. tostring(kind or "unknown")
end

local function bav_storeLOS(key, value, now)
    local cache = NPCAIVisionBridge._LOSCache or {items={}, count=0}
    if not cache.items then cache.items = {}; cache.count = 0 end
    local maxRecords = tonumber(NPCAIVisionBridge.Config.losCacheMaxRecords) or 360
    if (tonumber(cache.count) or 0) > maxRecords then
        cache.items = {}
        cache.count = 0
    end
    if not cache.items[key] then cache.count = (tonumber(cache.count) or 0) + 1 end
    cache.items[key] = {value=value == true, at=now or bav_now()}
    NPCAIVisionBridge._LOSCache = cache
end

local function bav_canSeeCached(observer, target, brain, kind, dist)
    local cacheMs = tonumber(NPCAIVisionBridge.Config.losCacheMs) or 0
    if cacheMs <= 0 then return bav_canSee(observer, target) end

    local now = bav_now()
    local key = bav_losCacheKey(observer, target, kind)
    local cache = NPCAIVisionBridge._LOSCache
    local entry = cache and cache.items and cache.items[key]
    if entry and entry.at and now - entry.at <= cacheMs then
        return entry.value == true
    end

    local close = tonumber(dist) and dist <= (tonumber(NPCAIVisionBridge.Config.closeRange) or 3.0)
    if not close and NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.AllowLOS then
        if not NPCWorkSchedulerBridge.AllowLOS(key, "ai_vision") then
            if entry and entry.at and now - entry.at <= cacheMs * 4 then
                return entry.value == true
            end
            return false
        end
    end

    local canSee = bav_canSee(observer, target)
    bav_storeLOS(key, canSee, now)
    return canSee
end


local function bav_threatStillEnemy(brain, threat)
    if not threat then return false end
    local kind = threat.kind or threat.targetKind
    if kind == "player" and NPCFactionBridge and NPCFactionBridge.IsEnabled and NPCFactionBridge.IsEnabled() and NPCFactionBridge.CanBrainAttackPlayer then
        local player = nil
        if NPCPlayerClient and NPCPlayerClient.GetPlayerById then
            player = NPCPlayerClient.GetPlayerById(threat.id or threat.targetId or threat.eid)
        end
        if player then
            return NPCFactionBridge.CanBrainAttackPlayer(brain, player) == true
        end
    end
    return true
end

local function bav_targetNoise(target, dist)
    if not target or not instanceof(target, "IsoPlayer") then return 0 end

    local noise = 0

    local ok, running = pcall(function()
        return target:isRunning()
    end)
    if ok and running then noise = noise + 0.18 end

    ok, running = pcall(function()
        return target:isSprinting()
    end)
    if ok and running then noise = noise + 0.25 end

    ok, running = pcall(function()
        return target:isSneaking()
    end)
    if ok and running then noise = noise - 0.12 end

    if dist <= NPCAIVisionBridge.Config.closeRange then
        noise = noise + 0.18
    elseif dist <= NPCAIVisionBridge.Config.hearingRange then
        noise = noise + math.max(0, 0.12 - (dist * 0.008))
    end

    return noise
end

local function bav_baseRange(brain, kind)
    local range

    if kind == "player" then
        range = NPCAIVisionBridge.Config.playerVisionRange
    elseif kind == "bandit" then
        range = NPCAIVisionBridge.Config.banditVisionRange
    else
        range = NPCAIVisionBridge.Config.zombieVisionRange
    end

    if brain and NPCEntity and NPCEntity.IsDNA and brain.id then
        -- DNA checks require the actual zombie in most call sites. Kept out here intentionally.
    end

    return range
end

function NPCAIVisionBridge.CanDetect(observer, target, brain, kind)
    if not observer or not target then return false, nil end
    if not bav_isAlive(target) then return false, nil end
    if not bav_sameZ(observer, target) then return false, nil end

    local ox, oy = observer:getX(), observer:getY()
    local tx, ty = target:getX(), target:getY()
    local d2 = bav_dist2(ox, oy, tx, ty)
    local range = bav_baseRange(brain, kind)

    if NPCEntity and NPCEntity.IsDNA and NPCEntity.IsDNA(observer, "blind") then
        range = range - 7
    end
    if range < 6 then range = 6 end

    local hearingRange = tonumber(NPCAIVisionBridge.Config.hearingRange) or 12
    local maxRange = math.max(range, hearingRange)
    if d2 > maxRange * maxRange then
        return false, nil
    end

    local dist = math.sqrt(d2)
    if dist > range and dist > hearingRange then
        return false, nil
    end

    local wall = bav_blockedByWall(observer, target)
    local close = dist <= NPCAIVisionBridge.Config.closeRange
    local inCone = close or not bav_isBehind(observer, target)
    local canSee = false
    if not wall or close then
        canSee = bav_canSeeCached(observer, target, brain, kind, dist)
    end
    local light = bav_getSquareLight(target)
    local noise = bav_targetNoise(target, dist)
    local distanceScore = math.max(0, 0.75 - (dist / math.max(1, range)))
    local score = light + distanceScore + noise

    if wall and dist > 1.35 then
        canSee = false
        score = noise + math.max(0, 0.28 - (dist / math.max(1, NPCAIVisionBridge.Config.hearingRange or 12)) * 0.16)
    end

    if close then score = score + 0.35 end
    if not inCone and not wall then score = score - 0.38 end
    if canSee then score = score + 0.18 end

    local threshold = NPCAIVisionBridge.Config.zombieThreshold
    if kind == "player" then
        threshold = NPCAIVisionBridge.Config.playerThreshold
    elseif kind == "bandit" then
        threshold = NPCAIVisionBridge.Config.banditThreshold
    end

    local heard = noise > 0.18 and dist <= NPCAIVisionBridge.Config.hearingRange
    local detected = false
    if close and not wall then
        detected = true
    elseif canSee and inCone and score >= threshold then
        detected = true
    elseif heard and not wall then
        detected = true
    elseif heard and wall and score >= (NPCAIVisionBridge.Config.heardThroughWallPenalty or 0.18) then
        detected = true
    end

    if not detected then return false, nil end

    return true, {
        target = target,
        x = tx,
        y = ty,
        z = target:getZ(),
        dist = dist,
        score = score,
        canSee = canSee,
        heard = heard,
        throughWall = wall and heard and not canSee,
        stimulus = canSee and "seen" or (heard and "heard" or "unknown"),
        kind = kind or "unknown"
    }
end

function NPCAIVisionBridge.RememberThreat(observer, brain, detection)
    if not brain or not detection then return end
    if NPCOrderContract and NPCOrderContract.CanAggro and not NPCOrderContract.CanAggro(brain) then
        if brain.ai and brain.ai.senses then
            brain.ai.senses.currentThreat = nil
            brain.ai.senses.lastThreat = nil
            brain.ai.senses.lastKnownEnemyPosition = nil
        end
        return
    end

    brain.ai = brain.ai or {}
    brain.ai.senses = brain.ai.senses or {}

    local now = bav_now()
    local canSee = detection.canSee == true
    local heard = detection.heard == true
    local confidence = tonumber(detection.score or 0) or 0
    if canSee then confidence = confidence + 0.35 end
    if heard then confidence = confidence + 0.12 end

    brain.ai.senses.lastThreat = {
        id = detection.id,
        x = detection.x,
        y = detection.y,
        z = detection.z,
        kind = detection.kind,
        dist = detection.dist,
        score = detection.score,
        confidence = confidence,
        canSee = canSee,
        heard = heard,
        throughWall = detection.throughWall == true,
        stimulus = detection.stimulus or (canSee and "seen" or (heard and "heard" or "unknown")),
        memoryOnly = false,
        seenAt = now,
        lastSeenAt = canSee and now or nil,
        lastHeardAt = heard and now or nil,
        lastKnownEnemyPosition = {x=detection.x, y=detection.y, z=detection.z, updatedAt=now, kind=detection.kind}
    }
    brain.ai.senses.currentThreat = brain.ai.senses.lastThreat
    brain.ai.senses.lastKnownEnemyPosition = brain.ai.senses.lastThreat.lastKnownEnemyPosition

    if NPCUtilityAIBridge and NPCUtilityAIBridge.RememberThreat then
        pcall(function()
            NPCUtilityAIBridge.RememberThreat(brain, detection)
        end)
    end
end

function NPCAIVisionBridge.GetRememberedThreat(brain)
    if NPCOrderContract and NPCOrderContract.CanAggro and not NPCOrderContract.CanAggro(brain) then
        if brain and brain.ai and brain.ai.senses then
            brain.ai.senses.currentThreat = nil
            brain.ai.senses.lastThreat = nil
            brain.ai.senses.lastKnownEnemyPosition = nil
        end
        return nil
    end
    if not brain or not brain.ai or not brain.ai.senses or not brain.ai.senses.lastThreat then return nil end

    local last = brain.ai.senses.lastThreat
    if not bav_threatStillEnemy(brain, last) then
        brain.ai.senses.lastThreat = nil
        brain.ai.senses.currentThreat = nil
        brain.ai.senses.lastKnownEnemyPosition = nil
        return nil
    end

    local now = bav_now()
    local ageMs = now - (last.seenAt or 0)
    local hardLimit = (NPCAIVisionBridge.Config.softMemorySeconds or NPCAIVisionBridge.Config.memorySeconds or 8) * 1000
    if ageMs > hardLimit then
        brain.ai.senses.lastThreat = nil
        brain.ai.senses.currentThreat = nil
        return nil
    end

    local memoryLimit = (NPCAIVisionBridge.Config.memorySeconds or 8) * 1000
    local confidence = tonumber(last.confidence or last.score or 0) or 0
    if ageMs > memoryLimit then
        confidence = confidence * 0.35
    else
        confidence = confidence * math.max(0.25, 1.0 - (ageMs / math.max(1, memoryLimit)) * 0.65)
    end

    return {
        id = last.id,
        x = last.x,
        y = last.y,
        z = last.z,
        kind = last.kind,
        dist = last.dist,
        score = last.score,
        confidence = confidence,
        canSee = false,
        heard = false,
        throughWall = last.throughWall == true,
        stimulus = "memory",
        memoryOnly = true,
        seenAt = last.seenAt,
        lastSeenAt = last.lastSeenAt,
        lastHeardAt = last.lastHeardAt,
        lastKnownEnemyPosition = last.lastKnownEnemyPosition
    }
end

function NPCAIVisionBridge.IsMemoryOnly(threat)
    return threat and threat.memoryOnly == true
end

function NPCAIVisionBridge.GetLastKnownEnemyPosition(brain)
    if not brain or not brain.ai or not brain.ai.senses then return nil end
    local pos = brain.ai.senses.lastKnownEnemyPosition
    if pos then return pos end
    local threat = NPCAIVisionBridge.GetRememberedThreat(brain)
    if threat then return {x=threat.x, y=threat.y, z=threat.z, kind=threat.kind, updatedAt=threat.seenAt} end
    return nil
end

function NPCAIVisionBridge.FindNearestThreat(observer, brain, maxDist, includePlayers)
    if NPCOrderContract and NPCOrderContract.CanAggro and not NPCOrderContract.CanAggro(brain) then return nil end
    if not observer then return nil end

    maxDist = maxDist or 30
    local loadLevel, zoom = bav_getLoadLevel()
    if loadLevel >= 3 then
        maxDist = math.min(maxDist, zoom >= 1.75 and 18 or 22)
    elseif loadLevel >= 2 then
        maxDist = math.min(maxDist, zoom >= 1.75 and 22 or 26)
    elseif loadLevel >= 1 and zoom >= 1.90 then
        maxDist = math.min(maxDist, 28)
    end
    local now = bav_now()
    if brain then
        brain.ai = brain.ai or {}
        brain.ai.senses = brain.ai.senses or {}
        local senses = brain.ai.senses
        local cached = senses.currentThreat
        if cached and cached.seenAt and now < (senses.nextThreatScanAt or 0) then
            if not bav_threatStillEnemy(brain, cached) then
                senses.currentThreat = nil
                if senses.lastThreat and senses.lastThreat.id == cached.id and senses.lastThreat.kind == cached.kind then
                    senses.lastThreat = nil
                    senses.lastKnownEnemyPosition = nil
                end
            else
                local cachedAge = now - (cached.seenAt or 0)
                if cachedAge <= (NPCAIVisionBridge.Config.staleCurrentThreatMs or 900) and (not cached.dist or cached.dist <= maxDist) then
                    return cached
                end
            end
        end
        local senseId = brain.id or brain.uid or brain.persistentId or bav_characterKey(observer, "observer")
        if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.AllowSense and not NPCWorkSchedulerBridge.AllowSense(senseId, brain, nil) then
            local remembered = NPCAIVisionBridge.GetRememberedThreat(brain)
            if remembered then return remembered end
            return senses.currentThreat
        end
        local scanCooldown = tonumber(NPCAIVisionBridge.Config.threatScanCooldownMs) or 1100
        if loadLevel >= 3 then
            scanCooldown = scanCooldown * 2
        elseif loadLevel >= 2 then
            scanCooldown = math.floor(scanCooldown * 1.5)
        end
        senses.nextThreatScanAt = now + scanCooldown
    end

    local ox, oy, oz = observer:getX(), observer:getY(), observer:getZ()
    local best = nil
    local bestD2 = maxDist * maxDist
    local checkedCandidates = 0
    local maxCandidates = tonumber(NPCAIVisionBridge.Config.maxThreatCandidatesPerScan) or 8
    if loadLevel >= 3 then
        maxCandidates = math.min(maxCandidates, 3)
    elseif loadLevel >= 2 then
        maxCandidates = math.min(maxCandidates, 5)
    elseif loadLevel >= 1 then
        maxCandidates = math.min(maxCandidates, 6)
    end

    if includePlayers ~= false and NPCPlayerClient and NPCPlayerClient.GetPlayers and ((NPCFactionBridge and NPCFactionBridge.IsEnabled and NPCFactionBridge.IsEnabled()) or (NPCEntity and NPCEntity.IsHostile and NPCEntity.IsHostile(observer))) then
        local playerList = NPCPlayerClient.GetPlayers()
        if playerList then
            for i = 0, playerList:size() - 1 do
                local player = playerList:get(i)
                if player and instanceof(player, "IsoPlayer") and not NPCPlayerClient.IsGhost(player) and player:getZ() == oz and (not NPCFactionBridge or not NPCFactionBridge.CanBrainAttackPlayer or NPCFactionBridge.CanBrainAttackPlayer(brain, player)) then
                    local d2 = bav_dist2(ox, oy, player:getX(), player:getY())
                    if d2 < bestD2 and checkedCandidates < maxCandidates then
                        checkedCandidates = checkedCandidates + 1
                        local ok, detection = NPCAIVisionBridge.CanDetect(observer, player, brain, "player")
                        if ok and detection then
                            bestD2 = d2
                            detection.id = NPCUtils and NPCUtils.GetCharacterID and NPCUtils.GetCharacterID(player) or nil
                            best = detection
                        end
                    end
                end
            end
        end
    end

    if NPCZombieCacheBridge and NPCZombieCacheBridge.CacheLight then
        local nearby = NPCZombieCacheBridge.CacheLight
        if NPCSpatialIndexBridge and NPCSpatialIndexBridge.GetNearbyAllInto then
            nearby = NPCAIVisionBridge._nearbyScratch or {}
            NPCAIVisionBridge._nearbyScratch = nearby
            NPCSpatialIndexBridge.GetNearbyAllInto(nearby, ox, oy, oz, maxDist)
        elseif NPCSpatialIndexBridge and NPCSpatialIndexBridge.GetNearbyAll then
            nearby = NPCSpatialIndexBridge.GetNearbyAll(ox, oy, oz, maxDist)
        end

        for id, data in pairs(nearby) do
            id = data and (data.id or id) or id
            if data and data.z == oz then
                local d2 = bav_dist2(ox, oy, data.x, data.y)
                if d2 > 0.01 and d2 < bestD2 then
                    local target = NPCZombieCacheBridge.Cache and NPCZombieCacheBridge.Cache[id]
                    if target and bav_isAlive(target) then
                        local tBrain = data.brain or bav_getBrain(target)
                        local enemy = false
                        local kind = "zombie"

                        if not tBrain or not tBrain.clan then
                            enemy = true
                            kind = "zombie"
                        elseif brain and tBrain and brain.roadPatrol and tBrain.roadPatrol and brain.patrolColor and tBrain.patrolColor and brain.patrolColor ~= tBrain.patrolColor then
                            enemy = true
                            kind = "bandit"
                        elseif brain and tBrain and brain.battleEnemyGroupId and tBrain.worldGroupId and tostring(brain.battleEnemyGroupId) == tostring(tBrain.worldGroupId) then
                            enemy = true
                            kind = "bandit"
                        elseif NPCFactionBridge and NPCFactionBridge.IsEnabled and NPCFactionBridge.IsEnabled() and NPCFactionBridge.AreBrainsEnemies and NPCFactionBridge.AreBrainsEnemies(brain, tBrain) then
                            enemy = true
                            kind = "bandit"
                        elseif (not NPCFactionBridge or not NPCFactionBridge.IsEnabled or not NPCFactionBridge.IsEnabled()) and brain and brain.clan ~= tBrain.clan and (brain.hostile or tBrain.hostile) then
                            enemy = true
                            kind = "bandit"
                        end

                        if enemy and checkedCandidates < maxCandidates then
                            checkedCandidates = checkedCandidates + 1
                            local ok, detection = NPCAIVisionBridge.CanDetect(observer, target, brain, kind)
                            if ok and detection then
                                bestD2 = d2
                                detection.id = id
                                best = detection
                            end
                        end
                    end
                end
            end
        end
    end

    if best then
        NPCAIVisionBridge.RememberThreat(observer, brain, best)
        if NPCHumanizedAIBridge and NPCHumanizedAIBridge.UpdateAwareness then
            pcall(function()
                NPCHumanizedAIBridge.UpdateAwareness(observer, brain, best)
            end)
        end
        return best
    end

    if brain and brain.ai and brain.ai.senses then
        brain.ai.senses.currentThreat = nil
    end

    return NPCAIVisionBridge.GetRememberedThreat(brain)
end

function NPCAIVisionBridge.CountFriendsAround(observer, brain, radius)
    if not observer or not brain or not NPCZombieCacheBridge or not NPCZombieCacheBridge.CacheLightB then return 0 end

    local ox, oy, oz = observer:getX(), observer:getY(), observer:getZ()
    local r2 = (radius or 2) * (radius or 2)
    local count = 0
    local nearby = NPCZombieCacheBridge.CacheLightB
    if NPCSpatialIndexBridge and NPCSpatialIndexBridge.GetNearbyNPCsInto then
        nearby = NPCAIVisionBridge._friendScratch or {}
        NPCAIVisionBridge._friendScratch = nearby
        NPCSpatialIndexBridge.GetNearbyNPCsInto(nearby, ox, oy, oz, radius or 2)
    elseif NPCSpatialIndexBridge and NPCSpatialIndexBridge.GetNearbyNPCs then
        nearby = NPCSpatialIndexBridge.GetNearbyNPCs(ox, oy, oz, radius or 2)
    end

    for _, data in pairs(nearby) do
        if data and data.z == oz and data.brain and data.brain.clan == brain.clan then
            local d2 = bav_dist2(ox, oy, data.x, data.y)
            if d2 > 0.01 and d2 < r2 then
                count = count + 1
            end
        end
    end

    return count
end
