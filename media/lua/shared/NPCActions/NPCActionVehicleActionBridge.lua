NPCActionVehicleActionBridge = NPCActionVehicleActionBridge or {}
require "NPCCore/NPCLegacyGlobalsBridge"

local NPC_ACTION_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
NPCUtils = NPCUtils or NPC_ACTION_LEGACY_GLOBALS.Get("Utils")


local function zaVehicleSquare(task)
    if not task or not getCell or task.vx == nil or task.vy == nil then return nil end
    local cell = getCell()
    if not cell then return nil end
    return cell:getGridSquare(task.vx, task.vy, task.vz or 0)
end

local function zaVehicleResolve(task)
    local square = zaVehicleSquare(task)
    if not square or not square.getVehicleContainer then return nil end
    return square:getVehicleContainer()
end

local function zaVehicleIsWheelArea(area)
    return area == "TireRearLeft" or area == "TireRearRight" or area == "TireFrontLeft" or area == "TireFrontRight"
end

local function zaVehicleFace(zombie, task)
    if not zombie or not task then return end
    local x = tonumber(task.px) or tonumber(task.vx)
    local y = tonumber(task.py) or tonumber(task.vy)
    if not x or not y then return end
    if zombie.faceLocation then pcall(function() zombie:faceLocation(x, y) end) end
end

local function zaVehicleSetAnim(zombie, task, vehicle)
    if not zombie or not task or not vehicle then return end
    local anim = zaVehicleIsWheelArea(task.area) and "LootLow" or "Loot"
    task.anim = task.anim or anim
    if not zaVehicleIsWheelArea(task.area) and zombie.playSound then
        pcall(function() zombie:playSound("VehicleHoodOpen") end)
    end
    if zombie.setBumpType then pcall(function() zombie:setBumpType(task.anim) end) end
end

local function zaVehicleDropItem(zombie, item)
    if not zombie or not item or not (NPCUtils and NPCUtils.IsController and NPCUtils.IsController(zombie)) then return end
    local square = zombie.getSquare and zombie:getSquare() or nil
    if not square or not square.AddWorldInventoryItem then return end
    local ox = ZombRandFloat and ZombRandFloat(0.2, 0.8) or 0.5
    local oy = ZombRandFloat and ZombRandFloat(0.2, 0.8) or 0.5
    pcall(function() square:AddWorldInventoryItem(item, ox, oy, 0) end)
end

local function zaVehicleTellServer(task)
    if not task or not sendClientCommand or not getPlayer then return end
    local player = getPlayer()
    if not player then return end
    local args = {x=task.vx, y=task.vy, id=task.id}
    pcall(function() sendClientCommand(player, 'NPCCommands', 'VehiclePartRemove', args) end)
end


NPCActionVehicleActionBridge.OnStart = function(zombie, task)
    zaVehicleSetAnim(zombie, task, zaVehicleResolve(task))
    return true
end

NPCActionVehicleActionBridge.OnWorking = function(zombie, task)
    zaVehicleFace(zombie, task)
    if not task or not task.anim then return true end
    local ok, bump = pcall(function() return zombie:getBumpType() end)
    return not ok or bump ~= task.anim
end

NPCActionVehicleActionBridge.OnComplete = function(zombie, task)
    local vehicle = zaVehicleResolve(task)
    if not vehicle or not task or not task.id then return true end
    local part = vehicle:getPartById(task.id)
    if not part or task.subaction ~= "Uninstall" then return true end

    local item = part:getInventoryItem()
    if not item then return true end

    zaVehicleDropItem(zombie, item)

    if zaVehicleIsWheelArea(task.area) then
        pcall(function() part:setModelVisible("InflatedTirePlusWheel", false) end)
        if part.getWheelIndex and vehicle.setTireRemoved then
            pcall(function() vehicle:setTireRemoved(part:getWheelIndex(), true) end)
        end
    end

    if vehicle.updatePartStats then pcall(function() vehicle:updatePartStats() end) end
    zaVehicleTellServer(task)
    return true
end
