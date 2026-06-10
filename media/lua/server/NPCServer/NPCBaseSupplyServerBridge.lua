-- NPCBaseSupplyServerBridge.lua
-- Neutral server backend for player-to-base supply slots and donated gear distribution.
-- Isolated layer: does not change spawn/materialization pipeline and does not
-- call a heavy full mod-data transmit. It stores the exact donated item types
-- on the base and gradually assigns them to base squads / nearby convoys.

if isClient and isClient() then return end

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCCompatibilityBridge"
require "NPCCore/NPCRuntimeCacheBridge"
require "NPCServer/NPCBaseCampServerBridge"
require "NPCServer/NPCContractsServerBridge"

NPCBaseSupplyServerBridge = NPCBaseSupplyServerBridge or {}
NPCBaseSupplyServerBridge.Enabled = true
NPCBaseSupplyServerBridge.Version = 3
NPCBaseSupplyServerBridge.DONATE_RADIUS_PAD = NPCBaseSupplyServerBridge.DONATE_RADIUS_PAD or 18
NPCBaseSupplyServerBridge.GEAR_SHARE_RADIUS = NPCBaseSupplyServerBridge.GEAR_SHARE_RADIUS or 560
NPCBaseSupplyServerBridge.MAX_ITEMS_PER_DONATION = NPCBaseSupplyServerBridge.MAX_ITEMS_PER_DONATION or 80
NPCBaseSupplyServerBridge.MAX_NPCS_PER_UPDATE = NPCBaseSupplyServerBridge.MAX_NPCS_PER_UPDATE or 24
NPCBaseSupplyServerBridge._tick = NPCBaseSupplyServerBridge._tick or 0

local BBS_RESOURCES = {"food", "clothing", "weapons", "armor", "ammo", "magazines", "weaponParts", "maintenance"}

local function bbs_nowHours()
    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then
            local ok, value = pcall(function() return gt:getWorldAgeHours() end)
            if ok and value then return tonumber(value) or 0 end
        end
    end
    return 0
end

