-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade: real strategic AI logic lives in NPCCore/NPCStrategicAIBridge.lua.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCStrategicAIBridge"

NPCStrategicAIBridge = NPCLegacyGlobalsBridge.InstallAlias("StrategicAI", NPCStrategicAIBridge)
