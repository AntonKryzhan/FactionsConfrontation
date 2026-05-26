-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral NPCNamesBridge backend.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCNamesBridge"

NPCLegacyGlobalsBridge.InstallAlias("Names", NPCNamesBridge)
