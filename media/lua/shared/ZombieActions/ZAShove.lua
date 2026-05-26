require "NPCActions/NPCActionShoveBridge"

ZombieActions = ZombieActions or {}

ZombieActions.Shove = ZombieActions.Shove or {}

ZombieActions.Shove.onStart = function(zombie, task)
    return NPCActionShoveBridge.OnStart(zombie, task)
end

ZombieActions.Shove.onWorking = function(zombie, task)
    return NPCActionShoveBridge.OnWorking(zombie, task)
end

ZombieActions.Shove.onComplete = function(zombie, task)
    return NPCActionShoveBridge.OnComplete(zombie, task)
end
