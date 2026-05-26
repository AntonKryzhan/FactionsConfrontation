require "NPCBehavior/NPCProgramCivilianBridge"

ZombiePrograms = ZombiePrograms or {}

ZombiePrograms.Civilian = ZombiePrograms.Civilian or {}
ZombiePrograms.Civilian.Stages = ZombiePrograms.Civilian.Stages or {}

ZombiePrograms.Civilian.Init = function(bandit)
end

ZombiePrograms.Civilian.GetCapabilities = function()
    return NPCProgramCivilianBridge.GetCapabilities()
end

ZombiePrograms.Civilian.Prepare = function(bandit)
    return NPCProgramCivilianBridge.Prepare(bandit)
end

ZombiePrograms.Civilian.Follow = function(bandit)
    return NPCProgramCivilianBridge.Follow(bandit)
end
