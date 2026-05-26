-- NPCBlackMarketClientBridge.lua
-- Static black market world-prop visual and context menu.
-- The black market is intentionally not an IsoZombie/IsoGameCharacter.

require "NPCCore/NPCLegacyContractBridge"
pcall(require, "ISUI/ISPanel")
pcall(require, "ISUI/ISUIElement")

NPCBlackMarketClientBridge = NPCBlackMarketClientBridge or {}

local BBMC_LEGACY_TEXT_PREFIX = NPCLegacyContractBridge.Text.prefix
local BBMC_LEGACY_KEYS = {
    blackMarketProp = NPCLegacyContractBridge.Key("BLACK_MARKET_PROP")
}

local function bbmc_text(key)
    return getText(BBMC_LEGACY_TEXT_PREFIX .. tostring(key or ""))
end
NPCBlackMarketClientBridge.contacts = NPCBlackMarketClientBridge.contacts or {}
NPCBlackMarketClientBridge.overlay = NPCBlackMarketClientBridge.overlay or nil
NPCBlackMarketClientBridge.lastKnownContact = NPCBlackMarketClientBridge.lastKnownContact or nil
NPCBlackMarketClientBridge.worldProps = NPCBlackMarketClientBridge.worldProps or {}

local BBMC_STATIC_SPRITE = "media/ui/black_market_service.png"
local BBMC_WORLD_PROP_SPRITE_PREFIX = "media/ui/black_market_world_prop"
local BBMC_WORLD_PROP_REPULSE_RADIUS = 0.58
local BBMC_WORLD_PROP_REPULSE_FORCE = 0.06
local BBMC_WORLD_PROP_REPULSE_INTERVAL_MS = 80

local function bbmc_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        local ok, value = pcall(function() return NPCLegacySettingsBridge.GetBool(name, defaultValue == true) end)
        if ok and value ~= nil then return value == true end
    end
    return defaultValue == true
end

local function bbmc_num(name, defaultValue, minValue, maxValue)
    local value = defaultValue
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        local ok, got = pcall(function() return NPCLegacySettingsBridge.GetNumber(name, defaultValue, minValue, maxValue) end)
        if ok and got ~= nil then value = got end
    end
    value = tonumber(value) or tonumber(defaultValue) or 0
    if minValue ~= nil and value < minValue then value = minValue end
    if maxValue ~= nil and value > maxValue then value = maxValue end
    return value
end

local function bbmc_player(playerNum)
    return getSpecificPlayer(playerNum or 0) or getPlayer()
end

local function bbmc_clickedSquare(worldobjects)
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

local function bbmc_halo(text, r, g, b)
    local player = getPlayer() or getSpecificPlayer(0)
    if HaloTextHelper and player and text then
        HaloTextHelper.addText(player, tostring(text), r or 220, g or 220, b or 160)
    end
end

local function bbmc_dist(a, b, x, y)
    local dx = (tonumber(a) or 0) - (tonumber(x) or 0)
    local dy = (tonumber(b) or 0) - (tonumber(y) or 0)
    return math.sqrt(dx * dx + dy * dy)
end

local function bbmc_storeLastContact(contact)
    if type(contact) ~= "table" then return end
    if not (contact.blackMarketId or contact.id) then return end
    NPCBlackMarketClientBridge.lastKnownContact = {
        id = contact.blackMarketId or contact.id,
        blackMarketId = contact.blackMarketId or contact.id,
        x = tonumber(contact.x),
        y = tonumber(contact.y),
        z = tonumber(contact.z) or 0,
        markerType = contact.markerType or "black_market",
        blackMarket = true,
        blackMarketStatus = contact.blackMarketStatus,
        blackMarketSide = contact.blackMarketSide,
        sourceSide = contact.sourceSide,
        blackMarketStaticObject = contact.blackMarketStaticObject,
        blackMarketVirtualObject = contact.blackMarketVirtualObject,
    }
end

local function bbmc_lastKnownContactNear(player, radius)
    local contact = NPCBlackMarketClientBridge.lastKnownContact
    if not (player and contact and contact.x and contact.y) then return nil end
    local pd = bbmc_dist(contact.x, contact.y, player:getX(), player:getY())
    if pd <= (tonumber(radius) or 0) then return contact end
    return nil
end

local function bbmc_nowMs()
    if getTimestampMs then
        local ok, value = pcall(function() return getTimestampMs() end)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return math.floor((os.time() or 0) * 1000)
end

local function bbmc_contactKey(contact, fallback)
    if type(contact) ~= "table" then return tostring(fallback or "") end
    return tostring(contact.blackMarketId or contact.id or fallback or "")
end

