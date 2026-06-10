-- NPCDebugMapMarkersBridge.lua
-- Neutral client debug-map bridge.
-- The historical legacy debug-map markers table is kept as a compatibility alias.

require "NPCCore/NPCLegacyGlobalsBridge"

NPCDebugMapMarkersBridge = NPCLegacyGlobalsBridge.InstallAlias("DebugMapMarkers", NPCDebugMapMarkersBridge, "NPCDebugMapMarkersBridge")

-- Debug map markers for legacy item module.
-- Draws current/last known NPC positions over the world map and mini-map without revealing map tiles.

NPCDebugMapMarkersBridge = NPCDebugMapMarkersBridge or {}

NPCDebugMapMarkersBridge.Enabled = true
NPCDebugMapMarkersBridge.MarkerSize = 8
NPCDebugMapMarkersBridge.MaxMarkers = 300
NPCDebugMapMarkersBridge.SyncIntervalMs = 5000
NPCDebugMapMarkersBridge.SyncMoveDelta = 2

NPCDebugMapMarkersBridge._hooksInstalled = NPCDebugMapMarkersBridge._hooksInstalled or {}
NPCDebugMapMarkersBridge._lastSync = NPCDebugMapMarkersBridge._lastSync or 0
NPCDebugMapMarkersBridge._lastSent = NPCDebugMapMarkersBridge._lastSent or {}
NPCDebugMapMarkersBridge._screenStable = NPCDebugMapMarkersBridge._screenStable or {}


local function banditDebugSettingBool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        return NPCLegacySettingsBridge.GetBool(name, defaultValue == true)
    end
    return defaultValue == true
end


local function banditDebugAverageFPS()
    if getAverageFPS then
        local ok, fps = pcall(function() return getAverageFPS() end)
        if ok and tonumber(fps) then return tonumber(fps) end
    end
    return 60
end

local function banditDebugMapLoadLevel()
    if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.GetLoadLevel then
        local ok, level = pcall(function() return NPCWorkSchedulerBridge.GetLoadLevel(false) end)
        if ok and tonumber(level) then return tonumber(level) or 0 end
    end
    local fps = banditDebugAverageFPS()
    if fps > 0 and fps < 30 then return 3 end
    if fps > 0 and fps < 45 then return 2 end
    if fps > 0 and fps < 55 then return 1 end
    return 0
end

