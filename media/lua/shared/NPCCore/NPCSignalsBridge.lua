-- NPCSignalsBridge.lua
-- Neutral shared backend for lightweight signal items and field commands for hired squads.
-- Uses existing inventory items when available; does not register new physical items.

NPCSignalsBridge = NPCSignalsBridge or {}

NPCSignalsBridge.Actions = {
    rally = {
        label="Whistle: rally bodyguards",
        signalLabel="whistle",
        keywords={"whistle"},
        orderName="Follow",
        fireMode="Defensive",
        formation="ring",
        followDistance=3.0,
        markerLabel="RALLY"
    },
    smoke = {
        label="Smoke: fall back to me",
        signalLabel="smoke",
        keywords={"smoke", "smokebomb", "smoke bomb", "smokegrenade", "smoke grenade"},
        orderName="Return",
        fireMode="HoldFire",
        formation="close",
        followDistance=3.0,
        markerLabel="SMOKE"
    },
    attack = {
        label="Flare: mark attack point",
        signalLabel="flare",
        keywords={"flare", "roadflare", "road flare", "signal flare", "flares"},
        orderName="Guard",
        fireMode="Suppress",
        formation="wide",
        followDistance=5.0,
        markerLabel="ATTACK"
    },
    target = {
        label="Radio marker: mark target",
        signalLabel="radio marker",
        keywords={"radio", "walkie", "receiver", "transmitter", "ham"},
        orderName="Patrol",
        fireMode="Suppress",
        formation="wide",
        followDistance=5.0,
        markerLabel="TARGET"
    },
    post = {
        label="Flag: temporary post here",
        signalLabel="field flag",
        keywords={"flag", "banner", "sheet", "ripped sheets", "sheetrope", "sheet rope"},
        orderName="Guard",
        fireMode="Defensive",
        formation="wide",
        followDistance=4.0,
        markerLabel="POST"
    }
}

local function bs_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        local ok, value = pcall(function() return NPCLegacySettingsBridge.GetBool(name, defaultValue == true) end)
        if ok and value ~= nil then return value == true end
    end
    return defaultValue == true
end

local function bs_num(name, defaultValue, minValue, maxValue)
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

local function bs_now()
    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then
            local ok, value = pcall(function() return gt:getWorldAgeHours() end)
            if ok and value then return tonumber(value) or 0 end
        end
    end
    return os.time and (os.time() / 3600) or 0
end

local function bs_playerId(player)
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

local function bs_itemText(item)
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

local function bs_itemMatches(item, action)
    local cfg = NPCSignalsBridge.Actions[action]
    if not cfg then return false end
    local text = bs_itemText(item)
    if text == "" then return false end
    for _, keyword in ipairs(cfg.keywords or {}) do
        if text:find(tostring(keyword):lower(), 1, true) then return true end
    end
    return false
end

local function bs_inventoryItems(player)
    if not (player and player.getInventory) then return nil end
    local okInv, inv = pcall(function() return player:getInventory() end)
    if not okInv or not inv then return nil end
    if inv.getItems then
        local okItems, items = pcall(function() return inv:getItems() end)
        if okItems and items and items.size and items.get then return inv, items end
    end
    return inv, nil
end

function NPCSignalsBridge.IsEnabled()
    return bs_bool("Signal_Enabled", true)
end

function NPCSignalsBridge.RequireItems()
    return bs_bool("Signal_RequireItems", false)
end

function NPCSignalsBridge.ConsumeItems()
    return bs_bool("Signal_ConsumeItems", false)
end

function NPCSignalsBridge.CooldownHours()
    return bs_num("Signal_CooldownMinutes", 4, 0, 1440) / 60
end

function NPCSignalsBridge.MarkerHours()
    return bs_num("Signal_MarkerHours", 3, 0.1, 168)
end

function NPCSignalsBridge.MaxActiveMarkers()
    return math.floor(bs_num("Signal_MaxActiveMarkers", 32, 0, 200))
end

function NPCSignalsBridge.NowHours()
    return bs_now()
end

function NPCSignalsBridge.PlayerId(player)
    return bs_playerId(player)
end

function NPCSignalsBridge.Action(action)
    return NPCSignalsBridge.Actions[tostring(action or "")]
end

function NPCSignalsBridge.EnsureData(gmd)
    if not gmd then return nil end
    gmd.NPCSignalsBridge = gmd.NPCSignalsBridge or {}
    gmd.NPCSignalsBridge.playerCooldowns = gmd.NPCSignalsBridge.playerCooldowns or {}
    gmd.NPCSignalsBridge.history = gmd.NPCSignalsBridge.history or {}
    gmd.NPCSignalsBridge.activeMarkers = gmd.NPCSignalsBridge.activeMarkers or {}
    gmd.NPCSignalsBridge.stats = gmd.NPCSignalsBridge.stats or {used=0, rally=0, smoke=0, attack=0, target=0, post=0, denied=0}
    gmd.NPCSignalsBridge.nextId = tonumber(gmd.NPCSignalsBridge.nextId) or 1
    gmd.DebugMapMarkers = gmd.DebugMapMarkers or {}
    return gmd.NPCSignalsBridge
end

