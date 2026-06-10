-- NPCWorldSnapshotBridge.lua
-- Runtime-only shared world snapshot cache.
-- Keeps common player/FPS/queue counters in one place so hot systems do not
-- repeatedly scan online players and ModData in the same scheduler slice.

require "NPCCore/NPCBufferPoolBridge"

NPCWorldSnapshotBridge = NPCWorldSnapshotBridge or {}
NPCWorldSnapshotBridge.VERSION = "2026-06-02-stage357-dense-world-snapshot-1"

NPCWorldSnapshotBridge.Config = NPCWorldSnapshotBridge.Config or {
    enabled = true,
    refreshTicks = 3,
    queueRefreshTicks = 12,
    maxPlayers = 64,
    debug = false
}

NPCWorldSnapshotBridge.State = NPCWorldSnapshotBridge.State or {
    tick = -999999,
    queueTick = -999999,
    worldAgeHours = 0,
    fps = 60,
    zoom = 1,
    playerCount = 0,
    players = {},
    playerObj = {},
    playerIndex = {},
    playerKey = {},
    playerX = {},
    playerY = {},
    playerZ = {},
    playerVehicle = {},
    playerChunkX = {},
    playerChunkY = {},
    npcCount = 0,
    zombieCount = 0,
    queueCount = 0,
    markerCount = 0,
    pendingSpawn = 0,
    pendingTasks = 0
}

