NPCActionPlaceItemBridge = NPCActionPlaceItemBridge or {}
require "NPCCore/NPCLegacyGlobalsBridge"

local NPC_ACTION_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
NPCEntity = NPCEntity or NPC_ACTION_LEGACY_GLOBALS.Get("Entity")
NPCUtils = NPCUtils or NPC_ACTION_LEGACY_GLOBALS.Get("Utils")



local function isControlledByThisSide(zombie)
    return NPCUtils and NPCUtils.IsController and NPCUtils.IsController(zombie)
end

local function getTargetSquare(zombie, task)
    if not task or not task.x or not task.y or task.z == nil then return nil end
    local cell = nil
    if zombie and zombie.getCell then cell = zombie:getCell() end
    if not cell and getCell then cell = getCell() end
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

local function readSurfaceOffset(object)
    if not object then return 0 end

    local offset = 0
    if object.getSurfaceOffsetNoTable then
        local noTable = object:getSurfaceOffsetNoTable()
        if noTable and noTable > offset then offset = noTable end
    end
    if object.getSurfaceOffset then
        local tableOffset = object:getSurfaceOffset()
        if tableOffset and tableOffset > offset then offset = tableOffset end
    end
    return offset
end

local function findSurfaceOffset(square)
    if not square or not square.getLuaTileObjectList then return 0 end

    local maxOffset = 0
    local tileObjects = square:getLuaTileObjectList()
    if not tileObjects then return 0 end

    for _, object in pairs(tileObjects) do
        local offset = readSurfaceOffset(object)
        if offset > maxOffset then maxOffset = offset end
    end

    return maxOffset / 96
end

NPCActionPlaceItemBridge.OnStart = function(zombie, task)
    return true
end

NPCActionPlaceItemBridge.OnWorking = function(zombie, task)
    faceTaskSquare(zombie, task)
    return actionAnimationFinished(zombie, task)
end

NPCActionPlaceItemBridge.OnComplete = function(zombie, task)
    if not isControlledByThisSide(zombie) then return true end
    if not zombie or not task or not task.itemType then return true end

    local inventory = zombie:getInventory()
    if not inventory or not inventory.getItemFromType then return true end

    local item = inventory:getItemFromType(task.itemType)
    if not item then return true end

    local square = getTargetSquare(zombie, task)
    if not square or not square.AddWorldInventoryItem then return true end

    local zOffset = findSurfaceOffset(square)
    inventory:Remove(item)
    updateDeathItems(zombie)
    square:AddWorldInventoryItem(item, ZombRandFloat(0.35, 0.65), ZombRandFloat(0.35, 0.65), zOffset)
    return true
end
