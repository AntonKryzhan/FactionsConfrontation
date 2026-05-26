-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral disguise backend.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCDisguiseBridge"

NPCLegacyGlobalsBridge.InstallAlias("Disguise", NPCDisguiseBridge)
