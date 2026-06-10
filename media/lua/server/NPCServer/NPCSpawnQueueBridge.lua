-- NPCSpawnQueueBridge.lua
-- Neutral server-side queued NPC materialization backend.

require "NPCCore/NPCLegacyGlobalsBridge"

local NPC_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
if isClient and isClient() then return end

NPCSpawnQueueBridge = NPCSpawnQueueBridge or {}
NPCSpawnQueueBridge.Queue = NPCSpawnQueueBridge.Queue or {}
NPCSpawnQueueBridge.Head = NPCSpawnQueueBridge.Head or 1
NPCSpawnQueueBridge.Tick = NPCSpawnQueueBridge.Tick or 0
NPCSpawnQueueBridge.MaxEventsPerTick = NPCSpawnQueueBridge.MaxEventsPerTick or 1
if NPCLegacySettingsBridge then
    NPCSpawnQueueBridge.MaxEventsPerTick = NPCLegacySettingsBridge.GetNumber("SpawnQueue_MaxEventsPerTick", NPCSpawnQueueBridge.MaxEventsPerTick, 1, 50)
end

local function bsq_cloneEvent(event)
    local e = {}
    for k, v in pairs(event or {}) do
        e[k] = v
    end
    return e
end

local function bsq_groupCount(event)
    if type(event) ~= "table" or type(event.bandits) ~= "table" then return 0 end
    local n = #event.bandits
    if n > 0 then return n end
    for _ in pairs(event.bandits) do
        n = n + 1
    end
    return n
end

local function bsq_groupKey(groupId, event)
    local key = groupId or (type(event) == "table" and event.worldGroupId)
    if key == nil then return nil end
    key = tostring(key)
    if key == "" or key == "nil" then return nil end
    return key
end

local function bsq_pendingForGroup(groupId)
    groupId = bsq_groupKey(groupId)
    if not groupId then return 0 end

    local n = 0
    local head = tonumber(NPCSpawnQueueBridge.Head) or 1
    for i = head, #NPCSpawnQueueBridge.Queue do
        local entry = NPCSpawnQueueBridge.Queue[i]
        if entry and tostring(entry.groupId or "") == groupId then
            n = n + 1
        end
    end
    return n
end

local function bsq_retryDelayTicks(retryCount)
    local base = (NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber("SpawnQueue_RetryDelayTicks", 12, 1, 600)) or 12
    local maxDelay = (NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber("SpawnQueue_MaxRetryDelayTicks", 180, base, 3600)) or 180
    local retries = math.max(1, tonumber(retryCount) or 1)
    local delay = base * retries
    if delay > maxDelay then delay = maxDelay end
    return math.max(1, math.floor(delay))
end

local function bsq_refreshGroupMarker(gmd, groupId, group)
    if not (gmd and groupId and group) then return end

    if NPCWorldDirectorServer and NPCWorldDirectorServer.UpdateRoadPatrolMarker and group.roadPatrol then
        NPCWorldDirectorServer.UpdateRoadPatrolMarker(gmd, group)
        return
    end

    local refresher = NPC_LEGACY_GLOBALS.Get("RefreshWorldGroupMarker")
    if refresher then
        refresher(gmd, groupId)
        return
    end

    if type(gmd.DebugMapMarkers) == "table" then
        local marker = gmd.DebugMapMarkers[tostring(groupId)]
        if marker then
            marker.state = group.state
            marker.spawnPending = group.spawnPending or false
            marker.spawnQueued = group.spawnQueued or 0
            marker.updatedAt = group.updatedAt
            gmd.DebugMapMarkers[tostring(groupId)] = marker
            if NPCNetContract and NPCNetContract.SendDebugMapUpdate then
                NPCNetContract.SendDebugMapUpdate(marker)
            else
                sendServerCommand('NPCDebugMap', 'Update', marker)
            end
        end
    end
end

local function bsq_finishGroupQueue(entry, reason)
    if not (entry and entry.groupId and GetNPCModData) then return end

    local gmd = GetNPCModData()
    local groupId = tostring(entry.groupId)
    local group = gmd and gmd.VirtualGroups and gmd.VirtualGroups[groupId] or nil
    if not group then return end

    group.spawnPending = false
    group.spawnQueued = 0
    if group.state == "spawning" then group.state = "physical" end
    group.lastSpawnQueueDropReason = reason
    group.updatedAt = getGameTime and getGameTime():getWorldAgeHours() or group.updatedAt
    gmd.VirtualGroups[groupId] = group
    bsq_refreshGroupMarker(gmd, groupId, group)
end

