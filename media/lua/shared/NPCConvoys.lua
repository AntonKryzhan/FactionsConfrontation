-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral convoy backend.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCConvoysBridge"

NPCLegacyGlobalsBridge.InstallAlias("Convoys", NPCConvoysBridge)
