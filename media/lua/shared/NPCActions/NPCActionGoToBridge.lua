NPCActionGoToBridge = NPCActionGoToBridge or {}
require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCLegacyContractBridge"

local NPC_ACTION_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
NPCEntity = NPCEntity or NPC_ACTION_LEGACY_GLOBALS.Get("Entity")
NPCUtils = NPCUtils or NPC_ACTION_LEGACY_GLOBALS.Get("Utils")
NPCMovementStabilityBridge = NPCMovementStabilityBridge or NPC_ACTION_LEGACY_GLOBALS.Get("MovementStability")


local function zaMoveValid(zombie, task)
    return zombie ~= nil and task ~= nil and task.x ~= nil and task.y ~= nil and task.z ~= nil
end

local function zaMoveController(zombie)
    return NPCUtils and NPCUtils.IsController and NPCUtils.IsController(zombie) == true
end

local function zaMoveDistance(zombie, task)
    local dx = math.abs((zombie:getX() or 0) - tonumber(task.x))
    local dy = math.abs((zombie:getY() or 0) - tonumber(task.y))
    return dx, dy
end

local function zaMoveNormalizeWalk(zombie, task)
    if not zaMoveValid(zombie, task) then return end
    if not task.walkType or task.walkType == "" then task.walkType = "Walk" end

    if task.closeSlow then
        local dx, dy = zaMoveDistance(zombie, task)
        local sameZ = math.floor(zombie:getZ() or 0) == math.floor(tonumber(task.z) or 0)
        if sameZ and dx <= 2 and dy <= 2 then
            task.walkType = "WalkAim"
        elseif sameZ and dx <= 3 and dy <= 3 then
            task.walkType = "Walk"
        end
    end

    if zombie.setVariable then
        pcall(function() zombie:setVariable(NPCLegacyContractBridge.Key("WALK_TYPE"), task.walkType) end)
    end
end

local function zaMoveBeginMotion(zombie, task)
    if not zaMoveValid(zombie, task) then return end
    local moving = NPCEntity and NPCEntity.IsMoving and NPCEntity.IsMoving(zombie) == true
    if not moving then
        local distance
        if NPCUtils and NPCUtils.DistTo then
            distance = NPCUtils.DistTo(zombie:getX(), zombie:getY(), task.x, task.y)
        else
            local dx, dy = zaMoveDistance(zombie, task)
            distance = math.sqrt(dx * dx + dy * dy)
        end

        if distance and distance > 2 and zombie.setBumpType then
            local bump = task.walkType == "Run" and "IdleToRun" or task.walkType == "Walk" and "IdleToWalk" or nil
            if bump then pcall(function() zombie:setBumpType(bump) end) end
        end

        if NPCEntity and NPCEntity.SetMoving then pcall(function() NPCEntity.SetMoving(zombie, true) end) end
        return
    end

    if task.walkType ~= "Run" or not (NPCUtils and NPCUtils.CalcAngle) then return end
    local faceDir = zombie.getDirectionAngle and zombie:getDirectionAngle() or 0
    local targetDir = NPCUtils.CalcAngle(zombie:getX(), zombie:getY(), task.x, task.y)
    local delta = faceDir - targetDir
    if delta > 180 then delta = delta - 360 elseif delta < -180 then delta = delta + 360 end
    if math.abs(delta) > 130 then
        if zombie.faceLocation then pcall(function() zombie:faceLocation(task.x, task.y) end) end
        if zombie.setBumpType then pcall(function() zombie:setBumpType("IdleToRun") end) end
    end
end

local function zaMoveStartPath(zombie, task, useFloatPath)
    if not zaMoveController(zombie) or not zaMoveValid(zombie, task) then return end
    local dx, dy = zaMoveDistance(zombie, task)
    if dx <= 0.02 and dy <= 0.02 and math.floor(zombie:getZ() or 0) == math.floor(tonumber(task.z) or 0) then return end

    if NPCMovementStabilityBridge and NPCMovementStabilityBridge.StartPath then
        NPCMovementStabilityBridge.StartPath(zombie, task, true)
        return
    end

    local behavior = zombie.getPathFindBehavior2 and zombie:getPathFindBehavior2() or nil
    if not behavior then return end

    if task.vehiclePartArea then
        local square = getCell and getCell():getGridSquare(task.x, task.y, task.z) or nil
        local vehicle = square and square:getVehicleContainer() or nil
        if vehicle and behavior.pathToVehicleArea then
            pcall(function() behavior:pathToVehicleArea(vehicle, task.vehiclePartArea) end)
        end
    elseif useFloatPath and zombie.pathToLocationF then
        pcall(function() zombie:pathToLocationF(task.x + 0.5, task.y + 0.5, task.z) end)
    elseif behavior.pathToLocation then
        pcall(function() behavior:pathToLocation(task.x, task.y, task.z) end)
    end
end

local function zaMoveUpdatePath(zombie, task)
    if not zaMoveController(zombie) then return false end
    if NPCMovementStabilityBridge and NPCMovementStabilityBridge.UpdatePath then
        return NPCMovementStabilityBridge.UpdatePath(zombie, task) == true
    end

    local behavior = zombie and zombie.getPathFindBehavior2 and zombie:getPathFindBehavior2() or nil
    if behavior and behavior.update then
        local ok, result = pcall(function() return behavior:update() end)
        if ok and (result == BehaviorResult.Failed or result == BehaviorResult.Succeeded) then return true end
    end
    return false
end

local function zaMoveFallbackWorking(zombie, task)
    if NPCMovementStabilityBridge and NPCMovementStabilityBridge.OnMoveWorking then
        return NPCMovementStabilityBridge.OnMoveWorking(zombie, task)
    end
    return false
end

local function zaMoveFinish(zombie, task)
    if NPCMovementStabilityBridge and NPCMovementStabilityBridge.OnMoveComplete then
        return NPCMovementStabilityBridge.OnMoveComplete(zombie, task)
    end
    if zaMoveController(zombie) then
        local behavior = zombie and zombie.getPathFindBehavior2 and zombie:getPathFindBehavior2() or nil
        if behavior then
            if behavior.cancel then pcall(function() behavior:cancel() end) end
            if behavior.reset then pcall(function() behavior:reset() end) end
        end
    end
    return true
end

NPCActionGoToBridge.OnStart = function(zombie, task)
    if not zaMoveValid(zombie, task) then return true end
    if NPCMovementStabilityBridge and NPCMovementStabilityBridge.Prepare then
        NPCMovementStabilityBridge.Prepare(zombie, task, "GoTo")
    end
    zaMoveNormalizeWalk(zombie, task)
    zaMoveBeginMotion(zombie, task)
    zaMoveStartPath(zombie, task, true)
    return true
end

NPCActionGoToBridge.OnWorking = function(zombie, task)
    if not zaMoveValid(zombie, task) then return true end
    zaMoveNormalizeWalk(zombie, task)
    if zaMoveUpdatePath(zombie, task) then return true end
    return zaMoveFallbackWorking(zombie, task)
end

NPCActionGoToBridge.OnComplete = function(zombie, task)
    return zaMoveFinish(zombie, task)
end
