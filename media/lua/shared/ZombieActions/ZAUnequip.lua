require "NPCActions/NPCActionUnequipBridge"

ZombieActions = ZombieActions or {}

ZombieActions.Unequip = ZombieActions.Unequip or {}

ZombieActions.Unequip.onStart = function(zombie, task)
    return NPCActionUnequipBridge.OnStart(zombie, task)
end

ZombieActions.Unequip.onWorking = function(zombie, task)
    return NPCActionUnequipBridge.OnWorking(zombie, task)
end

ZombieActions.Unequip.onComplete = function(zombie, task)
    return NPCActionUnequipBridge.OnComplete(zombie, task)
end
