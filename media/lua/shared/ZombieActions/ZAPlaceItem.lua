require "NPCActions/NPCActionPlaceItemBridge"

ZombieActions = ZombieActions or {}

ZombieActions.PlaceItem = ZombieActions.PlaceItem or {}

ZombieActions.PlaceItem.onStart = function(zombie, task)
    return NPCActionPlaceItemBridge.OnStart(zombie, task)
end

ZombieActions.PlaceItem.onWorking = function(zombie, task)
    return NPCActionPlaceItemBridge.OnWorking(zombie, task)
end

ZombieActions.PlaceItem.onComplete = function(zombie, task)
    return NPCActionPlaceItemBridge.OnComplete(zombie, task)
end
