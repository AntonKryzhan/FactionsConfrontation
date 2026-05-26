require "NPCActions/NPCActionLightToggleBridge"

ZombieActions = ZombieActions or {}

ZombieActions.LightToggle = ZombieActions.LightToggle or {}

ZombieActions.LightToggle.onStart = function(zombie, task)
    return NPCActionLightToggleBridge.OnStart(zombie, task)
end

ZombieActions.LightToggle.onWorking = function(zombie, task)
    return NPCActionLightToggleBridge.OnWorking(zombie, task)
end

ZombieActions.LightToggle.onComplete = function(zombie, task)
    return NPCActionLightToggleBridge.OnComplete(zombie, task)
end
