require "NPCClient/NPCPlayerClient"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCPlayerClient = NPCLegacyGlobalsBridge.InstallAlias("PlayerClient", NPCPlayerClient, "NPCPlayerClient")
