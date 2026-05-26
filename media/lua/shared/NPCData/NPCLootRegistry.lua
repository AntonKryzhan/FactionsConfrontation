require "NPCCore/NPCCompatibilityBridge"
require "NPCCore/NPCLegacySettingsBridge"
NPCLootRegistry = NPCLootRegistry or {}
local Registry = NPCLootRegistry

local function getModSet()
    if getActivatedMods then
        return getActivatedMods()
    end
    return nil
end

function Registry.HasMod(modId)
    local mods = getModSet()
    return mods and modId and mods:contains(modId) or false
end

function Registry.GetGameVersion()
    if NPCCompatibilityBridge and NPCCompatibilityBridge.GetGameVersion then
        return NPCCompatibilityBridge.GetGameVersion()
    end
    return 41
end

function Registry.ResolveItemName(name)
    if NPCCompatibilityBridge and NPCCompatibilityBridge.GetLegacyItem then
        return NPCCompatibilityBridge.GetLegacyItem(name)
    end
    return name
end

function Registry.GetChanceMultiplier()
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        return NPCLegacySettingsBridge.GetNumber("Loot_GlobalChanceMultiplier", 1.0, 0.0, 5.0)
    end
    return 1.0
end

function Registry.ClampPercent(value)
    local number = tonumber(value) or 0
    if number < 0 then return 0 end
    if number > 100 then return 100 end
    return number
end

function Registry.MakeEntry(name, chance, quantity)
    local entry = {
        name = Registry.ResolveItemName(name),
        chance = Registry.ClampPercent((tonumber(chance) or 0) * Registry.GetChanceMultiplier())
    }
    if quantity ~= nil then
        entry.quantity = quantity
    end
    return entry
end

