-- NPCConvoysBridge.lua
-- Neutral shared backend for lightweight interactive supply convoys.
-- Convoys are virtual map entities, so they add player-facing objectives without spawning large NPC groups.

require "NPCCore/NPCLegacyGlobalsBridge"

NPCConvoysBridge = NPCConvoysBridge or {}

local BCV_RESOURCES = {"food", "medical", "ammo", "fuel", "materials", "weapons", "armor", "magazines"}
local function bcv_baseCampProvider()
    return NPCBaseCampServerBridge or NPCLegacyGlobalsBridge.Get("BaseCampSystem") or nil
end

local function bcv_baseSupplyProvider()
    return NPCBaseSupplyServerBridge or NPCLegacyGlobalsBridge.Get("BaseSupply") or nil
end

local BCV_RESOURCE_LABEL = {
    food = "Food",
    medical = "Medical",
    ammo = "Ammo",
    fuel = "Fuel",
    materials = "Materials",
    weapons = "Weapons",
    armor = "Armor",
    magazines = "Magazines"
}

local BCV_BASE_RESOURCE = {
    hospital = "medical",
    clinic = "medical",
    shop = "food",
    grocery = "food",
    police = "ammo",
    fire = "fuel",
    warehouse = "materials",
    school = "food",
    office = "materials"
}

local function bcv_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        local ok, value = pcall(function() return NPCLegacySettingsBridge.GetBool(name, defaultValue == true) end)
        if ok and value ~= nil then return value == true end
    end
    return defaultValue == true
end

local function bcv_num(name, defaultValue, minValue, maxValue)
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

local function bcv_now()
    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then
            local ok, value = pcall(function() return gt:getWorldAgeHours() end)
            if ok and value then return tonumber(value) or 0 end
        end
    end
    return os.time and (os.time() / 3600) or 0
end

local function bcv_rand(maxValue)
    maxValue = math.floor(tonumber(maxValue) or 0)
    if maxValue <= 0 then return 0 end
    if ZombRand then
        local ok, value = pcall(function() return ZombRand(maxValue) end)
        if ok and value ~= nil then return tonumber(value) or 0 end
    end
    return math.random(0, maxValue - 1)
end

