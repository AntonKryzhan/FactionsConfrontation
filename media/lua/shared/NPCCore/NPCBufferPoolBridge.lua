-- NPCBufferPoolBridge.lua
-- Runtime-only pooled scratch buffers for non-persistent hot paths.
--
-- This bridge does not change save data, network payloads or marker formats.
-- It only reuses temporary Lua tables to reduce GC churn during background
-- influence/cache maintenance.

NPCBufferPoolBridge = NPCBufferPoolBridge or {}

NPCBufferPoolBridge.VERSION = "2026-06-02-stage360-fps-tuned-buffer-pool-1"
NPCBufferPoolBridge.Config = NPCBufferPoolBridge.Config or {
    enabled = true,
    maxBuffers = 48,
    maxEntriesToClear = 2048,
    debug = false
}
NPCBufferPoolBridge.Pools = NPCBufferPoolBridge.Pools or {}
NPCBufferPoolBridge.Stats = NPCBufferPoolBridge.Stats or {
    acquired = 0,
    reused = 0,
    released = 0,
    dropped = 0
}

local function bpool_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        return NPCLegacySettingsBridge.GetBool(name, defaultValue == true)
    end
    return defaultValue == true
end

local function bpool_number(name, defaultValue, minValue, maxValue)
    local value = defaultValue
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        value = NPCLegacySettingsBridge.GetNumber(name, defaultValue, minValue, maxValue)
    end
    value = tonumber(value) or tonumber(defaultValue) or 0
    if minValue ~= nil and value < minValue then value = minValue end
    if maxValue ~= nil and value > maxValue then value = maxValue end
    return value
end

function NPCBufferPoolBridge.ApplySettings()
    local c = NPCBufferPoolBridge.Config
    c.enabled = bpool_bool("BufferPool_Enabled", c.enabled ~= false)
    c.maxBuffers = bpool_number("BufferPool_MaxBuffers", c.maxBuffers or 48, 0, 2048)
    c.maxEntriesToClear = bpool_number("BufferPool_MaxEntriesToClear", c.maxEntriesToClear or 2048, 64, 20000)
    c.debug = bpool_bool("BufferPool_Debug", c.debug == true)
end

local function bpool_clearArray(t, count)
    if type(t) ~= "table" then return t end
    local n = tonumber(count or t.n or #t) or 0
    local maxClear = tonumber(NPCBufferPoolBridge.Config.maxEntriesToClear) or 4096
    if n > maxClear then n = maxClear end
    for i = 1, n do
        t[i] = nil
    end
    t.n = 0
    return t
end

function NPCBufferPoolBridge.ClearArray(t, count)
    return bpool_clearArray(t, count)
end

function NPCBufferPoolBridge.ClearMap(t)
    if type(t) ~= "table" then return t end
    for k, _ in pairs(t) do
        t[k] = nil
    end
    return t
end

function NPCBufferPoolBridge.Acquire(name)
    if not (NPCBufferPoolBridge.Config and NPCBufferPoolBridge.Config.enabled ~= false) then
        return {n = 0}
    end
    name = tostring(name or "default")
    local pool = NPCBufferPoolBridge.Pools[name]
    if not pool then
        pool = {}
        NPCBufferPoolBridge.Pools[name] = pool
    end
    local t = pool[#pool]
    if t then
        pool[#pool] = nil
        NPCBufferPoolBridge.Stats.reused = (NPCBufferPoolBridge.Stats.reused or 0) + 1
    else
        t = {n = 0}
    end
    t.n = 0
    t._poolName = name
    NPCBufferPoolBridge.Stats.acquired = (NPCBufferPoolBridge.Stats.acquired or 0) + 1
    return t
end

function NPCBufferPoolBridge.Release(name, t, count)
    if type(t) ~= "table" then return false end
    if not (NPCBufferPoolBridge.Config and NPCBufferPoolBridge.Config.enabled ~= false) then return false end

    local n = tonumber(count or t.n or #t) or 0
    local maxClear = tonumber(NPCBufferPoolBridge.Config.maxEntriesToClear) or 2048
    if n > maxClear then
        -- Large scratch buffers are cheaper to drop than to clear synchronously.
        -- They are not returned to the pool, so retained references can be collected
        -- naturally without adding a long release-time loop to the current frame.
        NPCBufferPoolBridge.Stats.dropped = (NPCBufferPoolBridge.Stats.dropped or 0) + 1
        return false
    end

    name = tostring(name or t._poolName or "default")
    bpool_clearArray(t, n)
    t._poolName = name

    local pool = NPCBufferPoolBridge.Pools[name]
    if not pool then
        pool = {}
        NPCBufferPoolBridge.Pools[name] = pool
    end

    local maxBuffers = tonumber(NPCBufferPoolBridge.Config.maxBuffers) or 48
    if maxBuffers <= 0 or #pool >= maxBuffers then
        NPCBufferPoolBridge.Stats.dropped = (NPCBufferPoolBridge.Stats.dropped or 0) + 1
        return false
    end

    pool[#pool + 1] = t
    NPCBufferPoolBridge.Stats.released = (NPCBufferPoolBridge.Stats.released or 0) + 1
    return true
end

function NPCBufferPoolBridge.GetStats()
    return NPCBufferPoolBridge.Stats
end

NPCBufferPoolBridge.ApplySettings()
