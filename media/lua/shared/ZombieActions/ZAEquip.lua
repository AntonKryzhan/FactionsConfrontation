require "NPCActions/NPCActionEquipBridge"

ZombieActions = ZombieActions or {}

ZombieActions.Equip = ZombieActions.Equip or {}

ZombieActions.Equip.onStart = function(zombie, task)
    return NPCActionEquipBridge.OnStart(zombie, task)
end

ZombieActions.Equip.onWorking = function(zombie, task)
    return NPCActionEquipBridge.OnWorking(zombie, task)
end

ZombieActions.Equip.onComplete = function(zombie, task)
    return NPCActionEquipBridge.OnComplete(zombie, task)
end
