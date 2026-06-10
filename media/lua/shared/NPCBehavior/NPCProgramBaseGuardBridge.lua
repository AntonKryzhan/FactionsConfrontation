NPCProgramBaseGuardBridge = NPCProgramBaseGuardBridge or {}

require "NPCBehavior/NPCBehaviorBridge"
require "NPCBehavior/NPCBrainDataBridge"
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
    local brain = NPCBrainDataBridge and NPCBrainDataBridge.Get and NPCBrainDataBridge.Get(bandit) or nil
    local questGuard = brain and brain.blackMarketQuestGuard == true
    if brain and ((brain.checkpointGuard == true or brain.checkpointPhysical == true or brain.checkpointId) or questGuard) and not brain.breachPursuit and not brain.checkpointBreachPursuit then
        local anchor = brain.guardPoint or brain.holdPoint or (type(brain.order) == "table" and (brain.order.guardPoint or brain.order.anchor)) or nil
        if type(anchor) == "table" and anchor.x and anchor.y and NPCUtils and NPCUtils.DistTo then
            local dist = NPCUtils.DistTo(bandit:getX(), bandit:getY(), tonumber(anchor.x) or bandit:getX(), tonumber(anchor.y) or bandit:getY())
            if dist > math.max(3, tonumber(brain.checkpointHoldRadius) or 5) then
                table.insert(tasks, {action="Move", time=120, endurance=0.01, x=tonumber(anchor.x), y=tonumber(anchor.y), z=tonumber(anchor.z) or bandit:getZ(), walkType="Run", closeSlow=false, checkpointReturn=true})
                return {status=true, next="Wait", tasks=tasks}
            end
        end
        appendGuardTask(tasks)
        if spottedPlayer(bandit, spotDist) then
            if questGuard then
                npcEntityCall("Say", bandit, "SPOTTED")
                npcEntityCall("SetSleeping", bandit, false)
                npcEntityCall("ForceStationary", bandit, true)
                return {status=true, next="Wait", tasks=tasks}
            end
            return wakeAndHandoff(bandit, tasks)
        end
        return {status=true, next="Wait", tasks=tasks}
    end

    if mode == "guard" and Bridge and Bridge.TryLivingWorldTask then
        local profile = Bridge.WalkProfile and Bridge.WalkProfile(bandit, {defaultWalkType = "Walk", defaultEndurance = 0, limpWalkType = "Limp", limpEndurance = 0}) or {walkType = "Walk", endurance = 0}
        if Bridge.TryLivingWorldTask(bandit, tasks, profile, {program = "BaseGuard", allowLoot = false, allowBaseLife = true, cooldownMs = 5200, baseCooldownMs = 5600, fallbackAnim = "ShiftWeight"}) then
            if spottedPlayer(bandit, spotDist) then
                return wakeAndHandoff(bandit, tasks)
            end
            return {status=true, next="Wait", tasks=tasks}
        end
    end

    appendScheduledTask(bandit, tasks, mode)

    if spottedPlayer(bandit, spotDist) then
        return wakeAndHandoff(bandit, tasks)
    end

    return {status=true, next="Wait", tasks=tasks}
end
