-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral black market shared backend.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCBlackMarketBridge"

NPCLegacyGlobalsBridge.InstallAlias("BlackMarket", NPCBlackMarketBridge)
