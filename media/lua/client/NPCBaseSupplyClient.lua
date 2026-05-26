require "NPCClient/NPCBaseSupplyClientBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCBaseSupplyClientBridge = NPCLegacyGlobalsBridge.InstallAlias("BaseSupplyClient", NPCBaseSupplyClientBridge, "NPCBaseSupplyClient")
NPCBaseSupplyClient = NPCBaseSupplyClientBridge
