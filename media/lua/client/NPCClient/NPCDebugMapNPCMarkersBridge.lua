-- NPCDebugMapNPCMarkersBridge.lua
-- Neutral client debug-map bridge.
-- The historical legacy debug-map NPC markers table is kept as a compatibility alias.

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCLegacyGlobalsBridge"
NPCDebugMapNPCMarkersBridge = NPCDebugMapNPCMarkersBridge or {}

local BLNPC_LEGACY_TEXT_PREFIX = NPCLegacyContractBridge.Text.prefix

local function blnpc_text(key)
    return getText(BLNPC_LEGACY_TEXT_PREFIX .. tostring(key or ""))
end

NPCDebugMapNPCMarkersBridge = NPCLegacyGlobalsBridge.InstallAlias("DebugMapNPCMarkers", NPCDebugMapNPCMarkersBridge, "NPCDebugMapNPCMarkersBridge")

--
-- Debug map markers for legacy NPC runtime WorldDirector NPC groups/NPCs.
-- Draws compact dots directly over the world map/minimap UI, so discovered
-- vanilla map areas are not required.
--

NPCDebugMapNPCMarkersBridge = NPCDebugMapNPCMarkersBridge or {}

NPCDebugMapNPCMarkersBridge.markers = NPCDebugMapNPCMarkersBridge.markers or {}
NPCDebugMapNPCMarkersBridge._hookedWorldMap = NPCDebugMapNPCMarkersBridge._hookedWorldMap or false
NPCDebugMapNPCMarkersBridge._hookedMiniMapInner = NPCDebugMapNPCMarkersBridge._hookedMiniMapInner or false
NPCDebugMapNPCMarkersBridge._hookedMiniMapOuter = NPCDebugMapNPCMarkersBridge._hookedMiniMapOuter or false
NPCDebugMapNPCMarkersBridge._tick = NPCDebugMapNPCMarkersBridge._tick or 0
NPCDebugMapNPCMarkersBridge._lastRequest = NPCDebugMapNPCMarkersBridge._lastRequest or 0
NPCDebugMapNPCMarkersBridge._pendingSync = NPCDebugMapNPCMarkersBridge._pendingSync or nil
NPCDebugMapNPCMarkersBridge._lastMapOpenSync = NPCDebugMapNPCMarkersBridge._lastMapOpenSync or 0
NPCDebugMapNPCMarkersBridge._lastMaterializeProbe = NPCDebugMapNPCMarkersBridge._lastMaterializeProbe or 0
NPCDebugMapNPCMarkersBridge._lastMaterializeMarker = NPCDebugMapNPCMarkersBridge._lastMaterializeMarker or nil

local function blnpc_asNumber(value, fallback)
    local n = tonumber(value)
    if n == nil then return fallback end
    return n
end

local blnpc_nowMs
local blnpc_settingNumber

local function blnpc_markerId(marker)
    if not marker then return nil end
    return marker.id or marker.uid or marker.groupId
end

local function blnpc_copyMarker(marker)
    if not marker then return nil end

    local x = blnpc_asNumber(marker.x, nil)
    local y = blnpc_asNumber(marker.y, nil)
    if not x or not y then return nil end

    local copied = {}
    for k, v in pairs(marker) do
        copied[k] = v
    end

    copied.x = x
    copied.y = y
    copied.z = blnpc_asNumber(marker.z, 0)
    copied.id = tostring(blnpc_markerId(copied) or tostring(copied.x) .. "_" .. tostring(copied.y))

    return copied
end

local function blnpc_canKeepLastSeen(marker)
    return false
end

local function blnpc_staleTtlMs()
    return blnpc_settingNumber("Debug_StaleMarkerMinutes", 180, 0, 10080) * 60000
end

local function blnpc_makeLastSeen(marker, reason)
    if not marker or not blnpc_canKeepLastSeen(marker) then return nil end
    local stale = {}
    for k, v in pairs(marker) do
        stale[k] = v
    end
    stale.dead = false
    stale.stale = true
    stale.lastSeen = true
    stale.lastSeenReason = reason or stale.lastSeenReason or "last_seen"
    stale.virtual = stale.markerType == "group" and stale.virtual ~= false or stale.virtual
    stale.active = false
    stale.updatedAt = stale.updatedAt or (getGameTime and getGameTime():getWorldAgeHours() or 0)
    stale._clientSeenMs = stale._clientSeenMs or blnpc_nowMs()
    stale._clientLastSeenMs = blnpc_nowMs()
    return stale
end

local function blnpc_keepFreshLastSeen(oldMarker, incoming)
    if not oldMarker or incoming[tostring(oldMarker.id or "")] then return nil end
    if not blnpc_canKeepLastSeen(oldMarker) then return nil end

    local now = blnpc_nowMs()
    local last = tonumber(oldMarker._clientLastSeenMs or oldMarker._clientSeenMs) or now
    if now - last > blnpc_staleTtlMs() then return nil end

    if oldMarker.stale or oldMarker.lastSeen then
        oldMarker._clientLastSeenMs = last
        return oldMarker
    end

    return blnpc_makeLastSeen(oldMarker, "missing_from_sync")
end

function NPCDebugMapNPCMarkersBridge.Set(marker)
    local copied = blnpc_copyMarker(marker)
    if not copied then return end

    copied._clientSeenMs = blnpc_nowMs()

    if copied.dead then
        if copied.markerType == "leader" then
            copied.leaderState = "dead"
            copied.dead = false
            copied.stale = false
            copied.lastSeen = false
            NPCDebugMapNPCMarkersBridge.markers[copied.id] = copied
            return
        elseif blnpc_canKeepLastSeen(copied) then
            NPCDebugMapNPCMarkersBridge.markers[copied.id] = blnpc_makeLastSeen(NPCDebugMapNPCMarkersBridge.markers[copied.id] or copied, "dead_or_removed")
            return
        end
        NPCDebugMapNPCMarkersBridge.markers[copied.id] = nil
        return
    end

    copied.stale = copied.stale == true
    copied.lastSeen = copied.lastSeen == true
    NPCDebugMapNPCMarkersBridge.markers[copied.id] = copied
end

function NPCDebugMapNPCMarkersBridge.Remove(id)
    if not id then return end
    local markerId = tostring(id)
    local marker = NPCDebugMapNPCMarkersBridge.markers[markerId]
    if blnpc_canKeepLastSeen(marker) then
        NPCDebugMapNPCMarkersBridge.markers[markerId] = blnpc_makeLastSeen(marker, "remove_command")
        return
    end
    NPCDebugMapNPCMarkersBridge.markers[markerId] = nil
end

function NPCDebugMapNPCMarkersBridge.Clear()
    NPCDebugMapNPCMarkersBridge.markers = {}
end

