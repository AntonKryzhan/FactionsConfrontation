require "NPCCore/NPCCreatorBridge"
require "NPCCore/NPCCompatibilityBridge"
require "NPCCore/NPCUtilityCore"
require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCLegacyGlobalsBridge"
-- NPCDebugSpawnSurvivorBridge.lua
-- Neutral client bridge for the legacy legacy debug-spawn survivor client module.

--
-- ********************************
-- *** NPC zombies           ***
-- ********************************
-- *** Debug survivor spawner    ***
-- ********************************
--

NPCDebugSpawnSurvivorBridge = NPCDebugSpawnSurvivorBridge or {}

local NPC_DEBUG_SPAWN_TEXT_PREFIX = NPCLegacyContractBridge.Text.prefix

local function debugSpawnText(key)
    return getText(NPC_DEBUG_SPAWN_TEXT_PREFIX .. tostring(key or ""))
end

local function isAdminOnly()
    if isAdmin and isAdmin() then
        return true
    end

    return false
end

local function sayPlayer(player, text)
    if player and player.Say then
        player:Say(text)
    end
end

local function isWaterSquare(square)
    if not square then return true end

    if square.isWater then
        local ok, ret = pcall(function() return square:isWater() end)
        if ok and ret then return true end
    end

    local props = square:getProperties()
    if props and props:Is(IsoFlagType.water) then
        return true
    end

    return false
end

local function hasGround(square)
    if not square then return false end

    if square:getZ() == 0 then
        return true
    end

    if square.getFloor then
        local ok, floor = pcall(function() return square:getFloor() end)
        if ok and floor then return true end
    end

    return false
end

function NPCDebugSpawnSurvivorBridge.IsValidSpawnSquare(square)
    if not square then return false end
    if not hasGround(square) then return false end
    if isWaterSquare(square) then return false end

    if SafeHouse and SafeHouse.isSafeHouse and SafeHouse.isSafeHouse(square, nil, true) then
        return false
    end

    if square:getBuilding() then
        return false
    end

    if square:getVehicleContainer() then
        return false
    end

    if not square:isFree(false) then
        return false
    end

    return true
end

function NPCDebugSpawnSurvivorBridge.FindSquareNearPlayer(player)
    if not player then return nil end

    local cell = getCell()
    if not cell then return nil end

    local px = math.floor(player:getX())
    local py = math.floor(player:getY())
    local pz = 0
    local candidates = {}

    for radius = 2, 14 do
        candidates = {}

        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.abs(dx) == radius or math.abs(dy) == radius then
                    local square = cell:getGridSquare(px + dx, py + dy, pz)
                    if NPCDebugSpawnSurvivorBridge.IsValidSpawnSquare(square) then
                        table.insert(candidates, square)
                    end
                end
            end
        end

        if #candidates > 0 then
            return candidates[1 + ZombRand(#candidates)]
        end
    end

    return nil
end

local function makeFallbackSurvivor()
    local clan = nil
    if NPCCreatorBridge and NPCCreatorBridge.GetDefaultProfile then
        clan = NPCCreatorBridge.GetDefaultProfile("Civilian")
    end

    local melee = NPCCompatibilityBridge.GetLegacyItem("Base.Plank")
    local outfit = "Generic01"
    local femaleChance = 40
    local health = 3.0
    local clanId = 1
    local eatBody = false
    local accuracyBoost = 0.8
    local loot = {}

    if clan then
        clanId = clan.id or clanId
        femaleChance = clan.femaleChance or femaleChance
        health = clan.health or health
        eatBody = clan.eatBody or eatBody
        accuracyBoost = clan.accuracyBoost or accuracyBoost

        if clan.Melee and #clan.Melee > 0 then
            melee = NPCUtilityCore.Choice(clan.Melee)
        end

        if clan.Outfits and #clan.Outfits > 0 then
            outfit = NPCUtilityCore.Choice(clan.Outfits)
        end

        if clan.Loot then
            loot = NPCCreatorBridge.MakeLoot(clan.Loot)
        end
    end

    local weapons = {}
    weapons.primary = {name=false, magSize=0, bulletsLeft=0, magCount=0}
    weapons.secondary = {name=false, magSize=0, bulletsLeft=0, magCount=0}
    weapons.melee = melee

    local bandit = {}
    bandit.clan = clanId
    bandit.health = health
    bandit.femaleChance = femaleChance
    bandit.eatBody = eatBody
    bandit.accuracyBoost = accuracyBoost
    bandit.weapons = weapons
    bandit.outfit = outfit
    bandit.loot = loot

    return bandit
end

function NPCDebugSpawnSurvivorBridge.MakeSurvivor()
    local wave = {}
    wave.clanId = 1
    wave.hasPistolChance = 0
    wave.pistolMagCount = 0
    wave.hasRifleChance = 0
    wave.rifleMagCount = 0

    if NPCCreatorBridge and NPCCreatorBridge.MakeFromWave then
        local ok, bandit = pcall(function() return NPCCreatorBridge.MakeFromWave(wave) end)
        if ok and bandit then
            return bandit
        end
    end

    return makeFallbackSurvivor()
end

function NPCDebugSpawnSurvivorBridge.SpawnNearPlayer(player)
    if not player then return end

    local square = NPCDebugSpawnSurvivorBridge.FindSquareNearPlayer(player)
    if not square then
        sayPlayer(player, "No valid outdoor spawn square nearby.")
        print("[WARN] NPC debug survivor spawn failed: no valid square near player.")
        return
    end

    local event = {}
    event.occured = false
    event.hostile = false
    event.program = {}
    event.program.name = "Companion"
    event.program.stage = "Prepare"
    event.bandits = {}
    event.x = square:getX()
    event.y = square:getY()
    event.z = square:getZ()

    table.insert(event.bandits, NPCDebugSpawnSurvivorBridge.MakeSurvivor())

    sendClientCommand(player, 'NPCCommands', 'SpawnGroup', event)
    sayPlayer(player, "Survivor spawned nearby.")
    print("[INFO] NPC debug survivor spawned near player at " .. tostring(event.x) .. "," .. tostring(event.y) .. "," .. tostring(event.z))
end

local function onPreFillWorldObjectContextMenu(playerID, context, worldobjects, test)
    if test then return end
    if not isAdminOnly() then return end

    local player = getSpecificPlayer(playerID)
    if not player then return end

    context:addOption("[NPC] " .. debugSpawnText("Menu_SpawnSurvivorNearMe"), player, NPCDebugSpawnSurvivorBridge.SpawnNearPlayer)
end

Events.OnPreFillWorldObjectContextMenu.Add(onPreFillWorldObjectContextMenu)

NPCLegacyGlobalsBridge.InstallAlias("DebugSpawnSurvivor", NPCDebugSpawnSurvivorBridge, "NPCDebugSpawnSurvivorBridge")
