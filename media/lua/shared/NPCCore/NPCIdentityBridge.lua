-- NPCIdentityBridge.lua
-- Neutral shared backend for persistent NPC identity records.

NPCIdentityBridge = NPCIdentityBridge or {}

NPCIdentityBridge.Version = 2

function NPCIdentityBridge.GetWorldAgeHours()
    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then
            return gt:getWorldAgeHours()
        end
    end
    return 0
end

function NPCIdentityBridge.Copy(value, depth)
    depth = depth or 0
    if depth > 8 then return nil end
    if type(value) ~= "table" then return value end

    local ret = {}
    for k, v in pairs(value) do
        local tk = type(k)
        local tv = type(v)
        if (tk == "string" or tk == "number" or tk == "boolean") and tv ~= "function" and tv ~= "userdata" and tv ~= "thread" then
            if tv == "table" then
                ret[k] = NPCIdentityBridge.Copy(v, depth + 1)
            else
                ret[k] = v
            end
        end
    end

    return ret
end

function NPCIdentityBridge.EnsureGlobalData(gmd)
    if not gmd then return nil end

    if not gmd.Registry then gmd.Registry = {} end
    if not gmd.RuntimeToUID then gmd.RuntimeToUID = {} end
    if not gmd.UIDToRuntime then gmd.UIDToRuntime = {} end
    if not gmd.DeadRegistry then gmd.DeadRegistry = {} end
    if not gmd.PersistentNPCs then gmd.PersistentNPCs = {} end
    if not gmd.PersistentGroups then gmd.PersistentGroups = {} end
    if not gmd.PersistentRuntimeToUID then gmd.PersistentRuntimeToUID = {} end
    if not gmd.PersistentUIDToRuntime then gmd.PersistentUIDToRuntime = {} end
    if not gmd.NextPersistentId then gmd.NextPersistentId = 1 end
    if not gmd.SimStats then gmd.SimStats = {} end
    if not gmd.PersistentVersion or gmd.PersistentVersion < NPCIdentityBridge.Version then
        gmd.PersistentVersion = NPCIdentityBridge.Version
    end

    return gmd
end

function NPCIdentityBridge.NewUID(gmd)
    NPCIdentityBridge.EnsureGlobalData(gmd)

    local nextId = tonumber(gmd.NextPersistentId) or 1
    local uid = "bandit-" .. tostring(nextId)

    while gmd.Registry and gmd.Registry[uid] do
        nextId = nextId + 1
        uid = "bandit-" .. tostring(nextId)
    end

    gmd.NextPersistentId = nextId + 1
    return uid
end

function NPCIdentityBridge.EnsureOrder(brain)
    if not brain then return end

    if NPCOrderContract and NPCOrderContract.Ensure then
        NPCOrderContract.Ensure(brain)
        return
    end

    if not brain.order then
        brain.order = {
            name = "Auto",
            source = "system",
            issued = NPCIdentityBridge.GetWorldAgeHours(),
            fireMode = "FireAtWill"
        }
    elseif type(brain.order) == "string" then
        brain.order = {
            name = brain.order,
            source = "legacy",
            issued = NPCIdentityBridge.GetWorldAgeHours(),
            fireMode = "FireAtWill"
        }
    elseif not brain.order.fireMode then
        brain.order.fireMode = "FireAtWill"
    end
end

function NPCIdentityBridge.EnsureBrain(brain, gmd, runtimeId, allowNewUID)
    if not brain then return nil end

    NPCIdentityBridge.EnsureGlobalData(gmd)

    if brain.uid and not brain.persistentId then
        brain.persistentId = brain.uid
    elseif brain.persistentId and not brain.uid then
        brain.uid = brain.persistentId
    elseif not brain.uid and allowNewUID ~= false and gmd then
        brain.uid = NPCIdentityBridge.NewUID(gmd)
        brain.persistentId = brain.uid
    end

    if runtimeId and brain.uid and gmd then
        gmd.RuntimeToUID[tostring(runtimeId)] = brain.uid
        gmd.UIDToRuntime[brain.uid] = tostring(runtimeId)
    end

    if brain.id and brain.uid and gmd then
        gmd.RuntimeToUID[tostring(brain.id)] = brain.uid
        gmd.UIDToRuntime[brain.uid] = tostring(brain.id)
    end

    NPCIdentityBridge.EnsureOrder(brain)

    if not brain.sim then brain.sim = {} end
    brain.sim.version = NPCIdentityBridge.Version
    if not brain.sim.state then brain.sim.state = "Spawned" end
    if not brain.sim.order then brain.sim.order = brain.order and brain.order.name or "Auto" end
    if not brain.sim.fireMode then brain.sim.fireMode = brain.order and brain.order.fireMode or "FireAtWill" end
    if not brain.sim.created then brain.sim.created = brain.born or NPCIdentityBridge.GetWorldAgeHours() end
    if not brain.sim.updated then brain.sim.updated = NPCIdentityBridge.GetWorldAgeHours() end

    if not brain.watchdog then brain.watchdog = {} end
    if brain.watchdog.stuck == nil then brain.watchdog.stuck = false end
    if not brain.watchdog.stuckTicks then brain.watchdog.stuckTicks = 0 end
    if not brain.watchdog.lastMove then brain.watchdog.lastMove = NPCIdentityBridge.GetWorldAgeHours() end

    if not brain.debug then brain.debug = {} end
    brain.debug.state = brain.sim.state
    brain.debug.order = brain.sim.order
    brain.debug.fireMode = brain.sim.fireMode
    brain.debug.watchdog = brain.watchdog.stuck

    if brain.worldGroupId and not brain.groupId then
        brain.groupId = brain.worldGroupId
    elseif brain.groupId and not brain.worldGroupId then
        brain.worldGroupId = brain.groupId
    end

    return brain
