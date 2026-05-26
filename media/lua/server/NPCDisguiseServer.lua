-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral server disguise backend.

if not isServer() then return end

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCServer/NPCDisguiseServerBridge"

NPCDisguiseServer = NPCLegacyGlobalsBridge.InstallAlias("DisguiseServer", NPCDisguiseServerBridge, "NPCDisguiseServer")

if NPCDisguiseServer and NPCDisguiseServer.Install then
    NPCDisguiseServer.Install()
end
