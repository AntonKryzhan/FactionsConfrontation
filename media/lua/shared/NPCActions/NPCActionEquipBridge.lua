NPCActionEquipBridge = NPCActionEquipBridge or {}
require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCLegacyContractBridge"

local NPC_ACTION_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
NPCEntity = NPCEntity or NPC_ACTION_LEGACY_GLOBALS.Get("Entity")
NPCCompatibilityBridge = NPCCompatibilityBridge or NPC_ACTION_LEGACY_GLOBALS.Get("Compatibility")
NPCBaseSupplyGearBridge = NPCBaseSupplyGearBridge or NPC_ACTION_LEGACY_GLOBALS.Get("BaseSupplyGear")

local NPC_ACTION_EQUIP_LEGACY_KEYS = {
    torch = NPCLegacyContractBridge.Key("TORCH"),
    primary = NPCLegacyContractBridge.Key("PRIMARY"),
    primaryType = NPCLegacyContractBridge.Key("PRIMARY_TYPE"),
    secondary = NPCLegacyContractBridge.Key("SECONDARY")
}


local function getVariableStringSafe(zombie, key)
    if not zombie or type(zombie.getVariableString) ~= "function" then return nil end
    return zombie:getVariableString(key)
end

local function setVariableSafe(zombie, key, value)
    if zombie and type(zombie.setVariable) == "function" then
        zombie:setVariable(key, value)
    end
end

local function getBumpTypeSafe(zombie)
    if not zombie or type(zombie.getBumpType) ~= "function" then return nil end
    return zombie:getBumpType()
end

local function setBumpTypeSafe(zombie, anim)
    if zombie and anim and type(zombie.setBumpType) == "function" then
        zombie:setBumpType(anim)
    end
end

local function instanceItem(itemType, zombie, slot)
    local item = nil
    if NPCBaseSupplyGearBridge and type(NPCBaseSupplyGearBridge.InstanceItem) == "function" then
        item = NPCBaseSupplyGearBridge.InstanceItem(itemType, zombie, slot)
    end
    if not item and NPCCompatibilityBridge and type(NPCCompatibilityBridge.InstanceItem) == "function" then
        item = NPCCompatibilityBridge.InstanceItem(itemType)
    end
    return item
end

local function safeSetPrimaryHandItem(zombie, item)
    if NPCCompatibilityBridge and type(NPCCompatibilityBridge.SafeSetPrimaryHandItem) == "function" then
        NPCCompatibilityBridge.SafeSetPrimaryHandItem(zombie, item)
    elseif zombie and type(zombie.setPrimaryHandItem) == "function" then
        zombie:setPrimaryHandItem(item)
    end
end

local function safeSetSecondaryHandItem(zombie, item)
    if NPCCompatibilityBridge and type(NPCCompatibilityBridge.SafeSetSecondaryHandItem) == "function" then
        NPCCompatibilityBridge.SafeSetSecondaryHandItem(zombie, item)
    elseif zombie and type(zombie.setSecondaryHandItem) == "function" then
        zombie:setSecondaryHandItem(item)
    end
end

local function getWeaponType(item)
    if not item or type(item.IsWeapon) ~= "function" then return nil end
    if not item:IsWeapon() then return nil end
    if not WeaponType or type(WeaponType.getWeaponType) ~= "function" then return nil end
    return WeaponType.getWeaponType(item)
end

local function getHands(primaryItem, primaryItemType)
    if primaryItemType then
        if primaryItemType == WeaponType.barehand then
            return "barehand"
        elseif primaryItemType == WeaponType.firearm then
            return "rifle"
        elseif primaryItemType == WeaponType.handgun then
            return "handgun"
        elseif primaryItemType == WeaponType.heavy then
            return "twohanded"
        elseif primaryItemType == WeaponType.onehanded then
            return "onehanded"
        elseif primaryItemType == WeaponType.spear then
            return "spear"
        elseif primaryItemType == WeaponType.twohanded then
            return "twohanded"
        elseif primaryItemType == WeaponType.throwing then
            return "throwing"
        elseif primaryItemType == WeaponType.chainsaw then
            return "chainsaw"
        else
            return "onehanded"
        end
    end

    if primaryItem and type(primaryItem.IsWeapon) == "function" and primaryItem:IsWeapon() then
        return "onehanded"
    end
    return "item"
