-- NPCDisguiseBridge.lua
-- Lightweight faction-disguise layer. Keeps the real player faction untouched and only changes perceived side.

NPCDisguiseBridge = NPCDisguiseBridge or {}

local function bd_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        local ok, value = pcall(function() return NPCLegacySettingsBridge.GetBool(name, defaultValue == true) end)
        if ok and value ~= nil then return value == true end
    end
    return defaultValue == true
end

local function bd_num(name, defaultValue, minValue, maxValue)
    local value = defaultValue
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        local ok, got = pcall(function() return NPCLegacySettingsBridge.GetNumber(name, defaultValue, minValue, maxValue) end)
        if ok and got ~= nil then value = got end
    end
    value = tonumber(value) or tonumber(defaultValue) or 0
    if minValue ~= nil and value < minValue then value = minValue end
    if maxValue ~= nil and value > maxValue then value = maxValue end
    return value
end

local function bd_now()
    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then
            local ok, value = pcall(function() return gt:getWorldAgeHours() end)
            if ok and value then return tonumber(value) or 0 end
        end
    end
    return os.time and (os.time() / 3600) or 0
end

local function bd_side(side)
    if NPCFactionBridge and NPCFactionBridge.NormalizeSide then
        return NPCFactionBridge.NormalizeSide(side)
    end
    side = tostring(side or ""):lower()
    if side == "red" or side == "green" or side == "blue" or side == "black" then return side end
    return nil
end

local function bd_playerId(player)
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

local function bd_playerName(player)
    if not player then return nil end
    if player.getUsername then
        local ok, name = pcall(function() return player:getUsername() end)
        if ok and name then return tostring(name) end
    end
    if player.getDisplayName then
        local ok, name = pcall(function() return player:getDisplayName() end)
        if ok and name then return tostring(name) end
    end
    return nil
end

local function bd_copyRecord(rec)
    if type(rec) ~= "table" then return nil end
    local out = {}
    for k, v in pairs(rec) do out[k] = v end
    return out
end

local function bd_getOnlineRecord(id)
    if id == nil then return nil end
    local gmd = GetNPCModDataPlayers and GetNPCModDataPlayers() or nil
    local online = gmd and gmd.OnlinePlayers or nil
    if type(online) ~= "table" then return nil end
    return online[id] or online[tostring(id)]
end

function NPCDisguiseBridge.IsEnabled()
    return bd_bool("Disguise_Enabled", true)
end

function NPCDisguiseBridge.DurationHours()
    return bd_num("Disguise_DurationMinutes", 180, 1, 10080) / 60
end

function NPCDisguiseBridge.CompromiseHours()
    return bd_num("Disguise_CompromiseMinutes", 120, 1, 10080) / 60
end

function NPCDisguiseBridge.InspectChance()
    return bd_num("Disguise_InspectChance", 35, 0, 100)
end

function NPCDisguiseBridge.CloseInspectRadius()
    return bd_num("Disguise_CloseInspectRadius", 6, 1, 40)
end

function NPCDisguiseBridge.NormalizeSide(side)
    return bd_side(side)
end

function NPCDisguiseBridge.GetPlayerRecord(player)
    if not NPCDisguiseBridge.IsEnabled() or not player then return nil end
    local now = bd_now()
    local md = player.getModData and player:getModData() or nil
    local rec = md and md.NPCDisguiseBridge or nil

    if type(rec) ~= "table" then
        local online = bd_getOnlineRecord(bd_playerId(player))
        if type(online) == "table" and type(online.disguise) == "table" then
            rec = bd_copyRecord(online.disguise)
        elseif type(online) == "table" and online.disguiseSide then
            rec = {
                side = online.disguiseSide,
                expiresAt = online.disguiseExpiresAt,
                compromised = online.disguiseCompromised,
                compromisedUntil = online.disguiseCompromisedUntil,
                reason = online.disguiseReason,
                updatedAt = online.disguiseUpdatedAt
            }
        end
    end

    if type(rec) ~= "table" then return nil end
    rec.side = bd_side(rec.side)
    if not rec.side then return nil end
    if rec.expiresAt and now >= tonumber(rec.expiresAt) then return nil end
    if rec.compromised == true then
        if not rec.compromisedUntil or now < tonumber(rec.compromisedUntil) then return rec end
        rec.compromised = false
        rec.compromisedUntil = nil
        if md then md.NPCDisguiseBridge = rec end
    end
    return rec
end

function NPCDisguiseBridge.GetPlayerDisguiseSide(player)
    local rec = NPCDisguiseBridge.GetPlayerRecord(player)
    if not rec or rec.compromised == true then return nil end
    return bd_side(rec.side)
end

function NPCDisguiseBridge.IsCompromised(player)
    local rec = NPCDisguiseBridge.GetPlayerRecord(player)
    return rec and rec.compromised == true or false
end