end

function NPCIdentityBridge.ReadCoords(brain)
    if not brain then return nil end

    if brain.debugCoords and brain.debugCoords.x and brain.debugCoords.y then
        return tonumber(brain.debugCoords.x), tonumber(brain.debugCoords.y), tonumber(brain.debugCoords.z) or 0
    end

    if brain.x and brain.y then
        return tonumber(brain.x), tonumber(brain.y), tonumber(brain.z) or 0
    end

    if brain.bornCoords and brain.bornCoords.x and brain.bornCoords.y then
        return tonumber(brain.bornCoords.x), tonumber(brain.bornCoords.y), tonumber(brain.bornCoords.z) or 0
    end

    return nil
end

function NPCIdentityBridge.ReadCurrentTask(brain)
    if not brain or not brain.tasks or not brain.tasks[1] then return nil end

    local task = brain.tasks[1]
    if type(task) ~= "table" then return nil end

    return {
        action = task.action,
        state = task.state,
        x = task.x,
        y = task.y,
        z = task.z,
        time = task.time,
        target = task.target,
        slot = task.slot,
        directorState = task.directorState,
        directorReason = task.directorReason
    }
end

function NPCIdentityBridge.BuildSnapshot(gmd, brain, runtimeId)
    if not brain then return nil end

    NPCIdentityBridge.EnsureGlobalData(gmd)
    brain = NPCIdentityBridge.EnsureBrain(brain, gmd, runtimeId or brain.id, true)

    local x, y, z = NPCIdentityBridge.ReadCoords(brain)
    local programName = nil
    local programStage = nil
    if brain.program then
        programName = brain.program.name
        programStage = brain.program.stage
    end

    local orderName = nil
    local fireMode = nil
    if brain.order then
        orderName = brain.order.name or brain.order
        fireMode = brain.order.fireMode
    end

    return {
        uid = brain.uid,
        persistentId = brain.persistentId or brain.uid,
        id = brain.id,
        runtimeId = runtimeId or brain.id,
        fullname = brain.fullname,
        female = brain.female,
        voice = brain.voice,
        outfit = brain.outfit,
        appearanceSeed = brain.appearanceSeed,
        faceProfile = brain.faceProfile,
        skinTexture = brain.skinTexture,
        skinColor = NPCIdentityBridge.Copy(brain.skinColor),
        hairStyle = brain.hairStyle,
        hairColor = NPCIdentityBridge.Copy(brain.hairColor),
        beardStyle = brain.beardStyle,
        beardColor = NPCIdentityBridge.Copy(brain.beardColor),

        clan = brain.clan,
        hostile = brain.hostile,
        relationship = brain.relationship or (brain.hostile and "hostile" or "friendly"),
        master = brain.master,

        health = brain.health,
        maxHealth = brain.maxHealth,
        endurance = brain.endurance,
        infection = brain.infection,

        role = brain.role,
        tacticalRole = brain.tacticalRole,
        relationshipToPlayer = brain.relationshipToPlayer or brain.relationship,
        currentWeapon = NPCIdentityBridge.Copy(brain.currentWeapon),
        ammo = NPCIdentityBridge.Copy(brain.ammo),
        inventoryLite = NPCIdentityBridge.Copy(brain.inventoryLite),
        needs = NPCIdentityBridge.Copy(brain.needs or (brain.ai and brain.ai.needs)),
        stock = NPCIdentityBridge.Copy(brain.stock or (brain.ai and brain.ai.stock)),
        skills = NPCIdentityBridge.Copy(brain.skills or (brain.ai and brain.ai.skills)),
        xp = NPCIdentityBridge.Copy(brain.xp or (brain.ai and brain.ai.xp)),
        morale = brain.morale or (brain.ai and brain.ai.morale),
        fear = brain.fear or (brain.ai and brain.ai.fear),
        aggression = brain.aggression or (brain.ai and brain.ai.aggression),
        discipline = brain.discipline or (brain.ai and brain.ai.discipline),
        lastKnownEnemyPosition = NPCIdentityBridge.Copy(brain.lastKnownEnemyPosition or (brain.ai and brain.ai.lastKnownEnemyPosition)),

        weapons = NPCIdentityBridge.Copy(brain.weapons),
        inventory = NPCIdentityBridge.Copy(brain.inventory),
        loot = NPCIdentityBridge.Copy(brain.loot),
        key = NPCIdentityBridge.Copy(brain.key),

        x = x,
        y = y,
        z = z or 0,
        born = brain.born,
        bornCoords = NPCIdentityBridge.Copy(brain.bornCoords),

        program = NPCIdentityBridge.Copy(brain.program),
        programName = programName,
        programStage = programStage,
        order = NPCIdentityBridge.Copy(brain.order),
        orderName = orderName,
        fireMode = fireMode,
        sim = NPCIdentityBridge.Copy(brain.sim),
        state = brain.state or (brain.sim and brain.sim.state),
        reason = brain.reason,
        fsm = NPCIdentityBridge.Copy(brain.fsm),
        watchdog = NPCIdentityBridge.Copy(brain.watchdog),
        debug = NPCIdentityBridge.Copy(brain.debug),
        lastTask = NPCIdentityBridge.ReadCurrentTask(brain),

        groupId = brain.groupId or brain.worldGroupId,
        worldGroupId = brain.worldGroupId or brain.groupId,
        worldDirector = brain.worldDirector,
        memberIndex = brain.memberIndex,
        homeBase = NPCIdentityBridge.Copy(brain.homeBase or brain.base or brain.baseId),
        homeBaseId = brain.homeBaseId or brain.baseId,

        permanent = brain.permanent,
        dead = brain.dead == true,
        updated = NPCIdentityBridge.GetWorldAgeHours(),
        version = NPCIdentityBridge.Version
    }
