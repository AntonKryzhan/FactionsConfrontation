-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral NPCPrisonerBridge backend.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCPrisonerBridge"

NPCLegacyGlobalsBridge.InstallAlias("Prisoner", NPCPrisonerBridge)
