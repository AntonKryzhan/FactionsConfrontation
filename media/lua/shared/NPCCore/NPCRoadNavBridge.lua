-- NPCRoadNavBridge.lua
-- Safe road/town navigation helpers for MP legacy item module.
-- Uses only z-aware MetaGrid calls; avoids Java overloads that spam/crash in PZ 41 MP.

require "NPCCore/NPCLegacyGlobalsBridge"

local NPC_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
NPCRoadNavBridge = NPCRoadNavBridge or {}
NPCRoadNavBridge.VERSION = "2026-05-02-road-patrol-chain-1"
local function brn_worldDirector()
    return NPCWorldDirector or NPC_LEGACY_GLOBALS.Get("WorldDirector") or nil
end

NPCRoadNavBridge.Config = NPCRoadNavBridge.Config or {
    loadedRoadSearchRadius = 52,
    loadedTownSearchRadius = 64,
    patrolRadius = 42,
    returnToRoadRadius = 80,
    chainStepMin = 9,
    chainStepMax = 18,
    chainSearchRadius = 24,
    chainExpireHours = 0.035,
    virtualStepRadius = 140,
    virtualStepAttempts = 180,
    roadScore = 90,
    preferredScore = 55,
    returnScore = 20
}

local BRN_BAD_ZONE_KEYWORDS = {"water", "deepforest", "deep forest", "forest", "vegetation", "vegitation", "foraging"}
local BRN_ROAD_ZONE_KEYWORDS = {"nav", "road", "street", "highway", "junction", "traffic"}
local BRN_TOWN_ZONE_KEYWORDS = {"town", "trailer", "commercial", "industrial", "business", "community", "restaurant", "shop", "store", "school", "police", "fire", "hospital", "parking"}
local BRN_SETTLEMENT_ZONE_KEYWORDS = {"farm", "farmhouse", "ranch", "camp"}

local function brn_lower(value)
    if not value then return "" end
    return string.lower(tostring(value))
end

local function brn_hasAny(value, needles)
    local v = brn_lower(value)
    for _, needle in ipairs(needles) do
        if string.find(v, needle, 1, true) then return true end
    end
    return false
end

local function brn_dist2(x1, y1, x2, y2)
    local dx = x1 - x2
    local dy = y1 - y2
    return dx * dx + dy * dy
end

local function brn_dist(x1, y1, x2, y2)
    return math.sqrt(brn_dist2(x1, y1, x2, y2))
end

local function brn_worldAgeHours()
    if getGameTime then return getGameTime():getWorldAgeHours() end
    return 0
end

local function brn_zoneType(zone)
    if not zone then return nil end
    local ok, zoneType = pcall(function() return zone:getType() end)
    if ok and zoneType then return tostring(zoneType) end
    return nil
end

local function brn_zoneListAdd(types, zone)
    local zoneType = brn_zoneType(zone)
    if zoneType then table.insert(types, zoneType) end
end

function NPCRoadNavBridge.GetZoneTypesAt(x, y)
    local types = {}
    local world = getWorld and getWorld() or nil
    if not world then return types end
    local metaGrid = world:getMetaGrid()
    if not metaGrid then return types end

    local ok, zones = pcall(function()
        return metaGrid:getZonesAt(math.floor(x), math.floor(y), 0)
    end)
    if ok and zones then
        local okSize, zoneCount = pcall(function() return zones:size() end)
        if okSize and zoneCount then
            for i=0, zoneCount - 1 do brn_zoneListAdd(types, zones:get(i)) end
        elseif type(zones) == "table" then
            for _, zone in pairs(zones) do brn_zoneListAdd(types, zone) end
        end
    end

    ok, zones = pcall(function()
        return metaGrid:getZoneAt(math.floor(x), math.floor(y), 0)
    end)
    if ok and zones then brn_zoneListAdd(types, zones) end
    return types
end

function NPCRoadNavBridge.ScorePoint(x, y)
    local zoneTypes = NPCRoadNavBridge.GetZoneTypesAt(x, y)
    local score = -8
    local class = "unmarked"
    for _, zoneType in pairs(zoneTypes) do
        local z = brn_lower(zoneType)
        if brn_hasAny(z, BRN_BAD_ZONE_KEYWORDS) then return -1000, "blocked", zoneTypes end
        if brn_hasAny(z, BRN_ROAD_ZONE_KEYWORDS) then
            score = score + 125
            class = "road"
        elseif brn_hasAny(z, BRN_TOWN_ZONE_KEYWORDS) then
            score = score + 95
            if class ~= "road" then class = "town" end
        elseif brn_hasAny(z, BRN_SETTLEMENT_ZONE_KEYWORDS) then
            score = score + 35
            if class ~= "road" and class ~= "town" then class = "settlement" end
        end
    end
    return score, class, zoneTypes