function NPCDisguiseBridge.GetPlayerPerceivedSide(player, observerBrain)
    local disguiseSide = NPCDisguiseBridge.GetPlayerDisguiseSide(player)
    if disguiseSide then return disguiseSide end
    return nil
end

function NPCDisguiseBridge.CanPassAsSide(player, side)
    side = bd_side(side)
    local disguiseSide = NPCDisguiseBridge.GetPlayerDisguiseSide(player)
    return side ~= nil and disguiseSide ~= nil and side == disguiseSide
end

function NPCDisguiseBridge.BuildPayload(player, rec)
    rec = rec or NPCDisguiseBridge.GetPlayerRecord(player)
    return {
        id = bd_playerId(player),
        name = bd_playerName(player),
        side = rec and rec.side or nil,
        expiresAt = rec and rec.expiresAt or nil,
        reason = rec and rec.reason or nil,
        compromised = rec and rec.compromised == true or false,
        compromisedUntil = rec and rec.compromisedUntil or nil,
        updatedAt = rec and rec.updatedAt or bd_now()
    }
end

function NPCDisguiseBridge.SetPlayerDisguise(player, side, reason, durationHours, silent)
    if not player then return nil end
    side = bd_side(side)
    local md = player.getModData and player:getModData() or nil
    local now = bd_now()

    if not side then
        if md then md.NPCDisguiseBridge = nil end
        if isClient and isClient() and sendClientCommand then
            sendClientCommand(player, 'NPCDisguise', 'SetDisguise', NPCDisguiseBridge.BuildPayload(player, nil))
        end
        if not silent and player.Say then pcall(function() player:Say("Disguise removed.") end) end
        return nil
    end

    local rec = {
        side = side,
        reason = reason or "manual",
        expiresAt = now + (tonumber(durationHours) or NPCDisguiseBridge.DurationHours()),
        compromised = false,
        compromisedUntil = nil,
        updatedAt = now
    }
    if md then md.NPCDisguiseBridge = rec end

    if isClient and isClient() and sendClientCommand then
        sendClientCommand(player, 'NPCDisguise', 'SetDisguise', NPCDisguiseBridge.BuildPayload(player, rec))
    end

    if not silent and player.Say then
        local label = NPCFactionBridge and NPCFactionBridge.GetSideLabel and NPCFactionBridge.GetSideLabel(side) or tostring(side)
        pcall(function() player:Say("Disguised as " .. tostring(label) .. ".") end)
    end
    return rec
end

function NPCDisguiseBridge.ApplyServerPayload(player, args)
    if not player or type(args) ~= "table" then return nil end
    local side = bd_side(args.side or args.disguiseSide)
    local md = player.getModData and player:getModData() or nil
    if not side then
        if md then md.NPCDisguiseBridge = nil end
        return nil
    end
    local rec = {
        side = side,
        reason = args.reason or args.disguiseReason,
        expiresAt = tonumber(args.expiresAt or args.disguiseExpiresAt),
        compromised = args.compromised == true or args.disguiseCompromised == true,
        compromisedUntil = tonumber(args.compromisedUntil or args.disguiseCompromisedUntil),
        updatedAt = tonumber(args.updatedAt or args.disguiseUpdatedAt) or bd_now()
    }
    if md then md.NPCDisguiseBridge = rec end
    return rec
end

function NPCDisguiseBridge.Compromise(player, reason, sourceSide, silent)
    if not player then return nil end
    local rec = NPCDisguiseBridge.GetPlayerRecord(player)
    if not rec or not rec.side then return nil end
    local now = bd_now()
    rec.compromised = true
    rec.compromisedReason = reason or "compromised"
    rec.compromisedBySide = bd_side(sourceSide)
    rec.compromisedUntil = now + NPCDisguiseBridge.CompromiseHours()
    rec.updatedAt = now

    local md = player.getModData and player:getModData() or nil
    if md then md.NPCDisguiseBridge = rec end

    if isClient and isClient() and sendClientCommand then
        sendClientCommand(player, 'NPCDisguise', 'SetDisguise', NPCDisguiseBridge.BuildPayload(player, rec))
    elseif isServer and isServer() and NPCDisguiseServerBridge and NPCDisguiseServerBridge.SetDisguise then
        pcall(function() NPCDisguiseServerBridge.SetDisguise(player, NPCDisguiseBridge.BuildPayload(player, rec)) end)
    end

    if not silent and player.Say then pcall(function() player:Say("Disguise compromised!") end) end
    return rec
end

function NPCDisguiseBridge.RollInspection(player, checkpointSide)
    if not player then return false end
    if not NPCDisguiseBridge.CanPassAsSide(player, checkpointSide) then return false end
    local chance = NPCDisguiseBridge.InspectChance()
    if chance <= 0 then return true end
    local roll = ZombRand and ZombRand(100) or math.random(0, 99)
    if roll < chance then
        NPCDisguiseBridge.Compromise(player, "checkpoint_inspection", checkpointSide)
        return false
    end
    return true
end
