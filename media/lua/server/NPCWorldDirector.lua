if isClient and isClient() then return end

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCServer/NPCWorldDirector"

NPCWorldDirectorServer = NPCLegacyGlobalsBridge.InstallAlias("WorldDirector", NPCWorldDirector, "NPCWorldDirectorServer")
