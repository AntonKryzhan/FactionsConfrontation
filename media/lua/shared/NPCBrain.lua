require "NPCCore/NPCLegacyGlobalsBridge"

NPCBrainData = NPCLegacyGlobalsBridge.InstallAlias("Brain", NPCBrainData, "NPCBrainData")

require "NPCBehavior/NPCBrainDataBridge"

function NPCBrainData.Get(zombie)
    return NPCBrainDataBridge.Get(zombie)
end

function NPCBrainData.Update(zombie, brain)
    return NPCBrainDataBridge.Update(zombie, brain)
end

function NPCBrainData.Remove(zombie)
    return NPCBrainDataBridge.Remove(zombie)
end
