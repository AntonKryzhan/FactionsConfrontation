require "NPCCore/NPCLegacySettingsBridge"

NPCRenderReliefBridge = NPCRenderReliefBridge or {}

NPCRenderReliefBridge.VERSION = "2026-05-30-stage302-xhigh-static-chunk-render-relief-1"
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
    sampleTicks = 3,
    highZoom = 1.20,
    criticalZoom = 1.45,
    panicZoom = 1.75,
    lowFPS = 66,
    criticalFPS = 61,
    panicFPS = 56,
    shadowOffLevel = 1,
    torchOffLevel = 1,
    labelOffLevel = 1,
    farNPCProxyLevel = 1,
    farNPCProxyDistance = 18,
    farNPCProxyInterval = 72,
    panicNPCProxyDistance = 12,
    panicNPCProxyInterval = 140,
    zoomCapEnabled = false,
    zoomCapLevel = 2,
    zoomCapLevels1x = "50;75;100;125;150;175",
    zoomCapLevels2x = "50;75;100;125;150;175",
    zoomCapRestoreLevels1x = "50;75;100;125;150;175;200;250",
    zoomCapRestoreLevels2x = "50;75;100;125;150;175;200;250",
    zoomCapRestoreMs = 12000,
    debug = false,
    debugIntervalMs = 15000,
    effectReliefLevel = 1,
    effectQueueSoftLimit = 96,
    effectQueueHardLimit = 160,
    farEffectDistance = 28,
    panicEffectDistance = 18,
    combatSoundReliefLevel = 2,
    combatSplatReliefLevel = 2,
    farCombatSoundDistance = 18,
    panicCombatSoundDistance = 12,
    farCombatSplatDistance = 16,
    panicCombatSplatDistance = 10
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
    cfg.sampleTicks = brr_number("RenderRelief_SampleTicks", cfg.sampleTicks or 3, 1, 600)
    cfg.highZoom = brr_number("RenderRelief_HighZoom", cfg.highZoom or 1.20, 1.0, 4.0)
    cfg.criticalZoom = brr_number("RenderRelief_CriticalZoom", cfg.criticalZoom or 1.45, 1.0, 4.0)
    cfg.panicZoom = brr_number("RenderRelief_PanicZoom", cfg.panicZoom or 1.75, 1.0, 4.0)
    cfg.lowFPS = brr_number("RenderRelief_LowFPS", cfg.lowFPS or 66, 5, 240)
    cfg.criticalFPS = brr_number("RenderRelief_CriticalFPS", cfg.criticalFPS or 61, 5, 240)
    cfg.panicFPS = brr_number("RenderRelief_PanicFPS", cfg.panicFPS or 56, 5, 240)
    cfg.shadowOffLevel = brr_number("RenderRelief_ShadowOffLevel", cfg.shadowOffLevel or 1, 0, 3)
    cfg.torchOffLevel = brr_number("RenderRelief_TorchOffLevel", cfg.torchOffLevel or 1, 0, 3)
    cfg.labelOffLevel = brr_number("RenderRelief_LabelOffLevel", cfg.labelOffLevel or 1, 0, 3)
    cfg.farNPCProxyLevel = brr_number("RenderRelief_FarNPCProxyLevel", cfg.farNPCProxyLevel or 1, 0, 3)
    cfg.farNPCProxyDistance = brr_number("RenderRelief_FarNPCProxyDistance", cfg.farNPCProxyDistance or 18, 4, 200)
    cfg.farNPCProxyInterval = brr_number("RenderRelief_FarNPCProxyInterval", cfg.farNPCProxyInterval or 72, 4, 600)
    cfg.panicNPCProxyDistance = brr_number("RenderRelief_PanicNPCProxyDistance", cfg.panicNPCProxyDistance or 12, 4, 200)
    cfg.panicNPCProxyInterval = brr_number("RenderRelief_PanicNPCProxyInterval", cfg.panicNPCProxyInterval or 140, 4, 900)
    -- v9.2: hard-disable runtime zoom-level rewriting. Rewriting Core zoom option strings while
    -- the player scrolls the mouse wheel makes Build 41 snap to a middle zoom level.
    cfg.zoomCapEnabled = false
    cfg.zoomCapLevel = brr_number("RenderRelief_ZoomCapLevel", cfg.zoomCapLevel or 2, 0, 3)
    cfg.zoomCapRestoreMs = brr_number("RenderRelief_ZoomCapRestoreMs", cfg.zoomCapRestoreMs or 12000, 1000, 120000)
    cfg.debug = brr_bool("RenderRelief_Debug", cfg.debug == true)
    cfg.debugIntervalMs = brr_number("RenderRelief_DebugIntervalMs", cfg.debugIntervalMs or 15000, 1000, 120000)
    cfg.effectReliefLevel = brr_number("RenderRelief_EffectReliefLevel", cfg.effectReliefLevel or 1, 0, 3)
    cfg.effectQueueSoftLimit = brr_number("RenderRelief_EffectQueueSoftLimit", cfg.effectQueueSoftLimit or 96, 8, 512)
    cfg.effectQueueHardLimit = brr_number("RenderRelief_EffectQueueHardLimit", cfg.effectQueueHardLimit or 160, 16, 768)
    cfg.farEffectDistance = brr_number("RenderRelief_FarEffectDistance", cfg.farEffectDistance or 28, 4, 200)
    cfg.panicEffectDistance = brr_number("RenderRelief_PanicEffectDistance", cfg.panicEffectDistance or 18, 4, 200)
    cfg.combatSoundReliefLevel = brr_number("RenderRelief_CombatSoundReliefLevel", cfg.combatSoundReliefLevel or 2, 0, 3)
    cfg.combatSplatReliefLevel = brr_number("RenderRelief_CombatSplatReliefLevel", cfg.combatSplatReliefLevel or 2, 0, 3)
    cfg.farCombatSoundDistance = brr_number("RenderRelief_FarCombatSoundDistance", cfg.farCombatSoundDistance or 18, 4, 120)
    cfg.panicCombatSoundDistance = brr_number("RenderRelief_PanicCombatSoundDistance", cfg.panicCombatSoundDistance or 12, 4, 120)
    cfg.farCombatSplatDistance = brr_number("RenderRelief_FarCombatSplatDistance", cfg.farCombatSplatDistance or 16, 4, 120)
    cfg.panicCombatSplatDistance = brr_number("RenderRelief_PanicCombatSplatDistance", cfg.panicCombatSplatDistance or 10, 4, 120)
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


