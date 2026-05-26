require "NPCCore/NPCLegacyContractBridge"

NPCActionFishingBridge = NPCActionFishingBridge or {}
require "NPCCore/NPCLegacyGlobalsBridge"

local NPC_ACTION_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
NPCEntity = NPCEntity or NPC_ACTION_LEGACY_GLOBALS.Get("Entity")
NPCUtils = NPCUtils or NPC_ACTION_LEGACY_GLOBALS.Get("Utils")
NPCCompatibilityBridge = NPCCompatibilityBridge or NPC_ACTION_LEGACY_GLOBALS.Get("Compatibility")


local fishTypes = {"Base.Bass", "Base.Crappie", "Base.Perch", "Base.Pike", "Base.Panfish", "Base.Trout"}

local function instanceItem(fullType)
    if not fullType then return nil end
    if NPCCompatibilityBridge and NPCCompatibilityBridge.InstanceItem then
        return NPCCompatibilityBridge.InstanceItem(fullType)
    end
    if InventoryItemFactory and InventoryItemFactory.CreateItem then
        return InventoryItemFactory.CreateItem(fullType)
    end
    return nil
end

local function refreshDeathItems(zombie)
    if NPCEntity and NPCEntity.UpdateItemsToSpawnAtDeath then
        NPCEntity.UpdateItemsToSpawnAtDeath(zombie)
    end
end

local function faceTask(zombie, task)
    if zombie and task and task.x and task.y and zombie.faceLocation then
        zombie:faceLocation(task.x, task.y)
    end
end

local function nextRand(limit)
    if not limit or limit <= 0 then return 0 end
    if NPCUtils and NPCUtils.NPCRand then
        return NPCUtils.NPCRand(limit)
    end
    if ZombRand then
        return ZombRand(limit)
    end
    return 0
end

local function addRandomFish(zombie)
    local inventory = zombie and zombie.getInventory and zombie:getInventory() or nil
    if not inventory then return end

    local index = 1 + nextRand(#fishTypes)
    local fishType = fishTypes[index]
    if not fishType then return end

    local fishItem = instanceItem(fishType)
    if fishItem then
        inventory:AddItem(fishItem)
        refreshDeathItems(zombie)
    end
end

local function updateTask(zombie, task)
    if NPCEntity and NPCEntity.UpdateTask then
        NPCEntity.UpdateTask(zombie, task)
    end
end

function NPCActionFishingBridge.OnStart(zombie, task)
    if not zombie then return true end

    local spear = instanceItem("Base.SpearShort")
    if NPCCompatibilityBridge and NPCCompatibilityBridge.SafeSetPrimaryHandItem then
        NPCCompatibilityBridge.SafeSetPrimaryHandItem(zombie, spear)
    elseif zombie.setPrimaryHandItem then
        zombie:setPrimaryHandItem(spear)
    end

    if task and task.itemPrimary then
        zombie:setVariable(NPCLegacyContractBridge.Key("PRIMARY"), task.itemPrimary)
    end
    zombie:setVariable(NPCLegacyContractBridge.Key("PRIMARY_TYPE"), "spear")
    return true
end

function NPCActionFishingBridge.OnWorking(zombie, task)
    if not zombie or not task then return true end
    faceTask(zombie, task)
    task.stage = task.stage or 1

    if not zombie:isBumped() then
        if task.stage < 9 then
            zombie:setBumpType("FishingSpearIdle")
        else
            zombie:setBumpType("FishingSpearStrike")
            if zombie.playSound then zombie:playSound("StrikeWithFishingSpear") end
        end
        task.stage = task.stage + 1
        updateTask(zombie, task)
    end

    if task.stage >= 10 then
        if nextRand(2) == 1 then addRandomFish(zombie) end
        return true
    end
    return false
end

function NPCActionFishingBridge.OnComplete(zombie, task)
    return true
end
