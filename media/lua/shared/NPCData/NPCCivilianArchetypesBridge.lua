-- NPCCivilianArchetypesBridge.lua
-- Role/style catalog for professional, civilian and subculture NPC archetypes.

NPCCivilianArchetypesBridge = NPCCivilianArchetypesBridge or {}
NPCCivilianArchetypesBridge.Version = 1

local function bca_mods()
    return getActivatedMods and getActivatedMods() or nil
end

local function bca_hasMod(id)
    local mods = bca_mods()
    return mods and mods.contains and mods:contains(id)
end

local function bca_push(t, v)
    if t and v then t[#t + 1] = v end
end

local function bca_copy(list)
    local out = {}
    if type(list) == "table" then
        for i = 1, #list do out[#out + 1] = list[i] end
    end
    return out
end

local function bca_hash(value)
    local s = tostring(value or "")
    local h = 0
    for i = 1, #s do
        h = (h * 131 + string.byte(s, i)) % 2147483647
    end
    return h
end

local function bca_seed(member, salt)
    if type(member) ~= "table" then return bca_hash(salt or "") end
    return bca_hash(table.concat({
        tostring(member.persistentId or member.uid or member.id or ""),
        tostring(member.worldGroupId or member.groupId or ""),
        tostring(member.memberIndex or ""),
        tostring(member.factionSide or member.side or member.faction or member.patrolColor or ""),
        tostring(member.baseArchetype or member.baseStyle or ""),
        tostring(member.tacticalRole or member.role or member.strategicRole or ""),
        tostring(member.outfit or ""),
        tostring(salt or "")
    }, "|"))
end

local function bca_pick(list, seed)
    if type(list) ~= "table" or #list == 0 then return nil end
    local index = (math.abs(tonumber(seed) or 0) % #list) + 1
    return list[index]
end

local function bca_profile(id, category, style, outfits, wear, loot, opts)
    opts = opts or {}
    return {
        id = id,
        category = category,
        appearanceStyle = style,
        outfits = outfits or {},
        wear = wear or {},
        loot = loot or {},
        groupWeight = opts.groupWeight or 1,
        side = opts.side,
        tags = opts.tags or {},
        discipline = opts.discipline,
        aggression = opts.aggression,
        morale = opts.morale,
        accuracyBoost = opts.accuracyBoost,
        healthBonus = opts.healthBonus,
        tacticalRole = opts.tacticalRole,
        cinematic = opts.cinematic ~= false
    }
end

function NPCCivilianArchetypesBridge.ApplyBWardrobeIntegration(profiles)
    if type(profiles) ~= "table" or not bca_hasMod("BWardrobe") then return end

    local function wear(profileId, fullType)
        local profile = profiles[profileId]
        if profile and type(profile.wear) == "table" then
            bca_push(profile.wear, fullType)
        end
    end

    wear("punk", "BWardrobe.Hat_Cap_Casual_Reverse")
    wear("punk", "BWardrobe.Earring_X")
    wear("punk", "BWardrobe.Glasses_Cool_Black")
    wear("goth", "BWardrobe.Earring_Cross_Inverted")
    wear("goth", "BWardrobe.Necklace_Pendant_Cross")
    wear("goth", "BWardrobe.Glasses_Round_Black")
    wear("metalhead", "BWardrobe.Necklace_Pendant_Lightning1")
    wear("metalhead", "BWardrobe.Earring_Lightning1")
    wear("biker", "BWardrobe.Glasses_Aviator_Black")
    wear("biker", "BWardrobe.Earring_Gun")
    wear("rapper", "BWardrobe.Necklace_Pendant_Cash")
    wear("rapper", "BWardrobe.Glasses_Cool_Gold")
    wear("hacker", "BWardrobe.Glasses_Pixel")
    wear("gamer", "BWardrobe.Glasses_Pixel")
    wear("artist", "BWardrobe.Glasses_Circle_Gold")
    wear("journalist", "BWardrobe.Eyeglasses_Aviator")
    wear("business_manager", "BWardrobe.Eyeglasses_Cool_Silver")
    wear("lawyer", "BWardrobe.Eyeglasses_Round_Silver")
    wear("scientist", "BWardrobe.Eyeglasses_Circle_Silver")
    wear("lab_tech", "BWardrobe.Eyeglasses_Circle_Black")
    wear("school_teacher", "BWardrobe.Eyeglasses_Round")
    wear("professor", "BWardrobe.Eyeglasses_Round_Gold")
    wear("skater", "BWardrobe.Hat_Cap_Casual_Reverse")
    wear("skater", "BWardrobe.Glasses_Cool")
    wear("hippie", "BWardrobe.Glasses_Round")
    wear("eco_activist", "BWardrobe.Hat_Cap_Casual")
    wear("cashier", "BWardrobe.Hat_Cap_Casual")
    wear("courier", "BWardrobe.Hat_Cap_Casual_Reverse")
end


function NPCCivilianArchetypesBridge.ApplyScrapSmithIntegration(profiles)
    if type(profiles) ~= "table" or not bca_hasMod("ScrapSmith") then return end

    local function wear(profileId, fullType)
        local profile = profiles[profileId]
        if profile and type(profile.wear) == "table" then
            bca_push(profile.wear, fullType)
        end
    end

    local function loot(profileId, fullType)
        local profile = profiles[profileId]
        if profile and type(profile.loot) == "table" then
            bca_push(profile.loot, fullType)
        end
    end

    wear("soldier", "ScrapSmithArmor.scrapsmith_chainmailHauberk")
    wear("soldier", "ScrapSmithArmor.scrapsmith_kettleHelm")
    wear("private_security", "ScrapSmithArmor.scrapsmith_gambeson")
    wear("private_security", "ScrapSmithArmor.scrapsmith_bascinet")
    wear("prepper", "ScrapSmithArmor.scrapsmith_gambeson")
    wear("prepper", "ScrapSmithArmor.scrapsmith_kettleHelm")
    wear("raider", "ScrapSmithArmor.scrapsmith_coatOfPlates")
    wear("raider", "ScrapSmithArmor.scrapsmith_blackenedGreatHelm")
    wear("biker", "ScrapSmithArmor.scrapsmith_chainmailHauberk")
    wear("metalhead", "ScrapSmithArmor.scrapsmith_plateCuirass")
    wear("digger", "ScrapSmithArmor.scrapsmith_gambeson")
    wear("construction_worker", "ScrapSmithArmor.scrapsmith_plateMittens")
    wear("welder", "ScrapSmithArmor.scrapsmith_plateMittens")

    loot("prepper", "ScrapSmith.scrapsmith_scrapMachete")
    loot("raider", "ScrapSmith.scrapsmith_spikedClub")
    loot("biker", "ScrapSmith.scrapsmith_warAxe")
    loot("metalhead", "ScrapSmith.scrapsmith_morningStar")
    loot("survivalist", "ScrapSmith.scrapsmith_taperedWoodenClub")
end

function NPCCivilianArchetypesBridge.ApplyBCGRareWeaponsIntegration(profiles)
    if type(profiles) ~= "table" or not bca_hasMod("BCGRareWeapons") then return end

    local function loot(profileId, fullType)
        local profile = profiles[profileId]
        if profile and type(profile.loot) == "table" then
            bca_push(profile.loot, fullType)
        end
    end

    loot("prepper", "BCGRareWeapons.ReinforcedBaseballBat")
    loot("raider", "BCGRareWeapons.VikingAxe")
    loot("biker", "BCGRareWeapons.ReinforcedBaseballBat")
    loot("survivalist", "BCGRareWeapons.VikingAxe")
end

function NPCCivilianArchetypesBridge.Ensure()
    if NPCCivilianArchetypesBridge.Ready then return end

    local profiles = {}
    local byCategory = {}

    local function add(profile)
        profiles[profile.id] = profile
        byCategory[profile.category] = byCategory[profile.category] or {}
        byCategory[profile.category][#byCategory[profile.category] + 1] = profile.id
    end

    add(bca_profile("doctor", "medical", "medic", {"Doctor", "Pharmacist", "Generic01"}, {"Base.Bag_Satchel_Medical", "Base.Gloves_LeatherGlovesBlack"}, {"Base.Bandage", "Base.AlcoholWipes", "Base.Pills", "Base.SutureNeedle"}, {discipline=1.10, morale=1.05, tags={"medical", "professional"}}))
    add(bca_profile("nurse", "medical", "medic", {"Doctor", "Pharmacist", "Generic02"}, {"Base.Bag_Satchel_Medical"}, {"Base.Bandage", "Base.AlcoholWipes", "Base.Pills"}, {discipline=1.05, tags={"medical", "support"}}))
    add(bca_profile("paramedic", "medical", "medic", {"Doctor", "Pharmacist", "Generic01"}, {"Base.Bag_Satchel_Medical", "Base.Gloves_LeatherGlovesBlack"}, {"Base.Bandage", "Base.AlcoholWipes", "Base.Disinfectant"}, {discipline=1.08, morale=1.08, tags={"medical", "field"}}))
    add(bca_profile("pharmacist", "medical", "medic", {"Pharmacist", "Generic01"}, {"Base.Bag_Satchel"}, {"Base.Pills", "Base.PillsBeta", "Base.AlcoholWipes"}, {tags={"medical", "civilian"}}))
    add(bca_profile("veterinarian", "medical", "survivor", {"Doctor", "Hunter", "Redneck"}, {"Base.Bag_Satchel"}, {"Base.Bandage", "Base.SutureNeedle"}, {tags={"medical", "rural"}}))

    add(bca_profile("school_teacher", "education", "survivor", {"Generic01", "Varsity", "Tourist"}, {"Base.Bag_Satchel"}, {"Base.Book", "Base.Pencil", "Base.Notebook"}, {discipline=1.05, tags={"civilian", "education"}}))
    add(bca_profile("professor", "education", "trader", {"Generic01", "Varsity", "Tourist"}, {"Base.Bag_Satchel"}, {"Base.Book", "Base.Notebook", "Base.Pen"}, {discipline=1.08, tags={"civilian", "education"}}))
    add(bca_profile("scientist", "science", "medic", {"HazardSuit", "Doctor", "Pharmacist"}, {"Base.Bag_Satchel", "Base.Gloves_LeatherGlovesBlack"}, {"Base.Notebook", "Base.Pen", "Base.AlcoholWipes"}, {discipline=1.08, tags={"science", "lab"}}))
    add(bca_profile("lab_tech", "science", "medic", {"HazardSuit", "Doctor", "Pharmacist", "Generic01"}, {"Base.Bag_Satchel"}, {"Base.AlcoholWipes", "Base.Notebook"}, {tags={"science", "lab"}}))

    add(bca_profile("soldier", "security", "militia", {"ArmyCamoGreen", "ArmyCamoDesert", "Veteran"}, {"Base.Vest_BulletArmy", "Base.Hat_ArmyHelmet", "Base.Bag_ALICEpack_Army", "Base.Gloves_LeatherGlovesBlack"}, {"Base.556Box", "Base.Bandage"}, {discipline=1.20, accuracyBoost=1.16, side={red=2, green=2, blue=1}, tags={"military", "combat"}}))
    add(bca_profile("police_officer", "security", "checkpoint", {"Police", "PoliceState", "PoliceRiot"}, {"Base.Vest_BulletPolice", "Base.HolsterSimple", "Base.Hat_Army"}, {"Base.9mmClip", "Base.Bandage"}, {discipline=1.16, accuracyBoost=1.08, side={green=2, blue=1}, tags={"police", "law"}}))
    add(bca_profile("firefighter", "security", "militia", {"Fireman", "Generic01", "Generic02"}, {"Base.Bag_ALICEpack_Army", "Base.Gloves_LeatherGlovesBlack", "Base.Hat_ArmyHelmet"}, {"Base.Bandage", "Base.WaterBottleFull"}, {discipline=1.12, morale=1.12, tags={"rescue", "field"}}))
    add(bca_profile("prison_guard", "security", "checkpoint", {"PrisonGuard", "Police"}, {"Base.Vest_BulletPolice", "Base.HolsterSimple"}, {"Base.9mmClip", "Base.HandTorch"}, {discipline=1.12, accuracyBoost=1.06, side={red=1, green=1}, tags={"law", "guard"}}))
    add(bca_profile("private_security", "security", "checkpoint", {"PrivateMilitia", "Police", "PoliceState"}, {"Base.Vest_BulletPolice", "Base.HolsterSimple"}, {"Base.Bandage", "Base.9mmClip"}, {discipline=1.08, accuracyBoost=1.05, side={blue=2, green=1}, tags={"guard", "contractor"}}))

    add(bca_profile("engineer", "industry", "survivor", {"Fossoil", "Gas2Go", "Generic01"}, {"Base.Bag_Satchel"}, {"Base.Screwdriver", "Base.Pencil", "Base.Notebook"}, {discipline=1.06, tags={"technical", "industry"}}))
    add(bca_profile("welder", "industry", "survivor", {"Fossoil", "Gas2Go", "Woodcut"}, {"Base.WeldingMask", "Base.Gloves_LeatherGlovesBlack", "Base.Bag_Satchel"}, {"Base.PropaneTorch", "Base.WeldingRods"}, {tags={"technical", "labor"}}))
    add(bca_profile("construction_worker", "industry", "survivor", {"Fossoil", "Woodcut", "Generic02"}, {"Base.Bag_Satchel", "Base.Gloves_LeatherGlovesBlack"}, {"Base.Hammer", "Base.NailsBox", "Base.Saw"}, {healthBonus=0.10, tags={"labor", "builder"}}))
    add(bca_profile("electrician", "industry", "survivor", {"Fossoil", "Gas2Go", "Generic02"}, {"Base.Bag_Satchel"}, {"Base.Screwdriver", "Base.ElectronicsScrap", "Base.Battery"}, {tags={"technical", "repair"}}))
    add(bca_profile("mechanic", "industry", "survivor", {"Gas2Go", "Fossoil", "Generic02"}, {"Base.Bag_Satchel", "Base.Gloves_LeatherGlovesBlack"}, {"Base.Wrench", "Base.Screwdriver", "Base.TirePump"}, {tags={"technical", "vehicles"}}))

    add(bca_profile("truck_driver", "transport", "scout", {"Gas2Go", "Fossoil", "Tourist"}, {"Base.Bag_Satchel"}, {"Base.MuldraughMap", "Base.LouisvilleMap", "Base.WaterBottleFull"}, {morale=1.05, tags={"road", "logistics"}}))
    add(bca_profile("courier", "transport", "scout", {"Generic01", "Tourist", "Varsity"}, {"Base.Bag_Satchel"}, {"Base.MuldraughMap", "Base.Pen"}, {tags={"road", "runner"}}))
    add(bca_profile("loader", "transport", "survivor", {"Fossoil", "Generic02"}, {"Base.Bag_Satchel", "Base.Gloves_LeatherGlovesBlack"}, {"Base.TinnedSoup", "Base.WaterBottleFull"}, {healthBonus=0.10, tags={"labor"}}))

    add(bca_profile("programmer", "tech", "trader", {"Generic01", "Varsity", "Tourist"}, {"Base.Bag_Satchel"}, {"Base.ElectronicsScrap", "Base.Notebook", "Base.Pen"}, {tags={"tech", "civilian"}}))
    add(bca_profile("sysadmin", "tech", "scout", {"Generic01", "Gas2Go", "Varsity"}, {"Base.Bag_Satchel"}, {"Base.Screwdriver", "Base.Battery", "Base.ElectronicsScrap"}, {tags={"tech", "repair"}}))
    add(bca_profile("hacker", "subculture", "scout", {"Varsity", "Punk", "Rocker"}, {"Base.Bag_Satchel"}, {"Base.ElectronicsScrap", "Base.Battery", "Base.Notebook"}, {side={red=1, blue=1}, tags={"tech", "subculture"}}))

    add(bca_profile("cashier", "service", "survivor", {"GigaMart_Employee", "Generic01", "Generic02"}, {"Base.Bag_Satchel"}, {"Base.Pen", "Base.WaterBottleFull"}, {tags={"service", "civilian"}}))
    add(bca_profile("bartender", "service", "trader", {"Waiter_Diner", "Waiter_Restaurant", "Generic01"}, {"Base.Bag_Satchel"}, { "Base.CigaretteSingle", "Base.Lighter"}, {tags={"service", "social"}}))
    add(bca_profile("chef", "service", "survivor", {"Chef", "Waiter_Diner", "Waiter_Restaurant"}, {"Base.Bag_Satchel"}, {"Base.KitchenKnife", "Base.CannedBeans", "Base.TinnedSoup"}, {tags={"service", "food"}}))
    add(bca_profile("cleaner", "service", "survivor", {"Generic02", "GigaMart_Employee"}, {"Base.Bag_Satchel"}, {"Base.Bleach", "Base.Towel"}, {tags={"service"}}))

    add(bca_profile("business_manager", "business", "trader", {"Generic01", "Varsity", "Tourist"}, {"Base.Bag_Satchel"}, {"Base.Pen", "Base.Notebook", "Base.CigaretteSingle"}, {discipline=1.05, tags={"business", "civilian"}}))
    add(bca_profile("lawyer", "business", "trader", {"Generic01", "Varsity"}, {"Base.Bag_Satchel"}, {"Base.Pen", "Base.Notebook"}, {discipline=1.08, tags={"law", "civilian"}}))
    add(bca_profile("journalist", "media", "scout", {"Generic01", "Tourist", "Varsity"}, {"Base.Bag_Satchel"}, {"Base.Notebook", "Base.Pen", "Base.Camera"}, {tags={"media", "scout"}}))
    add(bca_profile("artist", "media", "survivor", {"Rocker", "Tourist", "Generic01"}, {"Base.Bag_Satchel"}, {"Base.Pen", "Base.Notebook"}, {tags={"media", "civilian"}}))
    add(bca_profile("musician", "media", "survivor", {"Rocker", "Punk", "Generic01"}, {"Base.Bag_Satchel"}, {"Base.CigaretteSingle", "Base.Lighter"}, {tags={"media", "subculture"}}))

    add(bca_profile("farmer", "rural", "survivor", {"Redneck", "Hunter", "Generic02"}, {"Base.Bag_Satchel", "Base.Gloves_LeatherGlovesBlack"}, {"farming.CarrotBagSeed", "farming.PotatoBagSeed", "Base.WaterBottleFull"}, {healthBonus=0.10, side={green=2}, tags={"rural", "food"}}))
    add(bca_profile("trapper", "rural", "scout", {"Hunter", "Camper", "Redneck"}, {"Base.Bag_ALICEpack_Army", "Base.Bag_Satchel"}, {"Base.TrapMouse", "Base.HuntingKnife", "Base.WaterBottleFull"}, {accuracyBoost=1.04, side={green=2, blue=1}, tags={"rural", "scout"}}))
    add(bca_profile("fisher", "rural", "survivor", {"Tourist", "Generic01", "Hunter"}, {"Base.Bag_Satchel"}, {"Base.FishingLine", "Base.FishingTackle"}, {tags={"rural", "food"}}))

    add(bca_profile("punk", "subculture", "raider", {"Punk", "Rocker", "Thug"}, {"Base.Bag_Satchel", "Base.HolsterSimple"}, {"Base.CigaretteSingle", "Base.Lighter"}, {aggression=1.15, side={red=3}, tags={"subculture", "raider"}}))
    add(bca_profile("goth", "subculture", "raider", {"Goth", "Punk", "Rocker"}, {"Base.Bag_Satchel"}, {"Base.CigaretteSingle", "Base.Notebook"}, {side={red=1}, tags={"subculture"}}))
    add(bca_profile("metalhead", "subculture", "raider", {"Rocker", "Biker", "Punk"}, {"Base.Bag_Satchel", "Base.Gloves_LeatherGlovesBlack"}, {"Base.CigaretteSingle", "Base.Lighter"}, {aggression=1.12, side={red=2}, tags={"subculture", "raider"}}))
    add(bca_profile("rapper", "subculture", "survivor", {"Young", "Thug", "Generic01"}, {"Base.Bag_Satchel"}, {"Base.CigaretteSingle"}, {side={red=1, green=1}, tags={"subculture", "urban"}}))
    add(bca_profile("biker", "subculture", "raider", {"Biker", "Rocker"}, {"Base.Bag_Satchel", "Base.Gloves_LeatherGlovesBlack", "Base.HolsterSimple"}, {"Base.CigaretteSingle", "Base.Lighter"}, {aggression=1.18, side={red=2, blue=1}, tags={"road", "subculture"}}))
    add(bca_profile("gamer", "subculture", "trader", {"Varsity", "Young", "Generic01"}, {"Base.Bag_Satchel"}, {"Base.Battery", "Base.ElectronicsScrap"}, {tags={"subculture", "tech"}}))
    add(bca_profile("ultras", "subculture", "raider", {"SportsFan", "Thug", "Young"}, {"Base.Bag_Satchel"}, {"Base.CigaretteSingle", "Base.WaterBottleFull"}, {aggression=1.20, side={red=2}, tags={"subculture", "raider"}}))
    add(bca_profile("skater", "subculture", "scout", {"Young", "Varsity", "Punk"}, {"Base.Bag_Satchel"}, {"Base.WaterBottleFull"}, {tags={"subculture", "runner"}}))
    add(bca_profile("hippie", "subculture", "survivor", {"Tourist", "Hobbo", "Generic01"}, {"Base.Bag_Satchel"}, {"Base.CannedCorn", "Base.WaterBottleFull"}, {morale=1.05, tags={"subculture", "rural"}}))
    add(bca_profile("eco_activist", "subculture", "survivor", {"Varsity", "Tourist", "Generic01"}, {"Base.Bag_Satchel"}, {"Base.WaterBottleFull", "Base.Notebook"}, {side={green=2}, tags={"subculture", "green"}}))
    add(bca_profile("prepper", "subculture", "militia", {"Survivalist03", "Camper", "Hunter"}, {"Base.Bag_ALICEpack_Army", "Base.HolsterSimple", "Base.Gloves_LeatherGlovesBlack"}, {"Base.CannedBeans", "Base.WaterBottleFull", "Base.Bandage"}, {discipline=1.08, accuracyBoost=1.06, side={green=2, blue=1}, tags={"survival", "prepper"}}))
    add(bca_profile("digger", "subculture", "scout", {"Fossoil", "Camper", "Generic01"}, {"Base.Bag_Satchel", "Base.Gloves_LeatherGlovesBlack"}, {"Base.HandTorch", "Base.Battery", "Base.Crowbar"}, {tags={"explorer", "scout"}}))

    if bca_hasMod("Authentic Z - Current") then
        bca_push(profiles.doctor.outfits, "AuthenticSurvivorDoctor")
        bca_push(profiles.police_officer.outfits, "AuthenticSurvivorPolice")
        bca_push(profiles.biker.outfits, "AuthenticBiker")
        bca_push(profiles.prepper.outfits, "AuthenticSurvivorCovid")
        bca_push(profiles.hippie.outfits, "AuthenticHomeless")
    end
    if bca_hasMod("Brita_2") then
        bca_push(profiles.soldier.outfits, "Brita_Gorka")
        bca_push(profiles.private_security.outfits, "Brita_Hunter_2")
        bca_push(profiles.punk.outfits, "Brita_Killa_2")
    end

    NPCCivilianArchetypesBridge.ApplyBWardrobeIntegration(profiles)
    NPCCivilianArchetypesBridge.ApplyScrapSmithIntegration(profiles)
    NPCCivilianArchetypesBridge.ApplyBCGRareWeaponsIntegration(profiles)

    NPCCivilianArchetypesBridge.Profiles = profiles
    NPCCivilianArchetypesBridge.ByCategory = byCategory
    NPCCivilianArchetypesBridge.Ready = true
end

function NPCCivilianArchetypesBridge.GetProfile(id)
    NPCCivilianArchetypesBridge.Ensure()
    return NPCCivilianArchetypesBridge.Profiles[tostring(id or "")]
end

function NPCCivilianArchetypesBridge.GetOutfits(profile)
    if type(profile) ~= "table" then return {} end
    return bca_copy(profile.outfits)
end

local function bca_weightedPick(ids, member, salt)
    NPCCivilianArchetypesBridge.Ensure()
    if type(ids) ~= "table" or #ids == 0 then return nil end
    local total = 0
    local weighted = {}
    local side = tostring(member and (member.factionSide or member.side or member.faction or member.patrolColor) or "")
    for _, id in ipairs(ids) do
        local profile = NPCCivilianArchetypesBridge.Profiles[id]
        if profile then
            local weight = tonumber(profile.groupWeight) or 1
            if type(profile.side) == "table" and profile.side[side] then
                weight = weight * tonumber(profile.side[side])
            end
            if weight > 0 then
                total = total + weight
                weighted[#weighted + 1] = {id=id, ceiling=total}
            end
        end
    end
    if total <= 0 or #weighted == 0 then return ids[1] end
    local roll = (math.abs(bca_seed(member, salt or "pick")) % math.max(1, math.floor(total * 100))) / 100
    for _, entry in ipairs(weighted) do
        if roll <= entry.ceiling then return entry.id end
    end
    return weighted[#weighted].id
end

function NPCCivilianArchetypesBridge.ResolveForMember(member)
    NPCCivilianArchetypesBridge.Ensure()
    if type(member) ~= "table" then return nil end
    if member.professionArchetype then return NPCCivilianArchetypesBridge.GetProfile(member.professionArchetype) end

    local side = tostring(member.factionSide or member.side or member.faction or member.patrolColor or "")
    local role = tostring(member.tacticalRole or member.role or member.strategicRole or "")
    local archetype = tostring(member.baseArchetype or member.baseStyle or member.behaviorStyle or "")
    local outfit = string.lower(tostring(member.outfit or ""))

    if member.blackMarket == true or member.blackMarketNPC == true or member.special == "BlackMarket" then
        return NPCCivilianArchetypesBridge.GetProfile(bca_weightedPick({"bartender", "business_manager", "lawyer"}, member, "market"))
    end
    if role == "leader" or member.commandAura then
        if side == "red" then return NPCCivilianArchetypesBridge.GetProfile(bca_weightedPick({"biker", "punk", "metalhead", "soldier"}, member, "red_leader")) end
        if side == "green" then return NPCCivilianArchetypesBridge.GetProfile(bca_weightedPick({"prepper", "police_officer", "farmer", "soldier"}, member, "green_leader")) end
        if side == "blue" then return NPCCivilianArchetypesBridge.GetProfile(bca_weightedPick({"private_security", "soldier", "paramedic"}, member, "blue_leader")) end
        return NPCCivilianArchetypesBridge.GetProfile(bca_weightedPick({"business_manager", "prepper", "police_officer"}, member, "leader"))
    end
    if member.mercenary or member.mercenaryElite then
        return NPCCivilianArchetypesBridge.GetProfile(bca_weightedPick({"private_security", "soldier", "paramedic", "mechanic"}, member, "merc"))
    end
    if archetype == "military" or archetype == "elite_safehouse" then
        return NPCCivilianArchetypesBridge.GetProfile(bca_weightedPick({"soldier", "private_security", "paramedic"}, member, "military"))
    end
    if archetype == "checkpoint" or role == "checkpoint_guard" or role == "road_guard" then
        return NPCCivilianArchetypesBridge.GetProfile(bca_weightedPick({"police_officer", "prison_guard", "private_security", "truck_driver"}, member, "checkpoint"))
    end
    if archetype == "raider" then
        return NPCCivilianArchetypesBridge.GetProfile(bca_weightedPick({"punk", "biker", "metalhead", "ultras", "digger"}, member, "raider"))
    end
    if archetype == "punk" then
        return NPCCivilianArchetypesBridge.GetProfile(bca_weightedPick({"punk", "goth", "metalhead", "skater"}, member, "punk"))
    end
    if string.find(outfit, "doctor", 1, true) or string.find(outfit, "nurse", 1, true) or string.find(outfit, "hospital", 1, true) then
        return NPCCivilianArchetypesBridge.GetProfile(bca_weightedPick({"doctor", "nurse", "paramedic"}, member, "medical_outfit"))
    end
    if string.find(outfit, "hazard", 1, true) or string.find(outfit, "scient", 1, true) then
        return NPCCivilianArchetypesBridge.GetProfile(bca_weightedPick({"scientist", "lab_tech"}, member, "science_outfit"))
    end
    if string.find(outfit, "police", 1, true) then
        return NPCCivilianArchetypesBridge.GetProfile("police_officer")
    end
    if string.find(outfit, "fire", 1, true) then
        return NPCCivilianArchetypesBridge.GetProfile("firefighter")
    end
    if string.find(outfit, "construction", 1, true) or string.find(outfit, "mechanic", 1, true) then
        return NPCCivilianArchetypesBridge.GetProfile(bca_weightedPick({"construction_worker", "mechanic", "welder", "electrician"}, member, "industry_outfit"))
    end
    if string.find(outfit, "biker", 1, true) then return NPCCivilianArchetypesBridge.GetProfile("biker") end
    if string.find(outfit, "punk", 1, true) then return NPCCivilianArchetypesBridge.GetProfile("punk") end
    if string.find(outfit, "rocker", 1, true) then return NPCCivilianArchetypesBridge.GetProfile("metalhead") end
    if string.find(outfit, "farmer", 1, true) or string.find(outfit, "hunter", 1, true) then
        return NPCCivilianArchetypesBridge.GetProfile(bca_weightedPick({"farmer", "trapper", "prepper"}, member, "rural_outfit"))
    end

    if side == "red" then return NPCCivilianArchetypesBridge.GetProfile(bca_weightedPick({"punk", "biker", "metalhead", "ultras", "hacker", "digger"}, member, "red")) end
    if side == "green" then return NPCCivilianArchetypesBridge.GetProfile(bca_weightedPick({"prepper", "farmer", "construction_worker", "trapper", "police_officer", "paramedic", "eco_activist"}, member, "green")) end
    if side == "blue" then return NPCCivilianArchetypesBridge.GetProfile(bca_weightedPick({"private_security", "soldier", "paramedic", "mechanic", "sysadmin"}, member, "blue")) end

    return NPCCivilianArchetypesBridge.GetProfile(bca_weightedPick({"truck_driver", "cashier", "school_teacher", "chef", "mechanic", "programmer", "farmer", "prepper", "gamer", "digger"}, member, "civilian"))
end

function NPCCivilianArchetypesBridge.PickOutfit(profile, member)
    local outfits = NPCCivilianArchetypesBridge.GetOutfits(profile)
    return bca_pick(outfits, bca_seed(member, "outfit:" .. tostring(profile and profile.id or "")))
end

function NPCCivilianArchetypesBridge.PickWear(profile, member)
    local out = {}
    if type(profile) ~= "table" or type(profile.wear) ~= "table" then return out end
    for i = 1, #profile.wear do
        local fullType = profile.wear[i]
        local chance = 70
        if i == 1 then chance = 92 elseif i == 2 then chance = 74 elseif i == 3 then chance = 54 else chance = 34 end
        if (math.abs(bca_seed(member, "wear:" .. tostring(profile.id) .. ":" .. tostring(i))) % 100) < chance then
            out[#out + 1] = fullType
        end
    end
    return out
end

function NPCCivilianArchetypesBridge.PickLoot(profile, member)
    local out = {}
    if type(profile) ~= "table" or type(profile.loot) ~= "table" then return out end
    for i = 1, #profile.loot do
        if (math.abs(bca_seed(member, "loot:" .. tostring(profile.id) .. ":" .. tostring(i))) % 100) < 38 then
            out[#out + 1] = profile.loot[i]
        end
    end
    return out
end
