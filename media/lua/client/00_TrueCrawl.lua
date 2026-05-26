require "NPCClient/NPCTrueCrawlCompatBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCPatches = NPCLegacyGlobalsBridge.InstallAlias("Patches", NPCPatches, "NPCPatches")

NPCPatches.TrueCrawl = function()
    return NPCTrueCrawlCompatBridge.Install()
end


Events.OnGameStart.Add(NPCPatches.TrueCrawl)