function NPCSpawnQueueBridge.Enqueue(event, nextIndex, totalCount, groupId)
    if NPCLegacySettingsBridge and not NPCLegacySettingsBridge.GetBool("SpawnQueue_Enabled", true) then return false end
    if type(event) ~= "table" or type(event.bandits) ~= "table" then return false end

    local key = bsq_groupKey(groupId, event)
    if key then
        local maxPendingPerGroup = (NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber("SpawnQueue_MaxPendingPerGroup", 1, 1, 50)) or 1
        if bsq_pendingForGroup(key) >= maxPendingPerGroup then
            if NPCDiagnosticsBridge and NPCDiagnosticsBridge.Log then
                NPCDiagnosticsBridge.Log("SPAWN_QUEUE", "enqueue rejected: duplicate group queue", {groupId=key, pendingForGroup=bsq_pendingForGroup(key), maxPendingPerGroup=maxPendingPerGroup}, "spawnq-duplicate:" .. tostring(key), true)
            end
            return false
        end
    end

    local maxPending = (NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber("SpawnQueue_MaxPending", 180, 1, 5000)) or 180
    if NPCSpawnQueueBridge.PendingCount() >= maxPending then
        if NPCDiagnosticsBridge and NPCDiagnosticsBridge.Log then
            NPCDiagnosticsBridge.Log("SPAWN_QUEUE", "enqueue rejected: pending limit reached", {groupId=groupId or event.worldGroupId, pending=NPCSpawnQueueBridge.PendingCount(), maxPending=maxPending}, "spawnq-reject:" .. tostring(groupId or event.worldGroupId or "unknown"), true)
        end
        return false
    end

    nextIndex = tonumber(nextIndex) or 1
    totalCount = tonumber(totalCount) or bsq_groupCount(event)

    if nextIndex > totalCount then return false end

    local entry = {
        event = bsq_cloneEvent(event),
        nextIndex = nextIndex,
        totalCount = totalCount,
        groupId = key or groupId or event.worldGroupId,
        createdAt = getGameTime and getGameTime():getWorldAgeHours() or 0
    }

    table.insert(NPCSpawnQueueBridge.Queue, entry)
    if NPCDiagnosticsBridge and NPCDiagnosticsBridge.Log then
        NPCDiagnosticsBridge.Log("SPAWN_QUEUE", "group spawn queued", {groupId=entry.groupId, nextIndex=entry.nextIndex, totalCount=entry.totalCount, pending=NPCSpawnQueueBridge.PendingCount()}, "spawnq-enqueue:" .. tostring(entry.groupId or "unknown"), true)
    end
    return true
end


function NPCSpawnQueueBridge.CancelGroup(groupId, reason)
    groupId = bsq_groupKey(groupId)
    if not groupId then return 0 end

    local removed = 0
    local head = tonumber(NPCSpawnQueueBridge.Head) or 1
    for i = head, #NPCSpawnQueueBridge.Queue do
        local entry = NPCSpawnQueueBridge.Queue[i]
        if entry and tostring(entry.groupId or "") == groupId then
            NPCSpawnQueueBridge.Queue[i] = false
            removed = removed + 1
        end
    end

    if removed > 0 then
        NPCSpawnQueueBridge.Compact()
        if NPCDiagnosticsBridge and NPCDiagnosticsBridge.Log then
            NPCDiagnosticsBridge.Log("SPAWN_QUEUE", "cancelled pending group spawn queue", {groupId=groupId, removed=removed, reason=reason}, "spawnq-cancel:" .. tostring(groupId), true)
        end
        bsq_finishGroupQueue({groupId = groupId}, reason or "group_spawn_queue_cancelled")
    end

    return removed
end

function NPCSpawnQueueBridge.HasPending(groupId)
    if not groupId then return false end
    groupId = tostring(groupId)
    local head = tonumber(NPCSpawnQueueBridge.Head) or 1
    for i = head, #NPCSpawnQueueBridge.Queue do
        local entry = NPCSpawnQueueBridge.Queue[i]
        if entry and tostring(entry.groupId) == groupId then return true end
    end
    return false
end

function NPCSpawnQueueBridge.PendingCount()
    local n = 0
    local head = tonumber(NPCSpawnQueueBridge.Head) or 1
    for i = head, #NPCSpawnQueueBridge.Queue do
        if NPCSpawnQueueBridge.Queue[i] then
            n = n + 1
        end
    end
    return n
end

