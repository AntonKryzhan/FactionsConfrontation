-- Legacy compatibility facade for the neutral visible base stockpiles backend.

if isClient and isClient() then return end

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCServer/NPCBaseStockpilesServerBridge"

NPCBaseStockpilesServer = NPCLegacyGlobalsBridge.InstallAlias("BaseStockpilesServer", NPCBaseStockpilesServerBridge, "NPCBaseStockpilesServer")

if NPCBaseStockpilesServer and NPCBaseStockpilesServer.Install then
    NPCBaseStockpilesServer.Install()
end
