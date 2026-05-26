NPCActionDropBridge = NPCActionDropBridge or {}
require "NPCCore/NPCLegacyGlobalsBridge"

local NPC_ACTION_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
NPCUtils = NPCUtils or NPC_ACTION_LEGACY_GLOBALS.Get("Utils")
NPCCompatibilityBridge = NPCCompatibilityBridge or NPC_ACTION_LEGACY_GLOBALS.Get("Compatibility")


local function actionAnimationFinished(zombie, task)
    if not zombie or not task or not task.anim or not zombie.getBumpType then return true end
    return zombie:getBumpType() ~= task.anim
end

local function isControlledByThisSide(zombie)
    return NPCUtils and NPCUtils.IsController and NPCUtils.IsController(zombie)
end

local function makeDropItem(task)
    if not task then return nil end
    local itemType = task.itemType or task.item
    if not itemType then return nil end
    if NPCCompatibilityBridge and NPCCompatibilityBridge.InstanceItem then
        return NPCCompatibilityBridge.InstanceItem(itemType)
    end
    return nil
end

local function dropItemOnSquare(zombie, item)
    if not zombie or not item or not zombie.getSquare then return end
    local square = zombie:getSquare()
    if square and square.AddWorldInventoryItem then
        square:AddWorldInventoryItem(item, ZombRandFloat(0.2, 0.8), ZombRandFloat(0.2, 0.8), 0)
    end
end

function NPCActionDropBridge.OnStart(zombie, task)
    return true
end

function NPCActionDropBridge.OnWorking(zombie, task)
    return actionAnimationFinished(zombie, task)
end

function NPCActionDropBridge.OnComplete(zombie, task)
    if isControlledByThisSide(zombie) then
        dropItemOnSquare(zombie, makeDropItem(task))
    end
    return true
end