local function bbs_dist(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return math.sqrt(dx * dx + dy * dy)
end

local function bbs_lower(value)
    if not value then return "" end
    return string.lower(tostring(value))
end

local function bbs_itemCacheKey(item)
    if type(item) ~= "table" then return nil end
    return tostring(item.fullType or item.type or item.name or "")
        .. "|" .. tostring(item.category or "")
        .. "|" .. tostring(item.displayCategory or "")
        .. "|" .. tostring(item.bodyLocation or "")
        .. "|" .. tostring(item.partType or "")
end

local function bbs_getBaseCamps(gmd)
    if NPCBaseCampServerBridge and NPCBaseCampServerBridge.GetBaseCamps then
        local ok, camps = pcall(function() return NPCBaseCampServerBridge.GetBaseCamps() end)
        if ok and type(camps) == "table" then return camps end
    end
    return gmd and gmd.BaseCamps or {}
end

local function bbs_getBaseById(gmd, baseId)
    if not baseId then return nil end
    local camps = bbs_getBaseCamps(gmd)
    return camps and camps[tostring(baseId)] or nil
end

local function bbs_sideForBase(base)
    if not base then return nil end
    return base.owner or base.captureTeam
end

local function bbs_sideForGroup(group)
    if type(group) ~= "table" then return nil end
    if group.convoyFaction then return tostring(group.convoyFaction) end
    if group.patrolColor == "green" or group.hostile == false then return "green" end
    if group.patrolColor == "red" or group.hostile == true then return "red" end
    return nil
end

local function bbs_findNearbyBase(gmd, x, y, baseId)
    local camps = bbs_getBaseCamps(gmd)
    if baseId and camps then
        local base = camps[tostring(baseId)]
        if base and base.x and base.y then
            local d = bbs_dist(x, y, base.x, base.y)
            local radius = (tonumber(base.radius) or (NPCBaseCampServerBridge and NPCBaseCampServerBridge.BASE_RADIUS) or 82) + NPCBaseSupplyServerBridge.DONATE_RADIUS_PAD
            if d <= radius then return base, d end
        end
    end

    local best = nil
    local bestDist = 999999
    for _, base in pairs(camps or {}) do
        if type(base) == "table" and base.x and base.y then
            local radius = (tonumber(base.radius) or (NPCBaseCampServerBridge and NPCBaseCampServerBridge.BASE_RADIUS) or 82) + NPCBaseSupplyServerBridge.DONATE_RADIUS_PAD
            local d = bbs_dist(x, y, base.x, base.y)
            if d <= radius and d < bestDist then
                best = base
                bestDist = d
            end
        end
    end
    return best, bestDist
end

function NPCBaseSupplyServerBridge.EnsureBaseSupply(base)
    if type(base) ~= "table" then return nil end
    base.stock = base.stock or {}
    base.donatedStock = base.donatedStock or {}
    base.donatedItems = base.donatedItems or {}
    base.donatedStats = base.donatedStats or {totalItems=0, totalDonations=0}
    base.donatedWeaponKits = base.donatedWeaponKits or {}
    base.donatedAttachedWeaponParts = tonumber(base.donatedAttachedWeaponParts) or 0

    for _, resource in ipairs(BBS_RESOURCES) do
        if base.stock[resource] == nil then base.stock[resource] = 0 end
        if base.donatedStock[resource] == nil then base.donatedStock[resource] = 0 end
        if type(base.donatedItems[resource]) ~= "table" then base.donatedItems[resource] = {} end
    end

    return base.donatedItems
end

function NPCBaseSupplyServerBridge.SyncBaseFields(base)
    if type(base) ~= "table" then return end
    NPCBaseSupplyServerBridge.EnsureBaseSupply(base)

    base.stockFood = math.floor((tonumber(base.stock.food) or tonumber(base.stockFood) or 0) + 0.5)
    base.stockClothing = math.floor((tonumber(base.stock.clothing) or tonumber(base.stockClothing) or 0) + 0.5)
    base.stockWeapons = math.floor((tonumber(base.stock.weapons) or tonumber(base.stockWeapons) or 0) + 0.5)
    base.stockArmor = math.floor((tonumber(base.stock.armor) or tonumber(base.stockArmor) or 0) + 0.5)
    base.stockAmmo = math.floor((tonumber(base.stock.ammo) or tonumber(base.stockAmmo) or 0) + 0.5)
    base.stockMagazines = math.floor((tonumber(base.stock.magazines) or tonumber(base.stockMagazines) or 0) + 0.5)
    base.stockWeaponParts = math.floor((tonumber(base.stock.weaponParts) or tonumber(base.stockWeaponParts) or 0) + 0.5)
    base.stockMaintenance = math.floor((tonumber(base.stock.maintenance) or tonumber(base.stockMaintenance) or 0) + 0.5)

    base.donatedFood = math.floor((tonumber(base.donatedStock.food) or 0) + 0.5)
    base.donatedClothing = math.floor((tonumber(base.donatedStock.clothing) or 0) + 0.5)
    base.donatedWeapons = math.floor((tonumber(base.donatedStock.weapons) or 0) + 0.5)
    base.donatedArmor = math.floor((tonumber(base.donatedStock.armor) or 0) + 0.5)
    base.donatedAmmo = math.floor((tonumber(base.donatedStock.ammo) or 0) + 0.5)
    base.donatedMagazines = math.floor((tonumber(base.donatedStock.magazines) or 0) + 0.5)
    base.donatedWeaponParts = math.floor((tonumber(base.donatedStock.weaponParts) or 0) + 0.5)
    base.donatedMaintenance = math.floor((tonumber(base.donatedStock.maintenance) or 0) + 0.5)
    base.donatedWeaponKitsCount = math.floor((type(base.donatedWeaponKits) == "table" and #base.donatedWeaponKits or 0) + 0.5)
    base.donatedAttachedWeaponParts = math.floor((tonumber(base.donatedAttachedWeaponParts) or 0) + 0.5)
    base.donatedTotalItems = math.floor((tonumber(base.donatedStats.totalItems) or 0) + 0.5)
    base.donatedTotalDonations = math.floor((tonumber(base.donatedStats.totalDonations) or 0) + 0.5)
end

local function bbs_categoryFromItem(item)
    if type(item) ~= "table" then return nil end
    local cacheKey = bbs_itemCacheKey(item)
    if NPCRuntimeCacheBridge and NPCRuntimeCacheBridge.GetItemClass and cacheKey then
        local cached = NPCRuntimeCacheBridge.GetItemClass(cacheKey)
        if cached ~= nil then return cached ~= false and cached or nil end
    end

    local explicit = bbs_lower(item.resource or item.baseResource)
    for _, resource in ipairs(BBS_RESOURCES) do
        if explicit == bbs_lower(resource) then
            if NPCRuntimeCacheBridge and NPCRuntimeCacheBridge.SetItemClass and cacheKey then NPCRuntimeCacheBridge.SetItemClass(cacheKey, resource) end
            return resource
        end
    end

    local ft = bbs_lower(item.fullType or item.type or item.name)
    local cat = bbs_lower(item.category)
    local display = bbs_lower(item.displayCategory)
    local body = bbs_lower(item.bodyLocation)
    local partType = bbs_lower(item.partType)
    local protection = tonumber(item.protection) or 0
    local maxAmmo = tonumber(item.maxAmmo) or 0
    local detected = nil

    if item.isFood == true or cat == "food" or display == "food" then detected = "food" end
    if not detected and (item.isWeaponPart == true or cat == "weaponpart" or display == "weaponpart" or partType ~= "") then detected = "weaponParts" end
    if not detected and (item.isMagazine == true or (display == "ammo" and (maxAmmo > 0 or item.gunType or item.magazineAmmoType))) then detected = "magazines" end
    if not detected and (item.isMaintenance == true or string.find(ft, "guntoolkit", 1, true) or string.find(ft, "solvent", 1, true) or string.find(ft, "wd40", 1, true)) then detected = "maintenance" end
    if not detected and (item.isAmmo == true or cat == "ammo" or display == "ammo" or string.find(ft, "ammo", 1, true) or string.find(ft, "bullet", 1, true) or string.find(ft, "shell", 1, true)) then detected = "ammo" end
    if not detected and (item.isWeapon == true or cat == "weapon" or display == "weapon") then detected = "weapons" end
    if not detected and (item.isArmor == true or protection > 0 or string.find(ft, "armor", 1, true) or string.find(ft, "bullet", 1, true) or string.find(ft, "vest", 1, true) or string.find(ft, "helmet", 1, true) or string.find(ft, "pads", 1, true)) then detected = "armor" end
    if not detected and (item.isClothing == true or cat == "clothing" or display == "clothing" or body ~= "") then detected = "clothing" end

    if NPCRuntimeCacheBridge and NPCRuntimeCacheBridge.SetItemClass and cacheKey then
        NPCRuntimeCacheBridge.SetItemClass(cacheKey, detected or false)
    end
    return detected
end

local function bbs_amountFor(item, resource)
    local amount = tonumber(item.baseAmount) or tonumber(item.count) or 1
    if resource == "ammo" then amount = tonumber(item.ammoCount) or amount end
    if amount < 1 then amount = 1 end
    return math.floor(amount + 0.5)
end

local function bbs_copySerializable(value, depth)
    depth = depth or 0
    if depth > 5 then return nil end
    if type(value) ~= "table" then return value end
    local ret = {}
    for k, v in pairs(value) do
        local tk = type(k)
        local tv = type(v)
        if (tk == "string" or tk == "number" or tk == "boolean") and tv ~= "function" and tv ~= "userdata" and tv ~= "thread" then
            if tv == "table" then
                ret[k] = bbs_copySerializable(v, depth + 1)
            else
                ret[k] = v
            end
        end
    end
    return ret
end

local function bbs_makeWeaponKit(item)
    local kit = {
        fullType = tostring(item.fullType or item.type or item.name or ""),
        name = item.name or item.displayName or item.fullType,
        resource = "weapons",
        isRanged = item.isRanged == true,
        isTwoHandWeapon = item.isTwoHandWeapon == true,
        ammoType = item.ammoType,
        magazineType = item.magazineType,
        maxAmmo = tonumber(item.maxAmmo) or 0,
        condition = tonumber(item.condition) or 0,
        maxCondition = tonumber(item.maxCondition) or 0,
        loadedAmmo = tonumber(item.ammoCount) or tonumber(item.loadedAmmo) or 0,
        donatedAt = bbs_nowHours(),
        source = "base_supply",
        attachments = {},
        attachmentCount = 0
    }

    if type(item.attachments) == "table" then
        for _, part in ipairs(item.attachments) do
            if type(part) == "table" and part.fullType then
                local copy = bbs_copySerializable(part)
                table.insert(kit.attachments, copy)
                kit.attachmentCount = kit.attachmentCount + 1
            end
        end
    end

    return kit
end

local function bbs_storeWeaponKit(base, item, amount)
    NPCBaseSupplyServerBridge.EnsureBaseSupply(base)
    local fullType = tostring(item.fullType or item.type or item.name or "")
    if fullType == "" then return false end

    amount = math.max(1, math.floor((tonumber(amount) or 1) + 0.5))
    for _ = 1, amount do
        local kit = bbs_makeWeaponKit(item)
        table.insert(base.donatedWeaponKits, kit)
    end

    base.stock.weapons = (tonumber(base.stock.weapons) or 0) + amount
    base.donatedStock.weapons = (tonumber(base.donatedStock.weapons) or 0) + amount
    base.donatedAttachedWeaponParts = (tonumber(base.donatedAttachedWeaponParts) or 0) + ((tonumber(item.attachmentCount) or (type(item.attachments) == "table" and #item.attachments or 0)) * amount)
    base.donatedStats.totalItems = (tonumber(base.donatedStats.totalItems) or 0) + amount
    base.donatedStats.totalDonations = (tonumber(base.donatedStats.totalDonations) or 0) + 1
    base.donatedStats.lastDonatedAt = bbs_nowHours()
    NPCBaseSupplyServerBridge.SyncBaseFields(base)
    return true
end

local function bbs_storeItem(base, item, resource, amount)
    NPCBaseSupplyServerBridge.EnsureBaseSupply(base)
    local fullType = tostring(item.fullType or item.type or item.name or "")
    if fullType == "" then return false end

    if resource == "weapons" then
        return bbs_storeWeaponKit(base, item, amount)
    end

    local bucket = base.donatedItems[resource]
    local entry = bucket[fullType]
    if type(entry) ~= "table" then
        entry = {
            fullType = fullType,
            name = item.name or item.displayName or fullType,
            resource = resource,
            count = 0,
            isRanged = item.isRanged == true,
            isTwoHandWeapon = item.isTwoHandWeapon == true,
            isWeapon = item.isWeapon == true,
            isFood = item.isFood == true,
            isClothing = item.isClothing == true,
            isArmor = item.isArmor == true,
            bodyLocation = item.bodyLocation,
            ammoType = item.ammoType,
            magazineType = item.magazineType,
            magazineAmmoType = item.magazineAmmoType,
            gunType = item.gunType,
            partType = item.partType,
            mountOn = item.mountOn,
            maxAmmo = tonumber(item.maxAmmo) or 0,
            condition = tonumber(item.condition) or 0,
            maxCondition = tonumber(item.maxCondition) or 0,
            protection = tonumber(item.protection) or 0,
            firstDonatedAt = bbs_nowHours()
        }
        bucket[fullType] = entry
    end

    entry.count = (tonumber(entry.count) or 0) + amount
    entry.lastDonatedAt = bbs_nowHours()
    entry.condition = math.max(tonumber(entry.condition) or 0, tonumber(item.condition) or 0)
    entry.maxCondition = math.max(tonumber(entry.maxCondition) or 0, tonumber(item.maxCondition) or 0)
    entry.protection = math.max(tonumber(entry.protection) or 0, tonumber(item.protection) or 0)
    if item.bodyLocation then entry.bodyLocation = item.bodyLocation end
    if item.ammoType then entry.ammoType = item.ammoType end
    if item.magazineType then entry.magazineType = item.magazineType end
    if item.magazineAmmoType then entry.magazineAmmoType = item.magazineAmmoType end
    if item.gunType then entry.gunType = item.gunType end
    if item.partType then entry.partType = item.partType end
    if item.mountOn then entry.mountOn = item.mountOn end
    if item.maxAmmo then entry.maxAmmo = tonumber(item.maxAmmo) or entry.maxAmmo end

    base.stock[resource] = (tonumber(base.stock[resource]) or 0) + amount
    base.donatedStock[resource] = (tonumber(base.donatedStock[resource]) or 0) + amount
    base.donatedStats.totalItems = (tonumber(base.donatedStats.totalItems) or 0) + amount
    base.donatedStats.totalDonations = (tonumber(base.donatedStats.totalDonations) or 0) + 1
    base.donatedStats.lastDonatedAt = bbs_nowHours()
    NPCBaseSupplyServerBridge.SyncBaseFields(base)
    return true
end

local function bbs_takeEntry(base, resource, predicate)
    NPCBaseSupplyServerBridge.EnsureBaseSupply(base)
    local bucket = base.donatedItems and base.donatedItems[resource]
    if type(bucket) ~= "table" then return nil end

    local bestKey = nil
    local best = nil
    local bestScore = -999999
    for key, entry in pairs(bucket) do
        if type(entry) == "table" and (tonumber(entry.count) or 0) > 0 then
            if not predicate or predicate(entry) then
                local score = (tonumber(entry.protection) or 0) + (tonumber(entry.condition) or 0) * 0.1 + (tonumber(entry.maxCondition) or 0) * 0.2
                if entry.isRanged then score = score + 50 end
                if entry.isTwoHandWeapon then score = score + 8 end
                if score > bestScore then
                    bestKey = key
                    best = entry
                    bestScore = score
                end
            end
        end
    end
    if not best then return nil end

    best.count = (tonumber(best.count) or 0) - 1
    base.stock[resource] = math.max(0, (tonumber(base.stock[resource]) or 0) - 1)
    base.donatedStock[resource] = math.max(0, (tonumber(base.donatedStock[resource]) or 0) - 1)
    if best.count <= 0 and bestKey then bucket[bestKey] = nil end
    NPCBaseSupplyServerBridge.SyncBaseFields(base)

    local copy = {}
    for k, v in pairs(best) do copy[k] = v end
    copy.count = 1
    return copy
end

local function bbs_addInventoryType(member, fullType)
    if type(member) ~= "table" or not fullType then return end
    if type(member.inventory) ~= "table" then member.inventory = {} end
    table.insert(member.inventory, tostring(fullType))
    if type(member.inventoryLite) ~= "table" then member.inventoryLite = {} end
    table.insert(member.inventoryLite, {type=tostring(fullType), fullType=tostring(fullType), source="base_supply"})
end

local function bbs_addLootType(member, fullType)
    if type(member) ~= "table" or not fullType then return end
    if type(member.loot) ~= "table" then member.loot = {} end
    table.insert(member.loot, tostring(fullType))
end

local function bbs_takeWeaponKit(base)
    NPCBaseSupplyServerBridge.EnsureBaseSupply(base)
    local kits = base.donatedWeaponKits
    if type(kits) ~= "table" or #kits <= 0 then return nil end

    local bestIndex = nil
    local bestScore = -999999
    for index, kit in ipairs(kits) do
        if type(kit) == "table" and kit.fullType then
            local score = (tonumber(kit.condition) or 0) * 0.2 + (tonumber(kit.maxCondition) or 0) * 0.1 + (tonumber(kit.attachmentCount) or (type(kit.attachments) == "table" and #kit.attachments or 0)) * 8
            if kit.isRanged then score = score + 50 end
            if kit.isTwoHandWeapon then score = score + 8 end
            if score > bestScore then
                bestScore = score
                bestIndex = index
            end
        end
    end

    if not bestIndex then return nil end
    local kit = table.remove(kits, bestIndex)
    base.stock.weapons = math.max(0, (tonumber(base.stock.weapons) or 0) - 1)
    base.donatedStock.weapons = math.max(0, (tonumber(base.donatedStock.weapons) or 0) - 1)
    base.donatedAttachedWeaponParts = math.max(0, (tonumber(base.donatedAttachedWeaponParts) or 0) - (tonumber(kit.attachmentCount) or (type(kit.attachments) == "table" and #kit.attachments or 0)))
    NPCBaseSupplyServerBridge.SyncBaseFields(base)
    return kit
end


local function bbs_cargoCategoryWeight(resource)
    if resource == "weapons" then return 1 end
    if resource == "armor" then return 2 end
    if resource == "weaponParts" then return 2 end
    if resource == "magazines" then return 2 end
    if resource == "maintenance" then return 2 end
    return 1
end

local function bbs_cargoCategoriesForResource(resource, missionType)
    resource = tostring(resource or "supplies")
    if resource == "weapons" then return {"weapons", "weaponParts", "magazines", "ammo"} end
    if resource == "ammo" then return {"ammo", "magazines", "weaponParts"} end
    if resource == "magazines" then return {"magazines", "ammo"} end
    if resource == "weaponParts" then return {"weaponParts", "maintenance"} end
    if resource == "armor" then return {"armor", "clothing"} end
    if resource == "clothing" then return {"clothing", "armor"} end
    if resource == "tools" or resource == "spareParts" or resource == "materials" then return {"weaponParts", "maintenance", "armor"} end
    if resource == "food" or resource == "water" then return {"food"} end
    if resource == "medical" then return {"maintenance", "clothing", "food"} end
    if missionType == "raid" then return {"weapons", "ammo", "magazines", "weaponParts", "armor", "food", "maintenance"} end
    return {"food", "ammo", "magazines", "weapons", "armor", "clothing", "weaponParts", "maintenance"}
end

local function bbs_pushCargoEntry(cargo, resource, entry, count)
    if type(cargo) ~= "table" or type(entry) ~= "table" or not resource then return 0 end
    cargo.items = cargo.items or {}
    cargo.itemCounts = cargo.itemCounts or {}
    cargo.items[resource] = cargo.items[resource] or {}
    count = math.max(1, math.floor((tonumber(count) or tonumber(entry.count) or 1) + 0.5))

    local fullType = tostring(entry.fullType or entry.type or entry.name or "")
    if fullType == "" then return 0 end
    local bucket = cargo.items[resource]
    local existing = bucket[fullType]
    if type(existing) ~= "table" then
        existing = bbs_copySerializable(entry) or {fullType=fullType, resource=resource}
        existing.count = 0
        bucket[fullType] = existing
    end
    existing.count = (tonumber(existing.count) or 0) + count
    cargo.itemCounts[resource] = (tonumber(cargo.itemCounts[resource]) or 0) + count
    cargo.exactUnits = (tonumber(cargo.exactUnits) or 0) + count
    cargo.powerValue = (tonumber(cargo.powerValue) or 0) + count * bbs_cargoCategoryWeight(resource)
    return count
end

local function bbs_addEntryToBase(base, resource, entry, count)
    if type(base) ~= "table" or type(entry) ~= "table" or not resource then return 0 end
    NPCBaseSupplyServerBridge.EnsureBaseSupply(base)
    local fullType = tostring(entry.fullType or entry.type or entry.name or "")
    if fullType == "" then return 0 end
    count = math.max(1, math.floor((tonumber(count) or tonumber(entry.count) or 1) + 0.5))

    if type(base.donatedItems[resource]) ~= "table" then base.donatedItems[resource] = {} end
    if base.stock[resource] == nil then base.stock[resource] = 0 end
    if base.donatedStock[resource] == nil then base.donatedStock[resource] = 0 end

    local bucket = base.donatedItems[resource]
    local existing = bucket[fullType]
    if type(existing) ~= "table" then
        existing = bbs_copySerializable(entry) or {fullType=fullType, resource=resource}
        existing.count = 0
        bucket[fullType] = existing
    end
    existing.count = (tonumber(existing.count) or 0) + count
    existing.lastDonatedAt = bbs_nowHours()
    existing.resource = resource
    base.stock[resource] = (tonumber(base.stock[resource]) or 0) + count
    base.donatedStock[resource] = (tonumber(base.donatedStock[resource]) or 0) + count
    base.donatedStats.totalItems = (tonumber(base.donatedStats.totalItems) or 0) + count
    NPCBaseSupplyServerBridge.SyncBaseFields(base)
    return count
end

function NPCBaseSupplyServerBridge.GetArmoryValue(base)
    if type(base) ~= "table" then return 0 end
    NPCBaseSupplyServerBridge.EnsureBaseSupply(base)
    local stock = base.stock or {}
    local value = 0
    value = value + (tonumber(stock.weapons) or 0) * 18
    value = value + (tonumber(stock.armor) or 0) * 9
    value = value + (tonumber(stock.ammo) or 0) * 1.3
    value = value + (tonumber(stock.magazines) or 0) * 4
    value = value + (tonumber(stock.weaponParts) or 0) * 5
    value = value + (tonumber(stock.maintenance) or 0) * 2
    value = value + (tonumber(base.donatedAttachedWeaponParts) or 0) * 4
    if type(base.donatedWeaponKits) == "table" then
        for _, kit in ipairs(base.donatedWeaponKits) do
            if type(kit) == "table" then
                value = value + 8 + (tonumber(kit.attachmentCount) or (type(kit.attachments) == "table" and #kit.attachments or 0)) * 5
                value = value + math.min(10, (tonumber(kit.condition) or 0) * 0.35)
            end
        end
    end
    return value
end

function NPCBaseSupplyServerBridge.ExtractCargo(base, economyResource, desiredAmount, missionType)
    if type(base) ~= "table" then return nil end
    NPCBaseSupplyServerBridge.EnsureBaseSupply(base)
    desiredAmount = math.max(1, math.floor((tonumber(desiredAmount) or 1) + 0.5))

    local cargo = {
        version = NPCBaseSupplyServerBridge.Version,
        economyResource = economyResource,
        missionType = missionType,
        exactUnits = 0,
        powerValue = 0,
        items = {},
        itemCounts = {},
        weaponKits = {}
    }

    local categories = bbs_cargoCategoriesForResource(economyResource, missionType)
    local remaining = desiredAmount

    for _, resource in ipairs(categories) do
        if remaining <= 0 then break end
        if resource == "weapons" then
            local limit = math.min(6, math.max(1, remaining))
            while limit > 0 and remaining > 0 do
                local kit = bbs_takeWeaponKit(base)
                if not kit then break end
                table.insert(cargo.weaponKits, kit)
                cargo.exactUnits = (tonumber(cargo.exactUnits) or 0) + 1
                cargo.powerValue = (tonumber(cargo.powerValue) or 0) + 18 + (tonumber(kit.attachmentCount) or (type(kit.attachments) == "table" and #kit.attachments or 0)) * 5
                remaining = remaining - 1
                limit = limit - 1
            end
        end

        if remaining <= 0 then break end
        if resource ~= "weapons" then
            local limit = math.min(12, math.max(1, remaining))
            while limit > 0 and remaining > 0 do
                local entry = bbs_takeEntry(base, resource)
                if not entry then break end
                bbs_pushCargoEntry(cargo, resource, entry, 1)
                remaining = remaining - 1
                limit = limit - 1
            end
        end
    end

    cargo.summary = "Kits " .. tostring(#(cargo.weaponKits or {})) .. ", Items " .. tostring(cargo.exactUnits or 0)
    if (tonumber(cargo.exactUnits) or 0) <= 0 and #(cargo.weaponKits or {}) <= 0 then
        return nil
    end
    NPCBaseSupplyServerBridge.SyncBaseFields(base)
    return cargo
end

function NPCBaseSupplyServerBridge.ImportCargo(base, cargo)
    if type(base) ~= "table" or type(cargo) ~= "table" then return 0 end
    NPCBaseSupplyServerBridge.EnsureBaseSupply(base)
    local added = 0

    if type(cargo.weaponKits) == "table" then
        for _, kit in ipairs(cargo.weaponKits) do
            if type(kit) == "table" and kit.fullType then
                table.insert(base.donatedWeaponKits, bbs_copySerializable(kit) or kit)
                base.stock.weapons = (tonumber(base.stock.weapons) or 0) + 1
                base.donatedStock.weapons = (tonumber(base.donatedStock.weapons) or 0) + 1
                base.donatedAttachedWeaponParts = (tonumber(base.donatedAttachedWeaponParts) or 0) + (tonumber(kit.attachmentCount) or (type(kit.attachments) == "table" and #kit.attachments or 0))
                base.donatedStats.totalItems = (tonumber(base.donatedStats.totalItems) or 0) + 1
                added = added + 1
            end
        end
    end

    if type(cargo.items) == "table" then
        for resource, bucket in pairs(cargo.items) do
            if type(bucket) == "table" then
                for _, entry in pairs(bucket) do
                    if type(entry) == "table" then
                        added = added + bbs_addEntryToBase(base, resource, entry, tonumber(entry.count) or 1)
                    end
                end
            end
        end
    end

    if added > 0 then
        base.donatedStats.totalDonations = (tonumber(base.donatedStats.totalDonations) or 0) + 1
        base.donatedStats.lastDonatedAt = bbs_nowHours()
        NPCBaseSupplyServerBridge.SyncBaseFields(base)
        if NPCBaseSupplyServerBridge.SendBaseUpdate then NPCBaseSupplyServerBridge.SendBaseUpdate(base) end
    end
    return added
end

function NPCBaseSupplyServerBridge.TransferCargo(originBase, targetBase, cargo)
    if type(targetBase) ~= "table" or type(cargo) ~= "table" then return 0 end
    return NPCBaseSupplyServerBridge.ImportCargo(targetBase, cargo)
end

local function bbs_shortType(fullType)
    local value = tostring(fullType or "")
    local _, _, short = string.find(value, "%.([^%.]+)$")
    return short or value
end

local function bbs_itemMatchesWeapon(entry, kit)
    if not entry or not kit then return true end
    local weaponFull = tostring(kit.fullType or "")
    local weaponShort = bbs_shortType(weaponFull)
    local ammoType = tostring(kit.ammoType or "")
    local magazineType = tostring(kit.magazineType or "")

    if entry.fullType and magazineType ~= "" and tostring(entry.fullType) == magazineType then return true end
    if entry.fullType and ammoType ~= "" and tostring(entry.fullType) == ammoType then return true end
    if entry.ammoType and ammoType ~= "" and tostring(entry.ammoType) == ammoType then return true end
    if entry.magazineAmmoType and ammoType ~= "" and tostring(entry.magazineAmmoType) == ammoType then return true end
    if entry.gunType then
        local gunType = tostring(entry.gunType)
        if gunType == weaponFull or gunType == weaponShort then return true end
    end
    return false
end

local function bbs_takeCompatibleEntry(base, resource, kit)
    return bbs_takeEntry(base, resource, function(entry)
        return bbs_itemMatchesWeapon(entry, kit)
    end) or bbs_takeEntry(base, resource)
end

local function bbs_partMatchesWeapon(entry, kit, usedPartTypes)
    if not entry or not kit then return false end
    local partType = tostring(entry.partType or "")
    if partType ~= "" and usedPartTypes and usedPartTypes[partType] then return false end

    local mount = bbs_lower(entry.mountOn)
    if mount == "" then return true end
    local weaponFull = bbs_lower(kit.fullType)
    local weaponShort = bbs_lower(bbs_shortType(kit.fullType))
    return string.find(mount, weaponFull, 1, true) ~= nil or string.find(mount, weaponShort, 1, true) ~= nil
end

local function bbs_attachAvailableParts(base, kit)
    if type(kit) ~= "table" then return kit end
    kit.attachments = kit.attachments or {}
    local used = {}
    for _, part in ipairs(kit.attachments) do
        if type(part) == "table" and part.partType then used[tostring(part.partType)] = true end
    end

    local maxExtra = 3
    while maxExtra > 0 do
        local part = bbs_takeEntry(base, "weaponParts", function(entry)
            return bbs_partMatchesWeapon(entry, kit, used)
        end)
        if not part then break end
        if part.partType then used[tostring(part.partType)] = true end
        table.insert(kit.attachments, part)
        kit.attachmentCount = (tonumber(kit.attachmentCount) or 0) + 1
        maxExtra = maxExtra - 1
    end

    return kit
end

local function bbs_weaponRecord(entry, magCount, magazine, ammo)
    local magName = nil
    local magSize = tonumber(entry.maxAmmo) or 0
    if magazine then
        magName = magazine.fullType or magazine.ammoType or magazine.magazineAmmoType
        magSize = math.max(magSize, tonumber(magazine.maxAmmo) or 0)
    end
    if not magName and ammo then magName = ammo.fullType end
    if not magName then magName = entry.magazineType or entry.ammoType end

    return {
        name = entry.fullType,
        magName = magName,
        magSize = magSize,
        bulletsLeft = math.max(0, tonumber(entry.loadedAmmo) or 0),
        magCount = math.max(0, tonumber(magCount) or 0),
        ammoType = entry.ammoType,
        magazineType = entry.magazineType,
        baseSupplyKit = bbs_copySerializable(entry)
    }
end

local function bbs_entryLooksRanged(entry)
    local ft = bbs_lower(entry and entry.fullType)
    return entry and (entry.isRanged == true or string.find(ft, "rifle", 1, true) or string.find(ft, "pistol", 1, true) or string.find(ft, "shotgun", 1, true) or string.find(ft, "gun", 1, true))
end

local function bbs_applyWeapon(member, base)
    member.weapons = member.weapons or {melee="Base.Axe", primary={name=false, magSize=0, bulletsLeft=0, magCount=0}, secondary={name=false, magSize=0, bulletsLeft=0, magCount=0}}
    member.baseGear = member.baseGear or {}
    member.baseGearWeaponKits = member.baseGearWeaponKits or {}
    member.baseGearMagazines = member.baseGearMagazines or {}
    member.baseGearWeaponParts = member.baseGearWeaponParts or {}

    if not member.baseGear.weapon then
        local weapon = bbs_takeWeaponKit(base) or bbs_takeEntry(base, "weapons", bbs_entryLooksRanged) or bbs_takeEntry(base, "weapons")
        if weapon then
            weapon = bbs_attachAvailableParts(base, weapon)
            local magazine = bbs_takeCompatibleEntry(base, "magazines", weapon)
            local ammo = bbs_takeCompatibleEntry(base, "ammo", weapon)
            local magCount = 0
            if magazine then magCount = magCount + 1 end
            if ammo then magCount = magCount + 1 end

            if bbs_entryLooksRanged(weapon) then
                if weapon.isTwoHandWeapon or not (member.weapons.primary and member.weapons.primary.name) then
                    member.weapons.primary = bbs_weaponRecord(weapon, magCount, magazine, ammo)
                    member.baseGearWeaponKits.primary = bbs_copySerializable(weapon)
                else
                    member.weapons.secondary = bbs_weaponRecord(weapon, magCount, magazine, ammo)
                    member.baseGearWeaponKits.secondary = bbs_copySerializable(weapon)
                end
            else
                member.weapons.melee = weapon.fullType
                member.baseGearWeaponKits.melee = bbs_copySerializable(weapon)
            end

            member.baseGear.weapon = weapon.fullType
            if magazine then
                member.baseGear.magazine = magazine.fullType
                table.insert(member.baseGearMagazines, bbs_copySerializable(magazine))
                bbs_addInventoryType(member, magazine.fullType)
            end
            if ammo then
                member.baseGear.ammo = ammo.fullType
                bbs_addInventoryType(member, ammo.fullType)
            end
            if type(weapon.attachments) == "table" then
                for _, part in ipairs(weapon.attachments) do
                    if type(part) == "table" and part.fullType then
                        table.insert(member.baseGearWeaponParts, bbs_copySerializable(part))
                    end
                end
            end
            return true
        end
    end

    if member.baseGear.weapon and not member.baseGear.ammo then
        local kit = member.baseGearWeaponKits.primary or member.baseGearWeaponKits.secondary or member.baseGearWeaponKits.melee or {fullType=member.baseGear.weapon}
        local magazine = bbs_takeCompatibleEntry(base, "magazines", kit)
        local ammo = bbs_takeCompatibleEntry(base, "ammo", kit)
        if magazine or ammo then
            local addCount = 0
            if magazine then addCount = addCount + 1 end
            if ammo then addCount = addCount + 1 end
            if member.weapons.primary and member.weapons.primary.name then
                member.weapons.primary.magCount = (tonumber(member.weapons.primary.magCount) or 0) + addCount
                member.weapons.primary.magName = member.weapons.primary.magName or (magazine and magazine.fullType) or (ammo and ammo.fullType)
            elseif member.weapons.secondary and member.weapons.secondary.name then
                member.weapons.secondary.magCount = (tonumber(member.weapons.secondary.magCount) or 0) + addCount
                member.weapons.secondary.magName = member.weapons.secondary.magName or (magazine and magazine.fullType) or (ammo and ammo.fullType)
            end
            if magazine then
                member.baseGear.magazine = magazine.fullType
                table.insert(member.baseGearMagazines, bbs_copySerializable(magazine))
                bbs_addInventoryType(member, magazine.fullType)
            end
            if ammo then
                member.baseGear.ammo = ammo.fullType
                bbs_addInventoryType(member, ammo.fullType)
            end
            return true
        end
    end

    return false
end

local function bbs_applyWear(member, base, resource)
    member.baseGear = member.baseGear or {}
    member.baseGearWear = member.baseGearWear or {}
    if resource == "armor" and member.baseGear.armor then return false end
    if resource == "clothing" and member.baseGear.clothing then return false end
    if #member.baseGearWear >= 3 then return false end

    local entry = bbs_takeEntry(base, resource)
    if not entry then return false end
    table.insert(member.baseGearWear, entry.fullType)
    bbs_addInventoryType(member, entry.fullType)
    bbs_addLootType(member, entry.fullType)
    if resource == "armor" then member.baseGear.armor = entry.fullType else member.baseGear.clothing = entry.fullType end
    return true
end

local function bbs_applyFood(member, base)
    member.baseGear = member.baseGear or {}
    if member.baseGear.food then return false end
    local entry = bbs_takeEntry(base, "food")
    if not entry then return false end
    member.baseGear.food = entry.fullType
    bbs_addInventoryType(member, entry.fullType)
    return true
end

function NPCBaseSupplyServerBridge.ApplyGearToMember(base, member)
    if type(base) ~= "table" or type(member) ~= "table" then return false end
    local changed = false
    if bbs_applyWeapon(member, base) then changed = true end
    if bbs_applyWear(member, base, "armor") then changed = true end
    if bbs_applyWear(member, base, "clothing") then changed = true end
    if bbs_applyFood(member, base) then changed = true end
    if changed then
        member.baseGearBaseId = base.id
        member.homeBaseId = member.homeBaseId or base.id
        member.baseGearAppliedAt = bbs_nowHours()
    end
    return changed
end

function NPCBaseSupplyServerBridge.GroupMatchesBase(base, group)
    if type(base) ~= "table" or type(group) ~= "table" then return false end
    local baseSide = bbs_sideForBase(base)
    local groupSide = bbs_sideForGroup(group)
    if baseSide and groupSide and baseSide ~= groupSide then return false end
    if group.homeBaseId and tostring(group.homeBaseId) == tostring(base.id) then return true end
    if group.missionOriginBaseId and tostring(group.missionOriginBaseId) == tostring(base.id) then return true end
    if group.originBaseId and tostring(group.originBaseId) == tostring(base.id) then return true end
    if group.targetBaseId and tostring(group.targetBaseId) == tostring(base.id) and group.state == "home_base" then return true end
    if group.x and group.y and bbs_dist(group.x, group.y, base.x, base.y) <= NPCBaseSupplyServerBridge.GEAR_SHARE_RADIUS then return true end
    return false
end

function NPCBaseSupplyServerBridge.ApplyGearToGroup(base, group)
    if not NPCBaseSupplyServerBridge.GroupMatchesBase(base, group) then return false end
    if type(group.members) ~= "table" then return false end
    local changed = false
    local applied = 0
    for _, member in pairs(group.members) do
        if applied >= NPCBaseSupplyServerBridge.MAX_NPCS_PER_UPDATE then break end
        if NPCBaseSupplyServerBridge.ApplyGearToMember(base, member) then
            changed = true
            applied = applied + 1
        end
    end
    if changed then
        group.baseGearBaseId = base.id
        group.baseGearAppliedAt = bbs_nowHours()
        group.updatedAt = bbs_nowHours()
    end
    return changed
end

function NPCBaseSupplyServerBridge.ApplyGearAroundBase(base)
    if type(base) ~= "table" then return false end
    local gmd = GetNPCModData()
    local changed = false
    for groupId, group in pairs(gmd.VirtualGroups or {}) do
        if NPCBaseSupplyServerBridge.ApplyGearToGroup(base, group) then
            gmd.VirtualGroups[groupId] = group
            changed = true
        end
    end
    return changed
end

local function bbs_supplySummary(base)
    NPCBaseSupplyServerBridge.SyncBaseFields(base)
    return "Food " .. tostring(base.donatedFood or 0)
        .. ", Clothes " .. tostring(base.donatedClothing or 0)
        .. ", Weapons " .. tostring(base.donatedWeapons or 0)
        .. ", Parts " .. tostring((base.donatedWeaponParts or 0) + (base.donatedAttachedWeaponParts or 0))
        .. ", Mags " .. tostring(base.donatedMagazines or 0)
        .. ", Armor " .. tostring(base.donatedArmor or 0)
        .. ", Ammo " .. tostring(base.donatedAmmo or 0)
end


local function bbs_instanceItem(fullType)
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

function NPCBaseSupplyServerBridge.ApplyVisualGearToZombie(zombie, brain, bandit)
    if not zombie or type(brain) ~= "table" then return false end
    local wear = brain.baseGearWear or (bandit and bandit.baseGearWear)
    if type(wear) ~= "table" then return false end
    local changed = false
    for _, fullType in ipairs(wear) do
        local item = bbs_instanceItem(fullType)
        if item then
            local bodyLocation = nil
            local okLoc, loc = pcall(function()
                if item.getBodyLocation then return item:getBodyLocation() end
                return nil
            end)
            if okLoc then bodyLocation = loc end
            if bodyLocation and tostring(bodyLocation) ~= "" and zombie.setWornItem then
                local okWear = pcall(function() zombie:setWornItem(bodyLocation, item) end)
                if okWear then changed = true end
            end
            if zombie.getInventory then
                local okInv = pcall(function() zombie:getInventory():AddItem(item) end)
                if okInv then changed = true end
            end
        end
    end
    return changed
end

function NPCBaseSupplyServerBridge.MakeMarker(base)
    if type(base) ~= "table" then return nil end
    NPCBaseSupplyServerBridge.SyncBaseFields(base)
    return {
        id = "SUPPLY_" .. tostring(base.id),
        markerType = "base_supply",
        baseId = base.id,
        x = base.x,
        y = base.y,
        z = base.z or 0,
        owner = base.owner,
        captureTeam = base.captureTeam,
        hostile = base.owner == "red" or (not base.owner and base.captureTeam == "red"),
        friendly = base.owner == "green" or (not base.owner and base.captureTeam == "green"),
        stockFood = base.stockFood or 0,
        stockClothing = base.stockClothing or 0,
        stockWeapons = base.stockWeapons or 0,
        stockArmor = base.stockArmor or 0,
        stockAmmo = base.stockAmmo or 0,
        stockMagazines = base.stockMagazines or 0,
        stockWeaponParts = base.stockWeaponParts or 0,
        stockMaintenance = base.stockMaintenance or 0,
        donatedFood = base.donatedFood or 0,
        donatedClothing = base.donatedClothing or 0,
        donatedWeapons = base.donatedWeapons or 0,
        donatedArmor = base.donatedArmor or 0,
        donatedAmmo = base.donatedAmmo or 0,
        donatedMagazines = base.donatedMagazines or 0,
        donatedWeaponParts = base.donatedWeaponParts or 0,
        donatedAttachedWeaponParts = base.donatedAttachedWeaponParts or 0,
        donatedMaintenance = base.donatedMaintenance or 0,
        donatedWeaponKitsCount = base.donatedWeaponKitsCount or 0,
        donatedTotalItems = base.donatedTotalItems or 0,
        summary = bbs_supplySummary(base),
        updatedAt = bbs_nowHours()
    }
end

function NPCBaseSupplyServerBridge.SendBaseUpdate(base, player)
    local marker = NPCBaseSupplyServerBridge.MakeMarker(base)
    if not marker then return false end
    local gmd = GetNPCModData()
    gmd.DebugMapMarkers = gmd.DebugMapMarkers or {}
    gmd.DebugMapMarkers[marker.id] = marker

    if player then
        sendServerCommand(player, 'NPCBaseSupply', 'BaseUpdate', marker)
    else
        sendServerCommand('NPCBaseSupply', 'BaseUpdate', marker)
    end

    if NPCNetContract and NPCNetContract.SendDebugMapUpdate then
        NPCNetContract.SendDebugMapUpdate(marker, player)
    elseif player then
        sendServerCommand(player, 'NPCDebugMap', 'Update', marker)
    else
        sendServerCommand('NPCDebugMap', 'Update', marker)
    end
    return true
end

function NPCBaseSupplyServerBridge.SendAllToPlayer(player)
    local gmd = GetNPCModData()
    for _, base in pairs(bbs_getBaseCamps(gmd) or {}) do
        if type(base) == "table" and base.donatedStock then
            NPCBaseSupplyServerBridge.SendBaseUpdate(base, player)
        end
    end
end

function NPCBaseSupplyServerBridge.AddDonation(player, args)
    if not NPCBaseSupplyServerBridge.Enabled or type(args) ~= "table" then return false, "disabled" end
    local gmd = GetNPCModData()
    local px = player and player.getX and player:getX() or tonumber(args.x)
    local py = player and player.getY and player:getY() or tonumber(args.y)
    if not px or not py then return false, "no_player_position" end

    local base = bbs_findNearbyBase(gmd, px, py, args.baseId)
    if not base then return false, "not_in_base" end
    if not bbs_sideForBase(base) then return false, "base_not_owned" end

    local items = args.items
    if type(items) ~= "table" then return false, "no_items" end

    local accepted = 0
    local counts = {food=0, clothing=0, weapons=0, armor=0, ammo=0, magazines=0, weaponParts=0, maintenance=0}
    for index, item in ipairs(items) do
        if index > NPCBaseSupplyServerBridge.MAX_ITEMS_PER_DONATION then break end
        if type(item) == "table" then
            local resource = bbs_categoryFromItem(item)
            if resource then
                local amount = bbs_amountFor(item, resource)
                if bbs_storeItem(base, item, resource, amount) then
                    accepted = accepted + 1
                    counts[resource] = (tonumber(counts[resource]) or 0) + amount
                end
            end
        end
    end

    if accepted <= 0 then return false, "no_supported_items" end

    base.lastDonationAt = bbs_nowHours()
    base.lastDonationPlayer = player and player.getUsername and player:getUsername() or nil
    base.lastDonationSummary = "Food " .. tostring(counts.food or 0)
        .. ", Clothes " .. tostring(counts.clothing or 0)
        .. ", Weapons " .. tostring(counts.weapons or 0)
        .. ", Parts " .. tostring(counts.weaponParts or 0)
        .. ", Mags " .. tostring(counts.magazines or 0)
        .. ", Armor " .. tostring(counts.armor or 0)
        .. ", Ammo " .. tostring(counts.ammo or 0)

    NPCBaseSupplyServerBridge.ApplyGearAroundBase(base)
    NPCBaseSupplyServerBridge.SendBaseUpdate(base, nil)
    if NPCBaseCampServerBridge and NPCBaseCampServerBridge.SendBaseMarkers then
        NPCBaseCampServerBridge.SendBaseMarkers(base, true)
    end

    if NPCContractsServerBridge and NPCContractsServerBridge.OnSupplyDonation then
        NPCContractsServerBridge.OnSupplyDonation(player, base, counts)
    end

    if player then
        sendServerCommand(player, 'NPCBaseSupply', 'DonationResult', {
            ok=true,
            baseId=base.id,
            accepted=accepted,
            summary=base.lastDonationSummary,
            food=counts.food or 0,
            clothing=counts.clothing or 0,
            weapons=counts.weapons or 0,
            armor=counts.armor or 0,
            ammo=counts.ammo or 0,
            magazines=counts.magazines or 0,
            weaponParts=counts.weaponParts or 0,
            maintenance=counts.maintenance or 0
        })
    end

    return true, accepted
end

function NPCBaseSupplyServerBridge.OnClientCommand(module, command, player, args)
    if not NPCLegacyContractBridge.IsModule(module, "NPCBaseSupply", "baseSupply") then return false end
    if command == "DonateItems" then
        local ok, result = NPCBaseSupplyServerBridge.AddDonation(player, args)
        if not ok and player then
            sendServerCommand(player, 'NPCBaseSupply', 'DonationResult', {ok=false, reason=tostring(result or "failed")})
        end
        return true
    elseif command == "RequestSync" then
        NPCBaseSupplyServerBridge.SendAllToPlayer(player)
        return true
    end
    return false
end

local function bbs_updateAll()
    if not NPCBaseSupplyServerBridge.Enabled then return end
    local gmd = GetNPCModData()
    for _, base in pairs(bbs_getBaseCamps(gmd) or {}) do
        if type(base) == "table" and base.donatedStock then
            NPCBaseSupplyServerBridge.ApplyGearAroundBase(base)
            NPCBaseSupplyServerBridge.SendBaseUpdate(base, nil)
        end
    end
end

local function bbs_onClientCommand(module, command, player, args)
    NPCBaseSupplyServerBridge.OnClientCommand(module, command, player, args)
end

local function bbs_onTick()
    NPCBaseSupplyServerBridge._tick = (NPCBaseSupplyServerBridge._tick or 0) + 1
    if NPCBaseSupplyServerBridge._tick % 1200 == 420 then
        local level = 0
        if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.GetLoadLevel then
            local okLevel, gotLevel = pcall(function() return NPCWorkSchedulerBridge.GetLoadLevel(false) end)
            if okLevel then level = tonumber(gotLevel) or 0 end
        end
        if level < 2 then
            bbs_updateAll()
        end
    end
end

Events.OnClientCommand.Add(bbs_onClientCommand)
Events.OnTick.Add(bbs_onTick)
Events.EveryTenMinutes.Add(bbs_updateAll)

print("[NPCBaseSupplyServerBridge] Player base supply slots enabled")
