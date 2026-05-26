-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral NPCHumanizedAIBridge backend.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCHumanizedAIBridge"

NPCLegacyGlobalsBridge.InstallAlias("HumanizedAI", NPCHumanizedAIBridge)
