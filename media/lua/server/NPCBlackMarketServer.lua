-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral black market server backend.

if not isServer() then return end

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCServer/NPCBlackMarketServerBridge"

NPCBlackMarketServer = NPCLegacyGlobalsBridge.InstallAlias("BlackMarketServer", NPCBlackMarketServerBridge, "NPCBlackMarketServer")

if NPCBlackMarketServer and NPCBlackMarketServer.Install then
    NPCBlackMarketServer.Install()
end
