require "NPCActions/NPCActionDestroyBridge"

ZombieActions = ZombieActions or {}

ZombieActions.Destroy = ZombieActions.Destroy or {}

ZombieActions.Destroy.onStart = function(zombie, task)
    return NPCActionDestroyBridge.OnStart(zombie, task)
end

ZombieActions.Destroy.onWorking = function(zombie, task)
    return NPCActionDestroyBridge.OnWorking(zombie, task)
end

ZombieActions.Destroy.onComplete = function(zombie, task)
    return NPCActionDestroyBridge.OnComplete(zombie, task)
end
