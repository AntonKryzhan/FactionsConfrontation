-- NPCCheckpointsServerBridge.lua
-- Neutral server command layer and marker upkeep for lightweight faction checkpoints.

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

local NPC_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
if not isServer() then return end

require "NPCCore/NPCCheckpointsBridge"
require "NPCCore/NPCFactionDocsBridge"

NPCCheckpointsServerBridge = NPCCheckpointsServerBridge or {}
local function npcserver_setDebugMarker(gmd, marker)
    local runtime = NPCServerRuntime
    local setter = runtime and runtime.SetDebugMarker or NPC_LEGACY_GLOBALS.Get("SetDebugMarker")
    if setter then return setter(gmd, marker) end
    return false
end


local function bcps_halo(player, text, r, g, b)
    if player and text then sendServerCommand(player, 'NPCCheckpoints', 'Result', {text=text, r=r or 180, g=g or 230, b=b or 255}) end
end

local function bcps_say(player, text)
    if player and player.Say and text then pcall(function() player:Say(text) end) end
end

local function bcps_now()
    return NPCCheckpointsBridge and NPCCheckpointsBridge.NowHours and NPCCheckpointsBridge.NowHours() or 0
end

local function bcps_side(value)
    if NPCFactionBridge and NPCFactionBridge.NormalizeSide then return NPCFactionBridge.NormalizeSide(value) end
    value = tostring(value or ""):lower()
    if value == "red" or value == "green" or value == "blue" or value == "black" then return value end
    return nil
end

local function bcps_playerSide(player)
    if NPCFactionBridge and NPCFactionBridge.GetPlayerSide then
        local ok, side = pcall(function() return NPCFactionBridge.GetPlayerSide(player) end)
        if ok and side then return bcps_side(side) or "blue" end
    end
    return "blue"
end

local function bcps_setMarker(gmd, marker)
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

local function bcps_ensure(gmd)
    if not gmd then return nil end
    if not gmd.DebugMapMarkers then gmd.DebugMapMarkers = {} end
    if NPCCheckpointsBridge and NPCCheckpointsBridge.EnsureData then return NPCCheckpointsBridge.EnsureData(gmd) end
    return nil
end

local function bcps_markerFor(cp)
    return NPCCheckpointsBridge and NPCCheckpointsBridge.MakeMarker and NPCCheckpointsBridge.MakeMarker(cp) or nil
end

local function bcps_updateMarker(gmd, cp)
    local marker = bcps_markerFor(cp)
    if marker then bcps_setMarker(gmd, marker) end
end

local function bcps_groupSide(group)
    if not group then return nil end
    return bcps_side(group.factionSide or group.faction or group.side or group.patrolColor)
end

local function bcps_createFromRoadPatrols(gmd, data)
    if not (gmd and data and gmd.VirtualGroups and NPCCheckpointsBridge) then return 0 end
    local created = 0
    for gid, group in pairs(gmd.VirtualGroups) do
        if group and group.roadPatrol and group.x and group.y and not group.checkpointId then
            if not NPCCheckpointsBridge.HasNearby(gmd, group.x, group.y, NPCCheckpointsBridge.MinSpacing()) then
                local side = bcps_groupSide(group)
                if side == "red" or side == "green" then
                    local cp = NPCCheckpointsBridge.MakeCheckpoint(gmd, group.x, group.y, group.z or 0, side, {source="road_patrol", sourceId=gid})
                    if cp then
                        group.checkpointId = cp.id
                        group.checkpointGuard = true
                        gmd.VirtualGroups[gid] = group
                        bcps_updateMarker(gmd, cp)
                        created = created + 1
                        if created >= 2 then break end
                    end
                end
            end
        end
    end
    return created
end

local function bcps_createFallback(gmd, data)
    if not (NPCWorldDirectorServer and NPCWorldDirectorServer.GetRandomRoadPoint and NPCCheckpointsBridge) then return nil end
    for i=1, 12 do
        local point = NPCWorldDirectorServer.GetRandomRoadPoint()
        if point and point.x and point.y and not NPCCheckpointsBridge.HasNearby(gmd, point.x, point.y, NPCCheckpointsBridge.MinSpacing()) then
            local side = (ZombRand and ZombRand(2) == 0) and "red" or "green"
            local cp = NPCCheckpointsBridge.MakeCheckpoint(gmd, point.x, point.y, point.z or 0, side, {source="road"})
            if cp then bcps_updateMarker(gmd, cp) end
            return cp
        end
    end
    return nil
