--
-- Neutral server-side observational director brain runtime for NPC Remaster.
--
-- This module is intentionally analysis-only. It records lightweight world/player
-- signals, keeps a small event ring and produces dry-run candidate decisions for
-- later balancing. Live assists are opt-in behind Director_DryRun and only retarget
-- existing low-priority virtual groups, reviews the outcomes of those decisions, can gently slow risky live assists from recent failures, keeps a short local cell cooldown to avoid repeatedly selecting the same area, maintains a lightweight pacing phase, stores a bounded intent ledger for tuning, applies live-policy safety gates to optional live assists and records bounded telemetry snapshots, runs a lightweight health monitor, builds compact admin reports, applies explicit director safety profiles, runs a final consistency audit, can trigger a bounded runtime safety lock that falls back to dry-run during severe overload and records a compact foundation summary for end-of-line diagnostics; this module never creates or deletes groups.
--

if isClient and isClient() then return end

NPCDirectorBrainServerBridge = NPCDirectorBrainServerBridge or {}

NPCDirectorBrainServerBridge.Config = NPCDirectorBrainServerBridge.Config or {
    enabled = true,
    profile = 1,
    profileWarningsEnabled = true,
    profileName = "diagnostics_only",
    profileApplied = "diagnostics_only",
    profileRisk = "safe",
    dryRun = true,
    debugLog = false,
    pressureGuardEnabled = true,
    pressureGuardThreshold = 1.65,
    pressureGuardHardThreshold = 2.60,
    pressureGuardRetryMinutes = 1.5,
    pressureGuardCriticalRetryMinutes = 3.0,
    routeBiasEnabled = true,
    routeBiasStrength = 1.0,
    routeBiasMaxBonus = 80,
    routeBiasCombatPenalty = 0.65,
    routeBiasForgetHours = 36,
    retargetEnabled = true,
    retargetMaxGroupsPerUpdate = 1,
    retargetCooldownHours = 4,
    retargetMaxDistance = 1600,
    retargetMinScore = 0.35,
    outcomeTrackingEnabled = true,
    outcomeMaxRecords = 160,
    outcomeReviewHours = 1.0,
    outcomeShortLifeHours = 0.5,
    outcomeSuccessMinTravel = 120,
    outcomeFeedbackEnabled = true,
    outcomeFeedbackWindowHours = 6,
    outcomeRetargetFailurePenalty = 0.55,
    outcomeActivationFailurePenalty = 0.35,
    cellCooldownEnabled = true,
    cellCooldownHours = 4,
    cellCooldownPenalty = 0.45,
    cellCooldownMaxRecords = 180,
    pacingEnabled = true,
    pacingQuietPressure = 0.70,
    pacingBuildPressure = 1.20,
    pacingPressureThreshold = 1.80,
    pacingRecoveryHours = 1.25,
    pacingRetargetBoost = 1.15,
    pacingRecoveryRetargetMultiplier = 0.35,
    intentLedgerEnabled = true,
    intentLedgerMaxRecords = 144,
    intentLedgerWindowHours = 12,
    intentLedgerTopCandidates = 5,
    livePolicyEnabled = true,
    livePolicyPressureLimit = 2.20,
    livePolicyRetargetPressureLimit = 1.45,
    livePolicyRouteBiasPressureLimit = 2.00,
    livePolicyMinOutcomeSamples = 3,
    livePolicyFailureRateLimit = 0.65,
    livePolicyRecoveryRetargetBlock = true,
    telemetryEnabled = true,
    telemetryMaxRecords = 96,
    telemetryIntervalHours = 1.0,
    telemetryWindowHours = 24,
    telemetryTopEvents = 6,
    healthMonitorEnabled = true,
    healthMaxRecords = 80,
    healthWindowHours = 12,
    healthPressureWarning = 2.75,
    healthQueueWarning = 80,
    healthMarkerWarning = 450,
    healthVirtualGroupWarning = 180,
    healthRepeatIntentCount = 5,
    adminReportEnabled = true,
    adminReportMaxRecords = 24,
    adminReportIntervalHours = 2.0,
    adminReportLogToConsole = false,
    adminReportIncludeWarnings = true,
    consistencyCheckEnabled = true,
    consistencyMaxRecords = 80,
    consistencyWindowHours = 12,
    consistencyIntervalHours = 1.0,
    consistencyStrictLiveMode = true,
    runtimeSafetyEnabled = true,
    runtimeSafetyAutoDryRun = true,
    runtimeSafetyPressureLimit = 3.40,
    runtimeSafetyQueueLimit = 120,
    runtimeSafetyMarkerLimit = 650,
    runtimeSafetyWarningLimit = 8,
    runtimeSafetyLockHours = 2.0,
    foundationSummaryEnabled = true,
    foundationSummaryMaxRecords = 16,
    foundationSummaryIntervalHours = 2.0,
    maxEvents = 120,
    worldMemoryCellSize = 150,
    maxMemoryCells = 900,
    pressureDecay = 0.90,
    playerTravelHeatDistance = 120
}

NPCDirectorBrainServerBridge._tick = NPCDirectorBrainServerBridge._tick or 0

local function bdb_now()
    local gt = getGameTime and getGameTime() or nil
    if gt and gt.getWorldAgeHours then
        local ok, age = pcall(function() return gt:getWorldAgeHours() end)
        if ok and age then return tonumber(age) or 0 end
    end
    return 0
end

local function bdb_log(message)
    if NPCDirectorBrainServerBridge.Config and NPCDirectorBrainServerBridge.Config.debugLog then
        print(message)
    end
end

local function bdb_clamp(value, minValue, maxValue)
    value = tonumber(value) or 0
    if minValue ~= nil and value < minValue then return minValue end
    if maxValue ~= nil and value > maxValue then return maxValue end
    return value
end

local function bdb_count(tbl)
    local count = 0
    if type(tbl) == "table" then
        for _, _ in pairs(tbl) do count = count + 1 end
    end
    return count
end

local function bdb_key(value)
    if value == nil then return nil end
    return tostring(value)
end

local function bdb_safePlayerName(player, index)
    if player then
        if player.getUsername then
            local ok, name = pcall(function() return player:getUsername() end)
            if ok and name and tostring(name) ~= "" then return tostring(name) end
        end
        if player.getDisplayName then
            local ok, name = pcall(function() return player:getDisplayName() end)
            if ok and name and tostring(name) ~= "" then return tostring(name) end
        end
        if player.getOnlineID then
            local ok, id = pcall(function() return player:getOnlineID() end)
            if ok and id ~= nil then return "id:" .. tostring(id) end
        end
    end
    return "player:" .. tostring(index or 0)
end

