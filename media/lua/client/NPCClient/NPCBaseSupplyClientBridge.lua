-- NPCBaseSupplyClientBridge.lua
-- Inventory action + HUD/map overlay for player-donated base supplies.

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCLegacyGlobalsBridge"
NPCBaseSupplyClientBridge = NPCBaseSupplyClientBridge or {}
NPCBaseSupplyClientBridge.Enabled = true
NPCBaseSupplyClientBridge.MaxItemsPerDonation = 80
NPCBaseSupplyClientBridge.bases = NPCBaseSupplyClientBridge.bases or {}
NPCBaseSupplyClientBridge._patchedPanel = NPCBaseSupplyClientBridge._patchedPanel or false
NPCBaseSupplyClientBridge._hookedWorldMap = NPCBaseSupplyClientBridge._hookedWorldMap or false
NPCBaseSupplyClientBridge._hookedMiniMapInner = NPCBaseSupplyClientBridge._hookedMiniMapInner or false
NPCBaseSupplyClientBridge._hookedMiniMapOuter = NPCBaseSupplyClientBridge._hookedMiniMapOuter or false
NPCBaseSupplyClientBridge._syncRequested = NPCBaseSupplyClientBridge._syncRequested or false

local NPC_BASE_SUPPLY_CLIENT_LEGACY_TEXT_PREFIX = NPCLegacyContractBridge.Text.prefix

local function bbsc_text(key)
    return getText(NPC_BASE_SUPPLY_CLIENT_LEGACY_TEXT_PREFIX .. tostring(key or ""))
end

local function bbsc_baseCaptureProvider()
    return NPCBaseCaptureUIBridge or NPCBaseCaptureUI or NPCLegacyGlobalsBridge.Get("BaseCaptureUI")
end

local function bbsc_baseCapturePanelProvider()
    return NPCBaseCapturePanelBridge or NPCBaseCapturePanel or NPCLegacyGlobalsBridge.Get("BaseCapturePanel")
end

local function bbsc_lower(value)
    if not value then return "" end
    return string.lower(tostring(value))
end

local function bbsc_safe(item, method)
    if not item or not item[method] then return nil end
    local ok, value = pcall(function() return item[method](item) end)
    if ok then return value end
    return nil
end

local function bbsc_fullType(item)
    return bbsc_safe(item, "getFullType") or bbsc_safe(item, "getType") or tostring(item)
end

local function bbsc_protection(item)
    local total = 0
    for _, method in ipairs({"getBiteDefense", "getScratchDefense", "getBulletDefense", "getNeckProtectionModifier"}) do
        total = total + (tonumber(bbsc_safe(item, method)) or 0)
    end
    return total
end

local function bbsc_boolMethod(item, method)
    local ok, value = pcall(function()
        if item and item[method] then return item[method](item) end
        return false
    end)
    return ok and value == true
end

local function bbsc_stringValue(value)
    if value == nil then return nil end
    local t = type(value)
    if t == "string" or t == "number" or t == "boolean" then return tostring(value) end
    local ok, text = pcall(function() return tostring(value) end)
    if ok then return text end
    return nil
end

local function bbsc_mountOnText(item)
    local mount = bbsc_safe(item, "getMountOn")
    return bbsc_stringValue(mount)
end

local function bbsc_weaponPartInfo(part)
    if not part then return nil end
    local fullType = bbsc_fullType(part)
    if not fullType or fullType == "" then return nil end
    return {
        fullType = fullType,
        type = tostring(bbsc_safe(part, "getType") or ""),
        name = tostring(bbsc_safe(part, "getDisplayName") or fullType),
        category = tostring(bbsc_safe(part, "getCategory") or ""),
        displayCategory = tostring(bbsc_safe(part, "getDisplayCategory") or ""),
        resource = "weaponParts",
        isWeaponPart = true,
        partType = bbsc_safe(part, "getPartType"),
        mountOn = bbsc_mountOnText(part),
        condition = tonumber(bbsc_safe(part, "getCondition")) or 0,
        maxCondition = tonumber(bbsc_safe(part, "getConditionMax")) or 0,
        count = 1,
        baseAmount = 1
    }
end

local function bbsc_collectWeaponAttachments(item)
    local attachments = {}
    for _, method in ipairs({"getScope", "getClip", "getSling", "getStock", "getCanon", "getRecoilpad"}) do
        local part = bbsc_safe(item, method)
        local info = bbsc_weaponPartInfo(part)
        if info then table.insert(attachments, info) end
    end
    return attachments
end

