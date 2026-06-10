NPCBaseClient = NPCBaseClient or {}
NPCBaseClient.const = NPCBaseClient.const or {}
NPCBaseClient.const.padding = NPCBaseClient.const.padding or 20
NPCBaseClient.data = NPCBaseClient.data or {}

local Base = NPCBaseClient

local function alwaysTrue(_item)
    return true
end

local function asNumber(value, fallback)
    if type(value) == "number" then
        return value
    end
    return fallback
end

local function keyFor(x, y, z)
    return tostring(x) .. "-" .. tostring(y) .. "-" .. tostring(z)
end

local function ensureTable(parent, name)
    if type(parent[name]) ~= "table" then
        parent[name] = {}
    end
    return parent[name]
end

local function cellFor(character)
    if character and character.getCell then
        return character:getCell()
    end
    if getCell then
        return getCell()
    end
end

local function distTo(ax, ay, bx, by)
    if NPCUtils and NPCUtils.DistTo then
        return NPCUtils.DistTo(ax, ay, bx, by)
    end
    local dx = ax - bx
    local dy = ay - by
    return math.sqrt((dx * dx) + (dy * dy))
end

local function safeCount(list)
    if list and list.size then
        return list:size()
    end
    return 0
end

local function safeGet(list, index)
    if list and list.get then
        return list:get(index)
    end
end

local function farmingSystem()
    if CFarmingSystem and CFarmingSystem.instance then
        return CFarmingSystem.instance
    end
end

local function getPlantAt(x, y, z)
    local system = farmingSystem()
    if system and system.getLuaObjectAt then
        return system:getLuaObjectAt(x, y, z)
    end
end

local function safeWaterAmount(object)
    if not object or not object.getWaterAmount then
        return 0
    end
    local ok, amount = pcall(function()
        return object:getWaterAmount()
    end)
    if ok and type(amount) == "number" then
        return amount
    end
    return 0
end

local function nearestBaseIdAt(x, y)
    for baseId, base in pairs(Base.data) do
        if base and x >= base.x and x <= base.x2 and y >= base.y and y <= base.y2 then
            return baseId
        end
    end
end

local function baseForCharacter(character)
    if not character or not character.getX or not character.getY then
        return nil
    end
    local baseId = nearestBaseIdAt(character:getX(), character:getY())
    if baseId then
        return baseId, Base.data[baseId]
    end
end

local function resolveSquare(character, x, y, z)
    local cell = cellFor(character)
    if cell and cell.getGridSquare then
        return cell:getGridSquare(x, y, z)
    end
end

local function addObject(base, x, y, z, objectType)
    if not base or not objectType then
        return
    end
    local bucket = ensureTable(base, objectType)
    local id = keyFor(x, y, z)
    bucket[id] = { id = id, x = x, y = y, z = z }
end

local function removeObject(base, x, y, z, objectType)
    if not base or not objectType or not base[objectType] then
        return
    end
    base[objectType][keyFor(x, y, z)] = nil
end

local function addItems(base, x, y, z, containerType, itemCounts)
    if not base or not itemCounts then
        return
    end
    local id = keyFor(x, y, z)
    local containers = ensureTable(base, "containers")
    local itemIndex = ensureTable(base, "items")

    containers[id] = {
        id = id,
        x = x,
        y = y,
        z = z,
        type = containerType or "unknown",
        items = itemCounts,
    }

    for itemType, count in pairs(itemCounts) do
        if type(itemType) == "string" and type(count) == "number" and count > 0 then
            itemIndex[itemType] = itemIndex[itemType] or {}
            itemIndex[itemType][id] = {
                x = x,
                y = y,
                z = z,
                type = containerType or "unknown",
                cnt = count,
            }
        end
    end
end

