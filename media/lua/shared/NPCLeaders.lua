-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral faction leaders backend.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCLeadersBridge"

NPCLegacyGlobalsBridge.InstallAlias("Leaders", NPCLeadersBridge)
