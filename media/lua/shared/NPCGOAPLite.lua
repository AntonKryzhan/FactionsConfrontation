-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral NPCGOAPLiteBridge backend.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCGOAPLiteBridge"

NPCLegacyGlobalsBridge.InstallAlias("GOAPLite", NPCGOAPLiteBridge)
