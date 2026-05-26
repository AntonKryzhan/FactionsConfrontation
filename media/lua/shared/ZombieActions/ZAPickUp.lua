require "NPCActions/NPCActionPickUpBridge"

ZombieActions = ZombieActions or {}

ZombieActions.PickUp = ZombieActions.PickUp or {}

ZombieActions.PickUp.onStart = function(zombie, task)
    return NPCActionPickUpBridge.OnStart(zombie, task)
end

ZombieActions.PickUp.onWorking = function(zombie, task)
    return NPCActionPickUpBridge.OnWorking(zombie, task)
end

ZombieActions.PickUp.onComplete = function(zombie, task)
    return NPCActionPickUpBridge.OnComplete(zombie, task)
end
