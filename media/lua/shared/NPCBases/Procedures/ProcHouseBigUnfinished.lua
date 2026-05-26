require "NPCCore/NPCLegacyGlobalsBridge"

NPCProc = NPCLegacyGlobalsBridge.InstallAlias("Proc", NPCProc, "NPCProc")

function NPCProc.HouseBigUnfinished (sx, sy, sz)
	return false
end
