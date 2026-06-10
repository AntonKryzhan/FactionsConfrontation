-- NPCBlackMarketDefenseQuestServerBridge.lua
-- Black market defense contracts: hold a marked zone against three pistol waves.

require "NPCCore/NPCBlackMarketBridge"
require "NPCCore/NPCWeaponsBridge"
require "NPCCore/NPCOutfitsBridge"
require "NPCCore/NPCLegacyContractBridge"

NPCBlackMarketDefenseQuestServerBridge = NPCBlackMarketDefenseQuestServerBridge or {}

local BMDQ_WAVE_DELAY_MS = 15000
local BMDQ_TOTAL_WAVES = 3
local BMDQ_EXT_SANDBOX = "FactionsConfrontation"

local BMDQ_REWARD_CONTAINER_CANDIDATES = {
    "Base.Bag_ALICEpack_Army",
    "Base.Bag_ALICEpack",
    "Base.Bag_BigHikingBag",
    "Base.Bag_NormalHikingBag",
    "Base.Bag_DuffelBag",
    "Base.Bag_Satchel",
    "Base.Plasticbag"
}

local function bmdq_nowHours()
    if getGameTime and getGameTime() and getGameTime().getWorldAgeHours then
        local ok, value = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok and value then return tonumber(value) or 0 end
    end
    return os.time and ((os.time() or 0) / 3600) or 0
end

local function bmdq_nowMs()
    if getTimestampMs then
        local ok, value = pcall(function() return getTimestampMs() end)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return math.floor((os.time and os.time() or 0) * 1000)
end

local function bmdq_rand(minValue, maxValue)
    minValue = math.floor(tonumber(minValue) or 0)
    maxValue = math.floor(tonumber(maxValue) or minValue)
    if maxValue <= minValue then return minValue end
    if ZombRand then
        local ok, value = pcall(function() return ZombRand(minValue, maxValue) end)
        if ok and tonumber(value) then return tonumber(value) end
        ok, value = pcall(function() return minValue + ZombRand(maxValue - minValue) end)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return math.random(minValue, maxValue - 1)
end

local function bmdq_num(name, defaultValue, minValue, maxValue)
    local value = defaultValue
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        local ok, got = pcall(function() return NPCLegacySettingsBridge.GetNumber(name, defaultValue, minValue, maxValue) end)
        if ok and got ~= nil then value = got end
    else
        local vars = SandboxVars and SandboxVars[BMDQ_EXT_SANDBOX] or nil
        if vars and vars[name] ~= nil then value = vars[name] end
    end
    value = tonumber(value) or tonumber(defaultValue) or 0
    if minValue ~= nil and value < minValue then value = minValue end
    if maxValue ~= nil and value > maxValue then value = maxValue end
    return value
end

