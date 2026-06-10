-- NPCBlackMarketClientBridge.lua
-- Static black market world-prop visual and context menu.
-- The black market is intentionally not an IsoZombie/IsoGameCharacter.

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCIntelDossierBridge"
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

local function bbmc_textOr(key, fallback)
    local text = bbmc_text(key)
    if text == BBMC_LEGACY_TEXT_PREFIX .. tostring(key or "") then return tostring(fallback or key or "") end
    return text
end
NPCBlackMarketClientBridge.contacts = NPCBlackMarketClientBridge.contacts or {}
NPCBlackMarketClientBridge.overlay = NPCBlackMarketClientBridge.overlay or nil
NPCBlackMarketClientBridge.lastKnownContact = NPCBlackMarketClientBridge.lastKnownContact or nil
NPCBlackMarketClientBridge.worldProps = NPCBlackMarketClientBridge.worldProps or {}
NPCBlackMarketClientBridge.dropMarkers = NPCBlackMarketClientBridge.dropMarkers or {}
NPCBlackMarketClientBridge.fetchQuest = NPCBlackMarketClientBridge.fetchQuest or nil
NPCBlackMarketClientBridge.fetchQuestHasItem = NPCBlackMarketClientBridge.fetchQuestHasItem == true
NPCBlackMarketClientBridge.defenseQuest = NPCBlackMarketClientBridge.defenseQuest or nil
NPCBlackMarketClientBridge._fetchQuestZoneOverlayHookInstalled = NPCBlackMarketClientBridge._fetchQuestZoneOverlayHookInstalled or false

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
        if key == "" then return end
        if seen[key] then
            if marker.blackMarketHasPendingReward == true or marker.blackMarketRewardHighlight == true or marker.blackMarketQuestTurnInHighlight == true then
                local stored = NPCBlackMarketClientBridge.contacts and NPCBlackMarketClientBridge.contacts[key] or nil
                if type(stored) == "table" then
                    stored.blackMarketHasPendingReward = marker.blackMarketHasPendingReward == true or nil
                    stored.blackMarketRewardHighlight = marker.blackMarketRewardHighlight == true or nil
                    stored.blackMarketQuestTurnInHighlight = marker.blackMarketQuestTurnInHighlight == true or nil
                    stored.blackMarketRewardX = marker.blackMarketRewardX
                    stored.blackMarketRewardY = marker.blackMarketRewardY
                    stored.blackMarketRewardZ = marker.blackMarketRewardZ
                end
            end
            return
        end
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

local function bbmc_paymentSnapshot(player)
    local out = { gold = 0, silver = 0 }
    if not (player and NPCBlackMarketBridge and NPCBlackMarketBridge.CountItems) then return out end
    local okGold, gold = pcall(function() return NPCBlackMarketBridge.CountItems(player, "gold") end)
    if okGold then out.gold = math.floor(tonumber(gold) or 0) end
    local okSilver, silver = pcall(function() return NPCBlackMarketBridge.CountItems(player, "silver") end)
    if okSilver then out.silver = math.floor(tonumber(silver) or 0) end
    return out
end

local function bbmc_deal(player, contact, action, side)
    if not player then return end
    local args = {contactId=contact and (contact.blackMarketId or contact.id), action=action, side=side}
    if NPCBlackMarketBridge and NPCBlackMarketBridge.DealCost then
        local okCost, resource, amount = pcall(function() return NPCBlackMarketBridge.DealCost(action) end)
        if okCost and resource then
            local counts = bbmc_paymentSnapshot(player)
            args.clientPaymentResource = tostring(resource)
            args.clientPaymentAmount = math.floor(tonumber(amount) or 0)
            args.clientPaymentGoldCount = counts.gold
            args.clientPaymentSilverCount = counts.silver
            args.clientPaymentOk = (resource == "gold" and counts.gold >= args.clientPaymentAmount) or (resource == "silver" and counts.silver >= args.clientPaymentAmount) or args.clientPaymentAmount <= 0
        end
    end
    local active = nil
    if player.getPrimaryHandItem then
        local ok, item = pcall(function() return player:getPrimaryHandItem() end)
        if ok then active = item end
    end
    if active and active.getFullType then
        local ok, ft = pcall(function() return active:getFullType() end)
        if ok and ft then args.activeWeaponFullType = tostring(ft) end
    end
    sendClientCommand(player, 'NPCBlackMarket', 'Deal', args)
end

local function bbmc_takeClientPayment(args)
    local player = getPlayer() or getSpecificPlayer(0)
    if not (player and args and NPCBlackMarketBridge and NPCBlackMarketBridge.TakeItems) then return end
    local resource = tostring(args.resource or args.clientPaymentResource or "")
    local amount = math.floor(tonumber(args.amount or args.clientPaymentAmount) or 0)
    if amount <= 0 then return end
    local okCall, okPaid = pcall(function() return NPCBlackMarketBridge.TakeItems(player, resource, amount) end)
    print("[NPCBlackMarket] client payment removal ok=" .. tostring(okCall and okPaid == true) .. " resource=" .. tostring(resource) .. " amount=" .. tostring(amount) .. " context=" .. tostring(args.context))
end

local function bbmc_addSideDeals(menu, player, contact, label, action)
    local root = menu:addOption(label)
    local sub = menu:getNew(menu)
    menu:addSubMenu(root, sub)
    for _, side in ipairs({"red", "green", "blue"}) do
        sub:addOption(bbmc_sideLabel(side) .. " — " .. bbmc_priceLabel(action), player, function(p) bbmc_deal(p, contact, action, side) end)
    end
end

local function bbmc_addDropDeals(menu, player, contact)
    if not bbmc_bool("BlackMarket_DeadDropEnabled", true) then return end
    local root = menu:addOption(bbmc_text("Menu_OrderDeadDrop"))
    local sub = menu:getNew(menu)
    menu:addSubMenu(root, sub)
    local side = contact and (contact.blackMarketSide or contact.sourceSide) or nil
    sub:addOption(bbmc_text("Menu_OrderAmmoDrop") .. " — " .. bbmc_priceLabel("ammo_drop"), player, function(p) bbmc_deal(p, contact, "ammo_drop", side) end)
    sub:addOption(bbmc_text("Menu_OrderMedicalDrop") .. " — " .. bbmc_priceLabel("medical_drop"), player, function(p) bbmc_deal(p, contact, "medical_drop", side) end)
    sub:addOption(bbmc_text("Menu_OrderWeaponDrop") .. " — " .. bbmc_priceLabel("weapon_drop"), player, function(p) bbmc_deal(p, contact, "weapon_drop", side) end)
    sub:addOption(bbmc_text("Menu_OrderArmorDrop") .. " — " .. bbmc_priceLabel("armor_drop"), player, function(p) bbmc_deal(p, contact, "armor_drop", side) end)
