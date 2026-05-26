require "NPCClient/NPCModOptionsBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCModOptionsBridge = NPCLegacyGlobalsBridge.InstallAlias("ModOptions", NPCModOptionsBridge, "NPCModOptions")
NPCModOptionsBridge.Install()
