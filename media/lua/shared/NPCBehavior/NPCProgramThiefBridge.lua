require "NPCBehavior/NPCBehaviorBridge"

NPCProgramThiefBridge = NPCProgramThiefBridge or {}

local Bridge = NPCBehaviorBridge

local function predicateAll(item)
    return true
end

function NPCProgramThiefBridge.GetCapabilities()
    return Bridge.Capabilities({
        melee = true,
        shoot = true,
        smashWindow = true,
        openDoor = true,
        breakDoor = true,
        breakObjects = true,
        unbarricade = true,
        disableGenerators = false,
        sabotageCars = false
    })
end

function NPCProgramThiefBridge.Prepare(bandit)
    return Bridge.PrepareArmed(bandit, {stationary = false, next = "Operate"})
end

function NPCProgramThiefBridge.Operate(bandit)
    local tasks = {}
    local profile = Bridge.WalkProfile(bandit, {defaultWalkType = "Run", defaultEndurance = 0})

    local baseId, base = Bridge.GetClosestPlayerBase(bandit)
    if not base then
        return Bridge.Result("Operate", tasks)
    end

    if Bridge.InventoryItemCount(bandit, predicateAll) > 10 then
        return Bridge.Result("Escape", tasks)
    end

    local containerId, containerData = Bridge.GetClosestBaseContainer(bandit, baseId)
    if not containerId or not containerData then
        return Bridge.Result("Escape", tasks)
    end

    local itemType, count = Bridge.FirstContainerItem(containerData)
    if not itemType then
        return Bridge.Result("Escape", tasks)
    end

    local task = Bridge.MakeMoveOrLootTask(bandit, containerData, itemType, count, profile.walkType, profile.endurance)
    if task then
        Bridge.SayToVisiblePlayers(bandit, "THIEF_SPOTTED")
        table.insert(tasks, task)
    end

    return Bridge.Result("Operate", tasks)
end

function NPCProgramThiefBridge.Wait(bandit)
    return Bridge.Result("Operate", {})
end

function NPCProgramThiefBridge.Escape(bandit)
    local tasks = {}
    local task = Bridge.EscapeTaskAwayFromClosestPlayer(bandit, {walkType = "Run", endurance = -0.03, closeDistance = 12})
    if task then table.insert(tasks, task) end
    return Bridge.Result("Escape", tasks)
end