end

local function bbmc_addIntelDossierSale(menu, player, contact)
    if not bbmc_bool("IntelDossier_Enabled", true) then return end
    if not bbmc_bool("IntelDossier_SellEnabled", true) then return end
    menu:addOption(bbmc_text("Menu_SellIntelDossiers"), player, function(p) bbmc_deal(p, contact, "sell_intel", nil) end)
end

local function bbmc_fetchQuestActive()
    local quest = NPCBlackMarketClientBridge.fetchQuest
    return type(quest) == "table" and tostring(quest.status or "active") == "active" and tostring(quest.id or "") ~= ""
end

local function bbmc_fetchQuestId()
    local quest = NPCBlackMarketClientBridge.fetchQuest
    if type(quest) == "table" then return tostring(quest.id or "") end
    return ""
end

local function bbmc_fetchQuestContactId()
    local quest = NPCBlackMarketClientBridge.fetchQuest
    if type(quest) == "table" then return tostring(quest.contactId or "") end
    return ""
end

local function bbmc_fetchQuestZoneRadius()
    local quest = NPCBlackMarketClientBridge.fetchQuest
    local value = type(quest) == "table" and tonumber(quest.zoneRadius) or nil
    if value and value > 0 then return value end
    if NPCBlackMarketBridge and NPCBlackMarketBridge.FetchQuestZoneRadius then
        local ok, got = pcall(function() return NPCBlackMarketBridge.FetchQuestZoneRadius() end)
        if ok and tonumber(got) then return tonumber(got) end
    end
    return 24
end

local function bbmc_defenseQuestActive()
    local quest = NPCBlackMarketClientBridge.defenseQuest
    return type(quest) == "table" and tostring(quest.status or "active") == "active" and tostring(quest.id or "") ~= ""
end

local function bbmc_defenseQuestId()
    local quest = NPCBlackMarketClientBridge.defenseQuest
    if type(quest) == "table" then return tostring(quest.id or "") end
    return ""
end

local function bbmc_defenseQuestZoneRadius()
    local quest = NPCBlackMarketClientBridge.defenseQuest
    local value = type(quest) == "table" and tonumber(quest.zoneRadius) or nil
    if value and value > 0 then return value end
    if NPCBlackMarketBridge and NPCBlackMarketBridge.DefenseQuestZoneRadius then
        local ok, got = pcall(function() return NPCBlackMarketBridge.DefenseQuestZoneRadius() end)
        if ok and tonumber(got) then return tonumber(got) end
    end
    return 28
end

local function bbmc_anyContractActive()
    return bbmc_fetchQuestActive() or bbmc_defenseQuestActive()
end

local function bbmc_itemModData(item)
    if not (item and item.getModData) then return nil end
    local ok, md = pcall(function() return item:getModData() end)
    if ok and type(md) == "table" then return md end
    return nil
end

local function bbmc_truthy(value)
    if value == true then return true end
    if tonumber(tostring(value or "")) == 1 then return true end
    local text = string.lower(tostring(value or ""))
    return text == "true" or text == "yes" or text == "y"
end

local function bbmc_itemFullType(item)
    if not item then return nil end
    local ok, fullType = pcall(function() return item:getFullType() end)
    if ok and fullType and tostring(fullType) ~= "" then return tostring(fullType) end
    ok, fullType = pcall(function() return item:getType() end)
    if ok and fullType and tostring(fullType) ~= "" then
        fullType = tostring(fullType)
        if not string.find(fullType, ".", 1, true) then fullType = "Base." .. fullType end
        return fullType
    end
    return nil
end

local function bbmc_fetchQuestItemNameLooksQuest(item)
    if not item then return false end
    local methods = {"getName", "getDisplayName"}
    for _, method in ipairs(methods) do
        if item[method] then
            local ok, name = pcall(function() return item[method](item) end)
            if ok and name then
                local text = string.lower(tostring(name))
                if string.sub(text, 1, 6) == "quest:" then return true end
            end
        end
    end
    return false
end

local function bbmc_fetchQuestItemMatches(item, questId)
    local quest = NPCBlackMarketClientBridge.fetchQuest
    local md = bbmc_itemModData(item)
    local wantedQuestId = tostring(questId or (type(quest) == "table" and quest.id) or "")
    local itemFullType = bbmc_itemFullType(item)
    local questFullType = type(quest) == "table" and tostring(quest.itemFullType or "") or ""
    local nameLooksQuest = bbmc_fetchQuestItemNameLooksQuest(item)
    if md then
        local mdId = tostring(md.blackMarketFetchQuestId or md.blackMarketDropId or md.blackMarketQuestId or "")
        local markedItem = bbmc_truthy(md.blackMarketFetchQuestItem) or tostring(md.blackMarketFetchQuestRole or "") == "item" or tostring(md.blackMarketDropRole or "") == "content"
        if wantedQuestId ~= "" and mdId == wantedQuestId then return true end
        if markedItem and (nameLooksQuest or questFullType == "" or itemFullType == questFullType) then return true end
    end
    if nameLooksQuest then return true end
    if questFullType ~= "" and itemFullType == questFullType then return true end
    return false
end

local function bbmc_findFetchQuestItemInContainer(container, questId, depth, seen)
    if not container or tostring(questId or "") == "" or (tonumber(depth) or 0) > 6 then return nil end
    seen = seen or {}
    if seen[container] then return nil end
    seen[container] = true
    if not container.getItems then return nil end
    local okItems, items = pcall(function() return container:getItems() end)
    if not (okItems and items and items.size and items.get) then return nil end
    local okSize, size = pcall(function() return items:size() end)
    size = okSize and (tonumber(size) or 0) or 0
    for i = 0, size - 1 do
        local okItem, item = pcall(function() return items:get(i) end)
        if okItem and item then
            if bbmc_fetchQuestItemMatches(item, questId) then return item end
            local child = nil
            if item.getInventory then
                local okChild, gotChild = pcall(function() return item:getInventory() end)
                if okChild then child = gotChild end
            end
            if child then
                local found = bbmc_findFetchQuestItemInContainer(child, questId, (tonumber(depth) or 0) + 1, seen)
                if found then return found end
            end
        end
    end
    return nil
end

