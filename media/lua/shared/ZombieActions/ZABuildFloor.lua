require "NPCActions/NPCActionBuildFloorBridge"

ZombieActions = ZombieActions or {}

ZombieActions.BuildFloor = ZombieActions.BuildFloor or {}

ZombieActions.BuildFloor.onStart = function(zombie, task)
    return NPCActionBuildFloorBridge.OnStart(zombie, task)
end

ZombieActions.BuildFloor.onWorking = function(zombie, task)
    return NPCActionBuildFloorBridge.OnWorking(zombie, task)
end

ZombieActions.BuildFloor.onComplete = function(zombie, task)
    return NPCActionBuildFloorBridge.OnComplete(zombie, task)
end
