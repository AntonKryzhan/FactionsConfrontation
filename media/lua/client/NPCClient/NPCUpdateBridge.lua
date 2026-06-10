NPCUpdateBridge = NPCUpdateBridge or {}

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCIdentityReconciliationBridge"
pcall(require, "NPCCore/NPCActionRouterBridge")
pcall(require, "NPCCore/NPCBeliefStateBridge")
pcall(require, "NPCCore/NPCExperienceLedgerBridge")
pcall(require, "NPCCore/NPCAdaptiveLearningBridge")
pcall(require, "NPCCore/NPCInfluenceFieldBridge")

local Bridge = NPCUpdateBridge
local bridge_normMercenaryOrderName
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
    preservationNearby = {},
    attackingZombies = {},
    fallbackCombatCandidates = {ids={}, kinds={}, d2s={}, n=0}
}
Bridge._temp = BRIDGE_TEMP

Bridge.CombatMemoryConfig = Bridge.CombatMemoryConfig or {
    visibleTtlMs = 2600,
    softTtlMs = 6200,
    confidenceDecayMs = 5400,
    minConfidence = 0.22,
    maxMemoryDist = 34,
    faceTaskMs = 22,
    adaptiveBusyMemoryMs = 2800
}

Bridge.SharedSquadSensingConfig = Bridge.SharedSquadSensingConfig or {
    enabled = true,
    visibleTtlMs = 900,
    softTtlMs = 2600,
    maxDist = 34,
    bucketSize = 18,
    stalePruneMs = 9000
}
Bridge.SharedSquadSensing = Bridge.SharedSquadSensing or {}

Bridge.BattleSlotConfig = Bridge.BattleSlotConfig or {
    enabled = true,
    windowMs = 320,
    deniedCooldownMs = 420,
    deniedFaceTaskMs = 18,
    closeEnemyBypassRadius = 4.0,
    supportMeleeSlots = 2,
    reserveMeleeSlots = 1,
    proxyMeleeSlots = 1,
    supportFireSlots = 3,
    reserveFireSlots = 2,
    proxyFireSlots = 1,
    frontlineHighPressureMeleeSlots = 3,
    frontlineHighPressureFireSlots = 5
}
Bridge.BattleAttackSlots = Bridge.BattleAttackSlots or {window=-1, slots={}}

Bridge.CombatLOSCacheConfig = Bridge.CombatLOSCacheConfig or {
    enabled = true,
    positiveTtlMs = 520,
    negativeTtlMs = 260,
    maxMoveDrift = 2.75,
    stalePruneMs = 12000,
    cqbBypassRadius = 8.5,
    indoorBypassRadius = 16.0,
    sameRoomBypassRadius = 22.0
}
Bridge.CombatLOSCache = Bridge.CombatLOSCache or {}

Bridge.ZombieNPCTargetHintConfig = Bridge.ZombieNPCTargetHintConfig or {
    enabled = true,
    visualTtlMs = 420,
    noiseTtlMs = 720,
    maxMoveDrift = 10.0,
    stalePruneMs = 6500
}
Bridge.ZombieNPCTargetHints = Bridge.ZombieNPCTargetHints or {}

Bridge.ZombieNPCBitePressureConfig = Bridge.ZombieNPCBitePressureConfig or {
    enabled = true,
    ttlMs = 220,
    maxMoveDrift = 1.4,
    stalePruneMs = 5000
}
Bridge.ZombieNPCBitePressureCache = Bridge.ZombieNPCBitePressureCache or {}

Bridge.ZombieNPCIntentThrottleConfig = Bridge.ZombieNPCIntentThrottleConfig or {
    enabled = true,
    stalePruneMs = 16000
}
Bridge.ZombieNPCIntentThrottle = Bridge.ZombieNPCIntentThrottle or {}

Bridge.RuntimeCacheCleanupConfig = Bridge.RuntimeCacheCleanupConfig or {
    enabled = true,
    intervalMs = 3500,
    maxChecksPerCache = 96
}
Bridge.RuntimeCacheCleanupState = Bridge.RuntimeCacheCleanupState or {nextAtMs=0, cursors={}}

Bridge.RuntimeOptimizationDiagnosticsConfig = Bridge.RuntimeOptimizationDiagnosticsConfig or {
    enabled = true
}
Bridge.RuntimeOptimizationStats = Bridge.RuntimeOptimizationStats or {}

Bridge.MercenaryOrderDiagnosticsConfig = Bridge.MercenaryOrderDiagnosticsConfig or {
    enabled = true
}
Bridge.MercenaryOrderStats = Bridge.MercenaryOrderStats or {}
Bridge.MercenaryOrderCleanupConfig = Bridge.MercenaryOrderCleanupConfig or {
    enabled = true,
    intervalMs = 4200,
    staleImmediateGraceMs = 8500,
    staleConsumedMs = 90000,
    staleDebugMs = 180000
}
Bridge.MercenaryOrderCleanupState = Bridge.MercenaryOrderCleanupState or {checked=0, removed=0, lastRunAtMs=0}

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
    if NPCRenderReliefBridge and NPCRenderReliefBridge.ShouldSkipOverheadLabels and NPCRenderReliefBridge.ShouldSkipOverheadLabels() then return end
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

function Bridge.GetLOSCacheCharacterId(character)
    if not character then return nil end
    if NPCUtils and NPCUtils.GetCharacterID then
        local ok, id = pcall(function() return NPCUtils.GetCharacterID(character) end)
        if ok and id ~= nil then return id end
    end
    if NPCUtils and NPCUtils.GetZombieID then
        local ok, id = pcall(function() return NPCUtils.GetZombieID(character) end)
        if ok and id ~= nil then return id end
    end
    return tostring(character)
end

function Bridge.GetCharacterSquareSafe(character)
    if not (character and character.getSquare) then return nil end
    local ok, square = pcall(function() return character:getSquare() end)
    if ok then return square end
    return nil
end

function Bridge.GetCharacterRoomSafe(character)
    local square = Bridge.GetCharacterSquareSafe(character)
    if not (square and square.getRoom) then return nil end
    local ok, room = pcall(function() return square:getRoom() end)
    if ok then return room end
    return nil
end

function Bridge.IsCharacterIndoorsSafe(character)
    local square = Bridge.GetCharacterSquareSafe(character)
    if not square then return false end
    if square.isOutside then
        local ok, outside = pcall(function() return square:isOutside() end)
        if ok then return outside ~= true end
    end
    if square.getRoom then
        local ok, room = pcall(function() return square:getRoom() end)
        if ok and room ~= nil then return true end
    end
    if square.getBuilding then
        local ok, building = pcall(function() return square:getBuilding() end)
        if ok and building ~= nil then return true end
    end
    return false
end

function Bridge.ShouldBypassCombatLOSCacheForFidelity(bandit, target)
    if not (bandit and target and bandit.getX and bandit.getY and target.getX and target.getY) then return false end

    if bandit.getZ and target.getZ and math.floor(bandit:getZ()) ~= math.floor(target:getZ()) then return true end

    local cfg = Bridge.CombatLOSCacheConfig or {}
    local dx = bandit:getX() - target:getX()
    local dy = bandit:getY() - target:getY()
    local d2 = dx * dx + dy * dy

    local cqb = tonumber(cfg.cqbBypassRadius) or 8.5
    if d2 <= cqb * cqb then return true end

    local indoor = tonumber(cfg.indoorBypassRadius) or 16.0
    local sameRoom = tonumber(cfg.sameRoomBypassRadius) or 22.0
    local maxBypass = math.max(indoor, sameRoom)
    if d2 > maxBypass * maxBypass then return false end

    local sourceRoom = Bridge.GetCharacterRoomSafe(bandit)
    local targetRoom = Bridge.GetCharacterRoomSafe(target)
    if sourceRoom ~= nil and sourceRoom == targetRoom then
        if d2 <= sameRoom * sameRoom then return true end
    end

    if Bridge.IsCharacterIndoorsSafe(bandit) or Bridge.IsCharacterIndoorsSafe(target) then
        if d2 <= indoor * indoor then return true end
    end

    return false
end

function Bridge.ShouldUseCombatLOSCache(bandit, brain, target, targetKind)
    local cfg = Bridge.CombatLOSCacheConfig or {}
    if cfg.enabled == false then return false end
    if not (bandit and brain and target) then return false end

    local kind = targetKind or Bridge.TargetKind(target)
    if kind == "player" or (instanceof and instanceof(target, "IsoPlayer")) then return false end
    if Bridge.IsPlayerControlledBrain and Bridge.IsPlayerControlledBrain(brain) then return false end
    if Bridge.IsBlackMarketNoCombatBrain and Bridge.IsBlackMarketNoCombatBrain(brain) then return false end
    if not Bridge.IsLiveTarget(target) then return false end
    if Bridge.ShouldBypassCombatLOSCacheForFidelity and Bridge.ShouldBypassCombatLOSCacheForFidelity(bandit, target) then return false end

    local role = Bridge.GetBattleSlotRole and Bridge.GetBattleSlotRole(brain) or ""
    if role == "support" or role == "reserve" or role == "proxy" then return true end

    local level = tonumber(brain.ai and brain.ai.physicalBattleGovernorLevel) or 0
    if role == "frontline" and level >= 2 then return true end

    return false
end

function Bridge.GetCombatLOSCacheKey(bandit, target, targetKind)
    local sid = Bridge.GetLOSCacheCharacterId(bandit)
    local tid = Bridge.GetLOSCacheCharacterId(target)
    if sid == nil or tid == nil then return nil end
    return tostring(sid) .. ":" .. tostring(targetKind or Bridge.TargetKind(target)) .. ":" .. tostring(tid)
end

function Bridge.GetCombatLOSCacheResult(bandit, brain, target, targetKind)
    if not Bridge.ShouldUseCombatLOSCache(bandit, brain, target, targetKind) then return nil end
    local key = Bridge.GetCombatLOSCacheKey(bandit, target, targetKind)
    if not key then return nil end

    local entry = Bridge.CombatLOSCache and Bridge.CombatLOSCache[key] or nil
    if type(entry) ~= "table" then
        Bridge.IncRuntimeOptimizationStat("combat_los_cache_miss_empty")
        return nil
    end

    local now = Bridge.NowMs()
    if (tonumber(entry.untilMs) or 0) < now then
        Bridge.CombatLOSCache[key] = nil
        Bridge.IncRuntimeOptimizationStat("combat_los_cache_miss_expired")
        return nil
    end

    if not (bandit.getX and bandit.getY and target.getX and target.getY) then return nil end
    if bandit.getZ and target.getZ and math.floor(bandit:getZ()) ~= math.floor(target:getZ()) then return nil end

    local bx, by = bandit:getX(), bandit:getY()
    local tx, ty = target:getX(), target:getY()
    local drift = tonumber((Bridge.CombatLOSCacheConfig or {}).maxMoveDrift) or 2.75
    local bdx, bdy = bx - (tonumber(entry.bx) or bx), by - (tonumber(entry.by) or by)
    local tdx, tdy = tx - (tonumber(entry.tx) or tx), ty - (tonumber(entry.ty) or ty)
    if (bdx * bdx + bdy * bdy) > drift * drift or (tdx * tdx + tdy * tdy) > drift * drift then
        Bridge.CombatLOSCache[key] = nil
        Bridge.IncRuntimeOptimizationStat("combat_los_cache_miss_drift")
        return nil
    end

    if entry.result ~= true then
        Bridge.IncRuntimeOptimizationStat("combat_los_cache_hit_negative")
        return false, nil
    end

    local dx, dy = bx - tx, by - ty
    local dist = math.sqrt(dx * dx + dy * dy)
    Bridge.IncRuntimeOptimizationStat("combat_los_cache_hit_positive")
    return true, {target=target, x=tx, y=ty, z=target.getZ and target:getZ() or entry.tz, dist=dist, kind=targetKind or Bridge.TargetKind(target), cachedLOS=true}
end

function Bridge.StoreCombatLOSCacheResult(bandit, brain, target, targetKind, result, detection)
    if not Bridge.ShouldUseCombatLOSCache(bandit, brain, target, targetKind) then return end
    local key = Bridge.GetCombatLOSCacheKey(bandit, target, targetKind)
    if not key then return end
    if not (bandit.getX and bandit.getY and target.getX and target.getY) then return end

    local now = Bridge.NowMs()
    local cfg = Bridge.CombatLOSCacheConfig or {}
    local ttl = result == true and (tonumber(cfg.positiveTtlMs) or 520) or (tonumber(cfg.negativeTtlMs) or 260)
    Bridge.IncRuntimeOptimizationStat(result == true and "combat_los_cache_store_positive" or "combat_los_cache_store_negative")
    Bridge.CombatLOSCache[key] = {
        result = result == true,
        untilMs = now + ttl,
        bx = bandit:getX(),
        by = bandit:getY(),
        bz = bandit.getZ and bandit:getZ() or nil,
        tx = target:getX(),
        ty = target:getY(),
        tz = target.getZ and target:getZ() or nil,
        kind = targetKind or Bridge.TargetKind(target),
        source = brain and (brain.id or brain.uid or brain.persistentId) or nil,
        dist = detection and detection.dist or nil
    }

    if ZombRand and ZombRand(96) == 0 then
        Bridge.PruneCombatLOSCache(now)
    end
end

function Bridge.PruneCombatLOSCache(now)
    now = tonumber(now) or Bridge.NowMs()
    local stale = tonumber((Bridge.CombatLOSCacheConfig or {}).stalePruneMs) or 12000
    for key, entry in pairs(Bridge.CombatLOSCache or {}) do
        if type(entry) ~= "table" or (tonumber(entry.untilMs) or 0) + stale < now then
            Bridge.CombatLOSCache[key] = nil
        end
    end
end

function Bridge.DetectTarget(bandit, target, brain, kind)
    if not (bandit and target) then return false, nil end

    local cached, cachedDetection = Bridge.GetCombatLOSCacheResult(bandit, brain, target, kind)
    if cached ~= nil then return cached == true, cachedDetection end
    Bridge.IncRuntimeOptimizationStat("combat_los_fresh_scan")

    if NPCAIVisionBridge and NPCAIVisionBridge.CanDetect then
        local ok, detected, detection = pcall(function()
            return NPCAIVisionBridge.CanDetect(bandit, target, brain, kind)
        end)
        if ok then
            Bridge.StoreCombatLOSCacheResult(bandit, brain, target, kind, detected == true, detection)
            if detected then return true, detection end
        end
        return false, nil
    end

    local ok, canSee = pcall(function()
        return bandit:CanSee(target)
    end)
    if not ok then return false, nil end

    local dist = nil
    local detection = nil
    if canSee then
        dist = NPCUtils.DistTo(bandit:getX(), bandit:getY(), target:getX(), target:getY())
        detection = {target=target, x=target:getX(), y=target:getY(), z=target:getZ(), dist=dist, kind=kind}
    end
    Bridge.StoreCombatLOSCacheResult(bandit, brain, target, kind, canSee == true, detection)
    if not canSee then return false, nil end

    return true, detection
end

function Bridge.IsLiveTarget(target)
    if not target then return false end
    if target.isAlive then
        local ok, alive = pcall(function() return target:isAlive() end)
        if ok and alive == false then return false end
    end
    if target.isDead then
        local ok, dead = pcall(function() return target:isDead() end)
        if ok and dead == true then return false end
    end
    return true
end

function Bridge.ResolveCombatTarget(targetId, targetKind)
    if targetId == nil then return nil end

    if targetKind == "player" and NPCPlayerClient and NPCPlayerClient.GetPlayerById then
        local okPlayer, player = pcall(function() return NPCPlayerClient.GetPlayerById(targetId) end)
        if okPlayer and player then return player end
    end

    if NPCZombieCacheBridge and NPCZombieCacheBridge.Cache then
        local target = NPCZombieCacheBridge.Cache[targetId] or NPCZombieCacheBridge.Cache[tostring(targetId)]
        if target then return target end
    end

    if NPCPlayerClient and NPCPlayerClient.GetPlayerById then
        local okPlayer, player = pcall(function() return NPCPlayerClient.GetPlayerById(targetId) end)
        if okPlayer and player then return player end
    end

    return nil
end

function Bridge.TargetKind(target)
    if instanceof and instanceof(target, "IsoPlayer") then return "player" end
    if instanceof and instanceof(target, "IsoZombie") then
        if target.getVariableBoolean and target:getVariableBoolean(NPC_LEGACY_KEYS.FLAG) then return "bandit" end
        return "zombie"
    end
    return "bandit"
end


-- Stage 392: mercenary friendly-fire immunity and priority retaliation.
Bridge.MercenaryRetaliationTargets = Bridge.MercenaryRetaliationTargets or {}

function Bridge.GetPlayerRuntimeId(player)
    if not player then return nil end
    if player.getOnlineID then
        local ok, value = pcall(function() return player:getOnlineID() end)
        if ok and value ~= nil then return tostring(value) end
    end
    if player.getUsername then
        local ok, value = pcall(function() return player:getUsername() end)
        if ok and value ~= nil and tostring(value) ~= "" then return tostring(value) end
    end
    if player.getDisplayName then
        local ok, value = pcall(function() return player:getDisplayName() end)
        if ok and value ~= nil and tostring(value) ~= "" then return tostring(value) end
    end
    return nil
end

function Bridge.GetMercenaryOwnerId(brain)
    if type(brain) ~= "table" then return nil end
    return brain.mercenaryHiredBy or brain.master or brain.followPlayer or brain.ownerPlayerId or brain.hiredByPlayerId
end

function Bridge.IsSameMercenaryOwnerBrain(a, b)
    local ao = Bridge.GetMercenaryOwnerId(a)
    local bo = Bridge.GetMercenaryOwnerId(b)
    return ao ~= nil and bo ~= nil and tostring(ao) == tostring(bo)
end

function Bridge.IsMercenaryOwnedByPlayer(brain, player)
    local owner = Bridge.GetMercenaryOwnerId(brain)
    local pid = Bridge.GetPlayerRuntimeId(player)
    return owner ~= nil and pid ~= nil and tostring(owner) == tostring(pid)
end

function Bridge.IsFriendlyMercenaryDamageSource(attacker, victimBrain)
    if type(victimBrain) ~= "table" or Bridge.IsMercenaryFireDisciplineBrain(victimBrain) ~= true then return false end
    if not attacker then return false end

    if instanceof and instanceof(attacker, "IsoPlayer") then
        return Bridge.IsMercenaryOwnedByPlayer(victimBrain, attacker) == true
    end

    if instanceof and instanceof(attacker, "IsoZombie") and attacker.getVariableBoolean and attacker:getVariableBoolean(NPC_LEGACY_KEYS.FLAG) then
        local attackerBrain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(attacker) or nil
        if type(attackerBrain) ~= "table" then return false end
        if attackerBrain.id ~= nil and victimBrain.id ~= nil and tostring(attackerBrain.id) == tostring(victimBrain.id) then return true end
        if Bridge.IsSameMercenaryOwnerBrain(attackerBrain, victimBrain) then return true end
        local ag = attackerBrain.worldGroupId or attackerBrain.groupId or attackerBrain.homeGroupId
        local vg = victimBrain.worldGroupId or victimBrain.groupId or victimBrain.homeGroupId
        if ag ~= nil and vg ~= nil and tostring(ag) == tostring(vg) then return true end
    end

    return false
end

function Bridge.RestoreFriendlyMercenaryHealth(bandit, brain, reason)
    if not (bandit and type(brain) == "table") then return false end
    local maxHealth = tonumber(brain.maxHealth) or tonumber(brain.health) or 12.0
    local desiredHealth = tonumber(brain.health) or maxHealth
    if desiredHealth > maxHealth then desiredHealth = maxHealth end
    local current = bandit.getHealth and tonumber(bandit:getHealth()) or desiredHealth
    if current and current < desiredHealth and bandit.setHealth then
        pcall(function() bandit:setHealth(desiredHealth) end)
    end
    brain.health = desiredHealth
    brain.ai = brain.ai or {}
    brain.ai.lastFriendlyFireIgnoredAtMs = Bridge.NowMs and Bridge.NowMs() or (getTimestampMs and getTimestampMs() or 0)
    brain.ai.lastFriendlyFireIgnoredReason = reason or "friendly_fire"
    if bandit.setAttackedBy then pcall(function() bandit:setAttackedBy(nil) end) end
    if bandit.setTarget then pcall(function() bandit:setTarget(nil) end) end
    return true
end

function Bridge.ResolveMercenaryRetaliationEntry(entry)
    if type(entry) ~= "table" or entry.id == nil then return nil end
    return Bridge.ResolveCombatTarget(entry.id, entry.kind)
end

function Bridge.IsMercenaryRetaliationActive(brain, target)
    if type(brain) ~= "table" then return false end
    local now = Bridge.NowMs and Bridge.NowMs() or (getTimestampMs and getTimestampMs() or 0)
    local owner = Bridge.GetMercenaryOwnerId(brain)
    local entry = brain.ai and brain.ai.mercenaryRetaliationTarget or nil
    if type(entry) ~= "table" and owner ~= nil then
        entry = Bridge.MercenaryRetaliationTargets and Bridge.MercenaryRetaliationTargets[tostring(owner)] or nil
    end
    if type(entry) ~= "table" then return false end
    if entry.untilMs ~= nil and tonumber(entry.untilMs) and tonumber(entry.untilMs) < now then return false end
    local obj = Bridge.ResolveMercenaryRetaliationEntry(entry)
    if not Bridge.IsLiveTarget(obj) then return false end
    if target ~= nil then
        local tid = NPCUtils and NPCUtils.GetCharacterID and NPCUtils.GetCharacterID(target) or Bridge.GetPlayerRuntimeId(target)
        if tid ~= nil and tostring(tid) ~= tostring(entry.id) then return false end
    end
    return true
end

function Bridge.GetMercenaryRetaliationTarget(bandit, brain, maxDist)
    if not (bandit and type(brain) == "table") then return nil end
    local owner = Bridge.GetMercenaryOwnerId(brain)
    if owner == nil then return nil end

    local now = Bridge.NowMs and Bridge.NowMs() or (getTimestampMs and getTimestampMs() or 0)
    local entry = brain.ai and brain.ai.mercenaryRetaliationTarget or nil
    local globalEntry = Bridge.MercenaryRetaliationTargets and Bridge.MercenaryRetaliationTargets[tostring(owner)] or nil
    if type(globalEntry) == "table" and ((tonumber(globalEntry.seenAtMs) or 0) >= (tonumber(entry and entry.seenAtMs) or 0)) then
        entry = globalEntry
    end
    if type(entry) ~= "table" then return nil end
    if entry.untilMs ~= nil and tonumber(entry.untilMs) and tonumber(entry.untilMs) < now then return nil end

    local target = Bridge.ResolveMercenaryRetaliationEntry(entry)
    if not Bridge.IsLiveTarget(target) then
        if Bridge.MercenaryRetaliationTargets then Bridge.MercenaryRetaliationTargets[tostring(owner)] = nil end
        if brain.ai then brain.ai.mercenaryRetaliationTarget = nil end
        return nil
    end
    if Bridge.IsFriendlyMercenaryDamageSource(target, brain) then return nil end
    if target.getZ and bandit.getZ and math.floor(tonumber(target:getZ()) or 0) ~= math.floor(tonumber(bandit:getZ()) or 0) then return nil end
    if not (target.getX and target.getY and bandit.getX and bandit.getY) then return nil end

    local dist = NPCUtils and NPCUtils.DistTo and NPCUtils.DistTo(bandit:getX(), bandit:getY(), target:getX(), target:getY()) or math.sqrt(((bandit:getX() - target:getX()) ^ 2) + ((bandit:getY() - target:getY()) ^ 2))
    local limit = tonumber(maxDist) or 42
    if dist > limit then return nil end

    entry.x = target:getX()
    entry.y = target:getY()
    entry.z = target.getZ and target:getZ() or entry.z
    entry.dist = dist
    if brain.ai then brain.ai.mercenaryRetaliationTarget = entry end
    return target, entry.kind or Bridge.TargetKind(target), dist, true, 1.0, entry
end

-- Stage 393: owner-protection zombie target lane.  Follow already works; this
-- keeps movement untouched and only makes hired mercenaries treat zombies that
-- are actively chasing or biting their owner as immediate shoot-in-place targets.
function Bridge.GetMercenaryOwnerPlayer(bandit, brain)
    if NPCBehaviorBridge and NPCBehaviorBridge.GetMasterPlayer then
        local ok, master = pcall(function() return NPCBehaviorBridge.GetMasterPlayer(bandit) end)
        if ok and master and master.getX then return master end
    end
    local owner = Bridge.GetMercenaryOwnerId(brain)
    if owner ~= nil and NPCPlayerClient and NPCPlayerClient.GetPlayers then
        local okList, list = pcall(function() return NPCPlayerClient.GetPlayers() end)
        if okList and list and list.size then
            for i=0, list:size()-1 do
                local player = list:get(i)
                if player and tostring(Bridge.GetPlayerRuntimeId(player) or "") == tostring(owner) then
                    return player
                end
            end
        end
    end
    if getPlayer then
        local player = getPlayer()
        if player and player.getX then return player end
    end
    return nil
end

function Bridge.IsZombieThreateningMercenaryOwner(zombie, owner, ownerThreatRadius)
    if not (zombie and owner and zombie.getX and zombie.getY and owner.getX and owner.getY) then return false end
    if not Bridge.IsLiveTarget(zombie) then return false end
    if zombie.getVariableBoolean and zombie:getVariableBoolean(NPC_LEGACY_KEYS.FLAG) then return false end
    if zombie.getZ and owner.getZ and math.floor(tonumber(zombie:getZ()) or 0) ~= math.floor(tonumber(owner:getZ()) or 0) then return false end

    local ownerDist = NPCUtils and NPCUtils.DistTo and NPCUtils.DistTo(zombie:getX(), zombie:getY(), owner:getX(), owner:getY()) or math.sqrt(((zombie:getX() - owner:getX()) ^ 2) + ((zombie:getY() - owner:getY()) ^ 2))
    local radius = tonumber(ownerThreatRadius) or 7.5

    local targetIsOwner = false
    if zombie.getTarget then
        local okTarget, target = pcall(function() return zombie:getTarget() end)
        targetIsOwner = okTarget and target == owner
    end

    if targetIsOwner == true then return ownerDist <= radius + 4.0, ownerDist, true end
    if ownerDist <= 2.75 then return true, ownerDist, false end
    if ownerDist <= radius and zombie.isUseless and zombie:isUseless() ~= true then
        -- Fallback for cases where B41 has not exposed getTarget() yet but the
        -- zombie is already in the owner's danger bubble.
        return true, ownerDist, false
    end
    return false, ownerDist, false
end

function Bridge.GetMercenaryOwnerThreatZombie(bandit, brain, maxMercDist)
    if not (bandit and type(brain) == "table" and bandit.getX and bandit.getY) then return nil end
    if not Bridge.IsMercenaryFireDisciplineBrain(brain) then return nil end
    local owner = Bridge.GetMercenaryOwnerPlayer(bandit, brain)
    if not (owner and owner.getX and owner.getY) then return nil end
    if owner.getZ and bandit.getZ and math.floor(tonumber(owner:getZ()) or 0) ~= math.floor(tonumber(bandit:getZ()) or 0) then return nil end

    local cache = NPCZombieCacheBridge and NPCZombieCacheBridge.Cache or nil
    if type(cache) ~= "table" then return nil end

    local limit = tonumber(maxMercDist) or 24.0
    local bestZombie, bestDist, bestOwnerDist, bestScore = nil, nil, nil, -9999
    local ownerThreatRadius = 7.5

    for _, zombie in pairs(cache) do
        if zombie and zombie.getX and zombie.getY and Bridge.IsLiveTarget(zombie) then
            local threatening, ownerDist, directTarget = Bridge.IsZombieThreateningMercenaryOwner(zombie, owner, ownerThreatRadius)
            if threatening == true then
                local mercDist = NPCUtils and NPCUtils.DistTo and NPCUtils.DistTo(bandit:getX(), bandit:getY(), zombie:getX(), zombie:getY()) or math.sqrt(((bandit:getX() - zombie:getX()) ^ 2) + ((bandit:getY() - zombie:getY()) ^ 2))
                if mercDist <= limit then
                    local detected = false
                    local okDetect, retDetect = pcall(function() return Bridge.DetectTarget(bandit, zombie, brain, "zombie") end)
                    detected = okDetect and retDetect == true
                    if detected then
                        local score = (directTarget and 100 or 0) - ((tonumber(ownerDist) or 99) * 3.0) - (mercDist * 0.35)
                        if score > bestScore then
                            bestScore = score
                            bestZombie = zombie
                            bestDist = mercDist
                            bestOwnerDist = ownerDist
                        end
                    end
                end
            end
        end
    end

    if bestZombie then
        brain.ai = brain.ai or {}
        brain.ai.lastOwnerThreatZombieAtMs = Bridge.NowMs and Bridge.NowMs() or (getTimestampMs and getTimestampMs() or 0)
        brain.ai.lastOwnerThreatZombieDist = bestDist
        brain.ai.lastOwnerThreatOwnerDist = bestOwnerDist
        return bestZombie, "zombie", bestDist, bestOwnerDist
    end
    return nil
end

function Bridge.MarkMercenaryRetaliationTarget(victimBandit, victimBrain, attacker, weapon)
    if not (victimBandit and type(victimBrain) == "table" and attacker) then return false end
    if Bridge.IsMercenaryFireDisciplineBrain(victimBrain) ~= true then return false end
    if Bridge.IsFriendlyMercenaryDamageSource(attacker, victimBrain) then return false end
    if not Bridge.IsLiveTarget(attacker) then return false end
    if not (instanceof and (instanceof(attacker, "IsoPlayer") or instanceof(attacker, "IsoZombie"))) then return false end

    local owner = Bridge.GetMercenaryOwnerId(victimBrain)
    if owner == nil then return false end
    local targetKind = Bridge.TargetKind(attacker)
    local targetId = nil
    if targetKind == "player" then
        targetId = Bridge.GetPlayerRuntimeId(attacker)
    end
    if targetId == nil and NPCUtils and NPCUtils.GetCharacterID then
        local ok, got = pcall(function() return NPCUtils.GetCharacterID(attacker) end)
        if ok then targetId = got end
    end
    if targetId == nil then return false end

    local now = Bridge.NowMs and Bridge.NowMs() or (getTimestampMs and getTimestampMs() or 0)
    local ttl = 120000
    local entry = {
        id = targetId,
        kind = targetKind,
        x = attacker.getX and attacker:getX() or nil,
        y = attacker.getY and attacker:getY() or nil,
        z = attacker.getZ and attacker:getZ() or nil,
        seenAtMs = now,
        visibleUntilMs = now + 3500,
        softUntilMs = now + ttl,
        untilMs = now + ttl,
        owner = tostring(owner),
        sourceVictim = victimBrain.id or victimBrain.uid or victimBrain.persistentId,
        reason = "mercenary_under_fire"
    }

    Bridge.MercenaryRetaliationTargets[tostring(owner)] = entry
    local touched = 0
    if NPCZombieCacheBridge and NPCZombieCacheBridge.Cache then
        for _, obj in pairs(NPCZombieCacheBridge.Cache) do
            if obj and obj.getVariableBoolean and obj:getVariableBoolean(NPC_LEGACY_KEYS.FLAG) then
                local b = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(obj) or nil
                if type(b) == "table" and Bridge.IsMercenaryFireDisciplineBrain(b) and tostring(Bridge.GetMercenaryOwnerId(b) or "") == tostring(owner) then
                    b.ai = b.ai or {}
                    b.ai.mercenaryRetaliationTarget = entry
                    b.ai.mercenaryRetaliationFireUntilMs = entry.untilMs
                    b.ai.forceCombatNow = true
                    b.ai.lastGenerateTaskFrameTick = nil
                    if Bridge.UpdateBattlefieldMemory and obj.getX and attacker.getX then
                        local dist = NPCUtils and NPCUtils.DistTo and NPCUtils.DistTo(obj:getX(), obj:getY(), attacker:getX(), attacker:getY()) or nil
                        pcall(function() Bridge.UpdateBattlefieldMemory(obj, b, attacker, targetKind, dist, true) end)
                    end
                    if NPCBrainData and NPCBrainData.Update then pcall(function() NPCBrainData.Update(obj, b) end) end
                    touched = touched + 1
                end
            end
        end
    end
    if touched == 0 then
        victimBrain.ai = victimBrain.ai or {}
        victimBrain.ai.mercenaryRetaliationTarget = entry
        victimBrain.ai.mercenaryRetaliationFireUntilMs = entry.untilMs
    end
    return true
end

function Bridge.GetSharedSquadSensingKey(bandit, brain)
    if not (bandit and bandit.getX and bandit.getY and type(brain) == "table") then return nil end
    if Bridge.IsBlackMarketNoCombatBrain and Bridge.IsBlackMarketNoCombatBrain(brain) then return nil end
    if Bridge.IsPlayerControlledBrain and Bridge.IsPlayerControlledBrain(brain) then return nil end

    local side = brain.side or brain.faction or brain.clan or brain.patrolColor or brain.groupSide or "neutral"
    local groupId = brain.worldGroupId or brain.groupId or brain.squadId or brain.battleGroupId or brain.battleId or brain.enemyGroupId
    if groupId ~= nil then
        return "g:" .. tostring(side) .. ":" .. tostring(groupId)
    end

    local cfg = Bridge.SharedSquadSensingConfig or {}
    local bucketSize = math.max(8, tonumber(cfg.bucketSize) or 18)
    local x = math.floor((tonumber(bandit:getX()) or 0) / bucketSize)
    local y = math.floor((tonumber(bandit:getY()) or 0) / bucketSize)
    local z = math.floor(tonumber(bandit.getZ and bandit:getZ() or 0) or 0)
    return "b:" .. tostring(side) .. ":" .. tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)
end

function Bridge.ShouldUseSharedSquadSensing(brain)
    local cfg = Bridge.SharedSquadSensingConfig or {}
    if cfg.enabled == false or type(brain) ~= "table" then return false end
    if Bridge.IsPlayerControlledBrain and Bridge.IsPlayerControlledBrain(brain) then return false end
    if Bridge.IsBlackMarketNoCombatBrain and Bridge.IsBlackMarketNoCombatBrain(brain) then return false end

    local role = brain.ai and tostring(brain.ai.physicalBattleGovernorRole or "") or ""
    if role == "support" or role == "reserve" or role == "proxy" then return true end
    return false
end

function Bridge.PruneSharedSquadSensing(now)
    local cfg = Bridge.SharedSquadSensingConfig or {}
    local pruneMs = tonumber(cfg.stalePruneMs) or 9000
    local cache = Bridge.SharedSquadSensing
    for key, entry in pairs(cache) do
        if type(entry) ~= "table" or (tonumber(entry.softUntilMs) or 0) + pruneMs < now then
            cache[key] = nil
        end
    end
end

function Bridge.ShareSquadCombatTarget(bandit, brain, target, targetKind, dist)
    if not (bandit and brain and target) then return false end
    local kind = targetKind or Bridge.TargetKind(target)
    if kind == "player" then return false end
    if not Bridge.IsLiveTarget(target) then return false end

    local key = Bridge.GetSharedSquadSensingKey(bandit, brain)
    if not key then return false end

    local targetId = NPCUtils and NPCUtils.GetCharacterID and NPCUtils.GetCharacterID(target) or nil
    if targetId == nil then return false end

    local now = Bridge.NowMs()
    local cfg = Bridge.SharedSquadSensingConfig or {}
    local visibleTtl = tonumber(cfg.visibleTtlMs) or 900
    local softTtl = tonumber(cfg.softTtlMs) or 2600
    Bridge.IncRuntimeOptimizationStat("shared_squad_store")
    Bridge.SharedSquadSensing[key] = {
        id = targetId,
        kind = kind,
        x = target.getX and target:getX() or nil,
        y = target.getY and target:getY() or nil,
        z = target.getZ and target:getZ() or nil,
        dist = dist,
        seenAtMs = now,
        visibleUntilMs = now + visibleTtl,
        softUntilMs = now + softTtl,
        sourceId = brain.id or brain.uid or brain.persistentId
    }

    if ZombRand and ZombRand(64) == 0 then
        Bridge.PruneSharedSquadSensing(now)
    end
    return true
end

function Bridge.GetSharedSquadCombatTarget(bandit, brain, maxDist, requiredId, requiredKind)
    if not Bridge.ShouldUseSharedSquadSensing(brain) then return nil end

    local key = Bridge.GetSharedSquadSensingKey(bandit, brain)
    if not key then return nil end

    local entry = Bridge.SharedSquadSensing and Bridge.SharedSquadSensing[key] or nil
    if type(entry) ~= "table" then
        Bridge.IncRuntimeOptimizationStat("shared_squad_miss_empty")
        return nil
    end

    local now = Bridge.NowMs()
    if (tonumber(entry.softUntilMs) or 0) < now then
        Bridge.SharedSquadSensing[key] = nil
        Bridge.IncRuntimeOptimizationStat("shared_squad_miss_expired")
        return nil
    end
    if requiredId ~= nil and tostring(entry.id) ~= tostring(requiredId) then return nil end
    if requiredKind ~= nil and entry.kind ~= nil and tostring(entry.kind) ~= tostring(requiredKind) then return nil end

    local target = Bridge.ResolveCombatTarget(entry.id, entry.kind)
    if not Bridge.IsLiveTarget(target) then
        Bridge.SharedSquadSensing[key] = nil
        Bridge.IncRuntimeOptimizationStat("shared_squad_miss_invalid")
        return nil
    end
    if target.getZ and bandit.getZ and math.floor(target:getZ()) ~= math.floor(bandit:getZ()) then return nil end

    local tx = target.getX and target:getX() or tonumber(entry.x)
    local ty = target.getY and target:getY() or tonumber(entry.y)
    if not (tx and ty and bandit.getX and bandit.getY) then return nil end

    local dx = bandit:getX() - tx
    local dy = bandit:getY() - ty
    local d2 = dx * dx + dy * dy
    local limit = tonumber(maxDist) or tonumber((Bridge.SharedSquadSensingConfig or {}).maxDist) or 34
    if d2 > limit * limit then return nil end

    local dist = math.sqrt(d2)
    if Bridge.ShouldBypassCombatLOSCacheForFidelity and Bridge.ShouldBypassCombatLOSCacheForFidelity(bandit, target) then return nil end

    entry.x = tx
    entry.y = ty
    entry.z = target.getZ and target:getZ() or entry.z
    entry.dist = dist

    local confidence = (tonumber(entry.visibleUntilMs) or 0) >= now and 0.82 or 0.48
    Bridge.IncRuntimeOptimizationStat("shared_squad_hit")
    return target, entry.kind or Bridge.TargetKind(target), dist, false, confidence, entry