local function removeItems(base, x, y, z)
    if not base then
        return
    end
    local id = keyFor(x, y, z)
    if type(base.containers) == "table" then
        base.containers[id] = nil
    end
    if type(base.items) == "table" then
        local emptyItemTypes
        for itemType, locations in pairs(base.items) do
            if type(locations) == "table" then
                locations[id] = nil
                if not next(locations) then
                    emptyItemTypes = emptyItemTypes or {}
                    emptyItemTypes[#emptyItemTypes + 1] = itemType
                end
            end
        end
        if emptyItemTypes then
            for index = 1, #emptyItemTypes do
                base.items[emptyItemTypes[index]] = nil
            end
        end
    end
end

local function countWorldItems(square)
    local counts = {}
    local worldObjects = square and square.getWorldObjects and square:getWorldObjects()
    for index = 0, safeCount(worldObjects) - 1 do
        local worldObject = safeGet(worldObjects, index)
        local item = worldObject and worldObject.getItem and worldObject:getItem()
        local itemType = item and item.getFullType and item:getFullType()
        if itemType then
            counts[itemType] = (counts[itemType] or 0) + 1
        end
    end
    return counts, safeCount(worldObjects)
end

local function countContainerItems(container)
    local counts = {}
    if not container then
        return counts
    end

    local array = ArrayList and ArrayList.new and ArrayList.new()
    if array and container.getAllEvalRecurse then
        container:getAllEvalRecurse(alwaysTrue, array)
        for index = 0, safeCount(array) - 1 do
            local item = safeGet(array, index)
            local itemType = item and item.getFullType and item:getFullType()
            if itemType then
                counts[itemType] = (counts[itemType] or 0) + 1
            end
        end
        return counts
    end

    local items = container.getItems and container:getItems()
    for index = 0, safeCount(items) - 1 do
        local item = safeGet(items, index)
        local itemType = item and item.getFullType and item:getFullType()
        if itemType then
            counts[itemType] = (counts[itemType] or 0) + 1
        end
    end
    return counts
end

local function hasEntries(tbl)
    if type(tbl) ~= "table" then
        return false
    end

    for _ in pairs(tbl) do
        return true
    end

    return false
end

local function scanSquareItems(base, square)
    local x = square:getX()
    local y = square:getY()
    local z = square:getZ()

    if square.haveBlood and square:haveBlood() then
        addObject(base, x, y, z, "blood")
    else
        removeObject(base, x, y, z, "blood")
    end

    local items, worldObjectCount = countWorldItems(square)
    if worldObjectCount > 0 and hasEntries(items) then
        addItems(base, x, y, z, "floor", items)
    else
        removeItems(base, x, y, z)
    end
end

local function scanLuaObjects(base, square)
    local x = square:getX()
    local y = square:getY()
    local z = square:getZ()

    if getPlantAt(x, y, z) then
        addObject(base, x, y, z, "farms")
    else
        removeObject(base, x, y, z, "farms")
    end
end

local function scanStaticObjects(base, square)
    local x = square:getX()
    local y = square:getY()
    local z = square:getZ()
    local movingObjects = square.getStaticMovingObjects and square:getStaticMovingObjects()

    for index = 0, safeCount(movingObjects) - 1 do
        local object = safeGet(movingObjects, index)
        if object and instanceof and instanceof(object, "IsoDeadBody") then
            addObject(base, x, y, z, "deadbodies")
        end
    end
end

local function scanObject(base, square, object)
    if not object then
        return
    end

    local x = square:getX()
    local y = square:getY()
    local z = square:getZ()

    if instanceof and instanceof(object, "IsoGenerator") then
        addObject(base, x, y, z, "generators")
        return
    end

    local modData = object.getModData and object:getModData() or {}
    if object.getName and object:getName() == "EmptyGraves" and modData.filled == false then
        addObject(base, x, y, z, "graves")
        return
    end

    if safeWaterAmount(object) > 10 then
        addObject(base, x, y, z, "waterSources")
        return
    end

    local sprite = object.getSprite and object:getSprite()
    local spriteProps = sprite and sprite.getProperties and sprite:getProperties()
    if spriteProps and spriteProps.Is and spriteProps:Is("IsTrashCan") then
        addObject(base, x, y, z, "trashcans")
        return
    end

    local container = object.getContainer and object:getContainer()
    if container then
        local containerType = container.getType and container:getType() or "unknown"
        addItems(base, x, y, z, containerType, countContainerItems(container))
    end
end

local function scanRealObjects(base, square)
    local x = square:getX()
    local y = square:getY()
    local z = square:getZ()

    removeObject(base, x, y, z, "generators")
    removeObject(base, x, y, z, "deadbodies")
    removeObject(base, x, y, z, "graves")
    removeObject(base, x, y, z, "waterSources")
    removeObject(base, x, y, z, "trashcans")

    scanStaticObjects(base, square)

    local objects = square.getObjects and square:getObjects()
    for index = 0, safeCount(objects) - 1 do
        scanObject(base, square, safeGet(objects, index))
    end
end

local function scanSquare(base, square)
    if not base or not square then
        return
    end
    scanSquareItems(base, square)
    scanLuaObjects(base, square)
    scanRealObjects(base, square)
end

local function nearestRecord(character, records, validator)
    if not character or not records or not character.getX or not character.getY then
        return nil
    end

    local x = character:getX()
    local y = character:getY()
    local bestRecord
    local bestDistance = math.huge

    for _, record in pairs(records) do
        if record and record.x and record.y then
            local candidate = validator and validator(record) or record
            if candidate then
                local distance = distTo(record.x, record.y, x, y)
                if distance < bestDistance then
                    bestRecord = candidate
                    bestDistance = distance
                end
            end
        end
    end

    return bestRecord
end

local function squareHasContainer(square, containerType, itemType)
    local objects = square and square.getObjects and square:getObjects()
    for index = 0, safeCount(objects) - 1 do
        local object = safeGet(objects, index)
        local container = object and object.getContainerByType and object:getContainerByType(containerType)
        if container and (not itemType or container:getItemCountFromTypeRecurse(itemType) > 0) then
            return container
        end
    end
end

function Base.Debug(_buildingDef)
    return Base.data
end

function Base.GetBase(character)
    local _baseId, base = baseForCharacter(character)
    return base
end

function Base.GetBaseClosest(character)
    if not character or not character.getX or not character.getY then
        return nil
    end

    local x = character:getX()
    local y = character:getY()
    local bestBaseId
    local bestBase
    local bestDistance = 100

    for baseId, base in pairs(Base.data) do
        if base then
            local distance = distTo(base.x, base.y, x, y)
            if distance < bestDistance then
                bestBaseId = baseId
                bestBase = base
                bestDistance = distance
            end
        end
    end

    return bestBaseId, bestBase
end

function Base.GetContainerClosest(character, baseId)
    if not character or not baseId or not Base.data[baseId] then
        return nil
    end

    local x = character:getX()
    local y = character:getY()
    local bestContainerId
    local bestContainer
    local bestDistance = 100

    for containerId, container in pairs(Base.data[baseId].containers or {}) do
        if hasEntries(container.items) then
            local distance = distTo(container.x, container.y, x, y)
            if distance < bestDistance then
                bestContainerId = containerId
                bestContainer = container
                bestDistance = distance
            end
        end
    end

    return bestContainerId, bestContainer
end

function Base.RegisterBase(x, y, x2, y2)
    x = asNumber(x)
    y = asNumber(y)
    x2 = asNumber(x2)
    y2 = asNumber(y2)
    if not x or not y or not x2 or not y2 then
        return nil
    end

    if nearestBaseIdAt(x, y) then
        return nil
    end

    local padding = asNumber(Base.const.padding, 20)
    local baseId = tostring(x) .. "-" .. tostring(y)
    Base.data[baseId] = Base.data[baseId] or {
        id = baseId,
        pointer = { x = 0, y = 0, z = 0 },
        x = x - padding,
        y = y - padding,
        x2 = x2 + padding,
        y2 = y2 + padding,
        items = {},
        farms = {},
        containers = {},
        waterSources = {},
        generators = {},
        blood = {},
        trashcans = {},
        deadbodies = {},
        graves = {},
    }
    return baseId
end

function Base.Regenerate(baseId)
    local base = Base.data[baseId]
    if not base then
        return
    end

    base.pointer = base.pointer or { x = 0, y = 0, z = 0 }
    local cell = getCell and getCell()
    if not cell then
        return
    end

    local step = 10
    local xmin = base.x + base.pointer.x
    local xmax = math.min(base.x + base.pointer.x + step, base.x2)
    local ymin = base.y + base.pointer.y
    local ymax = math.min(base.y + base.pointer.y + step, base.y2)

    for z = 0, 1 do
        for x = xmin, xmax do
            for y = ymin, ymax do
                local square = cell:getGridSquare(x, y, z)
                if square then
                    scanSquare(base, square)
                end
            end
        end
    end

    if xmin > base.x2 - step then
        base.pointer.x = 0
        base.pointer.y = base.pointer.y + step
        if ymin > base.y2 - step then
            base.pointer.y = 0
        end
    else
        base.pointer.x = base.pointer.x + step
    end
end

function Base.ReindexItems(baseId)
    local base = Base.data[baseId]
    if not base then
        return
    end

    local items = {}
    for containerId, container in pairs(base.containers or {}) do
        for itemType, count in pairs(container.items or {}) do
            if type(itemType) == "string" and type(count) == "number" and count > 0 then
                items[itemType] = items[itemType] or {}
                items[itemType][containerId] = {
                    x = container.x,
                    y = container.y,
                    z = container.z,
                    type = container.type,
                    cnt = count,
                }
            end
        end
    end
    base.items = items
end

function Base.Update(numberTicks)
    if isServer and isServer() then
        return
    end

    numberTicks = asNumber(numberTicks, 0)
    if numberTicks % 10 == 0 and GetNPCModData then
        local gmd = GetNPCModData()
        for _baseId, baseData in pairs((gmd and gmd.Bases) or {}) do
            if baseData and baseData.x and baseData.y and baseData.x2 and baseData.y2 then
                Base.RegisterBase(baseData.x, baseData.y, baseData.x2, baseData.y2)
            end
        end
    end

    if numberTicks % 10 == 0 then
        for baseId, _ in pairs(Base.data) do
            Base.Regenerate(baseId)
        end
    end

    if numberTicks % 50 == 0 then
        for baseId, _ in pairs(Base.data) do
            Base.ReindexItems(baseId)
        end
    end
end

function Base.GetContainerWithItem(character, item, count)
    if not character or not item then
        return nil
    end

    local baseId, base = baseForCharacter(character)
    count = asNumber(count, 1)
    if not baseId or not base or not base.items or not base.items[item] then
        return nil
    end

    local x = character:getX()
    local y = character:getY()
    local bestLocation
    local bestDistance = math.huge

    for _containerId, location in pairs(base.items[item]) do
        if location.cnt and location.cnt >= count then
            local distance = distTo(location.x, location.y, x, y)
            if distance < bestDistance then
                bestLocation = location
                bestDistance = distance
            end
        end
    end

    if not bestLocation then
        return nil
    end

    local square = resolveSquare(character, bestLocation.x, bestLocation.y, bestLocation.z)
    if not square then
        return nil
    end

    if bestLocation.type == "floor" then
        return square
    end
    return squareHasContainer(square, bestLocation.type, item)
end

function Base.GetContainerOfType(character, containerType)
    if not character or not containerType then
        return nil
    end

    local _baseId, base = baseForCharacter(character)
    if not base then
        return nil
    end

    local x = character:getX()
    local y = character:getY()
    local bestContainer
    local bestDistance = math.huge

    for _containerId, container in pairs(base.containers or {}) do
        if container.type == containerType then
            local distance = distTo(container.x, container.y, x, y)
            if distance < bestDistance then
                bestContainer = container
                bestDistance = distance
            end
        end
    end

    if not bestContainer then
        return nil
    end

    local square = resolveSquare(character, bestContainer.x, bestContainer.y, bestContainer.z)
    if not square then
        return nil
    end

    if bestContainer.type == "floor" then
        return square
    end
    return squareHasContainer(square, bestContainer.type)
end

function Base.GetFarm(character)
    local _baseId, base = baseForCharacter(character)
    if not base then
        return nil
    end

    return nearestRecord(character, base.farms, function(farm)
        local plant = getPlantAt(farm.x, farm.y, farm.z)
        if plant and plant.waterNeeded and plant.waterLvl and plant.waterNeeded > 0 and plant.waterLvl < plant.waterNeeded - 20 then
            return plant
        end
    end)
end

function Base.GetWaterSource(character)
    local _baseId, base = baseForCharacter(character)
    if not base then
        return nil
    end

    return nearestRecord(character, base.waterSources, function(sourceRecord)
        local square = resolveSquare(character, sourceRecord.x, sourceRecord.y, sourceRecord.z)
        local objects = square and square.getObjects and square:getObjects()
        for index = 0, safeCount(objects) - 1 do
            local object = safeGet(objects, index)
            if safeWaterAmount(object) > 10 then
                return object
            end
        end
    end)
end

function Base.GetGenerator(character)
    local _baseId, base = baseForCharacter(character)
    if not base then
        return nil
    end

    return nearestRecord(character, base.generators, function(generatorRecord)
        local square = resolveSquare(character, generatorRecord.x, generatorRecord.y, generatorRecord.z)
        local generator = square and square.getGenerator and square:getGenerator()
        if not generator then
            return nil
        end
        local condition = generator.getCondition and generator:getCondition() or 100
        local fuel = generator.getFuel and generator:getFuel() or 100
        if condition < 60 or fuel < 40 then
            return generator
        end
    end)
end

function Base.GetBlood(character)
    local _baseId, base = baseForCharacter(character)
    if not base then
        return nil
    end

    return nearestRecord(character, base.blood, function(bloodRecord)
        local square = resolveSquare(character, bloodRecord.x, bloodRecord.y, bloodRecord.z)
        if square and square.haveBlood and square:haveBlood() then
            return square
        end
    end)
end

function Base.GetTrashcan(character)
    local _baseId, base = baseForCharacter(character)
    if not base then
        return nil
    end

    return nearestRecord(character, base.trashcans, function(trashRecord)
        local square = resolveSquare(character, trashRecord.x, trashRecord.y, trashRecord.z)
        local objects = square and square.getObjects and square:getObjects()
        for index = 0, safeCount(objects) - 1 do
            local object = safeGet(objects, index)
            local sprite = object and object.getSprite and object:getSprite()
            local props = sprite and sprite.getProperties and sprite:getProperties()
            if props and props.Is and props:Is("IsTrashCan") then
                return object
            end
        end
    end)
end

function Base.GetGrave(character, isFull)
    local _baseId, base = baseForCharacter(character)
    if not base then
        return nil
    end

    return nearestRecord(character, base.graves, function(graveRecord)
        local square = resolveSquare(character, graveRecord.x, graveRecord.y, graveRecord.z)
        local objects = square and square.getSpecialObjects and square:getSpecialObjects()
        for index = 0, safeCount(objects) - 1 do
            local object = safeGet(objects, index)
            if object and object.getName and object:getName() == "EmptyGraves" then
                local modData = object.getModData and object:getModData() or {}
                local corpses = asNumber(modData.corpses, 0)
                if modData.filled == false and ((isFull and corpses >= 5) or ((not isFull) and corpses < 5)) then
                    return object
                end
            end
        end
    end)
end

function Base.GetDeadbody(character)
    local _baseId, base = baseForCharacter(character)
    if not base then
        return nil
    end

    return nearestRecord(character, base.deadbodies, function(bodyRecord)
        local square = resolveSquare(character, bodyRecord.x, bodyRecord.y, bodyRecord.z)
        if square and square.getDeadBody then
            return square:getDeadBody()
        end
    end)
end

return Base
