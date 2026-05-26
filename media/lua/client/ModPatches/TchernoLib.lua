require "NPCCore/NPCLegacyGlobalsBridge"

NPCPatches = NPCLegacyGlobalsBridge.InstallAlias("Patches", NPCPatches, "NPCPatches")

NPCPatches.TchernoLib = function()
    local mods = getActivatedMods and getActivatedMods()
    if not (mods and mods.contains and mods:contains("TchernoLib")) then
        return false
    end

    if not (PlaVar and PlaVar.onZombieUpdateDontAttack and Events and Events.OnZombieUpdate) then
        return false
    end

    if PlaVar.__AKTchernoLibCompatInstalled then
        return true
    end

    Events.OnZombieUpdate.Remove(PlaVar.onZombieUpdateDontAttack)

    PlaVar.__AKTchernoLibOriginalOnZombieUpdateDontAttack = PlaVar.onZombieUpdateDontAttack
    PlaVar.onZombieUpdateDontAttack = function(isoZombie)
        return false
    end

    PlaVar.__AKTchernoLibCompatInstalled = true
    print("TchernoLib compatibility patch applied.")
    return true
end

-- Keep this compatibility hook manual; it is not registered by default.
