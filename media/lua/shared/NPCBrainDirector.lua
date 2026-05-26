require "NPCBehavior/NPCBrainDirector"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCBrainDirector = NPCLegacyGlobalsBridge.InstallAlias("BrainDirector", NPCBrainDirector, "NPCBrainDirector")
