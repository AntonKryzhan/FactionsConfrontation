-- NPCRadioInterceptBridge.lua
-- Neutral shared backend for radio intercept state, scanning and intel markers.
-- Lightweight player-facing radio intercepts for convoys, checkpoints, bases and daily passwords.
-- Uses existing virtual systems; does not add physical radio items or heavy tick logic.

require "NPCCore/NPCLegacyContractBridge"

NPCRadioInterceptBridge = NPCRadioInterceptBridge or {}

local BRI_SIDES = {"red", "green", "blue", "black"}
local BRI_SUPPLY_CACHE_LEGACY_KEYS = {
    enabled = NPCLegacyContractBridge.Key("RADIO_SUPPLY_CACHE"),
    tier = NPCLegacyContractBridge.Key("RADIO_SUPPLY_CACHE_TIER"),
    items = NPCLegacyContractBridge.Key("RADIO_SUPPLY_CACHE_ITEMS"),
    timestamp = NPCLegacyContractBridge.Key("RADIO_SUPPLY_CACHE_AT")
}

local function bri_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        local ok, value = pcall(function() return NPCLegacySettingsBridge.GetBool(name, defaultValue == true) end)
        if ok and value ~= nil then return value == true end
    end
    return defaultValue == true
end

local function bri_num(name, defaultValue, minValue, maxValue)
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

local function bri_now()
    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then
            local ok, value = pcall(function() return gt:getWorldAgeHours() end)
            if ok and value then return tonumber(value) or 0 end
        end
    end
    return os.time and (os.time() / 3600) or 0
end

local function bri_rand(maxValue)
    maxValue = math.floor(tonumber(maxValue) or 0)
    if maxValue <= 0 then return 0 end
    if ZombRand then
        local ok, value = pcall(function() return ZombRand(maxValue) end)
        if ok and value ~= nil then return tonumber(value) or 0 end
    end
    return math.random(0, maxValue - 1)
end

local function bri_side(side)
    if NPCFactionBridge and NPCFactionBridge.NormalizeSide then
        local s = NPCFactionBridge.NormalizeSide(side)
        if s then return s end
    end
    side = tostring(side or ""):lower()
    if side == "red" or side == "green" or side == "blue" or side == "black" then return side end
    return nil
end

local function bri_sideLabel(side)
    if NPCFactionBridge and NPCFactionBridge.GetSideLabel then
        local ok, label = pcall(function() return NPCFactionBridge.GetSideLabel(side) end)
        if ok and label then return tostring(label) end
    end
    return tostring(side or "faction")
end

local function bri_playerId(player)
    if not player then return nil end
    if NPCUtils and NPCUtils.GetCharacterID then
        local ok, id = pcall(function() return NPCUtils.GetCharacterID(player) end)
        if ok and id ~= nil then return id end
    end
    if player.getOnlineID then
        local ok, id = pcall(function() return player:getOnlineID() end)
        if ok and id ~= nil then return id end
    end
    return nil
end

local function bri_playerName(player)
    if not player then return "player" end
    if player.getUsername then
        local ok, name = pcall(function() return player:getUsername() end)
        if ok and name then return tostring(name) end
    end
    if player.getFullName then
        local ok, name = pcall(function() return player:getFullName() end)
        if ok and name then return tostring(name) end
    end
    return "player"
end