function NPCSpawnQueueBridge.Compact()
    local newQueue = {}
    local head = tonumber(NPCSpawnQueueBridge.Head) or 1
    for i = head, #NPCSpawnQueueBridge.Queue do
        local entry = NPCSpawnQueueBridge.Queue[i]
        if entry then
            table.insert(newQueue, entry)
        end
    end
    NPCSpawnQueueBridge.Queue = newQueue
    NPCSpawnQueueBridge.Head = 1
end

function NPCSpawnQueueBridge.ProcessEntry(entry)
    if not entry or not entry.event then return true end
    local serverRuntime = NPCServerRuntime or NPC_LEGACY_GLOBALS.Get("ServerRuntime")
    if not serverRuntime or not serverRuntime.Commands or not serverRuntime.Commands.SpawnGroup then return false end

    local totalCount = tonumber(entry.totalCount) or bsq_groupCount(entry.event)
    local nextIndex = tonumber(entry.nextIndex) or 1
    if nextIndex > totalCount then
        bsq_finishGroupQueue(entry, nil)
        return true
    end

    local retryAfterTick = tonumber(entry.retryAfterTick) or 0
    if retryAfterTick > 0 and (tonumber(NPCSpawnQueueBridge.Tick) or 0) < retryAfterTick then
        return false
    end

    local batch = (NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber("SpawnQueue_MaxPerTick", 3, 1, 100)) or 3
    if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.GetSpawnBatch then
        batch = tonumber(NPCWorkSchedulerBridge.GetSpawnBatch()) or batch
    end
    if NPCCrowdBudgetBridge and NPCCrowdBudgetBridge.AdjustQueuedSpawnBatch then
        batch = NPCCrowdBudgetBridge.AdjustQueuedSpawnBatch(entry, batch)
    end
    if NPCWorldDirectorServer and NPCWorldDirectorServer.AdjustQueuedSpawnBatch then
        local adjustedBatch, deferTicks, deferReason = NPCWorldDirectorServer.AdjustQueuedSpawnBatch(entry, batch)
        adjustedBatch = tonumber(adjustedBatch) or 0
        if adjustedBatch < 1 then
            entry.retryAfterTick = (tonumber(NPCSpawnQueueBridge.Tick) or 0) + math.max(30, tonumber(deferTicks) or 180)
            entry.lastDeferReason = deferReason or "proxy_lod_spawn_queue_defer"
            if entry.groupId and GetNPCModData then
                local gmd = GetNPCModData()
                local group = gmd and gmd.VirtualGroups and gmd.VirtualGroups[tostring(entry.groupId)] or nil
                if group then
                    group.lastActivationDeferReason = entry.lastDeferReason
                    group.retryAfter = getGameTime and (getGameTime():getWorldAgeHours() + math.max(1, tonumber(NPCWorldDirectorServer.PROXY_LOD_RETRY_SECONDS) or 18) / 3600) or group.retryAfter
                    group.updatedAt = getGameTime and getGameTime():getWorldAgeHours() or group.updatedAt
                    gmd.VirtualGroups[tostring(entry.groupId)] = group
                    bsq_refreshGroupMarker(gmd, tostring(entry.groupId), group)
                end
            end
            return false
        end
        batch = adjustedBatch
    end
    if batch < 1 then batch = 1 end

    local event = bsq_cloneEvent(entry.event)
    event.spawnStart = nextIndex
    event.spawnLimit = batch
    event.spawnQueued = true

    local ok, spawnedOrError = pcall(function()
        return serverRuntime.Commands.SpawnGroup(nil, event)
    end)

    if not ok then
        entry.retryCount = (tonumber(entry.retryCount) or 0) + 1
        local maxRetries = (NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber("SpawnQueue_MaxRetries", 8, 0, 100)) or 8
        print("[NPCSpawnQueue] SpawnGroup failed: " .. tostring(spawnedOrError))
        if NPCDiagnosticsBridge and NPCDiagnosticsBridge.Log then
            NPCDiagnosticsBridge.Log("SPAWN_QUEUE", "SpawnGroup pcall failed", {groupId=entry.groupId, error=spawnedOrError, retryCount=entry.retryCount, nextIndex=nextIndex, totalCount=totalCount}, "spawnq-error:" .. tostring(entry.groupId or "unknown"), true)
        end
        if entry.retryCount > maxRetries then
            bsq_finishGroupQueue(entry, "spawn_group_error_drop")
            return true
        end
        entry.retryAfterTick = (tonumber(NPCSpawnQueueBridge.Tick) or 0) + bsq_retryDelayTicks(entry.retryCount)
        return false
    end

    local spawned = tonumber(spawnedOrError) or 0
    if spawned <= 0 then
        entry.retryCount = (tonumber(entry.retryCount) or 0) + 1
        local maxRetries = (NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber("SpawnQueue_MaxRetries", 8, 0, 100)) or 8
        if entry.retryCount > maxRetries then
            print("[NPCSpawnQueue] Dropping stalled group " .. tostring(entry.groupId))
            if NPCDiagnosticsBridge and NPCDiagnosticsBridge.Log then
                NPCDiagnosticsBridge.Log("SPAWN_QUEUE", "dropping stalled group after repeated zero-spawn attempts", {groupId=entry.groupId, retryCount=entry.retryCount, nextIndex=nextIndex, totalCount=totalCount}, "spawnq-drop:" .. tostring(entry.groupId or "unknown"), true)
            end
            bsq_finishGroupQueue(entry, "zero_spawn_drop")
            return true
        end
        entry.retryAfterTick = (tonumber(NPCSpawnQueueBridge.Tick) or 0) + bsq_retryDelayTicks(entry.retryCount)
        return false
    end

    entry.retryCount = 0
    entry.retryAfterTick = nil

    if NPCDiagnosticsBridge and NPCDiagnosticsBridge.Verbose then
        NPCDiagnosticsBridge.Verbose("SPAWN_QUEUE", "spawn queue batch processed", {groupId=entry.groupId, spawned=spawned, nextIndex=nextIndex, batch=batch, totalCount=totalCount}, "spawnq-batch:" .. tostring(entry.groupId or "unknown"))
    end

    entry.nextIndex = nextIndex + batch

    if entry.groupId then
        local gmd = GetNPCModData()
        local groupId = tostring(entry.groupId)
        local group = gmd and gmd.VirtualGroups and gmd.VirtualGroups[groupId] or nil
        if group then
            group.spawnPending = entry.nextIndex <= totalCount
            group.spawnQueued = math.max(0, totalCount - entry.nextIndex + 1)
            if group.spawnPending then
                group.state = "spawning"
            else
                group.state = "physical"
            end
            group.updatedAt = getGameTime():getWorldAgeHours()
            gmd.VirtualGroups[groupId] = group
            if NPCWorldDirectorServer and NPCWorldDirectorServer.UpdateRoadPatrolMarker and group.roadPatrol then
                NPCWorldDirectorServer.UpdateRoadPatrolMarker(gmd, group)
            else
                local refresher = NPC_LEGACY_GLOBALS.Get("RefreshWorldGroupMarker")
                if refresher then
                    refresher(gmd, groupId)
                end
            end
        end
    end

    return entry.nextIndex > totalCount
