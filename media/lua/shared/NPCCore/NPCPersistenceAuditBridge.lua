-- NPCPersistenceAuditBridge.lua
-- Low-cost persistence, wounded-state and human-visual safety audit for physical NPC runtimes.
-- Runtime-only guard: does not introduce new save roots or network commands.

require "NPCCore/NPCLegacyContractBridge"

NPCPersistenceAuditBridge = NPCPersistenceAuditBridge or {}
NPCPersistenceAuditBridge.Version = 1
NPCPersistenceAuditBridge.RuntimeAuditMs = NPCPersistenceAuditBridge.RuntimeAuditMs or 1400
NPCPersistenceAuditBridge.ProfileAuditHours = NPCPersistenceAuditBridge.ProfileAuditHours or 0.12

local NPC_PA_KEYS = {
    liveFlag = NPCLegacyContractBridge.Key("FLAG"),
    isNPC = NPCLegacyContractBridge.Key("IS_FLAG"),
    formerNPCZombie = NPCLegacyContractBridge.Key("FORMER_ZOMBIE"),
    formerNPCZombieAt = NPCLegacyContractBridge.Key("FORMER_ZOMBIE_AT"),
    formerNPCZombieSide = NPCLegacyContractBridge.Key("FORMER_ZOMBIE_SIDE"),
    runtimeId = NPCLegacyContractBridge.Key("RUNTIME_ID"),
    persistentId = NPCLegacyContractBridge.Key("PERSISTENT_ID"),
    worldGroupId = NPCLegacyContractBridge.Key("WORLD_GROUP_ID"),
    program = NPCLegacyContractBridge.Key("PROGRAM"),
    visualSig = NPCLegacyContractBridge.Key("VISUAL_SIG"),
    visualAt = NPCLegacyContractBridge.Key("VISUAL_AT")
}

local function pa_nowMs()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then return math.floor(gt:getWorldAgeHours() * 3600000) end
    end
    return 0
end

local function pa_nowHours()
    if NPCIdentityBridge and NPCIdentityBridge.GetWorldAgeHours then
        local ok, value = pcall(function() return NPCIdentityBridge.GetWorldAgeHours() end)
        if ok and value then return tonumber(value) or 0 end
    end
    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then return tonumber(gt:getWorldAgeHours()) or 0 end
    end
    return 0
end

local function pa_copy(value, depth)
    depth = depth or 0
    if depth > 8 then return nil end
    if type(value) ~= "table" then return value end
    local ret = {}
    for k, v in pairs(value) do
        local tk, tv = type(k), type(v)
        if (tk == "string" or tk == "number" or tk == "boolean") and tv ~= "function" and tv ~= "userdata" and tv ~= "thread" then
            if tv == "table" then ret[k] = pa_copy(v, depth + 1) else ret[k] = v end
        end
    end
    return ret
end

local function pa_bool(value)
    return value == true or value == 1 or value == "1" or value == "true"
end

local function pa_nonEmpty(value)
    return value ~= nil and tostring(value) ~= "" and tostring(value) ~= "nil" and tostring(value) ~= "false"
end

local function pa_modData(zombie)
    if not (zombie and zombie.getModData) then return nil end
    local ok, md = pcall(function() return zombie:getModData() end)
    if ok then return md end
    return nil
end

local function pa_isZombie(zombie)
    return zombie ~= nil and instanceof ~= nil and instanceof(zombie, "IsoZombie")
end

local function pa_isBadSkinName(name)
    name = tostring(name or "")
    if name == "" then return true end
    if string.match(name, "^MaleBody0[1-5]$") or string.match(name, "^FemaleBody0[1-5]$") then return false end
    local lower = string.lower(name)
    return string.find(lower, "zombie", 1, true) ~= nil
        or string.find(lower, "zed", 1, true) ~= nil
        or string.find(lower, "rot", 1, true) ~= nil
        or string.find(lower, "skeleton", 1, true) ~= nil
        or string.find(lower, "burnt", 1, true) ~= nil
end

local function pa_isBadSkinColor(color)
    if type(color) ~= "table" then return true end
    local r = tonumber(color.r)
    local g = tonumber(color.g)
    local b = tonumber(color.b)
    if not r or not g or not b then return true end
    if r < 0.18 or g < 0.12 or b < 0.08 or r > 1.0 or g > 1.0 or b > 1.0 then return true end
    if g > r + 0.08 and g > b + 0.06 then return true end
    if b > r + 0.12 then return true end
    local maxc = math.max(r, math.max(g, b))
    local minc = math.min(r, math.min(g, b))
    return maxc < 0.55 and (maxc - minc) < 0.055
