-- NPCDebugMapNPCMarkersBridge.lua
-- Neutral client debug-map bridge.
-- The historical legacy debug-map NPC markers table is kept as a compatibility alias.

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCMarkerReconciliationBridge"
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
NPCDebugMapNPCMarkersBridge._lastLocalReconcile = NPCDebugMapNPCMarkersBridge._lastLocalReconcile or 0
NPCDebugMapNPCMarkersBridge._lastSyncReceived = NPCDebugMapNPCMarkersBridge._lastSyncReceived or 0
NPCDebugMapNPCMarkersBridge._lastSyncCount = NPCDebugMapNPCMarkersBridge._lastSyncCount or 0
NPCDebugMapNPCMarkersBridge._screenStable = NPCDebugMapNPCMarkersBridge._screenStable or {}

local function blnpc_asNumber(value, fallback)
    local n = tonumber(value)
    if n == nil then return fallback end
    return n
end

local function blnpc_worldAgeHours()
    local gt = getGameTime and getGameTime() or nil
    if gt and gt.getWorldAgeHours then
        local ok, value = pcall(function() return gt:getWorldAgeHours() end)
        if ok and value then return tonumber(value) or 0 end
    end
    return 0
end

local function blnpc_isSinglePlayerRuntime()
    return (not (isClient and isClient())) and (not (isServer and isServer()))
end

local function blnpc_mapMotionAlmostSame(a, b)
    a = tonumber(a) or 0
    b = tonumber(b) or 0
    return math.abs(a - b) <= 0.05
end

local function blnpc_mapMotionDistance(ax, ay, bx, by)
    ax = tonumber(ax)
    ay = tonumber(ay)
    bx = tonumber(bx)
    by = tonumber(by)
    if not (ax and ay and bx and by) then return nil end
    local dx = bx - ax
    local dy = by - ay
    return math.sqrt(dx * dx + dy * dy)
end

