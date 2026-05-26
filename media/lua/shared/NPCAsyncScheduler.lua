-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral NPCAsyncSchedulerBridge backend.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCAsyncSchedulerBridge"

NPCLegacyGlobalsBridge.InstallAlias("AsyncScheduler", NPCAsyncSchedulerBridge)
