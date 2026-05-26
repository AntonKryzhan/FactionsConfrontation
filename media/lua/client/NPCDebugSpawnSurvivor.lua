require "NPCClient/NPCDebugSpawnSurvivorBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCDebugSpawnSurvivorBridge = NPCLegacyGlobalsBridge.InstallAlias("DebugSpawnSurvivor", NPCDebugSpawnSurvivorBridge, "NPCDebugSpawnSurvivor")
NPCDebugSpawnSurvivor = NPCDebugSpawnSurvivorBridge
