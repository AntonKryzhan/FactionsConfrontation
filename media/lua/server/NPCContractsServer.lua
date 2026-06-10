-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral server contracts backend.

if isClient and isClient() then return end

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCServer/NPCContractsServerBridge"

NPCContractsServer = NPCLegacyGlobalsBridge.InstallAlias("ContractsServer", NPCContractsServerBridge, "NPCContractsServer")

if NPCContractsServer and NPCContractsServer.Install then
    NPCContractsServer.Install()
end
