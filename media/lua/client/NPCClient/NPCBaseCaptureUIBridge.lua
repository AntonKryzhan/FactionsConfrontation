-- NPCBaseCaptureUIBridge.lua
-- Client HUD for nearby strategic base capture progress.

require "NPCCore/NPCLegacyContractBridge"
require "ISUI/ISUIElement"

NPCBaseCaptureUIBridge = NPCBaseCaptureUIBridge or {}
NPCBaseCaptureUIBridge.Enabled = true
NPCBaseCaptureUIBridge.NearRadius = NPCBaseCaptureUIBridge.NearRadius or 150
NPCBaseCaptureUIBridge.BasePadRadius = NPCBaseCaptureUIBridge.BasePadRadius or 8
NPCBaseCaptureUIBridge.DisplaySeconds = NPCBaseCaptureUIBridge.DisplaySeconds or 8
NPCBaseCaptureUIBridge.DisplayUntilMs = NPCBaseCaptureUIBridge.DisplayUntilMs or 0
NPCBaseCaptureUIBridge.CurrentBaseId = NPCBaseCaptureUIBridge.CurrentBaseId or nil
NPCBaseCaptureUIBridge.bases = NPCBaseCaptureUIBridge.bases or {}
NPCBaseCaptureUIBridge.zones = NPCBaseCaptureUIBridge.zones or {}
NPCBaseCaptureUIBridge._tick = NPCBaseCaptureUIBridge._tick or 0
NPCBaseCaptureUIBridge.panel = NPCBaseCaptureUIBridge.panel or nil

local function bbc_asNumber(value, fallback)
    local n = tonumber(value)
    if n == nil then return fallback end
    return n
end

local function bbc_nowMs()
    if getTimestampMs then
        local ok, value = pcall(function() return getTimestampMs() end)
        if ok and tonumber(value) then return tonumber(value) end
    end
    if getGameTime then
        local ok, value = pcall(function() return math.floor((getGameTime():getWorldAgeHours() or 0) * 3600000) end)
        if ok and tonumber(value) then return tonumber(value) end
    end
    if os and os.time then
        local ok, value = pcall(function() return os.time() * 1000 end)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return 0
end

local function bbc_text(key, fallback)
    local text = getText and getText(key) or nil
    if not text or text == key then return fallback end
    return text
end

local function bbc_truncate(value, maxLen)
    local text = tostring(value or "")
    maxLen = tonumber(maxLen) or 46
    if string.len(text) <= maxLen then return text end
    if maxLen <= 3 then return string.sub(text, 1, maxLen) end
    return string.sub(text, 1, maxLen - 3) .. "..."
end

local BBC_NEED_LABEL = {
    F = "Food", W = "Water", A = "Ammo", M = "Medical", U = "Fuel",
    R = "Materials", T = "Tools", G = "Weapons", P = "Parts", S = "Supplies",
    food = "Food", water = "Water", ammo = "Ammo", medical = "Medical", fuel = "Fuel",
    materials = "Materials", tools = "Tools", weapons = "Weapons", spareParts = "Parts", supplies = "Supplies"
}

local function bbc_formatNeedSummary(value)
    local text = tostring(value or "ok")
    if text == "" or text == "ok" then return "Needs: ok" end
    if text == "neutral" then return "Needs: neutral" end

    local critical = {}
    local low = {}
    for token in string.gmatch(text, "%S+") do
        local key, status = string.match(token, "([^:]+):([^:]+)")
        if key and status then
            local label = BBC_NEED_LABEL[key] or tostring(key)
            if status == "critical" then
                table.insert(critical, label)
            elseif status == "low" then
                table.insert(low, label)
            end
        end
    end

    if #critical > 0 then
        return bbc_truncate("Critical: " .. table.concat(critical, ", "), 48)
    end
    if #low > 0 then
        return bbc_truncate("Low: " .. table.concat(low, ", "), 48)
    end
    return bbc_truncate("Needs: " .. text, 48)
end

