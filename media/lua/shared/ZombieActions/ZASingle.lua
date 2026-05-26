require "NPCActions/NPCActionSingleBridge"

ZombieActions = ZombieActions or {}

ZombieActions.Single = ZombieActions.Single or {}

ZombieActions.Single.onStart = function(zombie, task)
    return NPCActionSingleBridge.OnStart(zombie, task)
end

ZombieActions.Single.onWorking = function(zombie, task)
    return NPCActionSingleBridge.OnWorking(zombie, task)
end

ZombieActions.Single.onComplete = function(zombie, task)
    return NPCActionSingleBridge.OnComplete(zombie, task)
end