end

function Bridge.GetBattleSlotRole(brain)
    return brain and brain.ai and tostring(brain.ai.physicalBattleGovernorRole or "") or ""
end

function Bridge.ShouldUseBattleAttackSlots(bandit, brain, target, targetKind, dist, mode)
    local cfg = Bridge.BattleSlotConfig or {}
    if cfg.enabled == false then return false end
    if not (bandit and brain and target and mode) then return false end
    if targetKind == "player" or (instanceof and instanceof(target, "IsoPlayer")) then return false end
    if Bridge.IsPlayerControlledBrain and Bridge.IsPlayerControlledBrain(brain) then return false end
    if Bridge.IsBlackMarketNoCombatBrain and Bridge.IsBlackMarketNoCombatBrain(brain) then return false end
    if not Bridge.IsLiveTarget(target) then return false end

    dist = tonumber(dist) or 9999
    if dist <= (tonumber(cfg.closeEnemyBypassRadius) or 4.0) then return false end

    local role = Bridge.GetBattleSlotRole(brain)
    if role == "support" or role == "reserve" or role == "proxy" then return true end

    local level = tonumber(brain.ai and brain.ai.physicalBattleGovernorLevel) or 0
    if role == "frontline" and level >= 2 and dist > 12 then return true end
    return false
end

function Bridge.GetBattleAttackSlotLimit(brain, mode)
    local cfg = Bridge.BattleSlotConfig or {}
    local role = Bridge.GetBattleSlotRole(brain)
    mode = tostring(mode or "melee")

    if role == "proxy" then
        if mode == "fire" then return tonumber(cfg.proxyFireSlots) or 1 end
        return tonumber(cfg.proxyMeleeSlots) or 1
    elseif role == "reserve" then
        if mode == "fire" then return tonumber(cfg.reserveFireSlots) or 2 end
        return tonumber(cfg.reserveMeleeSlots) or 1
    elseif role == "support" then
        if mode == "fire" then return tonumber(cfg.supportFireSlots) or 3 end
        return tonumber(cfg.supportMeleeSlots) or 2
    elseif role == "frontline" then
        if mode == "fire" then return tonumber(cfg.frontlineHighPressureFireSlots) or 5 end
        return tonumber(cfg.frontlineHighPressureMeleeSlots) or 3
    end

    return 9999
end

function Bridge.AcquireBattleAttackSlot(bandit, brain, target, targetKind, mode)
    if not (target and NPCUtils and NPCUtils.GetCharacterID) then return true, "no-target-id" end
    local targetId = NPCUtils.GetCharacterID(target)
    if targetId == nil then return true, "no-target-id" end

    local cfg = Bridge.BattleSlotConfig or {}
    local windowMs = math.max(80, tonumber(cfg.windowMs) or 320)
    local now = Bridge.NowMs()
    local window = math.floor(now / windowMs)
    local state = Bridge.BattleAttackSlots
    if type(state) ~= "table" or state.window ~= window then
        state = {window=window, slots={}}
        Bridge.BattleAttackSlots = state
    end

    local key = tostring(targetKind or Bridge.TargetKind(target)) .. ":" .. tostring(targetId) .. ":" .. tostring(mode or "melee")
    local used = tonumber(state.slots[key]) or 0
    local limit = math.max(1, math.floor(tonumber(Bridge.GetBattleAttackSlotLimit(brain, mode)) or 1))
    if used >= limit then
        Bridge.IncRuntimeOptimizationStat("battle_attack_slot_denied")
        return false, "slot-full", used, limit
    end

    Bridge.IncRuntimeOptimizationStat("battle_attack_slot_granted")
    state.slots[key] = used + 1
    if brain then
        brain.ai = brain.ai or {}
        brain.ai.lastBattleAttackSlotAtMs = now
        brain.ai.lastBattleAttackSlotMode = mode
    end
    return true, "slot-ok", used + 1, limit
end

function Bridge.MakeBattleSlotWaitTask(bandit, brain, enemyCharacter, targetKind, mode)
    if not (bandit and brain and enemyCharacter and enemyCharacter.getX and enemyCharacter.getY) then return nil end
    if NPCEntity and NPCEntity.HasActionTask and NPCEntity.HasActionTask(bandit) then return nil end

    local now = Bridge.NowMs()
    brain.ai = brain.ai or {}
    local cfg = Bridge.BattleSlotConfig or {}
    local cooldown = tonumber(cfg.deniedCooldownMs) or 420
    if (tonumber(brain.ai.lastBattleSlotDeniedAtMs) or 0) + cooldown > now then return nil end
    Bridge.IncRuntimeOptimizationStat("battle_slot_wait_task")
    brain.ai.lastBattleSlotDeniedAtMs = now
    brain.ai.lastBattleSlotDeniedMode = mode

    if bandit.faceThisObject then
        pcall(function() bandit:faceThisObject(enemyCharacter) end)
    end

    return {
        action = "FaceLocation",
        x = enemyCharacter:getX(),
        y = enemyCharacter:getY(),
        z = enemyCharacter:getZ(),
        time = tonumber(cfg.deniedFaceTaskMs) or 18,
        targetId = NPCUtils.GetCharacterID(enemyCharacter),
        targetKind = targetKind or Bridge.TargetKind(enemyCharacter),
        combatMove = true,
        routerPriority = 60,
        director = true,
        directorState = "BattleSlotWait",
        directorReason = "attack slot saturated"
    }
end


function Bridge.GetMeleeStrikeRange(weaponName, fallbackRange)
    local maxRange = tonumber(fallbackRange)
    if (not maxRange or maxRange <= 0) and weaponName and NPCCompatibilityBridge and NPCCompatibilityBridge.InstanceItem then
        local ok, item = pcall(function() return NPCCompatibilityBridge.InstanceItem(weaponName) end)
        if ok and item and item.getMaxRange then maxRange = tonumber(item:getMaxRange()) end
    end

    maxRange = tonumber(maxRange) or 1.1
    if maxRange < 0.70 then return math.max(0.48, maxRange - 0.05) end
    if maxRange < 1.15 then return math.max(0.62, maxRange - 0.18) end
    return math.max(0.78, maxRange - 0.25)
end

function Bridge.GetMeleeApproachRange(weaponName, fallbackRange)
    local strikeRange = Bridge.GetMeleeStrikeRange(weaponName, fallbackRange)
    if strikeRange < 0.70 then return math.max(0.42, strikeRange - 0.08) end
    return math.max(0.55, strikeRange - 0.12)
end

function Bridge.GetMeleeRangeForBrain(brain, weapons)
    if not (brain and weapons and weapons.melee) then return 1.1 end
    brain.ai = brain.ai or {}
    if brain.ai.cachedMeleeName == weapons.melee and brain.ai.cachedMeleeRange then
        return brain.ai.cachedMeleeRange
    end

    local maxRange = 1.1
    local okRange, item = pcall(function() return NPCCompatibilityBridge.InstanceItem(weapons.melee) end)
    if okRange and item and item.getMaxRange then
        maxRange = tonumber(item:getMaxRange()) or maxRange
    end

    brain.ai.cachedMeleeName = weapons.melee
    brain.ai.cachedMeleeRange = maxRange
    return maxRange
end

local function bridge_combatMemoryConfig(name, fallback)
    local cfg = Bridge.CombatMemoryConfig or {}
    return tonumber(cfg[name]) or tonumber(fallback) or 0
end

function Bridge.UpdateBattlefieldMemory(bandit, brain, target, targetKind, dist, detected)
    if not (bandit and brain and target) then return nil end
    local targetId = NPCUtils and NPCUtils.GetCharacterID and NPCUtils.GetCharacterID(target) or nil
    if targetId == nil then return nil end

    local now = Bridge.NowMs()
    local visibleTtl = bridge_combatMemoryConfig("visibleTtlMs", 2600)
    local softTtl = bridge_combatMemoryConfig("softTtlMs", 6200)
    local kind = targetKind or Bridge.TargetKind(target)
    local tx = target.getX and target:getX() or nil
    local ty = target.getY and target:getY() or nil
    local tz = target.getZ and target:getZ() or nil

    brain.ai = brain.ai or {}
    local previous = brain.ai.battlefieldMemory
    local seenCount = 1
    if previous and tostring(previous.id) == tostring(targetId) then
        seenCount = (tonumber(previous.seenCount) or 0) + 1
    end

    local mem = {
        id = targetId,
        kind = kind,
        x = tx,
        y = ty,
        z = tz,
        dist = dist,
        confidence = detected == false and 0.65 or 1.0,
        seenAtMs = now,
        visibleUntilMs = now + visibleTtl,
        softUntilMs = now + softTtl,
        seenCount = seenCount
    }
    brain.ai.battlefieldMemory = mem
    brain.ai.enemyConfidence = mem.confidence
    brain.ai.enemyConfidenceUntilMs = mem.softUntilMs
    brain.ai.lastEnemySeenAtMs = now
    brain.inBattle = true

    if NPCBeliefStateBridge and NPCBeliefStateBridge.UpdateEnemy then
        pcall(function()
            NPCBeliefStateBridge.UpdateEnemy(brain, bandit, target, {
                targetId = targetId,
                kind = kind,
                dist = dist,
                detected = detected ~= false,
                visible = detected ~= false,
                sameFloor = true,
                ttlMs = softTtl
            })
        end)
    end
    if NPCExperienceLedgerBridge and NPCExperienceLedgerBridge.Record then
        pcall(function() NPCExperienceLedgerBridge.Record(brain, bandit, detected == false and "enemy_memory_refresh" or "enemy_seen", {kind=kind, dist=dist}) end)
    end
    if NPCInfluenceFieldBridge and NPCInfluenceFieldBridge.InjectCombatContact then
        local lastInfluence = tonumber(brain.ai.lastInfluenceContactAtMs) or 0
        if now - lastInfluence > 650 then
            brain.ai.lastInfluenceContactAtMs = now
            pcall(function()
                NPCInfluenceFieldBridge.InjectCombatContact(bandit, target, {kind=kind, dist=dist, confidence=detected == false and 0.45 or 1.0, firefight=false})
            end)
        end
    end

    brain.targetId = targetId
    brain.targetKind = kind
    brain.currentThreat = brain.currentThreat or {}
    brain.currentThreat.id = targetId
    brain.currentThreat.kind = kind
    brain.currentThreat.x = tx
    brain.currentThreat.y = ty
    brain.currentThreat.z = tz
    brain.currentThreat.dist = dist
    brain.currentThreat.canSee = detected ~= false
    brain.currentThreat.confidence = mem.confidence
    brain.currentThreat.untilMs = mem.softUntilMs
    return mem
end

function Bridge.DecayBattlefieldMemory(bandit, brain, maxDist)
    if not (bandit and brain and brain.ai and type(brain.ai.battlefieldMemory) == "table") then return nil end
    local mem = brain.ai.battlefieldMemory
    local now = Bridge.NowMs()
    if mem.softUntilMs and now > tonumber(mem.softUntilMs) then
        brain.ai.battlefieldMemory = nil
        brain.ai.enemyConfidence = 0
        return nil
    end

    local target = Bridge.ResolveCombatTarget(mem.id, mem.kind)
    if not Bridge.IsLiveTarget(target) then
        brain.ai.battlefieldMemory = nil
        brain.ai.enemyConfidence = 0
        return nil
    end
    if target.getZ and bandit.getZ and math.floor(target:getZ()) ~= math.floor(bandit:getZ()) then
        brain.ai.battlefieldMemory = nil
        brain.ai.enemyConfidence = 0
        return nil
    end

    local dist = NPCUtils.DistTo(bandit:getX(), bandit:getY(), target:getX(), target:getY())
    if dist > (tonumber(maxDist) or bridge_combatMemoryConfig("maxMemoryDist", 34)) then
        brain.ai.battlefieldMemory = nil
        brain.ai.enemyConfidence = 0
        return nil
    end

    local decay = bridge_combatMemoryConfig("confidenceDecayMs", 5400)
    local age = math.max(0, now - (tonumber(mem.seenAtMs) or now))
    local confidence = 1.0 - (age / math.max(1, decay))
    if confidence < 0 then confidence = 0 end
    if confidence > 1 then confidence = 1 end
    mem.confidence = confidence
    mem.dist = dist
    mem.x = target.getX and target:getX() or mem.x
    mem.y = target.getY and target:getY() or mem.y
    mem.z = target.getZ and target:getZ() or mem.z
    brain.ai.enemyConfidence = confidence
    brain.ai.enemyConfidenceUntilMs = mem.softUntilMs

    if NPCBeliefStateBridge and NPCBeliefStateBridge.UpdateEnemy then
        pcall(function()
            NPCBeliefStateBridge.UpdateEnemy(brain, bandit, target, {
                targetId = mem.id,
                kind = mem.kind,
                dist = dist,
                detected = false,
                memory = true,
                sameFloor = true,
                ttlMs = math.max(500, (tonumber(mem.softUntilMs) or now) - now)
            })
        end)
    end

    if confidence < bridge_combatMemoryConfig("minConfidence", 0.22) then return nil end

    brain.currentThreat = brain.currentThreat or {}
    brain.currentThreat.id = mem.id
    brain.currentThreat.kind = mem.kind
    brain.currentThreat.x = mem.x
    brain.currentThreat.y = mem.y
    brain.currentThreat.z = mem.z
    brain.currentThreat.dist = dist
    brain.currentThreat.canSee = false
    brain.currentThreat.confidence = confidence
    brain.currentThreat.untilMs = mem.softUntilMs
    return target, mem.kind or Bridge.TargetKind(target), dist, false, confidence
end

function Bridge.GetStableCombatTarget(bandit, brain, maxDist)
    if not (bandit and brain and brain.ai and type(brain.ai.stableCombatTarget) == "table") then
        return Bridge.DecayBattlefieldMemory(bandit, brain, maxDist)
    end

    local stable = brain.ai.stableCombatTarget
    local now = Bridge.NowMs()
    local target = Bridge.ResolveCombatTarget(stable.id, stable.kind)
    if not Bridge.IsLiveTarget(target) then return Bridge.DecayBattlefieldMemory(bandit, brain, maxDist) end
    if target.getZ and bandit.getZ and math.floor(target:getZ()) ~= math.floor(bandit:getZ()) then return Bridge.DecayBattlefieldMemory(bandit, brain, maxDist) end

    local dist = NPCUtils.DistTo(bandit:getX(), bandit:getY(), target:getX(), target:getY())
    if dist > (tonumber(maxDist) or 40) then return Bridge.DecayBattlefieldMemory(bandit, brain, maxDist) end

    local sharedTarget, sharedKind, sharedDist, sharedCanSee, sharedConfidence = Bridge.GetSharedSquadCombatTarget(bandit, brain, maxDist, stable.id, stable.kind)
    if sharedTarget then
        local memory = Bridge.UpdateBattlefieldMemory(bandit, brain, sharedTarget, sharedKind, sharedDist, false)
        return sharedTarget, sharedKind, sharedDist, sharedCanSee, tonumber(sharedConfidence) or (memory and memory.confidence) or 0.48
    end

    local detected, detection = Bridge.DetectTarget(bandit, target, brain, stable.kind or Bridge.TargetKind(target))
    if detected then
        dist = detection and detection.dist or dist
        Bridge.UpdateBattlefieldMemory(bandit, brain, target, stable.kind or Bridge.TargetKind(target), dist, true)
        return target, stable.kind or Bridge.TargetKind(target), dist, true, 1.0
    end

    if stable.untilMs and now <= stable.untilMs then
        local memory = Bridge.UpdateBattlefieldMemory(bandit, brain, target, stable.kind or Bridge.TargetKind(target), dist, false)
        if memory and (tonumber(memory.confidence) or 0) >= bridge_combatMemoryConfig("minConfidence", 0.22) then
            return target, memory.kind or Bridge.TargetKind(target), dist, false, memory.confidence
        end
    end

    return Bridge.DecayBattlefieldMemory(bandit, brain, maxDist)
end

function Bridge.RememberStableCombatTarget(bandit, brain, target, targetKind, dist)
    if not (brain and target) then return end
    local targetId = NPCUtils and NPCUtils.GetCharacterID and NPCUtils.GetCharacterID(target) or nil
    if targetId == nil then return end

    brain.ai = brain.ai or {}
    brain.ai.stableCombatTarget = {
        id = targetId,
        kind = targetKind or Bridge.TargetKind(target),
        x = target.getX and target:getX() or nil,
        y = target.getY and target:getY() or nil,
        z = target.getZ and target:getZ() or nil,
        dist = dist,
        untilMs = Bridge.NowMs() + 2200
    }

    Bridge.UpdateBattlefieldMemory(bandit, brain, target, targetKind, dist, true)
    Bridge.ShareSquadCombatTarget(bandit, brain, target, targetKind, dist)
end

function Bridge.HasActiveBattlefieldMemory(brain)
    if not (brain and brain.ai) then return false end
    local now = Bridge.NowMs()
    local confidence = tonumber(brain.ai.enemyConfidence) or 0
    if NPCBeliefStateBridge and NPCBeliefStateBridge.GetEnemyConfidence then
        local ok, beliefConfidence = pcall(function() return NPCBeliefStateBridge.GetEnemyConfidence(brain) end)
        if ok then confidence = math.max(confidence, tonumber(beliefConfidence) or 0) end
    end
    return confidence >= bridge_combatMemoryConfig("minConfidence", 0.22) and (tonumber(brain.ai.enemyConfidenceUntilMs) or 0) > now
end

function Bridge.ShouldRunAdaptiveCombatFrame(bandit, brain, uTick)
    if not brain then return true end
    if Bridge.HasActiveBattlefieldMemory(brain) then return true end
    if Bridge.IsPlayerControlledBrain and Bridge.IsPlayerControlledBrain(brain) then return true end
    if brain.inBattle == true or brain.virtualBattle == true or brain.underFire == true then return true end
    if NPCEntity and NPCEntity.HasActionTask and NPCEntity.HasActionTask(bandit) then return true end

    local perfLevel = Bridge.GetPerfLevel()
    if perfLevel >= 3 then return (tonumber(uTick) or 0) % 4 == 0 end
    if perfLevel >= 2 then return (tonumber(uTick) or 0) % 3 ~= 1 end
    return true
end

function Bridge.MakeRetreatTaskFromTarget(bandit, target, reason, distance, walkType)
    if not (bandit and target and target.getX and target.getY) then return nil end

    local bx, by, bz = bandit:getX(), bandit:getY(), bandit:getZ()
    local dx = bx - target:getX()
    local dy = by - target:getY()
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.05 then
        local angle = ZombRand and (ZombRand(628) / 100.0) or 0
        dx = math.cos(angle)
        dy = math.sin(angle)
        len = 1
    end

    distance = tonumber(distance) or 3.0
    local tx = bx + (dx / len) * distance
    local ty = by + (dy / len) * distance
    local tz = bz

    if NPCMovementStabilityBridge and NPCMovementStabilityBridge.FindFreeAround then
        local ok, square = pcall(function() return NPCMovementStabilityBridge.FindFreeAround(tx, ty, bz, bandit, 3) end)
        if ok and square then
            tx, ty, tz = square:getX(), square:getY(), square:getZ()
        end
    end

    return {
        action = "Move",
        x = tx,
        y = ty,
        z = tz,
        time = 90,
        walkType = walkType or "WalkAim",
        arriveDist = 0.8,
        closeSlow = true,
        combatMove = true,
        pathThrottleMs = 650,
        sameTargetPathThrottleMs = 1600,
        director = true,
        directorState = "KeepDistance",
        directorReason = reason or "combat retreat"
    }
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

function Bridge.IncRuntimeOptimizationStat(name, amount)
    local cfg = Bridge.RuntimeOptimizationDiagnosticsConfig or {}
    if cfg.enabled == false then return end
    name = tostring(name or "unknown")
    local stats = Bridge.RuntimeOptimizationStats or {}
    Bridge.RuntimeOptimizationStats = stats
    stats[name] = (tonumber(stats[name]) or 0) + (tonumber(amount) or 1)
end

function Bridge.CountRuntimeTableLimited(tbl, limit)
    if type(tbl) ~= "table" then return 0 end
    limit = tonumber(limit) or 5000
    local n = 0
    for _ in pairs(tbl) do
        n = n + 1
        if n >= limit then return n end
    end
    return n
end

function Bridge.GetRuntimeOptimizationDiagnostics(reset)
    local out = {
        nowMs = Bridge.NowMs(),
        stats = {},
        cacheSizes = {
            combatLOS = Bridge.CountRuntimeTableLimited(Bridge.CombatLOSCache),
            sharedSquadSensing = Bridge.CountRuntimeTableLimited(Bridge.SharedSquadSensing),
            zombieNPCTargetHints = Bridge.CountRuntimeTableLimited(Bridge.ZombieNPCTargetHints),
            zombieNPCBitePressure = Bridge.CountRuntimeTableLimited(Bridge.ZombieNPCBitePressureCache),
            zombieNPCIntentThrottle = Bridge.CountRuntimeTableLimited(Bridge.ZombieNPCIntentThrottle),
            battleAttackSlots = Bridge.BattleAttackSlots and Bridge.CountRuntimeTableLimited(Bridge.BattleAttackSlots.slots) or 0
        },
        cleanup = {
            lastRunAtMs = Bridge.RuntimeCacheCleanupState and Bridge.RuntimeCacheCleanupState.lastRunAtMs or nil,
            lastChecked = Bridge.RuntimeCacheCleanupState and Bridge.RuntimeCacheCleanupState.lastChecked or nil,
            lastRemoved = Bridge.RuntimeCacheCleanupState and Bridge.RuntimeCacheCleanupState.lastRemoved or nil
        }
    }
    for k, v in pairs(Bridge.RuntimeOptimizationStats or {}) do
        out.stats[k] = v
    end
    if Bridge.GetMercenaryOrderDiagnostics then
        out.mercenaryOrders = Bridge.GetMercenaryOrderDiagnostics(false)
    end
    if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.GetBattleGovernorDiagnostics then
        local ok, schedulerDiag = pcall(function() return NPCWorkSchedulerBridge.GetBattleGovernorDiagnostics(false) end)
        if ok then out.battleGovernor = schedulerDiag end
    end
    if reset == true then
        Bridge.RuntimeOptimizationStats = {}
        if Bridge.GetMercenaryOrderDiagnostics then
            Bridge.GetMercenaryOrderDiagnostics(true)
        end
        if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.GetBattleGovernorDiagnostics then
            pcall(function() NPCWorkSchedulerBridge.GetBattleGovernorDiagnostics(true) end)
        end
    end
    return out
end

function Bridge.PrintRuntimeOptimizationDiagnostics(reset)
    local diag = Bridge.GetRuntimeOptimizationDiagnostics(reset == true)
    print("[NPCUpdateBridge] Runtime optimization diagnostics")
    if diag and diag.cacheSizes then
        print("[NPCUpdateBridge] cacheSizes los=" .. tostring(diag.cacheSizes.combatLOS)
            .. " squad=" .. tostring(diag.cacheSizes.sharedSquadSensing)
            .. " hints=" .. tostring(diag.cacheSizes.zombieNPCTargetHints)
            .. " bite=" .. tostring(diag.cacheSizes.zombieNPCBitePressure)
            .. " intent=" .. tostring(diag.cacheSizes.zombieNPCIntentThrottle)
            .. " slots=" .. tostring(diag.cacheSizes.battleAttackSlots))
    end
    for k, v in pairs((diag and diag.stats) or {}) do
        print("[NPCUpdateBridge] stat " .. tostring(k) .. "=" .. tostring(v))
    end
    return diag
end

function Bridge.IncMercenaryOrderStat(name, amount)
    local cfg = Bridge.MercenaryOrderDiagnosticsConfig or {}
    if cfg.enabled == false then return end
    name = tostring(name or "unknown")
    local stats = Bridge.MercenaryOrderStats or {}
    Bridge.MercenaryOrderStats = stats
    stats[name] = (tonumber(stats[name]) or 0) + (tonumber(amount) or 1)
end

function Bridge.GetMercenaryOrderDiagnostics(reset)
    local out = {
        nowMs = Bridge.NowMs(),
        stats = {},
        cleanup = {
            checked = Bridge.MercenaryOrderCleanupState and Bridge.MercenaryOrderCleanupState.checked or 0,
            removed = Bridge.MercenaryOrderCleanupState and Bridge.MercenaryOrderCleanupState.removed or 0,
            lastRunAtMs = Bridge.MercenaryOrderCleanupState and Bridge.MercenaryOrderCleanupState.lastRunAtMs or 0
        }
    }
    for k, v in pairs(Bridge.MercenaryOrderStats or {}) do
        out.stats[k] = v
    end
    if reset == true then
        Bridge.MercenaryOrderStats = {}
        Bridge.MercenaryOrderCleanupState = {checked=0, removed=0, lastRunAtMs=Bridge.NowMs()}
    end
    return out
end

function Bridge.PrintMercenaryOrderDiagnostics(reset)
    local diag = Bridge.GetMercenaryOrderDiagnostics(reset == true)
    print("[NPCUpdateBridge] Mercenary order diagnostics")
    if diag and diag.cleanup then
        print("[NPCUpdateBridge] orderCleanup checked=" .. tostring(diag.cleanup.checked)
            .. " removed=" .. tostring(diag.cleanup.removed)
            .. " lastRunAtMs=" .. tostring(diag.cleanup.lastRunAtMs))
    end
    for k, v in pairs((diag and diag.stats) or {}) do
        print("[NPCUpdateBridge] orderStat " .. tostring(k) .. "=" .. tostring(v))
    end
    return diag
end

function Bridge.PruneRuntimeCacheStep(cacheName, cache, staleFn, now, maxChecks)
    if type(cache) ~= "table" or type(staleFn) ~= "function" then return 0, 0 end

    local state = Bridge.RuntimeCacheCleanupState or {nextAtMs=0, cursors={}}
    Bridge.RuntimeCacheCleanupState = state
    state.cursors = state.cursors or {}

    local cursor = state.cursors[cacheName]
    local checked = 0
    local removed = 0
    maxChecks = math.max(8, math.floor(tonumber(maxChecks) or 64))

    while checked < maxChecks do
        local ok, key, entry = pcall(next, cache, cursor)
        if not ok then
            cursor = nil
            ok, key, entry = pcall(next, cache, nil)
        end
        if not ok or key == nil then
            cursor = nil
            break
        end

        local okNext, nextKey = pcall(next, cache, key)
        if not okNext then nextKey = nil end

        checked = checked + 1
        local remove = false
        local okStale, stale = pcall(staleFn, entry, now, key)
        if (not okStale) or stale == true then remove = true end
        if remove then
            cache[key] = nil
            removed = removed + 1
        end

        cursor = nextKey
        if cursor == nil then break end
    end

    state.cursors[cacheName] = cursor
    return checked, removed
end

function Bridge.MaybePruneRuntimeCaches(now, force)
    local cfg = Bridge.RuntimeCacheCleanupConfig or {}
    if cfg.enabled == false then return false end

    now = tonumber(now) or Bridge.NowMs()
    local state = Bridge.RuntimeCacheCleanupState or {nextAtMs=0, cursors={}}
    Bridge.RuntimeCacheCleanupState = state
    state.cursors = state.cursors or {}

    local interval = math.max(750, tonumber(cfg.intervalMs) or 3500)
    if force ~= true and (tonumber(state.nextAtMs) or 0) > now then return false end
    state.nextAtMs = now + interval

    local maxChecks = math.max(16, math.floor(tonumber(cfg.maxChecksPerCache) or 96))
    local checked = 0
    local removed = 0
    local c, r

    local losStale = tonumber((Bridge.CombatLOSCacheConfig or {}).stalePruneMs) or 12000
    c, r = Bridge.PruneRuntimeCacheStep("CombatLOSCache", Bridge.CombatLOSCache, function(entry, t)
        return type(entry) ~= "table" or (tonumber(entry.untilMs) or 0) + losStale < t
    end, now, maxChecks)
    checked = checked + c; removed = removed + r

    local squadStale = tonumber((Bridge.SharedSquadSensingConfig or {}).stalePruneMs) or 9000
    c, r = Bridge.PruneRuntimeCacheStep("SharedSquadSensing", Bridge.SharedSquadSensing, function(entry, t)
        return type(entry) ~= "table" or (tonumber(entry.softUntilMs) or 0) + squadStale < t
    end, now, maxChecks)
    checked = checked + c; removed = removed + r

    local hintStale = tonumber((Bridge.ZombieNPCTargetHintConfig or {}).stalePruneMs) or 6500
    c, r = Bridge.PruneRuntimeCacheStep("ZombieNPCTargetHints", Bridge.ZombieNPCTargetHints, function(entry, t)
        return type(entry) ~= "table" or (tonumber(entry.untilMs) or 0) + hintStale < t
    end, now, maxChecks)
    checked = checked + c; removed = removed + r

    local biteStale = tonumber((Bridge.ZombieNPCBitePressureConfig or {}).stalePruneMs) or 5000
    c, r = Bridge.PruneRuntimeCacheStep("ZombieNPCBitePressureCache", Bridge.ZombieNPCBitePressureCache, function(entry, t)
        return type(entry) ~= "table" or (tonumber(entry.untilMs) or 0) + biteStale < t
    end, now, maxChecks)
    checked = checked + c; removed = removed + r

    local intentStale = tonumber((Bridge.ZombieNPCIntentThrottleConfig or {}).stalePruneMs) or 16000
    c, r = Bridge.PruneRuntimeCacheStep("ZombieNPCIntentThrottle", Bridge.ZombieNPCIntentThrottle, function(entry, t)
        return type(entry) ~= "table" or (tonumber(entry.lastSeenMs) or 0) + intentStale < t
    end, now, maxChecks)
    checked = checked + c; removed = removed + r

    local slots = Bridge.BattleAttackSlots
    if type(slots) == "table" then
        local windowMs = tonumber((Bridge.BattleSlotConfig or {}).windowMs) or 320
        local currentWindow = math.floor(now / math.max(80, windowMs))
        if tonumber(slots.window) and tonumber(slots.window) < currentWindow - 3 then
            slots.window = currentWindow
            slots.slots = {}
            removed = removed + 1
        end
    end

    local budget = Bridge._zombieNpcRefreshBudget
    if type(budget) == "table" and tonumber(budget.window) then
        local currentRefreshWindow = math.floor(now / 100)
        if budget.window < currentRefreshWindow - 3 then
            Bridge._zombieNpcRefreshBudget = nil
            removed = removed + 1
        end
    end

    state.lastRunAtMs = now
    state.lastChecked = checked
    state.lastRemoved = removed
    Bridge.IncRuntimeOptimizationStat("runtime_cleanup_runs")
    Bridge.IncRuntimeOptimizationStat("runtime_cleanup_checked", checked)
    Bridge.IncRuntimeOptimizationStat("runtime_cleanup_removed", removed)
    return true
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

function Bridge.GetZombieNPCBool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        return NPCLegacySettingsBridge.GetBool(name, defaultValue == true)
    end
    local vars = SandboxVars and SandboxVars[NPC_UPDATE_LEGACY_EXT_SANDBOX] or nil
    if vars and vars[name] ~= nil then
        local value = vars[name]
        return value == true or value == 1 or value == "true"
    end
    return defaultValue == true
end

function Bridge.GetZombieNPCNumber(name, defaultValue, minValue, maxValue)
    local value
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        value = NPCLegacySettingsBridge.GetNumber(name, defaultValue, minValue, maxValue)
    else
        local vars = SandboxVars and SandboxVars[NPC_UPDATE_LEGACY_EXT_SANDBOX] or nil
        value = tonumber(vars and vars[name]) or tonumber(defaultValue) or 0
        if minValue ~= nil and value < minValue then value = minValue end
        if maxValue ~= nil and value > maxValue then value = maxValue end
    end
    return value
end

function Bridge.IsZombieNPCAggroEnabled()
    return Bridge.GetZombieNPCBool("ZombieNPC_AggroEnabled", true)
end

function Bridge.IsZombieNPCAttackVisualsEnabled()
    return Bridge.GetZombieNPCBool("ZombieNPC_AttackVisualsEnabled", true)
end

function Bridge.AllowZombieNPCTargetRefresh(zombie, key)
    local maxPerWindow = Bridge.GetZombieNPCNumber("ZombieNPC_MaxTargetRefreshPerTick", 10, 1, 80)
    local now = Bridge.NowMs()
    local window = math.floor(now / 100)
    local budget = Bridge._zombieNpcRefreshBudget
    if not budget or budget.window ~= window then
        budget = {window=window, count=0}
        Bridge._zombieNpcRefreshBudget = budget
    end
    if budget.count >= maxPerWindow then return false end
    budget.count = budget.count + 1
    return true
end

function Bridge.GetZombieNPCTargetHintKey(zombie)
    if not zombie then return nil end
    if NPCUtils and NPCUtils.GetZombieID then
        local ok, id = pcall(function() return NPCUtils.GetZombieID(zombie) end)
        if ok and id ~= nil then return tostring(id) end
    end
    return tostring(zombie)
end

function Bridge.PruneZombieNPCTargetHints(now)
    now = tonumber(now) or Bridge.NowMs()
    local cfg = Bridge.ZombieNPCTargetHintConfig or {}
    local stale = tonumber(cfg.stalePruneMs) or 6500
    for key, entry in pairs(Bridge.ZombieNPCTargetHints or {}) do
        if type(entry) ~= "table" or (tonumber(entry.untilMs) or 0) < now - stale then
            Bridge.ZombieNPCTargetHints[key] = nil
        end
    end
end

function Bridge.StoreZombieNPCTargetHint(zombie, enemy, maxRadius)
    local cfg = Bridge.ZombieNPCTargetHintConfig or {}
    if cfg.enabled == false then return end
    if not (zombie and enemy and enemy.id and enemy.x and enemy.y) then return end

    local key = Bridge.GetZombieNPCTargetHintKey(zombie)
    if not key then return end

    local now = Bridge.NowMs()
    local ttl = enemy.noise == true and (tonumber(cfg.noiseTtlMs) or 720) or (tonumber(cfg.visualTtlMs) or 420)
    Bridge.IncRuntimeOptimizationStat(enemy.noise == true and "zombie_npc_target_hint_store_noise" or "zombie_npc_target_hint_store_visual")
    Bridge.ZombieNPCTargetHints[key] = {
        id = enemy.id,
        x = tonumber(enemy.x),
        y = tonumber(enemy.y),
        z = tonumber(enemy.z),
        noise = enemy.noise == true,
        radius = tonumber(maxRadius),
        untilMs = now + math.max(80, ttl),
        zx = zombie.getX and zombie:getX() or nil,
        zy = zombie.getY and zombie:getY() or nil,
        zz = zombie.getZ and zombie:getZ() or nil
    }

    Bridge._zombieNpcHintStores = (tonumber(Bridge._zombieNpcHintStores) or 0) + 1
    if Bridge._zombieNpcHintStores % 96 == 1 then
        Bridge.PruneZombieNPCTargetHints(now)
    end
end

function Bridge.GetZombieNPCTargetHint(zombie, visualRadius, hearingRadius)
    local cfg = Bridge.ZombieNPCTargetHintConfig or {}
    if cfg.enabled == false then return nil end
    if not (zombie and zombie.getX and zombie.getY) then return nil end

    local key = Bridge.GetZombieNPCTargetHintKey(zombie)
    local entry = key and Bridge.ZombieNPCTargetHints and Bridge.ZombieNPCTargetHints[key] or nil
    if type(entry) ~= "table" then
        Bridge.IncRuntimeOptimizationStat("zombie_npc_target_hint_miss_empty")
        return nil
    end

    local now = Bridge.NowMs()
    if (tonumber(entry.untilMs) or 0) < now then
        Bridge.ZombieNPCTargetHints[key] = nil
        Bridge.IncRuntimeOptimizationStat("zombie_npc_target_hint_miss_expired")
        return nil
    end

    local zx, zy = zombie:getX(), zombie:getY()
    local zz = zombie.getZ and zombie:getZ() or tonumber(entry.zz) or 0
    local drift = tonumber(cfg.maxMoveDrift) or 10.0
    local oldZx, oldZy = tonumber(entry.zx), tonumber(entry.zy)
    if oldZx and oldZy then
        local mdx = zx - oldZx
        local mdy = zy - oldZy
        if mdx * mdx + mdy * mdy > drift * drift then
            Bridge.ZombieNPCTargetHints[key] = nil
            Bridge.IncRuntimeOptimizationStat("zombie_npc_target_hint_miss_drift")
            return nil
        end
    end

    local bandit = NPCZombieCacheBridge and NPCZombieCacheBridge.Cache and (NPCZombieCacheBridge.Cache[entry.id] or NPCZombieCacheBridge.Cache[tostring(entry.id)]) or nil
    if not (bandit and bandit.isAlive and bandit:isAlive()) then
        Bridge.ZombieNPCTargetHints[key] = nil
        Bridge.IncRuntimeOptimizationStat("zombie_npc_target_hint_miss_invalid")
        return nil
    end
    if bandit.getZ and math.abs((bandit:getZ() or zz) - zz) > 1 then
        Bridge.ZombieNPCTargetHints[key] = nil
        return nil
    end

    local tx = bandit.getX and bandit:getX() or tonumber(entry.x)
    local ty = bandit.getY and bandit:getY() or tonumber(entry.y)
    local tz = bandit.getZ and bandit:getZ() or tonumber(entry.z) or zz
    if not (tx and ty) then return nil end

    local dx = tx - zx
    local dy = ty - zy
    local d2 = dx * dx + dy * dy
    local radius = entry.noise == true and (tonumber(hearingRadius) or tonumber(entry.radius) or 36) or (tonumber(visualRadius) or tonumber(entry.radius) or 24)
    if d2 > radius * radius then
        Bridge.ZombieNPCTargetHints[key] = nil
        Bridge.IncRuntimeOptimizationStat("zombie_npc_target_hint_miss_radius")
        return nil
    end

    Bridge.IncRuntimeOptimizationStat(entry.noise == true and "zombie_npc_target_hint_hit_noise" or "zombie_npc_target_hint_hit_visual")
    return {id=entry.id, x=tx, y=ty, z=tz, dist=math.sqrt(d2), noise=entry.noise == true, cachedHint=true}
