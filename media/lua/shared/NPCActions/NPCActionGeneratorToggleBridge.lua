NPCActionGeneratorToggleBridge = NPCActionGeneratorToggleBridge or {}

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

function NPCActionGeneratorToggleBridge.OnStart(zombie, task)
    return true
end

function NPCActionGeneratorToggleBridge.OnWorking(zombie, task)
    if not zombie or not task then return true end
    faceTask(zombie, task)
    if task.time and task.time <= 0 then return true end
    if task.anim and zombie:getBumpType() ~= task.anim then
        zombie:setBumpType(task.anim)
    end
    return false
end

function NPCActionGeneratorToggleBridge.OnComplete(zombie, task)
    local square = getTaskSquare(zombie, task)
    local generator = square and square:getGenerator() or nil
    if generator and generator.setActivated then
        generator:setActivated(task and task.status == true)
    end
    return true
end
