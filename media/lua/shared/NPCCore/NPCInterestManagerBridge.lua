-- NPCInterestManagerBridge.lua
-- Neutral shared backend for interest manager.

NPCInterestManagerBridge = NPCInterestManagerBridge or {}

NPCInterestManagerBridge.VERSION = "2026-06-10-stage454-interest-aabb-radius2-1"
NPCInterestManagerBridge.Config = NPCInterestManagerBridge.Config or {
    enabled = true,
    worldRadius = 700,
    minimapRadius = 180,
    syncRadius = 900,
    adminRadius = 2200,
    tileBucketSize = 50,
    alwaysSendCombat = true,
    alwaysSendHired = true,
    alwaysSendBases = true,
    alwaysSendSpies = true,
    importantRadiusMultiplier = 1.75,
    debugLog = false
}

local function nset(k, d, mi, ma)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        return NPCLegacySettingsBridge.GetNumber(k, d, mi, ma)
    end
    return tonumber(d) or 0
end

local function bset(k, d)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        return NPCLegacySettingsBridge.GetBool(k, d == true)
    end
    return d == true
end

function NPCInterestManagerBridge.ApplySettings()
    local c = NPCInterestManagerBridge.Config
    c.enabled = bset("Interest_Enabled", c.enabled ~= false)
    c.worldRadius = nset("Interest_WorldMapRadius", c.worldRadius, 0, 5000)
    c.minimapRadius = nset("Interest_MinimapRadius", c.minimapRadius, 0, 2000)
    c.syncRadius = nset("Interest_SyncRadius", c.syncRadius, 0, 6000)
    c.adminRadius = nset("Interest_AdminRadius", c.adminRadius, 0, 10000)
    c.tileBucketSize = nset("Interest_TileBucketSize", c.tileBucketSize, 10, 500)
    c.alwaysSendCombat = bset("Interest_AlwaysSendCombat", c.alwaysSendCombat ~= false)
    c.alwaysSendHired = bset("Interest_AlwaysSendHired", c.alwaysSendHired ~= false)
    c.alwaysSendBases = bset("Interest_AlwaysSendBases", c.alwaysSendBases ~= false)
    c.alwaysSendSpies = bset("Interest_AlwaysSendSpies", c.alwaysSendSpies ~= false)
    c.importantRadiusMultiplier = nset("Interest_ImportantRadiusMultiplier", c.importantRadiusMultiplier or 1.75, 1.0, 8.0)
    c.debugLog = bset("Interest_DebugLog", c.debugLog == true)
end

local function d2(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return dx * dx + dy * dy
end

function NPCInterestManagerBridge.IsCombatMarker(m)
    return m and (m.dead or m.inBattle or m.virtualBattle or m.battleId or m.captureActive or m.contested or m.captureStatus == "capturing" or m.captureStatus == "decapturing") == true
end

function NPCInterestManagerBridge.IsSpyMarker(m)
    return m and (m.spy == true or m.spyDefected == true or ((tonumber(m.spyCount) or 0) > 0)) == true
end

function NPCInterestManagerBridge.IsHiredMarker(m)
    return m and (m.mercenaryHired == true or m.hired == true or m.isPlayerGuard == true) == true
end

function NPCInterestManagerBridge.IsBaseMarker(m)
    return m and (m.markerType == "base" or m.markerType == "economy_mission") == true
end

function NPCInterestManagerBridge.IsImportantMarker(m)
    return NPCInterestManagerBridge.IsCombatMarker(m)
        or NPCInterestManagerBridge.IsSpyMarker(m)
        or NPCInterestManagerBridge.IsHiredMarker(m)
        or NPCInterestManagerBridge.IsBaseMarker(m)
end

function NPCInterestManagerBridge.IsAlwaysRelevant(m)
    local c = NPCInterestManagerBridge.Config
    if not m then return false end
    if c.alwaysSendCombat and NPCInterestManagerBridge.IsCombatMarker(m) then return true end
    if c.alwaysSendHired and NPCInterestManagerBridge.IsHiredMarker(m) then return true end
    if c.alwaysSendBases and NPCInterestManagerBridge.IsBaseMarker(m) then return true end
    if c.alwaysSendSpies and NPCInterestManagerBridge.IsSpyMarker(m) then return true end
    return false
end

function NPCInterestManagerBridge.GetRadius(mode, marker)
    local c = NPCInterestManagerBridge.Config
    local r
    if mode == "minimap" then
        r = c.minimapRadius
    elseif mode == "sync" then
        r = c.syncRadius
    elseif mode == "admin" then
        r = c.adminRadius
    else
        r = c.worldRadius
    end

    if marker and NPCInterestManagerBridge.IsImportantMarker(marker) then
        r = r * (tonumber(c.importantRadiusMultiplier) or 1.0)
    end
    return r
end

local function playerOk(m, p, r)
    if not p or not p.getX then return false end
    if r <= 0 then return true end
    local px = tonumber(p:getX()) or 0
    local py = tonumber(p:getY()) or 0
    local dx = (tonumber(m.x) or 0) - px
    if dx > r or dx < -r then return false end
    local dy = (tonumber(m.y) or 0) - py
    if dy > r or dy < -r then return false end
    return dx * dx + dy * dy <= r * r
end

local function anyPlayer(fn)
    if getOnlinePlayers then
        local ok, ps = pcall(function() return getOnlinePlayers() end)
        if ok and ps then
            for i = 0, ps:size() - 1 do
                if fn(ps:get(i)) then return true end
            end
            return false
        end
    end
    if getNumActivePlayers and getSpecificPlayer then
        for i = 0, getNumActivePlayers() - 1 do
            if fn(getSpecificPlayer(i)) then return true end
        end
        return false
    end
    if getSpecificPlayer then return fn(getSpecificPlayer(0)) end
    return true
end

function NPCInterestManagerBridge.ShouldSendMarker(m, player, mode)
    if not NPCInterestManagerBridge.Config.enabled then return true end
    if type(m) ~= "table" or not m.x or not m.y then return false end
    if mode == "sync" then return true end
    if NPCInterestManagerBridge.IsAlwaysRelevant(m) then return true end

    local r = NPCInterestManagerBridge.GetRadius(mode or "world", m)
    if player then return playerOk(m, player, r) end
    return anyPlayer(function(p) return playerOk(m, p, r) end)
end

NPCInterestManagerBridge.ApplySettings()
