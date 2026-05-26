require "NPCCore/NPCLegacySettingsBridge"

NPCRenderReliefBridge = NPCRenderReliefBridge or {}

NPCRenderReliefBridge.VERSION = "2026-05-10-v9.2-zoom-wheel-hotfix"
NPCRenderReliefBridge.State = NPCRenderReliefBridge.State or {
    tick = -99999,
    fps = 60,
    zoom = 1,
    level = 0,
    name = "LOW",
    zoomCapApplied = false,
    zoomCapRestoreAttempted = false,
    originalZoomLevels1x = nil,
    originalZoomLevels2x = nil,
    lastReliefMs = 0,
    lastLogMs = 0
}

NPCRenderReliefBridge.Config = NPCRenderReliefBridge.Config or {
    enabled = true,
    sampleTicks = 15,
    highZoom = 1.55,
    criticalZoom = 1.95,
    panicZoom = 2.35,
    lowFPS = 58,
    criticalFPS = 50,
    panicFPS = 42,
    shadowOffLevel = 1,
    torchOffLevel = 2,
    zoomCapEnabled = false,
    zoomCapLevel = 2,
    zoomCapLevels1x = "50;75;100;125;150;175",
    zoomCapLevels2x = "50;75;100;125;150;175",
    zoomCapRestoreLevels1x = "50;75;100;125;150;175;200;250",
    zoomCapRestoreLevels2x = "50;75;100;125;150;175;200;250",
    zoomCapRestoreMs = 12000,
    debug = false,
    debugIntervalMs = 15000
}

local function brr_nowMs()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then
        local ok, hours = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok and hours then return math.floor((tonumber(hours) or 0) * 3600000) end
    end
    return 0
end

local function brr_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        local ok, value = pcall(function() return NPCLegacySettingsBridge.GetBool(name, defaultValue == true) end)
        if ok then return value == true end
    end
    return defaultValue == true
end

local function brr_number(name, defaultValue, minValue, maxValue)
    local value = tonumber(defaultValue) or 0
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        local ok, got = pcall(function() return NPCLegacySettingsBridge.GetNumber(name, value, minValue, maxValue) end)
        if ok and got ~= nil then value = tonumber(got) or value end
    end
    if minValue ~= nil and value < minValue then value = minValue end
    if maxValue ~= nil and value > maxValue then value = maxValue end
    return value
end

local function brr_applySettings()
    local cfg = NPCRenderReliefBridge.Config
    cfg.enabled = brr_bool("RenderRelief_Enabled", cfg.enabled ~= false)
    cfg.sampleTicks = brr_number("RenderRelief_SampleTicks", cfg.sampleTicks or 15, 1, 600)
    cfg.highZoom = brr_number("RenderRelief_HighZoom", cfg.highZoom or 1.55, 1.0, 4.0)
    cfg.criticalZoom = brr_number("RenderRelief_CriticalZoom", cfg.criticalZoom or 1.95, 1.0, 4.0)
    cfg.panicZoom = brr_number("RenderRelief_PanicZoom", cfg.panicZoom or 2.35, 1.0, 4.0)
    cfg.lowFPS = brr_number("RenderRelief_LowFPS", cfg.lowFPS or 58, 5, 240)
    cfg.criticalFPS = brr_number("RenderRelief_CriticalFPS", cfg.criticalFPS or 50, 5, 240)
    cfg.panicFPS = brr_number("RenderRelief_PanicFPS", cfg.panicFPS or 42, 5, 240)
    cfg.shadowOffLevel = brr_number("RenderRelief_ShadowOffLevel", cfg.shadowOffLevel or 1, 0, 3)
    cfg.torchOffLevel = brr_number("RenderRelief_TorchOffLevel", cfg.torchOffLevel or 2, 0, 3)
    -- v9.2: hard-disable runtime zoom-level rewriting. Rewriting Core zoom option strings while
    -- the player scrolls the mouse wheel makes Build 41 snap to a middle zoom level.
    cfg.zoomCapEnabled = false
    cfg.zoomCapLevel = brr_number("RenderRelief_ZoomCapLevel", cfg.zoomCapLevel or 2, 0, 3)
    cfg.zoomCapRestoreMs = brr_number("RenderRelief_ZoomCapRestoreMs", cfg.zoomCapRestoreMs or 12000, 1000, 120000)
    cfg.debug = brr_bool("RenderRelief_Debug", cfg.debug == true)
    cfg.debugIntervalMs = brr_number("RenderRelief_DebugIntervalMs", cfg.debugIntervalMs or 15000, 1000, 120000)
