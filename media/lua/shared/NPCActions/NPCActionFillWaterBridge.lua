NPCActionFillWaterBridge = NPCActionFillWaterBridge or {}
require "NPCCore/NPCLegacyGlobalsBridge"

local NPC_ACTION_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
NPCEntity = NPCEntity or NPC_ACTION_LEGACY_GLOBALS.Get("Entity")
NPCUtils = NPCUtils or NPC_ACTION_LEGACY_GLOBALS.Get("Utils")
NPCCompatibilityBridge = NPCCompatibilityBridge or NPC_ACTION_LEGACY_GLOBALS.Get("Compatibility")


local function getInventory(zombie)
    if not zombie or type(zombie.getInventory) ~= "function" then return nil end

    local ok, inventory = pcall(function()
        return zombie:getInventory()
    end)
    if ok then return inventory end
    return nil
end

local function refreshDeathItems(zombie)
    if not (NPCEntity and NPCEntity.UpdateItemsToSpawnAtDeath) then return end

    pcall(function()
        NPCEntity.UpdateItemsToSpawnAtDeath(zombie)
    end)
end

local function faceTask(zombie, task)
    if not zombie or not task then return end

    local x = tonumber(task.x)
    local y = tonumber(task.y)
    if not x or not y then return end

    if type(zombie.faceLocation) == "function" then
        pcall(function()
            zombie:faceLocation(x, y)
        end)
    elseif type(zombie.faceLocationF) == "function" then
        pcall(function()
            zombie:faceLocationF(x, y)
        end)
    end
end

local function stopEmitter(zombie)
    if not zombie or type(zombie.getEmitter) ~= "function" then return end

    local ok, emitter = pcall(function()
        return zombie:getEmitter()
    end)
    if ok and emitter and type(emitter.stopAll) == "function" then
        pcall(function()
            emitter:stopAll()
        end)
    end
end

local function setPrimaryHand(zombie, item)
    if not (NPCCompatibilityBridge and NPCCompatibilityBridge.SafeSetPrimaryHandItem) then return end

    pcall(function()
        NPCCompatibilityBridge.SafeSetPrimaryHandItem(zombie, item)
    end)
end

local function removeFromInventory(inventory, item)
    if not inventory or not item or type(inventory.Remove) ~= "function" then return end

    pcall(function()
        inventory:Remove(item)
    end)
end

local function addToInventory(inventory, item)
    if not inventory or not item or type(inventory.AddItem) ~= "function" then return end

    pcall(function()
        inventory:AddItem(item)
    end)
end

local function holdItem(zombie, inventory, item)
    if not zombie or not item then return end

    setPrimaryHand(zombie, item)
    removeFromInventory(inventory, item)
    refreshDeathItems(zombie)
end

local function restoreItem(zombie, item)
    local inventory = getInventory(zombie)
    if not inventory or not item then return end

    addToInventory(inventory, item)
    setPrimaryHand(zombie, nil)
    refreshDeathItems(zombie)
end

local function getItemByType(inventory, itemType)
    if not inventory or not itemType or type(inventory.getItemFromType) ~= "function" then return nil end

    local ok, item = pcall(function()
        return inventory:getItemFromType(itemType)
    end)
    if ok then return item end
    return nil
end

local function getPrimaryItem(zombie)
    if not zombie or type(zombie.getPrimaryHandItem) ~= "function" then return nil end

    local ok, item = pcall(function()
        return zombie:getPrimaryHandItem()
    end)
    if ok then return item end
    return nil
end

local function getTaskSquare(zombie, task)
    if not task then return nil end

    local x = tonumber(task.x)
    local y = tonumber(task.y)
    local z = tonumber(task.z) or 0
    if not x or not y then return nil end

    local cell = nil
    if zombie and type(zombie.getCell) == "function" then
        local ok, zombieCell = pcall(function()
            return zombie:getCell()
        end)
        if ok then cell = zombieCell end
    end
    if not cell and getCell then cell = getCell() end
    if not cell or type(cell.getGridSquare) ~= "function" then return nil end

    local ok, square = pcall(function()
        return cell:getGridSquare(x, y, z)
    end)
    if ok then return square end
    return nil
end

local function readWaterAmount(object)
    if not object or type(object.getWaterAmount) ~= "function" then return 0 end

    local ok, amount = pcall(function()
        return object:getWaterAmount()
    end)
    if ok and amount and amount > 0 then return amount end
    return 0
