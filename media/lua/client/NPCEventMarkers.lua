require "NPCClient/NPCEventMarkerUI"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCLegacyGlobalsBridge.InstallAlias("EventMarker", NPCEventMarkerUI.Marker, "NPCEventMarker")