end

function NPCIdentityBridge.TouchRegistry(gmd, brain, runtimeId)
    if not (gmd and brain) then return nil end

    NPCIdentityBridge.EnsureGlobalData(gmd)

    local snapshot = NPCIdentityBridge.BuildSnapshot(gmd, brain, runtimeId)
    if not snapshot or not snapshot.uid then return nil end

    local old = gmd.Registry[snapshot.uid]
    if old and old.dead and not snapshot.dead then
        snapshot.dead = false
        snapshot.revivedAt = NPCIdentityBridge.GetWorldAgeHours()
    end

    gmd.Registry[snapshot.uid] = snapshot
    if NPCPersistentNPCBridge and NPCPersistentNPCBridge.TouchFromSnapshot then
        NPCPersistentNPCBridge.TouchFromSnapshot(gmd, snapshot, brain)
    end

    if snapshot.runtimeId then
        gmd.RuntimeToUID[tostring(snapshot.runtimeId)] = snapshot.uid
        gmd.UIDToRuntime[snapshot.uid] = tostring(snapshot.runtimeId)
    end

    if snapshot.id then
        gmd.RuntimeToUID[tostring(snapshot.id)] = snapshot.uid
        gmd.UIDToRuntime[snapshot.uid] = tostring(snapshot.id)
    end

    return snapshot
end

