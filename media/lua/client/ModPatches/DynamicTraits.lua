require "NPCCore/NPCLegacyGlobalsBridge"

NPCPatches = NPCLegacyGlobalsBridge.InstallAlias("Patches", NPCPatches, "NPCPatches")

local function bp_dt_hasDynamicTraits()
    if not getActivatedMods then return false end

    local ok, mods = pcall(getActivatedMods)
    if not ok or not mods then return false end
    if type(mods.contains) ~= "function" then return false end

    return mods:contains("DynamicTraits") == true
end

local function bp_dt_isPlayer(character)
    if not character or not instanceof then return false end

    local ok, result = pcall(instanceof, character, "IsoPlayer")
    return ok and result == true
end

local function bp_dt_callMainHandler(player, target, weapon, damage)
    if not bp_dt_isPlayer(player) then return end
    if type(onPlayerHittingAZombie) ~= "function" then return end

    local ok, err = pcall(onPlayerHittingAZombie, player, target, weapon, damage)
    if not ok then
        print("[NPCWorld] DynamicTraits hit handler guarded: " .. tostring(err))
    end
end

NPCPatches.DynamicTraits = function()
    if not bp_dt_hasDynamicTraits() then return false end

    NPCPatches.DynamicTraitsGuard = NPCPatches.DynamicTraitsGuard or {}
    local guard = NPCPatches.DynamicTraitsGuard
    if guard.installed then return true end

    guard.original = rawget(_G, "DTOnWeaponHitCharacterMain")
    guard.installed = true

    _G.DTOnWeaponHitCharacterMain = function(player, target, weapon, damage)
        bp_dt_callMainHandler(player, target, weapon, damage)
    end

    return true
end

if Events and Events.OnGameStart then
    Events.OnGameStart.Remove(NPCPatches.DynamicTraits)
    Events.OnGameStart.Add(NPCPatches.DynamicTraits)
end
