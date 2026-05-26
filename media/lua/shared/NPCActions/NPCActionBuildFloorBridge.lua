NPCActionBuildFloorBridge = NPCActionBuildFloorBridge or {}

local function faceTask(zombie, task)
    if zombie and task and task.x and task.y then
        zombie:faceLocation(task.x, task.y)
    end
end

local function playWorkSound(zombie, task)
    if not zombie or not task or not task.sound then return end
    local emitter = zombie.getEmitter and zombie:getEmitter() or nil
    if not emitter or not emitter:isPlaying(task.sound) then
        zombie:playSound(task.sound)
    end
end

local function getTargetSquare(task)
    if not task or not task.x or not task.y then return nil end
    local cell = getCell()
    if not cell then return nil end
    return cell:getGridSquare(task.x, task.y, task.z or 0)
end

local function isWaterObject(object)
    if not object or not object.getProperties then return false end
    local properties = object:getProperties()
    return properties and properties:Is(IsoFlagType.water)
end

local function addFloor(square)
    if not square then return nil end
    local floor = IsoObject.new(square, "carpentry_02_56", "")
    square:AddSpecialObject(floor)
    if floor and floor.transmitCompleteItemToServer then
        floor:transmitCompleteItemToServer()
    end
    return floor
end

local function removeWaterObject(square, object)
    if not square or not object then return end
    if isClient and isClient() and sledgeDestroy then
        sledgeDestroy(object)
    elseif square.transmitRemoveItemFromSquare then
        square:transmitRemoveItemFromSquare(object)
    end
end

function NPCActionBuildFloorBridge.OnStart(zombie, task)
    return true
end

function NPCActionBuildFloorBridge.OnWorking(zombie, task)
    if not zombie or not task then return true end
    faceTask(zombie, task)
    if task.time and task.time <= 0 then return true end
    if zombie:getVariableString("BumpAnimFinished") then
        zombie:setVariable("BumpAnimFinished", false)
        if task.anim then zombie:setBumpType(task.anim) end
        playWorkSound(zombie, task)
    end
    return false
end

function NPCActionBuildFloorBridge.OnComplete(zombie, task)
    local square = getTargetSquare(task)
    local objects = square and square:getObjects() or nil
    if not objects then return true end

    for i=0, objects:size() - 1 do
        local object = objects:get(i)
        if isWaterObject(object) then
            addFloor(square)
            removeWaterObject(square, object)
            return true
        end
    end
    return true
end
