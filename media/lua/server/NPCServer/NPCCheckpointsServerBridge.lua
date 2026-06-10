-- NPCCheckpointsServerBridge.lua
-- Neutral server command layer and marker upkeep for lightweight faction checkpoints.

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

local NPC_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
if isClient and isClient() then return end

require "NPCCore/NPCCheckpointsBridge"
require "NPCCore/NPCDiagnosticsBridge"
require "NPCCore/NPCFactionDocsBridge"
require "NPCServer/NPCWorldDirector"
require "NPCServer/NPCWorldDirectorBridge"

NPCCheckpointsServerBridge = NPCCheckpointsServerBridge or {}
local function npcserver_setDebugMarker(gmd, marker)
    local runtime = NPCServerRuntime
    local setter = runtime and runtime.SetDebugMarker or NPC_LEGACY_GLOBALS.Get("SetDebugMarker")
    if setter then return setter(gmd, marker) end
    return false
end


local function bcps_halo(player, text, r, g, b)
    if player and text then sendServerCommand(player, 'NPCCheckpoints', 'Result', {text=text, r=r or 180, g=g or 230, b=b or 255}) end
end

local function bcps_say(player, text)
    if player and player.Say and text then pcall(function() player:Say(text) end) end
end

local function bcps_now()
    return NPCCheckpointsBridge and NPCCheckpointsBridge.NowHours and NPCCheckpointsBridge.NowHours() or 0
end

local function bcps_side(value)
    if NPCFactionBridge and NPCFactionBridge.NormalizeSide then return NPCFactionBridge.NormalizeSide(value) end
    value = tostring(value or ""):lower()
    if value == "red" or value == "green" or value == "blue" or value == "black" then return value end
    return nil
end

local function bcps_playerSide(player)
    if NPCFactionBridge and NPCFactionBridge.GetPlayerSide then
        local ok, side = pcall(function() return NPCFactionBridge.GetPlayerSide(player) end)
        if ok and side then return bcps_side(side) or "blue" end
    end
    return "blue"
end

local function bcps_setMarker(gmd, marker)
    if not (gmd and marker and marker.id) then return end
    if not npcserver_setDebugMarker(gmd, marker) then
        gmd.DebugMapMarkers = gmd.DebugMapMarkers or {}
        gmd.DebugMapMarkers[tostring(marker.id)] = marker
        if NPCNetContract and NPCNetContract.SendDebugMapUpdate then
            NPCNetContract.SendDebugMapUpdate(marker)
        else
            sendServerCommand('NPCDebugMap', 'Update', marker)
        end
    end
end

local function bcps_ensure(gmd)
    if not gmd then return nil end
    if not gmd.DebugMapMarkers then gmd.DebugMapMarkers = {} end
    if NPCCheckpointsBridge and NPCCheckpointsBridge.EnsureData then return NPCCheckpointsBridge.EnsureData(gmd) end
    return nil
end

local function bcps_markerFor(cp)
    return NPCCheckpointsBridge and NPCCheckpointsBridge.MakeMarker and NPCCheckpointsBridge.MakeMarker(cp) or nil
end

local function bcps_updateMarker(gmd, cp)
    local marker = bcps_markerFor(cp)
    if marker then bcps_setMarker(gmd, marker) end
end

