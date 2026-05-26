-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral NPCProxySimulationBridge backend.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCProxySimulationBridge"

NPCLegacyGlobalsBridge.InstallAlias("ProxySimulation", NPCProxySimulationBridge)
