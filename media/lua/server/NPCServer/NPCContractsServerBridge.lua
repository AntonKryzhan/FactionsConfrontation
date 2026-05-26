-- NPCContractsServerBridge.lua
-- Neutral server command backend for player faction contracts.

if not isServer() then return end

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCContractsBridge"

NPCContractsServerBridge = NPCContractsServerBridge or {}

local function bcs_say(player, text)
    if player and player.Say and text then pcall(function() player:Say(text) end) end
end

local function bcs_halo(player, text, r, g, b)
    if player and text then
        sendServerCommand(player, 'NPCContracts', 'Result', {text=text, r=r or 180, g=g or 230, b=b or 255})
    end
end

local function bcs_ensure(gmd)
    if not gmd then return end
    if not gmd.DebugMapMarkers then gmd.DebugMapMarkers = {} end
    if NPCContractsBridge and NPCContractsBridge.EnsureData then NPCContractsBridge.EnsureData(gmd) end
end

local function bcs_setMarker(gmd, marker)
    if not gmd or not marker or not marker.id then return end
    if not gmd.DebugMapMarkers then gmd.DebugMapMarkers = {} end
    marker.updatedAt = NPCContractsBridge and NPCContractsBridge.NowHours and NPCContractsBridge.NowHours() or 0
    gmd.DebugMapMarkers[tostring(marker.id)] = marker
    if NPCNetContract and NPCNetContract.SendDebugMapUpdate then
        NPCNetContract.SendDebugMapUpdate(marker)
    else
        sendServerCommand('NPCDebugMap', 'Update', marker)
    end
end

local function bcs_removeMarker(gmd, markerId)
    if not gmd or not markerId then return end
    if gmd.DebugMapMarkers then gmd.DebugMapMarkers[tostring(markerId)] = nil end
    if NPCNetContract and NPCNetContract.SendDebugMapRemove then
        NPCNetContract.SendDebugMapRemove(tostring(markerId))
    else
        sendServerCommand('NPCDebugMap', 'Remove', {id=tostring(markerId)})
    end
end

local function bcs_sendActive(player, contract)
    if not player then return end
    if contract and contract.status == "active" then
        sendServerCommand(player, 'NPCContracts', 'Active', contract)
    else
        sendServerCommand(player, 'NPCContracts', 'Clear', {})
    end
end

local function bcs_sync(player)
    if not (NPCContractsBridge and NPCContractsBridge.IsEnabled and NPCContractsBridge.IsEnabled()) then return end
    local gmd = GetNPCModData()
    bcs_ensure(gmd)
    local contract = NPCContractsBridge.GetActive(gmd, player)
    bcs_sendActive(player, contract)
end

local function bcs_request(player, args)
    if not (NPCContractsBridge and NPCContractsBridge.IsEnabled and NPCContractsBridge.IsEnabled()) then return end
    if type(args) ~= "table" then return end

    local gmd = GetNPCModData()
    bcs_ensure(gmd)

    local active = NPCContractsBridge.GetActive(gmd, player)
    if active then
        if NPCContractsBridge.IsExpired(active) then
            NPCContractsBridge.Fail(gmd, active, "expired")
            bcs_removeMarker(gmd, active.markerId)
            bcs_sendActive(player, nil)
        else
            bcs_sendActive(player, active)
            bcs_halo(player, "Contract already active: " .. tostring(active.text or active.title), 255, 220, 120)
            return
        end
    end

    local base = NPCContractsBridge.FindBaseById(gmd, args.baseId)
    if not base then
        bcs_halo(player, "No contract base found nearby.", 255, 120, 80)
        return
    end
    if not NPCContractsBridge.CanUseBase(base, player) then
        bcs_halo(player, "This base will not work with you.", 255, 120, 80)
        return
    end

    local contract, err = NPCContractsBridge.CreateContract(gmd, player, base, args.contractType)
    if not contract then
        bcs_halo(player, "No contract available: " .. tostring(err or "none"), 255, 120, 80)
        return
    end

    local marker = NPCContractsBridge.MakeMarker(contract)
    if marker then bcs_setMarker(gmd, marker) end
    bcs_sendActive(player, contract)
    bcs_halo(player, tostring(contract.text or "Faction contract accepted."), 140, 240, 160)
    bcs_say(player, tostring(contract.text or "Faction contract accepted."))
    TransmitNPCModData()
end

