-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral server field signal backend.

if not isServer() then return end

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCServer/NPCSignalsServerBridge"

NPCSignalsServer = NPCLegacyGlobalsBridge.InstallAlias("SignalsServer", NPCSignalsServerBridge, "NPCSignalsServer")

if NPCSignalsServer and NPCSignalsServer.Install then
    NPCSignalsServer.Install()
end
