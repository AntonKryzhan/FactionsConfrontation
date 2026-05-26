-- NPCWorldRulesClientBridge.lua
-- Integration rules debug menu and summary notifications.

require "NPCCore/NPCLegacyContractBridge"

NPCWorldRulesClientBridge = NPCWorldRulesClientBridge or {}

local BWR_LEGACY_TEXT_PREFIX = NPCLegacyContractBridge.Text.prefix

local function bwr_text(key)
    return getText(BWR_LEGACY_TEXT_PREFIX .. tostring(key or ""))
end

local function bwr_player()
    return getPlayer() or getSpecificPlayer(0)
end

local function bwr_halo(text, r, g, b)
    local player = bwr_player()
    if HaloTextHelper and player and text then HaloTextHelper.addText(player, tostring(text), r or 210, g or 220, b or 255) end
end

function NPCWorldRulesClientBridge.RequestSummary(player)
    player = player or bwr_player()
    if not player then return end
    sendClientCommand(player, 'NPCWorldRules', 'Summary', {})
end

function NPCWorldRulesClientBridge.OnFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    if test then return end
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool and not NPCLegacySettingsBridge.GetBool("WorldRules_DebugMenu", true) then return end
    local player = getSpecificPlayer(playerNum) or bwr_player()
    if not player then return end
    local root = context:addOption(bwr_text("Menu_WorldRulesSoftlockGuard"))
    local menu = context:getNew(context)
    context:addSubMenu(root, menu)
    menu:addOption(bwr_text("Menu_CheckIntegrationSummary"), player, NPCWorldRulesClientBridge.RequestSummary)
end

function NPCWorldRulesClientBridge.OnServerCommand(module, command, args)
    if not NPCLegacyContractBridge.IsModule(module, 'NPCWorldRules', 'worldRules') then return end
    if (command == 'Result' or command == 'Summary') and args and args.text then
        bwr_halo(args.text, args.r, args.g, args.b)
    end
end


function NPCWorldRulesClientBridge.Install()
    Events.OnFillWorldObjectContextMenu.Add(NPCWorldRulesClientBridge.OnFillWorldObjectContextMenu)
    Events.OnServerCommand.Add(NPCWorldRulesClientBridge.OnServerCommand)
end
