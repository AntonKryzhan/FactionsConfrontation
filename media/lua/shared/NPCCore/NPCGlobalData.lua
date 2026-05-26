NPCGlobalData = NPCGlobalData or {}

require "NPCCommands/NPCNetContract"
require "NPCCore/NPCDiagnosticsBridge"
require "NPCCore/NPCIdentityBridge"
require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCGlobalDataStore = NPCLegacyGlobalsBridge.InstallAlias("GlobalData", NPCGlobalDataStore, "NPCGlobalDataStore")
NPCGlobalDataPlayersStore = NPCLegacyGlobalsBridge.InstallAlias("GlobalDataPlayers", NPCGlobalDataPlayersStore, "NPCGlobalDataPlayersStore")

local NPC_GMD_LEGACY_KEYS = NPCLegacyContractBridge.ModData
local NPC_GMD_LEGACY_FUNCTIONS = NPCLegacyContractBridge.Functions
local NPC_GMD_LOG_PREFIX = "[NPCGMD]"
local NPC_GMD_PAYLOAD_LABEL = "NPC compatibility payload"

NPCGlobalData._clientSafeSyncRequested = NPCGlobalData._clientSafeSyncRequested or false
NPCGlobalData._clientSafeSyncReady = NPCGlobalData._clientSafeSyncReady or false

function NPCGlobalData.IsClientSafeSyncReady()
    if isClient and isClient() then
        return NPCGlobalData._clientSafeSyncReady == true
    end
    return true
end

local function bgmd_requestNPCSafeSync(player)
    if not isClient or not isClient() then return end
    if NPCGlobalData._clientSafeSyncRequested then return end
    if not player and getPlayer then player = getPlayer() end
    if not player or not sendClientCommand then return end

    NPCGlobalData._clientSafeSyncReady = false
    NPCGlobalData._clientSafeSyncRequested = true
    sendClientCommand(player, "NPCCommands", "RequestSafeSync", {})
end

function NPCGlobalData.InitNPCModData(isNewGame)

    -- BANDIT GLOBAL MODDATA
    local globalData = ModData.getOrCreate(NPC_GMD_LEGACY_KEYS.data)
    if isClient() then
        -- Do not request the raw server-side compatibility table on join.
        -- It can contain large NPC/marker state and corrupt the GlobalModData packet.
        -- A safe, trimmed snapshot is requested after the local player exists.
        bgmd_requestNPCSafeSync()
    end

    if not globalData.Queue then globalData.Queue = {} end
    if not globalData.VirtualGroups then globalData.VirtualGroups = {} end
    if not globalData.DebugMapMarkers then globalData.DebugMapMarkers = {} end
    if not globalData.BattleRemains then globalData.BattleRemains = {} end
    if not globalData.WorldDirector then
        globalData.WorldDirector = {
            enabled = true,
            initialized = false,
            nextGroupId = 1,
            lastUpdate = 0,
            lastSpawn = 0
        }
    end

    if not globalData.Registry then globalData.Registry = {} end
    if not globalData.RuntimeToUID then globalData.RuntimeToUID = {} end
    if not globalData.UIDToRuntime then globalData.UIDToRuntime = {} end
    if not globalData.DeadRegistry then globalData.DeadRegistry = {} end
    if not globalData.PersistentNPCs then globalData.PersistentNPCs = {} end
    if not globalData.PersistentGroups then globalData.PersistentGroups = {} end
    if not globalData.PersistentRuntimeToUID then globalData.PersistentRuntimeToUID = {} end
    if not globalData.PersistentUIDToRuntime then globalData.PersistentUIDToRuntime = {} end
    if not globalData.NextPersistentId then globalData.NextPersistentId = 1 end
    if not globalData.PersistentVersion then globalData.PersistentVersion = 2 end
    if NPCIdentityBridge and NPCIdentityBridge.EnsureGlobalData then
        NPCIdentityBridge.EnsureGlobalData(globalData)
    end
    if NPCPersistentNPCBridge and NPCPersistentNPCBridge.EnsureData then
        NPCPersistentNPCBridge.EnsureData(globalData)
    end

    -- uncomment these to reset all bandits on server restart
    -- if isServer() then
    --    globalData.Queue = {}
    -- end
    
    if not globalData.Scenes then globalData.Scenes = {} end
    if not globalData[NPC_GMD_LEGACY_KEYS.bandits] then globalData[NPC_GMD_LEGACY_KEYS.bandits] = {} end
    if not globalData.Posts then globalData.Posts = {} end
    if not globalData.Bases then globalData.Bases = {} end
    if not globalData.Kills then globalData.Kills = {} end
    if not globalData.VisitedBuildings then globalData.VisitedBuildings = {} end
    NPCGlobalDataStore = NPCLegacyGlobalsBridge.InstallAlias("GlobalData", globalData, "NPCGlobalDataStore")

    -- BANDIT PLAYERS GLOBAL MODDATA
    local globalDataPlayers = ModData.getOrCreate(NPC_GMD_LEGACY_KEYS.players)
    if isClient() then
        ModData.request(NPC_GMD_LEGACY_KEYS.players)
    end
   
    globalDataPlayers.OnlinePlayers = {}
    NPCGlobalDataPlayersStore = NPCLegacyGlobalsBridge.InstallAlias("GlobalDataPlayers", globalDataPlayers, "NPCGlobalDataPlayersStore")
