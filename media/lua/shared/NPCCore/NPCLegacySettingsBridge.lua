NPCLegacySettingsBridge = NPCLegacySettingsBridge or {}

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

local NPC_LEGACY_SETTINGS_SANDBOX = NPCLegacyContractBridge.Sandbox or {}

local function bls_legacyGlobal(key)
    if NPCLegacyGlobalsBridge and NPCLegacyGlobalsBridge.Get then
        return NPCLegacyGlobalsBridge.Get(key)
    end
    return nil
end

NPCLegacySettingsBridge.Defaults = NPCLegacySettingsBridge.Defaults or {
    World_Enabled = true,
    World_InitialGroups = 18,
    World_MaxVirtualGroups = 56,
    World_MaxPhysicalGroups = 5,
    World_MaxGroupActivationsPerUpdate = 1,
    World_MaxGroupActivationsPerPlayer = 1,
    World_MaxBattlePairActivationsPerUpdate = 1,
    World_TeleportActivationCooldownSeconds = 8,
    World_TeleportDistanceThreshold = 180,
    World_TeleportMarkerMaterializeRadius = 36,
    World_TeleportMarkerBypassDefers = true,
    World_DeferActivationWhenNPCNearPlayer = true,
    World_ActivationNPCSoftCapPerPlayer = 12,
    World_DeferredActivationRetryMinutes = 0.72,
    World_MaterializeBattlePairAsSingleWave = true,
    World_InitialRoadPatrolsGreen = 4,
    World_InitialRoadPatrolsRed = 4,
    World_MaxRoadPatrols = 14,
    World_SpawnChancePerTenMin = 12,
    World_PatrolEncounterPairs = 3,
    World_UrbanSpawnRadius = 220,
    World_RoadPatrolUrbanRadius = 220,
    World_PatrolTargetRadius = 360,
    World_RelocateRuralGroups = true,
    World_BattleRemainsMaterialize = true,
    World_BattleRemainsActivationRadius = 70,
    World_BattleRemainsMaxRecords = 12,
    World_BattleRemainsMaxBodies = 2,
    World_BattleRemainsMaxDebris = 8,
    World_BattleRemainsMinSpacing = 96,
    World_BattleRemainsCleanupEnabled = true,
    World_BattleRemainsCleanupRadius = 42,
    World_BattleRemainsCleanupCorpseSoftCap = 18,
    World_BattleRemainsCleanupDebrisSoftCap = 24,
    World_UrbanCoverPropsEnabled = true,
    World_UrbanCoverPropsRadius = 58,
    World_UrbanCoverPropsIntervalTicks = 900,
    World_UrbanCoverPropsMaxClustersPerRun = 2,
    World_UrbanCoverPropsMaxRecords = 120,
    World_UrbanCoverPropsMinSpacing = 18,
    World_UrbanCoverPropsBuildingRadius = 7,
    World_UrbanCoverPropsAttemptsPerPlayer = 34,
    World_UrbanCoverPropsMaxItemsPerCluster = 4,
    Perf_AllowHighPhysicalPopulation = true,

    SpawnQueue_Enabled = true,
    SpawnQueue_MaxPerTick = 1,
    SpawnQueue_MaxEventsPerTick = 1,
    SpawnQueue_MaxPending = 24,
    SpawnQueue_MaxPendingPerGroup = 1,
    SpawnQueue_MaxRetries = 8,
    SpawnQueue_RetryDelayTicks = 12,
    SpawnQueue_MaxRetryDelayTicks = 180,

    AIWork_Enabled = true,
    AIWork_MaxHeavyOpsPerTick = 6,
    AIWork_CombatOpsPerTick = 9,
    AIWork_UtilityOpsPerTick = 5,
    AIWork_ZombieOpsPerTick = 5,
    AIWork_MarkerOpsPerTick = 7,
    AIWork_PhysicalOpsPerTick = 6,
    AIWork_PathOpsPerTick = 2,
    AIWork_ZombiePathOpsPerTick = 2,
    AIWork_SenseOpsPerTick = 4,
    AIWork_LOSOpsPerTick = 5,
    AIWork_AdaptiveBudget = true,
    AIWork_AdaptiveSampleTicks = 3,
    AIWork_LowFPS = 52,
    AIWork_CriticalFPS = 45,
    AIWork_PanicFPS = 36,
    AIWork_HighNPC = 14,
    AIWork_CriticalNPC = 26,
    AIWork_HighZombies = 110,
    AIWork_CriticalZombies = 190,
    AIWork_HighBudgetPercent = 55,
    AIWork_CriticalBudgetPercent = 32,
    AIWork_PanicBudgetPercent = 12,
    AIWork_HighIntervalMultiplier = 2,
    AIWork_CriticalIntervalMultiplier = 5,
    AIWork_PanicIntervalMultiplier = 12,
    AIWork_MaxZombieInterval = 90,
    AIWork_DebugSummary = false,
    AIWork_DebugSummaryMs = 15000,
    AIWork_CombatThinkInterval = 2,
    AIWork_IdleThinkInterval = 10,
    AIWork_FarThinkInterval = 38,
    AIWork_ZombieCheckInterval = 5,
    AIWork_ZombieCacheBaseInterval = 4,
    AIWork_ZombieCacheHighInterval = 6,
    AIWork_ZombieCacheCriticalInterval = 9,

    AsyncBudget_Enabled = true,
    AsyncBudget_MaxJobsPerTick = 1,
    AsyncBudget_MaxStepsPerJob = 32,
    AsyncBudget_MaxQueuedJobs = 18,
    AsyncBudget_MinIntervalTicks = 6,
    AsyncBudget_HighLoadIntervalTicks = 12,
    AsyncBudget_DisableOnCriticalLoad = true,
    AsyncBudget_Debug = false,

    BufferPool_Enabled = true,
    BufferPool_MaxBuffers = 40,
    BufferPool_MaxEntriesToClear = 2048,
    BufferPool_Debug = false,

    NavPerf_Enabled = true,
    NavPerf_RepairQueueEnabled = true,
    NavPerf_RepairPerTick = 2,
    NavPerf_MaxRepairQueue = 64,
    NavPerf_RepairCooldownMs = 1250,
    NavPerf_RepairHoldMs = 2200,
    NavPerf_BadCellCooldownMs = 90000,
    NavPerf_BadCellMaxRecords = 360,
    NavPerf_BadCellPenalty = 7.5,
    NavPerf_BadTargetPenalty = 12.0,
    NavPerf_CrowdPenalty = 2.2,
    NavPerf_CrowdRadius = 1,
    NavPerf_PortalGuardEnabled = true,
    NavPerf_PortalHoldMs = 1100,
    NavPerf_PortalPenalty = 6.0,
    NavPerf_PortalQueueEnabled = true,
    NavPerf_PortalQueueHoldMs = 8500,
    NavPerf_PortalQueueWaitMs = 650,
    NavPerf_PortalQueueMaxWaitMs = 6500,
    NavPerf_PortalQueueMaxPerPortal = 6,
    NavPerf_PortalQueueStaleMs = 12000,
    NavPerf_ProgressReward = 1.2,
    NavPerf_Debug = false,

    SquadNav_Enabled = true,
    SquadNav_MinDistance = 18,
    SquadNav_StepDistance = 12,
    SquadNav_SearchRadius = 5,
    SquadNav_CacheMs = 2200,
    SquadNav_MaxCacheRecords = 240,
    SquadNav_BucketSize = 10,
    SquadNav_MaxSegmentsPerTask = 10,
    SquadNav_ArriveDist = 1.35,
    SquadNav_FormationSpread = 1.25,
    SquadNav_RoadBias = true,
    SquadNav_Debug = false,

    LOD_PhysicalSpawnRadius = 130,
    LOD_PhysicalDespawnRadius = 360,
    LOD_PhysicalDespawnHighLoadRadius = 320,
    LOD_PhysicalDespawnCriticalRadius = 260,
    LOD_PhysicalDespawnImportantRadius = 620,
    LOD_PhysicalDespawnMinAgeSeconds = 6,
    LOD_PhysicalCleanupIntervalTicks = 300,
    LOD_PhysicalCleanupHighIntervalTicks = 90,
    LOD_PhysicalCleanupCriticalIntervalTicks = 30,
    LOD_MaxPhysicalNPCPerPlayer = 12,
    LOD_MaxPhysicalNPCGlobal = 28,

    Radio_Enabled = true,
    Radio_Radius = 72,
    Radio_MemorySeconds = 38,
    Radio_FlankEnabled = true,
    Radio_FlankDistance = 8.0,
    Radio_CoverDistance = 5.5,
    Radio_OverwatchDistance = 13.0,
    Radio_FriendlyFireCheck = true,

    Sense_Enabled = true,
    Sense_ViewDistance = 36,
    Sense_ZombieViewDistance = 26,
    Sense_HearingRadius = 12,
    Sense_MemorySeconds = 5.0,
    Sense_ThreatScanCooldownMs = 450,
    Sense_MaxThreatCandidatesPerScan = 18,
    Sense_LOSCacheMs = 220,
    Sense_LOSCacheMaxRecords = 360,
    Sense_IdleScanInterval = 2,

    Health_MaxHealth = 3.0,
    Health_HardMaxHealth = 4.0,
    Health_AutoRegenEnabled = true,
    Health_RegenDelaySeconds = 5.5,
    Health_RegenPerSecond = 0.35,
    Health_ZombieDamageToNPC = true,

    Persistent_Enabled = true,
    Persistent_MaxProfiles = 500,
    Persistent_MaxInventoryLite = 36,

    Base_ZoneStockMax = 999,
    Base_ZoneProductionRate = 1.0,
    Base_ZoneConsumptionRate = 1.0,
    Base_ZoneMarkersEnabled = true,

    Net_DeltaSyncEnabled = true,
    Net_MaxMarkerEventsPerTick = 7,
    Net_SnapshotChunkSize = 20,
    Net_GlobalMarkerUpdateSeconds = 45.0,
    Net_NearMarkerUpdateSeconds = 10.0,
    Net_DebugMapEnabled = true,
    Net_MaxMarkerRemovesPerTick = 7,
    Net_MaxPendingMarkerUpdates = 350,
    Net_MaxPendingMarkerRemoves = 120,
    Net_MaxSnapshotChunksPerTick = 1,
    Net_MaxSnapshotMarkers = 650,
    Net_MaxSimStateUpdatesPerTick = 10,
    Net_LifecycleStateUpdatesPerRun = 18,
    Net_LifecycleHeavyPayloadSeconds = 30,
    Net_QueuedSnapshotSync = true,
    Net_SyncCooldownSeconds = 7.5,
    Net_PayloadSanitizer = true,
    Net_MaxMarkerStringBytes = 96,
    Net_MaxMarkerTableEntries = 24,
    Net_ClientCommandRateLimit = true,
    Net_ClientCommandMinIntervalMs = 40,
    Net_PlayerUpdateMinIntervalMs = 700,
    Net_StateUpdateMinIntervalMs = 250,
    Net_DebugMapRequestCooldownSeconds = 10.0,
    Net_DebugMapMaterializeCooldownMs = 2000,
    Net_OrderCommandMinIntervalMs = 300,
    Net_SpawnCommandCooldownSeconds = 2.0,
    Net_MaxClientCommandFields = 120,
    Net_MaxClientStringBytes = 160,
    Net_MaxClientPayloadDepth = 4,
    Net_LogDroppedCommands = false,

    Debug_MapMarkersEnabled = true,
    Debug_WorldMapMarkersEnabled = true,
    Debug_MiniMapMarkersEnabled = false,
    Debug_NPCMarkersEnabled = true,
    Debug_ShowBattleIcon = true,
    Debug_ShowPatrolLetterP = true,
    Debug_ShowStateOverHead = false,
    Debug_DiagnosticsLog = true,
    Debug_DiagnosticsFileLog = true,
    Debug_DiagnosticsFileName = "NPC_FACTIONS.log",
    Debug_DiagnosticsConsoleLog = false,
    Debug_DiagnosticsVerbose = false,
    Debug_DiagnosticsFullTrace = false,
    Debug_DiagnosticsRateMs = 7000,
    Debug_DiagnosticsIdentityGlobalRateMs = 3500,
    Debug_DiagnosticsNPCFrameMs = 5000,
    Debug_DiagnosticsTransitionMs = 900,
    Debug_DiagnosticsWorldSnapshotMs = 15000,
    Debug_DiagnosticsMaxLinesPerSecond = 24,
    Debug_DiagnosticsCompactRepeats = true,
    Debug_DiagnosticsCompactFlushMs = 1200,
    Debug_DiagnosticsSystemSnapshot = true,
    Debug_DiagnosticsSystemSnapshotMs = 30000,
    Debug_DiagnosticsRiskActions = true,
    Debug_DiagnosticsVisibleNPC = false,
    Debug_DiagnosticsVisibleNPCMs = 10000,
    Debug_DiagnosticsVisibleNPCRadius = 45,
    Debug_TransientMarkerGraceSeconds = 10,
    Debug_MapMarkerAutoMaterialize = false,
    Debug_MapMarkerMaterializeCooldownMs = 10000,
    Debug_VirtualMarkerActivationRadius = 70,
    Debug_MaxWorldMapMarkers = 160,
    Debug_MaxMiniMapMarkers = 45,
    Debug_MapLabelsUnderLoad = false,
    Debug_MapRuntimeEntityMarkersUnderLoad = false,
    Debug_MapHardCapAtLowFPS = true,

    Faction_Enabled = true,
    Faction_PlayerMenuEnabled = true,
    Faction_DefaultPlayerSide = 3,
    Faction_BlackDurationMinutes = 30,
    Faction_PlayerAutoSideOnHit = true,
    Faction_NPCPanicRogueEnabled = true,
    Faction_NPCPanicFearThreshold = 0.92,
    Faction_NPCPanicMoraleMax = 0.22,
    Faction_NPCPanicRogueChancePerMinute = 35,
    Faction_RedGoodMoodHoldFire = true,
    Faction_GoodMoodMoraleThreshold = 0.86,
    Faction_GoodMoodFearMax = 0.22,
    Faction_GoodMoodNeutralMinutes = 20,

    Mercenary_Enabled = true,
    Mercenary_HireEnabled = true,
    Mercenary_BlueRoadPatrolChance = 25,
    Mercenary_BlueGroupChance = 10,
    Mercenary_EliteOnBlue = true,
    Mercenary_EliteHealth = 4.0,
    Mercenary_AccuracyBoost = 1.75,
    Mercenary_PrimaryMagCount = 8,
    Mercenary_SecondaryMagCount = 4,
    Mercenary_HireResource = 1,
    Mercenary_HireCostCount = 10,
    Mercenary_GoldJewelryCost = 2,
    Mercenary_AllowSilverPayment = true,
    Mercenary_SilverJewelryCost = 6,
    Spy_Enabled = true,
    Spy_GoldJewelryCost = 1,
    Spy_AllowSilverPayment = true,
    Spy_SilverJewelryCost = 3,
    Spy_ShowMarkers = true,
    Spy_AllSpiesAutoAlly = true,
    Spy_SabotageEnabled = true,
    Spy_SabotageTickMinutes = 30,
    Spy_BaseTheftRate = 0.12,
    Spy_FalseRadioChance = 35,

    Prisoner_Enabled = true,
    Prisoner_HealthThreshold = 0.20,
    Prisoner_InterrogateCooldownMinutes = 180,
    Prisoner_LieChance = 20,
    Prisoner_IntelNoiseTiles = 24,
    Prisoner_IntelMarkerHours = 24,
    Prisoner_MaxIntelMarkers = 50,

    Contract_Enabled = true,
    Contract_SupplyChance = 60,
    Contract_SupplyRequiredAmount = 5,
    Contract_PreferredResourceSoftCap = 18,
    Contract_ReconSearchRadius = 2600,
    Contract_ReconCompleteRadius = 28,
    Contract_ExpireHours = 24,
    Contract_RewardFavor = 3,
    Contract_RecoverEnabled = true,
    Contract_RecoverChance = 25,
    Contract_PhysicalObjectivesEnabled = true,
    Contract_PhysicalSpawnDistance = 90,
    Contract_PhysicalCompleteRadius = 18,
    Contract_PhysicalObjectiveSearchRadius = 10,
    Contract_PhysicalMaxMaterializePerTick = 1,
    Contract_PhysicalGuardsEnabled = true,
    Contract_PhysicalGuardMin = 1,
    Contract_PhysicalGuardMax = 3,

    Convoy_Enabled = true,
    Convoy_MaxActive = 10,
    Convoy_MoveSpeedTilesPerHour = 92,
    Convoy_InteractionRadius = 28,
    Convoy_BaseInteractionPad = 18,
    Convoy_CargoAmount = 8,
    Convoy_RaidCargoAmount = 10,
    Convoy_RaidSuccessChance = 72,
    Convoy_EscortRewardFavor = 4,
    Convoy_RaidRewardFavor = 2,
    Convoy_ExpireHours = 18,
    Convoy_ArrivedKeepHours = 2,
    Convoy_MaxRouteDistance = 3200,
    Convoy_MaxLootItems = 8,
    Convoy_RoadRoutingEnabled = true,
    Convoy_PhysicalEnabled = true,
    Convoy_PhysicalSpawnDistance = 96,
    Convoy_PhysicalMaxMaterializePerTick = 1,
    Convoy_PhysicalGuardMin = 2,
    Convoy_PhysicalGuardMax = 5,
    Convoy_PhysicalCargoOnRaid = true,
    Convoy_PhysicalCargoMaxItems = 10,

    Disguise_Enabled = true,
    Disguise_DurationMinutes = 180,
    Disguise_CompromiseMinutes = 120,
    Disguise_InspectChance = 35,
    Disguise_CloseInspectRadius = 6,

    Checkpoint_Enabled = true,
    Checkpoint_MaxActive = 14,
    Checkpoint_InteractionRadius = 26,
    Checkpoint_MinSpacing = 360,
    Checkpoint_TollAmount = 4,
    Checkpoint_PassHours = 8,
    Checkpoint_PhysicalEnabled = true,
    Checkpoint_PhysicalSpawnDistance = 92,
    Checkpoint_PhysicalMaxMaterializePerTick = 1,
    Checkpoint_PhysicalGuardMin = 2,
    Checkpoint_PhysicalGuardMax = 5,
    Checkpoint_PhysicalPropsEnabled = true,
    Checkpoint_PhysicalPropRadius = 4,
    Checkpoint_PhysicalPropsMax = 6,
    Checkpoint_LifetimeHours = 24,

    Documents_Enabled = true,
    Documents_DocumentHours = 72,
    Documents_PasswordHours = 24,
    Documents_IntelRewardChance = 55,
    Documents_ForgedFailChance = 12,
    Documents_PhysicalItemsEnabled = true,
    Documents_PhysicalCheckpointUseEnabled = true,
    Documents_PhysicalConsumeOnFail = true,

    RadioIntercept_Enabled = true,
    RadioIntercept_RequireRadio = true,
    RadioIntercept_RequirePoweredRadio = true,
    RadioIntercept_CooldownMinutes = 20,
    RadioIntercept_HistoryLimit = 10,
    RadioIntercept_FalseChance = 15,
    RadioIntercept_StaleChance = 20,
    RadioIntercept_IncompleteChance = 22,
    RadioIntercept_PasswordLeakChance = 22,
    RadioIntercept_RedFrequency = 143.7,
    RadioIntercept_GreenFrequency = 152.3,
    RadioIntercept_BlueFrequency = 161.5,
    RadioIntercept_BlackFrequency = 171.9,
    RadioIntercept_SignalRange = 1800,
    RadioIntercept_FrequencyTolerance = 0.35,
    RadioIntercept_LockThreshold = 62,
    RadioIntercept_MarkerEnabled = true,
    RadioIntercept_MarkerHours = 6,
    RadioIntercept_MarkerNoiseTiles = 45,
    RadioIntercept_MinMarkerLock = 70,
    RadioIntercept_MonitorEnabled = true,
    RadioIntercept_MonitorTickMinutes = 10,
    RadioIntercept_MonitorMinLock = 58,
    RadioIntercept_EncryptionEnabled = true,
    RadioIntercept_RedEncryptedChance = 35,
    RadioIntercept_GreenEncryptedChance = 35,
    RadioIntercept_BlueEncryptedChance = 15,
    RadioIntercept_BlackEncryptedChance = 55,
    RadioIntercept_DecodeProgressPerLock = 18,
    RadioIntercept_DecodeThreshold = 100,
    RadioIntercept_WorldEventsEnabled = true,
    RadioIntercept_EventMemoryHours = 12,
    RadioIntercept_EventRefreshMinutes = 10,
    RadioIntercept_EventMaxCount = 80,
    RadioIntercept_EventWeightBonus = 4,
    RadioIntercept_CounterIntelEnabled = true,
    RadioIntercept_CounterIntelBaseChance = 4,
    RadioIntercept_CounterIntelMonitorChance = 2,
    RadioIntercept_CounterIntelBlackBonus = 8,
    RadioIntercept_CounterIntelHeatPerScan = 2.5,
    RadioIntercept_CounterIntelHeatDecayHours = 12,
    RadioIntercept_CounterIntelMaxHeat = 60,
    RadioIntercept_CounterIntelBurnHours = 4,
    RadioIntercept_CounterIntelFalseSignalChance = 45,
    RadioIntercept_CounterIntelMarkerEnabled = true,
    RadioIntercept_CounterIntelMarkerHours = 3,
    RadioIntercept_HistoryMaxAgeHours = 48,
    RadioIntercept_RadioSilenceHours = 2,
    RadioIntercept_RadioSilenceHeatReduction = 12,

    Signal_Enabled = true,
    Signal_RequireItems = false,
    Signal_ConsumeItems = false,
    Signal_CooldownMinutes = 4,
    Signal_MarkerHours = 3,
    Signal_MaxActiveMarkers = 32,

    Wounded_Enabled = true,
    Wounded_DownChance = 65,
    Wounded_HealthThreshold = 0.28,
    Wounded_DownedHealth = 0.22,
    Wounded_StabilizedHealth = 0.48,
    Wounded_BleedoutMinutes = 45,
    Wounded_RequireMedicalItem = false,
    Wounded_ConsumeMedicalItem = false,
    Wounded_EvacuationBaseRadius = 2600,

    Loyalty_Enabled = true,
    Loyalty_Initial = 55,
    Loyalty_Max = 100,
    Loyalty_Min = 0,
    Loyalty_HireBonus = 6,
    Loyalty_CommandPenalty = -0.25,
    Loyalty_WoundedPenalty = -3,
    Loyalty_StabilizeBonus = 12,
    Loyalty_EvacuateBonus = 8,
    Loyalty_AbandonPenalty = -30,
    Loyalty_AbandonWitnessPenalty = -12,
    Loyalty_AllowRefuseRiskyOrders = false,
    Loyalty_RefuseThreshold = 18,
    Loyalty_RefuseChance = 35,

    Bounty_Enabled = true,
    Bounty_HitValue = 3,
    Bounty_KillValue = 18,
    Bounty_OwnFactionKillBonus = 20,
    Bounty_AlertThreshold = 18,
    Bounty_WantedThreshold = 30,
    Bounty_HuntedThreshold = 55,
    Bounty_KillOnSightThreshold = 80,
    Bounty_DurationHours = 72,
    Bounty_HitCooldownMinutes = 2,
    Bounty_DecayPerDay = 6,
    Bounty_CheckpointBlockThreshold = 18,
    Bounty_HunterRetargetEnabled = true,
    Bounty_HunterRetargetRadius = 2400,
    Bounty_HunterMaxGroupsPerFaction = 2,

    Leader_Enabled = true,
    Leader_BaseCommandersEnabled = true,
    Leader_SquadLeadersEnabled = true,
    Leader_MaxGroupLeadersPerSide = 8,
    Leader_ReplacementHours = 24,
    Leader_BaseDeathReadinessPenalty = 18,
    Leader_BaseDeathMoralePenalty = 0.18,
    Leader_KillBountyBonus = 35,
    Leader_RadioWeight = 3,
    Leader_PhysicalEnabled = true,
    Leader_PhysicalSpawnDistance = 120,
    Leader_PhysicalGuardMin = 2,
    Leader_PhysicalGuardMax = 4,
    Leader_PhysicalMaxMaterializePerTick = 1,
    Leader_PhysicalRetryHours = 0.35,

    BaseStockpile_PhysicalEnabled = true,
    BaseStockpile_SpawnDistance = 105,
    BaseStockpile_PlacementRadius = 9,
    BaseStockpile_UpdateTicks = 900,
    BaseStockpile_MaxMaterializePerRun = 1,
    BaseStockpile_MaxActivePerBase = 3,
    BaseStockpile_RecordTTLHours = 72,
    BaseStockpile_CooldownHours = 10,
    BaseStockpile_MinVirtualStock = 4,
    BaseStockpile_StockPortion = 0.22,
    BaseStockpile_MaxStockPerContainer = 10,
    BaseStockpile_MaxItemsPerContainer = 8,

    BlackMarket_Enabled = true,
    BlackMarket_MaxContacts = 10,
    BlackMarket_InteractionRadius = 28,
    BlackMarket_ContactHours = 36,
    BlackMarket_ForgedPapersCost = 4,
    BlackMarket_StolenBadgeCost = 2,
    BlackMarket_PasswordCost = 3,
    BlackMarket_BountyPayoffCost = 3,
    BlackMarket_BountyReduction = 35,
    BlackMarket_LeaderTipCost = 2,
    BlackMarket_AmmoDropCost = 5,
    BlackMarket_MedicalDropCost = 4,
    BlackMarket_WeaponDropCost = 3,
    BlackMarket_ArmorDropCost = 2,
    BlackMarket_DeadDropMinDistance = 2,
    BlackMarket_DeadDropMaxDistance = 5,
    BlackMarket_DeadDropRevealDistance = 72,
    BlackMarket_RadioWeight = 3,
    BlackMarket_ReputationEnabled = true,
    BlackMarket_DeadDropEnabled = true,
    BlackMarket_StashDealChance = 28,
    BlackMarket_AmbushChance = 12,
    BlackMarket_CourierEnabled = true,
    BlackMarket_PriceVolatility = 20,

    RadioIntercept_PhysicalStashesEnabled = true,
    RadioIntercept_StashRevealDistance = 36,
    RadioIntercept_StashMarkerOverhead = true,
    RadioIntercept_StashGuardChance = 20,
    RadioIntercept_StashAmbushChance = 12,
    RadioIntercept_StashLootedMarkerHours = 2,
    RadioIntercept_CounterIntelHunterWavesEnabled = true,
    RadioIntercept_CounterIntelHunterMinHeat = 25,
    RadioIntercept_CounterIntelHunterWavesMax = 3,
    RadioIntercept_CounterIntelHunterCooldownHours = 6,
    RadioIntercept_CounterIntelHunterMinSpawnDistance = 110,
    RadioIntercept_CounterIntelHunterMaxSpawnDistance = 240,
    RadioIntercept_CounterIntelHunterMaxActivePerPlayer = 1,
    RadioIntercept_CounterIntelHunterEliteWaveLevel = 9,

    IntelDossier_Enabled = true,
    IntelDossier_Threshold = 100,
    IntelDossier_RadioGain = 12,
    IntelDossier_BaseProbeGain = 20,
    IntelDossier_BaseProbeRadius = 42,
    IntelDossier_BaseProbeCooldownMinutes = 60,
    IntelDossier_ConvoyGain = 30,
    IntelDossier_StashGain = 20,
    IntelDossier_SpyGain = 16,
    IntelDossier_NeutralCollectsBothSides = true,
    IntelDossier_SellEnabled = true,
    IntelDossier_GoldReward = 100,
    IntelDossier_EncryptedGoldReward = 250,
    IntelDossier_SaleHeatGain = 5,
    IntelDossier_MaxSoldPerDeal = 5,
    IntelDossier_NotifyProgress = false,

    WorldMarker_Enabled = true,
    WorldMarker_NPCNameplates = true,
    WorldMarker_FactionColors = true,
    WorldMarker_NPCLevels = true,
    WorldMarker_NPCStars = true,
    WorldMarker_EliteLabels = true,
    WorldMarker_StashMarkers = true,
    WorldMarker_DrawDistance = 46,
    WorldMarker_MaxVisible = 22,
    WorldMarker_UpdateTicks = 12,
    WorldMarker_OnlyWhenAimed = false,
    WorldMarker_HideThroughWalls = true,

    HeatWanted_Enabled = true,
    HeatWanted_RadioScanHeat = 1.5,
    HeatWanted_IntelProgressScale = 0.05,
    HeatWanted_BaseReconHeat = 1.0,
    HeatWanted_IntelSaleHeat = 4.0,
    HeatWanted_IntelSaleFactionScale = 0.5,
    HeatWanted_BlackMarketDealHeat = 1.0,
    HeatWanted_BlackMarketDeadDropHeat = 2.0,
    HeatWanted_CompromisedDealHeat = 6.0,
    HeatWanted_DecayPerDay = 8.0,
    HeatWanted_MaxHeat = 150.0,
    HeatWanted_Level1Threshold = 15.0,
    HeatWanted_Level2Threshold = 35.0,
    HeatWanted_Level3Threshold = 60.0,
    HeatWanted_Level4Threshold = 90.0,
    HeatWanted_Level5Threshold = 125.0,
    HeatWanted_CounterIntelScale = 0.45,
    HeatWanted_FactionBountyBridgeEnabled = true,
    HeatWanted_BountyMultiplier = 0.35,
    HeatWanted_BountyMinLevel = 3,
    HeatWanted_MarkerEnabled = true,
    HeatWanted_MarkerMinLevel = 3,
    HeatWanted_NotifyLevelChanges = true,

    ZombieNPC_AggroEnabled = true,
    ZombieNPC_AggroRadius = 22,
    ZombieNPC_HearingRadius = 36,
    ZombieNPC_VisualChaseRadius = 24,
    ZombieNPC_DamageMultiplier = 1.0,
    ZombieNPC_MaxTargetRefreshPerTick = 10,
    ZombieNPC_AttackVisualsEnabled = true,

    WorldRules_Enabled = true,
    WorldRules_SoftlockWarnings = true,
    WorldRules_SyncAfterConsequence = true,
    WorldRules_BountyOverridesDisguise = true,
    WorldRules_DocumentsBlockedByBounty = true,
    WorldRules_LeaderPenaltyCooldownHours = 12,
    WorldRules_DebugMenu = true,

    Runtime_TaskQueueEnabled = true,
    Runtime_TaskQueueHighBudget = 3,
    Runtime_TaskQueueNormalBudget = 6,
    Runtime_TaskQueueLowBudget = 8,
    Runtime_SettingsCacheSeconds = 5,
    Runtime_TablePoolMax = 48,

    StreamingRuntime_Enabled = true,
    StreamingRuntime_Debug = false,
    StreamingRuntime_SampleTicks = 24,
    StreamingRuntime_FastVehicleSpeed = 8.0,
    StreamingRuntime_TravelCooldownSeconds = 15,
    StreamingRuntime_TeleportDistance = 80,
    StreamingRuntime_TeleportCooldownSeconds = 1,
    StreamingRuntime_TeleportSnapshotChunksPerTick = 6,
    StreamingRuntime_DeferMaterialization = true,
    StreamingRuntime_DeferRetrySeconds = 12,
    StreamingRuntime_CriticalRetrySeconds = 24,
    StreamingRuntime_NPCHigh = 28,
    StreamingRuntime_NPCCritical = 46,
    StreamingRuntime_PendingSpawnHigh = 4,
    StreamingRuntime_PendingSpawnCritical = 8,
    StreamingRuntime_PendingMarkerHigh = 70,
    StreamingRuntime_PendingMarkerCritical = 150,
    StreamingRuntime_PendingTaskHigh = 36,
    StreamingRuntime_PendingTaskCritical = 90,
    StreamingRuntime_MediumThreshold = 28,
    StreamingRuntime_HighThreshold = 48,
    StreamingRuntime_CriticalThreshold = 78,
    StreamingRuntime_HeatDecay = 11,

    CrowdBudget_Enabled = true,
    CrowdBudget_Debug = false,
    CrowdBudget_SampleTicks = 12,
    CrowdBudget_NearRadius = 180,
    CrowdBudget_ZombieRadius = 140,
    CrowdBudget_MaxNPCNearPlayer = 12,
    CrowdBudget_CriticalNPCNearPlayer = 20,
    CrowdBudget_MaxZombiesNearPlayer = 70,
    CrowdBudget_CriticalZombiesNearPlayer = 120,
    CrowdBudget_RetrySeconds = 12,
    CrowdBudget_CriticalRetrySeconds = 24,
    CrowdBudget_DripFeedMaxBatch = 3,
    CrowdBudget_CriticalDripFeedMaxBatch = 1,
    CrowdBudget_UrbanTightenPercent = 20,
    CrowdBudget_FastTravelTightenPercent = 35,
    CrowdBudget_PreserveCombat = true,

    AILOD_Enabled = true,
    AILOD_NPCFullRadius = 38,
    AILOD_NPCHighRadius = 82,
    AILOD_NPCMediumRadius = 160,
    AILOD_NPCLowRadius = 300,
    AILOD_ProxyUpdateSeconds = 22,
    AILOD_UseCriticality = true,
    AILOD_DebugLog = false,
    AILOD_PhysicalFrameEnabled = true,
    AILOD_PhysicalFullInterval = 1,
    AILOD_PhysicalHighInterval = 4,
    AILOD_PhysicalMediumInterval = 16,
    AILOD_PhysicalLowInterval = 48,
    AILOD_PhysicalProxyInterval = 120,
    AILOD_SpawnWakeSeconds = 8,
    BrainScheduler_Enabled = true,
    BrainScheduler_MinThinkMs = 180,
    BrainScheduler_LowThinkMs = 1500,
    BrainScheduler_ProxyThinkMs = 4000,
    BrainScheduler_DebugLog = false,
    Interest_Enabled = true,
    Interest_WorldMapRadius = 600,
    Interest_MinimapRadius = 150,
    Interest_SyncRadius = 750,
    Interest_AdminRadius = 2200,
    Interest_TileBucketSize = 50,
    Interest_AlwaysSendCombat = true,
    Interest_AlwaysSendHired = true,
    Interest_AlwaysSendBases = true,
    Interest_DebugLog = false,
    Flow_Enabled = true,
    Flow_StepRadiusBuckets = 2,
    Flow_MinScore = 1.4,
    Flow_CacheSeconds = 8,
    TacticalCost_Enabled = true,
    TacticalCost_SampleRadius = 7,
    TacticalCost_Samples = 12,
    TacticalCost_ThreatWeight = 1.4,
    TacticalCost_ZombieWeight = 0.7,
    TacticalCost_NoiseWeight = 0.25,
    GOAPLite_Enabled = true,
    GOAPLite_CooldownSeconds = 5,
    GOAPLite_MaxPlansPerTick = 4,
    FormationSlots_Enabled = true,
    FormationSlots_SlotSpacing = 1.55,
    FormationSlots_PersonalSpace = 1.05,
    FormationSlots_MaxSlots = 18,
    ProxyLOD_Enabled = true,
    ProxyLOD_BattleMultiplier = 1.0,
    ProxyLOD_MaxLossPerTick = 2,
    ProxyLOD_MoraleInfluence = true,

    Influence_Enabled = true,
    Influence_NumericKeys = true,
    Influence_AsyncMaintenance = true,
    Influence_BucketSize = 50,
    Influence_MaxCells = 1200,
    Influence_UpdateBucketsPerTick = 5,
    Influence_ProcessIntervalTicks = 6,
    Influence_DecayPerUpdate = 0.035,
    Influence_DiffusionRate = 0.08,
    Influence_SourceRadius = 140,
    Influence_UseForVirtualGroups = true,
    Influence_UseForBaseZones = true,
    Influence_UseForNPCUtility = true,
    Influence_DebugLog = false,

    World_OffscreenSpawnMinDistance = 48,
    World_OffscreenSpawnMaxDistance = 78,
    World_OffscreenSpawnSafePlayerRadius = 38,
    World_OffscreenSpawnSearchRadius = 9,
    World_NoNewGroupNearPlayerRadius = 700,
    World_VirtualMoveSpeedTilesPerHour = 120,
    World_VirtualTargetRadius = 300,
    World_RoadPatrolStepRadius = 260,
    World_RoadPatrolBattleRadius = 190,
    World_RoadPatrolBattleKeepRadius = 300,
    World_RoadPatrolBattleTickMinutes = 8.0,
    World_PreferredPointAttempts = 420,
    World_FallbackPointAttempts = 120,
    World_VirtualTargetAttempts = 80,

    Director_Enabled = true,
    Director_DryRun = true,
    Director_DebugLog = false,
    Director_MaxEvents = 80,
    Director_WorldMemoryCellSize = 150,
    Director_MaxMemoryCells = 700,
    Director_PressureDecay = 0.90,
    Director_PlayerTravelHeatDistance = 120,

    Base_Enabled = true,
    Base_MaxBases = 12,
    Base_Radius = 82,
    Base_MinDistance = 420,
    Base_SearchAttempts = 60,
    Base_CaptureHours = 0.75,
    Base_StatusWindowTimeoutSeconds = 8,
    Base_GroupTargetRadius = 900,
    Base_HomeAssignRadius = 220,
    Base_ZoneRebalanceMinutes = 25,

    Orders_FollowDistance = 4.0,
    Orders_GuardPlayerDistance = 5.5,
    Orders_HoldRadius = 2.5,
    Orders_GuardRadius = 10.0,
    Orders_PatrolRadius = 18.0,
    Orders_DefendRadius = 14.0,
    Orders_LootScanRadius = 12,
    Orders_FleeDistance = 9.0,
    Orders_KeepDistance = 4.0,
    Orders_SearchRadius = 12.0,
    Orders_TacticalRadioSearchRadius = 46.0,
    Orders_HumanizedSearchPauseTicks = 65,
    Orders_DefensiveShootDistance = 8,

    Utility_MemorySeconds = 120,
    Utility_AutonomyDelayMinutes = 2.1,
    Morale_LowHealthThreshold = 0.36,
    Morale_CriticalHealthThreshold = 0.22,
    Morale_FleeFearThreshold = 0.78,
    Morale_HoldMoraleThreshold = 0.42,
    Morale_ThreatFearMultiplier = 1.0,
    Morale_ThreatMoraleLossMultiplier = 1.0,

    Needs_Enabled = true,
    Needs_TickMinutes = 1.08,
    Needs_HungerLimit = 0.74,
    Needs_WaterLimit = 0.78,
    Needs_RestLimit = 0.82,
    Needs_BoredomLimit = 0.65,
    Needs_FoodRatePerHour = 0.030,
    Needs_WaterRatePerHour = 0.040,
    Needs_RestRatePerHour = 0.028,
    Needs_BoredomRatePerHour = 0.025,
    Needs_CombatNeedMultiplier = 1.8,
    Needs_CombatRestMultiplier = 2.1,

    Combat_MinimumGunDistance = 5.5,
    Combat_IdealGunDistance = 11.0,
    Combat_HoldFireCooldownSeconds = 2.0,
    Combat_ReturnFireSeconds = 8.0,
    Combat_DangerCloseDistance = 7.0,
    Combat_DefensiveDistance = 9.0,
    Combat_SuppressDistance = 32.0,

    Progression_MaxLevel = 30,
    Progression_MaxSkill = 10,
    Progression_XPMultiplier = 1.0,

    Loot_GlobalChanceMultiplier = 1.0,
}

