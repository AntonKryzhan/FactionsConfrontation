-- NPCBlackMarketBridge.lua
-- Neutral shared backend for black market contacts and services.
-- Contacts are virtual map records: they do not add physical NPCs or items by themselves.

NPCBlackMarketBridge = NPCBlackMarketBridge or {}
NPCBlackMarketBridge.Version = 2

local BBM_SIDES = {"red", "green", "blue"}

local BBM_SPRITES = {
    "media/ui/black_market_service.png",
    "media/ui/black_market_service_2.png",
    "media/ui/black_market_service_3.png",
    "media/ui/black_market_service_4.png",
    "media/ui/black_market_service_5.png",
    "media/ui/black_market_service_6.png",
    "media/ui/black_market_service_7.png",
    "media/ui/black_market_service_8.png",
    "media/ui/black_market_service_9.png",
    "media/ui/black_market_service_10.png"
}

local BBM_RESOURCES = {
    gold = {label="gold jewelry", items={
        "Base.Ring_Right_MiddleFinger_Gold", "Base.Ring_Left_MiddleFinger_Gold",
        "Base.Ring_Right_RingFinger_Gold", "Base.Ring_Left_RingFinger_Gold",
        "Base.Ring_Right_MiddleFinger_GoldDiamond", "Base.Ring_Left_MiddleFinger_GoldDiamond",
        "Base.Ring_Right_RingFinger_GoldDiamond", "Base.Ring_Left_RingFinger_GoldDiamond",
        "Base.Necklace_Gold", "Base.Necklace_GoldRuby", "Base.Necklace_GoldDiamond",
        "Base.NecklaceLong_GoldDiamond", "Base.Bracelet_ChainRightGold", "Base.Bracelet_ChainLeftGold",
        "Base.Bracelet_BangleRightGold", "Base.Bracelet_BangleLeftGold",
        "Base.Earring_LoopLrg_Gold", "Base.Earring_LoopMed_Gold", "Base.Earring_LoopSmall_Gold",
        "Base.WristWatch_Left_ClassicGold", "Base.WristWatch_Right_ClassicGold"
    }},
    silver = {label="silver jewelry", items={
        "Base.Ring_Right_MiddleFinger_Silver", "Base.Ring_Left_MiddleFinger_Silver",
        "Base.Ring_Right_RingFinger_Silver", "Base.Ring_Left_RingFinger_Silver",
        "Base.Necklace_Silver", "Base.Necklace_SilverSapphire", "Base.Necklace_SilverCrucifix",
        "Base.Bracelet_ChainRightSilver", "Base.Bracelet_ChainLeftSilver",
        "Base.Bracelet_BangleRightSilver", "Base.Bracelet_BangleLeftSilver",
        "Base.Earring_LoopLrg_Silver", "Base.Earring_LoopMed_Silver", "Base.Earring_LoopSmall_Silver",
        "Base.WristWatch_Left_ClassicSilver", "Base.WristWatch_Right_ClassicSilver"
    }},
    ammo9 = {label="9mm rounds", items={"Base.9mmBullets"}},
    ammo556 = {label="5.56 rounds", items={"Base.556Bullets"}},
    medical = {label="medical supplies", items={"Base.FirstAidKit", "Base.Bandage", "Base.AlcoholBandage", "Base.Disinfectant"}},
    fuel = {label="fuel can", items={"Base.PetrolCan"}}
}

local BBM_DEALS = {
    forged_papers = {label="forged papers", resource="silver", setting="BlackMarket_ForgedPapersCost", default=4, docType="forged_papers"},
    stolen_badge = {label="stolen badge", resource="gold", setting="BlackMarket_StolenBadgeCost", default=2, docType="stolen_badge"},
    password = {label="daily password", resource="silver", setting="BlackMarket_PasswordCost", default=3},
    bounty_payoff = {label="bounty payoff", resource="gold", setting="BlackMarket_BountyPayoffCost", default=3},
    leader_tip = {label="leader rumor", resource="silver", setting="BlackMarket_LeaderTipCost", default=2}
}

local function bbm_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        local ok, value = pcall(function() return NPCLegacySettingsBridge.GetBool(name, defaultValue == true) end)
        if ok and value ~= nil then return value == true end
    end
    return defaultValue == true
end

