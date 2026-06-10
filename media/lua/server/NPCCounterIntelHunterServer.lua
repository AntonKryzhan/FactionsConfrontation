if isClient and isClient() then return end

require "NPCServer/NPCCounterIntelHunterServerBridge"

NPCCounterIntelHunterServer = NPCCounterIntelHunterServerBridge

if NPCCounterIntelHunterServer and NPCCounterIntelHunterServer.Install then
    NPCCounterIntelHunterServer.Install()
end