end

function Bridge.GetZombieCurrentNPCTargetEnemy(zombie, maxRadius)
    if not (zombie and zombie.getTarget and zombie.getX and zombie.getY) then return nil end

    local target = zombie:getTarget()
    if not (target and target.getVariableBoolean and target:getVariableBoolean(NPC_LEGACY_KEYS.FLAG)) then return nil end
    if not (target.isAlive and target:isAlive() and target.getX and target.getY) then return nil end
    if NPCBlackMarketBridge and NPCBlackMarketBridge.IsNoCombatCharacter and NPCBlackMarketBridge.IsNoCombatCharacter(target) then return nil end

    local zx, zy = zombie:getX(), zombie:getY()
    local zz = zombie.getZ and zombie:getZ() or 0
    local tx, ty = target:getX(), target:getY()
    local tz = target.getZ and target:getZ() or zz
    if math.abs((tonumber(tz) or zz) - (tonumber(zz) or 0)) > 1 then return nil end

    local dx = tx - zx
    local dy = ty - zy
    local d2 = dx * dx + dy * dy
    local radius = tonumber(maxRadius) or 24
    if d2 > radius * radius then return nil end

    local targetId = nil
    if NPCUtils and NPCUtils.GetZombieID then
        local okId, gotId = pcall(function() return NPCUtils.GetZombieID(target) end)
        if okId and gotId ~= nil then targetId = gotId end
    end
    if targetId == nil then targetId = tostring(target) end

    Bridge.IncRuntimeOptimizationStat("zombie_current_npc_target_hit")
    return {id=targetId, x=tx, y=ty, z=tz, dist=math.sqrt(d2), currentTarget=true, targetObj=target}
end

function Bridge.PruneZombieNPCIntentThrottle(now)
    now = tonumber(now) or Bridge.NowMs()
    local cfg = Bridge.ZombieNPCIntentThrottleConfig or {}
    local stale = tonumber(cfg.stalePruneMs) or 16000
    for key, entry in pairs(Bridge.ZombieNPCIntentThrottle or {}) do
        if type(entry) ~= "table" or (tonumber(entry.lastSeenMs) or 0) < now - stale then
            Bridge.ZombieNPCIntentThrottle[key] = nil
        end
    end
end

function Bridge.GetZombieNPCIntentThrottleState(zombie, create)
    local cfg = Bridge.ZombieNPCIntentThrottleConfig or {}
    if cfg.enabled == false then return nil end
    if not zombie then return nil end

    local key = Bridge.GetZombieNPCTargetHintKey and Bridge.GetZombieNPCTargetHintKey(zombie) or tostring(zombie)
    if not key then return nil end

    local cache = Bridge.ZombieNPCIntentThrottle or {}
    Bridge.ZombieNPCIntentThrottle = cache
    local state = cache[key]
    if type(state) ~= "table" and create == true then
        state = {}
        cache[key] = state
        Bridge.IncRuntimeOptimizationStat("zombie_npc_intent_throttle_created")
    elseif type(state) == "table" then
        Bridge.IncRuntimeOptimizationStat("zombie_npc_intent_throttle_hit")
    end
    if type(state) ~= "table" then return nil end

    local now = Bridge.NowMs()
    state.lastSeenMs = now

    Bridge._zombieNpcIntentThrottleTouches = (tonumber(Bridge._zombieNpcIntentThrottleTouches) or 0) + 1
    if Bridge._zombieNpcIntentThrottleTouches % 128 == 1 then
        Bridge.PruneZombieNPCIntentThrottle(now)
    end

    return state
end

function Bridge.GetZombieNPCBitePressureKey(enemy)
    if enemy and enemy.id ~= nil then return tostring(enemy.id) end
    if enemy and enemy.x and enemy.y then
        return tostring(math.floor(tonumber(enemy.x) or 0)) .. ":" .. tostring(math.floor(tonumber(enemy.y) or 0)) .. ":" .. tostring(math.floor(tonumber(enemy.z) or 0))
    end
    return nil
end

function Bridge.PruneZombieNPCBitePressure(now)
    now = tonumber(now) or Bridge.NowMs()
    local cfg = Bridge.ZombieNPCBitePressureConfig or {}
    local stale = tonumber(cfg.stalePruneMs) or 5000
    for key, entry in pairs(Bridge.ZombieNPCBitePressureCache or {}) do
        if type(entry) ~= "table" or (tonumber(entry.untilMs) or 0) < now - stale then
            Bridge.ZombieNPCBitePressureCache[key] = nil
        end
    end
end

function Bridge.GetZombieNPCBitePressure(enemy)
    local cfg = Bridge.ZombieNPCBitePressureConfig or {}
    local cacheEnabled = cfg.enabled ~= false
    if not (enemy and enemy.x and enemy.y) then return nil end

    local key = Bridge.GetZombieNPCBitePressureKey(enemy)
    if not key then return nil end

    local now = Bridge.NowMs()
    local cache = Bridge.ZombieNPCBitePressureCache or {}
    Bridge.ZombieNPCBitePressureCache = cache
    local ex, ey, ez = tonumber(enemy.x), tonumber(enemy.y), tonumber(enemy.z) or 0
    if not (ex and ey) then return nil end
    local entry = cacheEnabled and cache[key] or nil
    if type(entry) == "table" and (tonumber(entry.untilMs) or 0) >= now then
        local oldX, oldY, oldZ = tonumber(entry.x), tonumber(entry.y), tonumber(entry.z) or 0
        local drift = tonumber(cfg.maxMoveDrift) or 1.4
        if oldX and oldY and ex and ey and math.abs((oldZ or 0) - ez) <= 1 then
            local dx = ex - oldX
            local dy = ey - oldY
            if dx * dx + dy * dy <= drift * drift then
                Bridge.IncRuntimeOptimizationStat("zombie_npc_bite_pressure_cache_hit")
                return tonumber(entry.count) or 0
            end
        end
        cache[key] = nil
    end

    local attackingZombiesNumber = 0
    local attackingZombieList, attackingZombieCount = Bridge.GetNearbyZombiesInto("attackingZombies", ex, ey, ez, 1.2, 16)
    if attackingZombieList then
        for i = 1, attackingZombieCount do
            local attackingZombie = attackingZombieList[i]
            if attackingZombie and math.abs(attackingZombie.x - ex) + math.abs(attackingZombie.y - ey) < 1 then
                local dx = attackingZombie.x - ex
                local dy = attackingZombie.y - ey
                if dx * dx + dy * dy < 0.36 then
                    attackingZombiesNumber = attackingZombiesNumber + 1
                    if attackingZombiesNumber > 2 then break end
                end
            end
        end
    elseif NPCZombieCacheBridge and NPCZombieCacheBridge.CacheLightZ then
        for id, attackingZombie in pairs(NPCZombieCacheBridge.CacheLightZ) do
            if math.abs(attackingZombie.x - ex) + math.abs(attackingZombie.y - ey) < 1 then
                local dx = attackingZombie.x - ex
                local dy = attackingZombie.y - ey
                if dx * dx + dy * dy < 0.36 then
                    attackingZombiesNumber = attackingZombiesNumber + 1
                    if attackingZombiesNumber > 2 then break end
                end
            end
        end
    end

    if cacheEnabled then
        Bridge.IncRuntimeOptimizationStat("zombie_npc_bite_pressure_cache_store")
        cache[key] = {
            count = attackingZombiesNumber,
            x = ex,
            y = ey,
            z = ez,
            untilMs = now + math.max(60, tonumber(cfg.ttlMs) or 220)
        }

        Bridge._zombieNpcBitePressureStores = (tonumber(Bridge._zombieNpcBitePressureStores) or 0) + 1
        if Bridge._zombieNpcBitePressureStores % 96 == 1 then
            Bridge.PruneZombieNPCBitePressure(now)
        end
    end

    return attackingZombiesNumber
end

function Bridge.GetRecentNPCShotMemoryEnemy(zombie, maxRadius)
    if not (zombie and zombie.getX and NPCZombieCacheBridge and NPCZombieCacheBridge.ShotMemory) then return nil end
    maxRadius = tonumber(maxRadius) or Bridge.GetZombieNPCNumber("ZombieNPC_HearingRadius", 36, 4, 120)
    if maxRadius <= 0 then return nil end

    local now = Bridge.NowMs()
    local zx, zy, zz = zombie:getX(), zombie:getY(), zombie:getZ()
    local best = nil
    local bestD2 = maxRadius * maxRadius

    for id, shot in pairs(NPCZombieCacheBridge.ShotMemory) do
        if type(shot) ~= "table" or (tonumber(shot.untilMs) or 0) < now then
            NPCZombieCacheBridge.ShotMemory[id] = nil
        else
            local sx = tonumber(shot.x)
            local sy = tonumber(shot.y)
            local sz = tonumber(shot.z) or zz
            if sx and sy and math.abs(sz - zz) <= 1 then
                local dx = sx - zx
                local dy = sy - zy
                local d2 = dx * dx + dy * dy
                local radius = math.min(maxRadius, tonumber(shot.radius) or maxRadius)
                if d2 <= bestD2 and d2 <= radius * radius then
                    local bandit = NPCZombieCacheBridge.Cache and (NPCZombieCacheBridge.Cache[id] or NPCZombieCacheBridge.Cache[tostring(id)]) or nil
                    if bandit and bandit.isAlive and bandit:isAlive() then
                        bestD2 = d2
                        best = {id=id, x=sx, y=sy, z=sz, dist=math.sqrt(d2), noise=true}
                    end
                end
            end
        end
    end

    return best
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
    return tostring(brain.persistentId or brain.uid or "") .. "|" .. tostring(brain.appearanceSeed or "") .. "|" .. tostring(brain.faceProfile or "") .. "|" .. tostring(brain.skinTexture or "") .. "|" .. Bridge.ColorSignature(brain.skinColor) .. "|" .. tostring(brain.hairStyle or "") .. "|" .. Bridge.ColorSignature(brain.hairColor)
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

function Bridge.IsBadNPCSkinColor(color)
    if type(color) ~= "table" then return true end
    local r = tonumber(color.r)
    local g = tonumber(color.g)
    local b = tonumber(color.b)
    if not r or not g or not b then return true end
    if r < 0.18 or g < 0.12 or b < 0.08 or r > 1.0 or g > 1.0 or b > 1.0 then return true end
    if g > r + 0.08 and g > b + 0.06 then return true end
    if b > r + 0.12 then return true end
    local maxc = math.max(r, math.max(g, b))
    local minc = math.min(r, math.min(g, b))
    if maxc < 0.55 and (maxc - minc) < 0.055 then return true end
    return false
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
    if not (visuals and ImmutableColor) then return false end
    if Bridge.IsBadNPCSkinColor(skinColor) then
        skinColor = {r = 0.86, g = 0.66, b = 0.52}
    end
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
    local needsPreset = brain.humanVisualLocked ~= true
        or Bridge.IsBadNPCSkinTextureName(brain.skinTexture)
        or Bridge.IsBadNPCSkinColor(brain.skinColor)
    if needsPreset and NPCCreatorBridge and NPCCreatorBridge.ApplyHumanFacePresetToBrain then
        pcall(function() NPCCreatorBridge.ApplyHumanFacePresetToBrain(brain, zombie, nil, false) end)
    end
    if Bridge.IsBadNPCSkinTextureName(brain.skinTexture) then
        brain.skinTexture = Bridge.GetFallbackHumanSkinTexture(zombie, brain)
        brain.humanVisualNormalized = true
    end
    if Bridge.IsBadNPCSkinColor(brain.skinColor) then
        brain.skinColor = {r = 0.86, g = 0.66, b = 0.52}
        brain.humanVisualNormalized = true
    end
    brain.infection = 0
    brain.humanVisualLocked = true
    brain.humanVisualSignature = Bridge.VisualSignature(brain)
    return brain.skinTexture
end

function Bridge.EnsureHumanNPCVisual(zombie, brain, force)
    if not (zombie and brain) then return false end
    local md = zombie.getModData and zombie:getModData() or nil
    local now = Bridge.NowMs()

    local skinTexture = Bridge.NormalizeNPCSkinTexture(zombie, brain)
    local signature = Bridge.VisualSignature(brain)
    local visuals = zombie.getHumanVisual and zombie:getHumanVisual() or nil
    local currentSkin = Bridge.GetVisualSkinTexture(visuals)
    local visualBad = Bridge.IsBadNPCSkinTextureName(currentSkin)
    local needsSkinFix = skinTexture ~= nil and (currentSkin == nil or currentSkin == "" or currentSkin ~= skinTexture or visualBad)
    local locked = md and md.NPC_HUMAN_VISUAL_LOCKED == true and md.NPC_HUMAN_VISUAL_SIG == signature

    if force == true and locked and not needsSkinFix then
        force = false
    end

    local needsCleanup = force == true or needsSkinFix or visualBad
    if not needsCleanup and md and md.NPC_HUMAN_VISUAL_AT and now - md.NPC_HUMAN_VISUAL_AT < 300000 then return false end

    pcall(function() zombie:setNoTeeth(false) end)
    pcall(function() zombie:setVariable("ZombieBiteDone", false) end)
    pcall(function() zombie:setVariable(NPC_LEGACY_KEYS.FORMER_ZOMBIE, false) end)

    if visuals then
        if skinTexture then pcall(function() visuals:setSkinTextureName(skinTexture) end) end
        Bridge.ApplyHumanSkinColor(visuals, brain.skinColor)
        if needsCleanup then Bridge.ClearHumanVisualDamage(visuals) end
    end
    if needsCleanup then Bridge.ClearItemVisualDamage(zombie) end

    if md then
        md.NPC_HUMAN_VISUAL_AT = now
        md.NPC_HUMAN_VISUAL_LOCKED = true
        md.NPC_HUMAN_VISUAL_SIG = signature
        md.NPC_HUMAN_VISUAL_SKIN = skinTexture
        md.NPC_HUMAN_VISUAL_NORMALIZED = brain.humanVisualNormalized == true
        md[NPC_LEGACY_KEYS.FORMER_ZOMBIE] = false
    end
    brain.humanVisualLocked = true
    brain.humanVisualSignature = signature

    if force or needsSkinFix then
        local lastReset = md and tonumber(md.NPC_HUMAN_VISUAL_RESET_AT) or nil
        if not locked and (not lastReset or now - lastReset >= 30000) then
            pcall(function() zombie:resetModelNextFrame() end)
            if force == true then pcall(function() zombie:resetModel() end) end
            if md then md.NPC_HUMAN_VISUAL_RESET_AT = now end
        end
    end
    return true
end

function Bridge.GetCombatCandidateLimit()
    local level, zoom = Bridge.GetPerfLevel()
    local limit = 8
    if level >= 3 then
        limit = 2
    elseif level >= 2 then
        limit = 3
    elseif level >= 1 then
        limit = 5
    end
    if zoom >= 2.35 then
        limit = math.min(limit, 2)
    elseif zoom >= 1.90 then
        limit = math.min(limit, 3)
    elseif zoom >= 1.45 then
        limit = math.min(limit, 4)
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

function Bridge.GetNearbyAllInto(bufferName, x, y, z, radius, maxResults)
    if NPCSpatialIndexBridge and NPCSpatialIndexBridge.GetNearbyAllInto then
        return NPCSpatialIndexBridge.GetNearbyAllInto(Bridge.GetTempArray(bufferName), x, y, z, radius, maxResults)
    end
    if NPCSpatialIndexBridge and NPCSpatialIndexBridge.GetNearbyAll then
        local list = NPCSpatialIndexBridge.GetNearbyAll(x, y, z, radius)
        return list, list and #list or 0, false
    end
    return nil, 0, false
end

function Bridge.GetNearbyZombiesInto(bufferName, x, y, z, radius, maxResults)
    if NPCSpatialIndexBridge and NPCSpatialIndexBridge.GetNearbyZombiesInto then
        return NPCSpatialIndexBridge.GetNearbyZombiesInto(Bridge.GetTempArray(bufferName), x, y, z, radius, maxResults)
    end
    if NPCSpatialIndexBridge and NPCSpatialIndexBridge.GetNearbyZombies then
        local list = NPCSpatialIndexBridge.GetNearbyZombies(x, y, z, radius)
        return list, list and #list or 0, false
    end
    return nil, 0, false
end

function Bridge.GetQueueBrain(gmd, id, persistentId)
    if not (gmd and gmd.Queue) then return nil end
    if id ~= nil then
        local brain = gmd.Queue[id]
        if brain then return brain end
        brain = gmd.Queue[tostring(id)]
        if brain then return brain end
        local nid = tonumber(id)
        if nid then
            brain = gmd.Queue[nid]
            if brain then return brain end
        end
    end
    if persistentId ~= nil then
        local wanted = tostring(persistentId)
        for _, brain in pairs(gmd.Queue) do
            if type(brain) == "table" then
                local brainPersistentId = brain.persistentId or brain.uid
                if brainPersistentId and tostring(brainPersistentId) == wanted then return brain end
            end
        end
    end
    return nil
end

function Bridge.EnsureImmediateNPCLightCache(zombie, id, brain)
    if not (zombie and id and brain and NPCZombieCacheBridge) then return false end
    if NPCZombieCacheBridge.CacheLightB and NPCZombieCacheBridge.CacheLightB[id] then return true end

    NPCZombieCacheBridge.Cache = NPCZombieCacheBridge.Cache or {}
    NPCZombieCacheBridge.CacheLight = NPCZombieCacheBridge.CacheLight or {}
    NPCZombieCacheBridge.CacheLightB = NPCZombieCacheBridge.CacheLightB or {}

    local x, y, z = zombie:getX(), zombie:getY(), zombie:getZ()
    local light = {id = id, x = x, y = y, z = z or 0, brain = brain}
    light["is" .. tostring(NPCLegacyContractBridge.Token or "Bandit")] = true
    if NPCBlackMarketBridge and NPCBlackMarketBridge.IsNoCombatBrain and NPCBlackMarketBridge.IsNoCombatBrain(brain) then
        light.noZombieTarget = true
    end

    NPCZombieCacheBridge.Cache[id] = zombie
    NPCZombieCacheBridge.CacheLight[id] = light
    NPCZombieCacheBridge.CacheLightB[id] = light
    if NPCZombieCacheBridge.CacheLightZ then NPCZombieCacheBridge.CacheLightZ[id] = nil end
    return true
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

function Bridge.TableHasEntries(value)
    if type(value) ~= "table" then return false end
    for _, _ in pairs(value) do return true end
    return false
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

    if not Bridge.TableHasEntries(brain) then return nil end

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
    if NPCCreatorBridge and NPCCreatorBridge.ApplyHumanFacePresetToBrain then
        pcall(function() NPCCreatorBridge.ApplyHumanFacePresetToBrain(brain, zombie, member or profile, false) end)
    end
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

function Bridge.TryRebuildPersistentBrain(zombie, gmd, id, brain)
    local ok, rebuilt = pcall(function() return Bridge.RebuildPersistentBrain(zombie, gmd, id, brain) end)
    if ok then return rebuilt end
    return nil
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
    if zombie:getVariableBoolean(NPC_LEGACY_KEYS.FLAG) then
        if type(brain) ~= "table" and Bridge.HasPersistentNPCStamp(zombie, brain) then
            local rebuilt = Bridge.TryRebuildPersistentBrain(zombie, gmd, id, brain)
            if rebuilt then
                Bridge.MarkAsNPC(zombie, rebuilt)
                return rebuilt, true, true
            end
        end
        return brain, true, true
    end
    if not Bridge.HasPersistentNPCStamp(zombie, brain) then return brain, false, false end

    local persistentId = Bridge.GetZombieServiceId(zombie, NPC_LEGACY_KEYS.PERSISTENT_ID, NPC_LEGACY_KEYS.PERSISTENT_ID)
    local queuedBrain = Bridge.GetQueueBrain(gmd, id, persistentId)
    if queuedBrain then
        Bridge.MarkAsNPC(zombie, queuedBrain)
        return queuedBrain, true, true
    end

    if Bridge.RuntimeKnownPhysical(gmd, id) then
        local rebuilt = Bridge.TryRebuildPersistentBrain(zombie, gmd, id, brain)
        if rebuilt then
            Bridge.MarkAsNPC(zombie, rebuilt)
            return rebuilt, true, true
        end
    end

    persistentId = persistentId or Bridge.GetZombieServiceId(zombie, NPC_LEGACY_KEYS.PERSISTENT_ID, NPC_LEGACY_KEYS.PERSISTENT_ID)
    if persistentId and Bridge.FindPersistentProfile(gmd, persistentId) then
        local rebuilt = Bridge.TryRebuildPersistentBrain(zombie, gmd, id, brain)
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

function Bridge.IsLivePersistentRuntimeResidue(zombie, reason)
    if not zombie then return false end
    local reasonText = tostring(reason or "")
    if reasonText ~= "stale_persistent_runtime_after_reconnect" and reasonText ~= "queue_miss_orphan_cleanup" then return false end

    local isDead = false
    local okDead, deadValue = pcall(function() return zombie:isDead() end)
    if okDead and deadValue == true then isDead = true end
    local okAlive, aliveValue = pcall(function() return zombie:isAlive() end)
    if okAlive and aliveValue == false then isDead = true end
    if isDead then return false end
    if Bridge.IsFormerNPCZombie(zombie) then return false end

    local persistentId = Bridge.GetZombieServiceId(zombie, NPC_LEGACY_KEYS.PERSISTENT_ID, NPC_LEGACY_KEYS.PERSISTENT_ID)
    local groupId = Bridge.GetZombieServiceId(zombie, NPC_LEGACY_KEYS.WORLD_GROUP_ID, NPC_LEGACY_KEYS.WORLD_GROUP_ID)
    if not persistentId and not groupId then return false end

    local md = zombie.getModData and zombie:getModData() or nil
    local now = Bridge.NowMs()
    if md and md.NPCIdentityQuarantined == true and md.NPCIdentityQuarantineReason == reasonText and md.NPCIdentityQuarantinedAt and now - tonumber(md.NPCIdentityQuarantinedAt) < 10000 then
        return true
    end
    if md then
        md.NPCIdentityQuarantined = true
        md.NPCIdentityQuarantineReason = reasonText
        md.NPCIdentityQuarantinedAt = now
        md[NPC_LEGACY_KEYS.IS_FLAG] = true
        md[NPC_LEGACY_KEYS.FORMER_ZOMBIE] = false
    end
    pcall(function() zombie:setVariable(NPC_LEGACY_KEYS.FLAG, true) end)
    pcall(function() zombie:setVariable(NPC_LEGACY_KEYS.FORMER_ZOMBIE, false) end)
    pcall(function() zombie:setNoTeeth(false) end)
    pcall(function() zombie:setReanim(false) end)

    if NPCDiagnosticsBridge and NPCDiagnosticsBridge.LogZombie then
        NPCDiagnosticsBridge.LogZombie("NPC_IDENTITY", "protect_persistent_runtime_residue", zombie, nil, {reason=reasonText, persistentId=persistentId, groupId=groupId}, "identity-protect-residue:" .. reasonText .. ":" .. tostring(persistentId or groupId or "unknown"), false)
    end
    return true
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

function Bridge.IsWoundedRuntime(zombie, brain)
    brain = brain or (NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(zombie)) or nil
    if type(brain) == "table" and brain.wounded == true then return true end
    local md = zombie and zombie.getModData and zombie:getModData() or nil
    return md and (md.NPCWounded == true or md.NPCWoundedState ~= nil) or false
end

function Bridge.ProtectWoundedRuntime(zombie, brain)
    if not Bridge.IsWoundedRuntime(zombie, brain) then return false end
    brain = brain or (NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(zombie)) or nil
    if type(brain) == "table" then
        brain.infection = 0
        brain.woundedNoDespawn = true
        brain.woundedKeepRuntime = true
        brain.noZombieTarget = true
        brain.noAggro = true
        if NPCBrainData and NPCBrainData.Update then pcall(function() NPCBrainData.Update(zombie, brain) end) end
    end
    local md = zombie and zombie.getModData and zombie:getModData() or nil
    if md then
        md.NPCWounded = true
        md.NPCWoundedState = brain and brain.woundedState or md.NPCWoundedState or "wounded"
        md.NPCKeepCorpse = true
        md.NPCNoRuntimeCleanup = true
        md[NPC_LEGACY_KEYS.IS_FLAG] = true
        md[NPC_LEGACY_KEYS.FORMER_ZOMBIE] = false
    end
    pcall(function() zombie:setVariable(NPC_LEGACY_KEYS.FLAG, true) end)
    pcall(function() zombie:setVariable(NPC_LEGACY_KEYS.FORMER_ZOMBIE, false) end)
    pcall(function() zombie:setReanim(false) end)
    pcall(function() zombie:setNoTeeth(false) end)
    return true
end

function Bridge.ShouldKeepDeadNPCCorpse(zombie, reason)
    if not zombie then return false end
    local md = zombie.getModData and zombie:getModData() or nil
    if not md then return false end
    if not (md.NPCKeepCorpse == true or md.NPCLootableCorpse == true or md.NPCCorpseFromNPCCombat == true) then return false end
    local reasonText = string.lower(tostring(reason or ""))
    if string.find(reasonText, "force", 1, true) or string.find(reasonText, "blackmarket", 1, true) then return false end
    local isDead = false
    local okDead, deadValue = pcall(function() return zombie:isDead() end)
    if okDead and deadValue == true then isDead = true end
    local okAlive, aliveValue = pcall(function() return zombie:isAlive() end)
    if okAlive and aliveValue == false then isDead = true end
    return isDead == true
end

function Bridge.RemoveNPCRuntimeObject(zombie, reason)
    if not zombie then return false end
    if Bridge.ShouldKeepDeadNPCCorpse and Bridge.ShouldKeepDeadNPCCorpse(zombie, reason) then return false end
    if Bridge.ProtectWoundedRuntime and Bridge.ProtectWoundedRuntime(zombie, nil) then return false end

    if Bridge.IsLivePersistentRuntimeResidue and Bridge.IsLivePersistentRuntimeResidue(zombie, reason) then
        return false
    end

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

    if NPCDiagnosticsBridge and NPCDiagnosticsBridge.LogZombie then
        NPCDiagnosticsBridge.LogZombie("NPC_IDENTITY", "remove_runtime_object", zombie, nil, {reason=reason, isDead=isDead}, "identity-remove-runtime:" .. tostring(reason or "unknown"), true)
    end

    if not isDead then
        pcall(function() zombie:removeFromWorld() end)
        pcall(function() zombie:removeFromSquare() end)
    elseif md then
        md[NPC_LEGACY_KEYS.FORMER_ZOMBIE] = true
        md[NPC_LEGACY_KEYS.FORMER_ZOMBIE_AT] = getGameTime and getGameTime():getWorldAgeHours() or 0
    end

    return true
end

function Bridge.IsHumanAnimationBrain(brain)
    return brain and (brain.forceHumanAnimation == true or brain.humanNPC == true or brain.noZombieAnimation == true or brain.isFactionLeader == true or brain.leaderPhysical == true)
end

function Bridge.ApplyHumanAnimationSanity(zombie, brain, walkType)
    if not (zombie and Bridge.IsHumanAnimationBrain(brain)) then return false end
    walkType = walkType or brain.defaultWalkType or brain.walkType or "Walk"
    if walkType ~= "Run" and walkType ~= "WalkAim" then walkType = "Walk" end
    brain.infection = 0
    brain.sound = 0
    brain.eatBody = false
    brain.humanNPC = true
    brain.forceHumanAnimation = true
    brain.noZombieAnimation = true
    brain.dna = brain.dna or {}
    brain.dna.slow = false
    brain.dna.blind = false
    brain.dna.sneak = false
    brain.dna.unfit = false
    brain.dna.coward = false
    local md = zombie.getModData and zombie:getModData() or nil
    if md then
        md.NPC_HUMAN_ANIMATION = true
        md.NPC_NO_ZOMBIE_ANIMATION = true
        md.NPC_IS_LIVE_HUMAN = true
        md[NPC_LEGACY_KEYS.FORMER_ZOMBIE] = false
    end
    pcall(function() zombie:setNoTeeth(false) end)
    pcall(function() zombie:setReanim(false) end)
    pcall(function() zombie:setVariable(NPC_LEGACY_KEYS.FORMER_ZOMBIE, false) end)
    pcall(function() zombie:setVariable(NPC_LEGACY_KEYS.WALK_TYPE, walkType) end)
    -- `zombieWalkType` is read-only in B41 MP and logs a warning even inside pcall; setWalkType below preserves behavior.
    pcall(function() zombie:setWalkType(walkType) end)
    pcall(function() zombie:setCrawler(false) end)
    pcall(function() zombie:setFakeDead(false) end)
    pcall(function() zombie:setFallOnFront(false) end)
    pcall(function() zombie:setKnockedDown(false) end)
    pcall(function() zombie:setOnFloor(false) end)
    pcall(function() zombie:setSitAgainstWall(false) end)
    return true
end

function Bridge.MarkAsNPC(zombie, brain)
    if not (zombie and brain) then return false end

    if NPCCreatorBridge and NPCCreatorBridge.ApplyHumanFacePresetToBrain then
        pcall(function() NPCCreatorBridge.ApplyHumanFacePresetToBrain(brain, zombie, nil, false) end)
    end

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
    Bridge.ApplyHumanAnimationSanity(zombie, brain, "Walk")
    Bridge.EnforceLiveNPCNotVanillaZombie(zombie, brain, "mark_as_npc")

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

    local markId = tostring(brain.persistentId or brain.uid or brain.id or "unknown")
    local alreadyMarked = zmd and zmd.NPC_MARKED_PERSISTENT_ID == markId and zmd.NPC_HUMAN_VISUAL_LOCKED == true
    Bridge.EnsureHumanNPCVisual(zombie, brain, alreadyMarked ~= true)
    if zmd then
        zmd.NPC_MARKED_PERSISTENT_ID = markId
        zmd.NPC_MARKED_AT = Bridge.NowMs()
    end
    if NPCDiagnosticsBridge and NPCDiagnosticsBridge.LogZombie and not alreadyMarked then
        NPCDiagnosticsBridge.LogZombie("NPC_IDENTITY", "mark_as_npc", zombie, brain, {event="mark_as_npc"}, "identity-mark:" .. tostring(brain.id or brain.persistentId or "unknown"), false)
    end
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
    if Bridge.IsBlackMarketNPC(bandit) or Bridge.IsWorldPersistentNPC(bandit, oldBrain) or (oldBrain and (oldBrain.uid or oldBrain.persistentId or oldBrain.wounded == true or oldBrain.mercenaryHired == true)) then
        if oldBrain then
            oldBrain.infection = 0
            oldBrain.zombifyBlocked = true
            oldBrain.zombifyBlockedAt = Bridge.NowMs()
            if bandit.getHealth and bandit.setHealth then
                local h = tonumber(bandit:getHealth()) or tonumber(oldBrain.health) or 0.35
                if h < 0.12 then pcall(function() bandit:setHealth(0.12) end) end
            end
            if NPCEntity and NPCEntity.ClearTasks then pcall(function() NPCEntity.ClearTasks(bandit) end) end
            Bridge.MarkAsNPC(bandit, oldBrain)
        end
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
    if md and md[NPC_LEGACY_KEYS.VISUAL_AT] and now - md[NPC_LEGACY_KEYS.VISUAL_AT] < 30000 then return false end

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

    local lastReset = md and tonumber(md.NPC_VISUAL_RESET_AT) or nil
    if not lastReset or now - lastReset >= 30000 then
        pcall(function() bandit:resetModelNextFrame() end)
        if skinMismatch == true then pcall(function() bandit:resetModel() end) end
        if md then md.NPC_VISUAL_RESET_AT = now end
    end

    if NPCDiagnosticsBridge and NPCDiagnosticsBridge.TraceAppearance then
        NPCDiagnosticsBridge.TraceAppearance("apply_visuals", bandit, brain, {visualSig=visualSig, currentSkin=currentSkin, newSkin=brain.skinTexture, skinMismatch=skinMismatch}, false)
    end

    if md then
        md[NPC_LEGACY_KEYS.VISUAL_SIG] = visualSig
        md[NPC_LEGACY_KEYS.VISUAL_AT] = now
    end
    return true
end

function Bridge.HasVisibleEssentialClothing(zombie)
    if not (zombie and zombie.getWornItems) then return true end
    local okWorn, worn = pcall(function() return zombie:getWornItems() end)
    if not okWorn or not worn then return true end

    local hasTorso, hasLegs, hasFeet = false, false, false
    local function markBodyLocation(loc)
        loc = string.lower(tostring(loc or ""))
        if loc == "" then return end
        if string.find(loc, "torso", 1, true) or string.find(loc, "shirt", 1, true) or string.find(loc, "jacket", 1, true) or string.find(loc, "chest", 1, true) then hasTorso = true end
        if string.find(loc, "legs", 1, true) or string.find(loc, "pants", 1, true) or string.find(loc, "trousers", 1, true) then hasLegs = true end
        if string.find(loc, "feet", 1, true) or string.find(loc, "shoes", 1, true) then hasFeet = true end
    end

    local size = 0
    local okSize, wornSize = pcall(function() return worn:size() end)
    if okSize and tonumber(wornSize) then size = tonumber(wornSize) end
    if size <= 0 then return false end
    if not worn.getItemByIndex then return true end

    for i = 0, math.max(0, size - 1) do
        local okItem, item = pcall(function() return worn:getItemByIndex(i) end)
        if okItem and item and item.getBodyLocation then
            local okLoc, value = pcall(function() return item:getBodyLocation() end)
            if okLoc and value then markBodyLocation(value) end
        end
        if hasTorso == true and hasLegs == true and hasFeet == true then return true end
    end

    return hasTorso == true and hasLegs == true and hasFeet == true
end

function Bridge.EnsureEssentialNPCClothing(zombie, brain)
    if not (zombie and brain) then return false end
    if Bridge.IsBlackMarketNPC and Bridge.IsBlackMarketNPC(zombie) then return false end
    local md = zombie.getModData and zombie:getModData() or nil
    local now = Bridge.NowMs and Bridge.NowMs() or 0
    if md and md.NPC_CLOTHING_GUARD_AT and now - tonumber(md.NPC_CLOTHING_GUARD_AT or 0) < 15000 then return false end
    if md then md.NPC_CLOTHING_GUARD_AT = now end
    if Bridge.HasVisibleEssentialClothing(zombie) then return false end
    if not (InventoryItemFactory and InventoryItemFactory.CreateItem and zombie.setWornItem) then return false end

    local fallback = {
        "Base.Shirt_CamoGreen",
        "Base.Jacket_ArmyCamoGreen",
        "Base.Trousers_ArmyService",
        "Base.Shoes_ArmyBoots"
    }
    local changed = false
    for _, fullType in ipairs(fallback) do
        local okItem, item = pcall(function() return InventoryItemFactory.CreateItem(fullType) end)
        if okItem and item then
            local location = nil
            if item.getBodyLocation then
                local okLoc, locValue = pcall(function() return item:getBodyLocation() end)
                if okLoc and locValue and tostring(locValue) ~= "" then location = locValue end
            end
            if location then
                local okWear = pcall(function() zombie:setWornItem(location, item) end)
                if okWear then changed = true end
            end
        end
    end

    if changed then
        brain._stage448ClothingRestoredAt = now
        if md then md.NPC_CLOTHING_RESTORED_AT = now end
        pcall(function() zombie:resetModelNextFrame() end)
        if NPCPersistentNPCBridge and NPCPersistentNPCBridge.BuildWornLite then
            local okLite, wornLite = pcall(function() return NPCPersistentNPCBridge.BuildWornLite(zombie, brain) end)
            if okLite and wornLite then
                brain.wornLite = wornLite
                brain.gearLite = wornLite
            end
        end
    end
    return changed
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

