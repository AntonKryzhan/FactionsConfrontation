NPCActionFaceLocationBridge = NPCActionFaceLocationBridge or {}

local function getTarget(task)
    if not task then return nil, nil end
    local x = tonumber(task.fx) or tonumber(task.x)
    local y = tonumber(task.fy) or tonumber(task.y)
    if not x or not y then return nil, nil end
    return x, y
end

local function turnActor(actor, x, y)
    if not actor or not x or not y then return false end
    if actor.faceLocationF then
        actor:faceLocationF(x, y)
    elseif actor.faceLocation then
        actor:faceLocation(x, y)
    else
        return false
    end
    return true
end

local function isDone(task)
    if not task then return true end
    local time = tonumber(task.time)
    return time ~= nil and time <= 0
end

function NPCActionFaceLocationBridge.OnStart(zombie, task)
    local x, y = getTarget(task)
    turnActor(zombie, x, y)
    return true
end

function NPCActionFaceLocationBridge.OnWorking(zombie, task)
    local x, y = getTarget(task)
    turnActor(zombie, x, y)
    return isDone(task)
end

function NPCActionFaceLocationBridge.OnComplete(zombie, task)
    return true
end
