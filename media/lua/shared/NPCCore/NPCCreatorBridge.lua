-- NPCCreatorBridge.lua
-- Neutral shared backend for NPC brain/loadout creation.

NPCCreatorBridge = NPCCreatorBridge or {}

require "NPCData/NPCCivilianArchetypesBridge"

local NPC_APPEARANCE_STYLE_KITS = {
    leader = {
        backpackChance = 82,
        backpacks = {"Base.Bag_ALICEpack_Army", "Base.Bag_Satchel"},
        headChance = 68,
        heads = {"Base.Hat_Army", "Base.Hat_ArmyHelmet"},
        torsoChance = 90,
        torsos = {"Base.HolsterDouble", "Base.Vest_BulletArmy", "Base.Vest_BulletPolice"},
        handChance = 36,
        hands = {"Base.Gloves_LeatherGlovesBlack"}
    },
    mercenary = {
        backpackChance = 74,
        backpacks = {"Base.Bag_ALICEpack_Army", "Base.Bag_Satchel"},
        headChance = 56,
        heads = {"Base.Hat_Army", "Base.Hat_ArmyHelmet"},
        torsoChance = 82,
        torsos = {"Base.HolsterDouble", "Base.Vest_BulletArmy"},
        handChance = 34,
        hands = {"Base.Gloves_LeatherGlovesBlack"}
    },
    militia = {
        backpackChance = 58,
        backpacks = {"Base.Bag_ALICEpack_Army", "Base.Bag_Satchel"},
        headChance = 48,
        heads = {"Base.Hat_Army", "Base.Hat_ArmyHelmet"},
        torsoChance = 72,
        torsos = {"Base.HolsterSimple", "Base.Vest_BulletArmy", "Base.Vest_BulletPolice"},
        handChance = 28,
        hands = {"Base.Gloves_LeatherGlovesBlack"}
    },
    checkpoint = {
        backpackChance = 26,
        backpacks = {"Base.Bag_Satchel"},
        headChance = 72,
        heads = {"Base.Hat_Army", "Base.Hat_ArmyHelmet"},
        torsoChance = 86,
        torsos = {"Base.Vest_BulletPolice", "Base.HolsterSimple", "Base.Vest_BulletArmy"},
        handChance = 30,
        hands = {"Base.Gloves_LeatherGlovesBlack"}
    },
    scout = {
        backpackChance = 68,
        backpacks = {"Base.Bag_Satchel", "Base.Bag_ALICEpack_Army"},
        headChance = 30,
        heads = {"Base.Hat_Army"},
        torsoChance = 44,
        torsos = {"Base.HolsterSimple"},
        handChance = 18,
        hands = {"Base.Gloves_LeatherGlovesBlack"}
    },
    medic = {
        backpackChance = 84,
        backpacks = {"Base.Bag_Satchel_Medical", "Base.Bag_Satchel"},
        headChance = 18,
        heads = {"Base.Hat_Army"},
        torsoChance = 24,
        torsos = {"Base.HolsterSimple"},
        handChance = 12,
        hands = {"Base.Gloves_LeatherGlovesBlack"}
    },
    raider = {
        backpackChance = 42,
        backpacks = {"Base.Bag_Satchel", "Base.Bag_ALICEpack_Army"},
        headChance = 22,
        heads = {"Base.Hat_Army"},
        torsoChance = 38,
        torsos = {"Base.HolsterSimple", "Base.Vest_BulletArmy"},
        handChance = 22,
        hands = {"Base.Gloves_LeatherGlovesBlack"}
    },
    trader = {
        backpackChance = 54,
        backpacks = {"Base.Bag_Satchel", "Base.Bag_Satchel_Medical"},
        headChance = 14,
        heads = {"Base.Hat_Army"},
        torsoChance = 18,
        torsos = {"Base.HolsterSimple"},
        handChance = 8,
        hands = {"Base.Gloves_LeatherGlovesBlack"}
    },
    survivor = {
        backpackChance = 46,
        backpacks = {"Base.Bag_Satchel", "Base.Bag_ALICEpack_Army"},
        headChance = 14,
        heads = {"Base.Hat_Army"},
        torsoChance = 26,
        torsos = {"Base.HolsterSimple"},
        handChance = 14,
        hands = {"Base.Gloves_LeatherGlovesBlack"}
    }
}

local function npcc_styleHash(value)
    local s = tostring(value or "")
    local h = 0
    for i = 1, #s do
        h = (h * 131 + string.byte(s, i)) % 2147483647
    end
    return h
end

local function npcc_seed(member, salt)
    local parts = {
        member and (member.persistentId or member.uid or member.id) or "",
        member and (member.worldGroupId or member.groupId) or "",
        member and member.memberIndex or "",
        member and member.factionSide or member and member.side or "",
        member and member.outfit or "",
        member and member.tacticalRole or member and member.role or "",
        salt or ""
    }
    return npcc_styleHash(table.concat(parts, "|"))
end

