-- NPCRadioInterceptServerBridge.lua
-- Neutral server backend for player-facing radio scan commands and passive monitoring.
-- Server command layer for player-facing radio scans.

if not isServer() then return end

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCRadioInterceptBridge"

NPCRadioInterceptServerBridge = NPCRadioInterceptServerBridge or {}

local function bris_halo(player, text, r, g, b)
    if player and text then sendServerCommand(player, 'NPCRadioIntercept', 'Result', {text=text, r=r or 180, g=g or 230, b=b or 255}) end
end

-- Raw player speech is intentionally not used for radio scan output.
-- The client mirrors radio events into the local chat UI with readable guidance.

local function bris_ensure(gmd)
    if not gmd then return nil end
    if NPCRadioInterceptBridge and NPCRadioInterceptBridge.EnsureData then return NPCRadioInterceptBridge.EnsureData(gmd) end
    return nil
end

local function bris_checkScan(player)
    if not (NPCRadioInterceptBridge and NPCRadioInterceptBridge.IsEnabled and NPCRadioInterceptBridge.IsEnabled()) then return false end
    local gmd = GetNPCModData()
    local data = bris_ensure(gmd)
    if not data then return false end

    local ok, reason, waitHours = NPCRadioInterceptBridge.CanScan(gmd, player)
    if not ok then
        if reason == "no_radio" then
            bris_halo(player, "You need a radio or walkie-talkie to intercept faction traffic.", 255, 180, 80)
        elseif reason == "radio_off" then
            bris_halo(player, "Radio must be turned on and powered to intercept faction traffic.", 255, 180, 80)
        elseif reason == "cooldown" then
            local minutes = math.max(1, math.ceil((tonumber(waitHours) or 0) * 60))
            bris_halo(player, "Radio scan cooldown: " .. tostring(minutes) .. " min.", 255, 180, 80)
        elseif reason == "radio_silence" then
            local minutes = math.max(1, math.ceil((tonumber(waitHours) or 0) * 60))
            bris_halo(player, "Radio silence active: " .. tostring(minutes) .. " min.", 180, 230, 255)
        else
            bris_halo(player, "Radio intercept unavailable.", 255, 180, 80)
        end
        return false
    end
    return true, gmd, data
end

local function bris_finishScan(player, gmd, data, msg, metrics)
    NPCRadioInterceptBridge.SetCooldown(gmd, player)
    local counterIntel = nil
    if NPCRadioInterceptBridge.RegisterCounterIntelExposure then
        counterIntel = NPCRadioInterceptBridge.RegisterCounterIntelExposure(gmd, player, msg, metrics, "scan")
    end
    NPCRadioInterceptBridge.AddHistory(gmd, player, msg)
    data.stats.scans = (tonumber(data.stats.scans) or 0) + 1
    if msg and msg.encrypted then data.stats.encrypted = (tonumber(data.stats.encrypted) or 0) + 1 end
    if msg and msg.decrypted then data.stats.decrypted = (tonumber(data.stats.decrypted) or 0) + 1 end

    local factionDocs = NPCLegacyGlobalsBridge.Get("FactionDocs")
    if msg and msg.kind == "password" and msg.decoded ~= false and not msg.falseSignal and factionDocs and factionDocs.GrantPassword then
        local rec = factionDocs.GrantPassword(gmd, player, msg.side, "radio_intercept", 8)
        if rec then
            data.stats.passwordLeaks = (tonumber(data.stats.passwordLeaks) or 0) + 1
        end
    end

    local markerAdded = false
    if msg and msg.decoded ~= false and NPCRadioInterceptBridge.AddIntelMarker then
        markerAdded = NPCRadioInterceptBridge.AddIntelMarker(gmd, player, msg, metrics) == true
    end

    local prefix = "Radio"
    if metrics then
        prefix = "Radio " .. string.format("%.2f MHz", tonumber(metrics.frequency) or 0) .. " S" .. tostring(metrics.signal or 0) .. " N" .. tostring(metrics.noise or 0) .. " L" .. tostring(metrics.lock or 0)
    end
    local text = msg and msg.text or "Only static on this frequency."
    if markerAdded then text = text .. " Map marker added." end
    if counterIntel and counterIntel.text then text = text .. " " .. tostring(counterIntel.text) end
    bris_halo(player, prefix .. ": " .. tostring(text), 180, 230, 255)
    TransmitNPCModData()
