-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral NPCCreatorBridge backend.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCCreatorBridge"

NPCLegacyGlobalsBridge.InstallAlias("Creator", NPCCreatorBridge)