end

function NPCCheckpointsServerBridge.EnsureCheckpoints(force)
    if not (NPCCheckpointsBridge and NPCCheckpointsBridge.IsEnabled and NPCCheckpointsBridge.IsEnabled()) then return 0 end
    local gmd = GetNPCModData()
    local data = bcps_ensure(gmd)
    if not data then return 0 end
    local maxActive = NPCCheckpointsBridge.MaxActive()
    if maxActive <= 0 then return 0 end

    local activeCount = 0
    for _, cp in pairs(data.active or {}) do
        if cp and cp.status ~= "removed" then activeCount = activeCount + 1 end
    end
    if activeCount >= maxActive and not force then return 0 end

    local created = 0
    while activeCount + created < maxActive do
        local made = bcps_createFromRoadPatrols(gmd, data)
        if made <= 0 then
            local cp = bcps_createFallback(gmd, data)
            if cp then made = 1 end
        end
        if made <= 0 then break end
        created = created + made
        if not force and created >= 2 then break end
    end
    if created > 0 then TransmitNPCModData() end
    return created
end

local function bcps_textFor(cp, player)
    if NPCWorldRules and NPCWorldRules.CheckpointStatusText then
        local ok, text = pcall(function() return NPCWorldRules.CheckpointStatusText(GetNPCModData(), player, cp) end)
        if ok and text then return text end
    end
    if not cp then return "Checkpoint" end
    local sideLabel = NPCCheckpointsBridge.GetSideLabel(cp.side or cp.checkpointSide)
    return tostring(sideLabel) .. " checkpoint asks for " .. tostring(cp.tollAmount or 0) .. " " .. tostring(cp.tollLabel or cp.tollResource or "supplies")
end

local function bcps_bountyBlocks(player, cp)
    if not (player and cp and NPCBountyBridge and NPCBountyBridge.IsWantedByFaction) then return false end
    local gmd = GetNPCModData()
    local side = bcps_side(cp.side or cp.checkpointSide)
    if not side then return false end
    return NPCBountyBridge.IsWantedByFaction(gmd, player, side, NPCBountyBridge.CheckpointBlocksAt and NPCBountyBridge.CheckpointBlocksAt() or nil)
end

local function bcps_canPassAsFaction(player, cp)
    if not (player and cp) then return false, "none" end
    local playerSide = bcps_playerSide(player)
    local cpSide = bcps_side(cp.side or cp.checkpointSide)
    if cpSide and playerSide == cpSide then return true, "faction" end
    if NPCDisguiseBridge and NPCDisguiseBridge.CanPassAsSide and NPCDisguiseBridge.CanPassAsSide(player, cpSide) then
        if NPCDisguiseBridge.RollInspection and not NPCDisguiseBridge.RollInspection(player, cpSide) then
            return false, "disguise_failed"
        end
        return true, "disguise"
    end
    return false, "hostile"
end