end

local function bris_scan(player)
    local ok, gmd, data = bris_checkScan(player)
    if not ok then return end
    local msg = NPCRadioInterceptBridge.GenerateMessage(gmd, player)
    bris_finishScan(player, gmd, data, msg, nil)
end

local function bris_tunedScan(player, args)
    local ok, gmd, data = bris_checkScan(player)
    if not ok then return end
    args = type(args) == "table" and args or {}
    local msg, metrics = NPCRadioInterceptBridge.GenerateTunedMessage(gmd, player, args)
    bris_finishScan(player, gmd, data, msg, metrics)
end

function NPCRadioInterceptServerBridge.SendHistory(player)
    local gmd = GetNPCModData()
    bris_ensure(gmd)
    if NPCRadioInterceptBridge and NPCRadioInterceptBridge.CleanupIntelMarkers then
        NPCRadioInterceptBridge.CleanupIntelMarkers(gmd)
    end
    if NPCRadioInterceptBridge and NPCRadioInterceptBridge.CleanupCounterIntelMarkers then
        NPCRadioInterceptBridge.CleanupCounterIntelMarkers(gmd)
    end
    local text = NPCRadioInterceptBridge and NPCRadioInterceptBridge.HistoryText and NPCRadioInterceptBridge.HistoryText(gmd, player) or "No radio intercepts stored."
    bris_halo(player, text, 180, 230, 255)
end

function NPCRadioInterceptServerBridge.SendStatus(player)
    local text = NPCRadioInterceptBridge and NPCRadioInterceptBridge.RadioStatusText and NPCRadioInterceptBridge.RadioStatusText(player) or "Radio status unavailable."
    local gmd = GetNPCModData()
    if NPCRadioInterceptBridge and NPCRadioInterceptBridge.ReceiverStatusText then
        text = text .. " / " .. NPCRadioInterceptBridge.ReceiverStatusText(gmd, player)
    end
    bris_halo(player, text, 180, 230, 255)
end

local function bris_receiverStatus(player)
    local gmd = GetNPCModData()
    local text = NPCRadioInterceptBridge and NPCRadioInterceptBridge.ReceiverStatusText and NPCRadioInterceptBridge.ReceiverStatusText(gmd, player) or "Receiver unavailable."
    bris_halo(player, text, 180, 230, 255)
end

local function bris_decoderStatus(player)
    local gmd = GetNPCModData()
    local text = NPCRadioInterceptBridge and NPCRadioInterceptBridge.DecoderStatusText and NPCRadioInterceptBridge.DecoderStatusText(gmd, player) or "Decoder unavailable."
    bris_halo(player, text, 180, 230, 255)
end

local function bris_summary(player)
    local gmd = GetNPCModData()
    local text = NPCRadioInterceptBridge and NPCRadioInterceptBridge.SummaryText and NPCRadioInterceptBridge.SummaryText(gmd, player) or "Radio summary unavailable."
    bris_halo(player, text, 180, 230, 255)
end

local function bris_clearHistory(player)
    local gmd = GetNPCModData()
    if NPCRadioInterceptBridge and NPCRadioInterceptBridge.ClearHistory and NPCRadioInterceptBridge.ClearHistory(gmd, player) then
        bris_halo(player, "Radio intercept history cleared.", 180, 230, 255)
        TransmitNPCModData()
    else
        bris_halo(player, "Radio history unavailable.", 255, 180, 80)
    end
end

