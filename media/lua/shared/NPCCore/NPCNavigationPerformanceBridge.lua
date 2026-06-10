-- NPCNavigationPerformanceBridge.lua
-- Neutral shared backend for navigation performance, repair queue and portal pressure.
-- Lightweight navigation repair layer for NPC movement.
-- Keeps pathfinding bounded by repairing only delayed/stuck movers and by
-- remembering bad cells/portal pressure instead of constantly replanning all NPCs.

require "NPCCore/NPCLegacyContractBridge"

NPCNavigationPerformanceBridge = NPCNavigationPerformanceBridge or {}

NPCNavigationPerformanceBridge.VERSION = "2026-06-10-stage454-safe-queue-compaction-1"
local BNP_LEGACY_ENTITY_GLOBAL = NPCLegacyContractBridge.Key("FLAG")

local function bnp_entity()
    return NPCEntity or (_G and _G[BNP_LEGACY_ENTITY_GLOBAL]) or nil
end

NPCNavigationPerformanceBridge.Config = NPCNavigationPerformanceBridge.Config or {
    enabled = true,
    repairQueueEnabled = true,
    repairPerTick = 2,
    maxRepairQueue = 64,
    repairCooldownMs = 1250,
    repairHoldMs = 2200,
    badCellCooldownMs = 90000,
    badCellMaxRecords = 360,
    badCellPenalty = 7.5,
    badTargetPenalty = 12.0,
    crowdPenalty = 2.2,
    crowdRadius = 1,
    densityCacheMs = 220,
    densityHighCost = 8.0,
    densityCriticalCost = 16.0,
    portalGuardEnabled = true,
    portalHoldMs = 1100,
    portalPenalty = 6.0,
    portalQueueEnabled = true,
    portalQueueHoldMs = 8500,
    portalQueueWaitMs = 650,
    portalQueueMaxWaitMs = 6500,
    portalQueueMaxPerPortal = 6,
    portalQueueStaleMs = 12000,
    progressReward = 1.2,
    debug = false
}

NPCNavigationPerformanceBridge.RepairQueue = NPCNavigationPerformanceBridge.RepairQueue or {}
NPCNavigationPerformanceBridge.RepairIds = NPCNavigationPerformanceBridge.RepairIds or {}
NPCNavigationPerformanceBridge.BadCells = NPCNavigationPerformanceBridge.BadCells or {}
NPCNavigationPerformanceBridge.PortalClaims = NPCNavigationPerformanceBridge.PortalClaims or {}
NPCNavigationPerformanceBridge.PortalQueues = NPCNavigationPerformanceBridge.PortalQueues or {}
NPCNavigationPerformanceBridge.DensityCache = NPCNavigationPerformanceBridge.DensityCache or {}
NPCNavigationPerformanceBridge.Stats = NPCNavigationPerformanceBridge.Stats or {
    queued = 0,
    repaired = 0,
    skipped = 0,
    dropped = 0,
    badCells = 0,
    portalsQueued = 0,
    portalsGranted = 0,
    portalsReleased = 0,
    portalsSkipped = 0
}

