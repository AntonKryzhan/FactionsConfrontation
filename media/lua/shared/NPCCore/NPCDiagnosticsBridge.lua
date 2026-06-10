require "NPCCore/NPCLegacySettingsBridge"
require "NPCCore/NPCLegacyContractBridge"

NPCDiagnosticsBridge = NPCDiagnosticsBridge or {}
NPCDiagnosticsBridge._last = NPCDiagnosticsBridge._last or {}
NPCDiagnosticsBridge._seq = NPCDiagnosticsBridge._seq or 0
NPCDiagnosticsBridge._frame = NPCDiagnosticsBridge._frame or {}
NPCDiagnosticsBridge._state = NPCDiagnosticsBridge._state or {}
NPCDiagnosticsBridge._fileBudget = NPCDiagnosticsBridge._fileBudget or {sec=-1, count=0, dropped=0, writing=false}
NPCDiagnosticsBridge._worldSnapshotAt = NPCDiagnosticsBridge._worldSnapshotAt or 0
NPCDiagnosticsBridge._systemSnapshotAt = NPCDiagnosticsBridge._systemSnapshotAt or 0
NPCDiagnosticsBridge._visibleFrame = NPCDiagnosticsBridge._visibleFrame or {}
NPCDiagnosticsBridge._riskLast = NPCDiagnosticsBridge._riskLast or {}
NPCDiagnosticsBridge._compact = NPCDiagnosticsBridge._compact or {signature=nil, line=nil, count=0, firstMs=0, lastMs=0, force=false}
NPCDiagnosticsBridge._flushHookInstalled = NPCDiagnosticsBridge._flushHookInstalled or false

local NPC_DIAGNOSTICS_LEGACY_KEYS = {
    liveFlag = NPCLegacyContractBridge.Key("FLAG"),
    formerNPCZombie = NPCLegacyContractBridge.Key("FORMER_ZOMBIE"),
    runtimeId = NPCLegacyContractBridge.Key("RUNTIME_ID"),
    persistentId = NPCLegacyContractBridge.Key("PERSISTENT_ID"),
    worldGroupId = NPCLegacyContractBridge.Key("WORLD_GROUP_ID"),
    mdFlag = NPCLegacyContractBridge.Key("IS_FLAG"),
    walkType = NPCLegacyContractBridge.Key("WALK_TYPE"),
    primary = NPCLegacyContractBridge.Key("PRIMARY"),
    secondary = NPCLegacyContractBridge.Key("SECONDARY")
}
local NPC_DIAGNOSTICS_LOG_PREFIX = "[NPCDiag]"
local NPC_DIAGNOSTICS_FILE_DEFAULT = "NPC_FACTIONS.log"

