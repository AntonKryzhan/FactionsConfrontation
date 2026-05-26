-- NPCSpatialIndexBridge.lua
-- Neutral shared backend for spatial lookup/index buffers.

require "NPCCore/NPCLegacyContractBridge"

NPCSpatialIndexBridge = NPCSpatialIndexBridge or {}

NPCSpatialIndexBridge.VERSION = "2026-05-10-packed-buffer-index-2"

NPCSpatialIndexBridge.Config = NPCSpatialIndexBridge.Config or {
    bucketSize = 8,
    refreshMs = 120
}

NPCSpatialIndexBridge._builtAt = NPCSpatialIndexBridge._builtAt or 0
NPCSpatialIndexBridge._cacheLightRef = NPCSpatialIndexBridge._cacheLightRef or nil
NPCSpatialIndexBridge._all = NPCSpatialIndexBridge._all or {}
NPCSpatialIndexBridge._bandits = NPCSpatialIndexBridge._bandits or {}
NPCSpatialIndexBridge._zombies = NPCSpatialIndexBridge._zombies or {}
NPCSpatialIndexBridge._stats = NPCSpatialIndexBridge._stats or {all=0, bandits=0, zombies=0}
NPCSpatialIndexBridge._buffers = NPCSpatialIndexBridge._buffers or {}

local NPC_SPATIAL_INDEX_LEGACY_LIGHT_FLAG = "is" .. NPCLegacyContractBridge.Token

local BSI_KEY_OFFSET = 1048576
local BSI_KEY_SPAN = 2097152

local function bsi_packZ(z)
    return math.floor(tonumber(z) or 0)
end

local function bsi_packBucket(bx, by)
    return (math.floor(tonumber(bx) or 0) + BSI_KEY_OFFSET) * BSI_KEY_SPAN + (math.floor(tonumber(by) or 0) + BSI_KEY_OFFSET)
end

local function bsi_now()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then return math.floor((getGameTime():getWorldAgeHours() or 0) * 3600000) end
    return 0
end

local function bsi_bucketSize()
    local size = tonumber(NPCSpatialIndexBridge.Config.bucketSize or 8) or 8
    if size < 4 then size = 4 end
    return size
end

local function bsi_bucketXY(x, y)
    local size = bsi_bucketSize()
    return math.floor((tonumber(x) or 0) / size), math.floor((tonumber(y) or 0) / size)
end

local function bsi_zkey(z)
    return bsi_packZ(z)
end

local function bsi_getBucket(map, z, bx, by, create)
    local zk = bsi_zkey(z)
    local zmap = map[zk]
    if not zmap then
        if not create then return nil end
        zmap = {}
        map[zk] = zmap
    end

    local key = bsi_packBucket(bx, by)
    local bucket = zmap[key]
    if not bucket and create then
        bucket = {}
        zmap[key] = bucket
    end

    return bucket
end

