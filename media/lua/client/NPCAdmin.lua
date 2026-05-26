require "NPCClient/NPCAdminMessageBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCAdmin = NPCLegacyGlobalsBridge.InstallAlias("Admin", NPCAdmin, "NPCAdmin")

NPCAdmin.AdminMessage = NPCAdminMessageBridge.AdminMessage

NPCAdminMessageBridge.Install()
