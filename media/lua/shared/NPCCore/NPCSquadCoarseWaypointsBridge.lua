-- NPCSquadCoarseWaypointsBridge.lua
-- Bounded squad-level coarse waypoint layer for movement tasks.
-- It keeps far movement from asking every NPC to solve the same long path at once.

local legacySquadCoarseWaypoints = NPCSquadCoarseWaypointsBridge
NPCSquadCoarseWaypointsBridge = NPCSquadCoarseWaypointsBridge or legacySquadCoarseWaypoints or {}

NPCSquadCoarseWaypointsBridge.VERSION = "2026-06-10-stage448-route-templates-2"

NPCSquadCoarseWaypointsBridge.Config = NPCSquadCoarseWaypointsBridge.Config or {
    enabled = true,
    minDistance = 18,
    stepDistance = 12,
    searchRadius = 5,
    cacheMs = 2200,
    maxCacheRecords = 240,
    bucketSize = 10,
    maxSegmentsPerTask = 10,
    arriveDist = 1.35,
    formationSpread = 1.25,
    roadBias = true,
    routeTemplatesEnabled = true,
    routeTemplateMs = 18000,
    routeTemplateMaxRecords = 180,
    routeTemplateVariants = 4,
    routeTemplateMinDistance = 28,
    routeTemplateRejoinRadius = 18,
    routeTemplateLateralStep = 7,
    debug = false
}

NPCSquadCoarseWaypointsBridge.Cache = NPCSquadCoarseWaypointsBridge.Cache or {}
NPCSquadCoarseWaypointsBridge.RouteTemplates = NPCSquadCoarseWaypointsBridge.RouteTemplates or {}
NPCSquadCoarseWaypointsBridge.Stats = NPCSquadCoarseWaypointsBridge.Stats or {
    resolved = 0,
    continued = 0,
    cacheHit = 0,
    cacheMiss = 0,
    failed = 0,
    pruned = 0,
    routeTemplateHit = 0,
    routeTemplateMiss = 0,
    routeTemplateRejoin = 0
}

local function scw_now()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then return math.floor(getGameTime():getWorldAgeHours() * 3600000) end
    return 0
end

local function scw_num(key, default, minValue, maxValue)
    local value = default
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        local ok, ret = pcall(function()
            return NPCLegacySettingsBridge.GetNumber(key, default, minValue, maxValue)
        end)
        if ok then value = ret end
    end
    value = tonumber(value) or default
    if minValue and value < minValue then value = minValue end
    if maxValue and value > maxValue then value = maxValue end
    return value
end

local function scw_bool(key, default)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        local ok, ret = pcall(function()
            return NPCLegacySettingsBridge.GetBool(key, default == true)
        end)
        if ok then return ret == true end
    end
    return default == true
end

function NPCSquadCoarseWaypointsBridge.ApplySettings()
    local c = NPCSquadCoarseWaypointsBridge.Config
    c.enabled = scw_bool("SquadNav_Enabled", c.enabled ~= false)
    c.minDistance = scw_num("SquadNav_MinDistance", c.minDistance or 18, 6, 80)
    c.stepDistance = scw_num("SquadNav_StepDistance", c.stepDistance or 12, 4, 60)
    c.searchRadius = scw_num("SquadNav_SearchRadius", c.searchRadius or 5, 1, 16)
    c.cacheMs = scw_num("SquadNav_CacheMs", c.cacheMs or 2200, 250, 30000)
    c.maxCacheRecords = scw_num("SquadNav_MaxCacheRecords", c.maxCacheRecords or 240, 16, 2000)
    c.bucketSize = scw_num("SquadNav_BucketSize", c.bucketSize or 10, 4, 64)
    c.maxSegmentsPerTask = scw_num("SquadNav_MaxSegmentsPerTask", c.maxSegmentsPerTask or 10, 2, 48)
    c.arriveDist = scw_num("SquadNav_ArriveDist", c.arriveDist or 1.35, 0.7, 4.0)
    c.formationSpread = scw_num("SquadNav_FormationSpread", c.formationSpread or 1.25, 0, 5.0)
    c.roadBias = scw_bool("SquadNav_RoadBias", c.roadBias ~= false)
    c.routeTemplatesEnabled = scw_bool("SquadNav_RouteTemplatesEnabled", c.routeTemplatesEnabled ~= false)
    c.routeTemplateMs = scw_num("SquadNav_RouteTemplateMs", c.routeTemplateMs or 18000, 1000, 180000)
    c.routeTemplateMaxRecords = scw_num("SquadNav_RouteTemplateMaxRecords", c.routeTemplateMaxRecords or 180, 16, 2000)
    c.routeTemplateVariants = scw_num("SquadNav_RouteTemplateVariants", c.routeTemplateVariants or 4, 1, 8)
    c.routeTemplateMinDistance = scw_num("SquadNav_RouteTemplateMinDistance", c.routeTemplateMinDistance or 28, 8, 180)
    c.routeTemplateRejoinRadius = scw_num("SquadNav_RouteTemplateRejoinRadius", c.routeTemplateRejoinRadius or 18, 3, 80)
    c.routeTemplateLateralStep = scw_num("SquadNav_RouteTemplateLateralStep", c.routeTemplateLateralStep or 7, 2, 40)
    c.debug = scw_bool("SquadNav_Debug", c.debug == true)
