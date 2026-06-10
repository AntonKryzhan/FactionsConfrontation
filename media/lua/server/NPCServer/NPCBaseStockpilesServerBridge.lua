-- NPCBaseStockpilesServerBridge.lua
-- Stage 368: visible faction economy stockpiles.
-- Server-only physical stockpile materializer for base supply resources.
-- It does not add UI boards, panels or new marker systems. Base stock becomes
-- tangible only when a player approaches an owned base and enough stock exists.

if isClient and isClient() then return end

require "NPCCore/NPCLegacyContractBridge"
pcall(require, "NPCCore/NPCLegacySettingsBridge")
pcall(require, "NPCCore/NPCDiagnosticsBridge")
pcall(require, "NPCServer/NPCBaseCampServerBridge")
pcall(require, "NPCServer/NPCBaseSupplyServerBridge")
pcall(require, "NPCCore/NPCCompatibilityBridge")

NPCBaseStockpilesServerBridge = NPCBaseStockpilesServerBridge or {}
NPCBaseStockpilesServerBridge.Version = 1
NPCBaseStockpilesServerBridge._tick = NPCBaseStockpilesServerBridge._tick or 0
NPCBaseStockpilesServerBridge._cursor = NPCBaseStockpilesServerBridge._cursor or 0

local BSS_RESOURCES = {
    "food", "ammo", "weapons", "armor", "magazines", "weaponParts", "maintenance", "clothing"
}

local BSS_LABELS = {
    food = "Food stockpile",
    ammo = "Ammo stockpile",
    weapons = "Armory stockpile",
    armor = "Armor stockpile",
    magazines = "Magazine stockpile",
    weaponParts = "Weapon-parts stockpile",
    maintenance = "Maintenance stockpile",
    clothing = "Clothing stockpile"
}

local BSS_CONTAINERS = {
    food = {"Base.Plasticbag", "Base.Lunchbox", "Base.Bag_Satchel", "Base.Handbag"},
    ammo = {"Base.Toolbox", "Base.Plasticbag", "Base.Duffelbag", "Base.Bag_Satchel"},
    weapons = {"Base.Duffelbag", "Base.Bag_Satchel", "Base.Plasticbag"},
    armor = {"Base.Duffelbag", "Base.Bag_Satchel", "Base.Plasticbag"},
    magazines = {"Base.Toolbox", "Base.Plasticbag", "Base.Bag_Satchel"},
    weaponParts = {"Base.Toolbox", "Base.Plasticbag", "Base.Bag_Satchel"},
    maintenance = {"Base.Toolbox", "Base.Plasticbag", "Base.Bag_Satchel"},
    clothing = {"Base.Duffelbag", "Base.Bag_Satchel", "Base.Plasticbag"},
    default = {"Base.Plasticbag", "Base.Bag_Satchel", "Base.Handbag"}
}

local BSS_ITEMS = {
    food = {"Base.CannedSoup", "Base.CannedBeans", "Base.CannedCorn", "Base.Crisps", "Base.WaterBottleFull", "Base.TinnedSoup"},
    ammo = {"Base.9mmBullets", "Base.ShotgunShells", "Base.308Bullets", "Base.223Bullets", "Base.Bullets9mmBox", "Base.ShotgunShellsBox"},
    weapons = {"Base.Pistol", "Base.Shotgun", "Base.HuntingKnife", "Base.Axe", "Base.Crowbar", "Base.BaseballBat"},
    armor = {"Base.BulletproofVest", "Base.ArmorMag1", "Base.Hat_Army", "Base.Hat_HardHat"},
    magazines = {"Base.9mmClip", "Base.45Clip", "Base.223Clip", "Base.308Clip"},
    weaponParts = {"Base.x2Scope", "Base.IronSight", "Base.RedDot", "Base.RecoilPad", "Base.Sling"},
    maintenance = {"Base.WD40", "Base.Glue", "Base.DuctTape", "Base.ScrewsBox", "Base.NailsBox", "Base.CleaningLiquid2"},
    clothing = {"Base.Jacket_ArmyCamoGreen", "Base.Trousers_ArmyService", "Base.Shirt_CamoGreen", "Base.Shoes_ArmyBoots", "Base.Gloves_LeatherGloves"},
    default = {"Base.SheetPaper2", "Base.Plasticbag"}
}

