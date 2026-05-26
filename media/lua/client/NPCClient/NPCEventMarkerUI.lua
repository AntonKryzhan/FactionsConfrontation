require "ISUI/ISUIElement"
require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCLegacyContractBridge"

NPCEventMarkerUI = NPCEventMarkerUI or {}

local NPC_EVENT_MARKER_PLACEMENT_KEY = NPCLegacyContractBridge and (NPCLegacyContractBridge.Token .. "EventMarkerPlacement") or "NPCEventMarkerPlacement"

local Marker = ISUIElement:derive("NPCEventMarker")

Marker.iconSize = 96
Marker.clickableSize = 45
Marker.maxRange = 500

local function safeTexture(path)
    if path and getTexture then
        return getTexture(path)
    end
    return nil
end

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function calculateBlend(color, underLayer, fade)
    local source = color or { r = 1, g = 0.5, b = 0.5, a = 1 }
    local base = underLayer or { r = 0.22, g = 0.22, b = 0.22, a = 1 }
    local alpha = clamp(fade or 1, 0.01, 1)
    local sourceAlpha = alpha
    local alphaShift = 1 - (1 - sourceAlpha) * (1 - (base.a or 1))
    if alphaShift <= 0 then
        return { r = source.r or 1, g = source.g or 1, b = source.b or 1, a = 1 }
    end
    return {
        r = ((source.r or 1) * (source.r or 1) / alphaShift) + ((base.r or 0) * (base.a or 1) * (1 - sourceAlpha) / alphaShift),
        g = ((source.g or 1) * (source.g or 1) / alphaShift) + ((base.g or 0) * (base.a or 1) * (1 - sourceAlpha) / alphaShift),
        b = ((source.b or 1) * (source.b or 1) / alphaShift) + ((base.b or 0) * (base.a or 1) * (1 - sourceAlpha) / alphaShift),
        a = 1
    }
end

function Marker:initialise()
    ISUIElement.initialise(self)
    self:addToUIManager()
    self.moveWithMouse = true
    self:setVisible(false)
end

function Marker:onMouseDoubleClick(x, y)
    self:setDuration(0)
    return true
end

function Marker:stopMoving()
    self.moving = false
    if ISMouseDrag then
        ISMouseDrag.dragView = nil
    end
end

function Marker:onMouseUp(x, y)
    if not self.moveWithMouse or not self:getIsVisible() then
        return
    end
    self:stopMoving()
    if ISMouseDrag and ISMouseDrag.tabPanel then
        ISMouseDrag.tabPanel:onMouseUp(x, y)
    end
end

function Marker:onMouseUpOutside(x, y)
    if not self.moveWithMouse or not self:getIsVisible() then
        return
    end
    self:stopMoving()
end

function Marker:onMouseDown(x, y)
    if not self.moveWithMouse then
        return true
    end
    if not self:getIsVisible() or not self:isMouseOver() then
        return
    end
    self.downX = x
    self.downY = y
    self.moving = true
    self:bringToTop()
    return true
end

function Marker:storePlacement()
    local player = self:getPlayer()
    if player and player.getModData then
        player:getModData()[NPC_EVENT_MARKER_PLACEMENT_KEY] = { self.x, self.y }
    end
end

function Marker:applyDrag(dx, dy)
    if not self.moveWithMouse or not self.moving then
        return
    end
    if self.parent then
        self.parent:setX(self.parent.x + dx)
        self.parent:setY(self.parent.y + dy)
    else
        self:setX(self.x + dx)
        self:setY(self.y + dy)
        self:bringToTop()
    end
    self:storePlacement()
end

function Marker:onMouseMoveOutside(dx, dy)
    if not self.moveWithMouse then return end
    self.mouseOver = false
    self:applyDrag(dx, dy)
end

function Marker:onMouseMove(dx, dy)
    if not self.moveWithMouse then return end
    self.mouseOver = true
    self:applyDrag(dx, dy)
end

function Marker:setDistance(dist)
    self.distanceToPoint = dist or Marker.maxRange
end

function Marker:setAngleFromPoint(posX, posY)
    if not posX or not posY or not self.player or not self.player.getX or not self.player.getY then
        return
    end
    local radians = math.atan2(posY - self.player:getY(), posX - self.player:getX()) + math.pi
    self.angle = ((radians * 180 / math.pi + 270) + 45) % 360
    self.posX = posX
    self.posY = posY
end

function Marker:setAngle(value)
    self.angle = value or 0
end

function Marker:setDuration(value)
    self.duration = tonumber(value) or 0
    if self.duration <= 0 then
        self:setVisible(false)
    end
end

function Marker:getDuration()
    return self.duration or 0
end

