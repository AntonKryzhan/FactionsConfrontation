NPCProgramCivilianBridge = NPCProgramCivilianBridge or {}

require "NPCBehavior/NPCBehaviorBridge"
require "NPCCore/NPCLegacyContractBridge"

local Bridge = NPCBehaviorBridge
local NPC_PROGRAM_LEGACY_ENTITY_GLOBAL = NPCLegacyContractBridge.Keys.FLAG

local function npcEntity()
    return NPCEntity or (_G and _G[NPC_PROGRAM_LEGACY_ENTITY_GLOBAL]) or nil
end

local function npcEntityCall(name, ...)
    local entity = npcEntity()
    local fn = entity and entity[name]
    if type(fn) ~= "function" then return nil end
    return fn(...)
end

local function npcSandboxBool(name, fallback)
    if Bridge and Bridge.GetSandboxBool then return Bridge.GetSandboxBool(name, fallback) end
    local vars = SandboxVars and SandboxVars[NPCLegacyContractBridge.Sandbox.main] or nil
    if vars and vars[name] ~= nil then return vars[name] == true end
    return fallback == true
end

local CAPABILITIES = {
    melee = true,
    shoot = true,
    smashWindow = true,
    openDoor = true,
    breakDoor = true,
    breakObjects = true,
    unbarricade = false,
    disableGenerators = false,
    sabotageCars = false
}

local function cloneCapabilities()
    local capabilities = {}
    for key, value in pairs(CAPABILITIES) do
        capabilities[key] = value
    end
    return capabilities
end

function NPCProgramCivilianBridge.GetCapabilities()
    return cloneCapabilities()
end

function NPCProgramCivilianBridge.Prepare(bandit)
    local tasks = {}
    local world = getWorld()
    local cm = world:getClimateManager()
    local dls = cm:getDayLightStrength()

    npcEntityCall("ForceStationary", bandit, false)
    npcEntityCall("SetWeapons", bandit, npcEntityCall("GetWeapons", bandit))

    local primary = npcEntityCall("GetBestWeapon", bandit)

    local secondary
    if npcSandboxBool("General_CarryTorches", false) and dls < 0.3 then
        secondary = "Base.HandTorch"
    end

    local task = {action="Equip", itemPrimary=primary, itemSecondary=secondary}
    table.insert(tasks, task)

    return {status=true, next="Follow", tasks=tasks}
end

function NPCProgramCivilianBridge.Follow(bandit)
    local tasks = {}

    -- Companion logic depends on one of the players who is the master od the companion
    -- if there is no master, there is nothing to do.
    local master = NPCPlayerClient.GetMasterPlayer(bandit)
    if not master then
        local task = {action="Time", anim="Shrug", time=200}
        table.insert(tasks, task)
        return {status=true, next="Follow", tasks=tasks}
    end

    -- update walktype
    local walkType = "Run"
    local endurance = 0.00
    local dist = NPCUtils.DistTo(bandit:getX(), bandit:getY(), master:getX(), master:getY())

    local health = bandit:getHealth()
    if health < 0.4 then
        walkType = "Limp"
        endurance = 0
    end

    if dist < 22 then
        local closestZombie = NPCUtils.GetClosestZombieLocation(bandit)
        local closestNPC = NPCUtils.GetClosestEnemyNPCLocation(bandit)
        local closestEnemy = closestZombie

        if closestNPC.dist < closestZombie.dist then
            closestEnemy = closestNPC
        end

        if closestEnemy.dist < 8 then
            -- We are trying to save the player, so the friendly should act with high motivation
            -- that translates to running pace (even despite limping) and minimal endurance loss.
            walkType = "Run"
            endurance = -0.01
            table.insert(tasks, NPCUtils.GetMoveTask(endurance, closestEnemy.x, closestEnemy.y, closestEnemy.z, walkType, closestEnemy.dist))
            return {status=true, next="Follow", tasks=tasks}
        end
    end

    -- No enemies,  so follow the player.
    local minDist = 1
    if dist > minDist then
        local id = NPCUtils.GetCharacterID(bandit)

        local theta = master:getDirectionAngle() * math.pi / 180
        local lx = 3 * math.cos(theta)
        local ly = 3 * math.sin(theta)

        local dx = master:getX() - lx
        local dy = master:getY() - ly
        local dz = master:getZ()
        local dxf = ((math.abs(id) % 10) - 5) / 10
        local dyf = ((math.abs(id) % 11) - 5) / 10
        table.insert(tasks, NPCUtils.GetMoveTask(endurance, dx+dxf, dy+dyf, dz, walkType, dist))
    end

    return {status=true, next="Follow", tasks=tasks}
end