local function bbmc_eachContact(callback)
    local seen = {}
    local function visit(id, marker)
        if type(marker) ~= "table" then return end
        if marker.markerType ~= "black_market" and marker.blackMarket ~= true then return end
        if marker.blackMarketStatus == "closed" then return end
        local key = bbmc_contactKey(marker, id)
        if key == "" or seen[key] then return end
        seen[key] = true
        callback(marker, key)
    end
    for id, marker in pairs(NPCBlackMarketClientBridge.contacts or {}) do visit(id, marker) end
    if NPCDebugMapNPCMarkersBridge and type(NPCDebugMapNPCMarkersBridge.markers) == "table" then
        for id, marker in pairs(NPCDebugMapNPCMarkersBridge.markers) do visit(id, marker) end
    end
    if NPCDebugMapMarkersBridge and type(NPCDebugMapMarkersBridge.markers) == "table" then
        for id, marker in pairs(NPCDebugMapMarkersBridge.markers) do visit(id, marker) end
    end
end

local function bbmc_findContactById(id)
    id = tostring(id or "")
    if id == "" then return nil end
    local found = nil
    bbmc_eachContact(function(contact, key)
        if not found and tostring(key) == id then found = contact end
    end)
    local last = NPCBlackMarketClientBridge.lastKnownContact
    if not found and last and bbmc_contactKey(last) == id then found = last end
    return found
end

local function bbmc_contactFromWorldObjects(worldobjects)
    if type(worldobjects) ~= "table" then return nil end
    for _, obj in ipairs(worldobjects) do
        local md = nil
        if obj and obj.getModData then
            local ok, got = pcall(function() return obj:getModData() end)
            if ok then md = got end
        end
        if type(md) == "table" and (md.blackMarket == true or md[BBMC_LEGACY_KEYS.blackMarketProp] == true) then
            local contact = bbmc_findContactById(md.blackMarketId or md.BlackMarketId)
            if contact then
                bbmc_storeLastContact(contact)
                return contact
            end
        end
    end
    return nil
end

local bbmc_worldToScreen

local function bbmc_nearestContact(player, worldobjects)
    if not (player and player.getX and player.getY) then return nil end

    local objectContact = bbmc_contactFromWorldObjects(worldobjects)
    if objectContact then return objectContact end

    local square = bbmc_clickedSquare(worldobjects)
    local hasSquare = square and square.getX and square.getY
    local px, py = player:getX(), player:getY()
    local ax, ay = px, py
    if hasSquare then
        ax, ay = square:getX(), square:getY()
    end

    local clickRadius = bbmc_num("BlackMarket_StaticClickRadius", 4, 1, 12)
    local playerRadius = bbmc_num("BlackMarket_StaticPlayerRadius", 8, 2, 24)
    local clickBest, clickBestDist = nil, nil
    local playerBest, playerBestDist = nil, nil

    bbmc_eachContact(function(marker)
        local pd = bbmc_dist(marker.x, marker.y, px, py)
        if pd > playerRadius then return end

        if not playerBestDist or pd < playerBestDist then
            playerBest = marker
            playerBestDist = pd
        end

        if hasSquare then
            local d = bbmc_dist(marker.x, marker.y, ax, ay)
            if d <= clickRadius and (not clickBestDist or d < clickBestDist) then
                clickBest = marker
                clickBestDist = d
            end
        end
    end)

    -- UI sprites are not real world objects. If the player right-clicks the
    -- drawn sprite or nearby ground, the engine may report a shifted/empty
    -- clicked square. In that case, allow interaction by proximity; the server
    -- still validates distance before any deal is executed.
    local best = clickBest or playerBest
    if best then
        bbmc_storeLastContact(best)
        return best
    end

    -- Changing access level can briefly recycle client UI/state before the
    -- next server Contacts packet is received. Keep a nearby last-known static
    -- contact usable for click handling only; the server still validates the
    -- real contact and distance before any transaction.
    return bbmc_lastKnownContactNear(player, playerRadius + 4)
end

local function bbmc_screenContact(player, mx, my)
    if not (player and player.getX and player.getY) then return nil end
    mx = tonumber(mx) or ((getMouseX and getMouseX()) or 0)
    my = tonumber(my) or ((getMouseY and getMouseY()) or 0)

    local maxDrawDist = bbmc_num("BlackMarket_StaticDrawRadius", 70, 8, 180)
    local size = bbmc_num("BlackMarket_StaticSpriteSize", 48, 16, 128)
    local padding = bbmc_num("BlackMarket_StaticClickPadding", 16, 0, 64)
    local best, bestDist = nil, nil
    local seen = {}

    local function testContact(contact)
        if type(contact) ~= "table" then return end
        local key = tostring(contact.blackMarketId or contact.id or "")
        if key ~= "" then
            if seen[key] then return end
            seen[key] = true
        end
        local x, y, z = tonumber(contact.x), tonumber(contact.y), tonumber(contact.z) or 0
        if not x or not y then return end
        local pd = bbmc_dist(x, y, player:getX(), player:getY())
        if pd > maxDrawDist then return end
        local sx, sy = bbmc_worldToScreen(x, y, z)
        if not sx or not sy then return end
        local dx = math.floor(sx - (size / 2))
        local dy = math.floor(sy - size + 4)
        if mx < dx - padding or mx > dx + size + padding then return end
        if my < dy - padding or my > dy + size + padding then return end
        local sd = bbmc_dist(mx, my, dx + (size / 2), dy + (size / 2))
        if not bestDist or sd < bestDist then
            best = contact
            bestDist = sd
        end
    end

    bbmc_eachContact(testContact)
    testContact(NPCBlackMarketClientBridge.lastKnownContact)
    if best then
        bbmc_storeLastContact(best)
        return best
    end
    return nil
