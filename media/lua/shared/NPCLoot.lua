-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral NPCLootBridge backend.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCLootBridge"

NPCLegacyGlobalsBridge.InstallAlias("Loot", NPCLootBridge)
