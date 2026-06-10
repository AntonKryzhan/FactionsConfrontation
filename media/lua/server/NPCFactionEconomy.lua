-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral faction economy server backend.

if isClient and isClient() then return end

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCServer/NPCFactionEconomyServerBridge"

NPCFactionEconomyServer = NPCLegacyGlobalsBridge.InstallAlias("FactionEconomy", NPCFactionEconomyServerBridge, "NPCFactionEconomyServer")
