require "NPCActions/NPCActionGeneratorFixBridge"

ZombieActions = ZombieActions or {}

ZombieActions.GeneratorFix = ZombieActions.GeneratorFix or {}

ZombieActions.GeneratorFix.onStart = function(zombie, task)
    return NPCActionGeneratorFixBridge.OnStart(zombie, task)
end

ZombieActions.GeneratorFix.onWorking = function(zombie, task)
    return NPCActionGeneratorFixBridge.OnWorking(zombie, task)
end

ZombieActions.GeneratorFix.onComplete = function(zombie, task)
    return NPCActionGeneratorFixBridge.OnComplete(zombie, task)
end
