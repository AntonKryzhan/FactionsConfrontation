require "NPCClient/NPCBlackMarketClientBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCBlackMarketClientBridge = NPCLegacyGlobalsBridge.InstallAlias("BlackMarketClient", NPCBlackMarketClientBridge, "NPCBlackMarketClient")

if NPCBlackMarketStaticOverlayBridge or NPCLegacyGlobalsBridge.Get("BlackMarketStaticOverlay") then
    NPCLegacyGlobalsBridge.InstallAlias("BlackMarketStaticOverlay", NPCBlackMarketStaticOverlayBridge, "NPCBlackMarketStaticOverlay")
else
    rawset(_G, NPCLegacyGlobalsBridge.ResolveLegacyName("BlackMarketStaticOverlay"), NPCBlackMarketStaticOverlayBridge)
end
