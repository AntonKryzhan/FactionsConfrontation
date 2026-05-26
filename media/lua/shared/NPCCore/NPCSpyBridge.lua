-- NPCSpyBridge.lua
-- Neutral shared backend for spy/counter-intel, defection, sabotage and spy-intel markers.

NPCSpyBridge = NPCSpyBridge or {}

NPCSpyBridge.GoldJewelry = NPCSpyBridge.GoldJewelry or {
    "Base.Ring_Right_MiddleFinger_Gold", "Base.Ring_Left_MiddleFinger_Gold",
    "Base.Ring_Right_RingFinger_Gold", "Base.Ring_Left_RingFinger_Gold",
    "Base.Ring_Right_MiddleFinger_GoldDiamond", "Base.Ring_Left_MiddleFinger_GoldDiamond",
    "Base.Ring_Right_RingFinger_GoldDiamond", "Base.Ring_Left_RingFinger_GoldDiamond",
    "Base.Necklace_Gold", "Base.Necklace_GoldRuby", "Base.Necklace_GoldDiamond",
    "Base.NecklaceLong_GoldDiamond", "Base.Bracelet_ChainRightGold", "Base.Bracelet_ChainLeftGold",
    "Base.Bracelet_BangleRightGold", "Base.Bracelet_BangleLeftGold",
    "Base.Earring_LoopLrg_Gold", "Base.Earring_LoopMed_Gold", "Base.Earring_LoopSmall_Gold",
    "Base.WristWatch_Left_ClassicGold", "Base.WristWatch_Right_ClassicGold"
}

NPCSpyBridge.SilverJewelry = NPCSpyBridge.SilverJewelry or {
    "Base.Ring_Right_MiddleFinger_Silver", "Base.Ring_Left_MiddleFinger_Silver",
    "Base.Ring_Right_RingFinger_Silver", "Base.Ring_Left_RingFinger_Silver",
    "Base.Necklace_Silver", "Base.Necklace_SilverSapphire", "Base.Necklace_SilverCrucifix",
    "Base.Bracelet_ChainRightSilver", "Base.Bracelet_ChainLeftSilver",
    "Base.Bracelet_BangleRightSilver", "Base.Bracelet_BangleLeftSilver",
    "Base.Earring_LoopLrg_Silver", "Base.Earring_LoopMed_Silver", "Base.Earring_LoopSmall_Silver",
    "Base.WristWatch_Left_ClassicSilver", "Base.WristWatch_Right_ClassicSilver"
}

local function bs_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        return NPCLegacySettingsBridge.GetBool(name, defaultValue == true)
    end
    return defaultValue == true
end

local function bs_num(name, defaultValue, minValue, maxValue)
    local value = defaultValue
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        value = NPCLegacySettingsBridge.GetNumber(name, defaultValue, minValue, maxValue)
    end
    value = tonumber(value) or tonumber(defaultValue) or 0
    if minValue ~= nil and value < minValue then value = minValue end
    if maxValue ~= nil and value > maxValue then value = maxValue end
    return value
end

local function bs_worldHours()
    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then
            local ok, value = pcall(function() return gt:getWorldAgeHours() end)
            if ok and value then return tonumber(value) or 0 end
        end
    end
    return 0
end

local function bs_rand(maxValue)
    maxValue = math.floor(tonumber(maxValue) or 0)
    if maxValue <= 0 then return 0 end
    if ZombRand then return ZombRand(maxValue) end
    return math.random(0, maxValue - 1)
end

local function bs_same(a, b)
    if a == nil or b == nil then return false end
    return tostring(a) == tostring(b)
end

local function bs_side(value)
    if NPCFactionBridge and NPCFactionBridge.NormalizeSide then
        local side = NPCFactionBridge.NormalizeSide(value)
        if side then return side end
    end
    value = tostring(value or ""):lower()
    if value == "friendly" then return "green" end
    if value == "hostile" then return "red" end
    if value == "red" or value == "green" or value == "blue" or value == "black" then return value end
    return nil
end

