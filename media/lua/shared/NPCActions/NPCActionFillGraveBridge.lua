require "NPCCore/NPCLegacyContractBridge"

NPCActionFillGraveBridge = NPCActionFillGraveBridge or {}
require "NPCCore/NPCLegacyGlobalsBridge"

local NPC_ACTION_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
NPCEntity = NPCEntity or NPC_ACTION_LEGACY_GLOBALS.Get("Entity")
NPCCompatibilityBridge = NPCCompatibilityBridge or NPC_ACTION_LEGACY_GLOBALS.Get("Compatibility")


local function safeCall(fn)
    local ok, result = pcall(fn)
    if ok then return result end
    return nil
end

local function getInventory(zombie)
    if not zombie or not zombie.getInventory then return nil end
    return safeCall(function()
        return zombie:getInventory()
    end)
end

local function refreshDeathItems(zombie)
    if NPCEntity and NPCEntity.UpdateItemsToSpawnAtDeath then
        pcall(function()
            NPCEntity.UpdateItemsToSpawnAtDeath(zombie)
        end)
    end
end

local function setPrimaryHandItem(zombie, item)
    if not zombie then return end
    if NPCCompatibilityBridge and NPCCompatibilityBridge.SafeSetPrimaryHandItem then
        pcall(function()
            NPCCompatibilityBridge.SafeSetPrimaryHandItem(zombie, item)
        end)
    elseif zombie.setPrimaryHandItem then
        pcall(function()
            zombie:setPrimaryHandItem(item)
        end)
    end
end

local function removeInventoryItem(inventory, item)
    if not inventory or not item or not inventory.Remove then return end
    pcall(function()
        inventory:Remove(item)
    end)
end

local function addInventoryItem(inventory, item)
    if not inventory or not item or not inventory.AddItem then return end
    pcall(function()
        inventory:AddItem(item)
    end)
end

local function playSound(zombie, sound)
    if not zombie or not sound or not zombie.playSound then return end
    pcall(function()
        zombie:playSound(sound)
    end)
end

local function stopEmitter(zombie)
    if not zombie or not zombie.getEmitter then return end
    local emitter = safeCall(function()
        return zombie:getEmitter()
    end)
    if emitter and emitter.stopAll then
        pcall(function()
            emitter:stopAll()
        end)
    end
end

local function setActorVariable(zombie, name, value)
    if not zombie or not name or not zombie.setVariable then return end
    pcall(function()
        zombie:setVariable(name, value)
    end)
end

local function getItemType(item)
    if not item or not item.getType then return nil end
    return safeCall(function()
        return item:getType()
    end)
end

local function holdTool(zombie, inventory, item, itemType)
    if not zombie or not item then return end

    setPrimaryHandItem(zombie, item)
    setActorVariable(zombie, NPCLegacyContractBridge.Key("PRIMARY"), itemType or getItemType(item))
    setActorVariable(zombie, NPCLegacyContractBridge.Key("PRIMARY_TYPE"), "twohanded")
    removeInventoryItem(inventory, item)
    refreshDeathItems(zombie)
end

local function restoreHeldTool(zombie)
    if not zombie or not zombie.getPrimaryHandItem then return end

    local inventory = getInventory(zombie)
    if not inventory then return end

    local item = safeCall(function()
        return zombie:getPrimaryHandItem()
    end)
    if item then
        addInventoryItem(inventory, item)
        setPrimaryHandItem(zombie, nil)
        refreshDeathItems(zombie)
    end
end

local function faceTask(zombie, task)
    if not zombie or not task or task.x == nil or task.y == nil or not zombie.faceLocation then return end
    pcall(function()
        zombie:faceLocation(task.x, task.y)
    end)
end

local function getCellSquare(zombie, task)
    if not task or task.x == nil or task.y == nil then return nil end

    return safeCall(function()
        local cell = zombie and zombie.getCell and zombie:getCell() or getCell()
        if not cell then return nil end
        return cell:getGridSquare(task.x, task.y, task.z or 0)
    end)
end

local function getSpecialObjects(square)
    if not square or not square.getSpecialObjects then return nil end
    return safeCall(function()
        return square:getSpecialObjects()
    end)
