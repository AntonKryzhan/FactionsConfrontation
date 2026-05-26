-- NPCCrowdBudgetBridge.lua
-- Neutral shared backend for crowd budget and spawn pressure control.

-- NPCCrowdBudgetBridge.lua
-- Safe light-load/crowd budget layer for city streaming pressure.
-- This intentionally does not delete physical NPC bodies. It only defers new
-- materialization and drip-feeds spawn batches when nearby NPC/zombie pressure is high.

require "NPCCore/NPCLegacyGlobalsBridge"

local NPC_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
NPCCrowdBudgetBridge = NPCCrowdBudgetBridge or {}

NPCCrowdBudgetBridge.VERSION = "2026-05-09-crowd-budget-1"
local function bcb_worldDirector()
    return NPCWorldDirector or NPC_LEGACY_GLOBALS.Get("WorldDirector") or nil
end

NPCCrowdBudgetBridge.Config = NPCCrowdBudgetBridge.Config or {
    enabled = true,
    debug = false,
    sampleTicks = 45,
    nearRadius = 180,
    zombieRadius = 140,
    maxNPCNearPlayer = 42,
    criticalNPCNearPlayer = 64,
    maxZombiesNearPlayer = 220,
    criticalZombiesNearPlayer = 360,
    retrySeconds = 12,
    criticalRetrySeconds = 24,
    dripFeedMaxBatch = 4,
    criticalDripFeedMaxBatch = 2,
    urbanTightenPercent = 20,
    fastTravelTightenPercent = 35,
    preserveCombat = true
}

NPCCrowdBudgetBridge.State = NPCCrowdBudgetBridge.State or {
    tick = 0,
    players = {},
    worst = {level = 0, name = "LOW", npc = 0, zombies = 0},
    lastLogMs = 0
}

local BCB_LEVEL_NAMES = {"LOW", "HIGH", "CRITICAL"}

