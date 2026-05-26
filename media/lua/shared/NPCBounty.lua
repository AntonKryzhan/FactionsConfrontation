-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral bounty backend.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCBountyBridge"

NPCLegacyGlobalsBridge.InstallAlias("Bounty", NPCBountyBridge)
