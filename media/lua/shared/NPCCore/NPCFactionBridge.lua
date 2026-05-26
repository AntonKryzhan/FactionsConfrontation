-- NPCFactionBridge.lua
-- Neutral shared backend for faction side/reputation rules.

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCLegacyContractBridge"

NPCFactionBridge = NPCFactionBridge or {}

NPCFactionBridge.SIDE_RED = "red"
NPCFactionBridge.SIDE_GREEN = "green"
NPCFactionBridge.SIDE_BLUE = "blue"
NPCFactionBridge.SIDE_BLACK = "black"

NPCFactionBridge.SIDE_MASK = NPCFactionBridge.SIDE_MASK or {
    red = 1,
    green = 2,
    blue = 4,
    black = 8
}

NPCFactionBridge.ENEMY_MASK = NPCFactionBridge.ENEMY_MASK or {
    red = 2 + 8,
    green = 1 + 8,
    blue = 0,
    black = 1 + 2 + 4 + 8
}

function NPCFactionBridge.GetSideMask(side)
    side = NPCFactionBridge.NormalizeSide(side) or NPCFactionBridge.SIDE_BLUE
    return NPCFactionBridge.SIDE_MASK[side] or 0
end

function NPCFactionBridge.MaskHas(mask, flag)
    if NPCRuntimeCacheBridge and NPCRuntimeCacheBridge.MaskHas then
        return NPCRuntimeCacheBridge.MaskHas(mask, flag)
    end
    mask = tonumber(mask) or 0
    flag = tonumber(flag) or 0
    if flag <= 0 then return false end
    local div = math.floor(mask / flag)
    return (div % 2) >= 1
end

