-- NPCLoyaltyServerBridge.lua
-- Neutral server backend for mercenary loyalty status and sync helpers.

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

local NPC_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
local NPC_SYNC_COMMAND_MODULE = "NPCCommands"
local NPC_SYNC_UPDATE_PART_COMMAND = NPCLegacyContractBridge.Command("UPDATE_PART") or ("Update" .. NPCLegacyContractBridge.Token .. "Part")
if isClient and isClient() then return end

require "NPCCore/NPCLoyaltyBridge"

NPCLoyaltyServerBridge = NPCLoyaltyServerBridge or {}
local function npcserver_setDebugMarker(gmd, marker)
    local runtime = NPCServerRuntime
    local setter = runtime and runtime.SetDebugMarker or NPC_LEGACY_GLOBALS.Get("SetDebugMarker")
    if setter then return setter(gmd, marker) end
    return false
end


local function bls_halo(player, text, r, g, b)
    if player and text then sendServerCommand(player, 'NPCLoyalty', 'Result', {text=text, r=r or 180, g=g or 230, b=b or 255}) end
end

local function bls_npcMarkerId(id)
    if id == nil then return nil end
    local sid = tostring(id)
    if sid == "" or sid == "nil" then return nil end
    if string.sub(sid, 1, 4) == "npc:" then return sid end
    return "npc:" .. sid
end

local function bls_isNpcMarker(marker)
    return type(marker) == "table" and tostring(marker.markerType or "") == "npc"
end

local function bls_sendDebugRemove(id)
    if not id then return end
    if NPCNetContract and NPCNetContract.SendDebugMapRemove then
        NPCNetContract.SendDebugMapRemove(id)
    else
        sendServerCommand('NPCDebugMap', 'Remove', {id=tostring(id)})
    end
end

local function bls_syncBrain(id, brain)
    if not (id and brain) then return end
    sendServerCommand(NPC_SYNC_COMMAND_MODULE, NPC_SYNC_UPDATE_PART_COMMAND, {
        id=brain.id or id,
        loyalty=brain.loyalty,
        mercenaryLoyalty=brain.mercenaryLoyalty,
        loyaltyState=brain.loyaltyState,
        loyaltyForPlayerId=brain.loyaltyForPlayerId,
        loyaltyForPlayerName=brain.loyaltyForPlayerName,
        loyaltyReason=brain.loyaltyReason,
        loyaltyUpdatedAt=brain.loyaltyUpdatedAt,
        lastLoyaltyDelta=brain.lastLoyaltyDelta,
        lastLoyaltyReason=brain.lastLoyaltyReason
    })
end

local function bls_updateMarker(gmd, id, brain)
    if not (gmd and id and brain and gmd.DebugMapMarkers) then return end

    local markerId = bls_npcMarkerId(id)
    if not markerId then return end

    local marker = gmd.DebugMapMarkers[markerId]
    local oldMarkerId = nil
    if not bls_isNpcMarker(marker) then
        local legacyId = tostring(id)
        local legacy = gmd.DebugMapMarkers[legacyId]
        if bls_isNpcMarker(legacy) then
            marker = legacy
            oldMarkerId = legacyId
        end
    end

    if marker and NPCLoyaltyBridge and NPCLoyaltyBridge.MarkerFields then
        marker.id = markerId
        marker.markerType = "npc"
        marker.runtimeId = tostring(id)
        marker.groupId = brain.worldGroupId or brain.groupId or marker.groupId
        marker.worldGroupId = marker.groupId
        NPCLoyaltyBridge.MarkerFields(marker, brain)
        if not npcserver_setDebugMarker(gmd, marker) then
            gmd.DebugMapMarkers[markerId] = marker
            if oldMarkerId and oldMarkerId ~= markerId and bls_isNpcMarker(gmd.DebugMapMarkers[oldMarkerId]) then
                gmd.DebugMapMarkers[oldMarkerId] = nil
                bls_sendDebugRemove(oldMarkerId)
            end
            if NPCNetContract and NPCNetContract.SendDebugMapUpdate then
                NPCNetContract.SendDebugMapUpdate(marker)
            else
                sendServerCommand('NPCDebugMap', 'Update', marker)
            end
        end
    end
end

function NPCLoyaltyServerBridge.RefreshPlayer(player)
    if not (NPCLoyaltyBridge and NPCLoyaltyBridge.IsEnabled and NPCLoyaltyBridge.IsEnabled()) then return end
    local gmd = GetNPCModData()
    if not (gmd and type(gmd.Queue) == "table") then return end
    local changed = 0
    for id, brain in pairs(gmd.Queue) do
        if type(brain) == "table" and NPCLoyaltyBridge.IsHiredBy(brain, player) then
            NPCLoyaltyBridge.EnsureBrain(brain, player)
            NPCLoyaltyBridge.ApplyBrainModifiers(brain)
            gmd.Queue[id] = brain
            bls_syncBrain(id, brain)
            bls_updateMarker(gmd, id, brain)
            changed = changed + 1
        end
    end
    if changed > 0 and TransmitNPCModData then TransmitNPCModData() end
end

function NPCLoyaltyServerBridge.Status(player)
    if not (NPCLoyaltyBridge and NPCLoyaltyBridge.IsEnabled and NPCLoyaltyBridge.IsEnabled()) then
        bls_halo(player, "Mercenary loyalty disabled.", 255, 190, 90)
        return
    end
    local gmd = GetNPCModData()
    NPCLoyaltyServerBridge.RefreshPlayer(player)
    local summary = NPCLoyaltyBridge.Summary(gmd, player)
    bls_halo(player, summary.text or "No hired mercenaries.", 180, 230, 255)
end

function NPCLoyaltyServerBridge.OnClientCommand(module, command, player, args)
    if not NPCLegacyContractBridge.IsModule(module, "NPCLoyalty", "loyalty") then return end
    if command == "Status" then
        NPCLoyaltyServerBridge.Status(player)
    elseif command == "Refresh" then
        NPCLoyaltyServerBridge.RefreshPlayer(player)
    end
end

function NPCLoyaltyServerBridge.Install()
    if NPCLoyaltyServerBridge._installed then return end
    NPCLoyaltyServerBridge._installed = true
    Events.OnClientCommand.Add(NPCLoyaltyServerBridge.OnClientCommand)
end
