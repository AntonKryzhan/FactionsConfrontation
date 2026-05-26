require "NPCActions/NPCActionPutInContainerBridge"

ZombieActions = ZombieActions or {}

ZombieActions.PutInContainer = ZombieActions.PutInContainer or {}

ZombieActions.PutInContainer.onStart = function(zombie, task)
    return NPCActionPutInContainerBridge.OnStart(zombie, task)
end

ZombieActions.PutInContainer.onWorking = function(zombie, task)
    return NPCActionPutInContainerBridge.OnWorking(zombie, task)
end

ZombieActions.PutInContainer.onComplete = function(zombie, task)
    return NPCActionPutInContainerBridge.OnComplete(zombie, task)
end
