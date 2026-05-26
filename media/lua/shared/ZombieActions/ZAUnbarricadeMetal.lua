require "NPCActions/NPCActionUnbarricadeMetalBridge"

ZombieActions = ZombieActions or {}

ZombieActions.UnbarricadeMetal = ZombieActions.UnbarricadeMetal or {}

ZombieActions.UnbarricadeMetal.onStart = function(zombie, task)
    return NPCActionUnbarricadeMetalBridge.OnStart(zombie, task)
end

ZombieActions.UnbarricadeMetal.onWorking = function(zombie, task)
    return NPCActionUnbarricadeMetalBridge.OnWorking(zombie, task)
end

ZombieActions.UnbarricadeMetal.onComplete = function(zombie, task)
    return NPCActionUnbarricadeMetalBridge.OnComplete(zombie, task)
end
