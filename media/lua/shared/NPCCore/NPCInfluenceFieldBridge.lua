-- NPCInfluenceFieldBridge.lua
-- Neutral shared backend for runtime influence field.

-- NPCInfluenceFieldBridge.lua
-- Runtime-only influence fields for legacy NPC runtime.
--
-- This is the practical game-AI version of an iterative/local approximation idea:
-- instead of recalculating global decisions by scanning every group/base/NPC, the
-- world injects local sources (threat, noise, faction presence, base needs) into a
-- coarse bucket grid. The grid is then decayed and lightly diffused over time in a
-- small per-tick budget. AI and virtual groups can query the cached field cheaply.
--
-- Runtime data is intentionally NOT saved into ModData and is NOT replicated to clients.

NPCInfluenceFieldBridge = NPCInfluenceFieldBridge or {}

NPCInfluenceFieldBridge.Config = NPCInfluenceFieldBridge.Config or {
    enabled = true,
    bucketSize = 50,
    maxCells = 2200,
    updateBucketsPerTick = 18,
    decayPerUpdate = 0.035,
    diffusionRate = 0.08,
    sourceRadius = 140,
    virtualGroups = true,
    baseZones = true,
    npcUtility = true,
    debugLog = false
}

NPCInfluenceFieldBridge.Cells = NPCInfluenceFieldBridge.Cells or {}
NPCInfluenceFieldBridge.ActiveKeys = NPCInfluenceFieldBridge.ActiveKeys or {}
NPCInfluenceFieldBridge.ActiveSet = NPCInfluenceFieldBridge.ActiveSet or {}
NPCInfluenceFieldBridge.Head = NPCInfluenceFieldBridge.Head or 1
NPCInfluenceFieldBridge.Tick = NPCInfluenceFieldBridge.Tick or 0
NPCInfluenceFieldBridge.CellCount = NPCInfluenceFieldBridge.CellCount or 0
NPCInfluenceFieldBridge.LastSourceWorldHour = NPCInfluenceFieldBridge.LastSourceWorldHour or 0

local BIF_FIELDS = {"threat", "noise", "baseNeed", "loot", "red", "green", "blue", "black", "zombie"}

local function bif_log(msg)
    if NPCInfluenceFieldBridge.Config and NPCInfluenceFieldBridge.Config.debugLog then
        print("[NPCInfluenceFieldBridge] " .. tostring(msg))
    end
end

local function bif_clamp(value, minValue, maxValue)
    value = tonumber(value) or 0
    if minValue ~= nil and value < minValue then return minValue end
    if maxValue ~= nil and value > maxValue then return maxValue end
    return value
end

