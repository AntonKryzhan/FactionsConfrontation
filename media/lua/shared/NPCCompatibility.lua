require "NPCCore/NPCLegacyGlobalsBridge"
pcall(require, "NPCCompatibilityGuardsRuntime")
require "NPCCore/NPCCompatibilityBridge"

NPCCompatibilityBridge = NPCLegacyGlobalsBridge.InstallAlias("Compatibility", NPCCompatibilityBridge)
