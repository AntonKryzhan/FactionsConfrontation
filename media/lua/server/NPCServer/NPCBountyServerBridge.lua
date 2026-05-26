-- NPCBountyServerBridge.lua
-- Neutral server-side bounty records, checkpoint integration support and lightweight hunter retargeting.

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

local NPC_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
if not isServer() then return end

require "NPCCore/NPCBountyBridge"
require "NPCCore/NPCFactionBridge"

NPCBountyServerBridge = NPCBountyServerBridge or {}
local function npcserver_setDebugMarker(gmd, marker)
    local runtime = NPCServerRuntime
    local setter = runtime and runtime.SetDebugMarker or NPC_LEGACY_GLOBALS.Get("SetDebugMarker")
    if setter then return setter(gmd, marker) end
    return false
end


local function bbs_halo(player, text, r, g, b)
    if player and text then sendServerCommand(player, 'NPCBounty', 'Result', {text=text, r=r or 255, g=g or 210, b=b or 90}) end
end

local function bbs_sync(player)
    if not (NPCBountyBridge and player) then return end
    local gmd = GetNPCModData()
    local payload = NPCBountyBridge.BuildPayload(gmd, player)
    sendServerCommand(player, 'NPCBounty', 'State', payload)
end

function NPCBountyServerBridge.SyncPlayer(player)
    bbs_sync(player)
end

local function bbs_syncAll(reason)
    local worldRulesServer = NPCWorldRulesServer or (NPCLegacyGlobalsBridge and NPCLegacyGlobalsBridge.Get and NPCLegacyGlobalsBridge.Get("WorldRulesServer"))
    if worldRulesServer and worldRulesServer.SyncAll then
        worldRulesServer.SyncAll(reason or "bounty_sync")
        return
    end
    if getOnlinePlayers then
        local ok, players = pcall(function() return getOnlinePlayers() end)
        if ok and players and players.size and players.get then
            for i=0, players:size()-1 do
                local p = players:get(i)
                if p then bbs_sync(p) end
            end
            return
        end
    end
end

local function bbs_setMarker(gmd, marker)
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

local function bbs_updateBountyMarker(gmd, rec, side, sideRec)
    if not (NPCBountyBridge and gmd and rec and sideRec) then return end
    local marker = NPCBountyBridge.MakeBountyMarker(rec, side, sideRec)
    if marker then bbs_setMarker(gmd, marker) end
end

local function bbs_removeBountyMarker(gmd, pid, side)
    if not (gmd and pid and side) then return end
    local id = "bounty_" .. tostring(pid) .. "_" .. tostring(side)
    if gmd.DebugMapMarkers then gmd.DebugMapMarkers[id] = nil end
    if NPCNetContract and NPCNetContract.SendDebugMapRemove then
        NPCNetContract.SendDebugMapRemove(id)
    else
        sendServerCommand('NPCDebugMap', 'Remove', {id=id})
    end
end

local function bbs_side(value)
    if NPCFactionBridge and NPCFactionBridge.NormalizeSide then return NPCFactionBridge.NormalizeSide(value) end
    value = tostring(value or ""):lower()
    if value == "red" or value == "green" or value == "blue" or value == "black" then return value end
    return nil
end