local function bbsc_isRanged(item)
    if bbsc_boolMethod(item, "isRanged") then return true end
    local ft = bbsc_lower(bbsc_fullType(item))
    return string.find(ft, "rifle", 1, true) ~= nil
        or string.find(ft, "pistol", 1, true) ~= nil
        or string.find(ft, "shotgun", 1, true) ~= nil
        or string.find(ft, "gun", 1, true) ~= nil
end

local function bbsc_bodyLocation(item)
    return bbsc_safe(item, "getBodyLocation")
end

local function bbsc_category(item)
    local ft = bbsc_lower(bbsc_fullType(item))
    local cat = bbsc_lower(bbsc_safe(item, "getCategory"))
    local display = bbsc_lower(bbsc_safe(item, "getDisplayCategory"))
    local body = bbsc_lower(bbsc_bodyLocation(item))
    local partType = bbsc_lower(bbsc_safe(item, "getPartType"))
    local ammoType = bbsc_safe(item, "getAmmoType")
    local gunType = bbsc_safe(item, "getGunType")
    local maxAmmo = tonumber(bbsc_safe(item, "getMaxAmmo")) or 0
    local protection = bbsc_protection(item)

    if bbsc_boolMethod(item, "isFood") or cat == "food" or display == "food" then return "food" end
    if cat == "weaponpart" or display == "weaponpart" or partType ~= "" then return "weaponParts" end
    if display == "ammo" and (maxAmmo > 0 or ammoType or gunType or string.find(ft, "mag", 1, true) or string.find(ft, "clip", 1, true)) then return "magazines" end
    if string.find(ft, "guntoolkit", 1, true) or string.find(ft, "solvent", 1, true) or string.find(ft, "wd40", 1, true) then return "maintenance" end
    if cat == "ammo" or display == "ammo" or string.find(ft, "ammo", 1, true) or string.find(ft, "bullet", 1, true) or string.find(ft, "shell", 1, true) then return "ammo" end
    if bbsc_boolMethod(item, "IsWeapon") or bbsc_boolMethod(item, "isWeapon") or cat == "weapon" or display == "weapon" then return "weapons" end
    if protection > 0 or string.find(ft, "armor", 1, true) or string.find(ft, "bullet", 1, true) or string.find(ft, "vest", 1, true) or string.find(ft, "helmet", 1, true) or string.find(ft, "pads", 1, true) then return "armor" end
    if cat == "clothing" or display == "clothing" or body ~= "" then return "clothing" end
    return nil
end

local function bbsc_makeItemInfo(item)
    local resource = bbsc_category(item)
    if not resource then return nil end

    local count = tonumber(bbsc_safe(item, "getCount")) or 1
    if count < 1 then count = 1 end

    local ammoCount = nil
    local okAmmo, ammo = pcall(function()
        if item and item.getCurrentAmmoCount then return item:getCurrentAmmoCount() end
        return nil
    end)
    if okAmmo and ammo then ammoCount = tonumber(ammo) end

    local attachments = {}
    if resource == "weapons" then
        attachments = bbsc_collectWeaponAttachments(item)
    end

    return {
        fullType = bbsc_fullType(item),
        type = tostring(bbsc_safe(item, "getType") or ""),
        name = tostring(bbsc_safe(item, "getDisplayName") or bbsc_fullType(item)),
        category = tostring(bbsc_safe(item, "getCategory") or ""),
        displayCategory = tostring(bbsc_safe(item, "getDisplayCategory") or ""),
        bodyLocation = bbsc_bodyLocation(item),
        resource = resource,
        isFood = resource == "food",
        isAmmo = resource == "ammo",
        isMagazine = resource == "magazines",
        isWeaponPart = resource == "weaponParts",
        isMaintenance = resource == "maintenance",
        isWeapon = resource == "weapons",
        isRanged = bbsc_isRanged(item) == true,
        isTwoHandWeapon = bbsc_safe(item, "isTwoHandWeapon") == true,
        isClothing = resource == "clothing" or resource == "armor",
        isArmor = resource == "armor",
        protection = bbsc_protection(item),
        condition = tonumber(bbsc_safe(item, "getCondition")) or 0,
        maxCondition = tonumber(bbsc_safe(item, "getConditionMax")) or 0,
        ammoType = bbsc_safe(item, "getAmmoType"),
        magazineType = bbsc_safe(item, "getMagazineType"),
        magazineAmmoType = bbsc_safe(item, "getAmmoType"),
        gunType = bbsc_safe(item, "getGunType"),
        partType = bbsc_safe(item, "getPartType"),
        mountOn = bbsc_mountOnText(item),
        maxAmmo = tonumber(bbsc_safe(item, "getMaxAmmo")) or 0,
        ammoCount = ammoCount,
        loadedAmmo = ammoCount,
        attachments = attachments,
        attachmentCount = #attachments,
        count = count,
        baseAmount = 1
    }
