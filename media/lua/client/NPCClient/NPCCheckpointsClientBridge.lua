-- NPCCheckpointsClientBridge.lua
-- Context menu and notifications for faction road checkpoints.

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCLegacyGlobalsBridge"
NPCCheckpointsClientBridge = NPCCheckpointsClientBridge or {}

local BCPCL_LEGACY_TEXT_PREFIX = NPCLegacyContractBridge.Text.prefix

local function bcpcl_text(key)
    return getText(BCPCL_LEGACY_TEXT_PREFIX .. tostring(key or ""))
end
NPCCheckpointsClientBridge._syncRequested = NPCCheckpointsClientBridge._syncRequested or false

local function bcpcl_factionDocsClientProvider()
    return NPCFactionDocsClient or NPCFactionDocsClientBridge or NPCLegacyGlobalsBridge.Get("FactionDocsClient")
end

local function bcpcl_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        local ok, value = pcall(function() return NPCLegacySettingsBridge.GetBool(name, defaultValue == true) end)
        if ok and value ~= nil then return value == true end
    end
    return defaultValue == true
end

local function bcpcl_player()
    return getPlayer() or getSpecificPlayer(0)
end

local function bcpcl_clickedSquare(worldobjects)
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
    return nil
end

local function bcpcl_halo(text, r, g, b)
    local player = bcpcl_player()
    if HaloTextHelper and player and text then
        HaloTextHelper.addText(player, tostring(text), r or 180, g or 230, b or 255)
    end
end

local function bcpcl_dist(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return math.sqrt(dx * dx + dy * dy)
end

local function bcpcl_radius()
    if NPCCheckpointsBridge and NPCCheckpointsBridge.InteractionRadius then return NPCCheckpointsBridge.InteractionRadius() end
    return 26
end

local function bcpcl_nearCheckpoint(player, worldobjects)
    if not player or not NPCDebugMapNPCMarkersBridge or type(NPCDebugMapNPCMarkersBridge.markers) ~= "table" then return nil, nil end
    local px = player.getX and player:getX() or 0
    local py = player.getY and player:getY() or 0
    local ax, ay = px, py
    local square = bcpcl_clickedSquare(worldobjects)
    if square and square.getX and square.getY then
        ax, ay = square:getX(), square:getY()
    end
    local radius = bcpcl_radius()
    local playerRadius = radius + 8
    local best = nil
    local bestDist = radius + 0.001
    for _, marker in pairs(NPCDebugMapNPCMarkersBridge.markers) do
        if type(marker) == "table" and marker.markerType == "checkpoint" and marker.x and marker.y and marker.checkpointStatus ~= "removed" then
            local d = bcpcl_dist(ax, ay, marker.x, marker.y)
            local pd = bcpcl_dist(px, py, marker.x, marker.y)
            if d <= bestDist and pd <= playerRadius then
                best = marker
                bestDist = d
            end
        end
    end
    return best, bestDist
end

local function bcpcl_markerText(marker)
    if not marker then return bcpcl_text("Menu_Checkpoint") end
    local rawSide = tostring(marker.checkpointSide or marker.factionSide or marker.side or "faction")
    local sideKey = BCPCL_LEGACY_TEXT_PREFIX .. "Side_" .. rawSide
    local side = getText(sideKey)
    if side == sideKey then side = rawSide end
    local toll = tostring(marker.tollAmount or 0) .. " " .. tostring(marker.tollLabel or marker.tollResource or bcpcl_text("Menu_Supplies"))
    return tostring(side) .. " " .. bcpcl_text("Menu_CheckpointLower") .. " / " .. bcpcl_text("Menu_Toll") .. ": " .. toll
end

function NPCCheckpointsClientBridge.Interact(player, marker, action)
    if not player or not marker then return end
    sendClientCommand(player, 'NPCCheckpoints', 'Interact', {
        checkpointId = marker.checkpointId or marker.id,
        action = action or "request"
    })
end

function NPCCheckpointsClientBridge.OnFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    if test or not bcpcl_bool("Checkpoint_Enabled", true) then return end
    local player = getSpecificPlayer(playerNum) or bcpcl_player()
    if not player then return end
    local marker = bcpcl_nearCheckpoint(player, worldobjects)
    if not marker then return end

    local root = context:addOption(bcpcl_text("Menu_Checkpoint"))
    local menu = context:getNew(context)
    context:addSubMenu(root, menu)
    menu:addOption(bcpcl_markerText(marker), player, function() bcpcl_halo(bcpcl_markerText(marker), 180, 230, 255) end)
    menu:addOption(bcpcl_text("Menu_RequestPassage"), player, NPCCheckpointsClientBridge.Interact, marker, "request")
    menu:addOption(bcpcl_text("Menu_ShowDocuments"), player, NPCCheckpointsClientBridge.Interact, marker, "document")
    menu:addOption(bcpcl_text("Menu_GivePassword"), player, NPCCheckpointsClientBridge.Interact, marker, "password")
    menu:addOption(bcpcl_text("Menu_PayToll"), player, NPCCheckpointsClientBridge.Interact, marker, "pay")
    menu:addOption(bcpcl_text("Menu_BluffWithDisguise"), player, NPCCheckpointsClientBridge.Interact, marker, "bluff")
    local docsClient = bcpcl_factionDocsClientProvider()
    if docsClient and docsClient.RequestStatus then
        menu:addOption(bcpcl_text("Menu_KnownPapersPasswords"), player, docsClient.RequestStatus)
    end
    menu:addOption(bcpcl_text("Menu_ForcePassage"), player, NPCCheckpointsClientBridge.Interact, marker, "force")
end

function NPCCheckpointsClientBridge.OnServerCommand(module, command, args)
    if not NPCLegacyContractBridge.IsModule(module, "NPCCheckpoints", "checkpoints") then return end
    if command == "Result" and args and args.text then
        bcpcl_halo(args.text, args.r, args.g, args.b)
    end
end

local function bcpcl_onTick()
    if NPCCheckpointsClientBridge._syncRequested then return end
    local player = bcpcl_player()
    if not player then return end
    NPCCheckpointsClientBridge._syncRequested = true
    sendClientCommand(player, 'NPCCheckpoints', 'RequestSync', {})
end


function NPCCheckpointsClientBridge.Install()
    Events.OnFillWorldObjectContextMenu.Add(NPCCheckpointsClientBridge.OnFillWorldObjectContextMenu)
    Events.OnServerCommand.Add(NPCCheckpointsClientBridge.OnServerCommand)
    Events.OnTick.Add(bcpcl_onTick)
end