end

function NPCGlobalData.LoadNPCModData(key, globalData)
    if isClient() then
        if key and globalData then
            if key == NPC_GMD_LEGACY_KEYS.data then
                globalData.Queue = globalData.Queue or {}
                globalData.VirtualGroups = globalData.VirtualGroups or {}
                globalData.DebugMapMarkers = globalData.DebugMapMarkers or {}
                globalData.BattleRemains = globalData.BattleRemains or {}
                globalData.Scenes = globalData.Scenes or {}
                globalData[NPC_GMD_LEGACY_KEYS.bandits] = globalData[NPC_GMD_LEGACY_KEYS.bandits] or {}
                globalData.Posts = globalData.Posts or {}
                globalData.Bases = globalData.Bases or {}
                globalData.Kills = globalData.Kills or {}
                globalData.VisitedBuildings = globalData.VisitedBuildings or {}
                NPCGlobalDataStore = NPCLegacyGlobalsBridge.InstallAlias("GlobalData", globalData, "NPCGlobalDataStore")
                NPCGlobalData._clientSafeSyncRequested = false
                NPCGlobalData._clientSafeSyncReady = true
            elseif key == NPC_GMD_LEGACY_KEYS.players then
                NPCGlobalDataPlayersStore = NPCLegacyGlobalsBridge.InstallAlias("GlobalDataPlayers", globalData, "NPCGlobalDataPlayersStore")
            end
        end
    end
end

NPCGlobalData[NPC_GMD_LEGACY_FUNCTIONS.initModData] = function(...)
    return NPCGlobalData.InitNPCModData(...)
end

NPCGlobalData[NPC_GMD_LEGACY_FUNCTIONS.loadModData] = function(...)
    return NPCGlobalData.LoadNPCModData(...)
end

function NPCGlobalData.GetNPCModData()
    return NPCGlobalDataStore
end

function NPCGlobalData.GetNPCModDataPlayers()
    return NPCGlobalDataPlayersStore
end

NPCGlobalData[NPC_GMD_LEGACY_FUNCTIONS.getModData] = function()
    return NPCGlobalData.GetNPCModData()
end

NPCGlobalData[NPC_GMD_LEGACY_FUNCTIONS.getModDataPlayers] = function()
    return NPCGlobalData.GetNPCModDataPlayers()
end

local function bgmd_tableCount(tbl)
    local count = 0
    if type(tbl) ~= "table" then return 0 end
    for _, _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

local function bgmd_brainCoords(brain)
    if type(brain) ~= "table" then return nil, nil, 0 end

    if type(brain.debugCoords) == "table" and brain.debugCoords.x and brain.debugCoords.y then
        return tonumber(brain.debugCoords.x), tonumber(brain.debugCoords.y), tonumber(brain.debugCoords.z) or 0
    end

    if brain.x and brain.y then
        return tonumber(brain.x), tonumber(brain.y), tonumber(brain.z) or 0
    end

    if type(brain.bornCoords) == "table" and brain.bornCoords.x and brain.bornCoords.y then
        return tonumber(brain.bornCoords.x), tonumber(brain.bornCoords.y), tonumber(brain.bornCoords.z) or 0
    end

    return nil, nil, 0
end

