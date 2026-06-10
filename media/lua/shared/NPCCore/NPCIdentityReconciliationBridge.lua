-- NPCIdentityReconciliationBridge.lua
-- Shared runtime-only reconciliation helpers for physical NPC objects, Queue brains,
-- persistent profiles, group runtime state and debug NPC markers.

NPCIdentityReconciliationBridge = NPCIdentityReconciliationBridge or {}
NPCIdentityReconciliationBridge.Version = 2

require "NPCCore/NPCLegacyContractBridge"

NPCIdentityReconciliationBridge.DefaultIntervalSeconds = NPCIdentityReconciliationBridge.DefaultIntervalSeconds or 15
NPCIdentityReconciliationBridge.DefaultQueueBudget = NPCIdentityReconciliationBridge.DefaultQueueBudget or 96
NPCIdentityReconciliationBridge.DefaultGroupBudget = NPCIdentityReconciliationBridge.DefaultGroupBudget or 48
NPCIdentityReconciliationBridge.DefaultMarkerBudget = NPCIdentityReconciliationBridge.DefaultMarkerBudget or 96
NPCIdentityReconciliationBridge.AuthorityOwnerStaleMs = NPCIdentityReconciliationBridge.AuthorityOwnerStaleMs or 15000
NPCIdentityReconciliationBridge.AuthorityDuplicateQuarantineMs = NPCIdentityReconciliationBridge.AuthorityDuplicateQuarantineMs or 12000

local RECON_KEYS = NPCLegacyContractBridge.Keys or {}

local function recon_now()
    if NPCIdentityBridge and NPCIdentityBridge.GetWorldAgeHours then
        return NPCIdentityBridge.GetWorldAgeHours()
    end
    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then return gt:getWorldAgeHours() end
    end
    return 0
end

local function recon_nonempty(value)
    if value == nil then return nil end
    local text = tostring(value)
    if text == "" or text == "nil" or text == "false" then return nil end
    return text
end

local function recon_copy(value, depth)
    depth = depth or 0
    if depth > 8 then return nil end
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do
        local tk = type(k)
        local tv = type(v)
        if (tk == "string" or tk == "number" or tk == "boolean") and tv ~= "function" and tv ~= "userdata" and tv ~= "thread" then
            if tv == "table" then
                out[k] = recon_copy(v, depth + 1)
            else
                out[k] = v
            end
        end
    end
    return out
end

local function recon_tableHasEntries(value)
    if type(value) ~= "table" then return false end
    for _, _ in pairs(value) do return true end
    return false
end

local function recon_runtimeKey(runtimeId)
    runtimeId = recon_nonempty(runtimeId)
    if not runtimeId then return nil end
    return tostring(runtimeId)
end

local function recon_runtimeFromNpcMarkerId(id)
    id = recon_nonempty(id)
    if not id then return nil end
    if string.sub(id, 1, 4) == "npc:" then return string.sub(id, 5) end
    return id
end

function NPCIdentityReconciliationBridge.EnsureData(gmd)
    if not gmd then return nil end

    if not gmd.Queue then gmd.Queue = {} end
    if not gmd.Registry then gmd.Registry = {} end
    if not gmd.RuntimeToUID then gmd.RuntimeToUID = {} end
    if not gmd.UIDToRuntime then gmd.UIDToRuntime = {} end
    if not gmd.PersistentNPCs then gmd.PersistentNPCs = {} end
    if not gmd.PersistentGroups then gmd.PersistentGroups = {} end
    if not gmd.PersistentRuntimeToUID then gmd.PersistentRuntimeToUID = {} end
    if not gmd.PersistentUIDToRuntime then gmd.PersistentUIDToRuntime = {} end
    if not gmd.DebugMapMarkers then gmd.DebugMapMarkers = {} end

    if NPCIdentityBridge and NPCIdentityBridge.EnsureGlobalData then
        pcall(function() NPCIdentityBridge.EnsureGlobalData(gmd) end)
    end
    if NPCPersistentNPCBridge and NPCPersistentNPCBridge.EnsureData then
        pcall(function() NPCPersistentNPCBridge.EnsureData(gmd) end)
    end

    return gmd
end

