require "NPCActions/NPCActionAimBridge"

ZombieActions = ZombieActions or {}

ZombieActions.Aim = ZombieActions.Aim or {}

ZombieActions.Aim.onStart = function(zombie, task)
    return NPCActionAimBridge.OnStart(zombie, task)
end

ZombieActions.Aim.onWorking = function(zombie, task)
    return NPCActionAimBridge.OnWorking(zombie, task)
end

ZombieActions.Aim.onComplete = function(zombie, task)
    return NPCActionAimBridge.OnComplete(zombie, task)
end
