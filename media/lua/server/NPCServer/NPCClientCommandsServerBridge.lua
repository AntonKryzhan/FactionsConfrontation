NPCClientCommandsServerBridge = NPCClientCommandsServerBridge or {}

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

local NPC_SERVER_RUNTIME_GLOBAL = NPCLegacyGlobalsBridge.ResolveLegacyName("ServerRuntime")
local NPC_SERVER_SIM_KEY = NPCLegacyContractBridge.Token .. "Sim"

if NPCClientCommandsServerBridge._loaded then
    NPCServerRuntime = NPCClientCommandsServerBridge.NPCServerRuntime or NPCServerRuntime
    NPCLegacyGlobalsBridge.InstallAlias("ServerRuntime", NPCServerRuntime or NPCClientCommandsServerBridge[NPC_SERVER_RUNTIME_GLOBAL], "NPCServerRuntime")
    return
end

NPCClientCommandsServerBridge._loaded = true

local legacyServerRuntime = NPCLegacyGlobalsBridge.Get("ServerRuntime")
NPCServerRuntime = NPCLegacyGlobalsBridge.InstallAlias("ServerRuntime", NPCServerRuntime or legacyServerRuntime, "NPCServerRuntime")
NPCServerRuntime.Commands = NPCServerRuntime.Commands or {}
NPCServerRuntime.Players = NPCServerRuntime.Players or {}
NPCServerRuntime.NPCSim = NPCServerRuntime.NPCSim or NPCServerRuntime[NPC_SERVER_SIM_KEY] or {}
NPCServerRuntime[NPC_SERVER_SIM_KEY] = NPCServerRuntime.NPCSim
NPCServerRuntime.NPCCommands = NPCServerRuntime.Commands
NPCServerRuntime.NPCPlayers = NPCServerRuntime.Players
NPCServerRuntime.NoAutoTransmitCommands = NPCServerRuntime.NoAutoTransmitCommands or {
    DebugMapRequest = true,
    DebugMapMaterializeNear = true,
    DebugMapUpdate = true,
    DebugMapRemove = true,
    AddEffect = true,
    DestroyObject = true,
    RequestSafeSync = true
}

local NPC_SERVER_LEGACY_PREFIX = NPCLegacyContractBridge.Token
local NPC_SERVER_LEGACY_KEYS = NPCLegacyContractBridge.Keys
local NPC_SERVER_LEGACY_COMMANDS = NPCLegacyContractBridge.Commands

local function bsc_stage448BoostWeaponAmmoSlot(slot, slotName, inBattle)
    if type(slot) ~= "table" or not slot.name or slot.name == false then return false end
    local magSize = math.floor(tonumber(slot.magSize) or 0)
    if magSize <= 0 then
        magSize = slotName == "secondary" and 15 or 30
        slot.magSize = magSize
    end
    local minMags = slotName == "secondary" and 10 or 14
    if inBattle == true then minMags = minMags + 8 end
    local currentMags = math.floor(tonumber(slot.magCount) or 0)
    if currentMags < minMags then slot.magCount = minMags end
    local bulletsLeft = math.floor(tonumber(slot.bulletsLeft) or 0)
    if bulletsLeft < math.max(1, math.floor(magSize * 0.75)) then slot.bulletsLeft = magSize end
    slot.stage448AmmoBoost = true
    return true
end

local function bsc_stage448BoostBrainAmmo(brain, event)
    if type(brain) ~= "table" then return false end
    if brain.blackMarket == true or brain.blackMarketNPC == true or brain.special == "BlackMarket" then return false end
    if type(brain.weapons) ~= "table" then return false end
    local inBattle = brain.inBattle == true or brain.virtualBattle == true or (event and (event.inBattle == true or event.virtualBattle == true))
    local changed = false
    if bsc_stage448BoostWeaponAmmoSlot(brain.weapons.primary, "primary", inBattle) then changed = true end
    if bsc_stage448BoostWeaponAmmoSlot(brain.weapons.secondary, "secondary", inBattle) then changed = true end
    if changed then
        brain.stage448AmmoBoosted = true
        brain.stage448AmmoBoostedAt = getGameTime and getGameTime():getWorldAgeHours() or 0
    end
    return changed
end

require "NPCServer/NPCServerCommandBridge"
require "NPCServer/NPCWorldObjectCommandBridge"

local NPCServerEnsureWorldTables
local NPCServerGetQueueKey
local NPCServerSendDebugMap
local NPCServerSetDebugMarker
local NPCServerRemoveDebugMarker
local NPCServerGetWorldGroupId
local NPCServerRefreshWorldGroupMarker
local bsc_updateMercenaryMarker
local bsc_updateRuntimeDebugMarker
local bsc_refreshPhysicalGroupMarkerThrottled

local function bsc_cleanGroupDisplayName(name, groupId)
    if name == nil then return nil end
    local text = tostring(name or "")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    if text == "" or text == "nil" or text == "false" then return nil end
    local gid = tostring(groupId or "")
    if gid ~= "" and text == gid then return nil end
    if string.match(text, "^P%d+%s+BBC%d+$") or string.match(text, "^BBC%d+$") or string.match(text, "^WG%d+$") or string.match(text, "^CP%d+$") or string.match(text, "^SG%d+$") then return nil end
    text = string.gsub(text, "%s+P%d+%s+BBC%d+$", "")
    text = string.gsub(text, "%s+BBC%d+$", "")
    text = string.gsub(text, "%s+WG%d+$", "")
    text = string.gsub(text, "%s+CP%d+$", "")
    text = string.gsub(text, "%s+SG%d+$", "")
    if gid ~= "" then text = string.gsub(text, "%s+" .. gid .. "$", "") end
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    if text == "" or string.match(text, "^NPC Group%s*") then return nil end
    return text
end

local function bsc_groupDisplayName(groupId, group, preferred)
    if NPCWorldDirectorBridge and NPCWorldDirectorBridge.GetVirtualGroupDisplayName then
        local ok, name = pcall(function() return NPCWorldDirectorBridge.GetVirtualGroupDisplayName(groupId, group, preferred) end)
        if ok and name and tostring(name) ~= "" then return name end
    end
    local cleaned = bsc_cleanGroupDisplayName(preferred or (group and group.name), groupId)
    if cleaned then return cleaned end
    local side = tostring(group and (group.factionSide or group.side or group.faction or group.patrolColor) or "")
    side = string.lower(side)
    local sideLabel = side == "red" and "Red" or side == "blue" and "Blue" or "Green"
    if group and (group.mercenary or group.mercenaryElite or sideLabel == "Blue") then
        if group.mercenaryHired then return "Hired blue mercenaries" end
        return "Blue mercenaries"
    end
    if group and (group.checkpointId or group.targetClass == "checkpoint_road_patrol" or group.state == "checkpoint_patrol") then return sideLabel .. " checkpoint patrol" end
    if group and group.roadPatrol then return sideLabel .. " road patrol" end
    if group and (group.homeBaseId or group.state == "base_patrol" or group.targetClass == "base_guard") then return sideLabel .. " base patrol" end
    return sideLabel .. " patrol"
end

local function bsc_playerId(player)
    return NPCServerCommandBridge.PlayerId(player)
end

local function bsc_say(player, text)
    return NPCServerCommandBridge.Say(player, text)
end

local function bsc_logMercenary(text)
    return NPCServerCommandBridge.LogMercenary(text)
end

local function bsc_sendMercenaryHireResult(player, ok, message, args)
    return NPCServerCommandBridge.SendMercenaryHireResult(player, ok, message, args)
end

local function bsc_writeNPCServiceIds(zombie, brain, worldGroupId)
    if not (zombie and brain) then return end

    local runtimeId = brain.id
    local persistentId = brain.persistentId or brain.uid
    local groupId = worldGroupId or brain.worldGroupId or brain.groupId
    local programName = brain.program and brain.program.name or brain.programName
    local md = zombie:getModData()

    if md then
        md[NPC_SERVER_LEGACY_KEYS.isNPC] = true
        md[NPC_SERVER_LEGACY_KEYS.formerNPCZombie] = false
        if runtimeId ~= nil then md[NPC_SERVER_LEGACY_KEYS.runtimeId] = tostring(runtimeId) end
        if persistentId ~= nil then md[NPC_SERVER_LEGACY_KEYS.persistentId] = tostring(persistentId) end
        if groupId ~= nil then md[NPC_SERVER_LEGACY_KEYS.worldGroupId] = tostring(groupId) end
        if programName ~= nil then md[NPC_SERVER_LEGACY_KEYS.program] = tostring(programName) end
    end

    if brain.blackMarket == true or brain.blackMarketNPC == true then
        if md then
            md.NPCBlackMarketBridge = true
            md.BlackMarketNPC = true
            md.BlackMarketId = tostring(brain.blackMarketId or persistentId or runtimeId or "")
            md.BlackMarketRuntimeId = runtimeId and tostring(runtimeId) or nil
        end
        pcall(function() zombie:setVariable(NPC_SERVER_LEGACY_KEYS.blackMarket, true) end)
        pcall(function() zombie:setVariable("BlackMarketId", tostring(brain.blackMarketId or persistentId or runtimeId or "")) end)
    end

    if runtimeId ~= nil then pcall(function() zombie:setVariable(NPC_SERVER_LEGACY_KEYS.runtimeId, tostring(runtimeId)) end) end
    if persistentId ~= nil then pcall(function() zombie:setVariable(NPC_SERVER_LEGACY_KEYS.persistentId, tostring(persistentId)) end) end
    if groupId ~= nil then pcall(function() zombie:setVariable(NPC_SERVER_LEGACY_KEYS.worldGroupId, tostring(groupId)) end) end
    if programName ~= nil then pcall(function() zombie:setVariable(NPC_SERVER_LEGACY_KEYS.program, tostring(programName)) end) end
end

NPCServerRuntime.Commands.RequestSafeSync = function(player, args)
    if NPCWorldDirector and NPCWorldDirector.RevirtualizePersistedRuntimeState then
        NPCWorldDirector.RevirtualizePersistedRuntimeState()
    end
    if NPCWorldDirectorBridge and NPCWorldDirectorBridge.CleanupLoadedPersistedRuntimeObjects and NPCWorldDirector then
        pcall(function() NPCWorldDirectorBridge.CleanupLoadedPersistedRuntimeObjects(NPCWorldDirector, "safe_sync_persistent_runtime_cleanup") end)
    end
    if TransmitNPCModData then
        TransmitNPCModData()
    end
end

NPCServerRuntime.NetGuard = NPCServerRuntime.NetGuard or {last={}, dropped=0, lastPrune=0}

local function bsc_nowMs()
    return NPCServerCommandBridge.NowMs()
end