end

local function bbsc_flattenItems(items, out)
    out = out or {}
    if type(items) ~= "table" then return out end
    for _, value in pairs(items) do
        if value and value.getFullType then
            table.insert(out, value)
        elseif type(value) == "table" and value.items then
            for _, nested in pairs(value.items) do
                if nested and nested.getFullType then table.insert(out, nested) end
            end
        elseif type(value) == "table" and value[1] and value[1].getFullType then
            table.insert(out, value[1])
        end
    end
    return out
end

local function bbsc_isEquipped(player, item)
    if not player or not item then return false end
    local ok, equipped = pcall(function()
        if player.isEquipped and player:isEquipped(item) then return true end
        if player.getPrimaryHandItem and player:getPrimaryHandItem() == item then return true end
        if player.getSecondaryHandItem and player:getSecondaryHandItem() == item then return true end
        return false
    end)
    return ok and equipped == true
end

local function bbsc_removeItem(player, item)
    if not player or not item then return false end
    if bbsc_isEquipped(player, item) then return false end
    local container = bbsc_safe(item, "getContainer")
    if container and container.Remove then
        local ok = pcall(function() container:Remove(item) end)
        if ok then return true end
    end
    local inv = player:getInventory()
    if inv and inv.Remove then
        local ok = pcall(function() inv:Remove(item) end)
        if ok then return true end
    end
    return false
end

local function bbsc_nearBase()
    local provider = bbsc_baseCaptureProvider()
    if provider and provider.FindNearbyBase then
        local ok, base, dist = pcall(function() return provider.FindNearbyBase() end)
        if ok and base then return base, dist end
    end
    return nil, nil
end

function NPCBaseSupplyClientBridge.DonateSelected(player, base, rawItems)
    if not player or not base then return end
    local items = bbsc_flattenItems(rawItems)
    local payload = {}
    local removeList = {}
    for _, item in ipairs(items) do
        if #payload >= NPCBaseSupplyClientBridge.MaxItemsPerDonation then break end
        local info = bbsc_makeItemInfo(item)
        if info then
            table.insert(payload, info)
            table.insert(removeList, item)
        end
    end
    if #payload <= 0 then
        if HaloTextHelper then HaloTextHelper.addText(player, "No supported base resources selected", 255, 180, 80) end
        return
    end

    local removed = 0
    for _, item in ipairs(removeList) do
        if bbsc_removeItem(player, item) then removed = removed + 1 end
    end
    if removed <= 0 then
        if HaloTextHelper then HaloTextHelper.addText(player, "Base supply: selected items are equipped or locked", 255, 120, 80) end
        return
    end

    sendClientCommand(player, 'NPCBaseSupply', 'DonateItems', {
        baseId = base.baseId or base.id,
        x = player:getX(),
        y = player:getY(),
        z = player:getZ(),
        items = payload
    })
end

function NPCBaseSupplyClientBridge.OnFillInventoryObjectContextMenu(playerNum, context, items)
    if not NPCBaseSupplyClientBridge.Enabled then return end
    local player = getSpecificPlayer(playerNum)
    if not player then return end
    local base = bbsc_nearBase()
    if not base then return end

    local supported = 0
    for _, item in ipairs(bbsc_flattenItems(items)) do
        if bbsc_makeItemInfo(item) then supported = supported + 1 end
    end
    if supported <= 0 then return end

    context:addOption(bbsc_text("Menu_DonateToBaseSupply") .. " (" .. tostring(supported) .. ")", player, NPCBaseSupplyClientBridge.DonateSelected, base, items)
end

local function bbsc_storeBaseSupply(args)
    if type(args) ~= "table" or not args.baseId then return end
    NPCBaseSupplyClientBridge.bases[tostring(args.baseId)] = args
end

local function bbsc_supplyForBase(base)
    if not base then return nil end
    return NPCBaseSupplyClientBridge.bases[tostring(base.baseId or base.id or "")]
end