function Bridge.EnforceLiveNPCNotVanillaZombie(bandit, brain, reason)
    if not bandit then return false end

    local isNPCFlag = false
    if bandit.getVariableBoolean then
        local okFlag, flag = pcall(function() return bandit:getVariableBoolean(NPC_LEGACY_KEYS.FLAG) end)
        isNPCFlag = okFlag and flag == true
    end
    local looksLikeNPCBrain = brain and (brain.humanNPC == true or brain.forceHumanAnimation == true or brain.noZombieAnimation == true or brain.side ~= nil or brain.groupId ~= nil or brain.persistentId ~= nil or brain.uid ~= nil)
    if not isNPCFlag and not looksLikeNPCBrain then return false end

    local md = bandit.getModData and bandit:getModData() or nil
    if md then
        md.NPC_IS_LIVE_HUMAN = true
        md.NPC_NO_VANILLA_ZOMBIE_BRAIN = true
        md.NPC_NO_VANILLA_ZOMBIE_BRAIN_REASON = tostring(reason or "npc_guard")
        md[NPC_LEGACY_KEYS.FORMER_ZOMBIE] = false
    end

    if bandit.setVariable then
        pcall(function() bandit:setVariable(NPC_LEGACY_KEYS.FLAG, true) end)
        pcall(function() bandit:setVariable(NPC_LEGACY_KEYS.FORMER_ZOMBIE, false) end)
        pcall(function() bandit:setVariable("NoLungeAttack", true) end)
        pcall(function() bandit:setVariable("ZombieBiteDone", true) end)
        pcall(function() bandit:setVariable("NPCNoVanillaZombieBrain", true) end)
    end

    if bandit.setTarget then pcall(function() bandit:setTarget(nil) end) end
    if bandit.setTargetSeenTime then pcall(function() bandit:setTargetSeenTime(0) end) end
    if bandit.clearAggroList then pcall(function() bandit:clearAggroList() end) end
    if bandit.setEatBodyTarget then pcall(function() bandit:setEatBodyTarget(nil, false) end) end
    if bandit.setReanim then pcall(function() bandit:setReanim(false) end) end
    if bandit.setCrawler then pcall(function() bandit:setCrawler(false) end) end
    if bandit.setFakeDead then pcall(function() bandit:setFakeDead(false) end) end

    local asn = bandit.getActionStateName and tostring(bandit:getActionStateName() or "") or ""
    local lower = string.lower(asn)
    if lower == "lunge" or lower == "turnalerted" or string.find(lower, "attack", 1, true) then
        if bandit.changeState and ZombieIdleState and ZombieIdleState.instance then
            pcall(function() bandit:changeState(ZombieIdleState.instance()) end)
        end
    end

    return true
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
    local actionStateBrain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(bandit) or nil
    Bridge.EnforceLiveNPCNotVanillaZombie(bandit, actionStateBrain, "manage_action_state")
    if Bridge.IsBlackMarketNPC(bandit) then return Bridge.KeepBlackMarketStanding(bandit) end

    local woundedBrain = actionStateBrain
    if woundedBrain and woundedBrain.wounded == true and woundedBrain.woundedDowned == true and woundedBrain.woundedState == "downed" then
        Bridge.ProtectWoundedRuntime(bandit, woundedBrain)
        if NPCWoundedBridge and NPCWoundedBridge.ApplyLocalState then pcall(function() NPCWoundedBridge.ApplyLocalState(bandit, woundedBrain) end) end
        return false
    end

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

    local brain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(bandit) or nil

    if bridgeLegacySandboxBool("General_BleedOut", true) then
        local healing = false
        local health = bandit.getHealth and bandit:getHealth() or 1
        if health < 0.4 then
            local zx, zy = bandit:getX(), bandit:getY()
            if ZombRand and ZombRand(16) == 0 then
                local skipSplat = false
                if NPCRenderReliefBridge and NPCRenderReliefBridge.ShouldSkipCombatSplat then
                    local okSplat, retSplat = pcall(function() return NPCRenderReliefBridge.ShouldSkipCombatSplat(bandit, brain, "bleedout") end)
                    skipSplat = okSplat and retSplat == true
                end
                if not skipSplat then
                    local bx = zx - 0.5 + ZombRandFloat(0.1, 0.9)
                    local by = zy - 0.5 + ZombRandFloat(0.1, 0.9)
                    local chunk = bandit.getChunk and bandit:getChunk() or nil
                    if chunk and chunk.addBloodSplat then chunk:addBloodSplat(bx, by, 0, ZombRand(20)) end
                end
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
        if brain and brain.allowZombification ~= true then
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

    local nearby, nearbyCount = Bridge.GetNearbyAllInto("escapeNearby", bx, by, bz, radius or 18, 96)
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

    local potentialEnemyList, potentialEnemyCount = nil, 0
    local potentialEnemyIsArray = false
    if NPCSpatialIndexBridge and NPCSpatialIndexBridge.GetNearbyAllInto then
        potentialEnemyList, potentialEnemyCount = Bridge.GetNearbyAllInto("preservationNearby", bx, by, bz, radius, 96)
        potentialEnemyIsArray = true
    else
        potentialEnemyList = NPCZombieCacheBridge.CacheLight
    end

    local function countPotentialEnemy(potentialEnemy)
        if potentialEnemy and bz == potentialEnemy.z then  -- First check avoids unnecessary calculations
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

    if potentialEnemyIsArray then
        for i = 1, potentialEnemyCount do countPotentialEnemy(potentialEnemyList[i]) end
    else
        for _, potentialEnemy in pairs(potentialEnemyList or {}) do countPotentialEnemy(potentialEnemy) end
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


function Bridge.IsPlayerControlledBrain(brain)
    if type(brain) ~= "table" then return false end
    return brain.mercenaryHired == true
        or brain.hired == true
        or brain.isPlayerGuard == true
        or brain.playerOwned == true
        or brain.playerControlled == true
        or brain.master ~= nil
        or brain.follow == true
        or brain.followPlayer == true
end

function Bridge.ResolveCombatIntent(bandit, brain, enemyCharacter, enemyKind, dist, weapons, canMelee, canShoot, pistolRange, rifleRange, maxRange)
    local combat, firing, shove = false, false, false
    if not (bandit and brain and enemyCharacter and weapons) then return combat, firing, shove, maxRange end
    local zz = bandit.getZ and bandit:getZ() or 0
    local pz = enemyCharacter.getZ and enemyCharacter:getZ() or zz
    dist = tonumber(dist) or 9999

    if canMelee and weapons.melee and zz == pz then
        if not maxRange then
            maxRange = Bridge.GetMeleeRangeForBrain(brain, weapons)
        end
        local strikeRange = Bridge.GetMeleeStrikeRange(weapons.melee, maxRange)
        if dist <= strikeRange then
            local asn = enemyCharacter.getActionStateName and enemyCharacter:getActionStateName() or ""
            local prone = enemyCharacter.isProne and enemyCharacter:isProne() or false
            shove = dist < 0.7 and not prone and asn ~= "onground" and asn ~= "sitonground" and asn ~= "climbfence" and asn ~= "bumped" and asn ~= "getup" and asn ~= "falldown"
            combat = not shove
        end
    end

    local retaliationFireTarget = Bridge.IsMercenaryRetaliationActive and Bridge.IsMercenaryRetaliationActive(brain, enemyCharacter) == true
    if canShoot and (retaliationFireTarget == true or not NPCOrderContract or not NPCOrderContract.CanShootAtDistance or NPCOrderContract.CanShootAtDistance(brain, dist)) then
        if weapons.primary and (weapons.primary.bulletsLeft > 0 or weapons.primary.magCount > 0) and dist < rifleRange then
            firing = true
        elseif weapons.secondary and (weapons.secondary.bulletsLeft > 0 or weapons.secondary.magCount > 0) and dist < pistolRange then
            firing = true
        end
    end

    return combat, firing, shove, maxRange
end

function Bridge.HasUsableFirearmSlots(weapons)
    if type(weapons) ~= "table" then return false end
    for _, slot in ipairs({"primary", "secondary"}) do
        local weapon = weapons[slot]
        if type(weapon) == "table" and weapon.name and weapon.name ~= false and weapon.name ~= "" then
            if (tonumber(weapon.bulletsLeft or 0) or 0) > 0 or (tonumber(weapon.magCount or 0) or 0) > 0 or (tonumber(weapon.ammoCount or 0) or 0) > 0 then
                return true
            end
        end
    end
    return false
end

function Bridge.AreBrainsCombatEnemies(brain, targetBrain)
    if not targetBrain then return true end
    if brain and targetBrain and brain.id and targetBrain.id and tostring(brain.id) == tostring(targetBrain.id) then return false end
    if NPCFactionBridge and NPCFactionBridge.IsEnabled and NPCFactionBridge.IsEnabled() and NPCFactionBridge.AreBrainsEnemies then
        local ok, enemies = pcall(function() return NPCFactionBridge.AreBrainsEnemies(brain, targetBrain) end)
        if ok and enemies ~= nil then return enemies == true end
    end
    if brain and targetBrain then
        if brain.roadPatrol and targetBrain.roadPatrol and brain.patrolColor and targetBrain.patrolColor and brain.patrolColor ~= targetBrain.patrolColor then return true end
        if brain.battleEnemyGroupId and targetBrain.worldGroupId and tostring(brain.battleEnemyGroupId) == tostring(targetBrain.worldGroupId) then return true end
        if brain.clan ~= nil and targetBrain.clan ~= nil and brain.clan ~= targetBrain.clan and (brain.hostile or targetBrain.hostile) then return true end
        if brain.faction ~= nil and targetBrain.faction ~= nil and tostring(brain.faction) ~= tostring(targetBrain.faction) and (brain.hostile or targetBrain.hostile or brain.factionShoot or targetBrain.factionShoot) then return true end
    end
    return false
end

function Bridge.IsCombatPreemptibleTask(task)
    if not task or not task.action then return false end
    local action = task.action
    if action == "Shoot" or action == "Aim" or action == "Hit" or action == "Shove" or action == "Reload" or action == "Equip" or action == "Unequip" then return false end
    if task.playerOrder == true and task.allowCombatPreempt ~= true then return false end
    return action == "Move" or action == "GoTo" or action == "Time" or action == "FaceLocation" or action == "Single" or action == "Loot" or action == "LootItems"
end

function Bridge.TryPreemptForCombat(bandit, brain, enemyCharacter, firing, combat, shove)
    if not (bandit and brain and enemyCharacter) then return end
    if not (firing or combat or shove) then return end
    if not (NPCEntity and NPCEntity.GetTask and NPCEntity.ClearTasks) then return end
    local current = NPCEntity.GetTask(bandit)
    if not Bridge.IsCombatPreemptibleTask(current) then return end
    local now = getTimestampMs and getTimestampMs() or 0
    brain.ai = brain.ai or {}
    if (tonumber(brain.ai.lastCombatPreemptAt) or 0) + 240 > now then return end
    brain.ai.lastCombatPreemptAt = now
    if current then current.routerNoCooldownOnRemove = true end
    NPCEntity.ClearTasks(bandit)
    brain.ai.lastCombatPreemptReason = current and tostring(current.action) or "unknown"
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

function Bridge.IsMercenaryFireDisciplineBrain(brain)
    if type(brain) ~= "table" then return false end
    if NPCOrderContract and NPCOrderContract.IsHiredMercenary then
        local ok, hired = pcall(function() return NPCOrderContract.IsHiredMercenary(brain) end)
        if ok then return hired == true end
    end
    return brain.mercenaryHired == true or brain.isPlayerGuard == true or brain.relationshipToPlayer == "hired_bodyguard" or brain.factionState == "hired_blue_bodyguard"
end

function Bridge.GetStrictOrderBoundaryAnchor(bandit, brain, order)
    if not (bandit and type(brain) == "table") then return nil end
    order = order or Bridge.GetStrictMercenaryOrder(brain)
    if type(order) ~= "table" then return nil end
    local name = bridge_normMercenaryOrderName(order.name)
    if name == "Follow" or name == "Guard" or name == "FallBack" or name == "Return" then
        local master = Bridge.GetStrictOrderMaster(bandit, brain)
        if master and master.getX then
            return {x=master:getX(), y=master:getY(), z=master:getZ(), name=name}
        end
    elseif name == "Hold" then
        local anchor = Bridge.GetManualOrderAnchor(order, bandit)
        if anchor and anchor.x and anchor.y then
            return {x=anchor.x, y=anchor.y, z=anchor.z or bandit:getZ(), name=name}
        end
    end
    return nil
end

function Bridge.GetStrictOrderChaseBoundary(brain, name)
    name = bridge_normMercenaryOrderName(name)
    local order = type(brain) == "table" and type(brain.order) == "table" and brain.order or nil
    local combatRange = order and (tonumber(order.tacticalCombatRange) or (type(order.leash) == "table" and tonumber(order.leash.combat))) or nil
    if combatRange == nil and NPCOrderContract and NPCOrderContract.GetStrictCombatRange then combatRange = NPCOrderContract.GetStrictCombatRange(brain) end
    combatRange = tonumber(combatRange)
    if name == "Follow" then return math.min(combatRange or 8.0, 8.0) end
    if name == "Guard" then return math.min(combatRange or 10.5, 10.5) end
    if name == "Hold" then return math.min(combatRange or 7.0, 7.0) end
    if name == "FallBack" or name == "Return" then return math.min(combatRange or 4.5, 4.5) end
    return combatRange or 9.0
end

function Bridge.IsTargetOutsideStrictOrderBoundary(bandit, brain, enemyCharacter, dist)
    if not (bandit and type(brain) == "table" and enemyCharacter and enemyCharacter.getX and enemyCharacter.getY) then return false end
    local order = Bridge.GetStrictMercenaryOrder(brain)
    if type(order) ~= "table" then return false end
    dist = tonumber(dist or 9999) or 9999
    if dist <= 1.45 then return false end
    local anchor = Bridge.GetStrictOrderBoundaryAnchor(bandit, brain, order)
    if not anchor then return false end
    local name = anchor.name or bridge_normMercenaryOrderName(order.name)
    local boundary = Bridge.GetStrictOrderChaseBoundary(brain, name)
    local targetDx = (tonumber(enemyCharacter:getX()) or 0) - (tonumber(anchor.x) or 0)
    local targetDy = (tonumber(enemyCharacter:getY()) or 0) - (tonumber(anchor.y) or 0)
    local targetDist = math.sqrt(targetDx * targetDx + targetDy * targetDy)
    local targetZ = enemyCharacter.getZ and enemyCharacter:getZ() or anchor.z
    local targetZDist = math.abs((tonumber(targetZ) or 0) - (tonumber(anchor.z) or 0))
    if targetZDist > 0.45 then return true, targetDist, boundary, name end
    if targetDist > boundary then return true, targetDist, boundary, name end
    local selfDx = (tonumber(bandit:getX()) or 0) - (tonumber(anchor.x) or 0)
    local selfDy = (tonumber(bandit:getY()) or 0) - (tonumber(anchor.y) or 0)
    local selfDist = math.sqrt(selfDx * selfDx + selfDy * selfDy)
    local leash = Bridge.GetStrictOrderLeash(brain, name)
    if leash and selfDist > leash * 0.82 and targetDist > selfDist + 1.0 then return true, targetDist, boundary, name end
    return false, targetDist, boundary, name
end

function Bridge.IsStrictTaskOutsideChaseBoundary(bandit, brain, order, task)
    if not (bandit and type(brain) == "table" and type(order) == "table" and type(task) == "table") then return false end
    local action = tostring(task.action or "")
    if action == "" then return false end
    local chaseLike = task.combatMove == true or task.meleeApproach == true or task.targetId ~= nil or task.targetKind ~= nil or action == "Shoot" or action == "Aim" or action == "Hit" or action == "Shove"
    local directorState = tostring(task.directorState or task.state or "")
    if directorState == "SearchEnemy" or directorState == "PatrolArea" or directorState == "LootArea" or directorState == "FlankEnemy" or directorState == "BoundForward" or directorState == "InvestigateNoise" or directorState == "MeleeFallback" or directorState == "CombatMemory" then
        chaseLike = true
    end
    if chaseLike ~= true then return false end
    local anchor = Bridge.GetStrictOrderBoundaryAnchor(bandit, brain, order)
    if not anchor then return false end
    local name = anchor.name or bridge_normMercenaryOrderName(order.name)
    local boundary = Bridge.GetStrictOrderChaseBoundary(brain, name)
    local tx = tonumber(task.x)
    local ty = tonumber(task.y)
    local tz = tonumber(task.z) or tonumber(anchor.z) or 0
    if tx and ty then
        local dx = tx - (tonumber(anchor.x) or tx)
        local dy = ty - (tonumber(anchor.y) or ty)
        local taskDist = math.sqrt(dx * dx + dy * dy)
        local zdist = math.abs(tz - (tonumber(anchor.z) or tz))
        if zdist > 0.45 or taskDist > boundary then
            brain.ai = brain.ai or {}
            brain.ai.lastStrictBoundaryDeniedAtMs = Bridge.NowMs and Bridge.NowMs() or (getTimestampMs and getTimestampMs() or 0)
            brain.ai.lastStrictBoundaryDeniedReason = "task"
            brain.ai.lastStrictBoundaryDeniedOrder = name
            brain.ai.lastStrictBoundaryDeniedDist = taskDist
            return true
        end
    end
    local selfDx = (tonumber(bandit:getX()) or 0) - (tonumber(anchor.x) or 0)
    local selfDy = (tonumber(bandit:getY()) or 0) - (tonumber(anchor.y) or 0)
    local selfDist = math.sqrt(selfDx * selfDx + selfDy * selfDy)
    local leash = Bridge.GetStrictOrderLeash(brain, name)
    if leash and selfDist > leash * 0.82 then
        brain.ai = brain.ai or {}
        brain.ai.lastStrictBoundaryDeniedAtMs = Bridge.NowMs and Bridge.NowMs() or (getTimestampMs and getTimestampMs() or 0)
        brain.ai.lastStrictBoundaryDeniedReason = "self_leash"
        brain.ai.lastStrictBoundaryDeniedOrder = name
        brain.ai.lastStrictBoundaryDeniedDist = selfDist
        return true
    end
    return false
end

function Bridge.GetMercenaryCombatTaskDistance(bandit, task)
    if not (bandit and type(task) == "table") then return nil end
    local tx = tonumber(task.x)
    local ty = tonumber(task.y)
    if tx and ty and bandit.getX and bandit.getY then
        local dx = (tonumber(bandit:getX()) or 0) - tx
        local dy = (tonumber(bandit:getY()) or 0) - ty
        return math.sqrt(dx * dx + dy * dy)
    end
    return nil
end

function Bridge.IsMercenaryFireModeTaskDenied(bandit, brain, order, task)
    if not (bandit and type(brain) == "table" and type(task) == "table") then return false end
    if not Bridge.IsMercenaryFireDisciplineBrain(brain) then return false end
    if not (NPCOrderContract and NPCOrderContract.IsFireModeCombatTaskAllowed) then return false end

    local dist = Bridge.GetMercenaryCombatTaskDistance(bandit, task)
    if not dist and bandit.getTarget then
        local okTarget, target = pcall(function() return bandit:getTarget() end)
        if okTarget and target and target.getX and target.getY and bandit.getX and bandit.getY then
            local dx = (tonumber(bandit:getX()) or 0) - (tonumber(target:getX()) or 0)
            local dy = (tonumber(bandit:getY()) or 0) - (tonumber(target:getY()) or 0)
            dist = math.sqrt(dx * dx + dy * dy)
        end
    end
    dist = tonumber(dist or 9999) or 9999

    if Bridge.IsMercenaryRetaliationActive and Bridge.IsMercenaryRetaliationActive(brain) == true then return false end

    local mode = NPCOrderContract.GetFireMode and NPCOrderContract.GetFireMode(brain) or (order and order.fireMode)
    if NPCOrderContract.NormalizeFireMode then mode = NPCOrderContract.NormalizeFireMode(mode) end
    local allowed = NPCOrderContract.IsFireModeCombatTaskAllowed(brain, task, dist, mode) == true
    if allowed then return false end

    brain.ai = brain.ai or {}
    brain.ai.lastFireModeTaskDeniedAtMs = Bridge.NowMs and Bridge.NowMs() or (getTimestampMs and getTimestampMs() or 0)
    brain.ai.lastFireModeTaskDeniedMode = mode
    brain.ai.lastFireModeTaskDeniedAction = tostring(task.action or "")
    brain.ai.lastFireModeTaskDeniedDist = dist
    return true
end

function Bridge.ApplyMercenaryFireDiscipline(bandit, brain, enemyCharacter, enemyKind, dist, combat, firing, shove, enemyMemoryOnly)
    if not Bridge.IsMercenaryFireDisciplineBrain(brain) then return combat, firing, shove, true end
    if not enemyCharacter then return combat, firing, shove, false end

    dist = tonumber(dist or 9999) or 9999
    local mode = NPCOrderContract and NPCOrderContract.GetFireMode and NPCOrderContract.GetFireMode(brain) or nil
    if NPCOrderContract and NPCOrderContract.NormalizeFireMode then
        mode = NPCOrderContract.NormalizeFireMode(mode)
    else
        mode = tostring(mode or "FireAtWill")
    end
    local retaliationTarget = Bridge.IsMercenaryRetaliationActive and Bridge.IsMercenaryRetaliationActive(brain, enemyCharacter) == true
    if retaliationTarget then mode = "FireAtWill" end

    if dist <= 3.5 then
        brain.ai = brain.ai or {}
        brain.ai.lastCloseThreatAt = NPCOrderContract and NPCOrderContract.Now and NPCOrderContract.Now() or brain.ai.lastCloseThreatAt
    end

    local boundaryDenied, boundaryDist, boundaryLimit, boundaryOrder = false, nil, nil, nil
    if retaliationTarget ~= true then
        boundaryDenied, boundaryDist, boundaryLimit, boundaryOrder = Bridge.IsTargetOutsideStrictOrderBoundary(bandit, brain, enemyCharacter, dist)
    end
    if boundaryDenied then
        brain.ai = brain.ai or {}
        brain.ai.lastStrictBoundaryDeniedAtMs = Bridge.NowMs and Bridge.NowMs() or (getTimestampMs and getTimestampMs() or 0)
        brain.ai.lastStrictBoundaryDeniedReason = "target"
        brain.ai.lastStrictBoundaryDeniedOrder = boundaryOrder
        brain.ai.lastStrictBoundaryDeniedDist = boundaryDist
        brain.ai.lastStrictBoundaryDeniedLimit = boundaryLimit
        return false, false, false, false
    end

    local allowed = true
    if retaliationTarget ~= true and NPCOrderContract and NPCOrderContract.CanEngageAtDistance then
        allowed = NPCOrderContract.CanEngageAtDistance(brain, dist, mode) == true
    end

    if not allowed then
        brain.ai = brain.ai or {}
        brain.ai.lastFireDisciplineDeniedAtMs = Bridge.NowMs and Bridge.NowMs() or (getTimestampMs and getTimestampMs() or 0)
        brain.ai.lastFireDisciplineDeniedMode = mode
        brain.ai.lastFireDisciplineDeniedDist = dist
        return false, false, false, false
    end

    if mode == "HoldFire" then
        firing = false
        if dist > 1.35 then combat = false; shove = false end
    elseif mode == "MeleeOnly" then
        firing = false
        if dist > 2.35 then combat = false; shove = false end
    elseif mode == "ReturnFire" then
        if NPCOrderContract and NPCOrderContract.IsRecentlyProvoked and not NPCOrderContract.IsRecentlyProvoked(brain, 8) and dist > 3.5 then
            return false, false, false, false
        end
        if not firing and dist > 2.0 then combat = false; shove = false end
    elseif mode == "Defensive" then
        if not firing and dist > 2.5 then combat = false; shove = false end
    elseif mode == "Suppress" then
        if not firing and dist > 2.0 then combat = false; shove = false end
    elseif mode == "DangerClose" then
        if dist > 7.0 then return false, false, false, false end
    end

    if enemyMemoryOnly and firing then firing = false end
    if not (combat or firing or shove) then
        local chaseAllowed = true
        if NPCOrderContract and NPCOrderContract.AllowsChaseAtDistance then
            chaseAllowed = NPCOrderContract.AllowsChaseAtDistance(brain, dist, mode) == true
        end
        if not chaseAllowed then return false, false, false, false end
    end

    return combat, firing, shove, true
end

function Bridge.FilterCurrentTargetByMercenaryFireDiscipline(bandit, brain, enemyCharacter, enemyKind, dist, combat, firing, shove, enemyMemoryOnly)
    if not enemyCharacter then return nil, enemyKind, dist, combat, firing, shove end
    local allow
    combat, firing, shove, allow = Bridge.ApplyMercenaryFireDiscipline(bandit, brain, enemyCharacter, enemyKind, dist, combat, firing, shove, enemyMemoryOnly)
    if allow ~= true then return nil, nil, 40, false, false, false end
    return enemyCharacter, enemyKind, dist, combat, firing, shove
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
    local directMercenaryCombatActive = Bridge.IsMercenaryDirectCombatModeActive and Bridge.IsMercenaryDirectCombatModeActive(brain, type(brain) == "table" and brain.order or nil)
    if (not asyncCombatScanActive) and directMercenaryCombatActive ~= true and NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.AllowCombatScan then
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
    if not canShoot and Bridge.HasUsableFirearmSlots(weapons) then
        local orderAllows = true
        if NPCOrderContract and NPCOrderContract.CanShoot then
            orderAllows = NPCOrderContract.CanShoot(brain) == true
        end
        if orderAllows then
            canShoot = true
            brain.ai = brain.ai or {}
            brain.ai.combatShootCapabilityOverride = true
        end
    end
    if Bridge.IsMercenaryRetaliationActive and Bridge.IsMercenaryRetaliationActive(brain) and Bridge.HasUsableFirearmSlots(weapons) then
        canShoot = true
        brain.ai = brain.ai or {}
        brain.ai.combatShootCapabilityOverride = true
        brain.ai.combatShootCapabilityReason = "retaliation"
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


    -- Stable target fast path: do not rescan every visible NPC if we still have
    -- the same valid enemy from the previous combat frame.
    local enemyMemoryOnly = false
    local enemyConfidence = 0


    -- Stage 393: while following/guarding the owner, zombies that are already
    -- chasing or touching the owner are higher priority than generic area scan.
    -- This does not add chase movement; Stage391 hold-position filtering still
    -- allows only aim/shoot/reload/face-in-place tasks.
    if not enemyCharacter and Bridge.GetMercenaryOwnerThreatZombie then
        local ownerThreat, ownerThreatKind, ownerThreatDist = Bridge.GetMercenaryOwnerThreatZombie(bandit, brain, math.max(rifleRange, pistolRange, 18))
        if ownerThreat then
            enemyCharacter = ownerThreat
            selectedEnemyKind = ownerThreatKind or "zombie"
            bestDist = ownerThreatDist or bestDist
            enemyMemoryOnly = false
            enemyConfidence = 1.0
            combat, firing, shove, maxRange = Bridge.ResolveCombatIntent(bandit, brain, enemyCharacter, selectedEnemyKind, bestDist, weapons, canMelee, canShoot, pistolRange, rifleRange, maxRange)
            enemyCharacter, selectedEnemyKind, bestDist, combat, firing, shove = Bridge.FilterCurrentTargetByMercenaryFireDiscipline(bandit, brain, enemyCharacter, selectedEnemyKind, bestDist, combat, firing, shove, enemyMemoryOnly)
            if enemyCharacter and firing == true then
                brain.ai = brain.ai or {}
                brain.ai.forceCombatNow = true
                brain.ai.combatShootCapabilityReason = "owner_zombie_threat"
            end
        end
    end

    -- Stage 392: when a hired mercenary is shot by a hostile actor, every
    -- mercenary owned by the same player prioritizes that attacker until it dies
    -- or the temporary retaliation memory expires.  This runs before normal
    -- zombie scanning, but Stage 391 hold-position combat still forbids chase.
    local retaliationEnemy, retaliationKind, retaliationDist = nil, nil, nil
    if Bridge.GetMercenaryRetaliationTarget then
        retaliationEnemy, retaliationKind, retaliationDist = Bridge.GetMercenaryRetaliationTarget(bandit, brain, 42)
    end
    if retaliationEnemy then
        enemyCharacter = retaliationEnemy
        selectedEnemyKind = retaliationKind or Bridge.TargetKind(retaliationEnemy)
        bestDist = retaliationDist or bestDist
        enemyMemoryOnly = false
        enemyConfidence = 1.0
        combat, firing, shove, maxRange = Bridge.ResolveCombatIntent(bandit, brain, enemyCharacter, selectedEnemyKind, bestDist, weapons, canMelee, canShoot, pistolRange, rifleRange, maxRange)
        enemyCharacter, selectedEnemyKind, bestDist, combat, firing, shove = Bridge.FilterCurrentTargetByMercenaryFireDiscipline(bandit, brain, enemyCharacter, selectedEnemyKind, bestDist, combat, firing, shove, enemyMemoryOnly)
    end

    local stableEnemy, stableKind, stableDist, stableCanSee, stableConfidence = nil, nil, nil, nil, nil
    if not enemyCharacter then
        stableEnemy, stableKind, stableDist, stableCanSee, stableConfidence = Bridge.GetStableCombatTarget(bandit, brain, 32)
    end
    if stableEnemy then
        enemyCharacter = stableEnemy
        selectedEnemyKind = stableKind
        bestDist = stableDist
        enemyMemoryOnly = stableCanSee == false
        enemyConfidence = tonumber(stableConfidence) or (enemyMemoryOnly and 0.55 or 1.0)
        combat, firing, shove, maxRange = Bridge.ResolveCombatIntent(bandit, brain, enemyCharacter, selectedEnemyKind, bestDist, weapons, canMelee, canShoot, pistolRange, rifleRange, maxRange)
        if enemyMemoryOnly and firing then firing = false end
        enemyCharacter, selectedEnemyKind, bestDist, combat, firing, shove = Bridge.FilterCurrentTargetByMercenaryFireDiscipline(bandit, brain, enemyCharacter, selectedEnemyKind, bestDist, combat, firing, shove, enemyMemoryOnly)
    end

    if not enemyCharacter then
        local sharedEnemy, sharedKind, sharedDist, sharedCanSee, sharedConfidence = Bridge.GetSharedSquadCombatTarget(bandit, brain, 32)
        if sharedEnemy then
            enemyCharacter = sharedEnemy
            selectedEnemyKind = sharedKind
            bestDist = sharedDist
            enemyMemoryOnly = sharedCanSee == false
            enemyConfidence = tonumber(sharedConfidence) or 0.48
            Bridge.UpdateBattlefieldMemory(bandit, brain, enemyCharacter, selectedEnemyKind, bestDist, false)
            combat, firing, shove, maxRange = Bridge.ResolveCombatIntent(bandit, brain, enemyCharacter, selectedEnemyKind, bestDist, weapons, canMelee, canShoot, pistolRange, rifleRange, maxRange)
            if enemyMemoryOnly and firing then firing = false end
            enemyCharacter, selectedEnemyKind, bestDist, combat, firing, shove = Bridge.FilterCurrentTargetByMercenaryFireDiscipline(bandit, brain, enemyCharacter, selectedEnemyKind, bestDist, combat, firing, shove, enemyMemoryOnly)
        end
    end

    -- COMBAT AGAIST PLAYERS 
    if not enemyCharacter and ((NPCFactionBridge and NPCFactionBridge.IsEnabled and NPCFactionBridge.IsEnabled()) or NPCEntity.IsHostile(bandit)) then
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
                                    maxRange = Bridge.GetMeleeRangeForBrain(brain, weapons)
                                end
                                local strikeRange = Bridge.GetMeleeStrikeRange(weapons.melee, maxRange)
                                if dist <= strikeRange then
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
        if enemyCharacter then
            enemyCharacter, selectedEnemyKind, bestDist, combat, firing, shove = Bridge.FilterCurrentTargetByMercenaryFireDiscipline(bandit, brain, enemyCharacter, selectedEnemyKind, bestDist, combat, firing, shove, enemyMemoryOnly)
        end
    end

    -- COMBAT AGAINST ZOMBIES AND NPCS FROM OTHER CLAN
    if not enemyCharacter then
    local cache = NPCZombieCacheBridge.Cache
    local scanRadius = 36
    local strictScanRadius = Bridge.GetStrictMercenaryCombatScanRadius(brain)
    local perfLevel, cameraZoom = Bridge.GetPerfLevel()
    if perfLevel >= 3 then
        scanRadius = cameraZoom >= 1.75 and 22 or 26
    elseif perfLevel >= 2 then
        scanRadius = cameraZoom >= 1.75 and 26 or 30
    end
    if strictScanRadius and tonumber(strictScanRadius) then
        scanRadius = math.min(scanRadius, tonumber(strictScanRadius))
    end
    if NPCOrderContract and NPCOrderContract.GetFireDisciplineScanRadius then
        local fireDisciplineScanRadius = NPCOrderContract.GetFireDisciplineScanRadius(brain)
        if fireDisciplineScanRadius and tonumber(fireDisciplineScanRadius) then
            scanRadius = math.min(scanRadius, tonumber(fireDisciplineScanRadius))
        end
    end
    local potentialEnemyList, potentialEnemyCount = Bridge.GetNearbyAllInto("combatNearby", zx, zy, zz, scanRadius)
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
        if potentialEnemy and potentialEnemy.z == zz and not Bridge.IsBlackMarketNoCombatBrain(potentialEnemy.brain) and Bridge.AreBrainsCombatEnemies(brain, potentialEnemy.brain) then
            local dx = potentialEnemy.x - zx
            local dy = potentialEnemy.y - zy
            local manhattan = math.abs(dx) + math.abs(dy)
            if manhattan < scanRadius then
                local d2 = dx * dx + dy * dy
                local scanRadius2 = scanRadius * scanRadius
                if d2 < math.min(625, scanRadius2) then
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

                    combat, firing, shove, maxRange = Bridge.ResolveCombatIntent(bandit, brain, enemyCharacter, selectedEnemyKind, bestDist, weapons, canMelee, canShoot, pistolRange, rifleRange, maxRange)
                end
            end
        end
    end

    end

    if enemyCharacter then
        enemyCharacter, selectedEnemyKind, bestDist, combat, firing, shove = Bridge.FilterCurrentTargetByMercenaryFireDiscipline(bandit, brain, enemyCharacter, selectedEnemyKind, bestDist, combat, firing, shove, enemyMemoryOnly)
    end

    if not enemyCharacter then
        local rememberedEnemy, rememberedKind, rememberedDist, rememberedCanSee, rememberedConfidence = Bridge.DecayBattlefieldMemory(bandit, brain, 32)
        if rememberedEnemy then
            local strictMemoryRange = Bridge.GetStrictMercenaryCombatScanRadius(brain)
            if not strictMemoryRange or not rememberedDist or rememberedDist <= strictMemoryRange then
                enemyCharacter = rememberedEnemy
                selectedEnemyKind = rememberedKind
                bestDist = rememberedDist
                enemyMemoryOnly = rememberedCanSee == false
                enemyConfidence = tonumber(rememberedConfidence) or enemyConfidence
                combat, firing, shove, maxRange = Bridge.ResolveCombatIntent(bandit, brain, enemyCharacter, selectedEnemyKind, bestDist, weapons, canMelee, canShoot, pistolRange, rifleRange, maxRange)
                if firing then firing = false end
                enemyCharacter, selectedEnemyKind, bestDist, combat, firing, shove = Bridge.FilterCurrentTargetByMercenaryFireDiscipline(bandit, brain, enemyCharacter, selectedEnemyKind, bestDist, combat, firing, shove, enemyMemoryOnly)
            end
        end
    end

    if enemyCharacter and not enemyMemoryOnly and NPCTacticalRadioBridge and NPCTacticalRadioBridge.ReportContact then
        pcall(function()
            NPCTacticalRadioBridge.ReportContact(bandit, brain, enemyCharacter, selectedEnemyKind or "unknown", bestDist, 1.0)
        end)
    end

    if enemyCharacter and not enemyMemoryOnly then
        Bridge.RememberStableCombatTarget(bandit, brain, enemyCharacter, selectedEnemyKind, bestDist)
    end

    Bridge.ApplyMercenarySuppression(brain, enemyCharacter, selectedEnemyKind, bestDist, firing)
    Bridge.TryPreemptForCombat(bandit, brain, enemyCharacter, firing, combat, shove)

    if firing and combat and not shove then
        combat = false
    end

    if enemyMemoryOnly and enemyCharacter then
        Bridge.TryPreemptForCombat(bandit, brain, enemyCharacter, true, false, false)
        if not NPCEntity.HasActionTask(bandit) and enemyCharacter.getX and enemyCharacter.getY then
            bandit:faceThisObject(enemyCharacter)
            local eid = NPCUtils.GetCharacterID(enemyCharacter)
            local targetKind = Bridge.TargetKind(enemyCharacter)
            local faceTask = {action="FaceLocation", x=enemyCharacter:getX(), y=enemyCharacter:getY(), z=enemyCharacter:getZ(), time=bridge_combatMemoryConfig("faceTaskMs", 22), targetId=eid, targetKind=targetKind, combatMove=true, routerPriority=90, force=true, director=true, directorState="CombatMemory", directorReason="hold last seen enemy"}
            table.insert(tasks, faceTask)
            return tasks
        end
    end

    if firing and enemyCharacter and selectedEnemyKind == "zombie" and bestDist < 2.35 and not NPCEntity.HasActionTask(bandit) then
        local retreatTask = Bridge.MakeRetreatTaskFromTarget(bandit, enemyCharacter, "avoid close zombie while armed", 3.6, "WalkAim")
        if retreatTask then
            shove = false
            combat = false
            table.insert(tasks, retreatTask)
            return tasks
        end
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

    if enemyCharacter and not enemyMemoryOnly and (firing or combat or shove) then
        local attackMode = firing and "fire" or "melee"
        if Bridge.ShouldUseBattleAttackSlots(bandit, brain, enemyCharacter, selectedEnemyKind, bestDist, attackMode) then
            local slotOk = Bridge.AcquireBattleAttackSlot(bandit, brain, enemyCharacter, selectedEnemyKind, attackMode)
            if not slotOk then
                firing = false
                combat = false
                shove = false
                local waitTask = Bridge.MakeBattleSlotWaitTask(bandit, brain, enemyCharacter, selectedEnemyKind, attackMode)
                if waitTask then table.insert(tasks, waitTask) end
                return tasks
            end
        end
    end

    if shove then
        if not NPCEntity.HasTaskType(bandit, "Shove") then
            NPCEntity.ClearTasks(bandit)
            local veh = enemyCharacter:getVehicle()
            if veh then NPCEntity.Say(bandit, "CAR") end

            if bandit:isFacingObject(enemyCharacter, 0.1) then
                local eid = NPCUtils.GetCharacterID(enemyCharacter)
                local targetKind = Bridge.TargetKind(enemyCharacter)
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
                if not maxRange then
                    maxRange = Bridge.GetMeleeRangeForBrain(brain, weapons)
                end
                local strikeRange = Bridge.GetMeleeStrikeRange(weapons.melee, maxRange)
                if bestDist <= strikeRange then
                    local eid = NPCUtils.GetCharacterID(enemyCharacter)
                    local targetKind = Bridge.TargetKind(enemyCharacter)
                    local task = {action="Hit", time=65, endurance=-0.03, weapon=weapons.melee, eid=eid, targetId=eid, targetKind=targetKind, x=enemyCharacter:getX(), y=enemyCharacter:getY(), z=enemyCharacter:getZ(), meleeStrikeRange=strikeRange}
                    table.insert(tasks, task)
                else
                    local moveTask = {action="Move", x=enemyCharacter:getX(), y=enemyCharacter:getY(), z=enemyCharacter:getZ(), time=90, walkType=bestDist > 2.2 and "Run" or "Walk", arriveDist=Bridge.GetMeleeApproachRange(weapons.melee, maxRange), closeSlow=false, combatMove=true, meleeApproach=true, targetId=NPCUtils.GetCharacterID(enemyCharacter), targetKind=Bridge.TargetKind(enemyCharacter), director=true, directorState="MeleeFallback", directorReason="close before melee strike"}
                    table.insert(tasks, moveTask)
                end
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
                        local weaponSlot = weapons[slot]
                        if weaponSlot and weaponSlot.name and (weaponSlot.bulletsLeft > 0 or weaponSlot.magCount > 0) then
                            if not bandit:isPrimaryEquipped(weaponSlot.name) then
                                NPCEntity.Say(bandit, "SPOTTED")

                                local stasks = NPCPrograms.Weapon.Switch(bandit, weaponSlot.name)
                                for _, t in pairs(stasks) do table.insert(tasks, t) end
                            end

                            if not NPCEntity.IsAim(bandit) then
                                local stasks = NPCPrograms.Weapon.Aim(bandit, enemyCharacter, slot)
                                for _, t in pairs(stasks) do table.insert(tasks, t) end
                            end

                            if weaponSlot.bulletsLeft > 0 then
                                local stasks = NPCPrograms.Weapon.Shoot(bandit, enemyCharacter, slot)
                                for _, t in pairs(stasks) do table.insert(tasks, t) end

                            elseif weaponSlot.magCount > 0 then
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
                    for _, slot in pairs({"primary", "secondary"}) do
                        local weaponSlot = weapons[slot]
                        if weaponSlot and weaponSlot.name and ((tonumber(weaponSlot.bulletsLeft or 0) or 0) > 0 or (tonumber(weaponSlot.magCount or 0) or 0) > 0) then
                            local aimTasks = NPCPrograms.Weapon.Aim(bandit, enemyCharacter, slot)
                            for _, t in pairs(aimTasks) do
                                t.combatMove = true
                                t.routerPriority = 90
                                table.insert(tasks, t)
                            end
                            break
                        end
                    end
                end

            elseif instanceof(enemyCharacter, "IsoPlayer") then
                local task = {action="Time", anim="Smoke", time=250}
                table.insert(tasks, task)
                NPCEntity.Say(bandit, "DEATH")
            end

        end
    end

    if #tasks == 0 and enemyCharacter and Bridge.IsLiveTarget(enemyCharacter) and not NPCEntity.HasActionTask(bandit) then
        if canMelee and weapons and weapons.melee then
            NPCEntity.ClearTasks(bandit)
            if not bandit:isPrimaryEquipped(weapons.melee) then
                local stasks = NPCPrograms.Weapon.Switch(bandit, weapons.melee)
                for _, t in pairs(stasks) do table.insert(tasks, t) end
            end

            if not maxRange then
                maxRange = Bridge.GetMeleeRangeForBrain(brain, weapons)
            end

            local strikeRange = Bridge.GetMeleeStrikeRange(weapons.melee, maxRange)
            if bestDist <= strikeRange then
                bandit:faceThisObject(enemyCharacter)
                local eid = NPCUtils.GetCharacterID(enemyCharacter)
                local targetKind = Bridge.TargetKind(enemyCharacter)
                local task = {action="Hit", time=65, endurance=-0.03, weapon=weapons.melee, eid=eid, targetId=eid, targetKind=targetKind, x=enemyCharacter:getX(), y=enemyCharacter:getY(), z=enemyCharacter:getZ(), meleeStrikeRange=strikeRange}
                table.insert(tasks, task)
            else
                local moveTask = {action="Move", x=enemyCharacter:getX(), y=enemyCharacter:getY(), z=enemyCharacter:getZ(), time=120, walkType=bestDist > 2.2 and "Run" or "Walk", arriveDist=Bridge.GetMeleeApproachRange(weapons.melee, maxRange), closeSlow=false, combatMove=true, meleeApproach=true, targetId=NPCUtils.GetCharacterID(enemyCharacter), targetKind=Bridge.TargetKind(enemyCharacter), director=true, directorState="MeleeFallback", directorReason="close for melee fallback"}
                table.insert(tasks, moveTask)
            end
        elseif bestDist < 4.5 then
            local retreatTask = Bridge.MakeRetreatTaskFromTarget(bandit, enemyCharacter, "unarmed combat retreat", 4.0, "Run")
            if retreatTask then table.insert(tasks, retreatTask) end
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
    if NPCDiagnosticsBridge and NPCDiagnosticsBridge.Log then
        NPCDiagnosticsBridge.Log("NPC_TASK_ERROR", tostring(message), {key=key}, "task-error:" .. key, true)
    else
        print("[NPCUpdate] " .. tostring(message))
    end
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

    if NPCRenderReliefBridge and NPCRenderReliefBridge.ShouldSkipCombatSound then
        local brain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(bandit) or nil
        local okSkip, skip = pcall(function() return NPCRenderReliefBridge.ShouldSkipCombatSound(bandit, brain, sound) end)
        if okSkip and skip == true then return end
    end

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

        if NPCActionRouterBridge and NPCActionRouterBridge.OnTaskStart then
            local okRouter, allowTask = pcall(function()
                return NPCActionRouterBridge.OnTaskStart(bandit, task)
            end)
            if okRouter and allowTask == false then
                if NPCEntity and NPCEntity.RemoveTask then NPCEntity.RemoveTask(bandit) end
                return
            end
        end

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
            if NPCDiagnosticsBridge and NPCDiagnosticsBridge.TraceTaskTransition then
                local brain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(bandit) or nil
                NPCDiagnosticsBridge.TraceTaskTransition(bandit, brain, task, "NEW", "WORKING", "onStart", false)
            end
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
            if NPCDiagnosticsBridge and NPCDiagnosticsBridge.TraceTaskTransition then
                local brain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(bandit) or nil
                NPCDiagnosticsBridge.TraceTaskTransition(bandit, brain, task, "WORKING", "COMPLETED", done and "onWorking" or "time", false)
            end
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
            if NPCDiagnosticsBridge and NPCDiagnosticsBridge.TraceTaskTransition then
                local brain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(bandit) or nil
                NPCDiagnosticsBridge.TraceTaskTransition(bandit, brain, task, "COMPLETED", "REMOVED", "onComplete", false)
            end
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