local function bsc_mercenaryTelemetryText(args, serverReceiveMs)
    if type(args) ~= "table" then return "" end
    local parts = {}
    if args.clientTraceId ~= nil then parts[#parts + 1] = "trace=" .. tostring(args.clientTraceId) end
    if args.clientEvent ~= nil then parts[#parts + 1] = "event=" .. tostring(args.clientEvent) end
    local clientSendMs = tonumber(args.clientSendMs)
    if clientSendMs then
        parts[#parts + 1] = "clientSendMs=" .. tostring(clientSendMs)
        local recv = tonumber(serverReceiveMs)
        if recv and recv > 0 then parts[#parts + 1] = "clientToServerMs=" .. tostring(math.floor(recv - clientSendMs)) end
    end
    if args.clientOrderSeq ~= nil then parts[#parts + 1] = "clientSeq=" .. tostring(args.clientOrderSeq) end
    if #parts == 0 then return "" end
    return " " .. table.concat(parts, " ")
end

local function bsc_worldAgeHours()
    if getGameTime then
        local ok, value = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok then return tonumber(value) or 0 end
    end
    return 0
end

local function bsc_markMercenaryHireStabilized(group, player, changed)
    if type(group) ~= "table" then return end
    local now = bsc_worldAgeHours()
    local graceSeconds = 8
    group._mercenaryHireGraceUntil = now + (graceSeconds / 3600)
    group._lastMercenaryLeashForceAt = nil
    group._mercenaryLeashCleanupUntil = nil
    if player then
        group._lastFollowPlayerX = tonumber(player:getX()) or group._lastFollowPlayerX
        group._lastFollowPlayerY = tonumber(player:getY()) or group._lastFollowPlayerY
        group._lastFollowPlayerZ = math.floor(tonumber(player:getZ()) or group._lastFollowPlayerZ or 0)
    end
    if tonumber(changed) and tonumber(changed) > 0 then
        group.activated = true
        group.virtual = false
        group.spawnPending = false
        group.spawnQueued = 0
        group.spawnFailed = false
        group.retryAfter = nil
        group.lastSpawnFailReason = nil
        group.forceMercenaryLeashMaterialize = nil
        group.state = "physical"
    end
    group.updatedAt = now
end

local function bsc_settingBool(name, defaultValue)
    return NPCServerCommandBridge.SettingBool(name, defaultValue)
end

local function bsc_settingNumber(name, defaultValue, minValue, maxValue)
    return NPCServerCommandBridge.SettingNumber(name, defaultValue, minValue, maxValue)
end

local function bsc_safeCommandString(value, maxLen)
    return NPCServerCommandBridge.SafeString(value, maxLen)
end

local function bsc_sanitizeCommandValue(value, depth, maxDepth, maxFields, maxString)
    return NPCServerCommandBridge.SanitizeValue(value, depth, maxDepth, maxFields, maxString)
end

local function bsc_sanitizeCommandArgs(args, module, command)
    return NPCServerCommandBridge.SanitizeArgs(args, module, command)
end

local function bsc_commandCooldownMs(module, command, args)
    return NPCServerCommandBridge.CommandCooldownMs(module, command, args)
end

local function bsc_pruneNetGuard(now)
    return NPCServerCommandBridge.PruneNetGuard(NPCServerRuntime, now)
end

local function bsc_rateLimitKey(module, command, player, args)
    return NPCServerCommandBridge.RateLimitKey(module, command, player, args)
end

local function bsc_commandAllowed(module, command, player, args)
    return NPCServerCommandBridge.CommandAllowed(NPCServerRuntime, module, command, player, args)
end

local function bsc_groupIdOf(brain)
    if not brain then return nil end
    local groupId = brain.worldGroupId or brain.groupId
    if groupId then return tostring(groupId) end
    return nil
end

local function bsc_queueKeyForBrain(gmd, id)
    if not id then return nil end
    if gmd and gmd.Queue and gmd.Queue[id] then return id end
    if gmd and gmd.Queue and gmd.Queue[tostring(id)] then return tostring(id) end
    if NPCServerGetQueueKey then return NPCServerGetQueueKey(gmd, id) end
    return tostring(id)
end

local function bsc_nonEmptyId(value)
    if value == nil then return nil end
    local sid = tostring(value)
    if sid == "" or sid == "nil" or sid == "false" then return nil end
    return sid
end

local function bsc_addIdCandidate(list, seen, value)
    local sid = bsc_nonEmptyId(value)
    if not sid or seen[sid] then return end
    seen[sid] = true
    list[#list + 1] = sid
end

local function bsc_hireIdCandidates(args)
    local list = {}
    local seen = {}
    if type(args) == "table" then
        bsc_addIdCandidate(list, seen, args.id)
        bsc_addIdCandidate(list, seen, args.runtimeId)
        bsc_addIdCandidate(list, seen, args.brainId)
        bsc_addIdCandidate(list, seen, args.uid)
        bsc_addIdCandidate(list, seen, args.persistentId)
        bsc_addIdCandidate(list, seen, args.zombieId)
    else
        bsc_addIdCandidate(list, seen, args)
    end
    return list
end

local function bsc_brainMatchesIds(brain, qid, ids)
    if type(brain) ~= "table" or type(ids) ~= "table" then return false end
    local values = {
        qid,
        brain.id,
        brain.runtimeId,
        brain.uid,
        brain.persistentId,
        brain[NPC_SERVER_LEGACY_KEYS.runtimeId],
        brain[NPC_SERVER_LEGACY_KEYS.persistentId]
    }
    for _, value in ipairs(values) do
        local sid = bsc_nonEmptyId(value)
        if sid then
            for _, candidate in ipairs(ids) do
                if sid == tostring(candidate) then return true end
            end
        end
    end
    return false
end

local function bsc_brainDistanceSq(brain, x, y, z)
    if type(brain) ~= "table" or not x or not y then return nil end
    local bx = tonumber(brain.x) or (brain.debugCoords and tonumber(brain.debugCoords.x)) or (brain.bornCoords and tonumber(brain.bornCoords.x))
    local by = tonumber(brain.y) or (brain.debugCoords and tonumber(brain.debugCoords.y)) or (brain.bornCoords and tonumber(brain.bornCoords.y))
    local bz = tonumber(brain.z) or (brain.debugCoords and tonumber(brain.debugCoords.z)) or (brain.bornCoords and tonumber(brain.bornCoords.z)) or 0
    if not (bx and by) then return nil end
    if z ~= nil and math.abs((tonumber(z) or 0) - bz) > 1.0 then return nil end
    local dx = bx - x
    local dy = by - y
    return dx * dx + dy * dy
end

local function bsc_safeZombieId(zombie)
    if not zombie then return nil end
    if NPCUtils and NPCUtils.GetCharacterID then
        local ok, id = pcall(function() return NPCUtils.GetCharacterID(zombie) end)
        if ok and id ~= nil then return id end
    end
    if zombie.getOnlineID then
        local ok, id = pcall(function() return zombie:getOnlineID() end)
        if ok and id ~= nil then return id end
    end
    return nil
end

local function bsc_physicalZombieMatches(zombie, brain, ids, groupId, x, y, z)
    if not zombie then return false end
    if brain and bsc_brainMatchesIds(brain, bsc_safeZombieId(zombie), ids) then return true end

    local zmd = zombie.getModData and zombie:getModData() or nil
    if zmd then
        local values = {zmd[NPC_SERVER_LEGACY_KEYS.runtimeId], zmd[NPC_SERVER_LEGACY_KEYS.persistentId], zmd[NPC_SERVER_LEGACY_KEYS.worldGroupId], zmd.uid, zmd.persistentId}
        for _, value in ipairs(values) do
            local sid = bsc_nonEmptyId(value)
            if sid then
                if groupId and sid == tostring(groupId) then return true end
                for _, candidate in ipairs(ids or {}) do
                    if sid == tostring(candidate) then return true end
                end
            end
        end
    end

    if groupId and brain and bsc_groupIdOf(brain) and tostring(bsc_groupIdOf(brain)) == tostring(groupId) then return true end

    if x and y and zombie.getX and zombie.getY then
        local zx = tonumber(zombie:getX())
        local zy = tonumber(zombie:getY())
        local zz = zombie.getZ and tonumber(zombie:getZ()) or 0
        if zx and zy and (z == nil or math.abs((tonumber(z) or 0) - (zz or 0)) <= 1.0) then
            local dx = zx - x
            local dy = zy - y
            return (dx * dx + dy * dy) <= 36
        end
    end

    return false
end

local function bsc_findPhysicalBrainFromCommand(gmd, args)
    if not (gmd and type(args) == "table") then return nil, nil, nil end
    local cell = getCell and getCell() or nil
    local list = cell and cell.getZombieList and cell:getZombieList() or nil
    if not (list and list.size and list.get) then return nil, nil, nil end

    local ids = bsc_hireIdCandidates(args)
    local groupId = bsc_nonEmptyId(args.groupId or args.worldGroupId)
    local x = tonumber(args.x)
    local y = tonumber(args.y)
    local z = tonumber(args.z)
    local bestZombie = nil
    local bestBrain = nil
    local bestKey = nil
    local bestDist = 999999

    local size = 0
    local okSize, gotSize = pcall(function() return list:size() end)
    if okSize then size = tonumber(gotSize) or 0 end

    for i = 0, size - 1 do
        local okGet, zombie = pcall(function() return list:get(i) end)
        if okGet and zombie and zombie.getVariableBoolean and zombie:getVariableBoolean(NPC_SERVER_LEGACY_KEYS.liveFlag) then
            local brain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(zombie) or nil
            if brain and bsc_physicalZombieMatches(zombie, brain, ids, groupId, x, y, z) then
                local dist = 0
                if x and y and zombie.getX and zombie.getY then
                    local dx = (tonumber(zombie:getX()) or x) - x
                    local dy = (tonumber(zombie:getY()) or y) - y
                    dist = dx * dx + dy * dy
                end
                if dist < bestDist then
                    bestDist = dist
                    bestZombie = zombie
                    bestBrain = brain
                    bestKey = bsc_safeZombieId(zombie) or brain.id or brain.runtimeId or args.id
                end
            end
        end
    end

    if not bestBrain then return nil, nil, nil end
    bestKey = bsc_nonEmptyId(bestKey or bestBrain.id or args.id) or tostring(bestZombie)
    bestBrain.id = bestBrain.id or bestKey
    local qkey = bsc_queueKeyForBrain(gmd, bestKey) or bestKey
    if gmd.Queue then gmd.Queue[qkey] = bestBrain end
    return qkey, bestBrain, bestZombie
end

local function bsc_findBrainFromCommand(gmd, args)
    if not (gmd and gmd.Queue and type(args) == "table") then return nil, nil end
    local ids = bsc_hireIdCandidates(args)

    for _, id in ipairs(ids) do
        local key = bsc_queueKeyForBrain(gmd, id)
        if key and gmd.Queue[key] then return key, gmd.Queue[key] end
    end

    for qid, brain in pairs(gmd.Queue) do
        if bsc_brainMatchesIds(brain, qid, ids) then return qid, brain end
    end

    local groupId = bsc_nonEmptyId(args.groupId or args.worldGroupId)
    if groupId then
        for qid, brain in pairs(gmd.Queue) do
            if bsc_groupIdOf(brain) and tostring(bsc_groupIdOf(brain)) == groupId then return qid, brain end
        end
    end

    local x = tonumber(args.x)
    local y = tonumber(args.y)
    local z = tonumber(args.z)
    if x and y then
        local bestKey = nil
        local bestBrain = nil
        local bestDist = 999999
        for qid, brain in pairs(gmd.Queue) do
            local dist = bsc_brainDistanceSq(brain, x, y, z)
            if dist and dist < bestDist and dist <= 25 then
                bestKey = qid
                bestBrain = brain
                bestDist = dist
            end
        end
        if bestKey then return bestKey, bestBrain end
    end

    return nil, nil
end

local function bsc_groupFromCommand(gmd, args, brain)
    if not (gmd and type(args) == "table") then return nil, nil end
    local groupId = bsc_nonEmptyId(args.groupId or args.worldGroupId or bsc_groupIdOf(brain))
    if not groupId then return nil, nil end
    if gmd.VirtualGroups then
        if gmd.VirtualGroups[groupId] then return groupId, gmd.VirtualGroups[groupId] end
        for gid, group in pairs(gmd.VirtualGroups) do
            if group and tostring(group.id or group.groupId or group.worldGroupId or gid) == groupId then return tostring(gid), group end
        end
    end
    return groupId, nil
end

local function bsc_npcMarkerId(id)
    if id == nil then return nil end
    local sid = tostring(id)
    if sid == "" or sid == "nil" then return nil end
    if string.sub(sid, 1, 4) == "npc:" then return sid end
    return "npc:" .. sid
end

local function bsc_runtimeIdFromMarkerId(id)
    if id == nil then return nil end
    local sid = tostring(id)
    if string.sub(sid, 1, 4) == "npc:" then return string.sub(sid, 5) end
    return sid
end

local function bsc_isNpcMarker(marker)
    return type(marker) == "table" and tostring(marker.markerType or "") == "npc"
end

local function bsc_getNpcDebugMarker(gmd, id, brain)
    if not (gmd and gmd.DebugMapMarkers) then return nil, nil end

    local ids = {}
    if id ~= nil then ids[#ids + 1] = id end
    if brain then
        if brain.id ~= nil then ids[#ids + 1] = brain.id end
        if brain.runtimeId ~= nil then ids[#ids + 1] = brain.runtimeId end
        if brain.uid ~= nil then ids[#ids + 1] = brain.uid end
        if brain.persistentId ~= nil then ids[#ids + 1] = brain.persistentId end
    end

    for _, candidate in ipairs(ids) do
        local npcId = bsc_npcMarkerId(candidate)
        if npcId then
            local marker = gmd.DebugMapMarkers[npcId]
            if bsc_isNpcMarker(marker) then return marker, npcId end
        end
    end

    for _, candidate in ipairs(ids) do
        local legacyId = tostring(candidate)
        local marker = gmd.DebugMapMarkers[legacyId]
        if bsc_isNpcMarker(marker) then return marker, legacyId end
    end

    return nil, nil
end

local function bsc_removeLegacyNpcMarker(gmd, legacyId, keepId)
    if not (gmd and gmd.DebugMapMarkers and legacyId) then return end
    legacyId = tostring(legacyId)
    if legacyId == "" or legacyId == "nil" or legacyId == tostring(keepId or "") then return end

    local marker = gmd.DebugMapMarkers[legacyId]
    if bsc_isNpcMarker(marker) then
        gmd.DebugMapMarkers[legacyId] = nil
        NPCServerSendDebugMap('Remove', {id=legacyId})
    end
end

local function bsc_brainGroupId(brain)
    if not brain then return nil end
    return brain.worldGroupId or brain.groupId
end

local function bsc_brainSide(brain)
    if NPCFactionBridge and NPCFactionBridge.GetBrainSide then
        return NPCFactionBridge.GetBrainSide(brain)
    end
    return brain and (brain.factionSide or brain.faction or brain.side or brain.patrolColor)
end

local function bsc_distanceSqFromPlayerToCoords(player, x, y, z)
    if not (player and player.getX and player.getY and x and y) then return nil end
    local px = tonumber(player:getX())
    local py = tonumber(player:getY())
    local pz = player.getZ and tonumber(player:getZ()) or 0
    x = tonumber(x)
    y = tonumber(y)
    z = tonumber(z) or 0
    if not (px and py and x and y) then return nil end
    if math.abs((pz or 0) - (z or 0)) > 2.0 then return nil end
    local dx = x - px
    local dy = y - py
    return dx * dx + dy * dy
end

local function bsc_brainCoords(brain)
    if type(brain) ~= "table" then return nil, nil, nil end
    local x = tonumber(brain.x) or (brain.debugCoords and tonumber(brain.debugCoords.x)) or (brain.bornCoords and tonumber(brain.bornCoords.x))
    local y = tonumber(brain.y) or (brain.debugCoords and tonumber(brain.debugCoords.y)) or (brain.bornCoords and tonumber(brain.bornCoords.y))
    local z = tonumber(brain.z) or (brain.debugCoords and tonumber(brain.debugCoords.z)) or (brain.bornCoords and tonumber(brain.bornCoords.z)) or 0
    return x, y, z
end

local function bsc_groupCoords(group)
    if type(group) ~= "table" then return nil, nil, nil end
    local x = tonumber(group.x) or tonumber(group.cx) or tonumber(group.targetX) or tonumber(group.homeX)
    local y = tonumber(group.y) or tonumber(group.cy) or tonumber(group.targetY) or tonumber(group.homeY)
    local z = tonumber(group.z) or tonumber(group.cz) or tonumber(group.targetZ) or tonumber(group.homeZ) or 0
    return x, y, z
end

local function bsc_zombieCoords(zombie)
    if not (zombie and zombie.getX and zombie.getY) then return nil, nil, nil end
    local ok, x, y, z = pcall(function()
        return tonumber(zombie:getX()), tonumber(zombie:getY()), zombie.getZ and tonumber(zombie:getZ()) or 0
    end)
    if ok then return x, y, z end
    return nil, nil, nil
end

local function bsc_hireTargetNearPlayer(player, targetBrain, targetZombie, group)
    local physicalMax = 18
    local groupMax = 32

    local zx, zy, zz = bsc_zombieCoords(targetZombie)
    local dist = bsc_distanceSqFromPlayerToCoords(player, zx, zy, zz)
    if dist and dist <= physicalMax * physicalMax then return true end

    local bx, by, bz = bsc_brainCoords(targetBrain)
    dist = bsc_distanceSqFromPlayerToCoords(player, bx, by, bz)
    if dist and dist <= physicalMax * physicalMax then return true end

    local gx, gy, gz = bsc_groupCoords(group)
    dist = bsc_distanceSqFromPlayerToCoords(player, gx, gy, gz)
    if dist and dist <= groupMax * groupMax then return true end

    return false
end

local function bsc_mercenaryPointAnchorNearPlayer(player, anchor)
    if not (player and type(anchor) == "table") then return false end
    local maxDist = 220
    local maxZDelta = 4
    local ax = tonumber(anchor.x)
    local ay = tonumber(anchor.y)
    local az = tonumber(anchor.z) or 0
    if not ax or not ay then return false end

    local dist = bsc_distanceSqFromPlayerToCoords(player, ax, ay, az)
    if not dist or dist > maxDist * maxDist then return false end

    if player.getZ then
        local ok, pz = pcall(function() return tonumber(player:getZ()) or 0 end)
        if ok and pz and math.abs(az - pz) > maxZDelta then return false end
    end

    return true
end


local function bsc_anchorSquareIsInsideBuilding(anchor)
    if not (type(anchor) == "table" and anchor.x and anchor.y) then return false end
    if not getCell then return false end
    local cell = getCell()
    if not (cell and cell.getGridSquare) then return false end
    local okSquare, square = pcall(function() return cell:getGridSquare(math.floor(tonumber(anchor.x) or 0), math.floor(tonumber(anchor.y) or 0), math.floor(tonumber(anchor.z) or 0)) end)
    if not (okSquare and square) then return false end
    if square.getRoom then
        local okRoom, room = pcall(function() return square:getRoom() end)
        if okRoom and room ~= nil then return true end
    end
    if square.getBuilding then
        local okBuilding, building = pcall(function() return square:getBuilding() end)
        if okBuilding and building ~= nil then return true end
    end
    return false
end

local function bsc_serverAllowsMercenaryHire(targetBrain, group, pid)
    local owner = pid and tostring(pid) or nil
    if owner then
        if targetBrain and targetBrain.mercenaryHiredBy and tostring(targetBrain.mercenaryHiredBy) == owner then return true end
        if group and group.mercenaryHiredBy and tostring(group.mercenaryHiredBy) == owner then return true end
    end

    local brainSide = bsc_brainSide(targetBrain)
    local groupSide = group and (group.factionSide or group.faction or group.side or group.patrolColor) or nil
    local side = string.lower(tostring(brainSide or groupSide or ""))

    if side == "blue" then return true end
    if targetBrain and (targetBrain.mercenary == true or targetBrain.mercenaryElite == true) then return true end
    if group and (group.mercenary == true or group.mercenaryElite == true or group.hireable == true or group.recruitable == true) then return true end

    return false
end


local function bsc_syncProgramBrain(id, brain)
    if not (id and brain) then return end
    sendServerCommand('NPCCommands', NPC_SERVER_LEGACY_COMMANDS.updatePart, {
        id = brain.id or id,
        master = brain.master,
        hostile = brain.hostile,
        program = brain.program,
        order = brain.order,
        fireMode = brain.order and brain.order.fireMode or brain.fireMode,
        rbFireMode = brain.rbFireMode,
        tasks = brain.tasks,
        relationshipToPlayer = brain.relationshipToPlayer,
        factionSide = brain.factionSide,
        faction = brain.faction,
        side = brain.side,
        patrolColor = brain.patrolColor,
        clan = brain.clan
    })
end

local function bsc_updateNeutralCompanionMarker(gmd, id, brain)
    if not (gmd and id and brain) then return end
    if not gmd.DebugMapMarkers then gmd.DebugMapMarkers = {} end
    local markerId = bsc_npcMarkerId(id)
    if not markerId then return end
    local marker, oldMarkerId = bsc_getNpcDebugMarker(gmd, id, brain)
    if not marker then return end

    local programName = brain.program and brain.program.name or nil
    marker.id = markerId
    marker.markerType = "npc"
    marker.runtimeId = tostring(id)
    marker.groupId = bsc_brainGroupId(brain) or marker.groupId
    marker.worldGroupId = marker.groupId
    if oldMarkerId then bsc_removeLegacyNpcMarker(gmd, oldMarkerId, markerId) end
    marker.hostile = brain.hostile == true
    marker.friendly = programName == "Companion" or programName == "CompanionGuard"
    marker.isPlayerGuard = marker.friendly == true
    marker.master = brain.master
    marker.program = programName or marker.program
    marker.relationshipToPlayer = brain.relationshipToPlayer
    marker.factionSide = brain.factionSide or marker.factionSide
    marker.faction = brain.faction or marker.faction
    marker.side = brain.side or marker.side
    marker.patrolColor = brain.patrolColor or marker.patrolColor
    if NPCLoyaltyBridge and NPCLoyaltyBridge.MarkerFields then
        NPCLoyaltyBridge.MarkerFields(marker, brain)
    end
    if NPCLeadersBridge and NPCLeadersBridge.MarkerFields then
        NPCLeadersBridge.MarkerFields(marker, brain)
    end
    marker.updatedAt = getGameTime():getWorldAgeHours()
    NPCServerSetDebugMarker(gmd, marker)
end

local function bsc_applyNeutralProgram(brain, player, program)
    if type(brain) ~= "table" then return brain end
    local pid = bsc_playerId(player)
    program = tostring(program or "")

    brain.tasks = {}
    if brain.fsm then
        brain.fsm.targetId = nil
        brain.fsm.targetKind = nil
        brain.fsm.currentThreat = nil
        brain.fsm.lastThreat = nil
    end
    brain.currentThreat = nil
    brain.lastThreat = nil
    brain.targetId = nil
    brain.targetKind = nil

    if program == "Companion" or program == "CompanionGuard" then
        brain.master = pid
        brain.hostile = false
        brain.relationshipToPlayer = "companion"
        brain.program = {name=program, stage="Prepare"}
        brain.order = brain.order or {}
        brain.order.name = program == "CompanionGuard" and "Guard" or "Follow"
        brain.order.source = "neutral_join"
        brain.order.master = pid
        brain.order.priority = 90
        brain.order.fireMode = brain.order.fireMode or "Defensive"
        brain.order.formation = brain.order.formation or "close"
        brain.order.followDistance = brain.order.followDistance or 3.0
        brain.fireMode = brain.order.fireMode
        brain.rbFireMode = brain.fireMode
    else
        brain.master = false
        brain.relationshipToPlayer = "neutral"
        brain.program = {name="Looter", stage="Prepare"}
        brain.order = false
        brain.fireMode = false
        brain.rbFireMode = false
    end

    return brain
end

local function bsc_syncMercenaryBrain(id, brain)
    if not (id and brain) then return end
    sendServerCommand('NPCCommands', NPC_SERVER_LEGACY_COMMANDS.updatePart, {
        id = brain.id or id,
        master = brain.master,
        hostile = brain.hostile,
        program = brain.program,
        order = brain.order,
        fireMode = brain.order and brain.order.fireMode or brain.fireMode,
        rbFireMode = brain.rbFireMode,
        tasks = brain.tasks,
        weapons = brain.weapons,
        inventory = brain.inventory,
        loot = brain.loot,
        health = brain.health,
        maxHealth = brain.maxHealth,
        role = brain.role,
        tacticalRole = brain.tacticalRole,
        relationshipToPlayer = brain.relationshipToPlayer,
        factionSide = brain.factionSide,
        faction = brain.faction,
        side = brain.side,
        patrolColor = brain.patrolColor,
        factionState = brain.factionState,
        mercenary = brain.mercenary,
        mercenaryElite = brain.mercenaryElite,
        mercenaryHired = brain.mercenaryHired,
        mercenaryHiredBy = brain.mercenaryHiredBy,
        mercenaryHiredByName = brain.mercenaryHiredByName,
        isPlayerGuard = brain.isPlayerGuard,
        followPlayer = brain.followPlayer,
        guardPlayer = brain.guardPlayer,
        spy = brain.spy,
        spyForPlayerId = brain.spyForPlayerId,
        spyForPlayerName = brain.spyForPlayerName,
        spyOriginalSide = brain.spyOriginalSide,
        spyBribedAt = brain.spyBribedAt,
        spyState = brain.spyState,
        spyDefected = brain.spyDefected,
        spyDefectedAt = brain.spyDefectedAt,
        spySabotage = brain.spySabotage,
        spyAlliedGroup = brain.spyAlliedGroup,
        spyPaymentKind = brain.spyPaymentKind,
        prisoner = brain.prisoner,
        prisonerForPlayerId = brain.prisonerForPlayerId,
        prisonerForPlayerName = brain.prisonerForPlayerName,
        prisonerOriginalSide = brain.prisonerOriginalSide,
        prisonerTakenAt = brain.prisonerTakenAt,
        prisonerReleasedAt = brain.prisonerReleasedAt,
        prisonerInterrogatedAt = brain.prisonerInterrogatedAt,
        prisonerIntelCount = brain.prisonerIntelCount,
        prisonerState = brain.prisonerState,
        wounded = brain.wounded,
        woundedDowned = brain.woundedDowned,
        woundedState = brain.woundedState,
        woundedForPlayerId = brain.woundedForPlayerId,
        woundedExpiresAt = brain.woundedExpiresAt,
        loyalty = brain.loyalty,
        mercenaryLoyalty = brain.mercenaryLoyalty,
        loyaltyState = brain.loyaltyState,
        loyaltyForPlayerId = brain.loyaltyForPlayerId,
        loyaltyForPlayerName = brain.loyaltyForPlayerName,
        loyaltyReason = brain.loyaltyReason,
        loyaltyUpdatedAt = brain.loyaltyUpdatedAt,
        lastLoyaltyDelta = brain.lastLoyaltyDelta,
        lastLoyaltyReason = brain.lastLoyaltyReason,
        leader = brain.leader,
        isFactionLeader = brain.isFactionLeader,
        leaderId = brain.leaderId,
        leaderName = brain.leaderName,
        leaderRole = brain.leaderRole,
        leaderTitle = brain.leaderTitle,
        leaderSide = brain.leaderSide,
        leaderState = brain.leaderState,
        leaderInfluence = brain.leaderInfluence,
        mercenarySquadLeader = brain.mercenarySquadLeader,
        mercenarySquadLeaderName = brain.mercenarySquadLeaderName
    })
end


local function bsc_isOrderInterruptActiveForPayload(brain)
    local order = type(brain) == "table" and brain.order or nil
    if type(order) ~= "table" or order.interrupt ~= true then return false end
    local now = bsc_worldAgeHours()
    local untilHour = tonumber(order.interruptUntil or order.forceUntil)
    if untilHour and untilHour > now then return true end
    local issued = tonumber(order.interruptIssued or order.issued)
    return issued ~= nil and now >= issued and now - issued < (8 / 3600)
end

local function bsc_makeMercenaryOrderPayload(id, brain)
    if not (id and brain) then return nil end
    local clearCombat = bsc_isOrderInterruptActiveForPayload(brain)
    local targetId = brain.targetId
    local targetKind = brain.targetKind
    local currentThreat = brain.currentThreat
    local lastThreat = brain.lastThreat
    if clearCombat then
        targetId = false
        targetKind = false
        currentThreat = false
        lastThreat = false
    end
    local runtimeId = brain.runtimeId or brain[NPC_SERVER_LEGACY_KEYS.runtimeId]
    local persistentId = brain.persistentId or brain[NPC_SERVER_LEGACY_KEYS.persistentId]
    local worldGroupId = brain.worldGroupId or brain.groupId or brain[NPC_SERVER_LEGACY_KEYS.worldGroupId]
    local order = type(brain.order) == "table" and brain.order or nil
    local playerCommand = brain.commandAuthority == "player" or brain.playerCommandAuthority == true
        or (order and (order.commandAuthority == "player" or order.playerCommand == true or order.source == "player"))
    local urgentOrder = clearCombat == true or playerCommand == true
    local px = tonumber(brain.x) or (brain.debugCoords and tonumber(brain.debugCoords.x)) or (brain.bornCoords and tonumber(brain.bornCoords.x))
    local py = tonumber(brain.y) or (brain.debugCoords and tonumber(brain.debugCoords.y)) or (brain.bornCoords and tonumber(brain.bornCoords.y))
    local pz = tonumber(brain.z) or (brain.debugCoords and tonumber(brain.debugCoords.z)) or (brain.bornCoords and tonumber(brain.bornCoords.z))

    return {
        id = brain.id or id,
        runtimeId = runtimeId,
        persistentId = persistentId,
        uid = brain.uid,
        memberIndex = brain.memberIndex,
        slotIndex = brain.slotIndex,
        formationIndex = brain.formationIndex,
        worldGroupId = worldGroupId,
        groupId = worldGroupId,
        x = px,
        y = py,
        z = pz,
        master = brain.master,
        hostile = brain.hostile,
        program = brain.program,
        order = brain.order,
        fireMode = brain.order and brain.order.fireMode or brain.fireMode,
        rbFireMode = brain.rbFireMode,
        tasks = brain.tasks,
        targetId = targetId,
        targetKind = targetKind,
        currentThreat = currentThreat,
        lastThreat = lastThreat,
        factionSide = brain.factionSide,
        faction = brain.faction,
        side = brain.side,
        patrolColor = brain.patrolColor,
        mercenary = brain.mercenary,
        mercenaryHired = brain.mercenaryHired,
        mercenaryHiredBy = brain.mercenaryHiredBy,
        isPlayerGuard = brain.isPlayerGuard,
        followPlayer = brain.followPlayer,
        guardPlayer = brain.guardPlayer,
        relationshipToPlayer = brain.relationshipToPlayer,
        factionState = brain.factionState,
        mercenarySquadLeader = brain.mercenarySquadLeader,
        mercenarySquadLeaderName = brain.mercenarySquadLeaderName,
        orderRevision = brain.orderRevision or brain.mercenaryOrderRevision or brain.groupOrderRevision or (order and (order.orderRevision or order.groupOrderRevision)),
        mercenaryOrderRevision = brain.mercenaryOrderRevision or brain.orderRevision or brain.groupOrderRevision or (order and (order.orderRevision or order.groupOrderRevision)),
        groupOrderRevision = brain.groupOrderRevision or brain.orderRevision or brain.mercenaryOrderRevision or (order and (order.groupOrderRevision or order.orderRevision)),
        orderBatchId = brain.orderBatchId or brain.mercenaryOrderBatchId or brain.groupOrderBatchId or (order and (order.orderBatchId or order.groupOrderBatchId)),
        groupOrderBatchId = brain.groupOrderBatchId or brain.orderBatchId or brain.mercenaryOrderBatchId or (order and (order.groupOrderBatchId or order.orderBatchId)),
        orderIssuedMs = brain.mercenaryOrderIssuedMs,
        forceImmediateOrder = true,
        directMercenaryOrder = true,
        mercenaryDirect = true,
        orderSystem = "mercenary_direct",
        clearCombat = clearCombat == true,
        urgentMercenaryOrder = true,
        mercenaryOrderAsync = false
    }
end

local function bsc_syncMercenaryOrderBrain(id, brain)
    local payload = bsc_makeMercenaryOrderPayload(id, brain)
    if payload then sendServerCommand('NPCCommands', NPC_SERVER_LEGACY_COMMANDS.updatePart, payload) end
end

local function bsc_queueMercenaryOrderPayload(batch, id, brain)
    local payload = bsc_makeMercenaryOrderPayload(id, brain)
    if payload and type(batch) == "table" and type(batch._mercenaryTelemetry) == "table" then
        local mt = batch._mercenaryTelemetry
        payload.clientTraceId = mt.clientTraceId
        payload.clientSendMs = mt.clientSendMs
        payload.clientOrderSeq = mt.clientOrderSeq
        payload.clientEvent = mt.clientEvent
        payload.serverReceiveMs = mt.serverReceiveMs
        payload.orderAcceptedMs = mt.orderAcceptedMs
    end
    if payload then batch[#batch + 1] = payload end
end

local function bsc_flushMercenaryOrderBatch(batch)
    if type(batch) ~= "table" or #batch == 0 then return end
    local flushMs = bsc_nowMs and bsc_nowMs() or 0
    local revision = nil
    local batchId = nil
    for _, payload in ipairs(batch) do
        if type(payload) == "table" then
            revision = revision or payload.groupOrderRevision or payload.orderRevision or payload.mercenaryOrderRevision
            batchId = batchId or payload.groupOrderBatchId or payload.orderBatchId
            payload.urgentMercenaryOrder = true
            payload.mercenaryOrderAsync = false
            payload.forceImmediateOrder = true
            payload.applyTogether = true
            payload.serverFlushMs = flushMs
        end
    end
    local mt = type(batch._mercenaryTelemetry) == "table" and batch._mercenaryTelemetry or {}
    sendServerCommand('NPCCommands', 'MercenaryDirectOrderBatch', {
        entries = batch,
        clientTraceId = mt.clientTraceId,
        clientSendMs = mt.clientSendMs,
        clientOrderSeq = mt.clientOrderSeq,
        clientEvent = mt.clientEvent,
        serverReceiveMs = mt.serverReceiveMs,
        orderAcceptedMs = mt.orderAcceptedMs,
        serverFlushMs = flushMs,
        orderRevision = revision,
        groupOrderRevision = revision,
        orderBatchId = batchId,
        groupOrderBatchId = batchId,
        applyTogether = true,
        urgentMercenaryOrder = true,
        directMercenaryOrder = true,
        orderSystem = "mercenary_direct"
    })
end

local function bsc_mercenaryMemberSeenKey(id, brain)
    if type(brain) == "table" then
        local key = bsc_nonEmptyId(brain.uid or brain.persistentId or brain.id or brain.runtimeId or brain[NPC_SERVER_LEGACY_KEYS.runtimeId])
        if key then return key end
    end
    return bsc_nonEmptyId(id)
end

local function bsc_rememberMercenaryOrderMember(foundMembers, foundSeen, id, brain)
    local sid = bsc_nonEmptyId(id)
    if not sid then return false end
    local seenKey = bsc_mercenaryMemberSeenKey(id, brain) or sid
    if foundSeen and foundSeen[seenKey] then return false end
    if foundSeen then foundSeen[seenKey] = true end
    if type(foundMembers) == "table" then foundMembers[#foundMembers + 1] = id end
    return true
end

local function bsc_orderBrainCandidates(brain, fallback)
    local list = {}
    local seen = {}
    local function add(value)
        local sid = bsc_nonEmptyId(value)
        if sid and not seen[sid] then
            seen[sid] = true
            list[#list + 1] = sid
        end
    end
    add(fallback)
    if type(brain) == "table" then
        add(brain.id)
        add(brain.runtimeId)
        add(brain.uid)
        add(brain.persistentId)
        add(brain[NPC_SERVER_LEGACY_KEYS.runtimeId])
        add(brain[NPC_SERVER_LEGACY_KEYS.persistentId])
    end
    return list
end

local function bsc_existingQueueKeyForBrain(gmd, brain, fallback)
    local candidates = bsc_orderBrainCandidates(brain, fallback)
    if gmd and gmd.Queue then
        for _, sid in ipairs(candidates) do
            if gmd.Queue[sid] then return sid end
            local nid = tonumber(sid)
            if nid and gmd.Queue[nid] then return nid end
        end
        for qid, queuedBrain in pairs(gmd.Queue) do
            if queuedBrain == brain or bsc_brainMatchesIds(queuedBrain, qid, candidates) then return qid end
        end
    end
    return candidates[1]
end

local function bsc_isMercenaryInterruptActive(brain)
    local order = type(brain) == "table" and brain.order or nil
    if type(order) ~= "table" or order.interrupt ~= true then return false end
    local now = bsc_worldAgeHours()
    local untilHour = tonumber(order.interruptUntil or order.forceUntil)
    if untilHour and untilHour > now then return true end
    local issued = tonumber(order.interruptIssued or order.issued)
    return issued ~= nil and now >= issued and now - issued < (8 / 3600)
end

local function bsc_interruptPhysicalMercenaryOrder(zombie, brain)
    if not (zombie and type(brain) == "table" and bsc_isMercenaryInterruptActive(brain)) then return end
    brain.tasks = {}
    brain.targetId = nil
    brain.targetKind = nil
    brain.currentThreat = nil
    brain.lastThreat = nil
    brain.target = nil
    brain.enemy = nil
    brain.combatTarget = nil
    brain.radioThreat = nil
    brain._threatCache = nil
    brain._combatTargetCache = nil
    if brain.fsm then
        brain.fsm.targetId = nil
        brain.fsm.targetKind = nil
        brain.fsm.currentThreat = nil
        brain.fsm.lastThreat = nil
        brain.fsm.target = nil
    end
    if NPCEntity and NPCEntity.ClearTasks then pcall(function() NPCEntity.ClearTasks(zombie) end) end
    if NPCEntity and NPCEntity.SetAim then pcall(function() NPCEntity.SetAim(zombie, false) end) end
    if NPCEntity and NPCEntity.SetMoving then pcall(function() NPCEntity.SetMoving(zombie, false) end) end
    if zombie.setBumpDone then pcall(function() zombie:setBumpDone(true) end) end
    if zombie.clearAggroList then pcall(function() zombie:clearAggroList() end) end
    if zombie.setTarget then pcall(function() zombie:setTarget(nil) end) end
    if zombie.setAttackedBy then pcall(function() zombie:setAttackedBy(nil) end) end
end

local function bsc_applyOrderToStoredGroupMembers(gmd, group, player, pid, groupId, data, foundMembers, foundSeen, orderBatch)
    if not (gmd and type(group) == "table" and type(group.members) == "table" and NPCMercenaryContract and NPCMercenaryContract.ApplyOrderToBrain) then return 0 end
    local changed = 0
    local groupOwner = group.mercenaryHiredBy
    for _, member in pairs(group.members) do
        if type(member) == "table" then
            local hiredByPlayer = (member.mercenaryHiredBy and tostring(member.mercenaryHiredBy) == tostring(pid))
                or (groupOwner and tostring(groupOwner) == tostring(pid))
            if hiredByPlayer then
                NPCMercenaryContract.ApplyOrderToBrain(member, player, data)
                local qid = bsc_existingQueueKeyForBrain(gmd, member, member.id or member.runtimeId or member.uid or member.persistentId)
                if qid then
                    if gmd.Queue then gmd.Queue[qid] = member end
                    if bsc_rememberMercenaryOrderMember(foundMembers, foundSeen, qid, member) then
                        bsc_queueMercenaryOrderPayload(orderBatch, qid, member)
                        changed = changed + 1
                    end
                end
            end
        end
    end
    if changed > 0 then
        bsc_logMercenary("order group member fallback changed=" .. tostring(changed) .. " group=" .. tostring(groupId))
    end
    return changed
end

local function bsc_applyOrderToPhysicalMercenaries(gmd, player, pid, groupId, data, foundMembers, foundSeen, orderBatch)
    if not (gmd and player and NPCBrainData and NPCBrainData.Get and NPCBrainData.Update and NPCMercenaryContract and NPCMercenaryContract.ApplyOrderToBrain) then return 0 end
    local cell = getCell and getCell() or nil
    local list = cell and cell.getZombieList and cell:getZombieList() or nil
    if not (list and list.size and list.get) then return 0 end

    local changed = 0
    local size = 0
    local okSize, gotSize = pcall(function() return list:size() end)
    if okSize then size = tonumber(gotSize) or 0 end

    for i = 0, size - 1 do
        local okGet, zombie = pcall(function() return list:get(i) end)
        if okGet and zombie and zombie.getVariableBoolean and zombie:getVariableBoolean(NPC_SERVER_LEGACY_KEYS.liveFlag) then
            local brain = NPCBrainData.Get(zombie)
            if type(brain) == "table" then
                local hiredByPlayer = brain.mercenaryHiredBy and tostring(brain.mercenaryHiredBy) == tostring(pid)
                local sameGroup = (not groupId) or (bsc_groupIdOf(brain) and tostring(bsc_groupIdOf(brain)) == tostring(groupId))
                if hiredByPlayer and sameGroup then
                    local qid = bsc_existingQueueKeyForBrain(gmd, brain, bsc_safeZombieId(zombie))
                    local seenKey = bsc_mercenaryMemberSeenKey(qid or bsc_safeZombieId(zombie), brain)
                    local alreadyQueued = foundSeen and seenKey and foundSeen[seenKey] == true
                    if not alreadyQueued then
                        NPCMercenaryContract.ApplyOrderToBrain(brain, player, data)
                        bsc_interruptPhysicalMercenaryOrder(zombie, brain)
                        NPCBrainData.Update(zombie, brain)
                        bsc_writeNPCServiceIds(zombie, brain, groupId or bsc_groupIdOf(brain))
                    end

                    if qid and not alreadyQueued then
                        if gmd.Queue then gmd.Queue[qid] = brain end
                        if bsc_rememberMercenaryOrderMember(foundMembers, foundSeen, qid, brain) then
                            bsc_queueMercenaryOrderPayload(orderBatch, qid, brain)
                            changed = changed + 1
                        end
                    end
                end
            end
        end
    end

    if changed > 0 then
        bsc_logMercenary("order physical sync changed=" .. tostring(changed) .. " group=" .. tostring(groupId))
    end
    return changed
end

local function bsc_activeMercenaryCache(gmd)
    if not gmd then return nil end
    if not gmd.MercenaryActiveSquadByPlayer then gmd.MercenaryActiveSquadByPlayer = {} end
    if not gmd.MercenaryActiveMemberIdsByPlayer then gmd.MercenaryActiveMemberIdsByPlayer = {} end
    return gmd.MercenaryActiveSquadByPlayer, gmd.MercenaryActiveMemberIdsByPlayer
end

local function bsc_setActiveMercenarySquad(gmd, pid, groupId)
    if not (gmd and pid) then return end
    local squads, members = bsc_activeMercenaryCache(gmd)
    local key = tostring(pid)
    if groupId then squads[key] = tostring(groupId) else squads[key] = nil end
    local ids = {}
    local seen = {}
    if groupId and gmd.Queue then
        local sgid = tostring(groupId)
        for qid, brain in pairs(gmd.Queue) do
            if brain and brain.mercenaryHiredBy and tostring(brain.mercenaryHiredBy) == key and bsc_groupIdOf(brain) == sgid then
                local memberKey = bsc_mercenaryMemberSeenKey(qid, brain) or tostring(qid)
                if not seen[memberKey] then
                    seen[memberKey] = true
                    ids[#ids + 1] = qid
                end
            end
        end
    end
    members[key] = ids
end

local function bsc_mercenarySquadLeaderKey(member, id)
    if type(member) == "table" then
        local key = bsc_nonEmptyId(member.uid or member.persistentId or member.id or member.runtimeId or member[NPC_SERVER_LEGACY_KEYS.runtimeId])
        if key then return key end
    end
    return bsc_nonEmptyId(id)
end

local function bsc_markMercenarySquadLeader(gmd, group, groupId)
    if not (gmd and group) then return nil end
    groupId = groupId and tostring(groupId) or tostring(group.id or "")
    if groupId == "" then return nil end

    local preferredKey = bsc_nonEmptyId(group.mercenarySquadLeaderId or group.leaderMemberUid or group.leaderPersistentId)
    if not preferredKey and type(group.members) == "table" then
        for _, member in ipairs(group.members) do
            preferredKey = bsc_mercenarySquadLeaderKey(member)
            if preferredKey then break end
        end
    end

    local leaderName = nil
    if type(group.members) == "table" then
        for _, member in ipairs(group.members) do
            if type(member) == "table" then
                local key = bsc_mercenarySquadLeaderKey(member)
                local isLeader = preferredKey and key == preferredKey
                member.mercenarySquadLeader = isLeader == true
                if isLeader then
                    leaderName = member.fullname or member.name or member.forename or member.surname or leaderName
                    member.mercenarySquadLeaderName = leaderName
                else
                    member.mercenarySquadLeaderName = nil
                end
            end
        end
    end

    local queueLeaderId = nil
    local fallbackId = nil
    if gmd.Queue then
        for qid, brain in pairs(gmd.Queue) do
            if type(brain) == "table" and bsc_groupIdOf(brain) == groupId then
                local key = bsc_mercenarySquadLeaderKey(brain, qid)
                if not fallbackId then fallbackId = qid end
                if preferredKey and key == preferredKey then
                    queueLeaderId = qid
                    leaderName = brain.fullname or brain.name or brain.forename or brain.surname or leaderName
                    break
                end
            end
        end
        if not queueLeaderId then queueLeaderId = fallbackId end
        if not preferredKey and queueLeaderId then preferredKey = bsc_mercenarySquadLeaderKey(gmd.Queue[queueLeaderId], queueLeaderId) end
        for qid, brain in pairs(gmd.Queue) do
            if type(brain) == "table" and bsc_groupIdOf(brain) == groupId then
                local isLeader = tostring(qid) == tostring(queueLeaderId or "") or (preferredKey and bsc_mercenarySquadLeaderKey(brain, qid) == preferredKey)
                brain.mercenarySquadLeader = isLeader == true
                if isLeader then
                    leaderName = brain.fullname or brain.name or brain.forename or brain.surname or leaderName
                    brain.mercenarySquadLeaderName = leaderName
                else
                    brain.mercenarySquadLeaderName = nil
                end
                gmd.Queue[qid] = brain
                bsc_updateMercenaryMarker(gmd, qid, brain)
            end
        end
    end

    group.mercenarySquadLeaderId = preferredKey or (queueLeaderId and tostring(queueLeaderId)) or group.mercenarySquadLeaderId
    group.mercenarySquadLeaderName = leaderName or group.mercenarySquadLeaderName
    return group.mercenarySquadLeaderId
end

local function bsc_getActiveMercenarySquad(gmd, pid)
    if not (gmd and pid) then return nil end
    local squads = bsc_activeMercenaryCache(gmd)
    return squads and squads[tostring(pid)] or nil
end

local function bsc_getActiveMercenaryMemberIds(gmd, pid)
    if not (gmd and pid) then return nil end
    bsc_activeMercenaryCache(gmd)
    local members = gmd.MercenaryActiveMemberIdsByPlayer and gmd.MercenaryActiveMemberIdsByPlayer[tostring(pid)] or nil
    if type(members) == "table" and #members > 0 then return members end
    return nil
end

local function bsc_isMercenaryGroupOwnedByPlayer(gmd, groupId, pid)
    if not (gmd and groupId and pid) then return false end
    local sid = tostring(groupId)
    local key = tostring(pid)

    if gmd.VirtualGroups then
        local group = gmd.VirtualGroups[sid] or gmd.VirtualGroups[tonumber(sid)]
        if group and group.mercenaryHiredBy and tostring(group.mercenaryHiredBy) == key then return true end
        if group and group.mercenaryHired == true and group.mercenaryHiredBy == nil then return false end
    end

    if gmd.Queue then
        for _, brain in pairs(gmd.Queue) do
            if type(brain) == "table" and bsc_groupIdOf(brain) == sid then
                if brain.mercenaryHiredBy and tostring(brain.mercenaryHiredBy) == key then return true end
            end
        end
    end

    return false
end

local function bsc_orderSig(args, groupId)
    if type(args) ~= "table" then return tostring(groupId or "") end
    local x = args.x and tostring(math.floor((tonumber(args.x) or 0) * 10 + 0.5)) or ""
    local y = args.y and tostring(math.floor((tonumber(args.y) or 0) * 10 + 0.5)) or ""
    local z = args.z and tostring(math.floor((tonumber(args.z) or 0) * 10 + 0.5)) or ""
    return table.concat({tostring(groupId or args.groupId or ""), tostring(args.orderName or ""), tostring(args.fireMode or ""), tostring(args.formation or ""), tostring(args.followDistance or ""), x, y, z}, "|")
end

local function bsc_groupOnlyOrderData(data)
    local out = {}
    if type(data) == "table" then
        for k, v in pairs(data) do out[k] = v end
    end
    out._groupOnly = true
    return out
end

local function bsc_mercenaryOrderLabel(data)
    if type(data) ~= "table" then return "updated" end
    if data.orderName and tostring(data.orderName) ~= "" then return tostring(data.orderName) end
    if data.fireMode and tostring(data.fireMode) ~= "" then return "fire " .. tostring(data.fireMode) end
    if data.formation and tostring(data.formation) ~= "" then return "formation " .. tostring(data.formation) end
    if data.followDistance ~= nil then return "follow distance " .. tostring(data.followDistance) end
    return "updated"
end

local function bsc_normalizeMercenaryOrderName(name)
    name = tostring(name or "")
    if name == "" or name == "nil" then return nil end
    if name == "Follow" or name == "follow" or name == "FollowPlayer" then return "Follow" end
    if name == "Hold" or name == "hold" or name == "HoldPosition" then return "Hold" end
    if name == "Guard" or name == "guard" or name == "GuardArea" or name == "GuardPlayer" then return "Guard" end
    if name == "Patrol" or name == "patrol" or name == "PatrolArea" then return "Patrol" end
    if name == "Loot" or name == "loot" or name == "LootArea" then return "Loot" end
    if name == "LootHouse" or name == "loot_house" or name == "search_house" then return "LootHouse" end
    if name == "LootBodies" or name == "LootBodiesGear" or name == "LootBodiesClothing" or name == "LootBodiesWeapons" or name == "LootBodiesAmmo" or name == "LootBodiesMedical" or name == "LootBodiesSupplies" then return name end
    if name == "RearmHere" or name == "rearm" or name == "rearm_here" then return "RearmHere" end
    if name == "Flank" or name == "flank" or name == "flank_point" then return "Flank" end
    if name == "Encircle" or name == "encircle" or name == "surround" then return "Encircle" end
    if name == "BackToBack" or name == "back_to_back" or name == "all_around_defense" then return "BackToBack" end
    if name == "TakeCover" or name == "take_cover" then return "TakeCover" end
    if name == "Advance" or name == "advance" then return "Advance" end
    if name == "FallBack" or name == "fall_back" or name == "fallback" then return "FallBack" end
    if name == "WatchSector" or name == "watch_sector" then return "WatchSector" end
    if name == "Return" or name == "ReturnToBase" or name == "return" then return "Return" end
    return name
end

local function bsc_isMercenaryPointOrderName(name)
    name = bsc_normalizeMercenaryOrderName(name)
    return name == "Hold" or name == "Guard" or name == "Patrol" or name == "Loot" or name == "LootHouse"
        or name == "LootBodies" or name == "LootBodiesGear" or name == "LootBodiesClothing" or name == "LootBodiesWeapons"
        or name == "LootBodiesAmmo" or name == "LootBodiesMedical" or name == "LootBodiesSupplies" or name == "RearmHere"
        or name == "Return" or name == "Flank" or name == "Encircle" or name == "BackToBack" or name == "TakeCover"
        or name == "Advance" or name == "FallBack" or name == "WatchSector"
end

local function bsc_normalizeMercenaryFireMode(mode)
    if mode == nil then return nil end
    mode = tostring(mode or "")
    if mode == "" or mode == "nil" then return nil end
    local key = string.lower(mode)
    if key == "fireatwill" or key == "fire_at_will" or key == "aggressive" then return "FireAtWill" end
    if key == "defensive" or key == "defense" then return "Defensive" end
    if key == "holdfire" or key == "hold_fire" then return "HoldFire" end
    if key == "meleeonly" or key == "melee_only" then return "MeleeOnly" end
    if key == "returnfire" or key == "return_fire" then return "ReturnFire" end
    if key == "dangerclose" or key == "danger_close" then return "DangerClose" end
    if key == "suppress" or key == "suppression" then return "Suppress" end
    return nil
end

local function bsc_normalizeMercenaryFormation(formation)
    if formation == nil then return nil end
    formation = tostring(formation or "")
    if formation == "" or formation == "nil" then return nil end
    local key = string.lower(formation)
    if key == "close" then return "close" end
    if key == "ring" or key == "bodyguard" then return "ring" end
    if key == "wide" then return "wide" end
    if key == "line" then return "line" end
    if key == "wedge" then return "wedge" end
    return nil
end

local function bsc_clampMercenaryFollowDistance(value)
    if value == nil then return nil end
    local distance = tonumber(value)
    if not distance then return nil end
    if distance < 0.75 then distance = 0.75 end
    if distance > 8.0 then distance = 8.0 end
    return distance
end

local function bsc_mercenaryOrderFeedback(data, memberCount, changed, groupId)
    local label = bsc_mercenaryOrderLabel(data)
    local members = tonumber(memberCount) or 0
    local total = tonumber(changed) or members
    local parts = {"Mercenary order accepted: " .. label}
    if groupId then parts[#parts + 1] = "group " .. tostring(groupId) end
    if members > 0 then
        parts[#parts + 1] = tostring(members) .. (members == 1 and " member" or " members")
    elseif total > 0 then
        parts[#parts + 1] = "squad synced"
    end
    if type(data) == "table" then
        if data.fireMode and tostring(data.fireMode) ~= "" then parts[#parts + 1] = "fire " .. tostring(data.fireMode) end
        if data.formation and tostring(data.formation) ~= "" then parts[#parts + 1] = "formation " .. tostring(data.formation) end
    end
    return table.concat(parts, "; ") .. "."
end

local function bsc_statusSameGroup(brain, groupId)
    if not groupId then return true end
    local brainGroup = bsc_groupIdOf(brain)
    return brainGroup ~= nil and tostring(brainGroup) == tostring(groupId)
end

local function bsc_statusTaskName(brain)
    if type(brain) ~= "table" then return nil end
    local task = type(brain.tasks) == "table" and brain.tasks[1] or nil
    if type(task) == "table" then return task.action or task.type or task.name end
    if type(brain.program) == "table" then return brain.program.name end
    return brain.state or brain.programName
end

local function bsc_statusHealthRatio(brain)
    if type(brain) ~= "table" then return nil end
    local value = tonumber(brain.health or brain.hp or brain.Health or brain.hitpoints or brain.hitPoints)
    if value == nil then return nil end
    if value > 1.0 then value = value / 100.0 end
    if value < 0 then value = 0 end
    if value > 1 then value = 1 end
    return value
end

local function bsc_statusAddBrain(status, seen, id, brain, player)
    if type(status) ~= "table" or type(brain) ~= "table" then return end
    local key = bsc_mercenaryMemberSeenKey(id, brain) or bsc_nonEmptyId(id)
    if key and seen[key] then return end
    if key then seen[key] = true end

    status.count = status.count + 1
    status.groupId = status.groupId or bsc_groupIdOf(brain)
    local order = type(brain.order) == "table" and brain.order or nil
    if order then
        status.orderName = status.orderName or order.name
        status.fireMode = status.fireMode or order.fireMode or brain.fireMode or brain.rbFireMode
        status.formation = status.formation or order.formation or brain.formation
        status.followDistance = status.followDistance or order.followDistance
    else
        status.fireMode = status.fireMode or brain.fireMode or brain.rbFireMode
        status.formation = status.formation or brain.formation
    end
    if brain.strictPlayerOrder == true or brain.manualOrder == true or (order and (order.strictPlayerOrder == true or order.manualOrder == true)) then
        status.strict = status.strict + 1
    end
    local taskName = bsc_statusTaskName(brain)
    if taskName then
        taskName = tostring(taskName)
        status.currentTask = status.currentTask or taskName
        if taskName == "SearchEnemy" or taskName == "Attack" or taskName == "MeleeFallback" or taskName == "SuppressEnemy" or taskName == "TacticalCover" then
            status.combat = status.combat + 1
        elseif taskName == "FollowPlayer" or taskName == "CompanionFollow" or taskName == "Move" or taskName == "Walk" then
            status.moving = status.moving + 1
        elseif taskName == "HoldPosition" or taskName == "CompanionGuard" or taskName == "GuardPlayer" then
            status.holding = status.holding + 1
        end
    end
    local health = bsc_statusHealthRatio(brain)
    if health ~= nil and health < 0.62 then status.wounded = status.wounded + 1 end

    if player and player.getX and player.getY then
        local px = tonumber(player:getX())
        local py = tonumber(player:getY())
        local bx = tonumber(brain.x) or (brain.debugCoords and tonumber(brain.debugCoords.x)) or (brain.bornCoords and tonumber(brain.bornCoords.x))
        local by = tonumber(brain.y) or (brain.debugCoords and tonumber(brain.debugCoords.y)) or (brain.bornCoords and tonumber(brain.bornCoords.y))
        if px and py and bx and by then
            local dx = bx - px
            local dy = by - py
            if (dx * dx + dy * dy) > (24 * 24) then status.far = status.far + 1 end
        end
    end
end

local function bsc_collectMercenaryStatus(gmd, player, pid, groupId)
    local status = {count=0, strict=0, combat=0, moving=0, holding=0, wounded=0, far=0, groupId=groupId}
    local seen = {}
    local key = tostring(pid or "")
    if gmd and gmd.Queue then
        for qid, brain in pairs(gmd.Queue) do
            if type(brain) == "table" and brain.mercenaryHiredBy and tostring(brain.mercenaryHiredBy) == key and bsc_statusSameGroup(brain, groupId) then
                bsc_statusAddBrain(status, seen, qid, brain, player)
            end
        end
    end
    return status
end

local function bsc_formatMercenaryStatus(status)
    if type(status) ~= "table" or (tonumber(status.count) or 0) <= 0 then return "No hired mercenaries found." end
    local orderName = status.orderName or "none"
    local fireMode = status.fireMode or "default"
    local formation = status.formation or "default"
    local parts = {
        "Mercenary status: " .. tostring(status.count) .. (status.count == 1 and " member" or " members"),
        "order " .. tostring(orderName),
        "fire " .. tostring(fireMode),
        "formation " .. tostring(formation)
    }
    if status.groupId then parts[#parts + 1] = "group " .. tostring(status.groupId) end
    if status.strict and status.strict > 0 then parts[#parts + 1] = tostring(status.strict) .. " strict" end
    if status.combat and status.combat > 0 then parts[#parts + 1] = tostring(status.combat) .. " in combat" end
    if status.moving and status.moving > 0 then parts[#parts + 1] = tostring(status.moving) .. " moving" end
    if status.holding and status.holding > 0 then parts[#parts + 1] = tostring(status.holding) .. " holding" end
    if status.wounded and status.wounded > 0 then parts[#parts + 1] = tostring(status.wounded) .. " wounded" end
    if status.far and status.far > 0 then parts[#parts + 1] = tostring(status.far) .. " far" end
    return table.concat(parts, "; ") .. "."
end

local function bsc_throttleMercenaryOrder(gmd, pid, args, groupId)
    if not (gmd and pid) then return false end
    local now = bsc_nowMs and bsc_nowMs() or 0
    if now <= 0 then return false end
    if not gmd.MercenaryOrderThrottle then gmd.MercenaryOrderThrottle = {} end
    local key = tostring(pid)
    local sig = bsc_orderSig(args, groupId)
    local prev = gmd.MercenaryOrderThrottle[key]
    if prev and prev.sig == sig and (now - (tonumber(prev.ms) or 0)) < 250 then
        return true
    end
    gmd.MercenaryOrderThrottle[key] = {sig=sig, ms=now}
    return false
end

bsc_updateMercenaryMarker = function(gmd, id, brain)
    if not (gmd and id and brain) then return end
    if not gmd.DebugMapMarkers then gmd.DebugMapMarkers = {} end
    local markerId = bsc_npcMarkerId(id)
    if not markerId then return end
    local marker, oldMarkerId = bsc_getNpcDebugMarker(gmd, id, brain)
    if not marker then
        local coords = brain.debugCoords or brain.bornCoords or {}
        if coords.x or brain.x then
            marker = {id=markerId, markerType="npc", runtimeId=tostring(id), x=coords.x or brain.x, y=coords.y or brain.y, z=coords.z or brain.z or 0, name=brain.fullname or brain.name or "Hired mercenary"}
            gmd.DebugMapMarkers[markerId] = marker
        end
    end
    if marker then
        marker.id = markerId
        marker.markerType = "npc"
        marker.runtimeId = tostring(id)
        marker.groupId = bsc_brainGroupId(brain) or marker.groupId
        marker.worldGroupId = marker.groupId
        if oldMarkerId then bsc_removeLegacyNpcMarker(gmd, oldMarkerId, markerId) end
        marker.hostile = false
        marker.friendly = true
        marker.factionSide = "blue"
        marker.faction = "blue"
        marker.side = "blue"
        marker.patrolColor = "blue"
        marker.factionState = brain.factionState
        marker.program = brain.program and brain.program.name or marker.program
        marker.mercenary = brain.mercenary or false
        marker.mercenaryElite = brain.mercenaryElite or false
        marker.mercenaryHired = brain.mercenaryHired or false
        marker.mercenaryHiredBy = brain.mercenaryHiredBy
        marker.isPlayerGuard = brain.mercenaryHired == true
        marker.mercenarySquadLeader = brain.mercenarySquadLeader == true
        marker.mercenarySquadLeaderName = brain.mercenarySquadLeaderName
        if NPCLoyaltyBridge and NPCLoyaltyBridge.MarkerFields then
            NPCLoyaltyBridge.MarkerFields(marker, brain)
        end
        if NPCLeadersBridge and NPCLeadersBridge.MarkerFields then
            NPCLeadersBridge.MarkerFields(marker, brain)
        end
        marker.updatedAt = getGameTime():getWorldAgeHours()
        NPCServerSetDebugMarker(gmd, marker)
    end
end

local function bsc_updateMercenaryGroupMarker(gmd, groupId, group)
    if not (gmd and groupId) then return end
    local marker = gmd.DebugMapMarkers and gmd.DebugMapMarkers[tostring(groupId)] or nil
    if marker then
        marker.hostile = false
        marker.friendly = true
        marker.factionSide = "blue"
        marker.faction = "blue"
        marker.side = "blue"
        marker.patrolColor = "blue"
        marker.state = group and group.state or marker.state
        marker.program = group and group.program and group.program.name or marker.program
        if group then
            marker.mercenary = group.mercenary or false
            marker.mercenaryElite = group.mercenaryElite or false
            marker.mercenaryHired = group.mercenaryHired == true
            marker.mercenaryHiredBy = group.mercenaryHiredBy
            marker.isPlayerGuard = group.mercenaryHired == true
            marker.mercenarySquadLeaderId = group.mercenarySquadLeaderId
            marker.mercenarySquadLeaderName = group.mercenarySquadLeaderName
        end
        if NPCLoyaltyBridge and NPCLoyaltyBridge.MarkerFields and group then
            NPCLoyaltyBridge.MarkerFields(marker, group)
        end
        if NPCLeadersBridge and NPCLeadersBridge.MarkerFields and group then
            NPCLeadersBridge.MarkerFields(marker, group)
        end
        if group then
            marker.name = bsc_groupDisplayName(groupId, group, marker.name)
            marker.displayName = marker.name
        end
        marker.updatedAt = getGameTime():getWorldAgeHours()
        NPCServerSetDebugMarker(gmd, marker)
    end
end

local function bsc_updatePrisonerMarker(gmd, id, brain)
    if not (gmd and id and brain and gmd.DebugMapMarkers) then return end
    local markerId = bsc_npcMarkerId(id)
    local marker, oldMarkerId = bsc_getNpcDebugMarker(gmd, id, brain)
    if not marker or not markerId then return end
    marker.id = markerId
    marker.markerType = "npc"
    marker.runtimeId = tostring(id)
    marker.groupId = bsc_brainGroupId(brain) or marker.groupId
    marker.worldGroupId = marker.groupId
    if oldMarkerId then bsc_removeLegacyNpcMarker(gmd, oldMarkerId, markerId) end
    marker.prisoner = brain.prisoner == true
    marker.prisonerForPlayerId = brain.prisonerForPlayerId
    marker.prisonerForPlayerName = brain.prisonerForPlayerName
    marker.prisonerState = brain.prisonerState
    marker.hostile = brain.prisoner == true and false or marker.hostile
    marker.friendly = brain.prisoner == true and true or marker.friendly
    marker.program = brain.program and brain.program.name or marker.program
    marker.state = brain.prisonerState or marker.state
    marker.updatedAt = getGameTime():getWorldAgeHours()
    NPCServerSetDebugMarker(gmd, marker)
end

NPCServerRuntime.Players.PlayerUpdate = function(player, args)
    if type(args) ~= "table" or not args.id then return end

    local gmd = GetNPCModDataPlayers()
    if not gmd.OnlinePlayers then gmd.OnlinePlayers = {} end

    local id = args.id
    if NPCFactionBridge and NPCFactionBridge.NormalizeSide then
        args.factionSide = NPCFactionBridge.NormalizeSide(args.factionSide) or NPCFactionBridge.DefaultPlayerSide()
    end
    gmd.OnlinePlayers[id] = args
end

NPCServerRuntime.Players.SetFaction = function(player, args)
    if type(args) ~= "table" then return end

    local gmd = GetNPCModDataPlayers()
    if not gmd.OnlinePlayers then gmd.OnlinePlayers = {} end

    local id = args.id
    if not id and NPCUtils and NPCUtils.GetCharacterID then
        id = NPCUtils.GetCharacterID(player)
    end
    if not id then return end

    local side = args.factionSide
    if NPCFactionBridge and NPCFactionBridge.NormalizeSide then
        side = NPCFactionBridge.NormalizeSide(side) or NPCFactionBridge.DefaultPlayerSide()
    end

    local current = gmd.OnlinePlayers[id] or {}
    current.id = id
    current.name = args.name or current.name
    current.factionSide = side
    current.factionExpiresAt = tonumber(args.factionExpiresAt)
    current.factionReason = args.factionReason
    current.factionUpdatedAt = tonumber(args.factionUpdatedAt) or (getGameTime() and getGameTime():getWorldAgeHours() or 0)
    gmd.OnlinePlayers[id] = current
    gmd.OnlinePlayers[tostring(id)] = current

    if NPCFactionBridge and NPCFactionBridge.ForgetPlayerAsThreat then
        pcall(function() NPCFactionBridge.ForgetPlayerAsThreat(player) end)
    end

    sendServerCommand('NPCFaction', 'PlayerFactionChanged', {
        id = id,
        name = current.name,
        factionSide = current.factionSide,
        factionExpiresAt = current.factionExpiresAt,
        factionReason = current.factionReason,
        factionUpdatedAt = current.factionUpdatedAt
    })
end

NPCServerRuntime.NPCSim.StateUpdate = function(player, args)
    if not args or not args.id then return end

    local gmd = GetNPCModData()
    NPCServerEnsureWorldTables(gmd)

    local id = args.id
    local queueKey = NPCServerGetQueueKey(gmd, id)
    local brain = gmd.Queue and gmd.Queue[queueKey] or nil
    if not brain then return end

    if args.uid and not brain.uid then brain.uid = args.uid end
    if args.persistentId and not brain.persistentId then brain.persistentId = args.persistentId end

    if NPCIdentityBridge and NPCIdentityBridge.EnsureBrain then
        brain = NPCIdentityBridge.EnsureBrain(brain, gmd, id, true)
    end

    local now = getGameTime():getWorldAgeHours()

    if args.x and args.y then
        brain.debugCoords = {x=tonumber(args.x), y=tonumber(args.y), z=tonumber(args.z) or 0}
        brain.x = tonumber(args.x)
        brain.y = tonumber(args.y)
        brain.z = tonumber(args.z) or 0
        brain.debugUpdated = now
    end

    if args.health then brain.health = tonumber(args.health) or brain.health end
    if args.maxHealth then brain.maxHealth = tonumber(args.maxHealth) or brain.maxHealth end
    if args.role then brain.role = args.role end
    if args.tacticalRole then brain.tacticalRole = args.tacticalRole end
    if args.relationshipToPlayer then brain.relationshipToPlayer = args.relationshipToPlayer end
    if args.currentWeapon then brain.currentWeapon = args.currentWeapon end
    if args.ammo then brain.ammo = args.ammo end
    if args.inventoryLite then brain.inventoryLite = args.inventoryLite end
    if args.needs then brain.needs = args.needs end
    if args.stock then brain.stock = args.stock end
    if args.skills then brain.skills = args.skills end
    if args.xp then brain.xp = args.xp end
    if args.morale then brain.morale = args.morale end
    if args.fear then brain.fear = args.fear end
    if args.aggression then brain.aggression = args.aggression end
    if args.discipline then brain.discipline = args.discipline end
    if args.lastKnownEnemyPosition then brain.lastKnownEnemyPosition = args.lastKnownEnemyPosition end
    if args.weapons then brain.weapons = args.weapons end
    if args.inventory then brain.inventory = args.inventory end
    if args.loot then brain.loot = args.loot end
    if args.worldGroupId then brain.worldGroupId = args.worldGroupId end
    if args.groupId then brain.groupId = args.groupId end
    if args.homeBase then brain.homeBase = args.homeBase end
    if args.homeBaseId then brain.homeBaseId = args.homeBaseId end
    if args.currentTask then brain.lastTask = args.currentTask end
    if args.lastTask then brain.lastTask = args.lastTask end
    if args.fsm then brain.fsm = args.fsm end
    if args.reason then brain.reason = args.reason end
    if args.fullname then brain.fullname = args.fullname end
    if args.name and not brain.fullname then brain.fullname = args.name end
    if args.female ~= nil then brain.female = args.female == true end
    if args.voice then brain.voice = args.voice end
    if args.outfit then brain.outfit = args.outfit end
    if args.skinTexture then brain.skinTexture = args.skinTexture end
    if args.skinColor then brain.skinColor = args.skinColor end
    if args.hairStyle then brain.hairStyle = args.hairStyle end
    if args.hairColor then brain.hairColor = args.hairColor end
    if args.beardStyle then brain.beardStyle = args.beardStyle end
    if args.beardColor then brain.beardColor = args.beardColor end
    if args.clan then brain.clan = args.clan end
    if args.hostile ~= nil then brain.hostile = args.hostile == true end
    if args.master ~= nil then brain.master = args.master end
    if args.permanent ~= nil then brain.permanent = args.permanent == true end
    if args.endurance then brain.endurance = tonumber(args.endurance) or brain.endurance end
    if args.infection then brain.infection = tonumber(args.infection) or brain.infection end
    if args.key then brain.key = args.key end
    if args.order then
        if type(args.order) == "table" then
            brain.order = args.order
        else
            if not brain.order or type(brain.order) ~= "table" then brain.order = {} end
            brain.order.name = args.order
        end
    end
    if args.fireMode then
        if not brain.order or type(brain.order) ~= "table" then brain.order = {name = brain.sim and brain.sim.order or "Auto"} end
        brain.order.fireMode = args.fireMode
        brain.fireMode = args.fireMode
    end
    if args.program then brain.program = args.program end
    if args.sim then brain.sim = args.sim end
    if args.watchdog then brain.watchdog = args.watchdog end
    if args.debug then brain.debug = args.debug end
    if args.dna then brain.dna = args.dna end
    if args.location and args.location.x and args.location.y then
        brain.debugCoords = {x=tonumber(args.location.x), y=tonumber(args.location.y), z=tonumber(args.location.z) or 0}
        brain.x = tonumber(args.location.x)
        brain.y = tonumber(args.location.y)
        brain.z = tonumber(args.location.z) or 0
    end
    if args.roadPatrol ~= nil then brain.roadPatrol = args.roadPatrol == true end
    if args.roadBias ~= nil then brain.roadBias = args.roadBias == true end
    if args.preferRoads ~= nil then brain.preferRoads = args.preferRoads == true end
    if args.patrolColor then brain.patrolColor = args.patrolColor end
    if args.factionSide then brain.factionSide = args.factionSide end
    if args.faction then brain.faction = args.faction end
    if args.factionState then brain.factionState = args.factionState end
    if args.factionReason then brain.factionReason = args.factionReason end
    if args.factionShoot ~= nil then brain.factionShoot = args.factionShoot == true end
    if args.mercenary ~= nil then brain.mercenary = args.mercenary == true end
    if args.mercenaryElite ~= nil then brain.mercenaryElite = args.mercenaryElite == true end
    if args.mercenaryHired ~= nil then brain.mercenaryHired = args.mercenaryHired == true end
    if args.mercenaryHiredBy ~= nil then brain.mercenaryHiredBy = args.mercenaryHiredBy end
    if args.mercenaryHiredByName ~= nil then brain.mercenaryHiredByName = args.mercenaryHiredByName end
    if args.encounterId then brain.encounterId = args.encounterId end
    if args.inBattle ~= nil then brain.inBattle = args.inBattle == true end
    if args.virtualBattle ~= nil then brain.virtualBattle = args.virtualBattle == true end
    if args.battleId then brain.battleId = args.battleId end
    if args.enemyGroupId then brain.enemyGroupId = args.enemyGroupId end
    if args.battleEnemyGroupId then brain.battleEnemyGroupId = args.battleEnemyGroupId end

    if not brain.sim then brain.sim = {} end
    if args.state then brain.sim.state = args.state end
    if args.order and type(args.order) ~= "table" then brain.sim.order = args.order end
    if args.order and type(args.order) == "table" then brain.sim.order = args.order.name or brain.sim.order end
    if args.fireMode then brain.sim.fireMode = args.fireMode end
    if args.programName then brain.sim.programName = args.programName end
    if args.programStage then brain.sim.programStage = args.programStage end
    brain.sim.updated = now

    if not brain.debug then brain.debug = {} end
    brain.debug.state = brain.sim.state
    brain.debug.order = brain.sim.order
    brain.debug.fireMode = brain.sim.fireMode

    if not brain.watchdog then brain.watchdog = {} end
    if args.stuck ~= nil then brain.watchdog.stuck = args.stuck == true end
    if args.stuckTicks then brain.watchdog.stuckTicks = tonumber(args.stuckTicks) or 0 end
    if args.lastMove then brain.watchdog.lastMove = tonumber(args.lastMove) or brain.watchdog.lastMove end
    brain.debug.watchdog = brain.watchdog.stuck

    gmd.Queue[queueKey] = brain

    if NPCIdentityBridge and NPCIdentityBridge.TouchRegistry then
        NPCIdentityBridge.TouchRegistry(gmd, brain, id)
    end

    if bsc_updateRuntimeDebugMarker then
        bsc_updateRuntimeDebugMarker(gmd, queueKey, brain, args, now)
    end

    if bsc_refreshPhysicalGroupMarkerThrottled then
        bsc_refreshPhysicalGroupMarkerThrottled(gmd, brain.worldGroupId or brain.groupId or args.worldGroupId or args.groupId, now)
    end

    local syncPayload = {
        id=id,
        uid=brain.uid,
        x=brain.debugCoords and brain.debugCoords.x or nil,
        y=brain.debugCoords and brain.debugCoords.y or nil,
        z=brain.debugCoords and brain.debugCoords.z or 0,
        health=brain.health,
        maxHealth=brain.maxHealth,
        role=brain.role,
        tacticalRole=brain.tacticalRole,
        relationshipToPlayer=brain.relationshipToPlayer,
        currentWeapon=brain.currentWeapon,
        ammo=brain.ammo,
        inventoryLite=brain.inventoryLite,
        state=brain.sim and brain.sim.state or nil,
        order=brain.sim and brain.sim.order or nil,
        fireMode=brain.sim and brain.sim.fireMode or nil,
        factionSide=brain.factionSide,
        faction=brain.faction,
        factionState=brain.factionState,
        factionReason=brain.factionReason,
        factionShoot=brain.factionShoot,
        programName=brain.sim and brain.sim.programName or nil,
        programStage=brain.sim and brain.sim.programStage or nil,
        stuck=brain.watchdog and brain.watchdog.stuck or false,
        stuckTicks=brain.watchdog and brain.watchdog.stuckTicks or 0,
        updated=brain.sim and brain.sim.updated or now
    }
    if NPCNetContract and NPCNetContract.SendSimStateUpdate then
        NPCNetContract.SendSimStateUpdate(syncPayload)
    else
        sendServerCommand('NPCSim', 'StateUpdate', syncPayload)
    end
end

NPCServerEnsureWorldTables = function(gmd)
    if not gmd.Queue then gmd.Queue = {} end
    if not gmd.VirtualGroups then gmd.VirtualGroups = {} end
    if not gmd.DebugMapMarkers then gmd.DebugMapMarkers = {} end
    if not gmd.Registry then gmd.Registry = {} end
    if not gmd.RuntimeToUID then gmd.RuntimeToUID = {} end
    if not gmd.UIDToRuntime then gmd.UIDToRuntime = {} end
    if not gmd.DeadRegistry then gmd.DeadRegistry = {} end
    if not gmd.PersistentNPCs then gmd.PersistentNPCs = {} end
    if not gmd.PersistentGroups then gmd.PersistentGroups = {} end
    if not gmd.PersistentRuntimeToUID then gmd.PersistentRuntimeToUID = {} end
    if not gmd.PersistentUIDToRuntime then gmd.PersistentUIDToRuntime = {} end
    if not gmd.NextPersistentId then gmd.NextPersistentId = 1 end
    if NPCIdentityBridge and NPCIdentityBridge.EnsureGlobalData then
        NPCIdentityBridge.EnsureGlobalData(gmd)
    end
    if NPCPersistentNPCBridge and NPCPersistentNPCBridge.EnsureData then
        NPCPersistentNPCBridge.EnsureData(gmd)
    end
    if not gmd.WorldDirector then
        gmd.WorldDirector = {
            enabled = true,
            initialized = false,
            nextGroupId = 1,
            lastUpdate = 0,
            lastSpawn = 0
        }
    end
end

NPCServerSendDebugMap = function(command, args, player)
    if not args then args = {} end
    if NPCNetContract and NPCNetContract.SendDebugMap then
        NPCNetContract.SendDebugMap(command, args, player)
    else
        sendServerCommand('NPCDebugMap', command, args)
    end
end

NPCServerGetQueueKey = function(gmd, id)
    if not gmd or not gmd.Queue or id == nil then return id end

    if gmd.Queue[id] then return id end

    local sid = tostring(id)
    if gmd.Queue[sid] then return sid end

    local nid = tonumber(id)
    if nid and gmd.Queue[nid] then return nid end

    for key, brain in pairs(gmd.Queue) do
        if type(brain) == "table" then
            if tostring(brain.id or "") == sid
                    or tostring(brain.runtimeId or "") == sid
                    or tostring(brain.zombieId or "") == sid
                    or tostring(brain.characterId or "") == sid
                    or tostring(brain.uid or "") == sid
                    or tostring(brain.persistentId or "") == sid then
                return key
            end
        end
    end

    return id
end

NPCServerSetDebugMarker = function(gmd, marker)
    if not gmd or not marker or not marker.id then return end

    NPCServerEnsureWorldTables(gmd)

    local originalId = marker.id
    if tostring(marker.markerType or "") == "npc" then
        local runtimeId = bsc_runtimeIdFromMarkerId(marker.runtimeId or marker.id)
        if not runtimeId or runtimeId == "" or runtimeId == "nil" then return end
        marker.runtimeId = runtimeId
        marker.id = bsc_npcMarkerId(runtimeId)
        if not marker.id then return end
        marker.worldGroupId = marker.worldGroupId or marker.groupId
    end

    marker.updatedAt = getGameTime():getWorldAgeHours()
    gmd.DebugMapMarkers[tostring(marker.id)] = marker
    NPCServerSendDebugMap('Update', marker)

    if tostring(marker.markerType or "") == "npc" then
        bsc_removeLegacyNpcMarker(gmd, originalId, marker.id)
    end
end

NPCServerRemoveDebugMarker = function(gmd, id, markerType)
    if not gmd or not id then return false end

    NPCServerEnsureWorldTables(gmd)

    local markerId = tostring(id)
    if markerType == "npc" then
        local npcId = bsc_npcMarkerId(id)
        if npcId and bsc_isNpcMarker(gmd.DebugMapMarkers[npcId]) then
            markerId = npcId
        elseif bsc_isNpcMarker(gmd.DebugMapMarkers[markerId]) then
            -- legacy raw NPC marker only; never remove a group marker with the same numeric id
        else
            return false
        end
    elseif markerType and tostring(gmd.DebugMapMarkers[markerId] and gmd.DebugMapMarkers[markerId].markerType or "") ~= tostring(markerType) then
        return false
    end

    gmd.DebugMapMarkers[markerId] = nil
    NPCServerSendDebugMap('Remove', {id=markerId})
    return true
end

bsc_updateRuntimeDebugMarker = function(gmd, queueKey, brain, args, now)
    if not (gmd and brain and args and args.x and args.y) then return end
    if not NPCServerSetDebugMarker then return end

    NPCServerEnsureWorldTables(gmd)

    local runtimeId = bsc_runtimeIdFromMarkerId(args.id or queueKey or brain.id or brain.uid or brain.persistentId)
    local markerId = bsc_npcMarkerId(runtimeId)
    if not markerId then return end

    local marker, oldMarkerId = bsc_getNpcDebugMarker(gmd, runtimeId, brain)
    if not marker then marker = {} end
    marker.id = markerId
    marker.markerType = "npc"
    marker.runtimeId = tostring(runtimeId)
    marker.uid = brain.uid or args.uid or marker.uid
    marker.persistentId = brain.persistentId or args.persistentId or marker.persistentId
    marker.groupId = bsc_brainGroupId(brain) or args.worldGroupId or args.groupId or marker.groupId
    marker.worldGroupId = marker.groupId
    marker.x = tonumber(args.x) or marker.x
    marker.y = tonumber(args.y) or marker.y
    marker.z = tonumber(args.z) or marker.z or 0
    marker.name = brain.fullname or args.fullname or args.name or marker.name or "NPC"
    marker.hostile = brain.hostile
    marker.friendly = not brain.hostile
    marker.factionSide = brain.factionSide or args.factionSide or marker.factionSide
    marker.faction = brain.faction or args.faction or marker.faction
    marker.side = brain.side or args.side or marker.side
    marker.factionState = brain.factionState or args.factionState or marker.factionState
    marker.program = brain.program and brain.program.name or args.programName or marker.program
    marker.state = brain.sim and brain.sim.state or args.state or marker.state
    marker.order = brain.sim and brain.sim.order or args.order or marker.order
    marker.fireMode = brain.sim and brain.sim.fireMode or args.fireMode or marker.fireMode
    marker.stuck = brain.watchdog and brain.watchdog.stuck or args.stuck == true or false
    marker.roadPatrol = brain.roadPatrol or args.roadPatrol or false
    marker.patrolColor = brain.patrolColor or args.patrolColor or marker.patrolColor
    marker.encounterId = brain.encounterId or args.encounterId or marker.encounterId
    marker.inBattle = brain.inBattle or brain.virtualBattle or args.inBattle or false
    marker.battleId = brain.battleId or args.battleId or marker.battleId
    marker.enemyGroupId = brain.battleEnemyGroupId or brain.enemyGroupId or args.enemyGroupId or marker.enemyGroupId
    marker.virtual = false
    marker.active = true
    marker.dead = false
    marker.updatedAt = now or getGameTime():getWorldAgeHours()

    if NPCSpyBridge and NPCSpyBridge.ApplyMarkerFields then NPCSpyBridge.ApplyMarkerFields(marker, brain) end
    if NPCLeadersBridge and NPCLeadersBridge.MarkerFields then NPCLeadersBridge.MarkerFields(marker, brain) end
    if NPCWounded and NPCWounded.MarkerFields then NPCWounded.MarkerFields(marker, brain) end
    if NPCLoyaltyBridge and NPCLoyaltyBridge.MarkerFields then NPCLoyaltyBridge.MarkerFields(marker, brain) end
    if NPCBountyBridge and NPCBountyBridge.MarkerFields then NPCBountyBridge.MarkerFields(marker, brain) end

    if oldMarkerId then bsc_removeLegacyNpcMarker(gmd, oldMarkerId, markerId) end
    NPCServerSetDebugMarker(gmd, marker)
end

bsc_refreshPhysicalGroupMarkerThrottled = function(gmd, groupId, now)
    if not (gmd and groupId and NPCServerRefreshWorldGroupMarker) then return end

    NPCServerEnsureWorldTables(gmd)
    gmd.WorldDirector = gmd.WorldDirector or {}
    gmd.WorldDirector.physicalGroupMarkerRefreshAt = gmd.WorldDirector.physicalGroupMarkerRefreshAt or {}

    local sid = tostring(groupId)
    local worldAge = tonumber(now) or getGameTime():getWorldAgeHours()
    local intervalHours = 0.0012
    local last = tonumber(gmd.WorldDirector.physicalGroupMarkerRefreshAt[sid]) or 0
    if worldAge - last < intervalHours then return end

    gmd.WorldDirector.physicalGroupMarkerRefreshAt[sid] = worldAge
    NPCServerRefreshWorldGroupMarker(gmd, sid)
end

NPCServerGetWorldGroupId = function(gmd, id)
    if not gmd or not id then return nil end

    local key = NPCServerGetQueueKey(gmd, id)
    local brain = gmd.Queue and gmd.Queue[key]
    local brainGroupId = bsc_brainGroupId(brain)
    if brainGroupId then
        return tostring(brainGroupId)
    end

    local marker = nil
    if gmd.DebugMapMarkers then
        marker = gmd.DebugMapMarkers[bsc_npcMarkerId(id) or ""] or gmd.DebugMapMarkers[tostring(id)]
    end
    if marker and (marker.worldGroupId or marker.groupId) then
        return tostring(marker.worldGroupId or marker.groupId)
    end

    return nil
end

local function bsc_revirtualizePersistentGroup(gmd, groupId, reason)
    if not (gmd and groupId and gmd.VirtualGroups) then return false end

    groupId = tostring(groupId)
    local group = gmd.VirtualGroups[groupId]
    if type(group) ~= "table" then return false end

    if NPCPersistentNPCBridge and NPCPersistentNPCBridge.RestoreGroupMembers then
        NPCPersistentNPCBridge.RestoreGroupMembers(gmd, group)
    end

    if type(group.members) ~= "table" or #group.members <= 0 then return false end
    if group.blackMarketDefenseQuestGroup == true or group.blackMarketDefenseQuestId ~= nil or group.spawnClass == "black_market_defense_enemy" then return false end

    group.count = #group.members
    group.activated = false
    group.virtual = true
    group.physicalIds = nil
    group.spawnPending = false
    group.spawnQueued = 0
    group.spawnFailed = false
    group.retryAfter = nil
    group.lastSpawnFailReason = nil
    if group.roadPatrol then
        group.state = group.hostile and "red_road_patrol" or "green_road_patrol"
    else
        group.state = group.homeBaseId and "base_patrol" or "roaming"
    end
    group.updatedAt = getGameTime and getGameTime():getWorldAgeHours() or 0
    gmd.VirtualGroups[groupId] = group

    if NPCPersistentNPCBridge and NPCPersistentNPCBridge.RegisterGroup then
        NPCPersistentNPCBridge.RegisterGroup(gmd, group)
    end

    NPCServerRemoveDebugMarker(gmd, groupId)
    print("[NPCWorldDirector] Revirtualized persistent group " .. tostring(groupId) .. " reason=" .. tostring(reason or "queue_empty"))
    return true
end

NPCServerRefreshWorldGroupMarker = function(gmd, groupId)
    if not gmd or not groupId then return 0 end

    NPCServerEnsureWorldTables(gmd)

    groupId = tostring(groupId)
    local aliveCount = 0
    local sumX = 0
    local sumY = 0
    local sumZ = 0

    if gmd.Queue then
        for id, brain in pairs(gmd.Queue) do
            if brain and bsc_brainGroupId(brain) and tostring(bsc_brainGroupId(brain)) == groupId then
                aliveCount = aliveCount + 1

                local marker = nil
                if gmd.DebugMapMarkers then
                    marker = gmd.DebugMapMarkers[bsc_npcMarkerId(id) or ""]
                    if not marker or not bsc_isNpcMarker(marker) then
                        local legacy = gmd.DebugMapMarkers[tostring(id)]
                        if bsc_isNpcMarker(legacy) then marker = legacy end
                    end
                end
                local x = marker and tonumber(marker.x)
                local y = marker and tonumber(marker.y)
                local z = marker and tonumber(marker.z)

                if not x and brain.bornCoords then x = tonumber(brain.bornCoords.x) end
                if not y and brain.bornCoords then y = tonumber(brain.bornCoords.y) end
                if not z and brain.bornCoords then z = tonumber(brain.bornCoords.z) end

                sumX = sumX + (x or 0)
                sumY = sumY + (y or 0)
                sumZ = sumZ + (z or 0)
            end
        end
    end

    if aliveCount <= 0 then
        if bsc_revirtualizePersistentGroup(gmd, groupId, "refresh_marker_queue_empty") then
            TransmitNPCModData()
            return 0
        end

        if gmd.VirtualGroups then
            gmd.VirtualGroups[groupId] = nil
        end

        NPCServerRemoveDebugMarker(gmd, groupId)

        if NPCWorldDirector and NPCWorldDirector.OnPhysicalGroupCleared then
            pcall(function()
                NPCWorldDirector.OnPhysicalGroupCleared(groupId)
            end)
        end

        print("[NPCWorldDirector] Removed empty physical group " .. tostring(groupId))
        TransmitNPCModData()
        return 0
    end

    local group = gmd.VirtualGroups and gmd.VirtualGroups[groupId] or nil
    if group then
        group.count = aliveCount
        group.activated = true
        group.virtual = false
        group.state = "physical"
        group.x = math.floor(sumX / aliveCount)
        group.y = math.floor(sumY / aliveCount)
        group.z = math.floor(sumZ / aliveCount)
        group.updatedAt = getGameTime():getWorldAgeHours()
        gmd.VirtualGroups[groupId] = group
    end

    local marker = gmd.DebugMapMarkers and gmd.DebugMapMarkers[groupId] or {}
    marker.id = groupId
    marker.markerType = "group"
    marker.x = group and group.x or math.floor(sumX / aliveCount)
    marker.y = group and group.y or math.floor(sumY / aliveCount)
    marker.z = group and group.z or math.floor(sumZ / aliveCount)
    marker.name = bsc_groupDisplayName(groupId, group, marker.name)
    marker.displayName = marker.name
    marker.count = aliveCount
    marker.hostile = group and group.hostile or marker.hostile
    marker.friendly = group and (not group.hostile) or marker.friendly
    marker.factionSide = group and group.factionSide or marker.factionSide
    marker.faction = group and group.faction or marker.faction
    marker.side = group and group.side or marker.side
    marker.program = group and group.program and group.program.name or marker.program
    marker.virtual = false
    marker.active = true
    marker.dead = false
    marker.state = "physical"
    if NPCSpyBridge and NPCSpyBridge.ApplyMarkerFields and group then NPCSpyBridge.ApplyMarkerFields(marker, group) end
    if NPCLeadersBridge and NPCLeadersBridge.MarkerFields and group then NPCLeadersBridge.MarkerFields(marker, group) end
    marker.updatedAt = getGameTime():getWorldAgeHours()

    gmd.DebugMapMarkers[groupId] = marker
    NPCServerSetDebugMarker(gmd, marker)
    TransmitNPCModData()

    return aliveCount
end


NPCServerRuntime.Commands.PostToggle = function(player, args)
    local gmd = GetNPCModData()
    if not (args.x and args.y and args.z) then return end

    local id = args.x .. "-" .. args.y .. "-" .. args.z
    
    if gmd.Posts[id] then
        gmd.Posts[id] = nil
    else
        gmd.Posts[id] = args
    end
end

NPCServerRuntime.Commands.PostUpdate = function(player, args)
    local gmd = GetNPCModData()
    if not (args.x and args.y and args.z) then return end

    local id = args.x .. "-" .. args.y .. "-" .. args.z
    gmd.Posts[id] = args
end

NPCServerRuntime.Commands.BaseUpdate = function(player, args)
    local gmd = GetNPCModData()
    if not (args.x and args.y) then return end

    local id = args.x .. "-" .. args.y
    gmd.Bases[id] = args
end

NPCServerRuntime.Commands[NPC_SERVER_LEGACY_COMMANDS.remove]  = function(player, args)
    local gmd = GetNPCModData()
    NPCServerEnsureWorldTables(gmd)

    if not args or not args.id then return end

    local id = args.id
    local queueKey = NPCServerGetQueueKey(gmd, id)
    local markerId = tostring(id)
    local groupId = args.groupId or NPCServerGetWorldGroupId(gmd, id)

    if gmd.Queue[queueKey] then
        if not (args.cleanup or args.orphanCleanup or args.runtimeCleanup) then
            if NPCIdentityBridge and NPCIdentityBridge.MarkDead then
                NPCIdentityBridge.MarkDead(gmd, gmd.Queue[queueKey], id)
            end
        end
        gmd.Queue[queueKey] = nil
        -- print ("[INFO] NPC removed: " .. id)
    elseif groupId then
        bsc_revirtualizePersistentGroup(gmd, groupId, "bandit_remove_missing_queue")
    end

    NPCServerRemoveDebugMarker(gmd, queueKey or markerId, "npc")

    if groupId then
        NPCServerRefreshWorldGroupMarker(gmd, groupId)
    end
    if NPCBlackMarketDefenseQuestServerBridge and NPCBlackMarketDefenseQuestServerBridge.OnNPCRemoved then
        pcall(function() NPCBlackMarketDefenseQuestServerBridge.OnNPCRemoved(player, args) end)
    end
end

NPCServerRuntime.Commands[NPC_SERVER_LEGACY_COMMANDS.flush]  = function(player, args)
    local gmd = GetNPCModData()
    gmd.Queue = {}
    gmd.VirtualGroups = {}
    gmd.DebugMapMarkers = {}
    gmd.Registry = {}
    gmd.RuntimeToUID = {}
    gmd.UIDToRuntime = {}
    gmd.DeadRegistry = {}
    gmd.PersistentNPCs = {}
    gmd.PersistentGroups = {}
    gmd.PersistentRuntimeToUID = {}
    gmd.PersistentUIDToRuntime = {}
    gmd.NextPersistentId = 1
    gmd.WorldDirector = {
        enabled = true,
        initialized = false,
        nextGroupId = 1,
        lastUpdate = 0,
        lastSpawn = 0
    }
    gmd.VisitedBuildings = {}
    gmd.Posts = {}
    gmd.Bases = {}
    NPCServerSendDebugMap('Clear', {})
    print ("[INFO] All bandits removed!!!")
end

NPCServerRuntime.Commands[NPC_SERVER_LEGACY_COMMANDS.updatePartCommand] = function(player, args)
    local gmd = GetNPCModData()
    local id = args.id
    local key = bsc_queueKeyForBrain(gmd, id)
    if key and gmd.Queue[key] then

        local brain = gmd.Queue[key]
        for k, v in pairs(args) do
            brain[k] = v
            -- print ("[INFO] NPC sync id: " .. id .. " key: " .. k)
        end

        gmd.Queue[key] = brain

        local groupId = bsc_groupIdOf(brain) or args.worldGroupId or args.groupId
        if brain.mercenaryHired == true and groupId then
            local sid = tostring(groupId)
            local group = gmd.VirtualGroups and gmd.VirtualGroups[sid] or nil
            if group then
                group.mercenaryHired = true
                group.mercenaryHiredBy = group.mercenaryHiredBy or brain.mercenaryHiredBy or brain.master
                group.isPlayerGuard = true
                if brain.order and brain.order.name == "Follow" then
                    group.followPlayer = group.mercenaryHiredBy
                    group.guardPlayer = nil
                end
                if args.x and args.y then
                    group.x = tonumber(args.x) or group.x
                    group.y = tonumber(args.y) or group.y
                    group.z = tonumber(args.z) or group.z or 0
                end
                group.activated = true
                group.virtual = false
                group.state = "physical"
                group.updatedAt = getGameTime and getGameTime():getWorldAgeHours() or group.updatedAt
                gmd.VirtualGroups[sid] = group
                if bsc_refreshPhysicalGroupMarkerThrottled then
                    bsc_refreshPhysicalGroupMarkerThrottled(gmd, sid, group.updatedAt)
                end
            end
        end

        sendServerCommand('NPCCommands', NPC_SERVER_LEGACY_COMMANDS.updatePart, args)
    end
end

NPCServerRuntime.Commands.SwitchProgram = function(player, args)
    if type(args) ~= "table" then return end

    local program = tostring(args.program or "")
    if program ~= "Companion" and program ~= "CompanionGuard" and program ~= "Looter" then return end

    local gmd = GetNPCModData()
    NPCServerEnsureWorldTables(gmd)
    if not (gmd and gmd.Queue) then return end

    local id = args.id
    local key = bsc_queueKeyForBrain(gmd, id)
    local brain = key and gmd.Queue[key] or nil
    if not brain then
        bsc_say(player, "Neutral bandit is not synchronized yet.")
        return
    end

    local pid = bsc_playerId(player)
    if not pid then return end

    local currentProgram = brain.program and brain.program.name or "Looter"
    if program == "Companion" or program == "CompanionGuard" then
        local clan = tonumber(brain.clan) or 0
        if brain.hostile or clan <= 0 then
            bsc_say(player, "Only neutral bandits can join you.")
            return
        end
        if brain.mercenaryHiredBy and tostring(brain.mercenaryHiredBy) ~= tostring(pid) then
            bsc_say(player, "This bandit is already hired by another player.")
            return
        end
    else
        local owner = brain.master or brain.mercenaryHiredBy
        if owner and tostring(owner) ~= tostring(pid) then
            bsc_say(player, "This bandit is not under your command.")
            return
        end
        if currentProgram ~= "Companion" and currentProgram ~= "CompanionGuard" then return end
    end

    bsc_applyNeutralProgram(brain, player, program)
    gmd.Queue[key] = brain
    bsc_syncProgramBrain(key, brain)
    bsc_updateNeutralCompanionMarker(gmd, key, brain)

    local groupId = args.groupId or bsc_groupIdOf(brain)
    if groupId then NPCServerRefreshWorldGroupMarker(gmd, tostring(groupId)) end

    if program == "Looter" then
        bsc_say(player, "Neutral bandit released.")
    else
        bsc_say(player, "Neutral bandit joined you.")
    end
end


local function bsc_spyBrainPosition(brain)
    if not brain then return nil, nil, nil end
    local coords = brain.debugCoords or brain.bornCoords or {}
    local x = brain.x or coords.x
    local y = brain.y or coords.y
    local z = brain.z or coords.z or 0
    return tonumber(x), tonumber(y), tonumber(z) or 0
end

local function bsc_findSpyTargetBrain(gmd, args)
    if not (gmd and gmd.Queue and type(args) == "table") then return nil, nil end

    local ids = {args.id, args.runtimeId, args.uid, args.persistentId}
    for _, id in ipairs(ids) do
        if id ~= nil then
            local key = bsc_queueKeyForBrain(gmd, id)
            local brain = key and gmd.Queue[key] or nil
            if brain then return key, brain end
        end
    end

    local groupId = args.groupId and tostring(args.groupId) or nil
    for qid, brain in pairs(gmd.Queue) do
        if type(brain) == "table" then
            if args.id ~= nil and (tostring(brain.id or qid) == tostring(args.id) or tostring(brain.runtimeId or "") == tostring(args.id)) then return qid, brain end
            if args.uid ~= nil and (tostring(brain.uid or "") == tostring(args.uid) or tostring(brain.persistentId or "") == tostring(args.uid)) then return qid, brain end
            if args.persistentId ~= nil and (tostring(brain.persistentId or "") == tostring(args.persistentId) or tostring(brain.uid or "") == tostring(args.persistentId)) then return qid, brain end
        end
    end

    local ax = tonumber(args.x)
    local ay = tonumber(args.y)
    if ax and ay then
        local bestKey, bestBrain, bestDist = nil, nil, 999999
        for qid, brain in pairs(gmd.Queue) do
            if type(brain) == "table" then
                local gid = brain.worldGroupId or brain.groupId
                local gxOk = (not groupId) or (gid and tostring(gid) == groupId)
                if gxOk then
                    local bx, by = bsc_spyBrainPosition(brain)
                    if bx and by then
                        local dx = bx - ax
                        local dy = by - ay
                        local dist = math.sqrt(dx * dx + dy * dy)
                        if dist <= 6.0 and dist < bestDist then
                            bestKey, bestBrain, bestDist = qid, brain, dist
                        end
                    end
                end
            end
        end
        if bestBrain then return bestKey, bestBrain end
    end

    return nil, nil
end



NPCServerRuntime.Commands.BribeSpy = function(player, args)
    if not (NPCSpyBridge and NPCSpyBridge.IsEnabled and NPCSpyBridge.IsEnabled()) then return end
    if type(args) ~= "table" then return end
    local gmd = GetNPCModData()
    NPCServerEnsureWorldTables(gmd)
    if not (gmd and gmd.Queue) then return end

    local key, brain = bsc_findSpyTargetBrain(gmd, args)
    if not brain then
        bsc_say(player, "Spy target lost.")
        return
    end
    if not NPCSpyBridge.CanBribeBrain(brain, player) then
        bsc_say(player, "This target cannot be recruited as a spy.")
        return
    end

    local paid, paymentKind = NPCSpyBridge.TakePayment(player)
    if not paid then
        local goldCost = bsc_settingNumber("Spy_GoldJewelryCost", 1, 0, 100)
        local silverCost = bsc_settingNumber("Spy_SilverJewelryCost", 3, 0, 300)
        local clientGold = tonumber(args.clientGold) or 0
        local clientSilver = tonumber(args.clientSilver) or 0
        if clientGold >= goldCost then
            paymentKind = "gold_client_seen"
            paid = true
        elseif bsc_settingBool("Spy_AllowSilverPayment", true) and clientSilver >= silverCost then
            paymentKind = "silver_client_seen"
            paid = true
        end
    end
    if not paid then
        bsc_say(player, "Need " .. tostring(NPCSpyBridge.GetPaymentLabel and NPCSpyBridge.GetPaymentLabel() or "jewelry") .. ".")
        return
    end
    if paymentKind == "gold_client_seen" or paymentKind == "silver_client_seen" then
        sendServerCommand(player, 'NPCCommands', 'RemoveSpyPayment', {kind=paymentKind})
    end

    if not NPCSpyBridge.MarkBrain(brain, player, paymentKind) then return end
    if NPCSpyBridge.ResolveBaseForBrain then
        local base = NPCSpyBridge.ResolveBaseForBrain(gmd, brain)
        if base then
            brain.homeBaseId = brain.homeBaseId or base.id or base.baseId
            brain.baseId = brain.baseId or base.id or base.baseId
            brain.spyBaseId = tostring(base.id or base.baseId)
        end
    end

    gmd.Queue[key] = brain
    if NPCSpyBridge.RegisterBrain then NPCSpyBridge.RegisterBrain(gmd, brain, player) end

    local groupId = brain.worldGroupId or brain.groupId or args.groupId
    if groupId then NPCSpyBridge.MarkGroupSpyState(gmd, groupId) end
    bsc_syncMercenaryBrain(key, brain)

    if NPCServerSetDebugMarker then
        if not gmd.DebugMapMarkers then gmd.DebugMapMarkers = {} end
        local markerId = bsc_npcMarkerId(key)
        local marker, oldMarkerId = bsc_getNpcDebugMarker(gmd, key, brain)
        if not marker then
            local coords = brain.debugCoords or brain.bornCoords or {}
            if coords.x or brain.x or args.x then
                marker = {id=markerId, markerType="npc", runtimeId=tostring(key), x=coords.x or brain.x or args.x, y=coords.y or brain.y or args.y, z=coords.z or brain.z or args.z or 0, name=brain.fullname or brain.name or "Spy"}
                gmd.DebugMapMarkers[markerId] = marker
            end
        end
        if marker and markerId then
            marker.id = markerId
            marker.markerType = "npc"
            marker.runtimeId = tostring(key)
            marker.groupId = bsc_brainGroupId(brain) or marker.groupId
            marker.worldGroupId = marker.groupId
            if oldMarkerId then bsc_removeLegacyNpcMarker(gmd, oldMarkerId, markerId) end
            if NPCSpyBridge.ApplyMarkerFields then NPCSpyBridge.ApplyMarkerFields(marker, brain) end
            NPCServerSetDebugMarker(gmd, marker)
        end
    end

    if NPCSpyBridge.MakeIntelForBrain and NPCSpyBridge.MakeIntelMarker then
        local intel = NPCSpyBridge.MakeIntelForBrain(gmd, brain, player)
        local intelMarker = intel and NPCSpyBridge.MakeIntelMarker(gmd, intel) or nil
        if intel then
            gmd.SpyIntel = gmd.SpyIntel or {}
            gmd.SpyIntel[#gmd.SpyIntel + 1] = intel
        end
        if intelMarker and NPCServerSetDebugMarker then NPCServerSetDebugMarker(gmd, intelMarker) end
    end

    if groupId and NPCServerRefreshWorldGroupMarker then
        NPCServerRefreshWorldGroupMarker(gmd, tostring(groupId))
    end
    bsc_say(player, "Spy recruited. He will infiltrate, report intel and sabotage his base.")
end

NPCServerRuntime.Commands.TakePrisoner = function(player, args)
    if not (NPCPrisonerBridge and NPCPrisonerBridge.IsEnabled and NPCPrisonerBridge.IsEnabled()) then return end
    if type(args) ~= "table" then return end

    local gmd = GetNPCModData()
    NPCServerEnsureWorldTables(gmd)

    local id = args.id
    local key = bsc_queueKeyForBrain(gmd, id)
    local brain = key and gmd.Queue and gmd.Queue[key] or nil
    if not brain then
        bsc_say(player, "Target lost.")
        return
    end

    if not NPCPrisonerBridge.CanTakeBrain(brain, player) then
        bsc_say(player, "This NPC is not ready to surrender.")
        return
    end

    NPCPrisonerBridge.MarkPrisoner(brain, player)
    gmd.Queue[key] = brain
    bsc_syncMercenaryBrain(key, brain)
    bsc_updatePrisonerMarker(gmd, key, brain)

    local groupId = brain.worldGroupId or brain.groupId or args.groupId
    if groupId and NPCServerRefreshWorldGroupMarker then
        NPCServerRefreshWorldGroupMarker(gmd, tostring(groupId))
    end

    bsc_say(player, "Prisoner secured. Interrogate him for intel.")
end

NPCServerRuntime.Commands.InterrogatePrisoner = function(player, args)
    if not (NPCPrisonerBridge and NPCPrisonerBridge.IsEnabled and NPCPrisonerBridge.IsEnabled()) then return end
    if type(args) ~= "table" then return end

    local gmd = GetNPCModData()
    NPCServerEnsureWorldTables(gmd)

    local id = args.id
    local key = bsc_queueKeyForBrain(gmd, id)
    local brain = key and gmd.Queue and gmd.Queue[key] or nil
    if not brain then
        bsc_say(player, "Prisoner lost.")
        return
    end

    local intel, err = NPCPrisonerBridge.InterrogateBrain(gmd, brain, player)
    if not intel then
        bsc_say(player, err or "No useful intel.")
        return
    end

    gmd.Queue[key] = brain
    bsc_syncMercenaryBrain(key, brain)
    bsc_updatePrisonerMarker(gmd, key, brain)

    local marker = NPCPrisonerBridge.MakeIntelMarker(gmd, intel)
    if marker and NPCServerSetDebugMarker then
        NPCServerSetDebugMarker(gmd, marker)
    end

    if NPCFactionDocsServer and NPCFactionDocsServer.GrantIntelReward then
        NPCFactionDocsServer.GrantIntelReward(player, brain.prisonerOriginalSide or bsc_brainSide(brain), "interrogation")
    end

    bsc_say(player, intel.text or "The prisoner gave you intel.")
end

NPCServerRuntime.Commands.ReleasePrisoner = function(player, args)
    if not NPCPrisonerBridge then return end
    if type(args) ~= "table" then return end

    local gmd = GetNPCModData()
    NPCServerEnsureWorldTables(gmd)

    local id = args.id
    local key = bsc_queueKeyForBrain(gmd, id)
    local brain = key and gmd.Queue and gmd.Queue[key] or nil
    if not brain then
        bsc_say(player, "Prisoner lost.")
        return
    end
    if brain.prisoner ~= true then return end

    NPCPrisonerBridge.ReleasePrisoner(brain, player)
    gmd.Queue[key] = brain
    bsc_syncMercenaryBrain(key, brain)
    bsc_updatePrisonerMarker(gmd, key, brain)

    local groupId = brain.worldGroupId or brain.groupId or args.groupId
    if groupId and NPCServerRefreshWorldGroupMarker then
        NPCServerRefreshWorldGroupMarker(gmd, tostring(groupId))
    end

    bsc_say(player, "Prisoner released.")
end

local function bsc_sameHireTarget(brain, qid, keepGroupId, keepId)
    if not brain then return false end
    if keepGroupId and bsc_groupIdOf(brain) and tostring(bsc_groupIdOf(brain)) == tostring(keepGroupId) then return true end
    if keepId then
        local sid = tostring(keepId)
        if tostring(qid or "") == sid then return true end
        if tostring(brain.id or "") == sid then return true end
        if tostring(brain.uid or "") == sid then return true end
        if tostring(brain.persistentId or "") == sid then return true end
    end
    return false
end

local function bsc_releasePlayerMercenarySquads(gmd, player, keepGroupId, keepId)
    if not (gmd and NPCMercenaryContract and NPCMercenaryContract.ReleaseBrain and NPCMercenaryContract.ReleaseGroup) then return 0 end
    local pid = bsc_playerId(player)
    if not pid then return 0 end
    if keepGroupId then keepGroupId = tostring(keepGroupId) end
    if keepId then keepId = tostring(keepId) end

    local released = 0
    if gmd.VirtualGroups then
        for gid, group in pairs(gmd.VirtualGroups) do
            if group and group.mercenaryHiredBy and tostring(group.mercenaryHiredBy) == tostring(pid) and tostring(gid) ~= tostring(keepGroupId or "") then
                NPCMercenaryContract.ReleaseGroup(gmd, group, player, {reason="replace_hired_squad"})
                gmd.VirtualGroups[gid] = group
                bsc_updateMercenaryGroupMarker(gmd, gid, group)
                released = released + 1
            end
        end
    end

    if gmd.Queue then
        for qid, brain in pairs(gmd.Queue) do
            if brain and brain.mercenaryHiredBy and tostring(brain.mercenaryHiredBy) == tostring(pid) and not bsc_sameHireTarget(brain, qid, keepGroupId, keepId) then
                NPCMercenaryContract.ReleaseBrain(brain, player, {reason="replace_hired_squad"})
                gmd.Queue[qid] = brain
                bsc_syncMercenaryBrain(qid, brain)
                bsc_updateMercenaryMarker(gmd, qid, brain)
                released = released + 1
                local oldGroupId = bsc_groupIdOf(brain)
                if oldGroupId and gmd.VirtualGroups and gmd.VirtualGroups[tostring(oldGroupId)] then
                    local oldGroup = gmd.VirtualGroups[tostring(oldGroupId)]
                    if oldGroup and oldGroup.mercenaryHiredBy and tostring(oldGroup.mercenaryHiredBy) == tostring(pid) then
                        NPCMercenaryContract.ReleaseGroup(gmd, oldGroup, player, {reason="replace_hired_squad"})
                        gmd.VirtualGroups[tostring(oldGroupId)] = oldGroup
                        bsc_updateMercenaryGroupMarker(gmd, tostring(oldGroupId), oldGroup)
                    end
                end
            end
        end
    end

    return released
end

NPCServerRuntime.Commands.HireMercenaryGroup = function(player, args)
    if not (NPCMercenaryContract and NPCMercenaryContract.IsHireEnabled and NPCMercenaryContract.IsHireEnabled()) then return end
    if type(args) ~= "table" then return end
    local serverReceiveMs = bsc_nowMs and bsc_nowMs() or 0

    local gmd = GetNPCModData()
    NPCServerEnsureWorldTables(gmd)

    local key, targetBrain = bsc_findBrainFromCommand(gmd, args)
    local targetZombie = nil
    if not targetBrain then
        key, targetBrain, targetZombie = bsc_findPhysicalBrainFromCommand(gmd, args)
    elseif not targetZombie then
        local physicalKey, physicalBrain, physicalZombie = bsc_findPhysicalBrainFromCommand(gmd, args)
        if physicalBrain and (physicalBrain == targetBrain
            or bsc_brainMatchesIds(physicalBrain, physicalKey, bsc_hireIdCandidates(args))
            or (bsc_groupIdOf(physicalBrain) and bsc_groupIdOf(targetBrain) and bsc_groupIdOf(physicalBrain) == bsc_groupIdOf(targetBrain)))
        then
            targetZombie = physicalZombie
            key = key or physicalKey
        end
    end

    local groupId, group = bsc_groupFromCommand(gmd, args, targetBrain)

    bsc_logMercenary("hire request id=" .. tostring(args.id) .. " runtime=" .. tostring(args.runtimeId) .. " pid=" .. tostring(args.persistentId) .. " group=" .. tostring(args.groupId) .. " key=" .. tostring(key) .. " found=" .. tostring(targetBrain ~= nil) .. " groupFound=" .. tostring(group ~= nil) .. bsc_mercenaryTelemetryText(args, serverReceiveMs))

    if not targetBrain and not group then
        bsc_sendMercenaryHireResult(player, false, "Mercenary target lost. Step closer and reopen the menu.", args)
        return
    end

    if targetBrain and NPCBlackMarketBridge and NPCBlackMarketBridge.IsNoCombatBrain and NPCBlackMarketBridge.IsNoCombatBrain(targetBrain) then
        bsc_sendMercenaryHireResult(player, false, "This black market contact cannot be hired.", args)
        return
    end

    local pid = bsc_playerId(player)
    if not pid then return end

    if not bsc_serverAllowsMercenaryHire(targetBrain, group, pid) then
        bsc_logMercenary("hire rejected: server-side target is not a blue mercenary pid=" .. tostring(pid) .. " group=" .. tostring(groupId) .. " argsMercenary=" .. tostring(args.mercenary) .. " argsSide=" .. tostring(args.brainSide))
        bsc_sendMercenaryHireResult(player, false, "Only blue mercenary squads can be hired.", args)
        return
    end

    if not bsc_hireTargetNearPlayer(player, targetBrain, targetZombie, group) then
        bsc_logMercenary("hire rejected: target too far from player pid=" .. tostring(pid) .. " group=" .. tostring(groupId) .. " key=" .. tostring(key))
        bsc_sendMercenaryHireResult(player, false, "Mercenary target lost. Step closer and reopen the menu.", args)
        return
    end

    if group and group.mercenaryHiredBy and tostring(group.mercenaryHiredBy) ~= tostring(pid) then
        bsc_sendMercenaryHireResult(player, false, "This mercenary squad is already hired.", args)
        return
    end
    if targetBrain and targetBrain.mercenaryHiredBy and tostring(targetBrain.mercenaryHiredBy) ~= tostring(pid) then
        bsc_sendMercenaryHireResult(player, false, "This mercenary squad is already hired.", args)
        return
    end

    local alreadyHired = (group and group.mercenaryHiredBy and tostring(group.mercenaryHiredBy) == tostring(pid))
        or (targetBrain and targetBrain.mercenaryHiredBy and tostring(targetBrain.mercenaryHiredBy) == tostring(pid))

    local paid, paymentKind = true, "already_hired"
    local takeClientPayment = false
    if not alreadyHired then
        paid, paymentKind = NPCMercenaryContract.TakePayment(player)
        if not paid then
            local clientGold = tonumber(args.clientPaymentGoldCount) or 0
            local clientSilver = tonumber(args.clientPaymentSilverCount) or 0
            local goldCost = NPCMercenaryContract.GetGoldJewelryCost and NPCMercenaryContract.GetGoldJewelryCost() or 0
            local silverCost = NPCMercenaryContract.GetSilverJewelryCost and NPCMercenaryContract.GetSilverJewelryCost() or 0
            local clientHasGold = goldCost > 0 and clientGold >= goldCost
            local clientHasSilver = NPCMercenaryContract.AllowSilverPayment and NPCMercenaryContract.AllowSilverPayment() and silverCost > 0 and clientSilver >= silverCost
            if clientHasGold or clientHasSilver then
                paid = true
                paymentKind = clientHasGold and "client_gold" or "client_silver"
                takeClientPayment = true
                bsc_logMercenary("payment accepted from client inventory snapshot kind=" .. tostring(paymentKind) .. " gold=" .. tostring(clientGold) .. " silver=" .. tostring(clientSilver))
            else
                bsc_logMercenary("payment failed kind=" .. tostring(paymentKind) .. " clientGold=" .. tostring(clientGold) .. " clientSilver=" .. tostring(clientSilver) .. " clientPayment=" .. tostring(args.clientPaymentOk))
                bsc_sendMercenaryHireResult(player, false, "Need payment: " .. tostring(NPCMercenaryContract.GetHireCostLabel()), args)
                return
            end
        end
    end

    local releasedPrevious = 0
    if not alreadyHired then
        releasedPrevious = bsc_releasePlayerMercenarySquads(gmd, player, groupId, key or args.id)
    end

    if group then
        NPCMercenaryContract.HireGroup(gmd, group, player, {formation="close", followDistance=3.0})
        gmd.VirtualGroups[groupId] = group
        bsc_updateMercenaryGroupMarker(gmd, groupId, group)
    end

    local changed = 0
    local targetIds = bsc_hireIdCandidates(args)
    if gmd.Queue then
        for qid, brain in pairs(gmd.Queue) do
            local sameGroup = groupId and bsc_groupIdOf(brain) == groupId
            local sameTarget = (key ~= nil and tostring(qid) == tostring(key)) or bsc_brainMatchesIds(brain, qid, targetIds)
            if sameGroup or sameTarget then
                NPCMercenaryContract.HireBrain(brain, player, {formation="close", followDistance=3.0})
                gmd.Queue[qid] = brain
                bsc_syncMercenaryBrain(qid, brain)
                bsc_updateMercenaryMarker(gmd, qid, brain)
                changed = changed + 1
            end
        end
    end

    if changed == 0 and targetBrain and key ~= nil then
        NPCMercenaryContract.HireBrain(targetBrain, player, {formation="close", followDistance=3.0})
        gmd.Queue[key] = targetBrain
        bsc_syncMercenaryBrain(key, targetBrain)
        bsc_updateMercenaryMarker(gmd, key, targetBrain)
        changed = 1
    end

    if group then
        bsc_markMercenaryHireStabilized(group, player, changed)
        bsc_markMercenarySquadLeader(gmd, group, groupId)
        gmd.VirtualGroups[groupId] = group
        if NPCPersistentNPCBridge and NPCPersistentNPCBridge.RegisterGroup then
            pcall(function() NPCPersistentNPCBridge.RegisterGroup(gmd, group) end)
        end
        bsc_updateMercenaryGroupMarker(gmd, groupId, group)
    end

    if targetZombie and targetBrain and NPCBrainData and NPCBrainData.Update then
        pcall(function() NPCBrainData.Update(targetZombie, targetBrain) end)
        bsc_writeNPCServiceIds(targetZombie, targetBrain, groupId)
    end

    if groupId and NPCServerRefreshWorldGroupMarker then NPCServerRefreshWorldGroupMarker(gmd, groupId) end
    if changed > 0 or group then
        local activeGroupId = groupId or (targetBrain and bsc_groupIdOf(targetBrain)) or args.groupId
        if activeGroupId then bsc_setActiveMercenarySquad(gmd, pid, activeGroupId) end
        local result = {
            id = targetBrain and (targetBrain.id or key) or args.id,
            runtimeId = args.runtimeId,
            persistentId = targetBrain and targetBrain.persistentId or args.persistentId,
            groupId = groupId or args.groupId,
            x = args.x,
            y = args.y,
            z = args.z,
            mercenaryHiredBy = pid,
            paymentKind = paymentKind,
            takeClientPayment = takeClientPayment == true,
            clientTraceId = args.clientTraceId,
            clientSendMs = tonumber(args.clientSendMs),
            clientOrderSeq = args.clientOrderSeq,
            clientEvent = args.clientEvent,
            serverReceiveMs = serverReceiveMs,
            serverAcceptMs = bsc_nowMs and bsc_nowMs() or serverReceiveMs
        }
        local okMessage = "Mercenary squad hired."
        if alreadyHired then
            okMessage = "Mercenaries are already under your command."
        elseif releasedPrevious > 0 then
            okMessage = "Mercenary squad hired. Previous squad released."
        end
        bsc_sendMercenaryHireResult(player, true, okMessage, result)
        bsc_logMercenary("hire success changed=" .. tostring(changed) .. " group=" .. tostring(groupId) .. " payment=" .. tostring(paymentKind) .. " releasedPrevious=" .. tostring(releasedPrevious))
    else
        bsc_sendMercenaryHireResult(player, false, "Mercenary target lost. Step closer and reopen the menu.", args)
    end
end

NPCServerRuntime.Commands.MercenaryGroupOrder = function(player, args)
    if not (NPCMercenaryContract and NPCMercenaryContract.IsHireEnabled and NPCMercenaryContract.IsHireEnabled()) then return end
    if type(args) ~= "table" then return end
    local serverReceiveMs = bsc_nowMs and bsc_nowMs() or 0

    local gmd = GetNPCModData()
    NPCServerEnsureWorldTables(gmd)

    local pid = bsc_playerId(player)
    if not pid then return end

    local requestedGroupId = args.groupId and tostring(args.groupId) or nil
    local groupId = requestedGroupId
    if not groupId then groupId = bsc_getActiveMercenarySquad(gmd, pid) end
    if requestedGroupId and not bsc_isMercenaryGroupOwnedByPlayer(gmd, requestedGroupId, pid) then
        bsc_logMercenary("order rejected: group not hired by player pid=" .. tostring(pid) .. " group=" .. tostring(requestedGroupId) .. " order=" .. tostring(args.orderName) .. bsc_mercenaryTelemetryText(args, serverReceiveMs))
        bsc_say(player, "This mercenary squad is not under your command.")
        return
    end
    if groupId and not bsc_isMercenaryGroupOwnedByPlayer(gmd, groupId, pid) then
        bsc_logMercenary("order ignored stale active group pid=" .. tostring(pid) .. " group=" .. tostring(groupId) .. " order=" .. tostring(args.orderName) .. bsc_mercenaryTelemetryText(args, serverReceiveMs))
        if requestedGroupId then
            bsc_say(player, "This mercenary squad is not under your command.")
            return
        end
        groupId = nil
    end

    local normalizedOrderName = bsc_normalizeMercenaryOrderName(args.orderName)
    local normalizedFireMode = bsc_normalizeMercenaryFireMode(args.fireMode)
    local normalizedFormation = bsc_normalizeMercenaryFormation(args.formation)
    local normalizedFollowDistance = bsc_clampMercenaryFollowDistance(args.followDistance)
    local rawFireMode = tostring(args.fireMode or "")
    local rawFormation = tostring(args.formation or "")
    local rawFollowDistance = tostring(args.followDistance or "")
    if rawFireMode ~= "" and rawFireMode ~= "nil" and not normalizedFireMode then
        bsc_logMercenary("order rejected: invalid fire mode pid=" .. tostring(pid) .. " group=" .. tostring(groupId) .. " fire=" .. tostring(args.fireMode) .. bsc_mercenaryTelemetryText(args, serverReceiveMs))
        bsc_say(player, "Unsupported mercenary fire mode.")
        return
    end
    if rawFormation ~= "" and rawFormation ~= "nil" and not normalizedFormation then
        bsc_logMercenary("order rejected: invalid formation pid=" .. tostring(pid) .. " group=" .. tostring(groupId) .. " formation=" .. tostring(args.formation) .. bsc_mercenaryTelemetryText(args, serverReceiveMs))
        bsc_say(player, "Unsupported mercenary formation.")
        return
    end
    if rawFollowDistance ~= "" and rawFollowDistance ~= "nil" and not normalizedFollowDistance then
        bsc_logMercenary("order rejected: invalid follow distance pid=" .. tostring(pid) .. " group=" .. tostring(groupId) .. " distance=" .. tostring(args.followDistance) .. bsc_mercenaryTelemetryText(args, serverReceiveMs))
        bsc_say(player, "Unsupported mercenary follow distance.")
        return
    end
    args.orderName = normalizedOrderName
    args.fireMode = normalizedFireMode
    args.formation = normalizedFormation
    args.followDistance = normalizedFollowDistance
    local hasOrderOverlay = normalizedFireMode ~= nil or normalizedFormation ~= nil or normalizedFollowDistance ~= nil
    if not normalizedOrderName and not hasOrderOverlay then
        bsc_logMercenary("order rejected: empty mercenary command pid=" .. tostring(pid) .. " group=" .. tostring(groupId) .. bsc_mercenaryTelemetryText(args, serverReceiveMs))
        return
    end
    local pointOrder = bsc_isMercenaryPointOrderName(normalizedOrderName)
    local followOrder = normalizedOrderName == "Follow"

    bsc_logMercenary("order request pid=" .. tostring(pid) .. " group=" .. tostring(groupId) .. " order=" .. tostring(args.orderName) .. " fire=" .. tostring(args.fireMode) .. " formation=" .. tostring(args.formation) .. " x=" .. tostring(args.x) .. " y=" .. tostring(args.y) .. " target=" .. tostring(args.targetType or args.anchorMode) .. bsc_mercenaryTelemetryText(args, serverReceiveMs))

    local anchor = nil
    if pointOrder and args.x and args.y then
        local ax = tonumber(args.x)
        local ay = tonumber(args.y)
        if ax and ay then
            anchor = {x=ax, y=ay, z=tonumber(args.z) or 0, facingAngle=tonumber(args.facingAngle)}
        end
    end
    if pointOrder and not anchor then
        bsc_logMercenary("order rejected: point order without cursor anchor pid=" .. tostring(pid) .. " order=" .. tostring(args.orderName) .. bsc_mercenaryTelemetryText(args, serverReceiveMs))
        bsc_say(player, "Mercenary order needs a world point. Right-click the target point and try again.")
        return
    end
    if pointOrder and not bsc_mercenaryPointAnchorNearPlayer(player, anchor) then
        bsc_logMercenary("order rejected: point anchor too far pid=" .. tostring(pid) .. " order=" .. tostring(args.orderName) .. " x=" .. tostring(anchor and anchor.x) .. " y=" .. tostring(anchor and anchor.y) .. " z=" .. tostring(anchor and anchor.z) .. bsc_mercenaryTelemetryText(args, serverReceiveMs))
        bsc_say(player, "Mercenary order target is too far away. Step closer and try again.")
        return
    end
    if normalizedOrderName == "LootHouse" and not bsc_anchorSquareIsInsideBuilding(anchor) then
        bsc_logMercenary("order rejected: LootHouse outside building pid=" .. tostring(pid) .. " group=" .. tostring(groupId) .. " x=" .. tostring(anchor and anchor.x) .. " y=" .. tostring(anchor and anchor.y) .. " z=" .. tostring(anchor and anchor.z) .. bsc_mercenaryTelemetryText(args, serverReceiveMs))
        bsc_say(player, "Search house works only when you click inside a building.")
        return
    end
    if bsc_throttleMercenaryOrder(gmd, pid, args, groupId) then
        bsc_logMercenary("order throttled pid=" .. tostring(pid) .. " group=" .. tostring(groupId) .. " order=" .. tostring(args.orderName) .. " fire=" .. tostring(args.fireMode) .. " formation=" .. tostring(args.formation) .. bsc_mercenaryTelemetryText(args, serverReceiveMs))
        return
    end

    gmd.MercenaryOrderRevision = (tonumber(gmd.MercenaryOrderRevision) or 0) + 1
    local orderRevision = gmd.MercenaryOrderRevision
    local orderBatchId = tostring(pid) .. ":" .. tostring(orderRevision)

    local data = {
        orderName = normalizedOrderName,
        anchor = anchor,
        targetType = pointOrder and "point" or (followOrder and "player" or nil),
        anchorMode = pointOrder and (args.anchorMode or "cursor") or (followOrder and "player" or nil),
        cursorAnchor = pointOrder == true or nil,
        fireMode = normalizedFireMode,
        formation = normalizedFormation,
        followDistance = normalizedFollowDistance,
        master = pid,
        groupId = groupId,
        orderRevision = orderRevision,
        groupOrderRevision = orderRevision,
        orderBatchId = orderBatchId,
        groupOrderBatchId = orderBatchId,
        orderIssuedMs = bsc_nowMs and bsc_nowMs() or nil,
        clientTraceId = args.clientTraceId,
        clientSendMs = tonumber(args.clientSendMs),
        clientOrderSeq = args.clientOrderSeq,
        clientEvent = args.clientEvent,
        serverReceiveMs = serverReceiveMs,
        forceImmediate = true,
        directMercenaryOrder = true,
        orderSystem = "mercenary_direct",
        interruptSeconds = normalizedOrderName == "Follow" and 10 or 7
    }

    local lootOrderName = tostring(args.orderName or "")
    local isLootOrder = lootOrderName == "Loot" or lootOrderName == "LootHouse"
        or lootOrderName == "LootBodies" or lootOrderName == "LootBodiesGear"
        or lootOrderName == "LootBodiesClothing" or lootOrderName == "LootBodiesWeapons"
        or lootOrderName == "LootBodiesAmmo" or lootOrderName == "LootBodiesMedical"
        or lootOrderName == "LootBodiesSupplies" or lootOrderName == "RearmHere"

    if isLootOrder then
        data.manualLoot = true
        data.manualSupplyLoot = true
        data.lootEquipUpgrades = true
        data.lootTakeWeapons = true
        data.lootTakeAmmo = true
        data.lootTakeArmor = true
        data.lootTakeClothing = true
        data.lootTakeMedical = true
        data.lootTakeFood = true
        data.lootBodiesOnly = lootOrderName == "LootBodies"
            or lootOrderName == "LootBodiesGear"
            or lootOrderName == "LootBodiesClothing"
            or lootOrderName == "LootBodiesWeapons"
            or lootOrderName == "LootBodiesAmmo"
            or lootOrderName == "LootBodiesMedical"
            or lootOrderName == "LootBodiesSupplies"

        if lootOrderName == "LootHouse" then
            data.lootRadius = 14
            data.lootMaxItems = 10
        elseif data.lootBodiesOnly then
            data.lootRadius = 18
            data.lootMaxItems = 10
            data.lootMaxContainers = 3
        else
            data.lootRadius = 18
            data.lootMaxItems = 8
        end

        if lootOrderName == "LootBodiesGear" then
            data.lootTakeMedical = false
            data.lootTakeFood = false
        elseif lootOrderName == "LootBodiesClothing" then
            data.lootTakeWeapons = false
            data.lootTakeAmmo = false
            data.lootTakeMedical = false
            data.lootTakeFood = false
        elseif lootOrderName == "LootBodiesWeapons" then
            data.lootTakeArmor = false
            data.lootTakeClothing = false
            data.lootTakeMedical = false
            data.lootTakeFood = false
        elseif lootOrderName == "LootBodiesAmmo" then
            data.lootEquipUpgrades = false
            data.lootTakeWeapons = false
            data.lootTakeArmor = false
            data.lootTakeClothing = false
            data.lootTakeMedical = false
            data.lootTakeFood = false
            data.lootMaxItems = 14
        elseif lootOrderName == "LootBodiesMedical" then
            data.lootEquipUpgrades = false
            data.lootTakeWeapons = false
            data.lootTakeAmmo = false
            data.lootTakeArmor = false
            data.lootTakeClothing = false
            data.lootTakeFood = false
            data.lootMaxItems = 12
        elseif lootOrderName == "LootBodiesSupplies" then
            data.lootEquipUpgrades = false
            data.lootTakeWeapons = false
            data.lootTakeArmor = false
            data.lootTakeClothing = false
            data.lootMaxItems = 12
        elseif lootOrderName == "RearmHere" then
            data.lootTakeFood = false
            data.lootRadius = 14
            data.lootMaxItems = 9
        end
    end

    local changed = 0
    local touchedGroup = false
    local touchedGroupRef = nil
    local cachedMembers = nil
    if groupId then
        local activeGroupId = bsc_getActiveMercenarySquad(gmd, pid)
        if not requestedGroupId or tostring(activeGroupId or "") == tostring(groupId) then
            cachedMembers = bsc_getActiveMercenaryMemberIds(gmd, pid)
        end
    end

    if groupId and gmd.VirtualGroups and (gmd.VirtualGroups[groupId] or gmd.VirtualGroups[tonumber(groupId)]) then
        local vgid = gmd.VirtualGroups[groupId] and groupId or tonumber(groupId)
        local group = gmd.VirtualGroups[vgid]
        if group and group.mercenaryHiredBy and tostring(group.mercenaryHiredBy) == tostring(pid) then
            NPCMercenaryContract.ApplyOrderToGroup(group, player, bsc_groupOnlyOrderData(data))
            gmd.VirtualGroups[vgid] = group
            bsc_updateMercenaryGroupMarker(gmd, vgid, group)
            touchedGroup = true
            touchedGroupRef = group
            changed = changed + 1
        end
    elseif gmd.VirtualGroups and not groupId then
        for gid, group in pairs(gmd.VirtualGroups) do
            if group and group.mercenaryHiredBy and tostring(group.mercenaryHiredBy) == tostring(pid) then
                groupId = tostring(gid)
                NPCMercenaryContract.ApplyOrderToGroup(group, player, bsc_groupOnlyOrderData(data))
                gmd.VirtualGroups[gid] = group
                bsc_updateMercenaryGroupMarker(gmd, gid, group)
                touchedGroup = true
                touchedGroupRef = group
                changed = changed + 1
                break
            end
        end
    end

    local foundMembers = {}
    local foundMemberSeen = {}
    local orderBatch = {
        _mercenaryTelemetry = {
            clientTraceId = args.clientTraceId,
            clientSendMs = tonumber(args.clientSendMs),
            clientOrderSeq = args.clientOrderSeq,
            clientEvent = args.clientEvent,
            serverReceiveMs = serverReceiveMs,
            orderAcceptedMs = bsc_nowMs and bsc_nowMs() or serverReceiveMs
        }
    }
    if cachedMembers and gmd.Queue then
        for _, qid in ipairs(cachedMembers) do
            local brain = gmd.Queue[qid] or gmd.Queue[tostring(qid)]
            if brain and brain.mercenaryHiredBy and tostring(brain.mercenaryHiredBy) == tostring(pid) then
                if (not groupId) or bsc_groupIdOf(brain) == tostring(groupId) then
                    if bsc_rememberMercenaryOrderMember(foundMembers, foundMemberSeen, qid, brain) then
                        NPCMercenaryContract.ApplyOrderToBrain(brain, player, data)
                        gmd.Queue[qid] = brain
                        bsc_queueMercenaryOrderPayload(orderBatch, qid, brain)
                        changed = changed + 1
                    end
                end
            end
        end
    end

    if #foundMembers == 0 and gmd.Queue then
        for qid, brain in pairs(gmd.Queue) do
            local sameGroup = (not groupId) or bsc_groupIdOf(brain) == tostring(groupId)
            local hiredByPlayer = brain and brain.mercenaryHiredBy and tostring(brain.mercenaryHiredBy) == tostring(pid)
            if sameGroup and hiredByPlayer then
                if not groupId then groupId = bsc_groupIdOf(brain) end
                if bsc_rememberMercenaryOrderMember(foundMembers, foundMemberSeen, qid, brain) then
                    NPCMercenaryContract.ApplyOrderToBrain(brain, player, data)
                    gmd.Queue[qid] = brain
                    bsc_queueMercenaryOrderPayload(orderBatch, qid, brain)
                    changed = changed + 1
                end
            end
        end
    end

    if #foundMembers == 0 and groupId and gmd.Queue and not requestedGroupId then
        local fallbackGroupId = nil
        for qid, brain in pairs(gmd.Queue) do
            local hiredByPlayer = brain and brain.mercenaryHiredBy and tostring(brain.mercenaryHiredBy) == tostring(pid)
            if hiredByPlayer then
                if not fallbackGroupId then fallbackGroupId = bsc_groupIdOf(brain) end
                if bsc_rememberMercenaryOrderMember(foundMembers, foundMemberSeen, qid, brain) then
                    NPCMercenaryContract.ApplyOrderToBrain(brain, player, data)
                    gmd.Queue[qid] = brain
                    bsc_queueMercenaryOrderPayload(orderBatch, qid, brain)
                    changed = changed + 1
                end
            end
        end
        if fallbackGroupId then
            bsc_logMercenary("order stale group fallback oldGroup=" .. tostring(groupId) .. " newGroup=" .. tostring(fallbackGroupId) .. " members=" .. tostring(#foundMembers))
            groupId = fallbackGroupId
        end
    end

    if touchedGroupRef then
        changed = changed + bsc_applyOrderToStoredGroupMembers(gmd, touchedGroupRef, player, pid, groupId, data, foundMembers, foundMemberSeen, orderBatch)
    end

    local physicalChanged = bsc_applyOrderToPhysicalMercenaries(gmd, player, pid, groupId, data, foundMembers, foundMemberSeen, orderBatch)
    if physicalChanged == 0 and groupId and #foundMembers == 0 and not requestedGroupId then
        physicalChanged = bsc_applyOrderToPhysicalMercenaries(gmd, player, pid, nil, data, foundMembers, foundMemberSeen, orderBatch)
    end
    changed = changed + physicalChanged

    bsc_flushMercenaryOrderBatch(orderBatch)

    if groupId and #foundMembers > 0 then
        bsc_setActiveMercenarySquad(gmd, pid, groupId)
    end

    bsc_logMercenary("order result pid=" .. tostring(pid) .. " group=" .. tostring(groupId) .. " changed=" .. tostring(changed) .. " members=" .. tostring(#foundMembers) .. " touchedGroup=" .. tostring(touchedGroup) .. " revision=" .. tostring(orderRevision) .. bsc_mercenaryTelemetryText(args, serverReceiveMs))

    if changed > 0 then
        bsc_say(player, bsc_mercenaryOrderFeedback(data, #foundMembers, changed, groupId))
    else
        bsc_say(player, "No hired mercenaries found for this order.")
    end
end

NPCServerRuntime.Commands.MercenaryOrderStatus = function(player, args)
    if not (NPCMercenaryContract and NPCMercenaryContract.IsHireEnabled and NPCMercenaryContract.IsHireEnabled()) then return end
    args = type(args) == "table" and args or {}
    local serverReceiveMs = bsc_nowMs and bsc_nowMs() or 0

    local gmd = GetNPCModData()
    NPCServerEnsureWorldTables(gmd)

    local pid = bsc_playerId(player)
    if not pid then return end

    local requestedGroupId = args.groupId and tostring(args.groupId) or nil
    local groupId = requestedGroupId
    if requestedGroupId and not bsc_isMercenaryGroupOwnedByPlayer(gmd, requestedGroupId, pid) then
        bsc_say(player, "This mercenary squad is not under your command.")
        return
    end
    if not groupId then groupId = bsc_getActiveMercenarySquad(gmd, pid) end

    bsc_logMercenary("status request pid=" .. tostring(pid) .. " group=" .. tostring(groupId) .. bsc_mercenaryTelemetryText(args, serverReceiveMs))
    local status = bsc_collectMercenaryStatus(gmd, player, pid, groupId)
    if (tonumber(status.count) or 0) <= 0 and groupId and not requestedGroupId then
        status = bsc_collectMercenaryStatus(gmd, player, pid, nil)
    end
    bsc_say(player, bsc_formatMercenaryStatus(status))
end

NPCServerRuntime.Commands.DebugMapRequest = function(player, args)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool and not NPCLegacySettingsBridge.GetBool("Net_DebugMapEnabled", true) then
        sendServerCommand(player, 'NPCDebugMap', 'Clear', {})
        return
    end

    local gmd = GetNPCModData()
    NPCServerEnsureWorldTables(gmd)

    if NPCWorldDirector and NPCWorldDirector.Bootstrap then
        NPCWorldDirector.Bootstrap()
    end
    if NPCWorldDirectorBridge and NPCWorldDirectorBridge.RefreshVirtualMapForSync and NPCWorldDirector then
        pcall(function() NPCWorldDirectorBridge.RefreshVirtualMapForSync(NPCWorldDirector, "debug_map_request", nil) end)
    elseif NPCWorldDirectorBridge and NPCWorldDirectorBridge.UpdateVirtualMapHeartbeat and NPCWorldDirector then
        pcall(function() NPCWorldDirectorBridge.UpdateVirtualMapHeartbeat(NPCWorldDirector, "debug_map_request") end)
    end

    if NPCNetContract and NPCNetContract.SendDebugMapSync then
        NPCNetContract.SendDebugMapSync(player, gmd)
    else
        NPCServerSendDebugMap('Sync', {markers = gmd.DebugMapMarkers}, player)
    end
end

NPCServerRuntime.Commands.DebugMapMaterializeNear = function(player, args)
    if not player or not args then return end
    if not (NPCWorldDirector and NPCWorldDirector.MaterializeGroup and NPCWorldDirector.EnsureData) then return end

    local markerId = args.markerId and tostring(args.markerId) or nil
    if not markerId or markerId == "" then return end

    local gmd = NPCWorldDirector.EnsureData()
    local group = gmd.VirtualGroups and gmd.VirtualGroups[markerId] or nil
    if not group or group.activated == true then return end
    if (tonumber(group.count) or 0) <= 0 then return end

    local px = tonumber(player:getX()) or 0
    local py = tonumber(player:getY()) or 0
    local gx = tonumber(group.x)
    local gy = tonumber(group.y)
    if not gx or not gy then return end

    local radius = bsc_settingNumber("Debug_VirtualMarkerActivationRadius", 70, 12, 220)
    local dx = gx - px
    local dy = gy - py
    if dx * dx + dy * dy > radius * radius then return end

    local worldAge = getGameTime and getGameTime():getWorldAgeHours() or 0
    if tonumber(group.retryAfter) and tonumber(group.retryAfter) > worldAge then return end

    local maxPhysical = tonumber(NPCWorldDirector.MAX_PHYSICAL_GROUPS) or bsc_settingNumber("World_MaxPhysicalGroups", 8, 1, 80)
    if NPCWorldDirector.GetPhysicalGroupCount and NPCWorldDirector.GetPhysicalGroupCount() >= maxPhysical then
        if NPCWorldDirector.DeferGroupActivation then
            NPCWorldDirector.DeferGroupActivation(group, "debug_marker_physical_group_cap")
        end
        return
    end

    NPCWorldDirector.MaterializeGroup(group, player)
end

NPCServerRuntime.Commands.DebugMapUpdate = function(player, args)
    local gmd = GetNPCModData()
    NPCServerEnsureWorldTables(gmd)

    if args and args.id then
        if args.dead then
            local id = args.id
            local queueKey = NPCServerGetQueueKey(gmd, id)
            local markerId = tostring(id)
            local groupId = args.groupId or NPCServerGetWorldGroupId(gmd, id)

            if gmd.Queue[queueKey] then
                if NPCIdentityBridge and NPCIdentityBridge.MarkDead then
                    NPCIdentityBridge.MarkDead(gmd, gmd.Queue[queueKey], id)
                end
                gmd.Queue[queueKey] = nil
            end

            NPCServerRemoveDebugMarker(gmd, queueKey or markerId, "npc")

            if groupId then
                NPCServerRefreshWorldGroupMarker(gmd, groupId)
            end
        else
            NPCServerSetDebugMarker(gmd, args)
        end
    end
end

NPCServerRuntime.Commands.DebugMapRemove = function(player, args)
    local gmd = GetNPCModData()
    if args and args.id then
        local markerType = args.markerType
        if not markerType and string.sub(tostring(args.id), 1, 4) == "npc:" then
            markerType = "npc"
        end
        NPCServerRemoveDebugMarker(gmd, args.id, markerType)
    end
end

NPCServerRuntime.Commands.AddEffect = function(player, args)
    sendServerCommand('NPCEffects', 'Add', args)
end

local function bsc_isBlackMarketServiceMember(member, event)
    if type(member) == "table" and (member.blackMarket == true or member.blackMarketNPC == true or member.blackMarketService == true or member.special == "BlackMarket") then return true end
    if type(event) == "table" and (event.blackMarketContact == true or event.blackMarketService == true or event.program and event.program.name == "BlackMarket") then return true end
    return false
end

local function bsc_applyBlackMarketServiceBrain(brain)
    if type(brain) ~= "table" then return brain end
    if NPCBlackMarketBridge and NPCBlackMarketBridge.ApplyServiceIdentity then
        return NPCBlackMarketBridge.ApplyServiceIdentity(brain)
    end
    brain.blackMarket = true
    brain.blackMarketNPC = true
    brain.blackMarketService = true
    brain.special = "BlackMarket"
    brain.nonCombatant = true
    brain.noAggro = true
    brain.noZombieTarget = true
    brain.immortal = true
    brain.noLoot = true
    brain.mercenary = false
    brain.mercenaryElite = false
    brain.hostile = false
    brain.factionSide = "black_market"
    brain.faction = "black_market"
    brain.side = "black_market"
    brain.patrolColor = "black_market"
    brain.factionState = "black_market_service"
    brain.factionShoot = false
    brain.relationshipToPlayer = "black_market"
    return brain
end

local function bsc_isHumanAnimationMember(bandit, brain)
    return (bandit and (bandit.forceHumanAnimation == true or bandit.humanNPC == true or bandit.noZombieAnimation == true or bandit.isFactionLeader == true or bandit.leaderPhysical == true or bandit.checkpointGuard == true or bandit.checkpointPhysical == true))
        or (brain and (brain.forceHumanAnimation == true or brain.humanNPC == true or brain.noZombieAnimation == true or brain.isFactionLeader == true or brain.leaderPhysical == true or brain.checkpointGuard == true or brain.checkpointPhysical == true))
end

local function bsc_applyHumanAnimationSanity(zombie, brain, bandit)
    if not (zombie and bsc_isHumanAnimationMember(bandit, brain)) then return false end
    local walkType = (bandit and (bandit.defaultWalkType or bandit.walkType)) or (brain and (brain.defaultWalkType or brain.walkType)) or "Walk"
    if walkType ~= "Run" and walkType ~= "WalkAim" then walkType = "Walk" end
    if brain then
        brain.humanNPC = true
        brain.forceHumanAnimation = true
        brain.noZombieAnimation = true
        brain.infection = 0
        brain.sound = 0
        brain.eatBody = false
        brain.dna = brain.dna or {}
        brain.dna.slow = false
        brain.dna.blind = false
        brain.dna.sneak = false
        brain.dna.unfit = false
        brain.dna.coward = false
    end
    local md = zombie.getModData and zombie:getModData() or nil
    if md then
        md.NPC_HUMAN_ANIMATION = true
        md.NPC_NO_ZOMBIE_ANIMATION = true
        md.NPC_IS_LIVE_HUMAN = true
        md[NPC_SERVER_LEGACY_KEYS.formerNPCZombie] = false
    end
    pcall(function() zombie:setNoTeeth(false) end)
    pcall(function() zombie:setReanim(false) end)
    pcall(function() zombie:setVariable(NPC_SERVER_LEGACY_KEYS.formerNPCZombie, false) end)
    pcall(function() zombie:setVariable(NPC_SERVER_LEGACY_KEYS.walkType, walkType) end)
    -- `zombieWalkType` is read-only in B41 MP and logs a warning even inside pcall; setWalkType below preserves behavior.
    pcall(function() zombie:setWalkType(walkType) end)
    pcall(function() zombie:setBumpType(walkType == "Run" and "IdleToRun" or "IdleToWalk") end)
    pcall(function() zombie:setCrawler(false) end)
    pcall(function() zombie:setFakeDead(false) end)
    pcall(function() zombie:setFallOnFront(false) end)
    pcall(function() zombie:setKnockedDown(false) end)
    pcall(function() zombie:setOnFloor(false) end)
    pcall(function() zombie:setSitAgainstWall(false) end)
    local emitter = zombie.getEmitter and zombie:getEmitter() or nil
    if emitter and emitter.stopAll then pcall(function() emitter:stopAll() end) end
    return true
end

NPCServerRuntime.Commands.SpawnGroup = function(player, event)
    if type(event) ~= "table" then return 0 end
    if type(event.bandits) ~= "table" then return 0 end

    local getSkinTexture = function(female, id)
        -- must be deterministc, do not use random
        local r = 1 + math.abs(id) % 5
        if female then
            return "FemaleBody0" .. tostring(r)
        else
            return "MaleBody0" .. tostring(r)
        end
    end

    local radius = 0.5
    local knockedDown = false
    local crawler = false
    local isFallOnFront = false
    local isFakeDead = false
    local isInvulnerable = false
    local isSitting = false
    local gmd = GetNPCModData()
    NPCServerEnsureWorldTables(gmd)

    if event.worldGroupId and NPCPersistentNPCBridge and NPCPersistentNPCBridge.RestoreGroupMembers and gmd.VirtualGroups then
        local group = gmd.VirtualGroups[tostring(event.worldGroupId)]
        if group then
            NPCPersistentNPCBridge.RestoreGroupMembers(gmd, group)
            if type(group.members) == "table" and #group.members > 0 then
                event.bandits = group.members
            end
        end
    end

    local baseX = math.floor(tonumber(event.x) or (player and player:getX()) or 0)
    local baseY = math.floor(tonumber(event.y) or (player and player:getY()) or 0)
    local gz = math.floor(tonumber(event.z) or 0)
    local spawnedCount = 0
    local banditList = {}
    for _, member in pairs(event.bandits) do
        banditList[#banditList + 1] = member
    end
    local totalNPCs = #banditList
    local spawnStart = math.floor(tonumber(event.spawnStart) or 1)
    local spawnLimit = math.floor(tonumber(event.spawnLimit) or totalNPCs)
    if spawnStart < 1 then spawnStart = 1 end
    if spawnLimit < 1 then spawnLimit = totalNPCs end
    local spawnEnd = math.min(totalNPCs, spawnStart + spawnLimit - 1)

    for banditIndex = spawnStart, spawnEnd do
        local bandit = banditList[banditIndex]
        local isBlackMarketService = bsc_isBlackMarketServiceMember(bandit, event)
        if isBlackMarketService then
            bandit = bsc_applyBlackMarketServiceBrain(bandit)
            bandit.uid = nil
            bandit.persistentId = nil
            bandit.permanent = false
            bandit.disablePersistence = true
        elseif NPCPersistentNPCBridge and NPCPersistentNPCBridge.ApplyProfileToMember then
            bandit = NPCPersistentNPCBridge.ApplyProfileToMember(gmd, bandit)
        end

        local gx = baseX
        local gy = baseY
 
        if totalNPCs > 1 then
            gx = ZombRand(baseX - radius, baseX + radius + 1)
            gy = ZombRand(baseY - radius, baseY + radius + 1)
        end

        if NPCHealthRegenBridge and NPCHealthRegenBridge.NormalizeSpawnHealth then
            bandit.health = NPCHealthRegenBridge.NormalizeSpawnHealth(bandit.health)
            bandit.maxHealth = bandit.health
        elseif not bandit.health or bandit.health < 3.0 then
            bandit.health = 3.0
            bandit.maxHealth = bandit.health
        end

        local zombieList = nil
        local spawnInvulnerable = isInvulnerable or bandit.immortal == true or bandit.blackMarket == true or bandit.blackMarketNPC == true
        local okSpawn, spawnedOrError = pcall(function()
            return NPCCompatibilityBridge.AddZombiesInOutfit(gx, gy, gz, bandit.outfit, bandit.femaleChance, crawler, isFallOnFront, isFakeDead, knockedDown, spawnInvulnerable, isSitting, bandit.health)
        end)
        if okSpawn then
            zombieList = spawnedOrError
        else
            print("[NPCWorldDirector] SpawnGroup AddZombiesInOutfit failed: " .. tostring(spawnedOrError))
        end

        local zombieCount = 0
        if zombieList then
            local okSize, sizeOrError = pcall(function() return zombieList:size() end)
            if okSize and sizeOrError then
                zombieCount = tonumber(sizeOrError) or 0
            end
        end

        for i=0, zombieCount-1 do
            local zombie = zombieList:get(i)
            local zombieVisuals = zombie:getHumanVisual()
            local id = NPCUtils.GetCharacterID(zombie)

            zombie:setHealth(bandit.health)

            -- clients will change that flag to true once they recognize the bandit by its ID
            zombie:setVariable(NPC_SERVER_LEGACY_KEYS.liveFlag, false)

            -- just in case
            NPCCompatibilityBridge.SafeSetPrimaryHandItem(zombie, nil)
            NPCCompatibilityBridge.SafeSetSecondaryHandItem(zombie, nil)
            zombie:clearAttachedItems()

            local brain = {}

            -- unique runtime bandit id based on outfit
            brain.id = id
            brain.uid = bandit.uid or bandit.persistentId
            brain.persistentId = bandit.persistentId or bandit.uid
            brain.memberIndex = bandit.memberIndex
            brain.homeBase = bandit.homeBase

            -- permanent bandits will store bandit details
            brain.permanent = bandit.permanent

            -- flag to simulate being in a vehicle
            brain.inVehicle = false

            -- gender
            if bandit.female ~= nil then
                brain.female = bandit.female == true
            else
                brain.female = zombie:isFemale()
            end

            -- time of birth
            brain.born = getGameTime():getWorldAgeHours()
            if event.worldDirector then
                brain.entryWakeUntilAge = brain.born + (8 / 3600)
            end

            -- place of birth
            brain.bornCoords = {}
            brain.bornCoords.x = gx
            brain.bornCoords.y = gy
            brain.bornCoords.z = gz

            -- initial health
            brain.health = bandit.health
            brain.maxHealth = bandit.maxHealth or bandit.health

            -- Only true companion spawns should follow the materializing player.
            -- Independent WorldDirector survivor groups use Looter-like AI and must
            -- not become passive player-followers just because a player approached.
            if event.worldDirector and event.program and event.program.name ~= "Companion" then
                brain.master = false
            elseif player then
                brain.master = NPCUtils.GetCharacterID(player)
            else
                brain.master = false
            end

            -- Link physical NPCs back to their virtual WorldDirector group.
            -- This allows the server to remove the global group marker when
            -- the last materialized NPC from the group is killed.
            brain.worldGroupId = event.worldGroupId
            brain.worldDirector = event.worldDirector or false
            brain.roadPatrol = event.roadPatrol or bandit.roadPatrol or false
            brain.roadBias = event.roadBias or bandit.roadBias or brain.roadPatrol or false
            brain.preferRoads = event.preferRoads or bandit.preferRoads or brain.roadBias or false
            brain.patrolColor = event.patrolColor or bandit.patrolColor
            brain.encounterId = event.encounterId or bandit.encounterId or bandit.roadEncounterId
            brain.inBattle = event.inBattle or bandit.inBattle or false
            brain.virtualBattle = event.virtualBattle or bandit.virtualBattle or false
            brain.battleId = event.battleId or bandit.battleId
            brain.battleEnemyGroupId = event.battleEnemyGroupId or bandit.battleEnemyGroupId or bandit.enemyGroupId

            -- for keyring
            brain.fullname = bandit.fullname or bandit.name or NPCNamesBridge.GenerateName(zombie:isFemale())
            brain.name = brain.fullname

            -- which voice to use
            brain.voice = bandit.voice or NPCEntity.PickVoice(zombie)

            -- hostility towards human players
            brain.hostile = event.hostile

            -- looks
            local hairColor = zombieVisuals:getHairColor()
            local beardColor = zombieVisuals:getBeardColor()
            local skinColor = zombieVisuals:getSkinColor()

            brain.appearanceSeed = bandit.appearanceSeed
            brain.faceProfile = bandit.faceProfile
            brain.skinTexture = bandit.skinTexture and bandit.skinTexture or getSkinTexture(zombie:isFemale(), tonumber(bandit.appearanceSeed or id) or id)
            brain.skinColor = bandit.skinColor and bandit.skinColor or {r=skinColor:getRedFloat(), g=skinColor:getGreenFloat(), b=skinColor:getBlueFloat()}
            brain.hairStyle = bandit.hairStyle and bandit.hairStyle or zombieVisuals:getHairModel()
            brain.hairColor = bandit.hairColor and bandit.hairColor or {r=hairColor:getRedFloat(), g=hairColor:getGreenFloat(), b=hairColor:getBlueFloat()}
            brain.beardStyle = bandit.beardStyle and bandit.beardStyle or zombieVisuals:getBeardModel()
            brain.beardColor = bandit.beardColor and bandit.beardColor or {r=beardColor:getRedFloat(), g=beardColor:getGreenFloat(), b=beardColor:getBlueFloat()}
            brain.outfit = bandit.outfit

            -- copy clan abilities to the bandit
            brain.clan = bandit.clan
            brain.eatBody = bandit.eatBody
            brain.accuracyBoost = tonumber(bandit.accuracyBoost) or 1
            if brain.accuracyBoost <= 0 then brain.accuracyBoost = 1 end

            -- the AI program to follow at start
            brain.program = {}
            brain.program.name = event.program.name
            brain.program.stage = event.program.stage

            -- random DNA
            local dna = bandit.dna
            if type(dna) ~= "table" then
                dna = {}
                dna.slow = NPCUtils.CoinFlip()
                dna.blind = NPCUtils.CoinFlip()
                dna.sneak = NPCUtils.CoinFlip()
                dna.unfit = NPCUtils.CoinFlip()
                dna.coward = NPCUtils.CoinFlip()
            end
            brain.dna = dna
            if bsc_isHumanAnimationMember(bandit, brain) then
                brain.dna.slow = false
                brain.dna.blind = false
                brain.dna.sneak = false
                brain.dna.unfit = false
                brain.dna.coward = false
            end

            -- program specific capabilities independent from clan
            -- brain.capabilities = ZombiePrograms[event.program.name].GetCapabilities()

            -- action and state flags
            brain.stationary = false
            brain.sleeping = false
            brain.aiming = false
            brain.moving = false
            brain.endurance = 1.00
            brain.speech = 0.00
            brain.sound = 0.00
            brain.infection = 0

            -- inventory
            brain.weapons = bandit.weapons
            brain.loot = bandit.loot
            brain.key = bandit.key
            brain.inventory = bandit.inventory or {}
            brain.inventoryLite = bandit.inventoryLite
            brain.currentWeapon = bandit.currentWeapon
            brain.ammo = bandit.ammo
            brain.role = bandit.role
            brain.tacticalRole = bandit.tacticalRole
            brain.strategicRole = bandit.strategicRole
            brain.homeBaseId = bandit.homeBaseId
            brain.homeBase = bandit.homeBase
            brain.homeBaseZoneType = bandit.homeBaseZoneType
            brain.baseZoneType = bandit.baseZoneType
            brain.guardPoint = bandit.guardPoint
            brain.patrolTarget = bandit.patrolTarget
            brain.checkpointId = bandit.checkpointId
            brain.strategicMarkerId = bandit.strategicMarkerId
            brain.leader = bandit.leader
            brain.isFactionLeader = bandit.isFactionLeader
            brain.leaderId = bandit.leaderId
            brain.leaderName = bandit.leaderName
            brain.leaderRole = bandit.leaderRole
            brain.leaderTitle = bandit.leaderTitle
            brain.leaderSide = bandit.leaderSide
            brain.leaderState = bandit.leaderState
            brain.leaderInfluence = bandit.leaderInfluence
            brain.leaderArchetype = bandit.leaderArchetype
            brain.humanNPC = bandit.humanNPC == true
            brain.forceHumanAnimation = bandit.forceHumanAnimation == true
            brain.noZombieAnimation = bandit.noZombieAnimation == true
            brain.leaderPhysical = bandit.leaderPhysical == true
            brain.defaultWalkType = bandit.defaultWalkType
            brain.walkType = bandit.walkType
            brain.relationshipToPlayer = bandit.relationshipToPlayer
            if bandit.blackMarketQuestGuard == true then
                brain.blackMarketQuestGuard = true
                brain.blackMarketQuestId = bandit.blackMarketQuestId
                brain.blackMarketQuestCacheId = bandit.blackMarketQuestCacheId
                brain.holdPoint = bandit.holdPoint
                brain.returnPoint = bandit.returnPoint
                brain.blackMarketQuestGuardLeash = bandit.blackMarketQuestGuardLeash
                brain.checkpointHoldRadius = bandit.checkpointHoldRadius
                brain.order = bandit.order
                brain.hostile = true
                brain.factionSide = bandit.factionSide or "black"
                brain.faction = bandit.faction or "black"
                brain.side = bandit.side or "black"
                brain.patrolColor = bandit.patrolColor or "black"
                brain.humanNPC = true
                brain.forceHumanAnimation = true
                brain.noZombieAnimation = true
                brain.defaultWalkType = bandit.defaultWalkType or brain.defaultWalkType or "Walk"
                brain.walkType = bandit.walkType or brain.walkType or "Walk"
            end
            if isBlackMarketService or bandit.blackMarket == true or bandit.blackMarketNPC == true or event.blackMarketContact == true then
                brain.blackMarket = true
                brain.blackMarketNPC = true
                brain.blackMarketService = true
                brain.blackMarketId = bandit.blackMarketId or event.blackMarketContactId or brain.persistentId or brain.uid
                brain.blackMarketSide = bandit.blackMarketSide
                brain.blackMarketCityX = bandit.blackMarketCityX or event.blackMarketCityX or gx
                brain.blackMarketCityY = bandit.blackMarketCityY or event.blackMarketCityY or gy
                brain.blackMarketCityRadius = bandit.blackMarketCityRadius or event.blackMarketCityRadius
                brain.uid = nil
                brain.persistentId = nil
                brain.permanent = false
                brain.disablePersistence = true
                brain.special = "BlackMarket"
                brain.nonCombatant = true
                brain.noAggro = true
                brain.noZombieTarget = true
                brain.immortal = true
                brain.noLoot = true
                brain.hostile = false
                brain.clan = 0
                brain = bsc_applyBlackMarketServiceBrain(brain)
                brain.weapons = {melee=false, primary={name=false, magSize=0, bulletsLeft=0, magCount=0}, secondary={name=false, magSize=0, bulletsLeft=0, magCount=0}}
                brain.loot = {}

                local contactId = tostring(brain.blackMarketId or "")
                local md = zombie:getModData()
                if md then
                    md.NPCBlackMarketBridge = true
                    md.BlackMarketNPC = true
                    md.BlackMarketId = contactId
                    md.BlackMarketRuntimeId = tostring(id)
                    md[NPC_SERVER_LEGACY_KEYS.runtimeId] = tostring(id)
                end
                pcall(function() zombie:setVariable(NPC_SERVER_LEGACY_KEYS.blackMarket, true) end)
                pcall(function() zombie:setVariable("BlackMarketId", contactId) end)
                pcall(function() zombie:setVariable(NPC_SERVER_LEGACY_KEYS.runtimeId, tostring(id)) end)
                pcall(function() zombie:setVariable(NPC_SERVER_LEGACY_KEYS.liveFlag, false) end)
                pcall(function() zombie:setTarget(nil) end)
                pcall(function() zombie:setAttackedBy(nil) end)
                if NPCBlackMarketBridge and NPCBlackMarketBridge.TouchContactRuntime and contactId ~= "" then
                    pcall(function() NPCBlackMarketBridge.TouchContactRuntime(gmd, contactId, id, zombie:getX(), zombie:getY(), zombie:getZ()) end)
                end
            end
            brain.baseGear = bandit.baseGear
            brain.baseGearWear = bandit.baseGearWear
            brain.baseGearWeaponKits = bandit.baseGearWeaponKits
            brain.baseGearWeaponParts = bandit.baseGearWeaponParts
            brain.baseGearMagazines = bandit.baseGearMagazines
            brain.baseGearBaseId = bandit.baseGearBaseId
            if NPCBaseSupplyServer and NPCBaseSupplyServer.ApplyVisualGearToZombie then
                NPCBaseSupplyServer.ApplyVisualGearToZombie(zombie, brain, bandit)
            end
            if (not isBlackMarketService) and NPCPersistentNPCBridge and NPCPersistentNPCBridge.ApplyProfileToBrain and not (brain.blackMarket == true or brain.blackMarketNPC == true or brain.special == "BlackMarket") then
                brain = NPCPersistentNPCBridge.ApplyProfileToBrain(gmd, brain, zombie, bandit)
            elseif isBlackMarketService then
                brain = bsc_applyBlackMarketServiceBrain(brain)
            end

            if (not isBlackMarketService) and NPCCreatorBridge and NPCCreatorBridge.ApplyHumanFacePresetToBrain then
                brain = NPCCreatorBridge.ApplyHumanFacePresetToBrain(brain, zombie, bandit, false)
            end

            if brain.fullname == nil and bandit.fullname then brain.fullname = bandit.fullname end
            brain.name = brain.fullname or brain.name
            bsc_stage448BoostBrainAmmo(brain, event)
            bsc_applyHumanAnimationSanity(zombie, brain, bandit)
            if bandit.blackMarketQuestGuard == true then
                brain.blackMarketQuestGuard = true
                brain.blackMarketQuestId = bandit.blackMarketQuestId
                brain.blackMarketQuestCacheId = bandit.blackMarketQuestCacheId
                brain.guardPoint = bandit.guardPoint or brain.guardPoint
                brain.holdPoint = bandit.holdPoint or brain.holdPoint
                brain.returnPoint = bandit.returnPoint or brain.returnPoint
                brain.blackMarketQuestGuardLeash = bandit.blackMarketQuestGuardLeash or brain.blackMarketQuestGuardLeash
                brain.checkpointHoldRadius = bandit.checkpointHoldRadius or brain.checkpointHoldRadius
                brain.order = bandit.order or brain.order
                brain.hostile = true
                brain.factionSide = "black"
                brain.faction = "black"
                brain.side = "black"
                brain.patrolColor = "black"
                brain.humanNPC = true
                brain.forceHumanAnimation = true
                brain.noZombieAnimation = true
                brain.defaultWalkType = brain.defaultWalkType or "Walk"
                brain.walkType = brain.walkType or "Walk"
            end
            if bandit.blackMarketDefenseEnemy == true then
                brain.blackMarketDefenseEnemy = true
                brain.blackMarketDefenseGuard = true
                brain.defenceGuard = true
                brain.blackMarketDefenseQuestId = bandit.blackMarketDefenseQuestId or bandit.blackMarketQuestId
                brain.blackMarketDefenseWave = bandit.blackMarketDefenseWave
                brain.blackMarketDefenseZoneRadius = bandit.blackMarketDefenseZoneRadius
                brain.blackMarketQuestGuard = true
                brain.blackMarketQuestId = brain.blackMarketDefenseQuestId or brain.blackMarketQuestId
                brain.blackMarketQuestGuardLeash = bandit.blackMarketQuestGuardLeash or brain.blackMarketQuestGuardLeash
                brain.checkpointHoldRadius = bandit.checkpointHoldRadius or brain.checkpointHoldRadius
                brain.guardPoint = bandit.guardPoint or brain.guardPoint
                brain.holdPoint = bandit.holdPoint or brain.holdPoint
                brain.returnPoint = bandit.returnPoint or brain.returnPoint
                brain.order = bandit.order or brain.order
                brain.role = bandit.role or "black_market_defense_guard"
                brain.tacticalRole = bandit.tacticalRole or "assault"
                brain.displayTitle = bandit.displayTitle or "DEFENCE GUARD"
                brain.nameplateTitle = bandit.nameplateTitle or "DEFENCE GUARD"
                brain.blackMarketDefenseMarkerColor = bandit.blackMarketDefenseMarkerColor or "black_market"
                brain.alwaysShowWorldMarker = true
                brain.xrayWorldMarker = true
                brain.targetClass = bandit.targetClass or "black_market_defense_player"
                brain.hostile = true
                brain.factionSide = "black"
                brain.faction = "black"
                brain.side = "black"
                brain.patrolColor = "black"
                brain.humanNPC = true
                brain.forceHumanAnimation = true
                brain.noZombieAnimation = true
                brain.defaultWalkType = brain.defaultWalkType or "Run"
                brain.walkType = brain.walkType or "Run"
            end
            
            -- empty task table, will be populated during bandit life
            brain.tasks = {}

            if event.worldDirector and (event.offscreenEntry or event.debugTeleportEntry or event.mercenaryLeashEntry or event.checkpointAnchorEntry) and event.entryTargetX and event.entryTargetY then
                local tx = tonumber(event.entryTargetX)
                local ty = tonumber(event.entryTargetY)
                local tz = tonumber(event.entryTargetZ) or gz
                if tx and ty then
                    local spread = (banditIndex % 5) - 2
                    local side = ((banditIndex * 2) % 5) - 2
                    tx = tx + spread
                    ty = ty + side

                    local dx = tx - gx
                    local dy = ty - gy
                    local dist = math.sqrt(dx * dx + dy * dy)
                    if dist < 1.0 then
                        tx = gx + spread
                        ty = gy + side
                        dx = tx - gx
                        dy = ty - gy
                        dist = math.sqrt(dx * dx + dy * dy)
                    end

                    local moveTask = nil
                    if NPCUtils and NPCUtils.GetMoveTask then
                        local okTask, taskOrError = pcall(function()
                            return NPCUtils.GetMoveTask(0.01, tx, ty, tz, "Run", math.max(2, dist), false)
                        end)
                        if okTask then moveTask = taskOrError end
                    end

                    if not moveTask then
                        moveTask = {action="Move", time=90, endurance=0.01, x=tx, y=ty, z=tz, walkType="Run", closeSlow=false}
                    end

                    moveTask.director = true
                    moveTask.directorState = "Entry"
                    moveTask.directorReason = event.debugTeleportEntry and "teleport marker materialization" or (event.mercenaryLeashEntry and "mercenary leash materialization" or (event.checkpointAnchorEntry and "checkpoint anchor materialization" or "offscreen materialization"))
                    moveTask.entryWake = event.debugTeleportEntry == true or event.checkpointAnchorEntry == true
                    table.insert(brain.tasks, moveTask)
                end
            end

            -- not used
            brain.world = {}

            -- print ("[INFO] NPC " .. brain.fullname .. "(".. id .. ") from clan " .. bandit.clan .. " in outfit " .. bandit.outfit .. " has joined the game.")
            gmd.Queue[id] = brain

            if not (brain.blackMarket == true or brain.blackMarketNPC == true or brain.special == "BlackMarket") then
                if NPCIdentityBridge and NPCIdentityBridge.EnsureBrain then
                    brain = NPCIdentityBridge.EnsureBrain(brain, gmd, id, true)
                    gmd.Queue[id] = brain
                end
                if NPCIdentityBridge and NPCIdentityBridge.TouchRegistry then
                    NPCIdentityBridge.TouchRegistry(gmd, brain, id)
                end
                if NPCPersistentNPCBridge and NPCPersistentNPCBridge.TouchFromRuntime and not brain.disablePersistence then
                    pcall(function() NPCPersistentNPCBridge.TouchFromRuntime(gmd, brain, id, zombie) end)
                end
            end

            if event.worldGroupId and gmd.VirtualGroups then
                local groupId = tostring(event.worldGroupId)
                local group = gmd.VirtualGroups[groupId]
                if group then
                    if not group.physicalIds then group.physicalIds = {} end
                    table.insert(group.physicalIds, tostring(id))
                    group.activated = true
                    group.virtual = false
                    group.state = "physical"
                    group.updatedAt = getGameTime():getWorldAgeHours()
                    gmd.VirtualGroups[groupId] = group
                end
            end

            if brain.blackMarket == true and NPCBlackMarketBridge and NPCBlackMarketBridge.GetContact and NPCBlackMarketBridge.MakeMarker then
                local contact = NPCBlackMarketBridge.GetContact(gmd, brain.blackMarketId)
                if contact then
                    contact.runtimeId = tostring(id)
                    contact.x = gx
                    contact.y = gy
                    contact.z = gz
                    contact.updatedAt = getGameTime():getWorldAgeHours()
                    local marker = NPCBlackMarketBridge.MakeMarker(contact)
                    if marker then NPCServerSetDebugMarker(gmd, marker) end
                end
            else
                local npcMarker = {
                    id = bsc_npcMarkerId(id),
                    markerType = "npc",
                    runtimeId = tostring(id),
                    groupId = event.worldGroupId,
                    worldGroupId = event.worldGroupId,
                    x = gx,
                    y = gy,
                    z = gz,
                    name = brain.leaderName or brain.fullname,
                    hostile = brain.hostile,
                    friendly = not brain.hostile,
                    factionSide = brain.factionSide,
                    faction = brain.faction,
                    side = brain.side,
                    factionState = brain.factionState,
                    program = brain.program and brain.program.name or nil,
                    role = brain.role,
                    tacticalRole = brain.tacticalRole,
                    strategicRole = brain.strategicRole,
                    blackMarketDefenseEnemy = brain.blackMarketDefenseEnemy == true or nil,
                    blackMarketDefenseGuard = brain.blackMarketDefenseGuard == true or nil,
                    defenceGuard = brain.defenceGuard == true or nil,
                    blackMarketDefenseQuestId = brain.blackMarketDefenseQuestId,
                    blackMarketDefenseWave = brain.blackMarketDefenseWave,
                    blackMarketQuestId = brain.blackMarketQuestId,
                    displayTitle = brain.displayTitle,
                    nameplateTitle = brain.nameplateTitle,
                    highContrastMapMarker = brain.blackMarketDefenseEnemy == true or nil,
                    stashMarkerOverhead = brain.blackMarketDefenseEnemy == true or nil,
                    alwaysShowWorldMarker = brain.blackMarketDefenseEnemy == true or nil,
                    xrayWorldMarker = brain.blackMarketDefenseEnemy == true or nil,
                    blackMarketDefenseMarkerColor = brain.blackMarketDefenseMarkerColor,
                    roadPatrol = brain.roadPatrol or false,
                    patrolColor = brain.patrolColor,
                    checkpointId = brain.checkpointId,
                    homeBaseId = brain.homeBaseId,
                    guardPoint = brain.guardPoint,
                    encounterId = brain.encounterId,
                    inBattle = brain.inBattle or brain.virtualBattle or false,
                    battleId = brain.battleId,
                    enemyGroupId = brain.battleEnemyGroupId,
                    virtual = false,
                    dead = false
                }
                if NPCLeadersBridge and NPCLeadersBridge.MarkerFields then
                    NPCLeadersBridge.MarkerFields(npcMarker, brain)
                end
                NPCServerSetDebugMarker(gmd, npcMarker)
            end

            if brain.blackMarket and NPCBlackMarketBridge and NPCBlackMarketBridge.TouchContactRuntime then
                NPCBlackMarketBridge.TouchContactRuntime(gmd, brain.blackMarketId, id, gx, gy, gz)
            end

            bsc_writeNPCServiceIds(zombie, brain, event.worldGroupId)
            bsc_applyHumanAnimationSanity(zombie, brain, bandit)
            spawnedCount = spawnedCount + 1
        end
    end

    if event.worldGroupId then
        if spawnedCount > 0 then
            NPCServerRefreshWorldGroupMarker(gmd, event.worldGroupId)
        elseif event.spawnQueued then
            -- A queued follow-up batch may legitimately fail if the area unloads mid-spawn.
            -- Keep the already materialized members and let NPCSpawnQueue retry/drop the batch.
        else
            local groupId = tostring(event.worldGroupId)
            local group = gmd.VirtualGroups and gmd.VirtualGroups[groupId] or nil
            if group then
                group.activated = false
                group.virtual = true
                group.physicalIds = nil
                group.spawnFailed = true
                group.spawnFailCount = (tonumber(group.spawnFailCount) or 0) + 1
                group.spawnFailedAt = getGameTime():getWorldAgeHours()
                group.retryAfter = group.spawnFailedAt + 0.015
                group.lastSpawnFailReason = "spawn_group_zero"
                if group.state == "physical" then group.state = "spawn_retry" end
                gmd.VirtualGroups[groupId] = group

                local marker = gmd.DebugMapMarkers and gmd.DebugMapMarkers[groupId] or {}
                marker.id = groupId
                marker.markerType = "group"
                marker.x = group.x or event.x
                marker.y = group.y or event.y
                marker.z = group.z or event.z or 0
                marker.name = bsc_groupDisplayName(groupId, group, marker.name)
                marker.displayName = marker.name
                marker.count = group.count
                marker.hostile = group.hostile
                marker.friendly = not group.hostile
                marker.program = group.program and group.program.name or marker.program
                marker.virtual = true
                marker.active = false
                marker.dead = false
                marker.state = group.state or "spawn_retry"
                marker.roadPatrol = group.roadPatrol or false
                marker.patrolColor = group.patrolColor
                marker.spawnFailed = true
                marker.spawnFailCount = group.spawnFailCount
                marker.spawnFailReason = group.lastSpawnFailReason
                marker.updatedAt = group.spawnFailedAt
                NPCServerSetDebugMarker(gmd, marker)
            end
        end
    end

    return spawnedCount
end

NPCServerRuntime.Commands.SpawnRestore = function(player, brain)
    local gmd = GetNPCModData()
    local knockedDown = false
    local crawler = false
    local isFallOnFront = false
    local isFakeDead = false
    local isInvulnerable = false
    local isSitting = false
    local health = brain.maxHealth or brain.health or 3.0
    if NPCHealthRegenBridge and NPCHealthRegenBridge.NormalizeSpawnHealth then
        health = NPCHealthRegenBridge.NormalizeSpawnHealth(health)
    elseif health < 3.0 then
        health = 3.0
    end
    brain.maxHealth = health
    brain.health = health
    local outfit = brain.outfit
    local oldId = brain.id
    local gx = brain.bornCoords.x
    local gy = brain.bornCoords.y
    local gz = brain.bornCoords.z

    local femaleChance = 0
    if brain.female then
        femaleChance = 100
    end

    local zombieList = NPCCompatibilityBridge.AddZombiesInOutfit(gx, gy, gz, outfit, femaleChance, crawler, isFallOnFront, isFakeDead, knockedDown, isInvulnerable, isSitting, health)
    for i=0, zombieList:size()-1 do
        local zombie = zombieList:get(i)
        local id = NPCUtils.GetCharacterID(zombie)

        zombie:setHealth(health)

        -- clients will change that flag to true once they recognize the bandit by its ID
        zombie:setVariable(NPC_SERVER_LEGACY_KEYS.liveFlag, false)

        -- just in case
        NPCCompatibilityBridge.SafeSetPrimaryHandItem(zombie, nil)
        NPCCompatibilityBridge.SafeSetSecondaryHandItem(zombie, nil)
        zombie:clearAttachedItems()

        -- we have new runtime id, but keep persistent UID
        brain.id = id

        if NPCIdentityBridge and NPCIdentityBridge.EnsureBrain then
            brain = NPCIdentityBridge.EnsureBrain(brain, gmd, id, true)
        end
        if NPCCreatorBridge and NPCCreatorBridge.ApplyHumanFacePresetToBrain then
            brain = NPCCreatorBridge.ApplyHumanFacePresetToBrain(brain, zombie, brain, false)
        end
        bsc_stage448BoostBrainAmmo(brain, nil)

        -- swap
        gmd.Queue[oldId] = nil
        gmd.Queue[id] = brain

        if NPCIdentityBridge and NPCIdentityBridge.TouchRegistry then
            NPCIdentityBridge.TouchRegistry(gmd, brain, id)
        end
        if NPCPersistentNPCBridge and NPCPersistentNPCBridge.TouchFromRuntime and not brain.disablePersistence then
            pcall(function() NPCPersistentNPCBridge.TouchFromRuntime(gmd, brain, id, zombie) end)
        end

        bsc_writeNPCServiceIds(zombie, brain, brain.worldGroupId or brain.groupId)
    end
end

local _getBarricadeAble = function(x, y, z, index)
    local sq = getCell():getGridSquare(x, y, z)
    if sq and index >= 0 and index < sq:getObjects():size() then
        local o = sq:getObjects():get(index)
        if instanceof(o, 'BarricadeAble') then
            return o
        end
    end
    return nil
end

NPCServerRuntime.Commands.Unbarricade = function(player, args)
    local object = _getBarricadeAble(args.x, args.y, args.z, args.index)
    if object then
        local barricade = object:getBarricadeOnSameSquare()
        if not barricade then barricade = object:getBarricadeOnOppositeSquare() end
        if barricade then
            if barricade:isMetal() then
                local metal = barricade:removeMetal(nil)
            elseif barricade:isMetalBar() then
                local bar = barricade:removeMetalBar(nil)
            else
                local plank = barricade:removePlank(nil)
                if barricade:getNumPlanks() > 0 then
                    barricade:sendObjectChange('state')
                end
            end
        end
    end
end

NPCServerRuntime.Commands.Barricade = function(player, args)
    local object = _getBarricadeAble(args.x, args.y, args.z, args.index)
    if object then
        local barricade = IsoBarricade.AddBarricadeToObject(object, player)
        if barricade then
            if not barricade:isMetal() and args.isMetal then
                local metal = NPCCompatibilityBridge.InstanceItem("Base.SheetMetal")
                metal:setCondition(args.condition)
                barricade:addMetal(nil, metal)
                barricade:transmitCompleteItemToClients()
            elseif not barricade:isMetalBar() and args.isMetalBar then
                local metal = NPCCompatibilityBridge.InstanceItem("Base.MetalBar")
                metal:setCondition(args.condition)
                barricade:addMetalBar(nil, metal)
                barricade:transmitCompleteItemToClients()
            elseif barricade:getNumPlanks() < 4 then
                local plank = NPCCompatibilityBridge.InstanceItem("Base.Plank")
                plank:setCondition(args.condition)
                barricade:addPlank(nil, plank)
                if barricade:getNumPlanks() == 1 then
                    barricade:transmitCompleteItemToClients()
                else
                    barricade:sendObjectChange('state')
                end
            end
        end
    else
        noise('expected BarricadeAble')
    end
end

local function NPCServerRecalcDoorArea(square, radius)
    return NPCWorldObjectCommandBridge.RecalcArea(square, radius)
end


local function NPCServerGetDestroyableObject(square, index)
    return NPCWorldObjectCommandBridge.GetDestroyableObject(square, index)
end

NPCServerRuntime.Commands.DestroyObject = function(player, args)
    local sq = NPCWorldObjectCommandBridge.GetSquare(args.x, args.y, args.z)
    local object = NPCServerGetDestroyableObject(sq, args.index)
    if object then
        -- Stage447: a DestroyObject request against a usable door is interpreted as
        -- a door-open request first. Barricaded/blocked doors still fall back to breach damage.
        if NPCWorldObjectCommandBridge.CanOpenDoorLikePlayer(object) and not NPCWorldObjectCommandBridge.DoorIsOpen(object) then
            NPCWorldObjectCommandBridge.OpenDoorObject(sq, object)
            return
        end
        NPCWorldObjectCommandBridge.DamageDestroyableObject(sq, object, player, args.damage)
    end
end

local function NPCServerIsDoorObject(object)
    return NPCWorldObjectCommandBridge.IsDoorObject(object)
end

local function NPCServerDoorLockedLikePlayer(object)
    return NPCWorldObjectCommandBridge.DoorLockedLikePlayer(object)
end

local function NPCServerDoorIsOpen(object)
    return NPCWorldObjectCommandBridge.DoorIsOpen(object)
end

local function NPCServerDoorIsBarricaded(object)
    return NPCWorldObjectCommandBridge.DoorIsBarricaded(object)
end

local function NPCServerCanOpenDoorLikePlayer(object)
    return NPCWorldObjectCommandBridge.CanOpenDoorLikePlayer(object)
end

local function NPCServerFindDoorOnSquare(sq, preferredIndex)
    return NPCWorldObjectCommandBridge.FindDoorOnSquare(sq, preferredIndex)
end

NPCServerRuntime.Commands.OpenDoor = function(player, args)
    local sq = NPCWorldObjectCommandBridge.GetSquare(args.x, args.y, args.z)
    local object = NPCServerFindDoorOnSquare(sq, args.index)
    NPCWorldObjectCommandBridge.OpenDoorObject(sq, object)
end

NPCServerRuntime.Commands.CloseDoor = function(player, args)
    local sq = NPCWorldObjectCommandBridge.GetSquare(args.x, args.y, args.z)
    local object = NPCServerFindDoorOnSquare(sq, args.index)
    NPCWorldObjectCommandBridge.CloseDoorObject(sq, object)
end

NPCServerRuntime.Commands.LockDoor = function(player, args)
    local sq = NPCWorldObjectCommandBridge.GetSquare(args.x, args.y, args.z)
    local object = NPCServerFindDoorOnSquare(sq, args.index)
    NPCWorldObjectCommandBridge.SetDoorLockedByKey(sq, object, true)
end

NPCServerRuntime.Commands.UnlockDoor = function(player, args)
    local sq = NPCWorldObjectCommandBridge.GetSquare(args.x, args.y, args.z)
    local object = NPCServerFindDoorOnSquare(sq, args.index)
    NPCWorldObjectCommandBridge.SetDoorLockedByKey(sq, object, false)
end

NPCServerRuntime.Commands.VehicleSpawn = function(player, args)
    local square = getCell():getGridSquare(args.x, args.y, 0)
    if square then
        local vehicle = addVehicleDebug(args.type, IsoDirections.S, nil, square)
        if vehicle then
            for i = 0, vehicle:getPartCount() - 1 do
                local container = vehicle:getPartByIndex(i):getItemContainer()
                if container then
                    container:removeAllItems()
                end
            end
            vehicle:repair()
            vehicle:setColor(0, 0, 0)

            if ZombRand(3) == 1 then
                vehicle:setAlarmed(true)
            end

            local cond = (2 + ZombRand(8)) / 10
            vehicle:setGeneralPartCondition(cond, 80)
            if args.engine then
                vehicle:setHotwired(true)
                vehicle:tryStartEngine(true)
                vehicle:engineDoStartingSuccess()
                vehicle:engineDoRunning()
            end

            if args.lights then
                vehicle:setHeadlightsOn(true)
            end

            if args.lightbar or args.siren or args.alarm then
                local newargs = {id=vehicle:getId(), lightbar=args.lightbar, siren=args.siren, alarm=args.alarm}
                sendServerCommand('NPCCommands', 'UpdateVehicle', newargs)
            end
        end
    end
end

NPCServerRuntime.Commands.VehiclePartRemove = function(player, args)
    local sq = getCell():getGridSquare(args.x, args.y, 0)
    if sq then
        local vehicle = sq:getVehicleContainer()
        if vehicle then
            local vehiclePart = vehicle:getPartById(args.id)
            if vehiclePart then
                vehiclePart:setInventoryItem(nil)
                vehicle:transmitPartItem(vehiclePart)
                vehicle:updatePartStats()
            end
        end
    end
end

NPCServerRuntime.Commands.VehiclePartDamage = function(player, args)
    local sq = getCell():getGridSquare(args.x, args.y, 0)
    if sq then
        local vehicle = sq:getVehicleContainer()
        if vehicle then
            local vehiclePart = vehicle:getPartById(args.id)
            if vehiclePart then
                vehiclePart:damage(args.dmg)

                if vehiclePart:getCondition() <= 0 then
                    vehiclePart:setInventoryItem(nil)
                    vehicle:transmitPartItem(vehiclePart)
                else
                    vehicle:transmitPartCondition(vehiclePart)
                end
                vehicle:updatePartStats()
            end
        end
    end
end

NPCServerRuntime.Commands[NPC_SERVER_LEGACY_COMMANDS.incrementKills] = function(player, args)
    local gmd = GetNPCModData()
    local id = NPCUtils.GetCharacterID(player)
    if gmd.Kills[id] then
        gmd.Kills[id] = gmd.Kills[id] + 1
    else
        gmd.Kills[id] = 1
    end
end

NPCServerRuntime.Commands[NPC_SERVER_LEGACY_COMMANDS.resetKills] = function(player, args)
    local gmd = GetNPCModData()
    local id = NPCUtils.GetCharacterID(player)
    if gmd.Kills[id] then
        gmd.Kills[id] = 0
    end
end

NPCServerRuntime.Commands.UpdateVisitedBuilding = function(player, args)
    local gmd = GetNPCModData()
    gmd.VisitedBuildings[args.bid] = args.wah 
end

-- main
local onClientCommand = function(module, command, player, args)
    local serverModule = NPCServerCommandBridge.NormalizeModule(module)
    if NPCServerRuntime[serverModule] and NPCServerRuntime[serverModule][command] then
        if type(args) ~= "table" then args = {} end
        args = bsc_sanitizeCommandArgs(args, serverModule, command)
        if not bsc_commandAllowed(serverModule, command, player, args) then return end

        local argStr = ""
        for k, v in pairs(args) do
            argStr = argStr .. " " .. k .. "=" .. tostring(v)
        end
        -- print ("received " .. module .. "." .. command .. " "  .. argStr)

        local ok, err = pcall(function()
            NPCServerRuntime[serverModule][command](player, args)
        end)
        if not ok then
            print("[NPCServerRuntime] " .. tostring(serverModule) .. "." .. tostring(command) .. " failed: " .. tostring(err))
            return
        end

        if serverModule == "Commands" then
            if not (NPCServerRuntime.NoAutoTransmitCommands and NPCServerRuntime.NoAutoTransmitCommands[command]) then
                TransmitNPCModData()
            end
        elseif serverModule == "Players" then
            TransmitNPCModDataPlayers()
        end
    end
end

function NPCClientCommandsServerBridge.DispatchClientCommand(module, command, player, args)
    return onClientCommand(module, command, player, args or {})
end


local function bsc_findSpyPlayerById(playerId)
    if not playerId then return nil end
    local target = tostring(playerId)
    local players = nil
    if getOnlinePlayers then
        local ok, value = pcall(function() return getOnlinePlayers() end)
        if ok then players = value end
    end
    if players and players.size then
        for i = 0, players:size() - 1 do
            local player = players:get(i)
            if player and tostring(bsc_playerId(player) or "") == target then return player end
        end
    end
    if getPlayer then
        local player = getPlayer()
        if player and tostring(bsc_playerId(player) or "") == target then return player end
    end
    return nil
end

local function bsc_notifySpyEvents(events)
    if type(events) ~= "table" then return end
    for _, event in ipairs(events) do
        if type(event) == "table" and event.message then
            local player = bsc_findSpyPlayerById(event.playerId)
            if player then bsc_say(player, tostring(event.message)) end
        end
    end
end

local function bsc_spyEveryTenMinutes()
    if not (NPCSpyBridge and NPCSpyBridge.UpdateSpyNetwork) then return end
    local gmd = GetNPCModData()
    NPCServerEnsureWorldTables(gmd)
    local changed, removed, events = NPCSpyBridge.UpdateSpyNetwork(gmd)
    if type(removed) == "table" then
        for _, id in ipairs(removed) do
            if NPCServerRemoveDebugMarker then
                NPCServerRemoveDebugMarker(gmd, tostring(id))
            else
                sendServerCommand('NPCDebugMap', 'Remove', {id=tostring(id)})
            end
        end
    end
    if type(changed) == "table" then
        for _, marker in ipairs(changed) do
            if marker and NPCServerSetDebugMarker then
                NPCServerSetDebugMarker(gmd, marker)
            elseif marker then
                sendServerCommand('NPCDebugMap', 'Update', marker)
            end
        end
    end
    bsc_notifySpyEvents(events)
    if (type(changed) == "table" and #changed > 0) or (type(removed) == "table" and #removed > 0) or (type(events) == "table" and #events > 0) then
        TransmitNPCModData()
    end
end

if Events and Events.EveryTenMinutes and not NPCClientCommandsServerBridge._spyTickInstalled then
    Events.EveryTenMinutes.Add(bsc_spyEveryTenMinutes)
    NPCClientCommandsServerBridge._spyTickInstalled = true
end

if Events and Events.OnClientCommand and not NPCClientCommandsServerBridge._clientCommandInstalled then
    Events.OnClientCommand.Add(onClientCommand)
    NPCClientCommandsServerBridge._clientCommandInstalled = true
end

NPCServerRuntime.EnsureWorldTables = NPCServerRuntime.EnsureWorldTables or NPCServerEnsureWorldTables
NPCServerRuntime.GetQueueKey = NPCServerRuntime.GetQueueKey or NPCServerGetQueueKey
NPCServerRuntime.SendDebugMap = NPCServerRuntime.SendDebugMap or NPCServerSendDebugMap
NPCServerRuntime.SetDebugMarker = NPCServerRuntime.SetDebugMarker or NPCServerSetDebugMarker
NPCServerRuntime.RemoveDebugMarker = NPCServerRuntime.RemoveDebugMarker or NPCServerRemoveDebugMarker
NPCServerRuntime.GetWorldGroupId = NPCServerRuntime.GetWorldGroupId or NPCServerGetWorldGroupId
NPCServerRuntime.RefreshWorldGroupMarker = NPCServerRuntime.RefreshWorldGroupMarker or NPCServerRefreshWorldGroupMarker

NPCClientCommandsServerBridge.NPCServerRuntime = NPCServerRuntime
NPCClientCommandsServerBridge[NPC_SERVER_RUNTIME_GLOBAL] = NPCServerRuntime
NPCLegacyGlobalsBridge.InstallAlias("ServerRuntime", NPCServerRuntime, "NPCServerRuntime")
