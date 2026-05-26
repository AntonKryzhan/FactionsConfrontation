require "NPCActions/NPCActionFillWaterBridge"

ZombieActions = ZombieActions or {}

ZombieActions.FillWater = ZombieActions.FillWater or {}

ZombieActions.FillWater.onStart = function(zombie, task)
    return NPCActionFillWaterBridge.OnStart(zombie, task)
end

ZombieActions.FillWater.onWorking = function(zombie, task)
    return NPCActionFillWaterBridge.OnWorking(zombie, task)
end

ZombieActions.FillWater.onComplete = function(zombie, task)
    return NPCActionFillWaterBridge.OnComplete(zombie, task)
end
