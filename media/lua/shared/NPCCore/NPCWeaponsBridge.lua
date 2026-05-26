-- NPCWeaponsBridge.lua
-- Neutral shared backend for NPC weapon pools.

require "NPCData/NPCLoadoutRegistry"

-- Compatibility facade for the historical global table.  Weapon definitions are
-- registered through NPCLoadoutRegistry so future loadout code can use neutral
-- data contracts while existing callers keep the same API.
NPCWeaponsBridge = NPCWeaponsBridge or {}

NPCWeaponsBridge.MakeHandgun = function(name, magName, magSize, shotSound, shotDelay, ammoName)
    return NPCLoadoutRegistry.MakeFirearm(name, magName, magSize, shotSound, shotDelay, ammoName)
end

NPCWeaponsBridge.Copy = function(weapon)
    return NPCLoadoutRegistry.CopySpec(weapon)
end

NPCWeaponsBridge.IsFirearmsRevampActive = function()
    return NPCLoadoutRegistry.HasMod("firearmmodRevamp")
end

NPCWeaponsBridge.IsFirearmsB41Active = function()
    return NPCLoadoutRegistry.HasMod("firearmmod") or NPCLoadoutRegistry.HasMod("firearmmodRevamp")
end

NPCWeaponsBridge.IsArsenalGunfighterActive = function()
    return NPCLoadoutRegistry.IsArsenalGunfighterActive and NPCLoadoutRegistry.IsArsenalGunfighterActive() or false
end

NPCWeaponsBridge.IsBritaArsenalActive = function()
    return NPCLoadoutRegistry.IsBritaArsenalActive and NPCLoadoutRegistry.IsBritaArsenalActive() or false
end

NPCWeaponsBridge.IsBWardrobeActive = function()
    return NPCLoadoutRegistry.IsBWardrobeActive and NPCLoadoutRegistry.IsBWardrobeActive() or false
end

NPCWeaponsBridge.IsPSAActive = function()
    return NPCLoadoutRegistry.IsPSAActive and NPCLoadoutRegistry.IsPSAActive() or false
end

NPCWeaponsBridge.IsBCGRareWeaponsActive = function()
    return NPCLoadoutRegistry.IsBCGRareWeaponsActive and NPCLoadoutRegistry.IsBCGRareWeaponsActive() or false
end

NPCWeaponsBridge.IsScrapSmithActive = function()
    return NPCLoadoutRegistry.IsScrapSmithActive and NPCLoadoutRegistry.IsScrapSmithActive() or false
end

NPCWeaponsBridge.AddWeapon = function(tab, weapon)
    return NPCLoadoutRegistry.UpsertByName(tab, weapon)
end

local function attachRegistrationSource(weapon)
    if weapon and NPCWeaponsBridge._registrationSource then
        weapon.source = NPCWeaponsBridge._registrationSource
    end
    return weapon
end

NPCWeaponsBridge.AddPrimary = function(name, magName, magSize, shotSound, shotDelay, ammoName)
    NPCWeaponsBridge.Primary = NPCWeaponsBridge.Primary or {}
    local weapon = attachRegistrationSource(NPCWeaponsBridge.MakeHandgun(name, magName, magSize, shotSound, shotDelay, ammoName))
    NPCWeaponsBridge.AddWeapon(NPCWeaponsBridge.Primary, weapon)
    if weapon and weapon.source == "firearmmodRevamp" then
        NPCWeaponsBridge.FirearmsPrimary = NPCWeaponsBridge.FirearmsPrimary or {}
        NPCWeaponsBridge.AddWeapon(NPCWeaponsBridge.FirearmsPrimary, weapon)
    elseif weapon and (weapon.source == "britaArsenal" or weapon.source == "arsenalGunfighter") then
        NPCWeaponsBridge.BritaArsenalPrimary = NPCWeaponsBridge.BritaArsenalPrimary or {}
        NPCWeaponsBridge.AddWeapon(NPCWeaponsBridge.BritaArsenalPrimary, weapon)
    elseif weapon and weapon.source == "psa" then
        NPCWeaponsBridge.PSAPrimary = NPCWeaponsBridge.PSAPrimary or {}
        NPCWeaponsBridge.AddWeapon(NPCWeaponsBridge.PSAPrimary, weapon)
    end
    if weapon and (weapon.source == "britaArsenal" or weapon.source == "arsenalGunfighter" or weapon.source == "psa") then
        NPCWeaponsBridge.IntegratedPrimary = NPCWeaponsBridge.IntegratedPrimary or {}
        NPCWeaponsBridge.AddWeapon(NPCWeaponsBridge.IntegratedPrimary, weapon)
    end
    return weapon
