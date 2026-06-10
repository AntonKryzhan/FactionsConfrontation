-- NPCCheckpointsClientBridge.lua
-- Context menu and notifications for faction road checkpoints.

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCLegacyGlobalsBridge"
pcall(require, "ISUI/ISPanel")
pcall(require, "ISUI/ISUIElement")
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


local function bcpcl_uiVisible(ui)
    if not ui then return false end
    if ui.isReallyVisible then
        local ok, value = pcall(function() return ui:isReallyVisible() end)
        if ok and value ~= nil then return value == true end
    end
    if ui.isVisible then
        local ok, value = pcall(function() return ui:isVisible() end)
        if ok and value ~= nil then return value == true end
    end
    if ui.getIsVisible then
        local ok, value = pcall(function() return ui:getIsVisible() end)
        if ok and value ~= nil then return value == true end
    end
    if ui.javaObject and ui.javaObject.isVisible then
        local ok, value = pcall(function() return ui.javaObject:isVisible() end)
        if ok and value ~= nil then return value == true end
    end
    if ui.visible ~= nil and ui.javaObject then return ui.visible == true end
    return false
end

local function bcpcl_isWorldMapUI(ui)
    if not ui then return false end
    local t = tostring(ui.Type or ui.type or ui.className or "")
    if t == "ISWorldMap" then return true end
    local mt = getmetatable(ui)
    local idx = mt and mt.__index or nil
    local mtName = tostring((type(idx) == "table" and (idx.Type or idx.type or idx.className)) or "")
    if mtName == "ISWorldMap" then return true end
    if ui.mapAPI and ui.character and ui.symbolsUI then return true end
    return false
end

local function bcpcl_worldMapReallyOpen(ui, fromManager)
    if not bcpcl_isWorldMapUI(ui) then return false end
    if ui.isReallyVisible then
        local ok, value = pcall(function() return ui:isReallyVisible() end)
        if ok then return value == true end
    end
    if fromManager == true then return bcpcl_uiVisible(ui) end
    -- The global map singleton can exist with visible=true before it is actually
    -- attached/open. Do not treat that object as open unless Java UI exists too.
    if not ui.javaObject then return false end
    return bcpcl_uiVisible(ui)
end

local function bcpcl_isWorldMapOpen()
    local direct = nil
    if type(_G) == "table" then
        direct = rawget(_G, "ISWorldMap_instance") or rawget(_G, "ISWorldMapInstance")
    end
    if direct and bcpcl_worldMapReallyOpen(direct, false) then return true end

    if UIManager and UIManager.getUI then
        local ok, list = pcall(function() return UIManager.getUI() end)
        if ok and list then
            local size = nil
            if list.size then
                local sOk, sVal = pcall(function() return list:size() end)
                if sOk then size = tonumber(sVal) end
            end
            if size and list.get then
                for i = 0, size - 1 do
                    local gOk, ui = pcall(function() return list:get(i) end)
                    if gOk and bcpcl_worldMapReallyOpen(ui, true) then return true end
                end
            elseif type(list) == "table" then
                for _, ui in pairs(list) do
                    if bcpcl_worldMapReallyOpen(ui, true) then return true end
                end
            end
        end
    end
    return false
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

local function bcpcl_worldToScreen(x, y, z)
    if not (IsoUtils and IsoCamera) then return nil end
    local ok, sx, sy = pcall(function()
        local wx = (tonumber(x) or 0) + 0.5
        local wy = (tonumber(y) or 0) + 0.5
        local wz = tonumber(z) or 0
        local screenX = IsoUtils.XToScreen(wx, wy, wz, 0)
        local screenY = IsoUtils.YToScreen(wx, wy, wz, 0)
        if IsoCamera.getOffX then screenX = screenX - IsoCamera.getOffX() end
        if IsoCamera.getOffY then screenY = screenY - IsoCamera.getOffY() end
        local zoom = 1
        if getCore and getCore() and getCore().getZoom then
            local zOk, zVal = pcall(function() return getCore():getZoom(0) end)
            if zOk and tonumber(zVal) and tonumber(zVal) > 0 then zoom = tonumber(zVal) end
        end
        return screenX / zoom, screenY / zoom
    end)
    if ok then return sx, sy end
    return nil
end

