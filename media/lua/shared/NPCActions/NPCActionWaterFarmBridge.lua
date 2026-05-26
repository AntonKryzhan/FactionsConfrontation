NPCActionWaterFarmBridge = NPCActionWaterFarmBridge or {}
require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCLegacyContractBridge"

local NPC_ACTION_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
local NPC_ACTION_LEGACY_ITEMS = NPCLegacyContractBridge.Items
NPCUtils = NPCUtils or NPC_ACTION_LEGACY_GLOBALS.Get("Utils")
NPCCompatibilityBridge = NPCCompatibilityBridge or NPC_ACTION_LEGACY_GLOBALS.Get("Compatibility")


local function createInventoryItem(fullType)
    if not fullType then return nil end
    if NPCCompatibilityBridge and NPCCompatibilityBridge.InstanceItem then
        return NPCCompatibilityBridge.InstanceItem(fullType)
    end
    if InventoryItemFactory and InventoryItemFactory.CreateItem then
        return InventoryItemFactory.CreateItem(fullType)
    end
    return nil
end

local function makeVisualWaterContainer(itemType)
    if itemType == "farming.WateredCanFull" or itemType == "farming.WateredCan" or itemType == "Base.WateredCan" then
        return createInventoryItem(NPC_ACTION_LEGACY_ITEMS.wateringCan)
    end
    if itemType == "Base.BucketWaterFull" or itemType == "Base.BucketEmpty" or itemType == "Base.Bucket" then
        return createInventoryItem(NPC_ACTION_LEGACY_ITEMS.bucket)
    end
    return nil
end

local function getActorInventory(zombie)
    if zombie and zombie.getInventory then return zombie:getInventory() end
    return nil
end

local function getTaskItem(zombie, task)
    local inventory = getActorInventory(zombie)
    if not inventory or not task or not task.itemType or not inventory.getItemFromType then return nil end
    return inventory:getItemFromType(task.itemType)
end

local function isDrainableItem(item)
    return item and instanceof and instanceof(item, "DrainableComboItem")
end

local function faceTaskTarget(zombie, task)
    if zombie and task and task.x and task.y and zombie.faceLocation then
        zombie:faceLocation(task.x, task.y)
    end
end

local function controlledHere(zombie)
    return NPCUtils and NPCUtils.IsController and NPCUtils.IsController(zombie)
end

local function getFarmPlant(task)
    if not task or not task.x or not task.y then return nil end
    if not CFarmingSystem or not CFarmingSystem.instance then return nil end
    if not CFarmingSystem.instance.getLuaObjectAt then return nil end
    return CFarmingSystem.instance:getLuaObjectAt(task.x, task.y, task.z or 0)
end

local function sendFarmWaterCommand(task, uses)
    if not task or not uses or uses <= 0 then return end
    if not CFarmingSystem or not CFarmingSystem.instance or not CFarmingSystem.instance.sendCommand then return end
    if not getPlayer then return end

    local player = getPlayer()
    if not player then return end

    CFarmingSystem.instance:sendCommand(player, 'water', {x=task.x, y=task.y, z=task.z or 0, uses=uses})
end

local function setPrimaryItem(zombie, item)
    if not zombie then return end
    if NPCCompatibilityBridge and NPCCompatibilityBridge.SafeSetPrimaryHandItem then
        NPCCompatibilityBridge.SafeSetPrimaryHandItem(zombie, item)
    elseif zombie.setPrimaryHandItem then
        zombie:setPrimaryHandItem(item)
    end
end

local function setWorkingAnimation(zombie, task)
    if not zombie or not task or not task.anim or not zombie.getBumpType or not zombie.setBumpType then return end
    if zombie:getBumpType() ~= task.anim then
        zombie:setBumpType(task.anim)
    end
end

local function calculateWaterAmount(item, plant)
    local waterNeeded = (plant.waterNeeded or 0) - (plant.waterLvl or 0)
    if waterNeeded <= 0 then return 0, 0, nil end

    local useDelta = item and item.getUseDelta and item:getUseDelta() or nil
    if not useDelta or useDelta <= 0 then return 0, 0, nil end

    local usedDelta = item.getUsedDelta and item:getUsedDelta() or 0
    local available = math.floor((usedDelta / useDelta) + 0.5) * 4
    local toPour = waterNeeded
    if available < toPour then toPour = available end
    if toPour < 0 then toPour = 0 end

    return toPour, available, useDelta
end

local function applyRemainingWater(item, available, poured, useDelta)
    if not item or not item.setUsedDelta or not useDelta then return end
    local left = available - poured
    local newDelta = left * useDelta / 4
    if newDelta > 1 then newDelta = 1 end
    if newDelta < 0 then newDelta = 0 end
    item:setUsedDelta(newDelta)
end

function NPCActionWaterFarmBridge.OnStart(zombie, task)
    local item = getTaskItem(zombie, task)
    if not isDrainableItem(item) then return true end

    local fakeItem = makeVisualWaterContainer(item:getFullType())
    setPrimaryItem(zombie, fakeItem)

    if zombie and zombie.playSound then zombie:playSound("WaterCrops") end
    return true
end

function NPCActionWaterFarmBridge.OnWorking(zombie, task)
    if not zombie or not task then return true end
    faceTaskTarget(zombie, task)
    if task.time and task.time <= 0 then return true end
    setWorkingAnimation(zombie, task)
    return false
end

function NPCActionWaterFarmBridge.OnComplete(zombie, task)
    setPrimaryItem(zombie, nil)

    local item = getTaskItem(zombie, task)
    if not isDrainableItem(item) then return true end

    local plant = getFarmPlant(task)
    if not plant then return true end

    local waterToPour, waterAvailable, useDelta = calculateWaterAmount(item, plant)
    if waterToPour > 0 and controlledHere(zombie) then
        sendFarmWaterCommand(task, waterToPour)
    end
    applyRemainingWater(item, waterAvailable, waterToPour, useDelta)
    return true
end
