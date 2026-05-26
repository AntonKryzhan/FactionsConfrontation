require "NPCClient/NPCSchedulerBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCScheduler = NPCLegacyGlobalsBridge.InstallAlias("Scheduler", NPCScheduler, "NPCScheduler")

NPCScheduler.DaysSinceApo = NPCSchedulerBridge.DaysSinceApo
NPCScheduler.GetWaveDataAll = NPCSchedulerBridge.GetWaveDataAll
NPCScheduler.GetWaveDataForDay = NPCSchedulerBridge.GetWaveDataForDay
NPCScheduler.GenerateSpawnPoint = NPCSchedulerBridge.GenerateSpawnPoint
NPCScheduler.SpawnWave = NPCSchedulerBridge.SpawnWave
NPCScheduler.RaiseDefences = NPCSchedulerBridge.RaiseDefences
NPCScheduler.GenerateSpawnPointsInRandomBuilding = NPCSchedulerBridge.GenerateSpawnPointsInRandomBuilding
NPCScheduler.GetDensityScore = NPCSchedulerBridge.GetDensityScore
NPCScheduler.GetSpawnZoneBoost = NPCSchedulerBridge.GetSpawnZoneBoost
NPCScheduler.SpawnDefenders = NPCSchedulerBridge.SpawnDefenders
NPCScheduler.SpawnBase = NPCSchedulerBridge.SpawnBase
NPCScheduler.BroadcastTV = NPCSchedulerBridge.BroadcastTV
NPCScheduler.CheckEvent = NPCSchedulerBridge.CheckEvent

NPCSchedulerBridge.Install()
