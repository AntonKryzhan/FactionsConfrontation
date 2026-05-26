NPCActionWashBridge = NPCActionWashBridge or {}

local function faceWashTarget(actor, task)
    if not actor or not task or task.x == nil or task.y == nil then return end
    actor:faceLocation(task.x, task.y)
end

local function stopActorSounds(actor)
    if not actor or not actor.getEmitter then return end
    local emitter = actor:getEmitter()
    if emitter then
        emitter:stopAll()
    end
end

local function resetVisualDirtAndBlood(visual)
    if not visual or not BloodBodyPartType then return end
    for i = 1, BloodBodyPartType.MAX:index() do
        local bodyPart = BloodBodyPartType.FromIndex(i - 1)
        if bodyPart then
            visual:setBlood(bodyPart, 0)
            visual:setDirt(bodyPart, 0)
        end
    end
end

local function getActorVisual(actor)
    if not actor or not actor.getHumanVisual then return nil end
    return actor:getHumanVisual()
end

function NPCActionWashBridge.OnStart(zombie, task)
    if zombie and zombie.playSound then
        zombie:playSound("WashYourself")
    end
    return true
end

function NPCActionWashBridge.OnWorking(zombie, task)
    if not zombie or not task then return true end

    faceWashTarget(zombie, task)

    if task.time and task.time <= 0 then return true end

    if task.anim and zombie.getBumpType and zombie.setBumpType and zombie:getBumpType() ~= task.anim then
        zombie:setBumpType(task.anim)
    end

    return false
end

function NPCActionWashBridge.OnComplete(zombie, task)
    stopActorSounds(zombie)
    resetVisualDirtAndBlood(getActorVisual(zombie))

    if zombie and zombie.resetModelNextFrame then
        zombie:resetModelNextFrame()
    end

    return true
end