local function bcpcl_checkpointColor(marker)
    local side = tostring(marker and (marker.checkpointSide or marker.factionSide or marker.side) or "")
    if marker and marker.breachActive == true then return 1.0, 0.12, 0.06 end
    if side == "green" then return 0.25, 0.95, 0.25 end
    if side == "blue" then return 0.30, 0.60, 1.0 end
    return 1.0, 0.25, 0.18
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
    -- Stage 364: keep checkpoint interaction context-menu only, but do not expose disguise-specific UI in this pass.
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
    if NPCCheckpointsClientBridge.EnsureZoneOverlay then NPCCheckpointsClientBridge.EnsureZoneOverlay() end
    if NPCCheckpointsClientBridge._syncRequested then return end
    local player = bcpcl_player()
    if not player then return end
    NPCCheckpointsClientBridge._syncRequested = true
    sendClientCommand(player, 'NPCCheckpoints', 'RequestSync', {})
end




-- Stage 394: checkpoint zone drawing must never become an interactive UI layer.
-- Stage 393 fixed a startup AddUI crash by using addToUIManager(), but the
-- full-screen panel still sat above vanilla UI and could eat mouse clicks.
-- Keep the visual zone, but draw it from a render hook through an unattached
-- proxy object so inventory/context/windows remain clickable.
NPCCheckpointsClientBridge.zoneOverlay = nil
NPCCheckpointsClientBridge._zoneOverlayHookInstalled = NPCCheckpointsClientBridge._zoneOverlayHookInstalled or false
NPCCheckpointsClientBridge._zoneDrawProxy = NPCCheckpointsClientBridge._zoneDrawProxy or nil

local function bcpcl_textManager()
    if getTextManager then
        local ok, tm = pcall(function() return getTextManager() end)
        if ok and tm then return tm end
    end
    if TextManager and TextManager.instance then return TextManager.instance end
    return nil
end

local function bcpcl_drawTextCentre(ui, text, x, y, r, g, b, a, font)
    text = tostring(text or "")
    if text == "" then return false end
    x = tonumber(x) or 0
    y = tonumber(y) or 0
    r = tonumber(r) or 1.0
    g = tonumber(g) or 1.0
    b = tonumber(b) or 1.0
    a = tonumber(a) or 1.0
    font = font or UIFont.Small

    local tm = bcpcl_textManager()
    if tm then
        if tm.DrawStringCentre then
            local ok = pcall(function() tm:DrawStringCentre(font, x, y, text, r, g, b, a) end)
            if ok then return true end
            ok = pcall(function() tm:DrawStringCentre(text, x, y, r, g, b, a, font) end)
            if ok then return true end
        end
        if tm.DrawString then
            local tw = 0
            if tm.MeasureStringX then
                local ok, measured = pcall(function() return tm:MeasureStringX(font, text) end)
                if ok then tw = tonumber(measured) or 0 end
            end
            local ok = pcall(function() tm:DrawString(font, x - (tw / 2), y, text, r, g, b, a) end)
            if ok then return true end
            ok = pcall(function() tm:DrawString(x - (tw / 2), y, text, r, g, b, a, font) end)
            if ok then return true end
        end
    end

    if ui and ui.drawTextCentre then
        local ok = pcall(function() ui:drawTextCentre(text, x, y, r, g, b, a, font) end)
        if ok then return true end
    end
    return false
end


local function bcpcl_drawZonePoint(ui, x, y, alpha, r, g, b)
    x = math.floor(tonumber(x) or 0)
    y = math.floor(tonumber(y) or 0)
    alpha = tonumber(alpha) or 0.65
    r = tonumber(r) or 1.0
    g = tonumber(g) or 0.25
    b = tonumber(b) or 0.18

    -- A detached proxy's drawRect can be accepted by Kahlua but still not appear
    -- on some PZ UI passes. TextManager draws are reliable without creating a
    -- clickable full-screen UI layer, so the visible checkpoint zone uses bullets.
    bcpcl_drawTextCentre(ui, "•", x, y - 5, r, g, b, alpha, UIFont.Small)
    return true
end

local function bcpcl_zoneDrawProxy()
    local proxy = NPCCheckpointsClientBridge._zoneDrawProxy
    if proxy and proxy.drawRect then return proxy end
    if ISPanel and ISPanel.new then
        proxy = ISPanel:new(0, 0, 1, 1)
    elseif ISUIElement and ISUIElement.new then
        proxy = ISUIElement:new(0, 0, 1, 1)
    end
    if proxy then
        pcall(function() proxy.background = false end)
        pcall(function() proxy.moveWithMouse = false end)
        pcall(function() proxy.bConsumeMouseEvents = false end)
        pcall(function() proxy.consumeMouseEvents = false end)
        pcall(function() proxy.capture = false end)
        if proxy.initialise then pcall(function() proxy:initialise() end) end
        -- Intentionally do NOT call addToUIManager() here.
        NPCCheckpointsClientBridge._zoneDrawProxy = proxy
    end
    return proxy