local function bri_itemText(item)
    if not item then return "" end
    local parts = {}
    if item.getFullType then
        local ok, value = pcall(function() return item:getFullType() end)
        if ok and value then parts[#parts + 1] = tostring(value) end
    end
    if item.getType then
        local ok, value = pcall(function() return item:getType() end)
        if ok and value then parts[#parts + 1] = tostring(value) end
    end
    if item.getDisplayName then
        local ok, value = pcall(function() return item:getDisplayName() end)
        if ok and value then parts[#parts + 1] = tostring(value) end
    end
    return table.concat(parts, " "):lower()
end

local function bri_hasRadioItem(item)
    local text = bri_itemText(item)
    if text == "" and not (item and item.getDeviceData) then return false end
    if text:find("radio", 1, true) then return true end
    if text:find("walkie", 1, true) then return true end
    if text:find("ham", 1, true) then return true end
    if text:find("receiver", 1, true) then return true end
    if item and item.getDeviceData then
        local ok, data = pcall(function() return item:getDeviceData() end)
        if ok and data then return true end
    end
    return false
end

local function bri_deviceData(item)
    if not (item and item.getDeviceData) then return nil end
    local ok, data = pcall(function() return item:getDeviceData() end)
    if ok then return data end
    return nil
end

local function bri_callNumber(obj, methodName, fallback)
    if not (obj and obj[methodName]) then return fallback end
    local ok, value = pcall(function() return obj[methodName](obj) end)
    if ok and value ~= nil then return tonumber(value) or fallback end
    return fallback
end

local function bri_callBool(obj, methodName, fallback)
    if not (obj and obj[methodName]) then return fallback end
    local ok, value = pcall(function() return obj[methodName](obj) end)
    if ok and value ~= nil then return value == true end
    return fallback
end

local function bri_normalizeFrequency(value)
    local n = tonumber(value)
    if not n then return nil end
    if n > 10000 then return n / 1000.0 end
    if n > 1000 then return n / 10.0 end
    return n
end

local function bri_readRadioInfo(item)
    if not item then return nil end
    local data = bri_deviceData(item)
    local info = {
        item = item,
        text = bri_itemText(item),
        hasDeviceData = data ~= nil,
        turnedOn = nil,
        power = nil,
        volume = nil,
        frequency = nil,
        powered = true
    }
    if data then
        info.turnedOn = bri_callBool(data, "getIsTurnedOn", info.turnedOn)
        info.turnedOn = bri_callBool(data, "getTurnedOn", info.turnedOn)
        info.power = bri_callNumber(data, "getPower", info.power)
        info.power = bri_callNumber(data, "getBatteryPower", info.power)
        info.volume = bri_callNumber(data, "getDeviceVolume", info.volume)
        info.frequency = bri_normalizeFrequency(bri_callNumber(data, "getChannel", info.frequency))
        info.frequency = bri_normalizeFrequency(bri_callNumber(data, "getChannelRange", info.frequency))
        if info.turnedOn ~= nil and info.turnedOn ~= true then info.powered = false end
        if info.power ~= nil and info.power <= 0 then info.powered = false end
    end
    return info
end

local function bri_inventoryItems(inv, out, seen)
    if not (inv and inv.getItems) then return end
    seen = seen or {}
    out = out or {}
    local okItems, items = pcall(function() return inv:getItems() end)
    if not (okItems and items and items.size and items.get) then return end
    for i=0, items:size() - 1 do
        local okItem, item = pcall(function() return items:get(i) end)
        if okItem and item then
            local key = tostring(item)
            if not seen[key] then
                seen[key] = true
                out[#out + 1] = item
                if item.getInventory then
                    local okSub, subInv = pcall(function() return item:getInventory() end)
                    if okSub and subInv then bri_inventoryItems(subInv, out, seen) end
                end
            end
        end
    end
end

local function bri_dist(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return math.sqrt(dx * dx + dy * dy)
end

function NPCRadioInterceptBridge.IsEnabled()
    return bri_bool("RadioIntercept_Enabled", true)
end

function NPCRadioInterceptBridge.RequireRadio()
    return bri_bool("RadioIntercept_RequireRadio", true)
end

function NPCRadioInterceptBridge.CooldownHours()
    return bri_num("RadioIntercept_CooldownMinutes", 20, 1, 1440) / 60
end

function NPCRadioInterceptBridge.HistoryLimit()
    return math.floor(bri_num("RadioIntercept_HistoryLimit", 10, 1, 60))
end

function NPCRadioInterceptBridge.FalseChance()
    return bri_num("RadioIntercept_FalseChance", 15, 0, 100)
end

function NPCRadioInterceptBridge.StaleChance()
    return bri_num("RadioIntercept_StaleChance", 20, 0, 100)
end

function NPCRadioInterceptBridge.IncompleteChance()
    return bri_num("RadioIntercept_IncompleteChance", 22, 0, 100)
end

function NPCRadioInterceptBridge.PasswordLeakChance()
    return bri_num("RadioIntercept_PasswordLeakChance", 22, 0, 100)
end

function NPCRadioInterceptBridge.RequirePoweredRadio()
    return bri_bool("RadioIntercept_RequirePoweredRadio", true)
end

function NPCRadioInterceptBridge.SignalRange()
    return bri_num("RadioIntercept_SignalRange", 1800, 80, 8000)
end

function NPCRadioInterceptBridge.FrequencyTolerance()
    return bri_num("RadioIntercept_FrequencyTolerance", 0.35, 0.02, 5.0)
end

function NPCRadioInterceptBridge.LockThreshold()
    return bri_num("RadioIntercept_LockThreshold", 62, 1, 100)
end

function NPCRadioInterceptBridge.MarkerEnabled()
    return bri_bool("RadioIntercept_MarkerEnabled", true)
end

function NPCRadioInterceptBridge.MarkerHours()
    return bri_num("RadioIntercept_MarkerHours", 6, 0.1, 168)
end

function NPCRadioInterceptBridge.MarkerNoiseTiles()
    return bri_num("RadioIntercept_MarkerNoiseTiles", 45, 0, 600)
end

function NPCRadioInterceptBridge.MinMarkerLock()
    return bri_num("RadioIntercept_MinMarkerLock", 70, 1, 100)
end

function NPCRadioInterceptBridge.SupplyCacheEnabled()
    return bri_bool("RadioIntercept_SupplyCacheEnabled", true)
end

function NPCRadioInterceptBridge.SupplyCacheSignalChance()
    return bri_num("RadioIntercept_SupplyCacheSignalChance", 18, 0, 100)
end

function NPCRadioInterceptBridge.SupplyCacheFillChance()
    return bri_num("RadioIntercept_SupplyCacheFillChance", 80, 0, 100)
end

function NPCRadioInterceptBridge.SupplyCacheSearchRadius()
    return bri_num("RadioIntercept_SupplyCacheSearchRadius", 80, 10, 400)
end

function NPCRadioInterceptBridge.SupplyCacheMaxItems()
    return math.floor(bri_num("RadioIntercept_SupplyCacheMaxItems", 24, 4, 80))
end

function NPCRadioInterceptBridge.MonitorEnabled()
    return bri_bool("RadioIntercept_MonitorEnabled", true)
end

function NPCRadioInterceptBridge.MonitorTickHours()
    return bri_num("RadioIntercept_MonitorTickMinutes", 10, 1, 240) / 60
end

function NPCRadioInterceptBridge.MonitorMinLock()
    return bri_num("RadioIntercept_MonitorMinLock", 58, 1, 100)
end

function NPCRadioInterceptBridge.EncryptionEnabled()
    return bri_bool("RadioIntercept_EncryptionEnabled", true)
end

function NPCRadioInterceptBridge.EncryptionChance(side)
    side = bri_side(side) or tostring(side or ""):lower()
    if side == "green" then return bri_num("RadioIntercept_GreenEncryptedChance", 35, 0, 100) end
    if side == "blue" then return bri_num("RadioIntercept_BlueEncryptedChance", 15, 0, 100) end
    if side == "black" then return bri_num("RadioIntercept_BlackEncryptedChance", 55, 0, 100) end
    return bri_num("RadioIntercept_RedEncryptedChance", 35, 0, 100)
end

function NPCRadioInterceptBridge.DecoderProgressPerLock()
    return bri_num("RadioIntercept_DecodeProgressPerLock", 18, 1, 100)
end

function NPCRadioInterceptBridge.DecoderThreshold()
    return bri_num("RadioIntercept_DecodeThreshold", 100, 10, 500)
end

function NPCRadioInterceptBridge.WorldEventsEnabled()
    return bri_bool("RadioIntercept_WorldEventsEnabled", true)
end

function NPCRadioInterceptBridge.WorldEventMemoryHours()
    return bri_num("RadioIntercept_EventMemoryHours", 12, 0.5, 168)
end

function NPCRadioInterceptBridge.WorldEventRefreshHours()
    return bri_num("RadioIntercept_EventRefreshMinutes", 10, 1, 240) / 60
end

function NPCRadioInterceptBridge.WorldEventMaxCount()
    return math.floor(bri_num("RadioIntercept_EventMaxCount", 80, 5, 500))
end

function NPCRadioInterceptBridge.WorldEventWeightBonus()
    return bri_num("RadioIntercept_EventWeightBonus", 4, 1, 20)
end

function NPCRadioInterceptBridge.CounterIntelEnabled()
    return bri_bool("RadioIntercept_CounterIntelEnabled", true)
end

function NPCRadioInterceptBridge.CounterIntelBaseChance()
    return bri_num("RadioIntercept_CounterIntelBaseChance", 4, 0, 100)
end

function NPCRadioInterceptBridge.CounterIntelMonitorChance()
    return bri_num("RadioIntercept_CounterIntelMonitorChance", 2, 0, 100)
end

function NPCRadioInterceptBridge.CounterIntelBlackBonus()
    return bri_num("RadioIntercept_CounterIntelBlackBonus", 8, 0, 100)
end

function NPCRadioInterceptBridge.CounterIntelHeatPerScan()
    return bri_num("RadioIntercept_CounterIntelHeatPerScan", 2.5, 0, 50)
end

function NPCRadioInterceptBridge.CounterIntelHeatDecayHours()
    return bri_num("RadioIntercept_CounterIntelHeatDecayHours", 12, 0.1, 168)
end

function NPCRadioInterceptBridge.CounterIntelMaxHeat()
    return bri_num("RadioIntercept_CounterIntelMaxHeat", 60, 0, 200)
end

function NPCRadioInterceptBridge.CounterIntelBurnHours()
    return bri_num("RadioIntercept_CounterIntelBurnHours", 4, 0.1, 72)
end

function NPCRadioInterceptBridge.CounterIntelFalseSignalChance()
    return bri_num("RadioIntercept_CounterIntelFalseSignalChance", 45, 0, 100)
end

function NPCRadioInterceptBridge.CounterIntelMarkerEnabled()
    return bri_bool("RadioIntercept_CounterIntelMarkerEnabled", true)
end

function NPCRadioInterceptBridge.CounterIntelMarkerHours()
    return bri_num("RadioIntercept_CounterIntelMarkerHours", 3, 0.1, 72)
end

function NPCRadioInterceptBridge.HistoryMaxAgeHours()
    return bri_num("RadioIntercept_HistoryMaxAgeHours", 48, 1, 720)
end

function NPCRadioInterceptBridge.RadioSilenceHours()
    return bri_num("RadioIntercept_RadioSilenceHours", 2, 0.1, 72)
end

function NPCRadioInterceptBridge.RadioSilenceHeatReduction()
    return bri_num("RadioIntercept_RadioSilenceHeatReduction", 12, 0, 100)
end

function NPCRadioInterceptBridge.SideFrequency(side)
    side = bri_side(side) or tostring(side or ""):lower()
    if side == "green" then return bri_num("RadioIntercept_GreenFrequency", 152.3, 80.0, 200.0) end
    if side == "blue" then return bri_num("RadioIntercept_BlueFrequency", 161.5, 80.0, 200.0) end
    if side == "black" then return bri_num("RadioIntercept_BlackFrequency", 171.9, 80.0, 200.0) end
    return bri_num("RadioIntercept_RedFrequency", 143.7, 80.0, 200.0)
end

function NPCRadioInterceptBridge.FrequencyLabel(side)
    local f = NPCRadioInterceptBridge.SideFrequency(side)
    return string.format("%.2f MHz", tonumber(f) or 0)
end

function NPCRadioInterceptBridge.NowHours()
    return bri_now()
end

function NPCRadioInterceptBridge.PlayerId(player)
    return bri_playerId(player)
end

function NPCRadioInterceptBridge.GetRadioDeviceInfo(player)
    if not (player and player.getInventory) then return nil end
    local okInv, inv = pcall(function() return player:getInventory() end)
    if not okInv or not inv then return nil end
    local items = {}
    bri_inventoryItems(inv, items, {})
    for _, item in ipairs(items) do
        if bri_hasRadioItem(item) then
            local info = bri_readRadioInfo(item)
            if info then return info end
        end
    end
    return nil
end

function NPCRadioInterceptBridge.HasRadio(player)
    if not NPCRadioInterceptBridge.RequireRadio() then return true end
    local info = NPCRadioInterceptBridge.GetRadioDeviceInfo(player)
    return info ~= nil
end

function NPCRadioInterceptBridge.HasPoweredRadio(player)
    if not NPCRadioInterceptBridge.RequireRadio() then return true end
    local info = NPCRadioInterceptBridge.GetRadioDeviceInfo(player)
    if not info then return false, "no_radio" end
    if NPCRadioInterceptBridge.RequirePoweredRadio() and info.powered ~= true then return false, "radio_off", info end
    return true, "ok", info
end

function NPCRadioInterceptBridge.RadioStatusText(player)
    if not NPCRadioInterceptBridge.RequireRadio() then return "Radio requirement disabled." end
    local info = NPCRadioInterceptBridge.GetRadioDeviceInfo(player)
    if not info then return "No radio or walkie-talkie found." end
    local parts = {}
    parts[#parts + 1] = info.powered and "Radio ready" or "Radio is off or has no power"
    if info.frequency then parts[#parts + 1] = "tuned " .. string.format("%.2f MHz", info.frequency) end
    if info.volume then parts[#parts + 1] = "volume " .. tostring(math.floor(info.volume + 0.5)) end
    if info.power then parts[#parts + 1] = "battery " .. tostring(math.floor(info.power + 0.5)) end
    return table.concat(parts, " / ")
end

local function bri_clamp(value, minValue, maxValue)
    value = tonumber(value) or 0
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

function NPCRadioInterceptBridge.EnsureData(gmd)
    if not gmd then return nil end
    gmd.NPCRadioInterceptBridge = gmd.NPCRadioInterceptBridge or {}
    gmd.NPCRadioInterceptBridge.playerCooldowns = gmd.NPCRadioInterceptBridge.playerCooldowns or {}
    gmd.NPCRadioInterceptBridge.playerHistory = gmd.NPCRadioInterceptBridge.playerHistory or {}
    gmd.NPCRadioInterceptBridge.decoderProgress = gmd.NPCRadioInterceptBridge.decoderProgress or {}
    gmd.NPCRadioInterceptBridge.worldEvents = gmd.NPCRadioInterceptBridge.worldEvents or {}
    gmd.NPCRadioInterceptBridge.worldEventLastRefresh = tonumber(gmd.NPCRadioInterceptBridge.worldEventLastRefresh) or 0
    gmd.NPCRadioInterceptBridge.worldEventNextRefresh = tonumber(gmd.NPCRadioInterceptBridge.worldEventNextRefresh) or 0
    gmd.NPCRadioInterceptBridge.counterIntel = gmd.NPCRadioInterceptBridge.counterIntel or {}
    gmd.NPCRadioInterceptBridge.counterIntel.players = gmd.NPCRadioInterceptBridge.counterIntel.players or {}
    gmd.NPCRadioInterceptBridge.counterIntel.markers = gmd.NPCRadioInterceptBridge.counterIntel.markers or {}
    gmd.NPCRadioInterceptBridge.radioSilence = gmd.NPCRadioInterceptBridge.radioSilence or {}
    gmd.NPCRadioInterceptBridge.stats = gmd.NPCRadioInterceptBridge.stats or {scans=0, messages=0, falseSignals=0, passwordLeaks=0, monitorHits=0}
    gmd.NPCRadioInterceptBridge.stats.encrypted = tonumber(gmd.NPCRadioInterceptBridge.stats.encrypted) or 0
    gmd.NPCRadioInterceptBridge.stats.decrypted = tonumber(gmd.NPCRadioInterceptBridge.stats.decrypted) or 0
    gmd.NPCRadioInterceptBridge.stats.worldEvents = tonumber(gmd.NPCRadioInterceptBridge.stats.worldEvents) or 0
    gmd.NPCRadioInterceptBridge.stats.counterDetections = tonumber(gmd.NPCRadioInterceptBridge.stats.counterDetections) or 0
    gmd.NPCRadioInterceptBridge.stats.counterDecoys = tonumber(gmd.NPCRadioInterceptBridge.stats.counterDecoys) or 0
    return gmd.NPCRadioInterceptBridge
end

local function bri_receiverDefaults()
    return {
        frequency = NPCRadioInterceptBridge.SideFrequency("red"),
        gain = 55,
        squelch = 35,
        filter = "wide",
        monitoring = false,
        monitorLastAt = 0,
        monitorNextAt = 0,
        updatedAt = bri_now()
    }
end

local function bri_receiverPid(player)
    return tostring(bri_playerId(player) or "0")
end

function NPCRadioInterceptBridge.EnsureReceiverState(gmd, player)
    local data = NPCRadioInterceptBridge.EnsureData(gmd)
    if not data then return nil end
    data.receiverState = data.receiverState or {}
    local pid = bri_receiverPid(player)
    local state = data.receiverState[pid]
    if type(state) ~= "table" then
        state = bri_receiverDefaults()
        data.receiverState[pid] = state
    end
    state.frequency = bri_clamp(bri_normalizeFrequency(state.frequency) or NPCRadioInterceptBridge.SideFrequency("red"), 80.0, 200.0)
    state.gain = bri_clamp(state.gain or 55, 0, 100)
    state.squelch = bri_clamp(state.squelch or 35, 0, 100)
    if state.filter ~= "narrow" then state.filter = "wide" end
    state.monitoring = state.monitoring == true
    state.monitorLastAt = tonumber(state.monitorLastAt) or 0
    state.monitorNextAt = tonumber(state.monitorNextAt) or 0
    return state
end

local function bri_decoderDefaultSide()
    return {progress = 0, decoded = false, updatedAt = bri_now()}
end

function NPCRadioInterceptBridge.EnsureDecoderState(gmd, player)
    local data = NPCRadioInterceptBridge.EnsureData(gmd)
    if not data then return nil end
    local pid = bri_receiverPid(player)
    data.decoderProgress[pid] = data.decoderProgress[pid] or {}
    for _, side in ipairs(BRI_SIDES) do
        if type(data.decoderProgress[pid][side]) ~= "table" then
            data.decoderProgress[pid][side] = bri_decoderDefaultSide()
        end
        local row = data.decoderProgress[pid][side]
        row.progress = bri_clamp(row.progress or 0, 0, NPCRadioInterceptBridge.DecoderThreshold())
        row.decoded = row.decoded == true or row.progress >= NPCRadioInterceptBridge.DecoderThreshold()
        row.updatedAt = tonumber(row.updatedAt) or 0
    end
    return data.decoderProgress[pid]
end

function NPCRadioInterceptBridge.DecoderStatusText(gmd, player)
    local state = NPCRadioInterceptBridge.EnsureDecoderState(gmd, player)
    if not state then return "Decoder unavailable." end
    local parts = {}
    for _, side in ipairs(BRI_SIDES) do
        local row = state[side] or bri_decoderDefaultSide()
        local label = bri_sideLabel(side)
        if row.decoded == true then
            parts[#parts + 1] = label .. " decoded"
        else
            parts[#parts + 1] = label .. " " .. tostring(math.floor((tonumber(row.progress) or 0) + 0.5)) .. "%"
        end
    end
    return "Radio decoder: " .. table.concat(parts, " / ")
end

function NPCRadioInterceptBridge.RegisterEncryptedTraffic(gmd, player, side, metrics)
    side = bri_side(side) or "red"
    local state = NPCRadioInterceptBridge.EnsureDecoderState(gmd, player)
    if not state then return false, 0 end
    local row = state[side]
    if not row then return false, 0 end
    if row.decoded == true then return true, NPCRadioInterceptBridge.DecoderThreshold() end
    metrics = type(metrics) == "table" and metrics or {}
    local lock = bri_clamp(metrics.lock or 0, 0, 100)
    local signal = bri_clamp(metrics.signal or lock, 0, 100)
    local gain = math.max(1, NPCRadioInterceptBridge.DecoderProgressPerLock())
    local add = math.max(1, math.floor(((lock * 0.70 + signal * 0.30) / 100.0) * gain + 0.5))
    if lock < 35 then add = 1 end
    row.progress = bri_clamp((tonumber(row.progress) or 0) + add, 0, NPCRadioInterceptBridge.DecoderThreshold())
    row.updatedAt = bri_now()
    if row.progress >= NPCRadioInterceptBridge.DecoderThreshold() then
        row.progress = NPCRadioInterceptBridge.DecoderThreshold()
        row.decoded = true
        return true, row.progress
    end
    return false, row.progress
end

function NPCRadioInterceptBridge.IsSideDecoded(gmd, player, side)
    side = bri_side(side) or "red"
    local state = NPCRadioInterceptBridge.EnsureDecoderState(gmd, player)
    local row = state and state[side]
    return row and row.decoded == true
end


local function bri_counterPid(player)
    return tostring(bri_playerId(player) or "0")
end

local function bri_counterSide(side)
    return bri_side(side) or "red"
end

local function bri_playerXY(player)
    local x = player and player.getX and player:getX() or nil
    local y = player and player.getY and player:getY() or nil
    return tonumber(x), tonumber(y)
end

local function bri_counterState(gmd, player, side)
    local data = NPCRadioInterceptBridge.EnsureData(gmd)
    if not data then return nil end
    side = bri_counterSide(side)
    local pid = bri_counterPid(player)
    data.counterIntel.players[pid] = data.counterIntel.players[pid] or {}
    local row = data.counterIntel.players[pid][side]
    if type(row) ~= "table" then
        row = {heat = 0, lastAt = bri_now(), burnUntil = 0, detections = 0}
        data.counterIntel.players[pid][side] = row
    end
    local now = bri_now()
    local lastAt = tonumber(row.lastAt) or now
    local elapsed = math.max(0, now - lastAt)
    local decayHours = math.max(0.1, NPCRadioInterceptBridge.CounterIntelHeatDecayHours())
    if elapsed > 0 and (tonumber(row.heat) or 0) > 0 then
        row.heat = math.max(0, (tonumber(row.heat) or 0) - ((elapsed / decayHours) * NPCRadioInterceptBridge.CounterIntelMaxHeat()))
    end
    row.lastAt = now
    row.burnUntil = tonumber(row.burnUntil) or 0
    row.detections = tonumber(row.detections) or 0
    return row, data
end

function NPCRadioInterceptBridge.IsCounterIntelBurned(gmd, player, side)
    local row = bri_counterState(gmd, player, side)
    return row and tonumber(row.burnUntil or 0) > bri_now()
end

function NPCRadioInterceptBridge.CounterIntelStatusText(gmd, player)
    if not NPCRadioInterceptBridge.CounterIntelEnabled() then return "counterintel off" end
    local parts = {}
    for _, side in ipairs(BRI_SIDES) do
        local row = bri_counterState(gmd, player, side)
        if row then
            local heat = math.floor((tonumber(row.heat) or 0) + 0.5)
            local text = bri_sideLabel(side) .. " heat " .. tostring(heat)
            if tonumber(row.burnUntil or 0) > bri_now() then
                text = text .. " burned " .. tostring(math.max(1, math.ceil((tonumber(row.burnUntil) - bri_now()) * 60))) .. "m"
            end
            parts[#parts + 1] = text
        end
    end
    return "counterintel: " .. table.concat(parts, " / ")
end

function NPCRadioInterceptBridge.ApplyCounterIntelPressure(gmd, player, metrics)
    if not (NPCRadioInterceptBridge.CounterIntelEnabled() and type(metrics) == "table") then return metrics end
    local side = bri_counterSide(metrics.side)
    if NPCRadioInterceptBridge.IsCounterIntelBurned(gmd, player, side) then
        metrics.noise = math.floor(bri_clamp((tonumber(metrics.noise) or 0) + 16, 0, 100) + 0.5)
        metrics.signal = math.floor(bri_clamp((tonumber(metrics.signal) or 0) - 8, 0, 100) + 0.5)
        metrics.lock = math.floor(bri_clamp((tonumber(metrics.lock) or 0) - 18, 0, 100) + 0.5)
        metrics.decoded = metrics.lock >= NPCRadioInterceptBridge.LockThreshold()
        metrics.partial = metrics.lock >= math.max(25, NPCRadioInterceptBridge.LockThreshold() - 25)
        metrics.counterIntelBurned = true
    end
    return metrics
end

function NPCRadioInterceptBridge.CleanupCounterIntelMarkers(gmd)
    local data = NPCRadioInterceptBridge.EnsureData(gmd)
    if not data then return end
    local now = bri_now()
    data.counterIntel.markers = data.counterIntel.markers or {}
    for id, expiresAt in pairs(data.counterIntel.markers) do
        if tonumber(expiresAt) and tonumber(expiresAt) <= now then
            data.counterIntel.markers[id] = nil
            if gmd.DebugMapMarkers then gmd.DebugMapMarkers[tostring(id)] = nil end
            if sendServerCommand then pcall(function() sendServerCommand('NPCDebugMap', 'Remove', {id=tostring(id)}) end) end
        end
    end
end

function NPCRadioInterceptBridge.AddCounterIntelMarker(gmd, player, side, source, metrics)
    if not (gmd and player and NPCRadioInterceptBridge.CounterIntelMarkerEnabled()) then return false end
    local px, py = bri_playerXY(player)
    if not (px and py) then return false end
    local data = NPCRadioInterceptBridge.EnsureData(gmd)
    if not data then return false end
    NPCRadioInterceptBridge.CleanupCounterIntelMarkers(gmd)
    gmd.DebugMapMarkers = gmd.DebugMapMarkers or {}
    data.counterIntel.markers = data.counterIntel.markers or {}
    local jitter = 18 + bri_rand(38)
    local angle = bri_rand(6284) / 1000.0
    local mx = px + math.cos(angle) * jitter
    local my = py + math.sin(angle) * jitter
    local id = "radio_counterintel:" .. tostring(bri_counterPid(player)) .. ":" .. tostring(math.floor(bri_now() * 1000)) .. ":" .. tostring(bri_rand(100000))
    local expiresAt = bri_now() + NPCRadioInterceptBridge.CounterIntelMarkerHours()
    local marker = {
        id = id,
        markerType = "intel",
        x = mx,
        y = my,
        z = 0,
        side = bri_counterSide(side),
        name = "Radio triangulation risk",
        intelType = "radio_counterintel",
        intelFalse = true,
        radioIntel = true,
        radioCounterIntel = true,
        radioSourceKind = tostring(source or "scan"),
        signal = metrics and metrics.signal or nil,
        noise = metrics and metrics.noise or nil,
        lock = metrics and metrics.lock or nil,
        expiresAt = expiresAt,
        updatedAt = bri_now()
    }
    gmd.DebugMapMarkers[id] = marker
    data.counterIntel.markers[id] = expiresAt
    if NPCNetContract and NPCNetContract.SendDebugMapUpdate then
        NPCNetContract.SendDebugMapUpdate(marker)
    elseif sendServerCommand then
        pcall(function() sendServerCommand('NPCDebugMap', 'Update', marker) end)
    end
    return true
end

function NPCRadioInterceptBridge.RegisterCounterIntelExposure(gmd, player, msg, metrics, source)
    if not (NPCRadioInterceptBridge.CounterIntelEnabled() and gmd and player) then return nil end
    metrics = type(metrics) == "table" and metrics or {}
    source = tostring(source or "scan")
    local side = bri_counterSide((msg and msg.side) or metrics.side)
    local row, data = bri_counterState(gmd, player, side)
    if not (row and data) then return nil end

    local lock = bri_clamp(metrics.lock or 0, 0, 100)
    local signal = bri_clamp(metrics.signal or lock, 0, 100)
    local heatAdd = NPCRadioInterceptBridge.CounterIntelHeatPerScan() + ((lock + signal) / 100.0)
    if source == "monitor" then heatAdd = heatAdd * 0.55 end
    if msg and msg.encrypted == true then heatAdd = heatAdd + 1.5 end
    if msg and msg.decrypted == true then heatAdd = heatAdd + 2.0 end
    if msg and msg.eventTraffic == true then heatAdd = heatAdd + 1.0 end
    row.heat = bri_clamp((tonumber(row.heat) or 0) + heatAdd, 0, NPCRadioInterceptBridge.CounterIntelMaxHeat())
    row.lastAt = bri_now()

    local chance = source == "monitor" and NPCRadioInterceptBridge.CounterIntelMonitorChance() or NPCRadioInterceptBridge.CounterIntelBaseChance()
    chance = chance + ((tonumber(row.heat) or 0) * 0.35)
    if side == "black" then chance = chance + NPCRadioInterceptBridge.CounterIntelBlackBonus() end
    if msg and msg.encrypted == true then chance = chance + 2.0 end
    if msg and msg.decrypted == true then chance = chance + 3.0 end
    if lock >= NPCRadioInterceptBridge.MinMarkerLock() then chance = chance + 2.0 end
    chance = bri_clamp(chance, 0, 95)

    if bri_rand(10000) >= math.floor(chance * 100) then return nil end

    row.detections = (tonumber(row.detections) or 0) + 1
    row.burnUntil = math.max(tonumber(row.burnUntil) or 0, bri_now() + NPCRadioInterceptBridge.CounterIntelBurnHours())
    row.heat = bri_clamp((tonumber(row.heat) or 0) + 8, 0, NPCRadioInterceptBridge.CounterIntelMaxHeat())
    data.stats.counterDetections = (tonumber(data.stats.counterDetections) or 0) + 1

    local decoy = false
    if msg and bri_rand(100) < NPCRadioInterceptBridge.CounterIntelFalseSignalChance() then
        local fx, fy = bri_fakeAroundPlayer(player)
        msg.x = fx
        msg.y = fy
        msg.falseSignal = true
        msg.unreliable = true
        msg.decoded = true
        msg.encrypted = false
        msg.text = "Counterintelligence decoy on " .. bri_sideLabel(side) .. " channel: activity reported near " .. tostring(math.floor(fx)) .. "," .. tostring(math.floor(fy)) .. "."
        decoy = true
        data.stats.counterDecoys = (tonumber(data.stats.counterDecoys) or 0) + 1
    end

    local markerAdded = NPCRadioInterceptBridge.AddCounterIntelMarker(gmd, player, side, source, metrics) == true
    local text = bri_sideLabel(side) .. " counterintelligence may have detected your radio activity. Channel reliability reduced."
    if decoy then text = text .. " Possible decoy traffic injected." end
    if markerAdded then text = text .. " Triangulation marker added." end
    return {detected=true, side=side, text=text, decoy=decoy, markerAdded=markerAdded, chance=chance}
end


function NPCRadioInterceptBridge.GetRadioSilenceUntil(gmd, player)
    local data = NPCRadioInterceptBridge.EnsureData(gmd)
    if not data then return 0 end
    local pid = bri_counterPid(player)
    local untilAt = tonumber(data.radioSilence and data.radioSilence[pid] or 0) or 0
    if untilAt <= bri_now() then
        if data.radioSilence then data.radioSilence[pid] = nil end
        return 0
    end
    return untilAt
end

function NPCRadioInterceptBridge.IsRadioSilenced(gmd, player)
    return NPCRadioInterceptBridge.GetRadioSilenceUntil(gmd, player) > bri_now()
end

function NPCRadioInterceptBridge.SetRadioSilence(gmd, player, enabled)
    local data = NPCRadioInterceptBridge.EnsureData(gmd)
    if not data then return nil end
    local pid = bri_counterPid(player)
    data.radioSilence = data.radioSilence or {}
    local state = NPCRadioInterceptBridge.EnsureReceiverState(gmd, player)
    if enabled == true then
        data.radioSilence[pid] = bri_now() + NPCRadioInterceptBridge.RadioSilenceHours()
        if state then
            state.monitoring = false
            state.monitorNextAt = 0
            state.updatedAt = bri_now()
        end
        local reduction = NPCRadioInterceptBridge.RadioSilenceHeatReduction()
        local rows = data.counterIntel and data.counterIntel.players and data.counterIntel.players[pid]
        if type(rows) == "table" and reduction > 0 then
            for _, row in pairs(rows) do
                if type(row) == "table" then
                    row.heat = math.max(0, (tonumber(row.heat) or 0) - reduction)
                    row.lastAt = bri_now()
                end
            end
        end
    else
        data.radioSilence[pid] = nil
    end
    return data.radioSilence[pid] or 0
end

function NPCRadioInterceptBridge.RadioSilenceStatusText(gmd, player)
    local untilAt = NPCRadioInterceptBridge.GetRadioSilenceUntil(gmd, player)
    if untilAt <= bri_now() then return "radio silence OFF" end
    local minutes = math.max(1, math.ceil((untilAt - bri_now()) * 60))
    return "radio silence " .. tostring(minutes) .. "m"
end

function NPCRadioInterceptBridge.GetReceiverScanArgs(gmd, player)
    local state = NPCRadioInterceptBridge.EnsureReceiverState(gmd, player)
    if not state then return {} end
    return {
        frequency = state.frequency,
        gain = state.gain,
        squelch = state.squelch,
        filter = state.filter
    }
end

function NPCRadioInterceptBridge.AdjustReceiver(gmd, player, args)
    local state = NPCRadioInterceptBridge.EnsureReceiverState(gmd, player)
    if not state then return nil end
    args = type(args) == "table" and args or {}
    local action = tostring(args.action or "")
    if action == "freqDelta" then
        state.frequency = bri_clamp((tonumber(state.frequency) or NPCRadioInterceptBridge.SideFrequency("red")) + (tonumber(args.value) or 0), 80.0, 200.0)
    elseif action == "setFrequency" then
        state.frequency = bri_clamp(bri_normalizeFrequency(args.value) or state.frequency or NPCRadioInterceptBridge.SideFrequency("red"), 80.0, 200.0)
    elseif action == "side" then
        state.frequency = NPCRadioInterceptBridge.SideFrequency(args.value or args.side or "red")
    elseif action == "gainDelta" then
        state.gain = bri_clamp((tonumber(state.gain) or 55) + (tonumber(args.value) or 0), 0, 100)
    elseif action == "squelchDelta" then
        state.squelch = bri_clamp((tonumber(state.squelch) or 35) + (tonumber(args.value) or 0), 0, 100)
    elseif action == "setFilter" then
        state.filter = tostring(args.value or "wide") == "narrow" and "narrow" or "wide"
    elseif action == "monitor" then
        state.monitoring = args.value == true or tostring(args.value or ""):lower() == "true" or tostring(args.value or "") == "1"
        state.monitorNextAt = bri_now()
    elseif action == "reset" then
        local defaults = bri_receiverDefaults()
        state.frequency = defaults.frequency
        state.gain = defaults.gain
        state.squelch = defaults.squelch
        state.filter = defaults.filter
        state.monitoring = false
        state.monitorLastAt = 0
        state.monitorNextAt = 0
    end
    state.frequency = bri_clamp(bri_normalizeFrequency(state.frequency) or NPCRadioInterceptBridge.SideFrequency("red"), 80.0, 200.0)
    state.gain = bri_clamp(state.gain or 55, 0, 100)
    state.squelch = bri_clamp(state.squelch or 35, 0, 100)
    if state.filter ~= "narrow" then state.filter = "wide" end
    state.monitoring = state.monitoring == true
    state.monitorLastAt = tonumber(state.monitorLastAt) or 0
    state.monitorNextAt = tonumber(state.monitorNextAt) or 0
    state.updatedAt = bri_now()
    return state
end

function NPCRadioInterceptBridge.ReceiverStatusText(gmd, player)
    local state = NPCRadioInterceptBridge.EnsureReceiverState(gmd, player)
    if not state then return "Receiver unavailable." end
    local text = "Receiver " .. string.format("%.2f MHz", tonumber(state.frequency) or 0) .. " / gain " .. tostring(math.floor((tonumber(state.gain) or 0) + 0.5)) .. " / squelch " .. tostring(math.floor((tonumber(state.squelch) or 0) + 0.5)) .. " / filter " .. tostring(state.filter or "wide")
    text = text .. " / monitor " .. (state.monitoring and "ON" or "OFF")
    if state.monitoring and state.monitorNextAt and state.monitorNextAt > 0 then
        local wait = math.max(0, math.ceil((tonumber(state.monitorNextAt) - bri_now()) * 60))
        text = text .. " / next " .. tostring(wait) .. "m"
    end
    if type(state.lastMetrics) == "table" then
        text = text .. " / last S" .. tostring(state.lastMetrics.signal or 0) .. " N" .. tostring(state.lastMetrics.noise or 0) .. " L" .. tostring(state.lastMetrics.lock or 0)
    end
    if NPCRadioInterceptBridge.CounterIntelStatusText then
        text = text .. " / " .. NPCRadioInterceptBridge.CounterIntelStatusText(gmd, player)
    end
    if NPCRadioInterceptBridge.RadioSilenceStatusText then
        text = text .. " / " .. NPCRadioInterceptBridge.RadioSilenceStatusText(gmd, player)
    end
    return text
end

function NPCRadioInterceptBridge.SetReceiverMonitoring(gmd, player, enabled)
    local state = NPCRadioInterceptBridge.EnsureReceiverState(gmd, player)
    if not state then return nil end
    state.monitoring = enabled == true
    state.monitorNextAt = bri_now()
    state.updatedAt = bri_now()
    return state
end

function NPCRadioInterceptBridge.ShouldMonitorScan(gmd, player)
    if not NPCRadioInterceptBridge.IsEnabled() then return false, "disabled" end
    if not NPCRadioInterceptBridge.MonitorEnabled() then return false, "monitor_disabled" end
    local state = NPCRadioInterceptBridge.EnsureReceiverState(gmd, player)
    if not state or state.monitoring ~= true then return false, "not_monitoring" end
    if NPCRadioInterceptBridge.IsRadioSilenced(gmd, player) then return false, "radio_silence", state end
    local radioOk, radioReason = NPCRadioInterceptBridge.HasPoweredRadio(player)
    if not radioOk then return false, radioReason or "no_radio", state end
    local now = bri_now()
    if tonumber(state.monitorNextAt) and tonumber(state.monitorNextAt) > now then
        return false, "wait", state
    end
    return true, nil, state
end

function NPCRadioInterceptBridge.MarkMonitorScan(state)
    if type(state) ~= "table" then return end
    local now = bri_now()
    state.monitorLastAt = now
    state.monitorNextAt = now + NPCRadioInterceptBridge.MonitorTickHours()
    state.updatedAt = now
end

function NPCRadioInterceptBridge.CanScan(gmd, player)
    if not NPCRadioInterceptBridge.IsEnabled() then return false, "disabled" end
    local radioOk, radioReason = NPCRadioInterceptBridge.HasPoweredRadio(player)
    if not radioOk then return false, radioReason or "no_radio" end
    local data = NPCRadioInterceptBridge.EnsureData(gmd)
    if NPCRadioInterceptBridge.IsRadioSilenced(gmd, player) then
        return false, "radio_silence", NPCRadioInterceptBridge.GetRadioSilenceUntil(gmd, player) - bri_now()
    end
    local pid = tostring(bri_playerId(player) or "0")
    local now = bri_now()
    local nextAt = tonumber(data and data.playerCooldowns and data.playerCooldowns[pid] or 0) or 0
    if nextAt > now then return false, "cooldown", nextAt - now end
    return true, "ok"
end

function NPCRadioInterceptBridge.SetCooldown(gmd, player)
    local data = NPCRadioInterceptBridge.EnsureData(gmd)
    if not data then return end
    local pid = tostring(bri_playerId(player) or "0")
    data.playerCooldowns[pid] = bri_now() + NPCRadioInterceptBridge.CooldownHours()
end

local function bri_push(candidates, kind, side, x, y, text, weight, data)
    if not text then return end
    candidates[#candidates + 1] = {
        kind = kind or "signal",
        side = bri_side(side),
        x = tonumber(x),
        y = tonumber(y),
        text = tostring(text),
        weight = tonumber(weight) or 1,
        data = data
    }
end

local function bri_collectCheckpoints(gmd, candidates)
    local data = gmd and (gmd.NPCCheckpointsBridge or gmd.NPCCheckpointsBridge)
    if type(data) ~= "table" or type(data.active) ~= "table" then return end
    for _, cp in pairs(data.active) do
        if type(cp) == "table" and cp.status ~= "removed" and cp.x and cp.y then
            local side = bri_side(cp.side or cp.checkpointSide)
            local text = bri_sideLabel(side) .. " checkpoint demanding " .. tostring(cp.tollAmount or 0) .. " " .. tostring(cp.tollLabel or cp.tollResource or "supplies") .. " near " .. math.floor(tonumber(cp.x) or 0) .. "," .. math.floor(tonumber(cp.y) or 0) .. "."
            bri_push(candidates, "checkpoint", side, cp.x, cp.y, text, 4, cp)
        end
    end
end

local function bri_collectConvoys(gmd, candidates)
    local data = gmd and (gmd.NPCConvoysBridge or gmd.NPCConvoysBridge)
    if type(data) ~= "table" or type(data.active) ~= "table" then return end
    for _, convoy in pairs(data.active) do
        if type(convoy) == "table" and (convoy.status == "active" or convoy.status == "arrived") and convoy.x and convoy.y then
            local side = bri_side(convoy.side or convoy.factionSide)
            local cargo = tostring(convoy.cargoLabel or convoy.cargoResource or "cargo")
            local target = tostring(convoy.targetName or "drop point")
            local progress = math.floor((tonumber(convoy.progress) or 0) * 100)
            local text = bri_sideLabel(side) .. " convoy hauling " .. cargo .. " moving toward " .. target .. " / signal grid " .. math.floor(tonumber(convoy.x) or 0) .. "," .. math.floor(tonumber(convoy.y) or 0) .. " / " .. tostring(progress) .. "% route."
            bri_push(candidates, "convoy", side, convoy.x, convoy.y, text, 5, convoy)
        end
    end
end

local function bri_baseCamps(gmd)
    if NPCBaseCampSystem and NPCBaseCampSystem.GetBaseCamps then
        local ok, camps = pcall(function() return NPCBaseCampSystem.GetBaseCamps() end)
        if ok and type(camps) == "table" then return camps end
    end
    return gmd and gmd.BaseCamps or {}
end

local function bri_collectBases(gmd, candidates)
    local camps = bri_baseCamps(gmd)
    for _, base in pairs(camps or {}) do
        if type(base) == "table" and base.x and base.y then
            local side = bri_side(base.owner or base.captureTeam or base.factionSide or base.side)
            local status = tostring(base.status or base.captureStatus or "active")
            local baseName = tostring(base.name or base.title or base.baseName or ("base " .. tostring(base.id or "?")))
            local readiness = tonumber(base.garrisonReadiness or base.readiness or base.logisticsReadiness)
            local rtext = readiness and (" readiness " .. tostring(math.floor(readiness)) .. ".") or "."
            local text = bri_sideLabel(side) .. " base transmission: " .. baseName .. " status " .. status .. " near " .. math.floor(tonumber(base.x) or 0) .. "," .. math.floor(tonumber(base.y) or 0) .. rtext
            bri_push(candidates, "base", side, base.x, base.y, text, 3, base)
        end
    end
end

local function bri_collectLeaders(gmd, candidates)
    if not (NPCLeadersBridge and NPCLeadersBridge.GetRadioCandidates) then return end
    local list = NPCLeadersBridge.GetRadioCandidates(gmd)
    for _, item in ipairs(list or {}) do
        bri_push(candidates, item.kind or "leader", item.side, item.x, item.y, item.text, item.weight or 3, item.data)
    end
end

local function bri_collectBlackMarkets(gmd, candidates)
    if not (NPCBlackMarketBridge and NPCBlackMarketBridge.GetRadioCandidates) then return end
    local list = NPCBlackMarketBridge.GetRadioCandidates(gmd)
    for _, item in ipairs(list or {}) do
        bri_push(candidates, item.kind or "black_market", item.side, item.x, item.y, item.text, item.weight or 3, item.data)
    end
end

local function bri_collectBounties(gmd, candidates)
    local data = gmd and gmd.NPCBountyBridge
    if type(data) ~= "table" or type(data.players) ~= "table" then return end
    for _, rec in pairs(data.players) do
        if type(rec) == "table" and type(rec.bySide) == "table" then
            for side, sideRec in pairs(rec.bySide) do
                if type(sideRec) == "table" and NPCBountyBridge and NPCBountyBridge.IsSideRecordActive and NPCBountyBridge.IsSideRecordActive(sideRec, NPCBountyBridge.WantedThreshold()) then
                    local x = tonumber(sideRec.lastKnownX)
                    local y = tonumber(sideRec.lastKnownY)
                    local value = math.floor((tonumber(sideRec.value) or 0) + 0.5)
                    local text = bri_sideLabel(side) .. " faction bounty broadcast: " .. tostring(sideRec.playerName or rec.playerName or "unknown") .. " wanted / bounty " .. tostring(value) .. " / last grid " .. tostring(math.floor(x or 0)) .. "," .. tostring(math.floor(y or 0)) .. "."
                    bri_push(candidates, "bounty", side, x, y, text, 4, sideRec)
                end
            end
        end
    end
end


local function bri_supplyCacheAllowedContainer(container, object)
    if not container then return false end
    local ctype = ""
    if container.getType then
        local ok, value = pcall(function() return container:getType() end)
        if ok and value then ctype = tostring(value):lower() end
    end
    if ctype == "floor" or ctype == "inventorymale" or ctype == "inventoryfemale" or ctype == "corpse" or ctype == "zombie" then return false end
    if object and object.getObjectName then
        local ok, value = pcall(function() return object:getObjectName() end)
        local name = ok and value and tostring(value):lower() or ""
        if name == "deadbody" or name == "zombie" then return false end
    end
    return true
end

local function bri_supplyCacheContainerLabel(container, object)
    if container and container.getType then
        local ok, value = pcall(function() return container:getType() end)
        if ok and value and tostring(value) ~= "" then return tostring(value) end
    end
    if object and object.getObjectName then
        local ok, value = pcall(function() return object:getObjectName() end)
        if ok and value and tostring(value) ~= "" then return tostring(value) end
    end
    return "container"
end

local function bri_supplyCacheModData(object, container)
    if object and object.getModData then
        local ok, md = pcall(function() return object:getModData() end)
        if ok and type(md) == "table" then return md end
    end
    if container and container.getModData then
        local ok, md = pcall(function() return container:getModData() end)
        if ok and type(md) == "table" then return md end
    end
    return nil
end

local function bri_supplyCacheVisitSquare(square, out, seen, px, py)
    if not (square and square.getObjects) then return end
    local okObjects, objects = pcall(function() return square:getObjects() end)
    if not (okObjects and objects and objects.size and objects.get) then return end
    for i = 0, objects:size() - 1 do
        local okObj, object = pcall(function() return objects:get(i) end)
        if okObj and object and object.getContainer then
            local okCont, container = pcall(function() return object:getContainer() end)
            if okCont and container and bri_supplyCacheAllowedContainer(container, object) then
                local md = bri_supplyCacheModData(object, container)
                if not (md and md[BRI_SUPPLY_CACHE_LEGACY_KEYS.enabled] == true) then
                    local x = square.getX and square:getX() or nil
                    local y = square.getY and square:getY() or nil
                    local z = square.getZ and square:getZ() or 0
                    local key = tostring(math.floor(tonumber(x) or 0)) .. ":" .. tostring(math.floor(tonumber(y) or 0)) .. ":" .. tostring(math.floor(tonumber(z) or 0)) .. ":" .. tostring(i)
                    if not seen[key] then
                        seen[key] = true
                        out[#out + 1] = {
                            x = tonumber(x),
                            y = tonumber(y),
                            z = tonumber(z) or 0,
                            objectIndex = i,
                            label = bri_supplyCacheContainerLabel(container, object),
                            distance = bri_dist(px or x or 0, py or y or 0, x or 0, y or 0)
                        }
                    end
                end
            end
        end
    end
end

local function bri_supplyCacheFindContainers(player)
    local px, py = bri_playerXY(player)
    if not (px and py and getCell) then return {} end
    local cell = getCell()
    if not cell or not cell.getGridSquare then return {} end
    local radius = math.floor(NPCRadioInterceptBridge.SupplyCacheSearchRadius())
    local z = 0
    if player and player.getZ then
        local okZ, value = pcall(function() return player:getZ() end)
        if okZ and value then z = math.floor(tonumber(value) or 0) end
    end

    local out = {}
    local seen = {}
    local function visit(x, y)
        local okSq, square = pcall(function() return cell:getGridSquare(math.floor(x), math.floor(y), z) end)
        if okSq and square then bri_supplyCacheVisitSquare(square, out, seen, px, py) end
    end

    local closeRadius = math.min(radius, 14)
    for dx = -closeRadius, closeRadius do
        for dy = -closeRadius, closeRadius do
            visit(px + dx, py + dy)
        end
    end

    local attempts = math.max(80, math.min(320, radius * 4))
    for _ = 1, attempts do
        local dx = bri_rand(radius * 2 + 1) - radius
        local dy = bri_rand(radius * 2 + 1) - radius
        visit(px + dx, py + dy)
    end

    table.sort(out, function(a, b) return (tonumber(a.distance) or 999999) < (tonumber(b.distance) or 999999) end)
    return out
end

local function bri_collectSupplyCaches(gmd, candidates, player)
    if not (NPCRadioInterceptBridge.SupplyCacheEnabled() and player) then return end
    if bri_rand(100) >= NPCRadioInterceptBridge.SupplyCacheSignalChance() then return end
    local containers = bri_supplyCacheFindContainers(player)
    if #containers <= 0 then return end
    local limit = math.min(#containers, 12)
    local picked = containers[1 + bri_rand(limit)] or containers[1]
    if not (picked and picked.x and picked.y) then return end
    local side = BRI_SIDES[1 + bri_rand(#BRI_SIDES)] or "red"
    local text = "Supply cache signal: hidden stash in an existing " .. tostring(picked.label or "container") .. " near " .. tostring(math.floor(picked.x)) .. "," .. tostring(math.floor(picked.y)) .. "."
    bri_push(candidates, "supply_cache", side, picked.x, picked.y, text, 6, {
        cacheX = picked.x,
        cacheY = picked.y,
        cacheZ = picked.z or 0,
        objectIndex = picked.objectIndex,
        containerLabel = picked.label
    })
end

local BRI_SUPPLY_CACHE_LOOT = {
    gold = {
        "Base.Necklace_Gold", "Base.Necklace_GoldDiamond", "Base.Necklace_GoldRuby", "Base.Ring_Left_RingFinger_Gold", "Base.Ring_Right_RingFinger_Gold", "Base.Earring_LoopLrg_Gold", "Base.Bracelet_LeftGold", "Base.WristWatch_Left_ClassicGold", "Base.WristWatch_Right_ClassicGold"
    },
    silver = {
        "Base.Necklace_Silver", "Base.Necklace_SilverCrucifix", "Base.Ring_Left_RingFinger_Silver", "Base.Ring_Right_RingFinger_Silver", "Base.Earring_LoopLrg_Silver", "Base.Bracelet_LeftSilver", "Base.WristWatch_Left_ClassicBlack", "Base.WristWatch_Right_ClassicBlack"
    },
    weapons = {
        "Base.HuntingRifle", "Base.VarmintRifle", "Base.Shotgun", "Base.DoubleBarrelShotgun", "Base.308BulletsBox", "Base.223BulletsBox", "Base.ShotgunShellsBox", "Base.308Clip", "Base.223Clip"
    },
    armor = {
        "Base.Vest_BulletPolice", "Base.Vest_BulletArmy", "Base.Hat_Army", "Base.Hat_ArmyHelmet", "Base.Jacket_ArmyCamoGreen", "Base.Trousers_ArmyService", "Base.Gloves_LeatherGlovesBlack", "Base.Shoes_ArmyBoots"
    },
    medical = {
        "Base.FirstAidKit", "Base.Bandage", "Base.AlcoholWipes", "Base.Disinfectant", "Base.Pills", "Base.PillsBeta", "Base.PillsPainkillers", "Base.SutureNeedle", "Base.Tweezers", "Base.Splint"
    }
}

local BRI_SUPPLY_CACHE_TIER_LABELS = {
    gold = "gold valuables",
    silver = "silver valuables",
    weapons = "elite rifle cache",
    armor = "armor cache",
    medical = "medical cache"
}

local function bri_supplyCacheTier()
    local roll = bri_rand(100)
    if roll < 20 then return "gold" end
    if roll < 40 then return "silver" end
    if roll < 64 then return "weapons" end
    if roll < 82 then return "armor" end
    return "medical"
end

local function bri_supplyCacheGetObject(player, msg)
    if not (getCell and msg and msg.data) then return nil, nil end
    local cell = getCell()
    if not cell or not cell.getGridSquare then return nil, nil end
    local x = math.floor(tonumber(msg.data.cacheX or msg.x) or 0)
    local y = math.floor(tonumber(msg.data.cacheY or msg.y) or 0)
    local z = math.floor(tonumber(msg.data.cacheZ) or 0)
    local okSq, square = pcall(function() return cell:getGridSquare(x, y, z) end)
    if not (okSq and square and square.getObjects) then return nil, nil end
    local okObjects, objects = pcall(function() return square:getObjects() end)
    if not (okObjects and objects and objects.size and objects.get) then return nil, nil end
    local preferred = tonumber(msg.data.objectIndex)
    local function tryIndex(index)
        if index == nil or index < 0 or index >= objects:size() then return nil, nil end
        local okObj, object = pcall(function() return objects:get(index) end)
        if okObj and object and object.getContainer then
            local okCont, container = pcall(function() return object:getContainer() end)
            if okCont and container and bri_supplyCacheAllowedContainer(container, object) then return object, container end
        end
        return nil, nil
    end
    local object, container = tryIndex(preferred)
    if object and container then return object, container end
    for i = 0, objects:size() - 1 do
        object, container = tryIndex(i)
        if object and container then return object, container end
    end
    return nil, nil
end

local function bri_supplyCacheClear(container)
    if not container then return end
    if container.getItems then
        local okItems, items = pcall(function() return container:getItems() end)
        if okItems and items and items.size and items.get then
            local guard = 0
            while items:size() > 0 and guard < 500 do
                guard = guard + 1
                local okItem, item = pcall(function() return items:get(0) end)
                if not (okItem and item) then break end
                pcall(function() container:Remove(item) end)
                if container.removeItemOnServer then pcall(function() container:removeItemOnServer(item) end) end
            end
        end
    end
    if container.setExplored then pcall(function() container:setExplored(true) end) end
end

local function bri_supplyCacheAddItem(container, fullType)
    if not (container and container.AddItem and fullType) then return false end
    local ok, item = pcall(function() return container:AddItem(fullType) end)
    if not ok or not item then return false end
    if container.addItemOnServer then pcall(function() container:addItemOnServer(item) end) end
    return true
end

local function bri_supplyCacheFill(container, tier)
    local pool = BRI_SUPPLY_CACHE_LOOT[tier] or BRI_SUPPLY_CACHE_LOOT.medical
    local maxItems = NPCRadioInterceptBridge.SupplyCacheMaxItems()
    local target = math.max(4, maxItems - bri_rand(math.max(1, math.floor(maxItems * 0.35))))
    if tier == "weapons" then target = math.max(8, math.floor(target * 0.75)) end
    if tier == "gold" or tier == "silver" then target = math.max(8, target) end
    local added = 0
    local guard = target * 6
    while added < target and guard > 0 do
        guard = guard - 1
        local fullType = pool[1 + bri_rand(#pool)] or pool[1]
        if bri_supplyCacheAddItem(container, fullType) then added = added + 1 end
    end
    if added <= 0 and tier ~= "medical" then
        pool = BRI_SUPPLY_CACHE_LOOT.medical
        guard = target * 4
        while added < target and guard > 0 do
            guard = guard - 1
            local fullType = pool[1 + bri_rand(#pool)] or pool[1]
            if bri_supplyCacheAddItem(container, fullType) then added = added + 1 end
        end
    end
    return added
end

function NPCRadioInterceptBridge.ActivateSupplyCache(gmd, player, msg, marker)
    if not (NPCRadioInterceptBridge.SupplyCacheEnabled() and msg and msg.kind == "supply_cache") then return false, "disabled" end
    local object, container = bri_supplyCacheGetObject(player, msg)
    if not (object and container) then return false, "missing" end
    local md = bri_supplyCacheModData(object, container)
    if md and md[BRI_SUPPLY_CACHE_LEGACY_KEYS.enabled] == true then
        return false, "already", tostring(md[BRI_SUPPLY_CACHE_LEGACY_KEYS.tier] or "cache"), tonumber(md[BRI_SUPPLY_CACHE_LEGACY_KEYS.items]) or 0
    end
    if bri_rand(100) >= NPCRadioInterceptBridge.SupplyCacheFillChance() then
        if md then
            md[BRI_SUPPLY_CACHE_LEGACY_KEYS.enabled] = true
            md[BRI_SUPPLY_CACHE_LEGACY_KEYS.tier] = "old"
            md[BRI_SUPPLY_CACHE_LEGACY_KEYS.items] = 0
            md[BRI_SUPPLY_CACHE_LEGACY_KEYS.timestamp] = bri_now()
        end
        if object and object.transmitModData then pcall(function() object:transmitModData() end) end
        return false, "old", "old cache", 0
    end

    local tier = bri_supplyCacheTier()
    bri_supplyCacheClear(container)
    local added = bri_supplyCacheFill(container, tier)
    if added <= 0 then return false, "empty", tier, 0 end

    if md then
        md[BRI_SUPPLY_CACHE_LEGACY_KEYS.enabled] = true
        md[BRI_SUPPLY_CACHE_LEGACY_KEYS.tier] = tier
        md[BRI_SUPPLY_CACHE_LEGACY_KEYS.items] = added
        md[BRI_SUPPLY_CACHE_LEGACY_KEYS.timestamp] = bri_now()
    end
    if object and object.transmitModData then pcall(function() object:transmitModData() end) end
    if object and object.transmitUpdatedSpriteToClients then pcall(function() object:transmitUpdatedSpriteToClients() end) end
    if marker then
        marker.supplyCacheActivated = true
        marker.supplyCacheTier = tier
        marker.supplyCacheItems = added
    end
    return true, "filled", tier, added
end

local function bri_collectPasswords(gmd, candidates)
    if not (NPCFactionDocsBridge and NPCFactionDocsBridge.GetDailyPassword) then return end
    if bri_rand(100) >= NPCRadioInterceptBridge.PasswordLeakChance() then return end
    local side = BRI_SIDES[1 + bri_rand(#BRI_SIDES)] or "red"
    local pass = NPCFactionDocsBridge.GetDailyPassword(gmd, side)
    if type(pass) ~= "table" or not pass.password then return end
    local text = "possible " .. bri_sideLabel(side) .. " checkpoint password: " .. tostring(pass.password) .. "."
    bri_push(candidates, "password", side, nil, nil, text, 2, pass)
end

local function bri_weightedPick(candidates)
    if not candidates or #candidates <= 0 then return nil end
    local total = 0
    for _, c in ipairs(candidates) do total = total + (tonumber(c.weight) or 1) end
    if total <= 0 then return candidates[1] end
    local roll = bri_rand(math.floor(total * 1000)) / 1000
    local running = 0
    for _, c in ipairs(candidates) do
        running = running + (tonumber(c.weight) or 1)
        if roll <= running then return c end
    end
    return candidates[#candidates]
end

local function bri_fakeAroundPlayer(player)
    local px = player and player.getX and player:getX() or 0
    local py = player and player.getY and player:getY() or 0
    local angle = (bri_rand(6284) / 1000.0)
    local dist = 250 + bri_rand(1200)
    return px + math.cos(angle) * dist, py + math.sin(angle) * dist
end

local function bri_noiseText(candidate, player)
    local text = tostring(candidate and candidate.text or "weak transmission, no useful data.")
    local unreliable = false
    local falseSignal = false
    if bri_rand(100) < NPCRadioInterceptBridge.FalseChance() then
        falseSignal = true
        unreliable = true
        local fx, fy = bri_fakeAroundPlayer(player)
        local side = BRI_SIDES[1 + bri_rand(#BRI_SIDES)] or "red"
        text = bri_sideLabel(side) .. " encrypted traffic mentions activity near " .. math.floor(fx) .. "," .. math.floor(fy) .. "."
    elseif bri_rand(100) < NPCRadioInterceptBridge.StaleChance() then
        unreliable = true
        text = text .. " Signal may be old."
    end
    if bri_rand(100) < NPCRadioInterceptBridge.IncompleteChance() then
        unreliable = true
        text = text .. " Transmission breaks before confirmation."
    end
    return text, unreliable, falseSignal
end

local function bri_collectSpyIntel(gmd, candidates)
    if type(gmd) ~= "table" or type(gmd.SpyIntel) ~= "table" then return end
    for _, intel in ipairs(gmd.SpyIntel) do
        if type(intel) == "table" and intel.x and intel.y then
            local side = bri_side(intel.side or intel.factionSide or intel.targetSide)
            local title = tostring(intel.title or "spy intel")
            local text = tostring(intel.text or (title .. " near " .. math.floor(tonumber(intel.x) or 0) .. "," .. math.floor(tonumber(intel.y) or 0) .. "."))
            if intel.falseIntel == true or intel.spyIntelFalse == true or intel.confidence == "compromised" then
                text = "Compromised spy relay: " .. text
            else
                text = "Spy relay: " .. text
            end
            bri_push(candidates, "spy_intel", side, intel.x, intel.y, text, intel.elite == true and 7 or 5, intel)
        end
    end
end

local function bri_eventSourceKey(candidate)
    if type(candidate) ~= "table" then return nil end
    local data = type(candidate.data) == "table" and candidate.data or {}
    local direct = data.eventId or data.id or data.groupId or data.baseId or data.sourceId or data.markerId or data.uid or data.persistentId
    if direct ~= nil then return tostring(direct) end
    if candidate.x and candidate.y then
        local bx = math.floor((tonumber(candidate.x) or 0) / 20)
        local by = math.floor((tonumber(candidate.y) or 0) / 20)
        local txt = tostring(candidate.text or "")
        txt = txt:gsub("[^%w_%- ]", "")
        return tostring(bx) .. ":" .. tostring(by) .. ":" .. txt:sub(1, 42)
    end
    return tostring(candidate.text or candidate.kind or "event"):sub(1, 64)
end

local function bri_worldEventKey(candidate)
    local side = bri_side(candidate and candidate.side) or "unknown"
    local kind = tostring(candidate and candidate.kind or "signal")
    return "world:" .. kind .. ":" .. side .. ":" .. tostring(bri_eventSourceKey(candidate) or "unknown")
end

function NPCRadioInterceptBridge.RecordWorldEvent(gmd, candidate)
    if not (NPCRadioInterceptBridge.WorldEventsEnabled() and gmd and type(candidate) == "table" and candidate.text) then return nil end
    local data = NPCRadioInterceptBridge.EnsureData(gmd)
    if not data then return nil end
    data.worldEvents = data.worldEvents or {}
    local now = bri_now()
    local key = bri_worldEventKey(candidate)
    local rec = data.worldEvents[key]
    local isNew = type(rec) ~= "table"
    if isNew then
        rec = {id = key, createdAt = now}
        data.worldEvents[key] = rec
        data.stats.worldEvents = (tonumber(data.stats.worldEvents) or 0) + 1
    end
    rec.kind = tostring(candidate.kind or rec.kind or "signal")
    rec.side = bri_side(candidate.side) or rec.side
    rec.x = tonumber(candidate.x) or rec.x
    rec.y = tonumber(candidate.y) or rec.y
    rec.text = "Live traffic: " .. tostring(candidate.text)
    rec.weight = math.max(1, tonumber(candidate.weight) or tonumber(rec.weight) or 1) + NPCRadioInterceptBridge.WorldEventWeightBonus()
    rec.sourceKind = tostring(candidate.kind or rec.sourceKind or "signal")
    rec.eventTraffic = true
    rec.lastSeenAt = now
    rec.expiresAt = now + NPCRadioInterceptBridge.WorldEventMemoryHours()
    return rec, isNew
end

function NPCRadioInterceptBridge.CleanupWorldEvents(gmd)
    local data = NPCRadioInterceptBridge.EnsureData(gmd)
    if not data then return end
    data.worldEvents = data.worldEvents or {}
    local now = bri_now()
    local rows = {}
    for key, rec in pairs(data.worldEvents) do
        if type(rec) ~= "table" or (tonumber(rec.expiresAt) and tonumber(rec.expiresAt) <= now) then
            data.worldEvents[key] = nil
        else
            rows[#rows + 1] = {key=key, t=tonumber(rec.lastSeenAt or rec.createdAt) or 0}
        end
    end
    local maxCount = NPCRadioInterceptBridge.WorldEventMaxCount()
    if #rows <= maxCount then return end
    table.sort(rows, function(a, b) return (a.t or 0) < (b.t or 0) end)
    for i=1, #rows - maxCount do
        data.worldEvents[rows[i].key] = nil
    end
end

function NPCRadioInterceptBridge.RefreshWorldEvents(gmd, force)
    if not (NPCRadioInterceptBridge.WorldEventsEnabled() and gmd) then return end
    local data = NPCRadioInterceptBridge.EnsureData(gmd)
    if not data then return end
    local now = bri_now()
    if force ~= true and tonumber(data.worldEventNextRefresh or 0) > now then return end
    data.worldEventLastRefresh = now
    data.worldEventNextRefresh = now + NPCRadioInterceptBridge.WorldEventRefreshHours()

    local candidates = {}
    bri_collectConvoys(gmd, candidates)
    bri_collectCheckpoints(gmd, candidates)
    bri_collectBases(gmd, candidates)
    bri_collectLeaders(gmd, candidates)
    bri_collectBlackMarkets(gmd, candidates)
    bri_collectBounties(gmd, candidates)
    bri_collectSpyIntel(gmd, candidates)

    for _, candidate in ipairs(candidates) do
        if candidate.kind ~= "password" and candidate.kind ~= "noise" and candidate.kind ~= "static" then
            NPCRadioInterceptBridge.RecordWorldEvent(gmd, candidate)
        end
    end
    NPCRadioInterceptBridge.CleanupWorldEvents(gmd)
end

local function bri_collectWorldEvents(gmd, candidates)
    if not (NPCRadioInterceptBridge.WorldEventsEnabled() and gmd) then return end
    NPCRadioInterceptBridge.RefreshWorldEvents(gmd, false)
    local data = NPCRadioInterceptBridge.EnsureData(gmd)
    if not (data and type(data.worldEvents) == "table") then return end
    local now = bri_now()
    for _, rec in pairs(data.worldEvents) do
        if type(rec) == "table" and (not rec.expiresAt or tonumber(rec.expiresAt) > now) and rec.text then
            local c = {
                kind = rec.kind or "world_event",
                side = bri_side(rec.side),
                x = tonumber(rec.x),
                y = tonumber(rec.y),
                text = tostring(rec.text),
                weight = tonumber(rec.weight) or NPCRadioInterceptBridge.WorldEventWeightBonus(),
                data = rec,
                eventTraffic = true,
                sourceKind = rec.sourceKind
            }
            candidates[#candidates + 1] = c
        end
    end
end

function NPCRadioInterceptBridge.CollectCandidates(gmd, sideFilter, player)
    local candidates = {}
    bri_collectWorldEvents(gmd, candidates)
    bri_collectConvoys(gmd, candidates)
    bri_collectCheckpoints(gmd, candidates)
    bri_collectBases(gmd, candidates)
    bri_collectLeaders(gmd, candidates)
    bri_collectBlackMarkets(gmd, candidates)
    bri_collectBounties(gmd, candidates)
    bri_collectSpyIntel(gmd, candidates)
    bri_collectSupplyCaches(gmd, candidates, player)
    bri_collectPasswords(gmd, candidates)
    local side = bri_side(sideFilter)
    if side then
        local filtered = {}
        for _, c in ipairs(candidates) do
            if c.side == side or not c.side then filtered[#filtered + 1] = c end
        end
        candidates = filtered
    end
    return candidates
end

local function bri_signalMetrics(candidate, player, args)
    args = type(args) == "table" and args or {}
    local side = bri_side(args.side or (candidate and candidate.side)) or "red"
    local targetFrequency = NPCRadioInterceptBridge.SideFrequency(side)
    local radioInfo = NPCRadioInterceptBridge.GetRadioDeviceInfo(player)
    local frequency = bri_normalizeFrequency(args.frequency) or (radioInfo and radioInfo.frequency) or targetFrequency
    local diff = math.abs((tonumber(frequency) or targetFrequency) - targetFrequency)
    local tolerance = math.max(0.01, NPCRadioInterceptBridge.FrequencyTolerance())
    local tuneScore = bri_clamp(100 - ((diff / tolerance) * 100), 0, 100)

    local px = player and player.getX and player:getX() or nil
    local py = player and player.getY and player:getY() or nil
    local distScore = 78
    local distance = nil
    if px and py and candidate and candidate.x and candidate.y then
        distance = bri_dist(px, py, candidate.x, candidate.y)
        distScore = bri_clamp(100 - ((distance / NPCRadioInterceptBridge.SignalRange()) * 85), 5, 100)
    end

    local gain = bri_clamp(args.gain or 55, 0, 100)
    local squelch = bri_clamp(args.squelch or 35, 0, 100)
    local filter = tostring(args.filter or "wide")
    local filterBonus = filter == "narrow" and 8 or 0
    local noise = bri_clamp(22 + (100 - tuneScore) * 0.45 + (100 - distScore) * 0.28 + gain * 0.10 - squelch * 0.18 - filterBonus, 0, 100)
    local signal = bri_clamp(tuneScore * 0.58 + distScore * 0.42 + gain * 0.12 - noise * 0.10, 0, 100)
    local lock = bri_clamp(signal - noise * 0.34 + filterBonus, 0, 100)

    return {
        side = side,
        frequency = frequency,
        targetFrequency = targetFrequency,
        distance = distance,
        signal = math.floor(signal + 0.5),
        noise = math.floor(noise + 0.5),
        lock = math.floor(lock + 0.5),
        tuned = diff <= tolerance,
        decoded = lock >= NPCRadioInterceptBridge.LockThreshold(),
        partial = lock >= math.max(25, NPCRadioInterceptBridge.LockThreshold() - 25)
    }
end

local function bri_partialText(text)
    text = tostring(text or "")
    if #text <= 36 then return text end
    local words = {}
    for w in string.gmatch(text, "%S+") do
        if #w > 3 then words[#words + 1] = w end
        if #words >= 5 then break end
    end
    if #words <= 0 then return "... signal fragment ..." end
    return "... " .. table.concat(words, " ... ") .. " ..."
end

function NPCRadioInterceptBridge.GenerateMessage(gmd, player)
    local candidates = NPCRadioInterceptBridge.CollectCandidates(gmd, nil, player)
    local chosen = bri_weightedPick(candidates)
    local text, unreliable, falseSignal = bri_noiseText(chosen, player)
    if chosen and chosen.kind == "supply_cache" then
        text = tostring(chosen.text or "Supply cache signal.")
        unreliable = false
        falseSignal = false
    end
    local msg = {
        id = "radio_" .. tostring(math.floor(bri_now() * 1000)) .. "_" .. tostring(bri_rand(100000)),
        kind = chosen and chosen.kind or "noise",
        side = chosen and chosen.side or nil,
        x = chosen and chosen.x or nil,
        y = chosen and chosen.y or nil,
        text = text,
        unreliable = unreliable == true,
        falseSignal = falseSignal == true,
        createdAt = bri_now(),
        playerName = bri_playerName(player),
        eventTraffic = chosen and chosen.eventTraffic == true or false,
        sourceKind = chosen and chosen.sourceKind or nil,
        data = chosen and chosen.data or nil
    }
    return msg
end

local function bri_tunedPick(candidates, player, args)
    if type(candidates) ~= "table" or #candidates <= 0 then return nil end
    local total = 0
    local scored = {}
    for _, candidate in ipairs(candidates) do
        local metrics = bri_signalMetrics(candidate, player, args)
        local lock = tonumber(metrics.lock) or 0
        local weight = math.max(1, tonumber(candidate.weight) or 1) * math.max(1, lock)
        if metrics.tuned then weight = weight * 2 end
        if metrics.decoded then weight = weight * 2 end
        total = total + weight
        scored[#scored + 1] = {candidate=candidate, weight=weight}
    end
    if total <= 0 then return bri_weightedPick(candidates) end
    local roll = bri_rand(math.max(1, math.floor(total)))
    local acc = 0
    for _, entry in ipairs(scored) do
        acc = acc + entry.weight
        if roll <= acc then return entry.candidate end
    end
    return scored[#scored] and scored[#scored].candidate or bri_weightedPick(candidates)
end

local function bri_applyEncryption(gmd, player, msg, metrics)
    if not (msg and metrics and msg.decoded ~= false) then return msg end
    if not NPCRadioInterceptBridge.EncryptionEnabled() then return msg end
    if msg.falseSignal == true or msg.kind == "noise" or msg.kind == "static" then return msg end
    local side = bri_side(msg.side or metrics.side)
    if not side then return msg end
    if NPCRadioInterceptBridge.IsSideDecoded(gmd, player, side) then return msg end
    local chance = NPCRadioInterceptBridge.EncryptionChance(side)
    if chance <= 0 or bri_rand(100) >= chance then return msg end

    local originalText = tostring(msg.text or "")
    local decodedNow, progress = NPCRadioInterceptBridge.RegisterEncryptedTraffic(gmd, player, side, metrics)
    msg.encrypted = true
    msg.encryptedSide = side
    msg.decoderProgress = progress
    if decodedNow then
        msg.encrypted = false
        msg.decrypted = true
        msg.decoded = true
        msg.text = "Decrypted " .. bri_sideLabel(side) .. " traffic: " .. originalText
    else
        msg.decoded = false
        msg.unreliable = true
        msg.text = "Encrypted " .. bri_sideLabel(side) .. " traffic on " .. string.format("%.2f MHz", tonumber(metrics.frequency) or 0) .. ". Decoder progress " .. tostring(math.floor((tonumber(progress) or 0) + 0.5)) .. "%"
    end
    return msg
end

function NPCRadioInterceptBridge.GenerateTunedMessage(gmd, player, args)
    args = type(args) == "table" and args or {}
    local sideFilter = bri_side(args.side)
    local candidates = NPCRadioInterceptBridge.CollectCandidates(gmd, sideFilter, player)
    local chosen = bri_tunedPick(candidates, player, args)
    local metrics = bri_signalMetrics(chosen, player, args)
    NPCRadioInterceptBridge.ApplyCounterIntelPressure(gmd, player, metrics)
    local text, unreliable, falseSignal = bri_noiseText(chosen, player)
    if chosen and chosen.kind == "supply_cache" then
        text = tostring(chosen.text or "Supply cache signal.")
        unreliable = false
        falseSignal = false
    end
    if not metrics.decoded then
        unreliable = true
        if metrics.partial then
            text = "Partial radio fragment " .. string.format("%.2f MHz", metrics.frequency) .. ": " .. bri_partialText(text)
        else
            text = "Only static on " .. string.format("%.2f MHz", metrics.frequency) .. ". Signal not locked."
        end
    end
    local msg = {
        id = "radio_" .. tostring(math.floor(bri_now() * 1000)) .. "_" .. tostring(bri_rand(100000)),
        kind = chosen and chosen.kind or "noise",
        side = chosen and chosen.side or metrics.side,
        x = chosen and chosen.x or nil,
        y = chosen and chosen.y or nil,
        text = text,
        unreliable = unreliable == true or not metrics.decoded,
        falseSignal = falseSignal == true,
        createdAt = bri_now(),
        playerName = bri_playerName(player),
        frequency = metrics.frequency,
        signal = metrics.signal,
        noise = metrics.noise,
        lock = metrics.lock,
        decoded = metrics.decoded == true,
        eventTraffic = chosen and chosen.eventTraffic == true or false,
        sourceKind = chosen and chosen.sourceKind or nil,
        data = chosen and chosen.data or nil
    }
    msg = bri_applyEncryption(gmd, player, msg, metrics)
    return msg, metrics
end

function NPCRadioInterceptBridge.CleanupIntelMarkers(gmd)
    if not gmd then return end
    local data = NPCRadioInterceptBridge.EnsureData(gmd)
    local now = bri_now()
    if type(data.intelMarkers) ~= "table" then data.intelMarkers = {} end
    for id, expiresAt in pairs(data.intelMarkers) do
        if tonumber(expiresAt) and tonumber(expiresAt) <= now then
            data.intelMarkers[id] = nil
            if gmd.DebugMapMarkers then gmd.DebugMapMarkers[tostring(id)] = nil end
            if sendServerCommand then pcall(function() sendServerCommand('NPCDebugMap', 'Remove', {id=tostring(id)}) end) end
        end
    end
end

function NPCRadioInterceptBridge.AddIntelMarker(gmd, player, msg, metrics)
    if not (gmd and msg and msg.x and msg.y) then return false end
    if not NPCRadioInterceptBridge.MarkerEnabled() then return false end
    metrics = type(metrics) == "table" and metrics or msg
    if (tonumber(metrics.lock or msg.lock) or 0) < NPCRadioInterceptBridge.MinMarkerLock() then return false end
    local data = NPCRadioInterceptBridge.EnsureData(gmd)
    if not data then return false end
    NPCRadioInterceptBridge.CleanupIntelMarkers(gmd)
    data.intelMarkers = data.intelMarkers or {}
    gmd.DebugMapMarkers = gmd.DebugMapMarkers or {}

    local isSupplyCache = msg.kind == "supply_cache"
    local noise = NPCRadioInterceptBridge.MarkerNoiseTiles()
    local mx = tonumber(msg.x) or 0
    local my = tonumber(msg.y) or 0
    if noise > 0 and msg.falseSignal ~= true and not isSupplyCache then
        mx = mx + (bri_rand(math.floor(noise * 2) + 1) - noise)
        my = my + (bri_rand(math.floor(noise * 2) + 1) - noise)
    end
    local id = "radio_intel:" .. tostring(msg.id or tostring(bri_now()))
    local expiresAt = bri_now() + NPCRadioInterceptBridge.MarkerHours()
    local marker = {
        id = id,
        markerType = "intel",
        x = mx,
        y = my,
        z = 0,
        side = msg.side,
        name = isSupplyCache and "Supply cache" or "Radio intel",
        intelType = msg.kind or "radio",
        intelFalse = (not isSupplyCache) and (msg.unreliable == true or msg.falseSignal == true) or false,
        radioIntel = true,
        supplyCache = isSupplyCache,
        radioWorldEvent = msg.eventTraffic == true,
        radioSourceKind = msg.sourceKind,
        signal = metrics.signal or msg.signal,
        noise = metrics.noise or msg.noise,
        lock = metrics.lock or msg.lock,
        expiresAt = expiresAt,
        updatedAt = bri_now()
    }
    if isSupplyCache and NPCRadioInterceptBridge.ActivateSupplyCache then
        local okCache, cacheStatus, cacheTier, cacheItems = NPCRadioInterceptBridge.ActivateSupplyCache(gmd, player, msg, marker)
        marker.supplyCacheStatus = cacheStatus
        marker.supplyCacheTier = cacheTier
        marker.supplyCacheItems = cacheItems
        if okCache then
            local label = BRI_SUPPLY_CACHE_TIER_LABELS[tostring(cacheTier or "")] or tostring(cacheTier or "supply")
            msg.text = tostring(msg.text or "Supply cache signal.") .. " Cache prepared: " .. label .. ", " .. tostring(cacheItems or 0) .. " items."
        elseif cacheStatus == "old" then
            msg.text = tostring(msg.text or "Supply cache signal.") .. " Cache lead was old; the marked container may still hold ordinary loot."
        elseif cacheStatus == "already" then
            msg.text = tostring(msg.text or "Supply cache signal.") .. " Cache was already prepared earlier."
        else
            msg.text = tostring(msg.text or "Supply cache signal.") .. " Cache container could not be prepared; check the marked container anyway."
        end
    end

    gmd.DebugMapMarkers[id] = marker
    data.intelMarkers[id] = expiresAt
    if NPCNetContract and NPCNetContract.SendDebugMapUpdate then
        NPCNetContract.SendDebugMapUpdate(marker)
    elseif sendServerCommand then
        pcall(function() sendServerCommand('NPCDebugMap', 'Update', marker) end)
    end
    return true
end

local function bri_historyPid(player)
    return tostring(bri_playerId(player) or "0")
end

function NPCRadioInterceptBridge.CleanupPlayerHistory(gmd, player)
    local data = NPCRadioInterceptBridge.EnsureData(gmd)
    if not data then return 0 end
    local pid = bri_historyPid(player)
    data.playerHistory[pid] = data.playerHistory[pid] or {}
    local history = data.playerHistory[pid]
    local now = bri_now()
    local maxAge = NPCRadioInterceptBridge.HistoryMaxAgeHours()
    local cleaned = {}
    for _, msg in ipairs(history) do
        if type(msg) == "table" then
            local createdAt = tonumber(msg.createdAt) or now
            if maxAge <= 0 or (now - createdAt) <= maxAge then
                cleaned[#cleaned + 1] = msg
            end
        end
    end
    local limit = NPCRadioInterceptBridge.HistoryLimit()
    while #cleaned > limit do table.remove(cleaned) end
    data.playerHistory[pid] = cleaned
    return #cleaned
end

function NPCRadioInterceptBridge.ClearHistory(gmd, player)
    local data = NPCRadioInterceptBridge.EnsureData(gmd)
    if not data then return false end
    local pid = bri_historyPid(player)
    data.playerHistory[pid] = {}
    return true
end

function NPCRadioInterceptBridge.AddHistory(gmd, player, msg)
    local data = NPCRadioInterceptBridge.EnsureData(gmd)
    local pid = bri_historyPid(player)
    if not (data and msg) then return end
    NPCRadioInterceptBridge.CleanupPlayerHistory(gmd, player)
    data.playerHistory[pid] = data.playerHistory[pid] or {}
    table.insert(data.playerHistory[pid], 1, msg)
    local limit = NPCRadioInterceptBridge.HistoryLimit()
    while #data.playerHistory[pid] > limit do table.remove(data.playerHistory[pid]) end
    data.stats.messages = (tonumber(data.stats.messages) or 0) + 1
    if msg.falseSignal then data.stats.falseSignals = (tonumber(data.stats.falseSignals) or 0) + 1 end
end

local function bri_historySideText(side)
    side = bri_side(side)
    if not side then return "unknown" end
    return bri_sideLabel(side)
end

local function bri_historyAgeText(createdAt)
    local ageMinutes = math.max(0, math.floor((bri_now() - (tonumber(createdAt) or bri_now())) * 60 + 0.5))
    if ageMinutes < 60 then return tostring(ageMinutes) .. "m" end
    return tostring(math.floor(ageMinutes / 60)) .. "h"
end

function NPCRadioInterceptBridge.HistoryText(gmd, player)
    local data = NPCRadioInterceptBridge.EnsureData(gmd)
    local pid = bri_historyPid(player)
    NPCRadioInterceptBridge.CleanupPlayerHistory(gmd, player)
    local history = data and data.playerHistory and data.playerHistory[pid]
    if type(history) ~= "table" or #history <= 0 then return "No radio intercepts stored." end
    local parts = {}
    for i=1, math.min(#history, 6) do
        local msg = history[i]
        if type(msg) == "table" and msg.text then
            local tag = bri_historySideText(msg.side) .. "/" .. tostring(msg.kind or "signal")
            local flags = ""
            if msg.encrypted then flags = flags .. " encrypted" end
            if msg.decrypted then flags = flags .. " decoded" end
            if msg.falseSignal or msg.unreliable then flags = flags .. " unreliable" end
            if msg.eventTraffic then flags = flags .. " live" end
            parts[#parts + 1] = tostring(i) .. ") [" .. bri_historyAgeText(msg.createdAt) .. " " .. tag .. flags .. "] " .. tostring(msg.text)
        end
    end
    return table.concat(parts, " / ")
end

function NPCRadioInterceptBridge.SummaryText(gmd, player)
    local data = NPCRadioInterceptBridge.EnsureData(gmd)
    local state = NPCRadioInterceptBridge.EnsureReceiverState(gmd, player)
    NPCRadioInterceptBridge.CleanupPlayerHistory(gmd, player)
    if NPCRadioInterceptBridge.CleanupIntelMarkers then NPCRadioInterceptBridge.CleanupIntelMarkers(gmd) end
    if NPCRadioInterceptBridge.CleanupCounterIntelMarkers then NPCRadioInterceptBridge.CleanupCounterIntelMarkers(gmd) end
    local pid = bri_historyPid(player)
    local history = data and data.playerHistory and data.playerHistory[pid] or {}
    local events = type(data and data.worldEvents) == "table" and #data.worldEvents or 0
    local markerCount = 0
    if type(data and data.intelMarkers) == "table" then
        for _ in pairs(data.intelMarkers) do markerCount = markerCount + 1 end
    end
    local freq = state and string.format("%.2f", tonumber(state.frequency) or 0) or "0.00"
    local monitor = state and state.monitoring and "monitor ON" or "monitor OFF"
    local last = "no scan"
    if state and type(state.lastMetrics) == "table" then
        last = "S" .. tostring(state.lastMetrics.signal or 0) .. " N" .. tostring(state.lastMetrics.noise or 0) .. " L" .. tostring(state.lastMetrics.lock or 0)
    end
    return "Radio summary: " .. tostring(freq) .. " MHz / " .. monitor .. " / " .. last .. " / history " .. tostring(#history) .. " / events " .. tostring(events) .. " / markers " .. tostring(markerCount) .. " / " .. NPCRadioInterceptBridge.RadioSilenceStatusText(gmd, player)
end