local function bls_vars()
    local extKey = NPC_LEGACY_SETTINGS_SANDBOX.ext
    if SandboxVars and extKey and SandboxVars[extKey] then
        return SandboxVars[extKey]
    end
    return nil
end

local function bls_clamp(value, minValue, maxValue)
    if minValue ~= nil and value < minValue then return minValue end
    if maxValue ~= nil and value > maxValue then return maxValue end
    return value
end

function NPCLegacySettingsBridge.Get(name, defaultValue)
    local runtimeCache = NPCRuntimeCacheBridge or bls_legacyGlobal("RuntimeCache")
    if runtimeCache and runtimeCache.GetSetting then
        return runtimeCache.GetSetting(name, defaultValue, NPCLegacySettingsBridge.Defaults)
    end
    local vars = bls_vars()
    if vars and vars[name] ~= nil then return vars[name] end
    if NPCLegacySettingsBridge.Defaults[name] ~= nil then return NPCLegacySettingsBridge.Defaults[name] end
    return defaultValue
end

function NPCLegacySettingsBridge.GetNumber(name, defaultValue, minValue, maxValue)
    local value = tonumber(NPCLegacySettingsBridge.Get(name, defaultValue))
    if value == nil then value = tonumber(defaultValue) or 0 end
    return bls_clamp(value, minValue, maxValue)
