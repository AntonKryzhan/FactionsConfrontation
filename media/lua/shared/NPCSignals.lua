-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral field signal backend.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCSignalsBridge"

NPCLegacyGlobalsBridge.InstallAlias("Signals", NPCSignalsBridge)
