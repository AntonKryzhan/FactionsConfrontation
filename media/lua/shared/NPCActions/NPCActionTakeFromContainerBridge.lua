NPCActionTakeFromContainerBridge = NPCActionTakeFromContainerBridge or {}
require "NPCCore/NPCLegacyGlobalsBridge"

local NPC_ACTION_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
NPCEntity = NPCEntity or NPC_ACTION_LEGACY_GLOBALS.Get("Entity")
NPCUtils = NPCUtils or NPC_ACTION_LEGACY_GLOBALS.Get("Utils")



local function anyItem(item)
    return item ~= nil
end

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

local function isControlledByThisSide(zombie)
    return NPCUtils and NPCUtils.IsController and NPCUtils.IsController(zombie)
end

local function updateContainerOverlay(container)
    if isClient() then return end
    if not ItemPicker or not ItemPicker.updateOverlaySprite then return end
    if not container or not container.getParent then return end

    local parent = container:getParent()
    if parent and parent.getOverlaySprite and parent:getOverlaySprite() then
        ItemPicker.updateOverlaySprite(parent)
    end
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

local function moveItemToInventory(zombie, inventory, container, item)
    if not item or not inventory or not container then return false end

    container:Remove(item)
    if isControlledByThisSide(zombie) and container.removeItemOnServer then
        container:removeItemOnServer(item)
    end

    updateContainerOverlay(container)

    local finalItem = replaceDrainableIfNeeded(item)
    inventory:AddItem(finalItem)
    updateDeathItems(zombie)
    return true
end

NPCActionTakeFromContainerBridge.OnStart = function(zombie, task)
    return true
end

NPCActionTakeFromContainerBridge.OnWorking = function(zombie, task)
    faceTaskSquare(zombie, task)
    return actionAnimationFinished(zombie, task)
end

NPCActionTakeFromContainerBridge.OnComplete = function(zombie, task)
    if not zombie or not task or not task.itemType then return true end

    local inventory = zombie:getInventory()
    if not inventory then return true end

    local square = getTargetSquare(zombie, task)
    if not square or not square.getObjects then return true end

    local wanted = task.itemType
    local remaining = tonumber(task.cnt) or 1
    local objects = square:getObjects()
    if not objects then return true end

    for objectIndex = 0, objects:size() - 1 do
        local object = objects:get(objectIndex)
        local container = object and object.getContainer and object:getContainer()
        if container then
            local items = ArrayList.new()
            container:getAllEvalRecurse(anyItem, items)
            for itemIndex = 0, items:size() - 1 do
                local item = items:get(itemIndex)
                if item and item.getFullType and item:getFullType() == wanted then
                    if moveItemToInventory(zombie, inventory, container, item) then
                        remaining = remaining - 1
                        if remaining <= 0 then return true end
                    end
                end
            end
        end
    end

    return true
end
