-- NPCBlackMarketBridge.lua
-- Neutral shared backend for black market contacts and services.
-- Contacts are virtual map records: they do not add physical NPCs or items by themselves.

NPCBlackMarketBridge = NPCBlackMarketBridge or {}
NPCBlackMarketBridge.Version = 3

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
        "Base.GoldRing", "Base.Ring_Gold", "Base.RingGold", "Base.Ring_Left_Gold", "Base.Ring_Right_Gold",
        "Base.Ring_Right_MiddleFinger_Gold", "Base.Ring_Left_MiddleFinger_Gold",
        "Base.Ring_Right_RingFinger_Gold", "Base.Ring_Left_RingFinger_Gold",
        "Base.Ring_Right_MiddleFinger_GoldDiamond", "Base.Ring_Left_MiddleFinger_GoldDiamond",
        "Base.Ring_Right_RingFinger_GoldDiamond", "Base.Ring_Left_RingFinger_GoldDiamond",
        "Base.Ring_Right_MiddleFinger_GoldRuby", "Base.Ring_Left_MiddleFinger_GoldRuby",
        "Base.Ring_Right_RingFinger_GoldRuby", "Base.Ring_Left_RingFinger_GoldRuby",
        "Base.Necklace_Gold", "Base.Necklace_GoldRuby", "Base.Necklace_GoldDiamond",
        "Base.NecklaceLong_Gold", "Base.NecklaceLong_GoldDiamond", "Base.NecklaceLong_GoldRuby",
        "Base.Bracelet_ChainRightGold", "Base.Bracelet_ChainLeftGold",
        "Base.Bracelet_BangleRightGold", "Base.Bracelet_BangleLeftGold", "Base.Bracelet_LeftGold", "Base.Bracelet_RightGold",
        "Base.Earring_LoopLrg_Gold", "Base.Earring_LoopMed_Gold", "Base.Earring_LoopSmall_Gold",
        "Base.Earring_LoopLrg_Gold_Both", "Base.Earring_LoopMed_Gold_Both", "Base.Earring_LoopSmall_Gold_Both", "Base.Earring_LoopSmall_Gold_Top",
        "Base.Earring_Stud_Gold_Both",
        "Base.Earring_Gold_LoopLrg", "Base.Earring_Gold_LoopMed", "Base.Earring_Gold_LoopSmall",
        "Base.Earring_Gold_LoopLrg_Both", "Base.Earring_Gold_LoopMed_Both", "Base.Earring_Gold_LoopSmall_Both",
        "Base.Earring_Gold_LoopLarge", "Base.Earring_Gold_LoopLarge_Both",
        "Base.BellyButton_DangleGold", "Base.BellyButton_DangleGoldRuby",
        "Base.BellyButton_RingGold", "Base.BellyButton_RingGoldDiamond", "Base.BellyButton_RingGoldRuby",
        "Base.BellyButton_StudGold", "Base.BellyButton_StudGoldDiamond",
        "Base.NoseRing_Gold", "Base.NoseStud_Gold",
        "Base.WristWatch_Left_ClassicGold", "Base.WristWatch_Right_ClassicGold"
    }},
    silver = {label="silver jewelry", items={
        "Base.SilverRing", "Base.Ring_Silver", "Base.RingSilver", "Base.Ring_Left_Silver", "Base.Ring_Right_Silver",
        "Base.Ring_Right_MiddleFinger_Silver", "Base.Ring_Left_MiddleFinger_Silver",
        "Base.Ring_Right_RingFinger_Silver", "Base.Ring_Left_RingFinger_Silver",
        "Base.Ring_Right_MiddleFinger_SilverDiamond", "Base.Ring_Left_MiddleFinger_SilverDiamond",
        "Base.Ring_Right_RingFinger_SilverDiamond", "Base.Ring_Left_RingFinger_SilverDiamond",
        "Base.Necklace_Silver", "Base.Necklace_SilverSapphire", "Base.Necklace_SilverCrucifix", "Base.Necklace_SilverDiamond",
        "Base.NecklaceLong_Silver", "Base.NecklaceLong_SilverDiamond", "Base.NecklaceLong_SilverEmerald", "Base.NecklaceLong_SilverSapphire",
        "Base.Bracelet_ChainRightSilver", "Base.Bracelet_ChainLeftSilver",
        "Base.Bracelet_BangleRightSilver", "Base.Bracelet_BangleLeftSilver", "Base.Bracelet_LeftSilver", "Base.Bracelet_RightSilver",
        "Base.Earring_LoopLrg_Silver", "Base.Earring_LoopMed_Silver", "Base.Earring_LoopSmall_Silver",
        "Base.Earring_LoopLrg_Silver_Both", "Base.Earring_LoopMed_Silver_Both", "Base.Earring_LoopSmall_Silver_Both", "Base.Earring_LoopSmall_Silver_Top",
        "Base.Earring_Stud_Silver_Both",
        "Base.Earring_Silver_LoopLrg", "Base.Earring_Silver_LoopMed", "Base.Earring_Silver_LoopSmall",
        "Base.Earring_Silver_LoopLrg_Both", "Base.Earring_Silver_LoopMed_Both", "Base.Earring_Silver_LoopSmall_Both",
        "Base.Earring_Silver_LoopLarge", "Base.Earring_Silver_LoopLarge_Both",
        "Base.BellyButton_DangleSilver", "Base.BellyButton_DangleSilverDiamond",
        "Base.BellyButton_RingSilver", "Base.BellyButton_RingSilverAmethyst", "Base.BellyButton_RingSilverDiamond", "Base.BellyButton_RingSilverRuby",
        "Base.BellyButton_StudSilver", "Base.BellyButton_StudSilverDiamond",
        "Base.NoseRing_Silver", "Base.NoseStud_Silver",
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
    leader_tip = {label="leader rumor", resource="silver", setting="BlackMarket_LeaderTipCost", default=2},
    ammo_drop = {label="ammo cache", resource="silver", setting="BlackMarket_AmmoDropCost", default=5, deadDrop=true, dropType="ammo"},
    medical_drop = {label="medical cache", resource="silver", setting="BlackMarket_MedicalDropCost", default=4, deadDrop=true, dropType="medical"},
    weapon_drop = {label="weapon cache", resource="gold", setting="BlackMarket_WeaponDropCost", default=3, deadDrop=true, dropType="weapons"},
    armor_drop = {label="armor cache", resource="gold", setting="BlackMarket_ArmorDropCost", default=2, deadDrop=true, dropType="armor"}
}

local BBM_DEAD_DROP_BUNDLES = {
    ammo = {
        label = "ammo cache",
        container = {"Base.Bag_Satchel", "Base.Bag_DuffelBag", "Base.Plasticbag"},
        items = {"Base.9mmBullets", "Base.9mmBullets", "Base.556Bullets", "Base.556Bullets", "Base.ShotgunShells", "Base.ShotgunShells"}
    },
    medical = {
        label = "medical cache",
        container = {"Base.FirstAidKit", "Base.Bag_Satchel", "Base.Plasticbag"},
        items = {"Base.Bandage", "Base.Bandage", "Base.AlcoholBandage", "Base.Disinfectant", "Base.Pills", "Base.SutureNeedle"}
    },
    weapons = {
        label = "weapon cache",
        container = {"Base.Bag_DuffelBag", "Base.Bag_Satchel", "Base.Plasticbag"},
        items = {"Base.Pistol", "Base.9mmClip", "Base.9mmBullets", "Base.HuntingKnife", "Base.Shotgun", "Base.ShotgunShells"}
    },
    armor = {
        label = "armor cache",
        container = {"Base.Bag_DuffelBag", "Base.Bag_Satchel", "Base.Plasticbag"},
        items = {"Base.Vest_BulletArmy", "Base.Vest_BulletPolice", "Base.Hat_ArmyHelmet", "Base.Hat_Army", "Base.HolsterSimple", "Base.Gloves_LeatherGloves", "Base.Shoes_ArmyBoots"}
    }
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

function NPCBlackMarketBridge.DeadDropEnabled()
    return bbm_bool("BlackMarket_DeadDropEnabled", true)
end

function NPCBlackMarketBridge.DeadDropAmbushChance()
    return bbm_num("BlackMarket_AmbushChance", 12, 0, 100)
end

function NPCBlackMarketBridge.DeadDropRevealDistance()
    local radioReveal = bbm_num("RadioIntercept_StashRevealDistance", 36, 3, 120)
    local marketReveal = bbm_num("BlackMarket_DeadDropRevealDistance", 72, 3, 200)
    return math.max(radioReveal, marketReveal)
end

function NPCBlackMarketBridge.FetchQuestGuardMin()
    return math.max(1, math.floor(bbm_num("BlackMarket_FetchQuestGuardMin", 3, 1, 12)))
end

function NPCBlackMarketBridge.FetchQuestGuardMax()
    local minValue = NPCBlackMarketBridge.FetchQuestGuardMin()
    return math.max(minValue, math.floor(bbm_num("BlackMarket_FetchQuestGuardMax", 5, minValue, 16)))
end

function NPCBlackMarketBridge.FetchQuestGuardLeashRadius()
    return bbm_num("BlackMarket_FetchQuestGuardLeashRadius", 7, 3, 24)
end

function NPCBlackMarketBridge.FetchQuestGuardSpawnRadius()
    return bbm_num("BlackMarket_FetchQuestGuardSpawnRadius", 9, 3, 36)
end

function NPCBlackMarketBridge.FetchQuestZoneRadius()
    return bbm_num("BlackMarket_FetchQuestZoneRadius", 24, 8, 80)
end

function NPCBlackMarketBridge.DefenseQuestZoneRadius()
    return bbm_num("BlackMarket_DefenseQuestZoneRadius", 28, 10, 90)
end

function NPCBlackMarketBridge.DefenseQuestWaveSize(wave)
    local defaults = {4, 5, 6}
    local index = math.max(1, math.min(3, math.floor(tonumber(wave) or 1)))
    return math.max(1, math.floor(bbm_num("BlackMarket_DefenseQuestWave" .. tostring(index) .. "Size", defaults[index] or 4, 1, 24)))
end

function NPCBlackMarketBridge.PlayerId(player)
    return bbm_playerId(player)
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

function NPCBlackMarketBridge.DealLabel(action)
    local deal = BBM_DEALS[tostring(action or "")]
    return deal and deal.label or tostring(action or "deal")
end

function NPCBlackMarketBridge.IsDeadDropDeal(action)
    local deal = BBM_DEALS[tostring(action or "")]
    return deal and deal.deadDrop == true or false
end

function NPCBlackMarketBridge.DeadDropBundle(action)
    local deal = BBM_DEALS[tostring(action or "")]
    if not (deal and deal.dropType) then return nil end
    local bundle = BBM_DEAD_DROP_BUNDLES[tostring(deal.dropType)]
    if not bundle then return nil end
    return {
        type = tostring(deal.dropType),
        label = bundle.label or deal.label,
        container = bundle.container,
        items = bundle.items
    }
end

function NPCBlackMarketBridge.EnsureData(gmd)
    if not gmd then return nil end
    gmd.BlackMarket = gmd.BlackMarket or {}
    gmd.BlackMarket.contacts = gmd.BlackMarket.contacts or {}
    gmd.BlackMarket.history = gmd.BlackMarket.history or {}
    gmd.BlackMarket.playerDeals = gmd.BlackMarket.playerDeals or {}
    gmd.BlackMarket.deadDrops = gmd.BlackMarket.deadDrops or {}
    gmd.BlackMarket.fetchQuests = gmd.BlackMarket.fetchQuests or {}
    gmd.BlackMarket.defenseQuests = gmd.BlackMarket.defenseQuests or {}
    gmd.BlackMarket.stats = gmd.BlackMarket.stats or {contacts=0, trades=0, denied=0, payoffs=0, tips=0, deadDrops=0, fetchQuests=0, defenseQuests=0}
    gmd.BlackMarket.stats.deadDrops = tonumber(gmd.BlackMarket.stats.deadDrops) or 0
    gmd.BlackMarket.stats.fetchQuests = tonumber(gmd.BlackMarket.stats.fetchQuests) or 0
    gmd.BlackMarket.stats.defenseQuests = tonumber(gmd.BlackMarket.stats.defenseQuests) or 0
    gmd.BlackMarket.spriteBag = gmd.BlackMarket.spriteBag or {}
    gmd.BlackMarket.nextId = tonumber(gmd.BlackMarket.nextId) or 1
    gmd.BlackMarket.nextDeadDropId = tonumber(gmd.BlackMarket.nextDeadDropId) or 1
    gmd.BlackMarket.nextFetchQuestId = tonumber(gmd.BlackMarket.nextFetchQuestId) or 1
    gmd.BlackMarket.nextDefenseQuestId = tonumber(gmd.BlackMarket.nextDefenseQuestId) or 1
    if not gmd.DebugMapMarkers then gmd.DebugMapMarkers = {} end
    return gmd.BlackMarket
end

local function bbm_itemFullType(item)
    if not item then return nil end
    if item.getFullType then
        local ok, ft = pcall(function() return item:getFullType() end)
        if ok and ft then return tostring(ft) end
    end
    if item.getModule and item.getType then
        local ok, ft = pcall(function() return tostring(item:getModule()) .. "." .. tostring(item:getType()) end)
        if ok and ft then return tostring(ft) end
    end
    return nil
end

local function bbm_itemDisplayName(item)
    if not item then return "" end
    if item.getDisplayName then
        local ok, name = pcall(function() return item:getDisplayName() end)
        if ok and name then return tostring(name) end
    end
    if item.getName then
        local ok, name = pcall(function() return item:getName() end)
        if ok and name then return tostring(name) end
    end
    return bbm_itemFullType(item) or ""
end

local function bbm_itemModData(item)
    if item and item.getModData then
        local ok, md = pcall(function() return item:getModData() end)
        if ok then return md end
    end
    return nil
end

local function bbm_stackCount(item)
    if not item then return 1 end
    local methods = {"getCount", "getCurrentUses", "getUses"}
    for _, method in ipairs(methods) do
        local fn = item[method]
        if fn then
            local ok, value = pcall(function() return fn(item) end)
            value = ok and tonumber(value) or nil
            if value and value > 1 then return math.floor(value) end
        end
    end
    local md = bbm_itemModData(item)
    if md then
        local value = tonumber(md.fcGoldCount or md.fcBlackMarketGoldCount or md.count or md.Count or md.stackCount or md.StackCount)
        if value and value > 1 then return math.floor(value) end
    end
    return 1
end

local function bbm_countFromText(item)
    local text = string.lower(tostring(bbm_itemFullType(item) or "") .. " " .. tostring(bbm_itemDisplayName(item) or ""))
    local patterns = {
        "[xх]%s*(%d+)",
        "(%d+)%s*[xх]",
        "(%d+)%s*шт",
        "(%d+)%s*pcs",
        "(%d+)%s*pieces",
        "(%d+)%s*count"
    }
    for _, pattern in ipairs(patterns) do
        local value = tonumber(string.match(text, pattern))
        if value and value > 1 and value <= 100 then return math.floor(value) end
    end
    return 1
end

local function bbm_jewelryUnitValue(resourceKey, item)
    local key = tostring(resourceKey or "")
    if key ~= "gold" and key ~= "silver" then return 1 end
    local rawText = tostring(bbm_itemFullType(item) or "") .. " " .. tostring(bbm_itemDisplayName(item) or "")
    local text = string.lower(rawText)
    if string.find(text, "_both", 1, true)
        or string.find(text, "both", 1, true)
        or string.find(text, "pair", 1, true)
        or string.find(text, "large", 1, true)
        or string.find(text, "lrg", 1, true)
        or string.find(text, "looplrg", 1, true)
        or string.find(rawText, "серьги", 1, true)
        or string.find(rawText, "Серьги", 1, true)
        or string.find(rawText, "пара", 1, true)
        or string.find(rawText, "Пара", 1, true)
        or string.find(rawText, "Большие", 1, true)
        or string.find(rawText, "большие", 1, true) then
        return 2
    end
    return 1
end

local function bbm_resourceUnits(resourceKey, item)
    local stack = math.max(1, math.floor(tonumber(bbm_stackCount(item)) or 1))
    local fromText = math.max(1, math.floor(tonumber(bbm_countFromText(item)) or 1))
    local unitValue = math.max(1, math.floor(tonumber(bbm_jewelryUnitValue(resourceKey, item)) or 1))
    return math.max(stack, fromText) * unitValue, unitValue, stack
end

local function bbm_fullTypeUnitValue(resourceKey, fullType)
    local key = tostring(resourceKey or "")
    if key ~= "gold" and key ~= "silver" then return 1 end
    local text = tostring(fullType or "")
    local lower = string.lower(text)
    if string.find(lower, "_both", 1, true)
        or string.find(lower, "both", 1, true)
        or string.find(lower, "looplrg", 1, true)
        or string.find(lower, "lrg", 1, true)
        or string.find(lower, "large", 1, true) then
        return 2
    end
    return 1
end

local function bbm_scanInventoryItems(container, out, depth)
    out = out or {}
    if not container or (tonumber(depth) or 0) > 4 then return out end
    local items = nil
    if container.getItems then
        local ok, got = pcall(function() return container:getItems() end)
        if ok then items = got end
    end
    if not (items and items.size and items.get) then return out end
    local size = 0
    local okSize, gotSize = pcall(function() return items:size() end)
    if okSize then size = tonumber(gotSize) or 0 end
    for i = 0, size - 1 do
        local okItem, item = pcall(function() return items:get(i) end)
        if okItem and item then
            out[#out + 1] = item
            if item.getInventory then
                local okInv, inv = pcall(function() return item:getInventory() end)
                if okInv and inv then bbm_scanInventoryItems(inv, out, (tonumber(depth) or 0) + 1) end
            end
        end
    end
    return out
end

local function bbm_scanPlayerItems(player)
    local out = {}
    if player and player.getInventory then
        local ok, inv = pcall(function() return player:getInventory() end)
        if ok and inv then bbm_scanInventoryItems(inv, out, 0) end
    end
    if player and player.getWornItems then
        local okWorn, worn = pcall(function() return player:getWornItems() end)
        if okWorn and worn and worn.size and worn.get then
            local size = 0
            local okSize, gotSize = pcall(function() return worn:size() end)
            if okSize then size = tonumber(gotSize) or 0 end
            for i = 0, size - 1 do
                local okRow, row = pcall(function() return worn:get(i) end)
                local item = nil
                if okRow and row then
                    if row.getItem then
                        local okItem, got = pcall(function() return row:getItem() end)
                        if okItem then item = got end
                    else
                        item = row
                    end
                end
                if item then out[#out + 1] = item end
            end
        end
    end
    if player and player.getPrimaryHandItem then
        local ok, item = pcall(function() return player:getPrimaryHandItem() end)
        if ok and item then out[#out + 1] = item end
    end
    if player and player.getSecondaryHandItem then
        local ok, item = pcall(function() return player:getSecondaryHandItem() end)
        if ok and item then out[#out + 1] = item end
    end
    return out
end

local function bbm_exactResourceItem(res, fullType)
    if not (res and type(res.items) == "table" and fullType) then return false end
    for _, itemType in ipairs(res.items) do
        if fullType == itemType then return true end
    end
    return false
end

local function bbm_textContainsAny(text, words)
    text = tostring(text or "")
    local lower = string.lower(text)
    for _, word in ipairs(words or {}) do
        if string.find(text, word, 1, true) or string.find(lower, string.lower(tostring(word)), 1, true) then
            return true
        end
    end
    return false
end

local function bbm_looseJewelryMatch(resourceKey, item)
    local key = tostring(resourceKey or "")
    if key ~= "gold" and key ~= "silver" then return false end
    local ftRaw = tostring(bbm_itemFullType(item) or "")
    local dnRaw = tostring(bbm_itemDisplayName(item) or "")
    local ft = string.lower(ftRaw)
    local dn = string.lower(dnRaw)
    local md = bbm_itemModData(item)
    if md and ((key == "gold" and (md.fcBlackMarketGold == true or md.FactionsConfrontationGoldBundle == true)) or (key == "silver" and md.fcBlackMarketSilver == true)) then
        return true
    end

    local rawText = ftRaw .. " " .. dnRaw
    local text = ft .. " " .. dn
    local metalOk = false
    if key == "gold" then
        metalOk = bbm_textContainsAny(rawText, {"gold", "Gold", "GOLD", "золот", "Золот", "ЗОЛОТ"})
    else
        metalOk = bbm_textContainsAny(rawText, {"silver", "Silver", "SILVER", "сереб", "Сереб", "СЕРЕБ"})
    end
    if not metalOk then return false end

    -- Stage 377: treat any explicit gold/silver wearable/value item as black-market currency.
    -- Some vanilla/localized jewelry names do not expose a stable English jewelry word on the server,
    -- but still expose metal in the translated display name, for example RU gold hoop earrings.
    local accessoryOk = bbm_textContainsAny(rawText, {
        "ring", "necklace", "bracelet", "earring", "watch", "jewel", "jewelry", "jewellery", "bundle", "pack",
        "кольц", "Кольц", "ожерель", "Ожерель", "браслет", "Браслет", "серь", "Серь", "часы", "Часы", "украш", "Украш",
        "аксессуар", "Аксессуар", "цепоч", "Цепоч", "кулон", "Кулон"
    })
    if accessoryOk then return true end

    -- Conservative fallback: if the item fullType/displayName explicitly says gold/silver,
    -- accept it as a currency piece rather than blocking the trade. Black market deals are
    -- intentionally paid with valuables, not only with a narrow item-id whitelist.
    return true
end

local function bbm_resourceMatchesItem(resourceKey, res, item)
    local fullType = bbm_itemFullType(item)
    if bbm_exactResourceItem(res, fullType) then return true end
    return bbm_looseJewelryMatch(resourceKey, item)
end

local function bbm_containerExactCount(container, fullType)
    if not (container and fullType) then return 0 end
    local count = 0
    local methods = {"getItemCountFromTypeRecurse", "getCountTypeRecurse", "getItemCount"}
    for _, method in ipairs(methods) do
        local fn = container[method]
        if fn then
            local ok, value = pcall(function() return fn(container, fullType) end)
            value = ok and tonumber(value) or nil
            if value and value > count then count = math.floor(value) end
        end
    end
    return count
end

local function bbm_firstExactItem(container, fullType)
    if not (container and fullType) then return nil end
    local methods = {"getFirstTypeRecurse", "getFirstType", "FindAndReturn"}
    for _, method in ipairs(methods) do
        local fn = container[method]
        if fn then
            local ok, item = pcall(function() return fn(container, fullType) end)
            if ok and item then return item end
        end
    end
    return nil
end

local function bbm_exactResourceUnitsFromContainer(player, resourceKey, res)
    if not (player and player.getInventory and res and type(res.items) == "table") then return 0 end
    local okInv, inv = pcall(function() return player:getInventory() end)
    if not (okInv and inv) then return 0 end
    local total = 0
    for _, fullType in ipairs(res.items) do
        local count = bbm_containerExactCount(inv, fullType)
        if count > 0 then
            local units = count * bbm_fullTypeUnitValue(resourceKey, fullType)
            local first = bbm_firstExactItem(inv, fullType)
            if first then
                local stackUnits = bbm_resourceUnits(resourceKey, first)
                if stackUnits > units then units = stackUnits end
            end
            total = total + units
        end
    end
    return total
end


local function bbm_paymentTypeSet(itemTypes)
    local out = {}
    if type(itemTypes) == "table" then
        for _, fullType in ipairs(itemTypes) do
            if fullType ~= nil then
                out[string.lower(tostring(fullType))] = true
                local short = tostring(fullType):match("%.([^%.]+)$")
                if short then out[string.lower(short)] = true end
            end
        end
    end
    return out
end

local function bbm_inventory(playerOrInv)
    if playerOrInv and playerOrInv.getInventory then
        local ok, inv = pcall(function() return playerOrInv:getInventory() end)
        if ok and inv then return inv end
    end
    return playerOrInv
end

local function bbm_itemText(item, method)
    if not (item and method) then return nil end

    local ok, value = false, nil
    if method == "getFullType" and item.getFullType then
        ok, value = pcall(function() return item:getFullType() end)
    elseif method == "getType" and item.getType then
        ok, value = pcall(function() return item:getType() end)
    elseif method == "getName" and item.getName then
        ok, value = pcall(function() return item:getName() end)
    elseif method == "getDisplayName" and item.getDisplayName then
        ok, value = pcall(function() return item:getDisplayName() end)
    end
    if ok and value ~= nil then return tostring(value) end

    local fn = nil
    local okFn = pcall(function() fn = item[method] end)
    if not (okFn and fn) then return nil end
    ok, value = pcall(function() return fn(item) end)
    if ok and value ~= nil then return tostring(value) end
    return nil
end

local function bbm_itemContainer(item)
    if not item then return nil end
    if item.getContainer then
        local ok, container = pcall(function() return item:getContainer() end)
        if ok and container then return container end
    end
    if item.getOutermostContainer then
        local ok, container = pcall(function() return item:getOutermostContainer() end)
        if ok and container then return container end
    end
    return nil
end

local function bbm_nestedContainer(item)
    if not item then return nil end
    if item.getInventory then
        local ok, container = pcall(function() return item:getInventory() end)
        if ok and container then return container end
    end
    if item.getItemContainer then
        local ok, container = pcall(function() return item:getItemContainer() end)
        if ok and container then return container end
    end
    return nil
end

local function bbm_paymentStackCount(item)
    if not item then return 1 end

    if item.getCount then
        local ok, count = pcall(function() return item:getCount() end)
        count = ok and math.floor(tonumber(count) or 0) or 0
        if count > 1 then return count end
    end
    if item.getCurrentUses then
        local ok, count = pcall(function() return item:getCurrentUses() end)
        count = ok and math.floor(tonumber(count) or 0) or 0
        if count > 1 then return count end
    end
    if item.getUses then
        local ok, count = pcall(function() return item:getUses() end)
        count = ok and math.floor(tonumber(count) or 0) or 0
        if count > 1 then return count end
    end

    local md = bbm_itemModData(item)
    if md then
        local count = tonumber(md.fcGoldCount or md.fcBlackMarketGoldCount or md.fcBlackMarketSilverCount or md.count or md.Count or md.stackCount or md.StackCount)
        if count and count > 1 then return math.floor(count) end
    end

    return 1
end

local function bbm_isJewelryType(text)
    text = string.lower(tostring(text or ""))
    return string.find(text, "ring", 1, true)
        or string.find(text, "necklace", 1, true)
        or string.find(text, "bracelet", 1, true)
        or string.find(text, "earring", 1, true)
        or string.find(text, "wristwatch", 1, true)
        or string.find(text, "bellybutton", 1, true)
        or string.find(text, "nose", 1, true)
        or string.find(text, "jewel", 1, true)
        or string.find(text, "кольц", 1, true)
        or string.find(text, "цеп", 1, true)
        or string.find(text, "ожерел", 1, true)
        or string.find(text, "браслет", 1, true)
        or string.find(text, "серь", 1, true)
        or string.find(text, "час", 1, true)
        or string.find(text, "украшен", 1, true)
        or string.find(text, "пирсинг", 1, true)
end

local function bbm_paymentItemMatches(item, itemTypes, kind)
    if not item then return false end
    local set = bbm_paymentTypeSet(itemTypes)
    local fullType = bbm_itemText(item, "getFullType")
    local itemType = bbm_itemText(item, "getType")
    local name = bbm_itemText(item, "getName") or ""
    local displayName = bbm_itemText(item, "getDisplayName") or ""
    local text = tostring(fullType or "") .. " " .. tostring(itemType or "") .. " " .. tostring(name or "") .. " " .. tostring(displayName or "")
    local lowFull = string.lower(tostring(fullType or ""))
    local lowType = string.lower(tostring(itemType or ""))

    if set[lowFull] or set[lowType] then return true end
    if itemType and set[string.lower("Base." .. tostring(itemType))] then return true end

    local lowText = string.lower(text)
    local isGold = string.find(lowText, "gold", 1, true) or string.find(lowText, "золот", 1, true)
    local isSilver = string.find(lowText, "silver", 1, true) or string.find(lowText, "сереб", 1, true)
    if kind == "gold" and not isGold then return false end
    if kind == "silver" and not isSilver then return false end
    if bbm_isJewelryType(lowText) then return true end

    -- MP-safe fallback: some localized/modded valuable stacks expose only the
    -- metal name to Lua, without a stable "jewelry/ring/earring" token. The
    -- market treats explicit gold/silver valuables as payment instead of
    -- rejecting them with a false "Need silver jewelry" message.
    return isGold or isSilver
end

local function bbm_paymentItemKey(item)
    if not item then return nil end
    if item.getID then
        local ok, id = pcall(function() return item:getID() end)
        if ok and id ~= nil then return "id:" .. tostring(id) end
    end
    return nil
end

local function bbm_addPaymentItem(out, seenItems, item, container, itemTypes, kind)
    if not item then return end

    local key = bbm_paymentItemKey(item)
    if seenItems then
        if seenItems[item] then return end
        if key and seenItems[key] then return end
    end

    if bbm_paymentItemMatches(item, itemTypes, kind) then
        if seenItems then
            seenItems[item] = true
            if key then seenItems[key] = true end
        end
        out[#out + 1] = {item=item, container=bbm_itemContainer(item) or container}
    end
end

local function bbm_collectPaymentItemsFromContainer(container, itemTypes, kind, out, seen, depth, seenItems)
    if not container or not container.getItems then return end
    depth = tonumber(depth) or 0
    if depth > 5 then return end
    seen = seen or {}
    seenItems = seenItems or {}
    local key = tostring(container)
    if seen[key] then return end
    seen[key] = true

    local okItems, items = pcall(function() return container:getItems() end)
    if not (okItems and items and items.size and items.get) then return end

    local size = 0
    local okSize, gotSize = pcall(function() return items:size() end)
    if okSize then size = tonumber(gotSize) or 0 end
    for i = 0, size - 1 do
        local okGet, item = pcall(function() return items:get(i) end)
        if okGet and item then
            bbm_addPaymentItem(out, seenItems, item, container, itemTypes, kind)
            local nested = bbm_nestedContainer(item)
            if nested then bbm_collectPaymentItemsFromContainer(nested, itemTypes, kind, out, seen, depth + 1, seenItems) end
        end
    end
end

local function bbm_collectPaymentItemsFromWornItems(player, itemTypes, kind, out, seenItems)
    if not (player and player.getWornItems) then return end
    local okWorn, worn = pcall(function() return player:getWornItems() end)
    if not (okWorn and worn) then return end
    local inv = nil
    if player.getInventory then
        local okInv, gotInv = pcall(function() return player:getInventory() end)
        if okInv then inv = gotInv end
    end

    local size = 0
    if worn.size then
        local okSize, gotSize = pcall(function() return worn:size() end)
        if okSize then size = tonumber(gotSize) or 0 end
    end

    for i = 0, size - 1 do
        local item = nil
        if worn.getItemByIndex then
            local ok, got = pcall(function() return worn:getItemByIndex(i) end)
            if ok then item = got end
        end
        if not item and worn.get then
            local ok, wornItem = pcall(function() return worn:get(i) end)
            if ok and wornItem then
                if wornItem.getItem then
                    local okItem, got = pcall(function() return wornItem:getItem() end)
                    if okItem then item = got end
                else
                    item = wornItem
                end
            end
        end
        bbm_addPaymentItem(out, seenItems, item, inv, itemTypes, kind)
    end
end

local function bbm_collectPaymentItems(playerOrInv, itemTypes, kind)
    local out = {}
    local seenItems = {}
    local inv = playerOrInv
    if playerOrInv and playerOrInv.getInventory then
        local okInv, gotInv = pcall(function() return playerOrInv:getInventory() end)
        if okInv and gotInv then inv = gotInv end
        bbm_collectPaymentItemsFromWornItems(playerOrInv, itemTypes, kind, out, seenItems)
    end
    bbm_collectPaymentItemsFromContainer(inv, itemTypes, kind, out, {}, 0, seenItems)
    return out
end

local function bbm_exactItemCount(inv, itemTypes)
    inv = bbm_inventory(inv)
    if not (inv and inv.getItemCountFromTypeRecurse and type(itemTypes) == "table") then return 0 end
    local total = 0
    for _, fullType in ipairs(itemTypes) do
        local ok, count = pcall(function() return inv:getItemCountFromTypeRecurse(fullType) end)
        if ok and count then total = total + (tonumber(count) or 0) end
    end
    return total
end

local function bbm_blackMarketPaymentCount(playerOrInv, itemTypes, kind)
    local exactTotal = bbm_exactItemCount(playerOrInv, itemTypes)
    local collected = bbm_collectPaymentItems(playerOrInv, itemTypes, kind)
    if #collected > 0 then
        local total = 0
        for _, entry in ipairs(collected) do
            total = total + bbm_paymentStackCount(entry and entry.item)
        end
        if total > 0 then return math.max(total, exactTotal) end
    end
    return exactTotal
end

local function bbm_setPaymentStackCount(item, left)
    left = math.floor(tonumber(left) or 0)
    local setters = {
        {"setCount", left},
        {"setCurrentUses", left},
        {"setUses", left}
    }
    for _, row in ipairs(setters) do
        local fn = item and item[row[1]]
        if fn then
            local ok = pcall(function() fn(item, row[2]) end)
            if ok then return true end
        end
    end
    local md = bbm_itemModData(item)
    if md and (md.fcGoldCount or md.fcBlackMarketGoldCount or md.fcBlackMarketSilverCount or md.count or md.Count or md.stackCount or md.StackCount) then
        md.fcGoldCount = left
        md.fcBlackMarketGoldCount = left
        md.fcBlackMarketSilverCount = left
        md.count = left
        md.Count = left
        md.stackCount = left
        md.StackCount = left
        return true
    end
    return false
end

local function bbm_blackMarketRemovePayment(playerOrInv, itemTypes, count, kind)
    local remaining = tonumber(count) or 0
    if remaining <= 0 then return true end

    local payInv = bbm_inventory(playerOrInv)
    local collected = bbm_collectPaymentItems(playerOrInv, itemTypes, kind)
    for _, entry in ipairs(collected) do
        if remaining <= 0 then return true end

        local item = entry and entry.item
        local stackCount = bbm_paymentStackCount(item)
        local container = entry and entry.container or payInv
        local removed = false

        if item and stackCount > 1 then
            local take = math.min(remaining, stackCount)
            if take < stackCount and bbm_setPaymentStackCount(item, stackCount - take) then
                remaining = remaining - take
                removed = true
            end
        end

        if item and not removed then
            if container and container.Remove then
                local ok = pcall(function() container:Remove(item) end)
                if ok then removed = true end
            end
            if not removed and payInv and payInv.Remove then
                local ok = pcall(function() payInv:Remove(item) end)
                if ok then removed = true end
            end
            if removed then remaining = remaining - math.max(1, stackCount) end
        end
    end
    if remaining <= 0 then return true end

    if not (payInv and payInv.getItemCountFromTypeRecurse and payInv.RemoveOneOf and type(itemTypes) == "table") then return false end
    for _, fullType in ipairs(itemTypes) do
        while remaining > 0 do
            local before = 0
            local okCount, current = pcall(function() return payInv:getItemCountFromTypeRecurse(fullType) end)
            if not okCount or not current or tonumber(current) <= 0 then break end
            before = tonumber(current) or 0

            local removed = false
            local ok = pcall(function() payInv:RemoveOneOf(fullType, true) end)
            if ok and (tonumber(payInv:getItemCountFromTypeRecurse(fullType)) or 0) < before then removed = true end
            if not removed then
                before = tonumber(payInv:getItemCountFromTypeRecurse(fullType)) or 0
                ok = pcall(function() payInv:RemoveOneOf(fullType, false) end)
                if ok and (tonumber(payInv:getItemCountFromTypeRecurse(fullType)) or 0) < before then removed = true end
            end
            if not removed then break end
            remaining = remaining - 1
        end
        if remaining <= 0 then return true end
    end

    return remaining <= 0
end

function NPCBlackMarketBridge.CountItems(player, resourceKey)
    resourceKey = tostring(resourceKey or "")
    local res = BBM_RESOURCES[resourceKey]
    if not (player and res and type(res.items) == "table") then return 0 end

    -- Stage 382: black-market valuables now use the same payment philosophy as
    -- mercenary hiring: count exact item ids, inventory/worn/nested items, and
    -- stack-like jewelry counts; do not use pair/large-earring bonus units.
    if resourceKey == "gold" or resourceKey == "silver" then
        return bbm_blackMarketPaymentCount(player, res.items, resourceKey)
    end

    local total = 0
    local seen = {}
    for _, item in ipairs(bbm_scanPlayerItems(player)) do
        if item and not seen[item] and bbm_resourceMatchesItem(resourceKey, res, item) then
            seen[item] = true
            total = total + bbm_resourceUnits(resourceKey, item)
        end
    end

    local exactContainerTotal = bbm_exactResourceUnitsFromContainer(player, resourceKey, res)
    if exactContainerTotal > total then total = exactContainerTotal end
    return total
end

local function bbm_decreaseStack(item, removeCount)
    local current = bbm_stackCount(item)
    removeCount = math.floor(tonumber(removeCount) or 0)
    if removeCount <= 0 then return true, 0 end
    if current <= removeCount then return false, 0 end
    local left = current - removeCount
    local setters = {
        {"setCount", left},
        {"setCurrentUses", left},
        {"setUses", left}
    }
    for _, row in ipairs(setters) do
        local fn = item and item[row[1]]
        if fn then
            local ok = pcall(function() fn(item, row[2]) end)
            if ok then return true, removeCount end
        end
    end
    local md = bbm_itemModData(item)
    if md and (md.fcGoldCount or md.fcBlackMarketGoldCount or md.count or md.Count or md.stackCount or md.StackCount) then
        md.fcGoldCount = left
        md.fcBlackMarketGoldCount = left
        md.count = left
        md.Count = left
        md.stackCount = left
        return true, removeCount
    end
    return false, 0
end

local function bbm_unwearOrUnequipItem(player, item)
    if not (player and item) then return end
    if player.getPrimaryHandItem and player.setPrimaryHandItem then
        local ok, held = pcall(function() return player:getPrimaryHandItem() end)
        if ok and held == item then pcall(function() player:setPrimaryHandItem(nil) end) end
    end
    if player.getSecondaryHandItem and player.setSecondaryHandItem then
        local ok, held = pcall(function() return player:getSecondaryHandItem() end)
        if ok and held == item then pcall(function() player:setSecondaryHandItem(nil) end) end
    end
    if player.removeWornItem then
        pcall(function() player:removeWornItem(item) end)
    end
    local bodyLocation = nil
    if item.getBodyLocation then
        local ok, loc = pcall(function() return item:getBodyLocation() end)
        if ok and loc then bodyLocation = tostring(loc) end
    end
    if bodyLocation and bodyLocation ~= "" then
        if player.setWornItem then
            pcall(function() player:setWornItem(bodyLocation, nil) end)
        end
        if player.getWornItems then
            local okWorn, worn = pcall(function() return player:getWornItems() end)
            if okWorn and worn then
                if worn.setItem then pcall(function() worn:setItem(bodyLocation, nil) end) end
                if worn.remove then pcall(function() worn:remove(bodyLocation) end) end
                if worn.Remove then pcall(function() worn:Remove(bodyLocation) end) end
            end
        end
    end
end

local function bbm_itemStillInContainer(item, container)
    if not (item and container) then return false end
    local sameContainer = false
    if item.getContainer then
        local ok, current = pcall(function() return item:getContainer() end)
        if ok and current ~= nil then
            if current ~= container then return false end
            sameContainer = true
        end
    end
    if container.contains then
        local ok, value = pcall(function() return container:contains(item) end)
        if ok and value ~= nil then return value == true end
    end
    if container.getItems then
        local okItems, items = pcall(function() return container:getItems() end)
        if okItems and items and items.size and items.get then
            local size = 0
            local okSize, gotSize = pcall(function() return items:size() end)
            if okSize then size = tonumber(gotSize) or 0 end
            for i = 0, size - 1 do
                local okItem, got = pcall(function() return items:get(i) end)
                if okItem and got == item then return true end
            end
            return false
        end
    end
    return sameContainer
end

local function bbm_removeItemFromContainer(container, item, fullType)
    if not (container and item) then return false end
    local before = fullType and bbm_containerExactCount(container, fullType) or nil
    local methods = {"Remove", "RemoveItem", "DoRemoveItem"}
    for _, method in ipairs(methods) do
        local fn = container[method]
        if fn then
            local ok = pcall(function() fn(container, item) end)
            if ok then
                if before and before > 0 then
                    local after = bbm_containerExactCount(container, fullType)
                    if after < before then return true end
                end
                if not bbm_itemStillInContainer(item, container) then return true end
            end
        end
    end
    return false
end

local function bbm_removeItemObject(item, rootInventory, player)
    if not item then return false end
    local fullType = bbm_itemFullType(item)

    -- Worn jewelry may be visible in the inventory UI but server-side ItemContainer:Remove()
    -- can fail until it is unequipped from WornItems. Always try to detach it first.
    bbm_unwearOrUnequipItem(player, item)

    if item.getContainer then
        local okContainer, container = pcall(function() return item:getContainer() end)
        if okContainer and container and bbm_removeItemFromContainer(container, item, fullType) then return true end
    end
    if rootInventory and bbm_removeItemFromContainer(rootInventory, item, fullType) then return true end
    if rootInventory and rootInventory.RemoveOneOf and fullType then
        local before = bbm_containerExactCount(rootInventory, fullType)
        if before > 0 then
            local ok = pcall(function() rootInventory:RemoveOneOf(fullType, true) end)
            if ok and bbm_containerExactCount(rootInventory, fullType) < before then return true end
            before = bbm_containerExactCount(rootInventory, fullType)
            ok = pcall(function() rootInventory:RemoveOneOf(fullType, false) end)
            if ok and bbm_containerExactCount(rootInventory, fullType) < before then return true end
        end
    end
    return false
end

local function bbm_removeOneExactType(rootInventory, fullType)
    if not (rootInventory and fullType) then return false end
    if rootInventory.RemoveOneOf then
        local before = bbm_containerExactCount(rootInventory, fullType)
        if before > 0 then
            local ok = pcall(function() rootInventory:RemoveOneOf(fullType, true) end)
            if ok and bbm_containerExactCount(rootInventory, fullType) < before then return true end
            before = bbm_containerExactCount(rootInventory, fullType)
            ok = pcall(function() rootInventory:RemoveOneOf(fullType, false) end)
            if ok and bbm_containerExactCount(rootInventory, fullType) < before then return true end
        end
    end
    local item = bbm_firstExactItem(rootInventory, fullType)
    if item then return bbm_removeItemObject(item, rootInventory, nil) end
    return false
end

local function bbm_takeExactContainerFallback(player, resourceKey, res, rootInventory, amount, alreadyRemoved)
    local removed = math.floor(tonumber(alreadyRemoved) or 0)
    amount = math.floor(tonumber(amount) or 0)
    if removed >= amount then return removed end
    if not (rootInventory and res and type(res.items) == "table") then return removed end

    local rows = {}
    for _, fullType in ipairs(res.items) do
        local count = bbm_containerExactCount(rootInventory, fullType)
        if count > 0 then
            local first = bbm_firstExactItem(rootInventory, fullType)
            local unitValue = bbm_fullTypeUnitValue(resourceKey, fullType)
            if first then
                local _, firstUnitValue = bbm_resourceUnits(resourceKey, first)
                unitValue = math.max(unitValue, firstUnitValue or 1)
            end
            rows[#rows + 1] = { fullType = fullType, count = count, unitValue = unitValue, first = first }
        end
    end
    table.sort(rows, function(a, b)
        local need = amount - removed
        local ae = math.abs((tonumber(a.unitValue) or 1) - need)
        local be = math.abs((tonumber(b.unitValue) or 1) - need)
        if ae == be then return tostring(a.fullType or "") < tostring(b.fullType or "") end
        return ae < be
    end)

    for _, row in ipairs(rows) do
        if removed < amount and row.first then
            local units, unitValue, stack = bbm_resourceUnits(resourceKey, row.first)
            local need = amount - removed
            if units > need and stack > 1 then
                local stackNeed = math.max(1, math.ceil(need / math.max(1, unitValue)))
                local ok, takenStacks = bbm_decreaseStack(row.first, stackNeed)
                if ok then
                    removed = removed + (takenStacks * math.max(1, unitValue))
                    row.count = math.max(0, (tonumber(row.count) or 0) - takenStacks)
                end
            end
        end
        while removed < amount and (tonumber(row.count) or 0) > 0 do
            if bbm_removeOneExactType(rootInventory, row.fullType) then
                removed = removed + math.max(1, math.floor(tonumber(row.unitValue) or 1))
                row.count = (tonumber(row.count) or 0) - 1
            else
                break
            end
        end
        if removed >= amount then break end
    end
    return removed
end

function NPCBlackMarketBridge.TakeItems(player, resourceKey, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    resourceKey = tostring(resourceKey or "")
    local res = BBM_RESOURCES[resourceKey]
    if not (player and res and type(res.items) == "table" and player.getInventory) then return false end
    if NPCBlackMarketBridge.CountItems(player, resourceKey) < amount then return false end

    -- Stage 382: mirror mercenary hiring payment removal for valuables.
    if resourceKey == "gold" or resourceKey == "silver" then
        return bbm_blackMarketRemovePayment(player, res.items, amount, resourceKey)
    end

    local inv = player:getInventory()
    local removed = 0
    local seen = {}
    local candidates = {}
    for _, item in ipairs(bbm_scanPlayerItems(player)) do
        if item and not seen[item] and bbm_resourceMatchesItem(resourceKey, res, item) then
            seen[item] = true
            candidates[#candidates + 1] = item
        end
    end
    table.sort(candidates, function(a, b)
        local ac = bbm_resourceUnits(resourceKey, a)
        local bc = bbm_resourceUnits(resourceKey, b)
        if ac == bc then return tostring(bbm_itemFullType(a) or "") < tostring(bbm_itemFullType(b) or "") end
        return ac < bc
    end)

    for _, item in ipairs(candidates) do
        if removed >= amount then break end
        local units, unitValue, stack = bbm_resourceUnits(resourceKey, item)
        local need = amount - removed
        if units > need and stack > 1 then
            local stackNeed = math.max(1, math.ceil(need / math.max(1, unitValue)))
            local ok, takenStacks = bbm_decreaseStack(item, stackNeed)
            if ok then removed = removed + (takenStacks * math.max(1, unitValue)) end
        elseif units > need then
            if bbm_removeItemObject(item, inv, player) then removed = removed + units end
        else
            if bbm_removeItemObject(item, inv, player) then removed = removed + units end
        end
    end

    if removed < amount then
        removed = bbm_takeExactContainerFallback(player, resourceKey, res, inv, amount, removed)
    end
    return removed >= amount
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
    marker.blackMarketHasPendingReward = contact.blackMarketHasPendingReward == true or nil
    marker.blackMarketQuestTurnInHighlight = contact.blackMarketQuestTurnInHighlight == true or nil
    marker.blackMarketRewardX = contact.blackMarketRewardX
    marker.blackMarketRewardY = contact.blackMarketRewardY
    marker.blackMarketRewardZ = contact.blackMarketRewardZ
    marker.blackMarketRewardHighlight = contact.blackMarketHasPendingReward == true or nil
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
    local protectedContacts = {}
    if type(data.fetchQuests) == "table" then
        for _, quest in pairs(data.fetchQuests) do
            if type(quest) == "table" and quest.status == "active" and quest.contactId then
                protectedContacts[tostring(quest.contactId)] = true
            end
        end
    end
    if type(data.defenseQuests) == "table" then
        for _, quest in pairs(data.defenseQuests) do
            if type(quest) == "table" and quest.status == "active" and quest.contactId then
                protectedContacts[tostring(quest.contactId)] = true
            end
        end
    end
    local removed = 0
    for id, contact in pairs(data.contacts) do
        if type(contact) == "table" and protectedContacts[tostring(id)] then
            contact.expiresAt = math.max(tonumber(contact.expiresAt) or 0, now + 1)
        elseif type(contact) ~= "table" or (contact.expiresAt and now >= tonumber(contact.expiresAt)) or contact.blackMarketStatus == "closed" then
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
