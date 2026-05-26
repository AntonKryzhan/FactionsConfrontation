require "NPCClient/NPCImprovedProjectileCompatBridge"

function initCurrInfoPatched(player, weapon)
    return NPCImprovedProjectileCompatBridge.InitCurrentInfoPatched(player, weapon)
end

function initExploInfoPatched(player, weapon)
    return NPCImprovedProjectileCompatBridge.InitExplosiveInfoPatched(player, weapon)
end

NPCImprovedProjectileCompatBridge.Install()
