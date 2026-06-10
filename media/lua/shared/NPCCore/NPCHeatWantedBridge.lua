-- NPCHeatWantedBridge.lua
-- Unified player heat / wanted layer for espionage, black-market and counterintelligence loops.
-- Additive facade: keeps existing bounty and radio counterintel systems intact and feeds them through small hooks.

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCLegacySettingsBridge"

NPCHeatWantedBridge = NPCHeatWantedBridge or {}
NPCHeatWantedBridge.Version = 1

local HW_SIDES = {red=true, green=true, blue=true, black=true}
local HW_LEVEL_NAMES = {
    [0] = "clean",
    [1] = "suspicious",
    [2] = "flagged",
    [3] = "wanted",
    [4] = "hunted",
    [5] = "kill_on_sight"
}

local function hw_num(name, defaultValue, minValue, maxValue)
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

local function hw_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        local ok, got = pcall(function() return NPCLegacySettingsBridge.GetBool(name, defaultValue == true) end)
        if ok and got ~= nil then return got == true end
    end
    return defaultValue == true
end

local function hw_now()
    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then
            local ok, value = pcall(function() return gt:getWorldAgeHours() end)
            if ok and value then return tonumber(value) or 0 end
        end
    end
    return os.time and ((os.time() or 0) / 3600) or 0
end

local function hw_clamp(value, minValue, maxValue)
    value = tonumber(value) or 0
    if minValue ~= nil and value < minValue then return minValue end
    if maxValue ~= nil and value > maxValue then return maxValue end
    return value
end

local function hw_hasTableEntries(value)
    if type(value) ~= "table" then return false end
    for _ in pairs(value) do return true end
    return false
end

local function hw_side(value)
    if NPCFactionBridge and NPCFactionBridge.NormalizeSide then
        local ok, got = pcall(function() return NPCFactionBridge.NormalizeSide(value) end)
        if ok and got then return got end
    end
    value = tostring(value or ""):lower()
    if value == "black_market" or value == "market" then return "black" end
    if HW_SIDES[value] then return value end
    return nil
end

local function hw_sideLabel(side)
    side = hw_side(side) or tostring(side or "")
    if NPCFactionBridge and NPCFactionBridge.GetSideLabel then
        local ok, label = pcall(function() return NPCFactionBridge.GetSideLabel(side) end)
        if ok and label then return tostring(label) end
    end
    if side == "red" then return "Red" end
    if side == "green" then return "Green" end
    if side == "black" then return "Black Market" end
    if side == "blue" then return "Blue" end
    return tostring(side or "Unknown")
end

local function hw_playerId(player)
    if not player then return nil end
    if NPCUtils and NPCUtils.GetCharacterID then
        local ok, id = pcall(function() return NPCUtils.GetCharacterID(player) end)
        if ok and id ~= nil then return tostring(id) end
    end
    if player.getOnlineID then
        local ok, id = pcall(function() return player:getOnlineID() end)
        if ok and id ~= nil then return tostring(id) end
    end
    if player.getUsername then
        local ok, name = pcall(function() return player:getUsername() end)
        if ok and name then return tostring(name) end
    end
    return nil
end

local function hw_playerName(player)
    if not player then return "player" end
    if player.getUsername then
        local ok, name = pcall(function() return player:getUsername() end)
        if ok and name and tostring(name) ~= "" then return tostring(name) end
    end
    if player.getDisplayName then
        local ok, name = pcall(function() return player:getDisplayName() end)
        if ok and name and tostring(name) ~= "" then return tostring(name) end
    end
    return tostring(hw_playerId(player) or "player")
end

function NPCHeatWantedBridge.IsEnabled()
    return hw_bool("HeatWanted_Enabled", true)
end

function NPCHeatWantedBridge.NotifyEnabled()
    return hw_bool("HeatWanted_NotifyLevelChanges", true)
end

function NPCHeatWantedBridge.MarkerEnabled()
    return hw_bool("HeatWanted_MarkerEnabled", true)
end

function NPCHeatWantedBridge.MarkerMinLevel()
    return math.floor(hw_num("HeatWanted_MarkerMinLevel", 3, 0, 5))
end

function NPCHeatWantedBridge.DecayPerDay()
    return hw_num("HeatWanted_DecayPerDay", 8, 0, 500)
end

function NPCHeatWantedBridge.MaxHeat()
    return hw_num("HeatWanted_MaxHeat", 150, 10, 999)
end

function NPCHeatWantedBridge.CounterIntelScale()
    return hw_num("HeatWanted_CounterIntelScale", 0.45, 0, 5)
