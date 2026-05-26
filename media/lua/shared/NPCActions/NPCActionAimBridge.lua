NPCActionAimBridge = NPCActionAimBridge or {}
require "NPCCore/NPCLegacyGlobalsBridge"

local NPC_ACTION_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
NPCEntity = NPCEntity or NPC_ACTION_LEGACY_GLOBALS.Get("Entity")
NPCBrainData = NPCBrainData or NPC_ACTION_LEGACY_GLOBALS.Get("Brain")
NPCPlayerClient = NPCPlayerClient or NPC_ACTION_LEGACY_GLOBALS.Get("PlayerClient")
NPCFactionBridge = NPCFactionBridge or NPC_ACTION_LEGACY_GLOBALS.Get("Faction")


local function getBrain(character)
    if NPCBrainData and NPCBrainData.Get then
        return NPCBrainData.Get(character)
    end
    return nil
end

local function getTargetPlayer(task)
    if not task or task.targetKind ~= "player" then return nil end
    if not (NPCPlayerClient and NPCPlayerClient.GetPlayerById) then return nil end
    return NPCPlayerClient.GetPlayerById(task.targetId or task.eid)
end

local function canAimAtTarget(character, task)
    local player = getTargetPlayer(task)
    if not player then return true end
    if not (NPCFactionBridge and NPCFactionBridge.IsEnabled and NPCFactionBridge.IsEnabled() and NPCFactionBridge.CanBrainAttackPlayer) then return true end
    return NPCFactionBridge.CanBrainAttackPlayer(getBrain(character), player) == true
end

local function faceTaskLocation(character, task)
    if not character or not task or not task.x or not task.y then return end
    if character.faceLocationF then
        pcall(function() character:faceLocationF(task.x, task.y) end)
    elseif character.faceLocation then
        pcall(function() character:faceLocation(task.x, task.y) end)
    end
end

function NPCActionAimBridge.OnStart(character, task)
    if NPCEntity and NPCEntity.SetAim then
        pcall(function() NPCEntity.SetAim(character, true) end)
    end
    return true
end

function NPCActionAimBridge.OnWorking(character, task)
    if not canAimAtTarget(character, task) then return true end
    if NPCEntity and NPCEntity.SetAim then
        pcall(function() NPCEntity.SetAim(character, true) end)
    end
    faceTaskLocation(character, task)
    if not task or not task.anim then return true end
    local ok, bump = pcall(function() return character:getBumpType() end)
    return not ok or bump ~= task.anim
end

function NPCActionAimBridge.OnComplete(character, task)
    if canAimAtTarget(character, task) and NPCEntity and NPCEntity.SetAim then
        pcall(function() NPCEntity.SetAim(character, true) end)
    end
    return true
end
