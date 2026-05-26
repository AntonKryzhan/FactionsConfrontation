require "NPCBehavior/NPCProgramCompanionBridge"

ZombiePrograms = ZombiePrograms or {}

ZombiePrograms.Companion = ZombiePrograms.Companion or {}
ZombiePrograms.Companion.Stages = ZombiePrograms.Companion.Stages or {}

ZombiePrograms.Companion.Init = function(bandit)
    return NPCProgramCompanionBridge.Init(bandit)
end

ZombiePrograms.Companion.GetCapabilities = function()
    return NPCProgramCompanionBridge.GetCapabilities()
end

ZombiePrograms.Companion.Prepare = function(bandit)
    return NPCProgramCompanionBridge.Prepare(bandit)
end

ZombiePrograms.Companion.TryLootHouseOrder = function(bandit, brain, order, tasks, endurance)
    return NPCProgramCompanionBridge.TryLootHouseOrder(bandit, brain, order, tasks, endurance)
end

ZombiePrograms.Companion.TryTacticalPointOrder = function(bandit, brain, order, tasks, endurance)
    return NPCProgramCompanionBridge.TryTacticalPointOrder(bandit, brain, order, tasks, endurance)
end

ZombiePrograms.Companion.TryMobileOrder = function(bandit, brain, orderName, tasks)
    return NPCProgramCompanionBridge.TryMobileOrder(bandit, brain, orderName, tasks)
end

ZombiePrograms.Companion.TryVehicleSync = function(bandit, master, vehicle, dist, tasks)
    return NPCProgramCompanionBridge.TryVehicleSync(bandit, master, vehicle, dist, tasks)
end

ZombiePrograms.Companion.TryProtectMaster = function(bandit, dist, tasks, endurance)
    return NPCProgramCompanionBridge.TryProtectMaster(bandit, dist, tasks, endurance)
end

ZombiePrograms.Companion.TryLootWeapons = function(bandit, cell, tasks)
    return NPCProgramCompanionBridge.TryLootWeapons(bandit, cell, tasks)
end

ZombiePrograms.Companion.TryGuardpost = function(bandit, tasks, endurance, walkType, dist)
    return NPCProgramCompanionBridge.TryGuardpost(bandit, tasks, endurance, walkType, dist)
end

ZombiePrograms.Companion.TryFishing = function(bandit, cell, tasks, endurance)
    return NPCProgramCompanionBridge.TryFishing(bandit, cell, tasks, endurance)
end

ZombiePrograms.Companion.TryForaging = function(bandit, cm, tasks)
    return NPCProgramCompanionBridge.TryForaging(bandit, cm, tasks)
end

ZombiePrograms.Companion.TryHomeBaseTasks = function(bandit, cm, tasks)
    return NPCProgramCompanionBridge.TryHomeBaseTasks(bandit, cm, tasks)
end

ZombiePrograms.Companion.TryFollowSlot = function(bandit, master, brain, order, tasks, endurance, walkType)
    return NPCProgramCompanionBridge.TryFollowSlot(bandit, master, brain, order, tasks, endurance, walkType)
end

ZombiePrograms.Companion.TryIdle = function(bandit, tasks)
    return NPCProgramCompanionBridge.TryIdle(bandit, tasks)
end

ZombiePrograms.Companion.IsStrictFollowOrder = function(brain, order)
    return NPCProgramCompanionBridge.IsStrictFollowOrder(brain, order)
end

ZombiePrograms.Companion.Follow = function(bandit)
    return NPCProgramCompanionBridge.Follow(bandit)
end
