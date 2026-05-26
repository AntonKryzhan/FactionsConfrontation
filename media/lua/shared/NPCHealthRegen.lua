-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral NPCHealthRegenBridge backend.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCHealthRegenBridge"

NPCLegacyGlobalsBridge.InstallAlias("HealthRegen", NPCHealthRegenBridge)
