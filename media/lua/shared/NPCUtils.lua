require "NPCCore/NPCUtilityCore"
require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCUtils = NPCLegacyGlobalsBridge.InstallAlias("Utils", NPCUtils, "NPCUtils")

-- Compatibility facade for the historical utility table.
-- Implementation lives in NPCUtilityCore so newer systems can use neutral
-- helpers while existing runtime call sites keep the same API.

NPCUtils.ItemVisuals = NPCUtilityCore.ItemVisuals

local NPC_UTILS_LEGACY_TOKEN = NPCLegacyContractBridge.Token

local function bind(name)
    NPCUtils[name] = function(...)
        return NPCUtilityCore[name](...)
    end
end

bind("GetZombieID")
bind("GetCharacterID")
bind("IsController")
bind("IsInAngle")
bind("CalcAngle")
bind("GetClosestPlayerLocation")
bind("GetClosestEnemyPlayerLocation")
bind("GetClosestZombieLocation")
bind("GetClosestZombieLocationFast")
bind("GetClosest" .. NPC_UTILS_LEGACY_TOKEN .. "Location")
bind("GetClosest" .. NPC_UTILS_LEGACY_TOKEN .. "LocationFast")
bind("GetClosestEnemy" .. NPC_UTILS_LEGACY_TOKEN .. "Location")
bind("GetClosestNPCLocation")
bind("GetClosestNPCLocationFast")
bind("GetClosestEnemyNPCLocation")
bind("GetMoveTask")
bind("CloneIsoPlayer")
bind("GetNumNearbyBuildings")
bind("GetBuildingID")
bind("findPoint")
bind("Bresenham")
bind("IsWater")
bind("GetGroundType")
bind("ReplaceDrainable")
bind("DistTo")
bind("LineClear")
bind("DistToManhattan")
bind("Choice")
bind("CoinFlip")
bind("NPCRand")
local legacyRand = NPC_UTILS_LEGACY_TOKEN .. "Rand"
NPCUtils[legacyRand] = NPCUtils[legacyRand] or NPCUtils.NPCRand
