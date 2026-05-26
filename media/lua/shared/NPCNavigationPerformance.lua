-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral neutral shared backend for navigation performance, repair queue and portal pressure.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCNavigationPerformanceBridge"

NPCLegacyGlobalsBridge.InstallAlias("NavigationPerformance", NPCNavigationPerformanceBridge)
