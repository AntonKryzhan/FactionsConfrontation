require "NPCClient/NPCDebugMapMarkersBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCDebugMapMarkersBridge = NPCLegacyGlobalsBridge.InstallAlias("DebugMapMarkers", NPCDebugMapMarkersBridge, "NPCDebugMapMarkers")
NPCDebugMapMarkers = NPCDebugMapMarkersBridge
