-- NPCCheckpointsBridge.lua
-- Neutral shared backend for lightweight faction road checkpoints and tolls.
-- Checkpoints are virtual map entities: they do not spawn heavy NPC logic, but they gate roads through faction checks, disguise checks and toll payments.

NPCCheckpointsBridge = NPCCheckpointsBridge or {}

local BCP_RESOURCES = {
    {key="ammo", type="Base.9mmBullets", label="9mm rounds"},
    {key="food", type="Base.CannedFood", label="food"},
    {key="fuel", type="Base.PetrolCan", label="fuel can"},
    {key="medical", type="Base.Bandage", label="bandages"}
}

local function bcp_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        local ok, value = pcall(function() return NPCLegacySettingsBridge.GetBool(name, defaultValue == true) end)
        if ok and value ~= nil then return value == true end
    end
    return defaultValue == true
end

local function bcp_num(name, defaultValue, minValue, maxValue)
    local value = defaultValue
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        local ok, got = pcall(function() return NPCLegacySettingsBridge.GetNumber(name, defaultValue, minValue, maxValue) end)
        if ok and got ~= nil then value = got end
    end
    value = tonumber(value) or tonumber(defaultValue) or 0
    if minValue ~= nil and value < minValue then value = minValue end
    if maxValue ~= nil and value > maxValue then value = maxValue end
    return value
end

local function bcp_now()
    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then
            local ok, value = pcall(function() return gt:getWorldAgeHours() end)
            if ok and value then return tonumber(value) or 0 end
        end
    end
    return os.time and (os.time() / 3600) or 0
end

local function bcp_rand(maxValue)
    maxValue = math.floor(tonumber(maxValue) or 0)
    if maxValue <= 0 then return 0 end
    if ZombRand then
        local ok, value = pcall(function() return ZombRand(maxValue) end)
        if ok and value ~= nil then return tonumber(value) or 0 end
    end
    return math.random(0, maxValue - 1)
end

local function bcp_side(side)
    if NPCFactionBridge and NPCFactionBridge.NormalizeSide then
        local s = NPCFactionBridge.NormalizeSide(side)
        if s then return s end
    end
    side = tostring(side or ""):lower()
    if side == "red" or side == "green" or side == "blue" or side == "black" then return side end
    return nil
end

local function bcp_sideLabel(side)
    if NPCFactionBridge and NPCFactionBridge.GetSideLabel then
        local ok, label = pcall(function() return NPCFactionBridge.GetSideLabel(side) end)
        if ok and label then return tostring(label) end
    end
    return tostring(side or "unknown")
end