local function bbmc_findFetchQuestItemInWornItems(player, questId)
    if not (player and player.getWornItems and tostring(questId or "") ~= "") then return nil end
    local okWorn, worn = pcall(function() return player:getWornItems() end)
    if not (okWorn and worn) then return nil end
    local size = 0
    if worn.size then
        local okSize, gotSize = pcall(function() return worn:size() end)
        if okSize then size = tonumber(gotSize) or 0 end
    end
    for i = 0, size - 1 do
        local item = nil
        if worn.getItemByIndex then
            local okItem, gotItem = pcall(function() return worn:getItemByIndex(i) end)
            if okItem then item = gotItem end
        end
        if not item and worn.get then
            local okRow, row = pcall(function() return worn:get(i) end)
            if okRow and row then
                if row.getItem then
                    local okItem, gotItem = pcall(function() return row:getItem() end)
                    if okItem then item = gotItem end
                else
                    item = row
                end
            end
        end
        if item and bbmc_fetchQuestItemMatches(item, questId) then return item end
    end
    return nil
end

local function bbmc_findFetchQuestItemInHands(player, questId)
    if not (player and tostring(questId or "") ~= "") then return nil end
    for _, method in ipairs({"getPrimaryHandItem", "getSecondaryHandItem"}) do
        if player[method] then
            local okItem, item = pcall(function() return player[method](player) end)
            if okItem and item and bbmc_fetchQuestItemMatches(item, questId) then return item end
        end
    end
    return nil
end

local function bbmc_playerHasFetchQuestItem(player)
    if not (player and bbmc_fetchQuestActive()) then return false end
    local questId = bbmc_fetchQuestId()
    if player.getInventory then
        local okInv, inv = pcall(function() return player:getInventory() end)
        if okInv and inv and bbmc_findFetchQuestItemInContainer(inv, questId, 0, {}) then return true end
    end
    if bbmc_findFetchQuestItemInWornItems(player, questId) then return true end
    return bbmc_findFetchQuestItemInHands(player, questId) ~= nil
end

local function bbmc_fetchQuestCommand(player, contact, action)
    if not player then return end
    local args = {action=action, contactId=contact and (contact.blackMarketId or contact.id)}
    sendClientCommand(player, 'NPCBlackMarket', 'FetchQuest', args)
end

local function bbmc_defenseQuestCommand(player, contact, action)
    if not player then return end
    local args = {action=action, contactId=contact and (contact.blackMarketId or contact.id)}
    sendClientCommand(player, 'NPCBlackMarket', 'DefenseQuest', args)
end

local function bbmc_clearFetchQuestWorldMarker(questId)
    local id = tostring(questId or "")
    if id == "" then return end
    if NPCDebugMapNPCMarkersBridge and NPCDebugMapNPCMarkersBridge.Remove then pcall(function() NPCDebugMapNPCMarkersBridge.Remove(id) end) end
    if NPCDebugMapMarkersBridge and NPCDebugMapMarkersBridge.markers then NPCDebugMapMarkersBridge.markers[id] = nil end
    if NPCWorldMarkerClientBridge and NPCWorldMarkerClientBridge.Refresh then pcall(function() NPCWorldMarkerClientBridge.Refresh(true) end) end
end

local function bbmc_addDisabled(option, disabled)
    if option and disabled then option.notAvailable = true end
    return option
end

local function bbmc_addFetchQuestMenu(menu, player, contact)
    local root = menu:addOption(bbmc_textOr("Menu_BlackMarketContracts", "Contracts"))
    local sub = menu:getNew(menu)
    menu:addSubMenu(root, sub)

    local active = bbmc_fetchQuestActive()
    local defenseActive = bbmc_defenseQuestActive()
    local anyActive = active or defenseActive
    local hasItem = active and bbmc_playerHasFetchQuestItem(player)
    local activeContactId = bbmc_fetchQuestContactId()
    local thisContactId = tostring(contact and (contact.blackMarketId or contact.id) or "")
    local sameContact = active and activeContactId ~= "" and activeContactId == thisContactId
    NPCBlackMarketClientBridge.fetchQuestHasItem = hasItem == true

    local take = sub:addOption(bbmc_textOr("Menu_TakeFetchQuest", "Take steal contract"), player, function(p) bbmc_fetchQuestCommand(p, contact, "take") end)
    bbmc_addDisabled(take, anyActive)

    local defend = sub:addOption(bbmc_textOr("Menu_TakeDefenseQuest", "Take defense contract"), player, function(p) bbmc_defenseQuestCommand(p, contact, "take") end)
    bbmc_addDisabled(defend, anyActive)

    local turnIn = sub:addOption(bbmc_textOr("Menu_TurnInFetchQuest", "Turn in stolen QUEST item"), player, function(p) bbmc_fetchQuestCommand(p, contact, "turn_in") end)
    bbmc_addDisabled(turnIn, not (active and sameContact))

    if active then
        local quest = NPCBlackMarketClientBridge.fetchQuest
        local label = tostring(quest and quest.itemLabel or "QUEST item")
        sub:addOption(bbmc_textOr("Menu_ActiveFetchQuest", "Active") .. ": " .. label, player, function() bbmc_halo(bbmc_textOr("Menu_FetchQuestHint", "Steal the guarded QUEST item and put it in your inventory or the black-market turn-in box."), 235, 160, 255) end)
    elseif defenseActive then
        local quest = NPCBlackMarketClientBridge.defenseQuest
        local wave = tostring(quest and quest.currentWave or 0) .. "/" .. tostring(quest and quest.totalWaves or 3)
        local stage = tostring(quest and quest.stage or "")
        local remaining = tonumber(quest and quest.remaining) or 0
        local currentWave = tonumber(quest and quest.currentWave) or 0
        local totalWaves = tonumber(quest and quest.totalWaves) or 3
        local rewardPending = stage == "reward_pending" or stage == "reward_failed" or (currentWave >= totalWaves and remaining <= 0)
        if rewardPending then
            sub:addOption(bbmc_textOr("Menu_ClaimDefenseReward", "Claim defense reward"), player, function(p) bbmc_defenseQuestCommand(p, contact, "claim_reward") end)
            sub:addOption(bbmc_textOr("Menu_ActiveDefenseQuest", "Active defense") .. ": reward pending", player, function() bbmc_halo(bbmc_textOr("Menu_DefenseRewardHint", "Defense cleared. Claim the reward at this black market."), 120, 255, 120) end)
        else
            sub:addOption(bbmc_textOr("Menu_ActiveDefenseQuest", "Active defense") .. ": wave " .. wave, player, function() bbmc_halo(bbmc_textOr("Menu_DefenseQuestHint", "Enter and hold the marked zone. Kill all marked attackers."), 255, 90, 180) end)
        end
    else
        sub:addOption(bbmc_textOr("Menu_NoActiveFetchQuest", "No active contract"), player, function() bbmc_halo(bbmc_textOr("Menu_NoActiveFetchQuest", "No active contract"), 210, 210, 210) end)
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
    bbmc_addIntelDossierSale(menu, player, contact)
    bbmc_addDropDeals(menu, player, contact)
    bbmc_addFetchQuestMenu(menu, player, contact)
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

