-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral shared backend for runtime influence field.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCInfluenceFieldBridge"

NPCLegacyGlobalsBridge.InstallAlias("InfluenceField", NPCInfluenceFieldBridge)
