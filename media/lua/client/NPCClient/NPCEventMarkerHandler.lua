require "NPCClient/NPCEventMarkerUI"
require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCLegacyContractBridge"

NPCEventMarkerHandler = NPCEventMarkerHandler or {}
NPCEventMarkerHandler.markers = NPCEventMarkerHandler.markers or {}
NPCEventMarkerHandler.expirations = NPCEventMarkerHandler.expirations or {}

local NPC_EVENT_MARKER_PLACEMENT_KEY = NPCLegacyContractBridge and (NPCLegacyContractBridge.Token .. "EventMarkerPlacement") or "NPCEventMarkerPlacement"

local function activePlayerCount()
    return getNumActivePlayers and getNumActivePlayers() or 1
end

local function getPlayerByIndex(index)
    if getSpecificPlayer then
        return getSpecificPlayer(index)
    end
    if index == 0 and getPlayer then
        return getPlayer()
    end
    return nil
end

local function getSavedPlacement(player)
    if not player or not player.getModData then
        return nil, nil
    end
    local data = player:getModData()[NPC_EVENT_MARKER_PLACEMENT_KEY]
    if type(data) == "table" then
        return data[1], data[2]
    end
    return nil, nil
end

local function defaultMarkerScreenPosition(player)
    local oldX, oldY = getSavedPlacement(player)
    local screenW = getCore and getCore():getScreenWidth() or 800
    local markerClass = NPCEventMarker or NPCLegacyGlobalsBridge.Get("EventMarker")
    return oldX or ((screenW / 2) - (markerClass.iconSize / 2)), oldY or (markerClass.iconSize / 2)
end

local function isMarkerInInitialRange(player, x, y)
    if not player or not x or not y or not IsoUtils or not IsoUtils.DistanceTo then
        return false
    end
    local dist = IsoUtils.DistanceTo(x, y, player:getX(), player:getY())
    local markerClass = NPCEventMarker or NPCLegacyGlobalsBridge.Get("EventMarker")
    return dist and dist <= markerClass.maxRange
end

function NPCEventMarkerHandler.GetPlayerBucket(player)
    if not player then return nil end
    NPCEventMarkerHandler.markers[player] = NPCEventMarkerHandler.markers[player] or {}
    NPCEventMarkerHandler.expirations[player] = NPCEventMarkerHandler.expirations[player] or {}
    return NPCEventMarkerHandler.markers[player], NPCEventMarkerHandler.expirations[player]
end

function NPCEventMarkerHandler.CreateMarker(player, eventID, icon, duration, posX, posY, color, desc)
    local markerClass = NPCEventMarker or NPCLegacyGlobalsBridge.Get("EventMarker")
    if not markerClass or not player or not eventID or duration <= 0 then
        return nil
    end
    if not isMarkerInInitialRange(player, posX, posY) then
        return nil
    end

    local screenX, screenY = defaultMarkerScreenPosition(player)
    return markerClass:new(eventID, icon, duration, posX, posY, player, screenX, screenY, color, desc)
end

function NPCEventMarkerHandler.setOrUpdate(eventID, icon, duration, posX, posY, color, desc)
    if not eventID then return end
    duration = tonumber(duration) or 0

    for playerIndex = 0, activePlayerCount() - 1 do
        local player = getPlayerByIndex(playerIndex)
        if player then
            local markers, expirations = NPCEventMarkerHandler.GetPlayerBucket(player)
            if markers and expirations then
                expirations[eventID] = (getGametimeTimestamp and getGametimeTimestamp() or 0) + duration

                local marker = markers[eventID]
                if not marker and duration > 0 then
                    marker = NPCEventMarkerHandler.CreateMarker(player, eventID, icon, duration, posX, posY, color, desc)
                    markers[eventID] = marker
                end

                if marker then
                    if icon and getTexture then
                        marker.textureIcon = getTexture(icon)
                    end
                    if color then
                        marker.markerColor = color
                    end
                    marker.desc = desc or marker.desc
                    marker:setDuration(duration)
                    marker:update(posX, posY)
                end
            end
        end
    end
end

function NPCEventMarkerHandler.unSet(eventID)
    if not eventID then return end
    for player, markers in pairs(NPCEventMarkerHandler.markers) do
        local marker = markers and markers[eventID]
        if marker then
            marker:setDuration(0)
            marker:setVisible(false)
            markers[eventID] = nil
        end
        if NPCEventMarkerHandler.expirations[player] then
            NPCEventMarkerHandler.expirations[player][eventID] = nil
        end
    end
end

function NPCEventMarkerHandler.updatePos(eventID, posX, posY)
    if not eventID then return end
    for _, markers in pairs(NPCEventMarkerHandler.markers) do
        local marker = markers and markers[eventID]
        if marker then
            marker:update(posX, posY)
        end
    end
end

function NPCEventMarkerHandler.OnPlayerUpdate(player)
    if not player then return end
    local markers = NPCEventMarkerHandler.markers[player]
    if not markers then return end
    for _, marker in pairs(markers) do
        if marker and marker.update then
            marker:update(marker.posX, marker.posY)
        end
    end
end

NPCEventMarkerHandler = NPCLegacyGlobalsBridge.InstallAlias("EventMarkerHandler", NPCEventMarkerHandler, "NPCEventMarkerHandler")

return NPCEventMarkerHandler
