-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral base supply server backend.

if isClient and isClient() then return end

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCServer/NPCBaseSupplyServerBridge"

NPCBaseSupplyServer = NPCLegacyGlobalsBridge.InstallAlias("BaseSupply", NPCBaseSupplyServerBridge, "NPCBaseSupplyServer")
