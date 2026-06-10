-- NPCIntelDossierBridge.lua
-- Server-safe intelligence dossier progression and black-market sale helpers.

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCLegacySettingsBridge"
require "NPCCore/NPCHeatWantedBridge"

NPCIntelDossierBridge = NPCIntelDossierBridge or {}
NPCIntelDossierBridge.Version = 2

-- MP-safe physical representation: do not require additional media/scripts files.
-- Dossiers are vanilla papers tagged with ModData, gold payouts are vanilla gold jewelry bundles.
local BID_DOSSIER_ITEM = "Base.SheetPaper2"
local BID_GOLD_ITEM = "Base.Necklace_Gold"
local BID_LEGACY_SIDE_ITEMS = {
    red = "FactionsConfrontation.RedIntelDossier",
    green = "FactionsConfrontation.GreenIntelDossier",
    encrypted = "FactionsConfrontation.EncryptedIntelDossier",
    counterintel = "FactionsConfrontation.CounterIntelFile"
}

local function bid_num(name, defaultValue, minValue, maxValue)
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

local function bid_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        local ok, got = pcall(function() return NPCLegacySettingsBridge.GetBool(name, defaultValue == true) end)
        if ok and got ~= nil then return got == true end
    end
    return defaultValue == true
end

local function bid_now()
    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then
            local ok, value = pcall(function() return gt:getWorldAgeHours() end)
            if ok and value then return tonumber(value) or 0 end
        end
    end
    return os.time() / 3600
end

local function bid_side(side)
    if NPCFactionBridge and NPCFactionBridge.NormalizeSide then
        local ok, got = pcall(function() return NPCFactionBridge.NormalizeSide(side) end)
        if ok and got then return got end
    end
    side = tostring(side or ""):lower()
    if side == "red" or side == "green" or side == "blue" or side == "black" then return side end
    return nil
end

local function bid_playerSide(player)
    if NPCFactionBridge and NPCFactionBridge.GetPlayerSide then
        local ok, got = pcall(function() return NPCFactionBridge.GetPlayerSide(player) end)
        if ok then return bid_side(got) end
    end
    return bid_side(NPCFactionBridge and NPCFactionBridge.DefaultPlayerSide and NPCFactionBridge.DefaultPlayerSide()) or "blue"
end

local function bid_playerId(player)
    if not player then return "0" end
    if NPCUtils and NPCUtils.GetCharacterID then
        local ok, id = pcall(function() return NPCUtils.GetCharacterID(player) end)
        if ok and id ~= nil then return tostring(id) end
    end
    if player.getOnlineID then
        local ok, id = pcall(function() return player:getOnlineID() end)
        if ok and id ~= nil then return tostring(id) end
    end
    if player.getUsername then
        local ok, name = pcall(function() return player:getUsername() end)
        if ok and name then return tostring(name) end
    end
    return "0"
end

local function bid_playerName(player)
    if not player then return "player" end
    if player.getUsername then
        local ok, name = pcall(function() return player:getUsername() end)
        if ok and name and tostring(name) ~= "" then return tostring(name) end
    end
    if player.getDisplayName then
        local ok, name = pcall(function() return player:getDisplayName() end)
        if ok and name and tostring(name) ~= "" then return tostring(name) end
    end
    return "player"
end

function NPCIntelDossierBridge.IsEnabled()
    return bid_bool("IntelDossier_Enabled", true)
end

function NPCIntelDossierBridge.SellEnabled()
    return bid_bool("IntelDossier_SellEnabled", true)
end

function NPCIntelDossierBridge.Threshold()
    return math.floor(bid_num("IntelDossier_Threshold", 100, 10, 1000))
end

function NPCIntelDossierBridge.NotifyProgress()
    return bid_bool("IntelDossier_NotifyProgress", false)
end

function NPCIntelDossierBridge.NeutralCollectsBothSides()
    return bid_bool("IntelDossier_NeutralCollectsBothSides", true)
end

function NPCIntelDossierBridge.TargetSideForPlayer(player, sourceSide)
    sourceSide = bid_side(sourceSide)
    if sourceSide ~= "red" and sourceSide ~= "green" then return nil end
    local playerSide = bid_playerSide(player)
    if playerSide == "red" then
        if sourceSide == "green" then return "green" end
        return nil
    end
    if playerSide == "green" then
        if sourceSide == "red" then return "red" end
        return nil
    end
    if (playerSide == "blue" or playerSide == "black") and NPCIntelDossierBridge.NeutralCollectsBothSides() then
        return sourceSide
    end
    return nil
