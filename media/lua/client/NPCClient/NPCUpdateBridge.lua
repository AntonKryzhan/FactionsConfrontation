NPCUpdateBridge = NPCUpdateBridge or {}

require "NPCCore/NPCLegacyContractBridge"

local Bridge = NPCUpdateBridge
local NPC_LEGACY_KEYS = NPCLegacyContractBridge.Keys
local NPC_UPDATE_LEGACY_SANDBOX = NPCLegacyContractBridge.Sandbox.main
local NPC_UPDATE_LEGACY_EXT_SANDBOX = NPCLegacyContractBridge.Sandbox.ext
local NPC_UPDATE_LEGACY_ITEMS = NPCLegacyContractBridge.Items

local function bridgeLegacySandboxValue(name, defaultValue)
    local vars = SandboxVars and SandboxVars[NPC_UPDATE_LEGACY_SANDBOX] or nil
    if vars and vars[name] ~= nil then return vars[name] end
    return defaultValue
end

local function bridgeLegacySandboxBool(name, defaultValue)
    local value = bridgeLegacySandboxValue(name, defaultValue == true)
    return value == true or value == 1 or value == "true"
end

local function bridgeLegacySandboxNumber(name, defaultValue)
    return tonumber(bridgeLegacySandboxValue(name, defaultValue)) or tonumber(defaultValue) or 0
end

local BRIDGE_TEMP = Bridge._temp or {
    combatNearby = {},
    escapeNearby = {},
    attackingZombies = {},
    fallbackCombatCandidates = {ids={}, kinds={}, d2s={}, n=0}
}
Bridge._temp = BRIDGE_TEMP

function Bridge.CalcSpottedScore(player, dist)
    if not instanceof(player, "IsoPlayer") then return nil end

    local square = player:getSquare()
    if not square then return nil end

    local spottedScore = square:getLightLevel(0)

    if player:isRunning() then spottedScore = spottedScore + 0.1 end
    if player:isSprinting() then spottedScore = spottedScore + 0.12 end

    if player:isSneaking() then
        spottedScore = spottedScore - 0.1
        local objects = square:getObjects()
        if objects then
            for i = 0, objects:size() - 1 do
                local object = objects:get(i)
                local props = object and object:getProperties()
                if props and props:Is(IsoFlagType.vegitation) and props:Is(IsoFlagType.canBeCut) then
                    spottedScore = spottedScore - 0.15
                    break
                end
            end
        end
    end

    dist = tonumber(dist) or 9999
    if dist <= 8 then
        spottedScore = spottedScore + (0.65 - (dist * 0.075))
    end

    return spottedScore
end

function Bridge.ManageSpyMarker(bandit, brain, uTick)
    if not (NPCSpyBridge and NPCSpyBridge.ShowMarkers and NPCSpyBridge.ShowMarkers()) then return end
    if not (brain and brain.spy == true and brain.spyDefected ~= true and brain.spyCompromised ~= true) then return end
    if uTick and uTick % 64 ~= 11 then return end

    local elite = brain.spyElite == true or brain.spyRank == "elite"
    local label = elite and "ELITE SPY" or "SPY"
    local r, g, b = 0.15, 0.65, 1.0
    if elite then r, g, b = 1.0, 0.85, 0.15 end

    if bandit and bandit.addLineChatElement then
        pcall(function() bandit:addLineChatElement(label, r, g, b) end)
    elseif bandit and bandit.Say then
        pcall(function() bandit:Say(label) end)
    end
end

function Bridge.DetectTarget(bandit, target, brain, kind)
    if NPCAIVisionBridge and NPCAIVisionBridge.CanDetect then
        local ok, detected, detection = pcall(function()
            return NPCAIVisionBridge.CanDetect(bandit, target, brain, kind)
        end)
        if ok and detected then return true, detection end
        return false, nil
    end

    if not (bandit and target) then return false, nil end

    local ok, canSee = pcall(function()
        return bandit:CanSee(target)
    end)
    if not ok or not canSee then return false, nil end

    local dist = NPCUtils.DistTo(bandit:getX(), bandit:getY(), target:getX(), target:getY())
    return true, {target=target, x=target:getX(), y=target:getY(), z=target:getZ(), dist=dist, kind=kind}
end

function Bridge.IsBlackMarketNoCombatBrain(brain)
    if NPCBlackMarketBridge and NPCBlackMarketBridge.IsNoCombatBrain then
        return NPCBlackMarketBridge.IsNoCombatBrain(brain)
    end
    return brain and (brain.blackMarket == true or brain.nonCombatant == true or brain.noAggro == true or brain.noZombieTarget == true)
end

function Bridge.NowMs()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then return math.floor(getGameTime():getWorldAgeHours() * 3600000) end
    return 0
end

function Bridge.GetCameraZoom()
    if getCore and getCore() and getCore().getZoom then
        local ok, zoom = pcall(function() return getCore():getZoom(0) end)
        if ok and tonumber(zoom) then return tonumber(zoom) end
    end
    return 1
end

function Bridge.GetPerfLevel()
    local level = 0
    if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.GetLoadState then
        local ok, state = pcall(function() return NPCWorkSchedulerBridge.GetLoadState(false) end)
        if ok and state then level = tonumber(state.level) or 0 end
    end
    local zoom = Bridge.GetCameraZoom()
    if zoom >= 1.45 then level = math.max(level, 1) end
    if zoom >= 1.90 then level = math.max(level, 2) end
    if zoom >= 2.35 then level = math.max(level, 3) end
    return level, zoom
end

function Bridge.UpdateUtilityAIOnce(bandit, brain, uTick)
    if not (brain and NPCUtilityAIBridge and NPCUtilityAIBridge.Update) then return end
    brain.ai = brain.ai or {}
    local tick = tonumber(uTick) or (NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.GetTick and NPCWorkSchedulerBridge.GetTick()) or 0
    if brain.ai.utilityLastUpdateTick == tick then return end
    brain.ai.utilityLastUpdateTick = tick
    pcall(function()
        NPCUtilityAIBridge.Update(bandit, brain, uTick)
    end)
end

function Bridge.ColorSignature(color)
    if type(color) ~= "table" then return "" end
    return tostring(color.r or "") .. "," .. tostring(color.g or "") .. "," .. tostring(color.b or "")
end

function Bridge.VisualSignature(brain)
    if not brain then return "nil" end
    return tostring(brain.appearanceSeed or "") .. "|" .. tostring(brain.faceProfile or "") .. "|" .. tostring(brain.skinTexture or "") .. "|" .. Bridge.ColorSignature(brain.skinColor) .. "|" .. tostring(brain.hairStyle or "") .. "|" .. Bridge.ColorSignature(brain.hairColor)
        .. "|" .. tostring(brain.beardStyle or "") .. "|" .. Bridge.ColorSignature(brain.beardColor)
end

function Bridge.IsKnownHumanSkinTextureName(name)
    name = tostring(name or "")
    return string.match(name, "^MaleBody0[1-5]$") ~= nil
        or string.match(name, "^FemaleBody0[1-5]$") ~= nil
end

function Bridge.IsBadNPCSkinTextureName(name)
    name = tostring(name or "")
    if name == "" then return true end
    local lower = string.lower(name)
    if string.find(lower, "zombie", 1, true) ~= nil
        or string.find(lower, "zed", 1, true) ~= nil
        or string.find(lower, "rot", 1, true) ~= nil
        or string.find(lower, "skeleton", 1, true) ~= nil
        or string.find(lower, "burnt", 1, true) ~= nil then
        return true
    end
    return not Bridge.IsKnownHumanSkinTextureName(name)
end

function Bridge.GetVisualSkinTexture(visuals)
    if not visuals then return nil end
    if visuals.getSkinTextureName then
        local ok, value = pcall(function() return visuals:getSkinTextureName() end)
        if ok and value then return tostring(value) end
    end
    if visuals.getSkinTexture then
        local ok, value = pcall(function() return visuals:getSkinTexture() end)
        if ok and value then return tostring(value) end
    end
    return nil
end

function Bridge.ClearHumanVisualDamage(visuals)
    if not visuals then return false end
    pcall(function() visuals:removeBlood() end)
    local maxIndex = BloodBodyPartType and BloodBodyPartType.MAX and BloodBodyPartType.MAX:index() or 0
    for i = 0, maxIndex - 1 do
        local part = BloodBodyPartType.FromIndex(i)
        pcall(function() visuals:setBlood(part, 0) end)
        pcall(function() visuals:setDirt(part, 0) end)
    end
    return true
end

function Bridge.ClearItemVisualDamage(character)
    if not character or not character.getItemVisuals then return false end
    local itemVisuals = character:getItemVisuals()
    if not itemVisuals then return false end
    local maxIndex = BloodBodyPartType and BloodBodyPartType.MAX and BloodBodyPartType.MAX:index() or 0
    for i = 0, itemVisuals:size() - 1 do
        local item = itemVisuals:get(i)
        if item then
            for j = 0, maxIndex - 1 do
                local part = BloodBodyPartType.FromIndex(j)
                pcall(function() item:removeHole(j) end)
                pcall(function() item:setBlood(part, 0) end)
                pcall(function() item:setDirt(part, 0) end)
            end
        end
    end
    return true
end

function Bridge.ApplyHumanSkinColor(visuals, skinColor)
    if not (visuals and skinColor and ImmutableColor) then return false end
    local r = tonumber(skinColor.r) or 0.86
    local g = tonumber(skinColor.g) or 0.66
    local b = tonumber(skinColor.b) or 0.52
    r = math.max(0.18, math.min(1.0, r))
    g = math.max(0.12, math.min(0.92, g))
    b = math.max(0.08, math.min(0.82, b))
    pcall(function() visuals:setSkinColor(ImmutableColor.new(r, g, b)) end)
    return true
end

function Bridge.GetFallbackHumanSkinTexture(zombie, brain)
    local id = 0
    if brain then id = tonumber(brain.id or brain.uid or brain.persistentId) or 0 end
    if id == 0 and NPCUtils and NPCUtils.GetZombieID then
        local ok, value = pcall(function() return NPCUtils.GetZombieID(zombie) end)
        if ok and value then id = tonumber(value) or id end
    end
    local female = brain and brain.female == true
    if zombie and zombie.isFemale then
        local okFemale, value = pcall(function() return zombie:isFemale() == true end)
        if okFemale then female = value == true end
    end
    id = math.abs(math.floor(tonumber(id) or 0))
    if female then
        return "FemaleBody0" .. tostring(1 + id % 5)
    end
    return "MaleBody0" .. tostring(1 + id % 5)
end

function Bridge.NormalizeNPCSkinTexture(zombie, brain)
    if type(brain) ~= "table" then return nil end
    if NPCCreatorBridge and NPCCreatorBridge.ApplyHumanFacePresetToBrain then
        pcall(function() NPCCreatorBridge.ApplyHumanFacePresetToBrain(brain, zombie, nil, false) end)
    end
    if Bridge.IsBadNPCSkinTextureName(brain.skinTexture) then
        brain.skinTexture = Bridge.GetFallbackHumanSkinTexture(zombie, brain)
    end
    return brain.skinTexture
end

function Bridge.EnsureHumanNPCVisual(zombie, brain, force)
    if not (zombie and brain) then return false end
    local md = zombie.getModData and zombie:getModData() or nil
    local now = Bridge.NowMs()

    local skinTexture = Bridge.NormalizeNPCSkinTexture(zombie, brain)
    local visuals = zombie.getHumanVisual and zombie:getHumanVisual() or nil
    local currentSkin = Bridge.GetVisualSkinTexture(visuals)
    local needsSkinFix = skinTexture ~= nil and (currentSkin == nil or currentSkin == "" or currentSkin ~= skinTexture or Bridge.IsBadNPCSkinTextureName(currentSkin))
    local needsCleanup = force == true or needsSkinFix

    if not needsCleanup and not force and md and md.NPC_HUMAN_VISUAL_AT and now - md.NPC_HUMAN_VISUAL_AT < 10000 then return false end

    pcall(function() zombie:setNoTeeth(false) end)
    pcall(function() zombie:setVariable("ZombieBiteDone", false) end)
    pcall(function() zombie:setVariable(NPC_LEGACY_KEYS.FORMER_ZOMBIE, false) end)

    if visuals then
        if skinTexture then pcall(function() visuals:setSkinTextureName(skinTexture) end) end
        Bridge.ApplyHumanSkinColor(visuals, brain.skinColor)
        Bridge.ClearHumanVisualDamage(visuals)
    end
    Bridge.ClearItemVisualDamage(zombie)

    if md then md.NPC_HUMAN_VISUAL_AT = now end
    if force or needsSkinFix then
        pcall(function() zombie:resetModelNextFrame() end)
        pcall(function() zombie:resetModel() end)
    end
    return true
end

function Bridge.GetCombatCandidateLimit()
    local level, zoom = Bridge.GetPerfLevel()
    local limit = 10
    if level >= 3 then
        limit = 3
    elseif level >= 2 then
        limit = 5
    elseif level >= 1 then
        limit = 7
    end
    if zoom >= 2.35 then
        limit = math.min(limit, 3)
    elseif zoom >= 1.90 then
        limit = math.min(limit, 4)
    elseif zoom >= 1.45 then
        limit = math.min(limit, 6)
    end
    return limit
end

function Bridge.ClearArray(tbl, count)
    if not tbl then return end
    local n = tonumber(count) or #tbl
    for i = 1, n do
        tbl[i] = nil
    end
end