end

local function canUseSecondary(hands)
    return hands == "barehand" or hands == "onehanded" or hands == "handgun" or hands == "throwing"
end

local function updateTorchState(zombie, secondaryItem)
    local lightStrength = 0
    if secondaryItem and type(secondaryItem.getLightStrength) == "function" then
        lightStrength = secondaryItem:getLightStrength()
    end

    if lightStrength > 0 then
        if type(secondaryItem.setActivated) == "function" then
            secondaryItem:setActivated(true)
        end
        setVariableSafe(zombie, NPC_ACTION_EQUIP_LEGACY_KEYS.torch, true)
    else
        setVariableSafe(zombie, NPC_ACTION_EQUIP_LEGACY_KEYS.torch, false)
    end
end

local function clearSecondary(zombie)
    safeSetSecondaryHandItem(zombie, nil)
    setVariableSafe(zombie, NPC_ACTION_EQUIP_LEGACY_KEYS.secondary, "")
    setVariableSafe(zombie, NPC_ACTION_EQUIP_LEGACY_KEYS.torch, false)
end

local function getEquipAnimation(primaryItemType)
    if WeaponType then
        if primaryItemType == WeaponType.firearm or primaryItemType == WeaponType.spear or primaryItemType == WeaponType.heavy or primaryItemType == WeaponType.twohanded then
            return "AttachBackOut"
        elseif primaryItemType == WeaponType.handgun then
            return "AttachHolsterRightOut"
        end
    end
    return "AttachHolsterLeftOut"
end

local function updateTask(zombie, task)
    if NPCEntity and type(NPCEntity.UpdateTask) == "function" then
        NPCEntity.UpdateTask(zombie, task)
    end
end

local function equipSecondaryIfNeeded(zombie, task, hands)
    if not task.itemSecondary then return true end

    if canUseSecondary(hands) then
        local oldSecondaryPrimary = getVariableStringSafe(zombie, NPC_ACTION_EQUIP_LEGACY_KEYS.secondary)
        if oldSecondaryPrimary ~= task.itemSecondary then
            local secondaryItem = instanceItem(task.itemSecondary, zombie, "secondary")
            if not secondaryItem then return false end

            safeSetSecondaryHandItem(zombie, secondaryItem)
            setVariableSafe(zombie, NPC_ACTION_EQUIP_LEGACY_KEYS.secondary, task.itemSecondary)
            updateTorchState(zombie, secondaryItem)
        end
    else
        clearSecondary(zombie)
    end

    return true
end

function NPCActionEquipBridge.OnStart(zombie, task)
    if not zombie or not task then return false end

    local oldItemPrimary = getVariableStringSafe(zombie, NPC_ACTION_EQUIP_LEGACY_KEYS.primary)
    if task.itemPrimary and oldItemPrimary ~= task.itemPrimary then
        local primaryItem = instanceItem(task.itemPrimary, zombie, task.slot or "primary")
        if not primaryItem then return false end

        safeSetPrimaryHandItem(zombie, primaryItem)
        setVariableSafe(zombie, NPC_ACTION_EQUIP_LEGACY_KEYS.primary, task.itemPrimary)

        local primaryItemType = getWeaponType(primaryItem)
        local hands = getHands(primaryItem, primaryItemType)
        setVariableSafe(zombie, NPC_ACTION_EQUIP_LEGACY_KEYS.primaryType, hands)

        if not equipSecondaryIfNeeded(zombie, task, hands) then return false end

        local anim = getEquipAnimation(primaryItemType)
        task.anim = anim
        updateTask(zombie, task)
        setBumpTypeSafe(zombie, anim)
    end

    return true
end

function NPCActionEquipBridge.OnWorking(zombie, task)
    if not task or not task.anim then return true end
    if getBumpTypeSafe(zombie) ~= task.anim then return true end
    return false
end

function NPCActionEquipBridge.OnComplete(zombie, task)
    return true
end
