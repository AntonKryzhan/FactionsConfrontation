-- NPCBaseCampServerBridge.lua
-- Server-owned strategic base/camp capture layer.
-- The system is intentionally isolated from the WorldDirector spawn/materialize
-- pipeline: it creates lightweight base markers, assigns virtual groups a travel
-- target, and never calls full TransmitNPCModData() from capture ticks.

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

local NPC_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
if not isServer() then return end

local legacyBaseCampSystem = NPC_LEGACY_GLOBALS.Get("BaseCampSystem")
NPCBaseCampServerBridge = NPCLegacyGlobalsBridge.InstallAlias("BaseCampSystem", NPCBaseCampServerBridge or legacyBaseCampSystem, "NPCBaseCampServerBridge")

NPCBaseCampServerBridge.Enabled = true
NPCBaseCampServerBridge.Version = 4
NPCBaseCampServerBridge.MAX_BASES = NPCBaseCampServerBridge.MAX_BASES or 24
NPCBaseCampServerBridge.BASE_RADIUS = NPCBaseCampServerBridge.BASE_RADIUS or 36
NPCBaseCampServerBridge.BASE_MIN_DISTANCE = NPCBaseCampServerBridge.BASE_MIN_DISTANCE or 640
NPCBaseCampServerBridge.SEARCH_ATTEMPTS = NPCBaseCampServerBridge.SEARCH_ATTEMPTS or 180
NPCBaseCampServerBridge.CAPTURE_HOURS = NPCBaseCampServerBridge.CAPTURE_HOURS or 0.75
NPCBaseCampServerBridge.CAPTURE_POWER_ADVANTAGE = NPCBaseCampServerBridge.CAPTURE_POWER_ADVANTAGE or 1.14
NPCBaseCampServerBridge.CAPTURE_MIN_POWER_STEP = NPCBaseCampServerBridge.CAPTURE_MIN_POWER_STEP or 0.18
NPCBaseCampServerBridge.CAPTURE_MAX_POWER_STEP = NPCBaseCampServerBridge.CAPTURE_MAX_POWER_STEP or 2.15
NPCBaseCampServerBridge.VIRTUAL_GARRISON_POWER_ENABLED = NPCBaseCampServerBridge.VIRTUAL_GARRISON_POWER_ENABLED ~= false
NPCBaseCampServerBridge.GROUP_TARGET_RADIUS = NPCBaseCampServerBridge.GROUP_TARGET_RADIUS or 2200
NPCBaseCampServerBridge.HOME_ASSIGN_RADIUS = NPCBaseCampServerBridge.HOME_ASSIGN_RADIUS or 420
NPCBaseCampServerBridge._tick = NPCBaseCampServerBridge._tick or 0
NPCBaseCampServerBridge.ZONE_VERSION = NPCBaseCampServerBridge.ZONE_VERSION or 3
NPCBaseCampServerBridge.ZONE_STOCK_MAX = NPCBaseCampServerBridge.ZONE_STOCK_MAX or 999
NPCBaseCampServerBridge.ZONE_PRODUCTION_RATE = NPCBaseCampServerBridge.ZONE_PRODUCTION_RATE or 1.0
NPCBaseCampServerBridge.ZONE_CONSUMPTION_RATE = NPCBaseCampServerBridge.ZONE_CONSUMPTION_RATE or 1.0
NPCBaseCampServerBridge.ZONE_MARKERS_ENABLED = NPCBaseCampServerBridge.ZONE_MARKERS_ENABLED ~= false
NPCBaseCampServerBridge.ZONE_REBALANCE_HOURS = NPCBaseCampServerBridge.ZONE_REBALANCE_HOURS or 0.25
NPCBaseCampServerBridge.BUILDING_SEARCH_RADIUS = NPCBaseCampServerBridge.BUILDING_SEARCH_RADIUS or 96
NPCBaseCampServerBridge.BUILDING_SEARCH_STEP = NPCBaseCampServerBridge.BUILDING_SEARCH_STEP or 12
NPCBaseCampServerBridge.BUILDING_MIN_AREA = NPCBaseCampServerBridge.BUILDING_MIN_AREA or 24

NPCBaseCampSystem = NPCBaseCampSystem or NPCBaseCampServerBridge
NPCLegacyGlobalsBridge.InstallAlias("BaseCampSystem", NPCBaseCampSystem, "NPCBaseCampSystem")

local basecamp_worldDirector = NPCWorldDirector or NPC_LEGACY_GLOBALS.Get("WorldDirector")
local basecamp_factionEconomy = NPCFactionEconomyServer or NPCFactionEconomyServerBridge or NPCFactionEconomy or (NPCLegacyGlobalsBridge and NPCLegacyGlobalsBridge.Get and NPCLegacyGlobalsBridge.Get("FactionEconomy"))
local basecamp_gmd = NPCGMD or (NPCLegacyGlobalsBridge and NPCLegacyGlobalsBridge.Get and NPCLegacyGlobalsBridge.Get("GMD"))
local basecamp_baseSupply = NPCBaseSupplyServer or NPCBaseSupplyServerBridge or (NPCLegacyGlobalsBridge and NPCLegacyGlobalsBridge.Get and NPCLegacyGlobalsBridge.Get("BaseSupply"))
local basecamp_spy = NPCSpyBridge or (NPCLegacyGlobalsBridge and NPCLegacyGlobalsBridge.Get and NPCLegacyGlobalsBridge.Get("Spy"))
local basecamp_worldObjects = NPCWorldObjectCommandBridge or (NPCLegacyGlobalsBridge and NPCLegacyGlobalsBridge.Get and NPCLegacyGlobalsBridge.Get("WorldObjectCommand"))



local BCS_BAD_ZONE_KEYWORDS = {
    "water", "deepforest", "deep forest", "forest", "vegetation", "vegitation", "foraging", "farm",
    "farmland", "farm land", "field", "ranch", "camp"
}

local BCS_IMPORTANT_ZONE_KEYWORDS = {
    "hospital", "medical", "clinic", "doctor", "pharmacy", "commercial", "business", "shop", "store",
    "mall", "market", "grocery", "restaurant", "school", "police", "fire", "warehouse", "storage",
    "office", "factory", "industrial", "bank", "hotel", "motel", "community", "town", "gas", "fossoil"
}

local BCS_BASE_TYPE_KEYWORDS = {
    hospital = {"hospital", "medical", "clinic", "doctor", "pharmacy"},
    shop = {"shop", "store", "mall", "market", "grocery", "commercial", "business", "restaurant"},
    school = {"school"},
    police = {"police"},
    fire = {"fire"},
    warehouse = {"warehouse", "storage", "factory", "industrial"},
    office = {"office", "bank", "business"},
    city = {"town", "community", "hotel", "motel", "gas", "fossoil"}
}

local BCS_BASE_ARCHETYPE_CONFIG = {
    military = {label="Military outpost", garrisonSize=8, fortifyLevel=3, lootBias="ammo", behaviorStyle="disciplined_guard", visualStyle="military_outpost"},
    raider = {label="Raider den", garrisonSize=7, fortifyLevel=2, lootBias="weapons", behaviorStyle="aggressive_raiders", visualStyle="raider_den"},
    punk = {label="Punk hideout", garrisonSize=6, fortifyLevel=2, lootBias="materials", behaviorStyle="chaotic_guard", visualStyle="punk_hideout"},
    checkpoint = {label="Checkpoint depot", garrisonSize=6, fortifyLevel=3, lootBias="fuel", behaviorStyle="road_control", visualStyle="checkpoint_depot"},
    elite_safehouse = {label="Elite safehouse", garrisonSize=5, fortifyLevel=4, lootBias="weapons", behaviorStyle="elite_defense", visualStyle="elite_safehouse"}
}

local BCS_ARCHETYPE_KEYWORDS = {
    military = {"police", "fire", "warehouse", "storage", "factory", "industrial", "military", "army", "gun"},
    checkpoint = {"gas", "fossoil", "road", "nav", "highway", "parking"},
    elite_safehouse = {"office", "bank", "hotel", "motel", "business", "large_city_building"},
    punk = {"school", "community", "bar", "club", "town"},
    raider = {"shop", "store", "mall", "market", "grocery", "commercial", "restaurant", "urban"}
}

local BCS_ZONE_LAYOUT = {
    {zoneType="command", label="CMD", angle=0, ring=0.10, radius=10, capacity=3, duty="lead"},
    {zoneType="staging", label="STG", angle=180, ring=0.18, radius=14, capacity=8, duty="rally"},
    {zoneType="storage", label="STO", angle=300, ring=0.30, radius=14, capacity=6, duty="stash"},
    {zoneType="sleep", label="SLP", angle=240, ring=0.30, radius=16, capacity=10, duty="rest"},
    {zoneType="medical", label="MED", angle=120, ring=0.28, radius=12, capacity=4, duty="heal"},
    {zoneType="food", label="FOOD", angle=60, ring=0.30, radius=13, capacity=5, duty="eat"},
    {zoneType="ammo", label="AMMO", angle=330, ring=0.48, radius=12, capacity=5, duty="reload"},
    {zoneType="guard", label="G1", angle=45, ring=0.72, radius=12, capacity=3, duty="guard"},
    {zoneType="guard", label="G2", angle=135, ring=0.72, radius=12, capacity=3, duty="guard"},
    {zoneType="guard", label="G3", angle=225, ring=0.72, radius=12, capacity=3, duty="guard"},
    {zoneType="guard", label="G4", angle=315, ring=0.72, radius=12, capacity=3, duty="guard"},
    {zoneType="patrol", label="P1", angle=0, ring=0.92, radius=11, capacity=2, duty="patrol"},
    {zoneType="patrol", label="P2", angle=90, ring=0.92, radius=11, capacity=2, duty="patrol"},
    {zoneType="patrol", label="P3", angle=180, ring=0.92, radius=11, capacity=2, duty="patrol"},
    {zoneType="patrol", label="P4", angle=270, ring=0.92, radius=11, capacity=2, duty="patrol"}
}

local BCS_BASE_TYPE_ZONE_BONUS = {
    hospital = {medical=4, sleep=2, storage=1},
    shop = {food=4, storage=3},
    school = {sleep=2, food=1, medical=1},
    police = {ammo=4, guard=2},
    fire = {medical=2, storage=2, guard=1},
    warehouse = {storage=5, ammo=2},
    office = {command=2, storage=1},
    city = {command=1, food=1, storage=1},
    urban = {command=1, guard=1, patrol=1}
}

local BCS_ROLE_ZONE = {
    leader = "command", boss = "command", commander = "command", officer = "command",
    medic = "medical", doctor = "medical", nurse = "medical", healer = "medical",
    scavenger = "storage", looter = "storage", engineer = "storage", mechanic = "storage", worker = "storage",
    cook = "food", farmer = "food",
    guard = "guard", sentry = "guard", soldier = "guard", assault = "guard",
    sniper = "guard", marksman = "guard", overwatch = "guard", support = "guard",
    scout = "patrol", point = "patrol", patrol = "patrol", driver = "staging"
}

local BCS_ZONE_RESOURCE_KEYS = {
    "food", "water", "medical", "ammo", "fuel", "materials", "tools", "weapons", "spareParts", "supplies", "rest", "security"
}

local BCS_ZONE_RESOURCE_PROFILE = {
    command = {produce={supplies=0.6, security=0.9}, consume={food=0.04, water=0.05, supplies=0.05}, target={supplies=35, security=40}},
    staging = {produce={supplies=0.35, security=0.25}, consume={food=0.05, water=0.05}, target={supplies=25}},
    storage = {produce={supplies=2.6, materials=1.4, tools=0.35, spareParts=0.45}, consume={food=0.04, water=0.05}, target={supplies=110, materials=70, tools=20}},
    sleep = {produce={rest=2.2}, consume={food=0.03, water=0.04, supplies=0.02}, target={rest=80}},
    medical = {produce={medical=1.9}, consume={food=0.03, water=0.04, supplies=0.10}, target={medical=75}},
    food = {produce={food=2.4, water=1.6}, consume={supplies=0.06}, target={food=95, water=80}},
    ammo = {produce={ammo=2.2, weapons=0.14, spareParts=0.28}, consume={materials=0.12, supplies=0.08}, target={ammo=120, weapons=12}},
    guard = {produce={security=2.7}, consume={food=0.06, water=0.06, ammo=0.12, medical=0.02}, target={security=95, ammo=45}},
    patrol = {produce={security=1.7, supplies=0.25}, consume={food=0.08, water=0.08, ammo=0.10, medical=0.02}, target={security=75, ammo=32}},
}

local BCS_ZONE_DUTY_STATE = {
    command = "ReturnToBase",
    staging = "ReturnToBase",
    storage = "LootArea",
    sleep = "SleepRest",
    medical = "HealSelf",
    food = "EatDrink",
    ammo = "ReloadWeapon",
    guard = "DefendBase",
    patrol = "PatrolArea"
}



local function bcs_nowHours()
    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then
            return gt:getWorldAgeHours()
        end
    end
    return 0
end

local function bcs_count(tbl)
    local count = 0
    if type(tbl) ~= "table" then return 0 end
    for _, _ in pairs(tbl) do count = count + 1 end
    return count
end

local function bcs_clamp(value, minValue, maxValue)
    value = tonumber(value) or 0
    if minValue ~= nil and value < minValue then return minValue end
    if maxValue ~= nil and value > maxValue then return maxValue end
    return value
end

local function bcs_round(value)
    return math.floor((tonumber(value) or 0) + 0.5)
end

local function bcs_buildingRadiusFromBounds(x1, y1, x2, y2)
    x1 = tonumber(x1)
    y1 = tonumber(y1)
    x2 = tonumber(x2)
    y2 = tonumber(y2)
    if not x1 or not y1 or not x2 or not y2 then return nil end
    if x2 < x1 then x1, x2 = x2, x1 end
    if y2 < y1 then y1, y2 = y2, y1 end

    local w = math.max(1, x2 - x1)
    local h = math.max(1, y2 - y1)
    return math.max(12, math.floor(math.sqrt(w * w + h * h) / 2 + 6 + 0.5))
end

local function bcs_computeBaseRadius(base)
    local configured = bcs_clamp(NPCBaseCampServerBridge.BASE_RADIUS or 36, 10, 500)
    if type(base) == "table" and base.buildingBased == true then
        local buildingRadius = bcs_buildingRadiusFromBounds(base.buildingX, base.buildingY, base.buildingX2, base.buildingY2)
        if buildingRadius and buildingRadius > configured then
            return bcs_clamp(buildingRadius, 10, 500)
        end
    end
    return configured
end