local function bif_settingNumber(name, defaultValue, minValue, maxValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        return NPCLegacySettingsBridge.GetNumber(name, defaultValue, minValue, maxValue)
    end
    return bif_clamp(defaultValue, minValue, maxValue)
end

local function bif_settingBool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        return NPCLegacySettingsBridge.GetBool(name, defaultValue == true)
    end
    return defaultValue == true
end

local function bif_nowHours()
    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then
            local ok, v = pcall(function() return gt:getWorldAgeHours() end)
            if ok and v then return tonumber(v) or 0 end
        end
    end
    if getTimestamp then
        local ok, v = pcall(function() return getTimestamp() end)
        if ok and v then return (tonumber(v) or 0) / 3600 end
    end
    return os.time() / 3600
end

local function bif_dist(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return math.sqrt(dx * dx + dy * dy)
end

local function bif_normalSide(side)
    side = tostring(side or "")
    if side == "red" or side == "green" or side == "blue" or side == "black" then return side end
    return nil
end

local function bif_groupSide(group)
    if not group then return nil end
    if NPCStrategicAIBridge and NPCStrategicAIBridge.GetGroupSide then
        local ok, side = pcall(function() return NPCStrategicAIBridge.GetGroupSide(group) end)
        if ok and side then return bif_normalSide(side) end
    end
    return bif_normalSide(group.patrolColor or group.faction or group.side or (group.hostile and "red" or "green"))
end

local function bif_bucketSize()
    local size = tonumber(NPCInfluenceFieldBridge.Config.bucketSize) or 50
    if size < 10 then size = 10 end
    return size
end

function NPCInfluenceFieldBridge.ApplySettings()
    local c = NPCInfluenceFieldBridge.Config
    c.enabled = bif_settingBool("Influence_Enabled", c.enabled ~= false)
    c.bucketSize = bif_settingNumber("Influence_BucketSize", c.bucketSize or 50, 10, 200)
    c.maxCells = bif_settingNumber("Influence_MaxCells", c.maxCells or 2200, 128, 20000)
    c.updateBucketsPerTick = bif_settingNumber("Influence_UpdateBucketsPerTick", c.updateBucketsPerTick or 18, 0, 500)
    c.decayPerUpdate = bif_settingNumber("Influence_DecayPerUpdate", c.decayPerUpdate or 0.035, 0.0, 1.0)
    c.diffusionRate = bif_settingNumber("Influence_DiffusionRate", c.diffusionRate or 0.08, 0.0, 1.0)
    c.sourceRadius = bif_settingNumber("Influence_SourceRadius", c.sourceRadius or 140, 0, 600)
    c.virtualGroups = bif_settingBool("Influence_UseForVirtualGroups", c.virtualGroups ~= false)
    c.baseZones = bif_settingBool("Influence_UseForBaseZones", c.baseZones ~= false)
    c.npcUtility = bif_settingBool("Influence_UseForNPCUtility", c.npcUtility ~= false)
    c.debugLog = bif_settingBool("Influence_DebugLog", c.debugLog == true)
end

function NPCInfluenceFieldBridge.IsEnabled()
    return NPCInfluenceFieldBridge.Config and NPCInfluenceFieldBridge.Config.enabled == true
end

function NPCInfluenceFieldBridge.CellXY(x, y)
    local size = bif_bucketSize()
    return math.floor((tonumber(x) or 0) / size), math.floor((tonumber(y) or 0) / size)
end

function NPCInfluenceFieldBridge.Key(bx, by)
    return tostring(math.floor(tonumber(bx) or 0)) .. ":" .. tostring(math.floor(tonumber(by) or 0))
end

function NPCInfluenceFieldBridge.Center(bx, by)
    local size = bif_bucketSize()
    return (tonumber(bx) or 0) * size + math.floor(size / 2), (tonumber(by) or 0) * size + math.floor(size / 2)
end

local function bif_addActive(key)
    if not key or NPCInfluenceFieldBridge.ActiveSet[key] then return end
    NPCInfluenceFieldBridge.ActiveSet[key] = true
    table.insert(NPCInfluenceFieldBridge.ActiveKeys, key)
end

local function bif_cellMagnitude(cell)
    if not cell then return 0 end
    local sum = 0
    for _, field in ipairs(BIF_FIELDS) do
        local v = tonumber(cell[field]) or 0
        if v < 0 then v = -v end
        sum = sum + v
    end
    return sum
end

function NPCInfluenceFieldBridge.GetCellByBucket(bx, by, create)
    local key = NPCInfluenceFieldBridge.Key(bx, by)
    local cell = NPCInfluenceFieldBridge.Cells[key]
    if not cell and create then
        local maxCells = tonumber(NPCInfluenceFieldBridge.Config.maxCells) or 2200
        if NPCInfluenceFieldBridge.CellCount >= maxCells then
            NPCInfluenceFieldBridge.Prune(math.floor(maxCells * 0.85))
        end
        cell = {bx=bx, by=by, updatedAt=bif_nowHours()}
        NPCInfluenceFieldBridge.Cells[key] = cell
        NPCInfluenceFieldBridge.CellCount = (NPCInfluenceFieldBridge.CellCount or 0) + 1
    end
    if cell then bif_addActive(key) end
    return cell, key
end

function NPCInfluenceFieldBridge.GetCell(x, y, create)
    local bx, by = NPCInfluenceFieldBridge.CellXY(x, y)
    return NPCInfluenceFieldBridge.GetCellByBucket(bx, by, create)
end

function NPCInfluenceFieldBridge.Inject(field, x, y, value, radius)
    if not NPCInfluenceFieldBridge.IsEnabled() then return false end
    field = tostring(field or "")
    if field == "" then return false end
    value = tonumber(value) or 0
    if value == 0 then return false end

    radius = tonumber(radius) or NPCInfluenceFieldBridge.Config.sourceRadius or 140
    local size = bif_bucketSize()
    local bx, by = NPCInfluenceFieldBridge.CellXY(x, y)
    local steps = math.max(0, math.ceil(radius / size))
    local changed = false

    for oy=-steps, steps do
        for ox=-steps, steps do
            local cx, cy = NPCInfluenceFieldBridge.Center(bx + ox, by + oy)
            local d = bif_dist(x, y, cx, cy)
            if d <= radius + size then
                local weight = 1.0
                if radius > 0 then
                    weight = 1.0 - (d / (radius + size))
                    if weight < 0 then weight = 0 end
                end
                if weight > 0 then
                    local cell = NPCInfluenceFieldBridge.GetCellByBucket(bx + ox, by + oy, true)
                    if cell then
                        local old = tonumber(cell[field]) or 0
                        cell[field] = bif_clamp(old + value * weight, -1000, 1000)
                        cell.updatedAt = bif_nowHours()
                        changed = true
                    end
                end
            end
        end
    end

    return changed
end

function NPCInfluenceFieldBridge.InjectFaction(side, x, y, count, radius)
    side = bif_normalSide(side)
    if not side then return false end
    count = tonumber(count) or 1
    if count < 1 then count = 1 end
    return NPCInfluenceFieldBridge.Inject(side, x, y, math.min(100, 1.5 + count * 0.35), radius)
end

function NPCInfluenceFieldBridge.InjectThreat(x, y, value, radius)
    return NPCInfluenceFieldBridge.Inject("threat", x, y, value or 12, radius)
end

function NPCInfluenceFieldBridge.InjectNoise(x, y, value, radius)
    return NPCInfluenceFieldBridge.Inject("noise", x, y, value or 8, radius)
end

function NPCInfluenceFieldBridge.InjectBaseNeed(x, y, value, radius)
    return NPCInfluenceFieldBridge.Inject("baseNeed", x, y, value or 8, radius)
end

function NPCInfluenceFieldBridge.GetField(x, y, field)
    if not NPCInfluenceFieldBridge.IsEnabled() then return 0 end
    local cell = NPCInfluenceFieldBridge.GetCell(x, y, false)
    if not cell then return 0 end
    return tonumber(cell[tostring(field or "")]) or 0
end

function NPCInfluenceFieldBridge.GetScoreAtBucket(bx, by, weights)
    local cell = NPCInfluenceFieldBridge.GetCellByBucket(bx, by, false)
    if not cell or type(weights) ~= "table" then return 0 end
    local score = 0
    for field, weight in pairs(weights) do
        score = score + (tonumber(cell[field]) or 0) * (tonumber(weight) or 0)
    end
    return score
end

function NPCInfluenceFieldBridge.GetScore(x, y, weights)
    local bx, by = NPCInfluenceFieldBridge.CellXY(x, y)
    return NPCInfluenceFieldBridge.GetScoreAtBucket(bx, by, weights)
end

function NPCInfluenceFieldBridge.FindBestNeighbor(x, y, weights, radiusBuckets)
    if not NPCInfluenceFieldBridge.IsEnabled() then return nil end
    radiusBuckets = tonumber(radiusBuckets) or 1
    if radiusBuckets < 1 then radiusBuckets = 1 end
    if radiusBuckets > 6 then radiusBuckets = 6 end

    local bx, by = NPCInfluenceFieldBridge.CellXY(x, y)
    local best = nil
    local bestScore = NPCInfluenceFieldBridge.GetScoreAtBucket(bx, by, weights)

    for oy=-radiusBuckets, radiusBuckets do
        for ox=-radiusBuckets, radiusBuckets do
            if ox ~= 0 or oy ~= 0 then
                local score = NPCInfluenceFieldBridge.GetScoreAtBucket(bx + ox, by + oy, weights)
                if score > bestScore then
                    local cx, cy = NPCInfluenceFieldBridge.Center(bx + ox, by + oy)
                    bestScore = score
                    best = {x=cx, y=cy, z=0, score=score, bx=bx + ox, by=by + oy}
                end
            end
        end
    end

    return best
end

local function bif_weightsForGroup(group)
    local side = bif_groupSide(group)
    if side == "red" then
        return {green=2.0, black=1.8, blue=0.25, red=-0.7, noise=0.35, threat=0.45, baseNeed=0.55, zombie=-0.35}
    elseif side == "green" then
        return {red=2.0, black=1.8, blue=0.25, green=-0.7, noise=0.35, threat=0.45, baseNeed=0.55, zombie=-0.35}
    elseif side == "black" then
        return {red=1.4, green=1.4, blue=1.1, black=0.35, noise=0.70, threat=0.65, baseNeed=0.25, zombie=-0.25}
    elseif side == "blue" then
        return {baseNeed=1.0, loot=0.8, noise=-0.25, threat=-0.55, zombie=-0.45, red=-0.25, green=-0.25, black=-0.75}
    end
    return {baseNeed=0.7, loot=0.5, noise=0.25, threat=0.25, zombie=-0.25}
end

function NPCInfluenceFieldBridge.SuggestVirtualTarget(group)
    if not NPCInfluenceFieldBridge.IsEnabled() or not NPCInfluenceFieldBridge.Config.virtualGroups then return nil end
    if not group or not group.x or not group.y or group.activated or group.inBattle or group.economyMissionId then return nil end
    if group.targetClass == "base_capture" and group.targetBaseId then return nil end

    local weights = bif_weightsForGroup(group)
    local best = NPCInfluenceFieldBridge.FindBestNeighbor(group.x, group.y, weights, 3)
    if best and best.score and best.score >= 2.0 then
        best.spawnClass = "influence"
        best.influenceScore = best.score
        return best
    end
    return nil
end

function NPCInfluenceFieldBridge.GetWorldPointBonus(x, y, group)
    if not NPCInfluenceFieldBridge.IsEnabled() or not NPCInfluenceFieldBridge.Config.virtualGroups then return 0 end
    local weights = bif_weightsForGroup(group)
    local score = NPCInfluenceFieldBridge.GetScore(x, y, weights)
    if score > 80 then score = 80 end
    if score < -80 then score = -80 end
    return score
end

function NPCInfluenceFieldBridge.GetLocalStimulus(x, y)
    if not NPCInfluenceFieldBridge.IsEnabled() or not NPCInfluenceFieldBridge.Config.npcUtility then return nil end
    local cell = NPCInfluenceFieldBridge.GetCell(x, y, false)
    if not cell then return nil end
    local threat = tonumber(cell.threat) or 0
    local noise = tonumber(cell.noise) or 0
    local zombie = tonumber(cell.zombie) or 0
    local score = threat + noise * 0.75 + zombie * 0.4
    if score < 4.0 then return nil end
    local cx, cy = NPCInfluenceFieldBridge.Center(cell.bx or 0, cell.by or 0)
    return {x=cx, y=cy, z=0, score=score, threat=threat, noise=noise, zombie=zombie, memoryOnly=true, canSee=false, heard=noise > threat, kind="influence"}
end

function NPCInfluenceFieldBridge.UpdateFromWorld(gmd)
    if not NPCInfluenceFieldBridge.IsEnabled() then return false end
    if not gmd then return false end
    local radius = tonumber(NPCInfluenceFieldBridge.Config.sourceRadius) or 140
    local changed = false

    for _, group in pairs(gmd.VirtualGroups or {}) do
        if group and not group.activated and group.x and group.y and (tonumber(group.count) or 0) > 0 then
            local side = bif_groupSide(group)
            if side then
                changed = NPCInfluenceFieldBridge.InjectFaction(side, group.x, group.y, tonumber(group.count) or 1, radius) or changed
            end
            if group.inBattle then
                changed = NPCInfluenceFieldBridge.InjectThreat(group.x, group.y, 16 + ((tonumber(group.count) or 1) * 0.5), radius * 1.25) or changed
                changed = NPCInfluenceFieldBridge.InjectNoise(group.x, group.y, 12, radius * 1.6) or changed
            elseif group.roadPatrol then
                changed = NPCInfluenceFieldBridge.InjectNoise(group.x, group.y, 1.2, radius * 0.75) or changed
            end
        end
    end

    return changed
end

function NPCInfluenceFieldBridge.UpdateFromBases(gmd)
    if not NPCInfluenceFieldBridge.IsEnabled() or not NPCInfluenceFieldBridge.Config.baseZones then return false end
    if not gmd then return false end
    local changed = false
    local radius = math.max(80, tonumber(NPCInfluenceFieldBridge.Config.sourceRadius) or 140)

    for _, base in pairs(gmd.BaseCamps or {}) do
        if base and base.x and base.y then
            local readiness = tonumber(base.operationalReadiness or base.garrisonReadiness or base.defenseReadiness or 100) or 100
            local lowZones = tonumber(base.lowZones) or 0
            local overloaded = tonumber(base.overloadedZones) or 0
            local contested = base.status == "contested" or base.status == "capturing" or base.status == "decapturing"
            local need = math.max(0, 100 - readiness) * 0.18 + lowZones * 2.5 + overloaded * 1.5
            if contested then need = need + 12 end
            if need > 0.5 then
                changed = NPCInfluenceFieldBridge.InjectBaseNeed(base.x, base.y, need, radius) or changed
            end
            if base.owner == "red" or base.owner == "green" or base.owner == "blue" or base.owner == "black" then
                changed = NPCInfluenceFieldBridge.InjectFaction(base.owner, base.x, base.y, 4, radius * 0.8) or changed
            end
            if contested then
                changed = NPCInfluenceFieldBridge.InjectThreat(base.x, base.y, 10, radius) or changed
                changed = NPCInfluenceFieldBridge.InjectNoise(base.x, base.y, 7, radius) or changed
            end
        end
    end

    return changed
end

function NPCInfluenceFieldBridge.InjectBrainThreat(bandit, brain, threat)
    if not NPCInfluenceFieldBridge.IsEnabled() or not NPCInfluenceFieldBridge.Config.npcUtility then return false end
    if not bandit or not brain or not threat or not threat.x or not threat.y then return false end
    local now = bif_nowHours()
    if brain.influenceLastInject and now - (tonumber(brain.influenceLastInject) or 0) < 0.025 then return false end
    brain.influenceLastInject = now
    local changed = NPCInfluenceFieldBridge.InjectThreat(threat.x, threat.y, 4.5, 90)
    if threat.heard or threat.memoryOnly then
        changed = NPCInfluenceFieldBridge.InjectNoise(threat.x, threat.y, 3.0, 110) or changed
    end
    return changed
end

function NPCInfluenceFieldBridge.ProcessBucket(key)
    local cell = NPCInfluenceFieldBridge.Cells[key]
    if not cell then
        NPCInfluenceFieldBridge.ActiveSet[key] = nil
        return false
    end

    local decay = bif_clamp(NPCInfluenceFieldBridge.Config.decayPerUpdate or 0.035, 0, 1)
    local diffusion = bif_clamp(NPCInfluenceFieldBridge.Config.diffusionRate or 0.08, 0, 1)
    local bx = tonumber(cell.bx) or 0
    local by = tonumber(cell.by) or 0
    local changed = false

    for _, field in ipairs(BIF_FIELDS) do
        local v = tonumber(cell[field]) or 0
        if v ~= 0 then
            if diffusion > 0 then
                local total = 0
                local n = 0
                local n1 = NPCInfluenceFieldBridge.GetCellByBucket(bx + 1, by, false)
                local n2 = NPCInfluenceFieldBridge.GetCellByBucket(bx - 1, by, false)
                local n3 = NPCInfluenceFieldBridge.GetCellByBucket(bx, by + 1, false)
                local n4 = NPCInfluenceFieldBridge.GetCellByBucket(bx, by - 1, false)
                if n1 then total = total + (tonumber(n1[field]) or 0); n = n + 1 end
                if n2 then total = total + (tonumber(n2[field]) or 0); n = n + 1 end
                if n3 then total = total + (tonumber(n3[field]) or 0); n = n + 1 end
                if n4 then total = total + (tonumber(n4[field]) or 0); n = n + 1 end
                if n > 0 then
                    v = v + (((total / n) - v) * diffusion)
                end
            end
            v = v * (1.0 - decay)
            if v < 0.05 and v > -0.05 then v = nil end
            cell[field] = v
            changed = true
        end
    end

    if bif_cellMagnitude(cell) <= 0.05 then
        NPCInfluenceFieldBridge.Cells[key] = nil
        NPCInfluenceFieldBridge.ActiveSet[key] = nil
        NPCInfluenceFieldBridge.CellCount = math.max(0, (NPCInfluenceFieldBridge.CellCount or 1) - 1)
        return true
    end

    cell.updatedAt = bif_nowHours()
    return changed
end

function NPCInfluenceFieldBridge.Prune(targetCount)
    targetCount = tonumber(targetCount) or math.floor((tonumber(NPCInfluenceFieldBridge.Config.maxCells) or 2200) * 0.85)
    if (NPCInfluenceFieldBridge.CellCount or 0) <= targetCount then return 0 end

    local list = {}
    for key, cell in pairs(NPCInfluenceFieldBridge.Cells) do
        list[#list + 1] = {key=key, score=bif_cellMagnitude(cell)}
    end
    table.sort(list, function(a, b) return (a.score or 0) < (b.score or 0) end)

    local removed = 0
    for i=1, #list do
        if (NPCInfluenceFieldBridge.CellCount or 0) <= targetCount then break end
        local key = list[i].key
        if NPCInfluenceFieldBridge.Cells[key] then
            NPCInfluenceFieldBridge.Cells[key] = nil
            NPCInfluenceFieldBridge.ActiveSet[key] = nil
            NPCInfluenceFieldBridge.CellCount = math.max(0, (NPCInfluenceFieldBridge.CellCount or 1) - 1)
            removed = removed + 1
        end
    end

    -- Rebuild active list compactly after pruning.
    NPCInfluenceFieldBridge.ActiveKeys = {}
    for key, _ in pairs(NPCInfluenceFieldBridge.Cells) do
        NPCInfluenceFieldBridge.ActiveSet[key] = true
        NPCInfluenceFieldBridge.ActiveKeys[#NPCInfluenceFieldBridge.ActiveKeys + 1] = key
    end
    NPCInfluenceFieldBridge.Head = 1
    return removed
end

function NPCInfluenceFieldBridge.ProcessTick()
    if not NPCInfluenceFieldBridge.IsEnabled() then return end
    NPCInfluenceFieldBridge.Tick = (NPCInfluenceFieldBridge.Tick or 0) + 1
    if NPCInfluenceFieldBridge.Tick % 180 == 1 then
        NPCInfluenceFieldBridge.ApplySettings()
    end

    local budget = tonumber(NPCInfluenceFieldBridge.Config.updateBucketsPerTick) or 0
    if budget <= 0 then return end

    local processed = 0
    while processed < budget and #NPCInfluenceFieldBridge.ActiveKeys > 0 do
        local head = tonumber(NPCInfluenceFieldBridge.Head) or 1
        if head > #NPCInfluenceFieldBridge.ActiveKeys then
            NPCInfluenceFieldBridge.Head = 1
            break
        end
        local key = NPCInfluenceFieldBridge.ActiveKeys[head]
        NPCInfluenceFieldBridge.Head = head + 1
        if key and NPCInfluenceFieldBridge.Cells[key] then
            NPCInfluenceFieldBridge.ProcessBucket(key)
            processed = processed + 1
        else
            NPCInfluenceFieldBridge.ActiveSet[key] = nil
        end
    end

    if NPCInfluenceFieldBridge.Head > 96 and NPCInfluenceFieldBridge.Head > (#NPCInfluenceFieldBridge.ActiveKeys / 2) then
        local newKeys = {}
        local newSet = {}
        for key, cell in pairs(NPCInfluenceFieldBridge.Cells) do
            if cell then
                newKeys[#newKeys + 1] = key
                newSet[key] = true
            end
        end
        NPCInfluenceFieldBridge.ActiveKeys = newKeys
        NPCInfluenceFieldBridge.ActiveSet = newSet
        NPCInfluenceFieldBridge.Head = 1
    end
end

function NPCInfluenceFieldBridge.Reset()
    NPCInfluenceFieldBridge.Cells = {}
    NPCInfluenceFieldBridge.ActiveKeys = {}
    NPCInfluenceFieldBridge.ActiveSet = {}
    NPCInfluenceFieldBridge.Head = 1
    NPCInfluenceFieldBridge.CellCount = 0
end

NPCInfluenceFieldBridge.ApplySettings()

if Events and Events.OnTick and not NPCInfluenceFieldBridge._registered then
    NPCInfluenceFieldBridge._registered = true
    Events.OnTick.Add(NPCInfluenceFieldBridge.ProcessTick)
end