local function bbs_dist(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return math.sqrt(dx * dx + dy * dy)
end

local function bbs_updateGroupMarker(gmd, group)
    if not (gmd and group and group.id) then return end
    local marker = gmd.DebugMapMarkers and gmd.DebugMapMarkers[tostring(group.id)] or nil
    if not marker then return end
    marker.bountyHunter = group.bountyHunter == true
    marker.bountySide = group.bountySide or group.factionSide or group.side
    marker.bountyState = group.bountyState
    marker.bountyAmount = group.bountyAmount
    marker.bountyTargetPlayerId = group.bountyTargetPlayerId
    marker.bountyTargetPlayerName = group.bountyTargetPlayerName
    marker.targetX = group.targetX
    marker.targetY = group.targetY
    marker.state = group.state
    marker.updatedAt = group.updatedAt or (NPCBountyBridge and NPCBountyBridge.NowHours and NPCBountyBridge.NowHours() or 0)
    if NPCBountyBridge and NPCBountyBridge.MarkerFields then NPCBountyBridge.MarkerFields(marker, group) end
    bbs_setMarker(gmd, marker)
end

function NPCBountyServerBridge.DispatchHuntersFor(player, side, sideRec)
    if not (NPCBountyBridge and NPCBountyBridge.HunterRetargetEnabled and NPCBountyBridge.HunterRetargetEnabled()) then return 0 end
    if not (player and player.getX and sideRec and NPCBountyBridge.IsSideRecordActive(sideRec, NPCBountyBridge.HuntedThreshold())) then return 0 end
    local gmd = GetNPCModData()
    if not (gmd and type(gmd.VirtualGroups) == "table") then return 0 end
    side = bbs_side(side)
    if not side or side == "blue" or side == "black" then return 0 end
    local px = player:getX()
    local py = player:getY()
    local radius = NPCBountyBridge.HunterRadius()
    local maxGroups = NPCBountyBridge.HunterMaxGroups()
    if maxGroups <= 0 then return 0 end

    local candidates = {}
    for id, group in pairs(gmd.VirtualGroups) do
        if type(group) == "table" and not group.activated and not group.mercenary and (tonumber(group.count) or 0) > 0 then
            local gs = bbs_side(group.factionSide or group.side or group.patrolColor)
            if gs == side then
                local d = bbs_dist(group.x, group.y, px, py)
                if d <= radius then candidates[#candidates + 1] = {id=id, group=group, dist=d} end
            end
        end
    end
    table.sort(candidates, function(a, b) return (a.dist or 0) < (b.dist or 0) end)

    local changed = 0
    local pid = NPCBountyBridge.PlayerId(player)
    local pname = NPCBountyBridge.PlayerName(player)
    for i=1, math.min(#candidates, maxGroups) do
        local item = candidates[i]
        local group = item.group
        group.bountyHunter = true
        group.bountySide = side
        group.bountyState = sideRec.state
        group.bountyAmount = math.floor((tonumber(sideRec.value) or 0) + 0.5)
        group.bountyTargetPlayerId = pid
        group.bountyTargetPlayerName = pname
        group.targetX = math.floor(px)
        group.targetY = math.floor(py)
        group.targetZ = player.getZ and player:getZ() or 0
        group.targetClass = "bounty_hunt"
        group.state = tostring(side) .. "_bounty_hunt"
        group.updatedAt = NPCBountyBridge.NowHours()
        if type(group.members) == "table" then
            for _, member in pairs(group.members) do
                if type(member) == "table" then
                    member.bountyHunter = true
                    member.bountyTargetPlayerId = pid
                    member.bountyTargetPlayerName = pname
                    member.bountySide = side
                    member.bountyState = sideRec.state
                    member.bountyAmount = group.bountyAmount
                end
            end
        end
        gmd.VirtualGroups[item.id] = group
        bbs_updateGroupMarker(gmd, group)
        changed = changed + 1
    end
    if changed > 0 then
        local data = NPCBountyBridge.EnsureData(gmd)
        if data and data.stats then data.stats.hunters = (tonumber(data.stats.hunters) or 0) + changed end
    end
    return changed
end

function NPCBountyServerBridge.ReportHostileAction(player, args)
    if not (NPCBountyBridge and NPCBountyBridge.IsEnabled and NPCBountyBridge.IsEnabled()) then return end
    local gmd = GetNPCModData()
    local victimSide = bbs_side(args and args.victimSide)
    if not victimSide then return end
    local killed = args and args.killed == true
    local sideRec, rec = NPCBountyBridge.ReportHostileAction(gmd, player, victimSide, killed, args)
    if not sideRec or not rec then return end
    bbs_updateBountyMarker(gmd, rec, victimSide, sideRec)
    bbs_sync(player)
    if NPCBountyBridge.IsSideRecordActive(sideRec, NPCBountyBridge.HuntedThreshold()) then
        NPCBountyServerBridge.DispatchHuntersFor(player, victimSide, sideRec)
    end
    if sideRec.lastDelta and sideRec.lastDelta > 0 and sideRec.value >= NPCBountyBridge.WantedThreshold() then
        bbs_halo(player, tostring(rec.playerName or "You") .. " wanted by " .. tostring(victimSide) .. " faction. Bounty " .. tostring(math.floor(sideRec.value + 0.5)) .. ".", 255, 170, 60)
    end
    if TransmitNPCModData then TransmitNPCModData() end
end

function NPCBountyServerBridge.Status(player)
    local gmd = GetNPCModData()
    if NPCBountyBridge and NPCBountyBridge.Decay then NPCBountyBridge.Decay(gmd) end
    bbs_sync(player)
    local payload = NPCBountyBridge and NPCBountyBridge.BuildPayload and NPCBountyBridge.BuildPayload(gmd, player) or nil
    bbs_halo(player, payload and payload.text or "No active bounty.", 255, 225, 120)
end

function NPCBountyServerBridge.Refresh(player)
    local gmd = GetNPCModData()
    local data = NPCBountyBridge and NPCBountyBridge.EnsureData and NPCBountyBridge.EnsureData(gmd) or nil
    if not data or type(data.players) ~= "table" then return end
    NPCBountyBridge.Decay(gmd)
    local pid = tostring(NPCBountyBridge.PlayerId(player) or "")
    local rec = data.players[pid]
    if rec and type(rec.bySide) == "table" then
        for side, sideRec in pairs(rec.bySide) do
            if NPCBountyBridge.IsSideRecordActive(sideRec, 1) then
                bbs_updateBountyMarker(gmd, rec, side, sideRec)
                if NPCBountyBridge.IsSideRecordActive(sideRec, NPCBountyBridge.HuntedThreshold()) then
                    NPCBountyServerBridge.DispatchHuntersFor(player, side, sideRec)
                end
            else
                bbs_removeBountyMarker(gmd, pid, side)
            end
        end
    end
    bbs_sync(player)
    if TransmitNPCModData then TransmitNPCModData() end
end

function NPCBountyServerBridge.OnClientCommand(module, command, player, args)
    if not NPCLegacyContractBridge.IsModule(module, "NPCBounty", "bounty") then return end
    if command == "ReportHostileAction" then
        NPCBountyServerBridge.ReportHostileAction(player, args or {})
    elseif command == "Status" then
        NPCBountyServerBridge.Status(player)
    elseif command == "Refresh" then
        NPCBountyServerBridge.Refresh(player)
    end
end

local function bbs_everyTenMinutes()
    if not (NPCBountyBridge and NPCBountyBridge.IsEnabled and NPCBountyBridge.IsEnabled()) then return end
    local gmd = GetNPCModData()
    if not gmd then return end
    local changed = NPCBountyBridge.Decay(gmd)
    if changed and changed > 0 then
        bbs_syncAll("bounty_decay")
        if TransmitNPCModData then TransmitNPCModData() end
    end
end

function NPCBountyServerBridge.Install()
    if NPCBountyServerBridge._installed then return end
    Events.OnClientCommand.Add(NPCBountyServerBridge.OnClientCommand)
    Events.EveryTenMinutes.Add(bbs_everyTenMinutes)
    NPCBountyServerBridge._installed = true
end

NPCBountyServerBridge.Install()
