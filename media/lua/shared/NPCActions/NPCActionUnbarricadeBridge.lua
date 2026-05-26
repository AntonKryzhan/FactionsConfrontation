NPCActionUnbarricadeBridge = NPCActionUnbarricadeBridge or {}
require "NPCCore/NPCLegacyGlobalsBridge"

local NPC_ACTION_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
NPCEntity = NPCEntity or NPC_ACTION_LEGACY_GLOBALS.Get("Entity")
NPCUtils = NPCUtils or NPC_ACTION_LEGACY_GLOBALS.Get("Utils")
NPCCompatibilityBridge = NPCCompatibilityBridge or NPC_ACTION_LEGACY_GLOBALS.Get("Compatibility")
NPCNavigationPerformanceBridge = NPCNavigationPerformanceBridge or NPC_ACTION_LEGACY_GLOBALS.Get("NavigationPerformance")


local function ensureTool(zombie, fullType)
    if not zombie or not fullType then return end
    if not (NPCEntity and NPCEntity.Has and NPCEntity.AddLoot) then return end

    local ok, hasItem = pcall(function()
        return NPCEntity.Has(zombie, fullType)
    end)
    if ok and hasItem then return end

    pcall(function()
        NPCEntity.AddLoot(zombie, fullType)
    end)

    if NPCEntity.UpdateItemsToSpawnAtDeath then
        pcall(function()
            NPCEntity.UpdateItemsToSpawnAtDeath(zombie)
        end)
    end
end

local function playSound(zombie, sound)
    if not zombie or not sound or type(zombie.playSound) ~= "function" then return end

    pcall(function()
        zombie:playSound(sound)
    end)
end

local function stopSounds(zombie)
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

local function faceTarget(zombie, task)
    if not zombie or not task then return end

    local x = tonumber(task.fx) or tonumber(task.x)
    local y = tonumber(task.fy) or tonumber(task.y)
    if not x or not y then return end

    if type(zombie.faceLocationF) == "function" then
        pcall(function()
            zombie:faceLocationF(x, y)
        end)
    elseif type(zombie.faceLocation) == "function" then
        pcall(function()
            zombie:faceLocation(x, y)
        end)
    end
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

local function isController(zombie)
    if not (NPCUtils and NPCUtils.IsController) then return false end

    local ok, result = pcall(function()
        return NPCUtils.IsController(zombie)
    end)
    return ok and result == true
end

local function sendUnbarricade(task)
    if not task or not sendClientCommand or not getPlayer then return end

    local player = getPlayer()
    if not player then return end

    local args = {x=task.x, y=task.y, z=task.z, index=task.idx}
    pcall(function()
        sendClientCommand(player, 'NPCCommands', 'Unbarricade', args)
    end)
end

local function dropItem(zombie, fullType)
    if not zombie or not fullType then return end
    if not (NPCCompatibilityBridge and NPCCompatibilityBridge.InstanceItem) then return end
    if type(zombie.getSquare) ~= "function" then return end

    local okItem, item = pcall(function()
        return NPCCompatibilityBridge.InstanceItem(fullType)
    end)
    if not okItem or not item then return end

    local okSquare, square = pcall(function()
        return zombie:getSquare()
    end)
    if not okSquare or not square or type(square.AddWorldInventoryItem) ~= "function" then return end

    local ox = ZombRandFloat and ZombRandFloat(0.3, 0.7) or 0.5
    local oy = ZombRandFloat and ZombRandFloat(0.3, 0.7) or 0.5
    pcall(function()
        square:AddWorldInventoryItem(item, ox, oy, 0)
    end)
end

local function notifyMovement(zombie, task)
    if NPCNavigationPerformanceBridge and NPCNavigationPerformanceBridge.OnPortalTaskComplete then
        pcall(function()
            NPCNavigationPerformanceBridge.OnPortalTaskComplete(zombie, task)
        end)
    end
end

function NPCActionUnbarricadeBridge.OnStart(zombie, task)
    ensureTool(zombie, "Base.Crowbar")
    playSound(zombie, "BeginRemoveBarricadePlank")
    return true
end

function NPCActionUnbarricadeBridge.OnWorking(zombie, task)
    faceTarget(zombie, task)
    if not task or (tonumber(task.time) or 0) <= 0 then return true end
    setWorkingAnim(zombie, task)
    return false
end

function NPCActionUnbarricadeBridge.OnComplete(zombie, task)
    stopSounds(zombie)
    playSound(zombie, "RemoveBarricadePlank")

    if isController(zombie) then
        sendUnbarricade(task)
        dropItem(zombie, "Base.Plank")
    end

    notifyMovement(zombie, task)
    return true
end