function NPCIdentityReconciliationBridge.ReadRuntimeId(zombie, fallback)
    local runtimeId = recon_nonempty(fallback)
    if runtimeId then return runtimeId end
    if zombie and NPCUtils and NPCUtils.GetCharacterID then
        local ok, value = pcall(function() return NPCUtils.GetCharacterID(zombie) end)
        runtimeId = ok and recon_nonempty(value) or nil
        if runtimeId then return runtimeId end
    end
    if zombie and NPCUtils and NPCUtils.GetZombieID then
        local ok, value = pcall(function() return NPCUtils.GetZombieID(zombie) end)
        runtimeId = ok and recon_nonempty(value) or nil
        if runtimeId then return runtimeId end
    end
    return nil
end

function NPCIdentityReconciliationBridge.ReadPhysicalId(zombie, mdKey, variableName)
    if not zombie then return nil end
    local md = zombie.getModData and zombie:getModData() or nil
    local value = md and md[mdKey] or nil
    value = recon_nonempty(value)
    if value then return value end
    if zombie.getVariableString and variableName then
        local ok, var = pcall(function() return zombie:getVariableString(variableName) end)
        if ok then return recon_nonempty(var) end
    end
    return nil
end

function NPCIdentityReconciliationBridge.ReadPhysicalIds(zombie, runtimeId)
    return {
        runtimeId = NPCIdentityReconciliationBridge.ReadRuntimeId(zombie, runtimeId),
        persistentId = NPCIdentityReconciliationBridge.ReadPhysicalId(zombie, RECON_KEYS.PERSISTENT_ID, RECON_KEYS.PERSISTENT_ID),
        groupId = NPCIdentityReconciliationBridge.ReadPhysicalId(zombie, RECON_KEYS.WORLD_GROUP_ID, RECON_KEYS.WORLD_GROUP_ID),
        programName = NPCIdentityReconciliationBridge.ReadPhysicalId(zombie, RECON_KEYS.PROGRAM, RECON_KEYS.PROGRAM)
    }
end

function NPCIdentityReconciliationBridge.FindQueueBrain(gmd, runtimeId, persistentId)
    if not (gmd and type(gmd.Queue) == "table") then return nil, nil end

    if runtimeId ~= nil then
        local brain = gmd.Queue[runtimeId] or gmd.Queue[tostring(runtimeId)]
        local numericId = tonumber(runtimeId)
        if not brain and numericId then brain = gmd.Queue[numericId] end
        if type(brain) == "table" then return brain, runtimeId end
    end

    if persistentId ~= nil then
        local wanted = tostring(persistentId)
        for key, brain in pairs(gmd.Queue) do
            if type(brain) == "table" then
                local brainPersistentId = brain.persistentId or brain.uid
                if brainPersistentId and tostring(brainPersistentId) == wanted then
                    return brain, key
                end
            end
        end
    end

    return nil, nil
end

function NPCIdentityReconciliationBridge.FindProfile(gmd, persistentId)
    if not (gmd and persistentId) then return nil end
    local key = tostring(persistentId)
    local profile = nil
    if type(gmd.PersistentNPCs) == "table" then profile = gmd.PersistentNPCs[key] end
    if type(profile) ~= "table" and type(gmd.Registry) == "table" then profile = gmd.Registry[key] end
    if type(profile) ~= "table" or profile.dead == true then return nil end
    return profile
end

function NPCIdentityReconciliationBridge.LinkRuntime(gmd, runtimeId, persistentId)
    if not (gmd and runtimeId ~= nil and persistentId ~= nil) then return false end
    local rid = tostring(runtimeId)
    local uid = tostring(persistentId)
    gmd.RuntimeToUID = gmd.RuntimeToUID or {}
    gmd.UIDToRuntime = gmd.UIDToRuntime or {}
    gmd.PersistentRuntimeToUID = gmd.PersistentRuntimeToUID or {}
    gmd.PersistentUIDToRuntime = gmd.PersistentUIDToRuntime or {}
    gmd.RuntimeToUID[rid] = uid
    gmd.UIDToRuntime[uid] = rid
    gmd.PersistentRuntimeToUID[rid] = uid
    gmd.PersistentUIDToRuntime[uid] = rid
    return true
end


