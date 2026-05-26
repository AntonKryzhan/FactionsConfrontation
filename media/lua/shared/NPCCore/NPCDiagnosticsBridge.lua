require "NPCCore/NPCLegacySettingsBridge"
require "NPCCore/NPCLegacyContractBridge"

NPCDiagnosticsBridge = NPCDiagnosticsBridge or {}
NPCDiagnosticsBridge._last = NPCDiagnosticsBridge._last or {}
NPCDiagnosticsBridge._seq = NPCDiagnosticsBridge._seq or 0

local NPC_DIAGNOSTICS_LEGACY_KEYS = {
    liveFlag = NPCLegacyContractBridge.Key("FLAG"),
    formerNPCZombie = NPCLegacyContractBridge.Key("FORMER_ZOMBIE"),
    runtimeId = NPCLegacyContractBridge.Key("RUNTIME_ID"),
    persistentId = NPCLegacyContractBridge.Key("PERSISTENT_ID"),
    worldGroupId = NPCLegacyContractBridge.Key("WORLD_GROUP_ID"),
    mdFlag = NPCLegacyContractBridge.Key("IS_FLAG")
}
local NPC_DIAGNOSTICS_LOG_PREFIX = "[NPCDiag]"

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

local function bd_count(t)
    local n = 0
    if type(t) == "table" then
        for _, _ in pairs(t) do n = n + 1 end
    end
    return n
end

local function bd_value(value)
    if value == nil then return "nil" end
    local vt = type(value)
    if vt == "table" then return "table" end
    if vt == "boolean" then return value and "true" or "false" end
    local s = tostring(value)
    if string.len(s) > 96 then s = string.sub(s, 1, 96) .. "..." end
    return s
end

local function bd_appendData(parts, data)
    if type(data) ~= "table" then return end
    for k, v in pairs(data) do
        table.insert(parts, tostring(k) .. "=" .. bd_value(v))
    end
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
    if not (chr and method) then return nil end
    local ok, value = pcall(function() return chr[method](chr) end)
    if ok then return value end
    return nil
end

local function bd_var(chr, name)
    if not (chr and name) then return nil end
    local ok, value = pcall(function() return chr:getVariableString(name) end)
    if ok and value and value ~= "" then return value end
    local okBool, valueBool = pcall(function() return chr:getVariableBoolean(name) end)
    if okBool and valueBool ~= nil then return valueBool end
    return nil
end

function NPCDiagnosticsBridge.Enabled()
    return bd_settingBool("Debug_DiagnosticsLog", true)
end

function NPCDiagnosticsBridge.VerboseEnabled()
    return bd_settingBool("Debug_DiagnosticsVerbose", false)
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

    return {
        id = brain.id,
        uid = brain.uid,
        persistentId = brain.persistentId,
        groupId = brain.worldGroupId or brain.groupId,
        program = programName,
        stage = programStage,
        health = brain.health,
        infection = brain.infection,
        state = state,
        order = order,
        dead = brain.dead
    }
end

function NPCDiagnosticsBridge.DescribeZombie(zombie)
    if not zombie then return {} end
    local md = nil
    local ok, modData = pcall(function() return zombie:getModData() end)
    if ok then md = modData end
    local x = bd_call(zombie, "getX")
    local y = bd_call(zombie, "getY")
    local z = bd_call(zombie, "getZ")
    return {
        charId = bd_characterId(zombie),
        x = x and math.floor((tonumber(x) or 0) * 10) / 10 or nil,
        y = y and math.floor((tonumber(y) or 0) * 10) / 10 or nil,
        z = z,
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
        useless = bd_call(zombie, "isUseless")
    }
end

function NPCDiagnosticsBridge.Log(channel, message, data, key, force)
    if not NPCDiagnosticsBridge.Enabled() then return end

    key = key or tostring(channel) .. ":" .. tostring(message)
    if not force then
        local rateMs = bd_settingNumber("Debug_DiagnosticsRateMs", 5000, 0, 60000)
        if rateMs > 0 then
            local now = bd_nowMs()
            local last = NPCDiagnosticsBridge._last[key]
            if last ~= nil and now - (tonumber(last) or 0) < rateMs then return end
            NPCDiagnosticsBridge._last[key] = now
        end
    end

    NPCDiagnosticsBridge._seq = (tonumber(NPCDiagnosticsBridge._seq) or 0) + 1

    local parts = {}
    table.insert(parts, NPC_DIAGNOSTICS_LOG_PREFIX)
    table.insert(parts, "[" .. bd_side() .. "]")
    table.insert(parts, "[" .. tostring(channel or "General") .. "]")
    table.insert(parts, "#" .. tostring(NPCDiagnosticsBridge._seq))
    table.insert(parts, "t=" .. tostring(math.floor(bd_worldAge() * 1000) / 1000))
    table.insert(parts, tostring(message or ""))
    bd_appendData(parts, data)

    print(table.concat(parts, " "))
end

function NPCDiagnosticsBridge.Verbose(channel, message, data, key)
    if not NPCDiagnosticsBridge.VerboseEnabled() then return end
    NPCDiagnosticsBridge.Log(channel, message, data, key, false)
end

local function bd_merge(out, data)
    if type(data) ~= "table" then return end
    for k, v in pairs(data) do
        out[k] = v
    end
end

function NPCDiagnosticsBridge.LogZombie(channel, message, zombie, brain, data, key, force)
    local out = {}
    bd_merge(out, NPCDiagnosticsBridge.DescribeZombie(zombie))
    bd_merge(out, NPCDiagnosticsBridge.DescribeBrain(brain))
    bd_merge(out, data)
    NPCDiagnosticsBridge.Log(channel, message, out, key, force)
end
