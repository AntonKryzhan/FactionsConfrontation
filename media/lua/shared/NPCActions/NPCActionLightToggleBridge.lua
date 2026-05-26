NPCActionLightToggleBridge = NPCActionLightToggleBridge or {}

local function faceTask(zombie, task)
    if zombie and task and task.x and task.y then
        zombie:faceLocation(task.x, task.y)
    end
end

local function getTaskSquare(zombie, task)
    if not task or not task.x or not task.y then return nil end
    local cell = zombie and zombie.getCell and zombie:getCell() or getCell()
    if not cell then return nil end
    return cell:getGridSquare(task.x, task.y, task.z or 0)
end

local function isLightSwitch(object)
    return object and instanceof(object, "IsoLightSwitch")
end

function NPCActionLightToggleBridge.OnStart(zombie, task)
    return true
end

function NPCActionLightToggleBridge.OnWorking(zombie, task)
    if not zombie or not task then return true end
    faceTask(zombie, task)
    if task.time and task.time <= 0 then return true end
    if task.anim and zombie:getBumpType() ~= task.anim then
        zombie:setBumpType(task.anim)
    end
    return false
end

function NPCActionLightToggleBridge.OnComplete(zombie, task)
    local square = getTaskSquare(zombie, task)
    local objects = square and square:getObjects() or nil
    if not objects then return true end

    for i=0, objects:size() - 1 do
        local object = objects:get(i)
        if isLightSwitch(object) and object.setActive then
            object:setActive(task and task.active == true)
        end
    end
    return true
end
