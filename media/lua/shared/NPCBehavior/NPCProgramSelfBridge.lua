NPCProgramSelfBridge = NPCProgramSelfBridge or {}

require "NPCBehavior/NPCBehaviorBridge"
require "NPCCore/NPCLegacyContractBridge"

local Bridge = NPCBehaviorBridge
local NPC_SELF_LEGACY_ENTITY_GLOBAL = NPCLegacyContractBridge.Key("FLAG")
local NPC_SELF_LEGACY_KEYS = {
    primaryType = NPCLegacyContractBridge.Key("PRIMARY_TYPE")
}

local function npcEntityCall(name, ...)
    local entity = NPCEntity or (_G and _G[NPC_SELF_LEGACY_ENTITY_GLOBAL]) or nil
    local fn = entity and entity[name]
    if type(fn) ~= "function" then return nil end
    return fn(...)
end

local function getItem(bandit, itemTypeTab, cnt)
    return NPCProgramHelpersBridge.GetItem(bandit, itemTypeTab, cnt)
end

function NPCProgramSelfBridge.Idle(bandit)
    local tasks = {}
    local action = ZombRand(50)

    local outOfAmmo = npcEntityCall("IsOutOfAmmo", bandit) == true
    local gameTime = getGameTime()
    local alfa = gameTime:getMinutes() * 4
    local theta = alfa * math.pi / 180
    local x1 = bandit:getX() + 3 * math.cos(theta)
    local y1 = bandit:getY() + 3 * math.sin(theta)

    if action == 0 then
        local task = {action="Time", anim="ShiftWeight", time=200}
        table.insert(tasks, task)
    elseif action == 1 then
        local task = {action="Time", anim="Cough", time=200}
        table.insert(tasks, task)
    elseif action == 2 then
        local task = {action="Time", anim="ChewNails", time=200}
        table.insert(tasks, task)
    elseif action == 3 then
        local task = {action="Time", anim="Smoke", time=200}
        table.insert(tasks, task)
        table.insert(tasks, task)
        table.insert(tasks, task)
    elseif action == 4 then
        local task = {action="Time", anim="PullAtCollar", time=200}
        table.insert(tasks, task)
    elseif action == 5 then
        local task = {action="Time", anim="Sneeze", time=200}
        table.insert(tasks, task)
        addSound(getPlayer(), bandit:getX(), bandit:getY(), bandit:getZ(), 7, 60)
    elseif action == 6 then
        local task = {action="Time", anim="WipeBrow", time=200}
        table.insert(tasks, task)
    elseif action == 7 then
        local task = {action="Time", anim="WipeHead", time=200}
        table.insert(tasks, task)

    elseif not outOfAmmo then
        local anim
        local sound
        local weaponType = Bridge and Bridge.GetPrimaryWeaponType and Bridge.GetPrimaryWeaponType(bandit) or bandit:getVariableString(NPC_SELF_LEGACY_KEYS.primaryType)
        if weaponType == "rifle" then
            sound = "M14BringToBear"
            anim1 = "IdleToAimRifle"
            anim2 = "AimRifle"
        end
        if weaponType == "handgun" then 
            sound = "M9BringToBear"
            anim1 = "IdleToAimPistol"
            anim2 = "AimPistol"
        end

        local task1 = {action="Aim", sound=sound, anim=anim1, x=x1, y=y1, time=30}
        table.insert(tasks, task1)

        local task2 = {action="Aim", anim=anim2, x=x1, y=y1, time=100}
        table.insert(tasks, task2)

        local task3 = {action="Aim", anim=anim2, x=x1, y=y1, time=100}
        table.insert(tasks, task3)
    else
        local task = {action="Time", anim="ShiftWeight", time=200}
        table.insert(tasks, task)
    end
    return tasks
end

function NPCProgramSelfBridge.Wash(bandit)
    local tasks = {}

    local visual = bandit:getHumanVisual()
    local bodyBlood = 0
    local bodyDirt = 0
    for i=1, BloodBodyPartType.MAX:index() do
        local part = BloodBodyPartType.FromIndex(i-1)
        bodyBlood = bodyBlood + visual:getBlood(part)
        bodyDirt = bodyDirt + visual:getDirt(part)
    end
    --[[
    if bodyBlood > 0 then
        print ("blood: " .. bodyBlood)
    end
    if bodyDirt > 0 then
        print ("dirt: " .. bodyDirt)
    end]]

    if bodyBlood + bodyDirt < 10 then return tasks end

    local itemType = "Base.Soap2"
    local inventory = bandit:getInventory()
    if inventory:getItemCountFromTypeRecurse(itemType) > 0 then
        local source = NPCBaseClient.GetWaterSource(bandit)
        if source then
            local square = source:getSquare()
            local asquare = AdjacentFreeTileFinder.Find(square, bandit)
            if asquare then
                local dist = NPCUtils.DistTo(bandit:getX(), bandit:getY(), asquare:getX() + 0.5, asquare:getY() + 0.5)
                if dist > 0.90 then
                    table.insert(tasks, NPCUtils.GetMoveTask(0, asquare:getX(), asquare:getY(), asquare:getZ(), "Walk", dist, false))
                    return tasks
                else
                    local task = {action="Wash", anim="washFace", x=square:getX(), y=square:getY(), z=square:getZ(), time=400}
                    table.insert(tasks, task)

                    return tasks
                end
            end
        end
    else

        -- go get soap
        local task = getItem(bandit, {itemType}, 1)
        if task then
            table.insert(tasks, task)
        end
    end

    return tasks
end
