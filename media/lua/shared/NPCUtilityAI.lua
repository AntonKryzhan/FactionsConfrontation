-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral neutral shared backend for utility ai needs, morale and autonomous task scoring.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCUtilityAIBridge"

NPCLegacyGlobalsBridge.InstallAlias("UtilityAI", NPCUtilityAIBridge)
