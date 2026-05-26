require "NPCActions/NPCActionShootBridge"

ZombieActions = ZombieActions or {}

ZombieActions.Shoot = ZombieActions.Shoot or {}

ZombieActions.Shoot.onStart = function(zombie, task)
    return NPCActionShootBridge.OnStart(zombie, task)
end

ZombieActions.Shoot.onWorking = function(zombie, task)
    return NPCActionShootBridge.OnWorking(zombie, task)
end

ZombieActions.Shoot.onComplete = function(zombie, task)
    return NPCActionShootBridge.OnComplete(zombie, task)
end