local function bris_radioSilence(player, args)
    local gmd = GetNPCModData()
    local enabled = args and (args.enabled == true or tostring(args.enabled or ""):lower() == "true" or tostring(args.enabled or "") == "1")
    if not (NPCRadioInterceptBridge and NPCRadioInterceptBridge.SetRadioSilence) then
        bris_halo(player, "Radio silence unavailable.", 255, 180, 80)
        return
    end
    local untilAt = NPCRadioInterceptBridge.SetRadioSilence(gmd, player, enabled)
    local text = enabled and "Radio silence enabled. Passive monitoring stopped and radio heat reduced." or "Radio silence disabled."
    if enabled and untilAt and untilAt > 0 then
        local minutes = math.max(1, math.ceil((untilAt - NPCRadioInterceptBridge.NowHours()) * 60))
        text = text .. " Duration " .. tostring(minutes) .. " min."
    end
    bris_halo(player, text, 180, 230, 255)
    TransmitNPCModData()
end

local function bris_adjustReceiver(player, args)
    local gmd = GetNPCModData()
    local state = NPCRadioInterceptBridge and NPCRadioInterceptBridge.AdjustReceiver and NPCRadioInterceptBridge.AdjustReceiver(gmd, player, args)
    if not state then
        bris_halo(player, "Receiver unavailable.", 255, 180, 80)
        return
    end
    bris_halo(player, NPCRadioInterceptBridge.ReceiverStatusText(gmd, player), 180, 230, 255)
    TransmitNPCModData()
end

local function bris_scanReceiver(player)
    local ok, gmd, data = bris_checkScan(player)
    if not ok then return end
    local scanArgs = NPCRadioInterceptBridge.GetReceiverScanArgs and NPCRadioInterceptBridge.GetReceiverScanArgs(gmd, player) or {}
    local msg, metrics = NPCRadioInterceptBridge.GenerateTunedMessage(gmd, player, scanArgs)
    local state = NPCRadioInterceptBridge.EnsureReceiverState and NPCRadioInterceptBridge.EnsureReceiverState(gmd, player)
    if state then
        state.lastMetrics = metrics
        state.lastScanAt = NPCRadioInterceptBridge.NowHours and NPCRadioInterceptBridge.NowHours() or nil
    end
    bris_finishScan(player, gmd, data, msg, metrics)
end

local function bris_setMonitor(player, args)
    local gmd = GetNPCModData()
    local enabled = args and (args.enabled == true or tostring(args.enabled or ""):lower() == "true" or tostring(args.enabled or "") == "1")
    local state = NPCRadioInterceptBridge and NPCRadioInterceptBridge.SetReceiverMonitoring and NPCRadioInterceptBridge.SetReceiverMonitoring(gmd, player, enabled)
    if not state then
        bris_halo(player, "Receiver unavailable.", 255, 180, 80)
        return
    end
    local text = enabled and "Radio monitor enabled." or "Radio monitor disabled."
    if NPCRadioInterceptBridge and NPCRadioInterceptBridge.ReceiverStatusText then
        text = text .. " " .. NPCRadioInterceptBridge.ReceiverStatusText(gmd, player)
    end
    bris_halo(player, text, 180, 230, 255)
    TransmitNPCModData()
end