function Bridge.IsB41Runtime()
    if NPCCompatibilityBridge and NPCCompatibilityBridge.GetGameVersion then
        local okVersion, version = pcall(function() return NPCCompatibilityBridge.GetGameVersion() end)
        return okVersion and (tonumber(version) or 42) < 42
    end
    return false
end

function Bridge.GetZombieNPCPressureLevel()
    local level, zoom = Bridge.GetPerfLevel()
    return tonumber(level) or 0, tonumber(zoom) or 1
end

function Bridge.ShouldRefreshZombieNPCTarget(zombie, bandit, enemy, intervalMs, sameTargetMs)
    if not (zombie and bandit) then return true end

    local now = Bridge.NowMs()
    local targetId = enemy and enemy.id or nil
    if targetId == nil and NPCUtils and NPCUtils.GetZombieID then
        local okId, gotId = pcall(function() return NPCUtils.GetZombieID(bandit) end)
        if okId then targetId = gotId end
    end
    local key = tostring(targetId or bandit)
    if not Bridge.AllowZombieNPCTargetRefresh(zombie, key) then return false end

    local state = Bridge.GetZombieNPCIntentThrottleState and Bridge.GetZombieNPCIntentThrottleState(zombie, true) or nil
    if state then
        local lastAt = tonumber(state.engageAt)
        if lastAt then
            local elapsed = now - lastAt
            if elapsed < (tonumber(intervalMs) or 2200) then return false end
            if state.engageKey == key and elapsed < (tonumber(sameTargetMs) or 6200) then return false end
        end
        state.engageAt = now
        state.engageKey = key
        return true
    end

    if not zombie.getModData then return true end
    local md = zombie:getModData()
    if not md then return true end

    local lastAt = tonumber(md.NPC_ZOMBIE_NPC_ENGAGE_AT)
    if lastAt then
        local elapsed = now - lastAt
        if elapsed < (tonumber(intervalMs) or 2200) then return false end
        if md.NPC_ZOMBIE_NPC_ENGAGE_KEY == key and elapsed < (tonumber(sameTargetMs) or 6200) then return false end
    end

    md.NPC_ZOMBIE_NPC_ENGAGE_AT = now
    md.NPC_ZOMBIE_NPC_ENGAGE_KEY = key
    return true
end

function Bridge.CanZombiePathToNPC(zombie, enemy, cooldownMs, sameTargetCooldownMs)
    if not (zombie and enemy and enemy.x and enemy.y) then return false end

    local state = Bridge.GetZombieNPCIntentThrottleState and Bridge.GetZombieNPCIntentThrottleState(zombie, true) or nil
    local md = nil
    if not state then
        if not zombie.getModData then return false end
        md = zombie:getModData()
        if not md then return false end
    end

    local now = Bridge.NowMs()
    cooldownMs = tonumber(cooldownMs) or 3000
    sameTargetCooldownMs = tonumber(sameTargetCooldownMs) or 7000

    local isB41 = Bridge.IsB41Runtime()
    local perfLevel, cameraZoom = Bridge.GetZombieNPCPressureLevel()
    if isB41 then
        -- In B41, waking normal zombies against NPC-zombies can create a burst of
        -- internal path2 work even when the Lua side does not call pathToLocationF.
        -- Keep zombie-vs-NPC functional, but spread retargets over time.
        cooldownMs = math.max(cooldownMs, 10500)
        sameTargetCooldownMs = math.max(sameTargetCooldownMs, 26000)
    end
    if perfLevel >= 3 or cameraZoom >= 1.90 then
        cooldownMs = math.max(cooldownMs, isB41 and 18000 or 7000)
        sameTargetCooldownMs = math.max(sameTargetCooldownMs, isB41 and 36000 or 14000)
    elseif perfLevel >= 2 or cameraZoom >= 1.45 then
        cooldownMs = math.max(cooldownMs, isB41 and 14000 or 4500)
        sameTargetCooldownMs = math.max(sameTargetCooldownMs, isB41 and 30000 or 10000)
    end

    local z = enemy.z or (zombie.getZ and zombie:getZ()) or 0
    local key = tostring(enemy.id or "") .. ":" .. tostring(math.floor(enemy.x)) .. ":" .. tostring(math.floor(enemy.y)) .. ":" .. tostring(math.floor(z or 0))
    local lastAt
    local lastKey
    if state then
        lastAt = tonumber(state.pathAt)
        lastKey = state.pathKey
    else
        lastAt = tonumber(md[NPC_LEGACY_KEYS.ZOMBIE_PATH_AT])
        lastKey = md[NPC_LEGACY_KEYS.ZOMBIE_PATH_KEY]
    end
    local elapsed = lastAt and (now - lastAt) or nil

    if elapsed then
        if elapsed < cooldownMs then return false end
        if lastKey == key and elapsed < sameTargetCooldownMs then return false end
    end

    if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.AllowPathRequest then
        local zid = key
        if NPCUtils and NPCUtils.GetZombieID then
            local okId, retId = pcall(function() return NPCUtils.GetZombieID(zombie) end)
            if okId and retId ~= nil then zid = retId end
        end
        if not NPCWorkSchedulerBridge.AllowPathRequest(zid, "zombie_bandit", "zombie") then
            if state then
                state.pathDeniedAt = now
            else
                md[NPC_LEGACY_KEYS.ZOMBIE_PATH_DENIED_AT] = now
            end
            return false
        end
    end

    if state then
        state.pathAt = now
        state.pathKey = key
    else
        md[NPC_LEGACY_KEYS.ZOMBIE_PATH_AT] = now
        md[NPC_LEGACY_KEYS.ZOMBIE_PATH_KEY] = key
    end
    return true
end


function Bridge.GetClosestPlayerObject(character, maxDist)
    if not character then return nil end
    local best = nil
    local bestD2 = nil
    local cx = character.getX and character:getX() or 0
    local cy = character.getY and character:getY() or 0
    maxDist = tonumber(maxDist) or 48
    local maxD2 = maxDist * maxDist

    local function consider(player)
        if not (player and player.getX and player.getY) then return end
        if NPCPlayerClient and NPCPlayerClient.IsGhost and NPCPlayerClient.IsGhost(player) then return end
        if player.isDead and player:isDead() then return end
        local dx = cx - player:getX()
        local dy = cy - player:getY()
        local d2 = dx * dx + dy * dy
        if d2 <= maxD2 and (not bestD2 or d2 < bestD2) then
            best = player
            bestD2 = d2
        end
    end

    if NPCPlayerClient and NPCPlayerClient.GetPlayers then
        local okPlayers, players = pcall(function() return NPCPlayerClient.GetPlayers() end)
        if okPlayers and players and players.size and players.get then
            for i = 0, players:size() - 1 do consider(players:get(i)) end
        end
    end
    if not best and getSpecificPlayer then consider(getSpecificPlayer(0)) end
    return best
end

function Bridge.EngageZombieWithNPC(zombie, bandit, enemy, usePlayerStimulus)
    if not (zombie and bandit and bandit.isAlive and bandit:isAlive()) then return false end

    local isB41 = Bridge.IsB41Runtime()
    local currentTarget = zombie.getTarget and zombie:getTarget() or nil
    local level, zoom = Bridge.GetZombieNPCPressureLevel()
    local intervalMs = isB41 and (level >= 3 and 5200 or (level >= 2 and 4200 or 3000)) or 1200
    local sameMs = isB41 and (level >= 3 and 22000 or (level >= 2 and 18000 or 12000)) or 3600
    if not Bridge.ShouldRefreshZombieNPCTarget(zombie, bandit, enemy, intervalMs, sameMs) then
        return true
    end

    pcall(function() zombie:setTarget(bandit) end)
    pcall(function() zombie:setAttackedBy(bandit) end)
    if zombie.addAggro then pcall(function() zombie:addAggro(bandit, isB41 and 1.0 or 3.0) end) end
    if zombie.setVariable then pcall(function() zombie:setVariable("ZombieBiteDone", false) end) end
    if zombie.setNoTeeth then pcall(function() zombie:setNoTeeth(false) end) end

    -- On B41 MP, zombie:spotted(player,true) can wake the vanilla WalkToward path2
    -- state and then our immediate NPC retarget creates the repeated
    -- "WalkTowardState but path2 != null" warning bursts seen in the logs.
    -- Keep the stimulus only for newer runtimes.
    if not isB41 and usePlayerStimulus == true and zombie.spotted then
        local player = Bridge.GetClosestPlayerObject(zombie, 56)
        if player then
            pcall(function() zombie:spotted(player, true) end)
            pcall(function() zombie:setTarget(bandit) end)
            pcall(function() zombie:setAttackedBy(bandit) end)
        end
    end
    return true
end

function Bridge.ShouldFastZombieNPCUpdate(zombie, uTick)
    if not Bridge.IsZombieNPCAggroEnabled() then return false end
    if not (zombie and zombie.getVariableBoolean) then return false end
    if zombie:getVariableBoolean(NPC_LEGACY_KEYS.FLAG) then return false end

    local level = 0
    if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.GetLoadLevel then
        local okLevel, gotLevel = pcall(function() return NPCWorkSchedulerBridge.GetLoadLevel(false) end)
        if okLevel then level = tonumber(gotLevel) or 0 end
    end

    local zid = NPCUtils and NPCUtils.GetZombieID and NPCUtils.GetZombieID(zombie) or tostring(zombie)
    local target = zombie.getTarget and zombie:getTarget() or nil
    if target and target.getVariableBoolean and target:getVariableBoolean(NPC_LEGACY_KEYS.FLAG) then
        local interval = level >= 3 and 18 or (level >= 2 and 12 or (level >= 1 and 8 or 4))
        if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.CanRun and NPCWorkSchedulerBridge.GetBudget then
            return NPCWorkSchedulerBridge.CanRun("zombie", "target-npc:" .. tostring(zid), interval, NPCWorkSchedulerBridge.GetBudget("zombie"), uTick)
        end
        return (tonumber(uTick) or 0) % interval == 0
    end

    local interval = level >= 3 and 12 or (level >= 2 and 8 or 6)
    if (tonumber(uTick) or 0) % interval ~= 0 then return false end

    if NPCSpatialIndexBridge and NPCSpatialIndexBridge.GetClosestNPCLocation then
        local configuredRadius = Bridge.GetZombieNPCNumber("ZombieNPC_VisualChaseRadius", 24, 4, 80)
        local radius = level >= 3 and math.min(configuredRadius, 8) or (level >= 2 and math.min(configuredRadius, 12) or math.min(configuredRadius, 16))
        local hearingRadius = nil
        local okEnemy, enemy = pcall(function() return NPCSpatialIndexBridge.GetClosestNPCLocation(zombie, radius) end)
        if not (okEnemy and enemy and enemy.dist and enemy.dist <= radius) then
            hearingRadius = Bridge.GetZombieNPCNumber("ZombieNPC_HearingRadius", 36, 4, 120)
            if level >= 3 then hearingRadius = math.min(hearingRadius, 16) elseif level >= 2 then hearingRadius = math.min(hearingRadius, 24) end
            enemy = Bridge.GetRecentNPCShotMemoryEnemy(zombie, hearingRadius)
        end
        if not (enemy and enemy.dist and enemy.dist <= math.max(radius, 1)) and not (enemy and enemy.noise == true) then return false end
        local allowed = true
        if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.CanRun and NPCWorkSchedulerBridge.GetBudget then
            allowed = NPCWorkSchedulerBridge.CanRun("zombie", "near-npc:" .. tostring(zid), interval, NPCWorkSchedulerBridge.GetBudget("zombie"), uTick)
        end
        if allowed and Bridge.StoreZombieNPCTargetHint then
            Bridge.StoreZombieNPCTargetHint(zombie, enemy, enemy.noise == true and hearingRadius or radius)
        end
        return allowed == true
    end
    return false
end

function Bridge.PathZombieToNPC(zombie, enemy, cooldownMs, sameTargetCooldownMs)
    if not Bridge.CanZombiePathToNPC(zombie, enemy, cooldownMs, sameTargetCooldownMs) then return false end
    if not (zombie and enemy and enemy.x and enemy.y) then return false end

    -- PZ 41 MP logs `WalkTowardState but path2 != null` when normal zombies
    -- are repeatedly given explicit path2 goals. Target/aggro is enough here;
    -- keep explicit pathing only for newer builds where the warning is fixed.
    local isB41 = Bridge.IsB41Runtime()
    if isB41 then
        local bandit = NPCZombieCacheBridge and NPCZombieCacheBridge.Cache and enemy.id and NPCZombieCacheBridge.Cache[enemy.id] or nil
        if bandit then
            Bridge.EngageZombieWithNPC(zombie, bandit, enemy, true)
        end
        return true
    end

    if not zombie.pathToLocationF then return false end
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
    damage = damage * Bridge.GetZombieNPCNumber("ZombieNPC_DamageMultiplier", 1.0, 0.05, 10.0)
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

    if not Bridge.IsZombieNPCAggroEnabled() then return end

    -- Keep vanilla lunge/bodydamage suppressed for NPC-zombie actors; Stage 360
    -- only controls the safe visual bump/bite layer below.
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

    -- Clear invalid target. `CanSee` is expensive when many vanilla zombies are visible;
    -- under render pressure, keep the current target until the LOS budget allows a check.
    if target and not target:isAlive() then
        zombie:setTarget(nil)
    elseif target then
        local zidForLOS = NPCUtils and NPCUtils.GetZombieID and NPCUtils.GetZombieID(zombie) or tostring(zombie)
        if not NPCWorkSchedulerBridge or not NPCWorkSchedulerBridge.AllowLOS or NPCWorkSchedulerBridge.AllowLOS("vanilla-zombie-target:" .. tostring(zidForLOS), "target") then
            if not zombie:CanSee(target) then zombie:setTarget(nil) end
        end
    end

    -- Stop sound if playing
    local emitter = zombie:getEmitter()
    if emitter:isPlaying("ChainsawIdle") then
        emitter:stopSoundByName("ChainsawIdle")
    end

    -- Fetch zombie coordinates and closest bandit location. The spatial index keeps
    -- zombie targeting from becoming O(zombies * bandits) in large fights.
    local zx, zy, zz = zombie:getX(), zombie:getY(), zombie:getZ()
    local zidForPath = NPCUtils and NPCUtils.GetZombieID and NPCUtils.GetZombieID(zombie) or tostring(zombie)
    local enemy
    local configuredAggroRadius = Bridge.GetZombieNPCNumber("ZombieNPC_AggroRadius", 26, 4, 90)
    local configuredHearingRadius = Bridge.GetZombieNPCNumber("ZombieNPC_HearingRadius", 36, 4, 120)
    local configuredVisualRadius = Bridge.GetZombieNPCNumber("ZombieNPC_VisualChaseRadius", 24, 4, 90)
    local zombieNpcRadius = configuredAggroRadius
    local perfLevel, cameraZoom = Bridge.GetPerfLevel()
    if perfLevel >= 3 then
        zombieNpcRadius = math.min(configuredAggroRadius, cameraZoom >= 1.75 and 12 or 16)
        configuredHearingRadius = math.min(configuredHearingRadius, 18)
    elseif perfLevel >= 2 then
        zombieNpcRadius = math.min(configuredAggroRadius, cameraZoom >= 1.75 and 18 or 22)
        configuredHearingRadius = math.min(configuredHearingRadius, 26)
    elseif perfLevel >= 1 and cameraZoom >= 1.90 then
        zombieNpcRadius = math.min(configuredAggroRadius, 22)
    end
    if Bridge.GetZombieCurrentNPCTargetEnemy then
        enemy = Bridge.GetZombieCurrentNPCTargetEnemy(zombie, zombieNpcRadius)
    end
    if not enemy and Bridge.GetZombieNPCTargetHint then
        enemy = Bridge.GetZombieNPCTargetHint(zombie, zombieNpcRadius, configuredHearingRadius)
    end
    if not enemy then
        if NPCSpatialIndexBridge and NPCSpatialIndexBridge.GetClosestNPCLocation then
            enemy = NPCSpatialIndexBridge.GetClosestNPCLocation(zombie, zombieNpcRadius)
        else
            enemy = NPCUtils.GetClosestNPCLocationFast(zombie)
        end
        local noiseEnemy = Bridge.GetRecentNPCShotMemoryEnemy(zombie, configuredHearingRadius)
        if noiseEnemy and (not enemy or not enemy.dist or enemy.dist > configuredVisualRadius or noiseEnemy.dist < enemy.dist) then
            enemy = noiseEnemy
        end
        if enemy and Bridge.StoreZombieNPCTargetHint then
            Bridge.StoreZombieNPCTargetHint(zombie, enemy, enemy.noise == true and configuredHearingRadius or zombieNpcRadius)
        end
    end

    if enemy and enemy.id and NPCZombieCacheBridge and NPCZombieCacheBridge.Cache then
        local enemyNPC = NPCZombieCacheBridge.Cache[enemy.id] or NPCZombieCacheBridge.Cache[tostring(enemy.id)] or enemy.targetObj
        if enemyNPC and NPCBlackMarketBridge and NPCBlackMarketBridge.IsNoCombatCharacter and NPCBlackMarketBridge.IsNoCombatCharacter(enemyNPC) then return end
    end

    -- If bandit is in range, proceed
    if enemy and enemy.dist and (enemy.dist < zombieNpcRadius or enemy.noise == true) then
        local player = NPCUtils.GetClosestPlayerLocation(zombie, true)
        
        -- Skip if player is closer than the bandit. NPC gunfire can still be heard
        -- from farther away, but it must not steal zombies already chasing a player.
        if player and player.dist and player.dist < enemy.dist then return end

        local bandit = NPCZombieCacheBridge.Cache[enemy.id] or NPCZombieCacheBridge.Cache[tostring(enemy.id)] or enemy.targetObj
        if not bandit or not bandit:isAlive() then return end

        -- Standard movement if bandit is far.
        -- In MP/PZ41 pathToCharacter() on a bandit-zombie can spam
        -- NetworkZombieMind.set: goal character is not set. Use a location goal
        -- instead; close combat still assigns target below.
        if enemy.dist > 6 then
            local allowLOS = not NPCWorkSchedulerBridge or not NPCWorkSchedulerBridge.AllowLOS or NPCWorkSchedulerBridge.AllowLOS("vanilla-zombie-path:" .. tostring(zidForPath), "path-to-npc")
            local canSeeNPC = allowLOS and zombie:CanSee(bandit)
            local currentTarget = zombie.getTarget and zombie:getTarget() or nil
            local heardNPC = enemy.noise == true and enemy.dist <= configuredHearingRadius
            if canSeeNPC or currentTarget == bandit or enemy.dist < math.min(configuredVisualRadius, 16) or heardNPC then
                Bridge.EngageZombieWithNPC(zombie, bandit, enemy, canSeeNPC == true or heardNPC == true)
                Bridge.PathZombieToNPC(zombie, enemy, heardNPC and 1800 or 2600, heardNPC and 3600 or 5200)
            end

        -- Approach bandit if in range
        elseif enemy.dist >= 0.59 then
            local allowLOS = not NPCWorkSchedulerBridge or not NPCWorkSchedulerBridge.AllowLOS or NPCWorkSchedulerBridge.AllowLOS("vanilla-zombie-close:" .. tostring(zidForPath), "close-to-npc")
            if allowLOS and zombie:CanSee(bandit) then
                if not Bridge.IsB41Runtime() then
                    Bridge.PathZombieToNPC(zombie, enemy, 1800, 3600)
                end
                Bridge.EngageZombieWithNPC(zombie, bandit, enemy, true)
            end

        -- Bite range attack
        elseif enemy.dist < 0.59 and enemy.z == zz then
            local isWallTo = zombie:getSquare():isSomethingTo(bandit:getSquare())
            if not isWallTo then
                if zombie:isFacingObject(bandit, 0.3) then
                    -- Optimized close-range attack logic. Stage 425 reuses a short
                    -- pressure cache per target NPC so each biting zombie does not repeat
                    -- the same nearby-zombie bucket scan in the same small time slice.
                    local attackingZombiesNumber = Bridge.GetZombieNPCBitePressure and Bridge.GetZombieNPCBitePressure(enemy) or 0
                    if attackingZombiesNumber == nil then attackingZombiesNumber = 0 end

                    -- Zombies use a custom NPC damage path here. Vanilla bodydamage is
                    -- still bypassed, but Stage 360 lets the visual bump/bite layer run
                    -- when the server enables ZombieNPC_AttackVisualsEnabled.
                    if Bridge.IsZombieNPCAttackVisualsEnabled() then
                        zombie:setBumpType("Bite")
                    else
                        zombie:setBumpType("")
                    end
                    local biteBrain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(bandit) or nil
                    local skipBiteSound = false
                    if NPCRenderReliefBridge and NPCRenderReliefBridge.ShouldSkipCombatSound then
                        local okSound, retSound = pcall(function() return NPCRenderReliefBridge.ShouldSkipCombatSound(bandit, biteBrain, "ZombieBite") end)
                        skipBiteSound = okSound and retSound == true
                    end
                    if not skipBiteSound then
                        if ZombRand(4) == 1 then
                            bandit:playSound("ZombieScratch")
                        else
                            bandit:playSound("ZombieBite")
                        end
                    end

                    local skipBiteSplat = false
                    if NPCRenderReliefBridge and NPCRenderReliefBridge.ShouldSkipCombatSplat then
                        local okSplat, retSplat = pcall(function() return NPCRenderReliefBridge.ShouldSkipCombatSplat(bandit, biteBrain, "ZombieBite") end)
                        skipBiteSplat = okSplat and retSplat == true
                    end
                    if not skipBiteSplat then
                        local teeth = NPCCompatibilityBridge.InstanceItem("Base.RollingPin")
                        NPCCompatibilityBridge.Splash(bandit, teeth, zombie)
                    end
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



bridge_normMercenaryOrderName = function(name)
    name = tostring(name or "")
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

local function bridge_isStrictMercenaryOrderName(name)
    name = bridge_normMercenaryOrderName(name)
    return name == "Follow" or name == "Hold" or name == "Guard" or name == "FallBack" or name == "Return"
end

local function bridge_isTacticalMercenaryOrderName(name)
    name = bridge_normMercenaryOrderName(name)
    return name == "Flank" or name == "Encircle" or name == "BackToBack" or name == "TakeCover" or name == "Advance" or name == "FallBack" or name == "WatchSector"
end

local function bridge_nowMercenaryHours()
    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then
            local ok, value = pcall(function() return gt:getWorldAgeHours() end)
            if ok and tonumber(value) then return tonumber(value) end
        end
    end
    return 0
end

function Bridge.EnsurePlayerCommandAuthorityRuntime(brain)
    if type(brain) ~= "table" then return false end
    local commanded = brain.commandAuthority == "player" or brain.playerCommandAuthority == true or brain.mercenaryDirectOrders == true
    if not commanded then return false end

    brain.commandAuthority = "player"
    brain.playerCommandAuthority = true
    brain.worldCommandDisabled = true
    brain.worldDirectorDisabled = true
    brain.livingWorldDisabled = true
    brain.autonomousWorldDisabled = true
    brain.master = brain.master or brain.mercenaryHiredBy

    local order = brain.order
    if type(order) ~= "table" or not order.name or order.name == "Auto" then
        local now = bridge_nowMercenaryHours()
        brain.ai = brain.ai or {}
        brain.ai.mercenaryDirectOrderSequence = (tonumber(brain.ai.mercenaryDirectOrderSequence) or 0) + 1
        order = {
            name="Follow",
            source="mercenary_direct",
            commandAuthority="player",
            playerCommand=true,
            playerCommandMode="mercenary_direct",
            mercenaryDirect=true,
            directMercenaryOrder=true,
            master=brain.master or brain.mercenaryHiredBy,
            issued=now,
            sequence=brain.ai.mercenaryDirectOrderSequence,
            priority=120,
            fireMode="Defensive",
            formation="close",
            followDistance=0.95,
            sticky=true,
            strict=true,
            leash={follow=3.6, guard=10.0, hold=3.0, combat=4.0},
            immediateReapply=true,
            immediateReapplySequence=brain.ai.mercenaryDirectOrderSequence,
            immediateReapplyUntil=now + (3.8 / 3600),
            immediateReapplyReason="runtime mercenary direct fallback",
            dispatchMode="mercenary_direct",
            forceImmediate=true
        }
        brain.order = order
    else
        order.source = "mercenary_direct"
        order.commandAuthority = "player"
        order.playerCommand = true
        order.playerCommandMode = "mercenary_direct"
        order.mercenaryDirect = true
        order.directMercenaryOrder = true
        order.dispatchMode = "mercenary_direct"
        order.forceImmediate = true
        if bridge_isStrictMercenaryOrderName(order.name) then
            order.sticky = true
            order.strict = true
            order.leash = order.leash or {follow=6.5, guard=10.0, hold=3.0, combat=6.5}
        end
    end
    brain.orderSystem = "mercenary_direct"
    return true
end
function Bridge.IsManualMercenaryOrderPending(brain)
    if type(brain) ~= "table" then return false, nil end
    if brain.mercenaryHired ~= true and brain.commandAuthority ~= "player" and brain.playerCommandAuthority ~= true then return false, nil end

    local order = type(brain.order) == "table" and brain.order or nil
    if type(order) ~= "table" then return false, nil end
    local direct = order.mercenaryDirect == true or order.directMercenaryOrder == true or brain.orderSystem == "mercenary_direct" or brain.mercenaryDirectOrders == true
    if not direct and order.source ~= "player" and order.interrupt ~= true then return false, nil end

    local issued = tonumber(order.issued or order.interruptIssued) or 0
    local revision = tonumber(order.orderRevision or order.groupOrderRevision or brain.orderRevision or brain.groupOrderRevision or brain.mercenaryOrderRevision)
    local sequence = tonumber(order.sequence)
    brain.ai = brain.ai or {}
    if revision then
        local consumedRev = tonumber(brain.ai.manualOrderConsumedRevision) or -1
        if revision <= consumedRev and brain.ai.forceManualOrderNow ~= true then return false, order end
    elseif sequence then
        local consumedSeq = tonumber(brain.ai.manualOrderConsumedSequence) or -1
        if sequence <= consumedSeq and brain.ai.forceManualOrderNow ~= true then return false, order end
    else
        local consumed = tonumber(brain.ai.manualOrderConsumedIssued) or -1
        if issued <= consumed and brain.ai.forceManualOrderNow ~= true then return false, order end
    end
    return true, order
end
function Bridge.IsManualOrderTaskInterruptible(task)
    if type(task) ~= "table" then return true end
    local action = tostring(task.action or "")
    if action == "Die" or action == "Zombify" then return false end
    if action == "Time" then
        local anim = tostring(task.anim or "")
        if anim == "GetUp" or anim == "Fall" or anim == "Death" then return false end
    end
    return true
end


function Bridge.GetMercenaryOrderRuntimeToken(brain, order)
    if type(order) ~= "table" then return nil end
    local revision = tonumber(order.orderRevision or order.groupOrderRevision or (type(brain) == "table" and (brain.orderRevision or brain.groupOrderRevision or brain.mercenaryOrderRevision)) or nil)
    if revision then return "r:" .. tostring(revision) end
    local sequence = tonumber(order.sequence)
    if sequence then return "s:" .. tostring(sequence) end
    local issued = tonumber(order.issued or order.interruptIssued) or 0
    return tostring(order.name or "") .. ":" .. tostring(issued)
end


function Bridge.ResetMercenaryAnimationState(bandit, reason)
    if not bandit then return false end
    if bandit.setBumpType then pcall(function() bandit:setBumpType("Idle") end) end
    if bandit.setBumpDone then pcall(function() bandit:setBumpDone(true) end) end
    if bandit.setVariable then
        pcall(function() bandit:setVariable("bMoving", false) end)
        pcall(function() bandit:setVariable("bPathfind", false) end)
        pcall(function() bandit:setVariable("BumpAnimFinished", true) end)
        pcall(function() bandit:setVariable("ZombieBiteDone", false) end)
        pcall(function() bandit:setVariable("hitreaction", "") end)
        -- Stage 390: search/forage/loot animations may leave the zombie-player
        -- proxy in a crouched locomotion blend.  Reset only animation variables;
        -- do not alter the direct movement lane/path target itself.
        pcall(function() bandit:setVariable("bCrouch", false) end)
        pcall(function() bandit:setVariable("bCrouching", false) end)
        pcall(function() bandit:setVariable("Crouch", false) end)
        pcall(function() bandit:setVariable("IsCrouching", false) end)
        pcall(function() bandit:setVariable("bSneak", false) end)
        pcall(function() bandit:setVariable("bAim", false) end)
        pcall(function() bandit:setVariable("IsAiming", false) end)
        pcall(function() bandit:setVariable("SitGroundStarted", false) end)
        pcall(function() bandit:setVariable("SitGroundAnim", "") end)
    end
    if bandit.setSneaking then pcall(function() bandit:setSneaking(false) end) end
    if bandit.setCrawling then pcall(function() bandit:setCrawling(false) end) end
    if bandit.setIgnoreMovement then pcall(function() bandit:setIgnoreMovement(false) end) end
    return true
end

local function bridge_itemFullType(item)
    if not item then return nil end
    if item.getFullType then
        local ok, value = pcall(function() return item:getFullType() end)
        if ok and value and tostring(value) ~= "" then return tostring(value) end
    end
    if item.getType then
        local ok, value = pcall(function() return item:getType() end)
        if ok and value and tostring(value) ~= "" then return tostring(value) end
    end
    return nil
end

local function bridge_itemIsRangedWeapon(item)
    if not item then return false end
    for _, method in ipairs({"isAimedFirearm", "isRanged", "isTwoHandWeapon"}) do
        if item[method] then
            local ok, value = pcall(function() return item[method](item) end)
            if ok and value == true and method ~= "isTwoHandWeapon" then return true end
        end
    end
    if item.getAmmoType then
        local ok, value = pcall(function() return item:getAmmoType() end)
        if ok and value and tostring(value) ~= "" then return true end
    end
    if item.getSubCategory then
        local ok, value = pcall(function() return item:getSubCategory() end)
        value = ok and tostring(value or ""):lower() or ""
        if value:find("firearm", 1, true) or value:find("gun", 1, true) then return true end
    end
    local ft = tostring(bridge_itemFullType(item) or ""):lower()
    return ft:find("pistol", 1, true) or ft:find("rifle", 1, true) or ft:find("shotgun", 1, true) or ft:find("revolver", 1, true)
end

function Bridge.FindMercenaryInventoryWeaponItem(bandit, preferredFullType)
    if not (bandit and bandit.getInventory) then return nil end
    local okInv, inv = pcall(function() return bandit:getInventory() end)
    if not (okInv and inv) then return nil end

    if preferredFullType and inv.FindAndReturn then
        local okFind, item = pcall(function() return inv:FindAndReturn(tostring(preferredFullType)) end)
        if okFind and item then return item end
    end

    local items = nil
    if inv.getItems then
        local okItems, got = pcall(function() return inv:getItems() end)
        if okItems then items = got end
    end
    if not (items and items.size and items.get) then return nil end

    local best = nil
    local bestScore = -1
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item and bridge_itemIsRangedWeapon(item) then
            local score = 10
            local ft = bridge_itemFullType(item)
            if preferredFullType and ft and tostring(ft) == tostring(preferredFullType) then score = score + 1000 end
            if item.getMaxRange then
                local okRange, range = pcall(function() return item:getMaxRange() end)
                if okRange and tonumber(range) then score = score + tonumber(range) end
            end
            if item.getCurrentAmmoCount then
                local okAmmo, ammo = pcall(function() return item:getCurrentAmmoCount() end)
                if okAmmo and tonumber(ammo) and tonumber(ammo) > 0 then score = score + 50 end
            end
            if score > bestScore then best, bestScore = item, score end
        end
    end
    return best
end

