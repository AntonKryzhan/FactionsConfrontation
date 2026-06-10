-- NPCCounterIntelHunterServerBridge.lua
-- Server-side counterintelligence hunter waves driven by radio/intercept heat.
-- Keeps the execution layer isolated from the large WorldDirector facade.

if isClient and isClient() then return end

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCLegacySettingsBridge"
require "NPCCore/NPCDiagnosticsBridge"
require "NPCCore/NPCRadioInterceptBridge"
require "NPCCore/NPCFactionBridge"
require "NPCServer/NPCWorldDirector"
require "NPCServer/NPCWorldDirectorBridge"

local NPC_LEGACY_GLOBALS = NPCLegacyGlobalsBridge

NPCCounterIntelHunterServerBridge = NPCCounterIntelHunterServerBridge or {}
NPCCounterIntelHunterServerBridge.Version = 1
NPCCounterIntelHunterServerBridge._tick = NPCCounterIntelHunterServerBridge._tick or 0

local function cih_now()
    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then
            local ok, value = pcall(function() return gt:getWorldAgeHours() end)
            if ok and value then return tonumber(value) or 0 end
        end
    end
    return os.time() / 3600
end

local function cih_num(name, defaultValue, minValue, maxValue)
    local value = defaultValue
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        local ok, got = pcall(function() return NPCLegacySettingsBridge.GetNumber(name, defaultValue, minValue, maxValue) end)
        if ok and got ~= nil then value = got end
    end
    value = tonumber(value) or tonumber(defaultValue) or 0
    if minValue ~= nil and value < minValue then value = minValue end
    if maxValue ~= nil and value > maxValue then value = maxValue end
    return value
end

local function cih_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        local ok, got = pcall(function() return NPCLegacySettingsBridge.GetBool(name, defaultValue == true) end)
        if ok and got ~= nil then return got == true end
    end
    return defaultValue == true
end

function NPCCounterIntelHunterServerBridge.IsEnabled()
    if NPCRadioInterceptBridge and NPCRadioInterceptBridge.CounterIntelEnabled and not NPCRadioInterceptBridge.CounterIntelEnabled() then return false end
    return cih_bool("RadioIntercept_CounterIntelHunterWavesEnabled", true)
end

function NPCCounterIntelHunterServerBridge.MinHeat()
    return cih_num("RadioIntercept_CounterIntelHunterMinHeat", 25, 0, 200)
end

function NPCCounterIntelHunterServerBridge.MaxWaves()
    return math.floor(cih_num("RadioIntercept_CounterIntelHunterWavesMax", 3, 1, 12))
end

function NPCCounterIntelHunterServerBridge.CooldownHours()
    return cih_num("RadioIntercept_CounterIntelHunterCooldownHours", 6, 0.05, 168)
end

function NPCCounterIntelHunterServerBridge.MinSpawnDistance()
    return cih_num("RadioIntercept_CounterIntelHunterMinSpawnDistance", 110, 40, 800)
end

function NPCCounterIntelHunterServerBridge.MaxSpawnDistance()
    local minDist = NPCCounterIntelHunterServerBridge.MinSpawnDistance()
    return math.max(minDist + 10, cih_num("RadioIntercept_CounterIntelHunterMaxSpawnDistance", 240, 60, 1400))
end

function NPCCounterIntelHunterServerBridge.MaxActivePerPlayer()
    return math.floor(cih_num("RadioIntercept_CounterIntelHunterMaxActivePerPlayer", 1, 0, 8))
end

function NPCCounterIntelHunterServerBridge.EliteWaveLevel()
    return math.floor(cih_num("RadioIntercept_CounterIntelHunterEliteWaveLevel", 9, 1, 20))
end

local function cih_side(value)
    if NPCFactionBridge and NPCFactionBridge.NormalizeSide then
        local ok, got = pcall(function() return NPCFactionBridge.NormalizeSide(value) end)
        if ok and got then return got end
    end
    value = tostring(value or ""):lower()
    if value == "red" or value == "green" or value == "blue" or value == "black" then return value end
    return nil
end

