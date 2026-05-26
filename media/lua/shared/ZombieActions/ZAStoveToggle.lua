require "NPCActions/NPCActionStoveToggleBridge"

ZombieActions = ZombieActions or {}

ZombieActions.StoveToggle = ZombieActions.StoveToggle or {}

ZombieActions.StoveToggle.onStart = function(zombie, task)
    return NPCActionStoveToggleBridge.OnStart(zombie, task)
end

ZombieActions.StoveToggle.onWorking = function(zombie, task)
    return NPCActionStoveToggleBridge.OnWorking(zombie, task)
end

ZombieActions.StoveToggle.onComplete = function(zombie, task)
    return NPCActionStoveToggleBridge.OnComplete(zombie, task)
end
