-- NPCWorldRules.lua
-- Central priority and softlock guard layer for high-level faction systems.
-- This file does not own any mechanic; it only decides priority between existing layers.

require "NPCCore/NPCLegacySettingsBridge"
require "NPCCore/NPCFactionBridge"
require "NPCCore/NPCBountyBridge"
require "NPCCore/NPCFactionDocsBridge"
require "NPCCore/NPCDisguiseBridge"
require "NPCCore/NPCCheckpointsBridge"
require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCLegacyContractBridge"

NPCWorldRules = NPCLegacyGlobalsBridge.InstallAlias("WorldRules", NPCWorldRules, "NPCWorldRules")
NPCWorldRules.Version = 1

local NPC_WORLD_RULE_SYNC_FIELDS = NPCLegacyContractBridge.WorldRuleFields

local function bwr_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        local ok, value = pcall(function() return NPCLegacySettingsBridge.GetBool(name, defaultValue == true) end)
        if ok and value ~= nil then return value == true end
    end
    return defaultValue == true
end

local function bwr_num(name, defaultValue, minValue, maxValue)
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

local function bwr_now()
    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then
            local ok, value = pcall(function() return gt:getWorldAgeHours() end)
            if ok and value then return tonumber(value) or 0 end
        end
    end
    return os.time and (os.time() / 3600) or 0
end

local function bwr_side(side)
    if NPCFactionBridge and NPCFactionBridge.NormalizeSide then
        local ok, s = pcall(function() return NPCFactionBridge.NormalizeSide(side) end)
        if ok and s then return s end
    end
    side = tostring(side or ""):lower()
    if side == "red" or side == "green" or side == "blue" or side == "black" then return side end
    return nil
end

local function bwr_sideLabel(side)
    if NPCFactionBridge and NPCFactionBridge.GetSideLabel then
        local ok, label = pcall(function() return NPCFactionBridge.GetSideLabel(side) end)
        if ok and label then return tostring(label) end
    end
    side = bwr_side(side) or tostring(side or "faction")
    return tostring(side)
end

function NPCWorldRules.IsEnabled()
    return bwr_bool("WorldRules_Enabled", true)
end

function NPCWorldRules.WarningEnabled()
    return bwr_bool("WorldRules_SoftlockWarnings", true)
end

function NPCWorldRules.SyncAfterConsequenceEnabled()
    return bwr_bool("WorldRules_SyncAfterConsequence", true)
end

function NPCWorldRules.BountyOverridesDisguise()
    return bwr_bool("WorldRules_BountyOverridesDisguise", true)
end

function NPCWorldRules.DocumentsBlockedByBounty()
    return bwr_bool("WorldRules_DocumentsBlockedByBounty", true)
end

function NPCWorldRules.LeaderPenaltyCooldownHours()
    return bwr_num("WorldRules_LeaderPenaltyCooldownHours", 12, 0, 240)
end

function NPCWorldRules.GetBountyThresholdForCheckpoint()
    if NPCBountyBridge and NPCBountyBridge.CheckpointBlocksAt then
        local ok, value = pcall(function() return NPCBountyBridge.CheckpointBlocksAt() end)
        if ok and value then return value end
    end
    if NPCBountyBridge and NPCBountyBridge.WantedThreshold then return NPCBountyBridge.WantedThreshold() end
    return 30
end

function NPCWorldRules.GetWantedThreshold()
    if NPCBountyBridge and NPCBountyBridge.WantedThreshold then return NPCBountyBridge.WantedThreshold() end
    return 30
end

function NPCWorldRules.GetSideBounty(gmd, player, side)
    if not (NPCBountyBridge and NPCBountyBridge.GetSideRecord) then return nil end
    side = bwr_side(side)
    if not side then return nil end
    local ok, rec = pcall(function() return NPCBountyBridge.GetSideRecord(gmd, player, side) end)
    if ok and type(rec) == "table" then return rec end
    return nil
end

function NPCWorldRules.IsBountyActive(gmd, player, side, threshold)
    if not (NPCBountyBridge and NPCBountyBridge.IsWantedByFaction) then return false, nil end
    side = bwr_side(side)
    if not side then return false, nil end
    threshold = tonumber(threshold) or NPCWorldRules.GetWantedThreshold()
    local ok, active = pcall(function() return NPCBountyBridge.IsWantedByFaction(gmd, player, side, threshold) end)
    local rec = NPCWorldRules.GetSideBounty(gmd, player, side)
    return ok and active == true, rec
end

