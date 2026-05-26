require "NPCBehavior/NPCBehaviorBridge"
require "NPCCore/NPCEntityState"
require "NPCCore/NPCUtilityCore"
require "NPCCore/NPCLegacyContractBridge"

NPCProgramRaiderBridge = NPCProgramRaiderBridge or {}

local Bridge = NPCBehaviorBridge

local function result(nextStage, tasks)
    if Bridge and Bridge.Result then return Bridge.Result(nextStage, tasks) end
    return {status = true, next = nextStage, tasks = tasks or {}}
end

local function prepareFallback(bandit)
    local tasks = {}
    if NPCEntityState then
        if NPCEntityState.ForceStationary then NPCEntityState.ForceStationary(bandit, false) end
        if NPCEntityState.SetWeapons and NPCEntityState.GetWeapons then NPCEntityState.SetWeapons(bandit, NPCEntityState.GetWeapons(bandit)) end
    end

    local primary = NPCEntityState and NPCEntityState.GetBestWeapon and NPCEntityState.GetBestWeapon(bandit) or nil
    local secondary
    local world = getWorld and getWorld() or nil
    local climate = world and world.getClimateManager and world:getClimateManager() or nil
    local daylight = climate and climate.getDayLightStrength and climate:getDayLightStrength() or 1
    if Bridge and Bridge.GetSandboxBool and Bridge.GetSandboxBool("General_CarryTorches", false) and daylight < 0.3 then
        secondary = "Base.HandTorch"
    end

    table.insert(tasks, {action = "Equip", itemPrimary = primary, itemSecondary = secondary})
    return result("Follow", tasks)
end

function NPCProgramRaiderBridge.GetCapabilities()
    if Bridge and Bridge.Capabilities then
        return Bridge.Capabilities({
            melee = true,
            shoot = true,
            smashWindow = true,
            openDoor = true,
            breakDoor = true,
            breakObjects = true,
            unbarricade = true,
            disableGenerators = true,
            sabotageCars = true
        })
    end

    return {
        melee = true,
        shoot = true,
        smashWindow = true,
        openDoor = true,
        breakDoor = true,
        breakObjects = true,
        unbarricade = true,
        disableGenerators = true,
        sabotageCars = true
    }
end

function NPCProgramRaiderBridge.Prepare(bandit)
    if Bridge and Bridge.PrepareEquipOnly then
        return Bridge.PrepareEquipOnly(bandit, {stationary = false, next = "Follow"})
    end
    return prepareFallback(bandit)
end

function NPCProgramRaiderBridge.Follow(bandit)
    local tasks = {}

    if not (Bridge and bandit) then
        table.insert(tasks, {action = "Time", anim = "Shrug", time = 200})
        return result("Follow", tasks)
    end

    local profile = Bridge.HostileWalkProfile and Bridge.HostileWalkProfile(bandit) or {walkType = "Run", endurance = -0.06}

    if Bridge.ShouldHostileEscape and Bridge.ShouldHostileEscape(bandit) then
        return result("Escape", tasks)
    end

    if Bridge.TryHostileServiceOpportunity then
        local serviceStage = Bridge.TryHostileServiceOpportunity(bandit, profile, tasks)
        if serviceStage then return result(serviceStage, tasks) end
    end

    if Bridge.HostileCombatMoveStage then
        local nextStage = Bridge.HostileCombatMoveStage(bandit, profile, tasks)
        return result(nextStage or "Follow", tasks)
    end

    table.insert(tasks, {action = "Time", anim = "Shrug", time = 200})
    return result("Follow", tasks)
end

function NPCProgramRaiderBridge.Escape(bandit)
    local tasks = {}

    if Bridge then
        local surrender = Bridge.HostileSurrenderResult and Bridge.HostileSurrenderResult(bandit, tasks) or nil
        if surrender then return surrender end

        local profile = Bridge.WalkProfile and Bridge.WalkProfile(bandit, {
            defaultWalkType = "Run",
            defaultEndurance = -0.06,
            limpWalkType = "Limp",
            limpEndurance = 0
        }) or {walkType = "Run", endurance = -0.06}

        local escapeTask = Bridge.EscapeTaskAwayFromClosestPlayer and Bridge.EscapeTaskAwayFromClosestPlayer(bandit, {
            deltaX = 100 + ((Bridge.GetCharacterId and math.abs(Bridge.GetCharacterId(bandit)) or 0) % 100),
            deltaY = 100 + ((Bridge.GetCharacterId and math.abs(Bridge.GetCharacterId(bandit) * 3) or 0) % 100),
            walkType = profile.walkType,
            endurance = profile.endurance,
            closeDistance = 12
        }) or nil
        if escapeTask then table.insert(tasks, escapeTask) end
        return result("Escape", tasks)
    end

    if NPCUtilityCore and NPCUtilityCore.GetClosestPlayerLocation and NPCUtilityCore.GetMoveTask then
        local closest = NPCUtilityCore.GetClosestPlayerLocation(bandit)
        if closest and closest.x and closest.y then
            table.insert(tasks, NPCUtilityCore.GetMoveTask(-0.06, closest.x + 120, closest.y + 120, 0, "Run", 12, false))
        end
    end
    return result("Escape", tasks)
end

function NPCProgramRaiderBridge.Surrender(bandit)
    local tasks = {}
    if ZombRand and ZombRand(2) == 0 then
        table.insert(tasks, {action = "Time", anim = "Surrender", time = 40})
    else
        table.insert(tasks, {action = "Time", anim = "Scramble", time = 40})
    end
    return result("Surrender", tasks)
end

function NPCProgramRaiderBridge.TurnOffGenerator(bandit)
    local tasks = {}
    if Bridge and Bridge.DisableGeneratorAtCurrentSquare then
        return Bridge.DisableGeneratorAtCurrentSquare(bandit, tasks)
    end

    local square = bandit and bandit.getSquare and bandit:getSquare() or nil
    local generator = square and square.getGenerator and square:getGenerator() or nil
    if generator and generator.isActivated and generator:isActivated() then
        table.insert(tasks, {action = "Time", anim = "LootLow", time = 40})
        table.insert(tasks, {action = "Time", anim = "LootLow", time = 40})
        generator:setActivated(false)
        if square.playSound then square:playSound("WorldEventElectricityShutdown") end
    end
    return result("Follow", tasks)
end

function NPCProgramRaiderBridge.SabotageVehicle(bandit)
    local tasks = {}
    if Bridge and Bridge.HostileSabotageVehicleResult then
        return Bridge.HostileSabotageVehicleResult(bandit, tasks, "Run")
    end
    return result("Follow", tasks)
end

function NPCProgramRaiderBridge.BuildBridge(bandit)
    local tasks = {}
    if Bridge and Bridge.BuildBridgeNearNPCResult then
        return Bridge.BuildBridgeNearNPCResult(bandit, tasks)
    elseif Bridge then
        local legacyBuildBridge = Bridge["BuildBridgeNear" .. NPCLegacyContractBridge.Token .. "Result"]
        if legacyBuildBridge then return legacyBuildBridge(bandit, tasks) end
    end
    return result("Follow", tasks)
end