local function cih_playerSide(player)
    if NPCFactionBridge and NPCFactionBridge.GetPlayerSide then
        local ok, got = pcall(function() return NPCFactionBridge.GetPlayerSide(player) end)
        if ok then return cih_side(got) end
    end
    return "blue"
end

local function cih_playerId(player)
    if not player then return "0" end
    if NPCUtils and NPCUtils.GetCharacterID then
        local ok, id = pcall(function() return NPCUtils.GetCharacterID(player) end)
        if ok and id ~= nil then return tostring(id) end
    end
    if player.getOnlineID then
        local ok, id = pcall(function() return player:getOnlineID() end)
        if ok and id ~= nil then return tostring(id) end
    end
    if player.getUsername then
        local ok, name = pcall(function() return player:getUsername() end)
        if ok and name then return tostring(name) end
    end
    return "0"
end

local function cih_playerName(player)
    if not player then return "player" end
    if player.getUsername then
        local ok, name = pcall(function() return player:getUsername() end)
        if ok and name and tostring(name) ~= "" then return tostring(name) end
    end
    if player.getDisplayName then
        local ok, name = pcall(function() return player:getDisplayName() end)
        if ok and name and tostring(name) ~= "" then return tostring(name) end
    end
    return "player"
end

local function cih_players()
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

local function cih_halo(player, text, r, g, b)
    if player and text and sendServerCommand then
        sendServerCommand(player, 'NPCCounterIntelHunter', 'Result', {text=tostring(text), r=r or 255, g=g or 80, b=b or 80})
    end
end

function NPCCounterIntelHunterServerBridge.EnsureData(gmd)
    if not gmd then return nil end
    gmd.CounterIntelHunters = gmd.CounterIntelHunters or {}
    gmd.CounterIntelHunters.players = gmd.CounterIntelHunters.players or {}
    gmd.CounterIntelHunters.groups = gmd.CounterIntelHunters.groups or {}
    gmd.CounterIntelHunters.nextId = tonumber(gmd.CounterIntelHunters.nextId) or 1
    gmd.CounterIntelHunters.stats = gmd.CounterIntelHunters.stats or {scheduled=0, materialized=0, retargets=0, expired=0}
    return gmd.CounterIntelHunters
end

local function cih_playerRecord(data, player)
    if not data then return nil end
    local pid = cih_playerId(player)
    data.players[pid] = data.players[pid] or {playerId=pid, playerName=cih_playerName(player), wave=0, active={}, cooldownUntil=0, lastSide=nil, lastHeat=0}
    local rec = data.players[pid]
    rec.playerName = cih_playerName(player)
    rec.active = rec.active or {}
    rec.wave = tonumber(rec.wave) or 0
    rec.cooldownUntil = tonumber(rec.cooldownUntil) or 0
    rec.lastHeat = tonumber(rec.lastHeat) or 0
    return rec
end

local function cih_bestHeat(gmd, player)
    if NPCRadioInterceptBridge and NPCRadioInterceptBridge.CounterIntelStatusText then
        pcall(function() NPCRadioInterceptBridge.CounterIntelStatusText(gmd, player) end)
    end
    local radio = gmd and gmd.NPCRadioInterceptBridge
    local ci = radio and radio.counterIntel
    local rows = ci and ci.players and ci.players[cih_playerId(player)]
    if type(rows) ~= "table" then return nil, 0 end
    local bestSide, bestHeat = nil, 0
    for side, row in pairs(rows) do
        local normalized = cih_side(side)
        if normalized and normalized ~= "blue" and type(row) == "table" then
            local heat = tonumber(row.heat) or 0
            if heat > bestHeat then
                bestSide = normalized
                bestHeat = heat
            end
        end
    end
    return bestSide, bestHeat
end

local function cih_hunterSide(player, sourceSide)
    sourceSide = cih_side(sourceSide)
    if sourceSide == "red" or sourceSide == "green" then return sourceSide end
    local playerSide = cih_playerSide(player)
    if playerSide == "red" then return "green" end
    if playerSide == "green" then return "red" end
    return "red"
end