local function bsi_insert(map, data)
    if not data or data.x == nil or data.y == nil then return end
    local bx, by = bsi_bucketXY(data.x, data.y)
    local bucket = bsi_getBucket(map, data.z or 0, bx, by, true)
    bucket[#bucket + 1] = data
end

function NPCSpatialIndexBridge.Reset()
    NPCSpatialIndexBridge._builtAt = 0
    NPCSpatialIndexBridge._cacheLightRef = nil
    NPCSpatialIndexBridge._all = {}
    NPCSpatialIndexBridge._bandits = {}
    NPCSpatialIndexBridge._zombies = {}
    NPCSpatialIndexBridge._stats = {all=0, bandits=0, zombies=0}
    NPCSpatialIndexBridge._buffers = NPCSpatialIndexBridge._buffers or {}
end

function NPCSpatialIndexBridge.Build(force)
    if not NPCZombieCacheBridge or not NPCZombieCacheBridge.CacheLight then return false end

    local now = bsi_now()
    local refresh = tonumber(NPCSpatialIndexBridge.Config.refreshMs or 120) or 120
    local cacheRef = NPCZombieCacheBridge.CacheLight

    if not force and NPCSpatialIndexBridge._cacheLightRef == cacheRef and now - (NPCSpatialIndexBridge._builtAt or 0) < refresh then
        return true
    end

    local all, bandits, zombies = {}, {}, {}
    local stats = {all=0, bandits=0, zombies=0}

    for id, data in pairs(cacheRef) do
        if data and data.x ~= nil and data.y ~= nil then
            data.id = data.id or id
            bsi_insert(all, data)
            stats.all = stats.all + 1

            if data[NPC_SPATIAL_INDEX_LEGACY_LIGHT_FLAG] or data.brain then
                bsi_insert(bandits, data)
                stats.bandits = stats.bandits + 1
            else
                bsi_insert(zombies, data)
                stats.zombies = stats.zombies + 1
            end
        end
    end

    NPCSpatialIndexBridge._all = all
    NPCSpatialIndexBridge._bandits = bandits
    NPCSpatialIndexBridge._zombies = zombies
    NPCSpatialIndexBridge._stats = stats
    NPCSpatialIndexBridge._cacheLightRef = cacheRef
    NPCSpatialIndexBridge._builtAt = now

    return true
end

function NPCSpatialIndexBridge.EnsureFresh(force)
    return NPCSpatialIndexBridge.Build(force)
end

local function bsi_clearArray(tbl, count)
    if not tbl then return end
    local n = tonumber(count) or #tbl
    for i = 1, n do
        tbl[i] = nil
    end
end

local function bsi_queryInto(map, result, x, y, z, radius)
    result = result or {}
    bsi_clearArray(result, #result)

    radius = tonumber(radius or 30) or 30
    if radius <= 0 then return result, 0 end

    local size = bsi_bucketSize()
    local bx, by = bsi_bucketXY(x, y)
    local br = math.ceil(radius / size)
    local r2 = radius * radius
    local zk = bsi_zkey(z or 0)
    local zmap = map[zk]
    if not zmap then return result, 0 end

    local count = 0
    for xx = bx - br, bx + br do
        for yy = by - br, by + br do
            local bucket = zmap[bsi_packBucket(xx, yy)]
            if bucket then
                for i = 1, #bucket do
                    local data = bucket[i]
                    if data and data.x ~= nil and data.y ~= nil then
                        local dx = data.x - x
                        local dy = data.y - y
                        if dx * dx + dy * dy <= r2 then
                            count = count + 1
                            result[count] = data
                        end
                    end
                end
            end
        end
    end

    return result, count
end

local function bsi_query(map, x, y, z, radius)
    local result = bsi_queryInto(map, {}, x, y, z, radius)
    return result
end

function NPCSpatialIndexBridge.GetNearbyAllInto(result, x, y, z, radius)
    if not NPCSpatialIndexBridge.Build(false) then
        result = result or {}
        bsi_clearArray(result, #result)
        return result, 0
    end
    return bsi_queryInto(NPCSpatialIndexBridge._all, result, x, y, z, radius)
end

function NPCSpatialIndexBridge.GetNearbyNPCsInto(result, x, y, z, radius)
    if not NPCSpatialIndexBridge.Build(false) then
        result = result or {}
        bsi_clearArray(result, #result)
        return result, 0
    end
    return bsi_queryInto(NPCSpatialIndexBridge._bandits, result, x, y, z, radius)
end

NPCSpatialIndexBridge[NPCLegacyContractBridge.Member("getNearbyInto")] = function(result, x, y, z, radius)
    return NPCSpatialIndexBridge.GetNearbyNPCsInto(result, x, y, z, radius)
end

function NPCSpatialIndexBridge.GetNearbyZombiesInto(result, x, y, z, radius)
    if not NPCSpatialIndexBridge.Build(false) then
        result = result or {}
        bsi_clearArray(result, #result)
        return result, 0
    end
    return bsi_queryInto(NPCSpatialIndexBridge._zombies, result, x, y, z, radius)
end

function NPCSpatialIndexBridge.GetNearbyAll(x, y, z, radius)
    if not NPCSpatialIndexBridge.Build(false) then return {} end
    return bsi_query(NPCSpatialIndexBridge._all, x, y, z, radius)
end

function NPCSpatialIndexBridge.GetNearbyNPCs(x, y, z, radius)
    if not NPCSpatialIndexBridge.Build(false) then return {} end
    return bsi_query(NPCSpatialIndexBridge._bandits, x, y, z, radius)
end

NPCSpatialIndexBridge[NPCLegacyContractBridge.Member("getNearby")] = function(x, y, z, radius)
    return NPCSpatialIndexBridge.GetNearbyNPCs(x, y, z, radius)
end

function NPCSpatialIndexBridge.GetNearbyZombies(x, y, z, radius)
    if not NPCSpatialIndexBridge.Build(false) then return {} end
    return bsi_query(NPCSpatialIndexBridge._zombies, x, y, z, radius)
end

local function bsi_emptyResult()
    return {dist=math.huge, x=false, y=false, z=false, id=false}
end

local function bsi_dist(x1, y1, x2, y2)
    local dx = x1 - x2
    local dy = y1 - y2
    return math.sqrt(dx * dx + dy * dy)
end

local function bsi_closest(list, character, skipId)
    local result = bsi_emptyResult()
    if not character then return result end

    local cx, cy = character:getX(), character:getY()
    for _, data in pairs(list or {}) do
        local skipTarget = data and (data.noZombieTarget or (data.brain and (data.brain.noZombieTarget or data.brain.noAggro or data.brain.blackMarket)))
        if data and not skipTarget and data.id ~= skipId then
            local dist = bsi_dist(cx, cy, data.x, data.y)
            if dist < result.dist then
                result.dist = dist
                result.x = data.x
                result.y = data.y
                result.z = data.z
                result.id = data.id
            end
        end
    end

    return result
end

function NPCSpatialIndexBridge.GetClosestNPCLocation(character, radius)
    if not character then return bsi_emptyResult() end
    local cid = NPCUtils and NPCUtils.GetCharacterID and NPCUtils.GetCharacterID(character) or nil
    local x, y, z = character:getX(), character:getY(), character:getZ()
    local list = NPCSpatialIndexBridge.GetNearbyNPCs(x, y, z, radius or 30)
    return bsi_closest(list, character, cid)
end

NPCSpatialIndexBridge[NPCLegacyContractBridge.Member("getClosestLocation")] = function(character, radius)
    return NPCSpatialIndexBridge.GetClosestNPCLocation(character, radius)
end

function NPCSpatialIndexBridge.GetClosestZombieLocation(character, radius)
    if not character then return bsi_emptyResult() end
    local x, y, z = character:getX(), character:getY(), character:getZ()
    local list = NPCSpatialIndexBridge.GetNearbyZombies(x, y, z, radius or 30)
    return bsi_closest(list, character, nil)
end

function NPCSpatialIndexBridge.CountNearbyNPCs(x, y, z, radius, predicate)
    local list = NPCSpatialIndexBridge.GetNearbyNPCs(x, y, z, radius or 8)
    if not predicate then return #list end

    local count = 0
    for _, data in pairs(list) do
        if predicate(data) then count = count + 1 end
    end
    return count
end

NPCSpatialIndexBridge[NPCLegacyContractBridge.Member("countNearby")] = function(x, y, z, radius, predicate)
    return NPCSpatialIndexBridge.CountNearbyNPCs(x, y, z, radius, predicate)
end

function NPCSpatialIndexBridge.CountNearbyZombies(x, y, z, radius, predicate)
    local list = NPCSpatialIndexBridge.GetNearbyZombies(x, y, z, radius or 8)
    if not predicate then return #list end

    local count = 0
    for _, data in pairs(list) do
        if predicate(data) then count = count + 1 end
    end
    return count
end

function NPCSpatialIndexBridge.Stats()
    NPCSpatialIndexBridge.Build(false)
    return NPCSpatialIndexBridge._stats
end