function NPCWorldRules.DecideAttack(brain, player)
    if not NPCWorldRules.IsEnabled() then return nil end
    if not brain or not player then return {result=false, reason="missing"} end

    local observerSide = NPCFactionBridge and NPCFactionBridge.GetBrainSide and NPCFactionBridge.GetBrainSide(brain) or nil
    observerSide = bwr_side(observerSide)
    local realSide = NPCFactionBridge and NPCFactionBridge.GetPlayerSide and NPCFactionBridge.GetPlayerSide(player) or nil
    realSide = bwr_side(realSide) or "blue"

    if NPCWorldRules.BountyOverridesDisguise() and observerSide then
        local active = NPCBountyBridge and NPCBountyBridge.ShouldFactionHuntPlayer and NPCBountyBridge.ShouldFactionHuntPlayer(observerSide, player, brain)
        if active then
            return {result=true, reason="bounty_overrides_disguise", observerSide=observerSide, targetSide=realSide}
        end
    end

    local targetSide = realSide
    local perceivedSide = nil
    if NPCDisguiseBridge and NPCDisguiseBridge.GetPlayerPerceivedSide then
        local ok, got = pcall(function() return NPCDisguiseBridge.GetPlayerPerceivedSide(player, brain) end)
        if ok then perceivedSide = bwr_side(got) end
        if perceivedSide then targetSide = perceivedSide end
    end

    local hostile = false
    if NPCFactionBridge and NPCFactionBridge.IsEnemySide then
        hostile = NPCFactionBridge.IsEnemySide(observerSide, targetSide)
    end
    return {result=hostile == true, reason=perceivedSide and "perceived_side" or "faction_side", observerSide=observerSide, targetSide=targetSide, realSide=realSide, perceivedSide=perceivedSide}
end

function NPCWorldRules.CanBrainAttackPlayer(brain, player)
    local decision = NPCWorldRules.DecideAttack(brain, player)
    if type(decision) == "table" then return decision.result == true, decision end
    return nil, nil
end

function NPCWorldRules.DecideCheckpoint(gmd, player, cp, action)
    if not NPCWorldRules.IsEnabled() then return nil end
    if not (player and cp) then return {allow=false, blocked=true, reason="missing", text="Checkpoint data is missing."} end
    action = tostring(action or "request")
    local cpSide = bwr_side(cp.side or cp.checkpointSide)
    local playerSide = NPCFactionBridge and NPCFactionBridge.GetPlayerSide and NPCFactionBridge.GetPlayerSide(player) or nil
    playerSide = bwr_side(playerSide) or "blue"

    if action == "force" then
        return {allow=true, reason="force", checkpointSide=cpSide, playerSide=playerSide}
    end

    if NPCCheckpointsBridge and NPCCheckpointsBridge.GetPlayerPass then
        local ok, pass = pcall(function() return NPCCheckpointsBridge.GetPlayerPass(gmd, player, cp) end)
        if ok and pass then
            return {allow=true, reason="existing_pass", checkpointSide=cpSide, playerSide=playerSide, pass=pass, text="Checkpoint pass is still valid."}
        end
    end

    local bountyActive, bountyRec = NPCWorldRules.IsBountyActive(gmd, player, cpSide, NPCWorldRules.GetBountyThresholdForCheckpoint())
    if bountyActive and action ~= "status" then
        local value = bountyRec and math.floor((tonumber(bountyRec.value) or 0) + 0.5) or 0
        local text = "Checkpoint recognizes your bounty. Passage denied."
        if NPCWorldRules.WarningEnabled() then
            text = text .. " Documents, passwords and disguise will not help until the bounty is reduced."
        end
        return {allow=false, blocked=true, reason="bounty", checkpointSide=cpSide, playerSide=playerSide, bountyValue=value, bountyState=bountyRec and bountyRec.state, text=text}
    end

    if action == "document" or action == "password" or action == "pay" or action == "status" then
        return {allow=nil, reason="defer", checkpointSide=cpSide, playerSide=playerSide}
    end

    if cpSide and playerSide == cpSide then
        return {allow=true, reason="faction", checkpointSide=cpSide, playerSide=playerSide, text="Checkpoint recognizes you. You may pass."}
    end

    if NPCDisguiseBridge and NPCDisguiseBridge.CanPassAsSide and NPCDisguiseBridge.CanPassAsSide(player, cpSide) then
        if NPCDisguiseBridge.RollInspection and not NPCDisguiseBridge.RollInspection(player, cpSide) then
            return {allow=false, blocked=true, reason="disguise_failed", checkpointSide=cpSide, playerSide=playerSide, text="Inspection failed. Your disguise is compromised."}
        end
        return {allow=true, reason="disguise", checkpointSide=cpSide, playerSide=playerSide, text="Disguise worked. Checkpoint lets you through."}
    end

    return {allow=false, blocked=true, reason="hostile", checkpointSide=cpSide, playerSide=playerSide, text="Checkpoint blocks the road. Pay toll or leave."}
