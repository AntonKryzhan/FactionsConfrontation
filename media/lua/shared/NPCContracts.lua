-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral contracts backend.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCContractsBridge"

NPCLegacyGlobalsBridge.InstallAlias("Contracts", NPCContractsBridge)
