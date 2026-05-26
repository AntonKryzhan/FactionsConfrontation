require "NPCActions/NPCActionDieBridge"

ZombieActions = ZombieActions or {}

ZombieActions.Die = ZombieActions.Die or {}

ZombieActions.Die.onStart = function(zombie, task)
    return NPCActionDieBridge.OnStart(zombie, task)
end

ZombieActions.Die.onWorking = function(zombie, task)
    return NPCActionDieBridge.OnWorking(zombie, task)
end

ZombieActions.Die.onComplete = function(zombie, task)
    return NPCActionDieBridge.OnComplete(zombie, task)
end
