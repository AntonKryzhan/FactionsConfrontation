require "NPCActions/NPCActionSmashWindowBridge"

ZombieActions = ZombieActions or {}

ZombieActions.SmashWindow = ZombieActions.SmashWindow or {}

ZombieActions.SmashWindow.onStart = function(zombie, task)
    return NPCActionSmashWindowBridge.OnStart(zombie, task)
end

ZombieActions.SmashWindow.onWorking = function(zombie, task)
    return NPCActionSmashWindowBridge.OnWorking(zombie, task)
end

ZombieActions.SmashWindow.onComplete = function(zombie, task)
    return NPCActionSmashWindowBridge.OnComplete(zombie, task)
end