local function bf_settingNumber(name, defaultValue, minValue, maxValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        return NPCLegacySettingsBridge.GetNumber(name, defaultValue, minValue, maxValue)
    end
    local value = tonumber(defaultValue) or 0
    if minValue ~= nil and value < minValue then value = minValue end
    if maxValue ~= nil and value > maxValue then value = maxValue end
    return value
end

local function bf_settingBool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        return NPCLegacySettingsBridge.GetBool(name, defaultValue == true)
    end
    return defaultValue == true
end

local function bf_nowHours()
    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then
            local ok, value = pcall(function() return gt:getWorldAgeHours() end)
            if ok and value then return tonumber(value) or 0 end
        end
    end
    return os.time() / 3600
end

local function bf_playerId(player)
    if not player then return nil end
    if NPCUtils and NPCUtils.GetCharacterID then
        local ok, id = pcall(function() return NPCUtils.GetCharacterID(player) end)
        if ok and id ~= nil then return id end
    end
    if player.getOnlineID then
        local ok, id = pcall(function() return player:getOnlineID() end)
        if ok and id ~= nil then return id end
    end
    return nil
end

local function bf_playerName(player)
    if not player then return nil end
    if player.getUsername then
        local ok, name = pcall(function() return player:getUsername() end)
        if ok and name then return tostring(name) end
    end
    if player.getDisplayName then
        local ok, name = pcall(function() return player:getDisplayName() end)
        if ok and name then return tostring(name) end
    end
    return nil
end

function NPCFactionBridge.NormalizeSide(side)
    side = tostring(side or ""):lower()
    if side == "friendly" then return NPCFactionBridge.SIDE_GREEN end
    if side == "hostile" then return NPCFactionBridge.SIDE_RED end
    if side == "neutral" then return NPCFactionBridge.SIDE_BLUE end
    if side == "rogue" or side == "deserter" or side == "renegade" then return NPCFactionBridge.SIDE_BLACK end
    if side == NPCFactionBridge.SIDE_RED or side == NPCFactionBridge.SIDE_GREEN or side == NPCFactionBridge.SIDE_BLUE or side == NPCFactionBridge.SIDE_BLACK then
        return side
    end
    return nil
end

function NPCFactionBridge.SideFromOption(value)
    value = tonumber(value) or 3
    if value == 1 then return NPCFactionBridge.SIDE_RED end
    if value == 2 then return NPCFactionBridge.SIDE_GREEN end
    if value == 4 then return NPCFactionBridge.SIDE_BLACK end
    return NPCFactionBridge.SIDE_BLUE
end

function NPCFactionBridge.DefaultPlayerSide()
    return NPCFactionBridge.SideFromOption(bf_settingNumber("Faction_DefaultPlayerSide", 3, 1, 4))
end

function NPCFactionBridge.BlackDurationHours()
    return bf_settingNumber("Faction_BlackDurationMinutes", 30, 1, 1440) / 60
end

function NPCFactionBridge.IsEnabled()
    return bf_settingBool("Faction_Enabled", true)
end

function NPCFactionBridge.IsMenuEnabled()
    return bf_settingBool("Faction_PlayerMenuEnabled", true)
end

function NPCFactionBridge.IsPlayerAutoSideEnabled()
    return bf_settingBool("Faction_PlayerAutoSideOnHit", true)
end

function NPCFactionBridge.IsServiceBrain(brain)
    if type(brain) ~= "table" then return false end
    if brain.blackMarket == true or brain.isBlackMarket == true or brain.noFaction == true then return true end
    if brain.tradeNpc == true or brain.serviceNpc == true or brain.blackMarketId ~= nil then return true end
    local function isBlackMarketValue(value)
        value = tostring(value or ""):lower()
        return value == "black_market" or value == "black_market_service" or value == "black_market_static" or value == "blackmarket" or value == "black market"
    end
    if isBlackMarketValue(brain.factionSide) or isBlackMarketValue(brain.faction) or isBlackMarketValue(brain.side) then return true end
    if isBlackMarketValue(brain.special) or isBlackMarketValue(brain.serviceType) or isBlackMarketValue(brain.factionState) then return true end
    if type(brain.program) == "table" and (isBlackMarketValue(brain.program.name) or isBlackMarketValue(brain.program.stage)) then return true end
    return false
end


local function bf_sameId(a, b)
    if a == nil or b == nil then return false end
    return tostring(a) == tostring(b)
end

local function bf_threatMatchesPlayer(threat, playerId)
    if type(threat) ~= "table" or playerId == nil then return false end
    local kind = threat.kind or threat.targetKind
    if kind and tostring(kind) ~= "player" then return false end
    return bf_sameId(threat.id or threat.targetId or threat.eid, playerId)
end

local function bf_clearBrainPlayerThreat(brain, playerId)
    if not brain or playerId == nil then return false end
    local changed = false

    if brain.targetKind == "player" and bf_sameId(brain.targetId, playerId) then
        brain.targetId = nil
        brain.targetKind = nil
        brain.targetDist = nil
        changed = true
    end

    if brain.fsm and brain.fsm.targetKind == "player" and bf_sameId(brain.fsm.targetId, playerId) then
        brain.fsm.targetId = nil
        brain.fsm.targetKind = nil
        brain.fsm.targetDist = nil
        brain.fsm.targetMemoryOnly = nil
        brain.fsm.targetCanSee = nil
        brain.fsm.targetHeard = nil
        brain.fsm.lastKnownEnemyPosition = nil
        changed = true
    end

    if brain.ai then
        if brain.ai.senses then
            local senses = brain.ai.senses
            if bf_threatMatchesPlayer(senses.currentThreat, playerId) then
                senses.currentThreat = nil
                changed = true
            end
            if bf_threatMatchesPlayer(senses.lastThreat, playerId) then
                senses.lastThreat = nil
                senses.lastKnownEnemyPosition = nil
                changed = true
            end
        end

        if bf_threatMatchesPlayer(brain.ai.lastThreat, playerId) then
            brain.ai.lastThreat = nil
            brain.ai.lastThreatAt = nil
            brain.ai.inHumanBattle = false
            changed = true
        end
    end

    if changed then
        brain.factionTargetInvalidatedAt = bf_nowHours()
        if brain.fsm then
            brain.fsm.reason = "player faction changed"
        end
        if not brain.ai or not brain.ai.lastThreat then
            brain.inBattle = false
            brain.virtualBattle = false
        end
    end

    return changed
end

function NPCFactionBridge.ForgetPlayerAsThreat(player)
    if not player then return 0 end
    local playerId = bf_playerId(player)
    if playerId == nil then return 0 end

    local cleared = 0
    local cache = NPCZombieCacheBridge and NPCZombieCacheBridge.Cache or nil
    if type(cache) ~= "table" then return 0 end

    for _, bandit in pairs(cache) do
        local brain = bandit and NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(bandit) or nil
        if brain and NPCFactionBridge.CanBrainAttackPlayer and not NPCFactionBridge.CanBrainAttackPlayer(brain, player) then
            if bf_clearBrainPlayerThreat(brain, playerId) then
                cleared = cleared + 1
            end
            if brain.tasks and #brain.tasks > 0 then
                local shouldClearTasks = false
                for _, task in ipairs(brain.tasks) do
                    if task and (task.action == "Shoot" or task.action == "Aim" or task.action == "Hit" or task.action == "Shove") then
                        local taskKind = task.targetKind or (task.eid and "player" or nil)
                        if taskKind == "player" and bf_sameId(task.targetId or task.eid, playerId) then
                            shouldClearTasks = true
                            break
                        end
                    end
                end
                if shouldClearTasks and NPCEntity and NPCEntity.ClearTasks then
                    pcall(function() NPCEntity.ClearTasks(bandit) end)
                    cleared = cleared + 1
                end
            end
        end
    end

    return cleared
end

function NPCFactionBridge.ApplyPlayerFactionPayload(args)
    if type(args) ~= "table" then return end
    local id = args.id
    if id == nil then return end

    local side = NPCFactionBridge.NormalizeSide(args.factionSide or args.side) or NPCFactionBridge.DefaultPlayerSide()
    local gmd = GetNPCModDataPlayers and GetNPCModDataPlayers() or nil
    if gmd then
        gmd.OnlinePlayers = gmd.OnlinePlayers or {}
        local rec = gmd.OnlinePlayers[id] or gmd.OnlinePlayers[tostring(id)] or {}
        rec.id = id
        rec.name = args.name or rec.name
        rec.factionSide = side
        rec.factionExpiresAt = tonumber(args.factionExpiresAt)
        rec.factionReason = args.factionReason or args.reason
        rec.factionUpdatedAt = tonumber(args.factionUpdatedAt) or bf_nowHours()
        gmd.OnlinePlayers[id] = rec
        gmd.OnlinePlayers[tostring(id)] = rec
    end

    local player = nil
    if NPCPlayerClient and NPCPlayerClient.GetPlayerById then
        player = NPCPlayerClient.GetPlayerById(id)
    end
    if player and NPCRuntimeCacheBridge and NPCRuntimeCacheBridge.SetPlayerFactionRecord then
        NPCRuntimeCacheBridge.SetPlayerFactionRecord(player, {
            side = side,
            expiresAt = tonumber(args.factionExpiresAt),
            reason = args.factionReason or args.reason,
            updatedAt = tonumber(args.factionUpdatedAt) or bf_nowHours()
        })
    end
    if player then
        NPCFactionBridge.ForgetPlayerAsThreat(player)
    end
end

function NPCFactionBridge.GetPlayerRecord(player)
    local defaultSide = NPCFactionBridge.DefaultPlayerSide()
    if not player then return {side=defaultSide} end

    if NPCRuntimeCacheBridge and NPCRuntimeCacheBridge.GetPlayerFactionRecord then
        local cached = NPCRuntimeCacheBridge.GetPlayerFactionRecord(player)
        if cached and cached.side then return cached end
    end

    local id = bf_playerId(player)
    local gmd = GetNPCModDataPlayers and GetNPCModDataPlayers() or nil
    local online = nil
    if gmd and gmd.OnlinePlayers and id ~= nil then
        online = gmd.OnlinePlayers[id] or gmd.OnlinePlayers[tostring(id)] or gmd.OnlinePlayers[tonumber(id)]
    end
    local rec = nil

    local md = player.getModData and player:getModData() or nil
    if md and type(md.NPCFactionBridge) == "table" then
        rec = {
            side = NPCFactionBridge.NormalizeSide(md.NPCFactionBridge.side) or defaultSide,
            expiresAt = tonumber(md.NPCFactionBridge.expiresAt),
            reason = md.NPCFactionBridge.reason,
            updatedAt = tonumber(md.NPCFactionBridge.updatedAt)
        }
    end

    if not rec and online and online.factionSide then
        rec = {
            side = NPCFactionBridge.NormalizeSide(online.factionSide) or defaultSide,
            expiresAt = tonumber(online.factionExpiresAt),
            reason = online.factionReason,
            updatedAt = tonumber(online.factionUpdatedAt)
        }
    end

    rec = rec or {side=defaultSide}
    if rec.side == NPCFactionBridge.SIDE_BLACK and rec.expiresAt and bf_nowHours() >= rec.expiresAt then
        rec.side = NPCFactionBridge.SIDE_BLUE
        rec.expiresAt = nil
        rec.reason = "black_timer_expired"
        rec.updatedAt = bf_nowHours()
        local localPlayer = getPlayer and getPlayer() or nil
        if player == localPlayer then
            NPCFactionBridge.SetPlayerSide(player, rec.side, rec.reason, nil, true)
        end
    end
    if NPCRuntimeCacheBridge and NPCRuntimeCacheBridge.SetPlayerFactionRecord then
        NPCRuntimeCacheBridge.SetPlayerFactionRecord(player, rec)
    end
    return rec
end

function NPCFactionBridge.GetPlayerSide(player)
    local rec = NPCFactionBridge.GetPlayerRecord(player)
    return NPCFactionBridge.NormalizeSide(rec and rec.side) or NPCFactionBridge.DefaultPlayerSide()
end

function NPCFactionBridge.BuildPlayerPayload(player)
    local rec = NPCFactionBridge.GetPlayerRecord(player)
    return {
        factionSide = rec.side,
        factionExpiresAt = rec.expiresAt,
        factionReason = rec.reason,
        factionUpdatedAt = rec.updatedAt
    }
end

function NPCFactionBridge.SetPlayerSide(player, side, reason, durationHours, silent)
    if not player then return nil end
    side = NPCFactionBridge.NormalizeSide(side) or NPCFactionBridge.DefaultPlayerSide()

    local now = bf_nowHours()
    local expiresAt = nil
    if side == NPCFactionBridge.SIDE_BLACK then
        expiresAt = now + (tonumber(durationHours) or NPCFactionBridge.BlackDurationHours())
    end

    local rec = {
        side = side,
        expiresAt = expiresAt,
        reason = reason or "manual",
        updatedAt = now
    }

    local md = player.getModData and player:getModData() or nil
    if md then md.NPCFactionBridge = rec end

    if NPCRuntimeCacheBridge and NPCRuntimeCacheBridge.SetPlayerFactionRecord then
        NPCRuntimeCacheBridge.SetPlayerFactionRecord(player, rec)
    end

    if NPCFactionBridge.ForgetPlayerAsThreat then
        NPCFactionBridge.ForgetPlayerAsThreat(player)
    end

    if isClient and isClient() and sendClientCommand then
        sendClientCommand(player, 'NPCPlayers', 'SetFaction', {
            id = bf_playerId(player),
            name = bf_playerName(player),
            factionSide = rec.side,
            factionExpiresAt = rec.expiresAt,
            factionReason = rec.reason,
            factionUpdatedAt = rec.updatedAt
        })
    end

    if not silent and player.Say then
        local label = NPCFactionBridge.GetSideLabel(side)
        pcall(function() player:Say("Faction: " .. label) end)
    end

    return rec
end

function NPCFactionBridge.GetSideLabel(side)
    side = NPCFactionBridge.NormalizeSide(side) or NPCFactionBridge.SIDE_BLUE
    if side == NPCFactionBridge.SIDE_RED then return "Red" end
    if side == NPCFactionBridge.SIDE_GREEN then return "Green" end
    if side == NPCFactionBridge.SIDE_BLACK then return "Black / Rogue" end
    return "Blue / Neutral"
end

function NPCFactionBridge.GetBrainSide(brain)
    if not brain then return nil end
    if NPCFactionBridge.IsServiceBrain and NPCFactionBridge.IsServiceBrain(brain) then return NPCFactionBridge.SIDE_BLUE end

    local side = NPCFactionBridge.NormalizeSide(brain.factionSide or brain.faction or brain.side)
    if side then return side end

    side = NPCFactionBridge.NormalizeSide(brain.patrolColor)
    if side then return side end

    if brain.clan == 0 then return NPCFactionBridge.SIDE_BLUE end
    if brain.hostile == false then return NPCFactionBridge.SIDE_GREEN end
    if brain.hostile == true then return NPCFactionBridge.SIDE_RED end
    return NPCFactionBridge.SIDE_RED
end

function NPCFactionBridge.SetBrainSide(brain, side, reason)
    if not brain then return nil end
    if NPCFactionBridge.IsServiceBrain and NPCFactionBridge.IsServiceBrain(brain) then
        brain.factionSide = "black_market_service"
        brain.faction = "black_market_service"
        brain.side = "black_market_service"
        brain.factionReason = reason or brain.factionReason or "service"
        brain.factionState = "service"
        brain.hostile = false
        brain.factionShoot = false
        return NPCFactionBridge.SIDE_BLUE
    end
    side = NPCFactionBridge.NormalizeSide(side) or NPCFactionBridge.SIDE_RED

    brain.factionSide = side
    brain.faction = side
    brain.side = side
    brain.factionReason = reason or brain.factionReason
    brain.factionUpdatedAt = bf_nowHours()

    if side == NPCFactionBridge.SIDE_RED then
        brain.hostile = true
        brain.patrolColor = "red"
    elseif side == NPCFactionBridge.SIDE_GREEN then
        brain.hostile = false
        brain.patrolColor = "green"
    elseif side == NPCFactionBridge.SIDE_BLUE then
        brain.hostile = false
        brain.patrolColor = "blue"
        if brain.program and (brain.program.name == "Raider" or brain.program.name == NPCLegacyContractBridge.Program("RAIDER")) then
            brain.program = {name="Looter", stage="Prepare"}
        end
        if NPCMercenaryContract and NPCMercenaryContract.ApplyEliteToBrain then
            NPCMercenaryContract.ApplyEliteToBrain(brain)
        end
    elseif side == NPCFactionBridge.SIDE_BLACK then
        brain.hostile = true
        brain.patrolColor = "black"
        brain.program = {name="Raider", stage="Prepare"}
    end

    return side
end

function NPCFactionBridge.EnsureBrainSide(brain)
    if not brain then return nil end
    local side = NPCFactionBridge.GetBrainSide(brain)
    if not brain.factionSide then
        NPCFactionBridge.SetBrainSide(brain, side, "initial")
    end
    return side
end

function NPCFactionBridge.IsEnemySide(observerSide, targetSide)
    observerSide = NPCFactionBridge.NormalizeSide(observerSide) or NPCFactionBridge.SIDE_RED
    targetSide = NPCFactionBridge.NormalizeSide(targetSide) or NPCFactionBridge.SIDE_BLUE

    local enemyMask = NPCFactionBridge.ENEMY_MASK[observerSide] or 0
    local targetMask = NPCFactionBridge.GetSideMask(targetSide)
    return NPCFactionBridge.MaskHas(enemyMask, targetMask)
end

function NPCFactionBridge.AreBrainsEnemies(brain, targetBrain)
    if not targetBrain then return true end
    if NPCFactionBridge.IsServiceBrain and (NPCFactionBridge.IsServiceBrain(brain) or NPCFactionBridge.IsServiceBrain(targetBrain)) then return false end
    if brain and targetBrain and brain.id and targetBrain.id and tostring(brain.id) == tostring(targetBrain.id) then return false end

    local observerSide = NPCFactionBridge.GetBrainSide(brain)
    local targetSide = NPCFactionBridge.GetBrainSide(targetBrain)
    return NPCFactionBridge.IsEnemySide(observerSide, targetSide)
end

function NPCFactionBridge.IsGoodMoodHoldFire(brain)
    if not brain then return false end
    if not bf_settingBool("Faction_RedGoodMoodHoldFire", true) then return false end
    if NPCFactionBridge.GetBrainSide(brain) ~= NPCFactionBridge.SIDE_RED then return false end

    local profile = brain.ai and brain.ai.profile or nil
    local morale = tonumber(profile and profile.morale or brain.morale) or 0
    local fear = tonumber(profile and profile.fear or brain.fear) or 0
    local moraleMin = bf_settingNumber("Faction_GoodMoodMoraleThreshold", 0.86, 0, 1)
    local fearMax = bf_settingNumber("Faction_GoodMoodFearMax", 0.22, 0, 1)

    return morale >= moraleMin and fear <= fearMax
end

function NPCFactionBridge.CanBrainAttackPlayer(brain, player)
    if NPCSpyBridge and NPCSpyBridge.ShouldHoldFireAgainstPlayer and NPCSpyBridge.ShouldHoldFireAgainstPlayer(brain, player) then return false end
    if not NPCFactionBridge.IsEnabled() then return brain and brain.hostile == true end
    if not brain or not player then return false end
    if NPCFactionBridge.IsGoodMoodHoldFire(brain) then return false end

    if NPCWorldRules and NPCWorldRules.CanBrainAttackPlayer then
        local ok, result = pcall(function() return NPCWorldRules.CanBrainAttackPlayer(brain, player) end)
        if ok and result ~= nil then return result == true end
    end

    local observerSide = NPCFactionBridge.GetBrainSide(brain)
    local targetSide = NPCFactionBridge.GetPlayerSide(player)
    if NPCDisguiseBridge and NPCDisguiseBridge.GetPlayerPerceivedSide then
        local perceivedSide = NPCDisguiseBridge.GetPlayerPerceivedSide(player, brain)
        if perceivedSide then targetSide = perceivedSide end
    end
    if NPCBountyBridge and NPCBountyBridge.ShouldFactionHuntPlayer and NPCBountyBridge.ShouldFactionHuntPlayer(observerSide, player, brain) then
        return true
    end
    return NPCFactionBridge.IsEnemySide(observerSide, targetSide)
end

function NPCFactionBridge.UpdateNPCState(bandit, brain)
    if not NPCFactionBridge.IsEnabled() or not brain then return nil end

    local side = NPCFactionBridge.EnsureBrainSide(brain)
    local now = bf_nowHours()
    local profile = brain.ai and brain.ai.profile or nil
    local fear = tonumber(profile and profile.fear or brain.fear) or 0
    local morale = tonumber(profile and profile.morale or brain.morale) or 0

    if side == NPCFactionBridge.SIDE_GREEN and bf_settingBool("Faction_NPCPanicRogueEnabled", true) then
        local fearMin = bf_settingNumber("Faction_NPCPanicFearThreshold", 0.92, 0, 1)
        local moraleMax = bf_settingNumber("Faction_NPCPanicMoraleMax", 0.22, 0, 1)
        if fear >= fearMin and morale <= moraleMax then
            if now >= (tonumber(brain.factionNextPanicCheckAt) or 0) then
                brain.factionNextPanicCheckAt = now + (1 / 60)
                local chance = bf_settingNumber("Faction_NPCPanicRogueChancePerMinute", 35, 0, 100)
                local roll = ZombRand and ZombRand(10000) or math.random(0, 9999)
                if chance >= 100 or roll < math.floor(chance * 100) then
                    side = NPCFactionBridge.SetBrainSide(brain, NPCFactionBridge.SIDE_BLACK, "panic_desertion")
                    brain.factionState = "deserted_black"
                    brain.factionShoot = true
                    return brain.factionState
                end
            end
            brain.factionState = "panic"
            brain.factionShoot = true
            return brain.factionState
        end
    end

    if side == NPCFactionBridge.SIDE_RED and NPCFactionBridge.IsGoodMoodHoldFire(brain) then
        local neutralMinutes = bf_settingNumber("Faction_GoodMoodNeutralMinutes", 20, 1, 1440)
        brain.factionGoodMoodSince = brain.factionGoodMoodSince or now
        if now - brain.factionGoodMoodSince >= neutralMinutes / 60 then
            side = NPCFactionBridge.SetBrainSide(brain, NPCFactionBridge.SIDE_BLUE, "good_mood_neutral")
            brain.factionState = brain.mercenary and "blue_mercenary" or "neutral_blue"
            brain.factionShoot = false
            return brain.factionState
        end
        brain.factionState = "hold_fire_good_mood"
        brain.factionShoot = false
        return brain.factionState
    else
        brain.factionGoodMoodSince = nil
    end

    if side == NPCFactionBridge.SIDE_BLUE then
        if NPCMercenaryContract and NPCMercenaryContract.ApplyEliteToBrain then
            NPCMercenaryContract.ApplyEliteToBrain(brain)
        end
        brain.factionState = brain.mercenary and "blue_mercenary" or "neutral_blue"
        brain.factionShoot = false
    elseif side == NPCFactionBridge.SIDE_BLACK then
        brain.factionState = "rogue_black"
        brain.factionShoot = true
    else
        brain.factionState = "shoot"
        brain.factionShoot = true
    end

    return brain.factionState
end

function NPCFactionBridge.OnPlayerHitNPC(player, victimBrain, killed)
    if not NPCFactionBridge.IsEnabled() then return end
    if not player or not victimBrain or (instanceof and not instanceof(player, "IsoPlayer")) then return end
    if player.isNPC and player:isNPC() then return end

    if NPCDisguiseBridge and NPCDisguiseBridge.Compromise then
        pcall(function() NPCDisguiseBridge.Compromise(player, "hostile_action", NPCFactionBridge.GetBrainSide(victimBrain), true) end)
    end

    local playerSide = NPCFactionBridge.GetPlayerSide(player)
    local victimSide = NPCFactionBridge.GetBrainSide(victimBrain)

    if sendClientCommand and victimSide then
        pcall(function()
            sendClientCommand(player, 'NPCBounty', 'ReportHostileAction', {
                victimSide = victimSide,
                killed = killed == true,
                victimId = victimBrain.id or victimBrain.uid,
                victimGroupId = victimBrain.groupId or victimBrain.worldGroupId
            })
        end)
        if killed == true and victimBrain and (victimBrain.leader == true or victimBrain.isFactionLeader == true or victimBrain.leaderId) then
            pcall(function()
                sendClientCommand(player, 'NPCLeaders', 'ReportLeaderKilled', {
                    victimSide = victimSide,
                    leaderId = victimBrain.leaderId,
                    leaderName = victimBrain.leaderName,
                    leaderRole = victimBrain.leaderRole,
                    victimId = victimBrain.id or victimBrain.uid,
                    groupId = victimBrain.groupId or victimBrain.worldGroupId,
                    baseId = victimBrain.baseId or victimBrain.homeBaseId,
                    x = player.getX and player:getX() or nil,
                    y = player.getY and player:getY() or nil
                })
            end)
        end
    end

    if not NPCFactionBridge.IsPlayerAutoSideEnabled() then return end

    if playerSide == victimSide then
        if killed then
            NPCFactionBridge.SetPlayerSide(player, NPCFactionBridge.SIDE_BLACK, "killed_own_faction", NPCFactionBridge.BlackDurationHours())
        end
        return
    end

    if playerSide == NPCFactionBridge.SIDE_BLACK then return end

    if victimSide == NPCFactionBridge.SIDE_RED then
        NPCFactionBridge.SetPlayerSide(player, NPCFactionBridge.SIDE_GREEN, "attacked_red", nil, true)
    elseif victimSide == NPCFactionBridge.SIDE_GREEN then
        NPCFactionBridge.SetPlayerSide(player, NPCFactionBridge.SIDE_RED, "attacked_green", nil, true)
    end
end

NPCFactionBridge[NPCLegacyContractBridge.Member("onPlayerHit")] = function(player, victimBrain, killed)
    return NPCFactionBridge.OnPlayerHitNPC(player, victimBrain, killed)
end

function NPCFactionBridge.UpdateLocalPlayerTimer(player)
    player = player or (getPlayer and getPlayer() or nil)
    if not player then return end
    local rec = NPCFactionBridge.GetPlayerRecord(player)
    if rec and rec.side == NPCFactionBridge.SIDE_BLACK and rec.expiresAt and bf_nowHours() >= rec.expiresAt then
        NPCFactionBridge.SetPlayerSide(player, NPCFactionBridge.SIDE_BLUE, "black_timer_expired", nil, true)
    end
end

local function bf_onServerCommand(module, command, args)
    if not NPCLegacyContractBridge.IsModule(module, "NPCFaction", "faction") then return end
    if command == "PlayerFactionChanged" then
        NPCFactionBridge.ApplyPlayerFactionPayload(args)
    elseif command == "ForgetPlayerThreat" then
        NPCFactionBridge.ApplyPlayerFactionPayload(args)
    end
end

if Events and Events.OnServerCommand and not NPCFactionBridge._serverCommandHooked then
    NPCFactionBridge._serverCommandHooked = true
    Events.OnServerCommand.Add(bf_onServerCommand)
end