local function bcps_interact(player, args)
    if not (NPCCheckpointsBridge and NPCCheckpointsBridge.IsEnabled and NPCCheckpointsBridge.IsEnabled()) then return end
    local gmd = GetNPCModData()
    local data = bcps_ensure(gmd)
    if not data then return end

    local cp = NPCCheckpointsBridge.FindCheckpoint(gmd, args and (args.checkpointId or args.id) or nil)
    if not cp then
        bcps_halo(player, "No checkpoint found.", 255, 120, 80)
        return
    end
    if player and player.getX and NPCCheckpointsBridge.Distance(player:getX(), player:getY(), cp.x, cp.y) > NPCCheckpointsBridge.InteractionRadius() + 8 then
        bcps_halo(player, "Move closer to the checkpoint.", 255, 180, 80)
        return
    end

    local action = tostring(args and args.action or "request")
    local ruleDecision = NPCWorldRules and NPCWorldRules.DecideCheckpoint and NPCWorldRules.DecideCheckpoint(gmd, player, cp, action) or nil
    if ruleDecision and ruleDecision.reason == "bounty" and action ~= "force" then
        cp.status = "bounty_alert"
        cp.updatedAt = bcps_now()
        data.stats.denied = (tonumber(data.stats.denied) or 0) + 1
        bcps_updateMarker(gmd, cp)
        if NPCDisguiseBridge and NPCDisguiseBridge.Compromise then pcall(function() NPCDisguiseBridge.Compromise(player, "bounty_checkpoint", cp.side, true) end) end
        bcps_halo(player, ruleDecision.text or "Checkpoint recognizes your bounty. Passage denied.", 255, 70, 50)
        if NPCWorldRulesServer and NPCWorldRulesServer.SyncAfterConsequence then NPCWorldRulesServer.SyncAfterConsequence(player, "checkpoint_bounty_block", {side=cp.side}) end
        TransmitNPCModData()
        return
    elseif action ~= "force" and not ruleDecision and bcps_bountyBlocks(player, cp) then
        cp.status = "bounty_alert"
        cp.updatedAt = bcps_now()
        data.stats.denied = (tonumber(data.stats.denied) or 0) + 1
        bcps_updateMarker(gmd, cp)
        if NPCDisguiseBridge and NPCDisguiseBridge.Compromise then pcall(function() NPCDisguiseBridge.Compromise(player, "bounty_checkpoint", cp.side, true) end) end
        bcps_halo(player, "Checkpoint recognizes your bounty. Passage denied.", 255, 70, 50)
        TransmitNPCModData()
        return
    end

    if NPCCheckpointsBridge.GetPlayerPass(gmd, player, cp) then
        bcps_halo(player, "Checkpoint pass is still valid.", 120, 255, 120)
        return
    end

    if action == "status" then
        bcps_halo(player, bcps_textFor(cp, player), 180, 230, 255)
        return
    elseif action == "document" then
        if NPCFactionDocsBridge and NPCFactionDocsBridge.UseDocumentAtCheckpoint then
            local ok, reason, doc = NPCFactionDocsBridge.UseDocumentAtCheckpoint(gmd, player, cp)
            if ok then
                NPCCheckpointsBridge.GrantPlayerPass(gmd, player, cp, "document")
                cp.status = "document_passed"
                cp.updatedAt = bcps_now()
                bcps_updateMarker(gmd, cp)
                bcps_halo(player, "Documents accepted. You may pass.", 120, 255, 120)
                if NPCWorldRulesServer and NPCWorldRulesServer.SyncAfterConsequence then NPCWorldRulesServer.SyncAfterConsequence(player, "checkpoint_document_pass", {side=cp.side}) end
                TransmitNPCModData()
                return
            end
            if reason == "document_failed" then
                cp.status = "alert"
                cp.updatedAt = bcps_now()
                data.stats.denied = (tonumber(data.stats.denied) or 0) + 1
                bcps_updateMarker(gmd, cp)
                if NPCDisguiseBridge and NPCDisguiseBridge.Compromise then pcall(function() NPCDisguiseBridge.Compromise(player, "bad_documents", cp.side, true) end) end
                bcps_halo(player, "Documents failed inspection. Checkpoint is alerted.", 255, 80, 60)
                if NPCWorldRulesServer and NPCWorldRulesServer.SyncAfterConsequence then NPCWorldRulesServer.SyncAfterConsequence(player, "checkpoint_document_failed", {side=cp.side}) end
                TransmitNPCModData()
                return
            end
        end
        bcps_halo(player, "No valid documents for this checkpoint.", 255, 180, 80)
        return
    elseif action == "password" then
        if NPCFactionDocsBridge and NPCFactionDocsBridge.UsePasswordAtCheckpoint then
            local ok, reason = NPCFactionDocsBridge.UsePasswordAtCheckpoint(gmd, player, cp)
            if ok then
                NPCCheckpointsBridge.GrantPlayerPass(gmd, player, cp, "password")
                cp.status = "password_passed"
                cp.updatedAt = bcps_now()
                bcps_updateMarker(gmd, cp)
                bcps_halo(player, "Password accepted. You may pass.", 120, 255, 120)
                if NPCWorldRulesServer and NPCWorldRulesServer.SyncAfterConsequence then NPCWorldRulesServer.SyncAfterConsequence(player, "checkpoint_password_pass", {side=cp.side}) end
                TransmitNPCModData()
                return
            end
            if reason == "wrong_password" then
                bcps_halo(player, "Password is outdated or wrong.", 255, 180, 80)
                return
            end
        end
        bcps_halo(player, "You do not know this checkpoint password.", 255, 180, 80)
        return
    elseif action == "pay" then
        if NPCCheckpointsBridge.TakePayment(player, cp.tollResource, cp.tollAmount) then
            NPCCheckpointsBridge.GrantPlayerPass(gmd, player, cp, "toll")
            data.stats.tolled = (tonumber(data.stats.tolled) or 0) + 1
            cp.status = "paid"
            cp.updatedAt = bcps_now()
            bcps_updateMarker(gmd, cp)
            bcps_halo(player, "Toll paid. You may pass.", 120, 255, 120)
            bcps_say(player, "Checkpoint paid.")
            if NPCWorldRulesServer and NPCWorldRulesServer.SyncAfterConsequence then NPCWorldRulesServer.SyncAfterConsequence(player, "checkpoint_toll_paid", {side=cp.side}) end
            TransmitNPCModData()
            return
        end
        bcps_halo(player, "Need toll: " .. tostring(cp.tollAmount or 0) .. " " .. tostring(cp.tollLabel or cp.tollResource or "supplies") .. ".", 255, 180, 80)
        return
    elseif action == "bluff" or action == "request" then
        local decision = ruleDecision or (NPCWorldRules and NPCWorldRules.DecideCheckpoint and NPCWorldRules.DecideCheckpoint(gmd, player, cp, action))
        local ok, reason = nil, nil
        if decision then
            ok = decision.allow == true
            reason = decision.reason
        else
            ok, reason = bcps_canPassAsFaction(player, cp)
        end
        if ok then
            NPCCheckpointsBridge.GrantPlayerPass(gmd, player, cp, reason)
            cp.status = reason == "disguise" and "disguise_passed" or "passed"
            cp.updatedAt = bcps_now()
            bcps_updateMarker(gmd, cp)
            bcps_halo(player, (decision and decision.text) or (reason == "disguise" and "Disguise worked. Checkpoint lets you through." or "Checkpoint recognizes you. You may pass."), 120, 255, 120)
            if NPCWorldRulesServer and NPCWorldRulesServer.SyncAfterConsequence then NPCWorldRulesServer.SyncAfterConsequence(player, "checkpoint_pass", {side=cp.side, reason=reason}) end
            TransmitNPCModData()
            return
        end
        if reason == "disguise_failed" then
            cp.status = "alert"
            cp.updatedAt = bcps_now()
            data.stats.denied = (tonumber(data.stats.denied) or 0) + 1
            bcps_updateMarker(gmd, cp)
            bcps_halo(player, (decision and decision.text) or "Inspection failed. Your disguise is compromised.", 255, 80, 60)
            if NPCWorldRulesServer and NPCWorldRulesServer.SyncAfterConsequence then NPCWorldRulesServer.SyncAfterConsequence(player, "checkpoint_disguise_failed", {side=cp.side}) end
            TransmitNPCModData()
            return
        end
        bcps_halo(player, (decision and decision.text) or "Checkpoint blocks the road. Pay toll or leave.", 255, 180, 80)
        return
    elseif action == "force" then
        cp.status = "alert"
        cp.lastForcedAt = bcps_now()
        cp.updatedAt = bcps_now()
        data.stats.forced = (tonumber(data.stats.forced) or 0) + 1
        if NPCDisguiseBridge and NPCDisguiseBridge.Compromise then pcall(function() NPCDisguiseBridge.Compromise(player, "forced_checkpoint", cp.side, true) end) end
        bcps_updateMarker(gmd, cp)
        bcps_halo(player, "You forced the checkpoint. Faction patrols are alerted.", 255, 80, 60)
        bcps_say(player, "Checkpoint forced!")
        if NPCWorldRulesServer and NPCWorldRulesServer.SyncAfterConsequence then NPCWorldRulesServer.SyncAfterConsequence(player, "checkpoint_forced", {side=cp.side}) end
        TransmitNPCModData()
        return
    end
end

function NPCCheckpointsServerBridge.OnClientCommand(module, command, player, args)
    if not NPCLegacyContractBridge.IsModule(module, "NPCCheckpoints", "checkpoints") then return end
    if command == "RequestSync" then
        NPCCheckpointsServerBridge.EnsureCheckpoints(false)
    elseif command == "Interact" then
        bcps_interact(player, args)
    end
end

local function bcps_everyTenMinutes()
    NPCCheckpointsServerBridge.EnsureCheckpoints(false)
end

function NPCCheckpointsServerBridge.Install()
    if NPCCheckpointsServerBridge._installed then return end
    NPCCheckpointsServerBridge._installed = true
    Events.OnClientCommand.Add(NPCCheckpointsServerBridge.OnClientCommand)
    Events.EveryTenMinutes.Add(bcps_everyTenMinutes)
end
