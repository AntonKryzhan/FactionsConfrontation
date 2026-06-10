-- NPCTacticalCoverBridge.lua
-- Neutral optional adapter for the historical tactical cover provider.

require "NPCCore/NPCLegacyGlobalsBridge"

NPCTacticalCoverBridge = NPCTacticalCoverBridge or {}
local NPC_LEGACY_GLOBALS = NPCLegacyGlobalsBridge

local function npctacticalcover_merge(source)
    if type(source) ~= "table" or source == NPCTacticalCoverBridge then return end
    for key, value in pairs(source) do
        if NPCTacticalCoverBridge[key] == nil then
            NPCTacticalCoverBridge[key] = value
        end
    end
end

function NPCTacticalCoverBridge.Resolve()
    local legacy = NPC_LEGACY_GLOBALS.Get("TacticalCover")
    npctacticalcover_merge(legacy)
    NPC_LEGACY_GLOBALS.InstallAlias("TacticalCover", NPCTacticalCoverBridge, "NPCTacticalCoverBridge")
    return NPCTacticalCoverBridge
end

NPCTacticalCoverBridge.Resolve()


NPCTacticalCoverBridge.VERSION = "2026-05-31-stage316-urban-cover-props-1"
NPCTacticalCoverBridge.Config = NPCTacticalCoverBridge.Config or {
    enabled = true,
    searchRadius = 7,
    coverDistance = 6.5,
    minScore = 1.0,
    reserveForMs = 1800,
    urbanCoverProps = true
}
NPCTacticalCoverBridge._cache = NPCTacticalCoverBridge._cache or {}

local function btc_nowMs()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then return math.floor(getGameTime():getWorldAgeHours() * 3600000) end
    return 0
end

local function btc_dist2(x1, y1, x2, y2)
    local dx = x1 - x2
    local dy = y1 - y2
    return dx * dx + dy * dy
end

local function btc_getSquare(x, y, z)
    local cell = getCell and getCell() or nil
    if not cell then return nil end
    return cell:getGridSquare(math.floor(x), math.floor(y), math.floor(z or 0))
end

local function btc_squareBlocked(square, mover)
    if not square then return true end
    if NPCMovementStabilityBridge and NPCMovementStabilityBridge.IsSquareBlocked then
        local ok, blocked = pcall(function() return NPCMovementStabilityBridge.IsSquareBlocked(square, mover) end)
        if ok then return blocked == true end
    end
    local ok, solid = pcall(function() return square:isSolid() or square:isSolidTrans() end)
    return ok and solid == true
end

local function btc_isUrbanCoverPropItem(fullType)
    fullType = tostring(fullType or "")
    return fullType == "Base.NormalTire1"
        or fullType == "Base.NormalTire2"
        or fullType == "Base.NormalTire3"
        or fullType == "Base.OldTire1"
        or fullType == "Base.OldTire2"
        or fullType == "Base.OldTire3"
        or fullType == "Base.ScrapMetal"
        or fullType == "Base.SmallSheetMetal"
        or fullType == "Base.SheetMetal"
        or fullType == "Base.MetalPipe"
        or fullType == "Base.MetalBar"
        or fullType == "Base.Plank"
        or fullType == "Base.UnusableWood"
        or fullType == "Base.NailsBox"
        or fullType == "Base.Nails"
        or fullType == "Base.Hinge"
        or fullType == "Base.Doorknob"
        or fullType == "Base.Screws"
        or fullType == "Base.EngineParts"
        or fullType == "Base.BrokenGlass"
        or fullType == "Base.Garbagebag"
        or fullType == "Base.EmptyPetrolCan"
        or fullType == "Base.PetrolCanEmpty"
        or fullType == "Base.WaterBottleEmpty"
        or fullType == "Base.PopEmpty"
        or fullType == "Base.TinCanEmpty"
end

local function btc_worldItemFullType(obj)
    if not obj then return nil end
    local okItem, item = pcall(function() return obj:getItem() end)
    if not okItem or not item then return nil end
    local okFull, fullType = pcall(function() return item:getFullType() end)
    if okFull and fullType then return tostring(fullType) end
    local okType, itemType = pcall(function() return item:getType() end)
    if okType and itemType then return "Base." .. tostring(itemType) end
    return nil
end

local function btc_squareHasUrbanCoverProp(square)
    if not square then return false end
    if NPCTacticalCoverBridge.Config and NPCTacticalCoverBridge.Config.urbanCoverProps == false then return false end
    local ok, objects = pcall(function() return square:getWorldObjects() end)
    if not ok or not objects then return false end
    local size = 0
    local okSize, result = pcall(function() return objects:size() end)
    if okSize and result then size = tonumber(result) or 0 end
    if size <= 0 then return false end
    for i = 0, size - 1 do
        local fullType = btc_worldItemFullType(objects:get(i))
        if btc_isUrbanCoverPropItem(fullType) then return true end
    end
    return false
end

local function btc_objectBlocks(obj)
    if not obj then return false end
    local ok, blocked = pcall(function()
        if instanceof and (instanceof(obj, "IsoDoor") or instanceof(obj, "IsoWindow") or instanceof(obj, "IsoThumpable")) then
            if obj.IsOpen and obj:IsOpen() == true then return false end
            if obj.isSmashed and obj:isSmashed() == true then return false end
            if obj.isBarricaded and obj:isBarricaded() == true then return true end
            return true
        end
        local props = obj:getProperties()
        if props and IsoFlagType then
            if IsoFlagType.collideN and props:Is(IsoFlagType.collideN) then return true end
            if IsoFlagType.collideW and props:Is(IsoFlagType.collideW) then return true end
            if IsoFlagType.solid and props:Is(IsoFlagType.solid) then return true end
            if IsoFlagType.solidtrans and props:Is(IsoFlagType.solidtrans) then return true end
        end
        local name = tostring(obj:getSpriteName() or ""):lower()
        return name:find("wall", 1, true) ~= nil
            or name:find("fence", 1, true) ~= nil
            or name:find("counter", 1, true) ~= nil
            or name:find("crate", 1, true) ~= nil
            or name:find("shelf", 1, true) ~= nil
            or name:find("barricade", 1, true) ~= nil
    end)
    return ok and blocked == true
