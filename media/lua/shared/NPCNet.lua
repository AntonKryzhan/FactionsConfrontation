require "NPCCommands/NPCNetContract"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCNetContract = NPCLegacyGlobalsBridge.InstallAlias("NetContract", NPCNetContract, "NPCNetContract")

-- Compatibility facade for the historical compact network sync API.
-- Implementation lives in NPCNetContract so newer systems can use neutral
-- network contracts while existing runtime code keeps legacy network API calls.
