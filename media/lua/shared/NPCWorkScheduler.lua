-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral shared backend for adaptive work scheduler.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCWorkSchedulerBridge"

NPCLegacyGlobalsBridge.InstallAlias("WorkScheduler", NPCWorkSchedulerBridge)
