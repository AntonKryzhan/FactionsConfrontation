NPCActionTimeBridge = NPCActionTimeBridge or {}

local function getBumpTypeSafe(zombie)
    if not zombie or type(zombie.getBumpType) ~= "function" then return nil end
    local ok, bump = pcall(function() return zombie:getBumpType() end)
    if ok then return bump end
    return nil
end

local function shouldComplete(zombie, task)
    if not task or not task.anim then return true end

    local bump = getBumpTypeSafe(zombie)
    if bump == nil then return true end

    return bump ~= task.anim
end

function NPCActionTimeBridge.OnStart(zombie, task)
    return true
end

function NPCActionTimeBridge.OnWorking(zombie, task)
    return shouldComplete(zombie, task)
end

function NPCActionTimeBridge.OnComplete(zombie, task)
    return true
end
