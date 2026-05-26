-- NPCLoyaltyClientBridge.lua
-- Context menu and notifications for mercenary loyalty.

require "NPCCore/NPCLegacyContractBridge"
NPCLoyaltyClientBridge = NPCLoyaltyClientBridge or {}

local NPC_LOYALTY_CLIENT_LEGACY_TEXT_PREFIX = NPCLegacyContractBridge.Text.prefix

local function blc_text(key)
    return getText(NPC_LOYALTY_CLIENT_LEGACY_TEXT_PREFIX .. tostring(key or ""))
end

local function blc_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        local ok, value = pcall(function() return NPCLegacySettingsBridge.GetBool(name, defaultValue == true) end)
        if ok and value ~= nil then return value == true end
    end
    return defaultValue == true
end

local function blc_player(playerNum)
    return getSpecificPlayer(playerNum or 0) or getPlayer()
end

local function blc_halo(text, r, g, b)
    local player = getPlayer() or getSpecificPlayer(0)
    if HaloTextHelper and player and text then
        HaloTextHelper.addText(player, tostring(text), r or 180, g or 230, b or 255)
    end
end

function NPCLoyaltyClientBridge.Status(player)
    player = player or getPlayer() or getSpecificPlayer(0)
    if not player then return end
    sendClientCommand(player, 'NPCLoyalty', 'Status', {})
end

function NPCLoyaltyClientBridge.Refresh(player)
    player = player or getPlayer() or getSpecificPlayer(0)
    if not player then return end
    sendClientCommand(player, 'NPCLoyalty', 'Refresh', {})
end

function NPCLoyaltyClientBridge.OnFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    if test or not blc_bool("Loyalty_Enabled", true) then return end
    local player = blc_player(playerNum)
    if not player then return end
    local root = context:addOption(blc_text("Menu_MercenaryLoyalty"))
    local menu = context:getNew(context)
    context:addSubMenu(root, menu)
    menu:addOption(blc_text("Menu_CheckSquadLoyalty"), player, NPCLoyaltyClientBridge.Status)
    menu:addOption(blc_text("Menu_RefreshLoyaltyMarkers"), player, NPCLoyaltyClientBridge.Refresh)
end

function NPCLoyaltyClientBridge.OnServerCommand(module, command, args)
    if not NPCLegacyContractBridge.IsModule(module, "NPCLoyalty", "loyalty") then return end
    if command == "Result" and args and args.text then
        blc_halo(args.text, args.r, args.g, args.b)
    end
end


function NPCLoyaltyClientBridge.Install()
    Events.OnFillWorldObjectContextMenu.Add(NPCLoyaltyClientBridge.OnFillWorldObjectContextMenu)
    Events.OnServerCommand.Add(NPCLoyaltyClientBridge.OnServerCommand)
end
