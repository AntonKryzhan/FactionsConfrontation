-- NPCFactionEconomyServerBridge.lua
-- Neutral server backend for base economy and convoy mission planning.
-- Keeps strategic motivation isolated from spawn/materialization: bases own stock,
-- economy creates virtual missions, and existing virtual groups/convoys receive
-- lightweight objectives without forcing real NPC spawn.

if not isServer() then return end

NPCFactionEconomyServerBridge = NPCFactionEconomyServerBridge or {}

NPCFactionEconomyServerBridge.Enabled = true
NPCFactionEconomyServerBridge.Version = 2
NPCFactionEconomyServerBridge.UPDATE_HOURS = NPCFactionEconomyServerBridge.UPDATE_HOURS or 0.10
NPCFactionEconomyServerBridge.MISSION_RADIUS = NPCFactionEconomyServerBridge.MISSION_RADIUS or 96
NPCFactionEconomyServerBridge.MAX_ACTIVE_MISSIONS_PER_SIDE = NPCFactionEconomyServerBridge.MAX_ACTIVE_MISSIONS_PER_SIDE or 8
NPCFactionEconomyServerBridge.MAX_NEW_MISSIONS_PER_UPDATE = NPCFactionEconomyServerBridge.MAX_NEW_MISSIONS_PER_UPDATE or 3
NPCFactionEconomyServerBridge.MIN_SUPPLY_CARGO = NPCFactionEconomyServerBridge.MIN_SUPPLY_CARGO or 8
NPCFactionEconomyServerBridge.MAX_SUPPLY_CARGO = NPCFactionEconomyServerBridge.MAX_SUPPLY_CARGO or 85
NPCFactionEconomyServerBridge.CONVOY_ASSIGN_RADIUS = NPCFactionEconomyServerBridge.CONVOY_ASSIGN_RADIUS or 2600
NPCFactionEconomyServerBridge.RAID_SEARCH_RADIUS = NPCFactionEconomyServerBridge.RAID_SEARCH_RADIUS or 3400
NPCFactionEconomyServerBridge._tick = NPCFactionEconomyServerBridge._tick or 0

local BFE_RESOURCES = {"food", "water", "ammo", "medical", "fuel", "materials", "tools", "weapons", "spareParts", "supplies", "clothing", "armor", "magazines", "weaponParts", "maintenance"}

local BFE_RESOURCE_LABEL = {
    food = "F",
    water = "W",
    ammo = "A",
    medical = "M",
    fuel = "U",
    materials = "R",
    tools = "T",
    weapons = "G",
    spareParts = "P",
    supplies = "S",
    clothing = "C",
    armor = "B",
    magazines = "M",
    weaponParts = "P",
    maintenance = "N"
}

local BFE_BASE_CAPACITY = {
    food = 420,
    water = 420,
    ammo = 360,
    medical = 260,
    fuel = 220,
    materials = 480,
    tools = 180,
    weapons = 160,
    spareParts = 220,
    supplies = 420,
    clothing = 220,
    armor = 140,
    magazines = 260,
    weaponParts = 190,
    maintenance = 140
}

local BFE_TARGET_PER_POP = {
    food = 7.0,
    water = 7.0,
    ammo = 6.0,
    medical = 3.0,
    fuel = 2.5,
    materials = 4.0,
    tools = 1.2,
    weapons = 1.0,
    spareParts = 2.0,
    supplies = 5.0,
    clothing = 0.9,
    armor = 0.45,
    magazines = 2.2,
    weaponParts = 0.7,
    maintenance = 0.6
}

local BFE_BASELINE_TARGET = {
    food = 35,
    water = 35,
    ammo = 24,
    medical = 18,
    fuel = 16,
    materials = 30,
    tools = 8,
    weapons = 6,
    spareParts = 12,
    supplies = 24,
    clothing = 8,
    armor = 5,
    magazines = 12,
    weaponParts = 6,
    maintenance = 5
}

local BFE_CONSUMPTION_PER_POP_HOUR = {
    food = 0.36,
    water = 0.38,
    ammo = 0.055,
    medical = 0.018,
    fuel = 0.012,
    materials = 0.010,
    tools = 0.002,
    weapons = 0.001,
    spareParts = 0.006,
    supplies = 0.030,
    clothing = 0.003,
    armor = 0.002,
    magazines = 0.020,
    weaponParts = 0.004,
    maintenance = 0.004
}

local BFE_BASE_PRODUCTION_PER_HOUR = {
    hospital = {medical=12, supplies=2, water=1, clothing=1},
    shop = {food=11, water=6, supplies=5, clothing=3},
    school = {food=3, water=3, medical=1, supplies=2, clothing=1},
    police = {ammo=9, weapons=2, magazines=3, weaponParts=1, armor=1, supplies=2},
    fire = {tools=5, fuel=4, medical=2, materials=2, maintenance=2},
    warehouse = {materials=12, spareParts=5, ammo=3, magazines=2, weaponParts=2, supplies=5},
    office = {supplies=6, tools=1, materials=2, clothing=1},
    city = {food=3, water=3, supplies=3, materials=2, clothing=1},
    urban = {food=2, water=2, supplies=2, materials=1}
}

local BFE_STRATEGIC_RESOURCE_BY_TYPE = {
    hospital = "medical",
    shop = "food",
    school = "supplies",
    police = "ammo",
    fire = "fuel",
    warehouse = "materials",
    office = "supplies",
    city = "food",
    urban = "supplies"
}

local function bfe_nowHours()
    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then
            local ok, value = pcall(function() return gt:getWorldAgeHours() end)
            if ok and value then return tonumber(value) or 0 end
        end
    end
    return 0
end

local function bfe_count(tbl)
    local count = 0
    if type(tbl) ~= "table" then return 0 end
    for _, _ in pairs(tbl) do count = count + 1 end
    return count
end

