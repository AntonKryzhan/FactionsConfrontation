-- Neutral world director bridge.
-- Compatibility backend for the legacy world-director facade.

NPCWorldDirectorBridge = NPCWorldDirectorBridge or {}
NPCWorldDirectorBridge.Version = 458

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCCheckpointsBridge"
require "NPCCore/NPCLeadersBridge"
require "NPCCore/NPCOutfitsBridge"
require "NPCCore/NPCIdentityReconciliationBridge"
require "NPCCore/NPCZombieLifecycleClassifierBridge"
require "NPCCore/NPCMarkerReconciliationBridge"
require "NPCCore/NPCDiagnosticsBridge"
pcall(require, "NPCCore/NPCPerformanceTelemetryBridge")
pcall(require, "NPCCore/NPCStreamingRuntimeBridge")

local function npc_wd_isSinglePlayerRuntime()
    return (not (isClient and isClient())) and (not (isServer and isServer()))
end

local function npc_wd_spBudget(value, fallback, minValue, maxValue)
    local n = tonumber(value) or tonumber(fallback) or 0
    if minValue ~= nil and n < minValue then n = minValue end
    if maxValue ~= nil and n > maxValue then n = maxValue end
    return n
end

local function npc_wd_shouldSkipSPActivationScan(source, tick)
    if not npc_wd_isSinglePlayerRuntime() then return false end
    if NPCStreamingRuntimeBridge and NPCStreamingRuntimeBridge.ShouldSkipActivationScan then
        local ok, skip = pcall(function() return NPCStreamingRuntimeBridge.ShouldSkipActivationScan(source or "world_director", tick) end)
        if ok and skip == true then return true end
    end
    return false
end

local npc_wd_shouldBootstrapGate
local npc_wd_recordBootstrapGate

local NPC_WORLD_DIRECTOR_LEGACY_KEYS = {
    liveFlag = NPCLegacyContractBridge.Key("FLAG"),
    isNPC = NPCLegacyContractBridge.Key("IS_FLAG"),
    formerNPCZombie = NPCLegacyContractBridge.Key("FORMER_ZOMBIE"),
    runtimeId = NPCLegacyContractBridge.Key("RUNTIME_ID"),
    persistentId = NPCLegacyContractBridge.Key("PERSISTENT_ID"),
    worldGroupId = NPCLegacyContractBridge.Key("WORLD_GROUP_ID"),
    program = NPCLegacyContractBridge.Key("PROGRAM"),
    primary = NPCLegacyContractBridge.Key("PRIMARY"),
    secondary = NPCLegacyContractBridge.Key("SECONDARY"),
    sandboxSection = NPCLegacyContractBridge.Sandbox.main
}
local NPC_WORLD_DIRECTOR_LEGACY_COMMANDS = {
    removeObjects = NPCLegacyContractBridge.Command("REMOVE_OBJECTS")
}
local NPC_WORLD_DIRECTOR_LOG_PREFIX = "[NPCWorldDirector]"
local NPC_WORLD_DIRECTOR_LEGACY_FIELDS = {
    formerCleanupScopes = NPCLegacyContractBridge.State.formerCleanupScopes
}

function NPCWorldDirectorBridge.IsPlayerCommandedMercenaryGroup(group)
    if type(group) ~= "table" then return false end
    return group.commandAuthority == "player"
        or group.playerCommandAuthority == true
        or group.worldCommandDisabled == true
        or group.mercenaryHired == true
        or group.hired == true
        or group.isPlayerGuard == true
        or group.state == "player_commanded"
end


function NPCWorldDirectorBridge.ApplyDefaults(director)
    if not director then return end

    director.STARTUP_GROUPS = 56
    director.STARTUP_ROAD_PATROLS_RED = 18
    director.STARTUP_ROAD_PATROLS_GREEN = 18
    director.STARTUP_ROAD_PATROL_ENCOUNTERS = 22
    director.MAX_ROAD_PATROLS = 70
    director.MAX_VIRTUAL_GROUPS = 150
    director.MAX_PHYSICAL_GROUPS = 6
    director.PHYSICAL_DEACTIVATION_RADIUS = 260
    director.PHYSICAL_REACTIVATION_RADIUS = 150
    director.PHYSICAL_DEACTIVATION_HIGH_LOAD_RADIUS = 220
    director.PHYSICAL_DEACTIVATION_CRITICAL_RADIUS = 190
    director.PHYSICAL_DEACTIVATION_IMPORTANT_RADIUS = 420
    director.PHYSICAL_DEACTIVATION_MIN_AGE_HOURS = 6 / 3600
    director.PHYSICAL_CLEANUP_INTERVAL_TICKS = 300
    director.PHYSICAL_CLEANUP_HIGH_INTERVAL_TICKS = 90
    director.PHYSICAL_CLEANUP_CRITICAL_INTERVAL_TICKS = 30
    director.PHYSICAL_CLEANUP_MAX_DEMATERIALIZE_PER_RUN = 5
    director.PHYSICAL_CLEANUP_STREAMING_MAX_DEMATERIALIZE_PER_RUN = 6
    director.SPAWN_CHANCE_PER_TEN_MIN = 34
    director.ACTIVATION_RADIUS = 150
    director.MAX_GROUP_ACTIVATIONS_PER_UPDATE = 1
    director.MAX_GROUP_ACTIVATIONS_PER_PLAYER = 1
    director.MAX_BATTLE_PAIR_ACTIVATIONS_PER_UPDATE = 1
    director.ACTIVATION_NPC_SOFT_CAP_PER_PLAYER = 14
    director.DEFER_ACTIVATION_WHEN_NPC_NEAR_PLAYER = true
    director.PROXY_LOD_HARD_CAP_ENABLED = true
    director.PROXY_LOD_MAX_REAL_NPC_PER_PLAYER = 12
    director.PROXY_LOD_MAX_REAL_NPC_HIGH = 8
    director.PROXY_LOD_MAX_REAL_NPC_CRITICAL = 5
    director.PROXY_LOD_MAX_REAL_NPC_GLOBAL = 28
    director.PROXY_LOD_PROTECTED_RADIUS = 74
    director.PROXY_LOD_ENFORCE_INTERVAL_TICKS = 30
    director.PROXY_LOD_DEMATERIALIZE_PER_RUN = 6
    director.PROXY_LOD_RETRY_SECONDS = 18
    director.PROXY_LOD_DEBUG = false
    director.WORLD_CALENDAR_QUEUE_ENABLED = true
    director.WORLD_CALENDAR_MAX_TASKS_PER_TICK = 2
    director.WORLD_CALENDAR_DEFER_TICKS = 9
    director.WORLD_CALENDAR_JITTER_TICKS = 37
    director.SP_HARD_STREAMING_QUARANTINE_ENABLED = director.SP_HARD_STREAMING_QUARANTINE_ENABLED ~= false
    director.SP_QUARANTINE_BOOTSTRAP_MIN_INTERVAL_TICKS = director.SP_QUARANTINE_BOOTSTRAP_MIN_INTERVAL_TICKS or 90
    director.SP_QUARANTINE_BOOTSTRAP_GROUPS_PER_STEP = director.SP_QUARANTINE_BOOTSTRAP_GROUPS_PER_STEP or 1
    director.SP_QUARANTINE_BOOTSTRAP_ROAD_PATROLS_PER_STEP = director.SP_QUARANTINE_BOOTSTRAP_ROAD_PATROLS_PER_STEP or 0
    director.SP_QUARANTINE_WORLD_UPDATE_DEFER_TICKS = director.SP_QUARANTINE_WORLD_UPDATE_DEFER_TICKS or 600
    director.SP_BOOTSTRAP_HARD_GATE_ENABLED = director.SP_BOOTSTRAP_HARD_GATE_ENABLED ~= false
    director.SP_BOOTSTRAP_GATE_MARKER_SYNC = director.SP_BOOTSTRAP_GATE_MARKER_SYNC ~= false
    director.SP_BOOTSTRAP_GATE_VIRTUAL_GROUPS = director.SP_BOOTSTRAP_GATE_VIRTUAL_GROUPS ~= false
    director.SP_BOOTSTRAP_GATE_ROAD_BATTLES = director.SP_BOOTSTRAP_GATE_ROAD_BATTLES ~= false
    director.SP_BOOTSTRAP_GATE_BASE_ECONOMY = director.SP_BOOTSTRAP_GATE_BASE_ECONOMY ~= false
    director.NET_BATCHED_REMOVE_OBJECTS = true
    director.NET_REMOVE_OBJECTS_BATCH_INTERVAL_TICKS = 6
    director.NET_REMOVE_OBJECTS_MAX_IDS_PER_BATCH = 96
    director.FORMER_NPC_CLEANUP_SCOPE_TTL_TICKS = 1800
    director.FORMER_NPC_CLEANUP_SCOPE_INTERVAL_TICKS = 15
    director.FORMER_NPC_CLEANUP_SCOPE_MAX = 32
    local formerLegacyScopePrefix = "FORMER_" .. "BAN" .. "DIT"
    director[formerLegacyScopePrefix .. "_CLEANUP_SCOPE_TTL_TICKS"] = director.FORMER_NPC_CLEANUP_SCOPE_TTL_TICKS
    director[formerLegacyScopePrefix .. "_CLEANUP_SCOPE_INTERVAL_TICKS"] = director.FORMER_NPC_CLEANUP_SCOPE_INTERVAL_TICKS
    director[formerLegacyScopePrefix .. "_CLEANUP_SCOPE_MAX"] = director.FORMER_NPC_CLEANUP_SCOPE_MAX
    director.TELEPORT_ACTIVATION_COOLDOWN_HOURS = 2 / 3600
    director.TELEPORT_DISTANCE_THRESHOLD = 180
    director.TELEPORT_MARKER_MATERIALIZE_RADIUS = 72
    director.DEFERRED_ACTIVATION_RETRY_HOURS = 0.012
    director.MATERIALIZE_BATTLE_PAIR_AS_SINGLE_WAVE = true
    director.OFFSCREEN_MATERIALIZE_ENABLED = true
    director.OFFSCREEN_SPAWN_MIN_DISTANCE = 48
    director.OFFSCREEN_SPAWN_MAX_DISTANCE = 78
    director.OFFSCREEN_SPAWN_SAFE_PLAYER_RADIUS = 38
    director.OFFSCREEN_SPAWN_SEARCH_RADIUS = 9
    director.NO_NEW_GROUP_NEAR_PLAYER_RADIUS = 700
    director.TILE_CELL_SIZE = 300

    -- Prefer places where a survivor/faction group can actually make sense.
    -- The director now tries town/road/navigation zones first and uses a random
    -- fallback only if a map/mod does not expose useful MetaGrid zone data.
    director.PREFERRED_POINT_ATTEMPTS = 1900
    director.FALLBACK_POINT_ATTEMPTS = 360
    director.VIRTUAL_TARGET_ATTEMPTS = 240
    director.VIRTUAL_MOVE_SPEED_TILES_PER_HOUR = 120
    director.VIRTUAL_TARGET_RADIUS = 300
    director.ROAD_PATROL_TARGET_RADIUS = 480
    director.ROAD_PATROL_VIRTUAL_STEP_RADIUS = 360
    director.VIRTUAL_CLUSTER_ACTIVATION_RADIUS = director.VIRTUAL_CLUSTER_ACTIVATION_RADIUS or 140
    director.VIRTUAL_CLUSTER_ACTIVATION_MAX = director.VIRTUAL_CLUSTER_ACTIVATION_MAX or 4
    director.VIRTUAL_MAP_ROAD_PROJECTION_ENABLED = director.VIRTUAL_MAP_ROAD_PROJECTION_ENABLED ~= false
    director.VIRTUAL_MAP_ROAD_PROJECTION_WAYPOINTS = director.VIRTUAL_MAP_ROAD_PROJECTION_WAYPOINTS or 5
    director.VIRTUAL_MAP_ROAD_PROJECTION_RADIUS = director.VIRTUAL_MAP_ROAD_PROJECTION_RADIUS or 360
    director.VIRTUAL_MAP_ROAD_PROJECTION_ATTEMPTS = director.VIRTUAL_MAP_ROAD_PROJECTION_ATTEMPTS or 48
    director.VIRTUAL_MAP_ROAD_PROJECTION_CACHE_HOURS = director.VIRTUAL_MAP_ROAD_PROJECTION_CACHE_HOURS or 0.35
    director.VIRTUAL_ROAD_FOLLOWING_ENABLED = director.VIRTUAL_ROAD_FOLLOWING_ENABLED ~= false
    director.VIRTUAL_ROAD_FOLLOWING_MIN_DISTANCE = director.VIRTUAL_ROAD_FOLLOWING_MIN_DISTANCE or 95
    director.VIRTUAL_ROAD_FOLLOWING_FINAL_APPROACH_DISTANCE = director.VIRTUAL_ROAD_FOLLOWING_FINAL_APPROACH_DISTANCE or 70
    director.VIRTUAL_ROAD_FOLLOWING_STEP_REUSE_DISTANCE = director.VIRTUAL_ROAD_FOLLOWING_STEP_REUSE_DISTANCE or 18
    director.VIRTUAL_ROAD_FOLLOWING_STEP_EXPIRE_HOURS = director.VIRTUAL_ROAD_FOLLOWING_STEP_EXPIRE_HOURS or 0.12
    director.ROAD_PATROL_ENCOUNTER_MIN_DISTANCE = 45
    director.ROAD_PATROL_ENCOUNTER_MAX_DISTANCE = 130
    director.ROAD_PATROL_BATTLE_RADIUS = 260
    director.ROAD_PATROL_BATTLE_GRID_SIZE = director.ROAD_PATROL_BATTLE_GRID_SIZE or 300
    director.ROAD_PATROL_BATTLE_KEEP_RADIUS = 360
    director.ROAD_PATROL_BATTLE_TICK_HOURS = 0.025
    if director.ROAD_PATROL_BATTLE_REENGAGE_COOLDOWN_HOURS == nil or tonumber(director.ROAD_PATROL_BATTLE_REENGAGE_COOLDOWN_HOURS) == 0.35 or tonumber(director.ROAD_PATROL_BATTLE_REENGAGE_COOLDOWN_HOURS) == 0.65 then director.ROAD_PATROL_BATTLE_REENGAGE_COOLDOWN_HOURS = 0.08 end
    director.ROAD_PATROL_BATTLE_STARTUP_DELAY_HOURS = director.ROAD_PATROL_BATTLE_STARTUP_DELAY_HOURS or 0.02
    director.ROAD_PATROL_BATTLE_MAX_STARTS_PER_UPDATE = director.ROAD_PATROL_BATTLE_MAX_STARTS_PER_UPDATE or 6
    director.ROAD_PATROL_BATTLE_DECISIVE = director.ROAD_PATROL_BATTLE_DECISIVE ~= false
    director.STRATEGIC_MARKER_GROUPS_ENABLED = director.STRATEGIC_MARKER_GROUPS_ENABLED ~= false
    director.STRATEGIC_MARKER_ACTIVATION_RADIUS = director.STRATEGIC_MARKER_ACTIVATION_RADIUS or 300
    director.CHECKPOINT_GUARD_GROUP_SIZE = director.CHECKPOINT_GUARD_GROUP_SIZE or 5
    director.CHECKPOINT_FORCE_ACTIVATION_RADIUS = director.CHECKPOINT_FORCE_ACTIVATION_RADIUS or 90
    director.BASE_GARRISON_GROUP_SIZE = director.BASE_GARRISON_GROUP_SIZE or 6
    director.STRATEGIC_GROUP_MIN_REFRESH_HOURS = director.STRATEGIC_GROUP_MIN_REFRESH_HOURS or 0.05
    director.STRATEGIC_MARKER_PERSISTENCE_ENABLED = director.STRATEGIC_MARKER_PERSISTENCE_ENABLED ~= false
    director.STRATEGIC_WAR_ENABLED = director.STRATEGIC_WAR_ENABLED ~= false
    director.STRATEGIC_FRONT_UPDATE_HOURS = director.STRATEGIC_FRONT_UPDATE_HOURS or 0.10
    director.STRATEGIC_FRONT_PRESSURE_COOLDOWN_HOURS = director.STRATEGIC_FRONT_PRESSURE_COOLDOWN_HOURS or 0.55
    director.STRATEGIC_FRONT_SIDE_TARGET_GROUPS = director.STRATEGIC_FRONT_SIDE_TARGET_GROUPS or 9
    director.STRATEGIC_FRONT_PRESSURE_GROUP_SIZE = director.STRATEGIC_FRONT_PRESSURE_GROUP_SIZE or 4
    director.STRATEGIC_WAR_MAX_BASE_IMBALANCE = director.STRATEGIC_WAR_MAX_BASE_IMBALANCE or 1
    director.STRATEGIC_GROUP_SIDE_BALANCE_MAX_DELTA = director.STRATEGIC_GROUP_SIDE_BALANCE_MAX_DELTA or 2
    director.STRATEGIC_FRONT_TIE_ALTERNATE_SIDES = director.STRATEGIC_FRONT_TIE_ALTERNATE_SIDES ~= false
    director.STRATEGIC_INITIAL_FACTION_BASES_ENABLED = director.STRATEGIC_INITIAL_FACTION_BASES_ENABLED ~= false
    director.STRATEGIC_INITIAL_FACTION_BASE_GRID = director.STRATEGIC_INITIAL_FACTION_BASE_GRID or 820
    director.STRATEGIC_INITIAL_FACTION_BASE_PROVOCATION_RADIUS = director.STRATEGIC_INITIAL_FACTION_BASE_PROVOCATION_RADIUS or 1500
    director.STRATEGIC_INITIAL_FACTION_BASE_MAX_IMBALANCE = director.STRATEGIC_INITIAL_FACTION_BASE_MAX_IMBALANCE or 1
    director.STRATEGIC_ACTIVITY_GRAPH_ENABLED = director.STRATEGIC_ACTIVITY_GRAPH_ENABLED ~= false
    director.STRATEGIC_ACTIVITY_UPDATE_HOURS = director.STRATEGIC_ACTIVITY_UPDATE_HOURS or 0.18
    director.STRATEGIC_ACTIVITY_INACTIVE_TTL_HOURS = director.STRATEGIC_ACTIVITY_INACTIVE_TTL_HOURS or 6.0
    if director.STRATEGIC_ACTIVITY_MAX_ASSIGNMENTS_PER_UPDATE == nil or tonumber(director.STRATEGIC_ACTIVITY_MAX_ASSIGNMENTS_PER_UPDATE) == 16 then director.STRATEGIC_ACTIVITY_MAX_ASSIGNMENTS_PER_UPDATE = 6 end
    director.STRATEGIC_ACTIVITY_STARTUP_DELAY_HOURS = director.STRATEGIC_ACTIVITY_STARTUP_DELAY_HOURS or 0.10
    director.STRATEGIC_ACTIVITY_STARTUP_RAMP_HOURS = director.STRATEGIC_ACTIVITY_STARTUP_RAMP_HOURS or 0.85
    director.STRATEGIC_ACTIVITY_STARTUP_MAX_ASSIGNMENTS = director.STRATEGIC_ACTIVITY_STARTUP_MAX_ASSIGNMENTS or 2
    director.STRATEGIC_ACTIVITY_SCAN_LIMIT_PER_UPDATE = director.STRATEGIC_ACTIVITY_SCAN_LIMIT_PER_UPDATE or 52
    director.STRATEGIC_ACTIVITY_STARTUP_SCAN_LIMIT = director.STRATEGIC_ACTIVITY_STARTUP_SCAN_LIMIT or 28
    director.STRATEGIC_ACTIVITY_REASSIGN_COOLDOWN_HOURS = director.STRATEGIC_ACTIVITY_REASSIGN_COOLDOWN_HOURS or 0.65
    director.STRATEGIC_ACTIVITY_SAME_TARGET_DISTANCE = director.STRATEGIC_ACTIVITY_SAME_TARGET_DISTANCE or 24
    director.STRATEGIC_ACTIVITY_HUNT_PLAYER_RADIUS = director.STRATEGIC_ACTIVITY_HUNT_PLAYER_RADIUS or 520
    director.STRATEGIC_ACTIVITY_SIEGE_RADIUS = director.STRATEGIC_ACTIVITY_SIEGE_RADIUS or 520
    director.STRATEGIC_ACTIVITY_LOW_READINESS = director.STRATEGIC_ACTIVITY_LOW_READINESS or 55
    if director.STRATEGIC_ACTIVITY_CRITICAL_READINESS == nil or tonumber(director.STRATEGIC_ACTIVITY_CRITICAL_READINESS) == 30 then director.STRATEGIC_ACTIVITY_CRITICAL_READINESS = 18 end
    if director.STRATEGIC_ACTIVITY_ROAD_PATROL_RETREAT_READINESS == nil or tonumber(director.STRATEGIC_ACTIVITY_ROAD_PATROL_RETREAT_READINESS) == 22 then director.STRATEGIC_ACTIVITY_ROAD_PATROL_RETREAT_READINESS = 14 end
    director.STRATEGIC_ACTIVITY_ROAD_PATROL_MIN_COUNT = director.STRATEGIC_ACTIVITY_ROAD_PATROL_MIN_COUNT or 1
    director.STRATEGIC_EXPANSION_NEUTRAL_FIRST_ENABLED = director.STRATEGIC_EXPANSION_NEUTRAL_FIRST_ENABLED ~= false
    director.STRATEGIC_EXPANSION_NEUTRAL_RADIUS = director.STRATEGIC_EXPANSION_NEUTRAL_RADIUS or 1800
    director.STRATEGIC_EXPANSION_NEUTRAL_BONUS = director.STRATEGIC_EXPANSION_NEUTRAL_BONUS or 420
    director.STRATEGIC_EXPANSION_ENEMY_DELAY_PENALTY = director.STRATEGIC_EXPANSION_ENEMY_DELAY_PENALTY or 620
    director.STRATEGIC_MANEUVER_ENABLED = director.STRATEGIC_MANEUVER_ENABLED ~= false
    director.STRATEGIC_MANEUVER_MIN_DISTANCE = director.STRATEGIC_MANEUVER_MIN_DISTANCE or 560
    director.STRATEGIC_MANEUVER_STRIKE_MIN_COUNT = director.STRATEGIC_MANEUVER_STRIKE_MIN_COUNT or 3
    director.STRATEGIC_MANEUVER_FLANK_MAX_OFFSET = director.STRATEGIC_MANEUVER_FLANK_MAX_OFFSET or 360
    director.STRATEGIC_MANEUVER_APPROACH_DISTANCE = director.STRATEGIC_MANEUVER_APPROACH_DISTANCE or 460
    director.STRATEGIC_STRIKE_ASSEMBLY_ENABLED = director.STRATEGIC_STRIKE_ASSEMBLY_ENABLED ~= false
    director.STRATEGIC_STRIKE_ASSEMBLY_MIN_GROUPS = director.STRATEGIC_STRIKE_ASSEMBLY_MIN_GROUPS or 2
    director.STRATEGIC_STRIKE_ASSEMBLY_MAX_GROUPS = director.STRATEGIC_STRIKE_ASSEMBLY_MAX_GROUPS or 4
    director.STRATEGIC_STRIKE_ASSEMBLY_MAX_WAIT_HOURS = director.STRATEGIC_STRIKE_ASSEMBLY_MAX_WAIT_HOURS or 1.25
    director.STRATEGIC_STRIKE_STAGING_DISTANCE = director.STRATEGIC_STRIKE_STAGING_DISTANCE or 360
    director.STRATEGIC_STRIKE_STAGING_OFFSET = director.STRATEGIC_STRIKE_STAGING_OFFSET or 170
    director.STRATEGIC_ENCIRCLEMENT_ENABLED = director.STRATEGIC_ENCIRCLEMENT_ENABLED ~= false
    director.STRATEGIC_ENCIRCLEMENT_MIN_COMMITTED_GROUPS = director.STRATEGIC_ENCIRCLEMENT_MIN_COMMITTED_GROUPS or 3
    director.STRATEGIC_ENCIRCLEMENT_RADIUS = director.STRATEGIC_ENCIRCLEMENT_RADIUS or 260
    director.STRATEGIC_ENCIRCLEMENT_OFFSET = director.STRATEGIC_ENCIRCLEMENT_OFFSET or 320
    director.STRATEGIC_REINFORCE_THREATENED_BASE_ENABLED = director.STRATEGIC_REINFORCE_THREATENED_BASE_ENABLED ~= false
    director.STRATEGIC_REINFORCE_THREATENED_BASE_MAX_GROUPS = director.STRATEGIC_REINFORCE_THREATENED_BASE_MAX_GROUPS or 3
    director.STRATEGIC_REINFORCE_THREATENED_BASE_RADIUS = director.STRATEGIC_REINFORCE_THREATENED_BASE_RADIUS or 2600
    director.STRATEGIC_REINFORCE_BREAK_STRIKE_THREAT = director.STRATEGIC_REINFORCE_BREAK_STRIKE_THREAT or 980
    director.STRATEGIC_REINFORCE_LOW_DEFENSE_SCORE = director.STRATEGIC_REINFORCE_LOW_DEFENSE_SCORE or 380
    director.STRATEGIC_COUNTER_AMBUSH_ENABLED = director.STRATEGIC_COUNTER_AMBUSH_ENABLED ~= false
    director.STRATEGIC_COUNTER_AMBUSH_MAX_PER_SIDE = director.STRATEGIC_COUNTER_AMBUSH_MAX_PER_SIDE or 2
    director.STRATEGIC_COUNTER_AMBUSH_MIN_THREAT = director.STRATEGIC_COUNTER_AMBUSH_MIN_THREAT or 620
    director.STRATEGIC_COUNTER_AMBUSH_MIN_READINESS = director.STRATEGIC_COUNTER_AMBUSH_MIN_READINESS or 58
    director.STRATEGIC_COUNTER_AMBUSH_RADIUS = director.STRATEGIC_COUNTER_AMBUSH_RADIUS or 2400
    director.STRATEGIC_COUNTER_AMBUSH_OFFSET = director.STRATEGIC_COUNTER_AMBUSH_OFFSET or 180
    director.BASE_OWNED_GLOBAL_GROUPS_ENABLED = director.BASE_OWNED_GLOBAL_GROUPS_ENABLED ~= false
    director.BASE_OWNED_GLOBAL_GROUPS_SPAWN_ENABLED = director.BASE_OWNED_GLOBAL_GROUPS_SPAWN_ENABLED ~= false
    director.BASE_OWNED_GLOBAL_GROUPS_REPAIR_PROTECT = director.BASE_OWNED_GLOBAL_GROUPS_REPAIR_PROTECT ~= false
    director.BASE_OWNED_GLOBAL_GROUPS_REPAIR_COOLDOWN_HOURS = director.BASE_OWNED_GLOBAL_GROUPS_REPAIR_COOLDOWN_HOURS or 1.20
    director.BASE_OWNED_GLOBAL_GROUPS_STAGING_RADIUS = director.BASE_OWNED_GLOBAL_GROUPS_STAGING_RADIUS or 42
    director.BASE_OWNED_GLOBAL_GROUPS_PATROL_RADIUS = director.BASE_OWNED_GLOBAL_GROUPS_PATROL_RADIUS or 620
    director.BASE_OWNED_GLOBAL_GROUPS_MAX_BASE_DISTANCE = director.BASE_OWNED_GLOBAL_GROUPS_MAX_BASE_DISTANCE or 6200
    director.BLUE_MERCENARY_PATROL_STABILITY_ENABLED = director.BLUE_MERCENARY_PATROL_STABILITY_ENABLED ~= false
    if director.BLUE_MERCENARY_PATROL_MOVE_SPEED == nil or tonumber(director.BLUE_MERCENARY_PATROL_MOVE_SPEED) == 34 or tonumber(director.BLUE_MERCENARY_PATROL_MOVE_SPEED) == 80 then director.BLUE_MERCENARY_PATROL_MOVE_SPEED = 22 end
    if director.BLUE_MERCENARY_PATROL_RETARGET_COOLDOWN_HOURS == nil or tonumber(director.BLUE_MERCENARY_PATROL_RETARGET_COOLDOWN_HOURS) == 1.50 then director.BLUE_MERCENARY_PATROL_RETARGET_COOLDOWN_HOURS = 3.0 end
    if director.BLUE_MERCENARY_PATROL_BATTLE_GRACE_HOURS == nil or tonumber(director.BLUE_MERCENARY_PATROL_BATTLE_GRACE_HOURS) == 4.0 then director.BLUE_MERCENARY_PATROL_BATTLE_GRACE_HOURS = 6.0 end
    if director.BLUE_MERCENARY_PATROL_MAP_DWELL_HOURS == nil or tonumber(director.BLUE_MERCENARY_PATROL_MAP_DWELL_HOURS) == 5.0 then director.BLUE_MERCENARY_PATROL_MAP_DWELL_HOURS = 8.0 end
    director.BLUE_MERCENARY_PATROL_MIN_COUNT_RETREAT = director.BLUE_MERCENARY_PATROL_MIN_COUNT_RETREAT or 1
    director.STRATEGIC_LOGISTICS_ENABLED = director.STRATEGIC_LOGISTICS_ENABLED ~= false
    director.STRATEGIC_LOGISTICS_UPDATE_HOURS = director.STRATEGIC_LOGISTICS_UPDATE_HOURS or 0.35
    director.STRATEGIC_LOGISTICS_MAX_DT_HOURS = director.STRATEGIC_LOGISTICS_MAX_DT_HOURS or 3.0
    director.STRATEGIC_LOGISTICS_LOW_SUPPLY = director.STRATEGIC_LOGISTICS_LOW_SUPPLY or 42
    director.STRATEGIC_LOGISTICS_LOW_AMMO = director.STRATEGIC_LOGISTICS_LOW_AMMO or 38
    director.STRATEGIC_LOGISTICS_LOW_MORALE = director.STRATEGIC_LOGISTICS_LOW_MORALE or 35
    director.STRATEGIC_LOGISTICS_CRITICAL_SUPPLY = director.STRATEGIC_LOGISTICS_CRITICAL_SUPPLY or 22
    director.STRATEGIC_LOGISTICS_CRITICAL_AMMO = director.STRATEGIC_LOGISTICS_CRITICAL_AMMO or 20
    director.STRATEGIC_LOGISTICS_CRITICAL_MORALE = director.STRATEGIC_LOGISTICS_CRITICAL_MORALE or 18
    director.STRATEGIC_LOGISTICS_GROUP_DRAIN = director.STRATEGIC_LOGISTICS_GROUP_DRAIN or 1.20
    director.STRATEGIC_LOGISTICS_BASE_REGEN = director.STRATEGIC_LOGISTICS_BASE_REGEN or 5.50
    director.STRATEGIC_LOGISTICS_RESUPPLY_RADIUS = director.STRATEGIC_LOGISTICS_RESUPPLY_RADIUS or 220
    director.STRATEGIC_LOGISTICS_FRONT_PRESSURE_RADIUS = director.STRATEGIC_LOGISTICS_FRONT_PRESSURE_RADIUS or 900
    director.STRATEGIC_LOGISTICS_FRONT_NUDGE_TILES = director.STRATEGIC_LOGISTICS_FRONT_NUDGE_TILES or 220
    director.STRATEGIC_LOGISTICS_SUPPLY_LINE_RANGE = director.STRATEGIC_LOGISTICS_SUPPLY_LINE_RANGE or 1800
    director.STRATEGIC_LOGISTICS_MAX_SIDE_LOSS_MEMORY = director.STRATEGIC_LOGISTICS_MAX_SIDE_LOSS_MEMORY or 120
    director.BASE_LOGISTICS_ECONOMY_ENABLED = director.BASE_LOGISTICS_ECONOMY_ENABLED ~= false
    director.BASE_LOGISTICS_ECONOMY_UPDATE_HOURS = director.BASE_LOGISTICS_ECONOMY_UPDATE_HOURS or 0.25
    director.BASE_LOGISTICS_MANPOWER_PER_GARRISON = director.BASE_LOGISTICS_MANPOWER_PER_GARRISON or 2.4
    director.BASE_LOGISTICS_MIN_PATROL_MANPOWER = director.BASE_LOGISTICS_MIN_PATROL_MANPOWER or 3
    director.BASE_LOGISTICS_MIN_RAID_MANPOWER = director.BASE_LOGISTICS_MIN_RAID_MANPOWER or 5
    director.BASE_LOGISTICS_MANPOWER_RECOVERY_PER_HOUR = director.BASE_LOGISTICS_MANPOWER_RECOVERY_PER_HOUR or 0.32
    director.BASE_LOGISTICS_WOUNDED_RECOVERY_PER_HOUR = director.BASE_LOGISTICS_WOUNDED_RECOVERY_PER_HOUR or 0.22
    director.BASE_LOGISTICS_GROUP_SUPPLY_DRAIN = director.BASE_LOGISTICS_GROUP_SUPPLY_DRAIN or 0.055
    director.BASE_LOGISTICS_GROUP_AMMO_DRAIN = director.BASE_LOGISTICS_GROUP_AMMO_DRAIN or 0.050
    director.BASE_LOGISTICS_GROUP_MEDICAL_DRAIN = director.BASE_LOGISTICS_GROUP_MEDICAL_DRAIN or 0.014
    director.BASE_LOGISTICS_RESUPPLY_GAIN = director.BASE_LOGISTICS_RESUPPLY_GAIN or 10.0
    director.BASE_LOGISTICS_CRITICAL_READINESS = director.BASE_LOGISTICS_CRITICAL_READINESS or 28
    director.BASE_LOGISTICS_LOW_READINESS = director.BASE_LOGISTICS_LOW_READINESS or 52
    director.STRATEGIC_REALISM_ENABLED = director.STRATEGIC_REALISM_ENABLED ~= false
    director.STRATEGIC_REALISM_ROUTE_PENALTY_PER_1000_TILES = director.STRATEGIC_REALISM_ROUTE_PENALTY_PER_1000_TILES or 140
    director.STRATEGIC_REALISM_DEFENSE_SCORE_WEIGHT = director.STRATEGIC_REALISM_DEFENSE_SCORE_WEIGHT or 0.85
    director.STRATEGIC_SIEGE_TICK_HOURS = director.STRATEGIC_SIEGE_TICK_HOURS or 0.22
    director.STRATEGIC_SIEGE_RADIUS = director.STRATEGIC_SIEGE_RADIUS or 140
    director.STRATEGIC_SIEGE_RETREAT_COUNT = director.STRATEGIC_SIEGE_RETREAT_COUNT or 2
    director.WORLD_BEHAVIOR_LOG_ENABLED = director.WORLD_BEHAVIOR_LOG_ENABLED ~= false
    if not director.WORLD_BEHAVIOR_LOG_FILE or director.WORLD_BEHAVIOR_LOG_FILE == "" then director.WORLD_BEHAVIOR_LOG_FILE = "NPC_FACTIONS.log" end
    director.FACTION_BALANCE_LOG_FILE = director.WORLD_BEHAVIOR_LOG_FILE
    director.WORLD_BEHAVIOR_SNAPSHOT_HOURS = director.WORLD_BEHAVIOR_SNAPSHOT_HOURS or 0.50
    director.BATTLE_REMAINS_MATERIALIZE_ENABLED = true
    director.BATTLE_REMAINS_PROP_ONLY = true
    director.BATTLE_REMAINS_ACTIVATION_RADIUS = 70
    director.BATTLE_REMAINS_MAX_RECORDS = 12
    director.BATTLE_REMAINS_MAX_BODIES = 2
    director.BATTLE_REMAINS_MAX_DEBRIS = 8
    director.BATTLE_REMAINS_MIN_SPACING = 96
    director.BATTLE_REMAINS_DECAY_HOURS = 24 * 2
    director.BATTLEFIELD_CLEANUP_ENABLED = true
    director.BATTLEFIELD_CLEANUP_RADIUS = 42
    director.BATTLEFIELD_CLEANUP_CORPSE_SOFT_CAP = 18
    director.BATTLEFIELD_CLEANUP_DEBRIS_SOFT_CAP = 24
    director.BATTLEFIELD_CLEANUP_INTERVAL_TICKS = 900
    director.BATTLEFIELD_CLEANUP_MAX_REMOVE_PER_RUN = 48
    director.URBAN_COVER_PROPS_ENABLED = true
    director.URBAN_COVER_PROPS_RADIUS = 58
    director.URBAN_COVER_PROPS_INTERVAL_TICKS = 900
    director.URBAN_COVER_PROPS_MAX_CLUSTERS_PER_RUN = 2
    director.URBAN_COVER_PROPS_MAX_RECORDS = 120
    director.URBAN_COVER_PROPS_MIN_SPACING = 18
    director.URBAN_COVER_PROPS_BUILDING_RADIUS = 7
    director.URBAN_COVER_PROPS_ATTEMPTS_PER_PLAYER = 34
    director.URBAN_COVER_PROPS_MAX_ITEMS_PER_CLUSTER = 4
    director.URBAN_GROUP_EARLY_SCORE = 150
    director.URBAN_GROUP_ACCEPT_SCORE = 120
    director.URBAN_GROUP_ROAD_BIAS_RADIUS = 220
    director.URBAN_GROUP_MIN_AFFINITY = 145
    director.ROAD_PATROL_URBAN_BIAS_RADIUS = 260
    director.ROAD_PATROL_MIN_URBAN_AFFINITY = 150
    director.ROAD_PATROL_ACCEPT_SCORE = 220
    director.ROAD_PATROL_EARLY_SCORE = 245
    director._tick = director._tick or 0
    director._startupRuntimeRevirtualized = director._startupRuntimeRevirtualized or false
    director.SINGLEPLAYER_BOOTSTRAP_GROUPS_PER_STEP = director.SINGLEPLAYER_BOOTSTRAP_GROUPS_PER_STEP or 4
    director.SINGLEPLAYER_BOOTSTRAP_ROAD_PATROLS_PER_STEP = director.SINGLEPLAYER_BOOTSTRAP_ROAD_PATROLS_PER_STEP or 4
    director.SINGLEPLAYER_BOOTSTRAP_TICK_INTERVAL = director.SINGLEPLAYER_BOOTSTRAP_TICK_INTERVAL or 45
    director.SINGLEPLAYER_ACTIVATION_TICK_INTERVAL = director.SINGLEPLAYER_ACTIVATION_TICK_INTERVAL or 120
    director.SINGLEPLAYER_WORLD_UPDATE_GROUP_BUDGET = director.SINGLEPLAYER_WORLD_UPDATE_GROUP_BUDGET or 18
    director.SINGLEPLAYER_MAP_SYNC_GROUP_BUDGET = director.SINGLEPLAYER_MAP_SYNC_GROUP_BUDGET or 90
    director.SERVER_BOOTSTRAP_GROUPS_PER_STEP = director.SERVER_BOOTSTRAP_GROUPS_PER_STEP or 6
    director.SERVER_BOOTSTRAP_ROAD_PATROLS_PER_STEP = director.SERVER_BOOTSTRAP_ROAD_PATROLS_PER_STEP or 4
    director.SERVER_BOOTSTRAP_TICK_INTERVAL = director.SERVER_BOOTSTRAP_TICK_INTERVAL or 30
    director.SERVER_WORLD_UPDATE_GROUP_BUDGET = director.SERVER_WORLD_UPDATE_GROUP_BUDGET or 36
    director.SERVER_MAP_SYNC_GROUP_BUDGET = director.SERVER_MAP_SYNC_GROUP_BUDGET or 120

    -- Stage 411: keep long-term world persistence strategic and cheap. Bases stay
    -- fully persistent through their own systems; distant world groups are stored
    -- as compact summaries, while physical groups around online players are
    -- snapshotted so they can be restored after a stop/start without replaying the
    -- entire global map runtime.
    director.PERSISTENCE_COMPACT_VIRTUAL_GROUPS = director.PERSISTENCE_COMPACT_VIRTUAL_GROUPS ~= false
    director.PERSISTENCE_COMPACT_INTERVAL_TICKS = director.PERSISTENCE_COMPACT_INTERVAL_TICKS or 900
    director.PERSISTENCE_COMPACT_GROUPS_PER_RUN = director.PERSISTENCE_COMPACT_GROUPS_PER_RUN or 32
    director.PERSISTENCE_PHYSICAL_BUBBLE_ENABLED = director.PERSISTENCE_PHYSICAL_BUBBLE_ENABLED ~= false
    director.PERSISTENCE_PHYSICAL_BUBBLE_RADIUS = director.PERSISTENCE_PHYSICAL_BUBBLE_RADIUS or 170
    director.PERSISTENCE_PHYSICAL_BUBBLE_MAX_GROUPS = director.PERSISTENCE_PHYSICAL_BUBBLE_MAX_GROUPS or 8
    director.PERSISTENCE_PHYSICAL_BUBBLE_INTERVAL_TICKS = director.PERSISTENCE_PHYSICAL_BUBBLE_INTERVAL_TICKS or 300
    director.PERSISTENCE_RESTORE_BUBBLE_RADIUS = director.PERSISTENCE_RESTORE_BUBBLE_RADIUS or 220
    director.PERSISTENCE_RESTORE_MAX_GROUPS_PER_RUN = director.PERSISTENCE_RESTORE_MAX_GROUPS_PER_RUN or 1

    director.DEBUG_LOG = director.DEBUG_LOG or false

    director.MERCENARY_FOLLOW_LEASH_ENABLED = director.MERCENARY_FOLLOW_LEASH_ENABLED ~= false
    director.MERCENARY_FOLLOW_LEASH_INTERVAL_TICKS = director.MERCENARY_FOLLOW_LEASH_INTERVAL_TICKS or 30
    director.MERCENARY_FOLLOW_TELEPORT_DISTANCE = director.MERCENARY_FOLLOW_TELEPORT_DISTANCE or 44
    director.MERCENARY_FOLLOW_VIRTUAL_TELEPORT_DISTANCE = director.MERCENARY_FOLLOW_VIRTUAL_TELEPORT_DISTANCE or 56
    director.MERCENARY_FOLLOW_PLAYER_TELEPORT_DISTANCE = director.MERCENARY_FOLLOW_PLAYER_TELEPORT_DISTANCE or 72
    director.MERCENARY_FOLLOW_HARD_RESTORE_DISTANCE = director.MERCENARY_FOLLOW_HARD_RESTORE_DISTANCE or 140
    director.MERCENARY_FOLLOW_CLOSE_RADIUS = director.MERCENARY_FOLLOW_CLOSE_RADIUS or 8
    director.MERCENARY_FOLLOW_HIRE_GRACE_SECONDS = director.MERCENARY_FOLLOW_HIRE_GRACE_SECONDS or 8
    director.MERCENARY_FOLLOW_LOADED_COUNT_CACHE_SECONDS = director.MERCENARY_FOLLOW_LOADED_COUNT_CACHE_SECONDS or 2
end

function NPCWorldDirectorBridge.LegacyFactionProfilesEnabled(_director)
    return false
end

function NPCWorldDirectorBridge.GenericProfile(_director)
    return {
        enabled = true,
        enemyBehaviour = 1,
        firstDay = 0,
        lastDay = 99999,
        spawnHourlyChance = 0,
        groupSize = 3,
        clanId = 1,
        hasPistolChance = 20,
        pistolMagCount = 2,
        hasRifleChance = 5,
        rifleMagCount = 1
    }
end

function NPCWorldDirectorBridge.IsDebugEnabled(director)
    return type(director) == "table" and director.DEBUG_LOG == true
end

function NPCWorldDirectorBridge.Log(director, message)
    if NPCWorldDirectorBridge.IsDebugEnabled(director) then
        print(message)
    end
end

local function wd_behaviorValue(value)
    if value == nil then return "nil" end
    local s = tostring(value)
    s = string.gsub(s, "[\r\n|]", " ")
    if string.len(s) > 96 then s = string.sub(s, 1, 96) end
    return s
end

local function wd_behaviorNow()
    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then
            local ok, value = pcall(function() return gt:getWorldAgeHours() end)
            if ok and value then return tonumber(value) or 0 end
        end
    end
    return 0
end

local function wd_factionLogFileName(director)
    local fileName = type(director) == "table" and director.WORLD_BEHAVIOR_LOG_FILE or nil
    if not fileName or fileName == "" then
        fileName = "NPC_FACTIONS.log"
    end
    return fileName
end

local function wd_factionContextSide(group)
    if type(group) ~= "table" then return nil end
    if group.mercenary == true and group.mercenaryHired ~= true then return "blue" end
    local side = group.side or group.factionSide or group.patrolColor
    if side == "red" or side == "green" or side == "blue" then return side end
    if group.hostile == true then return "red" end
    return "green"
end

local function wd_collectFactionLogContext(director, now)
    if not GetNPCModData then return nil end
    now = tonumber(now) or wd_behaviorNow()
    if type(director) == "table" and type(director._factionLogContext) == "table" and now - (tonumber(director._factionLogContextAt) or -999) < 0.05 then
        return director._factionLogContext
    end

    local gmd = GetNPCModData()
    if type(gmd) ~= "table" then return nil end
    local ctx = {
        redGroups = 0, greenGroups = 0, blueGroups = 0,
        redMembers = 0, greenMembers = 0, blueMembers = 0,
        redBases = 0, greenBases = 0, neutralBases = 0,
        attack = 0, siege = 0, assemble = 0, defend = 0, reinforce = 0,
        retreat = 0, scout = 0, patrol = 0, ambush = 0,
        roadBattles = 0, blueHireable = 0
    }

    for _, group in pairs(gmd.VirtualGroups or {}) do
        if type(group) == "table" then
            local side = wd_factionContextSide(group)
            local count = tonumber(group.count) or (type(group.members) == "table" and #group.members) or 0
            if side == "red" then
                ctx.redGroups = ctx.redGroups + 1
                ctx.redMembers = ctx.redMembers + count
            elseif side == "blue" then
                ctx.blueGroups = ctx.blueGroups + 1
                ctx.blueMembers = ctx.blueMembers + count
            else
                ctx.greenGroups = ctx.greenGroups + 1
                ctx.greenMembers = ctx.greenMembers + count
            end
            if group.mercenary == true and group.mercenaryHired ~= true and (group.hireable == true or group.recruitable == true) then ctx.blueHireable = ctx.blueHireable + 1 end
            local act = tostring(group.strategicActivityType or group.state or "")
            if act == "AttackBase" or act == "activity_attack" then ctx.attack = ctx.attack + 1 end
            if act == "SiegeBase" or act == "activity_siege" then ctx.siege = ctx.siege + 1 end
            if act == "AssembleStrike" or act == "activity_assemble_strike" then ctx.assemble = ctx.assemble + 1 end
            if act == "DefendBase" or act == "activity_defend" then ctx.defend = ctx.defend + 1 end
            if act == "ReinforceBase" or act == "activity_reinforce" then ctx.reinforce = ctx.reinforce + 1 end
            if act == "RetreatToBase" or act == "activity_retreat" then ctx.retreat = ctx.retreat + 1 end
            if act == "ScoutFront" or act == "activity_scout" then ctx.scout = ctx.scout + 1 end
            if act == "Patrol" or act == "roaming" then ctx.patrol = ctx.patrol + 1 end
            if act == "AmbushRoad" or act == "activity_ambush" or group.roadPatrol == true then ctx.ambush = ctx.ambush + 1 end
            if group.inBattle then ctx.roadBattles = ctx.roadBattles + 1 end
        end
    end

    for _, base in pairs(gmd.BaseCamps or {}) do
        if type(base) == "table" then
            if base.owner == "red" then ctx.redBases = ctx.redBases + 1
            elseif base.owner == "green" then ctx.greenBases = ctx.greenBases + 1
            else ctx.neutralBases = ctx.neutralBases + 1 end
        end
    end

    local logistics = gmd.WorldDirector and gmd.WorldDirector.sideLogistics or nil
    if type(logistics) == "table" then
        if type(logistics.red) == "table" then
            ctx.redSupply = logistics.red.supply
            ctx.redAmmo = logistics.red.ammo
            ctx.redMorale = logistics.red.morale
            ctx.redPressure = logistics.red.pressure
            ctx.redLosses = logistics.red.losses
        end
        if type(logistics.green) == "table" then
            ctx.greenSupply = logistics.green.supply
            ctx.greenAmmo = logistics.green.ammo
            ctx.greenMorale = logistics.green.morale
            ctx.greenPressure = logistics.green.pressure
            ctx.greenLosses = logistics.green.losses
        end
    end
    local war = gmd.WorldDirector and gmd.WorldDirector.strategicWar or nil
    if type(war) == "table" and type(war.front) == "table" then
        ctx.frontX = war.front.x
        ctx.frontY = war.front.y
    end

    if type(director) == "table" then
        director._factionLogContext = ctx
        director._factionLogContextAt = now
    end
    return ctx
end

function NPCWorldDirectorBridge.BehaviorLog(director, eventName, fields)
    if type(director) == "table" and director.WORLD_BEHAVIOR_LOG_ENABLED == false then return false end
    if not getFileWriter then return false end

    local parts = {
        "t=" .. wd_behaviorValue(string.format("%.3f", wd_behaviorNow())),
        "event=" .. wd_behaviorValue(eventName or "unknown")
    }
    local merged = {}
    local ctx = wd_collectFactionLogContext(director, wd_behaviorNow())
    if type(ctx) == "table" then
        for key, value in pairs(ctx) do merged[key] = value end
    end
    if type(fields) == "table" then
        for key, value in pairs(fields) do merged[key] = value end
    end
    local keys = {}
    for key, _ in pairs(merged) do table.insert(keys, tostring(key)) end
    table.sort(keys)
    for _, key in ipairs(keys) do
        parts[#parts + 1] = key .. "=" .. wd_behaviorValue(merged[key])
    end

    if NPCDiagnosticsBridge and NPCDiagnosticsBridge.Log then
        local data = {event = eventName or "unknown"}
        for key, value in pairs(merged) do data[key] = value end
        local force = eventName == "base_owner_changed" or eventName == "spawn_failed" or eventName == "runtime_reconcile_error"
        return NPCDiagnosticsBridge.Log("WORLD_BEHAVIOR", tostring(eventName or "unknown"), data, "world-behavior:" .. tostring(eventName or "unknown"), force) ~= false
    end

    local fileName = wd_factionLogFileName(director)
    local ok = pcall(function()
        local writer = getFileWriter(fileName, true, true)
        if writer then
            writer:write("[NPCDiag] | [SERVER] | [WORLD_BEHAVIOR] | " .. table.concat(parts, " | ") .. "\n")
            writer:close()
        end
    end)
    return ok == true
end

function NPCWorldDirectorBridge.GetDirectorBrain()
    return NPCDirectorBrainServerBridge or NPCDirectorBrainServer
end

function NPCWorldDirectorBridge.DirectorEvent(director, kind, x, y, z, meta)
    kind = tostring(kind or "")
    if npc_wd_shouldBootstrapGate and npc_wd_isSinglePlayerRuntime() then
        local lowerKind = string.lower(kind)
        local optional = string.find(lowerKind, "virtual", 1, true) or string.find(lowerKind, "road_battle", 1, true) or string.find(lowerKind, "battle_remains", 1, true) or string.find(lowerKind, "strategic", 1, true) or string.find(lowerKind, "base_", 1, true)
        if optional then
            local gate, retry, reason = npc_wd_shouldBootstrapGate(director, "director_event:" .. kind)
            if gate then npc_wd_recordBootstrapGate("director_event:" .. kind, retry, reason); return end
        end
    end
    local directorBrain = NPCWorldDirectorBridge.GetDirectorBrain()
    if not (directorBrain and directorBrain.PushEvent) then return end

    local ok, err = pcall(function()
        directorBrain.PushEvent(kind, x, y, z, meta)
    end)
    if not ok and NPCWorldDirectorBridge.IsDebugEnabled(director) then
        print(NPC_WORLD_DIRECTOR_LOG_PREFIX .. " Director event failed: " .. tostring(err))
    end
end

function NPCWorldDirectorBridge.DirectorOutcomeStart(director, kind, group, meta)
    local directorBrain = NPCWorldDirectorBridge.GetDirectorBrain()
    if not (directorBrain and directorBrain.RecordOutcomeStart) then return nil end

    local ok, result = pcall(function()
        return directorBrain.RecordOutcomeStart(kind, group, meta)
    end)
    if not ok and NPCWorldDirectorBridge.IsDebugEnabled(director) then
        print(NPC_WORLD_DIRECTOR_LOG_PREFIX .. " Director outcome start failed: " .. tostring(result))
    end
    if ok then return result end
    return nil
end

function NPCWorldDirectorBridge.DirectorOutcomeEnd(director, groupId, reason, group)
    local directorBrain = NPCWorldDirectorBridge.GetDirectorBrain()
    if not (directorBrain and directorBrain.RecordOutcomeEnd) then return end

    local ok, err = pcall(function()
        directorBrain.RecordOutcomeEnd(groupId, reason, group)
    end)
    if not ok and NPCWorldDirectorBridge.IsDebugEnabled(director) then
        print(NPC_WORLD_DIRECTOR_LOG_PREFIX .. " Director outcome end failed: " .. tostring(err))
    end
end

function NPCWorldDirectorBridge.DirectorPointBias(director, x, y, context)
    local directorBrain = NPCWorldDirectorBridge.GetDirectorBrain()
    if not (directorBrain and directorBrain.GetPointMemoryBias) then return 0, nil end

    local ok, bias, reason = pcall(function()
        return directorBrain.GetPointMemoryBias(x, y, context)
    end)
    if ok then return tonumber(bias) or 0, reason end
    if NPCWorldDirectorBridge.IsDebugEnabled(director) then
        print(NPC_WORLD_DIRECTOR_LOG_PREFIX .. " Director point bias failed: " .. tostring(bias))
    end
    return 0, nil
end

function NPCWorldDirectorBridge.DirectorRetargetAnchor(director, group, context)
    local directorBrain = NPCWorldDirectorBridge.GetDirectorBrain()
    if not (directorBrain and directorBrain.GetRetargetAnchor) then return nil end

    local ok, anchor = pcall(function()
        return directorBrain.GetRetargetAnchor(group, context)
    end)
    if ok then return anchor end
    if NPCWorldDirectorBridge.IsDebugEnabled(director) then
        print(NPC_WORLD_DIRECTOR_LOG_PREFIX .. " Director retarget failed: " .. tostring(anchor))
    end
    return nil
end

function NPCWorldDirectorBridge.DirectorRetargetBudget(_director)
    local directorBrain = NPCWorldDirectorBridge.GetDirectorBrain()
    if not (directorBrain and directorBrain.GetRetargetMaxGroupsPerUpdate) then return 0 end

    local ok, value = pcall(function()
        return directorBrain.GetRetargetMaxGroupsPerUpdate()
    end)
    if ok then return tonumber(value) or 0 end
    return 0
end

function NPCWorldDirectorBridge.DirectorCellCooldown(director, kind, x, y, z, meta)
    local directorBrain = NPCWorldDirectorBridge.GetDirectorBrain()
    if not (directorBrain and directorBrain.MarkCellCooldown) then return end

    local ok, err = pcall(function()
        directorBrain.MarkCellCooldown(kind, x, y, z, meta)
    end)
    if not ok and NPCWorldDirectorBridge.IsDebugEnabled(director) then
        print(NPC_WORLD_DIRECTOR_LOG_PREFIX .. " Director cell cooldown failed: " .. tostring(err))
    end
end

function NPCWorldDirectorBridge.SendDebugMap(command, args)
    if NPCNetContract and NPCNetContract.SendDebugMap then
        NPCNetContract.SendDebugMap(command, args)
        return
    end
    if sendServerCommand then
        sendServerCommand('NPCDebugMap', command, args or {})
    end
end


NPCWorldDirectorBridge.DebugMapDirtySync = NPCWorldDirectorBridge.DebugMapDirtySync or {
    enabled = true,
    minIntervalMs = 1200,
    forceIntervalMs = 12000,
    sent = {},
    stats = {sent=0, skipped=0, forced=0}
}

local function npc_wd_markerSignature(marker)
    if type(marker) ~= "table" then return "" end
    local x = math.floor((tonumber(marker.x) or 0) * 2 + 0.5) / 2
    local y = math.floor((tonumber(marker.y) or 0) * 2 + 0.5) / 2
    local parts = {
        tostring(marker.id or marker.uid or marker.groupId or ""),
        tostring(marker.markerType or marker.type or ""),
        tostring(marker.faction or marker.side or marker.owner or ""),
        tostring(x), tostring(y), tostring(marker.z or 0),
        tostring(marker.state or marker.status or marker.activity or ""),
        tostring(marker.active == true), tostring(marker.virtual == true), tostring(marker.dead == true),
        tostring(marker.inBattle == true), tostring(marker.leader == true), tostring(marker.isFactionLeader == true),
        tostring(marker.count or marker.size or marker.power or ""),
        tostring(marker.baseId or ""), tostring(marker.convoyId or ""), tostring(marker.checkpointId or "")
    }
    return table.concat(parts, "|")
end

local function npc_wd_nowMs()
    if getTimestampMs then
        local ok, value = pcall(function() return getTimestampMs() end)
        if ok and tonumber(value) then return tonumber(value) end
    end
    if getTimestamp then
        local ok, value = pcall(function() return getTimestamp() end)
        if ok and tonumber(value) then return tonumber(value) * 1000 end
    end
    if getGameTime and getGameTime() then
        local ok, hours = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok and tonumber(hours) then return tonumber(hours) * 3600000 end
    end
    return 0
end

local function npc_wd_shouldSendDebugMarker(marker)
    local cfg = NPCWorldDirectorBridge.DebugMapDirtySync
    if not (cfg and cfg.enabled) then return true end
    if type(marker) ~= "table" then return true end
    local id = tostring(marker.id or marker.uid or marker.groupId or "")
    if id == "" then return true end
    local now = npc_wd_nowMs()
    local sig = npc_wd_markerSignature(marker)
    local prev = cfg.sent[id]
    local minMs = tonumber(cfg.minIntervalMs) or 1200
    local forceMs = tonumber(cfg.forceIntervalMs) or 12000
    if prev and prev.sig == sig and now - (tonumber(prev.t) or 0) < forceMs then
        if now - (tonumber(prev.lastSkip) or 0) >= minMs then
            prev.lastSkip = now
        end
        cfg.stats.skipped = (tonumber(cfg.stats.skipped) or 0) + 1
        return false
    end
    cfg.sent[id] = {sig=sig, t=now}
    if prev and prev.sig == sig then cfg.stats.forced = (tonumber(cfg.stats.forced) or 0) + 1 end
    cfg.stats.sent = (tonumber(cfg.stats.sent) or 0) + 1
    return true
end

function NPCWorldDirectorBridge.GetDebugMapDirtySyncDiagnostics(reset)
    local cfg = NPCWorldDirectorBridge.DebugMapDirtySync or {}
    local stats = {}
    for k, v in pairs(cfg.stats or {}) do stats[k] = v end
    local tracked = 0
    for _, _ in pairs(cfg.sent or {}) do tracked = tracked + 1 end
    local out = {enabled = cfg.enabled, tracked = tracked, stats = stats}
    if reset == true then cfg.stats = {sent=0, skipped=0, forced=0} end
    return out
end

local function npc_wd_isCriticalDebugMarker(marker)
    if type(marker) ~= "table" then return false end
    return marker.mercenary == true or marker.mercenaryHired == true or marker.isPlayerGuard == true
        or marker.blackMarket == true or marker.blackMarketNPC == true or marker.contract == true
        or marker.playerOrder == true or marker.followPlayer == true or marker.guardPlayer == true
end

local function npc_wd_shouldThrottleDebugMarkerUpdate(marker)
    if npc_wd_isCriticalDebugMarker(marker) then return false end
    if not NPCStreamingRuntimeBridge then return false end
    local markerType = type(marker) == "table" and tostring(marker.markerType or marker.type or "marker") or "marker"
    local label = "debug_marker_update:" .. markerType
    if NPCStreamingRuntimeBridge.ShouldDropRuntimeTask then
        local okDrop, drop = pcall(function() return NPCStreamingRuntimeBridge.ShouldDropRuntimeTask(label, "normal") end)
        if okDrop and drop == true then return true end
    end
    if NPCStreamingRuntimeBridge.AllowRuntimeTaskNow then
        local okAllow, allow = pcall(function() return NPCStreamingRuntimeBridge.AllowRuntimeTaskNow(label, "normal") end)
        if okAllow and allow == false then return true end
    end
    return false
end

function NPCWorldDirectorBridge.SendDebugMapUpdate(marker)
    if not marker then return end
    if npc_wd_shouldThrottleDebugMarkerUpdate(marker) then return end
    if not npc_wd_shouldSendDebugMarker(marker) then return end
    if NPCNetContract and NPCNetContract.SendDebugMapUpdate then
        NPCNetContract.SendDebugMapUpdate(marker)
        return
    end
    if sendServerCommand then
        sendServerCommand('NPCDebugMap', 'Update', marker)
    end
end

function NPCWorldDirectorBridge.SendDebugMapRemove(id)
    if not id then return end
    if NPCWorldDirectorBridge.DebugMapDirtySync and NPCWorldDirectorBridge.DebugMapDirtySync.sent then
        NPCWorldDirectorBridge.DebugMapDirtySync.sent[tostring(id)] = nil
    end
    if NPCNetContract and NPCNetContract.SendDebugMapRemove then
        NPCNetContract.SendDebugMapRemove(id)
        return
    end
    if sendServerCommand then
        sendServerCommand('NPCDebugMap', 'Remove', {id=tostring(id)})
    end
end

function NPCWorldDirectorBridge.ReconcileDebugMarkers(gmd, reason, maxMarkers)
    if not (gmd and NPCMarkerReconciliationBridge and NPCMarkerReconciliationBridge.ReconcileServerMarkers) then return 0 end
    local ok, changed = pcall(function()
        return NPCMarkerReconciliationBridge.ReconcileServerMarkers(gmd, {
            reason = tostring(reason or "world_director"),
            maxMarkers = maxMarkers or 160,
            sendRemove = function(id) NPCWorldDirectorBridge.SendDebugMapRemove(id) end,
            sendUpdate = function(marker) NPCWorldDirectorBridge.SendDebugMapUpdate(marker) end
        })
    end)
    if ok then return tonumber(changed) or 0 end
    return 0
end

function NPCWorldDirectorBridge.NpcMarkerId(id)
    if id == nil then return nil end
    local sid = tostring(id)
    if sid == "" or sid == "nil" then return nil end
    if string.sub(sid, 1, 4) == "npc:" then return sid end
    return "npc:" .. sid
end

function NPCWorldDirectorBridge.IsNpcMarker(marker)
    return type(marker) == "table" and tostring(marker.markerType or "") == "npc"
end

function NPCWorldDirectorBridge.BrainGroupId(brain)
    if not brain then return nil end
    return brain.worldGroupId or brain.groupId
end

function NPCWorldDirectorBridge.RemoveMarkerById(gmd, id, expectedType)
    if not (gmd and gmd.DebugMapMarkers and id) then return false end

    local sid = tostring(id)
    local marker = gmd.DebugMapMarkers[sid]
    if expectedType and tostring(marker and marker.markerType or "") ~= tostring(expectedType) then return false end

    gmd.DebugMapMarkers[sid] = nil
    NPCWorldDirectorBridge.SendDebugMapRemove(sid)
    return true
end


function NPCWorldDirectorBridge.RemoveNpcMarkerForRuntime(gmd, runtimeId)
    if not (gmd and gmd.DebugMapMarkers and runtimeId) then return false end

    local removed = false
    local npcId = NPCWorldDirectorBridge.NpcMarkerId(runtimeId)
    if npcId and NPCWorldDirectorBridge.IsNpcMarker(gmd.DebugMapMarkers[npcId]) then
        removed = NPCWorldDirectorBridge.RemoveMarkerById(gmd, npcId, "npc") or removed
    end

    local legacyId = tostring(runtimeId)
    if legacyId ~= tostring(npcId or "") and NPCWorldDirectorBridge.IsNpcMarker(gmd.DebugMapMarkers[legacyId]) then
        removed = NPCWorldDirectorBridge.RemoveMarkerById(gmd, legacyId, "npc") or removed
    end

    return removed
end

function NPCWorldDirectorBridge.RemoveNpcMarkersForGroup(gmd, groupId)
    if not (gmd and gmd.DebugMapMarkers and groupId) then return false end

    groupId = tostring(groupId)
    local removeIds = {}
    for id, marker in pairs(gmd.DebugMapMarkers) do
        if NPCWorldDirectorBridge.IsNpcMarker(marker) and tostring(marker.worldGroupId or marker.groupId or "") == groupId then
            removeIds[#removeIds + 1] = tostring(id)
        end
    end

    for _, id in ipairs(removeIds) do
        NPCWorldDirectorBridge.RemoveMarkerById(gmd, id, "npc")
    end

    return #removeIds > 0
end

function NPCWorldDirectorBridge.RevirtualizePersistentGroup(director, gmd, groupId, reason)
    if not (gmd and groupId and gmd.VirtualGroups) then return false end

    groupId = tostring(groupId)
    local group = gmd.VirtualGroups[groupId]
    if type(group) ~= "table" then return false end

    if NPCPersistentNPCBridge and NPCPersistentNPCBridge.RestoreGroupMembers then
        NPCPersistentNPCBridge.RestoreGroupMembers(gmd, group)
    end

    if type(group.members) ~= "table" or #group.members <= 0 then return false end

    local worldAge = getGameTime and getGameTime():getWorldAgeHours() or 0
    group.count = #group.members
    group.activated = false
    group.virtual = true
    group.physicalIds = nil
    group.spawnPending = false
    group.spawnQueued = 0
    group.spawnFailed = false
    group.retryAfter = nil
    group.lastSpawnFailReason = nil
    if group.roadPatrol then
        group.state = group.hostile and "red_road_patrol" or "green_road_patrol"
    else
        group.state = group.homeBaseId and "base_patrol" or "roaming"
    end
    group.updatedAt = worldAge
    gmd.VirtualGroups[groupId] = group

    if NPCPersistentNPCBridge and NPCPersistentNPCBridge.RegisterGroup then
        NPCPersistentNPCBridge.RegisterGroup(gmd, group)
    end

    NPCWorldDirectorBridge.RemoveNpcMarkersForGroup(gmd, groupId)
    if director and director.UpdateGroupDebugMarker then
        director.UpdateGroupDebugMarker(groupId, group)
    end
    NPCWorldDirectorBridge.Log(director, NPC_WORLD_DIRECTOR_LOG_PREFIX .. " Revirtualized persistent group " .. tostring(groupId) .. " reason=" .. tostring(reason or "runtime_cleanup"))
    return true
end

function NPCWorldDirectorBridge.IdSet(ids)
    local set = {}
    if type(ids) == "table" then
        for _, id in pairs(ids) do
            if id ~= nil then set[tostring(id)] = true end
        end
    elseif ids ~= nil then
        set[tostring(ids)] = true
    end
    return set
end

function NPCWorldDirectorBridge.NearPoint(zombie, args)
    if not zombie then return false end
    args = args or {}
    local x = tonumber(args.x)
    local y = tonumber(args.y)
    if not x or not y then return true end

    local radius = tonumber(args.radius) or 48
    if radius <= 0 then return true end

    local zx = zombie.getX and zombie:getX() or x
    local zy = zombie.getY and zombie:getY() or y
    local dx = zx - x
    local dy = zy - y
    return (dx * dx + dy * dy) <= (radius * radius)
end

function NPCWorldDirectorBridge.GetZombieRuntimeId(zombie)
    if not (zombie and NPCUtils and NPCUtils.GetCharacterID) then return nil end

    local ok, id = pcall(function() return NPCUtils.GetCharacterID(zombie) end)
    if ok then return id end

    return nil
end

function NPCWorldDirectorBridge.NonEmpty(value)
    if value == nil then return nil end
    local text = tostring(value)
    if text == "" or text == "nil" or text == "false" then return nil end
    return text
end

function NPCWorldDirectorBridge.GetZombieServiceId(zombie, mdKey, variableName)
    if not zombie then return nil end

    local md = zombie.getModData and zombie:getModData() or nil
    local value = md and md[mdKey] or nil
    value = NPCWorldDirectorBridge.NonEmpty(value)
    if value then return value end

    if zombie.getVariableString then
        local ok, var = pcall(function() return zombie:getVariableString(variableName) end)
        if ok then return NPCWorldDirectorBridge.NonEmpty(var) end
    end

    return nil
end

function NPCWorldDirectorBridge.GetQueuedRuntimeBrain(gmd, runtimeId, persistentId)
    if not (gmd and type(gmd.Queue) == "table") then return nil, nil end

    if runtimeId ~= nil then
        local brain = gmd.Queue[runtimeId] or gmd.Queue[tostring(runtimeId)]
        local numericId = tonumber(runtimeId)
        if not brain and numericId then brain = gmd.Queue[numericId] end
        if type(brain) == "table" then return brain, runtimeId end
    end

    if persistentId ~= nil then
        local wanted = tostring(persistentId)
        for queueId, brain in pairs(gmd.Queue) do
            if type(brain) == "table" then
                local brainPersistentId = brain.persistentId or brain.uid
                if brainPersistentId and tostring(brainPersistentId) == wanted then
                    return brain, queueId
                end
            end
        end
    end

    return nil, nil
end

function NPCWorldDirectorBridge.SetHasEntries(set)
    if type(set) ~= "table" then return false end
    for _, _ in pairs(set) do return true end
    return false
end

function NPCWorldDirectorBridge.IsCleanupFormerNPCZombie(zombie)
    if not zombie then return false end

    if NPCZombieLifecycleClassifierBridge and NPCZombieLifecycleClassifierBridge.ShouldCleanupAsFormerNPC then
        local ok, cleanup = pcall(function() return NPCZombieLifecycleClassifierBridge.ShouldCleanupAsFormerNPC(zombie) end)
        if ok then return cleanup == true end
    end

    local md = zombie.getModData and zombie:getModData() or nil
    if md and md[NPC_WORLD_DIRECTOR_LEGACY_KEYS.formerNPCZombie] then return true end

    if zombie.getVariableBoolean then
        local okFormer, former = pcall(function() return zombie:getVariableBoolean(NPC_WORLD_DIRECTOR_LEGACY_KEYS.formerNPCZombie) end)
        if okFormer and former then return true end

        local okNPCFlag, isNPCFlag = pcall(function() return zombie:getVariableBoolean(NPC_WORLD_DIRECTOR_LEGACY_KEYS.liveFlag) end)
        if okNPCFlag and isNPCFlag then return false end
    end

    if NPCWorldDirectorBridge.GetZombieServiceId(zombie, NPC_WORLD_DIRECTOR_LEGACY_KEYS.runtimeId, NPC_WORLD_DIRECTOR_LEGACY_KEYS.runtimeId) then return true end
    if NPCWorldDirectorBridge.GetZombieServiceId(zombie, NPC_WORLD_DIRECTOR_LEGACY_KEYS.persistentId, NPC_WORLD_DIRECTOR_LEGACY_KEYS.persistentId) then return true end
    if NPCWorldDirectorBridge.GetZombieServiceId(zombie, NPC_WORLD_DIRECTOR_LEGACY_KEYS.worldGroupId, NPC_WORLD_DIRECTOR_LEGACY_KEYS.worldGroupId) then return true end

    return false
end

function NPCWorldDirectorBridge.IsStalePersistentRuntimeNPCZombie(zombie, gmd)
    if not zombie then return false end

    if NPCZombieLifecycleClassifierBridge and NPCZombieLifecycleClassifierBridge.Classify then
        local okClass, class = pcall(function() return NPCZombieLifecycleClassifierBridge.Classify(zombie) end)
        if okClass then
            if class == "ordinary_zombie" or class == "black_market" or class == "live_npc" or class == "wounded_npc" then return false end
        end
    end

    local md = zombie.getModData and zombie:getModData() or nil
    if md and (md.NPCBlackMarketBridge == true or md.BlackMarketNPC == true) then return false end
    if zombie.getVariableBoolean and NPC_WORLD_DIRECTOR_LEGACY_KEYS.blackMarket then
        local okBlack, black = pcall(function() return zombie:getVariableBoolean(NPC_WORLD_DIRECTOR_LEGACY_KEYS.blackMarket) end)
        if okBlack and black == true then return false end
    end

    local runtimeId = NPCWorldDirectorBridge.GetZombieRuntimeId(zombie)
    if runtimeId and gmd and type(gmd.Queue) == "table" then
        local sid = tostring(runtimeId)
        if gmd.Queue[runtimeId] or gmd.Queue[sid] or (tonumber(runtimeId) and gmd.Queue[tonumber(runtimeId)]) then return false end
    end

    local persistentId = NPCWorldDirectorBridge.GetZombieServiceId(zombie, NPC_WORLD_DIRECTOR_LEGACY_KEYS.persistentId, NPC_WORLD_DIRECTOR_LEGACY_KEYS.persistentId)
    local groupId = NPCWorldDirectorBridge.GetZombieServiceId(zombie, NPC_WORLD_DIRECTOR_LEGACY_KEYS.worldGroupId, NPC_WORLD_DIRECTOR_LEGACY_KEYS.worldGroupId)
    local program = NPCWorldDirectorBridge.GetZombieServiceId(zombie, NPC_WORLD_DIRECTOR_LEGACY_KEYS.program, NPC_WORLD_DIRECTOR_LEGACY_KEYS.program)
    local isNPC = md and md[NPC_WORLD_DIRECTOR_LEGACY_KEYS.isNPC] == true

    if not (persistentId or groupId or program or isNPC) then return false end
    if persistentId and gmd and type(gmd.PersistentNPCs) == "table" then
        local profile = gmd.PersistentNPCs[tostring(persistentId)]
        if type(profile) == "table" and profile.dead == true then return true end
    end
    return true
end

function NPCWorldDirectorBridge.WriteRecoveredNPCServiceIds(zombie, brain, groupId)
    if not (zombie and brain) then return false end

    local runtimeId = brain.id or brain.runtimeId
    local persistentId = brain.persistentId or brain.uid
    local programName = brain.program and brain.program.name or brain.programName
    local md = zombie.getModData and zombie:getModData() or nil
    if md then
        md[NPC_WORLD_DIRECTOR_LEGACY_KEYS.isNPC] = true
        md[NPC_WORLD_DIRECTOR_LEGACY_KEYS.formerNPCZombie] = false
        if runtimeId ~= nil then md[NPC_WORLD_DIRECTOR_LEGACY_KEYS.runtimeId] = tostring(runtimeId) end
        if persistentId ~= nil then md[NPC_WORLD_DIRECTOR_LEGACY_KEYS.persistentId] = tostring(persistentId) end
        if groupId ~= nil then md[NPC_WORLD_DIRECTOR_LEGACY_KEYS.worldGroupId] = tostring(groupId) end
        if programName ~= nil then md[NPC_WORLD_DIRECTOR_LEGACY_KEYS.program] = tostring(programName) end
    end

    pcall(function() zombie:setVariable(NPC_WORLD_DIRECTOR_LEGACY_KEYS.liveFlag, true) end)
    pcall(function() zombie:setVariable(NPC_WORLD_DIRECTOR_LEGACY_KEYS.formerNPCZombie, false) end)
    if runtimeId ~= nil then pcall(function() zombie:setVariable(NPC_WORLD_DIRECTOR_LEGACY_KEYS.runtimeId, tostring(runtimeId)) end) end
    if persistentId ~= nil then pcall(function() zombie:setVariable(NPC_WORLD_DIRECTOR_LEGACY_KEYS.persistentId, tostring(persistentId)) end) end
    if groupId ~= nil then pcall(function() zombie:setVariable(NPC_WORLD_DIRECTOR_LEGACY_KEYS.worldGroupId, tostring(groupId)) end) end
    if programName ~= nil then pcall(function() zombie:setVariable(NPC_WORLD_DIRECTOR_LEGACY_KEYS.program, tostring(programName)) end) end
    pcall(function() zombie:setNoTeeth(false) end)
    pcall(function() zombie:setReanim(false) end)
    return true
end

function NPCWorldDirectorBridge.RecoverLoadedQueuedRuntimeObject(director, zombie, gmd)
    if not (director and zombie and gmd) then return false end

    local alreadyNPC = false
    if zombie.getVariableBoolean then
        local okNPC, value = pcall(function() return zombie:getVariableBoolean(NPC_WORLD_DIRECTOR_LEGACY_KEYS.liveFlag) end)
        alreadyNPC = okNPC and value == true
    end
    local md = zombie.getModData and zombie:getModData() or nil
    if alreadyNPC and md and md[NPC_WORLD_DIRECTOR_LEGACY_KEYS.isNPC] == true then return false end
    if md and md[NPC_WORLD_DIRECTOR_LEGACY_KEYS.formerNPCZombie] == true then return false end

    local runtimeId = NPCWorldDirectorBridge.GetZombieRuntimeId(zombie)
    local persistentId = NPCWorldDirectorBridge.GetZombieServiceId(zombie, NPC_WORLD_DIRECTOR_LEGACY_KEYS.persistentId, NPC_WORLD_DIRECTOR_LEGACY_KEYS.persistentId)
    local queuedBrain = nil
    local queueKey = nil
    queuedBrain, queueKey = NPCWorldDirectorBridge.GetQueuedRuntimeBrain(gmd, runtimeId, persistentId)
    if type(queuedBrain) ~= "table" then return false end

    local hasPersistentStamp = persistentId ~= nil or queuedBrain.persistentId ~= nil or queuedBrain.uid ~= nil or queuedBrain.worldGroupId ~= nil or queuedBrain.groupId ~= nil
    if not hasPersistentStamp then return false end

    local brain = queuedBrain
    runtimeId = runtimeId or brain.id or brain.runtimeId or queueKey
    if runtimeId == nil then return false end

    persistentId = persistentId or brain.persistentId or brain.uid
    local groupId = brain.worldGroupId or brain.groupId or NPCWorldDirectorBridge.GetZombieServiceId(zombie, NPC_WORLD_DIRECTOR_LEGACY_KEYS.worldGroupId, NPC_WORLD_DIRECTOR_LEGACY_KEYS.worldGroupId)

    brain.id = runtimeId
    brain.runtimeId = runtimeId
    brain.uid = brain.uid or persistentId
    brain.persistentId = brain.persistentId or brain.uid or persistentId
    brain.worldGroupId = brain.worldGroupId or brain.groupId or groupId
    brain.groupId = brain.groupId or brain.worldGroupId or groupId
    brain.program = type(brain.program) == "table" and brain.program or {name = brain.programName or "Looter", stage = brain.programStage or "Prepare"}
    brain.tasks = type(brain.tasks) == "table" and brain.tasks or {}
    brain.weapons = type(brain.weapons) == "table" and brain.weapons or {melee=false, primary={name=false, magSize=0, bulletsLeft=0, magCount=0}, secondary={name=false, magSize=0, bulletsLeft=0, magCount=0}}
    brain.restoredFromQueuedRuntime = true

    if NPCIdentityBridge and NPCIdentityBridge.EnsureBrain then
        local okIdentity, identityBrain = pcall(function() return NPCIdentityBridge.EnsureBrain(brain, gmd, runtimeId, true) end)
        if okIdentity and type(identityBrain) == "table" then brain = identityBrain end
    end
    if NPCPersistentNPCBridge and NPCPersistentNPCBridge.ApplyProfileToBrain then
        local okProfile, profileBrain = pcall(function() return NPCPersistentNPCBridge.ApplyProfileToBrain(gmd, brain, zombie, nil) end)
        if okProfile and type(profileBrain) == "table" then brain = profileBrain end
    end

    gmd.Queue = gmd.Queue or {}
    gmd.Queue[runtimeId] = brain
    if queueKey ~= nil then gmd.Queue[queueKey] = brain end
    if NPCIdentityBridge and NPCIdentityBridge.TouchRegistry then
        pcall(function() NPCIdentityBridge.TouchRegistry(gmd, brain, runtimeId) end)
    end

    groupId = brain.worldGroupId or brain.groupId or groupId
    if groupId and type(gmd.VirtualGroups) == "table" then
        local group = gmd.VirtualGroups[tostring(groupId)]
        if type(group) == "table" then
            group.physicalIds = group.physicalIds or {}
            local sid = tostring(runtimeId)
            local seen = false
            for _, existing in ipairs(group.physicalIds) do
                if tostring(existing) == sid then seen = true break end
            end
            if not seen then table.insert(group.physicalIds, sid) end
            group.activated = true
            group.virtual = false
            group.state = "physical"
            group.updatedAt = getGameTime and getGameTime():getWorldAgeHours() or group.updatedAt
            gmd.VirtualGroups[tostring(groupId)] = group
        end
    end

    NPCWorldDirectorBridge.WriteRecoveredNPCServiceIds(zombie, brain, groupId)
    if NPCIdentityReconciliationBridge and NPCIdentityReconciliationBridge.ReconcileRuntimeObject then
        local okRecon, reconciledBrain = pcall(function()
            return NPCIdentityReconciliationBridge.ReconcileRuntimeObject(gmd, zombie, brain, runtimeId, "server_queued_runtime_recover")
        end)
        if okRecon and type(reconciledBrain) == "table" then brain = reconciledBrain end
    end
    brain.infection = 0
    if zombie.setHealth and brain.health then pcall(function() zombie:setHealth(brain.health) end) end
    local md = zombie.getModData and zombie:getModData() or nil
    if md then md[NPC_WORLD_DIRECTOR_LEGACY_KEYS.formerNPCZombie] = false end
    if zombie.setVariable then
        pcall(function() zombie:setVariable(NPC_WORLD_DIRECTOR_LEGACY_KEYS.formerNPCZombie, false) end)
        pcall(function() zombie:setVariable("ZombieBiteDone", false) end)
    end
    return true
end

function NPCWorldDirectorBridge.RecoverLoadedPersistedRuntimeObject(director, zombie, gmd)
    if not (director and zombie and gmd) then return false end

    local runtimeId = NPCWorldDirectorBridge.GetZombieRuntimeId(zombie)
    local persistentId = NPCWorldDirectorBridge.GetZombieServiceId(zombie, NPC_WORLD_DIRECTOR_LEGACY_KEYS.persistentId, NPC_WORLD_DIRECTOR_LEGACY_KEYS.persistentId)
    if not (runtimeId and persistentId) then return false end

    local profile = nil
    if type(gmd.PersistentNPCs) == "table" then profile = gmd.PersistentNPCs[tostring(persistentId)] end
    if not profile and type(gmd.Registry) == "table" then profile = gmd.Registry[tostring(persistentId)] end
    if type(profile) ~= "table" or profile.dead == true then return false end

    local brain = NPCWorldDirectorBridge.Copy(profile) or {}
    brain.id = runtimeId
    brain.runtimeId = runtimeId
    brain.uid = brain.uid or persistentId
    brain.persistentId = brain.persistentId or brain.uid or persistentId
    brain.worldGroupId = brain.worldGroupId or brain.groupId or NPCWorldDirectorBridge.GetZombieServiceId(zombie, NPC_WORLD_DIRECTOR_LEGACY_KEYS.worldGroupId, NPC_WORLD_DIRECTOR_LEGACY_KEYS.worldGroupId)
    brain.groupId = brain.groupId or brain.worldGroupId
    brain.program = type(brain.program) == "table" and brain.program or {name = brain.programName or "Looter", stage = brain.programStage or "Prepare"}
    brain.tasks = type(brain.tasks) == "table" and brain.tasks or {}
    brain.weapons = type(brain.weapons) == "table" and brain.weapons or {melee=false, primary={name=false, magSize=0, bulletsLeft=0, magCount=0}, secondary={name=false, magSize=0, bulletsLeft=0, magCount=0}}
    brain.health = brain.health or profile.health or 3.0
    brain.maxHealth = brain.maxHealth or profile.maxHealth or brain.health
    brain.restoredFromPersistentRuntime = true

    if NPCIdentityBridge and NPCIdentityBridge.EnsureBrain then
        brain = NPCIdentityBridge.EnsureBrain(brain, gmd, runtimeId, true) or brain
    end
    if NPCPersistentNPCBridge and NPCPersistentNPCBridge.ApplyProfileToBrain then
        brain = NPCPersistentNPCBridge.ApplyProfileToBrain(gmd, brain, zombie, profile) or brain
    end

    gmd.Queue = gmd.Queue or {}
    gmd.Queue[runtimeId] = brain
    if NPCIdentityBridge and NPCIdentityBridge.TouchRegistry then
        pcall(function() NPCIdentityBridge.TouchRegistry(gmd, brain, runtimeId) end)
    end

    local groupId = brain.worldGroupId or brain.groupId
    if groupId and type(gmd.VirtualGroups) == "table" then
        local group = gmd.VirtualGroups[tostring(groupId)]
        if type(group) == "table" then
            group.physicalIds = group.physicalIds or {}
            local sid = tostring(runtimeId)
            local seen = false
            for _, existing in ipairs(group.physicalIds) do
                if tostring(existing) == sid then seen = true break end
            end
            if not seen then table.insert(group.physicalIds, sid) end
            group.activated = true
            group.virtual = false
            group.state = "physical"
            group.updatedAt = getGameTime and getGameTime():getWorldAgeHours() or group.updatedAt
            gmd.VirtualGroups[tostring(groupId)] = group
        end
    end

    NPCWorldDirectorBridge.WriteRecoveredNPCServiceIds(zombie, brain, groupId)
    if NPCIdentityReconciliationBridge and NPCIdentityReconciliationBridge.ReconcileRuntimeObject then
        local okRecon, reconciledBrain = pcall(function()
            return NPCIdentityReconciliationBridge.ReconcileRuntimeObject(gmd, zombie, brain, runtimeId, "server_persisted_runtime_recover")
        end)
        if okRecon and type(reconciledBrain) == "table" then brain = reconciledBrain end
    end
    brain.infection = 0
    if zombie.setHealth and brain.health then pcall(function() zombie:setHealth(brain.health) end) end
    local md = zombie.getModData and zombie:getModData() or nil
    if md then md[NPC_WORLD_DIRECTOR_LEGACY_KEYS.formerNPCZombie] = false end
    if zombie.setVariable then
        pcall(function() zombie:setVariable(NPC_WORLD_DIRECTOR_LEGACY_KEYS.formerNPCZombie, false) end)
        pcall(function() zombie:setVariable("ZombieBiteDone", false) end)
    end
    return true
end

function NPCWorldDirectorBridge.CleanupLoadedPersistedRuntimeObjects(director, reason)
    local cell = getCell and getCell() or nil
    if not (director and cell and cell.getZombieList) then return 0 end

    local gmd = director.EnsureData and director.EnsureData() or NPCWorldDirectorBridge.EnsureData(director)
    if NPCIdentityReconciliationBridge and NPCIdentityReconciliationBridge.ReconcileGlobal then
        pcall(function()
            NPCIdentityReconciliationBridge.ReconcileGlobal(gmd, {
                reason = tostring(reason or "persistent_runtime_cleanup"),
                intervalSeconds = 20,
                maxQueue = 96,
                maxGroups = 48,
                maxMarkers = 96,
                allowSoftRevirtualize = true,
                sendRemove = function(id) NPCWorldDirectorBridge.SendDebugMapRemove(id) end
            })
        end)
    end
    NPCWorldDirectorBridge.ReconcileDebugMarkers(gmd, tostring(reason or "persistent_runtime_cleanup"), 96)
    local zombieList = cell:getZombieList()
    if not zombieList then return 0 end

    local removed = 0
    local recovered = 0
    for i = zombieList:size() - 1, 0, -1 do
        local zombie = zombieList:get(i)
        if NPCWorldDirectorBridge.RecoverLoadedQueuedRuntimeObject(director, zombie, gmd) then
            recovered = recovered + 1
        elseif NPCWorldDirectorBridge.IsStalePersistentRuntimeNPCZombie(zombie, gmd) then
            if NPCWorldDirectorBridge.RecoverLoadedPersistedRuntimeObject(director, zombie, gmd) then
                recovered = recovered + 1
            elseif NPCWorldDirectorBridge.RemoveZombieObject(zombie) then
                removed = removed + 1
            end
        end
    end

    if removed > 0 or recovered > 0 then
        gmd.WorldDirector = gmd.WorldDirector or {}
        gmd.WorldDirector.lastPersistentRuntimeCleanupAt = getGameTime and getGameTime():getWorldAgeHours() or 0
        gmd.WorldDirector.lastPersistentRuntimeCleanupReason = tostring(reason or "startup_persistent_runtime_cleanup")
        gmd.WorldDirector.lastPersistentRuntimeCleanupRemoved = removed
        gmd.WorldDirector.lastPersistentRuntimeCleanupRecovered = recovered
    end
    return removed + recovered
end

function NPCWorldDirectorBridge.MatchesCleanupScope(zombie, args, runtimeId, runtimeIdSet, persistentIdSet)
    args = args or {}

    if runtimeId and runtimeIdSet and runtimeIdSet[tostring(runtimeId)] then return true end

    local persistentId = NPCWorldDirectorBridge.GetZombieServiceId(zombie, NPC_WORLD_DIRECTOR_LEGACY_KEYS.persistentId, NPC_WORLD_DIRECTOR_LEGACY_KEYS.persistentId)
    if persistentId and persistentIdSet and persistentIdSet[tostring(persistentId)] then return true end

    local requestedGroupId = args.groupId or args.worldGroupId
    local hasPersistentIds = NPCWorldDirectorBridge.SetHasEntries(persistentIdSet)
    if requestedGroupId ~= nil then
        local objectGroupId = NPCWorldDirectorBridge.GetZombieServiceId(zombie, NPC_WORLD_DIRECTOR_LEGACY_KEYS.worldGroupId, NPC_WORLD_DIRECTOR_LEGACY_KEYS.worldGroupId)
        if objectGroupId and tostring(objectGroupId) == tostring(requestedGroupId) then return true end
        return false
    end

    if hasPersistentIds then return false end
    if NPCWorldDirectorBridge.SetHasEntries(runtimeIdSet) then return false end

    return true
end

function NPCWorldDirectorBridge.IsFormerNPCZombie(zombie)
    if not zombie then return false end
    if NPCZombieLifecycleClassifierBridge and NPCZombieLifecycleClassifierBridge.IsNPCLikeZombie then
        local ok, npcLike = pcall(function() return NPCZombieLifecycleClassifierBridge.IsNPCLikeZombie(zombie) end)
        if ok then return npcLike == true end
    end
    local md = zombie.getModData and zombie:getModData() or nil
    if md and (md[NPC_WORLD_DIRECTOR_LEGACY_KEYS.formerNPCZombie] or md[NPC_WORLD_DIRECTOR_LEGACY_KEYS.isNPC] or md[NPC_WORLD_DIRECTOR_LEGACY_KEYS.runtimeId] or md[NPC_WORLD_DIRECTOR_LEGACY_KEYS.persistentId] or md[NPC_WORLD_DIRECTOR_LEGACY_KEYS.worldGroupId] or md[NPC_WORLD_DIRECTOR_LEGACY_KEYS.program]) then return true end

    if zombie.getVariableBoolean then
        local okVar, var = pcall(function() return zombie:getVariableBoolean(NPC_WORLD_DIRECTOR_LEGACY_KEYS.formerNPCZombie) end)
        if okVar and var then return true end
    end

    if zombie.getVariableString then
        local okRuntime, runtimeId = pcall(function() return zombie:getVariableString(NPC_WORLD_DIRECTOR_LEGACY_KEYS.runtimeId) end)
        if okRuntime and runtimeId and runtimeId ~= "" then return true end

        local okPersistent, persistentId = pcall(function() return zombie:getVariableString(NPC_WORLD_DIRECTOR_LEGACY_KEYS.persistentId) end)
        if okPersistent and persistentId and persistentId ~= "" then return true end

        local okGroup, groupId = pcall(function() return zombie:getVariableString(NPC_WORLD_DIRECTOR_LEGACY_KEYS.worldGroupId) end)
        if okGroup and groupId and groupId ~= "" then return true end
    end

    return false
end

function NPCWorldDirectorBridge.ShouldKeepDeadNPCCorpse(zombie, args)
    if not zombie then return false end
    local md = zombie.getModData and zombie:getModData() or nil
    if not md then return false end
    if not (md.NPCKeepCorpse == true or md.NPCLootableCorpse == true or md.NPCCorpseFromNPCCombat == true) then return false end
    if args and (args.forceCorpseCleanup == true or args.forceRemoveCorpse == true or args.blackMarketStaticCleanup == true) then return false end
    local isDead = false
    local okDead, deadValue = pcall(function() return zombie:isDead() end)
    if okDead and deadValue == true then isDead = true end
    local okAlive, aliveValue = pcall(function() return zombie:isAlive() end)
    if okAlive and aliveValue == false then isDead = true end
    return isDead == true
end

function NPCWorldDirectorBridge.RemoveZombieObject(zombie, args)
    if not zombie then return false end
    if NPCWorldDirectorBridge.ShouldKeepDeadNPCCorpse(zombie, args) then return false end

    if NPCZombieLifecycleClassifierBridge and NPCZombieLifecycleClassifierBridge.IsOrdinaryZombie then
        local okOrdinary, ordinary = pcall(function() return NPCZombieLifecycleClassifierBridge.IsOrdinaryZombie(zombie) end)
        if okOrdinary and ordinary == true then return false end
    end

    pcall(function() zombie:setVariable(NPC_WORLD_DIRECTOR_LEGACY_KEYS.liveFlag, false) end)
    pcall(function() zombie:setVariable(NPC_WORLD_DIRECTOR_LEGACY_KEYS.primary, "") end)
    pcall(function() zombie:setVariable(NPC_WORLD_DIRECTOR_LEGACY_KEYS.secondary, "") end)
    pcall(function() zombie:clearAttachedItems() end)
    pcall(function() zombie:removeFromWorld() end)
    pcall(function() zombie:removeFromSquare() end)

    return true
end

function NPCWorldDirectorBridge.RemoveLoadedNPCObjects(director, args)
    args = args or {}

    local cell = getCell and getCell() or nil
    if not cell then return 0 end

    local zombieList = cell:getZombieList()
    if not zombieList then return 0 end

    local idSet = NPCWorldDirectorBridge.IdSet(args.ids or args.id)
    local persistentIdSet = NPCWorldDirectorBridge.IdSet(args.persistentIds or args.persistentId)
    local gmd = director and director.EnsureData and director.EnsureData() or nil
    local removed = 0

    for i = zombieList:size() - 1, 0, -1 do
        local zombie = zombieList:get(i)
        if zombie then
            local remove = false
            local runtimeId = NPCWorldDirectorBridge.GetZombieRuntimeId(zombie)
            local queueActive = runtimeId and gmd and gmd.Queue and (gmd.Queue[runtimeId] or gmd.Queue[tostring(runtimeId)] or (tonumber(runtimeId) and gmd.Queue[tonumber(runtimeId)]))

            if runtimeId and idSet[tostring(runtimeId)] and (not args.formerOnly or not queueActive) then
                remove = true
            elseif args.formerOnly and not queueActive and NPCWorldDirectorBridge.NearPoint(zombie, args) and NPCWorldDirectorBridge.IsCleanupFormerNPCZombie(zombie) and NPCWorldDirectorBridge.MatchesCleanupScope(zombie, args, runtimeId, idSet, persistentIdSet) then
                remove = true
            end

            if remove and NPCWorldDirectorBridge.RemoveZombieObject(zombie, args) then
                removed = removed + 1
            end
        end
    end

    return removed
end

function NPCWorldDirectorBridge.RemoveObjectQueueEnabled(director, args)
    if not (director and director.NET_BATCHED_REMOVE_OBJECTS == true) then return false end
    if not args or args.immediate or args.formerOnly or args.blackMarketStaticCleanup then return false end

    local idSet = NPCWorldDirectorBridge.IdSet(args.ids or args.id)
    for _, _ in pairs(idSet) do
        return true
    end

    return false
end

function NPCWorldDirectorBridge.QueueRemoveObjectArgs(director, args)
    if not NPCWorldDirectorBridge.RemoveObjectQueueEnabled(director, args) then return false end

    local q = director._removeObjectQueue
    if not q then
        q = {ids = {}, order = {}, head = 1, ticks = 0}
        director._removeObjectQueue = q
    end

    local idSet = NPCWorldDirectorBridge.IdSet(args.ids or args.id)
    local added = 0
    for id, _ in pairs(idSet) do
        local sid = tostring(id)
        if sid ~= "" and not q.ids[sid] then
            q.ids[sid] = true
            q.order[#q.order + 1] = sid
            added = added + 1
        end
    end

    if added <= 0 then return false end
    q.reason = tostring(args.reason or q.reason or "batched_remove_bandit_objects")
    q.groupId = args.groupId or q.groupId
    q.x = tonumber(args.x) or q.x
    q.y = tonumber(args.y) or q.y
    q.z = tonumber(args.z) or q.z
    return true
end

function NPCWorldDirectorBridge.FlushRemoveObjectQueue(director, force)
    local q = director and director._removeObjectQueue or nil
    if not q or type(q.order) ~= "table" then return 0 end

    q.ticks = (tonumber(q.ticks) or 0) + 1
    local interval = math.max(1, tonumber(director.NET_REMOVE_OBJECTS_BATCH_INTERVAL_TICKS) or 6)
    if not force and (q.ticks % interval) ~= 0 then return 0 end

    local maxIds = math.max(1, tonumber(director.NET_REMOVE_OBJECTS_MAX_IDS_PER_BATCH) or 96)
    local ids = {}

    while #ids < maxIds and #q.order > 0 do
        local id = table.remove(q.order, 1)
        if id and q.ids[id] then
            q.ids[id] = nil
            ids[#ids + 1] = id
        end
    end

    q.head = 1

    if #ids <= 0 then return 0 end

    local batch = {
        ids = ids,
        reason = tostring(q.reason or "batched_remove_bandit_objects"),
        batched = true,
        x = q.x,
        y = q.y,
        z = q.z
    }

    local removed = NPCWorldDirectorBridge.RemoveLoadedNPCObjects(director, batch)
    if sendServerCommand then
        sendServerCommand('NPCCommands', NPC_WORLD_DIRECTOR_LEGACY_COMMANDS.removeObjects, batch)
    end
    return removed
end

function NPCWorldDirectorBridge.RegisterFormerNPCCleanupScope(director, args)
    if not (director and args and args.formerOnly) then return false end

    local hasScope = args.groupId ~= nil or args.worldGroupId ~= nil or args.persistentIds ~= nil or args.persistentId ~= nil or args.ids ~= nil or args.id ~= nil
    if not hasScope then return false end

    local scopes = director._formerNPCCleanupScopes or director[NPC_WORLD_DIRECTOR_LEGACY_FIELDS.formerCleanupScopes]
    if type(scopes) ~= "table" then
        scopes = {}
    end
    director._formerNPCCleanupScopes = scopes
    director[NPC_WORLD_DIRECTOR_LEGACY_FIELDS.formerCleanupScopes] = scopes

    local tick = tonumber(director._tick) or 0
    local ttl = math.max(60, tonumber(director.FORMER_NPC_CLEANUP_SCOPE_TTL_TICKS) or 1800)
    local scope = {}
    for k, v in pairs(args) do scope[k] = v end
    scope.expiresTick = tick + ttl
    scope.radius = tonumber(scope.radius) or 160
    scope.reason = tostring(scope.reason or "former_bandit_delayed_cleanup")

    local key = tostring(scope.groupId or scope.worldGroupId or "") .. ":" .. tostring(scope.x or "") .. ":" .. tostring(scope.y or "") .. ":" .. tostring(scope.reason or "")
    for _, existing in ipairs(scopes) do
        local existingKey = tostring(existing.groupId or existing.worldGroupId or "") .. ":" .. tostring(existing.x or "") .. ":" .. tostring(existing.y or "") .. ":" .. tostring(existing.reason or "")
        if existingKey == key then
            existing.expiresTick = scope.expiresTick
            existing.radius = scope.radius
            existing.persistentIds = scope.persistentIds or existing.persistentIds
            existing.persistentId = scope.persistentId or existing.persistentId
            existing.ids = scope.ids or existing.ids
            existing.id = scope.id or existing.id
            return true
        end
    end

    scopes[#scopes + 1] = scope
    local maxScopes = math.max(4, tonumber(director.FORMER_NPC_CLEANUP_SCOPE_MAX) or 32)
    while #scopes > maxScopes do
        table.remove(scopes, 1)
    end

    return true
end

function NPCWorldDirectorBridge.FlushFormerNPCCleanupScopes(director, force)
    local scopes = director and (director._formerNPCCleanupScopes or director[NPC_WORLD_DIRECTOR_LEGACY_FIELDS.formerCleanupScopes]) or nil
    if director and type(scopes) == "table" then
        director._formerNPCCleanupScopes = scopes
        director[NPC_WORLD_DIRECTOR_LEGACY_FIELDS.formerCleanupScopes] = scopes
    end
    if type(scopes) ~= "table" or #scopes <= 0 then return 0 end

    local tick = tonumber(director._tick) or 0
    local interval = math.max(1, tonumber(director.FORMER_NPC_CLEANUP_SCOPE_INTERVAL_TICKS) or 15)
    if not force and (tick % interval) ~= 0 then return 0 end

    local removed = 0
    for i = #scopes, 1, -1 do
        local scope = scopes[i]
        if not scope or (scope.expiresTick and tick > tonumber(scope.expiresTick)) then
            table.remove(scopes, i)
        else
            removed = removed + (tonumber(NPCWorldDirectorBridge.RemoveLoadedNPCObjects(director, scope)) or 0)
        end
    end

    return removed
end

function NPCWorldDirectorBridge.RequestNPCObjectCleanup(director, args)
    args = args or {}

    if args.formerOnly then
        NPCWorldDirectorBridge.RegisterFormerNPCCleanupScope(director, args)
    end

    if NPCWorldDirectorBridge.QueueRemoveObjectArgs(director, args) then
        return 0
    end

    local removed = NPCWorldDirectorBridge.RemoveLoadedNPCObjects(director, args)
    if sendServerCommand then
        sendServerCommand('NPCCommands', NPC_WORLD_DIRECTOR_LEGACY_COMMANDS.removeObjects, args)
    end

    return removed
end

local NPC_WD_BAD_ZONE_KEYWORDS = {"water", "deepforest", "deep forest", "forest", "vegetation", "vegitation", "foraging", "farm", "farmland", "farm land", "field", "ranch", "camp"}
local NPC_WD_ROAD_ZONE_KEYWORDS = {"nav", "road", "street", "highway", "junction"}
local NPC_WD_TOWN_ZONE_KEYWORDS = {"town", "trailer", "commercial", "industrial", "business", "community", "restaurant", "shop", "store", "school", "police", "fire", "hospital", "residential", "parking", "office", "motel", "hotel", "bar", "gas", "fossoil", "bank", "warehouse", "storage", "factory", "carrepair", "mechanic"}
local NPC_WD_SETTLEMENT_ZONE_KEYWORDS = {"settlement", "village", "suburb", "neighborhood", "neighbourhood"}

local function npc_wd_dist(x1, y1, x2, y2)
    x1 = tonumber(x1) or 0
    y1 = tonumber(y1) or 0
    x2 = tonumber(x2) or 0
    y2 = tonumber(y2) or 0
    local dx = x1 - x2
    local dy = y1 - y2
    return math.sqrt(dx * dx + dy * dy)
end

function NPCWorldDirectorBridge.Lower(value)
    if not value then return "" end
    return string.lower(tostring(value))
end

function NPCWorldDirectorBridge.HasAny(value, needles)
    local v = NPCWorldDirectorBridge.Lower(value)
    if type(needles) ~= "table" then return false end
    for _, needle in ipairs(needles) do
        if string.find(v, tostring(needle), 1, true) then
            return true
        end
    end
    return false
end

function NPCWorldDirectorBridge.ZoneType(zone)
    if not zone then return nil end

    local ok, zoneType = pcall(function()
        return zone:getType()
    end)

    if ok and zoneType then
        return tostring(zoneType)
    end

    return nil
end

function NPCWorldDirectorBridge.ZoneListAdd(types, zone)
    if type(types) ~= "table" then return end
    local zoneType = NPCWorldDirectorBridge.ZoneType(zone)
    if zoneType then
        table.insert(types, zoneType)
    end
end

function NPCWorldDirectorBridge.GetWorldBounds(director)
    local minX, minY, maxX, maxY = 0, 0, 18000, 18000
    local world = getWorld and getWorld() or nil
    if not world then return minX, minY, maxX, maxY end

    local metaGrid = world:getMetaGrid()
    if not metaGrid then return minX, minY, maxX, maxY end

    local ok
    ok, minX = pcall(function() return metaGrid:getMinX() end)
    if not ok or not minX then minX = 0 end

    ok, minY = pcall(function() return metaGrid:getMinY() end)
    if not ok or not minY then minY = 0 end

    ok, maxX = pcall(function() return metaGrid:getMaxX() end)
    if not ok or not maxX then maxX = 60 end

    ok, maxY = pcall(function() return metaGrid:getMaxY() end)
    if not ok or not maxY then maxY = 60 end

    local tileCellSize = tonumber(director and director.TILE_CELL_SIZE) or 300
    minX = math.floor(minX * tileCellSize)
    minY = math.floor(minY * tileCellSize)
    maxX = math.floor((maxX + 1) * tileCellSize)
    maxY = math.floor((maxY + 1) * tileCellSize)

    if maxX - minX < 1000 then
        minX, maxX = 0, 18000
    end

    if maxY - minY < 1000 then
        minY, maxY = 0, 18000
    end

    return minX, minY, maxX, maxY
end

function NPCWorldDirectorBridge.IsTooCloseToPlayer(x, y, radius)
    local playerList = getOnlinePlayers and getOnlinePlayers() or nil
    if playerList then
        for i=0, playerList:size()-1 do
            local player = playerList:get(i)
            if player and not player:isDead() then
                if npc_wd_dist(x, y, player:getX(), player:getY()) < radius then
                    return true
                end
            end
        end
    end

    return false
end

function NPCWorldDirectorBridge.GetZoneTypesAt(x, y)
    local types = {}
    local world = getWorld and getWorld() or nil
    if not world then return types end

    local metaGrid = world:getMetaGrid()
    if not metaGrid then return types end

    local ok, zones = pcall(function()
        return metaGrid:getZonesAt(x, y, 0)
    end)

    if ok and zones then
        local okSize, zoneCount = pcall(function() return zones:size() end)
        if okSize and zoneCount then
            for i=0, zoneCount-1 do
                NPCWorldDirectorBridge.ZoneListAdd(types, zones:get(i))
            end
        elseif type(zones) == "table" then
            for _, zone in pairs(zones) do
                NPCWorldDirectorBridge.ZoneListAdd(types, zone)
            end
        end
    end

    ok, zones = pcall(function()
        return metaGrid:getZoneAt(x, y, 0)
    end)

    if ok and zones then
        NPCWorldDirectorBridge.ZoneListAdd(types, zones)
    end

    return types
end

function NPCWorldDirectorBridge.ScoreWorldPoint(director, x, y)
    local zoneTypes = director.GetZoneTypesAt and director.GetZoneTypesAt(x, y) or NPCWorldDirectorBridge.GetZoneTypesAt(x, y)
    local score = -25
    local reason = "unmarked"

    for _, zoneType in pairs(zoneTypes) do
        local z = NPCWorldDirectorBridge.Lower(zoneType)

        if NPCWorldDirectorBridge.HasAny(z, NPC_WD_BAD_ZONE_KEYWORDS) then
            return -1000, "blocked", zoneTypes
        end

        if NPCWorldDirectorBridge.HasAny(z, NPC_WD_TOWN_ZONE_KEYWORDS) then
            score = score + 180
            reason = "town"
        elseif NPCWorldDirectorBridge.HasAny(z, NPC_WD_SETTLEMENT_ZONE_KEYWORDS) then
            score = score + 140
            if reason ~= "town" then reason = "settlement" end
        elseif NPCWorldDirectorBridge.HasAny(z, NPC_WD_ROAD_ZONE_KEYWORDS) then
            score = score + 35
            if reason ~= "town" and reason ~= "settlement" then reason = "road" end
        end
    end

    return score, reason, zoneTypes
end

function NPCWorldDirectorBridge.IsZoneAllowed(director, x, y)
    local score = NPCWorldDirectorBridge.ScoreWorldPoint(director, x, y)
    return score > -1000
end

function NPCWorldDirectorBridge.IsUrbanReason(reason)
    return reason == "town" or reason == "settlement"
end

function NPCWorldDirectorBridge.GetUrbanAffinityAt(director, x, y, radius)
    radius = tonumber(radius) or 320
    local best = 0
    local offsets = {
        {0, 0},
        {radius, 0}, {-radius, 0}, {0, radius}, {0, -radius},
        {radius, radius}, {-radius, radius}, {radius, -radius}, {-radius, -radius},
        {math.floor(radius / 2), 0}, {-math.floor(radius / 2), 0}, {0, math.floor(radius / 2)}, {0, -math.floor(radius / 2)}
    }

    for _, p in ipairs(offsets) do
        local score, reason = NPCWorldDirectorBridge.ScoreWorldPoint(director, x + p[1], y + p[2])
        if reason == "town" then
            if score + 120 > best then best = score + 120 end
        elseif reason == "settlement" then
            if score + 80 > best then best = score + 80 end
        elseif score and score > 120 then
            if score > best then best = score end
        end
    end

    return best
end

function NPCWorldDirectorBridge.IsUrbanWorldPoint(director, x, y)
    local score, reason = NPCWorldDirectorBridge.ScoreWorldPoint(director, x, y)
    if NPCWorldDirectorBridge.IsUrbanReason(reason) and score >= (tonumber(director.URBAN_GROUP_ACCEPT_SCORE) or 170) then
        return true, score, reason
    end

    if reason == "road" then
        local affinity = NPCWorldDirectorBridge.GetUrbanAffinityAt(director, x, y, tonumber(director.URBAN_GROUP_ROAD_BIAS_RADIUS) or 220)
        if affinity >= (tonumber(director.URBAN_GROUP_MIN_AFFINITY) or 145) then
            return true, score + affinity, "urban_road"
        end
    end

    return false, score or -1000, reason or "blocked"
end

function NPCWorldDirectorBridge.ScoreRoadPatrolPoint(director, x, y)
    local score, reason = NPCWorldDirectorBridge.ScoreWorldPoint(director, x, y)
    if reason ~= "road" then
        return -1000, reason or "blocked", 0
    end

    local urbanAffinity = NPCWorldDirectorBridge.GetUrbanAffinityAt(director, x, y, tonumber(director.ROAD_PATROL_URBAN_BIAS_RADIUS) or 360)
    if urbanAffinity < (tonumber(director.ROAD_PATROL_MIN_URBAN_AFFINITY) or 150) then
        return -1000, "rural_road", urbanAffinity
    end

    local patrolScore = score + urbanAffinity
    return patrolScore, reason, urbanAffinity
end

function NPCWorldDirectorBridge.IsUrbanRoadPatrolPoint(director, x, y)
    local score, reason, urbanAffinity = NPCWorldDirectorBridge.ScoreRoadPatrolPoint(director, x, y)
    if reason == "road" and score >= (tonumber(director.ROAD_PATROL_ACCEPT_SCORE) or 220) then
        return true, score, reason, urbanAffinity
    end
    return false, score or -1000, reason or "blocked", urbanAffinity or 0
end

function NPCWorldDirectorBridge.GetRandomUrbanPoint(director, attempts, avoidPlayerRadius)
    local minX, minY, maxX, maxY = NPCWorldDirectorBridge.GetWorldBounds(director)
    local bestPoint = false
    local bestScore = -1000
    attempts = tonumber(attempts) or tonumber(director.PREFERRED_POINT_ATTEMPTS) or 120
    avoidPlayerRadius = tonumber(avoidPlayerRadius) or tonumber(director.NO_NEW_GROUP_NEAR_PLAYER_RADIUS) or 180

    for _=1, attempts do
        local x = minX + ZombRand(math.max(1, maxX - minX))
        local y = minY + ZombRand(math.max(1, maxY - minY))

        if not NPCWorldDirectorBridge.IsTooCloseToPlayer(x, y, avoidPlayerRadius) then
            local ok, score, reason = NPCWorldDirectorBridge.IsUrbanWorldPoint(director, x, y)
            if ok and score > bestScore then
                bestScore = score
                bestPoint = {x=x, y=y, z=0, spawnClass=reason, zoneScore=score}
                if score >= (tonumber(director.URBAN_GROUP_EARLY_SCORE) or 260) and reason ~= "urban_road" then
                    return bestPoint
                end
            end
        end
    end

    return bestPoint
end

function NPCWorldDirectorBridge.GetRandomWorldPoint(director)
    local point = NPCWorldDirectorBridge.GetRandomUrbanPoint(director, director.PREFERRED_POINT_ATTEMPTS, director.NO_NEW_GROUP_NEAR_PLAYER_RADIUS)
    if point then return point end
    return false
end

function NPCWorldDirectorBridge.GetNearbyPreferredPoint(director, x, y, radius)
    radius = tonumber(radius) or tonumber(director.VIRTUAL_TARGET_RADIUS) or 320

    local bestPoint = false
    local bestScore = -1000

    for _=1, (tonumber(director.VIRTUAL_TARGET_ATTEMPTS) or 80) do
        local dx = ZombRand(-radius, radius + 1)
        local dy = ZombRand(-radius, radius + 1)
        local tx = x + dx
        local ty = y + dy
        local ok, score, reason = NPCWorldDirectorBridge.IsUrbanWorldPoint(director, tx, ty)
        local directorBias = 0
        local directorBiasReason = nil
        if ok and NPCInfluenceFieldBridge and NPCInfluenceFieldBridge.GetWorldPointBonus then
            local bonus = NPCInfluenceFieldBridge.GetWorldPointBonus(tx, ty, nil)
            if bonus and bonus ~= 0 then score = score + bonus end
        end
        if ok then
            directorBias, directorBiasReason = NPCWorldDirectorBridge.DirectorPointBias(director, tx, ty, "roam")
            if directorBias ~= 0 then score = score + directorBias end
        end

        if ok and score > bestScore then
            bestScore = score
            bestPoint = {x=tx, y=ty, z=0, spawnClass=reason, zoneScore=score, directorBias=directorBias, directorBiasReason=directorBiasReason, influenceScore=NPCInfluenceFieldBridge and NPCInfluenceFieldBridge.GetScore and NPCInfluenceFieldBridge.GetScore(tx, ty, {threat=0.4, noise=0.25, baseNeed=0.5}) or nil}
            if score >= (tonumber(director.URBAN_GROUP_EARLY_SCORE) or 260) and reason ~= "urban_road" then
                return bestPoint
            end
        end
    end

    return bestPoint
end

function NPCWorldDirectorBridge.GetNearbyRoadPoint(director, x, y, radius)
    x = tonumber(x)
    y = tonumber(y)
    if not (x and y) then return false end
    radius = tonumber(radius) or (director and tonumber(director.ROAD_PATROL_TARGET_RADIUS)) or 420
    local bestPoint = false
    local bestScore = -1000

    if NPCRoadNavBridge and NPCRoadNavBridge.FindNearbyWorldRoadPoint then
        for _=1, 6 do
            local point = NPCRoadNavBridge.FindNearbyWorldRoadPoint(x, y, radius, (tonumber(director.VIRTUAL_TARGET_ATTEMPTS) or 80) + 80)
            if point then
                local ok, score, reason, urbanAffinity = NPCWorldDirectorBridge.IsUrbanRoadPatrolPoint(director, point.x, point.y)
                local directorBias = 0
                local directorBiasReason = nil
                if ok then
                    directorBias, directorBiasReason = NPCWorldDirectorBridge.DirectorPointBias(director, point.x, point.y, "road")
                    if directorBias ~= 0 then score = score + directorBias end
                end
                if ok and score > bestScore then
                    bestScore = score
                    bestPoint = {x=point.x, y=point.y, z=point.z or 0, spawnClass="road", zoneScore=score, urbanAffinity=urbanAffinity or 0, directorBias=directorBias, directorBiasReason=directorBiasReason}
                    if score >= (tonumber(director.ROAD_PATROL_EARLY_SCORE) or 320) then
                        return bestPoint
                    end
                end
            end
        end
    end

    for _=1, (tonumber(director.VIRTUAL_TARGET_ATTEMPTS) or 80) do
        local dx = ZombRand(-radius, radius + 1)
        local dy = ZombRand(-radius, radius + 1)
        local tx = x + dx
        local ty = y + dy
        local ok, score, reason, urbanAffinity = NPCWorldDirectorBridge.IsUrbanRoadPatrolPoint(director, tx, ty)
        local directorBias = 0
        local directorBiasReason = nil
        if ok then
            directorBias, directorBiasReason = NPCWorldDirectorBridge.DirectorPointBias(director, tx, ty, "road")
            if directorBias ~= 0 then score = score + directorBias end
        end
        if ok and score > bestScore then
            bestScore = score
            bestPoint = {x=tx, y=ty, z=0, spawnClass=reason, zoneScore=score, urbanAffinity=urbanAffinity or 0, directorBias=directorBias, directorBiasReason=directorBiasReason}
            if score >= (tonumber(director.ROAD_PATROL_EARLY_SCORE) or 320) then
                return bestPoint
            end
        end
    end

    return bestPoint
end

function NPCWorldDirectorBridge.GetRandomRoadPoint(director)
    local bestPoint = false
    local bestScore = -1000

    for _=1, 18 do
        local anchor = NPCWorldDirectorBridge.GetRandomUrbanPoint(director, math.max(120, math.floor((tonumber(director.PREFERRED_POINT_ATTEMPTS) or 120) / 8)), director.NO_NEW_GROUP_NEAR_PLAYER_RADIUS)
        if anchor then
            local candidate = NPCWorldDirectorBridge.GetNearbyRoadPoint(director, anchor.x, anchor.y, director.ROAD_PATROL_TARGET_RADIUS)
            if candidate then
                local score = tonumber(candidate.zoneScore) or -1000
                if score > bestScore then
                    bestPoint = candidate
                    bestScore = score
                    if score >= (tonumber(director.ROAD_PATROL_EARLY_SCORE) or 320) then
                        return bestPoint
                    end
                end
            end
        end
    end

    local minX, minY, maxX, maxY = NPCWorldDirectorBridge.GetWorldBounds(director)
    for _=1, (tonumber(director.PREFERRED_POINT_ATTEMPTS) or 120) do
        local x = minX + ZombRand(math.max(1, maxX - minX))
        local y = minY + ZombRand(math.max(1, maxY - minY))
        if not NPCWorldDirectorBridge.IsTooCloseToPlayer(x, y, (tonumber(director.NO_NEW_GROUP_NEAR_PLAYER_RADIUS) or 180)) then
            local ok, score, reason, urbanAffinity = NPCWorldDirectorBridge.IsUrbanRoadPatrolPoint(director, x, y)
            if ok and score > bestScore then
                bestScore = score
                bestPoint = {x=x, y=y, z=0, spawnClass="road", zoneScore=score, urbanAffinity=urbanAffinity or 0}
                if score >= (tonumber(director.ROAD_PATROL_EARLY_SCORE) or 320) then
                    return bestPoint
                end
            end
        end
    end

    return bestPoint
end

-- Stage 47: neutral physical activation / proxy-LOD backend.
-- This section keeps historical world-director contracts but moves physical-count,
-- activation-budget and proxy-LOD decisions out of the compatibility facade.

function NPCWorldDirectorBridge.Dist(x1, y1, x2, y2)
    x1 = tonumber(x1) or 0
    y1 = tonumber(y1) or 0
    x2 = tonumber(x2) or 0
    y2 = tonumber(y2) or 0
    local dx = x1 - x2
    local dy = y1 - y2
    return math.sqrt(dx * dx + dy * dy)
end

function NPCWorldDirectorBridge.CountTable(t)
    local n = 0
    if type(t) == "table" then
        for _, _ in pairs(t) do n = n + 1 end
    end
    return n
end

function NPCWorldDirectorBridge.PlayerKey(player)
    if not player then return nil end
    local ok, value
    if player.getOnlineID then
        ok, value = pcall(function() return player:getOnlineID() end)
        if ok and value ~= nil then return "online:" .. tostring(value) end
    end
    if player.getUsername then
        ok, value = pcall(function() return player:getUsername() end)
        if ok and value ~= nil and tostring(value) ~= "" then return "user:" .. tostring(value) end
    end
    if player.getDisplayName then
        ok, value = pcall(function() return player:getDisplayName() end)
        if ok and value ~= nil and tostring(value) ~= "" then return "name:" .. tostring(value) end
    end
    return tostring(player)
end

function NPCWorldDirectorBridge.PlayerId(player)
    if not player then return nil end
    if NPCUtils and NPCUtils.GetCharacterID then
        local ok, id = pcall(function() return NPCUtils.GetCharacterID(player) end)
        if ok and id ~= nil then return id end
    end
    if player.getOnlineID then
        local ok, id = pcall(function() return player:getOnlineID() end)
        if ok and id ~= nil then return id end
    end
    return nil
end

function NPCWorldDirectorBridge.FindPlayerByMercenaryOwner(ownerId)
    if ownerId == nil then return nil end
    local wanted = tostring(ownerId)
    local playerList = getOnlinePlayers and getOnlinePlayers() or nil
    if not playerList then return nil end

    for i=0, playerList:size()-1 do
        local player = playerList:get(i)
        if player and not player:isDead() then
            local pid = NPCWorldDirectorBridge.PlayerId(player)
            if pid ~= nil and tostring(pid) == wanted then return player end
            if player.getOnlineID then
                local ok, onlineId = pcall(function() return player:getOnlineID() end)
                if ok and onlineId ~= nil and tostring(onlineId) == wanted then return player end
            end
        end
    end

    return nil
end

function NPCWorldDirectorBridge.BrainCoords(brain)
    if type(brain) ~= "table" then return nil, nil, nil end
    local x = brain.debugCoords and tonumber(brain.debugCoords.x) or tonumber(brain.x)
    local y = brain.debugCoords and tonumber(brain.debugCoords.y) or tonumber(brain.y)
    local z = brain.debugCoords and tonumber(brain.debugCoords.z) or tonumber(brain.z) or 0
    if not x and brain.bornCoords then x = tonumber(brain.bornCoords.x) end
    if not y and brain.bornCoords then y = tonumber(brain.bornCoords.y) end
    if not z and brain.bornCoords then z = tonumber(brain.bornCoords.z) or 0 end
    return x, y, z
end

function NPCWorldDirectorBridge.IsHiredFollowGroup(group)
    if type(group) ~= "table" then return false end
    if not (group.mercenaryHired == true or group.hired == true or group.isPlayerGuard == true or group.followPlayer ~= nil) then return false end

    local order = type(group.order) == "table" and group.order or nil
    local orderName = order and (order.name or order.orderName) or nil
    if orderName == nil then return group.followPlayer ~= nil end
    return tostring(orderName) == "Follow"
end

function NPCWorldDirectorBridge.HiredFollowOwnerId(group)
    if type(group) ~= "table" then return nil end
    local order = type(group.order) == "table" and group.order or nil
    return group.followPlayer or group.mercenaryHiredBy or group.master or (order and order.master)
end

function NPCWorldDirectorBridge.HasPendingGroupSpawnQueue(groupId)
    if not groupId then return false end
    if NPCSpawnQueueServer and NPCSpawnQueueServer.HasPending then
        local ok, hasPending = pcall(function() return NPCSpawnQueueServer.HasPending(groupId) end)
        if ok and hasPending then return true end
    end
    if NPCSpawnQueueBridge and NPCSpawnQueueBridge.HasPending then
        local ok, hasPending = pcall(function() return NPCSpawnQueueBridge.HasPending(groupId) end)
        if ok and hasPending then return true end
    end
    return false
end

function NPCWorldDirectorBridge.CancelPendingGroupSpawnQueue(groupId, reason)
    if not groupId then return 0 end
    local removed = 0
    if NPCSpawnQueueServer and NPCSpawnQueueServer.CancelGroup then
        local ok, value = pcall(function() return NPCSpawnQueueServer.CancelGroup(groupId, reason) end)
        if ok and tonumber(value) then removed = math.max(removed, tonumber(value) or 0) end
    elseif NPCSpawnQueueBridge and NPCSpawnQueueBridge.CancelGroup then
        local ok, value = pcall(function() return NPCSpawnQueueBridge.CancelGroup(groupId, reason) end)
        if ok and tonumber(value) then removed = math.max(removed, tonumber(value) or 0) end
    end
    return removed
end

function NPCWorldDirectorBridge.MercenaryLeashRematerializeCooldownHours(director)
    local seconds = tonumber(director and director.MERCENARY_FOLLOW_REMATERIALIZE_COOLDOWN_SECONDS) or 45
    if seconds < 10 then seconds = 10 end
    return seconds / 3600
end

function NPCWorldDirectorBridge.MercenaryLeashHireGraceHours(director)
    local seconds = tonumber(director and director.MERCENARY_FOLLOW_HIRE_GRACE_SECONDS) or 8
    if seconds < 0 then seconds = 0 end
    return seconds / 3600
end

function NPCWorldDirectorBridge.MercenaryLeashLoadedCountCacheHours(director)
    local seconds = tonumber(director and director.MERCENARY_FOLLOW_LOADED_COUNT_CACHE_SECONDS) or 2
    if seconds < 0 then seconds = 0 end
    return seconds / 3600
end

function NPCWorldDirectorBridge.InvalidateMercenaryLoadedCountCache(director, groupId)
    if not (director and groupId and director._mercenaryLoadedGroupCountCache) then return end
    director._mercenaryLoadedGroupCountCache[tostring(groupId)] = nil
end

function NPCWorldDirectorBridge.UpdateHiredFollowGroupMarker(gmd, groupId, group, x, y, z, count)
    if not (gmd and groupId and group) then return end
    if not gmd.DebugMapMarkers then gmd.DebugMapMarkers = {} end

    groupId = tostring(groupId)
    local marker = gmd.DebugMapMarkers[groupId] or {}
    marker.id = groupId
    marker.markerType = "group"
    marker.x = math.floor(tonumber(x) or tonumber(group.x) or 0)
    marker.y = math.floor(tonumber(y) or tonumber(group.y) or 0)
    marker.z = math.floor(tonumber(z) or tonumber(group.z) or 0)
    marker.name = NPCWorldDirectorBridge.GetVirtualGroupDisplayName(groupId, group, "Hired Blue Mercenaries " .. tostring(groupId))
    marker.count = tonumber(count) or tonumber(group.count) or marker.count or 0
    marker.hostile = false
    marker.friendly = true
    marker.factionSide = "blue"
    marker.faction = "blue"
    marker.side = "blue"
    marker.patrolColor = "blue"
    marker.program = group.program and group.program.name or marker.program or "Companion"
    marker.mercenary = group.mercenary or true
    marker.mercenaryHired = true
    marker.mercenaryHiredBy = group.mercenaryHiredBy
    marker.isPlayerGuard = true
    marker.virtual = group.virtual == true
    marker.active = group.activated == true
    marker.dead = false
    marker.state = group.state
    marker.updatedAt = group.updatedAt or (getGameTime and getGameTime():getWorldAgeHours() or marker.updatedAt)
    NPCWorldDirectorBridge.ApplyVirtualGroupMapMotionFields(nil, marker, group, marker.updatedAt)
    gmd.DebugMapMarkers[groupId] = marker
    NPCWorldDirectorBridge.SendDebugMapUpdate(marker)
end

function NPCWorldDirectorBridge.PhysicalLoadLevel()
    local level = 0

    if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.GetLoadState then
        local ok, state = pcall(function() return NPCWorkSchedulerBridge.GetLoadState(false) end)
        if ok and state then
            level = math.max(level, tonumber(state.level) or 0)
        end
    end

    if NPCCrowdBudgetBridge and NPCCrowdBudgetBridge.GetDiagnostics then
        local ok, diag = pcall(function() return NPCCrowdBudgetBridge.GetDiagnostics() end)
        if ok and diag then
            level = math.max(level, tonumber(diag.level) or 0)
        end
    end

    if NPCStreamingRuntimeBridge and NPCStreamingRuntimeBridge.GetLevel then
        local ok, streamingLevel = pcall(function() return NPCStreamingRuntimeBridge.GetLevel() end)
        if ok then level = math.max(level, tonumber(streamingLevel) or 0) end
    end

    return level
end

function NPCWorldDirectorBridge.IsImportantPhysicalGroup(group)
    if not group then return false end
    if group.mercenaryHired or group.hired or group.isPlayerGuard or group.followPlayer or group.guardPlayer then return true end
    if group.inBattle or group.virtualBattle or group.battleId or group.enemyGroupId then return true end
    if group.bountyHunter or group.targetClass == "bounty_hunt" then return true end
    if group.leaderId or group.isFactionLeader then return true end
    if group.economyConvoy or group.convoyId then return true end
    if group.blackMarket or group.blackMarketNPC or group.blackMarketService or group.blackMarketQuestGuardGroup or group.blackMarketDefenseQuestGroup then return true end
    return false
end

function NPCWorldDirectorBridge.ProxyLog(director, message)
    if director and director.PROXY_LOD_DEBUG then
        print(message)
    end
end

function NPCWorldDirectorBridge.ProxyRetryHours(director)
    return math.max(1, tonumber(director and director.PROXY_LOD_RETRY_SECONDS) or 18) / 3600
end

function NPCWorldDirectorBridge.GetNearestPlayer(_director, x, y, radius)
    local playerList = getOnlinePlayers and getOnlinePlayers() or nil
    local bestPlayer = nil
    local bestDist = radius

    if playerList then
        for i=0, playerList:size()-1 do
            local player = playerList:get(i)
            if player and not player:isDead() then
                local d = NPCWorldDirectorBridge.Dist(x, y, player:getX(), player:getY())
                if d < bestDist then
                    bestDist = d
                    bestPlayer = player
                end
            end
        end
    end

    return bestPlayer, bestDist
end

function NPCWorldDirectorBridge.GetPhysicalGroupCount(director)
    local gmd = director.EnsureData()
    local count = 0
    local radius = director.PHYSICAL_DEACTIVATION_RADIUS or 650

    for _, group in pairs(gmd.VirtualGroups) do
        if group and group.activated then
            local nearPlayer = director.GetNearestPlayer(group.x, group.y, radius)
            if nearPlayer then
                count = count + 1
            end
        end
    end

    return count
end

function NPCWorldDirectorBridge.CountPhysicalNPCNearPlayer(director, player, radius)
    if not player then return 0 end
    local gmd = director.EnsureData()
    local px = tonumber(player:getX()) or 0
    local py = tonumber(player:getY()) or 0
    local r = tonumber(radius) or director.ACTIVATION_RADIUS or 260
    local r2 = r * r
    local count = 0

    if type(gmd.Queue) == "table" then
        for _, brain in pairs(gmd.Queue) do
            local x, y = NPCWorldDirectorBridge.BrainCoords(brain)
            if x and y then
                local dx = x - px
                local dy = y - py
                if dx * dx + dy * dy <= r2 then
                    count = count + 1
                end
            end
        end
    end

    return count
end

function NPCWorldDirectorBridge.GetGroupMemberCount(_director, group)
    if not group then return 0 end
    if type(group.members) == "table" then
        local n = #group.members
        if n and n > 0 then return n end
        return NPCWorldDirectorBridge.CountTable(group.members)
    end
    return tonumber(group.count) or 0
end

function NPCWorldDirectorBridge.IsProxyLODEnabled(director)
    return director and director.PROXY_LOD_HARD_CAP_ENABLED == true
end

function NPCWorldDirectorBridge.GetProxyLODPlayerCap(director)
    local level = NPCWorldDirectorBridge.PhysicalLoadLevel()
    local cap = tonumber(director.PROXY_LOD_MAX_REAL_NPC_PER_PLAYER) or 10
    if level >= 3 then
        cap = math.min(cap, math.max(2, math.floor((tonumber(director.PROXY_LOD_MAX_REAL_NPC_CRITICAL) or cap) * 0.65)))
    elseif level >= 2 then
        cap = math.min(cap, tonumber(director.PROXY_LOD_MAX_REAL_NPC_CRITICAL) or cap)
    elseif level >= 1 then
        cap = math.min(cap, tonumber(director.PROXY_LOD_MAX_REAL_NPC_HIGH) or cap)
    end
    return math.max(1, math.floor(cap))
end

function NPCWorldDirectorBridge.CountPhysicalNPCGlobal(director, limit)
    local gmd = director.EnsureData()
    local count = 0
    if type(gmd.Queue) == "table" then
        for _, brain in pairs(gmd.Queue) do
            if type(brain) == "table" and NPCWorldDirectorBridge.BrainGroupId(brain) then
                count = count + 1
                if limit and count >= limit then return count end
            end
        end
    end
    return count
end

function NPCWorldDirectorBridge.GetPhysicalGroupRuntimeInfo(director, groupId)
    local gmd = director.EnsureData()
    local count = 0
    local sumX, sumY, sumZ = 0, 0, 0
    if not groupId or type(gmd.Queue) ~= "table" then return 0, nil, nil, nil end
    groupId = tostring(groupId)
    for _, brain in pairs(gmd.Queue) do
        local brainGroupId = NPCWorldDirectorBridge.BrainGroupId(brain)
        if type(brain) == "table" and brainGroupId and tostring(brainGroupId) == groupId then
            local x, y, z = NPCWorldDirectorBridge.BrainCoords(brain)
            if x and y then
                count = count + 1
                sumX = sumX + x
                sumY = sumY + y
                sumZ = sumZ + (z or 0)
            end
        end
    end
    if count <= 0 then return 0, nil, nil, nil end
    return count, math.floor(sumX / count), math.floor(sumY / count), math.floor(sumZ / count)
end

function NPCWorldDirectorBridge.GetAvailablePhysicalNPCSlots(director, player, group, budget)
    if not director.IsProxyLODEnabled() then return 999999 end
    if NPCWorldDirectorBridge.IsImportantPhysicalGroup(group) then return 999999 end

    local playerCap = director.GetProxyLODPlayerCap()
    local currentNear = budget and tonumber(budget.npcNear) or nil
    if currentNear == nil and player then
        currentNear = director.CountPhysicalNPCNearPlayer(player, director.ACTIVATION_RADIUS)
    end
    currentNear = tonumber(currentNear) or 0

    local globalCap = math.max(1, tonumber(director.PROXY_LOD_MAX_REAL_NPC_GLOBAL) or 48)
    local globalNow = director.CountPhysicalNPCGlobal(globalCap + 1)

    local slots = playerCap - currentNear
    local globalSlots = globalCap - globalNow
    if globalSlots < slots then slots = globalSlots end
    return math.floor(slots)
end

function NPCWorldDirectorBridge.ShouldDeferForProxyLOD(director, group, player, budget)
    if not director.IsProxyLODEnabled() then return nil end
    if not group or NPCWorldDirectorBridge.IsImportantPhysicalGroup(group) then return nil end

    local worldAge = getGameTime():getWorldAgeHours()
    if group.proxyHoldUntil and worldAge < tonumber(group.proxyHoldUntil) then
        return "proxy_lod_hold", (tonumber(group.proxyHoldUntil) or worldAge) - worldAge
    end

    local slots = director.GetAvailablePhysicalNPCSlots(player, group, budget)
    if slots <= 0 then
        return "proxy_lod_player_or_global_cap", NPCWorldDirectorBridge.ProxyRetryHours(director)
    end

    return nil
end

function NPCWorldDirectorBridge.GetProxySpawnLimit(director, group, player, budget, requested)
    local requestedLimit = math.floor(tonumber(requested) or 0)
    if requestedLimit <= 0 then requestedLimit = director.GetGroupMemberCount(group) end
    if not director.IsProxyLODEnabled() or NPCWorldDirectorBridge.IsImportantPhysicalGroup(group) then
        return requestedLimit
    end

    local slots = director.GetAvailablePhysicalNPCSlots(player, group, budget)
    if slots <= 0 then return 0 end
    local limit = math.max(1, math.min(requestedLimit, slots))
    local loadLevel = NPCWorldDirectorBridge.PhysicalLoadLevel()
    if loadLevel >= 3 then
        limit = math.min(limit, 1)
    elseif loadLevel >= 2 then
        limit = math.min(limit, 2)
    elseif loadLevel >= 1 then
        limit = math.min(limit, 3)
    end
    return limit
end

function NPCWorldDirectorBridge.AdjustQueuedSpawnBatch(director, entry, requestedBatch)
    if not director.IsProxyLODEnabled() then return requestedBatch end
    if not entry or not entry.event then return requestedBatch end

    local gmd = director.EnsureData()
    local groupId = entry.groupId or entry.event.worldGroupId
    local group = groupId and gmd.VirtualGroups and gmd.VirtualGroups[tostring(groupId)] or nil
    if NPCWorldDirectorBridge.IsImportantPhysicalGroup(group) then return requestedBatch end

    local x = tonumber(entry.event.x) or (group and tonumber(group.x)) or nil
    local y = tonumber(entry.event.y) or (group and tonumber(group.y)) or nil
    local player = nil
    if x and y then
        player = director.GetNearestPlayer(x, y, director.ACTIVATION_RADIUS)
    end
    if not player and group then
        player = director.GetNearestPlayer(group.x, group.y, director.ACTIVATION_RADIUS)
    end

    if NPCStreamingRuntimeBridge and NPCStreamingRuntimeBridge.ShouldDeferQueuedSpawn then
        local ok, defer, deferTicks, deferReason = pcall(function() return NPCStreamingRuntimeBridge.ShouldDeferQueuedSpawn(entry, group, player) end)
        if ok and defer then
            return 0, deferTicks or 180, deferReason or "streaming_unload_spawn_pause"
        end
    end

    if not player then
        return 0, 180, "proxy_lod_no_near_player"
    end

    local slots = director.GetAvailablePhysicalNPCSlots(player, group, nil)
    if slots <= 0 then
        return 0, math.max(30, math.floor((tonumber(director.PROXY_LOD_RETRY_SECONDS) or 18) * 60)), "proxy_lod_spawn_queue_cap"
    end

    return math.max(1, math.min(tonumber(requestedBatch) or 1, slots))
end

function NPCWorldDirectorBridge.EnforceProxyLODPhysicalCaps(director, reason)
    if not director.IsProxyLODEnabled() then return false end

    local gmd = director.EnsureData()
    local now = getGameTime():getWorldAgeHours()
    local protectedRadius = math.max(40, tonumber(director.PROXY_LOD_PROTECTED_RADIUS) or 128)
    local playerCap = director.GetProxyLODPlayerCap()
    local globalCap = math.max(1, tonumber(director.PROXY_LOD_MAX_REAL_NPC_GLOBAL) or 48)
    local candidates = {}
    local changed = false

    local function addCandidate(groupId, group, pressure, nearestDist)
        if not groupId or not group or not group.activated then return end
        if NPCWorldDirectorBridge.IsImportantPhysicalGroup(group) then return end
        if not director.CanDematerializePhysicalGroup(group) then return end

        local memberCount, cx, cy, cz = director.GetPhysicalGroupRuntimeInfo(groupId)
        if memberCount <= 0 then return end

        local dist = nearestDist
        if dist == nil then
            local _, nd = director.GetNearestPlayer(cx or group.x, cy or group.y, 999999)
            dist = nd
        end
        dist = tonumber(dist) or 999999
        if dist < protectedRadius then return end

        candidates[#candidates + 1] = {
            id = tostring(groupId),
            group = group,
            count = memberCount,
            distance = dist,
            pressure = tonumber(pressure) or 0,
            score = (tonumber(pressure) or 0) * 100000 + dist + memberCount * 12
        }
    end

    local playerList = getOnlinePlayers and getOnlinePlayers() or nil
    if playerList then
        for i = 0, playerList:size() - 1 do
            local player = playerList:get(i)
            if player and not player:isDead() then
                local totalNear = director.CountPhysicalNPCNearPlayer(player, director.ACTIVATION_RADIUS)
                if totalNear > playerCap then
                    for groupId, group in pairs(gmd.VirtualGroups) do
                        if group and group.activated then
                            local count, cx, cy = director.GetPhysicalGroupRuntimeInfo(groupId)
                            if count > 0 and cx and cy then
                                local dx = cx - player:getX()
                                local dy = cy - player:getY()
                                local dist = math.sqrt(dx * dx + dy * dy)
                                if dist <= (tonumber(director.ACTIVATION_RADIUS) or 260) + 80 then
                                    addCandidate(groupId, group, totalNear - playerCap, dist)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    local globalNow = director.CountPhysicalNPCGlobal(globalCap + 1)
    if globalNow > globalCap then
        for groupId, group in pairs(gmd.VirtualGroups) do
            if group and group.activated then
                addCandidate(groupId, group, globalNow - globalCap, nil)
            end
        end
    end

    if #candidates <= 0 then return false end

    table.sort(candidates, function(a, b)
        if a.score == b.score then return tostring(a.id) < tostring(b.id) end
        return a.score > b.score
    end)

    local maxRun = math.max(1, tonumber(director.PROXY_LOD_DEMATERIALIZE_PER_RUN) or 2)
    local done = 0
    local used = {}
    for _, c in ipairs(candidates) do
        if done >= maxRun then break end
        if c.id and not used[c.id] then
            used[c.id] = true
            local group = gmd.VirtualGroups[c.id] or c.group
            if group and group.activated and director.DematerializeFarPhysicalGroup(c.id, group) then
                group = gmd.VirtualGroups[c.id] or group
                if group then
                    group.proxyDematerializedAt = now
                    group.proxyHoldUntil = now + NPCWorldDirectorBridge.ProxyRetryHours(director)
                    group.lastActivationDeferReason = "proxy_lod_dematerialized"
                    group.updatedAt = now
                    gmd.VirtualGroups[c.id] = group
                end
                done = done + 1
                changed = true
                NPCWorldDirectorBridge.ProxyLog(director, NPC_WORLD_DIRECTOR_LOG_PREFIX .. " ProxyLOD dematerialized group " .. tostring(c.id) .. " count=" .. tostring(c.count) .. " reason=" .. tostring(reason or "cap"))
            end
        end
    end

    if changed then
        gmd.WorldDirector = gmd.WorldDirector or {}
        gmd.WorldDirector.proxyLOD = gmd.WorldDirector.proxyLOD or {}
        gmd.WorldDirector.proxyLOD.lastRunAt = now
        gmd.WorldDirector.proxyLOD.lastRunReason = reason or "cap"
        gmd.WorldDirector.proxyLOD.lastDematerialized = done
        gmd.WorldDirector.proxyLOD.playerCap = playerCap
        gmd.WorldDirector.proxyLOD.globalCap = globalCap
        TransmitNPCModData()
    end

    return changed
end

function NPCWorldDirectorBridge.GetPhysicalDeactivationRadius(director, group)
    local base = tonumber(director.PHYSICAL_DEACTIVATION_RADIUS) or 650
    local activation = tonumber(director.ACTIVATION_RADIUS) or tonumber(director.PHYSICAL_REACTIVATION_RADIUS) or 260
    local minRadius = activation + 60
    if NPCStreamingRuntimeBridge and NPCStreamingRuntimeBridge.IsTravelUnloading then
        local ok, active = pcall(function() return NPCStreamingRuntimeBridge.IsTravelUnloading() end)
        if ok and active then minRadius = activation + 30 end
    end

    if NPCWorldDirectorBridge.IsImportantPhysicalGroup(group) then
        return math.max(minRadius, tonumber(director.PHYSICAL_DEACTIVATION_IMPORTANT_RADIUS) or base)
    end

    local radius = base
    local level = NPCWorldDirectorBridge.PhysicalLoadLevel()
    if level >= 2 then
        radius = math.min(radius, tonumber(director.PHYSICAL_DEACTIVATION_CRITICAL_RADIUS) or radius)
    elseif level >= 1 then
        radius = math.min(radius, tonumber(director.PHYSICAL_DEACTIVATION_HIGH_LOAD_RADIUS) or radius)
    end

    if NPCStreamingRuntimeBridge and NPCStreamingRuntimeBridge.GetUnloadDespawnRadius then
        local ok, streamingRadius = pcall(function() return NPCStreamingRuntimeBridge.GetUnloadDespawnRadius(group, radius, activation) end)
        if ok and tonumber(streamingRadius) then radius = tonumber(streamingRadius) end
    end

    return math.max(minRadius, radius)
end

function NPCWorldDirectorBridge.CanDematerializePhysicalGroup(director, group)
    if not group then return false end
    if group.mercenaryHired or group.hired or group.isPlayerGuard or group.followPlayer or group.guardPlayer then return false end
    if group.spawnPending or (tonumber(group.spawnQueued) or 0) > 0 then return false end

    local minAge = tonumber(director.PHYSICAL_DEACTIVATION_MIN_AGE_HOURS) or 0
    if NPCStreamingRuntimeBridge and NPCStreamingRuntimeBridge.GetUnloadMinAgeHours then
        local ok, streamingMinAge = pcall(function() return NPCStreamingRuntimeBridge.GetUnloadMinAgeHours(minAge) end)
        if ok and tonumber(streamingMinAge) then minAge = tonumber(streamingMinAge) end
    end
    if minAge > 0 then
        local worldAge = getGameTime():getWorldAgeHours()
        local materializedAt = tonumber(group.materializedAt) or tonumber(group.activatedAt) or tonumber(group.updatedAt) or 0
        if materializedAt > 0 and worldAge - materializedAt < minAge then
            return false
        end
    end

    return true
end

function NPCWorldDirectorBridge.GetPhysicalCleanupIntervalTicks(director)
    local level = NPCWorldDirectorBridge.PhysicalLoadLevel()
    local interval = nil
    if level >= 2 then
        interval = math.max(60, tonumber(director.PHYSICAL_CLEANUP_CRITICAL_INTERVAL_TICKS) or 300)
    elseif level >= 1 then
        interval = math.max(60, tonumber(director.PHYSICAL_CLEANUP_HIGH_INTERVAL_TICKS) or 600)
    else
        interval = math.max(60, tonumber(director.PHYSICAL_CLEANUP_INTERVAL_TICKS) or 1200)
    end

    if NPCStreamingRuntimeBridge and NPCStreamingRuntimeBridge.GetUnloadCleanupIntervalTicks then
        local ok, streamingInterval = pcall(function() return NPCStreamingRuntimeBridge.GetUnloadCleanupIntervalTicks(interval) end)
        if ok and tonumber(streamingInterval) then interval = tonumber(streamingInterval) end
    end

    return math.max(15, math.floor(interval))
end

function NPCWorldDirectorBridge.GetPhysicalCleanupDematerializeBudget(director)
    if NPCStreamingRuntimeBridge and NPCStreamingRuntimeBridge.IsTravelUnloading then
        local ok, active = pcall(function() return NPCStreamingRuntimeBridge.IsTravelUnloading() end)
        if ok and active then
            return math.max(1, tonumber(director.PHYSICAL_CLEANUP_STREAMING_MAX_DEMATERIALIZE_PER_RUN) or 6)
        end
    end
    return math.max(1, tonumber(director.PHYSICAL_CLEANUP_MAX_DEMATERIALIZE_PER_RUN) or 3)
end

function NPCWorldDirectorBridge.DeferGroupActivation(director, group, reason, retryHours)
    if not group then return false end
    local worldAge = getGameTime():getWorldAgeHours()
    group.retryAfter = worldAge + (tonumber(retryHours) or tonumber(director.DEFERRED_ACTIVATION_RETRY_HOURS) or 0.012)
    group.lastActivationDeferReason = reason or "activation_deferred"
    group.updatedAt = worldAge
    if group.id then
        local gmd = director.EnsureData()
        gmd.VirtualGroups[tostring(group.id)] = group
        local marker = gmd.DebugMapMarkers[tostring(group.id)]
        if marker then
            marker.activationDeferred = true
            marker.activationDeferReason = group.lastActivationDeferReason
            marker.retryAfter = group.retryAfter
            marker.updatedAt = worldAge
            gmd.DebugMapMarkers[tostring(group.id)] = marker
            NPCWorldDirectorBridge.SendDebugMapUpdate(marker)
        end
    end
    return false
end

function NPCWorldDirectorBridge.PrepareActivationBudgets(director, gmd, worldAge)
    gmd = gmd or director.EnsureData()
    worldAge = worldAge or getGameTime():getWorldAgeHours()
    gmd.WorldDirector = gmd.WorldDirector or {}
    gmd.WorldDirector.activationPlayers = gmd.WorldDirector.activationPlayers or {}

    local budgets = {}
    local playerList = getOnlinePlayers and getOnlinePlayers() or nil
    if not playerList then return budgets end

    local threshold = tonumber(director.TELEPORT_DISTANCE_THRESHOLD) or 180
    local cooldownHours = tonumber(director.TELEPORT_ACTIVATION_COOLDOWN_HOURS) or 0

    for i=0, playerList:size()-1 do
        local player = playerList:get(i)
        if player and not player:isDead() then
            local key = NPCWorldDirectorBridge.PlayerKey(player) or tostring(i)
            local px = tonumber(player:getX()) or 0
            local py = tonumber(player:getY()) or 0
            local pz = tonumber(player:getZ()) or 0
            local prev = gmd.WorldDirector.activationPlayers[key]
            local teleported = false
            if prev and prev.x and prev.y then
                local d = NPCWorldDirectorBridge.Dist(px, py, tonumber(prev.x) or px, tonumber(prev.y) or py)
                if d >= threshold then
                    teleported = true
                    prev.teleportCooldownUntil = worldAge + cooldownHours
                    prev.lastTeleportDistance = d
                end
            else
                prev = {}
            end

            prev.x = px
            prev.y = py
            prev.z = pz
            prev.updatedAt = worldAge
            gmd.WorldDirector.activationPlayers[key] = prev

            budgets[key] = {
                key = key,
                player = player,
                x = px,
                y = py,
                z = pz,
                activations = 0,
                teleported = teleported,
                cooldownUntil = tonumber(prev.teleportCooldownUntil) or 0,
                npcNear = director.CountPhysicalNPCNearPlayer(player, director.ACTIVATION_RADIUS)
            }
        end
    end

    return budgets
end

function NPCWorldDirectorBridge.IsPlayerActivationCoolingDown(director, player)
    local key = NPCWorldDirectorBridge.PlayerKey(player)
    if not key then return false end
    local gmd = director.EnsureData()
    local state = gmd.WorldDirector and gmd.WorldDirector.activationPlayers and gmd.WorldDirector.activationPlayers[key]
    if not state then return false end
    return (tonumber(state.teleportCooldownUntil) or 0) > getGameTime():getWorldAgeHours()
end

function NPCWorldDirectorBridge.IsPlayerOnDebugMarker(director, group, player)
    if not group or not player then return false end
    if not director.IsPlayerActivationCoolingDown(player) then return false end

    local radius = tonumber(director.TELEPORT_MARKER_MATERIALIZE_RADIUS) or 36
    if radius <= 0 then return false end

    local gx = tonumber(group.x)
    local gy = tonumber(group.y)
    if not gx or not gy then return false end

    return NPCWorldDirectorBridge.Dist(gx, gy, player:getX(), player:getY()) <= radius
end

function NPCWorldDirectorBridge.GetActivationPriority(_director, group, player, distance)
    local score = tonumber(distance) or 999999
    if not group then return score end
    if group.bountyHunter or group.targetClass == "bounty_hunt" then score = score - 5000 end
    if group.inBattle then score = score - 1600 end
    if group.strategicGroup or group.checkpointId or group.homeBaseId then score = score - 900 end
    if group.leaderId or group.isFactionLeader then score = score - 700 end
    if group.economyConvoy or group.convoyId then score = score - 350 end
    if group.roadPatrol then score = score - 150 end
    return score
end

function NPCWorldDirectorBridge.IsCriticalCheckpointActivation(director, group, player, distance)
    if not (director and group and player) then return false end
    if not (group.checkpointId or group.checkpointGuard == true or group.state == "checkpoint_patrol") then return false end
    local dist = tonumber(distance)
    if not dist then
        local px = player.getX and player:getX() or nil
        local py = player.getY and player:getY() or nil
        if not (px and py and group.x and group.y) then return false end
        local dx = px - group.x
        local dy = py - group.y
        dist = math.sqrt(dx * dx + dy * dy)
    end
    return dist <= (tonumber(director.CHECKPOINT_FORCE_ACTIVATION_RADIUS) or 90)
end

function NPCWorldDirectorBridge.CountInactiveVirtualGroupsNear(director, group, radius, maxCount)
    if not (director and director.EnsureData and group and group.x and group.y) then return 0 end
    local gmd = director.EnsureData()
    if not (gmd and type(gmd.VirtualGroups) == "table") then return 0 end
    radius = tonumber(radius) or 140
    local r2 = radius * radius
    local count = 0
    for _, other in pairs(gmd.VirtualGroups) do
        if type(other) == "table" and other ~= group and other.activated ~= true and other.x and other.y then
            local dx = (tonumber(other.x) or 0) - (tonumber(group.x) or 0)
            local dy = (tonumber(other.y) or 0) - (tonumber(group.y) or 0)
            if dx * dx + dy * dy <= r2 then
                count = count + 1
                if maxCount and count >= maxCount then return count end
            end
        end
    end
    return count
end

function NPCWorldDirectorBridge.CanActivateGroupForPlayer(director, group, player, budget, totalActivations, distance)
    if not group or not player or not budget then return false end
    local criticalCheckpoint = NPCWorldDirectorBridge.IsCriticalCheckpointActivation(director, group, player, distance)
    local teleportMarkerEntry = director.TELEPORT_MARKER_BYPASS_DEFERS ~= false and NPCWorldDirectorBridge.IsPlayerOnDebugMarker(director, group, player)
    local urgentMarkerActivation = criticalCheckpoint or teleportMarkerEntry
    local physicalCount = director.GetPhysicalGroupCount()
    local hardCap = tonumber(director.MAX_PHYSICAL_GROUPS) or 20
    if physicalCount >= hardCap then
        if not urgentMarkerActivation or physicalCount >= hardCap + 1 then
            return director.DeferGroupActivation(group, teleportMarkerEntry and "teleport_marker_physical_group_cap" or "physical_group_cap")
        end
    end

    if not urgentMarkerActivation then
        local clusterMax = tonumber(director.VIRTUAL_CLUSTER_ACTIVATION_MAX) or 0
        if clusterMax > 0 and group.inBattle ~= true then
            local clusterCount = NPCWorldDirectorBridge.CountInactiveVirtualGroupsNear(director, group, director.VIRTUAL_CLUSTER_ACTIVATION_RADIUS, clusterMax + 1)
            if clusterCount > clusterMax then
                return director.DeferGroupActivation(group, "virtual_cluster_density", 0.02)
            end
        end

        local directorBrain = NPCWorldDirectorBridge.GetDirectorBrain()
        if directorBrain and directorBrain.ShouldDeferActivation then
            local pressureReason, pressureRetry = directorBrain.ShouldDeferActivation(group, player, budget)
            if pressureReason then
                return director.DeferGroupActivation(group, pressureReason, pressureRetry)
            end
        end

        if NPCStreamingRuntimeBridge and NPCStreamingRuntimeBridge.ShouldDeferActivation then
            local streamingReason, streamingRetry = NPCStreamingRuntimeBridge.ShouldDeferActivation(group, player, budget)
            if streamingReason then
                return director.DeferGroupActivation(group, streamingReason, streamingRetry)
            end
        end

        if NPCCrowdBudgetBridge and NPCCrowdBudgetBridge.ShouldDeferActivation then
            local crowdReason, crowdRetry = NPCCrowdBudgetBridge.ShouldDeferActivation(group, player, budget)
            if crowdReason then
                return director.DeferGroupActivation(group, crowdReason, crowdRetry)
            end
        end

        local proxyReason, proxyRetry = director.ShouldDeferForProxyLOD(group, player, budget)
        if proxyReason then
            return director.DeferGroupActivation(group, proxyReason, proxyRetry)
        end

        if (tonumber(totalActivations) or 0) >= (tonumber(director.MAX_GROUP_ACTIVATIONS_PER_UPDATE) or 1) then
            return director.DeferGroupActivation(group, "update_activation_budget")
        end

        if (tonumber(budget.activations) or 0) >= (tonumber(director.MAX_GROUP_ACTIVATIONS_PER_PLAYER) or 1) then
            return director.DeferGroupActivation(group, "player_activation_budget")
        end
    end

    if director.DEFER_ACTIVATION_WHEN_NPC_NEAR_PLAYER and not urgentMarkerActivation then
        local softCap = tonumber(director.ACTIVATION_NPC_SOFT_CAP_PER_PLAYER) or 0
        if softCap > 0 then
            local projected = (tonumber(budget.npcNear) or 0) + director.GetGroupMemberCount(group)
            if projected > softCap then
                return director.DeferGroupActivation(group, "npc_soft_cap_near_player")
            end
        end
    end

    return true
end

-- Stage 48: neutral battle-remains backend.
-- The compatibility world director keeps the public legacy world-director entry points,
-- while battle aftermath records, dead-body materialization and debug marker
-- cleanup live here.

NPCWorldDirectorBridge.BattleMemberOffsets = NPCWorldDirectorBridge.BattleMemberOffsets or {
    {x=0, y=0}, {x=1, y=0}, {x=-1, y=0}, {x=0, y=1}, {x=0, y=-1},
    {x=1, y=1}, {x=-1, y=1}, {x=1, y=-1}, {x=-1, y=-1},
    {x=2, y=0}, {x=-2, y=0}, {x=0, y=2}, {x=0, y=-2}
}

function NPCWorldDirectorBridge.BattleMemberOffset(index)
    local offsets = NPCWorldDirectorBridge.BattleMemberOffsets
    local count = #offsets
    if count <= 0 then return {x=0, y=0} end
    return offsets[((tonumber(index) or 1) - 1) % count + 1]
end

function NPCWorldDirectorBridge.BattleRemainsDistanceSq(record, x, y, z)
    if type(record) ~= "table" then return nil end
    local rx = tonumber(record.x)
    local ry = tonumber(record.y)
    if not rx or not ry then return nil end
    local rz = math.floor(tonumber(record.z) or 0)
    if z ~= nil and rz ~= math.floor(tonumber(z) or 0) then return nil end
    local dx = rx - (tonumber(x) or 0)
    local dy = ry - (tonumber(y) or 0)
    return dx * dx + dy * dy
end

function NPCWorldDirectorBridge.FindNearbyBattleRemains(gmd, x, y, z, radius)
    if type(gmd) ~= "table" or type(gmd.BattleRemains) ~= "table" then return nil end
    local r = tonumber(radius) or 0
    if r <= 0 then return nil end
    local r2 = r * r
    for id, record in pairs(gmd.BattleRemains) do
        local d2 = NPCWorldDirectorBridge.BattleRemainsDistanceSq(record, x, y, z)
        if d2 and d2 <= r2 then
            return id, record
        end
    end
    return nil
end

function NPCWorldDirectorBridge.TableCount(t)
    local count = 0
    if type(t) == "table" then
        for _, _ in pairs(t) do count = count + 1 end
    end
    return count
end

function NPCWorldDirectorBridge.CompactBattleMember(member)
    if type(member) ~= "table" then return {} end
    return {
        uid = member.uid or member.persistentId,
        outfit = member.outfit,
        femaleChance = member.femaleChance,
        patrolColor = member.patrolColor,
        factionSide = member.factionSide,
        faction = member.faction,
        side = member.side,
        role = member.role,
        tacticalRole = member.tacticalRole
    }
end

function NPCWorldDirectorBridge.MakeBattleRemainsId(battleId, groupId, worldAge)
    local tick = math.floor((tonumber(worldAge) or 0) * 100)
    return "NR" .. tostring(battleId or "0") .. "_" .. tostring(groupId or "0") .. "_" .. tostring(tick)
end

function NPCWorldDirectorBridge.SafeAddBattleBlood(square, amount)
    if not square then return 0 end
    local okChunk, chunk = pcall(function() return square:getChunk() end)
    if not okChunk or not chunk or not chunk.addBloodSplat then return 0 end

    local x, y, z = 0, 0, 0
    local okX, sx = pcall(function() return square:getX() end)
    local okY, sy = pcall(function() return square:getY() end)
    local okZ, sz = pcall(function() return square:getZ() end)
    if okX then x = tonumber(sx) or 0 end
    if okY then y = tonumber(sy) or 0 end
    if okZ then z = tonumber(sz) or 0 end

    local added = 0
    amount = tonumber(amount) or 0
    for _=1, amount do
        local ok = pcall(function()
            chunk:addBloodSplat(x + ZombRandFloat(0.1, 0.9), y + ZombRandFloat(0.1, 0.9), z, ZombRand(20))
        end)
        if ok then added = added + 1 end
    end
    return added
end

function NPCWorldDirectorBridge.SafeAddBattleDebris(square, itemType)
    if not square or not itemType then return false end
    return pcall(function()
        square:AddWorldInventoryItem(itemType, ZombRandFloat(0.18, 0.82), ZombRandFloat(0.18, 0.82), 0)
    end) == true
end

function NPCWorldDirectorBridge.SafeAddBattleAftermathProp(square, candidates)
    if not square or type(candidates) ~= "table" then return nil end
    for i = 1, #candidates do
        local itemType = candidates[i]
        if itemType then
            local ok = pcall(function()
                square:AddWorldInventoryItem(itemType, ZombRandFloat(0.14, 0.86), ZombRandFloat(0.14, 0.86), 0)
            end)
            if ok then return itemType end
        end
    end
    return nil
end

function NPCWorldDirectorBridge.BattleAftermathPropCandidates(index)
    local sets = NPCWorldDirectorBridge.BattleAftermathPropSets
    if type(sets) ~= "table" then
        sets = {
            { "Base.ScrapMetal", "Base.SmallSheetMetal", "Base.SheetMetal", "Base.MetalPipe", "Base.MetalBar" },
            { "Base.Plank", "Base.UnusableWood", "Base.NailsBox", "Base.Nails" },
            { "Base.BrokenGlass", "Base.Garbagebag", "Base.RippedSheetsDirty", "Base.BandageDirty" },
            { "Base.EmptyPetrolCan", "Base.PetrolCanEmpty", "Base.WaterBottleEmpty", "Base.PopEmpty", "Base.TinCanEmpty" },
            { "Base.NormalTire1", "Base.NormalTire2", "Base.NormalTire3", "Base.OldTire1", "Base.OldTire2", "Base.OldTire3" }
        }
        NPCWorldDirectorBridge.BattleAftermathPropSets = sets
    end
    local count = #sets
    if count <= 0 then return nil end
    return sets[((tonumber(index) or 1) - 1) % count + 1]
end


function NPCWorldDirectorBridge.UrbanCoverPropCandidates(index)
    local sets = NPCWorldDirectorBridge.UrbanCoverPropSets
    if type(sets) ~= "table" then
        sets = {
            { "Base.NormalTire1", "Base.NormalTire2", "Base.NormalTire3", "Base.OldTire1", "Base.OldTire2", "Base.OldTire3" },
            { "Base.ScrapMetal", "Base.SmallSheetMetal", "Base.SheetMetal", "Base.MetalPipe", "Base.MetalBar" },
            { "Base.Plank", "Base.UnusableWood", "Base.NailsBox", "Base.Nails" },
            { "Base.Hinge", "Base.Doorknob", "Base.Screws", "Base.MetalPipe" },
            { "Base.EngineParts", "Base.ScrapMetal", "Base.MetalBar", "Base.EmptyPetrolCan", "Base.PetrolCanEmpty" },
            { "Base.BrokenGlass", "Base.Garbagebag", "Base.EmptyPetrolCan", "Base.WaterBottleEmpty", "Base.PopEmpty", "Base.TinCanEmpty" }
        }
        NPCWorldDirectorBridge.UrbanCoverPropSets = sets
    end
    local count = #sets
    if count <= 0 then return nil end
    return sets[((tonumber(index) or 1) - 1) % count + 1]
end

function NPCWorldDirectorBridge.IsUrbanCoverPropItem(fullType)
    fullType = tostring(fullType or "")
    return fullType == "Base.NormalTire1"
        or fullType == "Base.NormalTire2"
        or fullType == "Base.NormalTire3"
        or fullType == "Base.OldTire1"
        or fullType == "Base.OldTire2"
        or fullType == "Base.OldTire3"
        or fullType == "Base.ScrapMetal"
        or fullType == "Base.SmallSheetMetal"
        or fullType == "Base.SheetMetal"
        or fullType == "Base.MetalPipe"
        or fullType == "Base.MetalBar"
        or fullType == "Base.Plank"
        or fullType == "Base.UnusableWood"
        or fullType == "Base.NailsBox"
        or fullType == "Base.Nails"
        or fullType == "Base.Hinge"
        or fullType == "Base.Doorknob"
        or fullType == "Base.Screws"
        or fullType == "Base.EngineParts"
        or fullType == "Base.BrokenGlass"
        or fullType == "Base.Garbagebag"
        or fullType == "Base.EmptyPetrolCan"
        or fullType == "Base.PetrolCanEmpty"
        or fullType == "Base.WaterBottleEmpty"
        or fullType == "Base.PopEmpty"
        or fullType == "Base.TinCanEmpty"
end

function NPCWorldDirectorBridge.EnsureUrbanCoverProps(gmd)
    if not gmd then return {} end
    if type(gmd.UrbanCoverProps) ~= "table" then gmd.UrbanCoverProps = {} end
    return gmd.UrbanCoverProps
end

function NPCWorldDirectorBridge.PruneUrbanCoverProps(director, gmd)
    local records = NPCWorldDirectorBridge.EnsureUrbanCoverProps(gmd)
    local maxRecords = math.max(0, tonumber(director and director.URBAN_COVER_PROPS_MAX_RECORDS) or 120)
    if maxRecords <= 0 then
        for id, _ in pairs(records) do records[id] = nil end
        return 0
    end

    local count = NPCWorldDirectorBridge.CountTable(records)
    local removed = 0
    while count > maxRecords do
        local oldestId, oldestAt = nil, nil
        for id, record in pairs(records) do
            local at = type(record) == "table" and tonumber(record.spawnedAt) or nil
            if not oldestId or (oldestAt == nil and at ~= nil) or (at ~= nil and oldestAt ~= nil and at < oldestAt) then
                oldestId = id
                oldestAt = at
            end
        end
        if not oldestId then break end
        records[oldestId] = nil
        removed = removed + 1
        count = count - 1
    end
    return removed
end

function NPCWorldDirectorBridge.IsNearUrbanCoverProp(records, x, y, z, minSpacing)
    if type(records) ~= "table" or not x or not y then return false end
    local spacing = tonumber(minSpacing) or 18
    local spacing2 = spacing * spacing
    local iz = math.floor(tonumber(z) or 0)
    for _, record in pairs(records) do
        if type(record) == "table" and record.x and record.y then
            local rz = math.floor(tonumber(record.z) or 0)
            if rz == iz then
                local dx = (tonumber(record.x) or 0) - x
                local dy = (tonumber(record.y) or 0) - y
                if dx * dx + dy * dy < spacing2 then return true end
            end
        end
    end
    return false
end

function NPCWorldDirectorBridge.GetSquareWorldItemFullType(obj)
    if not obj then return nil end
    local okItem, item = pcall(function() return obj:getItem() end)
    if not okItem or not item then return nil end
    local okFull, fullType = pcall(function() return item:getFullType() end)
    if okFull and fullType then return tostring(fullType) end
    local okType, itemType = pcall(function() return item:getType() end)
    if okType and itemType then return "Base." .. tostring(itemType) end
    return nil
end

function NPCWorldDirectorBridge.SquareHasUrbanCoverPropItem(square)
    if not square then return false end
    local ok, objects = pcall(function() return square:getWorldObjects() end)
    if not ok or not objects then return false end
    local size = 0
    local okSize, result = pcall(function() return objects:size() end)
    if okSize and result then size = tonumber(result) or 0 end
    if size <= 0 then return false end
    for i = 0, size - 1 do
        local obj = objects:get(i)
        local fullType = NPCWorldDirectorBridge.GetSquareWorldItemFullType(obj)
        if NPCWorldDirectorBridge.IsUrbanCoverPropItem(fullType) then return true end
    end
    return false
end

function NPCWorldDirectorBridge.IsOutdoorBuildableCoverSquare(square)
    if not square then return false end
    local okRoom, room = pcall(function() return square:getRoom() end)
    if okRoom and room then return false end
    local okBuilding, building = pcall(function() return square:getBuilding() end)
    if okBuilding and building then return false end
    local okSolid, solid = pcall(function() return square:isSolid() or square:isSolidTrans() end)
    if okSolid and solid then return false end
    local okFree, free = pcall(function() return square:isFree(false) end)
    if okFree and free == false then return false end
    if NPCWorldDirectorBridge.SquareHasUrbanCoverPropItem(square) then return false end
    return true
end

function NPCWorldDirectorBridge.SquareNearBuildingExterior(square, radius)
    if not square or not getCell then return false end
    local cell = getCell()
    if not cell then return false end
    local sx, sy, sz = square:getX(), square:getY(), square:getZ()
    local scan = math.max(2, tonumber(radius) or 7)
    for dx = -scan, scan do
        for dy = -scan, scan do
            if dx ~= 0 or dy ~= 0 then
                local nsq = cell:getGridSquare(sx + dx, sy + dy, sz)
                if nsq then
                    local okRoom, room = pcall(function() return nsq:getRoom() end)
                    if okRoom and room then return true end
                    local okBuilding, building = pcall(function() return nsq:getBuilding() end)
                    if okBuilding and building then return true end
                end
            end
        end
    end
    return false
end

function NPCWorldDirectorBridge.FindUrbanCoverPropSquare(director, player, gmd)
    if not player or not getCell then return nil end
    local cell = getCell()
    if not cell then return nil end

    local radius = math.max(12, tonumber(director and director.URBAN_COVER_PROPS_RADIUS) or 58)
    local attempts = math.max(6, tonumber(director and director.URBAN_COVER_PROPS_ATTEMPTS_PER_PLAYER) or 34)
    local buildingRadius = math.max(2, tonumber(director and director.URBAN_COVER_PROPS_BUILDING_RADIUS) or 7)
    local records = NPCWorldDirectorBridge.EnsureUrbanCoverProps(gmd)
    local minSpacing = math.max(6, tonumber(director and director.URBAN_COVER_PROPS_MIN_SPACING) or 18)
    local px = math.floor(player:getX())
    local py = math.floor(player:getY())
    local pz = math.floor(player:getZ() or 0)

    for _ = 1, attempts do
        local dx = ZombRand and (ZombRand(radius * 2 + 1) - radius) or math.random(-radius, radius)
        local dy = ZombRand and (ZombRand(radius * 2 + 1) - radius) or math.random(-radius, radius)
        if dx ~= 0 or dy ~= 0 then
            local x = px + dx
            local y = py + dy
            local sq = cell:getGridSquare(x, y, pz)
            if sq and NPCWorldDirectorBridge.IsOutdoorBuildableCoverSquare(sq) then
                if not NPCWorldDirectorBridge.IsNearUrbanCoverProp(records, x, y, pz, minSpacing) then
                    if NPCWorldDirectorBridge.SquareNearBuildingExterior(sq, buildingRadius) then
                        return sq
                    end
                end
            end
        end
    end

    return nil
end

function NPCWorldDirectorBridge.AddUrbanCoverPropItem(square, setIndex)
    if not square then return nil end
    local candidates = NPCWorldDirectorBridge.UrbanCoverPropCandidates(setIndex)
    if type(candidates) ~= "table" then return nil end
    return NPCWorldDirectorBridge.SafeAddBattleAftermathProp(square, candidates)
end

function NPCWorldDirectorBridge.SpawnUrbanCoverPropCluster(director, gmd, square)
    if not (director and gmd and square) then return 0 end
    local records = NPCWorldDirectorBridge.EnsureUrbanCoverProps(gmd)
    local x, y, z = square:getX(), square:getY(), square:getZ()
    local minSpacing = math.max(6, tonumber(director.URBAN_COVER_PROPS_MIN_SPACING) or 18)
    if NPCWorldDirectorBridge.IsNearUrbanCoverProp(records, x, y, z, minSpacing) then return 0 end

    local maxItems = math.max(1, math.min(8, tonumber(director.URBAN_COVER_PROPS_MAX_ITEMS_PER_CLUSTER) or 4))
    local targetItems = math.max(1, math.min(maxItems, 2 + (ZombRand and ZombRand(math.max(1, maxItems)) or math.random(0, math.max(1, maxItems - 1)))))
    local offsets = {{0,0},{1,0},{0,1},{-1,0},{0,-1},{1,1},{-1,1},{1,-1},{-1,-1},{2,0},{0,2},{-2,0},{0,-2}}
    local cell = getCell and getCell() or nil
    if not cell then return 0 end

    local spawned = 0
    local itemTypes = {}
    for i = 1, #offsets do
        if spawned >= targetItems then break end
        local ox, oy = offsets[i][1], offsets[i][2]
        local sq = cell:getGridSquare(x + ox, y + oy, z)
        if sq and NPCWorldDirectorBridge.IsOutdoorBuildableCoverSquare(sq) then
            local itemType = NPCWorldDirectorBridge.AddUrbanCoverPropItem(sq, i)
            if itemType then
                spawned = spawned + 1
                itemTypes[#itemTypes + 1] = itemType
            end
        end
    end

    if spawned <= 0 then return 0 end
    local okAge, worldAge = pcall(function() return getGameTime():getWorldAgeHours() end)
    local id = "urban_cover_" .. tostring(x) .. "_" .. tostring(y) .. "_" .. tostring(z)
    records[id] = {
        id = id,
        kind = "urban_cover_prop",
        x = x,
        y = y,
        z = z,
        spawnedAt = okAge and worldAge or 0,
        count = spawned,
        items = itemTypes
    }
    NPCWorldDirectorBridge.PruneUrbanCoverProps(director, gmd)
    NPCWorldDirectorBridge.Log(director, "[NPCWorldDirector] Spawned urban cover props " .. tostring(id) .. " items=" .. tostring(spawned))
    return spawned
end

function NPCWorldDirectorBridge.UpdateUrbanCoverProps(director)
    if not (director and director.URBAN_COVER_PROPS_ENABLED and getOnlinePlayers) then return 0 end
    local gmd = director.EnsureData and director.EnsureData() or NPCWorldDirectorBridge.EnsureData(director)
    if not gmd then return 0 end
    NPCWorldDirectorBridge.PruneUrbanCoverProps(director, gmd)

    local players = getOnlinePlayers()
    if not players then return 0 end
    local size = 0
    local okSize, result = pcall(function() return players:size() end)
    if okSize and result then size = tonumber(result) or 0 end
    if size <= 0 then return 0 end

    local maxClusters = math.max(0, tonumber(director.URBAN_COVER_PROPS_MAX_CLUSTERS_PER_RUN) or 2)
    if maxClusters <= 0 then return 0 end

    local spawnedClusters = 0
    local spawnedItems = 0
    for i = 0, size - 1 do
        if spawnedClusters >= maxClusters then break end
        local player = players:get(i)
        if player then
            local square = NPCWorldDirectorBridge.FindUrbanCoverPropSquare(director, player, gmd)
            if square then
                local added = NPCWorldDirectorBridge.SpawnUrbanCoverPropCluster(director, gmd, square)
                if added > 0 then
                    spawnedClusters = spawnedClusters + 1
                    spawnedItems = spawnedItems + added
                end
            end
        end
    end

    return spawnedItems
end


function NPCWorldDirectorBridge.SpawnBattleCorpse(member, square, x, y, z)
    if not square then return false end
    if not (NPCCompatibilityBridge and NPCCompatibilityBridge.AddZombiesInOutfit) then return false end

    member = type(member) == "table" and member or {}
    local fallOnFront = ZombRand(2) == 0
    local okSpawn, zombieList = pcall(function()
        return NPCCompatibilityBridge.AddZombiesInOutfit(
            math.floor(tonumber(x) or 0),
            math.floor(tonumber(y) or 0),
            math.floor(tonumber(z) or 0),
            member.outfit,
            tonumber(member.femaleChance) or 50,
            false,
            fallOnFront,
            false,
            false,
            false,
            false,
            0.1
        )
    end)
    if not okSpawn or not zombieList then return false end

    local okSize, size = pcall(function() return zombieList:size() end)
    if not okSize or (tonumber(size) or 0) <= 0 then return false end

    local zombie = zombieList:get(0)
    if not zombie then return false end
    pcall(function() zombie:setHealth(0) end)

    if IsoDeadBody and IsoDeadBody.new then
        local okBody = pcall(function() IsoDeadBody.new(zombie, false) end)
        if okBody then return true end
    end
    if zombie.Kill and getCell and getCell() and getCell().getFakeZombieForHit then
        return pcall(function() zombie:Kill(getCell():getFakeZombieForHit(), true) end) == true
    end
    return false
end

function NPCWorldDirectorBridge.RemoveBattleRemainsRecord(director, gmd, id)
    if not gmd or not id then return end
    local sid = tostring(id)
    if type(gmd.BattleRemains) == "table" then gmd.BattleRemains[sid] = nil end
    if type(gmd.DebugMapMarkers) == "table" then gmd.DebugMapMarkers[sid] = nil end
    NPCWorldDirectorBridge.SendDebugMapRemove(sid)
end

function NPCWorldDirectorBridge.PruneBattleRemains(director, gmd, worldAge)
    if type(gmd) ~= "table" or type(gmd.BattleRemains) ~= "table" then return false end

    local changed = false
    local maxRecords = tonumber(director and director.BATTLE_REMAINS_MAX_RECORDS) or 48
    if maxRecords < 8 then maxRecords = 8 end
    local decayHours = tonumber(director and director.BATTLE_REMAINS_DECAY_HOURS) or (24 * 21)
    if worldAge == nil and getGameTime then
        local ok, value = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok then worldAge = value end
    end
    worldAge = tonumber(worldAge) or 0

    for id, record in pairs(gmd.BattleRemains) do
        if type(record) ~= "table" then
            NPCWorldDirectorBridge.RemoveBattleRemainsRecord(director, gmd, id)
            changed = true
        else
            local baseAt = tonumber(record.materializedAt) or tonumber(record.createdAt) or worldAge
            if record.materialized and decayHours > 0 and worldAge - baseAt > decayHours then
                NPCWorldDirectorBridge.RemoveBattleRemainsRecord(director, gmd, id)
                changed = true
            end
        end
    end

    local count = NPCWorldDirectorBridge.TableCount(gmd.BattleRemains)
    while count > maxRecords do
        local oldestId, oldestAt, oldestMaterialized = nil, nil, false
        for id, record in pairs(gmd.BattleRemains) do
            if type(record) == "table" then
                local at = tonumber(record.createdAt) or 0
                local materialized = record.materialized == true
                if not oldestId or (materialized and not oldestMaterialized) or (materialized == oldestMaterialized and (oldestAt == nil or at < oldestAt)) then
                    oldestId = id
                    oldestAt = at
                    oldestMaterialized = materialized
                end
            end
        end
        if not oldestId then break end
        NPCWorldDirectorBridge.RemoveBattleRemainsRecord(director, gmd, oldestId)
        changed = true
        count = count - 1
    end
    return changed
end

function NPCWorldDirectorBridge.CreateBattleRemains(director, gmd, loser, winner, battleId, membersSnapshot, worldAge)
    if director and director.SP_BOOTSTRAP_GATE_ROAD_BATTLES ~= false then
        local gate, retry, reason = npc_wd_shouldBootstrapGate(director, "battle_remains")
        if gate then npc_wd_recordBootstrapGate("battle_remains", retry, reason); return false end
    end
    if type(gmd) ~= "table" or type(loser) ~= "table" or loser.id == nil then return false end
    if type(gmd.BattleRemains) ~= "table" then gmd.BattleRemains = {} end
    if type(gmd.DebugMapMarkers) ~= "table" then gmd.DebugMapMarkers = {} end

    if worldAge == nil and getGameTime then
        local ok, value = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok then worldAge = value end
    end
    worldAge = tonumber(worldAge) or 0

    local maxBodies = tonumber(director and director.BATTLE_REMAINS_MAX_BODIES) or 2
    if maxBodies < 0 then maxBodies = 0 end

    local members = {}
    if type(membersSnapshot) == "table" then
        for _, member in pairs(membersSnapshot) do
            if #members >= maxBodies then break end
            members[#members + 1] = NPCWorldDirectorBridge.CompactBattleMember(member)
        end
    end
    if #members <= 0 and maxBodies > 0 then
        members[1] = NPCWorldDirectorBridge.CompactBattleMember(type(loser.members) == "table" and loser.members[1] or nil)
    end

    local lx = tonumber(loser.x) or 0
    local ly = tonumber(loser.y) or 0
    local wx = type(winner) == "table" and tonumber(winner.x) or nil
    local wy = type(winner) == "table" and tonumber(winner.y) or nil
    local x = wx and math.floor((lx + wx) / 2) or math.floor(lx)
    local y = wy and math.floor((ly + wy) / 2) or math.floor(ly)
    local z = tonumber(loser.z) or (type(winner) == "table" and tonumber(winner.z)) or 0
    local spacing = tonumber(director and director.BATTLE_REMAINS_MIN_SPACING) or 96
    local nearbyId, nearbyRecord = NPCWorldDirectorBridge.FindNearbyBattleRemains(gmd, x, y, z, spacing)
    if nearbyId and type(nearbyRecord) == "table" then
        nearbyRecord.count = math.min((tonumber(nearbyRecord.count) or 0) + #members, tonumber(director and director.BATTLE_REMAINS_MAX_BODIES) or 2)
        nearbyRecord.updatedAt = worldAge
        nearbyRecord.lastBattleId = battleId
        gmd.BattleRemains[tostring(nearbyId)] = nearbyRecord
        return true
    end

    local id = NPCWorldDirectorBridge.MakeBattleRemainsId(battleId, loser.id, worldAge)

    local winnerGroupId = type(winner) == "table" and winner.id ~= nil and tostring(winner.id) or nil
    local record = {
        id = id,
        x = x,
        y = y,
        z = z,
        count = #members,
        members = members,
        loserGroupId = tostring(loser.id),
        winnerGroupId = winnerGroupId,
        battleId = battleId,
        hostile = loser.hostile,
        friendly = false,
        factionSide = loser.factionSide,
        faction = loser.faction,
        side = loser.side,
        patrolColor = loser.patrolColor,
        roadPatrol = loser.roadPatrol or false,
        createdAt = worldAge,
        materialized = false
    }

    gmd.BattleRemains[id] = record
    gmd.DebugMapMarkers[id] = {
        id = id,
        markerType = "battle_remains",
        x = x,
        y = y,
        z = z,
        name = "Aftermath " .. tostring(loser.id),
        count = #members,
        hostile = loser.hostile,
        friendly = false,
        factionSide = loser.factionSide,
        faction = loser.faction,
        side = loser.side,
        patrolColor = loser.patrolColor,
        roadPatrol = loser.roadPatrol or false,
        virtual = true,
        active = false,
        dead = true,
        state = "battle_remains",
        battleRemains = true,
        battleId = battleId,
        loserGroupId = tostring(loser.id),
        winnerGroupId = winnerGroupId,
        updatedAt = worldAge
    }

    NPCWorldDirectorBridge.SendDebugMapUpdate(gmd.DebugMapMarkers[id])
    NPCWorldDirectorBridge.DirectorEvent(director, "battle_remains_created", x, y, z, {
        battleId = tostring(battleId or ""),
        loserGroupId = tostring(loser.id),
        winnerGroupId = winnerGroupId or "",
        count = #members
    })
    NPCWorldDirectorBridge.PruneBattleRemains(director, gmd, worldAge)
    return true
end

function NPCWorldDirectorBridge.MaterializeBattleRemains(director, gmd, remainsId, record, player)
    if type(gmd) ~= "table" or remainsId == nil or type(record) ~= "table" or record.materialized then return false end
    if not (director and director.FindLoadedSpawnSquareNear) then return false end

    local baseX = math.floor(tonumber(record.x) or 0)
    local baseY = math.floor(tonumber(record.y) or 0)
    local baseZ = math.floor(tonumber(record.z) or 0)
    local baseSquare = director.FindLoadedSpawnSquareNear(baseX, baseY, baseZ, 36)
    if not baseSquare then return false end

    if director.BATTLE_REMAINS_MATERIALIZE_ENABLED ~= true and director.BATTLE_REMAINS_PROP_ONLY ~= true then
        record.materialized = true
        local okAge, worldAge = pcall(function() return getGameTime():getWorldAgeHours() end)
        record.materializedAt = okAge and worldAge or record.materializedAt
        record.spawnedBodies = 0
        record.suppressed = true
        gmd.BattleRemains[tostring(remainsId)] = record
        if type(gmd.DebugMapMarkers) == "table" then gmd.DebugMapMarkers[tostring(remainsId)] = nil end
        NPCWorldDirectorBridge.SendDebugMapRemove(tostring(remainsId))
        return true
    end

    local spawnedBodies = 0
    local spawnedProps = 0
    local members = type(record.members) == "table" and record.members or {}
    local debrisCap = tonumber(director.BATTLE_REMAINS_MAX_DEBRIS) or 8
    if debrisCap < 1 then debrisCap = 1 end
    local intensity = math.max(tonumber(record.count) or 0, #members, 1)
    local debrisCount = math.min(debrisCap, 4 + intensity + ZombRand(3))
    for i=1, debrisCount do
        local offset = NPCWorldDirectorBridge.BattleMemberOffset(i)
        local square = director.FindLoadedSpawnSquareNear(baseX + offset.x + ZombRand(-4, 5), baseY + offset.y + ZombRand(-4, 5), baseZ, 8) or baseSquare
        if square then
            local candidates = NPCWorldDirectorBridge.BattleAftermathPropCandidates(i + ZombRand(4))
            if NPCWorldDirectorBridge.SafeAddBattleAftermathProp(square, candidates) then
                spawnedProps = spawnedProps + 1
            end
            if spawnedProps <= 2 and ZombRand(3) == 0 then
                NPCWorldDirectorBridge.SafeAddBattleBlood(square, 1)
            end
        end
    end

    record.materialized = true
    local okAge, worldAge = pcall(function() return getGameTime():getWorldAgeHours() end)
    record.materializedAt = okAge and worldAge or record.materializedAt
    record.spawnedBodies = spawnedBodies
    record.spawnedProps = spawnedProps
    gmd.BattleRemains[tostring(remainsId)] = record
    if type(gmd.DebugMapMarkers) == "table" then gmd.DebugMapMarkers[tostring(remainsId)] = nil end

    NPCWorldDirectorBridge.SendDebugMapRemove(tostring(remainsId))
    NPCWorldDirectorBridge.DirectorEvent(director, "battle_remains_materialized", baseX, baseY, baseZ, {
        battleId = tostring(record.battleId or ""),
        remainsId = tostring(remainsId),
        spawnedBodies = spawnedBodies,
        spawnedProps = spawnedProps
    })
    NPCWorldDirectorBridge.Log(director, "[NPCWorldDirector] Materialized aftermath " .. tostring(remainsId) .. " props=" .. tostring(spawnedProps))
    return true
end

function NPCWorldDirectorBridge.IsBattleDebrisItem(fullType)
    fullType = tostring(fullType or "")
    return fullType == "Base.RippedSheetsDirty"
        or fullType == "Base.BandageDirty"
        or fullType == "Base.Cigarettes"
        or fullType == "Base.WaterBottleEmpty"
        or fullType == "Base.PopEmpty"
        or fullType == "Base.TinCanEmpty"
        or fullType == "Base.Bullets9mmBox"
        or fullType == "Base.ShotgunShellsBox"
        or fullType == "Base.Bullets45Box"
        or fullType == "Base.ScrapMetal"
        or fullType == "Base.SmallSheetMetal"
        or fullType == "Base.SheetMetal"
        or fullType == "Base.MetalPipe"
        or fullType == "Base.MetalBar"
        or fullType == "Base.Plank"
        or fullType == "Base.UnusableWood"
        or fullType == "Base.NailsBox"
        or fullType == "Base.Nails"
        or fullType == "Base.Hinge"
        or fullType == "Base.Doorknob"
        or fullType == "Base.Screws"
        or fullType == "Base.EngineParts"
        or fullType == "Base.BrokenGlass"
        or fullType == "Base.Garbagebag"
        or fullType == "Base.EmptyPetrolCan"
        or fullType == "Base.PetrolCanEmpty"
        or fullType == "Base.NormalTire1"
        or fullType == "Base.NormalTire2"
        or fullType == "Base.NormalTire3"
        or fullType == "Base.OldTire1"
        or fullType == "Base.OldTire2"
        or fullType == "Base.OldTire3"
end

function NPCWorldDirectorBridge.RemoveWorldObjectSafe(obj)
    if not obj then return false end
    local ok = false
    if obj.removeFromWorld then ok = pcall(function() obj:removeFromWorld() end) or ok end
    if obj.removeFromSquare then ok = pcall(function() obj:removeFromSquare() end) or ok end
    return ok == true
end

function NPCWorldDirectorBridge.CleanupBattlefieldClutterAroundPlayer(director, player)
    if not (director and director.BATTLEFIELD_CLEANUP_ENABLED) or not player or not getCell then return 0 end
    local radius = tonumber(director.BATTLEFIELD_CLEANUP_RADIUS) or 42
    local corpseSoftCap = tonumber(director.BATTLEFIELD_CLEANUP_CORPSE_SOFT_CAP) or 18
    local debrisSoftCap = tonumber(director.BATTLEFIELD_CLEANUP_DEBRIS_SOFT_CAP) or 24
    local maxRemove = tonumber(director.BATTLEFIELD_CLEANUP_MAX_REMOVE_PER_RUN) or 48
    if radius <= 0 or maxRemove <= 0 then return 0 end

    local cell = getCell()
    if not cell then return 0 end
    local px = math.floor(tonumber(player:getX()) or 0)
    local py = math.floor(tonumber(player:getY()) or 0)
    local pz = math.floor(tonumber(player:getZ()) or 0)
    local bodies = {}
    local debris = {}

    for y = py - radius, py + radius do
        for x = px - radius, px + radius do
            local square = cell:getGridSquare(x, y, pz)
            if square then
                if square.getDeadBody then
                    local okBody, body = pcall(function() return square:getDeadBody() end)
                    if okBody and body then bodies[#bodies + 1] = body end
                end
                if square.getWorldObjects then
                    local okWorld, worldObjects = pcall(function() return square:getWorldObjects() end)
                    if okWorld and worldObjects then
                        local size = worldObjects:size()
                        for i = 0, size - 1 do
                            local obj = worldObjects:get(i)
                            local item = obj and obj.getItem and obj:getItem() or nil
                            local fullType = item and item.getFullType and item:getFullType() or nil
                            if NPCWorldDirectorBridge.IsBattleDebrisItem(fullType) then
                                debris[#debris + 1] = obj
                            end
                        end
                    end
                end
            end
        end
    end

    local removed = 0
    if #debris > debrisSoftCap then
        for i = debrisSoftCap + 1, #debris do
            if removed >= maxRemove then break end
            if NPCWorldDirectorBridge.RemoveWorldObjectSafe(debris[i]) then removed = removed + 1 end
        end
    end
    if #bodies > corpseSoftCap then
        for i = corpseSoftCap + 1, #bodies do
            if removed >= maxRemove then break end
            if NPCWorldDirectorBridge.RemoveWorldObjectSafe(bodies[i]) then removed = removed + 1 end
        end
    end
    return removed
end

function NPCWorldDirectorBridge.CleanupBattlefieldClutter(director)
    if not (director and director.BATTLEFIELD_CLEANUP_ENABLED) or not getOnlinePlayers then return 0 end
    local playerList = getOnlinePlayers()
    if not playerList then return 0 end
    local removed = 0
    for i = 0, playerList:size() - 1 do
        local player = playerList:get(i)
        if player and not player:isDead() then
            removed = removed + NPCWorldDirectorBridge.CleanupBattlefieldClutterAroundPlayer(director, player)
        end
    end
    return removed
end

function NPCWorldDirectorBridge.UpdateBattleRemains(director)
    if not (director and director.EnsureData) then return false end
    local gmd = director.EnsureData()
    if type(gmd) ~= "table" then return false end
    if type(gmd.BattleRemains) ~= "table" then gmd.BattleRemains = {} end

    local worldAge = 0
    local okAge, value = pcall(function() return getGameTime():getWorldAgeHours() end)
    if okAge then worldAge = tonumber(value) or 0 end
    local changed = NPCWorldDirectorBridge.PruneBattleRemains(director, gmd, worldAge) or false
    local radius = tonumber(director.BATTLE_REMAINS_ACTIVATION_RADIUS) or 280

    for remainsId, record in pairs(gmd.BattleRemains) do
        if type(record) == "table" and not record.materialized and record.x and record.y then
            local player = nil
            if director.GetNearestPlayer then
                player = director.GetNearestPlayer(record.x, record.y, radius)
            end
            if player and NPCWorldDirectorBridge.MaterializeBattleRemains(director, gmd, remainsId, record, player) then
                changed = true
            end
        end
    end

    if changed and TransmitNPCModData then
        TransmitNPCModData()
    end
    return changed
end


-- Stage 58: neutral world-director runtime data and startup revirtualization backend.
-- Keeps the historical legacy world-director public entry points as wrappers while
-- moving ModData shape setup and saved-runtime reset out of the compatibility facade.

function NPCWorldDirectorBridge.EnsureData(_director)
    local gmd = GetNPCModData()
    if not gmd.Queue then gmd.Queue = {} end
    if not gmd.VirtualGroups then gmd.VirtualGroups = {} end
    if not gmd.DebugMapMarkers then gmd.DebugMapMarkers = {} end
    if not gmd.BattleRemains then gmd.BattleRemains = {} end
    if not gmd.UrbanCoverProps then gmd.UrbanCoverProps = {} end
    if not gmd.WorldDirector then
        gmd.WorldDirector = {
            enabled = true,
            initialized = false,
            nextGroupId = 1,
            lastUpdate = 0,
            lastSpawn = 0
        }
    end
    if gmd.WorldDirector.enabled == nil then gmd.WorldDirector.enabled = true end
    if not gmd.WorldDirector.nextGroupId then gmd.WorldDirector.nextGroupId = 1 end
    if NPCIdentityBridge and NPCIdentityBridge.EnsureGlobalData then
        NPCIdentityBridge.EnsureGlobalData(gmd)
    end
    return gmd
end

function NPCWorldDirectorBridge.ResumeVirtualState(group)
    if not group then return "roaming" end
    if group.inBattle then return "road_battle" end
    if group.roadPatrol then
        return NPCStrategicAIBridge and NPCStrategicAIBridge.ResumeGroupState and NPCStrategicAIBridge.ResumeGroupState(group) or (group.hostile and "red_road_patrol" or "green_road_patrol")
    end
    if group.homeBaseId then return "base_patrol" end
    return "roaming"
end

function NPCWorldDirectorBridge.RefreshRevirtualizedGroupMarker(gmd, groupId, group, worldAge)
    if not (gmd and gmd.DebugMapMarkers and groupId and group) then return end

    local marker = gmd.DebugMapMarkers[groupId] or {}
    marker.id = groupId
    marker.markerType = "group"
    marker.groupId = groupId
    marker.x = group.x
    marker.y = group.y
    marker.z = group.z or 0
    marker.name = NPCWorldDirectorBridge.GetVirtualGroupDisplayName(groupId, group, marker.name)
    marker.displayName = marker.name
    marker.count = group.count
    marker.hostile = group.hostile
    marker.friendly = not group.hostile
    marker.factionSide = group.factionSide
    marker.faction = group.faction
    marker.side = group.side
    marker.program = group.program and group.program.name or marker.program or "Raider"
    marker.virtual = true
    marker.active = false
    marker.dead = false
    marker.state = group.state
    marker.spawnPending = false
    marker.spawnQueued = 0
    marker.spawnClass = group.spawnClass
    marker.roadPatrol = group.roadPatrol or false
    marker.patrolColor = group.patrolColor
    marker.mercenary = group.mercenary or false
    marker.mercenaryElite = group.mercenaryElite or false
    marker.hireable = group.hireable or false
    marker.recruitable = group.recruitable or false
    marker.blueMercenaryMapDwellUntil = group.blueMercenaryMapDwellUntil
    marker.encounterId = group.encounterId
    marker.inBattle = group.inBattle or false
    marker.battleId = group.battleId
    marker.enemyGroupId = group.enemyGroupId
    marker.battleCasualties = group.battleCasualties or 0
    marker.spawnFailed = false
    marker.spawnFailCount = group.spawnFailCount
    marker.spawnFailReason = nil
    marker.updatedAt = worldAge
    NPCWorldDirectorBridge.ApplyVirtualGroupMapMotionFields(nil, marker, group, worldAge)
    gmd.DebugMapMarkers[groupId] = marker
    NPCWorldDirectorBridge.SendDebugMapUpdate(marker)
end

function NPCWorldDirectorBridge.RevirtualizePersistedRuntimeState(director)
    if type(director) ~= "table" then return false end
    if director._startupRuntimeRevirtualized then return false end
    director._startupRuntimeRevirtualized = true

    local gmd = director.EnsureData and director.EnsureData() or NPCWorldDirectorBridge.EnsureData(director)
    local changed = false
    local worldAge = getGameTime and getGameTime():getWorldAgeHours() or 0

    if NPCPersistentNPCBridge and NPCPersistentNPCBridge.ClearRuntimeLinks then
        changed = NPCPersistentNPCBridge.ClearRuntimeLinks(gmd) or changed
    end

    if type(gmd.Queue) == "table" and NPCWorldDirectorBridge.CountTable(gmd.Queue) > 0 then
        gmd.Queue = {}
        changed = true
    end
    gmd.RuntimeToUID = {}
    gmd.UIDToRuntime = {}
    gmd.PersistentRuntimeToUID = {}
    gmd.PersistentUIDToRuntime = {}

    if type(gmd.DebugMapMarkers) == "table" then
        local removeIds = {}
        for id, marker in pairs(gmd.DebugMapMarkers) do
            if NPCWorldDirectorBridge.IsNpcMarker(marker) then
                removeIds[#removeIds + 1] = tostring(id)
            end
        end
        for _, id in ipairs(removeIds) do
            NPCWorldDirectorBridge.RemoveMarkerById(gmd, id, "npc")
            changed = true
        end
    end

    for groupId, group in pairs(gmd.VirtualGroups or {}) do
        if type(group) == "table" and (group.activated or group.virtual == false or group.state == "physical" or group.state == "spawning" or group.physicalIds ~= nil or group.spawnPending) then
            groupId = tostring(groupId)
            if NPCPersistentNPCBridge and NPCPersistentNPCBridge.RestoreGroupMembers then
                NPCPersistentNPCBridge.RestoreGroupMembers(gmd, group)
            end
            local bubble = NPCWorldDirectorBridge.GetPersistedPhysicalBubble(gmd, groupId)
            if bubble and NPCWorldDirectorBridge.PreparePhysicalBubbleGroupForRestore(director, gmd, groupId, group, bubble, worldAge) then
                -- Keep only a compact strategic snapshot in save, but make the
                -- nearby physical group eligible for fast restoration when the
                -- owning player returns after a stop/start.
            else
                group.activated = false
                group.virtual = true
                group.physicalIds = nil
                group.spawnPending = false
                group.spawnQueued = 0
                group.retryAfter = nil
                group.lastSpawnFailReason = nil
                group.spawnFailed = false
                group.state = NPCWorldDirectorBridge.ResumeVirtualState(group)
                if type(group.members) == "table" and #group.members > 0 then
                    group.count = #group.members
                end
                group.updatedAt = worldAge
                NPCWorldDirectorBridge.CompactVirtualGroupForStrategicPersistence(director, gmd, groupId, group, "startup_revirtualize")
            end
            gmd.VirtualGroups[groupId] = group
            if NPCPersistentNPCBridge and NPCPersistentNPCBridge.RegisterGroup then
                NPCPersistentNPCBridge.RegisterGroup(gmd, group)
            end
            NPCWorldDirectorBridge.RemoveNpcMarkersForGroup(gmd, groupId)
            NPCWorldDirectorBridge.RefreshRevirtualizedGroupMarker(gmd, groupId, group, worldAge)
            changed = true
        end
    end

    if NPCWorldDirectorBridge.CleanupLoadedPersistedRuntimeObjects(director, "startup_revirtualize") > 0 then
        changed = true
    end

    if NPCIdentityReconciliationBridge and NPCIdentityReconciliationBridge.ReconcileGlobal then
        local okRecon, reconChanged = pcall(function()
            return NPCIdentityReconciliationBridge.ReconcileGlobal(gmd, {
                force = true,
                reason = "startup_revirtualize",
                maxQueue = 160,
                maxGroups = 96,
                maxMarkers = 160,
                allowSoftRevirtualize = true,
                sendRemove = function(id) NPCWorldDirectorBridge.SendDebugMapRemove(id) end
            })
        end)
        if okRecon and tonumber(reconChanged) and tonumber(reconChanged) > 0 then changed = true end
    end

    if NPCWorldDirectorBridge.ReconcileDebugMarkers(gmd, "startup_revirtualize", 180) > 0 then changed = true end

    if changed and TransmitNPCModData then
        TransmitNPCModData()
    end

    return changed
end

function NPCWorldDirectorBridge.RevirtualizePersistedRuntimeStateStep(director, maxGroups)
    if type(director) ~= "table" then return false, true end
    if director._startupRuntimeRevirtualized then return false, true end

    local gmd = director.EnsureData and director.EnsureData() or NPCWorldDirectorBridge.EnsureData(director)
    local worldAge = getGameTime and getGameTime():getWorldAgeHours() or 0
    local state = director._spRuntimeRevirtualizeState
    if type(state) ~= "table" then
        state = {groupIds = {}, index = 1, initialized = true}
        for groupId, _ in pairs(gmd.VirtualGroups or {}) do
            state.groupIds[#state.groupIds + 1] = tostring(groupId)
        end
        director._spRuntimeRevirtualizeState = state
        if NPCPersistentNPCBridge and NPCPersistentNPCBridge.ClearRuntimeLinks then
            pcall(function() NPCPersistentNPCBridge.ClearRuntimeLinks(gmd) end)
        end
        if type(gmd.Queue) == "table" and NPCWorldDirectorBridge.CountTable(gmd.Queue) > 0 then
            gmd.Queue = {}
        end
        gmd.RuntimeToUID = {}
        gmd.UIDToRuntime = {}
        gmd.PersistentRuntimeToUID = {}
        gmd.PersistentUIDToRuntime = {}
    end

    local budget = npc_wd_spBudget(maxGroups, 8, 1, 64)
    local changed = false
    local processed = 0
    while state.index <= #state.groupIds and processed < budget do
        local groupId = tostring(state.groupIds[state.index] or "")
        state.index = state.index + 1
        processed = processed + 1
        local group = gmd.VirtualGroups and gmd.VirtualGroups[groupId] or nil
        if type(group) == "table" and (group.activated or group.virtual == false or group.state == "physical" or group.state == "spawning" or group.physicalIds ~= nil or group.spawnPending) then
            if NPCPersistentNPCBridge and NPCPersistentNPCBridge.RestoreGroupMembers then
                pcall(function() NPCPersistentNPCBridge.RestoreGroupMembers(gmd, group) end)
            end
            local bubble = NPCWorldDirectorBridge.GetPersistedPhysicalBubble(gmd, groupId)
            if bubble and NPCWorldDirectorBridge.PreparePhysicalBubbleGroupForRestore(director, gmd, groupId, group, bubble, worldAge) then
                -- Restored as a lazy physical-bubble candidate below.
            else
                group.activated = false
                group.virtual = true
                group.physicalIds = nil
                group.spawnPending = false
                group.spawnQueued = 0
                group.retryAfter = nil
                group.lastSpawnFailReason = nil
                group.spawnFailed = false
                group.state = NPCWorldDirectorBridge.ResumeVirtualState(group)
                if type(group.members) == "table" and #group.members > 0 then
                    group.count = #group.members
                end
                group.updatedAt = worldAge
                NPCWorldDirectorBridge.CompactVirtualGroupForStrategicPersistence(director, gmd, groupId, group, "startup_revirtualize_step")
            end
            gmd.VirtualGroups[groupId] = group
            if NPCPersistentNPCBridge and NPCPersistentNPCBridge.RegisterGroup then
                pcall(function() NPCPersistentNPCBridge.RegisterGroup(gmd, group) end)
            end
            NPCWorldDirectorBridge.RefreshRevirtualizedGroupMarker(gmd, groupId, group, worldAge)
            changed = true
        end
    end

    if state.index > #state.groupIds then
        director._startupRuntimeRevirtualized = true
        director._spRuntimeRevirtualizeState = nil
        if NPCWorldDirectorBridge.ReconcileDebugMarkers(gmd, "sp_startup_revirtualize", 90) > 0 then changed = true end
        return changed, true
    end

    return changed, false
end

-- Stage 49: neutral virtual-group creation backend.
-- Public legacy world-director entry points remain compatibility wrappers, while the
-- server-owned virtual group assembly and debug marker payload now live here.

function NPCWorldDirectorBridge.Choice(t)
    if type(t) ~= "table" then return nil end
    local count = #t
    if count <= 0 then return nil end
    return t[ZombRand(count) + 1]
end

function NPCWorldDirectorBridge.Copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copied = {}
    seen[value] = copied
    for k, v in pairs(value) do
        copied[NPCWorldDirectorBridge.Copy(k, seen)] = NPCWorldDirectorBridge.Copy(v, seen)
    end
    return copied
end

function NPCWorldDirectorBridge.ClampGroupSize(size)
    size = tonumber(size) or 3
    if size < 1 then return 1 end
    if size > 12 then return 12 end
    return math.floor(size)
end

-- Stage 59: neutral wave/profile and member template backend.

function NPCWorldDirectorBridge.GetWaveDataAll(director)
    local banditSandbox = SandboxVars and SandboxVars[NPC_WORLD_DIRECTOR_LEGACY_KEYS.sandboxSection]
    local waveData = {}

    if not banditSandbox or not NPCWorldDirectorBridge.LegacyFactionProfilesEnabled(director) then
        table.insert(waveData, NPCWorldDirectorBridge.GenericProfile(director))
        return waveData
    end

    for i=1, 16 do
        local wave = {}
        wave.enabled = banditSandbox["Clan_" .. tostring(i) .. "_WaveEnabled"]
        wave.enemyBehaviour = banditSandbox["Clan_" .. tostring(i) .. "_EnemyBehaviour"] or 1
        wave.firstDay = banditSandbox["Clan_" .. tostring(i) .. "_FirstDay"] or 0
        wave.lastDay = banditSandbox["Clan_" .. tostring(i) .. "_LastDay"] or 99999
        wave.spawnHourlyChance = banditSandbox["Clan_" .. tostring(i) .. "_SpawnHourlyChance"] or 0
        wave.groupSize = banditSandbox["Clan_" .. tostring(i) .. "_GroupSize"] or 3
        wave.clanId = banditSandbox["Clan_" .. tostring(i) .. "_GroupName"] or i
        wave.hasPistolChance = banditSandbox["Clan_" .. tostring(i) .. "_HasPistolChance"] or 20
        wave.pistolMagCount = banditSandbox["Clan_" .. tostring(i) .. "_PistolMagCount"] or 2
        wave.hasRifleChance = banditSandbox["Clan_" .. tostring(i) .. "_HasRifleChance"] or 5
        wave.rifleMagCount = banditSandbox["Clan_" .. tostring(i) .. "_RifleMagCount"] or 1

        if wave.enabled and wave.spawnHourlyChance > 0 then
            table.insert(waveData, wave)
        end
    end

    if #waveData == 0 then
        table.insert(waveData, NPCWorldDirectorBridge.GenericProfile(director))
    end

    return waveData
end

function NPCWorldDirectorBridge.GetWaveDataForDay(director, day)
    local waveData = NPCWorldDirectorBridge.GetWaveDataAll(director)
    local ret = {}

    for _, wave in pairs(waveData) do
        if wave.enabled and day >= wave.firstDay and day <= wave.lastDay then
            table.insert(ret, wave)
        end
    end

    if #ret == 0 then
        ret = waveData
    end

    return ret
end

function NPCWorldDirectorBridge.GetProgramForWave(_director, wave)
    local event = {}
    event.hostile = true
    event.program = {}

    if wave.enemyBehaviour == 1 then
        event.program.name = NPCWorldDirectorBridge.Choice({"Raider", "Looter", "Thief"})
    elseif wave.enemyBehaviour == 2 then
        event.program.name = "Raider"
    elseif wave.enemyBehaviour == 3 then
        event.program.name = "Looter"
    elseif wave.enemyBehaviour == 4 then
        event.program.name = "Looter"
    elseif wave.enemyBehaviour == 5 then
        event.program.name = "Thief"
    elseif wave.enemyBehaviour == 6 then
        event.program.name = NPCWorldDirectorBridge.Choice({"Looter", "Thief"})
    elseif wave.enemyBehaviour == 7 then
        event.program.name = "Looter"
        event.hostile = false
    elseif wave.enemyBehaviour == 8 then
        event.program.name = "Companion"
        event.hostile = false
    elseif wave.enemyBehaviour == 9 then
        event.program.name = NPCWorldDirectorBridge.Choice({"Looter", "Companion"})
        event.hostile = false
    elseif wave.enemyBehaviour == 10 then
        if ZombRand(2) == 0 then
            event.program.name = NPCWorldDirectorBridge.Choice({"Raider", "Looter", "Thief"})
        else
            event.program.name = NPCWorldDirectorBridge.Choice({"Looter", "Companion"})
            event.hostile = false
        end
    else
        event.program.name = "Raider"
    end

    if event.program.name == "Thief" then
        event.hostile = false
    end

    event.program.stage = "Prepare"
    return event
end

function NPCWorldDirectorBridge.MakeFallbackNPC(_director, wave)
    if NPCCreatorBridge and NPCCreatorBridge.GetFirearmWeightedWave then
        wave = NPCCreatorBridge.GetFirearmWeightedWave(wave or {})
    else
        wave = wave or {}
    end
    local bandit = {}

    bandit.clan = wave.clanId or 1
    bandit.health = NPCHealthRegenBridge and NPCHealthRegenBridge.NormalizeSpawnHealth and NPCHealthRegenBridge.NormalizeSpawnHealth(1.0) or 3.0
    bandit.femaleChance = 50
    bandit.eatBody = false
    bandit.accuracyBoost = 1

    bandit.weapons = {}
    local meleePool = nil
    if NPCWeaponsBridge and NPCWeaponsBridge.GetSpawnMelee then
        meleePool = NPCWeaponsBridge.GetSpawnMelee(nil)
    elseif NPCWeaponsBridge and NPCWeaponsBridge.GetMelee then
        meleePool = NPCWeaponsBridge.GetMelee()
    end
    if meleePool and #meleePool > 0 then
        bandit.weapons.melee = NPCWorldDirectorBridge.Choice(meleePool) or "Base.Axe"
    else
        bandit.weapons.melee = "Base.Axe"
    end

    local primaryPool = nil
    local secondaryPool = nil
    if NPCWeaponsBridge and NPCWeaponsBridge.GetSpawnPrimary then
        primaryPool = NPCWeaponsBridge.GetSpawnPrimary(nil)
    elseif NPCWeaponsBridge then
        primaryPool = NPCWeaponsBridge.Primary
    end
    if NPCWeaponsBridge and NPCWeaponsBridge.GetSpawnSecondary then
        secondaryPool = NPCWeaponsBridge.GetSpawnSecondary(nil)
    elseif NPCWeaponsBridge then
        secondaryPool = NPCWeaponsBridge.Secondary
    end

    bandit.weapons.primary = {name=false, magSize=0, bulletsLeft=0, magCount=0}
    if primaryPool and #primaryPool > 0 and ZombRand(101) < (wave.hasRifleChance or 0) then
        local primary = nil
        if NPCCreatorBridge and NPCCreatorBridge.PickBalancedFirearm then
            primary = NPCCreatorBridge.PickBalancedFirearm(primaryPool, wave, "primary")
        else
            primary = NPCWorldDirectorBridge.Choice(primaryPool)
        end
        bandit.weapons.primary = NPCWorldDirectorBridge.Copy(primary)
        bandit.weapons.primary.magCount = wave.rifleMagCount or 1
    end

    bandit.weapons.secondary = {name=false, magSize=0, bulletsLeft=0, magCount=0}
    if secondaryPool and #secondaryPool > 0 and ZombRand(101) < (wave.hasPistolChance or 0) then
        local secondary = nil
        if NPCCreatorBridge and NPCCreatorBridge.PickBalancedFirearm then
            secondary = NPCCreatorBridge.PickBalancedFirearm(secondaryPool, wave, "secondary")
        else
            secondary = NPCWorldDirectorBridge.Choice(secondaryPool)
        end
        bandit.weapons.secondary = NPCWorldDirectorBridge.Copy(secondary)
        bandit.weapons.secondary.magCount = wave.pistolMagCount or 2
    end

    local outfits = {"Generic01", "Generic02", "Survivalist03", "Thug", "Redneck"}
    if NPCOutfitsBridge then
        if NPCOutfitsBridge.DesperateCitizen and #NPCOutfitsBridge.DesperateCitizen > 0 then
            outfits = NPCOutfitsBridge.DesperateCitizen
        elseif NPCOutfitsBridge.Prepper and #NPCOutfitsBridge.Prepper > 0 then
            outfits = NPCOutfitsBridge.Prepper
        end
    end
    bandit.outfit = NPCWorldDirectorBridge.Choice(outfits) or "Generic01"

    bandit.loot = {}
    return bandit
end

function NPCWorldDirectorBridge.MakeNPCFromWave(director, wave)
    if NPCCreatorBridge and NPCCreatorBridge.MakeFromWave then
        local ok, bandit = pcall(function()
            return NPCCreatorBridge.MakeFromWave(wave)
        end)

        if ok and bandit then
            return bandit
        end
    end

    return NPCWorldDirectorBridge.MakeFallbackNPC(director, wave)
end

function NPCWorldDirectorBridge.PrepareVirtualMember(director, gmd, wave, groupId, index, groupSide, mercenaryGroup)
    if not (director and director.MakeNPCFromWave) then return nil end
    local member = director.MakeNPCFromWave(wave)
    if type(member) ~= "table" then return nil end

    if NPCIdentityBridge and NPCIdentityBridge.NewUID then
        member.uid = member.uid or NPCIdentityBridge.NewUID(gmd)
        member.persistentId = member.persistentId or member.uid
    end

    member.worldGroupId = groupId
    member.groupId = groupId
    member.memberIndex = index
    member.roadBias = true
    member.preferRoads = true
    member.factionSide = groupSide
    member.faction = groupSide
    member.side = groupSide
    member.patrolColor = groupSide

    if mercenaryGroup and NPCMercenaryContract and NPCMercenaryContract.ApplyEliteToMember then
        NPCMercenaryContract.ApplyEliteToMember(member)
    end

    member.accuracyBoost = tonumber(member.accuracyBoost) or 1
    if member.accuracyBoost <= 0 then member.accuracyBoost = 1 end
    if NPCCreatorBridge and NPCCreatorBridge.ApplyAppearanceStyleToMember then
        NPCCreatorBridge.ApplyAppearanceStyleToMember(member)
    end
    return member
end

function NPCWorldDirectorBridge.ApplyVirtualGroupStrategicState(director, gmd, group)
    if type(group) ~= "table" then return group end

    if NPCStrategicAIBridge and NPCStrategicAIBridge.EnsureGroupBase then
        NPCStrategicAIBridge.EnsureGroupBase(gmd, group)
    end
    if NPCBaseSupplyServer and NPCBaseSupplyServer.ApplyGearToGroup and group.homeBaseId then
        local home = NPCStrategicAIBridge and NPCStrategicAIBridge.GetBaseById and NPCStrategicAIBridge.GetBaseById(gmd, group.homeBaseId) or nil
        if home then NPCBaseSupplyServer.ApplyGearToGroup(home, group) end
    end
    if NPCStrategicAIBridge and NPCStrategicAIBridge.EvaluateGroupCombatPower then
        NPCStrategicAIBridge.EvaluateGroupCombatPower(gmd, group)
    end
    if NPCWorldDirectorBridge.EnsureBaseOwnedGroup then
        NPCWorldDirectorBridge.EnsureBaseOwnedGroup(director, gmd, group, getGameTime and getGameTime():getWorldAgeHours() or nil, "strategic_state")
    end

    return group
end

function NPCWorldDirectorBridge.CleanVirtualGroupDisplayName(name, groupId)
    if name == nil then return nil end
    local text = tostring(name or "")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    if text == "" or text == "nil" or text == "false" then return nil end

    local gid = tostring(groupId or "")
    if gid ~= "" and text == gid then return nil end
    if string.match(text, "^P%d+%s+BBC%d+$") then return nil end
    if string.match(text, "^BBC%d+$") then return nil end
    if string.match(text, "^WG%d+$") then return nil end
    if string.match(text, "^CP%d+$") then return nil end
    if string.match(text, "^SG%d+$") then return nil end

    text = string.gsub(text, "%s+P%d+%s+BBC%d+$", "")
    text = string.gsub(text, "%s+BBC%d+$", "")
    text = string.gsub(text, "%s+WG%d+$", "")
    text = string.gsub(text, "%s+CP%d+$", "")
    text = string.gsub(text, "%s+SG%d+$", "")
    if gid ~= "" then
        text = string.gsub(text, "%s+" .. gid .. "$", "")
    end
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")

    local lower = string.lower(text)
    if text == "" or lower == "npc group" or lower == "road patrol" or lower == "checkpoint patrol" then return nil end
    if string.match(text, "^NPC Group%s*") then return nil end
    return text
end

function NPCWorldDirectorBridge.GetVirtualGroupSideLabel(group)
    local side = group and (group.factionSide or group.side or group.faction or group.patrolColor) or nil
    side = tostring(side or "")
    if NPCFactionBridge and NPCFactionBridge.NormalizeSide then
        local ok, normalized = pcall(function() return NPCFactionBridge.NormalizeSide(side) end)
        if ok and normalized then side = tostring(normalized) end
    end
    side = string.lower(side)
    if side == "red" then return "Red" end
    if side == "green" then return "Green" end
    if side == "blue" then return "Blue" end
    if group and group.hostile == true then return "Red" end
    return "Green"
end

function NPCWorldDirectorBridge.GetVirtualGroupDisplayName(groupId, group, preferredName)
    local cleaned = NPCWorldDirectorBridge.CleanVirtualGroupDisplayName(preferredName or (group and group.name), groupId)
    if cleaned then return cleaned end

    local sideLabel = NPCWorldDirectorBridge.GetVirtualGroupSideLabel(group)
    if group and (group.mercenary or group.mercenaryElite or sideLabel == "Blue") then
        if group.mercenaryHired then return "Hired blue mercenaries" end
        return "Blue mercenaries"
    end
    if group and group.inBattle then
        return "Battle: " .. sideLabel .. " patrol"
    end
    if group and (group.checkpointId or group.targetClass == "checkpoint_road_patrol" or group.state == "checkpoint_patrol") then
        return sideLabel .. " checkpoint patrol"
    end
    if group and group.roadPatrol then
        return sideLabel .. " road patrol"
    end
    if group and (group.homeBaseId or group.state == "base_patrol" or group.targetClass == "base_guard") then
        return sideLabel .. " base patrol"
    end
    if group and group.strategicActivityType then
        return sideLabel .. " field team"
    end
    return sideLabel .. " patrol"
end

function NPCWorldDirectorBridge.MapMotionDistance(ax, ay, bx, by)
    ax = tonumber(ax) or 0
    ay = tonumber(ay) or 0
    bx = tonumber(bx) or 0
    by = tonumber(by) or 0
    local dx = bx - ax
    local dy = by - ay
    return math.sqrt(dx * dx + dy * dy)
end

function NPCWorldDirectorBridge.MapMotionQuantize(value, size)
    size = tonumber(size) or 80
    if size <= 1 then size = 80 end
    return math.floor((tonumber(value) or 0) / size)
end

function NPCWorldDirectorBridge.ClearVirtualGroupMapPath(marker)
    if not marker then return marker end
    marker.mapPathKey = nil
    marker.mapPathCount = nil
    for i=1, 6 do
        marker["mapPathX" .. tostring(i)] = nil
        marker["mapPathY" .. tostring(i)] = nil
    end
    return marker
end

function NPCWorldDirectorBridge.CopyVirtualGroupMapPathToMarker(marker, path)
    NPCWorldDirectorBridge.ClearVirtualGroupMapPath(marker)
    if not (marker and type(path) == "table" and type(path.nodes) == "table" and #path.nodes > 0) then return marker end

    local count = 0
    for i, node in ipairs(path.nodes) do
        if count >= 6 then break end
        local x = tonumber(node and node.x)
        local y = tonumber(node and node.y)
        if x and y then
            count = count + 1
            marker["mapPathX" .. tostring(count)] = x
            marker["mapPathY" .. tostring(count)] = y
        end
    end
    if count > 0 then
        marker.mapPathCount = count
        marker.mapPathKey = path.key
    end
    return marker
end

function NPCWorldDirectorBridge.BuildVirtualGroupMapRoadPath(director, group, sx, sy, tx, ty, worldAge)
    if not (director and group and director.VIRTUAL_MAP_ROAD_PROJECTION_ENABLED ~= false) then return nil end
    if not (NPCRoadNavBridge and NPCRoadNavBridge.FindNearbyWorldRoadStepToward) then return nil end
    sx = tonumber(sx); sy = tonumber(sy); tx = tonumber(tx); ty = tonumber(ty)
    if not (sx and sy and tx and ty) then return nil end

    local totalDist = NPCWorldDirectorBridge.MapMotionDistance(sx, sy, tx, ty)
    if totalDist < 80 then return nil end

    local q = tonumber(director.VIRTUAL_MAP_ROAD_PROJECTION_KEY_SIZE) or 80
    local routeX = tonumber(group.routeX)
    local routeY = tonumber(group.routeY)
    local key = table.concat({
        tostring(group.id or ""),
        tostring(NPCWorldDirectorBridge.MapMotionQuantize(sx, q)),
        tostring(NPCWorldDirectorBridge.MapMotionQuantize(sy, q)),
        tostring(NPCWorldDirectorBridge.MapMotionQuantize(tx, q)),
        tostring(NPCWorldDirectorBridge.MapMotionQuantize(ty, q)),
        tostring(NPCWorldDirectorBridge.MapMotionQuantize(routeX or tx, q)),
        tostring(NPCWorldDirectorBridge.MapMotionQuantize(routeY or ty, q)),
        tostring(group.roadPatrol == true)
    }, ":")

    local now = tonumber(worldAge) or (getGameTime and getGameTime():getWorldAgeHours() or 0)
    local cached = group.mapRoadPath
    if type(cached) == "table" and cached.key == key and type(cached.nodes) == "table" then
        local cachedAt = tonumber(cached.updatedAt) or now
        if now - cachedAt <= (tonumber(director.VIRTUAL_MAP_ROAD_PROJECTION_CACHE_HOURS) or 0.35) then
            return cached
        end
    end

    local nodes = {}
    local maxNodes = math.max(1, math.min(6, tonumber(director.VIRTUAL_MAP_ROAD_PROJECTION_WAYPOINTS) or 5))
    local radius = tonumber(director.VIRTUAL_MAP_ROAD_PROJECTION_RADIUS) or tonumber(director.ROAD_PATROL_VIRTUAL_STEP_RADIUS) or 360
    local attempts = tonumber(director.VIRTUAL_MAP_ROAD_PROJECTION_ATTEMPTS) or 48
    local curX = sx
    local curY = sy

    local function addNode(node)
        if not node or #nodes >= maxNodes then return false end
        local nx = tonumber(node.x)
        local ny = tonumber(node.y)
        if not (nx and ny) then return false end
        if NPCWorldDirectorBridge.MapMotionDistance(curX, curY, nx, ny) < 18 then return false end
        nodes[#nodes + 1] = {x=nx, y=ny}
        curX = nx
        curY = ny
        return true
    end

    if group.roadPatrol and group.targetX and group.targetY then
        addNode({x=group.targetX, y=group.targetY})
    end

    while #nodes < maxNodes and NPCWorldDirectorBridge.MapMotionDistance(curX, curY, tx, ty) > radius * 0.55 do
        local step = nil
        local okStep, got = pcall(function()
            return NPCRoadNavBridge.FindNearbyWorldRoadStepToward(curX, curY, tx, ty, radius, attempts)
        end)
        if okStep and got and got.x and got.y then step = got end
        if not addNode(step) then break end
    end

    if #nodes <= 0 then
        group.mapRoadPath = nil
        return nil
    end

    local path = {key=key, updatedAt=now, nodes=nodes}
    group.mapRoadPath = path
    return path
end

function NPCWorldDirectorBridge.ApplyVirtualGroupMapMotionFields(director, marker, group, worldAge)
    if not (marker and group) then return marker end
    director = director or NPCWorldDirector

    local x = tonumber(group.preciseX) or tonumber(group.x) or tonumber(marker.x)
    local y = tonumber(group.preciseY) or tonumber(group.y) or tonumber(marker.y)
    local tx = tonumber((group.roadPatrol and group.routeX) or group.mapRouteX or group.targetX)
    local ty = tonumber((group.roadPatrol and group.routeY) or group.mapRouteY or group.targetY)
    local speed = tonumber(group.speed) or tonumber(director and director.VIRTUAL_MOVE_SPEED_TILES_PER_HOUR) or 120
    local baseSpeed = tonumber(director and director.VIRTUAL_MOVE_SPEED_TILES_PER_HOUR) or 120
    if speed > 0 and speed < baseSpeed and not NPCWorldDirectorBridge.IsRecruitableBlueMercenaryPatrol(group) then speed = baseSpeed end

    if x then marker.preciseX = x end
    if y then marker.preciseY = y end
    marker.mapMotion = marker.markerType == "group" and marker.virtual ~= false and marker.active ~= true and group.activated ~= true and tx ~= nil and ty ~= nil and group.inBattle ~= true
    marker.mapSourceX = x or marker.x
    marker.mapSourceY = y or marker.y
    marker.mapTargetX = tx
    marker.mapTargetY = ty
    marker.mapMoveSpeed = math.max(1, speed)
    marker.mapUpdatedAt = tonumber(group.updatedAt) or tonumber(worldAge) or (getGameTime and getGameTime():getWorldAgeHours() or nil)

    local path = nil
    if marker.mapMotion then
        path = NPCWorldDirectorBridge.BuildVirtualGroupMapRoadPath(director, group, marker.mapSourceX, marker.mapSourceY, marker.mapTargetX, marker.mapTargetY, marker.mapUpdatedAt)
    end
    NPCWorldDirectorBridge.CopyVirtualGroupMapPathToMarker(marker, path)

    return marker
end

function NPCWorldDirectorBridge.BuildVirtualGroupMarker(group)
    if type(group) ~= "table" then return nil end
    local groupId = group.id
    local marker = {
        id = groupId,
        markerType = "group",
        x = group.x,
        y = group.y,
        z = group.z,
        name = NPCWorldDirectorBridge.GetVirtualGroupDisplayName(groupId, group),
        displayName = NPCWorldDirectorBridge.GetVirtualGroupDisplayName(groupId, group),
        count = group.count,
        hostile = group.hostile,
        friendly = not group.hostile,
        factionSide = group.factionSide,
        faction = group.faction,
        side = group.side,
        program = group.program and group.program.name or "Raider",
        virtual = true,
        active = false,
        dead = false,
        state = group.state,
        spawnClass = group.spawnClass,
        patrolColor = group.patrolColor,
        mercenary = group.mercenary or false,
        mercenaryElite = group.mercenaryElite or false,
        mercenaryHired = group.mercenaryHired or false,
        mercenaryHiredBy = group.mercenaryHiredBy,
        zoneScore = group.zoneScore or 0,
        urbanAffinity = group.urbanAffinity or 0,
        directorBias = group.directorBias,
        directorBiasReason = group.directorBiasReason,
        targetX = group.targetX,
        targetY = group.targetY,
        homeBaseId = group.homeBaseId,
        homeBaseOwner = group.homeBaseOwner,
        baseOwnedGlobalSquad = group.baseOwnedGlobalSquad == true,
        baseOwnedRole = group.baseOwnedRole,
        originBaseId = group.originBaseId,
        routeOwnerBaseId = group.routeOwnerBaseId,
        baseOwnedRouteReason = group.baseOwnedRouteReason,
        locationRepairProtected = group.locationRepairProtected == true,
        strategicPower = group.strategicPower,
        combatReadiness = group.combatReadiness,
        supplyReadiness = group.supplyReadiness,
        ammoReadiness = group.ammoReadiness,
        armoryReadiness = group.armoryReadiness,
        moraleReadiness = group.moraleReadiness,
        supplyLineState = group.supplyLineState,
        logisticsBaseId = group.logisticsBaseId,
        logisticsBaseDistance = group.logisticsBaseDistance,
        strategicActivityLogisticsSupply = group.strategicActivityLogisticsSupply,
        strategicActivityLogisticsAmmo = group.strategicActivityLogisticsAmmo,
        strategicActivityLogisticsMorale = group.strategicActivityLogisticsMorale,
        strategicActivityId = group.strategicActivityId,
        strategicActivityType = group.strategicActivityType,
        strategicActivityState = group.strategicActivityState,
        strategicActivityPriority = group.strategicActivityPriority,
        strategicActivityTargetBaseId = group.strategicActivityTargetBaseId,
        strategicActivityTargetGroupId = group.strategicActivityTargetGroupId
    }
    return NPCWorldDirectorBridge.ApplyVirtualGroupMapMotionFields(nil, marker, group)
end


function NPCWorldDirectorBridge.GetRoadPatrolCount(director, hostile)
    if type(director) ~= "table" or not director.EnsureData then return 0 end
    local gmd = director.EnsureData()
    local groups = gmd and gmd.VirtualGroups or nil
    if type(groups) ~= "table" then return 0 end
    local count = 0
    for _, group in pairs(groups) do
        if group and group.roadPatrol and group.hostile == hostile then count = count + 1 end
    end
    return count
end

function NPCWorldDirectorBridge.GetAnyRoadPatrolCount(director)
    if type(director) ~= "table" or not director.EnsureData then return 0 end
    local gmd = director.EnsureData()
    local groups = gmd and gmd.VirtualGroups or nil
    if type(groups) ~= "table" then return 0 end
    local count = 0
    for _, group in pairs(groups) do
        if group and group.roadPatrol then count = count + 1 end
    end
    return count
end

function NPCWorldDirectorBridge.GetRoadPatrolEncounterCount(director)
    if type(director) ~= "table" or not director.EnsureData then return 0 end
    local gmd = director.EnsureData()
    local groups = gmd and gmd.VirtualGroups or nil
    if type(groups) ~= "table" then return 0 end
    local encounters = {}
    for _, group in pairs(groups) do
        if group and group.roadPatrol and group.encounterId then
            encounters[tostring(group.encounterId)] = true
        end
    end
    local count = 0
    for _, _ in pairs(encounters) do count = count + 1 end
    return count
end

function NPCWorldDirectorBridge.BuildRoadPatrolMarker(director, gmd, group, namePrefix)
    if not group or not group.id then return nil end
    local marker = gmd and gmd.DebugMapMarkers and gmd.DebugMapMarkers[group.id] or {}
    marker.id = group.id
    marker.markerType = "group"
    marker.x = group.x
    marker.y = group.y
    marker.z = group.z or 0
    marker.name = NPCWorldDirectorBridge.GetVirtualGroupDisplayName(group.id, group, tostring(namePrefix or "Road Patrol ") .. tostring(group.id))
    marker.displayName = marker.name
    marker.count = group.count or 0
    marker.hostile = group.hostile
    marker.friendly = not group.hostile
    marker.factionSide = group.factionSide
    marker.faction = group.faction
    marker.side = group.side
    marker.program = group.program and group.program.name or "Raider"
    marker.virtual = not group.activated
    marker.active = group.activated == true
    marker.dead = (tonumber(group.count) or 0) <= 0
    marker.state = group.state
    marker.spawnPending = group.spawnPending or false
    marker.spawnQueued = group.spawnQueued or 0
    marker.spawnClass = group.spawnClass
    marker.zoneScore = group.zoneScore or 0
    marker.urbanAffinity = group.urbanAffinity or 0
    marker.directorBias = group.directorBias
    marker.directorBiasReason = group.directorBiasReason
    marker.roadPatrol = group.roadPatrol or false
    marker.patrolColor = group.patrolColor
    marker.mercenary = group.mercenary or false
    marker.mercenaryElite = group.mercenaryElite or false
    marker.mercenaryHired = group.mercenaryHired or false
    marker.mercenaryHiredBy = group.mercenaryHiredBy
    marker.encounterId = group.encounterId
    marker.inBattle = group.inBattle or false
    marker.battleId = group.battleId
    marker.enemyGroupId = group.enemyGroupId
    marker.battleCasualties = group.battleCasualties or 0
    marker.targetX = group.targetX
    marker.targetY = group.targetY
    marker.economyMissionId = group.economyMissionId
    marker.missionType = group.missionType
    marker.missionState = group.economyMissionId and group.state or nil
    marker.resource = group.missionResource
    marker.originBaseId = group.missionOriginBaseId or group.originBaseId
    marker.targetBaseId = group.missionTargetBaseId or group.targetBaseId
    marker.convoyFaction = group.convoyFaction or group.patrolColor
    marker.homeBaseId = group.homeBaseId
    marker.homeBaseOwner = group.homeBaseOwner
    marker.baseOwnedGlobalSquad = group.baseOwnedGlobalSquad == true
    marker.baseOwnedRole = group.baseOwnedRole
    marker.routeOwnerBaseId = group.routeOwnerBaseId
    marker.baseOwnedRouteReason = group.baseOwnedRouteReason
    marker.locationRepairProtected = group.locationRepairProtected == true
    marker.strategicPower = group.strategicPower
    marker.combatReadiness = group.combatReadiness
    marker.supplyReadiness = group.supplyReadiness
    marker.ammoReadiness = group.ammoReadiness
    marker.armoryReadiness = group.armoryReadiness
    marker.strategicActivityId = group.strategicActivityId
    marker.strategicActivityType = group.strategicActivityType
    marker.strategicActivityState = group.strategicActivityState
    marker.strategicActivityPriority = group.strategicActivityPriority
    marker.strategicActivityTargetBaseId = group.strategicActivityTargetBaseId
    marker.strategicActivityTargetGroupId = group.strategicActivityTargetGroupId
    if NPCStrategicAIBridge and NPCStrategicAIBridge.BuildMarkerFields then
        NPCStrategicAIBridge.BuildMarkerFields(marker, group)
    end
    marker.updatedAt = group.updatedAt or (getGameTime and getGameTime():getWorldAgeHours() or 0)
    return NPCWorldDirectorBridge.ApplyVirtualGroupMapMotionFields(director, marker, group)
end

function NPCWorldDirectorBridge.StrategicSide(side)
    if NPCFactionBridge and NPCFactionBridge.NormalizeSide then
        local ok, s = pcall(function() return NPCFactionBridge.NormalizeSide(side) end)
        if ok and s then return s end
    end
    side = tostring(side or ""):lower()
    if side == "red" or side == "green" or side == "blue" then return side end
    return nil
end

function NPCWorldDirectorBridge.NextStrategicGroupId(gmd, prefix)
    if not gmd then return nil end
    gmd.WorldDirector = gmd.WorldDirector or {}
    local n = tonumber(gmd.WorldDirector.nextGroupId) or 1
    gmd.WorldDirector.nextGroupId = n + 1
    return tostring(prefix or "SG") .. tostring(n)
end

function NPCWorldDirectorBridge.StrategicGroupExists(gmd, groupId)
    if not groupId or not gmd or type(gmd.VirtualGroups) ~= "table" then return false end
    local group = gmd.VirtualGroups[tostring(groupId)]
    return type(group) == "table" and (tonumber(group.count) or 0) > 0 and group.removed ~= true
end

function NPCWorldDirectorBridge.MakeStrategicWave(side, size, archetype)
    return {
        enabled = true,
        enemyBehaviour = side == "red" and 2 or 7,
        firstDay = 0,
        lastDay = 99999,
        spawnHourlyChance = 0,
        groupSize = size or 4,
        clanId = side == "red" and 4 or 8,
        hasPistolChance = archetype == "leader" and 100 or 65,
        pistolMagCount = archetype == "leader" and 3 or 2,
        hasRifleChance = archetype == "leader" and 100 or 55,
        rifleMagCount = archetype == "leader" and 3 or 2
    }
end

function NPCWorldDirectorBridge.StrategicGuardOffset(index)
    local offsets = {
        {x=0, y=0, zone="command"}, {x=3, y=1, zone="guard"}, {x=-3, y=-1, zone="guard"},
        {x=1, y=4, zone="patrol"}, {x=-1, y=-4, zone="patrol"}, {x=5, y=0, zone="staging"},
        {x=-5, y=0, zone="staging"}, {x=0, y=6, zone="guard"}, {x=0, y=-6, zone="guard"}
    }
    return offsets[((tonumber(index) or 1) - 1) % #offsets + 1]
end

local function wd_firstOutfitPool(names)
    if not NPCOutfitsBridge or type(names) ~= "table" then return nil end
    for _, name in ipairs(names) do
        local pool = NPCOutfitsBridge[name]
        if type(pool) == "table" and #pool > 0 then return pool end
    end
    return nil
end

function NPCWorldDirectorBridge.BaseArchetypeOutfitPool(archetype, side)
    archetype = tostring(archetype or "")
    if archetype == "military" then return wd_firstOutfitPool({"NewOrder", "PrivateMilitia", "Police", "Veteran", "Prepper"}) end
    if archetype == "checkpoint" then return wd_firstOutfitPool({"Police", "PrivateMilitia", "Veteran", "Prepper"}) end
    if archetype == "elite_safehouse" then return wd_firstOutfitPool({"Veteran", "NewOrder", "Police", "PrivateMilitia", "Prepper"}) end
    if archetype == "punk" then return wd_firstOutfitPool({"Biker", "DesperateCitizen", "Crimial", "DoomRider"}) end
    if archetype == "raider" then return wd_firstOutfitPool({"DeathLegion", "Crimial", "PrivateMilitia", "DoomRider"}) end
    if side == "red" then return wd_firstOutfitPool({"DeathLegion", "PrivateMilitia", "Crimial"}) end
    return wd_firstOutfitPool({"Veteran", "Prepper", "Police"})
end

function NPCWorldDirectorBridge.ApplyBaseArchetypeToMember(member, archetype, side, index)
    if type(member) ~= "table" then return member end
    archetype = tostring(archetype or "")
    if archetype == "" then return member end

    member.baseArchetype = archetype
    member.baseStyle = archetype
    member.preferCover = true
    member.strategicBaseSpecialist = true

    if archetype == "military" then
        member.behaviorStyle = "disciplined_guard"
        member.tacticalRole = member.tacticalRole == "leader" and member.tacticalRole or (((tonumber(index) or 1) % 4 == 0) and "ammo_guard" or "rifle_guard")
        member.accuracyBoost = math.max(tonumber(member.accuracyBoost) or 1, 1.28)
        member.health = math.max(tonumber(member.health) or 3.0, 3.7)
    elseif archetype == "checkpoint" then
        member.behaviorStyle = "road_control"
        member.roadBias = true
        member.preferRoads = true
        member.tacticalRole = member.tacticalRole == "leader" and member.tacticalRole or "road_guard"
        member.accuracyBoost = math.max(tonumber(member.accuracyBoost) or 1, 1.18)
    elseif archetype == "elite_safehouse" then
        member.behaviorStyle = "elite_defense"
        member.tacticalRole = member.tacticalRole == "leader" and member.tacticalRole or "elite_bodyguard"
        member.accuracyBoost = math.max(tonumber(member.accuracyBoost) or 1, 1.42)
        member.health = math.max(tonumber(member.health) or 3.0, 4.0)
        member.commandAura = member.commandAura or ((tonumber(index) or 1) == 1)
    elseif archetype == "punk" then
        member.behaviorStyle = "chaotic_guard"
        member.tacticalRole = member.tacticalRole == "leader" and member.tacticalRole or "skirmisher"
        member.accuracyBoost = math.max(tonumber(member.accuracyBoost) or 1, 1.08)
        member.health = math.max(tonumber(member.health) or 3.0, 3.45)
    elseif archetype == "raider" then
        member.behaviorStyle = "aggressive_raiders"
        member.tacticalRole = member.tacticalRole == "leader" and member.tacticalRole or "assault_guard"
        member.accuracyBoost = math.max(tonumber(member.accuracyBoost) or 1, 1.15)
        member.health = math.max(tonumber(member.health) or 3.0, 3.55)
    end
    member.maxHealth = math.max(tonumber(member.maxHealth) or 0, tonumber(member.health) or 0)

    local pool = NPCWorldDirectorBridge.BaseArchetypeOutfitPool(archetype, side)
    if type(pool) == "table" and #pool > 0 then
        member.outfit = pool[((math.max(1, tonumber(index) or 1) - 1) % #pool) + 1]
    end
    return member
end

function NPCWorldDirectorBridge.MakeStrategicMember(director, gmd, groupId, side, index, kind, leader, baseArchetype)
    local wave = NPCWorldDirectorBridge.MakeStrategicWave(side, 1, leader and "leader" or kind)
    local member = NPCWorldDirectorBridge.PrepareVirtualMember(director, gmd, wave, groupId, index, side, false)
    if type(member) ~= "table" then return nil end

    member.strategicSpawn = true
    member.strategicRole = kind
    member.role = kind == "checkpoint" and "checkpoint_guard" or "base_guard"
    member.tacticalRole = index == 1 and "leader" or (kind == "checkpoint" and "road_guard" or "sentinel")
    member.program = {name = kind == "base" and "BaseGuard" or "Raider", stage = "Prepare"}
    member.accuracyBoost = math.max(tonumber(member.accuracyBoost) or 1, index == 1 and 1.35 or 1.12)
    member.health = math.max(tonumber(member.health) or 3.0, index == 1 and 4.4 or 3.4)
    member.maxHealth = member.health
    member.roadBias = kind == "checkpoint" or member.roadBias
    member.preferRoads = kind == "checkpoint" or member.preferRoads
    member.factionSide = side
    member.faction = side
    member.side = side
    member.patrolColor = side

    if baseArchetype then
        NPCWorldDirectorBridge.ApplyBaseArchetypeToMember(member, baseArchetype, side, index)
    end

    if leader and NPCLeadersBridge and NPCLeadersBridge.ApplyLeaderIdentityToMember and index == 1 then
        NPCLeadersBridge.ApplyLeaderIdentityToMember(member, leader, index)
    elseif leader and kind == "base" and NPCLeadersBridge and NPCLeadersBridge.ApplyLeaderSquadIdentityToMember then
        NPCLeadersBridge.ApplyLeaderSquadIdentityToMember(member, leader, index)
    elseif kind == "checkpoint" and NPCOutfitsBridge then
        local pool = side == "red" and (NPCOutfitsBridge.PrivateMilitia or NPCOutfitsBridge.Crimial) or (NPCOutfitsBridge.Police or NPCOutfitsBridge.Veteran)
        if type(pool) == "table" and #pool > 0 then member.outfit = pool[((index - 1) % #pool) + 1] end
    elseif kind == "base" and NPCOutfitsBridge and not baseArchetype then
        local pool = side == "red" and (NPCOutfitsBridge.DeathLegion or NPCOutfitsBridge.PrivateMilitia) or (NPCOutfitsBridge.Veteran or NPCOutfitsBridge.Prepper)
        if type(pool) == "table" and #pool > 0 then member.outfit = pool[((index - 1) % #pool) + 1] end
    end

    if NPCCreatorBridge and NPCCreatorBridge.ApplyAppearanceStyleToMember then
        NPCCreatorBridge.ApplyAppearanceStyleToMember(member)
    end
    return member
end

function NPCWorldDirectorBridge.SetStrategicMemberAnchors(member, x, y, z, index, kind, target)
    if type(member) ~= "table" then return member end
    local off = NPCWorldDirectorBridge.StrategicGuardOffset(index)
    local ax = math.floor((tonumber(x) or 0) + (tonumber(off.x) or 0))
    local ay = math.floor((tonumber(y) or 0) + (tonumber(off.y) or 0))
    local az = tonumber(z) or 0
    member.guardPoint = {x=ax, y=ay, z=az}
    member.homeBaseZoneType = kind == "checkpoint" and "patrol" or off.zone
    member.baseZoneType = member.homeBaseZoneType
    if kind == "checkpoint" and target then
        member.patrolTarget = {x=target.x, y=target.y, z=target.z or az}
        member.targetX = target.x
        member.targetY = target.y
        member.targetZ = target.z or az
        member.order = nil
    else
        member.order = {name="Guard", anchor={x=ax, y=ay, z=az}, source="strategic_marker"}
    end
    return member
end

function NPCWorldDirectorBridge.CreateStrategicVirtualGroup(director, gmd, opts)
    if not (director and gmd and type(opts) == "table") then return nil end
    if director.SP_BOOTSTRAP_GATE_VIRTUAL_GROUPS ~= false then
        local gate, retry, reason = NPCWorldDirectorBridge.ShouldBootstrapGate(director, "strategic_virtual_group")
        if gate then NPCWorldDirectorBridge.RecordBootstrapGate("strategic_virtual_group", retry, reason); return nil end
    end
    gmd.VirtualGroups = gmd.VirtualGroups or {}
    gmd.DebugMapMarkers = gmd.DebugMapMarkers or {}
    local side = NPCWorldDirectorBridge.StrategicSide(opts.side)
    if not side then return nil end
    local groupId = NPCWorldDirectorBridge.NextStrategicGroupId(gmd, opts.prefix or "SG")
    if not groupId then return nil end

    local x = math.floor(tonumber(opts.x) or 0)
    local y = math.floor(tonumber(opts.y) or 0)
    local z = tonumber(opts.z) or 0
    local count = NPCWorldDirectorBridge.ClampGroupSize(opts.count or 4)
    local target = opts.target
    local members = {}
    for i=1, count do
        local member = NPCWorldDirectorBridge.MakeStrategicMember(director, gmd, groupId, side, i, opts.kind, i == 1 and opts.leader or nil, opts.baseArchetype or opts.archetype)
        if member then
            member.homeBaseId = opts.baseId
            member.checkpointId = opts.checkpointId
            member.strategicMarkerId = opts.markerId
            NPCWorldDirectorBridge.SetStrategicMemberAnchors(member, x, y, z, i, opts.kind, target)
            table.insert(members, member)
        end
    end
    if #members <= 0 then return nil end

    local worldAge = getGameTime and getGameTime():getWorldAgeHours() or 0
    local group = {
        id = groupId,
        x = x,
        y = y,
        z = z,
        count = #members,
        hostile = side == "red",
        program = {name = opts.kind == "base" and "BaseGuard" or "Raider", stage = "Prepare"},
        members = members,
        virtual = true,
        activated = false,
        createdAt = worldAge,
        updatedAt = worldAge,
        state = opts.state or "strategic_guard",
        spawnClass = opts.kind or "strategic",
        targetX = target and target.x or x,
        targetY = target and target.y or y,
        targetZ = target and target.z or z,
        targetClass = opts.kind == "checkpoint" and "checkpoint_road_patrol" or "base_guard",
        speed = tonumber(director.VIRTUAL_MOVE_SPEED_TILES_PER_HOUR) or 120,
        factionSide = side,
        faction = side,
        side = side,
        patrolColor = side,
        baseArchetype = opts.baseArchetype or opts.archetype,
        baseStyle = opts.baseArchetype or opts.archetype,
        behaviorStyle = opts.behaviorStyle,
        lootBias = opts.lootBias,
        fortifyLevel = opts.fortifyLevel,
        roadBias = opts.kind == "checkpoint",
        preferRoads = opts.kind == "checkpoint",
        roadPatrol = opts.kind == "checkpoint",
        checkpointId = opts.checkpointId,
        homeBaseId = opts.baseId or opts.originBaseId,
        originBaseId = opts.originBaseId or opts.baseId,
        homeBaseOwner = opts.baseOwner,
        baseOwnedGlobalSquad = (opts.baseId or opts.originBaseId) ~= nil,
        routeOwnerBaseId = opts.originBaseId or opts.baseId,
        baseOwnedRole = opts.kind == "base" and "garrison" or (opts.kind == "checkpoint" and "checkpoint_patrol" or "field"),
        strategicMarkerId = opts.markerId,
        strategicGroup = true,
        leaderId = opts.leader and opts.leader.id or nil,
        leaderName = opts.leader and opts.leader.name or nil,
        leaderRole = opts.leader and opts.leader.kind or nil,
        leaderSide = opts.leader and opts.leader.side or nil,
        isFactionLeader = opts.leader ~= nil,
        leader = opts.leader ~= nil
    }

    if opts.leader and NPCLeadersBridge and NPCLeadersBridge.MarkerFields then
        NPCLeadersBridge.MarkerFields(group, opts.leader)
    end
    if NPCWorldDirectorBridge.EnsureBaseOwnedGroup then
        NPCWorldDirectorBridge.EnsureBaseOwnedGroup(director, gmd, group, worldAge, "strategic_group_created")
    end
    if NPCWorldDirectorBridge.TryConsumeBaseEconomyForGroup and group.homeBaseId then
        local homeBase = NPCWorldDirectorBridge.GetStrategicBaseById and NPCWorldDirectorBridge.GetStrategicBaseById(gmd, group.homeBaseId) or nil
        if homeBase then NPCWorldDirectorBridge.TryConsumeBaseEconomyForGroup(director, gmd, homeBase, group, group.baseOwnedRole or group.state, worldAge) end
    end
    if NPCIdentityBridge and NPCIdentityBridge.TouchVirtualGroup then
        NPCIdentityBridge.TouchVirtualGroup(gmd, group)
    end
    if NPCPersistentNPCBridge and NPCPersistentNPCBridge.RegisterGroup then
        NPCPersistentNPCBridge.RegisterGroup(gmd, group)
    end

    gmd.VirtualGroups[groupId] = group
    local marker = nil
    if group.roadPatrol then
        marker = NPCWorldDirectorBridge.BuildRoadPatrolMarker(director, gmd, group, opts.namePrefix or "Checkpoint patrol ")
    else
        marker = NPCWorldDirectorBridge.BuildVirtualGroupMarker(group)
    end
    if marker then
        marker.name = NPCWorldDirectorBridge.GetVirtualGroupDisplayName(groupId, group, opts.name or marker.name)
        group.name = marker.name
        marker.displayName = marker.name
        marker.markerType = "group"
        marker.strategicGroup = true
        marker.checkpointId = opts.checkpointId
        marker.baseId = opts.baseId
        marker.baseArchetype = group.baseArchetype
        marker.baseStyle = group.baseStyle
        marker.behaviorStyle = group.behaviorStyle
        marker.lootBias = group.lootBias
        marker.leaderId = group.leaderId
        marker.leaderName = group.leaderName
        marker.leaderRole = group.leaderRole
        gmd.DebugMapMarkers[groupId] = marker
        NPCWorldDirectorBridge.SendDebugMapUpdate(marker)
    end
    return group
end

function NPCWorldDirectorBridge.EnsureCheckpointGuardGroups(director, gmd, worldAge)
    if not (director and gmd and gmd.NPCCheckpointsBridge and type(gmd.NPCCheckpointsBridge.active) == "table") then return 0 end
    local changed = 0
    for _, cp in pairs(gmd.NPCCheckpointsBridge.active) do
        if type(cp) == "table" and cp.status ~= "removed" and cp.x and cp.y then
            if not NPCWorldDirectorBridge.StrategicGroupExists(gmd, cp.guardGroupId) then
                local player = NPCWorldDirectorBridge.GetNearestPlayer(director, cp.x, cp.y, director.STRATEGIC_MARKER_ACTIVATION_RADIUS)
                if player then
                    local side = NPCWorldDirectorBridge.StrategicSide(cp.side or cp.checkpointSide) or "red"
                    local target = NPCWorldDirectorBridge.GetNearbyRoadPoint(director, cp.x, cp.y, director.ROAD_PATROL_TARGET_RADIUS)
                        or NPCWorldDirectorBridge.GetNearbyPreferredPoint(director, cp.x, cp.y, director.VIRTUAL_TARGET_RADIUS)
                    local group = NPCWorldDirectorBridge.CreateStrategicVirtualGroup(director, gmd, {
                        prefix = "CP",
                        kind = "checkpoint",
                        state = "checkpoint_patrol",
                        x = cp.x,
                        y = cp.y,
                        z = cp.z or 0,
                        side = side,
                        count = tonumber(director.CHECKPOINT_GUARD_GROUP_SIZE) or 5,
                        checkpointId = cp.id,
                        markerId = cp.markerId or cp.id,
                        target = target,
                        name = tostring(NPCCheckpointsBridge and NPCCheckpointsBridge.GetSideLabel and NPCCheckpointsBridge.GetSideLabel(side) or side) .. " checkpoint patrol " .. tostring(cp.id),
                        namePrefix = "Checkpoint patrol "
                    })
                    if group then
                        group.checkpointGuard = true
                        group.forceCheckpointActivation = true
                        group.checkpointId = group.checkpointId or cp.id
                        cp.guardGroupId = group.id
                        cp.updatedAt = worldAge
                        changed = changed + 1
                    end
                end
            else
                local group = gmd.VirtualGroups and gmd.VirtualGroups[tostring(cp.guardGroupId)] or nil
                if type(group) == "table" then
                    group.checkpointGuard = true
                    group.forceCheckpointActivation = true
                    group.checkpointId = group.checkpointId or cp.id
                    group.state = group.state or "checkpoint_patrol"
                    group.x = tonumber(group.x) or tonumber(cp.x) or group.x
                    group.y = tonumber(group.y) or tonumber(cp.y) or group.y
                    group.z = tonumber(group.z) or tonumber(cp.z) or group.z
                end
            end
        end
    end
    return changed
end

function NPCWorldDirectorBridge.EnsureBaseGarrisonGroups(director, gmd, worldAge)
    if not (director and gmd and type(gmd.BaseCamps) == "table") then return 0 end
    local changed = 0
    for _, base in pairs(gmd.BaseCamps) do
        if type(base) == "table" and base.x and base.y then
            local side = NPCWorldDirectorBridge.StrategicSide(base.owner or base.captureTeam or base.commanderSide)
            if side and not NPCWorldDirectorBridge.StrategicGroupExists(gmd, base.garrisonGroupId) then
                local player = NPCWorldDirectorBridge.GetNearestPlayer(director, base.x, base.y, director.STRATEGIC_MARKER_ACTIVATION_RADIUS)
                if player then
                    local leader = nil
                    if NPCLeadersBridge and NPCLeadersBridge.EnsureBaseCommander then
                        leader = NPCLeadersBridge.EnsureBaseCommander(gmd, base)
                    end
                    if NPCBaseCampServerBridge and NPCBaseCampServerBridge.EnsureBaseArchetype then
                        NPCBaseCampServerBridge.EnsureBaseArchetype(base)
                    end
                    local garrisonSize = tonumber(director.BASE_GARRISON_GROUP_SIZE) or 6
                    if NPCBaseCampServerBridge and NPCBaseCampServerBridge.GetBaseGarrisonSize then
                        garrisonSize = NPCBaseCampServerBridge.GetBaseGarrisonSize(base) or garrisonSize
                    end
                    local group = NPCWorldDirectorBridge.CreateStrategicVirtualGroup(director, gmd, {
                        prefix = "BG",
                        kind = "base",
                        state = "base_garrison",
                        x = base.x,
                        y = base.y,
                        z = base.z or 0,
                        side = side,
                        count = garrisonSize,
                        baseId = base.id,
                        markerId = base.id,
                        leader = leader,
                        baseArchetype = base.baseArchetype or base.archetype,
                        behaviorStyle = base.behaviorStyle,
                        lootBias = base.lootBias,
                        fortifyLevel = base.fortifyLevel,
                        name = tostring(base.baseArchetypeLabel or base.name or "Base") .. " garrison"
                    })
                    if group then
                        base.garrisonGroupId = group.id
                        base.homeGroupId = base.homeGroupId or group.id
                        if NPCBaseCampServerBridge and NPCBaseCampServerBridge.AssignGroupZone then
                            pcall(function() NPCBaseCampServerBridge.AssignGroupZone(base, group, group.id) end)
                        end
                        base.updatedAt = worldAge
                        changed = changed + 1
                    end
                end
            else
                local group = gmd.VirtualGroups and gmd.VirtualGroups[tostring(base.garrisonGroupId)] or nil
                if type(group) == "table" and NPCBaseCampServerBridge and NPCBaseCampServerBridge.AssignGroupZone then
                    pcall(function() NPCBaseCampServerBridge.AssignGroupZone(base, group, group.id) end)
                end
            end
        end
    end
    return changed
end

function NPCWorldDirectorBridge.EnsureStrategicMarkerGroups(director, gmd, worldAge)
    if not (director and director.STRATEGIC_MARKER_GROUPS_ENABLED ~= false and gmd) then return 0 end
    gmd.WorldDirector = gmd.WorldDirector or {}
    local last = tonumber(gmd.WorldDirector.lastStrategicMarkerGroupCheck) or 0
    local minRefresh = tonumber(director.STRATEGIC_GROUP_MIN_REFRESH_HOURS) or 0.05
    if last > 0 and worldAge - last < minRefresh then return 0 end
    gmd.WorldDirector.lastStrategicMarkerGroupCheck = worldAge

    local changed = 0
    changed = changed + NPCWorldDirectorBridge.EnsureCheckpointGuardGroups(director, gmd, worldAge)
    changed = changed + NPCWorldDirectorBridge.EnsureBaseGarrisonGroups(director, gmd, worldAge)
    if changed > 0 and TransmitNPCModData then TransmitNPCModData() end
    return changed
end

function NPCWorldDirectorBridge.StrategicWarSideAnchor(director, side, axis)
    local minX, minY, maxX, maxY = NPCWorldDirectorBridge.GetWorldBounds(director)
    local midX = math.floor((minX + maxX) / 2)
    local midY = math.floor((minY + maxY) / 2)
    local marginX = math.floor(math.max(300, (maxX - minX) * 0.08))
    local marginY = math.floor(math.max(300, (maxY - minY) * 0.08))
    local redFirst = axis == "north_south" and minY or minX
    local greenFirst = axis == "north_south" and maxY or maxX
    if side == "red" then
        if axis == "north_south" then return {x=midX, y=redFirst + marginY, z=0} end
        return {x=redFirst + marginX, y=midY, z=0}
    end
    if axis == "north_south" then return {x=midX, y=greenFirst - marginY, z=0} end
    return {x=greenFirst - marginX, y=midY, z=0}
end

function NPCWorldDirectorBridge.DistanceToPoint(record, point)
    if not (record and point and record.x and record.y and point.x and point.y) then return 999999 end
    return NPCWorldDirectorBridge.Dist(record.x, record.y, point.x, point.y)
end

function NPCWorldDirectorBridge.FindNearestUnclaimedWarBase(gmd, point, reservedId)
    local best = nil
    local bestDist = 999999
    for id, base in pairs(gmd and gmd.BaseCamps or {}) do
        if type(base) == "table" and base.x and base.y and (not base.owner or tostring(base.owner) == "") and tostring(id) ~= tostring(reservedId or "") then
            local d = NPCWorldDirectorBridge.DistanceToPoint(base, point)
            if d < bestDist then
                best = base
                best.id = best.id or tostring(id)
                bestDist = d
            end
        end
    end
    return best
end

function NPCWorldDirectorBridge.SeedStrategicWarBase(gmd, side, point, reservedId, worldAge)
    local base = NPCWorldDirectorBridge.FindNearestUnclaimedWarBase(gmd, point, reservedId)
    if not base then return nil end
    base.owner = side
    base.captureTeam = nil
    base.progress = 100
    base.status = "controlled"
    base.strategicSeedBase = true
    base.strategicSeedSide = side
    base.updatedAt = worldAge
    if NPCBaseCampServerBridge and NPCBaseCampServerBridge.SendBaseMarkers then
        pcall(function() NPCBaseCampServerBridge.SendBaseMarkers(base, true) end)
    end
    return base
end

function NPCWorldDirectorBridge.CountStrategicSideGroups(gmd, side)
    local count = 0
    for _, group in pairs(gmd and gmd.VirtualGroups or {}) do
        if type(group) == "table" and not group.activated and NPCWorldDirectorBridge.GroupMemberCount(group) > 0 then
            local groupSide = group.side or group.factionSide or group.patrolColor or (group.hostile and "red" or "green")
            if tostring(groupSide) == tostring(side) then count = count + 1 end
        end
    end
    return count
end

function NPCWorldDirectorBridge.BalanceSpawnSideForStrategicWar(director, gmd, event, groupSide)
    if not (director and director.STRATEGIC_WAR_ENABLED ~= false and gmd and type(event) == "table") then return groupSide end
    if groupSide ~= "red" and groupSide ~= "green" then return groupSide end
    local maxDelta = tonumber(director.STRATEGIC_GROUP_SIDE_BALANCE_MAX_DELTA) or 2
    if maxDelta < 0 then maxDelta = 0 end
    local redCount = NPCWorldDirectorBridge.CountStrategicSideGroups(gmd, "red")
    local greenCount = NPCWorldDirectorBridge.CountStrategicSideGroups(gmd, "green")
    if groupSide == "red" and redCount > greenCount + maxDelta then
        event.hostile = false
        return "green"
    end
    if groupSide == "green" and greenCount > redCount + maxDelta then
        event.hostile = true
        return "red"
    end
    return groupSide
end

function NPCWorldDirectorBridge.StrategicSideCentroid(gmd, side)
    local sx, sy, weight = 0, 0, 0
    for _, base in pairs(gmd and gmd.BaseCamps or {}) do
        if type(base) == "table" and base.x and base.y and (base.owner == side or base.captureTeam == side) then
            sx = sx + base.x * 4
            sy = sy + base.y * 4
            weight = weight + 4
        end
    end
    for _, group in pairs(gmd and gmd.VirtualGroups or {}) do
        if type(group) == "table" and group.x and group.y and NPCWorldDirectorBridge.GroupMemberCount(group) > 0 then
            local groupSide = group.side or group.factionSide or group.patrolColor or (group.hostile and "red" or "green")
            if tostring(groupSide) == tostring(side) then
                local w = math.max(1, tonumber(group.count) or 1)
                sx = sx + group.x * w
                sy = sy + group.y * w
                weight = weight + w
            end
        end
    end
    if weight <= 0 then return nil end
    return {x=math.floor(sx / weight), y=math.floor(sy / weight), z=0, weight=weight}
end

function NPCWorldDirectorBridge.CountStrategicWarBases(gmd)
    local redBaseCount, greenBaseCount, neutralBaseCount = 0, 0, 0
    for _, base in pairs(gmd and gmd.BaseCamps or {}) do
        if type(base) == "table" then
            if base.owner == "red" then
                redBaseCount = redBaseCount + 1
            elseif base.owner == "green" then
                greenBaseCount = greenBaseCount + 1
            elseif not base.owner or tostring(base.owner) == "" or tostring(base.owner) == "neutral" then
                neutralBaseCount = neutralBaseCount + 1
            end
        end
    end
    return redBaseCount, greenBaseCount, neutralBaseCount
end

local function wd_initialBaseOwnerHash(base, salt)
    local x = tonumber(base and base.x) or 0
    local y = tonumber(base and base.y) or 0
    local key = tostring(base and (base.id or base.name or "") or "") .. tostring(salt or "")
    local sum = 0
    for i = 1, #key do
        sum = sum + string.byte(key, i) * (i + 23)
    end
    local v = math.sin(x * 12.9898 + y * 78.233 + sum * 0.04123) * 43758.5453
    return v - math.floor(v)
end

local function wd_initialBaseIsNeutral(base)
    if type(base) ~= "table" then return false end
    local owner = base.owner
    local captureTeam = base.captureTeam
    owner = owner ~= nil and tostring(owner) or ""
    captureTeam = captureTeam ~= nil and tostring(captureTeam) or ""
    return (owner == "" or owner == "neutral") and (captureTeam == "" or captureTeam == "neutral")
end

local function wd_nearestInitialOwnedSide(gmd, base, radius)
    if not (gmd and base and base.x and base.y) then return nil, nil end
    local bestSide = nil
    local bestDist = tonumber(radius) or 0
    if bestDist <= 0 then return nil, nil end
    for _, other in pairs(gmd.BaseCamps or {}) do
        if type(other) == "table" and other ~= base and other.x and other.y and (other.owner == "red" or other.owner == "green") then
            local d = NPCWorldDirectorBridge.DistanceToPoint(base, other)
            if d <= bestDist then
                bestDist = d
                bestSide = other.owner
            end
        end
    end
    return bestSide, bestDist
end

local function wd_chooseInitialFactionBaseOwner(director, gmd, base, redCount, greenCount)
    if not (base and base.x and base.y) then return nil end
    local maxImbalance = tonumber(director and director.STRATEGIC_INITIAL_FACTION_BASE_MAX_IMBALANCE) or 1
    if redCount > greenCount + maxImbalance then return "green" end
    if greenCount > redCount + maxImbalance then return "red" end

    local nearSide = wd_nearestInitialOwnedSide(gmd, base, tonumber(director and director.STRATEGIC_INITIAL_FACTION_BASE_PROVOCATION_RADIUS) or 1500)
    if nearSide and wd_initialBaseOwnerHash(base, "near") > 0.28 then
        return nearSide == "red" and "green" or "red"
    end

    local grid = math.max(180, tonumber(director and director.STRATEGIC_INITIAL_FACTION_BASE_GRID) or 820)
    local cellX = math.floor((tonumber(base.x) or 0) / grid)
    local cellY = math.floor((tonumber(base.y) or 0) / grid)
    local side = ((cellX + cellY) % 2 == 0) and "red" or "green"
    if wd_initialBaseOwnerHash(base, "flip") > 0.66 then side = side == "red" and "green" or "red" end

    if side == "red" and redCount > greenCount + maxImbalance then return "green" end
    if side == "green" and greenCount > redCount + maxImbalance then return "red" end
    return side
end

function NPCWorldDirectorBridge.EnsureInitialFactionBaseOwnership(director, gmd, war, worldAge, redBaseCount, greenBaseCount)
    if not (director and director.STRATEGIC_INITIAL_FACTION_BASES_ENABLED ~= false and gmd and type(gmd.BaseCamps) == "table") then
        return false, redBaseCount or 0, greenBaseCount or 0
    end

    redBaseCount = tonumber(redBaseCount) or 0
    greenBaseCount = tonumber(greenBaseCount) or 0
    local changed = false
    local assigned = 0
    local ids = {}
    for id, base in pairs(gmd.BaseCamps or {}) do
        if type(base) == "table" and base.x and base.y and wd_initialBaseIsNeutral(base) then
            ids[#ids + 1] = tostring(id)
            base.id = base.id or tostring(id)
        end
    end
    table.sort(ids, function(a, b)
        local ba = gmd.BaseCamps[a]
        local bb = gmd.BaseCamps[b]
        local ha = wd_initialBaseOwnerHash(ba, "sort")
        local hb = wd_initialBaseOwnerHash(bb, "sort")
        if ha == hb then return tostring(a) < tostring(b) end
        return ha < hb
    end)

    for _, id in ipairs(ids) do
        local base = gmd.BaseCamps[id]
        if type(base) == "table" and wd_initialBaseIsNeutral(base) then
            local side = wd_chooseInitialFactionBaseOwner(director, gmd, base, redBaseCount, greenBaseCount)
            if side == "red" or side == "green" then
                base.owner = side
                base.captureTeam = nil
                base.progress = 100
                base.status = "controlled"
                base.initialFactionOwner = side
                base.initialFactionOwnerStage = 447
                base.strategicSeedSide = side
                base.updatedAt = worldAge
                if side == "red" then redBaseCount = redBaseCount + 1 else greenBaseCount = greenBaseCount + 1 end
                assigned = assigned + 1
                changed = true
                if NPCBaseCampServerBridge and NPCBaseCampServerBridge.UpdateVirtualGarrisonPower then
                    pcall(function() NPCBaseCampServerBridge.UpdateVirtualGarrisonPower(base, worldAge) end)
                end
                if NPCBaseCampServerBridge and NPCBaseCampServerBridge.SendBaseMarkers then
                    pcall(function() NPCBaseCampServerBridge.SendBaseMarkers(base, true) end)
                end
            end
        end
    end

    if changed then
        war.initialFactionBaseOwnershipStage = 447
        war.initialFactionBaseOwnershipAt = worldAge
        war.initialFactionBaseOwnershipAssigned = (tonumber(war.initialFactionBaseOwnershipAssigned) or 0) + assigned
        NPCWorldDirectorBridge.BehaviorLog(director, "initial_faction_base_ownership", {assigned=assigned, redBases=redBaseCount, greenBases=greenBaseCount})
    end
    return changed, redBaseCount, greenBaseCount
end

function NPCWorldDirectorBridge.FindBalanceSeedBase(gmd, side, war, reservedId)
    local anchor = side == "red" and war.redAnchor or war.greenAnchor
    local front = war.front
    local best = nil
    local bestScore = 999999
    for id, base in pairs(gmd and gmd.BaseCamps or {}) do
        if type(base) == "table" and base.x and base.y and (not base.owner or tostring(base.owner) == "") and tostring(id) ~= tostring(reservedId or "") then
            local score = NPCWorldDirectorBridge.DistanceToPoint(base, anchor)
            if front then score = score + NPCWorldDirectorBridge.DistanceToPoint(base, front) * 0.35 end
            if side == "green" and base.captureTeam == "green" then score = score - 220 end
            if side == "red" and base.captureTeam == "red" then score = score - 220 end
            if score < bestScore then
                best = base
                best.id = best.id or tostring(id)
                bestScore = score
            end
        end
    end
    return best
end

function NPCWorldDirectorBridge.BalanceStrategicWarBases(director, gmd, war, redBaseCount, greenBaseCount, worldAge)
    if not (director and gmd and war) then return false, redBaseCount or 0, greenBaseCount or 0 end
    local maxImbalance = tonumber(director.STRATEGIC_WAR_MAX_BASE_IMBALANCE) or 1
    if maxImbalance < 0 then maxImbalance = 0 end
    redBaseCount = tonumber(redBaseCount) or 0
    greenBaseCount = tonumber(greenBaseCount) or 0
    local changed = false
    local safety = 0
    while math.abs(redBaseCount - greenBaseCount) > maxImbalance and safety < 3 do
        safety = safety + 1
        local side = redBaseCount > greenBaseCount and "green" or "red"
        local reserved = side == "green" and war.redSeedBaseId or war.greenSeedBaseId
        local base = NPCWorldDirectorBridge.FindBalanceSeedBase(gmd, side, war, reserved)
        if not base then break end
        base.owner = side
        base.captureTeam = nil
        base.progress = 100
        base.status = "controlled"
        base.strategicBalanceSeed = true
        base.strategicSeedSide = side
        base.updatedAt = worldAge
        if side == "green" then greenBaseCount = greenBaseCount + 1 else redBaseCount = redBaseCount + 1 end
        if NPCBaseCampServerBridge and NPCBaseCampServerBridge.SendBaseMarkers then
            pcall(function() NPCBaseCampServerBridge.SendBaseMarkers(base, true) end)
        end
        changed = true
    end
    return changed, redBaseCount, greenBaseCount
end

function NPCWorldDirectorBridge.SelectStrategicPressureSide(director, gmd, war, redCount, greenCount, target)
    if redCount < target and greenCount >= target then return "red" end
    if greenCount < target and redCount >= target then return "green" end
    if redCount < greenCount and redCount < target then return "red" end
    if greenCount < redCount and greenCount < target then return "green" end
    if not (redCount < target and greenCount < target) then return nil end

    local redBases, greenBases = NPCWorldDirectorBridge.CountStrategicWarBases(gmd)
    if redBases > greenBases then return "green" end
    if greenBases > redBases then return "red" end

    if director and director.STRATEGIC_FRONT_TIE_ALTERNATE_SIDES ~= false then
        return war and war.lastPressureSide == "red" and "green" or "red"
    end
    return "green"
end

function NPCWorldDirectorBridge.EnsureStrategicWarState(director, gmd, worldAge)
    if not (director and director.STRATEGIC_WAR_ENABLED ~= false and gmd) then return false end
    gmd.WorldDirector = gmd.WorldDirector or {}
    local war = gmd.WorldDirector.strategicWar
    local changed = false
    if type(war) ~= "table" then
        local axis = (ZombRand and ZombRand(2) == 0) and "west_east" or "north_south"
        war = {
            version = 1,
            axis = axis,
            redAnchor = NPCWorldDirectorBridge.StrategicWarSideAnchor(director, "red", axis),
            greenAnchor = NPCWorldDirectorBridge.StrategicWarSideAnchor(director, "green", axis),
            createdAt = worldAge,
            lastFrontUpdate = 0,
            lastPressureAt = 0
        }
        gmd.WorldDirector.strategicWar = war
        changed = true
    end

    local redBaseCount, greenBaseCount = NPCWorldDirectorBridge.CountStrategicWarBases(gmd)
    local initialChanged = false
    initialChanged, redBaseCount, greenBaseCount = NPCWorldDirectorBridge.EnsureInitialFactionBaseOwnership(director, gmd, war, worldAge, redBaseCount, greenBaseCount)
    changed = changed or initialChanged

    if redBaseCount <= 0 then
        local base = NPCWorldDirectorBridge.SeedStrategicWarBase(gmd, "red", war.redAnchor, war.greenSeedBaseId, worldAge)
        if base then war.redSeedBaseId = base.id; redBaseCount = redBaseCount + 1; changed = true end
    end
    if greenBaseCount <= 0 then
        local base = NPCWorldDirectorBridge.SeedStrategicWarBase(gmd, "green", war.greenAnchor, war.redSeedBaseId, worldAge)
        if base then war.greenSeedBaseId = base.id; greenBaseCount = greenBaseCount + 1; changed = true end
    end

    local balanceChanged = false
    balanceChanged, redBaseCount, greenBaseCount = NPCWorldDirectorBridge.BalanceStrategicWarBases(director, gmd, war, redBaseCount, greenBaseCount, worldAge)
    changed = changed or balanceChanged

    local minRefresh = tonumber(director.STRATEGIC_FRONT_UPDATE_HOURS) or 0.10
    if (tonumber(war.lastFrontUpdate) or 0) > 0 and worldAge - (tonumber(war.lastFrontUpdate) or 0) < minRefresh then
        return changed
    end
    war.lastFrontUpdate = worldAge

    local redCenter = NPCWorldDirectorBridge.StrategicSideCentroid(gmd, "red") or war.redAnchor
    local greenCenter = NPCWorldDirectorBridge.StrategicSideCentroid(gmd, "green") or war.greenAnchor
    local frontX = math.floor(((tonumber(redCenter.x) or 0) + (tonumber(greenCenter.x) or 0)) / 2)
    local frontY = math.floor(((tonumber(redCenter.y) or 0) + (tonumber(greenCenter.y) or 0)) / 2)
    local logistics = war.logistics
    if type(logistics) == "table" and type(logistics.red) == "table" and type(logistics.green) == "table" then
        local redForce = (tonumber(logistics.red.pressure) or 0) * 1.3 + (tonumber(logistics.red.supply) or 50) * 0.20 + (tonumber(logistics.red.ammo) or 50) * 0.14 + (tonumber(logistics.red.morale) or 50) * 0.10
        local greenForce = (tonumber(logistics.green.pressure) or 0) * 1.3 + (tonumber(logistics.green.supply) or 50) * 0.20 + (tonumber(logistics.green.ammo) or 50) * 0.14 + (tonumber(logistics.green.morale) or 50) * 0.10
        local totalForce = math.max(1, redForce + greenForce)
        local balance = (redForce - greenForce) / totalForce
        if balance < -1 then balance = -1 end
        if balance > 1 then balance = 1 end
        local dx = (tonumber(greenCenter.x) or frontX) - (tonumber(redCenter.x) or frontX)
        local dy = (tonumber(greenCenter.y) or frontY) - (tonumber(redCenter.y) or frontY)
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 1 then
            local nudge = balance * (tonumber(director.STRATEGIC_LOGISTICS_FRONT_NUDGE_TILES) or 220)
            frontX = math.floor(frontX + dx / len * nudge)
            frontY = math.floor(frontY + dy / len * nudge)
        end
    end
    war.front = war.front or {}
    war.front.x = frontX
    war.front.y = frontY
    war.front.z = 0
    war.front.redPower = redCenter.weight or 0
    war.front.greenPower = greenCenter.weight or 0
    war.front.updatedAt = worldAge
    changed = true

    gmd.DebugMapMarkers = gmd.DebugMapMarkers or {}
    local marker = gmd.DebugMapMarkers.STRATEGIC_FRONT_MAIN or {}
    marker.id = "STRATEGIC_FRONT_MAIN"
    marker.markerType = "front"
    marker.x = frontX
    marker.y = frontY
    marker.z = 0
    marker.name = "Strategic front"
    marker.virtual = true
    marker.active = false
    marker.dead = false
    marker.redPower = war.front.redPower
    marker.greenPower = war.front.greenPower
    marker.redLogisticsSupply = war.front.redLogisticsSupply
    marker.greenLogisticsSupply = war.front.greenLogisticsSupply
    marker.redLogisticsAmmo = war.front.redLogisticsAmmo
    marker.greenLogisticsAmmo = war.front.greenLogisticsAmmo
    marker.redLogisticsMorale = war.front.redLogisticsMorale
    marker.greenLogisticsMorale = war.front.greenLogisticsMorale
    marker.redPressure = war.front.redPressure
    marker.greenPressure = war.front.greenPressure
    marker.updatedAt = worldAge
    gmd.DebugMapMarkers.STRATEGIC_FRONT_MAIN = marker
    NPCWorldDirectorBridge.SendDebugMapUpdate(marker)

    return changed
end

function NPCWorldDirectorBridge.EstimateStrategicRoutePenalty(director, gmd, side, fromRecord, base)
    if not (director and gmd and fromRecord and base and fromRecord.x and fromRecord.y and base.x and base.y) then return 0 end
    local dist = NPCWorldDirectorBridge.DistanceToPoint(fromRecord, base)
    local nearestOwn, supplyDist = NPCWorldDirectorBridge.FindNearestOwnedStrategicBase(gmd, base.x, base.y, side)
    if not nearestOwn then supplyDist = dist end
    local routePenalty = (dist / 1000) * (tonumber(director.STRATEGIC_REALISM_ROUTE_PENALTY_PER_1000_TILES) or 140)
    local supplyPenalty = (supplyDist / math.max(1, tonumber(director.STRATEGIC_LOGISTICS_SUPPLY_LINE_RANGE) or 1800)) * 260
    return routePenalty + supplyPenalty
end

function NPCWorldDirectorBridge.EstimateStrategicBaseDefenseScore(director, base)
    if type(base) ~= "table" then return 0 end
    local power = tonumber(base.virtualGarrisonPower) or tonumber(base.defensePower) or 0
    local fortify = tonumber(base.fortifyLevel) or 1
    local readiness = math.min(
        tonumber(base.defenseReadiness) or 70,
        tonumber(base.ammoReadiness) or 70,
        tonumber(base.logisticsReadiness) or 70
    )
    local score = power * (tonumber(director and director.STRATEGIC_REALISM_DEFENSE_SCORE_WEIGHT) or 0.85)
    score = score + fortify * 85 + readiness * 2.2
    if base.owner then score = score + 160 end
    if base.status == "contested" or base.status == "siege_contested" then score = score - 90 end
    if base.captureTeam then score = score - 55 end
    return score
end

function NPCWorldDirectorBridge.FindStrategicFrontTargetBase(gmd, side, front, fromRecord, director)
    local other = side == "red" and "green" or "red"
    local source = fromRecord or front
    local neutralFirst = not director or director.STRATEGIC_EXPANSION_NEUTRAL_FIRST_ENABLED ~= false
    local neutralRadius = tonumber(director and director.STRATEGIC_EXPANSION_NEUTRAL_RADIUS) or 1800
    local enemyDelayPenalty = tonumber(director and director.STRATEGIC_EXPANSION_ENEMY_DELAY_PENALTY) or 620
    local bestNeutral = nil
    local bestNeutralScore = 999999
    local bestOther = nil
    local bestOtherScore = 999999

    for _, base in pairs(gmd and gmd.BaseCamps or {}) do
        if type(base) == "table" and base.x and base.y and base.owner ~= side then
            local owner = base.owner
            local neutral = owner == nil or tostring(owner) == "" or tostring(owner) == "neutral"
            local enemy = owner == other
            local dFront = front and NPCWorldDirectorBridge.DistanceToPoint(base, front) or 0
            local dSource = source and NPCWorldDirectorBridge.DistanceToPoint(base, source) or dFront
            local score = dSource * 0.65 + dFront * 0.35

            if neutral then
                if not source or dSource <= neutralRadius then
                    score = score - (tonumber(director and director.STRATEGIC_EXPANSION_NEUTRAL_BONUS) or 420)
                else
                    score = score + 140
                end
                if base.captureTeam and base.captureTeam ~= side then score = score + 160 end
            elseif enemy then
                score = score - 220
            else
                score = score + 120
            end

            if base.captureTeam == side then score = score - 180 end
            if base.status == "contested" then score = score - 70 end
            if director and director.STRATEGIC_REALISM_ENABLED ~= false then
                score = score + NPCWorldDirectorBridge.EstimateStrategicBaseDefenseScore(director, base)
                score = score + NPCWorldDirectorBridge.EstimateStrategicRoutePenalty(director, gmd, side, fromRecord or front or base, base)
                local sideLogistics = NPCWorldDirectorBridge.SideLogistics(gmd, side)
                if sideLogistics then
                    local readiness = math.min(tonumber(sideLogistics.supply) or 100, tonumber(sideLogistics.ammo) or 100, tonumber(sideLogistics.morale) or 100)
                    if readiness < 65 then score = score + (65 - readiness) * 16 end
                end
                if base.baseArchetype == "elite_safehouse" then score = score + 180 end
                if base.baseArchetype == "military" then score = score + 120 end
                if base.baseArchetype == "checkpoint" then score = score - 45 end
            end

            if neutral then
                if score < bestNeutralScore then
                    bestNeutral = base
                    bestNeutral.id = bestNeutral.id or tostring(base.id or "")
                    bestNeutralScore = score
                end
            elseif score < bestOtherScore then
                bestOther = base
                bestOther.id = bestOther.id or tostring(base.id or "")
                bestOtherScore = score
            end
        end
    end

    if neutralFirst and bestNeutral and (not bestOther or bestNeutralScore <= bestOtherScore + enemyDelayPenalty) then
        return bestNeutral
    end
    return bestOther or bestNeutral
end

function NPCWorldDirectorBridge.ApplyStrategicFrontOrders(director, gmd, worldAge)
    local war = gmd and gmd.WorldDirector and gmd.WorldDirector.strategicWar or nil
    local front = war and war.front or nil
    if not front then return false end

    local changed = false
    for groupId, group in pairs(gmd.VirtualGroups or {}) do
        if type(group) == "table"
            and not group.activated
            and not group.inBattle
            and not NPCWorldDirectorBridge.IsPlayerCommandedMercenaryGroup(group)
            and not group.economyMissionId
            and not group.mercenary
            and not group.roadPatrol
            and not group.checkpointId
            and group.state ~= "base_garrison"
            and group.targetClass ~= "base_guard"
            and NPCWorldDirectorBridge.GroupMemberCount(group) > 0 then
            local side = group.side or group.factionSide or group.patrolColor or (group.hostile and "red" or "green")
            if side == "red" or side == "green" then
                local targetBase = NPCWorldDirectorBridge.FindStrategicFrontTargetBase(gmd, side, front, group, director)
                if targetBase and (group.targetBaseId ~= targetBase.id or group.targetClass ~= "base_capture") then
                    group.targetX = targetBase.x
                    group.targetY = targetBase.y
                    group.targetZ = targetBase.z or 0
                    group.targetClass = "base_capture"
                    group.targetBaseId = targetBase.id
                    group.state = "front_push"
                    group.strategicFrontOrder = true
                    group.strategicFrontAt = worldAge
                    gmd.VirtualGroups[groupId] = group
                    changed = true
                elseif not targetBase and (group.targetClass ~= "front_patrol" or not group.targetX) then
                    group.targetX = front.x
                    group.targetY = front.y
                    group.targetZ = front.z or 0
                    group.targetClass = "front_patrol"
                    group.state = "moving_to_front"
                    group.strategicFrontOrder = true
                    group.strategicFrontAt = worldAge
                    gmd.VirtualGroups[groupId] = group
                    changed = true
                end
            end
        end
    end
    return changed
end

function NPCWorldDirectorBridge.EnsureStrategicFrontPressure(director, gmd, worldAge)
    local war = gmd and gmd.WorldDirector and gmd.WorldDirector.strategicWar or nil
    if not (director and gmd and war and war.front) then return false end
    local cap = tonumber(director.MAX_VIRTUAL_GROUPS) or 0
    if cap > 0 and NPCWorldDirectorBridge.CountTable(gmd.VirtualGroups or {}) >= cap then return false end
    local cooldown = tonumber(director.STRATEGIC_FRONT_PRESSURE_COOLDOWN_HOURS) or 1.0
    if (tonumber(war.lastPressureAt) or 0) > 0 and worldAge - (tonumber(war.lastPressureAt) or 0) < cooldown then return false end

    local target = tonumber(director.STRATEGIC_FRONT_SIDE_TARGET_GROUPS) or 6
    local redCount = NPCWorldDirectorBridge.CountStrategicSideGroups(gmd, "red")
    local greenCount = NPCWorldDirectorBridge.CountStrategicSideGroups(gmd, "green")
    local side = NPCWorldDirectorBridge.SelectStrategicPressureSide(director, gmd, war, redCount, greenCount, target)
    if not side then return false end
    local sideLogistics = NPCWorldDirectorBridge.SideLogistics(gmd, side)
    if sideLogistics and ((tonumber(sideLogistics.supply) or 100) < (tonumber(director.STRATEGIC_LOGISTICS_LOW_SUPPLY) or 42) or (tonumber(sideLogistics.ammo) or 100) < (tonumber(director.STRATEGIC_LOGISTICS_LOW_AMMO) or 38)) then
        return false
    end

    local anchor = side == "red" and war.redAnchor or war.greenAnchor
    local targetPoint = {x=war.front.x, y=war.front.y, z=0}
    if not anchor then return false end
    local group = NPCWorldDirectorBridge.CreateStrategicVirtualGroup(director, gmd, {
        prefix = "FR",
        kind = "checkpoint",
        state = "front_march",
        x = anchor.x,
        y = anchor.y,
        z = anchor.z or 0,
        side = side,
        count = tonumber(director.STRATEGIC_FRONT_PRESSURE_GROUP_SIZE) or 4,
        target = targetPoint,
        name = tostring(side) .. " front column"
    })
    if group then
        group.strategicFrontColumn = true
        group.targetClass = "front_patrol"
        gmd.VirtualGroups[group.id] = group
        war.lastPressureAt = worldAge
        war.lastPressureSide = side
        NPCWorldDirectorBridge.BehaviorLog(director, "front_pressure_group_created", {groupId=group.id, side=side, x=group.x, y=group.y, targetX=group.targetX, targetY=group.targetY, redGroups=redCount, greenGroups=greenCount})
        NPCWorldDirectorBridge.Log(director, NPC_WORLD_DIRECTOR_LOG_PREFIX .. " Created strategic front pressure group " .. tostring(group.id) .. " side=" .. tostring(side))
        return true
    end
    return false
end


local NPC_STRATEGIC_ACTIVITY_STATES = {
    Patrol = "activity_patrol",
    AttackBase = "activity_attack_base",
    AssembleStrike = "activity_assemble_strike",
    DefendBase = "activity_defend_base",
    EscortConvoy = "activity_escort_convoy",
    AmbushRoad = "activity_ambush_road",
    ScoutFront = "activity_scout_front",
    SiegeBase = "activity_siege_base",
    RetreatToBase = "activity_retreat_to_base",
    HuntPlayer = "activity_hunt_player",
    ReinforceBase = "activity_reinforce_base"
}

local NPC_STRATEGIC_ACTIVITY_TARGET_CLASS = {
    Patrol = "activity_patrol",
    AttackBase = "base_capture",
    AssembleStrike = "strike_staging",
    DefendBase = "base_defense",
    EscortConvoy = "convoy_escort",
    AmbushRoad = "road_ambush",
    ScoutFront = "front_scout",
    SiegeBase = "base_capture",
    RetreatToBase = "retreat_base",
    HuntPlayer = "hunt_player",
    ReinforceBase = "base_reinforce"
}

local function wd_activityTypePriority(activityType)
    if activityType == "RetreatToBase" then return 10 end
    if activityType == "DefendBase" then return 20 end
    if activityType == "ReinforceBase" then return 30 end
    if activityType == "SiegeBase" then return 40 end
    if activityType == "AssembleStrike" then return 45 end
    if activityType == "AttackBase" then return 50 end
    if activityType == "EscortConvoy" then return 60 end
    if activityType == "AmbushRoad" then return 70 end
    if activityType == "HuntPlayer" then return 80 end
    if activityType == "ScoutFront" then return 90 end
    return 100
end

local function wd_activityBaseOwner(base)
    if type(base) ~= "table" then return nil end
    return base.owner or base.captureTeam or base.commanderSide
end

local function wd_activityBaseId(base)
    if type(base) ~= "table" then return nil end
    return base.id or base.baseId or base.markerId
end

local function wd_clamp(value, minValue, maxValue)
    value = tonumber(value) or 0
    minValue = tonumber(minValue) or 0
    maxValue = tonumber(maxValue) or 100
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function wd_groupSide(group)
    if type(group) ~= "table" then return nil end
    return group.side or group.factionSide or group.patrolColor or (group.hostile and "red" or "green")
end

function NPCWorldDirectorBridge.IsRecruitableBlueMercenaryPatrol(group)
    if type(group) ~= "table" then return false end
    local side = wd_groupSide(group)
    return side == "blue"
        and group.mercenary == true
        and group.mercenaryHired ~= true
        and group.hired ~= true
        and group.isPlayerGuard ~= true
end

local function wd_worldAgeHoursSafe()
    if getGameTime then
        local ok, value = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok and value then return tonumber(value) or 0 end
    end
    return 0
end

local function wd_groupReadiness(group)
    if type(group) ~= "table" then return 100 end
    return math.min(
        tonumber(group.supplyReadiness) or 100,
        tonumber(group.ammoReadiness) or 100,
        tonumber(group.armoryReadiness) or 100,
        tonumber(group.combatReadiness) or 100,
        tonumber(group.moraleReadiness) or 100
    )
end

local function wd_activityLogisticsCost(activityType)
    if activityType == "SiegeBase" then return 1.55, 1.70, 1.20 end
    if activityType == "AttackBase" then return 1.35, 1.45, 1.05 end
    if activityType == "ReinforceBase" then return 1.10, 1.00, 0.95 end
    if activityType == "DefendBase" then return 0.80, 0.95, 0.75 end
    if activityType == "AmbushRoad" then return 0.85, 1.05, 0.80 end
    if activityType == "ScoutFront" then return 0.65, 0.45, 0.75 end
    if activityType == "EscortConvoy" then return 0.75, 0.65, 0.70 end
    if activityType == "RetreatToBase" then return 0.35, 0.25, 0.45 end
    if activityType == "HuntPlayer" then return 1.05, 1.20, 0.95 end
    return 0.55, 0.45, 0.50
end


local WD_BASE_ECONOMY_STOCK_KEYS = {"food", "water", "medical", "ammo", "weapons", "armor", "materials", "tools", "supplies", "fuel", "spareParts"}
local WD_BASE_ECONOMY_FIELD_BY_KEY = {
    food = "stockFood", water = "stockWater", medical = "stockMedical", ammo = "stockAmmo",
    weapons = "stockWeapons", armor = "stockArmor", materials = "stockMaterials", tools = "stockTools",
    supplies = "stockSupplies", fuel = "stockFuel", spareParts = "stockSpareParts"
}

local function wd_baseEconomyStock(base, key)
    if type(base) ~= "table" then return 0 end
    local amount = 0
    if type(base.stock) == "table" then amount = amount + (tonumber(base.stock[key]) or 0) end
    if type(base.zoneStock) == "table" then amount = amount + (tonumber(base.zoneStock[key]) or 0) end
    local field = WD_BASE_ECONOMY_FIELD_BY_KEY[key]
    if amount <= 0 and field then amount = tonumber(base[field]) or 0 end
    return math.max(0, amount)
end

local function wd_baseEconomyReadiness(base, key, perManpower)
    local manpower = math.max(1, tonumber(perManpower) or tonumber(base and base.economy and base.economy.manpowerActive) or tonumber(base and base.garrisonSize) or 4)
    local amount = wd_baseEconomyStock(base, key)
    return wd_clamp((amount / manpower) * 18, 0, 100)
end

local function wd_baseEconomyConsumeFromStockTable(stock, key, amount)
    if type(stock) ~= "table" or amount <= 0 then return amount, 0 end
    local have = tonumber(stock[key]) or 0
    if have <= 0 then return amount, 0 end
    local take = math.min(have, amount)
    stock[key] = have - take
    return amount - take, take
end

local function wd_baseEconomyConsumeResource(base, key, amount)
    if type(base) ~= "table" or not key then return 0 end
    amount = math.max(0, tonumber(amount) or 0)
    if amount <= 0 then return 0 end
    local remaining = amount
    local taken = 0
    local zoneTaken = 0
    base.stock = base.stock or {}
    remaining, taken = wd_baseEconomyConsumeFromStockTable(base.stock, key, remaining)
    if remaining > 0 and type(base.zones) == "table" then
        for _, zone in pairs(base.zones) do
            if remaining <= 0 then break end
            if type(zone) == "table" and type(zone.stock) == "table" then
                local left, got = wd_baseEconomyConsumeFromStockTable(zone.stock, key, remaining)
                remaining = left
                taken = taken + got
                zoneTaken = zoneTaken + got
            end
        end
    end
    if type(base.zoneStock) == "table" then
        base.zoneStock[key] = math.max(0, (tonumber(base.zoneStock[key]) or 0) - zoneTaken)
    end
    local field = WD_BASE_ECONOMY_FIELD_BY_KEY[key]
    if field then base[field] = math.max(0, (tonumber(base[field]) or 0) - taken) end
    return taken
end

local function wd_baseEconomyAddResource(base, key, amount)
    if type(base) ~= "table" or not key then return 0 end
    amount = math.max(0, tonumber(amount) or 0)
    if amount <= 0 then return 0 end
    base.stock = base.stock or {}
    base.stock[key] = (tonumber(base.stock[key]) or 0) + amount
    local field = WD_BASE_ECONOMY_FIELD_BY_KEY[key]
    if field then base[field] = (tonumber(base[field]) or 0) + amount end
    return amount
end

local function wd_baseEconomyStatusFromScores(supplyScore, ammoScore, medicalScore, manpowerReserve)
    if manpowerReserve <= 0 or supplyScore <= 18 or ammoScore <= 14 then return "critical" end
    if supplyScore <= 42 or ammoScore <= 34 or medicalScore <= 22 or manpowerReserve <= 2 then return "low" end
    return "ok"
end

local function wd_baseEconomyNeedSummary(economy)
    if type(economy) ~= "table" then return "ok" end
    local needs = {}
    if (tonumber(economy.supplyReadiness) or 100) <= 42 then table.insert(needs, "food/water") end
    if (tonumber(economy.ammoReadiness) or 100) <= 34 then table.insert(needs, "ammo") end
    if (tonumber(economy.medicalReadiness) or 100) <= 22 then table.insert(needs, "medical") end
    if (tonumber(economy.manpowerReserve) or 0) <= 2 then table.insert(needs, "manpower") end
    if #needs <= 0 then return "ok" end
    return table.concat(needs, " ")
end

function NPCWorldDirectorBridge.EnsureBaseEconomy(base, worldAge)
    if type(base) ~= "table" then return nil end
    local now = tonumber(worldAge) or wd_worldAgeHoursSafe()
    base.economy = type(base.economy) == "table" and base.economy or {}
    local economy = base.economy
    economy.version = 2
    economy.createdAt = tonumber(economy.createdAt) or now
    local garrison = math.max(1, tonumber(base.garrisonSize) or tonumber(base.virtualGarrisonEffective) or 5)
    local fortify = math.max(1, tonumber(base.fortifyLevel) or 1)
    local defaultMax = math.max(garrison + 2, math.floor(garrison * ((NPCWorldDirector and tonumber(NPCWorldDirector.BASE_LOGISTICS_MANPOWER_PER_GARRISON)) or 2.4) + fortify + 0.5))
    economy.manpowerMax = math.max(tonumber(economy.manpowerMax) or 0, defaultMax)
    economy.manpower = wd_clamp(tonumber(economy.manpower) or economy.manpowerMax, 0, economy.manpowerMax)
    economy.wounded = wd_clamp(tonumber(economy.wounded) or 0, 0, economy.manpowerMax)
    economy.losses = math.max(0, tonumber(economy.losses) or tonumber(base.virtualGarrisonLosses) or 0)
    economy.deployed = math.max(0, tonumber(economy.deployed) or 0)
    economy.missionCount = math.max(0, tonumber(economy.missionCount) or 0)
    economy.manpowerActive = math.max(0, economy.manpower - economy.wounded)
    economy.manpowerReserve = math.max(0, economy.manpowerActive - economy.deployed)
    return economy
end

function NPCWorldDirectorBridge.BaseEconomyHash(base)
    if type(base) ~= "table" then return "" end
    local e = base.economy or {}
    return table.concat({
        tostring(e.status or ""),
        tostring(math.floor((tonumber(e.manpower) or 0) + 0.5)),
        tostring(math.floor((tonumber(e.manpowerReserve) or 0) + 0.5)),
        tostring(math.floor((tonumber(e.deployed) or 0) + 0.5)),
        tostring(math.floor((tonumber(e.supplyReadiness) or 0) + 0.5)),
        tostring(math.floor((tonumber(e.ammoReadiness) or 0) + 0.5)),
        tostring(math.floor((tonumber(e.medicalReadiness) or 0) + 0.5)),
        tostring(math.floor((tonumber(e.morale) or 0) + 0.5)),
        tostring(e.needSummary or "")
    }, ":")
end

function NPCWorldDirectorBridge.GetBaseEconomySpawnPenalty(base)
    if type(base) ~= "table" then return 0 end
    local e = NPCWorldDirectorBridge.EnsureBaseEconomy(base, wd_worldAgeHoursSafe())
    if type(e) ~= "table" then return 0 end
    local penalty = 0
    if e.status == "critical" then penalty = penalty + 2400 end
    if e.status == "low" then penalty = penalty + 750 end
    if e.canSpawnPatrol == false then penalty = penalty + 900 end
    penalty = penalty + math.max(0, tonumber(e.deployed) or 0) * 120
    penalty = penalty - math.min(500, math.max(0, tonumber(e.manpowerReserve) or 0) * 45)
    return penalty
end

function NPCWorldDirectorBridge.UpdateBaseEconomy(director, gmd, worldAge)
    if not (director and director.BASE_LOGISTICS_ECONOMY_ENABLED ~= false and gmd and type(gmd.BaseCamps) == "table") then return false end
    gmd.WorldDirector = gmd.WorldDirector or {}
    local wd = gmd.WorldDirector
    local last = tonumber(wd.lastBaseEconomyUpdate) or 0
    local interval = tonumber(director.BASE_LOGISTICS_ECONOMY_UPDATE_HOURS) or 0.25
    if last > 0 and worldAge - last < interval then return false end
    local dt = last > 0 and (worldAge - last) or interval
    dt = wd_clamp(dt, 0.05, tonumber(director.STRATEGIC_LOGISTICS_MAX_DT_HOURS) or 3.0)
    wd.lastBaseEconomyUpdate = worldAge

    local deployed = {}
    for _, group in pairs(gmd.VirtualGroups or {}) do
        if type(group) == "table" and NPCWorldDirectorBridge.GroupMemberCount(group) > 0 then
            local baseId = group.homeBaseId or group.missionOriginBaseId or group.originBaseId or group.logisticsBaseId
            if baseId then
                local key = tostring(baseId)
                deployed[key] = deployed[key] or {members=0, missions=0, low=0, losses=0}
                local count = NPCWorldDirectorBridge.GroupMemberCount(group)
                if not group.economyReservedAt then deployed[key].members = deployed[key].members + count end
                if group.strategicActivityType or group.economyMissionId then deployed[key].missions = deployed[key].missions + 1 end
                if wd_groupReadiness(group) <= (tonumber(director.STRATEGIC_ACTIVITY_LOW_READINESS) or 55) then deployed[key].low = deployed[key].low + 1 end
                deployed[key].losses = deployed[key].losses + math.max(0, tonumber(group.logisticsRecentLosses) or 0)
            end
        end
    end

    local changed = false
    for id, base in pairs(gmd.BaseCamps or {}) do
        if type(base) == "table" then
            local owner = wd_activityBaseOwner(base)
            local economy = NPCWorldDirectorBridge.EnsureBaseEconomy(base, worldAge)
            if economy then
                local key = tostring(wd_activityBaseId(base) or id)
                local dep = deployed[key] or {members=0, missions=0, low=0, losses=0}
                local previousHash = NPCWorldDirectorBridge.BaseEconomyHash(base)
                economy.deployed = math.max(0, tonumber(dep.members) or 0)
                economy.missionCount = math.max(0, tonumber(dep.missions) or 0)
                economy.lowReadinessGroups = math.max(0, tonumber(dep.low) or 0)
                economy.recentLosses = math.max(0, tonumber(dep.losses) or 0)

                if owner == "red" or owner == "green" then
                    local foodWater = wd_baseEconomyStock(base, "food") + wd_baseEconomyStock(base, "water")
                    local ammoStock = wd_baseEconomyStock(base, "ammo")
                    local medStock = wd_baseEconomyStock(base, "medical")
                    local armoryStock = wd_baseEconomyStock(base, "weapons") * 3 + wd_baseEconomyStock(base, "armor") * 2 + wd_baseEconomyStock(base, "materials") * 0.25
                    local population = math.max(1, tonumber(economy.manpower) or tonumber(base.garrisonSize) or 4)
                    economy.supplyReadiness = wd_clamp((foodWater / population) * 10, 0, 100)
                    economy.ammoReadiness = wd_clamp((ammoStock / population) * 16, 0, 100)
                    economy.medicalReadiness = wd_clamp((medStock / population) * 22, 0, 100)
                    economy.armoryReadiness = wd_clamp((armoryStock / population) * 10, 0, 100)
                    economy.zoneReadiness = math.floor(((tonumber(base.garrisonReadiness) or 65) + (tonumber(base.logisticsReadiness) or 65) + (tonumber(base.defenseReadiness) or 65)) / 3 + 0.5)

                    local recoverRate = (tonumber(director.BASE_LOGISTICS_MANPOWER_RECOVERY_PER_HOUR) or 0.32) * dt
                    local woundedRate = (tonumber(director.BASE_LOGISTICS_WOUNDED_RECOVERY_PER_HOUR) or 0.22) * dt
                    if economy.supplyReadiness < 35 then recoverRate = recoverRate * 0.35 end
                    if economy.medicalReadiness < 25 then woundedRate = woundedRate * 0.40 end
                    if economy.wounded > 0 then
                        local recovered = math.min(economy.wounded, woundedRate)
                        economy.wounded = economy.wounded - recovered
                    end
                    if economy.manpower < economy.manpowerMax and economy.supplyReadiness >= 45 and economy.medicalReadiness >= 20 then
                        economy.manpower = math.min(economy.manpowerMax, economy.manpower + recoverRate)
                    end
                    economy.manpowerActive = math.max(0, economy.manpower - economy.wounded)
                    economy.manpowerReserve = math.max(0, economy.manpowerActive - economy.deployed)
                    economy.status = wd_baseEconomyStatusFromScores(economy.supplyReadiness, economy.ammoReadiness, economy.medicalReadiness, economy.manpowerReserve)
                    economy.canSpawnPatrol = economy.status ~= "critical" and economy.manpowerReserve >= (tonumber(director.BASE_LOGISTICS_MIN_PATROL_MANPOWER) or 3) and economy.ammoReadiness >= 22 and economy.supplyReadiness >= 28
                    economy.canRaid = economy.status == "ok" and economy.manpowerReserve >= (tonumber(director.BASE_LOGISTICS_MIN_RAID_MANPOWER) or 5) and economy.ammoReadiness >= 45 and economy.supplyReadiness >= 45
                    economy.morale = wd_clamp(45 + economy.supplyReadiness * 0.20 + economy.ammoReadiness * 0.15 + economy.zoneReadiness * 0.20 - economy.lowReadinessGroups * 4 - economy.recentLosses * 2, 0, 100)
                    economy.needSummary = wd_baseEconomyNeedSummary(economy)
                    economy.updatedAt = worldAge

                    base.economyStatus = economy.status
                    base.needSummary = economy.needSummary
                    base.missionCount = economy.missionCount
                    base.manpower = math.floor(economy.manpower + 0.5)
                    base.manpowerReserve = math.floor(economy.manpowerReserve + 0.5)
                    base.manpowerDeployed = math.floor(economy.deployed + 0.5)
                    base.canSpawnPatrol = economy.canSpawnPatrol == true
                    base.canRaid = economy.canRaid == true
                    base.baseEconomyMorale = math.floor((tonumber(economy.morale) or 0) + 0.5)
                else
                    economy.status = "neutral"
                    economy.canSpawnPatrol = false
                    economy.canRaid = false
                    economy.needSummary = "neutral"
                end

                local afterHash = NPCWorldDirectorBridge.BaseEconomyHash(base)
                if previousHash ~= afterHash then
                    base.updatedAt = worldAge
                    if NPCBaseCampServerBridge and NPCBaseCampServerBridge.SendBaseMarker then pcall(function() NPCBaseCampServerBridge.SendBaseMarker(base) end) end
                    changed = true
                end
                gmd.BaseCamps[id] = base
            end
        end
    end
    return changed
end

function NPCWorldDirectorBridge.TryConsumeBaseEconomyForGroup(director, gmd, base, group, missionType, worldAge)
    if not (director and director.BASE_LOGISTICS_ECONOMY_ENABLED ~= false and type(base) == "table" and type(group) == "table") then return false end
    if director.SP_BOOTSTRAP_GATE_BASE_ECONOMY ~= false then
        local gate, retry, reason = npc_wd_shouldBootstrapGate(director, "base_economy_reserve")
        if gate then npc_wd_recordBootstrapGate("base_economy_reserve", retry, reason); return false end
    end
    if group.economyReservedAt then return false end
    if NPCWorldDirectorBridge.IsPlayerCommandedMercenaryGroup and NPCWorldDirectorBridge.IsPlayerCommandedMercenaryGroup(group) then return false end
    if group.state == "base_garrison" or group.targetClass == "base_guard" or group.baseOwnedRole == "garrison" then return false end
    local economy = NPCWorldDirectorBridge.EnsureBaseEconomy(base, worldAge)
    if type(economy) ~= "table" then return false end
    local count = math.max(1, NPCWorldDirectorBridge.GroupMemberCount(group))
    local kind = tostring(missionType or group.strategicActivityType or group.baseOwnedRole or group.state or "patrol")
    local raid = kind == "AttackBase" or kind == "SiegeBase" or kind == "raid" or kind == "field"
    local manpowerCost = count
    local ammoCost = count * (raid and 1.25 or 0.65)
    local supplyCost = count * (raid and 0.55 or 0.30)
    local medicalCost = count * (raid and 0.18 or 0.08)

    economy.manpower = wd_clamp((tonumber(economy.manpower) or manpowerCost) - manpowerCost, 0, tonumber(economy.manpowerMax) or manpowerCost)
    economy.manpowerActive = math.max(0, economy.manpower - (tonumber(economy.wounded) or 0))
    economy.manpowerReserve = math.max(0, economy.manpowerActive - (tonumber(economy.deployed) or 0))
    wd_baseEconomyConsumeResource(base, "ammo", ammoCost)
    wd_baseEconomyConsumeResource(base, "food", supplyCost * 0.55)
    wd_baseEconomyConsumeResource(base, "water", supplyCost * 0.45)
    wd_baseEconomyConsumeResource(base, "medical", medicalCost)

    group.economyReservedAt = tonumber(worldAge) or wd_worldAgeHoursSafe()
    group.economyManpowerCost = manpowerCost
    group.economyAmmoCost = ammoCost
    group.economySupplyCost = supplyCost
    group.economyMedicalCost = medicalCost
    group.economyMissionId = group.economyMissionId or ("BE_" .. tostring(group.id or "G"))
    group.missionOriginBaseId = group.missionOriginBaseId or wd_activityBaseId(base)
    group.missionType = group.missionType or kind
    group.homeBaseId = group.homeBaseId or wd_activityBaseId(base)
    group.homeBaseOwner = group.homeBaseOwner or wd_activityBaseOwner(base)
    if type(group.members) == "table" then
        for _, member in pairs(group.members) do
            if type(member) == "table" then
                member.economyMissionId = group.economyMissionId
                member.homeBaseId = member.homeBaseId or group.homeBaseId
                member.homeBaseOwner = member.homeBaseOwner or group.homeBaseOwner
            end
        end
    end
    NPCWorldDirectorBridge.BehaviorLog(director, "base_economy_group_reserved", {groupId=tostring(group.id or ""), baseId=tostring(group.homeBaseId or ""), side=tostring(group.side or group.factionSide or group.patrolColor or ""), count=count, mission=kind, manpower=math.floor((tonumber(economy.manpower) or 0) + 0.5), reserve=math.floor((tonumber(economy.manpowerReserve) or 0) + 0.5)})
    return true
end

function NPCWorldDirectorBridge.ApplyBaseEconomyGroupUpkeep(director, gmd, group, activityType, dt, nearBase, baseDist)
    if not (director and director.BASE_LOGISTICS_ECONOMY_ENABLED ~= false and gmd and type(group) == "table") then return false end
    local baseId = group.homeBaseId or group.missionOriginBaseId or group.originBaseId or group.logisticsBaseId
    if not baseId then return false end
    local base = NPCWorldDirectorBridge.GetStrategicBaseById and NPCWorldDirectorBridge.GetStrategicBaseById(gmd, baseId) or nil
    if type(base) ~= "table" then return false end
    local count = math.max(1, NPCWorldDirectorBridge.GroupMemberCount(group))
    dt = wd_clamp(dt, 0, tonumber(director.STRATEGIC_LOGISTICS_MAX_DT_HOURS) or 3.0)
    if dt <= 0 then return false end

    local economy = NPCWorldDirectorBridge.EnsureBaseEconomy(base, wd_worldAgeHoursSafe())
    if type(economy) ~= "table" then return false end
    local supplyCost, ammoCost = wd_activityLogisticsCost(activityType or group.strategicActivityType or group.state)
    local lineFactor = (tonumber(baseDist) or 0) > (tonumber(director.STRATEGIC_LOGISTICS_SUPPLY_LINE_RANGE) or 1800) and 1.55 or 1.0
    local drain = count * dt
    local resupplying = nearBase and tostring(wd_activityBaseId(nearBase) or "") == tostring(baseId) and (tonumber(baseDist) or 999999) <= (tonumber(director.STRATEGIC_LOGISTICS_RESUPPLY_RADIUS) or 220)

    if resupplying then
        local gain = (tonumber(director.BASE_LOGISTICS_RESUPPLY_GAIN) or 10.0) * dt
        group.supplyReadiness = wd_clamp((tonumber(group.supplyReadiness) or 65) + gain, 0, 100)
        group.ammoReadiness = wd_clamp((tonumber(group.ammoReadiness) or 65) + gain * 0.85, 0, 100)
        group.moraleReadiness = wd_clamp((tonumber(group.moraleReadiness) or 60) + gain * 0.35, 0, 100)
        return true
    end

    local foodCost = drain * (tonumber(director.BASE_LOGISTICS_GROUP_SUPPLY_DRAIN) or 0.055) * supplyCost * lineFactor
    local ammoUse = drain * (tonumber(director.BASE_LOGISTICS_GROUP_AMMO_DRAIN) or 0.050) * ammoCost * lineFactor
    local medUse = drain * (tonumber(director.BASE_LOGISTICS_GROUP_MEDICAL_DRAIN) or 0.014) * lineFactor
    local gotFood = wd_baseEconomyConsumeResource(base, "food", foodCost * 0.55) + wd_baseEconomyConsumeResource(base, "water", foodCost * 0.45)
    local gotAmmo = wd_baseEconomyConsumeResource(base, "ammo", ammoUse)
    local gotMed = wd_baseEconomyConsumeResource(base, "medical", medUse)
    local supplyRatio = foodCost > 0 and wd_clamp(gotFood / foodCost, 0, 1) or 1
    local ammoRatio = ammoUse > 0 and wd_clamp(gotAmmo / ammoUse, 0, 1) or 1
    if supplyRatio < 0.65 then group.supplyReadiness = wd_clamp((tonumber(group.supplyReadiness) or 100) - (1 - supplyRatio) * 8 * dt, 0, 100) end
    if ammoRatio < 0.65 then group.ammoReadiness = wd_clamp((tonumber(group.ammoReadiness) or 100) - (1 - ammoRatio) * 10 * dt, 0, 100) end
    if gotMed < medUse * 0.5 then group.moraleReadiness = wd_clamp((tonumber(group.moraleReadiness) or 100) - 3 * dt, 0, 100) end
    economy.lastGroupUpkeepAt = wd_worldAgeHoursSafe()
    base.economy = economy
    return true
end

function NPCWorldDirectorBridge.RegisterBaseEconomyLoss(director, gmd, baseId, losses, wounded, worldAge)
    if not (director and director.BASE_LOGISTICS_ECONOMY_ENABLED ~= false and gmd and baseId) then return false end
    local base = NPCWorldDirectorBridge.GetStrategicBaseById and NPCWorldDirectorBridge.GetStrategicBaseById(gmd, baseId) or nil
    if type(base) ~= "table" then return false end
    local economy = NPCWorldDirectorBridge.EnsureBaseEconomy(base, worldAge)
    if type(economy) ~= "table" then return false end
    losses = math.max(0, tonumber(losses) or 0)
    wounded = math.max(0, tonumber(wounded) or 0)
    if losses <= 0 and wounded <= 0 then return false end
    economy.losses = math.max(0, (tonumber(economy.losses) or 0) + losses)
    economy.wounded = wd_clamp((tonumber(economy.wounded) or 0) + wounded, 0, tonumber(economy.manpowerMax) or 999)
    economy.manpower = wd_clamp((tonumber(economy.manpower) or 0) - losses, 0, tonumber(economy.manpowerMax) or 999)
    economy.manpowerActive = math.max(0, economy.manpower - economy.wounded)
    economy.manpowerReserve = math.max(0, economy.manpowerActive - (tonumber(economy.deployed) or 0))
    base.updatedAt = tonumber(worldAge) or wd_worldAgeHoursSafe()
    NPCWorldDirectorBridge.BehaviorLog(director, "base_economy_losses", {baseId=tostring(baseId), losses=losses, wounded=wounded, manpower=math.floor((tonumber(economy.manpower) or 0) + 0.5), reserve=math.floor((tonumber(economy.manpowerReserve) or 0) + 0.5)})
    return true
end

function NPCWorldDirectorBridge.EnsureStrategicLogisticsData(gmd)
    if type(gmd) ~= "table" then return nil end
    gmd.WorldDirector = gmd.WorldDirector or {}
    local war = gmd.WorldDirector.strategicWar
    if type(war) ~= "table" then return nil end
    war.logistics = war.logistics or {
        version = 1,
        createdAt = getGameTime and getGameTime():getWorldAgeHours() or 0,
        lastUpdate = 0,
        red = {supply=65, ammo=65, morale=60, pressure=0, reserve=0, losses=0},
        green = {supply=65, ammo=65, morale=60, pressure=0, reserve=0, losses=0}
    }
    war.logistics.red = war.logistics.red or {supply=65, ammo=65, morale=60, pressure=0, reserve=0, losses=0}
    war.logistics.green = war.logistics.green or {supply=65, ammo=65, morale=60, pressure=0, reserve=0, losses=0}
    return war.logistics
end

function NPCWorldDirectorBridge.SideLogistics(gmd, side)
    local logistics = NPCWorldDirectorBridge.EnsureStrategicLogisticsData(gmd)
    if not logistics then return nil end
    if side == "red" then return logistics.red end
    if side == "green" then return logistics.green end
    return nil
end

function NPCWorldDirectorBridge.FindNearestOwnedStrategicBase(gmd, x, y, side)
    local best = nil
    local bestDist = 999999
    for _, base in pairs(gmd and gmd.BaseCamps or {}) do
        if type(base) == "table" and base.x and base.y and wd_activityBaseOwner(base) == side then
            local dist = NPCWorldDirectorBridge.DistanceToPoint(base, {x=x, y=y})
            if dist < bestDist then
                best = base
                bestDist = dist
            end
        end
    end
    return best, bestDist
end


function NPCWorldDirectorBridge.BaseOwnedGroupSide(group)
    local side = wd_groupSide(group)
    if side == "red" or side == "green" then return side end
    return nil
end

function NPCWorldDirectorBridge.IsBaseOwnedGlobalSquad(group)
    if type(group) ~= "table" then return false end
    if group.mercenary == true or group.mercenaryElite == true or wd_groupSide(group) == "blue" then return false end
    return group.baseOwnedGlobalSquad == true
        or group.homeBaseId ~= nil
        or group.originBaseId ~= nil
        or group.missionOriginBaseId ~= nil
        or group.logisticsBaseId ~= nil
end

function NPCWorldDirectorBridge.GetBaseOwnedBaseId(base)
    return wd_activityBaseId(base)
end

function NPCWorldDirectorBridge.GetBaseOwnedHomeBase(gmd, group, side)
    if not (gmd and type(group) == "table") then return nil end
    side = side or NPCWorldDirectorBridge.BaseOwnedGroupSide(group)
    local preferred = group.homeBaseId or group.originBaseId or group.missionOriginBaseId or group.logisticsBaseId
    if preferred then
        local base = NPCWorldDirectorBridge.GetStrategicBaseById and NPCWorldDirectorBridge.GetStrategicBaseById(gmd, preferred) or nil
        if type(base) == "table" and base.x and base.y then
            local owner = wd_activityBaseOwner(base)
            if not side or owner == side then return base end
        end
    end

    local base = nil
    local maxDist = tonumber(NPCWorldDirector and NPCWorldDirector.BASE_OWNED_GLOBAL_GROUPS_MAX_BASE_DISTANCE) or 6200
    local baseDist = 999999
    if side then
        base, baseDist = NPCWorldDirectorBridge.FindNearestOwnedStrategicBase(gmd, group.x or group.targetX, group.y or group.targetY, side)
    end
    if type(base) == "table" and base.x and base.y and (tonumber(baseDist) or 999999) <= maxDist then return base end

    local best = nil
    local bestDist = maxDist
    for _, candidate in pairs(gmd.BaseCamps or {}) do
        if type(candidate) == "table" and candidate.x and candidate.y then
            local owner = wd_activityBaseOwner(candidate)
            if side == nil or owner == side then
                local dist = NPCWorldDirectorBridge.DistanceToPoint(candidate, {x=group.x or group.targetX, y=group.y or group.targetY})
                if dist < bestDist then
                    best = candidate
                    bestDist = dist
                end
            end
        end
    end
    return best
end

function NPCWorldDirectorBridge.SelectBaseOwnedSpawnBase(gmd, side, fallbackPoint)
    if not (gmd and type(gmd.BaseCamps) == "table") then return nil end
    if side ~= "red" and side ~= "green" then return nil end

    local best = nil
    local bestScore = 999999999
    local fx = fallbackPoint and tonumber(fallbackPoint.x) or nil
    local fy = fallbackPoint and tonumber(fallbackPoint.y) or nil
    for _, base in pairs(gmd.BaseCamps or {}) do
        if type(base) == "table" and base.x and base.y and wd_activityBaseOwner(base) == side then
            local baseId = tostring(wd_activityBaseId(base) or "")
            local owned = 0
            for _, group in pairs(gmd.VirtualGroups or {}) do
                if type(group) == "table" and tostring(group.homeBaseId or group.originBaseId or "") == baseId and NPCWorldDirectorBridge.GroupMemberCount(group) > 0 then
                    owned = owned + 1
                end
            end
            local score = owned * 900
            if fx and fy then score = score + NPCWorldDirectorBridge.DistanceToPoint(base, {x=fx, y=fy}) * 0.15 end
            if NPCWorldDirectorBridge.GetBaseEconomySpawnPenalty then score = score + NPCWorldDirectorBridge.GetBaseEconomySpawnPenalty(base) end
            if base.status == "contested" or base.captureTeam then score = score - 120 end
            if score < bestScore then
                best = base
                bestScore = score
            end
        end
    end
    return best
end

function NPCWorldDirectorBridge.MakeBaseOwnedStagingPoint(director, base, roadBias)
    if type(base) ~= "table" or not base.x or not base.y then return nil end
    local radius = math.max(1, math.floor(tonumber(director and director.BASE_OWNED_GLOBAL_GROUPS_STAGING_RADIUS) or 42))
    local point = nil
    if roadBias and NPCWorldDirectorBridge.GetNearbyRoadPoint then
        point = NPCWorldDirectorBridge.GetNearbyRoadPoint(director, base.x, base.y, radius * 2)
    end
    if not point and NPCWorldDirectorBridge.GetNearbyPreferredPoint then
        point = NPCWorldDirectorBridge.GetNearbyPreferredPoint(director, base.x, base.y, radius)
    end
    if point and point.x and point.y then
        point.originBaseId = wd_activityBaseId(base)
        point.originBaseOwner = wd_activityBaseOwner(base)
        point.baseOwnedStaging = true
        return point
    end

    local offX = 0
    local offY = 0
    if ZombRand then
        offX = ZombRand(radius * 2 + 1) - radius
        offY = ZombRand(radius * 2 + 1) - radius
    end
    return {
        x = math.floor((tonumber(base.x) or 0) + offX),
        y = math.floor((tonumber(base.y) or 0) + offY),
        z = tonumber(base.z) or 0,
        spawnClass = roadBias and "base_road_staging" or "base_staging",
        zoneScore = 260,
        urbanAffinity = 180,
        originBaseId = wd_activityBaseId(base),
        originBaseOwner = wd_activityBaseOwner(base),
        baseOwnedStaging = true
    }
end

function NPCWorldDirectorBridge.AssignBaseOwnedFields(director, gmd, group, base, worldAge, reason)
    if not (type(group) == "table" and type(base) == "table" and base.x and base.y) then return false end
    local side = NPCWorldDirectorBridge.BaseOwnedGroupSide(group)
    if not side then return false end
    local owner = wd_activityBaseOwner(base)
    if owner and owner ~= side then return false end

    local baseId = wd_activityBaseId(base)
    if not baseId then return false end
    local changed = false
    if tostring(group.homeBaseId or "") ~= tostring(baseId) then group.homeBaseId = baseId; changed = true end
    if not group.originBaseId then group.originBaseId = baseId; changed = true end
    if not group.missionOriginBaseId and group.economyMissionId then group.missionOriginBaseId = baseId; changed = true end
    if group.homeBaseOwner ~= owner then group.homeBaseOwner = owner; changed = true end
    if group.baseOwnedGlobalSquad ~= true then group.baseOwnedGlobalSquad = true; changed = true end
    group.baseOwnedSince = group.baseOwnedSince or tonumber(worldAge) or wd_worldAgeHoursSafe()
    group.baseOwnedLastReason = tostring(reason or group.baseOwnedLastReason or "assigned")
    group.homeBase = group.homeBase or {}
    if group.homeBase.x ~= base.x then group.homeBase.x = base.x; changed = true end
    if group.homeBase.y ~= base.y then group.homeBase.y = base.y; changed = true end
    group.homeBase.z = base.z or group.homeBase.z or 0
    group.routeOwnerBaseId = group.routeOwnerBaseId or baseId
    if not group.baseOwnedRole then
        if group.roadPatrol then group.baseOwnedRole = "patrol"
        elseif group.targetClass == "base_guard" or group.state == "base_garrison" then group.baseOwnedRole = "garrison"
        elseif group.targetBaseId then group.baseOwnedRole = "operation"
        else group.baseOwnedRole = "field" end
        changed = true
    end

    if type(group.members) == "table" then
        for _, member in pairs(group.members) do
            if type(member) == "table" then
                member.homeBaseId = member.homeBaseId or baseId
                member.originBaseId = member.originBaseId or baseId
                member.homeBaseOwner = member.homeBaseOwner or owner
                member.baseOwnedGlobalSquad = true
                member.baseOwnedRole = member.baseOwnedRole or group.baseOwnedRole
            end
        end
    end

    return changed
end

function NPCWorldDirectorBridge.EnsureBaseOwnedGroup(director, gmd, group, worldAge, reason)
    if not (director and director.BASE_OWNED_GLOBAL_GROUPS_ENABLED ~= false and gmd and type(group) == "table") then return false end
    if group.activated == true or group.mercenary == true or group.mercenaryElite == true then return false end
    local side = NPCWorldDirectorBridge.BaseOwnedGroupSide(group)
    if not side then return false end

    local base = NPCWorldDirectorBridge.GetBaseOwnedHomeBase(gmd, group, side)
    if not base then return false end
    return NPCWorldDirectorBridge.AssignBaseOwnedFields(director, gmd, group, base, worldAge, reason)
end

function NPCWorldDirectorBridge.RefreshBaseOwnedRouteTarget(director, gmd, group, worldAge, reason)
    if not (director and director.BASE_OWNED_GLOBAL_GROUPS_ENABLED ~= false and type(group) == "table") then return false end
    if group.activated == true or group.inBattle == true or group.mercenary == true then return false end
    if not NPCWorldDirectorBridge.IsBaseOwnedGlobalSquad(group) then return false end
    gmd = gmd or (director.EnsureData and director.EnsureData()) or nil
    if not gmd then return false end

    local side = NPCWorldDirectorBridge.BaseOwnedGroupSide(group)
    local base = NPCWorldDirectorBridge.GetBaseOwnedHomeBase(gmd, group, side)
    if not base then return false end
    NPCWorldDirectorBridge.AssignBaseOwnedFields(director, gmd, group, base, worldAge, reason)

    local targetClass = tostring(group.targetClass or "")
    if group.economyMissionId or group.convoyId or group.economyConvoy or group.bountyHunter then return false end
    if group.targetBaseId and targetClass ~= "retreat_base" and targetClass ~= "base_guard" and targetClass ~= "checkpoint_road_patrol" then return false end
    if targetClass == "base_capture" or targetClass == "base_defense" or targetClass == "base_reinforce" then return false end

    if group.targetX and group.targetY then
        local keepDistance = group.roadPatrol and 45 or 80
        if NPCWorldDirectorBridge.Dist(group.x, group.y, group.targetX, group.targetY) > keepDistance then return false end
    end

    local changed = false
    local target = nil
    local stepTarget = nil
    if group.roadPatrol then
        local patrolRadius = tonumber(director.BASE_OWNED_GLOBAL_GROUPS_PATROL_RADIUS) or tonumber(director.ROAD_PATROL_TARGET_RADIUS) or 480
        target = NPCWorldDirectorBridge.GetNearbyRoadPoint and NPCWorldDirectorBridge.GetNearbyRoadPoint(director, base.x, base.y, patrolRadius) or nil
        target = target or (NPCWorldDirectorBridge.GetNearbyPreferredPoint and NPCWorldDirectorBridge.GetNearbyPreferredPoint(director, base.x, base.y, patrolRadius) or nil)
        if not target then target = {x=base.x, y=base.y, z=base.z or 0, spawnClass="base_patrol_anchor"} end
        if target and NPCRoadNavBridge and NPCRoadNavBridge.FindNearbyWorldRoadStepToward then
            stepTarget = NPCRoadNavBridge.FindNearbyWorldRoadStepToward(group.x or base.x, group.y or base.y, target.x, target.y, director.ROAD_PATROL_VIRTUAL_STEP_RADIUS, director.VIRTUAL_TARGET_ATTEMPTS)
        end
        stepTarget = stepTarget or target
        group.routeX = target.x
        group.routeY = target.y
        group.routeZ = target.z or 0
        group.targetX = stepTarget.x
        group.targetY = stepTarget.y
        group.targetZ = stepTarget.z or 0
        group.targetClass = stepTarget == target and "base_owned_road_anchor" or "base_owned_road_step"
        group.baseOwnedRouteReason = tostring(reason or "base_patrol")
        group.routeOwnerBaseId = wd_activityBaseId(base)
        changed = true
    else
        if targetClass == "retreat_base" or group.strategicActivityType == "RetreatToBase" then
            target = {x=base.x, y=base.y, z=base.z or 0, spawnClass="retreat_base"}
        elseif targetClass == "base_guard" or group.state == "base_garrison" then
            return false
        else
            local patrolRadius = math.min(tonumber(director.BASE_OWNED_GLOBAL_GROUPS_PATROL_RADIUS) or 620, tonumber(director.VIRTUAL_TARGET_RADIUS) or 300)
            target = NPCWorldDirectorBridge.GetNearbyPreferredPoint and NPCWorldDirectorBridge.GetNearbyPreferredPoint(director, base.x, base.y, patrolRadius) or nil
            target = target or {x=base.x, y=base.y, z=base.z or 0, spawnClass="base_patrol_anchor"}
        end
        group.targetX = target.x
        group.targetY = target.y
        group.targetZ = target.z or 0
        group.targetClass = target.spawnClass or "base_owned_patrol"
        group.baseOwnedRouteReason = tostring(reason or "base_patrol")
        group.routeOwnerBaseId = wd_activityBaseId(base)
        changed = true
    end

    if changed then
        group.baseOwnedRouteAt = tonumber(worldAge) or wd_worldAgeHoursSafe()
        group.directorRetargetReason = nil
        group.directorRetargetScore = nil
    end
    return changed
end

function NPCWorldDirectorBridge.RepairBaseOwnedGroupLocation(director, group, worldAge)
    if not (director and director.BASE_OWNED_GLOBAL_GROUPS_REPAIR_PROTECT ~= false and type(group) == "table") then return nil end
    if director.SP_BOOTSTRAP_GATE_BASE_ECONOMY ~= false then
        local gate, retry, reason = npc_wd_shouldBootstrapGate(director, "base_owned_repair")
        if gate then npc_wd_recordBootstrapGate("base_owned_repair", retry, reason); return nil end
    end
    if group.activated == true or group.mercenary == true or group.mercenaryElite == true then return nil end
    if not NPCWorldDirectorBridge.IsBaseOwnedGlobalSquad(group) then return nil end

    local gmd = director.EnsureData and director.EnsureData() or nil
    if not gmd then return nil end
    local side = NPCWorldDirectorBridge.BaseOwnedGroupSide(group)
    local base = NPCWorldDirectorBridge.GetBaseOwnedHomeBase(gmd, group, side)
    if not base then return nil end
    NPCWorldDirectorBridge.AssignBaseOwnedFields(director, gmd, group, base, worldAge, "repair_protect")

    local changed = false
    if not group.x or not group.y then
        local point = NPCWorldDirectorBridge.MakeBaseOwnedStagingPoint(director, base, group.roadPatrol == true)
        if point then
            group.x = point.x
            group.y = point.y
            group.z = point.z or 0
            group.preciseX = tonumber(group.x) or 0
            group.preciseY = tonumber(group.y) or 0
            group.spawnClass = point.spawnClass or group.spawnClass or "base_staging"
            changed = true
        end
    end

    if group.x and group.y then
        local now = tonumber(worldAge) or wd_worldAgeHoursSafe()
        local last = tonumber(group.baseOwnedRepairProtectedAt) or 0
        local cooldown = tonumber(director.BASE_OWNED_GLOBAL_GROUPS_REPAIR_COOLDOWN_HOURS) or 1.20
        if last <= 0 or now - last >= cooldown then
            group.baseOwnedRepairProtectedAt = now
            group.locationRepairProtected = true
            group.locationRepairReason = "kept_base_owned_route"
            changed = NPCWorldDirectorBridge.RefreshBaseOwnedRouteTarget(director, gmd, group, now, "repair_protect") or changed
            NPCWorldDirectorBridge.BehaviorLog(director, "base_owned_repair_protected", {groupId=tostring(group.id or ""), side=tostring(side or ""), baseId=tostring(group.homeBaseId or ""), x=math.floor(tonumber(group.x) or 0), y=math.floor(tonumber(group.y) or 0), targetX=math.floor(tonumber(group.targetX) or 0), targetY=math.floor(tonumber(group.targetY) or 0)})
        end
    end
    return changed
end

function NPCWorldDirectorBridge.EstimateStrategicSupplyLine(gmd, group, side)
    if type(group) ~= "table" then return nil, 999999 end
    local base, dist = NPCWorldDirectorBridge.FindNearestOwnedStrategicBase(gmd, group.x or group.targetX, group.y or group.targetY, side)
    if not base then return nil, 999999 end
    return base, dist
end

function NPCWorldDirectorBridge.UpdateStrategicLogistics(director, gmd, worldAge)
    if not (director and director.STRATEGIC_LOGISTICS_ENABLED ~= false and gmd and type(gmd.VirtualGroups) == "table") then return false end
    local logistics = NPCWorldDirectorBridge.EnsureStrategicLogisticsData(gmd)
    if not logistics then return false end
    local last = tonumber(logistics.lastUpdate) or 0
    local interval = tonumber(director.STRATEGIC_LOGISTICS_UPDATE_HOURS) or 0.35
    if last > 0 and worldAge - last < interval then return false end
    local dt = last > 0 and (worldAge - last) or interval
    dt = wd_clamp(dt, 0.05, tonumber(director.STRATEGIC_LOGISTICS_MAX_DT_HOURS) or 3.0)
    logistics.lastUpdate = worldAge

    local sideState = {
        red = {bases=0, groups=0, members=0, pressure=0, reserve=0, drainSupply=0, drainAmmo=0, avgReadiness=0, readinessWeight=0, newLosses=0},
        green = {bases=0, groups=0, members=0, pressure=0, reserve=0, drainSupply=0, drainAmmo=0, avgReadiness=0, readinessWeight=0, newLosses=0}
    }

    for _, base in pairs(gmd.BaseCamps or {}) do
        if type(base) == "table" then
            local owner = wd_activityBaseOwner(base)
            local state = sideState[owner]
            if state then
                state.bases = state.bases + 1
                local basePower = 1
                if base.status == "controlled" then basePower = basePower + 0.6 end
                if base.status == "contested" then basePower = basePower - 0.3 end
                if base.baseArchetype == "military" or base.baseArchetype == "elite_safehouse" then basePower = basePower + 0.4 end
                if type(base.economy) == "table" then
                    if base.economy.status == "critical" then basePower = basePower - 0.45 end
                    if base.economy.status == "low" then basePower = basePower - 0.20 end
                    basePower = basePower + math.min(0.40, (tonumber(base.economy.manpowerReserve) or 0) * 0.025)
                    basePower = basePower + math.min(0.25, ((tonumber(base.economy.supplyReadiness) or 50) - 50) * 0.006)
                end
                base.logisticsPower = wd_clamp(basePower * 20, 5, 55)
            end
        end
    end

    local war = gmd.WorldDirector and gmd.WorldDirector.strategicWar or nil
    local front = war and war.front or nil
    local frontRadius = tonumber(director.STRATEGIC_LOGISTICS_FRONT_PRESSURE_RADIUS) or 900
    local resupplyRadius = tonumber(director.STRATEGIC_LOGISTICS_RESUPPLY_RADIUS) or 220
    local supplyLineRange = tonumber(director.STRATEGIC_LOGISTICS_SUPPLY_LINE_RANGE) or 1800
    for groupId, group in pairs(gmd.VirtualGroups or {}) do
        if type(group) == "table" and NPCWorldDirectorBridge.GroupMemberCount(group) > 0 then
            local side = wd_groupSide(group)
            local state = sideState[side]
            if state then
                local count = NPCWorldDirectorBridge.GroupMemberCount(group)
                local activityType = group.strategicActivityType or group.activityType or "Patrol"
                local readiness = wd_groupReadiness(group)
                local supplyCost, ammoCost, moraleCost = wd_activityLogisticsCost(activityType)
                local nearBase, baseDist = NPCWorldDirectorBridge.EstimateStrategicSupplyLine(gmd, group, side)
                local lineFactor = baseDist > supplyLineRange and 1.45 or (baseDist > supplyLineRange * 0.65 and 1.20 or 1.0)
                local attackFactor = (activityType == "AttackBase" or activityType == "SiegeBase" or activityType == "HuntPlayer") and 1.25 or 1.0
                local memberDrain = math.max(1, count) * (tonumber(director.STRATEGIC_LOGISTICS_GROUP_DRAIN) or 1.20) * dt * lineFactor * attackFactor / 6
                state.groups = state.groups + 1
                state.members = state.members + count
                state.drainSupply = state.drainSupply + memberDrain * supplyCost
                state.drainAmmo = state.drainAmmo + memberDrain * ammoCost
                state.avgReadiness = state.avgReadiness + readiness * count
                state.readinessWeight = state.readinessWeight + count

                local oldCount = tonumber(group.logisticsLastMemberCount) or count
                if oldCount > count then
                    local lost = oldCount - count
                    state.newLosses = state.newLosses + lost
                    group.logisticsRecentLosses = (tonumber(group.logisticsRecentLosses) or 0) + lost
                end
                group.logisticsLastMemberCount = count

                local resupplying = nearBase and baseDist <= resupplyRadius and (activityType == "RetreatToBase" or activityType == "DefendBase" or activityType == "ReinforceBase" or group.state == "base_garrison")
                if resupplying then
                    local gain = (tonumber(director.STRATEGIC_LOGISTICS_BASE_REGEN) or 5.5) * dt
                    group.supplyReadiness = wd_clamp((tonumber(group.supplyReadiness) or readiness) + gain, 0, 100)
                    group.ammoReadiness = wd_clamp((tonumber(group.ammoReadiness) or readiness) + gain * 0.85, 0, 100)
                    group.combatReadiness = wd_clamp((tonumber(group.combatReadiness) or readiness) + gain * 0.45, 0, 100)
                    group.moraleReadiness = wd_clamp((tonumber(group.moraleReadiness) or readiness) + gain * 0.35, 0, 100)
                    group.supplyLineState = "resupplying"
                else
                    group.supplyReadiness = wd_clamp((tonumber(group.supplyReadiness) or 100) - memberDrain * supplyCost, 0, 100)
                    group.ammoReadiness = wd_clamp((tonumber(group.ammoReadiness) or 100) - memberDrain * ammoCost, 0, 100)
                    group.moraleReadiness = wd_clamp((tonumber(group.moraleReadiness) or 100) - memberDrain * moraleCost * 0.40, 0, 100)
                    group.supplyLineState = baseDist > supplyLineRange and "stretched" or "connected"
                end
                group.logisticsBaseId = nearBase and wd_activityBaseId(nearBase) or nil
                group.logisticsBaseDistance = math.floor(baseDist or 999999)
                if NPCWorldDirectorBridge.ApplyBaseEconomyGroupUpkeep then
                    NPCWorldDirectorBridge.ApplyBaseEconomyGroupUpkeep(director, gmd, group, activityType, dt, nearBase, baseDist)
                end
                group.logisticsUpdatedAt = worldAge
                if front and front.x and front.y then
                    local distFront = NPCWorldDirectorBridge.DistanceToPoint(group, front)
                    if distFront <= frontRadius then
                        local pressure = count * (wd_groupReadiness(group) / 100) * (1 - (distFront / math.max(1, frontRadius)))
                        if activityType == "AttackBase" or activityType == "SiegeBase" then pressure = pressure * 1.45 end
                        if activityType == "DefendBase" or activityType == "ReinforceBase" then pressure = pressure * 0.90 end
                        state.pressure = state.pressure + pressure
                    else
                        state.reserve = state.reserve + math.max(1, count)
                    end
                else
                    state.reserve = state.reserve + math.max(1, count)
                end
                gmd.VirtualGroups[groupId] = group
            end
        end
    end

    local changed = false
    for _, side in ipairs({"red", "green"}) do
        local state = sideState[side]
        local dst = logistics[side] or {}
        local regen = state.bases * (tonumber(director.STRATEGIC_LOGISTICS_BASE_REGEN) or 5.5) * dt
        local avgReadiness = state.readinessWeight > 0 and (state.avgReadiness / state.readinessWeight) or 65
        local losses = wd_clamp((tonumber(dst.losses) or 0) + state.newLosses, 0, tonumber(director.STRATEGIC_LOGISTICS_MAX_SIDE_LOSS_MEMORY) or 120)
        local supply = wd_clamp((tonumber(dst.supply) or 65) + regen - state.drainSupply, 0, 100)
        local ammo = wd_clamp((tonumber(dst.ammo) or 65) + regen * 0.75 - state.drainAmmo, 0, 100)
        local morale = wd_clamp((tonumber(dst.morale) or 60) + (avgReadiness - 55) * 0.025 + state.bases * 0.05 - state.newLosses * 1.8, 0, 100)
        dst.supply = supply
        dst.ammo = ammo
        dst.morale = morale
        dst.pressure = state.pressure
        dst.reserve = state.reserve
        dst.groups = state.groups
        dst.members = state.members
        dst.bases = state.bases
        dst.losses = losses
        dst.avgReadiness = math.floor(avgReadiness)
        dst.updatedAt = worldAge
        logistics[side] = dst
        changed = true
    end

    if war and war.front then
        war.front.redLogisticsSupply = logistics.red.supply
        war.front.greenLogisticsSupply = logistics.green.supply
        war.front.redLogisticsAmmo = logistics.red.ammo
        war.front.greenLogisticsAmmo = logistics.green.ammo
        war.front.redLogisticsMorale = logistics.red.morale
        war.front.greenLogisticsMorale = logistics.green.morale
        war.front.redPressure = logistics.red.pressure
        war.front.greenPressure = logistics.green.pressure
        war.front.redReserve = logistics.red.reserve
        war.front.greenReserve = logistics.green.reserve
        war.front.redLosses = logistics.red.losses
        war.front.greenLosses = logistics.green.losses
        if type(gmd.DebugMapMarkers) == "table" and gmd.DebugMapMarkers.STRATEGIC_FRONT_MAIN then
            local marker = gmd.DebugMapMarkers.STRATEGIC_FRONT_MAIN
            marker.redLogisticsSupply = war.front.redLogisticsSupply
            marker.greenLogisticsSupply = war.front.greenLogisticsSupply
            marker.redLogisticsAmmo = war.front.redLogisticsAmmo
            marker.greenLogisticsAmmo = war.front.greenLogisticsAmmo
            marker.redLogisticsMorale = war.front.redLogisticsMorale
            marker.greenLogisticsMorale = war.front.greenLogisticsMorale
            marker.redPressure = war.front.redPressure
            marker.greenPressure = war.front.greenPressure
            marker.redReserve = war.front.redReserve
            marker.greenReserve = war.front.greenReserve
            marker.updatedAt = worldAge
            NPCWorldDirectorBridge.SendDebugMapUpdate(marker)
        end
    end

    return changed
end

function NPCWorldDirectorBridge.EnsureStrategicActivityData(gmd)
    if type(gmd) ~= "table" then return nil end
    gmd.WorldDirector = gmd.WorldDirector or {}
    gmd.WorldDirector.strategicActivities = gmd.WorldDirector.strategicActivities or {}
    return gmd.WorldDirector.strategicActivities
end

function NPCWorldDirectorBridge.FindNearestStrategicActivityBase(gmd, x, y, side, mode, front)
    local best = nil
    local bestScore = 999999
    local other = side == "red" and "green" or "red"
    for _, base in pairs(gmd and gmd.BaseCamps or {}) do
        if type(base) == "table" and base.x and base.y then
            local owner = wd_activityBaseOwner(base)
            local ok = false
            if mode == "own" then ok = owner == side end
            if mode == "enemy" then ok = owner == other or (owner and owner ~= side) end
            if mode == "contested" then ok = base.captureTeam == side or base.captureTeam == other or base.status == "contested" end
            if ok then
                local score = NPCWorldDirectorBridge.DistanceToPoint(base, {x=x, y=y})
                if mode == "enemy" and front then score = score + NPCWorldDirectorBridge.DistanceToPoint(base, front) * 0.25 end
                if mode == "own" and base.status == "contested" then score = score - 300 end
                if mode == "enemy" and owner == other then score = score - 200 end
                if score < bestScore then
                    best = base
                    best.id = best.id or tostring(wd_activityBaseId(base) or "")
                    bestScore = score
                end
            end
        end
    end
    return best, bestScore
end


local function wd_strategyBaseOwner(base)
    if type(base) ~= "table" then return nil end
    local owner = base.owner
    if owner == nil then return nil end
    owner = tostring(owner)
    if owner == "" or owner == "neutral" then return nil end
    return owner
end

local function wd_strategyBaseIsNeutral(base)
    return wd_strategyBaseOwner(base) == nil
end

local function wd_groupStableRoll(group, modulo)
    modulo = math.max(1, tonumber(modulo) or 1)
    local key = tostring(group and (group.id or group.groupId or group.name or group.targetBaseId) or "")
    local sum = 0
    for i = 1, #key do
        sum = (sum + string.byte(key, i) * i) % 9973
    end
    return sum % modulo
end

local function wd_strategicManeuverRole(director, group, targetBase, neutralTarget, readiness, sideSupply, sideAmmo, sideMorale)
    if neutralTarget then return "secure_neutral" end
    if not (director and director.STRATEGIC_MANEUVER_ENABLED ~= false and group and targetBase) then return "main" end
    local count = NPCWorldDirectorBridge.GroupMemberCount(group)
    if count < (tonumber(director.STRATEGIC_MANEUVER_STRIKE_MIN_COUNT) or 3) then return "main" end
    if (tonumber(readiness) or 0) < (tonumber(director.STRATEGIC_ACTIVITY_LOW_READINESS) or 55) then return "main" end
    if math.min(tonumber(sideSupply) or 100, tonumber(sideAmmo) or 100, tonumber(sideMorale) or 100) < 48 then return "main" end
    local dist = NPCWorldDirectorBridge.DistanceToPoint(group, targetBase)
    if dist < (tonumber(director.STRATEGIC_MANEUVER_MIN_DISTANCE) or 560) then return "main" end

    local roll = wd_groupStableRoll(group, 5)
    if roll == 1 then return "flank_left" end
    if roll == 2 then return "flank_right" end
    if roll == 3 then return "feint" end
    return "main"
end

local function wd_strategicManeuverPoint(director, group, targetBase, role)
    if not (group and targetBase and group.x and group.y and targetBase.x and targetBase.y) then return nil, nil end
    if role ~= "flank_left" and role ~= "flank_right" and role ~= "feint" then return targetBase.x, targetBase.y end

    local gx = tonumber(group.x) or 0
    local gy = tonumber(group.y) or 0
    local tx = tonumber(targetBase.x) or gx
    local ty = tonumber(targetBase.y) or gy
    local dx = tx - gx
    local dy = ty - gy
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist <= 1 then return tx, ty end

    local nx = dx / dist
    local ny = dy / dist
    local sign = role == "flank_right" and -1 or 1
    local approach = math.min(dist * (role == "feint" and 0.34 or 0.58), tonumber(director and director.STRATEGIC_MANEUVER_APPROACH_DISTANCE) or 460)
    local offsetMax = tonumber(director and director.STRATEGIC_MANEUVER_FLANK_MAX_OFFSET) or 360
    local offset = math.min(math.max(dist * (role == "feint" and 0.12 or 0.22), 120), offsetMax)
    local px = gx + nx * approach + (-ny) * offset * sign
    local py = gy + ny * approach + nx * offset * sign

    return math.floor(px + 0.5), math.floor(py + 0.5)
end

local function wd_strategicStrikeKey(side, targetBaseId)
    if not (side and targetBaseId) then return nil end
    return tostring(side) .. ":" .. tostring(targetBaseId)
end

local function wd_strategicStrikeInfo(director, side, targetBaseId)
    local cache = director and director._strategicStrikeCache or nil
    local key = wd_strategicStrikeKey(side, targetBaseId)
    return key and type(cache) == "table" and cache[key] or nil
end

local function wd_strategicStrikeStagingPoint(director, group, targetBase)
    if not (group and targetBase and group.x and group.y and targetBase.x and targetBase.y) then return nil, nil end

    local gx = tonumber(group.x) or 0
    local gy = tonumber(group.y) or 0
    local tx = tonumber(targetBase.x) or gx
    local ty = tonumber(targetBase.y) or gy
    local dx = tx - gx
    local dy = ty - gy
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist <= 1 then return tx, ty end

    local nx = dx / dist
    local ny = dy / dist
    local stagingDistance = math.min(dist * 0.45, tonumber(director and director.STRATEGIC_STRIKE_STAGING_DISTANCE) or 360)
    local offset = math.min(math.max(dist * 0.12, 80), tonumber(director and director.STRATEGIC_STRIKE_STAGING_OFFSET) or 170)
    local sideRoll = wd_groupStableRoll(group, 2) == 0 and -1 or 1
    local px = tx - nx * stagingDistance + (-ny) * offset * sideRoll
    local py = ty - ny * stagingDistance + nx * offset * sideRoll

    return math.floor(px + 0.5), math.floor(py + 0.5)
end

local function wd_theatreSide(cache, side)
    if type(cache) ~= "table" or (side ~= "red" and side ~= "green") then return nil end
    cache[side] = cache[side] or {pressureByBase={}, reinforceByBase={}, ambushByBase={}}
    cache[side].pressureByBase = cache[side].pressureByBase or {}
    cache[side].reinforceByBase = cache[side].reinforceByBase or {}
    cache[side].ambushByBase = cache[side].ambushByBase or {}
    return cache[side]
end

local function wd_tableCountInfoAdd(tbl, key, count, power)
    if type(tbl) ~= "table" or not key then return nil end
    key = tostring(key)
    local info = tbl[key] or {count=0, power=0}
    info.count = info.count + (tonumber(count) or 1)
    info.power = info.power + (tonumber(power) or 0)
    tbl[key] = info
    return info
end

function NPCWorldDirectorBridge.RebuildStrategicTheatreContext(director, gmd, groupIds, worldAge)
    if not (director and gmd and type(groupIds) == "table") then return nil end
    if director.STRATEGIC_ENCIRCLEMENT_ENABLED == false and director.STRATEGIC_REINFORCE_THREATENED_BASE_ENABLED == false and director.STRATEGIC_COUNTER_AMBUSH_ENABLED == false then return nil end

    local cache = {
        red = {pressureByBase={}, reinforceByBase={}, ambushByBase={}},
        green = {pressureByBase={}, reinforceByBase={}, ambushByBase={}},
        updatedAt = worldAge
    }

    for _, groupId in ipairs(groupIds) do
        local group = gmd.VirtualGroups and gmd.VirtualGroups[groupId] or nil
        if type(group) == "table" and not group.activated and not group.inBattle then
            local side = wd_groupSide(group)
            local sideRec = wd_theatreSide(cache, side)
            if sideRec then
                local activityType = group.strategicActivityType or group.activityType
                local targetBaseId = group.strategicActivityTargetBaseId or group.targetBaseId or group.strategicStrikeAssemblyBaseId
                local power = tonumber(group.strategicPower) or ((tonumber(group.count) or NPCWorldDirectorBridge.GroupMemberCount(group)) * 18)
                if targetBaseId and activityType == "AmbushRoad" then
                    wd_tableCountInfoAdd(sideRec.ambushByBase, targetBaseId, 1, power)
                elseif targetBaseId and (activityType == "AssembleStrike" or activityType == "AttackBase" or activityType == "SiegeBase") then
                    local pressure = wd_tableCountInfoAdd(sideRec.pressureByBase, targetBaseId, 1, power)
                    pressure.x = (tonumber(pressure.x) or 0) + (tonumber(group.x) or tonumber(group.targetX) or 0)
                    pressure.y = (tonumber(pressure.y) or 0) + (tonumber(group.y) or tonumber(group.targetY) or 0)
                    if group.strategicPlanKind == "encircle" then
                        pressure.encircle = (tonumber(pressure.encircle) or 0) + 1
                    elseif group.strategicManeuverRole == "screen_reinforce" then
                        pressure.screen = (tonumber(pressure.screen) or 0) + 1
                    end
                elseif targetBaseId and (activityType == "ReinforceBase" or activityType == "DefendBase") then
                    wd_tableCountInfoAdd(sideRec.reinforceByBase, targetBaseId, 1, power)
                end
            end
        end
    end

    for _, base in pairs(gmd.BaseCamps or {}) do
        if type(base) == "table" and base.x and base.y then
            local owner = wd_strategyBaseOwner(base)
            if owner == "red" or owner == "green" then
                local sideRec = wd_theatreSide(cache, owner)
                local other = owner == "red" and "green" or "red"
                local otherRec = wd_theatreSide(cache, other)
                local baseId = wd_activityBaseId(base)
                if sideRec and otherRec and baseId then
                    baseId = tostring(baseId)
                    local enemyPressure = otherRec.pressureByBase[baseId]
                    local threat = 0
                    if base.status == "contested" or base.status == "siege_contested" then threat = threat + 520 end
                    if base.captureTeam and base.captureTeam ~= owner then threat = threat + 420 end
                    if enemyPressure then threat = threat + (tonumber(enemyPressure.count) or 0) * 150 + (tonumber(enemyPressure.power) or 0) * 0.18 end
                    local defenseScore = NPCWorldDirectorBridge.EstimateStrategicBaseDefenseScore(director, base)
                    local lowDefenseScore = tonumber(director.STRATEGIC_REINFORCE_LOW_DEFENSE_SCORE) or 380
                    if defenseScore < lowDefenseScore then threat = threat + (lowDefenseScore - defenseScore) * 0.55 end
                    if threat > (tonumber(sideRec.threatenedBaseThreat) or 0) then
                        sideRec.threatenedBase = base
                        sideRec.threatenedBaseId = baseId
                        sideRec.threatenedBaseThreat = threat
                        sideRec.threatenedEnemyGroups = enemyPressure and tonumber(enemyPressure.count) or 0
                        sideRec.threatenedEnemyPower = enemyPressure and tonumber(enemyPressure.power) or 0
                        if enemyPressure and (tonumber(enemyPressure.count) or 0) > 0 then
                            sideRec.threatenedApproachX = (tonumber(enemyPressure.x) or base.x or 0) / math.max(1, tonumber(enemyPressure.count) or 1)
                            sideRec.threatenedApproachY = (tonumber(enemyPressure.y) or base.y or 0) / math.max(1, tonumber(enemyPressure.count) or 1)
                        else
                            sideRec.threatenedApproachX = nil
                            sideRec.threatenedApproachY = nil
                        end
                    end
                end
            end
        end
    end

    director._strategicTheatreCache = cache
    return cache
end

local function wd_strategicPressureInfo(director, side, targetBaseId)
    local cache = director and director._strategicTheatreCache or nil
    local sideRec = wd_theatreSide(cache, side)
    if not (sideRec and targetBaseId) then return nil end
    return sideRec.pressureByBase[tostring(targetBaseId)]
end

local function wd_strategicEncirclementRole(director, side, group, targetBase, targetBaseId, neutralTarget, currentRole, committedGroups)
    if neutralTarget or currentRole == "assemble" then return currentRole end
    if not (director and director.STRATEGIC_ENCIRCLEMENT_ENABLED ~= false and side and group and targetBase and targetBaseId) then return currentRole end
    local committed = tonumber(committedGroups) or 0
    if committed < (tonumber(director.STRATEGIC_ENCIRCLEMENT_MIN_COMMITTED_GROUPS) or 3) then return currentRole end
    if NPCWorldDirectorBridge.GroupMemberCount(group) < (tonumber(director.STRATEGIC_MANEUVER_STRIKE_MIN_COUNT) or 3) then return currentRole end

    local pressure = wd_strategicPressureInfo(director, side, targetBaseId)
    local encircleCount = pressure and tonumber(pressure.encircle) or 0
    local screenCount = pressure and tonumber(pressure.screen) or 0
    local roll = wd_groupStableRoll(group, 8)
    if encircleCount < 2 and roll == 0 then return "encircle_left" end
    if encircleCount < 2 and roll == 1 then return "encircle_right" end
    if screenCount < 1 and committed >= ((tonumber(director.STRATEGIC_ENCIRCLEMENT_MIN_COMMITTED_GROUPS) or 3) + 1) and roll == 2 then return "screen_reinforce" end
    return currentRole
end

local function wd_strategicEncirclementPoint(director, gmd, side, group, targetBase, role)
    if not (targetBase and targetBase.x and targetBase.y and group and group.x and group.y) then return nil, nil end
    if role ~= "encircle_left" and role ~= "encircle_right" and role ~= "screen_reinforce" then return nil, nil end

    local tx = tonumber(targetBase.x) or 0
    local ty = tonumber(targetBase.y) or 0
    local ref = nil
    if role == "screen_reinforce" then
        local other = side == "red" and "green" or "red"
        ref = NPCWorldDirectorBridge.FindNearestOwnedStrategicBase(gmd, tx, ty, other)
    end
    ref = ref or NPCWorldDirectorBridge.FindNearestOwnedStrategicBase(gmd, tx, ty, side) or group
    local rx = tonumber(ref.x) or tonumber(group.x) or tx
    local ry = tonumber(ref.y) or tonumber(group.y) or ty
    local dx = tx - rx
    local dy = ty - ry
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist <= 1 then
        dx = tx - (tonumber(group.x) or tx)
        dy = ty - (tonumber(group.y) or ty)
        dist = math.sqrt(dx * dx + dy * dy)
    end
    if dist <= 1 then return tx, ty end

    local nx = dx / dist
    local ny = dy / dist
    local radius = tonumber(director and director.STRATEGIC_ENCIRCLEMENT_RADIUS) or 260
    local offset = tonumber(director and director.STRATEGIC_ENCIRCLEMENT_OFFSET) or 320
    local sign = role == "encircle_right" and -1 or 1
    if role == "screen_reinforce" then
        local px = tx + nx * math.min(radius * 1.15, 340)
        local py = ty + ny * math.min(radius * 1.15, 340)
        return math.floor(px + 0.5), math.floor(py + 0.5)
    end

    local px = tx - nx * math.min(radius * 0.45, 140) + (-ny) * offset * sign
    local py = ty - ny * math.min(radius * 0.45, 140) + nx * offset * sign
    return math.floor(px + 0.5), math.floor(py + 0.5)
end

local function wd_strategicCounterAmbushPoint(director, sideRec, group, base)
    if not (base and base.x and base.y and group) then return nil, nil end
    local bx = tonumber(base.x) or 0
    local by = tonumber(base.y) or 0
    local ax = tonumber(sideRec and sideRec.threatenedApproachX) or tonumber(group.x) or bx
    local ay = tonumber(sideRec and sideRec.threatenedApproachY) or tonumber(group.y) or by
    local dx = bx - ax
    local dy = by - ay
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist <= 1 then
        dx = bx - (tonumber(group.x) or bx)
        dy = by - (tonumber(group.y) or by)
        dist = math.sqrt(dx * dx + dy * dy)
    end
    if dist <= 1 then return bx, by end

    local nx = dx / dist
    local ny = dy / dist
    local offset = math.min(math.max(dist * 0.08, 70), tonumber(director and director.STRATEGIC_COUNTER_AMBUSH_OFFSET) or 180)
    local sign = wd_groupStableRoll(group, 2) == 0 and 1 or -1
    local t = wd_clamp(0.54 + (wd_groupStableRoll(group, 5) * 0.035), 0.50, 0.70)
    local px = ax + dx * t + (-ny) * offset * sign
    local py = ay + dy * t + nx * offset * sign
    return math.floor(px + 0.5), math.floor(py + 0.5)
end

function NPCWorldDirectorBridge.BuildStrategicCounterAmbush(director, gmd, side, group, readiness, sideSupply, sideAmmo, sideMorale, front, worldAge)
    if not (director and director.STRATEGIC_COUNTER_AMBUSH_ENABLED ~= false and gmd and group and side) then return nil end
    local cache = director._strategicTheatreCache
    local sideRec = wd_theatreSide(cache, side)
    local base = sideRec and sideRec.threatenedBase or nil
    local baseId = sideRec and sideRec.threatenedBaseId or nil
    if not (base and baseId and base.x and base.y) then return nil end

    local threat = tonumber(sideRec.threatenedBaseThreat) or 0
    if threat < (tonumber(director.STRATEGIC_COUNTER_AMBUSH_MIN_THREAT) or 620) then return nil end
    if (tonumber(readiness) or 0) < (tonumber(director.STRATEGIC_COUNTER_AMBUSH_MIN_READINESS) or 58) then return nil end
    if math.min(tonumber(sideSupply) or 100, tonumber(sideAmmo) or 100, tonumber(sideMorale) or 100) < 48 then return nil end
    if NPCWorldDirectorBridge.GroupMemberCount(group) < math.max(2, tonumber(director.STRATEGIC_ACTIVITY_ROAD_PATROL_MIN_COUNT) or 1) then return nil end

    local ambushInfo = sideRec.ambushByBase and sideRec.ambushByBase[tostring(baseId)] or nil
    local assigned = ambushInfo and tonumber(ambushInfo.count) or 0
    if assigned >= (tonumber(director.STRATEGIC_COUNTER_AMBUSH_MAX_PER_SIDE) or 2) then return nil end

    local activityType = group.strategicActivityType or group.activityType
    local isCommittedAttack = activityType == "AssembleStrike" or activityType == "AttackBase" or activityType == "SiegeBase"
    if isCommittedAttack and threat < (tonumber(director.STRATEGIC_REINFORCE_BREAK_STRIKE_THREAT) or 980) then return nil end

    local dist = NPCWorldDirectorBridge.DistanceToPoint(group, base)
    if dist > (tonumber(director.STRATEGIC_COUNTER_AMBUSH_RADIUS) or 2400) and wd_groupStableRoll(group, 5) ~= 0 then return nil end
    if wd_groupStableRoll(group, 4) == 3 and assigned > 0 then return nil end

    local x, y = wd_strategicCounterAmbushPoint(director, sideRec, group, base)
    if not (x and y) then return nil end
    return {
        type="AmbushRoad",
        x=x,
        y=y,
        z=base.z or 0,
        targetBaseId=baseId,
        priority=wd_activityTypePriority("AmbushRoad") - (threat >= (tonumber(director.STRATEGIC_REINFORCE_BREAK_STRIKE_THREAT) or 980) and 16 or 8),
        logisticsSupply=sideSupply,
        logisticsAmmo=sideAmmo,
        logisticsMorale=sideMorale,
        strategicPlanKind="counter_ambush",
        strategicManeuverRole="counter_ambush",
        strategicManeuverTargetX=base.x,
        strategicManeuverTargetY=base.y,
        strategicManeuverTargetBaseId=baseId,
        strategicManeuverAssignedAt=worldAge
    }
end

function NPCWorldDirectorBridge.BuildStrategicThreatResponse(director, gmd, side, group, readiness, sideSupply, sideAmmo, sideMorale, front, worldAge)
    if not (director and director.STRATEGIC_REINFORCE_THREATENED_BASE_ENABLED ~= false and gmd and group and side) then return nil end
    local cache = director._strategicTheatreCache
    local sideRec = wd_theatreSide(cache, side)
    local base = sideRec and sideRec.threatenedBase or nil
    local baseId = sideRec and sideRec.threatenedBaseId or nil
    if not (base and baseId and base.x and base.y) then return nil end

    local lowReadiness = tonumber(director.STRATEGIC_ACTIVITY_LOW_READINESS) or 55
    if (tonumber(readiness) or 0) < lowReadiness then return nil end
    if math.min(tonumber(sideSupply) or 100, tonumber(sideAmmo) or 100, tonumber(sideMorale) or 100) < 45 then return nil end

    local reinforceInfo = sideRec.reinforceByBase and sideRec.reinforceByBase[tostring(baseId)] or nil
    local assigned = reinforceInfo and tonumber(reinforceInfo.count) or 0
    local enemyGroups = tonumber(sideRec.threatenedEnemyGroups) or 0
    local required = math.max(1, enemyGroups + 1)
    local maxGroups = tonumber(director.STRATEGIC_REINFORCE_THREATENED_BASE_MAX_GROUPS) or 3
    if required > maxGroups then required = maxGroups end
    if assigned >= required then return nil end

    local activityType = group.strategicActivityType or group.activityType
    local isCommittedAttack = activityType == "AssembleStrike" or activityType == "AttackBase" or activityType == "SiegeBase"
    local threat = tonumber(sideRec.threatenedBaseThreat) or 0
    local breakThreat = tonumber(director.STRATEGIC_REINFORCE_BREAK_STRIKE_THREAT) or 980
    local strongThreat = threat >= breakThreat
    if isCommittedAttack and not strongThreat then return nil end
    if not strongThreat and wd_groupStableRoll(group, 3) ~= 0 then return nil end

    local dist = NPCWorldDirectorBridge.DistanceToPoint(group, base)
    local radius = tonumber(director.STRATEGIC_REINFORCE_THREATENED_BASE_RADIUS) or 2600
    if dist > radius and wd_groupStableRoll(group, 4) ~= 0 then return nil end

    return {
        type="ReinforceBase",
        x=base.x,
        y=base.y,
        z=base.z or 0,
        targetBaseId=baseId,
        priority=wd_activityTypePriority("ReinforceBase") - (threat >= (tonumber(director.STRATEGIC_REINFORCE_BREAK_STRIKE_THREAT) or 980) and 8 or 0),
        logisticsSupply=sideSupply,
        logisticsAmmo=sideAmmo,
        logisticsMorale=sideMorale,
        strategicPlanKind="threat_response",
        strategicManeuverRole="reinforce_threatened_base",
        strategicManeuverTargetX=base.x,
        strategicManeuverTargetY=base.y,
        strategicManeuverTargetBaseId=baseId,
        strategicManeuverAssignedAt=worldAge
    }
end

function NPCWorldDirectorBridge.RebuildStrategicStrikeContext(director, gmd, groupIds, worldAge)
    if not (director and director.STRATEGIC_STRIKE_ASSEMBLY_ENABLED ~= false and gmd and type(groupIds) == "table") then return nil end
    local cache = {}
    for _, groupId in ipairs(groupIds) do
        local group = gmd.VirtualGroups and gmd.VirtualGroups[groupId] or nil
        if type(group) == "table" and not group.activated and not group.inBattle then
            local activityType = group.strategicActivityType
            if activityType == "AssembleStrike" or activityType == "AttackBase" or activityType == "SiegeBase" then
                local side = wd_groupSide(group)
                local targetBaseId = group.strategicStrikeAssemblyBaseId or group.strategicActivityTargetBaseId or group.targetBaseId
                local key = wd_strategicStrikeKey(side, targetBaseId)
                if key then
                    local info = cache[key] or {count=0, power=0, assembling=0, attacking=0, oldestAt=worldAge}
                    info.count = info.count + 1
                    info.power = info.power + (tonumber(group.strategicPower) or ((tonumber(group.count) or NPCWorldDirectorBridge.GroupMemberCount(group)) * 18))
                    if activityType == "AssembleStrike" then info.assembling = info.assembling + 1 else info.attacking = info.attacking + 1 end
                    local at = tonumber(group.strategicStrikeAssemblyAt) or tonumber(group.strategicActivityUpdatedAt) or worldAge
                    if at < (tonumber(info.oldestAt) or worldAge) then info.oldestAt = at end
                    cache[key] = info
                end
            end
        end
    end
    director._strategicStrikeCache = cache
    return cache
end

function NPCWorldDirectorBridge.BuildStrategicBaseActivity(director, gmd, side, group, targetBase, readiness, sideSupply, sideAmmo, sideMorale, homeEconomy, worldAge)
    if not (targetBase and targetBase.x and targetBase.y and group) then return nil end
    local dist = NPCWorldDirectorBridge.DistanceToPoint(group, targetBase)
    local neutralTarget = wd_strategyBaseIsNeutral(targetBase)
    local targetBaseId = wd_activityBaseId(targetBase)
    local role = wd_strategicManeuverRole(director, group, targetBase, neutralTarget, readiness, sideSupply, sideAmmo, sideMorale)
    local activityType = dist <= (tonumber(director.STRATEGIC_ACTIVITY_SIEGE_RADIUS) or 420) and "SiegeBase" or "AttackBase"
    local targetX, targetY = nil, nil
    local planKind = "contact"
    local strikeCommitted = nil
    local strikeRequired = nil
    local strikeReady = nil

    if neutralTarget then
        planKind = "expansion"
        targetX, targetY = wd_strategicManeuverPoint(director, group, targetBase, role)
    else
        local info = targetBaseId and wd_strategicStrikeInfo(director, side, targetBaseId) or nil
        local existingAttack = (group.strategicActivityType == "AttackBase" or group.strategicActivityType == "SiegeBase") and tostring(group.strategicActivityTargetBaseId or group.targetBaseId or "") == tostring(targetBaseId or "")
        if director and director.STRATEGIC_STRIKE_ASSEMBLY_ENABLED ~= false and targetBaseId and not existingAttack then
            strikeCommitted = info and tonumber(info.count) or 0
            strikeRequired = math.max(1, tonumber(director.STRATEGIC_STRIKE_ASSEMBLY_MIN_GROUPS) or 2)
            local maxGroups = math.max(strikeRequired, tonumber(director.STRATEGIC_STRIKE_ASSEMBLY_MAX_GROUPS) or 4)
            if strikeCommitted > maxGroups then strikeCommitted = maxGroups end
            local sameAssembly = group.strategicActivityType == "AssembleStrike" and tostring(group.strategicStrikeAssemblyBaseId or group.strategicActivityTargetBaseId or group.targetBaseId or "") == tostring(targetBaseId or "")
            local assemblyAt = tonumber(group.strategicStrikeAssemblyAt) or tonumber(group.strategicActivityUpdatedAt) or worldAge
            local waited = sameAssembly and ((tonumber(worldAge) or 0) - assemblyAt) or 0
            local maxWait = tonumber(director.STRATEGIC_STRIKE_ASSEMBLY_MAX_WAIT_HOURS) or 1.25
            strikeReady = strikeCommitted >= strikeRequired or waited >= maxWait
            if not strikeReady then
                activityType = "AssembleStrike"
                planKind = "strike_group"
                role = "assemble"
                targetX, targetY = wd_strategicStrikeStagingPoint(director, group, targetBase)
            end
        end

        if activityType ~= "AssembleStrike" then
            local committedForRole = tonumber(strikeCommitted) or (info and tonumber(info.count)) or 0
            role = wd_strategicEncirclementRole(director, side, group, targetBase, targetBaseId, neutralTarget, role, committedForRole)
            if role == "encircle_left" or role == "encircle_right" or role == "screen_reinforce" then
                targetX, targetY = wd_strategicEncirclementPoint(director, gmd, side, group, targetBase, role)
            else
                targetX, targetY = wd_strategicManeuverPoint(director, group, targetBase, role)
            end
            if role == "flank_left" or role == "flank_right" then
                planKind = "flank"
            elseif role == "feint" then
                planKind = "feint"
            elseif role == "encircle_left" or role == "encircle_right" or role == "screen_reinforce" then
                planKind = "encircle"
            elseif NPCWorldDirectorBridge.GroupMemberCount(group) >= (tonumber(director.STRATEGIC_MANEUVER_STRIKE_MIN_COUNT) or 3) then
                planKind = "strike_group"
            end
        end
    end

    return {
        type = activityType,
        x = targetX or targetBase.x,
        y = targetY or targetBase.y,
        z = targetBase.z or 0,
        targetBaseId = targetBaseId,
        priority = wd_activityTypePriority(activityType) + (neutralTarget and -6 or 0) + (role == "feint" and 8 or 0),
        logisticsSupply = sideSupply,
        logisticsAmmo = sideAmmo,
        logisticsMorale = sideMorale,
        baseEconomyStatus = homeEconomy and homeEconomy.status,
        strategicPlanKind = planKind,
        strategicManeuverRole = role,
        strategicManeuverTargetX = targetBase.x,
        strategicManeuverTargetY = targetBase.y,
        strategicManeuverTargetBaseId = targetBaseId,
        strategicManeuverAssignedAt = worldAge,
        strategicStrikeCommittedGroups = strikeCommitted,
        strategicStrikeRequiredGroups = strikeRequired,
        strategicStrikeReady = strikeReady
    }
end

function NPCWorldDirectorBridge.CanAssignStrategicActivity(group)
    if type(group) ~= "table" then return false end
    if group.activated or group.inBattle or group.mercenary then return false end
    if group.state == "base_garrison" or group.targetClass == "base_guard" then return false end
    if group.bountyHunter or group.targetClass == "bounty_hunt" then return false end
    if NPCWorldDirectorBridge.GroupMemberCount(group) <= 0 then return false end
    return true
end

function NPCWorldDirectorBridge.ResolveStrategicActivityForGroup(director, gmd, group, worldAge)
    if not NPCWorldDirectorBridge.CanAssignStrategicActivity(group) then return nil end
    local side = group.side or group.factionSide or group.patrolColor or (group.hostile and "red" or "green")
    if side ~= "red" and side ~= "green" then return nil end

    local war = gmd and gmd.WorldDirector and gmd.WorldDirector.strategicWar or nil
    local front = war and war.front or nil
    local home = NPCStrategicAIBridge and NPCStrategicAIBridge.GetBaseById and NPCStrategicAIBridge.GetBaseById(gmd, group.homeBaseId or group.missionOriginBaseId or group.originBaseId) or nil
    local readiness = wd_groupReadiness(group)
    local count = NPCWorldDirectorBridge.GroupMemberCount(group)
    local sideLogistics = NPCWorldDirectorBridge.SideLogistics(gmd, side)
    local sideSupply = sideLogistics and tonumber(sideLogistics.supply) or 100
    local sideAmmo = sideLogistics and tonumber(sideLogistics.ammo) or 100
    local sideMorale = sideLogistics and tonumber(sideLogistics.morale) or 100
    local lowLogistics = sideSupply <= (tonumber(director.STRATEGIC_LOGISTICS_LOW_SUPPLY) or 42) or sideAmmo <= (tonumber(director.STRATEGIC_LOGISTICS_LOW_AMMO) or 38) or sideMorale <= (tonumber(director.STRATEGIC_LOGISTICS_LOW_MORALE) or 35)
    local criticalLogistics = sideSupply <= (tonumber(director.STRATEGIC_LOGISTICS_CRITICAL_SUPPLY) or 22) or sideAmmo <= (tonumber(director.STRATEGIC_LOGISTICS_CRITICAL_AMMO) or 20) or sideMorale <= (tonumber(director.STRATEGIC_LOGISTICS_CRITICAL_MORALE) or 18)
    local isRoadActivityGroup = group.roadPatrol or group.checkpointId
    local homeEconomy = home and home.economy or nil
    local homeEconomyCritical = type(homeEconomy) == "table" and (homeEconomy.status == "critical" or (tonumber(homeEconomy.manpowerReserve) or 0) <= 0)
    local homeEconomyLow = type(homeEconomy) == "table" and (homeEconomy.status == "low" or (tonumber(homeEconomy.supplyReadiness) or 100) <= (tonumber(director.BASE_LOGISTICS_LOW_READINESS) or 52))

    if homeEconomyCritical and home then
        return {type="RetreatToBase", x=home.x, y=home.y, z=home.z or 0, targetBaseId=wd_activityBaseId(home), priority=wd_activityTypePriority("RetreatToBase"), logisticsSupply=sideSupply, logisticsAmmo=sideAmmo, logisticsMorale=sideMorale, baseEconomyStatus=homeEconomy.status}
    end

    if group.economyConvoy or group.convoyId then
        return {type="EscortConvoy", x=group.targetX or group.x, y=group.targetY or group.y, z=group.targetZ or group.z or 0, targetGroupId=group.convoyId or group.id, priority=wd_activityTypePriority("EscortConvoy")}
    end

    if isRoadActivityGroup
        and count > (tonumber(director.STRATEGIC_ACTIVITY_ROAD_PATROL_MIN_COUNT) or 1)
        and readiness > (tonumber(director.STRATEGIC_ACTIVITY_ROAD_PATROL_RETREAT_READINESS) or 22)
        and not criticalLogistics then
        local roadTarget = nil
        if NPCWorldDirectorBridge.GetNearbyRoadPoint then
            roadTarget = NPCWorldDirectorBridge.GetNearbyRoadPoint(director, group.x, group.y, director.ROAD_PATROL_TARGET_RADIUS)
        end
        roadTarget = roadTarget or {x=group.targetX or group.x, y=group.targetY or group.y, z=group.targetZ or group.z or 0}
        return {type="AmbushRoad", x=roadTarget.x, y=roadTarget.y, z=roadTarget.z or 0, targetGroupId=group.id, priority=wd_activityTypePriority("AmbushRoad")}
    end

    if home and (home.status == "contested" or (home.captureTeam and home.captureTeam ~= side)) then
        return {type="DefendBase", x=home.x, y=home.y, z=home.z or 0, targetBaseId=wd_activityBaseId(home), priority=wd_activityTypePriority("DefendBase")}
    end

    local criticalReadiness = readiness <= (tonumber(director.STRATEGIC_ACTIVITY_CRITICAL_READINESS) or 30)
    local stretchedAndWeak = group.supplyLineState == "stretched" and readiness <= (tonumber(director.STRATEGIC_ACTIVITY_LOW_READINESS) or 55)
    local shouldRetreat = criticalReadiness or count <= 1 or criticalLogistics or stretchedAndWeak
    if isRoadActivityGroup then
        shouldRetreat = readiness <= (tonumber(director.STRATEGIC_ACTIVITY_ROAD_PATROL_RETREAT_READINESS) or 22) or count <= (tonumber(director.STRATEGIC_ACTIVITY_ROAD_PATROL_MIN_COUNT) or 1) or criticalLogistics
    end
    if shouldRetreat then
        local fallbackHome = home or NPCWorldDirectorBridge.FindNearestStrategicActivityBase(gmd, group.x, group.y, side, "own", front)
        if fallbackHome then
            return {type="RetreatToBase", x=fallbackHome.x, y=fallbackHome.y, z=fallbackHome.z or 0, targetBaseId=wd_activityBaseId(fallbackHome), priority=wd_activityTypePriority("RetreatToBase"), logisticsSupply=sideSupply, logisticsAmmo=sideAmmo, logisticsMorale=sideMorale}
        end
    end

    if group.roadPatrol or group.checkpointId then
        local roadTarget = nil
        if NPCWorldDirectorBridge.GetNearbyRoadPoint then
            roadTarget = NPCWorldDirectorBridge.GetNearbyRoadPoint(director, group.x, group.y, director.ROAD_PATROL_TARGET_RADIUS)
        end
        roadTarget = roadTarget or {x=group.targetX or group.x, y=group.targetY or group.y, z=group.targetZ or group.z or 0}
        return {type="AmbushRoad", x=roadTarget.x, y=roadTarget.y, z=roadTarget.z or 0, targetGroupId=group.id, priority=wd_activityTypePriority("AmbushRoad")}
    end

    local friendlyNeed = NPCWorldDirectorBridge.FindNearestStrategicActivityBase(gmd, group.x, group.y, side, "own", front)
    if friendlyNeed and friendlyNeed.status == "contested" then
        return {type="ReinforceBase", x=friendlyNeed.x, y=friendlyNeed.y, z=friendlyNeed.z or 0, targetBaseId=wd_activityBaseId(friendlyNeed), priority=wd_activityTypePriority("ReinforceBase")}
    end

    local threatResponse = NPCWorldDirectorBridge.BuildStrategicThreatResponse(director, gmd, side, group, readiness, sideSupply, sideAmmo, sideMorale, front, worldAge)
    if threatResponse then return threatResponse end

    local counterAmbush = NPCWorldDirectorBridge.BuildStrategicCounterAmbush(director, gmd, side, group, readiness, sideSupply, sideAmmo, sideMorale, front, worldAge)
    if counterAmbush then return counterAmbush end

    local targetBase = NPCWorldDirectorBridge.FindStrategicFrontTargetBase(gmd, side, front, group, director) or NPCWorldDirectorBridge.FindNearestStrategicActivityBase(gmd, group.x, group.y, side, "enemy", front)
    if targetBase then
        if lowLogistics and front and front.x and front.y then
            return {type="ScoutFront", x=front.x, y=front.y, z=front.z or 0, priority=wd_activityTypePriority("ScoutFront"), logisticsSupply=sideSupply, logisticsAmmo=sideAmmo, logisticsMorale=sideMorale}
        end
        if homeEconomyLow and front and front.x and front.y then
            return {type="ScoutFront", x=front.x, y=front.y, z=front.z or 0, priority=wd_activityTypePriority("ScoutFront"), logisticsSupply=sideSupply, logisticsAmmo=sideAmmo, logisticsMorale=sideMorale, baseEconomyStatus=homeEconomy and homeEconomy.status}
        end
        local baseActivity = NPCWorldDirectorBridge.BuildStrategicBaseActivity(director, gmd, side, group, targetBase, readiness, sideSupply, sideAmmo, sideMorale, homeEconomy, worldAge)
        if baseActivity then return baseActivity end
    end

    if front and front.x and front.y then
        return {type="ScoutFront", x=front.x, y=front.y, z=front.z or 0, priority=wd_activityTypePriority("ScoutFront")}
    end

    if group.hostile == true then
        local player, dist = NPCWorldDirectorBridge.GetNearestPlayer(director, group.x, group.y, tonumber(director.STRATEGIC_ACTIVITY_HUNT_PLAYER_RADIUS) or 520)
        if player and dist then
            return {type="HuntPlayer", x=player:getX(), y=player:getY(), z=player:getZ() or 0, priority=wd_activityTypePriority("HuntPlayer")}
        end
    end

    return {type="Patrol", x=group.targetX or group.x, y=group.targetY or group.y, z=group.targetZ or group.z or 0, priority=wd_activityTypePriority("Patrol")}
end

function NPCWorldDirectorBridge.StrategicActivityId(activity, side)
    if type(activity) ~= "table" then return nil end
    local target = activity.targetBaseId or activity.targetGroupId or "front"
    return tostring(side or "neutral") .. "_" .. tostring(activity.type or "Patrol") .. "_" .. tostring(target)
end

function NPCWorldDirectorBridge.UpsertStrategicActivity(director, gmd, activity, group, side, worldAge)
    local activities = NPCWorldDirectorBridge.EnsureStrategicActivityData(gmd)
    if not activities or type(activity) ~= "table" or not activity.type then return nil end
    local activityId = NPCWorldDirectorBridge.StrategicActivityId(activity, side)
    if not activityId then return nil end
    local record = activities[activityId] or {id=activityId, createdAt=worldAge, assignedGroups={}}
    record.type = activity.type
    record.side = side
    record.x = activity.x
    record.y = activity.y
    record.z = activity.z or 0
    record.targetBaseId = activity.targetBaseId
    record.targetGroupId = activity.targetGroupId
    record.strategicPlanKind = activity.strategicPlanKind
    record.strategicManeuverRole = activity.strategicManeuverRole
    record.strategicManeuverTargetX = activity.strategicManeuverTargetX
    record.strategicManeuverTargetY = activity.strategicManeuverTargetY
    record.strategicManeuverTargetBaseId = activity.strategicManeuverTargetBaseId
    record.strategicStrikeCommittedGroups = activity.strategicStrikeCommittedGroups
    record.strategicStrikeRequiredGroups = activity.strategicStrikeRequiredGroups
    record.strategicStrikeReady = activity.strategicStrikeReady
    record.logisticsSupply = activity.logisticsSupply
    record.logisticsAmmo = activity.logisticsAmmo
    record.logisticsMorale = activity.logisticsMorale
    record.priority = activity.priority or wd_activityTypePriority(activity.type)
    record.state = NPC_STRATEGIC_ACTIVITY_STATES[activity.type] or "activity_active"
    record.active = true
    record.updatedAt = worldAge
    record.assignedGroups = record.assignedGroups or {}
    if group and group.id then record.assignedGroups[tostring(group.id)] = true end
    activities[activityId] = record

    if type(gmd.DebugMapMarkers) == "table" then
        local markerId = "SA_" .. tostring(activityId)
        local marker = gmd.DebugMapMarkers[markerId] or {}
        marker.id = markerId
        marker.markerType = "activity"
        marker.x = record.x
        marker.y = record.y
        marker.z = record.z or 0
        marker.name = tostring(record.type) .. " " .. tostring(record.targetBaseId or record.targetGroupId or record.side or "")
        marker.virtual = true
        marker.active = true
        marker.dead = false
        marker.side = record.side
        marker.factionSide = record.side
        marker.strategicActivityId = record.id
        marker.strategicActivityType = record.type
        marker.strategicActivityState = record.state
        marker.strategicActivityPriority = record.priority
        marker.targetBaseId = record.targetBaseId
        marker.targetGroupId = record.targetGroupId
        marker.strategicPlanKind = record.strategicPlanKind
        marker.strategicManeuverRole = record.strategicManeuverRole
        marker.strategicManeuverTargetX = record.strategicManeuverTargetX
        marker.strategicManeuverTargetY = record.strategicManeuverTargetY
        marker.strategicManeuverTargetBaseId = record.strategicManeuverTargetBaseId
        marker.strategicStrikeCommittedGroups = record.strategicStrikeCommittedGroups
        marker.strategicStrikeRequiredGroups = record.strategicStrikeRequiredGroups
        marker.strategicStrikeReady = record.strategicStrikeReady
        marker.logisticsSupply = record.logisticsSupply
        marker.logisticsAmmo = record.logisticsAmmo
        marker.logisticsMorale = record.logisticsMorale
        marker.updatedAt = worldAge
        gmd.DebugMapMarkers[markerId] = marker
        NPCWorldDirectorBridge.SendDebugMapUpdate(marker)
    end

    return record
end

function NPCWorldDirectorBridge.ShouldKeepStrategicActivity(director, group, activity, worldAge)
    if type(group) ~= "table" or type(activity) ~= "table" or not activity.type then return false end
    if tostring(group.strategicActivityType or "") ~= tostring(activity.type or "") then return false end
    local last = tonumber(group.strategicActivityUpdatedAt) or 0
    local cooldown = tonumber(director and director.STRATEGIC_ACTIVITY_REASSIGN_COOLDOWN_HOURS) or 0
    if last <= 0 or cooldown <= 0 or (tonumber(worldAge) or 0) - last >= cooldown then return false end
    if activity.targetBaseId and tostring(group.strategicActivityTargetBaseId or group.targetBaseId or "") ~= tostring(activity.targetBaseId) then return false end
    if activity.targetGroupId and tostring(group.strategicActivityTargetGroupId or "") ~= tostring(activity.targetGroupId) then return false end
    if activity.x and activity.y and group.targetX and group.targetY then
        local dx = (tonumber(group.targetX) or 0) - (tonumber(activity.x) or 0)
        local dy = (tonumber(group.targetY) or 0) - (tonumber(activity.y) or 0)
        local maxDist = tonumber(director and director.STRATEGIC_ACTIVITY_SAME_TARGET_DISTANCE) or 24
        if dx * dx + dy * dy > maxDist * maxDist then return false end
    end
    return true
end

function NPCWorldDirectorBridge.ApplyStrategicActivityToGroup(director, gmd, groupId, group, activity, worldAge)
    if type(group) ~= "table" or type(activity) ~= "table" or not activity.type then return false end
    local side = group.side or group.factionSide or group.patrolColor or (group.hostile and "red" or "green")
    if NPCWorldDirectorBridge.ShouldKeepStrategicActivity(director, group, activity, worldAge) then return false end
    local record = NPCWorldDirectorBridge.UpsertStrategicActivity(director, gmd, activity, group, side, worldAge)
    if not record then return false end

    local changed = false
    local state = NPC_STRATEGIC_ACTIVITY_STATES[activity.type] or "activity_active"
    local targetClass = NPC_STRATEGIC_ACTIVITY_TARGET_CLASS[activity.type] or "activity"
    if group.strategicActivityId ~= record.id then group.strategicActivityId = record.id; changed = true end
    if group.strategicActivityType ~= activity.type then group.strategicActivityType = activity.type; changed = true end
    if group.strategicActivityState ~= state then group.strategicActivityState = state; changed = true end
    if group.strategicActivityPriority ~= record.priority then group.strategicActivityPriority = record.priority; changed = true end
    if activity.logisticsSupply and group.strategicActivityLogisticsSupply ~= activity.logisticsSupply then group.strategicActivityLogisticsSupply = activity.logisticsSupply; changed = true end
    if activity.logisticsAmmo and group.strategicActivityLogisticsAmmo ~= activity.logisticsAmmo then group.strategicActivityLogisticsAmmo = activity.logisticsAmmo; changed = true end
    if activity.logisticsMorale and group.strategicActivityLogisticsMorale ~= activity.logisticsMorale then group.strategicActivityLogisticsMorale = activity.logisticsMorale; changed = true end
    if group.targetClass ~= targetClass then group.targetClass = targetClass; changed = true end
    if group.state ~= state then group.state = state; changed = true end
    if activity.x and math.floor(tonumber(group.targetX) or -999999) ~= math.floor(tonumber(activity.x) or 0) then group.targetX = activity.x; changed = true end
    if activity.y and math.floor(tonumber(group.targetY) or -999999) ~= math.floor(tonumber(activity.y) or 0) then group.targetY = activity.y; changed = true end
    if activity.z and math.floor(tonumber(group.targetZ) or -999999) ~= math.floor(tonumber(activity.z) or 0) then group.targetZ = activity.z; changed = true end
    if activity.targetBaseId and tostring(group.targetBaseId or "") ~= tostring(activity.targetBaseId) then group.targetBaseId = activity.targetBaseId; changed = true end
    if activity.targetBaseId and tostring(group.strategicActivityTargetBaseId or "") ~= tostring(activity.targetBaseId) then group.strategicActivityTargetBaseId = activity.targetBaseId; changed = true end
    if activity.targetGroupId and tostring(group.strategicActivityTargetGroupId or "") ~= tostring(activity.targetGroupId) then group.strategicActivityTargetGroupId = activity.targetGroupId; changed = true end
    if group.strategicPlanKind ~= activity.strategicPlanKind then group.strategicPlanKind = activity.strategicPlanKind; changed = true end
    if group.strategicManeuverRole ~= activity.strategicManeuverRole then group.strategicManeuverRole = activity.strategicManeuverRole; changed = true end
    if group.strategicManeuverTargetX ~= activity.strategicManeuverTargetX then group.strategicManeuverTargetX = activity.strategicManeuverTargetX; changed = true end
    if group.strategicManeuverTargetY ~= activity.strategicManeuverTargetY then group.strategicManeuverTargetY = activity.strategicManeuverTargetY; changed = true end
    if group.strategicManeuverTargetBaseId ~= activity.strategicManeuverTargetBaseId then group.strategicManeuverTargetBaseId = activity.strategicManeuverTargetBaseId; changed = true end
    if group.strategicManeuverAssignedAt ~= activity.strategicManeuverAssignedAt then group.strategicManeuverAssignedAt = activity.strategicManeuverAssignedAt; changed = true end
    if group.strategicStrikeCommittedGroups ~= activity.strategicStrikeCommittedGroups then group.strategicStrikeCommittedGroups = activity.strategicStrikeCommittedGroups; changed = true end
    if group.strategicStrikeRequiredGroups ~= activity.strategicStrikeRequiredGroups then group.strategicStrikeRequiredGroups = activity.strategicStrikeRequiredGroups; changed = true end
    if group.strategicStrikeReady ~= activity.strategicStrikeReady then group.strategicStrikeReady = activity.strategicStrikeReady; changed = true end
    if activity.type == "AssembleStrike" then
        if not group.strategicStrikeAssemblyAt or tostring(group.strategicStrikeAssemblyBaseId or "") ~= tostring(activity.targetBaseId or "") then group.strategicStrikeAssemblyAt = worldAge; changed = true end
        if group.strategicStrikeAssemblyBaseId ~= activity.targetBaseId then group.strategicStrikeAssemblyBaseId = activity.targetBaseId; changed = true end
    elseif group.strategicStrikeAssemblyAt ~= nil and activity.type ~= "AttackBase" and activity.type ~= "SiegeBase" then
        group.strategicStrikeAssemblyAt = nil; group.strategicStrikeAssemblyBaseId = nil; changed = true
    end
    if activity.type == "AttackBase" or activity.type == "SiegeBase" then group.strategicFrontOrder = true end
    group.strategicActivityUpdatedAt = worldAge

    if type(group.members) == "table" then
        for _, member in pairs(group.members) do
            if type(member) == "table" then
                member.strategicActivityId = group.strategicActivityId
                member.strategicActivityType = group.strategicActivityType
                member.strategicActivityState = group.strategicActivityState
                member.strategicPlanKind = group.strategicPlanKind
                member.strategicManeuverRole = group.strategicManeuverRole
                member.strategicStrikeReady = group.strategicStrikeReady
                member.targetBaseId = group.targetBaseId
                member.supplyLineState = group.supplyLineState
                member.logisticsBaseId = group.logisticsBaseId
                if activity.type == "DefendBase" or activity.type == "ReinforceBase" or activity.type == "RetreatToBase" then
                    member.homeBaseZoneType = member.homeBaseZoneType or "guard"
                    member.baseZoneType = member.baseZoneType or member.homeBaseZoneType
                elseif activity.type == "AmbushRoad" then
                    member.roadBias = true
                    member.preferRoads = true
                    member.tacticalRole = member.tacticalRole or "road_guard"
                end
            end
        end
    end

    gmd.VirtualGroups[tostring(groupId or group.id)] = group
    if changed and type(gmd.DebugMapMarkers) == "table" and NPCWorldDirectorBridge.BuildVirtualGroupUpdateMarker then
        local marker = NPCWorldDirectorBridge.BuildVirtualGroupUpdateMarker(gmd, tostring(groupId or group.id), group)
        gmd.DebugMapMarkers[tostring(groupId or group.id)] = marker
        NPCWorldDirectorBridge.SendDebugMapUpdate(marker)
    end
    if changed then
        NPCWorldDirectorBridge.BehaviorLog(director, "activity_assigned", {groupId=tostring(groupId or group.id), side=side, activity=activity.type, plan=activity.strategicPlanKind, role=activity.strategicManeuverRole, targetBaseId=activity.targetBaseId, targetGroupId=activity.targetGroupId, x=math.floor(tonumber(activity.x) or 0), y=math.floor(tonumber(activity.y) or 0), readiness=wd_groupReadiness(group), supply=activity.logisticsSupply, ammo=activity.logisticsAmmo, morale=activity.logisticsMorale})
    end
    return changed
end

function NPCWorldDirectorBridge.CleanupStrategicActivities(director, gmd, worldAge)
    local activities = NPCWorldDirectorBridge.EnsureStrategicActivityData(gmd)
    if not activities then return false end
    local ttl = tonumber(director.STRATEGIC_ACTIVITY_INACTIVE_TTL_HOURS) or 6.0
    local changed = false
    for id, activity in pairs(activities) do
        if type(activity) ~= "table" or (activity.active == false and worldAge - (tonumber(activity.updatedAt) or worldAge) > ttl) then
            activities[id] = nil
            local markerId = "SA_" .. tostring(id)
            if type(gmd.DebugMapMarkers) == "table" and gmd.DebugMapMarkers[markerId] then
                gmd.DebugMapMarkers[markerId] = nil
                NPCWorldDirectorBridge.SendDebugMapRemove(markerId)
            end
            changed = true
        elseif type(activity) == "table" then
            activity.active = false
            activity.assignedGroups = {}
        end
    end
    return changed
end

function NPCWorldDirectorBridge.UpdateStrategicActivityGraph(director, gmd, worldAge)
    if not (director and director.STRATEGIC_ACTIVITY_GRAPH_ENABLED ~= false and gmd and type(gmd.VirtualGroups) == "table") then return false end
    gmd.WorldDirector = gmd.WorldDirector or {}
    local wd = gmd.WorldDirector

    local startupAt = tonumber(wd.strategicActivityStartupAt)
    if not startupAt then
        startupAt = worldAge
        wd.strategicActivityStartupAt = startupAt
        wd.strategicActivityReadyAt = worldAge + (tonumber(director.STRATEGIC_ACTIVITY_STARTUP_DELAY_HOURS) or 0.10)
        wd.strategicActivityCursor = 1
        wd.lastStrategicActivityUpdate = worldAge
        return false
    end

    local readyAt = tonumber(wd.strategicActivityReadyAt) or startupAt
    if worldAge < readyAt then return false end

    local last = tonumber(wd.lastStrategicActivityUpdate) or 0
    local interval = tonumber(director.STRATEGIC_ACTIVITY_UPDATE_HOURS) or 0.18
    if last > 0 and worldAge - last < interval then return false end
    wd.lastStrategicActivityUpdate = worldAge

    local changed = NPCWorldDirectorBridge.CleanupStrategicActivities(director, gmd, worldAge) or false
    local assigned = 0
    local limit = tonumber(director.STRATEGIC_ACTIVITY_MAX_ASSIGNMENTS_PER_UPDATE) or 6
    local elapsed = math.max(0, worldAge - startupAt)
    local rampHours = tonumber(director.STRATEGIC_ACTIVITY_STARTUP_RAMP_HOURS) or 0.85
    local startupLimit = tonumber(director.STRATEGIC_ACTIVITY_STARTUP_MAX_ASSIGNMENTS) or 2
    local scanLimit = tonumber(director.STRATEGIC_ACTIVITY_SCAN_LIMIT_PER_UPDATE) or 52
    if rampHours > 0 and elapsed < rampHours then
        local ramp = elapsed / rampHours
        limit = math.max(1, math.floor(startupLimit + (limit - startupLimit) * ramp + 0.5))
        scanLimit = tonumber(director.STRATEGIC_ACTIVITY_STARTUP_SCAN_LIMIT) or 28
    end

    local groupIds = {}
    for groupId, _ in pairs(gmd.VirtualGroups or {}) do
        groupIds[#groupIds + 1] = groupId
    end
    table.sort(groupIds, function(a, b) return tostring(a or "") < tostring(b or "") end)
    if #groupIds == 0 then return changed end
    NPCWorldDirectorBridge.RebuildStrategicStrikeContext(director, gmd, groupIds, worldAge)
    NPCWorldDirectorBridge.RebuildStrategicTheatreContext(director, gmd, groupIds, worldAge)

    local cursor = math.floor(tonumber(wd.strategicActivityCursor) or 1)
    if cursor < 1 or cursor > #groupIds then cursor = 1 end
    local scanCount = math.min(#groupIds, math.max(1, math.floor(scanLimit)))
    local candidates = {}
    for offset = 0, scanCount - 1 do
        local index = ((cursor + offset - 1) % #groupIds) + 1
        local groupId = groupIds[index]
        local group = gmd.VirtualGroups[groupId]
        if NPCWorldDirectorBridge.CanAssignStrategicActivity(group) then
            local activity = NPCWorldDirectorBridge.ResolveStrategicActivityForGroup(director, gmd, group, worldAge)
            if activity then
                table.insert(candidates, {groupId=groupId, group=group, activity=activity, priority=activity.priority or wd_activityTypePriority(activity.type)})
            end
        end
    end
    wd.strategicActivityCursor = ((cursor + scanCount - 1) % #groupIds) + 1

    table.sort(candidates, function(a, b)
        if a.priority == b.priority then return tostring(a.groupId or "") < tostring(b.groupId or "") end
        return a.priority < b.priority
    end)
    for _, candidate in ipairs(candidates) do
        if assigned >= limit then break end
        if NPCWorldDirectorBridge.ApplyStrategicActivityToGroup(director, gmd, candidate.groupId, candidate.group, candidate.activity, worldAge) then
            changed = true
            assigned = assigned + 1
        end
    end
    return changed
end

local function wd_randomPercent()
    if ZombRand then return ZombRand(100) end
    return math.random(0, 99)
end

function NPCWorldDirectorBridge.GetStrategicBaseById(gmd, baseId)
    if not (gmd and baseId) then return nil end
    if NPCStrategicAIBridge and NPCStrategicAIBridge.GetBaseById then
        local ok, base = pcall(function() return NPCStrategicAIBridge.GetBaseById(gmd, baseId) end)
        if ok and base then return base end
    end
    for id, base in pairs(gmd.BaseCamps or {}) do
        if tostring(id) == tostring(baseId) or tostring(base and base.id or "") == tostring(baseId) then return base end
    end
    return nil
end

function NPCWorldDirectorBridge.TrimStrategicGroupAfterLoss(group)
    if not group then return 0 end
    local count = tonumber(group.count) or #(group.members or {})
    if count < 0 then count = 0 end
    group.count = count
    if type(group.members) == "table" then
        while #group.members > count do table.remove(group.members) end
    end
    return count
end

function NPCWorldDirectorBridge.ApplyStrategicSiegeAttrition(director, gmd, groupId, group, base, worldAge)
    if not (director and gmd and group and base and group.x and group.y and base.x and base.y) then return false end
    local side = wd_groupSide(group)
    if side ~= "red" and side ~= "green" then return false end
    local defenderSide = base.owner
    if defenderSide ~= "red" and defenderSide ~= "green" then return false end
    if defenderSide == side then return false end

    local dist = NPCWorldDirectorBridge.DistanceToPoint(group, base)
    if dist > (tonumber(director.STRATEGIC_SIEGE_RADIUS) or 110) then return false end
    local tick = tonumber(director.STRATEGIC_SIEGE_TICK_HOURS) or 0.22
    local last = tonumber(group.lastStrategicSiegeTickAt) or 0
    if last > 0 and worldAge - last < tick then return false end
    group.lastStrategicSiegeTickAt = worldAge

    if NPCStrategicAIBridge and NPCStrategicAIBridge.EvaluateGroupCombatPower then
        pcall(function() NPCStrategicAIBridge.EvaluateGroupCombatPower(gmd, group) end)
    end
    if NPCBaseCampServerBridge and NPCBaseCampServerBridge.UpdateVirtualGarrisonPower then
        pcall(function() NPCBaseCampServerBridge.UpdateVirtualGarrisonPower(base, worldAge) end)
    end

    local attackerPower = math.max(1, tonumber(group.strategicPower) or ((tonumber(group.count) or 1) * 18))
    local defenderPower = math.max(1, tonumber(base.virtualGarrisonPower) or tonumber(base.defensePower) or ((tonumber(base.garrisonSize) or 5) * 24))
    local ratio = attackerPower / math.max(1, attackerPower + defenderPower)
    local attackerLoss = 0
    local defenderLoss = 0

    local attackerLossChance = 8 + (1 - ratio) * 58
    local defenderLossChance = 5 + ratio * 52
    if (tonumber(group.ammoReadiness) or 100) < 45 then attackerLossChance = attackerLossChance + 10 end
    if (tonumber(base.ammoReadiness) or 100) < 45 then defenderLossChance = defenderLossChance + 8 end
    if wd_randomPercent() < attackerLossChance then attackerLoss = attackerLoss + 1 end
    if (tonumber(group.count) or 0) > 5 and ratio < 0.42 and wd_randomPercent() < 28 then attackerLoss = attackerLoss + 1 end
    if wd_randomPercent() < defenderLossChance then defenderLoss = defenderLoss + 1 end
    if ratio > 0.62 and wd_randomPercent() < 24 then defenderLoss = defenderLoss + 1 end

    if attackerLoss > 0 then
        local count = math.max(0, (tonumber(group.count) or 0) - attackerLoss)
        group.count = count
        group.siegeCasualties = (tonumber(group.siegeCasualties) or 0) + attackerLoss
        NPCWorldDirectorBridge.TrimStrategicGroupAfterLoss(group)
        if NPCWorldDirectorBridge.RegisterBaseEconomyLoss then NPCWorldDirectorBridge.RegisterBaseEconomyLoss(director, gmd, group.homeBaseId or group.missionOriginBaseId or group.originBaseId, attackerLoss, 0, worldAge) end
        if NPCStrategicAIBridge and NPCStrategicAIBridge.ApplyBattleStress then pcall(function() NPCStrategicAIBridge.ApplyBattleStress(group, attackerLoss) end) end
    end
    if defenderLoss > 0 then
        base.virtualGarrisonLosses = math.max(0, (tonumber(base.virtualGarrisonLosses) or 0) + defenderLoss)
        base.defenseReadiness = math.max(0, (tonumber(base.defenseReadiness) or 70) - defenderLoss * 4)
        base.updatedAt = worldAge
        if NPCWorldDirectorBridge.RegisterBaseEconomyLoss then NPCWorldDirectorBridge.RegisterBaseEconomyLoss(director, gmd, wd_activityBaseId(base), defenderLoss, 0, worldAge) end
        if NPCBaseCampServerBridge and NPCBaseCampServerBridge.UpdateVirtualGarrisonPower then pcall(function() NPCBaseCampServerBridge.UpdateVirtualGarrisonPower(base, worldAge) end) end
        if NPCBaseCampServerBridge and NPCBaseCampServerBridge.SendBaseMarker then pcall(function() NPCBaseCampServerBridge.SendBaseMarker(base) end) end
    end
    if NPCStrategicAIBridge and NPCStrategicAIBridge.ApplyBaseBattleConsumption then
        pcall(function() NPCStrategicAIBridge.ApplyBaseBattleConsumption(gmd, group, tonumber(group.count) or 1, attackerLoss) end)
    end

    local remaining = tonumber(group.count) or 0
    if remaining <= 0 then
        NPCWorldDirectorBridge.BehaviorLog(director, "siege_group_destroyed", {groupId=tostring(groupId or group.id), side=side, baseId=base.id, defender=defenderSide, attackerLoss=attackerLoss, defenderLoss=defenderLoss, ratio=math.floor(ratio * 100 + 0.5)})
        NPCWorldDirectorBridge.RemoveWorldGroup(director, tostring(groupId or group.id), "strategic_siege_lost")
        return true
    end

    if remaining <= (tonumber(director.STRATEGIC_SIEGE_RETREAT_COUNT) or 2) or (tonumber(group.supplyReadiness) or 100) < 35 or (tonumber(group.ammoReadiness) or 100) < 30 then
        local home = NPCWorldDirectorBridge.FindNearestOwnedStrategicBase(gmd, group.x, group.y, side)
        if home then
            group.targetX, group.targetY, group.targetZ = home.x, home.y, home.z or 0
            group.targetBaseId = home.id
            group.targetClass = "retreat_base"
            group.state = "activity_retreat_to_base"
            group.strategicActivityType = "RetreatToBase"
        end
    end

    gmd.VirtualGroups[tostring(groupId or group.id)] = group
    if attackerLoss > 0 or defenderLoss > 0 then
        NPCWorldDirectorBridge.BehaviorLog(director, "siege_tick", {groupId=tostring(groupId or group.id), side=side, baseId=base.id, defender=defenderSide, attackerPower=math.floor(attackerPower + 0.5), defenderPower=math.floor(defenderPower + 0.5), attackerLoss=attackerLoss, defenderLoss=defenderLoss, groupCount=group.count, baseProgress=math.floor((tonumber(base.progress) or 0) + 0.5), ratio=math.floor(ratio * 100 + 0.5)})
    end
    return attackerLoss > 0 or defenderLoss > 0
end

function NPCWorldDirectorBridge.UpdateStrategicSieges(director, gmd, worldAge)
    if not (director and director.STRATEGIC_REALISM_ENABLED ~= false and gmd and type(gmd.VirtualGroups) == "table") then return false end
    local changed = false
    for groupId, group in pairs(gmd.VirtualGroups or {}) do
        if type(group) == "table" and not group.activated and not group.inBattle and (group.strategicActivityType == "SiegeBase" or group.strategicActivityType == "AttackBase" or group.targetClass == "base_capture") and group.targetBaseId then
            local base = NPCWorldDirectorBridge.GetStrategicBaseById(gmd, group.targetBaseId)
            if base then changed = NPCWorldDirectorBridge.ApplyStrategicSiegeAttrition(director, gmd, groupId, group, base, worldAge) or changed end
        end
    end
    return changed
end

function NPCWorldDirectorBridge.CountStrategicActivityTypes(gmd)
    local out = {AttackBase=0, SiegeBase=0, AssembleStrike=0, DefendBase=0, ReinforceBase=0, RetreatToBase=0, ScoutFront=0, Patrol=0, AmbushRoad=0, EscortConvoy=0, HuntPlayer=0}
    for _, group in pairs(gmd and gmd.VirtualGroups or {}) do
        if type(group) == "table" and not group.activated then
            local key = group.strategicActivityType or "Patrol"
            out[key] = (tonumber(out[key]) or 0) + 1
        end
    end
    return out
end

function NPCWorldDirectorBridge.WriteStrategicBehaviorSnapshot(director, gmd, worldAge)
    if not (director and director.WORLD_BEHAVIOR_LOG_ENABLED ~= false and gmd) then return false end
    gmd.WorldDirector = gmd.WorldDirector or {}
    local interval = tonumber(director.WORLD_BEHAVIOR_SNAPSHOT_HOURS) or 0.50
    local last = tonumber(gmd.WorldDirector.lastBehaviorSnapshotAt) or 0
    if last > 0 and worldAge - last < interval then return false end
    gmd.WorldDirector.lastBehaviorSnapshotAt = worldAge
    local redBases, greenBases, neutralBases = NPCWorldDirectorBridge.CountStrategicWarBases(gmd)
    local redGroups = NPCWorldDirectorBridge.CountStrategicSideGroups(gmd, "red")
    local greenGroups = NPCWorldDirectorBridge.CountStrategicSideGroups(gmd, "green")
    local war = gmd.WorldDirector.strategicWar or {}
    local front = war.front or {}
    local logistics = war.logistics or {}
    local acts = NPCWorldDirectorBridge.CountStrategicActivityTypes(gmd)
    NPCWorldDirectorBridge.BehaviorLog(director, "strategic_snapshot", {redBases=redBases, greenBases=greenBases, neutralBases=neutralBases, redGroups=redGroups, greenGroups=greenGroups, frontX=front.x, frontY=front.y, redSupply=logistics.red and logistics.red.supply, greenSupply=logistics.green and logistics.green.supply, redAmmo=logistics.red and logistics.red.ammo, greenAmmo=logistics.green and logistics.green.ammo, attack=acts.AttackBase, siege=acts.SiegeBase, defend=acts.DefendBase, reinforce=acts.ReinforceBase, retreat=acts.RetreatToBase, scout=acts.ScoutFront, patrol=acts.Patrol, ambush=acts.AmbushRoad, assemble=acts.AssembleStrike})
    return true
end

function NPCWorldDirectorBridge.UpdateStrategicWar(director, gmd, worldAge)
    local changed = NPCWorldDirectorBridge.EnsureStrategicWarState(director, gmd, worldAge) or false
    changed = NPCWorldDirectorBridge.UpdateBaseEconomy(director, gmd, worldAge) or changed
    changed = NPCWorldDirectorBridge.UpdateStrategicLogistics(director, gmd, worldAge) or changed
    changed = NPCWorldDirectorBridge.ApplyStrategicFrontOrders(director, gmd, worldAge) or changed
    changed = NPCWorldDirectorBridge.EnsureStrategicFrontPressure(director, gmd, worldAge) or changed
    changed = NPCWorldDirectorBridge.UpdateStrategicActivityGraph(director, gmd, worldAge) or changed
    changed = NPCWorldDirectorBridge.UpdateStrategicSieges(director, gmd, worldAge) or changed
    NPCWorldDirectorBridge.WriteStrategicBehaviorSnapshot(director, gmd, worldAge)
    return changed
end

function NPCWorldDirectorBridge.CreateRoadPatrol(director, hostile, force, pointOverride, targetOverride, encounterId)
    if type(director) ~= "table" or not director.EnsureData then return false end
    local gmd = director.EnsureData()
    if not gmd or not gmd.WorldDirector or not gmd.WorldDirector.enabled then return false end
    gmd.VirtualGroups = gmd.VirtualGroups or {}
    gmd.DebugMapMarkers = gmd.DebugMapMarkers or {}
    if NPCWorldDirectorBridge.GetAnyRoadPatrolCount(director) >= (tonumber(director.MAX_ROAD_PATROLS) or 0) then return false end
    if not force then
        local chance = math.max(8, math.floor((tonumber(director.SPAWN_CHANCE_PER_TEN_MIN) or 0) * 0.6))
        if ZombRand(101) > chance then return false end
    end

    local point = pointOverride or (director.GetRandomRoadPoint and director.GetRandomRoadPoint())
    if not point or not point.x or not point.y then return false end

    local target = targetOverride
        or (director.GetNearbyRoadPoint and director.GetNearbyRoadPoint(point.x, point.y, director.ROAD_PATROL_TARGET_RADIUS))
        or (director.GetNearbyPreferredPoint and director.GetNearbyPreferredPoint(point.x, point.y, director.VIRTUAL_TARGET_RADIUS))
    local stepTarget = target
    if target and NPCRoadNavBridge and NPCRoadNavBridge.FindNearbyWorldRoadStepToward then
        stepTarget = NPCRoadNavBridge.FindNearbyWorldRoadStepToward(point.x, point.y, target.x, target.y, director.ROAD_PATROL_VIRTUAL_STEP_RADIUS, director.VIRTUAL_TARGET_ATTEMPTS) or target
    end

    local worldAge = getGameTime and getGameTime():getWorldAgeHours() or 0
    local daysPassed = worldAge / 24
    local waveData = director.GetWaveDataForDay and director.GetWaveDataForDay(daysPassed) or nil
    local wave = NPCWorldDirectorBridge.Choice(waveData) or {groupSize=4, clanId=1, hasPistolChance=25, pistolMagCount=2, hasRifleChance=10, rifleMagCount=1}
    local event = {hostile = hostile == true, program = {name="Raider", stage="Prepare"}}
    local mercenaryPatrol = (not event.hostile) and NPCMercenaryContract and NPCMercenaryContract.RollBlueRoadPatrol and NPCMercenaryContract.RollBlueRoadPatrol()
    local patrolSide = mercenaryPatrol and "blue" or (event.hostile and "red" or "green")
    if mercenaryPatrol then event.program = {name="Looter", stage="Prepare"} end

    local originBase = nil
    if director.BASE_OWNED_GLOBAL_GROUPS_SPAWN_ENABLED ~= false and not mercenaryPatrol and not pointOverride and (patrolSide == "red" or patrolSide == "green") then
        originBase = NPCWorldDirectorBridge.SelectBaseOwnedSpawnBase(gmd, patrolSide, point)
        local staging = originBase and NPCWorldDirectorBridge.MakeBaseOwnedStagingPoint(director, originBase, true) or nil
        if staging then
            point = staging
            target = targetOverride
                or (NPCWorldDirectorBridge.GetNearbyRoadPoint and NPCWorldDirectorBridge.GetNearbyRoadPoint(director, point.x, point.y, director.ROAD_PATROL_TARGET_RADIUS))
                or (NPCWorldDirectorBridge.GetNearbyPreferredPoint and NPCWorldDirectorBridge.GetNearbyPreferredPoint(director, point.x, point.y, director.VIRTUAL_TARGET_RADIUS))
            stepTarget = target
            if target and NPCRoadNavBridge and NPCRoadNavBridge.FindNearbyWorldRoadStepToward then
                stepTarget = NPCRoadNavBridge.FindNearbyWorldRoadStepToward(point.x, point.y, target.x, target.y, director.ROAD_PATROL_VIRTUAL_STEP_RADIUS, director.VIRTUAL_TARGET_ATTEMPTS) or target
            end
        end
    end

    local nextId = tonumber(gmd.WorldDirector.nextGroupId) or 1
    local groupId = "RP" .. tostring(nextId)
    gmd.WorldDirector.nextGroupId = nextId + 1

    local groupSize = NPCWorldDirectorBridge.ClampGroupSize(wave.groupSize, 2, 7)
    if groupSize > 3 then groupSize = 3 + ZombRand(math.max(1, groupSize - 2)) end

    local members = {}
    for i=1, groupSize do
        local member = director.MakeNPCFromWave and director.MakeNPCFromWave(wave) or nil
        if type(member) ~= "table" then member = {} end
        if NPCIdentityBridge and NPCIdentityBridge.NewUID then
            member.uid = member.uid or NPCIdentityBridge.NewUID(gmd)
            member.persistentId = member.persistentId or member.uid
        end
        member.worldGroupId = groupId
        member.groupId = groupId
        member.memberIndex = i
        member.roadPatrol = true
        member.roadBias = true
        member.preferRoads = true
        member.patrolColor = patrolSide
        member.factionSide = patrolSide
        member.faction = patrolSide
        member.side = patrolSide
        if mercenaryPatrol and NPCMercenaryContract and NPCMercenaryContract.ApplyEliteToMember then
            NPCMercenaryContract.ApplyEliteToMember(member)
        end
        member.roadEncounterId = encounterId
        member.accuracyBoost = tonumber(member.accuracyBoost) or 1
        if member.accuracyBoost <= 0 then member.accuracyBoost = 1 end
        table.insert(members, member)
    end

    local group = {
        id = groupId,
        x = point.x,
        y = point.y,
        z = point.z or 0,
        clanId = wave.clanId,
        count = #members,
        hostile = event.hostile,
        program = event.program,
        members = members,
        virtual = true,
        activated = false,
        createdAt = worldAge,
        updatedAt = worldAge,
        state = mercenaryPatrol and "blue_mercenary_patrol" or (event.hostile and "red_road_patrol" or "green_road_patrol"),
        spawnClass = "road",
        zoneScore = point.zoneScore or 0,
        urbanAffinity = point.urbanAffinity or 0,
        directorBias = point.directorBias or target and target.directorBias or stepTarget and stepTarget.directorBias,
        directorBiasReason = point.directorBiasReason or target and target.directorBiasReason or stepTarget and stepTarget.directorBiasReason,
        routeX = target and target.x or point.x,
        routeY = target and target.y or point.y,
        routeZ = target and target.z or 0,
        targetX = stepTarget and stepTarget.x or point.x,
        targetY = stepTarget and stepTarget.y or point.y,
        targetZ = stepTarget and stepTarget.z or 0,
        targetClass = "road",
        speed = mercenaryPatrol and ((tonumber(director.BLUE_MERCENARY_PATROL_MOVE_SPEED) or 34) + ZombRand(10)) or ((tonumber(director.VIRTUAL_MOVE_SPEED_TILES_PER_HOUR) or 0) + 40 + ZombRand(45)),
        roadPatrol = true,
        roadBias = true,
        patrolColor = patrolSide,
        factionSide = patrolSide,
        faction = patrolSide,
        side = patrolSide,
        mercenary = mercenaryPatrol == true,
        mercenaryElite = mercenaryPatrol == true,
        hireable = mercenaryPatrol == true,
        recruitable = mercenaryPatrol == true,
        blueMercenaryRouteAt = mercenaryPatrol and worldAge or nil,
        blueMercenaryBattleGraceUntil = mercenaryPatrol and (worldAge + (tonumber(director.BLUE_MERCENARY_PATROL_BATTLE_GRACE_HOURS) or 4.0)) or nil,
        blueMercenaryMapDwellUntil = mercenaryPatrol and (worldAge + (tonumber(director.BLUE_MERCENARY_PATROL_MAP_DWELL_HOURS) or 5.0)) or nil,
        encounterId = encounterId,
        inBattle = false,
        battleId = nil,
        enemyGroupId = nil,
        battleCasualties = 0,
        baseOwnedGlobalSquad = originBase ~= nil,
        originBaseId = originBase and wd_activityBaseId(originBase) or nil,
        homeBaseId = originBase and wd_activityBaseId(originBase) or nil,
        homeBaseOwner = originBase and wd_activityBaseOwner(originBase) or nil,
        routeOwnerBaseId = originBase and wd_activityBaseId(originBase) or nil,
        baseOwnedRole = originBase and "road_patrol" or nil
    }

    if mercenaryPatrol and NPCMercenaryContract and NPCMercenaryContract.ApplyEliteToGroup then
        NPCMercenaryContract.ApplyEliteToGroup(group)
    end
    if NPCStrategicAIBridge and NPCStrategicAIBridge.EnsureGroupBase then NPCStrategicAIBridge.EnsureGroupBase(gmd, group) end
    if NPCWorldDirectorBridge.EnsureBaseOwnedGroup then NPCWorldDirectorBridge.EnsureBaseOwnedGroup(director, gmd, group, worldAge, "road_patrol_created") end
    if NPCWorldDirectorBridge.TryConsumeBaseEconomyForGroup and originBase then
        NPCWorldDirectorBridge.TryConsumeBaseEconomyForGroup(director, gmd, originBase, group, "road_patrol", worldAge)
    end
    if NPCBaseSupplyServer and NPCBaseSupplyServer.ApplyGearToGroup and group.homeBaseId then
        local home = NPCStrategicAIBridge and NPCStrategicAIBridge.GetBaseById and NPCStrategicAIBridge.GetBaseById(gmd, group.homeBaseId) or nil
        if home then NPCBaseSupplyServer.ApplyGearToGroup(home, group) end
    end
    if NPCStrategicAIBridge and NPCStrategicAIBridge.EvaluateGroupCombatPower then NPCStrategicAIBridge.EvaluateGroupCombatPower(gmd, group) end

    gmd.VirtualGroups[groupId] = group
    gmd.WorldDirector.lastSpawn = worldAge
    if NPCIdentityBridge and NPCIdentityBridge.TouchVirtualGroup then NPCIdentityBridge.TouchVirtualGroup(gmd, group) end
    if NPCPersistentNPCBridge and NPCPersistentNPCBridge.RegisterGroup then NPCPersistentNPCBridge.RegisterGroup(gmd, group) end

    local namePrefix = mercenaryPatrol and "Blue Mercenaries " or (event.hostile and "Red Road Patrol " or "Green Road Patrol ")
    local marker = NPCWorldDirectorBridge.BuildRoadPatrolMarker(director, gmd, group, namePrefix)
    if marker then
        gmd.DebugMapMarkers[groupId] = marker
        NPCWorldDirectorBridge.SendDebugMapUpdate(marker)
    end
    NPCWorldDirectorBridge.Log(director, "[NPCWorldDirector] Created " .. tostring(group.patrolColor) .. " road patrol " .. tostring(groupId) .. " at " .. tostring(group.x) .. "," .. tostring(group.y))
    if TransmitNPCModData and not director._suppressWorldDirectorTransmit then TransmitNPCModData() end
    return group
end

function NPCWorldDirectorBridge.UpdateRoadPatrolMarker(director, gmd, group)
    if not gmd or not group or not group.id then return end
    gmd.DebugMapMarkers = gmd.DebugMapMarkers or {}
    local prefix = group.hostile and "Red Road Patrol " or "Green Road Patrol "
    if group.inBattle then prefix = group.hostile and "Battle: Red Road Patrol " or "Battle: Green Road Patrol " end
    local marker = NPCWorldDirectorBridge.BuildRoadPatrolMarker(director, gmd, group, prefix)
    if not marker then return end
    gmd.DebugMapMarkers[group.id] = marker
    NPCWorldDirectorBridge.SendDebugMapUpdate(marker)
end

function NPCWorldDirectorBridge.CreateRoadPatrolEncounterPair(director, force)
    if type(director) ~= "table" or not director.EnsureData then return false end
    local gmd = director.EnsureData()
    if not gmd or not gmd.WorldDirector then return false end
    if NPCWorldDirectorBridge.GetAnyRoadPatrolCount(director) + 2 > (tonumber(director.MAX_ROAD_PATROLS) or 0) then return false end

    local pointA = director.GetRandomRoadPoint and director.GetRandomRoadPoint() or nil
    if not pointA then return false end

    local pointB = nil
    local minDistance = director.ROAD_PATROL_ENCOUNTER_MIN_DISTANCE or 180
    local maxDistance = director.ROAD_PATROL_ENCOUNTER_MAX_DISTANCE or 420
    for _=1, 8 do
        local candidate = director.GetNearbyRoadPoint and director.GetNearbyRoadPoint(pointA.x, pointA.y, maxDistance) or nil
        if candidate then
            local d = NPCWorldDirectorBridge.Dist(pointA.x, pointA.y, candidate.x, candidate.y)
            if d >= minDistance and d <= maxDistance then
                pointB = candidate
                break
            elseif not pointB then
                pointB = candidate
            end
        end
    end
    if not pointB then return false end

    local encounterId = "RPE" .. tostring(gmd.WorldDirector.nextGroupId or 1)
    local red = NPCWorldDirectorBridge.CreateRoadPatrol(director, true, true, pointA, pointB, encounterId)
    if not red then return false end
    local green = NPCWorldDirectorBridge.CreateRoadPatrol(director, false, true, pointB, pointA, encounterId)
    if not green then
        if gmd.VirtualGroups then gmd.VirtualGroups[red.id] = nil end
        if gmd.DebugMapMarkers then gmd.DebugMapMarkers[red.id] = nil end
        NPCWorldDirectorBridge.SendDebugMapRemove(red.id)
        return false
    end

    red.enemyGroupId = green.id
    green.enemyGroupId = red.id
    red.routeX, red.routeY, red.routeZ = pointB.x, pointB.y, pointB.z or 0
    green.routeX, green.routeY, green.routeZ = pointA.x, pointA.y, pointA.z or 0
    for _, member in pairs(red.members or {}) do
        member.enemyGroupId = green.id
        member.battleEnemyGroupId = green.id
    end
    for _, member in pairs(green.members or {}) do
        member.enemyGroupId = red.id
        member.battleEnemyGroupId = red.id
    end
    gmd.VirtualGroups[red.id] = red
    gmd.VirtualGroups[green.id] = green
    NPCWorldDirectorBridge.UpdateRoadPatrolMarker(director, gmd, red)
    NPCWorldDirectorBridge.UpdateRoadPatrolMarker(director, gmd, green)
    if TransmitNPCModData and not director._suppressWorldDirectorTransmit then TransmitNPCModData() end
    return red, green
end

function NPCWorldDirectorBridge.EnsureRoadPatrols(director, force, budget)
    if type(director) ~= "table" then return false end
    if director.SP_BOOTSTRAP_GATE_VIRTUAL_GROUPS ~= false then
        local gate, retry, reason = npc_wd_shouldBootstrapGate(director, force and "road_patrol_bootstrap" or "road_patrol_growth")
        if gate then npc_wd_recordBootstrapGate(force and "road_patrol_bootstrap" or "road_patrol_growth", retry, reason); return false end
    end
    local redTarget = tonumber(director.STARTUP_ROAD_PATROLS_RED) or 0
    local greenTarget = tonumber(director.STARTUP_ROAD_PATROLS_GREEN) or 0
    local redCount = NPCWorldDirectorBridge.GetRoadPatrolCount(director, true)
    local greenCount = NPCWorldDirectorBridge.GetRoadPatrolCount(director, false)
    local changed = false
    local budgetLeft = tonumber(budget)

    local function consumeBudget()
        if budgetLeft == nil then return true end
        if budgetLeft <= 0 then return false end
        budgetLeft = budgetLeft - 1
        return true
    end

    while redCount < redTarget and greenCount < greenTarget and consumeBudget() do
        local red, green = NPCWorldDirectorBridge.CreateRoadPatrolEncounterPair(director, true)
        if not red or not green then break end
        redCount = redCount + 1
        greenCount = greenCount + 1
        changed = true
    end
    while redCount < redTarget and consumeBudget() do
        local group = NPCWorldDirectorBridge.CreateRoadPatrol(director, true, true)
        if not group then break end
        redCount = redCount + 1
        changed = true
    end
    while greenCount < greenTarget and consumeBudget() do
        local group = NPCWorldDirectorBridge.CreateRoadPatrol(director, false, true)
        if not group then break end
        greenCount = greenCount + 1
        changed = true
    end

    local encounterTarget = tonumber(director.STARTUP_ROAD_PATROL_ENCOUNTERS) or 0
    while NPCWorldDirectorBridge.GetRoadPatrolEncounterCount(director) < encounterTarget
        and NPCWorldDirectorBridge.GetAnyRoadPatrolCount(director) + 2 <= (tonumber(director.MAX_ROAD_PATROLS) or 0)
        and consumeBudget() do
        local red, green = NPCWorldDirectorBridge.CreateRoadPatrolEncounterPair(director, true)
        if not red or not green then break end
        changed = true
    end

    if not force and NPCWorldDirectorBridge.GetAnyRoadPatrolCount(director) < (tonumber(director.MAX_ROAD_PATROLS) or 0) then
        if ZombRand(101) < 8 then
            local red, green = NPCWorldDirectorBridge.CreateRoadPatrolEncounterPair(director, false)
            if red and green then
                changed = true
            else
                changed = NPCWorldDirectorBridge.CreateRoadPatrol(director, ZombRand(2) == 0, false) ~= false or changed
            end
        end
    end
    return changed
end


-- Stage 54: neutral road-patrol virtual battle backend.
-- This keeps the historical legacy world-director entry points as wrappers while
-- moving virtual battle state, damage ticks and battle-pair materialization here.

function NPCWorldDirectorBridge.RoadBattleId(a, b)
    a = tostring(a or "")
    b = tostring(b or "")
    if a < b then return "RB" .. a .. "_" .. b end
    return "RB" .. b .. "_" .. a
end

function NPCWorldDirectorBridge.RoadBattleGridSize(director)
    local radius = tonumber(director.ROAD_PATROL_BATTLE_RADIUS) or 125
    local configured = tonumber(director.ROAD_PATROL_BATTLE_GRID_SIZE) or 140
    if configured < radius then configured = radius end
    if configured < 32 then configured = 32 end
    return configured
end

function NPCWorldDirectorBridge.RoadBattleBucketKey(x, y, cellSize)
    local bx = math.floor((tonumber(x) or 0) / cellSize)
    local by = math.floor((tonumber(y) or 0) / cellSize)
    return tostring(bx) .. ":" .. tostring(by), bx, by
end

function NPCWorldDirectorBridge.BuildRoadBattleIndex(director, gmd)
    local cellSize = NPCWorldDirectorBridge.RoadBattleGridSize(director)
    local buckets = {}
    local ids = {}

    for groupId, group in pairs(gmd.VirtualGroups or {}) do
        if group and not group.activated and not group.inBattle and (tonumber(group.count) or 0) > 0 and group.x and group.y then
            local id = tostring(groupId)
            local key = NPCWorldDirectorBridge.RoadBattleBucketKey(group.x, group.y, cellSize)
            local bucket = buckets[key]
            if not bucket then
                bucket = {}
                buckets[key] = bucket
            end
            bucket[#bucket + 1] = id
            ids[#ids + 1] = id
        end
    end

    return buckets, ids, cellSize
end

function NPCWorldDirectorBridge.TrimGroupMembers(group)
    if not group then return 0 end
    if type(group.members) ~= "table" then
        group.members = {}
    end
    local count = tonumber(group.count) or #group.members or 0
    if count < 0 then count = 0 end
    while #group.members > count do
        table.remove(group.members)
    end
    group.count = count
    return count
end

function NPCWorldDirectorBridge.AreRoadPatrolEnemies(_director, a, b)
    if not a or not b then return false end
    if a.activated or b.activated then return false end
    if (tonumber(a.count) or 0) <= 0 or (tonumber(b.count) or 0) <= 0 then return false end

    local worldAge = wd_worldAgeHoursSafe()
    if NPCWorldDirectorBridge.IsRecruitableBlueMercenaryPatrol(a) and worldAge < (tonumber(a.blueMercenaryBattleGraceUntil) or 0) then return false end
    if NPCWorldDirectorBridge.IsRecruitableBlueMercenaryPatrol(b) and worldAge < (tonumber(b.blueMercenaryBattleGraceUntil) or 0) then return false end

    local sideA = NPCStrategicAIBridge and NPCStrategicAIBridge.GetGroupSide and NPCStrategicAIBridge.GetGroupSide(a) or (a.hostile and "red" or "green")
    local sideB = NPCStrategicAIBridge and NPCStrategicAIBridge.GetGroupSide and NPCStrategicAIBridge.GetGroupSide(b) or (b.hostile and "red" or "green")
    if sideA and sideB and sideA ~= sideB then return true end
    return a.hostile ~= b.hostile or (a.patrolColor and b.patrolColor and a.patrolColor ~= b.patrolColor)
end

function NPCWorldDirectorBridge.StartRoadPatrolBattle(director, gmd, a, b, worldAge)
    if director and director.SP_BOOTSTRAP_GATE_ROAD_BATTLES ~= false then
        local gate, retry, reason = npc_wd_shouldBootstrapGate(director, "road_battle_start")
        if gate then npc_wd_recordBootstrapGate("road_battle_start", retry, reason); return false end
    end
    if not NPCWorldDirectorBridge.AreRoadPatrolEnemies(director, a, b) then return false end

    local battleId = NPCWorldDirectorBridge.RoadBattleId(a.id, b.id)
    gmd.WorldDirector = gmd.WorldDirector or {}
    gmd.WorldDirector.roadBattlePairCooldowns = gmd.WorldDirector.roadBattlePairCooldowns or {}
    local lastPairBattle = tonumber(gmd.WorldDirector.roadBattlePairCooldowns[battleId]) or 0
    local reengageCooldown = tonumber(director.ROAD_PATROL_BATTLE_REENGAGE_COOLDOWN_HOURS) or 0
    if lastPairBattle > 0 and reengageCooldown > 0 and worldAge - lastPairBattle < reengageCooldown then return false end
    gmd.WorldDirector.roadBattlePairCooldowns[battleId] = worldAge
    a.preBattleTargetX = a.targetX
    a.preBattleTargetY = a.targetY
    a.preBattleTargetZ = a.targetZ
    a.preBattleTargetClass = a.targetClass
    b.preBattleTargetX = b.targetX
    b.preBattleTargetY = b.targetY
    b.preBattleTargetZ = b.targetZ
    b.preBattleTargetClass = b.targetClass
    a.inBattle = true
    b.inBattle = true
    a.battleId = battleId
    b.battleId = battleId
    a.enemyGroupId = b.id
    b.enemyGroupId = a.id
    a.state = "road_battle"
    b.state = "road_battle"
    a.lastBattleAt = worldAge
    b.lastBattleAt = worldAge
    a.targetX, a.targetY = a.x, a.y
    b.targetX, b.targetY = b.x, b.y
    a.targetClass = "battle_hold"
    b.targetClass = "battle_hold"
    if NPCStrategicAIBridge and NPCStrategicAIBridge.EvaluateGroupCombatPower then
        NPCStrategicAIBridge.EvaluateGroupCombatPower(gmd, a)
        NPCStrategicAIBridge.EvaluateGroupCombatPower(gmd, b)
    end

    for _, member in pairs(a.members or {}) do
        member.battleEnemyGroupId = b.id
        member.enemyGroupId = b.id
        member.virtualBattle = true
    end
    for _, member in pairs(b.members or {}) do
        member.battleEnemyGroupId = a.id
        member.enemyGroupId = a.id
        member.virtualBattle = true
    end

    gmd.VirtualGroups[a.id] = a
    gmd.VirtualGroups[b.id] = b
    NPCWorldDirectorBridge.UpdateRoadPatrolMarker(director, gmd, a)
    NPCWorldDirectorBridge.UpdateRoadPatrolMarker(director, gmd, b)
    NPCWorldDirectorBridge.DirectorEvent(director, "road_battle_started", math.floor(((tonumber(a.x) or 0) + (tonumber(b.x) or 0)) / 2), math.floor(((tonumber(a.y) or 0) + (tonumber(b.y) or 0)) / 2), a.z or b.z or 0, {battleId = battleId, groupA = tostring(a.id), groupB = tostring(b.id)})
    NPCWorldDirectorBridge.BehaviorLog(director, "road_battle_started", {battleId=battleId, groupA=tostring(a.id), groupB=tostring(b.id), sideA=wd_groupSide(a), sideB=wd_groupSide(b), x=math.floor(((tonumber(a.x) or 0) + (tonumber(b.x) or 0)) / 2), y=math.floor(((tonumber(a.y) or 0) + (tonumber(b.y) or 0)) / 2)})
    NPCWorldDirectorBridge.Log(director, NPC_WORLD_DIRECTOR_LOG_PREFIX .. " Road patrol battle started " .. tostring(battleId))
    return true
end

function NPCWorldDirectorBridge.ClearRoadPatrolBattle(director, gmd, group, reason)
    if not group then return false end
    group.inBattle = false
    group.battleId = nil
    group.enemyGroupId = nil
    group.lastBattleAt = nil
    if reason == "battle_won" and group.preBattleTargetX and group.preBattleTargetY then
        group.targetX = group.preBattleTargetX
        group.targetY = group.preBattleTargetY
        group.targetZ = group.preBattleTargetZ or group.targetZ or 0
        group.targetClass = group.preBattleTargetClass or group.targetClass
    elseif group.targetClass == "battle_hold" then
        group.targetX = nil
        group.targetY = nil
        group.targetClass = nil
    end
    group.preBattleTargetX = nil
    group.preBattleTargetY = nil
    group.preBattleTargetZ = nil
    group.preBattleTargetClass = nil
    group.state = NPCStrategicAIBridge and NPCStrategicAIBridge.ResumeGroupState and NPCStrategicAIBridge.ResumeGroupState(group) or (group.hostile and "red_road_patrol" or "green_road_patrol")
    for _, member in pairs(group.members or {}) do
        member.virtualBattle = false
        member.battleEnemyGroupId = nil
        member.enemyGroupId = nil
    end
    if gmd and group.id then
        gmd.VirtualGroups[group.id] = group
        NPCWorldDirectorBridge.UpdateRoadPatrolMarker(director, gmd, group)
    end
    return true
end

function NPCWorldDirectorBridge.ApplyRoadPatrolBattleDamage(director, group, attacker)
    if not group or not attacker then return 0 end
    local count = tonumber(group.count) or #(group.members or {})
    local attackCount = tonumber(attacker.count) or #(attacker.members or {})
    if count <= 0 or attackCount <= 0 then return 0 end

    local gmd = director.EnsureData and director.EnsureData() or nil
    local casualties = nil
    if NPCProxySimulationBridge and NPCProxySimulationBridge.RollVirtualBattleLoss then
        local okProxy, proxyLoss = pcall(function() return NPCProxySimulationBridge.RollVirtualBattleLoss(group, attacker) end)
        if okProxy and proxyLoss ~= nil then casualties = proxyLoss end
    end
    if casualties == nil and NPCStrategicAIBridge and NPCStrategicAIBridge.RollVirtualBattleLoss then
        casualties = NPCStrategicAIBridge.RollVirtualBattleLoss(gmd, group, attacker)
    end
    if casualties == nil then
        casualties = 0
        local power = attackCount * 18 + ZombRand(34)
        if attacker.hostile then power = power + 4 end
        if attacker.inBattle then power = power + 6 end
        if power >= 52 then casualties = casualties + 1 end
        if count > 3 and power >= 92 and ZombRand(100) < 40 then casualties = casualties + 1 end
    end

    if casualties > count then casualties = count end
    if casualties > 0 then
        group.count = count - casualties
        group.battleCasualties = (tonumber(group.battleCasualties) or 0) + casualties
        NPCWorldDirectorBridge.TrimGroupMembers(group)
    end

    if NPCStrategicAIBridge and NPCStrategicAIBridge.EvaluateGroupCombatPower then
        NPCStrategicAIBridge.EvaluateGroupCombatPower(gmd, group)
        NPCStrategicAIBridge.EvaluateGroupCombatPower(gmd, attacker)
    end

    return casualties
end

function NPCWorldDirectorBridge.RoadPatrolBattleScore(group)
    if not group then return 0 end
    local count = tonumber(group.count) or #(group.members or {}) or 0
    local power = tonumber(group.strategicPower) or 0
    local readiness = tonumber(group.combatReadiness) or tonumber(group.supplyReadiness) or 55
    local morale = tonumber(group.moraleReadiness) or readiness
    local ammo = tonumber(group.ammoReadiness) or readiness
    local score = power
    if score <= 0 then score = count * 22 end
    score = score + count * 8 + readiness * 0.35 + morale * 0.20 + ammo * 0.20
    if group.mercenary or group.mercenaryElite then score = score + 12 end
    if group.homeBaseId then score = score + 6 end
    if ZombRand then score = score + ZombRand(26) else score = score + 13 end
    return score
end

function NPCWorldDirectorBridge.ResolveRoadPatrolBattleDecisive(director, gmd, a, b, battleId, worldAge)
    if not (director and gmd and a and b and a.id and b.id) then return false end

    local scoreA = NPCWorldDirectorBridge.RoadPatrolBattleScore(a)
    local scoreB = NPCWorldDirectorBridge.RoadPatrolBattleScore(b)
    local winner, loser = a, b
    if scoreB > scoreA then
        winner, loser = b, a
    elseif scoreA == scoreB and ZombRand and ZombRand(2) == 0 then
        winner, loser = b, a
    end

    local loserMembers = NPCWorldDirectorBridge.Copy(loser.members or {})
    local winnerCount = tonumber(winner.count) or #(winner.members or {}) or 0
    local loserCount = tonumber(loser.count) or #(loser.members or {}) or 0
    local winnerLoss = 0
    if loserCount > 0 then
        winnerLoss = math.floor(loserCount / 3)
        if ZombRand and loserCount > 1 then winnerLoss = winnerLoss + ZombRand(2) end
    end
    if winnerLoss >= winnerCount then winnerLoss = math.max(0, winnerCount - 1) end
    if winnerLoss > 0 then
        winner.count = winnerCount - winnerLoss
        winner.battleCasualties = (tonumber(winner.battleCasualties) or 0) + winnerLoss
        NPCWorldDirectorBridge.TrimGroupMembers(winner)
    end

    loser.count = 0
    loser.battleCasualties = (tonumber(loser.battleCasualties) or 0) + loserCount
    NPCWorldDirectorBridge.CreateBattleRemains(director, gmd, loser, winner, battleId, loserMembers, worldAge)
    NPCWorldDirectorBridge.RemoveWorldGroup(director, loser.id, "road_collision_battle_lost")
    NPCWorldDirectorBridge.ClearRoadPatrolBattle(director, gmd, winner, "battle_won")
    if NPCWorldDirectorBridge.EnsureVirtualTarget then NPCWorldDirectorBridge.EnsureVirtualTarget(director, winner) end
    winner.updatedAt = worldAge
    gmd.VirtualGroups[tostring(winner.id)] = winner
    NPCWorldDirectorBridge.UpdateRoadPatrolMarker(director, gmd, winner)

    NPCWorldDirectorBridge.BehaviorLog(director, "road_collision_battle_resolved", {battleId=battleId, winner=tostring(winner.id), loser=tostring(loser.id), scoreA=math.floor(scoreA), scoreB=math.floor(scoreB), winnerLoss=winnerLoss})
    NPCWorldDirectorBridge.Log(director, NPC_WORLD_DIRECTOR_LOG_PREFIX .. " Road collision battle resolved " .. tostring(battleId) .. " winner=" .. tostring(winner.id) .. " loser=" .. tostring(loser.id))
    return true
end

function NPCWorldDirectorBridge.ProcessRoadPatrolBattlePair(director, gmd, a, b, worldAge, processed)
    if not a or not b or not a.id or not b.id then return false end
    processed = processed or {}
    local battleId = a.battleId or b.battleId or NPCWorldDirectorBridge.RoadBattleId(a.id, b.id)
    if processed[battleId] then return false end
    processed[battleId] = true

    if not NPCWorldDirectorBridge.AreRoadPatrolEnemies(director, a, b) then
        NPCWorldDirectorBridge.ClearRoadPatrolBattle(director, gmd, a, "not_enemies")
        NPCWorldDirectorBridge.ClearRoadPatrolBattle(director, gmd, b, "not_enemies")
        return true
    end

    local dist = NPCWorldDirectorBridge.Dist(a.x, a.y, b.x, b.y)
    if dist > (director.ROAD_PATROL_BATTLE_KEEP_RADIUS or 170) then
        NPCWorldDirectorBridge.ClearRoadPatrolBattle(director, gmd, a, "separated")
        NPCWorldDirectorBridge.ClearRoadPatrolBattle(director, gmd, b, "separated")
        return true
    end

    local last = math.max(tonumber(a.lastBattleAt) or 0, tonumber(b.lastBattleAt) or 0)
    if worldAge - last < (director.ROAD_PATROL_BATTLE_TICK_HOURS or 0.12) then
        return false
    end

    a.lastBattleAt = worldAge
    b.lastBattleAt = worldAge
    a.state = "road_battle"
    b.state = "road_battle"

    if director.ROAD_PATROL_BATTLE_DECISIVE ~= false then
        return NPCWorldDirectorBridge.ResolveRoadPatrolBattleDecisive(director, gmd, a, b, battleId, worldAge)
    end

    local membersA = NPCWorldDirectorBridge.Copy(a.members or {})
    local membersB = NPCWorldDirectorBridge.Copy(b.members or {})
    local lossA = NPCWorldDirectorBridge.ApplyRoadPatrolBattleDamage(director, a, b)
    local lossB = NPCWorldDirectorBridge.ApplyRoadPatrolBattleDamage(director, b, a)

    if (tonumber(a.count) or 0) <= 0 then
        NPCWorldDirectorBridge.CreateBattleRemains(director, gmd, a, b, battleId, membersA, worldAge)
        NPCWorldDirectorBridge.RemoveWorldGroup(director, a.id, "road_battle_lost")
        NPCWorldDirectorBridge.ClearRoadPatrolBattle(director, gmd, b, "battle_won")
    else
        gmd.VirtualGroups[a.id] = a
        NPCWorldDirectorBridge.UpdateRoadPatrolMarker(director, gmd, a)
    end

    if (tonumber(b.count) or 0) <= 0 then
        NPCWorldDirectorBridge.CreateBattleRemains(director, gmd, b, a, battleId, membersB, worldAge)
        NPCWorldDirectorBridge.RemoveWorldGroup(director, b.id, "road_battle_lost")
        if gmd.VirtualGroups[a.id] then
            NPCWorldDirectorBridge.ClearRoadPatrolBattle(director, gmd, a, "battle_won")
        end
    else
        gmd.VirtualGroups[b.id] = b
        NPCWorldDirectorBridge.UpdateRoadPatrolMarker(director, gmd, b)
    end

    if lossA > 0 or lossB > 0 then
        NPCWorldDirectorBridge.BehaviorLog(director, "road_battle_losses", {battleId=battleId, groupA=tostring(a.id), groupB=tostring(b.id), lossA=lossA, lossB=lossB, countA=a.count, countB=b.count, sideA=wd_groupSide(a), sideB=wd_groupSide(b)})
        NPCWorldDirectorBridge.Log(director, NPC_WORLD_DIRECTOR_LOG_PREFIX .. " Road battle " .. tostring(battleId) .. " losses red/green=" .. tostring(lossA) .. "/" .. tostring(lossB))
    end

    return true
end

function NPCWorldDirectorBridge.UpdateRoadPatrolBattles(director)
    local gmd = director.EnsureData and director.EnsureData() or nil
    if not gmd then return false end
    local worldAge = getGameTime():getWorldAgeHours()
    gmd.WorldDirector = gmd.WorldDirector or {}
    local wd = gmd.WorldDirector
    if not wd.roadBattleStartupAt then
        wd.roadBattleStartupAt = worldAge
        wd.roadBattleReadyAt = worldAge + (tonumber(director.ROAD_PATROL_BATTLE_STARTUP_DELAY_HOURS) or 0.10)
    end

    local changed = false
    local processed = {}

    for groupId, group in pairs(gmd.VirtualGroups) do
        if group and not group.activated and group.inBattle then
            local enemy = group.enemyGroupId and gmd.VirtualGroups[tostring(group.enemyGroupId)] or nil
            if enemy then
                changed = NPCWorldDirectorBridge.ProcessRoadPatrolBattlePair(director, gmd, group, enemy, worldAge, processed) or changed
            else
                changed = NPCWorldDirectorBridge.ClearRoadPatrolBattle(director, gmd, group, "enemy_missing") or changed
            end
        end
    end

    if worldAge < (tonumber(wd.roadBattleReadyAt) or 0) then
        if changed then TransmitNPCModData() end
        return changed
    end

    local buckets, ids, cellSize = NPCWorldDirectorBridge.BuildRoadBattleIndex(director, gmd)
    local checkedPairs = {}
    local started = 0
    local maxStarts = math.max(1, math.floor(tonumber(director.ROAD_PATROL_BATTLE_MAX_STARTS_PER_UPDATE) or 2))

    for i=1, #ids do
        if started >= maxStarts then break end
        local idA = ids[i]
        local a = gmd.VirtualGroups[idA]
        if a and not a.inBattle and a.x and a.y then
            local _, bx, by = NPCWorldDirectorBridge.RoadBattleBucketKey(a.x, a.y, cellSize)
            local battleStarted = false

            for ox=-1, 1 do
                if battleStarted or started >= maxStarts then break end
                for oy=-1, 1 do
                    if battleStarted or started >= maxStarts then break end
                    local bucket = buckets[tostring(bx + ox) .. ":" .. tostring(by + oy)]
                    if bucket then
                        for j=1, #bucket do
                            if started >= maxStarts then break end
                            local idB = bucket[j]
                            if idB ~= idA then
                                local pairId = NPCWorldDirectorBridge.RoadBattleId(idA, idB)
                                if not checkedPairs[pairId] then
                                    checkedPairs[pairId] = true
                                    local b = gmd.VirtualGroups[idB]
                                    if b and not b.inBattle and b.x and b.y and NPCWorldDirectorBridge.AreRoadPatrolEnemies(director, a, b) then
                                        local battleRadius = (a.roadPatrol or b.roadPatrol or a.economyConvoy or b.economyConvoy) and (director.ROAD_PATROL_BATTLE_RADIUS or 110) or 78
                                        local dx = (tonumber(a.x) or 0) - (tonumber(b.x) or 0)
                                        local dy = (tonumber(a.y) or 0) - (tonumber(b.y) or 0)
                                        if dx * dx + dy * dy <= battleRadius * battleRadius then
                                            if NPCWorldDirectorBridge.StartRoadPatrolBattle(director, gmd, a, b, worldAge) then
                                                changed = true
                                                started = started + 1
                                            end
                                            battleStarted = true
                                            break
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if changed then
        TransmitNPCModData()
    end
    return changed
end

function NPCWorldDirectorBridge.MaterializeRoadBattlePair(director, group, enemy, player)
    if not group or not enemy or group.activated or enemy.activated then return false end
    if not player then return false end

    local mx = math.floor(((tonumber(group.x) or 0) + (tonumber(enemy.x) or 0)) / 2)
    local my = math.floor(((tonumber(group.y) or 0) + (tonumber(enemy.y) or 0)) / 2)
    local mz = group.z or enemy.z or 0
    local road = NPCRoadNavBridge and NPCRoadNavBridge.FindLoadedRoadAround and NPCRoadNavBridge.FindLoadedRoadAround(mx, my, mz, 90) or nil
    local cx = road and road.x or mx
    local cy = road and road.y or my
    local dx = (tonumber(enemy.x) or cx + 1) - (tonumber(group.x) or cx)
    local dy = (tonumber(enemy.y) or cy) - (tonumber(group.y) or cy)
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then dx, dy, len = 1, 0, 1 end
    dx = dx / len
    dy = dy / len

    group.x = math.floor(cx - dx * 10)
    group.y = math.floor(cy - dy * 10)
    enemy.x = math.floor(cx + dx * 10)
    enemy.y = math.floor(cy + dy * 10)
    group.targetX, group.targetY = enemy.x, enemy.y
    enemy.targetX, enemy.targetY = group.x, group.y

    local gmd = director.EnsureData and director.EnsureData() or nil
    if not gmd then return false end
    gmd.VirtualGroups[group.id] = group
    gmd.VirtualGroups[enemy.id] = enemy

    local okA = NPCWorldDirectorBridge.MaterializeGroup(director, group, player)
    local okB = false
    if director.MATERIALIZE_BATTLE_PAIR_AS_SINGLE_WAVE then
        NPCWorldDirectorBridge.DeferGroupActivation(director, enemy, "battle_pair_second_wave")
    else
        okB = NPCWorldDirectorBridge.MaterializeGroup(director, enemy, player)
    end
    return okA or okB
end

function NPCWorldDirectorBridge.CreateVirtualGroup(director, force)
    if type(director) ~= "table" or not director.EnsureData then return false end
    if director.SP_BOOTSTRAP_GATE_VIRTUAL_GROUPS ~= false then
        local gate, retry, reason = npc_wd_shouldBootstrapGate(director, force and "virtual_group_bootstrap" or "virtual_group_growth")
        if gate then npc_wd_recordBootstrapGate(force and "virtual_group_bootstrap" or "virtual_group_growth", retry, reason); return false end
    end
    local gmd = director.EnsureData()
    if type(gmd) ~= "table" then return false end
    if type(gmd.WorldDirector) ~= "table" then return false end
    if not gmd.WorldDirector.enabled then return false end

    if type(gmd.VirtualGroups) ~= "table" then gmd.VirtualGroups = {} end
    if NPCWorldDirectorBridge.CountTable(gmd.VirtualGroups) >= (tonumber(director.MAX_VIRTUAL_GROUPS) or 0) then
        return false
    end

    if not force then
        local roll = ZombRand(101)
        if roll > (tonumber(director.SPAWN_CHANCE_PER_TEN_MIN) or 0) then
            return false
        end
    end

    local worldAge = 0
    if getGameTime then
        local ok, value = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok then worldAge = tonumber(value) or 0 end
    end
    local daysPassed = worldAge / 24
    local waveData = director.GetWaveDataForDay and director.GetWaveDataForDay(daysPassed) or nil
    local wave = NPCWorldDirectorBridge.Choice(waveData)
    if not wave then return false end

    local point = director.GetRandomWorldPoint and director.GetRandomWorldPoint() or nil
    if type(point) ~= "table" then return false end

    local event = director.GetProgramForWave and director.GetProgramForWave(wave) or nil
    if type(event) ~= "table" then return false end

    local mercenaryGroup = (not event.hostile) and NPCMercenaryContract and NPCMercenaryContract.RollBlueGroup and NPCMercenaryContract.RollBlueGroup()
    local groupSide = mercenaryGroup and "blue" or (event.hostile and "red" or "green")
    if mercenaryGroup then
        event.program = {name="Looter", stage="Prepare"}
        event.hostile = false
    else
        groupSide = NPCWorldDirectorBridge.BalanceSpawnSideForStrategicWar(director, gmd, event, groupSide)
    end

    local originBase = nil
    if director.BASE_OWNED_GLOBAL_GROUPS_SPAWN_ENABLED ~= false and not mercenaryGroup and (groupSide == "red" or groupSide == "green") then
        originBase = NPCWorldDirectorBridge.SelectBaseOwnedSpawnBase(gmd, groupSide, point)
        local staging = originBase and NPCWorldDirectorBridge.MakeBaseOwnedStagingPoint(director, originBase, true) or nil
        if staging then point = staging end
    end

    local groupId = "WG" .. tostring(gmd.WorldDirector.nextGroupId or 1)
    gmd.WorldDirector.nextGroupId = (tonumber(gmd.WorldDirector.nextGroupId) or 1) + 1

    local groupSize = NPCWorldDirectorBridge.ClampGroupSize(wave.groupSize)
    local members = {}
    for i=1, groupSize do
        local member = NPCWorldDirectorBridge.PrepareVirtualMember(director, gmd, wave, groupId, i, groupSide, mercenaryGroup)
        if member then table.insert(members, member) end
    end
    if #members <= 0 then return false end

    local roamTarget = director.GetNearbyPreferredPoint and director.GetNearbyPreferredPoint(point.x, point.y, director.VIRTUAL_TARGET_RADIUS) or nil

    local group = {
        id = groupId,
        x = point.x,
        y = point.y,
        z = point.z,
        preciseX = tonumber(point.x) or 0,
        preciseY = tonumber(point.y) or 0,
        clanId = wave.clanId,
        count = #members,
        hostile = event.hostile,
        program = event.program,
        members = members,
        virtual = true,
        activated = false,
        createdAt = worldAge,
        updatedAt = worldAge,
        state = mercenaryGroup and "blue_mercenary_group" or "roaming",
        spawnClass = point.spawnClass or "preferred",
        zoneScore = point.zoneScore or 0,
        urbanAffinity = point.urbanAffinity or 0,
        directorBias = roamTarget and roamTarget.directorBias,
        directorBiasReason = roamTarget and roamTarget.directorBiasReason,
        targetX = roamTarget and roamTarget.x or point.x,
        targetY = roamTarget and roamTarget.y or point.y,
        targetZ = roamTarget and roamTarget.z or 0,
        targetClass = roamTarget and roamTarget.spawnClass or "roam",
        speed = mercenaryGroup and ((tonumber(director.BLUE_MERCENARY_PATROL_MOVE_SPEED) or 34) + ZombRand(12)) or ((tonumber(director.VIRTUAL_MOVE_SPEED_TILES_PER_HOUR) or 120) + ZombRand(45)),
        factionSide = groupSide,
        faction = groupSide,
        side = groupSide,
        patrolColor = groupSide,
        mercenary = mercenaryGroup == true,
        mercenaryElite = mercenaryGroup == true,
        hireable = mercenaryGroup == true,
        recruitable = mercenaryGroup == true,
        blueMercenaryRouteAt = mercenaryGroup and worldAge or nil,
        blueMercenaryBattleGraceUntil = mercenaryGroup and (worldAge + (tonumber(director.BLUE_MERCENARY_PATROL_BATTLE_GRACE_HOURS) or 4.0)) or nil,
        blueMercenaryMapDwellUntil = mercenaryGroup and (worldAge + (tonumber(director.BLUE_MERCENARY_PATROL_MAP_DWELL_HOURS) or 5.0)) or nil,
        roadBias = true,
        baseOwnedGlobalSquad = originBase ~= nil,
        originBaseId = originBase and wd_activityBaseId(originBase) or nil,
        homeBaseId = originBase and wd_activityBaseId(originBase) or nil,
        homeBaseOwner = originBase and wd_activityBaseOwner(originBase) or nil,
        routeOwnerBaseId = originBase and wd_activityBaseId(originBase) or nil
    }

    if mercenaryGroup and NPCMercenaryContract and NPCMercenaryContract.ApplyEliteToGroup then
        NPCMercenaryContract.ApplyEliteToGroup(group)
    end

    NPCWorldDirectorBridge.ApplyVirtualGroupStrategicState(director, gmd, group)
    if NPCWorldDirectorBridge.TryConsumeBaseEconomyForGroup and originBase then
        NPCWorldDirectorBridge.TryConsumeBaseEconomyForGroup(director, gmd, originBase, group, "field", worldAge)
    end

    gmd.VirtualGroups[groupId] = group
    gmd.WorldDirector.lastSpawn = worldAge

    if NPCIdentityBridge and NPCIdentityBridge.TouchVirtualGroup then
        NPCIdentityBridge.TouchVirtualGroup(gmd, group)
    end
    if NPCPersistentNPCBridge and NPCPersistentNPCBridge.RegisterGroup then
        NPCPersistentNPCBridge.RegisterGroup(gmd, group)
    end

    if type(gmd.DebugMapMarkers) ~= "table" then gmd.DebugMapMarkers = {} end
    local marker = NPCWorldDirectorBridge.BuildVirtualGroupMarker(group)
    if marker then
        gmd.DebugMapMarkers[groupId] = marker
        NPCWorldDirectorBridge.SendDebugMapUpdate(marker)
    end

    NPCWorldDirectorBridge.DirectorEvent(director, "virtual_group_created", group.x, group.y, group.z or 0, {
        groupId = groupId,
        count = group.count,
        side = group.side,
        roadPatrol = group.roadPatrol or false,
        mercenary = group.mercenary or false,
        force = force == true
    })
    NPCWorldDirectorBridge.Log(director, NPC_WORLD_DIRECTOR_LOG_PREFIX .. " Created virtual group " .. tostring(groupId) .. " at " .. tostring(group.x) .. "," .. tostring(group.y) .. " class=" .. tostring(group.spawnClass) .. " count=" .. tostring(group.count))

    if TransmitNPCModData and not director._suppressWorldDirectorTransmit then TransmitNPCModData() end
    return group
end

-- Stage 51: neutral materialization backend.
-- Keeps historical legacy world-director public entry points but moves loaded-square
-- search, offscreen entry selection, spawn failure bookkeeping and group materialize
-- execution out of the compatibility facade.

local npc_wd_materializeOffsets = {
    {x=0, y=0}, {x=1, y=0}, {x=-1, y=0}, {x=0, y=1}, {x=0, y=-1},
    {x=1, y=1}, {x=-1, y=1}, {x=1, y=-1}, {x=-1, y=-1},
    {x=2, y=0}, {x=-2, y=0}, {x=0, y=2}, {x=0, y=-2}
}

function NPCWorldDirectorBridge.MaterializeMemberOffset(index)
    return npc_wd_materializeOffsets[((tonumber(index) or 1) - 1) % #npc_wd_materializeOffsets + 1]
end

function NPCWorldDirectorBridge.GroupPersistentIds(group)
    local ids = {}
    if type(group) ~= "table" or type(group.members) ~= "table" then return ids end
    for _, member in ipairs(group.members) do
        local pid = member and (member.persistentId or member.uid)
        if pid ~= nil then table.insert(ids, tostring(pid)) end
    end
    return ids
end

function NPCWorldDirectorBridge.IsSquareUsable(_director, square)
    if not square then return false end

    local ok, result = pcall(function() return square:isFree(false) end)
    if ok and not result then return false end

    -- Do not call square:isWater() here. On PZ 41 MP some builds expose no
    -- matching Lua/Java overload and the engine logs a full stack trace even
    -- inside pcall(). A water square is not a valid materialization point in
    -- normal cells anyway; the floor/free/room/building checks below are safer.

    ok, result = pcall(function() return square:getRoom() end)
    if ok and result then return false end

    ok, result = pcall(function() return square:getBuilding() end)
    if ok and result then return false end

    if SafeHouse and SafeHouse.isSafeHouse then
        ok, result = pcall(function() return SafeHouse.isSafeHouse(square, nil, true) end)
        if ok and result then return false end
    end

    return true
end


function NPCWorldDirectorBridge.IsCompanionLeashSquareUsable(_director, square, playerBuilding)
    if not square then return false end

    local ok, result = pcall(function() return square:isFree(false) end)
    if ok and not result then return false end

    if playerBuilding then
        ok, result = pcall(function() return square:getBuilding() end)
        if (not ok) or result ~= playerBuilding then return false end
    end

    if SafeHouse and SafeHouse.isSafeHouse then
        ok, result = pcall(function() return SafeHouse.isSafeHouse(square, nil, true) end)
        if ok and result and not playerBuilding then return false end
    end

    return true
end

function NPCWorldDirectorBridge.FindLoadedCompanionLeashSquareNear(director, player, x, y, z, radius)
    local cell = getCell and getCell() or nil
    if not (cell and player) then return nil end

    x = math.floor(tonumber(x) or 0)
    y = math.floor(tonumber(y) or 0)
    z = math.floor(tonumber(z) or (player.getZ and player:getZ()) or 0)
    radius = tonumber(radius) or 8
    if radius < 2 then radius = 2 end
    if radius > 18 then radius = 18 end

    local playerSquare = player.getSquare and player:getSquare() or nil
    local playerBuilding = nil
    if playerSquare and playerSquare.getBuilding then
        local ok, building = pcall(function() return playerSquare:getBuilding() end)
        if ok then playerBuilding = building end
    end

    local square = cell:getGridSquare(x, y, z)
    if NPCWorldDirectorBridge.IsCompanionLeashSquareUsable(director, square, playerBuilding) then
        return square
    end

    local px = player.getX and math.floor(tonumber(player:getX()) or x) or x
    local py = player.getY and math.floor(tonumber(player:getY()) or y) or y
    square = cell:getGridSquare(px, py, z)
    if NPCWorldDirectorBridge.IsCompanionLeashSquareUsable(director, square, playerBuilding) then
        return square
    end

    for r = 1, radius do
        for dx = -r, r do
            for dy = -r, r do
                if r == 0 or math.abs(dx) == r or math.abs(dy) == r then
                    square = cell:getGridSquare(px + dx, py + dy, z)
                    if NPCWorldDirectorBridge.IsCompanionLeashSquareUsable(director, square, playerBuilding) then
                        return square
                    end
                end
            end
        end
    end

    return nil
end

function NPCWorldDirectorBridge.FindLoadedSpawnSquareNear(director, x, y, z, radius)
    local cell = getCell and getCell() or nil
    if not cell then return false end

    x = math.floor(tonumber(x) or 0)
    y = math.floor(tonumber(y) or 0)
    z = math.floor(tonumber(z) or 0)
    radius = tonumber(radius) or 24
    if radius < 8 then radius = 8 end
    if radius > 64 then radius = 64 end

    local square = cell:getGridSquare(x, y, z)
    if NPCWorldDirectorBridge.IsSquareUsable(director, square) then
        return square
    end

    for r=1, radius do
        local checks = {
            {x + r, y}, {x - r, y}, {x, y + r}, {x, y - r},
            {x + r, y + r}, {x - r, y + r}, {x + r, y - r}, {x - r, y - r}
        }
        for _, p in ipairs(checks) do
            square = cell:getGridSquare(p[1], p[2], z)
            if NPCWorldDirectorBridge.IsSquareUsable(director, square) then
                return square
            end
        end

        for _=1, 10 do
            local dx = ZombRand(-r, r + 1)
            local dy = ZombRand(-r, r + 1)
            square = cell:getGridSquare(x + dx, y + dy, z)
            if NPCWorldDirectorBridge.IsSquareUsable(director, square) then
                return square
            end
        end
    end

    return false
end

local function npc_wd_norm(dx, dy)
    dx = tonumber(dx) or 0
    dy = tonumber(dy) or 0
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.001 then return nil, nil end
    return dx / len, dy / len
end

local function npc_wd_addDir(dirs, dx, dy)
    local nx, ny = npc_wd_norm(dx, dy)
    if not nx then return end

    for _, d in ipairs(dirs) do
        if math.abs(d.x - nx) < 0.08 and math.abs(d.y - ny) < 0.08 then
            return
        end
    end

    table.insert(dirs, {x=nx, y=ny})
end

function NPCWorldDirectorBridge.PlayerForwardVector(player)
    if not player then return nil, nil end

    local ok, vec = pcall(function() return player:getForwardDirection() end)
    if ok and vec then
        local vx, vy = nil, nil
        ok, vx = pcall(function() return vec:getX() end)
        local okY
        okY, vy = pcall(function() return vec:getY() end)
        if ok and okY then
            local nx, ny = npc_wd_norm(vx, vy)
            if nx then return nx, ny end
        end
    end

    ok, vec = pcall(function() return player:getDir():ToVector() end)
    if ok and vec then
        local vx, vy = nil, nil
        ok, vx = pcall(function() return vec:getX() end)
        local okY
        okY, vy = pcall(function() return vec:getY() end)
        if ok and okY then
            local nx, ny = npc_wd_norm(vx, vy)
            if nx then return nx, ny end
        end
    end

    return nil, nil
end

function NPCWorldDirectorBridge.IsPointAwayFromPlayers(_director, x, y, minDist)
    local playerList = getOnlinePlayers and getOnlinePlayers() or nil
    if not playerList then return true end

    minDist = tonumber(minDist) or 32
    for i=0, playerList:size()-1 do
        local player = playerList:get(i)
        if player and not player:isDead() then
            if NPCWorldDirectorBridge.Dist(x, y, player:getX(), player:getY()) < minDist then
                return false
            end
        end
    end

    return true
end

function NPCWorldDirectorBridge.FindOffscreenMaterializeSquare(director, group, player)
    if not (director and director.OFFSCREEN_MATERIALIZE_ENABLED) then return nil end
    if not group or not player then return nil end

    local px = tonumber(player:getX()) or 0
    local py = tonumber(player:getY()) or 0
    local pz = math.floor(tonumber(player:getZ()) or 0)
    local gx = tonumber(group.x) or px
    local gy = tonumber(group.y) or py
    local gz = math.floor(tonumber(group.z) or pz)

    local minDist = tonumber(director.OFFSCREEN_SPAWN_MIN_DISTANCE) or 48
    local maxDist = tonumber(director.OFFSCREEN_SPAWN_MAX_DISTANCE) or 78
    local safeDist = tonumber(director.OFFSCREEN_SPAWN_SAFE_PLAYER_RADIUS) or 38
    local searchRadius = tonumber(director.OFFSCREEN_SPAWN_SEARCH_RADIUS) or 9

    if maxDist < minDist then maxDist = minDist end

    if NPCWorldDirectorBridge.IsPointAwayFromPlayers(director, gx, gy, minDist) then
        local naturalSquare = nil
        if group.roadPatrol and NPCRoadNavBridge and NPCRoadNavBridge.FindLoadedRoadAround then
            local road = NPCRoadNavBridge.FindLoadedRoadAround(gx, gy, gz, 34)
            naturalSquare = road and road.square or nil
        end
        naturalSquare = naturalSquare or NPCWorldDirectorBridge.FindLoadedSpawnSquareNear(director, gx, gy, gz, searchRadius)
        if naturalSquare and NPCWorldDirectorBridge.IsPointAwayFromPlayers(director, naturalSquare:getX(), naturalSquare:getY(), safeDist) then
            return naturalSquare
        end
    end

    local dirs = {}
    npc_wd_addDir(dirs, gx - px, gy - py)

    local fx, fy = NPCWorldDirectorBridge.PlayerForwardVector(player)
    if fx and fy then
        npc_wd_addDir(dirs, -fx, -fy)
        npc_wd_addDir(dirs, -fy, fx)
        npc_wd_addDir(dirs, fy, -fx)
        npc_wd_addDir(dirs, fx, fy)
    end

    local seed = tostring(group.id or group.encounterId or group.battleId or "0")
    local n = tonumber((string.gsub(seed, "%D", ""))) or ZombRand(1000)
    for i=0, 15 do
        local angle = ((n + i * 73) % 360) * math.pi / 180
        npc_wd_addDir(dirs, math.cos(angle), math.sin(angle))
    end

    for _, dir in ipairs(dirs) do
        local dist = minDist
        while dist <= maxDist do
            local jitterX = ZombRand(-4, 5)
            local jitterY = ZombRand(-4, 5)
            local cx = math.floor(px + dir.x * dist + jitterX)
            local cy = math.floor(py + dir.y * dist + jitterY)
            local square = nil

            if group.roadPatrol and NPCRoadNavBridge and NPCRoadNavBridge.FindLoadedRoadAround then
                local road = NPCRoadNavBridge.FindLoadedRoadAround(cx, cy, pz, 24)
                square = road and road.square or nil
            end

            square = square or NPCWorldDirectorBridge.FindLoadedSpawnSquareNear(director, cx, cy, pz, searchRadius)
            if square and NPCWorldDirectorBridge.IsPointAwayFromPlayers(director, square:getX(), square:getY(), safeDist) then
                return square
            end

            dist = dist + 6
        end
    end

    return nil
end

function NPCWorldDirectorBridge.FindHiredMercenaryLeashSquare(director, player, index)
    if not player then return nil end

    local px = tonumber(player:getX()) or 0
    local py = tonumber(player:getY()) or 0
    local pz = math.floor(tonumber(player:getZ()) or 0)
    local fx, fy = NPCWorldDirectorBridge.PlayerForwardVector(player)
    if not fx then fx, fy = 0, 1 end
    local sx, sy = -fy, fx
    local slot = NPCWorldDirectorBridge.MaterializeMemberOffset(index or 1)
    local x = px - fx * 3 + sx * (tonumber(slot.x) or 0)
    local y = py - fy * 3 + sy * (tonumber(slot.x) or 0)
    x = x + (tonumber(slot.y) or 0) * 0.35
    y = y + (tonumber(slot.y) or 0) * 0.35

    local radius = tonumber(director and director.MERCENARY_FOLLOW_CLOSE_RADIUS) or 8
    local playerSquare = player.getSquare and player:getSquare() or nil
    local playerBuilding = nil
    if playerSquare and playerSquare.getBuilding then
        local ok, building = pcall(function() return playerSquare:getBuilding() end)
        if ok then playerBuilding = building end
    end
    if playerBuilding then
        return NPCWorldDirectorBridge.FindLoadedCompanionLeashSquareNear(director, player, x, y, pz, radius)
            or NPCWorldDirectorBridge.FindLoadedCompanionLeashSquareNear(director, player, px, py, pz, radius)
            or NPCWorldDirectorBridge.FindLoadedSpawnSquareNear(director, x, y, pz, radius)
            or NPCWorldDirectorBridge.FindLoadedSpawnSquareNear(director, px, py, pz, radius)
    end
    return NPCWorldDirectorBridge.FindLoadedSpawnSquareNear(director, x, y, pz, radius)
        or NPCWorldDirectorBridge.FindLoadedSpawnSquareNear(director, px, py, pz, radius)
end

function NPCWorldDirectorBridge.MarkGroupMaterializeFailed(director, group, player, reason)
    if not group or not group.id or not director or not director.EnsureData then return false end

    local gmd = director.EnsureData()
    if type(gmd) ~= "table" then return false end
    if type(gmd.VirtualGroups) ~= "table" then gmd.VirtualGroups = {} end
    if type(gmd.DebugMapMarkers) ~= "table" then gmd.DebugMapMarkers = {} end

    local worldAge = 0
    if getGameTime then
        local ok, value = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok then worldAge = tonumber(value) or 0 end
    end

    group.activated = false
    group.virtual = true
    group.physicalIds = nil
    group.spawnFailed = true
    group.spawnFailCount = (tonumber(group.spawnFailCount) or 0) + 1
    group.spawnFailedAt = worldAge
    group.retryAfter = worldAge + 0.015
    group.lastSpawnFailReason = reason or "unknown"
    group.state = group.inBattle and "road_battle" or "spawn_retry"
    group.updatedAt = worldAge

    if player then
        group.lastActivatorX = math.floor(tonumber(player:getX()) or 0)
        group.lastActivatorY = math.floor(tonumber(player:getY()) or 0)
        group.lastActivatorZ = math.floor(tonumber(player:getZ()) or 0)
    end

    gmd.VirtualGroups[tostring(group.id)] = group

    local marker = gmd.DebugMapMarkers[tostring(group.id)] or {}
    marker.id = tostring(group.id)
    marker.markerType = "group"
    marker.x = group.x
    marker.y = group.y
    marker.z = group.z or 0
    marker.name = NPCWorldDirectorBridge.GetVirtualGroupDisplayName(group.id, group, marker.name)
    marker.displayName = marker.name
    marker.count = group.count
    marker.hostile = group.hostile
    marker.friendly = not group.hostile
    marker.factionSide = group.factionSide
    marker.faction = group.faction
    marker.side = group.side
    marker.program = group.program and group.program.name or "Raider"
    marker.virtual = true
    marker.active = false
    marker.dead = false
    marker.state = group.state
    marker.spawnPending = group.spawnPending or false
    marker.spawnQueued = group.spawnQueued or 0
    marker.spawnClass = group.spawnClass
    marker.zoneScore = group.zoneScore or 0
    marker.urbanAffinity = group.urbanAffinity or 0
    marker.roadPatrol = group.roadPatrol or false
    marker.patrolColor = group.patrolColor
    marker.mercenary = group.mercenary or false
    marker.mercenaryElite = group.mercenaryElite or false
    marker.hireable = group.hireable or false
    marker.recruitable = group.recruitable or false
    marker.blueMercenaryMapDwellUntil = group.blueMercenaryMapDwellUntil
    marker.encounterId = group.encounterId
    marker.inBattle = group.inBattle or false
    marker.battleId = group.battleId
    marker.enemyGroupId = group.enemyGroupId
    marker.battleCasualties = group.battleCasualties or 0
    marker.spawnFailed = true
    marker.spawnFailCount = group.spawnFailCount
    marker.spawnFailReason = group.lastSpawnFailReason
    marker.updatedAt = group.updatedAt
    gmd.DebugMapMarkers[tostring(group.id)] = marker

    NPCWorldDirectorBridge.SendDebugMapUpdate(marker)
    if TransmitNPCModData then TransmitNPCModData() end

    NPCWorldDirectorBridge.DirectorEvent(director, "materialize_failed", group.x, group.y, group.z or 0, {
        groupId = tostring(group.id),
        reason = tostring(reason or "unknown"),
        failCount = group.spawnFailCount
    })
    NPCWorldDirectorBridge.Log(director, NPC_WORLD_DIRECTOR_LOG_PREFIX .. " Materialize failed for " .. tostring(group.id) .. " reason=" .. tostring(reason or "unknown"))
    return false
end

function NPCWorldDirectorBridge.MaterializeGroup(director, group, player)
    if not group or group.activated then return false end
    if not player then return false end
    local serverRuntime = NPCServerRuntime or (NPCLegacyGlobalsBridge and NPCLegacyGlobalsBridge.Get and NPCLegacyGlobalsBridge.Get("ServerRuntime"))
    if not (serverRuntime and serverRuntime.Commands and serverRuntime.Commands.SpawnGroup) then return false end

    local entryTargetX = group.x
    local entryTargetY = group.y
    local entryTargetZ = group.z or 0
    local debugTeleportEntry = NPCWorldDirectorBridge.IsPlayerOnDebugMarker(director, group, player)
    local forceMercenaryLeashEntry = group.forceMercenaryLeashMaterialize == true and NPCWorldDirectorBridge.IsHiredFollowGroup(group)
    local checkpointAnchorEntry = group.checkpointGuardGroup == true and group.checkpointAnchorMaterialize == true
    local worldGroupAnchorEntry = group.anchorMaterializeAtGroup == true
    if forceMercenaryLeashEntry and group.id then
        NPCWorldDirectorBridge.CancelPendingGroupSpawnQueue(group.id, "mercenary_leash_materialize_cancel_pending_spawn")
    end
    local square = nil

    if checkpointAnchorEntry then
        square = NPCWorldDirectorBridge.FindLoadedSpawnSquareNear(director, entryTargetX, entryTargetY, entryTargetZ, tonumber(group.checkpointSpawnRadius) or 7)
    end

    if worldGroupAnchorEntry and not square then
        square = NPCWorldDirectorBridge.FindLoadedSpawnSquareNear(director, entryTargetX, entryTargetY, entryTargetZ, tonumber(group.anchorSpawnRadius) or 12)
        if not square and group.roadBias and NPCRoadNavBridge and NPCRoadNavBridge.FindLoadedRoadAround then
            local road = NPCRoadNavBridge.FindLoadedRoadAround(entryTargetX, entryTargetY, entryTargetZ, tonumber(group.anchorRoadRadius) or 36)
            square = road and road.square or nil
        end
        if not square then
            return NPCWorldDirectorBridge.MarkGroupMaterializeFailed(director, group, player, "anchor_square_unloaded")
        end
    end

    if forceMercenaryLeashEntry and not square then
        square = NPCWorldDirectorBridge.FindHiredMercenaryLeashSquare(director, player, 1)
    end

    if not square and debugTeleportEntry then
        square = NPCWorldDirectorBridge.FindLoadedSpawnSquareNear(director, entryTargetX, entryTargetY, entryTargetZ, 18)
        square = square or NPCWorldDirectorBridge.FindLoadedSpawnSquareNear(director, player:getX(), player:getY(), player:getZ(), 18)
    end

    if not square then
        square = NPCWorldDirectorBridge.FindOffscreenMaterializeSquare(director, group, player)
    end
    local offscreenEntry = square ~= nil and not debugTeleportEntry and not forceMercenaryLeashEntry and not checkpointAnchorEntry and not worldGroupAnchorEntry

    if not square and group.roadPatrol and NPCRoadNavBridge and NPCRoadNavBridge.FindLoadedRoadAround then
        local road = NPCRoadNavBridge.FindLoadedRoadAround(group.x, group.y, group.z or 0, 80)
        square = road and road.square or nil
    end

    square = square or NPCWorldDirectorBridge.FindLoadedSpawnSquareNear(director, group.x, group.y, group.z or 0, 36)

    if not square and player then
        square = NPCWorldDirectorBridge.FindLoadedSpawnSquareNear(director, player:getX(), player:getY(), player:getZ(), 42)
        if not square and NPCWorldDirectorBridge.IsPlayerActivationCoolingDown(director, player) then
            return NPCWorldDirectorBridge.DeferGroupActivation(director, group, "teleport_loaded_square_cooldown")
        end
    end

    if not square then
        return NPCWorldDirectorBridge.MarkGroupMaterializeFailed(director, group, player, "no_loaded_square")
    end

    NPCWorldDirectorBridge.InvalidateMercenaryLoadedCountCache(director, group.id)

    if director.RequestNPCObjectCleanup then
        director.RequestNPCObjectCleanup({
            groupId = tostring(group.id),
            persistentIds = NPCWorldDirectorBridge.GroupPersistentIds(group),
            x = entryTargetX,
            y = entryTargetY,
            z = entryTargetZ,
            radius = 72,
            formerOnly = true,
            reason = "pre_materialize_former_bandit_cleanup"
        })
    end

    if NPCPersistentNPCBridge and NPCPersistentNPCBridge.RestoreGroupMembers then
        NPCPersistentNPCBridge.RestoreGroupMembers(director.EnsureData(), group)
    end

    if NPCIdentityBridge and NPCIdentityBridge.TouchVirtualGroup then
        NPCIdentityBridge.TouchVirtualGroup(director.EnsureData(), group)
    end

    local event = {
        worldGroupId = group.id,
        worldDirector = true,
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
        hostile = group.hostile,
        program = group.program,
        roadPatrol = group.roadPatrol or false,
        roadBias = group.roadBias or group.roadPatrol or false,
        preferRoads = group.roadBias or group.roadPatrol or false,
        patrolColor = group.patrolColor,
        encounterId = group.encounterId,
        inBattle = group.inBattle or false,
        battleId = group.battleId,
        battleEnemyGroupId = group.enemyGroupId,
        virtualBattle = group.inBattle or false,
        offscreenEntry = offscreenEntry,
        debugTeleportEntry = debugTeleportEntry,
        mercenaryLeashEntry = forceMercenaryLeashEntry or nil,
        checkpointAnchorEntry = checkpointAnchorEntry or nil,
        anchorMaterializeEntry = worldGroupAnchorEntry or nil,
        entryTargetX = entryTargetX,
        entryTargetY = entryTargetY,
        entryTargetZ = entryTargetZ,
        bandits = group.members
    }

    group.physicalIds = {}

    local totalMembers = 0
    if type(group.members) == "table" then
        totalMembers = #group.members
        if totalMembers <= 0 then totalMembers = NPCWorldDirectorBridge.CountTable(group.members) end
    end
    local spawnBatch = totalMembers
    if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.GetSpawnBatch then
        spawnBatch = tonumber(NPCWorkSchedulerBridge.GetSpawnBatch()) or spawnBatch
    end
    if forceMercenaryLeashEntry then
        -- Hired follow/leash repair must materialize the squad as one stable runtime set.
        -- Splitting it through delayed spawn queue makes the same squad appear to respawn
        -- every few seconds and generates repeated pathing spikes around the owner.
        spawnBatch = totalMembers
    end
    if NPCCrowdBudgetBridge and NPCCrowdBudgetBridge.AdjustSpawnBatch then
        spawnBatch = NPCCrowdBudgetBridge.AdjustSpawnBatch(group, player, spawnBatch, totalMembers)
    end
    if forceMercenaryLeashEntry then spawnBatch = totalMembers end
    local proxyBudget = nil
    if player then
        proxyBudget = {npcNear = NPCWorldDirectorBridge.CountPhysicalNPCNearPlayer(director, player, director.ACTIVATION_RADIUS)}
    end
    spawnBatch = NPCWorldDirectorBridge.GetProxySpawnLimit(director, group, player, proxyBudget, spawnBatch)
    if spawnBatch < 1 then
        return NPCWorldDirectorBridge.DeferGroupActivation(director, group, "proxy_lod_no_spawn_slots", NPCWorldDirectorBridge.ProxyRetryHours(director))
    end
    if totalMembers > 0 and spawnBatch < totalMembers then
        event.spawnStart = 1
        event.spawnLimit = spawnBatch
    end

    local spawned = tonumber(serverRuntime.Commands.SpawnGroup(player, event)) or 0
    if spawned <= 0 then
        return NPCWorldDirectorBridge.MarkGroupMaterializeFailed(director, group, player, "spawn_returned_zero")
    end

    if totalMembers > 0 and spawnBatch < totalMembers and NPCSpawnQueueServer and NPCSpawnQueueServer.Enqueue then
        NPCSpawnQueueServer.Enqueue(event, spawnBatch + 1, totalMembers, group.id)
    end

    group.activated = true
    group.virtual = false
    group.spawnFailed = false
    group.retryAfter = nil
    group.lastSpawnFailReason = nil
    group.spawnPending = totalMembers > 0 and spawnBatch < totalMembers or false
    group.spawnQueued = group.spawnPending and math.max(0, totalMembers - spawnBatch) or 0
    group.state = group.spawnPending and "spawning" or "physical"
    group.x = event.x
    group.y = event.y
    group.z = event.z
    group.count = spawned

    local worldAge = 0
    if getGameTime then
        local ok, value = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok then worldAge = tonumber(value) or 0 end
    end
    group.updatedAt = worldAge
    group.materializedAt = group.updatedAt
    NPCWorldDirectorBridge.InvalidateMercenaryLoadedCountCache(director, group.id)
    group.forceMercenaryLeashMaterialize = nil
    group.checkpointAnchorMaterialize = nil
    group.anchorMaterializeAtGroup = nil
    group.anchorSpawnRadius = nil
    group.anchorRoadRadius = nil
    group.proxyHoldUntil = nil
    group.restorePhysicalBubble = nil
    group.restorePhysicalBubbleUntil = nil

    local gmd = director.EnsureData()
    if type(gmd.VirtualGroups) ~= "table" then gmd.VirtualGroups = {} end
    if type(gmd.DebugMapMarkers) ~= "table" then gmd.DebugMapMarkers = {} end
    local current = gmd.VirtualGroups[tostring(group.id)] or group
    for k, v in pairs(group) do
        current[k] = v
    end
    gmd.VirtualGroups[tostring(group.id)] = current

    local marker = gmd.DebugMapMarkers[tostring(group.id)] or {}
    marker.id = tostring(group.id)
    marker.markerType = "group"
    marker.x = group.x
    marker.y = group.y
    marker.z = group.z
    marker.name = NPCWorldDirectorBridge.GetVirtualGroupDisplayName(group.id, group, marker.name)
    marker.displayName = marker.name
    marker.count = group.count
    marker.hostile = group.hostile
    marker.friendly = not group.hostile
    marker.factionSide = group.factionSide
    marker.faction = group.faction
    marker.side = group.side
    marker.program = group.program and group.program.name or "Raider"
    marker.virtual = false
    marker.active = true
    marker.dead = false
    marker.state = group.state
    marker.spawnPending = group.spawnPending or false
    marker.spawnQueued = group.spawnQueued or 0
    marker.spawnClass = group.spawnClass
    marker.debugTeleportEntry = debugTeleportEntry or nil
    marker.zoneScore = group.zoneScore or 0
    marker.urbanAffinity = group.urbanAffinity or 0
    marker.roadPatrol = group.roadPatrol or false
    marker.patrolColor = group.patrolColor
    marker.mercenary = group.mercenary or false
    marker.mercenaryElite = group.mercenaryElite or false
    marker.hireable = group.hireable or false
    marker.recruitable = group.recruitable or false
    marker.blueMercenaryMapDwellUntil = group.blueMercenaryMapDwellUntil
    marker.encounterId = group.encounterId
    marker.inBattle = false
    marker.battleId = group.battleId
    marker.enemyGroupId = group.enemyGroupId
    marker.battleCasualties = group.battleCasualties or 0
    marker.spawnFailed = false
    marker.strategicActivityId = group.strategicActivityId
    marker.strategicActivityType = group.strategicActivityType
    marker.strategicActivityState = group.strategicActivityState
    marker.strategicActivityPriority = group.strategicActivityPriority
    marker.strategicActivityTargetBaseId = group.strategicActivityTargetBaseId
    marker.strategicActivityTargetGroupId = group.strategicActivityTargetGroupId
    marker.updatedAt = group.updatedAt
    gmd.DebugMapMarkers[tostring(group.id)] = marker

    NPCWorldDirectorBridge.SendDebugMapUpdate(marker)
    if TransmitNPCModData then TransmitNPCModData() end

    NPCWorldDirectorBridge.DirectorEvent(director, "group_materialized", group.x, group.y, group.z or 0, {
        groupId = tostring(group.id),
        count = spawned,
        side = group.side,
        roadPatrol = group.roadPatrol or false
    })
    NPCWorldDirectorBridge.DirectorOutcomeStart(director, "materialization", group, {
        count = spawned,
        side = tostring(group.side or ""),
        roadPatrol = group.roadPatrol or false
    })
    NPCWorldDirectorBridge.DirectorCellCooldown(director, "materialization", group.x, group.y, group.z or 0, {
        groupId = tostring(group.id or ""),
        count = spawned,
        side = tostring(group.side or ""),
        roadPatrol = group.roadPatrol or false
    })
    NPCWorldDirectorBridge.Log(director, NPC_WORLD_DIRECTOR_LOG_PREFIX .. " Materialized group " .. tostring(group.id) .. " at " .. tostring(group.x) .. "," .. tostring(group.y) .. " spawned=" .. tostring(spawned))
    return true
end

-- Stage 56: neutral activation loop backend.
-- Keeps the historical legacy world-director activation entry point as a compatibility
-- wrapper while candidate selection, budgeting and battle-pair activation live here.

function NPCWorldDirectorBridge.ActivateGroupsNearPlayers(director)
    if not director or not director.EnsureData then return end
    local gmd = director.EnsureData()
    if not gmd then return end
    local worldAge = getGameTime():getWorldAgeHours()

    NPCWorldDirectorBridge.EnsureStrategicMarkerGroups(director, gmd, worldAge)

    local budgets = NPCWorldDirectorBridge.PrepareActivationBudgets(director, gmd, worldAge)
    local candidates = {}

    if type(gmd.VirtualGroups) ~= "table" then return end

    for _, group in pairs(gmd.VirtualGroups) do
        if group and not group.activated then
            if group.restorePhysicalBubble == true and group.restorePhysicalBubbleUntil and worldAge > tonumber(group.restorePhysicalBubbleUntil) then
                group.restorePhysicalBubble = nil
                group.restorePhysicalBubbleUntil = nil
                group.state = NPCWorldDirectorBridge.ResumeVirtualState(group)
            end
            if not group.retryAfter or worldAge >= tonumber(group.retryAfter) then
                local activationRadius = NPCWorldDirectorBridge.GetActivationRadiusForGroup(director, group)
                local player, dist = NPCWorldDirectorBridge.GetNearestPlayer(director, group.x, group.y, activationRadius)
                if player then
                    local key = NPCWorldDirectorBridge.PlayerKey(player)
                    local budget = key and budgets[key] or nil
                    if budget then
                        local priority = NPCWorldDirectorBridge.GetActivationPriority(director, group, player, dist)
                        if group.restorePhysicalBubble == true then priority = priority - 250 end
                        table.insert(candidates, {
                            group = group,
                            player = player,
                            budget = budget,
                            distance = dist or 999999,
                            priority = priority
                        })
                    end
                end
            end
        end
    end

    table.sort(candidates, function(a, b)
        if a.priority == b.priority then
            return tostring(a.group and a.group.id or "") < tostring(b.group and b.group.id or "")
        end
        return a.priority < b.priority
    end)

    local totalActivations = 0
    local battlePairs = 0
    local restoreActivations = 0
    local restoreMax = math.max(1, tonumber(director.PERSISTENCE_RESTORE_MAX_GROUPS_PER_RUN) or 1)

    for i=1, #candidates do
        local candidate = candidates[i]
        local group = candidate.group
        local criticalCheckpoint = NPCWorldDirectorBridge.IsCriticalCheckpointActivation(director, group, candidate.player, candidate.distance)
        local teleportMarkerEntry = director.TELEPORT_MARKER_BYPASS_DEFERS ~= false and NPCWorldDirectorBridge.IsPlayerOnDebugMarker(director, group, candidate.player)
        local restoreBubbleActivation = group and group.restorePhysicalBubble == true
        local restoreBudgetBlocked = restoreBubbleActivation and restoreActivations >= restoreMax
        local urgentMarkerActivation = criticalCheckpoint or teleportMarkerEntry or (restoreBubbleActivation and not restoreBudgetBlocked)
        local blockedByActivationBudget = totalActivations >= (tonumber(director.MAX_GROUP_ACTIVATIONS_PER_UPDATE) or 1) and not urgentMarkerActivation
        local blockedByPhysicalBudget = NPCWorldDirectorBridge.GetPhysicalGroupCount(director) >= director.MAX_PHYSICAL_GROUPS and not urgentMarkerActivation
        local player = candidate.player
        local budget = candidate.budget

        if not (blockedByActivationBudget or blockedByPhysicalBudget or restoreBudgetBlocked) and group and not group.activated and player and budget then
            if NPCWorldDirectorBridge.CanActivateGroupForPlayer(director, group, player, budget, totalActivations, candidate.distance) then
                local done = false
                if group.inBattle and group.enemyGroupId then
                    local enemy = gmd.VirtualGroups[tostring(group.enemyGroupId)]
                    if enemy and not enemy.activated and battlePairs < (tonumber(director.MAX_BATTLE_PAIR_ACTIVATIONS_PER_UPDATE) or 1) then
                        done = NPCWorldDirectorBridge.MaterializeRoadBattlePair(director, group, enemy, player)
                        if done then battlePairs = battlePairs + 1 end
                    elseif enemy and not enemy.activated then
                        NPCWorldDirectorBridge.DeferGroupActivation(director, enemy, "battle_pair_budget")
                    end
                end

                if not done then
                    done = NPCWorldDirectorBridge.MaterializeGroup(director, group, player)
                end

                if done then
                    totalActivations = totalActivations + 1
                    if restoreBubbleActivation then restoreActivations = restoreActivations + 1 end
                    budget.activations = (tonumber(budget.activations) or 0) + 1
                    budget.npcNear = (tonumber(budget.npcNear) or 0) + NPCWorldDirectorBridge.GetGroupMemberCount(director, group)
                end
            end
        end
    end
end

-- Stage 52: neutral physical group lifecycle backend.
-- Keeps historical legacy world-director entry points as compatibility wrappers while
-- dematerialization, physical group cleanup and queue snapshot logic live here.

local function npc_wd_stage52_worldAge()
    if getGameTime then
        local ok, value = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok then return tonumber(value) or 0 end
    end
    return 0
end

local NPC_WORLD_DIRECTOR_STAGE411_MEMBER_FIELDS = {
    "uid", "persistentId", "memberIndex", "fullname", "name", "female", "voice", "outfit", "appearanceSeed", "faceProfile",
    "skinTexture", "skinColor", "hairStyle", "hairColor", "beardStyle", "beardColor", "humanVisualLocked", "humanVisualSignature", "humanVisualNormalized", "humanVisualNormalizedAt",
    "health", "maxHealth", "endurance", "infection", "role", "tacticalRole", "relationship", "relationshipToPlayer",
    "clan", "faction", "factionSide", "side", "factionState", "hostile", "friendly", "master", "isPlayerGuard", "followPlayer", "guardPlayer",
    "mercenary", "mercenaryElite", "mercenaryHired", "mercenaryHiredBy", "mercenaryHiredByName", "mercenarySquadLeader", "mercenarySquadLeaderName",
    "wounded", "woundedDowned", "woundedState", "woundedReason", "woundedAt", "woundedExpiresAt", "woundedForPlayerId", "woundedForPlayerName", "woundedX", "woundedY", "woundedZ", "woundedStabilized", "woundedStabilizedAt", "woundedEvacuating", "woundedEvacuatedAt", "woundedEvacTarget", "woundedEvacBaseId", "woundedAbandoned", "woundedAbandonedAt", "woundedNoDespawn", "woundedKeepRuntime",
    "spy", "spyForPlayerId", "spyForPlayerName", "spyOriginalSide", "spyBribedAt", "spyState", "spyDefected", "spyDefectedAt", "spySabotage", "spyAlliedGroup", "spyPaymentKind", "spyDefectionReason",
    "homeBaseId", "homeBase", "homeBaseZoneId", "homeBaseZoneType", "homeBaseZone", "baseZoneId", "baseZoneType", "baseDuty", "baseDutyState", "baseDutyReason", "baseDutyGroupId", "baseDutyOwner",
    "guardPoint", "patrolPoint", "medicalPoint", "restPoint", "foodPoint", "ammoPoint", "storagePoint", "returnPoint",
    "currentWeapon", "ammo", "weapons", "inventoryLite", "wornLite", "gearLite", "loot", "key", "baseGear", "baseGearWear", "baseGearWeaponKits", "baseGearWeaponParts", "baseGearMagazines", "baseGearBaseId",
    "needs", "stock", "skills", "xp", "morale", "fear", "aggression", "discipline", "lastKnownEnemyPosition", "order", "fireMode", "program", "programName", "programStage", "lastTask",
    "roadPatrol", "roadBias", "preferRoads", "patrolColor", "encounterId", "inBattle", "virtualBattle", "battleId", "enemyGroupId", "battleEnemyGroupId", "worldGroupId", "groupId"
}

local NPC_WORLD_DIRECTOR_STAGE411_GROUP_TRANSIENT_FIELDS = {
    "physicalIds", "spawnPending", "spawnQueued", "spawnFailed", "retryAfter", "lastSpawnFailReason", "spawnFailReason", "debugTeleportEntry",
    "proxyHoldUntil", "proxyDematerializedAt", "forceMercenaryLeashMaterialize", "checkpointAnchorMaterialize", "anchorMaterializeAtGroup", "anchorSpawnRadius", "anchorRoadRadius",
    "currentPath", "path", "pathTarget", "pathFind", "pathRequest", "roadPath", "roadStep", "roadStepExpireAt", "mapPath", "mapRoute", "mapNodes", "cachedRoute", "runtime", "ai", "debug",
    "lastActivationAt", "lastActivationPlayer", "lastSpawnAttemptAt", "lastSpawnedRuntimeIds", "spawnBatch", "spawnStart", "spawnLimit"
}

function NPCWorldDirectorBridge.CompactMemberForStrategicPersistence(member)
    if type(member) ~= "table" then return nil end
    local out = {}
    for _, key in ipairs(NPC_WORLD_DIRECTOR_STAGE411_MEMBER_FIELDS) do
        local value = member[key]
        if value ~= nil then
            out[key] = type(value) == "table" and NPCWorldDirectorBridge.Copy(value) or value
        end
    end
    out.uid = out.uid or out.persistentId
    out.persistentId = out.persistentId or out.uid
    out.name = out.name or out.fullname
    out.fullname = out.fullname or out.name
    out.groupId = out.groupId or out.worldGroupId
    out.worldGroupId = out.worldGroupId or out.groupId
    return out
end

function NPCWorldDirectorBridge.CompactGroupMembersForStrategicPersistence(group)
    if type(group) ~= "table" or type(group.members) ~= "table" then return 0 end
    local compact = {}
    local seen = {}
    for _, member in ipairs(group.members) do
        local out = NPCWorldDirectorBridge.CompactMemberForStrategicPersistence(member)
        if out then
            local key = tostring(out.uid or out.persistentId or out.memberIndex or (#compact + 1))
            if not seen[key] then
                seen[key] = true
                compact[#compact + 1] = out
            end
        end
    end
    group.members = compact
    if #compact > 0 then group.count = #compact end
    return #compact
end

function NPCWorldDirectorBridge.CompactVirtualGroupForStrategicPersistence(director, gmd, groupId, group, reason)
    if type(group) ~= "table" then return false end
    groupId = tostring(groupId or group.id or "")
    if groupId == "" then return false end

    local wasPhysicalBubble = group.persistPhysicalBubble == true or group.restorePhysicalBubble == true
    NPCWorldDirectorBridge.CompactGroupMembersForStrategicPersistence(group)
    for _, key in ipairs(NPC_WORLD_DIRECTOR_STAGE411_GROUP_TRANSIENT_FIELDS) do
        group[key] = nil
    end

    if not wasPhysicalBubble then
        group.activated = false
        group.virtual = true
        group.state = NPCWorldDirectorBridge.ResumeVirtualState(group)
        group.persistPhysicalBubble = nil
        group.restorePhysicalBubble = nil
        group.restorePhysicalBubbleUntil = nil
    end

    group.id = group.id or groupId
    group.count = tonumber(group.count) or NPCWorldDirectorBridge.GroupMemberCount(group)
    group.updatedAt = npc_wd_stage52_worldAge()
    group.compactStrategicPersistence = true
    group.compactStrategicPersistenceReason = tostring(reason or "strategic_compact")

    if gmd and type(gmd.VirtualGroups) == "table" then
        gmd.VirtualGroups[groupId] = group
    end
    return true
end

function NPCWorldDirectorBridge.EnsurePhysicalBubbleStore(gmd)
    if not gmd then return nil end
    gmd.WorldDirector = gmd.WorldDirector or {}
    if type(gmd.WorldDirector.PhysicalBubbleGroups) ~= "table" then gmd.WorldDirector.PhysicalBubbleGroups = {} end
    return gmd.WorldDirector.PhysicalBubbleGroups
end

function NPCWorldDirectorBridge.GetPersistedPhysicalBubble(gmd, groupId)
    local store = gmd and gmd.WorldDirector and gmd.WorldDirector.PhysicalBubbleGroups or nil
    if type(store) ~= "table" or groupId == nil then return nil end
    return store[tostring(groupId)]
end

function NPCWorldDirectorBridge.IsGroupNearAnyPlayer(director, group, radius)
    if not (director and group and group.x and group.y) then return false, nil, nil end
    local player, dist = NPCWorldDirectorBridge.GetNearestPlayer(director, group.x, group.y, tonumber(radius) or 160)
    return player ~= nil, player, dist
end

function NPCWorldDirectorBridge.SnapshotPhysicalBubbleGroups(director, reason, maxGroups)
    if not (director and director.PERSISTENCE_PHYSICAL_BUBBLE_ENABLED ~= false and director.EnsureData) then return 0 end
    local gmd = director.EnsureData()
    if not (gmd and type(gmd.VirtualGroups) == "table") then return 0 end

    local radius = tonumber(director.PERSISTENCE_PHYSICAL_BUBBLE_RADIUS) or 170
    local limit = tonumber(maxGroups) or tonumber(director.PERSISTENCE_PHYSICAL_BUBBLE_MAX_GROUPS) or 8
    if limit <= 0 then return 0 end
    local store = NPCWorldDirectorBridge.EnsurePhysicalBubbleStore(gmd)
    if not store then return 0 end
    local worldAge = npc_wd_stage52_worldAge()
    local changed = 0

    for groupId, group in pairs(gmd.VirtualGroups) do
        if changed >= limit then break end
        if type(group) == "table" and group.activated == true and group.virtual == false then
            local nearPlayer = NPCWorldDirectorBridge.IsGroupNearAnyPlayer(director, group, radius)
            if nearPlayer then
                local members, _queueIds, avgX, avgY, avgZ = NPCWorldDirectorBridge.GetPhysicalMemberSnapshots(director, groupId)
                if #members > 0 then
                    group.members = members
                    NPCWorldDirectorBridge.CompactGroupMembersForStrategicPersistence(group)
                    group.count = #group.members
                    group.x = avgX or group.x
                    group.y = avgY or group.y
                    group.z = avgZ or group.z or 0
                    group.persistPhysicalBubble = true
                    group.persistPhysicalBubbleAt = worldAge
                    group.persistPhysicalBubbleReason = tostring(reason or "physical_bubble_snapshot")
                    group.persistPhysicalBubbleRadius = radius
                    group.persistPhysicalBubbleCount = group.count
                    group.compactStrategicPersistence = true
                    gmd.VirtualGroups[tostring(groupId)] = group
                    store[tostring(groupId)] = {
                        id = tostring(groupId),
                        x = group.x,
                        y = group.y,
                        z = group.z or 0,
                        count = group.count,
                        members = NPCWorldDirectorBridge.Copy(group.members),
                        updatedAt = worldAge,
                        reason = tostring(reason or "physical_bubble_snapshot")
                    }
                    if NPCPersistentNPCBridge and NPCPersistentNPCBridge.RegisterGroup then
                        pcall(function() NPCPersistentNPCBridge.RegisterGroup(gmd, group) end)
                    end
                    changed = changed + 1
                end
            end
        end
    end

    gmd.WorldDirector.lastPhysicalBubbleSnapshotAt = worldAge
    gmd.WorldDirector.lastPhysicalBubbleSnapshotReason = tostring(reason or "physical_bubble_snapshot")
    gmd.WorldDirector.lastPhysicalBubbleSnapshotCount = changed
    return changed
end

function NPCWorldDirectorBridge.CompactStrategicPersistence(director, reason, maxGroups)
    if not (director and director.PERSISTENCE_COMPACT_VIRTUAL_GROUPS ~= false and director.EnsureData) then return 0 end
    local gmd = director.EnsureData()
    if not (gmd and type(gmd.VirtualGroups) == "table") then return 0 end

    local ids = {}
    for groupId, _ in pairs(gmd.VirtualGroups) do ids[#ids + 1] = tostring(groupId) end
    table.sort(ids)

    local budget = tonumber(maxGroups) or tonumber(director.PERSISTENCE_COMPACT_GROUPS_PER_RUN) or 32
    if budget <= 0 then return 0 end
    local state = gmd.WorldDirector or {}
    gmd.WorldDirector = state
    local cursor = tonumber(state.strategicPersistenceCursor) or 1
    if cursor > #ids then cursor = 1 end

    local changed = 0
    local scanned = 0
    while #ids > 0 and scanned < #ids and changed < budget do
        local groupId = ids[cursor]
        cursor = cursor + 1
        if cursor > #ids then cursor = 1 end
        scanned = scanned + 1
        local group = gmd.VirtualGroups[groupId]
        if type(group) == "table" and group.activated ~= true then
            if NPCWorldDirectorBridge.CompactVirtualGroupForStrategicPersistence(director, gmd, groupId, group, reason) then
                changed = changed + 1
            end
        end
    end

    state.strategicPersistenceCursor = cursor
    state.lastStrategicPersistenceCompactAt = npc_wd_stage52_worldAge()
    state.lastStrategicPersistenceCompactReason = tostring(reason or "strategic_compact")
    state.lastStrategicPersistenceCompactCount = changed
    return changed
end

function NPCWorldDirectorBridge.PreparePhysicalBubbleGroupForRestore(director, gmd, groupId, group, bubble, worldAge)
    if not (gmd and groupId and type(group) == "table" and type(bubble) == "table") then return false end
    local members = type(bubble.members) == "table" and NPCWorldDirectorBridge.Copy(bubble.members) or group.members
    if type(members) ~= "table" or #members <= 0 then return false end
    group.members = members
    NPCWorldDirectorBridge.CompactGroupMembersForStrategicPersistence(group)
    group.count = #group.members
    group.x = tonumber(bubble.x) or group.x
    group.y = tonumber(bubble.y) or group.y
    group.z = tonumber(bubble.z) or group.z or 0
    group.activated = false
    group.virtual = true
    group.physicalIds = nil
    group.spawnPending = false
    group.spawnQueued = 0
    group.spawnFailed = false
    group.retryAfter = nil
    group.lastSpawnFailReason = nil
    group.persistPhysicalBubble = true
    group.restorePhysicalBubble = true
    group.restorePhysicalBubbleAt = worldAge
    group.restorePhysicalBubbleUntil = worldAge + 1.5
    group.state = "restore_pending"
    group.updatedAt = worldAge
    gmd.VirtualGroups[tostring(groupId)] = group
    return true
end

function NPCWorldDirectorBridge.GetActivationRadiusForGroup(director, group)
    if group and group.restorePhysicalBubble == true then
        return tonumber(director.PERSISTENCE_RESTORE_BUBBLE_RADIUS) or tonumber(director.ACTIVATION_RADIUS) or 150
    end
    return tonumber(director.ACTIVATION_RADIUS) or 150
end

function NPCWorldDirectorBridge.FlushStrategicPersistence(director, reason)
    if not (director and director.EnsureData) then return 0 end
    local physical = NPCWorldDirectorBridge.SnapshotPhysicalBubbleGroups(director, reason or "flush")
    local compact = NPCWorldDirectorBridge.CompactStrategicPersistence(director, reason or "flush", tonumber(director.PERSISTENCE_COMPACT_GROUPS_PER_RUN) or 32)
    return (tonumber(physical) or 0) + (tonumber(compact) or 0)
end

function NPCWorldDirectorBridge.GetPhysicalMemberSnapshots(director, groupId)
    local gmd = director and director.EnsureData and director.EnsureData() or nil
    local members = {}
    local queueIds = {}
    local sumX = 0
    local sumY = 0
    local sumZ = 0

    if not groupId or type(gmd) ~= "table" or type(gmd.Queue) ~= "table" then
        return members, queueIds, nil, nil, nil
    end

    groupId = tostring(groupId)
    local seenMembers = {}
    for id, brain in pairs(gmd.Queue) do
        local brainGroupId = NPCWorldDirectorBridge.BrainGroupId(brain)
        if type(brain) == "table" and brainGroupId and tostring(brainGroupId) == groupId then
            local memberKey = brain.uid or brain.persistentId or brain.id or id
            memberKey = memberKey ~= nil and tostring(memberKey) or nil
            if memberKey and seenMembers[memberKey] then
                queueIds[#queueIds + 1] = id
            else
                if memberKey then seenMembers[memberKey] = true end
                local runtimeZombie = nil
                if NPCWorldDirectorBridge.FindLoadedNPCZombieForBrain then
                    runtimeZombie = NPCWorldDirectorBridge.FindLoadedNPCZombieForBrain(director, id, brain, groupId)
                end
                if NPCPersistentNPCBridge and NPCPersistentNPCBridge.TouchFromRuntime then
                    local ok, err = pcall(function() NPCPersistentNPCBridge.TouchFromRuntime(gmd, brain, id, runtimeZombie) end)
                    if not ok then NPCWorldDirectorBridge.Log(director, NPC_WORLD_DIRECTOR_LOG_PREFIX .. " TouchFromRuntime failed: " .. tostring(err)) end
                end

                local x = brain.debugCoords and tonumber(brain.debugCoords.x) or tonumber(brain.x)
            local y = brain.debugCoords and tonumber(brain.debugCoords.y) or tonumber(brain.y)
            local z = brain.debugCoords and tonumber(brain.debugCoords.z) or tonumber(brain.z) or 0
            if not x and brain.bornCoords then x = tonumber(brain.bornCoords.x) end
            if not y and brain.bornCoords then y = tonumber(brain.bornCoords.y) end
            if not z and brain.bornCoords then z = tonumber(brain.bornCoords.z) or 0 end

            local ai = brain.ai or {}
            local member = {
                uid = brain.uid,
                persistentId = brain.persistentId,
                runtimeId = id,
                memberIndex = brain.memberIndex,
                fullname = brain.fullname,
                homeBase = brain.homeBase,
                permanent = brain.permanent,
                female = brain.female,
                voice = brain.voice,
                femaleChance = brain.female and 100 or 0,
                outfit = brain.outfit,
                appearanceSeed = brain.appearanceSeed,
                faceProfile = brain.faceProfile,
                skinTexture = brain.skinTexture,
                skinColor = brain.skinColor,
                hairStyle = brain.hairStyle,
                hairColor = brain.hairColor,
                beardStyle = brain.beardStyle,
                beardColor = brain.beardColor,
                humanVisualLocked = brain.humanVisualLocked,
                humanVisualSignature = brain.humanVisualSignature,
                humanVisualNormalized = brain.humanVisualNormalized,
                humanVisualNormalizedAt = brain.humanVisualNormalizedAt,
                health = brain.health or brain.maxHealth or 3.0,
                maxHealth = brain.maxHealth or brain.health or 3.0,
                role = brain.role,
                tacticalRole = brain.tacticalRole,
                master = brain.master,
                mercenary = brain.mercenary,
                mercenaryElite = brain.mercenaryElite,
                mercenaryHired = brain.mercenaryHired,
                mercenaryHiredBy = brain.mercenaryHiredBy,
                mercenaryHiredByName = brain.mercenaryHiredByName,
                mercenarySquadLeader = brain.mercenarySquadLeader,
                mercenarySquadLeaderName = brain.mercenarySquadLeaderName,
                isPlayerGuard = brain.isPlayerGuard,
                followPlayer = brain.followPlayer,
                guardPlayer = brain.guardPlayer,
                friendly = brain.friendly,
                relationship = brain.relationship,
                relationshipToPlayer = brain.relationshipToPlayer,
                factionState = brain.factionState,
                factionSide = brain.factionSide,
                faction = brain.faction,
                side = brain.side,
                currentWeapon = brain.currentWeapon,
                ammo = brain.ammo,
                inventoryLite = brain.inventoryLite,
                needs = brain.needs or ai.needs,
                stock = brain.stock or ai.stock,
                skills = brain.skills or ai.skills,
                xp = brain.xp or ai.xp,
                morale = brain.morale or ai.morale,
                fear = brain.fear or ai.fear,
                aggression = brain.aggression or ai.aggression,
                discipline = brain.discipline or ai.discipline,
                lastKnownEnemyPosition = brain.lastKnownEnemyPosition or ai.lastKnownEnemyPosition,
                lastTask = brain.lastTask,
                order = brain.order,
                fireMode = brain.order and brain.order.fireMode or brain.fireMode,
                program = brain.program,
                sim = brain.sim,
                fsm = brain.fsm,
                watchdog = brain.watchdog,
                debug = brain.debug,
                dna = brain.dna,
                state = brain.state or (brain.sim and brain.sim.state),
                homeBaseId = brain.homeBaseId,
                clan = brain.clan,
                eatBody = brain.eatBody,
                accuracyBoost = brain.accuracyBoost,
                weapons = brain.weapons,
                loot = brain.loot,
                key = brain.key,
                inventory = brain.inventory,
                baseGear = brain.baseGear,
                baseGearWear = brain.baseGearWear,
                baseGearWeaponKits = brain.baseGearWeaponKits,
                baseGearWeaponParts = brain.baseGearWeaponParts,
                baseGearMagazines = brain.baseGearMagazines,
                baseGearBaseId = brain.baseGearBaseId,
                roadPatrol = brain.roadPatrol or false,
                roadBias = brain.roadBias or false,
                preferRoads = brain.preferRoads or false,
                patrolColor = brain.patrolColor,
                encounterId = brain.encounterId,
                inBattle = brain.inBattle or brain.virtualBattle or false,
                virtualBattle = brain.virtualBattle or false,
                battleId = brain.battleId,
                enemyGroupId = brain.battleEnemyGroupId or brain.enemyGroupId,
                battleEnemyGroupId = brain.battleEnemyGroupId or brain.enemyGroupId,
                worldGroupId = brainGroupId,
                groupId = brain.groupId
            }

                table.insert(members, member)
                table.insert(queueIds, id)
                sumX = sumX + (x or 0)
                sumY = sumY + (y or 0)
                sumZ = sumZ + (z or 0)
            end
        end
    end

    if #members <= 0 then
        return members, queueIds, nil, nil, nil
    end

    return members, queueIds, math.floor(sumX / #members), math.floor(sumY / #members), math.floor(sumZ / #members)
end

function NPCWorldDirectorBridge.GroupMemberCount(group)
    if type(group) ~= "table" then return 0 end
    local count = tonumber(group.count) or 0
    if count > 0 then return count end
    if type(group.members) == "table" then
        for _, member in pairs(group.members) do
            if type(member) == "table" then count = count + 1 end
        end
    end
    return count
end

function NPCWorldDirectorBridge.IsWorldGroupTrueDeathReason(reason)
    reason = tostring(reason or "")
    return reason == "all_members_dead"
        or reason == "road_battle_lost"
        or reason == "strategic_battle_lost"
        or reason == "manual_delete"
end

function NPCWorldDirectorBridge.PreserveWorldGroupAsVirtual(director, gmd, groupId, group, reason)
    if not (director and gmd and groupId and type(group) == "table") then return false end
    if NPCWorldDirectorBridge.IsWorldGroupTrueDeathReason(reason) then return false end

    if group.blackMarketDefenseQuestGroup == true or group.blackMarketDefenseQuestId ~= nil or group.spawnClass == "black_market_defense_enemy" then return false end

    local count = NPCWorldDirectorBridge.GroupMemberCount(group)
    if count <= 0 then return false end

    groupId = tostring(groupId)
    if type(gmd.VirtualGroups) ~= "table" then gmd.VirtualGroups = {} end
    if type(gmd.DebugMapMarkers) ~= "table" then gmd.DebugMapMarkers = {} end

    if type(group.members) ~= "table" and NPCPersistentNPCBridge and NPCPersistentNPCBridge.RestoreGroupMembers then
        pcall(function() NPCPersistentNPCBridge.RestoreGroupMembers(gmd, group) end)
        count = NPCWorldDirectorBridge.GroupMemberCount(group)
    end
    if count <= 0 then return false end

    NPCWorldDirectorBridge.RemoveNpcMarkersForGroup(gmd, groupId)
    group.count = count
    group.activated = false
    group.virtual = true
    group.physicalIds = nil
    group.spawnPending = false
    group.spawnQueued = 0
    group.spawnFailed = false
    group.retryAfter = nil
    group.lastSpawnFailReason = nil
    group.preservedVirtual = true
    group.preservedReason = tostring(reason or "runtime_marker_preserve")
    group.updatedAt = npc_wd_stage52_worldAge()
    if NPCStrategicAIBridge and NPCStrategicAIBridge.ResumeGroupState then
        local ok, state = pcall(function() return NPCStrategicAIBridge.ResumeGroupState(group) end)
        if ok and state then group.state = state end
    elseif group.roadPatrol then
        group.state = group.hostile and "red_road_patrol" or "green_road_patrol"
    else
        group.state = group.homeBaseId and "base_patrol" or "roaming"
    end

    gmd.VirtualGroups[groupId] = group
    if NPCPersistentNPCBridge and NPCPersistentNPCBridge.RegisterGroup then
        pcall(function() NPCPersistentNPCBridge.RegisterGroup(gmd, group) end)
    end

    local marker = nil
    if NPCWorldDirectorBridge.BuildVirtualGroupUpdateMarker then
        marker = NPCWorldDirectorBridge.BuildVirtualGroupUpdateMarker(gmd, groupId, group)
    else
        marker = NPCWorldDirectorBridge.BuildVirtualGroupMarker(group)
    end
    if marker then
        marker.preservedVirtual = true
        marker.preservedReason = group.preservedReason
        marker.dead = false
        marker.virtual = true
        marker.active = false
        gmd.DebugMapMarkers[groupId] = marker
        NPCWorldDirectorBridge.SendDebugMapUpdate(marker)
    end

    NPCWorldDirectorBridge.Log(director, NPC_WORLD_DIRECTOR_LOG_PREFIX .. " Preserved virtual group marker " .. tostring(groupId) .. " reason=" .. tostring(reason or "runtime_marker_preserve"))
    return true
end

function NPCWorldDirectorBridge.DematerializeFarPhysicalGroup(director, groupId, group)
    if not groupId or not group or not (director and director.EnsureData) then return false end

    local gmd = director.EnsureData()
    if type(gmd) ~= "table" then return false end
    if type(gmd.VirtualGroups) ~= "table" then gmd.VirtualGroups = {} end
    if type(gmd.DebugMapMarkers) ~= "table" then gmd.DebugMapMarkers = {} end
    groupId = tostring(groupId)

    local members, queueIds, avgX, avgY, avgZ = NPCWorldDirectorBridge.GetPhysicalMemberSnapshots(director, groupId)
    if #members <= 0 then
        local restored = false
        if NPCPersistentNPCBridge and NPCPersistentNPCBridge.RestoreGroupMembers then
            local ok, result = pcall(function() return NPCPersistentNPCBridge.RestoreGroupMembers(gmd, group) end)
            restored = ok and result and type(group.members) == "table" and #group.members > 0
        end
        if restored then
            NPCWorldDirectorBridge.RemoveNpcMarkersForGroup(gmd, groupId)
            group.count = #group.members
            group.activated = false
            group.virtual = true
            group.physicalIds = nil
            group.spawnFailed = false
            group.retryAfter = nil
            group.lastSpawnFailReason = nil
            group.updatedAt = npc_wd_stage52_worldAge()
            gmd.VirtualGroups[groupId] = group
            if NPCPersistentNPCBridge and NPCPersistentNPCBridge.RegisterGroup then
                pcall(function() NPCPersistentNPCBridge.RegisterGroup(gmd, group) end)
            end
            return true
        end

        if NPCWorldDirectorBridge.PreserveWorldGroupAsVirtual(director, gmd, groupId, group, "dematerialize_no_runtime_members") then
            return true
        end

        gmd.VirtualGroups[groupId] = nil
        NPCWorldDirectorBridge.RemoveNpcMarkersForGroup(gmd, groupId)
        gmd.DebugMapMarkers[groupId] = nil
        NPCWorldDirectorBridge.SendDebugMapRemove(groupId)
        return true
    end

    local cleanupIds = {}
    if type(gmd.Queue) ~= "table" then gmd.Queue = {} end
    for _, runtimeId in ipairs(queueIds) do
        local sid = tostring(runtimeId)
        local brain = gmd.Queue[runtimeId] or gmd.Queue[sid]
        local uid = brain and brain.uid or nil
        table.insert(cleanupIds, sid)
        gmd.Queue[runtimeId] = nil
        gmd.Queue[sid] = nil
        if gmd.RuntimeToUID then gmd.RuntimeToUID[sid] = nil end
        if uid and gmd.UIDToRuntime then gmd.UIDToRuntime[tostring(uid)] = nil end
        NPCWorldDirectorBridge.RemoveNpcMarkerForRuntime(gmd, sid)
    end

    if #cleanupIds > 0 and director.RequestNPCObjectCleanup then
        director.RequestNPCObjectCleanup({
            ids = cleanupIds,
            groupId = groupId,
            x = avgX or group.x,
            y = avgY or group.y,
            z = avgZ or group.z or 0,
            radius = 96,
            reason = "world_group_dematerialize"
        })
    end

    NPCWorldDirectorBridge.RemoveNpcMarkersForGroup(gmd, groupId)

    group.members = members
    group.count = #members
    group.x = avgX or group.x
    group.y = avgY or group.y
    group.z = avgZ or group.z or 0
    group.activated = false
    group.virtual = true
    group.physicalIds = nil
    group.spawnFailed = false
    group.retryAfter = nil
    group.lastSpawnFailReason = nil
    if group.roadPatrol then
        if NPCStrategicAIBridge and NPCStrategicAIBridge.ResumeGroupState then
            local ok, state = pcall(function() return NPCStrategicAIBridge.ResumeGroupState(group) end)
            group.state = ok and state or (group.hostile and "red_road_patrol" or "green_road_patrol")
        else
            group.state = group.hostile and "red_road_patrol" or "green_road_patrol"
        end
    else
        group.state = group.homeBaseId and "base_patrol" or "roaming"
    end
    group.updatedAt = npc_wd_stage52_worldAge()
    gmd.VirtualGroups[groupId] = group
    if NPCPersistentNPCBridge and NPCPersistentNPCBridge.RegisterGroup then
        pcall(function() NPCPersistentNPCBridge.RegisterGroup(gmd, group) end)
    end

    local marker = gmd.DebugMapMarkers[groupId] or {}
    marker.id = groupId
    marker.markerType = "group"
    marker.x = group.x
    marker.y = group.y
    marker.z = group.z or 0
    marker.name = NPCWorldDirectorBridge.GetVirtualGroupDisplayName(groupId, group, marker.name)
    marker.displayName = marker.name
    marker.count = group.count
    marker.hostile = group.hostile
    marker.friendly = not group.hostile
    marker.program = group.program and group.program.name or marker.program or "Raider"
    marker.virtual = true
    marker.active = false
    marker.dead = false
    marker.state = group.state
    marker.spawnPending = group.spawnPending or false
    marker.spawnQueued = group.spawnQueued or 0
    marker.spawnClass = group.spawnClass
    marker.zoneScore = group.zoneScore or 0
    marker.urbanAffinity = group.urbanAffinity or 0
    marker.roadPatrol = group.roadPatrol or false
    marker.patrolColor = group.patrolColor
    marker.mercenary = group.mercenary or false
    marker.mercenaryElite = group.mercenaryElite or false
    marker.hireable = group.hireable or false
    marker.recruitable = group.recruitable or false
    marker.blueMercenaryMapDwellUntil = group.blueMercenaryMapDwellUntil
    marker.encounterId = group.encounterId
    marker.inBattle = group.inBattle or false
    marker.battleId = group.battleId
    marker.enemyGroupId = group.enemyGroupId
    marker.battleCasualties = group.battleCasualties or 0
    marker.updatedAt = group.updatedAt
    gmd.DebugMapMarkers[groupId] = marker
    NPCWorldDirectorBridge.SendDebugMapUpdate(marker)

    NPCWorldDirectorBridge.Log(director, NPC_WORLD_DIRECTOR_LOG_PREFIX .. " Dematerialized far physical group " .. tostring(groupId) .. " members=" .. tostring(#members))
    return true
end

function NPCWorldDirectorBridge.CountAlivePhysicalMembers(director, groupId)
    if not groupId or not (director and director.EnsureData) then return 0 end

    local gmd = director.EnsureData()
    if type(gmd) ~= "table" or type(gmd.Queue) ~= "table" then return 0 end

    local count = 0
    for _, brain in pairs(gmd.Queue) do
        local brainGroupId = NPCWorldDirectorBridge.BrainGroupId(brain)
        if brain and brainGroupId and tostring(brainGroupId) == tostring(groupId) then
            count = count + 1
        end
    end

    return count
end

function NPCWorldDirectorBridge.RemoveWorldGroup(director, groupId, reason)
    if not groupId or not (director and director.EnsureData) then return false end

    local gmd = director.EnsureData()
    if type(gmd) ~= "table" then return false end
    if type(gmd.VirtualGroups) ~= "table" then gmd.VirtualGroups = {} end
    if type(gmd.DebugMapMarkers) ~= "table" then gmd.DebugMapMarkers = {} end
    groupId = tostring(groupId)

    local removedGroup = gmd.VirtualGroups[groupId]
    if NPCWorldDirectorBridge.PreserveWorldGroupAsVirtual(director, gmd, groupId, removedGroup, reason) then
        return true
    end
    NPCWorldDirectorBridge.DirectorOutcomeEnd(director, groupId, tostring(reason or "unknown"), removedGroup)
    gmd.VirtualGroups[groupId] = nil
    NPCWorldDirectorBridge.RemoveNpcMarkersForGroup(gmd, groupId)
    gmd.DebugMapMarkers[groupId] = nil

    NPCWorldDirectorBridge.DirectorEvent(director, "world_group_removed", removedGroup and removedGroup.x or nil, removedGroup and removedGroup.y or nil, removedGroup and removedGroup.z or 0, {groupId = groupId, reason = tostring(reason or "unknown")})
    NPCWorldDirectorBridge.SendDebugMapRemove(groupId)
    if TransmitNPCModData then TransmitNPCModData() end

    NPCWorldDirectorBridge.Log(director, NPC_WORLD_DIRECTOR_LOG_PREFIX .. " Removed world group " .. tostring(groupId) .. " reason=" .. tostring(reason or "unknown"))
    return true
end

function NPCWorldDirectorBridge.OnPhysicalGroupCleared(director, groupId)
    if not (director and director.EnsureData) then return false end

    local gmd = director.EnsureData()
    if NPCWorldDirectorBridge.RevirtualizePersistentGroup(director, gmd, groupId, "physical_group_cleared_queue_empty") then
        if TransmitNPCModData then TransmitNPCModData() end
        return true
    end
    return NPCWorldDirectorBridge.RemoveWorldGroup(director, groupId, "all_members_dead")
end

function NPCWorldDirectorBridge.UpdatePhysicalGroupMarker(director, gmd, groupId, group, alive)
    if not (gmd and gmd.DebugMapMarkers and groupId and group) then return false end

    group.count = alive
    group.virtual = false
    group.activated = true
    group.state = "physical"
    group.updatedAt = npc_wd_stage52_worldAge()
    gmd.VirtualGroups[tostring(groupId)] = group

    local marker = gmd.DebugMapMarkers[tostring(groupId)]
    if marker then
        marker.count = alive
        marker.virtual = false
        marker.active = true
        marker.dead = false
        marker.state = "physical"
        marker.updatedAt = group.updatedAt
        gmd.DebugMapMarkers[tostring(groupId)] = marker
        NPCWorldDirectorBridge.SendDebugMapUpdate(marker)
    end

    return true
end

function NPCWorldDirectorBridge.CleanupDeadPhysicalGroups(director)
    if not (director and director.EnsureData) then return false end

    local gmd = director.EnsureData()
    if type(gmd) ~= "table" then return false end
    if type(gmd.VirtualGroups) ~= "table" then gmd.VirtualGroups = {} end
    local changed = false
    local dematerialized = 0
    local dematerializeBudget = director.GetPhysicalCleanupDematerializeBudget and director.GetPhysicalCleanupDematerializeBudget() or NPCWorldDirectorBridge.GetPhysicalCleanupDematerializeBudget(director)

    if NPCStrategicAIBridge and NPCStrategicAIBridge.EnsureAllGroupsAssigned then
        local ok, result = pcall(function() return NPCStrategicAIBridge.EnsureAllGroupsAssigned(gmd) end)
        changed = (ok and result) or changed
    end

    for groupId, group in pairs(gmd.VirtualGroups) do
        if group and group.activated then
            local radius = director.GetPhysicalDeactivationRadius and director.GetPhysicalDeactivationRadius(group) or NPCWorldDirectorBridge.GetPhysicalDeactivationRadius(director, group)
            local nearPlayer = NPCWorldDirectorBridge.GetNearestPlayer(director, group.x, group.y, radius)
            if not nearPlayer then
                local canDematerialize = director.CanDematerializePhysicalGroup and director.CanDematerializePhysicalGroup(group) or NPCWorldDirectorBridge.CanDematerializePhysicalGroup(director, group)
                if dematerialized < dematerializeBudget and canDematerialize and NPCWorldDirectorBridge.DematerializeFarPhysicalGroup(director, groupId, group) then
                    changed = true
                    dematerialized = dematerialized + 1
                end
            else
                local alive = NPCWorldDirectorBridge.CountAlivePhysicalMembers(director, groupId)
                local hasPhysicalIds = false
                if type(group.physicalIds) == "table" then
                    for _, _ in pairs(group.physicalIds) do
                        hasPhysicalIds = true
                        break
                    end
                elseif group.physicalIds then
                    hasPhysicalIds = true
                end

                if alive <= 0 and (hasPhysicalIds or group.state == "physical") then
                    if NPCWorldDirectorBridge.RevirtualizePersistentGroup(director, gmd, groupId, "empty_physical_cleanup_queue_empty") then
                        changed = true
                    elseif NPCWorldDirectorBridge.PreserveWorldGroupAsVirtual(director, gmd, groupId, group, "empty_physical_cleanup") then
                        changed = true
                    else
                        NPCWorldDirectorBridge.DirectorOutcomeEnd(director, groupId, "empty_physical_cleanup", group)
                        NPCWorldDirectorBridge.DirectorEvent(director, "world_group_removed", group.x, group.y, group.z or 0, {groupId = tostring(groupId), reason = "empty_physical_cleanup"})
                        gmd.VirtualGroups[groupId] = nil
                        NPCWorldDirectorBridge.RemoveNpcMarkersForGroup(gmd, groupId)
                        if type(gmd.DebugMapMarkers) == "table" then gmd.DebugMapMarkers[groupId] = nil end
                        NPCWorldDirectorBridge.SendDebugMapRemove(tostring(groupId))
                        NPCWorldDirectorBridge.Log(director, NPC_WORLD_DIRECTOR_LOG_PREFIX .. " Cleanup removed empty physical group " .. tostring(groupId))
                        changed = true
                    end
                elseif alive > 0 and group.count ~= alive then
                    changed = NPCWorldDirectorBridge.UpdatePhysicalGroupMarker(director, gmd, groupId, group, alive) or changed
                end
            end
        end
    end

    if changed and TransmitNPCModData then
        TransmitNPCModData()
    end

    return changed
end


-- Stage 53: neutral hired mercenary follow/leash backend.
-- Keeps historical legacy world-director entry points as compatibility wrappers while
-- hired follow teleport repair and safe rematerialization live here.

function NPCWorldDirectorBridge.FindLoadedNPCZombieForBrain(_director, runtimeId, brain, groupId)
    local cell = getCell and getCell() or nil
    if not cell then return nil end

    local zombieList = cell:getZombieList()
    if not zombieList then return nil end

    local wantedRuntime = runtimeId ~= nil and tostring(runtimeId) or nil
    local wantedUid = brain and brain.uid and tostring(brain.uid) or nil
    local wantedPersistent = brain and (brain.persistentId or brain.uid) and tostring(brain.persistentId or brain.uid) or nil
    local wantedGroup = groupId and tostring(groupId) or nil

    for i=0, zombieList:size()-1 do
        local zombie = zombieList:get(i)
        if zombie then
            local runtime = NPCWorldDirectorBridge.GetZombieRuntimeId(zombie)
            if wantedRuntime and runtime ~= nil and tostring(runtime) == wantedRuntime then return zombie end

            local persistent = NPCWorldDirectorBridge.GetZombieServiceId(zombie, NPC_WORLD_DIRECTOR_LEGACY_KEYS.persistentId, NPC_WORLD_DIRECTOR_LEGACY_KEYS.persistentId)
            if wantedPersistent and persistent and tostring(persistent) == wantedPersistent then return zombie end
            if wantedUid and persistent and tostring(persistent) == wantedUid then return zombie end

            local objectGroupId = NPCWorldDirectorBridge.GetZombieServiceId(zombie, NPC_WORLD_DIRECTOR_LEGACY_KEYS.worldGroupId, NPC_WORLD_DIRECTOR_LEGACY_KEYS.worldGroupId)
            if wantedGroup and objectGroupId and tostring(objectGroupId) == wantedGroup then
                local brainId = nil
                if NPCBrainData and NPCBrainData.Get then
                    local ok, zbrain = pcall(function() return NPCBrainData.Get(zombie) end)
                    if ok and zbrain then brainId = zbrain.uid or zbrain.persistentId or zbrain.id end
                end
                if not wantedPersistent or (brainId and tostring(brainId) == wantedPersistent) then return zombie end
            end
        end
    end

    return nil
end

function NPCWorldDirectorBridge.CountLoadedNPCZombiesForGroup(director, groupId)
    local cell = getCell and getCell() or nil
    if not (cell and groupId) then return 0 end

    local wantedGroup = tostring(groupId)
    local worldAge = getGameTime and getGameTime():getWorldAgeHours() or 0
    if director then
        director._mercenaryLoadedGroupCountCache = director._mercenaryLoadedGroupCountCache or {}
        local cached = director._mercenaryLoadedGroupCountCache[wantedGroup]
        local ttl = NPCWorldDirectorBridge.MercenaryLeashLoadedCountCacheHours(director)
        if cached and ttl > 0 and worldAge - (tonumber(cached.at) or 0) <= ttl then
            return tonumber(cached.count) or 0
        end
    end

    local zombieList = cell:getZombieList()
    if not zombieList then return 0 end

    local count = 0
    for i=0, zombieList:size()-1 do
        local zombie = zombieList:get(i)
        if zombie then
            local objectGroupId = NPCWorldDirectorBridge.GetZombieServiceId(zombie, NPC_WORLD_DIRECTOR_LEGACY_KEYS.worldGroupId, NPC_WORLD_DIRECTOR_LEGACY_KEYS.worldGroupId)
            if objectGroupId and tostring(objectGroupId) == wantedGroup then
                count = count + 1
            end
        end
    end

    if director and director._mercenaryLoadedGroupCountCache then
        director._mercenaryLoadedGroupCountCache[wantedGroup] = {count=count, at=worldAge}
    end

    return count
end

function NPCWorldDirectorBridge.CollectDuplicateLoadedNPCObjectIdsForGroup(_director, groupId, player)
    local cell = getCell and getCell() or nil
    if not (cell and groupId) then return {} end

    local zombieList = cell:getZombieList()
    if not zombieList then return {} end

    local wantedGroup = tostring(groupId)
    local byPersistent = {}
    local duplicates = {}
    local px = player and tonumber(player:getX()) or nil
    local py = player and tonumber(player:getY()) or nil

    for i=0, zombieList:size()-1 do
        local zombie = zombieList:get(i)
        if zombie then
            local objectGroupId = NPCWorldDirectorBridge.GetZombieServiceId(zombie, NPC_WORLD_DIRECTOR_LEGACY_KEYS.worldGroupId, NPC_WORLD_DIRECTOR_LEGACY_KEYS.worldGroupId)
            if objectGroupId and tostring(objectGroupId) == wantedGroup then
                local runtimeId = NPCWorldDirectorBridge.GetZombieRuntimeId(zombie)
                local persistentId = NPCWorldDirectorBridge.GetZombieServiceId(zombie, NPC_WORLD_DIRECTOR_LEGACY_KEYS.persistentId, NPC_WORLD_DIRECTOR_LEGACY_KEYS.persistentId)
                if runtimeId and persistentId then
                    local zx = zombie.getX and tonumber(zombie:getX()) or nil
                    local zy = zombie.getY and tonumber(zombie:getY()) or nil
                    local dist = (px and py and zx and zy) and NPCWorldDirectorBridge.Dist(px, py, zx, zy) or 999999
                    local key = tostring(persistentId)
                    local current = byPersistent[key]
                    local candidate = {runtimeId = tostring(runtimeId), dist = dist}
                    if not current then
                        byPersistent[key] = candidate
                    elseif candidate.dist < current.dist then
                        duplicates[#duplicates + 1] = current.runtimeId
                        byPersistent[key] = candidate
                    else
                        duplicates[#duplicates + 1] = candidate.runtimeId
                    end
                end
            end
        end
    end

    return duplicates
end

function NPCWorldDirectorBridge.CleanupDuplicateLoadedMercenaries(director, gmd, groupId, group, player)
    if not (director and gmd and groupId and group and player) then return 0 end
    local ids = NPCWorldDirectorBridge.CollectDuplicateLoadedNPCObjectIdsForGroup(director, groupId, player)
    if type(ids) ~= "table" or #ids <= 0 then return 0 end

    if director.RequestNPCObjectCleanup then
        director.RequestNPCObjectCleanup({
            ids = ids,
            groupId = tostring(groupId),
            x = player:getX(),
            y = player:getY(),
            z = player:getZ(),
            radius = 160,
            immediate = true,
            reason = "mercenary_follow_duplicate_loaded_cleanup"
        })
    end

    group.lastDuplicateCleanupAt = getGameTime and getGameTime():getWorldAgeHours() or group.lastDuplicateCleanupAt
    group.lastDuplicateCleanupCount = #ids
    gmd.VirtualGroups[tostring(groupId)] = group
    return #ids
end

function NPCWorldDirectorBridge.ForceHiredMercenaryGroupNearPlayer(director, gmd, groupId, group, player, reason)
    if not (director and gmd and groupId and group and player) then return false end

    groupId = tostring(groupId)
    local px = tonumber(player:getX()) or tonumber(group.x) or 0
    local py = tonumber(player:getY()) or tonumber(group.y) or 0
    local pz = math.floor(tonumber(player:getZ()) or tonumber(group.z) or 0)
    local oldX = tonumber(group.x) or px
    local oldY = tonumber(group.y) or py
    local oldZ = tonumber(group.z) or pz
    local worldAge = getGameTime and getGameTime():getWorldAgeHours() or 0

    NPCWorldDirectorBridge.InvalidateMercenaryLoadedCountCache(director, groupId)
    NPCWorldDirectorBridge.CancelPendingGroupSpawnQueue(groupId, reason or "mercenary_follow_rematerialize_cancel_pending_spawn")

    if NPCPersistentNPCBridge and NPCPersistentNPCBridge.RestoreGroupMembers then
        pcall(function() NPCPersistentNPCBridge.RestoreGroupMembers(gmd, group) end)
    end

    local members, queueIds, avgX, avgY, avgZ = nil, nil, nil, nil, nil
    if director.GetPhysicalMemberSnapshots then
        members, queueIds, avgX, avgY, avgZ = director.GetPhysicalMemberSnapshots(groupId)
    else
        members, queueIds, avgX, avgY, avgZ = NPCWorldDirectorBridge.GetPhysicalMemberSnapshots(director, groupId)
    end
    if type(members) == "table" and #members > 0 then
        group.members = members
        group.count = #members
    elseif type(group.members) ~= "table" or #group.members <= 0 then
        return false
    end

    local cleanupIds = {}
    if type(queueIds) == "table" then
        for _, runtimeId in ipairs(queueIds) do
            local sid = tostring(runtimeId)
            cleanupIds[#cleanupIds + 1] = sid
            local brain = gmd.Queue and (gmd.Queue[runtimeId] or gmd.Queue[sid]) or nil
            local uid = brain and brain.uid or nil
            if gmd.Queue then
                gmd.Queue[runtimeId] = nil
                gmd.Queue[sid] = nil
            end
            if gmd.RuntimeToUID then gmd.RuntimeToUID[sid] = nil end
            if uid and gmd.UIDToRuntime then gmd.UIDToRuntime[tostring(uid)] = nil end
            NPCWorldDirectorBridge.RemoveNpcMarkerForRuntime(gmd, sid)
        end
    end

    if #cleanupIds > 0 then
        if director.RequestNPCObjectCleanup then
            director.RequestNPCObjectCleanup({
                ids = cleanupIds,
                groupId = groupId,
                x = avgX or oldX,
                y = avgY or oldY,
                z = avgZ or oldZ,
                radius = 160,
                reason = reason or "mercenary_follow_player_teleport_cleanup"
            })
        end
    else
        if director.RequestNPCObjectCleanup then
            director.RequestNPCObjectCleanup({
                groupId = groupId,
                persistentIds = NPCWorldDirectorBridge.GroupPersistentIds(group),
                x = oldX,
                y = oldY,
                z = oldZ,
                radius = 160,
                reason = reason or "mercenary_follow_player_teleport_cleanup"
            })
        end
    end

    group.x = px
    group.y = py
    group.z = pz
    group.activated = false
    group.virtual = true
    group.physicalIds = nil
    group.spawnPending = false
    group.spawnQueued = 0
    group.spawnFailed = false
    group.retryAfter = nil
    group.proxyHoldUntil = nil
    group.lastSpawnFailReason = nil
    group.lastActivationDeferReason = nil
    group.forceMercenaryLeashMaterialize = true
    group.state = "hired_follow_leash"
    group.isPlayerGuard = true
    group.mercenaryHired = true
    group.followPlayer = group.followPlayer or group.mercenaryHiredBy or group.master or (group.order and group.order.master)
    group.guardPlayer = nil
    group.hostile = false
    group.friendly = true
    group.updatedAt = worldAge or group.updatedAt
    group._lastMercenaryLeashForceAt = worldAge
    group._mercenaryLeashCleanupUntil = worldAge + NPCWorldDirectorBridge.MercenaryLeashRematerializeCooldownHours(director)
    group._lastFollowPlayerX = px
    group._lastFollowPlayerY = py
    group._lastFollowPlayerZ = pz
    gmd.VirtualGroups[groupId] = group

    NPCWorldDirectorBridge.RemoveNpcMarkersForGroup(gmd, groupId)
    NPCWorldDirectorBridge.UpdateHiredFollowGroupMarker(gmd, groupId, group, px, py, pz, group.count)

    if NPCPersistentNPCBridge and NPCPersistentNPCBridge.RegisterGroup then
        pcall(function() NPCPersistentNPCBridge.RegisterGroup(gmd, group) end)
    end

    if director.MaterializeGroup then
        director.MaterializeGroup(group, player)
    else
        NPCWorldDirectorBridge.MaterializeGroup(director, group, player)
    end
    return true
end

function NPCWorldDirectorBridge.PlaceHiredMercenaryRuntime(director, groupId, runtimeId, brain, player, index, reason)
    local square = NPCWorldDirectorBridge.FindHiredMercenaryLeashSquare(director, player, index)
    if not square then return false, nil end

    local x = square:getX() + 0.5
    local y = square:getY() + 0.5
    local z = square:getZ()
    local teleported = false
    local zombie = NPCWorldDirectorBridge.FindLoadedNPCZombieForBrain(director, runtimeId, brain, groupId)

    if zombie then
        if NPCEntity and NPCEntity.ClearTasks then pcall(function() NPCEntity.ClearTasks(zombie) end) end
        if zombie.setTarget then pcall(function() zombie:setTarget(nil) end) end
        if zombie.setAttackedBy then pcall(function() zombie:setAttackedBy(nil) end) end
        if zombie.clearAggroList then pcall(function() zombie:clearAggroList() end) end
        if zombie.setX then pcall(function() zombie:setX(x) end) end
        if zombie.setY then pcall(function() zombie:setY(y) end) end
        if zombie.setZ then pcall(function() zombie:setZ(z) end) end
        teleported = true
    end

    if type(brain) == "table" then
        brain.x = x
        brain.y = y
        brain.z = z
        brain.debugCoords = {x=x, y=y, z=z}
        brain.bornCoords = brain.bornCoords or {}
        brain.bornCoords.x = x
        brain.bornCoords.y = y
        brain.bornCoords.z = z
        brain.currentThreat = nil
        brain.lastThreat = nil
        brain.targetId = nil
        brain.targetKind = nil
        brain.tasks = {}
        brain.isPlayerGuard = true
        brain.followPlayer = brain.followPlayer or (brain.order and brain.order.master)
        brain.updatedAt = getGameTime and getGameTime():getWorldAgeHours() or brain.updatedAt
        if zombie and NPCPersistentNPCBridge and NPCPersistentNPCBridge.TouchFromRuntime then
            pcall(function()
                local gmd = director and director.EnsureData and director.EnsureData() or nil
                if gmd then NPCPersistentNPCBridge.TouchFromRuntime(gmd, brain, runtimeId, zombie) end
            end)
        end
        if zombie and NPCCreatorBridge and NPCCreatorBridge.ApplyHumanFacePresetToBrain then
            pcall(function() NPCCreatorBridge.ApplyHumanFacePresetToBrain(brain, zombie, brain, false) end)
        end
        if brain.fsm then
            brain.fsm.targetId = nil
            brain.fsm.targetKind = nil
            brain.fsm.currentThreat = nil
            brain.fsm.lastThreat = nil
        end
    end

    return true, {
        id = brain and (brain.id or runtimeId) or runtimeId,
        runtimeId = runtimeId,
        persistentId = brain and (brain.persistentId or brain.uid) or nil,
        groupId = groupId,
        x = x,
        y = y,
        z = z,
        reason = reason or "mercenary_follow_leash"
    }, teleported
end

function NPCWorldDirectorBridge.EnforceHiredMercenaryFollowLeash(director, reason)
    if not director then return false end
    if director.MERCENARY_FOLLOW_LEASH_ENABLED == false then return false end

    local gmd = director.EnsureData and director.EnsureData() or nil
    if not (gmd and gmd.VirtualGroups) then return false end

    local changed = false
    local worldAge = getGameTime and getGameTime():getWorldAgeHours() or 0
    local teleportDistance = tonumber(director.MERCENARY_FOLLOW_TELEPORT_DISTANCE) or 44
    local virtualDistance = tonumber(director.MERCENARY_FOLLOW_VIRTUAL_TELEPORT_DISTANCE) or 56
    local hardRestoreDistance = tonumber(director.MERCENARY_FOLLOW_HARD_RESTORE_DISTANCE) or 140
    if hardRestoreDistance < teleportDistance + 32 then hardRestoreDistance = teleportDistance + 32 end

    for groupId, group in pairs(gmd.VirtualGroups) do
        if NPCWorldDirectorBridge.IsHiredFollowGroup(group) then
            groupId = tostring(groupId)
            group.isPlayerGuard = true
            group.mercenaryHired = true
            group.followPlayer = group.followPlayer or group.mercenaryHiredBy or (group.order and group.order.master)
            group.guardPlayer = nil
            group.hostile = false
            group.friendly = true

            local ownerId = NPCWorldDirectorBridge.HiredFollowOwnerId(group)
            local player = NPCWorldDirectorBridge.FindPlayerByMercenaryOwner(ownerId)
            if player then
                local px = tonumber(player:getX()) or 0
                local py = tonumber(player:getY()) or 0
                local pz = math.floor(tonumber(player:getZ()) or 0)
                local lastPx = tonumber(group._lastFollowPlayerX)
                local lastPy = tonumber(group._lastFollowPlayerY)
                local jumpDistance = (lastPx and lastPy) and NPCWorldDirectorBridge.Dist(lastPx, lastPy, px, py) or 0
                local playerTeleportDistance = tonumber(director.MERCENARY_FOLLOW_PLAYER_TELEPORT_DISTANCE) or 72
                local playerTeleported = jumpDistance > playerTeleportDistance
                group._lastFollowPlayerX = px
                group._lastFollowPlayerY = py
                group._lastFollowPlayerZ = pz
                local alive, cx, cy, cz = nil, nil, nil, nil
                if director.GetPhysicalGroupRuntimeInfo then
                    alive, cx, cy, cz = director.GetPhysicalGroupRuntimeInfo(groupId)
                else
                    alive, cx, cy, cz = NPCWorldDirectorBridge.GetPhysicalGroupRuntimeInfo(director, groupId)
                end
                alive = tonumber(alive) or 0
                local loadedAlive = alive > 0 and NPCWorldDirectorBridge.CountLoadedNPCZombiesForGroup(director, groupId) or 0
                local dist = nil
                if cx and cy then dist = NPCWorldDirectorBridge.Dist(cx, cy, px, py) end

                local hireGraceUntil = tonumber(group._mercenaryHireGraceUntil) or 0
                local hireGraceActive = hireGraceUntil > worldAge and not playerTeleported
                if not hireGraceActive and loadedAlive > alive and alive > 0 then
                    local cleaned = NPCWorldDirectorBridge.CleanupDuplicateLoadedMercenaries(director, gmd, groupId, group, player)
                    if cleaned > 0 then changed = true end
                end

                local spawnPending = group.spawnPending == true or (tonumber(group.spawnQueued) or 0) > 0 or NPCWorldDirectorBridge.HasPendingGroupSpawnQueue(groupId)
                local cooldownUntil = tonumber(group._mercenaryLeashCleanupUntil) or 0
                local rematerializeCoolingDown = cooldownUntil > worldAge
                local cooldownBlocksRematerialize = rematerializeCoolingDown and not playerTeleported
                local needsSafeRematerialize = alive > 0 and not spawnPending and not cooldownBlocksRematerialize and not hireGraceActive and (playerTeleported or loadedAlive < alive or loadedAlive <= 0 or (dist and dist > hardRestoreDistance))

                if alive > 0 and not needsSafeRematerialize and group.activated and not hireGraceActive then
                    for _, brain in pairs(gmd.Queue or {}) do
                        local brainGroupId = NPCWorldDirectorBridge.BrainGroupId(brain)
                        if type(brain) == "table" and brainGroupId and tostring(brainGroupId) == groupId then
                            local bx, by = NPCWorldDirectorBridge.BrainCoords(brain)
                            local memberDist = (bx and by) and NPCWorldDirectorBridge.Dist(bx, by, px, py) or 0
                            if memberDist > hardRestoreDistance then
                                needsSafeRematerialize = true
                                break
                            elseif memberDist > teleportDistance then
                                brain.followPlayer = ownerId
                                brain.isPlayerGuard = true
                                brain.guardPlayer = nil
                                brain.order = type(brain.order) == "table" and brain.order or {name="Follow"}
                                brain.order.name = "Follow"
                                brain.order.master = brain.order.master or ownerId
                                brain.order.followDistance = brain.order.followDistance or 3.0
                                brain.order.fireMode = brain.order.fireMode or brain.fireMode or "Defensive"
                                brain.forceFollowRefreshAt = worldAge
                            end
                        end
                    end
                end

                if alive > 0 and needsSafeRematerialize then
                    -- Never move live hired NPC IsoZombie objects directly during follow/leash repair.
                    -- Fast travel, admin teleports and chunk unload/reload can make direct setX/setY
                    -- leave clients with corpse/zombie network objects. The safe path is always:
                    -- snapshot persistent brains, remove old physical objects, then spawn a fresh
                    -- hired squad near the owner's currently loaded square.
                    if NPCWorldDirectorBridge.ForceHiredMercenaryGroupNearPlayer(director, gmd, groupId, group, player, reason or (playerTeleported and "mercenary_follow_player_teleport" or "mercenary_follow_leash_resync")) then
                        changed = true
                    end
                elseif group.activated and alive > 0 then
                    local idx = 1
                    local sumX, sumY, sumZ = 0, 0, 0
                    for qid, brain in pairs(gmd.Queue or {}) do
                        local brainGroupId = NPCWorldDirectorBridge.BrainGroupId(brain)
                        if type(brain) == "table" and brainGroupId and tostring(brainGroupId) == groupId then
                            brain.isPlayerGuard = true
                            brain.followPlayer = ownerId
                            gmd.Queue[qid] = brain
                            local nx, ny, nz = NPCWorldDirectorBridge.BrainCoords(brain)
                            if nx and ny then
                                sumX = sumX + nx
                                sumY = sumY + ny
                                sumZ = sumZ + (nz or 0)
                            end
                            idx = idx + 1
                        end
                    end

                    if cx and cy then
                        group.x = cx or group.x
                        group.y = cy or group.y
                        group.z = cz or group.z or pz
                        group.activated = true
                        group.virtual = false
                        group.state = "physical"
                        group.updatedAt = worldAge
                        gmd.VirtualGroups[groupId] = group
                    end
                else
                    local gx = tonumber(group.x) or px
                    local gy = tonumber(group.y) or py
                    local oldZ = tonumber(group.z) or pz
                    local groupDist = NPCWorldDirectorBridge.Dist(gx, gy, px, py)
                    local spawnPending = group.spawnPending == true or (tonumber(group.spawnQueued) or 0) > 0 or NPCWorldDirectorBridge.HasPendingGroupSpawnQueue(groupId)
                    local cooldownUntil = tonumber(group._mercenaryLeashCleanupUntil) or 0
                    local rematerializeCoolingDown = cooldownUntil > worldAge
                    local cooldownBlocksRematerialize = rematerializeCoolingDown and not playerTeleported
                    local needsVirtualResync = groupDist > virtualDistance or group.virtual == true or not group.activated
                    if playerTeleported and groupDist > teleportDistance then needsVirtualResync = true end
                    if (not playerTeleported) and group.activated == true and groupDist <= hardRestoreDistance then needsVirtualResync = false end
                    if needsVirtualResync and not spawnPending and not cooldownBlocksRematerialize then
                        NPCWorldDirectorBridge.InvalidateMercenaryLoadedCountCache(director, groupId)
                        NPCWorldDirectorBridge.CancelPendingGroupSpawnQueue(groupId, "mercenary_follow_virtual_resync_cancel_pending_spawn")
                        if NPCPersistentNPCBridge and NPCPersistentNPCBridge.RestoreGroupMembers then
                            pcall(function() NPCPersistentNPCBridge.RestoreGroupMembers(gmd, group) end)
                        end

                        group.x = px
                        group.y = py
                        group.z = pz
                        group.activated = false
                        group.virtual = true
                        group.state = "hired_follow_leash"
                        group.spawnFailed = false
                        group.retryAfter = nil
                        group.proxyHoldUntil = nil
                        group.lastActivationDeferReason = nil
                        group.forceMercenaryLeashMaterialize = true
                        group._lastMercenaryLeashForceAt = worldAge
                        group._mercenaryLeashCleanupUntil = worldAge + NPCWorldDirectorBridge.MercenaryLeashRematerializeCooldownHours(director)
                        group.updatedAt = worldAge
                        gmd.VirtualGroups[groupId] = group
                        NPCWorldDirectorBridge.UpdateHiredFollowGroupMarker(gmd, groupId, group, px, py, pz, group.count)

                        if director.RequestNPCObjectCleanup then
                            director.RequestNPCObjectCleanup({
                                groupId = groupId,
                                persistentIds = NPCWorldDirectorBridge.GroupPersistentIds(group),
                                x = gx,
                                y = gy,
                                z = oldZ,
                                radius = 128,
                                reason = "mercenary_follow_leash_resync_cleanup"
                            })
                        end

                        if director.MaterializeGroup then
                            director.MaterializeGroup(group, player)
                        else
                            NPCWorldDirectorBridge.MaterializeGroup(director, group, player)
                        end
                        changed = true
                    end
                end
            end
        end
    end

    if changed and TransmitNPCModData then
        TransmitNPCModData()
    end

    return changed
end

-- Stage 55: neutral virtual-group movement/update backend.
-- The compatibility facade keeps legacy world-director entry points, but target
-- selection, relocation, director-brain retargeting and marker refresh live here.

function NPCWorldDirectorBridge.EnsureVirtualTarget(director, group)
    if not group then return end

    if group.economyMissionId then
        if (not group.targetX or not group.targetY) and group.missionTargetX and group.missionTargetY then
            group.targetX = group.missionTargetX
            group.targetY = group.missionTargetY
            group.targetZ = group.missionTargetZ or 0
        end
        if group.targetX and group.targetY then
            return
        end
    end

    if NPCWorldDirectorBridge.IsBaseOwnedGlobalSquad and NPCWorldDirectorBridge.IsBaseOwnedGlobalSquad(group) then
        local gmd = director and director.EnsureData and director.EnsureData() or nil
        local now = wd_worldAgeHoursSafe()
        local changed = NPCWorldDirectorBridge.RefreshBaseOwnedRouteTarget and NPCWorldDirectorBridge.RefreshBaseOwnedRouteTarget(director, gmd, group, now, "ensure_target") or false
        if changed or (group.targetX and group.targetY) then return end
    end

    if group.roadPatrol then
        if NPCWorldDirectorBridge.IsRecruitableBlueMercenaryPatrol(group) and group.targetX and group.targetY then
            local now = wd_worldAgeHoursSafe()
            local lastRouteAt = tonumber(group.blueMercenaryRouteAt) or tonumber(group.createdAt) or now
            local cooldown = tonumber(director.BLUE_MERCENARY_PATROL_RETARGET_COOLDOWN_HOURS) or 1.50
            if now - lastRouteAt < cooldown then
                return
            end
        end

        local routeReached = true
        if group.routeX and group.routeY then
            routeReached = NPCWorldDirectorBridge.Dist(group.x, group.y, group.routeX, group.routeY) <= 120
        end

        if routeReached then
            local route = NPCWorldDirectorBridge.GetNearbyRoadPoint(director, group.x, group.y, director.ROAD_PATROL_TARGET_RADIUS)
            if route then
                group.routeX = route.x
                group.routeY = route.y
                group.routeZ = route.z or 0
            end
        end

        if group.targetX and group.targetY then
            local distToStep = NPCWorldDirectorBridge.Dist(group.x, group.y, group.targetX, group.targetY)
            if distToStep > 45 then
                return
            end
        end

        local step = nil
        if NPCFlowFieldBridge and NPCFlowFieldBridge.SuggestVirtualStep then
            local okFlow, flowStep = pcall(function() return NPCFlowFieldBridge.SuggestVirtualStep(group) end)
            if okFlow and flowStep and flowStep.x and flowStep.y then step = flowStep end
        end
        if not step and group.routeX and group.routeY and NPCRoadNavBridge and NPCRoadNavBridge.FindNearbyWorldRoadStepToward then
            step = NPCRoadNavBridge.FindNearbyWorldRoadStepToward(group.x, group.y, group.routeX, group.routeY, director.ROAD_PATROL_VIRTUAL_STEP_RADIUS, director.VIRTUAL_TARGET_ATTEMPTS)
        end
        if step and NPCRoadNavBridge and NPCRoadNavBridge.IsBlockedSegment and NPCRoadNavBridge.IsBlockedSegment(group.x, group.y, step.x, step.y, 8) then
            step = nil
        end
        step = step or NPCWorldDirectorBridge.GetNearbyRoadPoint(director, group.x, group.y, director.ROAD_PATROL_VIRTUAL_STEP_RADIUS)

        if step then
            group.targetX = step.x
            group.targetY = step.y
            group.targetZ = step.z or 0
            group.targetClass = "road_step"
            group.directorBias = step.directorBias or group.directorBias
            group.directorBiasReason = step.directorBiasReason or group.directorBiasReason
            if NPCWorldDirectorBridge.IsRecruitableBlueMercenaryPatrol(group) then
                group.blueMercenaryRouteAt = wd_worldAgeHoursSafe()
            end
        end
        return
    end

    if group.targetClass == "base_capture" and group.targetBaseId and group.targetX and group.targetY then
        return
    end

    if group.targetX and group.targetY then
        local distToTarget = NPCWorldDirectorBridge.Dist(group.x, group.y, group.targetX, group.targetY)
        if distToTarget > 80 then
            return
        end
    end

    local target = nil
    if NPCFlowFieldBridge and NPCFlowFieldBridge.SuggestVirtualStep then
        local okFlow, flowTarget = pcall(function() return NPCFlowFieldBridge.SuggestVirtualStep(group) end)
        if okFlow and flowTarget and flowTarget.x and flowTarget.y then target = flowTarget end
    end
    if not target and NPCInfluenceFieldBridge and NPCInfluenceFieldBridge.SuggestVirtualTarget then
        target = NPCInfluenceFieldBridge.SuggestVirtualTarget(group)
    end
    target = target or NPCWorldDirectorBridge.GetNearbyPreferredPoint(director, group.x, group.y, director.VIRTUAL_TARGET_RADIUS)
    if target then
        group.targetX = target.x
        group.targetY = target.y
        group.targetZ = target.z or 0
        group.targetClass = target.spawnClass or "roam"
        group.directorBias = target.directorBias or group.directorBias
        group.directorBiasReason = target.directorBiasReason or group.directorBiasReason
        group.influenceScore = target.influenceScore or target.score or group.influenceScore
    end
end

function NPCWorldDirectorBridge.IsVirtualGroupUrbanPlaced(director, group)
    if not group then return false end
    if group.roadPatrol then
        local ok = NPCWorldDirectorBridge.IsUrbanRoadPatrolPoint(director, group.x, group.y)
        return ok == true
    end

    local ok = NPCWorldDirectorBridge.IsUrbanWorldPoint(director, group.x, group.y)
    return ok == true
end

function NPCWorldDirectorBridge.RepairVirtualGroupLocation(director, group)
    if not group or group.activated then return false end

    if NPCWorldDirectorBridge.RepairBaseOwnedGroupLocation then
        local protectedRepair = NPCWorldDirectorBridge.RepairBaseOwnedGroupLocation(director, group, wd_worldAgeHoursSafe())
        if protectedRepair ~= nil then return protectedRepair == true end
    end

    if NPCWorldDirectorBridge.IsVirtualGroupUrbanPlaced(director, group) then
        local score, reason = NPCWorldDirectorBridge.ScoreWorldPoint(director, group.x, group.y)
        group.spawnClass = group.spawnClass or reason
        group.zoneScore = tonumber(group.zoneScore) or score or 0
        if group.roadPatrol then
            local _, _, _, affinity = NPCWorldDirectorBridge.IsUrbanRoadPatrolPoint(director, group.x, group.y)
            group.urbanAffinity = affinity or group.urbanAffinity or 0
        end
        return false
    end

    if group.inBattle then
        group.inBattle = false
        group.battleId = nil
        group.enemyGroupId = nil
        group.lastBattleAt = nil
        for _, member in pairs(group.members or {}) do
            member.virtualBattle = false
            member.battleEnemyGroupId = nil
            member.enemyGroupId = nil
        end
    end

    local point = nil
    if group.roadPatrol then
        point = NPCWorldDirectorBridge.GetRandomRoadPoint(director)
    else
        point = NPCWorldDirectorBridge.GetRandomWorldPoint(director)
    end
    if not point then return false end

    local target = nil
    local stepTarget = nil
    if group.roadPatrol then
        target = NPCWorldDirectorBridge.GetNearbyRoadPoint(director, point.x, point.y, director.ROAD_PATROL_TARGET_RADIUS)
        if target and NPCRoadNavBridge and NPCRoadNavBridge.FindNearbyWorldRoadStepToward then
            stepTarget = NPCRoadNavBridge.FindNearbyWorldRoadStepToward(point.x, point.y, target.x, target.y, director.ROAD_PATROL_VIRTUAL_STEP_RADIUS, director.VIRTUAL_TARGET_ATTEMPTS)
        end
    end
    target = target or NPCWorldDirectorBridge.GetNearbyPreferredPoint(director, point.x, point.y, director.VIRTUAL_TARGET_RADIUS)
    stepTarget = stepTarget or target

    group.x = point.x
    group.y = point.y
    group.z = point.z or 0
    group.preciseX = tonumber(group.x) or 0
    group.preciseY = tonumber(group.y) or 0
    group.spawnClass = point.spawnClass or "urban"
    group.zoneScore = point.zoneScore or 0
    group.urbanAffinity = point.urbanAffinity or 0
    group.routeX = group.roadPatrol and target and target.x or nil
    group.routeY = group.roadPatrol and target and target.y or nil
    group.routeZ = group.roadPatrol and target and target.z or nil
    group.targetX = stepTarget and stepTarget.x or point.x
    group.targetY = stepTarget and stepTarget.y or point.y
    group.targetZ = stepTarget and stepTarget.z or 0
    group.targetClass = group.roadPatrol and "road_step" or (target and target.spawnClass or "urban_roam")
    group.state = group.roadPatrol and (group.hostile and "red_road_patrol" or "green_road_patrol") or "relocated_urban"

    NPCWorldDirectorBridge.Log(director, "[NPCWorldDirector] Relocated rural virtual group " .. tostring(group.id) .. " to urban point " .. tostring(group.x) .. "," .. tostring(group.y) .. " class=" .. tostring(group.spawnClass))

    return true
end

function NPCWorldDirectorBridge.TryDirectorRetargetGroup(director, group, worldAge)
    if not group or group.activated then return false end
    if group.inBattle or group.enemyGroupId or group.economyMissionId then return false end
    if group.targetClass == "base_capture" or group.targetBaseId then return false end
    if group.bountyHunter or group.targetClass == "bounty_hunt" then return false end
    if group.leaderId or group.isFactionLeader then return false end
    if group.economyConvoy or group.convoyId then return false end
    if NPCWorldDirectorBridge.IsBaseOwnedGlobalSquad and NPCWorldDirectorBridge.IsBaseOwnedGlobalSquad(group) then return false end
    if NPCWorldDirectorBridge.IsRecruitableBlueMercenaryPatrol(group) then
        local now = tonumber(worldAge) or wd_worldAgeHoursSafe()
        local dwellUntil = tonumber(group.blueMercenaryMapDwellUntil) or 0
        if dwellUntil > 0 and now < dwellUntil then return false end
        local lastRouteAt = tonumber(group.blueMercenaryRouteAt) or tonumber(group.directorRetargetAt) or tonumber(group.createdAt) or now
        if now - lastRouteAt < (tonumber(director.BLUE_MERCENARY_PATROL_RETARGET_COOLDOWN_HOURS) or 1.50) then return false end
    end

    local anchor = NPCWorldDirectorBridge.DirectorRetargetAnchor(director, group, group.roadPatrol and "road" or "roam")
    if not anchor or not anchor.x or not anchor.y then return false end

    local target = nil
    local stepTarget = nil
    if group.roadPatrol then
        target = NPCWorldDirectorBridge.GetNearbyRoadPoint(director, anchor.x, anchor.y, director.ROAD_PATROL_TARGET_RADIUS)
        if target and NPCRoadNavBridge and NPCRoadNavBridge.FindNearbyWorldRoadStepToward then
            stepTarget = NPCRoadNavBridge.FindNearbyWorldRoadStepToward(group.x, group.y, target.x, target.y, director.ROAD_PATROL_VIRTUAL_STEP_RADIUS, director.VIRTUAL_TARGET_ATTEMPTS)
        end
        if not stepTarget then return false end

        group.routeX = target.x
        group.routeY = target.y
        group.routeZ = target.z or 0
        group.targetX = stepTarget.x
        group.targetY = stepTarget.y
        group.targetZ = stepTarget.z or 0
        group.targetClass = "director_road_step"
    else
        target = NPCWorldDirectorBridge.GetNearbyPreferredPoint(director, anchor.x, anchor.y, director.VIRTUAL_TARGET_RADIUS)
        if not target then return false end

        group.targetX = target.x
        group.targetY = target.y
        group.targetZ = target.z or 0
        group.targetClass = "director_retarget"
    end

    group.directorRetargetAt = worldAge or getGameTime():getWorldAgeHours()
    group.directorRetargetReason = anchor.reason or "memory"
    group.directorRetargetScore = math.floor((tonumber(anchor.score) or 0) * 100) / 100
    group.directorBias = target and target.directorBias or group.directorBias
    group.directorBiasReason = target and target.directorBiasReason or group.directorBiasReason

    NPCWorldDirectorBridge.DirectorEvent(director, "director_group_retargeted", group.x, group.y, group.z or 0, {
        groupId = tostring(group.id or ""),
        reason = tostring(group.directorRetargetReason),
        score = group.directorRetargetScore,
        roadPatrol = group.roadPatrol or false
    })
    NPCWorldDirectorBridge.DirectorOutcomeStart(director, "retarget", group, {
        reason = tostring(group.directorRetargetReason),
        score = group.directorRetargetScore,
        roadPatrol = group.roadPatrol or false,
        targetClass = tostring(group.targetClass or "")
    })
    NPCWorldDirectorBridge.DirectorCellCooldown(director, "retarget", group.targetX or group.x, group.targetY or group.y, group.targetZ or group.z or 0, {
        groupId = tostring(group.id or ""),
        reason = tostring(group.directorRetargetReason or ""),
        score = group.directorRetargetScore,
        targetClass = tostring(group.targetClass or "")
    })

    return true
end

function NPCWorldDirectorBridge.ShouldVirtualGroupFollowRoads(group)
    if type(group) ~= "table" then return false end
    if group.disableRoadRouting == true then return false end
    if group.roadPatrol == true or group.roadBias == true or group.preferRoads == true then return true end
    if group.counterIntelHunter == true then return true end
    if group.routeOwnerBaseId or group.homeBaseId or group.baseId then return true end
    if group.strategicActivityType or group.strategicActivityId then return true end
    local targetClass = tostring(group.targetClass or "")
    if targetClass == "base_capture" or targetClass == "front_patrol" or targetClass == "activity" or targetClass == "road_step" then return true end
    return false
end

function NPCWorldDirectorBridge.ResolveVirtualRoadMoveTarget(director, group, x, y, targetX, targetY, worldAge)
    if not (director and group and director.VIRTUAL_ROAD_FOLLOWING_ENABLED ~= false) then return targetX, targetY, false end
    if not (NPCRoadNavBridge and NPCRoadNavBridge.FindNearbyWorldRoadStepToward) then return targetX, targetY, false end
    if not NPCWorldDirectorBridge.ShouldVirtualGroupFollowRoads(group) then return targetX, targetY, false end

    x = tonumber(x); y = tonumber(y); targetX = tonumber(targetX); targetY = tonumber(targetY)
    if not (x and y and targetX and targetY) then return targetX, targetY, false end

    local distToFinal = NPCWorldDirectorBridge.Dist(x, y, targetX, targetY)
    local minDistance = tonumber(director.VIRTUAL_ROAD_FOLLOWING_MIN_DISTANCE) or 95
    local finalApproach = tonumber(director.VIRTUAL_ROAD_FOLLOWING_FINAL_APPROACH_DISTANCE) or 70
    if distToFinal <= finalApproach or distToFinal < minDistance then return targetX, targetY, false end

    local now = tonumber(worldAge) or wd_worldAgeHoursSafe()
    local reuseDistance = tonumber(director.VIRTUAL_ROAD_FOLLOWING_STEP_REUSE_DISTANCE) or 18
    local expireHours = tonumber(director.VIRTUAL_ROAD_FOLLOWING_STEP_EXPIRE_HOURS) or 0.12
    local stepX = tonumber(group.virtualRoadStepX)
    local stepY = tonumber(group.virtualRoadStepY)
    if stepX and stepY then
        local stepAge = now - (tonumber(group.virtualRoadStepAt) or now)
        local stillUseful = stepAge <= expireHours and NPCWorldDirectorBridge.Dist(x, y, stepX, stepY) > reuseDistance and NPCWorldDirectorBridge.Dist(stepX, stepY, targetX, targetY) < distToFinal + 24
        if stillUseful then
            return stepX, stepY, true
        end
        group.virtualRoadStepX = nil
        group.virtualRoadStepY = nil
        group.virtualRoadStepAt = nil
    end

    local radius = tonumber(director.ROAD_PATROL_VIRTUAL_STEP_RADIUS) or 360
    local attempts = tonumber(director.VIRTUAL_TARGET_ATTEMPTS) or 240
    local okStep, step = pcall(function()
        return NPCRoadNavBridge.FindNearbyWorldRoadStepToward(x, y, targetX, targetY, radius, attempts)
    end)
    if okStep and step and step.x and step.y then
        local sx = tonumber(step.x)
        local sy = tonumber(step.y)
        if sx and sy and NPCWorldDirectorBridge.Dist(sx, sy, targetX, targetY) < distToFinal + 24 then
            group.virtualRoadStepX = sx
            group.virtualRoadStepY = sy
            group.virtualRoadStepAt = now
            group.mapRouteX = targetX
            group.mapRouteY = targetY
            group.mapRouteZ = group.targetZ or 0
            group.roadFollowing = true
            return sx, sy, true
        end
    end

    return targetX, targetY, false
end


function NPCWorldDirectorBridge.AdvanceVirtualGroupMapMotion(director, group, worldAge)
    if not group or group.activated or group.inBattle then return false end

    if group.preciseX == nil then group.preciseX = tonumber(group.x) or 0 end
    if group.preciseY == nil then group.preciseY = tonumber(group.y) or 0 end

    if not group.targetX or not group.targetY then
        NPCWorldDirectorBridge.EnsureVirtualTarget(director, group)
        if not group.targetX or not group.targetY then return false end
    end

    local lastUpdate = tonumber(group.updatedAt) or worldAge
    local dt = worldAge - lastUpdate
    if dt <= 0 then return false end
    if dt > 0.25 then dt = 0.25 end

    local x = tonumber(group.preciseX) or tonumber(group.x) or 0
    local y = tonumber(group.preciseY) or tonumber(group.y) or 0
    local moveX, moveY, intermediateRoadStep = NPCWorldDirectorBridge.ResolveVirtualRoadMoveTarget(director, group, x, y, group.targetX, group.targetY, worldAge)
    local dx = moveX - x
    local dy = moveY - y
    local dist = math.sqrt(dx * dx + dy * dy)

    if dist < 1 then
        group.preciseX = tonumber(moveX) or x
        group.preciseY = tonumber(moveY) or y
        group.x = math.floor(group.preciseX)
        group.y = math.floor(group.preciseY)
        group.updatedAt = worldAge
        if intermediateRoadStep then
            group.virtualRoadStepX = nil
            group.virtualRoadStepY = nil
            group.virtualRoadStepAt = nil
            return true
        end
        if group.economyMissionId then
            group.state = "eco_arrived"
            return true
        end
        if group.targetClass == "base_capture" and group.targetBaseId then
            group.state = "holding_base"
            return true
        end
        if group.targetClass == "strike_staging" then
            group.state = "activity_assemble_strike"
            return true
        end
        group.targetX = nil
        group.targetY = nil
        NPCWorldDirectorBridge.EnsureVirtualTarget(director, group)
        return true
    end

    local baseSpeed = tonumber(director.VIRTUAL_MOVE_SPEED_TILES_PER_HOUR) or 120
    local speed = tonumber(group.speed) or baseSpeed
    if speed <= 0 then speed = baseSpeed end
    if NPCWorldDirectorBridge.IsRecruitableBlueMercenaryPatrol(group) then
        local blueSpeed = tonumber(director.BLUE_MERCENARY_PATROL_MOVE_SPEED) or 22
        local blueCap = blueSpeed + 12
        if speed > blueCap then speed = blueCap end
    else
        if speed < baseSpeed then speed = baseSpeed end
        local speedCap = group.roadPatrol and (baseSpeed + 240) or (baseSpeed + 120)
        if speed > speedCap then speed = speedCap end
    end

    local step = speed * dt
    if step > dist then step = dist end

    local newX = x + (dx / dist) * step
    local newY = y + (dy / dist) * step
    group.preciseX = newX
    group.preciseY = newY
    group.x = math.floor(newX)
    group.y = math.floor(newY)
    group.z = 0
    group.updatedAt = worldAge
    if group.economyMissionId then
        group.state = "eco_" .. tostring(group.missionType or "mission")
    elseif group.strategicActivityState then
        group.state = group.strategicActivityState
    else
        group.state = group.roadPatrol and (group.hostile and "red_road_patrol" or "green_road_patrol") or (group.homeBaseId and "base_patrol" or "roaming")
    end

    return true
end

function NPCWorldDirectorBridge.UpdateVirtualGroup(director, group, worldAge, opts)
    if not group or group.activated then return false end
    opts = type(opts) == "table" and opts or {}
    if opts.forceLOD ~= true and NPCAILODTraderBridge and NPCAILODTraderBridge.ShouldUpdateVirtualGroup then
        local okLOD, allowed = pcall(function() return NPCAILODTraderBridge.ShouldUpdateVirtualGroup(group, worldAge) end)
        if okLOD and allowed == false then return false end
    end
    if group.inBattle then
        group.updatedAt = worldAge
        group.state = "road_battle"
        return true
    end

    local gmd = director.EnsureData and director.EnsureData() or nil
    if NPCStrategicAIBridge and NPCStrategicAIBridge.EnsureGroupBase then
        NPCStrategicAIBridge.EnsureGroupBase(gmd, group)
    end
    if NPCWorldDirectorBridge.EnsureBaseOwnedGroup then
        NPCWorldDirectorBridge.EnsureBaseOwnedGroup(director, gmd, group, worldAge, "virtual_update")
    end
    if NPCStrategicAIBridge and NPCStrategicAIBridge.EvaluateGroupCombatPower then
        NPCStrategicAIBridge.EvaluateGroupCombatPower(gmd, group)
    end

    NPCWorldDirectorBridge.EnsureVirtualTarget(director, group)
    if not group.targetX or not group.targetY then return false end

    local lastUpdate = tonumber(group.updatedAt) or worldAge
    local dt = worldAge - lastUpdate
    if dt <= 0 then return false end
    if dt > 1.0 then dt = 1.0 end

    local x = tonumber(group.preciseX) or tonumber(group.x) or 0
    local y = tonumber(group.preciseY) or tonumber(group.y) or 0
    local moveX, moveY, intermediateRoadStep = NPCWorldDirectorBridge.ResolveVirtualRoadMoveTarget(director, group, x, y, group.targetX, group.targetY, worldAge)
    local dx = moveX - x
    local dy = moveY - y
    local dist = math.sqrt(dx * dx + dy * dy)

    if dist < 1 then
        group.preciseX = tonumber(moveX) or x
        group.preciseY = tonumber(moveY) or y
        group.x = math.floor(group.preciseX)
        group.y = math.floor(group.preciseY)
        if intermediateRoadStep then
            group.virtualRoadStepX = nil
            group.virtualRoadStepY = nil
            group.virtualRoadStepAt = nil
            group.updatedAt = worldAge
            return true
        end
        if group.economyMissionId then
            group.state = "eco_arrived"
            group.updatedAt = worldAge
            return true
        end
        if group.targetClass == "base_capture" and group.targetBaseId then
            group.state = "holding_base"
            group.updatedAt = worldAge
            return true
        end
        if group.targetClass == "strike_staging" then
            group.state = "activity_assemble_strike"
            group.updatedAt = worldAge
            return true
        end
        group.targetX = nil
        group.targetY = nil
        NPCWorldDirectorBridge.EnsureVirtualTarget(director, group)
        return false
    end

    local baseSpeed = tonumber(director.VIRTUAL_MOVE_SPEED_TILES_PER_HOUR) or 120
    local speed = tonumber(group.speed) or baseSpeed
    if speed <= 0 then speed = baseSpeed end
    if NPCWorldDirectorBridge.IsRecruitableBlueMercenaryPatrol(group) then
        local blueSpeed = tonumber(director.BLUE_MERCENARY_PATROL_MOVE_SPEED) or 22
        local blueCap = blueSpeed + 12
        if speed > blueCap then speed = blueCap end
    else
        if speed < baseSpeed then speed = baseSpeed end
        local speedCap = group.roadPatrol and (baseSpeed + 240) or (baseSpeed + 120)
        if speed > speedCap then speed = speedCap end
    end
    local step = speed * dt
    if step > dist then step = dist end

    local newX = x + (dx / dist) * step
    local newY = y + (dy / dist) * step
    group.preciseX = newX
    group.preciseY = newY
    group.x = math.floor(newX)
    group.y = math.floor(newY)
    group.z = 0
    group.updatedAt = worldAge
    if group.economyMissionId then
        group.state = "eco_" .. tostring(group.missionType or "mission")
    elseif group.strategicActivityState then
        group.state = group.strategicActivityState
    else
        group.state = group.roadPatrol and (group.hostile and "red_road_patrol" or "green_road_patrol") or (group.homeBaseId and "base_patrol" or "roaming")
    end

    if NPCStrategicAIBridge and NPCStrategicAIBridge.EvaluateGroupCombatPower then
        NPCStrategicAIBridge.EvaluateGroupCombatPower(gmd, group)
    end

    return true
end

function NPCWorldDirectorBridge.BuildVirtualGroupUpdateMarker(gmd, groupId, group)
    local marker = gmd.DebugMapMarkers[groupId] or {}
    marker.id = groupId
    marker.markerType = "group"
    marker.x = group.x
    marker.y = group.y
    marker.z = group.z or 0
    marker.name = NPCWorldDirectorBridge.GetVirtualGroupDisplayName(groupId, group, marker.name)
    marker.displayName = marker.name
    marker.count = group.count
    marker.hostile = group.hostile
    marker.friendly = not group.hostile
    marker.program = group.program and group.program.name or "Raider"
    marker.virtual = true
    marker.active = false
    marker.dead = false
    marker.state = group.state or "roaming"
    marker.spawnClass = group.spawnClass
    marker.zoneScore = group.zoneScore or 0
    marker.urbanAffinity = group.urbanAffinity or 0
    marker.roadPatrol = group.roadPatrol or false
    marker.patrolColor = group.patrolColor
    marker.mercenary = group.mercenary or false
    marker.mercenaryElite = group.mercenaryElite or false
    marker.hireable = group.hireable or false
    marker.recruitable = group.recruitable or false
    marker.blueMercenaryMapDwellUntil = group.blueMercenaryMapDwellUntil
    marker.encounterId = group.encounterId
    marker.inBattle = group.inBattle or false
    marker.battleId = group.battleId
    marker.enemyGroupId = group.enemyGroupId
    marker.battleCasualties = group.battleCasualties or 0
    marker.targetX = group.targetX
    marker.targetY = group.targetY
    marker.economyMissionId = group.economyMissionId
    marker.missionType = group.missionType
    marker.missionState = group.economyMissionId and group.state or nil
    marker.resource = group.missionResource
    marker.originBaseId = group.missionOriginBaseId or group.originBaseId
    marker.targetBaseId = group.missionTargetBaseId or group.targetBaseId
    marker.homeBaseId = group.homeBaseId
    marker.homeBaseOwner = group.homeBaseOwner
    marker.baseOwnedGlobalSquad = group.baseOwnedGlobalSquad == true
    marker.baseOwnedRole = group.baseOwnedRole
    marker.routeOwnerBaseId = group.routeOwnerBaseId
    marker.baseOwnedRouteReason = group.baseOwnedRouteReason
    marker.locationRepairProtected = group.locationRepairProtected == true
    marker.strategicPower = group.strategicPower
    marker.combatReadiness = group.combatReadiness
    marker.influenceScore = group.influenceScore
    marker.directorRetargetReason = group.directorRetargetReason
    marker.directorRetargetScore = group.directorRetargetScore
    marker.directorRetargetAt = group.directorRetargetAt
    marker.supplyReadiness = group.supplyReadiness
    marker.ammoReadiness = group.ammoReadiness
    marker.armoryReadiness = group.armoryReadiness
    marker.moraleReadiness = group.moraleReadiness
    marker.supplyLineState = group.supplyLineState
    marker.logisticsBaseId = group.logisticsBaseId
    marker.logisticsBaseDistance = group.logisticsBaseDistance
    marker.strategicActivityLogisticsSupply = group.strategicActivityLogisticsSupply
    marker.strategicActivityLogisticsAmmo = group.strategicActivityLogisticsAmmo
    marker.strategicActivityLogisticsMorale = group.strategicActivityLogisticsMorale
    marker.strategicActivityType = group.strategicActivityType
    marker.strategicActivityState = group.strategicActivityState or group.state
    marker.strategicActivityTargetBaseId = group.strategicActivityTargetBaseId
    marker.strategicActivityTargetGroupId = group.strategicActivityTargetGroupId
    marker.strategicPlanKind = group.strategicPlanKind
    marker.strategicManeuverRole = group.strategicManeuverRole
    marker.strategicManeuverTargetX = group.strategicManeuverTargetX
    marker.strategicManeuverTargetY = group.strategicManeuverTargetY
    marker.strategicManeuverTargetBaseId = group.strategicManeuverTargetBaseId
    marker.strategicStrikeCommittedGroups = group.strategicStrikeCommittedGroups
    marker.strategicStrikeRequiredGroups = group.strategicStrikeRequiredGroups
    marker.strategicStrikeReady = group.strategicStrikeReady
    marker.convoyFaction = group.convoyFaction or group.patrolColor
    marker.leader = group.leader == true or group.isFactionLeader == true or group.leaderId ~= nil
    marker.isFactionLeader = group.isFactionLeader == true or group.leaderId ~= nil
    marker.leaderId = group.leaderId
    marker.leaderName = group.leaderName
    marker.leaderRole = group.leaderRole
    marker.leaderSide = group.leaderSide
    marker.leaderState = group.leaderState
    marker.leaderInfluence = group.leaderInfluence
    marker.strategicActivityId = group.strategicActivityId
    marker.strategicActivityType = group.strategicActivityType
    marker.strategicActivityState = group.strategicActivityState
    marker.strategicActivityPriority = group.strategicActivityPriority
    marker.strategicActivityTargetBaseId = group.strategicActivityTargetBaseId
    marker.strategicActivityTargetGroupId = group.strategicActivityTargetGroupId
    marker.updatedAt = group.updatedAt
    return NPCWorldDirectorBridge.ApplyVirtualGroupMapMotionFields(nil, marker, group)
end

function NPCWorldDirectorBridge.MaintainPersistentStrategicMarkers(director, gmd, worldAge)
    if not (director and director.STRATEGIC_MARKER_PERSISTENCE_ENABLED ~= false and gmd) then return false end
    if director.SP_BOOTSTRAP_GATE_MARKER_SYNC ~= false then
        local gate, retry, reason = npc_wd_shouldBootstrapGate(director, "strategic_markers")
        if gate then npc_wd_recordBootstrapGate("strategic_markers", retry, reason); return false end
    end
    if type(gmd.DebugMapMarkers) ~= "table" then gmd.DebugMapMarkers = {} end
    local changed = false

    for groupId, group in pairs(gmd.VirtualGroups or {}) do
        if type(group) == "table" and NPCWorldDirectorBridge.GroupMemberCount(group) > 0 then
            local sid = tostring(groupId)
            local marker = gmd.DebugMapMarkers[sid]
            if type(marker) ~= "table" or marker.dead == true then
                marker = NPCWorldDirectorBridge.BuildVirtualGroupUpdateMarker(gmd, sid, group)
                marker.dead = false
                gmd.DebugMapMarkers[sid] = marker
                NPCWorldDirectorBridge.SendDebugMapUpdate(marker)
                changed = true
            end
        end
    end

    if NPCCheckpointsBridge and NPCCheckpointsBridge.MakeMarker then
        local checkpoints = gmd.NPCCheckpointsBridge and gmd.NPCCheckpointsBridge.active or nil
        for _, cp in pairs(checkpoints or {}) do
            if type(cp) == "table" and cp.status ~= "removed" then
                local marker = NPCCheckpointsBridge.MakeMarker(cp)
                if marker and marker.id and type(gmd.DebugMapMarkers[tostring(marker.id)]) ~= "table" then
                    gmd.DebugMapMarkers[tostring(marker.id)] = marker
                    NPCWorldDirectorBridge.SendDebugMapUpdate(marker)
                    changed = true
                end
            end
        end
    end

    if NPCLeadersBridge and NPCLeadersBridge.EnsureData then
        local data = NPCLeadersBridge.EnsureData(gmd)
        for _, leader in pairs(data and data.leaders or {}) do
            local marker = nil
            if NPCLeadersBridge.MakeLeaderMarkerIfVisible then
                marker = NPCLeadersBridge.MakeLeaderMarkerIfVisible(gmd, leader)
            elseif NPCLeadersBridge.MakeLeaderMarker then
                marker = NPCLeadersBridge.MakeLeaderMarker(leader)
            end

            local markerId = leader and leader.id and ("leader_" .. tostring(leader.id)) or nil
            local attachedGroupId = marker and marker.attachedGroupId or nil
            if attachedGroupId and gmd.DebugMapMarkers[tostring(attachedGroupId)] then
                local groupMarker = gmd.DebugMapMarkers[tostring(attachedGroupId)]
                groupMarker.leader = true
                groupMarker.isFactionLeader = true
                groupMarker.leaderId = leader.id
                groupMarker.leaderName = leader.name
                groupMarker.leaderRole = leader.kind
                groupMarker.leaderSide = leader.side
                groupMarker.leaderState = leader.state
                groupMarker.leaderInfluence = leader.influence
                gmd.DebugMapMarkers[tostring(attachedGroupId)] = groupMarker
                NPCWorldDirectorBridge.SendDebugMapUpdate(groupMarker)
                if markerId and type(gmd.DebugMapMarkers[markerId]) == "table" then
                    gmd.DebugMapMarkers[markerId] = nil
                    NPCWorldDirectorBridge.SendDebugMapRemove(markerId)
                end
                changed = true
            elseif marker and marker.id then
                local sid = tostring(marker.id)
                local existing = gmd.DebugMapMarkers[sid]
                if type(existing) ~= "table" or existing.dead == true
                        or tostring(existing.attachedGroupId or "") ~= tostring(marker.attachedGroupId or "")
                        or math.floor(tonumber(existing.x) or 0) ~= math.floor(tonumber(marker.x) or 0)
                        or math.floor(tonumber(existing.y) or 0) ~= math.floor(tonumber(marker.y) or 0) then
                    gmd.DebugMapMarkers[sid] = marker
                    NPCWorldDirectorBridge.SendDebugMapUpdate(marker)
                    changed = true
                end
            elseif markerId and type(gmd.DebugMapMarkers[markerId]) == "table" then
                gmd.DebugMapMarkers[markerId] = nil
                NPCWorldDirectorBridge.SendDebugMapRemove(markerId)
                changed = true
            end
        end
    end

    local war = gmd.WorldDirector and gmd.WorldDirector.strategicWar or nil
    if war and war.front and type(gmd.DebugMapMarkers.STRATEGIC_FRONT_MAIN) ~= "table" then
        gmd.DebugMapMarkers.STRATEGIC_FRONT_MAIN = {
            id = "STRATEGIC_FRONT_MAIN",
            markerType = "front",
            x = war.front.x,
            y = war.front.y,
            z = war.front.z or 0,
            name = "Strategic front",
            virtual = true,
            active = false,
            dead = false,
            redPower = war.front.redPower,
            greenPower = war.front.greenPower,
            updatedAt = worldAge
        }
        NPCWorldDirectorBridge.SendDebugMapUpdate(gmd.DebugMapMarkers.STRATEGIC_FRONT_MAIN)
        changed = true
    end

    if NPCWorldDirectorBridge.ReconcileDebugMarkers(gmd, "persistent_strategic_markers", 96) > 0 then changed = true end

    return changed
end

function NPCWorldDirectorBridge.UpdateVirtualGroups(director, opts)
    local gmd = director.EnsureData and director.EnsureData() or nil
    if not (gmd and gmd.VirtualGroups and gmd.DebugMapMarkers) then return false end
    if director and director.SP_BOOTSTRAP_GATE_VIRTUAL_GROUPS ~= false then
        local gate, retry, reason = NPCWorldDirectorBridge.ShouldBootstrapGate(director, "virtual_group_update")
        if gate then NPCWorldDirectorBridge.RecordBootstrapGate("virtual_group_update", retry, reason); return false end
    end

    opts = type(opts) == "table" and opts or {}
    local worldAge = getGameTime():getWorldAgeHours()
    local changed = false
    local retargetBudget = NPCWorldDirectorBridge.DirectorRetargetBudget(director)
    if opts.retarget == false then retargetBudget = 0 end
    local retargetedCount = 0
    local maxGroups = tonumber(opts.maxGroups) or 0
    local scanned = 0
    local cursorKey = opts.cursorKey and tostring(opts.cursorKey) or nil
    local startAfter = opts.startAfter and tostring(opts.startAfter) or nil
    if not startAfter and cursorKey and gmd.WorldDirector then startAfter = gmd.WorldDirector[cursorKey] and tostring(gmd.WorldDirector[cursorKey]) or nil end
    local passedStart = startAfter == nil
    local lastGroupId = nil

    for groupId, group in pairs(gmd.VirtualGroups) do
        groupId = tostring(groupId)
        if not passedStart then
            if groupId == startAfter then passedStart = true end
        elseif group and not group.activated then
            if maxGroups > 0 and scanned >= maxGroups then break end
            scanned = scanned + 1
            lastGroupId = groupId
            local repaired = NPCWorldDirectorBridge.RepairVirtualGroupLocation(director, group)
            local retargeted = false
            if retargetedCount < retargetBudget then
                retargeted = NPCWorldDirectorBridge.TryDirectorRetargetGroup(director, group, worldAge)
                if retargeted then retargetedCount = retargetedCount + 1 end
            end
            local moved = NPCWorldDirectorBridge.UpdateVirtualGroup(director, group, worldAge, opts)
            if repaired or retargeted or moved then
                gmd.VirtualGroups[groupId] = group

                if NPCIdentityBridge and NPCIdentityBridge.TouchVirtualGroup then
                    NPCIdentityBridge.TouchVirtualGroup(gmd, group)
                end

                local marker = NPCWorldDirectorBridge.BuildVirtualGroupUpdateMarker(gmd, groupId, group)
                gmd.DebugMapMarkers[groupId] = marker
                NPCWorldDirectorBridge.SendDebugMapUpdate(marker)

                changed = true
            end
        end
    end

    if cursorKey and maxGroups > 0 then
        gmd.WorldDirector = gmd.WorldDirector or {}
        if scanned < maxGroups then
            gmd.WorldDirector[cursorKey] = nil
        else
            gmd.WorldDirector[cursorKey] = lastGroupId
        end
    end

    if changed and TransmitNPCModData and not director._suppressWorldDirectorTransmit then
        TransmitNPCModData()
    end
    return changed
end

function NPCWorldDirectorBridge.UpdateVirtualMapHeartbeat(director, reason)
    if director and director.SP_BOOTSTRAP_GATE_MARKER_SYNC ~= false then
        local gate, retry, qReason = npc_wd_shouldBootstrapGate(director, "virtual_map_heartbeat")
        if gate then npc_wd_recordBootstrapGate("virtual_map_heartbeat", retry, qReason); return false end
    end
    local gmd = director and director.EnsureData and director.EnsureData() or nil
    if not (gmd and gmd.WorldDirector and gmd.WorldDirector.enabled) then return false end
    gmd.VirtualGroups = gmd.VirtualGroups or {}
    gmd.DebugMapMarkers = gmd.DebugMapMarkers or {}

    local changed = false

    -- Force a bounded marker refresh without advancing virtual movement. The
    -- strategic simulation keeps the original BanditsRemaster movement cadence,
    -- while the player-facing global map still receives fresh marker payloads.
    local refreshed = 0
    local budget = tonumber(director.VIRTUAL_MAP_HEARTBEAT_MARKER_BUDGET) or 36
    local markerCursor = gmd.WorldDirector.virtualMapHeartbeatMarkerCursor and tostring(gmd.WorldDirector.virtualMapHeartbeatMarkerCursor) or nil
    local markerPassed = markerCursor == nil
    local markerLastId = nil
    for groupId, group in pairs(gmd.VirtualGroups or {}) do
        groupId = tostring(groupId)
        if not markerPassed then
            if groupId == markerCursor then markerPassed = true end
        elseif refreshed < budget and type(group) == "table" and group.activated ~= true then
            local marker = NPCWorldDirectorBridge.BuildVirtualGroupUpdateMarker and NPCWorldDirectorBridge.BuildVirtualGroupUpdateMarker(gmd, groupId, group) or nil
            if marker and marker.id then
                marker.heartbeat = true
                marker.heartbeatReason = tostring(reason or "tick")
                marker.updatedAt = getGameTime and getGameTime():getWorldAgeHours() or marker.updatedAt
                gmd.DebugMapMarkers[groupId] = marker
                NPCWorldDirectorBridge.SendDebugMapUpdate(marker)
                refreshed = refreshed + 1
                markerLastId = groupId
            end
        end
        if refreshed >= budget then break end
    end
    if markerLastId then
        gmd.WorldDirector.virtualMapHeartbeatMarkerCursor = markerLastId
    else
        gmd.WorldDirector.virtualMapHeartbeatMarkerCursor = nil
    end

    if refreshed > 0 or changed then
        gmd.WorldDirector.lastVirtualMapHeartbeat = getGameTime and getGameTime():getWorldAgeHours() or 0
        if NPCDiagnosticsBridge and NPCDiagnosticsBridge.LogWorld then
            NPCDiagnosticsBridge.LogWorld("WORLD_SNAPSHOT", "virtual_map_heartbeat", {
                reason = tostring(reason or "tick"),
                groups = NPCWorldDirectorBridge.CountTable(gmd.VirtualGroups or {}),
                markers = NPCWorldDirectorBridge.CountTable(gmd.DebugMapMarkers or {}),
                refreshed = refreshed,
                changed = changed == true,
                cursor = tostring(gmd.WorldDirector.virtualMapHeartbeatCursor or "")
            }, "world-virtual-map-heartbeat", false)
        end
    end
    return changed or refreshed > 0
end


function NPCWorldDirectorBridge.RefreshVirtualMapForSync(director, reason, maxGroups)
    if director and director.SP_BOOTSTRAP_GATE_MARKER_SYNC ~= false then
        local gate, retry, qReason = npc_wd_shouldBootstrapGate(director, "virtual_map_sync")
        if gate then npc_wd_recordBootstrapGate("virtual_map_sync", retry, qReason); return 0, 0 end
    end
    local gmd = director and director.EnsureData and director.EnsureData() or nil
    if not (gmd and gmd.WorldDirector and gmd.WorldDirector.enabled) then return 0, 0 end
    gmd.VirtualGroups = gmd.VirtualGroups or {}
    gmd.DebugMapMarkers = gmd.DebugMapMarkers or {}

    local worldAge = getGameTime and getGameTime():getWorldAgeHours() or 0
    local limit = tonumber(maxGroups or director.VIRTUAL_MAP_SYNC_GROUP_BUDGET) or 650
    local scanned = 0
    local changed = 0
    local refreshed = 0

    for groupId, group in pairs(gmd.VirtualGroups or {}) do
        if limit > 0 and scanned >= limit then break end
        groupId = tostring(groupId)
        if type(group) == "table" and group.activated ~= true then
            scanned = scanned + 1
            if group.preciseX == nil then group.preciseX = tonumber(group.x) or 0 end
            if group.preciseY == nil then group.preciseY = tonumber(group.y) or 0 end

            local repaired = NPCWorldDirectorBridge.RepairVirtualGroupLocation and NPCWorldDirectorBridge.RepairVirtualGroupLocation(director, group) or false
            if repaired then
                changed = changed + 1
            end

            gmd.VirtualGroups[groupId] = group
            local marker = NPCWorldDirectorBridge.BuildVirtualGroupUpdateMarker and NPCWorldDirectorBridge.BuildVirtualGroupUpdateMarker(gmd, groupId, group) or nil
            if marker and marker.id then
                marker.mapSync = true
                marker.mapSyncReason = tostring(reason or "debug_map_request")
                marker.updatedAt = worldAge
                gmd.DebugMapMarkers[groupId] = marker
                refreshed = refreshed + 1
            end
        end
    end

    if refreshed > 0 then
        gmd.WorldDirector.lastVirtualMapSyncRefresh = worldAge
        gmd.WorldDirector.lastVirtualMapSyncReason = tostring(reason or "debug_map_request")
    end
    return changed, refreshed
end

function NPCWorldDirectorBridge.SyncMarkers(director)
    if director and director.SP_BOOTSTRAP_GATE_MARKER_SYNC ~= false then
        local gate, retry, reason = npc_wd_shouldBootstrapGate(director, "marker_sync")
        if gate then npc_wd_recordBootstrapGate("marker_sync", retry, reason); return false end
    end
    local gmd = director.EnsureData()
    NPCWorldDirectorBridge.ReconcileDebugMarkers(gmd, "sync_markers", 180)
    if NPCWorldDirectorBridge.DebugMapDirtySync and type(gmd.DebugMapMarkers) == "table" then
        local now = npc_wd_nowMs()
        NPCWorldDirectorBridge.DebugMapDirtySync.sent = NPCWorldDirectorBridge.DebugMapDirtySync.sent or {}
        for id, marker in pairs(gmd.DebugMapMarkers) do
            if type(marker) == "table" then
                NPCWorldDirectorBridge.DebugMapDirtySync.sent[tostring(id)] = {sig=npc_wd_markerSignature(marker), t=now}
            end
        end
    end
    NPCWorldDirectorBridge.SendDebugMap('Sync', {markers = gmd.DebugMapMarkers})
end


-- Stage452/453: runtime-only calendar queue for non-critical world-director work.
-- It spreads optional maintenance jobs across ticks instead of letting several
-- heavy periodic tasks collide in the same frame. It does not alter save data,
-- marker payload formats, mercenary commands, bases, contracts or Black Market.
NPCWorldDirectorBridge.CalendarQueue = NPCWorldDirectorBridge.CalendarQueue or {tasks={}, tick=-1, ranThisTick=0, stats={ran=0,deferred=0,scheduled=0,disabled=0,quarantined=0}}

local function npc_wd_calendarHash(value)
    local s = tostring(value or "")
    local h = 0
    for i = 1, #s do h = (h * 33 + string.byte(s, i)) % 10007 end
    return h
end

local function npc_wd_perfRecord(name, amount)
    if NPCPerformanceTelemetryBridge and NPCPerformanceTelemetryBridge.Record then
        pcall(function() NPCPerformanceTelemetryBridge.Record(name, amount or 1) end)
    end
end

function NPCWorldDirectorBridge.GetCalendarDiagnostics(reset)
    local q = NPCWorldDirectorBridge.CalendarQueue or {tasks={}, stats={}}
    local stats = q.stats or {}
    local out = {ran=tonumber(stats.ran) or 0, deferred=tonumber(stats.deferred) or 0, scheduled=tonumber(stats.scheduled) or 0, disabled=tonumber(stats.disabled) or 0, quarantined=tonumber(stats.quarantined) or 0, tasks=0}
    for _, _ in pairs(q.tasks or {}) do out.tasks = out.tasks + 1 end
    out.ranThisTick = tonumber(q.ranThisTick) or 0
    if reset == true then q.stats = {ran=0,deferred=0,scheduled=0,disabled=0,quarantined=0}; NPCWorldDirectorBridge.CalendarQueue = q end
    return out
end


local function npc_wd_quarantineRecord(taskName, retryTicks, reason)
    if NPCPerformanceTelemetryBridge and NPCPerformanceTelemetryBridge.Record then
        pcall(function() NPCPerformanceTelemetryBridge.Record("world_quarantine_deferred", 1) end)
    end
    if NPCDiagnosticsBridge and NPCDiagnosticsBridge.Verbose then
        NPCDiagnosticsBridge.Verbose("WORLD_QUARANTINE", "defer_world_task", {task=tostring(taskName or ""), retryTicks=retryTicks, reason=reason}, "world-quarantine:" .. tostring(taskName or ""))
    end
end

local function npc_wd_shouldWorldQuarantine(director, taskName)
    if not director or director.SP_HARD_STREAMING_QUARANTINE_ENABLED == false then return false end
    if not npc_wd_isSinglePlayerRuntime() then return false end
    if NPCStreamingRuntimeBridge and NPCStreamingRuntimeBridge.ShouldQuarantineWorldTask then
        local ok, defer, retryTicks, reason = pcall(function() return NPCStreamingRuntimeBridge.ShouldQuarantineWorldTask(taskName) end)
        if ok and defer then return true, tonumber(retryTicks) or tonumber(director.WORLD_CALENDAR_DEFER_TICKS) or 9, reason end
    end
    return false
end

npc_wd_shouldBootstrapGate = function(director, taskName)
    if not director or director.SP_BOOTSTRAP_HARD_GATE_ENABLED == false then return false end
    if not npc_wd_isSinglePlayerRuntime() then return false end
    if NPCStreamingRuntimeBridge and NPCStreamingRuntimeBridge.ShouldGateWorldBootstrapTask then
        local ok, gate, retryTicks, reason = pcall(function() return NPCStreamingRuntimeBridge.ShouldGateWorldBootstrapTask(taskName) end)
        if ok and gate then return true, tonumber(retryTicks) or tonumber(director.SP_QUARANTINE_WORLD_UPDATE_DEFER_TICKS) or 600, reason end
    end
    return false
end

npc_wd_recordBootstrapGate = function(taskName, retryTicks, reason)
    if NPCPerformanceTelemetryBridge and NPCPerformanceTelemetryBridge.Record then
        pcall(function() NPCPerformanceTelemetryBridge.Record("world_bootstrap_gate_deferred", 1) end)
    end
    if NPCDiagnosticsBridge and NPCDiagnosticsBridge.Verbose then
        NPCDiagnosticsBridge.Verbose("WORLD_QUARANTINE", "gate_bootstrap_task", {task=tostring(taskName or ""), retryTicks=retryTicks, reason=reason}, "world-bootstrap-gate:" .. tostring(taskName or ""))
    end
end

function NPCWorldDirectorBridge.ShouldBootstrapGate(director, taskName)
    if npc_wd_shouldBootstrapGate then return npc_wd_shouldBootstrapGate(director, taskName) end
    return false
end

function NPCWorldDirectorBridge.RecordBootstrapGate(taskName, retryTicks, reason)
    if npc_wd_recordBootstrapGate then return npc_wd_recordBootstrapGate(taskName, retryTicks, reason) end
end

function NPCWorldDirectorBridge.CalendarDue(director, key, intervalTicks, jitterTicks)
    if not director then return true end
    if director.WORLD_CALENDAR_QUEUE_ENABLED == false then
        local q = NPCWorldDirectorBridge.CalendarQueue or {stats={}}
        q.stats = q.stats or {}; q.stats.disabled = (tonumber(q.stats.disabled) or 0) + 1; NPCWorldDirectorBridge.CalendarQueue = q
        return true
    end

    local tick = tonumber(director._tick) or 0
    intervalTicks = math.max(1, math.floor(tonumber(intervalTicks) or 1))
    jitterTicks = math.max(0, math.floor(tonumber(jitterTicks) or tonumber(director.WORLD_CALENDAR_JITTER_TICKS) or 0))

    local q = NPCWorldDirectorBridge.CalendarQueue or {tasks={}, tick=-1, ranThisTick=0, stats={}}
    q.tasks = q.tasks or {}; q.stats = q.stats or {}
    if q.tick ~= tick then q.tick = tick; q.ranThisTick = 0 end

    key = tostring(key or "world_task")
    local task = q.tasks[key]
    if not task then
        local offset = jitterTicks > 0 and (npc_wd_calendarHash(key) % math.min(intervalTicks, jitterTicks)) or 0
        task = {nextAt = tick + intervalTicks + offset, interval = intervalTicks}
        q.tasks[key] = task
        q.stats.scheduled = (tonumber(q.stats.scheduled) or 0) + 1
        NPCWorldDirectorBridge.CalendarQueue = q
        return false
    end

    if tick < (tonumber(task.nextAt) or tick) then
        NPCWorldDirectorBridge.CalendarQueue = q
        return false
    end

    local qDefer, qRetry, qReason = npc_wd_shouldWorldQuarantine(director, key)
    if qDefer then
        task.nextAt = tick + math.max(1, math.floor(tonumber(qRetry) or tonumber(director.WORLD_CALENDAR_DEFER_TICKS) or 9))
        q.stats.quarantined = (tonumber(q.stats.quarantined) or 0) + 1
        NPCWorldDirectorBridge.CalendarQueue = q
        npc_wd_quarantineRecord(key, qRetry, qReason)
        return false
    end

    local maxPerTick = math.max(1, math.floor(tonumber(director.WORLD_CALENDAR_MAX_TASKS_PER_TICK) or 2))
    if (tonumber(q.ranThisTick) or 0) >= maxPerTick then
        local deferTicks = math.max(1, math.floor(tonumber(director.WORLD_CALENDAR_DEFER_TICKS) or 7))
        task.nextAt = tick + deferTicks
        q.stats.deferred = (tonumber(q.stats.deferred) or 0) + 1
        NPCWorldDirectorBridge.CalendarQueue = q
        npc_wd_perfRecord("world_calendar_deferred", 1)
        return false
    end

    local spread = jitterTicks > 0 and (npc_wd_calendarHash(key .. ":" .. tostring(tick)) % (jitterTicks + 1)) or 0
    task.nextAt = tick + intervalTicks + spread
    task.interval = intervalTicks
    q.ranThisTick = (tonumber(q.ranThisTick) or 0) + 1
    q.stats.ran = (tonumber(q.stats.ran) or 0) + 1
    NPCWorldDirectorBridge.CalendarQueue = q
    npc_wd_perfRecord("world_calendar_run", 1)
    return true
end

local function npc_wd_transmitOnce(director, changed)
    if not changed then return end
    if TransmitNPCModData then TransmitNPCModData() end
end

function NPCWorldDirectorBridge.BoundedBootstrap(director, mode)
    local gmd = director.EnsureData()
    if not gmd.WorldDirector.enabled then return end

    mode = tostring(mode or (npc_wd_isSinglePlayerRuntime() and "singleplayer" or "server"))
    local isSP = mode == "singleplayer"
    local bootstrapQuarantine = false
    local bootstrapRetryTicks = 0
    local bootstrapQuarantineReason = nil
    if isSP then
        bootstrapQuarantine, bootstrapRetryTicks, bootstrapQuarantineReason = npc_wd_shouldWorldQuarantine(director, "bootstrap_sync")
    end
    local startupTarget = tonumber(director.STARTUP_GROUPS) or 0
    if gmd.WorldDirector.initialized and startupTarget > 0 and NPCWorldDirectorBridge.CountTable(gmd.VirtualGroups) <= 0 then
        gmd.WorldDirector.initialized = false
    end

    local worldAge = getGameTime and getGameTime():getWorldAgeHours() or 0
    local changed = false
    local revirtDone = true
    if not director._startupRuntimeRevirtualized then
        local revirtBudget = isSP and 8 or 12
        local revirtChanged
        revirtChanged, revirtDone = NPCWorldDirectorBridge.RevirtualizePersistedRuntimeStateStep(director, revirtBudget)
        changed = revirtChanged or changed
    end

    if isSP then
        local hardGate, hardGateRetry, hardGateReason = npc_wd_shouldBootstrapGate(director, "bootstrap_world_init")
        if hardGate then
            gmd.WorldDirector.spBootstrapInProgress = true
            gmd.WorldDirector.lastUpdate = gmd.WorldDirector.lastUpdate or worldAge
            npc_wd_recordBootstrapGate("bootstrap_world_init", hardGateRetry, hardGateReason)
            return
        end
    end

    if not gmd.WorldDirector.initialized then
        director._suppressWorldDirectorTransmit = true
        local okBootstrap, bootstrapError = pcall(function()
            local existing = NPCWorldDirectorBridge.CountTable(gmd.VirtualGroups)
            local target = startupTarget
            local groupBudget = isSP
                and npc_wd_spBudget(director.SINGLEPLAYER_BOOTSTRAP_GROUPS_PER_STEP, 4, 1, 24)
                or npc_wd_spBudget(director.SERVER_BOOTSTRAP_GROUPS_PER_STEP, 6, 1, 32)
            if isSP and bootstrapQuarantine then
                groupBudget = math.max(0, math.min(groupBudget, tonumber(director.SP_QUARANTINE_BOOTSTRAP_GROUPS_PER_STEP) or 1))
            end
            local created = 0
            while existing < target and created < groupBudget do
                if not director.CreateVirtualGroup(true) then break end
                existing = existing + 1
                created = created + 1
                changed = true
            end

            local patrolBudget = isSP
                and npc_wd_spBudget(director.SINGLEPLAYER_BOOTSTRAP_ROAD_PATROLS_PER_STEP, 4, 1, 24)
                or npc_wd_spBudget(director.SERVER_BOOTSTRAP_ROAD_PATROLS_PER_STEP, 4, 1, 32)
            if isSP and bootstrapQuarantine then
                patrolBudget = math.max(0, math.min(patrolBudget, tonumber(director.SP_QUARANTINE_BOOTSTRAP_ROAD_PATROLS_PER_STEP) or 0))
            end
            if patrolBudget > 0 and director.EnsureRoadPatrols(true, patrolBudget) then changed = true end
        end)
        director._suppressWorldDirectorTransmit = nil
        if not okBootstrap then
            NPCWorldDirectorBridge.Log(director, NPC_WORLD_DIRECTOR_LOG_PREFIX .. " Bounded bootstrap failed: " .. tostring(bootstrapError))
        end

        local groupsReady = NPCWorldDirectorBridge.CountTable(gmd.VirtualGroups) >= startupTarget
        local redReady = NPCWorldDirectorBridge.GetRoadPatrolCount(director, true) >= (tonumber(director.STARTUP_ROAD_PATROLS_RED) or 0)
        local greenReady = NPCWorldDirectorBridge.GetRoadPatrolCount(director, false) >= (tonumber(director.STARTUP_ROAD_PATROLS_GREEN) or 0)
        local encountersReady = NPCWorldDirectorBridge.GetRoadPatrolEncounterCount(director) >= (tonumber(director.STARTUP_ROAD_PATROL_ENCOUNTERS) or 0)

        if groupsReady and redReady and greenReady and encountersReady and revirtDone and not bootstrapQuarantine then
            NPCWorldDirectorBridge.UpdateStrategicWar(director, gmd, worldAge)
            NPCWorldDirectorBridge.MaintainPersistentStrategicMarkers(director, gmd, worldAge)
            gmd.WorldDirector.initialized = true
            gmd.WorldDirector.spBootstrapInProgress = nil
            gmd.WorldDirector.serverBootstrapInProgress = nil
            gmd.WorldDirector.lastUpdate = worldAge
            changed = true
            NPCWorldDirectorBridge.Log(director, NPC_WORLD_DIRECTOR_LOG_PREFIX .. " Bounded bootstrap completed. Virtual groups=" .. tostring(NPCWorldDirectorBridge.CountTable(gmd.VirtualGroups)))
            if director.SyncMarkers then director.SyncMarkers() end
        else
            if isSP then
                gmd.WorldDirector.spBootstrapInProgress = true
            else
                gmd.WorldDirector.serverBootstrapInProgress = true
            end
            gmd.WorldDirector.lastUpdate = gmd.WorldDirector.lastUpdate or worldAge
        end
    end

    if not (isSP and bootstrapQuarantine) then
        local syncBudget = isSP
            and npc_wd_spBudget(director.SINGLEPLAYER_MAP_SYNC_GROUP_BUDGET, 90, 24, 240)
            or npc_wd_spBudget(director.SERVER_MAP_SYNC_GROUP_BUDGET, 120, 24, 260)
        local _, refreshed = NPCWorldDirectorBridge.RefreshVirtualMapForSync(director, mode .. "_bootstrap", syncBudget)
        if tonumber(refreshed) and refreshed > 0 then changed = true end

        npc_wd_transmitOnce(director, changed)
    else
        npc_wd_quarantineRecord("bootstrap_sync", bootstrapRetryTicks, bootstrapQuarantineReason)
    end
end

function NPCWorldDirectorBridge.SinglePlayerBootstrap(director)
    return NPCWorldDirectorBridge.BoundedBootstrap(director, "singleplayer")
end

function NPCWorldDirectorBridge.Bootstrap(director)
    return NPCWorldDirectorBridge.BoundedBootstrap(director, npc_wd_isSinglePlayerRuntime() and "singleplayer" or "server")
end

function NPCWorldDirectorBridge.UpdateWorld(director)
    local gmd = director.EnsureData()
    if not gmd.WorldDirector.enabled then return end

    local qWorld, qWorldRetry, qWorldReason = npc_wd_shouldWorldQuarantine(director, "world_update")
    local hardGateWorld, hardGateWorldRetry, hardGateWorldReason = npc_wd_shouldBootstrapGate(director, "world_update")
    if hardGateWorld and not qWorld then qWorld, qWorldRetry, qWorldReason = true, hardGateWorldRetry, hardGateWorldReason end
    if qWorld then
        npc_wd_quarantineRecord("world_update", qWorldRetry, qWorldReason)
        if director.EnforceHiredMercenaryFollowLeash then director.EnforceHiredMercenaryFollowLeash("world_update_quarantine") end
        if director.CleanupDeadPhysicalGroups then director.CleanupDeadPhysicalGroups() end
        if director.EnforceProxyLODPhysicalCaps then director.EnforceProxyLODPhysicalCaps("world_update_quarantine") end
        gmd.WorldDirector.lastUpdate = getGameTime():getWorldAgeHours()
        return
    end
    director.Bootstrap()
    local updateBudget = npc_wd_isSinglePlayerRuntime()
        and npc_wd_spBudget(director.SINGLEPLAYER_WORLD_UPDATE_GROUP_BUDGET, 18, 4, 80)
        or npc_wd_spBudget(director.SERVER_WORLD_UPDATE_GROUP_BUDGET, 36, 8, 140)
    local updateCursor = npc_wd_isSinglePlayerRuntime() and "spWorldUpdateCursor" or "serverWorldUpdateCursor"
    NPCWorldDirectorBridge.UpdateVirtualGroups(director, {forceLOD = true, maxGroups = updateBudget, cursorKey = updateCursor})
    director.UpdateRoadPatrolBattles()
    NPCWorldDirectorBridge.UpdateStrategicWar(director, gmd, getGameTime():getWorldAgeHours())
    if NPCInfluenceFieldBridge and NPCInfluenceFieldBridge.UpdateFromWorld then
        NPCInfluenceFieldBridge.UpdateFromWorld(gmd)
    end
    director._suppressWorldDirectorTransmit = true
    local okWorldGrowth, worldGrowthError = pcall(function()
        director.CreateVirtualGroup(false)
        director.EnsureRoadPatrols(false, npc_wd_isSinglePlayerRuntime() and 1 or 2)
    end)
    director._suppressWorldDirectorTransmit = nil
    if not okWorldGrowth then
        NPCWorldDirectorBridge.Log(director, NPC_WORLD_DIRECTOR_LOG_PREFIX .. " World growth tick failed: " .. tostring(worldGrowthError))
    end
    director.EnforceHiredMercenaryFollowLeash("world_update")
    director.CleanupDeadPhysicalGroups()
    director.EnforceProxyLODPhysicalCaps("world_update")
    director.UpdateBattleRemains()
    NPCWorldDirectorBridge.UpdateUrbanCoverProps(director)
    if director.BATTLEFIELD_CLEANUP_ENABLED then NPCWorldDirectorBridge.CleanupBattlefieldClutter(director) end
    if not npc_wd_shouldSkipSPActivationScan("world_update", director._tick or 0) then
        director.ActivateGroupsNearPlayers()
    end
    NPCWorldDirectorBridge.MaintainPersistentStrategicMarkers(director, gmd, getGameTime():getWorldAgeHours())
    NPCWorldDirectorBridge.SnapshotPhysicalBubbleGroups(director, "world_update_physical_bubble")
    NPCWorldDirectorBridge.CompactStrategicPersistence(director, "world_update_strategic_compact")

    gmd.WorldDirector.lastUpdate = getGameTime():getWorldAgeHours()
    TransmitNPCModData()
    director.SyncMarkers()
end

function NPCWorldDirectorBridge.OnTick(director)
    director._tick = director._tick + 1

    if director.FlushRemoveObjectQueue then
        director.FlushRemoveObjectQueue(false)
    end
    if director.FlushFormerNPCCleanupScopes then
        director.FlushFormerNPCCleanupScopes(false)
    end

    if director._tick == 1 then
        NPCWorldDirectorBridge.RevirtualizePersistedRuntimeStateStep(director, npc_wd_isSinglePlayerRuntime() and 6 or 12)
    end

    local bootstrapInterval = npc_wd_isSinglePlayerRuntime()
        and math.max(15, tonumber(director.SINGLEPLAYER_BOOTSTRAP_TICK_INTERVAL) or 45)
        or math.max(20, tonumber(director.SERVER_BOOTSTRAP_TICK_INTERVAL) or 30)
    if npc_wd_isSinglePlayerRuntime() then
        local qBoot = npc_wd_shouldWorldQuarantine(director, "bootstrap_sync")
        if qBoot then
            bootstrapInterval = math.max(bootstrapInterval, tonumber(director.SP_QUARANTINE_BOOTSTRAP_MIN_INTERVAL_TICKS) or 90)
        end
    end
    local gmdForBootstrap = director.EnsureData and director.EnsureData() or nil
    if director._tick > 1 and bootstrapInterval > 0 and gmdForBootstrap and gmdForBootstrap.WorldDirector and gmdForBootstrap.WorldDirector.initialized ~= true and director._tick % bootstrapInterval == 0 and not qBoot then
        director.Bootstrap()
    elseif qBoot and director._tick % math.max(30, math.min(bootstrapInterval, 180)) == 0 then
        npc_wd_recordBootstrapGate("bootstrap_tick", bootstrapInterval, "sp_bootstrap_gate")
    end

    if npc_wd_isSinglePlayerRuntime() then
        local spActivationInterval = math.max(30, tonumber(director.SINGLEPLAYER_ACTIVATION_TICK_INTERVAL) or 120)
        local qActivation = npc_wd_shouldWorldQuarantine(director, "activation_scan")
        if director._tick > 120 and director._tick % spActivationInterval == 0 and not qActivation and not npc_wd_shouldSkipSPActivationScan("sp_tick", director._tick) then
            director.ActivateGroupsNearPlayers()
        end
    end

    local mercenaryLeashInterval = math.max(30, tonumber(director.MERCENARY_FOLLOW_LEASH_INTERVAL_TICKS) or 75)
    if director._tick % mercenaryLeashInterval == 0 then
        director.EnforceHiredMercenaryFollowLeash("tick")
    end

    local cleanupInterval = director.GetPhysicalCleanupIntervalTicks and director.GetPhysicalCleanupIntervalTicks() or 1200
    if cleanupInterval > 0 and director._tick % cleanupInterval == 0 then
        director.CleanupDeadPhysicalGroups()
    end

    local proxyInterval = math.max(15, tonumber(director.PROXY_LOD_ENFORCE_INTERVAL_TICKS) or 30)
    local loadLevel = NPCWorldDirectorBridge.PhysicalLoadLevel()
    if loadLevel >= 3 then
        proxyInterval = math.min(proxyInterval, 15)
    elseif loadLevel >= 2 then
        proxyInterval = math.min(proxyInterval, 30)
    end
    if NPCStreamingRuntimeBridge and NPCStreamingRuntimeBridge.IsTravelUnloading then
        local ok, active = pcall(function() return NPCStreamingRuntimeBridge.IsTravelUnloading() end)
        if ok and active then proxyInterval = math.min(proxyInterval, 15) end
    end
    if director.IsProxyLODEnabled and proxyInterval > 0 and director._tick % proxyInterval == 0 then
        director.EnforceProxyLODPhysicalCaps("tick")
    end

    if director._tick == 180 then
        local qBoot180, qRetry180, qReason180 = npc_wd_shouldWorldQuarantine(director, "bootstrap_sync")
        if not qBoot180 then
            director.Bootstrap()
        else
            npc_wd_quarantineRecord("bootstrap_tick_180", qRetry180, qReason180)
        end
    else
        if NPCWorldDirectorBridge.CalendarDue(director, "periodic_battle_remains", 1200, 90) then
            director.UpdateBattleRemains()
        end
        if NPCWorldDirectorBridge.CalendarDue(director, "periodic_activation_scan", 1200, 75) and not npc_wd_shouldSkipSPActivationScan("periodic", director._tick) then
            director.ActivateGroupsNearPlayers()
        end
        if NPCInfluenceFieldBridge and NPCInfluenceFieldBridge.UpdateFromWorld and NPCWorldDirectorBridge.CalendarDue(director, "periodic_influence_world", 1200, 110) then
            NPCInfluenceFieldBridge.UpdateFromWorld(director.EnsureData())
        end
    end

    local clutterInterval = math.max(300, tonumber(director.BATTLEFIELD_CLEANUP_INTERVAL_TICKS) or 900)
    if director.BATTLEFIELD_CLEANUP_ENABLED and clutterInterval > 0 and NPCWorldDirectorBridge.CalendarDue(director, "battlefield_clutter", clutterInterval, 97) then
        NPCWorldDirectorBridge.CleanupBattlefieldClutter(director)
    end

    local urbanCoverInterval = math.max(300, tonumber(director.URBAN_COVER_PROPS_INTERVAL_TICKS) or 900)
    if director.URBAN_COVER_PROPS_ENABLED and urbanCoverInterval > 0 and director._tick > 240 and NPCWorldDirectorBridge.CalendarDue(director, "urban_cover_props", urbanCoverInterval, 101) then
        NPCWorldDirectorBridge.UpdateUrbanCoverProps(director)
    end

    local bubbleInterval = math.max(120, tonumber(director.PERSISTENCE_PHYSICAL_BUBBLE_INTERVAL_TICKS) or 300)
    if director.PERSISTENCE_PHYSICAL_BUBBLE_ENABLED ~= false and bubbleInterval > 0 and director._tick > 180 and NPCWorldDirectorBridge.CalendarDue(director, "physical_bubble_snapshot", bubbleInterval, 47) then
        if NPCWorldDirectorBridge.SnapshotPhysicalBubbleGroups(director, "tick_physical_bubble") > 0 and TransmitNPCModData then
            TransmitNPCModData()
        end
    end

    local compactInterval = math.max(300, tonumber(director.PERSISTENCE_COMPACT_INTERVAL_TICKS) or 900)
    if director.PERSISTENCE_COMPACT_VIRTUAL_GROUPS ~= false and compactInterval > 0 and director._tick > 240 and NPCWorldDirectorBridge.CalendarDue(director, "strategic_compact", compactInterval, 89) then
        if NPCWorldDirectorBridge.CompactStrategicPersistence(director, "tick_strategic_compact") > 0 and TransmitNPCModData then
            TransmitNPCModData()
        end
    end

    -- Global-map heartbeat: refreshes marker payloads only. Actual virtual
    -- group movement keeps the heavier BanditsRemaster-style world-update cadence;
    -- the client projects marker movement between authoritative updates.
    local mapHeartbeatInterval = math.max(120, tonumber(director.VIRTUAL_MAP_HEARTBEAT_TICKS) or 240)
    if director._tick > 120 and mapHeartbeatInterval > 0 and NPCWorldDirectorBridge.CalendarDue(director, "virtual_map_heartbeat", mapHeartbeatInterval, 61) then
        NPCWorldDirectorBridge.UpdateVirtualMapHeartbeat(director, "tick")
    end
end

function NPCWorldDirectorBridge.EveryTenMinutes(director)
    director.UpdateWorld()
end

function NPCWorldDirectorBridge.InstallRuntimeEvents(director)
    local function npc_wd_onTick()
        return NPCWorldDirectorBridge.OnTick(director)
    end

    local function npc_wd_everyTenMinutes()
        return NPCWorldDirectorBridge.EveryTenMinutes(director)
    end

    Events.OnTick.Add(npc_wd_onTick)
    Events.EveryTenMinutes.Add(npc_wd_everyTenMinutes)

    if Events.OnSave and type(Events.OnSave.Add) == "function" and not director._stage411PersistenceSaveHookInstalled then
        director._stage411PersistenceSaveHookInstalled = true
        Events.OnSave.Add(function()
            local changed = NPCWorldDirectorBridge.FlushStrategicPersistence(director, "on_save")
            if changed > 0 and TransmitNPCModData then TransmitNPCModData() end
        end)
    end
end

-- NPCWorldDirectorBridge legacy helper aliases for compatibility with old wrappers/extensions.
local NPC_WD_LEGACY_TOKEN = "Ban" .. "dit"
NPCWorldDirectorBridge["IsCleanupFormer" .. NPC_WD_LEGACY_TOKEN .. "Zombie"] = NPCWorldDirectorBridge.IsCleanupFormerNPCZombie
NPCWorldDirectorBridge["IsFormer" .. NPC_WD_LEGACY_TOKEN .. "Zombie"] = NPCWorldDirectorBridge.IsFormerNPCZombie
NPCWorldDirectorBridge["RemoveLoaded" .. NPC_WD_LEGACY_TOKEN .. "Objects"] = NPCWorldDirectorBridge.RemoveLoadedNPCObjects
NPCWorldDirectorBridge["RegisterFormer" .. NPC_WD_LEGACY_TOKEN .. "CleanupScope"] = NPCWorldDirectorBridge.RegisterFormerNPCCleanupScope
NPCWorldDirectorBridge["FlushFormer" .. NPC_WD_LEGACY_TOKEN .. "CleanupScopes"] = NPCWorldDirectorBridge.FlushFormerNPCCleanupScopes
NPCWorldDirectorBridge["Request" .. NPC_WD_LEGACY_TOKEN .. "ObjectCleanup"] = NPCWorldDirectorBridge.RequestNPCObjectCleanup
NPCWorldDirectorBridge["MakeFallback" .. NPC_WD_LEGACY_TOKEN] = NPCWorldDirectorBridge.MakeFallbackNPC
NPCWorldDirectorBridge["Make" .. NPC_WD_LEGACY_TOKEN .. "FromWave"] = NPCWorldDirectorBridge.MakeNPCFromWave
NPCWorldDirectorBridge["FindLoaded" .. NPC_WD_LEGACY_TOKEN .. "ZombieForBrain"] = NPCWorldDirectorBridge.FindLoadedNPCZombieForBrain
NPCWorldDirectorBridge["CountLoaded" .. NPC_WD_LEGACY_TOKEN .. "ZombiesForGroup"] = NPCWorldDirectorBridge.CountLoadedNPCZombiesForGroup
