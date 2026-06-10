-- NPCWorldMarkerClientBridge.lua
-- Lightweight client-only overhead markers for discovered physical world targets.
-- Stage 355 enables radio stash overhead labels without changing map marker payload contracts.

require "NPCCore/NPCLegacyContractBridge"
pcall(require, "NPCCore/NPCLegacySettingsBridge")
pcall(require, "NPCClient/NPCDebugMapNPCMarkersBridge")
pcall(require, "NPCClient/NPCZombieCacheBridge")
pcall(require, "NPCCore/NPCFactionBridge")
pcall(require, "NPCCore/NPCNamesBridge")

NPCWorldMarkerClientBridge = NPCWorldMarkerClientBridge or {}

local BWM_EXT_SANDBOX = NPCLegacyContractBridge.Sandbox.ext
local BWM_TEXT_PREFIX = NPCLegacyContractBridge.Text.prefix

local function bwm_textManager()
    if getTextManager then
        local ok, tm = pcall(function() return getTextManager() end)
        if ok and tm then return tm end
    end
    if TextManager and TextManager.instance then return TextManager.instance end
    return nil
end

local function bwm_drawTextCentre(ui, text, x, y, r, g, b, a, font)
    text = tostring(text or "")
    if text == "" then return false end
    x = tonumber(x) or 0
    y = tonumber(y) or 0
    r = tonumber(r) or 1.0
    g = tonumber(g) or 1.0
    b = tonumber(b) or 1.0
    a = tonumber(a) or 1.0
    font = font or UIFont.Small

    -- Stage 374: render-hook proxies are not attached to UIManager, so their
    -- drawTextCentre calls can be silently invisible. Prefer TextManager when
    -- the proxy asks for direct drawing; keep the old UI path for real panels.
    if ui and ui.drawTextCentre and ui._bwmUseTextManagerDirect ~= true then
        local ok = pcall(function() ui:drawTextCentre(text, x, y, r, g, b, a, font) end)
        if ok then return true end
        ok = pcall(function() ui:drawTextCentre(text, x, y, r, g, b, font) end)
        if ok then return true end
    end

    local tm = bwm_textManager()
    if tm then
        local ok = false
        if tm.DrawStringCentre then
            ok = pcall(function() tm:DrawStringCentre(font, x, y, text, r, g, b, a) end)
            if ok then return true end
            ok = pcall(function() tm:DrawStringCentre(text, x, y, r, g, b, a, font) end)
            if ok then return true end
        end
        if tm.DrawString then
            local tw = 0
            if tm.MeasureStringX then
                local mOk, measured = pcall(function() return tm:MeasureStringX(font, text) end)
                if mOk then tw = tonumber(measured) or 0 end
            elseif getTextManager and getTextManager().MeasureStringX then
                local mOk, measured = pcall(function() return getTextManager():MeasureStringX(font, text) end)
                if mOk then tw = tonumber(measured) or 0 end
            end
            ok = pcall(function() tm:DrawString(font, x - (tw / 2), y, text, r, g, b, a) end)
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

local function bwm_canDraw(ui)
    return (ui and ui.drawTextCentre) or bwm_textManager() ~= nil
end


local function bwm_uiVisible(ui)
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

local function bwm_isWorldMapUI(ui)
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

local function bwm_worldMapReallyOpen(ui, fromManager)
    if not bwm_isWorldMapUI(ui) then return false end
    if ui.isReallyVisible then
        local ok, value = pcall(function() return ui:isReallyVisible() end)
        if ok then return value == true end
    end
    if fromManager == true then return bwm_uiVisible(ui) end
    if not ui.javaObject then return false end
    return bwm_uiVisible(ui)
end

local function bwm_isWorldMapOpen()
    local direct = nil
    if type(_G) == "table" then
        direct = rawget(_G, "ISWorldMap_instance") or rawget(_G, "ISWorldMapInstance")
    end
    if direct and bwm_worldMapReallyOpen(direct, false) then return true end

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
                    if gOk and bwm_worldMapReallyOpen(ui, true) then return true end
                end
            elseif type(list) == "table" then
                for _, ui in pairs(list) do
                    if bwm_worldMapReallyOpen(ui, true) then return true end
                end
            end
        end
    end
    return false
end