local function bcv_dist(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return math.sqrt(dx * dx + dy * dy)
end

local function bcv_side(value)
    if NPCFactionBridge and NPCFactionBridge.NormalizeSide then
        local side = NPCFactionBridge.NormalizeSide(value)
        if side then return side end
    end
    value = tostring(value or ""):lower()
    if value == "friendly" then return "green" end
    if value == "hostile" then return "red" end
    if value == "red" or value == "green" or value == "blue" or value == "black" then return value end
    return nil
end

local function bcv_playerId(player)
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

local function bcv_playerName(player)
    if not player then return "player" end
    if player.getUsername then
        local ok, name = pcall(function() return player:getUsername() end)
        if ok and name then return tostring(name) end
    end
    if player.getFullName then
        local ok, name = pcall(function() return player:getFullName() end)
        if ok and name then return tostring(name) end
    end
    return "player"
end

local function bcv_playerSide(player)
    if NPCFactionBridge and NPCFactionBridge.GetPlayerSide then
        local ok, side = pcall(function() return NPCFactionBridge.GetPlayerSide(player) end)
        if ok and side then return bcv_side(side) or "blue" end
    end
    return "blue"
end

local function bcv_enemySide(side)
    side = bcv_side(side) or "blue"
    if side == "red" then return "green" end
    if side == "green" then return "red" end
    if side == "black" then return "red" end
    return "red"
end

local function bcv_isEnemy(a, b)
    a = bcv_side(a)
    b = bcv_side(b)
    if not a or not b then return false end
    if NPCFactionBridge and NPCFactionBridge.IsEnemySide then
        local ok, value = pcall(function() return NPCFactionBridge.IsEnemySide(a, b) end)
        if ok and value ~= nil then return value == true end
    end
    if a == "black" or b == "black" then return true end
    if a == "red" and b == "green" then return true end
    if a == "green" and b == "red" then return true end
    return false
end

local function bcv_baseSide(base)
    if not base then return nil end
    return bcv_side(base.owner or base.captureTeam or base.factionSide or base.faction or base.side)
end

local function bcv_baseName(base)
    return tostring(base and (base.name or base.title or base.baseName or ("Base " .. tostring(base.id or "?"))) or "base")
end

local function bcv_resourceForBase(base)
    local key = tostring(base and (base.baseType or base.type or base.kind) or "")
    return BCV_BASE_RESOURCE[key] or BCV_RESOURCES[1 + bcv_rand(#BCV_RESOURCES)] or "food"
end

local function bcv_getBaseCamps(gmd)
    local baseCampProvider = bcv_baseCampProvider()
    if baseCampProvider and baseCampProvider.GetBaseCamps then
        local ok, camps = pcall(function() return baseCampProvider.GetBaseCamps() end)
        if ok and type(camps) == "table" then return camps end
    end
    return gmd and gmd.BaseCamps or {}
end

local function bcv_makeFallbackPoint(x, y, minDist, maxDist)
    minDist = tonumber(minDist) or 500
    maxDist = tonumber(maxDist) or 1100
    if maxDist < minDist then maxDist = minDist end
    local dist = minDist + bcv_rand(maxDist - minDist + 1)
    local angle = (bcv_rand(6284) / 1000.0)
    return (tonumber(x) or 0) + math.cos(angle) * dist, (tonumber(y) or 0) + math.sin(angle) * dist, 0
end

function NPCConvoysBridge.IsEnabled()
    return bcv_bool("Convoy_Enabled", true)
end

function NPCConvoysBridge.NowHours()
    return bcv_now()
end

function NPCConvoysBridge.ResourceLabel(resource)
    return BCV_RESOURCE_LABEL[tostring(resource or "")] or tostring(resource or "Cargo")
end

function NPCConvoysBridge.EnsureData(gmd)
    if not gmd then return nil end
    gmd.NPCConvoysBridge = gmd.NPCConvoysBridge or {}
    gmd.NPCConvoysBridge.active = gmd.NPCConvoysBridge.active or {}
    gmd.NPCConvoysBridge.history = gmd.NPCConvoysBridge.history or {}
    gmd.NPCConvoysBridge.playerOps = gmd.NPCConvoysBridge.playerOps or {}
    gmd.NPCConvoysBridge.favor = gmd.NPCConvoysBridge.favor or {}
    gmd.NPCConvoysBridge.stats = gmd.NPCConvoysBridge.stats or {created=0, escorted=0, raided=0, expired=0}
    gmd.NPCConvoysBridge.nextId = tonumber(gmd.NPCConvoysBridge.nextId) or 1
    if not gmd.DebugMapMarkers then gmd.DebugMapMarkers = {} end
    return gmd.NPCConvoysBridge
end

function NPCConvoysBridge.PlayerId(player)
    return bcv_playerId(player)
end

function NPCConvoysBridge.PlayerSide(player)
    return bcv_playerSide(player)
end

function NPCConvoysBridge.FindBaseById(gmd, baseId)
    if not baseId then return nil end
    local camps = bcv_getBaseCamps(gmd)
    return camps and camps[tostring(baseId)] or nil
end

function NPCConvoysBridge.FindNearbyBase(gmd, x, y, baseId)
    local camps = bcv_getBaseCamps(gmd)
    if baseId and camps then
        local base = camps[tostring(baseId)]
        if base and base.x and base.y then
            return base, bcv_dist(x, y, base.x, base.y)
        end
    end

    local best = nil
    local bestDist = 999999
    for _, base in pairs(camps or {}) do
        if type(base) == "table" and base.x and base.y then
            local radius = (tonumber(base.radius) or 82) + bcv_num("Convoy_BaseInteractionPad", 18, 0, 120)
            local d = bcv_dist(x, y, base.x, base.y)
            if d <= radius and d < bestDist then
                best = base
                bestDist = d
            end
        end
    end
    return best, bestDist
end

function NPCConvoysBridge.CanUseBase(base, player)
    if not base then return false end
    local playerSide = bcv_playerSide(player)
    local side = bcv_baseSide(base) or playerSide
    if side == "black" then return false end
    if bcv_isEnemy(playerSide, side) then return false end
    return true
end

local function bcv_pickBaseDestination(gmd, originBase, side, preferEnemy)
    local camps = bcv_getBaseCamps(gmd)
    local best = nil
    local bestScore = nil
    for _, base in pairs(camps or {}) do
        if type(base) == "table" and base.x and base.y and tostring(base.id or "") ~= tostring(originBase and originBase.id or "") then
            local bs = bcv_baseSide(base)
            local ok = false
            if preferEnemy then
                ok = bcv_isEnemy(side, bs)
            else
                ok = (not bs) or bs == side or bs == "blue"
            end
            if ok then
                local d = bcv_dist(originBase.x, originBase.y, base.x, base.y)
                if d >= 450 and d <= bcv_num("Convoy_MaxRouteDistance", 3200, 600, 12000) then
                    local score = d + bcv_rand(380)
                    if not best or score < bestScore then
                        best = base
                        bestScore = score
                    end
                end
            end
        end
    end
    return best
end

function NPCConvoysBridge.ActiveCount(gmd)
    local data = NPCConvoysBridge.EnsureData(gmd)
    if not data then return 0 end
    local count = 0
    for _, convoy in pairs(data.active or {}) do
        if convoy and convoy.status == "active" then count = count + 1 end
    end
    return count
end

function NPCConvoysBridge.GetActiveOperation(gmd, player)
    local data = NPCConvoysBridge.EnsureData(gmd)
    local pid = bcv_playerId(player)
    if not data or not pid then return nil end
    local op = data.playerOps[tostring(pid)]
    if not op or op.status ~= "active" then return nil end
    local convoy = data.active[tostring(op.convoyId)]
    if not convoy or convoy.status == "completed" or convoy.status == "raided" or convoy.status == "expired" then
        data.playerOps[tostring(pid)] = nil
        return nil
    end
    return op, convoy
end

function NPCConvoysBridge.CreateFromBase(gmd, player, base, objective)
    if not NPCConvoysBridge.IsEnabled() then return nil, "disabled" end
    if not gmd or not player or not base then return nil, "bad_args" end
    local data = NPCConvoysBridge.EnsureData(gmd)
    if not data then return nil, "no_data" end
    if NPCConvoysBridge.ActiveCount(gmd) >= bcv_num("Convoy_MaxActive", 10, 1, 100) then return nil, "too_many" end

    local existing = NPCConvoysBridge.GetActiveOperation(gmd, player)
    if existing then return nil, "operation_active" end

    objective = tostring(objective or "escort")
    if objective ~= "escort" and objective ~= "raid" then objective = "escort" end

    local pid = tostring(bcv_playerId(player) or "0")
    local playerSide = bcv_playerSide(player)
    local side = bcv_baseSide(base) or playerSide
    local startX = tonumber(base.x) or (player.getX and player:getX()) or 0
    local startY = tonumber(base.y) or (player.getY and player:getY()) or 0
    local startZ = tonumber(base.z) or 0
    local destBase = nil
    local destX, destY, destZ = nil, nil, 0
    local cargoResource = bcv_resourceForBase(base)
    local cargoAmount = math.floor(bcv_num("Convoy_CargoAmount", 8, 1, 1000) + 0.5)

    if objective == "escort" then
        destBase = bcv_pickBaseDestination(gmd, base, side, false)
        if destBase then
            destX = tonumber(destBase.x) or startX
            destY = tonumber(destBase.y) or startY
            destZ = tonumber(destBase.z) or 0
            cargoResource = bcv_resourceForBase(destBase)
        else
            destX, destY, destZ = bcv_makeFallbackPoint(startX, startY, 650, 1250)
        end
    else
        side = bcv_enemySide(playerSide)
        destBase = bcv_pickBaseDestination(gmd, base, playerSide, true) or base
        destX = tonumber(base.x) or startX
        destY = tonumber(base.y) or startY
        destZ = tonumber(base.z) or 0
        startX, startY, startZ = bcv_makeFallbackPoint(destX, destY, 650, 1300)
        cargoResource = BCV_RESOURCES[1 + bcv_rand(#BCV_RESOURCES)] or "ammo"
        cargoAmount = math.floor(bcv_num("Convoy_RaidCargoAmount", cargoAmount, 1, 1000) + 0.5)
    end

    local distance = bcv_dist(startX, startY, destX, destY)
    if distance < 1 then distance = 1 end

    local id = tostring(data.nextId)
    data.nextId = data.nextId + 1

    local now = bcv_now()
    local convoy = {
        id = id,
        markerId = "convoy_" .. id,
        objective = objective,
        status = "active",
        side = side,
        factionSide = side,
        originBaseId = base.id,
        originName = bcv_baseName(base),
        targetBaseId = destBase and destBase.id or nil,
        targetName = destBase and bcv_baseName(destBase) or "field drop",
        x = startX,
        y = startY,
        z = startZ,
        originX = startX,
        originY = startY,
        originZ = startZ,
        destX = destX,
        destY = destY,
        destZ = destZ,
        distance = distance,
        progress = 0,
        cargoResource = cargoResource,
        cargoLabel = NPCConvoysBridge.ResourceLabel(cargoResource),
        cargoAmount = cargoAmount,
        playerId = pid,
        playerName = bcv_playerName(player),
        createdAt = now,
        updatedAt = now,
        expiresAt = now + bcv_num("Convoy_ExpireHours", 18, 1, 168),
        speedTilesPerHour = bcv_num("Convoy_MoveSpeedTilesPerHour", 92, 5, 600)
    }

    if objective == "escort" then
        convoy.title = "Escort convoy"
        convoy.text = "Escort " .. convoy.cargoLabel .. " convoy from " .. tostring(convoy.originName) .. " to " .. tostring(convoy.targetName) .. "."
    else
        convoy.title = "Raid convoy"
        convoy.text = "Enemy " .. convoy.cargoLabel .. " convoy spotted near " .. tostring(base.name or base.id or "base") .. ". Intercept it before it arrives."
    end

    data.active[id] = convoy
    data.playerOps[pid] = {convoyId=id, objective=objective, status="active", createdAt=now}
    data.stats.created = (tonumber(data.stats.created) or 0) + 1
    return convoy, nil
end

function NPCConvoysBridge.Tick(gmd)
    local data = NPCConvoysBridge.EnsureData(gmd)
    if not data then return {} end
    local now = bcv_now()
    local changed = {}

    for id, convoy in pairs(data.active or {}) do
        if type(convoy) == "table" and convoy.status == "active" then
            local last = tonumber(convoy.updatedAt) or now
            local dt = now - last
            if dt < 0 then dt = 0 end
            convoy.updatedAt = now

            local distance = tonumber(convoy.distance) or bcv_dist(convoy.originX, convoy.originY, convoy.destX, convoy.destY)
            if distance < 1 then distance = 1 end
            local speed = tonumber(convoy.speedTilesPerHour) or bcv_num("Convoy_MoveSpeedTilesPerHour", 92, 5, 600)
            convoy.progress = (tonumber(convoy.progress) or 0) + ((speed * dt) / distance)
            if convoy.progress > 1 then convoy.progress = 1 end

            local p = convoy.progress
            convoy.x = (tonumber(convoy.originX) or 0) + ((tonumber(convoy.destX) or 0) - (tonumber(convoy.originX) or 0)) * p
            convoy.y = (tonumber(convoy.originY) or 0) + ((tonumber(convoy.destY) or 0) - (tonumber(convoy.originY) or 0)) * p
            convoy.z = tonumber(convoy.originZ) or tonumber(convoy.destZ) or 0

            if now >= (tonumber(convoy.expiresAt) or (now + 1)) then
                convoy.status = "expired"
                convoy.completedAt = now
                data.history[id] = convoy
                data.active[id] = nil
                data.stats.expired = (tonumber(data.stats.expired) or 0) + 1
            elseif convoy.progress >= 1 then
                convoy.status = "arrived"
                convoy.x = tonumber(convoy.destX) or convoy.x
                convoy.y = tonumber(convoy.destY) or convoy.y
            end
            changed[#changed + 1] = convoy
        elseif type(convoy) == "table" and convoy.status == "arrived" then
            convoy.updatedAt = now
            changed[#changed + 1] = convoy
            if convoy.objective == "raid" and now - (tonumber(convoy.createdAt) or now) > bcv_num("Convoy_ArrivedKeepHours", 2, 0, 48) then
                convoy.status = "expired"
                convoy.completedAt = now
                data.history[id] = convoy
                data.active[id] = nil
                data.stats.expired = (tonumber(data.stats.expired) or 0) + 1
            end
        end
    end

    return changed
end

function NPCConvoysBridge.FindNearest(gmd, player, radius, includeFriendly)
    local data = NPCConvoysBridge.EnsureData(gmd)
    if not data or not player then return nil, nil end
    local x = player.getX and player:getX() or 0
    local y = player.getY and player:getY() or 0
    local playerSide = bcv_playerSide(player)
    radius = tonumber(radius) or bcv_num("Convoy_InteractionRadius", 28, 2, 200)

    local best = nil
    local bestDist = radius + 0.001
    for _, convoy in pairs(data.active or {}) do
        if type(convoy) == "table" and (convoy.status == "active" or convoy.status == "arrived") and convoy.x and convoy.y then
            local ok = includeFriendly == true or bcv_isEnemy(playerSide, convoy.side) or tostring(convoy.playerId or "") == tostring(bcv_playerId(player) or "")
            if ok then
                local d = bcv_dist(x, y, convoy.x, convoy.y)
                if d <= bestDist then
                    best = convoy
                    bestDist = d
                end
            end
        end
    end
    return best, bestDist
end

function NPCConvoysBridge.AddFavor(gmd, player, side, amount)
    local data = NPCConvoysBridge.EnsureData(gmd)
    local pid = tostring(bcv_playerId(player) or "")
    if pid == "" or not data then return 0 end
    side = tostring(side or "neutral")
    amount = math.floor((tonumber(amount) or 0) + 0.5)
    data.favor[pid] = data.favor[pid] or {}
    data.favor[pid][side] = (tonumber(data.favor[pid][side]) or 0) + amount

    if gmd.ContractReputation then
        gmd.ContractReputation[pid] = gmd.ContractReputation[pid] or {}
        gmd.ContractReputation[pid][side] = (tonumber(gmd.ContractReputation[pid][side]) or 0) + amount
    end
    return amount
end

local function bcv_addBaseStock(base, resource, amount)
    if type(base) ~= "table" then return false end
    resource = tostring(resource or "food")
    amount = math.floor((tonumber(amount) or 0) + 0.5)
    if amount <= 0 then return false end
    base.stock = base.stock or {}
    base.donatedStock = base.donatedStock or {}
    base.stock[resource] = (tonumber(base.stock[resource]) or tonumber(base["stock" .. string.upper(string.sub(resource, 1, 1)) .. string.sub(resource, 2)]) or 0) + amount
    base.donatedStock[resource] = (tonumber(base.donatedStock[resource]) or 0) + amount
    local baseSupplyProvider = bcv_baseSupplyProvider()
    if baseSupplyProvider and baseSupplyProvider.SyncBaseFields then pcall(function() baseSupplyProvider.SyncBaseFields(base) end) end
    return true
end

function NPCConvoysBridge.CompleteEscort(gmd, player)
    local data = NPCConvoysBridge.EnsureData(gmd)
    local op, convoy = NPCConvoysBridge.GetActiveOperation(gmd, player)
    if not op or not convoy then return nil, "no_operation" end
    if convoy.objective ~= "escort" then return nil, "not_escort" end
    if convoy.status ~= "arrived" then return convoy, "not_arrived" end

    local radius = bcv_num("Convoy_InteractionRadius", 28, 2, 200)
    local px = player.getX and player:getX() or 0
    local py = player.getY and player:getY() or 0
    if bcv_dist(px, py, convoy.x, convoy.y) > radius then return convoy, "too_far" end

    local targetBase = NPCConvoysBridge.FindBaseById(gmd, convoy.targetBaseId)
    bcv_addBaseStock(targetBase, convoy.cargoResource, convoy.cargoAmount)

    convoy.status = "completed"
    convoy.completedAt = bcv_now()
    data.history[tostring(convoy.id)] = convoy
    data.active[tostring(convoy.id)] = nil
    data.playerOps[tostring(op.playerId or bcv_playerId(player))] = nil
    data.playerOps[tostring(bcv_playerId(player) or "")] = nil
    data.stats.escorted = (tonumber(data.stats.escorted) or 0) + 1
    NPCConvoysBridge.AddFavor(gmd, player, convoy.side, bcv_num("Convoy_EscortRewardFavor", 4, 0, 1000))
    return convoy, nil
end

local function bcv_givePlayerLoot(player, resource, amount)
    if not player or not player.getInventory then return 0 end
    local inv = nil
    local okInv, got = pcall(function() return player:getInventory() end)
    if okInv then inv = got end
    if not inv or not inv.AddItem then return 0 end

    local itemPools = {
        food = {"Base.CannedChili", "Base.CannedCorn", "Base.CannedCornedBeef"},
        medical = {"Base.Bandage", "Base.AlcoholWipes"},
        ammo = {"Base.Bullets9mmBox", "Base.ShotgunShellsBox", "Base.Bullets45Box"},
        fuel = {"Base.PetrolCan"},
        materials = {"Base.Nails", "Base.NailsBox", "Base.Plank"},
        weapons = {"Base.KitchenKnife", "Base.Axe", "Base.Pistol"},
        armor = {"Base.Vest_BulletPolice"},
        magazines = {"Base.9mmClip", "Base.45Clip"}
    }

    local pool = itemPools[tostring(resource or "")] or itemPools.food
    local added = 0
    local count = math.max(1, math.min(tonumber(amount) or 1, bcv_num("Convoy_MaxLootItems", 8, 1, 80)))
    for i = 1, count do
        local fullType = pool[1 + bcv_rand(#pool)] or pool[1]
        local ok = pcall(function() inv:AddItem(fullType) end)
        if ok then added = added + 1 end
    end
    return added
end

function NPCConvoysBridge.RaidConvoy(gmd, player, convoyId)
    local data = NPCConvoysBridge.EnsureData(gmd)
    if not data or not player then return nil, "no_data" end
    local convoy = nil
    if convoyId then convoy = data.active[tostring(convoyId)] end
    if not convoy then convoy = NPCConvoysBridge.FindNearest(gmd, player, bcv_num("Convoy_InteractionRadius", 28, 2, 200), false) end
    if not convoy then return nil, "no_convoy" end

    local px = player.getX and player:getX() or 0
    local py = player.getY and player:getY() or 0
    if bcv_dist(px, py, convoy.x, convoy.y) > bcv_num("Convoy_InteractionRadius", 28, 2, 200) then return convoy, "too_far" end
    if not bcv_isEnemy(bcv_playerSide(player), convoy.side) then return convoy, "not_enemy" end

    local successChance = bcv_num("Convoy_RaidSuccessChance", 72, 0, 100)
    local roll = bcv_rand(100) + 1
    if roll > successChance then
        convoy.lastRaidAt = bcv_now()
        convoy.raidAttempts = (tonumber(convoy.raidAttempts) or 0) + 1
        return convoy, "failed"
    end

    local lootCount = bcv_givePlayerLoot(player, convoy.cargoResource, convoy.cargoAmount)
    convoy.status = "raided"
    convoy.completedAt = bcv_now()
    convoy.raidedBy = tostring(bcv_playerId(player) or "")
    convoy.lootItemsGiven = lootCount
    data.history[tostring(convoy.id)] = convoy
    data.active[tostring(convoy.id)] = nil
    data.stats.raided = (tonumber(data.stats.raided) or 0) + 1
    NPCConvoysBridge.AddFavor(gmd, player, bcv_playerSide(player), bcv_num("Convoy_RaidRewardFavor", 2, 0, 1000))
    return convoy, nil
end

function NPCConvoysBridge.MakeMarker(convoy)
    if type(convoy) ~= "table" or not convoy.x or not convoy.y then return nil end
    return {
        id = tostring(convoy.markerId or ("convoy_" .. tostring(convoy.id))),
        markerType = "convoy",
        convoyId = tostring(convoy.id or ""),
        convoyObjective = convoy.objective,
        convoyStatus = convoy.status,
        x = convoy.x,
        y = convoy.y,
        z = convoy.z or 0,
        destX = convoy.destX,
        destY = convoy.destY,
        side = convoy.side,
        factionSide = convoy.side,
        faction = convoy.side,
        owner = convoy.side,
        cargoResource = convoy.cargoResource,
        cargoLabel = convoy.cargoLabel,
        cargoAmount = convoy.cargoAmount,
        progress = convoy.progress,
        targetName = convoy.targetName,
        originName = convoy.originName,
        playerId = convoy.playerId,
        hostile = convoy.objective == "raid",
        friendly = convoy.objective == "escort",
        name = convoy.title or "Convoy",
        updatedAt = bcv_now()
    }
end

function NPCConvoysBridge.OperationText(op, convoy)
    if not convoy then return "No active convoy operation" end
    local progress = math.floor(((tonumber(convoy.progress) or 0) * 100) + 0.5)
    if convoy.objective == "escort" then
        if convoy.status == "arrived" then return "Escort convoy arrived. Meet it and complete delivery." end
        return "Escort " .. tostring(convoy.cargoLabel or convoy.cargoResource or "cargo") .. " convoy: " .. tostring(progress) .. "%"
    end
    if convoy.status == "arrived" then return "Enemy convoy arrived. Last chance to raid." end
    return "Raid enemy " .. tostring(convoy.cargoLabel or convoy.cargoResource or "cargo") .. " convoy: " .. tostring(progress) .. "%"
end