local function bbmc_isDirectCacheDropType(dropType)
    dropType = tostring(dropType or "")
    return dropType == "weapons" or dropType == "ammo" or dropType == "medical" or dropType == "armor"
end

local function bbmc_cacheItemName(item)
    if not item then return "" end
    for _, method in ipairs({"getName", "getDisplayName", "getFullType", "getType"}) do
        local fn = item[method]
        if type(fn) == "function" then
            local ok, value = pcall(function() return fn(item) end)
            if ok and value ~= nil then return tostring(value) end
        end
    end
    return ""
end

local function bbmc_cacheItemCount(item)
    if not item then return nil end
    for _, method in ipairs({"getCount", "getUses", "getCurrentUses", "getDrainableUsesInt"}) do
        local fn = item[method]
        if type(fn) == "function" then
            local ok, value = pcall(function() return fn(item) end)
            if ok and tonumber(value) ~= nil then return tonumber(value) end
        end
    end
    return nil
end

local function bbmc_cacheItemStillUseful(item)
    if not item then return false end
    local count = bbmc_cacheItemCount(item)
    if count ~= nil and count <= 0 then return false end
    return true
end

local function bbmc_cacheInventoryEmpty(item, depth)
    if not item then return true end
    depth = tonumber(depth) or 0
    if depth > 5 then return false end

    local inv = nil
    if item.getInventory then
        local okInv, gotInv = pcall(function() return item:getInventory() end)
        if okInv then inv = gotInv end
    end
    if not inv then return not bbmc_cacheItemStillUseful(item) end

    if inv.isEmpty then
        local okEmpty, empty = pcall(function() return inv:isEmpty() end)
        if okEmpty and empty == true then return true end
    end
    if not inv.getItems then return false end

    local okItems, items = pcall(function() return inv:getItems() end)
    if not (okItems and items and items.size and items.get) then return false end
    local okSize, size = pcall(function() return items:size() end)
    size = okSize and (tonumber(size) or 0) or 0
    if size <= 0 then return true end

    for i = 0, size - 1 do
        local okGet, child = pcall(function() return items:get(i) end)
        if okGet and child then
            local childInv = nil
            if child.getInventory then
                local okChildInv, gotChildInv = pcall(function() return child:getInventory() end)
                if okChildInv then childInv = gotChildInv end
            end
            if childInv then
                if not bbmc_cacheInventoryEmpty(child, depth + 1) then return false end
            elseif bbmc_cacheItemStillUseful(child) then
                return false
            end
        end
    end
    return true
end

local function bbmc_cacheObjectMatches(item, md, args)
    if not item then return false end
    local id = tostring(args and (args.id or args.dropId) or "")
    if id ~= "" and type(md) == "table" and tostring(md.blackMarketDropId or "") == id then return true end
    local label = tostring(args and args.label or ""):lower()
    local name = tostring(bbmc_cacheItemName(item)):lower()
    if label ~= "" and name == label then return true end
    local dropType = tostring(args and args.dropType or "")
    if dropType == "ammo" and (name == "ammo cache" or name == "ammunition cache") then return true end
    return false
end

local bbmc_removeWorldInventoryObject

local function bbmc_forceRemoveCache(args)
    if type(args) ~= "table" or not getCell then return 0 end
    local cell = getCell()
    if not (cell and cell.getGridSquare) then return 0 end
    local x = math.floor((tonumber(args.x) or 0) + 0.5)
    local y = math.floor((tonumber(args.y) or 0) + 0.5)
    local z = math.floor(tonumber(args.z) or 0)
    local radius = 10
    local removed = 0
    for dx = -radius, radius do
        for dy = -radius, radius do
            local okSquare, square = pcall(function() return cell:getGridSquare(x + dx, y + dy, z) end)
            if okSquare and square and square.getWorldObjects then
                local okObjects, worldObjects = pcall(function() return square:getWorldObjects() end)
                if okObjects and worldObjects and worldObjects.size and worldObjects.get then
                    local okSize, size = pcall(function() return worldObjects:size() end)
                    size = okSize and (tonumber(size) or 0) or 0
                    for i = size - 1, 0, -1 do
                        local okObj, worldObject = pcall(function() return worldObjects:get(i) end)
                        if okObj and worldObject and worldObject.getItem then
                            local okItem, item = pcall(function() return worldObject:getItem() end)
                            if okItem and item then
                                local md = nil
                                if item.getModData then
                                    local okMd, gotMd = pcall(function() return item:getModData() end)
                                    if okMd and type(gotMd) == "table" then md = gotMd end
                                end
                                if bbmc_cacheObjectMatches(item, md, args) then
                                    if bbmc_removeWorldInventoryObject(square, worldObject) then removed = removed + 1 end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    local id = tostring(args.id or args.dropId or "")
    if id ~= "" then
        NPCBlackMarketClientBridge.dropMarkers[id] = nil
        if NPCDebugMapMarkersBridge and NPCDebugMapMarkersBridge.markers then NPCDebugMapMarkersBridge.markers[id] = nil end
        if NPCDebugMapNPCMarkersBridge and NPCDebugMapNPCMarkersBridge.markers then NPCDebugMapNPCMarkersBridge.markers[id] = nil end
    end
    return removed
end

bbmc_removeWorldInventoryObject = function(square, worldObject)
    if not (square and worldObject) then return false end
    local removed = false
    if square.transmitRemoveItemFromSquare then
        local ok = pcall(function() square:transmitRemoveItemFromSquare(worldObject) end)
        removed = removed or ok == true
    end
    if square.removeWorldObject then
        local ok = pcall(function() square:removeWorldObject(worldObject) end)
        removed = removed or ok == true
    end
    if worldObject.removeFromSquare then
        local ok = pcall(function() worldObject:removeFromSquare() end)
        removed = removed or ok == true
    end
    if worldObject.removeFromWorld then
        local ok = pcall(function() worldObject:removeFromWorld() end)
        removed = removed or ok == true
    end
    return removed
end

