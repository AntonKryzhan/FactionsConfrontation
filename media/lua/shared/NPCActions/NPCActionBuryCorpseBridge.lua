NPCActionBuryCorpseBridge = NPCActionBuryCorpseBridge or {}
require "NPCCore/NPCLegacyGlobalsBridge"

local NPC_ACTION_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
NPCUtils = NPCUtils or NPC_ACTION_LEGACY_GLOBALS.Get("Utils")


local function safeCall(fn)
    local ok, result = pcall(fn)
    if ok then return result end
    return nil
end

local function faceTask(zombie, task)
    if not zombie or not task or not task.x or not task.y or not zombie.faceLocationF then return end
    pcall(function()
        zombie:faceLocationF(task.x, task.y)
    end)
end

local function isAnimationDone(zombie, task)
    if not zombie or not task or not task.anim or not zombie.getBumpType then return true end
    local bump = safeCall(function()
        return zombie:getBumpType()
    end)
    return bump ~= task.anim
end

local function getTaskSquare(zombie, task)
    if not zombie or not task or task.x == nil or task.y == nil or task.z == nil then return nil end
    return safeCall(function()
        local cell = zombie:getCell()
        return cell and cell:getGridSquare(task.x, task.y, task.z)
    end)
end

local function isController(zombie)
    if not NPCUtils or not NPCUtils.IsController then return false end
    local result = safeCall(function()
        return NPCUtils.IsController(zombie)
    end)
    return result == true
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

local function incrementCorpseCount(square)
    local grave = findEmptyGrave(square)
    if not grave or not grave.getModData then return end

    local modData = safeCall(function()
        return grave:getModData()
    end)
    if not modData then return end

    modData.corpses = (tonumber(modData.corpses) or 0) + 1
    if grave.transmitModData then
        pcall(function()
            grave:transmitModData()
        end)
    end
end

local function removeOneCorpseItem(zombie)
    if not zombie or not zombie.getInventory then return end

    local inventory = safeCall(function()
        return zombie:getInventory()
    end)
    if not inventory then return end

    local hasMale = safeCall(function()
        return inventory:containsType("CorpseMale")
    end) == true
    local hasFemale = safeCall(function()
        return inventory:containsType("CorpseFemale")
    end) == true

    if hasMale then
        pcall(function()
            inventory:RemoveOneOf("CorpseMale", false)
        end)
    elseif hasFemale then
        pcall(function()
            inventory:RemoveOneOf("CorpseFemale", false)
        end)
    end
end

local function getSquareCoordinates(square)
    if not square then return nil, nil, nil end
    local x = safeCall(function() return square:getX() end)
    local y = safeCall(function() return square:getY() end)
    local z = safeCall(function() return square:getZ() end)
    return x, y, z
end

local function readGravePairOffset(grave)
    if not grave then return nil, nil end

    local north = safeCall(function()
        return grave:getNorth()
    end) == true
    local modData = grave.getModData and safeCall(function()
        return grave:getModData()
    end) or nil
    local spriteType = modData and modData.spriteType or nil

    if north then
        if spriteType == "sprite1" then return 0, -1 end
        if spriteType == "sprite2" then return 0, 1 end
    else
        if spriteType == "sprite1" then return -1, 0 end
        if spriteType == "sprite2" then return 1, 0 end
    end

    return nil, nil
end

local function getPairedSquare(square, grave)
    local dx, dy = readGravePairOffset(grave)
    if not dx or not dy then return nil end

    local x, y, z = getSquareCoordinates(square)
    if x == nil or y == nil or z == nil then return nil end

    return safeCall(function()
        return getCell():getGridSquare(x + dx, y + dy, z)
    end)
end

function NPCActionBuryCorpseBridge.OnStart(zombie, task)
    return true
end

function NPCActionBuryCorpseBridge.OnWorking(zombie, task)
    faceTask(zombie, task)
    return isAnimationDone(zombie, task)
end

function NPCActionBuryCorpseBridge.OnComplete(zombie, task)
    removeOneCorpseItem(zombie)

    if isController(zombie) then
        local square = getTaskSquare(zombie, task)
        local grave = findEmptyGrave(square)
        if grave then
            incrementCorpseCount(square)
            incrementCorpseCount(getPairedSquare(square, grave))
        end
    end

    return true
end