local function bgmd_nearAnyPlayer(x, y, radius)
    if not x or not y then return true end
    if not isServer or not isServer() then return true end

    local players = getOnlinePlayers and getOnlinePlayers() or nil
    if not players then return true end

    local size = 0
    local okSize, result = pcall(function() return players:size() end)
    if okSize and result then size = tonumber(result) or 0 end
    if size <= 0 then return true end

    local r = tonumber(radius) or 420
    local r2 = r * r
    for i = 0, size - 1 do
        local player = players:get(i)
        if player then
            local dx = (tonumber(player:getX()) or 0) - x
            local dy = (tonumber(player:getY()) or 0) - y
            if dx * dx + dy * dy <= r2 then
                return true
            end
        end
    end

    return false
end

local function bgmd_liteString(value, maxLen)
    if value == nil then return nil end
    local text = tostring(value)
    maxLen = tonumber(maxLen) or 96
    if #text > maxLen then
        text = string.sub(text, 1, maxLen)
    end
    return text
end

local function bgmd_litePrimitive(value, maxString)
    local t = type(value)
    if t == "number" then
        if value ~= value or value == math.huge or value == -math.huge then return nil end
        return value
    end
    if t == "boolean" then return value end
    if t == "string" then return bgmd_liteString(value, maxString) end
    return nil
end

local function bgmd_liteKey(key)
    local t = type(key)
    if t == "string" or t == "number" then return key end
    if t == "boolean" then return tostring(key) end
    return nil
end

local function bgmd_skipNestedKey(key)
    local k = tostring(key or "")
    k = string.lower(k)
    if k == "inventory" or k == "loot" or k == "world" or k == "memory" or k == "history" then return true end
    if k == "registry" or k == "persistentnpcs" or k == "persistentgroups" then return true end
    if k == "runtimetouid" or k == "uidtoruntime" or k == "deadsregistry" or k == "deadregistry" then return true end
    if k == "persistentruntimetouid" or k == "persistentuidtoruntime" then return true end
    if string.find(k, "java", 1, true) or string.find(k, "object", 1, true) then return true end
    return false
end

local function bgmd_sanitizeValue(value, depth, maxItems, maxString)
    local primitive = bgmd_litePrimitive(value, maxString)
    if primitive ~= nil then return primitive end
    if type(value) ~= "table" then return nil end
    depth = tonumber(depth) or 0
    if depth <= 0 then return nil end

    local out = {}
    local count = 0
    maxItems = tonumber(maxItems) or 24
    for k, v in pairs(value) do
        if not bgmd_skipNestedKey(k) then
            local lk = bgmd_liteKey(k)
            if lk ~= nil then
                local lv = bgmd_sanitizeValue(v, depth - 1, maxItems, maxString)
                if lv ~= nil then
                    out[lk] = lv
                    count = count + 1
                    if count >= maxItems then break end
                end
            end
        end
    end
    return out
end

