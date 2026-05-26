-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral NPCIdentityBridge backend.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCIdentityBridge"

NPCLegacyGlobalsBridge.InstallAlias("Identity", NPCIdentityBridge)
