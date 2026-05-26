-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral NPCFormationSlotsBridge backend.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCFormationSlotsBridge"

NPCLegacyGlobalsBridge.InstallAlias("FormationSlots", NPCFormationSlotsBridge)
