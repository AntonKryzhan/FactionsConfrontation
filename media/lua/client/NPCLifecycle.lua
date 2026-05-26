require "NPCClient/NPCLifecycleBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCLifecycleBridge = NPCLegacyGlobalsBridge.InstallAlias("Lifecycle", NPCLifecycleBridge, "NPCLifecycle")
NPCLifecycle = NPCLifecycleBridge
