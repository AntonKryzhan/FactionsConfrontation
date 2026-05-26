-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral NPCTaskQueueBridge backend.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCTaskQueueBridge"

NPCLegacyGlobalsBridge.InstallAlias("TaskQueue", NPCTaskQueueBridge)
