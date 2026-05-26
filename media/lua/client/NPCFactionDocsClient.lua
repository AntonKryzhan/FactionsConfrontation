require "NPCClient/NPCFactionDocsClientBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCFactionDocsClient = NPCLegacyGlobalsBridge.InstallAlias("FactionDocsClient", NPCFactionDocsClient, "NPCFactionDocsClient")

NPCFactionDocsClient.RequestStatus = NPCFactionDocsClientBridge.RequestStatus
NPCFactionDocsClient.OnServerCommand = NPCFactionDocsClientBridge.OnServerCommand
NPCFactionDocsClient.Install = NPCFactionDocsClientBridge.Install

NPCFactionDocsClient.Install()