local function brr_nearestPlayerDistance(x, y)
    x = tonumber(x); y = tonumber(y)
    if not x or not y then return 999999 end
    local best = 999999 * 999999
    if getNumActivePlayers and getSpecificPlayer then
        local count = getNumActivePlayers() or 1
        for i = 0, count - 1 do
            local p = getSpecificPlayer(i)
            if p and p.getX and p.getY then
                local dx = x - p:getX()
                local dy = y - p:getY()
                local d2 = dx * dx + dy * dy
                if d2 < best then best = d2 end
            end
        end
    elseif getPlayer then
        local p = getPlayer()
        if p and p.getX and p.getY then
            local dx = x - p:getX()
            local dy = y - p:getY()
            best = dx * dx + dy * dy
        end
    end
    return math.sqrt(best)
end

local function brr_isPlayerControlledBrain(brain)
    if type(brain) ~= "table" then return false end
    return brain.mercenaryHired == true
        or brain.hired == true
        or brain.isPlayerGuard == true
        or brain.playerOwned == true
        or brain.playerControlled == true
        or brain.master ~= nil
        or brain.follow == true
        or brain.followPlayer == true
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

    if zoom >= (tonumber(cfg.highZoom) or 1.20) then level = math.max(level, 1) end
    if zoom >= (tonumber(cfg.criticalZoom) or 1.45) then level = math.max(level, 2) end
    if zoom >= (tonumber(cfg.panicZoom) or 1.75) then level = math.max(level, 3) end
    if fps > 0 and fps < (tonumber(cfg.lowFPS) or 66) then level = math.max(level, 1) end
    if fps > 0 and fps < (tonumber(cfg.criticalFPS) or 61) then level = math.max(level, 2) end
    if fps > 0 and fps < (tonumber(cfg.panicFPS) or 56) then level = math.max(level, 3) end

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