function Bridge.RestoreMercenaryWeaponAfterHoldFire(bandit, brain, order)
    if not (bandit and type(order) == "table") then return false end
    local fireMode = tostring(order.fireMode or "")
    if fireMode == "" and NPCOrderContract and NPCOrderContract.GetFireMode then
        fireMode = tostring(NPCOrderContract.GetFireMode(brain) or "")
    end
    if NPCOrderContract and NPCOrderContract.NormalizeFireMode then fireMode = NPCOrderContract.NormalizeFireMode(fireMode) end
    local retaliationActive = Bridge.IsMercenaryRetaliationActive and Bridge.IsMercenaryRetaliationActive(brain) == true
    if (fireMode == "HoldFire" or fireMode == "MeleeOnly") and retaliationActive ~= true then return false end
    if not (fireMode == "FireAtWill" or fireMode == "Defensive" or fireMode == "ReturnFire" or fireMode == "DangerClose" or fireMode == "Suppress" or retaliationActive == true) then return false end

    local current = nil
    if bandit.getPrimaryHandItem then
        local ok, item = pcall(function() return bandit:getPrimaryHandItem() end)
        if ok then current = item end
    end
    if current ~= nil then return false end

    local preferred = brain and brain.ai and (brain.ai.holdFireLastPrimaryFullType or brain.ai.holdFireLastSecondaryFullType) or nil
    local item = Bridge.FindMercenaryInventoryWeaponItem and Bridge.FindMercenaryInventoryWeaponItem(bandit, preferred) or nil
    if not item then return false end

    local changed = false
    if bandit.setPrimaryHandItem then
        local ok = pcall(function() bandit:setPrimaryHandItem(item) end)
        changed = ok == true
    end
    if changed and bandit.setSecondaryHandItem then
        pcall(function() bandit:setSecondaryHandItem(item) end)
    end
    if changed and bandit.setVariable then
        local ft = bridge_itemFullType(item) or ""
        pcall(function() bandit:setVariable(NPC_LEGACY_KEYS.PRIMARY, ft) end)
        pcall(function() bandit:setVariable(NPC_LEGACY_KEYS.SECONDARY, ft) end)
    end
    if changed and brain then
        brain.ai = brain.ai or {}
        brain.ai.holdFireReequippedAtMs = Bridge.NowMs and Bridge.NowMs() or (getTimestampMs and getTimestampMs() or 0)
        brain.ai.holdFireReequippedFullType = bridge_itemFullType(item)
    end
    return changed
end

function Bridge.ApplyMercenaryFireModeEquipment(bandit, brain, order)
    if not (bandit and type(order) == "table") then return false end
    local fireMode = tostring(order.fireMode or "")
    if NPCOrderContract and NPCOrderContract.NormalizeFireMode then fireMode = NPCOrderContract.NormalizeFireMode(fireMode) end
    if fireMode ~= "HoldFire" or (Bridge.IsMercenaryRetaliationActive and Bridge.IsMercenaryRetaliationActive(brain) == true) then
        return Bridge.RestoreMercenaryWeaponAfterHoldFire and Bridge.RestoreMercenaryWeaponAfterHoldFire(bandit, brain, order) or false
    end
    local changed = false
    if brain then brain.ai = brain.ai or {} end
    if bandit.getPrimaryHandItem and bandit.setPrimaryHandItem then
        local ok, item = pcall(function() return bandit:getPrimaryHandItem() end)
        if ok and item ~= nil then
            if brain then brain.ai.holdFireLastPrimaryFullType = bridge_itemFullType(item) end
            pcall(function() bandit:setPrimaryHandItem(nil) end)
            changed = true
        end
    end
    if bandit.getSecondaryHandItem and bandit.setSecondaryHandItem then
        local ok, item = pcall(function() return bandit:getSecondaryHandItem() end)
        if ok and item ~= nil then
            if brain then brain.ai.holdFireLastSecondaryFullType = bridge_itemFullType(item) end
            pcall(function() bandit:setSecondaryHandItem(nil) end)
            changed = true
        end
    end
    if bandit.setVariable then
        pcall(function() bandit:setVariable(NPC_LEGACY_KEYS.PRIMARY, "") end)
        pcall(function() bandit:setVariable(NPC_LEGACY_KEYS.SECONDARY, "") end)
    end
    if brain then
        brain.ai = brain.ai or {}
        brain.ai.holdFireUnequippedAtMs = Bridge.NowMs and Bridge.NowMs() or (getTimestampMs and getTimestampMs() or 0)
    end
    return changed
end

function Bridge.ResetMercenaryOrderMotionRuntime(bandit, brain, order, reason)
    if not (bandit and type(brain) == "table") then return false end
    brain.ai = brain.ai or {}
    local nowMs = Bridge.NowMs and Bridge.NowMs() or (getTimestampMs and getTimestampMs() or 0)
    brain.ai.lastGenerateTaskFrameTick = nil
    brain.ai.pathThrottle = nil
    brain.ai.lastAIDeniedAtMs = nil
    brain.ai.mercenaryUnifiedExecutionAtMs = nowMs
    brain.ai.mercenaryUnifiedExecutionReason = tostring(reason or "order_reset")
    brain.ai.mercenaryUnifiedExecutionOrder = order and order.name or brain.ai.mercenaryUnifiedExecutionOrder

    -- Clear stale movement/follow runtime owned by older orders.  This is not
    -- general AI cleanup: it runs only when a player-owned mercenary receives a
    -- new direct order or a strict order watchdog explicitly re-applies it.
    brain.ai.followSlotPathAtMs = nil
    brain.ai.followSlotTargetX = nil
    brain.ai.followSlotTargetY = nil
    brain.ai.leaderFollowSlotPathAtMs = nil
    brain.ai.leaderFollowSlotTargetX = nil
    brain.ai.leaderFollowSlotTargetY = nil
    brain.ai.strictFollowSlot = nil
    brain.ai.strictLeaderFollowSlot = nil
    brain.ai.bodyguardFollowSlotAtMs = nil

    if NPCEntity and NPCEntity.SetMoving then pcall(function() NPCEntity.SetMoving(bandit, false) end) end
    if NPCEntity and NPCEntity.ForceStationary then pcall(function() NPCEntity.ForceStationary(bandit, false) end) end

    if bandit.setPath2 then pcall(function() bandit:setPath2(nil) end) end
    if bandit.getPathFindBehavior2 then
        local okBehavior, behavior = pcall(function() return bandit:getPathFindBehavior2() end)
        if okBehavior and behavior then
            if behavior.cancel then pcall(function() behavior:cancel() end) end
            if behavior.reset then pcall(function() behavior:reset() end) end
        end
    end
    if bandit.setBumpDone then pcall(function() bandit:setBumpDone(true) end) end
    if Bridge.ResetMercenaryAnimationState then Bridge.ResetMercenaryAnimationState(bandit, reason) end
    return true
end

function Bridge.ClearMercenaryOrderCombatState(bandit, brain, order)
    if not (bandit and type(brain) == "table") then return false end

    local currentTask = NPCEntity and NPCEntity.GetTask and NPCEntity.GetTask(bandit) or (brain.tasks and brain.tasks[1]) or nil
    if not Bridge.IsManualOrderTaskInterruptible(currentTask) then return false end

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
    if brain.ai then
        brain.ai.stableCombatTarget = nil
        brain.ai.lastCombatScan = nil
        brain.ai.lastThreatScan = nil
        brain.ai.manualControlUntil = math.max(tonumber(brain.ai.manualControlUntil) or 0, bridge_nowMercenaryHours() + (18 / 3600))
        brain.ai.lastManualHardOrderAt = bridge_nowMercenaryHours()
        brain.ai.lastGenerateTaskFrameTick = nil
        local orderName = order and order.name and tostring(order.name) or nil
        if orderName == "Follow" then
            brain.ai.followSlotPathAtMs = nil
            brain.ai.followSlotTargetX = nil
            brain.ai.followSlotTargetY = nil
            brain.ai.leaderFollowSlotPathAtMs = nil
            brain.ai.leaderFollowSlotTargetX = nil
            brain.ai.leaderFollowSlotTargetY = nil
            brain.ai.strictFollowSlot = nil
            brain.ai.strictLeaderFollowSlot = nil
        end
    end
    if brain.fsm then
        brain.fsm.targetId = nil
        brain.fsm.targetKind = nil
        brain.fsm.currentThreat = nil
        brain.fsm.lastThreat = nil
        brain.fsm.target = nil
        brain.fsm.enemy = nil
        brain.fsm.state = nil
    end

    if NPCEntity and NPCEntity.ClearTasks then pcall(function() NPCEntity.ClearTasks(bandit) end) end
    Bridge.ResetMercenaryOrderMotionRuntime(bandit, brain, order, "clear_combat_state")
    if Bridge.ApplyMercenaryFireModeEquipment then Bridge.ApplyMercenaryFireModeEquipment(bandit, brain, order) end
    if NPCEntity and NPCEntity.SetAim then pcall(function() NPCEntity.SetAim(bandit, false) end) end
    if NPCEntity and NPCEntity.SetMoving then pcall(function() NPCEntity.SetMoving(bandit, false) end) end
    if bandit.clearAggroList then pcall(function() bandit:clearAggroList() end) end
    if bandit.setTarget then pcall(function() bandit:setTarget(nil) end) end
    if bandit.setAttackedBy then pcall(function() bandit:setAttackedBy(nil) end) end
    if bandit.setTargetSeenTime then pcall(function() bandit:setTargetSeenTime(0) end) end
    if bandit.setBumpDone then pcall(function() bandit:setBumpDone(true) end) end

    local name = order and order.name or nil
    local directMercenaryOrder = type(order) == "table" and (
        order.directMercenaryOrder == true
        or order.mercenaryDirect == true
        or order.dispatchMode == "mercenary_direct"
        or order.orderSystem == "mercenary_direct"
        or order.source == "player"
        or order.playerCommand == true
    )
    if NPCEntity and NPCEntity.SetProgram and directMercenaryOrder ~= true then
        if name == "Hold" or name == "Guard" then
            NPCEntity.SetProgram(bandit, "CompanionGuard", {})
            if brain.program then brain.program.stage = "Guard" end
        else
            NPCEntity.SetProgram(bandit, "Companion", {})
            if brain.program then brain.program.stage = "Follow" end
        end
    end

    return true
end

function Bridge.GetManualOrderAnchor(order, bandit, strictAnchor)
    if type(order) == "table" and type(order.anchor) == "table" and order.anchor.x and order.anchor.y then
        return {x=tonumber(order.anchor.x), y=tonumber(order.anchor.y), z=tonumber(order.anchor.z) or (bandit and bandit.getZ and bandit:getZ()) or 0, facingAngle=tonumber(order.anchor.facingAngle)}
    end
    if strictAnchor == true then return nil end
    if bandit and bandit.getX then
        return {x=bandit:getX(), y=bandit:getY(), z=bandit:getZ()}
    end
    return nil
end



function Bridge.GetMercenaryFollowTarget(bandit, brain, order)
    if not (bandit and type(brain) == "table") then return nil end
    order = order or (type(brain.order) == "table" and brain.order or nil)
    local master = NPCBehaviorBridge and NPCBehaviorBridge.GetMasterPlayer and NPCBehaviorBridge.GetMasterPlayer(bandit) or nil
    if not (master and master.getX) then return nil end

    local formation = order and order.formation or "close"
    formation = tostring(formation or "close")
    local followDistance = tonumber(order and order.followDistance) or 0.95
    if followDistance < 0.75 then followDistance = 0.75 end
    if formation == "close" or formation == "bodyguard" then
        if followDistance > 2.4 then followDistance = 2.4 end
    else
        -- Stage 387: non-close formations must be visually meaningful.  The
        -- bodyguard slot helper is intentionally compact; use the regular
        -- formation slot planner for line/wedge/ring/wide so Follow does not
        -- collapse into the same small ring around the player.
        if followDistance < 2.0 then followDistance = 2.0 end
        if followDistance > 8.0 then followDistance = 8.0 end
    end

    local tx, ty, tz = nil, nil, nil
    if NPCFormationSlotsBridge then
        if formation ~= "close" and formation ~= "bodyguard" and NPCFormationSlotsBridge.GetSlotPoint then
            local okSlot, sx, sy, sz = pcall(function()
                return NPCFormationSlotsBridge.GetSlotPoint(master, brain, bandit, formation, followDistance)
            end)
            if okSlot and sx and sy then tx, ty, tz = sx, sy, sz end
        end
        if not (tx and ty) and NPCFormationSlotsBridge.GetPlayerFollowSlotPoint then
            local okSlot, sx, sy, sz = pcall(function()
                return NPCFormationSlotsBridge.GetPlayerFollowSlotPoint(master, brain, bandit, formation, followDistance)
            end)
            if okSlot and sx and sy then tx, ty, tz = sx, sy, sz end
        end
    end
    if not (tx and ty) then
        tx, ty, tz = master:getX(), master:getY(), master:getZ()
    end

    local dist = NPCUtils and NPCUtils.DistTo and NPCUtils.DistTo(bandit:getX(), bandit:getY(), tx, ty) or 9999
    local nowMs = Bridge.NowMs and Bridge.NowMs() or (getTimestampMs and getTimestampMs() or 0)
    brain.ai = brain.ai or {}
    local lastX = tonumber(brain.ai.bodyguardFollowSlotX)
    local lastY = tonumber(brain.ai.bodyguardFollowSlotY)
    local lastMs = tonumber(brain.ai.bodyguardFollowSlotAtMs) or 0
    local targetMoved = (not lastX or not lastY) or ((NPCUtils and NPCUtils.DistTo and NPCUtils.DistTo(lastX, lastY, tx, ty) or 0) > 0.28)
    local playerMoving = targetMoved and (nowMs <= 0 or lastMs <= 0 or (nowMs - lastMs) < 1300)
    if master.isRunning and master:isRunning() then playerMoving = true end
    if master.isSprinting and master:isSprinting() then playerMoving = true end
    if master.isPlayerMoving then
        local okMoving, moving = pcall(function() return master:isPlayerMoving() end)
        if okMoving and moving == true then playerMoving = true end
    end
    return tx, ty, tz or master:getZ(), dist, master, playerMoving, targetMoved, nowMs
end

function Bridge.RememberMercenaryFollowTarget(brain, tx, ty, tz, nowMs)
    if type(brain) ~= "table" then return end
    brain.ai = brain.ai or {}
    brain.ai.bodyguardFollowSlotX = tx
    brain.ai.bodyguardFollowSlotY = ty
    brain.ai.bodyguardFollowSlotZ = tz
    brain.ai.bodyguardFollowSlotAtMs = nowMs or (Bridge.NowMs and Bridge.NowMs() or (getTimestampMs and getTimestampMs() or 0))
    brain.ai.directFollowMasterX = nil
    brain.ai.directFollowMasterY = nil
    brain.ai.directFollowMasterZ = nil
end

function Bridge.MarkMercenaryOrderTask(task, order, name)
    if type(task) ~= "table" then return task end
    task.source = task.source or "player"
    task.manualOrder = true
    task.strictPlayerOrder = order and order.strict == true or task.strictPlayerOrder == true
    task.strictOrderName = name or (order and order.name)
    task.orderName = name or (order and order.name)
    task.orderSequence = tonumber(order and order.sequence) or task.orderSequence
    task.interrupt = true
    if order and (order.directMercenaryOrder == true or order.mercenaryDirect == true or order.dispatchMode == "mercenary_direct") then
        task.playerOrder = true
        task.commandAuthority = "player"
        task.mercenaryUnifiedImmediate = true
        local fireMode = tostring(order.fireMode or "")
        if NPCOrderContract and NPCOrderContract.NormalizeFireMode then fireMode = NPCOrderContract.NormalizeFireMode(fireMode) end
        if fireMode ~= "HoldFire" and fireMode ~= "MeleeOnly" then
            task.allowCombatPreempt = true
        end
    end
    if order and bridge_isTacticalMercenaryOrderName(order.name) then
        task.playerTacticalOrder = true
        task.playerCommand = true
        task.commandAuthority = "player"
        task.tacticalOrderName = order.name
    end
    return task
end

function Bridge.MarkMercenaryOrderTasks(tasks, order, name)
    if type(tasks) ~= "table" then return tasks end
    for _, task in pairs(tasks) do
        Bridge.MarkMercenaryOrderTask(task, order, name)
    end
    return tasks
end

function Bridge.IsStrictOrderImmediateWindow(brain, order)
    if not (type(brain) == "table" and type(order) == "table") then return false end
    if order.strict ~= true then return false end
    local now = bridge_nowMercenaryHours()
    local untilAge = tonumber(order.immediateReapplyUntil)
    if type(brain.ai) == "table" then
        untilAge = math.max(untilAge or 0, tonumber(brain.ai.strictOrderImmediateUntil) or 0)
        local seq = tonumber(brain.ai.strictOrderImmediateSequence)
        if seq and tonumber(order.sequence) and seq ~= tonumber(order.sequence) then return false end
        local aiName = brain.ai.strictOrderImmediateName
        if aiName and order.name and tostring(aiName) ~= tostring(order.name) then return false end
    end
    return untilAge ~= nil and untilAge > now
end

function Bridge.IsStrictOrderLocomotionInProgress(bandit, brain, order, dist, zdist, name)
    if not (bandit and type(brain) == "table" and type(order) == "table") then return false end
    if zdist and zdist > 0.35 then return false end
    local moving = false
    if NPCEntity and NPCEntity.IsMoving then
        local okMoving, retMoving = pcall(function() return NPCEntity.IsMoving(bandit) end)
        moving = okMoving and retMoving == true
    end
    if not moving then return false end
    local leash = Bridge.GetStrictOrderLeash and Bridge.GetStrictOrderLeash(brain, name) or nil
    if not dist or not leash then return true end
    local allow = leash + 1.8
    if name == "Follow" or name == "FallBack" or name == "Return" then
        allow = math.max(allow, 11.5)
    elseif name == "Guard" then
        allow = math.max(allow, 10.5)
    elseif name == "Hold" then
        allow = math.max(allow, 4.8)
    end
    return dist <= allow
end

function Bridge.IsStrictOrderImmediateTaskCompliant(bandit, brain, order, task)
    if not (bandit and type(brain) == "table" and type(order) == "table") then return true end
    local name = bridge_normMercenaryOrderName(order.name)
    local dist, zdist = Bridge.GetStrictOrderDistance(bandit, brain, order)
    if zdist and zdist > 0.35 then return false end

    local settle = 1.35
    if name == "Hold" then settle = 0.90 end
    if name == "Guard" then settle = 1.75 end
    if name == "FallBack" or name == "Return" then settle = 1.60 end

    if not task then
        if Bridge.IsStrictOrderLocomotionInProgress(bandit, brain, order, dist, zdist, name) then return true end
        return not dist or dist <= settle
    end
    if not Bridge.IsManualOrderTaskInterruptible(task) then return true end

    local fireMode = NPCOrderContract and NPCOrderContract.GetFireMode and NPCOrderContract.GetFireMode(brain) or tostring(order.fireMode or "")
    local action = tostring(task.action or "")
    local retaliationActive = Bridge.IsMercenaryRetaliationActive and Bridge.IsMercenaryRetaliationActive(brain) == true
    if fireMode == "HoldFire" and retaliationActive ~= true and (action == "Shoot" or action == "Aim" or action == "Hit" or action == "Shove" or action == "Reload") then return false end
    if Bridge.IsMercenaryFireModeTaskDenied and Bridge.IsMercenaryFireModeTaskDenied(bandit, brain, order, task) then return false end

    if Bridge.IsStrictTaskOutsideChaseBoundary(bandit, brain, order, task) then return false end

    if task.mercenaryHoldPositionCombat == true and (action == "Shoot" or action == "Aim" or action == "Reload" or action == "Equip" or action == "Unequip" or action == "FaceLocation") then
        return true
    end

    local directorState = tostring(task.directorState or task.state or "")
    if directorState == "SearchEnemy" or directorState == "PatrolArea" or directorState == "LootArea" or directorState == "FlankEnemy" or directorState == "BoundForward" or directorState == "InvestigateNoise" then return false end
    if action == "Shoot" or action == "Hit" or action == "Shove" then
        local target = nil
        if bandit.getTarget then
            local okTarget, retTarget = pcall(function() return bandit:getTarget() end)
            if okTarget then target = retTarget end
        end
        if target and target.getX and bandit.getX then
            local td = NPCUtils and NPCUtils.DistTo and NPCUtils.DistTo(bandit:getX(), bandit:getY(), target:getX(), target:getY()) or 9999
            if td > 2.25 then return false end
        elseif name == "Follow" or name == "Hold" or name == "Guard" then
            return false
        end
    end

    if name == "Follow" and (action == "Move" or action == "Walk" or task.x ~= nil) and task.x and task.y then
        local sx, sy, sz, slotDist, master, playerMoving, targetMoved = Bridge.GetMercenaryFollowTarget(bandit, brain, order)
        if sx and sy then
            local dx = (tonumber(task.x) or sx) - sx
            local dy = (tonumber(task.y) or sy) - sy
            local targetDrift = math.sqrt(dx * dx + dy * dy)
            local taskAge = Bridge.NowMs and (Bridge.NowMs() - (tonumber(task.routerCreatedAt) or tonumber(task.createdAt) or tonumber(task.startedAt) or 0)) or 0
            if targetDrift > 0.55 and (playerMoving == true or targetMoved == true or taskAge > 650) then
                brain.ai = brain.ai or {}
                brain.ai.lastFollowImmediateDrift = targetDrift
                brain.ai.lastFollowImmediateDriftAtMs = Bridge.NowMs and Bridge.NowMs() or (getTimestampMs and getTimestampMs() or 0)
                return false
            end
        end
    end

    if task.strictPlayerOrder == true or task.manualOrder == true or task.source == "player" then return true end
    if dist and dist > settle then return false end
    return true
end

function Bridge.ShouldImmediateReapplyStrictMercenaryOrder(bandit, brain, order)
    if not Bridge.IsStrictOrderImmediateWindow(brain, order) then return false end
    local task = NPCEntity and NPCEntity.GetTask and NPCEntity.GetTask(bandit) or (brain and brain.tasks and brain.tasks[1]) or nil
    if not Bridge.IsManualOrderTaskInterruptible(task) then return false end
    if type(brain.ai) == "table" and brain.ai.forceManualOrderNow == true then
        Bridge.IncMercenaryOrderStat("strict.immediate.force", 1)
        return true
    end
    if not Bridge.IsStrictOrderImmediateTaskCompliant(bandit, brain, order, task) then
        Bridge.IncMercenaryOrderStat("strict.immediate.noncompliant", 1)
        return true
    end
    Bridge.IncMercenaryOrderStat("strict.immediate.ok", 1)
    return false
end

function Bridge.GetStrictOrderWatchdogExpectedState(order)
    local name = bridge_normMercenaryOrderName(order and order.name)
    if name == "Follow" or name == "FallBack" or name == "Return" then return "FollowPlayer", name end
    if name == "Hold" then return "HoldPosition", name end
    if name == "Guard" then
        return "GuardPlayer", name
    end
    return nil, name
end

function Bridge.IsStrictOrderWatchdogAllowedState(state, name)
    state = tostring(state or "")
    if state == "" then return true end
    if state == "Moving" or state == "RecoverPath" or state == "ReloadWeapon" or state == "ReloadCover" or state == "HealSelf" or state == "EatDrink" then return true end
    if state == "EmergencyDefense" or state == "Flee" or state == "KeepDistance" then return true end
    if name == "Guard" and state == "GuardArea" then return true end
    if name == "Follow" and state == "GuardPlayer" then return false end
    return false
end

function Bridge.IsStrictOrderWatchdogBadState(state)
    state = tostring(state or "")
    return state == "SearchEnemy"
        or state == "Attack"
        or state == "MeleeFallback"
        or state == "PatrolArea"
        or state == "LootArea"
        or state == "FlankEnemy"
        or state == "BoundForward"
        or state == "InvestigateNoise"
        or state == "SuppressEnemy"
        or state == "TacticalCover"
        or state == "HoldAngle"
end

function Bridge.IsStrictOrderWatchdogDue(brain, order)
    if not (type(brain) == "table" and type(order) == "table") then return false end
    if Bridge.IsStrictOrderImmediateWindow(brain, order) then return true end
    brain.ai = brain.ai or {}
    local nowMs = Bridge.NowMs()
    local last = tonumber(brain.ai.lastStrictOrderWatchdogCheckAtMs) or 0
    local interval = tonumber(order.watchdogIntervalMs) or 720
    if interval < 320 then interval = 320 end
    if interval > 1800 then interval = 1800 end
    return nowMs - last >= interval
end

function Bridge.MarkStrictOrderWatchdogChecked(brain, reason)
    if type(brain) ~= "table" then return end
    brain.ai = brain.ai or {}
    brain.ai.lastStrictOrderWatchdogCheckAtMs = Bridge.NowMs()
    if reason then brain.ai.lastStrictOrderWatchdogReason = reason end
end

function Bridge.IsStrictOrderWatchdogCompliant(bandit, brain, order, task)
    if not (bandit and type(brain) == "table" and type(order) == "table") then return true end
    if Bridge.IsStrictOrderImmediateTaskCompliant(bandit, brain, order, task) == false then return false, "task" end

    local expected, name = Bridge.GetStrictOrderWatchdogExpectedState(order)
    if expected then
        local state = brain.fsm and brain.fsm.state or brain.state
        if state and state ~= expected then
            if Bridge.IsStrictOrderWatchdogBadState(state) then return false, "state" end
            if not Bridge.IsStrictOrderWatchdogAllowedState(state, name) then
                local dist, zdist = Bridge.GetStrictOrderDistance(bandit, brain, order)
                local leash = Bridge.GetStrictOrderLeash(brain, name)
                if zdist and zdist > 0.35 then return false, "z" end
                if dist and leash and dist > math.max(1.5, leash * 0.55) then return false, "state_drift" end
            end
        end
    end

    local target = nil
    if bandit and bandit.getTarget then
        local okTarget, gotTarget = pcall(function() return bandit:getTarget() end)
        if okTarget then target = gotTarget end
    end
    if target and target.getX and Bridge.IsTargetOutsideStrictOrderBoundary then
        local tx = target:getX()
        local ty = target:getY()
        local dx = (tonumber(bandit:getX()) or 0) - (tonumber(tx) or 0)
        local dy = (tonumber(bandit:getY()) or 0) - (tonumber(ty) or 0)
        local dist = math.sqrt(dx * dx + dy * dy)
        local denied = Bridge.IsTargetOutsideStrictOrderBoundary(bandit, brain, target, dist)
        if denied then return false, "target" end
        local fireMode = NPCOrderContract and NPCOrderContract.GetFireMode and NPCOrderContract.GetFireMode(brain) or tostring(order.fireMode or "")
        if fireMode == "HoldFire" and dist > 1.35 then return false, "hold_fire_target" end
    end

    return true, nil
end

function Bridge.ShouldWatchdogReapplyStrictMercenaryOrder(bandit, brain, order)
    if not (bandit and type(brain) == "table" and type(order) == "table") then return false end
    if not Bridge.IsStrictOrderWatchdogDue(brain, order) then return false end
    local task = NPCEntity and NPCEntity.GetTask and NPCEntity.GetTask(bandit) or (brain and brain.tasks and brain.tasks[1]) or nil
    if not Bridge.IsManualOrderTaskInterruptible(task) then
        Bridge.MarkStrictOrderWatchdogChecked(brain, "protected_task")
        Bridge.IncMercenaryOrderStat("strict.watchdog.protected", 1)
        return false
    end
    local compliant, reason = Bridge.IsStrictOrderWatchdogCompliant(bandit, brain, order, task)
    Bridge.MarkStrictOrderWatchdogChecked(brain, compliant and "ok" or reason)
    if compliant then
        Bridge.IncMercenaryOrderStat("strict.watchdog.ok", 1)
        return false
    end
    brain.ai = brain.ai or {}
    brain.ai.lastStrictOrderWatchdogReapplyReason = reason
    brain.ai.lastStrictOrderWatchdogReapplyAtMs = Bridge.NowMs()
    Bridge.IncMercenaryOrderStat("strict.watchdog.reapply", 1)
    if reason then Bridge.IncMercenaryOrderStat("strict.watchdog." .. tostring(reason), 1) end
    return true
end

function Bridge.IsCursorExactMercenaryPointOrderName(name)
    name = bridge_normMercenaryOrderName(name)
    return name == "Hold"
        or name == "Guard"
        or name == "Return"
        or name == "Advance"
        or name == "FallBack"
        or name == "Flank"
        or name == "Encircle"
        or name == "BackToBack"
        or name == "TakeCover"
        or name == "WatchSector"
end

function Bridge.IsMercenaryPointOrderDelegatedAfterArrival(name)
    name = bridge_normMercenaryOrderName(name)
    return name == "Patrol"
        or name == "Loot"
        or name == "LootHouse"
        or name == "LootBodies"
        or name == "LootBodiesGear"
        or name == "LootBodiesClothing"
        or name == "LootBodiesWeapons"
        or name == "LootBodiesAmmo"
        or name == "LootBodiesMedical"
        or name == "LootBodiesSupplies"
        or name == "RearmHere"
        or name == "Flank"
        or name == "Encircle"
        or name == "TakeCover"
        or name == "Advance"
        or name == "FallBack"
end

function Bridge.QueueCursorExactMercenaryPointTask(bandit, brain, order, tasks, name)
    if not (bandit and type(brain) == "table" and type(order) == "table") then return false end
    local anchor = Bridge.GetManualOrderAnchor(order, bandit, true)
    if not (anchor and anchor.x and anchor.y) then return false end
    tasks = tasks or {}

    local bx = tonumber(bandit:getX()) or 0
    local by = tonumber(bandit:getY()) or 0
    local bz = tonumber(bandit:getZ()) or 0
    local anchorX = tonumber(anchor.x)
    local anchorY = tonumber(anchor.y)
    local anchorZ = tonumber(anchor.z) or bz
    local tx = anchorX
    local ty = anchorY
    local tz = anchorZ
    if not (tx and ty) then return false end

    -- Stage 387: upper point commands must also use per-member formation
    -- slots.  Previously Hold/Guard/Return first drove every NPC to the exact
    -- clicked square, while tactical commands used slot-aware behavior.  This
    -- made tactical orders feel correct and upper orders look stuck/clumped.
    if (name == "Hold" or name == "Guard" or name == "Return" or name == "WatchSector" or name == "BackToBack")
        and NPCFormationSlotsBridge and NPCFormationSlotsBridge.GetAnchorSlotPoint then
        local formation = order and order.formation or "close"
        local followDistance = tonumber(order and order.followDistance) or 2.0
        if followDistance < 1.0 then followDistance = 1.0 end
        if followDistance > 8.0 then followDistance = 8.0 end
        local okSlot, sx, sy, sz = pcall(function()
            return NPCFormationSlotsBridge.GetAnchorSlotPoint({x=anchorX, y=anchorY, z=anchorZ}, brain, bandit, formation, followDistance)
        end)
        if okSlot and sx and sy then
            tx = tonumber(sx) or tx
            ty = tonumber(sy) or ty
            tz = tonumber(sz) or tz
        end
    end

    local dist = NPCUtils and NPCUtils.DistTo and NPCUtils.DistTo(bx, by, tx, ty) or 9999
    local zdist = math.abs(bz - tz)
    local settle = tonumber(order.cursorSettleDist) or 0.82
    if name == "Hold" or name == "Guard" or name == "Return" then settle = tonumber(order.cursorSettleDist) or 0.78 end

    brain.ai = brain.ai or {}
    brain.ai.mercenaryCursorOrderName = name
    brain.ai.mercenaryCursorOrderX = anchorX or tx
    brain.ai.mercenaryCursorOrderY = anchorY or ty
    brain.ai.mercenaryCursorOrderZ = anchorZ or tz
    brain.ai.mercenaryCursorSlotX = tx
    brain.ai.mercenaryCursorSlotY = ty
    brain.ai.mercenaryCursorSlotZ = tz
    brain.ai.mercenaryCursorOrderRevision = tonumber(order.orderRevision or order.groupOrderRevision or brain.orderRevision or brain.groupOrderRevision or brain.mercenaryOrderRevision)

    local delegatedAfterArrival = Bridge.IsMercenaryPointOrderDelegatedAfterArrival and Bridge.IsMercenaryPointOrderDelegatedAfterArrival(name)
    local needsMoveToAnchor = dist > settle or zdist > 0.2
    if needsMoveToAnchor or (order.forceImmediate == true and delegatedAfterArrival ~= true) then
        if NPCEntity and NPCEntity.ForceStationary then pcall(function() NPCEntity.ForceStationary(bandit, false) end) end
        if NPCEntity and NPCEntity.SetMoving then pcall(function() NPCEntity.SetMoving(bandit, true) end) end
        if NPCUtils and NPCUtils.GetMoveTask then
            local walkType = (name == "Advance" or name == "FallBack" or name == "Flank" or dist > 5.5) and "Run" or "Walk"
            local task = NPCUtils.GetMoveTask(0, tx, ty, tz, walkType, math.max(dist, 0.35), false)
            task.arriveDist = settle
            task.cursorExactOrder = true
            task.playerOrder = true
            task.manualOrder = true
            task.playerTacticalOrder = bridge_isTacticalMercenaryOrderName(name)
            task.orderName = name
            task.tacticalOrderName = name
            task.pathThrottleMs = 75
            task.sameTargetPathThrottleMs = 180
            task.movementIntentTtlMs = 1200
            task.routerTtlMs = 1400
            task.routerPreempt = true
            task.force = true
            task.forcePath = true
            task.mercenaryUnifiedImmediate = true
            task.delegatedAfterArrival = delegatedAfterArrival == true
            task.orderAnchorX = anchorX or tx
            task.orderAnchorY = anchorY or ty
            task.orderAnchorZ = anchorZ or tz
            task.orderSlotX = tx
            task.orderSlotY = ty
            task.orderSlotZ = tz
            Bridge.MarkMercenaryOrderTask(task, order, name)
            table.insert(tasks, task)
            return true
        end
    end

    if delegatedAfterArrival == true then
        if NPCEntity and NPCEntity.ForceStationary then pcall(function() NPCEntity.ForceStationary(bandit, false) end) end
        return false
    end

    if name == "Hold" or name == "Guard" or name == "Return" or name == "BackToBack" or name == "WatchSector" then
        if NPCEntity and NPCEntity.ForceStationary then pcall(function() NPCEntity.ForceStationary(bandit, true) end) end
        if Bridge.QueueMercenaryAmbientIdleTask(bandit, brain, order, tasks, {settled=true}) then
            return true
        end
        local faceAngle = tonumber(anchor.facingAngle) or 0
        local faceX = tx + math.cos(faceAngle) * 2
        local faceY = ty + math.sin(faceAngle) * 2
        local task = {action="FaceLocation", anim="Idle", x=faceX, y=faceY, time=50, cursorExactOrder=true, playerOrder=true, manualOrder=true, orderName=name}
        Bridge.MarkMercenaryOrderTask(task, order, name)
        table.insert(tasks, task)
        return true
    end

    return true
end


function Bridge.GetMercenaryFormationMemberIndex(bandit, brain)
    local function normalizeIndex(v)
        local n = tonumber(v)
        if n then
            n = math.floor(math.abs(n))
            if n < 1 then n = n + 1 end
            return ((n - 1) % 8) + 1
        end
        return nil
    end
    if type(brain) == "table" then
        local n = normalizeIndex(brain.memberIndex) or normalizeIndex(brain.groupMemberIndex) or normalizeIndex(brain.formationIndex) or normalizeIndex(brain.slotIndex) or normalizeIndex(brain.mercenarySlotIndex) or normalizeIndex(brain.id) or normalizeIndex(brain.uid) or normalizeIndex(brain.persistentId)
        if n then return n end
    end
    if NPCUtils and NPCUtils.GetZombieID and bandit then
        local n = normalizeIndex(NPCUtils.GetZombieID(bandit))
        if n then return n end
    end
    return 1
end

function Bridge.QueueMercenaryPatrolAroundAnchorTask(bandit, brain, order, tasks)
    if not (bandit and type(brain) == "table" and type(order) == "table") then return false end
    local anchor = Bridge.GetManualOrderAnchor(order, bandit, true)
    if not (anchor and anchor.x and anchor.y) then return false end
    tasks = tasks or {}

    local bx = tonumber(bandit:getX()) or 0
    local by = tonumber(bandit:getY()) or 0
    local bz = tonumber(bandit:getZ()) or 0
    local nowMs = Bridge.NowMs and Bridge.NowMs() or (getTimestampMs and getTimestampMs() or 0)
    local idx = Bridge.GetMercenaryFormationMemberIndex(bandit, brain)
    local phase = math.floor((nowMs / 2600) + idx) % 6
    local radius = 2.6 + ((idx - 1) % 3) * 0.65
    local angle = (idx - 1) * 2.399963 + phase * 0.72
    local tx = tonumber(anchor.x) + math.cos(angle) * radius
    local ty = tonumber(anchor.y) + math.sin(angle) * radius
    local tz = tonumber(anchor.z) or bz

    brain.ai = brain.ai or {}
    local lastX = tonumber(brain.ai.mercenaryPatrolSlotX)
    local lastY = tonumber(brain.ai.mercenaryPatrolSlotY)
    local slotMoved = (not lastX or not lastY) or ((NPCUtils and NPCUtils.DistTo and NPCUtils.DistTo(lastX, lastY, tx, ty) or 0) > 0.75)
    brain.ai.mercenaryPatrolSlotX = tx
    brain.ai.mercenaryPatrolSlotY = ty
    brain.ai.mercenaryPatrolSlotZ = tz
    brain.ai.mercenaryPatrolAnchorX = tonumber(anchor.x)
    brain.ai.mercenaryPatrolAnchorY = tonumber(anchor.y)
    brain.ai.mercenaryPatrolAnchorZ = tonumber(anchor.z) or bz

    local dist = NPCUtils and NPCUtils.DistTo and NPCUtils.DistTo(bx, by, tx, ty) or 9999
    local zdist = math.abs(bz - tz)
    if (dist > 0.95 or zdist > 0.2 or slotMoved == true) and NPCUtils and NPCUtils.GetMoveTask then
        if NPCEntity and NPCEntity.ForceStationary then pcall(function() NPCEntity.ForceStationary(bandit, false) end) end
        if NPCEntity and NPCEntity.SetMoving then pcall(function() NPCEntity.SetMoving(bandit, true) end) end
        local task = NPCUtils.GetMoveTask(0, tx, ty, tz, dist > 5.0 and "Run" or "Walk", math.max(dist, 0.5), false)
        task.arriveDist = 0.72
        task.playerOrder = true
        task.manualOrder = true
        task.playerTacticalOrder = true
        task.patrolAroundAnchor = true
        task.orderName = "Patrol"
        task.tacticalOrderName = "Patrol"
        task.routerPreempt = true
        task.force = true
        task.forcePath = true
        task.pathThrottleMs = 220
        task.sameTargetPathThrottleMs = 520
        task.movementIntentTtlMs = 1600
        task.routerTtlMs = 1800
        task.orderAnchorX = tonumber(anchor.x)
        task.orderAnchorY = tonumber(anchor.y)
        task.orderAnchorZ = tonumber(anchor.z) or tz
        task.orderSlotX = tx
        task.orderSlotY = ty
        task.orderSlotZ = tz
        Bridge.MarkMercenaryOrderTask(task, order, "Patrol")
        table.insert(tasks, task)
        return true
    end

    if NPCEntity and NPCEntity.ForceStationary then pcall(function() NPCEntity.ForceStationary(bandit, false) end) end
    local faceX = tonumber(anchor.x) or bx
    local faceY = tonumber(anchor.y) or by
    local task = {action="FaceLocation", anim="Idle", x=faceX, y=faceY, time=90, patrolAroundAnchor=true, playerOrder=true, manualOrder=true, orderName="Patrol", tacticalOrderName="Patrol", routerTtlMs=650}
    Bridge.MarkMercenaryOrderTask(task, order, "Patrol")
    table.insert(tasks, task)
    return true
