require "NPCBehavior/NPCProgramRaiderBridge"
require "ZombiePrograms/ZPRaider"
require "NPCCore/NPCLegacyContractBridge"

ZombiePrograms = ZombiePrograms or {}

-- Legacy program alias. New hostile NPCs use the neutral Raider program name;
-- old saves and remaining compatibility callers can still resolve legacy NPC.
ZombiePrograms[NPCLegacyContractBridge.Program("RAIDER")] = ZombiePrograms.Raider
