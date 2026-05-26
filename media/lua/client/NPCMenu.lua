require "NPCClient/NPCMenuBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCMenuBridge = NPCLegacyGlobalsBridge.InstallAlias("Menu", NPCMenuBridge, "NPCMenu")
