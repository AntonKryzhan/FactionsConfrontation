--
-- Compatibility facade for the neutral NPC director brain runtime.
--

if not isServer() then return end

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCServer/NPCDirectorBrainServerBridge"

NPCDirectorBrainServer = NPCLegacyGlobalsBridge.InstallAlias("DirectorBrain", NPCDirectorBrainServerBridge, "NPCDirectorBrainServer")
