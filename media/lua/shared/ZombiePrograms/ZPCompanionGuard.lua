require "NPCBehavior/NPCProgramCompanionGuardBridge"

ZombiePrograms = ZombiePrograms or {}

ZombiePrograms.CompanionGuard = ZombiePrograms.CompanionGuard or {}
ZombiePrograms.CompanionGuard.Stages = ZombiePrograms.CompanionGuard.Stages or {}

ZombiePrograms.CompanionGuard.Init = function(bandit)
end

ZombiePrograms.CompanionGuard.GetCapabilities = function()
    return NPCProgramCompanionGuardBridge.GetCapabilities()
end

ZombiePrograms.CompanionGuard.Prepare = function(bandit)
    return NPCProgramCompanionGuardBridge.Prepare(bandit)
end

ZombiePrograms.CompanionGuard.Guard = function(bandit)
    return NPCProgramCompanionGuardBridge.Guard(bandit)
end
