require "NPCClient/NPCSignalsClientBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCSignalsClient = NPCLegacyGlobalsBridge.InstallAlias("SignalsClient", NPCSignalsClient, "NPCSignalsClient")

NPCSignalsClient.Use = NPCSignalsClientBridge.Use
NPCSignalsClient.History = NPCSignalsClientBridge.History
NPCSignalsClient.OnFillWorldObjectContextMenu = NPCSignalsClientBridge.OnFillWorldObjectContextMenu
NPCSignalsClient.OnServerCommand = NPCSignalsClientBridge.OnServerCommand
NPCSignalsClient.Install = NPCSignalsClientBridge.Install

NPCSignalsClient.Install()
