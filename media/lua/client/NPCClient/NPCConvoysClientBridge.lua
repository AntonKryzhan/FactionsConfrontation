-- NPCConvoysClientBridge.lua
-- Context menu + HUD notifications for lightweight supply convoy operations.

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCLegacyGlobalsBridge"
NPCConvoysClientBridge = NPCConvoysClientBridge or {}

local BCVCL_LEGACY_TEXT_PREFIX = NPCLegacyContractBridge.Text.prefix

local function bcvcl_text(key)
    return getText(BCVCL_LEGACY_TEXT_PREFIX .. tostring(key or ""))
end
NPCConvoysClientBridge.active = NPCConvoysClientBridge.active or nil
NPCConvoysClientBridge._syncRequested = NPCConvoysClientBridge._syncRequested or false

local function bcvcl_baseCaptureProvider()
    return NPCBaseCaptureUIBridge or NPCBaseCaptureUI or NPCLegacyGlobalsBridge.Get("BaseCaptureUI")
end

local function bcvcl_settingBool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        local ok, value = pcall(function() return NPCLegacySettingsBridge.GetBool(name, defaultValue == true) end)
        if ok and value ~= nil then return value == true end
    end
    return defaultValue == true
end

local function bcvcl_settingNumber(name, defaultValue, minValue, maxValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        local ok, value = pcall(function() return NPCLegacySettingsBridge.GetNumber(name, defaultValue, minValue, maxValue) end)
        if ok and value ~= nil then return value end
    end
    local value = tonumber(defaultValue) or 0
    if minValue ~= nil and value < minValue then value = minValue end
    if maxValue ~= nil and value > maxValue then value = maxValue end
    return value
end

local function bcvcl_player()
    return getPlayer() or getSpecificPlayer(0)
end

local function bcvcl_halo(text, r, g, b)
    local player = bcvcl_player()
    if HaloTextHelper and player and text then
        HaloTextHelper.addText(player, tostring(text), r or 180, g or 230, b or 255)
    end
end

local function bcvcl_resourceLabel(resource, fallback)
    if resource then
        local key = BCVCL_LEGACY_TEXT_PREFIX .. "Menu_Resource_" .. tostring(resource)
        local label = getText(key)
        if label and label ~= key then return label end
    end
    return tostring(fallback or resource or bcvcl_text("Menu_Cargo"))
end

local function bcvcl_dist(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return math.sqrt(dx * dx + dy * dy)
end

local function bcvcl_nearBase()
    local provider = bcvcl_baseCaptureProvider()
    if provider and provider.FindNearbyBase then
        local ok, base, dist = pcall(function() return provider.FindNearbyBase() end)
        if ok and base then return base, dist end
    end
    return nil, nil
end

local function bcvcl_baseId(base)
    if not base then return nil end
    return base.baseId or base.id
end

local function bcvcl_nearConvoy(player)
    if not player or not NPCDebugMapNPCMarkersBridge or type(NPCDebugMapNPCMarkersBridge.markers) ~= "table" then return nil, nil end
    local px = player.getX and player:getX() or 0
    local py = player.getY and player:getY() or 0
    local radius = bcvcl_settingNumber("Convoy_InteractionRadius", 28, 2, 200)
    local best = nil
    local bestDist = radius + 0.001
    for _, marker in pairs(NPCDebugMapNPCMarkersBridge.markers) do
        if type(marker) == "table" and marker.markerType == "convoy" and marker.x and marker.y and marker.convoyStatus ~= "expired" then
            local d = bcvcl_dist(px, py, marker.x, marker.y)
            if d <= bestDist then
                best = marker
                bestDist = d
            end
        end
    end
    return best, bestDist
end

local function bcvcl_convoyText(convoy)
    if not convoy then return bcvcl_text("Menu_NoActiveConvoyOperation") end
    if convoy.operationText then return tostring(convoy.operationText) end
    local cargo = bcvcl_resourceLabel(convoy.cargoResource, convoy.cargoLabel)
    local status = tostring(convoy.convoyStatus or convoy.status or "active")
    local progress = math.floor(((tonumber(convoy.progress) or 0) * 100) + 0.5)
    if convoy.convoyObjective == "escort" or convoy.objective == "escort" then
        return bcvcl_text("Menu_Escort") .. " " .. cargo .. " " .. bcvcl_text("Menu_ConvoyLower") .. ": " .. tostring(progress) .. "% (" .. status .. ")"
    end
    return bcvcl_text("Menu_Enemy") .. " " .. cargo .. " " .. bcvcl_text("Menu_ConvoyLower") .. ": " .. tostring(progress) .. "% (" .. status .. ")"
end

function NPCConvoysClientBridge.RequestOperation(player, base, objective)
    if not player or not base then return end
    sendClientCommand(player, 'NPCConvoys', 'RequestOperation', {
        baseId = bcvcl_baseId(base),
        objective = objective or "escort"
    })
end

function NPCConvoysClientBridge.CompleteEscort(player)
    if not player then return end
    sendClientCommand(player, 'NPCConvoys', 'CompleteEscort', {})
end

function NPCConvoysClientBridge.RaidConvoy(player, marker)
    if not player then return end
    sendClientCommand(player, 'NPCConvoys', 'RaidConvoy', {convoyId = marker and marker.convoyId or nil})
end

function NPCConvoysClientBridge.OnFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    if test or not bcvcl_settingBool("Convoy_Enabled", true) then return end
    local player = getSpecificPlayer(playerNum) or bcvcl_player()
    if not player then return end

    local nearConvoy = bcvcl_nearConvoy(player)
    if nearConvoy then
        local root = context:addOption(bcvcl_text("Menu_Convoy"))
        local menu = context:getNew(context)
        context:addSubMenu(root, menu)
        menu:addOption(bcvcl_convoyText(nearConvoy), player, function() bcvcl_halo(bcvcl_convoyText(nearConvoy), 180, 230, 255) end)
        if nearConvoy.convoyObjective == "escort" or nearConvoy.friendly == true then
            menu:addOption(bcvcl_text("Menu_CompleteEscortDelivery"), player, NPCConvoysClientBridge.CompleteEscort)
        else
            menu:addOption(bcvcl_text("Menu_RaidConvoy"), player, NPCConvoysClientBridge.RaidConvoy, nearConvoy)
        end
    end

    local base = bcvcl_nearBase()
    if base then
        local root = context:addOption(bcvcl_text("Menu_ConvoyOperations"))
        local menu = context:getNew(context)
        context:addSubMenu(root, menu)
        if NPCConvoysClientBridge.active then
            menu:addOption(bcvcl_convoyText(NPCConvoysClientBridge.active), player, function() bcvcl_halo(bcvcl_convoyText(NPCConvoysClientBridge.active), 180, 230, 255) end)
        else
            menu:addOption(bcvcl_text("Menu_RequestEscortConvoy"), player, NPCConvoysClientBridge.RequestOperation, base, "escort")
            menu:addOption(bcvcl_text("Menu_RequestRaidIntel"), player, NPCConvoysClientBridge.RequestOperation, base, "raid")
        end
    elseif NPCConvoysClientBridge.active then
        local root = context:addOption(bcvcl_text("Menu_ConvoyOperation"))
        local menu = context:getNew(context)
        context:addSubMenu(root, menu)
        menu:addOption(bcvcl_convoyText(NPCConvoysClientBridge.active), player, function() bcvcl_halo(bcvcl_convoyText(NPCConvoysClientBridge.active), 180, 230, 255) end)
    end
end

function NPCConvoysClientBridge.OnServerCommand(module, command, args)
    if not NPCLegacyContractBridge.IsModule(module, "NPCConvoys", "convoys") then return end
    if command == "Active" then
        NPCConvoysClientBridge.active = args
        if args and args.operationText then bcvcl_halo(args.operationText, 140, 240, 160) end
    elseif command == "Clear" then
        NPCConvoysClientBridge.active = nil
    elseif command == "Result" then
        if args and args.text then bcvcl_halo(args.text, args.r, args.g, args.b) end
    end
end

local function bcvcl_onTick()
    if NPCConvoysClientBridge._syncRequested then return end
    local player = bcvcl_player()
    if not player then return end
    NPCConvoysClientBridge._syncRequested = true
    sendClientCommand(player, 'NPCConvoys', 'RequestSync', {})
end

function NPCConvoysClientBridge.Install()
    if NPCConvoysClientBridge._installed then return end
    NPCConvoysClientBridge._installed = true
    Events.OnFillWorldObjectContextMenu.Add(NPCConvoysClientBridge.OnFillWorldObjectContextMenu)
    Events.OnServerCommand.Add(NPCConvoysClientBridge.OnServerCommand)
    Events.OnTick.Add(bcvcl_onTick)
end
