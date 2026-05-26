-- NPCOutfitsBridge.lua
-- Neutral shared backend for NPC outfit pools.

-- register modded outfits by adding them to tables below

require "NPCCore/NPCLegacyContractBridge"

NPCOutfitsBridge = NPCOutfitsBridge or {}

local NPC_OUTFITS_LEGACY = NPCLegacyContractBridge.Outfits

-- WAVE 1
NPCOutfitsBridge.DesperateCitizen = NPCOutfitsBridge.DesperateCitizen or {}
table.insert(NPCOutfitsBridge.DesperateCitizen, "Bathrobe")
table.insert(NPCOutfitsBridge.DesperateCitizen, "Generic02")
table.insert(NPCOutfitsBridge.DesperateCitizen, "Generic01")
table.insert(NPCOutfitsBridge.DesperateCitizen, "Punk")
table.insert(NPCOutfitsBridge.DesperateCitizen, "Rocker")
table.insert(NPCOutfitsBridge.DesperateCitizen, "Tourist")

if getActivatedMods():contains("Authentic Z - Current") then
    table.insert(NPCOutfitsBridge.DesperateCitizen, "AuthenticHomeless")
    table.insert(NPCOutfitsBridge.DesperateCitizen, "AuthenticElderly")
    table.insert(NPCOutfitsBridge.DesperateCitizen, "AuthenticPostalDude")
    table.insert(NPCOutfitsBridge.DesperateCitizen, "AuthenticSurvivorCovid")
end

-- WAVE 2
NPCOutfitsBridge.Psychopath = NPCOutfitsBridge.Psychopath or {}
table.insert(NPCOutfitsBridge.Psychopath, "Naked")
table.insert(NPCOutfitsBridge.Psychopath, "HockeyPsycho")
table.insert(NPCOutfitsBridge.Psychopath, "HospitalPatient")
table.insert(NPCOutfitsBridge.Psychopath, "Trader")
table.insert(NPCOutfitsBridge.Psychopath, "TinFoilHat")

if getActivatedMods():contains("Authentic Z - Current") then
    table.insert(NPCOutfitsBridge.Psychopath, "AuthenticJasonPart3")
    table.insert(NPCOutfitsBridge.Psychopath, "AuthenticFat01")
    table.insert(NPCOutfitsBridge.Psychopath, "AuthenticFat02")
    table.insert(NPCOutfitsBridge.Psychopath, "AuthenticFat03")
    table.insert(NPCOutfitsBridge.Psychopath, "AuthenticGhostFace")
    table.insert(NPCOutfitsBridge.Psychopath, "AuthenticPolitician")
    table.insert(NPCOutfitsBridge.Psychopath, "AuthenticShortgunFace")
end

if getActivatedMods():contains("Brita_2") then
    table.insert(NPCOutfitsBridge.Psychopath, "Brita_Chain")
end

-- WAVE 3
NPCOutfitsBridge.Cannibal = NPCOutfitsBridge.Cannibal or {}
table.insert(NPCOutfitsBridge.Cannibal, "Woodcut")
table.insert(NPCOutfitsBridge.Cannibal, "Waiter_Restaurant")
table.insert(NPCOutfitsBridge.Cannibal, "Waiter_Diner")
if getActivatedMods():contains("Authentic Z - Current") then
    table.insert(NPCOutfitsBridge.Cannibal, "AuthenticNMRIHButcher")
    table.insert(NPCOutfitsBridge.Cannibal, "AuthenticLeatherFace")
end

-- WAVE 4
NPCOutfitsBridge.Crimial = NPCOutfitsBridge.Crimial or {}
table.insert(NPCOutfitsBridge.Crimial, "Thug")
table.insert(NPCOutfitsBridge.Crimial, "Redneck")
if getActivatedMods():contains("Authentic Z - Current") then
    table.insert(NPCOutfitsBridge.Crimial, "AuthenticBankRobber")
    table.insert(NPCOutfitsBridge.Crimial, "AuthenticNMRIHMolotov")
    table.insert(NPCOutfitsBridge.Crimial, "AuthenticPoncho")
end

if getActivatedMods():contains("Brita_2") then
    table.insert(NPCOutfitsBridge.Crimial, "Brita_Killa_2")
end

-- WAVE 5
NPCOutfitsBridge.Inmate = NPCOutfitsBridge.Inmate or {}
table.insert(NPCOutfitsBridge.Inmate, "Inmate")
table.insert(NPCOutfitsBridge.Inmate, "InmateEscaped")

-- WAVE 6
NPCOutfitsBridge.Police = NPCOutfitsBridge.Police or {}
table.insert(NPCOutfitsBridge.Police, "Police")
table.insert(NPCOutfitsBridge.Police, "PoliceState")
table.insert(NPCOutfitsBridge.Police, "PoliceRiot")
table.insert(NPCOutfitsBridge.Police, "PrisonGuard")

if getActivatedMods():contains("Authentic Z - Current") then
    table.insert(NPCOutfitsBridge.Police, "AuthenticSurvivorPolice")
    table.insert(NPCOutfitsBridge.Police, "AuthenticSecretService")
end

if getActivatedMods():contains("zReSWATARMORbykK") then
    table.insert(NPCOutfitsBridge.Police, "zReSA_SWAT1")
    table.insert(NPCOutfitsBridge.Police, "zReSA_SWAT2")
end

