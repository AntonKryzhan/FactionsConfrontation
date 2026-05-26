-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral mercenary loyalty server backend.

if not isServer() then return end

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCServer/NPCLoyaltyServerBridge"

NPCLoyaltyServer = NPCLegacyGlobalsBridge.InstallAlias("LoyaltyServer", NPCLoyaltyServerBridge, "NPCLoyaltyServer")

if NPCLoyaltyServer and NPCLoyaltyServer.Install then
    NPCLoyaltyServer.Install()
end