local function bbsc_supplyCounts(base)
    local supply = bbsc_supplyForBase(base) or base
    if not supply then return nil end
    local food = math.floor(tonumber(supply.donatedFood or supply.stockFood) or 0)
    local clothing = math.floor(tonumber(supply.donatedClothing or supply.stockClothing) or 0)
    local weapons = math.floor(tonumber(supply.donatedWeapons or supply.stockWeapons) or 0)
    local armor = math.floor(tonumber(supply.donatedArmor or supply.stockArmor) or 0)
    local ammo = math.floor(tonumber(supply.donatedAmmo or supply.stockAmmo) or 0)
    local magazines = math.floor(tonumber(supply.donatedMagazines or supply.stockMagazines) or 0)
    local weaponParts = math.floor((tonumber(supply.donatedWeaponParts or supply.stockWeaponParts) or 0) + (tonumber(supply.donatedAttachedWeaponParts) or 0))
    local maintenance = math.floor(tonumber(supply.donatedMaintenance or supply.stockMaintenance) or 0)
    local total = math.floor(tonumber(supply.donatedTotalItems) or (food + clothing + weapons + armor + ammo + magazines + weaponParts + maintenance))
    return food, clothing, weapons, armor, ammo, total, magazines, weaponParts, maintenance
end

local function bbsc_supplyLine(base)
    local food, clothing, weapons, armor, ammo = bbsc_supplyCounts(base)
    if not food then return "Base supply: no data" end
    return "Supply: Food " .. tostring(food)
        .. "  Clothes " .. tostring(clothing)
        .. "  Armor " .. tostring(armor)
        .. "  Ammo " .. tostring(ammo)
end

local function bbsc_supplyGearLine(base)
    local food, clothing, weapons, armor, ammo, total, magazines, weaponParts, maintenance = bbsc_supplyCounts(base)
    if not food then return "Armory: no data" end
    return "Armory: Weapons " .. tostring(weapons)
        .. "  Parts " .. tostring(weaponParts)
        .. "  Mags " .. tostring(magazines)
        .. "  Maintenance " .. tostring(maintenance)
end

local BBSC_PANEL_SUPPLY_Y = 202
local BBSC_PANEL_ARMORY_Y = 219
local BBSC_PANEL_MIN_HEIGHT = 246

local function bbsc_patchPanel()
    if NPCBaseSupplyClientBridge._patchedPanel then return end
    local panel = bbsc_baseCapturePanelProvider()
    if not panel or not panel.render then return end
    NPCBaseSupplyClientBridge._patchedPanel = true
    panel._NPCBaseSupplyRender = panel._NPCBaseSupplyRender or panel.render
    panel.render = function(self)
        if self and self.height and self.height < BBSC_PANEL_MIN_HEIGHT then self.height = BBSC_PANEL_MIN_HEIGHT end
        panel._NPCBaseSupplyRender(self)
        if self and self.base and self.drawText then
            self:drawText(bbsc_supplyLine(self.base), 10, BBSC_PANEL_SUPPLY_Y, 0.78, 0.92, 0.78, 1, UIFont.Small)
            self:drawText(bbsc_supplyGearLine(self.base), 10, BBSC_PANEL_ARMORY_Y, 0.78, 0.92, 0.78, 1, UIFont.Small)
        end
    end
end

local function bbsc_getMapAPI(ui)
    if not ui then return nil end
    if ui.mapAPI then return ui.mapAPI end
    if ui.javaObject and ui.javaObject.getAPIv1 then
        local ok, api = pcall(function() return ui.javaObject:getAPIv1() end)
        if ok and api then return api end
    end
    if ui.map and ui.map.mapAPI then return ui.map.mapAPI end
    if ui.inner and ui.inner.mapAPI then return ui.inner.mapAPI end
    return nil
end

local function bbsc_worldToUI(api, x, y)
    if not api then return nil, nil end
    local okX, uiX = pcall(function() return api:worldToUIX(x, y) end)
    local okY, uiY = pcall(function() return api:worldToUIY(x, y) end)
    if okX and okY and uiX and uiY then return uiX, uiY end
    okX, uiX = pcall(function() return api:worldToUIX(x) end)
    okY, uiY = pcall(function() return api:worldToUIY(y) end)
    if okX and okY and uiX and uiY then return uiX, uiY end
    return nil, nil
end


local function bbsc_settingBool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        return NPCLegacySettingsBridge.GetBool(name, defaultValue == true)
    end
    return defaultValue == true
end

local function bbsc_shouldRender(isMiniMap)
    if not bbsc_settingBool("Debug_MapMarkersEnabled", true) then return false end
    if isMiniMap then
        return bbsc_settingBool("Debug_MiniMapMarkersEnabled", false)
    end
    return bbsc_settingBool("Debug_WorldMapMarkersEnabled", true)
end

