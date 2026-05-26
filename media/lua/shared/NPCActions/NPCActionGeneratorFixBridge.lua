NPCActionGeneratorFixBridge = NPCActionGeneratorFixBridge or {}
require "NPCCore/NPCLegacyGlobalsBridge"

local NPC_ACTION_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
NPCEntity = NPCEntity or NPC_ACTION_LEGACY_GLOBALS.Get("Entity")
NPCUtils = NPCUtils or NPC_ACTION_LEGACY_GLOBALS.Get("Utils")


local function faceTask(zombie, task)
    if zombie and task and task.x and task.y then
        zombie:faceLocation(task.x, task.y)
    end
end

local function stopEmitter(zombie)
    if not zombie or not zombie.getEmitter then return end
    local emitter = zombie:getEmitter()
    if emitter then emitter:stopAll() end
end

local function getTaskSquare(zombie, task)
    if not zombie or not task or not task.x or not task.y then return nil end
    local cell = zombie.getCell and zombie:getCell() or getCell()
    if not cell then return nil end
    return cell:getGridSquare(task.x, task.y, task.z or 0)
end

local function isController(zombie)
    return NPCUtils and NPCUtils.IsController and NPCUtils.IsController(zombie)
end

local function refreshDeathItems(zombie)
    if NPCEntity and NPCEntity.UpdateItemsToSpawnAtDeath then
        NPCEntity.UpdateItemsToSpawnAtDeath(zombie)
    end
end

function NPCActionGeneratorFixBridge.OnStart(zombie, task)
    if zombie and zombie.playSound then zombie:playSound("GeneratorRepair") end
    return true
end

function NPCActionGeneratorFixBridge.OnWorking(zombie, task)
    if not zombie or not task then return true end
    faceTask(zombie, task)
    if task.time and task.time <= 0 then return true end
    if task.anim and zombie:getBumpType() ~= task.anim then
        zombie:setBumpType(task.anim)
    end
    return false
end

function NPCActionGeneratorFixBridge.OnComplete(zombie, task)
    stopEmitter(zombie)
    local square = getTaskSquare(zombie, task)
    local generator = square and square:getGenerator() or nil
    if not generator then return true end

    local inventory = zombie and zombie.getInventory and zombie:getInventory() or nil
    local scrap = inventory and inventory:getItemFromType("ElectronicsScrap") or nil
    if scrap then
        inventory:Remove(scrap)
        refreshDeathItems(zombie)
    end

    if isController(zombie) and generator.getCondition and generator.setCondition then
        local condition = generator:getCondition() or 0
        local fixed = condition + 5
        if fixed > 100 then fixed = 100 end
        generator:setCondition(fixed)
    end
    return true
end