function Bridge.GetTempArray(name)
    local tbl = BRIDGE_TEMP[name]
    if not tbl then
        tbl = {}
        BRIDGE_TEMP[name] = tbl
    end
    Bridge.ClearArray(tbl, #tbl)
    return tbl
end

function Bridge.GetCombatCandidateBuffer(brain)
    local buf
    if brain then
        brain.ai = brain.ai or {}
        buf = brain.ai.combatCandidateBuffer
        if not buf then
            buf = {ids={}, kinds={}, d2s={}, n=0}
            brain.ai.combatCandidateBuffer = buf
        end
    else
        buf = BRIDGE_TEMP.fallbackCombatCandidates
    end

    local n = tonumber(buf.n) or 0
    for i = 1, n do
        buf.ids[i] = nil
        buf.kinds[i] = nil
        buf.d2s[i] = nil
    end
    buf.n = 0
    return buf
end

function Bridge.GetNearbyAllInto(bufferName, x, y, z, radius)
    if NPCSpatialIndexBridge and NPCSpatialIndexBridge.GetNearbyAllInto then
        return NPCSpatialIndexBridge.GetNearbyAllInto(Bridge.GetTempArray(bufferName), x, y, z, radius)
    end
    if NPCSpatialIndexBridge and NPCSpatialIndexBridge.GetNearbyAll then
        local list = NPCSpatialIndexBridge.GetNearbyAll(x, y, z, radius)
        return list, list and #list or 0
    end
    return nil, 0
end

function Bridge.GetNearbyZombiesInto(bufferName, x, y, z, radius)
    if NPCSpatialIndexBridge and NPCSpatialIndexBridge.GetNearbyZombiesInto then
        return NPCSpatialIndexBridge.GetNearbyZombiesInto(Bridge.GetTempArray(bufferName), x, y, z, radius)
    end
    if NPCSpatialIndexBridge and NPCSpatialIndexBridge.GetNearbyZombies then
        local list = NPCSpatialIndexBridge.GetNearbyZombies(x, y, z, radius)
        return list, list and #list or 0
    end
    return nil, 0
end

function Bridge.GetQueueBrain(gmd, id)
    if not (gmd and gmd.Queue and id ~= nil) then return nil end
    local brain = gmd.Queue[id]
    if brain then return brain end
    brain = gmd.Queue[tostring(id)]
    if brain then return brain end
    local nid = tonumber(id)
    if nid then return gmd.Queue[nid] end
    return nil
end

function Bridge.IsClientNPCSyncReady()
    if NPCGMD and NPCGMD.IsClientSafeSyncReady then
        return NPCGMD.IsClientSafeSyncReady()
    end
    return true
end

function Bridge.WriteNPCServiceIds(zombie, brain)
    if not (zombie and brain) then return end

    local runtimeId = brain.id
    local persistentId = brain.persistentId or brain.uid
    local worldGroupId = brain.worldGroupId or brain.groupId
    local programName = brain.program and brain.program.name or brain.programName
    local md = zombie:getModData()

    if md then
        md[NPC_LEGACY_KEYS.IS_FLAG] = true
        md[NPC_LEGACY_KEYS.FORMER_ZOMBIE] = false
        if runtimeId ~= nil then md[NPC_LEGACY_KEYS.RUNTIME_ID] = tostring(runtimeId) end
        if persistentId ~= nil then md[NPC_LEGACY_KEYS.PERSISTENT_ID] = tostring(persistentId) end
        if worldGroupId ~= nil then md[NPC_LEGACY_KEYS.WORLD_GROUP_ID] = tostring(worldGroupId) end
        if programName ~= nil then md[NPC_LEGACY_KEYS.PROGRAM] = tostring(programName) end
    end

    if brain.blackMarket == true or brain.blackMarketNPC == true then
        if md then
            md.NPCBlackMarketBridge = true
            md.BlackMarketNPC = true
            md.BlackMarketId = tostring(brain.blackMarketId or persistentId or runtimeId or "")
            md.BlackMarketRuntimeId = runtimeId and tostring(runtimeId) or nil
        end
        pcall(function() zombie:setVariable(NPC_LEGACY_KEYS.BLACK_MARKET, true) end)
        pcall(function() zombie:setVariable("BlackMarketId", tostring(brain.blackMarketId or persistentId or runtimeId or "")) end)
    end

    if runtimeId ~= nil then pcall(function() zombie:setVariable(NPC_LEGACY_KEYS.RUNTIME_ID, tostring(runtimeId)) end) end
    if persistentId ~= nil then pcall(function() zombie:setVariable(NPC_LEGACY_KEYS.PERSISTENT_ID, tostring(persistentId)) end) end
    if worldGroupId ~= nil then pcall(function() zombie:setVariable(NPC_LEGACY_KEYS.WORLD_GROUP_ID, tostring(worldGroupId)) end) end
    if programName ~= nil then pcall(function() zombie:setVariable(NPC_LEGACY_KEYS.PROGRAM, tostring(programName)) end) end
end

function Bridge.NonEmpty(value)
    if value == nil then return nil end
    local text = tostring(value)
    if text == "" or text == "nil" or text == "false" then return nil end
    return text
end

function Bridge.GetZombieServiceId(zombie, mdKey, variableName)
    if not zombie then return nil end

    local md = zombie:getModData()
    local value = md and md[mdKey] or nil
    value = Bridge.NonEmpty(value)
    if value then return value end

    local ok, var = pcall(function() return zombie:getVariableString(variableName) end)
    if ok then return Bridge.NonEmpty(var) end

    return nil
end

function Bridge.CopyRuntimeData(value, depth)
    depth = depth or 0
    if depth > 8 then return nil end
    if type(value) ~= "table" then return value end

    local out = {}
    for k, v in pairs(value) do
        local tk, tv = type(k), type(v)
        if (tk == "string" or tk == "number" or tk == "boolean") and tv ~= "function" and tv ~= "userdata" and tv ~= "thread" then
            if tv == "table" then
                out[k] = Bridge.CopyRuntimeData(v, depth + 1)
            else
                out[k] = v
            end
        end
    end
    return out
end

function Bridge.HasPersistentNPCStamp(zombie, brain)
    if brain and (brain.persistentId or brain.uid or brain.worldGroupId or brain.groupId or brain.worldDirector) then return true end
    if not zombie then return false end

    local md = zombie:getModData()
    if md and (md[NPC_LEGACY_KEYS.IS_FLAG] == true or md[NPC_LEGACY_KEYS.PERSISTENT_ID] ~= nil or md[NPC_LEGACY_KEYS.WORLD_GROUP_ID] ~= nil) then return true end
    if Bridge.GetZombieServiceId(zombie, NPC_LEGACY_KEYS.PERSISTENT_ID, NPC_LEGACY_KEYS.PERSISTENT_ID) then return true end
    if Bridge.GetZombieServiceId(zombie, NPC_LEGACY_KEYS.WORLD_GROUP_ID, NPC_LEGACY_KEYS.WORLD_GROUP_ID) then return true end
    return false
end

function Bridge.FindPersistentProfile(gmd, persistentId)
    if not (gmd and persistentId) then return nil end
    local key = tostring(persistentId)
    if type(gmd.PersistentNPCs) == "table" and type(gmd.PersistentNPCs[key]) == "table" then return gmd.PersistentNPCs[key] end
    if type(gmd.Registry) == "table" and type(gmd.Registry[key]) == "table" then return gmd.Registry[key] end
    return nil
end

function Bridge.FindVirtualGroupMember(gmd, groupId, persistentId)
    if not (gmd and gmd.VirtualGroups and groupId) then return nil, nil end
    local group = gmd.VirtualGroups[tostring(groupId)] or gmd.VirtualGroups[groupId]
    if type(group) ~= "table" then return nil, nil end
    if not persistentId then return nil, group end

    local pid = tostring(persistentId)
    for _, member in ipairs(group.members or {}) do
        if type(member) == "table" and tostring(member.uid or member.persistentId or "") == pid then
            return member, group
        end
    end
    return nil, group
end

function Bridge.RebuildPersistentBrain(zombie, gmd, id, brain)
    brain = type(brain) == "table" and Bridge.CopyRuntimeData(brain) or nil

    local persistentId = Bridge.GetZombieServiceId(zombie, NPC_LEGACY_KEYS.PERSISTENT_ID, NPC_LEGACY_KEYS.PERSISTENT_ID)
    local groupId = Bridge.GetZombieServiceId(zombie, NPC_LEGACY_KEYS.WORLD_GROUP_ID, NPC_LEGACY_KEYS.WORLD_GROUP_ID)
    local profile = Bridge.FindPersistentProfile(gmd, persistentId)
    local member, group = Bridge.FindVirtualGroupMember(gmd, groupId, persistentId)

    if type(profile) == "table" and profile.dead == true then return nil end

    if not brain then
        brain = Bridge.CopyRuntimeData(profile or member or {}) or {}
    else
        local source = profile or member
        if type(source) == "table" then
            local copy = Bridge.CopyRuntimeData(source)
            for k, v in pairs(copy or {}) do
                if brain[k] == nil then brain[k] = v end
            end
        end
    end

    if next(brain) == nil then return nil end

    brain.id = id or brain.id
    brain.runtimeId = id or brain.runtimeId
    brain.uid = brain.uid or persistentId
    brain.persistentId = brain.persistentId or persistentId or brain.uid
    brain.worldGroupId = brain.worldGroupId or brain.groupId or groupId
    brain.groupId = brain.groupId or brain.worldGroupId or groupId
    brain.fullname = brain.fullname or brain.name or (profile and (profile.name or profile.fullname))
    brain.name = brain.fullname or brain.name
    brain.program = brain.program or (group and group.program) or {name="Looter", stage="Prepare"}
    brain.tasks = type(brain.tasks) == "table" and brain.tasks or {}
    brain.weapons = type(brain.weapons) == "table" and brain.weapons or {melee=false, primary={name=false, magSize=0, bulletsLeft=0, magCount=0}, secondary={name=false, magSize=0, bulletsLeft=0, magCount=0}}
    brain.clan = brain.clan or brain.faction or (group and (group.clanId or group.faction))
    brain.factionSide = brain.factionSide or brain.faction or brain.side or brain.patrolColor or (group and (group.factionSide or group.faction or group.side or group.patrolColor))
    brain.faction = brain.faction or brain.factionSide
    brain.side = brain.side or brain.factionSide
    brain.patrolColor = brain.patrolColor or brain.factionSide
    if NPCFactionBridge and NPCFactionBridge.EnsureBrainSide then
        pcall(function() NPCFactionBridge.EnsureBrainSide(brain) end)
    end
    if brain.hostile == nil then
        if NPCFactionBridge and NPCFactionBridge.GetBrainSide then
            local side = NPCFactionBridge.GetBrainSide(brain)
            brain.hostile = (side == "red" or side == "black")
        else
            brain.hostile = false
        end
    end
    brain.restoredFromPersistent = true
    return brain
end

function Bridge.TryRecoverPersistentNPC(zombie, gmd, id, brain)
    if not zombie then return brain, false, false end
    if Bridge.IsFormerNPCZombie(zombie) then return brain, false, false end
    local alive = true
    if zombie.isAlive then
        local okAlive, value = pcall(function() return zombie:isAlive() end)
        alive = (not okAlive) or value == true
    end
    if not alive then return brain, false, false end
    if zombie:getVariableBoolean(NPC_LEGACY_KEYS.FLAG) then return brain, true, true end
    if not Bridge.HasPersistentNPCStamp(zombie, brain) then return brain, false, false end

    local queuedBrain = Bridge.GetQueueBrain(gmd, id)
    if queuedBrain then
        Bridge.MarkAsNPC(zombie, queuedBrain)
        return queuedBrain, true, true
    end

    if Bridge.RuntimeKnownPhysical(gmd, id) then
        local rebuilt = Bridge.RebuildPersistentBrain(zombie, gmd, id, brain)
        if rebuilt then
            Bridge.MarkAsNPC(zombie, rebuilt)
            return rebuilt, true, true
        end
    end

    if not Bridge.IsClientNPCSyncReady() then
        return brain, true, false
    end

    return brain, false, false
end

function Bridge.GetBlackMarketContactId(zombie)
    if not zombie then return nil end
    local md = zombie:getModData()
    if md then
        local id = Bridge.NonEmpty(md.BlackMarketId or md.blackMarketId)
        if id then return id end
        if md.NPCBlackMarketBridge == true or md.BlackMarketNPC == true then
            local runtime = Bridge.NonEmpty(md.BlackMarketRuntimeId or md[NPC_LEGACY_KEYS.RUNTIME_ID])
            if runtime then return runtime end
        end
    end
    local okId, id = pcall(function() return zombie:getVariableString("BlackMarketId") end)
    if okId then
        id = Bridge.NonEmpty(id)
        if id then return id end
    end
    local okFlag, flag = pcall(function() return zombie:getVariableBoolean(NPC_LEGACY_KEYS.BLACK_MARKET) end)
    if okFlag and flag == true then
        return Bridge.GetZombieServiceId(zombie, NPC_LEGACY_KEYS.RUNTIME_ID, NPC_LEGACY_KEYS.RUNTIME_ID)
    end
    return nil
end

function Bridge.BlackMarketFallbackBrain(zombie, runtimeId)
    local contactId = Bridge.GetBlackMarketContactId(zombie)
    if not contactId then return nil end
    runtimeId = runtimeId or (NPCUtils and NPCUtils.GetZombieID and NPCUtils.GetZombieID(zombie))
    local x, y, z = zombie:getX(), zombie:getY(), zombie:getZ()
    return {
        id = runtimeId,
        uid = "black_market:" .. tostring(contactId),
        persistentId = "black_market:" .. tostring(contactId),
        blackMarket = true,
        blackMarketNPC = true,
        blackMarketId = tostring(contactId),
        special = "BlackMarket",
        nonCombatant = true,
        noAggro = true,
        noZombieTarget = true,
        immortal = true,
        noLoot = true,
        permanent = true,
        clan = 0,
        hostile = false,
        factionSide = (NPCBlackMarketBridge and NPCBlackMarketBridge.ServiceSide and NPCBlackMarketBridge.ServiceSide()) or "black_market",
        faction = (NPCBlackMarketBridge and NPCBlackMarketBridge.ServiceSide and NPCBlackMarketBridge.ServiceSide()) or "black_market",
        side = (NPCBlackMarketBridge and NPCBlackMarketBridge.ServiceSide and NPCBlackMarketBridge.ServiceSide()) or "black_market",
        patrolColor = (NPCBlackMarketBridge and NPCBlackMarketBridge.ServiceSide and NPCBlackMarketBridge.ServiceSide()) or "black_market",
        factionState = (NPCBlackMarketBridge and NPCBlackMarketBridge.ServiceState and NPCBlackMarketBridge.ServiceState()) or "black_market_service",
        factionShoot = false,
        mercenary = false,
        mercenaryElite = false,
        relationshipToPlayer = "black_market",
        role = "black_market",
        tacticalRole = "trader",
        health = 12.0,
        maxHealth = 12.0,
        bornCoords = {x=x, y=y, z=z},
        blackMarketX = x,
        blackMarketY = y,
        blackMarketZ = z,
        blackMarketCityX = x,
        blackMarketCityY = y,
        blackMarketCityRadius = (NPCBlackMarketBridge and NPCBlackMarketBridge.NPCCityRadius and NPCBlackMarketBridge.NPCCityRadius()) or 140,
        program = {name="BlackMarket", stage="Prepare"},
        tasks = {},
        weapons = {melee=false, primary={name=false, magSize=0, bulletsLeft=0, magCount=0}, secondary={name=false, magSize=0, bulletsLeft=0, magCount=0}},
        loot = {},
        inventory = {},
        currentWeapon = nil,
        ammo = nil
    }
end

function Bridge.IsFormerNPCZombie(zombie)
    if not zombie then return false end

    local md = zombie:getModData()
    if md and md[NPC_LEGACY_KEYS.FORMER_ZOMBIE] then return true end

    local ok, var = pcall(function() return zombie:getVariableBoolean(NPC_LEGACY_KEYS.FORMER_ZOMBIE) end)
    return ok and var == true
end

function Bridge.IsWorldPersistentNPC(zombie, brain)
    if brain and (brain.persistentId or brain.uid or brain.worldGroupId or brain.groupId or brain.worldDirector) then return true end
    if not zombie then return false end

    if Bridge.GetZombieServiceId(zombie, NPC_LEGACY_KEYS.PERSISTENT_ID, NPC_LEGACY_KEYS.PERSISTENT_ID) then return true end
    if Bridge.GetZombieServiceId(zombie, NPC_LEGACY_KEYS.WORLD_GROUP_ID, NPC_LEGACY_KEYS.WORLD_GROUP_ID) then return true end

    return false
end

function Bridge.RuntimeKnownPhysical(gmd, id)
    if not (gmd and id ~= nil) then return false end

    local sid = tostring(id)
    if gmd.DebugMapMarkers then
        local marker = gmd.DebugMapMarkers["npc:" .. sid] or gmd.DebugMapMarkers[sid]
        if type(marker) == "table" and tostring(marker.markerType or "") == "npc" then return true end
    end

    if type(gmd.VirtualGroups) == "table" then
        for _, group in pairs(gmd.VirtualGroups) do
            if type(group) == "table" and type(group.physicalIds) == "table" then
                for _, runtimeId in pairs(group.physicalIds) do
                    if tostring(runtimeId) == sid then return true end
                end
            end
        end
    end

    return false
end

function Bridge.RemoveNPCRuntimeObject(zombie, reason)
    if not zombie then return false end

    local md = zombie:getModData()
    if md then
        md[NPC_LEGACY_KEYS.RUNTIME_REMOVED] = true
        md[NPC_LEGACY_KEYS.RUNTIME_REMOVE_REASON] = tostring(reason or "orphan_runtime_cleanup")
        md[NPC_LEGACY_KEYS.RUNTIME_REMOVED_AT] = Bridge.NowMs()
        md[NPC_LEGACY_KEYS.IS_FLAG] = false
        md[NPC_LEGACY_KEYS.FORMER_ZOMBIE] = false
    end

    if NPCBrainData and NPCBrainData.Remove then
        pcall(function() NPCBrainData.Remove(zombie) end)
    end

    pcall(function() zombie:setUseless(false) end)
    pcall(function() zombie:setReanim(false) end)
    pcall(function() zombie:setVariable(NPC_LEGACY_KEYS.FLAG, false) end)
    pcall(function() zombie:setVariable(NPC_LEGACY_KEYS.FORMER_ZOMBIE, false) end)
    pcall(function() zombie:setVariable(NPC_LEGACY_KEYS.PRIMARY, "") end)
    pcall(function() zombie:setVariable(NPC_LEGACY_KEYS.SECONDARY, "") end)
    pcall(function() zombie:setVariable(NPC_LEGACY_KEYS.WALK_TYPE, "") end)
    pcall(function() NPCCompatibilityBridge.SafeSetPrimaryHandItem(zombie, nil) end)
    pcall(function() NPCCompatibilityBridge.SafeSetSecondaryHandItem(zombie, nil) end)
    pcall(function() zombie:clearAttachedItems() end)
    pcall(function() zombie:resetEquippedHandsModels() end)

    local isDead = false
    local okDead, deadValue = pcall(function() return zombie:isDead() end)
    if okDead and deadValue == true then isDead = true end
    local okAlive, aliveValue = pcall(function() return zombie:isAlive() end)
    if okAlive and aliveValue == false then isDead = true end

    if not isDead then
        pcall(function() zombie:removeFromWorld() end)
        pcall(function() zombie:removeFromSquare() end)
    elseif md then
        md[NPC_LEGACY_KEYS.FORMER_ZOMBIE] = true
        md[NPC_LEGACY_KEYS.FORMER_ZOMBIE_AT] = getGameTime and getGameTime():getWorldAgeHours() or 0
    end

    return true
end

function Bridge.MarkAsNPC(zombie, brain)
    if not (zombie and brain) then return false end

    if NPCBrainData and NPCBrainData.Update then
        NPCBrainData.Update(zombie, brain)
    end

    pcall(function() zombie:setNoTeeth(false) end)
    pcall(function() zombie:setVariable(NPC_LEGACY_KEYS.FLAG, true) end)
    pcall(function() zombie:setVariable(NPC_LEGACY_KEYS.FORMER_ZOMBIE, false) end)

    local zmd = zombie.getModData and zombie:getModData() or nil
    if zmd then zmd[NPC_LEGACY_KEYS.FORMER_ZOMBIE] = false end

    Bridge.WriteNPCServiceIds(zombie, brain)

    pcall(function() zombie:setVariable(NPC_LEGACY_KEYS.PRIMARY, "") end)
    pcall(function() zombie:setVariable(NPC_LEGACY_KEYS.SECONDARY, "") end)
    pcall(function() zombie:setWalkType("Walk") end)
    pcall(function() zombie:setVariable(NPC_LEGACY_KEYS.WALK_TYPE, "Walk") end)
    pcall(function() zombie:setVariable("ZombieHitReaction", "Chainsaw") end)

    local emitter = zombie.getEmitter and zombie:getEmitter() or nil
    if emitter and emitter.stopAll then pcall(function() emitter:stopAll() end) end

    if NPCCompatibilityBridge then
        if NPCCompatibilityBridge.SafeSetPrimaryHandItem then pcall(function() NPCCompatibilityBridge.SafeSetPrimaryHandItem(zombie, nil) end) end
        if NPCCompatibilityBridge.SafeSetSecondaryHandItem then pcall(function() NPCCompatibilityBridge.SafeSetSecondaryHandItem(zombie, nil) end) end
    end
    pcall(function() zombie:resetEquippedHandsModels() end)
    pcall(function() zombie:clearAttachedItems() end)
    pcall(function() zombie:setTurnAlertedValues(-5, 5) end)

    if NPCHealthRegenBridge and NPCHealthRegenBridge.ApplySpawnHealth then
        NPCHealthRegenBridge.ApplySpawnHealth(zombie, brain)
    elseif brain.health then
        pcall(function() zombie:setHealth(brain.health) end)
    end

    Bridge.EnsureHumanNPCVisual(zombie, brain, true)
    return true
end

function Bridge.IsBlackMarketNPC(bandit)
    if not bandit then return false end

    local brain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(bandit) or nil
    if NPCBlackMarketBridge and NPCBlackMarketBridge.IsNPCBrain and NPCBlackMarketBridge.IsNPCBrain(brain) then return true end
    if brain and (brain.blackMarket == true or brain.blackMarketNPC == true or brain.special == "BlackMarket") then return true end

    local md = bandit.getModData and bandit:getModData() or nil
    if md and (md.NPCBlackMarketBridge == true or md.BlackMarketNPC == true or md.BlackMarketId ~= nil) then return true end

    if bandit.getVariableBoolean then
        local ok, value = pcall(function() return bandit:getVariableBoolean(NPC_LEGACY_KEYS.BLACK_MARKET) end)
        if ok and value == true then return true end
    end

    return false
end

function Bridge.Zombify(bandit)
    if not bandit then return false end

    local oldBrain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(bandit) or nil
    if Bridge.IsBlackMarketNPC(bandit) then
        Bridge.RemoveNPCRuntimeObject(bandit, "blocked_black_market_zombify")
        return false
    end
    if Bridge.IsWorldPersistentNPC(bandit, oldBrain) then
        Bridge.RemoveNPCRuntimeObject(bandit, "blocked_persistent_zombify")
        return false
    end

    local md = bandit.getModData and bandit:getModData() or nil
    if md then
        md[NPC_LEGACY_KEYS.IS_FLAG] = true
        md[NPC_LEGACY_KEYS.FORMER_ZOMBIE] = true
        md[NPC_LEGACY_KEYS.FORMER_ZOMBIE_AT] = getGameTime and getGameTime():getWorldAgeHours() or 0
        md[NPC_LEGACY_KEYS.FORMER_ZOMBIE_SIDE] = oldBrain and (oldBrain.factionSide or oldBrain.faction or oldBrain.side or oldBrain.patrolColor) or nil
        if oldBrain then
            if oldBrain.id ~= nil then md[NPC_LEGACY_KEYS.RUNTIME_ID] = tostring(oldBrain.id) end
            if oldBrain.persistentId or oldBrain.uid then md[NPC_LEGACY_KEYS.PERSISTENT_ID] = tostring(oldBrain.persistentId or oldBrain.uid) end
            if oldBrain.worldGroupId or oldBrain.groupId then md[NPC_LEGACY_KEYS.WORLD_GROUP_ID] = tostring(oldBrain.worldGroupId or oldBrain.groupId) end
            if oldBrain.program and oldBrain.program.name then md[NPC_LEGACY_KEYS.PROGRAM] = tostring(oldBrain.program.name) end
        end
    end

    pcall(function() bandit:setNoTeeth(false) end)
    pcall(function() bandit:setUseless(false) end)
    pcall(function() bandit:setVariable(NPC_LEGACY_KEYS.FLAG, false) end)
    pcall(function() bandit:setVariable(NPC_LEGACY_KEYS.FORMER_ZOMBIE, true) end)
    pcall(function() bandit:setVariable(NPC_LEGACY_KEYS.PRIMARY, "") end)
    pcall(function() bandit:setVariable(NPC_LEGACY_KEYS.SECONDARY, "") end)
    pcall(function() bandit:setWalkType("2") end)
    pcall(function() bandit:setVariable(NPC_LEGACY_KEYS.WALK_TYPE, "") end)
    pcall(function() bandit:setVariable("ZombieHitReaction", "") end)

    if NPCCompatibilityBridge then
        if NPCCompatibilityBridge.SafeSetPrimaryHandItem then pcall(function() NPCCompatibilityBridge.SafeSetPrimaryHandItem(bandit, nil) end) end
        if NPCCompatibilityBridge.SafeSetSecondaryHandItem then pcall(function() NPCCompatibilityBridge.SafeSetSecondaryHandItem(bandit, nil) end) end
    end
    pcall(function() bandit:resetEquippedHandsModels() end)
    pcall(function() bandit:clearAttachedItems() end)

    local okHealth, health = pcall(function() return bandit:getHealth() end)
    health = okHealth and tonumber(health) or nil
    if health and health > 1.0 then pcall(function() bandit:setHealth(1.0) end) end

    if NPCBrainData and NPCBrainData.Remove then NPCBrainData.Remove(bandit) end
    return true
end

function Bridge.ApplyVisuals(bandit, brain)
    if not (bandit and brain and bandit.getHumanVisual) then return false end

    Bridge.EnsureHumanNPCVisual(bandit, brain, false)
    local banditVisuals = bandit:getHumanVisual()
    if not banditVisuals then return false end

    Bridge.NormalizeNPCSkinTexture(bandit, brain)
    local visualSig = Bridge.VisualSignature(brain)
    local md = bandit.getModData and bandit:getModData() or nil
    local currentSkin = Bridge.GetVisualSkinTexture(banditVisuals)
    local skinMismatch = brain.skinTexture ~= nil and (currentSkin == nil or currentSkin == "" or currentSkin ~= brain.skinTexture or Bridge.IsBadNPCSkinTextureName(currentSkin))
    if md and md[NPC_LEGACY_KEYS.VISUAL_SIG] == visualSig and not skinMismatch then return false end

    local now = Bridge.NowMs()
    if md and md[NPC_LEGACY_KEYS.VISUAL_AT] and now - md[NPC_LEGACY_KEYS.VISUAL_AT] < 5000 then return false end

    if brain.skinTexture then pcall(function() banditVisuals:setSkinTextureName(brain.skinTexture) end) end
    Bridge.ApplyHumanSkinColor(banditVisuals, brain.skinColor)
    if brain.hairStyle then pcall(function() banditVisuals:setHairModel(brain.hairStyle) end) end
    if brain.hairColor and ImmutableColor then pcall(function() banditVisuals:setHairColor(ImmutableColor.new(brain.hairColor.r, brain.hairColor.g, brain.hairColor.b)) end) end
    if brain.beardStyle ~= nil then pcall(function() banditVisuals:setBeardModel(brain.beardStyle) end) end
    if brain.beardColor and ImmutableColor then pcall(function() banditVisuals:setBeardColor(ImmutableColor.new(brain.beardColor.r, brain.beardColor.g, brain.beardColor.b)) end) end

    Bridge.ClearHumanVisualDamage(banditVisuals)

    local maxIndex = BloodBodyPartType and BloodBodyPartType.MAX and BloodBodyPartType.MAX:index() or 0
    local itemVisuals = bandit.getItemVisuals and bandit:getItemVisuals() or nil
    if itemVisuals then
        for i = 0, itemVisuals:size() - 1 do
            local item = itemVisuals:get(i)
            if item then
                for j = 0, maxIndex - 1 do
                    local part = BloodBodyPartType.FromIndex(j)
                    pcall(function() item:removeHole(j) end)
                    pcall(function() item:setBlood(part, 0) end)
                    pcall(function() item:setDirt(part, 0) end)
                end
                pcall(function() item:setInventoryItem(nil) end)
            end
        end
    end

    local bodyVisuals = banditVisuals.getBodyVisuals and banditVisuals:getBodyVisuals() or nil
    if bodyVisuals then
        local toRemove, toRemoveCount = {}, 0
        for i = 0, bodyVisuals:size() - 1 do
            local item = bodyVisuals:get(i)
            if item and NPCUtils and NPCUtils.ItemVisuals and NPCUtils.ItemVisuals[item:getItemType()] then
                toRemoveCount = toRemoveCount + 1
                toRemove[toRemoveCount] = item:getItemType()
            end
        end
        for i = 1, toRemoveCount do
            pcall(function() banditVisuals:removeBodyVisualFromItemType(toRemove[i]) end)
        end
    end

    pcall(function() bandit:resetModelNextFrame() end)
    pcall(function() bandit:resetModel() end)

    if md then
        md[NPC_LEGACY_KEYS.VISUAL_SIG] = visualSig
        md[NPC_LEGACY_KEYS.VISUAL_AT] = now
    end
    return true
end

function Bridge.ManageTorch(bandit)
    if not bandit then return false end
    if NPCCompatibilityBridge and NPCCompatibilityBridge.GetGameVersion and NPCCompatibilityBridge.GetGameVersion() >= 42 then return false end
    if not bridgeLegacySandboxBool("General_CarryTorches", true) then return false end
    if NPCRenderReliefBridge and NPCRenderReliefBridge.ShouldSkipTorch and NPCRenderReliefBridge.ShouldSkipTorch(bandit) then return false end
    if not bandit.getVariableBoolean then return false end

    local okTorch, hasTorch = pcall(function() return bandit:getVariableBoolean(NPC_LEGACY_KEYS.TORCH) end)
    if not okTorch or not hasTorch then return false end
    if bandit.getVehicle and bandit:getVehicle() then return false end

    local brain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(bandit) or nil
    local level, zoom = Bridge.GetPerfLevel()
    local interval = 300
    if level >= 3 or zoom >= 2.60 then
        interval = 1800
    elseif level >= 2 or zoom >= 2.15 then
        interval = 1200
    elseif level >= 1 or zoom >= 1.65 then
        interval = 750
    end
    if brain then
        brain.ai = brain.ai or {}
        local now = Bridge.NowMs()
        if brain.ai.torchLastAt and now - brain.ai.torchLastAt < interval then return false end
        brain.ai.torchLastAt = now
    end

    local cell = getCell and getCell() or nil
    if not cell then return false end

    local zx, zy, zz = bandit:getX(), bandit:getY(), bandit:getZ()
    if bandit.isProne and bandit:isProne() then
        cell:addLamppost(IsoLightSource.new(zx, zy, zz, 0.8, 0.8, 0.8, 2, 20))
    else
        local theta = (bandit.getDirectionAngle and bandit:getDirectionAngle() or 0) * 0.0174533
        local steps = 8
        if level >= 2 then
            steps = 4
        elseif level >= 1 then
            steps = 6
        end
        for i = 0, steps do
            local fadeFactor = i * 0.075
            local lx = zx + math.floor(i * math.cos(theta) + 0.5)
            local ly = zy + math.floor(i * math.sin(theta) + 0.5)
            local light = 0.8 - fadeFactor
            cell:addLamppost(IsoLightSource.new(lx, ly, zz, light, light, light, i * 0.5, 20))
        end
    end
    return true
end

function Bridge.ManageChainsaw(bandit)
    if not (bandit and bandit.isPrimaryEquipped) then return false end
    if not bandit:isPrimaryEquipped("AuthenticZClothing.Chainsaw") then return false end
    local emitter = bandit.getEmitter and bandit:getEmitter() or nil
    if emitter and emitter.isPlaying and not emitter:isPlaying("ChainsawIdle") and bandit.playSound then
        bandit:playSound("ChainsawIdle")
        return true
    end
    return false
end

function Bridge.ManageOnFire(bandit)
    if not bandit then return false end
    if bandit.isOnFire and bandit:isOnFire() then
        if NPCEntity and NPCEntity.HasTaskType and not NPCEntity.HasTaskType(bandit, "Die") then
            NPCEntity.ClearTasks(bandit)
            NPCEntity.AddTask(bandit, {action="Die", lock=true, anim="Die", fire=true, time=250})
        end
        return true
    end

    if NPCEntity and NPCEntity.HasActionTask and NPCEntity.HasActionTask(bandit) then return false end

    local cell = bandit.getCell and bandit:getCell() or nil
    if not cell then return false end
    local bx, by, bz = bandit:getX(), bandit:getY(), bandit:getZ()

    for x = -2, 2 do
        for y = -2, 2 do
            local testSquare = cell:getGridSquare(bx + x, by + y, bz)
            if testSquare and testSquare.haveFire and testSquare:haveFire() then
                if NPCEntity then
                    NPCEntity.ClearTasks(bandit)
                    NPCEntity.AddTask(bandit, {action="Time", anim="Cough", time=200})
                end
                return true
            end
        end
    end
    return false
end

function Bridge.ManageSpeechCooldown(brain)
    if brain and brain.speech and brain.speech > 0 then
        brain.speech = brain.speech - 0.01
        if brain.speech < 0 then brain.speech = 0 end
    end
end

function Bridge.ManageSoundCooldown(brain)
    if brain and brain.sound and brain.sound > 0 then
        brain.sound = brain.sound - 0.001
        if brain.sound < 0 then brain.sound = 0 end
    end
end

function Bridge.KeepBlackMarketStanding(bandit)
    if not bandit then return true end

    local brain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(bandit) or nil
    if brain then
        brain.stationary = false
        brain.sleeping = false
        brain.aiming = false
        brain.moving = false
        brain.hostile = false
        brain.nonCombatant = true
        brain.noAggro = true
        brain.noZombieTarget = true
        brain.immortal = true
    end

    if bandit.setTarget then pcall(function() bandit:setTarget(nil) end) end
    if bandit.setAttackedBy then pcall(function() bandit:setAttackedBy(nil) end) end
    if bandit.clearAggroList then pcall(function() bandit:clearAggroList() end) end
    if bandit.setVariable then
        pcall(function() bandit:setVariable(NPC_LEGACY_KEYS.BLACK_MARKET, true) end)
        pcall(function() bandit:setVariable(NPC_LEGACY_KEYS.WALK_TYPE, "Walk") end)
    end

    local asn = bandit.getActionStateName and bandit:getActionStateName() or nil
    if asn == "onground" or asn == "lunge" or asn == "getup" or asn == "getup-fromonback" or asn == "getup-fromonfront" or asn == "getup-fromsitting" then
        if bandit.changeState and ZombieIdleState and ZombieIdleState.instance then
            pcall(function() bandit:changeState(ZombieIdleState.instance()) end)
        end
    end
    return true
end

function Bridge.ManageActionState(bandit)
    if not bandit then return false end
    if Bridge.IsBlackMarketNPC(bandit) then return Bridge.KeepBlackMarketStanding(bandit) end

    local asn = bandit.getActionStateName and bandit:getActionStateName() or nil
    if asn == "onground" then
        if not (bandit.getVehicle and bandit:getVehicle()) then
            if bandit.isUnderVehicle and bandit:isUnderVehicle() then
                local bx, by = bandit:getX(), bandit:getY()
                pcall(function() bandit:setX(bx + 0.5) end)
                pcall(function() bandit:setY(by + 0.5) end)
            end
            if NPCEntity and NPCEntity.ClearTasks then NPCEntity.ClearTasks(bandit) end
            return false
        end
        return true
    elseif asn == "turnalerted" then
        if bandit.changeState and ZombieIdleState and ZombieIdleState.instance then pcall(function() bandit:changeState(ZombieIdleState.instance()) end) end
        if bandit.clearAggroList then pcall(function() bandit:clearAggroList() end) end
        if bandit.setTarget then pcall(function() bandit:setTarget(nil) end) end
        return true
    elseif asn == "pathfind" then
        return true
    elseif asn == "lunge" then
        if bandit.setUseless then pcall(function() bandit:setUseless(false) end) end
        if bandit.clearAggroList then pcall(function() bandit:clearAggroList() end) end
        if bandit.setTarget then pcall(function() bandit:setTarget(nil) end) end
        if bandit.changeState and ZombieIdleState and ZombieIdleState.instance then
            pcall(function() bandit:changeState(ZombieIdleState.instance()) end)
        end
        return true
    elseif asn == "getup" or asn == "getup-fromonback" or asn == "getup-fromonfront" or asn == "getup-fromsitting" or asn == "staggerback" or asn == "staggerback-knockeddown" then
        if NPCEntity and NPCEntity.ClearTasks then NPCEntity.ClearTasks(bandit) end
        return false
    end

    if bandit.setTarget then pcall(function() bandit:setTarget(nil) end) end
    if bandit.setTargetSeenTime then pcall(function() bandit:setTargetSeenTime(0) end) end
    if bandit.setUseless then pcall(function() bandit:setUseless(false) end) end
    return true
end

function Bridge.ManageEndurance(bandit)
    if not bridgeLegacySandboxBool("General_LimitedEndurance", true) then return {} end
    if not bandit then return {} end

    local brain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(bandit) or nil
    if not brain then return {} end
    if (brain.endurance or 0) > 0 or (NPCEntity and NPCEntity.HasActionTask and NPCEntity.HasActionTask(bandit)) then return {} end

    brain.endurance = 1
    local exhaustionTasks = {}
    local exhaustionTask = {action="Time", anim="Exhausted", time=200, lock=true}
    for i = 1, 5 do exhaustionTasks[i] = exhaustionTask end
    return exhaustionTasks
end

function Bridge.ManageHealth(bandit)
    local tasks = {}
    if not bandit then return tasks end

    if bridgeLegacySandboxBool("General_BleedOut", true) then
        local healing = false
        local health = bandit.getHealth and bandit:getHealth() or 1
        if health < 0.4 then
            local zx, zy = bandit:getX(), bandit:getY()
            if ZombRand and ZombRand(16) == 0 then
                local bx = zx - 0.5 + ZombRandFloat(0.1, 0.9)
                local by = zy - 0.5 + ZombRandFloat(0.1, 0.9)
                local chunk = bandit.getChunk and bandit:getChunk() or nil
                if chunk and chunk.addBloodSplat then chunk:addBloodSplat(bx, by, 0, ZombRand(20)) end
            end
            if NPCUtils and NPCUtils.IsController and NPCUtils.IsController(bandit) then
                pcall(function() bandit:setHealth(health - 0.00005) end)
            end
            if health < 0.2 and not (NPCEntity and NPCEntity.HasActionTask and NPCEntity.HasActionTask(bandit)) then
                if NPCEntity and NPCEntity.ClearTasks then NPCEntity.ClearTasks(bandit) end
                healing = true
            end
        end
        if healing then table.insert(tasks, {action="Bandage", time=800}) end
    end

    if bridgeLegacySandboxBool("General_Infection", true) then
        local brain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(bandit) or nil
        if brain and Bridge.IsWorldPersistentNPC(bandit, brain) then
            brain.infection = 0
        elseif brain and brain.infection and brain.infection > 0 then
            if NPCEntity and NPCEntity.UpdateInfection then NPCEntity.UpdateInfection(bandit, 0.001) end
            if brain.infection >= 100 then
                if NPCEntity and NPCEntity.ClearTasks then NPCEntity.ClearTasks(bandit) end
                table.insert(tasks, {action="Zombify", anim="Faint", lock=true, time=200})
            end
        end
    end
    return tasks
end



-- Stage 33: neutral collision / portal interaction bridge.
-- These functions keep the legacy local helper contracts in the old update facade,
-- but the implementation now lives in the neutral client backend.
function Bridge.CollisionIsDoor(object)
    if not object then return false end
    if instanceof(object, "IsoDoor") then return true end
    if instanceof(object, "IsoThumpable") then
        local ok, isDoor = pcall(function() return object:isDoor() == true end)
        if ok and isDoor then return true end
    end
    return false
end

function Bridge.CollisionIsLockedDoor(object)
    if not object then return false end
    if object.isBarricaded then
        local ok, barricaded = pcall(function() return object:isBarricaded() == true end)
        if ok and barricaded == true then return true end
    end
    return false
end

function Bridge.CollisionRecalcAround(cell, square, radius)
    if not cell or not square then return end
    radius = radius or 5

    for dx = -radius, radius do
        for dy = -radius, radius do
            local surroundingSquare = cell:getGridSquare(square:getX() + dx, square:getY() + dy, square:getZ())
            if surroundingSquare then
                pcall(function() surroundingSquare:InvalidateSpecialObjectPaths() end)
                pcall(function() surroundingSquare:RecalcProperties() end)
                pcall(function() surroundingSquare:RecalcAllWithNeighbours(true) end)
            end
        end
    end
end

function Bridge.CollisionRequestPortalTurn(bandit, object, purpose, tasks)
    if not NPCNavigationPerformanceBridge or not NPCNavigationPerformanceBridge.RequestPortalTurn then
        return true, nil
    end

    local ok, allowed, portalKey, position = pcall(function()
        return NPCNavigationPerformanceBridge.RequestPortalTurn(bandit, object, purpose)
    end)

    if not ok or allowed ~= false then
        return true, portalKey
    end

    if NPCNavigationPerformanceBridge.BuildPortalWaitTask then
        local waitTask = nil
        local okWait, ret = pcall(function()
            return NPCNavigationPerformanceBridge.BuildPortalWaitTask(bandit, object, portalKey, position)
        end)
        if okWait then waitTask = ret end
        if waitTask then table.insert(tasks, waitTask) end
    end

    if #tasks == 0 then
        pcall(function() bandit:faceThisObject(object) end)
    end

    return false, portalKey
end

function Bridge.CollisionReleasePortalTurn(bandit, portalKey)
    if portalKey and NPCNavigationPerformanceBridge and NPCNavigationPerformanceBridge.ReleasePortalKey then
        pcall(function() NPCNavigationPerformanceBridge.ReleasePortalKey(bandit, portalKey) end)
    end
end

-- manages collisions with doors, windows, fences and other objects
function Bridge.ManageCollisions(bandit)
    local tasks = {}
    if not bandit then return tasks end
    local square0 = bandit.getSquare and bandit:getSquare() or nil
    if not square0 then return tasks end

    local asn = bandit.getActionStateName and bandit:getActionStateName() or nil
    local sr = square0.getSheetRope and square0:getSheetRope() or nil
    if not NPCEntity.HasActionTask(bandit) and sr and asn ~= "climbrope" then
        bandit:changeState(ClimbSheetRopeState.instance())
        bandit:setVariable("ClimbUp", true)
    else
        bandit:setVariable("ClimbUp", false)
    end

    if not NPCEntity.HasActionTask(bandit) and bandit:isCollidedThisFrame() then
        local brain = NPCBrainData.Get(bandit)
        local nowMs = getTimestampMs and getTimestampMs() or 0
        if brain then
            brain.ai = brain.ai or {}
            brain.ai.collision = brain.ai.collision or {}
            if nowMs > 0 and brain.ai.collision.lastHandledAt and nowMs - brain.ai.collision.lastHandledAt < 650 then
                return tasks
            end
            brain.ai.collision.lastHandledAt = nowMs
        end

        local fd = bandit.getForwardDirection and bandit:getForwardDirection() or nil
        if not fd then return tasks end
        local fdx = math.floor(fd:getX() + 0.5)
        local fdy = math.floor(fd:getY() + 0.5)

        local sqs = {}
        table.insert(sqs, {x = math.floor(bandit:getX()), y = math.floor(bandit:getY()), z = bandit:getZ()})
        table.insert(sqs, {x = math.floor(bandit:getX()) + fdx, y=math.floor(bandit:getY()) + fdy, z = bandit:getZ()})

        local cell = getCell and getCell() or nil
        if not cell then return tasks end
        for _, s in pairs(sqs) do
            local square = cell:getGridSquare(s.x, s.y, s.z)
            if square then

                -- local safehouse = SafeHouse.isSafeHouse(square, nil, true)
                -- print ("SQ X:" .. square:getX() .. " Y:" .. square:getY())
                local objects = square:getObjects()
                for i = 0, objects:size() - 1 do
                    local object = objects:get(i)
                    local properties = object:getProperties()

                    if properties then
                        local weapons = NPCEntity.GetWeapons(bandit)
                        local lowFence = properties:Val("FenceTypeLow")
                        local hoppable = object:isHoppable()
                        local isDoorCollision = Bridge.CollisionIsDoor(object)

                        -- LOW FENCE COLLISION
                        if (lowFence or hoppable) and not isDoorCollision then
                            if bandit:isFacingObject(object, 0.5) then
                                local params = bandit:getStateMachineParams(ClimbOverFenceState.instance())
                                local raw = KahluaUtil.rawTostring2(params) -- ugly but works
                                local endx = string.match(raw, "3=(%d+)")
                                local endy = string.match(raw, "4=(%d+)")

                                if endx and endy then
                                    bandit:changeState(ClimbOverFenceState.instance())
                                    bandit:setBumpType("ClimbFenceEnd")
                                end
                            else
                                bandit:faceThisObject(object)
                            end
                            return tasks
                        end

                        -- HIGH FENCE COLLISION
                        local highFence = properties:Val("FenceTypeHigh")
                        if highFence and hoppable then
                            if bandit:getVariableBoolean("bPathfind") or not bandit:getVariableBoolean("bMoving") then
                                bandit:setVariable("bPathfind", false)
                                bandit:setVariable("bMoving", true)
                            end

                            if bandit:isFacingObject(object, 0.5) then

                                -- bandit:changeState(ClimbOverFenceState.instance())
                                if not bandit:getVariableBoolean("ClimbWallStartEnded") then
                                    bandit:setVariable("hitreaction", "ClimbWallStart")
                                else
                                    bandit:setCollidable(false)
                                    bandit:setVariable("hitreaction", "ClimbWallSuccess")
                                end


                            else
                                bandit:faceThisObject(object)
                            end
                            return tasks
                        end

                        -- WINDOW COLLISIONS
                        if instanceof(object, "IsoWindow") then
                            if bandit:isFacingObject(object, 0.5) then
                                if object:isBarricaded() then
                                    if bridgeLegacySandboxBool("General_RemoveBarricade", true) and NPCEntity.Can(bandit, "unbarricade") then
                                        local barricade = object:getBarricadeOnSameSquare()
                                        local fx, fy
                                        if barricade then
                                            if properties:Is(IsoFlagType.WindowN) then
                                                fx = barricade:getX()
                                                fy = barricade:getY() - 0.5
                                            else
                                                fx = barricade:getX() - 0.5
                                                fy = barricade:getY()
                                            end

                                        else
                                            barricade = object:getBarricadeOnOppositeSquare()
                                            if properties:Is(IsoFlagType.WindowN) then
                                                fx = barricade:getX()
                                                fy = barricade:getY() + 0.5
                                            else
                                                fx = barricade:getX() + 0.5
                                                fy = barricade:getY()
                                            end
                                        end

                                        if barricade:isMetal() or barricade:isMetalBar() then
                                            local task1 = {action="Equip", itemPrimary=NPC_UPDATE_LEGACY_ITEMS.propaneTorch}
                                            table.insert(tasks, task1)

                                            local task2 = {action="UnbarricadeMetal", anim="BlowtorchHigh", time=500, fx=fx, fy=fy, x=object:getSquare():getX(), y=object:getSquare():getY(), z=object:getSquare():getZ(), idx=object:getObjectIndex()}
                                            table.insert(tasks, task2)
                                            return tasks
                                        else
                                            local task1 = {action="Equip", itemPrimary="Base.Crowbar"}
                                            table.insert(tasks, task1)

                                            local task2 = {action="Unbarricade", anim="RemoveBarricadeCrowbarHigh", time=300, fx=fx, fy=fy, x=object:getSquare():getX(), y=object:getSquare():getY(), z=object:getSquare():getZ(), idx=object:getObjectIndex()}
                                            table.insert(tasks, task2)
                                            return tasks
                                        end
                                    end

                                elseif not object:IsOpen() and not object:isSmashed() then
                                    local task = {action="OpenWindow", anim="WindowOpen", time=25, x=object:getSquare():getX(), y=object:getSquare():getY(), z=object:getSquare():getZ()}
                                    table.insert(tasks, task)
                                    return tasks

                                elseif object:canClimbThrough(bandit) then
                                    ClimbThroughWindowState.instance():setParams(bandit, object)
                                    bandit:changeState(ClimbThroughWindowState.instance())
                                    bandit:setBumpType("ClimbWindow")
                                    return tasks
                                end
                            end

                        elseif false and (properties:Is(IsoFlagType.WindowW) or properties:Is(IsoFlagType.WindowN)) then
                            ClimbThroughWindowState.instance():setParams(bandit, object)
                            bandit:changeState(ClimbThroughWindowState.instance())
                            bandit:setBumpType("ClimbWindow")
                            return tasks
                        end

                        -- DOOR COLLISIONS
                        if isDoorCollision then
                            local portalKey = nil
                            if bandit:isFacingObject(object, 0.5) then
                                local portalAllowed
                                portalAllowed, portalKey = Bridge.CollisionRequestPortalTurn(bandit, object, "door", tasks)
                                if not portalAllowed then
                                    return tasks
                                end

                                if object:isBarricaded() then
                                    if bridgeLegacySandboxBool("General_RemoveBarricade", true) and NPCEntity.Can(bandit, "unbarricade") then

                                        local barricade = object:getBarricadeOnSameSquare()
                                        local fx, fy
                                        if barricade then
                                            if properties:Is(IsoFlagType.doorN) then
                                                fx = barricade:getX()
                                                fy = barricade:getY() - 1
                                            else
                                                fx = barricade:getX() - 1
                                                fy = barricade:getY()
                                            end

                                        else
                                            barricade = object:getBarricadeOnOppositeSquare()
                                            if properties:Is(IsoFlagType.doorN) then
                                                fx = barricade:getX()
                                                fy = barricade:getY() + 1
                                            else
                                                fx = barricade:getX() + 1
                                                fy = barricade:getY()
                                            end
                                        end
                                        local task1 = {action="Equip", itemPrimary="Base.Crowbar"}
                                        table.insert(tasks, task1)

                                        local task2 = {action="Unbarricade", anim="RemoveBarricadeCrowbarHigh", time=230, fx=fx, fy=fy, x=object:getSquare():getX(), y=object:getSquare():getY(), z=object:getSquare():getZ(), idx=object:getObjectIndex(), portalKey=portalKey}
                                        table.insert(tasks, task2)
                                        return tasks
                                    end

                                elseif Bridge.CollisionIsLockedDoor(object) then
                                    if bridgeLegacySandboxBool("General_DestroyDoor", true) and NPCEntity.Can(bandit, "breakDoor") then
                                        -- NPCEntity.ClearTasks(bandit)

                                        local task1 = {action="Equip", itemPrimary=weapons.melee}
                                        table.insert(tasks, task1)

                                        local task2 = {action="Destroy", anim="ChopTree", x=object:getSquare():getX(), y=object:getSquare():getY(), z=object:getSquare():getZ(), idx=object:getObjectIndex(), portalKey=portalKey, sound=object:getThumpSound(), time=80}
                                        table.insert(tasks, task2)
                                        return tasks
                                    end

                                elseif not object:IsOpen() and NPCEntity.Can(bandit, "openDoor") then
                                    pcall(function() if object.setLocked then object:setLocked(false) end end)
                                    pcall(function() if object.setLockedByKey then object:setLockedByKey(false) end end)
                                    pcall(function() if object.setPermaLocked then object:setPermaLocked(false) end end)
                                    pcall(function() if object.setLockedByPadlock then object:setLockedByPadlock(false) end end)
                                    local openedSpecial = false
                                    if instanceof(object, "IsoDoor") and IsoDoor then
                                        if IsoDoor.getDoubleDoorIndex and IsoDoor.getDoubleDoorIndex(object) > -1 and IsoDoor.toggleDoubleDoor then
                                            IsoDoor.toggleDoubleDoor(object, true)
                                            openedSpecial = true
                                        elseif IsoDoor.getGarageDoorIndex and IsoDoor.getGarageDoorIndex(object) > -1 and IsoDoor.toggleGarageDoor then
                                            IsoDoor.toggleGarageDoor(object, true)
                                            openedSpecial = true
                                        end
                                    end

                                    if not openedSpecial then
                                        object:ToggleDoorSilent()
                                    end

                                    local args = {
                                        x = object:getSquare():getX(),
                                        y = object:getSquare():getY(),
                                        z = object:getSquare():getZ(),
                                        index = object:getObjectIndex()
                                    }
                                    sendClientCommand(getPlayer(), 'NPCCommands', 'OpenDoor', args)

                                    Bridge.CollisionRecalcAround(cell, object:getSquare(), 5)
                                    bandit:playSound("WoodDoorOpen")
                                    Bridge.CollisionReleasePortalTurn(bandit, portalKey)
                                end

                                if portalKey and #tasks == 0 then
                                    Bridge.CollisionReleasePortalTurn(bandit, portalKey)
                                end
                            else
                                bandit:faceThisObject(object)
                            end
                            return tasks
                        end

                        -- THUMPABLE COLLISIONS
                        if instanceof(object, "IsoThumpable") and not properties:Val("FenceTypeLow") then
                            if bridgeLegacySandboxBool("General_DestroyThumpable", true) and NPCEntity.Can(bandit, "breakObjects") then
                                local isWallTo = bandit:getSquare():isSomethingTo(object:getSquare())
                                if not isWallTo then
                                    NPCEntity.ClearTasks(bandit)

                                    local task = {action="Equip", itemPrimary=weapons.melee}
                                    table.insert(tasks, task)

                                    local task = {action="FaceLocation", x=object:getSquare():getX(), y=object:getSquare():getY(), z=object:getSquare():getZ(), time=30}
                                    table.insert(tasks, task)

                                    local task = {action="Destroy", anim="ChopTree", x=object:getSquare():getX(), y=object:getSquare():getY(), z=object:getSquare():getZ(), idx=object:getObjectIndex(), sound=object:getThumpSound(), time=80}
                                    table.insert(tasks, task)
                                    return tasks
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return tasks
end



function Bridge.GetEscapePoint(bandit, radius)
    if not bandit then return 0, 0, 0 end

    local bx = bandit.getX and bandit:getX() or 0
    local by = bandit.getY and bandit:getY() or 0
    local bz = bandit.getZ and bandit:getZ() or 0
    local brain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(bandit) or nil

    local sectors = Bridge._escapeSectors
    if not sectors then
        sectors = {
            {x=-3,  y=-16, e=0},
            {x=5,   y=-13, e=0},
            {x=8,   y=-4,  e=0},
            {x=5,   y=5,   e=0},
            {x=-3,  y=8,   e=0},
            {x=-11, y=5,   e=0},
            {x=-15, y=-4,  e=0},
            {x=-11, y=-13, e=0}
        }
        Bridge._escapeSectors = sectors
    end

    for i = 1, #sectors do
        sectors[i].e = 0
    end

    local function isEnemy(otherBrain)
        if not otherBrain then return true end
        if NPCFactionBridge and NPCFactionBridge.IsEnabled and NPCFactionBridge.IsEnabled() and NPCFactionBridge.AreBrainsEnemies then
            return NPCFactionBridge.AreBrainsEnemies(brain, otherBrain)
        end
        if not brain then return false end
        return brain.clan ~= otherBrain.clan and (brain.hostile == true or otherBrain.hostile == true)
    end

    local function countEntry(entry)
        if not entry then return end
        local ex = (tonumber(entry.x) or bx) - bx
        local ey = (tonumber(entry.y) or by) - by
        for i = 1, #sectors do
            local sector = sectors[i]
            if ex >= sector.x and ex < sector.x + 8 and ey >= sector.y and ey < sector.y + 8 then
                if isEnemy(entry.brain) then
                    sector.e = sector.e + 1
                end
                return
            end
        end
    end

    local nearby, nearbyCount = Bridge.GetNearbyAllInto("escapeNearby", bx, by, bz, radius or 18)
    if nearby then
        for i = 1, nearbyCount do
            countEntry(nearby[i])
        end
    elseif NPCZombieCacheBridge and NPCZombieCacheBridge.CacheLight then
        for _, entry in pairs(NPCZombieCacheBridge.CacheLight) do
            countEntry(entry)
        end
    end

    local bestIndex = 1
    local bestScore = math.huge
    for i = 1, #sectors do
        if sectors[i].e < bestScore then
            bestScore = sectors[i].e
            bestIndex = i
        end
    end

    local chosen = sectors[bestIndex]
    return bx + chosen.x + 3.5, by + chosen.y + 3.5, bz
end

function Bridge.ManagePreservation(bandit)
    local tasks = {}
    local bx, by, bz = bandit:getX(), bandit:getY(), bandit:getZ()
    local brain = NPCBrainData.Get(bandit)
    if Bridge.IsBlackMarketNoCombatBrain(brain) then return tasks end

    local friendlies, enemies = 0, 0
    local radius = 9
    local radiusSquared = radius * radius  -- Avoid sqrt calls by using squared distance

    local potentialEnemyList = NPCZombieCacheBridge.CacheLight
    if NPCSpatialIndexBridge and NPCSpatialIndexBridge.GetNearbyAll then
        potentialEnemyList = NPCSpatialIndexBridge.GetNearbyAll(bx, by, bz, radius)
    end

    for _, potentialEnemy in pairs(potentialEnemyList) do
        if bz == potentialEnemy.z then  -- First check avoids unnecessary calculations
            local dx, dy = potentialEnemy.x - bx, potentialEnemy.y - by
            if dx * dx + dy * dy <= radiusSquared then  -- Faster than Manhattan distance
                local enemyBrain = potentialEnemy.brain
                if Bridge.IsBlackMarketNoCombatBrain(enemyBrain) then
                    friendlies = friendlies + 1
                elseif not enemyBrain or (NPCFactionBridge and NPCFactionBridge.IsEnabled and NPCFactionBridge.IsEnabled() and NPCFactionBridge.AreBrainsEnemies and NPCFactionBridge.AreBrainsEnemies(brain, enemyBrain)) or ((not NPCFactionBridge or not NPCFactionBridge.IsEnabled or not NPCFactionBridge.IsEnabled()) and brain.clan ~= enemyBrain.clan and (brain.hostile or enemyBrain.hostile)) then
                    enemies = enemies + 1
                else
                    friendlies = friendlies + 1
                end
            end
        end
    end

    if enemies > friendlies + 3 then
        local tx, ty, tz = Bridge.GetEscapePoint(bandit, 10)
        local task = NPCUtils.GetMoveTask(0.01, tx, ty, tz, "Run", 30, false)
        task.panic = true
        task.lock = true
        table.insert(tasks, task)
    end 

    return tasks
end

function Bridge.CheckFriendlyFire(bandit, attacker)
    if not (bandit and attacker) then return false end
    if not (bandit.getVariableBoolean and bandit:getVariableBoolean(NPC_LEGACY_KEYS.FLAG)) then return false end
    if not (instanceof and instanceof(attacker, "IsoPlayer")) then return false end
    if attacker.isNPC and attacker:isNPC() then return false end

    local brain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(bandit) or nil
    if not brain or brain.clan == 0 or brain.hostile == true then return false end

    local function makeHostile(target)
        if not target then return false end
        if NPCEntity and NPCEntity.SetHostile then NPCEntity.SetHostile(target, true) end
        if NPCEntity and NPCEntity.SetProgram then NPCEntity.SetProgram(target, "Raider", {}) end

        local targetBrain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(target) or nil
        if targetBrain and NPCEntity and NPCEntity.ForceSyncPart then
            NPCEntity.ForceSyncPart(target, {id=targetBrain.id, hostile=true, program={name="Raider", stage="Prepare"}})
        end
        return true
    end

    if brain.program and brain.program.name == "Thief" then
        return makeHostile(bandit)
    end

    local ax = attacker.getX and attacker:getX() or nil
    local ay = attacker.getY and attacker:getY() or nil
    if not (ax and ay and NPCZombieCacheBridge and NPCZombieCacheBridge.Cache and NPCZombieCacheBridge.CacheLightB) then return false end

    local changed = false
    for _, witness in pairs(NPCZombieCacheBridge.CacheLightB) do
        local wBrain = witness and witness.brain
        if wBrain and wBrain.hostile ~= true then
            local dx = (tonumber(witness.x) or ax) - ax
            local dy = (tonumber(witness.y) or ay) - ay
            if dx * dx + dy * dy < 144 then
                local friendly = NPCZombieCacheBridge.Cache[witness.id]
                local canSee = false
                if friendly and friendly.CanSee then
                    local ok, result = pcall(function() return friendly:CanSee(attacker) end)
                    canSee = ok and result == true
                end
                if canSee and makeHostile(friendly) then
                    changed = true
                end
            end
        end
    end
    return changed
end

function Bridge.ApplyMercenarySuppression(brain, enemyCharacter, enemyKind, dist, firing)
    if firing ~= true then return false end
    if enemyKind == "zombie" or enemyKind == "zed" or enemyKind == "undead" then return false end
    if not (NPCUtilityAIBridge and NPCUtilityAIBridge.ApplySuppressionFire and NPCUtilityAIBridge.IsPlayerGuardSuppressing) then return false end
    if not NPCUtilityAIBridge.IsPlayerGuardSuppressing(brain) then return false end
    if not enemyCharacter or (enemyCharacter.isAlive and not enemyCharacter:isAlive()) then return false end

    local targetBrain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(enemyCharacter) or nil
    if not targetBrain then return false end

    local ok = pcall(function()
        NPCUtilityAIBridge.ApplySuppressionFire(brain, enemyCharacter, targetBrain, dist)
    end)
    return ok == true
end

function Bridge.ManageCombat(bandit, uTick)

    if bandit:isCrawling() then return {} end 
    if NPCEntity.IsSleeping(bandit) then return {} end
    -- if bandit:getActionStateName() == "bumped" then return {} end

    local tasks = {}
    local zx, zy, zz = bandit:getX(), bandit:getY(), bandit:getZ()
    local brain = NPCBrainData.Get(bandit)
    if Bridge.IsBlackMarketNoCombatBrain(brain) then return tasks end
    local combatId = brain and (brain.id or brain.uid or brain.persistentId) or NPCUtils.GetZombieID(bandit)
    local asyncCombatScanActive = brain and brain.ai and brain.ai.asyncCombatScanActive == true
    if (not asyncCombatScanActive) and NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.AllowCombatScan then
        local okCombatGate, allowCombatGate = pcall(function()
            return NPCWorkSchedulerBridge.AllowCombatScan(combatId, brain, uTick, bandit)
        end)
        if okCombatGate and allowCombatGate == false then return tasks end
    end
    if NPCOrderContract and NPCOrderContract.Ensure then
        NPCOrderContract.Ensure(brain)
    end
    Bridge.UpdateUtilityAIOnce(bandit, brain)
    if NPCFactionBridge and NPCFactionBridge.UpdateNPCState then
        pcall(function()
            NPCFactionBridge.UpdateNPCState(bandit, brain)
        end)
    end

    local weapons = brain.weapons
    local canMelee = NPCEntity.Can(bandit, "melee")
    local canShoot = NPCEntity.Can(bandit, "shoot")
    if NPCOrderContract and NPCOrderContract.CanMelee then
        canMelee = canMelee and NPCOrderContract.CanMelee(brain)
    end
    if NPCOrderContract and NPCOrderContract.CanShoot then
        canShoot = canShoot and NPCOrderContract.CanShoot(brain)
    end
    
    local bestDist = 40
    local enemyCharacter
    local selectedEnemyKind
    local combat, firing, shove = false, false, false
    local maxRange

    -- PRECOMPUTE WEAPON RANGES
    local pistolRange, rifleRange = bridgeLegacySandboxNumber("General_PistolRange", 10) - 1, bridgeLegacySandboxNumber("General_RifleRange", 24) - 1
    if NPCEntity.IsDNA(bandit, "blind") then
        pistolRange, rifleRange = pistolRange - 4, rifleRange - 7
    end

    -- COMBAT AGAIST PLAYERS 
    if (NPCFactionBridge and NPCFactionBridge.IsEnabled and NPCFactionBridge.IsEnabled()) or NPCEntity.IsHostile(bandit) then
        local playerList = NPCPlayerClient.GetPlayers()

        for i=0, playerList:size()-1 do
            local potentialEnemy = playerList:get(i)
            if potentialEnemy and instanceof(potentialEnemy, "IsoPlayer") and not NPCPlayerClient.IsGhost(potentialEnemy) and (not NPCFactionBridge or not NPCFactionBridge.CanBrainAttackPlayer or NPCFactionBridge.CanBrainAttackPlayer(brain, potentialEnemy)) then
                local detected, detection = Bridge.DetectTarget(bandit, potentialEnemy, brain, "player")
                if detected then
                    local px, py, pz = potentialEnemy:getX(), potentialEnemy:getY(), potentialEnemy:getZ()
                    local dist = detection and detection.dist or math.sqrt(((zx - px) * (zx - px)) + ((zy - py) * (zy - py)))
                    if dist < bestDist and pz == zz then
                        local spottedScore = detection and detection.score or Bridge.CalcSpottedScore(potentialEnemy, dist)
                        if spottedScore and spottedScore > 0.20 then
                            bestDist, enemyCharacter = dist, potentialEnemy
                            selectedEnemyKind = "player"

                            --determine if bandit will be in combat mode
                            if weapons.melee and canMelee then
                                if not maxRange then
                                    maxRange = NPCCompatibilityBridge.InstanceItem(weapons.melee):getMaxRange()
                                end
                                if dist <= maxRange - 0.2 then
                                    local asn = enemyCharacter:getActionStateName()
                                    shove = dist < 0.6 and not potentialEnemy:isProne() and asn ~= "onground" and asn ~= "sitonground" and asn ~= "climbfence" and asn ~= "bumped"
                                    combat = not shove
                                end
                            end

                            --determine if bandit will be in shooting mode
                            if canShoot and (not NPCOrderContract or not NPCOrderContract.CanShootAtDistance or NPCOrderContract.CanShootAtDistance(brain, dist)) then
                                if weapons.primary and (weapons.primary.bulletsLeft > 0 or weapons.primary.magCount > 0) and dist < rifleRange then
                                    firing = true
                                elseif weapons.secondary and (weapons.secondary.bulletsLeft > 0 or weapons.secondary.magCount > 0) and dist < pistolRange then
                                    firing = true
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- COMBAT AGAINST ZOMBIES AND NPCS FROM OTHER CLAN
    local cache = NPCZombieCacheBridge.Cache
    local potentialEnemyList, potentialEnemyCount = Bridge.GetNearbyAllInto("combatNearby", zx, zy, zz, 36)
    local potentialEnemyIsArray = potentialEnemyList ~= nil
    if not potentialEnemyList then
        potentialEnemyList = NPCZombieCacheBridge.CacheLight
    end

    local candidateLimit = Bridge.GetCombatCandidateLimit()
    local candidateBuf = Bridge.GetCombatCandidateBuffer(brain)
    local candidateIds = candidateBuf.ids
    local candidateKinds = candidateBuf.kinds
    local candidateD2s = candidateBuf.d2s
    local candidateCount = 0
    local worstIndex, worstD2 = 0, -1

    local function considerPotentialEnemy(id, potentialEnemy)
        id = potentialEnemy and (potentialEnemy.id or id) or id
        if potentialEnemy and potentialEnemy.z == zz and not Bridge.IsBlackMarketNoCombatBrain(potentialEnemy.brain) and (not potentialEnemy.brain or (NPCFactionBridge and NPCFactionBridge.IsEnabled and NPCFactionBridge.IsEnabled() and NPCFactionBridge.AreBrainsEnemies and NPCFactionBridge.AreBrainsEnemies(brain, potentialEnemy.brain)) or ((not NPCFactionBridge or not NPCFactionBridge.IsEnabled or not NPCFactionBridge.IsEnabled()) and brain.clan ~= potentialEnemy.brain.clan and (brain.hostile or potentialEnemy.brain.hostile))) then
            local dx = potentialEnemy.x - zx
            local dy = potentialEnemy.y - zy
            local manhattan = math.abs(dx) + math.abs(dy)
            if manhattan < 36 then
                local d2 = dx * dx + dy * dy
                if d2 < 625 then
                    local enemyKind = potentialEnemy.brain and "bandit" or "zombie"
                    if candidateCount < candidateLimit then
                        candidateCount = candidateCount + 1
                        candidateIds[candidateCount] = id
                        candidateKinds[candidateCount] = enemyKind
                        candidateD2s[candidateCount] = d2
                        if d2 > worstD2 then
                            worstD2 = d2
                            worstIndex = candidateCount
                        end
                    elseif d2 < worstD2 and worstIndex > 0 then
                        candidateIds[worstIndex] = id
                        candidateKinds[worstIndex] = enemyKind
                        candidateD2s[worstIndex] = d2
                        worstD2 = d2
                        for i=1, candidateCount do
                            local cd2 = candidateD2s[i] or -1
                            if cd2 > worstD2 then
                                worstD2 = cd2
                                worstIndex = i
                            end
                        end
                    end
                end
            end
        end
    end

    if potentialEnemyIsArray then
        for i=1, potentialEnemyCount do
            local potentialEnemy = potentialEnemyList[i]
            considerPotentialEnemy(i, potentialEnemy)
        end
    else
        for id, potentialEnemy in pairs(potentialEnemyList) do
            considerPotentialEnemy(id, potentialEnemy)
        end
    end

    candidateBuf.n = candidateCount

    for i=1, candidateCount do
        local enemyInstance = cache[candidateIds[i]]
        if enemyInstance then
            local enemyKind = candidateKinds[i]
            local detected, detection = Bridge.DetectTarget(bandit, enemyInstance, brain, enemyKind)
            if detected then
                local px, py, pz = enemyInstance:getX(), enemyInstance:getY(), enemyInstance:getZ()
                local dist = detection and detection.dist or math.sqrt(((zx - px) * (zx - px)) + ((zy - py) * (zy - py)))
                if dist < 25 and dist < bestDist then
                    bestDist, enemyCharacter = dist, enemyInstance
                    selectedEnemyKind = enemyKind

                    --determine if bandit will be in combat mode
                    if canMelee and weapons.melee and zz == pz then
                        if not maxRange then
                            brain.ai = brain.ai or {}
                            if brain.ai.cachedMeleeName == weapons.melee and brain.ai.cachedMeleeRange then
                                maxRange = brain.ai.cachedMeleeRange
                            else
                                maxRange = NPCCompatibilityBridge.InstanceItem(weapons.melee):getMaxRange()
                                brain.ai.cachedMeleeName = weapons.melee
                                brain.ai.cachedMeleeRange = maxRange
                            end
                        end
                        if dist <= maxRange + 0.40 then
                            local asn = enemyCharacter:getActionStateName()
                            shove = dist < 0.7 and not enemyCharacter:isProne() and asn ~= "onground" and asn ~= "climbfence" and asn ~= "bumped" and asn ~= "getup" and asn ~= "falldown"
                            combat = not shove
                        end
                    end

                    --determine if bandit will be in shooting mode
                    if canShoot and (not NPCOrderContract or not NPCOrderContract.CanShootAtDistance or NPCOrderContract.CanShootAtDistance(brain, dist)) then
                        if weapons.primary and  (weapons.primary.bulletsLeft > 0 or weapons.primary.magCount > 0) and dist < rifleRange then 
                            firing = true
                        elseif weapons.secondary and  (weapons.secondary.bulletsLeft > 0 or weapons.secondary.magCount > 0) and dist < pistolRange then
                            firing = true
                        end
                    end
                end
            end
        end
    end

    if enemyCharacter and NPCTacticalRadioBridge and NPCTacticalRadioBridge.ReportContact then
        pcall(function()
            NPCTacticalRadioBridge.ReportContact(bandit, brain, enemyCharacter, selectedEnemyKind or "unknown", bestDist, 1.0)
        end)
    end

    Bridge.ApplyMercenarySuppression(brain, enemyCharacter, selectedEnemyKind, bestDist, firing)

    if firing and combat and not shove then
        combat = false
    end

    if firing and enemyCharacter and NPCTacticalRadioBridge and NPCTacticalRadioBridge.CanFire then
        local ok, clearFire = pcall(function()
            return NPCTacticalRadioBridge.CanFire(bandit, brain, enemyCharacter)
        end)
        if ok and clearFire == false then
            firing = false
            combat = false
            shove = false
        end
    end

    if shove then
        if not NPCEntity.HasTaskType(bandit, "Shove") then
            NPCEntity.ClearTasks(bandit)
            local veh = enemyCharacter:getVehicle()
            if veh then NPCEntity.Say(bandit, "CAR") end

            if bandit:isFacingObject(enemyCharacter, 0.1) then
                local eid = NPCUtils.GetCharacterID(enemyCharacter)
                local targetKind = (instanceof and instanceof(enemyCharacter, "IsoPlayer")) and "player" or "bandit"
                local task = {action="Shove", anim="Shove", sound="AttackShove", time=60, endurance=-0.05, eid=eid, targetId=eid, targetKind=targetKind, x=enemyCharacter:getX(), y=enemyCharacter:getY(), z=enemyCharacter:getZ()}
                table.insert(tasks, task)
            else
                bandit:faceThisObject(enemyCharacter)
            end
        end

    elseif combat then
        if not NPCEntity.HasTaskType(bandit, "Hit") and not NPCEntity.HasTaskType(bandit, "Shove") and not NPCEntity.HasTaskType(bandit, "Equip") and not NPCEntity.HasTaskType(bandit, "Unequip") and enemyCharacter:isAlive() then
            NPCEntity.ClearTasks(bandit)
            local veh = enemyCharacter:getVehicle()
            if veh then NPCEntity.Say(bandit, "CAR") end

            if not bandit:isPrimaryEquipped(weapons.melee) then
                local stasks = NPCPrograms.Weapon.Switch(bandit, weapons.melee)
                for _, t in pairs(stasks) do table.insert(tasks, t) end
            end

            if bandit:isFacingObject(enemyCharacter, 0.5) then
                local eid = NPCUtils.GetCharacterID(enemyCharacter)
                local targetKind = (instanceof and instanceof(enemyCharacter, "IsoPlayer")) and "player" or "bandit"
                local task = {action="Hit", time=65, endurance=-0.03, weapon=weapons.melee, eid=eid, targetId=eid, targetKind=targetKind, x=enemyCharacter:getX(), y=enemyCharacter:getY(), z=enemyCharacter:getZ()}
                table.insert(tasks, task)
            else
                bandit:faceThisObject(enemyCharacter)
            end

        
        elseif instanceof(enemyCharacter, "IsoPlayer") and not NPCEntity.HasActionTask(bandit) then
            local task = {action="Time", anim="Smoke", time=250}
            table.insert(tasks, task)
            NPCEntity.Say(bandit, "DEATH")
        end


    elseif firing then
        if not NPCEntity.HasActionTask(bandit) then
            NPCEntity.ClearTasks(bandit)
            if enemyCharacter:isAlive() then
                
                local veh = enemyCharacter:getVehicle()
                if veh then NPCEntity.Say(bandit, "CAR") end

                if bandit:isFacingObject(enemyCharacter, 0.5) then
                    for _, slot in pairs({"primary", "secondary"}) do
                        if weapons[slot].name and (weapons[slot].bulletsLeft > 0 or weapons[slot].magCount > 0) then
                            if not bandit:isPrimaryEquipped(weapons[slot].name) then
                                NPCEntity.Say(bandit, "SPOTTED")

                                local stasks = NPCPrograms.Weapon.Switch(bandit, weapons[slot].name)
                                for _, t in pairs(stasks) do table.insert(tasks, t) end
                            end

                            if not NPCEntity.IsAim(bandit) then
                                local stasks = NPCPrograms.Weapon.Aim(bandit, enemyCharacter, slot)
                                for _, t in pairs(stasks) do table.insert(tasks, t) end
                            end

                            if weapons[slot].bulletsLeft > 0 then
                                local stasks = NPCPrograms.Weapon.Shoot(bandit, enemyCharacter, slot)
                                for _, t in pairs(stasks) do table.insert(tasks, t) end

                            elseif weapons[slot].magCount > 0 then
                                NPCEntity.Say(bandit, "RELOADING")

                                local stasks = NPCPrograms.Weapon.Reload(bandit, slot)
                                for _, t in pairs(stasks) do table.insert(tasks, t) end
                            end
                            -- NPCEntity.SetWeapons(bandit, weapons)
                            break
                        end
                    end
                else
                    bandit:faceThisObject(enemyCharacter)
                end

            elseif instanceof(enemyCharacter, "IsoPlayer") then
                local task = {action="Time", anim="Smoke", time=250}
                table.insert(tasks, task)
                NPCEntity.Say(bandit, "DEATH")
            end

        end
    end

    return tasks
end



local BRIDGE_TASK_LAST_ERROR = Bridge._taskLastError or {}
Bridge._taskLastError = BRIDGE_TASK_LAST_ERROR

function Bridge.LogTaskError(key, message)
    key = tostring(key or "task")
    local now = getTimestampMs and getTimestampMs() or 0
    if (BRIDGE_TASK_LAST_ERROR[key] or 0) + 5000 > now then return end
    BRIDGE_TASK_LAST_ERROR[key] = now
    print("[NPCUpdate] " .. tostring(message))
end

function Bridge.RemoveBadTask(bandit, reason, task)
    Bridge.LogTaskError("bad-task:" .. tostring(reason or "unknown") .. ":" .. tostring(task and task.action or "nil"), "removed bad task action=" .. tostring(task and task.action or "nil") .. " reason=" .. tostring(reason or "unknown"))
    if NPCEntity and NPCEntity.RemoveTask then
        pcall(function() NPCEntity.RemoveTask(bandit) end)
    end
end

function Bridge.GetTaskAction(task)
    if not task or not task.action then return nil end
    if not ZombieActions then return nil end
    local action = ZombieActions[task.action]
    if type(action) ~= "table" then return nil end
    return action
end

function Bridge.CallTaskAction(action, methodName, bandit, task)
    if type(action) ~= "table" or type(action[methodName]) ~= "function" then
        return false, "missing_" .. tostring(methodName)
    end

    local ok, result = pcall(action[methodName], bandit, task)
    if not ok then return false, result end
    return true, result
end

function Bridge.CanPlayTaskSound(bandit, task)
    if not task or not task.sound then return false end
    if task.soundDistMax then
        local player = getPlayer and getPlayer() or nil
        if not player then return false end
        local dist = NPCUtils.DistTo(bandit:getX(), bandit:getY(), player:getX(), player:getY())
        if dist > task.soundDistMax then return false end
    end
    return true
end

function Bridge.PlayTaskSound(bandit, sound)
    if not bandit or not sound then return end

    local emitter = nil
    if bandit.getEmitter then
        local ok, value = pcall(function() return bandit:getEmitter() end)
        if ok then emitter = value end
    end

    local playing = false
    if emitter and emitter.isPlaying then
        local ok, value = pcall(function() return emitter:isPlaying(sound) end)
        playing = ok and value == true
    end

    if playing then return end

    if emitter and emitter.playSound then
        local ok = pcall(function() emitter:playSound(sound) end)
        if ok then return end
    end

    if bandit.playSound then
        pcall(function() bandit:playSound(sound) end)
    end
end

function Bridge.ProcessTask(bandit, task)
    if not task or not task.action then return end

    local action = Bridge.GetTaskAction(task)
    if not action then
        Bridge.RemoveBadTask(bandit, "missing_action", task)
        return
    end

    if not task.state then task.state = "NEW" end

    if task.state == "NEW" then
        
        if not task.time then task.time = 1000 end

        if task.action ~= "Shoot" and task.action ~= "Aim" then
            NPCEntity.SetAim(bandit, false)
        end

        if task.action ~= "Move" and task.action ~= "GoTo" then
            if NPCEntity.IsMoving(bandit) then
                NPCEntity.SetMoving(bandit, false)
            end
        end

        if Bridge.CanPlayTaskSound(bandit, task) then
            Bridge.PlayTaskSound(bandit, task.sound)
        end

        if task.anim then
            bandit:setBumpType(task.anim)
        end
        
        local ok, done = Bridge.CallTaskAction(action, "onStart", bandit, task)
        if not ok then
            Bridge.RemoveBadTask(bandit, done, task)
            return
        end

        if done then 
            task.state = "WORKING"
            --NPCEntity.UpdateTask(bandit, task)
        end

    elseif task.state == "WORKING" then

        -- normalize time speed
        local decrement = 1 / ((getAverageFPS() + 0.5) * 0.01666667)
        task.time = task.time - decrement

        local ok, done = Bridge.CallTaskAction(action, "onWorking", bandit, task)
        if not ok then
            Bridge.RemoveBadTask(bandit, done, task)
            return
        end
        if done or task.time <= 0 then 
            task.state = "COMPLETED"
        end
        -- NPCEntity.UpdateTask(bandit, task)

    elseif task.state == "COMPLETED" then

        if Bridge.CanPlayTaskSound(bandit, task) then
            Bridge.PlayTaskSound(bandit, task.sound)
        end
        
        if task.endurance then
            NPCEntity.UpdateEndurance(bandit, task.endurance)
        end

        local ok, done = Bridge.CallTaskAction(action, "onComplete", bandit, task)
        if not ok then
            Bridge.RemoveBadTask(bandit, done, task)
            return
        end

        if done then 
            NPCEntity.RemoveTask(bandit)
        end
    end
end

function Bridge.ManageSocialDistance(bandit)
    if not bandit then return false end
    local brain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(bandit) or nil
    if not (brain and brain.program and brain.program.name == "Companion") then return false end
    if not (NPCPlayerClient and NPCPlayerClient.GetPlayers and NPCUtils and NPCEntity and NPCEntity.SetProgram and NPCEntity.GetProgram) then return false end

    local players = NPCPlayerClient.GetPlayers()
    if not players then return false end

    local bx = bandit.getX and bandit:getX() or 0
    local by = bandit.getY and bandit:getY() or 0
    local bz = bandit.getZ and bandit:getZ() or 0
    local state = bandit.getActionStateName and bandit:getActionStateName() or nil

    for i = 0, players:size() - 1 do
        local player = players:get(i)
        if player then
            local px = player.getX and player:getX() or bx
            local py = player.getY and player:getY() or by
            local pz = player.getZ and player:getZ() or bz
            local inVehicle = player.getVehicle and player:getVehicle() or nil
            local dx, dy = bx - px, by - py
            if bz == pz and dx * dx + dy * dy < 9 and not inVehicle and state ~= "onground" then
                local closestZombie = NPCUtils.GetClosestZombieLocationFast and NPCUtils.GetClosestZombieLocationFast(player) or {dist=9999}
                local closestNPC = NPCUtils.GetClosestNPCLocationFast and NPCUtils.GetClosestNPCLocationFast(player) or {dist=9999}
                if (tonumber(closestZombie.dist) or 9999) > 10 and (tonumber(closestNPC.dist) or 9999) > 10 then
                    local program = NPCEntity.GetProgram(bandit)
                    if not program or program.name ~= "CompanionGuard" then
                        NPCEntity.SetProgram(bandit, "CompanionGuard", {})
                        return true
                    end
                end
            end
        end
    end
    return false
end

function Bridge.CanZombiePathToNPC(zombie, enemy, cooldownMs, sameTargetCooldownMs)
    if not (zombie and enemy and enemy.x and enemy.y) then return false end
    if not zombie.getModData then return false end

    local md = zombie:getModData()
    if not md then return false end

    local now = Bridge.NowMs()
    cooldownMs = tonumber(cooldownMs) or 1800
    sameTargetCooldownMs = tonumber(sameTargetCooldownMs) or 3600

    local z = enemy.z or (zombie.getZ and zombie:getZ()) or 0
    local key = tostring(enemy.id or "") .. ":" .. tostring(math.floor(enemy.x)) .. ":" .. tostring(math.floor(enemy.y)) .. ":" .. tostring(math.floor(z or 0))
    local lastAt = tonumber(md[NPC_LEGACY_KEYS.ZOMBIE_PATH_AT])
    local elapsed = lastAt and (now - lastAt) or nil

    if elapsed then
        if elapsed < cooldownMs then return false end
        if md[NPC_LEGACY_KEYS.ZOMBIE_PATH_KEY] == key and elapsed < sameTargetCooldownMs then return false end
    end

    if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.AllowPathRequest then
        local zid = key
        if NPCUtils and NPCUtils.GetZombieID then
            local okId, retId = pcall(function() return NPCUtils.GetZombieID(zombie) end)
            if okId and retId ~= nil then zid = retId end
        end
        if not NPCWorkSchedulerBridge.AllowPathRequest(zid, "zombie_bandit", "zombie") then
            md[NPC_LEGACY_KEYS.ZOMBIE_PATH_DENIED_AT] = now
            return false
        end
    end

    md[NPC_LEGACY_KEYS.ZOMBIE_PATH_AT] = now
    md[NPC_LEGACY_KEYS.ZOMBIE_PATH_KEY] = key
    return true
end

function Bridge.PathZombieToNPC(zombie, enemy, cooldownMs, sameTargetCooldownMs)
    if not Bridge.CanZombiePathToNPC(zombie, enemy, cooldownMs, sameTargetCooldownMs) then return false end
    if not (zombie and zombie.pathToLocationF and enemy and enemy.x and enemy.y) then return false end

    local ok = pcall(function()
        zombie:pathToLocationF(enemy.x + 0.5, enemy.y + 0.5, enemy.z or zombie:getZ())
    end)
    return ok == true
end

function Bridge.IsZombieDamageToNPCEnabled()
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        return NPCLegacySettingsBridge.GetBool("Health_ZombieDamageToNPC", true)
    end
    local vars = SandboxVars and SandboxVars[NPC_UPDATE_LEGACY_EXT_SANDBOX] or nil
    if vars and vars.Health_ZombieDamageToNPC ~= nil then
        return vars.Health_ZombieDamageToNPC == true
    end
    return true
end

function Bridge.ApplyZombieBiteDamageToNPC(zombie, bandit, attackingZombiesNumber)
    if not Bridge.IsZombieDamageToNPCEnabled() then return false end
    if not (zombie and bandit and bandit.getHealth and bandit.setHealth and bandit.isAlive and bandit:isAlive()) then return false end
    if NPCUtils and NPCUtils.IsController and not NPCUtils.IsController(bandit) then return false end

    local brain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(bandit) or nil
    if Bridge.IsBlackMarketNoCombatBrain(brain) then return false end

    local now = Bridge.NowMs()
    local zmd = zombie.getModData and zombie:getModData() or nil
    if zmd and zmd[NPC_LEGACY_KEYS.ZOMBIE_DAMAGE_AT] and now - zmd[NPC_LEGACY_KEYS.ZOMBIE_DAMAGE_AT] < 1150 then return false end
    if zmd then zmd[NPC_LEGACY_KEYS.ZOMBIE_DAMAGE_AT] = now end

    local maxHealth = tonumber(brain and brain.maxHealth) or tonumber(brain and brain.health) or 3.0
    if NPCHealthRegenBridge and NPCHealthRegenBridge.ResolveMaxHealth then
        local okHealth, resolved = pcall(function() return NPCHealthRegenBridge.ResolveMaxHealth(brain) end)
        if okHealth and tonumber(resolved) then maxHealth = tonumber(resolved) end
    end

    local health = tonumber(bandit:getHealth()) or tonumber(brain and brain.health) or maxHealth
    local attackers = tonumber(attackingZombiesNumber) or 1
    if attackers < 1 then attackers = 1 end
    if attackers > 3 then attackers = 3 end

    local damage = math.max(0.08, maxHealth * 0.035) + (attackers - 1) * 0.025
    if zombie.isBehind and zombie:isBehind(bandit) then damage = damage * 1.2 end

    local newHealth = health - damage
    if brain then
        brain.health = newHealth
        brain.regen = brain.regen or {}
        brain.regen.lastHealth = newHealth
        brain.regen.lastDamageAt = now
        brain.regen.nextRegenAt = now + ((NPCHealthRegenBridge and NPCHealthRegenBridge.RegenDelayMs) or 5500)
        brain.regen.lastRegenAt = now
    end

    if bandit.setAttackedBy then bandit:setAttackedBy(zombie) end
    if NPCUtilityAIBridge and NPCUtilityAIBridge.MarkDamaged then
        pcall(function() NPCUtilityAIBridge.MarkDamaged(bandit, zombie) end)
    end

    if bridgeLegacySandboxBool("General_Infection", true) and NPCEntity and NPCEntity.UpdateInfection and ZombRand and ZombRand(8) == 0 then
        NPCEntity.UpdateInfection(bandit, 8)
    end

    if newHealth <= 0 then
        bandit:setHealth(0)
        pcall(function()
            local cell = getCell and getCell() or nil
            local fake = cell and cell.getFakeZombieForHit and cell:getFakeZombieForHit() or nil
            bandit:Kill(fake, true)
        end)
    else
        bandit:setHealth(newHealth)
        if NPCHealthRegenBridge and NPCHealthRegenBridge.MarkDamaged then
            pcall(function() NPCHealthRegenBridge.MarkDamaged(bandit) end)
        end
        if NPCEntity and NPCEntity.ClearTasks then NPCEntity.ClearTasks(bandit) end
        if NPCEntity and NPCEntity.Say then NPCEntity.Say(bandit, "HIT", true) end
    end

    return true
end


-- manages zombie behavior towards NPCs
function Bridge.UpdateZombies(zombie)

    zombie:setVariable("NoLungeAttack", true)
    
    if zombie:getVariableBoolean(NPC_LEGACY_KEYS.FLAG) then return end
    if Bridge.HasPersistentNPCStamp(zombie, NPCBrainData.Get(zombie)) and not Bridge.IsFormerNPCZombie(zombie) then return end

    -- A demoted/removed NPC can briefly remain as a normal zombie with old hand models.
    -- Clear this before prone-state early returns so armed zombie residues cannot keep
    -- stale NPC weapons or confuse damage routing.
    local primaryResidue = zombie:getPrimaryHandItem()
    local secondaryResidue = zombie:getSecondaryHandItem()
    local banditPrimary = zombie:getVariableString(NPC_LEGACY_KEYS.PRIMARY)
    local banditSecondary = zombie:getVariableString(NPC_LEGACY_KEYS.SECONDARY)
    if primaryResidue or secondaryResidue or (banditPrimary and banditPrimary ~= "") or (banditSecondary and banditSecondary ~= "") then
        NPCCompatibilityBridge.SafeSetPrimaryHandItem(zombie, nil)
        NPCCompatibilityBridge.SafeSetSecondaryHandItem(zombie, nil)
        zombie:setVariable(NPC_LEGACY_KEYS.PRIMARY, "")
        zombie:setVariable(NPC_LEGACY_KEYS.SECONDARY, "")
        zombie:resetEquippedHandsModels()
        zombie:clearAttachedItems()
    end

    -- Recycle stale NPC brain before any prone/ground early-return.
    -- Otherwise a demoted former NPC can look like a normal zombie, but still
    -- be routed through old faction/brain damage checks and become unkillable.
    NPCBrainData.Remove(zombie)
    if zombie:isUseless() then
        zombie:setUseless(false)
    end

    if zombie:isProne() then return end

    local asn = zombie:getActionStateName()
    if asn == "bumped" or asn == "onground" or asn == "climbfence" or asn == "getup" then
        return
    end

    -- Handle zombie target and teeth state
    local target = zombie:getTarget()
    if target and instanceof(target, "IsoZombie") then
        zombie:setVariable("ZombieBiteDone", true)
        zombie:setNoTeeth(true)
    else
        zombie:setNoTeeth(false)
    end

    -- Clear invalid target
    if target and (not target:isAlive() or not zombie:CanSee(target)) then
        zombie:setTarget(nil)
    end

    -- Stop sound if playing
    local emitter = zombie:getEmitter()
    if emitter:isPlaying("ChainsawIdle") then
        emitter:stopSoundByName("ChainsawIdle")
    end

    -- Fetch zombie coordinates and closest bandit location. The spatial index keeps
    -- zombie targeting from becoming O(zombies * bandits) in large fights.
    local zx, zy, zz = zombie:getX(), zombie:getY(), zombie:getZ()
    local enemy
    if NPCSpatialIndexBridge and NPCSpatialIndexBridge.GetClosestNPCLocation then
        enemy = NPCSpatialIndexBridge.GetClosestNPCLocation(zombie, 30)
    else
        enemy = NPCUtils.GetClosestNPCLocationFast(zombie)
    end

    if enemy and enemy.id and NPCZombieCacheBridge and NPCZombieCacheBridge.Cache then
        local enemyNPC = NPCZombieCacheBridge.Cache[enemy.id]
        if enemyNPC and NPCBlackMarketBridge and NPCBlackMarketBridge.IsNoCombatCharacter and NPCBlackMarketBridge.IsNoCombatCharacter(enemyNPC) then return end
    end

    -- If bandit is in range, proceed
    if enemy and enemy.dist and enemy.dist < 30 then
        local player = NPCUtils.GetClosestPlayerLocation(zombie, true)
        
        -- Skip if player is closer than the bandit
        if player.dist < enemy.dist then return end

        local bandit = NPCZombieCacheBridge.Cache[enemy.id]
        if not bandit or not bandit:isAlive() then return end

        -- Standard movement if bandit is far.
        -- In MP/PZ41 pathToCharacter() on a bandit-zombie can spam
        -- NetworkZombieMind.set: goal character is not set. Use a location goal
        -- instead; close combat still assigns target below.
        if enemy.dist > 6 then
            if zombie:CanSee(bandit) then
                Bridge.PathZombieToNPC(zombie, enemy, 1600, 3600)
            end

        -- Approach bandit if in range
        elseif enemy.dist >= 0.59 then
            local player = getPlayer()
            if player and zombie:CanSee(bandit) and zombie:CanSee(player) then
                if NPCCompatibilityBridge.GetGameVersion() >= 42 then
                    Bridge.PathZombieToNPC(zombie, enemy, 900, 1800)
                end
                zombie:spotted(player, true)
                zombie:setTarget(bandit)
                zombie:setAttackedBy(bandit)
            end

        -- Bite range attack
        elseif enemy.dist < 0.59 and enemy.z == zz then
            local isWallTo = zombie:getSquare():isSomethingTo(bandit:getSquare())
            if not isWallTo then
                if zombie:isFacingObject(bandit, 0.3) then
                    -- Optimized close-range attack logic. Query only the bucket around
                    -- the target bandit instead of walking every cached zombie.
                    local attackingZombiesNumber = 0
                    local attackingZombieList, attackingZombieCount = Bridge.GetNearbyZombiesInto("attackingZombies", enemy.x, enemy.y, enemy.z or zz, 1.2)
                    if attackingZombieList then
                        for i = 1, attackingZombieCount do
                            local attackingZombie = attackingZombieList[i]
                            if attackingZombie and math.abs(attackingZombie.x - enemy.x) + math.abs(attackingZombie.y - enemy.y) < 1 then
                                local dx = attackingZombie.x - enemy.x
                                local dy = attackingZombie.y - enemy.y
                                if dx * dx + dy * dy < 0.36 then
                                    attackingZombiesNumber = attackingZombiesNumber + 1
                                    if attackingZombiesNumber > 2 then break end
                                end
                            end
                        end
                    else
                        for id, attackingZombie in pairs(NPCZombieCacheBridge.CacheLightZ) do
                            if math.abs(attackingZombie.x - enemy.x) + math.abs(attackingZombie.y - enemy.y) < 1 then
                                local dx = attackingZombie.x - enemy.x
                                local dy = attackingZombie.y - enemy.y
                                if dx * dx + dy * dy < 0.36 then
                                    attackingZombiesNumber = attackingZombiesNumber + 1
                                    if attackingZombiesNumber > 2 then break end
                                end
                            end
                        end
                    end

                    -- Zombies use a custom NPC damage path here. Vanilla bite damage is
                    -- suppressed by NoTeeth/NoLungeAttack above to avoid moodle/bodydamage
                    -- crashes on bandit-zombie actors, so enabled server settings must remove
                    -- NPC HP manually.
                    zombie:setBumpType("Bite")
                    if ZombRand(4) == 1 then
                        bandit:playSound("ZombieScratch")
                    else
                        bandit:playSound("ZombieBite")
                    end

                    local teeth = NPCCompatibilityBridge.InstanceItem("Base.RollingPin")
                    NPCCompatibilityBridge.Splash(bandit, teeth, zombie)
                    Bridge.ApplyZombieBiteDamageToNPC(zombie, bandit, attackingZombiesNumber)
                    bandit:setHitFromBehind(zombie:isBehind(bandit))

                    if instanceof(bandit, "IsoZombie") then
                        bandit:setHitAngle(zombie:getForwardDirection())
                        bandit:setPlayerAttackPosition(bandit:testDotSide(zombie))
                    end

                    zombie:setVariable("ZombieBiteDone", true)
                    zombie:setNoTeeth(true)
                else
                    zombie:faceThisObject(bandit)
                end
            end
        end
    end
end


-- generates NPC tasks
function Bridge.GenerateTask(bandit, uTick)
    local tasks = {}
    local brain = NPCBrainData.Get(bandit)
    local id = brain and (brain.id or brain.uid or brain.persistentId) or NPCUtils.GetZombieID(bandit)

    if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.AllowAI and not NPCWorkSchedulerBridge.AllowAI(id, brain, uTick) then
        return
    end

    if Bridge.IsBlackMarketNoCombatBrain(brain) then
        local program = NPCEntity.GetProgram(bandit)
        if program and program.name and program.stage and not NPCEntity.HasTask(bandit) then
            local programGroup = ZombiePrograms and ZombiePrograms[program.name] or nil
            local programFn = programGroup and programGroup[program.stage] or nil
            local ok, res = false, nil
            if type(programFn) == "function" then ok, res = pcall(function() return programFn(bandit) end) end
            if ok and res and res.status and res.next then
                NPCEntity.SetProgramStage(bandit, res.next)
                if type(res.tasks) == "table" then
                    for _, task in pairs(res.tasks) do table.insert(tasks, task) end
                end
            elseif not ok then
                Bridge.LogTaskError("program:" .. tostring(program and program.name) .. ":" .. tostring(program and program.stage), "ZombieProgram failed or missing: " .. tostring(program and program.name) .. "." .. tostring(program and program.stage) .. " / " .. tostring(res))
            end
        end
        if #tasks > 0 then
            brain.tasks = brain.tasks or {}
            for _, task in pairs(tasks) do if task and task.action then table.insert(brain.tasks, task) end end
        end
        return
    end

    if brain and NPCUtilityAIBridge and NPCUtilityAIBridge.Update and (not NPCWorkSchedulerBridge or not NPCWorkSchedulerBridge.AllowUtility or NPCWorkSchedulerBridge.AllowUtility(id, brain, uTick)) then
        Bridge.UpdateUtilityAIOnce(bandit, brain, uTick)
    end
    
    -- MANAGE NPC ENDURANCE LOSS
    local enduranceTasks = Bridge.ManageEndurance(bandit)
    if #enduranceTasks > 0 then
        for _, t in pairs(enduranceTasks) do table.insert(tasks, t) end
    end
    
    -- MANAGE BLEEDING AND HEALING
    if #tasks == 0 then
        local healingTasks = Bridge.ManageHealth(bandit)
        if #healingTasks > 0 then
            for _, t in pairs(healingTasks) do table.insert(tasks, t) end
        end
    end

    -- AVOIDANCE
    if #tasks == 0 and uTick % 4 == 0 then
        local avoidanceTasks = Bridge.ManagePreservation(bandit)
        if #avoidanceTasks > 0 then
            for _, t in pairs(avoidanceTasks) do table.insert(tasks, t) end
        end
    end

    -- MANAGE MELEE / SHOOTING TASKS
    if #tasks == 0  then
        local asyncQueued = false
        if NPCAsyncSchedulerBridge and NPCAsyncSchedulerBridge.EnqueueCombatScan then
            local okAsync, retAsync = pcall(function()
                return NPCAsyncSchedulerBridge.EnqueueCombatScan(bandit, brain, id, uTick, function()
                    return Bridge.ManageCombat(bandit, uTick)
                end)
            end)
            asyncQueued = okAsync and retAsync == true
        end

        if not asyncQueued then
            local ok, combatTasks = pcall(function() return Bridge.ManageCombat(bandit, uTick) end)
            if ok and combatTasks and #combatTasks > 0 then
                for _, t in pairs(combatTasks) do table.insert(tasks, t) end
            elseif not ok then
                Bridge.LogTaskError("combat:" .. tostring(id), "ManageCombat failed: " .. tostring(combatTasks))
            end
        end
    end

    -- MANAGE COLLISION TASKS
    if #tasks == 0  and uTick % 2 == 0 then
        local ok, colissionTasks = pcall(function() return Bridge.ManageCollisions(bandit) end)
        if ok and colissionTasks and #colissionTasks > 0 then
            for _, t in pairs(colissionTasks) do table.insert(tasks, t) end
        elseif not ok then
            Bridge.LogTaskError("collision:" .. tostring(id), "ManageCollisions failed: " .. tostring(colissionTasks))
        end
    end
    

    local activeProgram = NPCEntity.GetProgram(bandit)

    -- HIGH-LEVEL SAFE TACTICS
    -- The director may only add non-combat movement/recovery tasks when the
    -- legacy combat/health/preservation managers produced no task and no legacy
    -- program is ready. This keeps normal NPC/Companion programs responsive
    -- instead of inserting idle/patrol tasks before their own logic runs.
    if #tasks == 0 and (not activeProgram or not activeProgram.name or not activeProgram.stage) and NPCBrainDirector and NPCBrainDirector.PlanSafeTask then
        local directorTasks = NPCBrainDirector.PlanSafeTask(bandit, uTick)
        if directorTasks and #directorTasks > 0 then
            for _, t in pairs(directorTasks) do table.insert(tasks, t) end
        end
    end

    -- CUSTOM PROGRAM 
    if #tasks == 0 and not NPCEntity.HasTask(bandit) then
        local program = activeProgram or NPCEntity.GetProgram(bandit)
        if program and program.name and program.stage  then
            -- local ts = getTimestampMs()
            local programGroup = ZombiePrograms and ZombiePrograms[program.name] or nil
            local programFn = programGroup and programGroup[program.stage] or nil
            local ok, res = false, nil
            if type(programFn) == "function" then
                ok, res = pcall(function() return programFn(bandit) end)
            end
            -- print ("AT: " .. program.name .. "." .. program.stage .. " " .. (getTimestampMs() - ts))
            if ok and res and res.status and res.next then
                NPCEntity.SetProgramStage(bandit, res.next)
                if type(res.tasks) == "table" then
                    for _, task in pairs(res.tasks) do
                        table.insert(tasks, task)
                    end
                end
            else
                if not ok then
                    Bridge.LogTaskError("program:" .. tostring(program.name) .. ":" .. tostring(program.stage), "ZombieProgram failed or missing: " .. tostring(program.name) .. "." .. tostring(program.stage) .. " / " .. tostring(res))
                end
                local task = {action="Time", anim="Shrug", time=200}
                table.insert(tasks, task)
            end
        end
    end

    if NPCBrainDirector and NPCBrainDirector.Observe then
        NPCBrainDirector.Observe(bandit, uTick, tasks)
    end


    if #tasks > 0 and NPCMovementStabilityBridge and NPCMovementStabilityBridge.IsCombatLocked then
        local currentTask = NPCEntity.GetTask(bandit)
        local newTask = tasks[1]
        if currentTask and newTask and (currentTask.action == "Move" or currentTask.action == "GoTo") and (newTask.action == "Move" or newTask.action == "GoTo") then
            if not NPCMovementStabilityBridge.CheckProgress(bandit, currentTask) then
                tasks = {}
            end
        end
    end

    if #tasks > 0 then
        local brain = NPCBrainData.Get(bandit)
        if brain and NPCUtilityAIBridge and NPCUtilityAIBridge.OnTasksQueued then
            pcall(function()
                NPCUtilityAIBridge.OnTasksQueued(bandit, brain, tasks)
            end)
        end
        brain.tasks = brain.tasks or {}
        for _, task in pairs(tasks) do
            if task and task.action then
                table.insert(brain.tasks, task)
            end
        end
        -- NPCBrainData.Update(zombie, brain)
    end
end


-- neutral client event dispatchers formerly owned by the legacy update facade
function Bridge.OnNPCUpdate(zombie, uTick)
    uTick = tonumber(uTick) or 0

    local ts = getTimestampMs()
    
    if isServer() then return uTick end

    if not NPCEntity.Engine then return uTick end

    if uTick == 16 then uTick = 0 end
    uTick = uTick + 1

    if NPCCompatibilityBridge.IsReanimatedForGrappleOnly(zombie) then return uTick end

    local id = NPCUtils.GetZombieID(zombie)
    local zx = zombie:getX()
    local zy = zombie:getY()
    local zz = zombie:getZ()

    -- local cell = getCell()
    -- local world = getWorld()
    -- local gamemode = world:getGameMode()
    local brain = NPCBrainData.Get(zombie)
    
    -- INITIALIZE NPC ZOMBIES SPAWNED AND ENQUEUED BY SERVER.
    -- Queue misses must never demote an NPC into a normal zombie: safe-sync can
    -- legally trim Queue entries while the physical NPC is still alive.
    local gmd = GetNPCModData()
    if not zombie:getVariableBoolean(NPC_LEGACY_KEYS.FLAG) then
        local recoveredBrain, keepObject, restored = Bridge.TryRecoverPersistentNPC(zombie, gmd, id, brain)
        brain = recoveredBrain or brain
        if restored then
            -- Recovered from queue/physical runtime metadata; continue through the normal NPC update path.
        elseif keepObject then
            -- Safe-sync is not ready yet. Do not let the vanilla zombie update take over a stamped NPC object.
            return uTick
        elseif Bridge.HasPersistentNPCStamp(zombie, brain) and not Bridge.IsFormerNPCZombie(zombie) then
            Bridge.RemoveNPCRuntimeObject(zombie, "stale_persistent_runtime_after_reconnect")
            return uTick
        end
    end
    if gmd.Queue then
        local queuedBrain = Bridge.GetQueueBrain(gmd, id)
        if queuedBrain then -- and id ~= 0
            if not zombie:getVariableBoolean(NPC_LEGACY_KEYS.FLAG) then
                brain = queuedBrain
                Bridge.MarkAsNPC(zombie, brain)
            end
        else
            if not zombie:getVariableBoolean(NPC_LEGACY_KEYS.FLAG) then
                local blackMarketBrain = Bridge.BlackMarketFallbackBrain(zombie, id)
                if blackMarketBrain then
                    gmd.Queue[id] = blackMarketBrain
                    brain = blackMarketBrain
                    Bridge.MarkAsNPC(zombie, brain)
                end
            end
            if zombie:getVariableBoolean(NPC_LEGACY_KEYS.FLAG) and Bridge.IsClientNPCSyncReady() then
                if Bridge.RuntimeKnownPhysical(gmd, id) or Bridge.IsBlackMarketNoCombatBrain(NPCBrainData.Get(zombie)) then
                    return uTick
                end
                Bridge.RemoveNPCRuntimeObject(zombie, "queue_miss_orphan_cleanup")
                return uTick
            elseif (not zombie:getVariableBoolean(NPC_LEGACY_KEYS.FLAG)) and Bridge.IsFormerNPCZombie(zombie) and Bridge.IsClientNPCSyncReady() then
                Bridge.RemoveNPCRuntimeObject(zombie, "former_npc_zombie_cleanup")
                return uTick
            end
        end
    end
    
    -- if true then return end 
    -- ZOMBIES VS NPCS
    -- Using adaptive performance here.
    -- The more zombies in player's cell, the less frequent updates.
    -- Up to 100 zombies, update every tick, 
    -- 800+ zombies, update every 1/16 tick. 
    -- local zcnt = NPCZombieCacheBridge.GetAllCnt()
    -- if zcnt > 600 then zcnt = 600 end
    -- local skip = math.floor(zcnt / 50) + 1
    if uTick % 2 == 0 and (not NPCWorkSchedulerBridge or not NPCWorkSchedulerBridge.AllowZombieUpdate or NPCWorkSchedulerBridge.AllowZombieUpdate(id, uTick)) then
        -- print (skip)
        Bridge.UpdateZombies(zombie)
    end

    ------------------------------------------------------------------------------------------------------------------------------------
    -- NPC UPDATE AFTER THIS LINE
    ------------------------------------------------------------------------------------------------------------------------------------
    if not zombie:getVariableBoolean(NPC_LEGACY_KEYS.FLAG) then return uTick end
    if not brain then return uTick end
    
    -- distant bandits are not updated by this mod so they need to be set useless
    -- to prevent game updating them as if they were zombies
    local isBlackMarketNPC = Bridge.IsBlackMarketNPC(zombie)
    if NPCZombieCacheBridge.CacheLightB[id] then 
        if not isBlackMarketNPC and zombie.setUseless then pcall(function() zombie:setUseless(false) end) end
    elseif isBlackMarketNPC then
        Bridge.KeepBlackMarketStanding(zombie)
    else
        if zombie.setUseless then pcall(function() zombie:setUseless(true) end) end
        return uTick
    end
    
    local bandit = zombie
    local isNoCombatBrain = Bridge.IsBlackMarketNoCombatBrain(brain)

    -- IF TELEPORTING THEN THERE IS NO SENSE IN PROCEEDING
    if bandit:isTeleporting() then
        return uTick
    end

    -- SOFT PHYSICAL LOD
    -- Far, non-critical physical NPCs are already materialized by the engine, but
    -- they do not need the full AI/visual/task maintenance pass every zombie update.
    -- Critical combat/companion/targeted/locked-task NPCs bypass this gate.
    if not isNoCombatBrain and NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.AllowPhysicalUpdate then
        local allowFrame = true
        local okFrame, retFrame = pcall(function() return NPCWorkSchedulerBridge.AllowPhysicalUpdate(id, brain, bandit, uTick) end)
        if okFrame then allowFrame = retFrame ~= false end
        if not allowFrame then
            NPCEntity.SurpressZombieSounds(bandit)
            return uTick
        end
    end

    -- WALKTYPE
    -- we do it this way, if walktype get overwritten by game engine we force our animations
    zombie:setWalkType(zombie:getVariableString(NPC_LEGACY_KEYS.WALK_TYPE))

    -- NO ZOMBIE SOUNDS
    NPCEntity.SurpressZombieSounds(bandit)

    -- ZOOM-OUT RENDER RELIEF
    if NPCRenderReliefBridge and NPCRenderReliefBridge.ApplyCharacterRelief then
        pcall(function() NPCRenderReliefBridge.ApplyCharacterRelief(bandit, brain, id) end)
    end

    -- CANNIBALS
    if not brain.eatBody then
        bandit:setEatBodyTarget(nil, false)
    end
    
    -- ADJUST HUMAN VISUALS
    if not NPCWorkSchedulerBridge or not NPCWorkSchedulerBridge.AllowVisualUpdate or NPCWorkSchedulerBridge.AllowVisualUpdate(id, brain, uTick) then
        Bridge.ApplyVisuals(bandit, brain)
    end

    -- MANAGE NPC TORCH
    if not NPCWorkSchedulerBridge or not NPCWorkSchedulerBridge.AllowTorchUpdate or NPCWorkSchedulerBridge.AllowTorchUpdate(id, brain, uTick) then
        Bridge.ManageTorch(bandit)
    end

    -- MANAGE NPC CHAINSAW
    Bridge.ManageChainsaw(bandit)

    -- MANAGE NPC BEING ON FIRE
    if uTick == 2 then
        Bridge.ManageOnFire(bandit)
    end

    -- MANAGE NPC SPEECH COOLDOWN
    Bridge.ManageSpeechCooldown(brain)

    -- MANAGE SPY VISIBILITY MARKER
    Bridge.ManageSpyMarker(bandit, brain, uTick)

    -- MANAGE NPC SOUND COOLDOWN
    Bridge.ManageSoundCooldown(brain)

    -- UTILITY AI PROFILE / NEEDS / FIRE-MODE LOCKS
    if NPCUtilityAIBridge and NPCUtilityAIBridge.Update and uTick % 2 == 0 and (not NPCWorkSchedulerBridge or not NPCWorkSchedulerBridge.AllowUtility or NPCWorkSchedulerBridge.AllowUtility(id, brain, uTick)) then
        Bridge.UpdateUtilityAIOnce(bandit, brain, uTick)
    end

    -- CALL-OF-DUTY STYLE HEALTH REGENERATION
    if NPCHealthRegenBridge and NPCHealthRegenBridge.Update and uTick % 2 == 0 then
        NPCHealthRegenBridge.Update(bandit, brain)
    end

    -- ACTION STATE TWEAKS
    local continue = Bridge.ManageActionState(bandit)
    if not continue then return uTick end
    
    -- COMPANION SOCIAL DISTANCE HACK
    Bridge.ManageSocialDistance(bandit)

    if isNoCombatBrain then
        bandit:setHealth(brain.maxHealth or 12.0)
        if bandit.setTarget then pcall(function() bandit:setTarget(nil) end) end
        if bandit.setAttackedBy then pcall(function() bandit:setAttackedBy(nil) end) end
    end

    -- CRAWLERS SCREAM OCASSINALLY
    if bandit:isCrawling() then
        NPCEntity.Say(bandit, "DEAD")
    end
    
    Bridge.GenerateTask(bandit, uTick)

    local task = NPCEntity.GetTask(bandit)
    if task then
        Bridge.ProcessTask(bandit, task)
    end

    local elapsed = getTimestampMs() - ts
    return uTick
end

function Bridge.OnHitZombie(zombie, attacker, bodyPartType, handWeapon)
    if zombie:getVariableBoolean(NPC_LEGACY_KEYS.FLAG) then
        local bandit = zombie
        local brain = NPCBrainData.Get(bandit)

        if Bridge.IsBlackMarketNoCombatBrain(brain) then
            bandit:setHealth(brain.maxHealth or 12.0)
            if bandit.setTarget then pcall(function() bandit:setTarget(nil) end) end
            if bandit.setAttackedBy then pcall(function() bandit:setAttackedBy(nil) end) end
            return
        end

        if NPCHealthRegenBridge and NPCHealthRegenBridge.MarkDamaged then
            NPCHealthRegenBridge.MarkDamaged(bandit)
        end
        if NPCUtilityAIBridge and NPCUtilityAIBridge.MarkDamaged then
            pcall(function()
                NPCUtilityAIBridge.MarkDamaged(bandit, attacker)
            end)
        end

        if NPCFactionBridge and NPCFactionBridge.OnPlayerHitNPC then
            pcall(function()
                NPCFactionBridge.OnPlayerHitNPC(attacker, NPCBrainData.Get(bandit), false)
            end)
        end

        NPCEntity.AddVisualDamage(bandit, handWeapon)
        NPCEntity.ClearTasks(bandit)
        NPCEntity.Say(bandit, "HIT", true)
        if NPCEntity.IsSleeping(bandit) then
            local task = {action="Time", lock=true, anim="GetUp", time=150}
            NPCEntity.ClearTasks(bandit)
            NPCEntity.AddTask(bandit, task)
            NPCEntity.SetSleeping(bandit, false)
            NPCEntity.SetProgramStage(bandit, "Prepare")
        end
   
        if ZombRand(11) == 5 then
            Bridge.CheckFriendlyFire(bandit, attacker)
        end
        
    end
end

function Bridge.OnZombieDead(zombie)

    if not zombie:getVariableBoolean(NPC_LEGACY_KEYS.FLAG) then return end
        
    local bandit = zombie

    -- hostility against civilians (clan=0) is handled by other mods
    local brain = NPCBrainData.Get(bandit)
    if Bridge.IsBlackMarketNoCombatBrain(brain) then
        local player = getPlayer()
        if player and brain then
            sendClientCommand(player, 'NPCBlackMarket', 'NPCDead', {contactId=brain.blackMarketId, runtimeId=brain.id})
        end
        return
    end
    if brain.clan == 0 then return end

    NPCEntity.Say(bandit, "DEAD", true)

    local attacker = bandit:getAttackedBy()
    if NPCFactionBridge and NPCFactionBridge.OnPlayerHitNPC then
        pcall(function()
            NPCFactionBridge.OnPlayerHitNPC(attacker, brain, true)
        end)
    end
    Bridge.CheckFriendlyFire(bandit, attacker)

    local player = getPlayer()
    local killer = bandit:getAttackedBy()
    if killer then
        if killer == player then
            local args = {}
            args.id = 0
            sendClientCommand(player, 'NPCCommands', NPCLegacyContractBridge.Commands.incrementKills, args)
            player:setZombieKills(player:getZombieKills() - 1)
        end
    end

    local brain = NPCBrainData.Get(bandit)

    bandit:setUseless(false)
    bandit:setReanim(false)
    bandit:setVariable(NPC_LEGACY_KEYS.FLAG, false)
    NPCCompatibilityBridge.SafeSetPrimaryHandItem(bandit, nil)
    bandit:clearAttachedItems()
    bandit:resetEquippedHandsModels()
    -- bandit:getInventory():clear()

    local veh = bandit:getVehicle()
    if veh then
        veh:exit(bandit)
    end

    args = {}
    args.id = brain.id
    args.groupId = brain.worldGroupId or brain.groupId
    args.persistentId = brain.persistentId or brain.uid
    sendClientCommand(player, 'NPCCommands', NPCLegacyContractBridge.Commands.remove, args)
    NPCBrainData.Remove(bandit)
end

-- NPCUpdateBridge legacy helper aliases for compatibility with old wrappers/extensions.
local NPC_UPDATE_LEGACY_TOKEN = "Ban" .. "dit"
Bridge["IsClient" .. NPC_UPDATE_LEGACY_TOKEN .. "SyncReady"] = Bridge.IsClientNPCSyncReady
Bridge["Write" .. NPC_UPDATE_LEGACY_TOKEN .. "ServiceIds"] = Bridge.WriteNPCServiceIds
Bridge["IsWorldPersistent" .. NPC_UPDATE_LEGACY_TOKEN] = Bridge.IsWorldPersistentNPC
Bridge["Remove" .. NPC_UPDATE_LEGACY_TOKEN .. "RuntimeObject"] = Bridge.RemoveNPCRuntimeObject
Bridge[NPC_UPDATE_LEGACY_TOKEN .. "ize"] = Bridge.MarkAsNPC
Bridge["IsBlackMarket" .. NPC_UPDATE_LEGACY_TOKEN] = Bridge.IsBlackMarketNPC
Bridge["CanZombiePathTo" .. NPC_UPDATE_LEGACY_TOKEN] = Bridge.CanZombiePathToNPC
Bridge["PathZombieTo" .. NPC_UPDATE_LEGACY_TOKEN] = Bridge.PathZombieToNPC
Bridge["ApplyZombieBiteDamageTo" .. NPC_UPDATE_LEGACY_TOKEN] = Bridge.ApplyZombieBiteDamageToNPC
Bridge["On" .. NPC_UPDATE_LEGACY_TOKEN .. "Update"] = Bridge.OnNPCUpdate

return Bridge