end


local function bridge_searchHouseSquareAt(x, y, z)
    if not (getCell and x and y) then return nil end
    local cell = getCell()
    if not (cell and cell.getGridSquare) then return nil end
    local ok, square = pcall(function() return cell:getGridSquare(math.floor(tonumber(x) or 0), math.floor(tonumber(y) or 0), math.floor(tonumber(z) or 0)) end)
    if ok then return square end
    return nil
end

local function bridge_searchHouseSameBuilding(anchorSquare, square)
    if not (anchorSquare and square) then return false end
    local ab, sb = nil, nil
    if anchorSquare.getBuilding then pcall(function() ab = anchorSquare:getBuilding() end) end
    if square.getBuilding then pcall(function() sb = square:getBuilding() end) end
    if ab and sb and ab == sb then return true end
    local ar, sr = nil, nil
    if anchorSquare.getRoom then pcall(function() ar = anchorSquare:getRoom() end) end
    if square.getRoom then pcall(function() sr = square:getRoom() end) end
    if ar and sr and ar == sr then return true end
    if ar and sr and ar.getBuilding and sr.getBuilding then
        local arb, srb = nil, nil
        pcall(function() arb = ar:getBuilding() end)
        pcall(function() srb = sr:getBuilding() end)
        if arb and srb and arb == srb then return true end
    end
    return false
end

function Bridge.GetMercenarySearchHousePoint(bandit, brain, order)
    if not (bandit and type(brain) == "table" and type(order) == "table") then return nil end
    local anchor = Bridge.GetManualOrderAnchor(order, bandit, true)
    if not (anchor and anchor.x and anchor.y) then return nil end
    local ax = tonumber(anchor.x)
    local ay = tonumber(anchor.y)
    local az = tonumber(anchor.z) or (bandit.getZ and bandit:getZ() or 0)
    if not (ax and ay) then return nil end

    local anchorSquare = bridge_searchHouseSquareAt(ax, ay, az)
    brain.ai = brain.ai or {}
    local nowMs = Bridge.NowMs and Bridge.NowMs() or (getTimestampMs and getTimestampMs() or 0)
    local idx = Bridge.GetMercenaryFormationMemberIndex and Bridge.GetMercenaryFormationMemberIndex(bandit, brain) or 1
    local phase = math.floor((nowMs / 3200) + idx * 3) % 10
    local baseAngle = (idx - 1) * 2.399963 + phase * 0.92
    local baseRadius = 1.1 + ((idx + phase) % 4) * 0.85

    local bestX, bestY, bestZ = ax, ay, az
    for attempt = 0, 9 do
        local angle = baseAngle + attempt * 0.74
        local radius = baseRadius + (attempt % 3) * 0.75
        local tx = ax + math.cos(angle) * radius
        local ty = ay + math.sin(angle) * radius
        local square = bridge_searchHouseSquareAt(tx, ty, az)
        if bridge_searchHouseSameBuilding(anchorSquare, square) then
            bestX, bestY, bestZ = tx, ty, az
            break
        end
    end

    brain.ai.mercenarySearchHousePointX = bestX
    brain.ai.mercenarySearchHousePointY = bestY
    brain.ai.mercenarySearchHousePointZ = bestZ
    brain.ai.mercenarySearchHouseAnchorX = ax
    brain.ai.mercenarySearchHouseAnchorY = ay
    brain.ai.mercenarySearchHouseAnchorZ = az
    return bestX, bestY, bestZ
end