NPCWorldMarkerClientBridge._overlay = NPCWorldMarkerClientBridge._overlay or nil
NPCWorldMarkerClientBridge._drawProxy = NPCWorldMarkerClientBridge._drawProxy or nil
NPCWorldMarkerClientBridge._installed = NPCWorldMarkerClientBridge._installed or false
NPCWorldMarkerClientBridge._renderHookInstalled = NPCWorldMarkerClientBridge._renderHookInstalled or false
NPCWorldMarkerClientBridge._markerCache = NPCWorldMarkerClientBridge._markerCache or {}
NPCWorldMarkerClientBridge._npcCache = NPCWorldMarkerClientBridge._npcCache or {}
NPCWorldMarkerClientBridge._fallbackNames = NPCWorldMarkerClientBridge._fallbackNames or {}
NPCWorldMarkerClientBridge._lastRefreshTick = NPCWorldMarkerClientBridge._lastRefreshTick or 0

local function bwm_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        local ok, value = pcall(function() return NPCLegacySettingsBridge.GetBool(name, defaultValue == true) end)
        if ok and value ~= nil then return value == true end
    end
    local vars = SandboxVars and SandboxVars[BWM_EXT_SANDBOX] or nil
    if vars and vars[name] ~= nil then
        local v = vars[name]
        return v == true or v == 1 or tostring(v):lower() == "true"
    end
    return defaultValue == true
end

local function bwm_num(name, defaultValue, minValue, maxValue)
    local value = defaultValue
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        local ok, got = pcall(function() return NPCLegacySettingsBridge.GetNumber(name, defaultValue, minValue, maxValue) end)
        if ok and got ~= nil then value = got end
    else
        local vars = SandboxVars and SandboxVars[BWM_EXT_SANDBOX] or nil
        if vars and vars[name] ~= nil then value = vars[name] end
    end
    value = tonumber(value) or tonumber(defaultValue) or 0
    if minValue ~= nil and value < minValue then value = minValue end
    if maxValue ~= nil and value > maxValue then value = maxValue end
    return value
end

local function bwm_text(key, fallback)
    local full = BWM_TEXT_PREFIX .. tostring(key or "")
    if getText then
        local ok, value = pcall(function() return getText(full) end)
        if ok and value and value ~= full then return tostring(value) end
    end
    return fallback or tostring(key or "")
end

local function bwm_player()
    return (getPlayer and getPlayer()) or (getSpecificPlayer and getSpecificPlayer(0)) or nil
end

