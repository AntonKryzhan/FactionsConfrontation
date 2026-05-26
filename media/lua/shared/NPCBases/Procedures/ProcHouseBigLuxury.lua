require "NPCCore/NPCLegacyGlobalsBridge"

NPCProc = NPCLegacyGlobalsBridge.InstallAlias("Proc", NPCProc, "NPCProc")

function NPCProc.HouseBigLuxury (sx, sy, sz)
	return false
end
