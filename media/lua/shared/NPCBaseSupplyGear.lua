-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral base supply gear shared backend.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCBaseSupplyGearBridge"

NPCLegacyGlobalsBridge.InstallAlias("BaseSupplyGear", NPCBaseSupplyGearBridge)
