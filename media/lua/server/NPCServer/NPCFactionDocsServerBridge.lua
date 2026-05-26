-- NPCFactionDocsServerBridge.lua
-- Neutral server-side sync and reward hooks for faction papers and daily passwords.

if not isServer() then return end

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCFactionDocsBridge"

NPCFactionDocsServerBridge = NPCFactionDocsServerBridge or {}

local function bfds_halo(player, text, r, g, b)
    if player and text then sendServerCommand(player, 'NPCFactionDocs', 'Result', {text=text, r=r or 180, g=g or 230, b=b or 255}) end
end

function NPCFactionDocsServerBridge.SendStatus(player)
    if not (NPCFactionDocsBridge and NPCFactionDocsBridge.IsEnabled and NPCFactionDocsBridge.IsEnabled()) then return end
    local gmd = GetNPCModData()
    if NPCFactionDocsBridge.EnsureData then NPCFactionDocsBridge.EnsureData(gmd) end
    bfds_halo(player, NPCFactionDocsBridge.StatusText(gmd, player), 180, 230, 255)
end

function NPCFactionDocsServerBridge.GrantIntelReward(player, side, source)
    if not (NPCFactionDocsBridge and NPCFactionDocsBridge.GrantIntelReward) then return nil end
    local gmd = GetNPCModData()
    local reward = NPCFactionDocsBridge.GrantIntelReward(gmd, player, side, source)
    local text = NPCFactionDocsBridge.DescribeReward and NPCFactionDocsBridge.DescribeReward(reward) or nil
    if text then bfds_halo(player, text, 140, 240, 160) end
    return reward
end

function NPCFactionDocsServerBridge.OnClientCommand(module, command, player, args)
    if not NPCLegacyContractBridge.IsModule(module, "NPCFactionDocs", "factionDocs") then return end
    if command == "RequestStatus" then
        NPCFactionDocsServerBridge.SendStatus(player)
    end
end

function NPCFactionDocsServerBridge.Install()
    if NPCFactionDocsServerBridge._installed then return end
    NPCFactionDocsServerBridge._installed = true
    Events.OnClientCommand.Add(NPCFactionDocsServerBridge.OnClientCommand)
end
