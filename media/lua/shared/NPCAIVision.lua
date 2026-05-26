-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral shared backend for AI vision sensing, LOS cache and threat memory.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCAIVisionBridge"

NPCLegacyGlobalsBridge.InstallAlias("AIVision", NPCAIVisionBridge)
