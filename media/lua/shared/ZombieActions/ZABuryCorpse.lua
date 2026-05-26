require "NPCActions/NPCActionBuryCorpseBridge"

ZombieActions = ZombieActions or {}

ZombieActions.BuryCorpse = ZombieActions.BuryCorpse or {}

ZombieActions.BuryCorpse.onStart = function(zombie, task)
    return NPCActionBuryCorpseBridge.OnStart(zombie, task)
end

ZombieActions.BuryCorpse.onWorking = function(zombie, task)
    return NPCActionBuryCorpseBridge.OnWorking(zombie, task)
end

ZombieActions.BuryCorpse.onComplete = function(zombie, task)
    return NPCActionBuryCorpseBridge.OnComplete(zombie, task)
end
