require "NPCClient/NPCCharacterScreenBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCCharacterScreenBridge = NPCLegacyGlobalsBridge.InstallAlias("CharacterScreenBridge", NPCCharacterScreenBridge, "NPCCharacterScreenBridge")

NPCCharacterScreenBridge.Install()