end

function NPCLegacySettingsBridge.GetBool(name, defaultValue)
    local value = NPCLegacySettingsBridge.Get(name, defaultValue)
    if value == nil then return defaultValue == true end
    if value == true or value == 1 or value == "true" then return true end
    if value == false or value == 0 or value == "false" then return false end
    return defaultValue == true
end

function NPCLegacySettingsBridge.ApplyWorldDirector(director)
    if not director then return end
    director.STARTUP_GROUPS = NPCLegacySettingsBridge.GetNumber("World_InitialGroups", director.STARTUP_GROUPS, 0, 500)
    director.STARTUP_ROAD_PATROLS_RED = NPCLegacySettingsBridge.GetNumber("World_InitialRoadPatrolsRed", director.STARTUP_ROAD_PATROLS_RED, 0, 200)
    director.STARTUP_ROAD_PATROLS_GREEN = NPCLegacySettingsBridge.GetNumber("World_InitialRoadPatrolsGreen", director.STARTUP_ROAD_PATROLS_GREEN, 0, 200)
    director.STARTUP_ROAD_PATROL_ENCOUNTERS = NPCLegacySettingsBridge.GetNumber("World_PatrolEncounterPairs", director.STARTUP_ROAD_PATROL_ENCOUNTERS, 0, 200)
    director.MAX_ROAD_PATROLS = NPCLegacySettingsBridge.GetNumber("World_MaxRoadPatrols", director.MAX_ROAD_PATROLS, 0, 500)
    director.MAX_VIRTUAL_GROUPS = NPCLegacySettingsBridge.GetNumber("World_MaxVirtualGroups", director.MAX_VIRTUAL_GROUPS, 0, 2000)
    director.MAX_PHYSICAL_GROUPS = NPCLegacySettingsBridge.GetNumber("World_MaxPhysicalGroups", director.MAX_PHYSICAL_GROUPS, 1, 200)
    director.MAX_GROUP_ACTIVATIONS_PER_UPDATE = NPCLegacySettingsBridge.GetNumber("World_MaxGroupActivationsPerUpdate", director.MAX_GROUP_ACTIVATIONS_PER_UPDATE, 1, 50)
    director.MAX_GROUP_ACTIVATIONS_PER_PLAYER = NPCLegacySettingsBridge.GetNumber("World_MaxGroupActivationsPerPlayer", director.MAX_GROUP_ACTIVATIONS_PER_PLAYER, 1, 50)
    director.MAX_BATTLE_PAIR_ACTIVATIONS_PER_UPDATE = NPCLegacySettingsBridge.GetNumber("World_MaxBattlePairActivationsPerUpdate", director.MAX_BATTLE_PAIR_ACTIVATIONS_PER_UPDATE, 0, 50)
    director.TELEPORT_ACTIVATION_COOLDOWN_HOURS = NPCLegacySettingsBridge.GetNumber("World_TeleportActivationCooldownSeconds", (director.TELEPORT_ACTIVATION_COOLDOWN_HOURS or 0) * 3600, 0, 600) / 3600
    director.TELEPORT_DISTANCE_THRESHOLD = NPCLegacySettingsBridge.GetNumber("World_TeleportDistanceThreshold", director.TELEPORT_DISTANCE_THRESHOLD, 20, 5000)
    director.TELEPORT_MARKER_MATERIALIZE_RADIUS = NPCLegacySettingsBridge.GetNumber("World_TeleportMarkerMaterializeRadius", director.TELEPORT_MARKER_MATERIALIZE_RADIUS or 36, 4, 120)
    director.TELEPORT_MARKER_BYPASS_DEFERS = NPCLegacySettingsBridge.GetBool("World_TeleportMarkerBypassDefers", director.TELEPORT_MARKER_BYPASS_DEFERS ~= false)
    director.DEFER_ACTIVATION_WHEN_NPC_NEAR_PLAYER = NPCLegacySettingsBridge.GetBool("World_DeferActivationWhenNPCNearPlayer", director.DEFER_ACTIVATION_WHEN_NPC_NEAR_PLAYER)
    director.ACTIVATION_NPC_SOFT_CAP_PER_PLAYER = NPCLegacySettingsBridge.GetNumber("World_ActivationNPCSoftCapPerPlayer", director.ACTIVATION_NPC_SOFT_CAP_PER_PLAYER, 0, 500)
    director.PROXY_LOD_MAX_REAL_NPC_PER_PLAYER = NPCLegacySettingsBridge.GetNumber("LOD_MaxPhysicalNPCPerPlayer", director.PROXY_LOD_MAX_REAL_NPC_PER_PLAYER or 12, 1, 200)
    director.PROXY_LOD_MAX_REAL_NPC_HIGH = math.min(director.PROXY_LOD_MAX_REAL_NPC_PER_PLAYER, math.max(2, math.floor(director.PROXY_LOD_MAX_REAL_NPC_PER_PLAYER * 0.66)))
    director.PROXY_LOD_MAX_REAL_NPC_CRITICAL = math.min(director.PROXY_LOD_MAX_REAL_NPC_HIGH, math.max(2, math.floor(director.PROXY_LOD_MAX_REAL_NPC_PER_PLAYER * 0.42)))
    director.PROXY_LOD_MAX_REAL_NPC_GLOBAL = NPCLegacySettingsBridge.GetNumber("LOD_MaxPhysicalNPCGlobal", director.PROXY_LOD_MAX_REAL_NPC_GLOBAL or 28, 4, 400)
    if not NPCLegacySettingsBridge.GetBool("Perf_AllowHighPhysicalPopulation", true) then
        director.PROXY_LOD_MAX_REAL_NPC_PER_PLAYER = math.min(tonumber(director.PROXY_LOD_MAX_REAL_NPC_PER_PLAYER) or 16, 16)
        director.PROXY_LOD_MAX_REAL_NPC_HIGH = math.min(tonumber(director.PROXY_LOD_MAX_REAL_NPC_HIGH) or 10, 10)
        director.PROXY_LOD_MAX_REAL_NPC_CRITICAL = math.min(tonumber(director.PROXY_LOD_MAX_REAL_NPC_CRITICAL) or 6, 6)
        director.PROXY_LOD_MAX_REAL_NPC_GLOBAL = math.min(tonumber(director.PROXY_LOD_MAX_REAL_NPC_GLOBAL) or 40, 40)
    end
    director.DEFERRED_ACTIVATION_RETRY_HOURS = NPCLegacySettingsBridge.GetNumber("World_DeferredActivationRetryMinutes", (director.DEFERRED_ACTIVATION_RETRY_HOURS or 0.012) * 60, 0.1, 60) / 60
    director.MATERIALIZE_BATTLE_PAIR_AS_SINGLE_WAVE = NPCLegacySettingsBridge.GetBool("World_MaterializeBattlePairAsSingleWave", director.MATERIALIZE_BATTLE_PAIR_AS_SINGLE_WAVE)
    director.SPAWN_CHANCE_PER_TEN_MIN = NPCLegacySettingsBridge.GetNumber("World_SpawnChancePerTenMin", director.SPAWN_CHANCE_PER_TEN_MIN, 0, 100)
    director.PHYSICAL_DEACTIVATION_RADIUS = NPCLegacySettingsBridge.GetNumber("LOD_PhysicalDespawnRadius", director.PHYSICAL_DEACTIVATION_RADIUS, 120, 2000)
    director.PHYSICAL_REACTIVATION_RADIUS = NPCLegacySettingsBridge.GetNumber("LOD_PhysicalSpawnRadius", director.PHYSICAL_REACTIVATION_RADIUS, 40, director.PHYSICAL_DEACTIVATION_RADIUS)
    director.ACTIVATION_RADIUS = NPCLegacySettingsBridge.GetNumber("LOD_PhysicalSpawnRadius", director.ACTIVATION_RADIUS, 40, 1000)
    director.PHYSICAL_DEACTIVATION_HIGH_LOAD_RADIUS = NPCLegacySettingsBridge.GetNumber("LOD_PhysicalDespawnHighLoadRadius", director.PHYSICAL_DEACTIVATION_HIGH_LOAD_RADIUS or director.PHYSICAL_DEACTIVATION_RADIUS, director.ACTIVATION_RADIUS + 60, director.PHYSICAL_DEACTIVATION_RADIUS)
    director.PHYSICAL_DEACTIVATION_CRITICAL_RADIUS = NPCLegacySettingsBridge.GetNumber("LOD_PhysicalDespawnCriticalRadius", director.PHYSICAL_DEACTIVATION_CRITICAL_RADIUS or director.PHYSICAL_DEACTIVATION_HIGH_LOAD_RADIUS, director.ACTIVATION_RADIUS + 60, director.PHYSICAL_DEACTIVATION_RADIUS)
    director.PHYSICAL_DEACTIVATION_IMPORTANT_RADIUS = NPCLegacySettingsBridge.GetNumber("LOD_PhysicalDespawnImportantRadius", director.PHYSICAL_DEACTIVATION_IMPORTANT_RADIUS or director.PHYSICAL_DEACTIVATION_RADIUS, director.PHYSICAL_DEACTIVATION_RADIUS, 3000)
    director.PHYSICAL_DEACTIVATION_MIN_AGE_HOURS = NPCLegacySettingsBridge.GetNumber("LOD_PhysicalDespawnMinAgeSeconds", (director.PHYSICAL_DEACTIVATION_MIN_AGE_HOURS or 0) * 3600, 0, 600) / 3600
    director.PHYSICAL_CLEANUP_INTERVAL_TICKS = NPCLegacySettingsBridge.GetNumber("LOD_PhysicalCleanupIntervalTicks", director.PHYSICAL_CLEANUP_INTERVAL_TICKS or 1200, 60, 7200)
    director.PHYSICAL_CLEANUP_HIGH_INTERVAL_TICKS = NPCLegacySettingsBridge.GetNumber("LOD_PhysicalCleanupHighIntervalTicks", director.PHYSICAL_CLEANUP_HIGH_INTERVAL_TICKS or 600, 60, 7200)
    director.PHYSICAL_CLEANUP_CRITICAL_INTERVAL_TICKS = NPCLegacySettingsBridge.GetNumber("LOD_PhysicalCleanupCriticalIntervalTicks", director.PHYSICAL_CLEANUP_CRITICAL_INTERVAL_TICKS or 300, 60, 7200)
    if not NPCLegacySettingsBridge.GetBool("Perf_AllowHighPhysicalPopulation", true) then
        director.MAX_PHYSICAL_GROUPS = math.min(tonumber(director.MAX_PHYSICAL_GROUPS) or 6, 6)
        director.MAX_GROUP_ACTIVATIONS_PER_UPDATE = math.min(tonumber(director.MAX_GROUP_ACTIVATIONS_PER_UPDATE) or 2, 2)
        director.MAX_GROUP_ACTIVATIONS_PER_PLAYER = math.min(tonumber(director.MAX_GROUP_ACTIVATIONS_PER_PLAYER) or 2, 2)
        director.ACTIVATION_NPC_SOFT_CAP_PER_PLAYER = math.min(tonumber(director.ACTIVATION_NPC_SOFT_CAP_PER_PLAYER) or 18, 18)
        director.ACTIVATION_RADIUS = math.min(tonumber(director.ACTIVATION_RADIUS) or 150, 150)
        director.PHYSICAL_REACTIVATION_RADIUS = math.min(tonumber(director.PHYSICAL_REACTIVATION_RADIUS) or 150, 150)
        director.PHYSICAL_DEACTIVATION_RADIUS = math.min(tonumber(director.PHYSICAL_DEACTIVATION_RADIUS) or 420, 420)
        director.PHYSICAL_DEACTIVATION_HIGH_LOAD_RADIUS = math.min(tonumber(director.PHYSICAL_DEACTIVATION_HIGH_LOAD_RADIUS) or 320, 320)
        director.PHYSICAL_DEACTIVATION_CRITICAL_RADIUS = math.min(tonumber(director.PHYSICAL_DEACTIVATION_CRITICAL_RADIUS) or 260, 260)
        director.PHYSICAL_DEACTIVATION_IMPORTANT_RADIUS = math.min(tonumber(director.PHYSICAL_DEACTIVATION_IMPORTANT_RADIUS) or 620, 620)
        director.PHYSICAL_CLEANUP_INTERVAL_TICKS = math.min(tonumber(director.PHYSICAL_CLEANUP_INTERVAL_TICKS) or 300, 300)
        director.PHYSICAL_CLEANUP_HIGH_INTERVAL_TICKS = math.min(tonumber(director.PHYSICAL_CLEANUP_HIGH_INTERVAL_TICKS) or 90, 90)
        director.PHYSICAL_CLEANUP_CRITICAL_INTERVAL_TICKS = math.min(tonumber(director.PHYSICAL_CLEANUP_CRITICAL_INTERVAL_TICKS) or 30, 30)
    end
    director.URBAN_GROUP_ROAD_BIAS_RADIUS = NPCLegacySettingsBridge.GetNumber("World_UrbanSpawnRadius", director.URBAN_GROUP_ROAD_BIAS_RADIUS, 40, 2000)
    director.ROAD_PATROL_URBAN_BIAS_RADIUS = NPCLegacySettingsBridge.GetNumber("World_RoadPatrolUrbanRadius", director.ROAD_PATROL_URBAN_BIAS_RADIUS, 40, 2000)
    director.ROAD_PATROL_TARGET_RADIUS = NPCLegacySettingsBridge.GetNumber("World_PatrolTargetRadius", director.ROAD_PATROL_TARGET_RADIUS, 40, 2000)
    director.BATTLE_REMAINS_MATERIALIZE_ENABLED = NPCLegacySettingsBridge.GetBool("World_BattleRemainsMaterialize", director.BATTLE_REMAINS_MATERIALIZE_ENABLED == true)
    director.BATTLE_REMAINS_ACTIVATION_RADIUS = NPCLegacySettingsBridge.GetNumber("World_BattleRemainsActivationRadius", director.BATTLE_REMAINS_ACTIVATION_RADIUS, 8, 300)
    director.BATTLE_REMAINS_MAX_RECORDS = NPCLegacySettingsBridge.GetNumber("World_BattleRemainsMaxRecords", director.BATTLE_REMAINS_MAX_RECORDS, 0, 80)
    director.BATTLE_REMAINS_MAX_BODIES = NPCLegacySettingsBridge.GetNumber("World_BattleRemainsMaxBodies", director.BATTLE_REMAINS_MAX_BODIES, 0, 12)
    director.BATTLE_REMAINS_MAX_DEBRIS = NPCLegacySettingsBridge.GetNumber("World_BattleRemainsMaxDebris", director.BATTLE_REMAINS_MAX_DEBRIS or 2, 0, 24)
    director.BATTLE_REMAINS_MIN_SPACING = NPCLegacySettingsBridge.GetNumber("World_BattleRemainsMinSpacing", director.BATTLE_REMAINS_MIN_SPACING or 96, 16, 500)
    director.BATTLEFIELD_CLEANUP_ENABLED = NPCLegacySettingsBridge.GetBool("World_BattleRemainsCleanupEnabled", director.BATTLEFIELD_CLEANUP_ENABLED ~= false)
    director.BATTLEFIELD_CLEANUP_RADIUS = NPCLegacySettingsBridge.GetNumber("World_BattleRemainsCleanupRadius", director.BATTLEFIELD_CLEANUP_RADIUS or 42, 12, 120)
    director.BATTLEFIELD_CLEANUP_CORPSE_SOFT_CAP = NPCLegacySettingsBridge.GetNumber("World_BattleRemainsCleanupCorpseSoftCap", director.BATTLEFIELD_CLEANUP_CORPSE_SOFT_CAP or 18, 0, 120)
    director.BATTLEFIELD_CLEANUP_DEBRIS_SOFT_CAP = NPCLegacySettingsBridge.GetNumber("World_BattleRemainsCleanupDebrisSoftCap", director.BATTLEFIELD_CLEANUP_DEBRIS_SOFT_CAP or 24, 0, 180)
    director.URBAN_COVER_PROPS_ENABLED = NPCLegacySettingsBridge.GetBool("World_UrbanCoverPropsEnabled", director.URBAN_COVER_PROPS_ENABLED ~= false)
    director.URBAN_COVER_PROPS_RADIUS = NPCLegacySettingsBridge.GetNumber("World_UrbanCoverPropsRadius", director.URBAN_COVER_PROPS_RADIUS or 58, 12, 160)
    director.URBAN_COVER_PROPS_INTERVAL_TICKS = NPCLegacySettingsBridge.GetNumber("World_UrbanCoverPropsIntervalTicks", director.URBAN_COVER_PROPS_INTERVAL_TICKS or 900, 300, 7200)
    director.URBAN_COVER_PROPS_MAX_CLUSTERS_PER_RUN = NPCLegacySettingsBridge.GetNumber("World_UrbanCoverPropsMaxClustersPerRun", director.URBAN_COVER_PROPS_MAX_CLUSTERS_PER_RUN or 2, 0, 12)
    director.URBAN_COVER_PROPS_MAX_RECORDS = NPCLegacySettingsBridge.GetNumber("World_UrbanCoverPropsMaxRecords", director.URBAN_COVER_PROPS_MAX_RECORDS or 120, 0, 600)
    director.URBAN_COVER_PROPS_MIN_SPACING = NPCLegacySettingsBridge.GetNumber("World_UrbanCoverPropsMinSpacing", director.URBAN_COVER_PROPS_MIN_SPACING or 18, 6, 80)
    director.URBAN_COVER_PROPS_BUILDING_RADIUS = NPCLegacySettingsBridge.GetNumber("World_UrbanCoverPropsBuildingRadius", director.URBAN_COVER_PROPS_BUILDING_RADIUS or 7, 2, 16)
    director.URBAN_COVER_PROPS_ATTEMPTS_PER_PLAYER = NPCLegacySettingsBridge.GetNumber("World_UrbanCoverPropsAttemptsPerPlayer", director.URBAN_COVER_PROPS_ATTEMPTS_PER_PLAYER or 34, 6, 120)
    director.URBAN_COVER_PROPS_MAX_ITEMS_PER_CLUSTER = NPCLegacySettingsBridge.GetNumber("World_UrbanCoverPropsMaxItemsPerCluster", director.URBAN_COVER_PROPS_MAX_ITEMS_PER_CLUSTER or 4, 1, 8)
    if not NPCLegacySettingsBridge.GetBool("Perf_AllowHighPhysicalPopulation", true) then
        director.BATTLE_REMAINS_MATERIALIZE_ENABLED = true
        director.BATTLE_REMAINS_PROP_ONLY = true
        director.BATTLE_REMAINS_ACTIVATION_RADIUS = math.min(tonumber(director.BATTLE_REMAINS_ACTIVATION_RADIUS) or 70, 70)
        director.BATTLE_REMAINS_MAX_RECORDS = math.min(tonumber(director.BATTLE_REMAINS_MAX_RECORDS) or 12, 12)
        director.BATTLE_REMAINS_MAX_BODIES = math.min(tonumber(director.BATTLE_REMAINS_MAX_BODIES) or 2, 2)
        director.BATTLE_REMAINS_MAX_DEBRIS = math.min(math.max(tonumber(director.BATTLE_REMAINS_MAX_DEBRIS) or 8, 6), 8)
        director.BATTLE_REMAINS_MIN_SPACING = math.max(tonumber(director.BATTLE_REMAINS_MIN_SPACING) or 96, 96)
        director.URBAN_COVER_PROPS_RADIUS = math.min(tonumber(director.URBAN_COVER_PROPS_RADIUS) or 58, 58)
        director.URBAN_COVER_PROPS_INTERVAL_TICKS = math.max(tonumber(director.URBAN_COVER_PROPS_INTERVAL_TICKS) or 900, 900)
        director.URBAN_COVER_PROPS_MAX_CLUSTERS_PER_RUN = math.min(tonumber(director.URBAN_COVER_PROPS_MAX_CLUSTERS_PER_RUN) or 2, 2)
        director.URBAN_COVER_PROPS_MAX_RECORDS = math.min(tonumber(director.URBAN_COVER_PROPS_MAX_RECORDS) or 120, 120)
        director.URBAN_COVER_PROPS_MIN_SPACING = math.max(tonumber(director.URBAN_COVER_PROPS_MIN_SPACING) or 18, 18)
        director.URBAN_COVER_PROPS_MAX_ITEMS_PER_CLUSTER = math.min(tonumber(director.URBAN_COVER_PROPS_MAX_ITEMS_PER_CLUSTER) or 4, 4)
    end

    director.OFFSCREEN_SPAWN_MIN_DISTANCE = NPCLegacySettingsBridge.GetNumber("World_OffscreenSpawnMinDistance", director.OFFSCREEN_SPAWN_MIN_DISTANCE, 20, 300)
    director.OFFSCREEN_SPAWN_MAX_DISTANCE = NPCLegacySettingsBridge.GetNumber("World_OffscreenSpawnMaxDistance", director.OFFSCREEN_SPAWN_MAX_DISTANCE, director.OFFSCREEN_SPAWN_MIN_DISTANCE or 40, 500)
    director.OFFSCREEN_SPAWN_SAFE_PLAYER_RADIUS = NPCLegacySettingsBridge.GetNumber("World_OffscreenSpawnSafePlayerRadius", director.OFFSCREEN_SPAWN_SAFE_PLAYER_RADIUS, 5, 300)
    director.OFFSCREEN_SPAWN_SEARCH_RADIUS = NPCLegacySettingsBridge.GetNumber("World_OffscreenSpawnSearchRadius", director.OFFSCREEN_SPAWN_SEARCH_RADIUS, 1, 80)
    director.NO_NEW_GROUP_NEAR_PLAYER_RADIUS = NPCLegacySettingsBridge.GetNumber("World_NoNewGroupNearPlayerRadius", director.NO_NEW_GROUP_NEAR_PLAYER_RADIUS, 0, 5000)
    local virtualMoveSpeed = NPCLegacySettingsBridge.GetNumber("World_VirtualMoveSpeedTilesPerHour", director.VIRTUAL_MOVE_SPEED_TILES_PER_HOUR, 1, 30000)
    if tonumber(virtualMoveSpeed) == 1200 or tonumber(virtualMoveSpeed) == 30000 or tonumber(virtualMoveSpeed) > 1000 then virtualMoveSpeed = 120 end
    director.VIRTUAL_MOVE_SPEED_TILES_PER_HOUR = bls_clamp(tonumber(virtualMoveSpeed) or 120, 1, 1000)
    director.VIRTUAL_TARGET_RADIUS = NPCLegacySettingsBridge.GetNumber("World_VirtualTargetRadius", director.VIRTUAL_TARGET_RADIUS, 20, 2500)
    director.ROAD_PATROL_VIRTUAL_STEP_RADIUS = NPCLegacySettingsBridge.GetNumber("World_RoadPatrolStepRadius", director.ROAD_PATROL_VIRTUAL_STEP_RADIUS, 10, 1000)
    director.ROAD_PATROL_BATTLE_RADIUS = NPCLegacySettingsBridge.GetNumber("World_RoadPatrolBattleRadius", director.ROAD_PATROL_BATTLE_RADIUS, 10, 1000)
    director.ROAD_PATROL_BATTLE_KEEP_RADIUS = NPCLegacySettingsBridge.GetNumber("World_RoadPatrolBattleKeepRadius", director.ROAD_PATROL_BATTLE_KEEP_RADIUS, 20, 1500)
    director.ROAD_PATROL_BATTLE_TICK_HOURS = NPCLegacySettingsBridge.GetNumber("World_RoadPatrolBattleTickMinutes", (director.ROAD_PATROL_BATTLE_TICK_HOURS or 0.10) * 60, 1, 180) / 60
    director.PREFERRED_POINT_ATTEMPTS = NPCLegacySettingsBridge.GetNumber("World_PreferredPointAttempts", director.PREFERRED_POINT_ATTEMPTS, 10, 10000)
    director.FALLBACK_POINT_ATTEMPTS = NPCLegacySettingsBridge.GetNumber("World_FallbackPointAttempts", director.FALLBACK_POINT_ATTEMPTS, 10, 5000)
    director.VIRTUAL_TARGET_ATTEMPTS = NPCLegacySettingsBridge.GetNumber("World_VirtualTargetAttempts", director.VIRTUAL_TARGET_ATTEMPTS, 10, 5000)
