require "NPCClient/NPCActionInterceptor"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCActionInterceptor = NPCLegacyGlobalsBridge.InstallAlias("ActionInterceptor", NPCActionInterceptor, "NPCActionInterceptor")

NPCActionInterceptor.Main = NPCActionInterceptor.Main
NPCActionInterceptor.TryRegisterPlayerBase = NPCActionInterceptor.TryRegisterPlayerBase
NPCActionInterceptor.Install = NPCActionInterceptor.Install

NPCActionInterceptor.Install()
