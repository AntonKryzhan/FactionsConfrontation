-- NPCZombieLifecycleClassifierBridge.lua
-- Runtime-only classifier for ordinary zombies, live NPCs, former NPCs and NPC residue.
-- Keeps NPC cleanup/death-flow from touching vanilla zombies by accident.

NPCZombieLifecycleClassifierBridge = NPCZombieLifecycleClassifierBridge or {}
NPCZombieLifecycleClassifierBridge.Version = 1

require "NPCCore/NPCLegacyContractBridge"

local NPC_ZLC_KEYS = {
    liveFlag = NPCLegacyContractBridge.Key("FLAG"),
    isNPC = NPCLegacyContractBridge.Key("IS_FLAG"),
    formerNPCZombie = NPCLegacyContractBridge.Key("FORMER_ZOMBIE"),
    runtimeId = NPCLegacyContractBridge.Key("RUNTIME_ID"),
    persistentId = NPCLegacyContractBridge.Key("PERSISTENT_ID"),
    worldGroupId = NPCLegacyContractBridge.Key("WORLD_GROUP_ID"),
    program = NPCLegacyContractBridge.Key("PROGRAM"),
    primary = NPCLegacyContractBridge.Key("PRIMARY"),
    secondary = NPCLegacyContractBridge.Key("SECONDARY"),
    blackMarket = NPCLegacyContractBridge.Key("BLACK_MARKET")
}

local function zlc_isZombie(zombie)
    return zombie ~= nil and instanceof ~= nil and instanceof(zombie, "IsoZombie")
end

local function zlc_bool(value)
    return value == true or value == "true" or value == 1 or value == "1"
end

local function zlc_nonEmpty(value)
    return value ~= nil and tostring(value) ~= "" and tostring(value) ~= "false" and tostring(value) ~= "nil"
end

local function zlc_modData(zombie)
    if not (zombie and zombie.getModData) then return nil end
    local ok, md = pcall(function() return zombie:getModData() end)
    if ok then return md end
    return nil
end

local function zlc_variableBoolean(zombie, key)
    if not (zombie and zombie.getVariableBoolean and key) then return false end
    local ok, value = pcall(function() return zombie:getVariableBoolean(key) end)
    return ok and value == true
end

local function zlc_variableString(zombie, key)
    if not (zombie and zombie.getVariableString and key) then return nil end
    local ok, value = pcall(function() return zombie:getVariableString(key) end)
    if ok and zlc_nonEmpty(value) then return tostring(value) end
    return nil
end

local function zlc_serviceId(zombie, md, key)
    if md and zlc_nonEmpty(md[key]) then return tostring(md[key]) end
    return zlc_variableString(zombie, key)
end

local function zlc_hasHandItem(zombie, getter)
    if not (zombie and getter and zombie[getter]) then return false end
    local ok, item = pcall(function() return zombie[getter](zombie) end)
    return ok and item ~= nil
end

function NPCZombieLifecycleClassifierBridge.IsBlackMarket(zombie)
    if not zlc_isZombie(zombie) then return false end
    local md = zlc_modData(zombie)
    if md and (md.NPCBlackMarketBridge == true or md.BlackMarketNPC == true) then return true end
    if md and NPC_ZLC_KEYS.blackMarket and zlc_bool(md[NPC_ZLC_KEYS.blackMarket]) then return true end
    if NPC_ZLC_KEYS.blackMarket and zlc_variableBoolean(zombie, NPC_ZLC_KEYS.blackMarket) then return true end
    return false
end

function NPCZombieLifecycleClassifierBridge.IsLiveNPC(zombie)
    if not zlc_isZombie(zombie) then return false end
    if NPCZombieLifecycleClassifierBridge.IsFormerNPCZombie(zombie) then return false end
    local md = zlc_modData(zombie)
    if md and zlc_bool(md[NPC_ZLC_KEYS.liveFlag]) then return true end
    return zlc_variableBoolean(zombie, NPC_ZLC_KEYS.liveFlag)
end

function NPCZombieLifecycleClassifierBridge.IsFormerNPCZombie(zombie)
    if not zlc_isZombie(zombie) then return false end
    local md = zlc_modData(zombie)
    if md and zlc_bool(md[NPC_ZLC_KEYS.formerNPCZombie]) then return true end
    return zlc_variableBoolean(zombie, NPC_ZLC_KEYS.formerNPCZombie)
end