local function bris_playerList()
    local result = {}
    if getOnlinePlayers then
        local ok, players = pcall(function() return getOnlinePlayers() end)
        if ok and players and players.size and players.get then
            for i=0, players:size() - 1 do
                local okPlayer, player = pcall(function() return players:get(i) end)
                if okPlayer and player then result[#result + 1] = player end
            end
        end
    end
    if #result == 0 and getPlayer then
        local ok, player = pcall(function() return getPlayer() end)
        if ok and player then result[#result + 1] = player end
    end
    return result
end

local function bris_monitorTick()
    if not (NPCRadioInterceptBridge and NPCRadioInterceptBridge.ShouldMonitorScan) then return end
    local gmd = GetNPCModData()
    local data = bris_ensure(gmd)
    if not data then return end
    local changed = false
    for _, player in ipairs(bris_playerList()) do
        local ok, reason, state = NPCRadioInterceptBridge.ShouldMonitorScan(gmd, player)
        if ok and state then
            local scanArgs = NPCRadioInterceptBridge.GetReceiverScanArgs and NPCRadioInterceptBridge.GetReceiverScanArgs(gmd, player) or {}
            local msg, metrics = NPCRadioInterceptBridge.GenerateTunedMessage(gmd, player, scanArgs)
            local counterIntel = nil
            if NPCRadioInterceptBridge.RegisterCounterIntelExposure then
                counterIntel = NPCRadioInterceptBridge.RegisterCounterIntelExposure(gmd, player, msg, metrics, "monitor")
            end
            NPCRadioInterceptBridge.MarkMonitorScan(state)
            state.lastMetrics = metrics
            state.lastScanAt = NPCRadioInterceptBridge.NowHours and NPCRadioInterceptBridge.NowHours() or nil
            if msg and metrics and (tonumber(metrics.lock) or 0) >= NPCRadioInterceptBridge.MonitorMinLock() and (msg.decoded ~= false or msg.encrypted == true) then
                NPCRadioInterceptBridge.AddHistory(gmd, player, msg)
                data.stats.monitorHits = (tonumber(data.stats.monitorHits) or 0) + 1
                if msg.encrypted then data.stats.encrypted = (tonumber(data.stats.encrypted) or 0) + 1 end
                if msg.decrypted then data.stats.decrypted = (tonumber(data.stats.decrypted) or 0) + 1 end
                local factionDocs = NPCLegacyGlobalsBridge.Get("FactionDocs")
                if msg.kind == "password" and msg.decoded ~= false and not msg.falseSignal and factionDocs and factionDocs.GrantPassword then
                    local rec = factionDocs.GrantPassword(gmd, player, msg.side, "radio_monitor", 8)
                    if rec then data.stats.passwordLeaks = (tonumber(data.stats.passwordLeaks) or 0) + 1 end
                end
                local markerAdded = false
                if msg.decoded ~= false and NPCRadioInterceptBridge.AddIntelMarker then
                    markerAdded = NPCRadioInterceptBridge.AddIntelMarker(gmd, player, msg, metrics) == true
                end
                local text = "Radio monitor " .. string.format("%.2f MHz", tonumber(metrics.frequency) or 0) .. " S" .. tostring(metrics.signal or 0) .. " N" .. tostring(metrics.noise or 0) .. " L" .. tostring(metrics.lock or 0) .. ": " .. tostring(msg.text or "transmission")
                if markerAdded then text = text .. " Map marker added." end
                if counterIntel and counterIntel.text then text = text .. " " .. tostring(counterIntel.text) end
                bris_halo(player, text, 180, 230, 255)
                changed = true
            elseif reason ~= "wait" then
                changed = true
            else
                changed = true
            end
        end
    end
    if changed then
        TransmitNPCModData()
    end
end

function NPCRadioInterceptServerBridge.OnClientCommand(module, command, player, args)
    if not NPCLegacyContractBridge.IsModule(module, "NPCRadioIntercept", "radioIntercept") then return end
    if command == "Scan" then
        bris_scan(player)
    elseif command == "TuneScan" then
        bris_tunedScan(player, args)
    elseif command == "Status" then
        NPCRadioInterceptServerBridge.SendStatus(player)
    elseif command == "ReceiverStatus" then
        bris_receiverStatus(player)
    elseif command == "DecoderStatus" then
        bris_decoderStatus(player)
    elseif command == "Summary" then
        bris_summary(player)
    elseif command == "ClearHistory" then
        bris_clearHistory(player)
    elseif command == "RadioSilence" then
        bris_radioSilence(player, args)
    elseif command == "ReceiverAdjust" then
        bris_adjustReceiver(player, args)
    elseif command == "ReceiverScan" then
        bris_scanReceiver(player)
    elseif command == "ReceiverMonitor" then
        bris_setMonitor(player, args)
    elseif command == "History" then
        NPCRadioInterceptServerBridge.SendHistory(player)
    end
end

function NPCRadioInterceptServerBridge.Install()
    if NPCRadioInterceptServerBridge._installed then return end
    NPCRadioInterceptServerBridge._installed = true
    Events.OnClientCommand.Add(NPCRadioInterceptServerBridge.OnClientCommand)
    Events.EveryTenMinutes.Add(bris_monitorTick)
end
