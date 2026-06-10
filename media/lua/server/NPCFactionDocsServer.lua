-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral faction documents server backend.

if isClient and isClient() then return end

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCServer/NPCFactionDocsServerBridge"

NPCFactionDocsServer = NPCLegacyGlobalsBridge.InstallAlias("FactionDocsServer", NPCFactionDocsServerBridge, "NPCFactionDocsServer")

if NPCFactionDocsServer and NPCFactionDocsServer.Install then
    NPCFactionDocsServer.Install()
end
