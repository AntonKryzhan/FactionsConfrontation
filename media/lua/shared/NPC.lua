require "NPCCore/NPCEntityState"
require "NPCCore/NPCLegacyGlobalsBridge"
pcall(require, "NPCCore/NPCActionRouterBridge")

NPCEntity = NPCLegacyGlobalsBridge.InstallAlias("Entity", NPCEntity, "NPCEntity")

-- Compatibility facade for the historical global table.
-- Implementation lives in NPCEntityState so newer systems can call neutral
-- entity-state contracts while existing gameplay keeps the same API.

NPCEntity.SoundTab = NPCEntityState.SoundTab
NPCEntity.SoundStopList = NPCEntityState.SoundStopList
NPCEntity.VisualDamage = NPCEntityState.VisualDamage
NPCEntity.Engine = NPCEntityState.Engine

function NPCEntity.ForceSyncPart(...)
    return NPCEntityState.ForceSyncPart(...)
end

function NPCEntity.AddTask(...)
    return NPCEntityState.AddTask(...)
end

function NPCEntity.AddTaskFirst(...)
    return NPCEntityState.AddTaskFirst(...)
end

function NPCEntity.GetTask(...)
    return NPCEntityState.GetTask(...)
end

function NPCEntity.HasTask(...)
    return NPCEntityState.HasTask(...)
end

function NPCEntity.HasTaskType(...)
    return NPCEntityState.HasTaskType(...)
end

function NPCEntity.HasMoveTask(...)
    return NPCEntityState.HasMoveTask(...)
end

function NPCEntity.HasActionTask(...)
    return NPCEntityState.HasActionTask(...)
end

function NPCEntity.UpdateTask(...)
    return NPCEntityState.UpdateTask(...)
end

function NPCEntity.RemoveTask(...)
    return NPCEntityState.RemoveTask(...)
end

function NPCEntity.ClearTasks(...)
    return NPCEntityState.ClearTasks(...)
end

function NPCEntity.ClearMoveTasks(...)
    return NPCEntityState.ClearMoveTasks(...)
end

function NPCEntity.ClearOtherTasks(...)
    return NPCEntityState.ClearOtherTasks(...)
end

function NPCEntity.UpdateEndurance(...)
    return NPCEntityState.UpdateEndurance(...)
end

function NPCEntity.GetInfection(...)
    return NPCEntityState.GetInfection(...)
end

function NPCEntity.UpdateInfection(...)
    return NPCEntityState.UpdateInfection(...)
end

function NPCEntity.ForceStationary(...)
    return NPCEntityState.ForceStationary(...)
end

function NPCEntity.IsForceStationary(...)
    return NPCEntityState.IsForceStationary(...)
end

function NPCEntity.SetNearFire(...)
    return NPCEntityState.SetNearFire(...)
end

function NPCEntity.IsNearFire(...)
    return NPCEntityState.IsNearFire(...)
end

function NPCEntity.SetSleeping(...)
    return NPCEntityState.SetSleeping(...)
end

function NPCEntity.IsSleeping(...)
    return NPCEntityState.IsSleeping(...)
end

function NPCEntity.SetAim(...)
    return NPCEntityState.SetAim(...)
end

function NPCEntity.IsAim(...)
    return NPCEntityState.IsAim(...)
end

function NPCEntity.SetMoving(...)
    return NPCEntityState.SetMoving(...)
end

function NPCEntity.IsMoving(...)
    return NPCEntityState.IsMoving(...)
end

function NPCEntity.SetCapabilities(...)
    return NPCEntityState.SetCapabilities(...)
end

function NPCEntity.Can(...)
    return NPCEntityState.Can(...)
end

function NPCEntity.IsDNA(...)
    return NPCEntityState.IsDNA(...)
end

function NPCEntity.GetMaster(...)
    return NPCEntityState.GetMaster(...)
end

function NPCEntity.SetMaster(...)
    return NPCEntityState.SetMaster(...)
end

function NPCEntity.GetProgram(...)
    return NPCEntityState.GetProgram(...)
end

function NPCEntity.SetProgram(...)
    return NPCEntityState.SetProgram(...)
end

function NPCEntity.SetProgramStage(...)
    return NPCEntityState.SetProgramStage(...)
end

function NPCEntity.SetHostile(...)
    return NPCEntityState.SetHostile(...)
end

function NPCEntity.IsHostile(...)
    return NPCEntityState.IsHostile(...)
end

function NPCEntity.GetWeapons(...)
    return NPCEntityState.GetWeapons(...)
end

function NPCEntity.GetBestWeapon(...)
    return NPCEntityState.GetBestWeapon(...)
end

function NPCEntity.IsOutOfAmmo(...)
    return NPCEntityState.IsOutOfAmmo(...)
end

function NPCEntity.SetWeapons(...)
    return NPCEntityState.SetWeapons(...)
end

function NPCEntity.SetInventory(...)
    return NPCEntityState.SetInventory(...)
end

function NPCEntity.Has(...)
    return NPCEntityState.Has(...)
end

function NPCEntity.SetLoot(...)
    return NPCEntityState.SetLoot(...)
end

function NPCEntity.AddLoot(...)
    return NPCEntityState.AddLoot(...)
end

function NPCEntity.UpdateItemsToSpawnAtDeath(...)
    return NPCEntityState.UpdateItemsToSpawnAtDeath(...)
end

function NPCEntity.SurpressZombieSounds(...)
    return NPCEntityState.SurpressZombieSounds(...)
end

function NPCEntity.PickVoice(...)
    return NPCEntityState.PickVoice(...)
end

function NPCEntity.Say(...)
    return NPCEntityState.Say(...)
end

function NPCEntity.AddVisualDamage(...)
    return NPCEntityState.AddVisualDamage(...)
end