function NPCRenderReliefBridge.ShouldSkipOverheadLabels()
    if NPCRenderReliefBridge.Config.enabled == false then return false end
    local level = NPCRenderReliefBridge.GetLevel()
    local threshold = tonumber(NPCRenderReliefBridge.Config.labelOffLevel) or 1
    return threshold > 0 and level >= threshold
end

local function brr_isProtectedCombatBrain(brain)
    if type(brain) ~= "table" then return false end
    if brr_isPlayerControlledBrain(brain) then return true end
    return brain.nonCombatant == true
        or brain.noCombat == true
        or brain.noAggro == true
        or brain.blackMarket == true
        or brain.blackMarketContact == true
        or brain.blackMarketId ~= nil
end

local function brr_combatReliefEligible(brain)
    if type(brain) ~= "table" then return false end
    if brr_isProtectedCombatBrain(brain) then return false end
    local ai = brain.ai
    local role = ai and tostring(ai.physicalBattleGovernorRole or "") or ""
    if role == "support" or role == "reserve" or role == "proxy" then return true end
    local level = tonumber(ai and ai.physicalBattleGovernorLevel) or 0
    if role == "frontline" and level >= 2 then return true end
    return brain.virtualBattle == true or brain.inBattle == true or brain.battleId ~= nil
end

local function brr_effectHash(x, y, z, salt, interval)
    interval = math.max(1, math.floor(tonumber(interval) or 1))
    local h = math.floor((tonumber(x) or 0) * 17 + (tonumber(y) or 0) * 31 + (tonumber(z) or 0) * 7 + (tonumber(salt) or 0) * 13)
    return math.abs(h) % interval
end

function NPCRenderReliefBridge.ShouldCullClientEffect(effect, queuedCount)
    if NPCRenderReliefBridge.Config.enabled == false then return false end
    if type(effect) ~= "table" then return false end

    local state = NPCRenderReliefBridge.GetLoadState(false)
    local level = tonumber(state.level) or 0
    local cfg = NPCRenderReliefBridge.Config
    local threshold = tonumber(cfg.effectReliefLevel) or 1
    if threshold <= 0 or level < threshold then return false end

    local queued = tonumber(queuedCount) or 0
    if queued >= (tonumber(cfg.effectQueueHardLimit) or 160) then return true end

    local x = tonumber(effect.x)
    local y = tonumber(effect.y)
    if not x or not y then return queued >= (tonumber(cfg.effectQueueSoftLimit) or 96) end

    local dist = brr_nearestPlayerDistance(x, y)
    local minDist = level >= 3 and (tonumber(cfg.panicEffectDistance) or 18) or (tonumber(cfg.farEffectDistance) or 28)
    if dist < minDist and queued < (tonumber(cfg.effectQueueSoftLimit) or 96) then return false end

    local interval = level >= 3 and 3 or (level >= 2 and 4 or 6)
    if queued >= (tonumber(cfg.effectQueueSoftLimit) or 96) then interval = math.max(2, interval - 2) end
    return brr_effectHash(x, y, effect.z, brr_tick(), interval) ~= 0
end

function NPCRenderReliefBridge.GetClientEffectProcessBudget(queueCount)
    if NPCRenderReliefBridge.Config.enabled == false then return 999999, 2 end
    local state = NPCRenderReliefBridge.GetLoadState(false)
    local level = tonumber(state.level) or 0
    local queued = tonumber(queueCount) or 0
    if level >= 3 then return queued >= 120 and 10 or 14, 4 end
    if level >= 2 then return queued >= 120 and 14 or 22, 3 end
    if level >= 1 then return queued >= 120 and 22 or 36, 2 end
    return 999999, 2
end