end

function NPCIntelDossierBridge.EnsureData(gmd)
    if not gmd then return nil end
    gmd.IntelDossiers = gmd.IntelDossiers or {}
    gmd.IntelDossiers.players = gmd.IntelDossiers.players or {}
    gmd.IntelDossiers.baseProbe = gmd.IntelDossiers.baseProbe or {}
    gmd.IntelDossiers.stats = gmd.IntelDossiers.stats or {progress=0, granted=0, sold=0, gold=0}
    return gmd.IntelDossiers
end

local function bid_playerRecord(gmd, player)
    local data = NPCIntelDossierBridge.EnsureData(gmd)
    if not data then return nil end
    local pid = bid_playerId(player)
    data.players[pid] = data.players[pid] or {playerId=pid, playerName=bid_playerName(player), progress={red=0, green=0}, granted={red=0, green=0, encrypted=0, counterintel=0}, sold=0, gold=0}
    local rec = data.players[pid]
    rec.playerName = bid_playerName(player)
    rec.progress = rec.progress or {red=0, green=0}
    rec.granted = rec.granted or {red=0, green=0, encrypted=0, counterintel=0}
    rec.sold = tonumber(rec.sold) or 0
    rec.gold = tonumber(rec.gold) or 0
    return rec, data
end

local function bid_addItem(player, fullType, count)
    count = math.floor(tonumber(count) or 0)
    if count <= 0 then return 0 end
    if not (player and player.getInventory and fullType) then return 0 end
    local inv = player:getInventory()
    if not (inv and inv.AddItem) then return 0 end
    local added = 0
    for _ = 1, count do
        local ok, item = pcall(function() return inv:AddItem(fullType) end)
        if ok and item then
            added = added + 1
        else
            break
        end
    end
    return added
end

local function bid_itemFullType(item)
    if not item then return nil end
    if item.getFullType then
        local ok, ft = pcall(function() return item:getFullType() end)
        if ok and ft then return tostring(ft) end
    end
    if item.getModule and item.getType then
        local ok, ft = pcall(function() return tostring(item:getModule()) .. "." .. tostring(item:getType()) end)
        if ok and ft then return ft end
    end
    return nil
end

local function bid_itemModData(item)
    if item and item.getModData then
        local ok, md = pcall(function() return item:getModData() end)
        if ok then return md end
    end
    return nil
end

