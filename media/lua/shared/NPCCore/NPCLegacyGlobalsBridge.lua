NPCLegacyGlobalsBridge = NPCLegacyGlobalsBridge or {}

require "NPCCore/NPCLegacyContractBridge"

local NPC_LEGACY_GLOBAL_TOKEN = NPCLegacyContractBridge.Token
local NPC_LEGACY_GLOBAL_NAMES = NPCLegacyGlobalsBridge.GlobalNames or {
    Entity = NPC_LEGACY_GLOBAL_TOKEN,
    Utils = NPC_LEGACY_GLOBAL_TOKEN .. "Utils",
    Brain = NPC_LEGACY_GLOBAL_TOKEN .. "Brain",
    Compatibility = NPC_LEGACY_GLOBAL_TOKEN .. "Compatibility",
    MovementStability = NPC_LEGACY_GLOBAL_TOKEN .. "MovementStability",
    NavigationPerformance = NPC_LEGACY_GLOBAL_TOKEN .. "NavigationPerformance",
    PlayerClient = NPC_LEGACY_GLOBAL_TOKEN .. "Player",
    ZombieCache = NPC_LEGACY_GLOBAL_TOKEN .. "Zombie",
    Faction = NPC_LEGACY_GLOBAL_TOKEN .. "Faction",
    Spy = NPC_LEGACY_GLOBAL_TOKEN .. "Spy",
    ServerRuntime = NPC_LEGACY_GLOBAL_TOKEN .. "Server",
    DebugMapMarkers = NPC_LEGACY_GLOBAL_TOKEN .. "DebugMapMarkers",
    DebugMapNPCMarkers = NPC_LEGACY_GLOBAL_TOKEN .. "DebugMapNPCMarkers",
    WorldDirector = NPC_LEGACY_GLOBAL_TOKEN .. "WorldDirector",
    SpawnQueue = NPC_LEGACY_GLOBAL_TOKEN .. "SpawnQueue",
    SetDebugMarker = NPC_LEGACY_GLOBAL_TOKEN .. "ServerSetDebugMarker",
    RemoveDebugMarker = NPC_LEGACY_GLOBAL_TOKEN .. "ServerRemoveDebugMarker",
    RefreshWorldGroupMarker = NPC_LEGACY_GLOBAL_TOKEN .. "ServerRefreshWorldGroupMarker",
    BaseSupplyGear = NPC_LEGACY_GLOBAL_TOKEN .. "BaseSupplyGear",
    GlobalData = NPC_LEGACY_GLOBAL_TOKEN .. "GlobalData",
    GlobalDataPlayers = NPC_LEGACY_GLOBAL_TOKEN .. "GlobalDataPlayers",
    GMD = NPC_LEGACY_GLOBAL_TOKEN .. "GMD",
    BaseScenes = NPC_LEGACY_GLOBAL_TOKEN .. "BaseScenes",
    Scenes = NPC_LEGACY_GLOBAL_TOKEN .. "Scenes",
    BaseCampSystem = NPC_LEGACY_GLOBAL_TOKEN .. "BaseCampSystem",
    FactionDocsServer = NPC_LEGACY_GLOBAL_TOKEN .. "FactionDocsServer",
    FactionEconomy = NPC_LEGACY_GLOBAL_TOKEN .. "FactionEconomy",
    BountyServer = NPC_LEGACY_GLOBAL_TOKEN .. "BountyServer",
    WorldRulesServer = NPC_LEGACY_GLOBAL_TOKEN .. "WorldRulesServer",
    BaseSupply = NPC_LEGACY_GLOBAL_TOKEN .. "BaseSupply",
    TacticalCover = NPC_LEGACY_GLOBAL_TOKEN .. "TacticalCover",
}

NPCLegacyGlobalsBridge.GlobalNames = NPC_LEGACY_GLOBAL_NAMES

local function npc_ensureLegacyGlobalName(key, suffix)
    if key and suffix then
        NPC_LEGACY_GLOBAL_NAMES[key] = NPC_LEGACY_GLOBAL_NAMES[key] or (NPC_LEGACY_GLOBAL_TOKEN .. suffix)
    end
end