local function bbmc_reportEmptyCacheObject(player, square, worldObject, item, md)
    if not (player and square and worldObject and item and type(md) == "table") then return false end
    local dropType = tostring(md.blackMarketDropType or "")
    if not bbmc_isDirectCacheDropType(dropType) then return false end
    local dropId = tostring(md.blackMarketDropId or "")
    if dropId == "" then return false end
    if md.blackMarketDropContainer ~= true then return false end
    if not bbmc_cacheInventoryEmpty(item, 0) then return false end

    NPCBlackMarketClientBridge.emptyCacheReports = NPCBlackMarketClientBridge.emptyCacheReports or {}
    local now = bbmc_nowMs()
    local last = tonumber(NPCBlackMarketClientBridge.emptyCacheReports[dropId]) or 0
    if now - last < 3000 then return false end
    NPCBlackMarketClientBridge.emptyCacheReports[dropId] = now

    -- Remove locally for instant visual cleanup, then ask the server to mark the
    -- purchased cache as looted and remove the authoritative map marker/world item.
    bbmc_removeWorldInventoryObject(square, worldObject)
    sendClientCommand(player, 'NPCBlackMarket', 'DropEmptied', {id=dropId, dropType=dropType, clientEmpty=true})
    return true
end

local function bbmc_scanNearbyEmptyCaches(player)
    if not (player and player.getX and player.getY and getCell) then return 0 end
    local now = bbmc_nowMs()
    if NPCBlackMarketClientBridge.lastEmptyCacheScanMs and now - NPCBlackMarketClientBridge.lastEmptyCacheScanMs < 600 then return 0 end
    NPCBlackMarketClientBridge.lastEmptyCacheScanMs = now

    local cell = getCell()
    if not (cell and cell.getGridSquare) then return 0 end
    local px = math.floor((tonumber(player:getX()) or 0) + 0.5)
    local py = math.floor((tonumber(player:getY()) or 0) + 0.5)
    local pz = math.floor((player.getZ and tonumber(player:getZ()) or 0) or 0)
    local reported = 0
    for dx = -8, 8 do
        for dy = -8, 8 do
            local square = nil
            local okSquare, gotSquare = pcall(function() return cell:getGridSquare(px + dx, py + dy, pz) end)
            if okSquare then square = gotSquare end
            if square and square.getWorldObjects then
                local okObjects, worldObjects = pcall(function() return square:getWorldObjects() end)
                if okObjects and worldObjects and worldObjects.size and worldObjects.get then
                    local okSize, size = pcall(function() return worldObjects:size() end)
                    size = okSize and (tonumber(size) or 0) or 0
                    for i = size - 1, 0, -1 do
                        local okObj, worldObject = pcall(function() return worldObjects:get(i) end)
                        if okObj and worldObject and worldObject.getItem then
                            local okItem, item = pcall(function() return worldObject:getItem() end)
                            if okItem and item and item.getModData then
                                local okMd, md = pcall(function() return item:getModData() end)
                                if okMd and bbmc_reportEmptyCacheObject(player, square, worldObject, item, md) then
                                    reported = reported + 1
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return reported
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
    local maxDrawDist2 = maxDrawDist * maxDrawDist
    local px, py = player:getX(), player:getY()
    local wanted = {}

    bbmc_eachContact(function(contact, key)
        local x, y, z = tonumber(contact.x), tonumber(contact.y), tonumber(contact.z) or 0
        if not x or not y then return end
        local dx = x - px
        local dy = y - py
        if dx * dx + dy * dy > maxDrawDist2 then return end
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

local function bbmc_uiVisible(ui)
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
    return ui.visible == true and ui.javaObject ~= nil
end

local function bbmc_isWorldMapUI(ui)
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

local function bbmc_isWorldMapOpen()
    local direct = nil
    if type(_G) == "table" then direct = rawget(_G, "ISWorldMap_instance") or rawget(_G, "ISWorldMapInstance") end
    if direct and bbmc_isWorldMapUI(direct) and direct.javaObject and bbmc_uiVisible(direct) then return true end
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
                    if gOk and bbmc_isWorldMapUI(ui) and bbmc_uiVisible(ui) then return true end
                end
            elseif type(list) == "table" then
                for _, ui in pairs(list) do
                    if bbmc_isWorldMapUI(ui) and bbmc_uiVisible(ui) then return true end
                end
            end
        end
    end
    return false
end

local function bbmc_textManager()
    if getTextManager then
        local ok, tm = pcall(function() return getTextManager() end)
        if ok and tm then return tm end
    end
    if TextManager and TextManager.instance then return TextManager.instance end
    return nil
end

local function bbmc_drawTextCentre(ui, text, x, y, r, g, b, a, font)
    text = tostring(text or "")
    if text == "" then return false end
    x = tonumber(x) or 0
    y = tonumber(y) or 0
    r = tonumber(r) or 1.0
    g = tonumber(g) or 1.0
    b = tonumber(b) or 1.0
    a = tonumber(a) or 1.0
    font = font or UIFont.Small

    local tm = bbmc_textManager()
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

local function bbmc_drawZonePoint(ui, x, y, alpha, r, g, b)
    x = math.floor(tonumber(x) or 0)
    y = math.floor(tonumber(y) or 0)
    alpha = tonumber(alpha) or 0.60
    bbmc_drawTextCentre(ui, "•", x, y - 5, r or 0.70, g or 0.25, b or 1.0, alpha, UIFont.Small)
    return true
end

local function bbmc_zoneDrawProxy()
    local proxy = NPCBlackMarketClientBridge._fetchQuestZoneDrawProxy
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
        NPCBlackMarketClientBridge._fetchQuestZoneDrawProxy = proxy
    end
    return proxy
end

function NPCBlackMarketClientBridge.RenderFetchQuestZoneOverlay()
    if bbmc_isWorldMapOpen() then return end
    if not bbmc_bool("BlackMarket_Enabled", true) then return end

    local quest = NPCBlackMarketClientBridge.fetchQuest
    local defense = false
    if type(quest) ~= "table" or tostring(quest.status or "active") ~= "active" or quest.cacheEscaped == true or quest.guardsDematerialized == true then
        quest = NPCBlackMarketClientBridge.defenseQuest
        defense = true
    end
    if type(quest) ~= "table" or tostring(quest.status or "active") ~= "active" then return end

    local player = getPlayer() or getSpecificPlayer(0)
    if not (player and player.getX and player.getY) then return end
    local cx = defense and tonumber(quest.x) or tonumber(quest.originalCacheX or quest.x)
    local cy = defense and tonumber(quest.y) or tonumber(quest.originalCacheY or quest.y)
    local cz = defense and (tonumber(quest.z) or 0) or (tonumber(quest.originalCacheZ or quest.z) or 0)
    if not (cx and cy) then return end
    local radius = defense and bbmc_defenseQuestZoneRadius() or bbmc_fetchQuestZoneRadius()
    local pd = bbmc_dist(player:getX(), player:getY(), cx, cy)
    if pd > radius + 42 then return end

    local proxy = bbmc_zoneDrawProxy()
    if not proxy then return end
    local core = getCore and getCore() or nil
    local sw = core and core.getScreenWidth and core:getScreenWidth() or 1920
    local sh = core and core.getScreenHeight and core:getScreenHeight() or 1080
    local r, g, b = 0.70, 0.25, 1.0
    local alpha = NPCBlackMarketClientBridge.fetchQuestHasItem and 0.78 or 0.58
    if defense then
        r, g, b = 1.0, 0.16, 0.50
        alpha = 0.68
    end
    local lastX, lastY = nil, nil
    for i = 0, 40 do
        local a = (math.pi * 2) * (i / 40)
        local wx = cx + math.cos(a) * radius
        local wy = cy + math.sin(a) * radius
        local sx, sy = bbmc_worldToScreen(wx, wy, cz)
        if sx and sy then
            if lastX and lastY then
                local steps = math.max(1, math.floor(math.max(math.abs(sx - lastX), math.abs(sy - lastY)) / 5))
                for step = 0, steps do
                    local t = step / steps
                    local x = math.floor(lastX + (sx - lastX) * t)
                    local y = math.floor(lastY + (sy - lastY) * t)
                    if x > -16 and y > -16 and x < sw + 16 and y < sh + 16 then
                        bbmc_drawZonePoint(proxy, x, y, alpha, r, g, b)
                    end
                end
            end
            lastX, lastY = sx, sy
        end
    end
    local sx, sy = bbmc_worldToScreen(cx, cy, cz)
    if sx and sy then
        local label = NPCBlackMarketClientBridge.fetchQuestHasItem and "ESCAPE QUEST ZONE" or "BLACK MARKET QUEST ZONE"
        if defense then
            label = "DEFENSE ZONE"
            if tonumber(quest.currentWave or 0) and tonumber(quest.currentWave or 0) > 0 then
                label = label .. " W" .. tostring(quest.currentWave or 0) .. "/" .. tostring(quest.totalWaves or 3) .. " LEFT " .. tostring(quest.remaining or 0)
            end
        end
        bbmc_drawTextCentre(proxy, label, sx, sy - 70, r, g, b, 0.88, UIFont.Small)
    end
end

function NPCBlackMarketClientBridge.EnsureFetchQuestZoneOverlay()
    if NPCBlackMarketClientBridge._fetchQuestZoneOverlayHookInstalled then return end
    NPCBlackMarketClientBridge._fetchQuestZoneOverlayHookInstalled = true
    if Events and Events.OnPostUIDraw then
        Events.OnPostUIDraw.Add(NPCBlackMarketClientBridge.RenderFetchQuestZoneOverlay)
    elseif Events and Events.OnPreUIDraw then
        Events.OnPreUIDraw.Add(NPCBlackMarketClientBridge.RenderFetchQuestZoneOverlay)
    elseif Events and Events.OnRenderTick then
        Events.OnRenderTick.Add(NPCBlackMarketClientBridge.RenderFetchQuestZoneOverlay)
    else
        NPCBlackMarketClientBridge._fetchQuestZoneOverlayHookInstalled = false
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
        local reward = contact.blackMarketHasPendingReward == true or contact.blackMarketRewardHighlight == true
        local turnIn = contact.blackMarketQuestTurnInHighlight == true
        if reward or turnIn then
            local pad = math.max(4, math.floor(size * 0.12))
            if self.drawRectBorder then
                self:drawRectBorder(dx - pad - 1, dy - pad - 1, size + pad * 2 + 2, size + pad * 2 + 2, alpha * 0.92, 0, 0, 0)
                self:drawRectBorder(dx - pad, dy - pad, size + pad * 2, size + pad * 2, alpha * 0.96, 0.70, 0.25, 1.0)
                self:drawRectBorder(dx - pad + 2, dy - pad + 2, size + pad * 2 - 4, size + pad * 2 - 4, alpha * 0.72, 1.0, 0.20, 0.82)
            else
                self:drawRect(dx - pad - 1, dy - pad - 1, size + pad * 2 + 2, 2, alpha * 0.92, 0, 0, 0)
                self:drawRect(dx - pad - 1, dy + size + pad + 1, size + pad * 2 + 2, 2, alpha * 0.92, 0, 0, 0)
                self:drawRect(dx - pad - 1, dy - pad - 1, 2, size + pad * 2 + 2, alpha * 0.92, 0, 0, 0)
                self:drawRect(dx + size + pad + 1, dy - pad - 1, 2, size + pad * 2 + 2, alpha * 0.92, 0, 0, 0)
            end
        end
        if tex then
            self:drawTextureScaled(tex, dx, dy, size, size, alpha, 1, 1, 1)
        else
            self:drawRect(dx + 8, dy + 8, size - 16, size - 16, alpha, 0.10, 0.06, 0.12)
            self:drawTextCentre("BM", dx + size / 2, dy + size / 2 - 6, 0.95, 0.75, 1.0, alpha, UIFont.Small)
        end
        if reward then
            self:drawTextCentre("QUEST REWARD", dx + size / 2, dy - 24, 1.0, 0.82, 1.0, alpha, UIFont.Small)
        elseif turnIn then
            self:drawTextCentre("QUEST TURN-IN", dx + size / 2, dy - 24, 1.0, 0.82, 1.0, alpha, UIFont.Small)
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
    elseif command == "TakeClientPayment" and args then
        bbmc_takeClientPayment(args)
    elseif command == "ForceRemoveCache" and args then
        bbmc_forceRemoveCache(args)
    elseif command == "DropCreated" and args then
        local marker = type(args.marker) == "table" and args.marker or nil
        if marker and marker.id then
            NPCBlackMarketClientBridge.dropMarkers[tostring(marker.id)] = marker
            if NPCDebugMapMarkersBridge then
                NPCDebugMapMarkersBridge.markers = NPCDebugMapMarkersBridge.markers or {}
                NPCDebugMapMarkersBridge.markers[tostring(marker.id)] = marker
            end
            if NPCDebugMapNPCMarkersBridge and NPCDebugMapNPCMarkersBridge.Set then
                pcall(function() NPCDebugMapNPCMarkersBridge.Set(marker) end)
            end
            if NPCWorldMarkerClientBridge and NPCWorldMarkerClientBridge.Refresh then
                pcall(function() NPCWorldMarkerClientBridge.Refresh(true) end)
            end
        end
    elseif command == "DropRemoved" and args then
        local id = tostring(args.id or args.dropId or "")
        if id ~= "" then
            NPCBlackMarketClientBridge.dropMarkers[id] = nil
            if NPCDebugMapMarkersBridge and NPCDebugMapMarkersBridge.markers then NPCDebugMapMarkersBridge.markers[id] = nil end
            if NPCDebugMapNPCMarkersBridge and NPCDebugMapNPCMarkersBridge.Remove then pcall(function() NPCDebugMapNPCMarkersBridge.Remove(id) end) end
            if NPCWorldMarkerClientBridge and NPCWorldMarkerClientBridge.Refresh then pcall(function() NPCWorldMarkerClientBridge.Refresh(true) end) end
        end
    elseif command == "FetchQuestState" and args then
        local previousQuestId = nil
        local previousTurnInId = nil
        if type(NPCBlackMarketClientBridge.fetchQuest) == "table" and NPCBlackMarketClientBridge.fetchQuest.id then
            previousQuestId = tostring(NPCBlackMarketClientBridge.fetchQuest.id)
            previousTurnInId = previousQuestId .. "_turnin"
        end
        NPCBlackMarketClientBridge.fetchQuest = type(args.quest) == "table" and args.quest or nil
        NPCBlackMarketClientBridge.fetchQuestHasItem = args.hasItem == true
        if NPCBlackMarketClientBridge.fetchQuest and (args.hasItem == true or NPCBlackMarketClientBridge.fetchQuest.carried == true or NPCBlackMarketClientBridge.fetchQuest.markerHidden == true) then
            bbmc_clearFetchQuestWorldMarker(NPCBlackMarketClientBridge.fetchQuest.id)
        end
        if not NPCBlackMarketClientBridge.fetchQuest then
            if previousQuestId then bbmc_clearFetchQuestWorldMarker(previousQuestId) end
            if previousTurnInId then
                if NPCDebugMapNPCMarkersBridge and NPCDebugMapNPCMarkersBridge.Remove then pcall(function() NPCDebugMapNPCMarkersBridge.Remove(previousTurnInId) end) end
                if NPCDebugMapMarkersBridge and NPCDebugMapMarkersBridge.markers then NPCDebugMapMarkersBridge.markers[previousTurnInId] = nil end
            end
        end
    elseif command == "DefenseQuestState" and args then
        local previousQuestId = nil
        if type(NPCBlackMarketClientBridge.defenseQuest) == "table" and NPCBlackMarketClientBridge.defenseQuest.id then
            previousQuestId = tostring(NPCBlackMarketClientBridge.defenseQuest.id)
        end
        NPCBlackMarketClientBridge.defenseQuest = type(args.quest) == "table" and args.quest or nil
        if not NPCBlackMarketClientBridge.defenseQuest and previousQuestId then bbmc_clearFetchQuestWorldMarker(previousQuestId) end
        if args.message then
            if args.completed == true then
                bbmc_halo(tostring(args.message), 120, 255, 120)
            elseif args.cancelled == true then
                bbmc_halo(tostring(args.message), 255, 120, 90)
            else
                bbmc_halo(tostring(args.message), 255, 90, 180)
            end
        end
    elseif command == "LeaderIntel" and args then
        local marker = type(args.marker) == "table" and args.marker or nil
        if marker and marker.id then
            if NPCDebugMapNPCMarkersBridge and NPCDebugMapNPCMarkersBridge.Set then
                pcall(function() NPCDebugMapNPCMarkersBridge.Set(marker) end)
            elseif NPCDebugMapNPCMarkersBridge then
                NPCDebugMapNPCMarkersBridge.markers = NPCDebugMapNPCMarkersBridge.markers or {}
                NPCDebugMapNPCMarkersBridge.markers[tostring(marker.id)] = marker
            end
            if NPCDebugMapMarkersBridge then
                NPCDebugMapMarkersBridge.markers = NPCDebugMapMarkersBridge.markers or {}
                NPCDebugMapMarkersBridge.markers[tostring(marker.id)] = marker
            end
            bbmc_halo("Leader intel marker added to the global map.", 255, 230, 80)
        end
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

local function bbmc_findFetchQuestWorldItem(player)
    if not (player and player.getX and player.getY and getCell and bbmc_fetchQuestActive()) then return nil end
    local questId = bbmc_fetchQuestId()
    if questId == "" then return nil end
    local cell = getCell()
    if not (cell and cell.getGridSquare) then return nil end
    local px = math.floor((tonumber(player:getX()) or 0) + 0.5)
    local py = math.floor((tonumber(player:getY()) or 0) + 0.5)
    local pz = math.floor((player.getZ and tonumber(player:getZ()) or 0) or 0)
    for dx = -10, 10 do
        for dy = -10, 10 do
            local okSquare, square = pcall(function() return cell:getGridSquare(px + dx, py + dy, pz) end)
            if okSquare and square and square.getWorldObjects then
                local okObjects, worldObjects = pcall(function() return square:getWorldObjects() end)
                if okObjects and worldObjects and worldObjects.size and worldObjects.get then
                    local okSize, size = pcall(function() return worldObjects:size() end)
                    size = okSize and (tonumber(size) or 0) or 0
                    for i = 0, size - 1 do
                        local okObj, worldObject = pcall(function() return worldObjects:get(i) end)
                        if okObj and worldObject and worldObject.getItem then
                            local okItem, item = pcall(function() return worldObject:getItem() end)
                            if okItem and item then
                                if bbmc_fetchQuestItemMatches(item, questId) then return square end
                                local child = nil
                                if item.getInventory then
                                    local okChild, gotChild = pcall(function() return item:getInventory() end)
                                    if okChild then child = gotChild end
                                end
                                if child and bbmc_findFetchQuestItemInContainer(child, questId, 0, {}) then return square end
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function bbmc_reportFetchQuestState(player, now)
    if not (player and bbmc_fetchQuestActive()) then return end
    now = tonumber(now) or bbmc_nowMs()
    if NPCBlackMarketClientBridge.lastFetchQuestReportMs and now - NPCBlackMarketClientBridge.lastFetchQuestReportMs < 1600 then return end
    NPCBlackMarketClientBridge.lastFetchQuestReportMs = now

    local questId = bbmc_fetchQuestId()
    if bbmc_playerHasFetchQuestItem(player) then
        NPCBlackMarketClientBridge.fetchQuestHasItem = true
        bbmc_clearFetchQuestWorldMarker(questId)
        local quest = NPCBlackMarketClientBridge.fetchQuest
        local cx = type(quest) == "table" and tonumber(quest.originalCacheX or quest.x) or nil
        local cy = type(quest) == "table" and tonumber(quest.originalCacheY or quest.y) or nil
        local radius = bbmc_fetchQuestZoneRadius()
        if type(quest) == "table" and quest.cacheEscaped ~= true and cx and cy and player.getX and player.getY then
            local dx = (tonumber(player:getX()) or 0) - cx
            local dy = (tonumber(player:getY()) or 0) - cy
            if (dx * dx + dy * dy) > (radius * radius) then
                if NPCBlackMarketClientBridge.lastFetchQuestReportState ~= "escaped" or not NPCBlackMarketClientBridge.lastFetchQuestReportAtMs or now - NPCBlackMarketClientBridge.lastFetchQuestReportAtMs > 5000 then
                    NPCBlackMarketClientBridge.lastFetchQuestReportState = "escaped"
                    NPCBlackMarketClientBridge.lastFetchQuestReportAtMs = now
                    sendClientCommand(player, 'NPCBlackMarket', 'FetchQuest', {action="track", questId=questId, state="escaped", x=player:getX(), y=player:getY(), z=(player.getZ and player:getZ() or 0)})
                end
                return
            end
        end
        if NPCBlackMarketClientBridge.lastFetchQuestReportState ~= "carried" or not NPCBlackMarketClientBridge.lastFetchQuestReportAtMs or now - NPCBlackMarketClientBridge.lastFetchQuestReportAtMs > 5000 then
            NPCBlackMarketClientBridge.lastFetchQuestReportState = "carried"
            NPCBlackMarketClientBridge.lastFetchQuestReportAtMs = now
            sendClientCommand(player, 'NPCBlackMarket', 'FetchQuest', {action="track", questId=questId, state="carried"})
        end
        return
    end

    NPCBlackMarketClientBridge.fetchQuestHasItem = false
    local square = bbmc_findFetchQuestWorldItem(player)
    if square and square.getX and square.getY then
        local x, y, z = square:getX(), square:getY(), square.getZ and square:getZ() or 0
        local key = tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)
        if NPCBlackMarketClientBridge.lastFetchQuestReportState ~= key or not NPCBlackMarketClientBridge.lastFetchQuestReportAtMs or now - NPCBlackMarketClientBridge.lastFetchQuestReportAtMs > 5000 then
            NPCBlackMarketClientBridge.lastFetchQuestReportState = key
            NPCBlackMarketClientBridge.lastFetchQuestReportAtMs = now
            sendClientCommand(player, 'NPCBlackMarket', 'FetchQuest', {action="track", questId=questId, state="world", x=x, y=y, z=z})
        end
    end
