NPCActionPutInContainerBridge = NPCActionPutInContainerBridge or {}
require "NPCCore/NPCLegacyGlobalsBridge"

local NPC_ACTION_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
NPCEntity = NPCEntity or NPC_ACTION_LEGACY_GLOBALS.Get("Entity")
NPCUtils = NPCUtils or NPC_ACTION_LEGACY_GLOBALS.Get("Utils")



local function getCellFor(zombie)
    if zombie and zombie.getCell then return zombie:getCell() end
    if getCell then return getCell() end
    return nil
end

local function getTargetSquare(zombie, task)
    if not task or not task.x or not task.y or task.z == nil then return nil end
    local cell = getCellFor(zombie)
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

local function updateDeathItems(zombie)
    if NPCEntity and NPCEntity.UpdateItemsToSpawnAtDeath then
        NPCEntity.UpdateItemsToSpawnAtDeath(zombie)
    end
end

local function isControlledByThisSide(zombie)
    return NPCUtils and NPCUtils.IsController and NPCUtils.IsController(zombie)
end

local function firstContainer(square)
    if not square or not square.getObjects then return nil end
    local objects = square:getObjects()
    if not objects then return nil end
    for objectIndex = 0, objects:size() - 1 do
        local object = objects:get(objectIndex)
        local container = object and object.getContainer and object:getContainer()
        if container then return container end
    end
    return nil
end

NPCActionPutInContainerBridge.OnStart = function(zombie, task)
    return true
end

NPCActionPutInContainerBridge.OnWorking = function(zombie, task)
    faceTaskSquare(zombie, task)
    return actionAnimationFinished(zombie, task)
end

NPCActionPutInContainerBridge.OnComplete = function(zombie, task)
    if not zombie or not task or not task.itemType then return true end

    local inventory = zombie:getInventory()
    if not inventory or not inventory.getItemFromType then return true end

    local item = inventory:getItemFromType(task.itemType)
    if not item then return true end

    local square = getTargetSquare(zombie, task)
    local container = firstContainer(square)
    if not container then return true end

    container:AddItem(item)
    if isControlledByThisSide(zombie) and container.addItemOnServer then
        container:addItemOnServer(item)
    end

    inventory:Remove(item)
    updateDeathItems(zombie)
    return true
end
