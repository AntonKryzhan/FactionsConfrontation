-- NPCWorldRulesServerBridge.lua
-- Neutral server backend for world-rules sync and integration summaries.

if not isServer() then return end

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCWorldRulesBridge"
require "NPCCore/NPCBountyBridge"
require "NPCServer/NPCBountyServerBridge"

NPCWorldRulesServerBridge = NPCWorldRulesServerBridge or {}

local function bwr_halo(player, text, r, g, b)
    if player and text then sendServerCommand(player, 'NPCWorldRules', 'Result', {text=text, r=r or 210, g=g or 220, b=b or 255}) end
end

function NPCWorldRulesServerBridge.SyncAfterConsequence(player, reason, args)
    if not (player and NPCWorldRulesBridge and NPCWorldRulesBridge.SyncAfterConsequenceEnabled and NPCWorldRulesBridge.SyncAfterConsequenceEnabled()) then return end
    reason = tostring(reason or "consequence")
    local gmd = GetNPCModData and GetNPCModData() or nil

    if NPCBountyServerBridge and NPCBountyServerBridge.SyncPlayer then
        pcall(function() NPCBountyServerBridge.SyncPlayer(player) end)
    elseif NPCBountyBridge and NPCBountyBridge.BuildPayload and gmd then
        local ok, payload = pcall(function() return NPCBountyBridge.BuildPayload(gmd, player) end)
        if ok and payload then sendServerCommand(player, 'NPCBounty', 'State', payload) end
    end

    if NPCWorldRulesBridge and NPCWorldRulesBridge.MarkSync then
        pcall(function() NPCWorldRulesBridge.MarkSync(player, reason) end)
    end

    local summary = NPCWorldRulesBridge and NPCWorldRulesBridge.BuildSummary and NPCWorldRulesBridge.BuildSummary(gmd, player) or nil
    if summary then
        sendServerCommand(player, 'NPCWorldRules', 'Summary', {text=summary, reason=reason, args=args})
    end
end

function NPCWorldRulesServerBridge.SyncAll(reason)
    if not (NPCWorldRulesBridge and NPCWorldRulesBridge.SyncAfterConsequenceEnabled and NPCWorldRulesBridge.SyncAfterConsequenceEnabled()) then return end
    if getOnlinePlayers then
        local ok, players = pcall(function() return getOnlinePlayers() end)
        if ok and players and players.size and players.get then
            for i=0, players:size()-1 do
                local p = players:get(i)
                if p then NPCWorldRulesServerBridge.SyncAfterConsequence(p, reason or "sync_all") end
            end
            return
        end
    end
    if getNumActivePlayers and getSpecificPlayer then
        local n = getNumActivePlayers()
        for i=0, n-1 do
            local p = getSpecificPlayer(i)
            if p then NPCWorldRulesServerBridge.SyncAfterConsequence(p, reason or "sync_all") end
        end
    end
end

function NPCWorldRulesServerBridge.Summary(player)
    local gmd = GetNPCModData and GetNPCModData() or nil
    local text = NPCWorldRulesBridge and NPCWorldRulesBridge.BuildSummary and NPCWorldRulesBridge.BuildSummary(gmd, player) or "World rules summary unavailable."
    sendServerCommand(player, 'NPCWorldRules', 'Summary', {text=text, reason="manual"})
    bwr_halo(player, text, 210, 220, 255)
end

function NPCWorldRulesServerBridge.OnClientCommand(module, command, player, args)
    if not (NPCLegacyContractBridge and NPCLegacyContractBridge.IsModule and NPCLegacyContractBridge.IsModule(module, 'NPCWorldRules', 'worldRules')) then return end
    if command == 'Summary' or command == 'Refresh' then
        NPCWorldRulesServerBridge.Summary(player)
    end
end

function NPCWorldRulesServerBridge.Install()
    if NPCWorldRulesServerBridge._installed then return end
    NPCWorldRulesServerBridge._installed = true
    Events.OnClientCommand.Add(NPCWorldRulesServerBridge.OnClientCommand)
end

NPCWorldRulesServerBridge.Install()
