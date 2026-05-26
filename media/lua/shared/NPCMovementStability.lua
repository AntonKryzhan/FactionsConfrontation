-- movement-stability module.lua
-- Compatibility facade for the neutral neutral shared backend for movement stability and stuck recovery.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCMovementStabilityBridge"

NPCLegacyGlobalsBridge.InstallAlias("MovementStability", NPCMovementStabilityBridge)
