-- Neutral server command bridge.
-- Compatibility facade: media/lua/server/legacy client-command facade

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCLegacyGlobalsBridge"
NPCServerCommandBridge = NPCServerCommandBridge or {}
NPCServerCommandBridge.Version = 1

function NPCServerCommandBridge.NormalizeModule(module)
    if module == "NPCCommands" then return "Commands" end
    if module == "NPCPlayers" then return "Players" end
    if NPCLegacyContractBridge.IsModule(module, "NPCSim", "sim") then return "NPCSim" end
    return module
end

function NPCServerCommandBridge.OutboundModule(module)
    if module == "Commands" then return "NPCCommands" end
    if module == "Players" then return "NPCPlayers" end
    if NPCLegacyContractBridge.IsModule(module, "NPCSim", "sim") then return "NPCSim" end
    if NPCLegacyContractBridge.IsModule(module, "NPCDebugMap", "debugMap") then return "NPCDebugMap" end
    if NPCLegacyContractBridge.IsModule(module, "NPCEffects", "effects") then return "NPCEffects" end
    return module
end

function NPCServerCommandBridge.EnsureNetGuard(serverTable)
    local server = serverTable or NPCServerRuntime or NPCLegacyGlobalsBridge.Get("ServerRuntime") or {}
    server.NetGuard = server.NetGuard or {last={}, dropped=0, lastPrune=0}
    server.NetGuard.last = server.NetGuard.last or {}
    server.NetGuard.dropped = tonumber(server.NetGuard.dropped) or 0
    server.NetGuard.lastPrune = tonumber(server.NetGuard.lastPrune) or 0
    return server.NetGuard
end

function NPCServerCommandBridge.PlayerId(player)
    if not player then return nil end
    if NPCUtils and NPCUtils.GetCharacterID then
        local ok, id = pcall(function() return NPCUtils.GetCharacterID(player) end)
        if ok and id ~= nil then return id end
    end
    if player.getOnlineID then
        local ok, id = pcall(function() return player:getOnlineID() end)
        if ok and id ~= nil then return id end
    end
    return nil
end

function NPCServerCommandBridge.Say(player, text)
    if player and player.Say and text then
        pcall(function() player:Say(text) end)
    end
end

function NPCServerCommandBridge.LogMercenary(text)
    print("[NPCMercenary] " .. tostring(text or ""))
end

function NPCServerCommandBridge.SendMercenaryHireResult(player, ok, message, args)
    local payload = {}
    if type(args) == "table" then
        for k, v in pairs(args) do payload[k] = v end
    end
    payload.ok = ok == true
    payload.message = message
    if sendServerCommand then
        sendServerCommand(player, 'NPCCommands', 'MercenaryHireResult', payload)
    end
end

function NPCServerCommandBridge.NowMs()
    if getTimestampMs then
        local ok, value = pcall(function() return getTimestampMs() end)
        if ok and value then return tonumber(value) or 0 end
    end
    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then
            local ok, value = pcall(function() return gt:getWorldAgeHours() end)
            if ok and value then return math.floor((tonumber(value) or 0) * 3600000) end
        end
    end
    return os.time() * 1000
end

function NPCServerCommandBridge.SettingBool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        return NPCLegacySettingsBridge.GetBool(name, defaultValue == true)
    end
    return defaultValue == true
end