local function bwm_dist(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return math.sqrt(dx * dx + dy * dy)
end

local function bwm_worldToScreen(x, y, z)
    if not (IsoUtils and IsoCamera) then return nil, nil end
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
    return nil, nil
end

local function bwm_objectToScreen(obj, x, y, z)
    if obj and obj.getX and obj.getY and obj.getZ then
        local ok, gx, gy, gz = pcall(function()
            return obj:getX(), obj:getY(), obj:getZ()
        end)
        if ok and gx ~= nil and gy ~= nil then
            local sx, sy = bwm_worldToScreen(gx, gy, gz)
            if sx and sy then return sx, sy end
        end
    end
    return bwm_worldToScreen(x, y, z)
end

local function bwm_markerField(marker, key)
    if type(marker) ~= "table" then return nil end
    local ok, value = pcall(function() return rawget(marker, key) end)
    if ok then return value end
    ok, value = pcall(function() return marker[key] end)
    if ok then return value end
    return nil
end

local function bwm_markersSource()
    -- Stage 383: merge all known marker stores instead of returning the first one.
    -- Black-market drops are usually general debug markers, while NPC markers live
    -- in a separate client table. Returning only NPC markers made paid drops
    -- invisible to the overhead world-marker renderer.
    -- Stage 397: some stores can be proxy/Kahlua tables after map-marker/UI hooks;
    -- never call pairs() directly here because a bad proxy used to throw every frame.
    local out = {}
    local seen = {}
    local hasAny = false
    local function addMarker(id, marker)
        if type(marker) ~= "table" then return end
        local rawId = bwm_markerField(marker, "id")
        local key = tostring(rawId or id or "")
        if key == "" then key = tostring(id or "") end
        if key ~= "" and not seen[key] then
            seen[key] = true
            out[key] = marker
            hasAny = true
        end
    end
    local function addSource(source)
        if type(source) ~= "table" then return end
        local ok, err = pcall(function()
            local k = nil
            local guard = 0
            while true do
                local nOk, nk, nv = pcall(next, source, k)
                if not nOk then break end
                if nk == nil then break end
                addMarker(nk, nv)
                k = nk
                guard = guard + 1
                if guard > 2048 then break end
            end
        end)
        if not ok and type(NPCDiagnosticsBridge) == "table" and type(NPCDiagnosticsBridge.Log) == "function" then
            NPCDiagnosticsBridge.Log("WORLD_MARKER_WARN", "marker source ignored", { error = tostring(err or "unknown") })
        end
    end
    if type(NPCDebugMapNPCMarkersBridge) == "table" then addSource(rawget(NPCDebugMapNPCMarkersBridge, "markers")) end
    if type(NPCDebugMapMarkersBridge) == "table" then addSource(rawget(NPCDebugMapMarkersBridge, "markers")) end
    if type(NPCBlackMarketClientBridge) == "table" then addSource(rawget(NPCBlackMarketClientBridge, "dropMarkers")) end
    local gmd = nil
    if type(GetNPCModData) == "function" then
        local ok, data = pcall(GetNPCModData)
        if ok then gmd = data end
    end
    if type(gmd) == "table" then addSource(rawget(gmd, "DebugMapMarkers")) end
    return hasAny and out or nil
end

local function bwm_isRadioStashMarker(marker)
    return type(marker) == "table"
        and marker.supplyCache == true
        and marker.radioIntel == true
        and marker.x ~= nil
        and marker.y ~= nil
        and marker.stashMarkerOverhead ~= false
end

local function bwm_isBlackMarketDropMarker(marker)
    return type(marker) == "table"
        and (marker.blackMarketDrop == true or marker.blackMarketDeadDrop == true or marker.markerType == "black_market_drop")
        and marker.x ~= nil
        and marker.y ~= nil
        and marker.stashMarkerOverhead ~= false
end

local function bwm_cacheMarkers(player)
    NPCWorldMarkerClientBridge._markerCache = {}
    if not (player and player.getX and player.getY) then return end
    if not bwm_bool("WorldMarker_Enabled", true) then return end
    if not bwm_bool("WorldMarker_StashMarkers", true) then return end
    local allowRadioStashMarkers = bwm_bool("RadioIntercept_StashMarkerOverhead", true)
    local allowBlackMarketDrops = bwm_bool("BlackMarket_DeadDropEnabled", true)
    if not (allowRadioStashMarkers or allowBlackMarketDrops) then return end

    local source = bwm_markersSource()
    if type(source) ~= "table" then return end

    local px, py = player:getX(), player:getY()
    local drawDist = bwm_num("WorldMarker_DrawDistance", 46, 3, 200)
    local maxVisible = math.floor(bwm_num("WorldMarker_MaxVisible", 28, 1, 120))
    local rows = {}
    for _, marker in pairs(source) do
        local isRadioStash = allowRadioStashMarkers and bwm_isRadioStashMarker(marker)
        local isBlackMarketDrop = allowBlackMarketDrops and bwm_isBlackMarketDropMarker(marker)
        if isRadioStash or isBlackMarketDrop then
            local x, y = tonumber(marker.x), tonumber(marker.y)
            if x and y then
                local reveal = tonumber(marker.stashRevealDistance) or bwm_num("RadioIntercept_StashRevealDistance", 18, 3, 80)
                local allowedDist = math.min(drawDist, math.max(3, reveal))
                local dist = bwm_dist(px, py, x, y)
                if dist <= allowedDist then
                    rows[#rows + 1] = {marker=marker, dist=dist}
                end
            end
        end
    end
    table.sort(rows, function(a, b) return (a.dist or 999999) < (b.dist or 999999) end)
    for i = 1, math.min(#rows, maxVisible) do
        NPCWorldMarkerClientBridge._markerCache[#NPCWorldMarkerClientBridge._markerCache + 1] = rows[i]
    end
end

local function bwm_tierLabel(marker)
    if bwm_isBlackMarketDropMarker(marker) then
        local dropType = tostring(marker and marker.blackMarketDropType or "")
        if dropType == "ammo" then return "AMMO DEAD DROP" end
        if dropType == "medical" then return "MEDICAL DEAD DROP" end
        if dropType == "weapons" then return "WEAPON DEAD DROP" end
        if dropType == "armor" then return "ARMOR DEAD DROP" end
        if dropType == "quest" then return "QUEST" end
        if dropType == "defense" then return "DEFENSE ZONE" end
        return "BLACK MARKET DROP"
    end
    local tier = tostring(marker and marker.supplyCacheTier or "")
    if tier == "weapons" then return "WEAPON CACHE" end
    if tier == "armor" then return "ARMOR CACHE" end
    if tier == "medical" then return "MEDICAL CACHE" end
    if tier == "gold" or tier == "silver" then return "VALUABLES CACHE" end
    if tier == "old" then return "OLD CACHE" end
    return bwm_text("Map_SupplyCache", "SUPPLY CACHE")
end

local function bwm_statusLine(marker)
    if not marker then return nil end
    if bwm_isBlackMarketDropMarker(marker) then
        if marker.blackMarketCompromised == true or marker.blackMarketDropStatus == "compromised" then return "compromised signal" end
        if tostring(marker.blackMarketDropType or "") == "quest" then return "contract item" end
        if tostring(marker.blackMarketDropType or "") == "defense" then return "hold position" end
        return "paid delivery"
    end
    if marker.supplyCacheStatus == "old" then return "old lead" end
    if marker.supplyCacheStatus == "missing" then return "search area" end
    local items = tonumber(marker.supplyCacheItems)
    if items and items > 0 then return tostring(math.floor(items)) .. " items" end
    if marker.physicalStash == true then return "field drop" end
    return "marked stash"
end


local function bwm_normSide(side)
    if NPCFactionBridge and NPCFactionBridge.NormalizeSide then
        local ok, normalized = pcall(function() return NPCFactionBridge.NormalizeSide(side) end)
        if ok and normalized then return tostring(normalized) end
    end
    side = tostring(side or "")
    side = string.lower(side)
    if side == "1" or side == "red_faction" or side == "enemy" then return "red" end
    if side == "2" or side == "green_faction" or side == "ally" then return "green" end
    if side == "3" or side == "merc" or side == "mercenary" then return "blue" end
    if side == "black_market_service" then return "black_market" end
    return side
end

local function bwm_sideLabel(side, brain)
    if brain and brain.blackMarketDefenseEnemy == true then return "Black Market" end
    side = bwm_normSide(side)
    if side == "red" then return "Red" end
    if side == "green" then return "Green" end
    if side == "blue" then return "Blue" end
    if side == "black" then return "Black" end
    if side == "black_market" then return "Black Market" end
    if side == "rogue" then return "Rogue" end
    if side == "neutral" then return "Neutral" end
    if brain and brain.hostile then return "Red" end
    return "Neutral"
end

local function bwm_sideColor(side, brain)
    if brain and brain.blackMarketDefenseEnemy == true then return 0.70, 0.25, 1.0 end
    if not bwm_bool("WorldMarker_FactionColors", true) then return 0.95, 0.95, 0.86 end
    side = bwm_normSide(side)
    if side == "red" then return 1.0, 0.24, 0.18 end
    if side == "green" then return 0.26, 0.95, 0.30 end
    if side == "blue" then return 0.35, 0.60, 1.0 end
    if side == "black" or side == "black_market" then return 0.75, 0.55, 1.0 end
    if side == "rogue" then return 1.0, 0.60, 0.20 end
    if side == "neutral" then return 0.82, 0.82, 0.78 end
    if brain and brain.hostile then return 1.0, 0.24, 0.18 end
    return 0.82, 0.82, 0.78
end

local function bwm_hashText(text)
    text = tostring(text or "")
    local h = 0
    for i = 1, string.len(text) do
        h = (h * 33 + string.byte(text, i)) % 2147483647
    end
    return h
end

local function bwm_choice(list, idx, fallback)
    if type(list) ~= "table" or #list <= 0 then return fallback end
    idx = math.floor(tonumber(idx) or 0)
    return list[(idx % #list) + 1] or fallback
end

local function bwm_fallbackName(id, brain)
    local key = tostring((brain and (brain.uid or brain.persistentId or brain.id)) or id or "npc")
    local cached = NPCWorldMarkerClientBridge._fallbackNames[key]
    if cached then return cached end
    local h = bwm_hashText(key)
    local female = brain and brain.female == true
    local first = nil
    local last = nil
    if NPCNamesBridge then
        if female and NPCNamesBridge.Female then first = bwm_choice(NPCNamesBridge.Female.FirstNames, h, nil) end
        if not first and NPCNamesBridge.Male then first = bwm_choice(NPCNamesBridge.Male.FirstNames, h, nil) end
        last = bwm_choice(NPCNamesBridge.Surnames, math.floor(h / 13), nil)
    end
    local name = tostring(first or "Unknown") .. " " .. tostring(last or "Operative")
    NPCWorldMarkerClientBridge._fallbackNames[key] = name
    return name
end

local function bwm_npcName(id, brain)
    if not bwm_bool("WorldMarker_NPCNameplates", true) then return nil end
    local value = brain and (brain.fullname or brain.fullName or brain.name or brain.displayName)
    value = tostring(value or "")
    value = string.gsub(value, "^%s+", "")
    value = string.gsub(value, "%s+$", "")
    if value ~= "" and value ~= "nil" and value ~= "false" then return value end
    return bwm_fallbackName(id, brain)
end

local function bwm_programName(brain)
    if not brain then return nil end
    if type(brain.program) == "table" then return brain.program.name or brain.program.id end
    if brain.program ~= nil then return brain.program end
    return nil
end

local function bwm_roleToken(brain)
    if not brain then return "NPC" end
    if brain.blackMarketDefenseEnemy == true then return "DEFENCE GUARD" end
    if brain.counterIntelHunter == true then return "Hunter" end
    if brain.leader == true or brain.isFactionLeader == true or brain.leaderRole then return "Commander" end
    if brain.displayTitle and tostring(brain.displayTitle) ~= "" then return tostring(brain.displayTitle) end
    if brain.mercenaryHired or brain.mercenary or brain.mercenarySquadLeader then return "Mercenary" end
    local role = tostring(brain.tacticalRole or brain.role or brain.programName or bwm_programName(brain) or "")
    role = string.lower(role)
    if string.find(role, "guard", 1, true) then return "Guard" end
    if string.find(role, "raider", 1, true) then return "Raider" end
    if string.find(role, "looter", 1, true) then return "Looter" end
    if string.find(role, "patrol", 1, true) then return "Patrolman" end
    if string.find(role, "civil", 1, true) then return "Civilian" end
    if string.find(role, "black", 1, true) then return "Broker" end
    if string.find(role, "companion", 1, true) then return "Companion" end
    if string.find(role, "defend", 1, true) then return "Defender" end
    if brain.hostile then return "Fighter" end
    return "Survivor"
end

local function bwm_weaponTier(brain)
    local weapon = brain and (brain.currentWeapon or brain.weapon or brain.primaryWeapon or brain.equippedWeapon)
    local name = ""
    if type(weapon) == "table" then name = tostring(weapon.name or weapon.fullType or weapon.type or "") else name = tostring(weapon or "") end
    name = string.lower(name)
    if name == "" and brain and type(brain.weapons) == "table" then
        local primary = brain.weapons.primary
        if type(primary) == "table" then name = string.lower(tostring(primary.name or primary.fullType or primary.type or "")) end
    end
    if string.find(name, "sniper", 1, true) or string.find(name, "rifle", 1, true) or string.find(name, "m16", 1, true) or string.find(name, "ak", 1, true) then return 2 end
    if string.find(name, "shotgun", 1, true) or string.find(name, "moss", 1, true) then return 2 end
    if string.find(name, "pistol", 1, true) or string.find(name, "revolver", 1, true) or string.find(name, "handgun", 1, true) then return 1 end
    return 0
end

local function bwm_unitLevel(brain)
    local explicit = tonumber(brain and brain.unitLevel)
    if explicit then return math.max(1, math.min(10, math.floor(explicit))) end
    local level = 1
    if brain then
        local role = string.lower(tostring(brain.tacticalRole or brain.role or brain.programName or brain.displayTitle or ""))
        if brain.counterIntelHunter then level = level + 6 end
        if brain.eliteUnit or brain.counterIntelElite then level = level + 4 end
        if brain.leader or brain.isFactionLeader or brain.leaderRole then level = level + 5 end
        if brain.mercenaryHired or brain.mercenary or brain.mercenarySquadLeader then level = level + 3 end
        if string.find(role, "raider", 1, true) or string.find(role, "guard", 1, true) or string.find(role, "soldier", 1, true) or string.find(role, "defend", 1, true) then level = level + 2 end
        if string.find(role, "civil", 1, true) then level = math.max(1, level - 1) end
        if brain.hostile then level = level + 1 end
        level = level + bwm_weaponTier(brain)
        if tonumber(brain.health) and tonumber(brain.health) > 120 then level = level + 1 end
        if tonumber(brain.experienceLevel) then level = level + math.floor(tonumber(brain.experienceLevel) / 3) end
    end
    return math.max(1, math.min(10, math.floor(level)))
end

local function bwm_unitStars(brain, level)
    local explicit = tonumber(brain and brain.unitStars)
    if explicit then return math.max(1, math.min(3, math.floor(explicit))) end
    if brain and (brain.eliteUnit or brain.counterIntelElite) then return 3 end
    level = tonumber(level) or 1
    if level >= 8 then return 3 end
    if level >= 4 then return 2 end
    return 1
end

local function bwm_starText(stars)
    stars = math.max(1, math.min(3, math.floor(tonumber(stars) or 1)))
    if stars == 3 then return "★★★" end
    if stars == 2 then return "★★" end
    return "★"
end

local function bwm_gradeLabel(brain, level, stars)
    if brain and brain.blackMarketDefenseEnemy == true then return "DEFENCE GUARD" end
    if not bwm_bool("WorldMarker_EliteLabels", true) then return nil end
    if brain and brain.counterIntelHunter then return stars >= 3 and "ELITE COUNTER-INTEL" or "COUNTER-INTEL" end
    if brain and (brain.eliteUnit or stars >= 3) then return "ELITE" end
    if brain and (brain.leader or brain.isFactionLeader or brain.leaderRole) then return "COMMAND" end
    return nil
end

local function bwm_isAiming(player)
    if not player then return false end
    local methods = {"isAiming", "IsAiming", "isAimAtFloor", "isCharging"}
    for _, name in ipairs(methods) do
        local fn = player[name]
        if fn then
            local ok, value = pcall(function() return fn(player) end)
            if ok and value == true then return true end
        end
    end
    return false
end

local function bwm_canSeeNPC(player, npc, dist)
    if not bwm_bool("WorldMarker_HideThroughWalls", true) then return true end
    if not (player and npc) then return dist and dist <= 8 end
    if dist and dist <= 7 then return true end
    if player.CanSee then
        local ok, value = pcall(function() return player:CanSee(npc) end)
        if ok then return value == true end
    end
    return true
end

local function bwm_cacheNPCNameplates(player, remainingSlots)
    NPCWorldMarkerClientBridge._npcCache = {}
    if not (player and player.getX and player.getY) then return end
    if not bwm_bool("WorldMarker_Enabled", true) then return end
    if not bwm_bool("WorldMarker_NPCNameplates", true) then return end
    if bwm_bool("WorldMarker_OnlyWhenAimed", false) and not bwm_isAiming(player) then return end

    remainingSlots = math.max(0, math.floor(tonumber(remainingSlots) or 0))
    if remainingSlots <= 0 then return end

    local source = nil
    if NPCZombieCacheBridge and NPCZombieCacheBridge.GetAllB then
        local ok, got = pcall(function() return NPCZombieCacheBridge.GetAllB() end)
        if ok then source = got end
    end
    if type(source) ~= "table" then return end

    local px, py = player:getX(), player:getY()
    local drawDist = bwm_num("WorldMarker_DrawDistance", 46, 3, 200)
    local rows = {}
    for id, light in pairs(source) do
        local brain = light and light.brain
        local x = tonumber(light and light.x)
        local y = tonumber(light and light.y)
        local z = tonumber(light and light.z) or 0
        if brain and x and y and brain.dead ~= true then
            local dist = bwm_dist(px, py, x, y)
            local maxDist = drawDist
            if brain.blackMarketDefenseEnemy == true then
                maxDist = math.max(maxDist, bwm_num("BlackMarket_DefenseGuardMarkerDistance", 220, 40, 500))
            end
            if dist <= maxDist then
                local npc = nil
                if NPCZombieCacheBridge and NPCZombieCacheBridge.GetInstanceById then
                    local ok, got = pcall(function() return NPCZombieCacheBridge.GetInstanceById(id) end)
                    if ok then npc = got end
                end
                local dead = false
                if npc and npc.isDead then
                    local ok, value = pcall(function() return npc:isDead() end)
                    dead = ok and value == true
                end
                if not dead and (brain.blackMarketDefenseEnemy == true or bwm_canSeeNPC(player, npc, dist)) then
                    rows[#rows + 1] = {id=id, brain=brain, npc=npc, x=x, y=y, z=z, dist=dist}
                end
            end
        end
    end
    table.sort(rows, function(a, b)
        local ab = a.brain or {}
        local bb = b.brain or {}
        local ap = (ab.blackMarketDefenseEnemy and 5000 or 0) + (ab.counterIntelHunter and 3000 or 0) + ((ab.eliteUnit or ab.leader or ab.isFactionLeader) and 1200 or 0) - (a.dist or 0)
        local bp = (bb.blackMarketDefenseEnemy and 5000 or 0) + (bb.counterIntelHunter and 3000 or 0) + ((bb.eliteUnit or bb.leader or bb.isFactionLeader) and 1200 or 0) - (b.dist or 0)
        return ap > bp
    end)
    for i = 1, math.min(#rows, remainingSlots) do
        NPCWorldMarkerClientBridge._npcCache[#NPCWorldMarkerClientBridge._npcCache + 1] = rows[i]
    end
end

local function bwm_cacheAll(player)
    bwm_cacheMarkers(player)
    local maxVisible = math.floor(bwm_num("WorldMarker_MaxVisible", 28, 1, 120))
    local remaining = math.max(0, maxVisible - #(NPCWorldMarkerClientBridge._markerCache or {}))
    bwm_cacheNPCNameplates(player, remaining)
end

local function bwm_drawNameplate(ui, row, sw, sh)
    local brain = row and row.brain
    if not brain then return end
    local sx, sy = bwm_objectToScreen(row.npc, row.x, row.y, row.z)
    if not (sx and sy) then return end
    local dist = tonumber(row.dist) or 0
    local drawDist = bwm_num("WorldMarker_DrawDistance", 46, 3, 200)
    local alpha = math.max(0.28, math.min(1.0, 1.0 - (dist / math.max(1, drawDist)) * 0.62))
    local cx = math.floor(sx)
    local yOffset = bwm_num("WorldMarker_NameplateYOffset", 112, 40, 240)
    local cy = math.floor(sy - yOffset)
    if cx <= -180 or cy <= -100 or cx >= sw + 180 or cy >= sh + 100 then return end

    local side = brain.factionSide or brain.faction or brain.side or brain.patrolColor or brain.clan
    local sr, sg, sb = bwm_sideColor(side, brain)
    local name = bwm_npcName(row.id, brain)
    local role = bwm_roleToken(brain)
    local level = bwm_unitLevel(brain)
    local stars = bwm_unitStars(brain, level)
    local sideLabel = bwm_sideLabel(side, brain)
    local grade = bwm_gradeLabel(brain, level, stars)

    local info = sideLabel .. " " .. role
    if bwm_bool("WorldMarker_NPCLevels", true) then info = info .. " | Lv." .. tostring(level) end
    if bwm_bool("WorldMarker_NPCStars", true) then info = info .. " " .. bwm_starText(stars) end

    if grade then
        bwm_drawTextCentre(ui, grade, cx, cy - 14, 0, 0, 0, alpha * 0.88, UIFont.Small)
        bwm_drawTextCentre(ui, grade, cx, cy - 15, sr, sg, sb, alpha * 0.96, UIFont.Small)
    end
    if name and name ~= "" then
        bwm_drawTextCentre(ui, name, cx, cy + 1, 0, 0, 0, alpha, UIFont.Small)
        bwm_drawTextCentre(ui, name, cx, cy, 0.96, 0.96, 0.88, alpha, UIFont.Small)
    end
    bwm_drawTextCentre(ui, info, cx, cy + 14, 0, 0, 0, alpha * 0.92, UIFont.Small)
    bwm_drawTextCentre(ui, info, cx, cy + 13, sr, sg, sb, alpha * 0.98, UIFont.Small)
end

local BWM_OVERLAY_BASE = ISPanel or ISUIElement
if BWM_OVERLAY_BASE and BWM_OVERLAY_BASE.derive then
    NPCWorldMarkerOverlayBridge = NPCWorldMarkerOverlayBridge or BWM_OVERLAY_BASE:derive("NPCWorldMarkerOverlayBridge")
else
    NPCWorldMarkerOverlayBridge = nil
end

if NPCWorldMarkerOverlayBridge then
function NPCWorldMarkerOverlayBridge:initialise()
    if ISPanel and ISPanel.initialise then
        ISPanel.initialise(self)
    elseif ISUIElement and ISUIElement.initialise then
        ISUIElement.initialise(self)
    end
    if self.addToUIManager then self:addToUIManager() end
    if self.setVisible then self:setVisible(true) end
end
end

local function bwm_renderInternal(ui)
    if bwm_isWorldMapOpen() then return end
    if not bwm_canDraw(ui) then return end
    local player = bwm_player()
    if not player then return end
    local core = getCore and getCore() or nil
    local sw = core and core.getScreenWidth and core:getScreenWidth() or ui.width or 1920
    local sh = core and core.getScreenHeight and core:getScreenHeight() or ui.height or 1080
    if ui.setWidth then pcall(function() ui:setWidth(sw) end) end
    if ui.setHeight then pcall(function() ui:setHeight(sh) end) end

    local tick = 0
    if getTimestampMs then tick = math.floor(getTimestampMs() / 16) end
    local interval = math.floor(bwm_num("WorldMarker_UpdateTicks", 8, 1, 120))
    if tick <= 0 or tick - (NPCWorldMarkerClientBridge._lastRefreshTick or 0) >= interval then
        NPCWorldMarkerClientBridge._lastRefreshTick = tick
        bwm_cacheAll(player)
    end

    for _, row in ipairs(NPCWorldMarkerClientBridge._markerCache or {}) do
        local marker = row.marker
        local x, y, z = tonumber(marker.x), tonumber(marker.y), tonumber(marker.z) or 0
        if x and y then
            local sx, sy = bwm_worldToScreen(x, y, z)
            if sx and sy then
                local dist = tonumber(row.dist) or 0
                local alpha = math.max(0.35, math.min(1.0, 1.0 - (dist / math.max(1, bwm_num("WorldMarker_DrawDistance", 46, 3, 200))) * 0.55))
                local cx = math.floor(sx)
                local cy = math.floor(sy - 48)
                if cx > -160 and cy > -80 and cx < sw + 160 and cy < sh + 80 then
                    local title = bwm_tierLabel(marker)
                    local status = bwm_statusLine(marker)
                    bwm_drawTextCentre(ui, "◆", cx, cy - 13, 0, 0, 0, alpha, UIFont.Small)
                    bwm_drawTextCentre(ui, "◆", cx, cy - 14, 1.0, 0.86, 0.18, alpha, UIFont.Small)
                    bwm_drawTextCentre(ui, title, cx, cy + 1, 0, 0, 0, alpha, UIFont.Small)
                    bwm_drawTextCentre(ui, title, cx, cy, 1.0, 0.90, 0.30, alpha, UIFont.Small)
                    if status and status ~= "" then
                        bwm_drawTextCentre(ui, status, cx, cy + 14, 0, 0, 0, alpha * 0.92, UIFont.Small)
                        bwm_drawTextCentre(ui, status, cx, cy + 13, 0.95, 0.95, 0.82, alpha * 0.95, UIFont.Small)
                    end
                end
            end
        end
    end

    for _, row in ipairs(NPCWorldMarkerClientBridge._npcCache or {}) do
        bwm_drawNameplate(ui, row, sw, sh)
    end
end

if NPCWorldMarkerOverlayBridge then
function NPCWorldMarkerOverlayBridge:render()
    bwm_renderInternal(self)
end
end

if NPCWorldMarkerOverlayBridge then
function NPCWorldMarkerOverlayBridge:new()
    local core = getCore and getCore() or nil
    local sw = core and core.getScreenWidth and core:getScreenWidth() or 1920
    local sh = core and core.getScreenHeight and core:getScreenHeight() or 1080
    local o = nil
    if ISPanel and ISPanel.new then
        o = ISPanel.new(self, 0, 0, sw, sh)
    elseif ISUIElement and ISUIElement.new then
        o = ISUIElement.new(self, 0, 0, sw, sh)
    end
    if not o then return nil end
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.moveWithMouse = false
    o.bConsumeMouseEvents = false
    o.consumeMouseEvents = false
    o.capture = false
    if o.setAlwaysOnTop then pcall(function() o:setAlwaysOnTop(false) end) end
    if o.setCapture then pcall(function() o:setCapture(false) end) end
    if o.noBackground then pcall(function() o:noBackground() end) end
    return o
end
end

local function bwm_getDrawProxy()
    if NPCWorldMarkerClientBridge._drawProxy and NPCWorldMarkerClientBridge._drawProxy.drawTextCentre then
        return NPCWorldMarkerClientBridge._drawProxy
    end
    local proxy = nil
    if ISPanel and ISPanel.new then
        proxy = ISPanel:new(0, 0, 1, 1)
    elseif ISUIElement and ISUIElement.new then
        proxy = ISUIElement:new(0, 0, 1, 1)
    end
    if proxy then
        pcall(function() proxy._bwmUseTextManagerDirect = true end)
        pcall(function() proxy.background = false end)
        pcall(function() proxy.moveWithMouse = false end)
        pcall(function() proxy.bConsumeMouseEvents = false end)
        pcall(function() proxy.consumeMouseEvents = false end)
        pcall(function() proxy.capture = false end)
        if proxy.initialise then pcall(function() proxy:initialise() end) end
        NPCWorldMarkerClientBridge._drawProxy = proxy
    end
    return proxy
end

function NPCWorldMarkerClientBridge.RenderWorldMarkers()
    local proxy = bwm_getDrawProxy()
    if proxy then
        bwm_renderInternal(proxy)
    end
end

function NPCWorldMarkerClientBridge.Install()
    if NPCWorldMarkerClientBridge._installed then return end
    NPCWorldMarkerClientBridge._installed = true
    if NPCWorldMarkerClientBridge._renderHookInstalled then return end
    NPCWorldMarkerClientBridge._renderHookInstalled = true
    if Events and Events.OnPostUIDraw then
        Events.OnPostUIDraw.Add(NPCWorldMarkerClientBridge.RenderWorldMarkers)
    elseif Events and Events.OnPreUIDraw then
        Events.OnPreUIDraw.Add(NPCWorldMarkerClientBridge.RenderWorldMarkers)
    elseif Events and Events.OnRenderTick then
        Events.OnRenderTick.Add(NPCWorldMarkerClientBridge.RenderWorldMarkers)
    end
end

if Events and Events.OnGameStart then
    Events.OnGameStart.Add(NPCWorldMarkerClientBridge.Install)
end
