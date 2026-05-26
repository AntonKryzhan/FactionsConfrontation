NPCLoadoutRegistry = NPCLoadoutRegistry or {}
local Registry = NPCLoadoutRegistry

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

function Registry.HasAnyMod(modIds)
    if type(modIds) ~= "table" then return Registry.HasMod(modIds) end
    for i = 1, #modIds do
        if Registry.HasMod(modIds[i]) then return true end
    end
    return false
end

function Registry.IsArsenalGunfighterActive()
    return Registry.HasAnyMod({"Arsenal(26)GunFighter[MAIN MOD 2.0]", "Arsenal(26)GunFighter"})
end

function Registry.IsBritaWeaponPackActive()
    return Registry.HasMod("Brita")
end

function Registry.IsBritaArsenalActive()
    return Registry.IsArsenalGunfighterActive() or (Registry.IsBritaWeaponPackActive() and Registry.IsArsenalGunfighterActive())
end

function Registry.IsBWardrobeActive()
    return Registry.HasMod("BWardrobe")
end

function Registry.IsPSAActive()
    return Registry.HasMod("PRitemtest")
end

function Registry.IsBCGRareWeaponsActive()
    return Registry.HasMod("BCGRareWeapons")
end

function Registry.IsScrapSmithActive()
    return Registry.HasMod("ScrapSmith")
end

function Registry.IsScrapSmithBuhurtPracticionerActive()
    return Registry.HasMod("ScrapSmithBuhurtPracticioner")
end

function Registry.MakeFirearm(name, magName, magSize, shotSound, shotDelay, ammoName)
    return {
        name = name,
        magName = magName,
        magSize = magSize,
        bulletsLeft = magSize,
        shotSound = shotSound,
        shotDelay = shotDelay,
        ammoName = ammoName
    }
end

function Registry.CopySpec(weapon)
    if not weapon then return nil end
    local copy = {}
    for key, value in pairs(weapon) do
        copy[key] = value
    end
    return copy
end

