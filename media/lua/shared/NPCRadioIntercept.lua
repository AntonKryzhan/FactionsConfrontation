-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral radio intercept shared backend.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCRadioInterceptBridge"

NPCLegacyGlobalsBridge.InstallAlias("RadioIntercept", NPCRadioInterceptBridge)
