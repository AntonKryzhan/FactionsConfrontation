-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral radio intercept server backend.

if isClient and isClient() then return end

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCServer/NPCRadioInterceptServerBridge"

NPCRadioInterceptServer = NPCLegacyGlobalsBridge.InstallAlias("RadioInterceptServer", NPCRadioInterceptServerBridge, "NPCRadioInterceptServer")

if NPCRadioInterceptServer and NPCRadioInterceptServer.Install then
    NPCRadioInterceptServer.Install()
end
