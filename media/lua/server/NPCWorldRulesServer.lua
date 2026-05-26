-- NPCWorldRulesServer.lua
-- Server sync-after-consequence and debug summary for integration rules.

if not isServer() then return end

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCLegacyGlobalsBridge"
NPCWorldRules = NPCWorldRules or NPCLegacyGlobalsBridge.Get("WorldRules")
NPCWorldRulesServer = NPCLegacyGlobalsBridge.InstallAlias("WorldRulesServer", NPCWorldRulesServer, "NPCWorldRulesServer")

local bwr_bountyServer = NPCBountyServer or NPCLegacyGlobalsBridge.Get("BountyServer")
local bwr_bounty = NPCBountyBridge or NPCLegacyGlobalsBridge.Get("Bounty")

local NPC_WORLD_RULES_SERVER_LEGACY_MODULES = {
    worldRules = NPCLegacyContractBridge.Module("worldRules"),
    bounty = NPCLegacyContractBridge.Module("bounty")
}

local NPC_WORLD_RULES_SERVER_LEGACY_COMMANDS = {
    result = "Result",
    state = "State",
    summary = "Summary"
}

local function bwr_gmd()
    if GetNPCModData then return GetNPCModData() end
    local legacyGetModData = _G["Get" .. NPCLegacyContractBridge.Token .. "ModData"]
    if legacyGetModData then return legacyGetModData() end
    return nil
end

local function bwr_halo(player, text, r, g, b)
    if player and text then sendServerCommand(player, NPC_WORLD_RULES_SERVER_LEGACY_MODULES.worldRules, NPC_WORLD_RULES_SERVER_LEGACY_COMMANDS.result, {text=text, r=r or 210, g=g or 220, b=b or 255}) end
end

function NPCWorldRulesServer.SyncAfterConsequence(player, reason, args)
    if not (player and NPCWorldRules and NPCWorldRules.SyncAfterConsequenceEnabled and NPCWorldRules.SyncAfterConsequenceEnabled()) then return end
    reason = tostring(reason or "consequence")
    local gmd = bwr_gmd()

    if bwr_bountyServer and bwr_bountyServer.SyncPlayer then
        pcall(function() bwr_bountyServer.SyncPlayer(player) end)
    elseif bwr_bounty and bwr_bounty.BuildPayload and gmd then
        local ok, payload = pcall(function() return bwr_bounty.BuildPayload(gmd, player) end)
        if ok and payload then sendServerCommand(player, NPC_WORLD_RULES_SERVER_LEGACY_MODULES.bounty, NPC_WORLD_RULES_SERVER_LEGACY_COMMANDS.state, payload) end
    end

    if NPCWorldRules and NPCWorldRules.MarkSync then
        pcall(function() NPCWorldRules.MarkSync(player, reason) end)
    end

    local summary = NPCWorldRules and NPCWorldRules.BuildSummary and NPCWorldRules.BuildSummary(gmd, player) or nil
    if summary then
        sendServerCommand(player, NPC_WORLD_RULES_SERVER_LEGACY_MODULES.worldRules, NPC_WORLD_RULES_SERVER_LEGACY_COMMANDS.summary, {text=summary, reason=reason, args=args})
    end
end

function NPCWorldRulesServer.SyncAll(reason)
    if not (NPCWorldRules and NPCWorldRules.SyncAfterConsequenceEnabled and NPCWorldRules.SyncAfterConsequenceEnabled()) then return end
    if getOnlinePlayers then
        local ok, players = pcall(function() return getOnlinePlayers() end)
        if ok and players and players.size and players.get then
            for i=0, players:size()-1 do
                local p = players:get(i)
                if p then NPCWorldRulesServer.SyncAfterConsequence(p, reason or "sync_all") end
            end
            return
        end
    end
    if getNumActivePlayers and getSpecificPlayer then
        local n = getNumActivePlayers()
        for i=0, n-1 do
            local p = getSpecificPlayer(i)
            if p then NPCWorldRulesServer.SyncAfterConsequence(p, reason or "sync_all") end
        end
    end
end

function NPCWorldRulesServer.Summary(player)
    local gmd = bwr_gmd()
    local text = NPCWorldRules and NPCWorldRules.BuildSummary and NPCWorldRules.BuildSummary(gmd, player) or "World rules summary unavailable."
    sendServerCommand(player, NPC_WORLD_RULES_SERVER_LEGACY_MODULES.worldRules, NPC_WORLD_RULES_SERVER_LEGACY_COMMANDS.summary, {text=text, reason="manual"})
    bwr_halo(player, text, 210, 220, 255)
end

function NPCWorldRulesServer.OnClientCommand(module, command, player, args)
    if not NPCLegacyContractBridge.IsModule(module, "NPCWorldRules", "worldRules") then return end
    if command == 'Summary' or command == 'Refresh' then
        NPCWorldRulesServer.Summary(player)
    end
end

Events.OnClientCommand.Add(NPCWorldRulesServer.OnClientCommand)