local function bcs_settingNumber(name, defaultValue, minValue, maxValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        local ok, value = pcall(function()
            return NPCLegacySettingsBridge.GetNumber(name, defaultValue, minValue, maxValue)
        end)
        if ok and value ~= nil then return value end
    end
    return bcs_clamp(defaultValue, minValue, maxValue)
end

local function bcs_settingBool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        local ok, value = pcall(function()
            return NPCLegacySettingsBridge.GetBool(name, defaultValue)
        end)
        if ok and value ~= nil then return value == true end
    end
    return defaultValue == true
end

local function bcs_applySettings()
    NPCBaseCampServerBridge.Enabled = bcs_settingBool("Base_Enabled", NPCBaseCampServerBridge.Enabled ~= false)
    NPCBaseCampServerBridge.MAX_BASES = bcs_settingNumber("Base_MaxBases", NPCBaseCampServerBridge.MAX_BASES or 24, 0, 200)
    NPCBaseCampServerBridge.BASE_RADIUS = bcs_settingNumber("Base_Radius", NPCBaseCampServerBridge.BASE_RADIUS or 36, 10, 500)
    NPCBaseCampServerBridge.BASE_MIN_DISTANCE = bcs_settingNumber("Base_MinDistance", NPCBaseCampServerBridge.BASE_MIN_DISTANCE or 640, 0, 5000)
    NPCBaseCampServerBridge.SEARCH_ATTEMPTS = bcs_settingNumber("Base_SearchAttempts", NPCBaseCampServerBridge.SEARCH_ATTEMPTS or 180, 1, 10000)
    NPCBaseCampServerBridge.CAPTURE_HOURS = bcs_settingNumber("Base_CaptureHours", NPCBaseCampServerBridge.CAPTURE_HOURS or 0.75, 0.01, 240)
    NPCBaseCampServerBridge.CAPTURE_POWER_ADVANTAGE = bcs_settingNumber("Base_CapturePowerAdvantage", NPCBaseCampServerBridge.CAPTURE_POWER_ADVANTAGE or 1.14, 1.01, 4.0)
    NPCBaseCampServerBridge.GROUP_TARGET_RADIUS = bcs_settingNumber("Base_GroupTargetRadius", NPCBaseCampServerBridge.GROUP_TARGET_RADIUS or 2200, 50, 10000)
    NPCBaseCampServerBridge.HOME_ASSIGN_RADIUS = bcs_settingNumber("Base_HomeAssignRadius", NPCBaseCampServerBridge.HOME_ASSIGN_RADIUS or 420, 10, 5000)
    NPCBaseCampServerBridge.ZONE_REBALANCE_HOURS = bcs_settingNumber("Base_ZoneRebalanceMinutes", (NPCBaseCampServerBridge.ZONE_REBALANCE_HOURS or 0.25) * 60, 1, 1440) / 60
    NPCBaseCampServerBridge.ZONE_STOCK_MAX = bcs_settingNumber("Base_ZoneStockMax", NPCBaseCampServerBridge.ZONE_STOCK_MAX or 999, 25, 10000)
    NPCBaseCampServerBridge.ZONE_PRODUCTION_RATE = bcs_settingNumber("Base_ZoneProductionRate", NPCBaseCampServerBridge.ZONE_PRODUCTION_RATE or 1.0, 0.0, 10.0)
    NPCBaseCampServerBridge.ZONE_CONSUMPTION_RATE = bcs_settingNumber("Base_ZoneConsumptionRate", NPCBaseCampServerBridge.ZONE_CONSUMPTION_RATE or 1.0, 0.0, 10.0)
    NPCBaseCampServerBridge.ZONE_MARKERS_ENABLED = bcs_settingBool("Base_ZoneMarkersEnabled", NPCBaseCampServerBridge.ZONE_MARKERS_ENABLED ~= false)
    NPCBaseCampServerBridge.BUILDING_SEARCH_RADIUS = bcs_settingNumber("Base_BuildingSearchRadius", NPCBaseCampServerBridge.BUILDING_SEARCH_RADIUS or 96, 8, 512)
    NPCBaseCampServerBridge.BUILDING_SEARCH_STEP = bcs_settingNumber("Base_BuildingSearchStep", NPCBaseCampServerBridge.BUILDING_SEARCH_STEP or 12, 4, 64)
    NPCBaseCampServerBridge.BUILDING_MIN_AREA = bcs_settingNumber("Base_BuildingMinArea", NPCBaseCampServerBridge.BUILDING_MIN_AREA or 24, 4, 5000)
end

local function bcs_dist(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return math.sqrt(dx * dx + dy * dy)
end

local function bcs_lower(value)
    if not value then return "" end
    return string.lower(tostring(value))
end

local function bcs_hasAny(value, needles)
    local v = bcs_lower(value)
    for _, needle in ipairs(needles) do
        if string.find(v, needle, 1, true) then
            return true
        end
    end
    return false
end

local function bcs_sideIsGreen(side)
    return side == "green" or side == "friendly"
end

local function bcs_sideForGroup(group)
    if NPCFactionBridge and NPCFactionBridge.GetBrainSide then
        local side = NPCFactionBridge.NormalizeSide(group and (group.factionSide or group.faction or group.side or group.patrolColor))
        if side == "red" or side == "green" then return side end
        if side == "blue" or side == "black" then return nil end
    end
    if group and group.hostile == false then return "green" end
    return "red"
end

local function bcs_sideForBrain(brain)
    if NPCFactionBridge and NPCFactionBridge.GetBrainSide then
        local side = NPCFactionBridge.GetBrainSide(brain)
        if side == "red" or side == "green" then return side end
        if side == "blue" or side == "black" then return nil end
    end
    if brain and brain.hostile == false then return "green" end
    if brain and brain.program and tostring(brain.program.name or "") == "Companion" then return "green" end
    return "red"
end

local function bcs_zoneType(zone)
    if not zone then return nil end

    local ok, zoneType = pcall(function()
        return zone:getType()
    end)

    if ok and zoneType then
        return tostring(zoneType)
    end

    return nil
end

local function bcs_addZoneType(types, zone)
    local zoneType = bcs_zoneType(zone)
    if zoneType then
        table.insert(types, zoneType)
    end
end

local function bcs_getWorldBounds()
    if basecamp_worldDirector and basecamp_worldDirector.GetWorldBounds then
        local ok, minX, minY, maxX, maxY = pcall(function()
            return basecamp_worldDirector.GetWorldBounds()
        end)
        if ok and minX and minY and maxX and maxY then
            return minX, minY, maxX, maxY
        end
    end

    local minX, minY, maxX, maxY = 0, 0, 18000, 18000
    local world = getWorld()
    if not world then return minX, minY, maxX, maxY end

    local metaGrid = world:getMetaGrid()
    if not metaGrid then return minX, minY, maxX, maxY end

    local ok
    ok, minX = pcall(function() return metaGrid:getMinX() end)
    if not ok or not minX then minX = 0 end
    ok, minY = pcall(function() return metaGrid:getMinY() end)
    if not ok or not minY then minY = 0 end
    ok, maxX = pcall(function() return metaGrid:getMaxX() end)
    if not ok or not maxX then maxX = 60 end
    ok, maxY = pcall(function() return metaGrid:getMaxY() end)
    if not ok or not maxY then maxY = 60 end

    minX = math.floor(minX * 300)
    minY = math.floor(minY * 300)
    maxX = math.floor((maxX + 1) * 300)
    maxY = math.floor((maxY + 1) * 300)

    if maxX - minX < 1000 then minX, maxX = 0, 18000 end
    if maxY - minY < 1000 then minY, maxY = 0, 18000 end

    return minX, minY, maxX, maxY
end

function NPCBaseCampServerBridge.GetZoneTypesAt(x, y)
    local types = {}
    local world = getWorld()
    if not world then return types end

    local metaGrid = world:getMetaGrid()
    if not metaGrid then return types end

    local ok, zones = pcall(function()
        return metaGrid:getZonesAt(x, y, 0)
    end)

    if ok and zones then
        local okSize, zoneCount = pcall(function() return zones:size() end)
        if okSize and zoneCount then
            for i=0, zoneCount-1 do
                bcs_addZoneType(types, zones:get(i))
            end
        elseif type(zones) == "table" then
            for _, zone in pairs(zones) do
                bcs_addZoneType(types, zone)
            end
        end
    end

    ok, zones = pcall(function()
        return metaGrid:getZoneAt(x, y, 0)
    end)

    if ok and zones then
        bcs_addZoneType(types, zones)
    end

    return types
end


local bcs_baseTypeFromZones

local function bcs_buildingDefValue(buildingDef, getter)
    if not buildingDef then return nil end
    local ok, value = pcall(getter)
    if ok then return value end
    return nil
end

local function bcs_buildingDefBounds(buildingDef)
    if not buildingDef then return nil end

    local x1 = bcs_buildingDefValue(buildingDef, function() return buildingDef:getX() end)
    local y1 = bcs_buildingDefValue(buildingDef, function() return buildingDef:getY() end)
    local x2 = bcs_buildingDefValue(buildingDef, function() return buildingDef:getX2() end)
    local y2 = bcs_buildingDefValue(buildingDef, function() return buildingDef:getY2() end)

    x1 = tonumber(x1)
    y1 = tonumber(y1)
    x2 = tonumber(x2)
    y2 = tonumber(y2)
    if not x1 or not y1 or not x2 or not y2 then return nil end
    if x2 < x1 then x1, x2 = x2, x1 end
    if y2 < y1 then y1, y2 = y2, y1 end

    local w = math.max(1, x2 - x1)
    local h = math.max(1, y2 - y1)
    local area = w * h
    if area < (NPCBaseCampServerBridge.BUILDING_MIN_AREA or 24) then return nil end

    return {
        x1 = math.floor(x1),
        y1 = math.floor(y1),
        x2 = math.floor(x2),
        y2 = math.floor(y2),
        w = w,
        h = h,
        area = area,
        cx = math.floor((x1 + x2) / 2 + 0.5),
        cy = math.floor((y1 + y2) / 2 + 0.5)
    }
end

local function bcs_buildingDefKey(buildingDef, bounds)
    if not buildingDef then return nil end

    local key = bcs_buildingDefValue(buildingDef, function() return buildingDef:getKeyId() end)
    if key == nil then
        key = bcs_buildingDefValue(buildingDef, function() return buildingDef:getID() end)
    end
    if key ~= nil then return tostring(key) end

    if bounds then
        return tostring(bounds.x1) .. ":" .. tostring(bounds.y1) .. ":" .. tostring(bounds.x2) .. ":" .. tostring(bounds.y2)
    end

    return nil
end

local function bcs_addBuildingRoomType(types, roomDef)
    if not roomDef then return end

    local getter = roomDef.getName
    if type(getter) == "function" then
        local ok, value = pcall(function() return getter(roomDef) end)
        if ok and value then table.insert(types, tostring(value)) end
    end

    getter = roomDef.getType
    if type(getter) == "function" then
        local ok, value = pcall(function() return getter(roomDef) end)
        if ok and value then table.insert(types, tostring(value)) end
    end
end

local function bcs_buildingRoomTypes(buildingDef)
    local types = {}
    if not buildingDef then return types end

    local ok, rooms = pcall(function() return buildingDef:getRooms() end)
    if not ok or not rooms then return types end

    local okSize, roomCount = pcall(function() return rooms:size() end)
    if okSize and roomCount then
        for i=0, roomCount-1 do
            local okRoom, roomDef = pcall(function() return rooms:get(i) end)
            if okRoom then bcs_addBuildingRoomType(types, roomDef) end
        end
    elseif type(rooms) == "table" then
        for _, roomDef in pairs(rooms) do
            bcs_addBuildingRoomType(types, roomDef)
        end
    end

    return types
end

local function bcs_buildingDefAt(x, y, z)
    local world = getWorld()
    if world then
        local metaGrid = world:getMetaGrid()
        if metaGrid then
            local ok, roomDef = pcall(function()
                return metaGrid:getRoomAt(math.floor(x), math.floor(y), tonumber(z) or 0)
            end)
            if ok and roomDef then
                local okBuilding, buildingDef = pcall(function() return roomDef:getBuilding() end)
                if okBuilding and buildingDef then return buildingDef end
            end
        end
    end

    local cell = getCell and getCell() or nil
    if cell then
        local okSquare, square = pcall(function()
            return cell:getGridSquare(math.floor(x), math.floor(y), tonumber(z) or 0)
        end)
        if okSquare and square then
            local okBuilding, building = pcall(function() return square:getBuilding() end)
            if okBuilding and building then
                local okDef, buildingDef = pcall(function() return building:getDef() end)
                if okDef and buildingDef then return buildingDef end
            end
        end
    end

    return nil
end

local function bcs_makeBuildingPoint(buildingDef, sourceX, sourceY)
    local bounds = bcs_buildingDefBounds(buildingDef)
    if not bounds then return nil end

    local zoneTypes = NPCBaseCampServerBridge.GetZoneTypesAt(bounds.cx, bounds.cy)
    local score, reason = NPCBaseCampServerBridge.ScoreStrategicPoint(bounds.cx, bounds.cy)
    local roomTypes = bcs_buildingRoomTypes(buildingDef)
    local baseType = bcs_baseTypeFromZones(zoneTypes, reason)

    if baseType == "urban" and #roomTypes > 0 then
        baseType = bcs_baseTypeFromZones(roomTypes, reason)
    end

    if baseType ~= "urban" then
        score = score + 160
        reason = baseType
    end

    score = score + math.min(90, math.floor((bounds.area or 0) / 10))
    score = score - math.floor(bcs_dist(bounds.cx, bounds.cy, sourceX, sourceY) / 2)

    return {
        x = bounds.cx,
        y = bounds.cy,
        z = 0,
        score = score,
        reason = reason or baseType,
        zoneTypes = zoneTypes,
        roomTypes = roomTypes,
        baseType = baseType,
        buildingBased = true,
        buildingKey = bcs_buildingDefKey(buildingDef, bounds),
        buildingX = bounds.x1,
        buildingY = bounds.y1,
        buildingX2 = bounds.x2,
        buildingY2 = bounds.y2,
        buildingW = bounds.w,
        buildingH = bounds.h,
        buildingArea = bounds.area
    }
end

local function bcs_findBuildingNear(x, y, maxRadius, step)
    maxRadius = tonumber(maxRadius) or NPCBaseCampServerBridge.BUILDING_SEARCH_RADIUS or 96
    step = math.max(4, tonumber(step) or NPCBaseCampServerBridge.BUILDING_SEARCH_STEP or 12)

    local bestPoint = nil
    local bestScore = -1000
    local seen = {}
    local samples = {{0, 0}}

    for radius=step, maxRadius, step do
        table.insert(samples, {radius, 0})
        table.insert(samples, {-radius, 0})
        table.insert(samples, {0, radius})
        table.insert(samples, {0, -radius})
        table.insert(samples, {radius, radius})
        table.insert(samples, {radius, -radius})
        table.insert(samples, {-radius, radius})
        table.insert(samples, {-radius, -radius})
    end

    for _, offset in ipairs(samples) do
        local sx = math.floor((tonumber(x) or 0) + offset[1])
        local sy = math.floor((tonumber(y) or 0) + offset[2])
        local buildingDef = bcs_buildingDefAt(sx, sy, 0)
        if buildingDef then
            local bounds = bcs_buildingDefBounds(buildingDef)
            local key = bcs_buildingDefKey(buildingDef, bounds)
            if key and not seen[key] then
                seen[key] = true
                local point = bcs_makeBuildingPoint(buildingDef, x, y)
                if point and point.score > bestScore then
                    bestScore = point.score
                    bestPoint = point
                    if bestScore >= 300 then break end
                end
            end
        end
    end

    return bestPoint
end

function NPCBaseCampServerBridge.ScoreStrategicPoint(x, y)
    local zoneTypes = NPCBaseCampServerBridge.GetZoneTypesAt(x, y)
    local score = -40
    local reason = "unmarked"

    for _, zoneType in pairs(zoneTypes) do
        local z = bcs_lower(zoneType)

        if bcs_hasAny(z, BCS_BAD_ZONE_KEYWORDS) then
            return -1000, "blocked", zoneTypes
        end

        if bcs_hasAny(z, BCS_IMPORTANT_ZONE_KEYWORDS) then
            score = score + 210
            reason = z
        elseif string.find(z, "nav", 1, true) or string.find(z, "road", 1, true) then
            score = score + 15
        end
    end

    local affinity = 0
    if basecamp_worldDirector and basecamp_worldDirector.GetUrbanAffinityAt then
        local ok, value = pcall(function()
            return basecamp_worldDirector.GetUrbanAffinityAt(x, y, 260)
        end)
        if ok and value then affinity = tonumber(value) or 0 end
    end

    if affinity > 0 then
        score = score + math.floor(affinity / 3)
        if reason == "unmarked" and affinity >= 150 then reason = "large_city_building" end
    end

    return score, reason, zoneTypes
end

function bcs_baseTypeFromZones(zoneTypes, reason)
    local haystack = bcs_lower(reason or "")
    for _, zoneType in pairs(zoneTypes or {}) do
        haystack = haystack .. " " .. bcs_lower(zoneType)
    end

    for baseType, keywords in pairs(BCS_BASE_TYPE_KEYWORDS) do
        if bcs_hasAny(haystack, keywords) then
            return baseType
        end
    end

    return "urban"
end

local function bcs_hashText(value)
    local textValue = tostring(value or "")
    local h = 0
    for i=1, #textValue do
        h = (h + string.byte(textValue, i) * i) % 7919
    end
    return h
end

function NPCBaseCampServerBridge.ResolveBaseArchetype(base, point)
    local haystack = ""
    if type(point) == "table" then
        haystack = haystack .. " " .. bcs_lower(point.reason or "") .. " " .. bcs_lower(point.baseType or "")
        for _, zoneType in pairs(point.zoneTypes or {}) do haystack = haystack .. " " .. bcs_lower(zoneType) end
        for _, roomType in pairs(point.roomTypes or {}) do haystack = haystack .. " " .. bcs_lower(roomType) end
    end
    if type(base) == "table" then
        haystack = haystack .. " " .. bcs_lower(base.reason or "") .. " " .. bcs_lower(base.baseType or "") .. " " .. bcs_lower(base.name or "")
    end

    for archetype, keywords in pairs(BCS_ARCHETYPE_KEYWORDS) do
        if bcs_hasAny(haystack, keywords) then return archetype end
    end

    local seed = bcs_hashText((base and base.id or "") .. ":" .. tostring(base and base.x or point and point.x or "") .. ":" .. tostring(base and base.y or point and point.y or ""))
    local variants = {"raider", "punk", "military", "elite_safehouse"}
    return variants[(seed % #variants) + 1]
end

function NPCBaseCampServerBridge.GetBaseArchetypeConfig(base)
    local archetype = base and (base.baseArchetype or base.archetype) or nil
    return BCS_BASE_ARCHETYPE_CONFIG[tostring(archetype or "")] or BCS_BASE_ARCHETYPE_CONFIG.raider
end

function NPCBaseCampServerBridge.EnsureBaseArchetype(base, point)
    if type(base) ~= "table" then return nil end
    local archetype = base.baseArchetype or base.archetype or NPCBaseCampServerBridge.ResolveBaseArchetype(base, point)
    local config = BCS_BASE_ARCHETYPE_CONFIG[tostring(archetype or "")] or BCS_BASE_ARCHETYPE_CONFIG.raider
    base.baseArchetype = tostring(archetype or "raider")
    base.archetype = base.baseArchetype
    base.baseArchetypeLabel = config.label
    base.garrisonSize = tonumber(base.garrisonSize) or tonumber(config.garrisonSize) or 6
    base.fortifyLevel = tonumber(base.fortifyLevel) or tonumber(config.fortifyLevel) or 2
    base.lootBias = base.lootBias or config.lootBias
    base.behaviorStyle = base.behaviorStyle or config.behaviorStyle
    base.presentationStyle = base.presentationStyle or config.visualStyle
    base.visualStyle = base.visualStyle or config.visualStyle
    return config
end

function NPCBaseCampServerBridge.GetBaseGarrisonSize(base)
    local config = NPCBaseCampServerBridge.EnsureBaseArchetype(base)
    local value = tonumber(base and base.garrisonSize) or tonumber(config and config.garrisonSize) or 6
    if value < 3 then value = 3 end
    if value > 12 then value = 12 end
    return math.floor(value)
end

function NPCBaseCampServerBridge.EnsureData()
    local gmd = GetNPCModData()
    if not gmd.BaseCamps then gmd.BaseCamps = {} end
    if not gmd.BaseCampZones then gmd.BaseCampZones = {} end
    if not gmd.DebugMapMarkers then gmd.DebugMapMarkers = {} end
    if not gmd.BaseCampDirector then
        gmd.BaseCampDirector = {
            enabled = true,
            initialized = false,
            nextBaseId = 1,
            lastUpdate = 0,
            lastSearch = 0
        }
    end
    if gmd.BaseCampDirector.enabled == nil then gmd.BaseCampDirector.enabled = true end
    if not gmd.BaseCampDirector.nextBaseId then gmd.BaseCampDirector.nextBaseId = 1 end
    return gmd
end

function NPCBaseCampServerBridge.IsEnabled()
    local gmd = NPCBaseCampServerBridge.EnsureData()
    return NPCBaseCampServerBridge.Enabled and gmd.BaseCampDirector and gmd.BaseCampDirector.enabled ~= false
end

local function bcs_markerId(base)
    return "BASE_" .. tostring(base and base.id or "unknown")
end

local BCS_REGION_NAME_POOLS = {
    louisville = {"Louisville", "Jefferson", "River Road", "Cherokee", "Highlands"},
    valley_station = {"Valley Station", "Dixie Gate", "South Louisville", "Fenceline", "Outer Loop"},
    west_point = {"West Point", "Ferry Road", "Salt River", "Old Mill", "Riverside Ferry"},
    riverside = {"Riverside", "Riverbank", "Country Club", "Ohio Bend", "Scenic Grove"},
    muldraugh = {"Muldraugh", "Dixie Highway", "Rail Yard", "Truck Stop", "South Muldraugh"},
    rosewood = {"Rosewood", "Knox Prison", "Firebreak", "County Road", "Court House"},
    march_ridge = {"March Ridge", "Barracks Row", "Forest Gate", "Ridge Line", "Quarters"},
    ekron = {"Ekron", "Fallas Lake", "Doe Valley", "Lake Road", "Farmstead"},
    farmland = {"Knox County", "Bluegrass", "Grain Road", "Hunting Lodge", "Rural Route"}
}

local BCS_ARCHETYPE_NAME_SUFFIXES = {
    military = {"Armory", "Depot", "Motor Pool", "Guard Post", "Command Post"},
    checkpoint = {"Checkpoint", "Roadblock", "Gate", "Toll Stop", "Crossing"},
    elite_safehouse = {"Safehouse", "Refuge", "Estate", "Shelter", "Holdout"},
    punk = {"Garage", "Junkyard", "Crash House", "Lot", "Clubhouse"},
    raider = {"Hideout", "Camp", "Den", "Warehouse", "Stronghold"},
    urban = {"Outpost", "Station", "Depot", "Warehouse", "Watch"}
}

local function bcs_regionKeyForPoint(x, y)
    x = tonumber(x) or 0
    y = tonumber(y) or 0
    if x >= 11800 and y <= 4600 then return "louisville" end
    if x >= 12200 and y > 4600 and y <= 6900 then return "valley_station" end
    if x >= 10800 and x <= 12850 and y >= 5600 and y <= 8000 then return "west_point" end
    if x >= 5200 and x <= 7300 and y >= 4700 and y <= 6800 then return "riverside" end
    if x >= 10100 and x <= 11450 and y >= 8500 and y <= 10850 then return "muldraugh" end
    if x >= 7300 and x <= 9100 and y >= 10700 and y <= 12450 then return "rosewood" end
    if x >= 9400 and x <= 10900 and y >= 12100 and y <= 13450 then return "march_ridge" end
    if x >= 6500 and x <= 8500 and y >= 7600 and y <= 9900 then return "ekron" end
    return "farmland"
end

local function bcs_shouldReplaceBaseName(name)
    local value = tostring(name or "")
    if value == "" then return true end
    if string.match(value, "^Base%s+BC%d+$") then return true end
    if string.match(value, "^BC%d+$") then return true end
    if string.match(value, "^[FASWTM]%d+%s+[FASWTM]%d+") then return true end
    return false
end

function NPCBaseCampServerBridge.EnsureBaseHumanName(base, point)
    if type(base) ~= "table" then return nil end
    if not bcs_shouldReplaceBaseName(base.name) then
        base.neutralName = base.neutralName or base.name
        return base.name
    end
    if base.neutralName and tostring(base.neutralName) ~= "" and not bcs_shouldReplaceBaseName(base.neutralName) then
        base.name = base.neutralName
        return base.neutralName
    end

    local regionKey = bcs_regionKeyForPoint(base.x or (point and point.x), base.y or (point and point.y))
    local regions = BCS_REGION_NAME_POOLS[regionKey] or BCS_REGION_NAME_POOLS.farmland
    local archetype = tostring(base.baseArchetype or base.archetype or base.baseType or "urban")
    local suffixes = BCS_ARCHETYPE_NAME_SUFFIXES[archetype] or BCS_ARCHETYPE_NAME_SUFFIXES[tostring(base.baseType or "urban")] or BCS_ARCHETYPE_NAME_SUFFIXES.urban
    local seed = bcs_hashText(tostring(base.id or "") .. ":" .. tostring(base.x or "") .. ":" .. tostring(base.y or "") .. ":" .. tostring(archetype))
    local prefix = regions[(seed % #regions) + 1]
    local suffix = suffixes[(math.floor(seed / 7) % #suffixes) + 1]
    local name = tostring(prefix) .. " " .. tostring(suffix)

    local gmd = NPCBaseCampServerBridge.EnsureData()
    gmd.BaseCampDirector.usedHumanBaseNames = gmd.BaseCampDirector.usedHumanBaseNames or {}
    local used = gmd.BaseCampDirector.usedHumanBaseNames
    if used[name] and tostring(used[name]) ~= tostring(base.id or "") then
        local qualifiers = {"North", "South", "East", "West", "Annex", "Yard", "Post"}
        local qualifier = qualifiers[(math.floor(seed / 13) % #qualifiers) + 1]
        name = tostring(prefix) .. " " .. tostring(qualifier) .. " " .. tostring(suffix)
    end
    used[name] = tostring(base.id or "")
    base.neutralName = name
    base.name = name
    return name
end

local function bcs_zoneMarkerId(zone)
    return "BASEZONE_" .. tostring(zone and zone.id or "unknown")
end

local function bcs_zoneSummary(base)
    local summary = {total=0, command=0, staging=0, storage=0, sleep=0, medical=0, food=0, ammo=0, guard=0, patrol=0, assigned=0, present=0, operational=0, overloaded=0, low=0}
    if type(base) ~= "table" or type(base.zones) ~= "table" then return summary end

    for _, zone in pairs(base.zones) do
        if type(zone) == "table" then
            local zoneType = tostring(zone.zoneType or "unknown")
            summary.total = summary.total + 1
            summary[zoneType] = (tonumber(summary[zoneType]) or 0) + 1
            summary.assigned = summary.assigned + (tonumber(zone.assignedCount) or 0)
            summary.present = summary.present + (tonumber(zone.presentCount) or 0)
            if zone.operational ~= false then summary.operational = summary.operational + 1 end
            if zone.state == "overloaded" then summary.overloaded = summary.overloaded + 1 end
            if zone.state == "low" or zone.state == "critical" then summary.low = summary.low + 1 end
        end
    end

    return summary
end

local function bcs_zoneSummaryHash(base)
    if type(base) ~= "table" or type(base.zones) ~= "table" then return "" end

    local parts = {}
    for _, zone in pairs(base.zones) do
        if type(zone) == "table" then
            local stock = zone.stock or {}
            table.insert(parts, table.concat({
                tostring(zone.id),
                tostring(zone.zoneType),
                tostring(zone.assignedCount or 0),
                tostring(zone.presentCount or 0),
                tostring(math.floor((tonumber(stock.food) or 0) + 0.5)),
                tostring(math.floor((tonumber(stock.medical) or 0) + 0.5)),
                tostring(math.floor((tonumber(stock.ammo) or 0) + 0.5)),
                tostring(math.floor((tonumber(stock.supplies) or 0) + 0.5)),
                tostring(zone.state or "ready"),
                tostring(math.floor((tonumber(zone.readiness) or 0) + 0.5)),
                tostring(math.floor((tonumber(zone.deficitScore) or 0) + 0.5)),
                tostring(math.floor((tonumber(zone.demandScore) or 0) + 0.5))
            }, ":"))
        end
    end

    table.sort(parts)
    return table.concat(parts, "|")
end

local function bcs_stockValueForMarker(base, key, field)
    if type(base) ~= "table" then return 0 end
    local donated = type(base.stock) == "table" and (tonumber(base.stock[key]) or 0) or 0
    local hasZoneStock = type(base.zoneStock) == "table"
    local zoneStock = hasZoneStock and (tonumber(base.zoneStock[key]) or 0) or 0
    if hasZoneStock then return bcs_round(donated + zoneStock) end
    return bcs_round(tonumber(base[field]) or donated or 0)
end

local function bcs_resourceMarkerHash(base)
    if type(base) ~= "table" then return "" end
    local parts = {}
    for _, key in ipairs({"food", "water", "medical", "ammo", "fuel", "materials", "tools", "weapons", "spareParts", "supplies"}) do
        local field = "stock" .. string.upper(string.sub(key, 1, 1)) .. string.sub(key, 2)
        if key == "spareParts" then field = "stockSpareParts" end
        table.insert(parts, tostring(math.floor(bcs_stockValueForMarker(base, key, field) + 0.5)))
    end
    table.insert(parts, tostring(math.floor((tonumber(base.garrisonReadiness) or 0) + 0.5)))
    table.insert(parts, tostring(math.floor((tonumber(base.defenseReadiness) or 0) + 0.5)))
    table.insert(parts, tostring(math.floor((tonumber(base.logisticsReadiness) or 0) + 0.5)))
    table.insert(parts, tostring(math.floor((tonumber(base.foodReadiness) or 0) + 0.5)))
    table.insert(parts, tostring(math.floor((tonumber(base.ammoReadiness) or 0) + 0.5)))
    return table.concat(parts, ":")
end

function NPCBaseCampServerBridge.ShouldForceBaseResourceMarkerSync(base, worldAge)
    if type(base) ~= "table" then return false end
    worldAge = tonumber(worldAge) or bcs_nowHours()
    local hash = bcs_resourceMarkerHash(base)
    local lastHash = tostring(base._lastResourceMarkerHash or "")
    local lastAt = tonumber(base._lastResourceMarkerSyncAt) or 0
    local interval = tonumber(NPCBaseCampServerBridge.BASE_RESOURCE_MARKER_SYNC_HOURS) or 0.20
    if hash ~= lastHash or lastAt <= 0 or worldAge - lastAt >= interval then
        base._lastResourceMarkerHash = hash
        base._lastResourceMarkerSyncAt = worldAge
        return true
    end
    return false
end

local function bcs_makeMarker(base)
    NPCBaseCampServerBridge.EnsureBaseHumanName(base)
    local owner = base.owner
    local captureTeam = base.captureTeam
    local status = base.status or "idle"
    local active = status == "capturing" or status == "decapturing" or status == "contested" or status == "siege_contested" or status == "contested_winning_red" or status == "contested_winning_green" or status == "recovering"
    local economy = base.economy or {}
    local stock = base.stock or {}
    local zoneStock = base.zoneStock or {}

    local marker = {
        id = bcs_markerId(base),
        baseId = base.id,
        markerType = "base",
        x = base.x,
        y = base.y,
        z = base.z or 0,
        name = base.neutralName or base.name or ("Base " .. tostring(base.id)),
        baseType = base.baseType or "urban",
        baseArchetype = base.baseArchetype or base.archetype,
        baseArchetypeLabel = base.baseArchetypeLabel,
        behaviorStyle = base.behaviorStyle,
        presentationStyle = base.presentationStyle,
        lootBias = base.lootBias,
        fortifyLevel = base.fortifyLevel,
        garrisonSize = base.garrisonSize,
        buildingBased = base.buildingBased == true,
        buildingKey = base.buildingKey,
        buildingX = base.buildingX,
        buildingY = base.buildingY,
        buildingX2 = base.buildingX2,
        buildingY2 = base.buildingY2,
        buildingW = base.buildingW,
        buildingH = base.buildingH,
        buildingArea = base.buildingArea,
        owner = owner,
        captureTeam = captureTeam,
        progress = math.floor((tonumber(base.progress) or 0) + 0.5),
        captureProgress = math.floor((tonumber(base.progress) or 0) + 0.5),
        captureStatus = status,
        captureActive = active,
        contested = status == "contested" or status == "siege_contested" or status == "contested_winning_red" or status == "contested_winning_green",
        hostile = owner == "red" or (not owner and captureTeam == "red"),
        friendly = owner == "green" or (not owner and captureTeam == "green"),
        radius = tonumber(base.radius) or bcs_computeBaseRadius(base),
        redCount = base.redCount or 0,
        greenCount = base.greenCount or 0,
        redPower = base.redPower or 0,
        greenPower = base.greenPower or 0,
        capturePower = base.capturePower or 0,
        defensePower = base.defensePower or 0,
        virtualGarrisonPower = base.virtualGarrisonPower or 0,
        virtualGarrisonLosses = base.virtualGarrisonLosses or 0,
        powerAdvantage = base.powerAdvantage or 0,
        homeGroupId = base.homeGroupId,
        zoneVersion = base.zonesVersion or NPCBaseCampServerBridge.ZONE_VERSION,
        zoneCount = base.zoneCount or (bcs_zoneSummary(base).total or 0),
        zoneSummary = bcs_zoneSummary(base),
        stockFood = bcs_stockValueForMarker(base, "food", "stockFood"),
        stockWater = bcs_stockValueForMarker(base, "water", "stockWater"),
        stockMedical = bcs_stockValueForMarker(base, "medical", "stockMedical"),
        stockAmmo = bcs_stockValueForMarker(base, "ammo", "stockAmmo"),
        stockFuel = bcs_stockValueForMarker(base, "fuel", "stockFuel"),
        stockMaterials = bcs_stockValueForMarker(base, "materials", "stockMaterials"),
        stockTools = bcs_stockValueForMarker(base, "tools", "stockTools"),
        stockWeapons = bcs_stockValueForMarker(base, "weapons", "stockWeapons"),
        stockSpareParts = bcs_stockValueForMarker(base, "spareParts", "stockSpareParts"),
        stockSupplies = bcs_stockValueForMarker(base, "supplies", "stockSupplies"),
        economyStatus = economy.status or "unknown",
        needSummary = economy.needSummary or "ok",
        missionCount = economy.missionCount or 0,
        garrisonReadiness = base.garrisonReadiness or 0,
        defenseReadiness = base.defenseReadiness or 0,
        logisticsReadiness = base.logisticsReadiness or 0,
        medicalReadiness = base.medicalReadiness or 0,
        foodReadiness = base.foodReadiness or 0,
        ammoReadiness = base.ammoReadiness or 0,
        operationalZones = base.operationalZones or 0,
        overloadedZones = base.overloadedZones or 0,
        lowZones = base.lowZones or 0,
        zoneNeedSummary = base.zoneNeedSummary or "ok",
        commanderId = base.commanderId,
        commanderName = base.commanderName,
        commanderSide = base.commanderSide,
        commanderState = base.commanderState,
        commanderInfluence = base.commanderInfluence,
        commanderDeadAt = base.commanderDeadAt,
        leaderCrisisUntil = base.leaderCrisisUntil,
        updatedAt = base.updatedAt or bcs_nowHours()
    }
    if NPCLeadersBridge and NPCLeadersBridge.MarkerFields then NPCLeadersBridge.MarkerFields(marker, base) end
    return marker
end

local bcs_brainPosition

function NPCBaseCampServerBridge.SendBaseMarker(base)
    if not base then return false end

    local gmd = NPCBaseCampServerBridge.EnsureData()
    local marker = bcs_makeMarker(base)
    gmd.DebugMapMarkers[marker.id] = marker

    if NPCNetContract and NPCNetContract.SendDebugMapUpdate then
        NPCNetContract.SendDebugMapUpdate(marker)
    else
        sendServerCommand('NPCDebugMap', 'Update', marker)
    end

    return true
end

local function bcs_buildingRelativePoint(base, ux, uy, outside)
    local x1 = tonumber(base.buildingX)
    local y1 = tonumber(base.buildingY)
    local x2 = tonumber(base.buildingX2)
    local y2 = tonumber(base.buildingY2)
    if not x1 or not y1 or not x2 or not y2 then return nil, nil, nil end
    if x2 < x1 then x1, x2 = x2, x1 end
    if y2 < y1 then y1, y2 = y2, y1 end

    local margin = outside and 0 or 2
    local minX = math.min(x2, x1 + margin)
    local maxX = math.max(x1, x2 - margin)
    local minY = math.min(y2, y1 + margin)
    local maxY = math.max(y1, y2 - margin)
    local x = minX + (maxX - minX) * (tonumber(ux) or 0.5)
    local y = minY + (maxY - minY) * (tonumber(uy) or 0.5)

    return math.floor(x + 0.5), math.floor(y + 0.5), tonumber(base.z) or 0
end

local function bcs_buildingZonePoint(base, layout)
    if not base or base.buildingBased ~= true then return nil, nil, nil end

    local label = tostring(layout.label or "")
    local zoneType = tostring(layout.zoneType or "")
    if zoneType == "command" then return bcs_buildingRelativePoint(base, 0.50, 0.50, false) end
    if zoneType == "staging" then return bcs_buildingRelativePoint(base, 0.50, 0.68, false) end
    if zoneType == "storage" then return bcs_buildingRelativePoint(base, 0.25, 0.72, false) end
    if zoneType == "sleep" then return bcs_buildingRelativePoint(base, 0.75, 0.72, false) end
    if zoneType == "medical" then return bcs_buildingRelativePoint(base, 0.25, 0.30, false) end
    if zoneType == "food" then return bcs_buildingRelativePoint(base, 0.75, 0.30, false) end
    if zoneType == "ammo" then return bcs_buildingRelativePoint(base, 0.50, 0.22, false) end

    local x1 = tonumber(base.buildingX)
    local y1 = tonumber(base.buildingY)
    local x2 = tonumber(base.buildingX2)
    local y2 = tonumber(base.buildingY2)
    if not x1 or not y1 or not x2 or not y2 then return nil, nil, nil end
    if x2 < x1 then x1, x2 = x2, x1 end
    if y2 < y1 then y1, y2 = y2, y1 end

    local cx = tonumber(base.x) or math.floor((x1 + x2) / 2 + 0.5)
    local cy = tonumber(base.y) or math.floor((y1 + y2) / 2 + 0.5)
    local pad = 6
    if label == "G1" then return math.floor(x2 + pad), math.floor(y1 - pad), tonumber(base.z) or 0 end
    if label == "G2" then return math.floor(x1 - pad), math.floor(y1 - pad), tonumber(base.z) or 0 end
    if label == "G3" then return math.floor(x1 - pad), math.floor(y2 + pad), tonumber(base.z) or 0 end
    if label == "G4" then return math.floor(x2 + pad), math.floor(y2 + pad), tonumber(base.z) or 0 end
    if label == "P1" then return math.floor(cx), math.floor(y1 - pad * 2), tonumber(base.z) or 0 end
    if label == "P2" then return math.floor(x2 + pad * 2), math.floor(cy), tonumber(base.z) or 0 end
    if label == "P3" then return math.floor(cx), math.floor(y2 + pad * 2), tonumber(base.z) or 0 end
    if label == "P4" then return math.floor(x1 - pad * 2), math.floor(cy), tonumber(base.z) or 0 end

    return nil, nil, nil
end

local function bcs_zonePoint(base, layout)
    local bx, by, bz = bcs_buildingZonePoint(base, layout)
    if bx and by then return bx, by, bz end

    local radius = tonumber(base.radius) or NPCBaseCampServerBridge.BASE_RADIUS
    local angle = math.rad(tonumber(layout.angle) or 0)
    local ring = tonumber(layout.ring) or 0
    local x = math.floor((tonumber(base.x) or 0) + math.cos(angle) * radius * ring + 0.5)
    local y = math.floor((tonumber(base.y) or 0) + math.sin(angle) * radius * ring + 0.5)
    local z = tonumber(base.z) or 0
    return x, y, z
end
local function bcs_zoneTypeCount(zones, zoneType)
    local count = 0
    if type(zones) ~= "table" then return 0 end
    for _, zone in pairs(zones) do
        if type(zone) == "table" and zone.zoneType == zoneType then
            count = count + 1
        end
    end
    return count
end

local function bcs_defaultZoneStock(zoneType)
    local stock = {}
    for _, key in ipairs(BCS_ZONE_RESOURCE_KEYS) do stock[key] = 0 end
    local profile = BCS_ZONE_RESOURCE_PROFILE[zoneType or ""] or {}
    for key, value in pairs(profile.target or {}) do
        stock[key] = math.min(NPCBaseCampServerBridge.ZONE_STOCK_MAX, math.floor((tonumber(value) or 0) * 0.35 + 0.5))
    end
    return stock
end

local function bcs_migrateZoneStock(zoneType, oldStock)
    local stock = bcs_defaultZoneStock(zoneType)
    if type(oldStock) == "table" then
        for _, key in ipairs(BCS_ZONE_RESOURCE_KEYS) do
            if oldStock[key] ~= nil then stock[key] = tonumber(oldStock[key]) or 0 end
        end
    end
    return stock
end

local function bcs_makeZone(base, layout, index, oldZone)
    local x, y, z = bcs_zonePoint(base, layout)
    local zoneType = tostring(layout.zoneType or "misc")
    local typeIndex = bcs_zoneTypeCount(base.zones, zoneType) + 1
    local id = tostring(base.id) .. "_Z" .. tostring(index)
    local bonus = BCS_BASE_TYPE_ZONE_BONUS[base.baseType or "urban"] or BCS_BASE_TYPE_ZONE_BONUS.urban or {}
    local capacity = tonumber(layout.capacity) or 2
    capacity = capacity + (tonumber(bonus[zoneType]) or 0)

    local zone = {
        id = id,
        baseId = base.id,
        zoneIndex = index,
        zoneType = zoneType,
        typeIndex = typeIndex,
        label = tostring(layout.label or string.upper(string.sub(zoneType, 1, 3))),
        duty = layout.duty or zoneType,
        x = x,
        y = y,
        z = z,
        radius = tonumber(layout.radius) or 10,
        capacity = capacity,
        assignedCount = oldZone and oldZone.assignedCount or 0,
        presentCount = oldZone and oldZone.presentCount or 0,
        state = oldZone and oldZone.state or "ready",
        priority = (tonumber(layout.priority) or 0) + (tonumber(bonus[zoneType]) or 0),
        stock = bcs_migrateZoneStock(zoneType, oldZone and oldZone.stock),
        needs = oldZone and oldZone.needs or {},
        assigned = {},
        present = {},
        assignedRoles = oldZone and oldZone.assignedRoles or {},
        assignedCount = 0,
        presentCount = 0,
        operational = oldZone and oldZone.operational ~= false,
        readiness = oldZone and oldZone.readiness or 100,
        demandScore = oldZone and oldZone.demandScore or 0,
        deficitScore = oldZone and oldZone.deficitScore or 0,
        lastStockUpdate = oldZone and oldZone.lastStockUpdate or bcs_nowHours(),
        lastRosterUpdate = oldZone and oldZone.lastRosterUpdate or bcs_nowHours()
    }

    return zone
end

local function bcs_zoneLayoutHash(base)
    if type(base) ~= "table" then return "" end
    return table.concat({
        tostring(bcs_round(base.radius or NPCBaseCampServerBridge.BASE_RADIUS)),
        tostring(base.buildingBased == true),
        tostring(base.buildingKey or ""),
        tostring(base.buildingX or ""),
        tostring(base.buildingY or ""),
        tostring(base.buildingX2 or ""),
        tostring(base.buildingY2 or "")
    }, ":")
end

local function bcs_oldZoneLookup(base)
    local out = {}
    if type(base) ~= "table" or type(base.zones) ~= "table" then return out end

    for _, zone in pairs(base.zones) do
        if type(zone) == "table" then
            local key = tostring(zone.zoneType or "") .. ":" .. tostring(zone.typeIndex or zone.zoneIndex or "")
            out[key] = zone
            if zone.id then out[tostring(zone.id)] = zone end
        end
    end

    return out
end

function NPCBaseCampServerBridge.EnsureBaseZones(base)
    if not base then return false end
    local changed = false

    local desiredRadius = bcs_computeBaseRadius(base)
    if math.abs((tonumber(base.radius) or 0) - desiredRadius) > 0.5 then
        base.radius = desiredRadius
        changed = true
    end

    local layoutHash = bcs_zoneLayoutHash(base)
    if type(base.zones) ~= "table" or base.zonesVersion ~= NPCBaseCampServerBridge.ZONE_VERSION or base.zoneLayoutHash ~= layoutHash then
        local old = bcs_oldZoneLookup(base)
        base.zones = {}
        base.zonesVersion = NPCBaseCampServerBridge.ZONE_VERSION
        base.zoneLayoutHash = layoutHash
        base.zoneLayoutRadius = bcs_round(base.radius or NPCBaseCampServerBridge.BASE_RADIUS)

        for index, layout in ipairs(BCS_ZONE_LAYOUT) do
            local zoneType = tostring(layout.zoneType or "misc")
            local typeIndex = bcs_zoneTypeCount(base.zones, zoneType) + 1
            local oldZone = old[tostring(base.id) .. "_Z" .. tostring(index)] or old[zoneType .. ":" .. tostring(typeIndex)]
            local zone = bcs_makeZone(base, layout, index, oldZone)
            base.zones[zone.id] = zone
        end
        changed = true
    end

    local gmd = NPCBaseCampServerBridge.EnsureData()
    base.zoneCount = 0
    for _, zone in pairs(base.zones or {}) do
        if type(zone) == "table" then
            zone.baseId = base.id
            gmd.BaseCampZones[zone.id] = zone
            base.zoneCount = base.zoneCount + 1
        end
    end

    return changed
end

local function bcs_makeZoneMarker(base, zone)
    local stock = zone.stock or {}
    return {
        id = bcs_zoneMarkerId(zone),
        markerType = "base_zone",
        baseId = base.id,
        parentBaseId = base.id,
        zoneId = zone.id,
        baseZoneId = zone.id,
        zoneType = zone.zoneType,
        zoneIndex = zone.zoneIndex,
        zoneLabel = zone.label,
        duty = zone.duty,
        x = zone.x,
        y = zone.y,
        z = zone.z or 0,
        name = tostring(base.name or base.id) .. " " .. tostring(zone.label or zone.zoneType),
        owner = base.owner,
        captureTeam = base.captureTeam,
        captureStatus = base.status,
        friendly = base.owner == "green" or (not base.owner and base.captureTeam == "green"),
        hostile = base.owner == "red" or (not base.owner and base.captureTeam == "red"),
        radius = zone.radius,
        capacity = zone.capacity,
        assignedCount = zone.assignedCount or 0,
        presentCount = zone.presentCount or 0,
        state = zone.state or "ready",
        operational = zone.operational ~= false,
        readiness = zone.readiness or 0,
        demandScore = zone.demandScore or 0,
        deficitScore = zone.deficitScore or 0,
        assignedRoles = zone.assignedRoles or {},
        stockFood = stock.food or 0,
        stockMedical = stock.medical or 0,
        stockAmmo = stock.ammo or 0,
        stockSupplies = stock.supplies or 0,
        stockWater = stock.water or 0,
        stockMaterials = stock.materials or 0,
        stockSecurity = stock.security or 0,
        updatedAt = base.updatedAt or bcs_nowHours()
    }
end

function NPCBaseCampServerBridge.SendBaseZoneMarker(base, zone)
    if not base or not zone then return false end

    local gmd = NPCBaseCampServerBridge.EnsureData()
    local marker = bcs_makeZoneMarker(base, zone)
    gmd.DebugMapMarkers[marker.id] = marker

    if NPCNetContract and NPCNetContract.SendDebugMapUpdate then
        NPCNetContract.SendDebugMapUpdate(marker)
    else
        sendServerCommand('NPCDebugMap', 'Update', marker)
    end

    return true
end

function NPCBaseCampServerBridge.SendBaseZoneMarkers(base)
    if not base then return false end
    if NPCBaseCampServerBridge.ZONE_MARKERS_ENABLED == false then return false end
    NPCBaseCampServerBridge.EnsureBaseArchetype(base)
    NPCBaseCampServerBridge.EnsureBaseZones(base)

    for _, zone in pairs(base.zones or {}) do
        if NPCTaskQueueBridge and NPCTaskQueueBridge.Enqueue then
            local baseRef = base
            local zoneRef = zone
            NPCTaskQueueBridge.Enqueue(function()
                NPCBaseCampServerBridge.SendBaseZoneMarker(baseRef, zoneRef)
            end, "low", "base_zone_marker")
        else
            NPCBaseCampServerBridge.SendBaseZoneMarker(base, zone)
        end
    end

    return true
end

function NPCBaseCampServerBridge.SendBaseMarkers(base, includeZones)
    if not base then return false end
    NPCBaseCampServerBridge.SendBaseMarker(base)
    if includeZones then
        NPCBaseCampServerBridge.SendBaseZoneMarkers(base)
    end
    return true
end

function NPCBaseCampServerBridge.GetBaseZone(base, zoneId)
    if not base or not zoneId then return nil end
    return base.zones and base.zones[tostring(zoneId)] or nil
end

local function bcs_zoneMatches(zone, wantedType)
    if not zone or not wantedType then return false end
    if zone.zoneType == wantedType then return true end
    if wantedType == "rest" and zone.zoneType == "sleep" then return true end
    if wantedType == "reload" and zone.zoneType == "ammo" then return true end
    if wantedType == "heal" and zone.zoneType == "medical" then return true end
    if wantedType == "stash" and zone.zoneType == "storage" then return true end
    return false
end

function NPCBaseCampServerBridge.FindBestZone(base, wantedType)
    if not base then return nil end
    NPCBaseCampServerBridge.EnsureBaseZones(base)

    local best = nil
    local bestScore = 999999
    for _, zone in pairs(base.zones or {}) do
        if bcs_zoneMatches(zone, wantedType) then
            local assigned = tonumber(zone.assignedCount) or 0
            local cap = math.max(1, tonumber(zone.capacity) or 1)
            local score = (assigned / cap) * 100 - (tonumber(zone.priority) or 0)
            if score < bestScore then
                bestScore = score
                best = zone
            end
        end
    end

    if best then return best end

    for _, zone in pairs(base.zones or {}) do
        if zone and zone.zoneType == "staging" then return zone end
    end

    for _, zone in pairs(base.zones or {}) do
        if zone then return zone end
    end

    return nil
end

local function bcs_normalizedRole(entity)
    if type(entity) ~= "table" then return nil end
    local role = entity.role or entity.tacticalRole or entity.baseRole or entity.job or entity.profession
    if type(role) == "table" then role = role.name or role.id or role[1] end
    if role then return bcs_lower(role) end
    return nil
end

function NPCBaseCampServerBridge.WantedZoneForEntity(entity, stateHint)
    local state = bcs_lower(stateHint or (type(entity) == "table" and (entity.state or entity.order or entity.fsmState)) or "")

    if string.find(state, "heal", 1, true) or string.find(state, "medical", 1, true) then return "medical" end
    if string.find(state, "reload", 1, true) or string.find(state, "ammo", 1, true) then return "ammo" end
    if string.find(state, "eat", 1, true) or string.find(state, "food", 1, true) or string.find(state, "drink", 1, true) then return "food" end
    if string.find(state, "sleep", 1, true) or string.find(state, "rest", 1, true) then return "sleep" end
    if string.find(state, "loot", 1, true) or string.find(state, "scavenge", 1, true) then return "storage" end
    if string.find(state, "guard", 1, true) or string.find(state, "defend", 1, true) then return "guard" end
    if string.find(state, "patrol", 1, true) or string.find(state, "roam", 1, true) then return "patrol" end

    local role = bcs_normalizedRole(entity)
    if role and BCS_ROLE_ZONE[role] then return BCS_ROLE_ZONE[role] end
    if role then
        for key, zoneType in pairs(BCS_ROLE_ZONE) do
            if string.find(role, key, 1, true) then return zoneType end
        end
    end

    return "staging"
end

local function bcs_assignEntityZoneFields(entity, zone)
    if type(entity) ~= "table" or not zone then return false end

    entity.homeBaseZoneId = zone.id
    entity.homeBaseZoneType = zone.zoneType
    entity.homeBaseZone = {x=zone.x, y=zone.y, z=zone.z or 0}
    entity.baseZoneId = zone.id
    entity.baseZoneType = zone.zoneType
    entity.baseDuty = zone.duty or zone.zoneType
    entity.baseDutyState = BCS_ZONE_DUTY_STATE[zone.zoneType] or "ReturnToBase"
    entity.baseDutyReason = "base zone: " .. tostring(zone.zoneType)
    entity.baseDutyUpdatedAt = bcs_nowHours()

    if zone.zoneType == "guard" then
        entity.guardPoint = {x=zone.x, y=zone.y, z=zone.z or 0}
    elseif zone.zoneType == "patrol" then
        entity.patrolPoint = {x=zone.x, y=zone.y, z=zone.z or 0}
    elseif zone.zoneType == "medical" then
        entity.medicalPoint = {x=zone.x, y=zone.y, z=zone.z or 0}
        entity.returnPoint = {x=zone.x, y=zone.y, z=zone.z or 0}
    elseif zone.zoneType == "sleep" then
        entity.restPoint = {x=zone.x, y=zone.y, z=zone.z or 0}
        entity.returnPoint = {x=zone.x, y=zone.y, z=zone.z or 0}
    elseif zone.zoneType == "food" then
        entity.foodPoint = {x=zone.x, y=zone.y, z=zone.z or 0}
        entity.returnPoint = {x=zone.x, y=zone.y, z=zone.z or 0}
    elseif zone.zoneType == "ammo" then
        entity.ammoPoint = {x=zone.x, y=zone.y, z=zone.z or 0}
        entity.returnPoint = {x=zone.x, y=zone.y, z=zone.z or 0}
    elseif zone.zoneType == "storage" then
        entity.storagePoint = {x=zone.x, y=zone.y, z=zone.z or 0}
        entity.returnPoint = {x=zone.x, y=zone.y, z=zone.z or 0}
    else
        entity.returnPoint = {x=zone.x, y=zone.y, z=zone.z or 0}
    end

    return true
end

local function bcs_entityKey(entity, fallback)
    if type(entity) ~= "table" then return fallback and tostring(fallback) or nil end
    return tostring(entity.uid or entity.persistentId or entity.runtimeId or entity.id or entity.memberId or entity.name or entity.fullname or fallback or "unknown")
end

local function bcs_addRoleCount(zone, entity)
    if not zone or type(entity) ~= "table" then return end
    zone.assignedRoles = zone.assignedRoles or {}
    local role = bcs_normalizedRole(entity) or "member"
    zone.assignedRoles[role] = (tonumber(zone.assignedRoles[role]) or 0) + 1
end

local function bcs_addZoneAssignment(zone, amount, entity, fallbackKey)
    if not zone then return end
    amount = math.max(1, tonumber(amount) or 1)
    zone.assignedCount = (tonumber(zone.assignedCount) or 0) + amount
    if entity then
        zone.assigned = zone.assigned or {}
        local key = bcs_entityKey(entity, fallbackKey)
        if key then zone.assigned[key] = true end
        bcs_addRoleCount(zone, entity)
    end
end

local function bcs_addZonePresence(zone, amount, entity, fallbackKey)
    if not zone then return end
    amount = math.max(1, tonumber(amount) or 1)
    zone.presentCount = (tonumber(zone.presentCount) or 0) + amount
    if entity then
        zone.present = zone.present or {}
        local key = bcs_entityKey(entity, fallbackKey)
        if key then zone.present[key] = true end
    end
end

local function bcs_entityHealthRatio(entity)
    if type(entity) ~= "table" then return 1 end
    local health = tonumber(entity.health) or tonumber(entity.fsm and entity.fsm.health)
    local maxHealth = tonumber(entity.maxHealth)
    if health and maxHealth and maxHealth > 0 and health > 1 then return bcs_clamp(health / maxHealth, 0, 1) end
    if health then
        if health > 1 then health = health / 100 end
        return bcs_clamp(health, 0, 1)
    end
    return 1
end

local function bcs_needValue(entity, key)
    if type(entity) ~= "table" then return nil end
    local needs = entity.needs or (entity.ai and entity.ai.needs)
    if type(needs) ~= "table" then return nil end
    return tonumber(needs[key])
end

local function bcs_memberWantedZone(member, groupState)
    if bcs_entityHealthRatio(member) < 0.70 then return "medical" end
    local food = bcs_needValue(member, "food")
    local water = bcs_needValue(member, "water")
    local rest = bcs_needValue(member, "rest")
    if food and food < 0.32 then return "food" end
    if water and water < 0.32 then return "food" end
    if rest and rest < 0.28 then return "sleep" end
    local weapons = type(member) == "table" and member.weapons or nil
    if type(weapons) == "table" then
        for _, slot in ipairs({"primary", "secondary"}) do
            local weapon = weapons[slot]
            if type(weapon) == "table" and weapon.name and (tonumber(weapon.bulletsLeft) or 0) <= 0 and (tonumber(weapon.magCount) or 0) > 0 then
                return "ammo"
            end
        end
    end
    return NPCBaseCampServerBridge.WantedZoneForEntity(member, groupState)
end

function NPCBaseCampServerBridge.AssignGroupZone(base, group, groupId)
    if not base or type(group) ~= "table" then return false end
    NPCBaseCampServerBridge.EnsureBaseArchetype(base)
    NPCBaseCampServerBridge.EnsureBaseZones(base)

    group.baseArchetype = base.baseArchetype
    group.baseArchetypeLabel = base.baseArchetypeLabel
    group.behaviorStyle = base.behaviorStyle
    group.lootBias = base.lootBias

    local wanted = NPCBaseCampServerBridge.WantedZoneForEntity(group, group.state)
    if group.targetBaseId == base.id and group.homeBaseId ~= base.id then
        wanted = "staging"
    elseif group.homeBaseId == base.id and (group.state == "home_base" or group.state == "controlled_base" or not group.state) then
        wanted = "command"
    end

    local groupZone = NPCBaseCampServerBridge.FindBestZone(base, wanted)
    if not groupZone then return false end

    group.homeBaseZoneId = groupZone.id
    group.homeBaseZoneType = groupZone.zoneType
    group.homeBaseZone = {x=groupZone.x, y=groupZone.y, z=groupZone.z or 0}
    group.baseZoneId = groupZone.id
    group.baseZoneType = groupZone.zoneType
    group.baseDuty = groupZone.duty or groupZone.zoneType
    group.baseDutyState = BCS_ZONE_DUTY_STATE[groupZone.zoneType] or "ReturnToBase"
    group.baseDutyReason = "group base zone: " .. tostring(groupZone.zoneType)
    group.baseDutySummary = {command=0, staging=0, storage=0, sleep=0, medical=0, food=0, ammo=0, guard=0, patrol=0}

    if group.homeBaseId == base.id and not group.activated and group.state == "home_base" then
        group.targetX = groupZone.x
        group.targetY = groupZone.y
        group.targetZ = groupZone.z or 0
        group.targetClass = "base_zone_duty"
    end

    local memberCount = 0
    if type(group.members) == "table" then
        for memberIndex, member in pairs(group.members) do
            if type(member) == "table" then
                local memberWanted = bcs_memberWantedZone(member, group.state)
                local memberZone = nil
                local archetype = base.baseArchetype or "raider"
                local nIndex = tonumber(memberIndex) or 1
                if nIndex == 1 and (group.leader == true or group.leaderId or member.leader == true or member.leaderId) then
                    memberZone = NPCBaseCampServerBridge.FindBestZone(base, "command")
                    memberWanted = "command"
                elseif archetype == "checkpoint" then
                    memberWanted = (nIndex % 3 == 0) and "patrol" or "guard"
                elseif archetype == "military" then
                    memberWanted = (nIndex % 4 == 0) and "ammo" or "guard"
                elseif archetype == "elite_safehouse" then
                    memberWanted = (nIndex % 4 == 0) and "command" or "guard"
                elseif archetype == "punk" then
                    memberWanted = (nIndex % 3 == 0) and "staging" or "guard"
                elseif archetype == "raider" then
                    memberWanted = (nIndex % 4 == 0) and "storage" or "guard"
                end
                if not memberZone then
                    memberZone = NPCBaseCampServerBridge.FindBestZone(base, memberWanted) or groupZone
                end
                member.baseArchetype = base.baseArchetype
                member.baseArchetypeLabel = base.baseArchetypeLabel
                member.behaviorStyle = base.behaviorStyle
                member.lootBias = base.lootBias
                member.baseFortifyLevel = base.fortifyLevel
                bcs_assignEntityZoneFields(member, memberZone)
                member.homeBaseId = member.homeBaseId or base.id
                member.homeBase = member.homeBase or {x=base.x, y=base.y, z=base.z or 0}
                member.baseDutyGroupId = group.id or groupId
                member.baseDutyOwner = base.owner
                bcs_addZoneAssignment(memberZone, 1, member, tostring(groupId or "G") .. ":" .. tostring(memberIndex))
                group.baseDutySummary[memberZone.zoneType] = (tonumber(group.baseDutySummary[memberZone.zoneType]) or 0) + 1
                local mx = tonumber(member.x) or tonumber(member.debugCoords and member.debugCoords.x)
                local my = tonumber(member.y) or tonumber(member.debugCoords and member.debugCoords.y)
                if mx and my and bcs_dist(mx, my, memberZone.x, memberZone.y) <= (tonumber(memberZone.radius) or 10) + 8 then
                    bcs_addZonePresence(memberZone, 1, member, tostring(groupId or "G") .. ":" .. tostring(memberIndex))
                end
                memberCount = memberCount + 1
            end
        end
    end

    local abstractCount = math.max(0, (tonumber(group.count) or memberCount or 1) - memberCount)
    if abstractCount > 0 then
        bcs_addZoneAssignment(groupZone, abstractCount, group, groupId)
        if group.x and group.y and bcs_dist(group.x, group.y, groupZone.x, groupZone.y) <= (tonumber(groupZone.radius) or 10) + 16 then
            bcs_addZonePresence(groupZone, abstractCount, group, groupId)
        end
        group.baseDutySummary[groupZone.zoneType] = (tonumber(group.baseDutySummary[groupZone.zoneType]) or 0) + abstractCount
    elseif memberCount <= 0 then
        bcs_addZoneAssignment(groupZone, tonumber(group.count) or 1, group, groupId)
    end

    group.baseRosterUpdatedAt = bcs_nowHours()
    return true
end

function NPCBaseCampServerBridge.AssignBrainZone(base, brain)
    if not base or type(brain) ~= "table" then return false end
    NPCBaseCampServerBridge.EnsureBaseZones(base)

    local state = brain.fsmState or (brain.fsm and brain.fsm.state) or brain.state or brain.order
    local wanted = NPCBaseCampServerBridge.WantedZoneForEntity(brain, state)
    local zone = NPCBaseCampServerBridge.FindBestZone(base, wanted)
    if not zone then return false end

    brain.homeBaseId = brain.homeBaseId or base.id
    brain.homeBase = brain.homeBase or {x=base.x, y=base.y, z=base.z or 0}
    bcs_assignEntityZoneFields(brain, zone)

    local x, y = bcs_brainPosition(brain)
    bcs_addZoneAssignment(zone, 1, brain, brain.uid or brain.id)
    if x and y and bcs_dist(x, y, zone.x, zone.y) <= (tonumber(zone.radius) or 10) + 5 then
        bcs_addZonePresence(zone, 1, brain, brain.uid or brain.id)
    end

    return true
end

local function bcs_resetZoneRuntime(base)
    for _, zone in pairs(base.zones or {}) do
        if type(zone) == "table" then
            zone.assignedCount = 0
            zone.presentCount = 0
            zone.assigned = {}
            zone.present = {}
            zone.assignedRoles = {}
            zone.state = "ready"
        end
    end
end

local function bcs_runtimeCellSize()
    local radius = tonumber(NPCBaseCampServerBridge.BASE_RADIUS) or 36
    local size = radius + 60
    if size < 96 then size = 96 end
    return size
end

local function bcs_runtimeBucketKey(x, y, cellSize)
    local bx = math.floor((tonumber(x) or 0) / cellSize)
    local by = math.floor((tonumber(y) or 0) / cellSize)
    return tostring(bx) .. ":" .. tostring(by), bx, by
end

local function bcs_runtimeEnsureSlot(index, baseId)
    if not index or not baseId then return nil end
    baseId = tostring(baseId)
    local slot = index.byBase[baseId]
    if not slot then
        slot = {groups={}, brains={}, presence={red=0, green=0}}
        index.byBase[baseId] = slot
    end
    return slot
end

local function bcs_runtimeAddCandidateBaseIds(index, x, y, result)
    if not index or not x or not y then return result end
    result = result or {}
    local _, bx, by = bcs_runtimeBucketKey(x, y, index.cellSize)
    local radius = tonumber(NPCBaseCampServerBridge.BASE_RADIUS) or 36
    local br = math.ceil((radius + 60) / index.cellSize) + 1

    for ox=-br, br do
        for oy=-br, br do
            local bucket = index.buckets[tostring(bx + ox) .. ":" .. tostring(by + oy)]
            if bucket then
                for i=1, #bucket do
                    result[bucket[i]] = true
                end
            end
        end
    end

    return result
end

local function bcs_runtimeBuildBaseBuckets(gmd)
    local index = {cellSize=bcs_runtimeCellSize(), buckets={}, byBase={}}

    for id, base in pairs(gmd.BaseCamps or {}) do
        if type(base) == "table" and base.x and base.y then
            local baseId = tostring(id)
            base.id = base.id or baseId
            bcs_runtimeEnsureSlot(index, baseId)
            local key = bcs_runtimeBucketKey(base.x, base.y, index.cellSize)
            local bucket = index.buckets[key]
            if not bucket then
                bucket = {}
                index.buckets[key] = bucket
            end
            bucket[#bucket + 1] = baseId
        end
    end

    return index
end

function NPCBaseCampServerBridge.BuildRuntimeIndex(gmd)
    gmd = gmd or NPCBaseCampServerBridge.EnsureData()
    local index = bcs_runtimeBuildBaseBuckets(gmd)

    for groupId, group in pairs(gmd.VirtualGroups or {}) do
        if type(group) == "table" and (tonumber(group.count) or 0) > 0 then
            local direct = {}
            if group.homeBaseId and gmd.BaseCamps[tostring(group.homeBaseId)] then direct[tostring(group.homeBaseId)] = true end
            if group.targetBaseId and gmd.BaseCamps[tostring(group.targetBaseId)] then direct[tostring(group.targetBaseId)] = true end

            if group.x and group.y and not group.activated then
                bcs_runtimeAddCandidateBaseIds(index, group.x, group.y, direct)
            end

            for baseId, _ in pairs(direct) do
                local base = gmd.BaseCamps[tostring(baseId)]
                if type(base) == "table" then
                    local slot = bcs_runtimeEnsureSlot(index, baseId)
                    local dist = group.x and group.y and bcs_dist(group.x, group.y, base.x, base.y) or 999999
                    local radius = tonumber(base.radius) or NPCBaseCampServerBridge.BASE_RADIUS

                    if tostring(group.homeBaseId or "") == baseId or tostring(group.targetBaseId or "") == baseId then
                        slot.groups[tostring(groupId)] = group
                    end

                    if not group.activated and dist <= radius then
                        local side = bcs_sideForGroup(group)
                        if bcs_sideIsGreen(side) then
                            slot.presence.green = slot.presence.green + (tonumber(group.count) or 1)
                        elseif side == "red" then
                            slot.presence.red = slot.presence.red + (tonumber(group.count) or 1)
                        end
                    end
                end
            end
        end
    end

    for brainId, brain in pairs(gmd.Queue or {}) do
        if type(brain) == "table" then
            local x, y = bcs_brainPosition(brain)
            local direct = {}
            if brain.homeBaseId and gmd.BaseCamps[tostring(brain.homeBaseId)] then direct[tostring(brain.homeBaseId)] = true end
            if brain.baseId and gmd.BaseCamps[tostring(brain.baseId)] then direct[tostring(brain.baseId)] = true end
            if x and y then bcs_runtimeAddCandidateBaseIds(index, x, y, direct) end

            for baseId, _ in pairs(direct) do
                local base = gmd.BaseCamps[tostring(baseId)]
                if type(base) == "table" then
                    local slot = bcs_runtimeEnsureSlot(index, baseId)
                    local dist = x and y and bcs_dist(x, y, base.x, base.y) or 999999
                    local radius = tonumber(base.radius) or NPCBaseCampServerBridge.BASE_RADIUS

                    if tostring(brain.homeBaseId or "") == baseId or tostring(brain.baseId or "") == baseId or dist <= radius + 45 then
                        slot.brains[tostring(brainId)] = brain
                    end

                    if dist <= radius then
                        local side = bcs_sideForBrain(brain)
                        if bcs_sideIsGreen(side) then
                            slot.presence.green = slot.presence.green + 1
                        elseif side == "red" then
                            slot.presence.red = slot.presence.red + 1
                        end
                    end
                end
            end
        end
    end

    index.builtAt = bcs_nowHours()
    return index
end

local function bcs_runtimeSlotForBase(gmd, base)
    if not gmd or not base or not base.id then return nil end
    local index = NPCBaseCampServerBridge._runtimeIndex
    if type(index) ~= "table" or type(index.byBase) ~= "table" then return nil end
    return index.byBase[tostring(base.id)]
end

local function bcs_resourceStatus(zone, key, value, target)
    target = tonumber(target) or 0
    value = tonumber(value) or 0
    if target <= 0 then return "ok", 0, 0 end
    local ratio = value / target
    if ratio < 0.20 then return "critical", target - value, 100 - math.floor(ratio * 100) end
    if ratio < 0.55 then return "low", target - value, 60 - math.floor(ratio * 60) end
    return "ok", 0, 0
end

local function bcs_buildNeedSummary(base)
    local critical = {}
    local low = {}
    for _, zone in pairs(base.zones or {}) do
        if type(zone) == "table" and type(zone.needs) == "table" then
            for key, status in pairs(zone.needs) do
                local token = tostring(zone.zoneType or "zone") .. ":" .. tostring(key)
                if status == "critical" then
                    table.insert(critical, token)
                elseif status == "low" then
                    table.insert(low, token)
                end
            end
        end
    end
    if #critical > 0 then return "critical " .. table.concat(critical, " ") end
    if #low > 0 then return "low " .. table.concat(low, " ") end
    return "ok"
end

local function bcs_readinessForZone(zone)
    local cap = math.max(1, tonumber(zone.capacity) or 1)
    local assigned = math.max(0, tonumber(zone.assignedCount) or 0)
    local present = math.max(0, tonumber(zone.presentCount) or 0)
    local manning = math.min(1.0, ((present * 1.0) + (assigned * 0.35)) / cap)
    local deficit = math.min(100, tonumber(zone.deficitScore) or 0)
    local overloaded = assigned > cap and math.min(35, ((assigned - cap) / cap) * 35) or 0
    local score = math.floor((manning * 70) + 30 - deficit - overloaded + 0.5)
    return bcs_clamp(score, 0, 100)
end

local function bcs_zoneState(zone)
    if (tonumber(zone.assignedCount) or 0) > math.max(1, tonumber(zone.capacity) or 1) then return "overloaded" end
    if (tonumber(zone.deficitScore) or 0) >= 65 then return "critical" end
    if (tonumber(zone.deficitScore) or 0) >= 25 then return "low" end
    if (tonumber(zone.presentCount) or 0) <= 0 and (tonumber(zone.assignedCount) or 0) > 0 then return "assigned" end
    return "ready"
end

local function bcs_accumulateStock(base, worldAge)
    if not base or not base.owner then return end

    bcs_applySettings()

    if basecamp_baseSupply and basecamp_baseSupply.EnsureBaseSupply then
        pcall(function() basecamp_baseSupply.EnsureBaseSupply(base) end)
    end

    local last = tonumber(base.lastZoneStockUpdate) or worldAge
    local dt = worldAge - last
    if dt < 0 then dt = 0 end
    if dt > 0.25 then dt = 0.25 end
    base.lastZoneStockUpdate = worldAge
    if dt <= 0 then return end

    local bonus = BCS_BASE_TYPE_ZONE_BONUS[base.baseType or "urban"] or BCS_BASE_TYPE_ZONE_BONUS.urban or {}
    local total = {}
    for _, key in ipairs(BCS_ZONE_RESOURCE_KEYS) do total[key] = 0 end

    local readinessTotal = 0
    local readinessCount = 0
    local defenseTotal = 0
    local defenseCount = 0
    local logisticsTotal = 0
    local logisticsCount = 0
    local medicalTotal = 0
    local medicalCount = 0
    local foodTotal = 0
    local foodCount = 0
    local ammoTotal = 0
    local ammoCount = 0
    local operationalZones = 0
    local overloadedZones = 0
    local lowZones = 0

    for _, zone in pairs(base.zones or {}) do
        if type(zone) == "table" then
            zone.stock = bcs_migrateZoneStock(zone.zoneType, zone.stock)
            zone.needs = {}
            local workers = math.max(0, tonumber(zone.presentCount) or 0) + math.floor(math.max(0, tonumber(zone.assignedCount) or 0) / 3)
            local population = math.max(0, tonumber(zone.presentCount) or 0, tonumber(zone.assignedCount) or 0)
            local profile = BCS_ZONE_RESOURCE_PROFILE[zone.zoneType or ""] or {}
            local zoneBonus = 1 + ((tonumber(bonus[zone.zoneType]) or 0) * 0.18)
            local demandScore = 0
            local deficitScore = 0

            for key, rate in pairs(profile.produce or {}) do
                local gain = dt * math.max(1, workers) * (tonumber(rate) or 0) * zoneBonus * (NPCBaseCampServerBridge.ZONE_PRODUCTION_RATE or 1.0)
                zone.stock[key] = math.min(NPCBaseCampServerBridge.ZONE_STOCK_MAX, (tonumber(zone.stock[key]) or 0) + gain)
            end

            for key, rate in pairs(profile.consume or {}) do
                local loss = dt * math.max(1, population) * (tonumber(rate) or 0) * (NPCBaseCampServerBridge.ZONE_CONSUMPTION_RATE or 1.0)
                zone.stock[key] = (tonumber(zone.stock[key]) or 0) - loss
                if zone.stock[key] < 0 then
                    deficitScore = deficitScore + math.min(40, math.abs(zone.stock[key]) * 3)
                    zone.stock[key] = 0
                end
            end

            for key, target in pairs(profile.target or {}) do
                local status, deficit, score = bcs_resourceStatus(zone, key, zone.stock[key], target)
                zone.needs[key] = status
                demandScore = demandScore + math.max(0, tonumber(deficit) or 0)
                deficitScore = deficitScore + math.max(0, tonumber(score) or 0)
            end

            zone.demandScore = math.floor(demandScore + 0.5)
            zone.deficitScore = math.floor(math.min(100, deficitScore) + 0.5)
            zone.readiness = bcs_readinessForZone(zone)
            zone.state = bcs_zoneState(zone)
            zone.operational = zone.state ~= "critical" and zone.state ~= "overloaded"
            zone.lastStockUpdate = worldAge

            if zone.operational then operationalZones = operationalZones + 1 end
            if zone.state == "overloaded" then overloadedZones = overloadedZones + 1 end
            if zone.state == "low" or zone.state == "critical" then lowZones = lowZones + 1 end

            readinessTotal = readinessTotal + (tonumber(zone.readiness) or 0)
            readinessCount = readinessCount + 1
            if zone.zoneType == "guard" or zone.zoneType == "patrol" then
                defenseTotal = defenseTotal + (tonumber(zone.readiness) or 0)
                defenseCount = defenseCount + 1
            end
            if zone.zoneType == "storage" or zone.zoneType == "command" or zone.zoneType == "staging" then
                logisticsTotal = logisticsTotal + (tonumber(zone.readiness) or 0)
                logisticsCount = logisticsCount + 1
            end
            if zone.zoneType == "medical" then medicalTotal = medicalTotal + (tonumber(zone.readiness) or 0); medicalCount = medicalCount + 1 end
            if zone.zoneType == "food" then foodTotal = foodTotal + (tonumber(zone.readiness) or 0); foodCount = foodCount + 1 end
            if zone.zoneType == "ammo" then ammoTotal = ammoTotal + (tonumber(zone.readiness) or 0); ammoCount = ammoCount + 1 end

            for _, key in ipairs(BCS_ZONE_RESOURCE_KEYS) do
                total[key] = (tonumber(total[key]) or 0) + (tonumber(zone.stock[key]) or 0)
            end
        end
    end

    base.zoneStock = total
    base.garrisonReadiness = readinessCount > 0 and bcs_round(readinessTotal / readinessCount) or 0
    base.defenseReadiness = defenseCount > 0 and bcs_round(defenseTotal / defenseCount) or 0
    base.logisticsReadiness = logisticsCount > 0 and bcs_round(logisticsTotal / logisticsCount) or 0
    base.medicalReadiness = medicalCount > 0 and bcs_round(medicalTotal / medicalCount) or 0
    base.foodReadiness = foodCount > 0 and bcs_round(foodTotal / foodCount) or 0
    base.ammoReadiness = ammoCount > 0 and bcs_round(ammoTotal / ammoCount) or 0
    base.operationalZones = operationalZones
    base.overloadedZones = overloadedZones
    base.lowZones = lowZones
    base.zoneNeedSummary = bcs_buildNeedSummary(base)

    local donated = type(base.stock) == "table" and base.stock or {}
    base.stockFood = bcs_round((tonumber(donated.food) or 0) + (tonumber(total.food) or 0))
    base.stockWater = bcs_round((tonumber(donated.water) or 0) + (tonumber(total.water) or 0))
    base.stockMedical = bcs_round((tonumber(donated.medical) or 0) + (tonumber(total.medical) or 0))
    base.stockAmmo = bcs_round((tonumber(donated.ammo) or 0) + (tonumber(total.ammo) or 0))
    base.stockFuel = bcs_round((tonumber(donated.fuel) or 0) + (tonumber(total.fuel) or 0))
    base.stockMaterials = bcs_round((tonumber(donated.materials) or 0) + (tonumber(total.materials) or 0))
    base.stockTools = bcs_round((tonumber(donated.tools) or 0) + (tonumber(total.tools) or 0))
    base.stockWeapons = bcs_round((tonumber(donated.weapons) or 0) + (tonumber(total.weapons) or 0))
    base.stockSpareParts = bcs_round((tonumber(donated.spareParts) or 0) + (tonumber(total.spareParts) or 0))
    base.stockSupplies = bcs_round((tonumber(donated.supplies) or 0) + (tonumber(total.supplies) or 0))
    if basecamp_spy and basecamp_spy.SabotageBase then
        pcall(function() basecamp_spy.SabotageBase(NPCBaseCampServerBridge.EnsureData(), base, worldAge) end)
    end
end

function NPCBaseCampServerBridge.UpdateBaseZones(base, worldAge)
    if not base then return false end

    local changed = NPCBaseCampServerBridge.EnsureBaseZones(base)
    local before = base.zoneRuntimeHash or bcs_zoneSummaryHash(base)
    bcs_resetZoneRuntime(base)

    local gmd = NPCBaseCampServerBridge.EnsureData()
    local runtime = bcs_runtimeSlotForBase(gmd, base)
    if runtime then
        for groupId, group in pairs(runtime.groups or {}) do
            NPCBaseCampServerBridge.AssignGroupZone(base, group, groupId)
        end

        for _, brain in pairs(runtime.brains or {}) do
            NPCBaseCampServerBridge.AssignBrainZone(base, brain)
        end
    else
        for groupId, group in pairs(gmd.VirtualGroups or {}) do
            if type(group) == "table" and (group.homeBaseId == base.id or group.targetBaseId == base.id) then
                NPCBaseCampServerBridge.AssignGroupZone(base, group, groupId)
            end
        end

        for _, brain in pairs(gmd.Queue or {}) do
            if type(brain) == "table" then
                local x, y = bcs_brainPosition(brain)
                if brain.homeBaseId == base.id or brain.baseId == base.id or (x and y and bcs_dist(x, y, base.x, base.y) <= (tonumber(base.radius) or NPCBaseCampServerBridge.BASE_RADIUS) + 45) then
                    NPCBaseCampServerBridge.AssignBrainZone(base, brain)
                end
            end
        end
    end

    bcs_accumulateStock(base, worldAge or bcs_nowHours())

    local after = bcs_zoneSummaryHash(base)
    if before ~= after then changed = true end
    base.zoneRuntimeHash = after
    base.zoneCount = bcs_zoneSummary(base).total

    return changed
end

local function bcs_isNearExistingBase(gmd, x, y, radius)
    radius = radius or NPCBaseCampServerBridge.BASE_MIN_DISTANCE
    for _, base in pairs(gmd.BaseCamps or {}) do
        if base and base.x and base.y and bcs_dist(x, y, base.x, base.y) < radius then
            return true
        end
    end
    return false
end

function NPCBaseCampServerBridge.FindStrategicPoint()
    local gmd = NPCBaseCampServerBridge.EnsureData()
    local minX, minY, maxX, maxY = bcs_getWorldBounds()
    local bestPoint = nil
    local bestScore = -1000
    local seenBuildings = {}

    for i=1, NPCBaseCampServerBridge.SEARCH_ATTEMPTS do
        local x = minX + ZombRand(math.max(1, maxX - minX))
        local y = minY + ZombRand(math.max(1, maxY - minY))

        local buildingPoint = bcs_findBuildingNear(x, y, NPCBaseCampServerBridge.BUILDING_SEARCH_RADIUS, NPCBaseCampServerBridge.BUILDING_SEARCH_STEP)
        if buildingPoint and buildingPoint.buildingKey and not seenBuildings[buildingPoint.buildingKey] then
            seenBuildings[buildingPoint.buildingKey] = true
            if not bcs_isNearExistingBase(gmd, buildingPoint.x, buildingPoint.y, NPCBaseCampServerBridge.BASE_MIN_DISTANCE) then
                if buildingPoint.score > bestScore then
                    bestScore = buildingPoint.score
                    bestPoint = buildingPoint
                    if buildingPoint.score >= 300 then
                        break
                    end
                end
            end
        end
    end

    if bestPoint and bestPoint.score >= 140 then
        return bestPoint
    end

    return nil
end

function NPCBaseCampServerBridge.CreateStrategicPoint(force)
    local gmd = NPCBaseCampServerBridge.EnsureData()
    if not NPCBaseCampServerBridge.IsEnabled() then return false end
    if bcs_count(gmd.BaseCamps) >= NPCBaseCampServerBridge.MAX_BASES then return false end

    local point = NPCBaseCampServerBridge.FindStrategicPoint()
    if not point then return false end

    local id = "BC" .. tostring(gmd.BaseCampDirector.nextBaseId)
    gmd.BaseCampDirector.nextBaseId = gmd.BaseCampDirector.nextBaseId + 1

    local baseType = point.baseType or bcs_baseTypeFromZones(point.zoneTypes, point.reason)
    local baseRadius = bcs_computeBaseRadius(point)
    local base = {
        id = id,
        x = point.x,
        y = point.y,
        z = point.z or 0,
        name = "Base " .. tostring(id),
        baseType = baseType,
        buildingBased = point.buildingBased == true,
        buildingKey = point.buildingKey,
        buildingX = point.buildingX,
        buildingY = point.buildingY,
        buildingX2 = point.buildingX2,
        buildingY2 = point.buildingY2,
        buildingW = point.buildingW,
        buildingH = point.buildingH,
        buildingArea = point.buildingArea,
        radius = baseRadius,
        owner = nil,
        captureTeam = nil,
        progress = 0,
        status = "idle",
        redCount = 0,
        greenCount = 0,
        score = point.score or 0,
        reason = point.reason or baseType,
        createdAt = bcs_nowHours(),
        updatedAt = bcs_nowHours()
    }

    NPCBaseCampServerBridge.EnsureBaseArchetype(base, point)
    NPCBaseCampServerBridge.EnsureBaseHumanName(base, point)
    NPCBaseCampServerBridge.EnsureBaseZones(base)
    if basecamp_factionEconomy and basecamp_factionEconomy.SyncBaseStockFields then
        base.stock = base.stock or {}
        basecamp_factionEconomy.SyncBaseStockFields(base)
    end
    gmd.BaseCamps[id] = base
    NPCBaseCampServerBridge.SendBaseMarkers(base, true)
    return base
end

function NPCBaseCampServerBridge.MigrateBaseToBuilding(base)
    if type(base) ~= "table" then return false end
    if base.buildingBased == true then return false end
    if base.buildingMigrationChecked == true then return false end

    base.buildingMigrationChecked = true
    local point = bcs_findBuildingNear(base.x, base.y, math.max(NPCBaseCampServerBridge.BUILDING_SEARCH_RADIUS or 96, 192), NPCBaseCampServerBridge.BUILDING_SEARCH_STEP)
    if not point or point.buildingBased ~= true then return false end

    base.x = point.x
    base.y = point.y
    base.z = point.z or base.z or 0
    base.baseType = point.baseType or base.baseType or bcs_baseTypeFromZones(point.zoneTypes, point.reason)
    base.reason = point.reason or base.reason or base.baseType
    base.score = point.score or base.score or 0
    base.buildingBased = true
    base.buildingKey = point.buildingKey
    base.buildingX = point.buildingX
    base.buildingY = point.buildingY
    base.buildingX2 = point.buildingX2
    base.buildingY2 = point.buildingY2
    base.buildingW = point.buildingW
    base.buildingH = point.buildingH
    base.buildingArea = point.buildingArea
    base.radius = bcs_computeBaseRadius(base)
    base.baseArchetype = nil
    base.archetype = nil
    NPCBaseCampServerBridge.EnsureBaseArchetype(base, point)
    base.updatedAt = bcs_nowHours()
    base.zonesVersion = 0

    return true
end

function bcs_brainPosition(brain)
    if not brain then return nil, nil, nil end

    if basecamp_gmd and basecamp_gmd.GetBrainPosition then
        local ok, x, y, z = pcall(function()
            return basecamp_gmd.GetBrainPosition(brain)
        end)
        if ok and x and y then return tonumber(x), tonumber(y), tonumber(z) or 0 end
    end

    if brain.debugCoords and brain.debugCoords.x and brain.debugCoords.y then
        return tonumber(brain.debugCoords.x), tonumber(brain.debugCoords.y), tonumber(brain.debugCoords.z) or 0
    end
    if brain.x and brain.y then
        return tonumber(brain.x), tonumber(brain.y), tonumber(brain.z) or 0
    end
    if brain.bornCoords and brain.bornCoords.x and brain.bornCoords.y then
        return tonumber(brain.bornCoords.x), tonumber(brain.bornCoords.y), tonumber(brain.bornCoords.z) or 0
    end

    return nil, nil, nil
end

local function bcs_groupStrategicPower(gmd, group)
    if type(group) ~= "table" then return 0 end
    if NPCStrategicAIBridge and NPCStrategicAIBridge.EvaluateGroupCombatPower then
        pcall(function() NPCStrategicAIBridge.EvaluateGroupCombatPower(gmd, group) end)
    end
    local count = tonumber(group.count) or 0
    local power = tonumber(group.strategicPower) or 0
    if power <= 0 then power = math.max(1, count) * 18 end
    if group.strategicActivityType == "SiegeBase" then power = power * 1.10 end
    if group.strategicActivityType == "RetreatToBase" then power = power * 0.70 end
    return power
end

local function bcs_archetypeDefenseFactor(base)
    local archetype = base and (base.baseArchetype or base.archetype) or nil
    if archetype == "elite_safehouse" then return 1.35 end
    if archetype == "military" then return 1.25 end
    if archetype == "checkpoint" then return 1.18 end
    if archetype == "raider" then return 1.05 end
    if archetype == "punk" then return 0.96 end
    return 1.0
end

function NPCBaseCampServerBridge.UpdateVirtualGarrisonPower(base, worldAge)
    if type(base) ~= "table" then return 0 end
    if NPCBaseCampServerBridge.VIRTUAL_GARRISON_POWER_ENABLED == false then return 0 end
    NPCBaseCampServerBridge.EnsureBaseArchetype(base)
    local garrisonSize = tonumber(base.garrisonSize) or 5
    local losses = tonumber(base.virtualGarrisonLosses) or 0
    if losses < 0 then losses = 0 end
    local effective = math.max(0, garrisonSize - losses)
    local fortify = tonumber(base.fortifyLevel) or 1
    local logistics = (tonumber(base.logisticsReadiness) or 70) / 100
    local ammo = (tonumber(base.ammoReadiness) or 70) / 100
    local defense = (tonumber(base.defenseReadiness) or 70) / 100
    local readiness = bcs_clamp((logistics + ammo + defense) / 3, 0.30, 1.25)
    local commander = base.commanderDeadAt and 0.88 or ((base.commanderId or base.commanderName) and 1.08 or 1.0)
    local power = effective * (18 + fortify * 6) * bcs_archetypeDefenseFactor(base) * readiness * commander
    base.virtualGarrisonPower = math.floor(power + 0.5)
    base.virtualGarrisonEffective = effective
    base.virtualGarrisonUpdatedAt = worldAge or bcs_nowHours()
    return base.virtualGarrisonPower
end

function NPCBaseCampServerBridge.GetPresencePower(base)
    local gmd = NPCBaseCampServerBridge.EnsureData()
    local runtime = bcs_runtimeSlotForBase(gmd, base)
    if runtime and runtime.presence then
        local red = tonumber(runtime.presence.red) or 0
        local green = tonumber(runtime.presence.green) or 0
        local redPower = red * 18
        local greenPower = green * 18
        local garrisonPower = NPCBaseCampServerBridge.UpdateVirtualGarrisonPower(base, bcs_nowHours())
        if base.owner == "red" then
            redPower = redPower + garrisonPower
        elseif base.owner == "green" then
            greenPower = greenPower + garrisonPower
        end
        return red, green, redPower, greenPower
    end

    local redCount = 0
    local greenCount = 0
    local redPower = 0
    local greenPower = 0
    local radius = tonumber(base.radius) or NPCBaseCampServerBridge.BASE_RADIUS

    for _, group in pairs(gmd.VirtualGroups or {}) do
        if group and not group.activated and group.x and group.y and (tonumber(group.count) or 0) > 0 then
            if bcs_dist(group.x, group.y, base.x, base.y) <= radius then
                local side = bcs_sideForGroup(group)
                local count = tonumber(group.count) or 1
                local power = bcs_groupStrategicPower(gmd, group)
                if bcs_sideIsGreen(side) then
                    greenCount = greenCount + count
                    greenPower = greenPower + power
                elseif side == "red" then
                    redCount = redCount + count
                    redPower = redPower + power
                end
            end
        end
    end

    for _, brain in pairs(gmd.Queue or {}) do
        if type(brain) == "table" then
            local x, y = bcs_brainPosition(brain)
            if x and y and bcs_dist(x, y, base.x, base.y) <= radius then
                local side = bcs_sideForBrain(brain)
                if bcs_sideIsGreen(side) then
                    greenCount = greenCount + 1
                    greenPower = greenPower + 18
                elseif side == "red" then
                    redCount = redCount + 1
                    redPower = redPower + 18
                end
            end
        end
    end

    local garrisonPower = NPCBaseCampServerBridge.UpdateVirtualGarrisonPower(base, bcs_nowHours())
    if base.owner == "red" then
        redPower = redPower + garrisonPower
    elseif base.owner == "green" then
        greenPower = greenPower + garrisonPower
    end

    return redCount, greenCount, redPower, greenPower
end

function NPCBaseCampServerBridge.GetPresence(base)
    local redCount, greenCount = NPCBaseCampServerBridge.GetPresencePower(base)
    return redCount, greenCount
end

local function bcs_sameBaseState(a, b)
    if not a or not b then return false end
    return a.owner == b.owner
        and a.captureTeam == b.captureTeam
        and a.status == b.status
        and math.floor((tonumber(a.progress) or 0) + 0.5) == math.floor((tonumber(b.progress) or 0) + 0.5)
        and (tonumber(a.redCount) or 0) == (tonumber(b.redCount) or 0)
        and (tonumber(a.greenCount) or 0) == (tonumber(b.greenCount) or 0)
        and math.floor((tonumber(a.redPower) or 0) + 0.5) == math.floor((tonumber(b.redPower) or 0) + 0.5)
        and math.floor((tonumber(a.greenPower) or 0) + 0.5) == math.floor((tonumber(b.greenPower) or 0) + 0.5)
end

local function bcs_snapshotBase(base)
    return {
        owner = base.owner,
        captureTeam = base.captureTeam,
        status = base.status,
        progress = base.progress,
        redCount = base.redCount,
        greenCount = base.greenCount,
        redPower = base.redPower,
        greenPower = base.greenPower
    }
end

function NPCBaseCampServerBridge.AssignHomeBase(base, side)
    if not base or not side then return false end

    NPCBaseCampServerBridge.EnsureBaseZones(base)
    local gmd = NPCBaseCampServerBridge.EnsureData()
    local nearestGroup = nil
    local nearestDist = 999999

    for groupId, group in pairs(gmd.VirtualGroups or {}) do
        if group and bcs_sideForGroup(group) == side and group.x and group.y and (tonumber(group.count) or 0) > 0 then
            local d = bcs_dist(group.x, group.y, base.x, base.y)
            if d < nearestDist and d <= NPCBaseCampServerBridge.HOME_ASSIGN_RADIUS then
                nearestDist = d
                nearestGroup = group
                nearestGroup.id = nearestGroup.id or tostring(groupId)
            end
        end
    end

    if nearestGroup then
        nearestGroup.homeBaseId = base.id
        nearestGroup.homeBase = {x=base.x, y=base.y, z=base.z or 0}
        nearestGroup.targetBaseId = nil
        nearestGroup.state = nearestGroup.activated and nearestGroup.state or "home_base"
        NPCBaseCampServerBridge.AssignGroupZone(base, nearestGroup, nearestGroup.id)
        if type(nearestGroup.members) == "table" then
            for _, member in pairs(nearestGroup.members) do
                member.homeBaseId = base.id
                member.homeBase = {x=base.x, y=base.y, z=base.z or 0}
            end
        end
        base.homeGroupId = nearestGroup.id
        return true
    end

    return false
end

function NPCBaseCampServerBridge.CapturePowerStep(attackerPower, defenderPower)
    attackerPower = math.max(0, tonumber(attackerPower) or 0)
    defenderPower = math.max(0, tonumber(defenderPower) or 0)
    if attackerPower <= 0 then return 0 end
    if defenderPower <= 0 then
        return bcs_clamp(0.70 + attackerPower / 220, NPCBaseCampServerBridge.CAPTURE_MIN_POWER_STEP, NPCBaseCampServerBridge.CAPTURE_MAX_POWER_STEP)
    end
    local total = math.max(1, attackerPower + defenderPower)
    local advantage = (attackerPower - defenderPower) / total
    return bcs_clamp(0.22 + advantage * 2.4, NPCBaseCampServerBridge.CAPTURE_MIN_POWER_STEP, NPCBaseCampServerBridge.CAPTURE_MAX_POWER_STEP)
end

function NPCBaseCampServerBridge.LogStrategicBaseEvent(eventName, base, fields)
    if NPCWorldDirectorBridge and NPCWorldDirectorBridge.BehaviorLog then
        fields = fields or {}
        fields.baseId = fields.baseId or (base and base.id)
        fields.owner = fields.owner or (base and base.owner)
        fields.captureTeam = fields.captureTeam or (base and base.captureTeam)
        fields.status = fields.status or (base and base.status)
        fields.progress = fields.progress or (base and math.floor((tonumber(base.progress) or 0) + 0.5))
        NPCWorldDirectorBridge.BehaviorLog(basecamp_worldDirector or NPCWorldDirectorBridge, eventName, fields)
    end
end

function NPCBaseCampServerBridge.UpdateCapture(base, worldAge)
    if not base then return false end

    local before = bcs_snapshotBase(base)
    local redCount, greenCount, redPower, greenPower = NPCBaseCampServerBridge.GetPresencePower(base)
    local ownerBefore = base.owner

    base.redCount = redCount
    base.greenCount = greenCount
    base.redPower = math.floor((redPower or 0) + 0.5)
    base.greenPower = math.floor((greenPower or 0) + 0.5)

    local lastUpdate = tonumber(base.lastCaptureUpdate) or worldAge
    local dt = worldAge - lastUpdate
    if dt < 0 then dt = 0 end
    if dt > 0.10 then dt = 0.10 end
    base.lastCaptureUpdate = worldAge

    local side = nil
    local attackerPower = 0
    local defenderPower = 0
    local advantage = tonumber(NPCBaseCampServerBridge.CAPTURE_POWER_ADVANTAGE) or 1.14
    if redPower > 0 and greenPower > 0 then
        if redPower >= greenPower * advantage then
            side = "red"
            attackerPower = redPower
            defenderPower = greenPower
            base.status = "contested_winning_red"
        elseif greenPower >= redPower * advantage then
            side = "green"
            attackerPower = greenPower
            defenderPower = redPower
            base.status = "contested_winning_green"
        else
            base.status = "siege_contested"
            attackerPower = math.max(redPower, greenPower)
            defenderPower = math.min(redPower, greenPower)
        end
    elseif redPower > 0 then
        side = "red"
        attackerPower = redPower
        defenderPower = 0
    elseif greenPower > 0 then
        side = "green"
        attackerPower = greenPower
        defenderPower = 0
    end

    base.capturePower = math.floor((attackerPower or 0) + 0.5)
    base.defensePower = math.floor((defenderPower or 0) + 0.5)
    if attackerPower > 0 and defenderPower > 0 then
        base.powerAdvantage = math.floor((attackerPower / math.max(1, defenderPower)) * 100 + 0.5)
    else
        base.powerAdvantage = 0
    end

    if side then
        local step = 0
        if NPCBaseCampServerBridge.CAPTURE_HOURS > 0 then
            step = (dt / NPCBaseCampServerBridge.CAPTURE_HOURS) * 100
        end
        if step < 0 then step = 0 end
        step = step * NPCBaseCampServerBridge.CapturePowerStep(attackerPower, defenderPower)

        if base.owner == side then
            base.captureTeam = nil
            if (tonumber(base.progress) or 100) < 100 then
                base.progress = (tonumber(base.progress) or 0) + step * 0.45
                base.status = "recovering"
            else
                base.progress = 100
                base.status = "controlled"
            end
        elseif base.owner and base.owner ~= side then
            base.captureTeam = side
            base.status = base.status == "siege_contested" and "siege_contested" or "decapturing"
            base.progress = (tonumber(base.progress) or 100) - step
            if base.progress <= 0 then
                base.previousOwner = base.owner
                base.lostBy = base.owner
                base.lostAt = worldAge
                base.owner = nil
                base.progress = 0
                base.status = "capturing"
            end
        else
            if base.captureTeam ~= side then
                base.captureTeam = side
                if (tonumber(base.progress) or 0) <= 0 then base.progress = 0 end
            end
            base.status = "capturing"
            base.progress = (tonumber(base.progress) or 0) + step
            if base.progress >= 100 then
                base.owner = side
                base.captureTeam = nil
                base.progress = 100
                base.status = "controlled"
                base.virtualGarrisonLosses = 0
                NPCBaseCampServerBridge.UpdateVirtualGarrisonPower(base, worldAge)
            end
        end
    elseif redPower <= 0 and greenPower <= 0 then
        if base.owner then
            base.captureTeam = nil
            base.progress = 100
            base.status = "controlled"
        elseif base.captureTeam and (tonumber(base.progress) or 0) > 0 then
            base.status = "paused"
        else
            base.captureTeam = nil
            base.progress = 0
            base.status = "idle"
        end
    end

    if base.progress < 0 then base.progress = 0 end
    if base.progress > 100 then base.progress = 100 end
    base.updatedAt = worldAge

    if ownerBefore ~= base.owner then
        NPCBaseCampServerBridge.LogStrategicBaseEvent("base_owner_changed", base, {oldOwner=ownerBefore, newOwner=base.owner, redPower=base.redPower, greenPower=base.greenPower, redCount=base.redCount, greenCount=base.greenCount})
        if basecamp_factionEconomy and basecamp_factionEconomy.OnBaseOwnerChanged then
            basecamp_factionEconomy.OnBaseOwnerChanged(base, ownerBefore, base.owner)
        else
            if ownerBefore and ownerBefore ~= base.owner then
                base.previousOwner = ownerBefore
                base.lostBy = ownerBefore
                base.lostAt = worldAge
            end
            if base.owner then
                base.capturedBy = base.owner
                base.capturedAt = worldAge
            end
        end
    elseif not bcs_sameBaseState(before, base) and (base.status == "siege_contested" or base.status == "contested_winning_red" or base.status == "contested_winning_green" or base.status == "decapturing" or base.status == "capturing") then
        local lastCaptureLogAt = tonumber(base.lastCaptureLogAt) or 0
        if lastCaptureLogAt <= 0 or worldAge - lastCaptureLogAt >= 0.18 or math.abs((tonumber(base.progress) or 0) - (tonumber(base.lastCaptureLogProgress) or -999)) >= 12 then
            base.lastCaptureLogAt = worldAge
            base.lastCaptureLogProgress = tonumber(base.progress) or 0
            NPCBaseCampServerBridge.LogStrategicBaseEvent("base_capture_tick", base, {redPower=base.redPower, greenPower=base.greenPower, redCount=base.redCount, greenCount=base.greenCount, capturePower=base.capturePower, defensePower=base.defensePower})
        end
    end

    if ownerBefore ~= base.owner and base.owner then
        NPCBaseCampServerBridge.AssignHomeBase(base, base.owner)
    end

    return not bcs_sameBaseState(before, base)
end

local function bcs_baseOwnedBySide(base, side)
    return base and base.owner == side
end

function NPCBaseCampServerBridge.FindTargetBaseForGroup(group)
    if not group or group.activated or group.inBattle or group.roadPatrol or group.economyMissionId then return nil end
    if not group.x or not group.y then return nil end

    local gmd = NPCBaseCampServerBridge.EnsureData()
    local side = bcs_sideForGroup(group)
    local bestBase = nil
    local bestScore = 999999

    for _, base in pairs(gmd.BaseCamps or {}) do
        if base and base.x and base.y and not bcs_baseOwnedBySide(base, side) then
            local d = bcs_dist(group.x, group.y, base.x, base.y)
            if d <= NPCBaseCampServerBridge.GROUP_TARGET_RADIUS then
                local score = d
                if base.owner and base.owner ~= side then score = score - 250 end
                if base.captureTeam == side then score = score - 120 end
                if score < bestScore then
                    bestScore = score
                    bestBase = base
                end
            end
        end
    end

    return bestBase
end

function NPCBaseCampServerBridge.AssignVirtualGroupTargets()
    local gmd = NPCBaseCampServerBridge.EnsureData()
    local changed = false

    for groupId, group in pairs(gmd.VirtualGroups or {}) do
        if group and not group.activated and not group.inBattle and not group.roadPatrol and not group.economyMissionId and (tonumber(group.count) or 0) > 0 then
            local base = nil
            if group.targetBaseId then
                local current = gmd.BaseCamps[tostring(group.targetBaseId)]
                if current and not bcs_baseOwnedBySide(current, bcs_sideForGroup(group)) then
                    base = current
                end
            end

            base = base or NPCBaseCampServerBridge.FindTargetBaseForGroup(group)
            if base and (group.targetBaseId ~= base.id or group.targetClass ~= "base_capture") then
                group.targetX = base.x
                group.targetY = base.y
                group.targetZ = base.z or 0
                group.targetClass = "base_capture"
                group.targetBaseId = base.id
                group.state = "moving_to_base"
                group.updatedAt = bcs_nowHours()
                gmd.VirtualGroups[groupId] = group
                changed = true
            elseif group.targetBaseId then
                local own = gmd.BaseCamps[tostring(group.targetBaseId)]
                if own and bcs_baseOwnedBySide(own, bcs_sideForGroup(group)) then
                    group.targetBaseId = nil
                    group.state = group.homeBaseId and "home_base" or "roaming"
                    gmd.VirtualGroups[groupId] = group
                    changed = true
                end
            end
        end
    end

    return changed
end

function NPCBaseCampServerBridge.GetBaseCamps()
    return NPCBaseCampServerBridge.EnsureData().BaseCamps or {}
end

function NPCBaseCampServerBridge.GetNearbyBase(x, y, radius)
    local searchRadius = tonumber(radius)
    local nearest = nil
    local nearestDist = 999999

    for _, base in pairs(NPCBaseCampServerBridge.GetBaseCamps()) do
        if base and base.x and base.y then
            local d = bcs_dist(x, y, base.x, base.y)
            local baseRadius = searchRadius or tonumber(base.radius) or bcs_computeBaseRadius(base)
            if d <= baseRadius and d < nearestDist then
                nearest = base
                nearestDist = d
            end
        end
    end

    return nearest, nearestDist
end

function NPCBaseCampServerBridge.GetCaptureState(baseId)
    local gmd = NPCBaseCampServerBridge.EnsureData()
    if not baseId then return nil end
    return gmd.BaseCamps[tostring(baseId)]
end

function NPCBaseCampServerBridge.Init()
    bcs_applySettings()
    local gmd = NPCBaseCampServerBridge.EnsureData()
    if not NPCBaseCampServerBridge.IsEnabled() then return false end

    if not gmd.BaseCampDirector.initialized then
        gmd.BaseCampDirector.initialized = true
        gmd.BaseCampDirector.lastUpdate = bcs_nowHours()
        NPCBaseCampServerBridge.CreateStrategicPoint(true)
    end

    for _, base in pairs(gmd.BaseCamps or {}) do
        NPCBaseCampServerBridge.EnsureBaseZones(base)
        NPCBaseCampServerBridge.SendBaseMarkers(base, true)
    end

    return true
end


local function bcs_windowBarricade(square, window, planks)
    if not (square and window and IsoBarricade and IsoBarricade.AddBarricadeToObject) then return false end
    local barricade = nil
    if window.getBarricadeOnSameSquare then
        local ok, got = pcall(function() return window:getBarricadeOnSameSquare() end)
        if ok and got then barricade = got end
    end
    if not barricade and window.getBarricadeOnOppositeSquare then
        local ok, got = pcall(function() return window:getBarricadeOnOppositeSquare() end)
        if ok and got then barricade = got end
    end
    if not barricade then
        local ok, got = pcall(function() return IsoBarricade.AddBarricadeToObject(window, nil) end)
        if ok then barricade = got end
    end
    if not barricade then return false end
    local target = math.max(1, math.min(4, tonumber(planks) or 2))
    for _=1, target do
        local okCount, count = pcall(function() return barricade:getNumPlanks() end)
        count = okCount and tonumber(count) or 0
        if count >= target then break end
        local plank = NPCCompatibilityBridge and NPCCompatibilityBridge.InstanceItem and NPCCompatibilityBridge.InstanceItem("Base.Plank") or nil
        if not plank then break end
        pcall(function() barricade:addPlank(nil, plank) end)
    end
    if barricade.transmitCompleteItemToClients then
        pcall(function() barricade:transmitCompleteItemToClients() end)
    elseif barricade.sendObjectChange then
        pcall(function() barricade:sendObjectChange('state') end)
    end
    return true
end

local function bcs_baseSquareInside(base, square)
    if not (base and square) then return false end
    local x = square:getX()
    local y = square:getY()
    if base.buildingBased == true and base.buildingX and base.buildingX2 and base.buildingY and base.buildingY2 then
        return x >= tonumber(base.buildingX) and x <= tonumber(base.buildingX2) and y >= tonumber(base.buildingY) and y <= tonumber(base.buildingY2)
    end
    local radius = tonumber(base.radius) or NPCBaseCampServerBridge.BASE_RADIUS or 36
    return bcs_dist(x, y, base.x, base.y) <= radius
end

function NPCBaseCampServerBridge.PrepareBasePresentation(base, worldAge)
    if type(base) ~= "table" or not base.x or not base.y then return false end
    local cell = getCell and getCell() or nil
    if not cell then return false end
    local config = NPCBaseCampServerBridge.EnsureBaseArchetype(base)
    local changed = false
    local x1 = math.floor(tonumber(base.buildingX) or (tonumber(base.x) or 0) - 6)
    local y1 = math.floor(tonumber(base.buildingY) or (tonumber(base.y) or 0) - 6)
    local x2 = math.floor(tonumber(base.buildingX2) or (tonumber(base.x) or 0) + 6)
    local y2 = math.floor(tonumber(base.buildingY2) or (tonumber(base.y) or 0) + 6)
    local fortifyNeeded = tonumber(base.visualFortifiedAt or 0) <= 0
    local fortifyLevel = math.max(1, math.min(4, tonumber(base.fortifyLevel or config and config.fortifyLevel) or 2))
    local barricadeLimit = 8 + fortifyLevel * 5
    local barricaded = 0
    for z = 0, 1 do
        for x = x1 - 1, x2 + 1 do
            for y = y1 - 1, y2 + 1 do
                local square = cell:getGridSquare(x, y, z)
                if square and bcs_baseSquareInside(base, square) then
                    local objects = square.getObjects and square:getObjects() or nil
                    if objects then
                        for i = 0, objects:size() - 1 do
                            local object = objects:get(i)
                            if basecamp_worldObjects and basecamp_worldObjects.IsDoorObject and basecamp_worldObjects.IsDoorObject(object) then
                                if basecamp_worldObjects.SetDoorLockedByKey then
                                    local okUnlock, didUnlock = pcall(function() return basecamp_worldObjects.SetDoorLockedByKey(square, object, false) end)
                                    if okUnlock and didUnlock then changed = true end
                                end
                            end
                        end
                    end
                    if fortifyNeeded and barricaded < barricadeLimit and z == 0 then
                        local window = square.getWindow and square:getWindow() or nil
                        if window then
                            local okOut, outside = pcall(function() return square:isOutside() end)
                            if not okOut or outside ~= true then
                                local okBarr, did = pcall(function() return bcs_windowBarricade(square, window, fortifyLevel) end)
                                if okBarr and did then
                                    barricaded = barricaded + 1
                                    changed = true
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    if fortifyNeeded and barricaded > 0 then
        base.visualFortifiedAt = tonumber(worldAge) or bcs_nowHours()
        base.visualStyle = base.presentationStyle or (config and config.visualStyle) or "fortified_base"
    end
    base.doorsUnlockedAt = tonumber(worldAge) or bcs_nowHours()
    return changed
end

function NPCBaseCampServerBridge.UpdateWorld()
    bcs_applySettings()
    if not NPCBaseCampServerBridge.IsEnabled() then return false end

    local gmd = NPCBaseCampServerBridge.EnsureData()
    local worldAge = bcs_nowHours()
    local changed = false

    if not gmd.BaseCampDirector.initialized then
        NPCBaseCampServerBridge.Init()
    end

    if bcs_count(gmd.BaseCamps) < NPCBaseCampServerBridge.MAX_BASES then
        local lastSearch = tonumber(gmd.BaseCampDirector.lastSearch) or 0
        if worldAge - lastSearch >= 0.05 then
            gmd.BaseCampDirector.lastSearch = worldAge
            if NPCBaseCampServerBridge.CreateStrategicPoint(false) then
                changed = true
            end
        end
    end

    NPCBaseCampServerBridge._runtimeIndex = NPCBaseCampServerBridge.BuildRuntimeIndex(gmd)

    for id, base in pairs(gmd.BaseCamps or {}) do
        local migrated = NPCBaseCampServerBridge.MigrateBaseToBuilding(base)
        local captureChanged = NPCBaseCampServerBridge.UpdateCapture(base, worldAge)
        local zonesChanged = NPCBaseCampServerBridge.UpdateBaseZones(base, worldAge)
        local presentationChanged = NPCBaseCampServerBridge.PrepareBasePresentation(base, worldAge)
        local resourceMarkerChanged = NPCBaseCampServerBridge.ShouldForceBaseResourceMarkerSync(base, worldAge)
        if migrated then zonesChanged = true end
        if captureChanged or zonesChanged or presentationChanged or resourceMarkerChanged then
            gmd.BaseCamps[id] = base
            NPCBaseCampServerBridge.SendBaseMarkers(base, captureChanged or zonesChanged or presentationChanged)
            changed = true
        end
    end

    if NPCBaseCampServerBridge.AssignVirtualGroupTargets() then
        changed = true
    end

    if NPCInfluenceFieldBridge and NPCInfluenceFieldBridge.UpdateFromBases then
        NPCInfluenceFieldBridge.UpdateFromBases(gmd)
    end

    gmd.BaseCampDirector.lastUpdate = worldAge
    return changed
end

function NPCBaseCampServerBridge.Update()
    return NPCBaseCampServerBridge.UpdateWorld()
end

function NPCBaseCampServerBridge.OnClientCommand(module, command, player, args)
    if not NPCLegacyContractBridge.IsModule(module, "NPCBaseCamp", "baseCamp") then return false end
    if command == "RequestSync" then
        local gmd = NPCBaseCampServerBridge.EnsureData()
        for _, base in pairs(gmd.BaseCamps or {}) do
            NPCBaseCampServerBridge.EnsureBaseZones(base)
            local marker = bcs_makeMarker(base)
            if NPCNetContract and NPCNetContract.SendDebugMapUpdate then
                NPCNetContract.SendDebugMapUpdate(marker, player)
            elseif player then
                sendServerCommand(player, 'NPCDebugMap', 'Update', marker)
            else
                sendServerCommand('NPCDebugMap', 'Update', marker)
            end
            if NPCBaseCampServerBridge.ZONE_MARKERS_ENABLED ~= false then
                for _, zone in pairs(base.zones or {}) do
                    local zoneMarker = bcs_makeZoneMarker(base, zone)
                    if NPCNetContract and NPCNetContract.SendDebugMapUpdate then
                        NPCNetContract.SendDebugMapUpdate(zoneMarker, player)
                    elseif player then
                        sendServerCommand(player, 'NPCDebugMap', 'Update', zoneMarker)
                    else
                        sendServerCommand('NPCDebugMap', 'Update', zoneMarker)
                    end
                end
            end
        end
        return true
    end
    return false
end

local function bcs_onTick()
    NPCBaseCampServerBridge._tick = NPCBaseCampServerBridge._tick + 1

    if NPCBaseCampServerBridge._tick == 240 then
        NPCBaseCampServerBridge.Init()
    elseif NPCBaseCampServerBridge._tick % 240 == 0 then
        NPCBaseCampServerBridge.UpdateWorld()
    end
end

local function bcs_everyTenMinutes()
    NPCBaseCampServerBridge.UpdateWorld()
end

local function bcs_onClientCommand(module, command, player, args)
    NPCBaseCampServerBridge.OnClientCommand(module, command, player, args)
end

if not NPCBaseCampServerBridge._eventsInstalled then
    Events.OnTick.Add(bcs_onTick)
    Events.EveryTenMinutes.Add(bcs_everyTenMinutes)
    Events.OnClientCommand.Add(bcs_onClientCommand)
    NPCBaseCampServerBridge._eventsInstalled = true
    print("[NPCBaseCampServerBridge] Strategic base capture + zone system enabled")
end
