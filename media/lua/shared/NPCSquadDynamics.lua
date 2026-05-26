-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade: real logic lives in media/lua/shared/NPCCore/NPCSquadDynamicsBridge.lua.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCSquadDynamicsBridge"

NPCSquadDynamicsBridge = NPCLegacyGlobalsBridge.InstallAlias("SquadDynamics", NPCSquadDynamicsBridge)
