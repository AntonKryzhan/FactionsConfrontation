NPCActionDestroyBridge = NPCActionDestroyBridge or {}
require "NPCCore/NPCLegacyGlobalsBridge"

local NPC_ACTION_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
NPCEntity = NPCEntity or NPC_ACTION_LEGACY_GLOBALS.Get("Entity")
NPCUtils = NPCUtils or NPC_ACTION_LEGACY_GLOBALS.Get("Utils")
NPCNavigationPerformanceBridge = NPCNavigationPerformanceBridge or NPC_ACTION_LEGACY_GLOBALS.Get("NavigationPerformance")


local function getObjects(square)
    return square and square.getObjects and square:getObjects() or nil
end

local function getSpecialObjects(square)
    return square and square.getSpecialObjects and square:getSpecialObjects() or nil
end

local function isDoorLike(object)
    if not object or not instanceof then return false end
    if instanceof(object, "IsoDoor") then return true end
    if instanceof(object, "IsoThumpable") then return true end
    return false
end

local function isDoorObject(object)
    if not object or not instanceof then return false end
    if instanceof(object, "IsoDoor") then return true end
    if instanceof(object, "IsoThumpable") then
        local okDoor, isDoor = pcall(function()
            return object.isDoor and object:isDoor() == true
        end)
        return okDoor and isDoor == true
    end
    return false
end

local function isDoorOpen(object)
    if not isDoorObject(object) or not object.IsOpen then return false end
    local ok, open = pcall(function() return object:IsOpen() == true end)
    return ok and open == true
end

local function isDoorBarricaded(object)
    if not isDoorObject(object) then return true end
    if object.isBarricaded then
        local ok, barricaded = pcall(function() return object:isBarricaded() == true end)
        if ok and barricaded == true then return true end
    end
    return false
end

local function canOpenDoorLikePlayer(object)
    if not isDoorObject(object) then return false end
    if isDoorOpen(object) then return true end
    if isDoorBarricaded(object) then return false end
    return true
end

local function findCandidate(square, task)
    if not square then return nil end

    local objects = getObjects(square)
    local idx = task and tonumber(task.idx) or nil
    if objects and idx and idx >= 0 and idx < objects:size() then
        local object = objects:get(idx)
        if isDoorLike(object) then return object end
    end

    if square.getIsoDoor then
        local door = square:getIsoDoor()
        if door then return door end
    end

    local special = getSpecialObjects(square)
    if special then
        for i = 0, special:size() - 1 do
            local object = special:get(i)
            if isDoorLike(object) then return object end
        end
    end

    if objects then
        for i = 0, objects:size() - 1 do
            local object = objects:get(i)
            if isDoorLike(object) then return object end
        end
    end
    return nil
end

local function applyDamage(object, zombie, value)
    if not object then return end

    local damage = tonumber(value) or 40
    local okHealth, health = pcall(function()
        return object:getHealth()
    end)
    health = okHealth and tonumber(health) or damage
    local remaining = math.max(0, health - damage)

    if remaining <= 0 then
        if object.destroy then
            pcall(function()
                object:destroy()
            end)
        end
    else
        if object.setHealth then
            pcall(function()
                object:setHealth(remaining)
            end)
        end
        if object.Thump then
            pcall(function()
                object:Thump(zombie)
            end)
        end
    end
end

local function getTaskSquare(zombie, task)
    if not task or task.x == nil or task.y == nil or task.z == nil then return nil end

    local cell = getCell and getCell() or nil
    if not cell and zombie and zombie.getSquare and zombie:getSquare() then
        cell = zombie:getSquare():getCell()
    end
    return cell and cell:getGridSquare(task.x, task.y, task.z) or nil
end

local function sendDestroyCommand(task)
    if not task or not sendClientCommand or not getPlayer then return false end

    local player = getPlayer()
    if not player then return false end

    local args = {x=task.x, y=task.y, z=task.z, index=task.idx or -1, damage=task.damage or 40}
    local ok = pcall(function()
        sendClientCommand(player, 'NPCCommands', 'DestroyObject', args)
    end)
    return ok == true
end

local function sendOpenDoorCommand(task)
    if not task or not sendClientCommand or not getPlayer then return false end

    local player = getPlayer()
    if not player then return false end

    local args = {x=task.x, y=task.y, z=task.z, index=task.idx or -1}
    local ok = pcall(function()
        sendClientCommand(player, 'NPCCommands', 'OpenDoor', args)
    end)
    return ok == true
end

local function openDoorLocal(object)
    if not canOpenDoorLikePlayer(object) or isDoorOpen(object) then return false end

    pcall(function() if object.setLocked then object:setLocked(false) end end)
    pcall(function() if object.setLockedByKey then object:setLockedByKey(false) end end)
    pcall(function() if object.setPermaLocked then object:setPermaLocked(false) end end)
    pcall(function() if object.setLockedByPadlock then object:setLockedByPadlock(false) end end)

    if object.ToggleDoorSilent then
        pcall(function() object:ToggleDoorSilent() end)
        return true
    end
    if object.ToggleDoor then
        pcall(function() object:ToggleDoor(nil) end)
        return true
    end
    return false
end

local function isController(zombie)
    return NPCUtils and NPCUtils.IsController and NPCUtils.IsController(zombie) == true
end

local function faceTask(zombie, task)
    if zombie and task and task.x and task.y and zombie.faceLocationF then
        pcall(function()
            zombie:faceLocationF(task.x, task.y)
        end)
    end
end

local function isAnimationFinished(zombie, task)
    if not task or not task.anim then return true end

    local ok, bump = pcall(function()
        return zombie:getBumpType()
    end)
    return not ok or bump ~= task.anim
end

local function notifyPortalComplete(zombie, task)
    if NPCNavigationPerformanceBridge and NPCNavigationPerformanceBridge.OnPortalTaskComplete then
        pcall(function()
            NPCNavigationPerformanceBridge.OnPortalTaskComplete(zombie, task)
        end)
    end
end

function NPCActionDestroyBridge.OnStart(zombie, task)
    if NPCEntity and NPCEntity.Say then
        pcall(function()
            NPCEntity.Say(zombie, "BREACH")
        end)
    end
    return true
end

function NPCActionDestroyBridge.OnWorking(zombie, task)
    faceTask(zombie, task)
    return isAnimationFinished(zombie, task)
end

function NPCActionDestroyBridge.OnComplete(zombie, task)
    local square = getTaskSquare(zombie, task)
    local object = findCandidate(square, task)

    -- Stage447: living NPCs should treat normal doors as usable portals first.
    -- The old Destroy task is still kept for barricaded/blocked doors and generic thumpables.
    if canOpenDoorLikePlayer(object) and not isDoorOpen(object) then
        local sentOpen = isController(zombie) and isClient and isClient() and sendOpenDoorCommand(task)
        if not sentOpen then
            openDoorLocal(object)
        end
        notifyPortalComplete(zombie, task)
        return true
    end

    local sent = isController(zombie) and isClient and isClient() and sendDestroyCommand(task)
    if not sent then
        applyDamage(object, zombie, task and task.damage or 40)
    end

    notifyPortalComplete(zombie, task)
    return true
end
