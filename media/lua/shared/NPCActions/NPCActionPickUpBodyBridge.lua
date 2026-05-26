NPCActionPickUpBodyBridge = NPCActionPickUpBodyBridge or {}
require "NPCCore/NPCLegacyGlobalsBridge"

local NPC_ACTION_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
NPCEntity = NPCEntity or NPC_ACTION_LEGACY_GLOBALS.Get("Entity")
NPCUtils = NPCUtils or NPC_ACTION_LEGACY_GLOBALS.Get("Utils")


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

local function getTaskSquare(zombie, task)
    if not zombie or not task or task.x == nil or task.y == nil or task.z == nil then return nil end
    if not zombie.getCell then return nil end

    return safeCall(function()
        local cell = zombie:getCell()
        if not cell or not cell.getGridSquare then return nil end
        return cell:getGridSquare(task.x, task.y, task.z)
    end)
end

local function faceTaskSquare(zombie, task)
    if not zombie or not task or task.x == nil or task.y == nil or not zombie.faceLocationF then return end
    pcall(function()
        zombie:faceLocationF(task.x, task.y)
    end)
end

local function isAnimationFinished(zombie, task)
    if not zombie or not task or not task.anim or not zombie.getBumpType then return true end

    local bumpType = safeCall(function()
        return zombie:getBumpType()
    end)
    return bumpType ~= task.anim
end

local function isController(zombie)
    if not NPCUtils or not NPCUtils.IsController then return false end
    return safeCall(function()
        return NPCUtils.IsController(zombie)
    end) == true
end

local function refreshDeathItems(zombie)
    if NPCEntity and NPCEntity.UpdateItemsToSpawnAtDeath then
        pcall(function()
            NPCEntity.UpdateItemsToSpawnAtDeath(zombie)
        end)
    end
end

local function getDeadBody(square)
    if not square or not square.getDeadBody then return nil end
    return safeCall(function()
        return square:getDeadBody()
    end)
end

local function getBodyItem(body)
    if not body or not body.getItem then return nil end
    return safeCall(function()
        return body:getItem()
    end)
end

local function addItemToInventory(inventory, item)
    if not inventory or not item or not inventory.AddItem then return false end
    local added = safeCall(function()
        inventory:AddItem(item)
        return true
    end)
    return added == true
end

local function removeBodyFromSquare(square, body)
    if not square or not body or not square.removeCorpse then return end
    pcall(function()
        square:removeCorpse(body, false)
    end)
end

function NPCActionPickUpBodyBridge.OnStart(zombie, task)
    return true
end

function NPCActionPickUpBodyBridge.OnWorking(zombie, task)
    faceTaskSquare(zombie, task)
    return isAnimationFinished(zombie, task)
end

function NPCActionPickUpBodyBridge.OnComplete(zombie, task)
    if not zombie or not task then return true end

    local inventory = getInventory(zombie)
    local square = getTaskSquare(zombie, task)
    local body = getDeadBody(square)
    local bodyItem = getBodyItem(body)

    if not inventory or not square or not body or not bodyItem then return true end

    if addItemToInventory(inventory, bodyItem) then
        refreshDeathItems(zombie)
    end

    if isController(zombie) then
        removeBodyFromSquare(square, body)
    end

    return true
end
