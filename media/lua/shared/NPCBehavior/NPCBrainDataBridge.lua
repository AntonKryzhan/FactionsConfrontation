NPCBrainDataBridge = NPCBrainDataBridge or {}

function NPCBrainDataBridge.Get(zombie)
    local modData = zombie:getModData()
    return modData.brain
end

function NPCBrainDataBridge.Update(zombie, brain)
    local modData = zombie:getModData()
    modData.brain = brain
end

function NPCBrainDataBridge.Remove(zombie)
    local modData = zombie:getModData()
    modData.brain = nil
end
