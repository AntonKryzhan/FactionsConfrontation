require "NPCActions/NPCActionWashBridge"

ZombieActions = ZombieActions or {}

ZombieActions.Wash = ZombieActions.Wash or {}

ZombieActions.Wash.onStart = function(zombie, task)
    return NPCActionWashBridge.OnStart(zombie, task)
end

ZombieActions.Wash.onWorking = function(zombie, task)
    return NPCActionWashBridge.OnWorking(zombie, task)
end

ZombieActions.Wash.onComplete = function(zombie, task)
    return NPCActionWashBridge.OnComplete(zombie, task)
end
