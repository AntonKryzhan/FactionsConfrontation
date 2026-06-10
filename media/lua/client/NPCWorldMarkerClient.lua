require "NPCClient/NPCWorldMarkerClientBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCWorldMarkerClientBridge = NPCLegacyGlobalsBridge.InstallAlias("WorldMarkerClient", NPCWorldMarkerClientBridge, "NPCWorldMarkerClientBridge")
if NPCWorldMarkerOverlayBridge or NPCLegacyGlobalsBridge.Get("WorldMarkerOverlay") then
    NPCLegacyGlobalsBridge.InstallAlias("WorldMarkerOverlay", NPCWorldMarkerOverlayBridge, "NPCWorldMarkerOverlayBridge")
else
    rawset(_G, NPCLegacyGlobalsBridge.ResolveLegacyName("WorldMarkerOverlay"), NPCWorldMarkerOverlayBridge)
end
