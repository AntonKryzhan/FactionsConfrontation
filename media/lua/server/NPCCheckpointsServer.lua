-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral checkpoints server backend.

if not isServer() then return end

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCServer/NPCCheckpointsServerBridge"

NPCCheckpointsServer = NPCLegacyGlobalsBridge.InstallAlias("CheckpointsServer", NPCCheckpointsServerBridge, "NPCCheckpointsServer")

if NPCCheckpointsServer and NPCCheckpointsServer.Install then
    NPCCheckpointsServer.Install()
end
