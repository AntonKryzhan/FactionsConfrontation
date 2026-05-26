require "NPCBehavior/NPCProgramBaseGuardBridge"

ZombiePrograms = ZombiePrograms or {}

ZombiePrograms.BaseGuard = {}
ZombiePrograms.BaseGuard.Stages = {}

ZombiePrograms.BaseGuard.Init = function(bandit)
end

ZombiePrograms.BaseGuard.GetCapabilities = function()
    return NPCProgramBaseGuardBridge.GetCapabilities()
end

ZombiePrograms.BaseGuard.Prepare = function(bandit)
    return NPCProgramBaseGuardBridge.Prepare(bandit)
end

ZombiePrograms.BaseGuard.Wait = function(bandit)
    return NPCProgramBaseGuardBridge.Wait(bandit)
end
