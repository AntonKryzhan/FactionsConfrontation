NPCActionTimeItemBridge = NPCActionTimeItemBridge or {}
require "NPCCore/NPCLegacyGlobalsBridge"

local NPC_ACTION_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
NPCCompatibilityBridge = NPCCompatibilityBridge or NPC_ACTION_LEGACY_GLOBALS.Get("Compatibility")


local function makeActionItem(itemType)
    if not itemType or not NPCCompatibilityBridge or not NPCCompatibilityBridge.InstanceItem then
        return nil
    end
    return NPCCompatibilityBridge.InstanceItem(itemType)
end

local function setPrimary(zombie, item)
    if NPCCompatibilityBridge and NPCCompatibilityBridge.SafeSetPrimaryHandItem then
        NPCCompatibilityBridge.SafeSetPrimaryHandItem(zombie, item)
    elseif zombie and zombie.setPrimaryHandItem then
        zombie:setPrimaryHandItem(item)
    end
end

local function setSecondary(zombie, item)
    if NPCCompatibilityBridge and NPCCompatibilityBridge.SafeSetSecondaryHandItem then
        NPCCompatibilityBridge.SafeSetSecondaryHandItem(zombie, item)
    elseif zombie and zombie.setSecondaryHandItem then
        zombie:setSecondaryHandItem(item)
    end
end

local function keepAnimation(zombie, task)
    if not zombie or not task or not task.anim then return end
    if zombie.getBumpType and zombie:getBumpType() == task.anim then return end
    if zombie.setBumpType then
        zombie:setBumpType(task.anim)
    end
end

local function playActionSound(zombie, task)
    if not zombie or not task or not task.sound then return end
    if not zombie.getEmitter then return end

    local emitter = zombie:getEmitter()
    if not emitter then return end
    if emitter.isPlaying and emitter:isPlaying(task.sound) then return end
    if emitter.playSound then
        emitter:playSound(task.sound)
    end
end

function NPCActionTimeItemBridge.OnStart(zombie, task)
    if not zombie or not task then return true end

    local fakeItem = makeActionItem(task.item)
    if fakeItem then
        if not task.left then
            setPrimary(zombie, fakeItem)
        end
        if not task.right then
            setSecondary(zombie, fakeItem)
        end
    end

    return true
end

function NPCActionTimeItemBridge.OnWorking(zombie, task)
    if not zombie or not task then return true end
    if not task.time or task.time <= 0 then return true end

    keepAnimation(zombie, task)
    playActionSound(zombie, task)

    return false
end

function NPCActionTimeItemBridge.OnComplete(zombie, task)
    if zombie and task and task.item then
        if task.left then
            setSecondary(zombie, nil)
        else
            setPrimary(zombie, nil)
        end
    end
    return true
end
