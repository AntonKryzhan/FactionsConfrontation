-- NPCLootTargetCacheBridge.lua
-- Shared runtime cache for building/container/window scans.
-- Stage 311: keeps BrainDirector, LivingWorld and WorldRoutine from scanning
-- the same rooms/containers/portals independently in the same short window.

NPCLootTargetCacheBridge = NPCLootTargetCacheBridge or {}

NPCLootTargetCacheBridge.VERSION = "2026-05-31-stage311-loot-target-cache"

NPCLootTargetCacheBridge.Config = NPCLootTargetCacheBridge.Config or {
    containerTtlMs = 5200,
    portalTtlMs = 9000,
    failedTtlMs = 45000,
    bucketSize = 10,
    maxSquareChecks = 170,
    maxObjectChecks = 18,
    maxItemChecks = 70,
    maxPortalChecks = 110
}

NPCLootTargetCacheBridge.ContainerCache = NPCLootTargetCacheBridge.ContainerCache or {}
NPCLootTargetCacheBridge.PortalCache = NPCLootTargetCacheBridge.PortalCache or {}
NPCLootTargetCacheBridge.FailedTargets = NPCLootTargetCacheBridge.FailedTargets or {}

local function blc_nowMs()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then return math.floor((getGameTime():getWorldAgeHours() or 0) * 3600000) end
    return 0
end

local function blc_floor(value)
    return math.floor(tonumber(value) or 0)
end

local function blc_getCell()
    if getCell then return getCell() end
    return nil
end

local function blc_getSquare(x, y, z)
    local cell = blc_getCell()
    if not (cell and cell.getGridSquare) then return nil end
    local ok, square = pcall(function() return cell:getGridSquare(blc_floor(x), blc_floor(y), blc_floor(z)) end)
    if ok then return square end
    return nil
end

local function blc_squareKey(x, y, z)
    if x == nil or y == nil then return nil end
    return tostring(blc_floor(x)) .. ":" .. tostring(blc_floor(y)) .. ":" .. tostring(blc_floor(z))
end

local function blc_chrKey(chr, radius, need)
    if not (chr and chr.getX and chr.getY and chr.getZ) then return nil end
    local bucket = tonumber(NPCLootTargetCacheBridge.Config.bucketSize) or 10
    if bucket < 2 then bucket = 10 end
    local bx = math.floor((tonumber(chr:getX()) or 0) / bucket)
    local by = math.floor((tonumber(chr:getY()) or 0) / bucket)
    local bz = blc_floor(chr:getZ())
    local r = math.floor(tonumber(radius) or 0)
    local n = tostring(need or "any")
    return tostring(bx) .. ":" .. tostring(by) .. ":" .. tostring(bz) .. ":" .. tostring(r) .. ":" .. n
end

local function blc_isFailed(key, now)
    if not key then return false end
    now = now or blc_nowMs()
    local untilMs = tonumber(NPCLootTargetCacheBridge.FailedTargets[key]) or 0
    if untilMs > now then return true end
    NPCLootTargetCacheBridge.FailedTargets[key] = nil
    return false
end

local function blc_brainFailed(brain, key, now)
    if not (brain and key) then return false end
    now = now or blc_nowMs()
    local failed = brain.ai and brain.ai.lootTargetCache and brain.ai.lootTargetCache.failed or nil
    local untilMs = failed and tonumber(failed[key]) or 0
    if untilMs > now then return true end
    if failed then failed[key] = nil end
    return false
end

local function blc_text(value)
    if value == nil then return "" end
    return tostring(value):lower()
end