local function recon_now_ms()
    if getTimestampMs then
        local ok, value = pcall(function() return getTimestampMs() end)
        if ok and value then return tonumber(value) or 0 end
    end
    return math.floor(recon_now() * 3600000)
end

local function recon_isAliveZombie(zombie)
    if not zombie then return false end
    if zombie.isDead then
        local okDead, dead = pcall(function() return zombie:isDead() end)
        if okDead and dead == true then return false end
    end
    if zombie.isAlive then
        local okAlive, alive = pcall(function() return zombie:isAlive() end)
        if okAlive and alive == false then return false end
    end
    return true
end

function NPCIdentityReconciliationBridge.EnsureRuntimeAuthority()
    NPCIdentityReconciliationBridge._authority = NPCIdentityReconciliationBridge._authority or {owners = {}, byRuntime = {}, quarantined = {}}
    NPCIdentityReconciliationBridge._authority.owners = NPCIdentityReconciliationBridge._authority.owners or {}
    NPCIdentityReconciliationBridge._authority.byRuntime = NPCIdentityReconciliationBridge._authority.byRuntime or {}
    NPCIdentityReconciliationBridge._authority.quarantined = NPCIdentityReconciliationBridge._authority.quarantined or {}
    return NPCIdentityReconciliationBridge._authority
end

function NPCIdentityReconciliationBridge.QueueHasRuntime(gmd, runtimeId, persistentId)
    if not (gmd and type(gmd.Queue) == "table") then return false end
    local brain = NPCIdentityReconciliationBridge.FindQueueBrain(gmd, runtimeId, persistentId)
    return type(brain) == "table"
end

function NPCIdentityReconciliationBridge.QuarantineDuplicateObject(zombie, persistentId, runtimeId, ownerRuntimeId, reason)
    if not zombie then return false end
    local md = zombie.getModData and zombie:getModData() or nil
    local untilMs = recon_now_ms() + (tonumber(NPCIdentityReconciliationBridge.AuthorityDuplicateQuarantineMs) or 12000)
    if md then
        md.NPCAuthorityDuplicate = true
        md.NPCAuthorityQuarantineUntil = untilMs
        md.NPCAuthorityOwnerRuntimeId = ownerRuntimeId and tostring(ownerRuntimeId) or nil
        md.NPCAuthorityPersistentId = persistentId and tostring(persistentId) or nil
        md.NPCAuthorityRuntimeId = runtimeId and tostring(runtimeId) or nil
        md.NPCAuthorityReason = tostring(reason or "duplicate_persistent_owner")
    end
    if NPCDiagnosticsBridge and NPCDiagnosticsBridge.LogZombie then
        pcall(function()
            NPCDiagnosticsBridge.LogZombie("NPC_IDENTITY", "authority_duplicate_quarantine", zombie, nil, {
                persistentId = persistentId,
                runtimeId = runtimeId,
                ownerRuntimeId = ownerRuntimeId,
                reason = tostring(reason or "duplicate_persistent_owner")
            }, "authority-duplicate:" .. tostring(persistentId) .. ":" .. tostring(runtimeId), false)
        end)
    end
    return true
end

