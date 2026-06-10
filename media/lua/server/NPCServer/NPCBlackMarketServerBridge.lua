-- NPCBlackMarketServerBridge.lua
-- Neutral server backend for static black market service objects.
-- This file deliberately does not spawn IsoZombie/IsoGameCharacter traders.
require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

local NPC_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
if isClient and isClient() then return end

require "NPCCore/NPCBlackMarketBridge"
require "NPCCore/NPCDiagnosticsBridge"
require "NPCCore/NPCIntelDossierBridge"
require "NPCCore/NPCHeatWantedBridge"

require "NPCCore/NPCLegacyContractBridge"

NPCBlackMarketServerBridge = NPCBlackMarketServerBridge or {}
local function npcserver_setDebugMarker(gmd, marker)
    local runtime = NPCServerRuntime
    local setter = runtime and runtime.SetDebugMarker or NPC_LEGACY_GLOBALS.Get("SetDebugMarker")
    if setter then return setter(gmd, marker) end
    return false
end


local function halo(p,t,r,g,b)
    if p and t then sendServerCommand(p,'NPCBlackMarket','Result',{text=t,r=r or 220,g=g or 210,b=b or 120}) end
end

local function setMarker(gmd,m)
    if not (gmd and m and m.id) then return end
    if not npcserver_setDebugMarker(gmd,m) then
        gmd.DebugMapMarkers=gmd.DebugMapMarkers or {}
        gmd.DebugMapMarkers[tostring(m.id)]=m
        if NPCNetContract and NPCNetContract.SendDebugMapUpdate then NPCNetContract.SendDebugMapUpdate(m) else sendServerCommand('NPCDebugMap','Update',m) end
    end
end

local function removeMarker(gmd,id)
    if gmd and id then
        if gmd.DebugMapMarkers then gmd.DebugMapMarkers[tostring(id)]=nil end
        if NPCNetContract and NPCNetContract.SendDebugMapRemove then NPCNetContract.SendDebugMapRemove(id) else sendServerCommand('NPCDebugMap','Remove',{id=id}) end
        sendServerCommand('NPCBlackMarket','DropRemoved',{id=tostring(id)})
    end
end

local function syncMarker(gmd,c)
    local m=NPCBlackMarketBridge.MakeMarker(c)
    if m then setMarker(gmd,m) end
end