end

NPCWeaponsBridge.AddSecondary = function(name, magName, magSize, shotSound, shotDelay, ammoName)
    NPCWeaponsBridge.Secondary = NPCWeaponsBridge.Secondary or {}
    local weapon = attachRegistrationSource(NPCWeaponsBridge.MakeHandgun(name, magName, magSize, shotSound, shotDelay, ammoName))
    NPCWeaponsBridge.AddWeapon(NPCWeaponsBridge.Secondary, weapon)
    if weapon and weapon.source == "firearmmodRevamp" then
        NPCWeaponsBridge.FirearmsSecondary = NPCWeaponsBridge.FirearmsSecondary or {}
        NPCWeaponsBridge.AddWeapon(NPCWeaponsBridge.FirearmsSecondary, weapon)
    elseif weapon and (weapon.source == "britaArsenal" or weapon.source == "arsenalGunfighter") then
        NPCWeaponsBridge.BritaArsenalSecondary = NPCWeaponsBridge.BritaArsenalSecondary or {}
        NPCWeaponsBridge.AddWeapon(NPCWeaponsBridge.BritaArsenalSecondary, weapon)
    elseif weapon and weapon.source == "psa" then
        NPCWeaponsBridge.PSASecondary = NPCWeaponsBridge.PSASecondary or {}
        NPCWeaponsBridge.AddWeapon(NPCWeaponsBridge.PSASecondary, weapon)
    end
    if weapon and (weapon.source == "britaArsenal" or weapon.source == "arsenalGunfighter" or weapon.source == "psa") then
        NPCWeaponsBridge.IntegratedSecondary = NPCWeaponsBridge.IntegratedSecondary or {}
        NPCWeaponsBridge.AddWeapon(NPCWeaponsBridge.IntegratedSecondary, weapon)
    end
    return weapon
end

NPCWeaponsBridge.AddMelee = function(name)
    if not name then return end
    NPCWeaponsBridge.Melee = NPCWeaponsBridge.Melee or {}
    local before = #NPCWeaponsBridge.Melee
    NPCLoadoutRegistry.AppendMelee(NPCWeaponsBridge.Melee, { name })

    if NPCWeaponsBridge._registrationSource == "firearmmodRevamp" then
        NPCWeaponsBridge.FirearmsMelee = NPCWeaponsBridge.FirearmsMelee or {}
        NPCLoadoutRegistry.AppendMelee(NPCWeaponsBridge.FirearmsMelee, { name })
    elseif NPCWeaponsBridge._registrationSource == "britaArsenal" or NPCWeaponsBridge._registrationSource == "arsenalGunfighter" then
        NPCWeaponsBridge.BritaArsenalMelee = NPCWeaponsBridge.BritaArsenalMelee or {}
        NPCLoadoutRegistry.AppendMelee(NPCWeaponsBridge.BritaArsenalMelee, { name })
    elseif NPCWeaponsBridge._registrationSource == "psa" then
        NPCWeaponsBridge.PSAMelee = NPCWeaponsBridge.PSAMelee or {}
        NPCLoadoutRegistry.AppendMelee(NPCWeaponsBridge.PSAMelee, { name })
    elseif NPCWeaponsBridge._registrationSource == "scrapSmith" then
        NPCWeaponsBridge.ScrapSmithMelee = NPCWeaponsBridge.ScrapSmithMelee or {}
        NPCLoadoutRegistry.AppendMelee(NPCWeaponsBridge.ScrapSmithMelee, { name })
    elseif NPCWeaponsBridge._registrationSource == "bcgRareWeapons" then
        NPCWeaponsBridge.BCGRareWeaponsMelee = NPCWeaponsBridge.BCGRareWeaponsMelee or {}
        NPCLoadoutRegistry.AppendMelee(NPCWeaponsBridge.BCGRareWeaponsMelee, { name })
    end
    if NPCWeaponsBridge._registrationSource == "psa" or NPCWeaponsBridge._registrationSource == "scrapSmith" or NPCWeaponsBridge._registrationSource == "bcgRareWeapons" or NPCWeaponsBridge._registrationSource == "britaArsenal" or NPCWeaponsBridge._registrationSource == "arsenalGunfighter" then
        NPCWeaponsBridge.IntegratedMelee = NPCWeaponsBridge.IntegratedMelee or {}
        NPCLoadoutRegistry.AppendMelee(NPCWeaponsBridge.IntegratedMelee, { name })
    end
    return #NPCWeaponsBridge.Melee > before
