-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral checkpoints backend.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCCheckpointsBridge"

NPCLegacyGlobalsBridge.InstallAlias("Checkpoints", NPCCheckpointsBridge)