local function bcp_dist(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return math.sqrt(dx * dx + dy * dy)
end

local function bcp_playerId(player)
    if not player then return nil end
    if NPCUtils and NPCUtils.GetCharacterID then
        local ok, id = pcall(function() return NPCUtils.GetCharacterID(player) end)
        if ok and id ~= nil then return id end
    end
    if player.getOnlineID then
        local ok, id = pcall(function() return player:getOnlineID() end)
        if ok and id ~= nil then return id end
    end
    return nil
end

function NPCCheckpointsBridge.IsEnabled()
    return bcp_bool("Checkpoint_Enabled", true)
end

function NPCCheckpointsBridge.MaxActive()
    return math.floor(bcp_num("Checkpoint_MaxActive", 14, 0, 80))
end

function NPCCheckpointsBridge.InteractionRadius()
    return bcp_num("Checkpoint_InteractionRadius", 26, 4, 120)
end

function NPCCheckpointsBridge.MinSpacing()
    return bcp_num("Checkpoint_MinSpacing", 360, 60, 3000)
end

function NPCCheckpointsBridge.PassHours()
    return bcp_num("Checkpoint_PassHours", 8, 1, 168)
end

function NPCCheckpointsBridge.TollAmount()
    return math.floor(bcp_num("Checkpoint_TollAmount", 4, 0, 50))
end

function NPCCheckpointsBridge.NowHours()
    return bcp_now()
end

function NPCCheckpointsBridge.EnsureData(gmd)
    if not gmd then return nil end
    gmd.NPCCheckpointsBridge = gmd.NPCCheckpointsBridge or {}
    gmd.NPCCheckpointsBridge.active = gmd.NPCCheckpointsBridge.active or {}
    gmd.NPCCheckpointsBridge.history = gmd.NPCCheckpointsBridge.history or {}
    gmd.NPCCheckpointsBridge.playerPasses = gmd.NPCCheckpointsBridge.playerPasses or {}
    gmd.NPCCheckpointsBridge.stats = gmd.NPCCheckpointsBridge.stats or {created=0, passed=0, tolled=0, denied=0, forced=0}
    gmd.NPCCheckpointsBridge.nextId = tonumber(gmd.NPCCheckpointsBridge.nextId) or 1
    if not gmd.DebugMapMarkers then gmd.DebugMapMarkers = {} end
    return gmd.NPCCheckpointsBridge
end

function NPCCheckpointsBridge.ResourceByKey(key)
    key = tostring(key or "")
    for _, res in ipairs(BCP_RESOURCES) do
        if res.key == key or res.type == key then return res end
    end
    return nil
end

function NPCCheckpointsBridge.PickResource()
    local idx = 1 + bcp_rand(#BCP_RESOURCES)
    return BCP_RESOURCES[idx] or BCP_RESOURCES[1]
end

function NPCCheckpointsBridge.HasPayment(player, resourceKey, amount)
    amount = math.floor(tonumber(amount) or NPCCheckpointsBridge.TollAmount())
    if amount <= 0 then return true end
    local res = NPCCheckpointsBridge.ResourceByKey(resourceKey) or NPCCheckpointsBridge.PickResource()
    if not (player and res and res.type and player.getInventory) then return false end
    local inv = player:getInventory()
    if not inv or not inv.getItemCountFromTypeRecurse then return false end
    return (tonumber(inv:getItemCountFromTypeRecurse(res.type)) or 0) >= amount
end

function NPCCheckpointsBridge.TakePayment(player, resourceKey, amount)
    amount = math.floor(tonumber(amount) or NPCCheckpointsBridge.TollAmount())
    if amount <= 0 then return true end
    local res = NPCCheckpointsBridge.ResourceByKey(resourceKey) or NPCCheckpointsBridge.PickResource()
    if not (player and res and res.type and player.getInventory) then return false end
    local inv = player:getInventory()
    if not inv or not inv.getItemCountFromTypeRecurse or not inv.RemoveOneOf then return false end
    if (tonumber(inv:getItemCountFromTypeRecurse(res.type)) or 0) < amount then return false end
    for i=1, amount do
        local removed = false
        local before = tonumber(inv:getItemCountFromTypeRecurse(res.type)) or 0
        local ok = pcall(function() inv:RemoveOneOf(res.type, true) end)
        if ok and (tonumber(inv:getItemCountFromTypeRecurse(res.type)) or 0) < before then removed = true end
        if not removed then
            before = tonumber(inv:getItemCountFromTypeRecurse(res.type)) or 0
            ok = pcall(function() inv:RemoveOneOf(res.type, false) end)
            if ok and (tonumber(inv:getItemCountFromTypeRecurse(res.type)) or 0) < before then removed = true end
        end
        if not removed then return false end
    end
    return true
end

function NPCCheckpointsBridge.MakeId(data)
    if data and data.id then return tostring(data.id) end
    return "checkpoint_" .. tostring(bcp_now()) .. "_" .. tostring(bcp_rand(100000))
end

function NPCCheckpointsBridge.MakeCheckpoint(gmd, x, y, z, side, source)
    local data = NPCCheckpointsBridge.EnsureData(gmd)
    if not data then return nil end
    x = tonumber(x)
    y = tonumber(y)
    if not x or not y then return nil end
    side = bcp_side(side) or ((bcp_rand(2) == 0) and "red" or "green")
    local res = NPCCheckpointsBridge.PickResource()
    local id = "checkpoint_" .. tostring(data.nextId)
    data.nextId = (tonumber(data.nextId) or 1) + 1
    local cp = {
        id = id,
        markerId = id,
        x = math.floor(x),
        y = math.floor(y),
        z = tonumber(z) or 0,
        side = side,
        checkpointSide = side,
        status = "active",
        tollResource = res.key,
        tollType = res.type,
        tollLabel = res.label,
        tollAmount = NPCCheckpointsBridge.TollAmount(),
        source = source and source.source or "road",
        sourceId = source and source.sourceId or nil,
        createdAt = bcp_now(),
        updatedAt = bcp_now()
    }
    data.active[id] = cp
    data.stats.created = (tonumber(data.stats.created) or 0) + 1
    return cp
end

function NPCCheckpointsBridge.MakeMarker(cp)
    if not cp or not cp.id or not cp.x or not cp.y then return nil end
    local side = bcp_side(cp.side or cp.checkpointSide) or "red"
    local name = tostring(cp.name or (bcp_sideLabel(side) .. " checkpoint"))
    return {
        id = tostring(cp.markerId or cp.id),
        markerType = "checkpoint",
        name = name,
        x = tonumber(cp.x),
        y = tonumber(cp.y),
        z = tonumber(cp.z) or 0,
        factionSide = side,
        faction = side,
        side = side,
        checkpointId = cp.id,
        checkpointSide = side,
        checkpointStatus = cp.status or "active",
        tollResource = cp.tollResource,
        tollType = cp.tollType,
        tollLabel = cp.tollLabel,
        tollAmount = cp.tollAmount,
        hostile = side == "red",
        friendly = side == "green" or side == "blue",
        active = true,
        updatedAt = cp.updatedAt or bcp_now()
    }
end

function NPCCheckpointsBridge.FindCheckpoint(gmd, id)
    if not id then return nil end
    local data = NPCCheckpointsBridge.EnsureData(gmd)
    if not data then return nil end
    return data.active[tostring(id)] or data.active[tostring(id):gsub("^checkpoint_", "checkpoint_")]
end

function NPCCheckpointsBridge.FindNearest(gmd, x, y, radius)
    local data = NPCCheckpointsBridge.EnsureData(gmd)
    if not data then return nil, nil end
    radius = tonumber(radius) or NPCCheckpointsBridge.InteractionRadius()
    local best = nil
    local bestDist = radius + 0.001
    for _, cp in pairs(data.active) do
        if cp and cp.status ~= "removed" and cp.x and cp.y then
            local d = bcp_dist(x, y, cp.x, cp.y)
            if d <= bestDist then
                best = cp
                bestDist = d
            end
        end
    end
    return best, bestDist
end

function NPCCheckpointsBridge.HasNearby(gmd, x, y, radius)
    local cp = NPCCheckpointsBridge.FindNearest(gmd, x, y, radius or NPCCheckpointsBridge.MinSpacing())
    return cp ~= nil
end

function NPCCheckpointsBridge.GetPlayerPass(gmd, player, cp)
    local data = NPCCheckpointsBridge.EnsureData(gmd)
    local pid = bcp_playerId(player)
    if not data or not pid or not cp then return nil end
    local byPlayer = data.playerPasses[tostring(pid)]
    if type(byPlayer) ~= "table" then return nil end
    local untilAt = tonumber(byPlayer[tostring(cp.id)])
    if untilAt and untilAt > bcp_now() then return untilAt end
    byPlayer[tostring(cp.id)] = nil
    return nil
end

function NPCCheckpointsBridge.GrantPlayerPass(gmd, player, cp, reason)
    local data = NPCCheckpointsBridge.EnsureData(gmd)
    local pid = bcp_playerId(player)
    if not data or not pid or not cp then return nil end
    data.playerPasses[tostring(pid)] = data.playerPasses[tostring(pid)] or {}
    local untilAt = bcp_now() + NPCCheckpointsBridge.PassHours()
    data.playerPasses[tostring(pid)][tostring(cp.id)] = untilAt
    data.stats.passed = (tonumber(data.stats.passed) or 0) + 1
    cp.lastPassPlayerId = pid
    cp.lastPassReason = reason
    cp.updatedAt = bcp_now()
    return untilAt
end

function NPCCheckpointsBridge.GetSideLabel(side)
    return bcp_sideLabel(side)
end

function NPCCheckpointsBridge.Distance(x1, y1, x2, y2)
    return bcp_dist(x1, y1, x2, y2)
end