end

local function brr_tick()
    if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.GetTick then
        local ok, tick = pcall(function() return NPCWorkSchedulerBridge.GetTick() end)
        if ok and tick then return tonumber(tick) or 0 end
    end
    return 0
end

local function brr_averageFPS()
    if getAverageFPS then
        local ok, fps = pcall(function() return getAverageFPS() end)
        if ok and fps then return tonumber(fps) or 60 end
    end
    return 60
end

local function brr_zoom()
    if getCore and getCore() and getCore().getZoom then
        local ok, zoom = pcall(function() return getCore():getZoom(0) end)
        if ok and tonumber(zoom) then return tonumber(zoom) end
    end
    return 1
end

local function brr_readZoomLevels(core, getterName)
    if not core or not getterName or not core[getterName] then return nil end
    local ok, value = pcall(function() return core[getterName](core) end)
    if ok and value ~= nil then return tostring(value) end
    return nil
end

local function brr_restoreZoomCap(force)
    local state = NPCRenderReliefBridge.State
    local cfg = NPCRenderReliefBridge.Config
    local core = getCore and getCore() or nil
    if not core then return end
    if not core.setOptionZoomLevels1x or not core.setOptionZoomLevels2x then return end

    local now = brr_nowMs()
    if not force and state.zoomCapApplied and now - (state.lastReliefMs or 0) < (tonumber(cfg.zoomCapRestoreMs) or 12000) then return end

    local current1x = brr_readZoomLevels(core, "getOptionZoomLevels1x")
    local current2x = brr_readZoomLevels(core, "getOptionZoomLevels2x")
    local capped1x = tostring(cfg.zoomCapLevels1x or "50;75;100;125;150;175")
    local capped2x = tostring(cfg.zoomCapLevels2x or "50;75;100;125;150;175")

    local restore1x = state.originalZoomLevels1x
    local restore2x = state.originalZoomLevels2x

    -- If the game was restarted after v9 applied the capped list, the original values are lost.
    -- Restore only when the current value still exactly matches our capped list; otherwise leave
    -- the player's custom zoom settings untouched.
    if not restore1x and current1x == capped1x then
        restore1x = tostring(cfg.zoomCapRestoreLevels1x or "50;75;100;125;150;175;200;250")
    end
    if not restore2x and current2x == capped2x then
        restore2x = tostring(cfg.zoomCapRestoreLevels2x or "50;75;100;125;150;175;200;250")
    end

    if not restore1x and not restore2x then
        state.zoomCapApplied = false
        return
    end

    local ok = pcall(function()
        if restore1x and current1x ~= restore1x then
            core:setOptionZoomLevels1x(restore1x)
        end
        if restore2x and current2x ~= restore2x then
            core:setOptionZoomLevels2x(restore2x)
        end
        if core.zoomLevelsChanged then core:zoomLevelsChanged() end
    end)
    if ok then
        state.zoomCapApplied = false
        state.originalZoomLevels1x = nil
        state.originalZoomLevels2x = nil
    end
end

local function brr_applyZoomCap(level)
    local state = NPCRenderReliefBridge.State

    -- v9.2: do not cap/rewrite zoom lists at runtime. Mouse wheel zoom in Build 41 expects
    -- the option zoom list to stay stable; changing it during play makes the zoom snap/reset.
    -- Run one guarded restore pass in case v9 left the capped list in options, then stay inert.
    if not state.zoomCapRestoreAttempted then
        state.zoomCapRestoreAttempted = true
        brr_restoreZoomCap(true)
    end
