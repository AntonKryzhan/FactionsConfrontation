require "NPCCore/NPCLegacyGlobalsBridge"

NPCPatches = NPCLegacyGlobalsBridge.InstallAlias("Patches", NPCPatches, "NPCPatches")

local function bp_ip_hasImprovedProjectile()
    if not getActivatedMods then return false end

    local ok, mods = pcall(getActivatedMods)
    if not ok or not mods then return false end
    if type(mods.contains) ~= "function" then return false end

    return mods:contains("ImprovedProjectile") == true
end

NPCPatches.ImprovedProjectile = function()
    if not bp_ip_hasImprovedProjectile() then
        NPCPatches.ImprovedProjectileActive = false
        return false
    end

    -- Compatibility hook intentionally left passive: the current projectile stack
    -- does not need a runtime override here, but other files may still call this
    -- public patch entry point.
    NPCPatches.ImprovedProjectileActive = true
    return true
end

if Events and Events.OnGameStart then
    Events.OnGameStart.Remove(NPCPatches.ImprovedProjectile)
    Events.OnGameStart.Add(NPCPatches.ImprovedProjectile)
end
