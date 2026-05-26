require "NPCActions/NPCActionReloadBridge"

ZombieActions = ZombieActions or {}

ZombieActions.Reload = ZombieActions.Reload or {}

ZombieActions.Reload.onStart = function(zombie, task)
    return NPCActionReloadBridge.OnStart(zombie, task)
end

ZombieActions.Reload.onWorking = function(zombie, task)
    return NPCActionReloadBridge.OnWorking(zombie, task)
end

ZombieActions.Reload.onComplete = function(zombie, task)
    return NPCActionReloadBridge.OnComplete(zombie, task)
end
