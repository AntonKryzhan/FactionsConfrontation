require "NPCBehavior/NPCProgramLooterBridge"

ZombiePrograms = ZombiePrograms or {}

ZombiePrograms.Looter = ZombiePrograms.Looter or {}
ZombiePrograms.Looter.Stages = ZombiePrograms.Looter.Stages or {}

ZombiePrograms.Looter.Init = function(bandit)
end

ZombiePrograms.Looter.GetCapabilities = function()
    return NPCProgramLooterBridge.GetCapabilities()
end

ZombiePrograms.Looter.Prepare = function(bandit)
    return NPCProgramLooterBridge.Prepare(bandit)
end

ZombiePrograms.Looter.Operate = function(bandit)
    return NPCProgramLooterBridge.Operate(bandit)
end

ZombiePrograms.Looter.Wait = function(bandit)
    return NPCProgramLooterBridge.Wait(bandit)
end
