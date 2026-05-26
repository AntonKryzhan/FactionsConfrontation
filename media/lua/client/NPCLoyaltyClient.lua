require "NPCClient/NPCLoyaltyClientBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCLoyaltyClient = NPCLegacyGlobalsBridge.InstallAlias("LoyaltyClient", NPCLoyaltyClient, "NPCLoyaltyClient")

NPCLoyaltyClient.Status = NPCLoyaltyClientBridge.Status
NPCLoyaltyClient.Refresh = NPCLoyaltyClientBridge.Refresh
NPCLoyaltyClient.OnFillWorldObjectContextMenu = NPCLoyaltyClientBridge.OnFillWorldObjectContextMenu
NPCLoyaltyClient.OnServerCommand = NPCLoyaltyClientBridge.OnServerCommand
NPCLoyaltyClient.Install = NPCLoyaltyClientBridge.Install

NPCLoyaltyClient.Install()