function NPCZombieLifecycleClassifierBridge.HasNPCServiceStamp(zombie)
    if not zlc_isZombie(zombie) then return false end
    local md = zlc_modData(zombie)
    if md then
        if zlc_bool(md[NPC_ZLC_KEYS.isNPC]) then return true end
        if zlc_nonEmpty(md[NPC_ZLC_KEYS.runtimeId]) then return true end
        if zlc_nonEmpty(md[NPC_ZLC_KEYS.persistentId]) then return true end
        if zlc_nonEmpty(md[NPC_ZLC_KEYS.worldGroupId]) then return true end
        if zlc_nonEmpty(md[NPC_ZLC_KEYS.program]) then return true end
        if zlc_nonEmpty(md[NPC_ZLC_KEYS.primary]) then return true end
        if zlc_nonEmpty(md[NPC_ZLC_KEYS.secondary]) then return true end
    end

    if zlc_variableString(zombie, NPC_ZLC_KEYS.runtimeId) then return true end
    if zlc_variableString(zombie, NPC_ZLC_KEYS.persistentId) then return true end
    if zlc_variableString(zombie, NPC_ZLC_KEYS.worldGroupId) then return true end
    if zlc_variableString(zombie, NPC_ZLC_KEYS.program) then return true end
    if zlc_variableString(zombie, NPC_ZLC_KEYS.primary) then return true end
    if zlc_variableString(zombie, NPC_ZLC_KEYS.secondary) then return true end

    return false
end

function NPCZombieLifecycleClassifierBridge.IsArmedNPCResidue(zombie)
    if not zlc_isZombie(zombie) then return false end
    if NPCZombieLifecycleClassifierBridge.IsLiveNPC(zombie) then return true end
    if NPCZombieLifecycleClassifierBridge.IsFormerNPCZombie(zombie) then return true end
    if zlc_hasHandItem(zombie, "getPrimaryHandItem") then return true end
    if zlc_hasHandItem(zombie, "getSecondaryHandItem") then return true end
    return NPCZombieLifecycleClassifierBridge.HasNPCServiceStamp(zombie)
end

function NPCZombieLifecycleClassifierBridge.Classify(zombie, brain)
    if not zlc_isZombie(zombie) then return "non_zombie" end
    if NPCZombieLifecycleClassifierBridge.IsBlackMarket(zombie) then return "black_market" end
    if NPCZombieLifecycleClassifierBridge.IsLiveNPC(zombie) then
        if type(brain) == "table" and brain.wounded == true then return "wounded_npc" end
        return "live_npc"
    end
    if NPCZombieLifecycleClassifierBridge.IsFormerNPCZombie(zombie) then return "former_npc" end
    if NPCZombieLifecycleClassifierBridge.HasNPCServiceStamp(zombie) then
        if NPCZombieLifecycleClassifierBridge.IsArmedNPCResidue(zombie) then return "npc_residue" end
        return "stale_npc_runtime"
    end
    return "ordinary_zombie"
end

function NPCZombieLifecycleClassifierBridge.IsOrdinaryZombie(zombie)
    return NPCZombieLifecycleClassifierBridge.Classify(zombie) == "ordinary_zombie"
end

function NPCZombieLifecycleClassifierBridge.IsNPCLikeZombie(zombie, brain)
    local class = NPCZombieLifecycleClassifierBridge.Classify(zombie, brain)
    return class == "live_npc" or class == "wounded_npc" or class == "former_npc" or class == "npc_residue" or class == "stale_npc_runtime"
end

function NPCZombieLifecycleClassifierBridge.ShouldCleanupAsFormerNPC(zombie, brain)
    local class = NPCZombieLifecycleClassifierBridge.Classify(zombie, brain)
    return class == "former_npc" or class == "npc_residue" or class == "stale_npc_runtime"
end

function NPCZombieLifecycleClassifierBridge.ClearOrdinaryCorpseFlags(zombie)
    local md = zlc_modData(zombie)
    if not md then return false end
    md.NPCKeepCorpse = nil
    md.NPCCorpseFromNPCCombat = nil
    md.NPCCorpseDeathAt = nil
    md.NPCWounded = nil
    md.NPCWoundedState = nil
    return true
end

function NPCZombieLifecycleClassifierBridge.MarkNPCCombatCorpse(zombie)
    local md = zlc_modData(zombie)
    if not md then return false end
    md.NPCKeepCorpse = true
    md.NPCCorpseFromNPCCombat = true
    md.NPCCorpseDeathAt = getTimestampMs and getTimestampMs() or 0
    return true
end

function NPCZombieLifecycleClassifierBridge.PrepareDeathFlags(zombie, brain)
    local class = NPCZombieLifecycleClassifierBridge.Classify(zombie, brain)
    if class == "ordinary_zombie" then
        NPCZombieLifecycleClassifierBridge.ClearOrdinaryCorpseFlags(zombie)
        return class, false
    end
    if class == "live_npc" or class == "wounded_npc" or class == "former_npc" or class == "npc_residue" or class == "stale_npc_runtime" then
        NPCZombieLifecycleClassifierBridge.MarkNPCCombatCorpse(zombie)
        return class, true
    end
    return class, false
end

function NPCZombieLifecycleClassifierBridge.GetSafeKillSource(attacker, victim, fakeZombieProvider, brain)
    local class, npcLike = NPCZombieLifecycleClassifierBridge.PrepareDeathFlags(victim, brain)
    if npcLike then return attacker, class end
    if class == "ordinary_zombie" and type(fakeZombieProvider) == "function" then
        local ok, fake = pcall(fakeZombieProvider)
        if ok and fake then return fake, class end
    end
    return attacker, class
end

return NPCZombieLifecycleClassifierBridge