end

local function pa_fallbackSkin(brain, zombie)
    local seed = tonumber(brain and (brain.appearanceSeed or brain.persistentId or brain.uid or brain.id)) or 0
    seed = math.abs(math.floor(seed))
    local female = brain and brain.female == true
    if zombie and zombie.isFemale then
        local ok, value = pcall(function() return zombie:isFemale() == true end)
        if ok then female = value == true end
    end
    if female then return "FemaleBody0" .. tostring(1 + seed % 5) end
    return "MaleBody0" .. tostring(1 + seed % 5)
end

local function pa_visualSig(brain)
    if type(brain) ~= "table" then return "" end
    local function cs(color)
        if type(color) ~= "table" then return "" end
        return tostring(color.r or "") .. "," .. tostring(color.g or "") .. "," .. tostring(color.b or "")
    end
    return tostring(brain.persistentId or brain.uid or "") .. "|" .. tostring(brain.appearanceSeed or "") .. "|" .. tostring(brain.faceProfile or "") .. "|" .. tostring(brain.skinTexture or "") .. "|" .. cs(brain.skinColor) .. "|" .. tostring(brain.hairStyle or "") .. "|" .. cs(brain.hairColor) .. "|" .. tostring(brain.beardStyle or "") .. "|" .. cs(brain.beardColor)
end

local function pa_runtimeId(zombie, brain)
    if type(brain) == "table" then
        if brain.id ~= nil then return tostring(brain.id) end
        if brain.runtimeId ~= nil then return tostring(brain.runtimeId) end
    end
    if zombie and NPCUtils and NPCUtils.GetZombieID then
        local ok, id = pcall(function() return NPCUtils.GetZombieID(zombie) end)
        if ok and id ~= nil then return tostring(id) end
    end
    return nil
end

function NPCPersistenceAuditBridge.IsProtectedAlive(brain)
    if type(brain) ~= "table" then return false end
    if brain.dead == true or brain.confirmedDead == true or brain.woundedState == "dead" then return false end
    if brain.wounded == true and (brain.woundedDowned == true or brain.woundedStabilized == true or brain.woundedEvacuating == true or brain.woundedState == "downed" or brain.woundedState == "stabilized" or brain.woundedState == "evacuating") then return true end
    if brain.mercenaryHired == true or brain.isPlayerGuard == true then return true end
    if brain.persistentId ~= nil or brain.uid ~= nil then return true end
    return false
end

function NPCPersistenceAuditBridge.NormalizeHumanVisual(brain, zombie, reason)
    if type(brain) ~= "table" then return false end
    local changed = false
    if pa_isBadSkinName(brain.skinTexture) then
        brain.skinTexture = pa_fallbackSkin(brain, zombie)
        brain.humanVisualNormalized = true
        changed = true
    end
    if pa_isBadSkinColor(brain.skinColor) then
        brain.skinColor = {r = 0.86, g = 0.66, b = 0.52}
        brain.humanVisualNormalized = true
        changed = true
    end
    if brain.infection ~= nil and tonumber(brain.infection) ~= 0 then
        brain.infection = 0
        changed = true
    end
    if brain.zombie == true then brain.zombie = false; changed = true end
    if brain.reanimate == true then brain.reanimate = false; changed = true end
    if brain.formerNPCZombie == true then brain.formerNPCZombie = false; changed = true end
    brain.humanVisualLocked = true
    brain.humanVisualSignature = pa_visualSig(brain)
    if changed then
        brain.humanVisualNormalizedAt = pa_nowHours()
        brain.humanVisualNormalizedReason = reason or brain.humanVisualNormalizedReason or "persistence_audit"
    end
    return changed
end

