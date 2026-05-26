require "NPCBehavior/NPCProgramDefendBridge"

ZombiePrograms = ZombiePrograms or {}

ZombiePrograms.Defend = ZombiePrograms.Defend or {}
ZombiePrograms.Defend.Stages = ZombiePrograms.Defend.Stages or {}

ZombiePrograms.Defend.Init = function(bandit)
end

ZombiePrograms.Defend.GetCapabilities = function()
    return NPCProgramDefendBridge.GetCapabilities()
end

ZombiePrograms.Defend.Prepare = function(bandit)
    return NPCProgramDefendBridge.Prepare(bandit)
end

ZombiePrograms.Defend.Wait = function(bandit)
    return NPCProgramDefendBridge.Wait(bandit)
end