end

function NPCRenderReliefBridge.GetLoadState(force)
    brr_applySettings()
    local cfg = NPCRenderReliefBridge.Config
    local state = NPCRenderReliefBridge.State
    if cfg.enabled == false then
        state.level = 0
        state.name = "LOW"
        brr_restoreZoomCap(true)
        return state
    end

    local tick = brr_tick()
    local sampleTicks = tonumber(cfg.sampleTicks) or 15
    if not force and state.tick and tick - state.tick < sampleTicks then
        return state
    end

    local fps = brr_averageFPS()
    local zoom = brr_zoom()
    local level = 0

    if zoom >= (tonumber(cfg.highZoom) or 1.55) then level = math.max(level, 1) end
    if zoom >= (tonumber(cfg.criticalZoom) or 1.95) then level = math.max(level, 2) end
    if zoom >= (tonumber(cfg.panicZoom) or 2.35) then level = math.max(level, 3) end
    if fps > 0 and fps < (tonumber(cfg.lowFPS) or 58) then level = math.max(level, 1) end
    if fps > 0 and fps < (tonumber(cfg.criticalFPS) or 50) then level = math.max(level, 2) end
    if fps > 0 and fps < (tonumber(cfg.panicFPS) or 42) then level = math.max(level, 3) end

    state.tick = tick
    state.fps = fps
    state.zoom = zoom
    state.level = level
    state.name = level >= 3 and "PANIC" or (level >= 2 and "CRITICAL" or (level >= 1 and "HIGH" or "LOW"))
    if level > 0 then state.lastReliefMs = brr_nowMs() end

    brr_applyZoomCap(level)

    if cfg.debug then
        local now = brr_nowMs()
        if now - (state.lastLogMs or 0) >= (tonumber(cfg.debugIntervalMs) or 15000) then
            state.lastLogMs = now
            print("[NPCRenderRelief] level=" .. tostring(state.name) .. " fps=" .. tostring(math.floor((fps or 0) + 0.5)) .. " zoom=" .. tostring(math.floor((zoom or 1) * 100 + 0.5) / 100) .. " zoomCap=" .. tostring(state.zoomCapApplied == true))
        end
    end

    return state
end

function NPCRenderReliefBridge.GetLevel()
    local state = NPCRenderReliefBridge.GetLoadState(false)
    return tonumber(state.level) or 0, tonumber(state.zoom) or 1, tonumber(state.fps) or 60
end

function NPCRenderReliefBridge.ShouldSkipTorch(bandit)
    if NPCRenderReliefBridge.Config.enabled == false then return false end
    local level = NPCRenderReliefBridge.GetLevel()
    local threshold = tonumber(NPCRenderReliefBridge.Config.torchOffLevel) or 2
    return threshold > 0 and level >= threshold
end

function NPCRenderReliefBridge.ApplyCharacterRelief(bandit, brain, id)
    if not bandit then return end
    if NPCRenderReliefBridge.Config.enabled == false then return end

    -- Build 41 exposes IsoGameCharacter.doRenderShadow as a Java field, not as a safe Lua table field.
    -- Direct assignment from Kahlua logs "attempted index of non-table" every OnZombieUpdate pass.
    -- Keep render relief focused on safe paths here: zoom/FPS governor and torch-light throttling.
    local md = nil
    local okMd, retMd = pcall(function() return bandit:getModData() end)
    if okMd and type(retMd) == "table" then md = retMd end
    if md and md.BR_RenderReliefShadowOff then
        md.BR_RenderReliefShadowOff = nil
    end
end

function NPCRenderReliefBridge.OnTick()
    NPCRenderReliefBridge.GetLoadState(false)
end

brr_applySettings()

if Events and Events.OnTick and not NPCRenderReliefBridge._registered then
    NPCRenderReliefBridge._registered = true
    Events.OnTick.Add(NPCRenderReliefBridge.OnTick)
end
