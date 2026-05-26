require "NPCCore/NPCLegacyGlobalsBridge"

NPCProc = NPCLegacyGlobalsBridge.InstallAlias("Proc", NPCProc, "NPCProc")

function NPCProc.MilitaryTent (sx, sy, sz)
	return false
end