end

local function getObjectName(object)
    if not object or not object.getName then return nil end
    return safeCall(function()
        return object:getName()
    end)
end

local function findEmptyGrave(square)
    local objects = getSpecialObjects(square)
    if not objects then return nil end

    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if getObjectName(object) == "EmptyGraves" then
            return object
        end
    end

    return nil
end

local function markGraveFilled(square)
    local grave = findEmptyGrave(square)
    if not grave then return false end

    local modData = grave.getModData and safeCall(function()
        return grave:getModData()
    end) or nil
    if modData then
        modData.filled = true
    end

    if grave.transmitModData then
        pcall(function()
            grave:transmitModData()
        end)
    end

    local spriteName = safeCall(function()
        local sprite = grave:getSprite()
        return sprite and sprite:getName()
    end)
    if spriteName and luautils and luautils.split then
        local split = luautils.split(spriteName, "_")
        local index = tonumber(split and split[5])
        if index and grave.setSpriteFromName then
            pcall(function()
                grave:setSpriteFromName("location_community_cemetary_01_" .. tostring(index + 8))
            end)
            if grave.transmitUpdatedSpriteToServer then
                pcall(function()
                    grave:transmitUpdatedSpriteToServer()
                end)
            end
        end
    end

    return true
end

local function getSquareCoordinates(square)
    if not square then return nil, nil, nil end
    local x = safeCall(function() return square:getX() end)
    local y = safeCall(function() return square:getY() end)
    local z = safeCall(function() return square:getZ() end)
    return x, y, z
end

local function getSecondGraveSquare(square, grave)
    if not square or not grave then return nil end

    local modData = grave.getModData and safeCall(function()
        return grave:getModData()
    end) or nil
    local spriteType = modData and modData.spriteType or nil
    local x, y, z = getSquareCoordinates(square)
    if x == nil or y == nil or z == nil then return nil end

    local north = safeCall(function()
        return grave:getNorth()
    end) == true

    return safeCall(function()
        local cell = getCell()
        if not cell then return nil end
        if north then
            if spriteType == "sprite1" then return cell:getGridSquare(x, y - 1, z) end
            if spriteType == "sprite2" then return cell:getGridSquare(x, y + 1, z) end
        else
            if spriteType == "sprite1" then return cell:getGridSquare(x - 1, y, z) end
            if spriteType == "sprite2" then return cell:getGridSquare(x + 1, y, z) end
        end
        return nil
    end)
end

local function isWorkDone(zombie, task)
    if not task or task.time == nil then return false end
    return task.time <= 0
end

local function keepAnimation(zombie, task)
    if not zombie or not task or not task.anim or not zombie.getBumpType then return end

    local current = safeCall(function()
        return zombie:getBumpType()
    end)
    if current ~= task.anim then
        playSound(zombie, "Shoveling")
        if zombie.setBumpType then
            pcall(function()
                zombie:setBumpType(task.anim)
            end)
        end
    end
end

function NPCActionFillGraveBridge.OnStart(zombie, task)
    if not zombie or not task then return true end

    local inventory = getInventory(zombie)
    local item = nil
    if inventory and task.itemType and inventory.getItemFromType then
        item = safeCall(function()
            return inventory:getItemFromType(task.itemType)
        end)
    end

    if item then
        holdTool(zombie, inventory, item, task.itemType)
        playSound(zombie, "Shoveling")
    end

    return true
end

function NPCActionFillGraveBridge.OnWorking(zombie, task)
    if not zombie or not task then return true end

    faceTask(zombie, task)
    if isWorkDone(zombie, task) then return true end
    keepAnimation(zombie, task)

    return false
end

function NPCActionFillGraveBridge.OnComplete(zombie, task)
    stopEmitter(zombie)

    local square = getCellSquare(zombie, task)
    local grave = findEmptyGrave(square)
    if grave then
        local secondSquare = getSecondGraveSquare(square, grave)
        markGraveFilled(square)
        if secondSquare then
            markGraveFilled(secondSquare)
        end
    end

    restoreHeldTool(zombie)
    return true
end