local function npcc_pick(list, seed)
    if type(list) ~= "table" or #list == 0 then return nil end
    local index = (math.abs(tonumber(seed) or 0) % #list) + 1
    return list[index]
end

local NPC_HUMAN_FACE_PRESETS = {
    maleHair = {"Bald", "Fresh", "Demi", "FlatTop", "MohawkShort", "Short", "Messy", "CrewCut", "Mullet", "PonyTail", "Recede", "Baldspot"},
    femaleHair = {"Fresh", "Demi", "Short", "Messy", "Bob", "Long", "PonyTail", "Bun", "Pixie", "MohawkShort"},
    beard = {"", "Stubble", "Goatee", "Moustache", "Full", "Chops", "Long"},
    hairColors = {
        {r = 0.05, g = 0.04, b = 0.035},
        {r = 0.12, g = 0.07, b = 0.035},
        {r = 0.18, g = 0.12, b = 0.07},
        {r = 0.30, g = 0.20, b = 0.11},
        {r = 0.46, g = 0.34, b = 0.20},
        {r = 0.64, g = 0.52, b = 0.35},
        {r = 0.75, g = 0.62, b = 0.43},
        {r = 0.42, g = 0.42, b = 0.40}
    },
    skinColors = {
        {r = 0.94, g = 0.76, b = 0.62},
        {r = 0.86, g = 0.66, b = 0.52},
        {r = 0.74, g = 0.53, b = 0.40},
        {r = 0.58, g = 0.39, b = 0.28},
        {r = 0.40, g = 0.27, b = 0.20},
        {r = 0.92, g = 0.70, b = 0.55}
    }
}

local function npcc_colorCopy(color)
    if type(color) ~= "table" then return nil end
    return {r = tonumber(color.r) or 0, g = tonumber(color.g) or 0, b = tonumber(color.b) or 0}
end

local function npcc_isKnownHumanSkinTexture(name)
    name = tostring(name or "")
    return string.match(name, "^MaleBody0[1-5]$") ~= nil
        or string.match(name, "^FemaleBody0[1-5]$") ~= nil
end

local function npcc_isBadSkinTexture(name)
    name = tostring(name or "")
    if name == "" then return true end
    local lower = string.lower(name)
    if string.find(lower, "zombie", 1, true) ~= nil
        or string.find(lower, "zed", 1, true) ~= nil
        or string.find(lower, "rot", 1, true) ~= nil
        or string.find(lower, "skeleton", 1, true) ~= nil
        or string.find(lower, "burnt", 1, true) ~= nil then
        return true
    end
    return not npcc_isKnownHumanSkinTexture(name)
end

local function npcc_isBadSkinColor(color)
    if type(color) ~= "table" then return true end
    local r = tonumber(color.r)
    local g = tonumber(color.g)
    local b = tonumber(color.b)
    if not r or not g or not b then return true end
    if r < 0.18 or g < 0.12 or b < 0.08 or r > 1.0 or g > 1.0 or b > 1.0 then return true end
    if g > r + 0.08 and g > b + 0.06 then return true end
    if b > r + 0.12 then return true end
    local maxc = math.max(r, math.max(g, b))
    local minc = math.min(r, math.min(g, b))
    if maxc < 0.55 and (maxc - minc) < 0.055 then return true end
    return false
end

local function npcc_skinTextureFor(seed, female)
    seed = math.abs(math.floor(tonumber(seed) or 0))
    if female == true then
        return "FemaleBody0" .. tostring(1 + seed % 5)
    end
    return "MaleBody0" .. tostring(1 + seed % 5)
end

local function npcc_boolFromSeed(seed, chance)
    chance = math.max(0, math.min(100, tonumber(chance) or 0))
    return (math.abs(math.floor(tonumber(seed) or 0)) % 100) < chance
end

local function npcc_memberFemale(member, zombie)
    if zombie and zombie.isFemale then
        local ok, value = pcall(function() return zombie:isFemale() == true end)
        if ok then return value == true end
    end
    if type(member) == "table" and member.female ~= nil then return member.female == true end
    if type(member) == "table" and member.femaleChance ~= nil then
        return npcc_boolFromSeed(npcc_seed(member, "gender"), member.femaleChance)
    end
    return false
end

function NPCCreatorBridge.BuildHumanFacePreset(member, zombie)
    if type(member) ~= "table" then return nil end

    local seed = tonumber(member.appearanceSeed)
    if not seed or seed == 0 then
        seed = npcc_seed(member, "human-face")
    end

    local female = npcc_memberFemale(member, zombie)
    local style = tostring(member.appearanceStyle or (NPCCreatorBridge.ResolveAppearanceStyle and NPCCreatorBridge.ResolveAppearanceStyle(member)) or "survivor")
    local styleSeed = seed + npcc_styleHash(style)
    local hairList = female and NPC_HUMAN_FACE_PRESETS.femaleHair or NPC_HUMAN_FACE_PRESETS.maleHair
    local hairStyle = npcc_pick(hairList, styleSeed + 11)
    local beardStyle = nil
    if female ~= true then
        local beardRoll = math.abs(styleSeed + 23) % 100
        if style == "raider" or style == "survivor" then
            beardStyle = beardRoll < 72 and npcc_pick(NPC_HUMAN_FACE_PRESETS.beard, styleSeed + 23) or ""
        elseif style == "leader" or style == "mercenary" or style == "militia" then
            beardStyle = beardRoll < 48 and npcc_pick(NPC_HUMAN_FACE_PRESETS.beard, styleSeed + 23) or ""
        elseif style == "trader" or style == "medic" then
            beardStyle = beardRoll < 28 and npcc_pick(NPC_HUMAN_FACE_PRESETS.beard, styleSeed + 23) or ""
        else
            beardStyle = beardRoll < 40 and npcc_pick(NPC_HUMAN_FACE_PRESETS.beard, styleSeed + 23) or ""
        end
    else
        beardStyle = ""
    end

    local hairColor = npcc_colorCopy(npcc_pick(NPC_HUMAN_FACE_PRESETS.hairColors, styleSeed + 41)) or {r = 0.12, g = 0.08, b = 0.04}
    local skinColor = npcc_colorCopy(npcc_pick(NPC_HUMAN_FACE_PRESETS.skinColors, styleSeed + 37)) or {r = 0.86, g = 0.66, b = 0.52}
    local beardColor = npcc_colorCopy(hairColor)
    if beardColor and (math.abs(styleSeed + 59) % 100) < 24 then
        beardColor.r = math.max(0, beardColor.r * 0.72)
        beardColor.g = math.max(0, beardColor.g * 0.72)
        beardColor.b = math.max(0, beardColor.b * 0.72)
    end

    return {
        appearanceSeed = seed,
        faceProfile = "human_face_v1",
        female = female,
        skinTexture = npcc_skinTextureFor(seed + 7, female),
        skinColor = skinColor,
        hairStyle = hairStyle,
        hairColor = hairColor,
        beardStyle = beardStyle,
        beardColor = beardColor
    }
end

function NPCCreatorBridge.ApplyHumanFacePresetToMember(member, zombie, force)
    if type(member) ~= "table" then return member end
    local needsPreset = force == true or member.faceProfile ~= "human_face_v1"
    if not needsPreset and not npcc_isBadSkinTexture(member.skinTexture) then return member end

    local preset = NPCCreatorBridge.BuildHumanFacePreset(member, zombie)
    if not preset then return member end

    member.appearanceSeed = member.appearanceSeed or preset.appearanceSeed
    member.faceProfile = preset.faceProfile
    if member.female == nil then member.female = preset.female end
    if needsPreset or npcc_isBadSkinTexture(member.skinTexture) then member.skinTexture = preset.skinTexture end
    if needsPreset or npcc_isBadSkinColor(member.skinColor) then member.skinColor = preset.skinColor end
    if needsPreset or not member.hairStyle or member.hairStyle == "" then member.hairStyle = preset.hairStyle end
    if needsPreset or type(member.hairColor) ~= "table" then member.hairColor = preset.hairColor end
    if needsPreset or member.beardStyle == nil then member.beardStyle = preset.beardStyle end
    if needsPreset or type(member.beardColor) ~= "table" then member.beardColor = preset.beardColor end
    return member
end

function NPCCreatorBridge.ApplyHumanFacePresetToBrain(brain, zombie, member, force)
    if type(brain) ~= "table" then return brain end
    local source = {}
    if type(member) == "table" then
        for k, v in pairs(member) do source[k] = v end
    end
    for k, v in pairs(brain) do
        if source[k] == nil then source[k] = v end
    end
    source.female = npcc_memberFemale(brain, zombie)
    source.appearanceSeed = brain.appearanceSeed or source.appearanceSeed
    source.appearanceStyle = brain.appearanceStyle or source.appearanceStyle
    source.persistentId = brain.persistentId or brain.uid or source.persistentId
    source.uid = brain.uid or source.uid
    source.id = brain.id or source.id

    local preset = NPCCreatorBridge.BuildHumanFacePreset(source, zombie)
    if not preset then return brain end

    local needsPreset = force == true or brain.faceProfile ~= "human_face_v1"
    brain.appearanceSeed = brain.appearanceSeed or preset.appearanceSeed
    brain.faceProfile = preset.faceProfile
    brain.female = source.female == true
    if needsPreset or npcc_isBadSkinTexture(brain.skinTexture) then brain.skinTexture = preset.skinTexture end
    if needsPreset or npcc_isBadSkinColor(brain.skinColor) then brain.skinColor = preset.skinColor end
    if needsPreset or not brain.hairStyle or brain.hairStyle == "" then brain.hairStyle = preset.hairStyle end
    if needsPreset or type(brain.hairColor) ~= "table" then brain.hairColor = preset.hairColor end
    if needsPreset or brain.beardStyle == nil then brain.beardStyle = preset.beardStyle end
    if needsPreset or type(brain.beardColor) ~= "table" then brain.beardColor = preset.beardColor end
    return brain
end

local function npcc_contains(list, value)
    if type(list) ~= "table" or not value then return false end
    for _, existing in ipairs(list) do
        if existing == value then return true end
    end
    return false
end

local function npcc_wearCategory(fullType)
    local name = tostring(fullType or "")
    if string.find(name, "ScrapSmithArmor.scrapsmith_", 1, true) == 1 then
        if string.find(name, "Helm", 1, true) or string.find(name, "Bascinet", 1, true) or string.find(name, "bascinet", 1, true) or string.find(name, "Helmet", 1, true) or string.find(name, "kettleHelm", 1, true) then return "head" end
        if string.find(name, "Hauberk", 1, true) or string.find(name, "coatOfPlates", 1, true) or string.find(name, "gambeson", 1, true) or string.find(name, "plateCuirass", 1, true) then return "torso" end
        if string.find(name, "plateMittens", 1, true) then return "hands" end
    end
    if string.find(name, "Base.Bag_", 1, true) == 1 then return "bag" end
    if string.find(name, "Base.Hat_", 1, true) == 1 then return "head" end
    if string.find(name, "Base.Gloves_", 1, true) == 1 then return "hands" end
    if string.find(name, "Base.Holster", 1, true) == 1 or string.find(name, "Base.Vest_", 1, true) == 1 then return "torso" end
    return name
end

local function npcc_hasWearCategory(member, category)
    if type(member) ~= "table" or type(member.baseGearWear) ~= "table" or not category then return false end
    for _, existing in ipairs(member.baseGearWear) do
        if npcc_wearCategory(existing) == category then return true end
    end
    return false
end

local function npcc_addWear(member, fullType)
    if type(member) ~= "table" or not fullType then return false end
    member.baseGearWear = member.baseGearWear or {}
    if npcc_contains(member.baseGearWear, fullType) then return false end
    if npcc_hasWearCategory(member, npcc_wearCategory(fullType)) then return false end
    table.insert(member.baseGearWear, fullType)
    return true
end


local function npcc_hasActivatedMod(modId)
    if not getActivatedMods or not modId then return false end
    local mods = getActivatedMods()
    return mods and mods.contains and mods:contains(modId) or false
end

local function npcc_itemExists(fullType)
    if not fullType then return false end
    if NPCLoadoutRegistry and NPCLoadoutRegistry.ItemExists then return NPCLoadoutRegistry.ItemExists(fullType) end
    if not InventoryItemFactory or not InventoryItemFactory.CreateItem then return true end
    local ok, item = pcall(function() return InventoryItemFactory.CreateItem(fullType) end)
    return ok and item ~= nil
end

local function npcc_tryWearIfExists(member, fullType)
    if npcc_itemExists(fullType) then
        return npcc_addWear(member, fullType)
    end
    return false
end

local function npcc_applyScrapSmithStyle(member, style, seed)
    if not npcc_hasActivatedMod("ScrapSmith") then return end

    local roll = math.abs(tonumber(seed) or 0) % 100
    if style == "leader" or style == "mercenary" then
        if roll < 28 then npcc_tryWearIfExists(member, "ScrapSmithArmor.scrapsmith_coatOfPlates") end
        if roll < 52 then npcc_tryWearIfExists(member, "ScrapSmithArmor.scrapsmith_kettleHelm") end
    elseif style == "militia" or style == "checkpoint" then
        if roll < 22 then npcc_tryWearIfExists(member, "ScrapSmithArmor.scrapsmith_gambeson") end
        if roll < 46 then npcc_tryWearIfExists(member, "ScrapSmithArmor.scrapsmith_bascinet") end
    elseif style == "raider" then
        if roll < 20 then npcc_tryWearIfExists(member, "ScrapSmithArmor.scrapsmith_chainmailHauberk") end
        if roll < 38 then npcc_tryWearIfExists(member, "ScrapSmithArmor.scrapsmith_blackenedGreatHelm") end
    elseif style == "survivor" or style == "scout" then
        if roll < 12 then npcc_tryWearIfExists(member, "ScrapSmithArmor.scrapsmith_gambeson") end
    end
end

local function npcc_outfitHas(member, pattern)
    local outfit = tostring(member and member.outfit or "")
    return outfit ~= "" and string.find(string.lower(outfit), string.lower(pattern), 1, true) ~= nil
end

function NPCCreatorBridge.ResolveAppearanceStyle(member)
    if type(member) ~= "table" then return "survivor" end

    if member.appearanceStyle and member.appearanceStyle ~= "" then
        return tostring(member.appearanceStyle)
    end

    if NPCCivilianArchetypesBridge and NPCCivilianArchetypesBridge.ResolveForMember then
        local okProfile, profile = pcall(function() return NPCCivilianArchetypesBridge.ResolveForMember(member) end)
        if okProfile and type(profile) == "table" and profile.appearanceStyle then
            return tostring(profile.appearanceStyle)
        end
    end

    if member.blackMarket == true or member.blackMarketNPC == true or member.special == "BlackMarket" then
        return "trader"
    end

    local tacticalRole = tostring(member.tacticalRole or member.role or member.strategicRole or "")
    local side = tostring(member.factionSide or member.side or member.faction or member.patrolColor or "")
    local archetype = tostring(member.baseArchetype or member.baseStyle or member.behaviorStyle or "")

    if member.commandAura or tacticalRole == "leader" or tacticalRole == "base_commander" or member.mercenaryElite then
        return member.mercenary and "mercenary" or "leader"
    end
    if archetype == "checkpoint" or tacticalRole == "checkpoint_guard" or tacticalRole == "road_guard" then
        return "checkpoint"
    end
    if npcc_outfitHas(member, "scient") or npcc_outfitHas(member, "doctor") or npcc_outfitHas(member, "nurse") then
        return "medic"
    end
    if member.mercenary or archetype == "military" or archetype == "elite_safehouse" or tacticalRole == "elite_bodyguard" then
        return member.mercenary and "mercenary" or "militia"
    end
    if tacticalRole == "scout" or tacticalRole == "recon" or tacticalRole == "spotter" then
        return "scout"
    end
    if side == "red" or archetype == "raider" or npcc_outfitHas(member, "thug") or npcc_outfitHas(member, "punk") or npcc_outfitHas(member, "doom") then
        return "raider"
    end
    if side == "green" then
        return (member.preferRoads or tacticalRole == "patrol" or tacticalRole == "skirmisher") and "scout" or "survivor"
    end
    if side == "blue" then
        return member.mercenary and "mercenary" or "scout"
    end
    if side == "black" then
        return "trader"
    end
    if npcc_outfitHas(member, "police") or npcc_outfitHas(member, "army") or npcc_outfitHas(member, "veteran") then
        return "militia"
    end
    return "survivor"
end

function NPCCreatorBridge.ApplyCivilianArchetypeToMember(member)
    if type(member) ~= "table" then return member end
    if not (NPCCivilianArchetypesBridge and NPCCivilianArchetypesBridge.ResolveForMember) then return member end

    local okProfile, profile = pcall(function() return NPCCivilianArchetypesBridge.ResolveForMember(member) end)
    if not okProfile or type(profile) ~= "table" then return member end

    if member.professionArchetypeApplied == true and member.professionArchetype == profile.id then return member end

    member.professionArchetype = member.professionArchetype or profile.id
    member.professionCategory = member.professionCategory or profile.category
    member.professionArchetypeApplied = true
    member.appearanceStyle = member.appearanceStyle or profile.appearanceStyle
    member.cinematicAppearance = profile.cinematic == true
    member.behaviorTags = member.behaviorTags or {}
    if type(profile.tags) == "table" then
        for _, tag in ipairs(profile.tags) do
            member.behaviorTags[tostring(tag)] = true
        end
    end

    if profile.discipline and not member.discipline then member.discipline = profile.discipline end
    if profile.aggression and not member.aggression then member.aggression = profile.aggression end
    if profile.morale and not member.morale then member.morale = profile.morale end
    if profile.accuracyBoost then member.accuracyBoost = math.max(tonumber(member.accuracyBoost) or 1, tonumber(profile.accuracyBoost) or 1) end
    if profile.healthBonus then
        local health = tonumber(member.health) or 3.0
        member.health = health + tonumber(profile.healthBonus)
        member.maxHealth = math.max(tonumber(member.maxHealth) or 0, member.health)
    end

    if (not member.baseArchetype) and (not member.strategicBaseSpecialist) and NPCCivilianArchetypesBridge.PickOutfit then
        local outfit = NPCCivilianArchetypesBridge.PickOutfit(profile, member)
        if outfit and outfit ~= "" then member.outfit = outfit end
    end

    if NPCCivilianArchetypesBridge.PickWear then
        local wear = NPCCivilianArchetypesBridge.PickWear(profile, member)
        if type(wear) == "table" then
            member.baseGearWear = member.baseGearWear or {}
            for _, fullType in ipairs(wear) do
                npcc_addWear(member, fullType)
            end
        end
    end

    if NPCCivilianArchetypesBridge.PickLoot then
        local loot = NPCCivilianArchetypesBridge.PickLoot(profile, member)
        if type(loot) == "table" and #loot > 0 then
            member.loot = member.loot or {}
            for _, fullType in ipairs(loot) do
                member.loot[#member.loot + 1] = fullType
            end
        end
    end

    return member
end

function NPCCreatorBridge.ApplyAppearanceStyleToMember(member)
    if type(member) ~= "table" then return member end
    if not member.professionArchetype then
        NPCCreatorBridge.ApplyCivilianArchetypeToMember(member)
    end

    local style = NPCCreatorBridge.ResolveAppearanceStyle(member)
    local kit = NPC_APPEARANCE_STYLE_KITS[style] or NPC_APPEARANCE_STYLE_KITS.survivor
    local seed = npcc_seed(member, style)

    member.appearanceStyle = style
    member.baseGearWear = member.baseGearWear or {}

    local function tryWear(chance, items, salt)
        if type(items) ~= "table" or #items == 0 then return end
        local localSeed = npcc_seed(member, salt)
        if (math.abs(localSeed) % 100) < math.max(0, tonumber(chance) or 0) then
            local choice = npcc_pick(items, localSeed)
            if choice then npcc_addWear(member, choice) end
        end
    end

    tryWear(kit.backpackChance, kit.backpacks, "bag")
    tryWear(kit.torsoChance, kit.torsos, "torso")
    tryWear(kit.headChance, kit.heads, "head")
    tryWear(kit.handChance, kit.hands, "hands")

    if style == "leader" or style == "mercenary" then
        if not npcc_contains(member.baseGearWear, "Base.Bag_ALICEpack_Army") and not npcc_contains(member.baseGearWear, "Base.Bag_Satchel") then
            npcc_addWear(member, npcc_pick(kit.backpacks, seed + 17) or "Base.Bag_ALICEpack_Army")
        end
        if not npcc_contains(member.baseGearWear, "Base.HolsterDouble") and not npcc_contains(member.baseGearWear, "Base.Vest_BulletArmy") then
            npcc_addWear(member, npcc_pick(kit.torsos, seed + 29) or "Base.HolsterDouble")
        end
    elseif style == "medic" then
        if not npcc_contains(member.baseGearWear, "Base.Bag_Satchel_Medical") and not npcc_contains(member.baseGearWear, "Base.Bag_Satchel") then
            npcc_addWear(member, "Base.Bag_Satchel_Medical")
        end
    elseif style == "checkpoint" then
        if not npcc_contains(member.baseGearWear, "Base.Vest_BulletPolice") and not npcc_contains(member.baseGearWear, "Base.Vest_BulletArmy") then
            npcc_addWear(member, "Base.Vest_BulletPolice")
        end
    end

    if member.baseArchetype == "military" or member.baseArchetype == "elite_safehouse" then
        if not npcc_contains(member.baseGearWear, "Base.Hat_ArmyHelmet") then
            npcc_addWear(member, "Base.Hat_ArmyHelmet")
        end
    end

    npcc_applyScrapSmithStyle(member, style, seed)

    if #member.baseGearWear > 4 then
        local trimmed = {}
        for i = 1, 4 do trimmed[i] = member.baseGearWear[i] end
        member.baseGearWear = trimmed
    end

    if NPCCreatorBridge.ApplyHumanFacePresetToMember then
        NPCCreatorBridge.ApplyHumanFacePresetToMember(member, nil, false)
    end
    return member
end

function NPCCreatorBridge.CopyWeapon(weapon)
    if NPCWeaponsBridge and NPCWeaponsBridge.Copy then
        return NPCWeaponsBridge.Copy(weapon)
    end
    if not weapon then return nil end
    local copy = {}
    for k, v in pairs(weapon) do
        copy[k] = v
    end
    return copy
end

function NPCCreatorBridge.PickMelee(clan)
    local melee
    if NPCWeaponsBridge and NPCWeaponsBridge.GetSpawnMelee then
        melee = NPCWeaponsBridge.GetSpawnMelee(clan)
    elseif NPCWeaponsBridge and NPCWeaponsBridge.GetMeleeForClan then
        melee = NPCWeaponsBridge.GetMeleeForClan(clan)
    elseif clan then
        melee = clan.Melee
    end

    if melee and #melee > 0 then
        return NPCUtils.Choice(melee)
    end

    return "Base.Axe"
end

function NPCCreatorBridge.IsFirearmHeavyMode()
    if NPCWeaponsBridge and NPCWeaponsBridge.IsFirearmsRevampActive then
        local ok, active = pcall(NPCWeaponsBridge.IsFirearmsRevampActive)
        if ok and active then return true end
    end

    local mods = getActivatedMods and getActivatedMods()
    return mods and (mods:contains("firearmmodRevamp") or mods:contains("firearmmod"))
end

function NPCCreatorBridge.GetFirearmWeightedWave(wave)
    wave = wave or {}
    if not NPCCreatorBridge.IsFirearmHeavyMode() then return wave end

    local rifleChance = tonumber(wave.hasRifleChance) or 0
    local pistolChance = tonumber(wave.hasPistolChance) or 0

    -- Respect explicit melee-only scenes/configs. Firearms integrations should widen the
    -- weapon pool, not turn every low-tier civilian/neutral wave into an LMG squad.
    if rifleChance <= 0 and pistolChance <= 0 then return wave end

    local weighted = {}
    for k, v in pairs(wave) do
        weighted[k] = v
    end

    local elite = wave.eliteLoadout == true or wave.mercenaryElite == true or rifleChance >= 90 or (tonumber(wave.rifleMagCount) or 0) >= 5
    if elite then
        weighted.hasRifleChance = math.max(rifleChance, 88)
        weighted.hasPistolChance = math.max(pistolChance, 68)
        weighted.rifleMagCount = math.max(tonumber(wave.rifleMagCount) or 0, 4)
        weighted.pistolMagCount = math.max(tonumber(wave.pistolMagCount) or 0, 3)
    elseif rifleChance >= 35 or pistolChance >= 55 then
        weighted.hasRifleChance = math.max(rifleChance, 52)
        weighted.hasPistolChance = math.max(pistolChance, 58)
        weighted.rifleMagCount = math.max(tonumber(wave.rifleMagCount) or 0, 2)
        weighted.pistolMagCount = math.max(tonumber(wave.pistolMagCount) or 0, 3)
    else
        weighted.hasRifleChance = math.max(rifleChance, 18)
        weighted.hasPistolChance = math.max(pistolChance, 38)
        weighted.rifleMagCount = math.max(tonumber(wave.rifleMagCount) or 0, 1)
        weighted.pistolMagCount = math.max(tonumber(wave.pistolMagCount) or 0, 2)
    end

    return weighted
end

local function npcc_weaponName(weapon)
    if type(weapon) == "table" then return tostring(weapon.name or "") end
    return tostring(weapon or "")
end

local function npcc_weaponMagName(weapon)
    if type(weapon) ~= "table" then return "" end
    return tostring(weapon.magName or weapon.magazine or weapon.mag or "")
end

local function npcc_weaponMagSize(weapon)
    if type(weapon) ~= "table" then return 0 end
    return tonumber(weapon.magSize or weapon.clipSize or weapon.maxAmmo) or 0
end

function NPCCreatorBridge.FirearmSpawnTier(weapon)
    local name = string.lower(npcc_weaponName(weapon))
    local magName = string.lower(npcc_weaponMagName(weapon))
    local magSize = npcc_weaponMagSize(weapon)
    if name == "" then return "common" end

    if magSize >= 75
        or string.find(name, "lmg", 1, true)
        or string.find(name, "m249", 1, true)
        or string.find(name, "m240", 1, true)
        or string.find(name, "mg42", 1, true)
        or string.find(name, "m60", 1, true)
        or string.find(name, "mk43", 1, true)
        or string.find(name, "pkm", 1, true)
        or string.find(name, "rpd", 1, true)
        or string.find(name, "shrike", 1, true)
        or string.find(magName, "belt", 1, true) then
        return "heavy"
    end

    if string.find(name, "m40", 1, true)
        or string.find(name, "psg", 1, true)
        or string.find(name, "msg", 1, true)
        or string.find(name, "sniper", 1, true)
        or string.find(name, "338", 1, true)
        or string.find(magName, "308", 1, true)
        or string.find(magName, "762x54", 1, true) then
        return "marksman"
    end

    if string.find(name, "shotgun", 1, true)
        or string.find(name, "moss", 1, true)
        or string.find(name, "sxs", 1, true)
        or string.find(magName, "shotgun", 1, true) then
        return "shotgun"
    end

    if string.find(name, "22", 1, true)
        or string.find(magName, "22", 1, true)
        or string.find(name, "pcc", 1, true)
        or string.find(name, "carbine", 1, true) then
        return "civilian"
    end

    if magSize >= 35 then return "highcap" end
    return "common"
end

local function npcc_firearmSpawnWeight(weapon, wave, slot)
    local tier = NPCCreatorBridge.FirearmSpawnTier(weapon)
    local rifleChance = tonumber(wave and wave.hasRifleChance) or 0
    local elite = wave and (wave.eliteLoadout == true or wave.mercenaryElite == true or rifleChance >= 90 or (tonumber(wave.rifleMagCount) or 0) >= 5)

    if slot == "secondary" then
        if tier == "heavy" then return elite and 2 or 0 end
        if tier == "marksman" then return elite and 4 or 1 end
        if tier == "highcap" then return elite and 12 or 6 end
        return 18
    end

    if tier == "heavy" then return elite and 4 or 1 end
    if tier == "marksman" then return elite and 8 or 3 end
    if tier == "highcap" then return elite and 12 or 5 end
    if tier == "shotgun" then return elite and 10 or 13 end
    if tier == "civilian" then return elite and 8 or 26 end
    return elite and 18 or 14
end

function NPCCreatorBridge.PickBalancedFirearm(pool, wave, slot)
    if type(pool) ~= "table" or #pool <= 0 then return nil end

    local total = 0
    local weights = {}
    for i = 1, #pool do
        local weight = tonumber(npcc_firearmSpawnWeight(pool[i], wave, slot)) or 0
        if weight > 0 then
            total = total + weight
            weights[i] = weight
        end
    end

    if total <= 0 then
        return NPCUtils and NPCUtils.Choice and NPCUtils.Choice(pool) or pool[1]
    end

    local roll = ZombRand(total) + 1
    local cursor = 0
    for i = 1, #pool do
        local weight = weights[i]
        if weight and weight > 0 then
            cursor = cursor + weight
            if roll <= cursor then return pool[i] end
        end
    end

    return pool[#pool]
end

function NPCCreatorBridge.MakeWeapons(wave, clan)
    wave = NPCCreatorBridge.GetFirearmWeightedWave(wave)

    local weapons = {}

    -- fallback
    weapons.melee = "Base.Axe"

    local primaryPool = nil
    local secondaryPool = nil
    if NPCWeaponsBridge and NPCWeaponsBridge.GetSpawnPrimary then
        primaryPool = NPCWeaponsBridge.GetSpawnPrimary(clan)
    elseif clan then
        primaryPool = clan.Primary
    end
    if NPCWeaponsBridge and NPCWeaponsBridge.GetSpawnSecondary then
        secondaryPool = NPCWeaponsBridge.GetSpawnSecondary(clan)
    elseif clan then
        secondaryPool = clan.Secondary
    end

    -- set up primary weapon
    weapons.primary = {}
    weapons.primary.name = false
    weapons.primary.magSize = 0
    weapons.primary.bulletsLeft = 0
    weapons.primary.magCount = 0
    local rifleRandom = ZombRandFloat(0, 101)
    if primaryPool and #primaryPool > 0 and rifleRandom < (wave.hasRifleChance or 0) then
        weapons.primary = NPCCreatorBridge.CopyWeapon(NPCCreatorBridge.PickBalancedFirearm(primaryPool, wave, "primary"))
        weapons.primary.magCount = wave.rifleMagCount or 0
    end

    -- set up secondary weapon
    weapons.secondary = {}
    weapons.secondary.name = false
    weapons.secondary.magSize = 0
    weapons.secondary.bulletsLeft = 0
    weapons.secondary.magCount = 0
    local pistolRandom = ZombRandFloat(0, 101)
    if secondaryPool and #secondaryPool > 0 and pistolRandom < (wave.hasPistolChance or 0) then
        weapons.secondary = NPCCreatorBridge.CopyWeapon(NPCCreatorBridge.PickBalancedFirearm(secondaryPool, wave, "secondary"))
        weapons.secondary.magCount = wave.pistolMagCount or 0
    end

    return weapons
end

function NPCCreatorBridge.MakeLoot(clanLoot)
    local loot = {}

    -- add loot from loot table
    for k, v in pairs(clanLoot) do
        local r = ZombRand(101)
        if r <= v.chance then
            table.insert(loot, v.name)
        end
    end

    -- add clan-independent, individual random personal character loot below
    
    -- smoker
    if not getActivatedMods():contains("Smoker") then
        if ZombRand(4) == 1 then
            for i=1, ZombRand(19) do
                table.insert(loot, NPCCompatibilityBridge.GetLegacyItem("Base.CigaretteSingle"))
            end
            table.insert(loot, "Base.Lighter")
        end
    end

    -- hotties collector
    if ZombRand(100) == 1 then
        for i=1, ZombRand(31) do
            table.insert(loot, "Base.HottieZ")
        end
    end

    -- perv
    if ZombRand(100) == 1 then
        for i=1, ZombRand(44) do
            local i = ZombRand(7)
            if i == 1 then
                table.insert(loot, "Base.Underpants_White")
            elseif i == 2 then
                table.insert(loot, "Base.Underpants_Black")
            elseif i == 3 then
                table.insert(loot, "Base.FrillyUnderpants_Black")
            elseif i == 4 then
                table.insert(loot, "Base.FrillyUnderpants_Pink")
            elseif i == 5 then
                table.insert(loot, "Base.FrillyUnderpants_Red")
            elseif i == 6 then
                table.insert(loot, "Base.Underpants_RedSpots")
            else
                table.insert(loot, "Base.Underpants_AnimalPrint")
            end
        end
    end

    -- ku chwale ojczyzny!
    if ZombRand(100) == 1 then
        for i=1, ZombRand(18) do
            table.insert(loot, "Base.Perogies")
        end
    end
    

    return loot
end

function NPCCreatorBridge.GetFallbackClan()
    if NPCClan then
        return NPCClan.DoomRider or NPCClan.Police or NPCClan.Criminal or NPCClan.Reclaimer or NPCClan.Scientist
    end
    return nil
end

function NPCCreatorBridge.NormalizeHealth(health)
    if NPCHealthRegenBridge and NPCHealthRegenBridge.NormalizeSpawnHealth then
        return NPCHealthRegenBridge.NormalizeSpawnHealth(health)
    end

    health = tonumber(health) or 3.0
    if health < 3.0 then health = 3.0 end
    if health > 4.0 then health = 4.0 end
    return health
end

function NPCCreatorBridge.GetClanFromWave(wave)
    if wave and wave.clan and type(wave.clan) == "table" then return wave.clan end
    if wave and wave.clanId and NPCCreatorBridge.GroupMap then
        local clan = NPCCreatorBridge.GroupMap[wave.clanId] or NPCCreatorBridge.GroupMap[tostring(wave.clanId)] or NPCCreatorBridge.GroupMap[tonumber(wave.clanId)]
        if clan and type(clan) == "table" then return clan end
    end
    return NPCCreatorBridge.GetFallbackClan()
end

function NPCCreatorBridge.MakeFromWave(wave)
    wave = wave or {}
    local clan = NPCCreatorBridge.GetClanFromWave(wave)
    if not clan then return nil end

    local bandit = {}
    
    -- properties to be rewritten from clan file to bandit instance
    bandit.clan = clan.id
    bandit.health = NPCCreatorBridge.NormalizeHealth(clan.health)
    bandit.femaleChance = clan.femaleChance
    bandit.eatBody = clan.eatBody
    bandit.accuracyBoost = clan.accuracyBoost

    -- gun weapon choice comes from clan file, weapon probability from wave data
    bandit.weapons = NPCCreatorBridge.MakeWeapons(wave, clan)

    -- melee weapon choice comes from clan file
    bandit.weapons.melee = NPCCreatorBridge.PickMelee(clan)

    -- outfit choice comes from clan file
    bandit.outfit = NPCUtils.Choice(clan.Outfits)

    -- hairstyle 
    if clan.hairStyles then
        bandit.hairStyle = NPCUtils.Choice(clan.hairStyles)
    end
    
    -- loot choice comes from clan file
    bandit.loot = NPCCreatorBridge.MakeLoot(clan.Loot)

    NPCCreatorBridge.ApplyAppearanceStyleToMember(bandit)
    return bandit
end

function NPCCreatorBridge.MakeFromSpawnType(spawnData)
    local clan
    local config = {}

    -- clan detection based on building type
    if spawnData.buildingType == "medical" then
        clan = NPCClan.Scientist
        config.hasRifleChance = 0
        config.hasPistolChance = 50
        config.rifleMagCount = 0
        config.pistolMagCount = 3
    elseif spawnData.buildingType == "police" then
        clan = NPCClan.Police
        config.hasRifleChance = 20
        config.hasPistolChance = 50
        config.rifleMagCount = 2
        config.pistolMagCount = 4
    elseif spawnData.buildingType == "gunstore" then
        clan = NPCClan.DoomRider
        config.hasRifleChance = 100
        config.hasPistolChance = 100
        config.rifleMagCount = 6
        config.pistolMagCount = 4
    elseif spawnData.buildingType == "bank" then
        clan = NPCClan.Criminal
        config.hasRifleChance = 10
        config.hasPistolChance = 80
        config.rifleMagCount = 0
        config.pistolMagCount = 3
    elseif spawnData.buildingType == "church" then
        clan = NPCClan.Reclaimer
        config.hasRifleChance = 0
        config.hasPistolChance = 0
        config.rifleMagCount = 0
        config.pistolMagCount = 0
    else
        clan = NPCClan.DoomRider
        config.hasRifleChance = 5
        config.hasPistolChance = 20
        config.rifleMagCount = 1
        config.pistolMagCount = 2
    end

    clan = clan or NPCCreatorBridge.GetFallbackClan()
    if not clan then return nil end

    local bandit = {}

    -- properties to be rewritten from clan file to bandit instance
    bandit.clan = clan.id
    bandit.health = NPCCreatorBridge.NormalizeHealth(clan.health)
    bandit.femaleChance = clan.femaleChance
    bandit.eatBody = clan.eatBody
    bandit.accuracyBoost = clan.accuracyBoost

    -- gun weapon choice comes from clan file, weapon probability from wave data
    bandit.weapons = NPCCreatorBridge.MakeWeapons(config, clan)

    -- melee weapon choice comes from clan file
    bandit.weapons.melee = NPCCreatorBridge.PickMelee(clan)

    -- outfit choice comes from clan file
    bandit.outfit = NPCUtils.Choice(clan.Outfits)

    -- hairstyle 
    if clan.hairStyles then
        bandit.hairStyle = NPCUtils.Choice(clan.hairStyles)
    end

    -- loot choice comes from clan file
    bandit.loot = NPCCreatorBridge.MakeLoot(clan.Loot)

    NPCCreatorBridge.ApplyAppearanceStyleToMember(bandit)
    return bandit
end

-- assignment to wave system, clan files append this table
NPCCreatorBridge.GroupMap = NPCCreatorBridge.GroupMap or {}

