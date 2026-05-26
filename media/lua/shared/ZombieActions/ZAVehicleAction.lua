require "NPCActions/NPCActionVehicleActionBridge"

ZombieActions = ZombieActions or {}

ZombieActions.VehicleAction = ZombieActions.VehicleAction or {}

ZombieActions.VehicleAction.onStart = function(zombie, task)
    return NPCActionVehicleActionBridge.OnStart(zombie, task)
end

ZombieActions.VehicleAction.onWorking = function(zombie, task)
    return NPCActionVehicleActionBridge.OnWorking(zombie, task)
end

ZombieActions.VehicleAction.onComplete = function(zombie, task)
    return NPCActionVehicleActionBridge.OnComplete(zombie, task)
end
