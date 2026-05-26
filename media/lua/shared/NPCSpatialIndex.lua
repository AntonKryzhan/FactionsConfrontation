-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral NPCSpatialIndexBridge backend.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCSpatialIndexBridge"

NPCLegacyGlobalsBridge.InstallAlias("SpatialIndex", NPCSpatialIndexBridge)
