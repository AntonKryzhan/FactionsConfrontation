-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral NPCInterestManagerBridge backend.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCInterestManagerBridge"

NPCLegacyGlobalsBridge.InstallAlias("InterestManager", NPCInterestManagerBridge)
