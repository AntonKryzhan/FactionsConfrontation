-- NPCConvoysServerBridge.lua
-- Neutral server command layer and movement ticks for lightweight interactive supply convoys.

if not isServer() then return end

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCConvoysBridge"
require "NPCServer/NPCFactionDocsServerBridge"

NPCConvoysServerBridge = NPCConvoysServerBridge or {}

local function bcvs_say(player, text)
    if player and player.Say and text then pcall(function() player:Say(text) end) end
end

local function bcvs_halo(player, text, r, g, b)
    if player and text then
        sendServerCommand(player, 'NPCConvoys', 'Result', {text=text, r=r or 180, g=g or 230, b=b or 255})
    end
end

local function bcvs_ensure(gmd)
    if not gmd then return end
    if not gmd.DebugMapMarkers then gmd.DebugMapMarkers = {} end
    if NPCConvoysBridge and NPCConvoysBridge.EnsureData then NPCConvoysBridge.EnsureData(gmd) end
end

local function bcvs_setMarker(gmd, marker)
    if not gmd or not marker or not marker.id then return end
    if not gmd.DebugMapMarkers then gmd.DebugMapMarkers = {} end
    gmd.DebugMapMarkers[tostring(marker.id)] = marker
    if NPCNetContract and NPCNetContract.SendDebugMapUpdate then
        NPCNetContract.SendDebugMapUpdate(marker)
    else
        sendServerCommand('NPCDebugMap', 'Update', marker)
    end
end

local function bcvs_removeMarker(gmd, markerId)
    if not gmd or not markerId then return end
    if gmd.DebugMapMarkers then gmd.DebugMapMarkers[tostring(markerId)] = nil end
    if NPCNetContract and NPCNetContract.SendDebugMapRemove then
        NPCNetContract.SendDebugMapRemove(tostring(markerId))
    else
        sendServerCommand('NPCDebugMap', 'Remove', {id=tostring(markerId)})
    end
end

local function bcvs_sendActive(player)
    if not player then return end
    local gmd = GetNPCModData()
    bcvs_ensure(gmd)
    local op, convoy = NPCConvoysBridge.GetActiveOperation(gmd, player)
    if op and convoy then
        local copy = {}
        for k, v in pairs(convoy) do copy[k] = v end
        copy.operationText = NPCConvoysBridge.OperationText(op, convoy)
        sendServerCommand(player, 'NPCConvoys', 'Active', copy)
    else
        sendServerCommand(player, 'NPCConvoys', 'Clear', {})
    end
end

local function bcvs_requestOperation(player, args)
    if not (NPCConvoysBridge and NPCConvoysBridge.IsEnabled and NPCConvoysBridge.IsEnabled()) then return end
    if type(args) ~= "table" then return end

    local gmd = GetNPCModData()
    bcvs_ensure(gmd)

    local base = NPCConvoysBridge.FindBaseById(gmd, args.baseId)
    if not base then
        bcvs_halo(player, "No convoy base found nearby.", 255, 120, 80)
        return
    end
    if not NPCConvoysBridge.CanUseBase(base, player) then
        bcvs_halo(player, "This base will not organize convoys with you.", 255, 120, 80)
        return
    end

    local convoy, err = NPCConvoysBridge.CreateFromBase(gmd, player, base, args.objective or args.mode or "escort")
    if not convoy then
        if err == "operation_active" then
            bcvs_halo(player, "Convoy operation already active.", 255, 220, 120)
        elseif err == "too_many" then
            bcvs_halo(player, "Too many active convoys in the world.", 255, 180, 80)
        else
            bcvs_halo(player, "No convoy operation available: " .. tostring(err or "none"), 255, 120, 80)
        end
        bcvs_sendActive(player)
        return
    end

    local marker = NPCConvoysBridge.MakeMarker(convoy)
    if marker then bcvs_setMarker(gmd, marker) end
    bcvs_sendActive(player)
    bcvs_halo(player, tostring(convoy.text or "Convoy operation started."), 140, 240, 160)
    bcvs_say(player, tostring(convoy.text or "Convoy operation started."))
    TransmitNPCModData()
end

