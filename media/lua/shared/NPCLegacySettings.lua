require "NPCCore/NPCLegacySettingsBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCLegacySettingsBridge = NPCLegacyGlobalsBridge.InstallAlias("LegacySettings", NPCLegacySettingsBridge, "NPCLegacySettingsBridge")
