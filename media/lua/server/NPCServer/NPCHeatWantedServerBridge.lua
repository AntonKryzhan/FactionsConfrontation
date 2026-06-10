-- NPCHeatWantedServerBridge.lua
-- Server sync/decay layer for unified player heat and wanted state.

if isClient and isClient() then return end

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCHeatWantedBridge"
require "NPCCommands/NPCNetContract"

NPCHeatWantedServerBridge = NPCHeatWantedServerBridge or {}

local function hws_halo(player, text, r, g, b)
    if player and text and sendServerCommand then
        sendServerCommand(player, 'NPCHeatWanted', 'Result', {text=tostring(text), r=r or 255, g=g or 180, b=b or 80})
    end
end

local function hws_setMarker(gmd, marker)
    if not (gmd and marker and marker.id) then return false end
    gmd.DebugMapMarkers = gmd.DebugMapMarkers or {}
    gmd.DebugMapMarkers[tostring(marker.id)] = marker
    if NPCNetContract and NPCNetContract.SendDebugMapUpdate then
        NPCNetContract.SendDebugMapUpdate(marker)
    elseif sendServerCommand then
        sendServerCommand('NPCDebugMap', 'Update', marker)
    end
    return true
end

local function hws_removeMarker(gmd, id)
    if not (gmd and id) then return end
    if gmd.DebugMapMarkers then gmd.DebugMapMarkers[tostring(id)] = nil end
    if NPCNetContract and NPCNetContract.SendDebugMapRemove then
        NPCNetContract.SendDebugMapRemove(id)
    elseif sendServerCommand then
        sendServerCommand('NPCDebugMap', 'Remove', {id=tostring(id)})
    end
end

function NPCHeatWantedServerBridge.SyncPlayer(player, reason)
    if not (NPCHeatWantedBridge and player) then return nil end
    local gmd = GetNPCModData and GetNPCModData() or nil
    local payload = NPCHeatWantedBridge.BuildPayload(gmd, player)
    payload.reasonSync = reason
    if sendServerCommand then sendServerCommand(player, 'NPCHeatWanted', 'State', payload) end
    return payload
end

function NPCHeatWantedServerBridge.AfterHeatChanged(player, result)
    if not (NPCHeatWantedBridge and result and result.record) then return end
    local gmd = GetNPCModData and GetNPCModData() or nil
    if gmd and NPCHeatWantedBridge.MarkerEnabled and NPCHeatWantedBridge.MarkerEnabled() then
        local marker = NPCHeatWantedBridge.MakeMarker(result.record)
        if marker then
            hws_setMarker(gmd, marker)
        else
            hws_removeMarker(gmd, "heat_wanted_" .. tostring(result.record.playerId or "player"))
        end
    end
    NPCHeatWantedServerBridge.SyncPlayer(player, "heat_changed")
    if result.levelChanged and result.level > result.oldLevel and NPCHeatWantedBridge.NotifyEnabled and NPCHeatWantedBridge.NotifyEnabled() then
        hws_halo(player, "Wanted heat increased: L" .. tostring(result.level) .. " " .. tostring(result.state) .. " (" .. tostring(result.heat) .. ").", 255, 170, 70)
    end
end

function NPCHeatWantedServerBridge.Report(player, side, amount, reason, extra)
    local gmd = GetNPCModData and GetNPCModData() or nil
    local result = NPCHeatWantedBridge and NPCHeatWantedBridge.Add and NPCHeatWantedBridge.Add(gmd, player, side, amount, reason, extra) or nil
    if result then
        NPCHeatWantedServerBridge.AfterHeatChanged(player, result)
        if TransmitNPCModData then TransmitNPCModData() end
    end
    return result
end

function NPCHeatWantedServerBridge.Status(player)
    local gmd = GetNPCModData and GetNPCModData() or nil
    if NPCHeatWantedBridge and NPCHeatWantedBridge.Decay then NPCHeatWantedBridge.Decay(gmd) end
    local payload = NPCHeatWantedServerBridge.SyncPlayer(player, "status")
    hws_halo(player, payload and payload.text or "Heat unavailable.", 255, 210, 120)
end

local function hws_players()
    local out = {}
    if getOnlinePlayers then
        local ok, list = pcall(function() return getOnlinePlayers() end)
        if ok and list and list.size and list.get then
            for i = 0, list:size() - 1 do
                local okPlayer, player = pcall(function() return list:get(i) end)
                if okPlayer and player then out[#out + 1] = player end
            end
        end
    end
    if #out == 0 and getPlayer then
        local ok, player = pcall(function() return getPlayer() end)
        if ok and player then out[#out + 1] = player end
    end
    return out
end

function NPCHeatWantedServerBridge.RefreshAll(reason)
    local gmd = GetNPCModData and GetNPCModData() or nil
    if not gmd then return end
    if NPCHeatWantedBridge and NPCHeatWantedBridge.Decay then NPCHeatWantedBridge.Decay(gmd) end
    local data = NPCHeatWantedBridge and NPCHeatWantedBridge.EnsureData and NPCHeatWantedBridge.EnsureData(gmd) or nil
    if data and type(data.players) == "table" then
        for pid, rec in pairs(data.players) do
            if type(rec) == "table" then
                local marker = NPCHeatWantedBridge.MakeMarker(rec)
                if marker then hws_setMarker(gmd, marker) else hws_removeMarker(gmd, "heat_wanted_" .. tostring(pid)) end
            end
        end
    end
    for _, player in ipairs(hws_players()) do
        NPCHeatWantedServerBridge.SyncPlayer(player, reason or "refresh")
    end
    if TransmitNPCModData then TransmitNPCModData() end
end

function NPCHeatWantedServerBridge.EveryTenMinutes()
    if not (NPCHeatWantedBridge and NPCHeatWantedBridge.IsEnabled and NPCHeatWantedBridge.IsEnabled()) then return end
    NPCHeatWantedServerBridge.RefreshAll("decay")
end

function NPCHeatWantedServerBridge.OnClientCommand(module, command, player, args)
    if not NPCLegacyContractBridge.IsModule(module, "NPCHeatWanted", "heatWanted") then return end
    if command == "Status" or command == "Refresh" then
        NPCHeatWantedServerBridge.Status(player)
    elseif command == "DebugAdd" then
        NPCHeatWantedServerBridge.Report(player, args and args.side or "black", args and args.amount or 10, "debug", args)
        NPCHeatWantedServerBridge.Status(player)
    end
end

function NPCHeatWantedServerBridge.Install()
    if NPCHeatWantedServerBridge.__installed then return end
    NPCHeatWantedServerBridge.__installed = true
    Events.OnClientCommand.Add(NPCHeatWantedServerBridge.OnClientCommand)
    Events.EveryTenMinutes.Add(NPCHeatWantedServerBridge.EveryTenMinutes)
end

NPCHeatWantedServerBridge.Install()
