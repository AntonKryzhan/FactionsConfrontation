require "NPCActions/NPCActionFishingBridge"

ZombieActions = ZombieActions or {}

ZombieActions.Fishing = ZombieActions.Fishing or {}

ZombieActions.Fishing.onStart = function(zombie, task)
    return NPCActionFishingBridge.OnStart(zombie, task)
end

ZombieActions.Fishing.onWorking = function(zombie, task)
    return NPCActionFishingBridge.OnWorking(zombie, task)
end

ZombieActions.Fishing.onComplete = function(zombie, task)
    return NPCActionFishingBridge.OnComplete(zombie, task)
end
