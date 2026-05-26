NPCActionZombifyBridge = NPCActionZombifyBridge or {}
require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCLegacyContractBridge"

local NPC_ACTION_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
NPCUtils = NPCUtils or NPC_ACTION_LEGACY_GLOBALS.Get("Utils")
NPCBrainData = NPCBrainData or NPC_ACTION_LEGACY_GLOBALS.Get("Brain")
NPCServerRuntime = NPCServerRuntime or NPC_ACTION_LEGACY_GLOBALS.Get("ServerRuntime")

local NPC_ACTION_ZOMBIFY_LEGACY_KEYS = {
    liveFlag = NPCLegacyContractBridge.Key("FLAG"),
    formerNPCZombie = NPCLegacyContractBridge.Key("FORMER_ZOMBIE"),
    primary = NPCLegacyContractBridge.Key("PRIMARY"),
    secondary = NPCLegacyContractBridge.Key("SECONDARY"),
    persistentId = NPCLegacyContractBridge.Key("PERSISTENT_ID"),
    worldGroupId = NPCLegacyContractBridge.Key("WORLD_GROUP_ID")
}
local NPC_ACTION_ZOMBIFY_LEGACY_COMMANDS = {
    remove = NPCLegacyContractBridge.Command("REMOVE")
}


local function getBrain(zombie)
    if not zombie or not NPCBrainData or not NPCBrainData.Get then return nil end
    return NPCBrainData.Get(zombie)
end

local function getPersistentNpcIds(zombie, brain)
    local md = zombie and zombie.getModData and zombie:getModData() or nil
    local persistentId = (brain and (brain.persistentId or brain.uid)) or (md and md[NPC_ACTION_ZOMBIFY_LEGACY_KEYS.persistentId])
    local worldGroupId = (brain and (brain.worldGroupId or brain.groupId)) or (md and md[NPC_ACTION_ZOMBIFY_LEGACY_KEYS.worldGroupId])
    return persistentId, worldGroupId
end

local function clearNpcRuntimeState(zombie)
    if not zombie then return end
    pcall(function() zombie:setVariable(NPC_ACTION_ZOMBIFY_LEGACY_KEYS.liveFlag, false) end)
    pcall(function() zombie:setVariable(NPC_ACTION_ZOMBIFY_LEGACY_KEYS.formerNPCZombie, false) end)
    pcall(function() zombie:setVariable(NPC_ACTION_ZOMBIFY_LEGACY_KEYS.primary, "") end)
    pcall(function() zombie:setVariable(NPC_ACTION_ZOMBIFY_LEGACY_KEYS.secondary, "") end)
    pcall(function() zombie:clearAttachedItems() end)
end

local function removePersistentNpc(zombie)
    if NPCBrainData and NPCBrainData.Remove then pcall(function() NPCBrainData.Remove(zombie) end) end
    clearNpcRuntimeState(zombie)
    pcall(function() zombie:removeFromWorld() end)
    pcall(function() zombie:removeFromSquare() end)
end

local function requestLegacyNPCRemove(zombie)
    if not zombie or not NPCUtils or not NPCUtils.GetCharacterID then return true end
    local id = NPCUtils.GetCharacterID(zombie)
    local args = {}
    args.id = id
    if isClient and isClient() then
        if sendClientCommand and getPlayer then
            sendClientCommand(getPlayer(), 'NPCCommands', NPC_ACTION_ZOMBIFY_LEGACY_COMMANDS.remove, args)
        end
    else
        local serverRuntime = NPCServerRuntime
        if serverRuntime and serverRuntime.Commands and serverRuntime.Commands[NPC_ACTION_ZOMBIFY_LEGACY_COMMANDS.remove] and getPlayer then
            serverRuntime.Commands[NPC_ACTION_ZOMBIFY_LEGACY_COMMANDS.remove](getPlayer(), args)
        end
    end
    return true
end

function NPCActionZombifyBridge.OnStart(zombie, task)
    if zombie and zombie.clearAttachedItems then zombie:clearAttachedItems() end
    return true
end

function NPCActionZombifyBridge.OnWorking(zombie, task)
    if not zombie or not task then return true end
    if task.anim and zombie.getBumpType and zombie:getBumpType() ~= task.anim then return true end
    return false
end

function NPCActionZombifyBridge.OnComplete(zombie, task)
    if not zombie then return true end

    local brain = getBrain(zombie)
    local persistentId, worldGroupId = getPersistentNpcIds(zombie, brain)
    if persistentId or worldGroupId then
        removePersistentNpc(zombie)
        return true
    end

    if ZombieOnGroundState and zombie.changeState then
        zombie:changeState(ZombieOnGroundState.instance())
    end
    return requestLegacyNPCRemove(zombie)
end