local function bcb_number(name, defaultValue, minValue, maxValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        return NPCLegacySettingsBridge.GetNumber(name, defaultValue, minValue, maxValue)
    end
    local value = tonumber(defaultValue) or 0
    if minValue ~= nil and value < minValue then value = minValue end
    if maxValue ~= nil and value > maxValue then value = maxValue end
    return value
end

local function bcb_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        return NPCLegacySettingsBridge.GetBool(name, defaultValue == true)
    end
    return defaultValue == true
end

local function bcb_nowMs()
    if getTimestampMs then return getTimestampMs() end
    if getTimeInMillis then return getTimeInMillis() end
    if getGameTime then
        local ok, hours = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok and hours then return math.floor((tonumber(hours) or 0) * 3600000) end
    end
    return 0
end

local function bcb_getTick()
    if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.GetTick then
        local ok, tick = pcall(function() return NPCWorkSchedulerBridge.GetTick() end)
        if ok and tick then return tonumber(tick) or 0 end
    end
    return tonumber(NPCCrowdBudgetBridge.State.tick) or 0
end

local function bcb_dist2(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return dx * dx + dy * dy
end

local function bcb_count(tbl)
    if type(tbl) ~= "table" then return 0 end
    local n = #tbl
    if n and n > 0 then return n end
    n = 0
    for _, _ in pairs(tbl) do n = n + 1 end
    return n
end

local function bcb_playerKey(player, index)
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

local function bcb_eachPlayer(callback)
    if type(callback) ~= "function" then return end

    if getOnlinePlayers then
        local ok, players = pcall(function() return getOnlinePlayers() end)
        if ok and players then
            for i = 0, players:size() - 1 do
                local player = players:get(i)
                if player and not (player.isDead and player:isDead()) then
                    callback(player, i)
                end
            end
            return
        end
    end

    if getNumActivePlayers and getSpecificPlayer then
        local ok, count = pcall(function() return getNumActivePlayers() end)
        count = ok and tonumber(count) or 1
        for i = 0, math.max(0, count - 1) do
            local player = getSpecificPlayer(i)
            if player and not (player.isDead and player:isDead()) then
                callback(player, i)
            end
        end
        return
    end

    if getSpecificPlayer then
        local player = getSpecificPlayer(0)
        if player and not (player.isDead and player:isDead()) then
            callback(player, 0)
        end
    elseif getPlayer then
        local player = getPlayer()
        if player and not (player.isDead and player:isDead()) then
            callback(player, 0)
        end
    end
end

local function bcb_isUrban(player)
    if not player or not player.getSquare then return false end
    local square = nil
    local ok = pcall(function() square = player:getSquare() end)
    if not ok or not square then return false end

    local zone = nil
    pcall(function() zone = square:getZone() end)
    if zone and zone.getType then
        local ztype = tostring(zone:getType() or "")
        local low = string.lower(ztype)
        if ztype == "TownZone" or ztype == "Nav" or ztype == "TrailerPark" or string.find(low, "town", 1, true) or string.find(low, "city", 1, true) then
            return true
        end
    end

    local room = nil
    pcall(function() room = square:getRoom() end)
    if room then return true end

    local building = nil
    pcall(function() building = square:getBuilding() end)
    return building ~= nil
end

local function bcb_isFastTravel(player)
    if NPCStreamingRuntimeBridge and NPCStreamingRuntimeBridge.State and NPCStreamingRuntimeBridge.State.fastTravel then
        return true
    end
    if not player or not player.getVehicle or not player.getX then return false end

    local vehicle = false
    pcall(function() vehicle = player:getVehicle() ~= nil end)
    if not vehicle then return false end

    local key = bcb_playerKey(player, 0)
    local tick = bcb_getTick()
    local px = tonumber(player:getX()) or 0
    local py = tonumber(player:getY()) or 0
    local state = NPCCrowdBudgetBridge.State.players[key]
    if not state or not state.lastMoveX then return false end

    local dt = math.max(1, tick - (tonumber(state.lastMoveTick) or tick))
    local dist = math.sqrt(bcb_dist2(px, py, state.lastMoveX, state.lastMoveY))
    local speed = dist / math.max(0.1, dt / 60.0)
    return speed >= 8.0
end

local function bcb_countNPCNearPlayer(player, radius, limit)
    if not player then return 0 end
    local worldDirector = bcb_worldDirector()
    if worldDirector and worldDirector.CountPhysicalNPCNearPlayer then
        local ok, n = pcall(function() return worldDirector.CountPhysicalNPCNearPlayer(player, radius) end)
        if ok and n then return tonumber(n) or 0 end
    end

    local gmd = nil
    if GetNPCModData then pcall(function() gmd = GetNPCModData() end) end
    if not (gmd and type(gmd.Queue) == "table" and player.getX and player.getY) then return 0 end

    local px = tonumber(player:getX()) or 0
    local py = tonumber(player:getY()) or 0
    local r = tonumber(radius) or 180
    local r2 = r * r
    local count = 0

    for _, brain in pairs(gmd.Queue) do
        if type(brain) == "table" then
            local x = brain.debugCoords and tonumber(brain.debugCoords.x) or tonumber(brain.x)
            local y = brain.debugCoords and tonumber(brain.debugCoords.y) or tonumber(brain.y)
            if not x and brain.bornCoords then x = tonumber(brain.bornCoords.x) end
            if not y and brain.bornCoords then y = tonumber(brain.bornCoords.y) end
            if x and y and bcb_dist2(x, y, px, py) <= r2 then
                count = count + 1
                if limit and count >= limit then return count end
            end
        end
    end

    return count
end

local function bcb_countZombiesNearPlayer(player, radius, limit)
    if not player or not player.getX or not player.getY then return 0 end

    local px = tonumber(player:getX()) or 0
    local py = tonumber(player:getY()) or 0
    local r = tonumber(radius) or 140
    local r2 = r * r
    local count = 0

    -- Do not scan getCell():getZombieList() here. In MP/coop that Java list can
    -- shrink between size() and get(i), and Kahlua logs IndexOutOfBounds even
    -- inside pcall(). Use the mod's lightweight zombie cache when available and
    -- otherwise skip zombie pressure rather than opening the Lua error window.
    local cache = NPCZombieCacheBridge and NPCZombieCacheBridge.CacheLightZ
    if type(cache) ~= "table" then return 0 end

    for _, data in pairs(cache) do
        local zx = nil
        local zy = nil
        if type(data) == "table" then
            zx = tonumber(data.x)
            zy = tonumber(data.y)
        elseif data and data.getX and data.getY then
            local okX, x = pcall(function() return data:getX() end)
            local okY, y = pcall(function() return data:getY() end)
            if okX then zx = tonumber(x) end
            if okY then zy = tonumber(y) end
        end

        if zx and zy and bcb_dist2(zx, zy, px, py) <= r2 then
            count = count + 1
            if limit and count >= limit then return count end
        end
    end

    return count
end

function NPCCrowdBudgetBridge.ApplySettings()
    local c = NPCCrowdBudgetBridge.Config
    c.enabled = bcb_bool("CrowdBudget_Enabled", c.enabled ~= false)
    c.debug = bcb_bool("CrowdBudget_Debug", c.debug == true)
    c.sampleTicks = bcb_number("CrowdBudget_SampleTicks", c.sampleTicks or 45, 5, 300)
    c.nearRadius = bcb_number("CrowdBudget_NearRadius", c.nearRadius or 180, 40, 800)
    c.zombieRadius = bcb_number("CrowdBudget_ZombieRadius", c.zombieRadius or 140, 40, 800)
    c.maxNPCNearPlayer = bcb_number("CrowdBudget_MaxNPCNearPlayer", c.maxNPCNearPlayer or 42, 1, 500)
    c.criticalNPCNearPlayer = bcb_number("CrowdBudget_CriticalNPCNearPlayer", c.criticalNPCNearPlayer or 64, c.maxNPCNearPlayer or 42, 1000)
    c.maxZombiesNearPlayer = bcb_number("CrowdBudget_MaxZombiesNearPlayer", c.maxZombiesNearPlayer or 220, 0, 2000)
    c.criticalZombiesNearPlayer = bcb_number("CrowdBudget_CriticalZombiesNearPlayer", c.criticalZombiesNearPlayer or 360, c.maxZombiesNearPlayer or 220, 4000)
    c.retrySeconds = bcb_number("CrowdBudget_RetrySeconds", c.retrySeconds or 12, 1, 300)
    c.criticalRetrySeconds = bcb_number("CrowdBudget_CriticalRetrySeconds", c.criticalRetrySeconds or 24, 1, 600)
    c.dripFeedMaxBatch = bcb_number("CrowdBudget_DripFeedMaxBatch", c.dripFeedMaxBatch or 4, 1, 50)
    c.criticalDripFeedMaxBatch = bcb_number("CrowdBudget_CriticalDripFeedMaxBatch", c.criticalDripFeedMaxBatch or 2, 1, 50)
    c.urbanTightenPercent = bcb_number("CrowdBudget_UrbanTightenPercent", c.urbanTightenPercent or 20, 0, 90)
    c.fastTravelTightenPercent = bcb_number("CrowdBudget_FastTravelTightenPercent", c.fastTravelTightenPercent or 35, 0, 90)
    c.preserveCombat = bcb_bool("CrowdBudget_PreserveCombat", c.preserveCombat ~= false)
end

local function bcb_effectiveCap(baseCap, urban, fastTravel)
    local cap = tonumber(baseCap) or 0
    local c = NPCCrowdBudgetBridge.Config
    if urban then
        cap = math.floor(cap * (100 - (tonumber(c.urbanTightenPercent) or 0)) / 100)
    end
    if fastTravel then
        cap = math.floor(cap * (100 - (tonumber(c.fastTravelTightenPercent) or 0)) / 100)
    end
    return math.max(4, cap)
end

local function bcb_samplePlayer(player, key)
    local c = NPCCrowdBudgetBridge.Config
    key = key or bcb_playerKey(player, 0)
    local tick = bcb_getTick()
    local urban = bcb_isUrban(player)
    local fastTravel = bcb_isFastTravel(player)

    local npcCap = bcb_effectiveCap(c.maxNPCNearPlayer, urban, fastTravel)
    local npcCritical = bcb_effectiveCap(c.criticalNPCNearPlayer, urban, fastTravel)
    if npcCritical < npcCap then npcCritical = npcCap end

    local zombieCap = bcb_effectiveCap(c.maxZombiesNearPlayer, urban, fastTravel)
    local zombieCritical = bcb_effectiveCap(c.criticalZombiesNearPlayer, urban, fastTravel)
    if zombieCritical < zombieCap then zombieCritical = zombieCap end

    local npc = bcb_countNPCNearPlayer(player, c.nearRadius, npcCritical + 1)
    local zombies = bcb_countZombiesNearPlayer(player, c.zombieRadius, zombieCritical + 1)

    local level = 0
    local reason = nil
    if npc >= npcCritical then
        level = 2
        reason = "npc_critical"
    elseif zombies >= zombieCritical and zombieCritical > 0 then
        level = 2
        reason = "zombie_critical"
    elseif npc >= npcCap then
        level = 1
        reason = "npc_high"
    elseif zombies >= zombieCap and zombieCap > 0 then
        level = 1
        reason = "zombie_high"
    end

    local px = 0
    local py = 0
    if player and player.getX then px = tonumber(player:getX()) or 0 end
    if player and player.getY then py = tonumber(player:getY()) or 0 end

    local state = {
        key = key,
        tick = tick,
        x = px,
        y = py,
        npc = npc,
        zombies = zombies,
        npcCap = npcCap,
        npcCritical = npcCritical,
        zombieCap = zombieCap,
        zombieCritical = zombieCritical,
        urban = urban,
        fastTravel = fastTravel,
        level = level,
        name = BCB_LEVEL_NAMES[level + 1] or "LOW",
        reason = reason,
        lastMoveX = px,
        lastMoveY = py,
        lastMoveTick = tick
    }

    local prev = NPCCrowdBudgetBridge.State.players[key]
    if prev then
        state.prevX = prev.x
        state.prevY = prev.y
    end

    NPCCrowdBudgetBridge.State.players[key] = state
    return state
end

function NPCCrowdBudgetBridge.GetPlayerState(player)
    if not NPCCrowdBudgetBridge.Config.enabled or not player then return nil end
    local key = bcb_playerKey(player, 0)
    local tick = bcb_getTick()
    local cached = NPCCrowdBudgetBridge.State.players[key]
    if cached and tick - (tonumber(cached.tick) or 0) < (tonumber(NPCCrowdBudgetBridge.Config.sampleTicks) or 45) then
        return cached
    end
    return bcb_samplePlayer(player, key)
end

function NPCCrowdBudgetBridge.SampleAll()
    if not NPCCrowdBudgetBridge.Config.enabled then
        NPCCrowdBudgetBridge.State.worst = {level = 0, name = "LOW", npc = 0, zombies = 0}
        return
    end

    local worst = {level = 0, name = "LOW", npc = 0, zombies = 0}
    bcb_eachPlayer(function(player, index)
        local state = bcb_samplePlayer(player, bcb_playerKey(player, index))
        if state and (tonumber(state.level) or 0) > (tonumber(worst.level) or 0) then
            worst = state
        elseif state and (tonumber(state.level) or 0) == (tonumber(worst.level) or 0) and (tonumber(state.npc) or 0) > (tonumber(worst.npc) or 0) then
            worst = state
        end
    end)
    NPCCrowdBudgetBridge.State.worst = worst

    if NPCCrowdBudgetBridge.Config.debug and (tonumber(worst.level) or 0) > 0 then
        local now = bcb_nowMs()
        if now - (tonumber(NPCCrowdBudgetBridge.State.lastLogMs) or 0) >= 5000 then
            NPCCrowdBudgetBridge.State.lastLogMs = now
            print("[NPCCrowdBudgetBridge] level=" .. tostring(worst.name) .. " npc=" .. tostring(worst.npc) .. "/" .. tostring(worst.npcCap) .. " zeds=" .. tostring(worst.zombies) .. "/" .. tostring(worst.zombieCap) .. " urban=" .. tostring(worst.urban) .. " fast=" .. tostring(worst.fastTravel) .. " reason=" .. tostring(worst.reason))
        end
    end
end

local function bcb_importantGroup(group)
    if not group then return false end
    if group.inBattle or group.virtualBattle or group.battleId or group.enemyGroupId then return true end
    if group.bountyHunter or group.targetClass == "bounty_hunt" then return true end
    if group.mercenaryHired or group.hired or group.isPlayerGuard or group.guardPlayer or group.followPlayer then return true end
    if group.leaderId or group.isFactionLeader then return true end
    return false
end

function NPCCrowdBudgetBridge.ShouldDeferActivation(group, player, budget)
    if not NPCCrowdBudgetBridge.Config.enabled then return nil end
    if not group or not player then return nil end
    if NPCCrowdBudgetBridge.Config.preserveCombat and bcb_importantGroup(group) then return nil end

    local worldDirector = bcb_worldDirector()
    if worldDirector and worldDirector.IsPlayerOnDebugMarker then
        local ok, onMarker = pcall(function() return worldDirector.IsPlayerOnDebugMarker(group, player) end)
        if ok and onMarker then return nil end
    end

    local state = NPCCrowdBudgetBridge.GetPlayerState(player)
    if not state then return nil end

    local members = 0
    if worldDirector and worldDirector.GetGroupMemberCount then
        local ok, n = pcall(function() return worldDirector.GetGroupMemberCount(group) end)
        members = ok and tonumber(n) or 0
    else
        members = type(group.members) == "table" and bcb_count(group.members) or tonumber(group.count) or 0
    end

    local projected = (tonumber(state.npc) or 0) + math.max(1, tonumber(members) or 1)
    if projected >= (tonumber(state.npcCritical) or 999999) then
        return "crowd_budget_npc_critical", (tonumber(NPCCrowdBudgetBridge.Config.criticalRetrySeconds) or 24) / 3600
    end
    if projected >= (tonumber(state.npcCap) or 999999) then
        return "crowd_budget_npc_cap", (tonumber(NPCCrowdBudgetBridge.Config.retrySeconds) or 12) / 3600
    end
    if (tonumber(state.zombies) or 0) >= (tonumber(state.zombieCritical) or 999999) and (tonumber(state.zombieCritical) or 0) > 0 then
        return "crowd_budget_zombie_critical", (tonumber(NPCCrowdBudgetBridge.Config.criticalRetrySeconds) or 24) / 3600
    end
    if (tonumber(state.zombies) or 0) >= (tonumber(state.zombieCap) or 999999) and (tonumber(state.zombieCap) or 0) > 0 then
        return "crowd_budget_zombie_cap", (tonumber(NPCCrowdBudgetBridge.Config.retrySeconds) or 12) / 3600
    end

    return nil
end

function NPCCrowdBudgetBridge.AdjustSpawnBatch(group, player, batch, totalMembers)
    batch = math.max(1, tonumber(batch) or 1)
    if not NPCCrowdBudgetBridge.Config.enabled then return batch end
    if NPCCrowdBudgetBridge.Config.preserveCombat and bcb_importantGroup(group) then return batch end

    local state = player and NPCCrowdBudgetBridge.GetPlayerState(player) or NPCCrowdBudgetBridge.State.worst
    local level = state and tonumber(state.level) or 0
    if level >= 2 then
        batch = math.min(batch, tonumber(NPCCrowdBudgetBridge.Config.criticalDripFeedMaxBatch) or 2)
    elseif level >= 1 then
        batch = math.min(batch, tonumber(NPCCrowdBudgetBridge.Config.dripFeedMaxBatch) or 4)
    end

    totalMembers = tonumber(totalMembers) or 0
    if totalMembers > 0 then batch = math.min(batch, totalMembers) end
    return math.max(1, math.floor(batch))
end

function NPCCrowdBudgetBridge.AdjustGlobalSpawnBatch(batch)
    batch = math.max(1, tonumber(batch) or 1)
    if not NPCCrowdBudgetBridge.Config.enabled then return batch end
    local worst = NPCCrowdBudgetBridge.State.worst
    local level = worst and tonumber(worst.level) or 0
    if level >= 2 then
        return math.max(1, math.min(batch, tonumber(NPCCrowdBudgetBridge.Config.criticalDripFeedMaxBatch) or 2))
    elseif level >= 1 then
        return math.max(1, math.min(batch, tonumber(NPCCrowdBudgetBridge.Config.dripFeedMaxBatch) or 4))
    end
    return batch
end

function NPCCrowdBudgetBridge.AdjustQueuedSpawnBatch(entry, batch)
    return NPCCrowdBudgetBridge.AdjustGlobalSpawnBatch(batch)
end

function NPCCrowdBudgetBridge.GetDiagnostics()
    local worst = NPCCrowdBudgetBridge.State.worst or {}
    return {
        level = worst.level or 0,
        pressure = worst.name or "LOW",
        npc = worst.npc or 0,
        npcCap = worst.npcCap or NPCCrowdBudgetBridge.Config.maxNPCNearPlayer,
        zombies = worst.zombies or 0,
        zombieCap = worst.zombieCap or NPCCrowdBudgetBridge.Config.maxZombiesNearPlayer,
        reason = worst.reason or ""
    }
end

function NPCCrowdBudgetBridge.OnTick()
    NPCCrowdBudgetBridge.State.tick = (tonumber(NPCCrowdBudgetBridge.State.tick) or 0) + 1
    local tick = bcb_getTick()
    if tick % 300 == 1 then
        NPCCrowdBudgetBridge.ApplySettings()
    end
    if tick - (tonumber(NPCCrowdBudgetBridge.State.lastSampleTick) or 0) >= (tonumber(NPCCrowdBudgetBridge.Config.sampleTicks) or 45) then
        NPCCrowdBudgetBridge.State.lastSampleTick = tick
        NPCCrowdBudgetBridge.SampleAll()
    end
end

NPCCrowdBudgetBridge.ApplySettings()

if Events and Events.OnTick and not NPCCrowdBudgetBridge._registered then
    NPCCrowdBudgetBridge._registered = true
    Events.OnTick.Add(NPCCrowdBudgetBridge.OnTick)
end
