-- NPCSignalsClientBridge.lua
-- Context menu for lightweight signal items and field commands.

require "NPCCore/NPCLegacyContractBridge"
NPCSignalsClientBridge = NPCSignalsClientBridge or {}

local NPC_SIGNALS_CLIENT_LEGACY_TEXT_PREFIX = NPCLegacyContractBridge.Text.prefix

local function bsic_text(key)
    return getText(NPC_SIGNALS_CLIENT_LEGACY_TEXT_PREFIX .. tostring(key or ""))
end

local function bsic_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        local ok, value = pcall(function() return NPCLegacySettingsBridge.GetBool(name, defaultValue == true) end)
        if ok and value ~= nil then return value == true end
    end
    return defaultValue == true
end

local function bsic_player(playerNum)
    return getSpecificPlayer(playerNum or 0) or getPlayer()
end

local function bsic_square(worldobjects)
    if NPCCompatibilityBridge and NPCCompatibilityBridge.GetClickedSquare then
        local ok, sq = pcall(function() return NPCCompatibilityBridge.GetClickedSquare() end)
        if ok and sq then return sq end
    end
    if type(worldobjects) == "table" then
        for _, obj in ipairs(worldobjects) do
            if obj and obj.getSquare then
                local ok, sq = pcall(function() return obj:getSquare() end)
                if ok and sq then return sq end
            end
        end
    end
    local player = getPlayer()
    if player and player.getSquare then
        local ok, sq = pcall(function() return player:getSquare() end)
        if ok then return sq end
    end
    return nil
end

local function bsic_halo(text, r, g, b)
    local player = getPlayer() or getSpecificPlayer(0)
    if HaloTextHelper and player and text then
        HaloTextHelper.addText(player, tostring(text), r or 180, g or 230, b or 255)
    end
end

function NPCSignalsClientBridge.Use(player, square, action)
    if not player then player = getPlayer() or getSpecificPlayer(0) end
    if not player then return end
    local args = {action=action}
    if square then
        args.x = square:getX()
        args.y = square:getY()
        args.z = square:getZ()
    elseif player then
        args.x = player:getX()
        args.y = player:getY()
        args.z = player:getZ()
    end
    sendClientCommand(player, 'NPCSignals', 'Use', args)
end

function NPCSignalsClientBridge.History(player)
    if not player then player = getPlayer() or getSpecificPlayer(0) end
    if not player then return end
    sendClientCommand(player, 'NPCSignals', 'History', {})
end

function NPCSignalsClientBridge.OnFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    if test or not bsic_bool("Signal_Enabled", true) then return end
    local player = bsic_player(playerNum)
    if not player then return end
    local square = bsic_square(worldobjects)

    local root = context:addOption(bsic_text("Menu_FieldSignals"))
    local menu = context:getNew(context)
    context:addSubMenu(root, menu)

    menu:addOption(bsic_text("Menu_WhistleRallyBodyguards"), player, NPCSignalsClientBridge.Use, nil, "rally")
    menu:addOption(bsic_text("Menu_SmokeFallBackToMe"), player, NPCSignalsClientBridge.Use, nil, "smoke")
    menu:addOption(bsic_text("Menu_FlareMarkAttackPoint"), player, NPCSignalsClientBridge.Use, square, "attack")
    menu:addOption(bsic_text("Menu_RadioMarkerMarkTarget"), player, NPCSignalsClientBridge.Use, square, "target")
    menu:addOption(bsic_text("Menu_FlagTemporaryPostHere"), player, NPCSignalsClientBridge.Use, square, "post")
    menu:addOption(bsic_text("Menu_RecentFieldSignals"), player, NPCSignalsClientBridge.History)
end

function NPCSignalsClientBridge.OnServerCommand(module, command, args)
    if not NPCLegacyContractBridge.IsModule(module, "NPCSignals", "signals") then return end
    if command == "Result" and args and args.text then
        bsic_halo(args.text, args.r, args.g, args.b)
    end
end


function NPCSignalsClientBridge.Install()
    Events.OnFillWorldObjectContextMenu.Add(NPCSignalsClientBridge.OnFillWorldObjectContextMenu)
    Events.OnServerCommand.Add(NPCSignalsClientBridge.OnServerCommand)
end