function NPCPersistenceAuditBridge.ClearRuntimeZombieFlags(zombie, brain)
    if not pa_isZombie(zombie) then return false end
    if type(brain) ~= "table" then return false end
    local changed = false
    local md = pa_modData(zombie)
    if md then
        if md[NPC_PA_KEYS.formerNPCZombie] ~= nil then md[NPC_PA_KEYS.formerNPCZombie] = nil; changed = true end
        if md[NPC_PA_KEYS.formerNPCZombieAt] ~= nil then md[NPC_PA_KEYS.formerNPCZombieAt] = nil; changed = true end
        if md[NPC_PA_KEYS.formerNPCZombieSide] ~= nil then md[NPC_PA_KEYS.formerNPCZombieSide] = nil; changed = true end
        md.NPCFormerZombie = nil
        md.FactionsConfrontationFormerZombie = nil
        md.NPCReanimate = nil
        md.NPCZombified = nil
        md.NPCVisualAuditedAt = pa_nowMs()
        if brain.persistentId or brain.uid then md[NPC_PA_KEYS.persistentId] = tostring(brain.persistentId or brain.uid) end
        if brain.worldGroupId or brain.groupId then md[NPC_PA_KEYS.worldGroupId] = tostring(brain.worldGroupId or brain.groupId) end
    end
    if zombie.setReanim then pcall(function() zombie:setReanim(false) end) end
    if zombie.setVariable then
        pcall(function() zombie:setVariable(NPC_PA_KEYS.liveFlag, true) end)
        if NPC_PA_KEYS.isNPC then pcall(function() zombie:setVariable(NPC_PA_KEYS.isNPC, true) end) end
        if NPC_PA_KEYS.formerNPCZombie then pcall(function() zombie:setVariable(NPC_PA_KEYS.formerNPCZombie, false) end) end
        if NPC_PA_KEYS.persistentId and (brain.persistentId or brain.uid) then pcall(function() zombie:setVariable(NPC_PA_KEYS.persistentId, tostring(brain.persistentId or brain.uid)) end) end
        if NPC_PA_KEYS.worldGroupId and (brain.worldGroupId or brain.groupId) then pcall(function() zombie:setVariable(NPC_PA_KEYS.worldGroupId, tostring(brain.worldGroupId or brain.groupId)) end) end
        if NPC_PA_KEYS.visualSig then pcall(function() zombie:setVariable(NPC_PA_KEYS.visualSig, tostring(brain.humanVisualSignature or "")) end) end
        changed = true
    end
    return changed
end

function NPCPersistenceAuditBridge.EnsureRuntimeLinks(gmd, zombie, brain)
    if not (gmd and type(brain) == "table") then return false end
    local uid = brain.persistentId or brain.uid
    if not uid then return false end
    uid = tostring(uid)
    local rid = pa_runtimeId(zombie, brain)
    local changed = false
    if not gmd.PersistentRuntimeToUID then gmd.PersistentRuntimeToUID = {} end
    if not gmd.PersistentUIDToRuntime then gmd.PersistentUIDToRuntime = {} end
    if rid then
        if gmd.PersistentRuntimeToUID[rid] ~= uid then gmd.PersistentRuntimeToUID[rid] = uid; changed = true end
        if gmd.PersistentUIDToRuntime[uid] ~= rid then gmd.PersistentUIDToRuntime[uid] = rid; changed = true end
        if gmd.RuntimeToUID then gmd.RuntimeToUID[rid] = uid end
        if gmd.UIDToRuntime then gmd.UIDToRuntime[uid] = rid end
    end
    if gmd.DeadRegistry and NPCPersistenceAuditBridge.IsProtectedAlive(brain) and gmd.DeadRegistry[uid] ~= nil then
        gmd.DeadRegistry[uid] = nil
        changed = true
    end
    return changed
end

function NPCPersistenceAuditBridge.NormalizeWoundedBrain(brain, reason)
    if type(brain) ~= "table" or brain.wounded ~= true then return false end
    local changed = false
    brain.dead = nil
    brain.confirmedDead = nil
    brain.hostile = false
    brain.relationshipToPlayer = brain.relationshipToPlayer or (brain.woundedAbandoned and "abandoned_wounded" or "wounded_ally")
    if brain.woundedDowned == true or brain.woundedState == "downed" then
        brain.woundedDowned = true
        brain.woundedState = "downed"
        brain.health = math.max(tonumber(brain.health) or 0, NPCWounded and NPCWounded.DownedHealth and NPCWounded.DownedHealth() or 0.22)
        brain.fireMode = "HoldFire"
        brain.rbFireMode = "HoldFire"
        brain.order = type(brain.order) == "table" and brain.order or {name = "Hold"}
        brain.order.name = "Hold"
        brain.order.fireMode = "HoldFire"
        changed = true
    elseif brain.woundedStabilized == true or brain.woundedState == "stabilized" then
        brain.woundedDowned = false
        brain.woundedStabilized = true
        brain.woundedState = "stabilized"
        brain.health = math.max(tonumber(brain.health) or 0, NPCWounded and NPCWounded.StabilizedHealth and NPCWounded.StabilizedHealth() or 0.48)
        changed = true
    elseif brain.woundedEvacuating == true or brain.woundedState == "evacuating" then
        brain.woundedEvacuating = true
        brain.woundedState = "evacuating"
        brain.health = math.max(tonumber(brain.health) or 0, 0.35)
        changed = true
    end
    if changed then brain.woundedAuditedAt = pa_nowHours(); brain.woundedAuditReason = reason or "persistence_audit" end
    return changed
