-- NPCRuntimeCacheBridge.lua
-- Small runtime-only caches and bit helpers for hot legacy NPC runtime paths.
-- Runtime data is intentionally not written into ModData.

require "NPCCore/NPCLegacyContractBridge"

NPCRuntimeCacheBridge = NPCRuntimeCacheBridge or {}

NPCRuntimeCacheBridge.Settings = NPCRuntimeCacheBridge.Settings or {}
NPCRuntimeCacheBridge.ItemClass = NPCRuntimeCacheBridge.ItemClass or {}
NPCRuntimeCacheBridge.WeaponMeta = NPCRuntimeCacheBridge.WeaponMeta or {}
NPCRuntimeCacheBridge.PlayerFaction = NPCRuntimeCacheBridge.PlayerFaction or {}
NPCRuntimeCacheBridge.RoadPoint = NPCRuntimeCacheBridge.RoadPoint or {}
NPCRuntimeCacheBridge.TablePool = NPCRuntimeCacheBridge.TablePool or {}

NPCRuntimeCacheBridge.SettingsCacheSeconds = NPCRuntimeCacheBridge.SettingsCacheSeconds or 5
NPCRuntimeCacheBridge.TablePoolMax = NPCRuntimeCacheBridge.TablePoolMax or 64

local function brc_nowSeconds()
    if getTimestamp then
        local ok, value = pcall(function() return getTimestamp() end)
        if ok and value then return tonumber(value) or os.time() end
    end
    return os.time()
end

local function brc_nowHours()
    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then
            local ok, value = pcall(function() return gt:getWorldAgeHours() end)
            if ok and value then return tonumber(value) or 0 end
        end
    end
    return brc_nowSeconds() / 3600
end

local function brc_vars()
    local sandboxKey = NPCLegacyContractBridge.Sandbox.ext
    if SandboxVars and SandboxVars[sandboxKey] then
        return SandboxVars[sandboxKey]
    end
    return nil
end

local function brc_clamp(value, minValue, maxValue)
    if minValue ~= nil and value < minValue then return minValue end
    if maxValue ~= nil and value > maxValue then return maxValue end
    return value
end

function NPCRuntimeCacheBridge.SetSettingsCacheSeconds(seconds)
    seconds = tonumber(seconds) or NPCRuntimeCacheBridge.SettingsCacheSeconds or 5
    if seconds < 0 then seconds = 0 end
    NPCRuntimeCacheBridge.SettingsCacheSeconds = seconds
end

function NPCRuntimeCacheBridge.SetTablePoolMax(value)
    value = tonumber(value) or NPCRuntimeCacheBridge.TablePoolMax or 64
    if value < 0 then value = 0 end
    NPCRuntimeCacheBridge.TablePoolMax = math.floor(value + 0.5)
end

function NPCRuntimeCacheBridge.ClearSettings()
    NPCRuntimeCacheBridge.Settings = {}
end

function NPCRuntimeCacheBridge.GetSetting(name, defaultValue, defaults)
    name = tostring(name or "")
    if name == "" then return defaultValue end

    local ttl = tonumber(NPCRuntimeCacheBridge.SettingsCacheSeconds) or 0
    local now = brc_nowSeconds()
    local cached = NPCRuntimeCacheBridge.Settings[name]
    if ttl > 0 and cached and cached.expiresAt and cached.expiresAt >= now then
        return cached.value
    end

    local value = nil
    local vars = brc_vars()
    if vars and vars[name] ~= nil then
        value = vars[name]
    elseif type(defaults) == "table" and defaults[name] ~= nil then
        value = defaults[name]
    else
        value = defaultValue
    end

    if ttl > 0 then
        NPCRuntimeCacheBridge.Settings[name] = {value=value, expiresAt=now + ttl}
    end
    return value
end

function NPCRuntimeCacheBridge.GetNumber(name, defaultValue, minValue, maxValue, defaults)
    local value = tonumber(NPCRuntimeCacheBridge.GetSetting(name, defaultValue, defaults))
    if value == nil then value = tonumber(defaultValue) or 0 end
    return brc_clamp(value, minValue, maxValue)
end

function NPCRuntimeCacheBridge.GetBool(name, defaultValue, defaults)
    local value = NPCRuntimeCacheBridge.GetSetting(name, defaultValue, defaults)
    if value == nil then return defaultValue == true end
    if value == true or value == 1 or value == "true" then return true end
    if value == false or value == 0 or value == "false" then return false end
    return defaultValue == true
end

function NPCRuntimeCacheBridge.MaskHas(mask, flag)
    mask = tonumber(mask) or 0
    flag = tonumber(flag) or 0
    if flag <= 0 then return false end
    if bit32 and bit32.band then return bit32.band(mask, flag) ~= 0 end
    if bit and bit.band then return bit.band(mask, flag) ~= 0 end
    local div = math.floor(mask / flag)
    return (div % 2) >= 1
end

function NPCRuntimeCacheBridge.MaskAdd(mask, flag)
    mask = tonumber(mask) or 0
    flag = tonumber(flag) or 0
    if flag <= 0 then return mask end
    if NPCRuntimeCacheBridge.MaskHas(mask, flag) then return mask end
    return mask + flag