local function bbsc_drawSupplyText(ui, marker, x, y)
    if not ui or not ui.drawTextCentre or not marker then return end
    local line1 = bbsc_supplyLine(marker)
    local line2 = bbsc_supplyGearLine(marker)
    if not line1 or line1 == "" then return end
    pcall(function()
        ui:drawTextCentre(line1, x, y + 18, 0, 0, 0, 1.0, UIFont.Small)
        ui:drawTextCentre(line1, x, y + 17, 1, 1, 1, 0.95, UIFont.Small)
        ui:drawTextCentre(line2, x, y + 31, 0, 0, 0, 1.0, UIFont.Small)
        ui:drawTextCentre(line2, x, y + 30, 1, 1, 1, 0.95, UIFont.Small)
    end)
end

function NPCBaseSupplyClientBridge.RenderOnMap(ui, api, isMiniMap)
    if not bbsc_shouldRender(isMiniMap == true) then return end
    if not ui or not api then return end
    for _, marker in pairs(NPCBaseSupplyClientBridge.bases or {}) do
        if marker and marker.x and marker.y then
            local x, y = bbsc_worldToUI(api, marker.x, marker.y)
            if x and y then bbsc_drawSupplyText(ui, marker, x, y) end
        end
    end
end

local function bbsc_hookMaps()
    if ISWorldMap and ISWorldMap.render and not NPCBaseSupplyClientBridge._hookedWorldMap then
        NPCBaseSupplyClientBridge._hookedWorldMap = true
        ISWorldMap._NPCBaseSupplyRender = ISWorldMap.render
        ISWorldMap.render = function(self)
            ISWorldMap._NPCBaseSupplyRender(self)
            NPCBaseSupplyClientBridge.RenderOnMap(self, bbsc_getMapAPI(self), false)
        end
    end
    if ISMiniMapInner and ISMiniMapInner.render and not NPCBaseSupplyClientBridge._hookedMiniMapInner then
        NPCBaseSupplyClientBridge._hookedMiniMapInner = true
        ISMiniMapInner._NPCBaseSupplyRender = ISMiniMapInner.render
        ISMiniMapInner.render = function(self)
            ISMiniMapInner._NPCBaseSupplyRender(self)
            NPCBaseSupplyClientBridge.RenderOnMap(self, bbsc_getMapAPI(self), true)
        end
    end
    if ISMiniMapOuter and ISMiniMapOuter.render and not NPCBaseSupplyClientBridge._hookedMiniMapOuter then
        NPCBaseSupplyClientBridge._hookedMiniMapOuter = true
        ISMiniMapOuter._NPCBaseSupplyRender = ISMiniMapOuter.render
        ISMiniMapOuter.render = function(self)
            ISMiniMapOuter._NPCBaseSupplyRender(self)
            local inner = self.inner or self.map
            NPCBaseSupplyClientBridge.RenderOnMap(inner or self, bbsc_getMapAPI(inner or self), true)
        end
    end
end

function NPCBaseSupplyClientBridge.OnServerCommand(module, command, args)
    if not NPCLegacyContractBridge.IsModule(module, "NPCBaseSupply", "baseSupply") then return end
    if command == "BaseUpdate" then
        bbsc_storeBaseSupply(args)
    elseif command == "DonationResult" then
        local player = getPlayer()
        if args and args.ok then
            if HaloTextHelper and player then HaloTextHelper.addText(player, "Base supply +" .. tostring(args.summary or args.accepted or ""), 120, 255, 120) end
        else
            if HaloTextHelper and player then HaloTextHelper.addText(player, "Base supply failed: " .. tostring(args and args.reason or "failed"), 255, 100, 80) end
        end
    end
end

local function bbsc_onTick()
    bbsc_patchPanel()
    bbsc_hookMaps()
    if not NPCBaseSupplyClientBridge._syncRequested then
        local player = getPlayer()
        if player then
            NPCBaseSupplyClientBridge._syncRequested = true
            sendClientCommand(player, 'NPCBaseSupply', 'RequestSync', {})
        end
    end
end

local function bbsc_registerTickJob()
    if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.RegisterTickJob then
        NPCWorkSchedulerBridge.RegisterTickJob("NPCBaseSupplyClientBridge.SyncBootstrap", bbsc_onTick, "ui", 30, 1)
    elseif Events and Events.OnTick then
        Events.OnTick.Add(bbsc_onTick)
    end
end

Events.OnFillInventoryObjectContextMenu.Add(NPCBaseSupplyClientBridge.OnFillInventoryObjectContextMenu)
Events.OnServerCommand.Add(NPCBaseSupplyClientBridge.OnServerCommand)
bbsc_registerTickJob()