end

local function scw_dist2(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return dx * dx + dy * dy
end

local function scw_dist(x1, y1, x2, y2)
    return math.sqrt(scw_dist2(x1, y1, x2, y2))
end

local function scw_key3(x, y, z)
    return tostring(math.floor(tonumber(x) or 0)) .. ":" .. tostring(math.floor(tonumber(y) or 0)) .. ":" .. tostring(math.floor(tonumber(z) or 0))
end

local function scw_bucket(value)
    local bucket = tonumber(NPCSquadCoarseWaypointsBridge.Config.bucketSize) or 10
    if bucket < 1 then bucket = 1 end
    return math.floor((tonumber(value) or 0) / bucket)
end

local function scw_getBrain(zombie)
    if not zombie or not NPCBrainData or not NPCBrainData.Get then return nil end
    local ok, brain = pcall(function()
        return NPCBrainData.Get(zombie)
    end)
    if ok then return brain end
    return nil
end

local function scw_getId(zombie, brain)
    if brain then
        if brain.uid then return tostring(brain.uid) end
        if brain.id then return tostring(brain.id) end
        if brain.persistentId then return tostring(brain.persistentId) end
    end
    if zombie and NPCUtils and NPCUtils.GetCharacterID then
        local ok, id = pcall(function()
            return NPCUtils.GetCharacterID(zombie)
        end)
        if ok and id then return tostring(id) end
    end
    if zombie and NPCUtils and NPCUtils.GetZombieID then
        local ok, id = pcall(function()
            return NPCUtils.GetZombieID(zombie)
        end)
        if ok and id then return tostring(id) end
    end
    return tostring(zombie or "npc")
end

local function scw_hashId(value)
    value = tostring(value or "0")
    local n = tonumber(value)
    if n then return math.floor(n) end
    local h = 0
    for i = 1, string.len(value) do
        h = (h * 31 + string.byte(value, i)) % 1000003
    end
    return h
end

local function scw_groupId(brain)
    if not brain then return nil end
    return brain.worldGroupId
        or brain.groupId
        or brain.squadId
        or brain.mercenaryGroupId
        or brain.baseGroupId
        or brain.homeBaseId
        or brain.baseId
end

local function scw_taskAllowed(task)
    if not task or (task.action ~= "Move" and task.action ~= "GoTo") then return false end
    if task.vehiclePartArea then return false end
    if task.portalWait then return false end
    if task.navPerfRepair then return false end
    if task.recoveryTarget and not task._scw then return false end
    if task.disableCoarseWaypoint or task.noCoarseWaypoint then return false end
    if not task.x or not task.y then return false end
    return true
end

local function scw_getSquare(x, y, z)
    if NPCMovementStabilityBridge and NPCMovementStabilityBridge.GetSquare then
        return NPCMovementStabilityBridge.GetSquare(x, y, z)
    end
    local cell = getCell and getCell() or nil
    if not cell then return nil end
    return cell:getGridSquare(math.floor(x), math.floor(y), math.floor(z or 0))
end

local function scw_squareBlocked(square, mover)
    if not square then return true end
    if NPCMovementStabilityBridge and NPCMovementStabilityBridge.IsSquareBlocked then
        local ok, blocked = pcall(function()
            return NPCMovementStabilityBridge.IsSquareBlocked(square, mover)
        end)
        if ok then return blocked == true end
    end
    local ok, solid = pcall(function() return square:isSolid() end)
    if ok and solid then return true end
    ok, solid = pcall(function() return square:isSolidTrans() end)
    if ok and solid then return true end
    return false
end

local function scw_navCost(zombie, brain, square, finalX, finalY)
    if not NPCNavigationPerformanceBridge or not NPCNavigationPerformanceBridge.GetSquareCost then return 0 end
    local ok, cost = pcall(function()
        return NPCNavigationPerformanceBridge.GetSquareCost(zombie, brain, square, finalX, finalY, "squad coarse waypoint")
    end)
    if ok and cost then return tonumber(cost) or 0 end
    return 0
end

local function scw_roadBonus(square)
    if not NPCSquadCoarseWaypointsBridge.Config.roadBias then return 0 end
    if not square or not NPCRoadNavBridge or not NPCRoadNavBridge.ScorePoint then return 0 end
    local ok, score, class = pcall(function()
        return NPCRoadNavBridge.ScorePoint(square:getX(), square:getY())
    end)
    if not ok or not score then return 0 end
    if class == "road" then return math.min(8, math.max(0, score / 18)) end
    if class == "town" then return math.min(4, math.max(0, score / 35)) end
    if class == "blocked" then return -100 end
    return 0
end

local function scw_cacheKey(zombie, brain, finalX, finalY, finalZ)
    local group = scw_groupId(brain)
    if not group then return nil end
    return tostring(group)
        .. ":" .. tostring(math.floor(tonumber(finalZ) or 0))
        .. ":" .. tostring(scw_bucket(zombie:getX()))
        .. ":" .. tostring(scw_bucket(zombie:getY()))
        .. ":" .. tostring(scw_bucket(finalX))
        .. ":" .. tostring(scw_bucket(finalY))
end

local function scw_pruneCache(now)
    local cache = NPCSquadCoarseWaypointsBridge.Cache
    local maxRecords = tonumber(NPCSquadCoarseWaypointsBridge.Config.maxCacheRecords) or 240
    local count = 0
    local oldestKey = nil
    local oldestAt = math.huge

    for key, entry in pairs(cache) do
        if not entry or now > (entry.untilMs or 0) then
            cache[key] = nil
            NPCSquadCoarseWaypointsBridge.Stats.pruned = (NPCSquadCoarseWaypointsBridge.Stats.pruned or 0) + 1
        else
            count = count + 1
            if (entry.createdAt or 0) < oldestAt then
                oldestAt = entry.createdAt or 0
                oldestKey = key
            end
        end
    end

    if count >= maxRecords and oldestKey then
        cache[oldestKey] = nil
        NPCSquadCoarseWaypointsBridge.Stats.pruned = (NPCSquadCoarseWaypointsBridge.Stats.pruned or 0) + 1
    end
end

local function scw_cachedSquare(key, zombie)
    if not key then return nil end
    local now = scw_now()
    local entry = NPCSquadCoarseWaypointsBridge.Cache[key]
    if not entry then return nil end
    if now > (entry.untilMs or 0) then
        NPCSquadCoarseWaypointsBridge.Cache[key] = nil
        return nil
    end

    local square = scw_getSquare(entry.x, entry.y, entry.z)
    if square and not scw_squareBlocked(square, zombie) then
        NPCSquadCoarseWaypointsBridge.Stats.cacheHit = (NPCSquadCoarseWaypointsBridge.Stats.cacheHit or 0) + 1
        return square
    end

    NPCSquadCoarseWaypointsBridge.Cache[key] = nil
    return nil
end

local function scw_storeCache(key, square)
    if not key or not square then return end
    local now = scw_now()
    scw_pruneCache(now)
    NPCSquadCoarseWaypointsBridge.Cache[key] = {
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
        createdAt = now,
        untilMs = now + (tonumber(NPCSquadCoarseWaypointsBridge.Config.cacheMs) or 2200)
    }
end

local function scw_findLoadedSquare(zombie, brain, desiredX, desiredY, z, finalX, finalY)
    local cell = getCell and getCell() or nil
    if not cell then return nil end

    local bx = math.floor(desiredX)
    local by = math.floor(desiredY)
    local bz = math.floor(z or 0)
    local radius = tonumber(NPCSquadCoarseWaypointsBridge.Config.searchRadius) or 5
    local best = nil
    local bestScore = math.huge

    for r = 0, radius do
        for dx = -r, r do
            for dy = -r, r do
                if r == 0 or math.abs(dx) == r or math.abs(dy) == r then
                    local square = cell:getGridSquare(bx + dx, by + dy, bz)
                    if square and not scw_squareBlocked(square, zombie) then
                        local sx = square:getX() + 0.5
                        local sy = square:getY() + 0.5
                        local score = scw_dist2(sx, sy, desiredX, desiredY) * 1.25
                            + scw_dist2(sx, sy, finalX, finalY) * 0.02
                            + scw_navCost(zombie, brain, square, finalX, finalY)
                            - scw_roadBonus(square)
                        if score < bestScore then
                            bestScore = score
                            best = square
                        end
                    end
                end
            end
        end
        if best and r >= 2 then return best end
    end

    return best
end

local function scw_offsetSquare(zombie, brain, square, finalX, finalY)
    if not square then return nil end

    local group = scw_groupId(brain)
    local spread = tonumber(NPCSquadCoarseWaypointsBridge.Config.formationSpread) or 0
    if not group or spread <= 0.1 then return square end

    local id = scw_hashId(scw_getId(zombie, brain))
    local ring = id % 8
    local offsets = {
        {0, 0},
        {1, 0}, {-1, 0}, {0, 1}, {0, -1},
        {1, 1}, {-1, 1}, {1, -1}, {-1, -1},
        {2, 0}, {-2, 0}, {0, 2}, {0, -2}
    }
    local rotated = {}
    for i = 1, #offsets do
        rotated[#rotated + 1] = offsets[((i + ring - 1) % #offsets) + 1]
    end

    local best = square
    local bestScore = scw_navCost(zombie, brain, square, finalX, finalY)
    for _, off in ipairs(rotated) do
        local ox = math.floor(off[1] * spread + 0.5)
        local oy = math.floor(off[2] * spread + 0.5)
        local candidate = scw_getSquare(square:getX() + ox, square:getY() + oy, square:getZ())
        if candidate and not scw_squareBlocked(candidate, zombie) then
            local score = scw_navCost(zombie, brain, candidate, finalX, finalY)
                + scw_dist2(candidate:getX(), candidate:getY(), square:getX(), square:getY()) * 0.2
                + scw_dist2(candidate:getX(), candidate:getY(), finalX, finalY) * 0.01
            if score < bestScore then
                bestScore = score
                best = candidate
            end
        end
    end

    return best
end


local function scw_templateKey(zombie, brain, finalX, finalY, finalZ)
    local group = scw_groupId(brain)
    if not group or not zombie then return nil end
    local bucket = math.max(tonumber(NPCSquadCoarseWaypointsBridge.Config.bucketSize) or 10, 12)
    local function b(v) return math.floor((tonumber(v) or 0) / bucket) end
    return tostring(group) .. ":" .. tostring(math.floor(tonumber(finalZ) or 0))
        .. ":" .. tostring(b(zombie:getX())) .. ":" .. tostring(b(zombie:getY()))
        .. ":" .. tostring(b(finalX)) .. ":" .. tostring(b(finalY))
end

local function scw_pruneRouteTemplates(now)
    local cache = NPCSquadCoarseWaypointsBridge.RouteTemplates or {}
    local maxRecords = tonumber(NPCSquadCoarseWaypointsBridge.Config.routeTemplateMaxRecords) or 180
    local count = 0
    local oldestKey = nil
    local oldest = math.huge
    for key, entry in pairs(cache) do
        if not entry or now > (tonumber(entry.untilMs) or 0) then
            cache[key] = nil
        else
            count = count + 1
            if (tonumber(entry.createdAt) or 0) < oldest then
                oldest = tonumber(entry.createdAt) or 0
                oldestKey = key
            end
        end
    end
    if count >= maxRecords and oldestKey then cache[oldestKey] = nil end
end

local function scw_storeRouteTemplate(key, template)
    if not key or not template or not template.points or #template.points == 0 then return end
    local now = scw_now()
    scw_pruneRouteTemplates(now)
    template.createdAt = now
    template.untilMs = now + (tonumber(NPCSquadCoarseWaypointsBridge.Config.routeTemplateMs) or 18000)
    NPCSquadCoarseWaypointsBridge.RouteTemplates[key] = template
end

local function scw_getRouteTemplate(key)
    if not key then return nil end
    local now = scw_now()
    local entry = NPCSquadCoarseWaypointsBridge.RouteTemplates[key]
    if not entry then return nil end
    if now > (tonumber(entry.untilMs) or 0) then
        NPCSquadCoarseWaypointsBridge.RouteTemplates[key] = nil
        return nil
    end
    return entry
end

local function scw_templateOffsets()
    local lateral = tonumber(NPCSquadCoarseWaypointsBridge.Config.routeTemplateLateralStep) or 7
    local variants = math.max(1, math.floor(tonumber(NPCSquadCoarseWaypointsBridge.Config.routeTemplateVariants) or 4))
    local raw = {0, lateral, -lateral, lateral * 2, -lateral * 2, math.floor(lateral * 0.5), -math.floor(lateral * 0.5), lateral * 3}
    local out = {}
    for i = 1, math.min(variants, #raw) do out[#out + 1] = raw[i] end
    return out
end

local function scw_generateRouteTemplate(zombie, brain, finalX, finalY, finalZ)
    if not zombie or not finalX or not finalY then return nil end
    local zx = zombie:getX()
    local zy = zombie:getY()
    local dist = scw_dist(zx, zy, finalX, finalY)
    if dist < (tonumber(NPCSquadCoarseWaypointsBridge.Config.routeTemplateMinDistance) or 28) then return nil end
    local step = tonumber(NPCSquadCoarseWaypointsBridge.Config.stepDistance) or 12
    local maxSegments = tonumber(NPCSquadCoarseWaypointsBridge.Config.maxSegmentsPerTask) or 10
    local segmentCount = math.max(2, math.min(maxSegments, math.ceil(dist / math.max(4, step))))
    local vx = (finalX - zx) / math.max(0.001, dist)
    local vy = (finalY - zy) / math.max(0.001, dist)
    local nx = -vy
    local ny = vx

    local bestTemplate = nil
    local bestScore = math.huge
    for _, lateral in ipairs(scw_templateOffsets()) do
        local points = {}
        local score = math.abs(lateral) * 0.08
        for i = 1, segmentCount - 1 do
            local t = i / segmentCount
            local bend = math.sin(t * math.pi) * lateral
            local desiredX = zx + (finalX - zx) * t + nx * bend
            local desiredY = zy + (finalY - zy) * t + ny * bend
            local square = scw_findLoadedSquare(zombie, brain, desiredX, desiredY, finalZ, finalX, finalY)
            if square then
                points[#points + 1] = {x=square:getX(), y=square:getY(), z=square:getZ()}
                score = score + scw_navCost(zombie, brain, square, finalX, finalY) + scw_dist2(square:getX(), square:getY(), desiredX, desiredY) * 0.15
            else
                score = score + 9999
            end
        end
        if #points > 0 and score < bestScore then
            bestScore = score
            bestTemplate = {points=points, lateral=lateral, score=score, finalX=finalX, finalY=finalY, finalZ=finalZ}
        end
    end
    return bestTemplate
end

local function scw_selectRouteTemplateSquare(zombie, brain, task, finalX, finalY, finalZ)
    if not NPCSquadCoarseWaypointsBridge.Config.routeTemplatesEnabled then return nil end
    if not zombie or not task then return nil end
    local dist = scw_dist(zombie:getX(), zombie:getY(), finalX, finalY)
    if dist < (tonumber(NPCSquadCoarseWaypointsBridge.Config.routeTemplateMinDistance) or 28) then return nil end

    local key = scw_templateKey(zombie, brain, finalX, finalY, finalZ)
    if not key then return nil end
    local template = scw_getRouteTemplate(key)
    if not template then
        template = scw_generateRouteTemplate(zombie, brain, finalX, finalY, finalZ)
        if template then
            scw_storeRouteTemplate(key, template)
            NPCSquadCoarseWaypointsBridge.Stats.routeTemplateMiss = (NPCSquadCoarseWaypointsBridge.Stats.routeTemplateMiss or 0) + 1
        end
    else
        NPCSquadCoarseWaypointsBridge.Stats.routeTemplateHit = (NPCSquadCoarseWaypointsBridge.Stats.routeTemplateHit or 0) + 1
    end
    if not template or not template.points or #template.points == 0 then return nil end

    local scw = task._scw or {}
    local startIndex = math.max(1, tonumber(scw.routeTemplateIndex) or 1)
    local rejoinRadius = tonumber(NPCSquadCoarseWaypointsBridge.Config.routeTemplateRejoinRadius) or 18
    local rejoinR2 = rejoinRadius * rejoinRadius
    local bestIndex = nil
    local bestScore = math.huge
    for i = startIndex, #template.points do
        local pt = template.points[i]
        local square = pt and scw_getSquare(pt.x, pt.y, pt.z)
        if square and not scw_squareBlocked(square, zombie) then
            local d2 = scw_dist2(zombie:getX(), zombie:getY(), pt.x, pt.y)
            local score = d2 + (i - startIndex) * 18 + scw_dist2(pt.x, pt.y, finalX, finalY) * 0.015
            if d2 <= rejoinR2 and score < bestScore then
                bestIndex = i
                bestScore = score
            elseif not bestIndex and i == startIndex then
                bestIndex = i
                bestScore = score + 500
            end
        end
    end
    if not bestIndex then return nil end
    local pt = template.points[bestIndex]
    local square = scw_getSquare(pt.x, pt.y, pt.z)
    if not square or scw_squareBlocked(square, zombie) then return nil end

    task._scw = scw
    task._scw.routeTemplateKey = key
    task._scw.routeTemplateIndex = math.min(#template.points + 1, bestIndex + 1)
    task._scw.routeTemplateScore = template.score
    NPCSquadCoarseWaypointsBridge.Stats.routeTemplateRejoin = (NPCSquadCoarseWaypointsBridge.Stats.routeTemplateRejoin or 0) + 1
    return scw_offsetSquare(zombie, brain, square, finalX, finalY)
end

local function scw_findSegmentSquare(zombie, brain, finalX, finalY, finalZ, task)
    local zx = zombie:getX()
    local zy = zombie:getY()
    local dist = scw_dist(zx, zy, finalX, finalY)
    if dist <= (tonumber(NPCSquadCoarseWaypointsBridge.Config.minDistance) or 18) then return nil end

    local templated = scw_selectRouteTemplateSquare(zombie, brain, task, finalX, finalY, finalZ)
    if templated then return templated end

    local step = tonumber(NPCSquadCoarseWaypointsBridge.Config.stepDistance) or 12
    if step >= dist - 2 then step = math.max(4, dist - 2) end
    local vx = (finalX - zx) / math.max(0.001, dist)
    local vy = (finalY - zy) / math.max(0.001, dist)
    local desiredX = zx + vx * step
    local desiredY = zy + vy * step

    local key = scw_cacheKey(zombie, brain, finalX, finalY, finalZ)
    local cached = scw_cachedSquare(key, zombie)
    if cached then return scw_offsetSquare(zombie, brain, cached, finalX, finalY) end

    NPCSquadCoarseWaypointsBridge.Stats.cacheMiss = (NPCSquadCoarseWaypointsBridge.Stats.cacheMiss or 0) + 1
    local square = scw_findLoadedSquare(zombie, brain, desiredX, desiredY, finalZ, finalX, finalY)
    if square then
        scw_storeCache(key, square)
        return scw_offsetSquare(zombie, brain, square, finalX, finalY)
    end

    return nil
end

function NPCSquadCoarseWaypointsBridge.ResolveMoveTarget(zombie, brain, task)
    if not NPCSquadCoarseWaypointsBridge.Config.enabled then return false end
    if not zombie or not scw_taskAllowed(task) then return false end

    brain = brain or scw_getBrain(zombie)
    local scw = task._scw
    local finalX = scw and scw.finalX or tonumber(task.x)
    local finalY = scw and scw.finalY or tonumber(task.y)
    local finalZ = scw and scw.finalZ or tonumber(task.z or zombie:getZ())
    if not finalX or not finalY then return false end

    local finalDist = scw_dist(zombie:getX(), zombie:getY(), finalX, finalY)
    if zombie:getZ() == finalZ and finalDist <= (tonumber(NPCSquadCoarseWaypointsBridge.Config.minDistance) or 18) then
        return false
    end

    scw = scw or {
        finalX = finalX,
        finalY = finalY,
        finalZ = finalZ,
        originalWalkType = task.walkType,
        originalArriveDist = task.arriveDist,
        startedAt = scw_now(),
        segments = 0
    }

    if (scw.segments or 0) >= (tonumber(NPCSquadCoarseWaypointsBridge.Config.maxSegmentsPerTask) or 10) then
        task.x = finalX
        task.y = finalY
        task.z = finalZ
        task._scw = nil
        task.coarseWaypoint = nil
        return false
    end

    local square = scw_findSegmentSquare(zombie, brain, finalX, finalY, finalZ, task)
    if not square then
        NPCSquadCoarseWaypointsBridge.Stats.failed = (NPCSquadCoarseWaypointsBridge.Stats.failed or 0) + 1
        return false
    end

    scw.segments = (scw.segments or 0) + 1
    scw.lastSegmentAt = scw_now()
    scw.lastX = square:getX()
    scw.lastY = square:getY()
    scw.lastZ = square:getZ()
    task._scw = scw

    task.x = square:getX()
    task.y = square:getY()
    task.z = square:getZ()
    task.coarseWaypoint = true
    task.coarseFinalX = finalX
    task.coarseFinalY = finalY
    task.coarseFinalZ = finalZ
    task.adjustedTarget = true
    task.resolvedMoveTarget = true
    task.arriveDist = math.max(tonumber(task.arriveDist) or 0.9, tonumber(NPCSquadCoarseWaypointsBridge.Config.arriveDist) or 1.35)
    if task.walkType == "Run" and finalDist < ((tonumber(NPCSquadCoarseWaypointsBridge.Config.stepDistance) or 12) * 1.2) then
        task.walkType = "Walk"
    end
    task.time = math.max(tonumber(task.time) or 1000, 900)

    if brain then
        brain.ai = brain.ai or {}
        brain.ai.squadNav = brain.ai.squadNav or {}
        brain.ai.squadNav.active = true
        brain.ai.squadNav.finalX = finalX
        brain.ai.squadNav.finalY = finalY
        brain.ai.squadNav.finalZ = finalZ
        brain.ai.squadNav.segmentX = task.x
        brain.ai.squadNav.segmentY = task.y
        brain.ai.squadNav.segmentZ = task.z
        brain.ai.squadNav.segments = scw.segments
    end

    NPCSquadCoarseWaypointsBridge.Stats.resolved = (NPCSquadCoarseWaypointsBridge.Stats.resolved or 0) + 1
    return true
end

function NPCSquadCoarseWaypointsBridge.ContinueMoveTask(zombie, task)
    if not NPCSquadCoarseWaypointsBridge.Config.enabled then return false end
    if not zombie or not task or not task._scw then return false end

    local scw = task._scw
    local finalX = tonumber(scw.finalX)
    local finalY = tonumber(scw.finalY)
    local finalZ = tonumber(scw.finalZ or zombie:getZ())
    if not finalX or not finalY then return false end

    local arrive = tonumber(scw.originalArriveDist or task.arriveDist or NPCSquadCoarseWaypointsBridge.Config.arriveDist) or 1.35
    if zombie:getZ() == finalZ and scw_dist2(zombie:getX(), zombie:getY(), finalX, finalY) <= arrive * arrive then
        task._scw = nil
        task.coarseWaypoint = nil
        return false
    end

    if (scw.segments or 0) >= (tonumber(NPCSquadCoarseWaypointsBridge.Config.maxSegmentsPerTask) or 10) then
        task.x = finalX
        task.y = finalY
        task.z = finalZ
        task._scw = nil
        task.coarseWaypoint = nil
        task.disableCoarseWaypoint = true
        task.state = "NEW"
        task.time = math.max(tonumber(task.time) or 1000, 1000)
        task.arriveDist = scw.originalArriveDist or task.arriveDist
        task.walkType = scw.originalWalkType or task.walkType
        task._bms = nil
        return true
    end

    task.x = finalX
    task.y = finalY
    task.z = finalZ
    task.coarseWaypoint = true
    task.state = "NEW"
    task.time = math.max(tonumber(task.time) or 1000, 900)
    task._bms = nil

    NPCSquadCoarseWaypointsBridge.Stats.continued = (NPCSquadCoarseWaypointsBridge.Stats.continued or 0) + 1
    return true
end

NPCSquadCoarseWaypointsBridge.ApplySettings()
