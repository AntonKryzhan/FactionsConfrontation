-- NPCWoundedBridge.lua
-- Neutral require target for wounded-ally callers. Keeps the legacy legacy NPCWounded facade as an alias.

require "NPCCore/NPCLegacyContractBridge"
require "NPCWounded"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCWoundedBridge = NPCWoundedBridge or NPCWounded or NPCWounded or {}
NPCWounded = NPCWounded or NPCWoundedBridge
NPCLegacyGlobalsBridge.InstallAlias("Wounded", NPCWoundedBridge, "NPCWoundedBridge")

return NPCWoundedBridge
