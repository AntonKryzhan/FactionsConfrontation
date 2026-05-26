-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade: real logic lives in media/lua/shared/NPCCore/NPCStreamingRuntimeBridge.lua.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCStreamingRuntimeBridge"

NPCStreamingRuntimeBridge = NPCLegacyGlobalsBridge.InstallAlias("StreamingRuntime", NPCStreamingRuntimeBridge)
