NPCActionGeneratorRefillBridge = NPCActionGeneratorRefillBridge or {}
require "NPCCore/NPCLegacyGlobalsBridge"

local NPC_ACTION_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
NPCEntity = NPCEntity or NPC_ACTION_LEGACY_GLOBALS.Get("Entity")
NPCUtils = NPCUtils or NPC_ACTION_LEGACY_GLOBALS.Get("Utils")
NPCCompatibilityBridge = NPCCompatibilityBridge or NPC_ACTION_LEGACY_GLOBALS.Get("Compatibility")


local function getInventory(zombie)
    if zombie and zombie.getInventory then return zombie:getInventory() end
    return nil
end

local function refreshDeathItems(zombie)
    if NPCEntity and NPCEntity.UpdateItemsToSpawnAtDeath then
        NPCEntity.UpdateItemsToSpawnAtDeath(zombie)
    end
end

local function stopEmitter(zombie)
    local emitter = zombie and zombie.getEmitter and zombie:getEmitter() or nil
    if emitter then emitter:stopAll() end
end

local function faceTask(zombie, task)
    if zombie and task and task.x and task.y then
        zombie:faceLocation(task.x, task.y)
    end
end

local function getTaskSquare(zombie, task)
    if not task or not task.x or not task.y then return nil end
    local cell = zombie and zombie.getCell and zombie:getCell() or getCell()
    if not cell then return nil end
    return cell:getGridSquare(task.x, task.y, task.z or 0)
end

local function instanceItem(fullType)
    if NPCCompatibilityBridge and NPCCompatibilityBridge.InstanceItem then
        return NPCCompatibilityBridge.InstanceItem(fullType)
    end
    return InventoryItemFactory.CreateItem(fullType)
end

local function isController(zombie)
    return NPCUtils and NPCUtils.IsController and NPCUtils.IsController(zombie)
end

local function putItemOnGround(square, item)
    if square and item then
        square:AddWorldInventoryItem(item, ZombRandFloat(0.2, 0.8), ZombRandFloat(0.2, 0.8), 0)
    end
end

function NPCActionGeneratorRefillBridge.OnStart(zombie, task)
    local inventory = getInventory(zombie)
    local item = inventory and inventory:getItemFromType("PetrolCan") or nil
    if item then
        if NPCCompatibilityBridge and NPCCompatibilityBridge.SafeSetPrimaryHandItem then
            NPCCompatibilityBridge.SafeSetPrimaryHandItem(zombie, item)
        end
        inventory:Remove(item)
        refreshDeathItems(zombie)
        if zombie.playSound then zombie:playSound("GeneratorAddFuel") end
    end
    return true
end

function NPCActionGeneratorRefillBridge.OnWorking(zombie, task)
    if not zombie or not task then return true end
    faceTask(zombie, task)
    if task.time and task.time <= 0 then return true end
    if task.anim and zombie:getBumpType() ~= task.anim then
        zombie:setBumpType(task.anim)
    end
    return false
end

function NPCActionGeneratorRefillBridge.OnComplete(zombie, task)
    stopEmitter(zombie)

    local item = zombie and zombie.getPrimaryHandItem and zombie:getPrimaryHandItem() or nil
    if not item or item:getType() ~= "PetrolCan" then return true end

    local square = getTaskSquare(zombie, task)
    local generator = square and square:getGenerator() or nil
    if not generator then return true end

    local fuelFromCan = item:getUsedDelta() * 80
    local newFuel = (generator:getFuel() or 0) + fuelFromCan
    local gasLeft = (newFuel - 100) / 80
    if newFuel > 100 then newFuel = 100 end

    if gasLeft > 0 then
        item:setUsedDelta(gasLeft)
    else
        item = instanceItem("Base.EmptyPetrolCan")
    end

    if isController(zombie) then
        generator:setFuel(newFuel)
        putItemOnGround(square, item)
    end

    if NPCCompatibilityBridge and NPCCompatibilityBridge.SafeSetPrimaryHandItem then
        NPCCompatibilityBridge.SafeSetPrimaryHandItem(zombie, nil)
    end
    refreshDeathItems(zombie)
    return true
end
