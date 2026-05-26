require "NPCBehavior/NPCBehaviorBridge"

NPCProgramDefendBridge = NPCProgramDefendBridge or {}

local Bridge = NPCBehaviorBridge

function NPCProgramDefendBridge.GetCapabilities()
    return Bridge.Capabilities({
        melee = true,
        shoot = true,
        smashWindow = false,
        openDoor = true,
        breakDoor = false,
        breakObjects = false,
        unbarricade = false,
        disableGenerators = false,
        sabotageCars = false
    })
end

function NPCProgramDefendBridge.Prepare(bandit)
    return Bridge.PrepareArmed(bandit, {stationary = true, next = "Wait", returnEmptyTasks = true})
end

function NPCProgramDefendBridge.Wait(bandit)
    local tasks = {}

    if Bridge.IsOutside(bandit) then
        Bridge.SwitchProgram(bandit, "Looter", {}, false)
    end

    local schedule = Bridge.DefenderSchedule()
    local spotDist = schedule.spotDist

    if schedule.sleeping then
        Bridge.SetSleeping(bandit, true)
        Bridge.TryMattressAtNPC(bandit)
        table.insert(tasks, {action = "Sleep", anim = "Sleep", time = 100})
    else
        Bridge.SetSleeping(bandit, false)
        local idleTask = Bridge.GuardIdleTask()
        if idleTask then
            table.insert(tasks, idleTask)
            if idleTask.anim == "Smoke" then
                table.insert(tasks, idleTask)
                table.insert(tasks, idleTask)
            end
        end
    end

    local intruder = Bridge.FindBuildingIntruder(bandit, spotDist)
    if intruder then
        Bridge.ReactToDefenderIntruder(bandit)
        return Bridge.Result("Prepare", tasks)
    end

    return Bridge.Result("Wait", tasks)
end
