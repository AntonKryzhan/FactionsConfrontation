require "NPCClient/NPCLeadersClientBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCLeadersClient = NPCLegacyGlobalsBridge.InstallAlias("LeadersClient", NPCLeadersClient, "NPCLeadersClient")

NPCLeadersClient.Status = NPCLeadersClientBridge.Status
NPCLeadersClient.Refresh = NPCLeadersClientBridge.Refresh
NPCLeadersClient.OnFillWorldObjectContextMenu = NPCLeadersClientBridge.OnFillWorldObjectContextMenu
NPCLeadersClient.OnServerCommand = NPCLeadersClientBridge.OnServerCommand
NPCLeadersClient.Install = NPCLeadersClientBridge.Install

NPCLeadersClient.Install()