end

function NPCLegacySettingsBridge.ApplyWorkScheduler(scheduler)
    if not scheduler or type(scheduler.DefaultBudget) ~= "table" then return end
    scheduler.DefaultBudget.ai = NPCLegacySettingsBridge.GetNumber("AIWork_MaxHeavyOpsPerTick", scheduler.DefaultBudget.ai, 1, 300)
    scheduler.DefaultBudget.combat = NPCLegacySettingsBridge.GetNumber("AIWork_CombatOpsPerTick", scheduler.DefaultBudget.combat, 1, 400)
    scheduler.DefaultBudget.utility = NPCLegacySettingsBridge.GetNumber("AIWork_UtilityOpsPerTick", scheduler.DefaultBudget.utility, 1, 300)
    scheduler.DefaultBudget.zombie = NPCLegacySettingsBridge.GetNumber("AIWork_ZombieOpsPerTick", scheduler.DefaultBudget.zombie, 1, 500)
    scheduler.DefaultBudget.marker = NPCLegacySettingsBridge.GetNumber("AIWork_MarkerOpsPerTick", scheduler.DefaultBudget.marker, 1, 500)
    scheduler.DefaultBudget.physical = NPCLegacySettingsBridge.GetNumber("AIWork_PhysicalOpsPerTick", scheduler.DefaultBudget.physical or 72, 1, 1000)
    scheduler.DefaultBudget.spawn = NPCLegacySettingsBridge.GetNumber("SpawnQueue_MaxPerTick", scheduler.DefaultBudget.spawn, 1, 100)
    scheduler.DefaultBudget.path = NPCLegacySettingsBridge.GetNumber("AIWork_PathOpsPerTick", scheduler.DefaultBudget.path or 10, 1, 300)
    scheduler.DefaultBudget.zombiePath = NPCLegacySettingsBridge.GetNumber("AIWork_ZombiePathOpsPerTick", scheduler.DefaultBudget.zombiePath or 8, 1, 300)
    scheduler.DefaultBudget.sense = NPCLegacySettingsBridge.GetNumber("AIWork_SenseOpsPerTick", scheduler.DefaultBudget.sense or 24, 1, 500)
    scheduler.DefaultBudget.los = NPCLegacySettingsBridge.GetNumber("AIWork_LOSOpsPerTick", scheduler.DefaultBudget.los or 36, 1, 800)
    if not NPCLegacySettingsBridge.GetBool("Perf_AllowHighPhysicalPopulation", true) then
        scheduler.DefaultBudget.ai = math.min(tonumber(scheduler.DefaultBudget.ai) or 10, 10)
        scheduler.DefaultBudget.combat = math.min(tonumber(scheduler.DefaultBudget.combat) or 14, 14)
        scheduler.DefaultBudget.utility = math.min(tonumber(scheduler.DefaultBudget.utility) or 8, 8)
        scheduler.DefaultBudget.zombie = math.min(tonumber(scheduler.DefaultBudget.zombie) or 8, 8)
        scheduler.DefaultBudget.marker = math.min(tonumber(scheduler.DefaultBudget.marker) or 18, 18)
        scheduler.DefaultBudget.physical = math.min(tonumber(scheduler.DefaultBudget.physical) or 8, 8)
        scheduler.DefaultBudget.path = math.min(tonumber(scheduler.DefaultBudget.path) or 2, 2)
        scheduler.DefaultBudget.zombiePath = math.min(tonumber(scheduler.DefaultBudget.zombiePath) or 2, 2)
        scheduler.DefaultBudget.sense = math.min(tonumber(scheduler.DefaultBudget.sense) or 6, 6)
        scheduler.DefaultBudget.los = math.min(tonumber(scheduler.DefaultBudget.los) or 8, 8)
    end
    if scheduler.ApplyAdaptiveSettings then scheduler.ApplyAdaptiveSettings() end
