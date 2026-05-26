require "NPCCore/NPCLegacyGlobalsBridge"

NPCProc = NPCLegacyGlobalsBridge.InstallAlias("Proc", NPCProc, "NPCProc")

function NPCProc.Toilet (sx, sy, sz)
	return false
end