local function bdb_dist(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return math.sqrt(dx * dx + dy * dy)
end

local function bdb_metaCopy(meta)
    if type(meta) ~= "table" then return nil end
    local out = {}
    local n = 0
    for k, v in pairs(meta) do
        local tv = type(v)
        if tv == "string" or tv == "number" or tv == "boolean" then
            n = n + 1
            out[tostring(k)] = v
        end
        if n >= 12 then break end
    end
    return out
end


local function bdb_profileName(profile)
    profile = math.floor(tonumber(profile) or 1)
    if profile == 2 then return "safe_live_assist" end
    if profile == 3 then return "active_director_experimental" end
    if profile == 4 then return "custom" end
    return "diagnostics_only"
end

local function bdb_profileMax(value, maxValue)
    value = tonumber(value) or 0
    maxValue = tonumber(maxValue) or value
    if value > maxValue then return maxValue end
    return value
end

local function bdb_profileMin(value, minValue)
    value = tonumber(value) or 0
    minValue = tonumber(minValue) or value
    if value < minValue then return minValue end
    return value
end

function NPCDirectorBrainServerBridge.ApplyProfilePreset()
    local cfg = NPCDirectorBrainServerBridge.Config
    if not cfg then return nil end

    local profile = math.floor(tonumber(cfg.profile) or 1)
    if profile < 1 or profile > 4 then profile = 1 end
    local name = bdb_profileName(profile)
    cfg.profile = profile
    cfg.profileName = name
    cfg.profileApplied = name
    cfg.profileRisk = "custom"
    cfg.profileLiveAssist = cfg.dryRun == false
    cfg.profileNotes = nil

    if profile == 1 then
        cfg.dryRun = true
        cfg.pressureGuardEnabled = true
        cfg.routeBiasEnabled = true
        cfg.retargetEnabled = true
        cfg.outcomeTrackingEnabled = true
        cfg.outcomeFeedbackEnabled = true
        cfg.cellCooldownEnabled = true
        cfg.pacingEnabled = true
        cfg.intentLedgerEnabled = true
        cfg.livePolicyEnabled = true
        cfg.telemetryEnabled = true
        cfg.healthMonitorEnabled = true
        cfg.adminReportEnabled = true
        cfg.profileRisk = "safe"
        cfg.profileLiveAssist = false
        cfg.profileNotes = "dry_run_forced"
    elseif profile == 2 then
        cfg.dryRun = false
        cfg.pressureGuardEnabled = true
        cfg.routeBiasEnabled = true
        cfg.routeBiasStrength = bdb_profileMax(cfg.routeBiasStrength, 0.75)
        cfg.routeBiasMaxBonus = bdb_profileMax(cfg.routeBiasMaxBonus, 55)
        cfg.routeBiasCombatPenalty = bdb_profileMin(cfg.routeBiasCombatPenalty, 0.70)
        cfg.retargetEnabled = true
        cfg.retargetMaxGroupsPerUpdate = bdb_profileMax(cfg.retargetMaxGroupsPerUpdate, 1)
        cfg.retargetCooldownHours = bdb_profileMin(cfg.retargetCooldownHours, 6.0)
        cfg.retargetMaxDistance = bdb_profileMax(cfg.retargetMaxDistance, 1200)
        cfg.retargetMinScore = bdb_profileMin(cfg.retargetMinScore, 0.55)
        cfg.pressureGuardThreshold = bdb_profileMin(cfg.pressureGuardThreshold, 1.75)
        cfg.pressureGuardHardThreshold = bdb_profileMin(cfg.pressureGuardHardThreshold, 2.85)
        cfg.outcomeTrackingEnabled = true
        cfg.outcomeFeedbackEnabled = true
        cfg.cellCooldownEnabled = true
        cfg.pacingEnabled = true
        cfg.livePolicyEnabled = true
        cfg.livePolicyPressureLimit = bdb_profileMax(cfg.livePolicyPressureLimit, 2.05)
        cfg.livePolicyRetargetPressureLimit = bdb_profileMax(cfg.livePolicyRetargetPressureLimit, 1.25)
        cfg.livePolicyRouteBiasPressureLimit = bdb_profileMax(cfg.livePolicyRouteBiasPressureLimit, 1.75)
        cfg.livePolicyFailureRateLimit = bdb_profileMax(cfg.livePolicyFailureRateLimit, 0.55)
        cfg.livePolicyRecoveryRetargetBlock = true
        cfg.telemetryEnabled = true
        cfg.healthMonitorEnabled = true
        cfg.adminReportEnabled = true
        cfg.profileRisk = "guarded_live"
        cfg.profileLiveAssist = true
        cfg.profileNotes = "bounded_live_assists"
    elseif profile == 3 then
        cfg.dryRun = false
        cfg.pressureGuardEnabled = true
        cfg.routeBiasEnabled = true
        cfg.routeBiasStrength = bdb_profileMax(cfg.routeBiasStrength, 1.25)
        cfg.routeBiasMaxBonus = bdb_profileMax(cfg.routeBiasMaxBonus, 95)
        cfg.retargetEnabled = true
        cfg.retargetMaxGroupsPerUpdate = bdb_profileMax(cfg.retargetMaxGroupsPerUpdate, 2)
        cfg.retargetCooldownHours = bdb_profileMin(cfg.retargetCooldownHours, 3.0)
        cfg.retargetMaxDistance = bdb_profileMax(cfg.retargetMaxDistance, 1800)
        cfg.retargetMinScore = bdb_profileMin(cfg.retargetMinScore, 0.35)
        cfg.outcomeTrackingEnabled = true
        cfg.outcomeFeedbackEnabled = true
        cfg.cellCooldownEnabled = true
        cfg.pacingEnabled = true
        cfg.livePolicyEnabled = true
        cfg.livePolicyPressureLimit = bdb_profileMax(cfg.livePolicyPressureLimit, 2.35)
        cfg.livePolicyRetargetPressureLimit = bdb_profileMax(cfg.livePolicyRetargetPressureLimit, 1.65)
        cfg.livePolicyRouteBiasPressureLimit = bdb_profileMax(cfg.livePolicyRouteBiasPressureLimit, 2.10)
        cfg.livePolicyRecoveryRetargetBlock = true
        cfg.telemetryEnabled = true
        cfg.healthMonitorEnabled = true
        cfg.adminReportEnabled = true
        cfg.profileRisk = "experimental_live"
        cfg.profileLiveAssist = true
        cfg.profileNotes = "experimental_live_assists"
    else
        cfg.profileRisk = cfg.dryRun == false and "manual_live" or "manual_dry_run"
        cfg.profileLiveAssist = cfg.dryRun == false
        cfg.profileNotes = "manual_settings"
    end

    return cfg.profileName
end

function NPCDirectorBrainServerBridge.ApplySettings()
    local cfg = NPCDirectorBrainServerBridge.Config
    if NPCLegacySettingsBridge then
        cfg.enabled = NPCLegacySettingsBridge.GetBool("Director_Enabled", cfg.enabled ~= false)
        cfg.profile = math.floor(NPCLegacySettingsBridge.GetNumber("Director_Profile", cfg.profile or 1, 1, 4))
        cfg.profileWarningsEnabled = NPCLegacySettingsBridge.GetBool("Director_ProfileWarningsEnabled", cfg.profileWarningsEnabled ~= false)
        cfg.dryRun = NPCLegacySettingsBridge.GetBool("Director_DryRun", cfg.dryRun ~= false)
        cfg.debugLog = NPCLegacySettingsBridge.GetBool("Director_DebugLog", cfg.debugLog == true)
        cfg.pressureGuardEnabled = NPCLegacySettingsBridge.GetBool("Director_PressureGuardEnabled", cfg.pressureGuardEnabled ~= false)
        cfg.pressureGuardThreshold = NPCLegacySettingsBridge.GetNumber("Director_PressureGuardThreshold", cfg.pressureGuardThreshold, 0.1, 6.0)
        cfg.pressureGuardHardThreshold = NPCLegacySettingsBridge.GetNumber("Director_PressureGuardHardThreshold", cfg.pressureGuardHardThreshold, cfg.pressureGuardThreshold, 8.0)
        cfg.pressureGuardRetryMinutes = NPCLegacySettingsBridge.GetNumber("Director_PressureGuardRetryMinutes", cfg.pressureGuardRetryMinutes, 0.1, 30.0)
        cfg.pressureGuardCriticalRetryMinutes = NPCLegacySettingsBridge.GetNumber("Director_PressureGuardCriticalRetryMinutes", cfg.pressureGuardCriticalRetryMinutes, cfg.pressureGuardRetryMinutes, 60.0)
        cfg.routeBiasEnabled = NPCLegacySettingsBridge.GetBool("Director_RouteBiasEnabled", cfg.routeBiasEnabled ~= false)
        cfg.routeBiasStrength = NPCLegacySettingsBridge.GetNumber("Director_RouteBiasStrength", cfg.routeBiasStrength, 0.0, 3.0)
        cfg.routeBiasMaxBonus = NPCLegacySettingsBridge.GetNumber("Director_RouteBiasMaxBonus", cfg.routeBiasMaxBonus, 0, 250)
        cfg.routeBiasCombatPenalty = NPCLegacySettingsBridge.GetNumber("Director_RouteBiasCombatPenalty", cfg.routeBiasCombatPenalty, 0.0, 3.0)
        cfg.routeBiasForgetHours = NPCLegacySettingsBridge.GetNumber("Director_RouteBiasForgetHours", cfg.routeBiasForgetHours, 1, 168)
        cfg.retargetEnabled = NPCLegacySettingsBridge.GetBool("Director_RetargetEnabled", cfg.retargetEnabled ~= false)
        cfg.retargetMaxGroupsPerUpdate = NPCLegacySettingsBridge.GetNumber("Director_RetargetMaxGroupsPerUpdate", cfg.retargetMaxGroupsPerUpdate, 0, 10)
        cfg.retargetCooldownHours = NPCLegacySettingsBridge.GetNumber("Director_RetargetCooldownHours", cfg.retargetCooldownHours, 0.25, 48)
        cfg.retargetMaxDistance = NPCLegacySettingsBridge.GetNumber("Director_RetargetMaxDistance", cfg.retargetMaxDistance, 200, 5000)
        cfg.retargetMinScore = NPCLegacySettingsBridge.GetNumber("Director_RetargetMinScore", cfg.retargetMinScore, 0.0, 5.0)
        cfg.outcomeTrackingEnabled = NPCLegacySettingsBridge.GetBool("Director_OutcomeTrackingEnabled", cfg.outcomeTrackingEnabled ~= false)
        cfg.outcomeMaxRecords = NPCLegacySettingsBridge.GetNumber("Director_OutcomeMaxRecords", cfg.outcomeMaxRecords, 20, 1000)
        cfg.outcomeReviewHours = NPCLegacySettingsBridge.GetNumber("Director_OutcomeReviewHours", cfg.outcomeReviewHours, 0.10, 24.0)
        cfg.outcomeShortLifeHours = NPCLegacySettingsBridge.GetNumber("Director_OutcomeShortLifeHours", cfg.outcomeShortLifeHours, 0.05, 12.0)
        cfg.outcomeSuccessMinTravel = NPCLegacySettingsBridge.GetNumber("Director_OutcomeSuccessMinTravel", cfg.outcomeSuccessMinTravel, 20, 1000)
        cfg.outcomeFeedbackEnabled = NPCLegacySettingsBridge.GetBool("Director_OutcomeFeedbackEnabled", cfg.outcomeFeedbackEnabled ~= false)
        cfg.outcomeFeedbackWindowHours = NPCLegacySettingsBridge.GetNumber("Director_OutcomeFeedbackWindowHours", cfg.outcomeFeedbackWindowHours, 1.0, 72.0)
        cfg.outcomeRetargetFailurePenalty = NPCLegacySettingsBridge.GetNumber("Director_OutcomeRetargetFailurePenalty", cfg.outcomeRetargetFailurePenalty, 0.0, 2.0)
        cfg.outcomeActivationFailurePenalty = NPCLegacySettingsBridge.GetNumber("Director_OutcomeActivationFailurePenalty", cfg.outcomeActivationFailurePenalty, 0.0, 2.0)
        cfg.cellCooldownEnabled = NPCLegacySettingsBridge.GetBool("Director_CellCooldownEnabled", cfg.cellCooldownEnabled ~= false)
        cfg.cellCooldownHours = NPCLegacySettingsBridge.GetNumber("Director_CellCooldownHours", cfg.cellCooldownHours, 0.25, 48.0)
        cfg.cellCooldownPenalty = NPCLegacySettingsBridge.GetNumber("Director_CellCooldownPenalty", cfg.cellCooldownPenalty, 0.0, 3.0)
        cfg.cellCooldownMaxRecords = NPCLegacySettingsBridge.GetNumber("Director_CellCooldownMaxRecords", cfg.cellCooldownMaxRecords, 20, 1000)
        cfg.pacingEnabled = NPCLegacySettingsBridge.GetBool("Director_PacingEnabled", cfg.pacingEnabled ~= false)
        cfg.pacingQuietPressure = NPCLegacySettingsBridge.GetNumber("Director_PacingQuietPressure", cfg.pacingQuietPressure, 0.0, 3.0)
        cfg.pacingBuildPressure = NPCLegacySettingsBridge.GetNumber("Director_PacingBuildPressure", cfg.pacingBuildPressure, cfg.pacingQuietPressure, 4.0)
        cfg.pacingPressureThreshold = NPCLegacySettingsBridge.GetNumber("Director_PacingPressureThreshold", cfg.pacingPressureThreshold, cfg.pacingBuildPressure, 6.0)
        cfg.pacingRecoveryHours = NPCLegacySettingsBridge.GetNumber("Director_PacingRecoveryHours", cfg.pacingRecoveryHours, 0.10, 12.0)
        cfg.pacingRetargetBoost = NPCLegacySettingsBridge.GetNumber("Director_PacingRetargetBoost", cfg.pacingRetargetBoost, 0.50, 2.00)
        cfg.pacingRecoveryRetargetMultiplier = NPCLegacySettingsBridge.GetNumber("Director_PacingRecoveryRetargetMultiplier", cfg.pacingRecoveryRetargetMultiplier, 0.0, 1.0)
        cfg.intentLedgerEnabled = NPCLegacySettingsBridge.GetBool("Director_IntentLedgerEnabled", cfg.intentLedgerEnabled ~= false)
        cfg.intentLedgerMaxRecords = NPCLegacySettingsBridge.GetNumber("Director_IntentLedgerMaxRecords", cfg.intentLedgerMaxRecords, 20, 1000)
        cfg.intentLedgerWindowHours = NPCLegacySettingsBridge.GetNumber("Director_IntentLedgerWindowHours", cfg.intentLedgerWindowHours, 1.0, 168.0)
        cfg.intentLedgerTopCandidates = NPCLegacySettingsBridge.GetNumber("Director_IntentLedgerTopCandidates", cfg.intentLedgerTopCandidates, 1, 10)
        cfg.livePolicyEnabled = NPCLegacySettingsBridge.GetBool("Director_LivePolicyEnabled", cfg.livePolicyEnabled ~= false)
        cfg.livePolicyPressureLimit = NPCLegacySettingsBridge.GetNumber("Director_LivePolicyPressureLimit", cfg.livePolicyPressureLimit, 0.50, 6.00)
        cfg.livePolicyRetargetPressureLimit = NPCLegacySettingsBridge.GetNumber("Director_LivePolicyRetargetPressureLimit", cfg.livePolicyRetargetPressureLimit, 0.25, 6.00)
        cfg.livePolicyRouteBiasPressureLimit = NPCLegacySettingsBridge.GetNumber("Director_LivePolicyRouteBiasPressureLimit", cfg.livePolicyRouteBiasPressureLimit, 0.25, 6.00)
        cfg.livePolicyMinOutcomeSamples = NPCLegacySettingsBridge.GetNumber("Director_LivePolicyMinOutcomeSamples", cfg.livePolicyMinOutcomeSamples, 0, 30)
        cfg.livePolicyFailureRateLimit = NPCLegacySettingsBridge.GetNumber("Director_LivePolicyFailureRateLimit", cfg.livePolicyFailureRateLimit, 0.00, 1.00)
        cfg.livePolicyRecoveryRetargetBlock = NPCLegacySettingsBridge.GetBool("Director_LivePolicyRecoveryRetargetBlock", cfg.livePolicyRecoveryRetargetBlock ~= false)
        cfg.telemetryEnabled = NPCLegacySettingsBridge.GetBool("Director_TelemetryEnabled", cfg.telemetryEnabled ~= false)
        cfg.telemetryMaxRecords = NPCLegacySettingsBridge.GetNumber("Director_TelemetryMaxRecords", cfg.telemetryMaxRecords, 12, 1000)
        cfg.telemetryIntervalHours = NPCLegacySettingsBridge.GetNumber("Director_TelemetryIntervalHours", cfg.telemetryIntervalHours, 0.10, 24.0)
        cfg.telemetryWindowHours = NPCLegacySettingsBridge.GetNumber("Director_TelemetryWindowHours", cfg.telemetryWindowHours, 1.0, 168.0)
        cfg.telemetryTopEvents = NPCLegacySettingsBridge.GetNumber("Director_TelemetryTopEvents", cfg.telemetryTopEvents, 0, 20)
        cfg.healthMonitorEnabled = NPCLegacySettingsBridge.GetBool("Director_HealthMonitorEnabled", cfg.healthMonitorEnabled ~= false)
        cfg.healthMaxRecords = NPCLegacySettingsBridge.GetNumber("Director_HealthMaxRecords", cfg.healthMaxRecords, 10, 1000)
        cfg.healthWindowHours = NPCLegacySettingsBridge.GetNumber("Director_HealthWindowHours", cfg.healthWindowHours, 1.0, 168.0)
        cfg.healthPressureWarning = NPCLegacySettingsBridge.GetNumber("Director_HealthPressureWarning", cfg.healthPressureWarning, 0.5, 6.0)
        cfg.healthQueueWarning = NPCLegacySettingsBridge.GetNumber("Director_HealthQueueWarning", cfg.healthQueueWarning, 0, 5000)
        cfg.healthMarkerWarning = NPCLegacySettingsBridge.GetNumber("Director_HealthMarkerWarning", cfg.healthMarkerWarning, 0, 5000)
        cfg.healthVirtualGroupWarning = NPCLegacySettingsBridge.GetNumber("Director_HealthVirtualGroupWarning", cfg.healthVirtualGroupWarning, 0, 5000)
        cfg.healthRepeatIntentCount = NPCLegacySettingsBridge.GetNumber("Director_HealthRepeatIntentCount", cfg.healthRepeatIntentCount, 1, 50)
        cfg.adminReportEnabled = NPCLegacySettingsBridge.GetBool("Director_AdminReportEnabled", cfg.adminReportEnabled ~= false)
        cfg.adminReportMaxRecords = NPCLegacySettingsBridge.GetNumber("Director_AdminReportMaxRecords", cfg.adminReportMaxRecords, 4, 200)
        cfg.adminReportIntervalHours = NPCLegacySettingsBridge.GetNumber("Director_AdminReportIntervalHours", cfg.adminReportIntervalHours, 0.10, 24.0)
        cfg.adminReportLogToConsole = NPCLegacySettingsBridge.GetBool("Director_AdminReportLogToConsole", cfg.adminReportLogToConsole == true)
        cfg.adminReportIncludeWarnings = NPCLegacySettingsBridge.GetBool("Director_AdminReportIncludeWarnings", cfg.adminReportIncludeWarnings ~= false)
        cfg.consistencyCheckEnabled = NPCLegacySettingsBridge.GetBool("Director_ConsistencyCheckEnabled", cfg.consistencyCheckEnabled ~= false)
        cfg.consistencyMaxRecords = NPCLegacySettingsBridge.GetNumber("Director_ConsistencyMaxRecords", cfg.consistencyMaxRecords, 10, 1000)
        cfg.consistencyWindowHours = NPCLegacySettingsBridge.GetNumber("Director_ConsistencyWindowHours", cfg.consistencyWindowHours, 1.0, 168.0)
        cfg.consistencyIntervalHours = NPCLegacySettingsBridge.GetNumber("Director_ConsistencyIntervalHours", cfg.consistencyIntervalHours, 0.10, 24.0)
        cfg.consistencyStrictLiveMode = NPCLegacySettingsBridge.GetBool("Director_ConsistencyStrictLiveMode", cfg.consistencyStrictLiveMode ~= false)
        cfg.runtimeSafetyEnabled = NPCLegacySettingsBridge.GetBool("Director_RuntimeSafetyEnabled", cfg.runtimeSafetyEnabled ~= false)
        cfg.runtimeSafetyAutoDryRun = NPCLegacySettingsBridge.GetBool("Director_RuntimeSafetyAutoDryRun", cfg.runtimeSafetyAutoDryRun ~= false)
        cfg.runtimeSafetyPressureLimit = NPCLegacySettingsBridge.GetNumber("Director_RuntimeSafetyPressureLimit", cfg.runtimeSafetyPressureLimit, 0.50, 8.0)
        cfg.runtimeSafetyQueueLimit = NPCLegacySettingsBridge.GetNumber("Director_RuntimeSafetyQueueLimit", cfg.runtimeSafetyQueueLimit, 0, 5000)
        cfg.runtimeSafetyMarkerLimit = NPCLegacySettingsBridge.GetNumber("Director_RuntimeSafetyMarkerLimit", cfg.runtimeSafetyMarkerLimit, 0, 5000)
        cfg.runtimeSafetyWarningLimit = NPCLegacySettingsBridge.GetNumber("Director_RuntimeSafetyWarningLimit", cfg.runtimeSafetyWarningLimit, 1, 50)
        cfg.runtimeSafetyLockHours = NPCLegacySettingsBridge.GetNumber("Director_RuntimeSafetyLockHours", cfg.runtimeSafetyLockHours, 0.25, 24.0)
        cfg.foundationSummaryEnabled = NPCLegacySettingsBridge.GetBool("Director_FoundationSummaryEnabled", cfg.foundationSummaryEnabled ~= false)
        cfg.foundationSummaryMaxRecords = NPCLegacySettingsBridge.GetNumber("Director_FoundationSummaryMaxRecords", cfg.foundationSummaryMaxRecords, 4, 200)
        cfg.foundationSummaryIntervalHours = NPCLegacySettingsBridge.GetNumber("Director_FoundationSummaryIntervalHours", cfg.foundationSummaryIntervalHours, 0.10, 24.0)
        cfg.maxEvents = NPCLegacySettingsBridge.GetNumber("Director_MaxEvents", cfg.maxEvents, 20, 1000)
        cfg.worldMemoryCellSize = NPCLegacySettingsBridge.GetNumber("Director_WorldMemoryCellSize", cfg.worldMemoryCellSize, 50, 1000)
        cfg.maxMemoryCells = NPCLegacySettingsBridge.GetNumber("Director_MaxMemoryCells", cfg.maxMemoryCells, 50, 10000)
        cfg.pressureDecay = NPCLegacySettingsBridge.GetNumber("Director_PressureDecay", cfg.pressureDecay, 0.10, 1.0)
        cfg.playerTravelHeatDistance = NPCLegacySettingsBridge.GetNumber("Director_PlayerTravelHeatDistance", cfg.playerTravelHeatDistance, 20, 1000)
    end
    NPCDirectorBrainServerBridge.ApplyProfilePreset()
    NPCDirectorBrainServerBridge.ApplyRuntimeSafetyLock()
end

local function bdb_data()
    local gmd = GetNPCModData and GetNPCModData() or nil
    if type(gmd) ~= "table" then return nil end
    if type(gmd.DirectorBrain) ~= "table" then
        gmd.DirectorBrain = {
            version = 1,
            eventSeq = 0,
            events = {},
            profiles = {},
            worldMemory = {},
            cellCooldowns = {},
            outcomes = {},
            outcomeStats = {},
            outcomeSeq = 0,
            intentLedger = {},
            intentStats = {},
            intentSeq = 0,
            telemetry = {},
            telemetrySeq = 0,
            lastTelemetrySummary = {},
            healthWarnings = {},
            healthSeq = 0,
            lastHealthSummary = {},
            adminReports = {},
            adminReportSeq = 0,
            lastAdminReport = {},
            profileWarnings = {},
            profileWarningSeq = 0,
            lastProfileSummary = {},
            consistencyWarnings = {},
            consistencySeq = 0,
            lastConsistencySummary = {},
            runtimeSafetyLocks = {},
            runtimeSafetySeq = 0,
            lastRuntimeSafety = {},
            foundationReports = {},
            foundationSeq = 0,
            lastFoundationSummary = {},
            lastLivePolicy = {},
            pressure = {global = 0},
            pacing = {phase = "quiet", phaseStartedAt = 0},
            lastUpdate = 0,
            lastDecision = nil,
            lastWorld = nil
        }
    end
    local data = gmd.DirectorBrain
    if type(data.events) ~= "table" then data.events = {} end
    if type(data.profiles) ~= "table" then data.profiles = {} end
    if type(data.worldMemory) ~= "table" then data.worldMemory = {} end
    if type(data.cellCooldowns) ~= "table" then data.cellCooldowns = {} end
    if type(data.outcomes) ~= "table" then data.outcomes = {} end
    if type(data.outcomeStats) ~= "table" then data.outcomeStats = {} end
    if type(data.intentLedger) ~= "table" then data.intentLedger = {} end
    if type(data.intentStats) ~= "table" then data.intentStats = {} end
    if type(data.telemetry) ~= "table" then data.telemetry = {} end
    if type(data.lastTelemetrySummary) ~= "table" then data.lastTelemetrySummary = {} end
    if type(data.healthWarnings) ~= "table" then data.healthWarnings = {} end
    if type(data.lastHealthSummary) ~= "table" then data.lastHealthSummary = {} end
    if type(data.adminReports) ~= "table" then data.adminReports = {} end
    if type(data.lastAdminReport) ~= "table" then data.lastAdminReport = {} end
    if type(data.profileWarnings) ~= "table" then data.profileWarnings = {} end
    if type(data.lastProfileSummary) ~= "table" then data.lastProfileSummary = {} end
    if type(data.consistencyWarnings) ~= "table" then data.consistencyWarnings = {} end
    if type(data.lastConsistencySummary) ~= "table" then data.lastConsistencySummary = {} end
    if type(data.runtimeSafetyLocks) ~= "table" then data.runtimeSafetyLocks = {} end
    if type(data.lastRuntimeSafety) ~= "table" then data.lastRuntimeSafety = {} end
    if type(data.foundationReports) ~= "table" then data.foundationReports = {} end
    if type(data.lastFoundationSummary) ~= "table" then data.lastFoundationSummary = {} end
    if type(data.lastLivePolicy) ~= "table" then data.lastLivePolicy = {} end
    if type(data.pressure) ~= "table" then data.pressure = {global = 0} end
    if type(data.pacing) ~= "table" then data.pacing = {phase = "quiet", phaseStartedAt = 0} end
    data.version = 12
    data.eventSeq = tonumber(data.eventSeq) or 0
    data.outcomeSeq = tonumber(data.outcomeSeq) or 0
    data.intentSeq = tonumber(data.intentSeq) or 0
    data.telemetrySeq = tonumber(data.telemetrySeq) or 0
    data.healthSeq = tonumber(data.healthSeq) or 0
    data.adminReportSeq = tonumber(data.adminReportSeq) or 0
    data.profileWarningSeq = tonumber(data.profileWarningSeq) or 0
    data.consistencySeq = tonumber(data.consistencySeq) or 0
    data.runtimeSafetySeq = tonumber(data.runtimeSafetySeq) or 0
    data.foundationSeq = tonumber(data.foundationSeq) or 0
    return data, gmd
end

local function bdb_eventWeight(kind)
    if kind == "group_materialized" then return 0.65 end
    if kind == "materialize_failed" then return 0.20 end
    if kind == "road_battle_started" then return 0.90 end
    if kind == "world_group_removed" then return 0.25 end
    if kind == "virtual_group_created" then return 0.12 end
    if kind == "player_vehicle" then return 0.18 end
    if kind == "player_travel" then return 0.14 end
    if kind == "player_low_health" then return 0.22 end
    if kind == "director_activation_deferred" then return 0.08 end
    if kind == "director_group_retargeted" then return 0.06 end
    if kind == "director_outcome_started" then return 0.03 end
    if kind == "director_outcome_reviewed" then return 0.04 end
    if kind == "director_cell_cooldown" then return 0.03 end
    if kind == "director_pacing_phase" then return 0.02 end
    if kind == "director_intent_recorded" then return 0.01 end
    if kind == "director_live_policy" then return 0.01 end
    if kind == "director_telemetry_snapshot" then return 0.005 end
    if kind == "director_health_warning" then return 0.005 end
    if kind == "director_admin_report" then return 0.002 end
    if kind == "director_profile_warning" then return 0.002 end
    if kind == "director_consistency_warning" then return 0.002 end
    if kind == "director_runtime_safety_lock" then return 0.002 end
    if kind == "director_foundation_summary" then return 0.001 end
    return 0.05
end

local function bdb_cellKey(x, y)
    if not x or not y then return nil end
    local size = tonumber(NPCDirectorBrainServerBridge.Config.worldMemoryCellSize) or 150
    if size < 1 then size = 150 end
    local cx = math.floor((tonumber(x) or 0) / size)
    local cy = math.floor((tonumber(y) or 0) / size)
    return tostring(cx) .. ":" .. tostring(cy), cx, cy
end

local function bdb_trimMemory(data)
    local maxCells = tonumber(NPCDirectorBrainServerBridge.Config.maxMemoryCells) or 900
    if bdb_count(data.worldMemory) <= maxCells then return end

    local oldestKey = nil
    local oldestAge = nil
    for key, cell in pairs(data.worldMemory) do
        local age = tonumber(cell and cell.lastSeen) or 0
        if not oldestAge or age < oldestAge then
            oldestAge = age
            oldestKey = key
        end
    end
    if oldestKey then data.worldMemory[oldestKey] = nil end
end

local function bdb_touchCell(data, kind, x, y, weight)
    local key, cx, cy = bdb_cellKey(x, y)
    if not key then return end
    local now = bdb_now()
    local cell = data.worldMemory[key]
    if not cell then
        cell = {key = key, cx = cx, cy = cy, heat = 0, noise = 0, combat = 0, player = 0, events = 0, lastSeen = now}
        data.worldMemory[key] = cell
    end

    local decay = bdb_clamp(NPCDirectorBrainServerBridge.Config.pressureDecay, 0.10, 1.0)
    cell.heat = (tonumber(cell.heat) or 0) * decay + (tonumber(weight) or 0)
    cell.events = (tonumber(cell.events) or 0) + 1
    cell.lastSeen = now

    if kind == "road_battle_started" or kind == "group_materialized" then
        cell.combat = (tonumber(cell.combat) or 0) * decay + (tonumber(weight) or 0)
    elseif kind == "player_travel" or kind == "player_vehicle" then
        cell.player = (tonumber(cell.player) or 0) * decay + (tonumber(weight) or 0)
    elseif kind == "player_low_health" then
        cell.player = (tonumber(cell.player) or 0) * decay + (tonumber(weight) or 0)
    else
        cell.noise = (tonumber(cell.noise) or 0) * decay + (tonumber(weight) or 0) * 0.5
    end

    bdb_trimMemory(data)
end

function NPCDirectorBrainServerBridge.PushEvent(kind, x, y, z, meta)
    NPCDirectorBrainServerBridge.ApplySettings()
    if not NPCDirectorBrainServerBridge.Config.enabled then return false end
    if not kind then return false end

    local data = bdb_data()
    if not data then return false end

    data.eventSeq = (tonumber(data.eventSeq) or 0) + 1
    local event = {
        seq = data.eventSeq,
        t = bdb_now(),
        kind = tostring(kind),
        x = x and math.floor(tonumber(x) or 0) or nil,
        y = y and math.floor(tonumber(y) or 0) or nil,
        z = z and math.floor(tonumber(z) or 0) or nil,
        meta = bdb_metaCopy(meta)
    }

    table.insert(data.events, event)
    local maxEvents = tonumber(NPCDirectorBrainServerBridge.Config.maxEvents) or 120
    while #data.events > maxEvents do
        table.remove(data.events, 1)
    end

    bdb_touchCell(data, event.kind, event.x, event.y, bdb_eventWeight(event.kind))
    return true
end

local function bdb_isPlayerDead(player)
    if not player then return true end
    if player.isDead then
        local ok, dead = pcall(function() return player:isDead() end)
        if ok and dead then return true end
    end
    return false
end

local function bdb_playerHealth(player)
    if not player or not player.getBodyDamage then return nil end
    local ok, health = pcall(function()
        local bd = player:getBodyDamage()
        if bd and bd.getOverallBodyHealth then return bd:getOverallBodyHealth() end
        return nil
    end)
    if ok then return tonumber(health) end
    return nil
end

local function bdb_playerVehicle(player)
    if not player or not player.getVehicle then return false end
    local ok, vehicle = pcall(function() return player:getVehicle() end)
    return ok and vehicle ~= nil
end

function NPCDirectorBrainServerBridge.UpdatePlayers(data)
    local players = getOnlinePlayers and getOnlinePlayers() or nil
    if not players then return 0 end

    local size = 0
    local okSize, result = pcall(function() return players:size() end)
    if okSize and result then size = tonumber(result) or 0 end
    if size <= 0 then return 0 end

    local now = bdb_now()
    local updated = 0

    for i = 0, size - 1 do
        local player = players:get(i)
        if player and not bdb_isPlayerDead(player) then
            local key = bdb_safePlayerName(player, i)
            local profile = data.profiles[key]
            if not profile then
                profile = {name = key, samples = 0, travelScore = 0, vehicleScore = 0, lowHealthScore = 0, pressure = 0}
                data.profiles[key] = profile
            end

            local x = tonumber(player:getX()) or 0
            local y = tonumber(player:getY()) or 0
            local z = tonumber(player:getZ()) or 0
            local dist = 0
            if profile.lastX and profile.lastY then
                dist = bdb_dist(x, y, profile.lastX, profile.lastY)
            end

            local decay = bdb_clamp(NPCDirectorBrainServerBridge.Config.pressureDecay, 0.10, 1.0)
            profile.travelScore = (tonumber(profile.travelScore) or 0) * decay
            profile.vehicleScore = (tonumber(profile.vehicleScore) or 0) * decay
            profile.lowHealthScore = (tonumber(profile.lowHealthScore) or 0) * decay

            if dist >= (tonumber(NPCDirectorBrainServerBridge.Config.playerTravelHeatDistance) or 120) then
                profile.travelScore = profile.travelScore + bdb_clamp(dist / 800, 0.05, 0.75)
                NPCDirectorBrainServerBridge.PushEvent("player_travel", x, y, z, {player = key, dist = math.floor(dist)})
            end

            if bdb_playerVehicle(player) then
                profile.vehicleScore = profile.vehicleScore + 0.12
                if not profile.wasInVehicle then
                    NPCDirectorBrainServerBridge.PushEvent("player_vehicle", x, y, z, {player = key})
                end
                profile.wasInVehicle = true
            else
                profile.wasInVehicle = false
            end

            local health = bdb_playerHealth(player)
            if health and health > 0 and health < 45 then
                profile.lowHealthScore = profile.lowHealthScore + 0.18
                if not profile.wasLowHealth then
                    NPCDirectorBrainServerBridge.PushEvent("player_low_health", x, y, z, {player = key, health = math.floor(health)})
                end
                profile.wasLowHealth = true
            else
                profile.wasLowHealth = false
            end

            profile.lastX = math.floor(x)
            profile.lastY = math.floor(y)
            profile.lastZ = math.floor(z)
            profile.lastSeen = now
            profile.samples = (tonumber(profile.samples) or 0) + 1
            profile.pressure = bdb_clamp((profile.travelScore or 0) + (profile.vehicleScore or 0) + (profile.lowHealthScore or 0), 0, 3)
            bdb_touchCell(data, "player_sample", x, y, 0.03)
            updated = updated + 1
        end
    end

    return updated
end

local function bdb_worldSnapshot(gmd)
    local virtualGroups = gmd and gmd.VirtualGroups or nil
    local bases = gmd and gmd.Bases or nil
    local markers = gmd and gmd.DebugMapMarkers or nil
    local queue = gmd and gmd.Queue or nil
    local world = {
        virtual = 0,
        physical = 0,
        roadPatrols = 0,
        battles = 0,
        bases = bdb_count(bases),
        markers = bdb_count(markers),
        queue = bdb_count(queue)
    }

    if type(virtualGroups) == "table" then
        for _, group in pairs(virtualGroups) do
            if group then
                if group.activated then world.physical = world.physical + 1 else world.virtual = world.virtual + 1 end
                if group.roadPatrol then world.roadPatrols = world.roadPatrols + 1 end
                if group.inBattle then world.battles = world.battles + 1 end
            end
        end
    end

    return world
end

local function bdb_recentEventPressure(data)
    local pressure = 0
    local now = bdb_now()
    for _, event in ipairs(data.events or {}) do
        local age = now - (tonumber(event.t) or now)
        if age <= 2.0 then
            pressure = pressure + bdb_eventWeight(event.kind) * (1.0 - bdb_clamp(age / 2.0, 0, 1) * 0.65)
        end
    end
    return pressure
end

local function bdb_playerPressure(data)
    local total = 0
    local count = 0
    for _, profile in pairs(data.profiles or {}) do
        if profile then
            total = total + (tonumber(profile.pressure) or 0)
            count = count + 1
        end
    end
    if count <= 0 then return 0, 0 end
    return total / count, count
end


local function bdb_trimOutcomes(data)
    if not data or type(data.outcomes) ~= "table" then return end
    local maxRecords = math.floor(tonumber(NPCDirectorBrainServerBridge.Config.outcomeMaxRecords) or 160)
    if maxRecords < 20 then maxRecords = 20 end
    if bdb_count(data.outcomes) <= maxRecords then return end

    local oldestKey = nil
    local oldestTime = nil
    for key, outcome in pairs(data.outcomes) do
        local t = tonumber(outcome and (outcome.reviewedAt or outcome.startAt)) or 0
        if not oldestTime or t < oldestTime then
            oldestTime = t
            oldestKey = key
        end
    end
    if oldestKey then data.outcomes[oldestKey] = nil end
end

local function bdb_outcomeStats(data, kind)
    if type(data.outcomeStats) ~= "table" then data.outcomeStats = {} end
    kind = tostring(kind or "unknown")
    local stats = data.outcomeStats[kind]
    if type(stats) ~= "table" then
        stats = {started = 0, success = 0, failure = 0, neutral = 0}
        data.outcomeStats[kind] = stats
    end
    return stats
end

local function bdb_finalizeOutcome(data, outcome, result, reason, group)
    if not data or not outcome or outcome.status ~= "pending" then return false end
    local now = bdb_now()
    result = tostring(result or "neutral")
    reason = tostring(reason or "reviewed")

    outcome.status = "reviewed"
    outcome.result = result
    outcome.reason = reason
    outcome.reviewedAt = now
    outcome.endX = group and math.floor(tonumber(group.x) or outcome.x or 0) or outcome.endX
    outcome.endY = group and math.floor(tonumber(group.y) or outcome.y or 0) or outcome.endY
    outcome.endCount = group and tonumber(group.count) or outcome.endCount
    outcome.endActivated = group and group.activated == true or false

    local stats = bdb_outcomeStats(data, outcome.kind)
    if result == "success" then stats.success = (tonumber(stats.success) or 0) + 1
    elseif result == "failure" then stats.failure = (tonumber(stats.failure) or 0) + 1
    else stats.neutral = (tonumber(stats.neutral) or 0) + 1 end
    stats.lastResult = result
    stats.lastReason = reason
    stats.lastAt = now

    NPCDirectorBrainServerBridge.PushEvent("director_outcome_reviewed", outcome.endX or outcome.x, outcome.endY or outcome.y, outcome.z or 0, {
        groupId = tostring(outcome.groupId or ""),
        outcomeId = tostring(outcome.id or ""),
        kind = tostring(outcome.kind or "unknown"),
        result = result,
        reason = reason
    })

    if NPCDirectorBrainServerBridge.Config.debugLog then
        bdb_log("[NPCDirectorBrainServerBridge] outcome " .. tostring(outcome.kind) .. " group=" .. tostring(outcome.groupId) .. " result=" .. tostring(result) .. " reason=" .. tostring(reason))
    end
    return true
end

function NPCDirectorBrainServerBridge.RecordOutcomeStart(kind, group, meta)
    NPCDirectorBrainServerBridge.ApplySettings()
    local cfg = NPCDirectorBrainServerBridge.Config
    if not cfg.enabled or not cfg.outcomeTrackingEnabled then return nil end
    if not group or not group.id then return nil end

    local data = bdb_data()
    if not data then return nil end

    local now = bdb_now()
    local groupId = tostring(group.id)
    kind = tostring(kind or "unknown")
    data.outcomeSeq = (tonumber(data.outcomeSeq) or 0) + 1
    local outcomeId = kind .. ":" .. groupId .. ":" .. tostring(data.outcomeSeq)
    local reviewHours = tonumber(cfg.outcomeReviewHours) or 1.0
    if reviewHours < 0.10 then reviewHours = 0.10 end

    local outcome = {
        id = outcomeId,
        kind = kind,
        groupId = groupId,
        status = "pending",
        startAt = now,
        reviewAt = now + reviewHours,
        x = math.floor(tonumber(group.x) or 0),
        y = math.floor(tonumber(group.y) or 0),
        z = math.floor(tonumber(group.z) or 0),
        targetX = group.targetX and math.floor(tonumber(group.targetX) or 0) or nil,
        targetY = group.targetY and math.floor(tonumber(group.targetY) or 0) or nil,
        count = tonumber(group.count) or 0,
        roadPatrol = group.roadPatrol == true,
        meta = bdb_metaCopy(meta)
    }

    data.outcomes[outcomeId] = outcome
    local stats = bdb_outcomeStats(data, kind)
    stats.started = (tonumber(stats.started) or 0) + 1
    stats.lastStartedAt = now

    group.directorOutcomeId = outcomeId
    group.directorOutcomeKind = kind
    group.directorOutcomeStartedAt = now

    NPCDirectorBrainServerBridge.PushEvent("director_outcome_started", outcome.x, outcome.y, outcome.z or 0, {
        groupId = groupId,
        outcomeId = outcomeId,
        kind = kind
    })
    bdb_trimOutcomes(data)
    return outcomeId
end

function NPCDirectorBrainServerBridge.RecordOutcomeEnd(groupId, closeReason, group)
    NPCDirectorBrainServerBridge.ApplySettings()
    local cfg = NPCDirectorBrainServerBridge.Config
    if not cfg.enabled or not cfg.outcomeTrackingEnabled then return false end
    if not groupId then return false end

    local data = bdb_data()
    if not data or type(data.outcomes) ~= "table" then return false end

    groupId = tostring(groupId)
    local now = bdb_now()
    local shortLife = tonumber(cfg.outcomeShortLifeHours) or 0.5
    if shortLife < 0.05 then shortLife = 0.05 end
    local reason = tostring(closeReason or "closed")
    local changed = false

    for _, outcome in pairs(data.outcomes) do
        if outcome and outcome.status == "pending" and tostring(outcome.groupId) == groupId then
            local age = now - (tonumber(outcome.startAt) or now)
            local result = "neutral"
            local finalReason = reason
            if reason == "all_members_dead" or reason == "empty_physical_cleanup" or reason == "road_battle_lost" then
                result = "failure"
            elseif age <= shortLife then
                result = "failure"
                finalReason = "removed_early:" .. reason
            end
            changed = bdb_finalizeOutcome(data, outcome, result, finalReason, group) or changed
        end
    end
    return changed
end

function NPCDirectorBrainServerBridge.ReviewOutcomes(data, gmd)
    NPCDirectorBrainServerBridge.ApplySettings()
    local cfg = NPCDirectorBrainServerBridge.Config
    if not cfg.enabled or not cfg.outcomeTrackingEnabled then return 0, 0 end
    if not data or type(data.outcomes) ~= "table" then return 0, 0 end

    local now = bdb_now()
    local reviewed = 0
    local pending = 0
    local minTravel = tonumber(cfg.outcomeSuccessMinTravel) or 120
    if minTravel < 20 then minTravel = 20 end

    for _, outcome in pairs(data.outcomes) do
        if outcome and outcome.status == "pending" then
            pending = pending + 1
            if now >= (tonumber(outcome.reviewAt) or now + 1) then
                local group = gmd and gmd.VirtualGroups and gmd.VirtualGroups[tostring(outcome.groupId)] or nil
                local result = "neutral"
                local reason = "review_timeout"

                if not group then
                    result = "neutral"
                    reason = "group_no_longer_tracked"
                elseif outcome.kind == "materialization" then
                    if group.activated then
                        result = "success"
                        reason = "still_physical"
                    elseif (tonumber(group.count) or 0) > 0 then
                        result = "success"
                        reason = "survived_dematerialized"
                    else
                        result = "failure"
                        reason = "no_survivors"
                    end
                elseif outcome.kind == "retarget" then
                    local startX = tonumber(outcome.x) or tonumber(group.x) or 0
                    local startY = tonumber(outcome.y) or tonumber(group.y) or 0
                    local moved = bdb_dist(startX, startY, group.x, group.y)
                    local targetX = tonumber(outcome.targetX)
                    local targetY = tonumber(outcome.targetY)
                    local nearTarget = false
                    if targetX and targetY then
                        nearTarget = bdb_dist(group.x, group.y, targetX, targetY) <= math.max(90, minTravel)
                    end
                    if moved >= minTravel * 0.5 or nearTarget then
                        result = "success"
                        reason = nearTarget and "reached_retarget_area" or "moved_after_retarget"
                    else
                        result = "neutral"
                        reason = "retarget_pending"
                    end
                else
                    result = "neutral"
                    reason = "reviewed"
                end

                if bdb_finalizeOutcome(data, outcome, result, reason, group) then
                    reviewed = reviewed + 1
                    pending = pending - 1
                end
            end
        end
    end

    bdb_trimOutcomes(data)
    return reviewed, pending
end

local function bdb_outcomeSummary(data)
    local pending = 0
    local recentFailures = 0
    if type(data) ~= "table" or type(data.outcomes) ~= "table" then return 0, 0 end
    local now = bdb_now()
    for _, outcome in pairs(data.outcomes) do
        if outcome and outcome.status == "pending" then
            pending = pending + 1
        elseif outcome and outcome.result == "failure" then
            local age = now - (tonumber(outcome.reviewedAt) or now)
            if age >= 0 and age <= 6.0 then
                recentFailures = recentFailures + 1
            end
        end
    end
    return pending, recentFailures
end

local function bdb_recentOutcomeStats(data, kind, windowHours)
    local stats = {samples = 0, success = 0, failure = 0, neutral = 0, pending = 0}
    if type(data) ~= "table" or type(data.outcomes) ~= "table" then return stats end

    kind = tostring(kind or "unknown")
    local now = bdb_now()
    windowHours = tonumber(windowHours) or 6.0
    if windowHours < 1.0 then windowHours = 1.0 end

    for _, outcome in pairs(data.outcomes) do
        if outcome and tostring(outcome.kind or "") == kind then
            if outcome.status == "pending" then
                stats.pending = stats.pending + 1
            else
                local reviewedAt = tonumber(outcome.reviewedAt or outcome.startAt) or 0
                local age = now - reviewedAt
                if age >= 0 and age <= windowHours then
                    stats.samples = stats.samples + 1
                    if outcome.result == "success" then
                        stats.success = stats.success + 1
                    elseif outcome.result == "failure" then
                        stats.failure = stats.failure + 1
                    else
                        stats.neutral = stats.neutral + 1
                    end
                end
            end
        end
    end

    return stats
end

function NPCDirectorBrainServerBridge.GetOutcomeFeedback(kind)
    NPCDirectorBrainServerBridge.ApplySettings()
    local cfg = NPCDirectorBrainServerBridge.Config
    local feedback = {
        enabled = false,
        kind = tostring(kind or "unknown"),
        samples = 0,
        pending = 0,
        successRate = 0,
        failureRate = 0,
        multiplier = 1.0,
        pressureAdd = 0,
        minScoreAdd = 0,
        reason = "disabled"
    }

    if not cfg.enabled or not cfg.outcomeTrackingEnabled or not cfg.outcomeFeedbackEnabled then
        return feedback
    end

    local data = bdb_data()
    if not data then return feedback end

    local stats = bdb_recentOutcomeStats(data, feedback.kind, cfg.outcomeFeedbackWindowHours)
    feedback.enabled = true
    feedback.samples = tonumber(stats.samples) or 0
    feedback.pending = tonumber(stats.pending) or 0
    if feedback.samples <= 0 then
        feedback.reason = "no_recent_outcomes"
        return feedback
    end

    feedback.successRate = (tonumber(stats.success) or 0) / feedback.samples
    feedback.failureRate = (tonumber(stats.failure) or 0) / feedback.samples
    local retargetPenalty = tonumber(cfg.outcomeRetargetFailurePenalty) or 0.55
    local activationPenalty = tonumber(cfg.outcomeActivationFailurePenalty) or 0.35

    if feedback.kind == "retarget" then
        feedback.multiplier = bdb_clamp(1.0 - feedback.failureRate * retargetPenalty + feedback.successRate * 0.12, 0.20, 1.15)
        feedback.minScoreAdd = bdb_clamp(feedback.failureRate * retargetPenalty, 0, 2.0)
    elseif feedback.kind == "materialization" then
        feedback.multiplier = bdb_clamp(1.0 - feedback.failureRate * activationPenalty + feedback.successRate * 0.08, 0.35, 1.10)
        feedback.pressureAdd = bdb_clamp(feedback.failureRate * activationPenalty, 0, 2.0)
    else
        local penalty = math.max(retargetPenalty, activationPenalty)
        feedback.multiplier = bdb_clamp(1.0 - feedback.failureRate * penalty + feedback.successRate * 0.08, 0.25, 1.10)
    end

    if feedback.failureRate >= 0.50 then
        feedback.reason = "recent_failures"
    elseif feedback.successRate >= 0.50 then
        feedback.reason = "recent_successes"
    else
        feedback.reason = "mixed_outcomes"
    end

    data.lastOutcomeFeedback = data.lastOutcomeFeedback or {}
    data.lastOutcomeFeedback[feedback.kind] = {
        t = bdb_now(),
        samples = feedback.samples,
        pending = feedback.pending,
        successRate = math.floor(feedback.successRate * 100) / 100,
        failureRate = math.floor(feedback.failureRate * 100) / 100,
        multiplier = math.floor(feedback.multiplier * 100) / 100,
        pressureAdd = math.floor(feedback.pressureAdd * 100) / 100,
        minScoreAdd = math.floor(feedback.minScoreAdd * 100) / 100,
        reason = feedback.reason
    }

    return feedback
end


function NPCDirectorBrainServerBridge.UpdatePacing(data, world, pressure, playerPressure)
    NPCDirectorBrainServerBridge.ApplySettings()
    local cfg = NPCDirectorBrainServerBridge.Config
    if not data then return nil end
    if type(data.pacing) ~= "table" then data.pacing = {phase = "quiet", phaseStartedAt = bdb_now()} end

    local now = bdb_now()
    local pacing = data.pacing
    local previous = tostring(pacing.phase or "quiet")

    if not cfg.enabled or not cfg.pacingEnabled then
        pacing.phase = "off"
        pacing.phaseStartedAt = pacing.phaseStartedAt or now
        pacing.retargetMultiplier = 1.0
        pacing.routeBiasMultiplier = 1.0
        pacing.activationPressureAdd = 0
        pacing.retargetMinScoreAdd = 0
        pacing.updatedAt = now
        return pacing
    end

    local quietThreshold = tonumber(cfg.pacingQuietPressure) or 0.70
    local buildThreshold = tonumber(cfg.pacingBuildPressure) or 1.20
    local pressureThreshold = tonumber(cfg.pacingPressureThreshold) or 1.80
    local recoveryHours = tonumber(cfg.pacingRecoveryHours) or 1.25
    if buildThreshold < quietThreshold then buildThreshold = quietThreshold end
    if pressureThreshold < buildThreshold then pressureThreshold = buildThreshold end
    if recoveryHours < 0.10 then recoveryHours = 0.10 end

    local phase = "quiet"
    local p = tonumber(pressure) or 0
    local pp = tonumber(playerPressure) or 0
    local battles = tonumber(world and world.battles) or 0

    if p >= pressureThreshold or battles > 0 then
        phase = "pressure"
        pacing.lastPressureAt = now
        pacing.recoveryUntil = now + recoveryHours
    elseif tonumber(pacing.recoveryUntil) and now < tonumber(pacing.recoveryUntil) and p >= quietThreshold * 0.55 then
        phase = "recovery"
    elseif p >= buildThreshold or pp >= 0.35 then
        phase = "build"
    else
        phase = "quiet"
    end

    if previous ~= phase then
        pacing.phaseStartedAt = now
        NPCDirectorBrainServerBridge.PushEvent("director_pacing_phase", nil, nil, nil, {
            phase = phase,
            previous = previous,
            pressure = math.floor(p * 100) / 100,
            playerPressure = math.floor(pp * 100) / 100
        })
    end

    pacing.phase = phase
    pacing.updatedAt = now
    pacing.pressure = p
    pacing.playerPressure = pp

    local boost = tonumber(cfg.pacingRetargetBoost) or 1.15
    local recoveryRetarget = tonumber(cfg.pacingRecoveryRetargetMultiplier) or 0.35
    pacing.retargetMultiplier = 1.0
    pacing.routeBiasMultiplier = 1.0
    pacing.activationPressureAdd = 0
    pacing.retargetMinScoreAdd = 0

    if phase == "quiet" then
        pacing.retargetMultiplier = 0.90
        pacing.routeBiasMultiplier = 0.85
    elseif phase == "build" then
        pacing.retargetMultiplier = bdb_clamp(boost, 0.50, 2.00)
        pacing.routeBiasMultiplier = 1.10
    elseif phase == "pressure" then
        pacing.retargetMultiplier = 0.55
        pacing.routeBiasMultiplier = 0.65
        pacing.activationPressureAdd = 0.30
        pacing.retargetMinScoreAdd = 0.20
    elseif phase == "recovery" then
        pacing.retargetMultiplier = bdb_clamp(recoveryRetarget, 0.0, 1.0)
        pacing.routeBiasMultiplier = 0.45
        pacing.activationPressureAdd = 0.45
        pacing.retargetMinScoreAdd = 0.35
    end

    return pacing
end

function NPCDirectorBrainServerBridge.GetPacingModifier(kind)
    NPCDirectorBrainServerBridge.ApplySettings()
    local cfg = NPCDirectorBrainServerBridge.Config
    local data = bdb_data()
    local pacing = data and data.pacing or nil
    if not cfg.enabled or not cfg.pacingEnabled or type(pacing) ~= "table" then
        return {phase = "off", multiplier = 1.0, pressureAdd = 0, minScoreAdd = 0}
    end

    kind = tostring(kind or "generic")
    if kind == "retarget" then
        return {
            phase = pacing.phase or "quiet",
            multiplier = tonumber(pacing.retargetMultiplier) or 1.0,
            minScoreAdd = tonumber(pacing.retargetMinScoreAdd) or 0,
            pressureAdd = 0
        }
    elseif kind == "route_bias" then
        return {
            phase = pacing.phase or "quiet",
            multiplier = tonumber(pacing.routeBiasMultiplier) or 1.0,
            minScoreAdd = 0,
            pressureAdd = 0
        }
    elseif kind == "activation" then
        return {
            phase = pacing.phase or "quiet",
            multiplier = 1.0,
            minScoreAdd = 0,
            pressureAdd = tonumber(pacing.activationPressureAdd) or 0
        }
    end

    return {phase = pacing.phase or "quiet", multiplier = 1.0, pressureAdd = 0, minScoreAdd = 0}
end


function NPCDirectorBrainServerBridge.GetLivePolicy(kind)
    NPCDirectorBrainServerBridge.ApplySettings()
    local cfg = NPCDirectorBrainServerBridge.Config
    kind = tostring(kind or "generic")

    local neutral = {
        kind = kind,
        enabled = cfg.livePolicyEnabled ~= false,
        allowed = true,
        multiplier = 1.0,
        minScoreAdd = 0,
        pressureAdd = 0,
        reason = "neutral",
        dryRun = cfg.dryRun ~= false
    }

    if not cfg.enabled or not cfg.livePolicyEnabled then return neutral end

    local data = bdb_data()
    if not data then return neutral end
    if type(data.lastLivePolicy) ~= "table" then data.lastLivePolicy = {} end

    local pressure = 0
    if type(data.pressure) == "table" then
        pressure = tonumber(data.pressure.global) or 0
    end
    local phase = "off"
    if type(data.pacing) == "table" and data.pacing.phase then
        phase = tostring(data.pacing.phase)
    end

    local policy = {
        kind = kind,
        enabled = true,
        allowed = true,
        multiplier = 1.0,
        minScoreAdd = 0,
        pressureAdd = 0,
        reason = "ok",
        pressure = pressure,
        phase = phase,
        dryRun = cfg.dryRun ~= false,
        t = bdb_now()
    }

    local minSamples = math.floor(tonumber(cfg.livePolicyMinOutcomeSamples) or 3)
    if minSamples < 0 then minSamples = 0 end
    local failureLimit = tonumber(cfg.livePolicyFailureRateLimit) or 0.65
    failureLimit = bdb_clamp(failureLimit, 0, 1)

    if kind == "retarget" then
        local limit = tonumber(cfg.livePolicyRetargetPressureLimit) or 1.45
        if pressure >= limit then
            policy.allowed = false
            policy.multiplier = 0
            policy.reason = "live_policy_retarget_pressure"
        elseif cfg.livePolicyRecoveryRetargetBlock and phase == "recovery" then
            policy.allowed = false
            policy.multiplier = 0
            policy.reason = "live_policy_recovery"
        else
            local feedback = NPCDirectorBrainServerBridge.GetOutcomeFeedback("retarget")
            if feedback and (tonumber(feedback.samples) or 0) >= minSamples and (tonumber(feedback.failureRate) or 0) >= failureLimit then
                policy.allowed = false
                policy.multiplier = 0
                policy.minScoreAdd = tonumber(cfg.outcomeRetargetFailurePenalty) or 0.55
                policy.reason = "live_policy_retarget_failures"
            elseif phase == "pressure" then
                policy.multiplier = math.min(policy.multiplier, 0.50)
                policy.minScoreAdd = 0.15
                policy.reason = "live_policy_pressure_slowdown"
            end
        end
    elseif kind == "route_bias" then
        local limit = tonumber(cfg.livePolicyRouteBiasPressureLimit) or 2.0
        if pressure >= limit then
            policy.multiplier = 0.35
            policy.reason = "live_policy_route_pressure"
        elseif phase == "recovery" then
            policy.multiplier = 0.50
            policy.reason = "live_policy_route_recovery"
        elseif phase == "pressure" then
            policy.multiplier = 0.65
            policy.reason = "live_policy_route_pressure_phase"
        end
    elseif kind == "activation" then
        local limit = tonumber(cfg.livePolicyPressureLimit) or 2.20
        if pressure >= limit then
            policy.pressureAdd = math.min(1.0, (pressure - limit) * 0.5 + 0.20)
            policy.reason = "live_policy_activation_pressure"
        end
        local feedback = NPCDirectorBrainServerBridge.GetOutcomeFeedback("materialization")
        if feedback and (tonumber(feedback.samples) or 0) >= minSamples and (tonumber(feedback.failureRate) or 0) >= failureLimit then
            policy.pressureAdd = math.max(tonumber(policy.pressureAdd) or 0, tonumber(cfg.outcomeActivationFailurePenalty) or 0.35)
            policy.reason = "live_policy_activation_failures"
        end
    end

    policy.multiplier = bdb_clamp(policy.multiplier, 0, 2.0)
    policy.minScoreAdd = bdb_clamp(policy.minScoreAdd, 0, 5.0)
    policy.pressureAdd = bdb_clamp(policy.pressureAdd, 0, 3.0)

    data.lastLivePolicy[kind] = {
        t = policy.t,
        kind = policy.kind,
        allowed = policy.allowed,
        multiplier = policy.multiplier,
        minScoreAdd = policy.minScoreAdd,
        pressureAdd = policy.pressureAdd,
        reason = policy.reason,
        pressure = math.floor((policy.pressure or 0) * 100) / 100,
        phase = policy.phase,
        dryRun = policy.dryRun
    }

    return policy
end


local function bdb_trimIntentLedger(data)
    if not data or type(data.intentLedger) ~= "table" then return 0 end

    local maxRecords = math.floor(tonumber(NPCDirectorBrainServerBridge.Config.intentLedgerMaxRecords) or 144)
    if maxRecords < 20 then maxRecords = 20 end
    local windowHours = tonumber(NPCDirectorBrainServerBridge.Config.intentLedgerWindowHours) or 12
    if windowHours < 1 then windowHours = 1 end
    local now = bdb_now()

    local kept = {}
    for _, record in ipairs(data.intentLedger) do
        local t = tonumber(record and record.t) or 0
        if t > 0 and now - t <= windowHours * 2 then
            kept[#kept + 1] = record
        end
    end
    while #kept > maxRecords do
        table.remove(kept, 1)
    end
    data.intentLedger = kept
    return #kept
end

local function bdb_intentTopCandidates(candidates)
    local out = {}
    local limit = math.floor(tonumber(NPCDirectorBrainServerBridge.Config.intentLedgerTopCandidates) or 5)
    if limit < 1 then limit = 1 end
    if limit > 10 then limit = 10 end
    if type(candidates) ~= "table" then return out end

    for i = 1, math.min(#candidates, limit) do
        local candidate = candidates[i]
        if candidate then
            out[#out + 1] = {
                kind = tostring(candidate.kind or "unknown"),
                score = math.floor((tonumber(candidate.score) or 0) * 100) / 100,
                reason = tostring(candidate.reason or "")
            }
        end
    end
    return out
end

function NPCDirectorBrainServerBridge.UpdateIntentSummary(data)
    local summary = {
        t = bdb_now(),
        records = 0,
        dominantIntent = nil,
        dominantPhase = nil,
        avgPressure = 0,
        dryRunRecords = 0,
        liveRecords = 0,
        intents = {},
        phases = {}
    }

    if not data or type(data.intentLedger) ~= "table" then return summary end

    local now = bdb_now()
    local windowHours = tonumber(NPCDirectorBrainServerBridge.Config.intentLedgerWindowHours) or 12
    if windowHours < 1 then windowHours = 1 end
    local pressureSum = 0

    for _, record in ipairs(data.intentLedger) do
        local age = now - (tonumber(record and record.t) or now)
        if age >= 0 and age <= windowHours then
            local intent = tostring(record.selected or "unknown")
            local phase = tostring(record.pacingPhase or "unknown")
            summary.records = summary.records + 1
            summary.intents[intent] = (tonumber(summary.intents[intent]) or 0) + 1
            summary.phases[phase] = (tonumber(summary.phases[phase]) or 0) + 1
            pressureSum = pressureSum + (tonumber(record.pressure) or 0)
            if record.dryRun then summary.dryRunRecords = summary.dryRunRecords + 1 else summary.liveRecords = summary.liveRecords + 1 end
        end
    end

    if summary.records > 0 then
        summary.avgPressure = math.floor((pressureSum / summary.records) * 100) / 100
    end

    local bestIntentCount = 0
    for intent, count in pairs(summary.intents) do
        if count > bestIntentCount then
            bestIntentCount = count
            summary.dominantIntent = intent
        end
    end

    local bestPhaseCount = 0
    for phase, count in pairs(summary.phases) do
        if count > bestPhaseCount then
            bestPhaseCount = count
            summary.dominantPhase = phase
        end
    end

    data.lastIntentSummary = summary
    return summary
end

function NPCDirectorBrainServerBridge.RecordIntentDecision(data, decision, candidates)
    NPCDirectorBrainServerBridge.ApplySettings()
    local cfg = NPCDirectorBrainServerBridge.Config
    if not cfg.enabled or not cfg.intentLedgerEnabled then return false end
    if not data or type(decision) ~= "table" then return false end

    if type(data.intentLedger) ~= "table" then data.intentLedger = {} end
    if type(data.intentStats) ~= "table" then data.intentStats = {} end
    data.intentSeq = (tonumber(data.intentSeq) or 0) + 1

    local selected = tostring(decision.selected or "wait")
    local phase = tostring(decision.pacingPhase or "unknown")
    local record = {
        seq = data.intentSeq,
        t = tonumber(decision.t) or bdb_now(),
        dryRun = decision.dryRun ~= false,
        selected = selected,
        score = math.floor((tonumber(decision.score) or 0) * 100) / 100,
        reason = tostring(decision.reason or ""),
        pressure = math.floor((tonumber(decision.pressure) or 0) * 100) / 100,
        playerCount = tonumber(decision.playerCount) or 0,
        pacingPhase = phase,
        pendingOutcomes = tonumber(decision.pendingOutcomes) or 0,
        reviewedOutcomes = tonumber(decision.reviewedOutcomes) or 0,
        candidates = bdb_intentTopCandidates(candidates)
    }

    table.insert(data.intentLedger, record)
    local stats = data.intentStats[selected]
    if type(stats) ~= "table" then
        stats = {count = 0}
        data.intentStats[selected] = stats
    end
    stats.count = (tonumber(stats.count) or 0) + 1
    stats.lastAt = record.t
    stats.lastScore = record.score
    stats.lastPhase = phase

    bdb_trimIntentLedger(data)
    NPCDirectorBrainServerBridge.UpdateIntentSummary(data)

    local previous = data.lastIntentKind
    data.lastIntentKind = selected
    data.lastIntentAt = record.t
    if previous ~= selected then
        NPCDirectorBrainServerBridge.PushEvent("director_intent_recorded", nil, nil, nil, {
            selected = selected,
            previous = tostring(previous or ""),
            phase = phase,
            pressure = record.pressure,
            dryRun = record.dryRun
        })
    end

    return true
end



local function bdb_trimTelemetry(data)
    if not data or type(data.telemetry) ~= "table" then return 0 end

    local maxRecords = math.floor(tonumber(NPCDirectorBrainServerBridge.Config.telemetryMaxRecords) or 96)
    if maxRecords < 12 then maxRecords = 12 end
    local windowHours = tonumber(NPCDirectorBrainServerBridge.Config.telemetryWindowHours) or 24
    if windowHours < 1 then windowHours = 1 end
    local now = bdb_now()

    local kept = {}
    for _, record in ipairs(data.telemetry) do
        local t = tonumber(record and record.t) or 0
        if t > 0 and now - t <= windowHours * 2 then
            kept[#kept + 1] = record
        end
    end
    while #kept > maxRecords do
        table.remove(kept, 1)
    end
    data.telemetry = kept
    return #kept
end

local function bdb_recentEventKinds(data)
    local out = {}
    local limit = math.floor(tonumber(NPCDirectorBrainServerBridge.Config.telemetryTopEvents) or 6)
    if limit <= 0 then return out end
    if limit > 20 then limit = 20 end
    local now = bdb_now()
    local counts = {}

    for _, event in ipairs(data and data.events or {}) do
        local age = now - (tonumber(event and event.t) or now)
        if age >= 0 and age <= 2.0 then
            local kind = tostring(event.kind or "unknown")
            counts[kind] = (tonumber(counts[kind]) or 0) + 1
        end
    end

    for kind, count in pairs(counts) do
        out[#out + 1] = {kind = kind, count = count}
    end
    table.sort(out, function(a, b) return (a.count or 0) > (b.count or 0) end)
    while #out > limit do table.remove(out) end
    return out
end

local function bdb_countPendingOutcomes(data)
    local pending = 0
    local reviewed = 0
    if type(data and data.outcomes) == "table" then
        for _, outcome in pairs(data.outcomes) do
            if outcome and outcome.status == "pending" then pending = pending + 1
            elseif outcome and outcome.status == "reviewed" then reviewed = reviewed + 1 end
        end
    end
    return pending, reviewed
end

function NPCDirectorBrainServerBridge.UpdateTelemetrySummary(data)
    local summary = {
        t = bdb_now(),
        records = 0,
        avgPressure = 0,
        maxPressure = 0,
        pressureTrend = "stable",
        dominantPhase = nil,
        dominantDecision = nil,
        dryRunRecords = 0,
        liveRecords = 0,
        phases = {},
        decisions = {}
    }

    if not data or type(data.telemetry) ~= "table" then return summary end
    local now = bdb_now()
    local windowHours = tonumber(NPCDirectorBrainServerBridge.Config.telemetryWindowHours) or 24
    if windowHours < 1 then windowHours = 1 end
    local pressureSum = 0
    local firstPressure = nil
    local lastPressure = nil

    for _, record in ipairs(data.telemetry) do
        local age = now - (tonumber(record and record.t) or now)
        if age >= 0 and age <= windowHours then
            summary.records = summary.records + 1
            local pressure = tonumber(record.pressure and record.pressure.global) or 0
            pressureSum = pressureSum + pressure
            if pressure > summary.maxPressure then summary.maxPressure = pressure end
            if firstPressure == nil then firstPressure = pressure end
            lastPressure = pressure

            local phase = tostring(record.pacingPhase or "unknown")
            local decision = tostring(record.decision or "unknown")
            summary.phases[phase] = (tonumber(summary.phases[phase]) or 0) + 1
            summary.decisions[decision] = (tonumber(summary.decisions[decision]) or 0) + 1
            if record.dryRun then summary.dryRunRecords = summary.dryRunRecords + 1 else summary.liveRecords = summary.liveRecords + 1 end
        end
    end

    if summary.records > 0 then
        summary.avgPressure = math.floor((pressureSum / summary.records) * 100) / 100
        summary.maxPressure = math.floor(summary.maxPressure * 100) / 100
    end
    if firstPressure ~= nil and lastPressure ~= nil then
        local delta = lastPressure - firstPressure
        if delta > 0.30 then summary.pressureTrend = "rising"
        elseif delta < -0.30 then summary.pressureTrend = "falling" end
    end

    local bestPhaseCount = 0
    for phase, count in pairs(summary.phases) do
        if count > bestPhaseCount then
            bestPhaseCount = count
            summary.dominantPhase = phase
        end
    end

    local bestDecisionCount = 0
    for decision, count in pairs(summary.decisions) do
        if count > bestDecisionCount then
            bestDecisionCount = count
            summary.dominantDecision = decision
        end
    end

    data.lastTelemetrySummary = summary
    return summary
end

function NPCDirectorBrainServerBridge.RecordTelemetrySnapshot(data, world, pressure, eventPressure, playerPressure, groupPressure, updatedPlayers, activeCellCooldowns, pendingOutcomes, reviewedOutcomes, candidates)
    NPCDirectorBrainServerBridge.ApplySettings()
    local cfg = NPCDirectorBrainServerBridge.Config
    if not cfg.enabled or not cfg.telemetryEnabled then return false end
    if not data then return false end

    if type(data.telemetry) ~= "table" then data.telemetry = {} end
    local now = bdb_now()
    local interval = tonumber(cfg.telemetryIntervalHours) or 1.0
    if interval < 0.10 then interval = 0.10 end
    if data.lastTelemetryAt and now - (tonumber(data.lastTelemetryAt) or 0) < interval then
        return false
    end

    local pending, reviewed = bdb_countPendingOutcomes(data)
    pendingOutcomes = tonumber(pendingOutcomes) or pending
    reviewedOutcomes = tonumber(reviewedOutcomes) or reviewed

    data.telemetrySeq = (tonumber(data.telemetrySeq) or 0) + 1
    local decision = data.lastDecision or {}
    local record = {
        seq = data.telemetrySeq,
        t = now,
        dryRun = cfg.dryRun ~= false,
        pressure = {
            global = math.floor((tonumber(pressure) or 0) * 100) / 100,
            event = math.floor((tonumber(eventPressure) or 0) * 100) / 100,
            player = math.floor((tonumber(playerPressure) or 0) * 100) / 100,
            group = math.floor((tonumber(groupPressure) or 0) * 100) / 100
        },
        world = {
            virtual = tonumber(world and world.virtual) or 0,
            physical = tonumber(world and world.physical) or 0,
            roadPatrols = tonumber(world and world.roadPatrols) or 0,
            battles = tonumber(world and world.battles) or 0,
            bases = tonumber(world and world.bases) or 0,
            markers = tonumber(world and world.markers) or 0,
            queue = tonumber(world and world.queue) or 0
        },
        pacingPhase = data.pacing and tostring(data.pacing.phase or "unknown") or "unknown",
        decision = tostring(decision.selected or "wait"),
        policyRetarget = data.lastLivePolicy and data.lastLivePolicy.retarget and tostring(data.lastLivePolicy.retarget.reason or "ok") or "ok",
        pendingOutcomes = pendingOutcomes,
        reviewedOutcomes = reviewedOutcomes,
        intentSummary = data.lastIntentSummary and tostring(data.lastIntentSummary.dominantIntent or "") or "",
        telemetryRecordsBefore = #data.telemetry,
        memoryCells = bdb_count(data.worldMemory),
        cellCooldowns = tonumber(activeCellCooldowns) or bdb_count(data.cellCooldowns),
        players = tonumber(updatedPlayers) or 0,
        recentEvents = bdb_recentEventKinds(data),
        candidates = bdb_intentTopCandidates(candidates)
    }

    table.insert(data.telemetry, record)
    data.lastTelemetryAt = now
    bdb_trimTelemetry(data)
    NPCDirectorBrainServerBridge.UpdateTelemetrySummary(data)

    local previousBand = data.lastTelemetryPressureBand
    local band = "low"
    if record.pressure.global >= 2.0 then band = "high"
    elseif record.pressure.global >= 1.0 then band = "medium" end
    data.lastTelemetryPressureBand = band
    if previousBand ~= band then
        NPCDirectorBrainServerBridge.PushEvent("director_telemetry_snapshot", nil, nil, nil, {
            band = band,
            previous = tostring(previousBand or ""),
            pressure = record.pressure.global,
            phase = record.pacingPhase,
            decision = record.decision
        })
    end

    return true
end

local function bdb_trimHealthWarnings(data)
    if not data or type(data.healthWarnings) ~= "table" then return 0 end
    local cfg = NPCDirectorBrainServerBridge.Config
    local maxRecords = math.floor(tonumber(cfg.healthMaxRecords) or 80)
    if maxRecords < 10 then maxRecords = 10 end
    local windowHours = tonumber(cfg.healthWindowHours) or 12
    if windowHours < 1 then windowHours = 1 end
    local now = bdb_now()

    local kept = {}
    for _, warning in ipairs(data.healthWarnings) do
        local t = tonumber(warning and warning.t) or 0
        if t > 0 and now - t <= windowHours * 2 then
            kept[#kept + 1] = warning
        end
    end
    while #kept > maxRecords do
        table.remove(kept, 1)
    end
    data.healthWarnings = kept
    return #kept
end

local function bdb_recordHealthWarning(data, kind, severity, reason, meta)
    if not data then return false end
    if type(data.healthWarnings) ~= "table" then data.healthWarnings = {} end
    data.healthSeq = (tonumber(data.healthSeq) or 0) + 1

    local now = bdb_now()
    local selected = data.lastDecision and data.lastDecision.selected or nil
    local pressure = data.pressure and data.pressure.global or nil
    local phase = data.pacing and data.pacing.phase or nil
    local warning = {
        seq = data.healthSeq,
        t = now,
        kind = tostring(kind or "unknown"),
        severity = tostring(severity or "info"),
        reason = tostring(reason or ""),
        pressure = math.floor((tonumber(pressure) or 0) * 100) / 100,
        pacingPhase = phase and tostring(phase) or nil,
        selected = selected and tostring(selected) or nil,
        meta = bdb_metaCopy(meta)
    }
    data.healthWarnings[#data.healthWarnings + 1] = warning
    bdb_trimHealthWarnings(data)

    local eventKey = warning.kind .. ":" .. warning.severity
    if data.lastHealthWarningKey ~= eventKey or now - (tonumber(data.lastHealthWarningAt) or 0) >= 1.0 then
        data.lastHealthWarningKey = eventKey
        data.lastHealthWarningAt = now
        NPCDirectorBrainServerBridge.PushEvent("director_health_warning", nil, nil, nil, {
            kind = warning.kind,
            severity = warning.severity,
            reason = warning.reason,
            pressure = warning.pressure
        })
    end
    return true
end

function NPCDirectorBrainServerBridge.UpdateHealthSummary(data)
    local summary = {
        t = bdb_now(),
        records = 0,
        info = 0,
        warning = 0,
        critical = 0,
        dominantKind = nil,
        lastSeverity = nil,
        lastKind = nil,
        kinds = {}
    }

    if not data or type(data.healthWarnings) ~= "table" then return summary end
    local now = bdb_now()
    local windowHours = tonumber(NPCDirectorBrainServerBridge.Config.healthWindowHours) or 12
    if windowHours < 1 then windowHours = 1 end

    for _, warning in ipairs(data.healthWarnings) do
        local age = now - (tonumber(warning and warning.t) or now)
        if age >= 0 and age <= windowHours then
            local kind = tostring(warning.kind or "unknown")
            local severity = tostring(warning.severity or "info")
            summary.records = summary.records + 1
            summary.kinds[kind] = (tonumber(summary.kinds[kind]) or 0) + 1
            if severity == "critical" then summary.critical = summary.critical + 1
            elseif severity == "warning" then summary.warning = summary.warning + 1
            else summary.info = summary.info + 1 end
            summary.lastSeverity = severity
            summary.lastKind = kind
        end
    end

    local bestCount = 0
    for kind, count in pairs(summary.kinds) do
        if count > bestCount then
            bestCount = count
            summary.dominantKind = kind
        end
    end

    data.lastHealthSummary = summary
    return summary
end

function NPCDirectorBrainServerBridge.RunHealthMonitor(data, world, pressure, pendingOutcomes, reviewedOutcomes, candidates)
    NPCDirectorBrainServerBridge.ApplySettings()
    local cfg = NPCDirectorBrainServerBridge.Config
    if not cfg.enabled or not cfg.healthMonitorEnabled then return 0 end
    if not data or not world then return 0 end

    local created = 0
    local pressureLimit = tonumber(cfg.healthPressureWarning) or 2.75
    local queueLimit = tonumber(cfg.healthQueueWarning) or 80
    local markerLimit = tonumber(cfg.healthMarkerWarning) or 450
    local virtualLimit = tonumber(cfg.healthVirtualGroupWarning) or 180
    local repeatLimit = math.floor(tonumber(cfg.healthRepeatIntentCount) or 5)

    if pressure >= pressureLimit then
        local severity = "warning"
        if pressure >= pressureLimit + 1.0 then severity = "critical" end
        if bdb_recordHealthWarning(data, "high_pressure", severity, "director pressure above health warning threshold", {
            pressure = math.floor((tonumber(pressure) or 0) * 100) / 100,
            threshold = pressureLimit
        }) then created = created + 1 end
    end

    if queueLimit > 0 and (tonumber(world.queue) or 0) >= queueLimit then
        if bdb_recordHealthWarning(data, "queue_load", "warning", "spawn/brain queue count is high", {
            queue = tonumber(world.queue) or 0,
            threshold = queueLimit
        }) then created = created + 1 end
    end

    if markerLimit > 0 and (tonumber(world.markers) or 0) >= markerLimit then
        if bdb_recordHealthWarning(data, "marker_load", "warning", "debug marker count is high", {
            markers = tonumber(world.markers) or 0,
            threshold = markerLimit
        }) then created = created + 1 end
    end

    if virtualLimit > 0 and (tonumber(world.virtual) or 0) >= virtualLimit then
        if bdb_recordHealthWarning(data, "virtual_group_load", "warning", "virtual group count is high", {
            virtual = tonumber(world.virtual) or 0,
            threshold = virtualLimit
        }) then created = created + 1 end
    end

    local telemetry = data.lastTelemetrySummary
    if telemetry and telemetry.pressureTrend == "rising" and (tonumber(telemetry.maxPressure) or 0) >= pressureLimit then
        if bdb_recordHealthWarning(data, "rising_pressure_trend", "info", "telemetry pressure trend is rising near the warning threshold", {
            avgPressure = tonumber(telemetry.avgPressure) or 0,
            maxPressure = tonumber(telemetry.maxPressure) or 0
        }) then created = created + 1 end
    end

    local intent = data.lastIntentSummary
    if intent and intent.dominantIntent and repeatLimit > 0 then
        local count = tonumber(intent.intents and intent.intents[intent.dominantIntent]) or 0
        if count >= repeatLimit and tostring(intent.dominantIntent) ~= "wait" and (tonumber(intent.avgPressure) or 0) >= 1.2 then
            if bdb_recordHealthWarning(data, "repeated_intent", "info", "same director diagnostic intent dominates the recent window", {
                intent = tostring(intent.dominantIntent),
                count = count,
                avgPressure = tonumber(intent.avgPressure) or 0
            }) then created = created + 1 end
        end
    end

    local feedback = data.lastOutcomeFeedback or {}
    local retargetFeedback = feedback.retarget
    if retargetFeedback and (tonumber(retargetFeedback.samples) or 0) >= 3 and (tonumber(retargetFeedback.failureRate) or 0) >= 0.65 then
        if bdb_recordHealthWarning(data, "retarget_failure_rate", "warning", "recent live retarget outcomes have high failure rate", {
            samples = tonumber(retargetFeedback.samples) or 0,
            failureRate = tonumber(retargetFeedback.failureRate) or 0
        }) then created = created + 1 end
    end

    local materializationFeedback = feedback.materialization
    if materializationFeedback and (tonumber(materializationFeedback.samples) or 0) >= 3 and (tonumber(materializationFeedback.failureRate) or 0) >= 0.65 then
        if bdb_recordHealthWarning(data, "materialization_failure_rate", "warning", "recent materialization outcomes have high failure rate", {
            samples = tonumber(materializationFeedback.samples) or 0,
            failureRate = tonumber(materializationFeedback.failureRate) or 0
        }) then created = created + 1 end
    end

    if (tonumber(pendingOutcomes) or 0) >= 12 then
        if bdb_recordHealthWarning(data, "pending_outcome_backlog", "info", "director has a large pending outcome backlog", {
            pending = tonumber(pendingOutcomes) or 0,
            reviewed = tonumber(reviewedOutcomes) or 0
        }) then created = created + 1 end
    end

    local summary = NPCDirectorBrainServerBridge.UpdateHealthSummary(data)
    data.lastHealthCheck = {
        t = bdb_now(),
        created = created,
        records = summary and summary.records or 0,
        lastSeverity = summary and summary.lastSeverity or nil,
        dominantKind = summary and summary.dominantKind or nil,
        pressure = math.floor((tonumber(pressure) or 0) * 100) / 100
    }
    return created
end


local function bdb_trimProfileWarnings(data)
    if not data or type(data.profileWarnings) ~= "table" then return 0 end
    while #data.profileWarnings > 40 do
        table.remove(data.profileWarnings, 1)
    end
    return #data.profileWarnings
end

local function bdb_recordProfileWarning(data, kind, severity, message, meta)
    if not data or not NPCDirectorBrainServerBridge.Config.profileWarningsEnabled then return false end
    if type(data.profileWarnings) ~= "table" then data.profileWarnings = {} end
    local now = bdb_now()
    local key = tostring(kind or "profile_warning") .. ":" .. tostring(severity or "info")
    if data.lastProfileWarningKey == key and now - (tonumber(data.lastProfileWarningAt) or 0) < 1.0 then
        return false
    end
    local record = {
        seq = (tonumber(data.profileWarningSeq) or 0) + 1,
        t = now,
        kind = tostring(kind or "profile_warning"),
        severity = tostring(severity or "info"),
        message = tostring(message or "director profile warning"),
        profile = NPCDirectorBrainServerBridge.Config.profileName or "unknown",
        meta = bdb_metaCopy(meta)
    }
    data.profileWarningSeq = record.seq
    data.lastProfileWarningKey = key
    data.lastProfileWarningAt = now
    data.profileWarnings[#data.profileWarnings + 1] = record
    bdb_trimProfileWarnings(data)
    NPCDirectorBrainServerBridge.PushEvent("director_profile_warning", nil, nil, nil, {
        kind = record.kind,
        severity = record.severity,
        profile = record.profile
    })
    return true
end

function NPCDirectorBrainServerBridge.UpdateProfileSummary(data, world, pressure)
    local cfg = NPCDirectorBrainServerBridge.Config
    if not data or not cfg then return nil end
    if type(data.profileWarnings) ~= "table" then data.profileWarnings = {} end

    local warningsBefore = #data.profileWarnings
    if cfg.profileWarningsEnabled then
        if cfg.dryRun == false and not cfg.livePolicyEnabled then
            bdb_recordProfileWarning(data, "live_policy_disabled", "warning", "director live mode has no live-policy safety gate", {
                profile = cfg.profileName or "unknown"
            })
        end
        if cfg.dryRun == false and not cfg.pressureGuardEnabled then
            bdb_recordProfileWarning(data, "pressure_guard_disabled", "warning", "director live mode has no activation pressure guard", {
                profile = cfg.profileName or "unknown"
            })
        end
        if cfg.dryRun == false and (tonumber(cfg.retargetMaxGroupsPerUpdate) or 0) > 2 then
            bdb_recordProfileWarning(data, "retarget_budget_high", "warning", "director live retarget budget is high", {
                maxGroups = tonumber(cfg.retargetMaxGroupsPerUpdate) or 0
            })
        end
        if cfg.dryRun == false and (tonumber(cfg.routeBiasStrength) or 0) > 1.5 then
            bdb_recordProfileWarning(data, "route_bias_strong", "info", "director route-memory bias is strong in live mode", {
                strength = tonumber(cfg.routeBiasStrength) or 0
            })
        end
        if cfg.dryRun == false and (tonumber(pressure) or 0) >= (tonumber(cfg.livePolicyPressureLimit) or 2.2) and cfg.livePolicyEnabled then
            bdb_recordProfileWarning(data, "live_pressure_near_limit", "info", "director live mode is near the live-policy pressure limit", {
                pressure = math.floor((tonumber(pressure) or 0) * 100) / 100,
                limit = tonumber(cfg.livePolicyPressureLimit) or 0
            })
        end
        if cfg.profile == 4 and cfg.dryRun == false and cfg.adminReportEnabled ~= true then
            bdb_recordProfileWarning(data, "custom_live_no_report", "info", "custom live profile has admin report disabled", {})
        end
    end

    local recentWarnings = 0
    local latestSeverity = nil
    local now = bdb_now()
    for _, warning in ipairs(data.profileWarnings) do
        if now - (tonumber(warning.t) or 0) <= 12 then
            recentWarnings = recentWarnings + 1
            latestSeverity = warning.severity or latestSeverity
        end
    end

    data.lastProfileSummary = {
        t = now,
        id = tonumber(cfg.profile) or 1,
        name = tostring(cfg.profileName or bdb_profileName(cfg.profile)),
        applied = tostring(cfg.profileApplied or cfg.profileName or "unknown"),
        risk = tostring(cfg.profileRisk or "custom"),
        notes = cfg.profileNotes and tostring(cfg.profileNotes) or nil,
        dryRun = cfg.dryRun ~= false,
        liveAssist = cfg.dryRun == false,
        warnings = recentWarnings,
        warningRecords = #data.profileWarnings,
        created = #data.profileWarnings - warningsBefore,
        latestSeverity = latestSeverity,
        pressure = math.floor((tonumber(pressure) or 0) * 100) / 100,
        virtual = world and tonumber(world.virtual) or nil,
        physical = world and tonumber(world.physical) or nil
    }

    return data.lastProfileSummary
end


local function bdb_adminPressureBand(pressure)
    pressure = tonumber(pressure) or 0
    if pressure >= 2.75 then return "critical" end
    if pressure >= 2.00 then return "high" end
    if pressure >= 1.00 then return "medium" end
    return "low"
end

local function bdb_adminRound(value)
    return math.floor((tonumber(value) or 0) * 100) / 100
end


local function bdb_trimConsistencyWarnings(data)
    if not data or type(data.consistencyWarnings) ~= "table" then return 0 end

    local maxRecords = math.floor(tonumber(NPCDirectorBrainServerBridge.Config.consistencyMaxRecords) or 80)
    if maxRecords < 10 then maxRecords = 10 end
    local windowHours = tonumber(NPCDirectorBrainServerBridge.Config.consistencyWindowHours) or 12
    if windowHours < 1 then windowHours = 1 end
    local now = bdb_now()

    local kept = {}
    for _, record in ipairs(data.consistencyWarnings) do
        local t = tonumber(record and record.t) or 0
        if t > 0 and now - t <= windowHours * 2 then
            kept[#kept + 1] = record
        end
    end
    while #kept > maxRecords do
        table.remove(kept, 1)
    end
    data.consistencyWarnings = kept
    return #kept
end

local function bdb_recordConsistencyWarning(data, kind, severity, message, meta)
    if not data then return false end
    if type(data.consistencyWarnings) ~= "table" then data.consistencyWarnings = {} end

    local now = bdb_now()
    local key = tostring(kind or "unknown") .. ":" .. tostring(severity or "info")
    if data.lastConsistencyWarningKey == key and now - (tonumber(data.lastConsistencyWarningAt) or 0) < 1.0 then
        return false
    end

    data.consistencySeq = (tonumber(data.consistencySeq) or 0) + 1
    local record = {
        seq = data.consistencySeq,
        t = now,
        kind = tostring(kind or "unknown"),
        severity = tostring(severity or "info"),
        message = tostring(message or ""),
        meta = bdb_metaCopy(meta)
    }
    data.consistencyWarnings[#data.consistencyWarnings + 1] = record
    data.lastConsistencyWarningKey = key
    data.lastConsistencyWarningAt = now
    bdb_trimConsistencyWarnings(data)

    NPCDirectorBrainServerBridge.PushEvent("director_consistency_warning", nil, nil, nil, {
        kind = record.kind,
        severity = record.severity,
        message = record.message
    })
    return true
end

function NPCDirectorBrainServerBridge.UpdateConsistencySummary(data)
    local summary = {
        t = bdb_now(),
        records = 0,
        info = 0,
        warning = 0,
        critical = 0,
        dominantKind = nil,
        lastKind = nil,
        lastSeverity = nil,
        status = "ok",
        kinds = {}
    }

    if not data or type(data.consistencyWarnings) ~= "table" then
        if data then data.lastConsistencySummary = summary end
        return summary
    end

    local now = bdb_now()
    local windowHours = tonumber(NPCDirectorBrainServerBridge.Config.consistencyWindowHours) or 12
    if windowHours < 1 then windowHours = 1 end

    for _, warning in ipairs(data.consistencyWarnings) do
        local age = now - (tonumber(warning and warning.t) or now)
        if age >= 0 and age <= windowHours then
            local severity = tostring(warning.severity or "info")
            local kind = tostring(warning.kind or "unknown")
            summary.records = summary.records + 1
            summary.kinds[kind] = (tonumber(summary.kinds[kind]) or 0) + 1
            if severity == "critical" then summary.critical = summary.critical + 1
            elseif severity == "warning" then summary.warning = summary.warning + 1
            else summary.info = summary.info + 1 end
            summary.lastKind = kind
            summary.lastSeverity = severity
        end
    end

    local bestKindCount = 0
    for kind, count in pairs(summary.kinds) do
        if count > bestKindCount then
            bestKindCount = count
            summary.dominantKind = kind
        end
    end

    if summary.critical > 0 then summary.status = "critical"
    elseif summary.warning > 0 then summary.status = "warning"
    elseif summary.info > 0 then summary.status = "info" end

    data.lastConsistencySummary = summary
    return summary
end

function NPCDirectorBrainServerBridge.RunConsistencyCheck(data, world, pressure, pendingOutcomes, reviewedOutcomes, candidates)
    NPCDirectorBrainServerBridge.ApplySettings()
    local cfg = NPCDirectorBrainServerBridge.Config
    if not cfg.enabled or not cfg.consistencyCheckEnabled then return false end
    if not data then return false end

    local now = bdb_now()
    local interval = tonumber(cfg.consistencyIntervalHours) or 1.0
    if interval < 0.10 then interval = 0.10 end
    if data.lastConsistencyCheckAt and now - (tonumber(data.lastConsistencyCheckAt) or 0) < interval then
        return false
    end
    data.lastConsistencyCheckAt = now

    local before = type(data.consistencyWarnings) == "table" and #data.consistencyWarnings or 0
    local modeLive = cfg.dryRun == false
    local profileName = tostring(cfg.profileName or "unknown")

    local requiredTables = {
        "events", "worldMemory", "cellCooldowns", "outcomes", "intentLedger",
        "telemetry", "healthWarnings", "adminReports", "profileWarnings", "runtimeSafetyLocks"
    }
    for _, key in ipairs(requiredTables) do
        if type(data[key]) ~= "table" then
            bdb_recordConsistencyWarning(data, "missing_table_" .. key, "warning", "director diagnostic table is missing or invalid", {table = key})
        end
    end

    if modeLive and cfg.livePolicyEnabled ~= true then
        bdb_recordConsistencyWarning(data, "live_without_policy", "critical", "director live mode has no live-policy safety gate", {profile = profileName})
    end
    if modeLive and cfg.pressureGuardEnabled ~= true then
        bdb_recordConsistencyWarning(data, "live_without_pressure_guard", "critical", "director live mode has no activation pressure guard", {profile = profileName})
    end
    if modeLive and cfg.outcomeTrackingEnabled ~= true then
        bdb_recordConsistencyWarning(data, "live_without_outcome_tracking", "warning", "director live mode has no outcome tracking diagnostics", {profile = profileName})
    end
    if modeLive and cfg.healthMonitorEnabled ~= true then
        bdb_recordConsistencyWarning(data, "live_without_health_monitor", "warning", "director live mode has no health monitor diagnostics", {profile = profileName})
    end
    if modeLive and cfg.adminReportEnabled ~= true then
        bdb_recordConsistencyWarning(data, "live_without_admin_report", "info", "director live mode has no compact admin report", {profile = profileName})
    end

    local threshold = tonumber(cfg.pressureGuardThreshold) or 0
    local hardThreshold = tonumber(cfg.pressureGuardHardThreshold) or 0
    if cfg.pressureGuardEnabled and hardThreshold < threshold then
        bdb_recordConsistencyWarning(data, "pressure_threshold_order", "warning", "hard pressure threshold is below normal threshold", {
            threshold = threshold,
            hard = hardThreshold
        })
    end

    if modeLive and cfg.consistencyStrictLiveMode then
        if (tonumber(cfg.retargetMaxGroupsPerUpdate) or 0) > 2 then
            bdb_recordConsistencyWarning(data, "live_retarget_budget_high", "warning", "live retarget budget is high", {
                budget = tonumber(cfg.retargetMaxGroupsPerUpdate) or 0
            })
        end
        if (tonumber(cfg.routeBiasStrength) or 0) > 1.50 then
            bdb_recordConsistencyWarning(data, "live_route_bias_high", "warning", "live route-memory bias is strong", {
                strength = tonumber(cfg.routeBiasStrength) or 0
            })
        end
        if (tonumber(cfg.livePolicyFailureRateLimit) or 0) > 0.80 then
            bdb_recordConsistencyWarning(data, "live_failure_limit_loose", "info", "live-policy failure limit is loose", {
                limit = tonumber(cfg.livePolicyFailureRateLimit) or 0
            })
        end
    end

    local worldSnapshot = world or {}
    if (tonumber(worldSnapshot.queue) or 0) > (tonumber(cfg.healthQueueWarning) or 80) * 2 and (tonumber(cfg.healthQueueWarning) or 0) > 0 then
        bdb_recordConsistencyWarning(data, "queue_above_double_warning", "warning", "spawn queue is far above health warning threshold", {
            queue = tonumber(worldSnapshot.queue) or 0,
            threshold = tonumber(cfg.healthQueueWarning) or 0
        })
    end
    if (tonumber(worldSnapshot.markers) or 0) > (tonumber(cfg.healthMarkerWarning) or 450) * 2 and (tonumber(cfg.healthMarkerWarning) or 0) > 0 then
        bdb_recordConsistencyWarning(data, "markers_above_double_warning", "warning", "map marker count is far above health warning threshold", {
            markers = tonumber(worldSnapshot.markers) or 0,
            threshold = tonumber(cfg.healthMarkerWarning) or 0
        })
    end

    if (tonumber(pendingOutcomes) or 0) > math.max(20, (tonumber(cfg.outcomeMaxRecords) or 160) * 0.50) then
        bdb_recordConsistencyWarning(data, "pending_outcome_backlog", "warning", "pending outcome backlog is high", {
            pending = tonumber(pendingOutcomes) or 0,
            maxRecords = tonumber(cfg.outcomeMaxRecords) or 0
        })
    end

    if data.lastProfileSummary and tostring(data.lastProfileSummary.name or "") == "diagnostics_only" and modeLive then
        bdb_recordConsistencyWarning(data, "diagnostics_profile_live_mode", "critical", "diagnostics profile should not run live mode", {})
    end

    bdb_trimConsistencyWarnings(data)
    local summary = NPCDirectorBrainServerBridge.UpdateConsistencySummary(data)
    summary.newWarnings = math.max(0, (type(data.consistencyWarnings) == "table" and #data.consistencyWarnings or 0) - before)
    data.lastConsistencySummary = summary
    return true
end



local function bdb_trimRuntimeSafetyLocks(data)
    if not data or type(data.runtimeSafetyLocks) ~= "table" then return 0 end
    local maxRecords = 60
    local now = bdb_now()
    local lockHours = tonumber(NPCDirectorBrainServerBridge.Config.runtimeSafetyLockHours) or 2.0
    if lockHours < 0.25 then lockHours = 0.25 end

    local kept = {}
    for _, record in ipairs(data.runtimeSafetyLocks) do
        local t = tonumber(record and record.t) or 0
        if t > 0 and now - t <= math.max(12, lockHours * 4) then
            kept[#kept + 1] = record
        end
    end
    while #kept > maxRecords do
        table.remove(kept, 1)
    end
    data.runtimeSafetyLocks = kept
    return #kept
end

function NPCDirectorBrainServerBridge.ApplyRuntimeSafetyLock()
    local cfg = NPCDirectorBrainServerBridge.Config
    if not cfg or not cfg.runtimeSafetyEnabled then
        if cfg then
            cfg.runtimeSafetyLocked = false
            cfg.runtimeSafetyReason = nil
        end
        return false
    end

    local data = bdb_data and bdb_data() or nil
    if not data or type(data.lastRuntimeSafety) ~= "table" then
        cfg.runtimeSafetyLocked = false
        cfg.runtimeSafetyReason = nil
        return false
    end

    local now = bdb_now()
    local lockUntil = tonumber(data.lastRuntimeSafety.lockUntil) or 0
    if cfg.runtimeSafetyAutoDryRun and lockUntil > now then
        cfg.dryRun = true
        cfg.runtimeSafetyLocked = true
        cfg.runtimeSafetyReason = tostring(data.lastRuntimeSafety.reason or "runtime_safety_lock")
        cfg.runtimeSafetyLockUntil = lockUntil
        return true
    end

    cfg.runtimeSafetyLocked = false
    cfg.runtimeSafetyReason = nil
    cfg.runtimeSafetyLockUntil = nil
    return false
end

local function bdb_runtimeSafetyWarningCount(data)
    local count = 0
    local health = data and data.lastHealthSummary or nil
    local consistency = data and data.lastConsistencySummary or nil
    if type(health) == "table" then
        count = count + (tonumber(health.warning) or 0) + ((tonumber(health.critical) or 0) * 2)
    end
    if type(consistency) == "table" then
        count = count + (tonumber(consistency.warning) or 0) + ((tonumber(consistency.critical) or 0) * 2)
    end
    return count
end

function NPCDirectorBrainServerBridge.RunRuntimeSafetyCheck(data, world, pressure, pendingOutcomes, reviewedOutcomes, candidates)
    local cfg = NPCDirectorBrainServerBridge.Config
    if not cfg or not cfg.enabled or not cfg.runtimeSafetyEnabled then return false end
    if not data then return false end
    if type(data.runtimeSafetyLocks) ~= "table" then data.runtimeSafetyLocks = {} end
    if type(data.lastRuntimeSafety) ~= "table" then data.lastRuntimeSafety = {} end

    local now = bdb_now()
    local safety = data.lastRuntimeSafety
    local activeUntil = tonumber(safety.lockUntil) or 0
    if activeUntil > now then
        safety.status = "locked"
        safety.active = true
        safety.remainingHours = math.floor((activeUntil - now) * 100) / 100
        safety.dryRunForced = cfg.runtimeSafetyAutoDryRun == true
        if cfg.runtimeSafetyAutoDryRun then
            cfg.dryRun = true
            cfg.runtimeSafetyLocked = true
            cfg.runtimeSafetyReason = tostring(safety.reason or "runtime_safety_lock")
            cfg.runtimeSafetyLockUntil = activeUntil
        end
        return false
    end

    local worldSnapshot = world or {}
    local reasons = {}
    local pressureLimit = tonumber(cfg.runtimeSafetyPressureLimit) or 3.40
    local queueLimit = tonumber(cfg.runtimeSafetyQueueLimit) or 120
    local markerLimit = tonumber(cfg.runtimeSafetyMarkerLimit) or 650
    local warningLimit = tonumber(cfg.runtimeSafetyWarningLimit) or 8
    local warningScore = bdb_runtimeSafetyWarningCount(data)

    if (tonumber(pressure) or 0) >= pressureLimit then
        reasons[#reasons + 1] = "pressure_limit"
    end
    if queueLimit > 0 and (tonumber(worldSnapshot.queue) or 0) >= queueLimit then
        reasons[#reasons + 1] = "queue_limit"
    end
    if markerLimit > 0 and (tonumber(worldSnapshot.markers) or 0) >= markerLimit then
        reasons[#reasons + 1] = "marker_limit"
    end
    if warningScore >= warningLimit then
        reasons[#reasons + 1] = "warning_limit"
    end
    if data.lastHealthSummary and tostring(data.lastHealthSummary.status or data.lastHealthSummary.lastSeverity or "") == "critical" then
        reasons[#reasons + 1] = "health_critical"
    end
    if data.lastConsistencySummary and tostring(data.lastConsistencySummary.status or "") == "critical" then
        reasons[#reasons + 1] = "consistency_critical"
    end

    if #reasons <= 0 then
        data.lastRuntimeSafety = {
            t = now,
            status = "ok",
            active = false,
            dryRunForced = false,
            reason = nil,
            pressure = math.floor((tonumber(pressure) or 0) * 100) / 100,
            queue = tonumber(worldSnapshot.queue) or 0,
            markers = tonumber(worldSnapshot.markers) or 0,
            warningScore = warningScore
        }
        cfg.runtimeSafetyLocked = false
        cfg.runtimeSafetyReason = nil
        cfg.runtimeSafetyLockUntil = nil
        bdb_trimRuntimeSafetyLocks(data)
        return false
    end

    local reason = table.concat(reasons, "+")
    local lockHours = tonumber(cfg.runtimeSafetyLockHours) or 2.0
    if lockHours < 0.25 then lockHours = 0.25 end
    local lockUntil = now + lockHours

    local record = {
        seq = (tonumber(data.runtimeSafetySeq) or 0) + 1,
        t = now,
        status = "locked",
        active = true,
        reason = reason,
        reasons = reasons,
        lockUntil = lockUntil,
        lockHours = lockHours,
        dryRunForced = cfg.runtimeSafetyAutoDryRun == true,
        pressure = math.floor((tonumber(pressure) or 0) * 100) / 100,
        queue = tonumber(worldSnapshot.queue) or 0,
        markers = tonumber(worldSnapshot.markers) or 0,
        warningScore = warningScore,
        pendingOutcomes = tonumber(pendingOutcomes) or 0,
        reviewedOutcomes = tonumber(reviewedOutcomes) or 0
    }
    data.runtimeSafetySeq = record.seq
    data.runtimeSafetyLocks[#data.runtimeSafetyLocks + 1] = record
    data.lastRuntimeSafety = record
    bdb_trimRuntimeSafetyLocks(data)

    if cfg.runtimeSafetyAutoDryRun then
        cfg.dryRun = true
        cfg.runtimeSafetyLocked = true
        cfg.runtimeSafetyReason = reason
        cfg.runtimeSafetyLockUntil = lockUntil
    end

    NPCDirectorBrainServerBridge.PushEvent("director_runtime_safety_lock", nil, nil, nil, {
        reason = reason,
        pressure = record.pressure,
        queue = record.queue,
        markers = record.markers,
        warningScore = warningScore,
        dryRunForced = record.dryRunForced
    })

    return true
end


local function bdb_trimFoundationReports(data)
    if not data or type(data.foundationReports) ~= "table" then return 0 end
    local maxRecords = math.floor(tonumber(NPCDirectorBrainServerBridge.Config.foundationSummaryMaxRecords) or 16)
    if maxRecords < 4 then maxRecords = 4 end
    while #data.foundationReports > maxRecords do
        table.remove(data.foundationReports, 1)
    end
    return #data.foundationReports
end

local function bdb_foundationTableState(data, key)
    return type(data and data[key]) == "table"
end

local bdb_adminHealthStatus

function NPCDirectorBrainServerBridge.BuildFoundationSummary(data, world, pressure, pendingOutcomes, reviewedOutcomes, candidates)
    NPCDirectorBrainServerBridge.ApplySettings()
    local cfg = NPCDirectorBrainServerBridge.Config
    if not cfg.enabled or not cfg.foundationSummaryEnabled then return false end
    if not data or not world then return false end

    local now = bdb_now()
    local interval = tonumber(cfg.foundationSummaryIntervalHours) or 2.0
    if interval < 0.10 then interval = 0.10 end
    if data.lastFoundationSummaryAt and now - (tonumber(data.lastFoundationSummaryAt) or 0) < interval then
        return false
    end

    if type(data.foundationReports) ~= "table" then data.foundationReports = {} end
    local health = data.lastHealthSummary or {}
    local consistency = data.lastConsistencySummary or {}
    local runtimeSafety = data.lastRuntimeSafety or {}
    local telemetry = data.lastTelemetrySummary or {}
    local intent = data.lastIntentSummary or {}
    local profile = data.lastProfileSummary or {}
    local decision = data.lastDecision or {}
    local pressureValue = math.floor((tonumber(pressure) or 0) * 100) / 100
    local pressureBand = bdb_adminPressureBand(pressureValue)
    local healthStatus = bdb_adminHealthStatus(health)
    local consistencyStatus = tostring(consistency.status or "ok")
    local runtimeStatus = tostring(runtimeSafety.status or "ok")
    local dryRun = cfg.dryRun ~= false
    local liveAssist = dryRun == false

    local status = "ok"
    if runtimeSafety.active == true or runtimeStatus == "locked" or runtimeSafety.dryRunForced == true then
        status = "runtime_locked"
    elseif healthStatus == "critical" or consistencyStatus == "critical" then
        status = "critical"
    elseif healthStatus == "warning" or consistencyStatus == "warning" then
        status = "warning"
    elseif liveAssist then
        status = "live_assist"
    elseif dryRun then
        status = "diagnostics_only"
    end

    local guardSummary = {
        pressureGuard = cfg.pressureGuardEnabled == true,
        livePolicy = cfg.livePolicyEnabled == true,
        runtimeSafety = cfg.runtimeSafetyEnabled == true,
        outcomeTracking = cfg.outcomeTrackingEnabled == true,
        outcomeFeedback = cfg.outcomeFeedbackEnabled == true,
        pacing = cfg.pacingEnabled == true,
        consistency = cfg.consistencyCheckEnabled == true,
        health = cfg.healthMonitorEnabled == true
    }

    local tableState = {
        events = bdb_foundationTableState(data, "events"),
        worldMemory = bdb_foundationTableState(data, "worldMemory"),
        outcomes = bdb_foundationTableState(data, "outcomes"),
        intentLedger = bdb_foundationTableState(data, "intentLedger"),
        telemetry = bdb_foundationTableState(data, "telemetry"),
        healthWarnings = bdb_foundationTableState(data, "healthWarnings"),
        adminReports = bdb_foundationTableState(data, "adminReports"),
        profileWarnings = bdb_foundationTableState(data, "profileWarnings"),
        consistencyWarnings = bdb_foundationTableState(data, "consistencyWarnings"),
        runtimeSafetyLocks = bdb_foundationTableState(data, "runtimeSafetyLocks")
    }

    local missingTables = 0
    for _, present in pairs(tableState) do
        if not present then missingTables = missingTables + 1 end
    end

    local summary = {
        seq = (tonumber(data.foundationSeq) or 0) + 1,
        t = now,
        version = 12,
        status = status,
        dryRun = dryRun,
        liveAssist = liveAssist,
        profile = tostring(profile.name or cfg.profileName or "unknown"),
        profileRisk = tostring(profile.risk or cfg.profileRisk or "unknown"),
        pressure = pressureValue,
        pressureBand = pressureBand,
        pacingPhase = data.pacing and tostring(data.pacing.phase or "unknown") or "unknown",
        selected = tostring(decision.selected or "wait"),
        dominantIntent = tostring(intent.dominantIntent or decision.selected or "wait"),
        telemetryTrend = tostring(telemetry.pressureTrend or "stable"),
        healthStatus = healthStatus,
        consistencyStatus = consistencyStatus,
        runtimeSafetyStatus = runtimeStatus,
        runtimeSafetyActive = runtimeSafety.active == true,
        missingTables = missingTables,
        guards = guardSummary,
        tables = tableState,
        world = {
            virtual = tonumber(world.virtual) or 0,
            physical = tonumber(world.physical) or 0,
            queue = tonumber(world.queue) or 0,
            markers = tonumber(world.markers) or 0,
            battles = tonumber(world.battles) or 0
        },
        outcomes = {
            pending = tonumber(pendingOutcomes) or 0,
            reviewed = tonumber(reviewedOutcomes) or 0
        }
    }

    data.foundationSeq = summary.seq
    data.lastFoundationSummaryAt = now
    data.lastFoundationSummary = summary
    data.foundationReports[#data.foundationReports + 1] = summary
    bdb_trimFoundationReports(data)

    local statusKey = tostring(summary.status) .. ":" .. tostring(summary.profile) .. ":" .. tostring(summary.pressureBand) .. ":" .. tostring(summary.runtimeSafetyStatus)
    if data.lastFoundationStatusKey ~= statusKey then
        data.lastFoundationStatusKey = statusKey
        NPCDirectorBrainServerBridge.PushEvent("director_foundation_summary", nil, nil, nil, {
            status = summary.status,
            profile = summary.profile,
            pressure = summary.pressure,
            band = summary.pressureBand,
            health = summary.healthStatus,
            consistency = summary.consistencyStatus,
            runtimeSafety = summary.runtimeSafetyStatus,
            dryRun = summary.dryRun
        })
    end

    return true
end

local function bdb_trimAdminReports(data)
    if not data or type(data.adminReports) ~= "table" then return 0 end
    local maxRecords = math.floor(tonumber(NPCDirectorBrainServerBridge.Config.adminReportMaxRecords) or 24)
    if maxRecords < 4 then maxRecords = 4 end
    while #data.adminReports > maxRecords do
        table.remove(data.adminReports, 1)
    end
    return #data.adminReports
end

bdb_adminHealthStatus = function(summary)
    if type(summary) ~= "table" then return "ok" end
    if (tonumber(summary.critical) or 0) > 0 then return "critical" end
    if (tonumber(summary.warning) or 0) > 0 then return "warning" end
    if (tonumber(summary.info) or 0) > 0 then return "info" end
    return "ok"
end

function NPCDirectorBrainServerBridge.BuildAdminReport(data, world, pressure, pendingOutcomes, reviewedOutcomes, candidates)
    NPCDirectorBrainServerBridge.ApplySettings()
    local cfg = NPCDirectorBrainServerBridge.Config
    if not cfg.enabled or not cfg.adminReportEnabled then return false end
    if not data or not world then return false end

    local now = bdb_now()
    local interval = tonumber(cfg.adminReportIntervalHours) or 2.0
    if interval < 0.10 then interval = 0.10 end
    if data.lastAdminReportAt and now - (tonumber(data.lastAdminReportAt) or 0) < interval then
        return false
    end

    if type(data.adminReports) ~= "table" then data.adminReports = {} end
    local decision = data.lastDecision or {}
    local telemetry = data.lastTelemetrySummary or {}
    local health = data.lastHealthSummary or {}
    local intent = data.lastIntentSummary or {}
    local feedback = data.lastOutcomeFeedback or {}
    local policy = data.lastLivePolicy or {}
    local profile = data.lastProfileSummary or {}
    local consistency = data.lastConsistencySummary or {}
    local runtimeSafety = data.lastRuntimeSafety or {}
    local foundation = data.lastFoundationSummary or {}
    local retargetPolicy = policy.retarget or {}
    local routePolicy = policy.route_bias or {}
    local activationPolicy = policy.activation or {}
    local mode = cfg.dryRun ~= false and "dry-run" or "live"
    local phase = data.pacing and tostring(data.pacing.phase or "unknown") or "unknown"
    local selected = tostring(decision.selected or "wait")
    local dominantIntent = tostring(intent.dominantIntent or selected)
    local healthStatus = bdb_adminHealthStatus(health)
    local pressureValue = bdb_adminRound(pressure)
    local pressureBand = bdb_adminPressureBand(pressureValue)

    local report = {
        seq = (tonumber(data.adminReportSeq) or 0) + 1,
        t = now,
        mode = mode,
        dryRun = cfg.dryRun ~= false,
        pressure = pressureValue,
        pressureBand = pressureBand,
        pacingPhase = phase,
        selected = selected,
        selectedReason = tostring(decision.reason or ""),
        dominantIntent = dominantIntent,
        telemetryTrend = tostring(telemetry.pressureTrend or "stable"),
        healthStatus = healthStatus,
        healthDominant = health.dominantKind and tostring(health.dominantKind) or nil,
        consistencyStatus = tostring(consistency.status or "ok"),
        consistencyDominant = consistency.dominantKind and tostring(consistency.dominantKind) or nil,
        runtimeSafety = {
            status = tostring(runtimeSafety.status or "ok"),
            active = runtimeSafety.active == true,
            reason = runtimeSafety.reason and tostring(runtimeSafety.reason) or nil,
            dryRunForced = runtimeSafety.dryRunForced == true,
            lockUntil = tonumber(runtimeSafety.lockUntil) or nil,
            warningScore = tonumber(runtimeSafety.warningScore) or 0
        },
        foundation = {
            status = tostring(foundation.status or "unknown"),
            version = tonumber(foundation.version) or 12,
            missingTables = tonumber(foundation.missingTables) or 0,
            telemetryTrend = tostring(foundation.telemetryTrend or telemetry.pressureTrend or "stable"),
            runtimeSafetyStatus = tostring(foundation.runtimeSafetyStatus or runtimeSafety.status or "ok"),
            liveAssist = foundation.liveAssist == true
        },
        profile = {
            id = tonumber(profile.id) or tonumber(cfg.profile) or 1,
            name = tostring(profile.name or cfg.profileName or "unknown"),
            applied = tostring(profile.applied or cfg.profileApplied or "unknown"),
            risk = tostring(profile.risk or cfg.profileRisk or "custom"),
            dryRun = cfg.dryRun ~= false,
            liveAssist = cfg.dryRun == false,
            warnings = tonumber(profile.warnings) or 0,
            latestSeverity = profile.latestSeverity and tostring(profile.latestSeverity) or nil
        },
        livePolicy = {
            retarget = tostring(retargetPolicy.reason or "ok"),
            routeBias = tostring(routePolicy.reason or "ok"),
            activation = tostring(activationPolicy.reason or "ok")
        },
        world = {
            virtual = tonumber(world.virtual) or 0,
            physical = tonumber(world.physical) or 0,
            roadPatrols = tonumber(world.roadPatrols) or 0,
            battles = tonumber(world.battles) or 0,
            bases = tonumber(world.bases) or 0,
            markers = tonumber(world.markers) or 0,
            queue = tonumber(world.queue) or 0
        },
        outcomes = {
            pending = tonumber(pendingOutcomes) or 0,
            reviewed = tonumber(reviewedOutcomes) or 0,
            retargetFailureRate = feedback.retarget and bdb_adminRound(feedback.retarget.failureRate) or 0,
            materializationFailureRate = feedback.materialization and bdb_adminRound(feedback.materialization.failureRate) or 0
        },
        telemetry = {
            records = tonumber(telemetry.records) or 0,
            avgPressure = bdb_adminRound(telemetry.avgPressure),
            maxPressure = bdb_adminRound(telemetry.maxPressure),
            dominantPhase = telemetry.dominantPhase and tostring(telemetry.dominantPhase) or nil,
            dominantDecision = telemetry.dominantDecision and tostring(telemetry.dominantDecision) or nil
        },
        health = {
            records = tonumber(health.records) or 0,
            info = tonumber(health.info) or 0,
            warning = tonumber(health.warning) or 0,
            critical = tonumber(health.critical) or 0,
            lastSeverity = health.lastSeverity and tostring(health.lastSeverity) or nil,
            lastKind = health.lastKind and tostring(health.lastKind) or nil,
            dominantKind = health.dominantKind and tostring(health.dominantKind) or nil
        },
        consistency = {
            records = tonumber(consistency.records) or 0,
            info = tonumber(consistency.info) or 0,
            warning = tonumber(consistency.warning) or 0,
            critical = tonumber(consistency.critical) or 0,
            status = tostring(consistency.status or "ok"),
            lastSeverity = consistency.lastSeverity and tostring(consistency.lastSeverity) or nil,
            lastKind = consistency.lastKind and tostring(consistency.lastKind) or nil,
            dominantKind = consistency.dominantKind and tostring(consistency.dominantKind) or nil
        },
        topCandidates = bdb_intentTopCandidates(candidates),
        lines = {}
    }

    report.lines[#report.lines + 1] = "profile=" .. tostring(report.profile.name) ..
        " risk=" .. tostring(report.profile.risk) ..
        " mode=" .. report.mode ..
        " pressure=" .. tostring(report.pressure) .. "(" .. report.pressureBand .. ")" ..
        " phase=" .. tostring(report.pacingPhase) ..
        " selected=" .. tostring(report.selected) ..
        " dominant=" .. tostring(report.dominantIntent) ..
        " health=" .. tostring(report.healthStatus) ..
        " consistency=" .. tostring(report.consistencyStatus) ..
        " safety=" .. tostring(report.runtimeSafety and report.runtimeSafety.status or "ok") ..
        " foundation=" .. tostring(report.foundation and report.foundation.status or "unknown")
    report.lines[#report.lines + 1] = "world virtual=" .. tostring(report.world.virtual) ..
        " physical=" .. tostring(report.world.physical) ..
        " queue=" .. tostring(report.world.queue) ..
        " markers=" .. tostring(report.world.markers) ..
        " battles=" .. tostring(report.world.battles) ..
        " bases=" .. tostring(report.world.bases)
    report.lines[#report.lines + 1] = "telemetry trend=" .. tostring(report.telemetryTrend) ..
        " avg=" .. tostring(report.telemetry.avgPressure) ..
        " max=" .. tostring(report.telemetry.maxPressure) ..
        " records=" .. tostring(report.telemetry.records)
    report.lines[#report.lines + 1] = "policy retarget=" .. tostring(report.livePolicy.retarget) ..
        " route=" .. tostring(report.livePolicy.routeBias) ..
        " activation=" .. tostring(report.livePolicy.activation)
    report.lines[#report.lines + 1] = "outcomes pending=" .. tostring(report.outcomes.pending) ..
        " reviewed=" .. tostring(report.outcomes.reviewed) ..
        " retargetFail=" .. tostring(report.outcomes.retargetFailureRate) ..
        " materializeFail=" .. tostring(report.outcomes.materializationFailureRate)
    if cfg.adminReportIncludeWarnings and report.healthStatus ~= "ok" then
        report.lines[#report.lines + 1] = "health warnings info=" .. tostring(report.health.info) ..
            " warning=" .. tostring(report.health.warning) ..
            " critical=" .. tostring(report.health.critical) ..
            " dominant=" .. tostring(report.health.dominantKind or "none")
    end
    if cfg.adminReportIncludeWarnings and report.consistencyStatus ~= "ok" then
        report.lines[#report.lines + 1] = "consistency warnings info=" .. tostring(report.consistency.info) ..
            " warning=" .. tostring(report.consistency.warning) ..
            " critical=" .. tostring(report.consistency.critical) ..
            " dominant=" .. tostring(report.consistency.dominantKind or "none")
    end
    if report.foundation and report.foundation.status ~= "unknown" then
        report.lines[#report.lines + 1] = "foundation status=" .. tostring(report.foundation.status) ..
            " version=" .. tostring(report.foundation.version) ..
            " missingTables=" .. tostring(report.foundation.missingTables) ..
            " liveAssist=" .. tostring(report.foundation.liveAssist) ..
            " trend=" .. tostring(report.foundation.telemetryTrend)
    end
    if report.runtimeSafety and report.runtimeSafety.status ~= "ok" then
        report.lines[#report.lines + 1] = "runtime safety status=" .. tostring(report.runtimeSafety.status) ..
            " active=" .. tostring(report.runtimeSafety.active) ..
            " reason=" .. tostring(report.runtimeSafety.reason or "none") ..
            " dryRunForced=" .. tostring(report.runtimeSafety.dryRunForced) ..
            " warningScore=" .. tostring(report.runtimeSafety.warningScore or 0)
    end

    data.adminReportSeq = report.seq
    data.lastAdminReportAt = now
    data.lastAdminReport = report
    data.adminReports[#data.adminReports + 1] = report
    bdb_trimAdminReports(data)

    if cfg.adminReportLogToConsole then
        print("[NPCDirectorBrainServerBridge.Report] seq=" .. tostring(report.seq))
        for _, line in ipairs(report.lines) do
            print("[NPCDirectorBrainServerBridge.Report] " .. tostring(line))
        end
    end

    local statusKey = report.profile.name .. ":" .. report.pressureBand .. ":" .. report.healthStatus .. ":" .. report.consistencyStatus .. ":" .. tostring(report.foundation and report.foundation.status or "unknown") .. ":" .. report.selected
    if data.lastAdminReportStatusKey ~= statusKey then
        data.lastAdminReportStatusKey = statusKey
        NPCDirectorBrainServerBridge.PushEvent("director_admin_report", nil, nil, nil, {
            pressure = report.pressure,
            band = report.pressureBand,
            health = report.healthStatus,
            consistency = report.consistencyStatus,
            selected = report.selected,
            phase = report.pacingPhase,
            mode = report.mode,
            profile = report.profile.name,
            foundation = report.foundation and report.foundation.status or "unknown"
        })
    end

    return true
end


function NPCDirectorBrainServerBridge.BuildCandidates(data, world, pressure, playerPressure)
    local candidates = {}

    local function add(kind, score, reason)
        candidates[#candidates + 1] = {kind = kind, score = bdb_clamp(score, 0, 10), reason = reason}
    end

    add("wait", 0.45 + pressure * 0.35, "baseline recovery")

    local pacing = data and data.pacing or nil
    if pacing and pacing.phase and pacing.phase ~= "off" then
        local phaseScore = 0.25
        if pacing.phase == "pressure" then phaseScore = 0.85
        elseif pacing.phase == "recovery" then phaseScore = 0.75
        elseif pacing.phase == "build" then phaseScore = 0.55 end
        add("pacing_" .. tostring(pacing.phase), phaseScore, "director pacing phase is " .. tostring(pacing.phase))
    end

    if data and data.lastProfileSummary and (tonumber(data.lastProfileSummary.warnings) or 0) > 0 then
        add("review_director_profile", 0.32 + math.min(tonumber(data.lastProfileSummary.warnings) or 0, 12) * 0.03, "director profile validation has recent warnings")
    end

    if data and data.lastConsistencySummary and (tonumber(data.lastConsistencySummary.records) or 0) > 0 then
        add("review_director_consistency", 0.36 + math.min(tonumber(data.lastConsistencySummary.records) or 0, 12) * 0.03, "director consistency audit has recent warnings")
    end

    if NPCDirectorBrainServerBridge.Config.intentLedgerEnabled and data and data.lastIntentSummary and (tonumber(data.lastIntentSummary.records) or 0) >= 6 then
        add("review_intent_ledger", 0.25 + math.min(tonumber(data.lastIntentSummary.records) or 0, 20) * 0.01, "recent director decisions are available for tuning")
    end

    if NPCDirectorBrainServerBridge.Config.telemetryEnabled and data and data.lastTelemetrySummary and (tonumber(data.lastTelemetrySummary.records) or 0) >= 3 then
        local telemetryScore = 0.22 + math.min(tonumber(data.lastTelemetrySummary.records) or 0, 24) * 0.01
        if data.lastTelemetrySummary.pressureTrend == "rising" then telemetryScore = telemetryScore + 0.12 end
        add("review_telemetry", telemetryScore, "recent director telemetry snapshots are available for tuning")
    end

    if NPCDirectorBrainServerBridge.Config.healthMonitorEnabled and data and data.lastHealthSummary and (tonumber(data.lastHealthSummary.records) or 0) > 0 then
        local healthScore = 0.24 + math.min(tonumber(data.lastHealthSummary.records) or 0, 20) * 0.015
        if (tonumber(data.lastHealthSummary.critical) or 0) > 0 then healthScore = healthScore + 0.55
        elseif (tonumber(data.lastHealthSummary.warning) or 0) > 0 then healthScore = healthScore + 0.30 end
        add("review_director_health", healthScore, "director health monitor has recent warnings")
    end

    if NPCDirectorBrainServerBridge.Config.livePolicyEnabled then
        local retargetPolicy = NPCDirectorBrainServerBridge.GetLivePolicy("retarget")
        if retargetPolicy and retargetPolicy.allowed == false and world.virtual > 0 then
            add("live_policy_retarget_hold", 0.55 + pressure * 0.10, tostring(retargetPolicy.reason or "live policy holds retarget"))
        end
        local activationPolicy = NPCDirectorBrainServerBridge.GetLivePolicy("activation")
        if activationPolicy and (tonumber(activationPolicy.pressureAdd) or 0) > 0 then
            add("live_policy_activation_caution", 0.45 + (tonumber(activationPolicy.pressureAdd) or 0), tostring(activationPolicy.reason or "live policy raises activation caution"))
        end
    end

    if pressure > 1.1 then
        add("hold_pressure", pressure, "recent combat or materialization pressure is high")
    end

    if NPCDirectorBrainServerBridge.Config.pressureGuardEnabled and pressure >= (tonumber(NPCDirectorBrainServerBridge.Config.pressureGuardThreshold) or 1.65) then
        add("guard_group_activation", pressure + 0.20, "activation pressure guard would defer low-priority groups")
    end

    if playerPressure > 0.45 and pressure < 1.5 then
        add("observe_player_routes", playerPressure + 0.25, "players are moving or using vehicles")
    end

    if NPCDirectorBrainServerBridge.Config.routeBiasEnabled and playerPressure > 0.25 and pressure < 2.0 then
        add("route_memory_bias", playerPressure + 0.15, "remembered player routes can bias virtual targets in live mode")
    end

    if NPCDirectorBrainServerBridge.Config.retargetEnabled and world.virtual > 0 and playerPressure > 0.30 and pressure < 1.45 then
        add("retarget_existing_patrols", playerPressure + 0.30, "existing low-priority virtual groups can investigate remembered routes")
    end

    local pendingOutcomes, outcomeFailures = bdb_outcomeSummary(data)
    if pendingOutcomes > 0 then
        add("review_director_outcomes", 0.20 + math.min(pendingOutcomes, 10) * 0.04, "director has pending materialization/retarget outcomes")
    end
    if outcomeFailures > 0 and pressure > 1.0 then
        add("hold_after_failed_outcomes", 0.45 + math.min(outcomeFailures, 8) * 0.05, "recent director outcomes include failures")
    end

    local retargetFeedback = NPCDirectorBrainServerBridge.GetOutcomeFeedback("retarget")
    if retargetFeedback and retargetFeedback.samples > 0 and retargetFeedback.failureRate >= 0.35 then
        add("outcome_feedback_retarget_slowdown", 0.35 + retargetFeedback.failureRate, "recent retarget outcomes failed often enough to slow live retarget")
    end

    local materializationFeedback = NPCDirectorBrainServerBridge.GetOutcomeFeedback("materialization")
    if materializationFeedback and materializationFeedback.samples > 0 and materializationFeedback.failureRate >= 0.35 then
        add("outcome_feedback_activation_caution", 0.35 + materializationFeedback.failureRate, "recent materialization outcomes failed often enough to raise caution")
    end

    if world.battles > 0 then
        add("observe_battles", 0.70 + world.battles * 0.20, "virtual road battles are active")
    end

    if world.virtual > 0 and world.physical < 3 and pressure < 0.9 then
        add("candidate_light_patrol_pressure", 0.55, "low physical pressure and virtual groups available")
    end

    if world.bases > 0 and pressure < 1.2 then
        add("candidate_base_intel", 0.35 + math.min(world.bases, 10) * 0.03, "bases exist and pressure is acceptable")
    end

    table.sort(candidates, function(a, b) return (a.score or 0) > (b.score or 0) end)
    return candidates
end


local function bdb_isCriticalActivationGroup(group)
    if not group then return false end
    if group.bountyHunter or group.targetClass == "bounty_hunt" then return true end
    if group.inBattle or group.enemyGroupId then return true end
    if group.leaderId or group.isFactionLeader then return true end
    if group.economyConvoy or group.convoyId then return true end
    if group.forceActivation or group.forceMaterialize then return true end
    return false
end

local function bdb_isRetargetProtectedGroup(group)
    if not group or group.activated then return true end
    if bdb_isCriticalActivationGroup(group) then return true end
    if group.economyMissionId or group.missionTargetX or group.missionTargetY then return true end
    if group.targetClass == "base_capture" or group.targetBaseId then return true end
    if group.homeBaseId and not group.roadPatrol then return true end
    return false
end

local function bdb_cellCenter(cell)
    local size = tonumber(NPCDirectorBrainServerBridge.Config.worldMemoryCellSize) or 150
    if size < 1 then size = 150 end
    local cx = tonumber(cell and cell.cx)
    local cy = tonumber(cell and cell.cy)
    if not cx or not cy then return nil, nil end
    return math.floor((cx + 0.5) * size), math.floor((cy + 0.5) * size)
end

local function bdb_trimCellCooldowns(data, now)
    if not data or type(data.cellCooldowns) ~= "table" then return 0 end
    now = tonumber(now) or bdb_now()
    local hours = tonumber(NPCDirectorBrainServerBridge.Config.cellCooldownHours) or 4
    if hours < 0.25 then hours = 0.25 end
    local maxRecords = math.floor(tonumber(NPCDirectorBrainServerBridge.Config.cellCooldownMaxRecords) or 180)
    if maxRecords < 20 then maxRecords = 20 end

    local count = 0
    local oldestKey = nil
    local oldestTime = now
    for key, rec in pairs(data.cellCooldowns) do
        local t = tonumber(rec and rec.t) or 0
        if t <= 0 or now - t > hours then
            data.cellCooldowns[key] = nil
        else
            count = count + 1
            if t < oldestTime then
                oldestTime = t
                oldestKey = key
            end
        end
    end

    while count > maxRecords and oldestKey do
        data.cellCooldowns[oldestKey] = nil
        count = count - 1
        oldestKey = nil
        oldestTime = now
        for key, rec in pairs(data.cellCooldowns) do
            local t = tonumber(rec and rec.t) or 0
            if t < oldestTime then
                oldestTime = t
                oldestKey = key
            end
        end
    end

    return count
end

local function bdb_cellCooldownScore(data, x, y, now)
    local cfg = NPCDirectorBrainServerBridge.Config
    if not cfg.cellCooldownEnabled or not data or type(data.cellCooldowns) ~= "table" then return 0, nil end

    local _, cx, cy = bdb_cellKey(x, y)
    if cx == nil or cy == nil then return 0, nil end

    now = tonumber(now) or bdb_now()
    local hours = tonumber(cfg.cellCooldownHours) or 4
    if hours < 0.25 then hours = 0.25 end
    local penalty = tonumber(cfg.cellCooldownPenalty) or 0.45
    if penalty <= 0 then return 0, nil end

    local bestPenalty = 0
    local bestReason = nil
    for ox = -1, 1 do
        for oy = -1, 1 do
            local key = tostring(cx + ox) .. ":" .. tostring(cy + oy)
            local rec = data.cellCooldowns[key]
            local t = tonumber(rec and rec.t) or 0
            if t > 0 then
                local age = now - t
                if age >= 0 and age <= hours then
                    local ageFactor = 1.0 - bdb_clamp(age / hours, 0, 1)
                    local distFactor = (ox == 0 and oy == 0) and 1.0 or 0.45
                    local p = penalty * ageFactor * distFactor
                    if p > bestPenalty then
                        bestPenalty = p
                        bestReason = rec and rec.kind or "recent_director_cell"
                    end
                end
            end
        end
    end

    return bestPenalty, bestReason
end

function NPCDirectorBrainServerBridge.MarkCellCooldown(kind, x, y, z, meta)
    NPCDirectorBrainServerBridge.ApplySettings()
    local cfg = NPCDirectorBrainServerBridge.Config
    if not cfg.enabled or not cfg.cellCooldownEnabled then return false end

    x = tonumber(x)
    y = tonumber(y)
    if not x or not y then return false end

    local data = bdb_data()
    if not data then return false end
    if type(data.cellCooldowns) ~= "table" then data.cellCooldowns = {} end

    local key, cx, cy = bdb_cellKey(x, y)
    if not key then return false end

    local now = bdb_now()
    local rec = {
        t = now,
        x = math.floor(x),
        y = math.floor(y),
        z = tonumber(z) or 0,
        cx = cx,
        cy = cy,
        kind = tostring(kind or "director"),
        meta = bdb_metaCopy(meta)
    }
    data.cellCooldowns[key] = rec
    data.lastCellCooldown = rec
    bdb_trimCellCooldowns(data, now)

    NPCDirectorBrainServerBridge.PushEvent("director_cell_cooldown", x, y, tonumber(z) or 0, {
        key = key,
        kind = rec.kind,
        groupId = meta and meta.groupId or nil,
        reason = meta and meta.reason or nil
    })
    return true
end

local function bdb_retargetCellScore(cell, now, forgetHours, distance, maxDistance, context)
    if not cell then return nil, nil end
    local age = now - (tonumber(cell.lastSeen) or now)
    if age < 0 or age > forgetHours then return nil, nil end

    local player = tonumber(cell.player) or 0
    local noise = tonumber(cell.noise) or 0
    local heat = tonumber(cell.heat) or 0
    local combat = tonumber(cell.combat) or 0
    local score = player * 1.05 + noise * 0.35 + heat * 0.18 - combat * (tonumber(NPCDirectorBrainServerBridge.Config.routeBiasCombatPenalty) or 0.65)
    if context == "road" then
        score = score + player * 0.35
    end
    if score <= 0 then return nil, nil end

    local ageFactor = 1.0 - bdb_clamp(age / forgetHours, 0, 1)
    local distFactor = 1.0 - bdb_clamp(distance / maxDistance, 0, 1) * 0.55
    score = score * ageFactor * distFactor

    local reason = "world_heat"
    if player > 0.12 then reason = "player_route"
    elseif noise > 0.10 then reason = "noise_memory"
    end

    return score, reason
end

function NPCDirectorBrainServerBridge.GetRetargetAnchor(group, context)
    NPCDirectorBrainServerBridge.ApplySettings()
    local cfg = NPCDirectorBrainServerBridge.Config
    if not cfg.enabled or not cfg.retargetEnabled then return nil end
    if cfg.dryRun ~= false then return nil end
    local livePolicy = NPCDirectorBrainServerBridge.GetLivePolicy("retarget")
    if livePolicy and livePolicy.allowed == false then return nil end
    if bdb_isRetargetProtectedGroup(group) then return nil end

    local x = tonumber(group.x)
    local y = tonumber(group.y)
    if not x or not y then return nil end

    local now = bdb_now()
    local cooldown = tonumber(cfg.retargetCooldownHours) or 4
    if cooldown < 0.25 then cooldown = 0.25 end
    local lastRetarget = tonumber(group.directorRetargetAt) or 0
    if lastRetarget > 0 and now - lastRetarget < cooldown then return nil end

    local data = bdb_data()
    if not data or type(data.worldMemory) ~= "table" then return nil end

    local maxDistance = tonumber(cfg.retargetMaxDistance) or 1600
    if maxDistance < 200 then maxDistance = 200 end
    local forgetHours = tonumber(cfg.routeBiasForgetHours) or 36
    if forgetHours < 1 then forgetHours = 1 end

    local best = nil
    local ctx = tostring(context or (group.roadPatrol and "road" or "roam"))
    local feedback = NPCDirectorBrainServerBridge.GetOutcomeFeedback("retarget")
    local pacing = NPCDirectorBrainServerBridge.GetPacingModifier("retarget")
    local minScore = (tonumber(cfg.retargetMinScore) or 0.35) + (feedback and tonumber(feedback.minScoreAdd) or 0) + (pacing and tonumber(pacing.minScoreAdd) or 0) + (livePolicy and tonumber(livePolicy.minScoreAdd) or 0)
    for _, cell in pairs(data.worldMemory) do
        local tx, ty = bdb_cellCenter(cell)
        if tx and ty then
            local dist = bdb_dist(x, y, tx, ty)
            if dist <= maxDistance and dist >= 160 then
                local score, reason = bdb_retargetCellScore(cell, now, forgetHours, dist, maxDistance, ctx)
                if score then
                    local cooldownPenalty, cooldownReason = bdb_cellCooldownScore(data, tx, ty, now)
                    if cooldownPenalty > 0 then
                        score = score - cooldownPenalty
                        if not reason or cooldownPenalty >= 0.25 then reason = "cell_cooldown" end
                    end
                    if score >= minScore then
                        if not best or score > best.score then
                            best = {x = tx, y = ty, z = 0, score = score, reason = reason, cooldown = cooldownPenalty, cooldownReason = cooldownReason, distance = dist}
                        end
                    end
                end
            end
        end
    end

    return best
end

function NPCDirectorBrainServerBridge.GetRetargetMaxGroupsPerUpdate()
    NPCDirectorBrainServerBridge.ApplySettings()
    if not NPCDirectorBrainServerBridge.Config.enabled or not NPCDirectorBrainServerBridge.Config.retargetEnabled then return 0 end
    if NPCDirectorBrainServerBridge.Config.dryRun ~= false then return 0 end

    local maxGroups = math.floor(bdb_clamp(NPCDirectorBrainServerBridge.Config.retargetMaxGroupsPerUpdate, 0, 10))
    if maxGroups <= 0 then return 0 end

    local livePolicy = NPCDirectorBrainServerBridge.GetLivePolicy("retarget")
    if livePolicy and livePolicy.allowed == false then return 0 end

    local feedback = NPCDirectorBrainServerBridge.GetOutcomeFeedback("retarget")
    if feedback and feedback.samples > 0 and feedback.failureRate >= 0.50 then
        maxGroups = math.floor(maxGroups * (tonumber(feedback.multiplier) or 1.0))
    end

    local pacing = NPCDirectorBrainServerBridge.GetPacingModifier("retarget")
    if pacing and pacing.phase ~= "off" then
        maxGroups = math.floor(maxGroups * (tonumber(pacing.multiplier) or 1.0))
    end

    if livePolicy then
        maxGroups = math.floor(maxGroups * (tonumber(livePolicy.multiplier) or 1.0))
    end

    return bdb_clamp(maxGroups, 0, 10)
end

function NPCDirectorBrainServerBridge.GetCurrentPressure()
    local data = bdb_data()
    if not data or type(data.pressure) ~= "table" then return 0 end
    return tonumber(data.pressure.global) or 0
end

function NPCDirectorBrainServerBridge.GetPointMemoryBias(x, y, context)
    NPCDirectorBrainServerBridge.ApplySettings()
    local cfg = NPCDirectorBrainServerBridge.Config
    if not cfg.enabled or not cfg.routeBiasEnabled then return 0, nil end
    if cfg.dryRun ~= false then return 0, nil end

    x = tonumber(x)
    y = tonumber(y)
    if not x or not y then return 0, nil end

    local data = bdb_data()
    if not data or type(data.worldMemory) ~= "table" then return 0, nil end

    local livePolicy = NPCDirectorBrainServerBridge.GetLivePolicy("route_bias")
    if livePolicy and livePolicy.allowed == false then return 0, nil end

    local _, cx, cy = bdb_cellKey(x, y)
    if cx == nil or cy == nil then return 0, nil end

    local now = bdb_now()
    local forgetHours = tonumber(cfg.routeBiasForgetHours) or 36
    if forgetHours < 1 then forgetHours = 1 end

    local total = 0
    local bestReason = nil
    local samples = 0
    local combatPenalty = tonumber(cfg.routeBiasCombatPenalty) or 0.65
    local ctx = tostring(context or "roam")

    for ox = -1, 1 do
        for oy = -1, 1 do
            local key = tostring(cx + ox) .. ":" .. tostring(cy + oy)
            local cell = data.worldMemory[key]
            if cell then
                local age = now - (tonumber(cell.lastSeen) or now)
                if age <= forgetHours then
                    local ageFactor = 1.0 - bdb_clamp(age / forgetHours, 0, 1)
                    local distFactor = 1.0
                    if ox ~= 0 or oy ~= 0 then distFactor = 0.55 end

                    local player = tonumber(cell.player) or 0
                    local noise = tonumber(cell.noise) or 0
                    local heat = tonumber(cell.heat) or 0
                    local combat = tonumber(cell.combat) or 0

                    local score = player * 0.80 + noise * 0.30 + heat * 0.12 - combat * combatPenalty
                    if ctx == "road" then
                        score = score + player * 0.30
                    elseif ctx == "roam" then
                        score = score + heat * 0.08
                    end

                    total = total + score * ageFactor * distFactor
                    samples = samples + 1

                    if not bestReason then
                        if player > 0.12 then bestReason = "player_route"
                        elseif combat > 0.20 then bestReason = "combat_avoid"
                        elseif heat > 0.15 then bestReason = "world_heat"
                        elseif noise > 0.10 then bestReason = "noise_memory" end
                    end
                end
            end
        end
    end

    if samples <= 0 or total == 0 then return 0, nil end

    local strength = tonumber(cfg.routeBiasStrength) or 1.0
    local maxBonus = tonumber(cfg.routeBiasMaxBonus) or 80
    local pacing = NPCDirectorBrainServerBridge.GetPacingModifier("route_bias")
    local pacingMultiplier = pacing and tonumber(pacing.multiplier) or 1.0
    local policyMultiplier = livePolicy and tonumber(livePolicy.multiplier) or 1.0
    local bias = bdb_clamp(total * 60 * strength * pacingMultiplier * policyMultiplier, -maxBonus, maxBonus)

    local cooldownPenalty, cooldownReason = bdb_cellCooldownScore(data, x, y, now)
    if cooldownPenalty > 0 then
        bias = bias - (cooldownPenalty * 60)
        if cooldownPenalty >= 0.25 then bestReason = "cell_cooldown" end
    end

    bias = bdb_clamp(bias, -maxBonus, maxBonus)
    if math.abs(bias) < 1 then return 0, nil end

    return bias, bestReason or cooldownReason or "memory"
end


function NPCDirectorBrainServerBridge.ShouldDeferActivation(group, player, budget)
    NPCDirectorBrainServerBridge.ApplySettings()
    local cfg = NPCDirectorBrainServerBridge.Config
    if not cfg.enabled or not cfg.pressureGuardEnabled then return nil end
    if cfg.dryRun ~= false then return nil end
    if bdb_isCriticalActivationGroup(group) then return nil end

    if group and player and group.x and group.y and player.getX and player.getY then
        local ok, nearMarker = pcall(function()
            return bdb_dist(group.x, group.y, player:getX(), player:getY()) <= 45
        end)
        if ok and nearMarker then return nil end
    end

    local data = bdb_data()
    if not data or type(data.pressure) ~= "table" then return nil end

    local pressure = tonumber(data.pressure.global) or 0
    local pacing = NPCDirectorBrainServerBridge.GetPacingModifier("activation")
    if pacing and pacing.pressureAdd and pacing.pressureAdd > 0 then
        pressure = pressure + pacing.pressureAdd
    end
    local feedback = NPCDirectorBrainServerBridge.GetOutcomeFeedback("materialization")
    if feedback and feedback.samples > 0 and feedback.failureRate >= 0.35 then
        pressure = pressure + (tonumber(feedback.pressureAdd) or 0)
    end
    local livePolicy = NPCDirectorBrainServerBridge.GetLivePolicy("activation")
    if livePolicy and livePolicy.pressureAdd and livePolicy.pressureAdd > 0 then
        pressure = pressure + livePolicy.pressureAdd
    end
    if group and group.x and group.y then
        local cooldownPenalty = bdb_cellCooldownScore(data, group.x, group.y, bdb_now())
        if cooldownPenalty and cooldownPenalty > 0 then
            pressure = pressure + (cooldownPenalty * 0.35)
        end
    end
    local threshold = tonumber(cfg.pressureGuardThreshold) or 1.65
    if pressure < threshold then return nil end

    local hardThreshold = tonumber(cfg.pressureGuardHardThreshold) or 2.60
    local reason = "director_pressure_guard"
    local retryMinutes = tonumber(cfg.pressureGuardRetryMinutes) or 1.5
    if pressure >= hardThreshold then
        reason = "director_pressure_guard_hard"
        retryMinutes = tonumber(cfg.pressureGuardCriticalRetryMinutes) or retryMinutes
    end

    local playerKey = budget and budget.key or bdb_safePlayerName(player, 0)
    data.lastGuardDecision = {
        t = bdb_now(),
        reason = reason,
        pressure = pressure,
        player = playerKey,
        groupId = group and group.id and tostring(group.id) or nil,
        dryRun = false
    }

    if group then
        NPCDirectorBrainServerBridge.PushEvent("director_activation_deferred", group.x, group.y, group.z or 0, {
            groupId = tostring(group.id or ""),
            reason = reason,
            pressure = math.floor(pressure * 100) / 100,
            player = playerKey
        })
    end

    return reason, bdb_clamp(retryMinutes, 0.1, 60.0) / 60
end

function NPCDirectorBrainServerBridge.Update()
    NPCDirectorBrainServerBridge.ApplySettings()
    if not NPCDirectorBrainServerBridge.Config.enabled then return false end

    local data, gmd = bdb_data()
    if not data or not gmd then return false end

    if NPCStreamingRuntimeBridge and NPCStreamingRuntimeBridge.ShouldQuarantineWorldTask then
        local okQ, deferQ, retryQ, reasonQ = pcall(function() return NPCStreamingRuntimeBridge.ShouldQuarantineWorldTask("director_brain") end)
        if okQ and deferQ then
            data.lastDecision = {
                t = bdb_now(),
                dryRun = true,
                selected = "wait",
                score = 0,
                reason = "sp_streaming_quarantine:" .. tostring(reasonQ or ""),
                pressure = data.pressure and data.pressure.global or 0,
                quarantineRetryTicks = retryQ
            }
            data.lastUpdate = data.lastDecision.t
            if NPCPerformanceTelemetryBridge and NPCPerformanceTelemetryBridge.Record then
                pcall(function() NPCPerformanceTelemetryBridge.Record("director_brain_quarantined", 1) end)
            end
            if NPCDiagnosticsBridge and NPCDiagnosticsBridge.Verbose then
                NPCDiagnosticsBridge.Verbose("WORLD_QUARANTINE", "defer_director_brain", {retryTicks=retryQ, reason=reasonQ}, "world-quarantine:director_brain")
            end
            return false
        end
    end

    local updatedPlayers = NPCDirectorBrainServerBridge.UpdatePlayers(data)
    local world = bdb_worldSnapshot(gmd)
    local activeCellCooldowns = bdb_trimCellCooldowns(data, bdb_now())
    local reviewedOutcomes, pendingOutcomes = NPCDirectorBrainServerBridge.ReviewOutcomes(data, gmd)
    local eventPressure = bdb_recentEventPressure(data)
    local playerPressure, playerCount = bdb_playerPressure(data)
    local groupPressure = 0

    if NPCWorldDirectorServer then
        local maxPhysical = tonumber(NPCWorldDirectorServer.MAX_PHYSICAL_GROUPS) or 20
        if maxPhysical < 1 then maxPhysical = 1 end
        groupPressure = (world.physical / maxPhysical) + (world.battles * 0.12) + (world.queue * 0.02)
    end

    local pressure = bdb_clamp(eventPressure + playerPressure + groupPressure, 0, 6)
    data.pressure.global = pressure
    data.pressure.event = eventPressure
    data.pressure.player = playerPressure
    data.pressure.group = groupPressure
    data.pressure.updatedAt = bdb_now()
    data.lastWorld = world

    local profileSummary = NPCDirectorBrainServerBridge.UpdateProfileSummary(data, world, pressure)
    local pacing = NPCDirectorBrainServerBridge.UpdatePacing(data, world, pressure, playerPressure)
    local candidates = NPCDirectorBrainServerBridge.BuildCandidates(data, world, pressure, playerPressure)
    local selected = candidates[1] or {kind = "wait", score = 0, reason = "no candidates"}
    data.lastDecision = {
        t = bdb_now(),
        dryRun = NPCDirectorBrainServerBridge.Config.dryRun ~= false,
        selected = selected.kind,
        score = selected.score,
        reason = selected.reason,
        pressure = pressure,
        playerCount = playerCount,
        pendingOutcomes = pendingOutcomes,
        reviewedOutcomes = reviewedOutcomes,
        pacingPhase = pacing and pacing.phase or nil,
        candidates = candidates
    }
    NPCDirectorBrainServerBridge.RecordIntentDecision(data, data.lastDecision, candidates)
    NPCDirectorBrainServerBridge.RecordTelemetrySnapshot(data, world, pressure, eventPressure, playerPressure, groupPressure, updatedPlayers, activeCellCooldowns, pendingOutcomes, reviewedOutcomes, candidates)
    NPCDirectorBrainServerBridge.RunHealthMonitor(data, world, pressure, pendingOutcomes, reviewedOutcomes, candidates)
    NPCDirectorBrainServerBridge.RunConsistencyCheck(data, world, pressure, pendingOutcomes, reviewedOutcomes, candidates)
    NPCDirectorBrainServerBridge.RunRuntimeSafetyCheck(data, world, pressure, pendingOutcomes, reviewedOutcomes, candidates)
    NPCDirectorBrainServerBridge.BuildFoundationSummary(data, world, pressure, pendingOutcomes, reviewedOutcomes, candidates)
    NPCDirectorBrainServerBridge.BuildAdminReport(data, world, pressure, pendingOutcomes, reviewedOutcomes, candidates)
    data.lastUpdate = data.lastDecision.t

    if NPCDirectorBrainServerBridge.Config.debugLog then
        bdb_log("[NPCDirectorBrainServerBridge] pressure=" .. tostring(math.floor(pressure * 100) / 100) ..
            " event=" .. tostring(math.floor(eventPressure * 100) / 100) ..
            " player=" .. tostring(math.floor(playerPressure * 100) / 100) ..
            " groups=" .. tostring(world.virtual) .. "/" .. tostring(world.physical) ..
            " battles=" .. tostring(world.battles) ..
            " selected=" .. tostring(selected.kind) ..
            " pacing=" .. tostring(pacing and pacing.phase or "off") ..
            " intent=" .. tostring(data.lastIntentSummary and data.lastIntentSummary.dominantIntent or selected.kind) ..
            " telemetry=" .. tostring(data.lastTelemetrySummary and data.lastTelemetrySummary.pressureTrend or "stable") ..
            " health=" .. tostring(data.lastHealthSummary and data.lastHealthSummary.lastSeverity or "ok") ..
            " profile=" .. tostring(profileSummary and profileSummary.name or NPCDirectorBrainServerBridge.Config.profileName or "unknown") ..
            " consistency=" .. tostring(data.lastConsistencySummary and data.lastConsistencySummary.status or "ok") ..
            " safety=" .. tostring(data.lastRuntimeSafety and data.lastRuntimeSafety.status or "ok") ..
            " foundation=" .. tostring(data.lastFoundationSummary and data.lastFoundationSummary.status or "unknown") ..
            " report=" .. tostring(data.lastAdminReport and data.lastAdminReport.pressureBand or "none") ..
            " policy=" .. tostring(data.lastLivePolicy and data.lastLivePolicy.retarget and data.lastLivePolicy.retarget.reason or "ok") ..
            " dryRun=" .. tostring(NPCDirectorBrainServerBridge.Config.dryRun ~= false) ..
            " outcomes=" .. tostring(pendingOutcomes) .. "/" .. tostring(reviewedOutcomes) ..
            " players=" .. tostring(updatedPlayers))
    end

    return true
end

local function bdb_everyTenMinutes()
    NPCDirectorBrainServerBridge.Update()
end

if not NPCDirectorBrainServerBridge._eventsInstalled then
    NPCDirectorBrainServerBridge.ApplySettings()
    Events.EveryTenMinutes.Add(bdb_everyTenMinutes)
    NPCDirectorBrainServerBridge._eventsInstalled = true
end
