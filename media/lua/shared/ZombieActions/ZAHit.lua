require "NPCActions/NPCActionHitBridge"

ZombieActions = ZombieActions or {}

ZombieActions.Hit = ZombieActions.Hit or {}

ZombieActions.Hit.onStart = function(zombie, task)
    return NPCActionHitBridge.OnStart(zombie, task)
end

ZombieActions.Hit.onWorking = function(zombie, task)
    return NPCActionHitBridge.OnWorking(zombie, task)
end

ZombieActions.Hit.onComplete = function(zombie, task)
    return NPCActionHitBridge.OnComplete(zombie, task)
end
