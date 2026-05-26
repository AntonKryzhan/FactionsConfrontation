-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral NPCRoadNavBridge backend.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCRoadNavBridge"

NPCLegacyGlobalsBridge.InstallAlias("RoadNav", NPCRoadNavBridge)
