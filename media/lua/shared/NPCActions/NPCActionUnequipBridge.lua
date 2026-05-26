NPCActionUnequipBridge = NPCActionUnequipBridge or {}
require "NPCCore/NPCLegacyGlobalsBridge"

local NPC_ACTION_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
NPCCompatibilityBridge = NPCCompatibilityBridge or NPC_ACTION_LEGACY_GLOBALS.Get("Compatibility")


local function instanceItem(itemType)
    if not itemType then return nil end
    if not NPCCompatibilityBridge or type(NPCCompatibilityBridge.InstanceItem) ~= "function" then return nil end

    local ok, item = pcall(function()
        return NPCCompatibilityBridge.InstanceItem(itemType)
    end)
    if ok then return item end
    return nil
end

local function isWeapon(item)
    if not item or type(item.IsWeapon) ~= "function" then return false end

    local ok, weapon = pcall(function()
        return item:IsWeapon()
    end)
    return ok and weapon == true
end

local function getWeaponType(item)
    if not isWeapon(item) then return nil end
    if not WeaponType or type(WeaponType.getWeaponType) ~= "function" then return nil end

    local ok, weaponType = pcall(function()
        return WeaponType.getWeaponType(item)
    end)
    if ok then return weaponType end
    return nil
end

local function getUnequipAnimation(primaryItemType)
    if not WeaponType then return nil end
    if primaryItemType == WeaponType.firearm or primaryItemType == WeaponType.spear or primaryItemType == WeaponType.heavy or primaryItemType == WeaponType.twohanded then
        return "AttachBack"
    elseif primaryItemType == WeaponType.handgun then
        return "AttachHolsterRight"
    end
    return "AttachHolsterLeft"
end

local function getAttachSlot(primaryItemType)
    if not WeaponType then return nil end
    if primaryItemType == WeaponType.firearm or primaryItemType == WeaponType.spear or primaryItemType == WeaponType.heavy or primaryItemType == WeaponType.twohanded then
        return "Rifle On Back"
    elseif primaryItemType == WeaponType.handgun then
        return "Holster Right"
    end
    return "Belt Left"
end

local function setBumpTypeSafe(zombie, anim)
    if zombie and anim and type(zombie.setBumpType) == "function" then
        zombie:setBumpType(anim)
    end
end

local function getBumpTypeSafe(zombie)
    if not zombie or type(zombie.getBumpType) ~= "function" then return nil end
    return zombie:getBumpType()
end

local function setAttachedItemSafe(zombie, slot, item)
    if zombie and slot and item and type(zombie.setAttachedItem) == "function" then
        zombie:setAttachedItem(slot, item)
    end
end

function NPCActionUnequipBridge.OnStart(zombie, task)
    if not zombie or not task then return true end

    if task.itemPrimary then
        local primaryItem = instanceItem(task.itemPrimary)
        local primaryItemType = getWeaponType(primaryItem)
        if primaryItemType then
            local anim = getUnequipAnimation(primaryItemType)
            setBumpTypeSafe(zombie, anim)
        end
    end

    return true
end

function NPCActionUnequipBridge.OnWorking(zombie, task)
    if not task or getBumpTypeSafe(zombie) ~= task.anim then return true end
    return false
end

function NPCActionUnequipBridge.OnComplete(zombie, task)
    if not zombie or not task then return true end

    if task.itemPrimary then
        local primaryItem = instanceItem(task.itemPrimary)
        local primaryItemType = getWeaponType(primaryItem)
        if primaryItemType then
            local slot = getAttachSlot(primaryItemType)
            setAttachedItemSafe(zombie, slot, primaryItem)
        end
    end

    return true
end