local function cih_dist(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return math.sqrt(dx * dx + dy * dy)
end

local function cih_worldDirector()
    local director = NPCWorldDirectorServer or NPCWorldDirector or (NPC_LEGACY_GLOBALS and NPC_LEGACY_GLOBALS.Get and NPC_LEGACY_GLOBALS.Get("WorldDirector"))
    if type(director) ~= "table" or not director.EnsureData then return nil end
    return director
end

local function cih_applyMarkerFields(marker, group)
    if not (marker and group) then return marker end
    marker.name = group.name or marker.name or "Counter-Intel Hunter Team"
    marker.displayName = marker.name
    marker.markerType = "group"
    marker.counterIntelHunter = true
    marker.counterIntelWave = group.counterIntelWave
    marker.counterIntelState = group.counterIntelState or group.state
    marker.counterIntelSide = group.counterIntelSide or group.side
    marker.counterIntelHeat = group.counterIntelHeat
    marker.counterIntelElite = group.counterIntelElite == true
    marker.counterIntelTargetPlayerId = group.counterIntelTargetPlayerId
    marker.counterIntelTargetPlayerName = group.counterIntelTargetPlayerName
    marker.targetX = group.targetX
    marker.targetY = group.targetY
    marker.targetClass = group.targetClass
    marker.unitLevel = group.unitLevel
    marker.unitStars = group.unitStars
    marker.eliteUnit = group.eliteUnit == true
    marker.worldNameplate = true
    marker.displayTitle = group.displayTitle or "Counter-Intel"
    marker.patrolColor = group.patrolColor or group.side
    marker.factionSide = group.factionSide or group.side
    marker.side = group.side
    marker.hostile = true
    marker.friendly = false
    marker.updatedAt = group.updatedAt or cih_now()
    return marker
end

local function cih_setMarker(gmd, marker)
    if not (gmd and marker and marker.id) then return false end
    gmd.DebugMapMarkers = gmd.DebugMapMarkers or {}
    gmd.DebugMapMarkers[tostring(marker.id)] = marker
    if NPCNetContract and NPCNetContract.SendDebugMapUpdate then
        NPCNetContract.SendDebugMapUpdate(marker)
    elseif sendServerCommand then
        sendServerCommand('NPCDebugMap', 'Update', marker)
    end
    return true
end

local function cih_updateGroupMarker(gmd, group)
    if not (gmd and group and group.id) then return false end
    local marker = gmd.DebugMapMarkers and gmd.DebugMapMarkers[tostring(group.id)] or nil
    if not marker and NPCWorldDirectorBridge and NPCWorldDirectorBridge.BuildVirtualGroupMarker then
        marker = NPCWorldDirectorBridge.BuildVirtualGroupMarker(group)
    end
    marker = marker or {id=tostring(group.id), markerType="group"}
    marker.x = group.x
    marker.y = group.y
    marker.z = group.z or 0
    marker.virtual = group.virtual ~= false
    marker.active = group.activated == true
    marker.state = group.state
    marker.count = group.count
    cih_applyMarkerFields(marker, group)
    return cih_setMarker(gmd, marker)
end

local function cih_spawnPoint(player)
    if not (player and player.getX and player.getY) then return nil end
    local px, py = player:getX(), player:getY()
    local minDist = NPCCounterIntelHunterServerBridge.MinSpawnDistance()
    local maxDist = NPCCounterIntelHunterServerBridge.MaxSpawnDistance()
    local best = nil
    for _ = 1, 12 do
        local dist = minDist + ZombRand(math.max(1, math.floor(maxDist - minDist + 1)))
        local angle = (ZombRand(6284) / 1000.0)
        local x = math.floor(px + math.cos(angle) * dist)
        local y = math.floor(py + math.sin(angle) * dist)
        local z = player.getZ and player:getZ() or 0
        best = {x=x, y=y, z=z, dist=dist}
        if NPCRoadNavBridge and NPCRoadNavBridge.FindNearbyWorldRoadStepToward then
            local road = NPCRoadNavBridge.FindNearbyWorldRoadStepToward(x, y, px, py, 90, 10)
            if road and road.x and road.y then
                best = {x=math.floor(road.x), y=math.floor(road.y), z=road.z or z, dist=cih_dist(road.x, road.y, px, py)}
            end
        end
        if best.dist >= minDist * 0.75 then break end
    end
    return best
end

local function cih_waveProfile(waveNo)
    waveNo = math.max(1, tonumber(waveNo) or 1)
    local size = 2 + math.min(4, waveNo)
    return {
        enabled = true,
        enemyBehaviour = 2,
        firstDay = 0,
        lastDay = 99999,
        groupSize = size,
        clanId = 13,
        eliteLoadout = true,
        mercenaryElite = true,
        hasPistolChance = 100,
        pistolMagCount = 4 + waveNo,
        hasRifleChance = 100,
        rifleMagCount = 6 + waveNo
    }
end

local function cih_memberLevel(waveNo)
    local elite = NPCCounterIntelHunterServerBridge.EliteWaveLevel()
    if waveNo >= NPCCounterIntelHunterServerBridge.MaxWaves() then return elite end
    return math.max(2, math.min(elite - 1, 2 + waveNo * 2))
end

local function cih_stars(level)
    level = tonumber(level) or 1
    if level >= 8 then return 3 end
    if level >= 5 then return 2 end
    return 1
end

local function cih_addUnique(list, value)
    if type(list) ~= "table" or not value then return end
    for _, v in pairs(list) do
        if v == value then return end
    end
    table.insert(list, value)
end

local CIH_HUNTER_ARMOR = {
    "Base.Vest_BulletArmy",
    "Base.Vest_BulletPolice",
    "Base.Hat_ArmyHelmet",
    "Base.HolsterDouble",
    "Base.Bag_ALICEpack_Army",
    "Base.Gloves_LeatherGlovesBlack",
    "Base.Shoes_ArmyBoots"
}

local function cih_applyEliteGear(member)
    if type(member) ~= "table" then return end
    member.inventory = member.inventory or {}
    member.loot = member.loot or {}
    member.baseGearWear = member.baseGearWear or {}
    for _, itemType in ipairs(CIH_HUNTER_ARMOR) do
        cih_addUnique(member.inventory, itemType)
        cih_addUnique(member.loot, itemType)
        cih_addUnique(member.baseGearWear, itemType)
    end
    if type(member.weapons) == "table" then
        if type(member.weapons.primary) == "table" and member.weapons.primary.name then
            member.weapons.primary.magSize = tonumber(member.weapons.primary.magSize) or 30
            member.weapons.primary.bulletsLeft = member.weapons.primary.magSize
            member.weapons.primary.magCount = math.max(tonumber(member.weapons.primary.magCount) or 0, 8)
        end
        if type(member.weapons.secondary) == "table" and member.weapons.secondary.name then
            member.weapons.secondary.magSize = tonumber(member.weapons.secondary.magSize) or 15
            member.weapons.secondary.bulletsLeft = member.weapons.secondary.magSize
            member.weapons.secondary.magCount = math.max(tonumber(member.weapons.secondary.magCount) or 0, 5)
        end
    end
end

local function cih_applyMemberFields(member, group, index)
    if type(member) ~= "table" then return member end
    local level = cih_memberLevel(group.counterIntelWave)
    local stars = cih_stars(level)
    member.counterIntelHunter = true
    member.counterIntelWave = group.counterIntelWave
    member.counterIntelSide = group.counterIntelSide
    member.counterIntelTargetPlayerId = group.counterIntelTargetPlayerId
    member.counterIntelTargetPlayerName = group.counterIntelTargetPlayerName
    member.displayTitle = "Counter-Intel"
    member.nameplateTitle = "Counter-Intel"
    member.unitLevel = level
    member.unitStars = stars
    member.eliteUnit = stars >= 3
    member.role = index == 1 and "counterintel_leader" or "counterintel_hunter"
    member.tacticalRole = index == 1 and "hunter_leader" or "assault_hunter"
    member.program = {name="Raider", stage="Prepare"}
    member.order = {name="Advance", source="counterintel_hunter", fireMode="FireAtWill", priority=95, sticky=true, anchor={x=group.targetX, y=group.targetY, z=group.targetZ or 0}, note="Hunt intercepted radio operator"}
    member.factionSide = group.side
    member.faction = group.side
    member.side = group.side
    member.patrolColor = group.side
    member.accuracyBoost = math.max(tonumber(member.accuracyBoost) or 1, 1.0 + (level * 0.055))
    member.health = math.max(tonumber(member.health) or 3.0, 4.5 + (level * 0.16))
    member.maxHealth = math.max(tonumber(member.maxHealth) or 0, tonumber(member.health) or 0)
    cih_applyEliteGear(member)
    member.preferCover = true
    member.preferRoads = true
    member.roadBias = true
    if member.eliteUnit then
        member.behaviorStyle = "counterintel_elite"
        member.commandAura = index == 1
    else
        member.behaviorStyle = "counterintel_hunter"
    end
    return member
end

local function cih_makeGroup(gmd, director, player, sourceSide, heat, waveNo)
    if not (gmd and director and player and player.getX and player.getY) then return nil end
    local point = cih_spawnPoint(player)
    if not point then return nil end
    local data = NPCCounterIntelHunterServerBridge.EnsureData(gmd)
    if not data then return nil end

    local pid = cih_playerId(player)
    local pname = cih_playerName(player)
    local side = cih_hunterSide(player, sourceSide)
    local groupId = "CIH" .. tostring(data.nextId)
    data.nextId = (tonumber(data.nextId) or 1) + 1

    local px, py = player:getX(), player:getY()
    local pz = player.getZ and player:getZ() or 0
    local wave = cih_waveProfile(waveNo)
    local count = NPCWorldDirectorBridge and NPCWorldDirectorBridge.ClampGroupSize and NPCWorldDirectorBridge.ClampGroupSize(wave.groupSize, 2, 8) or wave.groupSize
    local group = {
        id = groupId,
        x = point.x,
        y = point.y,
        z = point.z or 0,
        preciseX = point.x,
        preciseY = point.y,
        clanId = wave.clanId,
        count = count,
        hostile = true,
        program = {name="Raider", stage="Prepare"},
        members = {},
        virtual = true,
        activated = false,
        createdAt = cih_now(),
        updatedAt = cih_now(),
        state = "counterintel_hunter_tracking",
        spawnClass = "counterintel_hunter",
        targetX = math.floor(px),
        targetY = math.floor(py),
        targetZ = pz,
        routeX = math.floor(px),
        routeY = math.floor(py),
        routeZ = pz,
        targetClass = "counterintel_hunt",
        speed = 145 + (tonumber(waveNo) or 1) * 28,
        roadBias = true,
        preferRoads = true,
        patrolColor = side,
        factionSide = side,
        faction = side,
        side = side,
        counterIntelHunter = true,
        counterIntelWave = waveNo,
        counterIntelState = "tracking",
        counterIntelSide = sourceSide or side,
        counterIntelHeat = math.floor((tonumber(heat) or 0) + 0.5),
        counterIntelTargetPlayerId = pid,
        counterIntelTargetPlayerName = pname,
        counterIntelElite = waveNo >= NPCCounterIntelHunterServerBridge.MaxWaves(),
        unitLevel = cih_memberLevel(waveNo),
        unitStars = cih_stars(cih_memberLevel(waveNo)),
        eliteUnit = waveNo >= NPCCounterIntelHunterServerBridge.MaxWaves(),
        displayTitle = "Counter-Intel",
        name = "Counter-Intel Hunter Team W" .. tostring(waveNo)
    }

    for i = 1, count do
        local member = nil
        if NPCWorldDirectorBridge and NPCWorldDirectorBridge.PrepareVirtualMember then
            member = NPCWorldDirectorBridge.PrepareVirtualMember(director, gmd, wave, groupId, i, side, false)
        end
        if type(member) ~= "table" then member = {} end
        if NPCIdentityBridge and NPCIdentityBridge.NewUID then
            member.uid = member.uid or NPCIdentityBridge.NewUID(gmd)
            member.persistentId = member.persistentId or member.uid
        end
        member.worldGroupId = groupId
        member.groupId = groupId
        member.memberIndex = i
        cih_applyMemberFields(member, group, i)
        group.members[#group.members + 1] = member
    end
    group.count = #group.members
    if group.count <= 0 then return nil end

    if NPCStrategicAIBridge and NPCStrategicAIBridge.EvaluateGroupCombatPower then
        pcall(function() NPCStrategicAIBridge.EvaluateGroupCombatPower(gmd, group) end)
    end
    if NPCIdentityBridge and NPCIdentityBridge.TouchVirtualGroup then
        pcall(function() NPCIdentityBridge.TouchVirtualGroup(gmd, group) end)
    end
    if NPCPersistentNPCBridge and NPCPersistentNPCBridge.RegisterGroup then
        pcall(function() NPCPersistentNPCBridge.RegisterGroup(gmd, group) end)
    end

    gmd.VirtualGroups = gmd.VirtualGroups or {}
    gmd.VirtualGroups[groupId] = group
    data.groups[groupId] = {playerId=pid, playerName=pname, side=sourceSide or side, wave=waveNo, state="tracking", createdAt=group.createdAt, groupId=groupId}
    local rec = cih_playerRecord(data, player)
    if rec then
        rec.active[groupId] = true
        rec.wave = math.max(tonumber(rec.wave) or 0, waveNo)
        rec.cooldownUntil = cih_now() + NPCCounterIntelHunterServerBridge.CooldownHours()
        rec.lastSide = sourceSide or side
        rec.lastHeat = tonumber(heat) or 0
        rec.updatedAt = cih_now()
    end
    data.stats.scheduled = (tonumber(data.stats.scheduled) or 0) + 1
    if NPCDiagnosticsBridge and NPCDiagnosticsBridge.LogRiskAction then
        NPCDiagnosticsBridge.LogRiskAction("counterintel", "hunter_wave_spawned", {playerId=pid, groupId=groupId, wave=waveNo, heat=heat, side=group.side, x=group.x, y=group.y, targetX=group.targetX, targetY=group.targetY}, "cih-spawn:" .. tostring(pid) .. ":" .. tostring(waveNo), true)
    end

    cih_updateGroupMarker(gmd, group)
    if NPCWorldDirectorBridge and NPCWorldDirectorBridge.DirectorEvent then
        pcall(function()
            NPCWorldDirectorBridge.DirectorEvent(director, "counterintel_hunter_created", group.x, group.y, group.z or 0, {groupId=groupId, playerId=pid, wave=waveNo, heat=group.counterIntelHeat, side=group.side})
        end)
    end
    cih_halo(player, "Counterintelligence hunter team dispatched. Wave " .. tostring(waveNo) .. "/" .. tostring(NPCCounterIntelHunterServerBridge.MaxWaves()) .. ".", 255, 80, 80)
    return group
end

local function cih_activeCount(gmd, rec)
    if not (gmd and rec and type(rec.active) == "table") then return 0 end
    local count = 0
    for groupId, _ in pairs(rec.active) do
        local group = gmd.VirtualGroups and gmd.VirtualGroups[tostring(groupId)] or nil
        if type(group) == "table" and group.counterIntelHunter == true and (tonumber(group.count) or 0) > 0 then
            count = count + 1
        else
            rec.active[groupId] = nil
        end
    end
    return count
end

function NPCCounterIntelHunterServerBridge.TryScheduleForPlayer(player, reason)
    if not NPCCounterIntelHunterServerBridge.IsEnabled() then return false end
    local maxActive = NPCCounterIntelHunterServerBridge.MaxActivePerPlayer()
    if maxActive <= 0 then return false end
    local gmd = GetNPCModData and GetNPCModData() or nil
    if not gmd then return false end
    gmd.VirtualGroups = gmd.VirtualGroups or {}
    local director = cih_worldDirector()
    if not director then return false end
    if gmd.WorldDirector and gmd.WorldDirector.enabled == false then return false end

    local side, heat = cih_bestHeat(gmd, player)
    if not side or heat < NPCCounterIntelHunterServerBridge.MinHeat() then return false end
    local data = NPCCounterIntelHunterServerBridge.EnsureData(gmd)
    local rec = cih_playerRecord(data, player)
    if not rec then return false end
    if cih_activeCount(gmd, rec) >= maxActive then return false end
    if cih_now() < (tonumber(rec.cooldownUntil) or 0) then return false end
    local maxWaves = NPCCounterIntelHunterServerBridge.MaxWaves()
    local nextWave = (tonumber(rec.wave) or 0) + 1
    if nextWave > maxWaves then return false end

    local group = cih_makeGroup(gmd, director, player, side, heat, nextWave)
    if group then
        if TransmitNPCModData then TransmitNPCModData() end
        return true
    end
    return false
end

local function cih_retargetMembers(group)
    if type(group) ~= "table" or type(group.members) ~= "table" then return end
    for _, member in pairs(group.members) do
        if type(member) == "table" and member.counterIntelHunter then
            member.order = member.order or {}
            member.order.name = "Advance"
            member.order.source = "counterintel_hunter"
            member.order.fireMode = "FireAtWill"
            member.order.priority = 95
            member.order.sticky = true
            member.order.anchor = {x=group.targetX, y=group.targetY, z=group.targetZ or 0}
            member.counterIntelTargetPlayerId = group.counterIntelTargetPlayerId
            member.counterIntelTargetPlayerName = group.counterIntelTargetPlayerName
        end
    end
end

function NPCCounterIntelHunterServerBridge.UpdateActiveGroups()
    if not NPCCounterIntelHunterServerBridge.IsEnabled() then return 0 end
    local gmd = GetNPCModData and GetNPCModData() or nil
    if not (gmd and type(gmd.VirtualGroups) == "table") then return 0 end
    local director = cih_worldDirector()
    if not director then return 0 end
    local data = NPCCounterIntelHunterServerBridge.EnsureData(gmd)
    if not data then return 0 end
    local playersById = {}
    for _, player in ipairs(cih_players()) do
        playersById[cih_playerId(player)] = player
    end

    local changed = 0
    local materializeDistance = math.min(96, math.max(64, NPCCounterIntelHunterServerBridge.MinSpawnDistance()))
    local now = cih_now()
    for groupId, info in pairs(data.groups or {}) do
        local group = gmd.VirtualGroups[tostring(groupId)]
        if type(group) ~= "table" or group.counterIntelHunter ~= true or (tonumber(group.count) or 0) <= 0 then
            data.groups[groupId] = nil
            data.stats.expired = (tonumber(data.stats.expired) or 0) + 1
        else
            local player = playersById[tostring(group.counterIntelTargetPlayerId or info.playerId or "")]
            if player and player.getX and player.getY then
                local px, py = player:getX(), player:getY()
                local pz = player.getZ and player:getZ() or 0
                group.targetX = math.floor(px)
                group.targetY = math.floor(py)
                group.targetZ = pz
                group.routeX = group.targetX
                group.routeY = group.targetY
                group.routeZ = pz
                group.targetClass = "counterintel_hunt"
                group.counterIntelState = group.activated and "materialized" or "tracking"
                group.state = group.activated and "counterintel_hunter_materialized" or "counterintel_hunter_tracking"
                group.updatedAt = now
                cih_retargetMembers(group)

                if group.virtual ~= false and not group.activated then
                    local gx = tonumber(group.preciseX or group.x) or 0
                    local gy = tonumber(group.preciseY or group.y) or 0
                    local dist = cih_dist(gx, gy, px, py)
                    local last = tonumber(group.counterIntelLastMoveAt) or tonumber(group.updatedAt) or now
                    local dt = math.max(0, now - last)
                    if dt > 0 and dist > materializeDistance * 0.55 then
                        local speed = tonumber(group.speed) or 160
                        local step = math.min(dist - materializeDistance * 0.45, speed * dt)
                        if step > 1 then
                            local nx = gx + ((px - gx) / math.max(0.001, dist)) * step
                            local ny = gy + ((py - gy) / math.max(0.001, dist)) * step
                            group.preciseX = nx
                            group.preciseY = ny
                            group.x = math.floor(nx)
                            group.y = math.floor(ny)
                        end
                    end
                    group.counterIntelLastMoveAt = now

                    local newDist = cih_dist(group.x, group.y, px, py)
                    if newDist <= materializeDistance then
                        group.anchorMaterializeAtGroup = true
                        group.anchorSpawnRadius = 18
                        group.anchorRoadRadius = 56
                        local ok, materialized = false, false
                        if director.MaterializeGroup then
                            ok, materialized = pcall(function() return director.MaterializeGroup(group, player) end)
                        elseif NPCWorldDirectorBridge and NPCWorldDirectorBridge.MaterializeGroup then
                            ok, materialized = pcall(function() return NPCWorldDirectorBridge.MaterializeGroup(director, group, player) end)
                        end
                        if ok and materialized then
                            data.stats.materialized = (tonumber(data.stats.materialized) or 0) + 1
                            if NPCDiagnosticsBridge and NPCDiagnosticsBridge.LogRiskAction then
                                NPCDiagnosticsBridge.LogRiskAction("counterintel", "hunter_materialized", {playerId=cih_playerId(player), groupId=group.id, wave=group.counterIntelWave, x=group.x, y=group.y, targetX=group.targetX, targetY=group.targetY}, "cih-materialized:" .. tostring(group.id), true)
                            end
                            group = gmd.VirtualGroups[tostring(groupId)] or group
                            group.counterIntelState = "materialized"
                            group.state = "counterintel_hunter_materialized"
                        end
                    end
                end
                gmd.VirtualGroups[tostring(groupId)] = group
                cih_updateGroupMarker(gmd, group)
                data.stats.retargets = (tonumber(data.stats.retargets) or 0) + 1
                changed = changed + 1
            end
        end
    end
    if changed > 0 and TransmitNPCModData then TransmitNPCModData() end
    return changed
end

function NPCCounterIntelHunterServerBridge.EveryTenMinutes()
    if not NPCCounterIntelHunterServerBridge.IsEnabled() then return end
    for _, player in ipairs(cih_players()) do
        NPCCounterIntelHunterServerBridge.TryScheduleForPlayer(player, "periodic_heat_check")
    end
end

function NPCCounterIntelHunterServerBridge.OnTick()
    NPCCounterIntelHunterServerBridge._tick = (tonumber(NPCCounterIntelHunterServerBridge._tick) or 0) + 1
    if (NPCCounterIntelHunterServerBridge._tick % 300) ~= 0 then return end
    NPCCounterIntelHunterServerBridge.UpdateActiveGroups()
end

function NPCCounterIntelHunterServerBridge.Status(player)
    local gmd = GetNPCModData and GetNPCModData() or nil
    local side, heat = cih_bestHeat(gmd, player)
    local data = NPCCounterIntelHunterServerBridge.EnsureData(gmd)
    local rec = data and cih_playerRecord(data, player) or nil
    local active = cih_activeCount(gmd, rec)
    cih_halo(player, "Counter-Intel heat " .. tostring(side or "none") .. " " .. tostring(math.floor((tonumber(heat) or 0) + 0.5)) .. "; waves " .. tostring(rec and rec.wave or 0) .. "/" .. tostring(NPCCounterIntelHunterServerBridge.MaxWaves()) .. "; active " .. tostring(active) .. ".", 255, 120, 80)
end

function NPCCounterIntelHunterServerBridge.OnClientCommand(module, command, player, args)
    if not NPCLegacyContractBridge.IsModule(module, "NPCCounterIntelHunter", "counterIntelHunter") then return end
    if command == "Status" then
        NPCCounterIntelHunterServerBridge.Status(player)
    elseif command == "ForceCheck" then
        NPCCounterIntelHunterServerBridge.TryScheduleForPlayer(player, "client_force_check")
        NPCCounterIntelHunterServerBridge.Status(player)
    end
end

function NPCCounterIntelHunterServerBridge.Install()
    if NPCCounterIntelHunterServerBridge.__installed then return end
    NPCCounterIntelHunterServerBridge.__installed = true
    Events.EveryTenMinutes.Add(NPCCounterIntelHunterServerBridge.EveryTenMinutes)
    Events.OnTick.Add(NPCCounterIntelHunterServerBridge.OnTick)
    Events.OnClientCommand.Add(NPCCounterIntelHunterServerBridge.OnClientCommand)
end