end

local function findWaterSource(square)
    if not square or type(square.getObjects) ~= "function" then return nil, 0 end

    local okObjects, objects = pcall(function()
        return square:getObjects()
    end)
    if not okObjects or not objects then return nil, 0 end

    local okSize, size = pcall(function()
        return objects:size()
    end)
    if not okSize or not size or size <= 0 then return nil, 0 end

    for i = 0, size - 1 do
        local okObject, object = pcall(function()
            return objects:get(i)
        end)
        if okObject then
            local amount = readWaterAmount(object)
            if amount > 0 then return object, amount end
        end
    end
    return nil, 0
end

local function isController(zombie)
    if not (NPCUtils and NPCUtils.IsController) then return false end

    local ok, result = pcall(function()
        return NPCUtils.IsController(zombie)
    end)
    return ok and result == true
end

local function updateSourceWater(zombie, source, task, waterLeft)
    if not source or not task or not isController(zombie) then return end
    if not getPlayer or not sendClientCommand then return end

    local player = getPlayer()
    if not player or type(source.getObjectIndex) ~= "function" then return end

    local okIndex, idx = pcall(function()
        return source:getObjectIndex()
    end)
    if not okIndex or idx == nil then return end

    local args = {x=task.x, y=task.y, z=task.z or 0, index=idx, amount=waterLeft}
    pcall(function()
        sendClientCommand(player, 'object', 'setWaterAmount', args)
    end)
end

local function isDrainableWaterItem(item)
    if not item or not instanceof then return false end

    local ok, result = pcall(function()
        return instanceof(item, "DrainableComboItem")
    end)
    return ok and result == true
end

local function getUseDelta(item)
    if not item or type(item.getUseDelta) ~= "function" then return nil end

    local ok, delta = pcall(function()
        return item:getUseDelta()
    end)
    if ok then return delta end
    return nil
end

local function getUsedDelta(item)
    if not item or type(item.getUsedDelta) ~= "function" then return 0 end

    local ok, delta = pcall(function()
        return item:getUsedDelta()
    end)
    if ok and delta then return delta end
    return 0
end

local function setUsedDelta(item, value)
    if not item or type(item.setUsedDelta) ~= "function" then return end

    pcall(function()
        item:setUsedDelta(value)
    end)
end

local function setWorkingAnim(zombie, task)
    if not zombie or not task or not task.anim then return end
    if type(zombie.getBumpType) ~= "function" or type(zombie.setBumpType) ~= "function" then return end

    local ok, current = pcall(function()
        return zombie:getBumpType()
    end)
    if not ok or current ~= task.anim then
        pcall(function()
            zombie:setBumpType(task.anim)
        end)
    end
end

function NPCActionFillWaterBridge.OnStart(zombie, task)
    if not task or not task.itemType then return true end

    local inventory = getInventory(zombie)
    local item = getItemByType(inventory, task.itemType)
    if item then holdItem(zombie, inventory, item) end
    return true
end

function NPCActionFillWaterBridge.OnWorking(zombie, task)
    if not zombie or not task then return true end

    faceTask(zombie, task)
    if task.time and task.time <= 0 then return true end
    setWorkingAnim(zombie, task)
    return false
end

function NPCActionFillWaterBridge.OnComplete(zombie, task)
    stopEmitter(zombie)

    local item = getPrimaryItem(zombie)
    if not isDrainableWaterItem(item) then
        restoreItem(zombie, item)
        return true
    end

    local square = getTaskSquare(zombie, task)
    local source, waterAvailable = findWaterSource(square)
    if not source then
        restoreItem(zombie, item)
        return true
    end

    local useDelta = getUseDelta(item)
    if not useDelta or useDelta <= 0 then
        restoreItem(zombie, item)
        return true
    end

    local waterToTake = math.floor((1 - getUsedDelta(item)) / useDelta + 0.5)
    if waterAvailable < waterToTake then waterToTake = waterAvailable end
    if waterToTake < 0 then waterToTake = 0 end

    updateSourceWater(zombie, source, task, waterAvailable - waterToTake)

    local newWater = getUsedDelta(item) + waterToTake * useDelta
    if newWater > 1 then newWater = 1 end
    setUsedDelta(item, newWater)
    restoreItem(zombie, item)
    return true
end