local function bs_dist(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return math.sqrt(dx * dx + dy * dy)
end

local function bs_tableHasRows(t)
    if type(t) ~= "table" then return false end
    for _, _ in pairs(t) do return true end
    return false
end

local function bs_baseSide(base)
    if not base then return nil end
    return bs_side(base.owner or base.captureTeam or base.factionSide or base.faction or base.side)
end

local function bs_groupSide(group)
    if not group then return nil end
    return bs_side(group.factionSide or group.faction or group.side or group.patrolColor)
end

local function bs_brainPosition(brain)
    if not brain then return nil, nil, nil end
    local coords = brain.debugCoords or brain.bornCoords or brain.lastKnownPosition or {}
    local x = brain.x or coords.x or (brain.order and brain.order.anchor and brain.order.anchor.x)
    local y = brain.y or coords.y or (brain.order and brain.order.anchor and brain.order.anchor.y)
    local z = brain.z or coords.z or (brain.order and brain.order.anchor and brain.order.anchor.z) or 0
    return tonumber(x), tonumber(y), tonumber(z) or 0
end

local function bs_groupPosition(group)
    if not group then return nil, nil, nil end
    local x = group.x or group.cx or (group.anchor and group.anchor.x)
    local y = group.y or group.cy or (group.anchor and group.anchor.y)
    local z = group.z or group.cz or (group.anchor and group.anchor.z) or 0
    return tonumber(x), tonumber(y), tonumber(z) or 0
end

local function bs_baseName(base)
    return tostring(base and (base.name or base.title or base.baseName or ("Base " .. tostring(base.id or "?"))) or "base")
end

function NPCSpyBridge.IsEnabled()
    return bs_bool("Spy_Enabled", true)
end

function NPCSpyBridge.IsSabotageEnabled()
    return NPCSpyBridge.IsEnabled() and bs_bool("Spy_SabotageEnabled", true)
end

function NPCSpyBridge.IsCounterIntelEnabled()
    return NPCSpyBridge.IsEnabled() and bs_bool("Spy_CounterIntelEnabled", true)
end

function NPCSpyBridge.ShowMarkers()
    return NPCSpyBridge.IsEnabled() and bs_bool("Spy_ShowMarkers", true)
end

function NPCSpyBridge.PlayerId(player)
    if not player then return nil end
    if NPCUtils and NPCUtils.GetCharacterID then
        local ok, id = pcall(function() return NPCUtils.GetCharacterID(player) end)
        if ok and id ~= nil then return tostring(id) end
    end
    if player.getOnlineID then
        local ok, id = pcall(function() return player:getOnlineID() end)
        if ok and id ~= nil then return tostring(id) end
    end
    return nil
end

function NPCSpyBridge.PlayerName(player)
    if not player then return nil end
    if player.getUsername then
        local ok, value = pcall(function() return player:getUsername() end)
        if ok and value then return tostring(value) end
    end
    if player.getDisplayName then
        local ok, value = pcall(function() return player:getDisplayName() end)
        if ok and value then return tostring(value) end
    end
    return "player"
end

function NPCSpyBridge.GetBrainSide(brain)
    if NPCFactionBridge and NPCFactionBridge.GetBrainSide then
        return NPCFactionBridge.GetBrainSide(brain)
    end
    return brain and (brain.factionSide or brain.faction or brain.side or brain.patrolColor) or nil
end

function NPCSpyBridge.GetPlayerSide(player)
    if NPCFactionBridge and NPCFactionBridge.GetPlayerSide then
        local ok, side = pcall(function() return NPCFactionBridge.GetPlayerSide(player) end)
        if ok and side then return side end
    end
    return "blue"
end

function NPCSpyBridge.IsSpyBrain(brain)
    return brain and brain.spy == true and brain.spyDefected ~= true
end

function NPCSpyBridge.IsDefectedBrain(brain)
    return brain and brain.spy == true and brain.spyDefected == true
end

function NPCSpyBridge.CanBribeBrain(brain, player)
    if not NPCSpyBridge.IsEnabled() then return false end
    if not brain or brain.spy == true or brain.spyDefected == true then return false end
    if brain.mercenaryHired == true then return false end
    if not player then return false end
    local pSide = NPCSpyBridge.GetPlayerSide(player)
    local bSide = NPCSpyBridge.GetBrainSide(brain)
    if pSide == "blue" and (bSide == "red" or bSide == "green") then return true end
    if pSide and bSide and tostring(pSide) == tostring(bSide) then return false end
    if NPCFactionBridge and NPCFactionBridge.CanBrainAttackPlayer then
        local ok, hostile = pcall(function() return NPCFactionBridge.CanBrainAttackPlayer(brain, player) end)
        if ok and hostile then return true end
    end
    if brain.hostile == true then return true end
    if pSide and bSide and NPCFactionBridge and NPCFactionBridge.IsEnemySide then
        local ok, hostile = pcall(function() return NPCFactionBridge.IsEnemySide(bSide, pSide) end)
        if ok and hostile then return true end
    end
    return false
end

local function bs_makeTypeSet(itemTypes)
    local set = {}
    for _, fullType in ipairs(itemTypes or {}) do
        set[tostring(fullType)] = true
        local tail = tostring(fullType):match("%.([^%.]+)$")
        if tail then set[tail] = true end
    end
    return set
end

local function bs_itemText(item)
    if not item then return "" end
    local parts = {}
    local methods = {"getFullType", "getType", "getName", "getDisplayName"}
    for _, method in ipairs(methods) do
        if item[method] then
            local ok, value = pcall(function() return item[method](item) end)
            if ok and value then parts[#parts + 1] = tostring(value) end
        end
    end
    return string.lower(table.concat(parts, " "))
end

local function bs_itemFullType(item)
    if not item then return nil end
    if item.getFullType then
        local ok, value = pcall(function() return item:getFullType() end)
        if ok and value then return tostring(value) end
    end
    if item.getType then
        local ok, value = pcall(function() return item:getType() end)
        if ok and value then return tostring(value) end
    end
    return nil
end

local function bs_itemUniqueKey(item, fallback)
    if not item then return tostring(fallback or "nil") end
    if item.getID then
        local ok, value = pcall(function() return item:getID() end)
        if ok and value ~= nil then return "id:" .. tostring(value) end
    end
    return tostring(item) .. ":" .. tostring(fallback or "")
end

local function bs_isGoldText(text)
    text = tostring(text or ""):lower()
    return text:find("gold", 1, true) ~= nil or text:find("золот", 1, true) ~= nil
end

local function bs_isSilverText(text)
    text = tostring(text or ""):lower()
    return text:find("silver", 1, true) ~= nil or text:find("сереб", 1, true) ~= nil
end

local function bs_isJewelryText(text)
    text = tostring(text or ""):lower()
    if text:find("ring", 1, true) or text:find("necklace", 1, true) or text:find("bracelet", 1, true) or text:find("earring", 1, true) or text:find("wristwatch", 1, true) then return true end
    if text:find("кольц", 1, true) or text:find("цеп", 1, true) or text:find("брасл", 1, true) or text:find("серь", 1, true) or text:find("украшен", 1, true) or text:find("часы", 1, true) then return true end
    return false
end

local function bs_isPaymentItem(item, itemTypes, kind)
    local set = bs_makeTypeSet(itemTypes)
    local fullType = bs_itemFullType(item)
    if fullType and set[fullType] then return true end
    if fullType and set[tostring(fullType):match("%.([^%.]+)$") or ""] then return true end
    local text = bs_itemText(item)
    if kind == "gold" then return bs_isGoldText(text) and bs_isJewelryText(text) end
    if kind == "silver" then return bs_isSilverText(text) and bs_isJewelryText(text) end
    return false
end

local function bs_collectContainerItems(container, out, seen)
    out = out or {}
    seen = seen or {}
    if not container then return out end
    local items = nil
    if container.getItems then
        local ok, value = pcall(function() return container:getItems() end)
        if ok then items = value end
    end
    if not items then return out end
    local size = 0
    pcall(function() size = items:size() end)
    for i = 0, size - 1 do
        local item = nil
        pcall(function() item = items:get(i) end)
        if item then
            local key = bs_itemUniqueKey(item, i)
            if not seen[key] then
                seen[key] = true
                out[#out + 1] = item
                if item.getInventory then
                    local okInv, sub = pcall(function() return item:getInventory() end)
                    if okInv and sub then bs_collectContainerItems(sub, out, seen) end
                end
            end
        end
    end
    return out
end

local function bs_countItems(inv, itemTypes, kind)
    if not inv then return 0 end
    local exact = 0
    for _, fullType in ipairs(itemTypes or {}) do
        local ok, count = pcall(function() return inv:getItemCountFromTypeRecurse(fullType) end)
        if ok and count then exact = exact + (tonumber(count) or 0) end
    end

    local tolerant = 0
    local items = bs_collectContainerItems(inv, {}, {})
    for _, item in ipairs(items) do
        if bs_isPaymentItem(item, itemTypes, kind) then tolerant = tolerant + 1 end
    end
    return math.max(exact, tolerant)
end

local function bs_removeExactItems(inv, itemTypes, count)
    if not inv then return 0 end
    local removedCount = 0
    local remaining = tonumber(count) or 0
    for _, fullType in ipairs(itemTypes or {}) do
        while remaining > 0 do
            local before = 0
            local okCount, countBefore = pcall(function() return inv:getItemCountFromTypeRecurse(fullType) end)
            if okCount then before = tonumber(countBefore) or 0 end
            if before <= 0 then break end

            local removed = false
            pcall(function() removed = inv:RemoveOneOf(fullType, true) end)
            if not removed then pcall(function() removed = inv:RemoveOneOf(fullType, false) end) end
            local after = before
            local okAfter, countAfter = pcall(function() return inv:getItemCountFromTypeRecurse(fullType) end)
            if okAfter then after = tonumber(countAfter) or before end
            if removed or after < before then
                removedCount = removedCount + 1
                remaining = remaining - 1
            else
                break
            end
        end
        if remaining <= 0 then break end
    end
    return removedCount
end

local function bs_removeObjectItem(inv, item)
    if not item then return false end
    local containers = {}
    if item.getContainer then
        local ok, c = pcall(function() return item:getContainer() end)
        if ok and c then containers[#containers + 1] = c end
    end
    if inv then containers[#containers + 1] = inv end
    for _, container in ipairs(containers) do
        if container and container.Remove then
            local ok = pcall(function() container:Remove(item) end)
            if ok then return true end
        end
    end
    return false
end

local function bs_removeItems(inv, itemTypes, count, kind)
    if not inv then return false end
    local remaining = tonumber(count) or 0
    if remaining <= 0 then return true end

    local removed = bs_removeExactItems(inv, itemTypes, remaining)
    remaining = remaining - removed
    if remaining <= 0 then return true end

    local items = bs_collectContainerItems(inv, {}, {})
    for _, item in ipairs(items) do
        if remaining <= 0 then break end
        if bs_isPaymentItem(item, itemTypes, kind) and bs_removeObjectItem(inv, item) then
            remaining = remaining - 1
        end
    end
    return remaining <= 0
end

function NPCSpyBridge.CountPayment(player)
    local out = {gold=0, silver=0}
    if not (player and player.getInventory) then return out end
    local inv = player:getInventory()
    out.gold = bs_countItems(inv, NPCSpyBridge.GoldJewelry, "gold")
    out.silver = bs_countItems(inv, NPCSpyBridge.SilverJewelry, "silver")
    return out
end

function NPCSpyBridge.GetPaymentLabel()
    local gold = bs_num("Spy_GoldJewelryCost", 1, 0, 100)
    local silver = bs_num("Spy_SilverJewelryCost", 3, 0, 300)
    if bs_bool("Spy_AllowSilverPayment", true) then
        return tostring(gold) .. " gold jewelry or " .. tostring(silver) .. " silver jewelry"
    end
    return tostring(gold) .. " gold jewelry"
end

function NPCSpyBridge.TakePayment(player)
    if not player or not player.getInventory then return false, "no_player" end
    local inv = player:getInventory()
    local goldCost = bs_num("Spy_GoldJewelryCost", 1, 0, 100)
    if goldCost <= 0 then return true, "free" end
    if bs_countItems(inv, NPCSpyBridge.GoldJewelry, "gold") >= goldCost then
        if bs_removeItems(inv, NPCSpyBridge.GoldJewelry, goldCost, "gold") then return true, "gold" end
    end
    if bs_bool("Spy_AllowSilverPayment", true) then
        local silverCost = bs_num("Spy_SilverJewelryCost", 3, 0, 300)
        if silverCost <= 0 then return true, "free" end
        if bs_countItems(inv, NPCSpyBridge.SilverJewelry, "silver") >= silverCost then
            if bs_removeItems(inv, NPCSpyBridge.SilverJewelry, silverCost, "silver") then return true, "silver" end
        end
    end
    return false, "not_enough"
end

function NPCSpyBridge.EnsureData(gmd)
    if not gmd then return end
    if type(gmd.SpyRegistry) ~= "table" then gmd.SpyRegistry = {} end
    if type(gmd.SpyIntel) ~= "table" then gmd.SpyIntel = {} end
    if type(gmd.SpyEvents) ~= "table" then gmd.SpyEvents = {} end
    if type(gmd.SpyStats) ~= "table" then gmd.SpyStats = {nextIntelId=1, generatedIntel=0, sabotageTicks=0} end
    gmd.SpyStats.nextIntelId = tonumber(gmd.SpyStats.nextIntelId) or 1
    gmd.SpyStats.generatedIntel = tonumber(gmd.SpyStats.generatedIntel) or 0
    gmd.SpyStats.sabotageTicks = tonumber(gmd.SpyStats.sabotageTicks) or 0
    gmd.SpyStats.counterIntelDetections = tonumber(gmd.SpyStats.counterIntelDetections) or 0
    gmd.SpyStats.elitePromotions = tonumber(gmd.SpyStats.elitePromotions) or 0
    if not gmd.DebugMapMarkers then gmd.DebugMapMarkers = {} end
end

function NPCSpyBridge.BrainKey(brain, fallback)
    if not brain then return fallback and tostring(fallback) or nil end
    return tostring(brain.uid or brain.persistentId or brain.id or brain.runtimeId or fallback or "")
end

function NPCSpyBridge.FindBaseById(gmd, baseId)
    if not (gmd and baseId) then return nil end
    local id = tostring(baseId)
    if type(gmd.BaseCamps) == "table" then
        local direct = gmd.BaseCamps[id]
        if type(direct) == "table" then return direct end
        for _, base in pairs(gmd.BaseCamps) do
            if type(base) == "table" and (bs_same(base.id, id) or bs_same(base.baseId, id) or bs_same("BASE_" .. tostring(base.id), id)) then
                return base
            end
        end
    end
    return nil
end

function NPCSpyBridge.ResolveBaseForBrain(gmd, brain)
    if not (gmd and brain) then return nil end
    local ids = {brain.homeBaseId, brain.baseId, brain.targetBaseId}
    local groupId = brain.worldGroupId or brain.groupId
    local group = groupId and gmd.VirtualGroups and gmd.VirtualGroups[tostring(groupId)] or nil
    if group then
        ids[#ids + 1] = group.homeBaseId
        ids[#ids + 1] = group.baseId
        ids[#ids + 1] = group.targetBaseId
    end
    for _, id in ipairs(ids) do
        local base = NPCSpyBridge.FindBaseById(gmd, id)
        if base then return base end
    end

    local bx, by = bs_brainPosition(brain)
    if not bx or not by then
        bx, by = bs_groupPosition(group)
    end
    if not bx or not by or type(gmd.BaseCamps) ~= "table" then return nil end

    local brainSide = bs_side(brain.spyOriginalSide or NPCSpyBridge.GetBrainSide(brain)) or bs_groupSide(group)
    local best, bestDist = nil, 999999
    for _, base in pairs(gmd.BaseCamps) do
        if type(base) == "table" and base.x and base.y then
            local side = bs_baseSide(base)
            local dist = bs_dist(bx, by, base.x, base.y)
            local radius = (tonumber(base.radius) or 80) + 220
            local sameSide = brainSide and side and tostring(side) == tostring(brainSide)
            if (sameSide or dist <= radius) and dist < bestDist then
                best = base
                bestDist = dist
            end
        end
    end
    return best
end

function NPCSpyBridge.RegisterBrain(gmd, brain, player)
    if not (gmd and brain and brain.spy == true) then return nil end
    NPCSpyBridge.EnsureData(gmd)
    local key = NPCSpyBridge.BrainKey(brain, brain.id)
    if not key or key == "" then return nil end

    local base = NPCSpyBridge.ResolveBaseForBrain(gmd, brain)
    if base then
        brain.homeBaseId = brain.homeBaseId or base.id or base.baseId
        brain.baseId = brain.baseId or base.id or base.baseId
        brain.spyBaseId = tostring(base.id or base.baseId)
    end

    local x, y, z = bs_brainPosition(brain)
    local groupId = brain.worldGroupId or brain.groupId
    local rec = gmd.SpyRegistry[key] or {}
    rec.id = key
    rec.runtimeId = brain.id or rec.runtimeId
    rec.uid = brain.uid or brain.persistentId or rec.uid
    rec.groupId = groupId and tostring(groupId) or rec.groupId
    rec.playerId = tostring(brain.spyForPlayerId or (player and NPCSpyBridge.PlayerId(player)) or rec.playerId or "")
    rec.playerName = brain.spyForPlayerName or (player and NPCSpyBridge.PlayerName(player)) or rec.playerName
    rec.originalSide = bs_side(brain.spyOriginalSide or rec.originalSide or NPCSpyBridge.GetBrainSide(brain))
    rec.baseId = brain.spyBaseId or rec.baseId
    rec.state = brain.spyState or rec.state or "infiltrating"
    rec.defected = brain.spyDefected == true
    rec.compromised = brain.spyCompromised == true or rec.compromised == true
    rec.doubleAgent = brain.spyDoubleAgent == true or rec.doubleAgent == true
    rec.captured = brain.spyCaptured == true or rec.captured == true
    rec.killed = brain.spyKilled == true or rec.killed == true
    rec.escaped = brain.spyEscaped == true or rec.escaped == true
    rec.sabotage = brain.spySabotage ~= false
    rec.recruitedAt = tonumber(brain.spyBribedAt) or tonumber(rec.recruitedAt) or bs_worldHours()
    rec.spyXp = tonumber(brain.spyXp) or tonumber(rec.spyXp) or 0
    rec.actionSuccesses = tonumber(brain.spyActionSuccesses) or tonumber(rec.actionSuccesses) or 0
    rec.suspicion = tonumber(brain.spySuspicion) or tonumber(rec.suspicion) or 0
    rec.heat = tonumber(brain.spyHeat) or tonumber(rec.heat) or 0
    rec.coverLevel = tonumber(brain.spyCoverLevel) or tonumber(rec.coverLevel) or 0
    rec.rank = brain.spyRank or rec.rank or "recruit"
    rec.elite = brain.spyElite == true or rec.elite == true or rec.rank == "elite"
    rec.x = x or rec.x
    rec.y = y or rec.y
    rec.z = z or rec.z or 0
    rec.lastSeenAt = bs_worldHours()
    rec.lastIntelAt = tonumber(brain.spyIntelLastAt) or tonumber(rec.lastIntelAt) or 0
    gmd.SpyRegistry[key] = rec
    return rec
end

function NPCSpyBridge.RegisterAll(gmd)
    if not gmd then return end
    NPCSpyBridge.EnsureData(gmd)
    if type(gmd.Queue) == "table" then
        for _, brain in pairs(gmd.Queue) do
            if type(brain) == "table" and brain.spy == true then NPCSpyBridge.RegisterBrain(gmd, brain) end
        end
    end
    if type(gmd.VirtualGroups) == "table" then
        for gid, group in pairs(gmd.VirtualGroups) do
            if type(group) == "table" and type(group.members) == "table" then
                for _, member in pairs(group.members) do
                    if type(member) == "table" and member.spy == true then
                        member.worldGroupId = member.worldGroupId or gid
                        member.groupId = member.groupId or gid
                        NPCSpyBridge.RegisterBrain(gmd, member)
                    end
                end
            end
        end
    end
end

function NPCSpyBridge.MarkBrain(brain, player, paymentKind)
    if not brain or not player then return false end
    local pid = NPCSpyBridge.PlayerId(player)
    if not pid then return false end
    brain.spy = true
    brain.spyForPlayerId = pid
    brain.spyForPlayerName = NPCSpyBridge.PlayerName(player)
    brain.spyOriginalSide = NPCSpyBridge.GetBrainSide(brain)
    brain.spyBribedAt = bs_worldHours()
    brain.spyState = "infiltrating"
    brain.spyDefected = false
    brain.spySabotage = true
    brain.spyIntel = true
    brain.spyIntelLastAt = tonumber(brain.spyIntelLastAt) or 0
    brain.spyXp = tonumber(brain.spyXp) or 0
    brain.spyActionSuccesses = tonumber(brain.spyActionSuccesses) or 0
    brain.spySuspicion = tonumber(brain.spySuspicion) or 0
    brain.spyHeat = tonumber(brain.spyHeat) or 0
    brain.spyCoverLevel = tonumber(brain.spyCoverLevel) or 0
    brain.spyRank = brain.spyRank or "recruit"
    brain.spyElite = brain.spyElite == true
    brain.spyCompromised = false
    brain.spyDoubleAgent = false
    brain.spyCaptured = false
    brain.spyKilled = false
    brain.spyEscaped = false
    brain.spyPaymentKind = paymentKind or brain.spyPaymentKind
    brain.relationshipToPlayer = "spy"
    brain.factionState = "spy"
    brain.tasks = {}
    if brain.fsm then
        brain.fsm.targetId = nil
        brain.fsm.targetKind = nil
        brain.fsm.currentThreat = nil
        brain.fsm.lastThreat = nil
    end
    brain.currentThreat = nil
    brain.lastThreat = nil
    brain.targetId = nil
    brain.targetKind = nil
    return true
end

function NPCSpyBridge.MarkGroupSpyState(gmd, groupId)
    if not (gmd and groupId) then return nil end
    NPCSpyBridge.EnsureData(gmd)
    local gid = tostring(groupId)
    local total, spies = 0, 0
    if gmd.Queue then
        for _, brain in pairs(gmd.Queue) do
            local bid = brain and (brain.worldGroupId or brain.groupId)
            if bid and tostring(bid) == gid then
                total = total + 1
                if brain.spy == true and brain.spyDefected ~= true then spies = spies + 1 end
            end
        end
    end
    local group = gmd.VirtualGroups and gmd.VirtualGroups[gid] or nil
    if group and type(group.members) == "table" then
        for _, member in pairs(group.members) do
            total = total + 1
            if member and member.spy == true and member.spyDefected ~= true then spies = spies + 1 end
        end
    end
    local allSpies = total > 0 and spies >= total
    if group then
        group.spyCount = spies
        group.spyTotal = total
        group.spy = spies > 0
        group.spyAllied = allSpies and bs_bool("Spy_AllSpiesAutoAlly", true) or false
        if allSpies then group.relationshipToPlayer = "spy_allied" end
    end
    if gmd.DebugMapMarkers and gmd.DebugMapMarkers[gid] then
        gmd.DebugMapMarkers[gid].spy = spies > 0
        gmd.DebugMapMarkers[gid].spyCount = spies
        gmd.DebugMapMarkers[gid].spyAllied = allSpies and bs_bool("Spy_AllSpiesAutoAlly", true) or false
    end
    if gmd.Queue then
        for _, brain in pairs(gmd.Queue) do
            local bid = brain and (brain.worldGroupId or brain.groupId)
            if bid and tostring(bid) == gid then
                brain.spyAlliedGroup = allSpies and bs_bool("Spy_AllSpiesAutoAlly", true) or false
                if brain.spyAlliedGroup then brain.relationshipToPlayer = "spy_allied" end
                if brain.spy == true then NPCSpyBridge.RegisterBrain(gmd, brain) end
            end
        end
    end
    return spies, total, allSpies
end

function NPCSpyBridge.ApplyMarkerFields(marker, source)
    if not marker or not source or not NPCSpyBridge.ShowMarkers() then return marker end
    if source.spy == true or (tonumber(source.spyCount) and tonumber(source.spyCount) > 0) then
        marker.spy = true
        marker.spyCount = tonumber(source.spyCount) or (source.spy and 1 or 0)
        marker.spyAllied = source.spyAllied or source.spyAlliedGroup or false
        marker.spyForPlayerId = source.spyForPlayerId
        marker.spyState = source.spyState
        marker.spyDefected = source.spyDefected or false
        marker.spyBaseId = source.spyBaseId or source.baseId or source.homeBaseId
        marker.spyRank = source.spyRank or source.rank
        marker.spyElite = source.spyElite == true or source.elite == true or source.spyRank == "elite" or source.rank == "elite"
        marker.spyCompromised = source.spyCompromised == true or source.compromised == true
        marker.spyDoubleAgent = source.spyDoubleAgent == true or source.doubleAgent == true
    end
    return marker
end

function NPCSpyBridge.ShouldHoldFireAgainstPlayer(brain, player)
    if not (brain and player) then return false end
    local pid = NPCSpyBridge.PlayerId(player)
    if not pid or tostring(brain.spyForPlayerId or "") ~= tostring(pid) then return false end
    if brain.spyCompromised == true or brain.spyDoubleAgent == true then return false end
    if brain.spy == true and brain.spyDefected ~= true then return true end
    if brain.spyDefected == true then return true end
    if brain.spyAlliedGroup == true then return true end
    return false
end

local function bs_spyRank(source)
    local rank = source and (source.spyRank or source.rank) or nil
    if rank == "elite" or source and (source.spyElite == true or source.elite == true) then return "elite" end
    if rank == "experienced" then return "experienced" end
    return "recruit"
end

local function bs_findSpyRecord(gmd, source)
    if not (gmd and source) then return nil, nil end
    NPCSpyBridge.EnsureData(gmd)
    local keys = {
        source.id, source.uid, source.persistentId, source.runtimeId,
        source.spyId, NPCSpyBridge.BrainKey(source, source.id)
    }
    for _, key in ipairs(keys) do
        if key ~= nil then
            local rec = gmd.SpyRegistry[tostring(key)]
            if type(rec) == "table" then return rec, tostring(key) end
        end
    end
    for key, rec in pairs(gmd.SpyRegistry or {}) do
        if type(rec) == "table" then
            if bs_same(rec.runtimeId, source.id) or bs_same(rec.runtimeId, source.runtimeId) or bs_same(rec.uid, source.uid) or bs_same(rec.uid, source.persistentId) then
                return rec, tostring(key)
            end
        end
    end
    return nil, nil
end

function NPCSpyBridge.FindSpyBrain(gmd, source)
    if not (gmd and source) then return nil end
    local key = NPCSpyBridge.BrainKey(source, source.id)
    if type(gmd.Queue) == "table" then
        for _, brain in pairs(gmd.Queue) do
            if type(brain) == "table" and brain.spy == true then
                if bs_same(NPCSpyBridge.BrainKey(brain, brain.id), key) or bs_same(brain.id, source.runtimeId) or bs_same(brain.id, source.id) or bs_same(brain.uid, source.uid) or bs_same(brain.persistentId, source.uid) then
                    return brain
                end
            end
        end
    end
    if type(gmd.VirtualGroups) == "table" then
        for gid, group in pairs(gmd.VirtualGroups) do
            if type(group) == "table" and type(group.members) == "table" then
                for _, member in pairs(group.members) do
                    if type(member) == "table" and member.spy == true then
                        if bs_same(NPCSpyBridge.BrainKey(member, member.id), key) or bs_same(member.id, source.runtimeId) or bs_same(member.uid, source.uid) or bs_same(member.persistentId, source.uid) then
                            member.worldGroupId = member.worldGroupId or gid
                            member.groupId = member.groupId or gid
                            return member
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function bs_setSpyValue(brain, rec, key, value)
    if type(brain) == "table" then brain[key] = value end
    if type(rec) == "table" then rec[key] = value end
end

function NPCSpyBridge.PushEvent(gmd, event)
    if not (gmd and type(event) == "table") then return end
    NPCSpyBridge.EnsureData(gmd)
    event.createdAt = event.createdAt or bs_worldHours()
    gmd.SpyEvents[#gmd.SpyEvents + 1] = event
end

function NPCSpyBridge.TakeEvents(gmd)
    if not gmd then return {} end
    NPCSpyBridge.EnsureData(gmd)
    local events = gmd.SpyEvents or {}
    gmd.SpyEvents = {}
    return events
end

local function bs_spyName(source)
    return tostring(source and (source.fullname or source.name or source.playerName or source.spyName or "spy") or "spy")
end

function NPCSpyBridge.UpdateSpyRiskAndRank(gmd, source, worldAge)
    if not (gmd and source) then return source end
    local brain = NPCSpyBridge.FindSpyBrain(gmd, source) or (source.spy == true and source or nil)
    local rec = bs_findSpyRecord(gmd, source)
    worldAge = tonumber(worldAge) or bs_worldHours()

    local lastRiskAt = tonumber(source.spyRiskUpdatedAt or source.riskUpdatedAt or rec and rec.riskUpdatedAt) or worldAge
    local dt = math.max(0, worldAge - lastRiskAt)
    if dt > 0 then
        local decay = bs_num("Spy_SuspicionDecayPerHour", 1.2, 0, 100)
        local heatDecay = bs_num("Spy_HeatDecayPerHour", 2.4, 0, 200)
        local suspicion = math.max(0, (tonumber(source.spySuspicion or source.suspicion or rec and rec.suspicion) or 0) - decay * dt)
        local heat = math.max(0, (tonumber(source.spyHeat or source.heat or rec and rec.heat) or 0) - heatDecay * dt)
        bs_setSpyValue(brain, rec, "spySuspicion", suspicion)
        bs_setSpyValue(brain, rec, "suspicion", suspicion)
        bs_setSpyValue(brain, rec, "spyHeat", heat)
        bs_setSpyValue(brain, rec, "heat", heat)
    end
    bs_setSpyValue(brain, rec, "spyRiskUpdatedAt", worldAge)
    bs_setSpyValue(brain, rec, "riskUpdatedAt", worldAge)

    local recruitedAt = tonumber(source.spyBribedAt or source.recruitedAt or rec and rec.recruitedAt) or worldAge
    local age = math.max(0, worldAge - recruitedAt)
    local successes = tonumber(source.spyActionSuccesses or source.actionSuccesses or rec and rec.actionSuccesses) or 0
    local currentRank = bs_spyRank(source)
    local rank = currentRank
    if rank ~= "elite" then
        local experiencedHours = bs_num("Spy_ExperiencedSurvivalHours", 24, 1, 10000)
        local eliteHours = bs_num("Spy_EliteSurvivalHours", 72, 1, 10000)
        local experiencedActions = bs_num("Spy_ExperiencedActionSuccesses", 4, 0, 10000)
        local eliteActions = bs_num("Spy_EliteActionSuccesses", 10, 0, 10000)
        if age >= eliteHours or successes >= eliteActions then
            rank = "elite"
        elseif age >= experiencedHours or successes >= experiencedActions then
            rank = "experienced"
        end
    end
    local becameElite = currentRank ~= "elite" and rank == "elite"
    bs_setSpyValue(brain, rec, "spyRank", rank)
    bs_setSpyValue(brain, rec, "rank", rank)
    bs_setSpyValue(brain, rec, "spyElite", rank == "elite")
    bs_setSpyValue(brain, rec, "elite", rank == "elite")
    if rank == "experienced" then
        local cover = math.max(tonumber(source.spyCoverLevel or source.coverLevel or rec and rec.coverLevel) or 0, 12)
        bs_setSpyValue(brain, rec, "spyCoverLevel", cover)
        bs_setSpyValue(brain, rec, "coverLevel", cover)
    elseif rank == "elite" then
        local cover = math.max(tonumber(source.spyCoverLevel or source.coverLevel or rec and rec.coverLevel) or 0, 28)
        bs_setSpyValue(brain, rec, "spyCoverLevel", cover)
        bs_setSpyValue(brain, rec, "coverLevel", cover)
    end
    if becameElite then
        gmd.SpyStats.elitePromotions = (tonumber(gmd.SpyStats.elitePromotions) or 0) + 1
        NPCSpyBridge.PushEvent(gmd, {
            kind = "elite",
            playerId = tostring(source.spyForPlayerId or source.playerId or rec and rec.playerId or ""),
            spyId = tostring(source.id or source.uid or rec and rec.id or ""),
            message = "Spy became elite: " .. bs_spyName(source)
        })
    end
    return brain or rec or source
end

local function bs_counterIntelSecurity(base)
    if type(base) ~= "table" then return 0 end
    local direct = tonumber(base.counterIntelLevel or base.securityReadiness or base.securityLevel)
    if direct then
        if direct <= 1 then return direct * 12 end
        return math.min(18, direct)
    end
    local total, count = 0, 0
    for _, key in ipairs({"garrisonReadiness", "defenseReadiness", "logisticsReadiness", "ammoReadiness"}) do
        local value = tonumber(base[key])
        if value then
            if value <= 1 then value = value * 10 end
            total = total + value
            count = count + 1
        end
    end
    if count <= 0 then return 0 end
    return math.min(14, total / count)
end

local function bs_actionFailureBase(actionName)
    if actionName == "sabotage" then return bs_num("Spy_SabotageFailureChance", 14, 0, 100) end
    if actionName == "radio" then return bs_num("Spy_RadioFailureChance", 8, 0, 100) end
    return bs_num("Spy_IntelFailureChance", 5, 0, 100)
end

function NPCSpyBridge.GetActionFailureChance(gmd, source, actionName, context)
    if not NPCSpyBridge.IsCounterIntelEnabled() then return 0 end
    local base = context and context.base or NPCSpyBridge.ResolveBaseForBrain(gmd, source)
    local suspicion = tonumber(source.spySuspicion or source.suspicion) or 0
    local heat = tonumber(source.spyHeat or source.heat) or 0
    local cover = tonumber(source.spyCoverLevel or source.coverLevel) or 0
    local chance = bs_actionFailureBase(actionName) + (suspicion * 0.22) + (heat * 0.18) + bs_counterIntelSecurity(base) - (cover * 0.12)
    local rank = bs_spyRank(source)
    if rank == "experienced" then chance = chance * 0.75 end
    if rank == "elite" then chance = chance * bs_num("Spy_EliteDetectionChanceMultiplier", 0.45, 0.05, 1.0) end
    if chance < 0 then chance = 0 end
    if chance > 95 then chance = 95 end
    return chance
end

local function bs_applySpyLoss(brain, rec, outcome, actionName)
    local state = outcome or "captured"
    bs_setSpyValue(brain, rec, "spyCompromised", true)
    bs_setSpyValue(brain, rec, "compromised", true)
    bs_setSpyValue(brain, rec, "spyDetectedAt", bs_worldHours())
    bs_setSpyValue(brain, rec, "detectedAt", bs_worldHours())
    bs_setSpyValue(brain, rec, "spyDetectedByAction", actionName)
    bs_setSpyValue(brain, rec, "detectedByAction", actionName)
    bs_setSpyValue(brain, rec, "spyState", state)
    bs_setSpyValue(brain, rec, "state", state)
    if state == "double_agent" then
        bs_setSpyValue(brain, rec, "spyDoubleAgent", true)
        bs_setSpyValue(brain, rec, "doubleAgent", true)
        bs_setSpyValue(brain, rec, "spySabotage", false)
        bs_setSpyValue(brain, rec, "sabotage", false)
        return
    end
    bs_setSpyValue(brain, rec, "spy", false)
    bs_setSpyValue(brain, rec, "spySabotage", false)
    bs_setSpyValue(brain, rec, "spyIntel", false)
    bs_setSpyValue(brain, rec, "sabotage", false)
    bs_setSpyValue(brain, rec, "inactive", true)
    if state == "captured" then bs_setSpyValue(brain, rec, "spyCaptured", true); bs_setSpyValue(brain, rec, "captured", true) end
    if state == "killed" then bs_setSpyValue(brain, rec, "spyKilled", true); bs_setSpyValue(brain, rec, "killed", true) end
    if state == "escaped" then bs_setSpyValue(brain, rec, "spyEscaped", true); bs_setSpyValue(brain, rec, "escaped", true) end
end

function NPCSpyBridge.ResolveDetectedSpy(gmd, source, actionName, context)
    if not (gmd and source) then return false end
    NPCSpyBridge.EnsureData(gmd)
    local brain = NPCSpyBridge.FindSpyBrain(gmd, source) or (source.spy == true and source or nil)
    local rec = bs_findSpyRecord(gmd, source)
    local doubleChance = bs_num("Spy_DoubleAgentChance", 12, 0, 100)
    local captureChance = bs_num("Spy_CaptureChance", 42, 0, 100)
    local deathChance = bs_num("Spy_DeathChance", 18, 0, 100)
    local roll = bs_rand(100)
    local outcome = "escaped"
    if roll < doubleChance then outcome = "double_agent"
    elseif roll < doubleChance + captureChance then outcome = "captured"
    elseif roll < doubleChance + captureChance + deathChance then outcome = "killed" end
    bs_applySpyLoss(brain, rec, outcome, actionName)
    gmd.SpyStats.counterIntelDetections = (tonumber(gmd.SpyStats.counterIntelDetections) or 0) + 1
    local label = outcome == "double_agent" and "turned double agent" or outcome
    NPCSpyBridge.PushEvent(gmd, {
        kind = "detected",
        outcome = outcome,
        action = actionName,
        playerId = tostring(source.spyForPlayerId or source.playerId or rec and rec.playerId or ""),
        spyId = tostring(source.id or source.uid or rec and rec.id or ""),
        message = "Spy compromised during " .. tostring(actionName or "operation") .. ": " .. label .. "."
    })
    return true
end

function NPCSpyBridge.TrySpyAction(gmd, source, actionName, context)
    if not (NPCSpyBridge.IsEnabled() and gmd and source) then return true end
    if source.spyDefected == true or source.defected == true then return false end
    if source.spyCompromised == true or source.compromised == true then return source.spyDoubleAgent == true or source.doubleAgent == true end
    local worldAge = bs_worldHours()
    local spy = NPCSpyBridge.UpdateSpyRiskAndRank(gmd, source, worldAge) or source
    local chance = NPCSpyBridge.GetActionFailureChance(gmd, spy, actionName, context)
    if chance > 0 and bs_rand(10000) < math.floor(chance * 100) then
        NPCSpyBridge.ResolveDetectedSpy(gmd, spy, actionName, context)
        return false
    end
    local suspicionGain = actionName == "sabotage" and bs_num("Spy_SabotageSuspicionGain", 18, 0, 100) or actionName == "radio" and bs_num("Spy_RadioSuspicionGain", 8, 0, 100) or bs_num("Spy_IntelSuspicionGain", 6, 0, 100)
    local heatGain = actionName == "sabotage" and bs_num("Spy_SabotageHeatGain", 12, 0, 100) or actionName == "radio" and bs_num("Spy_RadioHeatGain", 5, 0, 100) or bs_num("Spy_IntelHeatGain", 3, 0, 100)
    local rank = bs_spyRank(spy)
    if rank == "elite" then
        suspicionGain = suspicionGain * 0.45
        heatGain = heatGain * 0.45
    elseif rank == "experienced" then
        suspicionGain = suspicionGain * 0.70
        heatGain = heatGain * 0.70
    end
    local brain = NPCSpyBridge.FindSpyBrain(gmd, spy) or (spy.spy == true and spy or nil)
    local rec = bs_findSpyRecord(gmd, spy)
    local successes = (tonumber(spy.spyActionSuccesses or spy.actionSuccesses or rec and rec.actionSuccesses) or 0) + 1
    local xpGain = actionName == "sabotage" and 3 or 1
    local xp = (tonumber(spy.spyXp or rec and rec.spyXp) or 0) + xpGain
    local suspicion = math.min(100, (tonumber(spy.spySuspicion or spy.suspicion or rec and rec.suspicion) or 0) + suspicionGain)
    local heat = math.min(100, (tonumber(spy.spyHeat or spy.heat or rec and rec.heat) or 0) + heatGain)
    local cover = math.min(60, (tonumber(spy.spyCoverLevel or spy.coverLevel or rec and rec.coverLevel) or 0) + bs_num("Spy_CoverGainPerSuccess", 1.5, 0, 20))
    bs_setSpyValue(brain, rec, "spyActionSuccesses", successes)
    bs_setSpyValue(brain, rec, "actionSuccesses", successes)
    bs_setSpyValue(brain, rec, "spyXp", xp)
    bs_setSpyValue(brain, rec, "spySuspicion", suspicion)
    bs_setSpyValue(brain, rec, "suspicion", suspicion)
    bs_setSpyValue(brain, rec, "spyHeat", heat)
    bs_setSpyValue(brain, rec, "heat", heat)
    bs_setSpyValue(brain, rec, "spyCoverLevel", cover)
    bs_setSpyValue(brain, rec, "coverLevel", cover)
    bs_setSpyValue(brain, rec, "spyLastActionAt", worldAge)
    bs_setSpyValue(brain, rec, "lastActionAt", worldAge)
    bs_setSpyValue(brain, rec, "lastAction", actionName)
    NPCSpyBridge.UpdateSpyRiskAndRank(gmd, brain or rec or spy, worldAge)
    return true
end

local function bs_applyDefection(brain, player, reason)
    local pid = NPCSpyBridge.PlayerId(player)
    if not (brain and pid) then return false end
    brain.spy = true
    brain.spyDefected = true
    brain.spyState = "defected"
    brain.spyDefectedAt = bs_worldHours()
    brain.relationshipToPlayer = "ally"
    brain.factionState = "defected"
    brain.hostile = false
    brain.master = pid
    local side = NPCSpyBridge.GetPlayerSide(player) or "blue"
    if NPCFactionBridge and NPCFactionBridge.SetBrainSide then
        pcall(function() NPCFactionBridge.SetBrainSide(brain, side, "spy_defection") end)
    else
        brain.factionSide = side
        brain.faction = side
        brain.side = side
        brain.patrolColor = side
    end
    brain.order = brain.order or {}
    brain.order.name = brain.order.name or "GuardPlayer"
    brain.order.fireMode = "FireAtWill"
    brain.order.formation = brain.order.formation or "close"
    brain.order.master = pid
    brain.order.updatedAt = bs_worldHours()
    brain.program = brain.program or {}
    if brain.program.name ~= "Companion" and brain.program.name ~= "CompanionGuard" then
        brain.program.name = "CompanionGuard"
        brain.program.stage = "Prepare"
    end
    if brain.fsm then
        brain.fsm.targetId = nil
        brain.fsm.targetKind = nil
        brain.fsm.currentThreat = nil
        brain.fsm.lastThreat = nil
        brain.fsm.lastKnownEnemyPosition = nil
    end
    brain.currentThreat = nil
    brain.lastThreat = nil
    brain.targetId = nil
    brain.targetKind = nil
    brain.spyDefectionReason = reason or "combat"
    return true
end

function NPCSpyBridge.TryDefectToPlayer(bandit, brain, player, reason)
    if not NPCSpyBridge.IsEnabled() then return false end
    if not (brain and brain.spy == true and brain.spyDefected ~= true and player) then return false end
    local pid = NPCSpyBridge.PlayerId(player)
    if not pid or tostring(brain.spyForPlayerId or "") ~= tostring(pid) then return false end
    if not bs_applyDefection(brain, player, reason) then return false end
    if bandit then
        pcall(function()
            if NPCEntity and NPCEntity.ClearTasks then NPCEntity.ClearTasks(bandit) end
            if NPCBrainData and NPCBrainData.Update then NPCBrainData.Update(bandit, brain) end
            if NPCEntity and NPCEntity.ForceSyncPart then
                NPCEntity.ForceSyncPart(bandit, {
                    id = brain.id,
                    hostile = brain.hostile,
                    master = brain.master,
                    program = brain.program,
                    order = brain.order,
                    relationshipToPlayer = brain.relationshipToPlayer,
                    factionSide = brain.factionSide,
                    faction = brain.faction,
                    side = brain.side,
                    patrolColor = brain.patrolColor,
                    factionState = brain.factionState,
                    spy = brain.spy,
                    spyState = brain.spyState,
                    spyDefected = brain.spyDefected,
                    spyForPlayerId = brain.spyForPlayerId
                })
            end
        end)
    end
    return true
end

function NPCSpyBridge.TryDefectOnThreat(bandit, brain, threat)
    if not (threat and threat.kind == "player" and brain and brain.spy == true) then return false end
    if not (NPCPlayerClient and NPCPlayerClient.GetPlayerById) then return false end
    local tid = threat.id or threat.targetId or threat.eid
    local player = NPCPlayerClient.GetPlayerById(tid)
    if not player then return false end
    return NPCSpyBridge.TryDefectToPlayer(bandit, brain, player, "combat_contact")
end

function NPCSpyBridge.DistortRadioContact(brain, x, y, z, kind)
    if not (NPCSpyBridge.IsSabotageEnabled() and brain and brain.spy == true and brain.spyDefected ~= true and brain.spyCompromised ~= true) then return x, y, z, 1 end
    local chance = bs_num("Spy_FalseRadioChance", 35, 0, 100)
    if chance <= 0 or bs_rand(100) >= chance then return x, y, z, 1 end
    local gmd = GetNPCModData and GetNPCModData() or nil
    if gmd and NPCSpyBridge.TrySpyAction and not NPCSpyBridge.TrySpyAction(gmd, brain, "radio", {}) then return x, y, z, 1 end
    local radius = 8 + bs_rand(23)
    local sx = bs_rand(2) == 0 and -1 or 1
    local sy = bs_rand(2) == 0 and -1 or 1
    local confidence = bs_spyRank(brain) == "elite" and 0.15 or 0.25
    return (tonumber(x) or 0) + sx * radius, (tonumber(y) or 0) + sy * radius, z, confidence
end

local function bs_collectSpiesForBase(gmd, base)
    local out = {}
    if not (gmd and base) then return out end
    local baseId = base.id or base.baseId
    if not baseId then return out end
    NPCSpyBridge.EnsureData(gmd)

    if gmd.Queue then
        for _, brain in pairs(gmd.Queue) do
            if type(brain) == "table" and brain.spy == true and brain.spyDefected ~= true and brain.spySabotage ~= false then
                local resolved = NPCSpyBridge.ResolveBaseForBrain(gmd, brain)
                local hb = brain.homeBaseId or brain.baseId or brain.targetBaseId or brain.spyBaseId or (resolved and (resolved.id or resolved.baseId))
                if hb and tostring(hb) == tostring(baseId) then
                    out[#out + 1] = brain
                    NPCSpyBridge.RegisterBrain(gmd, brain)
                end
            end
        end
    end

    if gmd.VirtualGroups then
        for gid, group in pairs(gmd.VirtualGroups) do
            if type(group) == "table" then
                local groupBase = group.homeBaseId or group.baseId or group.targetBaseId
                if groupBase and tostring(groupBase) == tostring(baseId) and type(group.members) == "table" then
                    for _, member in pairs(group.members) do
                        if type(member) == "table" and member.spy == true and member.spyDefected ~= true and member.spySabotage ~= false then
                            member.worldGroupId = member.worldGroupId or gid
                            member.groupId = member.groupId or gid
                            out[#out + 1] = member
                            NPCSpyBridge.RegisterBrain(gmd, member)
                        end
                    end
                end
            end
        end
    end

    for _, rec in pairs(gmd.SpyRegistry or {}) do
        if type(rec) == "table" and rec.defected ~= true and rec.sabotage ~= false and rec.baseId and tostring(rec.baseId) == tostring(baseId) then
            out[#out + 1] = rec
        end
    end

    return out
end

local function bs_applyLossToTable(t, key, rate)
    if type(t) ~= "table" then return 0 end
    local value = tonumber(t[key])
    if not value or value <= 0 then return 0 end
    local loss = math.min(value, math.max(0.05, value * rate))
    t[key] = value - loss
    return loss
end

function NPCSpyBridge.SabotageBase(gmd, base, worldAge)
    if not (NPCSpyBridge.IsSabotageEnabled() and gmd and base) then return false end
    NPCSpyBridge.EnsureData(gmd)
    worldAge = tonumber(worldAge) or bs_worldHours()
    local interval = bs_num("Spy_SabotageTickMinutes", 30, 1, 1440) / 60
    if base.spyLastSabotageAt and worldAge - tonumber(base.spyLastSabotageAt) < interval then return false end

    local spies = bs_collectSpiesForBase(gmd, base)
    local activeSpies = {}
    local spyWeight = 0
    for _, spy in ipairs(spies) do
        if type(spy) == "table" and spy.spyCompromised ~= true and spy.compromised ~= true and NPCSpyBridge.TrySpyAction(gmd, spy, "sabotage", {base=base}) then
            activeSpies[#activeSpies + 1] = spy
            local rank = bs_spyRank(spy)
            if rank == "elite" then
                spyWeight = spyWeight + (1 + bs_num("Spy_EliteSabotageBonus", 0.50, 0, 5))
            elseif rank == "experienced" then
                spyWeight = spyWeight + 1.20
            else
                spyWeight = spyWeight + 1
            end
        end
    end
    local spyCount = #activeSpies
    if spyCount <= 0 then return false end

    local rate = bs_num("Spy_BaseTheftRate", 0.12, 0, 1) * spyWeight
    if rate <= 0 then return false end
    local keys = {"food", "water", "medical", "ammo", "supplies", "materials", "tools", "weapons", "spareParts", "stockFood", "stockWater", "stockMedical", "stockAmmo", "stockSupplies", "stockMaterials", "stockTools", "stockWeapons", "stockSpareParts"}
    local stolen = 0
    for _, key in ipairs(keys) do
        local value = tonumber(base[key])
        if value and value > 0 then
            local loss = math.min(value, math.max(0.05, value * rate))
            base[key] = value - loss
            stolen = stolen + loss
        end
    end
    for _, key in ipairs({"food", "water", "medical", "ammo", "supplies", "materials", "tools", "weapons", "spareParts"}) do
        stolen = stolen + bs_applyLossToTable(base.stock, key, rate)
        stolen = stolen + bs_applyLossToTable(base.donatedStock, key, rate)
        stolen = stolen + bs_applyLossToTable(base.zoneStock, key, rate * 0.5)
    end
    base.spyLastSabotageAt = worldAge
    base.spySabotageCount = (tonumber(base.spySabotageCount) or 0) + 1
    base.spySabotageScore = (tonumber(base.spySabotageScore) or 0) + stolen
    base.spyCount = math.max(tonumber(base.spyCount) or 0, spyCount)
    base.spySabotaged = true
    if base.garrisonReadiness then base.garrisonReadiness = math.max(0, tonumber(base.garrisonReadiness) - spyCount * 0.03) end
    if base.logisticsReadiness then base.logisticsReadiness = math.max(0, tonumber(base.logisticsReadiness) - spyCount * 0.04) end
    if base.defenseReadiness then base.defenseReadiness = math.max(0, tonumber(base.defenseReadiness) - spyCount * 0.03) end
    if base.ammoReadiness then base.ammoReadiness = math.max(0, tonumber(base.ammoReadiness) - spyCount * 0.05) end
    gmd.SpyStats.sabotageTicks = (tonumber(gmd.SpyStats.sabotageTicks) or 0) + 1
    return true, spyCount, stolen
end

function NPCSpyBridge.MakeIntelForBrain(gmd, brainOrRecord, player)
    if not (gmd and brainOrRecord) then return nil end
    local brain = brainOrRecord
    local rec = type(brainOrRecord) == "table" and brainOrRecord or nil
    local pid = tostring((player and NPCSpyBridge.PlayerId(player)) or brain.spyForPlayerId or brain.playerId or "")
    if pid == "" then return nil end

    local base = NPCSpyBridge.ResolveBaseForBrain(gmd, brain)
    local kind, name, x, y, z, side, sourceId = nil, nil, nil, nil, nil, nil, nil
    if base then
        kind = "base"
        name = bs_baseName(base)
        x = tonumber(base.x)
        y = tonumber(base.y)
        z = tonumber(base.z) or 0
        side = bs_baseSide(base) or bs_side(brain.spyOriginalSide or brain.originalSide)
        sourceId = base.id or base.baseId
    else
        local groupId = brain.worldGroupId or brain.groupId or brain.groupId
        local group = groupId and gmd.VirtualGroups and gmd.VirtualGroups[tostring(groupId)] or nil
        if group then
            kind = "patrol"
            name = group.name or ("Enemy group " .. tostring(groupId))
            x, y, z = bs_groupPosition(group)
            side = bs_groupSide(group) or bs_side(brain.spyOriginalSide or brain.originalSide)
            sourceId = groupId
        else
            kind = "contact"
            name = brain.fullname or brain.name or rec and rec.name or "Spy contact"
            x, y, z = bs_brainPosition(brain)
            side = bs_side(brain.spyOriginalSide or brain.originalSide or NPCSpyBridge.GetBrainSide(brain))
            sourceId = brain.uid or brain.persistentId or brain.id or rec and rec.id
        end
    end
    if not x or not y then return nil end

    local noise = bs_num("Spy_IntelNoiseTiles", 10, 0, 250)
    if bs_spyRank(brain) == "elite" then noise = math.floor(noise * bs_num("Spy_EliteIntelNoiseMultiplier", 0.45, 0, 1)) end
    local nx = math.floor(x + (noise > 0 and (bs_rand(noise * 2 + 1) - noise) or 0))
    local ny = math.floor(y + (noise > 0 and (bs_rand(noise * 2 + 1) - noise) or 0))
    return {
        createdAt = bs_worldHours(),
        playerId = pid,
        playerName = brain.spyForPlayerName or brain.playerName or (player and NPCSpyBridge.PlayerName(player)),
        spyId = NPCSpyBridge.BrainKey(brain, brain.id),
        spyName = brain.fullname or brain.name or "spy",
        kind = kind,
        side = side,
        sourceId = sourceId and tostring(sourceId) or nil,
        x = nx,
        y = ny,
        z = z or 0,
        confidence = noise <= 0 and "high" or "medium",
        rank = bs_spyRank(brain),
        elite = bs_spyRank(brain) == "elite",
        title = (bs_spyRank(brain) == "elite" and "Elite spy intel: " or "Spy intel: ") .. tostring(kind),
        text = (bs_spyRank(brain) == "elite" and "Elite spy intel: " or "Spy intel: ") .. tostring(kind) .. " of " .. tostring(side or "enemy") .. " near " .. tostring(nx) .. ", " .. tostring(ny) .. "."
    }
end

function NPCSpyBridge.MakeIntelMarker(gmd, intel)
    if not (gmd and intel and intel.x and intel.y and intel.playerId) then return nil end
    NPCSpyBridge.EnsureData(gmd)
    local nextId = tonumber(gmd.SpyStats.nextIntelId) or 1
    gmd.SpyStats.nextIntelId = nextId + 1
    local id = "spy_intel_" .. tostring(intel.playerId) .. "_" .. tostring(nextId)
    local marker = {
        id = id,
        markerType = "intel",
        x = intel.x,
        y = intel.y,
        z = intel.z or 0,
        name = intel.title or "Spy intel",
        hostile = false,
        friendly = true,
        factionSide = intel.side,
        faction = intel.side,
        side = intel.side,
        intelKind = intel.kind,
        intelFalse = false,
        intelConfidence = intel.confidence,
        spyIntel = true,
        spyIntelFalse = intel.falseIntel == true,
        spyRank = intel.rank,
        spyElite = intel.elite == true,
        spyId = intel.spyId,
        spyForPlayerId = intel.playerId,
        sourceId = intel.sourceId,
        updatedAt = bs_worldHours()
    }
    gmd.DebugMapMarkers[id] = marker
    intel.markerId = id
    return marker
end

function NPCSpyBridge.PruneIntel(gmd)
    if not gmd then return {} end
    NPCSpyBridge.EnsureData(gmd)
    local removed = {}
    local now = bs_worldHours()
    local ttl = bs_num("Spy_IntelMarkerHours", 24, 1, 240)
    local maxIntel = math.floor(bs_num("Spy_MaxIntelMarkers", 60, 1, 500))
    local kept = {}
    for _, intel in ipairs(gmd.SpyIntel or {}) do
        local expired = intel.createdAt and now - tonumber(intel.createdAt) > ttl
        if expired then
            if intel.markerId then removed[#removed + 1] = tostring(intel.markerId) end
        else
            kept[#kept + 1] = intel
        end
    end
    while #kept > maxIntel do
        local old = table.remove(kept, 1)
        if old and old.markerId then removed[#removed + 1] = tostring(old.markerId) end
    end
    for _, id in ipairs(removed) do
        if gmd.DebugMapMarkers then gmd.DebugMapMarkers[id] = nil end
    end
    gmd.SpyIntel = kept
    return removed
end

function NPCSpyBridge.UpdateSpyNetwork(gmd, worldAge)
    if not (NPCSpyBridge.IsEnabled() and gmd) then return {}, {}, {} end
    NPCSpyBridge.EnsureData(gmd)
    NPCSpyBridge.RegisterAll(gmd)

    worldAge = tonumber(worldAge) or bs_worldHours()
    local removed = NPCSpyBridge.PruneIntel(gmd)
    local changed = {}
    local interval = bs_num("Spy_IntelTickMinutes", 45, 5, 1440) / 60
    for key, rec in pairs(gmd.SpyRegistry or {}) do
        if type(rec) == "table" then
            NPCSpyBridge.UpdateSpyRiskAndRank(gmd, rec, worldAge)
        end
        if type(rec) == "table" and rec.defected ~= true and rec.playerId and rec.playerId ~= "" and rec.inactive ~= true then
            local last = tonumber(rec.lastIntelAt) or 0
            if worldAge - last >= interval then
                local brain = rec
                if gmd.Queue then
                    for _, candidate in pairs(gmd.Queue) do
                        if type(candidate) == "table" and (bs_same(candidate.id, rec.runtimeId) or bs_same(candidate.uid, rec.uid) or bs_same(candidate.persistentId, rec.uid) or bs_same(NPCSpyBridge.BrainKey(candidate, candidate.id), key)) then
                            brain = candidate
                            break
                        end
                    end
                end
                rec.lastIntelAt = worldAge
                local intel = nil
                if rec.doubleAgent == true or brain.spyDoubleAgent == true then
                    intel = NPCSpyBridge.MakeIntelForBrain(gmd, brain)
                    if intel then
                        local drift = 45 + bs_rand(136)
                        local sx = bs_rand(2) == 0 and -1 or 1
                        local sy = bs_rand(2) == 0 and -1 or 1
                        intel.x = math.floor((tonumber(intel.x) or 0) + sx * drift)
                        intel.y = math.floor((tonumber(intel.y) or 0) + sy * drift)
                        intel.confidence = "compromised"
                        intel.falseIntel = true
                        intel.title = "Compromised spy intel"
                        intel.text = "Compromised spy intel near " .. tostring(intel.x) .. ", " .. tostring(intel.y) .. "."
                    end
                elseif brain.spyCompromised ~= true and rec.compromised ~= true and NPCSpyBridge.TrySpyAction(gmd, brain, "intel", {}) then
                    intel = NPCSpyBridge.MakeIntelForBrain(gmd, brain)
                end
                if intel then
                    gmd.SpyIntel[#gmd.SpyIntel + 1] = intel
                    local marker = NPCSpyBridge.MakeIntelMarker(gmd, intel)
                    if marker then changed[#changed + 1] = marker end
                    if brain and brain.spy == true then brain.spyIntelLastAt = worldAge end
                    gmd.SpyStats.generatedIntel = (tonumber(gmd.SpyStats.generatedIntel) or 0) + 1
                end
            end
        end
    end
    local events = NPCSpyBridge.TakeEvents(gmd)
    return changed, removed, events
end

function NPCSpyBridge.CanCompleteReconFromIntel(gmd, player, contract)
    if not (gmd and player and contract and contract.type == "recon") then return false end
    NPCSpyBridge.EnsureData(gmd)
    local pid = NPCSpyBridge.PlayerId(player)
    if not pid then return false end
    local now = bs_worldHours()
    local ttl = bs_num("Spy_IntelMarkerHours", 24, 1, 240)
    for _, intel in ipairs(gmd.SpyIntel or {}) do
        if intel and tostring(intel.playerId or "") == tostring(pid) then
            local fresh = not intel.createdAt or now - tonumber(intel.createdAt) <= ttl
            local sameSource = intel.sourceId and contract.targetSourceId and tostring(intel.sourceId) == tostring(contract.targetSourceId)
            local near = intel.x and intel.y and bs_dist(intel.x, intel.y, contract.x, contract.y) <= ((tonumber(contract.completeRadius) or 28) + 24)
            if fresh and (sameSource or near) then return true end
        end
    end
    return false
end
