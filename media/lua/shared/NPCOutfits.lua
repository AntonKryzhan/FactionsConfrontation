-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral NPCOutfitsBridge backend.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCOutfitsBridge"

NPCLegacyGlobalsBridge.InstallAlias("Outfits", NPCOutfitsBridge)