function Registry.UpsertByName(target, weapon)
    if not target or not weapon or not weapon.name then return nil end
    for i = 1, #target do
        if target[i] and target[i].name == weapon.name then
            target[i] = weapon
            return weapon
        end
    end
    target[#target + 1] = weapon
    return weapon
end

function Registry.ItemExists(fullType)
    if fullType == nil or fullType == false then return true end
    if not InventoryItemFactory or not InventoryItemFactory.CreateItem then return true end
    local ok, item = pcall(function() return InventoryItemFactory.CreateItem(fullType) end)
    return ok and item ~= nil
end

function Registry.FirearmSpecExists(spec)
    if type(spec) ~= "table" then return false end
    if not Registry.ItemExists(spec[1]) then return false end
    if spec[2] ~= nil and spec[2] ~= false and not Registry.ItemExists(spec[2]) then return false end
    if spec[6] ~= nil and spec[6] ~= false and not Registry.ItemExists(spec[6]) then return false end
    return true
end

function Registry.AppendFirearms(target, specs, makeFirearm)
    if not target or not specs then return target end
    local builder = makeFirearm or Registry.MakeFirearm
    for i = 1, #specs do
        local spec = specs[i]
        if Registry.FirearmSpecExists and Registry.FirearmSpecExists(spec) or (not Registry.FirearmSpecExists and Registry.ItemExists(spec[1])) then
            target[#target + 1] = builder(spec[1], spec[2], spec[3], spec[4], spec[5], spec[6])
        end
    end
    return target
end

function Registry.AppendFirearmsUnique(target, specs, makeFirearm, source)
    if not target or not specs then return target end
    local builder = makeFirearm or Registry.MakeFirearm
    for i = 1, #specs do
        local spec = specs[i]
        if Registry.FirearmSpecExists and Registry.FirearmSpecExists(spec) or (not Registry.FirearmSpecExists and Registry.ItemExists(spec[1])) then
            local weapon = builder(spec[1], spec[2], spec[3], spec[4], spec[5], spec[6])
            if weapon and source then weapon.source = source end
            Registry.UpsertByName(target, weapon)
        end
    end
    return target
end

function Registry.AppendMelee(target, specs)
    if not target or not specs then return target end
    for i = 1, #specs do
        local name = specs[i]
        if Registry.ItemExists(name) then
            local exists = false
            for j = 1, #target do
                if target[j] == name then
                    exists = true
                    break
                end
            end
            if not exists then
                target[#target + 1] = name
            end
        end
    end
    return target
end

function Registry.AppendWear(target, specs)
    if not target or not specs then return target end
    for i = 1, #specs do
        local name = specs[i]
        if Registry.ItemExists(name) then
            local exists = false
            for j = 1, #target do
                if target[j] == name then
                    exists = true
                    break
                end
            end
            if not exists then
                target[#target + 1] = name
            end
        end
    end
    return target
end

function Registry.AppendViaRegister(specs, registerFn)
    if not specs or not registerFn then return end
    for i = 1, #specs do
        local spec = specs[i]
        registerFn(spec[1], spec[2], spec[3], spec[4], spec[5], spec[6])
    end
end

Registry.VanillaPrimary = {
    {"Base.AssaultRifle2", "Base.M14Clip", 20, "M14Shoot", 38},
    {"Base.AssaultRifle", "Base.556Clip", 30, "M14Shoot", 12},
}

Registry.VanillaSecondary = {
    {"Base.Pistol", "Base.9mmClip", 15, "M9Shoot", 35},
    {"Base.Pistol2", "Base.45Clip", 7, "M1911Shoot", 47},
    {"Base.Pistol3", "Base.44Clip", 8, "DesertEagleShoot", 45},
}

Registry.BritaArsenalPrimary = {
    {"Base.CMR_30", "Base.CP33Clip", 33, "M9Shoot", 18, "Base.Bullets22"},
    {"Base.CMR_30_Fold", "Base.CP33Clip", 33, "M9Shoot", 24, "Base.Bullets22"},
    {"Base.Moss500_20", false, 5, "JS2000ShotgunShoot", 38, "Base.20gShotgunShells"},
    {"Base.Ruger_PCC", "Base.9mmClip", 15, "M9Shoot", 20, "Base.Bullets9mm"},
    {"Base.Ruger_PCC_R", "Base.9mmClip", 15, "M9Shoot", 20, "Base.Bullets9mm"},
    {"Base.Ruger_PCC_M", "Base.9mmClip", 15, "M9Shoot", 20, "Base.Bullets9mm"},
    {"Base.ROYAL_SXS", false, 2, "DoubleBarrelShotgunShoot", 42, "Base.10gShotgunShells"},
    {"Base.10855_Silver", false, 4, "JS2000ShotgunShoot", 38, "Base.20gShotgunShells"},
    {"Base.LVOA_C", "Base.556Clip", 30, "M16Shoot", 30, "Base.556Bullets"},
    {"Base.ADAR", "Base.556Clip", 30, "M16Shoot", 30, "Base.556Bullets"},
    {"Base.MK47", "Base.AKClip", 30, "M16Shoot", 32, "Base.762x39Bullets"},
    {"Base.AAC_Honey", "Base.556Clip", 30, "M16Shoot", 30, "Base.556Bullets"},
    {"Base.AAC_Honey_Fold", "Base.556Clip", 30, "M16Shoot", 36, "Base.556Bullets"},
    {"Base.AAC_HoneySD", "Base.556Clip", 30, "SDshot", 30, "Base.556Bullets"},
    {"Base.AAC_HoneySD_Fold", "Base.556Clip", 30, "SDShot", 36, "Base.556Bullets"},
    {"Base.Bush_AR15_MOE", "Base.556Clip", 30, "M16Shoot", 29, "Base.556Bullets"},
    {"Base.Bush_XM15", "Base.556Clip", 30, "M16Shoot", 29, "Base.556Bullets"},
    {"Base.TR1_UltraLight", "Base.556Clip", 30, "M16Shoot", 30, "Base.556Bullets"},
    {"Base.K2_ADVK2", "Base.556Clip", 30, "M16Shoot", 30, "Base.556Bullets"},
    {"Base.K2_Grunt", "Base.556Clip", 30, "M16Shoot", 30, "Base.556Bullets"},
    {"Base.K1A_DEV", "Base.556Clip", 30, "M16Shoot", 30, "Base.556Bullets"},
    {"Base.K1A_DEV_Fold", "Base.556Clip", 30, "M16Shoot", 36, "Base.556Bullets"},
    {"Base.MCX_Spear", "Base.308ExtClip", 20, "M16Shoot", 36, "Base.308Bullets"},
    {"Base.MCX_Virtus", "Base.556Clip", 30, "M16Shoot", 30, "Base.556Bullets"},
    {"Base.MCX_VirtusPatrol", "Base.556Clip", 30, "M16Shoot", 29, "Base.556Bullets"},
    {"Base.MCX_Socom", "Base.556Clip", 30, "SDShot", 30, "Base.556Bullets"},
    {"Base.JW3_TTI_MPX", "Base.9mmClip", 15, "M9Shoot", 20, "Base.Bullets9mm"},
    {"Base.Ruger_1022", "Base.22Clip", 10, "M9Shoot", 19, "Base.Bullets22"},
    {"Base.Marlin_M70", "Base.22Clip", 10, "M9Shoot", 19, "Base.Bullets22"},
    {"Base.Cricket_22", false, 1, "MSR700Shoot", 19, "Base.Bullets22"},
    {"Base.AR7", "Base.22Clip", 10, "M9Shoot", 19, "Base.Bullets22"},
    {"Base.AR7_Fold", "Base.22Clip", 10, "M16Shoot", 20, "Base.Bullets22"},
    {"Base.American180", "Base.22Drum", 100, "M9Shoot", 18, "Base.Bullets22"},
    {"Base.ZIP22", "Base.22Clip", 10, "M9Shoot", 26, "Base.Bullets22"},
    {"Base.AK74", "Base.545StdClip", 30, "M14Shoot", 30, "Base.545x39Bullets"},
    {"Base.AKS74", "Base.545StdClip", 30, "M14Shoot", 31, "Base.545x39Bullets"},
    {"Base.AKS74_Fold", "Base.545StdClip", 30, "M14Shoot", 31, "Base.545x39Bullets"},
    {"Base.AKS74U", "Base.545StdClip", 30, "M14Shoot", 31, "Base.545x39Bullets"},
    {"Base.AKS74U_Fold", "Base.545StdClip", 30, "M14Shoot", 31, "Base.545x39Bullets"},
    {"Base.AK12", "Base.545StdClip", 30, "M14Shoot", 30, "Base.545x39Bullets"},
    {"Base.AK12_Fold", "Base.545StdClip", 30, "M14Shoot", 31, "Base.545x39Bullets"},
    {"Base.AK74_Alpha", "Base.545StdClip", 30, "M14Shoot", 31, "Base.545x39Bullets"},
    {"Base.AK74_Alpha_Fold", "Base.545StdClip", 30, "M14Shoot", 37, "Base.545x39Bullets"},
    {"Base.RPK74", "Base.545StdClip", 30, "M14Shoot", 29, "Base.545x39Bullets"},
    {"Base.AN94", "Base.545StdClip", 30, "M14Shoot", 30, "Base.545x39Bullets"},
    {"Base.AK47", "Base.AKClip", 30, "M14Shoot", 31, "Base.762x39Bullets"},
    {"Base.AKM", "Base.AKClip", 30, "M14Shoot", 31, "Base.762x39Bullets"},
    {"Base.AK103", "Base.AKClip", 30, "M14Shoot", 31, "Base.762x39Bullets"},
    {"Base.M85_Stock", "Base.556Clip", 30, "M14Shoot", 30, "Base.556Bullets"},
    {"Base.M85_Fold", "Base.556Clip", 30, "M14Shoot", 36, "Base.556Bullets"},
    {"Base.MD65_Stock", "Base.AKClip", 30, "M14Shoot", 32, "Base.762x39Bullets"},
    {"Base.MD65_Fold", "Base.AKClip", 30, "M14Shoot", 38, "Base.762x39Bullets"},
    {"Base.AKMS_Stock", "Base.AKClip", 30, "M14Shoot", 32, "Base.762x39Bullets"},
    {"Base.AKMS_Fold", "Base.AKClip", 30, "M14Shoot", 38, "Base.762x39Bullets"},
    {"Base.Bizon2_01_Stock", "Base.9mmDrum", 50, "M9Shoot", 21, "Base.Bullets9mm"},
    {"Base.Bizon2_01_Fold", "Base.9mmDrum", 50, "M9Shoot", 27, "Base.Bullets9mm"},
    {"Base.XM117", "Base.556Clip", 30, "M16Shoot", 30, "Base.556Bullets"},
    {"Base.H416", "Base.556Clip", 30, "M16Shoot", 30, "Base.556Bullets"},
    {"Base.AR18", "Base.556Clip", 30, "M16Shoot", 30, "Base.556Bullets"},
    {"Base.AR18_Fold", "Base.556Clip", 30, "M16Shoot", 36, "Base.556Bullets"},
    {"Base.AUG9", "Base.9mmClip", 15, "M9Shoot", 20, "Base.Bullets9mm"},
    {"Base.AUG9_Grip", "Base.9mmClip", 15, "M9Shoot", 18, "Base.Bullets9mm"},
    {"Base.AUG", "Base.556Clip", 30, "M16Shoot", 30, "Base.556Bullets"},
    {"Base.AUG_Grip", "Base.556Clip", 30, "M16Shoot", 28, "Base.556Bullets"},
    {"Base.AUG_A3", "Base.556Clip", 30, "M16Shoot", 30, "Base.556Bullets"},
    {"Base.AUG_A3_Grip", "Base.556Clip", 30, "M16Shoot", 28, "Base.556Bullets"},
    {"Base.BT380_Stock", "Base.380StdClip", 15, "M9Shoot", 20, "Base.Bullets380"},
    {"Base.BT380_Fold", "Base.380StdClip", 15, "M9Shoot", 26, "Base.Bullets380"},
    {"Base.BT9_Stock", "Base.9mmClip", 15, "M9Shoot", 21, "Base.Bullets9mm"},
    {"Base.BT9_Fold", "Base.9mmClip", 15, "M9Shoot", 27, "Base.Bullets9mm"},
    {"Base.Sako85", false, 5, "MSR700Shoot", 28, "Base.223Bullets"},
    {"Base.Savage12", false, 5, "MSR788Shoot", 34, "Base.308Bullets"},
    {"Base.L96", "Base.308StdClip", 10, "M14Shoot", 33, "Base.308Bullets"},
    {"Base.F2000", "Base.556Clip", 30, "M16Shoot", 30, "Base.556Bullets"},
    {"Base.Tavor", "Base.556Clip", 30, "M16Shoot", 30, "Base.556Bullets"},
    {"Base.QBZ_95", "Base.556Clip", 30, "M16Shoot", 30, "Base.556Bullets"},
    {"Base.FAMAS", "Base.556Clip", 30, "M16Shoot", 29, "Base.556Bullets"},
    {"Base.FAMAS_G2", "Base.556Clip", 30, "M16Shoot", 29, "Base.556Bullets"},
    {"Base.FAMAS_Felin", "Base.556Clip", 30, "M16Shoot", 29, "Base.556Bullets"},
    {"Base.K5", "Base.9mmClip", 15, "M9Shoot", 27, "Base.Bullets9mm"},
    {"Base.K7_Stock", "Base.9mmClip", 15, "SD9mmShot", 20, "Base.Bullets9mm"},
    {"Base.K7_Fold", "Base.9mmClip", 15, "SD9mmShot", 26, "Base.Bullets9mm"},
    {"Base.K14", "Base.308StdClip", 10, "M14Shoot", 34, "Base.308Bullets"},
    {"Base.K2C1_PH", "Base.556Clip", 30, "M16Shoot", 30, "Base.556Bullets"},
    {"Base.K2_C1", "Base.556Clip", 30, "M16Shoot", 30, "Base.556Bullets"},
    {"Base.K2_1", "Base.556Clip", 30, "M16Shoot", 30, "Base.556Bullets"},
    {"Base.K2_203", "Base.556Clip", 30, "M16Shoot", 30, "Base.556Bullets"},
    {"Base.K1DEV", "Base.556Clip", 30, "M16Shoot", 30, "Base.556Bullets"},
    {"Base.K1_1", "Base.556Clip", 30, "M16Shoot", 30, "Base.556Bullets"},
    {"Base.K1_1_Fold", "Base.556Clip", 30, "M16Shoot", 30, "Base.556Bullets"},
    {"Base.DR_200", "Base.556Clip", 30, "M16Shoot", 30, "Base.556Bullets"},
    {"Base.EVO_Fold", "Base.9mmClip", 15, "M9Shoot", 26, "Base.Bullets9mm"},
    {"Base.EVO_Stock", "Base.9mmClip", 15, "M9Shoot", 20, "Base.Bullets9mm"},
    {"Base.FAL", "Base.308ExtClip", 20, "M14Shoot", 35, "Base.308Bullets"},
    {"Base.FAL_PARA_Stock", "Base.308ExtClip", 20, "M14Shoot", 35, "Base.308Bullets"},
    {"Base.FAL_PARA_Fold", "Base.308ExtClip", 20, "M14Shoot", 42, "Base.308Bullets"},
    {"Base.FN_FNC", "Base.556Clip", 30, "M14Shoot", 29, "Base.556Bullets"},
    {"Base.FN_FNC_Fold", "Base.556Clip", 30, "M14Shoot", 36, "Base.556Bullets"},
    {"Base.Galil", "Base.308ExtClip", 20, "M14Shoot", 35, "Base.308Bullets"},
    {"Base.Galil_Fold", "Base.308ExtClip", 20, "M14Shoot", 42, "Base.308Bullets"},
    {"Base.Galil_Sniper", "Base.308ExtClip", 20, "M14Shoot", 34, "Base.308Bullets"},
    {"Base.Galil_Sniper_Fold", "Base.308ExtClip", 20, "M14Shoot", 41, "Base.308Bullets"},
    {"Base.G33", "Base.556Clip", 30, "M16Shoot", 29, "Base.556Bullets"},
    {"Base.G3", "Base.308ExtClip", 20, "M16Shoot", 35, "Base.308Bullets"},
    {"Base.G28", "Base.308ExtClip", 20, "M16Shoot", 34, "Base.308Bullets"},
    {"Base.MK18", "Base.556Clip", 30, "M16Shoot", 30, "Base.556Bullets"},
    {"Base.G36", "Base.556Clip", 30, "M16Shoot", 29, "Base.556Bullets"},
    {"Base.G36_Fold", "Base.556Clip", 30, "M16Shoot", 36, "Base.556Bullets"},
    {"Base.G36C", "Base.556Clip", 30, "M16Shoot", 30, "Base.556Bullets"},
    {"Base.G36C_Fold", "Base.556Clip", 30, "M16Shoot", 37, "Base.556Bullets"},
    {"Base.G36KV", "Base.556Clip", 30, "M16Shoot", 30, "Base.556Bullets"},
    {"Base.G36KV_Fold", "Base.556Clip", 30, "M16Shoot", 36, "Base.556Bullets"},
    {"Base.G11K3", "Base.P90Clip", 50, "M16Shoot", 18, "Base.Bullets57"},
    {"Base.PSG1", "Base.308StdClip", 10, "M16Shoot", 33, "Base.308Bullets"},
    {"Base.MSG90", "Base.308StdClip", 10, "M16Shoot", 34, "Base.308Bullets"},
    {"Base.Type20", "Base.556Clip", 30, "M16Shoot", 30, "Base.556Bullets"},
    {"Base.Type89", "Base.556Clip", 30, "M16Shoot", 30, "Base.556Bullets"},
    {"Base.Type89_Fold", "Base.556Clip", 30, "M16Shoot", 36, "Base.556Bullets"},
    {"Base.Type64", "Base.308ExtClip", 20, "M14Shoot", 36, "Base.308Bullets"},
    {"Base.KRISS_Stock", "Base.45DSClip", 13, "M1911Shoot", 22, "Base.Bullets45"},
    {"Base.KRISS_Fold", "Base.45DSClip", 13, "M1911Shoot", 28, "Base.Bullets45"},
    {"Base.KRISS9_Stock", "Base.9mmClip", 15, "M9Shoot", 20, "Base.Bullets9mm"},
    {"Base.KRISS9_Fold", "Base.9mmClip", 15, "M9Shoot", 26, "Base.Bullets9mm"},
    {"Base.KRISS9_MLOK_Stock", "Base.9mmClip", 15, "M9Shoot", 20, "Base.Bullets9mm"},
    {"Base.KRISS9_MLOK_Fold", "Base.9mmClip", 15, "M9Shoot", 26, "Base.Bullets9mm"},
    {"Base.KRISS22_MK11_Stock", "Base.22Clip", 10, "M9Shoot", 18, "Base.Bullets22"},
    {"Base.KRISS22_MK11_Fold", "Base.22Clip", 10, "M9Shoot", 24, "Base.Bullets22"},
    {"Base.KRISS22_CRB_Stock", "Base.22Clip", 10, "SDShot", 18, "Base.Bullets22"},
    {"Base.KRISS22_CRB_Fold", "Base.22Clip", 10, "SDShot", 24, "Base.Bullets22"},
    {"Base.L85", "Base.556Clip", 30, "M16Shoot", 29, "Base.556Bullets"},
    {"Base.L85A2", "Base.556Clip", 30, "M16Shoot", 29, "Base.556Bullets"},
    {"Base.L86", "Base.556Clip", 30, "M16Shoot", 27, "Base.556Bullets"},
    {"Base.L22", "Base.556Clip", 30, "M16Shoot", 28, "Base.556Bullets"},
    {"Base.Win_1894", false, 10, "MSR700Shoot", 28, "Base.Bullets44"},
    {"Base.Win_1895", false, 6, "MSR788Shoot", 36, "Base.308Bullets"},
    {"Base.Viper", false, 11, "MSR700Shoot", 29, "Base.223Bullets"},
    {"Base.Winchester1903", false, 10, "MSR700Shoot", 18, "Base.Bullets22"},
    {"Base.Winchester1873", false, 14, "MSR700Shoot", 27, "Base.Bullets45LC"},
    {"Base.Winchester1866", false, 13, "MSR700Shoot", 28, "Base.Bullets45LC"},
    {"Base.M240", "Base.308Belt", 100, "M14Shoot", 29, "Base.308Bullets"},
    {"Base.M240_Bipod", "Base.308Belt", 100, "M14Shoot", 29, "Base.308Bullets"},
    {"Base.K12", "Base.308Belt", 100, "M14Shoot", 30, "Base.308Bullets"},
    {"Base.MG42", "Base.308Belt", 100, "M14Shoot", 31, "Base.308Bullets"},
    {"Base.MG42_Bipod", "Base.308Belt", 100, "M14Shoot", 31, "Base.308Bullets"},
    {"Base.M60", "Base.308Belt", 100, "M14Shoot", 31, "Base.308Bullets"},
    {"Base.M60_Bipod", "Base.308Belt", 100, "M14Shoot", 31, "Base.308Bullets"},
    {"Base.MK43", "Base.308Belt", 100, "M14Shoot", 32, "Base.308Bullets"},
    {"Base.G21LMG", "Base.308Belt", 100, "M14Shoot", 33, "Base.308Bullets"},
    {"Base.G21LMG_Bipod", "Base.308Belt", 100, "M14Shoot", 33, "Base.308Bullets"},
    {"Base.M249", "Base.556Belt", 100, "M16Shoot", 27, "Base.556Bullets"},
    {"Base.M249E3", "Base.556Belt", 100, "M16Shoot", 27, "Base.556Bullets"},
    {"Base.M249E3_Fold", "Base.556Belt", 100, "M16Shoot", 34, "Base.556Bullets"},
    {"Base.K3LMG", "Base.556Belt", 100, "M16Shoot", 27, "Base.556Bullets"},
    {"Base.K3LMG_Bipod", "Base.556Belt", 100, "M16Shoot", 27, "Base.556Bullets"},
    {"Base.Shrike", "Base.556Belt", 100, "M16Shoot", 29, "Base.556Bullets"},
    {"Base.PKM", "Base.762x54rBelt", 100, "M14Shoot", 32, "Base.762x54rBullets"},
    {"Base.RPD", "Base.762x39Belt", 100, "M14Shoot", 29, "Base.762x39Bullets"},
    {"Base.RPD_Bipod", "Base.762x39Belt", 100, "M14Shoot", 29, "Base.762x39Bullets"},
    {"Base.M14", "Base.308ExtClip", 20, "M14Shoot", 35, "Base.308Bullets"},
    {"Base.M14EBR", "Base.308ExtClip", 20, "M14Shoot", 34, "Base.308Bullets"},
    {"Base.M14EBR_Fold", "Base.308ExtClip", 20, "M14Shoot", 41, "Base.308Bullets"},
    {"Base.M16A1", "Base.556Clip", 30, "M16Shoot", 30, "Base.556Bullets"},
    {"Base.M16A2", "Base.556Clip", 30, "M16Shoot", 30, "Base.556Bullets"},
    {"Base.M16A3", "Base.556Clip", 30, "M16Shoot", 30, "Base.556Bullets"},
    {"Base.M16Wood", "Base.556Clip", 30, "M16Shoot", 30, "Base.556Bullets"},
    {"Base.M16Tape", "Base.556Clip", 30, "M16Shoot", 30, "Base.556Bullets"},
    {"Base.M1Carbine", "Base.9mmClip", 15, "M9Shoot", 20, "Base.Bullets9mm"},
    {"Base.M2Carbine", "Base.9mmClip", 15, "M9Shoot", 20, "Base.Bullets9mm"},
    {"Base.M40", false, 5, "M14Shoot", 34, "Base.308Bullets"},
    {"Base.M40A1", false, 5, "M14Shoot", 34, "Base.308Bullets"},
}

Registry.BritaArsenalSecondary = {
    {"Base.CZ75", "Base.9mmClip", 15, "M9Shoot", 27, "Base.Bullets9mm"},
    {"Base.CZ_75_SP01_SS", "Base.9mmClip", 15, "M9Shoot", 26, "Base.Bullets9mm"},
    {"Base.CZ_75b", "Base.9mmClip", 15, "M9Shoot", 27, "Base.Bullets9mm"},
    {"Base.CZ_75_Compact", "Base.9mmClip", 15, "M9Shoot", 28, "Base.Bullets9mm"},
    {"Base.CZ_75_SP01", "Base.9mmClip", 15, "M9Shoot", 26, "Base.Bullets9mm"},
    {"Base.CZ_75_P01", "Base.9mmClip", 15, "M9Shoot", 27, "Base.Bullets9mm"},
    {"Base.CZ_75_Shadow", "Base.9mmClip", 15, "M9Shoot", 26, "Base.Bullets9mm"},
    {"Base.CZ_75_Czechmate", "Base.9mmClip", 15, "M9Shoot", 26, "Base.Bullets9mm"},
    {"Base.CZ97B", "Base.45DSClip", 13, "M9Shoot", 29, "Base.Bullets45"},
    {"Base.CZ_2075", "Base.9mmClip", 15, "M9Shoot", 28, "Base.Bullets9mm"},
    {"Base.EAA_Witness_9", "Base.9mmClip", 15, "M9Shoot", 26, "Base.Bullets9mm"},
    {"Base.EAA_Witness_45", "Base.45DSClip", 13, "M9Shoot", 29, "Base.Bullets45"},
    {"Base.EAA_Witness_Long_9", "Base.9mmClip", 15, "M9Shoot", 26, "Base.Bullets9mm"},
    {"Base.EAA_Witness_Long_45", "Base.45DSClip", 13, "M9Shoot", 29, "Base.Bullets45"},
    {"Base.DEagle_Long", "Base.44Clip", 8, "DesertEagleShoot", 34, "Base.Bullets44"},
    {"Base.DEagle_Hawk", "Base.50Clip", 7, "DesertEagleShoot", 39, "Base.Bullets50MAG"},
    {"Base.Revolver_Short", false, 6, "M625Shoot", 26, "Base.Bullets38"},
    {"Base.Revolver_Short_357", false, 6, "M625Shoot", 31, "Base.Bullets357"},
    {"Base.Revolver", false, 6, "M625Shoot", 26, "Base.Bullets38"},
    {"Base.Revolver_357", false, 6, "M625Shoot", 31, "Base.Bullets357"},
    {"Base.Revolver_Long", false, 6, "M625Shoot", 26, "Base.Bullets38"},
    {"Base.Revolver_Long_357", false, 6, "M625Shoot", 31, "Base.Bullets357"},
    {"Base.AMT1911", "Base.45Clip", 7, "M1911Shoot", 29, "Base.Bullets45"},
    {"Base.AMT1911_Long", "Base.45Clip", 7, "M1911Shoot", 29, "Base.Bullets45"},
    {"Base.M1911_Carbine", "Base.45Clip", 7, "M1911Shoot", 23, "Base.Bullets45"},
    {"Base.Colt1911", "Base.45Clip", 7, "M1911Shoot", 29, "Base.Bullets45"},
    {"Base.Colt_Kimber", "Base.45Clip", 7, "M1911Shoot", 29, "Base.Bullets45"},
    {"Base.Colt_Commander", "Base.45Clip", 7, "M1911Shoot", 29, "Base.Bullets45"},
    {"Base.PARA1911", "Base.45DSClip", 13, "M1911Shoot", 29, "Base.Bullets45"},
    {"Base.PULP_1911", "Base.45Clip", 7, "M1911Shoot", 29, "Base.Bullets45"},
    {"Base.STAR_BM", "Base.9mmSSClip", 10, "M1911Shoot", 27, "Base.Bullets9mm"},
    {"Base.M29_44", false, 6, "MagnumShoot", 35, "Base.Bullets44"},
    {"Base.M29_44Carbine", false, 6, "MagnumShoot", 28, "Base.Bullets44"},
    {"Base.Automag", "Base.44Clip", 8, "DesertEagleShoot", 35, "Base.Bullets44"},
    {"Base.DEagle", "Base.44Clip", 8, "DesertEagleShoot", 35, "Base.Bullets44"},
    {"Base.FN_57", "Base.57Clip", 20, "M9Shoot", 26, "Base.Bullets57"},
    {"Base.FN_57_MK2", "Base.57Clip", 20, "M9Shoot", 26, "Base.Bullets57"},
    {"Base.FN_P90", "Base.P90Clip", 50, "M9Shoot", 19, "Base.Bullets57"},
    {"Base.FN_PS90", "Base.P90Clip", 50, "M9Shoot", 18, "Base.Bullets57"},
    {"Base.AR57_PDW", "Base.P90Clip", 50, "M9Shoot", 18, "Base.Bullets57"},
    {"Base.AR57_PDW_Fold", "Base.P90Clip", 50, "M9Shoot", 25, "Base.Bullets57"},
    {"Base.AR57_PDW_Long", "Base.P90Clip", 50, "M9Shoot", 18, "Base.Bullets57"},
    {"Base.B93R", "Base.9mmClip", 15, "M9Shoot", 27, "Base.Bullets9mm"},
    {"Base.M9", "Base.9mmClip", 15, "M9Shoot", 27, "Base.Bullets9mm"},
    {"Base.M9A3", "Base.9mmClip", 15, "M9Shoot", 27, "Base.Bullets9mm"},
    {"Base.RPD_92FS", "Base.9mmClip", 15, "M9Shoot", 27, "Base.Bullets9mm"},
    {"Base.G17", "Base.9mmClip", 15, "M9Shoot", 28, "Base.Bullets9mm"},
    {"Base.G18", "Base.9mmClip", 15, "M9Shoot", 28, "Base.Bullets9mm"},
    {"Base.G21", "Base.45DSClip", 13, "M1911Shoot", 29, "Base.Bullets45"},
    {"Base.G34", "Base.9mmClip", 15, "M9Shoot", 28, "Base.Bullets9mm"},
    {"Base.G42", "Base.380Clip", 7, "M9Shoot", 27, "Base.Bullets380"},
    {"Base.G43", "Base.9mmSSClip", 10, "M9Shoot", 29, "Base.Bullets9mm"},
    {"Base.HK_MK23", "Base.45DSClip", 13, "M1911Shoot", 29, "Base.Bullets45"},
    {"Base.HK_USP", "Base.45DSClip", 13, "M1911Shoot", 29, "Base.Bullets45"},
    {"Base.HK_USP_Match", "Base.45DSClip", 13, "M1911Shoot", 27, "Base.Bullets45"},
    {"Base.PPK", "Base.380Clip", 7, "M9Shoot", 26, "Base.Bullets380"},
    {"Base.Colt1903", "Base.380Clip", 7, "M9Shoot", 26, "Base.Bullets380"},
    {"Base.Bersa85F", "Base.380Clip", 7, "M9Shoot", 26, "Base.Bullets380"},
    {"Base.MP9", "Base.9mmClip", 15, "M9Shoot", 27, "Base.Bullets9mm"},
    {"Base.MP45", "Base.45DSClip", 13, "M1911Shoot", 29, "Base.Bullets45"},
    {"Base.P226", "Base.9mmClip", 15, "M9Shoot", 27, "Base.Bullets9mm"},
    {"Base.P220", "Base.45DSClip", 13, "M1911Shoot", 29, "Base.Bullets45"},
    {"Base.XD9", "Base.9mmClip", 15, "M9Shoot", 27, "Base.Bullets9mm"},
    {"Base.XD4", "Base.45DSClip", 13, "M1911Shoot", 29, "Base.Bullets45"},
    {"Base.Taurus856", false, 6, "M36Shoot", 26, "Base.Bullets38"},
    {"Base.Colt_Service38", false, 6, "M625Shoot", 26, "Base.Bullets38"},
    {"Base.Colt_Service45", false, 6, "M625Shoot", 35, "Base.Bullets45LC"},
    {"Base.Colt_Navy_1851", false, 6, "M625Shoot", 31, "Base.Bullets357"},
    {"Base.M1936", false, 7, "M625Shoot", 31, "Base.Bullets357"},
    {"Base.BodyGuard380", "Base.380Clip", 7, "M9Shoot", 27, "Base.Bullets380"},
}

Registry.BritaArsenalMelee = {
    "Base.AK_Bayonet_Melee",
    "Base.M4_Bayonet_Melee",
    "Base.M1917_Bayonet_Melee",
    "Base.Chainsaw",
    "Base.Machete",
    "Base.Kukri",
    "Base.Gurkha",
    "Base.CombatKnife",
    "Base.EntrenchingTool",
    "Base.Tomahawk",
    "Base.FireAxe",
    "Base.HuntingKnife",
}


Registry.PSAPrimary = {
    {"Base.IZH38Shotgun", false, 1, "Airshoot", 42, "Base.4mmBullets"},
    {"Base.VarmintRifle", "Base.22LRClip", 5, "22lrshoot", 35, "Base.Bullets22LR"},
    {"Base.Kiparissmg", "Base.KiparisMag", 20, "PPSshoot", 22, "Base.Bullets9x18mm"},
    {"Base.Kiparissmg_folded", "Base.KiparisMag", 20, "PPSshoot", 22, "Base.Bullets9x18mm"},
    {"Base.MP40smg", "Base.MP40Mag", 32, "MP40shoot", 22, "Base.Bullets9mm"},
    {"Base.MP40smg_Folded", "Base.MP40Mag", 32, "MP40shoot", 22, "Base.Bullets9mm"},
    {"Base.PPSsmg", "Base.762TokarevPPSClip", 35, "PPSshoot", 22, "Base.Bullets762Tokarev"},
    {"Base.PPSsmg_folded", "Base.762TokarevPPSClip", 35, "PPSshoot", 22, "Base.Bullets762Tokarev"},
    {"Base.PPShsmg", "Base.762TokarevPPSHClip", 71, "PPSshoot", 22, "Base.Bullets762Tokarev"},
    {"Base.AKSURifle", "Base.545Clip", 30, "AK74shoot", 35, "Base.Bullets545"},
    {"Base.AKSURifle_Folded", "Base.545Clip", 30, "AK74shoot", 35, "Base.Bullets545"},
    {"Base.AssaultRifle", "Base.545Clip", 30, "AK74shoot", 35, "Base.Bullets545"},
    {"Base.AKsliva", "Base.545Clip", 30, "AK74shoot", 35, "Base.Bullets545"},
    {"Base.AKS74Rifle", "Base.545Clip", 30, "AK74shoot", 35, "Base.Bullets545"},
    {"Base.AKS74Rifle_Folded", "Base.545Clip", 30, "AK74shoot", 35, "Base.Bullets545"},
    {"Base.AKS74PRifle", "Base.545Clip", 30, "AK74shoot", 35, "Base.Bullets545"},
    {"Base.AKS74PRifle_Folded", "Base.545Clip", 30, "AK74shoot", 35, "Base.Bullets545"},
    {"Base.AK74MRifle", "Base.545Clip", 30, "AK74shoot", 35, "Base.Bullets545"},
    {"Base.AK74MRifle_Folded", "Base.545Clip", 30, "AK74shoot", 35, "Base.Bullets545"},
    {"Base.Shotgun", false, 4, "MP43shoot", 42, "Base.ShotgunShells"},
    {"Base.ShotgunSawnoff", false, 4, "KSfire", 42, "Base.ShotgunShells"},
    {"Base.KS23", false, 3, "KSfire", 42, "Base.23x75ShotgunShells"},
    {"Base.KS23S", false, 3, "KSfire", 42, "Base.23x75ShotgunShells"},
    {"Base.DoubleBarrelShotgun", false, 2, "MP43shoot", 42, "Base.ShotgunShells"},
    {"Base.DoubleBarrelShotgunSawnoff", false, 2, "MP43shoot", 42, "Base.ShotgunShells"},
    {"Base.TOZ34Shotgun", false, 2, "MP43shoot", 42, "Base.ShotgunShells"},
    {"Base.TOZ34ShotgunSawnoff", false, 2, "MP43shoot", 42, "Base.ShotgunShells"},
    {"Base.IzhRifle", false, 1, "MP43shoot", 42, "Base.ShotgunShells"},
    {"Base.IzhRifleSawnoff", false, 1, "MP43shoot", 35, "Base.ShotgunShells"},
    {"Base.AKM", "Base.762AKClip", 30, "AKshoot", 35, "Base.Bullets762AK"},
    {"Base.AKMS", "Base.762AKClip", 30, "AK74shoot", 35, "Base.Bullets762AK"},
    {"Base.AKMS_Folded", "Base.762AKClip", 30, "AK74shoot", 35, "Base.Bullets762AK"},
    {"Base.VeprKM", "Base.762AKClip", 30, "AKshoot", 35, "Base.Bullets762AK"},
    {"Base.AssaultRifle2", false, 10, "SKSshoot", 35, "Base.Bullets762AK"},
    {"Base.SVTrifle", "Base.SVTMagazine", 10, "SVDshoot", 35, "Base.Bullets762PKM"},
    {"Base.HuntingRifle", false, 5, "Mosinshoot", 35, "Base.Bullets762PKM"},
    {"Base.Mosin", false, 5, "Mosinshoot", 35, "Base.Bullets762PKM"},
    {"Base.MosinSawnoff", false, 5, "Mosinshoot", 35, "Base.Bullets762PKM"},
    {"Base.SVDRifle", "Base.SVDMagazine", 10, "SVDshoot", 35, "Base.Bullets762PKM"},
    {"Base.VSSrifle", "Base.939Clip", 10, "VSSshoot", 35, "Base.Bullets939"},
    {"Base.ASValrifle", "Base.939Clip", 10, "VSSshoot", 35, "Base.Bullets939"},
    {"Base.ASValrifle_Folded", "Base.939Clip", 10, "VSSshoot", 35, "Base.Bullets939"},
    {"Base.PKMmg", "Base.762PKMClip", 100, "PKMshoot", 24, "Base.Bullets762PKM"},
}

Registry.PSASecondary = {
    {"Base.Pistol", "Base.9x18mmClip", 8, "Makashoot", 45, "Base.Bullets9x18mm"},
    {"Base.PBpistol", "Base.9x18mmClip", 8, "PBshoot", 45, "Base.Bullets9x18mm"},
    {"Base.Pistol3", "Base.9x18mmLargeClip", 20, "APSshoot", 45, "Base.Bullets9x18mm"},
    {"Base.APBPistol", "Base.9x18mmLargeClip", 20, "APSshoot", 45, "Base.Bullets9x18mm"},
    {"Base.RSA", false, 6, "Makashoot", 45, "Base.Bullets9x18mm"},
    {"Base.Luger", "Base.LugerClip", 8, "Makashoot", 45, "Base.Bullets9mm"},
    {"Base.Pistol2", "Base.762TokarevClip", 8, "TTshoot", 45, "Base.Bullets762Tokarev"},
    {"Base.Revolver_Long", false, 7, "Nagantshoot", 45, "Base.Bullets762Nagant"},
}

Registry.PSAMelee = {
    "Base.ShashkaGoldBrown",
    "Base.ShashkaGoldBlack",
    "Base.ShashkaSilverBrown",
    "Base.ShashkaSilverBlack",
    "Base.TrenchShovel",
    "Base.TaigaMachete",
    "Base.TaigaMacheteArmy",
    "Base.ScoutKnife",
    "Base.BayonetKnife",
}

Registry.BCGRareWeaponsMelee = {
    "BCGRareWeapons.ReinforcedBaseballBat",
    "BCGRareWeapons.VikingAxe",
}

Registry.ScrapSmithMelee = {
    "ScrapSmith.scrapsmith_armingSword",
    "ScrapSmith.scrapsmith_cavalrySaber",
    "ScrapSmith.scrapsmith_dagger",
    "ScrapSmith.scrapsmith_desertSaber",
    "ScrapSmith.scrapsmith_estoc",
    "ScrapSmith.scrapsmith_falchion",
    "ScrapSmith.scrapsmith_flangedMace",
    "ScrapSmith.scrapsmith_grosseMesser",
    "ScrapSmith.scrapsmith_horsemansBattleaxe",
    "ScrapSmith.scrapsmith_iberianMace",
    "ScrapSmith.scrapsmith_ornateWarPick",
    "ScrapSmith.scrapsmith_rondelDagger",
    "ScrapSmith.scrapsmith_scrapMachete",
    "ScrapSmith.scrapsmith_simpleWarhammer",
    "ScrapSmith.scrapsmith_spadroon",
    "ScrapSmith.scrapsmith_spikedClub",
    "ScrapSmith.scrapsmith_ulfberht",
    "ScrapSmith.scrapsmith_warAxe",
    "ScrapSmith.scrapsmith_warClub",
    "ScrapSmith.scrapsmith_warhammer",
    "ScrapSmith.scrapsmith_bastardSword",
    "ScrapSmith.scrapsmith_danishWarAxe",
    "ScrapSmith.scrapsmith_goedendag",
    "ScrapSmith.scrapsmith_hookedSpear",
    "ScrapSmith.scrapsmith_longBladedHewingSpear",
    "ScrapSmith.scrapsmith_morningStar",
    "ScrapSmith.scrapsmith_nodachi",
    "ScrapSmith.scrapsmith_poleaxe",
    "ScrapSmith.scrapsmith_ranseur",
    "ScrapSmith.scrapsmith_scottishClaymore",
    "ScrapSmith.scrapsmith_taperedWoodenClub",
    "ScrapSmith.scrapsmith_zweihander",
    "SSWeapons.CavalrySabre",
    "SSWeapons.WarAx",
    "SSWeapons.IberianMace",
    "SSWeapons.ArmingSword",
    "SSWeapons.Dagger",
    "SSWeapons.GermanMace",
    "SSWeapons.GrosseMesser",
    "SSWeapons.HorsemansBattleAxe",
    "SSWeapons.ScrapMachete",
    "SSWeapons.RondelDagger",
    "SSWeapons.Saber",
    "SSWeapons.WarhammerT1",
    "SSWeapons.WarhammerT2",
    "SSWeapons.BasicPoleAxe",
    "SSWeapons.Zweihander",
    "SSWeapons.LongBladedHewingSpear",
    "SSWeapons.HookedSpear",
    "SSWeapons.DanishWarAxe",
    "SSWeapons.MorningStar",
}

Registry.ScrapSmithArmor = {
    "ScrapSmithArmor.scrapsmith_chainmailHauberk",
    "ScrapSmithArmor.scrapsmith_coatOfPlates",
    "ScrapSmithArmor.scrapsmith_gambeson",
    "ScrapSmithArmor.scrapsmith_bascinet",
    "ScrapSmithArmor.scrapsmith_blackenedGreatHelm",
    "ScrapSmithArmor.scrapsmith_bucketHelmet",
    "ScrapSmithArmor.scrapsmith_greatHelm",
    "ScrapSmithArmor.scrapsmith_hounskullBascinet",
    "ScrapSmithArmor.scrapsmith_hounskullBascinet_open",
    "ScrapSmithArmor.scrapsmith_kettleHelm",
    "ScrapSmithArmor.scrapsmith_klappvisorBascinet",
    "ScrapSmithArmor.scrapsmith_klappvisorBascinet_open",
    "ScrapSmithArmor.scrapsmith_pauldrons",
    "ScrapSmithArmor.scrapsmith_plateCuirass",
    "ScrapSmithArmor.scrapsmith_plateMittens",
}

Registry.ScrapSmithEliteArmor = {
    "ScrapSmithArmor.scrapsmith_plateCuirass",
    "ScrapSmithArmor.scrapsmith_blackenedGreatHelm",
    "ScrapSmithArmor.scrapsmith_greatHelm",
    "ScrapSmithArmor.scrapsmith_hounskullBascinet",
    "ScrapSmithArmor.scrapsmith_klappvisorBascinet",
    "ScrapSmithArmor.scrapsmith_plateMittens",
    "ScrapSmithArmor.scrapsmith_pauldrons",
}

Registry.BritaPrimary = Registry.BritaArsenalPrimary
Registry.BritaSecondary = Registry.BritaArsenalSecondary

Registry.FirearmModPrimary = {
    {"Base.AK47", "Base.AK_Mag", 30, "M16Shoot", 8},
    {"Base.AK47S", "Base.AK_Mag", 30, "M16Shoot", 8},
    {"Base.AR15", "Base.556Clip", 30, "M16Shoot", 18},
    {"Base.AR15Short", "Base.556Clip", 30, "M16Shoot", 16},
    {"Base.AssaultRifle", "Base.556Clip", 30, "M16Shoot", 8},
    {"Base.AssaultRifleShort", "Base.556Clip", 30, "M16Shoot", 8},
    {"Base.M16A2", "Base.556Clip", 30, "M16Shoot", 8},
    {"Base.M16A2Short", "Base.556Clip", 30, "M16Shoot", 8},
    {"Base.M733", "Base.556Clip", 30, "M16Shoot", 8},
    {"Base.Mini14", "Base.556Clip", 30, "M16Shoot", 20},
    {"Base.AC556", "Base.556Clip", 30, "M16Shoot", 8},
    {"Base.FN_FAL", "Base.FN_FAL_Mag", 20, "M16Shoot", 24},
    {"Base.FN_FALShort", "Base.FN_FAL_Mag", 20, "M16Shoot", 24},
    {"Base.AssaultRifle2", "Base.M14Clip", 20, "M14Shoot", 25},
    {"Base.M14A1", "Base.M14Clip", 20, "M14Shoot", 10},
    {"Base.BrowningAR", "Base.BrowningAR_Mag", 20, "M14Shoot", 14},
    {"Base.M1Garand", "Base.M1GarandClip", 8, "M14Shoot", 28},
    {"Base.SKS", false, 10, "M16Shoot", 22},
    {"Base.SKSMag", "Base.AK_Mag", 30, "M16Shoot", 22},
    {"Base.Winchester94", false, 10, "MSR788Shoot", 42},
    {"Base.Winchester73", false, 10, "MSR788Shoot", 40},
    {"Base.Rossi92", false, 10, "MSR788Shoot", 35},
    {"Base.VarmintRifle", false, 6, "MSR700Shoot", 90},
    {"Base.HuntingRifle", false, 3, "MSR788Shoot", 100},
    {"Base.M24Rifle", false, 5, "MSR700Shoot", 90},
    {"Base.M1903Springfield", false, 5, "M14Shoot", 100},
    {"Base.Rugerm7722", false, 6, "M9Shoot", 90},
    {"Base.Mac10", "Base.Mac10Mag", 30, "M1911Shoot", 5},
    {"Base.MP5", "Base.MP5Mag", 30, "M9Shoot", 6},
    {"Base.UZI", "Base.UZIMag", 25, "M9Shoot", 6},
    {"Base.M633", "Base.UZIMag", 25, "M9Shoot", 6},
    {"Base.M3Grease", "Base.Mac10Mag", 30, "MagnumShoot", 8},
    {"Base.M60", "Base.M60Mag", 100, "M16Shoot", 9},
    {"Base.DoubleBarrelShotgun", false, 2, "DoubleBarrelShotgunShoot", 30},
    {"Base.DoubleBarrelShotgunSawnoff", false, 2, "DoubleBarrelShotgunShoot", 36},
    {"Base.Shotgun", false, 5, "JS2000ShotgunShoot", 50},
    {"Base.ShotgunSawnoff", false, 5, "SawnOffJS2000ShotgunShoot", 55},
    {"Base.Mossberg500", false, 8, "JS2000ShotgunShoot", 50},
    {"Base.Mossberg500Tactical", false, 6, "JS2000ShotgunShoot", 52},
    {"Base.Remington870Wood", false, 7, "JS2000ShotgunShoot", 50},
    {"Base.Remington870Sawnoff", false, 7, "SawnOffJS2000ShotgunShoot", 55},
    {"Base.SPAS12", false, 8, "JS2000ShotgunShoot", 32},
    {"Base.LAW12", false, 8, "JS2000ShotgunShoot", 28},
}

Registry.FirearmModSecondary = {
    {"Base.Pistol", "Base.9mmClip", 15, "M9Shoot", 22},
    {"Base.Pistol2", "Base.45Clip", 7, "M1911Shoot", 24},
    {"Base.Pistol_M45A1", "Base.45Clip", 7, "M1911Shoot", 20},
    {"Base.Pistol3", "Base.44Clip", 8, "DesertEagleShoot", 28},
    {"Base.Pistol_Compact", "Base.9mmClip", 15, "M9Shoot", 22},
    {"Base.ColtAce", "Base.22Clip", 15, "M9Shoot", 26},
    {"Base.Glock17", "Base.Glock17Mag", 17, "M9Shoot", 22},
    {"Base.Revolver", false, 6, "M625Shoot", 22},
    {"Base.Revolver_Long", false, 6, "MagnumShoot", 28},
    {"Base.Revolver_Short", false, 5, "M36Shoot", 18},
    {"Base.Revolver_M29", false, 6, "MagnumShoot", 30},
    {"Base.ColtPython", false, 6, "MagnumShoot", 26},
    {"Base.ColtPythonStubby", false, 6, "MagnumShoot", 28},
    {"Base.ColtAnaconda", false, 6, "MagnumShoot", 30},
    {"Base.ColtPeacemaker", false, 6, "MagnumShoot", 34},
    {"Base.ColtSingleAction22", false, 6, "M9Shoot", 30},
}

Registry.VFExpansionPrimary = {
    {"Base.AK47", "Base.762Clip", 30, "AK47shoot", 17},
    {"Base.CAR15", "Base.556Clip", 30, "M14Shoot", 17},
    {"Base.FAL", "Base.FALClip", 20, "M14Shoot", 17},
    {"Base.MAC10Unfolded", "Base.45Clip32", 32, "M1911Shoot", 10},
    {"Base.M60MMG", "Base.M60Belt", 100, "M1911Shoot", 13},
    {"Base.CampCarbine", "Base.45Clip", 7, "M1911Shoot", 22},
    {"Base.MP5Unfolded", "Base.9mmClip30", 7, "M9Shoot", 12},
    {"Base.Mini14", "Base.223Clip20", 20, "AK47shoot", 17},
}

Registry.VFExpansionSecondary = {
    {"Base.CZ75", "Base.9mmClip16", 16, "M9Shoot", 35},
    {"Base.Glock", "Base.9mmClip16", 16, "M9Shoot", 35},
    {"Base.Glock18", "Base.9mmClip17", 16, "M9Shoot", 6},
    {"Base.MK2", "Base.22ClipPistol", 10, "Mk2shoot", 35},
    {"Base.MK23SOCOM", "Base.45Clip12", 12, "Mk2SDshoot", 35},
    {"Base.UziUnfolded", "Base.9mmClip32", 32, "M9Shoot", 6},
}

Registry.Guns93Secondary = {
    {"Base.Gov1911", "Base.45Clip", 7, "M1911Shoot", 47},
    {"Base.Javelina", "Base.DeltaEliteMag", 8, "DesertEagleShoot", 47},
    {"Base.DeltaElite", "Base.DeltaEliteMag", 8, "DesertEagleShoot", 47},
    {"Base.CalicoPistol", "Base.CalicoMag", 50, "M9Shoot", 35},
    {"Base.Glock17", "Base.G17Mag", 17, "M9Shoot", 35},
    {"Base.Glock20", "Base.G20Mag", 15, "M1911Shoot", 35},
    {"Base.Glock21", "Base.G21Mag", 13, "M1911Shoot", 35},
    {"Base.Glock22", "Base.G22Mag", 15, "M9Shoot", 35},
    {"Base.USP40", "Base.USP40Mag", 13, "M9Shoot", 34},
}

Registry.Guns93Primary = {
    {"Base.AKM", "Base.AKMag", 30, "DesertEagleShoot", 9},
    {"Base.AKMS", "Base.AKMag", 30, "DesertEagleShoot", 10},
    {"Base.CAR15", "Base.556Clip", 30, "M14Shoot", 12},
    {"Base.AR180", "Base.AR180Mag", 30, "M14Shoot", 12},
    {"Base.Brown308BAR", "Base.308BARMag", 4, "M14Shoot", 33},
    {"Base.Brown3006BAR", "Base.3006BARMag", 4, "M14Shoot", 35},
    {"Base.CalicoRifle", "Base.CalicoMag", 50, "M9Shoot", 22},
    {"Base.M635", "Base.ColtSMGMag", 32, "M9Shoot", 17},
    {"Base.M723", "Base.556Clip", 32, "M14Shoot", 33},
    {"Base.FAL", "Base.FALMag", 20, "M14Shoot", 38},
    {"Base.MP5", "Base.MP5Mag", 30, "M9Shoot", 12},
    {"Base.HK91", "Base.HK91Mag", 20, "M14Shoot", 35},
}

Registry.FirearmsRevampPrimary = {
    {"Base.AssaultRifle", "Base.556Clip", 30, "M16Shoot", 4},
    {"Base.FN_FAL", "Base.M14Clip", 20, "M16Shoot", 5},
    {"Base.M16A2", "Base.556Clip", 30, "M16Shoot", 4},
    {"Base.M733", "Base.556Clip", 30, "M16Shoot", 4},
    {"Base.AR15", "Base.556Clip", 30, "M16Shoot", 20},
    {"Base.Mini14", "Base.556Clip", 30, "M16Shoot", 22},
    {"Base.AC556", "Base.556Clip", 30, "M16Shoot", 5},
    {"Base.M60", "Base.M60Mag", 100, "M16Shoot", 6},
    {"Base.BrowningAR", "Base.BrowningAR_Mag", 20, "M16Shoot", 7},
    {"Base.AK47", "Base.AK_Mag", 30, "M16Shoot", 5},
    {"Base.AK47S", "Base.AK_Mag", 30, "M16Shoot", 5},
    {"Base.Winchester94", false, 10, "MSR788Shoot", 42},
    {"Base.Winchester73", false, 10, "MSR788Shoot", 40},
    {"Base.Rossi92", false, 10, "MSR788Shoot", 35},
    {"Base.Winchester94Sawn", false, 7, "MSR788Shoot", 47},
    {"Base.Winchester73Sawn", false, 7, "MSR788Shoot", 44},
    {"Base.Rossi92Sawn", false, 10, "MSR788Shoot", 37},
    {"Base.M1887", false, 5, "JS2000ShotgunShoot", 45},
    {"Base.M1887Short", false, 5, "JS2000ShotgunShoot", 45},
    {"Base.M1887Sawn", false, 5, "JS2000ShotgunShoot", 50},
    {"Base.VarmintRifle_Sawn", false, 6, "MSR700Shoot", 100},
    {"Base.HuntingRifle_Sawn", false, 3, "MSR788Shoot", 110},
    {"Base.Rugerm7722_Sawn", false, 6, "M9Shoot", 95},
    {"Base.VarmintRifle", false, 6, "MSR700Shoot", 90},
    {"Base.HuntingRifle", false, 3, "MSR788Shoot", 100},
    {"Base.Rugerm7722", false, 6, "M9Shoot", 90},
    {"Base.M24Rifle", false, 5, "MSR700Shoot", 90},
    {"Base.M1903Springfield_Sawn", false, 5, "M14Shoot", 115},
    {"Base.M1903Springfield", false, 5, "M14Shoot", 100},
    {"Base.SKS", false, 10, "M16Shoot", 22},
    {"Base.SKSMag", "Base.AK_Mag", 30, "M16Shoot", 22},
    {"Base.AssaultRifle2", "Base.M14Clip", 20, "M14Shoot", 25},
    {"Base.M14A1", "Base.M14Clip", 20, "M14Shoot", 4},
    {"Base.M1Garand", "Base.M1GarandClip", 8, "M14Shoot", 28},
    {"Base.Winchester77", "Base.22Clip", 10, "M9Shoot", 15},
    {"Base.Winchester77_Sawn", "Base.22Clip", 10, "M9Shoot", 17},
    {"Base.MP5", "Base.MP5Mag", 30, "M9Shoot", 4},
    {"Base.UZI", "Base.UZIMag", 25, "M9Shoot", 4},
    {"Base.M633", "Base.UZIMag", 25, "M9Shoot", 4},
    {"Base.Mac10", "Base.Mac10Mag", 30, "M1911Shoot", 4},
    {"Base.M3Grease", "Base.Mac10Mag", 30, "MagnumShoot", 8},
    {"Base.AssaultRifleShort", "Base.556Clip", 30, "M16Shoot", 4},
    {"Base.M16A2Short", "Base.556Clip", 30, "M16Shoot", 4},
    {"Base.AR15Short", "Base.556Clip", 30, "M16Shoot", 20},
    {"Base.FN_FALShort", "Base.M14Clip", 20, "M16Shoot", 6},
    {"Base.Mini14Short", "Base.556Clip", 30, "M16Shoot", 22},
    {"Base.AC556Short", "Base.556Clip", 30, "M16Shoot", 6},
    {"Base.Mini14Sawn", "Base.556Clip", 30, "M16Shoot", 30},
    {"Base.BrowningARShort", "Base.BrowningAR_Mag", 20, "M16Shoot", 8},
    {"Base.VarmintRifleShort", false, 6, "MSR700Shoot", 90},
    {"Base.HuntingRifleShort", false, 3, "MSR788Shoot", 100},
    {"Base.SKSShort", false, 10, "M16Shoot", 23},
    {"Base.SKSMagShort", "Base.AK_Mag", 30, "M16Shoot", 23},
    {"Base.SKSSawn", false, 10, "M16Shoot", 33},
    {"Base.SKSMagSawn", "Base.AK_Mag", 30, "M16Shoot", 33},
    {"Base.AssaultRifle2Short", "Base.M14Clip", 20, "M14Shoot", 25},
    {"Base.M14A1Short", "Base.M14Clip", 20, "M14Shoot", 5},
    {"Base.M1903SpringfieldShort", false, 5, "M14Shoot", 100},
    {"Base.DoubleBarrelShotgun", false, 2, "DoubleBarrelShotgunShoot", 30},
    {"Base.DoubleBarrelShotgunSawnoff", false, 2, "DoubleBarrelShotgunShoot", 35},
    {"Base.Shotgun", false, 5, "JS2000ShotgunShoot", 50},
    {"Base.ShotgunSawnoff", false, 5, "SawnOffJS2000ShotgunShoot", 55},
    {"Base.Mossberg500", false, 8, "JS2000ShotgunShoot", 50},
    {"Base.Mossberg500Tactical", false, 6, "JS2000ShotgunShoot", 55},
    {"Base.Remington870Wood", false, 7, "JS2000ShotgunShoot", 50},
    {"Base.Remington870Sawnoff", false, 7, "SawnOffJS2000ShotgunShoot", 55},
    {"Base.SPAS12", false, 8, "JS2000ShotgunShoot", 32},
    {"Base.LAW12", false, 8, "JS2000ShotgunShoot", 27},
    {"Base.ShotgunShort", false, 5, "JS2000ShotgunShoot", 50},
    {"Base.DoubleBarrelShotgunShort", false, 2, "DoubleBarrelShotgunShoot", 30},
    {"Base.OUShotgun", false, 2, "DoubleBarrelShotgunShoot", 27},
    {"Base.OUShotgunShort", false, 2, "DoubleBarrelShotgunShoot", 27},
    {"Base.OUShotgunSawnoff", false, 2, "DoubleBarrelShotgunShoot", 32},
    {"Base.AssaultRifleBayonet", "Base.556Clip", 30, "M16Shoot", 4},
    {"Base.M16A2Bayonet", "Base.556Clip", 30, "M16Shoot", 4},
    {"Base.AR15Bayonet", "Base.556Clip", 30, "M16Shoot", 20},
    {"Base.SKSBayonet", false, 10, "M16Shoot", 22},
    {"Base.SKSMagBayonet", "Base.AK_Mag", 30, "M16Shoot", 22},
    {"Base.AK47Bayonet", "Base.AK_Mag", 30, "M16Shoot", 5},
    {"Base.M1GarandBayonet", "Base.M1GarandClip", 8, "M14Shoot", 28},
    {"Base.M1903SpringfieldBayonet", false, 5, "M14Shoot", 100},
}

Registry.FirearmsRevampSecondary = {
    {"Base.Pistol", "Base.9mmClip", 15, "M9Shoot", 20},
    {"Base.Pistol2", "Base.45Clip", 7, "M1911Shoot", 20},
    {"Base.Pistol_M45A1", "Base.45Clip", 7, "M1911Shoot", 16},
    {"Base.Pistol3", "Base.44Clip", 8, "DesertEagleShoot", 28},
    {"Base.Glock17", "Base.Glock17Mag", 17, "M9Shoot", 22},
    {"Base.ColtAce", "Base.22Clip", 10, "M9Shoot", 16},
    {"Base.Pistol_Compact", "Base.9mmClip", 15, "M9Shoot", 21},
    {"Base.Revolver", false, 6, "M625Shoot", 18},
    {"Base.Revolver_Long", false, 6, "MagnumShoot", 24},
    {"Base.Revolver_Short", false, 5, "M36Shoot", 15},
    {"Base.Revolver_M29", false, 6, "MagnumShoot", 28},
    {"Base.ColtPython", false, 6, "MagnumShoot", 22},
    {"Base.ColtPythonStubby", false, 6, "MagnumShoot", 25},
    {"Base.ColtPythonHunter", false, 6, "MagnumShoot", 30},
    {"Base.ColtAnaconda", false, 6, "MagnumShoot", 27},
    {"Base.ColtPeacemaker", false, 6, "MagnumShoot", 32},
    {"Base.ColtSingleAction22", false, 6, "M9Shoot", 30},
}

Registry.FirearmsRevampMelee = {
    "Base.M9Bayonet",
    "Base.M1Bayonet",
    "Base.SpikeBayonet",
    "Base.SpearSpikeBayonet",
    "Base.SpearM1Bayonet",
    "Base.SpearM9Bayonet",
    "Base.AssaultRifleBayonetMelee",
    "Base.M16A2BayonetMelee",
    "Base.AR15BayonetMelee",
    "Base.SKSBayonetMelee",
    "Base.SKSMagBayonetMelee",
    "Base.AK47BayonetMelee",
    "Base.M1GarandBayonetMelee",
    "Base.M1903SpringfieldBayonetMelee",
}

