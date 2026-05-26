-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral shared backend for crowd budget and spawn pressure control.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCCrowdBudgetBridge"

NPCLegacyGlobalsBridge.InstallAlias("CrowdBudget", NPCCrowdBudgetBridge)