local function bnp_number(name, defaultValue, minValue, maxValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        return NPCLegacySettingsBridge.GetNumber(name, defaultValue, minValue, maxValue)
    end
    local value = tonumber(defaultValue) or 0
    if minValue ~= nil and value < minValue then value = minValue end
    if maxValue ~= nil and value > maxValue then value = maxValue end
    return value
end

local function bnp_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        return NPCLegacySettingsBridge.GetBool(name, defaultValue == true)
    end
    return defaultValue == true
end

function NPCNavigationPerformanceBridge.ApplySettings()
    local c = NPCNavigationPerformanceBridge.Config
    c.enabled = bnp_bool("NavPerf_Enabled", c.enabled ~= false)
    c.repairQueueEnabled = bnp_bool("NavPerf_RepairQueueEnabled", c.repairQueueEnabled ~= false)
    c.repairPerTick = bnp_number("NavPerf_RepairPerTick", c.repairPerTick or 2, 0, 20)
    c.maxRepairQueue = bnp_number("NavPerf_MaxRepairQueue", c.maxRepairQueue or 64, 4, 500)
    c.repairCooldownMs = bnp_number("NavPerf_RepairCooldownMs", c.repairCooldownMs or 1250, 100, 30000)
    c.repairHoldMs = bnp_number("NavPerf_RepairHoldMs", c.repairHoldMs or 2200, 250, 30000)
    c.badCellCooldownMs = bnp_number("NavPerf_BadCellCooldownMs", c.badCellCooldownMs or 90000, 1000, 600000)
    c.badCellMaxRecords = bnp_number("NavPerf_BadCellMaxRecords", c.badCellMaxRecords or 360, 16, 5000)
    c.badCellPenalty = bnp_number("NavPerf_BadCellPenalty", c.badCellPenalty or 7.5, 0, 100)
    c.badTargetPenalty = bnp_number("NavPerf_BadTargetPenalty", c.badTargetPenalty or 12.0, 0, 150)
    c.crowdPenalty = bnp_number("NavPerf_CrowdPenalty", c.crowdPenalty or 2.2, 0, 50)
    c.crowdRadius = bnp_number("NavPerf_CrowdRadius", c.crowdRadius or 1, 0, 4)
    c.densityCacheMs = bnp_number("NavPerf_DensityCacheMs", c.densityCacheMs or 220, 0, 5000)
    c.densityHighCost = bnp_number("NavPerf_DensityHighCost", c.densityHighCost or 8.0, 0, 200)
    c.densityCriticalCost = bnp_number("NavPerf_DensityCriticalCost", c.densityCriticalCost or 16.0, 0, 400)
    c.portalGuardEnabled = bnp_bool("NavPerf_PortalGuardEnabled", c.portalGuardEnabled ~= false)
    c.portalHoldMs = bnp_number("NavPerf_PortalHoldMs", c.portalHoldMs or 1100, 100, 10000)
    c.portalPenalty = bnp_number("NavPerf_PortalPenalty", c.portalPenalty or 6.0, 0, 80)
    c.portalQueueEnabled = bnp_bool("NavPerf_PortalQueueEnabled", c.portalQueueEnabled ~= false)
    c.portalQueueHoldMs = bnp_number("NavPerf_PortalQueueHoldMs", c.portalQueueHoldMs or 8500, 500, 30000)
    c.portalQueueWaitMs = bnp_number("NavPerf_PortalQueueWaitMs", c.portalQueueWaitMs or 650, 100, 5000)
    c.portalQueueMaxWaitMs = bnp_number("NavPerf_PortalQueueMaxWaitMs", c.portalQueueMaxWaitMs or 6500, 1000, 60000)
    c.portalQueueMaxPerPortal = bnp_number("NavPerf_PortalQueueMaxPerPortal", c.portalQueueMaxPerPortal or 6, 1, 30)
    c.portalQueueStaleMs = bnp_number("NavPerf_PortalQueueStaleMs", c.portalQueueStaleMs or 12000, 1000, 60000)
    c.progressReward = bnp_number("NavPerf_ProgressReward", c.progressReward or 1.2, 0, 20)
    c.debug = bnp_bool("NavPerf_Debug", c.debug == true)
end

local function bnp_now()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then return math.floor(getGameTime():getWorldAgeHours() * 3600000) end
    return 0
end

local function bnp_stat(name, amount)
    NPCNavigationPerformanceBridge.Stats = NPCNavigationPerformanceBridge.Stats or {}
    name = tostring(name or "unknown")
    NPCNavigationPerformanceBridge.Stats[name] = (tonumber(NPCNavigationPerformanceBridge.Stats[name]) or 0) + (tonumber(amount) or 1)
    if NPCPerformanceTelemetryBridge and NPCPerformanceTelemetryBridge.Record then
        pcall(function() NPCPerformanceTelemetryBridge.Record("nav." .. name, amount or 1) end)
    end
end

local function bnp_key(x, y, z)
    return tostring(math.floor(tonumber(x) or 0)) .. ":" .. tostring(math.floor(tonumber(y) or 0)) .. ":" .. tostring(math.floor(tonumber(z) or 0))
end

local function bnp_dist2(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return dx * dx + dy * dy
end

local function bnp_getBrain(zombie)
    if not zombie or not NPCBrainData or not NPCBrainData.Get then return nil end
    local ok, brain = pcall(function() return NPCBrainData.Get(zombie) end)
    if ok then return brain end
    return nil
end

local function bnp_id(zombie, brain)
    if brain then
        if brain.uid then return "uid:" .. tostring(brain.uid) end
        if brain.id then return "brain:" .. tostring(brain.id) end
    end
    if zombie and NPCUtils and NPCUtils.GetZombieID then
        local ok, zid = pcall(function() return NPCUtils.GetZombieID(zombie) end)
        if ok and zid then return "z:" .. tostring(zid) end
    end
    return tostring(zombie)
end

local function bnp_tableCount(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

local function bnp_cleanBadCells(now)
    now = now or bnp_now()
    local bad = NPCNavigationPerformanceBridge.BadCells
    for key, entry in pairs(bad) do
        if not entry or not entry.untilMs or now > entry.untilMs then
            bad[key] = nil
        end
    end

    local maxRecords = tonumber(NPCNavigationPerformanceBridge.Config.badCellMaxRecords) or 360
    local count = bnp_tableCount(bad)
    if count <= maxRecords then return end

    local oldestKey = nil
    local oldest = math.huge
    for key, entry in pairs(bad) do
        local t = tonumber(entry.untilMs) or 0
        if t < oldest then
            oldest = t
            oldestKey = key
        end
    end
    if oldestKey then bad[oldestKey] = nil end
end

function NPCNavigationPerformanceBridge.MarkBadCell(x, y, z, reason, weight)
    if not NPCNavigationPerformanceBridge.Config.enabled then return end
    if not x or not y then return end

    local now = bnp_now()
    bnp_cleanBadCells(now)

    local key = bnp_key(x, y, z or 0)
    local entry = NPCNavigationPerformanceBridge.BadCells[key] or {x=math.floor(x), y=math.floor(y), z=math.floor(z or 0), count=0}
    entry.count = (entry.count or 0) + 1
    entry.reason = reason or "bad_path"
    entry.weight = math.max(1, tonumber(weight) or 1)
    entry.untilMs = now + (tonumber(NPCNavigationPerformanceBridge.Config.badCellCooldownMs) or 90000)
    NPCNavigationPerformanceBridge.BadCells[key] = entry
    NPCNavigationPerformanceBridge.Stats.badCells = (NPCNavigationPerformanceBridge.Stats.badCells or 0) + 1
end

function NPCNavigationPerformanceBridge.IsBadCell(x, y, z)
    local key = bnp_key(x, y, z or 0)
    local entry = NPCNavigationPerformanceBridge.BadCells[key]
    if not entry then return false end
    if bnp_now() > (entry.untilMs or 0) then
        NPCNavigationPerformanceBridge.BadCells[key] = nil
        return false
    end
    return true
end

local function bnp_badCellCost(x, y, z)
    local now = bnp_now()
    local key = bnp_key(x, y, z or 0)
    local entry = NPCNavigationPerformanceBridge.BadCells[key]
    if not entry then return 0 end
    if now > (entry.untilMs or 0) then
        NPCNavigationPerformanceBridge.BadCells[key] = nil
        return 0
    end
    return (NPCNavigationPerformanceBridge.Config.badCellPenalty or 7.5) * math.min(6, entry.count or 1) * (entry.weight or 1)
end

local function bnp_isPortalObject(object)
    if not object then return false end
    if instanceof and instanceof(object, "IsoDoor") then return true end
    if instanceof and instanceof(object, "IsoWindow") then return true end
    if instanceof and instanceof(object, "IsoThumpable") then
        local ok, isDoor = pcall(function() return object:isDoor() == true end)
        if ok and isDoor then return true end
        ok, isDoor = pcall(function() return object:isHoppable() == true end)
        if ok and isDoor then return true end
    end
    return false
end

function NPCNavigationPerformanceBridge.IsPortalObject(object)
    return bnp_isPortalObject(object)
end

local function bnp_portalKeyForObject(object)
    if not object then return nil end
    local square = nil
    local ok = pcall(function() square = object:getSquare() end)
    if not ok or not square then return nil end

    local specialIndex = nil
    if instanceof and instanceof(object, "IsoDoor") and IsoDoor then
        local okDouble, doubleIndex = pcall(function()
            if IsoDoor.getDoubleDoorIndex then return IsoDoor.getDoubleDoorIndex(object) end
            return -1
        end)
        if okDouble and tonumber(doubleIndex) and tonumber(doubleIndex) >= 0 then
            specialIndex = "double:" .. tostring(doubleIndex)
        end

        if not specialIndex then
            local okGarage, garageIndex = pcall(function()
                if IsoDoor.getGarageDoorIndex then return IsoDoor.getGarageDoorIndex(object) end
                return -1
            end)
            if okGarage and tonumber(garageIndex) and tonumber(garageIndex) >= 0 then
                specialIndex = "garage:" .. tostring(garageIndex)
            end
        end
    end

    if specialIndex then
        return bnp_key(square:getX(), square:getY(), square:getZ()) .. ":" .. specialIndex
    end

    local idx = -1
    pcall(function() idx = object:getObjectIndex() end)
    return bnp_key(square:getX(), square:getY(), square:getZ()) .. ":" .. tostring(idx)
end

function NPCNavigationPerformanceBridge.GetPortalKey(object)
    return bnp_portalKeyForObject(object)
end

local function bnp_portalKeyForSquare(square)
    if not square then return nil end
    local ok, objects = pcall(function() return square:getObjects() end)
    if not ok or not objects then return nil end

    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if bnp_isPortalObject(object) then
            return bnp_portalKeyForObject(object)
        end
    end
    return nil
end

local function bnp_claimPortal(zombie, brain, square)
    if not NPCNavigationPerformanceBridge.Config.portalGuardEnabled then return nil end
    local key = bnp_portalKeyForSquare(square)
    if not key then return nil end

    local now = bnp_now()
    local id = bnp_id(zombie, brain)
    local claims = NPCNavigationPerformanceBridge.PortalClaims
    local claim = claims[key]
    if claim and now > (claim.untilMs or 0) then claim = nil end

    if not claim or claim.id == id then
        claims[key] = {id=id, untilMs=now + (NPCNavigationPerformanceBridge.Config.portalHoldMs or 1100)}
        return key
    end
    return key, claim
end

local function bnp_compactPortalQueue(queue)
    if not queue or type(queue.queue) ~= "table" then return end
    local old = queue.queue
    local new = {}
    for i = 1, #old do
        local entry = old[i]
        if entry and entry.id then new[#new + 1] = entry end
    end
    queue.queue = new
end

local function bnp_removeQueuedPortalId(queue, id)
    if not queue or not queue.queue or not id then return end
    local removed = false
    for i = #queue.queue, 1, -1 do
        local entry = queue.queue[i]
        if not entry or entry.id == id then
            queue.queue[i] = false
            removed = true
        end
    end
    if removed then bnp_compactPortalQueue(queue) end
end

local function bnp_portalQueuePosition(queue, id)
    if not queue or not queue.queue then return nil end
    for i = 1, #queue.queue do
        local entry = queue.queue[i]
        if entry and entry.id == id then return i, entry end
    end
    return nil
end

local function bnp_cleanPortalQueues(now)
    now = now or bnp_now()
    local staleMs = tonumber(NPCNavigationPerformanceBridge.Config.portalQueueStaleMs) or 12000

    for key, claim in pairs(NPCNavigationPerformanceBridge.PortalClaims) do
        if not claim or now > (claim.untilMs or 0) then
            NPCNavigationPerformanceBridge.PortalClaims[key] = nil
        end
    end

    for key, queue in pairs(NPCNavigationPerformanceBridge.PortalQueues) do
        if not queue then
            NPCNavigationPerformanceBridge.PortalQueues[key] = nil
        else
            if queue.owner and now > (queue.owner.untilMs or 0) then
                queue.owner = nil
            end

            if queue.queue then
                local removed = false
                for i = #queue.queue, 1, -1 do
                    local entry = queue.queue[i]
                    if not entry or now - (entry.queuedAt or now) > staleMs then
                        queue.queue[i] = false
                        removed = true
                    end
                end
                if removed then bnp_compactPortalQueue(queue) end
            end

            if (not queue.owner) and (not queue.queue or #queue.queue == 0) then
                NPCNavigationPerformanceBridge.PortalQueues[key] = nil
            end
        end
    end
end

function NPCNavigationPerformanceBridge.RequestPortalTurn(zombie, object, purpose)
    if not NPCNavigationPerformanceBridge.Config.enabled then return true, nil, 0 end
    if not NPCNavigationPerformanceBridge.Config.portalQueueEnabled then return true, nil, 0 end
    if not zombie or not bnp_isPortalObject(object) then return true, nil, 0 end

    local key = bnp_portalKeyForObject(object)
    if not key then return true, nil, 0 end

    local now = bnp_now()
    bnp_cleanPortalQueues(now)

    local brain = bnp_getBrain(zombie)
    local id = bnp_id(zombie, brain)
    local queues = NPCNavigationPerformanceBridge.PortalQueues
    local queue = queues[key]
    if not queue then
        queue = {queue={}}
        queues[key] = queue
    end

    local owner = queue.owner
    if owner and now > (owner.untilMs or 0) then
        queue.owner = nil
        owner = nil
    end

    local claim = NPCNavigationPerformanceBridge.PortalClaims[key]
    if claim and now > (claim.untilMs or 0) then
        NPCNavigationPerformanceBridge.PortalClaims[key] = nil
        claim = nil
    end
    if (not owner) and claim and claim.id ~= id then
        owner = {id=claim.id, untilMs=claim.untilMs, purpose="move_claim"}
        queue.owner = owner
    end

    if owner and owner.id ~= id then
        local pos, entry = bnp_portalQueuePosition(queue, id)
        if not entry then
            if #queue.queue < (tonumber(NPCNavigationPerformanceBridge.Config.portalQueueMaxPerPortal) or 6) then
                table.insert(queue.queue, {id=id, queuedAt=now, lastSeenAt=now, purpose=purpose or "portal"})
                pos = #queue.queue
                NPCNavigationPerformanceBridge.Stats.portalsQueued = (NPCNavigationPerformanceBridge.Stats.portalsQueued or 0) + 1
                bnp_stat("portalWait", 1)
            else
                NPCNavigationPerformanceBridge.Stats.portalsSkipped = (NPCNavigationPerformanceBridge.Stats.portalsSkipped or 0) + 1
                bnp_stat("portalDenied", 1)
                pos = #queue.queue + 1
            end
        else
            entry.lastSeenAt = now
            entry.purpose = purpose or entry.purpose
        end

        if brain then
            brain.ai = brain.ai or {}
            brain.ai.navPerf = brain.ai.navPerf or {}
            brain.ai.navPerf.portalWaiting = true
            brain.ai.navPerf.portalKey = key
            brain.ai.navPerf.portalPosition = pos or 1
            brain.ai.navPerf.portalPurpose = purpose or "portal"
            brain.ai.navPerf.portalWaitingAt = now
        end

        return false, key, pos or 1
    end

    queue.owner = {id=id, untilMs=now + (tonumber(NPCNavigationPerformanceBridge.Config.portalQueueHoldMs) or 8500), purpose=purpose or "portal"}
    bnp_removeQueuedPortalId(queue, id)
    NPCNavigationPerformanceBridge.PortalClaims[key] = {id=id, untilMs=now + math.max(tonumber(NPCNavigationPerformanceBridge.Config.portalHoldMs) or 1100, tonumber(NPCNavigationPerformanceBridge.Config.portalQueueHoldMs) or 8500)}
    NPCNavigationPerformanceBridge.Stats.portalsGranted = (NPCNavigationPerformanceBridge.Stats.portalsGranted or 0) + 1
    bnp_stat("portalAllowed", 1)

    if brain then
        brain.ai = brain.ai or {}
        brain.ai.navPerf = brain.ai.navPerf or {}
        brain.ai.navPerf.portalWaiting = false
        brain.ai.navPerf.portalOwner = key
        brain.ai.navPerf.portalPurpose = purpose or "portal"
        brain.ai.navPerf.portalGrantedAt = now
    end

    return true, key, 0
end

function NPCNavigationPerformanceBridge.BuildPortalWaitTask(zombie, object, key, position)
    if not object then return nil end
    local square = nil
    local ok = pcall(function() square = object:getSquare() end)
    if not ok or not square then return nil end

    local waitMs = tonumber(NPCNavigationPerformanceBridge.Config.portalQueueWaitMs) or 650
    if position and position > 1 then
        waitMs = math.min(tonumber(NPCNavigationPerformanceBridge.Config.portalQueueMaxWaitMs) or 6500, waitMs + (position - 1) * 180)
    end

    return {
        action = "FaceLocation",
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
        time = math.max(12, math.floor(waitMs / 16)),
        portalWait = true,
        portalKey = key,
        portalQueuePosition = position or 1
    }
end

function NPCNavigationPerformanceBridge.ReleasePortalKey(zombie, key)
    if not key then return end
    local brain = bnp_getBrain(zombie)
    local id = bnp_id(zombie, brain)

    local queue = NPCNavigationPerformanceBridge.PortalQueues[key]
    if queue then
        if queue.owner and (not zombie or queue.owner.id == id or bnp_now() > (queue.owner.untilMs or 0)) then
            queue.owner = nil
            NPCNavigationPerformanceBridge.Stats.portalsReleased = (NPCNavigationPerformanceBridge.Stats.portalsReleased or 0) + 1
        bnp_stat("portalReleased", 1)
        end
        bnp_removeQueuedPortalId(queue, id)
        if (not queue.owner) and (not queue.queue or #queue.queue == 0) then
            NPCNavigationPerformanceBridge.PortalQueues[key] = nil
        end
    end

    local claim = NPCNavigationPerformanceBridge.PortalClaims[key]
    if not claim or not zombie or claim.id == id or bnp_now() > (claim.untilMs or 0) then
        NPCNavigationPerformanceBridge.PortalClaims[key] = nil
    end

    if brain and brain.ai and brain.ai.navPerf then
        if brain.ai.navPerf.portalOwner == key then brain.ai.navPerf.portalOwner = nil end
        if brain.ai.navPerf.portalKey == key then
            brain.ai.navPerf.portalWaiting = false
            brain.ai.navPerf.portalKey = nil
            brain.ai.navPerf.portalPosition = nil
        end
    end
end

function NPCNavigationPerformanceBridge.OnPortalTaskComplete(zombie, task)
    if task and task.portalKey then
        NPCNavigationPerformanceBridge.ReleasePortalKey(zombie, task.portalKey)
    else
        NPCNavigationPerformanceBridge.ReleasePortal(zombie)
    end
end

function NPCNavigationPerformanceBridge.ReleasePortal(zombie)
    if not zombie then return end
    local brain = bnp_getBrain(zombie)
    local id = bnp_id(zombie, brain)
    local claims = NPCNavigationPerformanceBridge.PortalClaims
    for key, claim in pairs(claims) do
        if not claim or bnp_now() > (claim.untilMs or 0) or claim.id == id then
            claims[key] = nil
        end
    end

    for key, queue in pairs(NPCNavigationPerformanceBridge.PortalQueues) do
        if queue then
            if queue.owner and (queue.owner.id == id or bnp_now() > (queue.owner.untilMs or 0)) then
                queue.owner = nil
            end
            bnp_removeQueuedPortalId(queue, id)
            if (not queue.owner) and (not queue.queue or #queue.queue == 0) then
                NPCNavigationPerformanceBridge.PortalQueues[key] = nil
            end
        end
    end
end

local function bnp_crowdCost(square, mover)
    local radius = tonumber(NPCNavigationPerformanceBridge.Config.crowdRadius) or 1
    local penalty = tonumber(NPCNavigationPerformanceBridge.Config.crowdPenalty) or 0
    if not square or radius < 0 or penalty <= 0 then return 0 end

    local cacheMs = tonumber(NPCNavigationPerformanceBridge.Config.densityCacheMs) or 220
    local now = bnp_now()
    local sx = square:getX()
    local sy = square:getY()
    local sz = square:getZ()
    local key = bnp_key(sx, sy, sz) .. ":" .. tostring(radius)
    if cacheMs > 0 then
        local cached = NPCNavigationPerformanceBridge.DensityCache[key]
        if cached and now - (tonumber(cached.at) or 0) <= cacheMs then
            return tonumber(cached.cost) or 0
        end
    end

    local cell = getCell and getCell() or nil
    if not cell then return 0 end

    local cost = 0
    local count = 0
    for dx = -radius, radius do
        for dy = -radius, radius do
            local sq = cell:getGridSquare(sx + dx, sy + dy, sz)
            if sq then
                local ok, mlist = pcall(function() return sq:getMovingObjects() end)
                if ok and mlist and mlist:size() > 0 then
                    for i = 0, mlist:size() - 1 do
                        local obj = mlist:get(i)
                        if obj and obj ~= mover then
                            if instanceof and (instanceof(obj, "IsoZombie") or instanceof(obj, "IsoPlayer")) then
                                count = count + 1
                                cost = cost + penalty
                            end
                        end
                    end
                end
            end
        end
    end
    if cacheMs > 0 then
        NPCNavigationPerformanceBridge.DensityCache[key] = {at=now, cost=cost, count=count}
    end
    return cost
end

function NPCNavigationPerformanceBridge.GetDensityPressureAt(square)
    if not square then return 0, 0 end
    local cost = bnp_crowdCost(square, nil)
    local high = tonumber(NPCNavigationPerformanceBridge.Config.densityHighCost) or 8.0
    local critical = tonumber(NPCNavigationPerformanceBridge.Config.densityCriticalCost) or 16.0
    if cost >= critical then return 2, cost end
    if cost >= high then return 1, cost end
    return 0, cost
end

local function bnp_portalCost(square, mover, brain)
    if not NPCNavigationPerformanceBridge.Config.portalGuardEnabled then return 0 end
    local key = bnp_portalKeyForSquare(square)
    if not key then return 0 end

    local now = bnp_now()
    local claim = NPCNavigationPerformanceBridge.PortalClaims[key]
    if claim and now > (claim.untilMs or 0) then
        NPCNavigationPerformanceBridge.PortalClaims[key] = nil
        claim = nil
    end

    local id = bnp_id(mover, brain)
    if claim and claim.id ~= id then
        return tonumber(NPCNavigationPerformanceBridge.Config.portalPenalty) or 6.0
    end

    local queue = NPCNavigationPerformanceBridge.PortalQueues[key]
    if queue and queue.owner and bnp_now() <= (queue.owner.untilMs or 0) and queue.owner.id ~= id then
        return tonumber(NPCNavigationPerformanceBridge.Config.portalPenalty) or 6.0
    end

    return 0
end

function NPCNavigationPerformanceBridge.GetSquareCost(zombie, brain, square, targetX, targetY, reason)
    if not NPCNavigationPerformanceBridge.Config.enabled or not square then return 0 end

    local x = square:getX()
    local y = square:getY()
    local z = square:getZ()
    local cost = bnp_badCellCost(x, y, z)
    cost = cost + bnp_crowdCost(square, zombie)
    cost = cost + bnp_portalCost(square, zombie, brain)

    if brain and brain.ai and brain.ai.pathMemory and brain.ai.pathMemory.badTargets then
        local bad = brain.ai.pathMemory.badTargets[bnp_key(x, y, z)]
        if bad and (bad.untilMs or 0) >= bnp_now() then
            cost = cost + (tonumber(NPCNavigationPerformanceBridge.Config.badTargetPenalty) or 12.0)
        end
    end

    if targetX and targetY and brain and brain.ai and brain.ai.navPerf and brain.ai.navPerf.lastProgressX then
        local before = bnp_dist2(brain.ai.navPerf.lastProgressX, brain.ai.navPerf.lastProgressY, targetX, targetY)
        local after = bnp_dist2(x + 0.5, y + 0.5, targetX, targetY)
        if after < before then
            cost = cost - (tonumber(NPCNavigationPerformanceBridge.Config.progressReward) or 1.2)
        end
    end

    return cost
end

function NPCNavigationPerformanceBridge.OnMovePrepare(zombie, task)
    if not NPCNavigationPerformanceBridge.Config.enabled or not zombie or not task then return end

    local brain = bnp_getBrain(zombie)
    if brain then
        brain.ai = brain.ai or {}
        brain.ai.navPerf = brain.ai.navPerf or {}
        brain.ai.navPerf.lastPrepareAt = bnp_now()
        brain.ai.navPerf.lastTarget = {x=task.x, y=task.y, z=task.z or zombie:getZ()}
    end

    if task.x and task.y and NPCMovementStabilityBridge and NPCMovementStabilityBridge.GetSquare then
        local square = NPCMovementStabilityBridge.GetSquare(task.x, task.y, task.z or zombie:getZ())
        local portalKey = bnp_claimPortal(zombie, brain, square)
        if portalKey then task._bnpPortalKey = portalKey end
    end
end

function NPCNavigationPerformanceBridge.OnMoveProgress(zombie, task)
    if not NPCNavigationPerformanceBridge.Config.enabled or not zombie or not task then return end

    local brain = bnp_getBrain(zombie)
    if not brain then return end
    brain.ai = brain.ai or {}
    brain.ai.navPerf = brain.ai.navPerf or {}
    brain.ai.navPerf.lastProgressAt = bnp_now()
    brain.ai.navPerf.lastProgressX = zombie:getX()
    brain.ai.navPerf.lastProgressY = zombie:getY()
    brain.ai.navPerf.delayScore = 0
end

local function bnp_delayScore(zombie, task, reason)
    local now = bnp_now()
    local bms = task and task._bms or {}
    local score = 0
    score = score + ((bms.replans or 0) * 5)
    if bms.spinLoop then score = score + 10 end
    if bms.lastMoveAt then score = score + math.min(30, math.max(0, now - bms.lastMoveAt) / 250) end
    if bms.lastProgressAt then score = score + math.min(40, math.max(0, now - bms.lastProgressAt) / 300) end
    if reason == "path_failed" then score = score + 14 end
    if zombie and task and task.x and task.y then
        score = score + math.min(18, math.sqrt(bnp_dist2(zombie:getX(), zombie:getY(), task.x, task.y)) * 0.16)
    end
    return score
end

local function bnp_compactRepairQueue()
    local queue = NPCNavigationPerformanceBridge.RepairQueue
    if type(queue) ~= "table" then return end
    local new = {}
    for i = 1, #queue do
        local entry = queue[i]
        if entry and entry.id then new[#new + 1] = entry end
    end
    NPCNavigationPerformanceBridge.RepairQueue = new
end

local function bnp_queueIndex(id)
    local queue = NPCNavigationPerformanceBridge.RepairQueue
    for i = 1, #queue do
        local entry = queue[i]
        if entry and entry.id == id then return i end
    end
    return nil
end

local function bnp_dropLowestIfNeeded(newScore)
    local queue = NPCNavigationPerformanceBridge.RepairQueue
    local maxQueue = tonumber(NPCNavigationPerformanceBridge.Config.maxRepairQueue) or 64
    if #queue < maxQueue then return true end

    local lowestIndex = nil
    local lowestScore = math.huge
    for i = 1, #queue do
        local entry = queue[i]
        local score = entry and tonumber(entry.score) or -math.huge
        if score < lowestScore then
            lowestScore = score
            lowestIndex = i
        end
    end

    if lowestIndex and lowestScore < (tonumber(newScore) or 0) then
        local old = queue[lowestIndex]
        queue[lowestIndex] = false
        if old then NPCNavigationPerformanceBridge.RepairIds[old.id] = nil end
        bnp_compactRepairQueue()
        NPCNavigationPerformanceBridge.Stats.dropped = (NPCNavigationPerformanceBridge.Stats.dropped or 0) + 1
        bnp_stat("repairDropped", 1)
        return true
    end
    return false
end

function NPCNavigationPerformanceBridge.RequestRepair(zombie, task, reason)
    if not NPCNavigationPerformanceBridge.Config.enabled or not NPCNavigationPerformanceBridge.Config.repairQueueEnabled then return false end
    if not zombie or not task then return false end

    task._bms = task._bms or {}
    local now = bnp_now()
    if task._bms.waitingRepair and now < (task._bms.repairQueuedUntil or 0) then
        return true
    end
    if task._bms.lastRepairQueuedAt and now - task._bms.lastRepairQueuedAt < (NPCNavigationPerformanceBridge.Config.repairCooldownMs or 1250) then
        task._bms.waitingRepair = true
        task._bms.repairQueuedUntil = now + (NPCNavigationPerformanceBridge.Config.repairHoldMs or 2200)
        return true
    end

    local brain = bnp_getBrain(zombie)
    local id = bnp_id(zombie, brain)
    local score = bnp_delayScore(zombie, task, reason)

    local existingIndex = bnp_queueIndex(id)
    if existingIndex then
        local existing = NPCNavigationPerformanceBridge.RepairQueue[existingIndex]
        if existing then
            existing.zombie = zombie
            existing.task = task
            existing.reason = reason or existing.reason
            existing.score = math.max(existing.score or 0, score)
            existing.queuedAt = now
        end
        task._bms.waitingRepair = true
        task._bms.repairQueuedUntil = now + (NPCNavigationPerformanceBridge.Config.repairHoldMs or 2200)
        return true
    end

    if not bnp_dropLowestIfNeeded(score) then
        return false
    end

    local entry = {id=id, zombie=zombie, task=task, reason=reason or "movement_stuck", score=score, queuedAt=now}
    table.insert(NPCNavigationPerformanceBridge.RepairQueue, entry)
    NPCNavigationPerformanceBridge.RepairIds[id] = true
    NPCNavigationPerformanceBridge.Stats.queued = (NPCNavigationPerformanceBridge.Stats.queued or 0) + 1
    bnp_stat("repairQueued", 1)

    task._bms.lastRepairQueuedAt = now
    task._bms.waitingRepair = true
    task._bms.repairQueuedUntil = now + (NPCNavigationPerformanceBridge.Config.repairHoldMs or 2200)

    if brain then
        brain.ai = brain.ai or {}
        brain.ai.navPerf = brain.ai.navPerf or {}
        brain.ai.navPerf.delayScore = score
        brain.ai.navPerf.repairQueued = true
        brain.ai.navPerf.repairReason = reason or "movement_stuck"
    end

    return true
end

local function bnp_getCurrentTask(zombie)
    local entity = bnp_entity()
    if not zombie or not entity or not entity.GetTask then return nil end
    local ok, task = pcall(function() return entity.GetTask(zombie) end)
    if ok then return task end
    return nil
end

local function bnp_validEntry(entry)
    if not entry or not entry.zombie or not entry.task then return false end
    local zombie = entry.zombie
    local okDead, dead = pcall(function() return zombie:isDead() end)
    if okDead and dead then return false end
    local task = bnp_getCurrentTask(zombie)
    if not task or task ~= entry.task then return false end
    return true
end

local function bnp_applyRepair(entry)
    if not bnp_validEntry(entry) then return false end
    if not NPCMovementStabilityBridge then return false end

    local zombie = entry.zombie
    local task = entry.task
    local brain = bnp_getBrain(zombie)
    local z = task.z or zombie:getZ()

    NPCNavigationPerformanceBridge.MarkBadCell(math.floor(zombie:getX()), math.floor(zombie:getY()), zombie:getZ(), entry.reason or "repair_source", 1)
    if task.x and task.y then
        NPCNavigationPerformanceBridge.MarkBadCell(task.x, task.y, z, entry.reason or "repair_target", 1.5)
    end

    local recoverySquare = nil
    local ok, ret = pcall(function()
        return NPCMovementStabilityBridge.FindRecoverySquare(zombie, task)
    end)
    if ok then recoverySquare = ret end

    if not recoverySquare and NPCMovementStabilityBridge.FindFreeAround then
        recoverySquare = NPCMovementStabilityBridge.FindFreeAround(zombie:getX(), zombie:getY(), zombie:getZ(), zombie, 5)
    end

    if not recoverySquare then return false end

    task.originalX = task.originalX or task.x
    task.originalY = task.originalY or task.y
    task.originalZ = task.originalZ or task.z
    task.x = recoverySquare:getX()
    task.y = recoverySquare:getY()
    task.z = recoverySquare:getZ()
    task.adjustedTarget = true
    task.recoveryTarget = true
    task.navPerfRepair = true
    task.arriveDist = math.max(task.arriveDist or 0.9, 1.2)
    task.walkType = (task._bms and task._bms.replans and task._bms.replans <= 2) and "Walk" or (task.walkType or "Run")

    if task._bms then
        local now = bnp_now()
        task._bms.waitingRepair = false
        task._bms.repairQueuedUntil = 0
        task._bms.lastMoveAt = now
        task._bms.lastProgressAt = now
        task._bms.lastX = zombie:getX()
        task._bms.lastY = zombie:getY()
        task._bms.spinScore = 0
        task._bms.spinLoop = false
    end

    NPCMovementStabilityBridge.ResetPath(zombie, true)
    NPCMovementStabilityBridge.StartPath(zombie, task, true)
    local entity = bnp_entity()
    if entity and entity.SetMoving then pcall(function() entity.SetMoving(zombie, true) end) end

    if brain then
        brain.ai = brain.ai or {}
        brain.ai.navPerf = brain.ai.navPerf or {}
        brain.ai.navPerf.repairQueued = false
        brain.ai.navPerf.lastRepairAt = bnp_now()
        brain.ai.navPerf.lastRepairReason = entry.reason
        brain.ai.navPerf.lastRepairTarget = {x=task.x, y=task.y, z=task.z}
        brain.state = "RecoverPath"
        brain.reason = "bounded path repair"
    end

    return true
end

function NPCNavigationPerformanceBridge.ProcessRepairQueue()
    if not NPCNavigationPerformanceBridge.Config.enabled or not NPCNavigationPerformanceBridge.Config.repairQueueEnabled then return 0 end

    local queue = NPCNavigationPerformanceBridge.RepairQueue
    if #queue == 0 then return 0 end

    table.sort(queue, function(a, b)
        return (tonumber(a and a.score) or 0) > (tonumber(b and b.score) or 0)
    end)

    local budget = tonumber(NPCNavigationPerformanceBridge.Config.repairPerTick) or 2
    if NPCStreamingRuntimeBridge and NPCStreamingRuntimeBridge.AdjustNavRepairBudget then
        budget = NPCStreamingRuntimeBridge.AdjustNavRepairBudget(budget)
    end
    local processed = 0
    local index = 1
    while index <= #queue and processed < budget do
        local entry = queue[index]
        queue[index] = false
        if entry then NPCNavigationPerformanceBridge.RepairIds[entry.id] = nil end
        index = index + 1
        if entry then processed = processed + 1 end
        if entry and bnp_applyRepair(entry) then
            NPCNavigationPerformanceBridge.Stats.repaired = (NPCNavigationPerformanceBridge.Stats.repaired or 0) + 1
            bnp_stat("repairProcessed", 1)
        elseif entry then
            NPCNavigationPerformanceBridge.Stats.skipped = (NPCNavigationPerformanceBridge.Stats.skipped or 0) + 1
        end
    end
    bnp_compactRepairQueue()
    return processed
end

local function bnp_onTick()
    local now = bnp_now()
    bnp_cleanPortalQueues(now)
    local cacheMs = tonumber(NPCNavigationPerformanceBridge.Config.densityCacheMs) or 220
    if cacheMs > 0 then
        for key, entry in pairs(NPCNavigationPerformanceBridge.DensityCache or {}) do
            if not entry or now - (tonumber(entry.at) or 0) > cacheMs * 6 then
                NPCNavigationPerformanceBridge.DensityCache[key] = nil
            end
        end
    end
    NPCNavigationPerformanceBridge.ProcessRepairQueue()
end

function NPCNavigationPerformanceBridge.InstallTick()
    if NPCNavigationPerformanceBridge.TickInstalled then return end
    if Events and Events.OnTick then
        Events.OnTick.Add(bnp_onTick)
        NPCNavigationPerformanceBridge.TickInstalled = true
    end
end

function NPCNavigationPerformanceBridge.GetDiagnostics(reset)
    local stats = {}
    for k, v in pairs(NPCNavigationPerformanceBridge.Stats or {}) do stats[k] = v end
    local pendingRepair = 0
    if type(NPCNavigationPerformanceBridge.RepairQueue) == "table" then pendingRepair = #NPCNavigationPerformanceBridge.RepairQueue end
    local portalQueues = 0
    if type(NPCNavigationPerformanceBridge.PortalQueues) == "table" then
        for _, _ in pairs(NPCNavigationPerformanceBridge.PortalQueues) do portalQueues = portalQueues + 1 end
    end
    local out = {
        version = NPCNavigationPerformanceBridge.VERSION,
        stats = stats,
        pendingRepair = pendingRepair,
        portalQueues = portalQueues,
        config = NPCNavigationPerformanceBridge.Config
    }
    if reset == true then
        NPCNavigationPerformanceBridge.Stats = {
            queued = 0, repaired = 0, skipped = 0, dropped = 0, badCells = 0,
            portalsQueued = 0, portalsGranted = 0, portalsReleased = 0, portalsSkipped = 0,
            portalAllowed = 0, portalDenied = 0, portalWait = 0, repairQueued = 0, repairProcessed = 0, repairDropped = 0
        }
    end
    return out
end

NPCNavigationPerformanceBridge.ApplySettings()
NPCNavigationPerformanceBridge.InstallTick()