function NPCSignalsBridge.HasSignalItem(player, action)
    if not NPCSignalsBridge.RequireItems() then return true end
    local _, items = bs_inventoryItems(player)
    if not items then return false end
    for i=0, items:size() - 1 do
        local okItem, item = pcall(function() return items:get(i) end)
        if okItem and bs_itemMatches(item, action) then return true end
    end
    return false
end

function NPCSignalsBridge.TakeSignalItem(player, action)
    if not NPCSignalsBridge.RequireItems() then return true end
    if not NPCSignalsBridge.ConsumeItems() then return true end
    local inv, items = bs_inventoryItems(player)
    if not (inv and items) then return false end
    for i=0, items:size() - 1 do
        local okItem, item = pcall(function() return items:get(i) end)
        if okItem and bs_itemMatches(item, action) then
            local okRemove = false
            if inv.Remove then okRemove = pcall(function() inv:Remove(item) end) end
            if okRemove then return true end
            if item and item.getContainer then
                local okCont, cont = pcall(function() return item:getContainer() end)
                if okCont and cont and cont.Remove then
                    okRemove = pcall(function() cont:Remove(item) end)
                    if okRemove then return true end
                end
            end
            return false
        end
    end
    return false
end

function NPCSignalsBridge.CanUse(gmd, player, action)
    if not NPCSignalsBridge.IsEnabled() then return false, "disabled" end
    if not NPCSignalsBridge.Action(action) then return false, "unknown" end
    if not NPCSignalsBridge.HasSignalItem(player, action) then return false, "missing_item" end
    local data = NPCSignalsBridge.EnsureData(gmd)
    if not data then return false, "no_data" end
    local pid = tostring(bs_playerId(player) or "0")
    local nextAt = tonumber(data.playerCooldowns[pid]) or 0
    local now = bs_now()
    if nextAt > now then return false, "cooldown", nextAt - now end
    return true, "ok"
end

function NPCSignalsBridge.SetCooldown(gmd, player)
    local data = NPCSignalsBridge.EnsureData(gmd)
    if not data then return end
    local pid = tostring(bs_playerId(player) or "0")
    data.playerCooldowns[pid] = bs_now() + NPCSignalsBridge.CooldownHours()
end

function NPCSignalsBridge.MakeMarker(gmd, action, player, x, y, z, extra)
    local data = NPCSignalsBridge.EnsureData(gmd)
    local cfg = NPCSignalsBridge.Action(action)
    if not (data and cfg and x and y) then return nil end
    local id = "signal_" .. tostring(data.nextId or 1)
    data.nextId = (tonumber(data.nextId) or 1) + 1
    local now = bs_now()
    local marker = {
        id=id,
        markerType="signal",
        x=tonumber(x),
        y=tonumber(y),
        z=tonumber(z) or 0,
        name=cfg.markerLabel or cfg.label or "SIGNAL",
        signalId=id,
        signalAction=action,
        signalLabel=cfg.markerLabel or cfg.signalLabel or action,
        signalOwnerId=bs_playerId(player),
        signalExpiresAt=now + NPCSignalsBridge.MarkerHours(),
        createdAt=now,
        updatedAt=now,
        friendly=true,
        hostile=false,
        side="blue",
        factionSide="blue",
        state=action
    }
    if type(extra) == "table" then
        for k, v in pairs(extra) do marker[k] = v end
    end
    data.activeMarkers[id] = marker
    gmd.DebugMapMarkers[id] = marker
    return marker
end

function NPCSignalsBridge.Cleanup(gmd)
    local data = NPCSignalsBridge.EnsureData(gmd)
    if not data then return 0 end
    local now = bs_now()
    local removed = 0
    for id, marker in pairs(data.activeMarkers or {}) do
        if marker and tonumber(marker.signalExpiresAt) and tonumber(marker.signalExpiresAt) <= now then
            data.activeMarkers[id] = nil
            if gmd.DebugMapMarkers then gmd.DebugMapMarkers[id] = nil end
            removed = removed + 1
        end
    end
    local maxActive = NPCSignalsBridge.MaxActiveMarkers()
    if maxActive > 0 then
        local count = 0
        for _, _ in pairs(data.activeMarkers or {}) do count = count + 1 end
        if count > maxActive then
            for id, _ in pairs(data.activeMarkers or {}) do
                data.activeMarkers[id] = nil
                if gmd.DebugMapMarkers then gmd.DebugMapMarkers[id] = nil end
                removed = removed + 1
                count = count - 1
                if count <= maxActive then break end
            end
        end
    end
    return removed
end

function NPCSignalsBridge.AddHistory(gmd, player, action, text)
    local data = NPCSignalsBridge.EnsureData(gmd)
    if not data then return end
    local pid = tostring(bs_playerId(player) or "0")
    data.history[pid] = data.history[pid] or {}
    table.insert(data.history[pid], 1, {t=bs_now(), action=action, text=tostring(text or action)})
    while #data.history[pid] > 8 do table.remove(data.history[pid]) end
end

function NPCSignalsBridge.HistoryText(gmd, player)
    local data = NPCSignalsBridge.EnsureData(gmd)
    local pid = tostring(bs_playerId(player) or "0")
    local hist = data and data.history and data.history[pid]
    if not hist or #hist == 0 then return "No field signals used yet." end
    local out = {}
    for i=1, math.min(#hist, 5) do
        out[#out + 1] = tostring(hist[i].text or hist[i].action or "signal")
    end
    return table.concat(out, " | ")
end
