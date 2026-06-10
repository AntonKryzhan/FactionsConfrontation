-- NPCAdaptiveLearningBridge.lua
-- Small persistent contextual-bandit/Q-lite table for behavior scoring.
-- Stages 341-342: bounded server/local ModData learning, no neural network runtime.

NPCAdaptiveLearningBridge = NPCAdaptiveLearningBridge or {}

NPCAdaptiveLearningBridge.VERSION = "2026-05-31-stage349-forest-freeze-learning-governor-1"
NPCAdaptiveLearningBridge.MODDATA_KEY = "NPCAdaptiveLearning"

NPCAdaptiveLearningBridge.Config = NPCAdaptiveLearningBridge.Config or {
    enabled = true,
    persistent = true,
    alpha = 0.12,
    strength = 0.18,
    maxContexts = 1600,
    maxActionsPerContext = 10,
    maxPathEntries = 1600,
    minSamples = 3,
    maxPriorityModifier = 6,
    pruneEveryUpdates = 240,
    decay = 0.995,
    transmitEveryUpdates = 96,
    transmitMinMs = 30000,
    dirtyHardFlush = 320,
    dirtyCounterCap = 640,
    updateMinMs = 900,
    pathRecordMinMs = 1600,
    pathCellSize = 4,
    exportWeightsFile = false,
    exportWeightsFileName = "NPCAdaptiveLearning_weights.json",
    exportWeightsSummaryFileName = "NPCAdaptiveLearning_weights_summary.txt",
    exportEveryUpdates = 512,
    exportMinMs = 300000,
    exportMaxContexts = 400,
    exportMaxPathEntries = 800,
    exportMaxCoverEntries = 400,
    exportMaxWeaponEntries = 300
}

NPCAdaptiveLearningBridge._fallback = NPCAdaptiveLearningBridge._fallback or nil
NPCAdaptiveLearningBridge._updates = NPCAdaptiveLearningBridge._updates or 0
NPCAdaptiveLearningBridge._dirty = NPCAdaptiveLearningBridge._dirty or 0
NPCAdaptiveLearningBridge._lastTransmitMs = NPCAdaptiveLearningBridge._lastTransmitMs or 0
NPCAdaptiveLearningBridge._lastExportMs = NPCAdaptiveLearningBridge._lastExportMs or 0
NPCAdaptiveLearningBridge._exporting = NPCAdaptiveLearningBridge._exporting or false
NPCAdaptiveLearningBridge._lastActionUpdate = NPCAdaptiveLearningBridge._lastActionUpdate or {}
NPCAdaptiveLearningBridge._lastPathRecord = NPCAdaptiveLearningBridge._lastPathRecord or {}
NPCAdaptiveLearningBridge._sanitizedStore = NPCAdaptiveLearningBridge._sanitizedStore or false

local blearn_markDirty
local blearn_sanitizeStore

local function blearn_nowMs()
    if getTimestampMs then
        local ok, value = pcall(function() return getTimestampMs() end)
        if ok and value then return tonumber(value) or 0 end
    end
    if getGameTime then
        local ok, value = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok and value then return math.floor((tonumber(value) or 0) * 3600000) end
    end
    return os.time() * 1000
end

local function blearn_clamp(value, lo, hi)
    value = tonumber(value) or 0
    if lo ~= nil and value < lo then return lo end
    if hi ~= nil and value > hi then return hi end
    return value
end

local function blearn_modData()
    if NPCAdaptiveLearningBridge.Config.persistent == true and ModData and ModData.getOrCreate then
        local ok, data = pcall(function() return ModData.getOrCreate(NPCAdaptiveLearningBridge.MODDATA_KEY) end)
        if ok and type(data) == "table" then return data end
    end
    NPCAdaptiveLearningBridge._fallback = NPCAdaptiveLearningBridge._fallback or {}
    return NPCAdaptiveLearningBridge._fallback
end

function NPCAdaptiveLearningBridge.GetStore()
    local store = blearn_modData()
    store.version = store.version or NPCAdaptiveLearningBridge.VERSION
    store.createdAt = store.createdAt or blearn_nowMs()
    store.actionValues = store.actionValues or {}
    store.pathReliability = store.pathReliability or {}
    store.coverReliability = store.coverReliability or {}
    store.weaponStats = store.weaponStats or {}
    store.stats = store.stats or {updates=0, prunes=0}
    blearn_sanitizeStore(store)
    return store
