-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral NPCFactionBridge backend.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCFactionBridge"

NPCLegacyGlobalsBridge.InstallAlias("Faction", NPCFactionBridge)
