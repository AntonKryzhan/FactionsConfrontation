-- NPCGroupLifecycleBridge.lua
-- Shared helper for virtual/queued/physical group lifecycle state transitions.
-- This bridge keeps existing state strings and ModData layout intact; it only
-- centralizes safe state assignment for systems that opt into it.

NPCGroupLifecycleBridge = NPCGroupLifecycleBridge or {}
NPCGroupLifecycleBridge.VERSION = "2026-06-02-stage354-passive-lifecycle-1"

NPCGroupLifecycleBridge.State = {
    VIRTUAL = "virtual",
    QUEUED = "queued_for_spawn",
    SPAWNING = "spawning",
    PHYSICAL = "physical",
    SLEEPING = "sleeping",
    DESPAWNING = "despawning",
    DEAD = "dead"
}

local function ngl_nowHours()
    if getGameTime then
        local ok, hours = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok and hours then return tonumber(hours) or 0 end
    end
    return 0
end

function NPCGroupLifecycleBridge.Touch(group, reason)
    if type(group) ~= "table" then return group end
    group.updatedAt = ngl_nowHours()
    if reason ~= nil then group.lastLifecycleReason = tostring(reason) end
    return group
end

function NPCGroupLifecycleBridge.SetState(group, state, reason)
    if type(group) ~= "table" then return group end
    state = tostring(state or group.state or NPCGroupLifecycleBridge.State.VIRTUAL)
    group.state = state
    return NPCGroupLifecycleBridge.Touch(group, reason)
end

function NPCGroupLifecycleBridge.SetQueued(group, pendingCount, reason)
    if type(group) ~= "table" then return group end
    group.spawnPending = true
    group.spawnQueued = math.max(0, tonumber(pendingCount) or tonumber(group.spawnQueued) or 0)
    return NPCGroupLifecycleBridge.SetState(group, NPCGroupLifecycleBridge.State.QUEUED, reason or "spawn_queue")
end

function NPCGroupLifecycleBridge.SetSpawning(group, pendingCount, reason)
    if type(group) ~= "table" then return group end
    group.spawnPending = true
    group.spawnQueued = math.max(0, tonumber(pendingCount) or tonumber(group.spawnQueued) or 0)
    return NPCGroupLifecycleBridge.SetState(group, NPCGroupLifecycleBridge.State.SPAWNING, reason or "spawning")
end

function NPCGroupLifecycleBridge.SetPhysical(group, reason)
    if type(group) ~= "table" then return group end
    group.spawnPending = false
    group.spawnQueued = 0
    return NPCGroupLifecycleBridge.SetState(group, NPCGroupLifecycleBridge.State.PHYSICAL, reason or "physical")
end

function NPCGroupLifecycleBridge.SetVirtual(group, reason)
    if type(group) ~= "table" then return group end
    group.spawnPending = false
    group.spawnQueued = 0
    return NPCGroupLifecycleBridge.SetState(group, NPCGroupLifecycleBridge.State.VIRTUAL, reason or "virtual")
end

function NPCGroupLifecycleBridge.SetSleeping(group, reason)
    if type(group) ~= "table" then return group end
    group.spawnPending = false
    group.spawnQueued = 0
    return NPCGroupLifecycleBridge.SetState(group, NPCGroupLifecycleBridge.State.SLEEPING, reason or "sleeping")
end

function NPCGroupLifecycleBridge.SetDead(group, reason)
    if type(group) ~= "table" then return group end
    group.spawnPending = false
    group.spawnQueued = 0
    return NPCGroupLifecycleBridge.SetState(group, NPCGroupLifecycleBridge.State.DEAD, reason or "dead")
end
