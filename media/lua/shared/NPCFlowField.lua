-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral NPCFlowFieldBridge backend.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCFlowFieldBridge"

NPCLegacyGlobalsBridge.InstallAlias("FlowField", NPCFlowFieldBridge)
