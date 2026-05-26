require "NPCBehavior/NPCBrainSchedulerBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCBrainScheduler = NPCLegacyGlobalsBridge.InstallAlias("BrainScheduler", NPCBrainScheduler, "NPCBrainScheduler")

NPCBrainSchedulerBridge.ApplyDefaults(NPCBrainScheduler)

function NPCBrainScheduler.ApplySettings()
    return NPCBrainSchedulerBridge.ApplySettings(NPCBrainScheduler)
end

function NPCBrainScheduler.MarkDirty(bandit, brain, reason)
    return NPCBrainSchedulerBridge.MarkDirty(NPCBrainScheduler, bandit, brain, reason)
end

function NPCBrainScheduler.ShouldThink(bandit, brain, tick, sub, threat)
    return NPCBrainSchedulerBridge.ShouldThink(NPCBrainScheduler, bandit, brain, tick, sub, threat)
end

NPCBrainScheduler.ApplySettings()
