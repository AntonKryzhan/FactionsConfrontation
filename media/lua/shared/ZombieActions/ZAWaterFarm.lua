require "NPCActions/NPCActionWaterFarmBridge"

ZombieActions = ZombieActions or {}

ZombieActions.WaterFarm = ZombieActions.WaterFarm or {}

ZombieActions.WaterFarm.onStart = function(zombie, task)
    return NPCActionWaterFarmBridge.OnStart(zombie, task)
end

ZombieActions.WaterFarm.onWorking = function(zombie, task)
    return NPCActionWaterFarmBridge.OnWorking(zombie, task)
end

ZombieActions.WaterFarm.onComplete = function(zombie, task)
    return NPCActionWaterFarmBridge.OnComplete(zombie, task)
end