end

local function bbmc_reportDefenseQuestState(player, now)
    if not (player and player.getX and player.getY and bbmc_defenseQuestActive()) then return end
    now = tonumber(now) or bbmc_nowMs()
    if NPCBlackMarketClientBridge.lastDefenseQuestReportMs and now - NPCBlackMarketClientBridge.lastDefenseQuestReportMs < 1200 then return end
    NPCBlackMarketClientBridge.lastDefenseQuestReportMs = now
    local quest = NPCBlackMarketClientBridge.defenseQuest
    if type(quest) ~= "table" then return end
    local stage = tostring(quest.stage or "travel")
    if stage ~= "travel" then return end
    local radius = bbmc_defenseQuestZoneRadius()
    local dx = (tonumber(player:getX()) or 0) - (tonumber(quest.x) or 0)
    local dy = (tonumber(player:getY()) or 0) - (tonumber(quest.y) or 0)
    if (dx * dx + dy * dy) <= radius * radius then
        if NPCBlackMarketClientBridge.lastDefenseQuestReportState ~= "entered" or not NPCBlackMarketClientBridge.lastDefenseQuestReportAtMs or now - NPCBlackMarketClientBridge.lastDefenseQuestReportAtMs > 4000 then
            NPCBlackMarketClientBridge.lastDefenseQuestReportState = "entered"
            NPCBlackMarketClientBridge.lastDefenseQuestReportAtMs = now
            sendClientCommand(player, 'NPCBlackMarket', 'DefenseQuest', {action="track", questId=bbmc_defenseQuestId(), state="entered", x=player:getX(), y=player:getY(), z=(player.getZ and player:getZ() or 0)})
        end
    end