local function blc_itemText(item)
    if not item then return "" end
    local chunks = {}
    if item.getType then
        local ok, got = pcall(function() return item:getType() end)
        if ok and got then chunks[#chunks + 1] = got end
    end
    if item.getFullType then
        local ok, got = pcall(function() return item:getFullType() end)
        if ok and got then chunks[#chunks + 1] = got end
    end
    if item.getDisplayName then
        local ok, got = pcall(function() return item:getDisplayName() end)
        if ok and got then chunks[#chunks + 1] = got end
    end
    return blc_text(table.concat(chunks, " "))
end

local function blc_hasAny(text, words)
    text = blc_text(text)
    for _, word in ipairs(words) do
        if string.find(text, word, 1, true) then return true end
    end
    return false
end

local function blc_itemMatchesNeed(item, need)
    need = blc_text(need or "any")
    if need == "" or need == "any" or need == "nil" then return true end
    local text = blc_itemText(item)
    if need == "ammo" then return blc_hasAny(text, {"ammo", "bullet", "round", "shell", "magazine", "clip"}) end
    if need == "medical" or need == "med" then return blc_hasAny(text, {"bandage", "firstaid", "first aid", "med", "suture", "disinfect", "alcohol"}) end
    if need == "food" then return blc_hasAny(text, {"food", "canned", "chips", "bread", "meat", "soup", "fruit", "vegetable"}) end
    if need == "water" or need == "drink" then return blc_hasAny(text, {"water", "bottle", "canteen", "pop", "soda"}) end
    if need == "weapon" then return blc_hasAny(text, {"rifle", "shotgun", "pistol", "revolver", "gun", "knife", "machete", "bat", "axe"}) end
    if need == "gear" or need == "supplies" or need == "supply" then return true end
    return true
end

local function blc_squareAllowed(chr, square, options)
    if not square then return false end
    options = options or {}
    local brain = options.brain
    if brain and NPCMovementStabilityBridge and NPCMovementStabilityBridge.IsBadTarget then
        local ok, bad = pcall(function() return NPCMovementStabilityBridge.IsBadTarget(brain, square:getX(), square:getY(), square:getZ()) end)
        if ok and bad then return false end
    end
    if options.squareFilter then
        local ok, allowed = pcall(options.squareFilter, chr, square, options)
        if ok and allowed == false then return false end
    end
    return true
end

local function blc_scoreContainer(container, need, options)
    if not container then return 0 end
    local empty = false
    if container.isEmpty then
        local ok, got = pcall(function() return container:isEmpty() == true end)
        if ok then empty = got end
    end
    if empty then return 0 end
    need = need or "any"
    if tostring(need) == "any" or tostring(need) == "" then return 1 end

    local items = nil
    if container.getItems then
        local ok, got = pcall(function() return container:getItems() end)
        if ok then items = got end
    end
    if not items or not items.size or not items.get then return 0.8 end

    local maxItems = tonumber(options and options.maxItemChecks) or tonumber(NPCLootTargetCacheBridge.Config.maxItemChecks) or 70
    local limit = math.min(items:size() - 1, maxItems - 1)
    local score = 0
    for i = 0, limit do
        if blc_itemMatchesNeed(items:get(i), need) then
            score = score + 1
            if score >= 4 then return score end
        end
    end
    return score
end

local function blc_squareContainerScore(square, need, options)
    if not (square and square.getObjects) then return 0 end
    local ok, objects = pcall(function() return square:getObjects() end)
    if not ok or not objects or not objects.size or not objects.get then return 0 end
    local maxObjects = tonumber(options and options.maxObjectChecks) or tonumber(NPCLootTargetCacheBridge.Config.maxObjectChecks) or 18
    local limit = math.min(objects:size() - 1, maxObjects - 1)
    local score = 0
    for i = 0, limit do
        local object = objects:get(i)
        local container = object and object.getContainer and object:getContainer() or nil
        local got = blc_scoreContainer(container, need, options)
        if got > 0 then
            score = score + got
            if tostring(need or "any") == "any" then return score end
        end
    end
    return score
end

local function blc_cacheSquare(cache, key, square, score, now, ttlMs)
    if not (cache and key and square) then return end
    cache[key] = {
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
        score = score or 1,
        untilMs = (now or blc_nowMs()) + (tonumber(ttlMs) or tonumber(NPCLootTargetCacheBridge.Config.containerTtlMs) or 5200)
    }
end

local function blc_cachedSquare(cache, key, need, options, now)
    local rec = cache and key and cache[key] or nil
    if not rec then return nil end
    now = now or blc_nowMs()
    if (tonumber(rec.untilMs) or 0) < now then
        cache[key] = nil
        return nil
    end
    local square = blc_getSquare(rec.x, rec.y, rec.z)
    if not square then
        cache[key] = nil
        return nil
    end
    if blc_squareContainerScore(square, need, options) <= 0 then
        cache[key] = nil
        return nil
    end
    return square
end

function NPCLootTargetCacheBridge.MarkFailed(brain, x, y, z, ttlMs)
    local key = type(x) == "table" and x.getX and blc_squareKey(x:getX(), x:getY(), x:getZ()) or blc_squareKey(x, y, z)
    if not key then return false end
    local now = blc_nowMs()
    local untilMs = now + (tonumber(ttlMs) or tonumber(NPCLootTargetCacheBridge.Config.failedTtlMs) or 45000)
    NPCLootTargetCacheBridge.FailedTargets[key] = untilMs
    if brain then
        brain.ai = brain.ai or {}
        brain.ai.lootTargetCache = brain.ai.lootTargetCache or {failed = {}}
        brain.ai.lootTargetCache.failed = brain.ai.lootTargetCache.failed or {}
        brain.ai.lootTargetCache.failed[key] = untilMs
    end
    return true
end

function NPCLootTargetCacheBridge.FindContainerSquare(chr, radius, options)
    if not (chr and chr.getX and chr.getY and chr.getZ) then return nil end
    options = options or {}
    local cell = blc_getCell()
    if not cell then return nil end
    local need = options.need or "any"
    radius = tonumber(radius) or tonumber(options.radius) or 8
    if radius < 0 then radius = 0 end
    local now = blc_nowMs()
    local cacheKey = blc_chrKey(chr, radius, need)
    local cached = blc_cachedSquare(NPCLootTargetCacheBridge.ContainerCache, cacheKey, need, options, now)
    if cached and blc_squareAllowed(chr, cached, options) then return cached end

    local bx = blc_floor(chr:getX())
    local by = blc_floor(chr:getY())
    local bz = blc_floor(chr:getZ())
    local maxChecks = tonumber(options.maxSquareChecks) or tonumber(NPCLootTargetCacheBridge.Config.maxSquareChecks) or 170
    local checks = 0
    local bestSquare = nil
    local bestScore = 0
    local seed = now % 4

    for r = 0, radius do
        for dx = -r, r do
            for dy = -r, r do
                if checks >= maxChecks then
                    if bestSquare then blc_cacheSquare(NPCLootTargetCacheBridge.ContainerCache, cacheKey, bestSquare, bestScore, now, options.ttlMs) end
                    return bestSquare
                end
                if r == 0 or math.abs(dx) == r or math.abs(dy) == r then
                    local sx = bx + dx
                    local sy = by + dy
                    if r <= 2 or ((sx + sy + seed) % 2) == 0 then
                        checks = checks + 1
                        local key = blc_squareKey(sx, sy, bz)
                        if not blc_isFailed(key, now) and not blc_brainFailed(options.brain, key, now) then
                            local square = cell:getGridSquare(sx, sy, bz)
                            if square and blc_squareAllowed(chr, square, options) then
                                local score = blc_squareContainerScore(square, need, options)
                                if score > 0 then
                                    score = score - (r * 0.04)
                                    if score > bestScore then
                                        bestScore = score
                                        bestSquare = square
                                        if tostring(need or "any") == "any" and r <= 2 then
                                            blc_cacheSquare(NPCLootTargetCacheBridge.ContainerCache, cacheKey, bestSquare, bestScore, now, options.ttlMs)
                                            return bestSquare
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        if bestSquare and r >= 3 then break end
    end

    if bestSquare then blc_cacheSquare(NPCLootTargetCacheBridge.ContainerCache, cacheKey, bestSquare, bestScore, now, options.ttlMs) end
    return bestSquare
end

local function blc_isWindow(object)
    if not object then return false end
    if instanceof then
        local ok, result = pcall(function() return instanceof(object, "IsoWindow") end)
        if ok and result == true then return true end
    end
    return object.IsOpen ~= nil and object.ToggleWindow ~= nil
end

local function blc_windowOpen(object)
    if not (object and object.IsOpen) then return false end
    local ok, open = pcall(function() return object:IsOpen() == true end)
    return ok and open == true
end

local function blc_windowSmashed(object)
    if not (object and object.isSmashed) then return false end
    local ok, smashed = pcall(function() return object:isSmashed() == true end)
    return ok and smashed == true
end

local function blc_portalKey(chr, targetSquare, radius)
    if not (chr and targetSquare) then return nil end
    return blc_squareKey(targetSquare:getX(), targetSquare:getY(), targetSquare:getZ()) .. ":" .. tostring(math.floor(tonumber(radius) or 0))
end

function NPCLootTargetCacheBridge.FindWindowPortal(chr, targetSquare, options)
    if not (chr and targetSquare and targetSquare.getX) then return nil end
    options = options or {}
    local cell = blc_getCell()
    if not cell then return nil end
    local radius = tonumber(options.radius) or 6
    local now = blc_nowMs()
    local cacheKey = blc_portalKey(chr, targetSquare, radius)
    local cached = cacheKey and NPCLootTargetCacheBridge.PortalCache[cacheKey] or nil
    if cached and (tonumber(cached.untilMs) or 0) >= now then return cached.portal end

    local bx = blc_floor(chr:getX())
    local by = blc_floor(chr:getY())
    local tx = targetSquare:getX()
    local ty = targetSquare:getY()
    local tz = targetSquare:getZ()
    local checks = 0
    local maxChecks = tonumber(options.maxChecks) or tonumber(NPCLootTargetCacheBridge.Config.maxPortalChecks) or 110
    local best = nil
    local bestScore = nil

    for r = 1, radius do
        for dx = -r, r do
            for dy = -r, r do
                if checks >= maxChecks then break end
                if math.abs(dx) == r or math.abs(dy) == r then
                    checks = checks + 1
                    local square = cell:getGridSquare(tx + dx, ty + dy, tz)
                    if square and square.getObjects then
                        local ok, objects = pcall(function() return square:getObjects() end)
                        if ok and objects and objects.size and objects.get then
                            for i = 0, objects:size() - 1 do
                                local object = objects:get(i)
                                if blc_isWindow(object) then
                                    local sx = square:getX()
                                    local sy = square:getY()
                                    local score = ((bx - sx) * (bx - sx) + (by - sy) * (by - sy)) + ((tx - sx) * (tx - sx) + (ty - sy) * (ty - sy)) * 0.35
                                    if not bestScore or score < bestScore then
                                        bestScore = score
                                        best = {x = sx, y = sy, z = square:getZ(), open = blc_windowOpen(object), smashed = blc_windowSmashed(object)}
                                    end
                                end
                            end
                        end
                    end
                end
            end
            if checks >= maxChecks then break end
        end
        if best then break end
        if checks >= maxChecks then break end
    end

    if cacheKey then
        NPCLootTargetCacheBridge.PortalCache[cacheKey] = {portal = best, untilMs = now + (tonumber(options.ttlMs) or tonumber(NPCLootTargetCacheBridge.Config.portalTtlMs) or 9000)}
    end
    return best
end

function NPCLootTargetCacheBridge.FlushExpired()
    local now = blc_nowMs()
    for key, rec in pairs(NPCLootTargetCacheBridge.ContainerCache) do
        if not rec or (tonumber(rec.untilMs) or 0) < now then NPCLootTargetCacheBridge.ContainerCache[key] = nil end
    end
    for key, rec in pairs(NPCLootTargetCacheBridge.PortalCache) do
        if not rec or (tonumber(rec.untilMs) or 0) < now then NPCLootTargetCacheBridge.PortalCache[key] = nil end
    end
    for key, untilMs in pairs(NPCLootTargetCacheBridge.FailedTargets) do
        if (tonumber(untilMs) or 0) < now then NPCLootTargetCacheBridge.FailedTargets[key] = nil end
    end
end