function NPCIdentityBridge.TouchVirtualMember(gmd, member, group, index)
    if not (gmd and member and group) then return nil end

    NPCIdentityBridge.EnsureGlobalData(gmd)

    if not member.uid then
        member.uid = NPCIdentityBridge.NewUID(gmd)
        member.persistentId = member.uid
    elseif not member.persistentId then
        member.persistentId = member.uid
    end

    member.worldGroupId = group.id
    member.groupId = group.id
    member.memberIndex = index or member.memberIndex
    if not member.bornCoords then
        member.bornCoords = {x=group.x, y=group.y, z=group.z or 0}
    end

    local programName = group.program and group.program.name or nil
    local programStage = group.program and group.program.stage or nil

    local record = {
        uid = member.uid,
        persistentId = member.persistentId,
        id = member.id,
        runtimeId = member.id,
        fullname = member.fullname,
        female = member.female,
        outfit = member.outfit,
        clan = member.clan or group.clanId,
        hostile = group.hostile,
        relationship = group.hostile and "hostile" or "friendly",
        health = member.health,
        weapons = NPCIdentityBridge.Copy(member.weapons),
        inventory = NPCIdentityBridge.Copy(member.inventory),
        loot = NPCIdentityBridge.Copy(member.loot),
        key = NPCIdentityBridge.Copy(member.key),
        x = group.x,
        y = group.y,
        z = group.z or 0,
        born = member.born or group.createdAt,
        bornCoords = NPCIdentityBridge.Copy(member.bornCoords),
        program = NPCIdentityBridge.Copy(group.program),
        programName = programName,
        programStage = programStage,
        groupId = group.id,
        worldGroupId = group.id,
        worldDirector = true,
        memberIndex = index or member.memberIndex,
        virtual = group.virtual ~= false,
        state = group.state or "virtual",
        homeBase = NPCIdentityBridge.Copy(member.homeBase),
        dead = false,
        updated = NPCIdentityBridge.GetWorldAgeHours(),
        version = NPCIdentityBridge.Version
    }

    gmd.Registry[member.uid] = record
    if NPCPersistentNPCBridge and NPCPersistentNPCBridge.TouchVirtualMember then
        NPCPersistentNPCBridge.TouchVirtualMember(gmd, member, group, index)
    end
    return record
end

function NPCIdentityBridge.TouchVirtualGroup(gmd, group)
    if not (gmd and group and group.members) then return end

    NPCIdentityBridge.EnsureGlobalData(gmd)

    for i, member in ipairs(group.members) do
        NPCIdentityBridge.TouchVirtualMember(gmd, member, group, i)
    end
end

function NPCIdentityBridge.GetUIDByRuntimeId(gmd, runtimeId)
    if not (gmd and runtimeId) then return nil end
    NPCIdentityBridge.EnsureGlobalData(gmd)

    local uid = gmd.RuntimeToUID and gmd.RuntimeToUID[tostring(runtimeId)]
    if uid then return uid end

    if gmd.Queue and gmd.Queue[runtimeId] and gmd.Queue[runtimeId].uid then
        return gmd.Queue[runtimeId].uid
    end

    local sid = tostring(runtimeId)
    if gmd.Queue and gmd.Queue[sid] and gmd.Queue[sid].uid then
        return gmd.Queue[sid].uid
    end

    return nil
end

function NPCIdentityBridge.MarkDead(gmd, brainOrRuntimeId, runtimeId)
    if not gmd then return end

    NPCIdentityBridge.EnsureGlobalData(gmd)

    local brain = nil
    local id = runtimeId

    if type(brainOrRuntimeId) == "table" then
        brain = brainOrRuntimeId
        id = id or brain.id
    else
        id = brainOrRuntimeId
        if gmd.Queue then
            brain = gmd.Queue[id] or gmd.Queue[tostring(id)]
        end
    end

    local uid = nil
    if brain and brain.uid then
        uid = brain.uid
    elseif id then
        uid = NPCIdentityBridge.GetUIDByRuntimeId(gmd, id)
    end

    if uid then
        if NPCDiagnosticsBridge and NPCDiagnosticsBridge.Log then
            NPCDiagnosticsBridge.Log("MARK_DEAD", "NPCIdentity.MarkDead resolved UID", {runtimeId=id, uid=uid, brainId=brain and brain.id or nil, persistentId=brain and brain.persistentId or nil, groupId=brain and (brain.worldGroupId or brain.groupId) or nil}, "markdead:" .. tostring(uid), true)
        end
        local record = gmd.Registry and gmd.Registry[uid] or {}
        if brain then
            local snapshot = NPCIdentityBridge.BuildSnapshot(gmd, brain, id)
            if snapshot then record = snapshot end
        end

        record.uid = uid
        record.dead = true
        record.deathAt = NPCIdentityBridge.GetWorldAgeHours()
        record.updated = record.deathAt
        gmd.Registry[uid] = record
        gmd.DeadRegistry[uid] = record
        if NPCPersistentNPCBridge and NPCPersistentNPCBridge.MarkDead then
            NPCPersistentNPCBridge.MarkDead(gmd, record)
        end

        if id then
            gmd.RuntimeToUID[tostring(id)] = nil
        end
        if gmd.UIDToRuntime then
            gmd.UIDToRuntime[uid] = nil
        end
    end
end

function NPCIdentityBridge.RemoveFromRegistryByRuntimeId(gmd, runtimeId)
    NPCIdentityBridge.MarkDead(gmd, runtimeId, runtimeId)
end
