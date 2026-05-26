-- NPCTacticalCoverBridge.lua
-- Neutral optional adapter for the historical tactical cover provider.

require "NPCCore/NPCLegacyGlobalsBridge"

NPCTacticalCoverBridge = NPCTacticalCoverBridge or {}
local NPC_LEGACY_GLOBALS = NPCLegacyGlobalsBridge

local function npctacticalcover_merge(source)
    if type(source) ~= "table" or source == NPCTacticalCoverBridge then return end
    for key, value in pairs(source) do
        if NPCTacticalCoverBridge[key] == nil then
            NPCTacticalCoverBridge[key] = value
        end
    end
end

function NPCTacticalCoverBridge.Resolve()
    local legacy = NPC_LEGACY_GLOBALS.Get("TacticalCover")
    npctacticalcover_merge(legacy)
    NPC_LEGACY_GLOBALS.InstallAlias("TacticalCover", NPCTacticalCoverBridge, "NPCTacticalCoverBridge")
    return NPCTacticalCoverBridge
end

NPCTacticalCoverBridge.Resolve()