end

local function blearn_count(tbl)
    local n = 0
    if type(tbl) == "table" then for _, _ in pairs(tbl) do n = n + 1 end end
    return n
end


local function blearn_jsonEscape(value)
    local s = tostring(value or "")
    s = string.gsub(s, "\\", "\\\\")
    s = string.gsub(s, "\"", "\\\"")
    s = string.gsub(s, "\b", "\\b")
    s = string.gsub(s, "\f", "\\f")
    s = string.gsub(s, "\n", "\\n")
    s = string.gsub(s, "\r", "\\r")
    s = string.gsub(s, "\t", "\\t")
    return s
end

local function blearn_jsonIsArray(tbl)
    if type(tbl) ~= "table" then return false end
    local max, count = 0, 0
    for k, _ in pairs(tbl) do
        if type(k) ~= "number" or k <= 0 or math.floor(k) ~= k then return false end
        if k > max then max = k end
        count = count + 1
    end
    return max == count
end

local function blearn_json(value, depth)
    depth = tonumber(depth) or 0
    if depth > 8 then return "null" end
    local tv = type(value)
    if tv == "nil" then return "null" end
    if tv == "boolean" then return value and "true" or "false" end
    if tv == "number" then
        if value ~= value or value == math.huge or value == -math.huge then return "0" end
        return tostring(value)
    end
    if tv == "string" then return "\"" .. blearn_jsonEscape(value) .. "\"" end
    if tv ~= "table" then return "\"" .. blearn_jsonEscape(value) .. "\"" end

    local indent = string.rep("  ", depth)
    local childIndent = string.rep("  ", depth + 1)
    local parts = {}
    if blearn_jsonIsArray(value) then
        for i = 1, #value do parts[#parts + 1] = childIndent .. blearn_json(value[i], depth + 1) end
        if #parts == 0 then return "[]" end
        return "[\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "]"
    end

    local keys = {}
    for k, _ in pairs(value) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    for _, k in ipairs(keys) do
        parts[#parts + 1] = childIndent .. "\"" .. blearn_jsonEscape(k) .. "\": " .. blearn_json(value[k], depth + 1)
    end
    if #parts == 0 then return "{}" end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end

local function blearn_fileName(name, fallback)
    name = tostring(name or fallback or "")
    if name == "" then name = fallback or "NPCAdaptiveLearning_weights.json" end
    name = string.gsub(name, "[\\/:*?\"<>|]", "_")
    return name
end

local function blearn_sortedRecords(tbl, maxCount, scoreFn)
    local out = {}
    if type(tbl) ~= "table" then return out end
    for key, rec in pairs(tbl) do
        out[#out + 1] = {key=tostring(key), rec=rec, score=scoreFn and scoreFn(rec) or 0}
    end
    table.sort(out, function(a, b)
        if a.score == b.score then return tostring(a.key) < tostring(b.key) end
        return a.score > b.score
    end)
    maxCount = tonumber(maxCount) or #out
    while #out > maxCount do out[#out] = nil end
    return out
end

local function blearn_round(value)
    value = tonumber(value) or 0
    return math.floor(value * 10000 + 0.5) / 10000
end

local function blearn_actionSnapshot(store, maxContexts)
    local contexts = blearn_sortedRecords(store.actionValues or {}, maxContexts, function(actions)
        local newest, count, bestAbs = 0, 0, 0
        if type(actions) == "table" then
            for _, rec in pairs(actions) do
                newest = math.max(newest, tonumber(rec.last) or 0)
                count = count + (tonumber(rec.n) or 0)
                bestAbs = math.max(bestAbs, math.abs(tonumber(rec.q) or 0))
            end
        end
        return count + bestAbs * 1000 + newest / 10000000000000
    end)
    local out = {}
    local maxActions = tonumber(NPCAdaptiveLearningBridge.Config.maxActionsPerContext) or 10
    for _, ctx in ipairs(contexts) do
        local actions = {}
        local actionRows = blearn_sortedRecords(ctx.rec or {}, maxActions, function(rec)
            return (tonumber(rec.n) or 0) + math.abs(tonumber(rec.q) or 0) * 1000
        end)
        for _, row in ipairs(actionRows) do
            actions[row.key] = {
                q = blearn_round(row.rec and row.rec.q or 0),
                n = tonumber(row.rec and row.rec.n) or 0,
                last = tonumber(row.rec and row.rec.last) or 0
            }
        end
        out[ctx.key] = actions
    end
    return out
end

local function blearn_reliabilitySnapshot(tbl, maxCount)
    local rows = blearn_sortedRecords(tbl or {}, maxCount, function(rec)
        return (tonumber(rec.n) or 0) + math.abs(tonumber(rec.q) or 0) * 1000 + (tonumber(rec.last) or 0) / 10000000000000
    end)
    local out = {}
    for _, row in ipairs(rows) do
        local rec = row.rec or {}
        out[row.key] = {
            q = blearn_round(rec.q or 0),
            n = tonumber(rec.n) or 0,
            success = tonumber(rec.success) or nil,
            fail = tonumber(rec.fail) or nil,
            used = tonumber(rec.used) or nil,
            survived = tonumber(rec.survived) or nil,
            hitFromCover = tonumber(rec.hitFromCover) or nil,
            shots = tonumber(rec.shots) or nil,
            hits = tonumber(rec.hits) or nil,
            last = tonumber(rec.last) or 0
        }
    end
    return out
end

local function blearn_writeFile(fileName, contents)
    if not getFileWriter then return false end
    local wrote = false
    local ok = pcall(function()
        local writer = getFileWriter(fileName, true, false)
        if writer then
            writer:write(tostring(contents or ""))
            writer:close()
            wrote = true
        end
    end)
    return ok == true and wrote == true
end
function blearn_markDirty(store)
    local cap = tonumber(NPCAdaptiveLearningBridge.Config.dirtyCounterCap) or 640
    local dirty = (tonumber(NPCAdaptiveLearningBridge._dirty) or 0) + 1
    if cap > 0 and dirty > cap then dirty = cap end
    NPCAdaptiveLearningBridge._dirty = dirty
    if store then store.dirty = true end
end

function NPCAdaptiveLearningBridge.MaybeTransmit(force)
    if not (ModData and ModData.transmit and isServer and isServer()) then return false end
    local dirty = tonumber(NPCAdaptiveLearningBridge._dirty) or 0
    if dirty <= 0 and force ~= true then return false end

    local now = blearn_nowMs()
    local every = tonumber(NPCAdaptiveLearningBridge.Config.transmitEveryUpdates) or 48
    local minMs = tonumber(NPCAdaptiveLearningBridge.Config.transmitMinMs) or 20000
    local hardFlush = tonumber(NPCAdaptiveLearningBridge.Config.dirtyHardFlush) or 160
    if force ~= true and dirty < every and dirty < hardFlush and now - (tonumber(NPCAdaptiveLearningBridge._lastTransmitMs) or 0) < minMs then
        return false
    end

    if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.UseBudget and not force then
        local okBudget = NPCWorkSchedulerBridge.UseBudget("learning", NPCWorkSchedulerBridge.GetBudget and NPCWorkSchedulerBridge.GetBudget("learning") or 1)
        if not okBudget and dirty < hardFlush then return false end
    end

    NPCAdaptiveLearningBridge._lastTransmitMs = now
    NPCAdaptiveLearningBridge._dirty = 0
    local ok = pcall(function() ModData.transmit(NPCAdaptiveLearningBridge.MODDATA_KEY) end)
    return ok == true
end


function NPCAdaptiveLearningBridge.ExportWeightsSnapshot(maxContexts, maxPaths)
    local store = NPCAdaptiveLearningBridge.GetStore()
    maxContexts = tonumber(maxContexts) or tonumber(NPCAdaptiveLearningBridge.Config.exportMaxContexts) or 400
    maxPaths = tonumber(maxPaths) or tonumber(NPCAdaptiveLearningBridge.Config.exportMaxPathEntries) or 800
    local maxCover = tonumber(NPCAdaptiveLearningBridge.Config.exportMaxCoverEntries) or 400
    local maxWeapons = tonumber(NPCAdaptiveLearningBridge.Config.exportMaxWeaponEntries) or 300
    return {
        schema = "NPCAdaptiveLearningWeightsExport.v1",
        exportedAt = blearn_nowMs(),
        version = store.version or NPCAdaptiveLearningBridge.VERSION,
        summary = NPCAdaptiveLearningBridge.ExportSummary(),
        config = {
            alpha = NPCAdaptiveLearningBridge.Config.alpha,
            strength = NPCAdaptiveLearningBridge.Config.strength,
            minSamples = NPCAdaptiveLearningBridge.Config.minSamples,
            maxPriorityModifier = NPCAdaptiveLearningBridge.Config.maxPriorityModifier,
            contextsWritten = maxContexts,
            pathsWritten = maxPaths,
            coversWritten = maxCover,
            weaponsWritten = maxWeapons
        },
        actionValues = blearn_actionSnapshot(store, maxContexts),
        pathReliability = blearn_reliabilitySnapshot(store.pathReliability, maxPaths),
        coverReliability = blearn_reliabilitySnapshot(store.coverReliability, maxCover),
        weaponStats = blearn_reliabilitySnapshot(store.weaponStats, maxWeapons)
    }
end

function NPCAdaptiveLearningBridge.ExportWeightsTextSummary(snapshot)
    snapshot = snapshot or NPCAdaptiveLearningBridge.ExportWeightsSnapshot(80, 120)
    local summary = snapshot.summary or {}
    local lines = {}
    lines[#lines + 1] = "NPC Adaptive Learning Weights Summary"
    lines[#lines + 1] = "version=" .. tostring(snapshot.version or "unknown")
    lines[#lines + 1] = "exportedAt=" .. tostring(snapshot.exportedAt or 0)
    lines[#lines + 1] = "contexts=" .. tostring(summary.contexts or 0)
    lines[#lines + 1] = "paths=" .. tostring(summary.paths or 0)
    lines[#lines + 1] = "covers=" .. tostring(summary.covers or 0)
    lines[#lines + 1] = "weapons=" .. tostring(summary.weapons or 0)
    lines[#lines + 1] = "updates=" .. tostring(summary.updates or 0)
    lines[#lines + 1] = "prunes=" .. tostring(summary.prunes or 0)
    lines[#lines + 1] = "dirty=" .. tostring(summary.dirty or 0)
    lines[#lines + 1] = "lastExportOk=" .. tostring(summary.lastExportOk)
    lines[#lines + 1] = "lastExportFile=" .. tostring(summary.lastExportFile or "")
    return table.concat(lines, "\n") .. "\n"
end

function NPCAdaptiveLearningBridge.WriteWeightsFile(force)
    if NPCAdaptiveLearningBridge.Config.exportWeightsFile ~= true and force ~= true then return false end
    if NPCAdaptiveLearningBridge._exporting == true then return false end
    if not getFileWriter then return false end

    NPCAdaptiveLearningBridge._exporting = true
    local ok, result = pcall(function()
        local snapshot = NPCAdaptiveLearningBridge.ExportWeightsSnapshot()
        local fileName = blearn_fileName(NPCAdaptiveLearningBridge.Config.exportWeightsFileName, "NPCAdaptiveLearning_weights.json")
        local summaryName = blearn_fileName(NPCAdaptiveLearningBridge.Config.exportWeightsSummaryFileName, "NPCAdaptiveLearning_weights_summary.txt")
        local wroteMain = blearn_writeFile(fileName, blearn_json(snapshot, 0) .. "\n")
        local wroteSummary = blearn_writeFile(summaryName, NPCAdaptiveLearningBridge.ExportWeightsTextSummary(snapshot))
        local store = NPCAdaptiveLearningBridge.GetStore()
        store.lastWeightsExportAt = snapshot.exportedAt
        store.lastWeightsExportFile = fileName
        store.lastWeightsExportSummaryFile = summaryName
        store.lastWeightsExportOk = wroteMain == true
        store.lastWeightsExportSummaryOk = wroteSummary == true
        NPCAdaptiveLearningBridge._lastExportMs = snapshot.exportedAt
        return wroteMain == true
    end)
    NPCAdaptiveLearningBridge._exporting = false
    return ok == true and result == true
end

function NPCAdaptiveLearningBridge.MaybeExportWeights(force)
    if force == true then return NPCAdaptiveLearningBridge.WriteWeightsFile(true) end
    if NPCAdaptiveLearningBridge.Config.exportWeightsFile ~= true then return false end
    local dirty = tonumber(NPCAdaptiveLearningBridge._dirty) or 0
    if dirty <= 0 then return false end
    local now = blearn_nowMs()
    local every = tonumber(NPCAdaptiveLearningBridge.Config.exportEveryUpdates) or 96
    local minMs = tonumber(NPCAdaptiveLearningBridge.Config.exportMinMs) or 60000
    if dirty < every and now - (tonumber(NPCAdaptiveLearningBridge._lastExportMs) or 0) < minMs then return false end
    if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.UseBudget then
        local okBudget = NPCWorkSchedulerBridge.UseBudget("learning", NPCWorkSchedulerBridge.GetBudget and NPCWorkSchedulerBridge.GetBudget("learning") or 1)
        if not okBudget and dirty < every * 2 then return false end
    end
    return NPCAdaptiveLearningBridge.WriteWeightsFile(false)
end


local function blearn_bucketDist(dist)
    dist = tonumber(dist) or 9999
    if dist <= 4 then return "near" end
    if dist <= 10 then return "mid" end
    if dist <= 22 then return "far" end
    return "veryfar"
end

local function blearn_bool(value, yes, no)
    return value and (yes or "yes") or (no or "no")
end

local function blearn_safeToken(value, fallback)
    fallback = tostring(fallback or "unknown")
    local tv = type(value)
    if tv == "string" then
        local out = value
        if out == "" or string.find(out, "table 0x", 1, true) then return fallback end
        if string.len(out) > 28 then out = string.sub(out, 1, 28) end
        return out
    end
    if tv == "number" or tv == "boolean" then return tostring(value) end
    if tv ~= "table" then return fallback end

    local keys = {"role", "squadRole", "tacticalRole", "job", "name", "type", "kind", "id", "side", "faction", "clan", "team"}
    for _, key in ipairs(keys) do
        local got = blearn_safeToken(value[key], nil)
        if got and got ~= "unknown" then return got end
    end
    return fallback
end

local function blearn_actionKey(context, action)
    return tostring(context or "") .. "|" .. tostring(action or "")
end

local function blearn_throttle(map, key, now, minMs)
    minMs = tonumber(minMs) or 0
    if minMs <= 0 then return false end
    map = map or {}
    local last = tonumber(map[key]) or 0
    if last > 0 and now - last < minMs then return true end
    map[key] = now
    return false
end

function blearn_sanitizeStore(store)
    if NPCAdaptiveLearningBridge._sanitizedStore == true then return end
    NPCAdaptiveLearningBridge._sanitizedStore = true
    if type(store) ~= "table" or type(store.actionValues) ~= "table" then return end
    local removed = 0
    for k, _ in pairs(store.actionValues) do
        if string.find(tostring(k), "table 0x", 1, true) then
            store.actionValues[k] = nil
            removed = removed + 1
        end
    end
    if removed > 0 then blearn_markDirty(store) end
end

function NPCAdaptiveLearningBridge.MakeContext(brain, situation, data)
    data = data or {}
    local role = blearn_safeToken(brain and (brain.role or brain.squadRole or brain.tacticalRole or brain.job or brain.program or brain.behaviorRole), "npc")
    local faction = blearn_safeToken(brain and (brain.faction or brain.clan or brain.side or brain.team), "neutral")
    local indoor = data.indoor
    if indoor == nil and brain and brain.actionRouter and brain.actionRouter.lastIndoor ~= nil then indoor = brain.actionRouter.lastIndoor end
    local threat = tonumber(data.enemyConfidence or (brain and brain.ai and brain.ai.enemyConfidence)) or 0
    local threatBucket = threat >= 0.70 and "hot" or (threat >= 0.30 and "warm" or "cold")
    local distBucket = blearn_bucketDist(data.dist or (brain and brain.currentThreat and brain.currentThreat.dist))
    local weapon = blearn_safeToken(data.weaponCategory or data.weapon or (brain and brain.weaponCategory), "unknown")
    if string.len(weapon) > 24 then weapon = string.sub(weapon, 1, 24) end
    return table.concat({role, faction, tostring(situation or "generic"), blearn_bool(indoor == true, "indoor", "outdoor"), threatBucket, distBucket, weapon}, "|")
end

local function blearn_actionTable(store, context)
    store.actionValues[context] = store.actionValues[context] or {}
    return store.actionValues[context]
end

function NPCAdaptiveLearningBridge.Update(context, action, reward, data)
    if NPCAdaptiveLearningBridge.Config.enabled ~= true then return nil end
    if not context or not action then return nil end
    local now = blearn_nowMs()
    local throttleKey = blearn_actionKey(context, action)
    if blearn_throttle(NPCAdaptiveLearningBridge._lastActionUpdate, throttleKey, now, NPCAdaptiveLearningBridge.Config.updateMinMs) then return nil end
    local store = NPCAdaptiveLearningBridge.GetStore()
    local actions = blearn_actionTable(store, tostring(context))
    action = tostring(action)
    local rec = actions[action] or {q=0, n=0, last=0}
    local alpha = tonumber(NPCAdaptiveLearningBridge.Config.alpha) or 0.12
    reward = blearn_clamp(reward, -1, 1)
    rec.q = (tonumber(rec.q) or 0) + alpha * (reward - (tonumber(rec.q) or 0))
    rec.n = (tonumber(rec.n) or 0) + 1
    rec.last = now
    actions[action] = rec
    store.stats.updates = (tonumber(store.stats.updates) or 0) + 1
    NPCAdaptiveLearningBridge._updates = (tonumber(NPCAdaptiveLearningBridge._updates) or 0) + 1
    blearn_markDirty(store)
    if NPCAdaptiveLearningBridge._updates % (tonumber(NPCAdaptiveLearningBridge.Config.pruneEveryUpdates) or 160) == 0 then
        NPCAdaptiveLearningBridge.Prune(store)
    end
    NPCAdaptiveLearningBridge.MaybeTransmit(false)
    NPCAdaptiveLearningBridge.MaybeExportWeights(false)
    return rec
end

function NPCAdaptiveLearningBridge.GetActionValue(context, action)
    local store = NPCAdaptiveLearningBridge.GetStore()
    local rec = store.actionValues and store.actionValues[tostring(context or "")] and store.actionValues[tostring(context or "")][tostring(action or "")]
    if not rec then return 0, 0 end
    return tonumber(rec.q) or 0, tonumber(rec.n) or 0
end

function NPCAdaptiveLearningBridge.GetTaskPriorityModifier(brain, task, context)
    if NPCAdaptiveLearningBridge.Config.enabled ~= true then return 0 end
    if not task then return 0 end
    local action = tostring(task.action or "unknown")
    if action == "Die" or action == "Zombify" or action == "Shoot" or action == "Hit" or action == "Shove" then return 0 end
    local situation = (context and context.source) or task.routerSource or task.orderName or task.directorReason or "task"
    local ctx = NPCAdaptiveLearningBridge.MakeContext(brain, situation, {dist=task.dist, indoor=task.indoor, enemyConfidence=brain and brain.ai and brain.ai.enemyConfidence})
    local q, n = NPCAdaptiveLearningBridge.GetActionValue(ctx, action)
    if n < (tonumber(NPCAdaptiveLearningBridge.Config.minSamples) or 3) then return 0 end
    local max = tonumber(NPCAdaptiveLearningBridge.Config.maxPriorityModifier) or 6
    return math.floor(blearn_clamp(q * max, -max, max) + 0.5)
end

local function blearn_targetHash(taskOrPos)
    if type(taskOrPos) ~= "table" or taskOrPos.x == nil or taskOrPos.y == nil then return nil end
    local cell = math.max(1, tonumber(NPCAdaptiveLearningBridge.Config.pathCellSize) or 4)
    local x = math.floor(((tonumber(taskOrPos.x) or 0) / cell) + 0.5) * cell
    local y = math.floor(((tonumber(taskOrPos.y) or 0) / cell) + 0.5) * cell
    return tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(math.floor(tonumber(taskOrPos.z) or 0))
end

function NPCAdaptiveLearningBridge.RecordPathOutcome(taskOrPos, success, reward, data)
    if NPCAdaptiveLearningBridge.Config.enabled ~= true then return nil end
    local key = blearn_targetHash(taskOrPos)
    if not key then return nil end
    local now = blearn_nowMs()
    local throttleKey = key .. ":" .. tostring(success == true)
    if blearn_throttle(NPCAdaptiveLearningBridge._lastPathRecord, throttleKey, now, NPCAdaptiveLearningBridge.Config.pathRecordMinMs) then return nil end
    local store = NPCAdaptiveLearningBridge.GetStore()
    local rec = store.pathReliability[key] or {q=0, n=0, success=0, fail=0, last=0}
    local alpha = tonumber(NPCAdaptiveLearningBridge.Config.alpha) or 0.12
    reward = blearn_clamp(reward or (success and 0.25 or -0.35), -1, 1)
    rec.q = (tonumber(rec.q) or 0) + alpha * (reward - (tonumber(rec.q) or 0))
    rec.n = (tonumber(rec.n) or 0) + 1
    if success then rec.success = (tonumber(rec.success) or 0) + 1 else rec.fail = (tonumber(rec.fail) or 0) + 1 end
    rec.last = now
    store.pathReliability[key] = rec
    blearn_markDirty(store)
    NPCAdaptiveLearningBridge.MaybeTransmit(false)
    NPCAdaptiveLearningBridge.MaybeExportWeights(false)
    return rec
end

function NPCAdaptiveLearningBridge.GetPathModifier(taskOrPos)
    local key = blearn_targetHash(taskOrPos)
    if not key then return 0 end
    local store = NPCAdaptiveLearningBridge.GetStore()
    local rec = store.pathReliability and store.pathReliability[key]
    if not rec or (tonumber(rec.n) or 0) < (tonumber(NPCAdaptiveLearningBridge.Config.minSamples) or 3) then return 0 end
    local max = tonumber(NPCAdaptiveLearningBridge.Config.maxPriorityModifier) or 6
    return math.floor(blearn_clamp((tonumber(rec.q) or 0) * max, -max, max) + 0.5)
end

function NPCAdaptiveLearningBridge.Prune(store)
    store = store or NPCAdaptiveLearningBridge.GetStore()
    local now = blearn_nowMs()
    local maxContexts = tonumber(NPCAdaptiveLearningBridge.Config.maxContexts) or 1600
    local contexts = {}
    for k, actions in pairs(store.actionValues or {}) do
        if string.find(tostring(k), "table 0x", 1, true) then
            store.actionValues[k] = nil
        else
        local newest, count = 0, 0
        for _, rec in pairs(actions) do
            newest = math.max(newest, tonumber(rec.last) or 0)
            count = count + (tonumber(rec.n) or 0)
        end
        contexts[#contexts + 1] = {key=k, last=newest, count=count}
        end
    end
    if #contexts > maxContexts then
        table.sort(contexts, function(a, b)
            if a.count == b.count then return a.last > b.last end
            return a.count > b.count
        end)
        for i = maxContexts + 1, #contexts do store.actionValues[contexts[i].key] = nil end
    end

    local maxPaths = tonumber(NPCAdaptiveLearningBridge.Config.maxPathEntries) or 2600
    local paths = {}
    for k, rec in pairs(store.pathReliability or {}) do paths[#paths + 1] = {key=k, last=tonumber(rec.last) or 0, n=tonumber(rec.n) or 0} end
    if #paths > maxPaths then
        table.sort(paths, function(a, b)
            if a.n == b.n then return a.last > b.last end
            return a.n > b.n
        end)
        for i = maxPaths + 1, #paths do store.pathReliability[paths[i].key] = nil end
    end
    store.stats.prunes = (tonumber(store.stats.prunes) or 0) + 1
    store.lastPruneAt = now
    blearn_markDirty(store)
end

function NPCAdaptiveLearningBridge.ExportSummary()
    local store = NPCAdaptiveLearningBridge.GetStore()
    return {
        version = store.version,
        contexts = blearn_count(store.actionValues),
        paths = blearn_count(store.pathReliability),
        covers = blearn_count(store.coverReliability),
        weapons = blearn_count(store.weaponStats),
        updates = store.stats and store.stats.updates or 0,
        prunes = store.stats and store.stats.prunes or 0,
        dirty = tonumber(NPCAdaptiveLearningBridge._dirty) or 0,
        lastExportAt = store.lastWeightsExportAt or 0,
        lastExportOk = store.lastWeightsExportOk == true,
        lastExportFile = store.lastWeightsExportFile,
        lastExportSummaryFile = store.lastWeightsExportSummaryFile
    }
end

function NPCAdaptiveLearningBridge.Flush()
    local transmitted = NPCAdaptiveLearningBridge.MaybeTransmit(true)
    local exported = NPCAdaptiveLearningBridge.WriteWeightsFile(true)
    return transmitted == true or exported == true
end

function NPCAdaptiveLearningBridge.ExportWeightsNow()
    return NPCAdaptiveLearningBridge.WriteWeightsFile(true)
end