end

function NPCRoadNavBridge.IsRoadPoint(x, y)
    local score, class = NPCRoadNavBridge.ScorePoint(x, y)
    return class == "road" and score >= NPCRoadNavBridge.Config.roadScore
end

function NPCRoadNavBridge.IsPreferredPoint(x, y)
    local score, class = NPCRoadNavBridge.ScorePoint(x, y)
    return score >= NPCRoadNavBridge.Config.preferredScore and class ~= "blocked"
end

function NPCRoadNavBridge.IsWildPoint(x, y)
    local score, class = NPCRoadNavBridge.ScorePoint(x, y)
    return score < NPCRoadNavBridge.Config.returnScore or class == "blocked" or class == "unmarked"
end

function NPCRoadNavBridge.IsSquareUsable(square, mover)
    if not square then return false end
    local ok, water = pcall(function()
        if IsoFlagType and IsoFlagType.water then return square:Is(IsoFlagType.water) end
        return false
    end)
    if ok and water then return false end
    local solid = false
    ok, solid = pcall(function() return square:isSolid() end)
    if ok and solid then return false end
    local solidTrans = false
    ok, solidTrans = pcall(function() return square:isSolidTrans() end)
    if ok and solidTrans then return false end
    return true
end

function NPCRoadNavBridge.FindLoadedPreferredAround(x, y, z, radius, roadOnly)
    local cell = getCell and getCell() or nil
    if not cell then return nil end
    local bx = math.floor(x)
    local by = math.floor(y)
    local bz = math.floor(z or 0)
    radius = radius or (roadOnly and NPCRoadNavBridge.Config.loadedRoadSearchRadius or NPCRoadNavBridge.Config.loadedTownSearchRadius)
    local best = nil
    local bestScore = -1000000
    for r=0, radius do
        for dx=-r, r do
            for dy=-r, r do
                if r == 0 or math.abs(dx) == r or math.abs(dy) == r then
                    local sx = bx + dx
                    local sy = by + dy
                    local square = cell:getGridSquare(sx, sy, bz)
                    if square and NPCRoadNavBridge.IsSquareUsable(square, nil) then
                        local score, class = NPCRoadNavBridge.ScorePoint(sx, sy)
                        local allowed = false
                        if roadOnly then
                            allowed = class == "road" and score >= NPCRoadNavBridge.Config.roadScore
                        else
                            allowed = score >= NPCRoadNavBridge.Config.preferredScore and class ~= "blocked"
                        end
                        if allowed then
                            local candidateScore = score - (r * 0.85) - (brn_dist2(x, y, sx, sy) * 0.015)
                            if candidateScore > bestScore then
                                bestScore = candidateScore
                                best = {x=sx, y=sy, z=bz, square=square, score=score, class=class}
                            end
                        end
                    end
                end
            end
        end
        if best and r >= 6 then return best end
    end
    return best
end

function NPCRoadNavBridge.FindLoadedRoadAround(x, y, z, radius)
    return NPCRoadNavBridge.FindLoadedPreferredAround(x, y, z, radius or NPCRoadNavBridge.Config.loadedRoadSearchRadius, true)
end

function NPCRoadNavBridge.FindLoadedTownOrRoadAround(x, y, z, radius)
    return NPCRoadNavBridge.FindLoadedPreferredAround(x, y, z, radius or NPCRoadNavBridge.Config.loadedTownSearchRadius, false)
end