local function bcvs_completeEscort(player, args)
    if not (NPCConvoysBridge and NPCConvoysBridge.IsEnabled and NPCConvoysBridge.IsEnabled()) then return end
    local gmd = GetNPCModData()
    bcvs_ensure(gmd)

    local convoy, err = NPCConvoysBridge.CompleteEscort(gmd, player)
    if err then
        if err == "not_arrived" then
            bcvs_halo(player, "Convoy has not reached its destination yet.", 255, 180, 80)
        elseif err == "too_far" then
            bcvs_halo(player, "Move closer to the convoy to complete escort.", 255, 180, 80)
        else
            bcvs_halo(player, "No escort convoy to complete.", 255, 120, 80)
        end
        bcvs_sendActive(player)
        return
    end

    bcvs_removeMarker(gmd, convoy.markerId)
    bcvs_sendActive(player)
    bcvs_halo(player, "Convoy delivered: " .. tostring(convoy.cargoAmount or 0) .. " " .. tostring(convoy.cargoLabel or convoy.cargoResource or "cargo") .. ". Favor gained.", 120, 255, 120)
    if NPCFactionDocsServerBridge and NPCFactionDocsServerBridge.GrantIntelReward then
        NPCFactionDocsServerBridge.GrantIntelReward(player, convoy.side or convoy.factionSide, "convoy_escort")
    end
    bcvs_say(player, "Convoy delivered.")
    TransmitNPCModData()
end

local function bcvs_raidConvoy(player, args)
    if not (NPCConvoysBridge and NPCConvoysBridge.IsEnabled and NPCConvoysBridge.IsEnabled()) then return end
    local gmd = GetNPCModData()
    bcvs_ensure(gmd)

    local convoy, err = NPCConvoysBridge.RaidConvoy(gmd, player, args and args.convoyId or nil)
    if err then
        if err == "too_far" then
            bcvs_halo(player, "Move closer to the convoy before raiding.", 255, 180, 80)
        elseif err == "not_enemy" then
            bcvs_halo(player, "This convoy is not a valid enemy target.", 255, 180, 80)
        elseif err == "failed" and convoy then
            bcvs_halo(player, "Raid failed. The convoy is still moving.", 255, 120, 80)
            local marker = NPCConvoysBridge.MakeMarker(convoy)
            if marker then bcvs_setMarker(gmd, marker) end
        else
            bcvs_halo(player, "No enemy convoy nearby.", 255, 120, 80)
        end
        bcvs_sendActive(player)
        return
    end

    bcvs_removeMarker(gmd, convoy.markerId)
    bcvs_sendActive(player)
    local lootText = tostring(convoy.lootItemsGiven or 0) .. " loot item(s)"
    bcvs_halo(player, "Convoy raided: seized " .. lootText .. ".", 120, 255, 120)
    if NPCFactionDocsServerBridge and NPCFactionDocsServerBridge.GrantIntelReward then
        NPCFactionDocsServerBridge.GrantIntelReward(player, convoy.side or convoy.factionSide, "convoy_raid")
    end
    bcvs_say(player, "Convoy raided.")
    TransmitNPCModData()
end

local function bcvs_sync(player)
    if not (NPCConvoysBridge and NPCConvoysBridge.IsEnabled and NPCConvoysBridge.IsEnabled()) then return end
    bcvs_sendActive(player)
end

function NPCConvoysServerBridge.OnClientCommand(module, command, player, args)
    if not NPCLegacyContractBridge.IsModule(module, "NPCConvoys", "convoys") then return end
    if command == "RequestSync" then
        bcvs_sync(player)
    elseif command == "RequestOperation" then
        bcvs_requestOperation(player, args)
    elseif command == "CompleteEscort" then
        bcvs_completeEscort(player, args)
    elseif command == "RaidConvoy" then
        bcvs_raidConvoy(player, args)
    end
end

local function bcvs_everyTenMinutes()
    if not (NPCConvoysBridge and NPCConvoysBridge.IsEnabled and NPCConvoysBridge.IsEnabled()) then return end
    local gmd = GetNPCModData()
    bcvs_ensure(gmd)
    local changed = NPCConvoysBridge.Tick(gmd)
    for _, convoy in ipairs(changed or {}) do
        if convoy.status == "expired" or convoy.status == "completed" or convoy.status == "raided" then
            bcvs_removeMarker(gmd, convoy.markerId)
        else
            local marker = NPCConvoysBridge.MakeMarker(convoy)
            if marker then bcvs_setMarker(gmd, marker) end
        end
    end
    if changed and #changed > 0 then TransmitNPCModData() end
end

function NPCConvoysServerBridge.Install()
    if NPCConvoysServerBridge._installed then return end
    Events.OnClientCommand.Add(NPCConvoysServerBridge.OnClientCommand)
    Events.EveryTenMinutes.Add(bcvs_everyTenMinutes)
    NPCConvoysServerBridge._installed = true
end

NPCConvoysServerBridge.Install()
