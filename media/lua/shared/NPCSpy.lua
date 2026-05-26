-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral spy/counter-intel backend.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCSpyBridge"

NPCLegacyGlobalsBridge.InstallAlias("Spy", NPCSpyBridge)
