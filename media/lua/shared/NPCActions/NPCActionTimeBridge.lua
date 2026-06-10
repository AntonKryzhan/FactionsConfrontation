NPCActionTimeBridge = NPCActionTimeBridge or {}

local function actionTimeNowMs()
    if getTimestampMs then
        local ok, value = pcall(function() return getTimestampMs() end)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return 0
end

local function isPlayerCommandTimeTask(task)
    return task and (task.playerOrder == true or task.manualOrder == true or task.strictFollowSettled == true or task.playerLootOrder == true or task.playerCommand == true or task.mercenaryAmbientIdle == true)
end

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
    if isPlayerCommandTimeTask(task) then
        task._playerCommandTimeStartMs = actionTimeNowMs()
        task._playerCommandTimeLimitMs = math.max(250, math.min(2200, (tonumber(task.time) or 90) * 16))
        if NPCEntity and NPCEntity.SetMoving then pcall(function() NPCEntity.SetMoving(zombie, false) end) end
        if zombie and zombie.setBumpType and task.anim then pcall(function() zombie:setBumpType(task.anim) end) end
    end
    return true
end

function NPCActionTimeBridge.OnWorking(zombie, task)
    if isPlayerCommandTimeTask(task) then
        if task.time and task.time <= 0 then return true end
        local now = actionTimeNowMs()
        local started = tonumber(task._playerCommandTimeStartMs) or now
        local limit = tonumber(task._playerCommandTimeLimitMs) or 1200
        if now > 0 and started > 0 and now - started >= limit then return true end
    end
    return shouldComplete(zombie, task)
end

function NPCActionTimeBridge.OnComplete(zombie, task)
    if isPlayerCommandTimeTask(task) and zombie then
        if zombie.setBumpType then
            local bump = getBumpTypeSafe(zombie)
            if bump == task.anim then pcall(function() zombie:setBumpType("Idle") end) end
        end
        if zombie.setBumpDone then pcall(function() zombie:setBumpDone(true) end) end
        if zombie.setVariable then
            pcall(function() zombie:setVariable("bCrouch", false) end)
            pcall(function() zombie:setVariable("bCrouching", false) end)
            pcall(function() zombie:setVariable("Crouch", false) end)
            pcall(function() zombie:setVariable("IsCrouching", false) end)
            pcall(function() zombie:setVariable("bSneak", false) end)
            pcall(function() zombie:setVariable("bMoving", false) end)
            pcall(function() zombie:setVariable("bPathfind", false) end)
            pcall(function() zombie:setVariable("BumpAnimFinished", true) end)
        end
        if zombie.setSneaking then pcall(function() zombie:setSneaking(false) end) end
    end
    return true
end
