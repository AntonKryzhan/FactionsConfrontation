require "NPCActions/NPCActionGeneratorToggleBridge"

ZombieActions = ZombieActions or {}

ZombieActions.GeneratorToggle = ZombieActions.GeneratorToggle or {}

ZombieActions.GeneratorToggle.onStart = function(zombie, task)
    return NPCActionGeneratorToggleBridge.OnStart(zombie, task)
end

ZombieActions.GeneratorToggle.onWorking = function(zombie, task)
    return NPCActionGeneratorToggleBridge.OnWorking(zombie, task)
end

ZombieActions.GeneratorToggle.onComplete = function(zombie, task)
    return NPCActionGeneratorToggleBridge.OnComplete(zombie, task)
end
