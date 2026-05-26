require "NPCActions/NPCActionBandageBridge"

ZombieActions = ZombieActions or {}

ZombieActions.Bandage = ZombieActions.Bandage or {}

ZombieActions.Bandage.onStart = function(zombie, task)
    return NPCActionBandageBridge.OnStart(zombie, task)
end

ZombieActions.Bandage.onWorking = function(zombie, task)
    return NPCActionBandageBridge.OnWorking(zombie, task)
end

ZombieActions.Bandage.onComplete = function(zombie, task)
    return NPCActionBandageBridge.OnComplete(zombie, task)
end
