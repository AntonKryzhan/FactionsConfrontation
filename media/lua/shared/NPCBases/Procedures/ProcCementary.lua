require "NPCCore/NPCLegacyGlobalsBridge"

NPCProc = NPCLegacyGlobalsBridge.InstallAlias("Proc", NPCProc, "NPCProc")

function NPCProc.Cementary (sx, sy, sz)
	return false
end