local function bss_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        local ok, value = pcall(function() return NPCLegacySettingsBridge.GetBool(name, defaultValue == true) end)
        if ok and value ~= nil then return value == true end
    end
    return defaultValue == true
end

local function bss_num(name, defaultValue, minValue, maxValue)
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

local function bss_now()
    if getGameTime then
        local ok, value = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok and value then return tonumber(value) or 0 end
    end
    return 0
end

local function bss_rand(maxValue)
    maxValue = math.floor(tonumber(maxValue) or 0)
    if maxValue <= 0 then return 0 end
    if ZombRand then
        local ok, value = pcall(function() return ZombRand(maxValue) end)
        if ok and value ~= nil then return tonumber(value) or 0 end
    end
    return math.random(0, maxValue - 1)
end

local function bss_distSq(ax, ay, bx, by)
    ax = tonumber(ax) or 0
    ay = tonumber(ay) or 0
    bx = tonumber(bx) or 0
    by = tonumber(by) or 0
    local dx = ax - bx
    local dy = ay - by
    return dx * dx + dy * dy
end

local function bss_players()
    local out = {}
    if getOnlinePlayers then
        local ok, list = pcall(function() return getOnlinePlayers() end)
        if ok and list and list.size and list.get then
            for i = 0, list:size() - 1 do
                local okPlayer, player = pcall(function() return list:get(i) end)
                if okPlayer and player then out[#out + 1] = player end
            end
        end
    end
    if #out == 0 and getPlayer then
        local ok, player = pcall(function() return getPlayer() end)
        if ok and player then out[#out + 1] = player end
    end
    return out
end

local function bss_baseCamps(gmd)
    if NPCBaseCampServerBridge and NPCBaseCampServerBridge.GetBaseCamps then
        local ok, camps = pcall(function() return NPCBaseCampServerBridge.GetBaseCamps() end)
        if ok and type(camps) == "table" then return camps end
    end
    return gmd and gmd.BaseCamps or {}
end

local function bss_side(base)
    if type(base) ~= "table" then return nil end
    return base.owner or base.captureTeam or base.side or base.factionSide
end

local function bss_inventoryItem(fullType)
    if not fullType then return nil end
    if NPCCompatibilityBridge and NPCCompatibilityBridge.InstanceItem then
        local ok, item = pcall(function() return NPCCompatibilityBridge.InstanceItem(fullType) end)
        if ok and item then return item end
    end
    if InventoryItemFactory and InventoryItemFactory.CreateItem then
        local ok, item = pcall(function() return InventoryItemFactory.CreateItem(fullType) end)
        if ok and item then return item end
    end
    return nil
end

local function bss_pickInventoryItem(candidates)
    if type(candidates) ~= "table" then return nil end
    local start = bss_rand(#candidates) + 1
    for offset = 0, #candidates - 1 do
        local idx = ((start + offset - 1) % #candidates) + 1
        local item = bss_inventoryItem(candidates[idx])
        if item then return item, candidates[idx] end
    end
    return nil, nil
end

local function bss_addItem(inv, fullType)
    if not (inv and inv.AddItem and fullType) then return false end
    local ok, item = pcall(function() return inv:AddItem(fullType) end)
    return ok and item ~= nil
end

local function bss_addStockItems(inv, resource, amount)
    local items = BSS_ITEMS[resource] or BSS_ITEMS.default
    local maxItems = math.floor(bss_num("BaseStockpile_MaxItemsPerContainer", 8, 1, 40))
    local count = math.max(1, math.min(maxItems, math.floor(tonumber(amount) or 1)))
    local added = 0
    for i = 1, count do
        local fullType = items[((i + bss_rand(#items)) - 1) % #items + 1]
        if bss_addItem(inv, fullType) then added = added + 1 end
    end
    return added
end

local function bss_findSquareNear(x, y, z, radius)
    if not getCell then return nil end
    local cell = getCell()
    if not (cell and cell.getGridSquare) then return nil end
    x = math.floor(tonumber(x) or 0)
    y = math.floor(tonumber(y) or 0)
    z = math.floor(tonumber(z) or 0)
    radius = math.max(1, math.floor(tonumber(radius) or 8))
    for attempt = 1, math.max(10, radius * 5) do
        local dx = bss_rand(radius * 2 + 1) - radius
        local dy = bss_rand(radius * 2 + 1) - radius
        local ok, square = pcall(function() return cell:getGridSquare(x + dx, y + dy, z) end)
        if ok and square then return square, x + dx, y + dy, z end
    end
    local ok, square = pcall(function() return cell:getGridSquare(x, y, z) end)
    if ok then return square, x, y, z end
    return nil
end

local function bss_resourceStock(base, resource)
    if not (type(base) == "table" and resource) then return 0 end
    if NPCBaseSupplyServerBridge and NPCBaseSupplyServerBridge.EnsureBaseSupply then
        pcall(function() NPCBaseSupplyServerBridge.EnsureBaseSupply(base) end)
    end
    local stock = base.stock or {}
    local value = tonumber(stock[resource]) or 0
    if value <= 0 then
        local field = "stock" .. string.upper(string.sub(resource, 1, 1)) .. string.sub(resource, 2)
        value = tonumber(base[field]) or 0
    end
    return math.max(0, math.floor(value + 0.5))
end

local function bss_consumeStock(base, resource, amount)
    if not (type(base) == "table" and resource) then return 0 end
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount <= 0 then return 0 end
    if NPCBaseSupplyServerBridge and NPCBaseSupplyServerBridge.EnsureBaseSupply then
        pcall(function() NPCBaseSupplyServerBridge.EnsureBaseSupply(base) end)
    end
    base.stock = base.stock or {}
    base.donatedStock = base.donatedStock or {}
    local current = tonumber(base.stock[resource]) or 0
    local used = math.min(amount, math.max(0, math.floor(current + 0.5)))
    if used <= 0 then return 0 end
    base.stock[resource] = math.max(0, current - used)
    if base.donatedStock[resource] ~= nil then
        base.donatedStock[resource] = math.max(0, (tonumber(base.donatedStock[resource]) or 0) - used)
    end
    if NPCBaseSupplyServerBridge and NPCBaseSupplyServerBridge.SyncBaseFields then
        pcall(function() NPCBaseSupplyServerBridge.SyncBaseFields(base) end)
    end
    return used
end

local function bss_markContainer(item, base, resource, amount, x, y, z)
    if not (item and item.getModData and base) then return end
    local ok, md = pcall(function() return item:getModData() end)
    if not (ok and type(md) == "table") then return end
    local id = "BSTOCK_" .. tostring(base.id or "base") .. "_" .. tostring(resource) .. "_" .. tostring(math.floor(bss_now() * 1000)) .. "_" .. tostring(bss_rand(9999))
    md.baseStockpile = true
    md.baseStockpileId = id
    md.baseStockpileVersion = NPCBaseStockpilesServerBridge.Version
    md.baseId = base.id
    md.baseStockpileResource = resource
    md.baseStockpileAmount = amount
    md.baseStockpileOwner = bss_side(base)
    md.factionSide = bss_side(base)
    md.worldNameplate = true
    md.worldNameplateTitle = string.upper(tostring(BSS_LABELS[resource] or "Base stockpile"))
    md.worldNameplateSubtitle = "x" .. tostring(amount)
    if item.setName then pcall(function() item:setName(BSS_LABELS[resource] or "Base stockpile") end) end
    if item.transmitModData then pcall(function() item:transmitModData() end) end
    return id
end

local function bss_placeStockpile(base, resource, amount)
    if not (type(base) == "table" and base.x and base.y) then return false end
    local square, sx, sy, sz = bss_findSquareNear(base.x, base.y, base.z or 0, bss_num("BaseStockpile_PlacementRadius", 9, 1, 32))
    if not (square and square.AddWorldInventoryItem) then return false end

    local container, containerType = bss_pickInventoryItem(BSS_CONTAINERS[resource] or BSS_CONTAINERS.default)
    if not container then return false end
    local inv = nil
    if container.getInventory then
        local okInv, gotInv = pcall(function() return container:getInventory() end)
        if okInv then inv = gotInv end
    end
    local added = bss_addStockItems(inv, resource, amount)
    if added <= 0 and inv then
        -- keep the stockpile useful even if a heavily-modded item name is missing
        bss_addItem(inv, "Base.SheetPaper2")
    end

    local id = bss_markContainer(container, base, resource, amount, sx, sy, sz)
    local ox = 0.22 + (bss_rand(56) / 100.0)
    local oy = 0.22 + (bss_rand(56) / 100.0)
    local okWorld = pcall(function() return square:AddWorldInventoryItem(container, ox, oy, 0) end)
    if not okWorld then return false end

    base.physicalStockpiles = base.physicalStockpiles or {}
    base.physicalStockpiles[id or tostring(resource) .. tostring(bss_now())] = {
        id = id,
        resource = resource,
        amount = amount,
        itemCount = added,
        container = containerType,
        x = sx,
        y = sy,
        z = sz,
        createdAt = bss_now(),
        owner = bss_side(base)
    }
    base.physicalStockpileLastAt = bss_now()
    base.physicalStockpileCount = (tonumber(base.physicalStockpileCount) or 0) + 1
    return true
end

local function bss_activeCount(base)
    if type(base.physicalStockpiles) ~= "table" then return 0 end
    local now = bss_now()
    local ttl = bss_num("BaseStockpile_RecordTTLHours", 72, 1, 720)
    local count = 0
    for key, record in pairs(base.physicalStockpiles) do
        if type(record) == "table" and now - (tonumber(record.createdAt) or now) <= ttl then
            count = count + 1
        else
            base.physicalStockpiles[key] = nil
        end
    end
    return count
end

local function bss_chooseResource(base)
    local minStock = bss_num("BaseStockpile_MinVirtualStock", 4, 1, 100)
    local candidates = {}
    for _, resource in ipairs(BSS_RESOURCES) do
        local stock = bss_resourceStock(base, resource)
        if stock >= minStock then
            candidates[#candidates + 1] = {resource=resource, stock=stock, score=stock + bss_rand(7)}
        end
    end
    table.sort(candidates, function(a, b) return (a.score or 0) > (b.score or 0) end)
    return candidates[1]
end

local function bss_nearPlayer(base, players)
    if not (base and base.x and base.y and type(players) == "table") then return false end
    local radius = bss_num("BaseStockpile_SpawnDistance", 105, 24, 360)
    local r2 = radius * radius
    for _, player in ipairs(players) do
        if player and player.getX and player.getY then
            local ok, px, py = pcall(function() return player:getX(), player:getY() end)
            if ok and bss_distSq(base.x, base.y, px, py) <= r2 then return true end
        end
    end
    return false
end

function NPCBaseStockpilesServerBridge.TryMaterializeBase(base, players)
    if not bss_bool("BaseStockpile_PhysicalEnabled", true) then return false end
    if type(base) ~= "table" or not bss_side(base) then return false end
    if not bss_nearPlayer(base, players) then return false end
    local now = bss_now()
    local cooldown = bss_num("BaseStockpile_CooldownHours", 10, 0.1, 240)
    if now - (tonumber(base.physicalStockpileLastAt) or -9999) < cooldown then return false end
    local maxActive = math.floor(bss_num("BaseStockpile_MaxActivePerBase", 3, 1, 12))
    if bss_activeCount(base) >= maxActive then return false end

    local chosen = bss_chooseResource(base)
    if not chosen then return false end
    local portion = bss_num("BaseStockpile_StockPortion", 0.22, 0.01, 1.0)
    local maxPer = bss_num("BaseStockpile_MaxStockPerContainer", 10, 1, 80)
    local amount = math.max(1, math.min(maxPer, math.floor((tonumber(chosen.stock) or 0) * portion + 0.5)))
    amount = bss_consumeStock(base, chosen.resource, amount)
    if amount <= 0 then return false end
    if not bss_placeStockpile(base, chosen.resource, amount) then
        -- If the cell is not loaded or item placement failed, return the stock to the base.
        base.stock = base.stock or {}
        base.stock[chosen.resource] = (tonumber(base.stock[chosen.resource]) or 0) + amount
        base.donatedStock = base.donatedStock or {}
        base.donatedStock[chosen.resource] = (tonumber(base.donatedStock[chosen.resource]) or 0) + amount
        if NPCBaseSupplyServerBridge and NPCBaseSupplyServerBridge.SyncBaseFields then
            pcall(function() NPCBaseSupplyServerBridge.SyncBaseFields(base) end)
        end
        return false
    end
    if NPCBaseSupplyServerBridge and NPCBaseSupplyServerBridge.SendBaseUpdate then
        pcall(function() NPCBaseSupplyServerBridge.SendBaseUpdate(base, nil) end)
    end
    if NPCDiagnosticsBridge and NPCDiagnosticsBridge.LogRiskAction then
        NPCDiagnosticsBridge.LogRiskAction("base_stockpiles", "stockpile_materialized", {baseId=base.id or base.baseId, owner=base.owner, category=category, amount=amount, x=sx, y=sy}, "stockpile:" .. tostring(base.id or base.baseId) .. ":" .. tostring(category), true)
    end
    return true
end

function NPCBaseStockpilesServerBridge.Update()
    if not bss_bool("BaseStockpile_PhysicalEnabled", true) then return 0 end
    local players = bss_players()
    if #players <= 0 then return 0 end
    local gmd = GetNPCModData and GetNPCModData() or nil
    local camps = bss_baseCamps(gmd)
    if type(camps) ~= "table" then return 0 end
    local maxPerRun = math.floor(bss_num("BaseStockpile_MaxMaterializePerRun", 1, 1, 8))
    local made = 0
    for _, base in pairs(camps) do
        if made >= maxPerRun then break end
        if NPCBaseStockpilesServerBridge.TryMaterializeBase(base, players) then made = made + 1 end
    end
    return made
end

function NPCBaseStockpilesServerBridge.Install()
    if NPCBaseStockpilesServerBridge._installed then return end
    NPCBaseStockpilesServerBridge._installed = true
    if Events and Events.OnTick then
        Events.OnTick.Add(function()
            NPCBaseStockpilesServerBridge._tick = (NPCBaseStockpilesServerBridge._tick or 0) + 1
            local interval = math.floor(bss_num("BaseStockpile_UpdateTicks", 900, 120, 7200))
            if NPCBaseStockpilesServerBridge._tick % interval == 37 then
                local load = 0
                if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.GetLoadLevel then
                    local ok, value = pcall(function() return NPCWorkSchedulerBridge.GetLoadLevel(false) end)
                    if ok then load = tonumber(value) or 0 end
                end
                if load < 2 then NPCBaseStockpilesServerBridge.Update() end
            end
        end)
    end
    if Events and Events.EveryTenMinutes then Events.EveryTenMinutes.Add(NPCBaseStockpilesServerBridge.Update) end
end

NPCBaseStockpilesServerBridge.Install()

print("[NPCBaseStockpilesServerBridge] Visible base stockpiles enabled")
