require "NPCActions/NPCActionTimeBridge"

ZombieActions = ZombieActions or {}

ZombieActions.Time = ZombieActions.Time or {}

ZombieActions.Time.onStart = function(zombie, task)
    return NPCActionTimeBridge.OnStart(zombie, task)
end

ZombieActions.Time.onWorking = function(zombie, task)
    return NPCActionTimeBridge.OnWorking(zombie, task)
end

ZombieActions.Time.onComplete = function(zombie, task)
    return NPCActionTimeBridge.OnComplete(zombie, task)
end