end

function NPCPersistenceAuditBridge.AuditBrain(brain, zombie, reason)
    if type(brain) ~= "table" then return false end
    local changed = false
    if NPCPersistenceAuditBridge.NormalizeHumanVisual(brain, zombie, reason) then changed = true end
    if NPCPersistenceAuditBridge.NormalizeWoundedBrain(brain, reason) then changed = true end
    if brain.uid and not brain.persistentId then brain.persistentId = brain.uid; changed = true end
    if brain.persistentId and not brain.uid then brain.uid = brain.persistentId; changed = true end
    if brain.groupId and not brain.worldGroupId then brain.worldGroupId = brain.groupId; changed = true end
    if brain.worldGroupId and not brain.groupId then brain.groupId = brain.worldGroupId; changed = true end
    if changed then brain.persistenceAuditedAt = pa_nowHours() end
    return changed
end

function NPCPersistenceAuditBridge.AuditRuntimeObject(zombie, brain, gmd, reason)
    if type(brain) ~= "table" then return brain, false end
    local now = pa_nowMs()
    brain.ai = brain.ai or {}
    local last = tonumber(brain.ai.persistenceAuditAtMs) or 0
    if now > 0 and now - last < (tonumber(NPCPersistenceAuditBridge.RuntimeAuditMs) or 1400) then return brain, false end
    brain.ai.persistenceAuditAtMs = now
    local changed = NPCPersistenceAuditBridge.AuditBrain(brain, zombie, reason)
    if NPCPersistenceAuditBridge.ClearRuntimeZombieFlags(zombie, brain) then changed = true end
    if NPCPersistenceAuditBridge.EnsureRuntimeLinks(gmd, zombie, brain) then changed = true end
    return brain, changed
end

function NPCPersistenceAuditBridge.ShouldSuppressFalseDeath(zombie, brain)
    if not NPCPersistenceAuditBridge.IsProtectedAlive(brain) then return false end
    local health = tonumber(brain and brain.health) or nil
    if zombie and zombie.getHealth then
        local ok, value = pcall(function() return zombie:getHealth() end)
        if ok and value ~= nil then health = tonumber(value) or health end
    end
    if brain.wounded == true and (health == nil or health > 0.01) then return true end
    if brain.mercenaryHired == true and brain.wounded == true then return true end
    return false
end

function NPCPersistenceAuditBridge.MarkProfileAlive(gmd, brain, reason)
    if not (gmd and type(brain) == "table") then return false end
    local uid = brain.persistentId or brain.uid
    if not uid then return false end
    uid = tostring(uid)
    gmd.PersistentNPCs = gmd.PersistentNPCs or {}
    gmd.Registry = gmd.Registry or {}
    local profile = gmd.PersistentNPCs[uid] or gmd.Registry[uid] or {uid = uid, persistentId = uid}
    for _, key in ipairs({"wounded", "woundedDowned", "woundedStabilized", "woundedEvacuating", "woundedAbandoned", "woundedState", "woundedAt", "woundedExpiresAt", "woundedForPlayerId", "woundedForPlayerName", "woundedX", "woundedY", "woundedZ", "woundedEvacTarget", "health", "maxHealth", "relationshipToPlayer", "order", "fireMode", "rbFireMode", "humanVisualLocked", "humanVisualSignature", "humanVisualNormalized", "skinTexture", "skinColor", "hairStyle", "hairColor", "beardStyle", "beardColor", "appearanceSeed", "faceProfile", "female", "outfit"}) do
        if brain[key] ~= nil then profile[key] = pa_copy(brain[key]) end
    end
    profile.dead = nil
    profile.deathAt = nil
    profile.uid = uid
    profile.persistentId = profile.persistentId or uid
    profile.updated = pa_nowHours()
    profile.persistenceAuditReason = reason or "mark_alive"
    NPCPersistenceAuditBridge.AuditBrain(profile, nil, reason)
    gmd.PersistentNPCs[uid] = profile
    gmd.Registry[uid] = pa_copy(profile)
    if gmd.DeadRegistry then gmd.DeadRegistry[uid] = nil end
    return true
end

return NPCPersistenceAuditBridge
