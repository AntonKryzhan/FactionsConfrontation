require "NPCCommands/NPCOrderContract"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCOrderContract = NPCLegacyGlobalsBridge.InstallAlias("OrderContract", NPCOrderContract, "NPCOrderContract")

-- Compatibility facade for the historical friendly-order API.
-- Implementation lives in NPCOrderContract so newer systems can use neutral
-- command contracts while existing runtime code keeps legacy order API calls.
