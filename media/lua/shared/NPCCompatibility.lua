require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCCompatibilityBridge"

NPCCompatibilityBridge = NPCLegacyGlobalsBridge.InstallAlias("Compatibility", NPCCompatibilityBridge)
