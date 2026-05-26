-- NPCDisguiseClientBridge.lua
-- Player context menu for faction disguise.

require "NPCCore/NPCLegacyContractBridge"
NPCDisguiseClientBridge = NPCDisguiseClientBridge or {}

local BDC_LEGACY_TEXT_PREFIX = NPCLegacyContractBridge.Text.prefix

local function bdc_text(key)
    return getText(BDC_LEGACY_TEXT_PREFIX .. tostring(key or ""))
end

local function bdc_player()
    return getPlayer() or getSpecificPlayer(0)
end

local function bdc_halo(text, r, g, b)
    local player = bdc_player()
    if HaloTextHelper and player and text then
        HaloTextHelper.addText(player, tostring(text), r or 180, g or 230, b or 255)
    end
end

local function bdc_sideLabel(side)
    local key = BDC_LEGACY_TEXT_PREFIX .. "Side_" .. tostring(side or "none")
    local label = getText(key)
    if label and label ~= key then return label end
    if NPCFactionBridge and NPCFactionBridge.GetSideLabel then return NPCFactionBridge.GetSideLabel(side) end
    return tostring(side or "none")
end

function NPCDisguiseClientBridge.Set(player, side)
    if NPCDisguiseBridge and NPCDisguiseBridge.SetPlayerDisguise then
        NPCDisguiseBridge.SetPlayerDisguise(player, side, "manual_menu")
    end
end

function NPCDisguiseClientBridge.Clear(player)
    if NPCDisguiseBridge and NPCDisguiseBridge.SetPlayerDisguise then
        NPCDisguiseBridge.SetPlayerDisguise(player, nil, "manual_clear")
    end
end

function NPCDisguiseClientBridge.AddMenu(playerNum, context, worldobjects, test)
    if test or not (NPCDisguiseBridge and NPCDisguiseBridge.IsEnabled and NPCDisguiseBridge.IsEnabled()) then return end
    local player = getSpecificPlayer(playerNum) or bdc_player()
    if not player then return end

    local rec = NPCDisguiseBridge.GetPlayerRecord(player)
    local title = bdc_text("Menu_FactionDisguise")
    if rec and rec.side then
        title = title .. ": " .. bdc_sideLabel(rec.side)
        if rec.compromised then title = title .. " (" .. bdc_text("Menu_Compromised") .. ")" end
    else
        title = title .. ": " .. bdc_text("Side_none")
    end

    local root = context:addOption(title)
    local menu = context:getNew(context)
    context:addSubMenu(root, menu)

    menu:addOption(bdc_text("Menu_DisguiseAsRed"), player, NPCDisguiseClientBridge.Set, "red")
    menu:addOption(bdc_text("Menu_DisguiseAsGreen"), player, NPCDisguiseClientBridge.Set, "green")
    menu:addOption(bdc_text("Menu_DisguiseAsBlue"), player, NPCDisguiseClientBridge.Set, "blue")
    menu:addOption(bdc_text("Menu_RemoveDisguise"), player, NPCDisguiseClientBridge.Clear)
    if rec and rec.side then
        local text = bdc_text("Menu_Current") .. ": " .. bdc_sideLabel(rec.side)
        if rec.compromised then text = text .. " / " .. bdc_text("Menu_Compromised") end
        menu:addOption(text, player, function() bdc_halo(text, 180, 230, 255) end)
    end
end

function NPCDisguiseClientBridge.OnServerCommand(module, command, args)
    if not NPCLegacyContractBridge.IsModule(module, "NPCDisguise", "disguise") then return end
    local player = bdc_player()
    if not player then return end
    if command == "State" then
        if NPCDisguiseBridge and NPCDisguiseBridge.ApplyServerPayload then
            NPCDisguiseBridge.ApplyServerPayload(player, args)
        end
        if args and args.side then
            local text = bdc_text("Menu_DisguiseSynced") .. ": " .. bdc_sideLabel(args.side)
            if args.compromised then text = text .. " (" .. bdc_text("Menu_Compromised") .. ")" end
            bdc_halo(text, args.compromised and 255 or 160, args.compromised and 120 or 240, args.compromised and 80 or 160)
        else
            bdc_halo(bdc_text("Menu_DisguiseCleared"), 180, 230, 255)
        end
    end
end

function NPCDisguiseClientBridge.Install()
    if NPCDisguiseClientBridge._installed then return end
    NPCDisguiseClientBridge._installed = true
    Events.OnFillWorldObjectContextMenu.Add(NPCDisguiseClientBridge.AddMenu)
    Events.OnServerCommand.Add(NPCDisguiseClientBridge.OnServerCommand)
end