end

function NPCHeatWantedBridge.BountyBridgeEnabled()
    return hw_bool("HeatWanted_FactionBountyBridgeEnabled", true)
end

function NPCHeatWantedBridge.BountyMultiplier()
    return hw_num("HeatWanted_BountyMultiplier", 0.35, 0, 10)
end

function NPCHeatWantedBridge.BountyMinLevel()
    return math.floor(hw_num("HeatWanted_BountyMinLevel", 3, 0, 5))
end

function NPCHeatWantedBridge.LevelThreshold(level)
    level = math.floor(tonumber(level) or 0)
    if level <= 1 then return hw_num("HeatWanted_Level1Threshold", 15, 1, 999) end
    if level == 2 then return hw_num("HeatWanted_Level2Threshold", 35, 1, 999) end
    if level == 3 then return hw_num("HeatWanted_Level3Threshold", 60, 1, 999) end
    if level == 4 then return hw_num("HeatWanted_Level4Threshold", 90, 1, 999) end
    return hw_num("HeatWanted_Level5Threshold", 125, 1, 999)
end

function NPCHeatWantedBridge.LevelName(level)
    return HW_LEVEL_NAMES[math.floor(tonumber(level) or 0)] or HW_LEVEL_NAMES[0]
end

function NPCHeatWantedBridge.LevelForHeat(value)
    value = tonumber(value) or 0
    local level = 0
    for i = 1, 5 do
        if value >= NPCHeatWantedBridge.LevelThreshold(i) then level = i end
    end
    return level
end

function NPCHeatWantedBridge.EnsureData(gmd)
    if not gmd then return nil end
    gmd.NPCHeatWantedBridge = gmd.NPCHeatWantedBridge or {}
    gmd.NPCHeatWantedBridge.players = gmd.NPCHeatWantedBridge.players or {}
    gmd.NPCHeatWantedBridge.history = gmd.NPCHeatWantedBridge.history or {}
    gmd.NPCHeatWantedBridge.stats = gmd.NPCHeatWantedBridge.stats or {events=0, heat=0, levelUps=0, decays=0}
    if not gmd.DebugMapMarkers then gmd.DebugMapMarkers = {} end
    return gmd.NPCHeatWantedBridge
end

function NPCHeatWantedBridge.EnsurePlayerRecord(gmd, player)
    local data = NPCHeatWantedBridge.EnsureData(gmd)
    local pid = tostring(hw_playerId(player) or "")
    if not data or pid == "" then return nil, nil end
    data.players[pid] = data.players[pid] or {
        playerId = pid,
        playerName = hw_playerName(player),
        heat = 0,
        level = 0,
        state = "clean",
        bySide = {},
        events = 0,
        updatedAt = hw_now()
    }
    local rec = data.players[pid]
    rec.playerId = pid
    rec.playerName = hw_playerName(player)
    if type(rec.bySide) ~= "table" then rec.bySide = {} end
    rec.heat = tonumber(rec.heat) or 0
    rec.level = tonumber(rec.level) or 0
    rec.state = tostring(rec.state or NPCHeatWantedBridge.LevelName(rec.level))
    rec.events = tonumber(rec.events) or 0
    return rec, data
end

local function hw_decayRecord(rec, now)
    if type(rec) ~= "table" then return 0 end
    now = tonumber(now) or hw_now()
    local last = tonumber(rec.lastDecayAt or rec.updatedAt or now) or now
    local elapsed = math.max(0, now - last)
    local decay = (NPCHeatWantedBridge.DecayPerDay() / 24) * elapsed
    rec.lastDecayAt = now
    if decay <= 0 then return 0 end
    local before = tonumber(rec.heat) or 0
    local after = hw_clamp(before - decay, 0, NPCHeatWantedBridge.MaxHeat())
    rec.heat = after
    rec.level = NPCHeatWantedBridge.LevelForHeat(after)
    rec.state = NPCHeatWantedBridge.LevelName(rec.level)
    if type(rec.bySide) == "table" then
        for side, sideRec in pairs(rec.bySide) do
            if type(sideRec) == "table" then
                sideRec.heat = hw_clamp((tonumber(sideRec.heat) or 0) - decay, 0, NPCHeatWantedBridge.MaxHeat())
                sideRec.level = NPCHeatWantedBridge.LevelForHeat(sideRec.heat)
                sideRec.state = NPCHeatWantedBridge.LevelName(sideRec.level)
                sideRec.lastDecayAt = now
                if (tonumber(sideRec.heat) or 0) <= 0.5 then rec.bySide[side] = nil end
            end
        end
    else
        rec.bySide = {}
    end
    return math.max(0, before - after)