local function bcs_complete(player, args)
    if not (NPCContractsBridge and NPCContractsBridge.IsEnabled and NPCContractsBridge.IsEnabled()) then return end

    local gmd = GetNPCModData()
    bcs_ensure(gmd)

    local contract, err = NPCContractsBridge.TryCompleteActive(gmd, player)
    if not contract then
        bcs_halo(player, "No active contract.", 255, 120, 80)
        bcs_sendActive(player, nil)
        return
    end

    if err then
        if err == "too_far" then
            bcs_halo(player, "Recon target is still too far away.", 255, 180, 80)
        elseif err == "supply_incomplete" then
            bcs_halo(player, "Supply contract is not complete yet.", 255, 180, 80)
        elseif err == "expired" then
            bcs_removeMarker(gmd, contract.markerId)
            bcs_halo(player, "Contract expired.", 255, 120, 80)
            bcs_sendActive(player, nil)
        else
            bcs_halo(player, "Contract cannot be completed: " .. tostring(err), 255, 120, 80)
        end
        return
    end

    bcs_removeMarker(gmd, contract.markerId)
    bcs_sendActive(player, nil)
    local completeText = contract.completedBySpyIntel and "Recon complete by spy intel. Favor gained with " or "Contract complete. Favor gained with "
    bcs_halo(player, completeText .. tostring(contract.side or "faction") .. ".", 120, 255, 120)
    local factionDocsServer = NPCFactionDocsServer or (NPCLegacyGlobalsBridge and NPCLegacyGlobalsBridge.Get and NPCLegacyGlobalsBridge.Get("FactionDocsServer"))
    if factionDocsServer and factionDocsServer.GrantIntelReward then
        factionDocsServer.GrantIntelReward(player, contract.side, "contract")
    end
    bcs_say(player, "Contract complete.")
    TransmitNPCModData()
end

local function bcs_abandon(player, args)
    if not (NPCContractsBridge and NPCContractsBridge.IsEnabled and NPCContractsBridge.IsEnabled()) then return end
    local gmd = GetNPCModData()
    bcs_ensure(gmd)

    local contract = NPCContractsBridge.GetActive(gmd, player)
    if not contract then
        bcs_sendActive(player, nil)
        bcs_halo(player, "No active contract.", 255, 180, 80)
        return
    end

    NPCContractsBridge.Fail(gmd, contract, "abandoned")
    bcs_removeMarker(gmd, contract.markerId)
    bcs_sendActive(player, nil)
    bcs_halo(player, "Contract abandoned.", 255, 180, 80)
    TransmitNPCModData()
end

function NPCContractsServerBridge.OnClientCommand(module, command, player, args)
    if not NPCLegacyContractBridge.IsModule(module, "NPCContracts", "contracts") then return end
    if command == "RequestSync" then
        bcs_sync(player)
    elseif command == "RequestContract" then
        bcs_request(player, args)
    elseif command == "CompleteContract" then
        bcs_complete(player, args)
    elseif command == "AbandonContract" then
        bcs_abandon(player, args)
    end
end

function NPCContractsServerBridge.OnSupplyDonation(player, base, counts)
    if not (NPCContractsBridge and NPCContractsBridge.IsEnabled and NPCContractsBridge.IsEnabled()) then return nil end
    local gmd = GetNPCModData()
    bcs_ensure(gmd)

    local result = NPCContractsBridge.ApplySupplyDonation(gmd, player, base, counts)
    if not result or not result.contract then return nil end

    local contract = result.contract
    if result.status == "completed" then
        bcs_removeMarker(gmd, contract.markerId)
        bcs_sendActive(player, nil)
        bcs_halo(player, "Supply contract complete. Favor gained with " .. tostring(contract.side or "faction") .. ".", 120, 255, 120)
        local factionDocsServer = NPCFactionDocsServer or (NPCLegacyGlobalsBridge and NPCLegacyGlobalsBridge.Get and NPCLegacyGlobalsBridge.Get("FactionDocsServer"))
        if factionDocsServer and factionDocsServer.GrantIntelReward then
            factionDocsServer.GrantIntelReward(player, contract.side, "contract")
        end
        bcs_say(player, "Supply contract complete.")
    elseif result.status == "progress" then
        local marker = NPCContractsBridge.MakeMarker(contract)
        if marker then bcs_setMarker(gmd, marker) end
        bcs_sendActive(player, contract)
        bcs_halo(player, "Contract progress: " .. tostring(contract.deliveredAmount) .. "/" .. tostring(contract.requiredAmount) .. " " .. tostring(contract.resourceLabel or contract.resource) .. ".", 170, 230, 255)
    elseif result.status == "expired" then
        bcs_removeMarker(gmd, contract.markerId)
        bcs_sendActive(player, nil)
        bcs_halo(player, "Contract expired.", 255, 120, 80)
    end

    TransmitNPCModData()
    return result
end

function NPCContractsServerBridge.Install()
    if NPCContractsServerBridge._installed then return end
    Events.OnClientCommand.Add(NPCContractsServerBridge.OnClientCommand)
    NPCContractsServerBridge._installed = true
end

NPCContractsServerBridge.Install()