local function bfe_dist(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return math.sqrt(dx * dx + dy * dy)
end

local function bfe_clamp(value, minValue, maxValue)
    value = tonumber(value) or 0
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function bfe_sideForGroup(group)
    if group and group.hostile == false then return "green" end
    return "red"
end

local function bfe_hostileForSide(side)
    return side ~= "green"
end

local function bfe_otherSide(side)
    if side == "green" then return "red" end
    if side == "red" then return "green" end
    return nil
end

local function bfe_resourceCopy(source)
    local out = {}
    source = source or {}
    for _, resource in ipairs(BFE_RESOURCES) do
        out[resource] = math.max(0, tonumber(source[resource]) or 0)
    end
    return out
end

local function bfe_resourceSum(source)
    local total = 0
    source = source or {}
    for _, resource in ipairs(BFE_RESOURCES) do
        total = total + math.max(0, tonumber(source[resource]) or 0)
    end
    return total
end

local function bfe_addResource(target, resource, amount)
    if not target or not resource then return 0 end
    amount = tonumber(amount) or 0
    local maxValue = tonumber(BFE_BASE_CAPACITY[resource]) or 999
    target[resource] = bfe_clamp((tonumber(target[resource]) or 0) + amount, 0, maxValue)
    return target[resource]
end

local function bfe_removeResource(target, resource, amount)
    if not target or not resource then return 0 end
    amount = math.max(0, tonumber(amount) or 0)
    local have = math.max(0, tonumber(target[resource]) or 0)
    local taken = math.min(have, amount)
    target[resource] = have - taken
    return taken
end

local function bfe_pickCargoResource(cargo)
    local bestResource = nil
    local bestAmount = 0
    for _, resource in ipairs(BFE_RESOURCES) do
        local amount = tonumber(cargo and cargo[resource]) or 0
        if amount > bestAmount then
            bestAmount = amount
            bestResource = resource
        end
    end
    return bestResource, bestAmount
end

local function bfe_compactNeeds(economy)
    if not economy or type(economy.shortages) ~= "table" then return "ok" end
    local parts = {}
    for _, resource in ipairs(BFE_RESOURCES) do
        local status = economy.shortages[resource]
        if status == "critical" or status == "low" then
            table.insert(parts, tostring(BFE_RESOURCE_LABEL[resource] or string.sub(resource, 1, 1)) .. ":" .. status)
        end
    end
    if #parts == 0 then return "ok" end
    return table.concat(parts, " ")
end

function NPCFactionEconomyServerBridge.EnsureData()
    local gmd = GetNPCModData()
    if not gmd.FactionEconomy then
        gmd.FactionEconomy = {
            enabled = true,
            version = NPCFactionEconomyServerBridge.Version,
            initialized = false,
            nextMissionId = 1,
            lastUpdate = 0,
            missions = {},
            factions = {green={bases={}, missions={}}, red={bases={}, missions={}}}
        }
    end

    local data = gmd.FactionEconomy
    if data.enabled == nil then data.enabled = true end
    if not data.nextMissionId then data.nextMissionId = 1 end
    if type(data.missions) ~= "table" then data.missions = {} end
    if type(data.factions) ~= "table" then data.factions = {} end
    data.factions.green = data.factions.green or {bases={}, missions={}}
    data.factions.red = data.factions.red or {bases={}, missions={}}
    data.version = NPCFactionEconomyServerBridge.Version
    return gmd, data
end

function NPCFactionEconomyServerBridge.IsEnabled()
    local _, data = NPCFactionEconomyServerBridge.EnsureData()
    return NPCFactionEconomyServerBridge.Enabled == true and data.enabled ~= false
end

local function bfe_getBaseCamps(gmd)
    if NPCBaseCampSystem and NPCBaseCampSystem.GetBaseCamps then
        local ok, camps = pcall(function() return NPCBaseCampSystem.GetBaseCamps() end)
        if ok and type(camps) == "table" then return camps end
    end
    return gmd.BaseCamps or {}
end

local function bfe_syncBaseStockFields(base)
    if type(base) ~= "table" then return end
    local stock = base.stock or {}
    base.stockFood = math.floor((tonumber(stock.food) or 0) + 0.5)
    base.stockWater = math.floor((tonumber(stock.water) or 0) + 0.5)
    base.stockAmmo = math.floor((tonumber(stock.ammo) or 0) + 0.5)
    base.stockMedical = math.floor((tonumber(stock.medical) or 0) + 0.5)
    base.stockFuel = math.floor((tonumber(stock.fuel) or 0) + 0.5)
    base.stockMaterials = math.floor((tonumber(stock.materials) or 0) + 0.5)
    base.stockTools = math.floor((tonumber(stock.tools) or 0) + 0.5)
    base.stockWeapons = math.floor((tonumber(stock.weapons) or 0) + 0.5)
    base.stockSpareParts = math.floor((tonumber(stock.spareParts) or 0) + 0.5)
    base.stockSupplies = math.floor((tonumber(stock.supplies) or 0) + 0.5)
    base.stockClothing = math.floor((tonumber(stock.clothing) or 0) + 0.5)
    base.stockArmor = math.floor((tonumber(stock.armor) or 0) + 0.5)
    base.stockMagazines = math.floor((tonumber(stock.magazines) or 0) + 0.5)
    base.stockWeaponParts = math.floor((tonumber(stock.weaponParts) or 0) + 0.5)
    base.stockMaintenance = math.floor((tonumber(stock.maintenance) or 0) + 0.5)
end

function NPCFactionEconomyServerBridge.SyncBaseStockFields(base)
    bfe_syncBaseStockFields(base)
end

local function bfe_initialStockFor(base, resource)
    local baseType = tostring(base and base.baseType or "urban")
    local stock = 0
    if resource == "food" then stock = tonumber(base.stockFood) or 0 end
    if resource == "water" then stock = tonumber(base.stockWater) or 0 end
    if resource == "ammo" then stock = tonumber(base.stockAmmo) or 0 end
    if resource == "medical" then stock = tonumber(base.stockMedical) or 0 end
    if resource == "fuel" then stock = tonumber(base.stockFuel) or 0 end
    if resource == "materials" then stock = tonumber(base.stockMaterials) or 0 end
    if resource == "tools" then stock = tonumber(base.stockTools) or 0 end
    if resource == "weapons" then stock = tonumber(base.stockWeapons) or 0 end
    if resource == "spareParts" then stock = tonumber(base.stockSpareParts) or 0 end
    if resource == "supplies" then stock = tonumber(base.stockSupplies) or 0 end
    if resource == "clothing" then stock = tonumber(base.stockClothing) or 0 end
    if resource == "armor" then stock = tonumber(base.stockArmor) or 0 end
    if resource == "magazines" then stock = tonumber(base.stockMagazines) or 0 end
    if resource == "weaponParts" then stock = tonumber(base.stockWeaponParts) or 0 end
    if resource == "maintenance" then stock = tonumber(base.stockMaintenance) or 0 end

    if stock > 0 then return stock end

    local production = BFE_BASE_PRODUCTION_PER_HOUR[baseType] or BFE_BASE_PRODUCTION_PER_HOUR.urban or {}
    local strategicResource = BFE_STRATEGIC_RESOURCE_BY_TYPE[baseType] or "supplies"
    local seed = 12
    if resource == strategicResource then seed = seed + 35 end
    seed = seed + ((tonumber(production[resource]) or 0) * 2.0)
    if resource == "food" or resource == "water" then seed = seed + 12 end
    if resource == "supplies" then seed = seed + 10 end
    if resource == "ammo" or resource == "magazines" then seed = seed + 5 end
    if resource == "weapons" or resource == "armor" or resource == "weaponParts" then seed = seed + 3 end
    return math.floor(seed + 0.5)
end

local function bfe_ensureBaseStock(base)
    if type(base) ~= "table" then return nil end

    if type(base.stock) ~= "table" then
        base.stock = {}
    end

    for _, resource in ipairs(BFE_RESOURCES) do
        if base.stock[resource] == nil then
            base.stock[resource] = bfe_initialStockFor(base, resource)
        else
            base.stock[resource] = bfe_clamp(base.stock[resource], 0, tonumber(BFE_BASE_CAPACITY[resource]) or 999)
        end
    end

    base.stockInitialized = true
    bfe_syncBaseStockFields(base)
    return base.stock
end

local function bfe_groupBelongsToBase(group, base, side)
    if type(group) ~= "table" or type(base) ~= "table" then return false end
    if bfe_sideForGroup(group) ~= side then return false end
    if group.homeBaseId and tostring(group.homeBaseId) == tostring(base.id) then return true end
    if group.targetBaseId and tostring(group.targetBaseId) == tostring(base.id) then return true end
    if group.x and group.y and bfe_dist(group.x, group.y, base.x, base.y) <= (tonumber(base.radius) or 82) + 90 then return true end
    return false
end

local function bfe_basePopulation(gmd, base, side)
    local population = 0
    for _, group in pairs(gmd.VirtualGroups or {}) do
        if bfe_groupBelongsToBase(group, base, side) then
            population = population + math.max(1, tonumber(group.count) or 1)
        end
    end
    if side == "green" then
        population = math.max(population, tonumber(base.greenCount) or 0)
    else
        population = math.max(population, tonumber(base.redCount) or 0)
    end
    if population <= 0 and base.owner == side then population = 2 end
    return population
end

local function bfe_resourceTarget(base, resource, population)
    local baseline = tonumber(BFE_BASELINE_TARGET[resource]) or 0
    local perPop = tonumber(BFE_TARGET_PER_POP[resource]) or 0
    local strategicResource = BFE_STRATEGIC_RESOURCE_BY_TYPE[tostring(base.baseType or "urban")] or "supplies"
    local target = baseline + (math.max(1, tonumber(population) or 1) * perPop)
    if resource == strategicResource then target = target * 1.35 end
    return math.min(tonumber(BFE_BASE_CAPACITY[resource]) or 999, target)
end

local function bfe_applyProduction(base, dt)
    local stock = bfe_ensureBaseStock(base)
    if not stock or not base.owner then return end
    local baseType = tostring(base.baseType or "urban")
    local production = BFE_BASE_PRODUCTION_PER_HOUR[baseType] or BFE_BASE_PRODUCTION_PER_HOUR.urban or {}

    for resource, amountPerHour in pairs(production) do
        bfe_addResource(stock, resource, (tonumber(amountPerHour) or 0) * dt)
    end

    for _, zone in pairs(base.zones or {}) do
        if type(zone) == "table" then
            local workers = math.max(0, tonumber(zone.presentCount) or 0) + math.floor(math.max(0, tonumber(zone.assignedCount) or 0) / 4)
            if workers > 0 then
                if zone.zoneType == "food" then bfe_addResource(stock, "food", workers * dt * 1.2) end
                if zone.zoneType == "medical" then bfe_addResource(stock, "medical", workers * dt * 0.8) end
                if zone.zoneType == "ammo" then bfe_addResource(stock, "ammo", workers * dt * 0.9) end
                if zone.zoneType == "storage" then bfe_addResource(stock, "supplies", workers * dt * 0.9) end
                if zone.zoneType == "guard" then bfe_addResource(stock, "materials", workers * dt * 0.15) end
                if zone.zoneType == "patrol" then bfe_addResource(stock, "fuel", workers * dt * 0.05) end
            end
        end
    end
end

local function bfe_applyConsumption(base, population, dt)
    local stock = bfe_ensureBaseStock(base)
    if not stock or not base.owner then return end
    population = math.max(1, tonumber(population) or 1)

    for resource, amountPerPopHour in pairs(BFE_CONSUMPTION_PER_POP_HOUR) do
        bfe_removeResource(stock, resource, amountPerPopHour * population * dt)
    end

    if (tonumber(base.redCount) or 0) > 0 and (tonumber(base.greenCount) or 0) > 0 then
        bfe_removeResource(stock, "ammo", 1.4 * dt * population)
        bfe_removeResource(stock, "medical", 0.45 * dt * population)
        bfe_removeResource(stock, "supplies", 0.30 * dt * population)
    end
end

local function bfe_updateBaseEconomy(gmd, base, worldAge, dt)
    if type(base) ~= "table" then return false end
    local stock = bfe_ensureBaseStock(base)
    local side = base.owner

    if not side then
        base.economy = base.economy or {}
        base.economy.status = "neutral"
        base.economy.needSummary = "neutral"
        base.economy.population = 0
        base.economy.updatedAt = worldAge
        bfe_syncBaseStockFields(base)
        return true
    end

    local population = bfe_basePopulation(gmd, base, side)
    bfe_applyProduction(base, dt)
    bfe_applyConsumption(base, population, dt)

    local economy = base.economy or {}
    economy.population = population
    economy.shortages = {}
    economy.surplus = {}
    economy.targets = {}
    economy.needScore = 0
    economy.surplusScore = 0
    economy.status = "ok"
    economy.resourceCritical = nil
    economy.resourceLow = nil

    for _, resource in ipairs(BFE_RESOURCES) do
        local have = tonumber(stock[resource]) or 0
        local target = bfe_resourceTarget(base, resource, population)
        economy.targets[resource] = target

        if have < target * 0.35 then
            economy.shortages[resource] = "critical"
            economy.needScore = economy.needScore + (target - have) * 2.0
            economy.status = "critical"
            economy.resourceCritical = economy.resourceCritical or resource
        elseif have < target * 0.75 then
            economy.shortages[resource] = "low"
            economy.needScore = economy.needScore + (target - have)
            if economy.status ~= "critical" then economy.status = "low" end
            economy.resourceLow = economy.resourceLow or resource
        elseif have > target * 1.45 and have > 20 then
            economy.surplus[resource] = have - target
            economy.surplusScore = economy.surplusScore + (have - target)
        end
    end

    economy.needSummary = bfe_compactNeeds(economy)
    economy.strategicValue = (tonumber(base.score) or 0) + (population * 4)
    economy.threatLevel = math.max(0, (side == "green" and (tonumber(base.redCount) or 0) or (tonumber(base.greenCount) or 0)) * 12)
    economy.updatedAt = worldAge
    base.economy = economy
    bfe_syncBaseStockFields(base)
    return true
end

local function bfe_missionActive(mission)
    if type(mission) ~= "table" then return false end
    local state = tostring(mission.state or "")
    return state ~= "completed" and state ~= "failed" and state ~= "cancelled"
end

local function bfe_activeMissionCount(data, side)
    local count = 0
    for _, mission in pairs(data.missions or {}) do
        if bfe_missionActive(mission) and mission.faction == side then
            count = count + 1
        end
    end
    return count
end

local function bfe_hasActiveMission(data, side, missionType, targetBaseId, resource)
    for _, mission in pairs(data.missions or {}) do
        if bfe_missionActive(mission)
            and mission.faction == side
            and mission.missionType == missionType
            and tostring(mission.targetBaseId or "") == tostring(targetBaseId or "") then
            if not resource or mission.resource == resource then
                return true
            end
        end
    end
    return false
end

local function bfe_getBaseById(gmd, baseId)
    if not baseId then return nil end
    local bases = bfe_getBaseCamps(gmd)
    return bases[tostring(baseId)]
end

local function bfe_findSupplierBase(gmd, side, targetBase, resource)
    local bestBase = nil
    local bestScore = -999999
    for _, base in pairs(bfe_getBaseCamps(gmd)) do
        if type(base) == "table" and base.owner == side and base.id ~= targetBase.id and base.x and base.y then
            local stock = bfe_ensureBaseStock(base)
            local economy = base.economy or {}
            local surplus = economy.surplus and tonumber(economy.surplus[resource]) or 0
            if surplus <= 0 then
                local population = economy.population or 2
                surplus = (tonumber(stock[resource]) or 0) - (bfe_resourceTarget(base, resource, population) * 1.15)
            end
            if surplus >= NPCFactionEconomyServerBridge.MIN_SUPPLY_CARGO then
                local d = bfe_dist(base.x, base.y, targetBase.x, targetBase.y)
                local score = surplus * 3.0 - d * 0.02 + (tonumber(base.score) or 0) * 0.1
                if score > bestScore then
                    bestScore = score
                    bestBase = base
                end
            end
        end
    end
    return bestBase, bestScore
end

local function bfe_baseEnemyStrength(base, side)
    if not base then return 0 end
    if side == "green" then return tonumber(base.redCount) or 0 end
    return tonumber(base.greenCount) or 0
end

local function bfe_findRaidOrCaptureTarget(gmd, side, originBase, resource)
    local bestBase = nil
    local bestType = nil
    local bestScore = -999999
    local other = bfe_otherSide(side)

    for _, target in pairs(bfe_getBaseCamps(gmd)) do
        if type(target) == "table" and target.id ~= originBase.id and target.x and target.y and target.owner ~= side then
            local d = bfe_dist(originBase.x, originBase.y, target.x, target.y)
            if d <= NPCFactionEconomyServerBridge.RAID_SEARCH_RADIUS then
                local stock = bfe_ensureBaseStock(target)
                local strategicResource = BFE_STRATEGIC_RESOURCE_BY_TYPE[tostring(target.baseType or "urban")] or "supplies"
                local armoryValue = NPCBaseSupplyServer and NPCBaseSupplyServer.GetArmoryValue and NPCBaseSupplyServer.GetArmoryValue(target) or 0
                local resourceValue = 0
                if resource then
                    resourceValue = tonumber(stock[resource]) or 0
                    if strategicResource == resource then resourceValue = resourceValue + 60 end
                else
                    resourceValue = bfe_resourceSum(stock) * 0.16
                end
                if resource == "ammo" or resource == "weapons" or resource == "magazines" or resource == "weaponParts" or not resource then
                    resourceValue = resourceValue + math.min(140, armoryValue * 0.10)
                end

                local retakeBonus = 0
                if target.previousOwner == side or target.lostBy == side then retakeBonus = 130 end

                local enemyStrength = bfe_baseEnemyStrength(target, side)
                local targetType = "capture"
                if target.previousOwner == side or target.lostBy == side then
                    targetType = "retake"
                elseif target.owner == other and resourceValue >= 45 then
                    targetType = "raid"
                elseif not target.owner then
                    targetType = "capture"
                elseif target.owner == other then
                    targetType = "capture"
                end

                local score = resourceValue + retakeBonus + (tonumber(target.score) or 0) * 0.35 - d * 0.035 - enemyStrength * 18
                if target.status == "contested" then score = score + 45 end
                if target.owner == other then score = score + 15 end
                if score > bestScore then
                    bestScore = score
                    bestBase = target
                    bestType = targetType
                end
            end
        end
    end

    return bestBase, bestType, bestScore
end

local function bfe_makeMissionMarker(mission, targetBase, group)
    if not mission then return nil end
    local x = group and group.x or mission.x or (targetBase and targetBase.x)
    local y = group and group.y or mission.y or (targetBase and targetBase.y)
    if not x or not y then return nil end

    local side = mission.faction
    return {
        id = "ECON_" .. tostring(mission.id),
        markerType = "economy_mission",
        economyMissionId = mission.id,
        missionType = mission.missionType,
        missionState = mission.state,
        missionReason = mission.reason,
        resource = mission.resource,
        cargo = mission.cargo,
        itemCargoSummary = mission.itemCargoSummary,
        itemCargoValue = mission.itemCargoValue or 0,
        originBaseId = mission.originBaseId,
        targetBaseId = mission.targetBaseId,
        groupId = mission.groupId,
        x = x,
        y = y,
        z = (group and group.z) or (targetBase and targetBase.z) or 0,
        targetX = targetBase and targetBase.x or mission.targetX,
        targetY = targetBase and targetBase.y or mission.targetY,
        name = string.upper(tostring(side or "?")) .. " " .. string.upper(tostring(mission.missionType or "mission")) .. " " .. tostring(mission.targetBaseId or ""),
        owner = side,
        hostile = side == "red",
        friendly = side == "green",
        virtual = true,
        active = false,
        state = "eco_" .. tostring(mission.missionType or "mission"),
        strategicPower = group and group.strategicPower or mission.strategicPower,
        combatReadiness = group and group.combatReadiness or mission.combatReadiness,
        homeBaseId = group and group.homeBaseId or mission.originBaseId,
        updatedAt = mission.updatedAt or bfe_nowHours()
    }
end

local function bfe_sendMissionMarker(gmd, mission)
    if not mission then return false end
    local targetBase = bfe_getBaseById(gmd, mission.targetBaseId)
    local group = mission.groupId and gmd.VirtualGroups and gmd.VirtualGroups[tostring(mission.groupId)] or nil
    local marker = bfe_makeMissionMarker(mission, targetBase, group)
    if not marker then return false end
    gmd.DebugMapMarkers = gmd.DebugMapMarkers or {}
    gmd.DebugMapMarkers[marker.id] = marker
    if NPCNetContract and NPCNetContract.SendDebugMapUpdate then
        NPCNetContract.SendDebugMapUpdate(marker)
    else
        sendServerCommand('NPCDebugMap', 'Update', marker)
    end
    return true
end

local function bfe_removeMissionMarker(gmd, mission)
    if not mission then return end
    local id = "ECON_" .. tostring(mission.id)
    if gmd.DebugMapMarkers then gmd.DebugMapMarkers[id] = nil end
    if NPCNetContract and NPCNetContract.SendDebugMapRemove then
        NPCNetContract.SendDebugMapRemove(id)
    else
        sendServerCommand('NPCDebugMap', 'Remove', {id=id})
    end
end

local function bfe_createMission(gmd, data, side, missionType, originBase, targetBase, resource, cargo, priority, reason, itemCargo)
    if not originBase or not targetBase then return nil end
    if bfe_activeMissionCount(data, side) >= NPCFactionEconomyServerBridge.MAX_ACTIVE_MISSIONS_PER_SIDE then return nil end
    if bfe_hasActiveMission(data, side, missionType, targetBase.id, resource) then return nil end

    local id = "FE" .. tostring(data.nextMissionId or 1)
    data.nextMissionId = (tonumber(data.nextMissionId) or 1) + 1

    local mission = {
        id = id,
        faction = side,
        missionType = missionType,
        originBaseId = originBase.id,
        targetBaseId = targetBase.id,
        resource = resource,
        cargo = bfe_resourceCopy(cargo),
        itemCargo = itemCargo,
        itemCargoSummary = itemCargo and itemCargo.summary or nil,
        itemCargoValue = itemCargo and itemCargo.powerValue or 0,
        priority = tonumber(priority) or 0,
        reason = reason or "economy",
        state = "queued",
        createdAt = bfe_nowHours(),
        updatedAt = bfe_nowHours(),
        targetX = targetBase.x,
        targetY = targetBase.y,
        targetZ = targetBase.z or 0
    }

    data.missions[id] = mission
    bfe_sendMissionMarker(gmd, mission)
    return mission
end

local function bfe_findCarrierGroup(gmd, side, originBase)
    local bestGroup = nil
    local bestScore = 999999
    for groupId, group in pairs(gmd.VirtualGroups or {}) do
        if type(group) == "table"
            and not group.activated
            and not group.inBattle
            and (tonumber(group.count) or 0) > 0
            and not group.economyMissionId
            and bfe_sideForGroup(group) == side
            and group.x and group.y then
            local d = bfe_dist(group.x, group.y, originBase.x, originBase.y)
            if d <= NPCFactionEconomyServerBridge.CONVOY_ASSIGN_RADIUS then
                if NPCStrategicAIBridge and NPCStrategicAIBridge.EnsureGroupBase then
                    NPCStrategicAIBridge.EnsureGroupBase(gmd, group)
                end
                local strategic = NPCStrategicAIBridge and NPCStrategicAIBridge.EvaluateGroupCombatPower and NPCStrategicAIBridge.EvaluateGroupCombatPower(gmd, group) or nil
                local score = d
                if group.roadPatrol then score = score - 180 end
                if group.homeBaseId and tostring(group.homeBaseId) == tostring(originBase.id) then score = score - 320 end
                if strategic and strategic.power then score = score - math.min(280, tonumber(strategic.power) or 0) end
                if score < bestScore then
                    bestScore = score
                    bestGroup = group
                end
            end
        end
    end
    return bestGroup, bestScore
end

local function bfe_applyMissionToGroup(gmd, mission, group, originBase, targetBase)
    if not mission or not group or not targetBase then return false end
    local side = mission.faction
    group.homeBaseId = originBase and originBase.id or group.homeBaseId
    group.homeBase = originBase and {x=originBase.x, y=originBase.y, z=originBase.z or 0} or group.homeBase
    if NPCBaseSupplyServer and NPCBaseSupplyServer.ApplyGearToGroup and originBase then
        NPCBaseSupplyServer.ApplyGearToGroup(originBase, group)
    end
    if NPCStrategicAIBridge and NPCStrategicAIBridge.EnsureGroupBase then
        NPCStrategicAIBridge.EnsureGroupBase(gmd, group)
    end
    if NPCStrategicAIBridge and NPCStrategicAIBridge.EvaluateGroupCombatPower then
        local strategic = NPCStrategicAIBridge.EvaluateGroupCombatPower(gmd, group)
        mission.strategicPower = strategic and strategic.power or mission.strategicPower
        mission.combatReadiness = group.combatReadiness
    end
    group.economyMissionId = mission.id
    group.economyConvoy = true
    group.missionType = mission.missionType
    group.missionCargo = bfe_resourceCopy(mission.cargo)
    group.missionResource = mission.resource
    group.missionOriginBaseId = mission.originBaseId
    group.missionTargetBaseId = mission.targetBaseId
    group.originBaseId = mission.originBaseId
    group.targetBaseId = mission.targetBaseId
    group.missionTargetX = targetBase.x
    group.missionTargetY = targetBase.y
    group.missionTargetZ = targetBase.z or 0
    group.routeX = targetBase.x
    group.routeY = targetBase.y
    group.routeZ = targetBase.z or 0
    group.targetX = targetBase.x
    group.targetY = targetBase.y
    group.targetZ = targetBase.z or 0
    group.targetClass = "economy_" .. tostring(mission.missionType or "mission")
    group.state = "eco_" .. tostring(mission.missionType or "mission")
    group.convoyFaction = side
    group.patrolColor = side
    group.roadBias = true
    group.preferRoads = true
    group.updatedAt = bfe_nowHours()

    if type(group.members) == "table" then
        for _, member in pairs(group.members) do
            if type(member) == "table" then
                member.economyMissionId = mission.id
                member.missionType = mission.missionType
                member.missionResource = mission.resource
                member.missionTargetBaseId = mission.targetBaseId
                member.targetBaseId = mission.targetBaseId
                member.homeBaseId = member.homeBaseId or mission.originBaseId
                member.convoyFaction = side
            end
        end
    end

    mission.groupId = group.id
    mission.state = "moving"
    mission.assignedAt = bfe_nowHours()
    mission.updatedAt = mission.assignedAt
    gmd.VirtualGroups[group.id] = group
    bfe_sendMissionMarker(gmd, mission)
    return true
end

local function bfe_assignQueuedMissions(gmd, data)
    for _, mission in pairs(data.missions or {}) do
        if bfe_missionActive(mission) and mission.state == "queued" then
            local originBase = bfe_getBaseById(gmd, mission.originBaseId)
            local targetBase = bfe_getBaseById(gmd, mission.targetBaseId)
            if not originBase or not targetBase or originBase.owner ~= mission.faction then
                mission.state = "failed"
                mission.reason = "origin_lost"
                mission.updatedAt = bfe_nowHours()
                bfe_removeMissionMarker(gmd, mission)
            else
                local group = bfe_findCarrierGroup(gmd, mission.faction, originBase)
                if group then
                    bfe_applyMissionToGroup(gmd, mission, group, originBase, targetBase)
                else
                    mission.updatedAt = bfe_nowHours()
                    bfe_sendMissionMarker(gmd, mission)
                end
            end
        end
    end
end

local function bfe_clearGroupMission(group)
    if type(group) ~= "table" then return end
    group.economyMissionId = nil
    group.economyConvoy = nil
    group.missionType = nil
    group.missionCargo = nil
    group.missionResource = nil
    group.missionOriginBaseId = nil
    group.missionTargetBaseId = nil
    group.originBaseId = nil
    group.missionTargetX = nil
    group.missionTargetY = nil
    group.missionTargetZ = nil
    group.convoyFaction = nil
end

local function bfe_completeMission(gmd, data, mission, group, targetBase, originBase, status)
    mission.state = status or "completed"
    mission.completedAt = bfe_nowHours()
    mission.updatedAt = mission.completedAt
    if group then
        bfe_clearGroupMission(group)
        if targetBase and targetBase.owner == mission.faction then
            group.homeBaseId = targetBase.id
            group.homeBase = {x=targetBase.x, y=targetBase.y, z=targetBase.z or 0}
            group.state = "home_base"
            group.targetClass = "base_zone_duty"
        else
            group.state = group.roadPatrol and (group.hostile and "red_road_patrol" or "green_road_patrol") or "roaming"
            group.targetClass = nil
        end
        if NPCStrategicAIBridge and NPCStrategicAIBridge.EnsureGroupBase then
            NPCStrategicAIBridge.EnsureGroupBase(gmd, group)
        end
        if NPCStrategicAIBridge and NPCStrategicAIBridge.EvaluateGroupCombatPower then
            NPCStrategicAIBridge.EvaluateGroupCombatPower(gmd, group)
        end
        group.updatedAt = bfe_nowHours()
        if group.id then gmd.VirtualGroups[group.id] = group end
    end
    bfe_removeMissionMarker(gmd, mission)
end

local function bfe_updateMissionArrival(gmd, data, mission)
    if not bfe_missionActive(mission) then return false end
    local targetBase = bfe_getBaseById(gmd, mission.targetBaseId)
    local originBase = bfe_getBaseById(gmd, mission.originBaseId)
    if not targetBase then
        mission.state = "failed"
        mission.reason = "target_missing"
        bfe_removeMissionMarker(gmd, mission)
        return true
    end

    local group = mission.groupId and gmd.VirtualGroups and gmd.VirtualGroups[tostring(mission.groupId)] or nil
    if not group then
        if mission.state == "moving" then
            mission.state = "queued"
            mission.groupId = nil
            mission.updatedAt = bfe_nowHours()
            bfe_sendMissionMarker(gmd, mission)
            return true
        end
        return false
    end

    if group.inBattle or group.activated then
        mission.state = group.activated and "materialized" or "engaged"
        mission.updatedAt = bfe_nowHours()
        bfe_sendMissionMarker(gmd, mission)
        return true
    end

    local d = bfe_dist(group.x, group.y, targetBase.x, targetBase.y)
    if d > (tonumber(targetBase.radius) or NPCFactionEconomyServerBridge.MISSION_RADIUS) + 18 then
        mission.state = "moving"
        mission.updatedAt = bfe_nowHours()
        bfe_sendMissionMarker(gmd, mission)
        return false
    end

    if mission.missionType == "supply" then
        local stock = bfe_ensureBaseStock(targetBase)
        for _, resource in ipairs(BFE_RESOURCES) do
            bfe_addResource(stock, resource, tonumber(mission.cargo and mission.cargo[resource]) or 0)
        end
        if mission.itemCargo and NPCBaseSupplyServer and NPCBaseSupplyServer.ImportCargo then
            NPCBaseSupplyServer.ImportCargo(targetBase, mission.itemCargo)
        end
        targetBase.economy = targetBase.economy or {}
        targetBase.economy.lastDeliveryAt = bfe_nowHours()
        targetBase.economy.lastDeliveryFrom = mission.originBaseId
        bfe_syncBaseStockFields(targetBase)
        bfe_completeMission(gmd, data, mission, group, targetBase, originBase, "completed")
        return true
    end

    if mission.missionType == "raid" then
        local targetStock = bfe_ensureBaseStock(targetBase)
        local originStock = originBase and bfe_ensureBaseStock(originBase) or nil
        local stolen = {}
        local total = 0
        local resource = mission.resource or bfe_pickCargoResource(mission.cargo) or BFE_STRATEGIC_RESOURCE_BY_TYPE[tostring(targetBase.baseType or "urban")] or "supplies"
        local amount = math.max(NPCFactionEconomyServerBridge.MIN_SUPPLY_CARGO, math.min(NPCFactionEconomyServerBridge.MAX_SUPPLY_CARGO, (tonumber(targetStock[resource]) or 0) * 0.45))
        local itemCargo = nil
        local exactUnits = 0
        if NPCBaseSupplyServer and NPCBaseSupplyServer.ExtractCargo then
            itemCargo = NPCBaseSupplyServer.ExtractCargo(targetBase, resource, amount, "raid")
            exactUnits = tonumber(itemCargo and itemCargo.exactUnits) or 0
        end
        local abstractAmount = math.max(0, amount - exactUnits)
        stolen[resource] = bfe_removeResource(targetStock, resource, abstractAmount)
        total = total + (tonumber(stolen[resource]) or 0) + exactUnits
        if originStock and total > 0 then
            bfe_addResource(originStock, resource, tonumber(stolen[resource]) or 0)
            if itemCargo and NPCBaseSupplyServer and NPCBaseSupplyServer.ImportCargo then
                NPCBaseSupplyServer.ImportCargo(originBase, itemCargo)
            end
            bfe_syncBaseStockFields(originBase)
        end
        bfe_syncBaseStockFields(targetBase)
        mission.cargo = stolen
        mission.itemCargo = itemCargo
        mission.itemCargoSummary = itemCargo and itemCargo.summary or mission.itemCargoSummary
        mission.itemCargoValue = itemCargo and itemCargo.powerValue or mission.itemCargoValue
        bfe_completeMission(gmd, data, mission, group, originBase or targetBase, originBase, "completed")
        return true
    end

    if mission.missionType == "reinforce" then
        group.homeBaseId = targetBase.id
        group.homeBase = {x=targetBase.x, y=targetBase.y, z=targetBase.z or 0}
        group.state = "reinforcing_base"
        group.targetClass = "base_reinforce"
        if type(group.members) == "table" then
            for _, member in pairs(group.members) do
                if type(member) == "table" then
                    member.homeBaseId = targetBase.id
                    member.homeBase = {x=targetBase.x, y=targetBase.y, z=targetBase.z or 0}
                end
            end
        end
        if NPCBaseSupplyServer and NPCBaseSupplyServer.ApplyGearToGroup then
            NPCBaseSupplyServer.ApplyGearToGroup(targetBase, group)
        end
        if NPCStrategicAIBridge and NPCStrategicAIBridge.EvaluateGroupCombatPower then
            NPCStrategicAIBridge.EvaluateGroupCombatPower(gmd, group)
        end
        bfe_completeMission(gmd, data, mission, group, targetBase, originBase, "completed")
        return true
    end

    if mission.missionType == "capture" or mission.missionType == "retake" then
        group.targetBaseId = targetBase.id
        group.targetX = targetBase.x
        group.targetY = targetBase.y
        group.targetZ = targetBase.z or 0
        group.targetClass = "base_capture"
        group.state = "assaulting_base"
        if NPCStrategicAIBridge and NPCStrategicAIBridge.EvaluateGroupCombatPower then
            local strategic = NPCStrategicAIBridge.EvaluateGroupCombatPower(gmd, group)
            mission.strategicPower = strategic and strategic.power or mission.strategicPower
            mission.combatReadiness = group.combatReadiness
        end
        group.updatedAt = bfe_nowHours()
        gmd.VirtualGroups[group.id] = group

        if targetBase.owner == mission.faction then
            bfe_completeMission(gmd, data, mission, group, targetBase, originBase, "completed")
        else
            mission.state = "assaulting"
            mission.updatedAt = bfe_nowHours()
            bfe_sendMissionMarker(gmd, mission)
        end
        return true
    end

    bfe_completeMission(gmd, data, mission, group, targetBase, originBase, "completed")
    return true
end

local function bfe_updateExistingMissions(gmd, data)
    local changed = false
    for _, mission in pairs(data.missions or {}) do
        if bfe_updateMissionArrival(gmd, data, mission) then changed = true end
    end
    return changed
end

local function bfe_selectNeedResource(base)
    local economy = base and base.economy
    if not economy then return nil, 0, "ok" end
    local bestResource = nil
    local bestScore = 0
    local bestStatus = "ok"
    local stock = bfe_ensureBaseStock(base)
    for _, resource in ipairs(BFE_RESOURCES) do
        local status = economy.shortages and economy.shortages[resource]
        if status == "critical" or status == "low" then
            local target = economy.targets and tonumber(economy.targets[resource]) or bfe_resourceTarget(base, resource, economy.population or 2)
            local have = tonumber(stock[resource]) or 0
            local score = math.max(0, target - have)
            if status == "critical" then score = score * 2 end
            if score > bestScore then
                bestScore = score
                bestResource = resource
                bestStatus = status
            end
        end
    end
    return bestResource, bestScore, bestStatus
end

local function bfe_createSupplyMissionForNeed(gmd, data, side, targetBase, resource, needScore, status)
    if not resource or bfe_hasActiveMission(data, side, "supply", targetBase.id, resource) then return nil end

    local supplier = bfe_findSupplierBase(gmd, side, targetBase, resource)
    if supplier then
        local supplierStock = bfe_ensureBaseStock(supplier)
        local economy = supplier.economy or {}
        local surplus = economy.surplus and tonumber(economy.surplus[resource]) or 0
        if surplus <= 0 then surplus = math.max(0, (tonumber(supplierStock[resource]) or 0) - bfe_resourceTarget(supplier, resource, economy.population or 2) * 1.10) end
        local cargoAmount = math.min(NPCFactionEconomyServerBridge.MAX_SUPPLY_CARGO, math.max(NPCFactionEconomyServerBridge.MIN_SUPPLY_CARGO, surplus * 0.65, needScore * 0.45))
        local itemCargo = nil
        local exactUnits = 0
        if NPCBaseSupplyServer and NPCBaseSupplyServer.ExtractCargo then
            itemCargo = NPCBaseSupplyServer.ExtractCargo(supplier, resource, cargoAmount, "supply")
            exactUnits = tonumber(itemCargo and itemCargo.exactUnits) or 0
        end
        local abstractAmount = math.max(0, cargoAmount - exactUnits)
        abstractAmount = bfe_removeResource(supplierStock, resource, abstractAmount)
        local totalCargo = abstractAmount + exactUnits
        if totalCargo >= NPCFactionEconomyServerBridge.MIN_SUPPLY_CARGO or itemCargo then
            bfe_syncBaseStockFields(supplier)
            local cargo = {}
            cargo[resource] = abstractAmount
            return bfe_createMission(gmd, data, side, "supply", supplier, targetBase, resource, cargo, needScore, "shortage_" .. tostring(status), itemCargo)
        end
    end

    return nil
end

local function bfe_createOffensiveMissionForNeed(gmd, data, side, originBase, resource, needScore)
    local target, missionType, score = bfe_findRaidOrCaptureTarget(gmd, side, originBase, resource)
    if not target or not missionType then return nil end
    if score < 35 and missionType ~= "retake" then return nil end
    if bfe_hasActiveMission(data, side, missionType, target.id, resource) then return nil end

    local cargo = {}
    cargo[resource or (BFE_STRATEGIC_RESOURCE_BY_TYPE[tostring(target.baseType or "urban")] or "supplies")] = 0
    return bfe_createMission(gmd, data, side, missionType, originBase, target, resource, cargo, (needScore or 0) + (score or 0), "need_" .. tostring(resource or "strategic"))
end

local function bfe_createRetakeMissions(gmd, data, side)
    local created = 0
    for _, originBase in pairs(bfe_getBaseCamps(gmd)) do
        if created >= NPCFactionEconomyServerBridge.MAX_NEW_MISSIONS_PER_UPDATE then return created end
        if type(originBase) == "table" and originBase.owner == side then
            local target, missionType, score = bfe_findRaidOrCaptureTarget(gmd, side, originBase, nil)
            if target and missionType == "retake" and not bfe_hasActiveMission(data, side, "retake", target.id, nil) then
                if bfe_createMission(gmd, data, side, "retake", originBase, target, nil, {}, score + 100, "lost_base") then
                    created = created + 1
                end
            end
        end
    end
    return created
end


local function bfe_findReinforcePair(gmd, side)
    local bestOrigin = nil
    local bestTarget = nil
    local bestScore = -999999
    local bases = bfe_getBaseCamps(gmd)

    for _, target in pairs(bases or {}) do
        if type(target) == "table" and target.owner == side then
            local te = target.economy or {}
            local threat = tonumber(te.threatLevel) or 0
            if target.status == "contested" then threat = threat + 65 end
            if threat > 0 or te.status == "critical" then
                for _, origin in pairs(bases or {}) do
                    if type(origin) == "table" and origin.owner == side and origin.id ~= target.id then
                        local d = bfe_dist(origin.x, origin.y, target.x, target.y)
                        if d <= NPCFactionEconomyServerBridge.RAID_SEARCH_RADIUS then
                            local oe = origin.economy or {}
                            local originStrength = tonumber(oe.population) or 0
                            local targetPop = tonumber(te.population) or 0
                            local armory = NPCBaseSupplyServer and NPCBaseSupplyServer.GetArmoryValue and NPCBaseSupplyServer.GetArmoryValue(origin) or 0
                            local score = threat + (originStrength - targetPop) * 10 + math.min(80, armory * 0.05) - d * 0.025
                            if score > bestScore then
                                bestScore = score
                                bestOrigin = origin
                                bestTarget = target
                            end
                        end
                    end
                end
            end
        end
    end

    return bestOrigin, bestTarget, bestScore
end

local function bfe_createReinforceMission(gmd, data, side)
    local origin, target, score = bfe_findReinforcePair(gmd, side)
    if not origin or not target or score < 35 then return nil end
    if bfe_hasActiveMission(data, side, "reinforce", target.id, nil) then return nil end
    return bfe_createMission(gmd, data, side, "reinforce", origin, target, nil, {}, score, "base_under_pressure")
end

local function bfe_planFactionMissions(gmd, data, side)
    if bfe_activeMissionCount(data, side) >= NPCFactionEconomyServerBridge.MAX_ACTIVE_MISSIONS_PER_SIDE then return 0 end
    local created = 0

    created = created + bfe_createRetakeMissions(gmd, data, side)
    if created < NPCFactionEconomyServerBridge.MAX_NEW_MISSIONS_PER_UPDATE then
        if bfe_createReinforceMission(gmd, data, side) then created = created + 1 end
    end
    if created >= NPCFactionEconomyServerBridge.MAX_NEW_MISSIONS_PER_UPDATE then return created end

    local bases = {}
    for _, base in pairs(bfe_getBaseCamps(gmd)) do
        if type(base) == "table" and base.owner == side then table.insert(bases, base) end
    end

    table.sort(bases, function(a, b)
        local ea = a.economy or {}
        local eb = b.economy or {}
        return (tonumber(ea.needScore) or 0) > (tonumber(eb.needScore) or 0)
    end)

    for _, base in ipairs(bases) do
        if created >= NPCFactionEconomyServerBridge.MAX_NEW_MISSIONS_PER_UPDATE then break end
        if bfe_activeMissionCount(data, side) >= NPCFactionEconomyServerBridge.MAX_ACTIVE_MISSIONS_PER_SIDE then break end

        local resource, needScore, status = bfe_selectNeedResource(base)
        if resource and needScore > 0 then
            local mission = bfe_createSupplyMissionForNeed(gmd, data, side, base, resource, needScore, status)
            if not mission then
                mission = bfe_createOffensiveMissionForNeed(gmd, data, side, base, resource, needScore)
            end
            if mission then created = created + 1 end
        else
            local strategicResource = BFE_STRATEGIC_RESOURCE_BY_TYPE[tostring(base.baseType or "urban")] or "supplies"
            if ZombRand and ZombRand(100) < 18 then
                local mission = bfe_createOffensiveMissionForNeed(gmd, data, side, base, strategicResource, 10)
                if mission then created = created + 1 end
            end
        end
    end

    return created
end

local function bfe_refreshFactionSummary(gmd, data)
    data.factions.green = {bases={}, missions={}, resources={}}
    data.factions.red = {bases={}, missions={}, resources={}}

    for _, side in ipairs({"green", "red"}) do
        local faction = data.factions[side]
        for _, resource in ipairs(BFE_RESOURCES) do faction.resources[resource] = 0 end
    end

    for id, base in pairs(bfe_getBaseCamps(gmd)) do
        if type(base) == "table" then
            base.economy = base.economy or {}
            base.economy.missionCount = 0
        end
        if type(base) == "table" and (base.owner == "green" or base.owner == "red") then
            local faction = data.factions[base.owner]
            table.insert(faction.bases, id)
            local stock = bfe_ensureBaseStock(base)
            for _, resource in ipairs(BFE_RESOURCES) do
                faction.resources[resource] = (tonumber(faction.resources[resource]) or 0) + (tonumber(stock[resource]) or 0)
            end
        end
    end

    for id, mission in pairs(data.missions or {}) do
        if bfe_missionActive(mission) and data.factions[mission.faction] then
            table.insert(data.factions[mission.faction].missions, id)
            local originBase = bfe_getBaseById(gmd, mission.originBaseId)
            local targetBase = bfe_getBaseById(gmd, mission.targetBaseId)
            if originBase then
                originBase.economy = originBase.economy or {}
                originBase.economy.missionCount = (tonumber(originBase.economy.missionCount) or 0) + 1
            end
            if targetBase and targetBase ~= originBase then
                targetBase.economy = targetBase.economy or {}
                targetBase.economy.missionCount = (tonumber(targetBase.economy.missionCount) or 0) + 1
            end
        end
    end
end

local function bfe_pruneOldMissions(gmd, data)
    local now = bfe_nowHours()
    for id, mission in pairs(data.missions or {}) do
        if not bfe_missionActive(mission) and now - (tonumber(mission.updatedAt) or now) > 1.5 then
            bfe_removeMissionMarker(gmd, mission)
            data.missions[id] = nil
        end
    end
end

function NPCFactionEconomyServerBridge.OnBaseOwnerChanged(base, oldOwner, newOwner)
    if type(base) ~= "table" then return end
    if oldOwner and oldOwner ~= newOwner then
        base.previousOwner = oldOwner
        base.lostBy = oldOwner
        base.lostAt = bfe_nowHours()
    end
    if newOwner then
        base.capturedBy = newOwner
        base.capturedAt = bfe_nowHours()
        base.stock = base.stock or {}
        bfe_ensureBaseStock(base)
        bfe_addResource(base.stock, "supplies", 20)
        bfe_addResource(base.stock, "food", 10)
        bfe_syncBaseStockFields(base)
    end
end

function NPCFactionEconomyServerBridge.UpdateWorld()
    if not NPCFactionEconomyServerBridge.IsEnabled() then return false end
    local gmd, data = NPCFactionEconomyServerBridge.EnsureData()
    local worldAge = bfe_nowHours()
    local lastUpdate = tonumber(data.lastUpdate) or worldAge
    local dt = worldAge - lastUpdate
    if dt < 0 then dt = 0 end
    if dt > 0.50 then dt = 0.50 end
    if not data.initialized then dt = 0.10 end
    if dt <= 0 then dt = 0.10 end

    local changed = false
    if NPCStrategicAIBridge and NPCStrategicAIBridge.EnsureAllGroupsAssigned then
        changed = NPCStrategicAIBridge.EnsureAllGroupsAssigned(gmd) or changed
    end
    local bases = bfe_getBaseCamps(gmd)
    for id, base in pairs(bases or {}) do
        if bfe_updateBaseEconomy(gmd, base, worldAge, dt) then
            bases[id] = base
            if NPCBaseCampSystem and NPCBaseCampSystem.SendBaseMarker then
                NPCBaseCampSystem.SendBaseMarker(base)
            end
            changed = true
        end
    end

    if bfe_updateExistingMissions(gmd, data) then changed = true end
    bfe_planFactionMissions(gmd, data, "green")
    bfe_planFactionMissions(gmd, data, "red")
    bfe_assignQueuedMissions(gmd, data)
    bfe_refreshFactionSummary(gmd, data)
    for _, base in pairs(bfe_getBaseCamps(gmd) or {}) do
        if type(base) == "table" and NPCBaseCampSystem and NPCBaseCampSystem.SendBaseMarker then
            NPCBaseCampSystem.SendBaseMarker(base)
        end
    end
    bfe_pruneOldMissions(gmd, data)

    data.initialized = true
    data.lastUpdate = worldAge
    return changed
end

function NPCFactionEconomyServerBridge.Update()
    return NPCFactionEconomyServerBridge.UpdateWorld()
end

function NPCFactionEconomyServerBridge.GetMission(missionId)
    local _, data = NPCFactionEconomyServerBridge.EnsureData()
    if not missionId then return nil end
    return data.missions and data.missions[tostring(missionId)] or nil
end

function NPCFactionEconomyServerBridge.GetData()
    local _, data = NPCFactionEconomyServerBridge.EnsureData()
    return data
end

local function bfe_onTick()
    NPCFactionEconomyServerBridge._tick = (NPCFactionEconomyServerBridge._tick or 0) + 1
    if NPCFactionEconomyServerBridge._tick == 420 then
        NPCFactionEconomyServerBridge.UpdateWorld()
    elseif NPCFactionEconomyServerBridge._tick % 1800 == 0 then
        NPCFactionEconomyServerBridge.UpdateWorld()
    end
end

local function bfe_everyTenMinutes()
    NPCFactionEconomyServerBridge.UpdateWorld()
end

Events.OnTick.Add(bfe_onTick)
Events.EveryTenMinutes.Add(bfe_everyTenMinutes)

print("[NPCFactionEconomyServerBridge] Base stock + convoy mission economy enabled")
