require "NPCBehavior/NPCBehaviorBridge"

NPCProgramLooterBridge = NPCProgramLooterBridge or {}

local Bridge = NPCBehaviorBridge

function NPCProgramLooterBridge.GetCapabilities()
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

function NPCProgramLooterBridge.Prepare(bandit)
    return Bridge.PrepareArmed(bandit, {stationary = false, next = "Operate"})
end

function NPCProgramLooterBridge.Operate(bandit)
    local tasks = {}

    local hands = Bridge.GetPrimaryHands(bandit)
    local defaultWalkType = "Run"
    if hands == "rifle" or hands == "handgun" then
        defaultWalkType = "WalkAim"
    end

    local profile = Bridge.WalkProfile(bandit, {
        defaultWalkType = defaultWalkType,
        defaultEndurance = 0,
        nightSneakWalkType = "SneakWalk",
        nightSneakEndurance = 0,
        limpWalkType = "Limp",
        limpEndurance = 0
    })

    local target = Bridge.SelectCombatTarget(bandit, {includeInvisible = true, playerHandicap = 6})
    if target and target.x and target.y and target.z then
        Bridge.SpeakTargetContext(bandit, target)

        local minDist = 2
        if Bridge.IsOutOfAmmo(bandit) then
            minDist = 0.5
        end

        if (target.dist or 9999) > minDist then
            local moveTask = Bridge.MakeApproachTargetTask(
                bandit,
                target,
                profile.walkType,
                profile.endurance,
                Bridge.ShouldCloseSlow(target.enemy)
            )
            if moveTask then table.insert(tasks, moveTask) end
        end
    else
        if not Bridge.TryLivingWorldTask or not Bridge.TryLivingWorldTask(bandit, tasks, profile, {program = "Looter", allowLoot = true, fallbackAnim = "LootLow"}) then
            table.insert(tasks, {action = "Time", anim = "Shrug", time = 200})
        end
    end

    return Bridge.Result("Operate", tasks)
end

function NPCProgramLooterBridge.Wait(bandit)
    return Bridge.Result("Operate", {})
end
