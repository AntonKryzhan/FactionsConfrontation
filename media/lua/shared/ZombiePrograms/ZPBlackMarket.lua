-- ZPBlackMarket.lua
-- Static black market service object no-op.
-- Kept only to neutralize legacy saves/patches that still reference program={name="BlackMarket"}.

require "NPCBehavior/NPCProgramBlackMarketBridge"

ZombiePrograms = ZombiePrograms or {}
ZombiePrograms.BlackMarket = ZombiePrograms.BlackMarket or {}
ZombiePrograms.BlackMarket.Stages = ZombiePrograms.BlackMarket.Stages or {}

ZombiePrograms.BlackMarket.Init = function(bandit)
end

ZombiePrograms.BlackMarket.GetCapabilities = function()
    return NPCProgramBlackMarketBridge.GetCapabilities()
end

ZombiePrograms.BlackMarket.Prepare = function(bandit)
    return NPCProgramBlackMarketBridge.Noop(bandit)
end

ZombiePrograms.BlackMarket.Wait = function(bandit)
    return NPCProgramBlackMarketBridge.Noop(bandit)
end

ZombiePrograms.BlackMarket.Walk = function(bandit)
    return NPCProgramBlackMarketBridge.Noop(bandit)
end
