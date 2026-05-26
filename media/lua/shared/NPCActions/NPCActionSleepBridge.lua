NPCActionSleepBridge = NPCActionSleepBridge or {}

local sleepFacing = {
    S = {dx=0.5, dy=0.5, fx=-20, fy=0},
    N = {dx=0.5, dy=0.5, fx=20, fy=0},
    E = {dx=0.5, dy=0.5, fx=0, fy=20},
    W = {dx=0.5, dy=0.5, fx=0, fy=-20}
}

local function setSleepAnim(zombie, task)
    if zombie and task and task.anim and zombie.setBumpType then
        pcall(function() zombie:setBumpType(task.anim) end)
    end
end

local function pinToRestSpot(zombie, task)
    if not zombie or not task then return end
    local x = tonumber(task.x)
    local y = tonumber(task.y)
    local z = tonumber(task.z)
    local setup = task.facing and sleepFacing[tostring(task.facing)] or nil
    if not x or not y or not z or not setup then return end

    if zombie.setX then pcall(function() zombie:setX(x + setup.dx) end) end
    if zombie.setY then pcall(function() zombie:setY(y + setup.dy) end) end
    if zombie.setZ then pcall(function() zombie:setZ(z) end) end

    if zombie.faceLocationF then
        pcall(function() zombie:faceLocationF(x + setup.fx, y + setup.fy) end)
    elseif zombie.faceLocation then
        pcall(function() zombie:faceLocation(x + setup.fx, y + setup.fy) end)
    end
end

function NPCActionSleepBridge.OnStart(zombie, task)
    setSleepAnim(zombie, task)
    pinToRestSpot(zombie, task)
    return true
end

function NPCActionSleepBridge.OnWorking(zombie, task)
    setSleepAnim(zombie, task)
    pinToRestSpot(zombie, task)
    return false
end

function NPCActionSleepBridge.OnComplete(zombie, task)
    return true
end