function NPCDebugMapNPCMarkersBridge.Sync(markers)
    if not markers then return end

    local incoming = {}
    local nextMarkers = {}

    for id, marker in pairs(markers) do
        if type(marker) == "table" then
            local copied = blnpc_copyMarker(marker)
            if copied then
                incoming[copied.id] = true
                copied._clientSeenMs = blnpc_nowMs()
                if copied.dead and copied.markerType == "leader" then
                    copied.leaderState = "dead"
                    copied.dead = false
                elseif copied.dead and blnpc_canKeepLastSeen(copied) then
                    copied = blnpc_makeLastSeen(NPCDebugMapNPCMarkersBridge.markers[copied.id] or copied, "dead_or_removed")
                end
                if copied then nextMarkers[copied.id] = copied end
            elseif id ~= nil then
                incoming[tostring(id)] = true
            end
        end
    end

    for id, oldMarker in pairs(NPCDebugMapNPCMarkersBridge.markers or {}) do
        local kept = blnpc_keepFreshLastSeen(oldMarker, incoming)
        if kept then nextMarkers[tostring(id)] = kept end
    end

    NPCDebugMapNPCMarkersBridge.markers = nextMarkers
end

function NPCDebugMapNPCMarkersBridge.Merge(markers)
    if not markers then return end

    for _, marker in pairs(markers) do
        if type(marker) == "table" then
            NPCDebugMapNPCMarkersBridge.Set(marker)
        end
    end
end

function NPCDebugMapNPCMarkersBridge.Count()
    local c = 0
    for _, _ in pairs(NPCDebugMapNPCMarkersBridge.markers) do
        c = c + 1
    end
    return c
end

