require "NPCActions/NPCActionGoToBridge"

ZombieActions = ZombieActions or {}

ZombieActions.GoTo = ZombieActions.GoTo or {}

ZombieActions.GoTo.onStart = function(zombie, task)
    return NPCActionGoToBridge.OnStart(zombie, task)
end

ZombieActions.GoTo.onWorking = function(zombie, task)
    return NPCActionGoToBridge.OnWorking(zombie, task)
end

ZombieActions.GoTo.onComplete = function(zombie, task)
    return NPCActionGoToBridge.OnComplete(zombie, task)
end
