require "NPCActions/NPCActionLootWeaponsBridge"

ZombieActions = ZombieActions or {}

ZombieActions.LootWeapons = ZombieActions.LootWeapons or {}

ZombieActions.LootWeapons.onStart = function(zombie, task)
    return NPCActionLootWeaponsBridge.OnStart(zombie, task)
end

ZombieActions.LootWeapons.onWorking = function(zombie, task)
    return NPCActionLootWeaponsBridge.OnWorking(zombie, task)
end

ZombieActions.LootWeapons.onComplete = function(zombie, task)
    return NPCActionLootWeaponsBridge.OnComplete(zombie, task)
end