local function nws_number(name, defaultValue, minValue, maxValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        return NPCLegacySettingsBridge.GetNumber(name, defaultValue, minValue, maxValue)
    end
    local value = tonumber(defaultValue) or 0
    if minValue ~= nil and value < minValue then value = minValue end
    if maxValue ~= nil and value > maxValue then value = maxValue end
    return value
end

local function nws_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        return NPCLegacySettingsBridge.GetBool(name, defaultValue == true)
    end
    return defaultValue == true
end

local function nws_countLimited(tbl, limit)
    if type(tbl) ~= "table" then return 0 end
    local n = 0
    for _ in pairs(tbl) do
        n = n + 1
        if limit and n >= limit then return n end
    end
    return n
end

local function nws_clearRange(tbl, firstIndex)
    if type(tbl) ~= "table" then return tbl end
    local first = tonumber(firstIndex) or 1
    if first < 1 then first = 1 end
    for i = first, #tbl do tbl[i] = nil end
    return tbl
end

local function nws_trimPlayers(state, count)
    count = tonumber(count) or 0
    nws_clearRange(state.players, count + 1)
    nws_clearRange(state.playerObj, count + 1)
    nws_clearRange(state.playerIndex, count + 1)
    nws_clearRange(state.playerKey, count + 1)
    nws_clearRange(state.playerX, count + 1)
    nws_clearRange(state.playerY, count + 1)
    nws_clearRange(state.playerZ, count + 1)
    nws_clearRange(state.playerVehicle, count + 1)
    nws_clearRange(state.playerChunkX, count + 1)
    nws_clearRange(state.playerChunkY, count + 1)
end

local function nws_ensureStateTables(state)
    state.players = state.players or {}
    state.playerObj = state.playerObj or {}
    state.playerIndex = state.playerIndex or {}
    state.playerKey = state.playerKey or {}
    state.playerX = state.playerX or {}
    state.playerY = state.playerY or {}
    state.playerZ = state.playerZ or {}
    state.playerVehicle = state.playerVehicle or {}
    state.playerChunkX = state.playerChunkX or {}
    state.playerChunkY = state.playerChunkY or {}
end

local function nws_nowTick()
    if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.GetTick then
        local ok, tick = pcall(function() return NPCWorkSchedulerBridge.GetTick() end)
        if ok and tick then return tonumber(tick) or 0 end
    end
    return (tonumber(NPCWorldSnapshotBridge.State.tick) or 0) + 1
end

local function nws_worldAgeHours()
    if getGameTime then
        local ok, hours = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok and hours then return tonumber(hours) or 0 end
    end
    return 0
end

local function nws_averageFPS()
    if getAverageFPS then
        local ok, fps = pcall(function() return getAverageFPS() end)
        if ok and fps then return tonumber(fps) or 60 end
    end
    return 60
end

local function nws_cameraZoom()
    if getCore then
        local ok, zoom = pcall(function() return getCore():getZoom(0) end)
        if ok and zoom then return tonumber(zoom) or 1 end
    end
    return 1
end

local function nws_playerKey(player, index)
    if not player then return "player:" .. tostring(index or 0) end
    local ok, value
    if player.getOnlineID then
        ok, value = pcall(function() return player:getOnlineID() end)
        if ok and value ~= nil then return "online:" .. tostring(value) end
    end
    if player.getUsername then
        ok, value = pcall(function() return player:getUsername() end)
        if ok and value ~= nil and tostring(value) ~= "" then return "user:" .. tostring(value) end
    end
    if player.getDisplayName then
        ok, value = pcall(function() return player:getDisplayName() end)
        if ok and value ~= nil and tostring(value) ~= "" then return "name:" .. tostring(value) end
    end
    return "player:" .. tostring(index or 0)
end

local function nws_storePlayer(state, n, player, index)
    if not (player and player.getX and player.getY) then return n end
    if player.isDead and player:isDead() then return n end

    n = n + 1
    local slot = state.players[n]
    if not slot then
        slot = {}
        state.players[n] = slot
    end
    local pindex = index or (n - 1)
    local pkey = nws_playerKey(player, pindex)
    local px = tonumber(player:getX()) or 0
    local py = tonumber(player:getY()) or 0
    local pz = player.getZ and (tonumber(player:getZ()) or 0) or 0
    local inVehicle = false
    if player.getVehicle then
        local ok, vehicle = pcall(function() return player:getVehicle() end)
        inVehicle = ok and vehicle ~= nil or false
    end

    slot.player = player
    slot.index = pindex
    slot.key = pkey
    slot.x = px
    slot.y = py
    slot.z = pz
    slot.vehicle = inVehicle
    slot.chunkX = math.floor(px / 10)
    slot.chunkY = math.floor(py / 10)

    state.playerObj[n] = player
    state.playerIndex[n] = pindex
    state.playerKey[n] = pkey
    state.playerX[n] = px
    state.playerY[n] = py
    state.playerZ[n] = pz
    state.playerVehicle[n] = inVehicle
    state.playerChunkX[n] = slot.chunkX
    state.playerChunkY[n] = slot.chunkY
    return n
end

local function nws_refreshPlayers(state)
    local n = 0
    local maxPlayers = math.max(1, tonumber(NPCWorldSnapshotBridge.Config.maxPlayers) or 64)

    if getOnlinePlayers then
        local ok, players = pcall(function() return getOnlinePlayers() end)
        if ok and players then
            local size = 0
            pcall(function() size = players:size() end)
            for i = 0, math.min(size - 1, maxPlayers - 1) do
                n = nws_storePlayer(state, n, players:get(i), i)
            end
            if n > 0 then
                state.playerCount = n
                nws_trimPlayers(state, n)
                return
            end
        end
    end

    if getNumActivePlayers and getSpecificPlayer then
        local ok, count = pcall(function() return getNumActivePlayers() end)
        count = ok and tonumber(count) or 1
        for i = 0, math.min(math.max(0, count - 1), maxPlayers - 1) do
            n = nws_storePlayer(state, n, getSpecificPlayer(i), i)
        end
        if n > 0 then
            state.playerCount = n
            nws_trimPlayers(state, n)
            return
        end
    end

    if getSpecificPlayer then
        n = nws_storePlayer(state, n, getSpecificPlayer(0), 0)
    end

    state.playerCount = n
    nws_trimPlayers(state, n)
end

local function nws_refreshQueueCounters(state, tick, force)
    local queueTicks = math.max(1, tonumber(NPCWorldSnapshotBridge.Config.queueRefreshTicks) or 12)
    if not force and state.queueTick and tick - state.queueTick < queueTicks then return end
    state.queueTick = tick

    if NPCZombieCacheBridge then
        state.npcCount = nws_countLimited(NPCZombieCacheBridge.CacheLightB, 10000)
        state.zombieCount = nws_countLimited(NPCZombieCacheBridge.CacheLightZ, 20000)
    else
        state.npcCount = 0
        state.zombieCount = 0
    end

    local gmd = nil
    if GetNPCModData then
        pcall(function() gmd = GetNPCModData() end)
    end
    state.queueCount = gmd and nws_countLimited(gmd.Queue, 10000) or 0
    state.markerCount = gmd and nws_countLimited(gmd.DebugMapMarkers, 20000) or 0

    if NPCSpawnQueueBridge and NPCSpawnQueueBridge.PendingCount then
        local ok, n = pcall(function() return NPCSpawnQueueBridge.PendingCount() end)
        state.pendingSpawn = ok and (tonumber(n) or 0) or 0
    else
        state.pendingSpawn = 0
    end

    if NPCTaskQueueBridge and NPCTaskQueueBridge.PendingCount then
        local ok, n = pcall(function() return NPCTaskQueueBridge.PendingCount() end)
        state.pendingTasks = ok and (tonumber(n) or 0) or 0
    else
        state.pendingTasks = 0
    end
end

function NPCWorldSnapshotBridge.ApplySettings()
    local c = NPCWorldSnapshotBridge.Config
    c.enabled = nws_bool("WorldSnapshot_Enabled", c.enabled ~= false)
    c.refreshTicks = nws_number("WorldSnapshot_RefreshTicks", c.refreshTicks or 3, 1, 600)
    c.queueRefreshTicks = nws_number("WorldSnapshot_QueueRefreshTicks", c.queueRefreshTicks or 12, 1, 1200)
    c.maxPlayers = nws_number("WorldSnapshot_MaxPlayers", c.maxPlayers or 64, 1, 128)
    c.debug = nws_bool("WorldSnapshot_Debug", c.debug == true)
end

function NPCWorldSnapshotBridge.Refresh(force)
    NPCWorldSnapshotBridge.ApplySettings()
    local state = NPCWorldSnapshotBridge.State
    nws_ensureStateTables(state)
    local tick = nws_nowTick()
    local refreshTicks = math.max(1, tonumber(NPCWorldSnapshotBridge.Config.refreshTicks) or 3)
    if not force and state.tick and tick - state.tick < refreshTicks then
        return state
    end

    state.tick = tick
    state.worldAgeHours = nws_worldAgeHours()
    state.fps = nws_averageFPS()
    state.zoom = nws_cameraZoom()

    if NPCWorldSnapshotBridge.Config.enabled == false then
        state.playerCount = 0
        nws_trimPlayers(state, 0)
        return state
    end

    nws_refreshPlayers(state)
    nws_refreshQueueCounters(state, tick, force)
    return state
end

function NPCWorldSnapshotBridge.Get(force)
    return NPCWorldSnapshotBridge.Refresh(force == true)
end

function NPCWorldSnapshotBridge.ForEachPlayer(callback, force)
    if type(callback) ~= "function" then return 0 end
    local state = NPCWorldSnapshotBridge.Get(force == true)
    local n = tonumber(state.playerCount) or 0
    for i = 1, n do
        local player = state.playerObj and state.playerObj[i]
        local slot = state.players[i]
        if player then
            callback(player, (state.playerIndex and state.playerIndex[i]) or (i - 1), slot)
        elseif slot and slot.player then
            callback(slot.player, slot.index or (i - 1), slot)
        end
    end
    return n
end

function NPCWorldSnapshotBridge.GetPlayerPosition(index, force)
    local state = NPCWorldSnapshotBridge.Get(force == true)
    index = tonumber(index) or 1
    if index < 1 or index > (tonumber(state.playerCount) or 0) then return nil end
    return state.playerX[index], state.playerY[index], state.playerZ[index], state.playerObj[index]
end

function NPCWorldSnapshotBridge.GetNearestPlayerDistanceSq(x, y, force)
    local state = NPCWorldSnapshotBridge.Get(force == true)
    local best = nil
    local px = tonumber(x) or 0
    local py = tonumber(y) or 0
    local n = tonumber(state.playerCount) or 0
    local xs = state.playerX or {}
    local ys = state.playerY or {}
    for i = 1, n do
        local sx = xs[i]
        local sy = ys[i]
        if sx ~= nil and sy ~= nil then
            local dx = px - (tonumber(sx) or 0)
            local dy = py - (tonumber(sy) or 0)
            local d2 = dx * dx + dy * dy
            if not best or d2 < best then best = d2 end
        end
    end
    return best or 999999999999
end

function NPCWorldSnapshotBridge.GetNearestPlayerDistance(x, y, force)
    local d2 = NPCWorldSnapshotBridge.GetNearestPlayerDistanceSq(x, y, force == true)
    if not d2 or d2 >= 999999999999 then return 999999 end
    return math.sqrt(d2)
end

function NPCWorldSnapshotBridge.GetDiagnostics()
    local state = NPCWorldSnapshotBridge.Get(false)
    return {
        tick = state.tick,
        fps = state.fps,
        zoom = state.zoom,
        players = state.playerCount,
        denseArrays = state.playerX ~= nil,
        npc = state.npcCount,
        zombies = state.zombieCount,
        queue = state.queueCount,
        markers = state.markerCount,
        pendingSpawn = state.pendingSpawn,
        pendingTasks = state.pendingTasks
    }
end

NPCWorldSnapshotBridge.ApplySettings()