local function bmdq_dist2(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return dx * dx + dy * dy
end

local function bmdq_playerId(player)
    if NPCBlackMarketBridge and NPCBlackMarketBridge.PlayerId then
        local ok, id = pcall(function() return NPCBlackMarketBridge.PlayerId(player) end)
        if ok and id ~= nil then return tostring(id) end
    end
    if player and player.getOnlineID then
        local ok, id = pcall(function() return player:getOnlineID() end)
        if ok and id ~= nil then return tostring(id) end
    end
    if player and player.getUsername then
        local ok, name = pcall(function() return player:getUsername() end)
        if ok and name then return tostring(name) end
    end
    return nil
end

local function bmdq_playerName(player)
    if not player then return nil end
    if player.getUsername then
        local ok, name = pcall(function() return player:getUsername() end)
        if ok and name then return tostring(name) end
    end
    if player.getDisplayName then
        local ok, name = pcall(function() return player:getDisplayName() end)
        if ok and name then return tostring(name) end
    end
    return bmdq_playerId(player)
end

local function bmdq_isDead(player)
    if player and player.isDead then
        local ok, dead = pcall(function() return player:isDead() end)
        if ok and dead == true then return true end
    end
    return false
end

local function bmdq_data(gmd)
    if not (NPCBlackMarketBridge and NPCBlackMarketBridge.EnsureData) then return nil end
    local data = NPCBlackMarketBridge.EnsureData(gmd or GetNPCModData())
    if not data then return nil end
    data.defenseQuests = data.defenseQuests or {}
    data.nextDefenseQuestId = tonumber(data.nextDefenseQuestId) or 1
    data.stats = data.stats or {}
    data.stats.defenseQuests = tonumber(data.stats.defenseQuests) or 0
    return data
end

local function bmdq_key(player)
    local id = bmdq_playerId(player)
    if id and id ~= "" then return id end
    return nil
end

local function bmdq_active(data, player)
    local key = bmdq_key(player)
    if not (key and data and type(data.defenseQuests) == "table") then return key, nil end
    local quest = data.defenseQuests[key]
    if type(quest) == "table" and tostring(quest.status or "active") == "active" then return key, quest end
    return key, nil
end

local function bmdq_hasActiveFetch(data, player)
    local key = bmdq_key(player)
    if not (key and data and type(data.fetchQuests) == "table") then return false end
    local quest = data.fetchQuests[key]
    return type(quest) == "table" and tostring(quest.status or "active") == "active"
end

local function bmdq_nextId(data)
    data.nextDefenseQuestId = tonumber(data.nextDefenseQuestId) or 1
    local id = "black_market_defense_" .. tostring(data.nextDefenseQuestId)
    data.nextDefenseQuestId = data.nextDefenseQuestId + 1
    return id
end

local function bmdq_squareAt(cell, x, y, z)
    if not (cell and cell.getGridSquare and x and y) then return nil end
    local ok, square = pcall(function() return cell:getGridSquare(math.floor(x), math.floor(y), math.floor(z or 0)) end)
    if ok and square then return square end
    return nil
end

local function bmdq_lower(value)
    return string.lower(tostring(value or ""))
end

local function bmdq_javaListSize(list)
    if not list then return 0 end
    if type(list) == "table" then return #list end
    if list.size then
        local ok, value = pcall(function() return list:size() end)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return 0
end

local function bmdq_javaListGet(list, index)
    if not list then return nil end
    if type(list) == "table" then return list[(tonumber(index) or 0) + 1] end
    if list.get then
        local ok, value = pcall(function() return list:get(index) end)
        if ok then return value end
    end
    return nil
end

local function bmdq_buildingDefValue(buildingDef, getter)
    if not buildingDef then return nil end
    local ok, value = pcall(getter)
    if ok then return value end
    return nil
end

local function bmdq_buildingDefBounds(buildingDef)
    if not buildingDef then return nil end
    local x1 = tonumber(bmdq_buildingDefValue(buildingDef, function() return buildingDef:getX() end))
    local y1 = tonumber(bmdq_buildingDefValue(buildingDef, function() return buildingDef:getY() end))
    local x2 = tonumber(bmdq_buildingDefValue(buildingDef, function() return buildingDef:getX2() end))
    local y2 = tonumber(bmdq_buildingDefValue(buildingDef, function() return buildingDef:getY2() end))
    if not (x1 and y1 and x2 and y2) then return nil end
    if x2 < x1 then x1, x2 = x2, x1 end
    if y2 < y1 then y1, y2 = y2, y1 end
    local w = math.max(1, x2 - x1)
    local h = math.max(1, y2 - y1)
    local area = w * h
    if area < 18 then return nil end
    return {
        x1 = math.floor(x1),
        y1 = math.floor(y1),
        x2 = math.floor(x2),
        y2 = math.floor(y2),
        w = w,
        h = h,
        area = area,
        cx = math.floor((x1 + x2) / 2 + 0.5),
        cy = math.floor((y1 + y2) / 2 + 0.5)
    }
end

local function bmdq_buildingDefKey(buildingDef, bounds)
    if not buildingDef then return nil end
    local key = bmdq_buildingDefValue(buildingDef, function() return buildingDef:getKeyId() end)
    if key == nil then key = bmdq_buildingDefValue(buildingDef, function() return buildingDef:getID() end) end
    if key ~= nil then return tostring(key) end
    if bounds then
        return tostring(bounds.x1) .. ":" .. tostring(bounds.y1) .. ":" .. tostring(bounds.x2) .. ":" .. tostring(bounds.y2)
    end
    return nil
end

local function bmdq_roomType(roomDef)
    if not roomDef then return nil end
    if roomDef.getName then
        local ok, value = pcall(function() return roomDef:getName() end)
        if ok and value then return bmdq_lower(value) end
    end
    if roomDef.getType then
        local ok, value = pcall(function() return roomDef:getType() end)
        if ok and value then return bmdq_lower(value) end
    end
    return nil
end

local function bmdq_buildingRoomTypes(buildingDef)
    local types = {}
    if not buildingDef then return types end
    local ok, rooms = pcall(function() return buildingDef:getRooms() end)
    if not (ok and rooms) then return types end
    local count = bmdq_javaListSize(rooms)
    if count > 0 then
        for i=0, count-1 do
            local roomType = bmdq_roomType(bmdq_javaListGet(rooms, i))
            if roomType and roomType ~= "" then types[#types + 1] = roomType end
        end
    elseif type(rooms) == "table" then
        for _, roomDef in pairs(rooms) do
            local roomType = bmdq_roomType(roomDef)
            if roomType and roomType ~= "" then types[#types + 1] = roomType end
        end
    end
    return types
end

local function bmdq_hasRoomLike(types, needle)
    needle = bmdq_lower(needle)
    for _, roomType in ipairs(types or {}) do
        local value = bmdq_lower(roomType)
        if value == needle or string.find(value, needle, 1, true) then return true end
    end
    return false
end

local function bmdq_hasAnyRoomLike(types, needles)
    for _, needle in ipairs(needles or {}) do
        if bmdq_hasRoomLike(types, needle) then return true end
    end
    return false
end

local BMDQ_PRIVATE_HOME_GOOD_ROOMS = {"bedroom", "kitchen", "livingroom", "living", "bathroom", "garage"}
local BMDQ_PRIVATE_HOME_BAD_ROOMS = {"shop", "store", "office", "restaurant", "warehouse", "factory", "motel", "hotel", "police", "fire", "school", "church", "clinic", "hospital", "bank", "bar", "gas", "fossoil", "theatre", "cinema"}

local function bmdq_isPrivateHomeBuilding(buildingDef, bounds)
    local types = bmdq_buildingRoomTypes(buildingDef)
    if #types <= 0 then return false end
    if bmdq_hasAnyRoomLike(types, BMDQ_PRIVATE_HOME_BAD_ROOMS) then return false end
    local hasBedroom = bmdq_hasRoomLike(types, "bedroom")
    local hasKitchen = bmdq_hasRoomLike(types, "kitchen")
    local hasLiving = bmdq_hasRoomLike(types, "livingroom") or bmdq_hasRoomLike(types, "living")
    local hasBathroom = bmdq_hasRoomLike(types, "bathroom")
    local area = bounds and tonumber(bounds.area) or 0
    if hasBedroom and (hasKitchen or hasLiving or hasBathroom) then return true end
    if area > 0 and area <= 520 and bmdq_hasAnyRoomLike(types, BMDQ_PRIVATE_HOME_GOOD_ROOMS) then return true end
    return false
end

local function bmdq_buildingDefAt(x, y, z)
    local world = getWorld and getWorld() or nil
    if world and world.getMetaGrid then
        local metaGrid = world:getMetaGrid()
        if metaGrid and metaGrid.getRoomAt then
            local ok, roomDef = pcall(function() return metaGrid:getRoomAt(math.floor(x), math.floor(y), tonumber(z) or 0) end)
            if ok and roomDef then
                local okBuilding, buildingDef = pcall(function() return roomDef:getBuilding() end)
                if okBuilding and buildingDef then return buildingDef end
            end
        end
    end

    local cell = getCell and getCell() or nil
    local square = bmdq_squareAt(cell, x, y, z)
    if square and square.getBuilding then
        local okBuilding, building = pcall(function() return square:getBuilding() end)
        if okBuilding and building and building.getDef then
            local okDef, buildingDef = pcall(function() return building:getDef() end)
            if okDef and buildingDef then return buildingDef end
        end
    end
    return nil
end

local function bmdq_squareBuildingKey(square)
    if not (square and square.getBuilding) then return nil end
    local okBuilding, building = pcall(function() return square:getBuilding() end)
    if not (okBuilding and building and building.getDef) then return nil end
    local okDef, buildingDef = pcall(function() return building:getDef() end)
    if not (okDef and buildingDef) then return nil end
    return bmdq_buildingDefKey(buildingDef, bmdq_buildingDefBounds(buildingDef))
end

local function bmdq_pickSquareInsideBuilding(cell, buildingDef, bounds, z)
    if not bounds then return nil, nil, nil, z or 0 end
    local targetKey = bmdq_buildingDefKey(buildingDef, bounds)
    local bestSquare, bestX, bestY = nil, bounds.cx, bounds.cy
    local bestD2 = 999999999
    local cx = tonumber(bounds.cx) or 0
    local cy = tonumber(bounds.cy) or 0
    local stepMinX = math.max(bounds.x1, bounds.cx - 18)
    local stepMaxX = math.min(bounds.x2, bounds.cx + 18)
    local stepMinY = math.max(bounds.y1, bounds.cy - 18)
    local stepMaxY = math.min(bounds.y2, bounds.cy + 18)
    for x = stepMinX, stepMaxX do
        for y = stepMinY, stepMaxY do
            local square = bmdq_squareAt(cell, x, y, z)
            if square and (not targetKey or bmdq_squareBuildingKey(square) == targetKey) then
                local okRoom, room = pcall(function() return square:getRoom() end)
                if okRoom and room then
                    local d2 = bmdq_dist2(x, y, cx, cy)
                    if d2 < bestD2 then
                        bestD2 = d2
                        bestSquare = square
                        bestX = x
                        bestY = y
                    end
                end
            end
        end
    end
    return bestSquare, math.floor(bestX), math.floor(bestY), z or 0
end

local function bmdq_privateHousePoint(buildingDef, sourceX, sourceY, z)
    local bounds = bmdq_buildingDefBounds(buildingDef)
    if not bounds then return nil end
    if not bmdq_isPrivateHomeBuilding(buildingDef, bounds) then return nil end
    return {
        x = bounds.cx,
        y = bounds.cy,
        z = z or 0,
        d2 = bmdq_dist2(bounds.cx, bounds.cy, sourceX, sourceY),
        buildingKey = bmdq_buildingDefKey(buildingDef, bounds),
        buildingX = bounds.x1,
        buildingY = bounds.y1,
        buildingX2 = bounds.x2,
        buildingY2 = bounds.y2,
        buildingW = bounds.w,
        buildingH = bounds.h,
        buildingArea = bounds.area,
        buildingDef = buildingDef,
        bounds = bounds
    }
end

local function bmdq_findNearestPrivateHouse(sourceX, sourceY, z)
    local maxRadius = math.max(40, bmdq_num("BlackMarket_DefenseQuestHouseSearchRadius", 260, 40, 600))
    local step = math.max(4, bmdq_num("BlackMarket_DefenseQuestHouseSearchStep", 8, 4, 24))
    local seen = {}
    local best = nil

    local function consider(sx, sy)
        local buildingDef = bmdq_buildingDefAt(sx, sy, z)
        if not buildingDef then return end
        local bounds = bmdq_buildingDefBounds(buildingDef)
        local key = bmdq_buildingDefKey(buildingDef, bounds)
        if key and seen[key] then return end
        if key then seen[key] = true end
        local point = bmdq_privateHousePoint(buildingDef, sourceX, sourceY, z)
        if point and ((not best) or point.d2 < best.d2) then best = point end
    end

    consider(sourceX, sourceY)
    for radius = step, maxRadius, step do
        for dx = -radius, radius, step do
            consider(sourceX + dx, sourceY - radius)
            consider(sourceX + dx, sourceY + radius)
        end
        for dy = -radius + step, radius - step, step do
            consider(sourceX - radius, sourceY + dy)
            consider(sourceX + radius, sourceY + dy)
        end
        if best and best.d2 <= (radius + step) * (radius + step) then return best end
    end
    return best
end

local function bmdq_pickZoneSquare(player, contact, gmd)
    if not (player and player.getX and player.getY) then return nil end
    local cell = getCell and getCell() or nil
    local ox = contact and tonumber(contact.x) or tonumber(player:getX())
    local oy = contact and tonumber(contact.y) or tonumber(player:getY())
    local z = contact and tonumber(contact.z) or (player.getZ and math.floor(tonumber(player:getZ()) or 0) or 0)
    z = math.floor(tonumber(z) or 0)

    local house = bmdq_findNearestPrivateHouse(ox, oy, z)
    if not house then return nil, nil, nil, z, nil end

    local square, x, y, hz = bmdq_pickSquareInsideBuilding(cell, house.buildingDef, house.bounds, house.z or z)
    if not (x and y) then
        x = house.x
        y = house.y
        hz = house.z or z
    end
    return square, math.floor(x), math.floor(y), math.floor(hz or z), house
end

local function bmdq_contactFor(player, args)
    local gmd = GetNPCModData()
    if not (NPCBlackMarketBridge and NPCBlackMarketBridge.EnsureData) then return gmd, nil end
    NPCBlackMarketBridge.EnsureData(gmd)
    local contact = nil
    local contactId = tostring(args and args.contactId or "")
    if contactId ~= "" and NPCBlackMarketBridge.GetContact then
        contact = NPCBlackMarketBridge.GetContact(gmd, contactId)
    end
    if player and player.getX and player.getY then
        local radius = (NPCBlackMarketBridge.InteractionRadius and NPCBlackMarketBridge.InteractionRadius() or 28) + 8
        if contact and contact.x and contact.y and bmdq_dist2(contact.x, contact.y, player:getX(), player:getY()) <= radius * radius then
            return gmd, contact
        end
        if NPCBlackMarketBridge.NearestContact then
            local ok, nearest = pcall(function() return NPCBlackMarketBridge.NearestContact(gmd, player:getX(), player:getY(), radius) end)
            if ok and nearest then return gmd, nearest end
        end
    end
    return gmd, contact
end

local function bmdq_sendDebugMapUpdate(marker, player)
    if not marker then return end
    if NPCNetContract and NPCNetContract.SendDebugMapUpdate then
        pcall(function() NPCNetContract.SendDebugMapUpdate(marker, player) end)
    elseif player then
        sendServerCommand(player, 'NPCDebugMap', 'Update', marker)
    else
        sendServerCommand('NPCDebugMap', 'Update', marker)
    end
end

local function bmdq_sendDebugMapRemove(id, player)
    id = tostring(id or "")
    if id == "" then return end
    if NPCNetContract and NPCNetContract.SendDebugMapRemove then
        pcall(function() NPCNetContract.SendDebugMapRemove(id, player) end)
    elseif player then
        sendServerCommand(player, 'NPCDebugMap', 'Remove', {id=id})
    else
        sendServerCommand('NPCDebugMap', 'Remove', {id=id})
    end
end

local function bmdq_setMarker(gmd, marker, player)
    if not (gmd and marker and marker.id) then return nil end
    gmd.DebugMapMarkers = gmd.DebugMapMarkers or {}
    gmd.DebugMapMarkers[tostring(marker.id)] = marker
    bmdq_sendDebugMapUpdate(marker, player)
    return marker
end

local function bmdq_removeMarker(gmd, id, player)
    if gmd and gmd.DebugMapMarkers then gmd.DebugMapMarkers[tostring(id or "")] = nil end
    bmdq_sendDebugMapRemove(id, player)
end

local function bmdq_nonEmptyId(value)
    if value == nil then return nil end
    local text = tostring(value)
    if text == "" or text == "nil" then return nil end
    return text
end

local function bmdq_npcMarkerId(value)
    local text = bmdq_nonEmptyId(value)
    if not text then return nil end
    if string.sub(text, 1, 4) == "npc:" then return text end
    return "npc:" .. text
end

local function bmdq_removeDebugMarkerId(gmd, id, player)
    local text = bmdq_nonEmptyId(id)
    if not text then return false end
    if gmd and type(gmd.DebugMapMarkers) == "table" then gmd.DebugMapMarkers[text] = nil end
    bmdq_sendDebugMapRemove(text, player)
    return true
end

local function bmdq_removeNpcDebugMarkers(gmd, brain, queueKey, player)
    if not gmd then return 0 end
    local ids = {}
    local function add(value)
        local text = bmdq_nonEmptyId(value)
        if text then ids[text] = true end
    end
    add(queueKey)
    if type(brain) == "table" then
        add(brain.id)
        add(brain.runtimeId)
        add(brain.zombieId)
        add(brain.characterId)
        add(brain.uid)
        add(brain.persistentId)
    end
    local removed = 0
    for id in pairs(ids) do
        if bmdq_removeDebugMarkerId(gmd, id, player) then removed = removed + 1 end
        local npcId = bmdq_npcMarkerId(id)
        if npcId and bmdq_removeDebugMarkerId(gmd, npcId, player) then removed = removed + 1 end
    end
    return removed
end

local function bmdq_removeDefenseGroupMarkers(gmd, groupId, player)
    if not (gmd and type(gmd.DebugMapMarkers) == "table") then return 0 end
    local sid = bmdq_nonEmptyId(groupId)
    if not sid then return 0 end
    local remove = {}
    for id, marker in pairs(gmd.DebugMapMarkers) do
        if type(marker) == "table" then
            local markerGroup = bmdq_nonEmptyId(marker.worldGroupId or marker.groupId)
            if markerGroup == sid or tostring(marker.id or id) == sid then
                if marker.blackMarketDefenseEnemy == true or marker.blackMarketDefenseQuest == true or marker.blackMarketDefenseQuestId ~= nil or marker.markerType == "group" or marker.markerType == "npc" then
                    remove[#remove + 1] = tostring(id)
                end
            end
        elseif tostring(id) == sid then
            remove[#remove + 1] = tostring(id)
        end
    end
    local removed = 0
    for _, id in ipairs(remove) do
        if bmdq_removeDebugMarkerId(gmd, id, player) then removed = removed + 1 end
    end
    return removed
end

local function bmdq_removeFromPhysicalIds(group, ids)
    if not (type(group) == "table" and type(group.physicalIds) == "table" and type(ids) == "table") then return 0 end
    local nextIds = {}
    local removed = 0
    for _, value in ipairs(group.physicalIds) do
        local text = bmdq_nonEmptyId(value)
        if text and ids[text] then
            removed = removed + 1
        else
            nextIds[#nextIds + 1] = value
        end
    end
    group.physicalIds = nextIds
    return removed
end

local function bmdq_zoneRadius()
    if NPCBlackMarketBridge and NPCBlackMarketBridge.DefenseQuestZoneRadius then
        local ok, value = pcall(function() return NPCBlackMarketBridge.DefenseQuestZoneRadius() end)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return bmdq_num("BlackMarket_DefenseQuestZoneRadius", 28, 10, 90)
end

local function bmdq_marker(quest)
    if not quest then return nil end
    return {
        id = quest.id,
        markerType = "black_market_drop",
        blackMarket = true,
        blackMarketDrop = true,
        blackMarketDeadDrop = true,
        blackMarketDefenseQuest = true,
        blackMarketDefenseQuestId = quest.id,
        blackMarketDropId = quest.id,
        blackMarketDropType = "defense",
        blackMarketDropStatus = quest.status or "active",
        blackMarketDropLabel = "DEFEND",
        blackMarketId = quest.contactId,
        blackMarketContactId = quest.contactId,
        blackMarketPlayerId = quest.playerId,
        blackMarketPlayerName = quest.playerName,
        name = "Black market defense contract",
        displayName = "DEFEND ZONE",
        label = "DEFEND ZONE",
        blackMarketDropMapMarker = true,
        highContrastMapMarker = true,
        side = "black_market",
        factionSide = "black_market",
        sourceSide = quest.side,
        x = quest.x,
        y = quest.y,
        z = quest.z or 0,
        physicalStash = false,
        stashMarkerOverhead = true,
        stashRevealDistance = 160,
        blackMarketQuestZoneRadius = quest.zoneRadius or bmdq_zoneRadius(),
        blackMarketDefenseQuestWave = quest.currentWave or 0,
        blackMarketDefenseQuestRemaining = quest.remaining or 0,
        updatedAt = quest.updatedAt or bmdq_nowHours()
    }
end

local function bmdq_syncMarker(gmd, quest, player)
    local marker = bmdq_marker(quest)
    if marker then bmdq_setMarker(gmd, marker, player) end
    return marker
end

local function bmdq_statePayload(quest)
    if type(quest) ~= "table" or tostring(quest.status or "active") ~= "active" then return {quest=nil} end
    return {
        quest = {
            id = quest.id,
            contactId = quest.contactId,
            x = quest.x,
            y = quest.y,
            z = quest.z or 0,
            zoneRadius = quest.zoneRadius or bmdq_zoneRadius(),
            status = quest.status,
            stage = quest.stage or "travel",
            currentWave = tonumber(quest.currentWave) or 0,
            totalWaves = tonumber(quest.totalWaves) or BMDQ_TOTAL_WAVES,
            remaining = tonumber(quest.remaining) or 0,
            spawned = tonumber(quest.spawned) or 0,
            killed = tonumber(quest.killed) or 0,
            nextWaveAtMs = tonumber(quest.nextWaveAtMs) or 0
        }
    }
end

local function bmdq_sendState(player, quest, extra)
    if not player then return end
    local payload = bmdq_statePayload(quest)
    if type(extra) == "table" then
        for k, v in pairs(extra) do payload[k] = v end
    end
    sendServerCommand(player, 'NPCBlackMarket', 'DefenseQuestState', payload)
end

local function bmdq_onlinePlayersByKey()
    local out = {}
    if getOnlinePlayers then
        local okPlayers, players = pcall(function() return getOnlinePlayers() end)
        if okPlayers and players and players.size and players.get then
            local okSize, size = pcall(function() return players:size() end)
            size = okSize and (tonumber(size) or 0) or 0
            for i = 0, size - 1 do
                local okPlayer, player = pcall(function() return players:get(i) end)
                if okPlayer and player then
                    local key = bmdq_key(player)
                    if key then out[key] = player end
                end
            end
        end
    end
    if getPlayer then
        local okPlayer, player = pcall(function() return getPlayer() end)
        if okPlayer and player then
            local key = bmdq_key(player)
            if key then out[key] = player end
        end
    end
    return out
end

local function bmdq_worldDirector()
    local director = NPCWorldDirectorServer or NPCWorldDirector
    if type(director) == "table" and director.EnsureData then return director end
    return nil
end

local function bmdq_tableCopy(tbl)
    if type(tbl) ~= "table" then return nil end
    local out = {}
    for k, v in pairs(tbl) do out[k] = type(v) == "table" and bmdq_tableCopy(v) or v end
    return out
end

local function bmdq_pistolSpec()
    local fallback = {name="Base.Pistol", magName="Base.9mmClip", magSize=15, bulletsLeft=15, magCount=8, shotSound="M9Shoot", shotDelay=20, ammoName="Base.9mmBullets"}
    local pool = nil
    if NPCWeaponsBridge and NPCWeaponsBridge.GetSpawnSecondary then
        local ok, got = pcall(function() return NPCWeaponsBridge.GetSpawnSecondary(nil) end)
        if ok then pool = got end
    elseif NPCWeaponsBridge then
        pool = NPCWeaponsBridge.Secondary
    end
    if type(pool) == "table" and #pool > 0 then
        for _ = 1, 24 do
            local candidate = pool[bmdq_rand(1, #pool + 1)]
            local text = string.lower(tostring(candidate and candidate.name or ""))
            if text ~= "" and (string.find(text, "pistol", 1, true) or string.find(text, "glock", 1, true) or string.find(text, "m9", 1, true) or string.find(text, "colt", 1, true) or string.find(text, "revolver", 1, true)) then
                local weapon = bmdq_tableCopy(candidate)
                weapon.magSize = math.max(1, tonumber(weapon.magSize) or 15)
                weapon.bulletsLeft = weapon.magSize
                weapon.magCount = math.max(tonumber(weapon.magCount) or 0, 8)
                weapon.ammoName = weapon.ammoName or fallback.ammoName
                return weapon
            end
        end
    end
    return fallback
end

local function bmdq_waveEnemyCount(wave)
    local base = {4, 5, 6}
    local index = math.max(1, math.min(3, math.floor(tonumber(wave) or 1)))
    local value = base[index] or 4
    if NPCBlackMarketBridge and NPCBlackMarketBridge.DefenseQuestWaveSize then
        local ok, got = pcall(function() return NPCBlackMarketBridge.DefenseQuestWaveSize(index) end)
        if ok and tonumber(got) then value = tonumber(got) end
    end
    return math.max(1, math.floor(value))
end

local function bmdq_spawnPoint(quest, wave)
    local zoneRadius = tonumber(quest.zoneRadius) or bmdq_zoneRadius()
    local radius = math.max(2, math.min(zoneRadius - 3, 4 + (tonumber(wave) or 1) * 3))
    local angle = bmdq_rand(0, 6284) / 1000.0
    return math.floor((tonumber(quest.x) or 0) + math.cos(angle) * radius + 0.5), math.floor((tonumber(quest.y) or 0) + math.sin(angle) * radius + 0.5), tonumber(quest.z) or 0
end

local function bmdq_enemyAnchor(quest, index)
    local radius = math.max(3, (tonumber(quest.zoneRadius) or bmdq_zoneRadius()) - 4)
    local angle = ((math.max(1, tonumber(index) or 1) - 1) * 2.399963)
    return {x=math.floor((tonumber(quest.x) or 0) + math.cos(angle) * radius + 0.5), y=math.floor((tonumber(quest.y) or 0) + math.sin(angle) * radius + 0.5), z=tonumber(quest.z) or 0}
end

local function bmdq_defenseOutfit(index)
    local pool = {}
    local function append(list)
        if type(list) ~= "table" then return end
        for _, outfit in ipairs(list) do
            local text = tostring(outfit or "")
            if text ~= "" then pool[#pool + 1] = text end
        end
    end
    if NPCOutfitsBridge then
        append(NPCOutfitsBridge.NewOrder)
        append(NPCOutfitsBridge.PrivateMilitia)
        append(NPCOutfitsBridge.DeathLegion)
        append(NPCOutfitsBridge.Veteran)
        append(NPCOutfitsBridge.Police)
        append(NPCOutfitsBridge.Prepper)
    end
    if #pool <= 0 then
        pool = {"ArmyCamoGreen", "PrivateMilitia", "Veteran", "PoliceRiot", "Survivalist03"}
    end
    local idx = math.max(1, math.floor(tonumber(index) or 1))
    return pool[((idx - 1) % #pool) + 1] or "ArmyCamoGreen"
end

local function bmdq_applyEnemyFields(member, group, quest, index)
    if type(member) ~= "table" then return member end
    local anchor = bmdq_enemyAnchor(quest, index)
    local leash = math.max(6, tonumber(quest.zoneRadius) or bmdq_zoneRadius())
    member.blackMarketDefenseEnemy = true
    member.blackMarketDefenseQuestId = quest.id
    member.blackMarketQuestGuard = true
    member.blackMarketQuestId = quest.id
    member.blackMarketDefenseWave = quest.currentWave
    member.worldGroupId = group and group.id or member.worldGroupId
    member.groupId = group and group.id or member.groupId
    member.memberIndex = index
    member.blackMarketDefenseGuard = true
    member.defenceGuard = true
    member.displayTitle = "DEFENCE GUARD"
    member.nameplateTitle = "DEFENCE GUARD"
    member.role = "black_market_defense_guard"
    member.disablePersistence = true
    member.doNotPersist = true
    member.ephemeral = true
    member.tacticalRole = "assault"
    member.outfit = member.outfit or bmdq_defenseOutfit((tonumber(index) or 1) + ((tonumber(quest.currentWave) or 1) - 1) * 7)
    member.femaleChance = tonumber(member.femaleChance) or 0
    member.program = {name="BaseGuard", stage="Prepare"}
    member.guardPoint = {x=anchor.x, y=anchor.y, z=anchor.z}
    member.holdPoint = {x=anchor.x, y=anchor.y, z=anchor.z}
    member.returnPoint = {x=quest.x, y=quest.y, z=quest.z or 0}
    member.blackMarketDefenseCenter = {x=quest.x, y=quest.y, z=quest.z or 0}
    member.blackMarketDefenseNoNavigateOutside = true
    member.blackMarketDefenseTeleportLeash = true
    member.checkpointHoldRadius = leash
    member.blackMarketQuestGuardLeash = leash
    member.blackMarketDefenseZoneRadius = quest.zoneRadius or bmdq_zoneRadius()
    member.blackMarketDefenseMarkerColor = "black_market"
    member.highContrastMapMarker = true
    member.stashMarkerOverhead = true
    member.alwaysShowWorldMarker = true
    member.xrayWorldMarker = true
    member.order = {
        name="Guard",
        source="black_market_defense_quest",
        fireMode="FireAtWill",
        priority=96,
        sticky=true,
        strict=true,
        formation="loose",
        followDistance=1.0,
        anchor={x=anchor.x, y=anchor.y, z=anchor.z},
        guardPoint={x=anchor.x, y=anchor.y, z=anchor.z},
        leash={guard=leash, hold=math.max(4, leash * 0.75), combat=leash},
        note="Enter and hold the black-market defense zone"
    }
    member.factionSide = "black"
    member.faction = "black"
    member.side = "black"
    member.patrolColor = "black"
    member.hostile = true
    member.targetClass = "black_market_defense_player"
    member.humanNPC = true
    member.forceHumanAnimation = true
    member.noZombieAnimation = true
    member.defaultWalkType = "Run"
    member.walkType = "Run"
    member.preferCover = false
    member.preferRoads = false
    member.roadBias = false
    member.weapons = member.weapons or {}
    member.weapons.melee = false
    member.weapons.primary = false
    member.weapons.secondary = bmdq_pistolSpec()
    member.accuracyBoost = math.max(tonumber(member.accuracyBoost) or 1, 1.08)
    member.health = math.max(tonumber(member.health) or 2.6, 2.6 + (tonumber(quest.currentWave) or 1) * 0.25)
    member.maxHealth = math.max(tonumber(member.maxHealth) or 0, member.health)
    member.morale = math.max(tonumber(member.morale) or 0, 0.90)
    member.discipline = math.max(tonumber(member.discipline) or 0, 0.86)
    member.aggression = math.max(tonumber(member.aggression) or 0, 0.92)
    member.fear = math.min(tonumber(member.fear) or 1, 0.10)
    return member
end

local function bmdq_refreshEnemyOrders(gmd, quest)
    if not (gmd and quest and quest.waveGroupId) then return false end
    local group = gmd.VirtualGroups and gmd.VirtualGroups[tostring(quest.waveGroupId)] or nil
    if type(group) ~= "table" then return false end
    group.blackMarketDefenseQuestGroup = true
    group.blackMarketQuestGuardGroup = true
    group.blackMarketDefenseQuestId = quest.id
    group.targetX = quest.x
    group.targetY = quest.y
    group.targetZ = quest.z or 0
    group.routeX = quest.x
    group.routeY = quest.y
    group.routeZ = quest.z or 0
    group.hostile = true
    group.factionSide = "black"
    group.faction = "black"
    group.side = "black"
    group.patrolColor = "black"
    group.blackMarketDefenseNoNavigateOutside = true
    group.blackMarketDefenseMarkerColor = "black_market"
    group.program = {name="BaseGuard", stage="Prepare"}
    for i, member in ipairs(group.members or {}) do
        bmdq_applyEnemyFields(member, group, quest, i)
    end
    if type(gmd.Queue) == "table" then
        for runtimeId, brain in pairs(gmd.Queue) do
            if type(brain) == "table" and tostring(brain.worldGroupId or brain.groupId or "") == tostring(group.id) then
                local idx = tonumber(brain.memberIndex) or 1
                bmdq_applyEnemyFields(brain, group, quest, idx)
                gmd.Queue[runtimeId] = brain
            end
        end
    end
    group.updatedAt = bmdq_nowHours()
    gmd.VirtualGroups[tostring(group.id)] = group
    return true
end

local bmdq_countAlive

local function bmdq_countAliveInQueue(gmd, quest)
    if not (gmd and quest and type(gmd.Queue) == "table") then return 0 end
    local questId = tostring(quest.id or "")
    local groupId = tostring(quest.waveGroupId or "")
    if questId == "" or groupId == "" then return 0 end
    local alive = 0
    for _, brain in pairs(gmd.Queue) do
        if type(brain) == "table" and brain.dead ~= true and brain.isDead ~= true and not (tonumber(brain.health) ~= nil and tonumber(brain.health) <= 0) then
            local brainGroupId = tostring(brain.worldGroupId or brain.groupId or "")
            if brainGroupId == groupId then
                local defenseQuestId = tostring(brain.blackMarketDefenseQuestId or brain.blackMarketQuestId or "")
                if defenseQuestId == questId or brain.blackMarketDefenseEnemy == true or brain.blackMarketDefenseGuard == true or brain.role == "black_market_defense_enemy" or brain.role == "black_market_defense_guard" then
                    alive = alive + 1
                end
            end
        end
    end
    return alive
end

local function bmdq_spawnSquareNearQuest(gmd, player, quest, group, count)
    local serverRuntime = NPCServerRuntime or (NPCLegacyGlobalsBridge and NPCLegacyGlobalsBridge.Get and NPCLegacyGlobalsBridge.Get("ServerRuntime"))
    if not (serverRuntime and serverRuntime.Commands and serverRuntime.Commands.SpawnGroup) then return false, 0 end
    if not (gmd and quest and group and type(group.members) == "table" and #group.members > 0) then return false, 0 end

    local cell = getCell and getCell() or nil
    local z = tonumber(quest.z) or 0
    local square = bmdq_squareAt(cell, quest.x, quest.y, z)
    if not square and NPCWorldDirectorBridge and NPCWorldDirectorBridge.FindLoadedSpawnSquareNear then
        local director = bmdq_worldDirector()
        if director then
            local ok, got = pcall(function() return NPCWorldDirectorBridge.FindLoadedSpawnSquareNear(director, quest.x, quest.y, z, math.max(8, tonumber(quest.zoneRadius) or bmdq_zoneRadius())) end)
            if ok and got then square = got end
        end
    end
    if not square and player and player.getX and player.getY then
        square = bmdq_squareAt(cell, player:getX(), player:getY(), player.getZ and player:getZ() or z)
    end
    if not square then return false, 0 end

    group.x = square.getX and square:getX() or quest.x
    group.y = square.getY and square:getY() or quest.y
    group.z = square.getZ and square:getZ() or z
    group.preciseX = group.x
    group.preciseY = group.y
    group.anchorMaterializeAtGroup = nil
    group.anchorSpawnRadius = nil
    group.spawnPending = false
    group.spawnQueued = 0
    group.state = "defense_direct_spawn"
    group.updatedAt = bmdq_nowHours()
    gmd.VirtualGroups = gmd.VirtualGroups or {}
    gmd.VirtualGroups[tostring(group.id)] = group

    local event = {
        worldGroupId = group.id,
        worldDirector = true,
        x = group.x,
        y = group.y,
        z = group.z,
        hostile = true,
        program = group.program or {name="BaseGuard", stage="Prepare"},
        roadPatrol = false,
        roadBias = false,
        preferRoads = false,
        patrolColor = group.patrolColor or "black",
        inBattle = false,
        battleId = nil,
        battleEnemyGroupId = nil,
        virtualBattle = false,
        offscreenEntry = false,
        debugTeleportEntry = true,
        mercenaryLeashEntry = false,
        checkpointAnchorEntry = true,
        anchorMaterializeEntry = nil,
        entryTargetX = quest.x,
        entryTargetY = quest.y,
        entryTargetZ = quest.z or 0,
        bandits = group.members
    }

    local ok, spawned = pcall(function() return serverRuntime.Commands.SpawnGroup(player, event) end)
    spawned = ok and (tonumber(spawned) or 0) or 0
    if spawned <= 0 then
        if type(gmd.VirtualGroups) == "table" then gmd.VirtualGroups[tostring(group.id)] = nil end
        return false, 0
    end

    local current = gmd.VirtualGroups[tostring(group.id)] or group
    current.blackMarketDefenseQuestGroup = true
    current.blackMarketQuestGuardGroup = true
    current.blackMarketDefenseQuestId = quest.id
    current.activated = true
    current.virtual = false
    current.spawnFailed = false
    current.spawnPending = false
    current.spawnQueued = 0
    current.state = "physical"
    current.count = spawned
    current.updatedAt = bmdq_nowHours()
    gmd.VirtualGroups[tostring(group.id)] = current
    return true, spawned
end

local function bmdq_spawnWave(gmd, player, quest)
    if not (gmd and player and quest and quest.id) then return false end
    local director = bmdq_worldDirector()
    if not (director and NPCWorldDirectorBridge and NPCWorldDirectorBridge.PrepareVirtualMember) then return false end
    local waveIndex = (tonumber(quest.currentWave) or 0) + 1
    if waveIndex > (tonumber(quest.totalWaves) or BMDQ_TOTAL_WAVES) then return false end
    local count = bmdq_waveEnemyCount(waveIndex)
    local sx, sy, sz = bmdq_spawnPoint(quest, waveIndex)
    local spawnX, spawnY, spawnZ = tonumber(quest.x) or sx, tonumber(quest.y) or sy, tonumber(quest.z) or sz
    local groupId = "BMDQ" .. tostring(quest.id) .. "W" .. tostring(waveIndex)
    local wave = {enabled=true, enemyBehaviour=9, firstDay=0, lastDay=99999, spawnHourlyChance=0, groupSize=count, clanId=17, hasPistolChance=100, pistolMagCount=8, hasRifleChance=0, rifleMagCount=0}
    local group = {
        id = groupId,
        x = spawnX,
        y = spawnY,
        z = spawnZ,
        preciseX = spawnX,
        preciseY = spawnY,
        clanId = wave.clanId,
        count = count,
        hostile = true,
        program = {name="BaseGuard", stage="Prepare"},
        members = {},
        virtual = true,
        activated = false,
        createdAt = bmdq_nowHours(),
        updatedAt = bmdq_nowHours(),
        state = "black_market_defense_wave",
        spawnClass = "black_market_defense_enemy",
        targetX = quest.x,
        targetY = quest.y,
        targetZ = quest.z or 0,
        routeX = quest.x,
        routeY = quest.y,
        routeZ = quest.z or 0,
        intendedSpawnX = sx,
        intendedSpawnY = sy,
        intendedSpawnZ = sz,
        targetClass = "black_market_defense_player",
        speed = 1,
        patrolColor = "black",
        factionSide = "black",
        faction = "black",
        side = "black",
        blackMarketDefenseNoNavigateOutside = true,
        blackMarketDefenseMarkerColor = "black_market",
        blackMarketDefenseQuestGroup = true,
        blackMarketQuestGuardGroup = true,
        blackMarketDefenseQuestId = quest.id,
        blackMarketQuestContactId = quest.contactId,
        disablePersistence = true,
        doNotPersist = true,
        ephemeral = true,
        anchorMaterializeAtGroup = true,
        anchorSpawnRadius = 8,
        displayTitle = "DEFENSE WAVE " .. tostring(waveIndex),
        name = "Black market defense wave " .. tostring(waveIndex)
    }
    quest.currentWave = waveIndex
    quest.waveGroupId = groupId
    for i = 1, count do
        local member = nil
        local okMember, gotMember = pcall(function() return NPCWorldDirectorBridge.PrepareVirtualMember(director, gmd, wave, groupId, i, "black", false) end)
        if okMember then member = gotMember end
        if type(member) ~= "table" then member = {} end
        if NPCIdentityBridge and NPCIdentityBridge.NewUID then
            member.uid = member.uid or NPCIdentityBridge.NewUID(gmd)
            member.persistentId = member.persistentId or member.uid
        end
        bmdq_applyEnemyFields(member, group, quest, i)
        group.members[#group.members + 1] = member
    end
    group.count = #group.members
    if group.count <= 0 then return false end
    gmd.VirtualGroups = gmd.VirtualGroups or {}
    gmd.VirtualGroups[groupId] = group
    -- Defense waves are short-lived physical quest targets; never register them as persistent groups.
    local ok = false
    if director and director ~= NPCWorldDirectorBridge and director.MaterializeGroup then
        local safe, result = pcall(function() return director.MaterializeGroup(group, player) end)
        ok = safe and result == true
    end
    if not ok and NPCWorldDirectorBridge.MaterializeGroup then
        local safe, result = pcall(function() return NPCWorldDirectorBridge.MaterializeGroup(director, group, player) end)
        ok = safe and result == true
    end

    local current = gmd.VirtualGroups[groupId] or group
    local queueAlive = ok and bmdq_countAliveInQueue(gmd, quest) or 0
    local directSpawned = 0
    if (not ok) or queueAlive <= 0 then
        if type(gmd.VirtualGroups) == "table" then gmd.VirtualGroups[groupId] = group end
        ok, directSpawned = bmdq_spawnSquareNearQuest(gmd, player, quest, group, count)
        current = gmd.VirtualGroups[groupId] or group
        queueAlive = bmdq_countAliveInQueue(gmd, quest)
    end
    if not ok or queueAlive <= 0 then
        gmd.VirtualGroups[groupId] = nil
        quest.waveGroupId = nil
        quest.currentWave = waveIndex - 1
        return false
    end
    current.blackMarketDefenseQuestGroup = true
    current.blackMarketQuestGuardGroup = true
    current.blackMarketDefenseQuestId = quest.id
    current.state = current.spawnPending and "spawning" or "physical"
    current.updatedAt = bmdq_nowHours()
    gmd.VirtualGroups[groupId] = current
    quest.stage = "wave"
    bmdq_refreshEnemyOrders(gmd, quest)
    local physicalCount = 0
    if type(current.physicalIds) == "table" then physicalCount = #current.physicalIds end
    local aliveNow = bmdq_countAliveInQueue(gmd, quest)
    local spawnedNow = math.max(tonumber(aliveNow) or 0, tonumber(physicalCount) or 0, tonumber(directSpawned) or 0, tonumber(current.count) or 0)
    quest.spawned = spawnedNow
    quest.remaining = spawnedNow
    quest.killed = 0
    quest.waveSpawnedAtMs = bmdq_nowMs()
    quest.spawnGraceUntilMs = quest.waveSpawnedAtMs + 12000
    quest.updatedAt = bmdq_nowHours()
    bmdq_syncMarker(gmd, quest, player)
    bmdq_sendState(player, quest, {message="Defense wave " .. tostring(waveIndex) .. " started."})
    if TransmitNPCModData then TransmitNPCModData() end
    return true
end

local function bmdq_requestCleanup(gmd, quest, reason)
    if not (gmd and quest) then return false end
    local groupId = tostring(quest.waveGroupId or "")
    if groupId == "" then return false end
    local group = gmd.VirtualGroups and gmd.VirtualGroups[groupId] or nil
    if type(gmd.VirtualGroups) == "table" then gmd.VirtualGroups[groupId] = nil end
    if type(gmd.DebugMapMarkers) == "table" then gmd.DebugMapMarkers[groupId] = nil end
    bmdq_sendDebugMapRemove(groupId)
    bmdq_removeDefenseGroupMarkers(gmd, groupId)
    if type(gmd.PersistentGroups) == "table" then gmd.PersistentGroups[groupId] = nil end
    local director = bmdq_worldDirector()
    local args = {
        groupId = groupId,
        persistentIds = NPCWorldDirectorBridge and NPCWorldDirectorBridge.GroupPersistentIds and group and NPCWorldDirectorBridge.GroupPersistentIds(group) or nil,
        x = quest.x,
        y = quest.y,
        z = quest.z or 0,
        radius = (tonumber(quest.zoneRadius) or bmdq_zoneRadius()) + 60,
        reason = tostring(reason or "black_market_defense_quest_cleanup")
    }
    if director and director ~= NPCWorldDirectorBridge and director.RequestNPCObjectCleanup then pcall(function() director.RequestNPCObjectCleanup(args) end) end
    if NPCWorldDirectorBridge and NPCWorldDirectorBridge.RequestNPCObjectCleanup then pcall(function() NPCWorldDirectorBridge.RequestNPCObjectCleanup(director, args) end) end
    quest.waveGroupId = nil
    return true
end

local function bmdq_brainRuntimeId(brain, fallback)
    if type(brain) ~= "table" then return fallback end
    return brain.id or brain.runtimeId or fallback
end

local function bmdq_brainPosition(brain)
    if type(brain) ~= "table" then return nil, nil, nil end
    local dc = type(brain.debugCoords) == "table" and brain.debugCoords or nil
    local x = tonumber(dc and dc.x or brain.x or brain.preciseX or brain.lastX)
    local y = tonumber(dc and dc.y or brain.y or brain.preciseY or brain.lastY)
    local z = tonumber(dc and dc.z or brain.z or brain.lastZ) or 0
    return x, y, z
end

local function bmdq_clampedPoint(quest, index)
    local radius = math.max(2, (tonumber(quest.zoneRadius) or bmdq_zoneRadius()) - 5)
    local angle = ((math.max(1, tonumber(index) or 1) - 1) * 2.399963) + (bmdq_rand(0, 80) / 100.0)
    local x = math.floor((tonumber(quest.x) or 0) + math.cos(angle) * math.min(radius, 6) + 0.5)
    local y = math.floor((tonumber(quest.y) or 0) + math.sin(angle) * math.min(radius, 6) + 0.5)
    return x + 0.5, y + 0.5, tonumber(quest.z) or 0
end

local function bmdq_isDefenseBrainForQuest(brain, quest, groupId, questId)
    if type(brain) ~= "table" then return false end
    local brainGroupId = tostring(brain.worldGroupId or brain.groupId or "")
    if groupId ~= "" and brainGroupId ~= groupId then return false end
    local defenseQuestId = tostring(brain.blackMarketDefenseQuestId or brain.blackMarketQuestId or "")
    return defenseQuestId == questId or brain.blackMarketDefenseEnemy == true or brain.blackMarketDefenseGuard == true or brain.role == "black_market_defense_enemy" or brain.role == "black_market_defense_guard"
end

local function bmdq_requestEnemyTeleport(gmd, quest, queueKey, brain, reason)
    if not (gmd and quest and type(brain) == "table") then return false end
    local tx, ty, tz = bmdq_clampedPoint(quest, brain.memberIndex or queueKey)
    brain.x = tx
    brain.y = ty
    brain.z = tz
    brain.debugCoords = {x=tx, y=ty, z=tz}
    brain.guardPoint = brain.guardPoint or {x=tx, y=ty, z=tz}
    brain.holdPoint = brain.holdPoint or {x=tx, y=ty, z=tz}
    brain.returnPoint = {x=quest.x, y=quest.y, z=quest.z or 0}
    brain.blackMarketDefenseCenter = {x=quest.x, y=quest.y, z=quest.z or 0}
    brain.blackMarketDefenseNoNavigateOutside = true
    brain.currentThreat = nil
    brain.lastThreat = nil
    brain.targetId = nil
    brain.targetKind = nil
    brain.tasks = {}
    brain._lastDefenseLeashReason = tostring(reason or "zone_leash")
    brain._lastDefenseLeashAtMs = bmdq_nowMs()
    gmd.Queue[tostring(queueKey)] = brain
    if sendServerCommand and NPCLegacyContractBridge and NPCLegacyContractBridge.Commands then
        sendServerCommand('NPCCommands', NPCLegacyContractBridge.Commands.TELEPORT_OBJECTS, {
            objects = {{
                id = bmdq_brainRuntimeId(brain, queueKey),
                runtimeId = bmdq_brainRuntimeId(brain, queueKey),
                persistentId = brain.persistentId or brain.uid,
                uid = brain.uid,
                groupId = brain.worldGroupId or brain.groupId or quest.waveGroupId,
                worldGroupId = brain.worldGroupId or brain.groupId or quest.waveGroupId,
                x = tx,
                y = ty,
                z = tz,
                reason = tostring(reason or "black_market_defense_zone_leash")
            }}
        })
    end
    return true
end

local function bmdq_enforceZoneLeash(gmd, quest)
    if not (gmd and quest and type(gmd.Queue) == "table") then return 0 end
    local questId = tostring(quest.id or "")
    local groupId = tostring(quest.waveGroupId or "")
    if questId == "" or groupId == "" then return 0 end
    local radius = tonumber(quest.zoneRadius) or bmdq_zoneRadius()
    local hardRadius = math.max(2, radius - 0.25)
    local changed = 0
    for queueKey, brain in pairs(gmd.Queue) do
        if bmdq_isDefenseBrainForQuest(brain, quest, groupId, questId) then
            if brain.dead == true or brain.isDead == true or (tonumber(brain.health) ~= nil and tonumber(brain.health) <= 0) then
                gmd.Queue[queueKey] = nil
                changed = changed + 1
            else
                local x, y = bmdq_brainPosition(brain)
                if x and y and bmdq_dist2(x, y, quest.x, quest.y) > hardRadius * hardRadius then
                    if bmdq_requestEnemyTeleport(gmd, quest, queueKey, brain, "left_defense_zone") then
                        changed = changed + 1
                    end
                end
            end
        end
    end
    return changed
end

local function bmdq_markEnemyDead(gmd, quest, args, player)
    if not (gmd and quest and type(gmd.Queue) == "table") then return 0 end
    args = args or {}
    local removed = 0
    local groupId = bmdq_nonEmptyId(args.groupId or args.worldGroupId or quest.waveGroupId) or ""
    local questId = tostring(quest.id or "")
    local ids = {}
    local function addId(value)
        local text = bmdq_nonEmptyId(value)
        if not text then return end
        if string.sub(text, 1, 4) == "npc:" then
            ids[string.sub(text, 5)] = true
        end
        ids[text] = true
    end
    addId(args.runtimeId)
    addId(args.id)
    addId(args.zombieId)
    addId(args.characterId)
    addId(args.objectId)
    addId(args.persistentId)
    addId(args.uid)
    addId(args.queueKey)
    addId(args.brainId)

    local deathX = tonumber(args.x)
    local deathY = tonumber(args.y)
    local candidates = {}
    local exact = {}
    local bestKey, bestBrain, bestD2 = nil, nil, nil

    local function brainMatchesAnyId(queueKey, brain)
        if ids[tostring(queueKey or "")] then return true end
        if type(brain) ~= "table" then return false end
        return ids[tostring(brain.id or "")]
            or ids[tostring(brain.runtimeId or "")]
            or ids[tostring(brain.zombieId or "")]
            or ids[tostring(brain.characterId or "")]
            or ids[tostring(brain.uid or "")]
            or ids[tostring(brain.persistentId or "")]
    end

    for queueKey, brain in pairs(gmd.Queue) do
        if bmdq_isDefenseBrainForQuest(brain, quest, groupId, questId) then
            candidates[#candidates + 1] = {key=queueKey, brain=brain}
            if brainMatchesAnyId(queueKey, brain) then
                exact[#exact + 1] = {key=queueKey, brain=brain}
            elseif deathX and deathY then
                local bx, by = bmdq_brainPosition(brain)
                if bx and by then
                    local d2 = bmdq_dist2(bx, by, deathX, deathY)
                    if not bestD2 or d2 < bestD2 then
                        bestKey, bestBrain, bestD2 = queueKey, brain, d2
                    end
                end
            end
        end
    end

    local toRemove = exact
    if #toRemove <= 0 and bestKey and (bestD2 or 999999) <= math.max(25, (tonumber(quest.zoneRadius) or bmdq_zoneRadius()) ^ 2) then
        toRemove = {{key=bestKey, brain=bestBrain}}
    elseif #toRemove <= 0 and #candidates > 0 then
        -- Last-resort fallback: a defense death arrived but runtime identifiers did not line up.
        -- Remove one target from this wave so the quest cannot get stuck at left=N forever.
        toRemove = {candidates[1]}
    end

    local removedIds = {}
    for _, entry in ipairs(toRemove) do
        local queueKey = entry.key
        local brain = entry.brain
        if queueKey ~= nil and gmd.Queue[queueKey] ~= nil then
            if type(brain) == "table" then
                removedIds[tostring(queueKey)] = true
                removedIds[tostring(brain.id or "")] = true
                removedIds[tostring(brain.runtimeId or "")] = true
                removedIds[tostring(brain.zombieId or "")] = true
                removedIds[tostring(brain.characterId or "")] = true
                removedIds[tostring(brain.uid or "")] = true
                removedIds[tostring(brain.persistentId or "")] = true
            end
            gmd.Queue[queueKey] = nil
            bmdq_removeNpcDebugMarkers(gmd, brain, queueKey, player)
            removed = removed + 1
        end
    end

    if removed > 0 then
        local group = gmd.VirtualGroups and gmd.VirtualGroups[groupId] or nil
        if type(group) == "table" then
            bmdq_removeFromPhysicalIds(group, removedIds)
            group.count = math.max(0, (tonumber(group.count) or 0) - removed)
            group.disablePersistence = true
            group.doNotPersist = true
            group.ephemeral = true
            group.updatedAt = bmdq_nowHours()
            gmd.VirtualGroups[groupId] = group
        end
        if type(gmd.PersistentGroups) == "table" then gmd.PersistentGroups[groupId] = nil end
        quest.remaining = math.max(0, (tonumber(quest.remaining) or 0) - removed)
        quest.killed = math.max(tonumber(quest.killed) or 0, (tonumber(quest.spawned) or 0) - quest.remaining)
        quest.updatedAt = bmdq_nowHours()
    end
    return removed
end

function bmdq_countAlive(gmd, quest)
    if not (gmd and quest and type(gmd.Queue) == "table") then return 0 end
    local questId = tostring(quest.id or "")
    local groupId = tostring(quest.waveGroupId or "")
    if questId == "" or groupId == "" then return 0 end
    local alive = 0
    local aliveIds = {}
    for queueKey, brain in pairs(gmd.Queue) do
        if bmdq_isDefenseBrainForQuest(brain, quest, groupId, questId) then
            local dead = type(brain) ~= "table" or brain.dead == true or brain.isDead == true or (tonumber(brain.health) ~= nil and tonumber(brain.health) <= 0)
            if dead then
                bmdq_removeNpcDebugMarkers(gmd, brain, queueKey)
                gmd.Queue[queueKey] = nil
            else
                alive = alive + 1
                aliveIds[tostring(queueKey)] = true
                aliveIds[tostring(brain.id or "")] = true
                aliveIds[tostring(brain.runtimeId or "")] = true
                aliveIds[tostring(brain.uid or "")] = true
                aliveIds[tostring(brain.persistentId or "")] = true
            end
        end
    end

    if type(gmd.DebugMapMarkers) == "table" then
        local remove = {}
        for id, marker in pairs(gmd.DebugMapMarkers) do
            if type(marker) == "table" then
                local markerGroup = tostring(marker.worldGroupId or marker.groupId or "")
                if markerGroup == groupId and marker.blackMarketDefenseEnemy == true then
                    local runtimeId = bmdq_nonEmptyId(marker.runtimeId or marker.id)
                    if runtimeId and string.sub(runtimeId, 1, 4) == "npc:" then runtimeId = string.sub(runtimeId, 5) end
                    if not (runtimeId and aliveIds[runtimeId]) then remove[#remove + 1] = tostring(id) end
                end
            end
        end
        for _, id in ipairs(remove) do bmdq_removeDebugMarkerId(gmd, id) end
    end

    local group = gmd.VirtualGroups and gmd.VirtualGroups[groupId] or nil
    if type(group) == "table" then
        group.count = alive
        group.disablePersistence = true
        group.doNotPersist = true
        group.ephemeral = true
        group.updatedAt = bmdq_nowHours()
        if alive <= 0 and type(gmd.PersistentGroups) == "table" then gmd.PersistentGroups[groupId] = nil end
        gmd.VirtualGroups[groupId] = group
    end

    return alive
end

local function bmdq_inventoryItem(fullType)
    if not (InventoryItemFactory and fullType) then return nil end
    local ok, item = pcall(function() return InventoryItemFactory.CreateItem(tostring(fullType)) end)
    if ok and item then return item end
    return nil
end

local function bmdq_itemInventory(item)
    if not (item and item.getInventory) then return nil end
    local ok, inv = pcall(function() return item:getInventory() end)
    if ok then return inv end
    return nil
end

local function bmdq_addExisting(inv, item)
    if not (inv and item and inv.AddItem) then return false end
    local ok = pcall(function() inv:AddItem(item) end)
    return ok == true
end

local function bmdq_addItem(inv, fullType)
    if not (inv and fullType) then return nil end
    local item = bmdq_inventoryItem(fullType)
    if not item then return nil end
    if bmdq_addExisting(inv, item) then return item end
    return nil
end

local function bmdq_placeWorldInventoryItem(square, item)
    if not (square and item and square.AddWorldInventoryItem) then return false end
    local ok = pcall(function() square:AddWorldInventoryItem(item, 0.5, 0.5, 0) end)
    return ok == true
end

local function bmdq_createdFullType(item)
    if not item then return nil end
    if item.getFullType then
        local ok, ft = pcall(function() return item:getFullType() end)
        if ok and ft then return tostring(ft) end
    end
    return nil
end

local function bmdq_existingItem(fullType)
    local item = bmdq_inventoryItem(fullType)
    return item ~= nil
end

local function bmdq_ammoForSpec(spec)
    if type(spec) ~= "table" then return "Base.9mmBullets" end
    if spec.ammoName and bmdq_existingItem(spec.ammoName) then return spec.ammoName end
    local mag = string.lower(tostring(spec.magName or ""))
    local gun = string.lower(tostring(spec.name or ""))
    if string.find(mag, "556", 1, true) or string.find(gun, "m16", 1, true) or string.find(gun, "m4", 1, true) or string.find(gun, "m733", 1, true) then return bmdq_existingItem("Base.556Bullets") and "Base.556Bullets" or "Base.223Bullets" end
    if string.find(mag, "308", 1, true) or string.find(gun, "fal", 1, true) or string.find(gun, "m14", 1, true) then return "Base.308Bullets" end
    if string.find(mag, "ak", 1, true) or string.find(gun, "ak", 1, true) or string.find(gun, "sks", 1, true) then return bmdq_existingItem("Base.762x39Bullets") and "Base.762x39Bullets" or "Base.308Bullets" end
    if string.find(gun, "shotgun", 1, true) or string.find(gun, "spas", 1, true) or string.find(gun, "m870", 1, true) or string.find(gun, "mossberg", 1, true) then return "Base.ShotgunShells" end
    if string.find(mag, "9mm", 1, true) or string.find(gun, "mp5", 1, true) or string.find(gun, "uzi", 1, true) then return bmdq_existingItem("Base.9mmBullets") and "Base.9mmBullets" or "Base.Bullets9mm" end
    if string.find(mag, "45", 1, true) then return bmdq_existingItem("Base.45Bullets") and "Base.45Bullets" or "Base.Bullets45" end
    return bmdq_existingItem("Base.308Bullets") and "Base.308Bullets" or "Base.223Bullets"
end

local function bmdq_ammoBoxCandidates(ammo)
    local out = {}
    local seen = {}
    local function add(fullType)
        if not fullType or seen[fullType] then return end
        if bmdq_existingItem(fullType) then
            seen[fullType] = true
            out[#out + 1] = fullType
        end
    end
    local a = string.lower(tostring(ammo or ""))
    if string.find(a, "shotgun", 1, true) or string.find(a, "shell", 1, true) then
        add("Base.ShotgunShellsBox")
        add("Base.ShotgunShellBox")
    elseif string.find(a, "556", 1, true) or string.find(a, "5.56", 1, true) then
        add("Base.556Box")
        add("Base.556BulletsBox")
        add("Base.223Box")
    elseif string.find(a, "223", 1, true) then
        add("Base.223Box")
        add("Base.223BulletsBox")
    elseif string.find(a, "308", 1, true) or string.find(a, "7.62", 1, true) or string.find(a, "762", 1, true) then
        add("Base.308Box")
        add("Base.308BulletsBox")
        add("Base.762x39Box")
        add("Base.762x39BulletsBox")
    elseif string.find(a, "9mm", 1, true) then
        add("Base.Bullets9mmBox")
        add("Base.9mmBox")
        add("Base.9mmBulletsBox")
    elseif string.find(a, "45", 1, true) then
        add("Base.Bullets45Box")
        add("Base.45Box")
        add("Base.45BulletsBox")
    end
    add(tostring(ammo or "") .. "Box")
    return out
end

local function bmdq_uniqueAmmoBoxPool(ammoPool)
    local out = {}
    local seen = {}
    if type(ammoPool) ~= "table" then return out end
    for _, ammo in ipairs(ammoPool) do
        for _, fullType in ipairs(bmdq_ammoBoxCandidates(ammo)) do
            if not seen[fullType] then
                seen[fullType] = true
                out[#out + 1] = fullType
            end
        end
    end
    return out
end

local function bmdq_rewardCandidates()
    local out = {}
    local seen = {}
    local function addSpec(spec)
        if type(spec) ~= "table" or not spec.name or seen[tostring(spec.name)] then return end
        if not bmdq_existingItem(spec.name) then return end
        seen[tostring(spec.name)] = true
        out[#out + 1] = bmdq_tableCopy(spec)
    end
    local pools = {}
    if NPCWeaponsBridge and NPCWeaponsBridge.GetSpawnPrimary then
        local ok, pool = pcall(function() return NPCWeaponsBridge.GetSpawnPrimary(nil) end)
        if ok and type(pool) == "table" then pools[#pools + 1] = pool end
    end
    if NPCWeaponsBridge then
        if type(NPCWeaponsBridge.IntegratedPrimary) == "table" then pools[#pools + 1] = NPCWeaponsBridge.IntegratedPrimary end
        if type(NPCWeaponsBridge.FirearmsPrimary) == "table" then pools[#pools + 1] = NPCWeaponsBridge.FirearmsPrimary end
        if type(NPCWeaponsBridge.BritaArsenalPrimary) == "table" then pools[#pools + 1] = NPCWeaponsBridge.BritaArsenalPrimary end
        if type(NPCWeaponsBridge.Primary) == "table" then pools[#pools + 1] = NPCWeaponsBridge.Primary end
    end
    for _, pool in ipairs(pools) do
        for _, spec in ipairs(pool) do addSpec(spec) end
    end
    local fallback = {
        {name="Base.AssaultRifle", magName="Base.556Clip", magSize=30, ammoName="Base.556Bullets"},
        {name="Base.HuntingRifle", magName=false, magSize=5, ammoName="Base.308Bullets"},
        {name="Base.Shotgun", magName=false, magSize=5, ammoName="Base.ShotgunShells"},
        {name="Base.Pistol", magName="Base.9mmClip", magSize=15, ammoName="Base.9mmBullets"}
    }
    for _, spec in ipairs(fallback) do addSpec(spec) end
    return out
end

local function bmdq_markRewardBox(item, quest)
    if not (item and item.getModData and quest) then return end
    local ok, md = pcall(function() return item:getModData() end)
    if ok and type(md) == "table" then
        md.blackMarket = true
        md.blackMarketDefenseQuest = true
        md.blackMarketDefenseQuestRewardBox = true
        md.blackMarketDefenseQuestId = quest.id
        md.blackMarketContactId = quest.contactId
        md.blackMarketPlayerId = quest.playerId
        md.blackMarketPlayerName = quest.playerName
        md.blackMarketDropId = tostring(quest.id or "") .. "_defense_reward_box"
        md.blackMarketDropType = "defense_reward"
        md.blackMarketRewardPersistent = true
        md.blackMarketKeepOnVirtual = true
        md.blackMarketDoNotAutoCleanup = true
        md.worldNameplate = true
        md.worldNameplateTitle = "BLACK MARKET REWARD"
        md.worldNameplateSubtitle = "defense payment"
    end
    if item.setName then pcall(function() item:setName("BLACK MARKET REWARD") end) end
    if item.transmitModData then pcall(function() item:transmitModData() end) end
end

local function bmdq_inventoryCapacity(inv)
    if not inv then return nil end
    for _, method in ipairs({"getCapacity", "getMaxWeight", "getWeightLimit"}) do
        local fn = inv[method]
        if type(fn) == "function" then
            local ok, value = pcall(function() return fn(inv) end)
            if ok and tonumber(value) and tonumber(value) > 0 then return tonumber(value) end
        end
    end
    return nil
end

local function bmdq_inventoryWeight(inv)
    if not inv then return 0 end
    for _, method in ipairs({"getContentsWeight", "getWeight"}) do
        local fn = inv[method]
        if type(fn) == "function" then
            local ok, value = pcall(function() return fn(inv) end)
            if ok and tonumber(value) then return tonumber(value) end
        end
    end
    return 0
end

local function bmdq_itemWeight(fullType)
    local item = bmdq_inventoryItem(fullType)
    if not item then return 0.1 end
    for _, method in ipairs({"getActualWeight", "getWeight"}) do
        local fn = item[method]
        if type(fn) == "function" then
            local ok, value = pcall(function() return fn(item) end)
            if ok and tonumber(value) and tonumber(value) > 0 then return tonumber(value) end
        end
    end
    return 0.1
end

local function bmdq_rewardContainerItem()
    local bestItem = nil
    local bestCapacity = -1
    for _, fullType in ipairs(BMDQ_REWARD_CONTAINER_CANDIDATES) do
        local item = bmdq_inventoryItem(fullType)
        local inv = bmdq_itemInventory(item)
        if item and inv then
            local capacity = bmdq_inventoryCapacity(inv) or 0
            if capacity > bestCapacity then
                bestItem = item
                bestCapacity = capacity
            end
        end
    end
    return bestItem
end

local function bmdq_addRewardItem(inv, fullType)
    if not (inv and fullType and bmdq_existingItem(fullType)) then return nil end
    return bmdq_addItem(inv, fullType)
end

local function bmdq_fillAmmoToCapacity(inv, ammoPool, maxAdds)
    if not (inv and type(ammoPool) == "table" and #ammoPool > 0) then return 0 end
    local added = 0
    local capacity = bmdq_inventoryCapacity(inv)
    local boxPool = bmdq_uniqueAmmoBoxPool(ammoPool)
    local fillPool = (#boxPool > 0) and boxPool or ammoPool
    local minWeight = 999
    for _, ammo in ipairs(fillPool) do minWeight = math.min(minWeight, bmdq_itemWeight(ammo)) end
    if minWeight == 999 then minWeight = 0.1 end
    -- Prefer ammo boxes and cap individual item count. The old full-to-weight
    -- pass could create hundreds of bullet items inside a persistent world box.
    maxAdds = math.min(140, math.max(1, math.floor(tonumber(maxAdds) or 120)))
    local consecutiveFailed = 0
    local index = 1
    for _ = 1, maxAdds do
        if capacity and bmdq_inventoryWeight(inv) >= math.max(0, capacity - minWeight) then break end
        local ammo = fillPool[index]
        index = (index % #fillPool) + 1
        if ammo and bmdq_addRewardItem(inv, ammo) then
            added = added + 1
            consecutiveFailed = 0
        else
            consecutiveFailed = consecutiveFailed + 1
            if consecutiveFailed >= #fillPool then break end
        end
    end
    return added
end

local function bmdq_buildRewardBox(quest)
    local box = bmdq_rewardContainerItem()
    if not box then return nil, 0 end
    bmdq_markRewardBox(box, quest)
    local inv = bmdq_itemInventory(box)
    if not inv then return nil, 0 end
    local candidates = bmdq_rewardCandidates()
    if #candidates <= 0 then return nil, 0 end
    local added = 0
    local used = {}
    local selected = {}
    local wantWeapons = math.min(#candidates, bmdq_rand(3, 5))
    local attempts = 0
    while #selected < wantWeapons and attempts < (#candidates * 3) do
        attempts = attempts + 1
        local spec = candidates[bmdq_rand(1, #candidates + 1)]
        local key = spec and tostring(spec.name or "") or ""
        if spec and key ~= "" and not used[key] then
            used[key] = true
            selected[#selected + 1] = spec
        end
    end
    if #selected <= 0 then selected[1] = candidates[1] end

    local ammoPool = {}
    local seenAmmo = {}
    for _, spec in ipairs(selected) do
        if spec and spec.name and bmdq_addRewardItem(inv, spec.name) then
            added = added + 1
            local ammo = bmdq_ammoForSpec(spec)
            if ammo and bmdq_existingItem(ammo) and not seenAmmo[ammo] then
                seenAmmo[ammo] = true
                ammoPool[#ammoPool + 1] = ammo
            end
            if spec.magName and spec.magName ~= false and bmdq_existingItem(spec.magName) then
                for _ = 1, 6 do
                    if bmdq_addRewardItem(inv, spec.magName) then added = added + 1 end
                end
            end
            local boxCandidates = bmdq_ammoBoxCandidates(ammo)
            if #boxCandidates > 0 then
                for i = 1, 6 do
                    local boxAmmo = boxCandidates[((i - 1) % #boxCandidates) + 1]
                    if bmdq_addRewardItem(inv, boxAmmo) then added = added + 1 end
                end
            elseif ammo and bmdq_existingItem(ammo) then
                for _ = 1, 12 do
                    if bmdq_addRewardItem(inv, ammo) then added = added + 1 end
                end
            end
        end
    end

    added = added + bmdq_fillAmmoToCapacity(inv, ammoPool, 120)
    if added <= 0 then return nil, 0 end
    bmdq_markRewardBox(box, quest)
    return box, added
end

local function bmdq_placeReward(gmd, quest, player)
    local contact = NPCBlackMarketBridge and NPCBlackMarketBridge.GetContact and NPCBlackMarketBridge.GetContact(gmd, quest.contactId) or nil
    local x = tonumber(contact and contact.x) or tonumber(quest.turnInX) or (player and player.getX and tonumber(player:getX())) or tonumber(quest.x)
    local y = tonumber(contact and contact.y) or tonumber(quest.turnInY) or (player and player.getY and tonumber(player:getY())) or tonumber(quest.y)
    local z = tonumber(contact and contact.z) or tonumber(quest.turnInZ) or (player and player.getZ and tonumber(player:getZ())) or tonumber(quest.z) or 0
    local cell = getCell and getCell() or nil
    local square = bmdq_squareAt(cell, x, y, z)
    if not square then return false, 0 end
    local box, rewardCount = bmdq_buildRewardBox(quest)
    if not box then return false, 0 end
    if not bmdq_placeWorldInventoryItem(square, box) then return false, 0 end
    if contact then
        contact.blackMarketHasPendingReward = true
        contact.blackMarketRewardX = square.getX and square:getX() or x
        contact.blackMarketRewardY = square.getY and square:getY() or y
        contact.blackMarketRewardZ = square.getZ and square:getZ() or z
        contact.blackMarketNextMoveAt = math.max(tonumber(contact.blackMarketNextMoveAt) or 0, bmdq_nowHours() + 24)
        contact.updatedAt = bmdq_nowHours()
        if NPCBlackMarketBridge and NPCBlackMarketBridge.MakeMarker then
            bmdq_setMarker(gmd, NPCBlackMarketBridge.MakeMarker(contact), player)
        end
    end
    quest.rewardX = square.getX and square:getX() or x
    quest.rewardY = square.getY and square:getY() or y
    quest.rewardZ = square.getZ and square:getZ() or z
    quest.rewardItems = rewardCount
    return true, rewardCount
end

local function bmdq_complete(gmd, data, key, quest, player)
    if not (gmd and data and key and quest) then return false end
    bmdq_requestCleanup(gmd, quest, "black_market_defense_completed")
    quest.remaining = 0
    quest.killed = math.max(tonumber(quest.killed) or 0, tonumber(quest.spawned) or 0)
    local rewardOk, rewardCount = bmdq_placeReward(gmd, quest, player)
    if not rewardOk then
        -- The final wave is already cleared, but the black-market square can be
        -- unloaded when the player completes the zone far away from the contact.
        -- Keep the quest in a recoverable state and retry when the player returns
        -- to the market instead of leaving it stuck at wave 3/3, left 0.
        quest.status = "active"
        quest.stage = "reward_pending"
        quest.completedPending = true
        quest.remaining = 0
        quest.nextRewardRetryAtMs = bmdq_nowMs() + 5000
        quest.updatedAt = bmdq_nowHours()
        bmdq_removeMarker(gmd, quest.id, player)
        bmdq_sendState(player, quest, {message="Defense zone cleared. Return to the black market to claim the reward."})
        if TransmitNPCModData then TransmitNPCModData() end
        return false
    end
    data.defenseQuests[key] = nil
    quest.status = "completed"
    quest.stage = "completed"
    quest.completedPending = nil
    quest.remaining = 0
    quest.updatedAt = bmdq_nowHours()
    bmdq_removeMarker(gmd, quest.id, player)
    bmdq_sendState(player, nil, {completed=true, rewardBox=true, rewardItems=rewardCount, message="Defense contract completed. Reward placed at the black market."})
    if TransmitNPCModData then TransmitNPCModData() end
    return true
end

local function bmdq_cancel(gmd, data, key, quest, player, reason)
    if not (gmd and data and key and quest) then return false end
    bmdq_requestCleanup(gmd, quest, "black_market_defense_" .. tostring(reason or "cancelled"))
    data.defenseQuests[key] = nil
    quest.status = "cancelled"
    quest.stage = tostring(reason or "cancelled")
    quest.updatedAt = bmdq_nowHours()
    bmdq_removeMarker(gmd, quest.id, player)
    bmdq_sendState(player, nil, {cancelled=true, message="Defense contract cancelled."})
    if TransmitNPCModData then TransmitNPCModData() end
    return true
end

local function bmdq_create(gmd, player, contact)
    local data = bmdq_data(gmd)
    if not data then return false, "Black market data unavailable." end
    local key, active = bmdq_active(data, player)
    if active then return false, "Finish your active defense contract first." end
    if bmdq_hasActiveFetch(data, player) then return false, "Finish your active steal contract first." end
    local square, x, y, z, house = bmdq_pickZoneSquare(player, contact, gmd)
    if not (x and y) then return false, "No nearby private house was found for the defense zone." end
    local now = bmdq_nowHours()
    local quest = {
        id = bmdq_nextId(data),
        questType = "defense",
        status = "active",
        stage = "travel",
        contactId = contact and (contact.blackMarketId or contact.id) or nil,
        playerId = bmdq_playerId(player),
        playerName = bmdq_playerName(player),
        side = contact and (contact.blackMarketSide or contact.sourceSide) or nil,
        x = x,
        y = y,
        z = z or 0,
        turnInX = contact and contact.x,
        turnInY = contact and contact.y,
        turnInZ = contact and contact.z or 0,
        zoneRadius = bmdq_zoneRadius(),
        defenseHouse = house and true or false,
        defenseHouseKey = house and house.buildingKey or nil,
        defenseHouseX = house and house.buildingX or nil,
        defenseHouseY = house and house.buildingY or nil,
        defenseHouseX2 = house and house.buildingX2 or nil,
        defenseHouseY2 = house and house.buildingY2 or nil,
        defenseHouseArea = house and house.buildingArea or nil,
        currentWave = 0,
        totalWaves = BMDQ_TOTAL_WAVES,
        spawned = 0,
        killed = 0,
        remaining = 0,
        createdAt = now,
        updatedAt = now
    }
    data.defenseQuests[key] = quest
    data.stats.defenseQuests = (tonumber(data.stats.defenseQuests) or 0) + 1
    bmdq_syncMarker(gmd, quest, player)
    bmdq_sendState(player, quest, {message="Defense contract accepted. Enter the marked zone to start wave 1."})
    if TransmitNPCModData then TransmitNPCModData() end
    return true, quest
end

local function bmdq_playerInside(player, quest)
    if not (player and player.getX and player.getY and quest) then return false end
    local radius = tonumber(quest.zoneRadius) or bmdq_zoneRadius()
    return bmdq_dist2(player:getX(), player:getY(), quest.x, quest.y) <= radius * radius
end

local function bmdq_playerNearTurnIn(player, quest)
    if not (player and player.getX and player.getY and quest) then return false end
    local tx = tonumber(quest.turnInX) or tonumber(quest.x)
    local ty = tonumber(quest.turnInY) or tonumber(quest.y)
    if not (tx and ty) then return false end
    local radius = (NPCBlackMarketBridge and NPCBlackMarketBridge.InteractionRadius and NPCBlackMarketBridge.InteractionRadius() or 28) + 14
    return bmdq_dist2(player:getX(), player:getY(), tx, ty) <= radius * radius
end

local function bmdq_finalWaveCleared(quest)
    if type(quest) ~= "table" then return false end
    local stage = tostring(quest.stage or "")
    if stage == "reward_pending" or stage == "reward_failed" then return true end
    local currentWave = tonumber(quest.currentWave) or 0
    local totalWaves = tonumber(quest.totalWaves) or BMDQ_TOTAL_WAVES
    local spawned = tonumber(quest.spawned) or 0
    local remaining = tonumber(quest.remaining) or 0
    local graceUntil = tonumber(quest.spawnGraceUntilMs) or 0
    return stage == "wave" and currentWave >= totalWaves and spawned > 0 and remaining <= 0 and bmdq_nowMs() >= graceUntil
end

local function bmdq_rewardPending(quest)
    if type(quest) ~= "table" then return false end
    local stage = tostring(quest.stage or "")
    return stage == "reward_pending" or stage == "reward_failed" or quest.completedPending == true or bmdq_finalWaveCleared(quest)
end

local function bmdq_tryCompleteRewardPending(gmd, data, key, quest, player, force)
    if not bmdq_rewardPending(quest) then return false end
    quest.status = "active"
    quest.stage = "reward_pending"
    quest.completedPending = true
    quest.remaining = 0
    if not force then
        if not bmdq_playerNearTurnIn(player, quest) then
            bmdq_sendState(player, quest, {message="Defense zone cleared. Return to the black market to claim the reward."})
            return false
        end
        local now = bmdq_nowMs()
        if now < (tonumber(quest.nextRewardRetryAtMs) or 0) then return false end
        quest.nextRewardRetryAtMs = now + 5000
    end
    return bmdq_complete(gmd, data, key, quest, player)
end

local function bmdq_updateQuest(gmd, data, key, quest, player)
    if type(quest) ~= "table" or tostring(quest.status or "active") ~= "active" then
        data.defenseQuests[key] = nil
        return true
    end
    if player and bmdq_isDead(player) then
        return bmdq_cancel(gmd, data, key, quest, player, "player_dead")
    end
    if not player then return false end

    if bmdq_rewardPending(quest) then
        return bmdq_tryCompleteRewardPending(gmd, data, key, quest, player, false)
    end

    if quest.stage == "travel" then
        bmdq_syncMarker(gmd, quest, player)
        if bmdq_playerInside(player, quest) then
            return bmdq_spawnWave(gmd, player, quest)
        end
        return false
    end

    if quest.stage == "between_waves" then
        if bmdq_nowMs() >= (tonumber(quest.nextWaveAtMs) or 0) then
            return bmdq_spawnWave(gmd, player, quest)
        end
        return false
    end

    if quest.stage == "wave" then
        bmdq_enforceZoneLeash(gmd, quest)
        bmdq_refreshEnemyOrders(gmd, quest)
        local alive = bmdq_countAlive(gmd, quest)
        local spawned = tonumber(quest.spawned) or alive
        quest.remaining = alive
        quest.killed = math.max(0, spawned - alive)
        quest.updatedAt = bmdq_nowHours()
        bmdq_syncMarker(gmd, quest, player)
        bmdq_sendState(player, quest)
        if alive <= 0 and spawned > 0 and bmdq_nowMs() < (tonumber(quest.spawnGraceUntilMs) or ((tonumber(quest.waveSpawnedAtMs) or 0) + 3500)) then
            return false
        end
        if alive <= 0 and spawned > 0 then
            bmdq_requestCleanup(gmd, quest, "black_market_defense_wave_clear")
            if (tonumber(quest.currentWave) or 0) >= (tonumber(quest.totalWaves) or BMDQ_TOTAL_WAVES) then
                return bmdq_complete(gmd, data, key, quest, player)
            end
            quest.stage = "between_waves"
            quest.spawned = 0
            quest.killed = 0
            quest.remaining = 0
            quest.nextWaveAtMs = bmdq_nowMs() + BMDQ_WAVE_DELAY_MS
            quest.updatedAt = bmdq_nowHours()
            bmdq_syncMarker(gmd, quest, player)
            bmdq_sendState(player, quest, {message="Wave cleared. Next wave in 15 seconds."})
            if TransmitNPCModData then TransmitNPCModData() end
            return true
        end
    end
    return false
end

function NPCBlackMarketDefenseQuestServerBridge.Cleanup(gmd)
    local data = bmdq_data(gmd or GetNPCModData())
    if not (data and type(data.defenseQuests) == "table") then return 0 end
    local players = bmdq_onlinePlayersByKey()
    local changed = 0
    for key, quest in pairs(data.defenseQuests) do
        local player = players[tostring(key)]
        if bmdq_updateQuest(gmd, data, key, quest, player) then changed = changed + 1 end
    end
    return changed
end

function NPCBlackMarketDefenseQuestServerBridge.DefenseQuest(player, args)
    if not (NPCBlackMarketBridge and NPCBlackMarketBridge.IsEnabled and NPCBlackMarketBridge.IsEnabled()) then return end
    args = args or {}
    local action = tostring(args.action or "status")
    local gmd, contact = bmdq_contactFor(player, args)
    local data = bmdq_data(gmd)
    local key, quest = bmdq_active(data, player)

    if action == "status" then
        if quest and bmdq_rewardPending(quest) then
            bmdq_tryCompleteRewardPending(gmd, data, key, quest, player, contact ~= nil)
            key, quest = bmdq_active(data, player)
        end
        bmdq_sendState(player, quest)
        return
    elseif action == "claim_reward" then
        if quest and bmdq_rewardPending(quest) then
            if not bmdq_tryCompleteRewardPending(gmd, data, key, quest, player, contact ~= nil) then
                bmdq_sendState(player, quest, {message="Defense zone cleared. Stand near the black market and claim the reward again."})
            end
        else
            bmdq_sendState(player, quest)
        end
        return
    elseif action == "death" then
        if quest then bmdq_cancel(gmd, data, key, quest, player, "player_dead") else bmdq_sendState(player, nil) end
        return
    elseif action == "enemyDead" then
        if quest and tostring(args.questId or quest.id or "") == tostring(quest.id or "") then
            bmdq_markEnemyDead(gmd, quest, args, player)
            bmdq_updateQuest(gmd, data, key, quest, player)
        else
            bmdq_sendState(player, quest)
        end
        return
    elseif action == "track" then
        if quest and tostring(args.questId or "") == tostring(quest.id or "") and tostring(args.state or "") == "entered" then
            if quest.stage == "travel" and bmdq_playerInside(player, quest) then bmdq_spawnWave(gmd, player, quest) else bmdq_sendState(player, quest) end
        else
            bmdq_sendState(player, quest)
        end
        return
    elseif action == "take" then
        if not contact then
            if HaloTextHelper and player then HaloTextHelper.addText(player, "No black market service object nearby.", 255, 120, 70) end
            return
        end
        if quest and bmdq_rewardPending(quest) then
            bmdq_tryCompleteRewardPending(gmd, data, key, quest, player, true)
            return
        end
        local ok, result = bmdq_create(gmd, player, contact)
        if HaloTextHelper and player then
            if ok then
                HaloTextHelper.addText(player, "Defense contract accepted. Enter the marked zone.", 235, 160, 255)
            else
                HaloTextHelper.addText(player, tostring(result or "Defense contract unavailable."), 255, 120, 70)
            end
        end
        return
    end
    bmdq_sendState(player, quest)
end

function NPCBlackMarketDefenseQuestServerBridge.OnNPCRemoved(player, args)
    local gmd = GetNPCModData()
    local data = bmdq_data(gmd)
    if not (data and type(data.defenseQuests) == "table") then return false end
    local players = bmdq_onlinePlayersByKey()
    local changed = false
    for key, quest in pairs(data.defenseQuests) do
        if type(quest) == "table" and tostring(quest.status or "active") == "active" then
            local groupId = tostring(args and (args.groupId or args.worldGroupId) or "")
            if groupId == "" or groupId == tostring(quest.waveGroupId or "") then
                local playerForQuest = players[tostring(key)] or player
                if bmdq_markEnemyDead(gmd, quest, args or {}, playerForQuest) > 0 then
                    bmdq_updateQuest(gmd, data, key, quest, playerForQuest)
                    changed = true
                end
            end
        end
    end
    if changed and TransmitNPCModData then TransmitNPCModData() end
    return changed
end

function NPCBlackMarketDefenseQuestServerBridge.OnClientCommand(module, command, player, args)
    if not (NPCLegacyContractBridge and NPCLegacyContractBridge.IsModule and NPCLegacyContractBridge.IsModule(module, 'NPCBlackMarket', 'blackMarket')) then return end
    if command == 'DefenseQuest' then NPCBlackMarketDefenseQuestServerBridge.DefenseQuest(player, args or {}) end
end

local bmdq_tick = 0
local function bmdq_onTick()
    bmdq_tick = bmdq_tick + 1
    if bmdq_tick % 12 ~= 0 then return end
    local changed = NPCBlackMarketDefenseQuestServerBridge.Cleanup(GetNPCModData())
    if changed > 0 and TransmitNPCModData then TransmitNPCModData() end
end

local function bmdq_everyTen()
    NPCBlackMarketDefenseQuestServerBridge.Cleanup(GetNPCModData())
end

function NPCBlackMarketDefenseQuestServerBridge.Install()
    if NPCBlackMarketDefenseQuestServerBridge.__installed then return end
    NPCBlackMarketDefenseQuestServerBridge.__installed = true
    Events.OnClientCommand.Add(NPCBlackMarketDefenseQuestServerBridge.OnClientCommand)
    Events.OnTick.Add(bmdq_onTick)
    Events.EveryTenMinutes.Add(bmdq_everyTen)
end

NPCBlackMarketDefenseQuestServerBridge.Install()
