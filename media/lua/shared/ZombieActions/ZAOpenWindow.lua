require "NPCActions/NPCActionOpenWindowBridge"

ZombieActions = ZombieActions or {}

ZombieActions.OpenWindow = ZombieActions.OpenWindow or {}

ZombieActions.OpenWindow.onStart = function(zombie, task)
    return NPCActionOpenWindowBridge.OnStart(zombie, task)
end

ZombieActions.OpenWindow.onWorking = function(zombie, task)
    return NPCActionOpenWindowBridge.OnWorking(zombie, task)
end

ZombieActions.OpenWindow.onComplete = function(zombie, task)
    return NPCActionOpenWindowBridge.OnComplete(zombie, task)
end