function NPCIdentityReconciliationBridge.ClaimPersistentOwner(gmd, zombie, brain, runtimeId, persistentId, reason)
    persistentId = recon_nonempty(persistentId or (brain and (brain.persistentId or brain.uid)))
    if not persistentId then return true end
    runtimeId = recon_nonempty(runtimeId or (brain and (brain.id or brain.runtimeId)) or NPCIdentityReconciliationBridge.ReadRuntimeId(zombie, nil))
    if not runtimeId then return true end

    local auth = NPCIdentityReconciliationBridge.EnsureRuntimeAuthority()
    local pid = tostring(persistentId)
    local rid = tostring(runtimeId)
    local nowMs = recon_now_ms()
    local owner = auth.owners[pid]

    if owner and tostring(owner.runtimeId or "") == rid then
        owner.lastSeenMs = nowMs
        owner.reason = tostring(reason or owner.reason or "owner_refresh")
        auth.byRuntime[rid] = pid
        return true
    end

    local ownerRuntimeId = owner and recon_nonempty(owner.runtimeId) or nil
    local ownerHasQueue = ownerRuntimeId and NPCIdentityReconciliationBridge.QueueHasRuntime(gmd, ownerRuntimeId, pid) == true
    local challengerHasQueue = NPCIdentityReconciliationBridge.QueueHasRuntime(gmd, rid, pid) == true
    local ownerAge = owner and (nowMs - (tonumber(owner.lastSeenMs) or tonumber(owner.claimedAtMs) or 0)) or 999999999
    local allowTakeover = false

    if not owner or not ownerRuntimeId then
        allowTakeover = true
    elseif not ownerHasQueue and (challengerHasQueue or ownerAge > (tonumber(NPCIdentityReconciliationBridge.AuthorityOwnerStaleMs) or 15000)) then
        allowTakeover = true
    elseif ownerAge > math.max(30000, (tonumber(NPCIdentityReconciliationBridge.AuthorityOwnerStaleMs) or 15000) * 2) then
        allowTakeover = true
    end

    if allowTakeover then
        if ownerRuntimeId and auth.byRuntime[tostring(ownerRuntimeId)] == pid then
            auth.byRuntime[tostring(ownerRuntimeId)] = nil
        end
        auth.owners[pid] = {
            runtimeId = rid,
            persistentId = pid,
            claimedAtMs = nowMs,
            lastSeenMs = nowMs,
            reason = tostring(reason or "claim")
        }
        auth.byRuntime[rid] = pid
        local md = zombie and zombie.getModData and zombie:getModData() or nil
        if md then
            md.NPCAuthorityDuplicate = false
            md.NPCAuthorityOwnerRuntimeId = rid
            md.NPCAuthorityPersistentId = pid
            md.NPCAuthorityReason = tostring(reason or "claim")
        end
        return true
    end

    NPCIdentityReconciliationBridge.QuarantineDuplicateObject(zombie, pid, rid, ownerRuntimeId, reason)
    return false
end

function NPCIdentityReconciliationBridge.IsCurrentPersistentOwner(gmd, zombie, brain, runtimeId, persistentId)
    persistentId = recon_nonempty(persistentId or (brain and (brain.persistentId or brain.uid)) or NPCIdentityReconciliationBridge.ReadPhysicalId(zombie, RECON_KEYS.PERSISTENT_ID, RECON_KEYS.PERSISTENT_ID))
    if not persistentId then return true end
    runtimeId = recon_nonempty(runtimeId or (brain and (brain.id or brain.runtimeId)) or NPCIdentityReconciliationBridge.ReadRuntimeId(zombie, nil))
    if not runtimeId then return true end
    local auth = NPCIdentityReconciliationBridge.EnsureRuntimeAuthority()
    local owner = auth.owners[tostring(persistentId)]
    if not owner then return NPCIdentityReconciliationBridge.ClaimPersistentOwner(gmd, zombie, brain, runtimeId, persistentId, "owner_check") end
    if tostring(owner.runtimeId or "") == tostring(runtimeId) then
        owner.lastSeenMs = recon_now_ms()
        return true
    end
    if not NPCIdentityReconciliationBridge.QueueHasRuntime(gmd, owner.runtimeId, persistentId) and recon_isAliveZombie(zombie) then
        return NPCIdentityReconciliationBridge.ClaimPersistentOwner(gmd, zombie, brain, runtimeId, persistentId, "owner_takeover_check")
    end
    NPCIdentityReconciliationBridge.QuarantineDuplicateObject(zombie, persistentId, runtimeId, owner.runtimeId, "owner_check_failed")
    return false
end

function NPCIdentityReconciliationBridge.ReleasePersistentOwner(gmd, zombie, brain, runtimeId, persistentId, reason)
    persistentId = recon_nonempty(persistentId or (brain and (brain.persistentId or brain.uid)) or NPCIdentityReconciliationBridge.ReadPhysicalId(zombie, RECON_KEYS.PERSISTENT_ID, RECON_KEYS.PERSISTENT_ID))
    runtimeId = recon_nonempty(runtimeId or (brain and (brain.id or brain.runtimeId)) or NPCIdentityReconciliationBridge.ReadRuntimeId(zombie, nil))
    if not (persistentId and runtimeId) then return false end
    local auth = NPCIdentityReconciliationBridge.EnsureRuntimeAuthority()
    local pid = tostring(persistentId)
    local rid = tostring(runtimeId)
    local owner = auth.owners[pid]
    if owner and tostring(owner.runtimeId or "") == rid then
        auth.owners[pid] = nil
        auth.byRuntime[rid] = nil
        return true
    end
    if auth.byRuntime[rid] == pid then auth.byRuntime[rid] = nil end
    return false
