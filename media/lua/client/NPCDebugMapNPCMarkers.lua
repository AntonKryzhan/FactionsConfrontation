require "NPCClient/NPCDebugMapNPCMarkersBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCDebugMapNPCMarkersBridge = NPCLegacyGlobalsBridge.InstallAlias("DebugMapNPCMarkers", NPCDebugMapNPCMarkersBridge, "NPCDebugMapNPCMarkers")
NPCDebugMapNPCMarkers = NPCDebugMapNPCMarkersBridge
