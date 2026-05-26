-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade: real logic lives in media/lua/shared/NPCCore/NPCSquadCoarseWaypointsBridge.lua.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCSquadCoarseWaypointsBridge"

NPCSquadCoarseWaypointsBridge = NPCLegacyGlobalsBridge.InstallAlias("SquadCoarseWaypoints", NPCSquadCoarseWaypointsBridge)