end

local function bbmc_sideLabel(side)
    local key = BBMC_LEGACY_TEXT_PREFIX .. "Side_" .. tostring(side or "faction")
    local label = getText(key)
    if label and label ~= key then return label end
    if NPCBlackMarketBridge and NPCBlackMarketBridge.SideLabel then return NPCBlackMarketBridge.SideLabel(side) end
    return tostring(side or "faction")
end

local function bbmc_priceLabel(action)
    if NPCBlackMarketBridge and NPCBlackMarketBridge.DealCost then
        local resource, amount = NPCBlackMarketBridge.DealCost(action)
        if resource then
            local key = BBMC_LEGACY_TEXT_PREFIX .. "Menu_Resource_" .. tostring(resource)
            local label = getText(key)
            if label == key then label = tostring(resource) end
            return tostring(amount or 0) .. " " .. label
        end
    end
    return bbmc_text("Menu_Trade")
end

local function bbmc_deal(player, contact, action, side)
    if not player then return end
    sendClientCommand(player, 'NPCBlackMarket', 'Deal', {contactId=contact and (contact.blackMarketId or contact.id), action=action, side=side})
end

local function bbmc_addSideDeals(menu, player, contact, label, action)
    local root = menu:addOption(label)
    local sub = menu:getNew(menu)
    menu:addSubMenu(root, sub)
    for _, side in ipairs({"red", "green", "blue"}) do
        sub:addOption(bbmc_sideLabel(side) .. " — " .. bbmc_priceLabel(action), player, function(p) bbmc_deal(p, contact, action, side) end)
    end
end

local function bbmc_contextHasOption(context, label)
    if not (context and label) then return false end
    local options = context.options
    if type(options) ~= "table" then return false end
    for _, option in ipairs(options) do
        if type(option) == "table" then
            local name = option.name or option.text
            if name == label then return true end
        end
    end
    return false
end

local function bbmc_clearContextMenu(context)
    if not context then return end
    if context.removeFromUIManager then pcall(function() context:removeFromUIManager() end) end
    if context.clear then pcall(function() context:clear() end) end
end

local function bbmc_showContextMenu(context, x, y)
    if not context then return end
    if x and context.setX then pcall(function() context:setX(math.floor(tonumber(x) or 0)) end) end
    if y and context.setY then pcall(function() context:setY(math.floor(tonumber(y) or 0)) end) end
    if context.addToUIManager then pcall(function() context:addToUIManager() end) end
    if context.setVisible then pcall(function() context:setVisible(true) end) end
    if context.bringToTop then pcall(function() context:bringToTop() end) end
end

local function bbmc_addBlackMarketMenu(context, player, contact, forceAdd)
    if not (context and player and contact) then return false end
    local label = bbmc_text("Menu_BlackMarket")
    if not forceAdd and bbmc_contextHasOption(context, label) then return true end

    local root = context:addOption(label)
    local menu = context:getNew(context)
    context:addSubMenu(root, menu)
    menu:addOption(bbmc_text("Menu_CheckBlackMarketStatus"), player, NPCBlackMarketClientBridge.Status)
    menu:addOption(bbmc_text("Menu_RefreshBlackMarketMarkers"), player, NPCBlackMarketClientBridge.Refresh)

    menu:addOption(bbmc_text("Menu_Contact") .. ": " .. bbmc_sideLabel(contact.blackMarketSide or contact.sourceSide or "neutral"), player, function() bbmc_halo(bbmc_text("Menu_BlackMarketContactReady"), 230, 220, 150) end)
    bbmc_addSideDeals(menu, player, contact, bbmc_text("Menu_BuyForgedPapers"), "forged_papers")
    bbmc_addSideDeals(menu, player, contact, bbmc_text("Menu_BuyStolenBadge"), "stolen_badge")
    bbmc_addSideDeals(menu, player, contact, bbmc_text("Menu_BuyDailyPassword"), "password")
    bbmc_addSideDeals(menu, player, contact, bbmc_text("Menu_PayOffBounty"), "bounty_payoff")
    bbmc_addSideDeals(menu, player, contact, bbmc_text("Menu_BuyLeaderRumor"), "leader_tip")
    NPCBlackMarketClientBridge.lastContextMenuMs = bbmc_nowMs()
    return true
end

