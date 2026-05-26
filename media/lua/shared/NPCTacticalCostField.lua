-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral NPCTacticalCostFieldBridge backend.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCTacticalCostFieldBridge"

NPCLegacyGlobalsBridge.InstallAlias("TacticalCostField", NPCTacticalCostFieldBridge)
