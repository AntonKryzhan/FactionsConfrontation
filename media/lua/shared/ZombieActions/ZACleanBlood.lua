require "NPCActions/NPCActionCleanBloodBridge"

ZombieActions = ZombieActions or {}

ZombieActions.CleanBlood = ZombieActions.CleanBlood or {}

ZombieActions.CleanBlood.onStart = function(zombie, task)
    return NPCActionCleanBloodBridge.OnStart(zombie, task)
end

ZombieActions.CleanBlood.onWorking = function(zombie, task)
    return NPCActionCleanBloodBridge.OnWorking(zombie, task)
end

ZombieActions.CleanBlood.onComplete = function(zombie, task)
    return NPCActionCleanBloodBridge.OnComplete(zombie, task)
end
