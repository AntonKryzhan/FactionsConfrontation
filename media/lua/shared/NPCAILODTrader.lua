-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral NPCAILODTraderBridge backend.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCAILODTraderBridge"

NPCLegacyGlobalsBridge.InstallAlias("AILODTrader", NPCAILODTraderBridge)