-- WAVE 7
NPCOutfitsBridge.Prepper = NPCOutfitsBridge.Prepper or {}
table.insert(NPCOutfitsBridge.Prepper, "Survivalist03")
if getActivatedMods():contains("HNDLBR_Preppers") then
    table.insert(NPCOutfitsBridge.Prepper, "HNDLBR_Prepper")
    table.insert(NPCOutfitsBridge.Prepper, "HNDLBR_DoomsDayPrepper")
end

-- WAVE 8
NPCOutfitsBridge.Veteran = NPCOutfitsBridge.Veteran or {}
table.insert(NPCOutfitsBridge.Veteran, "Veteran")

-- WAVE 9
NPCOutfitsBridge.Biker = NPCOutfitsBridge.Biker or {}
table.insert(NPCOutfitsBridge.Biker, "Biker")

if getActivatedMods():contains("Authentic Z - Current") then
    table.insert(NPCOutfitsBridge.Biker, "AuthenticBiker")
    table.insert(NPCOutfitsBridge.Biker, "AuthenticBillMurray")
end

-- WAVE 10
NPCOutfitsBridge.Hunter = NPCOutfitsBridge.Hunter or {}
table.insert(NPCOutfitsBridge.Hunter, "Hunter")

-- WAVE 11
NPCOutfitsBridge.Reclaimer = NPCOutfitsBridge.Reclaimer or {}
table.insert(NPCOutfitsBridge.Reclaimer, "Priest")

if getActivatedMods():contains("Authentic Z - Current") then
    table.insert(NPCOutfitsBridge.Reclaimer, "AuthenticFuneralCoat")
    table.insert(NPCOutfitsBridge.Reclaimer, "AuthenticCultist")
end

-- WAVE 12
NPCOutfitsBridge.Scientist = NPCOutfitsBridge.Scientist or {}
table.insert(NPCOutfitsBridge.Scientist, "HazardSuit")

if getActivatedMods():contains("Authentic Z - Current") then
    table.insert(NPCOutfitsBridge.Scientist, "AuthenticHazardSuit")
    table.insert(NPCOutfitsBridge.Scientist, "AuthenticCEDAHazmatBlue")
    table.insert(NPCOutfitsBridge.Scientist, "AuthenticCEDAHazmatGreen")
    table.insert(NPCOutfitsBridge.Scientist, "AuthenticNBHHazmat")
    table.insert(NPCOutfitsBridge.Scientist, "AuthenticSurvivorHazardSuit")
end

-- WAVE 13
NPCOutfitsBridge.DoomRider = NPCOutfitsBridge.DoomRider or {}
table.insert(NPCOutfitsBridge.DoomRider, NPC_OUTFITS_LEGACY.generic)
table.insert(NPCOutfitsBridge.DoomRider, "Survivalist")

if getActivatedMods():contains("Brita_2") then
    table.insert(NPCOutfitsBridge.DoomRider, NPC_OUTFITS_LEGACY.brita)
    table.insert(NPCOutfitsBridge.DoomRider, NPC_OUTFITS_LEGACY.brita2)
end

-- WAVE 14
NPCOutfitsBridge.PrivateMilitia = NPCOutfitsBridge.PrivateMilitia or {}
if getActivatedMods():contains("USMilitaryPack") then
    table.insert(NPCOutfitsBridge.PrivateMilitia, "INFANTRY_USMP1")
    table.insert(NPCOutfitsBridge.PrivateMilitia, "INFANTRY_USMP2")
elseif getActivatedMods():contains("Brita_2") then
    table.insert(NPCOutfitsBridge.PrivateMilitia, "Brita_Gorka")
    table.insert(NPCOutfitsBridge.PrivateMilitia, "Brita_Hunter_2")
else
    table.insert(NPCOutfitsBridge.PrivateMilitia, "PrivateMilitia")
    table.insert(NPCOutfitsBridge.PrivateMilitia, "Camper")
end

-- WAVE 15
NPCOutfitsBridge.DeathLegion = NPCOutfitsBridge.DeathLegion or {}

if getActivatedMods():contains("Insurgent") then
    table.insert(NPCOutfitsBridge.DeathLegion, "InsurgentRifleman")
    table.insert(NPCOutfitsBridge.DeathLegion, "InsurgentAssault")
    table.insert(NPCOutfitsBridge.DeathLegion, "InsurgentOfficer")
else
    table.insert(NPCOutfitsBridge.DeathLegion, "ArmyCamoDesert")
end

-- WAVE 16
NPCOutfitsBridge.NewOrder = NPCOutfitsBridge.NewOrder or {}
if getActivatedMods():contains("KATTAJ1_Military") then
    table.insert(NPCOutfitsBridge.NewOrder, "KATTAJ1_Army_Black_Patriot")
    table.insert(NPCOutfitsBridge.NewOrder, "KATTAJ1_Army_Black_Defender")
    table.insert(NPCOutfitsBridge.NewOrder, "KATTAJ1_Army_Black_Vanguard")
    table.insert(NPCOutfitsBridge.NewOrder, "KATTAJ1_Army_Green_Patriot")
    table.insert(NPCOutfitsBridge.NewOrder, "KATTAJ1_Army_Green_Defender")
    table.insert(NPCOutfitsBridge.NewOrder, "KATTAJ1_Army_Green_Vanguard")
else
    table.insert(NPCOutfitsBridge.NewOrder, "ArmyCamoGreen")
    table.insert(NPCOutfitsBridge.NewOrder, "Ghillie")
end