end

function NPCCheckpointsClientBridge.RenderZoneOverlay()
    if bcpcl_isWorldMapOpen() then return end
    if not bcpcl_bool("Checkpoint_Enabled", true) then return end
    local player = bcpcl_player()
    if not (player and player.getX and player.getY) then return end
    local proxy = bcpcl_zoneDrawProxy()
    if not proxy then return end
    local core = getCore and getCore() or nil
    local sw = core and core.getScreenWidth and core:getScreenWidth() or 1920
    local sh = core and core.getScreenHeight and core:getScreenHeight() or 1080
    local markers = NPCDebugMapNPCMarkersBridge and NPCDebugMapNPCMarkersBridge.markers or nil
    if type(markers) ~= "table" then return end

    for _, marker in pairs(markers) do
        if type(marker) == "table" and marker.markerType == "checkpoint" and marker.checkpointStatus ~= "removed" and marker.x and marker.y then
            local radius = tonumber(marker.checkpointZoneRadius) or bcpcl_radius()
            local pd = bcpcl_dist(player:getX(), player:getY(), marker.x, marker.y)
            if pd <= radius + 42 then
                local r, g, b = bcpcl_checkpointColor(marker)
                local alpha = marker.breachActive and 0.80 or 0.55
                local lastX, lastY = nil, nil
                for i = 0, 40 do
                    local a = (math.pi * 2) * (i / 40)
                    local wx = (tonumber(marker.x) or 0) + math.cos(a) * radius
                    local wy = (tonumber(marker.y) or 0) + math.sin(a) * radius
                    local sx, sy = bcpcl_worldToScreen(wx, wy, tonumber(marker.z) or 0)
                    if sx and sy then
                        if lastX and lastY then
                            local steps = math.max(1, math.floor(math.max(math.abs(sx - lastX), math.abs(sy - lastY)) / 5))
                            for step = 0, steps do
                                local t = step / steps
                                local x = math.floor(lastX + (sx - lastX) * t)
                                local y = math.floor(lastY + (sy - lastY) * t)
                                if x > -16 and y > -16 and x < sw + 16 and y < sh + 16 then
                                    bcpcl_drawZonePoint(proxy, x, y, alpha, r, g, b)
                                end
                            end
                        end
                        lastX, lastY = sx, sy
                    end
                end
                local cx, cy = bcpcl_worldToScreen(marker.x, marker.y, tonumber(marker.z) or 0)
                if cx and cy then
                    local label = marker.breachActive and "CHECKPOINT BREACH ZONE" or "CHECKPOINT ZONE"
                    bcpcl_drawTextCentre(proxy, label, cx, cy - 70, r, g, b, 0.85, UIFont.Small)
                end
            end
        end
    end
end

function NPCCheckpointsClientBridge.EnsureZoneOverlay()
    if NPCCheckpointsClientBridge._zoneOverlayHookInstalled then return end
    NPCCheckpointsClientBridge._zoneOverlayHookInstalled = true
    if Events and Events.OnPostUIDraw then
        Events.OnPostUIDraw.Add(NPCCheckpointsClientBridge.RenderZoneOverlay)
    elseif Events and Events.OnPreUIDraw then
        Events.OnPreUIDraw.Add(NPCCheckpointsClientBridge.RenderZoneOverlay)
    elseif Events and Events.OnRenderTick then
        Events.OnRenderTick.Add(NPCCheckpointsClientBridge.RenderZoneOverlay)
    else
        NPCCheckpointsClientBridge._zoneOverlayHookInstalled = false
    end
end

function NPCCheckpointsClientBridge.Install()
    if NPCCheckpointsClientBridge._installed then return end
    NPCCheckpointsClientBridge._installed = true
    Events.OnFillWorldObjectContextMenu.Add(NPCCheckpointsClientBridge.OnFillWorldObjectContextMenu)
    Events.OnServerCommand.Add(NPCCheckpointsClientBridge.OnServerCommand)
    NPCCheckpointsClientBridge.EnsureZoneOverlay()
    if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.RegisterTickJob then
        NPCWorkSchedulerBridge.RegisterTickJob("NPCCheckpointsClientBridge.SyncBootstrap", bcpcl_onTick, "ui", 30, 1)
    elseif Events and Events.OnTick then
        Events.OnTick.Add(bcpcl_onTick)
    end
end