function NPCRoadNavBridge.FindWorldRoadPoint(minX, minY, maxX, maxY, attempts, avoidPlayersRadius)
    attempts = attempts or 1400
    local best = nil
    local bestScore = -1000000
    for i=1, attempts do
        local x = minX + ZombRand(math.max(1, maxX - minX))
        local y = minY + ZombRand(math.max(1, maxY - minY))
        local tooClose = false
        local worldDirector = brn_worldDirector()
        if worldDirector and worldDirector.IsTooCloseToPlayer and avoidPlayersRadius then
            tooClose = worldDirector.IsTooCloseToPlayer(x, y, avoidPlayersRadius)
        end
        if not tooClose then
            local score, class = NPCRoadNavBridge.ScorePoint(x, y)
            if class == "road" and score > bestScore then
                bestScore = score
                best = {x=x, y=y, z=0, spawnClass="road", zoneScore=score}
            end
            if class == "road" and score >= NPCRoadNavBridge.Config.roadScore + 25 then
                return {x=x, y=y, z=0, spawnClass="road", zoneScore=score}
            end
        end
    end
    return best
end

function NPCRoadNavBridge.FindNearbyWorldRoadPoint(x, y, radius, attempts)
    radius = radius or 420
    attempts = attempts or 240
    local best = nil
    local bestScore = -1000000
    for i=1, attempts do
        local tx = x + ZombRand(-radius, radius + 1)
        local ty = y + ZombRand(-radius, radius + 1)
        local score, class = NPCRoadNavBridge.ScorePoint(tx, ty)
        if class == "road" then
            local candidateScore = score - (brn_dist2(x, y, tx, ty) * 0.0005)
            if candidateScore > bestScore then
                bestScore = candidateScore
                best = {x=tx, y=ty, z=0, spawnClass="road", zoneScore=score}
            end
            if score >= NPCRoadNavBridge.Config.roadScore + 20 then
                return {x=tx, y=ty, z=0, spawnClass="road", zoneScore=score}
            end
        end
    end
    return best
end


function NPCRoadNavBridge.FindNearbyWorldRoadStepToward(x, y, targetX, targetY, radius, attempts)
    radius = radius or NPCRoadNavBridge.Config.virtualStepRadius
    attempts = attempts or NPCRoadNavBridge.Config.virtualStepAttempts
    if not x or not y or not targetX or not targetY then return nil end

    local vx = targetX - x
    local vy = targetY - y
    local vlen = math.sqrt(vx * vx + vy * vy)
    if vlen < 1 then
        return NPCRoadNavBridge.FindNearbyWorldRoadPoint(x, y, radius, attempts)
    end
    vx = vx / vlen
    vy = vy / vlen

    local best = nil
    local bestScore = -1000000
    for i=1, attempts do
        local tx = x + ZombRand(-radius, radius + 1)
        local ty = y + ZombRand(-radius, radius + 1)
        local score, class = NPCRoadNavBridge.ScorePoint(tx, ty)
        if class == "road" then
            local dx = tx - x
            local dy = ty - y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist > 12 then
                local forward = ((dx / dist) * vx + (dy / dist) * vy) * 180
                local targetPull = -brn_dist2(tx, ty, targetX, targetY) * 0.0007
                local stepPenalty = -math.abs(dist - radius * 0.65) * 0.45
                local candidateScore = score + forward + targetPull + stepPenalty
                if candidateScore > bestScore then
                    bestScore = candidateScore
                    best = {x=tx, y=ty, z=0, spawnClass="road", zoneScore=score}
                end
            end
        end
    end
    return best
end

function NPCRoadNavBridge.FindLoadedRoadStepToward(fromX, fromY, z, targetX, targetY, radius)
    local cell = getCell and getCell() or nil
    if not cell or not fromX or not fromY or not targetX or not targetY then return nil end

    radius = radius or NPCRoadNavBridge.Config.chainSearchRadius
    local minStep = NPCRoadNavBridge.Config.chainStepMin or 9
    local maxStep = NPCRoadNavBridge.Config.chainStepMax or 18
    local idealStep = (minStep + maxStep) * 0.5
    local bx = math.floor(fromX)
    local by = math.floor(fromY)
    local bz = math.floor(z or 0)

    local vx = targetX - fromX
    local vy = targetY - fromY
    local vlen = math.sqrt(vx * vx + vy * vy)
    if vlen < 1 then return nil end
    vx = vx / vlen
    vy = vy / vlen

    local best = nil
    local bestScore = -1000000
    for dx=-radius, radius do
        for dy=-radius, radius do
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist >= minStep and dist <= maxStep then
                local sx = bx + dx
                local sy = by + dy
                local sq = cell:getGridSquare(sx, sy, bz)
                if sq and NPCRoadNavBridge.IsSquareUsable(sq, nil) then
                    local score, class = NPCRoadNavBridge.ScorePoint(sx, sy)
                    if class == "road" and score >= NPCRoadNavBridge.Config.roadScore then
                        local forward = ((dx / dist) * vx + (dy / dist) * vy) * 160
                        local sidePenalty = math.abs((dx / dist) * (-vy) + (dy / dist) * vx) * 20
                        local targetPull = -brn_dist2(sx, sy, targetX, targetY) * 0.018
                        local stepPenalty = -math.abs(dist - idealStep) * 2.5
                        local candidateScore = score + forward + targetPull + stepPenalty - sidePenalty
                        if candidateScore > bestScore then
                            bestScore = candidateScore
                            best = {x=sx, y=sy, z=bz, square=sq, score=score, class=class}
                        end
                    end
                end
            end
        end
    end

    return best
