require "NPCActions/NPCActionTakeFromContainerBridge"

ZombieActions = ZombieActions or {}

ZombieActions.TakeFromContainer = ZombieActions.TakeFromContainer or {}

ZombieActions.TakeFromContainer.onStart = function(zombie, task)
    return NPCActionTakeFromContainerBridge.OnStart(zombie, task)
end

ZombieActions.TakeFromContainer.onWorking = function(zombie, task)
    return NPCActionTakeFromContainerBridge.OnWorking(zombie, task)
end

ZombieActions.TakeFromContainer.onComplete = function(zombie, task)
    return NPCActionTakeFromContainerBridge.OnComplete(zombie, task)
end