local function bbc_statusUpper(value)
    local text = tostring(value or "unknown")
    return string.upper(text)
end

local function bbc_dist(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return math.sqrt(dx * dx + dy * dy)
end

local function bbc_copyBase(marker)
    if not marker or marker.markerType ~= "base" then return nil end
    local x = bbc_asNumber(marker.x, nil)
    local y = bbc_asNumber(marker.y, nil)
    if not x or not y then return nil end

    local base = {}
    for k, v in pairs(marker) do
        base[k] = v
    end

    base.id = tostring(marker.baseId or marker.id or (tostring(x) .. "_" .. tostring(y)))
    base.x = x
    base.y = y
    base.z = bbc_asNumber(marker.z, 0)
    base.progress = bbc_asNumber(marker.progress or marker.captureProgress, 0)
    base.radius = bbc_asNumber(marker.radius, 36)
    return base
end

local function bbc_copyZone(marker)
    if not marker or marker.markerType ~= "base_zone" then return nil end
    local x = bbc_asNumber(marker.x, nil)
    local y = bbc_asNumber(marker.y, nil)
    if not x or not y then return nil end

    local zone = {}
    for k, v in pairs(marker) do
        zone[k] = v
    end

    zone.id = tostring(marker.baseZoneId or marker.zoneId or marker.id or (tostring(x) .. "_" .. tostring(y)))
    zone.baseId = tostring(marker.baseId or marker.parentBaseId or "")
    zone.x = x
    zone.y = y
    zone.z = bbc_asNumber(marker.z, 0)
    zone.assignedCount = bbc_asNumber(marker.assignedCount, 0)
    zone.presentCount = bbc_asNumber(marker.presentCount, 0)
    zone.capacity = bbc_asNumber(marker.capacity, 0)
    zone.stockFood = bbc_asNumber(marker.stockFood, 0)
    zone.stockMedical = bbc_asNumber(marker.stockMedical, 0)
    zone.stockAmmo = bbc_asNumber(marker.stockAmmo, 0)
    zone.stockSupplies = bbc_asNumber(marker.stockSupplies, 0)
    zone.stockWater = bbc_asNumber(marker.stockWater, 0)
    zone.stockMaterials = bbc_asNumber(marker.stockMaterials, 0)
    zone.stockSecurity = bbc_asNumber(marker.stockSecurity, 0)
    zone.readiness = bbc_asNumber(marker.readiness, 0)
    zone.demandScore = bbc_asNumber(marker.demandScore, 0)
    zone.deficitScore = bbc_asNumber(marker.deficitScore, 0)
    zone.operational = marker.operational ~= false
    return zone
end

function NPCBaseCaptureUIBridge.IsEnabled()
    return NPCBaseCaptureUIBridge.Enabled == true
end

function NPCBaseCaptureUIBridge.SetBase(marker)
    local base = bbc_copyBase(marker)
    if not base then return end
    NPCBaseCaptureUIBridge.bases[base.id] = base
end

function NPCBaseCaptureUIBridge.SetZone(marker)
    local zone = bbc_copyZone(marker)
    if not zone or zone.baseId == "" then return end
    NPCBaseCaptureUIBridge.zones[zone.baseId] = NPCBaseCaptureUIBridge.zones[zone.baseId] or {}
    NPCBaseCaptureUIBridge.zones[zone.baseId][zone.id] = zone
end

function NPCBaseCaptureUIBridge.RemoveBase(id)
    if not id then return end
    id = tostring(id)
    NPCBaseCaptureUIBridge.bases[id] = nil
    NPCBaseCaptureUIBridge.zones[id] = nil
    if string.sub(id, 1, 5) == "BASE_" then
        local baseId = string.sub(id, 6)
        NPCBaseCaptureUIBridge.bases[baseId] = nil
        NPCBaseCaptureUIBridge.zones[baseId] = nil
    end
end

local function bbc_ownerText(base)
    if not base then return "" end
    if base.captureStatus == "contested" or base.contested then
        return "CONTESTED"
    end
    if base.owner == "green" then return "OWNER: GREEN" end
    if base.owner == "red" then return "OWNER: RED" end
    if base.captureTeam == "green" then return "CAPTURE: GREEN" end
    if base.captureTeam == "red" then return "CAPTURE: RED" end
    return "NEUTRAL BASE"
end

local function bbc_statusText(base)
    if not base then return "" end
    local status = tostring(base.captureStatus or "idle")
    if status == "controlled" then return "controlled" end
    if status == "capturing" then return "capturing" end
    if status == "decapturing" then return "decapturing" end
    if status == "contested" then return "timer stopped" end
    if status == "paused" then return "paused" end
    return "waiting for squad"
end

local function bbc_getBaseZones(base)
    if not base then return nil end
    return NPCBaseCaptureUIBridge.zones[tostring(base.id or base.baseId or "")]
end

local function bbc_zoneLine(base)
    local zones = bbc_getBaseZones(base)
    local counts = {command=0, staging=0, storage=0, sleep=0, medical=0, food=0, ammo=0, guard=0, patrol=0}
    local total = 0

    for _, zone in pairs(zones or {}) do
        if type(zone) == "table" then
            local zt = tostring(zone.zoneType or "unknown")
            counts[zt] = (counts[zt] or 0) + 1
            total = total + 1
        end
    end

    if total <= 0 and base.zoneCount then
        return "Zones: " .. tostring(base.zoneCount)
    end

    if total <= 0 then return "Zones: waiting sync" end

    return "Zones: " .. tostring(total)
        .. "  Guard " .. tostring(counts.guard or 0)
        .. "  Patrol " .. tostring(counts.patrol or 0)
        .. "  Storage " .. tostring(counts.storage or 0)
end

local function bbc_zoneStockLine(base)
    local zones = bbc_getBaseZones(base)
    local food, med, ammo, supplies = 0, 0, 0, 0
    local assigned, present = 0, 0

    for _, zone in pairs(zones or {}) do
        if type(zone) == "table" then
            food = food + (tonumber(zone.stockFood) or 0)
            med = med + (tonumber(zone.stockMedical) or 0)
            ammo = ammo + (tonumber(zone.stockAmmo) or 0)
            supplies = supplies + (tonumber(zone.stockSupplies) or 0)
            assigned = assigned + (tonumber(zone.assignedCount) or 0)
            present = present + (tonumber(zone.presentCount) or 0)
        end
    end

    if food + med + ammo + supplies <= 0 then
        food = tonumber(base.stockFood) or 0
        med = tonumber(base.stockMedical) or 0
        ammo = tonumber(base.stockAmmo) or 0
        supplies = tonumber(base.stockSupplies) or 0
    end

    if food + med + ammo + supplies + assigned + present <= 0 then
        return "Duty/stock: no data yet"
    end

    return "Duty " .. tostring(math.floor(present)) .. "/" .. tostring(math.floor(assigned))
        .. "  Food " .. tostring(math.floor(food))
        .. "  Med " .. tostring(math.floor(med))
        .. "  Ammo " .. tostring(math.floor(ammo))
        .. "  Supplies " .. tostring(math.floor(supplies))
end

local function bbc_readinessLine(base)
    if not base then return "Readiness: no data" end
    local garrison = math.floor(tonumber(base.garrisonReadiness) or 0)
    local defense = math.floor(tonumber(base.defenseReadiness) or 0)
    local logistics = math.floor(tonumber(base.logisticsReadiness) or 0)
    local food = math.floor(tonumber(base.foodReadiness) or 0)
    local ammo = math.floor(tonumber(base.ammoReadiness) or 0)
    return "Ready: G " .. tostring(garrison) .. "%  Def " .. tostring(defense) .. "%  Log " .. tostring(logistics) .. "%  Food " .. tostring(food) .. "%  Ammo " .. tostring(ammo) .. "%"
end

local function bbc_zoneHealthLine(base)
    if not base then return "Zones: no data" end
    local operational = math.floor(tonumber(base.operationalZones) or 0)
    local low = math.floor(tonumber(base.lowZones) or 0)
    local overloaded = math.floor(tonumber(base.overloadedZones) or 0)
    local need = tostring(base.zoneNeedSummary or "ok")
    if need ~= "ok" and string.len(need) > 32 then need = string.sub(need, 1, 29) .. "..." end
    return "Zones: operational " .. tostring(operational) .. "  low " .. tostring(low) .. "  overloaded " .. tostring(overloaded) .. "  " .. need
end

local function bbc_economyLine(base)
    if not base then return "Economy: no data" end
    local status = bbc_statusUpper(base.economyStatus or "unknown")
    local missions = math.floor(tonumber(base.missionCount) or 0)
    return "Economy status: " .. status .. "  Missions: " .. tostring(missions)
end

local function bbc_economyNeedLine(base)
    if not base then return "Needs: no data" end
    return bbc_formatNeedSummary(base.needSummary or "ok")
end

local function bbc_economyLogisticsLine(base)
    if not base then return "Logistics: no data" end
    local water = math.floor(tonumber(base.stockWater) or 0)
    local fuel = math.floor(tonumber(base.stockFuel) or 0)
    local materials = math.floor(tonumber(base.stockMaterials) or 0)
    return "Stock: Water " .. tostring(water) .. "  Fuel " .. tostring(fuel) .. "  Materials " .. tostring(materials)
end

NPCBaseCapturePanelBridge = NPCBaseCapturePanelBridge or ISUIElement:derive("NPCBaseCapturePanelBridge")

function NPCBaseCapturePanelBridge:initialise()
    ISUIElement.initialise(self)
    self:setVisible(false)
    self:addToUIManager()
end

function NPCBaseCapturePanelBridge:setBase(base, dist)
    self.base = base
    self.distance = dist or 0
    self:setVisible(base ~= nil)
end

function NPCBaseCapturePanelBridge:render()
    if not self.base then return end

    local base = self.base
    local progress = bbc_asNumber(base.progress or base.captureProgress, 0)
    if progress < 0 then progress = 0 end
    if progress > 100 then progress = 100 end

    local r, g, b = 0.75, 0.75, 0.75
    if base.owner == "green" or base.captureTeam == "green" then
        r, g, b = 0.10, 0.90, 0.20
    elseif base.owner == "red" or base.captureTeam == "red" then
        r, g, b = 1.00, 0.10, 0.08
    end
    if base.captureStatus == "contested" or base.contested then
        r, g, b = 1.00, 0.80, 0.12
    end

    self:drawRect(0, 0, self.width, self.height, 0.72, 0.02, 0.02, 0.02)
    self:drawRectBorder(0, 0, self.width, self.height, 0.90, r, g, b)
    self:drawText(tostring(base.name or base.id or "Base"), 10, 8, 1, 1, 1, 1, UIFont.Small)
    self:drawText(bbc_ownerText(base), 10, 25, r, g, b, 1, UIFont.Small)
    self:drawText(bbc_statusText(base) .. "  " .. tostring(math.floor(progress + 0.5)) .. "%", 10, 42, 0.88, 0.88, 0.88, 1, UIFont.Small)
    self:drawText(bbc_zoneLine(base), 10, 59, 0.78, 0.78, 0.78, 1, UIFont.Small)
    self:drawText(bbc_zoneStockLine(base), 10, 76, 0.78, 0.78, 0.78, 1, UIFont.Small)
    self:drawText(bbc_readinessLine(base), 10, 93, 0.78, 0.78, 0.78, 1, UIFont.Small)
    self:drawText(bbc_zoneHealthLine(base), 10, 110, 0.78, 0.78, 0.78, 1, UIFont.Small)
    self:drawText(bbc_economyLine(base), 10, 127, 0.78, 0.78, 0.78, 1, UIFont.Small)
    self:drawText(bbc_economyNeedLine(base), 10, 144, 0.78, 0.78, 0.78, 1, UIFont.Small)
    self:drawText(bbc_economyLogisticsLine(base), 10, 161, 0.78, 0.78, 0.78, 1, UIFont.Small)

    local barX = 10
    local barY = 185
    local barW = self.width - 20
    local barH = 9
    self:drawRect(barX, barY, barW, barH, 0.92, 0, 0, 0)
    self:drawRect(barX + 1, barY + 1, math.floor((barW - 2) * (progress / 100)), barH - 2, 0.96, r, g, b)

    ISUIElement.render(self)
end

function NPCBaseCapturePanelBridge:new(x, y, w, h)
    local o = ISUIElement:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.border = false
    o.moveWithMouse = false
    o.base = nil
    o.distance = 0
    return o
end

function NPCBaseCaptureUIBridge.EnsurePanel()
    if NPCBaseCaptureUIBridge.panel then return NPCBaseCaptureUIBridge.panel end

    local sw = getCore() and getCore():getScreenWidth() or 1280
    local x = math.floor((sw - 300) / 2)
    local y = 72
    NPCBaseCaptureUIBridge.panel = NPCBaseCapturePanelBridge:new(x, y, 390, 213)
    NPCBaseCaptureUIBridge.panel:initialise()
    return NPCBaseCaptureUIBridge.panel
end

function NPCBaseCaptureUIBridge.FindNearbyBase()
    local player = getPlayer()
    if not player then return nil, nil end

    local px = player:getX()
    local py = player:getY()
    local best = nil
    local bestDist = 999999

    for _, base in pairs(NPCBaseCaptureUIBridge.bases or {}) do
        if base and base.x and base.y then
            local radius = math.max(NPCBaseCaptureUIBridge.NearRadius, bbc_asNumber(base.radius, 36) + 60)
            local d = bbc_dist(px, py, base.x, base.y)
            if d <= radius and d < bestDist then
                best = base
                bestDist = d
            end
        end
    end

    return best, bestDist
end

function NPCBaseCaptureUIBridge.FindCurrentBase()
    local player = getPlayer()
    if not player then return nil, nil end

    local px = player:getX()
    local py = player:getY()
    local best = nil
    local bestDist = 999999

    for _, base in pairs(NPCBaseCaptureUIBridge.bases or {}) do
        if base and base.x and base.y then
            local radius = math.max(1, bbc_asNumber(base.radius, 36)) + (tonumber(NPCBaseCaptureUIBridge.BasePadRadius) or 8)
            local d = bbc_dist(px, py, base.x, base.y)
            if d <= radius and d < bestDist then
                best = base
                bestDist = d
            end
        end
    end

    return best, bestDist
end

function NPCBaseCaptureUIBridge.GetDisplaySeconds()
    local seconds = tonumber(NPCBaseCaptureUIBridge.DisplaySeconds) or 8
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        local ok, value = pcall(function() return NPCLegacySettingsBridge.GetNumber("Base_StatusWindowTimeoutSeconds", seconds, 1, 120) end)
        if ok and tonumber(value) then seconds = tonumber(value) end
    end
    if seconds < 1 then seconds = 1 end
    if seconds > 120 then seconds = 120 end
    return seconds
end

function NPCBaseCaptureUIBridge.ShowBase(base, dist)
    if not base then
        base, dist = NPCBaseCaptureUIBridge.FindCurrentBase()
    end
    if not base then return false end

    NPCBaseCaptureUIBridge.DisplayUntilMs = bbc_nowMs() + math.floor(NPCBaseCaptureUIBridge.GetDisplaySeconds() * 1000)
    local panel = NPCBaseCaptureUIBridge.EnsurePanel()
    panel:setBase(base, dist)
    return true
end

function NPCBaseCaptureUIBridge.ShowCurrentBase(player)
    return NPCBaseCaptureUIBridge.ShowBase()
end

function NPCBaseCaptureUIBridge.AddContextMenu(context, player)
    if not context or not NPCBaseCaptureUIBridge.IsEnabled() then return end
    local base = NPCBaseCaptureUIBridge.FindCurrentBase()
    if not base then return end

    context:addOption(bbc_text(NPCLegacyContractBridge.Text.prefix .. "Menu_ShowBaseStatus", "Show base status"), player, NPCBaseCaptureUIBridge.ShowCurrentBase)
end

function NPCBaseCaptureUIBridge.Update()
    if not NPCBaseCaptureUIBridge.IsEnabled() then return false end

    local panel = NPCBaseCaptureUIBridge.EnsurePanel()
    local base, dist = NPCBaseCaptureUIBridge.FindCurrentBase()
    local now = bbc_nowMs()

    if not base then
        NPCBaseCaptureUIBridge.CurrentBaseId = nil
        NPCBaseCaptureUIBridge.DisplayUntilMs = 0
        panel:setBase(nil, nil)
        return false
    end

    local baseId = tostring(base.id or base.baseId or "")
    if baseId ~= "" and NPCBaseCaptureUIBridge.CurrentBaseId ~= baseId then
        NPCBaseCaptureUIBridge.ShowBase(base, dist)
    elseif (tonumber(NPCBaseCaptureUIBridge.DisplayUntilMs) or 0) > now then
        panel:setBase(base, dist)
    else
        panel:setBase(nil, nil)
    end

    NPCBaseCaptureUIBridge.CurrentBaseId = baseId
    return true
end

function NPCBaseCaptureUIBridge.Render()
    return NPCBaseCaptureUIBridge.Update()
end

function NPCBaseCaptureUIBridge.OnServerCommand(module, command, args)
    if not NPCLegacyContractBridge.IsModule(module, "NPCDebugMap", "debugMap") then return false end

    if command == "Remove" and args then
        NPCBaseCaptureUIBridge.RemoveBase(args.baseId or args.id)
    elseif (command == "Update" or command == "UpdateCompact") and args and args.markerType == "base" then
        NPCBaseCaptureUIBridge.SetBase(args)
    elseif (command == "Update" or command == "UpdateCompact") and args and args.markerType == "base_zone" then
        NPCBaseCaptureUIBridge.SetZone(args)
    elseif command == "SyncChunk" and args and args.markers then
        for _, marker in pairs(args.markers) do
            if type(marker) == "table" and marker.markerType == "base" then
                NPCBaseCaptureUIBridge.SetBase(marker)
            elseif type(marker) == "table" and marker.markerType == "base_zone" then
                NPCBaseCaptureUIBridge.SetZone(marker)
            end
        end
    elseif command == "Sync" and args then
        for _, marker in pairs(args.markers or args) do
            if type(marker) == "table" and marker.markerType == "base" then
                NPCBaseCaptureUIBridge.SetBase(marker)
            elseif type(marker) == "table" and marker.markerType == "base_zone" then
                NPCBaseCaptureUIBridge.SetZone(marker)
            end
        end
    elseif command == "Clear" then
        NPCBaseCaptureUIBridge.bases = {}
        NPCBaseCaptureUIBridge.zones = {}
    end

    return false
end

local function bbc_onTick()
    NPCBaseCaptureUIBridge._tick = NPCBaseCaptureUIBridge._tick + 1
    if NPCBaseCaptureUIBridge._tick % 20 == 0 then
        NPCBaseCaptureUIBridge.Update()
    end
end

local function bbc_onGameStart()
    NPCBaseCaptureUIBridge.EnsurePanel()
    local player = getPlayer()
    if player then
        sendClientCommand(player, "NPCBaseCamp", "RequestSync", {})
    end
end

Events.OnServerCommand.Add(NPCBaseCaptureUIBridge.OnServerCommand)
Events.OnTick.Add(bbc_onTick)
Events.OnGameStart.Add(bbc_onGameStart)

print("[NPCBaseCaptureUIBridge] Base capture HUD enabled")
