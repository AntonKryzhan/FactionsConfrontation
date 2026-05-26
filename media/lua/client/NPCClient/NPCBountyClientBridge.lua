require "NPCCore/NPCLegacyContractBridge"
NPCBountyClientBridge = NPCBountyClientBridge or {}

local NPC_BOUNTY_CLIENT_LEGACY_TEXT_PREFIX = NPCLegacyContractBridge.Text.prefix

local function bounty_text(key)
    return getText(NPC_BOUNTY_CLIENT_LEGACY_TEXT_PREFIX .. tostring(key or ""))
end

local function bounty_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        local ok, value = pcall(function() return NPCLegacySettingsBridge.GetBool(name, defaultValue == true) end)
        if ok and value ~= nil then return value == true end
    end
    return defaultValue == true
end

local function bounty_player(playerNum)
    return getSpecificPlayer(playerNum or 0) or getPlayer()
end

local function bounty_halo(text, r, g, b)
    local player = getPlayer() or getSpecificPlayer(0)
    if HaloTextHelper and player and text then
        HaloTextHelper.addText(player, tostring(text), r or 255, g or 225, b or 120)
    end
end

function NPCBountyClientBridge.Status(player)
    player = player or getPlayer() or getSpecificPlayer(0)
    if not player then return end
    sendClientCommand(player, 'NPCBounty', 'Status', {})
end

function NPCBountyClientBridge.Refresh(player)
    player = player or getPlayer() or getSpecificPlayer(0)
    if not player then return end
    sendClientCommand(player, 'NPCBounty', 'Refresh', {})
end

function NPCBountyClientBridge.OnFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    if test or not bounty_bool("Bounty_Enabled", true) then return end
    local player = bounty_player(playerNum)
    if not player then return end
    local root = context:addOption(bounty_text("Menu_FactionBounty"))
    local menu = context:getNew(context)
    context:addSubMenu(root, menu)
    menu:addOption(bounty_text("Menu_CheckBountyStatus"), player, NPCBountyClientBridge.Status)
    menu:addOption(bounty_text("Menu_RefreshBountyMarkers"), player, NPCBountyClientBridge.Refresh)
end

function NPCBountyClientBridge.OnServerCommand(module, command, args)
    if not NPCLegacyContractBridge.IsModule(module, "NPCBounty", "bounty") then return end
    if command == "Result" and args and args.text then
        bounty_halo(args.text, args.r, args.g, args.b)
    elseif command == "State" then
        if NPCBountyBridge and NPCBountyBridge.ApplyStatePayload then
            pcall(function() NPCBountyBridge.ApplyStatePayload(getPlayer() or getSpecificPlayer(0), args or {}) end)
        end
        if args and args.text then bounty_halo(args.text, 255, 225, 120) end
    end
end

function NPCBountyClientBridge.Install()
    Events.OnFillWorldObjectContextMenu.Add(NPCBountyClientBridge.OnFillWorldObjectContextMenu)
    Events.OnServerCommand.Add(NPCBountyClientBridge.OnServerCommand)
end