local function bid_scanInventoryItems(container, out, depth)
    if not container or depth > 3 then return out end
    local items = nil
    if container.getItems then
        local ok, got = pcall(function() return container:getItems() end)
        if ok then items = got end
    end
    if not items or not items.size or not items.get then return out end
    local size = 0
    local okSize, gotSize = pcall(function() return items:size() end)
    if okSize then size = tonumber(gotSize) or 0 end
    for i = 0, size - 1 do
        local okItem, item = pcall(function() return items:get(i) end)
        if okItem and item then
            out[#out + 1] = item
            if item.getInventory then
                local okInv, inv = pcall(function() return item:getInventory() end)
                if okInv and inv then bid_scanInventoryItems(inv, out, depth + 1) end
            end
        end
    end
    return out
end

local function bid_playerInventory(player)
    if player and player.getInventory then
        local ok, inv = pcall(function() return player:getInventory() end)
        if ok then return inv end
    end
    return nil
end

local function bid_addDossier(player, kind, targetSide, source, sourceId)
    local inv = bid_playerInventory(player)
    if not (inv and inv.AddItem) then return nil end
    local ok, item = pcall(function() return inv:AddItem(BID_DOSSIER_ITEM) end)
    if not ok or not item then return nil end
    local md = bid_itemModData(item)
    if md then
        md.FactionsConfrontationIntelDossier = true
        md.fcIntelKind = tostring(kind or targetSide or "intel")
        md.fcIntelSide = tostring(targetSide or "")
        md.fcIntelSource = tostring(source or "intel")
        md.fcIntelSourceId = sourceId and tostring(sourceId) or nil
        md.fcIntelCreatedAt = bid_now()
        md.fcIntelSellable = true
    end
    return item
end

local function bid_legacyKindFromType(fullType)
    if fullType == BID_LEGACY_SIDE_ITEMS.red then return "red" end
    if fullType == BID_LEGACY_SIDE_ITEMS.green then return "green" end
    if fullType == BID_LEGACY_SIDE_ITEMS.encrypted then return "encrypted" end
    if fullType == BID_LEGACY_SIDE_ITEMS.counterintel then return "counterintel" end
    return nil
end

local function bid_dossierKind(item)
    local md = bid_itemModData(item)
    if md and md.FactionsConfrontationIntelDossier == true then
        local kind = tostring(md.fcIntelKind or md.fcIntelSide or "")
        if kind == "red" or kind == "green" or kind == "encrypted" or kind == "counterintel" then return kind end
        return "encrypted"
    end
    return bid_legacyKindFromType(bid_itemFullType(item))
end

local function bid_removeItemObject(item, rootInventory)
    if not item then return false end
    if item.getContainer then
        local okContainer, container = pcall(function() return item:getContainer() end)
        if okContainer and container and container.Remove then
            local okRemove = pcall(function() container:Remove(item) end)
            if okRemove then return true end
        end
    end
    if rootInventory and rootInventory.Remove then
        local ok = pcall(function() rootInventory:Remove(item) end)
        if ok then return true end
    end
    return false
end

local function bid_collectSellable(player)
    local inv = bid_playerInventory(player)
    local result = {red={}, green={}, encrypted={}, counterintel={}, total=0}
    if not inv then return result end
    local items = bid_scanInventoryItems(inv, {}, 0)
    for _, item in ipairs(items) do
        local kind = bid_dossierKind(item)
        if kind and result[kind] then
            result[kind][#result[kind] + 1] = item
            result.total = result.total + 1
        end
    end
    return result
end

local function bid_goldBundleCount(goldValue)
    return math.max(1, math.ceil((tonumber(goldValue) or 0) / 100))
end

function NPCIntelDossierBridge.DossierItemForSide(side)
    side = bid_side(side)
    if side == "red" or side == "green" then return BID_DOSSIER_ITEM end
    return nil
end

function NPCIntelDossierBridge.GainForKind(kind, source)
    kind = tostring(kind or "radio")
    if kind == "base" or source == "base_probe" then return bid_num("IntelDossier_BaseProbeGain", 20, 0, 500) end
    if kind == "convoy" then return bid_num("IntelDossier_ConvoyGain", 30, 0, 500) end
    if kind == "supply_cache" or kind == "black_market_drop" or kind == "stash" then return bid_num("IntelDossier_StashGain", 20, 0, 500) end
    if kind == "spy_intel" then return bid_num("IntelDossier_SpyGain", 16, 0, 500) end
    if kind == "bounty" then return bid_num("IntelDossier_RadioGain", 10, 0, 500) end
    return bid_num("IntelDossier_RadioGain", 12, 0, 500)
end

function NPCIntelDossierBridge.AddProgress(gmd, player, targetSide, amount, source, sourceId)
    if not (NPCIntelDossierBridge.IsEnabled() and player) then return nil end
    targetSide = bid_side(targetSide)
    if targetSide ~= "red" and targetSide ~= "green" then return nil end
    amount = tonumber(amount) or 0
    if amount <= 0 then return nil end
    local rec, data = bid_playerRecord(gmd, player)
    if not rec then return nil end
    local threshold = math.max(1, NPCIntelDossierBridge.Threshold())
    rec.progress[targetSide] = (tonumber(rec.progress[targetSide]) or 0) + amount
    data.stats.progress = (tonumber(data.stats.progress) or 0) + amount
    local granted = 0
    while rec.progress[targetSide] >= threshold do
        rec.progress[targetSide] = rec.progress[targetSide] - threshold
        if bid_addDossier(player, targetSide, targetSide, source, sourceId) then
            granted = granted + 1
            rec.granted[targetSide] = (tonumber(rec.granted[targetSide]) or 0) + 1
            data.stats.granted = (tonumber(data.stats.granted) or 0) + 1
        else
            break
        end
    end
    rec.updatedAt = bid_now()
    rec.lastSource = tostring(source or "intel")
    rec.lastSourceId = sourceId and tostring(sourceId) or nil
    local heatWanted = nil
    if NPCHeatWantedBridge and NPCHeatWantedBridge.ReportIntelProgress then
        heatWanted = NPCHeatWantedBridge.ReportIntelProgress(gmd, player, targetSide, amount, source, sourceId)
        if heatWanted and NPCHeatWantedServerBridge and NPCHeatWantedServerBridge.AfterHeatChanged then
            NPCHeatWantedServerBridge.AfterHeatChanged(player, heatWanted)
        end
    end
    local left = math.floor((tonumber(rec.progress[targetSide]) or 0) + 0.5)
    local text = nil
    if granted > 0 then
        text = "Intelligence dossier assembled: " .. tostring(targetSide) .. " x" .. tostring(granted) .. "."
    elseif NPCIntelDossierBridge.NotifyProgress() then
        text = "Intel progress " .. tostring(targetSide) .. ": " .. tostring(left) .. "/" .. tostring(threshold) .. "."
    end
    return {targetSide=targetSide, amount=amount, progress=left, threshold=threshold, granted=granted, text=text}
end

function NPCIntelDossierBridge.GrantFromRadio(gmd, player, msg, metrics, source)
    if not (msg and msg.decoded ~= false and msg.falseSignal ~= true and msg.unreliable ~= true) then return nil end
    local targetSide = NPCIntelDossierBridge.TargetSideForPlayer(player, msg.side or (metrics and metrics.side))
    if not targetSide then return nil end
    local gain = NPCIntelDossierBridge.GainForKind(msg.kind, source)
    if metrics and metrics.lock then
        gain = gain * math.max(0.35, math.min(1.35, (tonumber(metrics.lock) or 60) / 80.0))
    end
    return NPCIntelDossierBridge.AddProgress(gmd, player, targetSide, math.floor(gain + 0.5), source or "radio", msg.id)
end

function NPCIntelDossierBridge.CountSellable(player)
    local collected = bid_collectSellable(player)
    local counts = {
        red = #collected.red,
        green = #collected.green,
        encrypted = #collected.encrypted,
        counterintel = #collected.counterintel
    }
    counts.total = counts.red + counts.green + counts.encrypted + counts.counterintel
    return counts
end

local function bid_addCounterIntelHeat(gmd, player, side, amount)
    if not (gmd and player and NPCRadioInterceptBridge and NPCRadioInterceptBridge.EnsureData) then return end
    local data = NPCRadioInterceptBridge.EnsureData(gmd)
    if not (data and data.counterIntel and data.counterIntel.players) then return end
    local pid = bid_playerId(player)
    side = bid_side(side) or "black"
    data.counterIntel.players[pid] = data.counterIntel.players[pid] or {}
    local row = data.counterIntel.players[pid][side]
    if type(row) ~= "table" then
        row = {heat=0, lastAt=bid_now(), burnUntil=0, detections=0}
        data.counterIntel.players[pid][side] = row
    end
    local maxHeat = NPCRadioInterceptBridge.CounterIntelMaxHeat and NPCRadioInterceptBridge.CounterIntelMaxHeat() or 60
    row.heat = math.max(0, math.min(maxHeat, (tonumber(row.heat) or 0) + (tonumber(amount) or 0)))
    row.lastAt = bid_now()
end

function NPCIntelDossierBridge.SellToBlackMarket(gmd, player, contact, side)
    if not (NPCIntelDossierBridge.IsEnabled() and NPCIntelDossierBridge.SellEnabled() and player) then return false, "Intelligence trade is disabled." end
    local collected = bid_collectSellable(player)
    if collected.total <= 0 then return false, "No intelligence dossiers to sell." end
    local maxSold = math.max(1, math.floor(bid_num("IntelDossier_MaxSoldPerDeal", 5, 1, 50)))
    local rewardNormal = math.floor(bid_num("IntelDossier_GoldReward", 100, 1, 10000))
    local rewardEncrypted = math.floor(bid_num("IntelDossier_EncryptedGoldReward", 250, 1, 20000))
    local sold = {red=0, green=0, encrypted=0, counterintel=0}
    local totalSold = 0
    local gold = 0
    local inv = bid_playerInventory(player)
    local order = {
        {key="encrypted", reward=rewardEncrypted},
        {key="counterintel", reward=rewardEncrypted},
        {key="red", reward=rewardNormal},
        {key="green", reward=rewardNormal}
    }
    for _, row in ipairs(order) do
        local bucket = collected[row.key] or {}
        while totalSold < maxSold and #bucket > 0 do
            local item = table.remove(bucket, 1)
            if not bid_removeItemObject(item, inv) then break end
            sold[row.key] = sold[row.key] + 1
            totalSold = totalSold + 1
            gold = gold + row.reward
        end
    end
    if totalSold <= 0 then return false, "Could not transfer intelligence dossiers." end
    local addedGold = bid_addItem(player, BID_GOLD_ITEM, bid_goldBundleCount(gold))
    local rec, data = bid_playerRecord(gmd, player)
    if rec then
        rec.sold = (tonumber(rec.sold) or 0) + totalSold
        rec.gold = (tonumber(rec.gold) or 0) + addedGold
        rec.lastSaleAt = bid_now()
    end
    if data then
        data.stats.sold = (tonumber(data.stats.sold) or 0) + totalSold
        data.stats.gold = (tonumber(data.stats.gold) or 0) + addedGold
    end
    local heat = bid_num("IntelDossier_SaleHeatGain", 5, 0, 100) * totalSold
    bid_addCounterIntelHeat(gmd, player, "black", heat)
    bid_addCounterIntelHeat(gmd, player, "red", heat * 0.5)
    bid_addCounterIntelHeat(gmd, player, "green", heat * 0.5)
    local heatWanted = nil
    if NPCHeatWantedBridge and NPCHeatWantedBridge.ReportIntelSale then
        heatWanted = NPCHeatWantedBridge.ReportIntelSale(gmd, player, sold, {totalSold=totalSold, gold=addedGold, heat=heat})
        if heatWanted and NPCHeatWantedServerBridge and NPCHeatWantedServerBridge.AfterHeatChanged then
            NPCHeatWantedServerBridge.AfterHeatChanged(player, heatWanted)
        end
    end
    local msg = "Sold " .. tostring(totalSold) .. " intelligence dossier(s) for " .. tostring(gold) .. " gold value."
    if addedGold > 0 then msg = msg .. " Paid as " .. tostring(addedGold) .. " gold jewelry bundle(s)." end
    if addedGold <= 0 then msg = msg .. " Inventory did not accept payout items." end
    if heatWanted and heatWanted.levelChanged and heatWanted.level > heatWanted.oldLevel then msg = msg .. " Wanted heat L" .. tostring(heatWanted.level) .. "." end
    return true, msg, {sold=sold, totalSold=totalSold, gold=addedGold, heat=heat, wantedHeat=heatWanted and heatWanted.heat, wantedLevel=heatWanted and heatWanted.level}
end

function NPCIntelDossierBridge.BaseProbeRadius()
    return bid_num("IntelDossier_BaseProbeRadius", 42, 4, 160)
end

function NPCIntelDossierBridge.BaseProbeCooldownHours()
    return bid_num("IntelDossier_BaseProbeCooldownMinutes", 60, 1, 1440) / 60
end

function NPCIntelDossierBridge.TryGrantBaseProbe(gmd, player, base)
    if not (NPCIntelDossierBridge.IsEnabled() and gmd and player and type(base) == "table") then return nil end
    local sourceSide = bid_side(base.owner or base.captureTeam or base.factionSide or base.side)
    local targetSide = NPCIntelDossierBridge.TargetSideForPlayer(player, sourceSide)
    if not targetSide then return nil end
    local px = player.getX and player:getX() or nil
    local py = player.getY and player:getY() or nil
    if not (px and py and base.x and base.y) then return nil end
    local dx = (tonumber(base.x) or 0) - (tonumber(px) or 0)
    local dy = (tonumber(base.y) or 0) - (tonumber(py) or 0)
    local radius = math.max(NPCIntelDossierBridge.BaseProbeRadius(), tonumber(base.radius or base.baseRadius) or 0)
    if (dx * dx + dy * dy) > radius * radius then return nil end
    local data = NPCIntelDossierBridge.EnsureData(gmd)
    if not data then return nil end
    data.baseProbe = data.baseProbe or {}
    local pid = bid_playerId(player)
    local key = tostring(pid) .. ":" .. tostring(base.id or base.baseId or math.floor(tonumber(base.x) or 0) .. ":" .. math.floor(tonumber(base.y) or 0))
    local now = bid_now()
    if tonumber(data.baseProbe[key] or 0) > now then return nil end
    data.baseProbe[key] = now + NPCIntelDossierBridge.BaseProbeCooldownHours()
    return NPCIntelDossierBridge.AddProgress(gmd, player, targetSide, NPCIntelDossierBridge.GainForKind("base", "base_probe"), "base_probe", base.id or base.baseId)
end

NPCLegacyGlobalsBridge.InstallAlias("IntelDossier", NPCIntelDossierBridge, "NPCIntelDossierBridge")
