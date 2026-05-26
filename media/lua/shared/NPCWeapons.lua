-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral NPCWeaponsBridge backend.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCWeaponsBridge"

NPCLegacyGlobalsBridge.InstallAlias("Weapons", NPCWeaponsBridge)