local function bgmd_liteIdList(ids, maxItems)
    local out = {}
    if type(ids) ~= "table" then return out end

    local count = 0
    maxItems = tonumber(maxItems) or 32
    for _, id in pairs(ids) do
        if id ~= nil then
            out[#out + 1] = tostring(id)
            count = count + 1
            if count >= maxItems then break end
        end
    end

    return out
end

local function bgmd_liteCoords(coords)
    if type(coords) ~= "table" then return nil end
    local x = tonumber(coords.x)
    local y = tonumber(coords.y)
    if not x or not y then return nil end
    return {x=x, y=y, z=tonumber(coords.z) or 0}
end

local function bgmd_liteProgram(program)
    if type(program) ~= "table" then return {name="Looter", stage="Prepare"} end
    return {
        name = bgmd_liteString(program.name or "Looter", 48),
        stage = bgmd_liteString(program.stage or "Prepare", 48),
        targetX = tonumber(program.targetX),
        targetY = tonumber(program.targetY),
        targetZ = tonumber(program.targetZ) or nil,
        x = tonumber(program.x),
        y = tonumber(program.y),
        z = tonumber(program.z) or nil
    }
end

local function bgmd_liteWeaponSlot(slot)
    if type(slot) ~= "table" then return nil end

    local name = bgmd_liteString(slot.name, 96)
    if not name or name == "" then return nil end

    return {
        name = name,
        magName = bgmd_liteString(slot.magName, 96),
        ammoType = bgmd_liteString(slot.ammoType, 96),
        bulletsLeft = tonumber(slot.bulletsLeft) or 0,
        magCount = tonumber(slot.magCount) or 0,
        ammoCount = tonumber(slot.ammoCount) or 0,
        rack = slot.rack == true,
        jammed = slot.jammed == true
    }
end

local function bgmd_liteWeapons(weapons)
    local out = {
        melee = "Base.BareHands",
        primary = {name=false, bulletsLeft=0, magCount=0, ammoCount=0},
        secondary = {name=false, bulletsLeft=0, magCount=0, ammoCount=0}
    }

    if type(weapons) ~= "table" then return out end

    if type(weapons.melee) == "string" and weapons.melee ~= "" then
        out.melee = bgmd_liteString(weapons.melee, 96)
    end

    local primary = bgmd_liteWeaponSlot(weapons.primary)
    if primary then out.primary = primary end

    local secondary = bgmd_liteWeaponSlot(weapons.secondary)
    if secondary then out.secondary = secondary end

    return out
end

local function bgmd_liteCurrentWeapon(currentWeapon)
    local slot = bgmd_liteWeaponSlot(currentWeapon)
    if slot then return slot end
    if type(currentWeapon) == "string" and currentWeapon ~= "" then
        return {name=bgmd_liteString(currentWeapon, 96), bulletsLeft=0, magCount=0, ammoCount=0}
    end
    return nil
end

local function bgmd_liteTask(task)
    if type(task) ~= "table" then return nil end
    local out = {}
    local keys = {
        "action", "time", "endurance", "x", "y", "z", "walkType", "closeSlow", "lock",
        "slot", "item", "sound", "soundRadius", "target", "targetX", "targetY", "targetZ",
        "director", "directorState", "directorReason", "building", "room", "stage"
    }
    for _, key in ipairs(keys) do
        local value = bgmd_litePrimitive(task[key], 96)
        if value ~= nil then out[key] = value end
    end
    return out
end

local function bgmd_liteTasks(tasks, maxItems)
    local out = {}
    if type(tasks) ~= "table" then return out end
    maxItems = tonumber(maxItems) or 6
    local count = 0
    for _, task in ipairs(tasks) do
        local lite = bgmd_liteTask(task)
        if lite then
            out[#out + 1] = lite
            count = count + 1
            if count >= maxItems then break end
        end
    end
    return out
end

local function bgmd_liteBrainTable(tbl, depth, maxItems)
    return bgmd_sanitizeValue(tbl, depth or 2, maxItems or 32, 96)
end

local function bgmd_makeClientBrain(id, brain)
    if type(brain) ~= "table" then return nil end

    local out = {}
    out.id = brain.id or id
    out.uid = bgmd_liteString(brain.uid or brain.persistentId, 64)
    out.persistentId = bgmd_liteString(brain.persistentId or brain.uid, 64)
    out.memberIndex = tonumber(brain.memberIndex)
    out.homeBase = bgmd_liteString(brain.homeBase, 64)
    out.permanent = brain.permanent == true
    out.inVehicle = brain.inVehicle == true
    out.female = brain.female == true
    out.born = tonumber(brain.born)
    out.bornCoords = bgmd_liteCoords(brain.bornCoords)
    out.debugCoords = bgmd_liteCoords(brain.debugCoords)
    out.x = tonumber(brain.x)
    out.y = tonumber(brain.y)
    out.z = tonumber(brain.z) or nil
    out.health = tonumber(brain.health)
    out.maxHealth = tonumber(brain.maxHealth)
    out.master = bgmd_litePrimitive(brain.master, 64)
    out.worldGroupId = bgmd_liteString(brain.worldGroupId or brain.groupId, 64)
    out.groupId = bgmd_liteString(brain.groupId or brain.worldGroupId, 64)
    out.worldDirector = brain.worldDirector == true
    out.roadPatrol = brain.roadPatrol == true
    out.roadBias = brain.roadBias == true
    out.preferRoads = brain.preferRoads == true
    out.patrolColor = bgmd_liteString(brain.patrolColor, 32)
    out.encounterId = bgmd_liteString(brain.encounterId, 64)
    out.inBattle = brain.inBattle == true
    out.virtualBattle = brain.virtualBattle == true
    out.battleId = bgmd_liteString(brain.battleId, 64)
    out.battleEnemyGroupId = bgmd_liteString(brain.battleEnemyGroupId, 64)
    out.fullname = bgmd_liteString(brain.fullname, 96)
    out.voice = bgmd_liteString(brain.voice, 48)
    out.hostile = brain.hostile == true
    out.friendly = brain.friendly == true
    out.skinTexture = bgmd_liteString(brain.skinTexture, 96)
    out.hairStyle = bgmd_liteString(brain.hairStyle, 96)
    out.hairColor = bgmd_liteBrainTable(brain.hairColor, 1, 8)
    out.beardStyle = bgmd_liteString(brain.beardStyle, 96)
    out.beardColor = bgmd_liteBrainTable(brain.beardColor, 1, 8)
    out.outfit = bgmd_liteString(brain.outfit, 96)
    out.clan = bgmd_liteString(brain.clan, 48)
    out.professionArchetype = bgmd_liteString(brain.professionArchetype, 64)
    out.professionCategory = bgmd_liteString(brain.professionCategory, 64)
    out.appearanceStyle = bgmd_liteString(brain.appearanceStyle, 64)
    out.cinematicAppearance = brain.cinematicAppearance == true
    out.eatBody = brain.eatBody == true
    out.accuracyBoost = tonumber(brain.accuracyBoost) or 1
    out.program = bgmd_liteProgram(brain.program)
    out.dna = bgmd_liteBrainTable(brain.dna, 1, 16)
    out.stationary = brain.stationary == true
    out.sleeping = brain.sleeping == true
    out.aiming = brain.aiming == true
    out.moving = brain.moving == true
    out.endurance = tonumber(brain.endurance) or 1.0
    out.speech = tonumber(brain.speech) or 0
    out.sound = tonumber(brain.sound) or 0
    out.infection = tonumber(brain.infection) or 0
    out.weapons = bgmd_liteWeapons(brain.weapons)
    out.currentWeapon = bgmd_liteCurrentWeapon(brain.currentWeapon)
    out.key = bgmd_litePrimitive(brain.key, 96)
    out.role = bgmd_liteString(brain.role, 48)
    out.tacticalRole = bgmd_liteString(brain.tacticalRole, 48)
    out.homeBaseId = bgmd_liteString(brain.homeBaseId, 64)
    out.relationshipToPlayer = bgmd_litePrimitive(brain.relationshipToPlayer, 64)
    out.factionSide = bgmd_liteString(brain.factionSide or brain.side, 32)
    out.faction = bgmd_liteString(brain.faction, 48)
    out.side = bgmd_liteString(brain.side, 32)
    out.factionState = bgmd_liteString(brain.factionState, 48)
    out.mercenary = brain.mercenary == true
    out.spy = brain.spy == true
    out.prisoner = brain.prisoner == true
    out.prisonerState = bgmd_liteString(brain.prisonerState, 48)
    out.prisonerForPlayerId = bgmd_liteString(brain.prisonerForPlayerId, 64)
    out.wounded = brain.wounded == true
    out.woundedDowned = brain.woundedDowned == true
    out.woundedState = bgmd_liteString(brain.woundedState, 48)
    out.loyalty = tonumber(brain.loyalty)
    out.morale = tonumber(brain.morale)
    out.tasks = bgmd_liteTasks(brain.tasks, 2)
    out.world = {}

    return out
end

local function bgmd_makeClientQueue(queue, maxItems, radius)
    local out = {}
    if type(queue) ~= "table" then return out end

    local count = 0
    maxItems = tonumber(maxItems) or 96
    radius = tonumber(radius) or 520
    for id, brain in pairs(queue) do
        if type(brain) == "table" then
            local x, y = bgmd_brainCoords(brain)
            if bgmd_nearAnyPlayer(x, y, radius) then
                local lite = bgmd_makeClientBrain(id, brain)
                if lite then
                    out[id] = lite
                    count = count + 1
                    if count >= maxItems then
                        break
                    end
                end
            end
        end
    end

    return out
end

local function bgmd_markerLite(marker)
    if type(marker) ~= "table" then return nil end
    local x = tonumber(marker.x)
    local y = tonumber(marker.y)
    if not x or not y then return nil end

    return {
        id = tostring(marker.id or marker.uid or marker.groupId or (tostring(x) .. "_" .. tostring(y))),
        markerType = marker.markerType,
        groupId = marker.groupId,
        x = x,
        y = y,
        z = tonumber(marker.z) or 0,
        name = marker.name,
        count = marker.count,
        hostile = marker.hostile,
        friendly = marker.friendly,
        factionSide = marker.factionSide,
        faction = marker.faction,
        side = marker.side,
        factionState = marker.factionState,
        program = marker.program,
        virtual = marker.virtual,
        active = marker.active,
        dead = marker.dead,
        state = marker.state,
        spawnClass = marker.spawnClass,
        roadPatrol = marker.roadPatrol,
        patrolColor = marker.patrolColor,
        encounterId = marker.encounterId,
        inBattle = marker.inBattle,
        battleId = marker.battleId,
        enemyGroupId = marker.enemyGroupId,
        battleCasualties = marker.battleCasualties,
        battleRemains = marker.battleRemains,
        loserGroupId = marker.loserGroupId,
        winnerGroupId = marker.winnerGroupId,
        spawnFailed = marker.spawnFailed,
        spawnFailCount = marker.spawnFailCount,
        spawnFailReason = marker.spawnFailReason,
        updatedAt = marker.updatedAt
    }
end

local function bgmd_makeClientMarkers(markers, maxItems)
    local out = {}
    if type(markers) ~= "table" then return out end

    local count = 0
    maxItems = tonumber(maxItems) or 220
    if NPCNetContract and NPCNetContract.DisableGMDMarkers then
        maxItems = 0
    end
    if maxItems <= 0 then return out end
    for id, marker in pairs(markers) do
        if type(marker) == "table" then
            local x = tonumber(marker.x)
            local y = tonumber(marker.y)
            if bgmd_nearAnyPlayer(x, y, 1800) or marker.markerType == "group" or marker.virtual then
                local lite = bgmd_markerLite(marker)
                if lite then
                    out[tostring(id)] = lite
                    count = count + 1
                    if count >= maxItems then
                        break
                    end
                end
            end
        end
    end

    return out
end

local function bgmd_groupLite(group)
    if type(group) ~= "table" or not group.id then return nil end

    return {
        id = tostring(group.id),
        x = tonumber(group.x),
        y = tonumber(group.y),
        z = tonumber(group.z) or 0,
        count = tonumber(group.count) or 0,
        hostile = group.hostile,
        friendly = group.friendly,
        factionSide = group.factionSide,
        faction = group.faction,
        side = group.side,
        activated = group.activated == true,
        virtual = group.virtual ~= false,
        physicalIds = bgmd_liteIdList(group.physicalIds, 32),
        state = group.state,
        spawnClass = group.spawnClass,
        roadPatrol = group.roadPatrol or false,
        roadBias = group.roadBias or false,
        preferRoads = group.preferRoads or false,
        patrolColor = group.patrolColor,
        encounterId = group.encounterId,
        inBattle = group.inBattle or false,
        battleId = group.battleId,
        enemyGroupId = group.enemyGroupId,
        battleCasualties = group.battleCasualties or 0,
        targetX = group.targetX,
        targetY = group.targetY,
        routeX = group.routeX,
        routeY = group.routeY,
        spawnFailed = group.spawnFailed,
        spawnFailCount = group.spawnFailCount,
        lastSpawnFailReason = group.lastSpawnFailReason,
        updatedAt = group.updatedAt
    }
end

local function bgmd_makeClientVirtualGroups(groups, maxItems)
    local out = {}
    if type(groups) ~= "table" then return out end

    local count = 0
    maxItems = tonumber(maxItems) or 90
    if NPCNetContract and NPCNetContract.DisableGMDVirtualGroups then
        maxItems = 0
    end
    if maxItems <= 0 then return out end
    for id, group in pairs(groups) do
        local lite = bgmd_groupLite(group)
        if lite then
            out[tostring(id)] = lite
            count = count + 1
            if count >= maxItems then
                break
            end
        end
    end

    return out
end

local function bgmd_worldDirectorLite(data)
    if type(data) ~= "table" then
        return {enabled=true, initialized=false, nextGroupId=1, lastUpdate=0, lastSpawn=0}
    end
    return {
        enabled = data.enabled ~= false,
        initialized = data.initialized == true,
        nextGroupId = tonumber(data.nextGroupId) or 1,
        lastUpdate = tonumber(data.lastUpdate) or 0,
        lastSpawn = tonumber(data.lastSpawn) or 0,
        lastBattleTick = tonumber(data.lastBattleTick) or nil,
        lastRoadPatrol = tonumber(data.lastRoadPatrol) or nil
    }
end

local function bgmd_rootSpecialKey(key)
    return key == "Queue"
        or key == "VirtualGroups"
        or key == "DebugMapMarkers"
        or key == "BattleRemains"
        or key == "Registry"
        or key == "RuntimeToUID"
        or key == "UIDToRuntime"
        or key == "DeadRegistry"
        or key == "PersistentNPCs"
        or key == "PersistentGroups"
        or key == "PersistentRuntimeToUID"
        or key == "PersistentUIDToRuntime"
        or key == "WorldDirector"
        or key == "TransmitStats"
end

local function bgmd_clearTable(tbl)
    local keys = {}
    for key, _ in pairs(tbl) do
        keys[#keys + 1] = key
    end
    for _, key in ipairs(keys) do
        tbl[key] = nil
    end
end

local function bgmd_backupAndClear(gmd)
    local backup = {}
    for key, value in pairs(gmd) do
        backup[key] = value
    end
    bgmd_clearTable(gmd)
    return backup
end

local function bgmd_restoreBackup(gmd, backup)
    bgmd_clearTable(gmd)
    for key, value in pairs(backup) do
        gmd[key] = value
    end
end

local function bgmd_fillGenericSnapshot(gmd, backup, mode)
    local genericDepth = tonumber(mode.genericDepth) or 0
    local genericMax = tonumber(mode.genericMax) or 0
    if genericDepth <= 0 or genericMax <= 0 then return end

    for key, value in pairs(backup) do
        if not bgmd_rootSpecialKey(key) then
            local lite = bgmd_sanitizeValue(value, genericDepth, genericMax, 128)
            if lite ~= nil then
                gmd[key] = lite
            end
        end
    end
end

local function bgmd_fillClientSnapshot(gmd, backup, mode)
    bgmd_clearTable(gmd)

    bgmd_fillGenericSnapshot(gmd, backup, mode)

    local queueMax = tonumber(mode.queueMax) or 0
    local queueRadius = tonumber(mode.queueRadius) or 520
    local markerMax = tonumber(mode.markerMax) or 0
    local groupMax = tonumber(mode.groupMax) or 0

    gmd.Queue = queueMax > 0 and bgmd_makeClientQueue(backup.Queue, queueMax, queueRadius) or {}
    gmd.VirtualGroups = groupMax > 0 and bgmd_makeClientVirtualGroups(backup.VirtualGroups, groupMax) or {}
    gmd.DebugMapMarkers = markerMax > 0 and bgmd_makeClientMarkers(backup.DebugMapMarkers, markerMax) or {}
    gmd.BattleRemains = {}
    gmd.Registry = {}
    gmd.RuntimeToUID = {}
    gmd.UIDToRuntime = {}
    gmd.DeadRegistry = {}
    gmd.PersistentNPCs = {}
    gmd.PersistentGroups = {}
    gmd.PersistentRuntimeToUID = {}
    gmd.PersistentUIDToRuntime = {}
    gmd.WorldDirector = bgmd_worldDirectorLite(backup.WorldDirector)
    gmd.TransmitStats = {
        mode = mode.name or "normal",
        queue = bgmd_tableCount(gmd.Queue),
        serverQueue = bgmd_tableCount(backup.Queue),
        virtualGroups = bgmd_tableCount(gmd.VirtualGroups),
        serverVirtualGroups = bgmd_tableCount(backup.VirtualGroups),
        markers = bgmd_tableCount(gmd.DebugMapMarkers),
        serverMarkers = bgmd_tableCount(backup.DebugMapMarkers),
        battleRemains = bgmd_tableCount(backup.BattleRemains)
    }
end

local function bgmd_logSafeTransmit(mode, message, data, critical)
    if NPCDiagnosticsBridge and NPCDiagnosticsBridge.Log then
        NPCDiagnosticsBridge.Log("SAFE_TRANSMIT", message, data, "safe-transmit-" .. tostring(mode or "mode"), critical == true)
    elseif critical then
        print(NPC_GMD_LOG_PREFIX .. " " .. tostring(message))
    end
end

local function bgmd_safeTransmitNPC()
    local gmd = NPCGlobalData.GetNPCModData()
    if type(gmd) ~= "table" then return end

    -- PZ serializes the whole GlobalModData table into one packet. The server-side
    -- The compatibility table may contain full brains, persistent profiles, debug markers,
    -- inventory snapshots and other nested data. Build a temporary client-only
    -- snapshot, transmit it, then restore the authoritative table in-place.
    local backup = bgmd_backupAndClear(gmd)
    local modes = {
        -- GlobalModData.transmit() serializes the table into one fixed packet and
        -- logs BufferOverflowException inside Java without reliably surfacing it to Lua.
        -- Keep the first packet small instead of depending on fallback retries.
        {name="normal", queueMax=48, queueRadius=480, markerMax=96, groupMax=60, genericDepth=0, genericMax=0},
        {name="reduced", queueMax=28, queueRadius=380, markerMax=40, groupMax=44, genericDepth=0, genericMax=0},
        {name="minimal", queueMax=12, queueRadius=300, markerMax=12, groupMax=24, genericDepth=0, genericMax=0}
    }

    local ok = false
    local err = nil
    local usedMode = nil

    for _, mode in ipairs(modes) do
        bgmd_fillClientSnapshot(gmd, backup, mode)
        local oldQueueCount = bgmd_tableCount(backup.Queue)
        local outQueueCount = bgmd_tableCount(gmd.Queue)
        if NPCDiagnosticsBridge and NPCDiagnosticsBridge.Log then
            if oldQueueCount > outQueueCount or mode.name ~= "normal" then
                NPCDiagnosticsBridge.Log("SAFE_TRANSMIT", "client " .. NPC_GMD_PAYLOAD_LABEL .. " prepared", {mode=mode.name, serverQueue=oldQueueCount, clientQueue=outQueueCount, virtualGroups=gmd.TransmitStats.virtualGroups, markers=gmd.TransmitStats.markers}, "safe-transmit-" .. mode.name, false)
            elseif NPCDiagnosticsBridge.VerboseEnabled and NPCDiagnosticsBridge.VerboseEnabled() then
                NPCDiagnosticsBridge.Verbose("SAFE_TRANSMIT", "client " .. NPC_GMD_PAYLOAD_LABEL .. " prepared", {mode=mode.name, serverQueue=oldQueueCount, clientQueue=outQueueCount, virtualGroups=gmd.TransmitStats.virtualGroups, markers=gmd.TransmitStats.markers}, "safe-transmit")
            end
        end

        ok, err = pcall(function()
            ModData.transmit(NPC_GMD_LEGACY_KEYS.data)
        end)
        if ok then
            usedMode = mode.name
            break
        end

        bgmd_logSafeTransmit(mode.name, "ModData.transmit failed; retrying with smaller " .. NPC_GMD_PAYLOAD_LABEL, {mode=mode.name, error=tostring(err)}, true)
    end

    bgmd_restoreBackup(gmd, backup)

    if not ok then
        print(NPC_GMD_LOG_PREFIX .. " Safe NPC ModData transmit failed after all retries: " .. tostring(err))
        bgmd_logSafeTransmit("failed", "ModData.transmit failed after all retries", {error=tostring(err)}, true)
    elseif usedMode and usedMode ~= "normal" then
        bgmd_logSafeTransmit(usedMode, "ModData.transmit succeeded with fallback payload", {mode=usedMode}, true)
    end
end

function NPCGlobalData.TransmitNPCModData()
    if isServer and isServer() then
        bgmd_safeTransmitNPC()
    else
        ModData.transmit(NPC_GMD_LEGACY_KEYS.data)
    end
end

function NPCGlobalData.TransmitNPCModDataPlayers()
    ModData.transmit(NPC_GMD_LEGACY_KEYS.players)
end

NPCGlobalData[NPC_GMD_LEGACY_FUNCTIONS.transmitModData] = function()
    return NPCGlobalData.TransmitNPCModData()
end

NPCGlobalData[NPC_GMD_LEGACY_FUNCTIONS.transmitModDataPlayers] = function()
    return NPCGlobalData.TransmitNPCModDataPlayers()
end

function NPCGlobalData.OnCreatePlayer(id)
    local player = nil
    if getSpecificPlayer then player = getSpecificPlayer(id) end
    bgmd_requestNPCSafeSync(player)
end
