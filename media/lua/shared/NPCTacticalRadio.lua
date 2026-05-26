-- tactical-radio module.lua
-- Compatibility facade for the neutral tactical radio backend.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCTacticalRadioBridge"

NPCLegacyGlobalsBridge.InstallAlias("TacticalRadio", NPCTacticalRadioBridge)