end

function NPCSpawnQueueBridge.OnTick()
    NPCSpawnQueueBridge.Tick = (NPCSpawnQueueBridge.Tick or 0) + 1

    if NPCLegacySettingsBridge then
        NPCSpawnQueueBridge.MaxEventsPerTick = NPCLegacySettingsBridge.GetNumber("SpawnQueue_MaxEventsPerTick", NPCSpawnQueueBridge.MaxEventsPerTick or 1, 1, 50)
    end

    if NPCSpawnQueueBridge.PendingCount() <= 0 then return end
    if NPCStreamingRuntimeBridge and NPCStreamingRuntimeBridge.ShouldSkipSpawnTick and NPCStreamingRuntimeBridge.ShouldSkipSpawnTick(NPCSpawnQueueBridge.Tick) then return end

    local maxEvents = tonumber(NPCSpawnQueueBridge.MaxEventsPerTick) or 1
    if NPCStreamingRuntimeBridge and NPCStreamingRuntimeBridge.AdjustSpawnEventBudget then
        maxEvents = NPCStreamingRuntimeBridge.AdjustSpawnEventBudget(maxEvents)
    end

    local processed = 0
    local i = tonumber(NPCSpawnQueueBridge.Head) or 1
    while i <= #NPCSpawnQueueBridge.Queue and processed < maxEvents do
        local entry = NPCSpawnQueueBridge.Queue[i]
        local retryAfterTick = entry and tonumber(entry.retryAfterTick) or 0
        if retryAfterTick > 0 and (tonumber(NPCSpawnQueueBridge.Tick) or 0) < retryAfterTick then
            i = i + 1
        else
            local done = NPCSpawnQueueBridge.ProcessEntry(entry)
            processed = processed + 1
            if done then
                NPCSpawnQueueBridge.Queue[i] = false
            end
            i = i + 1
        end
    end
    NPCSpawnQueueBridge.Compact()
end

if Events and Events.OnTick and not NPCSpawnQueueBridge._registered then
    NPCSpawnQueueBridge._registered = true
    Events.OnTick.Add(NPCSpawnQueueBridge.OnTick)
end
