require "NPCClient/NPCBroadcasterBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCBroadcasterBridge = NPCLegacyGlobalsBridge.InstallAlias("Broadcaster", NPCBroadcasterBridge, "NPCBroadcaster")
NPCBroadcaster = NPCBroadcasterBridge
