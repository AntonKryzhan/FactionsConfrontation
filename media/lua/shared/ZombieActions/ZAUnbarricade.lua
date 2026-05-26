require "NPCActions/NPCActionUnbarricadeBridge"

ZombieActions = ZombieActions or {}

ZombieActions.Unbarricade = ZombieActions.Unbarricade or {}

ZombieActions.Unbarricade.onStart = function(zombie, task)
    return NPCActionUnbarricadeBridge.OnStart(zombie, task)
end

ZombieActions.Unbarricade.onWorking = function(zombie, task)
    return NPCActionUnbarricadeBridge.OnWorking(zombie, task)
end

ZombieActions.Unbarricade.onComplete = function(zombie, task)
    return NPCActionUnbarricadeBridge.OnComplete(zombie, task)
end
