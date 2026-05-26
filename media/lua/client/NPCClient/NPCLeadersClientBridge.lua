require "NPCCore/NPCLegacyContractBridge"
NPCLeadersClientBridge = NPCLeadersClientBridge or {}

local NPC_LEADERS_CLIENT_LEGACY_TEXT_PREFIX = NPCLegacyContractBridge.Text.prefix

local function leaders_text(key)
    return getText(NPC_LEADERS_CLIENT_LEGACY_TEXT_PREFIX .. tostring(key or ""))
end

local function leaders_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        local ok, value = pcall(function() return NPCLegacySettingsBridge.GetBool(name, defaultValue == true) end)
        if ok and value ~= nil then return value == true end
    end
    return defaultValue == true
end

local function leaders_player(playerNum)
    return getSpecificPlayer(playerNum or 0) or getPlayer()
end

local function leaders_halo(text, r, g, b)
    local player = getPlayer() or getSpecificPlayer(0)
    if HaloTextHelper and player and text then
        HaloTextHelper.addText(player, tostring(text), r or 255, g or 225, b or 120)
    end
end

function NPCLeadersClientBridge.Status(player)
    player = player or getPlayer() or getSpecificPlayer(0)
    if not player then return end
    sendClientCommand(player, 'NPCLeaders', 'Status', {})
end

function NPCLeadersClientBridge.Refresh(player)
    player = player or getPlayer() or getSpecificPlayer(0)
    if not player then return end
    sendClientCommand(player, 'NPCLeaders', 'Refresh', {})
end

function NPCLeadersClientBridge.OnFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    if test or not leaders_bool("Leader_Enabled", true) then return end
    local player = leaders_player(playerNum)
    if not player then return end
    local root = context:addOption(leaders_text("Menu_FactionLeaders"))
    local menu = context:getNew(context)
    context:addSubMenu(root, menu)
    menu:addOption(leaders_text("Menu_CheckFactionLeaders"), player, NPCLeadersClientBridge.Status)
    menu:addOption(leaders_text("Menu_RefreshLeaderMarkers"), player, NPCLeadersClientBridge.Refresh)
end

function NPCLeadersClientBridge.OnServerCommand(module, command, args)
    if not NPCLegacyContractBridge.IsModule(module, "NPCLeaders", "leaders") then return end
    if command == "Result" and args and args.text then
        leaders_halo(args.text, args.r, args.g, args.b)
    elseif command == "State" and args and args.text then
        leaders_halo(args.text, 255, 225, 120)
        local player = getPlayer() or getSpecificPlayer(0)
        if player then
            local md = player:getModData()
            md.NPCLeadersBridge = args
        end
    end
end

function NPCLeadersClientBridge.Install()
    Events.OnFillWorldObjectContextMenu.Add(NPCLeadersClientBridge.OnFillWorldObjectContextMenu)
    Events.OnServerCommand.Add(NPCLeadersClientBridge.OnServerCommand)
end