blnpc_settingNumber = function(name, defaultValue, minValue, maxValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        return NPCLegacySettingsBridge.GetNumber(name, defaultValue, minValue, maxValue)
    end
    local value = tonumber(defaultValue) or 0
    if minValue ~= nil and value < minValue then value = minValue end
    if maxValue ~= nil and value > maxValue then value = maxValue end
    return value
end


local function blnpc_settingBool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        return NPCLegacySettingsBridge.GetBool(name, defaultValue == true)
    end
    return defaultValue == true
end

local function blnpc_shouldRender(isMiniMap)
    if not blnpc_settingBool("Debug_MapMarkersEnabled", true) then return false end
    if not blnpc_settingBool("Debug_NPCMarkersEnabled", true) then return false end
    if isMiniMap then
        return blnpc_settingBool("Debug_MiniMapMarkersEnabled", false)
    end
    return blnpc_settingBool("Debug_WorldMapMarkersEnabled", true)
end

local function blnpc_shouldRequestSync()
    if not blnpc_settingBool("Net_DebugMapEnabled", true) then return false end
    if not blnpc_settingBool("Debug_MapMarkersEnabled", true) then return false end
    if not blnpc_settingBool("Debug_NPCMarkersEnabled", true) then return false end
    return true
end

function NPCDebugMapNPCMarkersBridge.RequestSync()
    if not blnpc_shouldRequestSync() then
        NPCDebugMapNPCMarkersBridge.Clear()
        return
    end

    local player = getPlayer()
    if not player then return end

    local now = blnpc_nowMs()
    local cooldownMs = blnpc_settingNumber("Net_DebugMapRequestCooldownSeconds", 6.0, 0, 120) * 1000
    if cooldownMs > 0 and now - (tonumber(NPCDebugMapNPCMarkersBridge._lastRequest) or 0) < cooldownMs then
        return
    end
    NPCDebugMapNPCMarkersBridge._lastRequest = now

    sendClientCommand(player, 'NPCCommands', 'DebugMapRequest', {})
end

local function blnpc_onServerCommand(module, command, args)
    if not NPCLegacyContractBridge.IsModule(module, "NPCDebugMap", "debugMap") then return end

    if command == "Clear" then
        NPCDebugMapNPCMarkersBridge.Clear()
        NPCDebugMapNPCMarkersBridge._pendingSync = nil
    elseif command == "Remove" and args then
        NPCDebugMapNPCMarkersBridge.Remove(args.id or args.uid or args.groupId)
    elseif (command == "Update" or command == "UpdateCompact") and args then
        NPCDebugMapNPCMarkersBridge.Set(args)
    elseif command == "SyncBegin" then
        NPCDebugMapNPCMarkersBridge._pendingSync = {rev=args and args.rev or nil, markers={}, count=0}
    elseif command == "SyncChunk" and args then
        if not NPCDebugMapNPCMarkersBridge._pendingSync or (args.rev and NPCDebugMapNPCMarkersBridge._pendingSync.rev ~= args.rev) then
            NPCDebugMapNPCMarkersBridge._pendingSync = {rev=args.rev, markers={}, count=0}
        end
        for id, marker in pairs(args.markers or {}) do
            NPCDebugMapNPCMarkersBridge._pendingSync.markers[tostring(id)] = marker
            NPCDebugMapNPCMarkersBridge._pendingSync.count = (tonumber(NPCDebugMapNPCMarkersBridge._pendingSync.count) or 0) + 1
        end
    elseif command == "SyncEnd" then
        local pending = NPCDebugMapNPCMarkersBridge._pendingSync
        if pending and (not args or not args.rev or pending.rev == args.rev) then
            local expected = args and tonumber(args.count) or nil
            local partial = (args and args.truncated == true) or (expected and expected > 0 and (tonumber(pending.count) or 0) < expected)
            if partial and NPCDebugMapNPCMarkersBridge.Merge then
                NPCDebugMapNPCMarkersBridge.Merge(pending.markers)
            else
                NPCDebugMapNPCMarkersBridge.Sync(pending.markers)
            end
        end
        NPCDebugMapNPCMarkersBridge._pendingSync = nil
    elseif command == "Sync" and args then
        NPCDebugMapNPCMarkersBridge.Sync(args.markers or args)
        NPCDebugMapNPCMarkersBridge._pendingSync = nil
    end
end

local function blnpc_getMapAPI(ui)
    if not ui then return nil end
    if ui.mapAPI then return ui.mapAPI end
    if ui.javaObject and ui.javaObject.getAPIv1 then
        local ok, api = pcall(function()
            return ui.javaObject:getAPIv1()
        end)
        if ok and api then return api end
    end
    if ui.map and ui.map.mapAPI then return ui.map.mapAPI end
    if ui.inner and ui.inner.mapAPI then return ui.inner.mapAPI end
    return nil
end

local function blnpc_worldToUI(api, x, y)
    if not api then return nil, nil end

    local okX, uiX = pcall(function()
        return api:worldToUIX(x, y)
    end)
    local okY, uiY = pcall(function()
        return api:worldToUIY(x, y)
    end)

    if okX and okY and uiX and uiY then
        return uiX, uiY
    end

    okX, uiX = pcall(function()
        return api:worldToUIX(x)
    end)
    okY, uiY = pcall(function()
        return api:worldToUIY(y)
    end)

    if okX and okY and uiX and uiY then
        return uiX, uiY
    end

    return nil, nil
end

local function blnpc_getSize(ui)
    if not ui then return 0, 0 end

    local w = ui.width
    local h = ui.height

    if (not w or w <= 0) and ui.getWidth then
        local ok, res = pcall(function() return ui:getWidth() end)
        if ok then w = res end
    end

    if (not h or h <= 0) and ui.getHeight then
        local ok, res = pcall(function() return ui:getHeight() end)
        if ok then h = res end
    end

    return w or 0, h or 0
end

local function blnpc_drawRectSafe(ui, x, y, w, h, a, r, g, b)
    if not ui or not ui.drawRect then return end
    ui:drawRect(x, y, w, h, a, r, g, b)
end

local function blnpc_drawSmallLabel(ui, text, x, y, r, g, b, a)
    if not ui or not ui.drawTextCentre or not text or text == "" then return end
    pcall(function()
        ui:drawTextCentre(tostring(text), x, y + 1, 0, 0, 0, a or 0.92, UIFont.Small)
        ui:drawTextCentre(tostring(text), x, y, r or 1.0, g or 1.0, b or 1.0, a or 0.92, UIFont.Small)
    end)
end

local function blnpc_isStale(marker)
    return marker and (marker.stale == true or marker.lastSeen == true)
end

local function blnpc_shouldRenderPresenceMarker(marker)
    if not marker then return false end

    if marker.markerType == "group" then
        if blnpc_isStale(marker) then return false end
        if marker.dead == true then return false end
        return true
    elseif marker.markerType == "npc" then
        if blnpc_isStale(marker) then return false end
        if marker.dead == true then return false end
    end

    return true
end

local function blnpc_drawDiamond(ui, x, y, size, a, r, g, b)
    local half = math.max(2, math.floor(size / 2))
    for i = 0, half do
        local span = math.max(1, half - math.abs(i - half))
        blnpc_drawRectSafe(ui, x - span, y - half + i, span * 2, 1, a, r, g, b)
    end
    for i = 1, half do
        local span = math.max(1, half - i)
        blnpc_drawRectSafe(ui, x - span, y + i, span * 2, 1, a, r, g, b)
    end
end

local function blnpc_drawTriangle(ui, x, y, size, a, r, g, b)
    local half = math.max(2, math.floor(size / 2))
    for i = 0, half do
        local span = math.max(1, i + 1)
        blnpc_drawRectSafe(ui, x - span, y - half + i, span * 2, 1, a, r, g, b)
    end
end

local function blnpc_drawPatrolLetter(ui, x, y)
    if not ui then return end

    if ui.drawTextCentre then
        pcall(function()
            ui:drawTextCentre("P", x, y - 5, 0, 0, 0, 1.0, UIFont.Small)
        end)
        pcall(function()
            ui:drawTextCentre("P", x, y - 6, 1, 1, 1, 0.95, UIFont.Small)
        end)
        return
    end

    blnpc_drawRectSafe(ui, x - 2, y - 4, 1, 8, 1.0, 1, 1, 1)
    blnpc_drawRectSafe(ui, x - 1, y - 4, 4, 1, 1.0, 1, 1, 1)
    blnpc_drawRectSafe(ui, x + 2, y - 3, 1, 3, 1.0, 1, 1, 1)
    blnpc_drawRectSafe(ui, x - 1, y, 4, 1, 1.0, 1, 1, 1)
end


local function blnpc_drawGroupPower(ui, marker, x, y)
    if not ui or not marker or marker.markerType ~= "group" then return end
    local power = tonumber(marker.strategicPower)
    if not power or power <= 0 then return end
    local text = "P" .. tostring(math.floor(power + 0.5))
    if marker.homeBaseId then
        text = text .. " B" .. tostring(marker.homeBaseId)
    end
    if ui.drawTextCentre then
        pcall(function()
            ui:drawTextCentre(text, x, y + 8, 0, 0, 0, 0.95, UIFont.Small)
        end)
        pcall(function()
            ui:drawTextCentre(text, x, y + 7, 1, 1, 1, 0.92, UIFont.Small)
        end)
    end
end

local function blnpc_isNonZombieThreatKind(kind)
    if not kind then return false end
    kind = string.lower(tostring(kind))
    return kind ~= "" and kind ~= "zombie" and kind ~= "zed" and kind ~= "undead"
end

local function blnpc_isCombatState(state)
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

local function blnpc_isInBattle(marker)
    if not marker then return false end
    if marker.inBattle or marker.virtualBattle then return true end
    if marker.battleId then return true end
    if marker.state == "road_battle" or marker.order == "road_battle" then return true end

    local threatKind = marker.targetKind or marker.fsmTargetKind
    if blnpc_isNonZombieThreatKind(threatKind) and (marker.targetId or marker.fsmTargetId or blnpc_isCombatState(marker.state) or blnpc_isCombatState(marker.fsmState)) then
        return true
    end

    return false
end

local function blnpc_drawBattleIconFallback(ui, ox, oy, iconSize)
    for i = -iconSize, iconSize do
        blnpc_drawRectSafe(ui, ox + i, oy - i, 1, 1, 1.0, 0.95, 0.95, 0.95)
        blnpc_drawRectSafe(ui, ox + i, oy + i, 1, 1, 1.0, 0.95, 0.95, 0.95)
    end

    blnpc_drawRectSafe(ui, ox - 1, oy + iconSize - 1, 3, 3, 1.0, 0.70, 0.52, 0.22)
    blnpc_drawRectSafe(ui, ox - 1, oy - iconSize - 2, 3, 3, 1.0, 0.70, 0.52, 0.22)
    blnpc_drawRectSafe(ui, ox - iconSize - 2, oy - 1, 3, 3, 1.0, 0.70, 0.52, 0.22)
    blnpc_drawRectSafe(ui, ox + iconSize - 1, oy - 1, 3, 3, 1.0, 0.70, 0.52, 0.22)
end

local function blnpc_drawBattleIcon(ui, x, y, size)
    if not ui then return end

    local iconSize = math.max(4, math.floor((size or 6) / 2) + 2)
    local ox = math.floor(x + iconSize + 1)
    local oy = math.floor(y - iconSize - 1)

    blnpc_drawRectSafe(ui, ox - iconSize - 1, oy - iconSize - 1, iconSize * 2 + 2, iconSize * 2 + 2, 0.78, 0, 0, 0)

    if ui.drawTextCentre then
        local ok = pcall(function()
            ui:drawTextCentre("X", ox, oy - 7, 0, 0, 0, 1.0, UIFont.Small)
            ui:drawTextCentre("X", ox, oy - 8, 1, 1, 1, 1.0, UIFont.Small)
        end)
        if ok then return end
    end

    blnpc_drawBattleIconFallback(ui, ox, oy, iconSize)
end


blnpc_nowMs = function()
    if getTimestampMs then
        local ok, value = pcall(function() return getTimestampMs() end)
        if ok and value then return tonumber(value) or 0 end
    end
    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then
            local ok, value = pcall(function() return gt:getWorldAgeHours() end)
            if ok and value then return math.floor((tonumber(value) or 0) * 3600000) end
        end
    end
    return os.time() * 1000
end


local function blnpc_factionColor(marker)
    local side = marker and (marker.factionSide or marker.faction or marker.side or marker.patrolColor or marker.owner or marker.captureTeam) or nil
    if NPCFactionBridge and NPCFactionBridge.NormalizeSide then
        side = NPCFactionBridge.NormalizeSide(side)
    end
    if side == "red" then return 1.0, 0.08, 0.08 end
    if side == "green" then return 0.05, 0.95, 0.15 end
    if side == "black_market" then return 0.70, 0.25, 1.0 end
    if side == "blue" then return 0.12, 0.55, 1.0 end
    if side == "black" then return 0.02, 0.02, 0.02 end
    return nil
end

local function blnpc_baseColor(marker)
    local side = marker and (marker.owner or marker.captureTeam) or nil
    if marker and (marker.captureStatus == "contested" or marker.contested) then
        return 1.0, 0.78, 0.10
    end
    local fr, fg, fb = blnpc_factionColor(marker)
    if fr then return fr, fg, fb end
    return 0.82, 0.82, 0.82
end

local function blnpc_drawBaseLetter(ui, x, y)
    if not ui then return end

    if ui.drawTextCentre then
        local ok = pcall(function()
            ui:drawTextCentre("B", x, y - 7, 0, 0, 0, 1.0, UIFont.Small)
            ui:drawTextCentre("B", x, y - 8, 1, 1, 1, 1.0, UIFont.Small)
        end)
        if ok then return end
    end

    blnpc_drawRectSafe(ui, x - 3, y - 5, 1, 10, 1.0, 1, 1, 1)
    blnpc_drawRectSafe(ui, x - 2, y - 5, 4, 1, 1.0, 1, 1, 1)
    blnpc_drawRectSafe(ui, x + 2, y - 4, 1, 3, 1.0, 1, 1, 1)
    blnpc_drawRectSafe(ui, x - 2, y, 4, 1, 1.0, 1, 1, 1)
    blnpc_drawRectSafe(ui, x + 2, y + 1, 1, 3, 1.0, 1, 1, 1)
    blnpc_drawRectSafe(ui, x - 2, y + 4, 4, 1, 1.0, 1, 1, 1)
end

local function blnpc_drawBaseProgress(ui, x, y, marker, r, g, b)
    local progress = tonumber(marker.progress or marker.captureProgress) or 0
    if progress < 0 then progress = 0 end
    if progress > 100 then progress = 100 end

    local w = 24
    local h = 4
    local px = math.floor(x - w / 2)
    local py = math.floor(y - 17)
    blnpc_drawRectSafe(ui, px - 1, py - 1, w + 2, h + 2, 0.92, 0, 0, 0)
    blnpc_drawRectSafe(ui, px, py, w, h, 0.82, 0.12, 0.12, 0.12)
    blnpc_drawRectSafe(ui, px, py, math.floor(w * (progress / 100)), h, 0.98, r, g, b)
end

local function blnpc_drawBaseStockLabel(ui, marker, x, y)
    if not ui or not ui.drawTextCentre or not marker then return end
    local food = math.floor((tonumber(marker.stockFood) or 0) + 0.5)
    local ammo = math.floor((tonumber(marker.stockAmmo) or 0) + 0.5)
    local supplies = math.floor((tonumber(marker.stockSupplies) or 0) + 0.5)
    local foodReady = math.floor((tonumber(marker.foodReadiness) or 0) + 0.5)
    local ammoReady = math.floor((tonumber(marker.ammoReadiness) or 0) + 0.5)
    local hasStock = (food + ammo + supplies) > 0
    local hasReady = (foodReady + ammoReady) > 0
    if not hasStock and not hasReady then return end

    local line = "F" .. tostring(food) .. " A" .. tostring(ammo)
    if supplies > 0 then line = line .. " S" .. tostring(supplies) end
    if not hasStock and hasReady then line = "F" .. tostring(foodReady) .. "% A" .. tostring(ammoReady) .. "%" end
    pcall(function()
        ui:drawTextCentre(line, x, y + 20, 0, 0, 0, 0.86, UIFont.Small)
        ui:drawTextCentre(line, x, y + 19, 0.92, 0.92, 0.78, 0.94, UIFont.Small)
    end)
end

local function blnpc_zoneLetter(zoneType, label)
    if label and tostring(label) ~= "" then return string.sub(tostring(label), 1, 1) end
    zoneType = tostring(zoneType or "")
    if zoneType == "command" then return "C" end
    if zoneType == "staging" then return "T" end
    if zoneType == "storage" then return "S" end
    if zoneType == "sleep" then return "R" end
    if zoneType == "medical" then return "M" end
    if zoneType == "food" then return "F" end
    if zoneType == "ammo" then return "A" end
    if zoneType == "guard" then return "G" end
    if zoneType == "patrol" then return "P" end
    return "Z"
end

local function blnpc_drawZoneLetter(ui, x, y, letter)
    if not ui then return end

    if ui.drawTextCentre then
        local ok = pcall(function()
            ui:drawTextCentre(letter, x, y - 5, 0, 0, 0, 1.0, UIFont.Small)
            ui:drawTextCentre(letter, x, y - 6, 1, 1, 1, 0.95, UIFont.Small)
        end)
        if ok then return end
    end

    blnpc_drawRectSafe(ui, x - 1, y - 4, 2, 8, 1.0, 1, 1, 1)
end

local function blnpc_drawBaseZoneMarker(ui, marker, x, y)
    local r, g, b = blnpc_baseColor(marker)
    local size = 5
    local letter = blnpc_zoneLetter(marker.zoneType, marker.zoneLabel)

    if marker.zoneType == "command" then
        size = 6
    elseif marker.zoneType == "guard" or marker.zoneType == "patrol" then
        size = 4
    end

    blnpc_drawRectSafe(ui, x - size - 1, y - size - 1, (size + 1) * 2, (size + 1) * 2, 0.74, 0, 0, 0)
    blnpc_drawRectSafe(ui, x - size, y - size, size * 2, size * 2, 0.78, r, g, b)
    if ui.drawRectBorder then
        ui:drawRectBorder(x - size - 1, y - size - 1, (size + 1) * 2, (size + 1) * 2, 0.8, 0, 0, 0)
    end
    blnpc_drawZoneLetter(ui, x, y, letter)
end

local function blnpc_drawBaseMarker(ui, marker, x, y)
    local r, g, b = blnpc_baseColor(marker)
    local alpha = 0.98
    if marker.captureActive or marker.captureStatus == "capturing" or marker.captureStatus == "decapturing" then
        if math.floor(blnpc_nowMs() / 420) % 2 == 1 then
            alpha = 0.34
        end
    end

    local size = 9
    blnpc_drawRectSafe(ui, x - size - 1, y - size - 1, (size + 1) * 2, (size + 1) * 2, 0.90, 0, 0, 0)
    blnpc_drawRectSafe(ui, x - size, y - size, size * 2, size * 2, alpha, r, g, b)
    if ui.drawRectBorder then
        ui:drawRectBorder(x - size - 1, y - size - 1, (size + 1) * 2, (size + 1) * 2, 1.0, 0, 0, 0)
    end
    blnpc_drawBaseLetter(ui, x, y)
    blnpc_drawBaseProgress(ui, x, y, marker, r, g, b)
    if ui.drawTextCentre and marker and marker.commanderId then
        local label = marker.commanderState == "dead" and "CMD DOWN" or "CMD"
        ui:drawTextCentre(label, x, y - 30, 1.0, 0.88, 0.22, 1.0, UIFont.Small)
    end
end


local function blnpc_missionLetter(missionType)
    missionType = tostring(missionType or "")
    if missionType == "supply" then return "S" end
    if missionType == "raid" then return "R" end
    if missionType == "capture" then return "C" end
    if missionType == "retake" then return "T" end
    if missionType == "reinforce" then return "F" end
    if missionType == "scavenge" then return "L" end
    return "M"
end

local function blnpc_drawEconomyMissionMarker(ui, marker, x, y)
    local r, g, b = blnpc_baseColor(marker)
    local size = 7
    local letter = blnpc_missionLetter(marker.missionType)

    if marker.missionState == "queued" then
        r, g, b = 0.78, 0.78, 0.78
    elseif marker.missionState == "assaulting" or marker.missionType == "raid" or marker.missionType == "capture" or marker.missionType == "retake" then
        if marker.owner == "green" then
            r, g, b = 0.20, 0.95, 0.20
        else
            r, g, b = 1.00, 0.16, 0.08
        end
    end

    blnpc_drawDiamond(ui, x, y, size + 4, 0.88, 0, 0, 0)
    blnpc_drawDiamond(ui, x, y, size + 1, 0.92, r, g, b)
    if ui.drawRectBorder then
        ui:drawRectBorder(x - size - 1, y - size - 1, (size + 1) * 2, (size + 1) * 2, 0.9, 0, 0, 0)
    end
    blnpc_drawZoneLetter(ui, x, y, letter)
end

local function blnpc_drawIntelMarker(ui, marker, x, y)
    local size = 7
    local isCache = marker and (marker.supplyCache == true or tostring(marker.intelType or "") == "supply_cache")
    blnpc_drawDiamond(ui, x, y, size + 4, 0.88, 0, 0, 0)
    if isCache then
        blnpc_drawDiamond(ui, x, y, size + 1, 0.94, 1.0, 0.78, 0.15)
    else
        blnpc_drawDiamond(ui, x, y, size + 1, 0.92, 0.25, 0.65, 1.0)
    end
    if ui.drawTextCentre then
        if isCache then
            ui:drawTextCentre("$", x, y - 6, 1.0, 1.0, 1.0, 1.0, UIFont.Small)
            ui:drawTextCentre(blnpc_text("Map_SupplyCache"), x, y - 18, 1.0, 0.9, 0.35, 1.0, UIFont.Small)
            if marker and marker.supplyCacheActivated == true and marker.supplyCacheItems then
                ui:drawTextCentre(tostring(marker.supplyCacheItems), x, y + 9, 1.0, 1.0, 1.0, 0.95, UIFont.Small)
            end
        else
            ui:drawTextCentre("?", x, y - 6, 1.0, 1.0, 1.0, 1.0, UIFont.Small)
            if marker and marker.intelFalse then
                ui:drawTextCentre(blnpc_text("Map_Rumor"), x, y - 18, 0.5, 0.8, 1.0, 1.0, UIFont.Small)
            else
                ui:drawTextCentre(blnpc_text("Map_Intel"), x, y - 18, 0.5, 0.8, 1.0, 1.0, UIFont.Small)
            end
        end
    end
end

local function blnpc_drawContractMarker(ui, marker, x, y)
    local size = 7
    local r, g, b = blnpc_baseColor(marker)
    local letter = "C"
    if marker and marker.contractType == "supply" then letter = "S" end
    if marker and marker.contractType == "recon" then letter = "R" end

    blnpc_drawDiamond(ui, x, y, size + 4, 0.88, 0, 0, 0)
    blnpc_drawDiamond(ui, x, y, size + 1, 0.94, r or 1.0, g or 0.85, b or 0.20)
    if ui.drawTextCentre then
        ui:drawTextCentre(letter, x, y - 6, 1.0, 1.0, 1.0, 1.0, UIFont.Small)
        ui:drawTextCentre(blnpc_text("Map_Contract"), x, y - 18, 1.0, 0.9, 0.45, 1.0, UIFont.Small)
        if marker and marker.contractType == "supply" and marker.requiredAmount then
            local progress = tostring(marker.deliveredAmount or 0) .. "/" .. tostring(marker.requiredAmount)
            ui:drawTextCentre(progress, x, y + 9, 1.0, 1.0, 1.0, 0.95, UIFont.Small)
        end
    end
end

local function blnpc_drawConvoyMarker(ui, marker, x, y)
    local size = 8
    local r, g, b = blnpc_baseColor(marker)
    local letter = "C"
    if marker and marker.convoyObjective == "escort" then letter = "E" end
    if marker and marker.convoyObjective == "raid" then letter = "R" end

    if marker and (marker.convoyStatus == "arrived" or marker.convoyStatus == "completed") then
        r, g, b = 0.35, 0.95, 1.0
    elseif marker and marker.convoyObjective == "raid" then
        r, g, b = 1.0, 0.35, 0.12
    end

    blnpc_drawDiamond(ui, x, y, size + 5, 0.88, 0, 0, 0)
    if marker and marker.convoyObjective == "raid" then
        blnpc_drawTriangle(ui, x, y, size + 2, 0.94, r or 1.0, g or 0.55, b or 0.10)
    else
        blnpc_drawDiamond(ui, x, y, size + 2, 0.94, r or 0.35, g or 0.95, b or 1.0)
    end

    if ui.drawTextCentre then
        ui:drawTextCentre(letter, x, y - 6, 1.0, 1.0, 1.0, 1.0, UIFont.Small)
        ui:drawTextCentre(blnpc_text("Map_Convoy"), x, y - 18, 0.65, 0.95, 1.0, 1.0, UIFont.Small)
        local progress = math.floor(((tonumber(marker and marker.progress) or 0) * 100) + 0.5)
        local cargo = tostring(marker and (marker.cargoLabel or marker.cargoResource) or blnpc_text("Menu_Cargo"))
        if string.len(cargo) > 8 then cargo = string.sub(cargo, 1, 8) end
        ui:drawTextCentre(cargo .. " " .. tostring(progress) .. "%", x, y + 10, 1.0, 1.0, 1.0, 0.95, UIFont.Small)
    end
end

local function blnpc_drawCheckpointMarker(ui, marker, x, y)
    local size = 8
    local r, g, b = blnpc_factionColor(marker)
    if not r then r, g, b = 1.0, 0.75, 0.12 end
    if marker and marker.checkpointStatus == "alert" then
        r, g, b = 1.0, 0.10, 0.05
    elseif marker and marker.checkpointStatus == "bounty_alert" then
        r, g, b = 1.0, 0.05, 0.05
    elseif marker and (marker.checkpointStatus == "paid" or marker.checkpointStatus == "passed" or marker.checkpointStatus == "disguise_passed") then
        r, g, b = 0.15, 0.95, 0.35
    end

    blnpc_drawRectSafe(ui, x - size - 2, y - size - 2, (size + 2) * 2, (size + 2) * 2, 0.88, 0, 0, 0)
    blnpc_drawRectSafe(ui, x - size, y - size, size * 2, size * 2, 0.92, r, g, b)
    if ui.drawRectBorder then
        ui:drawRectBorder(x - size - 2, y - size - 2, (size + 2) * 2, (size + 2) * 2, 0.9, 0, 0, 0)
    end
    if ui.drawTextCentre then
        ui:drawTextCentre(blnpc_text("Map_CP"), x, y - 6, 1.0, 1.0, 1.0, 1.0, UIFont.Small)
        ui:drawTextCentre(blnpc_text("Map_CheckpointZone"), x, y - 18, 1.0, 0.9, 0.45, 1.0, UIFont.Small)
        local toll = tostring(marker and (marker.tollAmount or 0) or 0) .. " " .. tostring(marker and (marker.tollResource or "") or "")
        if string.len(toll) > 10 then toll = string.sub(toll, 1, 10) end
        ui:drawTextCentre(toll, x, y + 10, 1.0, 1.0, 1.0, 0.95, UIFont.Small)
        ui:drawTextCentre(blnpc_text("Map_RightClickNearby"), x, y + 22, 0.95, 0.92, 0.65, 0.90, UIFont.Small)
    end
end

local function blnpc_drawSignalMarker(ui, marker, x, y)
    local size = 8
    local r, g, b = 0.30, 0.70, 1.0
    local action = marker and tostring(marker.signalAction or "") or ""
    if action == "smoke" then
        r, g, b = 0.65, 0.65, 0.65
    elseif action == "attack" then
        r, g, b = 1.0, 0.30, 0.10
    elseif action == "target" then
        r, g, b = 1.0, 0.75, 0.15
    elseif action == "post" then
        r, g, b = 0.25, 0.95, 0.35
    elseif action == "rally" then
        r, g, b = 0.35, 0.95, 1.0
    end

    blnpc_drawDiamond(ui, x, y, size + 5, 0.90, 0, 0, 0)
    blnpc_drawDiamond(ui, x, y, size + 2, 0.94, r, g, b)
    if ui.drawTextCentre then
        local label = tostring(marker and (marker.signalLabel or marker.signalAction) or "SIG")
        if string.len(label) > 8 then label = string.sub(label, 1, 8) end
        ui:drawTextCentre(blnpc_text("Map_SIG"), x, y - 6, 1.0, 1.0, 1.0, 1.0, UIFont.Small)
        ui:drawTextCentre(label, x, y - 18, 0.85, 0.95, 1.0, 1.0, UIFont.Small)
    end
end

local function blnpc_drawBountyMarker(ui, marker, x, y)
    local size = 9
    local r, g, b = 1.0, 0.55, 0.10
    if marker and marker.bountyState == "kill_on_sight" then
        r, g, b = 1.0, 0.05, 0.02
    elseif marker and marker.bountyState == "hunted" then
        r, g, b = 1.0, 0.25, 0.05
    end
    blnpc_drawDiamond(ui, x, y, size + 5, 0.92, 0, 0, 0)
    blnpc_drawDiamond(ui, x, y, size + 2, 0.95, r, g, b)
    if ui.drawTextCentre then
        local value = tonumber(marker and marker.bountyAmount) or 0
        ui:drawTextCentre(blnpc_text("Map_Bounty"), x, y - 18, 1.0, 0.85, 0.25, 1.0, UIFont.Small)
        ui:drawTextCentre(tostring(value), x, y - 6, 1.0, 1.0, 1.0, 1.0, UIFont.Small)
    end
end

local function blnpc_drawBountyHunterIcon(ui, marker, x, y)
    if not marker or marker.bountyHunter ~= true then return end
    local text = blnpc_text("Map_Hunter")
    if marker.bountyState == "kill_on_sight" then text = blnpc_text("Map_KOS") end
    if ui.drawTextCentre then
        ui:drawTextCentre(text, x, y - 54, 1.0, 0.35, 0.08, 1.0, UIFont.Small)
    end
end

local function blnpc_drawBlackMarketMarker(ui, marker, x, y)
    local size = 9
    local r, g, b = 0.65, 0.20, 0.85
    if marker and marker.blackMarketStatus == "closed" then r, g, b = 0.45, 0.18, 0.62 end
    blnpc_drawDiamond(ui, x, y, size + 5, 0.92, 0, 0, 0)
    blnpc_drawDiamond(ui, x, y, size + 2, 0.95, r, g, b)
    if ui.drawTextCentre then
        ui:drawTextCentre("$", x, y - 8, 1.0, 1.0, 1.0, 1.0, UIFont.Small)
        ui:drawTextCentre(blnpc_text("Map_MarketContact"), x, y - 22, 0.95, 0.75, 1.0, 1.0, UIFont.Small)
        ui:drawTextCentre(blnpc_text("Map_RightClickNearby"), x, y + 10, 0.95, 0.90, 1.0, 0.90, UIFont.Small)
    end
end

local function blnpc_drawLeaderMarker(ui, marker, x, y)
    local size = 10
    local r, g, b = blnpc_factionColor(marker)
    if not r then r, g, b = 1.0, 0.82, 0.20 end
    local state = marker and tostring(marker.leaderState or marker.state or "active") or "active"
    local down = state == "dead" or (marker and marker.dead == true)
    if down or blnpc_isStale(marker) then return end
    blnpc_drawDiamond(ui, x, y, size + 6, 0.92, 0, 0, 0)
    blnpc_drawDiamond(ui, x, y, size + 3, 0.96, r, g, b)
    if ui.drawTextCentre then
        local text = blnpc_text("Map_LeaderIntel")
        if down then
            text = blnpc_text("Map_LeaderDown")
        elseif marker and marker.baseId then
            text = blnpc_text("Map_BaseCommanderIntel")
        elseif marker and marker.groupId then
            text = blnpc_text("Map_SquadLeaderEstimated")
        end
        ui:drawTextCentre("★", x, y - 8, 1.0, 1.0, 1.0, 1.0, UIFont.Small)
        ui:drawTextCentre(text, x, y - 22, 1.0, 0.90, 0.30, 1.0, UIFont.Small)
    end
end

local function blnpc_drawLeaderIcon(ui, marker, x, y)
    if not marker then return end
    local text = nil
    if marker.leader == true or marker.isFactionLeader == true then
        if marker.leaderState == "dead" or marker.dead == true or blnpc_isStale(marker) then return end
        text = blnpc_text("Map_Leader")
    elseif marker.commanderId then
        if marker.commanderState == "dead" or marker.dead == true or blnpc_isStale(marker) then return end
        text = blnpc_text("Map_Cmd")
    end
    if text and ui.drawTextCentre then
        ui:drawTextCentre(text, x, y - 66, 1.0, 0.88, 0.22, 1.0, UIFont.Small)
    end
end

local function blnpc_drawSpyIcon(ui, marker, x, y)
    if not (NPCSpyBridge and NPCSpyBridge.ShowMarkers and NPCSpyBridge.ShowMarkers()) then return end
    if not marker or not (marker.spy == true or (tonumber(marker.spyCount) and tonumber(marker.spyCount) > 0)) then return end
    local text = marker.markerType == "group" and "i" or blnpc_text("Map_Spy")
    if marker.spyDefected then text = blnpc_text("Map_Ally") end
    if ui.drawTextCentre then
        ui:drawTextCentre(text, x, y - 18, 0.15, 0.65, 1.0, 1.0, UIFont.Small)
    end
end

local function blnpc_drawMercenaryLeaderIcon(ui, marker, x, y)
    if not marker or marker.mercenarySquadLeader ~= true then return end
    if ui.drawTextCentre then
        ui:drawTextCentre("LEAD", x, y - 54, 0.25, 0.85, 1.0, 1.0, UIFont.Small)
    end
end

local function blnpc_drawWoundedIcon(ui, marker, x, y)
    if not marker or marker.wounded ~= true then return end
    local text = blnpc_text("Map_Wounded")
    if marker.woundedState == "evacuating" then text = blnpc_text("Map_Evac")
    elseif marker.woundedState == "stabilized" then text = blnpc_text("Map_Stable")
    elseif marker.woundedState == "abandoned" then text = blnpc_text("Map_Left") end
    if ui.drawTextCentre then
        ui:drawTextCentre(text, x, y - 30, 1.0, 0.25, 0.15, 1.0, UIFont.Small)
    end
end

local function blnpc_drawLoyaltyIcon(ui, marker, x, y)
    if not marker or not (marker.mercenaryHired == true or marker.isPlayerGuard == true) then return end
    if not marker.mercenaryLoyalty and not marker.loyaltyState then return end
    local value = tonumber(marker.mercenaryLoyalty)
    local state = tostring(marker.loyaltyState or "steady")
    local text = blnpc_text("Map_Loyal")
    local r, g, b = 0.35, 1.0, 0.45
    if state == "devoted" then
        text = blnpc_text("Map_Devoted")
        r, g, b = 0.25, 0.95, 1.0
    elseif state == "loyal" then
        text = blnpc_text("Map_Loyal")
        r, g, b = 0.35, 1.0, 0.45
    elseif state == "shaky" then
        text = blnpc_text("Map_Shaky")
        r, g, b = 1.0, 0.80, 0.15
    elseif state == "resentful" then
        text = blnpc_text("Map_Resent")
        r, g, b = 1.0, 0.25, 0.12
    else
        text = blnpc_text("Map_Steady")
        r, g, b = 0.80, 0.95, 1.0
    end
    if value then text = text .. " " .. tostring(math.floor(value + 0.5)) end
    if ui.drawTextCentre then
        ui:drawTextCentre(text, x, y - 42, r, g, b, 1.0, UIFont.Small)
    end
end

local function blnpc_drawDot(ui, marker, x, y)
    if not ui or not marker or not x or not y then return end

    if marker.markerType == "base_zone" then
        blnpc_drawBaseZoneMarker(ui, marker, x, y)
        return
    end

    if marker.markerType == "base" then
        blnpc_drawBaseMarker(ui, marker, x, y)
        return
    end

    if marker.markerType == "economy_mission" then
        blnpc_drawEconomyMissionMarker(ui, marker, x, y)
        return
    end

    if marker.markerType == "intel" then
        blnpc_drawIntelMarker(ui, marker, x, y)
        return
    end

    if marker.markerType == "contract" then
        blnpc_drawContractMarker(ui, marker, x, y)
        return
    end

    if marker.markerType == "convoy" then
        blnpc_drawConvoyMarker(ui, marker, x, y)
        return
    end

    if marker.markerType == "checkpoint" then
        blnpc_drawCheckpointMarker(ui, marker, x, y)
        return
    end

    if marker.markerType == "signal" then
        blnpc_drawSignalMarker(ui, marker, x, y)
        return
    end

    if marker.markerType == "bounty" then
        blnpc_drawBountyMarker(ui, marker, x, y)
        return
    end

    if marker.markerType == "leader" then
        blnpc_drawLeaderMarker(ui, marker, x, y)
        return
    end

    if marker.markerType == "black_market" then
        blnpc_drawBlackMarketMarker(ui, marker, x, y)
        return
    end

    local r, g, b = blnpc_factionColor(marker)
    if not r then
        r, g, b = 1.0, 0.08, 0.08
        if marker.friendly or marker.hostile == false then
            r, g, b = 0.05, 0.95, 0.15
        end
    end

    if blnpc_isStale(marker) then
        return
    end

    if marker.markerType == "group" then
        -- group dots are a bit larger than physical NPC dots
        if marker.active then
            if marker.hostile then
                r, g, b = 1.0, 0.38, 0.05
            else
                r, g, b = 0.15, 0.85, 0.95
            end
        end
        if blnpc_isStale(marker) then
            return
        end
    end

    local size = 4
    if marker.markerType == "group" then
        size = 6
    end

    pcall(function()
        if marker.roadPatrol then
            if marker.hostile then
                blnpc_drawTriangle(ui, x, y, size + 2, 0.98, r, g, b)
            else
                blnpc_drawDiamond(ui, x, y, size + 2, 0.98, r, g, b)
            end
            if ui.drawRectBorder then
                ui:drawRectBorder(x - size - 1, y - size - 1, (size + 1) * 2, (size + 1) * 2, 0.9, 0, 0, 0)
            else
                blnpc_drawRectSafe(ui, x - size - 1, y - size - 1, (size + 1) * 2, 1, 0.85, 0, 0, 0)
                blnpc_drawRectSafe(ui, x - size - 1, y + size, (size + 1) * 2, 1, 0.85, 0, 0, 0)
                blnpc_drawRectSafe(ui, x - size - 1, y - size - 1, 1, (size + 1) * 2, 0.85, 0, 0, 0)
                blnpc_drawRectSafe(ui, x + size, y - size - 1, 1, (size + 1) * 2, 0.85, 0, 0, 0)
            end
            blnpc_drawPatrolLetter(ui, x, y)
            if blnpc_isInBattle(marker) then
                blnpc_drawBattleIcon(ui, x, y, size + 1)
            end
        else
            blnpc_drawRectSafe(ui, x - size - 1, y - size - 1, (size + 1) * 2, (size + 1) * 2, 0.85, 0, 0, 0)
            blnpc_drawRectSafe(ui, x - size, y - size, size * 2, size * 2, 0.98, r, g, b)
            if blnpc_isInBattle(marker) then
                blnpc_drawBattleIcon(ui, x, y, size)
            end
        end
    end)

    if marker.markerType == "npc" then
        if blnpc_isStale(marker) then
            blnpc_drawSmallLabel(ui, blnpc_text("Map_NpcLastSeen"), x, y + 10, 0.75, 0.75, 0.75, 0.86)
        else
            blnpc_drawSmallLabel(ui, blnpc_text("Map_NpcActive"), x, y + 10, 0.90, 1.0, 0.90, 0.90)
        end
    elseif marker.markerType == "group" then
        local leaderGroup = marker.leader == true or marker.isFactionLeader == true or marker.leaderId ~= nil
        if blnpc_isStale(marker) then
            return
        elseif leaderGroup then
            -- Leader groups use the single leader icon label below; do not also
            -- print the generic patrol label under the same marker.
        elseif marker.virtual ~= false then
            blnpc_drawSmallLabel(ui, blnpc_text("Map_VirtualPatrol"), x, y + 12, 0.95, 0.95, 1.0, 0.90)
        elseif marker.active then
            blnpc_drawSmallLabel(ui, blnpc_text("Map_GroupActive"), x, y + 12, 0.90, 1.0, 0.90, 0.90)
        end
    end

    blnpc_drawWoundedIcon(ui, marker, x, y)
    blnpc_drawLoyaltyIcon(ui, marker, x, y)
    blnpc_drawBountyHunterIcon(ui, marker, x, y)
    blnpc_drawLeaderIcon(ui, marker, x, y)
    blnpc_drawMercenaryLeaderIcon(ui, marker, x, y)
    blnpc_drawSpyIcon(ui, marker, x, y)
    blnpc_drawGroupPower(ui, marker, x, y)
end

function NPCDebugMapNPCMarkersBridge.RenderOnMap(ui, api, isMiniMap)
    if not blnpc_shouldRender(isMiniMap == true) then return end
    if not ui or not api then return end

    if isMiniMap ~= true and blnpc_settingBool("Debug_RequestSyncOnMapOpen", true) then
        local now = blnpc_nowMs()
        local cooldownMs = math.max(1500, blnpc_settingNumber("Net_DebugMapRequestCooldownSeconds", 6.0, 0, 120) * 1000)
        if now - (tonumber(NPCDebugMapNPCMarkersBridge._lastMapOpenSync) or 0) >= cooldownMs then
            NPCDebugMapNPCMarkersBridge._lastMapOpenSync = now
            NPCDebugMapNPCMarkersBridge.RequestSync()
        end
    end

    local w, h = blnpc_getSize(ui)

    for _, marker in pairs(NPCDebugMapNPCMarkersBridge.markers) do
        if marker and marker.x and marker.y and blnpc_shouldRenderPresenceMarker(marker) and not marker.dead then
            local x, y = blnpc_worldToUI(api, marker.x, marker.y)
            if x and y then
                if w <= 0 or h <= 0 or (x >= -32 and y >= -32 and x <= w + 32 and y <= h + 32) then
                    blnpc_drawDot(ui, marker, x, y)
                end
            end
        end
    end
end

function NPCDebugMapNPCMarkersBridge.HookMaps()
    if ISWorldMap and ISWorldMap.render and not NPCDebugMapNPCMarkersBridge._hookedWorldMap then
        NPCDebugMapNPCMarkersBridge._hookedWorldMap = true
        ISWorldMap._NPCDebugMapNPCMarkersRender = ISWorldMap.render

        ISWorldMap.render = function(self)
            ISWorldMap._NPCDebugMapNPCMarkersRender(self)
            NPCDebugMapNPCMarkersBridge.RenderOnMap(self, blnpc_getMapAPI(self), false)
        end
    end

    if ISMiniMapInner and ISMiniMapInner.render and not NPCDebugMapNPCMarkersBridge._hookedMiniMapInner then
        NPCDebugMapNPCMarkersBridge._hookedMiniMapInner = true
        ISMiniMapInner._NPCDebugMapNPCMarkersRender = ISMiniMapInner.render

        ISMiniMapInner.render = function(self)
            ISMiniMapInner._NPCDebugMapNPCMarkersRender(self)
            NPCDebugMapNPCMarkersBridge.RenderOnMap(self, blnpc_getMapAPI(self), true)
        end
    end

    if ISMiniMapOuter and ISMiniMapOuter.render and not NPCDebugMapNPCMarkersBridge._hookedMiniMapOuter then
        NPCDebugMapNPCMarkersBridge._hookedMiniMapOuter = true
        ISMiniMapOuter._NPCDebugMapNPCMarkersRender = ISMiniMapOuter.render

        ISMiniMapOuter.render = function(self)
            ISMiniMapOuter._NPCDebugMapNPCMarkersRender(self)
            local inner = self.inner or self.map
            NPCDebugMapNPCMarkersBridge.RenderOnMap(inner or self, blnpc_getMapAPI(inner or self), true)
        end
    end
end

local function blnpc_onGameStart()
    NPCDebugMapNPCMarkersBridge.HookMaps()
    NPCDebugMapNPCMarkersBridge.RequestSync()
end

local function blnpc_tryMaterializeNearbyVirtualMarker()
    if not blnpc_settingBool("Debug_MapMarkerAutoMaterialize", true) then return end
    local player = getPlayer()
    if not player or not player.getX then return end

    local now = blnpc_nowMs()
    local cooldownMs = blnpc_settingNumber("Debug_MapMarkerMaterializeCooldownMs", 2500, 500, 30000)
    if now - (tonumber(NPCDebugMapNPCMarkersBridge._lastMaterializeProbe) or 0) < cooldownMs then return end

    local px = player:getX()
    local py = player:getY()
    local radius = blnpc_settingNumber("Debug_VirtualMarkerActivationRadius", 70, 12, 220)
    local r2 = radius * radius
    local best = nil
    local bestD2 = nil

    for _, marker in pairs(NPCDebugMapNPCMarkersBridge.markers or {}) do
        local materializeId = nil
        if type(marker) == "table" and marker.markerType == "group" and marker.virtual ~= false and marker.active ~= true and not blnpc_isStale(marker) then
            materializeId = marker.id
        elseif type(marker) == "table" and marker.markerType == "leader" and marker.groupId and not blnpc_isStale(marker) and tostring(marker.leaderState or "") ~= "dead" then
            materializeId = marker.groupId
        end

        if materializeId and marker.x and marker.y then
            local dx = (tonumber(marker.x) or 0) - px
            local dy = (tonumber(marker.y) or 0) - py
            local d2 = dx * dx + dy * dy
            if d2 <= r2 and (not bestD2 or d2 < bestD2) then
                best = marker
                best.materializeId = tostring(materializeId)
                bestD2 = d2
            end
        end
    end

    if not best then return end
    NPCDebugMapNPCMarkersBridge._lastMaterializeProbe = now
    NPCDebugMapNPCMarkersBridge._lastMaterializeMarker = tostring(best.materializeId or best.id)
    sendClientCommand(player, 'NPCCommands', 'DebugMapMaterializeNear', {markerId=tostring(best.materializeId or best.id), x=best.x, y=best.y})
end

local function blnpc_onTick()
    NPCDebugMapNPCMarkersBridge._tick = NPCDebugMapNPCMarkersBridge._tick + 1

    if NPCDebugMapNPCMarkersBridge._tick % 120 == 0 then
        NPCDebugMapNPCMarkersBridge.HookMaps()
    end

    if NPCDebugMapNPCMarkersBridge._tick % 120 == 0 then
        blnpc_tryMaterializeNearbyVirtualMarker()
    end

    if NPCDebugMapNPCMarkersBridge._tick % 600 == 0 then
        NPCDebugMapNPCMarkersBridge.RequestSync()
    end
end

Events.OnServerCommand.Add(blnpc_onServerCommand)
Events.OnGameStart.Add(blnpc_onGameStart)
Events.OnTick.Add(blnpc_onTick)

NPCDebugMapNPCMarkersBridge.HookMaps()


NPCLegacyGlobalsBridge.InstallAlias("DebugMapNPCMarkers", NPCDebugMapNPCMarkersBridge, "NPCDebugMapNPCMarkersBridge")
