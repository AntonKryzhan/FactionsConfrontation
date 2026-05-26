NPCActionSingleBridge = NPCActionSingleBridge or {}

local function isAnimActive(zombie, task)
    if not zombie or not task or not task.anim then return false end
    local ok, bump = pcall(function() return zombie:getBumpType() end)
    return ok and bump == task.anim
end

function NPCActionSingleBridge.OnStart(zombie, task)
    return true
end

function NPCActionSingleBridge.OnWorking(zombie, task)
    if isAnimActive(zombie, task) then return false end
    return true
end

function NPCActionSingleBridge.OnComplete(zombie, task)
    return true
end
