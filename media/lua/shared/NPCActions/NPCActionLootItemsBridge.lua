NPCActionLootItemsBridge = NPCActionLootItemsBridge or {}
require "NPCCore/NPCLegacyGlobalsBridge"

local NPC_ACTION_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
NPCEntity = NPCEntity or NPC_ACTION_LEGACY_GLOBALS.Get("Entity")


local function acceptAnyItem(item)
    return item ~= nil
end

local function faceTask(zombie, task)
    if zombie and task and task.x and task.y then
        zombie:faceLocation(task.x, task.y)
    end
end

local function refreshDeathItems(zombie)
    if NPCEntity and NPCEntity.UpdateItemsToSpawnAtDeath then
        NPCEntity.UpdateItemsToSpawnAtDeath(zombie)
    end
end

local function getTaskSquare(task)
    if not task or not task.x or not task.y then return nil end
    local cell = getCell()
    if not cell then return nil end
    return cell:getGridSquare(task.x, task.y, task.z or 0)
end

local function collectContainerItems(container)
    local items = ArrayList.new()
    if container and container.getAllEvalRecurse then
        container:getAllEvalRecurse(acceptAnyItem, items)
    end
    return items
end

local function transferItem(container, inventory, item)
    if not container or not inventory or not item then return false end
    container:Remove(item)
    if container.removeItemOnServer then
        container:removeItemOnServer(item)
    end
    inventory:AddItem(item)
    return true
end

NPCActionLootItemsBridge.OnStart = function(zombie, task)
    return true
end

NPCActionLootItemsBridge.OnWorking = function(zombie, task)
    if not zombie or not task then return true end
    faceTask(zombie, task)
    if task.time and task.time <= 0 then return true end
    if task.anim and zombie:getBumpType() ~= task.anim then
        zombie:setBumpType(task.anim)
    end
    return false
end

NPCActionLootItemsBridge.OnComplete = function(zombie, task)
    local square = getTaskSquare(task)
    local inventory = zombie and zombie.getInventory and zombie:getInventory() or nil
    if not square or not inventory then return true end

    local objects = square:getObjects()
    if not objects then return true end

    local changed = false
    for i=0, objects:size() - 1 do
        local object = objects:get(i)
        local container = object and object.getContainer and object:getContainer() or nil
        if container and not container:isEmpty() then
            local items = collectContainerItems(container)
            for j=0, items:size() - 1 do
                if transferItem(container, inventory, items:get(j)) then
                    changed = true
                end
            end
        end
    end

    if changed then refreshDeathItems(zombie) end
    return true
end
