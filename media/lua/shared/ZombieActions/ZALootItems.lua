require "NPCActions/NPCActionLootItemsBridge"

ZombieActions = ZombieActions or {}

ZombieActions.LootItems = ZombieActions.LootItems or {}

ZombieActions.LootItems.onStart = function(zombie, task)
    return NPCActionLootItemsBridge.OnStart(zombie, task)
end

ZombieActions.LootItems.onWorking = function(zombie, task)
    return NPCActionLootItemsBridge.OnWorking(zombie, task)
end

ZombieActions.LootItems.onComplete = function(zombie, task)
    return NPCActionLootItemsBridge.OnComplete(zombie, task)
end
