require "NPCCommands/NPCMercenaryContract"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCMercenaryContract = NPCLegacyGlobalsBridge.InstallAlias("Mercenary", NPCMercenaryContract, "NPCMercenaryContract")

-- Compatibility facade for the historical mercenary API.
-- Implementation lives in NPCMercenaryContract so newer systems can use neutral
-- mercenary contracts while existing runtime code keeps legacy mercenary API calls.
