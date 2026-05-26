-- NPCLootBridge.lua
-- Neutral shared backend for NPC death-loot pools.

require "NPCCore/NPCCompatibilityBridge"
require "NPCData/NPCLootRegistry"

-- Compatibility facade for the legacy global table.  The data itself lives in
-- NPCLootRegistry so future gameplay systems can consume neutral loot profiles
-- without depending on this file's historical name.
NPCLootBridge = NPCLootBridge or {}

NPCLootBridge.MakeItem = function(name, chance, quantity)
    return NPCLootRegistry.MakeEntry(name, chance, quantity)
end

NPCLootBridge.FillContainer = function(container, itemTab, itemNo)
    return NPCLootRegistry.RollAndFill(container, itemTab, itemNo)
end

local function append(target, specs)
    return NPCLootRegistry.AppendEntries(target, specs, NPCLootBridge.MakeItem)
end

local function shouldUseLegacySmokes()
    return NPCLootRegistry.GetGameVersion() < 42 and not NPCLootRegistry.HasMod("Smoker")
end

local function shouldUseBuild42Food()
    return NPCLootRegistry.GetGameVersion() >= 42
end

local function shouldUseFirearmsAmmo()
    return NPCLootRegistry.HasMod("firearmmod") or NPCLootRegistry.HasMod("firearmmodRevamp")
end

NPCLootBridge.Items = NPCLootBridge.Items or {}
append(NPCLootBridge.Items, NPCLootRegistry.InventoryCarryItems)
if shouldUseLegacySmokes() then
    append(NPCLootBridge.Items, NPCLootRegistry.InventoryLegacySmokes)
end
append(NPCLootBridge.Items, NPCLootRegistry.InventoryFoodItems)
if shouldUseBuild42Food() then
    append(NPCLootBridge.Items, NPCLootRegistry.InventoryBuild42Food)
end
append(NPCLootBridge.Items, NPCLootRegistry.InventoryValuables)

NPCLootBridge.FreshFoodItems = NPCLootBridge.FreshFoodItems or {}
append(NPCLootBridge.FreshFoodItems, NPCLootRegistry.FreshFoodItems)

NPCLootBridge.CannedFoodItems = NPCLootBridge.CannedFoodItems or {}
append(NPCLootBridge.CannedFoodItems, NPCLootRegistry.CannedFoodItems)

NPCLootBridge.Ammo = NPCLootBridge.Ammo or {}
append(NPCLootBridge.Ammo, NPCLootRegistry.StandardAmmo)
if shouldUseFirearmsAmmo() then
    append(NPCLootBridge.Ammo, NPCLootRegistry.FirearmsAmmo)
end
if NPCLootRegistry.HasMod("Guns93") then
    append(NPCLootBridge.Ammo, NPCLootRegistry.Guns93Ammo)
end