local function bbmc_openManualContextForContact(playerNum, x, y, contact)
    if not bbmc_bool("BlackMarket_Enabled", true) then return false end
    if not (ISContextMenu and ISContextMenu.get) then return false end

    local player = bbmc_player(playerNum)
    if not (player and contact) then return false end

    local now = bbmc_nowMs()
    if NPCBlackMarketClientBridge.lastContextMenuMs and now - NPCBlackMarketClientBridge.lastContextMenuMs < 120 then return true end

    bbmc_storeLastContact(contact)
    local mx = tonumber(x) or (getMouseX and getMouseX()) or 0
    local my = tonumber(y) or (getMouseY and getMouseY()) or 0
    local okCtx, context = pcall(function() return ISContextMenu.get(playerNum or 0, math.floor(mx), math.floor(my)) end)
    if not okCtx or not context then return false end

    -- Manual overlay/global fallback must not reuse stale options from a pooled
    -- context menu. This can happen after /setaccesslevel changes the local UI
    -- state. Clear only after a valid nearby black-market contact was found.
    bbmc_clearContextMenu(context)
    local added = bbmc_addBlackMarketMenu(context, player, contact, true)
    if added then bbmc_showContextMenu(context, mx, my) end
    return added
end

local function bbmc_openManualContext(playerNum, x, y)
    local player = bbmc_player(playerNum)
    if not player then return false end
    local okContact, contact = pcall(function() return bbmc_screenContact(player, x, y) or bbmc_nearestContact(player, nil) end)
    if not okContact or not contact then return false end
    return bbmc_openManualContextForContact(playerNum, x, y, contact)
end

local function bbmc_playerCanBeRepulsed(player)
    if not (player and player.getX and player.getY and player.getZ) then return false end
    if player.isDead then
        local ok, dead = pcall(function() return player:isDead() end)
        if ok and dead then return false end
    end
    if player.getVehicle then
        local ok, vehicle = pcall(function() return player:getVehicle() end)
        if ok and vehicle then return false end
    end
    if player.isNoClip then
        local ok, noclip = pcall(function() return player:isNoClip() end)
        if ok and noclip then return false end
    end
    return true
end

local function bbmc_applyWorldPropRepulsion(now)
    now = tonumber(now) or bbmc_nowMs()
    if NPCBlackMarketClientBridge.lastRepulseMs and now - NPCBlackMarketClientBridge.lastRepulseMs < BBMC_WORLD_PROP_REPULSE_INTERVAL_MS then return end
    NPCBlackMarketClientBridge.lastRepulseMs = now
    if not bbmc_bool("BlackMarket_Enabled", true) then return end

    local player = getPlayer() or getSpecificPlayer(0)
    if not bbmc_playerCanBeRepulsed(player) then return end

    local px, py, pz = player:getX(), player:getY(), player:getZ()
    local radius = BBMC_WORLD_PROP_REPULSE_RADIUS
    local radius2 = radius * radius
    local best, bestD2 = nil, nil
    local seen = {}

    bbmc_eachContact(function(contact, key)
        local x, y, z = tonumber(contact.x), tonumber(contact.y), tonumber(contact.z) or 0
        if not x or not y then return end
        if math.abs((tonumber(pz) or 0) - z) > 0.5 then return end
        key = tostring(key or contact.blackMarketId or contact.id or "")
        if key ~= "" then
            if seen[key] then return end
            seen[key] = true
        end
        local dx = (tonumber(px) or 0) - (x + 0.5)
        local dy = (tonumber(py) or 0) - (y + 0.5)
        local d2 = dx * dx + dy * dy
        if d2 <= radius2 and (not bestD2 or d2 < bestD2) then
            best = {dx=dx, dy=dy}
            bestD2 = d2
        end
    end)

    if not best then return end

    local dist = math.sqrt(bestD2 or 0)
    local nx, ny = best.dx, best.dy
    if dist < 0.001 then
        nx, ny = 1, 0
    else
        nx, ny = nx / dist, ny / dist
    end

    local force = math.min(BBMC_WORLD_PROP_REPULSE_FORCE, math.max(0.015, (radius - dist) * 0.35))
    if player.setImpulsex and player.setImpulsey then
        pcall(function()
            local ix = player.getImpulsex and player:getImpulsex() or 0
            local iy = player.getImpulsey and player:getImpulsey() or 0
            player:setImpulsex((tonumber(ix) or 0) + nx * force)
            player:setImpulsey((tonumber(iy) or 0) + ny * force)
        end)
    elseif player.setNx and player.setNy and player.getNx and player.getNy then
        pcall(function()
            player:setNx(player:getNx() + nx * force)
            player:setNy(player:getNy() + ny * force)
        end)
    end
end

function NPCBlackMarketClientBridge.Status(player)
    player = player or getPlayer() or getSpecificPlayer(0)
    if not player then return end
    sendClientCommand(player, 'NPCBlackMarket', 'Status', {})
end

function NPCBlackMarketClientBridge.Refresh(player)
    player = player or getPlayer() or getSpecificPlayer(0)
    if not player then return end
    sendClientCommand(player, 'NPCBlackMarket', 'Refresh', {})
end

function NPCBlackMarketClientBridge.OnFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    if test or not bbmc_bool("BlackMarket_Enabled", true) then return end
    local player = bbmc_player(playerNum)
    if not player then return end
    local okContact, contact = pcall(function() return bbmc_nearestContact(player, worldobjects) end)
    if not okContact or not contact then return end

    local added = bbmc_addBlackMarketMenu(context, player, contact)
    if added then
        local mx = (getMouseX and getMouseX()) or nil
        local my = (getMouseY and getMouseY()) or nil
        bbmc_showContextMenu(context, mx, my)
    end
