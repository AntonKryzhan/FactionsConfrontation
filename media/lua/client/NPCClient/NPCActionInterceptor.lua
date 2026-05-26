NPCActionInterceptor = NPCActionInterceptor or {}

local EVENT_NAME = "OnTimedActionPerform"

local function safeActionType(data)
    if not data or not data.action or not data.action.getMetaType then
        return nil
    end
    local ok, actionType = pcall(function()
        return data.action:getMetaType()
    end)
    if ok then
        return actionType
    end
    return nil
end

local function getDestContainer(data)
    if not data then return nil end
    return data.destContainer or data.container or data.itemContainer
end

local function isFoodStorageContainer(container)
    if not container or not container.getType then
        return false
    end
    local ok, containerType = pcall(function()
        return container:getType()
    end)
    if not ok or not containerType then
        return false
    end
    return containerType == "fridge" or containerType == "freezer"
end

local function getContainerBuildingDef(container)
    if not container or not container.getParent then
        return nil
    end

    local parent = container:getParent()
    if not parent or not parent.getSquare then
        return nil
    end

    local square = parent:getSquare()
    if not square or not square.getBuilding then
        return nil
    end

    local building = square:getBuilding()
    if not building or not building.getDef then
        return nil
    end

    return building:getDef()
end

local function makeBaseUpdateArgs(buildingDef)
    if not buildingDef then return nil end
    if not buildingDef.getX or not buildingDef.getY or not buildingDef.getX2 or not buildingDef.getY2 then
        return nil
    end

    return {
        x = buildingDef:getX(),
        y = buildingDef:getY(),
        x2 = buildingDef:getX2(),
        y2 = buildingDef:getY2()
    }
end

function NPCActionInterceptor.TryRegisterPlayerBase(character, data)
    if not character or not data then
        return false
    end

    local actionType = safeActionType(data)
    if actionType ~= "ISInventoryTransferAction" then
        return false
    end

    local container = getDestContainer(data)
    if not isFoodStorageContainer(container) then
        return false
    end

    local buildingDef = getContainerBuildingDef(container)
    local args = makeBaseUpdateArgs(buildingDef)
    if not args then
        return false
    end

    if sendClientCommand then
        sendClientCommand(character, "NPCCommands", "BaseUpdate", args)
        return true
    end

    return false
end

function NPCActionInterceptor.Main(data)
    if not data then return end

    local character = data.character
    if not character then return end

    NPCActionInterceptor.TryRegisterPlayerBase(character, data)
end

function NPCActionInterceptor.Install()
    if NPCActionInterceptor._installed then
        return
    end
    NPCActionInterceptor._installed = true

    if LuaEventManager and LuaEventManager.AddEvent then
        LuaEventManager.AddEvent(EVENT_NAME)
    end
    if Events and Events.OnTimedActionPerform and Events.OnTimedActionPerform.Add then
        Events.OnTimedActionPerform.Add(NPCActionInterceptor.Main)
    end
end

return NPCActionInterceptor