end

local function btc_squareHasCover(square)
    if not square then return false end
    if btc_squareHasUrbanCoverProp(square) then return true end
    local ok, objects = pcall(function() return square:getObjects() end)
    if not ok or not objects then return false end
    for i = 0, objects:size() - 1 do
        if btc_objectBlocks(objects:get(i)) then return true end
    end
    return false
end

local function btc_edgeBlocks(mover, fromSq, toSq)
    if not fromSq or not toSq then return false end
    local dx = toSq:getX() - fromSq:getX()
    local dy = toSq:getY() - fromSq:getY()
    if math.abs(dx) > 1 or math.abs(dy) > 1 then return true end
    local ok, blocked = pcall(function() return fromSq:testCollideAdjacent(mover, dx, dy, 0) end)
    if ok and blocked then return true end
    ok, blocked = pcall(function() return fromSq:isBlockedTo(toSq) end)
    if ok and blocked then return true end
    ok, blocked = pcall(function() return toSq:isBlockedTo(fromSq) end)
    return ok and blocked == true
end

local function btc_coverScore(bandit, square, threat)
    if not square or not threat or not threat.x or not threat.y then return -100000 end
    if btc_squareBlocked(square, bandit) then return -100000 end

    local sx = square:getX() + 0.5
    local sy = square:getY() + 0.5
    local sz = square:getZ()
    local tx = tonumber(threat.x) or sx
    local ty = tonumber(threat.y) or sy
    local dx = sx - tx
    local dy = sy - ty
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.05 then len = 1 end
    local ux = dx / len
    local uy = dy / len

    local score = 0
    local shieldSq = btc_getSquare(sx - ux, sy - uy, sz)
    if shieldSq and btc_squareHasCover(shieldSq) then
        score = score + 8
        if btc_squareHasUrbanCoverProp(shieldSq) then score = score + 2.5 end
    end
    if shieldSq and btc_edgeBlocks(bandit, square, shieldSq) then score = score + 5 end

    local dirs = {{1,0},{-1,0},{0,1},{0,-1}}
    for _, d in ipairs(dirs) do
        local nsq = btc_getSquare(square:getX() + d[1], square:getY() + d[2], sz)
        if nsq and btc_squareHasCover(nsq) then
            score = score + 1.25
            if btc_squareHasUrbanCoverProp(nsq) then score = score + 1.75 end
        end
    end

    local distThreat = math.sqrt(btc_dist2(sx, sy, tx, ty))
    local coverDistance = tonumber(NPCTacticalCoverBridge.Config.coverDistance) or 6.5
    if distThreat < 3.5 then score = score - 8 end
    if distThreat >= coverDistance then score = score + math.min(4, (distThreat - coverDistance) * 0.25) end

    if bandit then
        score = score - math.sqrt(btc_dist2(sx, sy, bandit:getX(), bandit:getY())) * 0.18
    end

    return score
end

function NPCTacticalCoverBridge.GetPoint(bandit, brain, threat, role)
    if NPCTacticalCoverBridge.Config and NPCTacticalCoverBridge.Config.enabled == false then return nil end
    if not bandit or not threat or not threat.x or not threat.y then return nil end

    local now = btc_nowMs()
    local cacheKey = tostring(brain and (brain.id or brain.uid or brain.persistentId) or bandit) .. ":" .. tostring(role or "cover")
    local cached = NPCTacticalCoverBridge._cache and NPCTacticalCoverBridge._cache[cacheKey]
    if cached and cached.untilMs and now < cached.untilMs and cached.x and cached.y then
        return cached
    end

    local radius = tonumber(NPCTacticalCoverBridge.Config.searchRadius) or 7
    local bestSq, bestScore
    if NPCMovementStabilityBridge and NPCMovementStabilityBridge.FindReachableAround then
        bestSq = NPCMovementStabilityBridge.FindReachableAround(bandit, radius, function(square, depth)
            local score = btc_coverScore(bandit, square, threat) - (tonumber(depth) or 0) * 0.25
            return score
        end)
        if bestSq then bestScore = btc_coverScore(bandit, bestSq, threat) end
    end

    if not bestSq then
        local origin = bandit:getSquare()
        if not origin then return nil end
        local ox, oy, oz = origin:getX(), origin:getY(), origin:getZ()
        for r = 1, radius do
            for dx = -r, r do
                for dy = -r, r do
                    if math.abs(dx) == r or math.abs(dy) == r then
                        local sq = btc_getSquare(ox + dx, oy + dy, oz)
                        local score = btc_coverScore(bandit, sq, threat)
                        if not bestScore or score > bestScore then
                            bestScore = score
                            bestSq = sq
                        end
                    end
                end
            end
        end
    end

    local minScore = tonumber(NPCTacticalCoverBridge.Config.minScore) or 1.0
    if not bestSq or not bestScore or bestScore < minScore then return nil end

    local point = {
        x = bestSq:getX(),
        y = bestSq:getY(),
        z = bestSq:getZ(),
        score = bestScore,
        role = role,
        reason = "obstacle-aware cover"
    }
    point.untilMs = now + (tonumber(NPCTacticalCoverBridge.Config.reserveForMs) or 1800)
    NPCTacticalCoverBridge._cache[cacheKey] = point
    return point
end

