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

local function resolveAimTarget(task)
    if not task then return nil end
    local targetId = task.targetId or task.eid
    if targetId == nil then return nil end

    if task.targetKind == "player" and NPCPlayerClient and NPCPlayerClient.GetPlayerById then
        local ok, player = pcall(function() return NPCPlayerClient.GetPlayerById(targetId) end)
        if ok and player then return player end
    end

    if NPCZombieCacheBridge and NPCZombieCacheBridge.Cache then
        local target = NPCZombieCacheBridge.Cache[targetId] or NPCZombieCacheBridge.Cache[tostring(targetId)]
        if target then return target end
    end

    if task.targetKind ~= "player" and NPCPlayerClient and NPCPlayerClient.GetPlayerById then
        local ok, player = pcall(function() return NPCPlayerClient.GetPlayerById(targetId) end)
        if ok and player then return player end
    end

    return nil
end

local function refreshAimTarget(character, task)
    if not (task and (task.targetId or task.eid)) then return true end
    local target = resolveAimTarget(task)
    if not target then return false end
    if target.isAlive then
        local okAlive, alive = pcall(function() return target:isAlive() end)
        if okAlive and alive == false then return false end
    end
    if character and target.getZ and character.getZ and math.floor(tonumber(character:getZ()) or 0) ~= math.floor(tonumber(target:getZ()) or 0) then
        return false
    end
    if target.getX and target.getY then
        task.x = target:getX()
        task.y = target:getY()
        task.z = target.getZ and target:getZ() or task.z
    end
    return true
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
    if not refreshAimTarget(character, task) then return true end
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
    refreshAimTarget(character, task)
    if canAimAtTarget(character, task) and NPCEntity and NPCEntity.SetAim then
        pcall(function() NPCEntity.SetAim(character, true) end)
    end
    return true
end
