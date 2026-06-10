-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral server bounty backend.

if isClient and isClient() then return end

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCServer/NPCBountyServerBridge"

NPCBountyServer = NPCLegacyGlobalsBridge.InstallAlias("BountyServer", NPCBountyServerBridge, "NPCBountyServer")

if NPCBountyServer and NPCBountyServer.Install then
    NPCBountyServer.Install()
end
