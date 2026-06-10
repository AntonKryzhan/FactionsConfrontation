-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral server-side queued NPC materialization backend.

if isClient and isClient() then return end

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCServer/NPCSpawnQueueBridge"

NPCSpawnQueueServer = NPCLegacyGlobalsBridge.InstallAlias("SpawnQueue", NPCSpawnQueueBridge, "NPCSpawnQueueServer")