end

function NPCWorldRules.CheckpointStatusText(gmd, player, cp)
    if not cp then return "Checkpoint" end
    local side = bwr_side(cp.side or cp.checkpointSide)
    local sideLabel = NPCCheckpointsBridge and NPCCheckpointsBridge.GetSideLabel and NPCCheckpointsBridge.GetSideLabel(side) or bwr_sideLabel(side)
    local toll = tostring(cp.tollAmount or 0) .. " " .. tostring(cp.tollLabel or cp.tollResource or "supplies")
    local text = tostring(sideLabel) .. " checkpoint asks for " .. toll
    local bountyActive, bountyRec = NPCWorldRules.IsBountyActive(gmd, player, side, NPCWorldRules.GetBountyThresholdForCheckpoint())
    if bountyActive then
        text = text .. ". WARNING: active bounty " .. tostring(math.floor((tonumber(bountyRec and bountyRec.value) or 0) + 0.5)) .. " blocks papers/password/disguise."
    end
    return text
end

local function bwr_findNearestMarker(gmd, player, markerType, radius)
    if not (gmd and player and player.getX and player.getY and type(gmd.DebugMapMarkers) == "table") then return nil end
    local px, py = player:getX(), player:getY()
    local best, bestDist = nil, tonumber(radius) or 999999
    for _, marker in pairs(gmd.DebugMapMarkers) do
        if type(marker) == "table" and marker.markerType == markerType and marker.x and marker.y then
            local dx = (tonumber(marker.x) or 0) - px
            local dy = (tonumber(marker.y) or 0) - py
            local d = math.sqrt(dx * dx + dy * dy)
            if d <= bestDist then best = marker; bestDist = d end
        end
    end
    return best, bestDist
end

function NPCWorldRules.BuildSummary(gmd, player)
    local parts = {}
    local side = NPCFactionBridge and NPCFactionBridge.GetPlayerSide and NPCFactionBridge.GetPlayerSide(player) or "blue"
    parts[#parts + 1] = "side=" .. tostring(side)

    if NPCDisguiseBridge then
        local disguise = nil
        if NPCDisguiseBridge.GetPlayerRecord then
            local ok, rec = pcall(function() return NPCDisguiseBridge.GetPlayerRecord(player) end)
            if ok and type(rec) == "table" then disguise = rec.disguise or rec end
        end
        if type(disguise) == "table" and disguise.side then
            parts[#parts + 1] = "disguise=" .. tostring(disguise.side) .. (disguise.compromised and ":compromised" or "")
        else
            parts[#parts + 1] = "disguise=none"
        end
    end

    if NPCBountyBridge and NPCBountyBridge.BuildPayload then
        local ok, payload = pcall(function() return NPCBountyBridge.BuildPayload(gmd, player) end)
        parts[#parts + 1] = (ok and payload and payload.text) or "Bounty: unknown"
    end

    if NPCFactionDocsBridge and NPCFactionDocsBridge.StatusText then
        local ok, text = pcall(function() return NPCFactionDocsBridge.StatusText(gmd, player) end)
        if ok and text then parts[#parts + 1] = tostring(text) end
    end

    local cp, cpd = bwr_findNearestMarker(gmd, player, "checkpoint", 5000)
    if cp then parts[#parts + 1] = "nearest checkpoint=" .. tostring(cp.checkpointSide or cp.side) .. " " .. tostring(math.floor(cpd or 0)) .. " tiles" end
    local bm, bmd = bwr_findNearestMarker(gmd, player, "black_market", 5000)
    if bm then parts[#parts + 1] = "nearest market=" .. tostring(bm.blackMarketSide or bm.side) .. " " .. tostring(math.floor(bmd or 0)) .. " tiles" end

    return table.concat(parts, " | ")
end

function NPCWorldRules.MarkSync(player, reason)
    local md = player and player.getModData and player:getModData() or nil
    if md then
        md[NPC_WORLD_RULE_SYNC_FIELDS.lastSyncReason] = reason or "sync"
        md[NPC_WORLD_RULE_SYNC_FIELDS.lastSyncAt] = bwr_now()
    end
end
