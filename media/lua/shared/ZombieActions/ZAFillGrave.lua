require "NPCActions/NPCActionFillGraveBridge"

ZombieActions = ZombieActions or {}

ZombieActions.FillGrave = ZombieActions.FillGrave or {}

ZombieActions.FillGrave.onStart = function(zombie, task)
    return NPCActionFillGraveBridge.OnStart(zombie, task)
end

ZombieActions.FillGrave.onWorking = function(zombie, task)
    return NPCActionFillGraveBridge.OnWorking(zombie, task)
end

ZombieActions.FillGrave.onComplete = function(zombie, task)
    return NPCActionFillGraveBridge.OnComplete(zombie, task)
end