end

function NPCLegacySettingsBridge.ApplyAIVision(vision)
    if not vision or type(vision.Config) ~= "table" then return end
    vision.Config.playerVisionRange = NPCLegacySettingsBridge.GetNumber("Sense_ViewDistance", vision.Config.playerVisionRange, 1, 200)
    vision.Config.banditVisionRange = NPCLegacySettingsBridge.GetNumber("Sense_ViewDistance", vision.Config.banditVisionRange, 1, 200)
    vision.Config.zombieVisionRange = NPCLegacySettingsBridge.GetNumber("Sense_ZombieViewDistance", vision.Config.zombieVisionRange, 1, 200)
    vision.Config.hearingRange = NPCLegacySettingsBridge.GetNumber("Sense_HearingRadius", vision.Config.hearingRange, 0, 250)
    vision.Config.memorySeconds = NPCLegacySettingsBridge.GetNumber("Sense_MemorySeconds", vision.Config.memorySeconds, 0, 600)
    vision.Config.threatScanCooldownMs = NPCLegacySettingsBridge.GetNumber("Sense_ThreatScanCooldownMs", vision.Config.threatScanCooldownMs or 350, 50, 5000)
    vision.Config.maxThreatCandidatesPerScan = NPCLegacySettingsBridge.GetNumber("Sense_MaxThreatCandidatesPerScan", vision.Config.maxThreatCandidatesPerScan or 18, 1, 100)
    vision.Config.losCacheMs = NPCLegacySettingsBridge.GetNumber("Sense_LOSCacheMs", vision.Config.losCacheMs or 220, 0, 3000)
    vision.Config.losCacheMaxRecords = NPCLegacySettingsBridge.GetNumber("Sense_LOSCacheMaxRecords", vision.Config.losCacheMaxRecords or 360, 32, 5000)
