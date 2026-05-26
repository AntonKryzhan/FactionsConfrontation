NPCActionPickUpBridge = NPCActionPickUpBridge or {}
require "NPCCore/NPCLegacyGlobalsBridge"

local NPC_ACTION_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
NPCEntity = NPCEntity or NPC_ACTION_LEGACY_GLOBALS.Get("Entity")
NPCUtils = NPCUtils or NPC_ACTION_LEGACY_GLOBALS.Get("Utils")


local function getTargetSquare(zombie, task)
    if not zombie or not task or not task.x or not task.y or task.z == nil then return nil end
    if not zombie.getCell then return nil end
    local cell = zombie:getCell()
    if not cell or not cell.getGridSquare then return nil end
    return cell:getGridSquare(task.x, task.y, task.z)
end

local function faceTaskSquare(zombie, task)
    if zombie and task and task.x and task.y and zombie.faceLocationF then
        zombie:faceLocationF(task.x, task.y)
    end
end

local function actionAnimationFinished(zombie, task)
    if not zombie or not task or not task.anim or not zombie.getBumpType then return true end
    return zombie:getBumpType() ~= task.anim
end

local function replaceDrainableIfNeeded(item)
    if NPCUtils and NPCUtils.ReplaceDrainable then
        return NPCUtils.ReplaceDrainable(item)
    end
    return item
end

local function updateDeathItems(zombie)
    if NPCEntity and NPCEntity.UpdateItemsToSpawnAtDeath then
        NPCEntity.UpdateItemsToSpawnAtDeath(zombie)
    end
end

local function detachWorldObject(square, object)
    if not square or not object then return end

    if square.removeWorldObject then square:removeWorldObject(object) end
    if square.transmitRemoveItemFromSquare then square:transmitRemoveItemFromSquare(object) end
    if square.RecalcProperties then square:RecalcProperties() end
    if square.RecalcAllWithNeighbours then square:RecalcAllWithNeighbours(true) end

    if object.removeFromWorld then object:removeFromWorld() end
    if object.removeFromSquare then object:removeFromSquare() end
    if object.setSquare then object:setSquare(nil) end

    local item = object.getItem and object:getItem()
    if item and item.setWorldItem then
        item:setWorldItem(nil)
    end
end

local function addPickedItem(inventory, item)
    if not inventory or not item then return end
    inventory:AddItem(replaceDrainableIfNeeded(item))
    if inventory.setDrawDirty then inventory:setDrawDirty(true) end
end

function NPCActionPickUpBridge.OnStart(zombie, task)
    return true
end

function NPCActionPickUpBridge.OnWorking(zombie, task)
    faceTaskSquare(zombie, task)
    return actionAnimationFinished(zombie, task)
end

function NPCActionPickUpBridge.OnComplete(zombie, task)
    if not zombie or not task or not task.itemType then return true end
    if not zombie.getInventory then return true end

    local inventory = zombie:getInventory()
    if not inventory then return true end

    local square = getTargetSquare(zombie, task)
    if not square or not square.getWorldObjects then return true end

    local wanted = task.itemType
    local remaining = tonumber(task.cnt) or 1
    local toRemove = {}
    local worldObjects = square:getWorldObjects()
    if not worldObjects or not worldObjects.size or not worldObjects.get then return true end

    for objectIndex = 0, worldObjects:size() - 1 do
        local object = worldObjects:get(objectIndex)
        local item = object and object.getItem and object:getItem()
        if item and item.getFullType and item:getFullType() == wanted then
            addPickedItem(inventory, item)
            updateDeathItems(zombie)

            table.insert(toRemove, object)
            remaining = remaining - 1
            if remaining <= 0 then break end
        end
    end

    for _, object in pairs(toRemove) do
        detachWorldObject(square, object)
    end

    return true
end