function Marker:render()
    if not self.visible or self:getDuration() <= 0 then
        return
    end

    self:setAngleFromPoint(self.posX, self.posY)

    local centerX = self.width / 2
    local centerY = self.height / 2
    local radius = self.radius or Marker.maxRange
    local dist = self.distanceToPoint or Marker.maxRange
    local distanceOverRadius = radius > 0 and (dist / radius) or 1
    local alphaFromDist = 0.2 + (0.8 * (1 - distanceOverRadius))
    local drawColor = calculateBlend(self.markerColor, { r = 0.22, g = 0.22, b = 0.22, a = 1 }, alphaFromDist)

    if self.textureBG then
        self:drawTexture(self.textureBG, centerX - (Marker.iconSize / 2), centerY - (Marker.iconSize / 2), 1, drawColor.r, drawColor.g, drawColor.b)
    end
    if self.desc then
        self:drawTextCentre(self.desc, centerX, centerY + 25, 1, 1, 1, 1, UIFont.Small)
    end

    local textureForPoint = self.texturePoint
    if distanceOverRadius <= (8 / Marker.maxRange) then
        textureForPoint = self.texturePointClose or textureForPoint
    elseif distanceOverRadius <= (125 / Marker.maxRange) then
        textureForPoint = self.texturePoint
    elseif distanceOverRadius <= (375 / Marker.maxRange) then
        textureForPoint = self.texturePointMedium or textureForPoint
    else
        textureForPoint = self.texturePointFar or textureForPoint
    end

    if textureForPoint and self.DrawTextureAngle then
        self:DrawTextureAngle(textureForPoint, centerX, centerY, self.angle or 0)
    end
    if self.textureIcon then
        self:drawTexture(self.textureIcon, centerX - (Marker.iconSize / 2), centerY - (Marker.iconSize / 2), 1, 1, 1, 1)
    end

    if self.player and getNumActivePlayers and getNumActivePlayers() > 1 and self.player.getPlayerNum then
        local coopTexture = self.textureCoopNum[(self.player:getPlayerNum() or 0) + 1]
        if coopTexture then
            self:drawTexture(coopTexture, centerX - (Marker.iconSize / 2), centerY - (Marker.iconSize / 2), 1, 1, 1, 1)
        end
    end

    ISUIElement.render(self)
end

function Marker:setEnabled(value)
    self.enabled = value and true or false
end

function Marker:getEnabled()
    return self.enabled
end

function Marker:prerender()
end

function Marker:refresh()
    self.opacity = 0
    self.opacityGain = 2
end

function Marker:getPlayer()
    return self.player
end

local function markerRadius(player)
    local radius = Marker.maxRange * 0.83
    if player and player.HasTrait then
        if player:HasTrait("EagleEyed") then
            radius = radius * 1.2
        elseif player:HasTrait("ShortSighted") then
            radius = radius * 0.8
        end
        local hour = getGameTime and getGameTime():getHour() or 12
        if hour < 6 or hour > 22 then
            if player:HasTrait("NightVision") then
                radius = radius * 1.1
            else
                radius = radius * 0.75
            end
        end
    end
    if player and player.isOutside and not player:isOutside() then
        radius = radius * 0.33
    end
    return clamp(radius, Marker.maxRange / 3, Marker.maxRange)
end

function Marker:update(posX, posY)
    if not self.enabled then return end

    local timeStamp = getTimeInMillis and getTimeInMillis() or 0
    if self.lastUpdateTime and self.lastUpdateTime + 5 >= timeStamp then
        return
    end
    self.lastUpdateTime = timeStamp

    posX = posX or self.posX
    posY = posY or self.posY
    if not posX or not posY or not self.player or not self.player.getX or not self.player.getY then
        self:setVisible(false)
        return
    end

    self.radius = markerRadius(self.player)
    if self:getDuration() <= 0 then
        self:setVisible(false)
        return
    end

    local dist = IsoUtils and IsoUtils.DistanceTo and IsoUtils.DistanceTo(posX, posY, self.player:getX(), self.player:getY()) or nil
    self.posX = posX
    self.posY = posY
    if dist and dist <= self.radius then
        self:setDistance(dist)
        self:setAngleFromPoint(self.posX, self.posY)
        self:setVisible(true)
    else
        self:setVisible(false)
    end
end

function Marker:new(eventID, icon, duration, posX, posY, player, screenX, screenY, color, desc)
    local o = ISUIElement:new(screenX or 0, screenY or 0, 1, 1)
    setmetatable(o, self)
    self.__index = self

    o.eventID = eventID
    o.player = player
    o.x = screenX or 0
    o.y = screenY or 0
    o.markerColor = color or { r = 1, g = 0.5, b = 0.5, a = 1 }
    o.posX = posX or 0
    o.posY = posY or 0
    o.width = Marker.clickableSize
    o.height = Marker.clickableSize
    o.angle = 0
    o.opacity = 255
    o.opacityGain = 2
    o.duration = duration or 0
    o.lastUpdateTime = -1
    o.enabled = true
    o.visible = true
    o.title = ""
    o.distanceToPoint = Marker.maxRange
    o.radius = nil
    o.mouseOver = false
    o.tooltip = nil
    o.center = false
    o.bConsumeMouseEvents = false
    o.joypadFocused = false
    o.translation = nil
    o.texturePoint = safeTexture("media/ui/eventMarker.png")
    o.texturePointClose = safeTexture("media/ui/eventMarker_close.png")
    o.texturePointMedium = safeTexture("media/ui/eventMarker_medium.png")
    o.texturePointFar = safeTexture("media/ui/eventMarker_far.png")
    o.textureBG = safeTexture("media/ui/eventMarkerBase.png")
    o.textureCoopNum = {
        safeTexture("media/ui/coop1.png"),
        safeTexture("media/ui/coop2.png"),
        safeTexture("media/ui/coop3.png"),
        safeTexture("media/ui/coop4.png")
    }
    o.textureIcon = safeTexture(icon)
    o.desc = desc
    o:initialise()
    return o
end

NPCEventMarkerUI.Marker = Marker
NPCEventMarker = Marker
NPCLegacyGlobalsBridge.InstallAlias("EventMarker", Marker, "NPCEventMarker")

return NPCEventMarkerUI