local function contactList(gmd)
    local d=NPCBlackMarketBridge.EnsureData(gmd)
    local list={}
    for _,c in pairs(d.contacts or {}) do
        if type(c)=="table" and c.blackMarketStatus ~= "closed" then list[#list+1]=c end
    end
    return list
end

local function syncContacts(p)
    local gmd=GetNPCModData()
    sendServerCommand(p,'NPCBlackMarket','Contacts',{contacts=contactList(gmd)})
end

local function syncContactsAll()
    local players = getOnlinePlayers and getOnlinePlayers() or nil
    if players and players.size and players.get then
        for i=0, players:size()-1 do
            local p = players:get(i)
            if p then syncContacts(p) end
        end
    end
end



local function bbms_nowHours()
    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then
            local ok, value = pcall(function() return gt:getWorldAgeHours() end)
            if ok and value ~= nil then return tonumber(value) or 0 end
        end
    end
    return os.time and (os.time() / 3600) or 0
end

local function bbms_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        local ok, value = pcall(function() return NPCLegacySettingsBridge.GetBool(name, defaultValue == true) end)
        if ok and value ~= nil then return value == true end
    end
    return defaultValue == true
end

local function bbms_num(name, defaultValue, minValue, maxValue)
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

local function bbms_rand(minValue, maxValue)
    minValue = math.floor(tonumber(minValue) or 0)
    maxValue = math.floor(tonumber(maxValue) or minValue)
    if maxValue <= minValue then return minValue end
    if ZombRand then
        local ok, value = pcall(function() return ZombRand(minValue, maxValue) end)
        if ok and value ~= nil then return tonumber(value) or minValue end
        ok, value = pcall(function() return minValue + ZombRand(maxValue - minValue) end)
        if ok and value ~= nil then return tonumber(value) or minValue end
    end
    return minValue + math.random(0, maxValue - minValue - 1)
end

local function bbms_dist(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return math.sqrt(dx * dx + dy * dy)
end


local function bbms_playerId(player)
    if NPCBlackMarketBridge and NPCBlackMarketBridge.PlayerId then
        local ok, id = pcall(function() return NPCBlackMarketBridge.PlayerId(player) end)
        if ok and id ~= nil then return tostring(id) end
    end
    if player and player.getOnlineID then
        local ok, id = pcall(function() return player:getOnlineID() end)
        if ok and id ~= nil then return tostring(id) end
    end
    if player and player.getUsername then
        local ok, name = pcall(function() return player:getUsername() end)
        if ok and name then return tostring(name) end
    end
    return "unknown"
end

local function bbms_playerName(player)
    if player and player.getUsername then
        local ok, name = pcall(function() return player:getUsername() end)
        if ok and name then return tostring(name) end
    end
    if player and player.getFullName then
        local ok, name = pcall(function() return player:getFullName() end)
        if ok and name then return tostring(name) end
    end
    return "player"
end

local function bbms_clientPaymentCount(args, resourceKey)
    if type(args) ~= "table" then return 0 end
    resourceKey = tostring(resourceKey or "")
    if resourceKey == "gold" then return math.floor(tonumber(args.clientPaymentGoldCount or args.clientGold) or 0) end
    if resourceKey == "silver" then return math.floor(tonumber(args.clientPaymentSilverCount or args.clientSilver) or 0) end
    return 0
end

local function bbms_clientPaymentOk(args, resourceKey, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    return bbms_clientPaymentCount(args, resourceKey) >= amount
end

local function bbms_paymentReceipt(resourceKey, amount, clientSide)
    return {
        resource = tostring(resourceKey or ""),
        amount = math.floor(tonumber(amount) or 0),
        takeClientPayment = clientSide == true
    }
end

local function bbms_sendClientPaymentRemoval(player, receipt, context)
    if not (player and type(receipt) == "table" and receipt.takeClientPayment == true) then return end
    sendServerCommand(player, 'NPCBlackMarket', 'TakeClientPayment', {
        resource = receipt.resource,
        amount = receipt.amount,
        context = context or "black_market_deal"
    })
end

local function bbms_dropId(data)
    local id = "black_market_drop_" .. tostring(data.nextDeadDropId or 1)
    data.nextDeadDropId = (tonumber(data.nextDeadDropId) or 1) + 1
    return id
end

local function bbms_inventoryItem(fullType)
    if not (InventoryItemFactory and InventoryItemFactory.CreateItem and fullType) then return nil end
    local ok, item = pcall(function() return InventoryItemFactory.CreateItem(fullType) end)
    if ok then return item end
    return nil
end

local function bbms_addItemToInventory(inv, fullType)
    if not (inv and fullType) then return nil end
    if inv.AddItem then
        local ok, item = pcall(function() return inv:AddItem(fullType) end)
        if ok and item then return item end
    end
    local item = bbms_inventoryItem(fullType)
    if item and inv.AddItem then
        local ok = pcall(function() inv:AddItem(item) end)
        if ok then return item end
    end
    return nil
end

local function bbms_addItemToInventoryQuiet(inv, fullType)
    if not (inv and inv.AddItem and fullType) then return nil end
    local item = bbms_inventoryItem(fullType)
    if not item then return nil end
    local ok = pcall(function() inv:AddItem(item) end)
    if ok then
        if item.transmitModData then pcall(function() item:transmitModData() end) end
        return item
    end
    return nil
end


local BBMS_WEAPON_DROP_CACHE = nil

local function bbms_normalizeFullType(fullType)
    if fullType == nil then return nil end
    fullType = tostring(fullType or "")
    if fullType == "" or fullType == "nil" or fullType == "null" then return nil end
    if string.find(fullType, ".", 1, true) then return fullType end
    return "Base." .. fullType
end

local function bbms_itemExists(fullType)
    fullType = bbms_normalizeFullType(fullType)
    if not fullType then return false end
    local item = bbms_inventoryItem(fullType)
    return item ~= nil
end

local function bbms_safeItemString(item, methods)
    if not item then return nil end
    for _, method in ipairs(methods or {}) do
        local fn = item[method]
        if type(fn) == "function" then
            local ok, value = pcall(function() return fn(item) end)
            if ok and value ~= nil and tostring(value) ~= "" and tostring(value) ~= "nil" and tostring(value) ~= "null" then
                return tostring(value)
            end
        end
    end
    return nil
end

local function bbms_scriptFullType(scriptItem)
    if not scriptItem then return nil end
    local fullType = bbms_safeItemString(scriptItem, {"getFullName", "getFullType"})
    if fullType then return bbms_normalizeFullType(fullType) end
    local moduleName = bbms_safeItemString(scriptItem, {"getModuleName"})
    local name = bbms_safeItemString(scriptItem, {"getName", "getType"})
    if moduleName and name then return tostring(moduleName) .. "." .. tostring(name) end
    return nil
end

local function bbms_createdItemFullType(item)
    return bbms_safeItemString(item, {"getFullType"}) or bbms_normalizeFullType(bbms_safeItemString(item, {"getType"}))
end

local function bbms_itemDisplayText(item, fullType)
    return string.lower(tostring(fullType or bbms_createdItemFullType(item) or "") .. " " .. tostring(bbms_safeItemString(item, {"getDisplayName", "getName"}) or ""))
end

local function bbms_itemHasNestedInventory(item)
    if not (item and item.getInventory) then return false end
    local ok, inv = pcall(function() return item:getInventory() end)
    return ok and inv ~= nil
end

local function bbms_looksLikeContainerOrSupplyCase(item, fullType)
    if bbms_itemHasNestedInventory(item) then return true end
    local text = bbms_itemDisplayText(item, fullType)
    return string.find(text, "case", 1, true)
        or string.find(text, "кейс", 1, true)
        or string.find(text, "bag", 1, true)
        or string.find(text, "сум", 1, true)
        or string.find(text, "box", 1, true)
        or string.find(text, "container", 1, true)
        or string.find(text, "crate", 1, true)
end

local function bbms_getAmmoType(weapon)
    local ammo = bbms_safeItemString(weapon, {"getAmmoType", "getAmmoTypeString"})
    ammo = bbms_normalizeFullType(ammo)
    if ammo and bbms_itemExists(ammo) then return ammo end
    return nil
end

local function bbms_getMagazineType(weapon)
    local magazine = bbms_safeItemString(weapon, {"getMagazineType", "getClipType"})
    magazine = bbms_normalizeFullType(magazine)
    if magazine and bbms_itemExists(magazine) then return magazine end
    return nil
end

local function bbms_createdWeaponLooksRanged(item, fullType)
    if not item then return false end
    if bbms_looksLikeContainerOrSupplyCase(item, fullType) then return false end
    local ok, value = pcall(function() return item.isRanged and item:isRanged() end)
    if ok and value == true then return true end
    ok, value = pcall(function() return item.isAimedFirearm and item:isAimedFirearm() end)
    if ok and value == true then return true end
    local sub = bbms_safeItemString(item, {"getSubCategory"})
    if sub and string.lower(sub) == "firearm" then return true end
    local cat = bbms_safeItemString(item, {"getCategories"})
    if cat and string.find(string.lower(cat), "firearm", 1, true) then return true end
    return false
end

local function bbms_weaponEntry(fullType)
    fullType = bbms_normalizeFullType(fullType)
    if not fullType then return nil end
    local weapon = bbms_inventoryItem(fullType)
    if not weapon then return nil end
    if bbms_looksLikeContainerOrSupplyCase(weapon, fullType) then return nil end
    local ammo = bbms_getAmmoType(weapon)
    local magazine = bbms_getMagazineType(weapon)
    local looksRanged = bbms_createdWeaponLooksRanged(weapon, fullType)
    if not looksRanged and not ammo and not magazine then return nil end
    local lower = string.lower(fullType)
    if not ammo then
        if string.find(lower, "shotgun", 1, true) then ammo = "Base.ShotgunShells"
        elseif string.find(lower, "556", 1, true) or string.find(lower, "m14", 1, true) or string.find(lower, "rifle", 1, true) then ammo = "Base.556Bullets"
        else ammo = "Base.9mmBullets" end
        if not bbms_itemExists(ammo) then ammo = nil end
    end
    return { weapon = fullType, magazine = magazine, ammo = ammo, display = bbms_safeItemString(weapon, {"getDisplayName", "getName"}) }
end

local function bbms_staticWeaponEntries()
    local candidates = {
        "Base.Pistol", "Base.Pistol2", "Base.Pistol3", "Base.Revolver", "Base.Revolver_Long", "Base.Revolver_Short",
        "Base.Shotgun", "Base.ShotgunSawnoff", "Base.DoubleBarrelShotgun", "Base.DoubleBarrelShotgunSawnoff",
        "Base.HuntingRifle", "Base.VarmintRifle", "Base.AssaultRifle", "Base.AssaultRifle2", "Base.M14"
    }
    local out = {}
    for _, fullType in ipairs(candidates) do
        local entry = bbms_weaponEntry(fullType)
        if entry then out[#out + 1] = entry end
    end
    return out
end

local function bbms_collectWeaponEntries()
    if type(BBMS_WEAPON_DROP_CACHE) == "table" then return BBMS_WEAPON_DROP_CACHE end
    local out = {}
    local seen = {}
    local function addEntry(fullType)
        local entry = bbms_weaponEntry(fullType)
        if entry and entry.weapon and not seen[entry.weapon] then
            seen[entry.weapon] = true
            out[#out + 1] = entry
        end
    end
    local sm = getScriptManager and getScriptManager() or nil
    local all = sm and sm.getAllItems and sm:getAllItems() or nil
    if all and all.size and all.get then
        local okSize, size = pcall(function() return all:size() end)
        size = okSize and tonumber(size) or 0
        for i = 0, size - 1 do
            local okGet, scriptItem = pcall(function() return all:get(i) end)
            if okGet and scriptItem then addEntry(bbms_scriptFullType(scriptItem)) end
        end
    end
    for _, entry in ipairs(bbms_staticWeaponEntries()) do
        if entry.weapon and not seen[entry.weapon] then
            seen[entry.weapon] = true
            out[#out + 1] = entry
        end
    end
    if #out <= 0 then
        out = {{ weapon = "Base.Pistol", magazine = "Base.9mmClip", ammo = "Base.9mmBullets" }}
    end
    BBMS_WEAPON_DROP_CACHE = out
    return BBMS_WEAPON_DROP_CACHE
end

local function bbms_pickWeaponEntry(data)
    local entries = bbms_collectWeaponEntries()
    if type(entries) ~= "table" or #entries <= 0 then return nil end
    local last = data and data.lastWeaponDropFullType or nil
    local entry = entries[bbms_rand(1, #entries + 1)] or entries[1]
    if last and #entries > 1 then
        for _ = 1, 6 do
            if entry and entry.weapon ~= last then break end
            entry = entries[bbms_rand(1, #entries + 1)] or entry
        end
    end
    if data and entry and entry.weapon then data.lastWeaponDropFullType = entry.weapon end
    return entry
end

local BBMS_AMMO_DROP_CACHE = nil
local BBMS_WEAPON_MOD_CACHE = nil

local function bbms_addUnique(out, seen, fullType)
    fullType = bbms_normalizeFullType(fullType)
    if not fullType or seen[fullType] then return end
    if not bbms_itemExists(fullType) then return end
    seen[fullType] = true
    out[#out + 1] = fullType
end

local function bbms_collectAmmoTypes()
    if type(BBMS_AMMO_DROP_CACHE) == "table" then return BBMS_AMMO_DROP_CACHE end
    local out, seen = {}, {}
    for _, entry in ipairs(bbms_collectWeaponEntries()) do
        bbms_addUnique(out, seen, entry.ammo)
    end
    local static = {
        "Base.9mmBullets", "Base.45Bullets", "Base.44Bullets", "Base.38Bullets",
        "Base.556Bullets", "Base.308Bullets", "Base.223Bullets", "Base.ShotgunShells",
        "Base.Bullets9mmBox", "Base.Bullets45Box", "Base.Bullets44Box", "Base.Bullets38Box",
        "Base.556Box", "Base.308Box", "Base.223Box", "Base.ShotgunShellsBox"
    }
    for _, fullType in ipairs(static) do bbms_addUnique(out, seen, fullType) end

    local sm = getScriptManager and getScriptManager() or nil
    local all = sm and sm.getAllItems and sm:getAllItems() or nil
    if all and all.size and all.get then
        local okSize, size = pcall(function() return all:size() end)
        size = okSize and tonumber(size) or 0
        for i = 0, size - 1 do
            local okGet, scriptItem = pcall(function() return all:get(i) end)
            if okGet and scriptItem then
                local fullType = bbms_scriptFullType(scriptItem)
                local text = string.lower(tostring(fullType or "") .. " " .. tostring(bbms_safeItemString(scriptItem, {"getDisplayName", "getName"}) or ""))
                if string.find(text, "ammo", 1, true) or string.find(text, "bullet", 1, true) or string.find(text, "round", 1, true) or string.find(text, "shell", 1, true) or string.find(text, "патрон", 1, true) then
                    bbms_addUnique(out, seen, fullType)
                end
            end
        end
    end
    BBMS_AMMO_DROP_CACHE = out
    return BBMS_AMMO_DROP_CACHE
end

local function bbms_collectWeaponMods()
    if type(BBMS_WEAPON_MOD_CACHE) == "table" then return BBMS_WEAPON_MOD_CACHE end
    local out, seen = {}, {}
    local static = {
        "Base.x2Scope", "Base.x4Scope", "Base.x8Scope", "Base.RedDot", "Base.Laser",
        "Base.RecoilPad", "Base.Sling", "Base.FiberglassStock", "Base.AmmoStrap",
        "Base.ChokeTubeFull", "Base.ChokeTubeImproved", "Base.IronSight", "Base.HolsterSimple", "Base.HolsterDouble"
    }
    for _, fullType in ipairs(static) do bbms_addUnique(out, seen, fullType) end

    local sm = getScriptManager and getScriptManager() or nil
    local all = sm and sm.getAllItems and sm:getAllItems() or nil
    if all and all.size and all.get then
        local okSize, size = pcall(function() return all:size() end)
        size = okSize and tonumber(size) or 0
        for i = 0, size - 1 do
            local okGet, scriptItem = pcall(function() return all:get(i) end)
            if okGet and scriptItem then
                local fullType = bbms_scriptFullType(scriptItem)
                local text = string.lower(tostring(fullType or "") .. " " .. tostring(bbms_safeItemString(scriptItem, {"getDisplayName", "getName"}) or ""))
                if string.find(text, "scope", 1, true) or string.find(text, "sight", 1, true) or string.find(text, "laser", 1, true)
                    or string.find(text, "suppressor", 1, true) or string.find(text, "silencer", 1, true) or string.find(text, "sling", 1, true)
                    or string.find(text, "choke", 1, true) or string.find(text, "stock", 1, true) or string.find(text, "recoil", 1, true)
                    or string.find(text, "weaponpart", 1, true) or string.find(text, "attachment", 1, true) then
                    bbms_addUnique(out, seen, fullType)
                end
            end
        end
    end
    BBMS_WEAPON_MOD_CACHE = out
    return BBMS_WEAPON_MOD_CACHE
end

local function bbms_appendRepeated(out, fullType, minCount, maxCount)
    fullType = bbms_normalizeFullType(fullType)
    if not fullType or not bbms_itemExists(fullType) then return 0 end
    local count = bbms_rand(minCount or 1, (maxCount or minCount or 1) + 1)
    for _ = 1, count do out[#out + 1] = fullType end
    return count
end

local function bbms_appendRandomExisting(out, pool, minCount, maxCount)
    local list = {}
    for _, fullType in ipairs(pool or {}) do
        fullType = bbms_normalizeFullType(fullType)
        if fullType and bbms_itemExists(fullType) then list[#list + 1] = fullType end
    end
    if #list <= 0 then return 0 end
    for i = #list, 2, -1 do
        local j = bbms_rand(1, i + 1)
        list[i], list[j] = list[j], list[i]
    end
    local count = bbms_rand(minCount or 1, (maxCount or minCount or 1) + 1)
    if count > #list then count = #list end
    for i = 1, count do out[#out + 1] = list[i] end
    return count
end

local function bbms_entryFromHeldItem(item)
    if not item then return nil end
    local fullType = bbms_createdItemFullType(item)
    if not fullType then return nil end
    if bbms_looksLikeContainerOrSupplyCase(item, fullType) then return nil end
    local ammo = bbms_getAmmoType(item)
    local magazine = bbms_getMagazineType(item)
    if not bbms_createdWeaponLooksRanged(item, fullType) and not ammo and not magazine then return nil end
    return { weapon = fullType, magazine = magazine, ammo = ammo, active = true }
end

local function bbms_entryFromFullType(fullType)
    fullType = bbms_normalizeFullType(fullType)
    if not fullType then return nil end
    local entry = bbms_weaponEntry(fullType)
    if entry then
        entry.active = true
        return entry
    end
    return nil
end

local function bbms_playerActiveWeaponEntry(player)
    if not player then return nil end
    if player.getPrimaryHandItem then
        local ok, item = pcall(function() return player:getPrimaryHandItem() end)
        local entry = ok and bbms_entryFromHeldItem(item) or nil
        if entry then return entry end
    end
    if player.getSecondaryHandItem then
        local ok, item = pcall(function() return player:getSecondaryHandItem() end)
        local entry = ok and bbms_entryFromHeldItem(item) or nil
        if entry then return entry end
    end
    return nil
end

local function bbms_randomExistingItems(list, minCount, maxCount)
    local pool = {}
    for _, fullType in ipairs(list or {}) do
        if bbms_itemExists(fullType) then pool[#pool + 1] = fullType end
    end
    if #pool <= 0 then return {} end
    for i = #pool, 2, -1 do
        local j = bbms_rand(1, i + 1)
        pool[i], pool[j] = pool[j], pool[i]
    end
    local count = bbms_rand(minCount or 1, (maxCount or #pool) + 1)
    if count > #pool then count = #pool end
    local out = {}
    for i = 1, count do out[#out + 1] = pool[i] end
    return out
end

local function bbms_isDirectCacheDropType(dropType)
    dropType = tostring(dropType or "")
    return dropType == "weapons" or dropType == "ammo" or dropType == "medical" or dropType == "armor"
end

local function bbms_cacheDisplayLabel(drop)
    local dropType = tostring(drop and drop.dropType or "")
    if dropType == "weapons" then return "Weapon cache"
    elseif dropType == "ammo" then return "Ammo cache"
    elseif dropType == "medical" then return "Medical cache"
    elseif dropType == "armor" then return "Armor cache" end
    return drop and drop.label or "Black market drop"
end

local function bbms_shouldMarkDropContent(drop)
    return not bbms_isDirectCacheDropType(drop and drop.dropType)
end

local function bbms_deadDropItems(data, bundle)
    if not bundle then return {} end
    local dropType = tostring(bundle.type or "")
    if dropType == "weapons" then
        local entry = bbms_pickWeaponEntry(data)
        local out = {}
        if entry and entry.weapon then out[#out + 1] = entry.weapon end
        if entry and entry.magazine then bbms_appendRepeated(out, entry.magazine, 2, 4) end
        if entry and entry.ammo then bbms_appendRepeated(out, entry.ammo, 4, 7) end
        bbms_appendRandomExisting(out, bbms_collectWeaponMods(), 1, 3)
        bbms_appendRandomExisting(out, bbms_collectAmmoTypes(), 1, 3)
        if #out <= 0 and type(bundle.items) == "table" then return bundle.items end
        return out
    elseif dropType == "armor" then
        local out = bbms_randomExistingItems(bundle.items, 5, 8)
        bbms_appendRandomExisting(out, {"Base.HolsterSimple", "Base.HolsterDouble", "Base.Bag_ALICEpack", "Base.Bag_DuffelBag"}, 1, 2)
        if #out > 0 then return out end
    elseif dropType == "ammo" then
        local out = {}
        local entry = bundle.activeWeaponEntry
        if entry and entry.ammo then bbms_appendRepeated(out, entry.ammo, 5, 9) end
        if entry and entry.magazine then bbms_appendRepeated(out, entry.magazine, 2, 4) end
        bbms_appendRandomExisting(out, bbms_collectWeaponMods(), 1, 3)
        bbms_appendRandomExisting(out, bbms_collectAmmoTypes(), 2, 5)
        if #out > 0 then return out end
        out = bbms_randomExistingItems(bundle.items, 4, 8)
        if #out > 0 then return out end
    elseif dropType == "medical" then
        local out = bbms_randomExistingItems(bundle.items, 5, 9)
        if #out > 0 then return out end
    end
    return type(bundle.items) == "table" and bundle.items or {}
end

local function bbms_dropTooClose(data, x, y, spacing)
    if not (data and type(data.deadDrops) == "table" and x and y) then return false end
    spacing = tonumber(spacing) or 4
    for _, drop in pairs(data.deadDrops) do
        if type(drop) == "table" and drop.status ~= "looted" then
            local dx = (tonumber(drop.x) or 0) - (tonumber(x) or 0)
            local dy = (tonumber(drop.y) or 0) - (tonumber(y) or 0)
            if (dx * dx + dy * dy) < (spacing * spacing) then return true end
        end
    end
    return false
end

local function bbms_squareAt(cell, x, y, z)
    if not (cell and cell.getGridSquare and x and y) then return nil end
    local ok, square = pcall(function() return cell:getGridSquare(math.floor(x), math.floor(y), math.floor(z or 0)) end)
    if ok and square then return square end
    return nil
end

local function bbms_pickDropSquare(player, contact, gmd)
    if not (player and player.getX and player.getY and getCell) then return nil end
    local cell = getCell()
    if not (cell and cell.getGridSquare) then return nil end
    local px, py = player:getX(), player:getY()
    local pz = player.getZ and player:getZ() or 0
    local z = math.floor(tonumber(pz) or 0)
    local data = NPCBlackMarketBridge and NPCBlackMarketBridge.EnsureData and NPCBlackMarketBridge.EnsureData(gmd) or nil
    local ox = contact and tonumber(contact.x) or nil
    local oy = contact and tonumber(contact.y) or nil
    if not ox or not oy then ox, oy = px, py end

    local minDist = math.max(3, bbms_num("BlackMarket_DeadDropMinDistance", 5, 2, 180))
    local maxDist = math.max(minDist + 3, bbms_num("BlackMarket_DeadDropMaxDistance", 14, 5, 240))
    local spacing = math.max(3, bbms_num("BlackMarket_DeadDropSpacing", 5, 2, 30))

    for _ = 1, 96 do
        local dist = bbms_rand(minDist, maxDist + 1)
        local angle = (bbms_rand(0, 6284) / 1000.0)
        local x = math.floor(ox + math.cos(angle) * dist + 0.5)
        local y = math.floor(oy + math.sin(angle) * dist + 0.5)
        if not bbms_dropTooClose(data, x, y, spacing) then
            local square = bbms_squareAt(cell, x, y, z)
            if square then return square, x, y, z end
        end
    end

    for radius = minDist, maxDist + spacing do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.abs(dx) == radius or math.abs(dy) == radius then
                    local x = math.floor(ox + dx)
                    local y = math.floor(oy + dy)
                    if not bbms_dropTooClose(data, x, y, spacing) then
                        local square = bbms_squareAt(cell, x, y, z)
                        if square then return square, x, y, z end
                    end
                end
            end
        end
    end

    -- Loaded-square fallback around the player, still avoiding an exact repeat when possible.
    for radius = 1, 8 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.abs(dx) == radius or math.abs(dy) == radius then
                    local x = math.floor(px + dx)
                    local y = math.floor(py + dy)
                    if not bbms_dropTooClose(data, x, y, 2) then
                        local square = bbms_squareAt(cell, x, y, z)
                        if square then return square, x, y, z end
                    end
                end
            end
        end
    end
    return nil
end

local function bbms_markDropItem(item, drop, role)
    if not (item and item.getModData and type(drop) == "table") then return end
    local ok, md = pcall(function() return item:getModData() end)
    if not (ok and type(md) == "table") then return end
    md.blackMarket = true
    md.blackMarketDrop = true
    md.blackMarketDeadDrop = true
    md.blackMarketDropId = drop.id
    md.blackMarketDropType = drop.dropType
    md.blackMarketDropStatus = drop.status
    md.blackMarketDropRole = role or md.blackMarketDropRole
    md.blackMarketDropContainer = (role == "container") or md.blackMarketDropContainer == true
    md.blackMarketDropContent = (role == "content") or md.blackMarketDropContent == true
    md.blackMarketSide = drop.side
    md.blackMarketPlayerId = drop.playerId
    md.blackMarketContactId = drop.contactId
    md.worldNameplate = true
    md.worldNameplateTitle = string.upper(tostring(drop.label or "BLACK MARKET DROP"))
    md.worldNameplateSubtitle = tostring(drop.status or "paid delivery")
    if role == "container" and item.setName then
        pcall(function() item:setName(bbms_cacheDisplayLabel(drop)) end)
    elseif item.setName and not bbms_isDirectCacheDropType(drop.dropType) then
        pcall(function() item:setName(drop.label or "Black market drop") end)
    end
    if item.transmitModData then pcall(function() item:transmitModData() end) end
end

local function bbms_transmitPlacedWorldItem(square, item, worldItem)
    -- AddWorldInventoryItem already places and syncs the world item. Extra
    -- transmitCompleteItemToClients/transmitModData calls can throw Java
    -- MethodArguments errors on hosted servers for IsoWorldInventoryObject,
    -- which also risks desyncing quest boxes. Keep this intentionally empty.
end

local function bbms_placeWorldInventoryItem(square, item)
    if not (square and item and square.AddWorldInventoryItem) then return false end
    local ox = 0.24 + (bbms_rand(0, 52) / 100.0)
    local oy = 0.24 + (bbms_rand(0, 52) / 100.0)
    local okWorld, worldItem = pcall(function() return square:AddWorldInventoryItem(item, ox, oy, 0) end)
    if okWorld == true and worldItem ~= nil then
        bbms_transmitPlacedWorldItem(square, item, worldItem)
        return true
    end
    return false
end

local function bbms_placeDeadDrop(square, drop, bundle, data)
    if not (square and drop and bundle and InventoryItemFactory) then return false end
    local containerItem = nil
    if type(bundle.container) == "table" then
        for _, fullType in ipairs(bundle.container) do
            containerItem = bbms_inventoryItem(fullType)
            if containerItem then break end
        end
    end
    if not containerItem then containerItem = bbms_inventoryItem("Base.Plasticbag") end
    if not containerItem then return false end

    bbms_markDropItem(containerItem, drop, "container")
    local inv = nil
    if containerItem.getInventory then
        local okInv, gotInv = pcall(function() return containerItem:getInventory() end)
        if okInv then inv = gotInv end
    end
    if bbms_isDirectCacheDropType(drop.dropType) and not inv then return false end
    local addedCount = 0
    local looseItems = {}
    local directCache = bbms_isDirectCacheDropType(drop.dropType)
    local dropItems = bbms_deadDropItems(data, bundle)
    if type(dropItems) == "table" then
        for _, itemType in ipairs(dropItems) do
            local addedItem = inv and bbms_addItemToInventory(inv, itemType) or nil
            if addedItem then
                if bbms_shouldMarkDropContent(drop) then bbms_markDropItem(addedItem, drop, "content") end
                addedCount = addedCount + 1
            elseif not directCache then
                local loose = bbms_inventoryItem(itemType)
                if loose then
                    if bbms_shouldMarkDropContent(drop) then bbms_markDropItem(loose, drop, "content") end
                    looseItems[#looseItems + 1] = loose
                end
            end
        end
    end

    local placed = bbms_placeWorldInventoryItem(square, containerItem)
    if not placed then return false end
    for _, loose in ipairs(looseItems) do
        if bbms_placeWorldInventoryItem(square, loose) then addedCount = addedCount + 1 end
    end
    drop.physical = true
    drop.materialized = true
    drop.itemCount = addedCount
    return true
end

local function bbms_buildDeadDropContainer(drop, bundle, data)
    if not (drop and bundle and InventoryItemFactory) then return nil, 0 end
    local containerItem = nil
    if type(bundle.container) == "table" then
        for _, fullType in ipairs(bundle.container) do
            containerItem = bbms_inventoryItem(fullType)
            if containerItem then break end
        end
    end
    if not containerItem then containerItem = bbms_inventoryItem("Base.Plasticbag") end
    if not containerItem then return nil, 0 end
    bbms_markDropItem(containerItem, drop, "container")
    local addedCount = 0
    local directCache = bbms_isDirectCacheDropType(drop.dropType)
    local inv = nil
    if containerItem.getInventory then
        local okInv, gotInv = pcall(function() return containerItem:getInventory() end)
        if okInv then inv = gotInv end
    end
    if directCache and not inv then return nil, 0 end
    local dropItems = bbms_deadDropItems(data, bundle)
    if inv and type(dropItems) == "table" then
        for _, itemType in ipairs(dropItems) do
            local addedItem = bbms_addItemToInventory(inv, itemType)
            if addedItem then
                if bbms_shouldMarkDropContent(drop) then bbms_markDropItem(addedItem, drop, "content") end
                addedCount = addedCount + 1
            end
        end
    end
    return containerItem, addedCount
end

local function bbms_grantDeadDropToPlayer(player, drop, bundle, data)
    if not (player and player.getInventory and drop and bundle) then return false end
    local okInv, playerInv = pcall(function() return player:getInventory() end)
    if not (okInv and playerInv) then return false end
    local package, addedCount = bbms_buildDeadDropContainer(drop, bundle, data)
    if not package then return false end
    local okAdd = false
    if playerInv.AddItem then
        okAdd = pcall(function() playerInv:AddItem(package) end)
    end
    if okAdd ~= true then return false end
    drop.physical = true
    drop.materialized = true
    drop.deliveryMode = "player_inventory_fallback"
    drop.inventoryFallback = true
    drop.itemCount = addedCount
    return true
end

local function bbms_createBlackMarketNoteItem(title, body, drop, subtype)
    local item = bbms_inventoryItem("Base.SheetPaper2") or bbms_inventoryItem("Base.SheetPaper")
    if not item then return nil end
    if item.setName then pcall(function() item:setName(tostring(title or "Black market note")) end) end
    if item.getModData then
        local okMd, md = pcall(function() return item:getModData() end)
        if okMd and type(md) == "table" then
            md.blackMarket = true
            md.blackMarketDocument = true
            md.blackMarketCredential = true
            md.blackMarketCredentialType = tostring(subtype or "note")
            md.blackMarketTitle = tostring(title or "Black market note")
            md.blackMarketText = tostring(body or "")
            if drop then
                md.blackMarketDropId = drop.id
                md.blackMarketDropType = drop.dropType
            end
        end
    end
    if drop then bbms_markDropItem(item, drop, "content") end
    if item.transmitModData then pcall(function() item:transmitModData() end) end
    return item
end

local function bbms_addExistingItemToInventory(inv, item)
    if not (inv and item and inv.AddItem) then return false end
    local ok = pcall(function() inv:AddItem(item) end)
    return ok == true
end

local function bbms_placeCustomDrop(square, drop, items, containers)
    if not (square and drop) then return false end
    local containerItem = nil
    if type(containers) == "table" then
        for _, fullType in ipairs(containers) do
            containerItem = bbms_inventoryItem(fullType)
            if containerItem then break end
        end
    end
    if not containerItem then containerItem = bbms_inventoryItem("Base.Plasticbag") end
    if not containerItem then return false end

    bbms_markDropItem(containerItem, drop, "container")
    local inv = nil
    if containerItem.getInventory then
        local okInv, gotInv = pcall(function() return containerItem:getInventory() end)
        if okInv then inv = gotInv end
    end

    local addedCount = 0
    local looseItems = {}
    for _, item in ipairs(items or {}) do
        if inv and bbms_addExistingItemToInventory(inv, item) then
            bbms_markDropItem(item, drop, "content")
            addedCount = addedCount + 1
        elseif item then
            bbms_markDropItem(item, drop, "content")
            looseItems[#looseItems + 1] = item
        end
    end

    if addedCount <= 0 and #looseItems <= 0 then return false end
    if not bbms_placeWorldInventoryItem(square, containerItem) then return false end
    for _, loose in ipairs(looseItems) do
        if bbms_placeWorldInventoryItem(square, loose) then addedCount = addedCount + 1 end
    end
    drop.physical = true
    drop.materialized = true
    drop.itemCount = addedCount
    return true
end

local function bbms_grantCustomDropToPlayer(player, drop, items, containers)
    if not (player and player.getInventory and drop) then return false end
    local okInv, playerInv = pcall(function() return player:getInventory() end)
    if not (okInv and playerInv) then return false end

    local containerItem = nil
    if type(containers) == "table" then
        for _, fullType in ipairs(containers) do
            containerItem = bbms_inventoryItem(fullType)
            if containerItem then break end
        end
    end
    if not containerItem then containerItem = bbms_inventoryItem("Base.Plasticbag") end
    if not containerItem then return false end
    bbms_markDropItem(containerItem, drop, "container")

    local inv = nil
    if containerItem.getInventory then
        local okNested, gotNested = pcall(function() return containerItem:getInventory() end)
        if okNested then inv = gotNested end
    end
    local addedCount = 0
    for _, item in ipairs(items or {}) do
        if item then
            bbms_markDropItem(item, drop, "content")
            if inv and bbms_addExistingItemToInventory(inv, item) then
                addedCount = addedCount + 1
            elseif bbms_addExistingItemToInventory(playerInv, item) then
                addedCount = addedCount + 1
            end
        end
    end
    if addedCount <= 0 then return false end
    if not bbms_addExistingItemToInventory(playerInv, containerItem) then return false end
    drop.physical = true
    drop.materialized = true
    drop.deliveryMode = "player_inventory_fallback"
    drop.inventoryFallback = true
    drop.itemCount = addedCount
    return true
end

local function bbms_createServiceDrop(gmd, player, contact, action, side, dropType, label, title, body)
    local data = NPCBlackMarketBridge.EnsureData(gmd)
    if not data then return false, "Black market data unavailable." end
    local square, x, y, z = bbms_pickDropSquare(player, contact, gmd)
    if not (square and x and y) and player and player.getX and player.getY then
        x = math.floor(tonumber(player:getX()) or 0)
        y = math.floor(tonumber(player:getY()) or 0)
        z = player.getZ and math.floor(tonumber(player:getZ()) or 0) or 0
    end

    local id = bbms_dropId(data)
    local now = bbms_nowHours()
    local drop = {
        id = id,
        contactId = contact and (contact.blackMarketId or contact.id) or nil,
        playerId = bbms_playerId(player),
        playerName = bbms_playerName(player),
        side = side or contact and (contact.blackMarketSide or contact.sourceSide) or nil,
        action = action,
        dropType = dropType or action or "service",
        label = label or title or "black market package",
        name = "Black market service package",
        x = x, y = y, z = z or 0,
        status = "active",
        serviceDrop = true,
        createdAt = now,
        updatedAt = now,
        expiresAt = now + 24
    }

    local note = bbms_createBlackMarketNoteItem(title, body, drop, dropType or action)
    if not note then return false, "Black market note could not be created." end

    local containers = {"Base.Bag_Satchel", "Base.Plasticbag"}
    local placed = false
    if square then placed = bbms_placeCustomDrop(square, drop, {note}, containers) end
    if not placed then
        placed = bbms_grantCustomDropToPlayer(player, drop, {note}, containers)
        if placed then
            drop.status = "delivered"
            drop.name = "Black market service delivery package"
        end
    end
    if not placed then return false, "Black market package could not be placed or delivered." end

    data.deadDrops[id] = drop
    data.stats.deadDrops = (tonumber(data.stats.deadDrops) or 0) + 1
    local marker = bbms_syncDrop(gmd, drop)
    if NPCNetContract and NPCNetContract.SendDebugMapUpdate and marker then NPCNetContract.SendDebugMapUpdate(marker) end
    if player and marker then sendServerCommand(player, 'NPCBlackMarket', 'DropCreated', {drop=drop, marker=marker}) end
    return true, drop
end

local function bbms_dropMarker(drop)
    if not drop then return nil end
    return {
        id = drop.id,
        markerType = "black_market_drop",
        blackMarket = true,
        blackMarketDrop = true,
        blackMarketDeadDrop = true,
        blackMarketDropId = drop.id,
        blackMarketDropType = drop.dropType,
        blackMarketDropStatus = drop.status,
        blackMarketDropLabel = drop.label,
        blackMarketSide = drop.side,
        blackMarketId = drop.contactId,
        blackMarketContactId = drop.contactId,
        blackMarketPlayerId = drop.playerId,
        blackMarketPlayerName = drop.playerName,
        blackMarketCompromised = drop.compromised == true,
        name = drop.name or drop.label or "Black market dead drop",
        displayName = string.upper(tostring(drop.label or "black market drop")),
        label = string.upper(tostring(drop.label or "black market drop")),
        blackMarketDropMapMarker = true,
        highContrastMapMarker = true,
        side = NPCBlackMarketBridge.ServiceSide and NPCBlackMarketBridge.ServiceSide() or "black_market",
        factionSide = NPCBlackMarketBridge.ServiceSide and NPCBlackMarketBridge.ServiceSide() or "black_market",
        sourceSide = drop.side,
        x = drop.x,
        y = drop.y,
        z = drop.z or 0,
        physicalStash = true,
        stashMarkerOverhead = true,
        stashRevealDistance = NPCBlackMarketBridge.DeadDropRevealDistance and NPCBlackMarketBridge.DeadDropRevealDistance() or 18,
        updatedAt = drop.updatedAt or bbms_nowHours(),
        expiresAt = drop.expiresAt
    }
end

local function bbms_syncDrop(gmd, drop)
    local marker = bbms_dropMarker(drop)
    if marker then setMarker(gmd, marker) end
    return marker
end

local function bbms_createDeadDrop(gmd, player, contact, action, side, args)
    if not (NPCBlackMarketBridge and NPCBlackMarketBridge.DeadDropEnabled and NPCBlackMarketBridge.DeadDropEnabled()) then
        return false, "Black market dead drops are disabled."
    end
    local bundle = NPCBlackMarketBridge.DeadDropBundle and NPCBlackMarketBridge.DeadDropBundle(action) or nil
    if not bundle then return false, "No dead-drop bundle for this deal." end
    bundle.activeWeaponEntry = bbms_entryFromFullType(args and args.activeWeaponFullType) or bbms_playerActiveWeaponEntry(player)
    local data = NPCBlackMarketBridge.EnsureData(gmd)
    if not data then return false, "Black market data unavailable." end
    local square, x, y, z = bbms_pickDropSquare(player, contact, gmd)
    if not (square and x and y) and player and player.getX and player.getY then
        x = math.floor(tonumber(player:getX()) or 0)
        y = math.floor(tonumber(player:getY()) or 0)
        z = player.getZ and math.floor(tonumber(player:getZ()) or 0) or 0
    end

    local id = bbms_dropId(data)
    local now = bbms_nowHours()
    local compromised = bbms_rand(0, 100) < (NPCBlackMarketBridge.DeadDropAmbushChance and NPCBlackMarketBridge.DeadDropAmbushChance() or 0)
    local drop = {
        id = id,
        contactId = contact and (contact.blackMarketId or contact.id) or nil,
        playerId = bbms_playerId(player),
        playerName = bbms_playerName(player),
        side = side or contact and (contact.blackMarketSide or contact.sourceSide) or nil,
        action = action,
        dropType = bundle.type,
        label = bundle.label,
        name = compromised and "Compromised black market cache" or "Black market cache",
        x = x,
        y = y,
        z = z or 0,
        status = compromised and "compromised" or "active",
        compromised = compromised,
        createdAt = now,
        updatedAt = now,
        expiresAt = now + 24
    }
    local placed = false
    if square then placed = bbms_placeDeadDrop(square, drop, bundle, data) end
    if not placed then
        placed = bbms_grantDeadDropToPlayer(player, drop, bundle, data)
        if placed then
            drop.status = "delivered"
            drop.name = "Black market direct delivery"
        end
    end
    if not placed then return false, "Black-market cache could not be placed or delivered." end
    data.deadDrops[id] = drop
    data.stats.deadDrops = (tonumber(data.stats.deadDrops) or 0) + 1
    local marker = bbms_syncDrop(gmd, drop)
    if NPCNetContract and NPCNetContract.SendDebugMapUpdate and marker then
        NPCNetContract.SendDebugMapUpdate(marker)
    end
    if player and marker then
        sendServerCommand(player, 'NPCBlackMarket', 'DropCreated', {drop=drop, marker=marker})
    end
    return true, drop
end


local function bbms_cacheItemName(item)
    if not item then return "" end
    for _, method in ipairs({"getName", "getDisplayName", "getFullType", "getType"}) do
        local fn = item[method]
        if type(fn) == "function" then
            local ok, value = pcall(function() return fn(item) end)
            if ok and value ~= nil then return tostring(value) end
        end
    end
    return ""
end

local function bbms_cacheItemCount(item)
    if not item then return nil end
    for _, method in ipairs({"getCount", "getUses", "getCurrentUses", "getDrainableUsesInt"}) do
        local fn = item[method]
        if type(fn) == "function" then
            local ok, value = pcall(function() return fn(item) end)
            if ok and tonumber(value) ~= nil then return tonumber(value) end
        end
    end
    return nil
end

local function bbms_cacheItemStillUseful(item)
    if not item then return false end
    local count = bbms_cacheItemCount(item)
    if count ~= nil and count <= 0 then return false end
    return true
end

local function bbms_itemInventoryEmpty(item, depth)
    if not item then return true end
    depth = tonumber(depth) or 0
    if depth > 5 then return false end

    local inv = nil
    if item.getInventory then
        local okInv, gotInv = pcall(function() return item:getInventory() end)
        if okInv then inv = gotInv end
    end
    if not inv then return not bbms_cacheItemStillUseful(item) end

    if inv.isEmpty then
        local ok, empty = pcall(function() return inv:isEmpty() end)
        if ok and empty == true then return true end
    end
    if not inv.getItems then return false end

    local okItems, items = pcall(function() return inv:getItems() end)
    if not (okItems and items and items.size and items.get) then return false end
    local okSize, size = pcall(function() return items:size() end)
    size = okSize and (tonumber(size) or 0) or 0
    if size <= 0 then return true end

    -- Empty nested cases/bags and spent zero-use stacks do not keep the cache alive.
    for i = 0, size - 1 do
        local okGet, child = pcall(function() return items:get(i) end)
        if okGet and child then
            local childInv = nil
            if child.getInventory then
                local okChildInv, gotChildInv = pcall(function() return child:getInventory() end)
                if okChildInv then childInv = gotChildInv end
            end
            if childInv then
                if not bbms_itemInventoryEmpty(child, depth + 1) then return false end
            elseif bbms_cacheItemStillUseful(child) then
                return false
            end
        end
    end
    return true
end

local function bbms_forceClientCacheRemoval(drop)
    if not drop then return end
    sendServerCommand('NPCBlackMarket', 'ForceRemoveCache', {
        id = tostring(drop.id or ""),
        dropId = tostring(drop.id or ""),
        dropType = tostring(drop.dropType or ""),
        label = tostring(bbms_cacheDisplayLabel(drop)),
        x = tonumber(drop.x),
        y = tonumber(drop.y),
        z = tonumber(drop.z) or 0
    })
end

local function bbms_dropContainerCandidate(item, md, drop, forceRemove)
    if not (item and drop) then return false end
    if type(md) == "table" and tostring(md.blackMarketDropId or "") == tostring(drop.id or "") then return true end
    if forceRemove ~= true then return false end
    local label = tostring(bbms_cacheDisplayLabel(drop)):lower()
    local name = tostring(bbms_cacheItemName(item)):lower()
    if label ~= "" and name == label then return true end
    if tostring(drop.dropType or "") == "ammo" and (name == "ammo cache" or name == "ammunition cache") then return true end
    return false
end

local function bbms_removeWorldInventoryObject(square, worldObject)
    if not (square and worldObject) then return false end
    local removed = false
    if square.transmitRemoveItemFromSquare then
        local ok = pcall(function() square:transmitRemoveItemFromSquare(worldObject) end)
        removed = removed or ok == true
    end
    if square.removeWorldObject then
        local ok = pcall(function() square:removeWorldObject(worldObject) end)
        removed = removed or ok == true
    end
    if worldObject.removeFromSquare then
        local ok = pcall(function() worldObject:removeFromSquare() end)
        removed = removed or ok == true
    end
    if worldObject.removeFromWorld then
        local ok = pcall(function() worldObject:removeFromWorld() end)
        removed = removed or ok == true
    end
    return removed
end

local function bbms_removeEmptyDropContainer(gmd, drop, forceRemove)
    if not (drop and getCell) then return false end
    forceRemove = forceRemove == true
    local cell = getCell()
    local square = bbms_squareAt(cell, drop.x, drop.y, drop.z or 0)
    if not (square and square.getWorldObjects) then return false end
    local worldObjects = nil
    local okObjects, gotObjects = pcall(function() return square:getWorldObjects() end)
    if okObjects then worldObjects = gotObjects end
    if not (worldObjects and worldObjects.size and worldObjects.get) then return false end
    local size = 0
    local okSize, gotSize = pcall(function() return worldObjects:size() end)
    if okSize then size = tonumber(gotSize) or 0 end

    local foundDropObject = false
    local hasNonEmptyDropObject = false
    local removedAny = false

    for i = size - 1, 0, -1 do
        local okGet, worldObject = pcall(function() return worldObjects:get(i) end)
        if okGet and worldObject and worldObject.getItem then
            local okItem, item = pcall(function() return worldObject:getItem() end)
            if okItem and item then
                local md = nil
                if item.getModData then
                    local okMd, gotMd = pcall(function() return item:getModData() end)
                    if okMd and type(gotMd) == "table" then md = gotMd end
                end
                if bbms_dropContainerCandidate(item, md, drop, forceRemove) then
                    foundDropObject = true
                    if forceRemove or bbms_itemInventoryEmpty(item, 0) then
                        if bbms_removeWorldInventoryObject(square, worldObject) then
                            removedAny = true
                        end
                    else
                        hasNonEmptyDropObject = true
                    end
                end
            end
        end
    end

    -- If the package itself was picked up, moved away, or reduced to empty
    -- nested cases, the purchased location is no longer a live stash. Remove
    -- the global/overhead marker immediately instead of waiting for expiry.
    if forceRemove or (foundDropObject and not hasNonEmptyDropObject) or (not foundDropObject and drop.materialized == true) then
        drop.status = "looted"
        drop.updatedAt = bbms_nowHours()
        bbms_forceClientCacheRemoval(drop)
        removeMarker(gmd, drop.id)
        return true
    end

    return removedAny
end

local function bbms_playerCanConfirmDropEmpty(player, drop)
    if not (player and drop and player.getX and player.getY) then return false end
    local dropType = tostring(drop.dropType or "")
    if not bbms_isDirectCacheDropType(dropType) then return false end
    local px, py = tonumber(player:getX()), tonumber(player:getY())
    local dx, dy = tonumber(drop.x), tonumber(drop.y)
    if not (px and py and dx and dy) then return false end
    local distSq = (px - dx) * (px - dx) + (py - dy) * (py - dy)
    if distSq <= (32 * 32) then return true end
    local pName = player.getUsername and player:getUsername() or player.getDisplayName and player:getDisplayName() or nil
    if pName and tostring(drop.playerName or "") == tostring(pName) then return true end
    return false
end

local function bbms_confirmEmptyDirectCache(gmd, player, args)
    if type(args) ~= "table" then return false end
    local id = tostring(args.id or args.dropId or "")
    if id == "" then return false end
    local data = NPCBlackMarketBridge.EnsureData(gmd)
    if not (data and type(data.deadDrops) == "table") then return false end
    local drop = data.deadDrops[id]
    if not (type(drop) == "table" and drop.status ~= "looted") then return false end
    if not bbms_playerCanConfirmDropEmpty(player, drop) then return false end
    bbms_removeEmptyDropContainer(gmd, drop, true)
    bbms_forceClientCacheRemoval(drop)
    drop.status = "looted"
    drop.updatedAt = bbms_nowHours()
    data.deadDrops[id] = nil
    removeMarker(gmd, id)
    if TransmitNPCModData then TransmitNPCModData() end
    return true
end

local function bbms_cleanupDeadDrops(gmd)
    local data = NPCBlackMarketBridge.EnsureData(gmd)
    if not (data and type(data.deadDrops) == "table") then return 0 end
    local now = bbms_nowHours()
    local removed = 0
    for id, drop in pairs(data.deadDrops) do
        if type(drop) == "table" and drop.status ~= "looted" then
            bbms_removeEmptyDropContainer(gmd, drop)
        end
        if type(drop) ~= "table" or (drop.expiresAt and now >= tonumber(drop.expiresAt)) or drop.status == "looted" then
            data.deadDrops[id] = nil
            removeMarker(gmd, id)
            removed = removed + 1
        end
    end
    return removed
end

local contactFor

local BBMS_FETCH_QUEST_ITEMS = {
    "Base.Painting",
    "Base.Picture",
    "Base.Vase",
    "Base.Statue",
    "Base.NecklaceLong_GoldDiamond",
    "Base.Necklace_GoldDiamond",
    "Base.Necklace_GoldRuby",
    "Base.Ring_Right_MiddleFinger_GoldDiamond",
    "Base.Ring_Left_MiddleFinger_GoldDiamond",
    "Base.Bracelet_BangleRightGold",
    "Base.WristWatch_Left_ClassicGold",
    "Base.WristWatch_Right_ClassicGold"
}

local BBMS_FETCH_QUEST_REWARD_CANS = {
    "Base.CannedSoup",
    "Base.CannedBeans",
    "Base.CannedCorn",
    "Base.CannedChili",
    "Base.CannedCornedBeef",
    "Base.CannedFruitCocktail",
    "Base.CannedPeaches",
    "Base.CannedSardines",
    "Base.CannedBolognese",
    "Base.TinnedSoup"
}

local BBMS_FETCH_QUEST_REWARD_MEDICAL = {
    {items={"Base.Bandage"}, count=10},
    {items={"Base.AlcoholBandage"}, count=10},
    {items={"Base.AlcoholWipes"}, count=10},
    {items={"Base.Disinfectant"}, count=10},
    {items={"Base.Antibiotics", "Base.PillsAntibiotics"}, count=10},
    {items={"Base.Pills"}, count=10},
    {items={"Base.PillsPainkillers"}, count=10},
    {items={"Base.PillsBeta"}, count=10},
    {items={"Base.SutureNeedle"}, count=10},
    {items={"Base.Tweezers"}, count=10},
    {items={"Base.Splint"}, count=10}
}

local BBMS_FETCH_QUEST_REWARD_WATER = {
    "Base.WaterBottleFull",
    "Base.WaterBottle",
    "Base.PopBottleWater",
    "Base.PopBottle"
}

local BBMS_REWARD_CONTAINER_CANDIDATES = {
    "Base.Bag_ALICEpack_Army",
    "Base.Bag_ALICEpack",
    "Base.Bag_BigHikingBag",
    "Base.Bag_NormalHikingBag",
    "Base.Bag_DuffelBag",
    "Base.Bag_Satchel",
    "Base.Plasticbag"
}

local function bbms_fetchQuestPlayerKey(player)
    local id = bbms_playerId(player)
    if id and tostring(id) ~= "" then return tostring(id) end
    return nil
end

local function bbms_fetchQuestId(data)
    data.nextFetchQuestId = tonumber(data.nextFetchQuestId) or 1
    local id = "black_market_fetch_" .. tostring(data.nextFetchQuestId)
    data.nextFetchQuestId = data.nextFetchQuestId + 1
    return id
end

local function bbms_activeFetchQuest(data, player)
    local key = bbms_fetchQuestPlayerKey(player)
    if not (key and data and type(data.fetchQuests) == "table") then return key, nil end
    local quest = data.fetchQuests[key]
    if type(quest) == "table" and quest.status == "active" then return key, quest end
    return key, nil
end

local function bbms_fetchQuestItemLabel(item, fullType)
    local label = bbms_itemDisplayText(item, fullType)
    if label and tostring(label) ~= "" then return tostring(label) end
    return tostring(fullType or "luxury item")
end

local function bbms_createFetchQuestItem(data)
    local count = #BBMS_FETCH_QUEST_ITEMS
    if count <= 0 then return nil, nil, nil end
    data.nextFetchQuestItemIndex = tonumber(data.nextFetchQuestItemIndex) or 1
    local start = math.max(1, math.floor(data.nextFetchQuestItemIndex))
    for i = 0, count - 1 do
        local index = ((start + i - 1) % count) + 1
        local fullType = BBMS_FETCH_QUEST_ITEMS[index]
        local item = bbms_inventoryItem(fullType)
        if item then
            data.nextFetchQuestItemIndex = (index % count) + 1
            return item, fullType, bbms_fetchQuestItemLabel(item, fullType)
        end
    end
    return nil, nil, nil
end

local function bbms_itemModData(item)
    if not (item and item.getModData) then return nil end
    local ok, md = pcall(function() return item:getModData() end)
    if ok and type(md) == "table" then return md end
    return nil
end

local function bbms_truthy(value)
    if value == true then return true end
    if tonumber(tostring(value or "")) == 1 then return true end
    local text = string.lower(tostring(value or ""))
    return text == "true" or text == "yes" or text == "y"
end

local function bbms_fetchQuestItemNameLooksQuest(item)
    if not item then return false end
    local methods = {"getName", "getDisplayName"}
    for _, method in ipairs(methods) do
        if item[method] then
            local ok, name = pcall(function() return item[method](item) end)
            if ok and name then
                local text = string.lower(tostring(name))
                if string.sub(text, 1, 6) == "quest:" then return true end
            end
        end
    end
    return false
end

local function bbms_fetchQuestItemMatches(item, quest)
    if not (item and quest) then return false end
    local questId = tostring(quest.id or "")
    local itemFullType = bbms_normalizeFullType(bbms_createdItemFullType(item))
    local questFullType = bbms_normalizeFullType(quest.itemFullType)
    local nameLooksQuest = bbms_fetchQuestItemNameLooksQuest(item)
    local md = bbms_itemModData(item)
    if md then
        local mdId = tostring(md.blackMarketFetchQuestId or md.blackMarketDropId or md.blackMarketQuestId or "")
        local markedItem = bbms_truthy(md.blackMarketFetchQuestItem) or tostring(md.blackMarketFetchQuestRole or "") == "item" or tostring(md.blackMarketDropRole or "") == "content"
        if questId ~= "" and mdId == questId then return true end
        if markedItem and (nameLooksQuest or not questFullType or questFullType == "" or itemFullType == questFullType) then return true end
    end
    -- Some PZ inventory transfers can lose custom ModData or expose a different
    -- fullType wrapper on the server. The quest item is intentionally renamed to
    -- QUEST: ..., but direct inventory turn-in should also survive cases where
    -- the custom name is not exposed server-side and only the original type remains.
    if nameLooksQuest then return true end
    if questFullType and questFullType ~= "" and itemFullType == questFullType then return true end
    return false
end

local function bbms_markFetchQuestItem(item, quest, role)
    local md = bbms_itemModData(item)
    if not (md and quest) then return end
    md.blackMarket = true
    md.blackMarketFetchQuest = true
    md.blackMarketFetchQuestId = quest.id
    md.blackMarketFetchQuestItem = role == "item" or md.blackMarketFetchQuestItem == true
    md.blackMarketFetchQuestContainer = role == "container" or md.blackMarketFetchQuestContainer == true
    md.blackMarketFetchQuestRole = role
    md.blackMarketContactId = quest.contactId
    md.blackMarketPlayerId = quest.playerId
    md.blackMarketPlayerName = quest.playerName
    md.blackMarketDropId = quest.id
    md.blackMarketDropType = "quest"
    md.blackMarketDropRole = role
    md.worldNameplate = true
    md.worldNameplateTitle = "QUEST"
    md.worldNameplateSubtitle = "guarded black market contract"
    if role == "item" and item.setName then
        pcall(function() item:setName("QUEST: " .. tostring(quest.itemLabel or "luxury item")) end)
    elseif role == "container" and item.setName then
        pcall(function() item:setName("QUEST CACHE") end)
    end
    if item.transmitModData then pcall(function() item:transmitModData() end) end
end

local function bbms_fetchQuestZoneRadius()
    if NPCBlackMarketBridge and NPCBlackMarketBridge.FetchQuestZoneRadius then
        local ok, value = pcall(function() return NPCBlackMarketBridge.FetchQuestZoneRadius() end)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return 24
end

local function bbms_fetchQuestTurnInMarkerId(quest)
    if not quest then return nil end
    return tostring(quest.id or "") .. "_turnin"
end

local function bbms_fetchQuestTurnInMarker(quest)
    if not (quest and quest.contactId and quest.turnInX and quest.turnInY) then return nil end
    return {
        id = bbms_fetchQuestTurnInMarkerId(quest),
        markerType = "black_market_turnin",
        blackMarket = true,
        blackMarketTurnIn = true,
        blackMarketQuestTurnIn = true,
        blackMarketFetchQuestId = quest.id,
        blackMarketId = quest.contactId,
        blackMarketContactId = quest.contactId,
        blackMarketPlayerId = quest.playerId,
        blackMarketPlayerName = quest.playerName,
        name = "QUEST turn-in black market",
        displayName = "QUEST TURN-IN",
        label = "QUEST TURN-IN",
        side = NPCBlackMarketBridge.ServiceSide and NPCBlackMarketBridge.ServiceSide() or "black_market",
        factionSide = NPCBlackMarketBridge.ServiceSide and NPCBlackMarketBridge.ServiceSide() or "black_market",
        sourceSide = quest.side,
        x = quest.turnInX,
        y = quest.turnInY,
        z = quest.turnInZ or 0,
        blackMarketTurnInMapMarker = true,
        updatedAt = quest.updatedAt or bbms_nowHours()
    }
end

local function bbms_syncFetchQuestTurnInMarker(gmd, quest)
    local marker = bbms_fetchQuestTurnInMarker(quest)
    if not marker then return nil end
    setMarker(gmd, marker)
    if NPCBlackMarketBridge and NPCBlackMarketBridge.GetContact then
        local contact = NPCBlackMarketBridge.GetContact(gmd, quest.contactId)
        if contact then
            contact.blackMarketQuestTurnInHighlight = true
            contact.updatedAt = bbms_nowHours()
            syncMarker(gmd, contact)
            syncContactsAll()
        end
    end
    return marker
end

local function bbms_removeFetchQuestMarkers(gmd, quest)
    if not (gmd and quest) then return end
    if quest.id then removeMarker(gmd, quest.id) end
    local turnInId = bbms_fetchQuestTurnInMarkerId(quest)
    if turnInId and turnInId ~= "_turnin" then removeMarker(gmd, turnInId) end
    if NPCBlackMarketBridge and NPCBlackMarketBridge.GetContact then
        local contact = NPCBlackMarketBridge.GetContact(gmd, quest.contactId)
        if contact then
            contact.blackMarketQuestTurnInHighlight = nil
            contact.updatedAt = bbms_nowHours()
            syncMarker(gmd, contact)
            syncContactsAll()
        end
    end
end

local function bbms_fetchQuestMarker(quest)
    if not quest then return nil end
    return {
        id = quest.id,
        markerType = "black_market_drop",
        blackMarket = true,
        blackMarketDrop = true,
        blackMarketDeadDrop = true,
        blackMarketDropId = quest.id,
        blackMarketDropType = "quest",
        blackMarketDropStatus = quest.status or "active",
        blackMarketDropLabel = "QUEST",
        blackMarketId = quest.contactId,
        blackMarketContactId = quest.contactId,
        blackMarketPlayerId = quest.playerId,
        blackMarketPlayerName = quest.playerName,
        name = "Black market steal contract",
        displayName = "QUEST",
        label = "QUEST",
        blackMarketDropMapMarker = true,
        side = NPCBlackMarketBridge.ServiceSide and NPCBlackMarketBridge.ServiceSide() or "black_market",
        factionSide = NPCBlackMarketBridge.ServiceSide and NPCBlackMarketBridge.ServiceSide() or "black_market",
        sourceSide = quest.side,
        x = quest.x,
        y = quest.y,
        z = quest.z or 0,
        originalCacheX = quest.originalCacheX or quest.x,
        originalCacheY = quest.originalCacheY or quest.y,
        originalCacheZ = quest.originalCacheZ or quest.z or 0,
        blackMarketQuestZoneRadius = quest.zoneRadius or bbms_fetchQuestZoneRadius(),
        physicalStash = true,
        stashMarkerOverhead = true,
        stashRevealDistance = 80,
        updatedAt = quest.updatedAt or bbms_nowHours()
    }
end

local function bbms_fetchQuestMarkerKey(quest)
    if not quest then return nil end
    return tostring(quest.id or "") .. ":" .. tostring(math.floor((tonumber(quest.x) or 0) + 0.5)) .. ":" .. tostring(math.floor((tonumber(quest.y) or 0) + 0.5)) .. ":" .. tostring(math.floor(tonumber(quest.z) or 0)) .. ":" .. tostring(quest.status or "active") .. ":" .. tostring(quest.carried == true)
end

local function bbms_syncFetchQuestMarker(gmd, quest, player, force)
    if not (gmd and quest and quest.id) then return nil end
    if quest.carried == true or quest.markerHidden == true then
        if quest.lastMarkerKey ~= "hidden" then removeMarker(gmd, quest.id) end
        quest.lastMarkerKey = "hidden"
        return nil
    end
    local key = bbms_fetchQuestMarkerKey(quest)
    if force ~= true and quest.lastMarkerKey == key then return bbms_fetchQuestMarker(quest) end
    local marker = bbms_fetchQuestMarker(quest)
    if marker then
        setMarker(gmd, marker)
        quest.lastMarkerKey = key
        if NPCNetContract and NPCNetContract.SendDebugMapUpdate then NPCNetContract.SendDebugMapUpdate(marker) end
        if player then sendServerCommand(player, 'NPCBlackMarket', 'DropCreated', {drop=quest, marker=marker}) end
    end
    return marker
end

local function bbms_fetchQuestStatePayload(quest, hasItem)
    if type(quest) ~= "table" or quest.status ~= "active" then return {quest=nil, hasItem=false} end
    return {
        quest = {
            id = quest.id,
            contactId = quest.contactId,
            itemFullType = quest.itemFullType,
            itemLabel = quest.itemLabel,
            x = quest.x,
            y = quest.y,
            z = quest.z or 0,
            originalCacheX = quest.originalCacheX or quest.x,
            originalCacheY = quest.originalCacheY or quest.y,
            originalCacheZ = quest.originalCacheZ or quest.z or 0,
            turnInX = quest.turnInX,
            turnInY = quest.turnInY,
            turnInZ = quest.turnInZ or 0,
            zoneRadius = quest.zoneRadius or bbms_fetchQuestZoneRadius(),
            carried = quest.carried == true,
            status = quest.status,
            questType = quest.questType or "steal",
            guarded = quest.guarded == true,
            guardCount = quest.guardCount,
            cacheEscaped = quest.cacheEscaped == true,
            guardsDematerialized = quest.guardsDematerialized == true
        },
        hasItem = hasItem == true
    }
end

local function bbms_sendFetchQuestState(player, gmd)
    if not player then return end
    local data = NPCBlackMarketBridge.EnsureData(gmd or GetNPCModData())
    local _, quest = bbms_activeFetchQuest(data, player)
    local hasItem = false
    if quest then
        local found = nil
        if player and player.getInventory then
            local okInv, inv = pcall(function() return player:getInventory() end)
            if okInv and inv then
                local scan
                scan = function(container, depth, seen)
                    if found or not container or (tonumber(depth) or 0) > 6 then return end
                    seen = seen or {}
                    if seen[container] then return end
                    seen[container] = true
                    if not container.getItems then return end
                    local okItems, items = pcall(function() return container:getItems() end)
                    if not (okItems and items and items.size and items.get) then return end
                    local okSize, size = pcall(function() return items:size() end)
                    size = okSize and (tonumber(size) or 0) or 0
                    for i = 0, size - 1 do
                        local okItem, item = pcall(function() return items:get(i) end)
                        if okItem and item then
                            if bbms_fetchQuestItemMatches(item, quest) then
                                found = item
                                return
                            end
                            local child = nil
                            if item.getInventory then
                                local okChild, gotChild = pcall(function() return item:getInventory() end)
                                if okChild then child = gotChild end
                            end
                            if child then scan(child, (tonumber(depth) or 0) + 1, seen) end
                            if found then return end
                        end
                    end
                end
                scan(inv, 0, {})
            end
        end
        hasItem = found ~= nil
    end
    sendServerCommand(player, 'NPCBlackMarket', 'FetchQuestState', bbms_fetchQuestStatePayload(quest, hasItem))
end

local function bbms_placeFetchQuestCache(square, quest, data)
    if not (square and quest and data and InventoryItemFactory) then return false end
    local questItem, fullType, itemLabel = bbms_createFetchQuestItem(data)
    if not questItem then return false end
    quest.itemFullType = fullType
    quest.itemLabel = itemLabel

    local containerItem = bbms_inventoryItem("Base.Bag_Satchel") or bbms_inventoryItem("Base.Bag_DuffelBag") or bbms_inventoryItem("Base.Plasticbag")
    if not containerItem then return false end
    bbms_markFetchQuestItem(questItem, quest, "item")
    bbms_markFetchQuestItem(containerItem, quest, "container")

    local inv = nil
    if containerItem.getInventory then
        local okInv, gotInv = pcall(function() return containerItem:getInventory() end)
        if okInv then inv = gotInv end
    end
    if inv and not bbms_addExistingItemToInventory(inv, questItem) then return false end
    if not inv then return false end
    if not bbms_placeWorldInventoryItem(square, containerItem) then return false end
    quest.physical = true
    quest.materialized = true
    quest.itemInCache = true
    quest.originalCacheX = quest.x
    quest.originalCacheY = quest.y
    quest.originalCacheZ = quest.z or 0
    quest.zoneRadius = quest.zoneRadius or bbms_fetchQuestZoneRadius()
    return true
end

local function bbms_fetchQuestTurnInBoxId(quest)
    if not quest then return nil end
    return tostring(quest.id or "") .. "_turnin_box"
end

local function bbms_markFetchQuestTurnInBox(item, quest)
    local md = bbms_itemModData(item)
    if not (md and quest) then return end
    md.blackMarket = true
    md.blackMarketFetchQuest = true
    md.blackMarketFetchQuestTurnInBox = true
    md.blackMarketFetchQuestId = quest.id
    md.blackMarketContactId = quest.contactId
    md.blackMarketPlayerId = quest.playerId
    md.blackMarketPlayerName = quest.playerName
    md.blackMarketDropId = bbms_fetchQuestTurnInBoxId(quest)
    md.blackMarketDropType = "quest_turnin"
    md.worldNameplate = true
    md.worldNameplateTitle = "QUEST TURN-IN"
    md.worldNameplateSubtitle = "put the stolen item here"
    if item.setName then pcall(function() item:setName("QUEST TURN-IN BOX") end) end
    if item.transmitModData then pcall(function() item:transmitModData() end) end
end

local function bbms_markFetchQuestRewardBox(item, quest)
    local md = bbms_itemModData(item)
    if not (md and quest) then return end
    md.blackMarket = true
    md.blackMarketFetchQuest = true
    md.blackMarketFetchQuestTurnInBox = false
    md.blackMarketFetchQuestRewardBox = true
    md.blackMarketFetchQuestId = quest.id
    md.blackMarketContactId = quest.contactId
    md.blackMarketPlayerId = quest.playerId
    md.blackMarketPlayerName = quest.playerName
    md.blackMarketDropId = tostring(quest.id or "") .. "_reward_box"
    md.blackMarketDropType = "quest_reward"
    md.blackMarketRewardPersistent = true
    md.blackMarketKeepOnVirtual = true
    md.blackMarketDoNotAutoCleanup = true
    md.worldNameplate = true
    md.worldNameplateTitle = "BLACK MARKET REWARD"
    md.worldNameplateSubtitle = "quest payment"
    if item.setName then pcall(function() item:setName("BLACK MARKET REWARD") end) end
    if item.transmitModData then pcall(function() item:transmitModData() end) end
end

local function bbms_itemInventory(item)
    if not (item and item.getInventory) then return nil end
    local okInv, inv = pcall(function() return item:getInventory() end)
    if okInv then return inv end
    return nil
end

local function bbms_turnInBoxCandidate(item, quest)
    if not (item and quest) then return false end
    local md = bbms_itemModData(item)
    if type(md) == "table" then
        if md.blackMarketFetchQuestTurnInBox == true then
            local qid = tostring(md.blackMarketFetchQuestId or "")
            local cid = tostring(md.blackMarketContactId or "")
            if qid == tostring(quest.id or "") or cid == tostring(quest.contactId or "") then return true end
        end
    end
    local name = string.lower(bbms_cacheItemName(item) or "")
    return name == "quest turn-in box" or name == "quest turn in box"
end

local function bbms_fetchQuestBoxRole(item, quest)
    if not (item and quest) then return nil end
    local questId = tostring(quest.id or "")
    local contactId = tostring(quest.contactId or "")
    local md = bbms_itemModData(item)
    local name = string.lower(bbms_cacheItemName(item) or "")
    local matchesQuest = false
    local matchesContact = false
    if type(md) == "table" then
        matchesQuest = questId ~= "" and tostring(md.blackMarketFetchQuestId or "") == questId
        matchesContact = contactId ~= "" and tostring(md.blackMarketContactId or "") == contactId
        if (matchesQuest or matchesContact) and md.blackMarketFetchQuestTurnInBox == true then return "turnin" end
        if (matchesQuest or matchesContact) and md.blackMarketFetchQuestRewardBox == true then return "reward" end
    end
    if name == "quest turn-in box" or name == "quest turn in box" then return "turnin" end
    if name == "black market reward" or name == "black-market reward" then return "reward" end
    return nil
end

local function bbms_findFetchQuestBoxesNear(x, y, z, quest, radius)
    local out = {}
    if not (quest and getCell) then return out end
    local cell = getCell()
    if not (cell and cell.getGridSquare) then return out end
    local cx = math.floor((tonumber(x) or tonumber(quest.turnInX) or 0) + 0.5)
    local cy = math.floor((tonumber(y) or tonumber(quest.turnInY) or 0) + 0.5)
    local cz = math.floor(tonumber(z) or tonumber(quest.turnInZ) or 0)
    radius = math.max(1, math.floor(tonumber(radius) or 5))
    for dx = -radius, radius do
        for dy = -radius, radius do
            local square = bbms_squareAt(cell, cx + dx, cy + dy, cz)
            if square and square.getWorldObjects then
                local okObjects, worldObjects = pcall(function() return square:getWorldObjects() end)
                if okObjects and worldObjects and worldObjects.size and worldObjects.get then
                    local okSize, size = pcall(function() return worldObjects:size() end)
                    size = okSize and (tonumber(size) or 0) or 0
                    for i = 0, size - 1 do
                        local okObj, worldObject = pcall(function() return worldObjects:get(i) end)
                        if okObj and worldObject and worldObject.getItem then
                            local okItem, item = pcall(function() return worldObject:getItem() end)
                            if okItem and item then
                                local role = bbms_fetchQuestBoxRole(item, quest)
                                if role then
                                    out[#out + 1] = {item=item, worldObject=worldObject, square=square, role=role}
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return out
end

local function bbms_removeFetchQuestBoxesNear(x, y, z, quest, radius, keepWorldObject, removeReward)
    local removed = 0
    local boxes = bbms_findFetchQuestBoxesNear(x, y, z, quest, radius)
    for _, box in ipairs(boxes) do
        if box.worldObject and box.square and box.worldObject ~= keepWorldObject then
            if box.role == "turnin" then
                if bbms_removeWorldInventoryObject(box.square, box.worldObject) then removed = removed + 1 end
            elseif box.role == "reward" and removeReward == true then
                -- Reward boxes are intentional player loot containers. Do not wipe
                -- partially looted reward boxes when a market virtualizes or when a
                -- later quest places a new reward; only empty leftovers are safe to clear.
                if bbms_itemInventoryEmpty(box.item, 0) then
                    if bbms_removeWorldInventoryObject(box.square, box.worldObject) then removed = removed + 1 end
                end
            end
        end
    end
    return removed
end

local function bbms_cleanupStaleFetchQuestTurnInBoxes(gmd)
    local data = NPCBlackMarketBridge and NPCBlackMarketBridge.EnsureData and NPCBlackMarketBridge.EnsureData(gmd) or nil
    if not (data and type(data.contacts) == "table") then return 0 end
    local active = {}
    if type(data.fetchQuests) == "table" then
        for _, quest in pairs(data.fetchQuests) do
            if type(quest) == "table" and quest.status == "active" and quest.id then
                active[tostring(quest.id)] = true
            end
        end
    end

    local removed = 0
    for _, contact in pairs(data.contacts) do
        if type(contact) == "table" and contact.x and contact.y then
            local contactId = tostring(contact.blackMarketId or contact.id or "")
            local probe = {id="", contactId=contactId, turnInX=contact.x, turnInY=contact.y, turnInZ=contact.z or 0}
            local boxes = bbms_findFetchQuestBoxesNear(contact.x, contact.y, contact.z or 0, probe, 7)
            for _, box in ipairs(boxes) do
                if box.role == "turnin" and box.item and box.worldObject and box.square then
                    local md = bbms_itemModData(box.item)
                    local qid = type(md) == "table" and tostring(md.blackMarketFetchQuestId or "") or ""
                    if qid == "" or active[qid] ~= true then
                        if bbms_removeWorldInventoryObject(box.square, box.worldObject) then removed = removed + 1 end
                    end
                end
            end
        end
    end
    return removed
end

local function bbms_findFetchQuestTurnInBoxNear(x, y, z, quest, radius)
    if not (quest and getCell) then return nil, nil, nil end
    local cell = getCell()
    if not (cell and cell.getGridSquare) then return nil, nil, nil end
    local cx = math.floor((tonumber(x) or tonumber(quest.turnInX) or 0) + 0.5)
    local cy = math.floor((tonumber(y) or tonumber(quest.turnInY) or 0) + 0.5)
    local cz = math.floor(tonumber(z) or tonumber(quest.turnInZ) or 0)
    radius = math.max(1, math.floor(tonumber(radius) or 3))
    for dx = -radius, radius do
        for dy = -radius, radius do
            local square = bbms_squareAt(cell, cx + dx, cy + dy, cz)
            if square and square.getWorldObjects then
                local okObjects, worldObjects = pcall(function() return square:getWorldObjects() end)
                if okObjects and worldObjects and worldObjects.size and worldObjects.get then
                    local okSize, size = pcall(function() return worldObjects:size() end)
                    size = okSize and (tonumber(size) or 0) or 0
                    for i = 0, size - 1 do
                        local okObj, worldObject = pcall(function() return worldObjects:get(i) end)
                        if okObj and worldObject and worldObject.getItem then
                            local okItem, item = pcall(function() return worldObject:getItem() end)
                            if okItem and bbms_turnInBoxCandidate(item, quest) then return item, worldObject, square end
                        end
                    end
                end
            end
        end
    end
    return nil, nil, nil
end

local function bbms_findFetchQuestTurnInBoxNearContact(contact, quest, radius)
    if not (contact and quest) then return nil, nil, nil end
    return bbms_findFetchQuestTurnInBoxNear(contact.x, contact.y, contact.z, quest, radius)
end

local function bbms_updateFetchQuestTurnInTarget(quest, contact)
    if not (quest and contact) then return false end
    local x = tonumber(contact.x) or tonumber(quest.turnInX)
    local y = tonumber(contact.y) or tonumber(quest.turnInY)
    local z = tonumber(contact.z) or tonumber(quest.turnInZ) or 0
    if not (x and y) then return false end
    local changed = math.floor((tonumber(quest.turnInX) or x) + 0.5) ~= math.floor(x + 0.5) or math.floor((tonumber(quest.turnInY) or y) + 0.5) ~= math.floor(y + 0.5) or math.floor(tonumber(quest.turnInZ) or z) ~= math.floor(z)
    quest.turnInX = x
    quest.turnInY = y
    quest.turnInZ = z
    if changed then quest.updatedAt = bbms_nowHours() end
    return changed
end

local function bbms_ensureFetchQuestTurnInBox(gmd, quest, contact)
    if not (quest and contact and getCell) then return false end
    local targetX = tonumber(contact.x) or tonumber(quest.turnInX)
    local targetY = tonumber(contact.y) or tonumber(quest.turnInY)
    local targetZ = tonumber(contact.z) or tonumber(quest.turnInZ) or 0
    if not (targetX and targetY) then return false end

    local oldX = tonumber(quest.turnInBoxX) or tonumber(quest.turnInX)
    local oldY = tonumber(quest.turnInBoxY) or tonumber(quest.turnInY)
    local oldZ = tonumber(quest.turnInBoxZ) or tonumber(quest.turnInZ) or 0
    local moved = oldX and oldY and ((math.floor(oldX + 0.5) ~= math.floor(targetX + 0.5)) or (math.floor(oldY + 0.5) ~= math.floor(targetY + 0.5)) or (math.floor(oldZ) ~= math.floor(targetZ)))

    if moved then
        local oldBox, oldWorldObject, oldSquare = bbms_findFetchQuestTurnInBoxNear(oldX, oldY, oldZ, quest, 3)
        if oldBox and oldWorldObject and oldSquare then
            if bbms_itemInventoryEmpty(oldBox, 0) then
                bbms_removeWorldInventoryObject(oldSquare, oldWorldObject)
            else
                -- Do not duplicate or move a box that already contains the stolen item.
                quest.turnInBoxX = oldSquare.getX and oldSquare:getX() or oldX
                quest.turnInBoxY = oldSquare.getY and oldSquare:getY() or oldY
                quest.turnInBoxZ = oldSquare.getZ and oldSquare:getZ() or oldZ
                bbms_updateFetchQuestTurnInTarget(quest, contact)
                return true
            end
        end
    end

    bbms_updateFetchQuestTurnInTarget(quest, contact)
    local existing, _, existingSquare = bbms_findFetchQuestTurnInBoxNear(targetX, targetY, targetZ, quest, 3)
    if existing then
        quest.turnInBoxPlaced = true
        quest.turnInBoxX = existingSquare and existingSquare.getX and existingSquare:getX() or targetX
        quest.turnInBoxY = existingSquare and existingSquare.getY and existingSquare:getY() or targetY
        quest.turnInBoxZ = existingSquare and existingSquare.getZ and existingSquare:getZ() or targetZ
        quest.turnInBoxUpdatedAt = bbms_nowHours()
        return true
    end

    local cell = getCell()
    local square = bbms_squareAt(cell, targetX, targetY, targetZ)
    if not square then return false end
    local box = bbms_inventoryItem("Base.Bag_Satchel") or bbms_inventoryItem("Base.Bag_DuffelBag") or bbms_inventoryItem("Base.Plasticbag")
    if not box then return false end
    bbms_markFetchQuestTurnInBox(box, quest)
    if not bbms_placeWorldInventoryItem(square, box) then return false end
    quest.turnInBoxPlaced = true
    quest.turnInBoxX = square.getX and square:getX() or targetX
    quest.turnInBoxY = square.getY and square:getY() or targetY
    quest.turnInBoxZ = square.getZ and square:getZ() or targetZ
    quest.turnInBoxUpdatedAt = bbms_nowHours()
    return true
end

local function bbms_removeEmptyFetchQuestTurnInBox(gmd, quest, contact)
    if not quest then return false end
    local box, worldObject, square = nil, nil, nil
    if contact then box, worldObject, square = bbms_findFetchQuestTurnInBoxNearContact(contact, quest, 3) end
    if not box then box, worldObject, square = bbms_findFetchQuestTurnInBoxNear(quest.turnInBoxX or quest.turnInX, quest.turnInBoxY or quest.turnInY, quest.turnInBoxZ or quest.turnInZ or 0, quest, 3) end
    if not (box and worldObject and square) then return false end
    if not bbms_itemInventoryEmpty(box, 0) then return false end
    return bbms_removeWorldInventoryObject(square, worldObject)
end

local function bbms_worldDirector()
    local director = NPCWorldDirectorServer or NPCWorldDirector
    if type(director) == "table" and director.EnsureData then return director end
    return nil
end

local function bbms_tableCopy(tbl)
    if type(tbl) ~= "table" then return nil end
    local out = {}
    for k, v in pairs(tbl) do
        if type(v) == "table" then
            local child = {}
            for ck, cv in pairs(v) do child[ck] = cv end
            out[k] = child
        else
            out[k] = v
        end
    end
    return out
end

local function bbms_pickListEntry(list)
    if type(list) ~= "table" or #list <= 0 then return nil end
    local index = bbms_rand(1, #list + 1)
    return list[index]
end

local function bbms_fetchQuestGuardCount()
    local minCount = 3
    local maxCount = 5
    if NPCBlackMarketBridge and NPCBlackMarketBridge.FetchQuestGuardMin then
        local okMin, gotMin = pcall(function() return NPCBlackMarketBridge.FetchQuestGuardMin() end)
        if okMin then minCount = tonumber(gotMin) or minCount end
    end
    if NPCBlackMarketBridge and NPCBlackMarketBridge.FetchQuestGuardMax then
        local okMax, gotMax = pcall(function() return NPCBlackMarketBridge.FetchQuestGuardMax() end)
        if okMax then maxCount = tonumber(gotMax) or maxCount end
    end
    minCount = math.max(0, math.floor(minCount))
    maxCount = math.max(minCount, math.floor(maxCount))
    if maxCount <= minCount then return minCount end
    return minCount + bbms_rand(0, (maxCount - minCount) + 1)
end

local function bbms_fetchQuestGuardLeashRadius()
    if NPCBlackMarketBridge and NPCBlackMarketBridge.FetchQuestGuardLeashRadius then
        local ok, value = pcall(function() return NPCBlackMarketBridge.FetchQuestGuardLeashRadius() end)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return 7
end

local function bbms_fetchQuestGuardSpawnRadius()
    if NPCBlackMarketBridge and NPCBlackMarketBridge.FetchQuestGuardSpawnRadius then
        local ok, value = pcall(function() return NPCBlackMarketBridge.FetchQuestGuardSpawnRadius() end)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return 9
end

local function bbms_fetchQuestGuardAnchor(quest, index)
    local x = tonumber(quest and (quest.originalCacheX or quest.x)) or 0
    local y = tonumber(quest and (quest.originalCacheY or quest.y)) or 0
    local z = tonumber(quest and (quest.originalCacheZ or quest.z)) or 0
    local radius = 2 + ((math.max(1, tonumber(index) or 1) - 1) % 3)
    local angle = ((math.max(1, tonumber(index) or 1) - 1) * 2.399963)
    return {x=math.floor(x + math.cos(angle) * radius + 0.5), y=math.floor(y + math.sin(angle) * radius + 0.5), z=z}
end

local function bbms_fetchQuestGuardWeapon(slot, fallback)
    local pool = nil
    if slot == "primary" then
        if NPCWeaponsBridge and NPCWeaponsBridge.GetSpawnPrimary then
            local ok, got = pcall(function() return NPCWeaponsBridge.GetSpawnPrimary(nil) end)
            if ok then pool = got end
        elseif NPCWeaponsBridge then pool = NPCWeaponsBridge.Primary end
    elseif slot == "secondary" then
        if NPCWeaponsBridge and NPCWeaponsBridge.GetSpawnSecondary then
            local ok, got = pcall(function() return NPCWeaponsBridge.GetSpawnSecondary(nil) end)
            if ok then pool = got end
        elseif NPCWeaponsBridge then pool = NPCWeaponsBridge.Secondary end
    end
    local weapon = bbms_tableCopy(bbms_pickListEntry(pool)) or bbms_tableCopy(fallback)
    if type(weapon) ~= "table" then return fallback end
    weapon.magSize = math.max(1, tonumber(weapon.magSize) or tonumber(fallback and fallback.magSize) or 15)
    weapon.bulletsLeft = weapon.magSize
    weapon.magCount = math.max(tonumber(weapon.magCount) or 0, tonumber(fallback and fallback.magCount) or 4)
    return weapon
end

local function bbms_applyFetchQuestGuardLoadout(member, index)
    if type(member) ~= "table" then return member end
    member.weapons = type(member.weapons) == "table" and member.weapons or {}
    member.weapons.melee = false
    member.weapons.primary = bbms_fetchQuestGuardWeapon("primary", {name="Base.AssaultRifle", magName="Base.556Clip", magSize=30, bulletsLeft=30, magCount=5, shotDelay=12})
    member.weapons.secondary = bbms_fetchQuestGuardWeapon("secondary", {name="Base.Pistol", magName="Base.9mmClip", magSize=15, bulletsLeft=15, magCount=4, shotDelay=35})

    if NPCOutfitsBridge then
        local pool = NPCOutfitsBridge.PrivateMilitia or NPCOutfitsBridge.Veteran or NPCOutfitsBridge.Prepper or NPCOutfitsBridge.Survivalist
        local outfit = bbms_pickListEntry(pool)
        if outfit then member.outfit = outfit end
    end

    member.accuracyBoost = math.max(tonumber(member.accuracyBoost) or 1, index == 1 and 1.35 or 1.18)
    member.health = math.max(tonumber(member.health) or 3.0, index == 1 and 4.2 or 3.5)
    member.maxHealth = math.max(tonumber(member.maxHealth) or 0, member.health)
    member.morale = math.max(tonumber(member.morale) or 0, 0.94)
    member.discipline = math.max(tonumber(member.discipline) or 0, 0.92)
    member.aggression = math.max(tonumber(member.aggression) or 0, 0.78)
    member.fear = math.min(tonumber(member.fear) or 1, 0.08)
    return member
end

local function bbms_applyFetchQuestGuardFields(member, group, quest, index)
    if type(member) ~= "table" then return member end
    local anchor = bbms_fetchQuestGuardAnchor(quest, index)
    local leash = bbms_fetchQuestGuardLeashRadius()
    member.blackMarketQuestGuard = true
    member.blackMarketQuestId = quest and quest.id or nil
    member.blackMarketQuestCacheId = quest and quest.id or nil
    member.worldGroupId = group and group.id or member.worldGroupId
    member.groupId = group and group.id or member.groupId
    member.memberIndex = index
    member.displayTitle = index == 1 and "QUEST Cache Sergeant" or "QUEST Cache Guard"
    member.nameplateTitle = member.displayTitle
    member.role = index == 1 and "black_market_quest_sergeant" or "black_market_quest_guard"
    member.tacticalRole = "guard"
    member.program = {name="BaseGuard", stage="Prepare"}
    member.guardPoint = {x=anchor.x, y=anchor.y, z=anchor.z}
    member.holdPoint = {x=anchor.x, y=anchor.y, z=anchor.z}
    member.returnPoint = {x=anchor.x, y=anchor.y, z=anchor.z}
    member.checkpointHoldRadius = math.max(3, leash)
    member.blackMarketQuestGuardLeash = math.max(3, leash)
    member.order = {
        name="Guard",
        source="black_market_fetch_quest",
        fireMode="FireAtWill",
        priority=94,
        sticky=true,
        strict=true,
        formation="close",
        followDistance=1.0,
        anchor={x=anchor.x, y=anchor.y, z=anchor.z},
        guardPoint={x=anchor.x, y=anchor.y, z=anchor.z},
        leash={guard=leash, hold=math.max(2.8, leash * 0.55), combat=leash},
        note="Protect guarded black-market QUEST cache"
    }
    member.factionSide = "black"
    member.faction = "black"
    member.side = "black"
    member.patrolColor = "black"
    member.hostile = true
    member.targetClass = "black_market_quest_intruder"
    member.humanNPC = true
    member.forceHumanAnimation = true
    member.noZombieAnimation = true
    member.defaultWalkType = "Walk"
    member.walkType = "Walk"
    member.preferCover = true
    member.preferRoads = false
    member.roadBias = false
    return bbms_applyFetchQuestGuardLoadout(member, index)
end

local function bbms_groupById(gmd, groupId)
    if not (gmd and type(gmd.VirtualGroups) == "table" and groupId) then return nil end
    return gmd.VirtualGroups[tostring(groupId)]
end

local function bbms_refreshFetchQuestGuardOrders(gmd, quest)
    if not (gmd and quest and quest.guardGroupId) then return false end
    local group = bbms_groupById(gmd, quest.guardGroupId)
    if type(group) ~= "table" then return false end
    local leash = bbms_fetchQuestGuardLeashRadius()
    local changed = false
    group.blackMarketQuestGuardGroup = true
    group.blackMarketQuestId = quest.id
    group.x = math.floor(tonumber(quest.originalCacheX or quest.x) or 0)
    group.y = math.floor(tonumber(quest.originalCacheY or quest.y) or 0)
    group.z = tonumber(quest.originalCacheZ or quest.z) or 0
    group.targetX = group.x
    group.targetY = group.y
    group.targetZ = group.z
    group.routeX = group.x
    group.routeY = group.y
    group.routeZ = group.z
    group.program = {name="BaseGuard", stage="Prepare"}
    group.hostile = true
    group.factionSide = "black"
    group.faction = "black"
    group.side = "black"
    group.patrolColor = "black"
    group.targetClass = "black_market_quest_intruder"
    group.blackMarketQuestGuardLeash = leash
    for i, member in ipairs(group.members or {}) do
        bbms_applyFetchQuestGuardFields(member, group, quest, i)
        changed = true
    end
    if type(gmd.Queue) == "table" then
        for runtimeId, brain in pairs(gmd.Queue) do
            if type(brain) == "table" and tostring(brain.worldGroupId or brain.groupId or "") == tostring(group.id or quest.guardGroupId) then
                local idx = tonumber(brain.memberIndex) or 1
                local anchor = bbms_fetchQuestGuardAnchor(quest, idx)
                brain.blackMarketQuestGuard = true
                brain.blackMarketQuestId = quest.id
                brain.blackMarketQuestCacheId = quest.id
                brain.guardPoint = {x=anchor.x, y=anchor.y, z=anchor.z}
                brain.holdPoint = {x=anchor.x, y=anchor.y, z=anchor.z}
                brain.returnPoint = {x=anchor.x, y=anchor.y, z=anchor.z}
                brain.checkpointHoldRadius = math.max(3, leash)
                brain.blackMarketQuestGuardLeash = math.max(3, leash)
                brain.order = brain.order or {}
                brain.order.name = "Guard"
                brain.order.source = "black_market_fetch_quest"
                brain.order.fireMode = "FireAtWill"
                brain.order.priority = 94
                brain.order.sticky = true
                brain.order.strict = true
                brain.order.anchor = {x=anchor.x, y=anchor.y, z=anchor.z}
                brain.order.guardPoint = {x=anchor.x, y=anchor.y, z=anchor.z}
                brain.order.leash = {guard=leash, hold=math.max(2.8, leash * 0.55), combat=leash}
                brain.program = {name="BaseGuard", stage=(brain.program and brain.program.stage) or "Prepare"}
                brain.hostile = true
                brain.factionSide = "black"
                brain.faction = "black"
                brain.side = "black"
                brain.patrolColor = "black"
                brain.humanNPC = true
                brain.forceHumanAnimation = true
                brain.noZombieAnimation = true
                brain.defaultWalkType = brain.defaultWalkType or "Walk"
                brain.walkType = brain.walkType or "Walk"
                gmd.Queue[runtimeId] = brain
                changed = true
            end
        end
    end
    group.updatedAt = bbms_nowHours()
    gmd.VirtualGroups[tostring(group.id or quest.guardGroupId)] = group
    return changed
end

local function bbms_requestFetchQuestGuardCleanup(gmd, quest, reason)
    if not (gmd and quest and quest.guardGroupId) then return false end
    local groupId = tostring(quest.guardGroupId)
    local group = bbms_groupById(gmd, groupId)
    if type(gmd.VirtualGroups) == "table" then gmd.VirtualGroups[groupId] = nil end
    if type(gmd.DebugMapMarkers) == "table" then gmd.DebugMapMarkers[groupId] = nil end
    if NPCNetContract and NPCNetContract.SendDebugMapRemove then NPCNetContract.SendDebugMapRemove(groupId) else sendServerCommand('NPCDebugMap','Remove',{id=groupId}) end

    local director = bbms_worldDirector()
    local args = {
        groupId = groupId,
        persistentIds = NPCWorldDirectorBridge and NPCWorldDirectorBridge.GroupPersistentIds and group and NPCWorldDirectorBridge.GroupPersistentIds(group) or nil,
        x = quest.originalCacheX or quest.x,
        y = quest.originalCacheY or quest.y,
        z = quest.originalCacheZ or quest.z or 0,
        radius = 56,
        reason = tostring(reason or "black_market_fetch_quest_cleanup")
    }
    local ok = false
    if director and director ~= NPCWorldDirectorBridge and director.RequestNPCObjectCleanup then
        local safe = pcall(function() director.RequestNPCObjectCleanup(args) end)
        ok = safe == true
    end
    if director and NPCWorldDirectorBridge and NPCWorldDirectorBridge.RequestNPCObjectCleanup then
        local safe = pcall(function() NPCWorldDirectorBridge.RequestNPCObjectCleanup(director, args) end)
        ok = ok or safe == true
    end
    quest.guardGroupId = nil
    quest.guardsRemovedAt = bbms_nowHours()
    return true
end

local function bbms_createFetchQuestGuardGroup(gmd, player, quest, contact)
    if not (gmd and player and quest and quest.id) then return false end
    if quest.guardGroupId and bbms_groupById(gmd, quest.guardGroupId) then
        bbms_refreshFetchQuestGuardOrders(gmd, quest)
        return true
    end
    local director = bbms_worldDirector()
    if not (director and NPCWorldDirectorBridge and NPCWorldDirectorBridge.PrepareVirtualMember) then return false end
    local count = bbms_fetchQuestGuardCount()
    if count <= 0 then return true end

    local groupId = "BMQG" .. tostring(quest.id)
    local wave = {
        enabled=true,
        enemyBehaviour=9,
        firstDay=0,
        lastDay=99999,
        spawnHourlyChance=0,
        groupSize=count,
        clanId=17,
        hasPistolChance=100,
        pistolMagCount=5,
        hasRifleChance=100,
        rifleMagCount=5
    }
    local group = {
        id = groupId,
        x = math.floor(tonumber(quest.originalCacheX or quest.x) or 0),
        y = math.floor(tonumber(quest.originalCacheY or quest.y) or 0),
        z = tonumber(quest.originalCacheZ or quest.z) or 0,
        preciseX = tonumber(quest.originalCacheX or quest.x) or 0,
        preciseY = tonumber(quest.originalCacheY or quest.y) or 0,
        clanId = wave.clanId,
        count = count,
        hostile = true,
        program = {name="BaseGuard", stage="Prepare"},
        members = {},
        virtual = true,
        activated = false,
        createdAt = bbms_nowHours(),
        updatedAt = bbms_nowHours(),
        state = "black_market_quest_guard",
        spawnClass = "black_market_quest_guard",
        targetX = quest.originalCacheX or quest.x,
        targetY = quest.originalCacheY or quest.y,
        targetZ = quest.originalCacheZ or quest.z or 0,
        routeX = quest.originalCacheX or quest.x,
        routeY = quest.originalCacheY or quest.y,
        routeZ = quest.originalCacheZ or quest.z or 0,
        targetClass = "black_market_quest_intruder",
        speed = 0,
        patrolColor = "black",
        factionSide = "black",
        faction = "black",
        side = "black",
        blackMarketQuestGuardGroup = true,
        blackMarketQuestId = quest.id,
        blackMarketQuestContactId = contact and (contact.blackMarketId or contact.id) or quest.contactId,
        anchorMaterializeAtGroup = true,
        anchorSpawnRadius = bbms_fetchQuestGuardSpawnRadius(),
        displayTitle = "QUEST Cache Guards",
        name = "Black market QUEST cache guards"
    }
    for i = 1, count do
        local member = nil
        local okMember, gotMember = pcall(function()
            return NPCWorldDirectorBridge.PrepareVirtualMember(director, gmd, wave, groupId, i, "black", false)
        end)
        if okMember then member = gotMember end
        if type(member) ~= "table" then member = {} end
        if NPCIdentityBridge and NPCIdentityBridge.NewUID then
            member.uid = member.uid or NPCIdentityBridge.NewUID(gmd)
            member.persistentId = member.persistentId or member.uid
        end
        bbms_applyFetchQuestGuardFields(member, group, quest, i)
        group.members[#group.members + 1] = member
    end
    group.count = #group.members
    if group.count <= 0 then return false end

    gmd.VirtualGroups = gmd.VirtualGroups or {}
    gmd.VirtualGroups[groupId] = group
    quest.guardGroupId = groupId
    quest.guarded = true
    quest.guardCount = group.count
    bbms_refreshFetchQuestGuardOrders(gmd, quest)

    if NPCPersistentNPCBridge and NPCPersistentNPCBridge.RegisterGroup then pcall(function() NPCPersistentNPCBridge.RegisterGroup(gmd, group) end) end
    local ok = false
    if director and director ~= NPCWorldDirectorBridge and director.MaterializeGroup then
        local safe, result = pcall(function() return director.MaterializeGroup(group, player) end)
        ok = safe and result == true
    end
    if not ok and NPCWorldDirectorBridge and NPCWorldDirectorBridge.MaterializeGroup then
        local safe, result = pcall(function() return NPCWorldDirectorBridge.MaterializeGroup(director, group, player) end)
        ok = safe and result == true
    end
    if ok then
        local current = bbms_groupById(gmd, groupId) or group
        current.blackMarketQuestGuardGroup = true
        current.blackMarketQuestId = quest.id
        current.state = current.spawnPending and "spawning" or "physical"
        current.updatedAt = bbms_nowHours()
        gmd.VirtualGroups[groupId] = current
        bbms_refreshFetchQuestGuardOrders(gmd, quest)
        return true
    end

    -- A steal contract must not exist as a free, unguarded cache. If the
    -- world director cannot materialize/schedule the guard group, roll it back
    -- so the caller refuses the contract instead of spawning only markers/boxes.
    gmd.VirtualGroups[groupId] = nil
    quest.guardGroupId = nil
    quest.guarded = false
    quest.guardCount = 0
    return false
end

local function bbms_findFetchQuestItemInContainer(container, quest, depth, seen)
    if not (container and quest) or (tonumber(depth) or 0) > 6 then return nil, nil end
    seen = seen or {}
    if seen[container] then return nil, nil end
    seen[container] = true
    if not container.getItems then return nil, nil end
    local okItems, items = pcall(function() return container:getItems() end)
    if not (okItems and items and items.size and items.get) then return nil, nil end
    local okSize, size = pcall(function() return items:size() end)
    size = okSize and (tonumber(size) or 0) or 0
    for i = 0, size - 1 do
        local okItem, item = pcall(function() return items:get(i) end)
        if okItem and item then
            if bbms_fetchQuestItemMatches(item, quest) then return item, container end
            local child = nil
            if item.getInventory then
                local okChild, gotChild = pcall(function() return item:getInventory() end)
                if okChild then child = gotChild end
            end
            if child then
                local found, owner = bbms_findFetchQuestItemInContainer(child, quest, (tonumber(depth) or 0) + 1, seen)
                if found then return found, owner end
            end
        end
    end
    return nil, nil
end

local function bbms_findFetchQuestItemInWornItems(player, quest)
    if not (player and player.getWornItems and quest) then return nil, nil end
    local okWorn, worn = pcall(function() return player:getWornItems() end)
    if not (okWorn and worn) then return nil, nil end
    local size = 0
    if worn.size then
        local okSize, gotSize = pcall(function() return worn:size() end)
        if okSize then size = tonumber(gotSize) or 0 end
    end
    for i = 0, size - 1 do
        local item = nil
        if worn.getItemByIndex then
            local okItem, gotItem = pcall(function() return worn:getItemByIndex(i) end)
            if okItem then item = gotItem end
        end
        if not item and worn.get then
            local okRow, row = pcall(function() return worn:get(i) end)
            if okRow and row then
                if row.getItem then
                    local okItem, gotItem = pcall(function() return row:getItem() end)
                    if okItem then item = gotItem end
                else
                    item = row
                end
            end
        end
        if item and bbms_fetchQuestItemMatches(item, quest) then return item, nil end
    end
    return nil, nil
end

local function bbms_findFetchQuestItemInHands(player, quest)
    if not (player and quest) then return nil, nil end
    for _, method in ipairs({"getPrimaryHandItem", "getSecondaryHandItem"}) do
        if player[method] then
            local okItem, item = pcall(function() return player[method](player) end)
            if okItem and item and bbms_fetchQuestItemMatches(item, quest) then return item, nil end
        end
    end
    return nil, nil
end

local function bbms_findFetchQuestItemInPlayer(player, quest)
    if not (player and quest) then return nil, nil end
    if player.getInventory then
        local okInv, inv = pcall(function() return player:getInventory() end)
        if okInv and inv then
            local item, container = bbms_findFetchQuestItemInContainer(inv, quest, 0, {})
            if item then return item, container end
        end
    end
    local wornItem, wornContainer = bbms_findFetchQuestItemInWornItems(player, quest)
    if wornItem then return wornItem, wornContainer end
    return bbms_findFetchQuestItemInHands(player, quest)
end

local function bbms_findFetchQuestItemNearContact(contact, quest, radius)
    if not (contact and quest and getCell) then return nil, nil, nil, nil end
    local cell = getCell()
    if not (cell and cell.getGridSquare) then return nil, nil, nil, nil end
    local cx = math.floor((tonumber(contact.x) or tonumber(quest.turnInX) or 0) + 0.5)
    local cy = math.floor((tonumber(contact.y) or tonumber(quest.turnInY) or 0) + 0.5)
    local cz = math.floor(tonumber(contact.z) or tonumber(quest.turnInZ) or 0)
    radius = math.max(1, math.floor(tonumber(radius) or 4))
    for dx = -radius, radius do
        for dy = -radius, radius do
            local square = bbms_squareAt(cell, cx + dx, cy + dy, cz)
            if square and square.getWorldObjects then
                local okObjects, worldObjects = pcall(function() return square:getWorldObjects() end)
                if okObjects and worldObjects and worldObjects.size and worldObjects.get then
                    local okSize, size = pcall(function() return worldObjects:size() end)
                    size = okSize and (tonumber(size) or 0) or 0
                    for i = 0, size - 1 do
                        local okObj, worldObject = pcall(function() return worldObjects:get(i) end)
                        if okObj and worldObject and worldObject.getItem then
                            local okItem, item = pcall(function() return worldObject:getItem() end)
                            if okItem and item then
                                if bbms_fetchQuestItemMatches(item, quest) then return item, nil, worldObject, square, item end
                                local inv = nil
                                if item.getInventory then
                                    local okInv, gotInv = pcall(function() return item:getInventory() end)
                                    if okInv then inv = gotInv end
                                end
                                if inv then
                                    local found, owner = bbms_findFetchQuestItemInContainer(inv, quest, 0, {})
                                    if found then return found, owner, worldObject, square, item end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return nil, nil, nil, nil
end

local function bbms_inventoryCapacity(inv)
    if not inv then return nil end
    for _, method in ipairs({"getCapacity", "getMaxWeight", "getWeightLimit"}) do
        local fn = inv[method]
        if type(fn) == "function" then
            local ok, value = pcall(function() return fn(inv) end)
            if ok and tonumber(value) and tonumber(value) > 0 then return tonumber(value) end
        end
    end
    return nil
end

local function bbms_inventoryWeight(inv)
    if not inv then return 0 end
    for _, method in ipairs({"getContentsWeight", "getWeight"}) do
        local fn = inv[method]
        if type(fn) == "function" then
            local ok, value = pcall(function() return fn(inv) end)
            if ok and tonumber(value) then return tonumber(value) end
        end
    end
    return 0
end

local function bbms_itemWeight(fullType)
    local item = bbms_inventoryItem(fullType)
    if not item then return 0.1 end
    for _, method in ipairs({"getActualWeight", "getWeight"}) do
        local fn = item[method]
        if type(fn) == "function" then
            local ok, value = pcall(function() return fn(item) end)
            if ok and tonumber(value) and tonumber(value) > 0 then return tonumber(value) end
        end
    end
    return 0.1
end

local function bbms_validRewardItems(list)
    local out = {}
    local seen = {}
    if type(list) ~= "table" then return out end
    for _, fullType in ipairs(list) do
        fullType = bbms_normalizeFullType(fullType)
        if fullType and not seen[fullType] and bbms_inventoryItem(fullType) then
            seen[fullType] = true
            out[#out + 1] = fullType
        end
    end
    return out
end

local function bbms_rewardContainerItem()
    local bestItem = nil
    local bestCapacity = -1
    for _, fullType in ipairs(BBMS_REWARD_CONTAINER_CANDIDATES) do
        local item = bbms_inventoryItem(fullType)
        local inv = bbms_itemInventory(item)
        if item and inv then
            local capacity = bbms_inventoryCapacity(inv) or 0
            if capacity > bestCapacity then
                bestItem = item
                bestCapacity = capacity
            end
        end
    end
    return bestItem
end

local function bbms_fillInventoryWithPool(inv, pool, maxAdds)
    if not (inv and type(pool) == "table" and #pool > 0) then return 0 end
    local added = 0
    local capacity = bbms_inventoryCapacity(inv)
    local minWeight = 999
    for _, fullType in ipairs(pool) do
        minWeight = math.min(minWeight, bbms_itemWeight(fullType))
    end
    if minWeight == 999 then minWeight = 0.1 end
    -- Keep the reward box valuable and visibly full, but avoid hundreds of tiny
    -- persistent InventoryItem objects that slow down chunk load/teleport sync.
    maxAdds = math.min(140, math.max(1, math.floor(tonumber(maxAdds) or 120)))
    local consecutiveFailed = 0
    local index = 1
    for _ = 1, maxAdds do
        if capacity and bbms_inventoryWeight(inv) >= math.max(0, capacity - minWeight) then break end
        local fullType = pool[index]
        index = (index % #pool) + 1
        if fullType and bbms_addItemToInventoryQuiet(inv, fullType) then
            added = added + 1
            consecutiveFailed = 0
        else
            consecutiveFailed = consecutiveFailed + 1
            if consecutiveFailed >= #pool then break end
        end
    end
    return added
end

local function bbms_grantFetchQuestRewardToInventory(inv)
    if not (inv and inv.AddItem) then return 0 end
    local added = 0
    local cans = bbms_validRewardItems(BBMS_FETCH_QUEST_REWARD_CANS)
    local water = bbms_validRewardItems(BBMS_FETCH_QUEST_REWARD_WATER)
    local fillPool = {}

    -- Seed the box with all requested reward categories first, then keep filling
    -- it until the container is practically full so the player must choose what to take.
    for i = 1, 10 do
        local fullType = cans[((i - 1) % math.max(1, #cans)) + 1]
        if fullType and bbms_addItemToInventoryQuiet(inv, fullType) then added = added + 1 end
    end
    -- Heavier food/water goes into the filler pool first; medical items are
    -- still guaranteed above, but no longer dominate the extra fill pass.
    for _, fullType in ipairs(cans) do fillPool[#fillPool + 1] = fullType end
    for _, fullType in ipairs(water) do fillPool[#fillPool + 1] = fullType end

    for _, reward in ipairs(BBMS_FETCH_QUEST_REWARD_MEDICAL) do
        local count = math.max(0, math.floor(tonumber(reward.count) or 0))
        local candidates = bbms_validRewardItems(type(reward.items) == "table" and reward.items or {})
        local fullType = candidates[1]
        if fullType then
            for _ = 1, count do
                if bbms_addItemToInventoryQuiet(inv, fullType) then added = added + 1 end
            end
            fillPool[#fillPool + 1] = fullType
        end
    end

    for i = 1, 10 do
        local fullType = water[((i - 1) % math.max(1, #water)) + 1]
        if fullType and bbms_addItemToInventoryQuiet(inv, fullType) then added = added + 1 end
    end

    added = added + bbms_fillInventoryWithPool(inv, fillPool, 120)
    return added
end

local function bbms_buildFetchQuestRewardBox(quest)
    if not quest then return nil, 0 end
    local box = bbms_rewardContainerItem()
    if not box then return nil, 0 end
    bbms_markFetchQuestRewardBox(box, quest)
    local inv = bbms_itemInventory(box)
    if not inv then return nil, 0 end
    local rewardCount = bbms_grantFetchQuestRewardToInventory(inv)
    if rewardCount <= 0 then return nil, 0 end
    bbms_markFetchQuestRewardBox(box, quest)
    return box, rewardCount
end


local function bbms_grantFetchQuestReward(player)
    if not (player and player.getInventory) then return 0 end
    local okInv, inv = pcall(function() return player:getInventory() end)
    if not okInv then return 0 end
    return bbms_grantFetchQuestRewardToInventory(inv)
end

local function bbms_containerExactCount(container, fullType)
    if not (container and container.getItems and fullType) then return 0 end
    fullType = tostring(fullType)
    local okItems, items = pcall(function() return container:getItems() end)
    if not (okItems and items and items.size and items.get) then return 0 end
    local okSize, size = pcall(function() return items:size() end)
    size = okSize and (tonumber(size) or 0) or 0
    local count = 0
    for i = 0, size - 1 do
        local okGet, child = pcall(function() return items:get(i) end)
        if okGet and child and tostring(bbms_createdItemFullType(child) or "") == fullType then count = count + 1 end
    end
    return count
end

local function bbms_containerContainsExactItem(container, item)
    if not (container and item) then return false end
    if item.getContainer then
        local okContainer, owner = pcall(function() return item:getContainer() end)
        if okContainer and owner ~= nil and owner == container then return true end
    end
    if item.getItemContainer then
        local okContainer, owner = pcall(function() return item:getItemContainer() end)
        if okContainer and owner ~= nil and owner == container then return true end
    end
    if not container.getItems then return false end
    local okItems, items = pcall(function() return container:getItems() end)
    if not (okItems and items and items.size and items.get) then return false end
    local okSize, size = pcall(function() return items:size() end)
    size = okSize and (tonumber(size) or 0) or 0
    for i = 0, size - 1 do
        local okGet, child = pcall(function() return items:get(i) end)
        if okGet and child == item then return true end
    end
    return false
end

local function bbms_syncRemovedInventoryItem(container, item)
    if container and container.removeItemOnServer and item then pcall(function() container:removeItemOnServer(item) end) end
    if item and item.transmitModData then pcall(function() item:transmitModData() end) end
end

local function bbms_removeItemFromContainer(container, item)
    if not (container and item) then return false end
    local fullType = bbms_createdItemFullType(item)
    local before = fullType and bbms_containerExactCount(container, fullType) or 0
    local hadItem = bbms_containerContainsExactItem(container, item)
    local methods = {"Remove", "RemoveItem", "DoRemoveItem", "removeItem"}
    for _, method in ipairs(methods) do
        local fn = container[method]
        if fn then
            local ok = pcall(function() fn(container, item) end)
            if ok then
                bbms_syncRemovedInventoryItem(container, item)
                if not bbms_containerContainsExactItem(container, item) then return true end
                if before > 0 and fullType and bbms_containerExactCount(container, fullType) < before then return true end
            end
        end
    end
    return hadItem == true and not bbms_containerContainsExactItem(container, item)
end

local function bbms_detachFetchQuestItemFromPlayer(player, item)
    if not (player and item) then return end
    if player.getPrimaryHandItem and player.setPrimaryHandItem then
        local okHeld, held = pcall(function() return player:getPrimaryHandItem() end)
        if okHeld and held == item then pcall(function() player:setPrimaryHandItem(nil) end) end
    end
    if player.getSecondaryHandItem and player.setSecondaryHandItem then
        local okHeld, held = pcall(function() return player:getSecondaryHandItem() end)
        if okHeld and held == item then pcall(function() player:setSecondaryHandItem(nil) end) end
    end
    if player.removeWornItem then pcall(function() player:removeWornItem(item) end) end
    local bodyLocation = nil
    if item.getBodyLocation then
        local okLoc, gotLoc = pcall(function() return item:getBodyLocation() end)
        if okLoc and gotLoc then bodyLocation = tostring(gotLoc) end
    end
    if bodyLocation and bodyLocation ~= "" then
        if player.setWornItem then pcall(function() player:setWornItem(bodyLocation, nil) end) end
        if player.getWornItems then
            local okWorn, worn = pcall(function() return player:getWornItems() end)
            if okWorn and worn then
                if worn.setItem then pcall(function() worn:setItem(bodyLocation, nil) end) end
                if worn.remove then pcall(function() worn:remove(bodyLocation) end) end
                if worn.Remove then pcall(function() worn:Remove(bodyLocation) end) end
            end
        end
    end
end

local function bbms_removeFetchQuestItem(item, container, player, worldObject, square)
    if not item then return false end
    if container and bbms_removeItemFromContainer(container, item) then return true end
    if player then bbms_detachFetchQuestItemFromPlayer(player, item) end
    if player and player.getInventory then
        local okInv, inv = pcall(function() return player:getInventory() end)
        if okInv and inv and bbms_removeItemFromContainer(inv, item) then return true end
    end
    if worldObject and square then
        local directWorldItem = false
        if worldObject.getItem then
            local okItem, worldItem = pcall(function() return worldObject:getItem() end)
            directWorldItem = okItem and worldItem == item
        end
        if directWorldItem and bbms_removeWorldInventoryObject(square, worldObject) then return true end
    end
    return false
end

local function bbms_playerIsDead(player)
    if not player then return false end
    if player.isDead then
        local ok, dead = pcall(function() return player:isDead() end)
        if ok and dead then return true end
    end
    if player.isAlive then
        local ok, alive = pcall(function() return player:isAlive() end)
        if ok and alive == false then return true end
    end
    return false
end

local function bbms_cancelFetchQuest(gmd, data, key, quest, player, reason)
    if not (data and key and quest) then return false end
    bbms_requestFetchQuestGuardCleanup(gmd, quest, "black_market_fetch_quest_" .. tostring(reason or "cancelled"))
    data.fetchQuests[key] = nil
    quest.status = "cancelled"
    quest.cancelReason = reason or "cancelled"
    quest.updatedAt = bbms_nowHours()
    bbms_removeFetchQuestMarkers(gmd, quest)
    local contact = NPCBlackMarketBridge and NPCBlackMarketBridge.GetContact and NPCBlackMarketBridge.GetContact(gmd, quest.contactId) or nil
    if contact then bbms_removeEmptyFetchQuestTurnInBox(gmd, quest, contact) end
    if player then bbms_sendFetchQuestState(player, gmd) end
    return true
end

local function bbms_createFetchQuest(gmd, player, contact)
    local data = NPCBlackMarketBridge.EnsureData(gmd)
    local key, active = bbms_activeFetchQuest(data, player)
    if active then return false, "Finish or lose your current black-market contract first." end
    if key and type(data.defenseQuests) == "table" then
        local defenseQuest = data.defenseQuests[tostring(key)]
        if type(defenseQuest) == "table" and tostring(defenseQuest.status or "active") == "active" then
            return false, "Finish your active defense contract first."
        end
    end
    if not key then return false, "Player contract id unavailable." end
    local square, x, y, z = bbms_pickDropSquare(player, contact, gmd)
    if not (square and x and y) then return false, "No suitable quest cache location found nearby." end

    local now = bbms_nowHours()
    local quest = {
        id = bbms_fetchQuestId(data),
        contactId = contact and (contact.blackMarketId or contact.id) or nil,
        playerId = key,
        playerName = bbms_playerName(player),
        side = contact and (contact.blackMarketSide or contact.sourceSide) or nil,
        turnInX = contact and tonumber(contact.x) or nil,
        turnInY = contact and tonumber(contact.y) or nil,
        turnInZ = contact and tonumber(contact.z) or 0,
        zoneRadius = bbms_fetchQuestZoneRadius(),
        status = "active",
        questType = "steal",
        x = x,
        y = y,
        z = z or 0,
        createdAt = now,
        updatedAt = now
    }

    if contact then
        bbms_removeFetchQuestBoxesNear(contact.x, contact.y, contact.z, quest, 7, nil, false)
    end

    if not bbms_createFetchQuestGuardGroup(gmd, player, quest, contact) then return false, "Quest cache guards could not be deployed." end
    if not bbms_placeFetchQuestCache(square, quest, data) then
        bbms_requestFetchQuestGuardCleanup(gmd, quest, "black_market_fetch_quest_cache_failed")
        return false, "Quest cache could not be placed."
    end
    bbms_refreshFetchQuestGuardOrders(gmd, quest)
    data.fetchQuests[key] = quest
    data.stats.fetchQuests = (tonumber(data.stats.fetchQuests) or 0) + 1
    bbms_syncFetchQuestMarker(gmd, quest, player, true)
    bbms_ensureFetchQuestTurnInBox(gmd, quest, contact)
    bbms_syncFetchQuestTurnInMarker(gmd, quest)
    bbms_sendFetchQuestState(player, gmd)
    if TransmitNPCModData then TransmitNPCModData() end
    return true, quest
end

local function bbms_completeFetchQuest(gmd, player, contact)
    local data = NPCBlackMarketBridge.EnsureData(gmd)
    local key, quest = bbms_activeFetchQuest(data, player)
    if not quest then return false, "No active black-market contract." end
    local contactId = contact and tostring(contact.blackMarketId or contact.id or "") or ""
    if contactId == "" or tostring(quest.contactId or "") ~= contactId then return false, "Return this item to the same black market contact." end

    local item, container = bbms_findFetchQuestItemInPlayer(player, quest)
    local worldObject, square, hostItem = nil, nil, nil
    if not item then
        item, container, worldObject, square, hostItem = bbms_findFetchQuestItemNearContact(contact, quest, 5)
    end
    if not item then return false, "Put the QUEST item in your inventory or in the black-market turn-in box." end

    local rewardSquare = square
    local depositedInTurnInBox = hostItem and bbms_turnInBoxCandidate(hostItem, quest) and worldObject and square
    if not rewardSquare and getCell then
        local cell = getCell()
        rewardSquare = bbms_squareAt(cell, contact.x, contact.y, contact.z or 0)
    end
    if not rewardSquare then return false, "Black-market reward box location is not available." end

    -- Build the reward package in memory first. The contract is completed only
    -- after the QUEST item/deposit box is physically removed and the reward box
    -- is placed. This avoids the previous state where a quest could close while
    -- the QUEST item still remained inside a stale turn-in container.
    local rewardBox, rewardCount = bbms_buildFetchQuestRewardBox(quest)
    if not rewardBox or rewardCount <= 0 then return false, "Black-market reward could not be prepared." end

    local removedQuestItem = false
    if depositedInTurnInBox then
        removedQuestItem = bbms_removeWorldInventoryObject(square, worldObject)
    else
        removedQuestItem = bbms_removeFetchQuestItem(item, container, player, worldObject, square)
    end
    if not removedQuestItem then return false, "Quest item could not be removed." end

    -- Remove any old turn-in/reward boxes around this market before placing the
    -- fresh reward box. For box delivery, the old deposit container was already
    -- removed above; this call cleans leftovers from older patch versions.
    bbms_removeFetchQuestBoxesNear(contact.x, contact.y, contact.z or 0, quest, 7, nil, true)

    if not bbms_placeWorldInventoryItem(rewardSquare, rewardBox) then return false, "Black-market reward box could not be placed." end

    if contact then
        contact.blackMarketHasPendingReward = true
        contact.blackMarketRewardX = rewardSquare.getX and rewardSquare:getX() or contact.x
        contact.blackMarketRewardY = rewardSquare.getY and rewardSquare:getY() or contact.y
        contact.blackMarketRewardZ = rewardSquare.getZ and rewardSquare:getZ() or (contact.z or 0)
        contact.blackMarketNextMoveAt = math.max(tonumber(contact.blackMarketNextMoveAt) or 0, bbms_nowHours() + 24)
        contact.updatedAt = bbms_nowHours()
        syncMarker(gmd, contact)
        syncContactsAll()
    end

    bbms_requestFetchQuestGuardCleanup(gmd, quest, "black_market_fetch_quest_completed")
    data.fetchQuests[key] = nil
    quest.status = "completed"
    quest.updatedAt = bbms_nowHours()
    quest.rewardItems = rewardCount
    quest.rewardBoxPlaced = true
    quest.turnInBoxPlaced = false
    bbms_removeFetchQuestMarkers(gmd, quest)
    bbms_sendFetchQuestState(player, gmd)
    if NPCDiagnosticsBridge and NPCDiagnosticsBridge.LogRiskAction then
        NPCDiagnosticsBridge.LogRiskAction("black_market", "fetch_quest_completed", {questId=quest.id, contactId=quest.contactId, item=quest.itemFullType, rewardItems=rewardCount}, "blackmarket-fetch-completed:" .. tostring(quest.id), false)
    end
    if TransmitNPCModData then TransmitNPCModData() end
    return true, "Stolen QUEST item delivered. Reward placed in the black-market reward box."
end

local function bbms_cleanupEscapedFetchQuestCache(gmd, quest)
    if not (gmd and quest) then return false end
    local drop = {
        id = quest.id,
        dropType = "quest",
        label = "QUEST CACHE",
        x = quest.originalCacheX or quest.x,
        y = quest.originalCacheY or quest.y,
        z = quest.originalCacheZ or quest.z or 0,
        materialized = true
    }
    local removed = false
    if bbms_removeEmptyDropContainer then
        local ok, got = pcall(function() return bbms_removeEmptyDropContainer(gmd, drop, true) end)
        removed = ok and got == true
    end
    if not removed then bbms_forceClientCacheRemoval(drop) end
    return true
end

local function bbms_escapeFetchQuest(gmd, player, quest)
    if not (gmd and player and quest and quest.id) then return false, "Invalid black-market contract state." end
    local item = bbms_findFetchQuestItemInPlayer(player, quest)
    if not item then return false, "QUEST item is not in player inventory." end
    local px, py = tonumber(player:getX()), tonumber(player:getY())
    if not (px and py) then return false, "Player position unavailable." end
    local cx = tonumber(quest.originalCacheX or quest.x)
    local cy = tonumber(quest.originalCacheY or quest.y)
    if not (cx and cy) then return false, "Quest cache position unavailable." end
    local radius = tonumber(quest.zoneRadius) or bbms_fetchQuestZoneRadius()
    local dx, dy = px - cx, py - cy
    if (dx * dx + dy * dy) <= (radius * radius) then return false, "Leave the guarded zone with the QUEST item first." end

    quest.carried = true
    quest.markerHidden = true
    quest.cacheEscaped = true
    quest.itemInCache = false
    quest.physical = false
    quest.materialized = false
    quest.guardsDematerialized = true
    quest.updatedAt = bbms_nowHours()
    bbms_cleanupEscapedFetchQuestCache(gmd, quest)
    bbms_requestFetchQuestGuardCleanup(gmd, quest, "black_market_fetch_quest_escaped")
    bbms_syncFetchQuestMarker(gmd, quest, player, true)
    bbms_syncFetchQuestTurnInMarker(gmd, quest)
    bbms_sendFetchQuestState(player, gmd)
    if TransmitNPCModData then TransmitNPCModData() end
    return true, "QUEST item escaped. Return it to the marked black market."
end

local function bbms_trackFetchQuest(gmd, player, args)
    local data = NPCBlackMarketBridge.EnsureData(gmd)
    local key, quest = bbms_activeFetchQuest(data, player)
    if not quest then bbms_sendFetchQuestState(player, gmd); return false end
    if tostring(args and args.questId or "") ~= tostring(quest.id or "") then return false end
    local state = tostring(args and args.state or "")
    if state == "carried" then
        quest.carried = true
        quest.markerHidden = true
        quest.updatedAt = bbms_nowHours()
        bbms_syncFetchQuestMarker(gmd, quest, player)
        bbms_syncFetchQuestTurnInMarker(gmd, quest)
        bbms_sendFetchQuestState(player, gmd)
        return true
    elseif state == "world" then
        local x = tonumber(args and args.x)
        local y = tonumber(args and args.y)
        local z = tonumber(args and args.z) or 0
        if not (x and y and player and player.getX and player.getY) then return false end
        local px, py = player:getX(), player:getY()
        local dx, dy = x - px, y - py
        if (dx * dx + dy * dy) > (40 * 40) then return false end
        quest.x = math.floor(x + 0.5)
        quest.y = math.floor(y + 0.5)
        quest.z = math.floor(z)
        quest.carried = false
        quest.markerHidden = false
        quest.updatedAt = bbms_nowHours()
        bbms_syncFetchQuestMarker(gmd, quest, player)
        bbms_syncFetchQuestTurnInMarker(gmd, quest)
        bbms_sendFetchQuestState(player, gmd)
        return true
    elseif state == "escaped" then
        local ok = bbms_escapeFetchQuest(gmd, player, quest)
        return ok == true
    elseif state == "dead" then
        return bbms_cancelFetchQuest(gmd, data, key, quest, player, "player_dead")
    end
    return false
end

function NPCBlackMarketServerBridge.FetchQuest(player, args)
    if not (NPCBlackMarketBridge and NPCBlackMarketBridge.IsEnabled()) then return end
    local action = tostring(args and args.action or "status")
    local gmd, contact = contactFor(player, args or {})
    if action == "track" then
        bbms_trackFetchQuest(gmd, player, args or {})
        return
    elseif action == "death" then
        local data = NPCBlackMarketBridge.EnsureData(gmd)
        local key, quest = bbms_activeFetchQuest(data, player)
        if quest then bbms_cancelFetchQuest(gmd, data, key, quest, player, "player_dead") else bbms_sendFetchQuestState(player, gmd) end
        return
    elseif action == "status" then
        bbms_sendFetchQuestState(player, gmd)
        return
    end

    if not contact then halo(player, "No black market service object nearby.", 255, 120, 70); return end
    if action == "take" then
        local ok, result = bbms_createFetchQuest(gmd, player, contact)
        if ok then
            local quest = result
            halo(player, "Contract accepted. Steal the guarded QUEST item and return " .. tostring(quest.itemLabel or "the item") .. ".", 235, 160, 255)
        else
            halo(player, tostring(result or "Contract unavailable."), 255, 120, 70)
            bbms_sendFetchQuestState(player, gmd)
        end
    elseif action == "turn_in" then
        local ok, result = bbms_completeFetchQuest(gmd, player, contact)
        halo(player, tostring(result or (ok and "Contract completed." or "Contract failed.")), ok and 235 or 255, ok and 160 or 120, ok and 255 or 70)
    else
        bbms_sendFetchQuestState(player, gmd)
    end
end

local function bbms_syncFetchQuestsForPlayer(gmd, player)
    if player then bbms_sendFetchQuestState(player, gmd) end
end

local function bbms_cleanupFetchQuests(gmd)
    local data = NPCBlackMarketBridge.EnsureData(gmd)
    if not (data and type(data.fetchQuests) == "table") then return 0 end
    local removed = 0
    local online = {}
    if getOnlinePlayers then
        local okPlayers, players = pcall(function() return getOnlinePlayers() end)
        if okPlayers and players and players.size and players.get then
            local okSize, size = pcall(function() return players:size() end)
            size = okSize and (tonumber(size) or 0) or 0
            for i = 0, size - 1 do
                local okPlayer, player = pcall(function() return players:get(i) end)
                if okPlayer and player then
                    local key = bbms_fetchQuestPlayerKey(player)
                    if key then online[key] = player end
                end
            end
        end
    end
    if getPlayer then
        local okPlayer, player = pcall(function() return getPlayer() end)
        if okPlayer and player then
            local key = bbms_fetchQuestPlayerKey(player)
            if key then online[key] = player end
        end
    end
    for key, quest in pairs(data.fetchQuests) do
        if type(quest) ~= "table" or quest.status ~= "active" then
            if type(quest) == "table" then bbms_requestFetchQuestGuardCleanup(gmd, quest, "black_market_fetch_quest_inactive") end
            data.fetchQuests[key] = nil
            removed = removed + 1
        else
            local player = online[tostring(key)]
            if player and bbms_playerIsDead(player) then
                if bbms_cancelFetchQuest(gmd, data, key, quest, player, "player_dead") then removed = removed + 1 end
            elseif quest.carried ~= true and quest.markerHidden ~= true then
                bbms_syncFetchQuestMarker(gmd, quest, player)
            end
            bbms_syncFetchQuestTurnInMarker(gmd, quest)
            if player then
                local contact = NPCBlackMarketBridge and NPCBlackMarketBridge.GetContact and NPCBlackMarketBridge.GetContact(gmd, quest.contactId) or nil
                if contact then
                    bbms_ensureFetchQuestTurnInBox(gmd, quest, contact)
                    bbms_syncFetchQuestTurnInMarker(gmd, quest)
                end
                local carriedItem = bbms_findFetchQuestItemInPlayer(player, quest)
                if carriedItem and (quest.carried ~= true or quest.markerHidden ~= true) then
                    quest.carried = true
                    quest.markerHidden = true
                    quest.itemInCache = false
                    quest.updatedAt = bbms_nowHours()
                    bbms_syncFetchQuestMarker(gmd, quest, player, true)
                    bbms_sendFetchQuestState(player, gmd)
                end
                if quest.cacheEscaped ~= true and quest.guardsDematerialized ~= true then
                    local escaped = bbms_escapeFetchQuest(gmd, player, quest)
                    if escaped ~= true then
                        if quest.guardGroupId and bbms_groupById(gmd, quest.guardGroupId) then
                            bbms_refreshFetchQuestGuardOrders(gmd, quest)
                        else
                            bbms_createFetchQuestGuardGroup(gmd, player, quest, nil)
                        end
                    end
                elseif quest.guardGroupId then
                    bbms_requestFetchQuestGuardCleanup(gmd, quest, "black_market_fetch_quest_escaped_cleanup")
                end
            end
        end
    end
    removed = removed + bbms_cleanupStaleFetchQuestTurnInBoxes(gmd)
    return removed
end

local function bbms_hasNonEmptyRewardBoxNearContact(contact)
    if not (contact and contact.x and contact.y) then return false end
    local contactId = tostring(contact.blackMarketId or contact.id or "")
    local probe = {id = "", contactId = contactId, turnInX = contact.x, turnInY = contact.y, turnInZ = contact.z or 0}
    local boxes = bbms_findFetchQuestBoxesNear(contact.x, contact.y, contact.z or 0, probe, 7)
    local foundLoadedReward = false
    local hasNonEmptyReward = false
    for _, box in ipairs(boxes) do
        if box.role == "reward" and box.item and box.worldObject and box.square then
            foundLoadedReward = true
            if bbms_itemInventoryEmpty(box.item, 0) then
                bbms_removeWorldInventoryObject(box.square, box.worldObject)
            else
                hasNonEmptyReward = true
            end
        end
    end
    if hasNonEmptyReward then
        contact.blackMarketHasPendingReward = true
        return true
    end
    if foundLoadedReward or contact.blackMarketHasPendingReward == true then
        local cell = getCell and getCell() or nil
        local square = cell and bbms_squareAt(cell, contact.x, contact.y, contact.z or 0) or nil
        if square then
            contact.blackMarketHasPendingReward = false
            contact.blackMarketRewardX = nil
            contact.blackMarketRewardY = nil
            contact.blackMarketRewardZ = nil
            contact.updatedAt = bbms_nowHours()
            local gmd = GetNPCModData and GetNPCModData() or nil
            if gmd then syncMarker(gmd, contact) end
            syncContactsAll()
        end
    end
    return contact.blackMarketHasPendingReward == true
end

local function bbms_materializeRadius()
    return bbms_num("BlackMarket_StaticDrawRadius", 70, 8, 180)
end

local function bbms_virtualHomeRadius()
    return bbms_num("BlackMarket_VirtualHomeRadius", 900, 80, 3000)
end

local function bbms_virtualStepRadius()
    return bbms_num("BlackMarket_VirtualStepRadius", 28, 6, 120)
end

local function bbms_virtualMoveHours()
    return bbms_num("BlackMarket_VirtualMoveMinutes", 8, 2, 120) / 60
end

local function bbms_anyPlayerNear(x, y, radius)
    local players = getOnlinePlayers and getOnlinePlayers() or nil
    if not (players and players.size and players.get) then return false end
    local okSize, count = pcall(function() return players:size() end)
    if not okSize then return false end
    for i = 0, (tonumber(count) or 0) - 1 do
        local okGet, player = pcall(function() return players:get(i) end)
        if okGet and player and player.getX and player.getY then
            local okPos, px, py = pcall(function() return player:getX(), player:getY() end)
            if okPos and bbms_dist(x, y, px, py) <= radius then return true end
        end
    end
    return false
end

local function bbms_normalizeVirtualContact(contact)
    if type(contact) ~= "table" then return end
    contact.blackMarketStaticObject = true
    contact.blackMarketVirtualObject = true
    if contact.blackMarketHomeX == nil then contact.blackMarketHomeX = math.floor(tonumber(contact.x) or 0) end
    if contact.blackMarketHomeY == nil then contact.blackMarketHomeY = math.floor(tonumber(contact.y) or 0) end
    if contact.blackMarketHomeZ == nil then contact.blackMarketHomeZ = tonumber(contact.z) or 0 end
    if contact.blackMarketHomeRadius == nil then contact.blackMarketHomeRadius = bbms_virtualHomeRadius() end
    if contact.blackMarketNextMoveAt == nil then contact.blackMarketNextMoveAt = bbms_nowHours() + bbms_virtualMoveHours() end
end

local function bbms_inHome(contact, x, y)
    local radius = tonumber(contact.blackMarketHomeRadius) or bbms_virtualHomeRadius()
    return bbms_dist(contact.blackMarketHomeX or contact.x, contact.blackMarketHomeY or contact.y, x, y) <= radius
end

local function bbms_pickVirtualTarget(contact)
    local hx = tonumber(contact.blackMarketHomeX) or tonumber(contact.x) or 0
    local hy = tonumber(contact.blackMarketHomeY) or tonumber(contact.y) or 0
    local radius = tonumber(contact.blackMarketHomeRadius) or bbms_virtualHomeRadius()
    local target = nil

    if NPCRoadNavBridge and NPCRoadNavBridge.FindNearbyWorldRoadPoint then
        local ok, got = pcall(function() return NPCRoadNavBridge.FindNearbyWorldRoadPoint(hx, hy, radius, 120) end)
        if ok and got and got.x and got.y and bbms_inHome(contact, got.x, got.y) then target = got end
    end

    if not target then
        for _ = 1, 24 do
            local tx = hx + bbms_rand(-radius, radius + 1)
            local ty = hy + bbms_rand(-radius, radius + 1)
            if bbms_inHome(contact, tx, ty) then
                target = {x = tx, y = ty, z = tonumber(contact.blackMarketHomeZ) or tonumber(contact.z) or 0}
                break
            end
        end
    end

    if target then
        contact.blackMarketTargetX = math.floor(tonumber(target.x) or hx)
        contact.blackMarketTargetY = math.floor(tonumber(target.y) or hy)
        contact.blackMarketTargetZ = tonumber(target.z) or tonumber(contact.blackMarketHomeZ) or tonumber(contact.z) or 0
    end
end

local function bbms_stepToward(contact)
    local x = tonumber(contact.x) or tonumber(contact.blackMarketHomeX) or 0
    local y = tonumber(contact.y) or tonumber(contact.blackMarketHomeY) or 0
    local z = tonumber(contact.z) or tonumber(contact.blackMarketHomeZ) or 0
    local tx = tonumber(contact.blackMarketTargetX)
    local ty = tonumber(contact.blackMarketTargetY)
    if not tx or not ty or bbms_dist(x, y, tx, ty) < 4 then
        bbms_pickVirtualTarget(contact)
        tx = tonumber(contact.blackMarketTargetX)
        ty = tonumber(contact.blackMarketTargetY)
    end
    if not tx or not ty then return false end

    local candidate = nil
    local stepRadius = bbms_virtualStepRadius()
    if NPCRoadNavBridge and NPCRoadNavBridge.FindNearbyWorldRoadStepToward then
        local ok, got = pcall(function() return NPCRoadNavBridge.FindNearbyWorldRoadStepToward(x, y, tx, ty, stepRadius, 80) end)
        if ok and got and got.x and got.y then candidate = got end
    end

    if not candidate then
        local dx = tx - x
        local dy = ty - y
        local len = math.sqrt(dx * dx + dy * dy)
        if len < 1 then return false end
        local step = math.min(stepRadius, len)
        candidate = {x = x + (dx / len) * step, y = y + (dy / len) * step, z = z}
    end

    local nx = math.floor((tonumber(candidate.x) or x) + 0.5)
    local ny = math.floor((tonumber(candidate.y) or y) + 0.5)
    local nz = tonumber(candidate.z) or z
    if not bbms_inHome(contact, nx, ny) then
        bbms_pickVirtualTarget(contact)
        return false
    end
    if bbms_anyPlayerNear(nx, ny, bbms_materializeRadius()) then
        return false
    end

    if nx == math.floor(x) and ny == math.floor(y) then return false end
    contact.x = nx
    contact.y = ny
    contact.z = nz
    contact.blackMarketVirtual = true
    contact.blackMarketMaterialized = false
    contact.blackMarketLastVirtualMoveAt = bbms_nowHours()
    contact.updatedAt = contact.blackMarketLastVirtualMoveAt
    return true
end

local function updateVirtualContacts(gmd)
    local d = NPCBlackMarketBridge.EnsureData(gmd)
    if not (d and type(d.contacts) == "table") then return 0 end
    local changed = 0
    local now = bbms_nowHours()
    local holdRadius = bbms_materializeRadius()
    for _, contact in pairs(d.contacts or {}) do
        if type(contact) == "table" and contact.blackMarketStatus ~= "closed" then
            bbms_normalizeVirtualContact(contact)
            local pendingReward = bbms_hasNonEmptyRewardBoxNearContact(contact)
            local visible = bbms_anyPlayerNear(contact.x, contact.y, holdRadius)
            if visible then
                if contact.blackMarketVirtual ~= false or contact.blackMarketMaterialized ~= true then changed = changed + 1 end
                contact.blackMarketVirtual = false
                contact.blackMarketMaterialized = true
                contact.blackMarketNextMoveAt = now + bbms_virtualMoveHours()
            else
                if contact.blackMarketVirtual ~= true or contact.blackMarketMaterialized ~= false then changed = changed + 1 end
                contact.blackMarketVirtual = true
                contact.blackMarketMaterialized = false
                if pendingReward == true then
                    -- A non-empty reward box pins the market position but not the
                    -- expensive materialized NPC/contact state. The box and marker
                    -- remain; teleport/chunk loading no longer has to keep the
                    -- black market fully active just because loot is waiting.
                    contact.blackMarketNextMoveAt = now + bbms_virtualMoveHours()
                elseif now >= (tonumber(contact.blackMarketNextMoveAt) or 0) then
                    if bbms_stepToward(contact) then changed = changed + 1 end
                    contact.blackMarketNextMoveAt = now + bbms_virtualMoveHours()
                end
            end
        end
    end
    return changed
end

local function safeZombieId(zombie)
    if not zombie then return nil end
    if zombie.getOnlineID then
        local ok, id = pcall(function() return zombie:getOnlineID() end)
        if ok and id ~= nil then return id end
    end
    if zombie.getID then
        local ok, id = pcall(function() return zombie:getID() end)
        if ok and id ~= nil then return id end
    end
    return nil
end

local function safeVar(zombie, name)
    if not (zombie and zombie.getVariableString) then return nil end
    local ok, value = pcall(function() return zombie:getVariableString(name) end)
    if ok and value and value ~= "" then return tostring(value) end
    return nil
end

local function brainMarksBlackMarket(brain)
    if type(brain) ~= "table" then return false end
    if brain.blackMarket == true or brain.blackMarketNPC == true or brain.blackMarketService == true or brain.special == "BlackMarket" then return true end
    if brain.blackMarketContact == true or brain.blackMarketContactId ~= nil then return true end
    if type(brain.program) == "table" and (brain.program.name == "BlackMarket" or brain.program.name == "BlackMarketPrepare") then return true end
    if tostring(brain.factionState or "") == "black_market_service" then return true end
    if tostring(brain.factionSide or "") == "black_market" or tostring(brain.factionSide or "") == "black_market_service" then return true end
    return false
end

local function zombieMarksBlackMarket(gmd, zombie)
    if not zombie then return false end
    local md = zombie.getModData and zombie:getModData() or nil
    if type(md) == "table" then
        if md.NPCBlackMarketBridge == true or md.BlackMarketNPC == true or md.BlackMarketService == true then return true end
        if md.BlackMarketId ~= nil or md.blackMarketId ~= nil or md.blackMarketContactId ~= nil then return true end
    end
    if safeVar(zombie, NPCLegacyContractBridge.Keys.BLACK_MARKET) == "true" then return true end
    if safeVar(zombie, "BlackMarketId") ~= nil then return true end
    local brain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(zombie) or nil
    if brainMarksBlackMarket(brain) then return true end
    local zid = safeZombieId(zombie)
    if gmd and zid and type(gmd.Queue) == "table" then
        brain = gmd.Queue[zid] or gmd.Queue[tostring(zid)] or (tonumber(zid) and gmd.Queue[tonumber(zid)])
        if brainMarksBlackMarket(brain) then return true end
    end
    return false
end

local function removeZombieObject(zombie)
    if not zombie then return false end
    if NPCBrainData and NPCBrainData.Remove then pcall(function() NPCBrainData.Remove(zombie) end) end
    pcall(function() zombie:setVariable(NPCLegacyContractBridge.Key("BLACK_MARKET"), false) end)
    pcall(function() zombie:setVariable("BlackMarketId", "") end)
    pcall(function() zombie:setVariable(NPCLegacyContractBridge.Key("FLAG"), false) end)
    pcall(function() zombie:setVariable(NPCLegacyContractBridge.Key("PRIMARY"), "") end)
    pcall(function() zombie:setVariable(NPCLegacyContractBridge.Key("SECONDARY"), "") end)
    pcall(function() zombie:clearAttachedItems() end)
    pcall(function() zombie:removeFromWorld() end)
    pcall(function() zombie:removeFromSquare() end)
    return true
end

local function cleanupLegacyBlackMarketNPCs(gmd)
    local removed = 0
    if gmd and type(gmd.Queue) == "table" then
        for id, brain in pairs(gmd.Queue) do
            if brainMarksBlackMarket(brain) then
                gmd.Queue[id] = nil
                removed = removed + 1
                removeMarker(gmd, tostring(id))
            end
        end
    end
    local cell = getCell and getCell() or nil
    local list = cell and cell.getZombieList and cell:getZombieList() or nil
    if list and list.size and list.get then
        local size = 0
        local okSize, gotSize = pcall(function() return list:size() end)
        if okSize then size = tonumber(gotSize) or 0 end
        for i = size - 1, 0, -1 do
            local okGet, zombie = pcall(function() return list:get(i) end)
            if okGet and zombie and zombieMarksBlackMarket(gmd, zombie) then
                local id = safeZombieId(zombie)
                if id and gmd and gmd.Queue then
                    gmd.Queue[id] = nil
                    gmd.Queue[tostring(id)] = nil
                    if tonumber(id) then gmd.Queue[tonumber(id)] = nil end
                end
                if removeZombieObject(zombie) then removed = removed + 1 end
                if id then
                    sendServerCommand('NPCCommands', NPCLegacyContractBridge.Commands.REMOVE_OBJECTS, {ids={id}, runtimeCleanup=true, blackMarketStaticCleanup=true})
                    removeMarker(gmd, tostring(id))
                end
            end
        end
    end
    return removed
end

contactFor = function(p,args)
    local gmd=GetNPCModData()
    local x=p and p.getX and p:getX() or 0
    local y=p and p.getY and p:getY() or 0
    local radius=NPCBlackMarketBridge.StaticPlayerRadius and NPCBlackMarketBridge.StaticPlayerRadius() or 8
    local c=NPCBlackMarketBridge.GetContact(gmd,args and args.contactId)
    if c then
        local dx=(tonumber(c.x) or 0)-(tonumber(x) or 0)
        local dy=(tonumber(c.y) or 0)-(tonumber(y) or 0)
        if math.sqrt(dx*dx+dy*dy)<=radius+2 then return gmd,c end
        return gmd,nil
    end
    return gmd, NPCBlackMarketBridge.NearestContact(gmd,x,y,radius)
end

local function paymentForDeal(p,args,action)
    local res,amt=NPCBlackMarketBridge.DealCost(action)
    if not res then return nil,false,"Unknown deal." end
    amt = math.floor(tonumber(amt) or 0)
    if amt<=0 then return bbms_paymentReceipt(res,0,false),true,"free" end
    local serverCount = NPCBlackMarketBridge.CountItems(p,res)
    if serverCount >= amt then return bbms_paymentReceipt(res,amt,bbms_clientPaymentOk(args,res,amt)),true,"paid" end
    if bbms_clientPaymentOk(args,res,amt) then return bbms_paymentReceipt(res,amt,true),true,"paid" end

    -- Black-market fallback: gold is accepted for silver-priced service packs
    -- when the player has no server-visible silver. This prevents false
    -- negatives in MP and gives high-value currency a sensible use.
    if res == "silver" then
        local goldCost = math.max(1, math.ceil(amt / 2))
        local goldCount = NPCBlackMarketBridge.CountItems(p,"gold")
        if goldCount >= goldCost then return bbms_paymentReceipt("gold",goldCost,bbms_clientPaymentOk(args,"gold",goldCost)),true,"paid" end
        if bbms_clientPaymentOk(args,"gold",goldCost) then return bbms_paymentReceipt("gold",goldCost,true),true,"paid" end
    end

    return bbms_paymentReceipt(res,amt,false),false,"Need "..NPCBlackMarketBridge.PriceText(action).."."
end

local function finalizePayment(p, receipt, action)
    if not (type(receipt) == "table") then return true end
    local res = receipt.resource
    local amt = math.floor(tonumber(receipt.amount) or 0)
    if amt <= 0 then return true end
    if NPCBlackMarketBridge.TakeItems(p,res,amt) then return true end
    if receipt.takeClientPayment == true then
        bbms_sendClientPaymentRemoval(p, receipt, action)
        return true
    end
    return false
end

local function payoff(gmd,p,side)
    if not (NPCBountyBridge and NPCBountyBridge.GetSideRecord and NPCBountyBridge.Add) then return false,"Bounty unavailable." end
    side=NPCBlackMarketBridge.NormalizeSide(side)
    local rec=NPCBountyBridge.GetSideRecord(gmd,p,side)
    if not rec or (tonumber(rec.value) or 0)<=0 then return false,"No active bounty with "..NPCBlackMarketBridge.SideLabel(side).."." end
    local before=tonumber(rec.value) or 0
    NPCBountyBridge.Add(gmd,p,side,-NPCBlackMarketBridge.BountyReduction(),"black_market_payoff")
    local afterRec=NPCBountyBridge.GetSideRecord(gmd,p,side)
    local after=afterRec and (tonumber(afterRec.value) or 0) or 0
    if after<=0.5 then
        removeMarker(gmd,"bounty_"..tostring(NPCBountyBridge.PlayerId(p)).."_"..tostring(side))
    elseif NPCBountyBridge.MakeBountyMarker then
        local pr=NPCBountyBridge.GetPlayerRecord(gmd,p)
        local m=NPCBountyBridge.MakeBountyMarker(pr,side,afterRec)
        if m then setMarker(gmd,m) end
    end
    if NPCWorldRulesServer and NPCWorldRulesServer.SyncAfterConsequence then
        NPCWorldRulesServer.SyncAfterConsequence(p,"black_market_bounty_payoff",{side=side,before=before,after=after})
    elseif NPCBountyServer and NPCBountyServer.SyncPlayer then
        NPCBountyServer.SyncPlayer(p)
    end
    return true,"Bounty reduced for "..NPCBlackMarketBridge.SideLabel(side)..": "..tostring(math.floor(before+0.5)).." -> "..tostring(math.floor(after+0.5)).."."
end

local function leaderTip(gmd,p,side)
    if not (gmd and gmd.NPCLeadersBridge and type(gmd.NPCLeadersBridge.leaders)=="table") then return false,"No leader rumors." end
    side=NPCBlackMarketBridge.NormalizeSide(side)
    for _,l in pairs(gmd.NPCLeadersBridge.leaders) do
        if type(l)=="table" and l.state~="dead" and NPCBlackMarketBridge.NormalizeSide(l.side)==side then
            local m=nil
            if NPCLeadersBridge and NPCLeadersBridge.MakeLeaderMarker then m=NPCLeadersBridge.MakeLeaderMarker(l) end
            if not m then m = {} end
            m.id = "black_market_leader_intel_" .. tostring(side or "side") .. "_" .. tostring(l.id or l.leaderId or l.groupId or math.floor(tonumber(l.x) or 0) .. "_" .. math.floor(tonumber(l.y) or 0))
            m.markerType = "leader"
            m.blackMarketLeaderIntel = true
            m.blackMarketPurchasedIntel = true
            m.highContrastMapMarker = true
            m.displayName = "BOUGHT LEADER INTEL"
            m.label = "BOUGHT LEADER INTEL"
            m.name = tostring(l.name or l.id or "Faction leader")
            m.side = side
            m.factionSide = side
            m.leaderState = tostring(l.state or "active")
            m.state = tostring(l.state or "active")
            m.dead = false
            m.stale = false
            m.lastSeen = false
            m.x = tonumber(l.x) or tonumber(l.preciseX) or 0
            m.y = tonumber(l.y) or tonumber(l.preciseY) or 0
            m.z = tonumber(l.z) or 0
            m.preciseX = tonumber(l.x) or tonumber(l.preciseX) or m.x
            m.preciseY = tonumber(l.y) or tonumber(l.preciseY) or m.y
            m.updatedAt = bbms_nowHours()
            setMarker(gmd,m)
            if p then
                sendServerCommand(p,'NPCBlackMarket','LeaderIntel',{marker=m})
            end
            return true,"Leader rumor: "..tostring(l.name or l.id).." near "..tostring(math.floor(tonumber(m.x) or 0))..","..tostring(math.floor(tonumber(m.y) or 0))..". Marker added to the global map."
        end
    end
    return false,"No living leader contact for "..NPCBlackMarketBridge.SideLabel(side).."."
end

local function grantFallbackBlackMarketNote(p, title, body)
    if not (p and p.getInventory) then return nil end
    local okInv, inv = pcall(function() return p:getInventory() end)
    if not (okInv and inv and inv.AddItem) then return nil end
    local item = nil
    local okAdd, got = pcall(function() return inv:AddItem("Base.SheetPaper2") end)
    if okAdd and got then item = got end
    if not item then
        okAdd, got = pcall(function() return inv:AddItem("Base.SheetPaper") end)
        if okAdd and got then item = got end
    end
    if not item then return nil end
    if item.setName then pcall(function() item:setName(tostring(title or "Black market note")) end) end
    if item.getModData then
        local okMd, md = pcall(function() return item:getModData() end)
        if okMd and type(md) == "table" then
            md.blackMarket = true
            md.blackMarketDocument = true
            md.blackMarketTitle = tostring(title or "Black market note")
            md.blackMarketText = tostring(body or "")
            if item.transmitModData then pcall(function() item:transmitModData() end) end
        end
    end
    return { label = title, item = item }
end

local function bbms_passwordText(side)
    local seed = tostring(side or "bm") .. tostring(math.floor(bbms_nowHours() or 0))
    local acc = 0
    for i = 1, #seed do acc = (acc + string.byte(seed, i) * i) % 9999 end
    return "BM-" .. tostring(1000 + acc)
end

function NPCBlackMarketServerBridge.Deal(p,args)
    if not (NPCBlackMarketBridge and NPCBlackMarketBridge.IsEnabled()) then return end
    local action=tostring(args and args.action or "")
    local side=NPCBlackMarketBridge.NormalizeSide(args and args.side)
    local gmd,c=contactFor(p,args or {})
    if not c then halo(p,"No black market service object nearby.",255,120,70); return end
    side=side or c.blackMarketSide or c.sourceSide
    local isDeadDropDeal = NPCBlackMarketBridge.IsDeadDropDeal and NPCBlackMarketBridge.IsDeadDropDeal(action)
    local isIntelSaleDeal = action == "sell_intel"
    local ok,msg = true,nil
    local paymentReceipt = nil
    if not isIntelSaleDeal then
        paymentReceipt,ok,msg=paymentForDeal(p,args or {},action)
        if not ok then halo(p,msg,255,120,70); return end
    end
    local success=false
    local drop=nil
    if isDeadDropDeal then
        success,drop=bbms_createDeadDrop(gmd,p,c,action,side,args or {})
        if success then
            if not finalizePayment(p, paymentReceipt, action) then
                success=false
                msg="Payment failed."
            else
                local delivery = (drop.inventoryFallback == true or drop.deliveryMode == "player_inventory_fallback") and " Package was delivered to your inventory as a fallback." or " Package was placed nearby; look for the BLACK MARKET DROP marker."
                msg="Dead drop ordered: "..tostring(drop.label or NPCBlackMarketBridge.DealLabel(action)).." near "..tostring(math.floor(tonumber(drop.x) or 0))..","..tostring(math.floor(tonumber(drop.y) or 0)).."."..delivery
                if drop.compromised then msg=msg.." The signal feels compromised." end
                if NPCDiagnosticsBridge and NPCDiagnosticsBridge.LogRiskAction then
                    NPCDiagnosticsBridge.LogRiskAction("black_market", "dead_drop_ordered", {action=action, dropId=drop.id, compromised=drop.compromised, x=drop.x, y=drop.y, inventoryFallback=drop.inventoryFallback == true, clientPayment=(paymentReceipt and paymentReceipt.takeClientPayment == true)}, "blackmarket-drop:" .. tostring(drop.id or action), true)
                end
            end
        else
            msg=tostring(drop or "Dead drop failed.")
            if NPCDiagnosticsBridge and NPCDiagnosticsBridge.LogRiskAction then
                NPCDiagnosticsBridge.LogRiskAction("black_market", "dead_drop_failed", {action=action, reason=msg}, "blackmarket-drop-failed:" .. tostring(action), true)
            end
        end
    elseif isIntelSaleDeal then
        if NPCIntelDossierBridge and NPCIntelDossierBridge.SellToBlackMarket then
            success,msg=NPCIntelDossierBridge.SellToBlackMarket(gmd,p,c,side)
        else
            success=false
            msg="Intelligence trade unavailable."
        end
    elseif action=="forged_papers" or action=="stolen_badge" then
        if NPCFactionDocsBridge and NPCFactionDocsBridge.GrantDocument then
            pcall(function() NPCFactionDocsBridge.GrantDocument(gmd,p,side,action,"black_market") end)
        end
        local label = action == "stolen_badge" and "Stolen faction badge" or "Forged faction papers"
        local dropType = action == "stolen_badge" and "badge" or "documents"
        local body = "Black market " .. tostring(label) .. " for " .. tostring(NPCBlackMarketBridge.SideLabel(side)) .. ". Present this as a purchased underworld credential."
        success,drop = bbms_createServiceDrop(gmd,p,c,action,side,dropType,label,label,body)
        msg=success and (tostring(label).." package ordered near "..tostring(math.floor(tonumber(drop.x) or 0))..","..tostring(math.floor(tonumber(drop.y) or 0))..". Look for the BLACK MARKET DROP marker.") or tostring(drop or "Document deal failed.")
        if success and drop and drop.inventoryFallback then msg = tostring(label).." was delivered to your inventory as a fallback." end
        if success and NPCWorldRules and NPCWorldRules.IsBountyActive and NPCWorldRules.IsBountyActive(gmd,p,side,NPCWorldRules.GetBountyThresholdForCheckpoint()) then msg=msg.." Warning: active bounty can still block checkpoints." end
    elseif action=="password" then
        local pass=nil
        if NPCFactionDocsBridge and NPCFactionDocsBridge.GrantPassword then
            local okPass, gotPass = pcall(function() return NPCFactionDocsBridge.GrantPassword(gmd,p,side,"black_market") end)
            if okPass then pass = gotPass end
        end
        if not pass then pass = { password = bbms_passwordText(side), label = "Daily password" } end
        local passwordText = tostring(pass and pass.password or bbms_passwordText(side))
        local label = "Black market password"
        local body = "Password for " .. tostring(NPCBlackMarketBridge.SideLabel(side)) .. ": " .. passwordText
        success,drop = bbms_createServiceDrop(gmd,p,c,action,side,"password",label,label,body)
        msg=success and ("Password package ordered near "..tostring(math.floor(tonumber(drop.x) or 0))..","..tostring(math.floor(tonumber(drop.y) or 0))..". Look for the PASSWORD DROP marker.") or tostring(drop or "Password deal failed.")
        if success and drop and drop.inventoryFallback then msg = "Password note was delivered to your inventory as a fallback: "..passwordText.."." end
        if success and NPCWorldRules and NPCWorldRules.IsBountyActive and NPCWorldRules.IsBountyActive(gmd,p,side,NPCWorldRules.GetBountyThresholdForCheckpoint()) then msg=msg.." Warning: active bounty can still block checkpoints." end
    elseif action=="bounty_payoff" then
        success,msg=payoff(gmd,p,side)
    elseif action=="leader_tip" then
        success,msg=leaderTip(gmd,p,side)
    else
        msg="Unknown black market deal."
    end
    if success and not isIntelSaleDeal and not isDeadDropDeal then
        if not finalizePayment(p, paymentReceipt, action) then
            success = false
            msg = "Payment failed."
        end
    end
    local heatWanted = nil
    if success and NPCHeatWantedBridge and NPCHeatWantedBridge.ReportBlackMarketDeal then
        heatWanted = NPCHeatWantedBridge.ReportBlackMarketDeal(gmd, p, action, side, true, {contactId=c and (c.blackMarketId or c.id), compromised=(drop and drop.compromised == true)})
        if heatWanted and NPCHeatWantedServerBridge and NPCHeatWantedServerBridge.AfterHeatChanged then
            NPCHeatWantedServerBridge.AfterHeatChanged(p, heatWanted)
        end
        if heatWanted and heatWanted.levelChanged and heatWanted.level > heatWanted.oldLevel then msg = tostring(msg or "") .. " Wanted heat L" .. tostring(heatWanted.level) .. "." end
    end
    if NPCDiagnosticsBridge and NPCDiagnosticsBridge.LogRiskAction then
        NPCDiagnosticsBridge.LogRiskAction("black_market", "deal", {action=action, side=side, success=success, contactId=c and c.id}, "blackmarket-deal:" .. tostring(action) .. ":" .. tostring(success), success ~= true)
    end
    NPCBlackMarketBridge.RecordTrade(gmd,p,c,action,side,success and "success" or "failed")
    c.updatedAt=getGameTime and getGameTime():getWorldAgeHours() or c.updatedAt
    syncMarker(gmd,c)
    halo(p,msg, success and 190 or 255, success and 230 or 130, success and 120 or 80)
    syncContacts(p)
    if success and action~="bounty_payoff" and NPCWorldRulesServer and NPCWorldRulesServer.SyncAfterConsequence then
        NPCWorldRulesServer.SyncAfterConsequence(p,"black_market_"..tostring(action),{side=side})
    end
    if TransmitNPCModData then TransmitNPCModData() end
end

function NPCBlackMarketServerBridge.Status(p)
    local gmd=GetNPCModData()
    cleanupLegacyBlackMarketNPCs(gmd)
    bbms_cleanupDeadDrops(gmd)
    NPCBlackMarketBridge.EnsureContacts(gmd)
    if NPCBlackMarketBridge.RebalanceContacts then NPCBlackMarketBridge.RebalanceContacts(gmd, 2) end
    updateVirtualContacts(gmd)
    halo(p,NPCBlackMarketBridge.StatusText(gmd,p),230,220,150)
    syncContacts(p)
    bbms_syncFetchQuestsForPlayer(gmd, p)
end

function NPCBlackMarketServerBridge.Refresh(p)
    local gmd=GetNPCModData()
    cleanupLegacyBlackMarketNPCs(gmd)
    NPCBlackMarketBridge.EnsureContacts(gmd)
    if NPCBlackMarketBridge.RebalanceContacts then NPCBlackMarketBridge.RebalanceContacts(gmd, 2) end
    updateVirtualContacts(gmd)
    local d=NPCBlackMarketBridge.EnsureData(gmd)
    for _,c in pairs(d.contacts or {}) do syncMarker(gmd,c) end
    for _,drop in pairs(d.deadDrops or {}) do bbms_syncDrop(gmd,drop) end
    bbms_cleanupFetchQuests(gmd)
    syncContacts(p)
    bbms_syncFetchQuestsForPlayer(gmd, p)
    if TransmitNPCModData then TransmitNPCModData() end
end

function NPCBlackMarketServerBridge.OnClientCommand(module,command,p,args)
    if not (NPCLegacyContractBridge and NPCLegacyContractBridge.IsModule and NPCLegacyContractBridge.IsModule(module, 'NPCBlackMarket', 'blackMarket')) then return end
    if command=='Deal' then NPCBlackMarketServerBridge.Deal(p,args or {})
    elseif command=='Status' then NPCBlackMarketServerBridge.Status(p)
    elseif command=='Refresh' then NPCBlackMarketServerBridge.Refresh(p)
    elseif command=='FetchQuest' then NPCBlackMarketServerBridge.FetchQuest(p,args or {})
    elseif command=='DropEmptied' then bbms_confirmEmptyDirectCache(GetNPCModData(), p, args or {})
    elseif command=='NPCDead' then return end
end

local function everyTen()
    if not (NPCBlackMarketBridge and NPCBlackMarketBridge.IsEnabled()) then return end
    local gmd=GetNPCModData()
    local removed=NPCBlackMarketBridge.Cleanup(gmd)
    removed = (tonumber(removed) or 0) + cleanupLegacyBlackMarketNPCs(gmd) + bbms_cleanupDeadDrops(gmd) + bbms_cleanupFetchQuests(gmd)
    NPCBlackMarketBridge.EnsureContacts(gmd)
    local rebalanced = NPCBlackMarketBridge.RebalanceContacts and NPCBlackMarketBridge.RebalanceContacts(gmd, 2) or 0
    local moved = updateVirtualContacts(gmd)
    local d=NPCBlackMarketBridge.EnsureData(gmd)
    for _,c in pairs(d.contacts or {}) do syncMarker(gmd,c) end
    for _,drop in pairs(d.deadDrops or {}) do bbms_syncDrop(gmd,drop) end
    bbms_cleanupFetchQuests(gmd)
    syncContactsAll()
    if ((tonumber(removed) or 0) > 0 or (tonumber(moved) or 0) > 0 or (tonumber(rebalanced) or 0) > 0) and TransmitNPCModData then TransmitNPCModData() end
end

local cleanupTick = 0
local cleanupBackoffTicks = 900
local function onTick()
    cleanupTick = cleanupTick + 1
    local gmd = GetNPCModData()
    if cleanupTick % 60 == 0 then
        bbms_cleanupDeadDrops(gmd)
        bbms_cleanupFetchQuests(gmd)
    end
    if cleanupTick % cleanupBackoffTicks ~= 0 then return end
    local removed = cleanupLegacyBlackMarketNPCs(gmd)
    if (tonumber(removed) or 0) > 0 then
        cleanupBackoffTicks = 900
    elseif cleanupBackoffTicks < 3600 then
        cleanupBackoffTicks = 3600
    end
end

function NPCBlackMarketServerBridge.Install()
    if NPCBlackMarketServerBridge.__installed then return end
    NPCBlackMarketServerBridge.__installed = true
    Events.OnClientCommand.Add(NPCBlackMarketServerBridge.OnClientCommand)
    Events.EveryTenMinutes.Add(everyTen)
    Events.OnTick.Add(onTick)
end
