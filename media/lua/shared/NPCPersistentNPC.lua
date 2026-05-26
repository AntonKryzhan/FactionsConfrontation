-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade: real logic lives in media/lua/shared/NPCCore/NPCPersistentNPCBridge.lua.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCPersistentNPCBridge"

NPCPersistentNPCBridge = NPCLegacyGlobalsBridge.InstallAlias("PersistentNPC", NPCPersistentNPCBridge)
