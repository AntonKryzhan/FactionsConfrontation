require "NPCCore/NPCCompatibilityBridge"
require "NPCBehavior/NPCProgramHelpersBridge"
require "NPCBehavior/NPCProgramWeaponBridge"
require "NPCBehavior/NPCProgramContainerBridge"
require "NPCBehavior/NPCProgramGeneratorBridge"
require "NPCBehavior/NPCProgramFarmBridge"
require "NPCBehavior/NPCProgramHousekeepingBridge"
require "NPCBehavior/NPCProgramMiscBridge"
require "NPCBehavior/NPCProgramSelfBridge"
NPCPrograms = NPCPrograms or {}

NPCPrograms.Weapon = NPCPrograms.Weapon or {}

NPCPrograms.Weapon.Switch = function(bandit, itemName)
    return NPCProgramWeaponBridge.Switch(bandit, itemName)
end

NPCPrograms.Weapon.Aim = function(bandit, enemyCharacter, slot)
    return NPCProgramWeaponBridge.Aim(bandit, enemyCharacter, slot)
end

NPCPrograms.Weapon.Shoot = function(bandit, enemyCharacter, slot)
    return NPCProgramWeaponBridge.Shoot(bandit, enemyCharacter, slot)
end

NPCPrograms.Weapon.Reload = function(bandit, slot)
    return NPCProgramWeaponBridge.Reload(bandit, slot)
end

NPCPrograms.Idle = function(bandit)
    return NPCProgramSelfBridge.Idle(bandit)
end 

NPCPrograms.Container = NPCPrograms.Container or {}

NPCPrograms.Container.WeaponLoot = function(bandit, object, container)
    return NPCProgramContainerBridge.WeaponLoot(bandit, object, container)
end

NPCPrograms.Container.Loot = function(bandit, object, container)
    return NPCProgramContainerBridge.Loot(bandit, object, container)
end

NPCPrograms.Generator = NPCPrograms.Generator or {}

NPCPrograms.Generator.Refuel = function(bandit, generator)
    return NPCProgramGeneratorBridge.Refuel(bandit, generator)
end

NPCPrograms.Generator.Repair = function(bandit, generator)
    return NPCProgramGeneratorBridge.Repair(bandit, generator)
end

NPCPrograms.Farm = NPCPrograms.Farm or {}
NPCProgramFarmBridge.ApplyDefaults(NPCPrograms.Farm)

NPCPrograms.Farm.PredicateFillable = function(item)
    return NPCProgramFarmBridge.PredicateFillable(item)
end

NPCPrograms.Farm.Water = function(bandit, plant)
    return NPCProgramFarmBridge.Water(bandit, plant)
end

NPCPrograms.Farm.Heal = function(bandit)
    return NPCProgramFarmBridge.Heal(bandit)
end

NPCPrograms.Housekeeping = NPCPrograms.Housekeeping or {}
NPCProgramHousekeepingBridge.ApplyDefaults(NPCPrograms.Housekeeping)

NPCPrograms.Housekeeping.PredicateTrash = function(item)
    return NPCProgramHousekeepingBridge.PredicateTrash(item)
end

NPCPrograms.Housekeeping.CleanBlood = function(bandit)
    return NPCProgramHousekeepingBridge.CleanBlood(bandit)
end

NPCPrograms.Housekeeping.RemoveTrash = function(bandit)
    return NPCProgramHousekeepingBridge.RemoveTrash(bandit)
end

NPCPrograms.Housekeeping.FillGraves = function(bandit)
    return NPCProgramHousekeepingBridge.FillGraves(bandit)
end

NPCPrograms.Housekeeping.RemoveCorpses = function(bandit)
    return NPCProgramHousekeepingBridge.RemoveCorpses(bandit)
end

NPCPrograms.Misc = NPCPrograms.Misc or {}

NPCPrograms.Misc.ReturnFood = function(bandit)
    return NPCProgramMiscBridge.ReturnFood(bandit)
end

NPCPrograms.Self = NPCPrograms.Self or {}

NPCPrograms.Self.Wash = function(bandit)
    return NPCProgramSelfBridge.Wash(bandit)
end