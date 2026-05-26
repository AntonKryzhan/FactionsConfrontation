-- NPCLeadersServerBridge.lua
-- Neutral server backend for faction leader / base commander assignment and death consequences.

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

local NPC_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
if not isServer() then return end

require "NPCCore/NPCLeadersBridge"

NPCLeadersServerBridge = NPCLeadersServerBridge or {}
local function npcserver_setDebugMarker(gmd, marker)
    local runtime = NPCServerRuntime
    local setter = runtime and runtime.SetDebugMarker or NPC_LEGACY_GLOBALS.Get("SetDebugMarker")
    if setter then return setter(gmd, marker) end
    return false
end

local leaders_baseCampSystem = NPCBaseCampSystem or (NPCLegacyGlobalsBridge and NPCLegacyGlobalsBridge.Get and NPCLegacyGlobalsBridge.Get("BaseCampSystem"))
local leaders_bountyServer = NPCBountyServer or (NPCLegacyGlobalsBridge and NPCLegacyGlobalsBridge.Get and NPCLegacyGlobalsBridge.Get("BountyServer"))


local function bls_halo(player, text, r, g, b)
    if player and text then sendServerCommand(player, 'NPCLeaders', 'Result', {text=text, r=r or 255, g=g or 225, b=b or 120}) end
end

local function bls_setMarker(gmd, marker)
    if not (gmd and marker and marker.id) then return end
    if not npcserver_setDebugMarker(gmd, marker) then
        gmd.DebugMapMarkers = gmd.DebugMapMarkers or {}
        gmd.DebugMapMarkers[tostring(marker.id)] = marker
        if NPCNetContract and NPCNetContract.SendDebugMapUpdate then
            NPCNetContract.SendDebugMapUpdate(marker)
        else
            sendServerCommand('NPCDebugMap', 'Update', marker)
        end
    end
end

local function bls_removeLeaderMarker(gmd, leader)
    if not (gmd and leader and leader.id) then return end
    local id = "leader_" .. tostring(leader.id)
    if not (gmd.DebugMapMarkers and gmd.DebugMapMarkers[id]) then return end
    gmd.DebugMapMarkers[id] = nil
    if NPCNetContract and NPCNetContract.SendDebugMapRemove then
        NPCNetContract.SendDebugMapRemove(id)
    else
        sendServerCommand('NPCDebugMap', 'Remove', {id=id})
    end
end

local function bls_updateLeaderMarker(gmd, leader)
    if not (NPCLeadersBridge and leader) then return end
    local marker = nil
    if NPCLeadersBridge.MakeLeaderMarkerIfVisible then
        marker = NPCLeadersBridge.MakeLeaderMarkerIfVisible(gmd, leader)
    elseif NPCLeadersBridge.MakeLeaderMarker then
        marker = NPCLeadersBridge.MakeLeaderMarker(leader)
    end
    if marker then
        bls_setMarker(gmd, marker)
    else
        bls_removeLeaderMarker(gmd, leader)
    end
end

local function bls_updateGroupMarker(gmd, group)
    if not (gmd and group and group.id) then return end
    local marker = gmd.DebugMapMarkers and gmd.DebugMapMarkers[tostring(group.id)] or nil
    if not marker then return end
    if NPCLeadersBridge and NPCLeadersBridge.MarkerFields then NPCLeadersBridge.MarkerFields(marker, group) end
    marker.updatedAt = NPCLeadersBridge and NPCLeadersBridge.NowHours and NPCLeadersBridge.NowHours() or marker.updatedAt
    bls_setMarker(gmd, marker)
end

function NPCLeadersServerBridge.EnsureWorldLeaders()
    if not (NPCLeadersBridge and NPCLeadersBridge.IsEnabled and NPCLeadersBridge.IsEnabled()) then return 0 end
    local gmd = GetNPCModData()
    if not gmd then return 0 end
    NPCLeadersBridge.EnsureData(gmd)
    local changed = 0

    if NPCLeadersBridge.BaseCommandersEnabled() and type(gmd.BaseCamps) == "table" then
        for _, base in pairs(gmd.BaseCamps) do
            if type(base) == "table" then
                local before = base.commanderId
                local leader = NPCLeadersBridge.EnsureBaseCommander(gmd, base)
                if leader then
                    bls_updateLeaderMarker(gmd, leader)
                    if leaders_baseCampSystem and leaders_baseCampSystem.SendBaseMarker then pcall(function() leaders_baseCampSystem.SendBaseMarker(base) end) end
                    if before ~= base.commanderId then changed = changed + 1 end
                end
            end
        end
    end

    if NPCLeadersBridge.SquadLeadersEnabled() and type(gmd.VirtualGroups) == "table" then
        local sideCounts = {}
        for groupId, group in pairs(gmd.VirtualGroups) do
            if type(group) == "table" and not group.mercenaryHired then
                local side = NPCLeadersBridge.Side(group.factionSide or group.side or group.patrolColor or group.faction)
                if side then
                    sideCounts[side] = sideCounts[side] or 0
                    if sideCounts[side] < NPCLeadersBridge.MaxGroupLeadersPerSide() then
                        local before = group.leaderId
                        local leader = NPCLeadersBridge.EnsureGroupLeader(gmd, group, groupId)
                        if leader then
                            sideCounts[side] = sideCounts[side] + 1
                            gmd.VirtualGroups[groupId] = group
                            bls_updateLeaderMarker(gmd, leader)
                            bls_updateGroupMarker(gmd, group)
                            if before ~= group.leaderId then changed = changed + 1 end
                        end
                    end
                end
            end
        end
    end

    if changed > 0 and TransmitNPCModData then TransmitNPCModData() end
    return changed