local function bd_setting(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.Get then
        return NPCLegacySettingsBridge.Get(name, defaultValue)
    end
    return defaultValue
end

local function bd_settingBool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        return NPCLegacySettingsBridge.GetBool(name, defaultValue == true)
    end
    return defaultValue == true
end

local function bd_settingNumber(name, defaultValue, minValue, maxValue)
    local value = defaultValue
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        value = NPCLegacySettingsBridge.GetNumber(name, defaultValue, minValue, maxValue)
    end
    value = tonumber(value) or tonumber(defaultValue) or 0
    if minValue ~= nil and value < minValue then value = minValue end
    if maxValue ~= nil and value > maxValue then value = maxValue end
    return value
end

local function bd_nowMs()
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

local function bd_worldAge()
    if getGameTime then
        local ok, value = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok and value then return tonumber(value) or 0 end
    end
    return 0
end

local function bd_side()
    if isServer and isServer() then return "SERVER" end
    if isClient and isClient() then return "CLIENT" end
    return "LOCAL"
end

local function bd_fps()
    if getAverageFPS then
        local ok, fps = pcall(function() return getAverageFPS() end)
        if ok and fps then return math.floor((tonumber(fps) or 0) * 10 + 0.5) / 10 end
    end
    return nil
end

local function bd_count(t)
    local n = 0
    if type(t) == "table" then
        for _, _ in pairs(t) do n = n + 1 end
    end
    return n
end

local function bd_round(value, digits)
    local n = tonumber(value)
    if not n then return value end
    local m = 10 ^ (digits or 2)
    return math.floor(n * m + 0.5) / m
end

local function bd_value(value)
    if value == nil then return "nil" end
    local vt = type(value)
    if vt == "table" then return "table" end
    if vt == "boolean" then return value and "true" or "false" end
    if vt == "number" then return tostring(bd_round(value, 3)) end
    local s = tostring(value)
    s = string.gsub(s, "[\r\n|]", " ")
    if string.len(s) > 128 then s = string.sub(s, 1, 128) .. "..." end
    return s
end

local function bd_appendData(parts, data)
    if type(data) ~= "table" then return end
    local entries = {}
    for k, v in pairs(data) do entries[#entries + 1] = {key=tostring(k), value=v} end
    table.sort(entries, function(a, b) return tostring(a.key) < tostring(b.key) end)
    for _, e in ipairs(entries) do
        table.insert(parts, tostring(e.key) .. "=" .. bd_value(e.value))
    end
end

local function bd_fileName()
    local fileName = bd_setting("Debug_DiagnosticsFileName", NPC_DIAGNOSTICS_FILE_DEFAULT)
    if not fileName or tostring(fileName) == "" then return NPC_DIAGNOSTICS_FILE_DEFAULT end
    return tostring(fileName)
end

local function bd_fileLogEnabled()
    return bd_settingBool("Debug_DiagnosticsFileLog", false)
end

local function bd_consoleLogEnabled()
    return bd_settingBool("Debug_DiagnosticsConsoleLog", false)
end

local function bd_canWriteFile(force)
    if force == true then return true end
    local budget = NPCDiagnosticsBridge._fileBudget
    local maxPerSecond = bd_settingNumber("Debug_DiagnosticsMaxLinesPerSecond", 4, 1, 2000)
    local nowMs = bd_nowMs()
    local sec = math.floor(nowMs / 1000)
    if budget.sec ~= sec then
        budget.sec = sec
        budget.count = 0
    end
    if budget.count >= maxPerSecond then
        budget.dropped = (tonumber(budget.dropped) or 0) + 1
        return false
    end
    budget.count = budget.count + 1
    return true
end

local function bd_writeFileRaw(line, force)
    if not bd_fileLogEnabled() then return false end
    if not getFileWriter then return false end
    if not bd_canWriteFile(force == true) then return false end
    local budget = NPCDiagnosticsBridge._fileBudget
    if budget.writing == true then return false end
    budget.writing = true
    local ok = pcall(function()
        local writer = getFileWriter(bd_fileName(), true, true)
        if writer then
            writer:write(tostring(line or "") .. "\n")
            writer:close()
        end
    end)
    budget.writing = false
    return ok == true
end

local function bd_compactSignature(line)
    local s = tostring(line or "")
    s = string.gsub(s, "#%d+", "#*")
    s = string.gsub(s, "t=[^|]+", "t=*")
    s = string.gsub(s, "ms=%d+", "ms=*")
    s = string.gsub(s, "fps=[^|]+", "fps=*")
    -- Runtime coordinates and volatile counters make useful repeat compaction impossible.
    -- Keep coarse semantic fields and normalize values that frequently differ on each frame.
    s = string.gsub(s, " | x=[^|]+", " | x=*")
    s = string.gsub(s, " | y=[^|]+", " | y=*")
    s = string.gsub(s, " | z=[^|]+", " | z=*")
    s = string.gsub(s, " | elapsedMs=[^|]+", " | elapsedMs=*")
    return s
end

local function bd_compactFlush(force)
    local c = NPCDiagnosticsBridge._compact
    if not c or not c.line or (tonumber(c.count) or 0) <= 0 then return false end
    local line = tostring(c.line)
    if (tonumber(c.count) or 0) > 1 then
        line = line .. " | repeatCount=" .. tostring(c.count) .. " | compactMs=" .. tostring(math.max(0, (tonumber(c.lastMs) or 0) - (tonumber(c.firstMs) or 0)))
    end
    NPCDiagnosticsBridge._compact = {signature=nil, line=nil, count=0, firstMs=0, lastMs=0, force=false}
    return bd_writeFileRaw(line, force == true or c.force == true)
end

local function bd_writeFile(line, force)
    if not bd_fileLogEnabled() then return false end
    if not bd_settingBool("Debug_DiagnosticsCompactRepeats", true) then
        return bd_writeFileRaw(line, force == true)
    end

    local now = bd_nowMs()
    local flushMs = bd_settingNumber("Debug_DiagnosticsCompactFlushMs", 1200, 100, 30000)
    local c = NPCDiagnosticsBridge._compact
    if c and c.line and (now - (tonumber(c.lastMs) or 0)) >= flushMs then
        bd_compactFlush(false)
        c = NPCDiagnosticsBridge._compact
    end

    local sig = bd_compactSignature(line)
    if c and c.line and c.signature == sig then
        c.count = (tonumber(c.count) or 1) + 1
        c.lastMs = now
        c.force = c.force == true or force == true
        return true
    end

    bd_compactFlush(force == true)
    NPCDiagnosticsBridge._compact = {signature=sig, line=tostring(line or ""), count=1, firstMs=now, lastMs=now, force=force == true}
    return true
end

local function bd_characterId(chr)
    if not chr then return nil end
    if NPCUtils and NPCUtils.GetCharacterID then
        local ok, id = pcall(function() return NPCUtils.GetCharacterID(chr) end)
        if ok and id ~= nil then return id end
    end
    return nil
end

local function bd_call(chr, method)
    if not (chr and method and chr[method]) then return nil end
    local ok, value = pcall(function() return chr[method](chr) end)
    if ok then return value end
    return nil
end

local function bd_var(chr, name)
    if not (chr and name and chr.getVariableString) then return nil end
    local ok, value = pcall(function() return chr:getVariableString(name) end)
    if ok and value and value ~= "" then return value end
    local okBool, valueBool = pcall(function() return chr:getVariableBoolean(name) end)
    if okBool and valueBool ~= nil then return valueBool end
    return nil
end

local function bd_itemName(item)
    if not item then return nil end
    local ok, value = pcall(function()
        if item.getFullType then return item:getFullType() end
        if item.getType then return item:getType() end
        return tostring(item)
    end)
    if ok then return value end
    return nil
end

local function bd_taskValue(task, key)
    if type(task) ~= "table" then return nil end
    return task[key]
end

local function bd_brainRuntimeId(brain, zombie)
    if type(brain) == "table" then
        return brain.id or brain.runtimeId or brain.uid or brain.persistentId
    end
    return bd_characterId(zombie)
end

local function bd_traceKey(zombie, brain, prefix)
    local id = bd_brainRuntimeId(brain, zombie) or "unknown"
    return tostring(prefix or "npc") .. ":" .. tostring(id)
end

local function bd_merge(out, data)
    if type(data) ~= "table" then return end
    for k, v in pairs(data) do out[k] = v end
end

function NPCDiagnosticsBridge.Enabled()
    return bd_settingBool("Debug_DiagnosticsLog", false)
end

function NPCDiagnosticsBridge.VerboseEnabled()
    return bd_settingBool("Debug_DiagnosticsVerbose", false)
end

function NPCDiagnosticsBridge.FullTraceEnabled()
    return bd_settingBool("Debug_DiagnosticsFullTrace", false)
end

function NPCDiagnosticsBridge.Count(t)
    return bd_count(t)
end

function NPCDiagnosticsBridge.DescribeBrain(brain)
    if type(brain) ~= "table" then return {} end

    local programName = brain.programName
    local programStage = brain.programStage
    if type(brain.program) == "table" then
        programName = brain.program.name or programName
        programStage = brain.program.stage or programStage
    elseif brain.program ~= nil then
        programName = tostring(brain.program)
    end

    local state = nil
    local order = nil
    if type(brain.sim) == "table" then
        state = brain.sim.state
        order = brain.sim.order
    end

    local targetId = brain.targetId or brain.enemyId
    if type(brain.fsm) == "table" then
        targetId = targetId or brain.fsm.targetId
    end
    if type(brain.ai) == "table" and type(brain.ai.intentArbiter) == "table" and type(brain.ai.intentArbiter.active) == "table" then
        -- recorded below as activeIntent*
    end

    local data = {
        id = brain.id,
        uid = brain.uid,
        persistentId = brain.persistentId,
        groupId = brain.worldGroupId or brain.groupId,
        program = programName,
        stage = programStage,
        health = brain.health,
        infection = brain.infection,
        state = state or brain.state,
        reason = brain.reason,
        order = order,
        targetId = targetId,
        dead = brain.dead,
        clan = brain.clan,
        faction = brain.factionSide or brain.faction or brain.side or brain.patrolColor
    }

    if type(brain.ai) == "table" then
        if type(brain.ai.intentArbiter) == "table" and type(brain.ai.intentArbiter.active) == "table" then
            local a = brain.ai.intentArbiter.active
            data.activeIntent = a.name or a.owner or a.intent
            data.activeIntentReason = a.reason
            data.activeIntentPriority = a.priority
        end
        if type(brain.ai.movementIntent) == "table" and type(brain.ai.movementIntent.active) == "table" then
            local m = brain.ai.movementIntent.active
            data.moveIntentOwner = m.owner
            data.moveIntentAction = m.action
            data.moveIntentX = m.x
            data.moveIntentY = m.y
            data.moveIntentPriority = m.priority
        end
        if type(brain.ai.pathThrottle) == "table" then
            data.pathDenied = brain.ai.pathThrottle.denied
            data.pathFailCount = brain.ai.pathThrottle.failCount
            data.lastPathDeny = brain.ai.pathThrottle.lastDeniedReason
        end
        if type(brain.ai.living) == "table" then
            data.livingState = brain.ai.living.state or brain.ai.living.lastIntent
            data.livingSuppressed = brain.ai.living.emergencyDisabled or brain.ai.living.suppressed
        end
    end
    if type(brain.watchdog) == "table" then
        data.watchdogStuck = brain.watchdog.stuck
        data.watchdogTicks = brain.watchdog.stuckTicks
    end
    return data
end

function NPCDiagnosticsBridge.DescribeZombie(zombie)
    if not zombie then return {} end
    local md = nil
    local ok, modData = pcall(function() return zombie:getModData() end)
    if ok then md = modData end
    local x = bd_call(zombie, "getX")
    local y = bd_call(zombie, "getY")
    local z = bd_call(zombie, "getZ")
    local target = bd_call(zombie, "getTarget")
    local attackedBy = bd_call(zombie, "getAttackedBy")
    local primary = bd_call(zombie, "getPrimaryHandItem")
    local secondary = bd_call(zombie, "getSecondaryHandItem")
    local state = bd_call(zombie, "getActionStateName")
    local square = bd_call(zombie, "getSquare")
    local roomName = nil
    if square and square.getRoom then
        local okRoom, room = pcall(function() return square:getRoom() end)
        if okRoom and room and room.getName then
            local okName, rn = pcall(function() return room:getName() end)
            if okName then roomName = rn end
        end
    end
    return {
        charId = bd_characterId(zombie),
        x = x and bd_round(x, 2) or nil,
        y = y and bd_round(y, 2) or nil,
        z = z,
        actionState = state,
        walkType = bd_var(zombie, NPC_DIAGNOSTICS_LEGACY_KEYS.walkType),
        primary = bd_itemName(primary),
        secondary = bd_itemName(secondary),
        targetCharId = bd_characterId(target),
        attackedById = bd_characterId(attackedBy),
        room = roomName,
        banditVar = bd_var(zombie, NPC_DIAGNOSTICS_LEGACY_KEYS.liveFlag),
        formerVar = bd_var(zombie, NPC_DIAGNOSTICS_LEGACY_KEYS.formerNPCZombie),
        runtimeVar = bd_var(zombie, NPC_DIAGNOSTICS_LEGACY_KEYS.runtimeId),
        persistentVar = bd_var(zombie, NPC_DIAGNOSTICS_LEGACY_KEYS.persistentId),
        groupVar = bd_var(zombie, NPC_DIAGNOSTICS_LEGACY_KEYS.worldGroupId),
        isNPCMD = md and md[NPC_DIAGNOSTICS_LEGACY_KEYS.mdFlag] or nil,
        formerMD = md and md[NPC_DIAGNOSTICS_LEGACY_KEYS.formerNPCZombie] or nil,
        runtimeMD = md and md[NPC_DIAGNOSTICS_LEGACY_KEYS.runtimeId] or nil,
        persistentMD = md and md[NPC_DIAGNOSTICS_LEGACY_KEYS.persistentId] or nil,
        groupMD = md and md[NPC_DIAGNOSTICS_LEGACY_KEYS.worldGroupId] or nil,
        health = bd_call(zombie, "getHealth"),
        alive = bd_call(zombie, "isAlive"),
        useless = bd_call(zombie, "isUseless"),
        teleporting = bd_call(zombie, "isTeleporting")
    }
end

function NPCDiagnosticsBridge.DescribeTask(task)
    if type(task) ~= "table" then return {} end
    local out = {
        taskAction = task.action,
        taskState = task.state,
        taskAnim = task.anim,
        taskTime = task.time and bd_round(task.time, 2) or nil,
        taskX = task.x and bd_round(task.x, 2) or nil,
        taskY = task.y and bd_round(task.y, 2) or nil,
        taskZ = task.z,
        taskWalk = task.walkType,
        taskTargetId = task.targetId or task.eid,
        taskTargetKind = task.targetKind,
        taskReason = task.directorReason or task.reason,
        taskDirectorState = task.directorState or task.stateName,
        taskCombat = task.combatMove or task.combatTask,
        taskLiving = task.livingIntent or task.livingMoveIntent,
        taskBase = task.baseDailyLife or task.baseDuty,
        taskSupply = task.supplyNeed or task.lootNeed,
        taskSquad = task.squadSupport
    }
    if type(task._bms) == "table" then
        out.moveOwner = task._bms.intentOwner
        out.movePriority = task._bms.intentPriority
        out.moveCancelled = task._bms.cancelled
        out.moveCancelReason = task._bms.cancelReason
        out.moveReplans = task._bms.replans
        out.moveSpinLoop = task._bms.spinLoop
        out.moveDirect = task._bms.directMove
        out.pathStarted = task._bms.pathStarted
        out.pathX = task._bms.pathX
        out.pathY = task._bms.pathY
        out.pathZ = task._bms.pathZ
    end
    return out
end

function NPCDiagnosticsBridge.Log(channel, message, data, key, force)
    if not NPCDiagnosticsBridge.Enabled() then return end

    key = key or tostring(channel) .. ":" .. tostring(message)
    local nowForRate = bd_nowMs()
    local noisyIdentity = channel == "NPC_IDENTITY" or channel == "NPC_APPEARANCE"
    if noisyIdentity then
        local globalRateMs = bd_settingNumber("Debug_DiagnosticsIdentityGlobalRateMs", 3500, 0, 60000)
        local lastGlobal = NPCDiagnosticsBridge._last["global:" .. tostring(channel)]
        if globalRateMs > 0 and lastGlobal ~= nil and nowForRate - (tonumber(lastGlobal) or 0) < globalRateMs then return end
        NPCDiagnosticsBridge._last["global:" .. tostring(channel)] = nowForRate
    end
    if force == true and noisyIdentity then
        local forcedRateMs = bd_settingNumber("Debug_DiagnosticsForcedIdentityRateMs", 2500, 250, 60000)
        local lastForced = NPCDiagnosticsBridge._last["forced:" .. tostring(key)]
        if lastForced ~= nil and nowForRate - (tonumber(lastForced) or 0) < forcedRateMs then return end
        NPCDiagnosticsBridge._last["forced:" .. tostring(key)] = nowForRate
        force = false
    end
    if not force then
        local rateMs = bd_settingNumber("Debug_DiagnosticsRateMs", noisyIdentity and 30000 or 12000, 0, 60000)
        if rateMs > 0 then
            local last = NPCDiagnosticsBridge._last[key]
            if last ~= nil and nowForRate - (tonumber(last) or 0) < rateMs then return end
            NPCDiagnosticsBridge._last[key] = nowForRate
        end
    end

    NPCDiagnosticsBridge._seq = (tonumber(NPCDiagnosticsBridge._seq) or 0) + 1

    local parts = {}
    table.insert(parts, NPC_DIAGNOSTICS_LOG_PREFIX)
    table.insert(parts, "[" .. bd_side() .. "]")
    table.insert(parts, "[" .. tostring(channel or "General") .. "]")
    table.insert(parts, "#" .. tostring(NPCDiagnosticsBridge._seq))
    table.insert(parts, "t=" .. tostring(bd_round(bd_worldAge(), 3)))
    table.insert(parts, "ms=" .. tostring(bd_nowMs()))
    local fps = bd_fps()
    if fps then table.insert(parts, "fps=" .. tostring(fps)) end
    table.insert(parts, tostring(message or ""))
    bd_appendData(parts, data)

    local line = table.concat(parts, " | ")
    bd_writeFile(line, force == true)
    if bd_consoleLogEnabled() then print(line) end
end

function NPCDiagnosticsBridge.Verbose(channel, message, data, key)
    if not NPCDiagnosticsBridge.VerboseEnabled() then return end
    NPCDiagnosticsBridge.Log(channel, message, data, key, false)
end

function NPCDiagnosticsBridge.LogZombie(channel, message, zombie, brain, data, key, force)
    local out = {}
    bd_merge(out, NPCDiagnosticsBridge.DescribeZombie(zombie))
    bd_merge(out, NPCDiagnosticsBridge.DescribeBrain(brain))
    bd_merge(out, data)
    NPCDiagnosticsBridge.Log(channel, message, out, key, force)
end

local function bd_frameFingerprint(phase, zombie, brain, task)
    local z = NPCDiagnosticsBridge.DescribeZombie(zombie)
    local b = NPCDiagnosticsBridge.DescribeBrain(brain)
    local t = NPCDiagnosticsBridge.DescribeTask(task)
    return table.concat({
        tostring(phase or ""), tostring(z.actionState or ""), tostring(z.walkType or ""),
        tostring(t.taskAction or ""), tostring(t.taskState or ""), tostring(t.taskTargetId or ""),
        tostring(t.taskX or ""), tostring(t.taskY or ""), tostring(t.moveOwner or ""),
        tostring(b.state or ""), tostring(b.reason or ""), tostring(b.targetId or ""), tostring(b.activeIntent or "")
    }, ":")
end

function NPCDiagnosticsBridge.TraceNPCFrame(phase, zombie, brain, task, data, key, force)
    if not NPCDiagnosticsBridge.FullTraceEnabled() then return end
    if not zombie then return end
    local now = bd_nowMs()
    local idKey = key or bd_traceKey(zombie, brain, "npc-frame")
    local interval = bd_settingNumber("Debug_DiagnosticsNPCFrameMs", 2000, 100, 60000)
    local changeInterval = bd_settingNumber("Debug_DiagnosticsTransitionMs", 350, 0, 60000)
    local fp = bd_frameFingerprint(phase, zombie, brain, task)
    local rec = NPCDiagnosticsBridge._frame[idKey] or {}
    local changed = rec.fp ~= fp
    if force ~= true then
        local minInterval = changed and changeInterval or interval
        if rec.at and now - (tonumber(rec.at) or 0) < minInterval then return end
    end
    rec.at = now
    rec.fp = fp
    NPCDiagnosticsBridge._frame[idKey] = rec

    local out = {phase = phase, changed = changed}
    bd_merge(out, NPCDiagnosticsBridge.DescribeTask(task))
    bd_merge(out, data)
    NPCDiagnosticsBridge.LogZombie("NPC_FRAME", tostring(phase or "update"), zombie, brain, out, idKey .. ":" .. tostring(phase or "update"), force == true)
end

function NPCDiagnosticsBridge.TraceTaskTransition(zombie, brain, task, fromState, toState, reason, force)
    if not NPCDiagnosticsBridge.FullTraceEnabled() then return end
    local out = {from = fromState, to = toState, transitionReason = reason}
    bd_merge(out, NPCDiagnosticsBridge.DescribeTask(task))
    NPCDiagnosticsBridge.LogZombie("NPC_TASK", tostring(task and task.action or "task") .. " " .. tostring(fromState) .. "->" .. tostring(toState), zombie, brain, out, bd_traceKey(zombie, brain, "task") .. ":" .. tostring(task and task.action or "nil") .. ":" .. tostring(fromState) .. ":" .. tostring(toState), force == true)
end

function NPCDiagnosticsBridge.TraceMovementEvent(eventName, zombie, task, data, force)
    if not NPCDiagnosticsBridge.FullTraceEnabled() then return end
    local brain = nil
    if zombie and NPCBrainData and NPCBrainData.Get then
        local ok, value = pcall(function() return NPCBrainData.Get(zombie) end)
        if ok then brain = value end
    end
    local out = {moveEvent = eventName}
    bd_merge(out, NPCDiagnosticsBridge.DescribeTask(task))
    bd_merge(out, data)
    NPCDiagnosticsBridge.LogZombie("NPC_MOVE", tostring(eventName or "move"), zombie, brain, out, bd_traceKey(zombie, brain, "move") .. ":" .. tostring(eventName or "move"), force == true)
end

function NPCDiagnosticsBridge.TraceAppearance(eventName, zombie, brain, data, force)
    if not NPCDiagnosticsBridge.FullTraceEnabled() then return end
    local out = {appearanceEvent = eventName}
    bd_merge(out, data)
    NPCDiagnosticsBridge.LogZombie("NPC_APPEARANCE", tostring(eventName or "appearance"), zombie, brain, out, bd_traceKey(zombie, brain, "appearance") .. ":" .. tostring(eventName or "appearance"), force == true)
end

function NPCDiagnosticsBridge.TraceSpawn(eventName, data, force)
    if not NPCDiagnosticsBridge.FullTraceEnabled() then return end
    NPCDiagnosticsBridge.Log("NPC_SPAWN", tostring(eventName or "spawn"), data, "spawn:" .. tostring(eventName or "spawn") .. ":" .. tostring(data and (data.groupId or data.persistentId or data.runtimeId) or "unknown"), force == true)
end

function NPCDiagnosticsBridge.TraceWorldSnapshot(gmd, reason, force)
    if not NPCDiagnosticsBridge.FullTraceEnabled() then return end
    if type(gmd) ~= "table" then return end
    local now = bd_nowMs()
    local interval = bd_settingNumber("Debug_DiagnosticsWorldSnapshotMs", 8000, 500, 120000)
    if force ~= true and now - (tonumber(NPCDiagnosticsBridge._worldSnapshotAt) or 0) < interval then return end
    NPCDiagnosticsBridge._worldSnapshotAt = now

    local queueCount = bd_count(gmd.Queue)
    local groupCount = bd_count(gmd.VirtualGroups)
    local markerCount = bd_count(gmd.DebugMapMarkers)
    local persistentCount = bd_count(gmd.PersistentNPCs or (gmd.Registry and gmd.Registry.persistentNPCs))
    local physicalGroups = 0
    local spawningGroups = 0
    local physicalIds = 0
    if type(gmd.VirtualGroups) == "table" then
        for _, group in pairs(gmd.VirtualGroups) do
            if type(group) == "table" then
                if group.state == "physical" then physicalGroups = physicalGroups + 1 end
                if group.state == "spawning" or group.spawnPending then spawningGroups = spawningGroups + 1 end
                if type(group.physicalIds) == "table" then physicalIds = physicalIds + #group.physicalIds end
            end
        end
    end
    local data = {
        reason = reason,
        queue = queueCount,
        virtualGroups = groupCount,
        physicalGroups = physicalGroups,
        spawningGroups = spawningGroups,
        physicalIds = physicalIds,
        markers = markerCount,
        persistentNPCs = persistentCount
    }
    if type(gmd.WorldDirector) == "table" then
        data.initialized = gmd.WorldDirector.initialized
        data.lastUpdate = gmd.WorldDirector.lastUpdate
    end
    NPCDiagnosticsBridge.Log("WORLD_SNAPSHOT", tostring(reason or "snapshot"), data, "world-snapshot", force == true)
end


function NPCDiagnosticsBridge.FlushCompact(force)
    return bd_compactFlush(force == true)
end

local function bd_groupSystemTags(group)
    if type(group) ~= "table" then return nil end
    if group.counterIntelHunter == true then return "counterintel" end
    if group.convoyPhysical == true or group.convoyId then return "convoy" end
    if group.checkpointPhysical == true or group.checkpointId then return "checkpoint" end
    if group.contractPhysical == true or group.contractId then return "contract" end
    if group.leaderPhysical == true or group.leaderId then return "leader" end
    if group.mercenary == true then return "mercenary" end
    if group.roadPatrol == true then return "road_patrol" end
    if group.baseOwned == true or group.baseId then return "base_group" end
    return nil
end

local function bd_countDebugMarkers(gmd, predicate)
    local n = 0
    if type(gmd) ~= "table" or type(gmd.DebugMapMarkers) ~= "table" then return 0 end
    for _, marker in pairs(gmd.DebugMapMarkers) do
        if type(marker) == "table" and (not predicate or predicate(marker)) then n = n + 1 end
    end
    return n
end

function NPCDiagnosticsBridge.SummarizeSystems(gmd)
    local out = {
        queue = bd_count(gmd and gmd.Queue),
        virtualGroups = bd_count(gmd and gmd.VirtualGroups),
        debugMarkers = bd_count(gmd and gmd.DebugMapMarkers),
        bases = bd_count(gmd and gmd.BaseCamps),
        spyIntel = bd_count(gmd and gmd.SpyIntel),
        playerContracts = bd_count(gmd and gmd.PlayerContracts)
    }

    if type(gmd) == "table" and type(gmd.VirtualGroups) == "table" then
        out.physicalGroups = 0
        out.spawningGroups = 0
        out.physicalIds = 0
        out.counterIntelGroups = 0
        out.convoyGroups = 0
        out.checkpointGroups = 0
        out.contractGroups = 0
        out.leaderGroups = 0
        out.roadBiasedGroups = 0
        out.directRouteFallbackGroups = 0
        for _, group in pairs(gmd.VirtualGroups) do
            if type(group) == "table" then
                if group.state == "physical" or group.activated == true then out.physicalGroups = out.physicalGroups + 1 end
                if group.state == "spawning" or group.spawnPending then out.spawningGroups = out.spawningGroups + 1 end
                if type(group.physicalIds) == "table" then out.physicalIds = out.physicalIds + #group.physicalIds end
                if group.counterIntelHunter == true then out.counterIntelGroups = out.counterIntelGroups + 1 end
                if group.convoyId or group.convoyPhysical == true then out.convoyGroups = out.convoyGroups + 1 end
                if group.checkpointId or group.checkpointPhysical == true then out.checkpointGroups = out.checkpointGroups + 1 end
                if group.contractId or group.contractPhysical == true then out.contractGroups = out.contractGroups + 1 end
                if group.leaderId or group.leaderPhysical == true then out.leaderGroups = out.leaderGroups + 1 end
                if group.roadBias == true or group.preferRoads == true or group.roadPatrol == true then out.roadBiasedGroups = out.roadBiasedGroups + 1 end
                if group.roadFallback == true or group.directRouteFallback == true then out.directRouteFallbackGroups = out.directRouteFallbackGroups + 1 end
            end
        end
    end

    local radio = type(gmd) == "table" and gmd.NPCRadioInterceptBridge or nil
    if type(radio) == "table" then
        out.radioCounterIntelPlayers = bd_count(radio.counterIntel and radio.counterIntel.players)
        out.radioCounterIntelMarkers = bd_count(radio.counterIntel and radio.counterIntel.markers)
        out.radioSignals = bd_count(radio.signals or radio.active or radio.markers)
    end

    local bm = type(gmd) == "table" and gmd.NPCBlackMarketBridge or nil
    if type(bm) == "table" then
        out.blackMarketContacts = bd_count(bm.contacts)
        out.blackMarketDrops = bd_count(bm.deadDrops or bm.drops)
        out.blackMarketTrades = tonumber(bm.stats and (bm.stats.trades or bm.stats.deals)) or nil
    end
    out.blackMarketDropMarkers = bd_countDebugMarkers(gmd, function(marker) return marker.blackMarketDrop == true or marker.blackMarketDeadDrop == true end)
    out.radioStashMarkers = bd_countDebugMarkers(gmd, function(marker) return marker.radioStash == true or marker.supplyCache == true end)
    out.wantedMarkers = bd_countDebugMarkers(gmd, function(marker) return marker.wantedPlayer == true or marker.heatWanted == true end)

    local convoys = type(gmd) == "table" and gmd.NPCConvoysBridge or nil
    if type(convoys) == "table" then
        out.convoysActive = bd_count(convoys.active)
        out.convoysHistory = bd_count(convoys.history)
        out.convoyCreated = tonumber(convoys.stats and convoys.stats.created) or nil
        out.convoyRaided = tonumber(convoys.stats and convoys.stats.raided) or nil
        out.convoyEscorted = tonumber(convoys.stats and convoys.stats.escorted) or nil
    end

    local checkpoints = type(gmd) == "table" and gmd.NPCCheckpointsBridge or nil
    if type(checkpoints) == "table" then
        out.checkpoints = bd_count(checkpoints.checkpoints or checkpoints.active or checkpoints.points)
        out.checkpointTolls = tonumber(checkpoints.stats and checkpoints.stats.tolls) or nil
        out.checkpointForced = tonumber(checkpoints.stats and checkpoints.stats.forced) or nil
    end

    local intel = type(gmd) == "table" and gmd.IntelDossiers or nil
    if type(intel) == "table" then
        out.intelPlayers = bd_count(intel.players)
        out.intelBaseProbe = bd_count(intel.baseProbe)
        out.intelProgress = tonumber(intel.stats and intel.stats.progress) or nil
        out.intelGranted = tonumber(intel.stats and intel.stats.granted) or nil
        out.intelSold = tonumber(intel.stats and intel.stats.sold) or nil
        out.intelGold = tonumber(intel.stats and intel.stats.gold) or nil
    end

    local heat = type(gmd) == "table" and gmd.NPCHeatWantedBridge or nil
    if type(heat) == "table" then
        out.wantedPlayers = bd_count(heat.players)
        out.wantedEvents = tonumber(heat.stats and heat.stats.events) or nil
        out.wantedLevelUps = tonumber(heat.stats and heat.stats.levelUps) or nil
        out.wantedHeat = tonumber(heat.stats and heat.stats.heat) or nil
    end

    local hunters = type(gmd) == "table" and gmd.NPCCounterIntelHunterServerBridge or type(gmd) == "table" and gmd.CounterIntelHunters or nil
    if type(hunters) == "table" then
        out.hunterPlayers = bd_count(hunters.players)
        out.hunterSpawned = tonumber(hunters.stats and hunters.stats.spawned) or nil
        out.hunterMaterialized = tonumber(hunters.stats and hunters.stats.materialized) or nil
    end

    local leaders = type(gmd) == "table" and gmd.NPCLeadersBridge or nil
    if type(leaders) == "table" then
        out.leaders = bd_count(leaders.leaders)
        out.leaderDeaths = tonumber(leaders.stats and leaders.stats.killed) or nil
    end

    return out
end

function NPCDiagnosticsBridge.LogSystemSnapshot(gmd, reason, force)
    if not NPCDiagnosticsBridge.Enabled() then return end
    if not bd_settingBool("Debug_DiagnosticsSystemSnapshot", true) then return end
    if type(gmd) ~= "table" then return end
    local now = bd_nowMs()
    local interval = bd_settingNumber("Debug_DiagnosticsSystemSnapshotMs", 30000, 1000, 600000)
    if force ~= true and now - (tonumber(NPCDiagnosticsBridge._systemSnapshotAt) or 0) < interval then return end
    NPCDiagnosticsBridge._systemSnapshotAt = now
    local data = NPCDiagnosticsBridge.SummarizeSystems(gmd)
    data.reason = reason or "periodic"
    NPCDiagnosticsBridge.Log("SYSTEMS", tostring(reason or "snapshot"), data, "systems-snapshot", force == true)
end

function NPCDiagnosticsBridge.LogRiskAction(systemName, actionName, data, key, force)
    if not NPCDiagnosticsBridge.Enabled() then return end
    if not bd_settingBool("Debug_DiagnosticsRiskActions", true) then return end
    local sys = tostring(systemName or "system")
    local action = tostring(actionName or "action")
    local out = {system=sys, action=action}
    bd_merge(out, data)
    NPCDiagnosticsBridge.Log("RISK_ACTION", sys .. ":" .. action, out, key or ("risk:" .. sys .. ":" .. action), force == true)
end

local function bd_isOnScreen(chr)
    if not chr then return false end
    if chr.isOnScreen then
        local ok, value = pcall(function() return chr:isOnScreen() end)
        if ok and value ~= nil then return value == true end
    end
    local player = getPlayer and getPlayer() or nil
    if not player then return false end
    local x = bd_call(chr, "getX")
    local y = bd_call(chr, "getY")
    local px = bd_call(player, "getX")
    local py = bd_call(player, "getY")
    if not (x and y and px and py) then return false end
    local dx = tonumber(x) - tonumber(px)
    local dy = tonumber(y) - tonumber(py)
    local radius = bd_settingNumber("Debug_DiagnosticsVisibleNPCRadius", 45, 8, 160)
    return dx * dx + dy * dy <= radius * radius
end

function NPCDiagnosticsBridge.TraceVisibleMaterializedNPC(phase, zombie, brain, task, data, force)
    if not NPCDiagnosticsBridge.Enabled() then return end
    if not bd_settingBool("Debug_DiagnosticsVisibleNPC", false) then return end
    if not bd_isOnScreen(zombie) then return end
    local idKey = bd_traceKey(zombie, brain, "visible-npc")
    local fp = bd_frameFingerprint(phase or "visible", zombie, brain, task)
    local now = bd_nowMs()
    local state = NPCDiagnosticsBridge._visibleFrame[idKey] or {}
    local changed = state.fp ~= fp
    local interval = bd_settingNumber("Debug_DiagnosticsVisibleNPCMs", 10000, 1000, 60000)
    if force ~= true and not changed and now - (tonumber(state.last) or 0) < interval then return end
    NPCDiagnosticsBridge._visibleFrame[idKey] = {fp=fp, last=now}
    local out = {phase=phase or "visible", visibleStateChanged=changed}
    bd_merge(out, NPCDiagnosticsBridge.DescribeZombie(zombie))
    bd_merge(out, NPCDiagnosticsBridge.DescribeBrain(brain))
    bd_merge(out, NPCDiagnosticsBridge.DescribeTask(task))
    bd_merge(out, data)
    NPCDiagnosticsBridge.Log("VISIBLE_NPC", tostring(phase or "update"), out, idKey, force == true or changed)
end

local function bd_installFlushHook()
    if NPCDiagnosticsBridge._flushHookInstalled then return end
    NPCDiagnosticsBridge._flushHookInstalled = true
    if Events and Events.OnTick then
        Events.OnTick.Add(function(tick)
            if (tonumber(tick) or 0) % 120 == 0 then
                if NPCDiagnosticsBridge and NPCDiagnosticsBridge.FlushCompact then NPCDiagnosticsBridge.FlushCompact(false) end
                if NPCDiagnosticsBridge and NPCDiagnosticsBridge.FlushDroppedSummary then NPCDiagnosticsBridge.FlushDroppedSummary(false) end
                if GetNPCModData and NPCDiagnosticsBridge and NPCDiagnosticsBridge.LogSystemSnapshot then
                    local ok, gmd = pcall(GetNPCModData)
                    if ok and type(gmd) == "table" then NPCDiagnosticsBridge.LogSystemSnapshot(gmd, "tick", false) end
                end
            end
        end)
    end
    if Events and Events.EveryTenMinutes then
        Events.EveryTenMinutes.Add(function()
            if NPCDiagnosticsBridge and NPCDiagnosticsBridge.FlushCompact then NPCDiagnosticsBridge.FlushCompact(true) end
            if GetNPCModData and NPCDiagnosticsBridge and NPCDiagnosticsBridge.LogSystemSnapshot then
                local ok, gmd = pcall(GetNPCModData)
                if ok and type(gmd) == "table" then NPCDiagnosticsBridge.LogSystemSnapshot(gmd, "ten_minutes", true) end
            end
        end)
    end
end

bd_installFlushHook()

function NPCDiagnosticsBridge.FlushDroppedSummary(force)
    local budget = NPCDiagnosticsBridge._fileBudget
    local dropped = tonumber(budget.dropped) or 0
    if dropped <= 0 then return end
    budget.dropped = 0
    NPCDiagnosticsBridge.Log("DIAGNOSTICS", "dropped diagnostic lines by budget", {dropped=dropped, maxPerSecond=bd_settingNumber("Debug_DiagnosticsMaxLinesPerSecond", 35, 1, 2000)}, "diag-dropped", force == true)
end
