NPCActionOpenWindowBridge = NPCActionOpenWindowBridge or {}

local function faceActionTarget(zombie, task)
    if not zombie or not task or not task.x or not task.y then return end
    if type(zombie.faceLocationF) ~= "function" then return end

    pcall(function()
        zombie:faceLocationF(task.x, task.y)
    end)
end

local function getCurrentBump(zombie)
    if not zombie or type(zombie.getBumpType) ~= "function" then return nil end

    local ok, bump = pcall(function()
        return zombie:getBumpType()
    end)
    if ok then return bump end
    return nil
end

local function shouldWaitForAnimation(zombie, task)
    if not task or not task.anim then return false end
    return getCurrentBump(zombie) == task.anim
end

local function getCellFor(zombie)
    if not zombie or type(zombie.getCell) ~= "function" then return nil end

    local ok, cell = pcall(function()
        return zombie:getCell()
    end)
    if ok then return cell end
    return nil
end

local function getActionSquare(zombie, task)
    if not task or not task.x or not task.y or task.z == nil then return nil end

    local cell = getCellFor(zombie)
    if not cell or type(cell.getGridSquare) ~= "function" then return nil end

    local ok, square = pcall(function()
        return cell:getGridSquare(task.x, task.y, task.z)
    end)
    if ok then return square end
    return nil
end

local function isIsoWindow(object)
    if not object or not instanceof then return false end

    local ok, result = pcall(function()
        return instanceof(object, "IsoWindow")
    end)
    return ok and result == true
end

local function findWindowOnSquare(square)
    if not square then return nil end

    if type(square.getWindow) == "function" then
        local ok, window = pcall(function()
            return square:getWindow()
        end)
        if ok and window then return window end
    end

    if type(square.getObjects) ~= "function" then return nil end
    local objectsOk, objects = pcall(function()
        return square:getObjects()
    end)
    if not objectsOk or not objects then return nil end

    for objectIndex = 0, objects:size() - 1 do
        local object = objects:get(objectIndex)
        if isIsoWindow(object) then return object end
    end

    return nil
end

local function isWindowOpen(window)
    if not window or type(window.IsOpen) ~= "function" then return false end
    local ok, open = pcall(function() return window:IsOpen() == true end)
    return ok and open == true
end

local function isWindowBlocked(window)
    if not window then return true end
    if type(window.isBarricaded) == "function" then
        local ok, barricaded = pcall(function() return window:isBarricaded() == true end)
        if ok and barricaded == true then return true end
    end
    if type(window.isSmashed) == "function" then
        local ok, smashed = pcall(function() return window:isSmashed() == true end)
        if ok and smashed == true then return true end
    end
    return false
end

local function toggleWindow(window, zombie)
    if not window or type(window.ToggleWindow) ~= "function" then return end

    pcall(function() if window.setLocked then window:setLocked(false) end end)
    pcall(function() if window.setPermaLocked then window:setPermaLocked(false) end end)
    pcall(function() if window.setLockedByKey then window:setLockedByKey(false) end end)
    pcall(function()
        window:ToggleWindow(zombie)
    end)
end

local function playOpenSound(zombie)
    if not zombie or type(zombie.playSound) ~= "function" then return end

    pcall(function()
        zombie:playSound("OpenWindow")
    end)
end

function NPCActionOpenWindowBridge.OnStart(zombie, task)
    return true
end

function NPCActionOpenWindowBridge.OnWorking(zombie, task)
    faceActionTarget(zombie, task)
    if shouldWaitForAnimation(zombie, task) then return false end
    return true
end

function NPCActionOpenWindowBridge.OnComplete(zombie, task)
    local square = getActionSquare(zombie, task)
    local window = findWindowOnSquare(square)
    if window and not isWindowBlocked(window) and not isWindowOpen(window) then
        toggleWindow(window, zombie)
        playOpenSound(zombie)
    end
    return true
end
