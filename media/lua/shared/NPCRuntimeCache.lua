-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral NPCRuntimeCacheBridge backend.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCRuntimeCacheBridge"

NPCLegacyGlobalsBridge.InstallAlias("RuntimeCache", NPCRuntimeCacheBridge)