local function bcps_num(name, defaultValue, minValue, maxValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        local ok, value = pcall(function() return NPCLegacySettingsBridge.GetNumber(name, defaultValue, minValue, maxValue) end)
        if ok and value ~= nil then return tonumber(value) or defaultValue end
    end
    return tonumber(defaultValue) or 0
end

local function bcps_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        local ok, value = pcall(function() return NPCLegacySettingsBridge.GetBool(name, defaultValue == true) end)
        if ok and value ~= nil then return value == true end
    end
    return defaultValue == true
end

local function bcps_players()
    local out = {}
    if getOnlinePlayers then
        local ok, list = pcall(function() return getOnlinePlayers() end)
        if ok and list and list.size and list.get then
            for i = 0, list:size() - 1 do
                local okPlayer, player = pcall(function() return list:get(i) end)
                if okPlayer and player then out[#out + 1] = player end
            end
        end
    end
    if #out == 0 and getPlayer then
        local ok, player = pcall(function() return getPlayer() end)
        if ok and player then out[#out + 1] = player end
    end
    return out
end

local function bcps_worldDirector()
    local director = NPCWorldDirectorServer or NPCWorldDirector
    if type(director) == "table" and director.EnsureData then return director end
    return nil
end


local function bcps_rand(maxValue)
    maxValue = math.floor(tonumber(maxValue) or 0)
    if maxValue <= 0 then return 0 end
    if ZombRand then
        local ok, value = pcall(function() return ZombRand(maxValue) end)
        if ok and value ~= nil then return tonumber(value) or 0 end
    end
    return math.random(0, maxValue - 1)
end

local function bcps_isCheckpointLifetimePaused(cp)
    if not cp then return false end
    local pauseRadius = math.max(
        tonumber(NPCCheckpointsBridge.PhysicalSpawnDistance and NPCCheckpointsBridge.PhysicalSpawnDistance()) or 92,
        (tonumber(cp.zoneRadius) or (NPCCheckpointsBridge.ZoneRadius and NPCCheckpointsBridge.ZoneRadius()) or 26) + 24
    )
    for _, player in ipairs(bcps_players()) do
        if player and player.getX and player.getY and NPCCheckpointsBridge.Distance(player:getX(), player:getY(), cp.x, cp.y) <= pauseRadius then
            return true
        end
    end
    return false
end

local function bcps_hasNearbyOther(gmd, x, y, radius, exceptId)
    local data = bcps_ensure(gmd)
    if not data then return false end
    radius = tonumber(radius) or (NPCCheckpointsBridge.MinSpacing and NPCCheckpointsBridge.MinSpacing()) or 360
    for _, cp in pairs(data.active or {}) do
        if type(cp) == "table" and cp.status ~= "removed" and tostring(cp.id or "") ~= tostring(exceptId or "") and cp.x and cp.y then
            if NPCCheckpointsBridge.Distance(x, y, cp.x, cp.y) <= radius then return true end
        end
    end
    return false
end

local function bcps_loadedSquareAllowsCheckpoint(x, y, z)
    if not getCell then return true end
    local cell = getCell()
    if not (cell and cell.getGridSquare) then return true end
    local ok, square = pcall(function() return cell:getGridSquare(math.floor(x), math.floor(y), math.floor(z or 0)) end)
    if not ok or not square then return true end
    if square.getRoom then
        local roomOk, room = pcall(function() return square:getRoom() end)
        if roomOk and room then return false end
    end
    if square.getFloor then
        local okFloor, floor = pcall(function() return square:getFloor() end)
        if okFloor and floor and floor.getSprite then
            local okSprite, sprite = pcall(function() return floor:getSprite() end)
            if okSprite and sprite and sprite.getName then
                local okName, name = pcall(function() return sprite:getName() end)
                if okName and name then
                    name = string.lower(tostring(name))
                    if string.find(name, "street", 1, true)
                        or string.find(name, "road", 1, true)
                        or string.find(name, "asphalt", 1, true)
                        or string.find(name, "parking", 1, true)
                        or string.find(name, "blends_street", 1, true) then
                        return true
                    end
                end
            end
        end
    end
    -- If the loaded square has no obvious road floor name, still allow it only
    -- when the meta/road navigation layer marks this exact point as road.
    if NPCRoadNavBridge and NPCRoadNavBridge.IsRoadPoint then
        local okRoad, isRoad = pcall(function() return NPCRoadNavBridge.IsRoadPoint(x, y) end)
        if okRoad then return isRoad == true end
    end
    return false
end

local function bcps_zoneTypesAt(x, y)
    if NPCRoadNavBridge and NPCRoadNavBridge.GetZoneTypesAt then
        local ok, types = pcall(function() return NPCRoadNavBridge.GetZoneTypesAt(x, y) end)
        if ok and type(types) == "table" then return types end
    end
    return {}
end

local function bcps_hasZoneKeyword(types, keyword)
    keyword = tostring(keyword or "")
    for _, zoneType in ipairs(types or {}) do
        if string.find(string.lower(tostring(zoneType or "")), keyword, 1, true) then return true end
    end
    return false
end

local function bcps_isRoadPoint(x, y)
    if NPCRoadNavBridge and NPCRoadNavBridge.IsRoadPoint then
        local ok, road = pcall(function() return NPCRoadNavBridge.IsRoadPoint(x, y) end)
        if ok and road == true then return true end
    end
    return false
end

local function bcps_strategicRoadScore(director, x, y, z)
    x = math.floor(tonumber(x) or 0)
    y = math.floor(tonumber(y) or 0)
    z = tonumber(z) or 0
    if not bcps_loadedSquareAllowsCheckpoint(x, y, z) then return nil end

    local okRoad, score, reason, urbanAffinity = false, -1000, "blocked", 0
    if NPCWorldDirectorBridge and NPCWorldDirectorBridge.IsUrbanRoadPatrolPoint then
        local ok, gotOk, gotScore, gotReason, gotUrban = pcall(function() return NPCWorldDirectorBridge.IsUrbanRoadPatrolPoint(director, x, y) end)
        if ok then
            okRoad = gotOk == true
            score = tonumber(gotScore) or score
            reason = gotReason or reason
            urbanAffinity = tonumber(gotUrban) or 0
        end
    end
    if not okRoad and not bcps_isRoadPoint(x, y) then return nil end
    if reason ~= "road" and not bcps_isRoadPoint(x, y) then return nil end

    local roadN = bcps_isRoadPoint(x, y - 14)
    local roadS = bcps_isRoadPoint(x, y + 14)
    local roadW = bcps_isRoadPoint(x - 14, y)
    local roadE = bcps_isRoadPoint(x + 14, y)
    local branches = (roadN and 1 or 0) + (roadS and 1 or 0) + (roadW and 1 or 0) + (roadE and 1 or 0)
    local intersection = ((roadN or roadS) and (roadW or roadE)) and 1 or 0
    local types = bcps_zoneTypesAt(x, y)
    local strategic = (tonumber(score) or 220) + (tonumber(urbanAffinity) or 0)
    strategic = strategic + branches * 40 + intersection * 160
    if bcps_hasZoneKeyword(types, "junction") or bcps_hasZoneKeyword(types, "intersection") then strategic = strategic + 180 end
    if bcps_hasZoneKeyword(types, "bridge") then strategic = strategic + 160 end
    if bcps_hasZoneKeyword(types, "highway") then strategic = strategic + 80 end
    if bcps_hasZoneKeyword(types, "town") or bcps_hasZoneKeyword(types, "commercial") or bcps_hasZoneKeyword(types, "residential") then strategic = strategic + 90 end
    if bcps_hasZoneKeyword(types, "forest") or bcps_hasZoneKeyword(types, "field") or bcps_hasZoneKeyword(types, "farm") then return nil end
    return strategic, {branches=branches, intersection=intersection == 1, urbanAffinity=urbanAffinity, zoneTypes=types}
end

local function bcps_callRoadPoint(director, mode, x, y, radius)
    local point = nil
    if mode == "near" then
        if NPCWorldDirectorBridge and NPCWorldDirectorBridge.GetNearbyRoadPoint then
            local ok, got = pcall(function() return NPCWorldDirectorBridge.GetNearbyRoadPoint(director, x, y, radius) end)
            if ok then point = got end
        end
        if (not point) and director and director.GetNearbyRoadPoint then
            local ok, got = pcall(function() return director.GetNearbyRoadPoint(director, x, y, radius) end)
            if not ok then ok, got = pcall(function() return director.GetNearbyRoadPoint(x, y, radius) end) end
            if ok then point = got end
        end
    else
        if director and director.GetRandomRoadPoint then
            local ok, got = pcall(function() return director.GetRandomRoadPoint(director) end)
            if not ok then ok, got = pcall(function() return director.GetRandomRoadPoint() end) end
            if ok then point = got end
        end
        if (not point) and NPCWorldDirectorBridge and NPCWorldDirectorBridge.GetRandomRoadPoint then
            local ok, got = pcall(function() return NPCWorldDirectorBridge.GetRandomRoadPoint(director) end)
            if ok then point = got end
        end
    end
    return point
end

local function bcps_findStrategicCheckpointPoint(gmd, aroundX, aroundY, exceptId)
    aroundX = tonumber(aroundX)
    aroundY = tonumber(aroundY)
    if not (aroundX and aroundY) then
        aroundX = nil
        aroundY = nil
    end
    local director = bcps_worldDirector()
    if not (director and NPCWorldDirectorBridge) then return nil end
    local best, bestScore, bestMeta = nil, -1000000, nil
    local attempts = aroundX and 34 or 48
    for i = 1, attempts do
        local candidate = nil
        if aroundX and i <= 18 then
            candidate = bcps_callRoadPoint(director, "near", aroundX, aroundY, 560 + bcps_rand(340))
        else
            candidate = bcps_callRoadPoint(director, "random")
        end
        if candidate and candidate.x and candidate.y then
            local x = math.floor(tonumber(candidate.x) or 0)
            local y = math.floor(tonumber(candidate.y) or 0)
            local z = tonumber(candidate.z) or 0
            if not bcps_hasNearbyOther(gmd, x, y, NPCCheckpointsBridge.MinSpacing and NPCCheckpointsBridge.MinSpacing() or 360, exceptId) then
                local score, meta = bcps_strategicRoadScore(director, x, y, z)
                if score and score > bestScore then
                    bestScore = score
                    bestMeta = meta
                    best = {x=x, y=y, z=z, spawnClass="strategic_road", zoneScore=score, strategic=true, strategicScore=score, strategicMeta=meta}
                    if score >= 720 then break end
                end
            end
        end
    end
    return best, bestScore, bestMeta
end

local BCPS_PROP_ITEMS = {
    "Base.Plank",
    "Base.SheetMetal",
    "Base.ScrapMetal",
    "Base.EmptyPetrolCan",
    "Base.NailsBox",
    "Base.PetrolCan"
}

local function bcps_inventoryItem(fullType)
    if not (InventoryItemFactory and InventoryItemFactory.CreateItem and fullType) then return nil end
    local ok, item = pcall(function() return InventoryItemFactory.CreateItem(fullType) end)
    if ok then return item end
    return nil
end

local BCPS_ROADBLOCK_VEHICLES = {
    "Base.CarLightsPolice",
    "Base.CarNormalPolice",
    "Base.PickUpVanLightsPolice",
    "Base.PickUpTruckLightsPolice",
    "Base.PickUpVanLights",
    "Base.CarLights"
}

local BCPS_ROADBLOCK_ITEMS = {
    "Base.Tire",
    "Base.Wheel",
    "Base.SheetMetal",
    "Base.ScrapMetal",
    "Base.Plank",
    "Base.EmptyPetrolCan",
    "Base.PetrolCan",
    "Base.NailsBox"
}

local function bcps_playerKey(player)
    if not player then return nil end
    if player.getOnlineID then
        local ok, id = pcall(function() return player:getOnlineID() end)
        if ok and id ~= nil then return tostring(id) end
    end
    if player.getUsername then
        local ok, name = pcall(function() return player:getUsername() end)
        if ok and name then return tostring(name) end
    end
    return nil
end

local function bcps_playerName(player)
    if player and player.getUsername then
        local ok, name = pcall(function() return player:getUsername() end)
        if ok and name then return tostring(name) end
    end
    return "player"
end

local function bcps_markRoadblockVehicle(vehicle, cp, index)
    if not (vehicle and cp) then return end
    if vehicle.getModData then
        local ok, md = pcall(function() return vehicle:getModData() end)
        if ok and type(md) == "table" then
            md.checkpointVehicle = true
            md.physicalCheckpoint = true
            md.checkpointId = tostring(cp.id or "")
            md.checkpointSide = cp.side or cp.checkpointSide
            md.factionSide = cp.side or cp.checkpointSide
            md.propIndex = index or 0
        end
    end
    if vehicle.setKeyIsOnDoor then pcall(function() vehicle:setKeyIsOnDoor(false) end) end
    if vehicle.setHotwired then pcall(function() vehicle:setHotwired(false) end) end
    if vehicle.setHeadlightsOn then pcall(function() vehicle:setHeadlightsOn(true) end) end
    if vehicle.setLightbarLightsMode then pcall(function() vehicle:setLightbarLightsMode(2) end) end
    if vehicle.repair then pcall(function() vehicle:repair() end) end
    if vehicle.transmitCompleteItemToClients then pcall(function() vehicle:transmitCompleteItemToClients() end) end
end

local function bcps_directionForIndex(index)
    if not IsoDirections then return nil end
    local dirs = {IsoDirections.E, IsoDirections.W, IsoDirections.N, IsoDirections.S}
    return dirs[((tonumber(index) or 1) - 1) % #dirs + 1]
end

local function bcps_trySpawnRoadblockVehicle(square, index)
    if not (square and addVehicleDebug) then return nil end
    local dir = bcps_directionForIndex(index)
    for _, script in ipairs(BCPS_ROADBLOCK_VEHICLES) do
        local ok, vehicle = pcall(function() return addVehicleDebug(script, dir, nil, square) end)
        if ok and vehicle then return vehicle end
    end
    return nil
end

local function bcps_removeVehicle(vehicle)
    if not vehicle then return false end
    local removed = false
    for _, method in ipairs({"removeFromWorld", "removeFromSquare", "permanentlyRemove"}) do
        if vehicle[method] then
            local ok = pcall(function() vehicle[method](vehicle) end)
            removed = removed or ok == true
        end
    end
    return removed
end

local function bcps_findVehicleById(id)
    id = tonumber(id)
    if not id then return nil end
    if getVehicleById then
        local ok, vehicle = pcall(function() return getVehicleById(id) end)
        if ok and vehicle then return vehicle end
    end
    if getCell then
        local cell = getCell()
        if cell and cell.getVehicles then
            local okList, list = pcall(function() return cell:getVehicles() end)
            if okList and list and list.size and list.get then
                for i = 0, list:size() - 1 do
                    local okVeh, vehicle = pcall(function() return list:get(i) end)
                    if okVeh and vehicle and vehicle.getId then
                        local okId, gotId = pcall(function() return vehicle:getId() end)
                        if okId and tonumber(gotId) == id then return vehicle end
                    end
                end
            end
        end
    end
    return nil
end

local function bcps_removeMarkedWorldObjects(gmd, cp)
    if not (cp and getCell) then return 0 end
    local cell = getCell()
    if not (cell and cell.getGridSquare) then return 0 end
    local radius = math.max(6, math.floor(tonumber(cp.zoneRadius) or (NPCCheckpointsBridge.ZoneRadius and NPCCheckpointsBridge.ZoneRadius()) or 26))
    local cx, cy, cz = math.floor(tonumber(cp.x) or 0), math.floor(tonumber(cp.y) or 0), math.floor(tonumber(cp.z) or 0)
    local removed = 0
    for dx = -radius, radius do
        for dy = -radius, radius do
            local okSq, square = pcall(function() return cell:getGridSquare(cx + dx, cy + dy, cz) end)
            if okSq and square and square.getWorldObjects then
                local okObjects, objects = pcall(function() return square:getWorldObjects() end)
                if okObjects and objects and objects.size and objects.get then
                    local okSize, size = pcall(function() return objects:size() end)
                    size = okSize and (tonumber(size) or 0) or 0
                    for i = size - 1, 0, -1 do
                        local okObj, obj = pcall(function() return objects:get(i) end)
                        if okObj and obj and obj.getItem then
                            local okItem, item = pcall(function() return obj:getItem() end)
                            local md = nil
                            if okItem and item and item.getModData then
                                local okMd, gotMd = pcall(function() return item:getModData() end)
                                if okMd and type(gotMd) == "table" then md = gotMd end
                            end
                            if type(md) == "table" and tostring(md.checkpointId or "") == tostring(cp.id or "") and md.physicalCheckpoint == true then
                                if square.transmitRemoveItemFromSquare then pcall(function() square:transmitRemoveItemFromSquare(obj) end) end
                                if square.removeWorldObject then pcall(function() square:removeWorldObject(obj) end) end
                                if obj.removeFromSquare then pcall(function() obj:removeFromSquare() end) end
                                if obj.removeFromWorld then pcall(function() obj:removeFromWorld() end) end
                                removed = removed + 1
                            end
                        end
                    end
                end
            end
        end
    end
    return removed
end

local function bcps_removeMarker(gmd, cp)
    if not (gmd and cp and cp.id) then return end
    if gmd.DebugMapMarkers then gmd.DebugMapMarkers[tostring(cp.markerId or cp.id)] = nil end
    if NPCNetContract and NPCNetContract.SendDebugMapRemove then
        NPCNetContract.SendDebugMapRemove(tostring(cp.markerId or cp.id))
    else
        sendServerCommand('NPCDebugMap', 'Remove', {id=tostring(cp.markerId or cp.id)})
    end
end

local function bcps_removePhysicalCheckpoint(gmd, cp, reason)
    if not (gmd and cp) then return false end
    for _, id in ipairs(cp.physicalVehicleIds or {}) do
        local vehicle = bcps_findVehicleById(id)
        if vehicle then bcps_removeVehicle(vehicle) end
    end
    bcps_removeMarkedWorldObjects(gmd, cp)
    local groupId = cp.physicalGuardGroupId
    if groupId and gmd.VirtualGroups then gmd.VirtualGroups[tostring(groupId)] = nil end
    cp.status = "removed"
    cp.removedReason = reason or "cleared"
    cp.updatedAt = bcps_now()
    cp.physicalGuardGroupId = nil
    cp.physicalState = "cleared"
    cp.physicalRoadblockPlaced = false
    cp.physicalPropsPlaced = false
    bcps_removeMarker(gmd, cp)
    return true
end

local function bcps_cellSquare(x, y, z)
    if not getCell then return nil end
    local cell = getCell()
    if not (cell and cell.getGridSquare) then return nil end
    local ok, square = pcall(function() return cell:getGridSquare(math.floor(tonumber(x) or 0), math.floor(tonumber(y) or 0), math.floor(tonumber(z) or 0)) end)
    if ok then return square end
    return nil
end

local function bcps_markProp(item, cp, index)
    if not (item and item.getModData and cp) then return end
    local ok, md = pcall(function() return item:getModData() end)
    if not (ok and type(md) == "table") then return end
    md.checkpointProp = true
    md.checkpointId = tostring(cp.id or "")
    md.checkpointSide = cp.side or cp.checkpointSide
    md.factionSide = cp.side or cp.checkpointSide
    md.worldNameplate = false
    md.physicalCheckpoint = true
    md.propIndex = index or 0
    if item.setName then pcall(function() item:setName("Checkpoint barricade") end) end
    if item.transmitModData then pcall(function() item:transmitModData() end) end
end

local function bcps_placePhysicalProps(gmd, cp)
    if not (gmd and cp and NPCCheckpointsBridge and NPCCheckpointsBridge.PhysicalPropsEnabled and NPCCheckpointsBridge.PhysicalPropsEnabled()) then return 0 end
    if cp.physicalPropsPlaced == true then return 0 end
    local maxProps = NPCCheckpointsBridge.PhysicalPropsMax and NPCCheckpointsBridge.PhysicalPropsMax() or 6
    if maxProps <= 0 then return 0 end
    local radius = NPCCheckpointsBridge.PhysicalPropRadius and NPCCheckpointsBridge.PhysicalPropRadius() or 4
    local placed = 0
    local offsets = {
        {-radius, 0}, {radius, 0}, {0, -radius}, {0, radius},
        {-radius + 1, -1}, {radius - 1, 1}, {-1, radius - 1}, {1, -radius + 1},
        {-radius, 1}, {radius, -1}, {1, radius}, {-1, -radius}
    }
    for i, off in ipairs(offsets) do
        if placed >= maxProps then break end
        local square = bcps_cellSquare((tonumber(cp.x) or 0) + off[1], (tonumber(cp.y) or 0) + off[2], tonumber(cp.z) or 0)
        if square and square.AddWorldInventoryItem then
            local item = nil
            for n = 1, #BCPS_PROP_ITEMS do
                local candidate = BCPS_PROP_ITEMS[((i + n - 2) % #BCPS_PROP_ITEMS) + 1]
                item = bcps_inventoryItem(candidate)
                if item then break end
            end
            if item then
                bcps_markProp(item, cp, i)
                local ox = 0.25 + ((i % 4) * 0.12)
                local oy = 0.25 + (((i + 1) % 4) * 0.12)
                local okWorld = pcall(function() square:AddWorldInventoryItem(item, ox, oy, 0) end)
                if okWorld then placed = placed + 1 end
            end
        end
    end
    if placed > 0 then
        cp.physicalPropsPlaced = true
        cp.physicalPropCount = placed
        cp.updatedAt = bcps_now()
        local data = bcps_ensure(gmd)
        if data and data.stats then data.stats.props = (tonumber(data.stats.props) or 0) + placed end
        bcps_updateMarker(gmd, cp)
        TransmitNPCModData()
    end
    return placed
end

local function bcps_placeRoadblockScene(gmd, cp)
    if not (gmd and cp and NPCCheckpointsBridge and NPCCheckpointsBridge.PhysicalPropsEnabled and NPCCheckpointsBridge.PhysicalPropsEnabled()) then return 0 end
    if cp.status == "removed" then return 0 end
    if cp.physicalRoadblockPlaced == true then return 0 end
    local radius = math.max(4, NPCCheckpointsBridge.PhysicalPropRadius and NPCCheckpointsBridge.PhysicalPropRadius() or 4)
    local offsets = {
        {-2, 0, "vehicle"}, {2, 0, "vehicle"},
        {-4, -1, "prop"}, {-3, 1, "prop"}, {3, -1, "prop"}, {4, 1, "prop"},
        {-1, -2, "prop"}, {1, 2, "prop"}, {0, -3, "prop"}, {0, 3, "prop"}
    }
    local placed = 0
    cp.physicalVehicleIds = cp.physicalVehicleIds or {}
    cp.zoneRadius = cp.zoneRadius or (NPCCheckpointsBridge.ZoneRadius and NPCCheckpointsBridge.ZoneRadius()) or NPCCheckpointsBridge.InteractionRadius()
    for i, off in ipairs(offsets) do
        local square = bcps_cellSquare((tonumber(cp.x) or 0) + off[1], (tonumber(cp.y) or 0) + off[2], tonumber(cp.z) or 0)
        if square then
            if off[3] == "vehicle" and NPCCheckpointsBridge.RoadblockVehicleEnabled and NPCCheckpointsBridge.RoadblockVehicleEnabled() then
                local vehicle = bcps_trySpawnRoadblockVehicle(square, i)
                if vehicle then
                    bcps_markRoadblockVehicle(vehicle, cp, i)
                    if vehicle.getId then
                        local okId, id = pcall(function() return vehicle:getId() end)
                        if okId and id ~= nil then cp.physicalVehicleIds[#cp.physicalVehicleIds + 1] = id end
                    end
                    placed = placed + 1
                end
            end
            if off[3] ~= "vehicle" or placed <= 0 then
                local item = nil
                for n = 1, #BCPS_ROADBLOCK_ITEMS do
                    local candidate = BCPS_ROADBLOCK_ITEMS[((i + n - 2) % #BCPS_ROADBLOCK_ITEMS) + 1]
                    item = bcps_inventoryItem(candidate)
                    if item then break end
                end
                if item and square.AddWorldInventoryItem then
                    bcps_markProp(item, cp, i + 100)
                    local ox = 0.20 + ((i % 5) * 0.12)
                    local oy = 0.20 + (((i + 2) % 5) * 0.12)
                    local okWorld, worldItem = pcall(function() return square:AddWorldInventoryItem(item, ox, oy, 0) end)
                    if okWorld then
                        if item.transmitModData then pcall(function() item:transmitModData() end) end
                        if worldItem and worldItem.transmitCompleteItemToClients then pcall(function() worldItem:transmitCompleteItemToClients() end) end
                        placed = placed + 1
                    end
                end
            end
        end
    end
    if placed > 0 then
        cp.physicalRoadblockPlaced = true
        cp.physicalRoadblockCount = placed
        cp.updatedAt = bcps_now()
        bcps_updateMarker(gmd, cp)
        if TransmitNPCModData then TransmitNPCModData() end
    end
    return placed
end

local function bcps_waveForCheckpoint(cp, count)
    count = math.max(1, tonumber(count) or 2)
    local side = bcps_side(cp and (cp.side or cp.checkpointSide)) or "red"
    local aggressive = cp and (cp.status == "alert" or cp.status == "bounty_alert" or cp.breachActive == true)
    return {
        enabled = true,
        enemyBehaviour = aggressive and 2 or 7,
        firstDay = 0,
        lastDay = 99999,
        groupSize = count,
        clanId = side == "green" and 11 or 12,
        hasPistolChance = aggressive and 70 or 45,
        pistolMagCount = aggressive and 3 or 2,
        hasRifleChance = aggressive and 40 or 20,
        rifleMagCount = aggressive and 2 or 1
    }
end


local function bcps_groupExists(gmd, groupId)
    return groupId ~= nil and gmd and type(gmd.VirtualGroups) == "table" and gmd.VirtualGroups[tostring(groupId)] ~= nil
end

local function bcps_groupById(gmd, groupId)
    if not (gmd and groupId and type(gmd.VirtualGroups) == "table") then return nil end
    local group = gmd.VirtualGroups[tostring(groupId)]
    if type(group) == "table" then return group end
    return nil
end

local function bcps_groupIsPhysical(group)
    if type(group) ~= "table" then return false end
    if group.activated == true and group.virtual ~= true then return true end
    if type(group.physicalIds) == "table" and #group.physicalIds > 0 and group.virtual ~= true then return true end
    return false
end

local function bcps_checkpointSlot(cp, index)
    local i = math.max(1, tonumber(index) or 1)
    local offsets = {
        {-1, 0}, {1, 0}, {-2, 1}, {2, -1}, {0, 1}, {0, -1},
        {-3, 0}, {3, 0}, {-1, 2}, {1, -2}
    }
    local off = offsets[((i - 1) % #offsets) + 1]
    return {
        x = (tonumber(cp and cp.x) or 0) + off[1],
        y = (tonumber(cp and cp.y) or 0) + off[2],
        z = tonumber(cp and cp.z) or 0
    }
end

local function bcps_reconcilePhysicalState(gmd, cp)
    if type(cp) ~= "table" then return false end
    local changed = false
    local groupId = cp.physicalGuardGroupId
    if groupId and not bcps_groupExists(gmd, groupId) then
        cp.physicalGuardGroupId = nil
        cp.physicalState = "virtual"
        cp.physicalGuardCount = nil
        cp.physicalReconciledAt = bcps_now()
        return true
    end
    if groupId then
        local group = bcps_groupById(gmd, groupId)
        if group then
            local desiredState = bcps_groupIsPhysical(group) and "materialized" or "virtual"
            if cp.physicalState ~= desiredState then
                cp.physicalState = desiredState
                changed = true
            end
            local desiredCount = tonumber(group.count) or (type(group.members) == "table" and #group.members) or cp.physicalGuardCount
            if desiredCount and cp.physicalGuardCount ~= desiredCount then
                cp.physicalGuardCount = desiredCount
                changed = true
            end
        end
    elseif cp.physicalState == "materialized" or cp.physicalState == "materializing" then
        cp.physicalState = "virtual"
        cp.physicalGuardCount = nil
        changed = true
    end
    if changed then cp.physicalReconciledAt = bcps_now() end
    return changed
end

local function bcps_applyCheckpointMemberFields(member, group, cp, index)
    if type(member) ~= "table" then return member end
    local alert = cp and (cp.status == "alert" or cp.status == "bounty_alert" or cp.breachActive == true)
    local level = alert and 5 or 3
    local anchor = bcps_checkpointSlot(cp, index)
    member.checkpointGuard = true
    member.checkpointPhysical = true
    member.checkpointId = tostring(cp and cp.id or "")
    member.displayTitle = index == 1 and "Checkpoint Sergeant" or "Checkpoint Guard"
    member.nameplateTitle = member.displayTitle
    member.unitLevel = level
    member.unitStars = level >= 5 and 2 or 1
    member.eliteUnit = false
    member.role = index == 1 and "checkpoint_sergeant" or "checkpoint_guard"
    member.tacticalRole = "guard"
    member.program = {name="BaseGuard", stage="Prepare"}
    member.guardPoint = anchor
    member.holdPoint = {x=anchor.x, y=anchor.y, z=anchor.z}
    member.returnPoint = {x=anchor.x, y=anchor.y, z=anchor.z}
    member.checkpointAnchor = {x=anchor.x, y=anchor.y, z=anchor.z}
    member.checkpointZoneRadius = cp and cp.zoneRadius or (NPCCheckpointsBridge.ZoneRadius and NPCCheckpointsBridge.ZoneRadius()) or 26
    member.order = {
        name="Guard",
        source="checkpoint_physical",
        fireMode=alert and "FireAtWill" or "Defensive",
        priority=74,
        sticky=true,
        formation="close",
        followDistance=1.0,
        anchor={x=anchor.x, y=anchor.y, z=anchor.z},
        guardPoint={x=anchor.x, y=anchor.y, z=anchor.z},
        note="Hold faction checkpoint"
    }
    member.factionSide = group.side
    member.faction = group.side
    member.side = group.side
    member.patrolColor = group.side
    member.hostile = alert == true
    member.humanNPC = true
    member.forceHumanAnimation = true
    member.noZombieAnimation = true
    member.defaultWalkType = "Walk"
    member.walkType = "Walk"
    member.preferRoads = true
    member.roadBias = true
    member.preferCover = true
    return member
end

local function bcps_refreshCheckpointGuardOrders(gmd, cp)
    if not (gmd and cp and cp.physicalGuardGroupId) then return false end
    local group = bcps_groupById(gmd, cp.physicalGuardGroupId)
    if type(group) ~= "table" then return false end
    local alert = cp.status == "alert" or cp.status == "bounty_alert" or cp.breachActive == true
    local now = bcps_now()
    if not alert and bcps_groupIsPhysical(group) and tonumber(cp._lastGuardOrderRefreshAt) and now - tonumber(cp._lastGuardOrderRefreshAt) < 0.003 then
        return false
    end
    cp._lastGuardOrderRefreshAt = now
    local changed = false
    local side = bcps_side(cp.side or cp.checkpointSide) or group.side or "red"
    group.checkpointGuardGroup = true
    group.checkpointPhysical = true
    group.checkpointId = tostring(cp.id or "")
    group.checkpointSide = side
    group.side = side
    group.factionSide = side
    group.faction = side
    group.patrolColor = side
    group.hostile = alert == true
    group.targetClass = alert and "player" or "checkpoint"
    if not alert then
        group.x = math.floor(tonumber(cp.x) or group.x or 0)
        group.y = math.floor(tonumber(cp.y) or group.y or 0)
        group.z = tonumber(cp.z) or group.z or 0
        group.preciseX = tonumber(cp.x) or group.x
        group.preciseY = tonumber(cp.y) or group.y
        group.targetX = cp.x
        group.targetY = cp.y
        group.targetZ = cp.z or 0
        group.routeX = cp.x
        group.routeY = cp.y
        group.routeZ = cp.z or 0
        group.program = {name="BaseGuard", stage="Checkpoint"}
        group.state = bcps_groupIsPhysical(group) and "physical" or "checkpoint_guard"
        group.checkpointAnchorMaterialize = true
        group.checkpointSpawnRadius = 7
    end
    for i, member in ipairs(group.members or {}) do
        if type(member) == "table" then
            bcps_applyCheckpointMemberFields(member, group, cp, i)
            changed = true
        end
    end
    if type(gmd.Queue) == "table" then
        for runtimeId, brain in pairs(gmd.Queue) do
            if type(brain) == "table" and tostring(brain.worldGroupId or brain.groupId or "") == tostring(group.id or cp.physicalGuardGroupId) then
                local idx = tonumber(brain.memberIndex) or 1
                local anchor = bcps_checkpointSlot(cp, idx)
                brain.checkpointGuard = true
                brain.checkpointPhysical = true
                brain.checkpointId = tostring(cp.id or "")
                brain.checkpointZoneRadius = cp.zoneRadius or brain.checkpointZoneRadius
                brain.guardPoint = {x=anchor.x, y=anchor.y, z=anchor.z}
                brain.holdPoint = {x=anchor.x, y=anchor.y, z=anchor.z}
                brain.returnPoint = {x=anchor.x, y=anchor.y, z=anchor.z}
                brain.order = brain.order or {}
                brain.order.name = "Guard"
                brain.order.source = "checkpoint_physical"
                brain.order.fireMode = alert and "FireAtWill" or "Defensive"
                brain.order.priority = alert and 96 or 74
                brain.order.sticky = true
                brain.order.formation = "close"
                brain.order.followDistance = 1.0
                brain.order.anchor = {x=anchor.x, y=anchor.y, z=anchor.z}
                brain.order.guardPoint = {x=anchor.x, y=anchor.y, z=anchor.z}
                if not alert then
                    brain.hostile = false
                    brain.program = {name="BaseGuard", stage=(brain.program and brain.program.stage) or "Prepare"}
                    brain.humanNPC = true
                    brain.forceHumanAnimation = true
                    brain.noZombieAnimation = true
                    brain.defaultWalkType = brain.defaultWalkType or "Walk"
                    brain.walkType = brain.walkType or "Walk"
                    local bx = tonumber(brain.x) or tonumber(brain.bornCoords and brain.bornCoords.x)
                    local by = tonumber(brain.y) or tonumber(brain.bornCoords and brain.bornCoords.y)
                    if bx and by and NPCCheckpointsBridge.Distance(bx, by, cp.x, cp.y) > ((tonumber(cp.zoneRadius) or 26) + 6) then
                        brain.tasks = {{action="Move", time=120, endurance=0.01, x=anchor.x, y=anchor.y, z=anchor.z, walkType="Run", closeSlow=false, checkpointReturn=true}}
                    end
                end
                gmd.Queue[runtimeId] = brain
                changed = true
            end
        end
    end
    group.updatedAt = bcps_now()
    gmd.VirtualGroups[tostring(group.id or cp.physicalGuardGroupId)] = group
    return changed
end

local function bcps_spawnPhysicalGuardGroup(gmd, cp, player)
    if not (gmd and cp and player and NPCCheckpointsBridge and NPCCheckpointsBridge.IsPhysicalEnabled and NPCCheckpointsBridge.IsPhysicalEnabled()) then return false end
    bcps_reconcilePhysicalState(gmd, cp)
    if bcps_groupExists(gmd, cp.physicalGuardGroupId) then return false end
    if cp.physicalState == "materialized" then return false end
    local director = bcps_worldDirector()
    if not director then return false end
    if not (NPCWorldDirectorBridge and NPCWorldDirectorBridge.PrepareVirtualMember) then return false end

    local minCount, maxCount = 2, 5
    if NPCCheckpointsBridge.PhysicalGuardRange then
        local okRange, gotMin, gotMax = pcall(function() return NPCCheckpointsBridge.PhysicalGuardRange() end)
        if okRange then
            minCount = tonumber(gotMin) or minCount
            maxCount = tonumber(gotMax) or maxCount
        end
    end
    if maxCount < minCount then maxCount = minCount end
    local span = math.max(0, maxCount - minCount)
    local count = minCount + (span > 0 and ZombRand(span + 1) or 0)
    if NPCWorldDirectorBridge.ClampGroupSize then count = NPCWorldDirectorBridge.ClampGroupSize(count, 1, 10) end
    if count <= 0 then return false end

    local side = bcps_side(cp.side or cp.checkpointSide) or "red"
    local groupId = "CPG" .. tostring(cp.id or tostring(ZombRand(999999)))
    local wave = bcps_waveForCheckpoint(cp, count)
    local group = {
        id = groupId,
        x = math.floor(tonumber(cp.x) or 0),
        y = math.floor(tonumber(cp.y) or 0),
        z = tonumber(cp.z) or 0,
        preciseX = tonumber(cp.x) or 0,
        preciseY = tonumber(cp.y) or 0,
        clanId = wave.clanId,
        count = count,
        hostile = cp.status == "alert" or cp.status == "bounty_alert" or cp.breachActive == true,
        program = {name="BaseGuard", stage="Checkpoint"},
        members = {},
        virtual = true,
        activated = false,
        createdAt = bcps_now(),
        updatedAt = bcps_now(),
        state = "checkpoint_guard",
        spawnClass = "checkpoint_guard",
        targetX = cp.x,
        targetY = cp.y,
        targetZ = cp.z or 0,
        routeX = cp.x,
        routeY = cp.y,
        routeZ = cp.z or 0,
        targetClass = "checkpoint",
        speed = 60,
        roadBias = true,
        preferRoads = true,
        patrolColor = side,
        factionSide = side,
        faction = side,
        side = side,
        checkpointGuardGroup = true,
        checkpointPhysical = true,
        checkpointAnchorMaterialize = true,
        checkpointSpawnRadius = 7,
        checkpointId = tostring(cp.id or ""),
        checkpointSide = side,
        displayTitle = "Checkpoint Guard",
        name = "Checkpoint guard team"
    }
    for i = 1, count do
        local member = nil
        local okMember, gotMember = pcall(function()
            return NPCWorldDirectorBridge.PrepareVirtualMember(director, gmd, wave, groupId, i, side, false)
        end)
        if okMember then member = gotMember end
        if type(member) ~= "table" then member = {} end
        if NPCIdentityBridge and NPCIdentityBridge.NewUID then
            member.uid = member.uid or NPCIdentityBridge.NewUID(gmd)
            member.persistentId = member.persistentId or member.uid
        end
        member.worldGroupId = groupId
        member.groupId = groupId
        member.memberIndex = i
        bcps_applyCheckpointMemberFields(member, group, cp, i)
        group.members[#group.members + 1] = member
    end
    group.count = #group.members
    if group.count <= 0 then return false end

    gmd.VirtualGroups = gmd.VirtualGroups or {}
    gmd.VirtualGroups[groupId] = group
    cp.physicalGuardGroupId = groupId
    cp.physicalState = "materializing"
    cp.physicalGuardCount = group.count
    cp.physicalMaterializedAt = bcps_now()
    bcps_refreshCheckpointGuardOrders(gmd, cp)

    if NPCPersistentNPCBridge and NPCPersistentNPCBridge.RegisterGroup then pcall(function() NPCPersistentNPCBridge.RegisterGroup(gmd, group) end) end
    local ok = false
    if director.MaterializeGroup then
        local safe, result = pcall(function() return director.MaterializeGroup(group, player) end)
        ok = safe and result == true
    elseif NPCWorldDirectorBridge.MaterializeGroup then
        local safe, result = pcall(function() return NPCWorldDirectorBridge.MaterializeGroup(director, group, player) end)
        ok = safe and result == true
    end
    if ok then
        cp.physicalState = "materialized"
        cp.physicalLastSeenAt = bcps_now()
        local data = bcps_ensure(gmd)
        if data and data.stats then data.stats.physical = (tonumber(data.stats.physical) or 0) + 1 end
        if NPCDiagnosticsBridge and NPCDiagnosticsBridge.LogRiskAction then
            NPCDiagnosticsBridge.LogRiskAction("checkpoints", "physical_materialized", {checkpointId=cp.id, groupId=groupId, side=cp.side or cp.owner, x=cp.x, y=cp.y, guards=group.count}, "checkpoint-materialized:" .. tostring(cp.id), true)
        end
        bcps_updateMarker(gmd, cp)
        bcps_halo(player, "Checkpoint guards spotted ahead.", 180, 230, 255)
        TransmitNPCModData()
        return true
    end
    cp.physicalState = "virtual"
    return false
end

local function bcps_materializeExistingCheckpointGroup(gmd, cp, player)
    if not (gmd and cp and player and cp.physicalGuardGroupId) then return false end
    local group = bcps_groupById(gmd, cp.physicalGuardGroupId)
    if type(group) ~= "table" then return false end
    if bcps_groupIsPhysical(group) then
        bcps_refreshCheckpointGuardOrders(gmd, cp)
        return false
    end
    local director = bcps_worldDirector()
    if not director then return false end
    if NPCPersistentNPCBridge and NPCPersistentNPCBridge.RestoreGroupMembers then
        pcall(function() NPCPersistentNPCBridge.RestoreGroupMembers(gmd, group) end)
    end
    if type(group.members) ~= "table" or #group.members <= 0 then return false end
    group.count = #group.members
    group.activated = false
    group.virtual = true
    group.physicalIds = nil
    group.spawnFailed = false
    group.spawnPending = false
    group.spawnQueued = 0
    group.retryAfter = nil
    group.lastSpawnFailReason = nil
    group.checkpointAnchorMaterialize = true
    group.checkpointSpawnRadius = 7
    group.x = math.floor(tonumber(cp.x) or group.x or 0)
    group.y = math.floor(tonumber(cp.y) or group.y or 0)
    group.z = tonumber(cp.z) or group.z or 0
    group.preciseX = tonumber(cp.x) or group.x
    group.preciseY = tonumber(cp.y) or group.y
    group.state = "checkpoint_guard"
    gmd.VirtualGroups[tostring(group.id or cp.physicalGuardGroupId)] = group
    bcps_refreshCheckpointGuardOrders(gmd, cp)
    cp.physicalState = "materializing"
    cp.physicalGuardCount = group.count
    cp.physicalMaterializedAt = bcps_now()
    local ok = false
    if director.MaterializeGroup then
        local safe, result = pcall(function() return director.MaterializeGroup(group, player) end)
        ok = safe and result == true
    elseif NPCWorldDirectorBridge.MaterializeGroup then
        local safe, result = pcall(function() return NPCWorldDirectorBridge.MaterializeGroup(director, group, player) end)
        ok = safe and result == true
    end
    if ok then
        cp.physicalState = "materialized"
        cp.physicalLastSeenAt = bcps_now()
        cp.updatedAt = bcps_now()
        bcps_updateMarker(gmd, cp)
        if TransmitNPCModData then TransmitNPCModData() end
        return true
    end
    cp.physicalState = "virtual"
    cp.updatedAt = bcps_now()
    return false
end

local function bcps_materializeNearbyCheckpoints(gmd)
    if not (gmd and NPCCheckpointsBridge and NPCCheckpointsBridge.IsPhysicalEnabled and NPCCheckpointsBridge.IsPhysicalEnabled()) then return 0 end
    local data = bcps_ensure(gmd)
    if not data then return 0 end
    local radius = NPCCheckpointsBridge.PhysicalSpawnDistance and NPCCheckpointsBridge.PhysicalSpawnDistance() or 92
    local maxPerTick = NPCCheckpointsBridge.PhysicalMaxMaterializePerTick and NPCCheckpointsBridge.PhysicalMaxMaterializePerTick() or 1
    maxPerTick = math.floor(tonumber(maxPerTick) or 0)
    if maxPerTick <= 0 then return 0 end
    local made = 0
    local reconciled = 0
    for _, cp in pairs(data.active or {}) do
        if type(cp) == "table" and bcps_reconcilePhysicalState(gmd, cp) then reconciled = reconciled + 1 end
        if made >= maxPerTick then break end
        if type(cp) == "table" and cp.status ~= "removed" and cp.x and cp.y then
            for _, player in ipairs(bcps_players()) do
                if player and player.getX and player.getY and NPCCheckpointsBridge.Distance(player:getX(), player:getY(), cp.x, cp.y) <= radius then
                    bcps_placeRoadblockScene(gmd, cp)
                    bcps_placePhysicalProps(gmd, cp)
                    if cp.physicalGuardGroupId then
                        if bcps_materializeExistingCheckpointGroup(gmd, cp, player) then
                            made = made + 1
                        else
                            bcps_refreshCheckpointGuardOrders(gmd, cp)
                        end
                    elseif bcps_spawnPhysicalGuardGroup(gmd, cp, player) then
                        made = made + 1
                    end
                    break
                end
            end
        end
    end
    return made + reconciled
end


local function bcps_updateGroupPursuit(gmd, cp, player)
    if not (gmd and cp and player and player.getX and player.getY) then return false end
    local group = cp.physicalGuardGroupId and gmd.VirtualGroups and gmd.VirtualGroups[tostring(cp.physicalGuardGroupId)] or nil
    if type(group) ~= "table" then return false end
    local px, py, pz = tonumber(player:getX()) or cp.x, tonumber(player:getY()) or cp.y, player.getZ and tonumber(player:getZ()) or tonumber(cp.z) or 0
    group.hostile = true
    group.breachPursuit = true
    group.checkpointBreachPursuit = true
    group.targetClass = "player"
    group.targetPlayerId = bcps_playerKey(player)
    group.targetPlayerName = bcps_playerName(player)
    group.targetX = px
    group.targetY = py
    group.targetZ = pz
    group.routeX = px
    group.routeY = py
    group.routeZ = pz
    group.updatedAt = bcps_now()
    for i, member in ipairs(group.members or {}) do
        if type(member) == "table" then
            member.hostile = true
            member.enemyBehaviour = 2
            member.fireMode = "FireAtWill"
            member.targetClass = "player"
            member.targetPlayerId = group.targetPlayerId
            member.targetPlayerName = group.targetPlayerName
            member.order = member.order or {}
            member.order.name = "HuntPlayer"
            member.order.source = "checkpoint_breach"
            member.order.fireMode = "FireAtWill"
            member.order.priority = 96
            member.order.sticky = true
            member.order.target = {x=px, y=py, z=pz, player=group.targetPlayerName}
            member.program = {name="Raider", stage="CheckpointBreach"}
        end
    end
    return true
end

local function bcps_triggerBreach(gmd, data, cp, player)
    if not (gmd and data and cp and player) then return false end
    cp.status = "alert"
    cp.breachActive = true
    cp.breachPlayerId = bcps_playerKey(player)
    cp.breachPlayerName = bcps_playerName(player)
    cp.lastForcedAt = bcps_now()
    cp.updatedAt = bcps_now()
    data.stats.forced = (tonumber(data.stats.forced) or 0) + 1
    bcps_placeRoadblockScene(gmd, cp)
    bcps_placePhysicalProps(gmd, cp)
    if NPCCheckpointsBridge.IsPhysicalEnabled and NPCCheckpointsBridge.IsPhysicalEnabled() then
        if cp.physicalGuardGroupId then
            bcps_materializeExistingCheckpointGroup(gmd, cp, player)
        else
            bcps_spawnPhysicalGuardGroup(gmd, cp, player)
        end
    end
    bcps_updateGroupPursuit(gmd, cp, player)
    bcps_updateMarker(gmd, cp)
    bcps_halo(player, "Checkpoint breach! Guards are pursuing you.", 255, 70, 50)
    if NPCDisguiseBridge and NPCDisguiseBridge.Compromise then pcall(function() NPCDisguiseBridge.Compromise(player, "checkpoint_breach", cp.side, true) end) end
    if NPCWorldRulesServer and NPCWorldRulesServer.SyncAfterConsequence then NPCWorldRulesServer.SyncAfterConsequence(player, "checkpoint_breach", {side=cp.side}) end
    if TransmitNPCModData then TransmitNPCModData() end
    return true
end

local function bcps_groupAliveCount(gmd, groupId)
    if not (gmd and groupId and gmd.VirtualGroups) then return 0 end
    local group = gmd.VirtualGroups[tostring(groupId)]
    if type(group) ~= "table" then return 0 end
    local alive = 0
    for _, member in ipairs(group.members or {}) do
        if type(member) == "table" and member.dead ~= true and (tonumber(member.health) or 1) > 0 then alive = alive + 1 end
    end
    if alive <= 0 and (tonumber(group.count) or 0) > 0 and type(group.members) ~= "table" then alive = tonumber(group.count) or 0 end
    return alive
end


local function bcps_relocateCheckpoint(gmd, cp, reason)
    if not (gmd and cp and cp.id) then return false end
    if cp.breachActive == true then return false end
    if bcps_isCheckpointLifetimePaused(cp) then return false end
    local point = bcps_findStrategicCheckpointPoint(gmd, cp.x, cp.y, tostring(cp.id)) or bcps_findStrategicCheckpointPoint(gmd, nil, nil, tostring(cp.id))
    if not (point and point.x and point.y) then return false end

    bcps_removeMarkedWorldObjects(gmd, cp)
    for _, id in ipairs(cp.physicalVehicleIds or {}) do
        local vehicle = bcps_findVehicleById(id)
        if vehicle then bcps_removeVehicle(vehicle) end
    end
    if cp.physicalGuardGroupId and gmd.VirtualGroups then
        gmd.VirtualGroups[tostring(cp.physicalGuardGroupId)] = nil
    end
    bcps_removeMarker(gmd, cp)

    cp.x = math.floor(tonumber(point.x) or tonumber(cp.x) or 0)
    cp.y = math.floor(tonumber(point.y) or tonumber(cp.y) or 0)
    cp.z = tonumber(point.z) or tonumber(cp.z) or 0
    cp.source = tostring(reason or "relocated")
    cp.strategic = true
    cp.strategicScore = point.strategicScore or point.zoneScore
    cp.strategicMeta = point.strategicMeta
    cp.status = "active"
    cp.breachActive = false
    cp.breachPlayerId = nil
    cp.breachPlayerName = nil
    cp.physicalGuardGroupId = nil
    cp.physicalGuardCount = 0
    cp.physicalState = "virtual"
    cp.physicalRoadblockPlaced = false
    cp.physicalPropsPlaced = false
    cp.physicalVehicleIds = nil
    cp.physicalRoadblockCount = 0
    cp.physicalPropCount = 0
    cp.lifetimeStartedAt = bcps_now()
    cp.lifetimePausedHours = 0
    cp.lifetimePauseStartedAt = nil
    cp.effectiveAgeHours = 0
    cp.relocatedAt = bcps_now()
    cp.updatedAt = bcps_now()

    local data = bcps_ensure(gmd)
    if data and data.stats then data.stats.relocated = (tonumber(data.stats.relocated) or 0) + 1 end
    bcps_updateMarker(gmd, cp)
    return true
end

local function bcps_updateCheckpointLifetimes(gmd)
    local data = bcps_ensure(gmd)
    if not data then return 0 end
    local changed = 0
    local now = bcps_now()
    for _, cp in pairs(data.active or {}) do
        if type(cp) == "table" and cp.status ~= "removed" and cp.x and cp.y then
            cp.lifetimeHours = tonumber(cp.lifetimeHours) or (NPCCheckpointsBridge.LifetimeHours and NPCCheckpointsBridge.LifetimeHours()) or 24
            cp.lifetimeStartedAt = tonumber(cp.lifetimeStartedAt or cp.createdAt) or now
            cp.lifetimePausedHours = tonumber(cp.lifetimePausedHours) or 0
            local paused = bcps_isCheckpointLifetimePaused(cp)
            if paused then
                cp.lifetimePauseStartedAt = tonumber(cp.lifetimePauseStartedAt) or now
                cp.lifetimePaused = true
                cp.updatedAt = now
            else
                if cp.lifetimePauseStartedAt then
                    cp.lifetimePausedHours = cp.lifetimePausedHours + math.max(0, now - tonumber(cp.lifetimePauseStartedAt))
                    cp.lifetimePauseStartedAt = nil
                    cp.updatedAt = now
                end
                cp.lifetimePaused = false
            end
            cp.effectiveAgeHours = math.max(0, now - cp.lifetimeStartedAt - cp.lifetimePausedHours)
            local invalidStrategic = false
            if cp.strategic ~= true then invalidStrategic = true end
            if not invalidStrategic then
                local director = bcps_worldDirector()
                invalidStrategic = bcps_strategicRoadScore(director, cp.x, cp.y, cp.z) == nil
            end
            if not paused and cp.breachActive ~= true and (cp.effectiveAgeHours >= cp.lifetimeHours or invalidStrategic) then
                if bcps_relocateCheckpoint(gmd, cp, invalidStrategic and "relocated_invalid_checkpoint_position" or "relocated_lifetime_expired") then
                    changed = changed + 1
                end
            end
        end
    end
    return changed
end

local function bcps_updateZoneBreachState(gmd)
    local data = bcps_ensure(gmd)
    if not data then return 0 end
    data.zonePlayers = data.zonePlayers or {}
    local changed = 0
    local zoneRadius = NPCCheckpointsBridge.ZoneRadius and NPCCheckpointsBridge.ZoneRadius() or NPCCheckpointsBridge.InteractionRadius()
    local forgiveness = NPCCheckpointsBridge.BreachForgivenessRadius and NPCCheckpointsBridge.BreachForgivenessRadius() or 6
    for _, player in ipairs(bcps_players()) do
        local pkey = bcps_playerKey(player)
        if pkey and player and player.getX and player.getY then
            data.zonePlayers[pkey] = data.zonePlayers[pkey] or {}
            local px, py = player:getX(), player:getY()
            for _, cp in pairs(data.active or {}) do
                if type(cp) == "table" and cp.status ~= "removed" and cp.x and cp.y then
                    cp.zoneRadius = cp.zoneRadius or zoneRadius
                    local d = NPCCheckpointsBridge.Distance(px, py, cp.x, cp.y)
                    local wasInside = data.zonePlayers[pkey][tostring(cp.id)] == true
                    local hasPass = NPCCheckpointsBridge.GetPlayerPass(gmd, player, cp) ~= nil
                    if d <= cp.zoneRadius then
                        data.zonePlayers[pkey][tostring(cp.id)] = true
                        if not cp.physicalRoadblockPlaced then changed = changed + bcps_placeRoadblockScene(gmd, cp) end
                    elseif wasInside then
                        data.zonePlayers[pkey][tostring(cp.id)] = nil
                        if not hasPass and d <= (cp.zoneRadius + forgiveness + 18) and cp.breachActive ~= true then
                            if bcps_triggerBreach(gmd, data, cp, player) then changed = changed + 1 end
                        end
                    end
                    if cp.breachActive == true then
                        if player and (cp.breachPlayerId == pkey or not cp.breachPlayerId) then
                            bcps_updateGroupPursuit(gmd, cp, player)
                        end
                        if cp.physicalGuardGroupId and bcps_groupAliveCount(gmd, cp.physicalGuardGroupId) <= 0 then
                            if bcps_removePhysicalCheckpoint(gmd, cp, "guards_eliminated") then changed = changed + 1 end
                        end
                    elseif cp.physicalGuardGroupId then
                        if bcps_refreshCheckpointGuardOrders(gmd, cp) then changed = changed + 1 end
                    end
                end
            end
        end
    end
    return changed
end

local function bcps_groupSide(group)
    if not group then return nil end
    return bcps_side(group.factionSide or group.faction or group.side or group.patrolColor)
end

local function bcps_createFromRoadPatrols(gmd, data)
    if not (gmd and data and gmd.VirtualGroups and NPCCheckpointsBridge) then return 0 end
    local created = 0
    for gid, group in pairs(gmd.VirtualGroups) do
        local gx = group and tonumber(group.x) or nil
        local gy = group and tonumber(group.y) or nil
        if group and group.roadPatrol and gx and gy and not group.checkpointId then
            local side = bcps_groupSide(group)
            if side == "red" or side == "green" then
                local point = bcps_findStrategicCheckpointPoint(gmd, gx, gy, nil)
                if point and point.x and point.y then
                    local cp = NPCCheckpointsBridge.MakeCheckpoint(gmd, point.x, point.y, point.z or 0, side, {source="strategic_road_patrol", sourceId=gid, strategic=true, strategicScore=point.strategicScore or point.zoneScore})
                    if cp then
                        cp.strategic = true
                        cp.strategicScore = point.strategicScore or point.zoneScore
                        cp.strategicMeta = point.strategicMeta
                        group.checkpointId = cp.id
                        group.checkpointGuard = true
                        gmd.VirtualGroups[gid] = group
                        bcps_updateMarker(gmd, cp)
                        created = created + 1
                        if created >= 2 then break end
                    end
                end
            end
        end
    end
    return created
end

local function bcps_createFallback(gmd, data)
    if not (NPCCheckpointsBridge and NPCCheckpointsBridge.MakeCheckpoint) then return nil end
    local point = bcps_findStrategicCheckpointPoint(gmd, nil, nil, nil)
    if point and point.x and point.y then
        local side = (ZombRand and ZombRand(2) == 0) and "red" or "green"
        local cp = NPCCheckpointsBridge.MakeCheckpoint(gmd, point.x, point.y, point.z or 0, side, {source="strategic_road", strategic=true, strategicScore=point.strategicScore or point.zoneScore})
        if cp then
            cp.strategic = true
            cp.strategicScore = point.strategicScore or point.zoneScore
            cp.strategicMeta = point.strategicMeta
            bcps_updateMarker(gmd, cp)
        end
        return cp
    end
    return nil
end

function NPCCheckpointsServerBridge.EnsureCheckpoints(force)
    if not (NPCCheckpointsBridge and NPCCheckpointsBridge.IsEnabled and NPCCheckpointsBridge.IsEnabled()) then return 0 end
    local gmd = GetNPCModData()
    local data = bcps_ensure(gmd)
    if not data then return 0 end
    local maxActive = NPCCheckpointsBridge.MaxActive()
    if maxActive <= 0 then return 0 end

    local activeCount = 0
    for _, cp in pairs(data.active or {}) do
        if cp and cp.status ~= "removed" then activeCount = activeCount + 1 end
    end
    if activeCount >= maxActive and not force then return 0 end

    local created = 0
    while activeCount + created < maxActive do
        local made = bcps_createFromRoadPatrols(gmd, data)
        if made <= 0 then
            local cp = bcps_createFallback(gmd, data)
            if cp then made = 1 end
        end
        if made <= 0 then break end
        created = created + made
        if not force and created >= 2 then break end
    end
    if created > 0 then TransmitNPCModData() end
    return created
end

local function bcps_textFor(cp, player)
    if NPCWorldRules and NPCWorldRules.CheckpointStatusText then
        local ok, text = pcall(function() return NPCWorldRules.CheckpointStatusText(GetNPCModData(), player, cp) end)
        if ok and text then return text end
    end
    if not cp then return "Checkpoint" end
    local sideLabel = NPCCheckpointsBridge.GetSideLabel(cp.side or cp.checkpointSide)
    return tostring(sideLabel) .. " checkpoint asks for " .. tostring(cp.tollAmount or 0) .. " " .. tostring(cp.tollLabel or cp.tollResource or "supplies")
end

local function bcps_bountyBlocks(player, cp)
    if not (player and cp and NPCBountyBridge and NPCBountyBridge.IsWantedByFaction) then return false end
    local gmd = GetNPCModData()
    local side = bcps_side(cp.side or cp.checkpointSide)
    if not side then return false end
    return NPCBountyBridge.IsWantedByFaction(gmd, player, side, NPCBountyBridge.CheckpointBlocksAt and NPCBountyBridge.CheckpointBlocksAt() or nil)
end

local function bcps_canPassAsFaction(player, cp)
    if not (player and cp) then return false, "none" end
    local playerSide = bcps_playerSide(player)
    local cpSide = bcps_side(cp.side or cp.checkpointSide)
    if cpSide and playerSide == cpSide then return true, "faction" end
    if NPCDisguiseBridge and NPCDisguiseBridge.CanPassAsSide and NPCDisguiseBridge.CanPassAsSide(player, cpSide) then
        if NPCDisguiseBridge.RollInspection and not NPCDisguiseBridge.RollInspection(player, cpSide) then
            return false, "disguise_failed"
        end
        return true, "disguise"
    end
    return false, "hostile"
end

local function bcps_interact(player, args)
    if not (NPCCheckpointsBridge and NPCCheckpointsBridge.IsEnabled and NPCCheckpointsBridge.IsEnabled()) then return end
    local gmd = GetNPCModData()
    local data = bcps_ensure(gmd)
    if not data then return end

    local cp = NPCCheckpointsBridge.FindCheckpoint(gmd, args and (args.checkpointId or args.id) or nil)
    if not cp then
        bcps_halo(player, "No checkpoint found.", 255, 120, 80)
        return
    end
    if player and player.getX and NPCCheckpointsBridge.Distance(player:getX(), player:getY(), cp.x, cp.y) > NPCCheckpointsBridge.InteractionRadius() + 8 then
        bcps_halo(player, "Move closer to the checkpoint.", 255, 180, 80)
        return
    end

    local action = tostring(args and args.action or "request")
    local ruleDecision = NPCWorldRules and NPCWorldRules.DecideCheckpoint and NPCWorldRules.DecideCheckpoint(gmd, player, cp, action) or nil
    if ruleDecision and ruleDecision.reason == "bounty" and action ~= "force" then
        cp.status = "bounty_alert"
        cp.updatedAt = bcps_now()
        data.stats.denied = (tonumber(data.stats.denied) or 0) + 1
        bcps_updateMarker(gmd, cp)
        if NPCDisguiseBridge and NPCDisguiseBridge.Compromise then pcall(function() NPCDisguiseBridge.Compromise(player, "bounty_checkpoint", cp.side, true) end) end
        bcps_halo(player, ruleDecision.text or "Checkpoint recognizes your bounty. Passage denied.", 255, 70, 50)
        if NPCWorldRulesServer and NPCWorldRulesServer.SyncAfterConsequence then NPCWorldRulesServer.SyncAfterConsequence(player, "checkpoint_bounty_block", {side=cp.side}) end
        TransmitNPCModData()
        return
    elseif action ~= "force" and not ruleDecision and bcps_bountyBlocks(player, cp) then
        cp.status = "bounty_alert"
        cp.updatedAt = bcps_now()
        data.stats.denied = (tonumber(data.stats.denied) or 0) + 1
        bcps_updateMarker(gmd, cp)
        if NPCDisguiseBridge and NPCDisguiseBridge.Compromise then pcall(function() NPCDisguiseBridge.Compromise(player, "bounty_checkpoint", cp.side, true) end) end
        bcps_halo(player, "Checkpoint recognizes your bounty. Passage denied.", 255, 70, 50)
        TransmitNPCModData()
        return
    end

    if NPCCheckpointsBridge.GetPlayerPass(gmd, player, cp) then
        bcps_halo(player, "Checkpoint pass is still valid.", 120, 255, 120)
        return
    end

    if action == "status" then
        bcps_halo(player, bcps_textFor(cp, player), 180, 230, 255)
        return
    elseif action == "document" then
        if NPCFactionDocsBridge and NPCFactionDocsBridge.UseDocumentAtCheckpoint then
            local ok, reason, doc = NPCFactionDocsBridge.UseDocumentAtCheckpoint(gmd, player, cp)
            if ok then
                NPCCheckpointsBridge.GrantPlayerPass(gmd, player, cp, "document")
                cp.status = "document_passed"
                cp.updatedAt = bcps_now()
                bcps_updateMarker(gmd, cp)
                bcps_halo(player, "Documents accepted. You may pass.", 120, 255, 120)
                if NPCWorldRulesServer and NPCWorldRulesServer.SyncAfterConsequence then NPCWorldRulesServer.SyncAfterConsequence(player, "checkpoint_document_pass", {side=cp.side}) end
                TransmitNPCModData()
                return
            end
            if reason == "document_failed" then
                cp.status = "alert"
                cp.updatedAt = bcps_now()
                data.stats.denied = (tonumber(data.stats.denied) or 0) + 1
                bcps_updateMarker(gmd, cp)
                if NPCDisguiseBridge and NPCDisguiseBridge.Compromise then pcall(function() NPCDisguiseBridge.Compromise(player, "bad_documents", cp.side, true) end) end
                bcps_halo(player, "Documents failed inspection. Checkpoint is alerted.", 255, 80, 60)
                if NPCWorldRulesServer and NPCWorldRulesServer.SyncAfterConsequence then NPCWorldRulesServer.SyncAfterConsequence(player, "checkpoint_document_failed", {side=cp.side}) end
                TransmitNPCModData()
                return
            end
        end
        bcps_halo(player, "No valid documents for this checkpoint.", 255, 180, 80)
        return
    elseif action == "password" then
        if NPCFactionDocsBridge and NPCFactionDocsBridge.UsePasswordAtCheckpoint then
            local ok, reason = NPCFactionDocsBridge.UsePasswordAtCheckpoint(gmd, player, cp)
            if ok then
                NPCCheckpointsBridge.GrantPlayerPass(gmd, player, cp, "password")
                cp.status = "password_passed"
                cp.updatedAt = bcps_now()
                bcps_updateMarker(gmd, cp)
                bcps_halo(player, "Password accepted. You may pass.", 120, 255, 120)
                if NPCWorldRulesServer and NPCWorldRulesServer.SyncAfterConsequence then NPCWorldRulesServer.SyncAfterConsequence(player, "checkpoint_password_pass", {side=cp.side}) end
                TransmitNPCModData()
                return
            end
            if reason == "wrong_password" then
                bcps_halo(player, "Password is outdated or wrong.", 255, 180, 80)
                return
            end
        end
        bcps_halo(player, "You do not know this checkpoint password.", 255, 180, 80)
        return
    elseif action == "pay" then
        if NPCCheckpointsBridge.TakePayment(player, cp.tollResource, cp.tollAmount) then
            NPCCheckpointsBridge.GrantPlayerPass(gmd, player, cp, "toll")
            data.stats.tolled = (tonumber(data.stats.tolled) or 0) + 1
            cp.status = "paid"
            cp.updatedAt = bcps_now()
            bcps_updateMarker(gmd, cp)
            bcps_halo(player, "Toll paid. You may pass.", 120, 255, 120)
            bcps_say(player, "Checkpoint paid.")
            if NPCWorldRulesServer and NPCWorldRulesServer.SyncAfterConsequence then NPCWorldRulesServer.SyncAfterConsequence(player, "checkpoint_toll_paid", {side=cp.side}) end
            TransmitNPCModData()
            return
        end
        bcps_halo(player, "Need toll: " .. tostring(cp.tollAmount or 0) .. " " .. tostring(cp.tollLabel or cp.tollResource or "supplies") .. ".", 255, 180, 80)
        return
    elseif action == "bluff" or action == "request" then
        local decision = ruleDecision or (NPCWorldRules and NPCWorldRules.DecideCheckpoint and NPCWorldRules.DecideCheckpoint(gmd, player, cp, action))
        local ok, reason = nil, nil
        if decision then
            ok = decision.allow == true
            reason = decision.reason
        else
            ok, reason = bcps_canPassAsFaction(player, cp)
        end
        if ok then
            NPCCheckpointsBridge.GrantPlayerPass(gmd, player, cp, reason)
            cp.status = reason == "disguise" and "disguise_passed" or "passed"
            cp.updatedAt = bcps_now()
            bcps_updateMarker(gmd, cp)
            bcps_halo(player, (decision and decision.text) or (reason == "disguise" and "Disguise worked. Checkpoint lets you through." or "Checkpoint recognizes you. You may pass."), 120, 255, 120)
            if NPCWorldRulesServer and NPCWorldRulesServer.SyncAfterConsequence then NPCWorldRulesServer.SyncAfterConsequence(player, "checkpoint_pass", {side=cp.side, reason=reason}) end
            TransmitNPCModData()
            return
        end
        if reason == "disguise_failed" then
            cp.status = "alert"
            cp.updatedAt = bcps_now()
            data.stats.denied = (tonumber(data.stats.denied) or 0) + 1
            bcps_updateMarker(gmd, cp)
            bcps_halo(player, (decision and decision.text) or "Inspection failed. Your disguise is compromised.", 255, 80, 60)
            if NPCWorldRulesServer and NPCWorldRulesServer.SyncAfterConsequence then NPCWorldRulesServer.SyncAfterConsequence(player, "checkpoint_disguise_failed", {side=cp.side}) end
            TransmitNPCModData()
            return
        end
        bcps_halo(player, (decision and decision.text) or "Checkpoint blocks the road. Pay toll or leave.", 255, 180, 80)
        return
    elseif action == "force" then
        cp.status = "alert"
        cp.breachActive = true
        cp.breachPlayerId = bcps_playerKey(player)
        cp.breachPlayerName = bcps_playerName(player)
        cp.lastForcedAt = bcps_now()
        cp.updatedAt = bcps_now()
        data.stats.forced = (tonumber(data.stats.forced) or 0) + 1
        if NPCDisguiseBridge and NPCDisguiseBridge.Compromise then pcall(function() NPCDisguiseBridge.Compromise(player, "forced_checkpoint", cp.side, true) end) end
        bcps_updateMarker(gmd, cp)
        bcps_placeRoadblockScene(gmd, cp)
        bcps_placePhysicalProps(gmd, cp)
        if NPCCheckpointsBridge.IsPhysicalEnabled and NPCCheckpointsBridge.IsPhysicalEnabled() then
            if cp.physicalGuardGroupId then
                bcps_materializeExistingCheckpointGroup(gmd, cp, player)
            else
                bcps_spawnPhysicalGuardGroup(gmd, cp, player)
            end
        end
        bcps_updateGroupPursuit(gmd, cp, player)
        bcps_halo(player, "You forced the checkpoint. Faction guards are alerted.", 255, 80, 60)
        bcps_say(player, "Checkpoint forced!")
        if NPCWorldRulesServer and NPCWorldRulesServer.SyncAfterConsequence then NPCWorldRulesServer.SyncAfterConsequence(player, "checkpoint_forced", {side=cp.side}) end
        TransmitNPCModData()
        return
    end
end

function NPCCheckpointsServerBridge.OnClientCommand(module, command, player, args)
    if not NPCLegacyContractBridge.IsModule(module, "NPCCheckpoints", "checkpoints") then return end
    if command == "RequestSync" then
        NPCCheckpointsServerBridge.EnsureCheckpoints(false)
    elseif command == "Interact" then
        bcps_interact(player, args)
    end
end

local function bcps_everyTenMinutes()
    NPCCheckpointsServerBridge.EnsureCheckpoints(false)
    local gmd = GetNPCModData()
    local changed = (tonumber(bcps_materializeNearbyCheckpoints(gmd)) or 0) + (tonumber(bcps_updateZoneBreachState(gmd)) or 0) + (tonumber(bcps_updateCheckpointLifetimes(gmd)) or 0)
    if changed and changed > 0 and TransmitNPCModData then TransmitNPCModData() end
end

local function bcps_onTick()
    NPCCheckpointsServerBridge._physicalTick = (tonumber(NPCCheckpointsServerBridge._physicalTick) or 0) + 1
    if NPCCheckpointsServerBridge._physicalTick < 45 then return end
    NPCCheckpointsServerBridge._physicalTick = 0
    local gmd = GetNPCModData()
    local changed = (tonumber(bcps_materializeNearbyCheckpoints(gmd)) or 0) + (tonumber(bcps_updateZoneBreachState(gmd)) or 0) + (tonumber(bcps_updateCheckpointLifetimes(gmd)) or 0)
    if changed and changed > 0 and TransmitNPCModData then TransmitNPCModData() end
end

function NPCCheckpointsServerBridge.Install()
    if NPCCheckpointsServerBridge._installed then return end
    NPCCheckpointsServerBridge._installed = true
    Events.OnClientCommand.Add(NPCCheckpointsServerBridge.OnClientCommand)
    Events.EveryTenMinutes.Add(bcps_everyTenMinutes)
    if Events and Events.OnTick then Events.OnTick.Add(bcps_onTick) end
end