function Registry.AppendEntries(target, specs, makeEntry)
    if not target or not specs then return target end
    local builder = makeEntry or Registry.MakeEntry
    for i = 1, #specs do
        local spec = specs[i]
        target[#target + 1] = builder(spec[1], spec[2], spec[3])
    end
    return target
end

function Registry.AddRolledItem(container, itemName)
    if not container or not itemName then return nil end
    if not container.AddItem then return nil end
    local item = container:AddItem(itemName)
    if item and container.addItemOnServer then
        container:addItemOnServer(item)
    end
    return item
end

function Registry.RollAndFill(container, entries, rollLimit)
    if not container or not entries then return 0 end
    local maxRoll = tonumber(rollLimit) or 1
    if maxRoll < 1 then maxRoll = 1 end
    local added = 0
    for i = 1, #entries do
        local entry = entries[i]
        if entry and entry.name and (ZombRand(101) <= (tonumber(entry.chance) or 0)) then
            local quantityRoll = ZombRand(maxRoll)
            for n = 0, quantityRoll do
                if Registry.AddRolledItem(container, entry.name) then
                    added = added + 1
                end
            end
        end
    end
    return added
end

Registry.InventoryCarryItems = {
    {"Base.WaterBottle", 80},
    {"Base.HandTorch", 100},
    {"Base.TinOpener", 11},
    {"Base.Hammer", 20},
    {"Base.Wrench", 20},
    {"Base.PipeWrench", 10},
    {"Base.Scissors", 10},
    {"Base.Screwdriver", 22},
    {"Base.Spoon", 40},
    {"Base.Pencil", 35},
    {"Base.WeldingMask", 2},
    {"Base.BlowTorch", 2},
    {"Base.Needle", 5},
    {"Base.Soap", 8},
    {"Base.Molotov", 1},
    {"Base.PipeBomb", 1},
    {"Base.Bandage", 21},
    {"Base.Pills", 9},
    {"Base.Lighter", 21},
    {"Base.HolsterSimple", 11},
}

Registry.InventoryLegacySmokes = {
    {"Base.Cigarettes", 33},
    {"Base.Cigarettes", 33},
    {"Base.Cigarettes", 33},
    {"Base.Cigarettes", 33},
    {"Base.Cigarettes", 33},
    {"Base.Cigarettes", 33},
}

Registry.InventoryFoodItems = {
    {"Base.TinnedBeans", 1},
    {"Base.CannedCarrots2", 1},
    {"Base.CannedChili", 1},
    {"Base.CannedCorn", 1},
    {"Base.CannedCornedBeef", 1},
    {"Base.CannedFruitCocktail", 1},
    {"Base.CannedMushroomSoup", 1},
    {"Base.CannedPeaches", 1},
    {"Base.CannedPeas", 1},
    {"Base.CannedPineapple", 1},
    {"Base.CannedPotato2", 1},
    {"Base.CannedSardines", 1},
    {"Base.TinnedSoup", 1},
    {"Base.CannedBolognese", 1},
    {"Base.CannedTomato2", 1},
    {"Base.TunaTin", 1},
    {"Base.Salami", 1},
    {"Base.Apple", 2},
    {"Base.Pear", 2},
    {"Base.Cherry", 1},
    {"Base.Grapes", 1},
    {"Base.Onion", 1},
    {"Base.MushroomGeneric1", 1},
    {"Base.MushroomGeneric2", 1},
    {"Base.RedRadish", 1},
    {"Base.Potato", 1},
    {"Base.Cabbage", 1},
    {"Base.CannedBroccoli", 1},
    {"Base.CannedCabbage", 1},
    {"Base.CannedCarrots", 1},
    {"Base.CannedPotato", 1},
    {"Base.CannedTomato", 1},
    {"Base.CannedEggplant", 1},
    {"Base.CannedBellPepper", 1},
    {"Base.BeerCan", 2},
    {"Base.Whiskey", 3},
    {"Base.JamFruit", 1},
    {"Base.Coffee2", 4},
    {"Base.Teabag2", 4},
    {"Base.Gum", 2},
    {"Base.Peppermint", 1},
    {"Base.GummyWorms", 1},
    {"Base.Jujubes", 1},
    {"Base.HiHis", 1},
    {"Base.CandyFruitSlices", 1},
    {"Base.Crisps", 1},
    {"Base.Crisps2", 1},
    {"Base.Crisps3", 1},
}

Registry.InventoryBuild42Food = {
    {"Base.Crisps4", 1},
}

Registry.InventoryValuables = {
    {"Base.PetrolCan", 1},
}

Registry.FreshFoodItems = {
    {"Base.RedRadish", 15},
    {"Base.Potato", 45},
    {"Base.Leek", 25},
    {"Base.Onion", 25},
    {"Base.Cabbage", 25},
    {"Base.Broccoli", 15},
    {"Base.BellPepper", 10},
    {"Base.Lettuce", 10},
    {"Base.Pumpkin", 8},
    {"Base.Tomato", 31},
    {"Base.Jalapeno", 10},
    {"Base.Eggplant", 5},
    {"Base.Avocado", 10},
    {"Base.Mango", 7},
    {"Base.MushroomGeneric3", 20},
    {"Base.Apple", 15},
    {"Base.Grapefruit", 15},
    {"Base.Grapes", 18},
    {"Base.Pear", 21},
    {"Base.Banana", 15},
    {"Base.Rabbitmeat", 40},
    {"Base.FrogMeat", 10},
    {"Base.Steak", 5},
    {"Base.MeatPatty", 7},
    {"Base.MuttonChop", 7},
    {"Base.Egg", 20},
    {"Base.Milk", 22},
    {"Base.Cheese", 75},
    {"Base.Yoghurt", 9},
    {"Base.Butter", 44},
    {"Base.BeerBottle", 66},
    {"Base.Wine", 18},
}

Registry.CannedFoodItems = {
    {"Base.TinnedBeans", 10},
    {"Base.CannedCarrots2", 10},
    {"Base.CannedChili", 10},
    {"Base.CannedCorn", 10},
    {"Base.CannedCornedBeef", 10},
    {"Base.CannedFruitCocktail", 10},
    {"Base.CannedMushroomSoup", 10},
    {"Base.CannedPeaches", 10},
    {"Base.CannedPeas", 10},
    {"Base.CannedPineapple", 10},
    {"Base.CannedPotato2", 10},
    {"Base.CannedSardines", 10},
    {"Base.TinnedSoup", 10},
    {"Base.CannedBolognese", 10},
    {"Base.CannedTomato2", 10},
    {"Base.TunaTin", 10},
    {"Base.CannedBroccoli", 10},
    {"Base.CannedCabbage", 10},
    {"Base.CannedCarrots", 10},
    {"Base.CannedPotato", 10},
    {"Base.CannedTomato", 10},
    {"Base.CannedEggplant", 10},
    {"Base.CannedBellPepper", 10},
}

Registry.StandardAmmo = {
    {"Base.223Box", 5},
    {"Base.308Box", 9},
    {"Base.Bullets38Box", 10},
    {"Base.Bullets44Box", 13},
    {"Base.Bullets45Box", 10},
    {"Base.556Box", 11},
    {"Base.Bullets9mmBox", 11},
    {"Base.ShotgunShellsBox", 8},
}

Registry.FirearmsAmmo = {
    {"Base.Bullets4440Box", 5},
    {"Base.Bullets357Box", 5},
    {"Base.762x51Box", 5},
    {"Base.762x39Box", 5},
    {"Base.Bullets22Box", 5},
    {"Base.Bullets3006Box", 5},
}

Registry.Guns93Ammo = {
    {"Base.3006Box", 4},
    {"Base.792Box", 4},
    {"Base.30CarBox", 4},
    {"Base.76239Box", 4},
    {"Base.3030Box", 4},
    {"Base.22Box", 4},
    {"Base.25Box", 4},
    {"Base.380Box", 4},
    {"Base.45LCBox", 4},
    {"Base.357Box", 4},
    {"Base.10mmBox", 4},
    {"Base.SlugBox", 4},
    {"Base.40Box", 4},
    {"Base.Bullets38Box", 4},
}