end

function NPCIdentityReconciliationBridge.WritePhysicalIdentity(zombie, brain, runtimeId, persistentId, groupId)
    if not (zombie and brain) then return false end
    local md = zombie.getModData and zombie:getModData() or nil
    runtimeId = runtimeId or brain.id or brain.runtimeId
    persistentId = persistentId or brain.persistentId or brain.uid
    groupId = groupId or brain.worldGroupId or brain.groupId
    local programName = brain.program and brain.program.name or brain.programName

    if md then
        md[RECON_KEYS.IS_FLAG] = true
        md[RECON_KEYS.FORMER_ZOMBIE] = false
        if runtimeId ~= nil then md[RECON_KEYS.RUNTIME_ID] = tostring(runtimeId) end
        if persistentId ~= nil then md[RECON_KEYS.PERSISTENT_ID] = tostring(persistentId) end
        if groupId ~= nil then md[RECON_KEYS.WORLD_GROUP_ID] = tostring(groupId) end
        if programName ~= nil then md[RECON_KEYS.PROGRAM] = tostring(programName) end
        md.NPCIdentityReconciledAt = recon_now()
    end

    if zombie.setVariable then
        pcall(function() zombie:setVariable(RECON_KEYS.FLAG, true) end)
        pcall(function() zombie:setVariable(RECON_KEYS.FORMER_ZOMBIE, false) end)
        if runtimeId ~= nil then pcall(function() zombie:setVariable(RECON_KEYS.RUNTIME_ID, tostring(runtimeId)) end) end
        if persistentId ~= nil then pcall(function() zombie:setVariable(RECON_KEYS.PERSISTENT_ID, tostring(persistentId)) end) end
        if groupId ~= nil then pcall(function() zombie:setVariable(RECON_KEYS.WORLD_GROUP_ID, tostring(groupId)) end) end
        if programName ~= nil then pcall(function() zombie:setVariable(RECON_KEYS.PROGRAM, tostring(programName)) end) end
    end

    pcall(function() zombie:setNoTeeth(false) end)
    pcall(function() zombie:setReanim(false) end)
    return true
end

function NPCIdentityReconciliationBridge.NormalizeBrain(gmd, brain, runtimeId, persistentId, groupId, zombie)
    if type(brain) ~= "table" then return nil, false end
    NPCIdentityReconciliationBridge.EnsureData(gmd)

    local changed = false
    runtimeId = recon_nonempty(runtimeId or brain.id or brain.runtimeId)
    persistentId = recon_nonempty(persistentId or brain.persistentId or brain.uid)
    groupId = recon_nonempty(groupId or brain.worldGroupId or brain.groupId)

    if runtimeId ~= nil then
        if tostring(brain.id or "") ~= tostring(runtimeId) then brain.id = runtimeId changed = true end
        if tostring(brain.runtimeId or "") ~= tostring(runtimeId) then brain.runtimeId = runtimeId changed = true end
    end
    if persistentId ~= nil then
        if tostring(brain.uid or "") ~= tostring(persistentId) then brain.uid = persistentId changed = true end
        if tostring(brain.persistentId or "") ~= tostring(persistentId) then brain.persistentId = persistentId changed = true end
    end
    if groupId ~= nil then
        if tostring(brain.worldGroupId or "") ~= tostring(groupId) then brain.worldGroupId = groupId changed = true end
        if tostring(brain.groupId or "") ~= tostring(groupId) then brain.groupId = groupId changed = true end
    end

    if NPCIdentityBridge and NPCIdentityBridge.EnsureBrain then
        local ok, normalized = pcall(function() return NPCIdentityBridge.EnsureBrain(brain, gmd, runtimeId, persistentId == nil) end)
        if ok and type(normalized) == "table" then brain = normalized end
    end

    if zombie and NPCPersistentNPCBridge and NPCPersistentNPCBridge.ApplyProfileToBrain then
        local ok, profiled = pcall(function() return NPCPersistentNPCBridge.ApplyProfileToBrain(gmd, brain, zombie, nil) end)
        if ok and type(profiled) == "table" then brain = profiled end
    end

    runtimeId = recon_nonempty(runtimeId or brain.id or brain.runtimeId)
    persistentId = recon_nonempty(persistentId or brain.persistentId or brain.uid)
    groupId = recon_nonempty(groupId or brain.worldGroupId or brain.groupId)

    if runtimeId ~= nil and persistentId ~= nil then
        NPCIdentityReconciliationBridge.LinkRuntime(gmd, runtimeId, persistentId)
    end
    if runtimeId ~= nil and gmd and type(gmd.Queue) == "table" then
        gmd.Queue[runtimeId] = brain
    end
    if NPCIdentityBridge and NPCIdentityBridge.TouchRegistry then
        pcall(function() NPCIdentityBridge.TouchRegistry(gmd, brain, runtimeId) end)
    elseif gmd and persistentId then
        gmd.Registry = gmd.Registry or {}
        local profile = recon_copy(brain)
        profile.uid = persistentId
        profile.persistentId = persistentId
        profile.runtimeId = runtimeId
        profile.updated = recon_now()
        gmd.Registry[persistentId] = profile
    end

    return brain, changed