end

local function bbmc_getTexture()
    local path = BBMC_STATIC_SPRITE
    if NPCBlackMarketBridge and NPCBlackMarketBridge.SpritePath then
        path = NPCBlackMarketBridge.SpritePath() or path
    end
    local ok, tex = pcall(function() return getTexture(path) end)
    if ok and tex then return tex end
    return nil
end

bbmc_worldToScreen = function(x, y, z)
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

local function bbmc_worldPropSpritePath(contact)
    local path = nil
    if NPCBlackMarketBridge and NPCBlackMarketBridge.SpritePathForContact then
        local ok, got = pcall(function() return NPCBlackMarketBridge.SpritePathForContact(contact) end)
        if ok and type(got) == "string" and got ~= "" then path = got end
    end
    if not path and type(contact) == "table" and type(contact.blackMarketSprite) == "string" then
        path = contact.blackMarketSprite
    end
    path = path or BBMC_STATIC_SPRITE
    local converted = path:gsub("media/ui/black_market_service", BBMC_WORLD_PROP_SPRITE_PREFIX)
    if converted ~= path then return converted end
    return path
end

local function bbmc_gridSquare(x, y, z)
    local cell = getCell and getCell() or nil
    if not (cell and cell.getGridSquare) then return nil end
    local gx = math.floor((tonumber(x) or 0) + 0.5)
    local gy = math.floor((tonumber(y) or 0) + 0.5)
    local gz = math.floor(tonumber(z) or 0)
    local ok, square = pcall(function() return cell:getGridSquare(gx, gy, gz) end)
    if ok then return square, gx, gy, gz end
    return nil, gx, gy, gz
end

local function bbmc_objectModData(obj)
    if not (obj and obj.getModData) then return nil end
    local ok, md = pcall(function() return obj:getModData() end)
    if ok and type(md) == "table" then return md end
    return nil
end

local function bbmc_markWorldProp(obj, contact, key, spritePath)
    local md = bbmc_objectModData(obj)
    if type(md) ~= "table" then return end
    md.blackMarket = true
    md.blackMarketId = key
    md.BlackMarketId = key
    md[BBMC_LEGACY_KEYS.blackMarketProp] = true
    md.blackMarketWorldProp = true
    md.blackMarketSpriteVariant = spritePath
    md.blackMarketNonPersistentVisual = true
    if type(contact) == "table" then
        md.blackMarketSide = contact.blackMarketSide or contact.sourceSide
        md.blackMarketStatus = contact.blackMarketStatus
    end
end

local function bbmc_findWorldPropOnSquare(square, key)
    if not (square and square.getObjects) then return nil end
    local objects = nil
    local okObjects, gotObjects = pcall(function() return square:getObjects() end)
    if okObjects then objects = gotObjects end
    if not (objects and objects.size and objects.get) then return nil end
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        local md = bbmc_objectModData(obj)
        if type(md) == "table" and (md[BBMC_LEGACY_KEYS.blackMarketProp] == true or md.blackMarketWorldProp == true) then
            if not key or tostring(md.blackMarketId or md.BlackMarketId or "") == tostring(key) then
                return obj
            end
        end
    end
    return nil
end