end

function NPCLeadersServerBridge.ReportLeaderKilled(player, args)
    if not (NPCLeadersBridge and NPCLeadersBridge.IsEnabled and NPCLeadersBridge.IsEnabled()) then return end
    local gmd = GetNPCModData()
    if not gmd then return end
    args = args or {}
    args.playerId = args.playerId or (NPCBountyBridge and NPCBountyBridge.PlayerId and NPCBountyBridge.PlayerId(player))
    args.playerName = args.playerName or (NPCBountyBridge and NPCBountyBridge.PlayerName and NPCBountyBridge.PlayerName(player))
    if player and player.getX then
        args.x = args.x or player:getX()
        args.y = args.y or player:getY()
    end
    local leader = NPCLeadersBridge.MarkLeaderKilled(gmd, player, args)
    if not leader then return end

    bls_updateLeaderMarker(gmd, leader)
    if leader.baseId and gmd.BaseCamps and gmd.BaseCamps[tostring(leader.baseId)] and leaders_baseCampSystem and leaders_baseCampSystem.SendBaseMarkers then
        pcall(function() leaders_baseCampSystem.SendBaseMarkers(gmd.BaseCamps[tostring(leader.baseId)], true) end)
    end

    if NPCBountyBridge and NPCBountyBridge.Add and player and leader.side then
        local sideRec, rec = NPCBountyBridge.Add(gmd, player, leader.side, NPCLeadersBridge.BountyBonus(), "killed_leader", {leaderId=leader.id})
        if sideRec and rec and NPCBountyBridge.MakeBountyMarker then
            local marker = NPCBountyBridge.MakeBountyMarker(rec, leader.side, sideRec)
            if marker then bls_setMarker(gmd, marker) end
        end
        if sideRec and leaders_bountyServer and leaders_bountyServer.DispatchHuntersFor and NPCBountyBridge.IsSideRecordActive(sideRec, NPCBountyBridge.HuntedThreshold()) then
            pcall(function() leaders_bountyServer.DispatchHuntersFor(player, leader.side, sideRec) end)
        end
    end

    bls_halo(player, tostring(leader.name or "Faction leader") .. " eliminated. " .. tostring(NPCLeadersBridge.SideLabel(leader.side)) .. " command disrupted.", 255, 120, 60)
    if TransmitNPCModData then TransmitNPCModData() end
end

function NPCLeadersServerBridge.Status(player)
    local gmd = GetNPCModData()
    NPCLeadersServerBridge.EnsureWorldLeaders()
    local payload = NPCLeadersBridge and NPCLeadersBridge.BuildStatusPayload and NPCLeadersBridge.BuildStatusPayload(gmd) or {text="No leader data."}
    sendServerCommand(player, 'NPCLeaders', 'State', payload)
    bls_halo(player, payload.text or "No leader data.", 255, 225, 120)
end

function NPCLeadersServerBridge.Refresh(player)
    local gmd = GetNPCModData()
    NPCLeadersServerBridge.EnsureWorldLeaders()
    local data = NPCLeadersBridge and NPCLeadersBridge.EnsureData and NPCLeadersBridge.EnsureData(gmd) or nil
    if data and type(data.leaders) == "table" then
        for _, leader in pairs(data.leaders) do bls_updateLeaderMarker(gmd, leader) end
    end
    NPCLeadersServerBridge.Status(player)
end

function NPCLeadersServerBridge.OnClientCommand(module, command, player, args)
    if not NPCLegacyContractBridge.IsModule(module, "NPCLeaders", "leaders") then return end
    if command == "ReportLeaderKilled" then
        NPCLeadersServerBridge.ReportLeaderKilled(player, args or {})
    elseif command == "Status" then
        NPCLeadersServerBridge.Status(player)
    elseif command == "Refresh" then
        NPCLeadersServerBridge.Refresh(player)
    end
end

function NPCLeadersServerBridge.EveryTenMinutes()
    NPCLeadersServerBridge.EnsureWorldLeaders()
end

function NPCLeadersServerBridge.Install()
    if NPCLeadersServerBridge._installed then return end
    Events.OnClientCommand.Add(NPCLeadersServerBridge.OnClientCommand)
    Events.EveryTenMinutes.Add(NPCLeadersServerBridge.EveryTenMinutes)
    NPCLeadersServerBridge._installed = true
end

NPCLeadersServerBridge.Install()