end

function NPCLegacySettingsBridge.ApplyTacticalRadio(radio)
    if not radio or type(radio.Config) ~= "table" then return end
    radio.Config.enabled = NPCLegacySettingsBridge.GetBool("Radio_Enabled", radio.Config.enabled ~= false)
    radio.Config.contactMemorySeconds = NPCLegacySettingsBridge.GetNumber("Radio_MemorySeconds", radio.Config.contactMemorySeconds, 1, 1200)
    radio.Config.shareRange = NPCLegacySettingsBridge.GetNumber("Radio_Radius", radio.Config.shareRange, 1, 500)
    radio.Config.flankEnabled = NPCLegacySettingsBridge.GetBool("Radio_FlankEnabled", radio.Config.flankEnabled ~= false)
    radio.Config.flankSideDistance = NPCLegacySettingsBridge.GetNumber("Radio_FlankDistance", radio.Config.flankSideDistance, 1, 80)
    radio.Config.coverDistance = NPCLegacySettingsBridge.GetNumber("Radio_CoverDistance", radio.Config.coverDistance, 1, 80)
    radio.Config.overwatchDistance = NPCLegacySettingsBridge.GetNumber("Radio_OverwatchDistance", radio.Config.overwatchDistance, 1, 120)
    radio.Config.friendlyFireCheck = NPCLegacySettingsBridge.GetBool("Radio_FriendlyFireCheck", radio.Config.friendlyFireCheck ~= false)