local function bbmc_loadIsoSprite(spritePath)
    if not (IsoSprite and IsoSprite.new and type(spritePath) == "string" and spritePath ~= "") then return nil end
    local okSprite, sprite = pcall(function() return IsoSprite.new() end)
    if not okSprite or not sprite then return nil end

    local candidates = {spritePath}
    local noExt = spritePath:gsub("%.png$", "")
    if noExt ~= spritePath then candidates[#candidates + 1] = noExt end

    for _, candidate in ipairs(candidates) do
        if sprite.LoadFramesNoDirPageSimple then
            local ok = pcall(function() sprite:LoadFramesNoDirPageSimple(candidate) end)
            if ok then return sprite end
        end
        if sprite.LoadFrameExplicit then
            local ok = pcall(function() sprite:LoadFrameExplicit(candidate) end)
            if ok then return sprite end
        end
    end
    return nil
end

local function bbmc_applyWorldPropSprite(obj, spritePath)
    if not obj then return false end
    local sprite = bbmc_loadIsoSprite(spritePath)
    if sprite and obj.setSprite then
        local ok = pcall(function() obj:setSprite(sprite) end)
        if ok then return true end
    end
    if obj.setSpriteName and type(spritePath) == "string" then
        local ok = pcall(function() obj:setSpriteName(spritePath) end)
        if ok then return true end
    end
    return false
end

local function bbmc_removeWorldPropByKey(key)
    key = tostring(key or "")
    local entry = NPCBlackMarketClientBridge.worldProps and NPCBlackMarketClientBridge.worldProps[key] or nil
    if not entry then return end
    NPCBlackMarketClientBridge.worldProps[key] = nil
    local obj = entry.object
    local square = entry.square or (obj and obj.getSquare and obj:getSquare() or nil)
    if square and obj then
        if square.RemoveTileObject then pcall(function() square:RemoveTileObject(obj) end) end
        if square.removeTileObject then pcall(function() square:removeTileObject(obj) end) end
        if square.getSpecialObjects and square.RemoveSpecialObject then pcall(function() square:RemoveSpecialObject(obj) end) end
    end
    if obj then
        if obj.removeFromWorld then pcall(function() obj:removeFromWorld() end) end
        if obj.removeFromSquare then pcall(function() obj:removeFromSquare() end) end
    end
end

function NPCBlackMarketClientBridge.CleanupWorldProps()
    for key, _ in pairs(NPCBlackMarketClientBridge.worldProps or {}) do
        bbmc_removeWorldPropByKey(key)
    end
    NPCBlackMarketClientBridge.worldProps = {}
end

local function bbmc_createWorldProp(contact, key)
    local spritePath = bbmc_worldPropSpritePath(contact)
    local square, gx, gy, gz = bbmc_gridSquare(contact.x, contact.y, contact.z)
    if not square then return nil end

    local existing = bbmc_findWorldPropOnSquare(square, key)
    if existing then
        bbmc_markWorldProp(existing, contact, key, spritePath)
        return {object=existing, square=square, x=gx, y=gy, z=gz, sprite=spritePath}
    end

    if not (IsoObject and IsoObject.new) then return nil end
    local okObj, obj = pcall(function() return IsoObject.new(square, "", "") end)
    if (not okObj or not obj) then
        okObj, obj = pcall(function() return IsoObject.new(square, spritePath, "") end)
    end
    if not okObj or not obj then return nil end

    local appliedSprite = bbmc_applyWorldPropSprite(obj, spritePath)
    if not appliedSprite then
        local okNamed, namedObj = pcall(function() return IsoObject.new(square, spritePath, "") end)
        if okNamed and namedObj then obj = namedObj end
    end
    if obj.setName then pcall(function() obj:setName("BlackMarketWorldObject") end) end
    bbmc_markWorldProp(obj, contact, key, spritePath)

    local added = false
    if square.AddSpecialObject then
        added = pcall(function() square:AddSpecialObject(obj) end)
    end
    if not added and square.AddTileObject then
        added = pcall(function() square:AddTileObject(obj) end)
    end
    if not added then return nil end

    return {object=obj, square=square, x=gx, y=gy, z=gz, sprite=spritePath}
end

function NPCBlackMarketClientBridge.SyncWorldProps(force)
    if not bbmc_bool("BlackMarket_Enabled", true) then
        NPCBlackMarketClientBridge.CleanupWorldProps()
        return
    end

    local player = getPlayer() or getSpecificPlayer(0)
    if not (player and player.getX and player.getY) then return end
    local maxDrawDist = bbmc_num("BlackMarket_StaticDrawRadius", 70, 8, 180)
    local wanted = {}

    bbmc_eachContact(function(contact, key)
        local x, y, z = tonumber(contact.x), tonumber(contact.y), tonumber(contact.z) or 0
        if not x or not y then return end
        if bbmc_dist(x, y, player:getX(), player:getY()) > maxDrawDist then return end
        local square, gx, gy, gz = bbmc_gridSquare(x, y, z)
        if not square then return end
        local spritePath = bbmc_worldPropSpritePath(contact)
        wanted[key] = true
        local entry = NPCBlackMarketClientBridge.worldProps[key]
        if not entry or not entry.object or entry.square ~= square or entry.x ~= gx or entry.y ~= gy or entry.z ~= gz or entry.sprite ~= spritePath or force then
            bbmc_removeWorldPropByKey(key)
            entry = bbmc_createWorldProp(contact, key)
            if entry then NPCBlackMarketClientBridge.worldProps[key] = entry end
        else
            bbmc_markWorldProp(entry.object, contact, key, spritePath)
        end
        bbmc_storeLastContact(contact)
    end)

    for key, _ in pairs(NPCBlackMarketClientBridge.worldProps or {}) do
        if not wanted[key] then bbmc_removeWorldPropByKey(key) end
    end
end

local BBMC_OVERLAY_BASE = ISPanel or ISUIElement
if BBMC_OVERLAY_BASE and BBMC_OVERLAY_BASE.derive then
    NPCBlackMarketStaticOverlayBridge = NPCBlackMarketStaticOverlayBridge or BBMC_OVERLAY_BASE:derive("NPCBlackMarketStaticOverlayBridge")
else
    NPCBlackMarketStaticOverlayBridge = nil
end

if NPCBlackMarketStaticOverlayBridge then
function NPCBlackMarketStaticOverlayBridge:initialise()
    if ISPanel and ISPanel.initialise then
        ISPanel.initialise(self)
    elseif ISUIElement and ISUIElement.initialise then
        ISUIElement.initialise(self)
    end
    if self.addToUIManager then self:addToUIManager() end
    if self.setVisible then self:setVisible(true) end
end
end

if NPCBlackMarketStaticOverlayBridge then
function NPCBlackMarketStaticOverlayBridge:onMouseDown(x, y)
    return false
end

function NPCBlackMarketStaticOverlayBridge:onMouseUp(x, y)
    return false
end

function NPCBlackMarketStaticOverlayBridge:onMouseMove(dx, dy)
    return false
end

function NPCBlackMarketStaticOverlayBridge:onMouseWheel(del)
    return false
end

function NPCBlackMarketStaticOverlayBridge:onRightMouseDown(x, y)
    -- Admin access can put admin/debug UI above normal world handlers. Keep the
    -- static black-market overlay above them, but consume right-clicks only when
    -- the cursor is actually over the drawn service sprite.
    local mx = (getMouseX and getMouseX()) or x or 0
    local my = (getMouseY and getMouseY()) or y or 0
    local player = bbmc_player(0)
    local contact = player and bbmc_screenContact(player, mx, my) or nil
    if contact then
        self.__NPCBlackMarketRightClickContact = contact
        bbmc_openManualContextForContact(0, mx, my, contact)
        return true
    end
    self.__NPCBlackMarketRightClickContact = nil
    return false
end

function NPCBlackMarketStaticOverlayBridge:onRightMouseUp(x, y)
    local mx = (getMouseX and getMouseX()) or x or 0
    local my = (getMouseY and getMouseY()) or y or 0
    local contact = self.__NPCBlackMarketRightClickContact
    self.__NPCBlackMarketRightClickContact = nil
    if not contact then
        local player = bbmc_player(0)
        contact = player and bbmc_screenContact(player, mx, my) or nil
    end
    if contact then
        bbmc_openManualContextForContact(0, mx, my, contact)
        return true
    end
    return false
end

function NPCBlackMarketStaticOverlayBridge:render()
    if not bbmc_bool("BlackMarket_Enabled", true) then return end
    local player = getPlayer() or getSpecificPlayer(0)
    if not (player and player.getX and player.getY) then return end
    local tex = bbmc_getTexture()
    local maxDrawDist = bbmc_num("BlackMarket_StaticDrawRadius", 70, 8, 180)
    local size = bbmc_num("BlackMarket_StaticSpriteSize", 48, 16, 128)
    local core = getCore and getCore() or nil
    local sw = core and core.getScreenWidth and core:getScreenWidth() or self.width
    local sh = core and core.getScreenHeight and core:getScreenHeight() or self.height
    self:setWidth(sw)
    self:setHeight(sh)

    bbmc_eachContact(function(contact)
        local x, y, z = tonumber(contact.x), tonumber(contact.y), tonumber(contact.z) or 0
        if not x or not y then return end
        local dist = bbmc_dist(x, y, player:getX(), player:getY())
        if dist > maxDrawDist then return end
        local sx, sy = bbmc_worldToScreen(x, y, z)
        if not sx or not sy then return end
        local dx = math.floor(sx - (size / 2))
        local dy = math.floor(sy - size + 4)
        if dx < -size or dy < -size or dx > sw + size or dy > sh + size then return end
        local alpha = math.max(0.35, math.min(1.0, 1.0 - (dist / maxDrawDist) * 0.55))
        if tex then
            self:drawTextureScaled(tex, dx, dy, size, size, alpha, 1, 1, 1)
        else
            self:drawRect(dx + 8, dy + 8, size - 16, size - 16, alpha, 0.10, 0.06, 0.12)
            self:drawTextCentre("BM", dx + size / 2, dy + size / 2 - 6, 0.95, 0.75, 1.0, alpha, UIFont.Small)
        end
        if dist <= 10 then
            local label = bbmc_text("Map_BlackMarket")
            if label == BBMC_LEGACY_TEXT_PREFIX .. "Map_BlackMarket" then label = "BLACK MARKET" end
            self:drawTextCentre(label, dx + size / 2, dy - 12, 0.78, 0.55, 1.0, alpha, UIFont.Small)
        end
    end)
end

function NPCBlackMarketStaticOverlayBridge:new()
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
    -- Keep the overlay transparent and non-modal. It should render the sprite,
    -- but must not sit above top inventory/loot/tool UI panels, otherwise those
    -- bars become unclickable. Black-market interaction is also handled by the
    -- global right-click events below, so the overlay does not need to live on
    -- top of every other UI element.
    if o.setAlwaysOnTop then pcall(function() o:setAlwaysOnTop(false) end) end
    if o.setCapture then pcall(function() o:setCapture(false) end) end
    if o.noBackground then pcall(function() o:noBackground() end) end
    return o
end
end

function NPCBlackMarketClientBridge.EnsureOverlay()
    -- World-prop mode must not create a UI overlay. The prop exists as an IsoObject
    -- on the map; right-click fallback is handled by global mouse events below.
end

function NPCBlackMarketClientBridge.OnServerCommand(module, command, args)
    if not NPCLegacyContractBridge.IsModule(module, "NPCBlackMarket", "blackMarket") then return end
    if command == "Result" and args and args.text then
        bbmc_halo(args.text, args.r, args.g, args.b)
    elseif command == "Contacts" and args then
        NPCBlackMarketClientBridge.contacts = {}
        for _, contact in pairs(args.contacts or {}) do
            if type(contact) == "table" and contact.id then
                NPCBlackMarketClientBridge.contacts[tostring(contact.id)] = contact
                local player = getPlayer() or getSpecificPlayer(0)
                local radius = bbmc_num("BlackMarket_StaticPlayerRadius", 8, 2, 24) + 8
                if player and contact.x and contact.y and bbmc_dist(contact.x, contact.y, player:getX(), player:getY()) <= radius then
                    bbmc_storeLastContact(contact)
                end
            end
        end
        NPCBlackMarketClientBridge.SyncWorldProps(true)
    end
end

local bbmc_resetOverlay

local function bbmc_onCreatePlayer()
    if bbmc_resetOverlay then bbmc_resetOverlay() end
    local player = getPlayer() or getSpecificPlayer(0)
    if player then NPCBlackMarketClientBridge.Refresh(player) end
    NPCBlackMarketClientBridge.SyncWorldProps(true)
end

local function bbmc_onRightMouseDown(x, y)
    local player = bbmc_player(0)
    local contact = player and bbmc_screenContact(player, x, y) or nil
    if contact then bbmc_openManualContextForContact(0, x, y, contact) end
end

local function bbmc_onRightMouseUp(x, y)
    bbmc_openManualContext(0, x, y)
end

bbmc_resetOverlay = function()
    local overlay = NPCBlackMarketClientBridge.overlay
    if overlay then
        if overlay.removeFromUIManager then pcall(function() overlay:removeFromUIManager() end) end
        if overlay.setVisible then pcall(function() overlay:setVisible(false) end) end
    end
    NPCBlackMarketClientBridge.overlay = nil
end

local function bbmc_accessLevel(player)
    if player and player.getAccessLevel then
        local ok, value = pcall(function() return player:getAccessLevel() end)
        if ok and value ~= nil then return tostring(value) end
    end
    return ""
end

local function bbmc_onTick()
    local now = bbmc_nowMs()
    bbmc_applyWorldPropRepulsion(now)
    if NPCBlackMarketClientBridge.lastAccessCheckMs and now - NPCBlackMarketClientBridge.lastAccessCheckMs < 1000 then return end
    NPCBlackMarketClientBridge.lastAccessCheckMs = now

    local player = getPlayer() or getSpecificPlayer(0)
    if not player then return end
    local access = bbmc_accessLevel(player)
    if NPCBlackMarketClientBridge.lastAccessLevel == nil then
        NPCBlackMarketClientBridge.lastAccessLevel = access
    elseif NPCBlackMarketClientBridge.lastAccessLevel ~= access then
        NPCBlackMarketClientBridge.lastAccessLevel = access
        NPCBlackMarketClientBridge.lastContextMenuMs = nil
        NPCBlackMarketClientBridge.lastAccessChangedAtMs = now
        bbmc_resetOverlay()
        NPCBlackMarketClientBridge.Refresh(player)
    elseif NPCBlackMarketClientBridge.lastAccessChangedAtMs and now - NPCBlackMarketClientBridge.lastAccessChangedAtMs < 5000 then
        -- During admin promotion/demotion PZ can rebuild UI/player state over a
        -- few frames. Keep refreshing the static contact list briefly so the
        -- right-click fallback has valid data even if the first packet arrived
        -- while the UI was being recycled.
        if not NPCBlackMarketClientBridge.lastPostAccessRefreshMs or now - NPCBlackMarketClientBridge.lastPostAccessRefreshMs > 1000 then
            NPCBlackMarketClientBridge.lastPostAccessRefreshMs = now
            NPCBlackMarketClientBridge.lastContextMenuMs = nil
            NPCBlackMarketClientBridge.Refresh(player)
        end
    end

    NPCBlackMarketClientBridge.SyncWorldProps(false)
end

Events.OnFillWorldObjectContextMenu.Add(NPCBlackMarketClientBridge.OnFillWorldObjectContextMenu)
Events.OnServerCommand.Add(NPCBlackMarketClientBridge.OnServerCommand)
Events.OnCreatePlayer.Add(bbmc_onCreatePlayer)
Events.OnGameStart.Add(function()
    bbmc_resetOverlay()
    NPCBlackMarketClientBridge.SyncWorldProps(true)
end)
if Events.OnRightMouseDown then Events.OnRightMouseDown.Add(bbmc_onRightMouseDown) end
if Events.OnRightMouseUp then Events.OnRightMouseUp.Add(bbmc_onRightMouseUp) end
if Events.OnSave then Events.OnSave.Add(NPCBlackMarketClientBridge.CleanupWorldProps) end
if Events.OnDisconnect then Events.OnDisconnect.Add(NPCBlackMarketClientBridge.CleanupWorldProps) end
if Events.OnTick then Events.OnTick.Add(bbmc_onTick) end
