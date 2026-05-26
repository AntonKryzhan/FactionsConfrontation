require "NPCActions/NPCActionZombifyBridge"

ZombieActions = ZombieActions or {}

ZombieActions.Zombify = ZombieActions.Zombify or {}

ZombieActions.Zombify.onStart = function(zombie, task)
    return NPCActionZombifyBridge.OnStart(zombie, task)
end

ZombieActions.Zombify.onWorking = function(zombie, task)
    return NPCActionZombifyBridge.OnWorking(zombie, task)
end

ZombieActions.Zombify.onComplete = function(zombie, task)
    return NPCActionZombifyBridge.OnComplete(zombie, task)
end