local function bbm_num(name, defaultValue, minValue, maxValue)
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

local function bbm_now()
    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then
            local ok, value = pcall(function() return gt:getWorldAgeHours() end)
            if ok and value then return tonumber(value) or 0 end
        end
    end
    return os.time and (os.time() / 3600) or 0
end

local function bbm_rand(maxValue)
    maxValue = math.floor(tonumber(maxValue) or 0)
    if maxValue <= 0 then return 0 end
    if ZombRand then
        local ok, value = pcall(function() return ZombRand(maxValue) end)
        if ok and value ~= nil then return tonumber(value) or 0 end
    end
    return math.random(0, maxValue - 1)
end

local function bbm_dist(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return math.sqrt(dx * dx + dy * dy)
end

local function bbm_side(side)
    if NPCFactionBridge and NPCFactionBridge.NormalizeSide then
        local s = NPCFactionBridge.NormalizeSide(side)
        if s == "red" or s == "green" or s == "blue" then return s end
    end
    side = tostring(side or ""):lower()
    if side == "red" or side == "green" or side == "blue" then return side end
    return nil
end

local function bbm_sideLabel(side)
    if NPCFactionBridge and NPCFactionBridge.GetSideLabel then
        local ok, label = pcall(function() return NPCFactionBridge.GetSideLabel(side) end)
        if ok and label then return tostring(label) end
    end
    return tostring(side or "faction")
end

local function bbm_playerId(player)
    if not player then return nil end
    if NPCUtils and NPCUtils.GetCharacterID then
        local ok, id = pcall(function() return NPCUtils.GetCharacterID(player) end)
        if ok and id ~= nil then return id end
    end
    if player.getOnlineID then
        local ok, id = pcall(function() return player:getOnlineID() end)
        if ok and id ~= nil then return id end
    end
    if player.getUsername then
        local ok, name = pcall(function() return player:getUsername() end)
        if ok and name then return tostring(name) end
    end
    return nil
end

function NPCBlackMarketBridge.IsEnabled()
    return bbm_bool("BlackMarket_Enabled", true)
end

function NPCBlackMarketBridge.InteractionRadius()
    return bbm_num("BlackMarket_InteractionRadius", 28, 4, 120)
end

function NPCBlackMarketBridge.MaxContacts()
    return math.floor(bbm_num("BlackMarket_MaxContacts", 10, 0, 80))
end

function NPCBlackMarketBridge.MinContactDistance()
    return bbm_num("BlackMarket_MinContactDistance", 650, 80, 5000)
end

function NPCBlackMarketBridge.SpawnOffsetRadius()
    return bbm_num("BlackMarket_SpawnOffsetRadius", 420, 40, 1800)
end

function NPCBlackMarketBridge.ContactRoamRadius()
    return bbm_num("BlackMarket_VirtualHomeRadius", 900, 80, 3000)
end

function NPCBlackMarketBridge.ContactHours()
    return bbm_num("BlackMarket_ContactHours", 36, 1, 240)
end

function NPCBlackMarketBridge.BountyReduction()
    return bbm_num("BlackMarket_BountyReduction", 35, 1, 999)
end


function NPCBlackMarketBridge.ServiceSide()
    return "black_market"
end

function NPCBlackMarketBridge.ServiceState()
    return "black_market_static"
end

function NPCBlackMarketBridge.SpriteVariants()
    return BBM_SPRITES
end

function NPCBlackMarketBridge.SpritePath()
    return BBM_SPRITES[1]
end

function NPCBlackMarketBridge.SpritePathForContact(contact, side)
    if type(contact) == "table" and type(contact.blackMarketSprite) == "string" and contact.blackMarketSprite ~= "" then
        return contact.blackMarketSprite
    end
    local key = nil
    if type(contact) == "table" then
        key = contact.blackMarketId or contact.id or contact.blackMarketSourceId
        side = side or contact.blackMarketSide or contact.sourceSide
    else
        key = contact
    end
    if type(BBM_SPRITES) ~= "table" or #BBM_SPRITES <= 0 then
        return "media/ui/black_market_service.png"
    end
    local hash = 0
    local source = tostring(key or side or "black_market")
    for i = 1, #source do
        hash = (hash + string.byte(source, i) * i) % 2147483647
    end
    local index = (hash % #BBM_SPRITES) + 1
    return BBM_SPRITES[index] or BBM_SPRITES[1]
end

local function bbm_refillSpriteBag(data)
    if type(data) ~= "table" then return end
    data.spriteBag = {}
    for i = 1, #BBM_SPRITES do data.spriteBag[i] = i end
    for i = #data.spriteBag, 2, -1 do
        local j = 1 + bbm_rand(i)
        data.spriteBag[i], data.spriteBag[j] = data.spriteBag[j], data.spriteBag[i]
    end
end

function NPCBlackMarketBridge.NextSpritePath(data, contactId, side, sourceId)
    if type(data) ~= "table" then return NPCBlackMarketBridge.SpritePathForContact(contactId, side) end
    if type(data.spriteBag) ~= "table" or #data.spriteBag <= 0 then
        bbm_refillSpriteBag(data)
    end
    local index = table.remove(data.spriteBag, 1)
    return BBM_SPRITES[index] or NPCBlackMarketBridge.SpritePathForContact(contactId or sourceId, side)
end

function NPCBlackMarketBridge.StaticClickRadius()
    return bbm_num("BlackMarket_StaticClickRadius", 4, 1, 12)
end

function NPCBlackMarketBridge.StaticPlayerRadius()
    return bbm_num("BlackMarket_StaticPlayerRadius", 8, 2, 24)
end

function NPCBlackMarketBridge.IsStaticServiceObject()
    return true
end

function NPCBlackMarketBridge.DealCost(action)
    local deal = BBM_DEALS[tostring(action or "")]
    if not deal then return nil end
    local amount = bbm_num(deal.setting, deal.default, 0, 999)
    return deal.resource, math.floor(amount), deal.label
end

function NPCBlackMarketBridge.EnsureData(gmd)
    if not gmd then return nil end
    gmd.BlackMarket = gmd.BlackMarket or {}
    gmd.BlackMarket.contacts = gmd.BlackMarket.contacts or {}
    gmd.BlackMarket.history = gmd.BlackMarket.history or {}
    gmd.BlackMarket.playerDeals = gmd.BlackMarket.playerDeals or {}
    gmd.BlackMarket.stats = gmd.BlackMarket.stats or {contacts=0, trades=0, denied=0, payoffs=0, tips=0}
    gmd.BlackMarket.spriteBag = gmd.BlackMarket.spriteBag or {}
    gmd.BlackMarket.nextId = tonumber(gmd.BlackMarket.nextId) or 1
    if not gmd.DebugMapMarkers then gmd.DebugMapMarkers = {} end
    return gmd.BlackMarket
end

function NPCBlackMarketBridge.CountItems(player, resourceKey)
    local res = BBM_RESOURCES[tostring(resourceKey or "")]
    if not (player and res and type(res.items) == "table" and player.getInventory) then return 0 end
    local inv = player:getInventory()
    if not inv or not inv.getItemCountFromTypeRecurse then return 0 end
    local total = 0
    for _, itemType in ipairs(res.items) do
        local ok, count = pcall(function() return inv:getItemCountFromTypeRecurse(itemType) end)
        if ok then total = total + (tonumber(count) or 0) end
    end
    return total
end

local function bbm_removeOne(inv, itemType)
    if not (inv and itemType and inv.getItemCountFromTypeRecurse and inv.RemoveOneOf) then return false end
    local before = tonumber(inv:getItemCountFromTypeRecurse(itemType)) or 0
    if before <= 0 then return false end
    local ok = pcall(function() inv:RemoveOneOf(itemType, true) end)
    if ok and (tonumber(inv:getItemCountFromTypeRecurse(itemType)) or 0) < before then return true end
    before = tonumber(inv:getItemCountFromTypeRecurse(itemType)) or 0
    ok = pcall(function() inv:RemoveOneOf(itemType, false) end)
    return ok and (tonumber(inv:getItemCountFromTypeRecurse(itemType)) or 0) < before
end

function NPCBlackMarketBridge.TakeItems(player, resourceKey, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    local res = BBM_RESOURCES[tostring(resourceKey or "")]
    if not (player and res and type(res.items) == "table" and player.getInventory) then return false end
    if NPCBlackMarketBridge.CountItems(player, resourceKey) < amount then return false end
    local inv = player:getInventory()
    if not inv then return false end
    local removed = 0
    while removed < amount do
        local did = false
        for _, itemType in ipairs(res.items) do
            if removed >= amount then break end
            if bbm_removeOne(inv, itemType) then
                removed = removed + 1
                did = true
            end
        end
        if not did then return false end
    end
    return true
end

function NPCBlackMarketBridge.PriceText(action)
    local resource, amount, label = NPCBlackMarketBridge.DealCost(action)
    local res = BBM_RESOURCES[resource]
    if not resource then return "unknown price" end
    return tostring(amount or 0) .. " " .. tostring(res and res.label or resource)
end

local function bbm_contactId(data)
    local id = "black_market_" .. tostring(data.nextId or 1)
    data.nextId = (tonumber(data.nextId) or 1) + 1
    return id
end

function NPCBlackMarketBridge.MakeContact(gmd, x, y, z, side, sourceId, sourceType)
    local data = NPCBlackMarketBridge.EnsureData(gmd)
    if not data then return nil end
    side = bbm_side(side) or BBM_SIDES[1 + bbm_rand(#BBM_SIDES)]
    local id = bbm_contactId(data)
    local contact = {
        id = id,
        markerType = "black_market",
        blackMarket = true,
        blackMarketId = id,
        blackMarketSide = side,
        sourceSide = side,
        blackMarketStatus = "active",
        blackMarketSourceId = sourceId,
        blackMarketSourceType = sourceType or "unknown",
        blackMarketServices = "docs/passwords/bounty/tips",
        blackMarketStaticObject = true,
        blackMarketSprite = NPCBlackMarketBridge.NextSpritePath(data, id, side, sourceId),
        blackMarketVirtualObject = true,
        blackMarketVirtual = true,
        blackMarketMaterialized = false,
        blackMarketHomeX = math.floor(tonumber(x) or 0),
        blackMarketHomeY = math.floor(tonumber(y) or 0),
        blackMarketHomeZ = tonumber(z) or 0,
        blackMarketHomeRadius = NPCBlackMarketBridge.ContactRoamRadius(),
        name = "Black market service object",
        side = NPCBlackMarketBridge.ServiceSide(),
        factionSide = NPCBlackMarketBridge.ServiceSide(),
        x = math.floor(tonumber(x) or 0),
        y = math.floor(tonumber(y) or 0),
        z = tonumber(z) or 0,
        createdAt = bbm_now(),
        updatedAt = bbm_now(),
        expiresAt = bbm_now() + NPCBlackMarketBridge.ContactHours()
    }
    data.contacts[id] = contact
    data.stats.contacts = (tonumber(data.stats.contacts) or 0) + 1
    return contact
end

function NPCBlackMarketBridge.MarkerFields(marker, contact)
    if not (marker and contact) then return marker end
    marker.markerType = "black_market"
    marker.blackMarket = true
    marker.blackMarketId = contact.blackMarketId or contact.id
    marker.blackMarketSide = contact.blackMarketSide or contact.side
    marker.blackMarketStatus = contact.blackMarketStatus or contact.state
    marker.blackMarketServices = contact.blackMarketServices
    marker.blackMarketStaticObject = true
    marker.blackMarketSprite = contact.blackMarketSprite or NPCBlackMarketBridge.SpritePathForContact(contact)
    marker.sourceSide = contact.blackMarketSide or contact.sourceSide
    marker.blackMarketSourceId = contact.blackMarketSourceId
    marker.blackMarketSourceType = contact.blackMarketSourceType
    marker.blackMarketVirtualObject = true
    marker.blackMarketVirtual = contact.blackMarketVirtual == true
    marker.blackMarketMaterialized = contact.blackMarketMaterialized == true
    return marker
end

function NPCBlackMarketBridge.MakeMarker(contact)
    if not contact then return nil end
    local marker = {
        id = contact.id,
        markerType = "black_market",
        blackMarket = true,
        name = contact.name or "Black market contact",
        x = contact.x,
        y = contact.y,
        z = contact.z or 0,
        side = NPCBlackMarketBridge.ServiceSide(),
        factionSide = NPCBlackMarketBridge.ServiceSide(),
        sourceSide = contact.blackMarketSide or contact.sourceSide,
        blackMarketStaticObject = true,
        blackMarketSprite = contact.blackMarketSprite or NPCBlackMarketBridge.SpritePathForContact(contact),
        updatedAt = contact.updatedAt or bbm_now()
    }
    NPCBlackMarketBridge.MarkerFields(marker, contact)
    return marker
end

function NPCBlackMarketBridge.Cleanup(gmd)
    local data = NPCBlackMarketBridge.EnsureData(gmd)
    if not data or type(data.contacts) ~= "table" then return 0 end
    local now = bbm_now()
    local removed = 0
    for id, contact in pairs(data.contacts) do
        if type(contact) ~= "table" or (contact.expiresAt and now >= tonumber(contact.expiresAt)) or contact.blackMarketStatus == "closed" then
            data.contacts[id] = nil
            if gmd.DebugMapMarkers then gmd.DebugMapMarkers[id] = nil end
            removed = removed + 1
        end
    end
    return removed
end

local function bbm_contactCount(data)
    local n = 0
    if type(data and data.contacts) ~= "table" then return 0 end
    local now = bbm_now()
    for _, contact in pairs(data.contacts) do
        if type(contact) == "table" and (not contact.expiresAt or now < tonumber(contact.expiresAt)) then n = n + 1 end
    end
    return n
end

function NPCBlackMarketBridge.ContactSourceExists(data, sourceId, sourceType)
    if not (data and sourceId and type(data.contacts) == "table") then return false end
    local sid = tostring(sourceId)
    local stype = tostring(sourceType or "")
    for _, contact in pairs(data.contacts) do
        if type(contact) == "table" and contact.blackMarketStatus ~= "closed" then
            if tostring(contact.blackMarketSourceId or "") == sid and tostring(contact.blackMarketSourceType or "") == stype then
                return true
            end
        end
    end
    return false
end

function NPCBlackMarketBridge.ContactTooClose(data, x, y, minDistance)
    if not (data and type(data.contacts) == "table" and x and y) then return false end
    minDistance = tonumber(minDistance) or NPCBlackMarketBridge.MinContactDistance()
    for _, contact in pairs(data.contacts) do
        if type(contact) == "table" and contact.blackMarketStatus ~= "closed" and contact.x and contact.y then
            if bbm_dist(contact.x, contact.y, x, y) < minDistance then return true end
        end
    end
    return false
end

local function bbm_shuffleCandidates(candidates)
    for i = #candidates, 2, -1 do
        local j = 1 + bbm_rand(i)
        candidates[i], candidates[j] = candidates[j], candidates[i]
    end
end

local function bbm_pickContactPoint(candidate, data)
    if not candidate then return nil end
    local cx = tonumber(candidate.x) or 0
    local cy = tonumber(candidate.y) or 0
    local cz = tonumber(candidate.z) or 0
    local radius = NPCBlackMarketBridge.SpawnOffsetRadius()
    local minDistance = NPCBlackMarketBridge.MinContactDistance()

    for attempt = 1, 10 do
        local point = nil
        if NPCRoadNavBridge and NPCRoadNavBridge.FindNearbyWorldRoadPoint then
            local ok, got = pcall(function() return NPCRoadNavBridge.FindNearbyWorldRoadPoint(cx, cy, radius, 120) end)
            if ok and got and got.x and got.y then point = got end
        end
        if not point then
            local ox = bbm_rand(radius * 2 + 1) - radius
            local oy = bbm_rand(radius * 2 + 1) - radius
            point = {x=cx + ox, y=cy + oy, z=cz}
        end
        if point and point.x and point.y and not NPCBlackMarketBridge.ContactTooClose(data, point.x, point.y, minDistance) then
            return math.floor(tonumber(point.x) or cx), math.floor(tonumber(point.y) or cy), tonumber(point.z) or cz
        end
    end

    if not NPCBlackMarketBridge.ContactTooClose(data, cx, cy, minDistance) then
        return math.floor(cx), math.floor(cy), cz
    end
    return nil
end

local function bbm_findContactSource(gmd, contact)
    if not (gmd and contact) then return contact end
    local sourceId = contact.blackMarketSourceId
    local sourceType = tostring(contact.blackMarketSourceType or "")
    if sourceType == "base" and sourceId and type(gmd.BaseCamps) == "table" then
        local base = gmd.BaseCamps[tostring(sourceId)] or gmd.BaseCamps[sourceId]
        if type(base) == "table" and base.x and base.y then
            return {x=base.x, y=base.y, z=base.z or 0, side=contact.blackMarketSide or contact.sourceSide, sourceId=sourceId, sourceType=sourceType}
        end
    elseif sourceType == "leader" and sourceId and type(gmd.NPCLeadersBridge) == "table" and type(gmd.NPCLeadersBridge.leaders) == "table" then
        local leader = gmd.NPCLeadersBridge.leaders[tostring(sourceId)] or gmd.NPCLeadersBridge.leaders[sourceId]
        if type(leader) == "table" and leader.x and leader.y then
            return {x=leader.x, y=leader.y, z=leader.z or 0, side=contact.blackMarketSide or contact.sourceSide, sourceId=sourceId, sourceType=sourceType}
        end
    end
    return {x=contact.blackMarketHomeX or contact.x, y=contact.blackMarketHomeY or contact.y, z=contact.blackMarketHomeZ or contact.z or 0, side=contact.blackMarketSide or contact.sourceSide, sourceId=sourceId, sourceType=sourceType}
end

function NPCBlackMarketBridge.RebalanceContacts(gmd, maxMoves)
    local data = NPCBlackMarketBridge.EnsureData(gmd)
    if not (data and type(data.contacts) == "table") then return 0 end
    maxMoves = math.floor(tonumber(maxMoves) or 2)
    if maxMoves <= 0 then return 0 end

    local moved = 0
    local accepted = {}
    for id, contact in pairs(data.contacts) do
        if type(contact) == "table" and contact.blackMarketStatus ~= "closed" and contact.x and contact.y then
            local crowded = false
            for _, other in ipairs(accepted) do
                if bbm_dist(contact.x, contact.y, other.x, other.y) < NPCBlackMarketBridge.MinContactDistance() then
                    crowded = true
                    break
                end
            end
            if crowded and moved < maxMoves then
                data.contacts[id] = nil
                local source = bbm_findContactSource(gmd, contact)
                local x, y, z = bbm_pickContactPoint(source, data)
                data.contacts[id] = contact
                if x and y then
                    contact.x = x
                    contact.y = y
                    contact.z = z or contact.z or 0
                    contact.blackMarketHomeX = x
                    contact.blackMarketHomeY = y
                    contact.blackMarketHomeZ = contact.z or 0
                    contact.blackMarketHomeRadius = NPCBlackMarketBridge.ContactRoamRadius()
                    contact.blackMarketTargetX = nil
                    contact.blackMarketTargetY = nil
                    contact.blackMarketTargetZ = nil
                    contact.blackMarketVirtual = true
                    contact.blackMarketMaterialized = false
                    contact.updatedAt = bbm_now()
                    moved = moved + 1
                end
            end
            accepted[#accepted + 1] = {x=contact.x, y=contact.y}
        end
    end
    return moved
end

function NPCBlackMarketBridge.EnsureContacts(gmd)
    if not NPCBlackMarketBridge.IsEnabled() then return 0 end
    local data = NPCBlackMarketBridge.EnsureData(gmd)
    if not data then return 0 end
    NPCBlackMarketBridge.Cleanup(gmd)
    local maxContacts = NPCBlackMarketBridge.MaxContacts()
    if maxContacts <= 0 or bbm_contactCount(data) >= maxContacts then return 0 end

    local created = 0
    local candidates = {}
    if type(gmd.BaseCamps) == "table" then
        for id, base in pairs(gmd.BaseCamps) do
            if type(base) == "table" and base.x and base.y then
                local side = bbm_side(base.owner or base.captureTeam or base.factionSide or base.side)
                if side and not NPCBlackMarketBridge.ContactSourceExists(data, id, "base") then
                    candidates[#candidates + 1] = {x=base.x, y=base.y, z=base.z or 0, side=side, sourceId=id, sourceType="base"}
                end
            end
        end
    end
    if type(gmd.NPCLeadersBridge) == "table" and type(gmd.NPCLeadersBridge.leaders) == "table" then
        for id, leader in pairs(gmd.NPCLeadersBridge.leaders) do
            if type(leader) == "table" and leader.x and leader.y and leader.state ~= "dead" then
                local side = bbm_side(leader.side)
                if side and not NPCBlackMarketBridge.ContactSourceExists(data, id, "leader") then
                    candidates[#candidates + 1] = {x=leader.x, y=leader.y, z=leader.z or 0, side=side, sourceId=id, sourceType="leader"}
                end
            end
        end
    end
    if #candidates <= 0 then return 0 end
    bbm_shuffleCandidates(candidates)

    for _, c in ipairs(candidates) do
        if bbm_contactCount(data) >= maxContacts then break end
        local x, y, z = bbm_pickContactPoint(c, data)
        if x and y then
            local contact = NPCBlackMarketBridge.MakeContact(gmd, x, y, z or c.z or 0, c.side, c.sourceId, c.sourceType)
            if contact then created = created + 1 end
        end
        if created >= 2 then break end
    end
    return created
end

function NPCBlackMarketBridge.NearestContact(gmd, x, y, radius)
    local data = NPCBlackMarketBridge.EnsureData(gmd)
    if not data or type(data.contacts) ~= "table" then return nil end
    radius = tonumber(radius) or NPCBlackMarketBridge.InteractionRadius()
    local best, bestDist = nil, nil
    for _, contact in pairs(data.contacts) do
        if type(contact) == "table" and contact.blackMarketStatus ~= "closed" and contact.x and contact.y then
            local dx = (tonumber(contact.x) or 0) - (tonumber(x) or 0)
            local dy = (tonumber(contact.y) or 0) - (tonumber(y) or 0)
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist <= radius and (not bestDist or dist < bestDist) then
                best = contact
                bestDist = dist
            end
        end
    end
    return best, bestDist
end

function NPCBlackMarketBridge.GetContact(gmd, id)
    local data = NPCBlackMarketBridge.EnsureData(gmd)
    if not data or not id then return nil end
    return data.contacts[tostring(id)]
end

function NPCBlackMarketBridge.RecordTrade(gmd, player, contact, action, side, result)
    local data = NPCBlackMarketBridge.EnsureData(gmd)
    if not data then return end
    local pid = tostring(bbm_playerId(player) or "unknown")
    local entry = {
        playerId = pid,
        playerName = player and player.getUsername and player:getUsername() or nil,
        contactId = contact and contact.id or nil,
        action = action,
        side = side,
        result = result,
        at = bbm_now()
    }
    data.history[#data.history + 1] = entry
    while #data.history > 40 do table.remove(data.history, 1) end
    data.playerDeals[pid] = data.playerDeals[pid] or {}
    data.playerDeals[pid][#data.playerDeals[pid] + 1] = entry
    while #data.playerDeals[pid] > 12 do table.remove(data.playerDeals[pid], 1) end
    data.stats.trades = (tonumber(data.stats.trades) or 0) + 1
end

function NPCBlackMarketBridge.StatusText(gmd, player)
    local data = NPCBlackMarketBridge.EnsureData(gmd)
    if not data then return "Black market unavailable." end
    local pid = tostring(bbm_playerId(player) or "")
    local n = bbm_contactCount(data)
    local parts = {"Black market contacts: " .. tostring(n)}
    local deals = data.playerDeals[pid]
    if type(deals) == "table" and #deals > 0 then
        local last = deals[#deals]
        parts[#parts + 1] = "last deal: " .. tostring(last.action or "deal") .. " " .. tostring(last.result or "")
    end
    return table.concat(parts, " / ")
end

function NPCBlackMarketBridge.GetRadioCandidates(gmd)
    local data = NPCBlackMarketBridge.EnsureData(gmd)
    local list = {}
    if not data or type(data.contacts) ~= "table" then return list end
    for _, contact in pairs(data.contacts) do
        if type(contact) == "table" and contact.blackMarketStatus ~= "closed" then
            local side = contact.blackMarketSide or contact.side
            local text = "Black market contact near grid " .. tostring(math.floor(tonumber(contact.x) or 0)) .. "," .. tostring(math.floor(tonumber(contact.y) or 0)) .. " trading papers, passwords and bounty favors."
            list[#list + 1] = {kind="black_market", side=side, x=contact.x, y=contact.y, text=text, weight=3, data=contact}
        end
    end
    return list
end

function NPCBlackMarketBridge.SideLabel(side)
    return bbm_sideLabel(side)
end

function NPCBlackMarketBridge.NormalizeSide(side)
    return bbm_side(side)
end