npc_ensureLegacyGlobalName("RuntimeCache", "RuntimeCache")
npc_ensureLegacyGlobalName("TaskQueue", "TaskQueue")
npc_ensureLegacyGlobalName("AILODTrader", "AILODTrader")
npc_ensureLegacyGlobalName("InterestManager", "InterestManager")
npc_ensureLegacyGlobalName("FlowField", "FlowField")
npc_ensureLegacyGlobalName("TacticalCostField", "TacticalCostField")
npc_ensureLegacyGlobalName("GOAPLite", "GOAPLite")
npc_ensureLegacyGlobalName("FormationSlots", "FormationSlots")
npc_ensureLegacyGlobalName("ProxySimulation", "ProxySimulation")
npc_ensureLegacyGlobalName("BrainDirector", "BrainDirector")
npc_ensureLegacyGlobalName("OrderContract", "Orders")
npc_ensureLegacyGlobalName("UtilityAI", "UtilityAI")
npc_ensureLegacyGlobalName("WorkScheduler", "WorkScheduler")
npc_ensureLegacyGlobalName("AIVision", "AIVision")
npc_ensureLegacyGlobalName("TacticalRadio", "TacticalRadio")
npc_ensureLegacyGlobalName("HealthRegen", "HealthRegen")
npc_ensureLegacyGlobalName("NetContract", "Net")
npc_ensureLegacyGlobalName("PersistentNPC", "PersistentNPC")
npc_ensureLegacyGlobalName("InfluenceField", "InfluenceField")
npc_ensureLegacyGlobalName("DirectorBrain", "DirectorBrain")
npc_ensureLegacyGlobalName("ActionInterceptor", "ActionInterceptor")
npc_ensureLegacyGlobalName("Admin", "Admin")
npc_ensureLegacyGlobalName("BaseCaptureUI", "BaseCaptureUI")
npc_ensureLegacyGlobalName("BaseCapturePanel", "BaseCapturePanel")
npc_ensureLegacyGlobalName("BaseSupplyClient", "BaseSupplyClient")
npc_ensureLegacyGlobalName("BlackMarketClient", "BlackMarketClient")
npc_ensureLegacyGlobalName("BlackMarketStaticOverlay", "BlackMarketStaticOverlay")
npc_ensureLegacyGlobalName("Broadcaster", "Broadcaster")
npc_ensureLegacyGlobalName("DebugSpawnSurvivor", "DebugSpawnSurvivor")
npc_ensureLegacyGlobalName("Lifecycle", "Lifecycle")
npc_ensureLegacyGlobalName("Menu", "Menu")
npc_ensureLegacyGlobalName("ModOptions", "ModOptions")
npc_ensureLegacyGlobalName("Permanent", "Permanent")
npc_ensureLegacyGlobalName("Post", "Post")
npc_ensureLegacyGlobalName("RadioInterceptClient", "RadioInterceptClient")
npc_ensureLegacyGlobalName("FactionDocsClient", "FactionDocsClient")
npc_ensureLegacyGlobalName("Mercenary", "Mercenary")

NPCLegacyGlobalsBridge.GlobalNames = NPC_LEGACY_GLOBAL_NAMES



local function npc_legacyGlobalName(key)
    if not key then return nil end
    if NPC_LEGACY_GLOBAL_NAMES[key] then return NPC_LEGACY_GLOBAL_NAMES[key] end
    key = tostring(key)
    if key:sub(1, #NPC_LEGACY_GLOBAL_TOKEN) == NPC_LEGACY_GLOBAL_TOKEN then return key end
    return NPC_LEGACY_GLOBAL_TOKEN .. key
end

function NPCLegacyGlobalsBridge.ResolveLegacyName(key)
    return npc_legacyGlobalName(key)
end

function NPCLegacyGlobalsBridge.MergeTables(target, previous)
    if type(target) ~= "table" or type(previous) ~= "table" or target == previous then return target end
    for key, value in pairs(previous) do
        if target[key] == nil then
            target[key] = value
        end
    end
    return target
end

function NPCLegacyGlobalsBridge.InstallAlias(key, value, neutralName)
    local legacyName = npc_legacyGlobalName(key)
    if not legacyName then return value end

    local target = value
    if type(value) == "string" then
        neutralName = value
        target = rawget(_G, neutralName)
    end

    local previous = rawget(_G, legacyName)
    if target == nil then
        target = previous or {}
    end

    if neutralName and target ~= nil then
        rawset(_G, neutralName, target)
    end

    NPCLegacyGlobalsBridge.MergeTables(target, previous)
    rawset(_G, legacyName, target)
    return target
end

function NPCLegacyGlobalsBridge.Get(key)
    local name = NPC_LEGACY_GLOBAL_NAMES[key] or key
    if not name then return nil end
    return rawget(_G, name)
end

function NPCLegacyGlobalsBridge.Set(key, value)
    local name = NPC_LEGACY_GLOBAL_NAMES[key] or key
    if name then
        rawset(_G, name, value)
    end
    return value
end

function NPCLegacyGlobalsBridge.Alias(key, value)
    if value ~= nil then
        return NPCLegacyGlobalsBridge.Set(key, value)
    end
    return NPCLegacyGlobalsBridge.Get(key)
end
