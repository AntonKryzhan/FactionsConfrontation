NPCWorldObjectCommandBridge = NPCWorldObjectCommandBridge or {}

local Bridge = NPCWorldObjectCommandBridge

local function safeCall(fn)
    if not fn then return nil end
    local ok, result = pcall(fn)
    if ok then return result end
    return nil
end

local function isInstance(object, className)
    if not object or not className or not instanceof then return false end
    local ok, result = pcall(function() return instanceof(object, className) end)
    return ok and result == true
end

function Bridge.GetSquare(x, y, z)
    local cell = getCell and getCell() or nil
    if not cell then return nil end
    x = tonumber(x)
    y = tonumber(y)
    z = tonumber(z) or 0
    if not x or not y then return nil end
    return cell:getGridSquare(x, y, z)
end

function Bridge.RecalcArea(square, radius)
    if not square then return false end
    radius = tonumber(radius) or 5
    if radius < 0 then radius = 0 end
    if radius > 12 then radius = 12 end

    local cell = getCell and getCell() or nil
    if not cell then return false end

    local sx = square:getX()
    local sy = square:getY()
    local sz = square:getZ()
    for dx = -radius, radius do
        for dy = -radius, radius do
            local surroundingSquare = cell:getGridSquare(sx + dx, sy + dy, sz)
            if surroundingSquare then
                pcall(function() surroundingSquare:InvalidateSpecialObjectPaths() end)
                pcall(function() surroundingSquare:RecalcProperties() end)
                pcall(function() surroundingSquare:RecalcAllWithNeighbours(true) end)
            end
        end
    end
    return true
end

function Bridge.IsDoorObject(object)
    if not object then return false end
    if isInstance(object, "IsoDoor") then return true end
    if isInstance(object, "IsoThumpable") then
        local isDoor = safeCall(function() return object:isDoor() == true end)
        if isDoor == true then return true end
    end
    return false
end

function Bridge.GetDestroyableObject(square, index)
    if not square then return nil end

    index = tonumber(index)
    local objects = square:getObjects()
    if objects and index and index >= 0 and index < objects:size() then
        local object = objects:get(index)
        if object and (Bridge.IsDoorObject(object) or isInstance(object, "IsoThumpable")) then
            return object
        end
    end

    local door = safeCall(function() return square:getIsoDoor() end)
    if door then return door end

    local specialObjects = safeCall(function() return square:getSpecialObjects() end)
    if specialObjects then
        for i = 0, specialObjects:size() - 1 do
            local object = specialObjects:get(i)
            if isInstance(object, "IsoThumpable") then
                return object
            end
        end
    end

    return nil
end

function Bridge.DoorLockedLikePlayer(object)
    if not Bridge.IsDoorObject(object) then return true end
    if Bridge.DoorIsBarricaded(object) then return true end
    return false
end

function Bridge.DoorIsOpen(object)
    if not Bridge.IsDoorObject(object) then return false end
    local open = safeCall(function() return object:IsOpen() == true end)
    return open == true
end

function Bridge.DoorIsBarricaded(object)
    if not Bridge.IsDoorObject(object) then return true end

    local fn = object.isBarricaded
    if fn then
        local barricaded = safeCall(function() return fn(object) == true end)
        if barricaded ~= nil then return barricaded == true end
    end

    return false
end

function Bridge.CanOpenDoorLikePlayer(object)
    if not Bridge.IsDoorObject(object) then return false end
    if Bridge.DoorIsOpen(object) then return true end
    if Bridge.DoorIsBarricaded(object) then return false end
    return true
end

function Bridge.FindDoorOnSquare(square, preferredIndex)
    if not square then return nil end

    local objects = square:getObjects()
    if not objects then return nil end

    local index = tonumber(preferredIndex)
    if index and index >= 0 and index < objects:size() then
        local object = objects:get(index)
        if Bridge.IsDoorObject(object) then return object end
    end

    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if Bridge.IsDoorObject(object) then return object end
    end

    return nil
end

function Bridge.SyncObjectState(object)
    if not object then return false end
    pcall(function() object:sendObjectChange('state') end)
    pcall(function() object:transmitCompleteItemToClients() end)
    pcall(function() object:syncIsoObject(false, 0, nil, nil) end)
    return true
end

function Bridge.DamageDestroyableObject(square, object, player, damage)
    if not square or not object then return false end

    local health = safeCall(function() return object:getHealth() end)
    if not health then return false end

    damage = tonumber(damage) or 40
    if damage < 0 then damage = 0 end

    health = health - damage
    if health < 0 then health = 0 end

    if health == 0 then
        pcall(function() object:destroy() end)
    else
        pcall(function() object:setHealth(health) end)
        if player then pcall(function() object:Thump(player) end) end
    end

    Bridge.SyncObjectState(object)
    Bridge.RecalcArea(square, 5)
    return true
end

function Bridge.OpenDoorObject(square, object)
    if not square or not Bridge.IsDoorObject(object) then return false end
    if Bridge.DoorIsOpen(object) then return false end
    if not Bridge.CanOpenDoorLikePlayer(object) then return false end

    pcall(function() if object.setLocked then object:setLocked(false) end end)
    pcall(function() if object.setLockedByKey then object:setLockedByKey(false) end end)
    pcall(function() if object.setPermaLocked then object:setPermaLocked(false) end end)
    pcall(function() if object.setLockedByPadlock then object:setLockedByPadlock(false) end end)

    local openedSpecial = false
    if isInstance(object, "IsoDoor") and IsoDoor then
        local doubleIndex = safeCall(function()
            if IsoDoor.getDoubleDoorIndex then return IsoDoor.getDoubleDoorIndex(object) end
            return -1
        end)
        if doubleIndex and doubleIndex > -1 and IsoDoor.toggleDoubleDoor then
            pcall(function() IsoDoor.toggleDoubleDoor(object, true) end)
            openedSpecial = true
        else
            local garageIndex = safeCall(function()
                if IsoDoor.getGarageDoorIndex then return IsoDoor.getGarageDoorIndex(object) end
                return -1
            end)
            if garageIndex and garageIndex > -1 and IsoDoor.toggleGarageDoor then
                pcall(function() IsoDoor.toggleGarageDoor(object, true) end)
                openedSpecial = true
            end
        end
    end

    if not openedSpecial then
        pcall(function() object:ToggleDoorSilent() end)
    end

    Bridge.SyncObjectState(object)
    Bridge.RecalcArea(square, 5)
    return true
end

function Bridge.CloseDoorObject(square, object)
    if not square or not Bridge.IsDoorObject(object) then return false end
    if not Bridge.DoorIsOpen(object) then return false end

    pcall(function() object:ToggleDoorSilent() end)
    Bridge.SyncObjectState(object)
    Bridge.RecalcArea(square, 5)
    return true
end

function Bridge.SetDoorLockedByKey(square, object, locked)
    if not square or not Bridge.IsDoorObject(object) then return false end

    local fn = object.isLockedByKey
    local current = false
    if fn then
        local value = safeCall(function() return fn(object) == true end)
        current = value == true
    end

    locked = locked == true
    if current ~= locked and object.setLockedByKey then
        pcall(function() object:setLockedByKey(locked) end)
        Bridge.SyncObjectState(object)
        Bridge.RecalcArea(square, 5)
        return true
    end

    return false
end

return NPCWorldObjectCommandBridge
