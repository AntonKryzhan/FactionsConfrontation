NPCProgramBlackMarketBridge = NPCProgramBlackMarketBridge or {}

require "NPCCore/NPCLegacyContractBridge"

local CAPABILITIES = {
    melee = false,
    shoot = false,
    smashWindow = false,
    openDoor = false,
    breakDoor = false,
    breakObjects = false,
    unbarricade = false,
    disableGenerators = false,
    sabotageCars = false
}

local function cloneCapabilities()
    local capabilities = {}
    for key, value in pairs(CAPABILITIES) do
        capabilities[key] = value
    end
    return capabilities
end

local function clearBlackMarketRuntimeState(bandit)
    if not bandit then return end

    if NPCBrainData and NPCBrainData.Remove then
        pcall(function()
            NPCBrainData.Remove(bandit)
        end)
    end

    pcall(function()
        bandit:setVariable(NPCLegacyContractBridge.Keys.BLACK_MARKET, false)
    end)
    pcall(function()
        bandit:setVariable("BlackMarketId", "")
    end)
end

function NPCProgramBlackMarketBridge.GetCapabilities()
    return cloneCapabilities()
end

function NPCProgramBlackMarketBridge.Noop(bandit)
    clearBlackMarketRuntimeState(bandit)
    return {status=true, next="Wait", tasks={{action="Time", anim="Idle", time=240}}}
end
