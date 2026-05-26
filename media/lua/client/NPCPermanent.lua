require "NPCClient/NPCPersistenceClient"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCPermanent = NPCLegacyGlobalsBridge.InstallAlias("Permanent", NPCPermanent, "NPCPermanent")

NPCPermanent.Check = NPCPersistenceClient.Check
NPCPermanent.Install = NPCPersistenceClient.Install

NPCPermanent.Install()
