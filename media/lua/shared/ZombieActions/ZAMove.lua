require "NPCActions/NPCActionMoveBridge"

ZombieActions = ZombieActions or {}

ZombieActions.Move = ZombieActions.Move or {}

ZombieActions.Move.onStart = function(zombie, task)
    return NPCActionMoveBridge.OnStart(zombie, task)
end

ZombieActions.Move.onWorking = function(zombie, task)
    return NPCActionMoveBridge.OnWorking(zombie, task)
end

ZombieActions.Move.onComplete = function(zombie, task)
    return NPCActionMoveBridge.OnComplete(zombie, task)
end