end

function NPCRuntimeCacheBridge.MaskRemove(mask, flag)
    mask = tonumber(mask) or 0
    flag = tonumber(flag) or 0
    if flag <= 0 then return mask end
    if not NPCRuntimeCacheBridge.MaskHas(mask, flag) then return mask end
    return mask - flag
end

local function brc_playerId(player)
    if not player then return nil end
    if NPCUtils and NPCUtils.GetCharacterID then
        local ok, id = pcall(function() return NPCUtils.GetCharacterID(player) end)
        if ok and id ~= nil then return tostring(id) end
    end
    if player.getOnlineID then
        local ok, id = pcall(function() return player:getOnlineID() end)
        if ok and id ~= nil then return tostring(id) end
    end
    if player.getUsername then
        local ok, id = pcall(function() return player:getUsername() end)
        if ok and id ~= nil then return tostring(id) end
    end
    return nil
end

function NPCRuntimeCacheBridge.GetPlayerFactionRecord(player)
    local id = brc_playerId(player)
    if not id then return nil end
    local rec = NPCRuntimeCacheBridge.PlayerFaction[id]
    if not rec then return nil end
    local nowHours = brc_nowHours()
    if rec.expiresAt and nowHours >= tonumber(rec.expiresAt) then
        NPCRuntimeCacheBridge.PlayerFaction[id] = nil
        return nil
    end
    local ttl = tonumber(rec.cacheExpiresAt) or 0
    if ttl > 0 and ttl < brc_nowSeconds() then
        NPCRuntimeCacheBridge.PlayerFaction[id] = nil
        return nil
    end
    return rec
end

function NPCRuntimeCacheBridge.SetPlayerFactionRecord(player, rec)
    local id = brc_playerId(player)
    if not id or type(rec) ~= "table" then return end
    local copy = {
        side = rec.side,
        expiresAt = rec.expiresAt,
        reason = rec.reason,
        updatedAt = rec.updatedAt,
        cacheExpiresAt = brc_nowSeconds() + 1
    }
    NPCRuntimeCacheBridge.PlayerFaction[id] = copy
end

function NPCRuntimeCacheBridge.ClearPlayerFaction(player)
    local id = brc_playerId(player)
    if id then NPCRuntimeCacheBridge.PlayerFaction[id] = nil end
end

function NPCRuntimeCacheBridge.GetItemClass(key)
    if not key then return nil end
    return NPCRuntimeCacheBridge.ItemClass[tostring(key)]
end

function NPCRuntimeCacheBridge.SetItemClass(key, value)
    if not key or value == nil then return value end
    NPCRuntimeCacheBridge.ItemClass[tostring(key)] = value
    return value
end

function NPCRuntimeCacheBridge.GetWeaponMeta(key)
    if not key then return nil end
    return NPCRuntimeCacheBridge.WeaponMeta[tostring(key)]
end

function NPCRuntimeCacheBridge.SetWeaponMeta(key, value)
    if not key or type(value) ~= "table" then return value end
    NPCRuntimeCacheBridge.WeaponMeta[tostring(key)] = value
    return value
end

function NPCRuntimeCacheBridge.GetRoadPoint(key)
    if not key then return nil end
    return NPCRuntimeCacheBridge.RoadPoint[tostring(key)]
end

function NPCRuntimeCacheBridge.SetRoadPoint(key, value)
    if not key or type(value) ~= "table" then return value end
    NPCRuntimeCacheBridge.RoadPoint[tostring(key)] = value
    return value
end

function NPCRuntimeCacheBridge.AcquireTable()
    local pool = NPCRuntimeCacheBridge.TablePool
    local n = #pool
    if n > 0 then
        local tbl = pool[n]
        pool[n] = nil
        return tbl
    end
    return {}
end

function NPCRuntimeCacheBridge.ReleaseTable(tbl)
    if type(tbl) ~= "table" then return end
    for k, _ in pairs(tbl) do tbl[k] = nil end
    local maxPool = tonumber(NPCRuntimeCacheBridge.TablePoolMax) or 0
    if maxPool > 0 and #NPCRuntimeCacheBridge.TablePool < maxPool then
        table.insert(NPCRuntimeCacheBridge.TablePool, tbl)
    end
end

function NPCRuntimeCacheBridge.ApplySettings()
    local defaults = NPCLegacySettingsBridge and NPCLegacySettingsBridge.Defaults or nil
    NPCRuntimeCacheBridge.SetSettingsCacheSeconds(NPCRuntimeCacheBridge.GetNumber("Runtime_SettingsCacheSeconds", NPCRuntimeCacheBridge.SettingsCacheSeconds or 5, 0, 120, defaults))
    NPCRuntimeCacheBridge.SetTablePoolMax(NPCRuntimeCacheBridge.GetNumber("Runtime_TablePoolMax", NPCRuntimeCacheBridge.TablePoolMax or 64, 0, 512, defaults))
end

NPCRuntimeCacheBridge.ApplySettings()
