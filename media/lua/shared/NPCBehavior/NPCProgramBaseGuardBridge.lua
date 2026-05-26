NPCProgramBaseGuardBridge = NPCProgramBaseGuardBridge or {}

require "NPCBehavior/NPCBehaviorBridge"
require "NPCCore/NPCLegacyContractBridge"

local Bridge = NPCBehaviorBridge
local NPC_PROGRAM_LEGACY_ENTITY_GLOBAL = NPCLegacyContractBridge.Key("FLAG")

local function npcEntity()
    return NPCEntity or (_G and _G[NPC_PROGRAM_LEGACY_ENTITY_GLOBAL]) or nil
end

local function npcEntityCall(name, ...)
    local entity = npcEntity()
    local fn = entity and entity[name]
    if type(fn) ~= "function" then return nil end
    return fn(...)
end

local CAPABILITIES = {
    melee = true,
    shoot = true,
    smashWindow = true,
    openDoor = true,
    breakDoor = true,
    breakObjects = true,
    unbarricade = true,
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

local function repeatTask(tasks, task, count)
    for _=1, count do
        table.insert(tasks, task)
    end
end

local function appendRestTask(tasks)
    local action = ZombRand(50)
    if action == 0 then
        table.insert(tasks, {action="Sleep", anim="SitRubHands", time=200})
    elseif action == 1 then
        repeatTask(tasks, {action="Sleep", anim="SitMaking", time=100}, 3)
    elseif action < 30 then
        table.insert(tasks, {action="Sleep", anim="SitAction", time=200})
    else
        table.insert(tasks, {action="Sleep", anim="Sit", time=200})
    end
end

local function appendGuardTask(tasks)
    local action = ZombRand(50)
    if action == 0 then
        table.insert(tasks, {action="Time", anim="Cough", time=200})
    elseif action == 1 then
        table.insert(tasks, {action="Time", anim="ChewNails", time=200})
    elseif action == 2 then
        repeatTask(tasks, {action="Time", anim="Smoke", time=200}, 3)
    else
        table.insert(tasks, {action="Time", anim="ShiftWeight", time=200})
    end
end

local function currentSchedule(hour)
    if hour >= 0 and hour < 7 then
        return "sleep", 5
    end
    if (hour >= 7 and hour < 8) or (hour >= 12 and hour < 13) or (hour >= 19 and hour < 22) then
        return "rest", 20
    end
    return "guard", 30
end

local function appendScheduledTask(bandit, tasks, mode)
    if mode == "sleep" then
        npcEntityCall("SetSleeping", bandit, true)
        table.insert(tasks, {action="Sleep", anim="Sleep", time=100})
    elseif mode == "rest" then
        npcEntityCall("SetSleeping", bandit, true)
        appendRestTask(tasks)
    else
        npcEntityCall("SetSleeping", bandit, false)
        appendGuardTask(tasks)
    end
end

local function spottedPlayer(bandit, spotDist)
    local playerList = NPCPlayerClient.GetPlayers()
    for i=0, playerList:size()-1 do
        local player = playerList:get(i)
        if player and bandit:CanSee(player) and not NPCPlayerClient.IsGhost(player) then
            local effectiveDist = spotDist
            if player:isSneaking() then effectiveDist = effectiveDist - 3 end
            local dist = NPCUtils.DistTo(player:getX(), player:getY(), bandit:getX(), bandit:getY())
            if dist <= effectiveDist then
                return player
            end
        end
    end
end

local function wakeAndHandoff(bandit, tasks)
    npcEntityCall("Say", bandit, "SPOTTED")
    npcEntityCall("SetSleeping", bandit, false)
    npcEntityCall("ClearTasks", bandit)
    npcEntityCall("SetProgram", bandit, "Raider", {})
    npcEntityCall("ForceStationary", bandit, false)
    return {status=true, next="Prepare", tasks=tasks}
end

function NPCProgramBaseGuardBridge.GetCapabilities()
    return cloneCapabilities()
end

function NPCProgramBaseGuardBridge.Prepare(bandit)
    local tasks = {}

    npcEntityCall("ForceStationary", bandit, true)
    npcEntityCall("SetWeapons", bandit, npcEntityCall("GetWeapons", bandit))
    table.insert(tasks, {action="Equip", itemPrimary=npcEntityCall("GetBestWeapon", bandit), itemSecondary=nil})

    return {status=true, next="Wait", tasks={}}
end

function NPCProgramBaseGuardBridge.Wait(bandit)
    local tasks = {}
    local mode, spotDist = currentSchedule(getGameTime():getHour())

    appendScheduledTask(bandit, tasks, mode)

    if spottedPlayer(bandit, spotDist) then
        return wakeAndHandoff(bandit, tasks)
    end

    return {status=true, next="Wait", tasks=tasks}
end
