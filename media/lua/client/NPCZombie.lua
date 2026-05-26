require "NPCClient/NPCZombieCacheBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCZombieCacheBridge = NPCLegacyGlobalsBridge.InstallAlias("ZombieCache", NPCZombieCacheBridge, "NPCZombieCache")
NPCZombieCache = NPCZombieCacheBridge
