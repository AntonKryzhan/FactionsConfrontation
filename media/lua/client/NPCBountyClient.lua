require "NPCClient/NPCBountyClientBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCBountyClient = NPCLegacyGlobalsBridge.InstallAlias("BountyClient", NPCBountyClient, "NPCBountyClient")

NPCBountyClient.Status = NPCBountyClientBridge.Status
NPCBountyClient.Refresh = NPCBountyClientBridge.Refresh
NPCBountyClient.OnFillWorldObjectContextMenu = NPCBountyClientBridge.OnFillWorldObjectContextMenu
NPCBountyClient.OnServerCommand = NPCBountyClientBridge.OnServerCommand
NPCBountyClient.Install = NPCBountyClientBridge.Install

NPCBountyClient.Install()