end

function NPCIdentityReconciliationBridge.RegisterGroupPhysical(gmd, brain, runtimeId)
    if not (gmd and brain and runtimeId ~= nil and type(gmd.VirtualGroups) == "table") then return false end
    local groupId = brain.worldGroupId or brain.groupId
    if not groupId then return false end
    local group = gmd.VirtualGroups[tostring(groupId)] or gmd.VirtualGroups[groupId]
    if type(group) ~= "table" then return false end

    local sid = tostring(runtimeId)
    group.physicalIds = type(group.physicalIds) == "table" and group.physicalIds or {}
    local seen = false
    for _, existing in ipairs(group.physicalIds) do
        if tostring(existing) == sid then seen = true break end
    end
    if not seen then group.physicalIds[#group.physicalIds + 1] = sid end
    group.activated = true
    group.virtual = false
    group.state = group.state == "spawning" and "physical" or (group.state or "physical")
    group.updatedAt = recon_now()
    gmd.VirtualGroups[tostring(groupId)] = group
    return true
end

function NPCIdentityReconciliationBridge.ReconcileRuntimeObject(gmd, zombie, brain, runtimeId, reason)
    if not gmd then return brain, false end
    NPCIdentityReconciliationBridge.EnsureData(gmd)

    local ids = NPCIdentityReconciliationBridge.ReadPhysicalIds(zombie, runtimeId)
    local reasonText = tostring(reason or "runtime")
    if reasonText == "client_npc_update" and type(brain) == "table" and type(brain.ai) == "table" then
        local lastAt = tonumber(brain.ai.identityReconciledAt)
        local now = recon_now()
        if lastAt and now - lastAt < (15 / 3600) then
            local wantsPersistent = brain.persistentId or brain.uid
            local physicalHasPersistent = ids.persistentId ~= nil or wantsPersistent == nil
            local physicalHasRuntime = ids.runtimeId ~= nil
            if physicalHasPersistent and physicalHasRuntime then return brain, false end
        end
    end

    local queueBrain = nil
    local queueKey = nil
    queueBrain, queueKey = NPCIdentityReconciliationBridge.FindQueueBrain(gmd, ids.runtimeId, ids.persistentId)
    if type(queueBrain) == "table" then brain = queueBrain end
    if type(brain) ~= "table" then return brain, false end

    local groupId = ids.groupId or brain.worldGroupId or brain.groupId
    local persistentId = ids.persistentId or brain.persistentId or brain.uid
    runtimeId = ids.runtimeId or brain.id or brain.runtimeId or queueKey
    if not NPCIdentityReconciliationBridge.ClaimPersistentOwner(gmd, zombie, brain, runtimeId, persistentId, reasonText) then
        return brain, false
    end

    local normalized, changed = NPCIdentityReconciliationBridge.NormalizeBrain(gmd, brain, runtimeId, persistentId, groupId, zombie)
    if type(normalized) == "table" then brain = normalized end

    runtimeId = runtimeId or brain.id or brain.runtimeId
    persistentId = persistentId or brain.persistentId or brain.uid
    groupId = groupId or brain.worldGroupId or brain.groupId
    if zombie then
        NPCIdentityReconciliationBridge.WritePhysicalIdentity(zombie, brain, runtimeId, persistentId, groupId)
    end
    NPCIdentityReconciliationBridge.RegisterGroupPhysical(gmd, brain, runtimeId)

    if brain.ai then
        brain.ai.identityReconciledAt = recon_now()
        brain.ai.identityReconcileReason = tostring(reason or "runtime")
    end

    if NPCDiagnosticsBridge and NPCDiagnosticsBridge.LogZombie and (changed == true or reasonText ~= "client_npc_update") then
        NPCDiagnosticsBridge.LogZombie("NPC_IDENTITY", "runtime_reconcile", zombie, brain, {reason=reasonText, runtimeId=runtimeId, persistentId=persistentId, groupId=groupId, changed=changed}, "identity-reconcile:" .. tostring(runtimeId or persistentId or "unknown"), changed == true)
    end

    return brain, changed == true
end

function NPCIdentityReconciliationBridge.ReconcileQueue(gmd, limit)
    if not (gmd and type(gmd.Queue) == "table") then return 0 end
    limit = tonumber(limit) or NPCIdentityReconciliationBridge.DefaultQueueBudget
    local changed = 0
    local scanned = 0
    for key, brain in pairs(gmd.Queue) do
        if scanned >= limit then break end
        scanned = scanned + 1
        if type(brain) == "table" then
            local runtimeId = brain.id or brain.runtimeId or key
            local normalized, didChange = NPCIdentityReconciliationBridge.NormalizeBrain(gmd, brain, runtimeId, brain.persistentId or brain.uid, brain.worldGroupId or brain.groupId, nil)
            if type(normalized) == "table" and didChange then changed = changed + 1 end
        end
    end
    return changed
end

function NPCIdentityReconciliationBridge.GroupHasQueuedBrain(gmd, groupId)
    if not (gmd and groupId and type(gmd.Queue) == "table") then return false end
    local gid = tostring(groupId)
    for _, brain in pairs(gmd.Queue) do
        if type(brain) == "table" and tostring(brain.worldGroupId or brain.groupId or "") == gid then return true end
    end
    return false
end

function NPCIdentityReconciliationBridge.ReconcileGroups(gmd, limit, allowSoftRevirtualize)
    if not (gmd and type(gmd.VirtualGroups) == "table") then return 0 end
    limit = tonumber(limit) or NPCIdentityReconciliationBridge.DefaultGroupBudget
    local changed = 0
    local scanned = 0
    for groupId, group in pairs(gmd.VirtualGroups) do
        if scanned >= limit then break end
        scanned = scanned + 1
        if type(group) == "table" then
            local keep = {}
            local removed = 0
            if type(group.physicalIds) == "table" then
                for _, runtimeId in ipairs(group.physicalIds) do
                    local brain = NPCIdentityReconciliationBridge.FindQueueBrain(gmd, runtimeId, nil)
                    if type(brain) == "table" then
                        keep[#keep + 1] = tostring(runtimeId)
                    else
                        removed = removed + 1
                    end
                end
            end
            if removed > 0 then
                if #keep > 0 then group.physicalIds = keep else group.physicalIds = nil end
                group.updatedAt = recon_now()
                changed = changed + 1
            end
            if allowSoftRevirtualize == true and group.activated == true and not NPCIdentityReconciliationBridge.GroupHasQueuedBrain(gmd, groupId) and group.spawnPending ~= true then
                group.activated = false
                group.virtual = true
                group.state = group.homeBaseId and "base_patrol" or (group.roadPatrol and (group.hostile and "red_road_patrol" or "green_road_patrol") or "roaming")
                group.spawnQueued = 0
                group.updatedAt = recon_now()
                changed = changed + 1
            end
            gmd.VirtualGroups[tostring(groupId)] = group
        end
    end
    return changed
end

function NPCIdentityReconciliationBridge.MarkerHasLiveRuntime(gmd, marker)
    if not (gmd and marker) then return false end
    local runtimeId = marker.runtimeId or marker.physicalId or marker.zombieId or recon_runtimeFromNpcMarkerId(marker.id)
    local persistentId = marker.persistentId or marker.uid
    local brain = NPCIdentityReconciliationBridge.FindQueueBrain(gmd, runtimeId, persistentId)
    if type(brain) == "table" then return true end
    if persistentId and NPCIdentityReconciliationBridge.FindProfile(gmd, persistentId) then return true end
    return false
end

function NPCIdentityReconciliationBridge.ReconcileMarkers(gmd, limit, sendRemove)
    if not (gmd and type(gmd.DebugMapMarkers) == "table") then return 0 end
    limit = tonumber(limit) or NPCIdentityReconciliationBridge.DefaultMarkerBudget
    local changed = 0
    local scanned = 0
    local removeIds = {}

    for id, marker in pairs(gmd.DebugMapMarkers) do
        if scanned >= limit then break end
        scanned = scanned + 1
        if type(marker) == "table" then
            if tostring(marker.markerType or "") == "npc" then
                if not NPCIdentityReconciliationBridge.MarkerHasLiveRuntime(gmd, marker) then
                    removeIds[#removeIds + 1] = tostring(id)
                end
            elseif tostring(marker.markerType or "") == "group" and marker.groupId then
                local group = gmd.VirtualGroups and (gmd.VirtualGroups[tostring(marker.groupId)] or gmd.VirtualGroups[marker.groupId]) or nil
                if type(group) == "table" then
                    marker.count = group.count or marker.count
                    marker.virtual = group.virtual ~= false
                    marker.active = group.activated == true
                    marker.spawnPending = group.spawnPending == true
                    marker.spawnQueued = tonumber(group.spawnQueued) or 0
                    marker.updatedAt = group.updatedAt or marker.updatedAt
                    gmd.DebugMapMarkers[id] = marker
                    changed = changed + 1
                end
            end
        end
    end

    for _, id in ipairs(removeIds) do
        gmd.DebugMapMarkers[id] = nil
        if sendRemove then pcall(function() sendRemove(id) end) end
        changed = changed + 1
    end

    return changed
end

function NPCIdentityReconciliationBridge.ReconcileGlobal(gmd, opts)
    if not gmd then return 0 end
    opts = opts or {}
    NPCIdentityReconciliationBridge.EnsureData(gmd)

    local worldAge = recon_now()
    local intervalSeconds = tonumber(opts.intervalSeconds) or NPCIdentityReconciliationBridge.DefaultIntervalSeconds
    local intervalHours = math.max(1, intervalSeconds) / 3600
    gmd.IdentityReconciliation = type(gmd.IdentityReconciliation) == "table" and gmd.IdentityReconciliation or {}
    if opts.force ~= true and gmd.IdentityReconciliation.lastAt and worldAge - tonumber(gmd.IdentityReconciliation.lastAt) < intervalHours then
        return 0
    end

    local changed = 0
    changed = changed + NPCIdentityReconciliationBridge.ReconcileQueue(gmd, opts.maxQueue)
    changed = changed + NPCIdentityReconciliationBridge.ReconcileGroups(gmd, opts.maxGroups, opts.allowSoftRevirtualize == true)
    changed = changed + NPCIdentityReconciliationBridge.ReconcileMarkers(gmd, opts.maxMarkers, opts.sendRemove)

    gmd.IdentityReconciliation.lastAt = worldAge
    gmd.IdentityReconciliation.lastReason = tostring(opts.reason or "periodic")
    gmd.IdentityReconciliation.lastChanged = changed
    gmd.IdentityReconciliation.version = NPCIdentityReconciliationBridge.Version
    if NPCDiagnosticsBridge and NPCDiagnosticsBridge.Log and changed > 0 then
        NPCDiagnosticsBridge.Log("NPC_IDENTITY", "global_reconcile", {reason=opts.reason or "periodic", changed=changed, queue=NPCDiagnosticsBridge.Count(gmd.Queue), groups=NPCDiagnosticsBridge.Count(gmd.VirtualGroups), markers=NPCDiagnosticsBridge.Count(gmd.DebugMapMarkers)}, "identity-global:" .. tostring(opts.reason or "periodic"), true)
    end
    return changed
end
