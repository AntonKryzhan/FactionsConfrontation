require "NPCActions/NPCActionDropBridge"

ZombieActions = ZombieActions or {}

ZombieActions.Drop = ZombieActions.Drop or {}

ZombieActions.Drop.onStart = function(zombie, task)
    return NPCActionDropBridge.OnStart(zombie, task)
end

ZombieActions.Drop.onWorking = function(zombie, task)
    return NPCActionDropBridge.OnWorking(zombie, task)
end

ZombieActions.Drop.onComplete = function(zombie, task)
    return NPCActionDropBridge.OnComplete(zombie, task)
end
