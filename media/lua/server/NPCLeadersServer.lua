-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral faction leaders server backend.

if not isServer() then return end

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCServer/NPCLeadersServerBridge"

NPCLeadersServer = NPCLegacyGlobalsBridge.InstallAlias("LeadersServer", NPCLeadersServerBridge, "NPCLeadersServer")

if NPCLeadersServer and NPCLeadersServer.Install then
    NPCLeadersServer.Install()
end
