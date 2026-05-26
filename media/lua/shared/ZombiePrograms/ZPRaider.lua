require "NPCBehavior/NPCProgramRaiderBridge"

ZombiePrograms = ZombiePrograms or {}

ZombiePrograms.Raider = ZombiePrograms.Raider or {}
ZombiePrograms.Raider.Stages = ZombiePrograms.Raider.Stages or {}

ZombiePrograms.Raider.Init = function(bandit)
end

ZombiePrograms.Raider.GetCapabilities = function()
    return NPCProgramRaiderBridge.GetCapabilities()
end

ZombiePrograms.Raider.Prepare = function(bandit)
    return NPCProgramRaiderBridge.Prepare(bandit)
end

ZombiePrograms.Raider.Follow = function(bandit)
    return NPCProgramRaiderBridge.Follow(bandit)
end

ZombiePrograms.Raider.Escape = function(bandit)
    return NPCProgramRaiderBridge.Escape(bandit)
end

ZombiePrograms.Raider.Surrender = function(bandit)
    return NPCProgramRaiderBridge.Surrender(bandit)
end

ZombiePrograms.Raider.TurnOffGenerator = function(bandit)
    return NPCProgramRaiderBridge.TurnOffGenerator(bandit)
end

ZombiePrograms.Raider.SabotageVehicle = function(bandit)
    return NPCProgramRaiderBridge.SabotageVehicle(bandit)
end

ZombiePrograms.Raider.BuildBridge = function(bandit)
    return NPCProgramRaiderBridge.BuildBridge(bandit)
end