end

function NPCLegacySettingsBridge.ApplyHealthRegen(health)
    if not health then return end
    health.DefaultMaxHealth = NPCLegacySettingsBridge.GetNumber("Health_MaxHealth", health.DefaultMaxHealth, 1, 20)
    health.MinSpawnHealth = NPCLegacySettingsBridge.GetNumber("Health_MaxHealth", health.MinSpawnHealth, 1, 20)
    health.HardMaxHealth = NPCLegacySettingsBridge.GetNumber("Health_HardMaxHealth", health.HardMaxHealth, health.DefaultMaxHealth, 30)
    health.RegenDelayMs = NPCLegacySettingsBridge.GetNumber("Health_RegenDelaySeconds", (health.RegenDelayMs or 0) / 1000, 0, 600) * 1000
    health.RegenRatePerSecond = NPCLegacySettingsBridge.GetNumber("Health_RegenPerSecond", health.RegenRatePerSecond, 0, 20)
    health.AutoRegenEnabled = NPCLegacySettingsBridge.GetBool("Health_AutoRegenEnabled", health.AutoRegenEnabled ~= false)
end

function NPCLegacySettingsBridge.ApplyNet(net)
    if not net then return end
    net.Enabled = NPCLegacySettingsBridge.GetBool("Net_DebugMapEnabled", net.Enabled ~= false)
    net.UseDebugMapCommands = NPCLegacySettingsBridge.GetBool("Net_DeltaSyncEnabled", net.UseDebugMapCommands ~= false)
    net.MarkerChunkSize = NPCLegacySettingsBridge.GetNumber("Net_SnapshotChunkSize", net.MarkerChunkSize, 8, 512)
    net.MaxMarkerUpdatesPerTick = NPCLegacySettingsBridge.GetNumber("Net_MaxMarkerEventsPerTick", net.MaxMarkerUpdatesPerTick, 1, 500)
    net.MaxMarkerRemovesPerTick = NPCLegacySettingsBridge.GetNumber("Net_MaxMarkerRemovesPerTick", net.MaxMarkerRemovesPerTick or net.MaxMarkerUpdatesPerTick, 1, 500)
    net.MaxPendingMarkerUpdates = NPCLegacySettingsBridge.GetNumber("Net_MaxPendingMarkerUpdates", net.MaxPendingMarkerUpdates or 1200, 64, 10000)
    net.MaxPendingMarkerRemoves = NPCLegacySettingsBridge.GetNumber("Net_MaxPendingMarkerRemoves", net.MaxPendingMarkerRemoves or 400, 32, 5000)
    net.MaxSnapshotChunksPerTick = NPCLegacySettingsBridge.GetNumber("Net_MaxSnapshotChunksPerTick", net.MaxSnapshotChunksPerTick or 2, 1, 64)
    net.MaxSnapshotMarkers = NPCLegacySettingsBridge.GetNumber("Net_MaxSnapshotMarkers", net.MaxSnapshotMarkers or 5000, 100, 20000)
    net.MaxSimStateUpdatesPerTick = NPCLegacySettingsBridge.GetNumber("Net_MaxSimStateUpdatesPerTick", net.MaxSimStateUpdatesPerTick or 18, 1, 500)
    net.QueuedSnapshotSync = NPCLegacySettingsBridge.GetBool("Net_QueuedSnapshotSync", net.QueuedSnapshotSync ~= false)
    net.SyncCooldownHours = NPCLegacySettingsBridge.GetNumber("Net_SyncCooldownSeconds", (net.SyncCooldownHours or 0) * 3600, 0, 120) / 3600
    net.PayloadSanitizer = NPCLegacySettingsBridge.GetBool("Net_PayloadSanitizer", net.PayloadSanitizer ~= false)
    net.MaxMarkerStringBytes = NPCLegacySettingsBridge.GetNumber("Net_MaxMarkerStringBytes", net.MaxMarkerStringBytes or 96, 16, 512)
    net.MaxMarkerTableEntries = NPCLegacySettingsBridge.GetNumber("Net_MaxMarkerTableEntries", net.MaxMarkerTableEntries or 24, 4, 128)
    net.MinMarkerIntervalHours = NPCLegacySettingsBridge.GetNumber("Net_NearMarkerUpdateSeconds", (net.MinMarkerIntervalHours or 0) * 3600, 0.1, 300) / 3600
    net.FarMarkerIntervalHours = NPCLegacySettingsBridge.GetNumber("Net_GlobalMarkerUpdateSeconds", (net.FarMarkerIntervalHours or 0) * 3600, 0.5, 600) / 3600
end

function NPCLegacySettingsBridge.ApplyPersistent(persistent)
    if not persistent then return end
    persistent.Enabled = NPCLegacySettingsBridge.GetBool("Persistent_Enabled", persistent.Enabled ~= false)
    persistent.MaxProfiles = NPCLegacySettingsBridge.GetNumber("Persistent_MaxProfiles", persistent.MaxProfiles or 500, 50, 10000)
    persistent.MaxInventoryLite = NPCLegacySettingsBridge.GetNumber("Persistent_MaxInventoryLite", persistent.MaxInventoryLite or 36, 0, 300)
end


function NPCLegacySettingsBridge.ApplyBrainDirector(director)
    if not director or type(director.Config) ~= "table" then return end
    director.Config.followDistance = NPCLegacySettingsBridge.GetNumber("Orders_FollowDistance", director.Config.followDistance, 1, 40)
    director.Config.guardPlayerDistance = NPCLegacySettingsBridge.GetNumber("Orders_GuardPlayerDistance", director.Config.guardPlayerDistance, 1, 60)
    director.Config.holdRadius = NPCLegacySettingsBridge.GetNumber("Orders_HoldRadius", director.Config.holdRadius, 0.5, 60)
    director.Config.guardRadius = NPCLegacySettingsBridge.GetNumber("Orders_GuardRadius", director.Config.guardRadius, 1, 200)
    director.Config.patrolRadius = NPCLegacySettingsBridge.GetNumber("Orders_PatrolRadius", director.Config.patrolRadius, 1, 300)
    director.Config.defendRadius = NPCLegacySettingsBridge.GetNumber("Orders_DefendRadius", director.Config.defendRadius, 1, 300)
    director.Config.lootScanRadius = NPCLegacySettingsBridge.GetNumber("Orders_LootScanRadius", director.Config.lootScanRadius, 1, 200)
    director.Config.fleeDistance = NPCLegacySettingsBridge.GetNumber("Orders_FleeDistance", director.Config.fleeDistance, 1, 200)
    director.Config.keepDistance = NPCLegacySettingsBridge.GetNumber("Orders_KeepDistance", director.Config.keepDistance, 0.5, 120)
    director.Config.searchRadius = NPCLegacySettingsBridge.GetNumber("Orders_SearchRadius", director.Config.searchRadius, 1, 200)
    director.Config.tacticalRadioSearchRadius = NPCLegacySettingsBridge.GetNumber("Orders_TacticalRadioSearchRadius", director.Config.tacticalRadioSearchRadius, 1, 500)
    director.Config.humanizedSearchPause = NPCLegacySettingsBridge.GetNumber("Orders_HumanizedSearchPauseTicks", director.Config.humanizedSearchPause, 1, 1800)
end

function NPCLegacySettingsBridge.ApplyOrders(orders)
    if not orders then return end
    orders.DefensiveShootDistance = NPCLegacySettingsBridge.GetNumber("Orders_DefensiveShootDistance", orders.DefensiveShootDistance or 8, 1, 120)
end