function Bridge.GetMercenarySearchHouseAnim(brain)
    local nowMs = Bridge.NowMs and Bridge.NowMs() or (getTimestampMs and getTimestampMs() or 0)
    local seed = 0
    if type(brain) == "table" then seed = tonumber(brain.id) or tonumber(brain.uid) or tonumber(brain.persistentId) or tonumber(brain.runtimeId) or 0 end
    local bucket = math.floor(nowMs / 900 + seed * 5) % 10
    local anims = {"LootLow", "Forage", "Loot", "ReadBook", "WipeBrow", "Shrug", "Smoke", "SitAction"}
    return anims[(bucket % #anims) + 1], 92 + (bucket % 4) * 24
end

function Bridge.QueueMercenarySearchHouseTask(bandit, brain, order, tasks)
    if not (bandit and type(brain) == "table" and type(order) == "table") then return false end
    tasks = tasks or {}
    local tx, ty, tz = Bridge.GetMercenarySearchHousePoint(bandit, brain, order)
    if not (tx and ty) then return false end
    local bx = tonumber(bandit:getX()) or 0
    local by = tonumber(bandit:getY()) or 0
    local bz = tonumber(bandit:getZ()) or 0
    local dist = NPCUtils and NPCUtils.DistTo and NPCUtils.DistTo(bx, by, tx, ty) or 9999
    local zdist = math.abs(bz - (tonumber(tz) or bz))

    if (dist > 0.95 or zdist > 0.2) and NPCUtils and NPCUtils.GetMoveTask then
        if NPCEntity and NPCEntity.ForceStationary then pcall(function() NPCEntity.ForceStationary(bandit, false) end) end
        if NPCEntity and NPCEntity.SetMoving then pcall(function() NPCEntity.SetMoving(bandit, true) end) end
        local task = NPCUtils.GetMoveTask(0, tx, ty, tz, dist > 5.5 and "Run" or "Walk", math.max(dist, 0.4), false)
        task.arriveDist = 0.72
        task.playerOrder = true
        task.manualOrder = true
        task.orderName = "LootHouse"
        task.tacticalOrderName = "LootHouse"
        task.mercenarySearchHouse = true
        task.mercenaryUnifiedImmediate = true
        task.allowCombatPreempt = true
        task.routerPreempt = true
        task.force = true
        task.forcePath = true
        task.pathThrottleMs = 160
        task.sameTargetPathThrottleMs = 520
        task.movementIntentTtlMs = 1450
        task.routerTtlMs = 1800
        task.orderSlotX = tx
        task.orderSlotY = ty
        task.orderSlotZ = tz
        Bridge.MarkMercenaryOrderTask(task, order, "LootHouse")
        table.insert(tasks, task)
        return true
    end

    if NPCEntity and NPCEntity.SetMoving then pcall(function() NPCEntity.SetMoving(bandit, false) end) end
    if NPCEntity and NPCEntity.ForceStationary then pcall(function() NPCEntity.ForceStationary(bandit, false) end) end
    local anim, time = Bridge.GetMercenarySearchHouseAnim(brain)
    local task = {
        action = "Time",
        anim = anim,
        time = time,
        playerOrder = true,
        manualOrder = true,
        playerCommand = true,
        mercenarySearchHouse = true,
        ambientSearch = true,
        orderName = "LootHouse",
        tacticalOrderName = "LootHouse",
        source = "mercenary_search_house",
        allowCombatPreempt = true,
        routerPriority = 18,
        routerTtlMs = 2200
    }
    Bridge.MarkMercenaryOrderTask(task, order, "LootHouse")
    table.insert(tasks, task)
    return true
end



function Bridge.IsMercenaryAmbientIdleOrderName(name)
    name = bridge_normMercenaryOrderName(name)
    return name == "Follow"
        or name == "Hold"
        or name == "Guard"
        or name == "Loot"
        or name == "LootHouse"
        or name == "LootBodies"
        or name == "LootBodiesGear"
        or name == "LootBodiesClothing"
        or name == "LootBodiesWeapons"
        or name == "LootBodiesAmmo"
        or name == "LootBodiesMedical"
        or name == "LootBodiesSupplies"
        or name == "RearmHere"
end

function Bridge.GetMercenaryAmbientIdleAnim(brain, order, context)
    local name = bridge_normMercenaryOrderName(order and order.name)
    local searchMode = context and context.search == true
    local nowMs = Bridge.NowMs and Bridge.NowMs() or (getTimestampMs and getTimestampMs() or 0)
    local seed = 0
    if type(brain) == "table" then
        seed = tonumber(brain.id) or tonumber(brain.uid) or tonumber(brain.persistentId) or tonumber(brain.runtimeId) or 0
    end
    local bucket = math.floor((nowMs / 1000) + seed * 7) % 12

    if searchMode or name == "Loot" or name == "LootHouse" or name == "RearmHere" or string.find(name or "", "LootBodies", 1, true) then
        local searchAnims = {"LootLow", "Loot", "Forage", "SitAction"}
        return searchAnims[(bucket % #searchAnims) + 1], 85 + (bucket % 4) * 18
    end

    local ambientAnims = {"ShiftWeight", "Shrug", "Smoke", "SitAction", "SitRubHands", "ChewNails", "WipeBrow", "PullAtCollar"}
    return ambientAnims[(bucket % #ambientAnims) + 1], 95 + (bucket % 5) * 20
end

function Bridge.IsMercenaryAmbientIdleSafe(bandit, brain, order, context)
    if not (bandit and type(brain) == "table" and type(order) == "table") then return false end
    local name = bridge_normMercenaryOrderName(order.name)
    if not Bridge.IsMercenaryAmbientIdleOrderName(name) then return false end
    if brain.mercenaryHired ~= true and brain.commandAuthority ~= "player" and brain.playerCommandAuthority ~= true then return false end

    local currentTask = NPCEntity and NPCEntity.GetTask and NPCEntity.GetTask(bandit) or (brain.tasks and brain.tasks[1]) or nil
    if currentTask then return false end
    if NPCEntity and NPCEntity.HasTask and NPCEntity.HasTask(bandit) then return false end

    local moving = false
    if NPCEntity and NPCEntity.IsMoving then
        local okMoving, retMoving = pcall(function() return NPCEntity.IsMoving(bandit) end)
        moving = okMoving and retMoving == true
    end
    if moving then
        brain.ai = brain.ai or {}
        brain.ai.mercenaryAmbientIdleSinceMs = nil
        return false
    end

    if bandit.getActionStateName then
        local okState, state = pcall(function() return bandit:getActionStateName() end)
        state = okState and tostring(state or ""):lower() or ""
        if state == "walktoward" or state == "walktoward-network" or state == "pathfind" or state == "run" or state == "climb" then
            brain.ai = brain.ai or {}
            brain.ai.mercenaryAmbientIdleSinceMs = nil
            return false
        end
    end

    if bandit.getTarget then
        local okTarget, target = pcall(function() return bandit:getTarget() end)
        if okTarget and target ~= nil then return false end
    end
    if brain.currentThreat or brain.lastThreat or brain.target or brain.enemy or brain.combatTarget or brain.radioThreat then return false end
    if brain.ai and brain.ai.stableCombatTarget then return false end

    local nowMs = Bridge.NowMs and Bridge.NowMs() or (getTimestampMs and getTimestampMs() or 0)
    brain.ai = brain.ai or {}
    local since = tonumber(brain.ai.mercenaryAmbientIdleSinceMs)
    if not since then
        brain.ai.mercenaryAmbientIdleSinceMs = nowMs
        return false
    end

    local searchMode = context and context.search == true
    local idleDelay = searchMode and 2200 or 10500
    if nowMs > 0 and nowMs - since < idleDelay then return false end

    local cooldown = searchMode and 5200 or 14500
    local last = tonumber(brain.ai.lastMercenaryAmbientIdleAtMs) or 0
    if nowMs > 0 and nowMs - last < cooldown then return false end

    local issued = tonumber(order.issued or order.interruptIssued)
    if issued and issued > 0 and bridge_nowMercenaryHours then
        local ageSeconds = (bridge_nowMercenaryHours() - issued) * 3600
        if ageSeconds < (searchMode and 2.0 or 7.0) then return false end
    end

    if name == "Follow" then
        local tx, ty, tz, dist, master, playerMoving = Bridge.GetMercenaryFollowTarget(bandit, brain, order)
        if playerMoving == true then return false end
        if not (tx and ty and master) then return false end
        if dist and dist > 1.65 then return false end
    elseif name == "Hold" or name == "Guard" then
        local anchor = Bridge.GetManualOrderAnchor(order, bandit, true)
        if anchor and anchor.x and anchor.y and NPCUtils and NPCUtils.DistTo then
            local dist = NPCUtils.DistTo(bandit:getX(), bandit:getY(), anchor.x, anchor.y)
            if dist and dist > 2.25 then return false end
        end
    else
        local anchor = Bridge.GetManualOrderAnchor(order, bandit, true)
        if anchor and anchor.x and anchor.y and NPCUtils and NPCUtils.DistTo then
            local dist = NPCUtils.DistTo(bandit:getX(), bandit:getY(), anchor.x, anchor.y)
            if dist and dist > 4.25 then return false end
        end
    end

    return true
end

function Bridge.QueueMercenaryAmbientIdleTask(bandit, brain, order, tasks, context)
    if not Bridge.IsMercenaryAmbientIdleSafe(bandit, brain, order, context) then return false end
    tasks = tasks or {}
    local anim, time = Bridge.GetMercenaryAmbientIdleAnim(brain, order, context)
    if not anim or anim == "" then return false end
    local nowMs = Bridge.NowMs and Bridge.NowMs() or (getTimestampMs and getTimestampMs() or 0)
    brain.ai = brain.ai or {}
    brain.ai.lastMercenaryAmbientIdleAtMs = nowMs
    brain.ai.lastMercenaryAmbientIdleAnim = anim
    brain.ai.lastMercenaryAmbientIdleOrder = bridge_normMercenaryOrderName(order and order.name)

    if NPCEntity and NPCEntity.SetMoving then pcall(function() NPCEntity.SetMoving(bandit, false) end) end
    if NPCEntity and NPCEntity.ForceStationary then pcall(function() NPCEntity.ForceStationary(bandit, false) end) end
    local task = {
        action = "Time",
        anim = anim,
        time = tonumber(time) or 110,
        mercenaryAmbientIdle = true,
        source = "mercenary_ambient_idle",
        ambientOrderName = bridge_normMercenaryOrderName(order and order.name),
        routerPriority = (context and context.search == true) and 16 or 12,
        routerTtlMs = (context and context.search == true) and 1800 or 2400,
        ambientSearch = context and context.search == true or false,
        manualOrder = false,
        playerOrder = false
    }
    table.insert(tasks, task)
    Bridge.IncMercenaryOrderStat("ambient_idle.queued", 1)
    Bridge.IncMercenaryOrderStat("ambient_idle." .. tostring(task.ambientOrderName or "unknown"), 1)
    return true
end

function Bridge.QueueImmediateMercenaryOrderTask(bandit, brain, order, tasks)
    if not (bandit and type(brain) == "table" and type(order) == "table") then return false end
    tasks = tasks or {}
    local name = bridge_normMercenaryOrderName(order.name)
    brain.ai = brain.ai or {}
    local runtimeToken = Bridge.GetMercenaryOrderRuntimeToken and Bridge.GetMercenaryOrderRuntimeToken(brain, order) or nil
    if runtimeToken and brain.ai.mercenaryUnifiedExecutionToken ~= runtimeToken then
        Bridge.ResetMercenaryOrderMotionRuntime(bandit, brain, order, "new_order:" .. tostring(name))
        brain.ai.mercenaryUnifiedExecutionToken = runtimeToken
    elseif brain.ai.forceManualOrderNow == true then
        Bridge.ResetMercenaryOrderMotionRuntime(bandit, brain, order, "forced_order:" .. tostring(name))
    end

    if name == "Follow" then
        local tx, ty, tz, dist, master, playerMoving, targetMoved, nowMs = Bridge.GetMercenaryFollowTarget(bandit, brain, order)
        if master and tx and ty then
            Bridge.RememberMercenaryFollowTarget(brain, tx, ty, tz, nowMs)

            -- Stage 386: Follow uses the same immediate movement lane as the
            -- working point orders.  The only difference is that the target is a
            -- live bodyguard slot around the player instead of a cursor anchor.
            if NPCUtils and NPCUtils.GetMoveTask and (dist > 0.38 or playerMoving == true or targetMoved == true or order.forceImmediate == true) then
                if NPCEntity and NPCEntity.ForceStationary then pcall(function() NPCEntity.ForceStationary(bandit, false) end) end
                if NPCEntity and NPCEntity.SetMoving then pcall(function() NPCEntity.SetMoving(bandit, true) end) end
                local walkType = (playerMoving == true or dist > 1.10) and "Run" or "Walk"
                local task = NPCUtils.GetMoveTask(0, tx, ty, tz or master:getZ(), walkType, math.max(dist, 0.40), false)
                task.arriveDist = 0.44
                task.strictFollowSlot = true
                task.bodyguardFollow = true
                task.directMercenaryFollow = true
                task.playerOrder = true
                task.manualOrder = true
                task.routerPreempt = true
                task.force = true
                task.forcePath = true
                task.pathThrottleMs = 70
                task.sameTargetPathThrottleMs = 160
                task.movementIntentTtlMs = 900
                task.routerTtlMs = 950
                task.followSlotX = tx
                task.followSlotY = ty
                task.followSlotZ = tz
                Bridge.MarkMercenaryOrderTask(task, order, name)
                table.insert(tasks, task)
                return true
            end

            if NPCEntity and NPCEntity.ForceStationary then pcall(function() NPCEntity.ForceStationary(bandit, false) end) end
            Bridge.QueueMercenaryAmbientIdleTask(bandit, brain, order, tasks, {settled=true})
            return #tasks > 0 or true
        end
    elseif Bridge.IsCursorExactMercenaryPointOrderName and Bridge.IsCursorExactMercenaryPointOrderName(name) then
        if Bridge.QueueCursorExactMercenaryPointTask and Bridge.QueueCursorExactMercenaryPointTask(bandit, brain, order, tasks, name) then
            return #tasks > 0 or true
        end
        if NPCBehaviorBridge and NPCBehaviorBridge.CompanionTryMobileOrder then
            local okMobile, nextStage = pcall(function() return NPCBehaviorBridge.CompanionTryMobileOrder(bandit, brain, name, tasks) end)
            if okMobile and nextStage then
                Bridge.MarkMercenaryOrderTasks(tasks, order, name)
                return #tasks > 0
            end
        end
    elseif name == "Patrol" then
        if Bridge.QueueCursorExactMercenaryPointTask and Bridge.QueueCursorExactMercenaryPointTask(bandit, brain, order, tasks, name) then
            return #tasks > 0 or true
        end
        -- Stage 387: after arriving at the clicked patrol anchor, stay in the
        -- same reliable player-command lane instead of falling back into the
        -- old Companion director, which could leave mercenaries frozen at the
        -- anchor.
        if Bridge.QueueMercenaryPatrolAroundAnchorTask and Bridge.QueueMercenaryPatrolAroundAnchorTask(bandit, brain, order, tasks) then
            return #tasks > 0 or true
        end
    elseif Bridge.IsMercenaryPointOrderDelegatedAfterArrival and Bridge.IsMercenaryPointOrderDelegatedAfterArrival(name) then
        if Bridge.QueueCursorExactMercenaryPointTask and Bridge.QueueCursorExactMercenaryPointTask(bandit, brain, order, tasks, name) then
            return #tasks > 0 or true
        end
        -- Stage 390: Search House gets its own direct, vanilla-animation lane.
        -- The old companion looting program could leave NPCs walking crouched and
        -- keep that blend after Follow.  Other loot/rearm orders still use the
        -- existing working pipeline.
        if name == "LootHouse" and Bridge.QueueMercenarySearchHouseTask and Bridge.QueueMercenarySearchHouseTask(bandit, brain, order, tasks) then
            return #tasks > 0 or true
        end
        -- Only after every mercenary is already at the cursor anchor do we let
        -- the legacy loot/search/rearm program take over.
        if NPCBehaviorBridge and NPCBehaviorBridge.CompanionTryMobileOrder then
            local okMobile, nextStage = pcall(function() return NPCBehaviorBridge.CompanionTryMobileOrder(bandit, brain, name, tasks) end)
            if okMobile and nextStage then
                Bridge.MarkMercenaryOrderTasks(tasks, order, name)
                return #tasks > 0
            end
        end
        if Bridge.QueueMercenaryAmbientIdleTask(bandit, brain, order, tasks, {search=true}) then
            return #tasks > 0
        end
    elseif name == "Hold" or name == "Guard" then
        local anchor = Bridge.GetManualOrderAnchor(order, bandit)
        if anchor then
            local dist = NPCUtils and NPCUtils.DistTo and NPCUtils.DistTo(bandit:getX(), bandit:getY(), anchor.x, anchor.y) or 9999
            local zdist = math.abs((tonumber(bandit:getZ()) or 0) - (tonumber(anchor.z) or 0))
            if dist > 0.85 or zdist > 0.2 then
                if NPCEntity and NPCEntity.ForceStationary then pcall(function() NPCEntity.ForceStationary(bandit, false) end) end
                if NPCUtils and NPCUtils.GetMoveTask then
                    local task = NPCUtils.GetMoveTask(0, anchor.x, anchor.y, anchor.z, dist > 9 and "Run" or "Walk", dist, false)
                    Bridge.MarkMercenaryOrderTask(task, order, name)
                    table.insert(tasks, task)
                    return true
                end
            end
            if NPCEntity and NPCEntity.ForceStationary then pcall(function() NPCEntity.ForceStationary(bandit, true) end) end
            if Bridge.QueueMercenaryAmbientIdleTask(bandit, brain, order, tasks, {settled=true}) then
                return true
            end
            local faceX = anchor.x + math.cos(tonumber(anchor.facingAngle) or 0) * 2
            local faceY = anchor.y + math.sin(tonumber(anchor.facingAngle) or 0) * 2
            local task = {action="FaceLocation", anim="Idle", x=faceX, y=faceY, time=70}
            Bridge.MarkMercenaryOrderTask(task, order, name)
            table.insert(tasks, task)
            return true
        end
    else
        if NPCBehaviorBridge and NPCBehaviorBridge.CompanionTryMobileOrder then
            local okMobile, nextStage = pcall(function() return NPCBehaviorBridge.CompanionTryMobileOrder(bandit, brain, name, tasks) end)
            if okMobile and nextStage then
                Bridge.MarkMercenaryOrderTasks(tasks, order, name)
                return #tasks > 0
            end
        end
    end

    return #tasks > 0
end

function Bridge.MarkManualMercenaryOrderConsumed(brain, order)
    if type(brain) ~= "table" then return end
    brain.ai = brain.ai or {}
    brain.ai.manualOrderConsumedIssued = tonumber(order and (order.issued or order.interruptIssued)) or brain.ai.manualOrderConsumedIssued or 0
    brain.ai.manualOrderConsumedSequence = tonumber(order and order.sequence) or brain.ai.manualOrderConsumedSequence
    brain.ai.manualOrderConsumedRevision = tonumber(order and (order.orderRevision or order.groupOrderRevision)) or tonumber(brain.orderRevision or brain.groupOrderRevision or brain.mercenaryOrderRevision) or brain.ai.manualOrderConsumedRevision
    brain.ai.manualOrderConsumedAtMs = Bridge.NowMs()
    if not Bridge.IsStrictOrderImmediateWindow(brain, order) then
        brain.ai.forceManualOrderNow = false
    end
end

function Bridge.GetStrictMercenaryOrder(brain)
    if type(brain) ~= "table" then return nil end
    local order = type(brain.order) == "table" and brain.order or nil
    if type(order) ~= "table" then return nil end
    local direct = order.mercenaryDirect == true or order.directMercenaryOrder == true or brain.orderSystem == "mercenary_direct" or brain.mercenaryDirectOrders == true
    if not direct and order.source ~= "player" and order.commandAuthority ~= "player" and order.playerCommand ~= true then return nil end
    if order.strict == true or bridge_isStrictMercenaryOrderName(order.name) then return order end
    return nil
end
function Bridge.GetMercenaryOrderNowHours()
    return bridge_nowMercenaryHours()
end
function Bridge.ClearMercenaryOrderRuntimeField(ai, key)
    if type(ai) ~= "table" or ai[key] == nil then return 0 end
    ai[key] = nil
    return 1
end

function Bridge.CleanupStrictMercenaryOrderRuntimeState(brain, order)
    local cfg = Bridge.MercenaryOrderCleanupConfig or {}
    if cfg.enabled == false or type(brain) ~= "table" then return 0 end
    if type(brain) ~= "table" or brain.mercenaryHired ~= true then return 0 end
    brain.ai = brain.ai or {}
    local ai = brain.ai
    local nowMs = Bridge.NowMs()
    local interval = tonumber(cfg.intervalMs) or 4200
    if interval < 1000 then interval = 1000 end
    if interval > 30000 then interval = 30000 end
    local last = tonumber(ai.lastStrictOrderCleanupAtMs) or 0
    if nowMs - last < interval then return 0 end
    ai.lastStrictOrderCleanupAtMs = nowMs

    local removed = 0
    local activeStrict = type(order) == "table"
    local nowHour = Bridge.GetMercenaryOrderNowHours()
    local graceMs = tonumber(cfg.staleImmediateGraceMs) or 8500
    if graceMs < 1000 then graceMs = 1000 end
    if graceMs > 30000 then graceMs = 30000 end
    local graceHours = graceMs / 3600000

    if not activeStrict then
        removed = removed + Bridge.ClearMercenaryOrderRuntimeField(ai, "forceManualOrderNow")
        removed = removed + Bridge.ClearMercenaryOrderRuntimeField(ai, "strictOrderImmediateName")
        removed = removed + Bridge.ClearMercenaryOrderRuntimeField(ai, "strictOrderImmediateUntil")
        removed = removed + Bridge.ClearMercenaryOrderRuntimeField(ai, "strictOrderImmediateReason")
        removed = removed + Bridge.ClearMercenaryOrderRuntimeField(ai, "strictOrderImmediateSequence")
        removed = removed + Bridge.ClearMercenaryOrderRuntimeField(ai, "strictPlayerOrderName")
        removed = removed + Bridge.ClearMercenaryOrderRuntimeField(ai, "strictPlayerOrderSequence")
        removed = removed + Bridge.ClearMercenaryOrderRuntimeField(ai, "strictPlayerOrderAt")
        removed = removed + Bridge.ClearMercenaryOrderRuntimeField(ai, "lastStrictOrderWatchdogReason")
        removed = removed + Bridge.ClearMercenaryOrderRuntimeField(ai, "lastStrictOrderWatchdogReapplyReason")
        if type(brain.order) == "table" then
            local staleOrder = brain.order
            if staleOrder.immediateReapply ~= nil then staleOrder.immediateReapply = nil; removed = removed + 1 end
            if staleOrder.immediateReapplySequence ~= nil then staleOrder.immediateReapplySequence = nil; removed = removed + 1 end
            if staleOrder.immediateReapplyUntil ~= nil then staleOrder.immediateReapplyUntil = nil; removed = removed + 1 end
            if staleOrder.immediateReapplyReason ~= nil then staleOrder.immediateReapplyReason = nil; removed = removed + 1 end
        end
    else
        local untilHour = tonumber(order.immediateReapplyUntil)
        if untilHour and nowHour > untilHour + graceHours then
            if order.immediateReapply ~= nil then order.immediateReapply = nil; removed = removed + 1 end
            if order.immediateReapplySequence ~= nil then order.immediateReapplySequence = nil; removed = removed + 1 end
            if order.immediateReapplyUntil ~= nil then order.immediateReapplyUntil = nil; removed = removed + 1 end
            if order.immediateReapplyReason ~= nil then order.immediateReapplyReason = nil; removed = removed + 1 end
        end
        local aiUntil = tonumber(ai.strictOrderImmediateUntil)
        if aiUntil and nowHour > aiUntil + graceHours then
            removed = removed + Bridge.ClearMercenaryOrderRuntimeField(ai, "strictOrderImmediateName")
            removed = removed + Bridge.ClearMercenaryOrderRuntimeField(ai, "strictOrderImmediateUntil")
            removed = removed + Bridge.ClearMercenaryOrderRuntimeField(ai, "strictOrderImmediateReason")
            removed = removed + Bridge.ClearMercenaryOrderRuntimeField(ai, "strictOrderImmediateSequence")
        end
        if ai.forceManualOrderNow == true and not Bridge.IsStrictOrderImmediateWindow(brain, order) then
            ai.forceManualOrderNow = false
            removed = removed + 1
        end
        local seq = tonumber(order.sequence)
        local consumedSeq = tonumber(ai.manualOrderConsumedSequence)
        local consumedAt = tonumber(ai.manualOrderConsumedAtMs) or 0
        local staleConsumedMs = tonumber(cfg.staleConsumedMs) or 90000
        if consumedSeq and seq and consumedSeq ~= seq and nowMs - consumedAt > staleConsumedMs then
            removed = removed + Bridge.ClearMercenaryOrderRuntimeField(ai, "manualOrderConsumedIssued")
            removed = removed + Bridge.ClearMercenaryOrderRuntimeField(ai, "manualOrderConsumedSequence")
            removed = removed + Bridge.ClearMercenaryOrderRuntimeField(ai, "manualOrderConsumedAtMs")
        end
        local staleDebugMs = tonumber(cfg.staleDebugMs) or 180000
        local watchdogAt = tonumber(ai.lastStrictOrderWatchdogCheckAtMs) or 0
        if watchdogAt > 0 and nowMs - watchdogAt > staleDebugMs then
            removed = removed + Bridge.ClearMercenaryOrderRuntimeField(ai, "lastStrictOrderWatchdogReason")
            removed = removed + Bridge.ClearMercenaryOrderRuntimeField(ai, "lastStrictOrderWatchdogReapplyReason")
        end
    end

    Bridge.MercenaryOrderCleanupState = Bridge.MercenaryOrderCleanupState or {checked=0, removed=0, lastRunAtMs=0}
    Bridge.MercenaryOrderCleanupState.checked = (tonumber(Bridge.MercenaryOrderCleanupState.checked) or 0) + 1
    Bridge.MercenaryOrderCleanupState.removed = (tonumber(Bridge.MercenaryOrderCleanupState.removed) or 0) + removed
    Bridge.MercenaryOrderCleanupState.lastRunAtMs = nowMs
    Bridge.IncMercenaryOrderStat("strict.cleanup.checked", 1)
    if removed > 0 then Bridge.IncMercenaryOrderStat("strict.cleanup.removed", removed) end
    return removed
end

function Bridge.GetStrictOrderMaster(bandit, brain)
    if NPCBehaviorBridge and NPCBehaviorBridge.GetMasterPlayer then
        local ok, master = pcall(function() return NPCBehaviorBridge.GetMasterPlayer(bandit) end)
        if ok and master then return master end
    end
    if getPlayer then return getPlayer() end
    return nil
end

function Bridge.GetStrictOrderDistance(bandit, brain, order)
    if not (bandit and type(brain) == "table" and type(order) == "table") then return nil, nil, nil end
    local name = bridge_normMercenaryOrderName(order.name)

    -- Stage 375: only Follow is anchored to the player.  Every point order
    -- with a cursor anchor is measured against that exact cursor point.
    -- Guard/Return/FallBack previously reused the player as boundary anchor,
    -- which could pull mercenaries away from the clicked world point.
    if name == "Follow" then
        local target = Bridge.GetStrictOrderMaster(bandit, brain)
        if not target then return nil, nil, nil end
        local dx = (tonumber(bandit:getX()) or 0) - (tonumber(target:getX()) or 0)
        local dy = (tonumber(bandit:getY()) or 0) - (tonumber(target:getY()) or 0)
        local dz = math.abs((tonumber(bandit:getZ()) or 0) - (tonumber(target:getZ()) or 0))
        return math.sqrt(dx * dx + dy * dy), dz, name
    end

    if type(order.anchor) == "table" and order.anchor.x and order.anchor.y then
        local dx = (tonumber(bandit:getX()) or 0) - (tonumber(order.anchor.x) or 0)
        local dy = (tonumber(bandit:getY()) or 0) - (tonumber(order.anchor.y) or 0)
        local dz = math.abs((tonumber(bandit:getZ()) or 0) - (tonumber(order.anchor.z) or tonumber(bandit:getZ()) or 0))
        return math.sqrt(dx * dx + dy * dy), dz, name
    end

    return nil, nil, name
end

function Bridge.GetStrictOrderLeash(brain, name)
    name = bridge_normMercenaryOrderName(name)
    local order = type(brain) == "table" and type(brain.order) == "table" and brain.order or nil
    if order and (order.directMercenaryOrder == true or order.mercenaryDirect == true or brain.orderSystem == "mercenary_direct") and type(order.leash) == "table" then
        if name == "Follow" then return tonumber(order.leash.follow) or 5.5 end
        if name == "Guard" then return tonumber(order.leash.guard) or 9.5 end
        if name == "Hold" then return tonumber(order.leash.hold) or 2.8 end
        return tonumber(order.leash.follow) or 5.5
    end
    if not (NPCOrderContract and NPCOrderContract.GetStrictLeash) then
        if name == "Follow" then return 5.5 end
        if name == "Guard" then return 9.5 end
        if name == "Hold" then return 2.8 end
        return 6.0
    end
    if name == "Follow" then return NPCOrderContract.GetStrictLeash(brain, "follow") or 5.5 end
    if name == "Guard" then return NPCOrderContract.GetStrictLeash(brain, "guard") or 9.5 end
    if name == "Hold" then return NPCOrderContract.GetStrictLeash(brain, "hold") or 2.8 end
    return NPCOrderContract.GetStrictLeash(brain, "follow") or 5.5
end

function Bridge.ShouldReapplyStrictMercenaryOrder(bandit, brain, order)
    if not (bandit and type(brain) == "table" and type(order) == "table") then return false end
    local currentTask = NPCEntity and NPCEntity.GetTask and NPCEntity.GetTask(bandit) or (brain.tasks and brain.tasks[1]) or nil
    if not Bridge.IsManualOrderTaskInterruptible(currentTask) then return false end
    local action = currentTask and tostring(currentTask.action or "") or ""
    local fireMode = NPCOrderContract and NPCOrderContract.GetFireMode and NPCOrderContract.GetFireMode(brain) or tostring(order.fireMode or "")
    if fireMode == "HoldFire" and (action == "Shoot" or action == "Aim" or action == "Hit" or action == "Shove" or action == "Reload") then return true end
    if Bridge.IsStrictTaskOutsideChaseBoundary(bandit, brain, order, currentTask) then return true end

    local dist, zdist, name = Bridge.GetStrictOrderDistance(bandit, brain, order)
    if not name then return false end
    if zdist and zdist > 0.35 then return true end
    if not dist then return false end
    local leash = Bridge.GetStrictOrderLeash(brain, name)
    if dist > leash then return true end
    if currentTask and (name == "Follow" or name == "Hold" or name == "Guard") then
        local directorState = tostring(currentTask.directorState or currentTask.state or "")
        if directorState == "SearchEnemy" or directorState == "PatrolArea" or directorState == "LootArea" or directorState == "FlankEnemy" or directorState == "BoundForward" or directorState == "InvestigateNoise" then
            return true
        end
        if currentTask.combatMove == true and dist > leash * 0.70 then return true end
    end
    return false
end

function Bridge.ReapplyStrictMercenaryOrder(bandit, brain, order)
    if not Bridge.ClearMercenaryOrderCombatState(bandit, brain, order) then return false end
    local immediateTasks = {}
    local queued = Bridge.QueueImmediateMercenaryOrderTask(bandit, brain, order, immediateTasks)
    if queued and #immediateTasks > 0 then
        Bridge.EnqueueGeneratedTasks(bandit, brain, immediateTasks, "strict_order_lock")
        brain.ai = brain.ai or {}
        brain.ai.lastStrictOrderReapplyAtMs = Bridge.NowMs()
        Bridge.IncMercenaryOrderStat("strict.reapply.queued", 1)
        if order and order.name then Bridge.IncMercenaryOrderStat("strict.reapply." .. tostring(order.name), 1) end
        return true
    end
    return false
end

function Bridge.GetStrictMercenaryCombatScanRadius(brain)
    if type(brain) ~= "table" then return nil end
    local order = type(brain.order) == "table" and brain.order or nil
    if type(order) ~= "table" then return nil end
    if order.directMercenaryOrder == true or order.mercenaryDirect == true or brain.orderSystem == "mercenary_direct" then
        if tonumber(order.tacticalCombatRange) then return tonumber(order.tacticalCombatRange) end
        if type(order.leash) == "table" and tonumber(order.leash.combat) then return tonumber(order.leash.combat) end
        return 6.5
    end
    if not (NPCOrderContract and NPCOrderContract.GetStrictCombatRange and NPCOrderContract.IsStrictPlayerOrderActive and NPCOrderContract.IsStrictPlayerOrderActive(brain)) then return nil end
    return NPCOrderContract.GetStrictCombatRange(brain)
end
function Bridge.GetPlayerCommandedTacticalOrder(brain)
    if type(brain) ~= "table" then return nil end
    local order = type(brain.order) == "table" and brain.order or nil
    if type(order) ~= "table" then return nil end
    local direct = order.directMercenaryOrder == true or order.mercenaryDirect == true or brain.orderSystem == "mercenary_direct"
    if direct and bridge_isTacticalMercenaryOrderName(order.name) then return order end
    if not (NPCOrderContract and NPCOrderContract.IsPlayerCommandedTacticalOrderActive and NPCOrderContract.IsPlayerCommandedTacticalOrderActive(brain)) then return nil end
    local ok, got = pcall(function() return NPCOrderContract.Get(brain) end)
    if ok and type(got) == "table" then return got end
    return order
end
function Bridge.IsPlayerTacticalCombatTask(task)
    if type(task) ~= "table" then return false end
    if task.playerTacticalOrder == true or task.playerOrder == true or task.manualOrder == true or task.source == "player" then return false end
    local action = tostring(task.action or "")
    local directorState = tostring(task.directorState or task.state or "")
    return task.combatMove == true
        or task.meleeApproach == true
        or task.targetId ~= nil
        or task.targetKind ~= nil
        or action == "Shoot"
        or action == "Aim"
        or action == "Hit"
        or action == "Shove"
        or directorState == "SearchEnemy"
        or directorState == "FlankEnemy"
        or directorState == "BoundForward"
        or directorState == "SuppressEnemy"
        or directorState == "InvestigateNoise"
        or directorState == "MeleeFallback"
end

function Bridge.QueuePlayerCommandedTacticalOrderTask(bandit, brain, order)
    if not (bandit and type(brain) == "table" and type(order) == "table") then return false end
    if not (NPCBehaviorBridge and NPCBehaviorBridge.CompanionTryMobileOrder) then return false end
    local tasks = {}
    local orderName = bridge_normMercenaryOrderName(order.name)
    local ok, nextStage = pcall(function() return NPCBehaviorBridge.CompanionTryMobileOrder(bandit, brain, orderName, tasks) end)
    if ok and nextStage and #tasks > 0 then
        Bridge.MarkMercenaryOrderTasks(tasks, order, orderName)
        Bridge.EnqueueGeneratedTasks(bandit, brain, tasks, "player_tactical_order")
        brain.ai = brain.ai or {}
        brain.ai.lastPlayerTacticalQueuedAtMs = Bridge.NowMs()
        brain.ai.lastPlayerTacticalQueuedName = orderName
        Bridge.IncMercenaryOrderStat("player_tactical.queued", 1)
        Bridge.IncMercenaryOrderStat("player_tactical." .. tostring(orderName), 1)
        return true
    end
    return false
end

function Bridge.MaintainPlayerCommandedTacticalOrder(bandit, brain, order)
    if not (bandit and type(brain) == "table" and type(order) == "table") then return false end
    local currentTask = NPCEntity and NPCEntity.GetTask and NPCEntity.GetTask(bandit) or (brain.tasks and brain.tasks[1]) or nil
    if currentTask then
        if not Bridge.IsManualOrderTaskInterruptible(currentTask) then return true end
        if currentTask.playerTacticalOrder == true or currentTask.playerOrder == true or currentTask.manualOrder == true or currentTask.source == "player" then
            local taskOrder = tostring(currentTask.orderName or currentTask.tacticalOrderName or "")
            local orderName = tostring(order.name or "")
            if taskOrder == "" or taskOrder == orderName then return true end
        end
        if Bridge.IsPlayerTacticalCombatTask(currentTask) then
            if Bridge.ClearMercenaryOrderCombatState(bandit, brain, order) then
                Bridge.IncMercenaryOrderStat("player_tactical.combat_task_cleared", 1)
                return Bridge.QueuePlayerCommandedTacticalOrderTask(bandit, brain, order)
            end
            return true
        end
        return false
    end
    return Bridge.QueuePlayerCommandedTacticalOrderTask(bandit, brain, order)
end


function Bridge.GetPlayerCommandedMercenaryOrder(brain)
    if type(brain) ~= "table" then return nil end
    local order = type(brain.order) == "table" and brain.order or nil
    if type(order) ~= "table" then return nil end
    local direct = order.directMercenaryOrder == true or order.mercenaryDirect == true or brain.orderSystem == "mercenary_direct" or brain.mercenaryDirectOrders == true or order.source == "player" or order.playerCommand == true
    if direct ~= true then return nil end
    local name = bridge_normMercenaryOrderName(order.name)
    if not name or name == "" then return nil end
    if name == "Follow" or name == "Patrol" then return order end
    if Bridge.IsCursorExactMercenaryPointOrderName and Bridge.IsCursorExactMercenaryPointOrderName(name) then return order end
    if Bridge.IsMercenaryPointOrderDelegatedAfterArrival and Bridge.IsMercenaryPointOrderDelegatedAfterArrival(name) then return order end
    if bridge_isTacticalMercenaryOrderName(name) then return order end
    return nil
end

function Bridge.IsSamePlayerMercenaryOrderTask(task, orderName)
    if type(task) ~= "table" then return false end
    if not (task.playerOrder == true or task.manualOrder == true or task.playerTacticalOrder == true or task.source == "player" or task.mercenaryUnifiedImmediate == true) then return false end
    local taskOrder = tostring(task.orderName or task.tacticalOrderName or task.strictOrderName or "")
    if taskOrder == "" then return true end
    return taskOrder == tostring(orderName or "")
end

function Bridge.IsMercenaryDirectCombatModeActive(brain, order)
    if type(brain) ~= "table" then return false end
    if not Bridge.IsMercenaryFireDisciplineBrain(brain) then return false end
    order = type(order) == "table" and order or (type(brain.order) == "table" and brain.order or nil)
    if type(order) ~= "table" then return false end
    local direct = order.directMercenaryOrder == true or order.mercenaryDirect == true or brain.orderSystem == "mercenary_direct" or brain.mercenaryDirectOrders == true or order.playerCommand == true
    if direct ~= true then return false end
    local fireMode = NPCOrderContract and NPCOrderContract.GetFireMode and NPCOrderContract.GetFireMode(brain) or order.fireMode
    if NPCOrderContract and NPCOrderContract.NormalizeFireMode then fireMode = NPCOrderContract.NormalizeFireMode(fireMode) end
    if fireMode == "HoldFire" or fireMode == "MeleeOnly" then return false end
    return fireMode == "FireAtWill" or fireMode == "Defensive" or fireMode == "ReturnFire" or fireMode == "DangerClose" or fireMode == "Suppress"
end

function Bridge.IsMercenaryDirectCombatHoldPositionTask(task)
    if type(task) ~= "table" then return false end
    local action = tostring(task.action or "")
    local directorState = tostring(task.directorState or task.state or "")

    -- Stage 391: player-commanded mercenaries may shoot/aim/reload in combat,
    -- but they must not chase threats or abandon the current Follow/Guard/Hold/
    -- Patrol/SearchHouse position.  Drop only locomotion/chase tasks; keep
    -- weapon and close-contact tasks.
    if action == "Move" or action == "GoTo" then return true end
    if action == "PathFind" or action == "Walk" or action == "Run" then return true end
    if task.meleeApproach == true then return true end
    if directorState == "SearchEnemy"
        or directorState == "MeleeFallback"
        or directorState == "CombatMemory"
        or directorState == "FlankEnemy"
        or directorState == "BoundForward"
        or directorState == "InvestigateNoise"
        or directorState == "KeepDistance" then
        return true
    end
    return false
end

function Bridge.GetMercenaryDirectCombatTaskTargetPoint(task)
    if type(task) ~= "table" then return nil, nil, nil end
    local x = tonumber(task.x)
    local y = tonumber(task.y)
    local z = tonumber(task.z)
    if x and y then return x, y, z end
    return nil, nil, nil
end

function Bridge.FilterMercenaryDirectCombatHoldPositionTasks(bandit, brain, order, tasks)
    if type(tasks) ~= "table" or #tasks == 0 then return tasks, false, false end

    local filtered = {}
    local droppedMove = false
    local targetX, targetY, targetZ = nil, nil, nil
    local closeContactLimit = 1.75

    for _, task in ipairs(tasks) do
        if type(task) == "table" then
            local action = tostring(task.action or "")
            local tx, ty, tz = Bridge.GetMercenaryDirectCombatTaskTargetPoint(task)
            if tx and ty then targetX, targetY, targetZ = tx, ty, tz end

            if Bridge.IsMercenaryDirectCombatHoldPositionTask(task) then
                droppedMove = true
            elseif action == "Hit" or action == "Shove" then
                -- Close contact is allowed, but never path toward the enemy.
                local dist = nil
                if tx and ty and bandit and bandit.getX and bandit.getY and NPCUtils and NPCUtils.DistTo then
                    dist = NPCUtils.DistTo(bandit:getX(), bandit:getY(), tx, ty)
                end
                if dist == nil or dist <= closeContactLimit then
                    task.mercenaryHoldPositionCombat = true
                    filtered[#filtered + 1] = task
                else
                    droppedMove = true
                end
            else
                -- Aim/Shoot/Reload/Equip/Unequip/FaceLocation/Time are allowed:
                -- they do not pull the squad out of its order lane.
                task.mercenaryHoldPositionCombat = true
                filtered[#filtered + 1] = task
            end
        end
    end

    local hasAction = #filtered > 0
    if not hasAction and droppedMove == true and targetX and targetY then
        -- If the combat brain wanted to chase but we forbid chase, still stop the
        -- current movement briefly and face the threat.  This makes FireAtWill
        -- feel responsive without turning it into pursuit behavior.
        local task = {
            action = "FaceLocation",
            anim = "Idle",
            x = targetX,
            y = targetY,
            z = targetZ,
            time = 80,
            playerOrderCombat = true,
            mercenaryHoldPositionCombat = true,
            holdPositionCombatFace = true,
            routerPreempt = true,
            routerPriority = 88,
            routerTtlMs = 260
        }
        filtered[#filtered + 1] = task
        hasAction = true
    end

    return filtered, hasAction, droppedMove
end

function Bridge.TryMercenaryDirectCombatPreempt(bandit, brain, order, uTick)
    if not Bridge.IsMercenaryDirectCombatModeActive(brain, order) then return false end
    local currentTask = NPCEntity and NPCEntity.GetTask and NPCEntity.GetTask(bandit) or (brain and brain.tasks and brain.tasks[1]) or nil
    if currentTask and not Bridge.IsManualOrderTaskInterruptible(currentTask) then return false end
    brain.ai = brain.ai or {}
    local nowMs = Bridge.NowMs and Bridge.NowMs() or (getTimestampMs and getTimestampMs() or 0)
    local last = tonumber(brain.ai.lastMercenaryDirectCombatPreemptAtMs) or 0
    if nowMs > 0 and nowMs - last < 260 then return false end

    local tasks = Bridge.ManageCombat and Bridge.ManageCombat(bandit, uTick) or nil
    if type(tasks) ~= "table" or #tasks == 0 then return false end

    if Bridge.FilterMercenaryDirectCombatHoldPositionTasks then
        local filtered, hasAction, droppedMove = Bridge.FilterMercenaryDirectCombatHoldPositionTasks(bandit, brain, order, tasks)
        tasks = filtered
        if droppedMove == true then
            brain.ai.lastMercenaryDirectCombatHoldPositionAtMs = nowMs
            brain.ai.lastMercenaryDirectCombatHoldPositionOrder = order and order.name or nil
        end
        if type(tasks) ~= "table" or #tasks == 0 or hasAction ~= true then return false end
    end

    local hasCombat = false
    for _, task in ipairs(tasks) do
        local action = tostring(task and task.action or "")
        if action == "Shoot" or action == "Aim" or action == "Hit" or action == "Shove" or action == "Reload" or action == "Equip" or action == "Unequip" or action == "FaceLocation" or task.targetId ~= nil or task.mercenaryHoldPositionCombat == true then
            hasCombat = true
            task.playerOrderCombat = true
            task.allowCombatPreempt = true
            task.routerPreempt = true
            task.mercenaryHoldPositionCombat = true
            -- Do not let Aim/Shoot tasks be interpreted by downstream filters as
            -- permission to path toward the enemy.
            if action ~= "Move" and action ~= "GoTo" then
                task.combatMove = false
                task.meleeApproach = false
            end
        end
    end
    if not hasCombat then return false end

    brain.ai.lastMercenaryDirectCombatPreemptAtMs = nowMs
    brain.ai.lastMercenaryDirectCombatPreemptOrder = order and order.name or nil
    if currentTask and Bridge.IsCombatPreemptibleTask and Bridge.IsCombatPreemptibleTask(currentTask) then
        if NPCEntity and NPCEntity.ClearTasks then pcall(function() NPCEntity.ClearTasks(bandit) end) end
        brain.tasks = {}
    end
    Bridge.EnqueueGeneratedTasks(bandit, brain, tasks, "mercenary_direct_combat")
    Bridge.IncMercenaryOrderStat("mercenary_direct.combat_preempt", 1)
    return true
end

function Bridge.MaintainPlayerCommandedMercenaryOrder(bandit, brain, order)
    if not (bandit and type(brain) == "table" and type(order) == "table") then return false end
    local name = bridge_normMercenaryOrderName(order.name)
    if not name or name == "" then return false end
    brain.ai = brain.ai or {}
    local currentTask = NPCEntity and NPCEntity.GetTask and NPCEntity.GetTask(bandit) or (brain.tasks and brain.tasks[1]) or nil
    if currentTask then
        if not Bridge.IsManualOrderTaskInterruptible(currentTask) then return true end
        if currentTask.mercenaryAmbientIdle == true then return true end
        if Bridge.IsSamePlayerMercenaryOrderTask(currentTask, name) then
            if name == "Follow" and Bridge.IsStrictOrderImmediateTaskCompliant then
                local okCompliant, compliant = pcall(function() return Bridge.IsStrictOrderImmediateTaskCompliant(bandit, brain, order, currentTask) end)
                if okCompliant and compliant == false then
                    local nowMs = Bridge.NowMs and Bridge.NowMs() or (getTimestampMs and getTimestampMs() or 0)
                    local last = tonumber(brain.ai.lastMercenaryMaintainRepathAtMs) or 0
                    if nowMs - last < 520 then return true end
                    brain.ai.lastMercenaryMaintainRepathAtMs = nowMs
                else
                    return true
                end
            else
                return true
            end
        end
        if currentTask.playerOrder == true or currentTask.manualOrder == true or currentTask.playerTacticalOrder == true or Bridge.IsPlayerTacticalCombatTask(currentTask) then
            Bridge.ClearMercenaryOrderCombatState(bandit, brain, order)
        else
            return false
        end
    end

    local tasks = {}
    local queued = Bridge.QueueImmediateMercenaryOrderTask(bandit, brain, order, tasks)
    if queued then
        if #tasks > 0 then
            Bridge.EnqueueGeneratedTasks(bandit, brain, tasks, "player_mercenary_order")
            Bridge.IncMercenaryOrderStat("player_mercenary.queued", 1)
            Bridge.IncMercenaryOrderStat("player_mercenary." .. tostring(name), 1)
        end
        return true
    end
    return false
end

function Bridge.EnqueueGeneratedTasks(bandit, brain, tasks, source)
    if not (brain and tasks and #tasks > 0) then return 0 end

    if NPCActionRouterBridge and NPCActionRouterBridge.FilterTasks then
        local ok, routed = pcall(function()
            return NPCActionRouterBridge.FilterTasks(bandit, brain, tasks, {source = source or "npc_update"})
        end)
        if ok and routed then tasks = routed end
    end

    if not tasks or #tasks == 0 then return 0 end
    brain.tasks = brain.tasks or {}
    local count = 0
    local preemptTasks = {}
    local normalTasks = {}
    for _, task in pairs(tasks) do
        if task and task.action then
            if NPCActionRouterBridge and NPCActionRouterBridge.ShouldPrependTask and NPCActionRouterBridge.ShouldPrependTask(task) then
                preemptTasks[#preemptTasks + 1] = task
            else
                normalTasks[#normalTasks + 1] = task
            end
        end
    end
    for i = #preemptTasks, 1, -1 do
        table.insert(brain.tasks, 1, preemptTasks[i])
        count = count + 1
    end
    for _, task in pairs(normalTasks) do
        table.insert(brain.tasks, task)
        count = count + 1
    end
    return count
end


-- generates NPC tasks
function Bridge.GenerateTask(bandit, uTick)
    local tasks = {}
    local brain = NPCBrainData.Get(bandit)
    local id = brain and (brain.id or brain.uid or brain.persistentId) or NPCUtils.GetZombieID(bandit)
    Bridge.EnsurePlayerCommandAuthorityRuntime(brain)
    local manualOrderPending, manualOrder = Bridge.IsManualMercenaryOrderPending(brain)
    local strictImmediateOrder = Bridge.GetStrictMercenaryOrder(brain)
    Bridge.CleanupStrictMercenaryOrderRuntimeState(brain, strictImmediateOrder)
    local strictImmediateActive = Bridge.IsStrictOrderImmediateWindow(brain, strictImmediateOrder)
    local strictWatchdogDue = Bridge.IsStrictOrderWatchdogDue(brain, strictImmediateOrder)
    if brain then
        brain.ai = brain.ai or {}
        local frameTick = (NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.GetTick and NPCWorkSchedulerBridge.GetTick()) or uTick
        if brain.ai.lastGenerateTaskFrameTick == frameTick and not manualOrderPending and not strictImmediateActive then return end
        brain.ai.lastGenerateTaskFrameTick = frameTick
    end

    local aiAllowed = true
    if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.AllowAI then
        aiAllowed = NPCWorkSchedulerBridge.AllowAI(id, brain, uTick) == true
    end
    if not aiAllowed and not manualOrderPending and not strictImmediateActive and not strictWatchdogDue then
        local noTask = not (NPCEntity and NPCEntity.HasTask and NPCEntity.HasTask(bandit))
        local nowMs = Bridge.NowMs()
        local deniedAt = brain and brain.ai and tonumber(brain.ai.lastAIDeniedAtMs) or nil
        if brain and brain.ai then brain.ai.lastAIDeniedAtMs = deniedAt or nowMs end
        if not (noTask and deniedAt and nowMs - deniedAt > 2600) then
            return
        end
    elseif brain and brain.ai then
        brain.ai.lastAIDeniedAtMs = nil
    end

    if manualOrderPending and Bridge.ClearMercenaryOrderCombatState(bandit, brain, manualOrder) then
        local immediateTasks = {}
        local queued = Bridge.QueueImmediateMercenaryOrderTask(bandit, brain, manualOrder, immediateTasks)
        if queued and #immediateTasks > 0 then
            Bridge.EnqueueGeneratedTasks(bandit, brain, immediateTasks, "manual_order")
            Bridge.IncMercenaryOrderStat("manual_order.queued", 1)
            if manualOrder and manualOrder.name then Bridge.IncMercenaryOrderStat("manual_order." .. tostring(manualOrder.name), 1) end
            Bridge.MarkManualMercenaryOrderConsumed(brain, manualOrder)
            return
        end
        if not (manualOrder and manualOrder.sticky == true) then
            Bridge.MarkManualMercenaryOrderConsumed(brain, manualOrder)
        end
        return
    end

    local playerMercenaryOrder = Bridge.GetPlayerCommandedMercenaryOrder and Bridge.GetPlayerCommandedMercenaryOrder(brain) or nil
    if playerMercenaryOrder and Bridge.TryMercenaryDirectCombatPreempt and Bridge.TryMercenaryDirectCombatPreempt(bandit, brain, playerMercenaryOrder, uTick) then
        return
    end
    if playerMercenaryOrder and Bridge.MaintainPlayerCommandedMercenaryOrder and Bridge.MaintainPlayerCommandedMercenaryOrder(bandit, brain, playerMercenaryOrder) then
        if brain and brain.ai then brain.ai.forceManualOrderNow = false end
        return
    end

    if strictImmediateActive and Bridge.ShouldImmediateReapplyStrictMercenaryOrder(bandit, brain, strictImmediateOrder) then
        if Bridge.ReapplyStrictMercenaryOrder(bandit, brain, strictImmediateOrder) then
            if brain and brain.ai then brain.ai.forceManualOrderNow = false end
            return
        end
    end

    if strictWatchdogDue and Bridge.ShouldWatchdogReapplyStrictMercenaryOrder(bandit, brain, strictImmediateOrder) then
        if Bridge.ReapplyStrictMercenaryOrder(bandit, brain, strictImmediateOrder) then
            if brain and brain.ai then brain.ai.forceManualOrderNow = false end
            return
        end
    end
    if not aiAllowed and not manualOrderPending and not strictImmediateActive then return end

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
            Bridge.EnqueueGeneratedTasks(bandit, brain, tasks, "black_market_program")
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

    -- STRICT PLAYER ORDER LOCK BEFORE AMBIENT AVOIDANCE
    if #tasks == 0 then
        local strictOrder = Bridge.GetStrictMercenaryOrder(brain)
        if strictOrder and Bridge.ShouldReapplyStrictMercenaryOrder(bandit, brain, strictOrder) then
            if Bridge.ReapplyStrictMercenaryOrder(bandit, brain, strictOrder) then return end
        end
    end

    -- AVOIDANCE
    if #tasks == 0 and uTick % 4 == 0 then
        local avoidanceTasks = Bridge.ManagePreservation(bandit)
        if #avoidanceTasks > 0 then
            for _, t in pairs(avoidanceTasks) do table.insert(tasks, t) end
        end
    end

    -- STRICT PLAYER ORDER LOCK
    -- Hired mercenaries may defend themselves nearby, but Follow/Hold/Guard-style
    -- player orders must pull them back before regular combat generation can make
    -- them chase distant targets or overwrite the command.
    if #tasks == 0 then
        local strictOrder = Bridge.GetStrictMercenaryOrder(brain)
        if strictOrder and Bridge.ShouldReapplyStrictMercenaryOrder(bandit, brain, strictOrder) then
            if Bridge.ReapplyStrictMercenaryOrder(bandit, brain, strictOrder) then return end
        end
    end

    -- PLAYER-COMMANDED FIRE MODE LOCK
    -- If a fire-mode change is active, do not let a stale combat task from the
    -- previous mode keep running until the next normal combat decision.
    if #tasks == 0 and brain and Bridge.IsMercenaryFireDisciplineBrain(brain) then
        local order = NPCOrderContract and NPCOrderContract.Get and NPCOrderContract.Get(brain) or nil
        local currentTask = NPCEntity and NPCEntity.GetTask and NPCEntity.GetTask(bandit) or (brain.tasks and brain.tasks[1]) or nil
        if currentTask and Bridge.IsManualOrderTaskInterruptible(currentTask) and Bridge.IsMercenaryFireModeTaskDenied and Bridge.IsMercenaryFireModeTaskDenied(bandit, brain, order, currentTask) then
            if Bridge.ClearMercenaryOrderCombatState(bandit, brain, order) then
                Bridge.IncMercenaryOrderStat("fire_mode.task_cleared", 1)
            end
        end
    end

    -- PLAYER-COMMANDED TACTICAL ORDER LOCK
    -- Tactical commands such as TakeCover/Flank/WatchSector are direct player
    -- orders. Keep them above normal combat generation so the combat AI cannot
    -- insert a chase/shoot/move task before the ordered tactical slot is reached.
    if #tasks == 0 then
        local tacticalOrder = Bridge.GetPlayerCommandedTacticalOrder(brain)
        if tacticalOrder and Bridge.MaintainPlayerCommandedTacticalOrder(bandit, brain, tacticalOrder) then return end
    end

    -- MANAGE MELEE / SHOOTING TASKS
    if #tasks == 0 and Bridge.ShouldRunAdaptiveCombatFrame(bandit, brain, uTick) then
        local combatCritical = NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.IsCombatCritical and NPCWorkSchedulerBridge.IsCombatCritical(bandit, brain)
        if Bridge.HasActiveBattlefieldMemory(brain) then combatCritical = true end
        local asyncQueued = false
        if not combatCritical and NPCAsyncSchedulerBridge and NPCAsyncSchedulerBridge.EnqueueCombatScan then
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
        Bridge.EnqueueGeneratedTasks(bandit, brain, tasks, "npc_update")
        -- NPCBrainData.Update(zombie, brain)
    end
end


function Bridge.EnforceBlackMarketDefenseZone(bandit, brain)
    if not (bandit and brain and brain.blackMarketDefenseEnemy == true) then return true end
    local center = brain.blackMarketDefenseCenter or brain.returnPoint or (type(brain.order) == "table" and (brain.order.anchor or brain.order.guardPoint)) or brain.guardPoint or brain.holdPoint
    if not (type(center) == "table" and center.x and center.y) then return true end
    local cx = tonumber(center.x)
    local cy = tonumber(center.y)
    local cz = tonumber(center.z) or (bandit.getZ and bandit:getZ()) or 0
    if not (cx and cy) then return true end
    local radius = math.max(3, tonumber(brain.blackMarketDefenseZoneRadius or brain.checkpointHoldRadius or brain.blackMarketQuestGuardLeash) or 18)
    local function dist2(x, y)
        local dx = (tonumber(x) or cx) - cx
        local dy = (tonumber(y) or cy) - cy
        return dx * dx + dy * dy
    end
    local function clampedPoint(x, y)
        x = tonumber(x) or cx
        y = tonumber(y) or cy
        local dx = x - cx
        local dy = y - cy
        local d = math.sqrt(dx * dx + dy * dy)
        local maxR = math.max(2, radius - 4)
        if d <= 0.01 then return cx + 0.5, cy + 0.5, cz end
        local scale = math.min(d, maxR) / d
        return cx + dx * scale, cy + dy * scale, cz
    end

    local target = nil
    if bandit.getTarget then
        local ok, got = pcall(function() return bandit:getTarget() end)
        if ok then target = got end
    end
    if target and target.getX and target.getY and dist2(target:getX(), target:getY()) > radius * radius then
        if bandit.setTarget then pcall(function() bandit:setTarget(nil) end) end
        if bandit.setAttackedBy then pcall(function() bandit:setAttackedBy(nil) end) end
        if bandit.clearAggroList then pcall(function() bandit:clearAggroList() end) end
        brain.currentThreat = nil
        brain.lastThreat = nil
        brain.targetId = nil
        brain.targetKind = nil
    end

    local task = NPCEntity and NPCEntity.GetTask and NPCEntity.GetTask(bandit) or nil
    if type(task) == "table" and (task.action == "Move" or task.action == "GoTo") and task.x and task.y and dist2(task.x, task.y) > radius * radius then
        local tx, ty, tz = clampedPoint(task.x, task.y)
        task.x = tx
        task.y = ty
        task.z = tz
        task.walkType = "Run"
        task.blackMarketDefenseClamped = true
    end

    local bx = bandit.getX and bandit:getX() or nil
    local by = bandit.getY and bandit:getY() or nil
    if bx and by and dist2(bx, by) > radius * radius then
        local tx, ty, tz = clampedPoint(cx + ((tonumber(brain.memberIndex) or 1) % 5) - 2, cy + ((tonumber(brain.memberIndex) or 1) % 3) - 1)
        if NPCEntity and NPCEntity.ClearTasks then pcall(function() NPCEntity.ClearTasks(bandit) end) end
        if bandit.setTarget then pcall(function() bandit:setTarget(nil) end) end
        if bandit.setAttackedBy then pcall(function() bandit:setAttackedBy(nil) end) end
        if bandit.clearAggroList then pcall(function() bandit:clearAggroList() end) end
        if bandit.setX then pcall(function() bandit:setX(tx) end) end
        if bandit.setY then pcall(function() bandit:setY(ty) end) end
        if bandit.setZ then pcall(function() bandit:setZ(tz) end) end
        brain.x = tx
        brain.y = ty
        brain.z = tz
        brain.debugCoords = {x=tx, y=ty, z=tz}
        brain.tasks = {}
        brain.currentThreat = nil
        brain.lastThreat = nil
        brain.targetId = nil
        brain.targetKind = nil
        if NPCBrainData and NPCBrainData.Update then pcall(function() NPCBrainData.Update(bandit, brain) end) end
        return false
    end
    return true
end

-- neutral client event dispatchers formerly owned by the legacy update facade
function Bridge.OnNPCUpdate(zombie, uTick)
    uTick = tonumber(uTick) or 0

    local ts = getTimestampMs()
    
    if isServer() then return uTick end

    if not NPCEntity.Engine then return uTick end

    if Bridge.MaybePruneRuntimeCaches then
        Bridge.MaybePruneRuntimeCaches(ts)
    end

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
                if Bridge.RuntimeKnownPhysical(gmd, id) or Bridge.IsBlackMarketNoCombatBrain(NPCBrainData.Get(zombie)) or Bridge.ProtectWoundedRuntime(zombie, brain) then
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

    if brain and zombie:getVariableBoolean(NPC_LEGACY_KEYS.FLAG) and NPCIdentityReconciliationBridge and NPCIdentityReconciliationBridge.ReconcileRuntimeObject then
        local okRecon, reconciledBrain = pcall(function()
            return NPCIdentityReconciliationBridge.ReconcileRuntimeObject(gmd, zombie, brain, id, "client_npc_update")
        end)
        if okRecon and type(reconciledBrain) == "table" then
            brain = reconciledBrain
        end
    end

    if brain and zombie:getVariableBoolean(NPC_LEGACY_KEYS.FLAG) then
        Bridge.EnforceLiveNPCNotVanillaZombie(zombie, brain, "pre_zombie_update_gate")
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
    local skipZombieVsNPC = false
    if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.IsPanic then
        local okPanic, panic = pcall(function() return NPCWorkSchedulerBridge.IsPanic(false) end)
        skipZombieVsNPC = okPanic and panic == true and not zombie:getVariableBoolean(NPC_LEGACY_KEYS.FLAG)
    end
    local fastZombieNPCUpdate = Bridge.ShouldFastZombieNPCUpdate(zombie, uTick)
    if uTick % 2 == 0 and (fastZombieNPCUpdate or (not skipZombieVsNPC and (not NPCWorkSchedulerBridge or not NPCWorkSchedulerBridge.AllowZombieUpdate or NPCWorkSchedulerBridge.AllowZombieUpdate(id, uTick)))) then
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
    if not NPCZombieCacheBridge.CacheLightB[id] and brain and zombie:getVariableBoolean(NPC_LEGACY_KEYS.FLAG) then
        Bridge.EnsureImmediateNPCLightCache(zombie, id, brain)
    end
    if NPCZombieCacheBridge.CacheLightB[id] then 
        if not isBlackMarketNPC and zombie.setUseless then pcall(function() zombie:setUseless(false) end) end
    elseif isBlackMarketNPC then
        Bridge.KeepBlackMarketStanding(zombie)
    else
        Bridge.EnforceLiveNPCNotVanillaZombie(zombie, brain, "outside_light_cache")
        if zombie.setUseless then pcall(function() zombie:setUseless(true) end) end
        return uTick
    end
    
    local bandit = zombie
    local isNoCombatBrain = Bridge.IsBlackMarketNoCombatBrain(brain)
    Bridge.EnforceLiveNPCNotVanillaZombie(bandit, brain, "npc_update_start")

    -- IF TELEPORTING THEN THERE IS NO SENSE IN PROCEEDING
    if bandit:isTeleporting() then
        return uTick
    end

    if brain.blackMarketDefenseEnemy == true then
        Bridge.EnforceBlackMarketDefenseZone(bandit, brain)
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
            Bridge.IncRuntimeOptimizationStat("physical_update_denied")
            if NPCDiagnosticsBridge and NPCDiagnosticsBridge.TraceNPCFrame then
                NPCDiagnosticsBridge.TraceNPCFrame("physical_denied", bandit, brain, NPCEntity and NPCEntity.GetTask and NPCEntity.GetTask(bandit) or nil, {uTick=uTick}, nil, false)
            end
            Bridge.EnforceLiveNPCNotVanillaZombie(bandit, brain, "physical_update_denied")
            NPCEntity.SurpressZombieSounds(bandit)
            return uTick
        end
    end

    -- WALKTYPE
    -- we do it this way, if walktype get overwritten by game engine we force our animations
    local bridgeWalkType = zombie:getVariableString(NPC_LEGACY_KEYS.WALK_TYPE)
    if Bridge.IsHumanAnimationBrain(brain) then
        if not bridgeWalkType or bridgeWalkType == "" or bridgeWalkType == "1" or bridgeWalkType == "2" then bridgeWalkType = "Walk" end
        Bridge.ApplyHumanAnimationSanity(zombie, brain, bridgeWalkType)
    end
    zombie:setWalkType(bridgeWalkType)

    -- NO ZOMBIE SOUNDS
    NPCEntity.SurpressZombieSounds(bandit)

    -- ZOOM-OUT RENDER RELIEF
    if NPCRenderReliefBridge and NPCRenderReliefBridge.ApplyCharacterRelief then
        pcall(function() NPCRenderReliefBridge.ApplyCharacterRelief(bandit, brain, id) end)
    end

    -- XHIGH RENDER PROXY
    -- Collapse distant autonomous NPC frames under extreme zoom/FPS pressure. Player-owned
    -- mercenaries stay outside this proxy path so menu orders remain immediate.
    if NPCRenderReliefBridge and NPCRenderReliefBridge.ShouldUseFarNPCProxy then
        local proxy = false
        local okProxy, retProxy = pcall(function() return NPCRenderReliefBridge.ShouldUseFarNPCProxy(bandit, brain, id, uTick) end)
        if okProxy then proxy = retProxy == true end
        if proxy then
            if NPCRenderReliefBridge.ApplyProxyFrame then pcall(function() NPCRenderReliefBridge.ApplyProxyFrame(bandit, brain) end) end
            return uTick
        end
    end

    -- CANNIBALS
    if not brain.eatBody then
        bandit:setEatBodyTarget(nil, false)
    end
    
    -- ADJUST HUMAN VISUALS
    if not NPCWorkSchedulerBridge or not NPCWorkSchedulerBridge.AllowVisualUpdate or NPCWorkSchedulerBridge.AllowVisualUpdate(id, brain, uTick) then
        Bridge.ApplyVisuals(bandit, brain)
    end
    Bridge.EnsureEssentialNPCClothing(bandit, brain)

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
    if brain.blackMarketDefenseEnemy == true then
        Bridge.EnforceBlackMarketDefenseZone(bandit, brain)
    end

    local task = NPCEntity.GetTask(bandit)
    if task then
        Bridge.ProcessTask(bandit, task)
    end

    if NPCDiagnosticsBridge and NPCDiagnosticsBridge.TraceNPCFrame then
        NPCDiagnosticsBridge.TraceNPCFrame("update", bandit, brain, NPCEntity.GetTask(bandit), {uTick=uTick, elapsedMs=(getTimestampMs and (getTimestampMs() - ts) or nil)}, nil, false)
    end
    if NPCDiagnosticsBridge and NPCDiagnosticsBridge.TraceVisibleMaterializedNPC then
        NPCDiagnosticsBridge.TraceVisibleMaterializedNPC("update", bandit, brain, NPCEntity.GetTask(bandit), {uTick=uTick, elapsedMs=(getTimestampMs and (getTimestampMs() - ts) or nil)}, false)
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

        -- Stage 392: bullets/melee from the hiring player or same-owner hired
        -- mercenaries pass through hired mercenaries.  Restore any vanilla hit
        -- health loss and do not trigger hostility/faction punishment.
        if Bridge.IsFriendlyMercenaryDamageSource and Bridge.IsFriendlyMercenaryDamageSource(attacker, brain) then
            if Bridge.RestoreFriendlyMercenaryHealth then
                Bridge.RestoreFriendlyMercenaryHealth(bandit, brain, "owner_or_squad_friendly_fire")
            end
            return
        end

        if Bridge.MarkMercenaryRetaliationTarget then
            pcall(function() Bridge.MarkMercenaryRetaliationTarget(bandit, brain, attacker, handWeapon) end)
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

    -- Stage 448: NPC corpses must remain as normal lootable corpses after death.
    -- Data/markers are still removed below, but loaded corpse objects are protected
    -- from the runtime cleanup queues so players can inspect and loot them.
    local deathMd = bandit.getModData and bandit:getModData() or nil
    if deathMd then
        deathMd.NPCKeepCorpse = true
        deathMd.NPCLootableCorpse = true
        deathMd.NPCCorpseFromNPCCombat = true
        deathMd.NPCCorpseDeathAt = Bridge.NowMs and Bridge.NowMs() or (getTimestampMs and getTimestampMs() or 0)
    end
    if NPCEntity and NPCEntity.UpdateItemsToSpawnAtDeath then
        pcall(function() NPCEntity.UpdateItemsToSpawnAtDeath(bandit) end)
    end

    -- hostility against civilians (clan=0) is handled by other mods
    local brain = NPCBrainData.Get(bandit)
    if type(brain) ~= "table" then
        if bandit.setVariable then
            bandit:setVariable(NPC_LEGACY_KEYS.FLAG, false)
        end
        if NPCBrainData and NPCBrainData.Remove then
            pcall(function() NPCBrainData.Remove(bandit) end)
        end
        return
    end
    if Bridge.IsBlackMarketNoCombatBrain(brain) then
        local player = getPlayer()
        if player and brain then
            sendClientCommand(player, 'NPCBlackMarket', 'NPCDead', {contactId=brain.blackMarketId, runtimeId=brain.id})
        end
        return
    end
    if brain.blackMarketDefenseEnemy == true then
        local player = getPlayer()
        local runtimeId = nil
        if NPCUtils and NPCUtils.GetZombieID then
            local okRuntime, gotRuntime = pcall(function() return NPCUtils.GetZombieID(bandit) end)
            if okRuntime and gotRuntime ~= nil then runtimeId = gotRuntime end
        end
        brain.dead = true
        brain.isDead = true
        if NPCBrainData and NPCBrainData.Update then pcall(function() NPCBrainData.Update(bandit, brain) end) end
        if player then
            sendClientCommand(player, 'NPCBlackMarket', 'DefenseQuest', {
                action='enemyDead',
                questId=brain.blackMarketDefenseQuestId or brain.blackMarketQuestId,
                runtimeId=runtimeId or brain.id,
                id=runtimeId or brain.id,
                zombieId=runtimeId,
                characterId=runtimeId,
                brainId=brain.id,
                persistentId=brain.persistentId or brain.uid,
                uid=brain.uid,
                memberIndex=brain.memberIndex,
                groupId=brain.worldGroupId or brain.groupId,
                worldGroupId=brain.worldGroupId or brain.groupId,
                x=bandit.getX and bandit:getX() or nil,
                y=bandit.getY and bandit:getY() or nil,
                z=bandit.getZ and bandit:getZ() or nil
            })
        end
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

    brain = NPCBrainData.Get(bandit) or brain

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
