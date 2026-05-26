require "NPCActions/NPCActionSleepBridge"

ZombieActions = ZombieActions or {}

ZombieActions.Sleep = ZombieActions.Sleep or {}

ZombieActions.Sleep.onStart = function(zombie, task)
    return NPCActionSleepBridge.OnStart(zombie, task)
end

ZombieActions.Sleep.onWorking = function(zombie, task)
    return NPCActionSleepBridge.OnWorking(zombie, task)
end

ZombieActions.Sleep.onComplete = function(zombie, task)
    return NPCActionSleepBridge.OnComplete(zombie, task)
end