end

function NPCRoadNavBridge.GetChainedMoveTarget(bandit, brain, state, reason, x, y, z)
    if not bandit or not brain or not x or not y then return x, y, z, false end
    if brain.master and not brain.roadPatrol then return x, y, z, false end
    if not (brain.roadPatrol or brain.roadBias or brain.preferRoads) then return x, y, z, false end

    z = z or bandit:getZ()
    local bx = bandit:getX()
    local by = bandit:getY()
    local distToFinal = brn_dist(bx, by, x, y)
    local maxStep = NPCRoadNavBridge.Config.chainStepMax or 18
    if distToFinal <= maxStep + 3 then return x, y, z, false end

    local roadState = state == "PatrolArea" or state == "RecoverPath" or state == "Regroup" or state == "ReturnToBase"
    local shouldChain = brain.roadPatrol == true
    if not shouldChain and roadState then
        shouldChain = distToFinal > 36 or NPCRoadNavBridge.IsWildPoint(bx, by) or NPCRoadNavBridge.IsWildPoint(x, y)
    end
    if not shouldChain then return x, y, z, false end

    brain.fsm = brain.fsm or {}
    local chain = brain.fsm.roadChain or {}
    local now = brn_worldAgeHours()
    local finalChanged = not chain.finalX or brn_dist2(chain.finalX, chain.finalY, x, y) > 64
    local reachedStep = not chain.x or brn_dist2(bx, by, chain.x, chain.y) < 7
    local expired = chain.expire and now > chain.expire

    if not finalChanged and not reachedStep and not expired and chain.x and chain.y then
        return chain.x, chain.y, chain.z or z, true, chain.finalX, chain.finalY, chain.finalZ or z
    end

    local anchor = NPCRoadNavBridge.FindLoadedRoadAround(bx, by, z, 18)
    local fromX = anchor and anchor.x or bx
    local fromY = anchor and anchor.y or by
    local step = NPCRoadNavBridge.FindLoadedRoadStepToward(fromX, fromY, z, x, y, NPCRoadNavBridge.Config.chainSearchRadius)

    if not step and brain.roadPatrol then
        step = NPCRoadNavBridge.FindLoadedRoadAround(bx, by, z, NPCRoadNavBridge.Config.returnToRoadRadius)
    elseif not step then
        step = NPCRoadNavBridge.FindLoadedTownOrRoadAround(bx, by, z, NPCRoadNavBridge.Config.returnToRoadRadius)
    end

    if not step then return x, y, z, false end

    brain.fsm.roadChain = {
        finalX = x,
        finalY = y,
        finalZ = z,
        x = step.x,
        y = step.y,
        z = step.z or z,
        expire = now + (NPCRoadNavBridge.Config.chainExpireHours or 0.035),
        state = state,
        reason = reason,
        roadPatrol = brain.roadPatrol or false
    }

    return step.x, step.y, step.z or z, true, x, y, z
end

