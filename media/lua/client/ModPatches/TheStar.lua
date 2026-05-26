require "NPCCore/NPCLegacyGlobalsBridge"

NPCPatches = NPCLegacyGlobalsBridge.InstallAlias("Patches", NPCPatches, "NPCPatches")

local BP_TS_LEGACY_ORIGINAL_SUFFIX = "_" .. NPCLegacyContractBridge.Plural .. "Original"
local BP_TS_LEGACY_WRAPPED_SUFFIX = "_" .. NPCLegacyContractBridge.Plural .. "Wrapped"

local function bp_ts_isTheStarActive()
    if not getActivatedMods then return false end
    local ok, active = pcall(function()
        local mods = getActivatedMods()
        return mods and mods:contains("TheStar")
    end)
    return ok and active == true
end

local function bp_ts_isPlayer(player)
    if not player or not instanceof then return false end
    local ok, result = pcall(function()
        return instanceof(player, "IsoPlayer")
    end)
    return ok and result == true
end

local function bp_ts_safeCall(handler, player, item)
    if not bp_ts_isPlayer(player) then return end
    local ok, err = pcall(handler, player, item)
    if not ok then
        print("[NPCWorld] TheStar handler guarded: " .. tostring(err))
    end
end

local function bp_ts_isTheStarHandler(handler)
    if type(handler) ~= "function" then return false end
    if not debug or not debug.getinfo then return true end

    local ok, info = pcall(debug.getinfo, handler, "S")
    if not ok or not info then return true end

    local source = tostring(info.source or "")
    if string.find(source, "TheStar", 1, true) then return true end
    if string.find(source, "WeaponCondition", 1, true) then return true end
    if string.find(source, "ConditionIndicator", 1, true) then return true end
    return false
end

local function bp_ts_installEquipEventGuard(eventObject, store, eventName)
    if not eventObject or type(eventObject.Add) ~= "function" or type(eventObject.Remove) ~= "function" then return false end
    if store.installed then return true end

    store.installed = true
    store.byOriginal = store.byOriginal or {}
    store.byWrapped = store.byWrapped or {}
    store.originalAdd = eventObject.Add
    store.originalRemove = eventObject.Remove

    eventObject.Add = function(handler)
        if not bp_ts_isTheStarActive() or not bp_ts_isTheStarHandler(handler) then
            return store.originalAdd(handler)
        end

        local wrapped = store.byOriginal[handler]
        if not wrapped then
            wrapped = function(player, item)
                if not bp_ts_isPlayer(player) then return end
                local ok, err = pcall(handler, player, item)
                if not ok then
                    print("[NPCWorld] TheStar " .. tostring(eventName) .. " handler guarded: " .. tostring(err))
                end
            end
            store.byOriginal[handler] = wrapped
            store.byWrapped[wrapped] = handler
        end

        return store.originalAdd(wrapped)
    end

    eventObject.Remove = function(handler)
        local wrapped = store.byOriginal and store.byOriginal[handler]
        if wrapped then
            store.originalRemove(wrapped)
            store.byWrapped[wrapped] = nil
            store.byOriginal[handler] = nil
            return
        end
        return store.originalRemove(handler)
    end

    return true
end

local function bp_ts_installEquipGuards()
    if not bp_ts_isTheStarActive() then return false end

    NPCPatches.TheStarEquipGuards = NPCPatches.TheStarEquipGuards or {}
    local guards = NPCPatches.TheStarEquipGuards
    guards.primary = guards.primary or {}
    guards.secondary = guards.secondary or {}

    bp_ts_installEquipEventGuard(Events.OnEquipPrimary, guards.primary, "OnEquipPrimary")
    bp_ts_installEquipEventGuard(Events.OnEquipSecondary, guards.secondary, "OnEquipSecondary")

    return true
end

local function bp_ts_patchHandler(owner, key, eventObject, optionEnabled)
    if type(owner) ~= "table" or type(owner[key]) ~= "function" then return false end
    if not eventObject or type(eventObject.Remove) ~= "function" or type(eventObject.Add) ~= "function" then return false end

    local original = owner[key]
    if owner[key .. BP_TS_LEGACY_ORIGINAL_SUFFIX] and owner[key .. BP_TS_LEGACY_WRAPPED_SUFFIX] then
        return true
    elseif owner[key .. BP_TS_LEGACY_ORIGINAL_SUFFIX] then
        original = owner[key .. BP_TS_LEGACY_ORIGINAL_SUFFIX]
    end

    eventObject.Remove(owner[key])
    eventObject.Remove(original)

    local wrapped = function(player, item)
        bp_ts_safeCall(original, player, item)
    end

    owner[key .. BP_TS_LEGACY_ORIGINAL_SUFFIX] = original
    owner[key .. BP_TS_LEGACY_WRAPPED_SUFFIX] = wrapped
    owner[key] = wrapped

    if optionEnabled ~= false then
        eventObject.Add(wrapped)
    end

    return true
end

NPCPatches.TheStar = function()
    if not bp_ts_isTheStarActive() then return end

    bp_ts_installEquipGuards()

    if TheStar then
        local patched = 0

        if TheStar.Notifier and TheStar.Notifier.Condition then
            if bp_ts_patchHandler(TheStar.Notifier.Condition, "onEquipPrimary", Events.OnEquipPrimary, not TheStar.Options or TheStar.Options.showOverheadNotification ~= false) then
                patched = patched + 1
            end
        end

        if TheStar.HandMainExtension and TheStar.HandMainExtension.Ammo then
            if bp_ts_patchHandler(TheStar.HandMainExtension.Ammo, "onEquipPrimary", Events.OnEquipPrimary, not TheStar.Options or TheStar.Options.showAmmoCountEquippedItem ~= false) then
                patched = patched + 1
            end
        end

        if TheStar.HandMainExtension and TheStar.HandMainExtension.Battery then
            if bp_ts_patchHandler(TheStar.HandMainExtension.Battery, "onEquipPrimary", Events.OnEquipPrimary, not TheStar.Options or TheStar.Options.showBatteryChargeEquippedItem ~= false) then
                patched = patched + 1
            end
        end

        if patched > 0 and NPCPatches.TheStarLastGuardedCount ~= patched then
            NPCPatches.TheStarLastGuardedCount = patched
            print("[NPCWorld] TheStar equip handlers guarded: " .. tostring(patched))
        end
    end
end

NPCPatches.TheStar()
Events.OnGameStart.Remove(NPCPatches.TheStar)
Events.OnGameStart.Add(NPCPatches.TheStar)

local function bp_ts_scheduleEarlyReapply()
    NPCPatches.TheStar()

    if NPCPatches.TheStarEarlyReapplyRunning then return end
    if not Events or not Events.OnTick then return end

    NPCPatches.TheStarEarlyReapplyRunning = true
    local ticks = 0
    local function retry()
        ticks = ticks + 1
        if ticks == 1 or ticks == 10 or ticks == 30 then
            NPCPatches.TheStar()
        end
        if ticks >= 30 then
            Events.OnTick.Remove(retry)
            NPCPatches.TheStarEarlyReapplyRunning = false
        end
    end
    Events.OnTick.Add(retry)
end

Events.OnCreatePlayer.Add(function()
    bp_ts_scheduleEarlyReapply()
end)