function NPCServerCommandBridge.SettingNumber(name, defaultValue, minValue, maxValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        return NPCLegacySettingsBridge.GetNumber(name, defaultValue, minValue, maxValue)
    end
    local value = tonumber(defaultValue) or 0
    if minValue ~= nil and value < minValue then value = minValue end
    if maxValue ~= nil and value > maxValue then value = maxValue end
    return value
end

function NPCServerCommandBridge.SafeString(value, maxLen)
    if value == nil then return nil end
    value = tostring(value)
    maxLen = tonumber(maxLen) or 160
    if string.len(value) > maxLen then return string.sub(value, 1, maxLen) end
    return value
end

function NPCServerCommandBridge.SanitizeValue(value, depth, maxDepth, maxFields, maxString)
    local vt = type(value)
    if vt == "nil" or vt == "boolean" then return value end
    if vt == "number" then
        if value ~= value then return 0 end
        if value > 1000000000 then return 1000000000 end
        if value < -1000000000 then return -1000000000 end
        return value
    end
    if vt == "string" then return NPCServerCommandBridge.SafeString(value, maxString) end
    if vt ~= "table" then return nil end
    if depth >= maxDepth then return nil end

    local out = {}
    local count = 0
    for k, v in pairs(value) do
        count = count + 1
        if count > maxFields then break end
        local kt = type(k)
        if kt == "string" or kt == "number" then
            local key = k
            if kt == "string" then key = NPCServerCommandBridge.SafeString(k, 64) end
            out[key] = NPCServerCommandBridge.SanitizeValue(v, depth + 1, maxDepth, maxFields, maxString)
        end
    end
    return out
end

function NPCServerCommandBridge.SanitizeArgs(args, module, command)
    module = NPCServerCommandBridge.NormalizeModule(module)
    if type(args) ~= "table" then return {} end
    local maxFields = NPCServerCommandBridge.SettingNumber("Net_MaxClientCommandFields", 120, 16, 1000)
    local maxString = NPCServerCommandBridge.SettingNumber("Net_MaxClientStringBytes", 160, 32, 1000)
    local maxDepth = NPCServerCommandBridge.SettingNumber("Net_MaxClientPayloadDepth", 4, 1, 8)
    if module == "Commands" and command == "SpawnRestore" then
        maxFields = math.max(maxFields, 360)
        maxString = math.max(maxString, 256)
        maxDepth = math.max(maxDepth, 6)
    elseif module == "Commands" and command == "SpawnGroup" then
        maxFields = math.max(maxFields, 220)
        maxString = math.max(maxString, 220)
    elseif module == "NPCSim" and command == "StateUpdate" then
        maxFields = math.max(maxFields, 180)
    end
    local clean = NPCServerCommandBridge.SanitizeValue(args, 0, maxDepth, maxFields, maxString)
    if type(clean) ~= "table" then return {} end
    return clean
end

function NPCServerCommandBridge.CommandCooldownMs(module, command, args)
    module = NPCServerCommandBridge.NormalizeModule(module)
    local base = NPCServerCommandBridge.SettingNumber("Net_ClientCommandMinIntervalMs", 40, 0, 5000)
    if module == "NPCSim" and command == "StateUpdate" then
        return NPCServerCommandBridge.SettingNumber("Net_StateUpdateMinIntervalMs", 180, 0, 5000)
    end
    if module == "Players" and command == "PlayerUpdate" then
        return NPCServerCommandBridge.SettingNumber("Net_PlayerUpdateMinIntervalMs", 500, 0, 10000)
    end
    if module == "Commands" and command == "DebugMapRequest" then
        return NPCServerCommandBridge.SettingNumber("Net_DebugMapRequestCooldownSeconds", 6.0, 0, 120) * 1000
    end
    if module == "Commands" and command == "DebugMapMaterializeNear" then
        return NPCServerCommandBridge.SettingNumber("Net_DebugMapMaterializeCooldownMs", 1200, 250, 30000)
    end
    if module == "Commands" and (command == "MercenaryGroupOrder" or command == "HireMercenaryGroup" or command == "SwitchProgram" or command == "BribeSpy" or command == "TakePrisoner" or command == "InterrogatePrisoner" or command == "ReleasePrisoner") then
        return NPCServerCommandBridge.SettingNumber("Net_OrderCommandMinIntervalMs", 250, 0, 10000)
    end
    if module == "Players" and command == "SetFaction" then
        return math.max(base, NPCServerCommandBridge.SettingNumber("Net_OrderCommandMinIntervalMs", 250, 0, 10000))
    end
    if module == "Commands" and (command == "SpawnGroup" or command == "SpawnRestore" or command == "VehicleSpawn") then
        return NPCServerCommandBridge.SettingNumber("Net_SpawnCommandCooldownSeconds", 2.0, 0, 120) * 1000
    end
    return base
end

function NPCServerCommandBridge.PruneNetGuard(serverTable, now)
    local guard = NPCServerCommandBridge.EnsureNetGuard(serverTable)
    now = tonumber(now) or NPCServerCommandBridge.NowMs()
    if now - (tonumber(guard.lastPrune) or 0) < 60000 then return end

    local staleMs = 600000
    for key, last in pairs(guard.last) do
        if now - (tonumber(last) or 0) > staleMs then
            guard.last[key] = nil
        end
    end
    guard.lastPrune = now
end

function NPCServerCommandBridge.RateLimitKey(module, command, player, args)
    module = NPCServerCommandBridge.NormalizeModule(module)
    local key = tostring(NPCServerCommandBridge.PlayerId(player) or "unknown") .. ":" .. tostring(module) .. ":" .. tostring(command)
    if module == "NPCSim" and command == "StateUpdate" and args and args.id then
        key = key .. ":" .. tostring(args.id)
    elseif module == "Commands" and (command == "HireMercenaryGroup" or command == "MercenaryGroupOrder") and args then
        key = key .. ":" .. tostring(args.id or args.runtimeId or args.persistentId or args.groupId or "")
    elseif module == "Commands" and command == "DebugMapMaterializeNear" and args and args.markerId then
        key = key .. ":" .. tostring(args.markerId)
    elseif module == "Commands" and command == "VehiclePartDamage" and args then
        key = key .. ":" .. tostring(args.x or "") .. ":" .. tostring(args.y or "") .. ":" .. tostring(args.id or "")
    end
    return key
end

function NPCServerCommandBridge.CommandAllowed(serverTable, module, command, player, args)
    module = NPCServerCommandBridge.NormalizeModule(module)
    if not NPCServerCommandBridge.SettingBool("Net_ClientCommandRateLimit", true) then return true end
    local cooldown = NPCServerCommandBridge.CommandCooldownMs(module, command, args)
    if cooldown <= 0 then return true end

    local guard = NPCServerCommandBridge.EnsureNetGuard(serverTable)
    local key = NPCServerCommandBridge.RateLimitKey(module, command, player, args)
    local now = NPCServerCommandBridge.NowMs()
    NPCServerCommandBridge.PruneNetGuard(serverTable, now)

    local last = tonumber(guard.last[key]) or -999999999
    if now - last < cooldown then
        guard.dropped = (tonumber(guard.dropped) or 0) + 1
        if NPCServerCommandBridge.SettingBool("Net_LogDroppedCommands", false) then
            print("[NPCServer] dropped throttled command " .. tostring(module) .. "." .. tostring(command) .. " from " .. tostring(NPCServerCommandBridge.PlayerId(player)))
        end
        return false
    end
    guard.last[key] = now
    return true
end
