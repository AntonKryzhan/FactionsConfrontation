-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral server convoy backend.

if not isServer() then return end

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCServer/NPCConvoysServerBridge"

NPCConvoysServer = NPCLegacyGlobalsBridge.InstallAlias("ConvoysServer", NPCConvoysServerBridge, "NPCConvoysServer")

if NPCConvoysServer and NPCConvoysServer.Install then
    NPCConvoysServer.Install()
end