local function blnpc_mapPathKey(marker)
    if not marker then return nil end
    if marker.mapPathKey ~= nil then return tostring(marker.mapPathKey) end
    local count = tonumber(marker.mapPathCount) or 0
    if count <= 0 then return nil end
    local parts = {}
    for i=1, math.min(6, count) do
        parts[#parts + 1] = tostring(math.floor((tonumber(marker["mapPathX" .. tostring(i)]) or 0) + 0.5))
        parts[#parts + 1] = tostring(math.floor((tonumber(marker["mapPathY" .. tostring(i)]) or 0) + 0.5))
    end
    return table.concat(parts, ":")
end

local function blnpc_prepareGroupMapMotion(marker, previous)
    if not marker or marker.markerType ~= "group" then return marker end

    local sx = blnpc_asNumber(marker.preciseX or marker.mapSourceX or marker.x, nil)
    local sy = blnpc_asNumber(marker.preciseY or marker.mapSourceY or marker.y, nil)
    local tx = blnpc_asNumber(marker.mapTargetX or marker.targetX, nil)
    local ty = blnpc_asNumber(marker.mapTargetY or marker.targetY, nil)
    local speed = blnpc_asNumber(marker.mapMoveSpeed, nil)
    local moving = marker.mapMotion == true and marker.virtual ~= false and marker.active ~= true and marker.inBattle ~= true and sx ~= nil and sy ~= nil and tx ~= nil and ty ~= nil and speed ~= nil and speed > 0
    local pathKey = blnpc_mapPathKey(marker)

    if not moving then
        marker._mapMotionStartX = nil
        marker._mapMotionStartY = nil
        marker._mapMotionStartAge = nil
        marker._mapMotionSourceX = nil
        marker._mapMotionSourceY = nil
        marker._mapMotionTargetX = nil
        marker._mapMotionTargetY = nil
        marker._mapMotionPathKey = nil
        marker._mapProjectedX = nil
        marker._mapProjectedY = nil
        return marker
    end

    local samePath = previous and tostring(previous._mapMotionPathKey or "") == tostring(pathKey or "")
    local preserve = previous and previous._mapMotionStartX and previous._mapMotionStartY and previous._mapMotionStartAge
        and samePath
        and blnpc_mapMotionAlmostSame(previous._mapMotionSourceX, sx)
        and blnpc_mapMotionAlmostSame(previous._mapMotionSourceY, sy)
        and blnpc_mapMotionAlmostSame(previous._mapMotionTargetX, tx)
        and blnpc_mapMotionAlmostSame(previous._mapMotionTargetY, ty)

    local sameTarget = previous
        and blnpc_mapMotionAlmostSame(previous._mapMotionTargetX, tx)
        and blnpc_mapMotionAlmostSame(previous._mapMotionTargetY, ty)
    local projectedX = previous and tonumber(previous._mapProjectedX or previous._mapMotionStartX or previous.preciseX or previous.x) or nil
    local projectedY = previous and tonumber(previous._mapProjectedY or previous._mapMotionStartY or previous.preciseY or previous.y) or nil
    local projectedGap = blnpc_mapMotionDistance(projectedX, projectedY, sx, sy)
    local smoothAuthoritativeStep = sameTarget and projectedX and projectedY and projectedGap and projectedGap <= 260

    marker._mapMotionSourceX = sx
    marker._mapMotionSourceY = sy
    marker._mapMotionTargetX = tx
    marker._mapMotionTargetY = ty
    marker._mapMotionPathKey = pathKey

    if preserve then
        marker._mapMotionStartX = previous._mapMotionStartX
        marker._mapMotionStartY = previous._mapMotionStartY
        marker._mapMotionStartAge = previous._mapMotionStartAge
        marker._mapProjectedX = previous._mapProjectedX
        marker._mapProjectedY = previous._mapProjectedY
    elseif smoothAuthoritativeStep then
        marker._mapMotionStartX = projectedX
        marker._mapMotionStartY = projectedY
        marker._mapMotionStartAge = blnpc_worldAgeHours()
        marker._mapProjectedX = projectedX
        marker._mapProjectedY = projectedY
    else
        marker._mapMotionStartX = sx
        marker._mapMotionStartY = sy
        marker._mapMotionStartAge = blnpc_worldAgeHours()
        marker._mapProjectedX = sx
        marker._mapProjectedY = sy
    end

    return marker
end

local function blnpc_projectAlongSegment(cx, cy, tx, ty, step)
    local dx = tx - cx
    local dy = ty - cy
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist <= 0.05 then return tx, ty, step, true end
    if step >= dist then return tx, ty, step - dist, true end
    return cx + (dx / dist) * step, cy + (dy / dist) * step, 0, false
end

local function blnpc_projectGroupMapPosition(marker)
    if not marker or marker.markerType ~= "group" then
        return marker and marker.x or nil, marker and marker.y or nil
    end
    if not (marker._mapMotionStartX and marker._mapMotionStartY and marker._mapMotionStartAge and marker._mapMotionTargetX and marker._mapMotionTargetY) then
        return blnpc_asNumber(marker.preciseX or marker.x, marker.x), blnpc_asNumber(marker.preciseY or marker.y, marker.y)
    end

    local cx = tonumber(marker._mapMotionStartX) or tonumber(marker.x) or 0
    local cy = tonumber(marker._mapMotionStartY) or tonumber(marker.y) or 0
    local dt = blnpc_worldAgeHours() - (tonumber(marker._mapMotionStartAge) or blnpc_worldAgeHours())
    if dt < 0 then dt = 0 end
    if dt > 0.50 then dt = 0.50 end
    local step = (tonumber(marker.mapMoveSpeed) or 120) * dt

    local count = math.min(6, math.max(0, tonumber(marker.mapPathCount) or 0))
    for i=1, count do
        local nx = tonumber(marker["mapPathX" .. tostring(i)])
        local ny = tonumber(marker["mapPathY" .. tostring(i)])
        if nx and ny then
            local px, py, left, done = blnpc_projectAlongSegment(cx, cy, nx, ny, step)
            if not done then
                marker._mapProjectedX = px
                marker._mapProjectedY = py
                return px, py
            end
            cx = px
            cy = py
            step = left
        end
    end

    local tx = tonumber(marker._mapMotionTargetX) or cx
    local ty = tonumber(marker._mapMotionTargetY) or cy
    local px, py = blnpc_projectAlongSegment(cx, cy, tx, ty, step)
    marker._mapProjectedX = px
    marker._mapProjectedY = py
    return px, py
end

local blnpc_nowMs
local blnpc_settingNumber
local blnpc_reconcileLocalMarkers

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

local function blnpc_cleanGroupDisplayName(value)
    if value == nil then return nil end
    local text = tostring(value or "")
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

local function blnpc_groupSideLabel(marker)
    local side = marker and (marker.factionSide or marker.faction or marker.side or marker.patrolColor or marker.owner or marker.captureTeam) or nil
    if NPCFactionBridge and NPCFactionBridge.NormalizeSide then
        side = NPCFactionBridge.NormalizeSide(side)
    end
    side = tostring(side or "")
    if side == "red" then return "Red" end
    if side == "green" then return "Green" end
    if side == "blue" then return "Blue" end
    if side == "black_market" then return "Blue" end
    if side == "black" then return "Black" end
    if marker and marker.hostile then return "Red" end
    return "Green"
end

local function blnpc_groupDisplayName(marker)
    if not marker then return nil end
    local cleaned = blnpc_cleanGroupDisplayName(marker.displayName) or blnpc_cleanGroupDisplayName(marker.name) or blnpc_cleanGroupDisplayName(marker.groupName) or blnpc_cleanGroupDisplayName(marker.title)
    if cleaned then return cleaned end

    local sideLabel = blnpc_groupSideLabel(marker)
    if marker.mercenaryHired or marker.mercenary or marker.mercenarySquad or marker.kind == "mercenary" then
        return "Blue mercenaries"
    end
    if marker.checkpointId or marker.targetClass == "checkpoint_road_patrol" or marker.state == "checkpoint_patrol" or marker.order == "checkpoint_patrol" then
        return sideLabel .. " checkpoint patrol"
    end
    if marker.roadPatrol or marker.targetClass == "road_patrol" or marker.state == "patrol" or marker.order == "patrol" then
        return sideLabel .. " road patrol"
    end
    if marker.homeBaseId or marker.baseId or marker.targetClass == "base" or marker.state == "base_patrol" or marker.order == "base_patrol" then
        return sideLabel .. " base patrol"
    end
    return sideLabel .. " patrol"
end

local function blnpc_normalizeGroupDisplayName(marker)
    if not marker or marker.markerType ~= "group" then return end
    local displayName = blnpc_groupDisplayName(marker)
    if not displayName or displayName == "" then return end
    marker.displayName = displayName
    marker.name = displayName
    marker.groupName = nil
    marker.title = nil
end

local function blnpc_canKeepLastSeen(marker)
    return false
end

local function blnpc_staleTtlMs()
    return blnpc_settingNumber("Debug_StaleMarkerMinutes", 180, 0, 10080) * 60000
end

local function blnpc_transientGraceMs()
    return blnpc_settingNumber("Debug_TransientMarkerGraceSeconds", 10, 0, 120) * 1000
end

local function blnpc_canKeepTransientMarker(marker)
    if not marker or marker.dead == true then return false end
    local markerType = tostring(marker.markerType or "")
    return markerType == "group"
        or markerType == "leader"
        or markerType == "black_market"
        or markerType == "black_market_drop"
        or markerType == "black_market_turnin"
        or marker.virtual == true
        or marker.active == true
end

local function blnpc_makeTransientMarker(marker, reason)
    if not blnpc_canKeepTransientMarker(marker) then return nil end

    local now = blnpc_nowMs()
    local grace = blnpc_transientGraceMs()
    if grace <= 0 then return nil end

    local missingSince = tonumber(marker._clientMissingSinceMs) or now
    if now - missingSince > grace then return nil end

    local transient = {}
    for k, v in pairs(marker) do
        transient[k] = v
    end
    transient.dead = false
    transient.stale = false
    transient.lastSeen = false
    transient.syncGrace = true
    transient.syncGraceReason = reason or "missing_from_sync"
    transient._clientMissingSinceMs = missingSince
    transient._clientLastSeenMs = tonumber(marker._clientLastSeenMs or marker._clientSeenMs) or now
    return transient
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

    local transient = blnpc_makeTransientMarker(oldMarker, "missing_from_sync")
    if transient then return transient end

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
    copied._clientMissingSinceMs = nil
    copied.syncGrace = nil
    copied.syncGraceReason = nil

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
    blnpc_normalizeGroupDisplayName(copied)
    blnpc_prepareGroupMapMotion(copied, NPCDebugMapNPCMarkersBridge.markers[copied.id])
    NPCDebugMapNPCMarkersBridge.markers[copied.id] = copied
end

function NPCDebugMapNPCMarkersBridge.Remove(id)
    if not id then return end
    local markerId = tostring(id)
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
                copied._clientMissingSinceMs = nil
                copied.syncGrace = nil
                copied.syncGraceReason = nil
                if copied.dead and copied.markerType == "leader" then
                    copied.leaderState = "dead"
                    copied.dead = false
                elseif copied.dead and blnpc_canKeepLastSeen(copied) then
                    copied = blnpc_makeLastSeen(NPCDebugMapNPCMarkersBridge.markers[copied.id] or copied, "dead_or_removed")
                end
                if copied then
                    copied.stale = copied.stale == true
                    copied.lastSeen = copied.lastSeen == true
                    blnpc_normalizeGroupDisplayName(copied)
                    blnpc_prepareGroupMapMotion(copied, NPCDebugMapNPCMarkersBridge.markers[copied.id])
                    nextMarkers[copied.id] = copied
                end
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
    NPCDebugMapNPCMarkersBridge._lastSyncReceived = blnpc_nowMs()
    NPCDebugMapNPCMarkersBridge._lastSyncCount = NPCDebugMapNPCMarkersBridge.Count and NPCDebugMapNPCMarkersBridge.Count() or 0
    blnpc_reconcileLocalMarkers(true)
end

function NPCDebugMapNPCMarkersBridge.Merge(markers)
    if not markers then return end

    for _, marker in pairs(markers) do
        if type(marker) == "table" then
            NPCDebugMapNPCMarkersBridge.Set(marker)
        end
    end
end


function NPCDebugMapNPCMarkersBridge.RefreshLocalVirtualGroups(force)
    if not blnpc_isSinglePlayerRuntime() then return 0 end
    if force ~= true and NPCDebugMapNPCMarkersBridge.Count and NPCDebugMapNPCMarkersBridge.Count() > 0 then return 0 end
    local gmd = GetNPCModData and GetNPCModData() or nil
    if type(gmd) ~= "table" then return 0 end

    local changed = 0
    if type(gmd.DebugMapMarkers) == "table" then
        for _, marker in pairs(gmd.DebugMapMarkers) do
            if type(marker) == "table" and marker.markerType then
                NPCDebugMapNPCMarkersBridge.Set(marker)
                changed = changed + 1
                if changed >= 260 then return changed end
            end
        end
    end

    if changed > 0 then return changed end
    if type(gmd.VirtualGroups) ~= "table" then return 0 end

    for groupId, group in pairs(gmd.VirtualGroups) do
        if type(group) == "table" and group.activated ~= true and group.x and group.y then
            local id = tostring(group.id or groupId)
            NPCDebugMapNPCMarkersBridge.Set({
                id = id,
                groupId = id,
                markerType = "group",
                x = tonumber(group.x) or 0,
                y = tonumber(group.y) or 0,
                z = tonumber(group.z) or 0,
                name = group.displayName or group.name or tostring(id),
                displayName = group.displayName or group.name or tostring(id),
                count = group.count or (type(group.members) == "table" and #group.members) or 0,
                hostile = group.hostile,
                friendly = not group.hostile,
                factionSide = group.factionSide,
                faction = group.faction,
                side = group.side,
                state = group.state,
                virtual = true,
                active = false,
                roadPatrol = group.roadPatrol or false,
                inBattle = group.inBattle or false,
                updatedAt = blnpc_worldAgeHours()
            })
            changed = changed + 1
            if changed >= 260 then break end
        end
    end
    return changed
end

function NPCDebugMapNPCMarkersBridge.Count()
    local c = 0
    for _, _ in pairs(NPCDebugMapNPCMarkersBridge.markers) do
        c = c + 1
    end
    return c
end

blnpc_reconcileLocalMarkers = function(force)
    if not (NPCMarkerReconciliationBridge and NPCMarkerReconciliationBridge.ReconcileClientMarkers) then return 0 end
    local now = blnpc_nowMs()
    if force ~= true and now - (tonumber(NPCDebugMapNPCMarkersBridge._lastLocalReconcile) or 0) < 1500 then return 0 end
    NPCDebugMapNPCMarkersBridge._lastLocalReconcile = now
    local ok, changed = pcall(function()
        return NPCMarkerReconciliationBridge.ReconcileClientMarkers(NPCDebugMapNPCMarkersBridge.markers, {
            maxMarkers = 220,
            leaderTtlHours = blnpc_settingNumber and blnpc_settingNumber("Debug_LeaderMarkerTtlHours", 2.0, 0.25, 24) or 2.0
        })
    end)
    if ok then return tonumber(changed) or 0 end
    return 0
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


local function blnpc_averageFPS()
    if getAverageFPS then
        local ok, fps = pcall(function() return getAverageFPS() end)
        if ok and tonumber(fps) then return tonumber(fps) end
    end
    return 60
end

local function blnpc_mapLoadLevel()
    if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.GetLoadLevel then
        local ok, level = pcall(function() return NPCWorkSchedulerBridge.GetLoadLevel(false) end)
        if ok and tonumber(level) then return tonumber(level) or 0 end
    end
    local fps = blnpc_averageFPS()
    if fps > 0 and fps < 30 then return 3 end
    if fps > 0 and fps < 45 then return 2 end
    if fps > 0 and fps < 55 then return 1 end
    return 0
end

local function blnpc_maxMarkersForLoad(isMiniMap, loadLevel)
    local base = blnpc_settingNumber(isMiniMap and "Debug_MaxMiniMapMarkers" or "Debug_MaxWorldMapMarkers", isMiniMap and 45 or 160, 0, 5000)
    if loadLevel >= 3 then return math.min(base, isMiniMap and 20 or 60) end
    if loadLevel >= 2 then return math.min(base, isMiniMap and 30 or 100) end
    if loadLevel >= 1 then return math.min(base, isMiniMap and 45 or 160) end
    return base
end

local function blnpc_suppressLabelsForLoad(isMiniMap, loadLevel)
    if isMiniMap then return true end
    if loadLevel <= 0 then return false end
    return not blnpc_settingBool("Debug_MapLabelsUnderLoad", false)
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
    local cooldownSeconds = blnpc_settingNumber("Net_DebugMapRequestCooldownSeconds", 3.0, 0, 120)
    if NPCStreamingRuntimeBridge and NPCStreamingRuntimeBridge.AdjustMarkerInterval then
        cooldownSeconds = NPCStreamingRuntimeBridge.AdjustMarkerInterval(cooldownSeconds)
    end
    local cooldownMs = cooldownSeconds * 1000
    if cooldownMs > 0 and now - (tonumber(NPCDebugMapNPCMarkersBridge._lastRequest) or 0) < cooldownMs then
        return
    end
    NPCDebugMapNPCMarkersBridge._lastRequest = now

    if blnpc_isSinglePlayerRuntime() then
        if NPCWorldDirector and NPCWorldDirector.Bootstrap then
            pcall(function() NPCWorldDirector.Bootstrap() end)
        end
        if NPCWorldDirector and NPCWorldDirector.SyncMarkers then
            pcall(function() NPCWorldDirector.SyncMarkers() end)
        end
        if NPCDebugMapNPCMarkersBridge.RefreshLocalVirtualGroups then
            NPCDebugMapNPCMarkersBridge.RefreshLocalVirtualGroups(true)
        end
    end

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


local function blnpc_stabilizeScreenPosition(marker, x, y, isMiniMap)
    if not marker or not marker.id or not x or not y then
        return x and math.floor(x + 0.5) or x, y and math.floor(y + 0.5) or y
    end

    local key = tostring(marker.id) .. (isMiniMap == true and ":mini" or ":world")
    local cache = NPCDebugMapNPCMarkersBridge._screenStable
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
        item.t = blnpc_nowMs()
        cache[key] = item
    end
    return rx, ry
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
    if NPCDebugMapNPCMarkersBridge._suppressMapLabels == true then return end
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
    if NPCDebugMapNPCMarkersBridge._suppressMapLabels == true then return end

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
            alpha = 0.70
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
    local reward = marker and marker.blackMarketHasPendingReward == true
    local turnIn = marker and marker.blackMarketQuestTurnInHighlight == true
    if marker and marker.blackMarketStatus == "closed" then r, g, b = 0.45, 0.18, 0.62 end
    if reward or turnIn then
        blnpc_drawDiamond(ui, x, y, size + 15, 0.94, 0, 0, 0)
        blnpc_drawDiamond(ui, x, y, size + 12, 0.97, 1.0, 0.20, 0.82)
        blnpc_drawDiamond(ui, x, y, size + 8, 0.97, 0.70, 0.25, 1.0)
    end
    blnpc_drawDiamond(ui, x, y, size + 5, 0.92, 0, 0, 0)
    blnpc_drawDiamond(ui, x, y, size + 2, 0.95, r, g, b)
    if ui.drawTextCentre then
        ui:drawTextCentre("$", x, y - 8, 1.0, 1.0, 1.0, 1.0, UIFont.Small)
        if reward then
            ui:drawTextCentre("QUEST REWARD", x, y - 28, 1.0, 0.82, 1.0, 1.0, UIFont.Small)
            ui:drawTextCentre("LOOT BOX", x, y + 12, 0.95, 0.90, 1.0, 0.94, UIFont.Small)
        elseif turnIn then
            ui:drawTextCentre("QUEST TURN-IN", x, y - 28, 1.0, 0.82, 1.0, 1.0, UIFont.Small)
            ui:drawTextCentre("RETURN ITEM", x, y + 12, 0.95, 0.90, 1.0, 0.94, UIFont.Small)
        else
            ui:drawTextCentre(blnpc_text("Map_MarketContact"), x, y - 22, 0.95, 0.75, 1.0, 1.0, UIFont.Small)
            ui:drawTextCentre(blnpc_text("Map_RightClickNearby"), x, y + 10, 0.95, 0.90, 1.0, 0.90, UIFont.Small)
        end
    end
end

local function blnpc_drawBlackMarketTurnInMarker(ui, marker, x, y)
    local size = 13
    local r, g, b = 1.0, 0.20, 0.82
    blnpc_drawDiamond(ui, x, y, size + 10, 0.96, 0, 0, 0)
    blnpc_drawDiamond(ui, x, y, size + 7, 0.98, r, g, b)
    blnpc_drawDiamond(ui, x, y, size + 3, 0.98, 0.65, 0.20, 0.85)
    blnpc_drawDiamond(ui, x, y, size, 0.95, 0.08, 0.04, 0.12)
    if ui.drawTextCentre then
        ui:drawTextCentre("$", x, y - 8, 1.0, 1.0, 1.0, 1.0, UIFont.Small)
        ui:drawTextCentre("QUEST TURN-IN", x, y - 26, r, g, b, 1.0, UIFont.Small)
        ui:drawTextCentre("RETURN ITEM", x, y + 12, 1.0, 0.85, 1.0, 0.95, UIFont.Small)
    end
end

local function blnpc_drawBlackMarketDropMarker(ui, marker, x, y)
    local size = 10
    local dropType = tostring(marker and marker.blackMarketDropType or "")
    local r, g, b = 0.75, 0.45, 1.0
    if dropType == "weapons" then r, g, b = 0.95, 0.70, 0.20
    elseif dropType == "ammo" then r, g, b = 0.55, 0.85, 1.0
    elseif dropType == "armor" then r, g, b = 0.80, 0.85, 0.95
    elseif dropType == "medical" then r, g, b = 0.30, 1.0, 0.55
    elseif dropType == "quest" then r, g, b = 1.0, 0.20, 0.82
    elseif dropType == "defense" then r, g, b = 0.70, 0.25, 1.0
    elseif dropType == "documents" or dropType == "badge" or dropType == "password" then r, g, b = 0.85, 0.50, 1.0 end
    blnpc_drawDiamond(ui, x, y, size + 8, 0.95, 0, 0, 0)
    blnpc_drawDiamond(ui, x, y, size + 5, 0.98, r, g, b)
    blnpc_drawDiamond(ui, x, y, size + 1, 0.98, 0.08, 0.04, 0.12)
    if ui.drawTextCentre then
        local code = "DROP"
        local label = "BLACK MARKET DROP"
        if dropType == "weapons" then label = "WEAPON CACHE"
        elseif dropType == "ammo" then label = "AMMO CACHE"
        elseif dropType == "armor" then label = "ARMOR CACHE"
        elseif dropType == "medical" then label = "MED CACHE"
        elseif dropType == "quest" then code = "QUEST"; label = "QUEST"
        elseif dropType == "defense" then code = "DEFEND"; label = "DEFENSE ZONE"
        elseif dropType == "documents" then label = "DOCUMENT DROP"
        elseif dropType == "badge" then label = "BADGE DROP"
        elseif dropType == "password" then label = "PASSWORD DROP" end
        ui:drawTextCentre(code, x, y - 8, 1.0, 1.0, 1.0, 1.0, UIFont.Small)
        ui:drawTextCentre(label, x, y - 24, r, g, b, 1.0, UIFont.Small)
    end
end

local function blnpc_drawLeaderMarker(ui, marker, x, y)
    local size = 10
    local r, g, b = blnpc_factionColor(marker)
    if not r then r, g, b = 1.0, 0.82, 0.20 end
    local state = marker and tostring(marker.leaderState or marker.state or "active") or "active"
    local down = state == "dead" or (marker and marker.dead == true)
    if down or blnpc_isStale(marker) then return end
    local purchased = marker and (marker.blackMarketLeaderIntel == true or marker.blackMarketPurchasedIntel == true)
    if purchased then
        size = 13
        r, g, b = 1.0, 0.88, 0.10
        blnpc_drawDiamond(ui, x, y, size + 10, 0.96, 0, 0, 0)
        blnpc_drawDiamond(ui, x, y, size + 6, 0.98, 1.0, 0.25, 0.05)
        blnpc_drawDiamond(ui, x, y, size + 2, 0.98, r, g, b)
    else
        blnpc_drawDiamond(ui, x, y, size + 6, 0.92, 0, 0, 0)
        blnpc_drawDiamond(ui, x, y, size + 3, 0.96, r, g, b)
    end
    if ui.drawTextCentre then
        local text = purchased and "BOUGHT LEADER INTEL" or blnpc_text("Map_LeaderIntel")
        if down then
            text = blnpc_text("Map_LeaderDown")
        elseif not purchased and marker and marker.baseId then
            text = blnpc_text("Map_BaseCommanderIntel")
        elseif not purchased and marker and marker.groupId then
            text = blnpc_text("Map_SquadLeaderEstimated")
        end
        ui:drawTextCentre("★", x, y - 8, 1.0, 1.0, 1.0, 1.0, UIFont.Small)
        ui:drawTextCentre(text, x, y - 25, 1.0, 0.92, 0.15, 1.0, UIFont.Small)
    end
end

local function blnpc_drawLeaderIcon(ui, marker, x, y)
    if not marker then return end
    if marker.markerType == "group" and blnpc_settingBool("Debug_ShowGroupAuxLabels", false) ~= true then return end
    local text = nil
    if marker.leader == true or marker.isFactionLeader == true then
        if marker.leaderState == "dead" or marker.dead == true or blnpc_isStale(marker) then return end
        if marker.markerType == "group" and marker.active ~= true and marker.virtual ~= false then
            text = marker.leaderId and blnpc_text("Map_SquadLeaderEstimated") or nil
        else
            text = blnpc_text("Map_Leader")
        end
    elseif marker.commanderId then
        if marker.commanderState == "dead" or marker.dead == true or blnpc_isStale(marker) then return end
        text = blnpc_text("Map_Cmd")
    end
    if text and ui.drawTextCentre then
        ui:drawTextCentre(text, x, y - 66, 1.0, 0.88, 0.22, 1.0, UIFont.Small)
    end
end

local function blnpc_drawSpyIcon(ui, marker, x, y)
    if marker and marker.markerType == "group" and blnpc_settingBool("Debug_ShowGroupAuxLabels", false) ~= true then return end
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
    if marker.markerType == "group" and blnpc_settingBool("Debug_ShowGroupAuxLabels", false) ~= true then return end
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

    if marker.markerType == "black_market_turnin" then
        blnpc_drawBlackMarketTurnInMarker(ui, marker, x, y)
        return
    end

    if marker.markerType == "black_market_drop" then
        blnpc_drawBlackMarketDropMarker(ui, marker, x, y)
        return
    end

    local defenseTarget = marker.blackMarketDefenseEnemy == true
    local r, g, b = blnpc_factionColor(marker)
    if defenseTarget then
        r, g, b = 0.70, 0.25, 1.0
    elseif not r then
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
    elseif defenseTarget then
        size = 7
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
        if defenseTarget then
            blnpc_drawSmallLabel(ui, "DEFENCE GUARD", x, y + 12, 0.70, 0.25, 1.0, 0.96)
        elseif blnpc_isStale(marker) then
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
        else
            local displayName = blnpc_groupDisplayName(marker)
            if displayName then
                blnpc_drawSmallLabel(ui, displayName, x, y - 18, 0.95, 0.95, 1.0, 0.94)
            end
            -- Keep group labels to one player-facing name. The marker shape already
            -- communicates virtual/active state, so avoid stacking PATROL/GROUP text.
        end
    end

    blnpc_drawWoundedIcon(ui, marker, x, y)
    blnpc_drawLoyaltyIcon(ui, marker, x, y)
    blnpc_drawBountyHunterIcon(ui, marker, x, y)
    blnpc_drawLeaderIcon(ui, marker, x, y)
    blnpc_drawMercenaryLeaderIcon(ui, marker, x, y)
    blnpc_drawSpyIcon(ui, marker, x, y)
    if blnpc_settingBool("Debug_ShowGroupPowerLabels", false) then
        blnpc_drawGroupPower(ui, marker, x, y)
    end
end

function NPCDebugMapNPCMarkersBridge.RenderOnMap(ui, api, isMiniMap)
    if not blnpc_shouldRender(isMiniMap == true) then return end
    if not ui or not api then return end

    if isMiniMap ~= true and blnpc_settingBool("Debug_RequestSyncOnMapOpen", true) then
        local now = blnpc_nowMs()
        local cooldownSeconds = blnpc_settingNumber("Net_DebugMapRequestCooldownSeconds", 6.0, 0, 120)
        if NPCStreamingRuntimeBridge and NPCStreamingRuntimeBridge.AdjustMarkerInterval then
            cooldownSeconds = NPCStreamingRuntimeBridge.AdjustMarkerInterval(cooldownSeconds)
        end
        local cooldownMs = math.max(1500, cooldownSeconds * 1000)
        if now - (tonumber(NPCDebugMapNPCMarkersBridge._lastMapOpenSync) or 0) >= cooldownMs then
            NPCDebugMapNPCMarkersBridge._lastMapOpenSync = now
            NPCDebugMapNPCMarkersBridge.RequestSync()
        end
    end

    local loadLevel = blnpc_mapLoadLevel()
    blnpc_reconcileLocalMarkers(loadLevel >= 2)
    local w, h = blnpc_getSize(ui)
    local maxMarkers = blnpc_maxMarkersForLoad(isMiniMap == true, loadLevel)
    if maxMarkers <= 0 then return end

    NPCDebugMapNPCMarkersBridge._suppressMapLabels = blnpc_suppressLabelsForLoad(isMiniMap == true, loadLevel)
    local drawn = 0
    for _, marker in pairs(NPCDebugMapNPCMarkersBridge.markers) do
        if drawn >= maxMarkers then break end
        if marker and marker.x and marker.y and blnpc_shouldRenderPresenceMarker(marker) and not marker.dead then
            local mapX, mapY = blnpc_projectGroupMapPosition(marker)
            local x, y = blnpc_worldToUI(api, mapX or marker.x, mapY or marker.y)
            if x and y then
                x, y = blnpc_stabilizeScreenPosition(marker, x, y, isMiniMap == true)
                local margin = isMiniMap == true and 36 or 96
                if w <= 0 or h <= 0 or (x >= -margin and y >= -margin and x <= w + margin and y <= h + margin) then
                    blnpc_drawDot(ui, marker, x, y)
                    drawn = drawn + 1
                end
            end
        end
    end
    NPCDebugMapNPCMarkersBridge._suppressMapLabels = nil
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

    blnpc_reconcileLocalMarkers(false)
    for _, marker in pairs(NPCDebugMapNPCMarkersBridge.markers or {}) do
        local materializeId = nil
        if type(marker) == "table" and marker.markerReconciledGhost ~= true and marker.markerType == "group" and marker.virtual ~= false and marker.active ~= true and not blnpc_isStale(marker) then
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

    if blnpc_isSinglePlayerRuntime() and NPCWorldDirector and NPCWorldDirector.EnsureData and NPCWorldDirector.MaterializeGroup then
        local ok, materialized = pcall(function()
            local gmd = NPCWorldDirector.EnsureData()
            local group = gmd and gmd.VirtualGroups and gmd.VirtualGroups[tostring(best.materializeId or best.id)] or nil
            if group and group.activated ~= true then
                return NPCWorldDirector.MaterializeGroup(group, player)
            end
            return false
        end)
        if ok and materialized then return end
    end

    sendClientCommand(player, 'NPCCommands', 'DebugMapMaterializeNear', {markerId=tostring(best.materializeId or best.id), x=best.x, y=best.y})
end

local function blnpc_onTick(tick)
    tick = tonumber(tick) or ((tonumber(NPCDebugMapNPCMarkersBridge._tick) or 0) + 1)
    NPCDebugMapNPCMarkersBridge._tick = tick

    local nextHook = tonumber(NPCDebugMapNPCMarkersBridge._nextHookTick) or 0
    if tick >= nextHook then
        NPCDebugMapNPCMarkersBridge._nextHookTick = tick + 120
        NPCDebugMapNPCMarkersBridge.HookMaps()
        if NPCDebugMapNPCMarkersBridge.RefreshLocalVirtualGroups then
            NPCDebugMapNPCMarkersBridge.RefreshLocalVirtualGroups(false)
        end
        blnpc_reconcileLocalMarkers(false)
        blnpc_tryMaterializeNearbyVirtualMarker()
    end

    local nextSync = tonumber(NPCDebugMapNPCMarkersBridge._nextSyncTick) or 0
    if tick >= nextSync then
        local interval = 240
        if NPCStreamingRuntimeBridge and NPCStreamingRuntimeBridge.AdjustMarkerInterval then
            interval = math.max(interval, math.floor(NPCStreamingRuntimeBridge.AdjustMarkerInterval(interval)))
        end
        NPCDebugMapNPCMarkersBridge._nextSyncTick = tick + interval
        NPCDebugMapNPCMarkersBridge.RequestSync()
    end
end

local function blnpc_registerTickJob()
    -- Stage449: prefer scheduler-governed marker sync. Direct OnTick remains
    -- only as a fallback, so map/debug marker maintenance no longer runs every
    -- frame when the shared scheduler is already available.
    if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.RegisterTickJob then
        NPCWorkSchedulerBridge.RegisterTickJob("NPCDebugMapNPCMarkersBridge.Sync", blnpc_onTick, "marker", 30, 2)
        return
    end
    if Events and Events.OnTick and not NPCDebugMapNPCMarkersBridge._directTickInstalled then
        NPCDebugMapNPCMarkersBridge._directTickInstalled = true
        Events.OnTick.Add(blnpc_onTick)
    end
end

Events.OnServerCommand.Add(blnpc_onServerCommand)
Events.OnGameStart.Add(blnpc_onGameStart)
blnpc_registerTickJob()

NPCDebugMapNPCMarkersBridge.HookMaps()


NPCLegacyGlobalsBridge.InstallAlias("DebugMapNPCMarkers", NPCDebugMapNPCMarkersBridge, "NPCDebugMapNPCMarkersBridge")