end

local function hw_addRadioCounterIntel(gmd, player, side, amount)
    amount = tonumber(amount) or 0
    if amount <= 0 then return end
    if not (gmd and player and NPCRadioInterceptBridge and NPCRadioInterceptBridge.EnsureData) then return end
    local scale = NPCHeatWantedBridge.CounterIntelScale()
    if scale <= 0 then return end
    local data = NPCRadioInterceptBridge.EnsureData(gmd)
    if not (data and data.counterIntel and data.counterIntel.players) then return end
    local pid = tostring(hw_playerId(player) or "")
    if pid == "" then return end
    side = hw_side(side) or "black"
    data.counterIntel.players[pid] = data.counterIntel.players[pid] or {}
    local row = data.counterIntel.players[pid][side]
    if type(row) ~= "table" then
        row = {heat=0, lastAt=hw_now(), burnUntil=0, detections=0}
        data.counterIntel.players[pid][side] = row
    end
    local maxHeat = NPCRadioInterceptBridge.CounterIntelMaxHeat and NPCRadioInterceptBridge.CounterIntelMaxHeat() or 60
    row.heat = hw_clamp((tonumber(row.heat) or 0) + (amount * scale), 0, maxHeat)
    row.lastAt = hw_now()
end

local function hw_addBounty(gmd, player, side, amount, reason, extra, level)
    if not NPCHeatWantedBridge.BountyBridgeEnabled() then return nil end
    side = hw_side(side)
    if side ~= "red" and side ~= "green" then return nil end
    if (tonumber(level) or 0) < NPCHeatWantedBridge.BountyMinLevel() then return nil end
    if not (NPCBountyBridge and NPCBountyBridge.Add) then return nil end
    local bountyAmount = math.floor((tonumber(amount) or 0) * NPCHeatWantedBridge.BountyMultiplier() + 0.5)
    if bountyAmount <= 0 then return nil end
    local ok, sideRec = pcall(function() return NPCBountyBridge.Add(gmd, player, side, bountyAmount, "heat_wanted_" .. tostring(reason or "activity"), extra) end)
    if ok then return sideRec end
    return nil
end

