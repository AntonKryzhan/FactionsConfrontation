-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral mercenary loyalty backend.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCLoyaltyBridge"

NPCLegacyGlobalsBridge.InstallAlias("Loyalty", NPCLoyaltyBridge)
