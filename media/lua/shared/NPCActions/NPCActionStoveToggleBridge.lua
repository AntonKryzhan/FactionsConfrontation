NPCActionStoveToggleBridge = NPCActionStoveToggleBridge or {}

local function faceTask(zombie, task)
    if not zombie or not task or not task.x or not task.y then return end
    pcall(function() zombie:faceLocationF(task.x, task.y) end)
end

local function isAnimActive(zombie, task)
    if not zombie or not task or not task.anim then return false end
    local ok, bump = pcall(function() return zombie:getBumpType() end)
    return ok and bump == task.anim
end

local function getTaskSquare(zombie, task)
    if not zombie or not task or not task.x or not task.y or task.z == nil then return nil end
    local ok, square = pcall(function()
        local cell = zombie:getCell()
        return cell and cell:getGridSquare(task.x, task.y, task.z)
    end)
    if ok then return square end
    return nil
end

local function isStove(object)
    if not object or not instanceof then return false end
    local ok, result = pcall(function() return instanceof(object, "IsoStove") end)
    return ok and result
end

function NPCActionStoveToggleBridge.OnStart(zombie, task)
    return true
end

function NPCActionStoveToggleBridge.OnWorking(zombie, task)
    faceTask(zombie, task)
    if isAnimActive(zombie, task) then return false end
    return true
end

function NPCActionStoveToggleBridge.OnComplete(zombie, task)
    local square = getTaskSquare(zombie, task)
    if not square then return true end

    local ok, objects = pcall(function() return square:getObjects() end)
    if not ok or not objects then return true end

    for i=0, objects:size()-1 do
        local object = objects:get(i)
        if isStove(object) then
            pcall(function() object:Toggle() end)
            break
        end
    end

    return true
end