end

NPCWeaponsBridge.GetMelee = function()
    return NPCWeaponsBridge.Melee
end

NPCWeaponsBridge.GetMeleeForClan = function(clan)
    local melee = {}
    if clan and clan.Melee then
        for i = 1, #clan.Melee do
            melee[#melee + 1] = clan.Melee[i]
        end
    end
    if NPCWeaponsBridge.Melee then
        for i = 1, #NPCWeaponsBridge.Melee do
            melee[#melee + 1] = NPCWeaponsBridge.Melee[i]
        end
    end
    return melee
end

NPCWeaponsBridge.GetPrimary = function()
    return NPCWeaponsBridge.Primary
end

NPCWeaponsBridge.GetSecondary = function()
    return NPCWeaponsBridge.Secondary
end

NPCWeaponsBridge.GetSpawnPrimary = function(clan)
    if NPCWeaponsBridge.IntegratedPrimary and #NPCWeaponsBridge.IntegratedPrimary > 0 then
        return NPCWeaponsBridge.IntegratedPrimary
    end
    if NPCWeaponsBridge.IsBritaArsenalActive() and NPCWeaponsBridge.BritaArsenalPrimary and #NPCWeaponsBridge.BritaArsenalPrimary > 0 then
        return NPCWeaponsBridge.BritaArsenalPrimary
    end
    if NPCWeaponsBridge.IsFirearmsRevampActive() and NPCWeaponsBridge.FirearmsPrimary and #NPCWeaponsBridge.FirearmsPrimary > 0 then
        return NPCWeaponsBridge.FirearmsPrimary
    end
    if NPCWeaponsBridge.IsFirearmsB41Active() and NPCWeaponsBridge.Primary and #NPCWeaponsBridge.Primary > 0 then
        return NPCWeaponsBridge.Primary
    end
    if clan and clan.Primary and #clan.Primary > 0 then
        return clan.Primary
    end
    return NPCWeaponsBridge.Primary
end

NPCWeaponsBridge.GetSpawnSecondary = function(clan)
    if NPCWeaponsBridge.IntegratedSecondary and #NPCWeaponsBridge.IntegratedSecondary > 0 then
        return NPCWeaponsBridge.IntegratedSecondary
    end
    if NPCWeaponsBridge.IsBritaArsenalActive() and NPCWeaponsBridge.BritaArsenalSecondary and #NPCWeaponsBridge.BritaArsenalSecondary > 0 then
        return NPCWeaponsBridge.BritaArsenalSecondary
    end
    if NPCWeaponsBridge.IsFirearmsRevampActive() and NPCWeaponsBridge.FirearmsSecondary and #NPCWeaponsBridge.FirearmsSecondary > 0 then
        return NPCWeaponsBridge.FirearmsSecondary
    end
    if NPCWeaponsBridge.IsFirearmsB41Active() and NPCWeaponsBridge.Secondary and #NPCWeaponsBridge.Secondary > 0 then
        return NPCWeaponsBridge.Secondary
    end
    if clan and clan.Secondary and #clan.Secondary > 0 then
        return clan.Secondary
    end
    return NPCWeaponsBridge.Secondary
end

NPCWeaponsBridge.GetSpawnMelee = function(clan)
    if NPCWeaponsBridge.IntegratedMelee and #NPCWeaponsBridge.IntegratedMelee >= 8 then
        return NPCWeaponsBridge.IntegratedMelee
    end
    if NPCWeaponsBridge.IsBritaArsenalActive() and NPCWeaponsBridge.BritaArsenalMelee and #NPCWeaponsBridge.BritaArsenalMelee > 0 then
        return NPCWeaponsBridge.BritaArsenalMelee
    end
    if NPCWeaponsBridge.IsFirearmsRevampActive() and NPCWeaponsBridge.FirearmsMelee and #NPCWeaponsBridge.FirearmsMelee > 0 then
        return NPCWeaponsBridge.FirearmsMelee
    end
    if NPCWeaponsBridge.GetMeleeForClan then
        return NPCWeaponsBridge.GetMeleeForClan(clan)
    end
    if clan and clan.Melee and #clan.Melee > 0 then
        return clan.Melee
    end
    return NPCWeaponsBridge.Melee
end

local function appendFirearms(target, specs)
    NPCLoadoutRegistry.AppendFirearms(target, specs, NPCWeaponsBridge.MakeHandgun)
end

local function appendFirearmsUnique(target, specs, source)
    if NPCLoadoutRegistry.AppendFirearmsUnique then
        return NPCLoadoutRegistry.AppendFirearmsUnique(target, specs, NPCWeaponsBridge.MakeHandgun, source)
    end
    return NPCLoadoutRegistry.AppendFirearms(target, specs, NPCWeaponsBridge.MakeHandgun)
end

local function loadStandardSet()
    NPCWeaponsBridge.Primary = NPCWeaponsBridge.Primary or {}
    NPCWeaponsBridge.Secondary = NPCWeaponsBridge.Secondary or {}
    NPCWeaponsBridge.Melee = NPCWeaponsBridge.Melee or {}
    NPCWeaponsBridge.IntegratedPrimary = NPCWeaponsBridge.IntegratedPrimary or {}
    NPCWeaponsBridge.IntegratedSecondary = NPCWeaponsBridge.IntegratedSecondary or {}
    NPCWeaponsBridge.IntegratedMelee = NPCWeaponsBridge.IntegratedMelee or {}
    appendFirearms(NPCWeaponsBridge.Primary, NPCLoadoutRegistry.VanillaPrimary)
    appendFirearms(NPCWeaponsBridge.Secondary, NPCLoadoutRegistry.VanillaSecondary)
end

local function loadOptionalSet()
    if NPCLoadoutRegistry.IsBritaArsenalActive and NPCLoadoutRegistry.IsBritaArsenalActive() then
        NPCWeaponsBridge.BritaArsenalPrimary = NPCWeaponsBridge.BritaArsenalPrimary or {}
        NPCWeaponsBridge.BritaArsenalSecondary = NPCWeaponsBridge.BritaArsenalSecondary or {}
        NPCWeaponsBridge.BritaArsenalMelee = NPCWeaponsBridge.BritaArsenalMelee or {}
        appendFirearmsUnique(NPCWeaponsBridge.BritaArsenalPrimary, NPCLoadoutRegistry.BritaArsenalPrimary, "britaArsenal")
        appendFirearmsUnique(NPCWeaponsBridge.BritaArsenalSecondary, NPCLoadoutRegistry.BritaArsenalSecondary, "britaArsenal")
        appendFirearmsUnique(NPCWeaponsBridge.Primary, NPCLoadoutRegistry.BritaArsenalPrimary, "britaArsenal")
        appendFirearmsUnique(NPCWeaponsBridge.Secondary, NPCLoadoutRegistry.BritaArsenalSecondary, "britaArsenal")
        appendFirearmsUnique(NPCWeaponsBridge.IntegratedPrimary, NPCLoadoutRegistry.BritaArsenalPrimary, "britaArsenal")
        appendFirearmsUnique(NPCWeaponsBridge.IntegratedSecondary, NPCLoadoutRegistry.BritaArsenalSecondary, "britaArsenal")
        NPCLoadoutRegistry.AppendMelee(NPCWeaponsBridge.Melee, NPCLoadoutRegistry.BritaArsenalMelee)
        NPCLoadoutRegistry.AppendMelee(NPCWeaponsBridge.BritaArsenalMelee, NPCLoadoutRegistry.BritaArsenalMelee)
        NPCLoadoutRegistry.AppendMelee(NPCWeaponsBridge.IntegratedMelee, NPCLoadoutRegistry.BritaArsenalMelee)
    end

    if NPCLoadoutRegistry.IsPSAActive and NPCLoadoutRegistry.IsPSAActive() then
        NPCWeaponsBridge.PSAPrimary = NPCWeaponsBridge.PSAPrimary or {}
        NPCWeaponsBridge.PSASecondary = NPCWeaponsBridge.PSASecondary or {}
        NPCWeaponsBridge.PSAMelee = NPCWeaponsBridge.PSAMelee or {}
        appendFirearmsUnique(NPCWeaponsBridge.PSAPrimary, NPCLoadoutRegistry.PSAPrimary, "psa")
        appendFirearmsUnique(NPCWeaponsBridge.PSASecondary, NPCLoadoutRegistry.PSASecondary, "psa")
        appendFirearmsUnique(NPCWeaponsBridge.Primary, NPCLoadoutRegistry.PSAPrimary, "psa")
        appendFirearmsUnique(NPCWeaponsBridge.Secondary, NPCLoadoutRegistry.PSASecondary, "psa")
        appendFirearmsUnique(NPCWeaponsBridge.IntegratedPrimary, NPCLoadoutRegistry.PSAPrimary, "psa")
        appendFirearmsUnique(NPCWeaponsBridge.IntegratedSecondary, NPCLoadoutRegistry.PSASecondary, "psa")
        NPCWeaponsBridge._registrationSource = "psa"
        NPCLoadoutRegistry.AppendMelee(NPCWeaponsBridge.Melee, NPCLoadoutRegistry.PSAMelee)
        NPCLoadoutRegistry.AppendMelee(NPCWeaponsBridge.PSAMelee, NPCLoadoutRegistry.PSAMelee)
        NPCLoadoutRegistry.AppendMelee(NPCWeaponsBridge.IntegratedMelee, NPCLoadoutRegistry.PSAMelee)
        NPCWeaponsBridge._registrationSource = nil
    end

    if NPCLoadoutRegistry.IsBCGRareWeaponsActive and NPCLoadoutRegistry.IsBCGRareWeaponsActive() then
        NPCWeaponsBridge.BCGRareWeaponsMelee = NPCWeaponsBridge.BCGRareWeaponsMelee or {}
        NPCWeaponsBridge._registrationSource = "bcgRareWeapons"
        NPCLoadoutRegistry.AppendMelee(NPCWeaponsBridge.Melee, NPCLoadoutRegistry.BCGRareWeaponsMelee)
        NPCLoadoutRegistry.AppendMelee(NPCWeaponsBridge.BCGRareWeaponsMelee, NPCLoadoutRegistry.BCGRareWeaponsMelee)
        NPCLoadoutRegistry.AppendMelee(NPCWeaponsBridge.IntegratedMelee, NPCLoadoutRegistry.BCGRareWeaponsMelee)
        NPCWeaponsBridge._registrationSource = nil
    end

    if NPCLoadoutRegistry.IsScrapSmithActive and NPCLoadoutRegistry.IsScrapSmithActive() then
        NPCWeaponsBridge.ScrapSmithMelee = NPCWeaponsBridge.ScrapSmithMelee or {}
        NPCWeaponsBridge._registrationSource = "scrapSmith"
        NPCLoadoutRegistry.AppendMelee(NPCWeaponsBridge.Melee, NPCLoadoutRegistry.ScrapSmithMelee)
        NPCLoadoutRegistry.AppendMelee(NPCWeaponsBridge.ScrapSmithMelee, NPCLoadoutRegistry.ScrapSmithMelee)
        NPCLoadoutRegistry.AppendMelee(NPCWeaponsBridge.IntegratedMelee, NPCLoadoutRegistry.ScrapSmithMelee)
        NPCWeaponsBridge._registrationSource = nil
    end

    if NPCLoadoutRegistry.HasMod("firearmmod") or NPCLoadoutRegistry.HasMod("firearmmodRevamp") then
        appendFirearms(NPCWeaponsBridge.Primary, NPCLoadoutRegistry.FirearmModPrimary)
        appendFirearms(NPCWeaponsBridge.Secondary, NPCLoadoutRegistry.FirearmModSecondary)
    end

    if NPCLoadoutRegistry.HasMod("VFExpansion1") then
        appendFirearms(NPCWeaponsBridge.Primary, NPCLoadoutRegistry.VFExpansionPrimary)
        appendFirearms(NPCWeaponsBridge.Secondary, NPCLoadoutRegistry.VFExpansionSecondary)
    end

    if NPCLoadoutRegistry.HasMod("Guns93") then
        appendFirearms(NPCWeaponsBridge.Secondary, NPCLoadoutRegistry.Guns93Secondary)
        appendFirearms(NPCWeaponsBridge.Primary, NPCLoadoutRegistry.Guns93Primary)
    end
end

local function loadRevampSet()
    if not NPCLoadoutRegistry.HasMod("firearmmodRevamp") then return end
    NPCWeaponsBridge._registrationSource = "firearmmodRevamp"
    NPCLoadoutRegistry.AppendViaRegister(NPCLoadoutRegistry.FirearmsRevampPrimary, NPCWeaponsBridge.AddPrimary)
    NPCLoadoutRegistry.AppendViaRegister(NPCLoadoutRegistry.FirearmsRevampSecondary, NPCWeaponsBridge.AddSecondary)
    for i = 1, #NPCLoadoutRegistry.FirearmsRevampMelee do
        NPCWeaponsBridge.AddMelee(NPCLoadoutRegistry.FirearmsRevampMelee[i])
    end
    NPCWeaponsBridge._registrationSource = nil
end

loadStandardSet()
loadOptionalSet()
loadRevampSet()
