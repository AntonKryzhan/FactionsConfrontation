-- NPCClanRegistryBridge.lua
-- Stage 253: legacy ZombieClans data was retired.
-- Keep an empty compatibility table for old debug/fallback callers only.

require "NPCCore/NPCLegacyGlobalsBridge"

NPCClan = NPCClan or {}
NPCClanRegistryBridge = NPCClan

NPCLegacyGlobalsBridge.InstallAlias("Clan", NPCClan, "NPCClan")

return NPCClanRegistryBridge
