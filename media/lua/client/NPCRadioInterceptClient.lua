require "NPCClient/NPCRadioInterceptClientBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCRadioInterceptClientBridge = NPCLegacyGlobalsBridge.InstallAlias("RadioInterceptClient", NPCRadioInterceptClientBridge, "NPCRadioInterceptClient")
NPCRadioInterceptClient = NPCRadioInterceptClientBridge
