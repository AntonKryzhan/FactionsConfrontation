-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral base supply server backend.

if not isServer() then return end

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCServer/NPCBaseSupplyServerBridge"

NPCBaseSupplyServer = NPCLegacyGlobalsBridge.InstallAlias("BaseSupply", NPCBaseSupplyServerBridge, "NPCBaseSupplyServer")