function NPCRoadNavBridge.FindPatrolPoint(bandit, brain, radius)
    if not bandit then return nil end
    radius = radius or NPCRoadNavBridge.Config.patrolRadius
    brain = brain or {}
    brain.fsm = brain.fsm or {}
    brain.fsm.roadPatrol = brain.fsm.roadPatrol or {}
    local px = bandit:getX()
    local py = bandit:getY()
    local pz = bandit:getZ()
    local road = NPCRoadNavBridge.FindLoadedRoadAround(px, py, pz, NPCRoadNavBridge.Config.returnToRoadRadius)
    if not road then return NPCRoadNavBridge.FindLoadedTownOrRoadAround(px, py, pz, NPCRoadNavBridge.Config.returnToRoadRadius) end
    local dir = brain.fsm.roadPatrol.dir
    if not dir or ZombRand(8) == 0 then
        local dirs = {{x=1,y=0},{x=-1,y=0},{x=0,y=1},{x=0,y=-1},{x=1,y=1},{x=-1,y=1},{x=1,y=-1},{x=-1,y=-1}}
        dir = dirs[1 + ZombRand(#dirs)]
        brain.fsm.roadPatrol.dir = dir
    end
    local best = nil
    local bestScore = -1000000
    local cell = getCell and getCell() or nil
    if not cell then return road end
    local bx = math.floor(road.x)
    local by = math.floor(road.y)
    local bz = math.floor(road.z or pz)
    for r=8, radius do
        for dx=-r, r do
            for dy=-r, r do
                if math.abs(dx) == r or math.abs(dy) == r then
                    local sx = bx + dx
                    local sy = by + dy
                    local sq = cell:getGridSquare(sx, sy, bz)
                    if sq and NPCRoadNavBridge.IsSquareUsable(sq, nil) then
                        local score, class = NPCRoadNavBridge.ScorePoint(sx, sy)
                        if class == "road" and score >= NPCRoadNavBridge.Config.roadScore then
                            local len = math.sqrt(dx * dx + dy * dy)
                            if len < 1 then len = 1 end
                            local forward = ((dx / len) * dir.x + (dy / len) * dir.y) * 80
                            local candidateScore = score + forward - math.abs(len - radius * 0.65)
                            if candidateScore > bestScore then
                                bestScore = candidateScore
                                best = {x=sx, y=sy, z=bz, square=sq, score=score, class=class}
                            end
                        end
                    end
                end
            end
        end
    end
    return best or road
end

function NPCRoadNavBridge.ShouldReturnToRoad(bandit, brain)
    if not bandit then return false end
    if brain and brain.roadPatrol then return true end
    if brain and brain.master then return false end

    local score, class = NPCRoadNavBridge.ScorePoint(bandit:getX(), bandit:getY())
    if class == "blocked" then return true end
    if score < NPCRoadNavBridge.Config.returnScore then return true end
    return false
end

function NPCRoadNavBridge.AdjustMoveTarget(bandit, brain, state, reason, x, y, z)
    if not bandit or not x or not y then return x, y, z, false end
    z = z or bandit:getZ()
    brain = brain or {}
    if brain.master and not brain.roadPatrol then return x, y, z, false end
    if brain.roadPatrol then
        local road = NPCRoadNavBridge.FindLoadedRoadAround(x, y, z, NPCRoadNavBridge.Config.loadedRoadSearchRadius)
            or NPCRoadNavBridge.FindPatrolPoint(bandit, brain, NPCRoadNavBridge.Config.patrolRadius)
        if road then return road.x, road.y, road.z or z, true end
        return x, y, z, false
    end
    local roadState = state == "PatrolArea" or state == "RecoverPath" or state == "Regroup" or state == "ReturnToBase"
    if roadState and (brain.roadBias or brain.preferRoads or state == "PatrolArea") and NPCRoadNavBridge.IsWildPoint(x, y) then
        local preferred = NPCRoadNavBridge.FindLoadedTownOrRoadAround(x, y, z, NPCRoadNavBridge.Config.loadedTownSearchRadius)
            or NPCRoadNavBridge.FindLoadedTownOrRoadAround(bandit:getX(), bandit:getY(), z, NPCRoadNavBridge.Config.returnToRoadRadius)
        if preferred then return preferred.x, preferred.y, preferred.z or z, true end
    end
    return x, y, z, false
end

function NPCRoadNavBridge.AdjustTaskTarget(bandit, brain, task)
    if not task or (task.action ~= "Move" and task.action ~= "GoTo") then return task end
    local x, y, z, changed = NPCRoadNavBridge.AdjustMoveTarget(bandit, brain, task.directorState, task.directorReason, task.x, task.y, task.z)
    if changed then
        task.originalRoadX = task.originalRoadX or task.x
        task.originalRoadY = task.originalRoadY or task.y
        task.originalRoadZ = task.originalRoadZ or task.z
        task.x = x
        task.y = y
        task.z = z
        task.roadAdjusted = true
    end
    return task
end
