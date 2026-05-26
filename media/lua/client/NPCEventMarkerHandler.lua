require "NPCClient/NPCEventMarkerHandler"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCEventMarkerHandler = NPCLegacyGlobalsBridge.InstallAlias("EventMarkerHandler", NPCEventMarkerHandler, "NPCEventMarkerHandler")