local function banditDebugSettingNumber(name, defaultValue, minValue, maxValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        return NPCLegacySettingsBridge.GetNumber(name, defaultValue, minValue, maxValue)
    end
    local value = tonumber(defaultValue) or 0
    if minValue ~= nil and value < minValue then value = minValue end
    if maxValue ~= nil and value > maxValue then value = maxValue end
    return value
end

local function banditDebugIsMiniMap(ui)
    if not ui then return false end
    local name = tostring(ui.Type or ui.type or "")
    if string.find(name, "MiniMap") then return true end
    if ISMiniMapInner and instanceof and instanceof(ui, "ISMiniMapInner") then return true end
    if ISMiniMap and instanceof and instanceof(ui, "ISMiniMap") then return true end
    return false
end

local function banditDebugShouldRender(ui, isMiniMap)
    if not banditDebugSettingBool("Debug_MapMarkersEnabled", true) then return false end
    if not banditDebugSettingBool("Debug_NPCMarkersEnabled", true) then return false end
    if isMiniMap == true or banditDebugIsMiniMap(ui) then
        return banditDebugSettingBool("Debug_MiniMapMarkersEnabled", false)
    end
    return banditDebugSettingBool("Debug_WorldMapMarkersEnabled", true)
end

local function banditDebugSafeCall(defaultValue, fn)
    local ok, result = pcall(fn)
    if ok then return result end
    return defaultValue
end

local function banditDebugGetMapAPI(mapUI)
    if not mapUI then return nil end

    if mapUI.mapAPI then return mapUI.mapAPI end
    if mapUI.javaObject and mapUI.javaObject.getAPIv1 then
        return banditDebugSafeCall(nil, function() return mapUI.javaObject:getAPIv1() end)
    end
    if mapUI.mapObj and mapUI.mapObj.getAPIv1 then
        return banditDebugSafeCall(nil, function() return mapUI.mapObj:getAPIv1() end)
    end
    if mapUI.map and mapUI.map.getAPIv1 then
        return banditDebugSafeCall(nil, function() return mapUI.map:getAPIv1() end)
    end

    return nil
end

local function banditDebugWorldToUI(mapAPI, x, y)
    if not mapAPI then return nil, nil end

    local ok, ux, uy = pcall(function()
        return mapAPI:worldToUIX(x, y), mapAPI:worldToUIY(x, y)
    end)
    if ok and ux and uy then return ux, uy end

    ok, ux, uy = pcall(function()
        return mapAPI:worldToUIX(x), mapAPI:worldToUIY(y)
    end)
    if ok and ux and uy then return ux, uy end

    ok, ux, uy = pcall(function()
        return mapAPI:worldToScreenX(x, y), mapAPI:worldToScreenY(x, y)
    end)
    if ok and ux and uy then return ux, uy end

    return nil, nil
end


local function banditDebugNowMs()
    if getTimestampMs then
        local ok, value = pcall(function() return getTimestampMs() end)
        if ok and value then return tonumber(value) or 0 end
    end
    if os and os.time then return os.time() * 1000 end
    return 0
end

local function banditDebugStabilizeScreenPosition(pos, x, y, isMiniMap)
    if not pos or not pos.id or not x or not y then
        return x and math.floor(x + 0.5) or x, y and math.floor(y + 0.5) or y
    end

    local key = tostring(pos.id) .. (isMiniMap == true and ":mini" or ":world")
    local cache = NPCDebugMapMarkersBridge._screenStable
    local item = cache and cache[key] or nil
    local rx = math.floor((tonumber(x) or 0) + 0.5)
    local ry = math.floor((tonumber(y) or 0) + 0.5)

    if item then
        local dx = math.abs(rx - (tonumber(item.x) or rx))
        local dy = math.abs(ry - (tonumber(item.y) or ry))
        if dx <= 1 and dy <= 1 then
            rx = item.x
            ry = item.y
        end
    end

    if cache then
        item = item or {}
        item.x = rx
        item.y = ry
        item.t = banditDebugNowMs()
        cache[key] = item
    end
    return rx, ry
end

local function banditDebugGetWidth(ui)
    if ui and ui.getWidth then
        return banditDebugSafeCall(ui.width or 0, function() return ui:getWidth() end)
    end
    return ui and ui.width or 0
end

local function banditDebugGetHeight(ui)
    if ui and ui.getHeight then
        return banditDebugSafeCall(ui.height or 0, function() return ui:getHeight() end)
    end
    return ui and ui.height or 0
end

local function banditDebugShapeRect(ui, x, y, w, h, a, r, g, b)
    if not ui or not ui.drawRect then return end
    ui:drawRect(x, y, w, h, a, r, g, b)
end

local function banditDebugDrawDiamond(ui, cx, cy, size, a, r, g, b)
    local half = math.max(2, math.floor(size / 2))
    for i = 0, half do
        local span = math.max(1, half - math.abs(i - half))
        banditDebugShapeRect(ui, cx - span, cy - half + i, span * 2, 1, a, r, g, b)
    end
    for i = 1, half do
        local span = math.max(1, half - i)
        banditDebugShapeRect(ui, cx - span, cy + i, span * 2, 1, a, r, g, b)
    end
end

local function banditDebugDrawTriangle(ui, cx, cy, size, a, r, g, b)
    local half = math.max(2, math.floor(size / 2))
    for i = 0, half do
        local span = math.max(1, i + 1)
        banditDebugShapeRect(ui, cx - span, cy - half + i, span * 2, 1, a, r, g, b)
    end
end

local function banditDebugDrawPatrolLetter(ui, cx, cy)
    if not ui then return end

    if ui.drawTextCentre then
        pcall(function()
            ui:drawTextCentre("P", cx, cy - 5, 0, 0, 0, 1.0, UIFont.Small)
        end)
        pcall(function()
            ui:drawTextCentre("P", cx, cy - 6, 1, 1, 1, 0.95, UIFont.Small)
        end)
        return
    end

    banditDebugShapeRect(ui, cx - 2, cy - 4, 1, 8, 1.0, 1, 1, 1)
    banditDebugShapeRect(ui, cx - 1, cy - 4, 4, 1, 1.0, 1, 1, 1)
    banditDebugShapeRect(ui, cx + 2, cy - 3, 1, 3, 1.0, 1, 1, 1)
    banditDebugShapeRect(ui, cx - 1, cy, 4, 1, 1.0, 1, 1, 1)
end

local function banditDebugIsNonZombieThreatKind(kind)
    if not kind then return false end
    kind = string.lower(tostring(kind))
    return kind ~= "" and kind ~= "zombie" and kind ~= "zed" and kind ~= "undead"
end

local function banditDebugIsCombatState(state)
    if not state then return false end
    state = tostring(state)
    return state == "road_battle"
        or state == "Attack"
        or state == "EmergencyDefense"
        or state == "MeleeFallback"
        or state == "KeepDistance"
        or state == "ReloadCover"
        or state == "SearchEnemy"
end

local function banditDebugIsInBattle(pos)
    if not pos then return false end
    if pos.inBattle or pos.virtualBattle then return true end
    if pos.battleId then return true end
    if pos.state == "road_battle" or pos.order == "road_battle" then return true end

    local threatKind = pos.targetKind or pos.fsmTargetKind
    if banditDebugIsNonZombieThreatKind(threatKind) and (pos.targetId or pos.fsmTargetId or banditDebugIsCombatState(pos.state) or banditDebugIsCombatState(pos.fsmState)) then
        return true
    end

    return false
end

local function banditDebugDrawBattleIconFallback(ui, ox, oy, iconSize)
    for i = -iconSize, iconSize do
        banditDebugShapeRect(ui, ox + i, oy - i, 1, 1, 1.0, 0.95, 0.95, 0.95)
        banditDebugShapeRect(ui, ox + i, oy + i, 1, 1, 1.0, 0.95, 0.95, 0.95)
    end

    banditDebugShapeRect(ui, ox - 1, oy + iconSize - 1, 3, 3, 1.0, 0.70, 0.52, 0.22)
    banditDebugShapeRect(ui, ox - 1, oy - iconSize - 2, 3, 3, 1.0, 0.70, 0.52, 0.22)
    banditDebugShapeRect(ui, ox - iconSize - 2, oy - 1, 3, 3, 1.0, 0.70, 0.52, 0.22)
    banditDebugShapeRect(ui, ox + iconSize - 1, oy - 1, 3, 3, 1.0, 0.70, 0.52, 0.22)
end

local function banditDebugDrawBattleIcon(ui, cx, cy, size)
    if not ui then return end

    local iconSize = math.max(4, math.floor((size or 4) / 2) + 2)
    local ox = math.floor(cx + iconSize + 1)
    local oy = math.floor(cy - iconSize - 1)

    banditDebugShapeRect(ui, ox - iconSize - 1, oy - iconSize - 1, iconSize * 2 + 2, iconSize * 2 + 2, 0.78, 0, 0, 0)

    if ui.drawTextCentre then
        local ok = pcall(function()
            ui:drawTextCentre("⚔", ox, oy - 7, 0, 0, 0, 1.0, UIFont.Small)
            ui:drawTextCentre("⚔", ox, oy - 8, 1, 1, 1, 1.0, UIFont.Small)
        end)
        if ok then return end
    end

    banditDebugDrawBattleIconFallback(ui, ox, oy, iconSize)
end

local function banditDebugDrawTextCentre(ui, text, x, y, r, g, b, a, font)
    if not (ui and ui.drawTextCentre and text) then return end
    text = tostring(text or "")
    if text == "" then return end
    local ok = pcall(function() ui:drawTextCentre(text, x, y, r, g, b, a, font) end)
    if ok then return end
    pcall(function() ui:drawTextCentre(text, x, y, r, g, b, font) end)
end

local function banditDebugCleanDisplayLabel(label)
    if label == nil then return nil end
    local text = tostring(label or "")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    if text == "" or text == "nil" or text == "false" then return nil end
    local lower = string.lower(text)
    if string.match(text, "^P%d+%s+[%w_%-]+$") or string.match(text, "^BBC%d+$") or string.match(text, "^WG[%w_%-]*$") or string.match(text, "^CP[%w_%-]*$") or string.match(text, "^SG[%w_%-]*$") then return nil end
    text = string.gsub(text, "%s+P%d+%s+[%w_%-]+$", "")
    text = string.gsub(text, "%s+BBC%d+$", "")
    text = string.gsub(text, "%s+WG[%w_%-]*$", "")
    text = string.gsub(text, "%s+CP[%w_%-]*$", "")
    text = string.gsub(text, "%s+SG[%w_%-]*$", "")
    text = string.gsub(text, "%s+[%w_%-]*%d+$", "")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    lower = string.lower(text)
    if text == "" then return nil end
    if string.match(lower, "^npc group%s*") or lower == "patrol" or lower == "road patrol" or lower == "checkpoint patrol" then return nil end
    return text
end

local function banditDebugSideLabel(pos)
    local side = pos and (pos.factionSide or pos.faction or pos.side or pos.patrolColor or pos.owner or pos.captureTeam) or nil
    if NPCFactionBridge and NPCFactionBridge.NormalizeSide then
        side = NPCFactionBridge.NormalizeSide(side)
    end
    side = tostring(side or "")
    if side == "red" then return "Red" end
    if side == "green" then return "Green" end
    if side == "blue" then return "Blue" end
    if side == "black_market" then return "Blue" end
    if side == "black" then return "Black" end
    if pos and pos.hostile then return "Red" end
    return "Green"
end

local function banditDebugFallbackDisplayLabel(pos)
    local sideLabel = banditDebugSideLabel(pos)
    if pos and (pos.mercenaryHired or pos.mercenary or pos.mercenarySquad) then return "Blue mercenaries" end
    if pos and (pos.checkpointId or pos.targetClass == "checkpoint_road_patrol" or pos.state == "checkpoint_patrol") then return sideLabel .. " checkpoint patrol" end
    if pos and pos.roadPatrol then return sideLabel .. " road patrol" end
    if pos and (pos.homeBaseId or pos.baseId or pos.targetClass == "base" or pos.state == "base_patrol") then return sideLabel .. " base patrol" end
    return sideLabel .. " patrol"
end

local function banditDebugDrawMarkerShape(ui, pos, cx, cy, size, r, g, b)
    if pos and pos.roadPatrol then
        if pos.hostile then
            banditDebugDrawTriangle(ui, cx, cy, size + 1, 0.92, r, g, b)
        else
            banditDebugDrawDiamond(ui, cx, cy, size + 1, 0.92, r, g, b)
        end
        if ui.drawRectBorder then
            ui:drawRectBorder(cx - size, cy - size, size * 2, size * 2, 0.95, 0, 0, 0)
        end
        banditDebugDrawPatrolLetter(ui, cx, cy)
        if banditDebugIsInBattle(pos) then
            banditDebugDrawBattleIcon(ui, cx, cy, size)
        end
        return
    end

    banditDebugShapeRect(ui, cx - size, cy - size, size * 2, size * 2, 0.85, r, g, b)
    if ui.drawRectBorder then
        ui:drawRectBorder(cx - size - 1, cy - size - 1, size * 2 + 2, size * 2 + 2, 1.0, 0, 0, 0)
    end
    if banditDebugIsInBattle(pos) then
        banditDebugDrawBattleIcon(ui, cx, cy, size)
    end
end

local function banditDebugReadBrainPosition(brain)
    if not brain then return nil end

    if brain.debugCoords and brain.debugCoords.x and brain.debugCoords.y then
        return brain.debugCoords.x, brain.debugCoords.y, brain.debugCoords.z or 0
    end

    if brain.bornCoords and brain.bornCoords.x and brain.bornCoords.y then
        return brain.bornCoords.x, brain.bornCoords.y, brain.bornCoords.z or 0
    end

    return nil
end

function NPCDebugMapMarkersBridge.GetPositions()
    local ret = {}

    local gmd = GetNPCModData and GetNPCModData() or nil
    if gmd and gmd.Queue then
        for id, brain in pairs(gmd.Queue) do
            local x, y, z = banditDebugReadBrainPosition(brain)
            if x and y then
                ret[id] = {
                    id = id,
                    uid = brain.uid,
                    x = x,
                    y = y,
                    z = z or 0,
                    name = brain.fullname,
                    clan = brain.clan,
                    hostile = brain.hostile,
                    factionSide = brain.factionSide,
                    faction = brain.faction,
                    side = brain.side,
                    factionState = brain.factionState,
                    state = brain.sim and brain.sim.state or nil,
                    order = brain.sim and brain.sim.order or nil,
                    fireMode = brain.sim and brain.sim.fireMode or brain.order and brain.order.fireMode or nil,
                    targetId = brain.targetId or brain.fsm and brain.fsm.targetId or nil,
                    targetKind = brain.targetKind or brain.fsm and brain.fsm.targetKind or nil,
                    targetDist = brain.targetDist or brain.fsm and brain.fsm.targetDist or nil,
                    fsmState = brain.fsm and brain.fsm.state or nil,
                    fsmTargetId = brain.fsm and brain.fsm.targetId or nil,
                    fsmTargetKind = brain.fsm and brain.fsm.targetKind or nil,
                    stuck = brain.watchdog and brain.watchdog.stuck or false,
                    roadPatrol = brain.roadPatrol or false,
                    patrolColor = brain.patrolColor or nil,
                    inBattle = brain.inBattle or brain.virtualBattle or false,
                    battleId = brain.battleId or nil
                }
            end
        end
    end

    if NPCZombieCacheBridge and NPCZombieCacheBridge.CacheLightB then
        for id, light in pairs(NPCZombieCacheBridge.CacheLightB) do
            if light and light.x and light.y then
                local brain = light.brain
                ret[id] = {
                    id = id,
                    uid = brain and brain.uid or nil,
                    x = light.x,
                    y = light.y,
                    z = light.z or 0,
                    name = brain and brain.fullname or nil,
                    clan = brain and brain.clan or nil,
                    hostile = brain and brain.hostile or false,
                    factionSide = brain and brain.factionSide or nil,
                    faction = brain and brain.faction or nil,
                    side = brain and brain.side or nil,
                    factionState = brain and brain.factionState or nil,
                    state = brain and brain.sim and brain.sim.state or nil,
                    order = brain and brain.sim and brain.sim.order or nil,
                    fireMode = brain and brain.sim and brain.sim.fireMode or brain and brain.order and brain.order.fireMode or nil,
                    targetId = brain and (brain.targetId or brain.fsm and brain.fsm.targetId) or nil,
                    targetKind = brain and (brain.targetKind or brain.fsm and brain.fsm.targetKind) or nil,
                    targetDist = brain and (brain.targetDist or brain.fsm and brain.fsm.targetDist) or nil,
                    fsmState = brain and brain.fsm and brain.fsm.state or nil,
                    fsmTargetId = brain and brain.fsm and brain.fsm.targetId or nil,
                    fsmTargetKind = brain and brain.fsm and brain.fsm.targetKind or nil,
                    stuck = brain and brain.watchdog and brain.watchdog.stuck or false,
                    roadPatrol = brain and brain.roadPatrol or false,
                    patrolColor = brain and brain.patrolColor or nil,
                    inBattle = brain and (brain.inBattle or brain.virtualBattle) or false,
                    battleId = brain and brain.battleId or nil
                }
            end
        end
    end

    return ret
end


local function banditDebugAddAuthoritativeNpcCandidate(candidates, value)
    if value == nil then return end
    local key = tostring(value)
    if key == "" or key == "nil" then return end

    candidates[#candidates + 1] = key
    if string.sub(key, 1, 4) == "npc:" then
        candidates[#candidates + 1] = string.sub(key, 5)
    else
        candidates[#candidates + 1] = "npc:" .. key
    end
end

local function banditDebugHasAuthoritativeNpcMarker(pos)
    if not pos then return false end
    if not (NPCDebugMapNPCMarkersBridge and NPCDebugMapNPCMarkersBridge.markers) then return false end

    local candidates = {}
    banditDebugAddAuthoritativeNpcCandidate(candidates, pos.id)
    banditDebugAddAuthoritativeNpcCandidate(candidates, pos.runtimeId)
    banditDebugAddAuthoritativeNpcCandidate(candidates, pos.uid)
    banditDebugAddAuthoritativeNpcCandidate(candidates, pos.persistentId)
    banditDebugAddAuthoritativeNpcCandidate(candidates, pos.groupId)
    banditDebugAddAuthoritativeNpcCandidate(candidates, pos.worldGroupId)

    for _, key in ipairs(candidates) do
        local marker = NPCDebugMapNPCMarkersBridge.markers[key]
        if marker and (marker.markerType == "npc" or marker.markerType == "group") and marker.dead ~= true and marker.stale ~= true and marker.lastSeen ~= true then
            return true
        end
    end

    local px = tonumber(pos.x)
    local py = tonumber(pos.y)
    if px and py then
        for _, marker in pairs(NPCDebugMapNPCMarkersBridge.markers) do
            if marker and marker.markerType == "group" and marker.dead ~= true and marker.stale ~= true and marker.lastSeen ~= true then
                local mx = tonumber(marker.preciseX or marker.x)
                local my = tonumber(marker.preciseY or marker.y)
                if mx and my then
                    local dx = mx - px
                    local dy = my - py
                    if dx * dx + dy * dy <= 16 then return true end
                end
            end
        end
    end

    return false
end

local function banditDebugFactionColor(pos)
    local side = pos and (pos.factionSide or pos.faction or pos.side or pos.patrolColor) or nil
    if NPCFactionBridge and NPCFactionBridge.NormalizeSide then
        side = NPCFactionBridge.NormalizeSide(side)
    end
    if side == "red" then return 1.0, 0.15, 0.15 end
    if side == "green" then return 0.15, 0.85, 0.25 end
    if side == "black_market" then return 0.70, 0.25, 1.0 end
    if side == "blue" then return 0.15, 0.55, 1.0 end
    if side == "black" then return 0.02, 0.02, 0.02 end
    if pos and pos.hostile then return 1.0, 0.15, 0.15 end
    return 0.15, 0.85, 0.25
end

local function banditDebugMarkerImportance(pos, isMiniMap)
    if not pos then return 0 end
    local score = 0
    if banditDebugIsInBattle(pos) then score = score + 9000 end
    if pos.spy or pos.spyDefected or ((tonumber(pos.spyCount) or 0) > 0) then score = score + 8200 end
    if pos.mercenaryHired or pos.hired or pos.isPlayerGuard then score = score + 7600 end
    if pos.stuck then score = score + 5000 end
    if pos.roadPatrol then score = score + 1200 end
    if pos.state then score = score + 500 end
    return score
end

function NPCDebugMapMarkersBridge.Render(mapUI, isMiniMap)
    if not NPCDebugMapMarkersBridge.Enabled then return end
    if not banditDebugShouldRender(mapUI, isMiniMap == true) then return end
    if isServer and isServer() then return end

    local mapAPI = banditDebugGetMapAPI(mapUI)
    if not mapAPI then return end

    local width = banditDebugGetWidth(mapUI)
    local height = banditDebugGetHeight(mapUI)
    if width <= 0 or height <= 0 then return end

    local loadLevel = banditDebugMapLoadLevel()
    if loadLevel >= 2 and not banditDebugSettingBool("Debug_MapRuntimeEntityMarkersUnderLoad", false) then
        return
    end

    local markerSize = NPCDebugMapMarkersBridge.MarkerSize
    local halfSize = markerSize / 2
    local maxMarkers
    if isMiniMap == true or banditDebugIsMiniMap(mapUI) then
        maxMarkers = banditDebugSettingNumber("Debug_MaxMiniMapMarkers", 90, 0, 2000)
    else
        maxMarkers = banditDebugSettingNumber("Debug_MaxWorldMapMarkers", 900, 0, 5000)
    end
    if loadLevel >= 3 then
        maxMarkers = math.min(maxMarkers, 45)
    elseif loadLevel >= 2 then
        maxMarkers = math.min(maxMarkers, 90)
    elseif loadLevel >= 1 then
        maxMarkers = math.min(maxMarkers, 160)
    end
    if maxMarkers <= 0 then return end
    local suppressLabels = loadLevel >= 1 and not banditDebugSettingBool("Debug_MapLabelsUnderLoad", false)

    local visible = {}
    for _, pos in pairs(NPCDebugMapMarkersBridge.GetPositions()) do
        if not banditDebugHasAuthoritativeNpcMarker(pos) then
            local ux, uy = banditDebugWorldToUI(mapAPI, pos.x, pos.y)
            if ux and uy then
                ux, uy = banditDebugStabilizeScreenPosition(pos, ux, uy, isMiniMap == true)
                local margin = isMiniMap == true and math.max(markerSize, 36) or math.max(markerSize, 96)
                if ux >= -margin and uy >= -margin and ux <= width + margin and uy <= height + margin then
                    pos._screenX = ux
                    pos._screenY = uy
                    pos._importance = banditDebugMarkerImportance(pos, isMiniMap == true)
                    table.insert(visible, pos)
                end
            end
        end
    end

    if banditDebugSettingBool("Debug_SortMarkersByImportance", true) then
        table.sort(visible, function(a, b)
            return (tonumber(a._importance) or 0) > (tonumber(b._importance) or 0)
        end)
    end

    local count = 0
    for _, pos in ipairs(visible) do
        if count >= maxMarkers then break end
        local ux, uy = pos._screenX, pos._screenY
        if ux and uy then
            local r, g, b = banditDebugFactionColor(pos)
            if pos.stuck then
                r, g, b = 1.0, 0.85, 0.10
            end

            banditDebugDrawMarkerShape(mapUI, pos, ux, uy, halfSize, r, g, b)

            local label = banditDebugCleanDisplayLabel(pos.displayName) or banditDebugCleanDisplayLabel(pos.name) or banditDebugCleanDisplayLabel(pos.clan) or banditDebugFallbackDisplayLabel(pos)
            -- Keep debug-map entities to one readable name. State/order/fire-mode
            -- markers still drive color/icons elsewhere and should not stack as
            -- extra text lines over the global-map group marker.
            if not suppressLabels and markerSize >= 8 and mapUI.drawTextCentre then
                banditDebugDrawTextCentre(mapUI, label, ux, uy + markerSize, 1, 1, 1, 0.9, UIFont.Small)
            end
            count = count + 1
        end
        pos._screenX = nil
        pos._screenY = nil
        pos._importance = nil
    end
end

local function banditDebugHookClass(classTable, className, methodName)
    if not classTable then return false end
    if NPCDebugMapMarkersBridge._hooksInstalled[className .. "." .. methodName] then return true end
    if type(classTable[methodName]) ~= "function" then return false end

    local oldMethod = classTable[methodName]
    classTable[methodName] = function(self, ...)
        oldMethod(self, ...)
        NPCDebugMapMarkersBridge.Render(self, string.find(tostring(className), "MiniMap") ~= nil)
    end

    NPCDebugMapMarkersBridge._hooksInstalled[className .. "." .. methodName] = true
    return true
end

function NPCDebugMapMarkersBridge.InstallHooks()
    if isServer and isServer() then return end

    if ISWorldMap then
        if not banditDebugHookClass(ISWorldMap, "ISWorldMap", "render") then
            banditDebugHookClass(ISWorldMap, "ISWorldMap", "prerender")
        end
    end

    if ISMiniMapInner then
        if not banditDebugHookClass(ISMiniMapInner, "ISMiniMapInner", "render") then
            banditDebugHookClass(ISMiniMapInner, "ISMiniMapInner", "prerender")
        end
    end

    if ISMiniMap then
        if not banditDebugHookClass(ISMiniMap, "ISMiniMap", "render") then
            banditDebugHookClass(ISMiniMap, "ISMiniMap", "prerender")
        end
    end
end

function NPCDebugMapMarkersBridge.SyncLoadedPositions()
    -- Server is the authority for world/debug marker sync. Sending live client
    -- positions back every few seconds created unnecessary network traffic and
    -- was ignored by the server command table in MP. Keep local drawing only.
    return
end

local function banditDebugOnTick()
    NPCDebugMapMarkersBridge.InstallHooks()
    NPCDebugMapMarkersBridge.SyncLoadedPositions()
end

local function banditDebugRegisterTickJob()
    -- Stage449: prefer the shared work scheduler. The old direct OnTick path is
    -- kept only as a fallback for unusual load orders. This avoids calling the
    -- hook installer every frame in normal runtime.
    if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.RegisterTickJob then
        NPCWorkSchedulerBridge.RegisterTickJob("NPCDebugMapMarkersBridge.Hooks", banditDebugOnTick, "marker", 120, 1)
        return
    end
    if Events and Events.OnTick and not NPCDebugMapMarkersBridge._directTickInstalled then
        NPCDebugMapMarkersBridge._directTickInstalled = true
        Events.OnTick.Add(banditDebugOnTick)
    end
end

Events.OnGameStart.Add(NPCDebugMapMarkersBridge.InstallHooks)
banditDebugRegisterTickJob()


NPCLegacyGlobalsBridge.InstallAlias("DebugMapMarkers", NPCDebugMapMarkersBridge, "NPCDebugMapMarkersBridge")
