require "NPCActions/NPCActionPickUpBodyBridge"

ZombieActions = ZombieActions or {}

ZombieActions.PickUpBody = ZombieActions.PickUpBody or {}

ZombieActions.PickUpBody.onStart = function(zombie, task)
    return NPCActionPickUpBodyBridge.OnStart(zombie, task)
end

ZombieActions.PickUpBody.onWorking = function(zombie, task)
    return NPCActionPickUpBodyBridge.OnWorking(zombie, task)
end

ZombieActions.PickUpBody.onComplete = function(zombie, task)
    return NPCActionPickUpBodyBridge.OnComplete(zombie, task)
end