end

local bbmc_resetOverlay

local function bbmc_onCreatePlayer()
    if bbmc_resetOverlay then bbmc_resetOverlay() end
    local player = getPlayer() or getSpecificPlayer(0)
    if player then
        NPCBlackMarketClientBridge.Refresh(player)
        sendClientCommand(player, 'NPCBlackMarket', 'DefenseQuest', {action="status"})
    end
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

local function bbmc_onPlayerDeath(player)
    if type(player) == "number" then player = getSpecificPlayer(player) end
    player = player or getPlayer() or getSpecificPlayer(0)
    if player then
        sendClientCommand(player, 'NPCBlackMarket', 'FetchQuest', {action="death", state="dead", questId=bbmc_fetchQuestId()})
        sendClientCommand(player, 'NPCBlackMarket', 'DefenseQuest', {action="death", state="dead", questId=bbmc_defenseQuestId()})
    end
    NPCBlackMarketClientBridge.fetchQuest = nil
    NPCBlackMarketClientBridge.fetchQuestHasItem = false
    NPCBlackMarketClientBridge.defenseQuest = nil
    NPCBlackMarketClientBridge.lastFetchQuestReportState = nil
    NPCBlackMarketClientBridge.lastFetchQuestReportAtMs = nil
    NPCBlackMarketClientBridge.lastDefenseQuestReportState = nil
    NPCBlackMarketClientBridge.lastDefenseQuestReportAtMs = nil
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
    local tickPlayer = getPlayer() or getSpecificPlayer(0)
    if tickPlayer then bbmc_scanNearbyEmptyCaches(tickPlayer) end
    if NPCBlackMarketClientBridge.lastAccessCheckMs and now - NPCBlackMarketClientBridge.lastAccessCheckMs < 1000 then return end
    NPCBlackMarketClientBridge.lastAccessCheckMs = now

    local player = getPlayer() or getSpecificPlayer(0)
    if not player then return end
    bbmc_reportFetchQuestState(player, now)
    bbmc_reportDefenseQuestState(player, now)
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
    NPCBlackMarketClientBridge.EnsureFetchQuestZoneOverlay()
    NPCBlackMarketClientBridge.SyncWorldProps(true)
end)
if Events.OnRightMouseDown then Events.OnRightMouseDown.Add(bbmc_onRightMouseDown) end
if Events.OnRightMouseUp then Events.OnRightMouseUp.Add(bbmc_onRightMouseUp) end
if Events.OnPlayerDeath then Events.OnPlayerDeath.Add(bbmc_onPlayerDeath) end
if Events.OnSave then Events.OnSave.Add(NPCBlackMarketClientBridge.CleanupWorldProps) end
if Events.OnDisconnect then Events.OnDisconnect.Add(NPCBlackMarketClientBridge.CleanupWorldProps) end
NPCBlackMarketClientBridge.EnsureFetchQuestZoneOverlay()
if Events.OnTick then Events.OnTick.Add(bbmc_onTick) end
