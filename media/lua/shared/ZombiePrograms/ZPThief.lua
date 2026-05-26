require "NPCBehavior/NPCProgramThiefBridge"

ZombiePrograms = ZombiePrograms or {}

ZombiePrograms.Thief = ZombiePrograms.Thief or {}
ZombiePrograms.Thief.Stages = ZombiePrograms.Thief.Stages or {}

ZombiePrograms.Thief.Init = function(bandit)
end

ZombiePrograms.Thief.GetCapabilities = function()
    return NPCProgramThiefBridge.GetCapabilities()
end

ZombiePrograms.Thief.Prepare = function(bandit)
    return NPCProgramThiefBridge.Prepare(bandit)
end

ZombiePrograms.Thief.Operate = function(bandit)
    return NPCProgramThiefBridge.Operate(bandit)
end

ZombiePrograms.Thief.Wait = function(bandit)
    return NPCProgramThiefBridge.Wait(bandit)
end

ZombiePrograms.Thief.Escape = function(bandit)
    return NPCProgramThiefBridge.Escape(bandit)
end
