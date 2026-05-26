require "NPCActions/NPCActionGeneratorRefillBridge"

ZombieActions = ZombieActions or {}

ZombieActions.GeneratorRefill = ZombieActions.GeneratorRefill or {}

ZombieActions.GeneratorRefill.onStart = function(zombie, task)
    return NPCActionGeneratorRefillBridge.OnStart(zombie, task)
end

ZombieActions.GeneratorRefill.onWorking = function(zombie, task)
    return NPCActionGeneratorRefillBridge.OnWorking(zombie, task)
end

ZombieActions.GeneratorRefill.onComplete = function(zombie, task)
    return NPCActionGeneratorRefillBridge.OnComplete(zombie, task)
end
