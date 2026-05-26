-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade: real base camp server logic lives in NPCServer/NPCBaseCampServerBridge.lua.

if not isServer() then return end

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCServer/NPCBaseCampServerBridge"

NPCBaseCampSystem = NPCLegacyGlobalsBridge.InstallAlias("BaseCampSystem", NPCBaseCampServerBridge, "NPCBaseCampSystem")
