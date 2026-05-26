require "NPCBehavior/NPCBehaviorBridge"

NPCProgramCompanionGuardBridge = NPCProgramCompanionGuardBridge or {}

local Bridge = NPCBehaviorBridge

function NPCProgramCompanionGuardBridge.GetCapabilities()
    return Bridge.Capabilities({
        melee = true,
        shoot = true,
        smashWindow = true,
        openDoor = true,
        breakDoor = true,
        breakObjects = true,
        unbarricade = false,
        disableGenerators = false,
        sabotageCars = false
    })
end

function NPCProgramCompanionGuardBridge.Prepare(bandit)
    return Bridge.PrepareEquipOnly(bandit, {stationary = true, next = "Guard"})
end

function NPCProgramCompanionGuardBridge.Guard(bandit)
    local tasks = {}
    local brain = Bridge.GetBrain(bandit)
    local order = Bridge.GetOrder(brain)

    local anchorTask, hasAnchorOrder = Bridge.GuardAnchorMoveTask(bandit, brain, order)
    if anchorTask then
        table.insert(tasks, anchorTask)
        return Bridge.Result("Guard", tasks)
    end

    if not Bridge.HasGuardPost(bandit) and not hasAnchorOrder then
        Bridge.SetProgram(bandit, "Companion", {})
        return Bridge.Result("Prepare", tasks)
    end

    local guardTasks = Bridge.FaceThreatOrIdleTasks(bandit, 12)
    for _, task in pairs(guardTasks) do
        table.insert(tasks, task)
    end

    return Bridge.Result("Guard", tasks)
end