function NPCLegacySettingsBridge.ApplyUtilityAI(utility)
    if not utility then return end
    utility.Config = utility.Config or {}
    utility.Progression = utility.Progression or {}
    utility.Config.memorySeconds = NPCLegacySettingsBridge.GetNumber("Utility_MemorySeconds", utility.Config.memorySeconds or 120, 1, 3600)
    utility.Config.autonomyDelayHours = NPCLegacySettingsBridge.GetNumber("Utility_AutonomyDelayMinutes", (utility.Config.autonomyDelayHours or 0.035) * 60, 0, 1440) / 60
    utility.Config.lowHealth = NPCLegacySettingsBridge.GetNumber("Morale_LowHealthThreshold", utility.Config.lowHealth or 0.36, 0, 1)
    utility.Config.criticalHealth = NPCLegacySettingsBridge.GetNumber("Morale_CriticalHealthThreshold", utility.Config.criticalHealth or 0.22, 0, 1)
    utility.Config.fearFlee = NPCLegacySettingsBridge.GetNumber("Morale_FleeFearThreshold", utility.Config.fearFlee or 0.78, 0, 1)
    utility.Config.moraleHold = NPCLegacySettingsBridge.GetNumber("Morale_HoldMoraleThreshold", utility.Config.moraleHold or 0.42, 0, 1)
    utility.Config.threatFearMultiplier = NPCLegacySettingsBridge.GetNumber("Morale_ThreatFearMultiplier", utility.Config.threatFearMultiplier or 1.0, 0, 10)
    utility.Config.threatMoraleLossMultiplier = NPCLegacySettingsBridge.GetNumber("Morale_ThreatMoraleLossMultiplier", utility.Config.threatMoraleLossMultiplier or 1.0, 0, 10)
    utility.Config.needsEnabled = NPCLegacySettingsBridge.GetBool("Needs_Enabled", utility.Config.needsEnabled ~= false)
    utility.Config.needsTickHours = NPCLegacySettingsBridge.GetNumber("Needs_TickMinutes", (utility.Config.needsTickHours or 0.018) * 60, 0.05, 180) / 60
    utility.Config.hungerLimit = NPCLegacySettingsBridge.GetNumber("Needs_HungerLimit", utility.Config.hungerLimit or 0.74, 0, 1)
    utility.Config.waterLimit = NPCLegacySettingsBridge.GetNumber("Needs_WaterLimit", utility.Config.waterLimit or 0.78, 0, 1)
    utility.Config.restLimit = NPCLegacySettingsBridge.GetNumber("Needs_RestLimit", utility.Config.restLimit or 0.82, 0, 1)
    utility.Config.boredomLimit = NPCLegacySettingsBridge.GetNumber("Needs_BoredomLimit", utility.Config.boredomLimit or 0.65, 0, 1)
    utility.Config.foodRatePerHour = NPCLegacySettingsBridge.GetNumber("Needs_FoodRatePerHour", utility.Config.foodRatePerHour or 0.030, 0, 5)
    utility.Config.waterRatePerHour = NPCLegacySettingsBridge.GetNumber("Needs_WaterRatePerHour", utility.Config.waterRatePerHour or 0.040, 0, 5)
    utility.Config.restRatePerHour = NPCLegacySettingsBridge.GetNumber("Needs_RestRatePerHour", utility.Config.restRatePerHour or 0.028, 0, 5)
    utility.Config.boredomRatePerHour = NPCLegacySettingsBridge.GetNumber("Needs_BoredomRatePerHour", utility.Config.boredomRatePerHour or 0.025, -5, 5)
    utility.Config.combatNeedMultiplier = NPCLegacySettingsBridge.GetNumber("Needs_CombatNeedMultiplier", utility.Config.combatNeedMultiplier or 1.8, 0, 20)
    utility.Config.combatRestMultiplier = NPCLegacySettingsBridge.GetNumber("Needs_CombatRestMultiplier", utility.Config.combatRestMultiplier or 2.1, 0, 20)
    utility.Config.minimumGunDistance = NPCLegacySettingsBridge.GetNumber("Combat_MinimumGunDistance", utility.Config.minimumGunDistance or 5.5, 0.5, 200)
    utility.Config.idealGunDistance = NPCLegacySettingsBridge.GetNumber("Combat_IdealGunDistance", utility.Config.idealGunDistance or 11.0, 1, 300)
    utility.Config.holdFireCooldownSeconds = NPCLegacySettingsBridge.GetNumber("Combat_HoldFireCooldownSeconds", utility.Config.holdFireCooldownSeconds or 2.0, 0, 600)
    utility.Config.returnFireSeconds = NPCLegacySettingsBridge.GetNumber("Combat_ReturnFireSeconds", utility.Config.returnFireSeconds or 8.0, 0, 600)
    utility.Config.dangerCloseDistance = NPCLegacySettingsBridge.GetNumber("Combat_DangerCloseDistance", utility.Config.dangerCloseDistance or 7.0, 0.5, 200)
    utility.Config.defensiveDistance = NPCLegacySettingsBridge.GetNumber("Combat_DefensiveDistance", utility.Config.defensiveDistance or 9.0, 0.5, 300)
    utility.Config.suppressDistance = NPCLegacySettingsBridge.GetNumber("Combat_SuppressDistance", utility.Config.suppressDistance or 32.0, 1, 500)
    utility.Progression.maxLevel = NPCLegacySettingsBridge.GetNumber("Progression_MaxLevel", utility.Progression.maxLevel or 30, 1, 200)
    utility.Progression.maxSkill = NPCLegacySettingsBridge.GetNumber("Progression_MaxSkill", utility.Progression.maxSkill or 10, 1, 50)
    utility.Progression.xpMultiplier = NPCLegacySettingsBridge.GetNumber("Progression_XPMultiplier", utility.Progression.xpMultiplier or 1.0, 0, 100)
end

local function bls_applySettings(primary, fallback)
    if primary and primary.ApplySettings then primary.ApplySettings() end
    if fallback and fallback ~= primary and fallback.ApplySettings then fallback.ApplySettings() end
end

function NPCLegacySettingsBridge.ApplyRuntimeQueue()
    bls_applySettings(NPCRuntimeCacheBridge, bls_legacyGlobal("RuntimeCache"))
    bls_applySettings(NPCTaskQueueBridge, bls_legacyGlobal("TaskQueue"))
end

function NPCLegacySettingsBridge.ApplyOptimizationLayers()
    bls_applySettings(NPCAILODTraderBridge, bls_legacyGlobal("AILODTrader"))
    bls_applySettings(NPCBrainSchedulerBridge, bls_legacyGlobal("BrainScheduler"))
    bls_applySettings(NPCInterestManagerBridge, bls_legacyGlobal("InterestManager"))
    bls_applySettings(NPCFlowFieldBridge, bls_legacyGlobal("FlowField"))
    bls_applySettings(NPCTacticalCostFieldBridge, bls_legacyGlobal("TacticalCostField"))
    bls_applySettings(NPCNavigationPerformanceBridge, bls_legacyGlobal("NavigationPerformance"))
    bls_applySettings(NPCGOAPLiteBridge, bls_legacyGlobal("GOAPLite"))
    bls_applySettings(NPCFormationSlotsBridge, bls_legacyGlobal("FormationSlots"))
    bls_applySettings(NPCProxySimulationBridge, bls_legacyGlobal("ProxySimulation"))
end

function NPCLegacySettingsBridge.ApplyAll()
    if NPCWorldDirector then NPCLegacySettingsBridge.ApplyWorldDirector(NPCWorldDirector) end
    local legacyWorldDirector = bls_legacyGlobal("WorldDirector")
    if legacyWorldDirector and legacyWorldDirector ~= NPCWorldDirector then NPCLegacySettingsBridge.ApplyWorldDirector(legacyWorldDirector) end
    if NPCBrainDirector then NPCLegacySettingsBridge.ApplyBrainDirector(NPCBrainDirector) end
    local legacyBrainDirector = bls_legacyGlobal("BrainDirector")
    if legacyBrainDirector and legacyBrainDirector ~= NPCBrainDirector then NPCLegacySettingsBridge.ApplyBrainDirector(legacyBrainDirector) end
    if NPCOrderContract then NPCLegacySettingsBridge.ApplyOrders(NPCOrderContract) end
    local legacyOrders = bls_legacyGlobal("OrderContract")
    if legacyOrders and legacyOrders ~= NPCOrderContract then NPCLegacySettingsBridge.ApplyOrders(legacyOrders) end
    if NPCUtilityAIBridge then NPCLegacySettingsBridge.ApplyUtilityAI(NPCUtilityAIBridge) end
    local legacyUtilityAI = bls_legacyGlobal("UtilityAI")
    if legacyUtilityAI and legacyUtilityAI ~= NPCUtilityAIBridge then NPCLegacySettingsBridge.ApplyUtilityAI(legacyUtilityAI) end
    if NPCWorkSchedulerBridge then NPCLegacySettingsBridge.ApplyWorkScheduler(NPCWorkSchedulerBridge) end
    local legacyWorkScheduler = bls_legacyGlobal("WorkScheduler")
    if legacyWorkScheduler and legacyWorkScheduler ~= NPCWorkSchedulerBridge then NPCLegacySettingsBridge.ApplyWorkScheduler(legacyWorkScheduler) end
    if NPCAIVisionBridge then NPCLegacySettingsBridge.ApplyAIVision(NPCAIVisionBridge) end
    local legacyAIVision = bls_legacyGlobal("AIVision")
    if legacyAIVision and legacyAIVision ~= NPCAIVisionBridge then NPCLegacySettingsBridge.ApplyAIVision(legacyAIVision) end
    if NPCTacticalRadioBridge then NPCLegacySettingsBridge.ApplyTacticalRadio(NPCTacticalRadioBridge) end
    local legacyTacticalRadio = bls_legacyGlobal("TacticalRadio")
    if legacyTacticalRadio and legacyTacticalRadio ~= NPCTacticalRadioBridge then NPCLegacySettingsBridge.ApplyTacticalRadio(legacyTacticalRadio) end
    if NPCHealthRegenBridge then NPCLegacySettingsBridge.ApplyHealthRegen(NPCHealthRegenBridge) end
    local legacyHealthRegen = bls_legacyGlobal("HealthRegen")
    if legacyHealthRegen and legacyHealthRegen ~= NPCHealthRegenBridge then NPCLegacySettingsBridge.ApplyHealthRegen(legacyHealthRegen) end
    if NPCNetContract then NPCLegacySettingsBridge.ApplyNet(NPCNetContract) end
    local legacyNetContract = bls_legacyGlobal("NetContract")
    if legacyNetContract and legacyNetContract ~= NPCNetContract then NPCLegacySettingsBridge.ApplyNet(legacyNetContract) end
    if NPCPersistentNPCBridge then NPCLegacySettingsBridge.ApplyPersistent(NPCPersistentNPCBridge) end
    local legacyPersistentNPC = bls_legacyGlobal("PersistentNPC")
    if legacyPersistentNPC and legacyPersistentNPC ~= NPCPersistentNPCBridge then NPCLegacySettingsBridge.ApplyPersistent(legacyPersistentNPC) end
    if NPCLegacySettingsBridge.ApplyRuntimeQueue then NPCLegacySettingsBridge.ApplyRuntimeQueue() end
    bls_applySettings(NPCInfluenceFieldBridge, bls_legacyGlobal("InfluenceField"))
    if NPCLegacySettingsBridge.ApplyOptimizationLayers then NPCLegacySettingsBridge.ApplyOptimizationLayers() end
    bls_applySettings(NPCDirectorBrainServerBridge, bls_legacyGlobal("DirectorBrain"))
end

NPCLegacySettingsBridge.ApplyAll()
