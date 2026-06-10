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
ZombiePrograms.BaseGuard.Checkpoint = function(bandit)
    return NPCProgramBaseGuardBridge.Wait(bandit)
end

ZombiePrograms.BaseGuard.CommanderGuard = function(bandit)
    return NPCProgramBaseGuardBridge.Wait(bandit)
end

ZombiePrograms.BaseGuard.Stages.Prepare = ZombiePrograms.BaseGuard.Prepare
ZombiePrograms.BaseGuard.Stages.Wait = ZombiePrograms.BaseGuard.Wait
ZombiePrograms.BaseGuard.Stages.Checkpoint = ZombiePrograms.BaseGuard.Checkpoint
ZombiePrograms.BaseGuard.Stages.CommanderGuard = ZombiePrograms.BaseGuard.CommanderGuard