function NPCRenderReliefBridge.ShouldSkipCombatSound(character, brain, sound)
    if NPCRenderReliefBridge.Config.enabled == false then return false end
    if not brr_combatReliefEligible(brain) then return false end
    if not (character and character.getX and character.getY) then return false end

    local state = NPCRenderReliefBridge.GetLoadState(false)
    local level = tonumber(state.level) or 0
    local cfg = NPCRenderReliefBridge.Config
    local threshold = tonumber(cfg.combatSoundReliefLevel) or 2
    if threshold <= 0 or level < threshold then return false end

    local dist = brr_nearestPlayerDistance(character:getX(), character:getY())
    local minDist = level >= 3 and (tonumber(cfg.panicCombatSoundDistance) or 12) or (tonumber(cfg.farCombatSoundDistance) or 18)
    if dist < minDist then return false end

    local interval = level >= 3 and 5 or 3
    local id = brain and (brain.id or brain.persistentId or brain.worldGroupId) or 0
    return brr_effectHash(character:getX(), character:getY(), character.getZ and character:getZ() or 0, brr_tick() + (tonumber(id) or 0), interval) ~= 0
end

function NPCRenderReliefBridge.ShouldSkipCombatSplat(character, brain, reason)
    if NPCRenderReliefBridge.Config.enabled == false then return false end
    if not brr_combatReliefEligible(brain) then return false end
    if not (character and character.getX and character.getY) then return false end

    local state = NPCRenderReliefBridge.GetLoadState(false)
    local level = tonumber(state.level) or 0
    local cfg = NPCRenderReliefBridge.Config
    local threshold = tonumber(cfg.combatSplatReliefLevel) or 2
    if threshold <= 0 or level < threshold then return false end

    local dist = brr_nearestPlayerDistance(character:getX(), character:getY())
    local minDist = level >= 3 and (tonumber(cfg.panicCombatSplatDistance) or 10) or (tonumber(cfg.farCombatSplatDistance) or 16)
    if dist < minDist then return false end

    local role = brain and brain.ai and tostring(brain.ai.physicalBattleGovernorRole or "") or ""
    if role == "proxy" then return true end
    local interval = level >= 3 and 3 or 2
    local id = brain and (brain.id or brain.persistentId or brain.worldGroupId) or 0
    return brr_effectHash(character:getX(), character:getY(), character.getZ and character:getZ() or 0, brr_tick() + (tonumber(id) or 0), interval) ~= 0
end

function NPCRenderReliefBridge.ShouldUseFarNPCProxy(bandit, brain, id, uTick)
    if NPCRenderReliefBridge.Config.enabled == false then return false end
    if brr_isPlayerControlledBrain(brain) then return false end
    if not (bandit and bandit.getX and bandit.getY) then return false end

    local state = NPCRenderReliefBridge.GetLoadState(false)
    local level = tonumber(state.level) or 0
    local cfg = NPCRenderReliefBridge.Config
    local threshold = tonumber(cfg.farNPCProxyLevel) or 2
    if threshold <= 0 or level < threshold then return false end

    local dist = brr_nearestPlayerDistance(bandit:getX(), bandit:getY())
    local minDist = level >= 3 and (tonumber(cfg.panicNPCProxyDistance) or 18) or (tonumber(cfg.farNPCProxyDistance) or 26)
    if dist < minDist then return false end

    local interval = level >= 3 and (tonumber(cfg.panicNPCProxyInterval) or 96) or (tonumber(cfg.farNPCProxyInterval) or 48)
    interval = math.max(4, math.floor(interval))
    local key = tostring(id or (brain and (brain.id or brain.persistentId) or 0))
    local h = 0
    for i = 1, #key do h = (h * 33 + string.byte(key, i)) % interval end
    return (tonumber(uTick) or 0) % interval ~= h
end

function NPCRenderReliefBridge.ApplyProxyFrame(bandit, brain)
    if not bandit then return end
    if NPCEntity and NPCEntity.SurpressZombieSounds then pcall(function() NPCEntity.SurpressZombieSounds(bandit) end) end
    if bandit.setUseless then pcall(function() bandit:setUseless(false) end) end
    if brain then
        brain.ai = brain.ai or {}
        brain.ai.renderProxyFrame = true
        brain.ai.renderProxyAt = brr_nowMs()
    end
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

    -- Keep this function side-effect-light: hard render culling is handled by the Java
    -- SpriteRenderer patch. Lua relief only marks runtime intent and avoids unsafe direct
    -- writes to IsoGameCharacter public fields.
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
