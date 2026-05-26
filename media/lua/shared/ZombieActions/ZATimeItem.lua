require "NPCActions/NPCActionTimeItemBridge"

ZombieActions = ZombieActions or {}

ZombieActions.TimeItem = ZombieActions.TimeItem or {}

ZombieActions.TimeItem.onStart = function(zombie, task)
    return NPCActionTimeItemBridge.OnStart(zombie, task)
end

ZombieActions.TimeItem.onWorking = function(zombie, task)
    return NPCActionTimeItemBridge.OnWorking(zombie, task)
end

ZombieActions.TimeItem.onComplete = function(zombie, task)
    return NPCActionTimeItemBridge.OnComplete(zombie, task)
end