function NPCHeatWantedBridge.Add(gmd, player, side, amount, reason, extra)
    if not (NPCHeatWantedBridge.IsEnabled() and gmd and player) then return nil end
    amount = tonumber(amount) or 0
    if amount == 0 then return nil end
    local rec, data = NPCHeatWantedBridge.EnsurePlayerRecord(gmd, player)
    if not rec then return nil end
    local now = hw_now()
    hw_decayRecord(rec, now)

    side = hw_side(side) or "black"
    rec.bySide[side] = rec.bySide[side] or {side=side, heat=0, level=0, state="clean"}
    local sideRec = rec.bySide[side]
    local oldHeat = tonumber(rec.heat) or 0
    local oldLevel = tonumber(rec.level) or 0
    local oldSideHeat = tonumber(sideRec.heat) or 0

    local maxHeat = NPCHeatWantedBridge.MaxHeat()
    rec.heat = hw_clamp(oldHeat + amount, 0, maxHeat)
    rec.level = NPCHeatWantedBridge.LevelForHeat(rec.heat)
    rec.state = NPCHeatWantedBridge.LevelName(rec.level)
    rec.events = (tonumber(rec.events) or 0) + 1
    rec.updatedAt = now
    rec.lastReason = tostring(reason or "activity")
    rec.lastSide = side
    rec.lastDelta = rec.heat - oldHeat
    sideRec.heat = hw_clamp(oldSideHeat + amount, 0, maxHeat)
    sideRec.level = NPCHeatWantedBridge.LevelForHeat(sideRec.heat)
    sideRec.state = NPCHeatWantedBridge.LevelName(sideRec.level)
    sideRec.reason = rec.lastReason
    sideRec.lastDelta = sideRec.heat - oldSideHeat
    sideRec.updatedAt = now
    sideRec.playerId = rec.playerId
    sideRec.playerName = rec.playerName
    sideRec.side = side

    if player.getX and player.getY then
        rec.lastKnownX = math.floor(player:getX())
        rec.lastKnownY = math.floor(player:getY())
        rec.lastKnownZ = player.getZ and player:getZ() or 0
        sideRec.lastKnownX = rec.lastKnownX
        sideRec.lastKnownY = rec.lastKnownY
        sideRec.lastKnownZ = rec.lastKnownZ
    elseif extra then
        rec.lastKnownX = tonumber(extra.x) or rec.lastKnownX
        rec.lastKnownY = tonumber(extra.y) or rec.lastKnownY
        rec.lastKnownZ = tonumber(extra.z) or rec.lastKnownZ
    end

    if data and data.stats then
        data.stats.events = (tonumber(data.stats.events) or 0) + 1
        data.stats.heat = (tonumber(data.stats.heat) or 0) + math.max(0, amount)
        if rec.level > oldLevel then data.stats.levelUps = (tonumber(data.stats.levelUps) or 0) + 1 end
    end
    if data and type(data.history) == "table" then
        data.history[#data.history + 1] = {playerId=rec.playerId, playerName=rec.playerName, side=side, amount=amount, heat=rec.heat, level=rec.level, reason=rec.lastReason, at=now}
        local maxHistory = 80
        while #data.history > maxHistory do table.remove(data.history, 1) end
    end

    if not (extra and extra.skipCounterIntel == true) then
        hw_addRadioCounterIntel(gmd, player, side, math.max(0, amount))
    end
    hw_addBounty(gmd, player, side, math.max(0, amount), reason, extra, rec.level)

    return {
        record = rec,
        sideRecord = sideRec,
        side = side,
        amount = amount,
        heat = math.floor((tonumber(rec.heat) or 0) + 0.5),
        level = rec.level,
        state = rec.state,
        oldLevel = oldLevel,
        levelChanged = rec.level ~= oldLevel,
        reason = rec.lastReason
    }
end

function NPCHeatWantedBridge.Decay(gmd)
    local data = NPCHeatWantedBridge.EnsureData(gmd)
    if not data or type(data.players) ~= "table" then return 0 end
    local now = hw_now()
    local changed = 0
    for pid, rec in pairs(data.players) do
        if type(rec) == "table" then
            local before = math.floor((tonumber(rec.heat) or 0) + 0.5)
            local decayed = hw_decayRecord(rec, now)
            local after = math.floor((tonumber(rec.heat) or 0) + 0.5)
            if decayed > 0 and after ~= before then changed = changed + 1 end
            if (tonumber(rec.heat) or 0) <= 0.5 and not hw_hasTableEntries(rec.bySide) then
                data.players[pid] = nil
                changed = changed + 1
            end
        end
    end
    if changed > 0 and data.stats then data.stats.decays = (tonumber(data.stats.decays) or 0) + changed end
    return changed
end

function NPCHeatWantedBridge.ReportRadioScan(gmd, player, msg, metrics, source)
    if not (gmd and player and msg) then return nil end
    local amount = hw_num("HeatWanted_RadioScanHeat", 1.5, 0, 100)
    if msg.encrypted == true then amount = amount + 0.75 end
    if msg.decrypted == true then amount = amount + 1.0 end
    if msg.eventTraffic == true then amount = amount + 0.5 end
    if metrics and metrics.lock then
        amount = amount * math.max(0.35, math.min(1.35, (tonumber(metrics.lock) or 60) / 80.0))
    end
    return NPCHeatWantedBridge.Add(gmd, player, msg.side or (metrics and metrics.side) or "black", amount, source or "radio_scan", {skipCounterIntel=true})
end

function NPCHeatWantedBridge.ReportIntelProgress(gmd, player, targetSide, amount, source, sourceId)
    if not (gmd and player and targetSide) then return nil end
    local gain = (tonumber(amount) or 0) * hw_num("HeatWanted_IntelProgressScale", 0.05, 0, 10)
    if source == "base_probe" then gain = gain + hw_num("HeatWanted_BaseReconHeat", 1.0, 0, 100) end
    if gain <= 0 then return nil end
    return NPCHeatWantedBridge.Add(gmd, player, targetSide, gain, source or "intel_progress", {sourceId=sourceId})
end

function NPCHeatWantedBridge.ReportIntelSale(gmd, player, sold, info)
    if not (gmd and player and type(sold) == "table") then return nil end
    local total = tonumber(info and info.totalSold) or 0
    if total <= 0 then return nil end
    local base = hw_num("HeatWanted_IntelSaleHeat", 4, 0, 100) * total
    local result = NPCHeatWantedBridge.Add(gmd, player, "black", base, "intel_sale_black_market", info)
    local factionScale = hw_num("HeatWanted_IntelSaleFactionScale", 0.5, 0, 5)
    if factionScale > 0 then
        if (tonumber(sold.red) or 0) > 0 then NPCHeatWantedBridge.Add(gmd, player, "red", base * factionScale * (tonumber(sold.red) or 0) / total, "sold_red_intel", info) end
        if (tonumber(sold.green) or 0) > 0 then NPCHeatWantedBridge.Add(gmd, player, "green", base * factionScale * (tonumber(sold.green) or 0) / total, "sold_green_intel", info) end
    end
    return result
end

function NPCHeatWantedBridge.ReportBlackMarketDeal(gmd, player, action, side, success, extra)
    if not success then return nil end
    local amount = hw_num("HeatWanted_BlackMarketDealHeat", 1.0, 0, 100)
    if NPCBlackMarketBridge and NPCBlackMarketBridge.IsDeadDropDeal and NPCBlackMarketBridge.IsDeadDropDeal(action) then
        amount = amount + hw_num("HeatWanted_BlackMarketDeadDropHeat", 2.0, 0, 100)
    end
    if extra and extra.compromised == true then amount = amount + hw_num("HeatWanted_CompromisedDealHeat", 6.0, 0, 100) end
    if amount <= 0 then return nil end
    return NPCHeatWantedBridge.Add(gmd, player, side or "black", amount, "black_market_" .. tostring(action or "deal"), extra)
end

function NPCHeatWantedBridge.MakeMarker(rec)
    if type(rec) ~= "table" then return nil end
    if not rec.lastKnownX or not rec.lastKnownY then return nil end
    local level = tonumber(rec.level) or NPCHeatWantedBridge.LevelForHeat(rec.heat)
    if level < NPCHeatWantedBridge.MarkerMinLevel() then return nil end
    return {
        id = "heat_wanted_" .. tostring(rec.playerId or "player"),
        markerType = "heat_wanted",
        heatWanted = true,
        heatWantedLevel = level,
        heatWantedState = rec.state or NPCHeatWantedBridge.LevelName(level),
        heatWantedValue = math.floor((tonumber(rec.heat) or 0) + 0.5),
        heatWantedReason = rec.lastReason,
        heatWantedSide = rec.lastSide,
        heatWantedPlayerId = rec.playerId,
        heatWantedPlayerName = rec.playerName,
        name = "Wanted heat: " .. tostring(rec.playerName or rec.playerId or "player"),
        x = rec.lastKnownX,
        y = rec.lastKnownY,
        z = rec.lastKnownZ or 0,
        active = true,
        hostile = true,
        friendly = false,
        updatedAt = rec.updatedAt or hw_now()
    }
end

function NPCHeatWantedBridge.BuildPayload(gmd, player)
    local rec = nil
    local data = NPCHeatWantedBridge.EnsureData(gmd)
    local pid = tostring(hw_playerId(player) or "")
    if data and pid ~= "" then rec = data.players[pid] end
    local payload = {level=0, heat=0, state="clean", text="Heat: clean", bySide={}, updatedAt=hw_now()}
    if type(rec) ~= "table" then return payload end
    payload.playerId = rec.playerId
    payload.playerName = rec.playerName
    payload.heat = math.floor((tonumber(rec.heat) or 0) + 0.5)
    payload.level = tonumber(rec.level) or 0
    payload.state = rec.state or NPCHeatWantedBridge.LevelName(payload.level)
    payload.reason = rec.lastReason
    payload.bySide = {}
    local parts = {}
    if type(rec.bySide) == "table" then
        for side, sideRec in pairs(rec.bySide) do
            if type(sideRec) == "table" and (tonumber(sideRec.heat) or 0) > 0.5 then
                payload.bySide[side] = {heat=math.floor((tonumber(sideRec.heat) or 0) + 0.5), level=sideRec.level, state=sideRec.state, reason=sideRec.reason}
                parts[#parts + 1] = hw_sideLabel(side) .. " " .. tostring(payload.bySide[side].state) .. " " .. tostring(payload.bySide[side].heat)
            end
        end
    end
    if #parts > 0 then
        payload.text = "Heat L" .. tostring(payload.level) .. " " .. tostring(payload.state) .. ": " .. table.concat(parts, " / ")
    else
        payload.text = "Heat: clean"
    end
    return payload
end

function NPCHeatWantedBridge.ApplyStatePayload(player, args)
    player = player or (getPlayer and getPlayer() or nil)
    if not (player and type(args) == "table" and player.getModData) then return end
    local md = player:getModData()
    if not md then return end
    md.NPCHeatWantedBridge = args
end

NPCLegacyGlobalsBridge.InstallAlias("HeatWanted", NPCHeatWantedBridge, "NPCHeatWantedBridge")
