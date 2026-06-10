-- NPCLivingWorldIntentBridge.lua
-- Lightweight observable world-intent layer for materialized NPCs.
-- It adds small post-combat / scavenging / base-life tasks without changing
-- task APIs, save contracts, networking, or combat ownership.

require "NPCBehavior/NPCIntentArbiterBridge"
require "NPCCore/NPCLootTargetCacheBridge"

NPCLivingWorldIntentBridge = NPCLivingWorldIntentBridge or {}

NPCLivingWorldIntentBridge.VERSION = "2026-05-27-living-world-intent-7-emergency-stabilizer"

NPCLivingWorldIntentBridge.Config = NPCLivingWorldIntentBridge.Config or {
    emergencyStabilizationMode = true,
    allowAutonomousLivingMovement = false,
    allowAutonomousLootNeeds = false,
    allowAutonomousBaseLifeMovement = false,
    allowAutonomousSquadCohesionMovement = false,
    allowDangerMemoryMovement = false,
    postCombatWindowMs = 12000,
    decisionCooldownMs = 3600,
    ambientCooldownMs = 6400,
    lootScanCooldownMs = 19000,
    lootScanRadius = 5,
    needAssessCooldownMs = 14000,
    needLootScanCooldownMs = 26000,
    needLootRadius = 6,
    needLootMaxItems = 5,
    needContainerScanItemLimit = 85,
    lowAmmoCount = 2,
    lowMedicalCount = 1,
    lowFoodCount = 1,
    lowWaterCount = 1,
    baseAmbientCooldownMs = 8200,
    baseDailyLifeCooldownMs = 9800,
    baseWorkCooldownMs = 22000,
    basePatrolCooldownMs = 24000,
    baseSocialCooldownMs = 26000,
    baseRecordScanLimit = 28,
    baseWorkRadius = 34,
    basePatrolMargin = 2.5,
    survivalNeedLimit = 0.78,
    restNeedLimit = 0.84,
    squadSupportCooldownMs = 5200,
    squadCohesionCooldownMs = 9500,
    squadSupportRadius = 13,
    squadCohesionRadius = 15,
    squadLeaderDistance = 8.5,
    squadCentroidDistance = 10.5,
    woundedRescueDistance = 1.65,
    woundedGuardDistance = 4.25,
    dangerMemoryCooldownMs = 6200,
    dangerMemoryTtlMs = 72000,
    dangerMemoryMax = 8,
    dangerAwareCooldownMs = 18000,
    dangerTraceCooldownMs = 26000,
    dangerWatchRadius = 15.0,
    dangerCloseRadius = 5.75,
    dangerInfluenceRadius = 34,
    dangerInfluenceValue = 0.65,
    combatGraceMs = 5200,
    livingStressSuppressMs = 18000,
    livingMoveLoopWindowMs = 22000,
    livingMoveLoopMax = 2,
    livingMoveRepeatMs = 24000,
    livingMoveRepeatRadius = 1.35,
    livingPathStressLevel = 2
}

local function lwi_nowMs()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then return math.floor(getGameTime():getWorldAgeHours() * 3600000) end
    return 0
end

local function lwi_nowHours()
    if getGameTime then return getGameTime():getWorldAgeHours() or 0 end
    return 0
end

local function lwi_emergencyStabilization()
    return NPCLivingWorldIntentBridge.Config and NPCLivingWorldIntentBridge.Config.emergencyStabilizationMode == true
end

local function lwi_allowAutonomousMove(kind)
    if not lwi_emergencyStabilization() then return true end
    kind = tostring(kind or ""):lower()
    if kind == "squad_rescue" or kind == "rescue" then return true end
    return false
end

local function lwi_rand(max)
    max = tonumber(max) or 1
    if max <= 0 then return 0 end
    if ZombRand then return ZombRand(max) end
    return math.floor(lwi_nowMs() % max)
end

local function lwi_dist(x1, y1, x2, y2)
    if not x1 or not y1 or not x2 or not y2 then return 99999 end
    local dx = x1 - x2
    local dy = y1 - y2
    return math.sqrt(dx * dx + dy * dy)
end

local function lwi_clamp(value, minValue, maxValue)
    value = tonumber(value) or 0
    if minValue ~= nil and value < minValue then return minValue end
    if maxValue ~= nil and value > maxValue then return maxValue end
    return value
end

local function lwi_quantDangerKey(x, y, z)
    if not x or not y then return nil end
    local qx = math.floor((tonumber(x) or 0) / 4)
    local qy = math.floor((tonumber(y) or 0) / 4)
    local qz = math.floor(tonumber(z) or 0)
    return tostring(qx) .. ":" .. tostring(qy) .. ":" .. tostring(qz)
end

local function lwi_pruneDangerMemory(living, now)
    if not living or type(living.dangerMemory) ~= "table" then return end
    now = now or lwi_nowMs()
    local ttl = tonumber(NPCLivingWorldIntentBridge.Config.dangerMemoryTtlMs) or 72000
    local maxCount = tonumber(NPCLivingWorldIntentBridge.Config.dangerMemoryMax) or 8
    local kept = {}

    for _, entry in pairs(living.dangerMemory) do
        if entry and entry.x and entry.y and (not entry.seenAtMs or now - entry.seenAtMs <= ttl) then
            kept[#kept + 1] = entry
        end
    end

    table.sort(kept, function(a, b)
        return tonumber(a.seenAtMs or 0) > tonumber(b.seenAtMs or 0)
    end)

    while #kept > maxCount do
        kept[#kept] = nil
    end

    living.dangerMemory = kept
end

local function lwi_rememberDanger(chr, brain, x, y, z, kind, weight, reason)
    if not brain or not x or not y then return false end
    local living = NPCLivingWorldIntentBridge.GetLiving(brain, chr)
    if not living then return false end

    local now = lwi_nowMs()
    local key = lwi_quantDangerKey(x, y, z)
    if not key then return false end
    living.dangerMemory = living.dangerMemory or {}
    living.dangerCooldowns = living.dangerCooldowns or {}

    local cooldown = tonumber(NPCLivingWorldIntentBridge.Config.dangerMemoryCooldownMs) or 6200
    if living.dangerCooldowns[key] and now < living.dangerCooldowns[key] then return false end
    living.dangerCooldowns[key] = now + cooldown

    local entry = nil
    for _, old in pairs(living.dangerMemory) do
        if old and old.key == key then
            entry = old
            break
        end
    end

    if not entry then
        entry = {key = key}
        living.dangerMemory[#living.dangerMemory + 1] = entry
    end

    entry.x = tonumber(x)
    entry.y = tonumber(y)
    entry.z = tonumber(z) or 0
    entry.kind = kind or entry.kind or "threat"
    entry.weight = lwi_clamp((tonumber(entry.weight) or 0.35) + (tonumber(weight) or 0.35), 0.2, 1.6)
    entry.reason = reason or entry.reason or "recent contact"
    entry.seenAtMs = now
    entry.expiresAtMs = now + (tonumber(NPCLivingWorldIntentBridge.Config.dangerMemoryTtlMs) or 72000)

    living.lastDangerX = entry.x
    living.lastDangerY = entry.y
    living.lastDangerZ = entry.z
    living.lastDangerKind = entry.kind
    living.lastDangerAtMs = now
    living.worldTraceCount = (tonumber(living.worldTraceCount) or 0) + 1

    if brain.ai then
        brain.ai.lastDangerX = entry.x
        brain.ai.lastDangerY = entry.y
        brain.ai.lastDangerZ = entry.z
        brain.ai.lastDangerKind = entry.kind
        brain.ai.lastDangerAtMs = now
    end

    if NPCInfluenceFieldBridge and NPCInfluenceFieldBridge.InjectThreat then
        pcall(function()
            NPCInfluenceFieldBridge.InjectThreat(entry.x, entry.y, tonumber(NPCLivingWorldIntentBridge.Config.dangerInfluenceValue) or 0.65, tonumber(NPCLivingWorldIntentBridge.Config.dangerInfluenceRadius) or 34)
        end)
    end

    lwi_pruneDangerMemory(living, now)
    return true
end

local function lwi_nearestRememberedDanger(chr, living, now, radius)
    if not (chr and chr.getX and chr.getY and living and type(living.dangerMemory) == "table") then return nil end
    now = now or lwi_nowMs()
    lwi_pruneDangerMemory(living, now)

    local x = chr:getX()
    local y = chr:getY()
    radius = tonumber(radius) or NPCLivingWorldIntentBridge.Config.dangerWatchRadius or 15
    local best = nil

    for _, entry in pairs(living.dangerMemory) do
        if entry and entry.x and entry.y then
            local dist = lwi_dist(x, y, entry.x, entry.y)
            if dist <= radius then
                local age = math.max(0, now - (tonumber(entry.seenAtMs) or now))
                local freshness = 1.0 - math.min(0.85, age / (tonumber(NPCLivingWorldIntentBridge.Config.dangerMemoryTtlMs) or 72000))
                local score = (tonumber(entry.weight) or 0.5) * freshness + math.max(0, radius - dist) / math.max(1, radius)
                if not best or score > best.score then
                    best = {
                        x = entry.x,
                        y = entry.y,
                        z = entry.z,
                        kind = entry.kind,
                        dist = dist,
                        ageMs = age,
                        score = score,
                        reason = entry.reason
                    }
                end
            end
        end
    end

    return best
end

local function lwi_brain(chr)
    if not chr or not NPCBrainData or not NPCBrainData.Get then return nil end
    local ok, brain = pcall(function() return NPCBrainData.Get(chr) end)
    if ok then return brain end
    return nil
end

local function lwi_charId(chr, brain)
    local id = brain and (brain.id or brain.uid or brain.persistentId or brain.worldMemberId) or nil
    if id ~= nil then return tonumber(id) or tostring(id) end
    if chr and NPCUtils and NPCUtils.GetCharacterID then
        local ok, got = pcall(function() return NPCUtils.GetCharacterID(chr) end)
        if ok and got ~= nil then return tonumber(got) or tostring(got) end
    end
    return tostring(chr or "npc")
end

local function lwi_seedNumber(chr, brain)
    local id = lwi_charId(chr, brain)
    if type(id) == "number" then return math.abs(id) end
    id = tostring(id or "npc")
    local n = 0
    for i = 1, #id do
        n = (n * 33 + string.byte(id, i)) % 9973
    end
    return n
end

local function lwi_programName(brain)
    if brain and brain.program and brain.program.name then return tostring(brain.program.name) end
    return tostring(brain and (brain.programName or brain.role or "") or "")
end

local function lwi_orderName(brain)
    if not brain then return nil end
    local order = brain.order or brain.directorOrder
    if type(order) == "table" then order = order.name or order.action or order.type or order.mode end
    if not order then return nil end
    order = tostring(order):lower()
    if order == "" then return nil end
    return order
end

local function lwi_hasExplicitOrder(brain)
    local order = lwi_orderName(brain)
    if not order or order == "free" or order == "freeroam" or order == "free_roam" then return false end
    return true
end

local function lwi_hasPlayerMaster(brain)
    return brain and (brain.master ~= nil or brain.mercenaryHired == true or brain.hired == true)
end

local function lwi_isCombatAction(action)
    return action == "Shoot" or action == "Aim" or action == "Hit" or action == "Shove" or action == "Reload"
end

local function lwi_getAction(chr)
    if not chr or not NPCEntity or not NPCEntity.GetTask then return nil end
    local ok, task = pcall(function() return NPCEntity.GetTask(chr) end)
    if ok and task then return task.action end
    return nil
end

local function lwi_getTask(chr)
    if not chr or not NPCEntity or not NPCEntity.GetTask then return nil end
    local ok, task = pcall(function() return NPCEntity.GetTask(chr) end)
    if ok then return task end
    return nil
end

local function lwi_loadLevel()
    if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.GetLoadState then
        local ok, state = pcall(function() return NPCWorkSchedulerBridge.GetLoadState(false) end)
        if ok and state then return tonumber(state.level) or 0 end
    end
    return 0
end

local function lwi_underPathStress()
    return lwi_loadLevel() >= (tonumber(NPCLivingWorldIntentBridge.Config.livingPathStressLevel) or 2)
end

local function lwi_livingSuppressed(living, now)
    if not living then return true end
    now = now or lwi_nowMs()
    if living.suppressLivingUntilMs and now < living.suppressLivingUntilMs then return true end
    return false
end

local function lwi_suppressLiving(living, now, ms, reason)
    if not living then return end
    now = now or lwi_nowMs()
    living.suppressLivingUntilMs = now + (tonumber(ms) or tonumber(NPCLivingWorldIntentBridge.Config.livingStressSuppressMs) or 18000)
    living.suppressLivingReason = reason or "living intent suppressed"
    living.intentState = nil
    living.intentReason = nil
    living.supplyNeed = nil
end

local function lwi_intentOwner(kind)
    kind = tostring(kind or "living_ambient"):lower()
    if kind == "squad" or kind == "squad rescue" or kind == "squad_rescue" or kind == "wounded" then return "squad_rescue" end
    if kind == "squad cohesion" or kind == "squad_cohesion" then return "squad_cohesion" end
    if kind == "base" or kind == "base patrol" or kind == "base_life" then return "base_life" end
    if kind == "supply" or kind == "supply_need" or kind == "loot" or kind == "inspect" then return "supply_need" end
    if kind == "danger" or kind == "danger_memory" then return "danger_memory" end
    if kind == "postcombat" or kind == "post_combat" then return "post_combat" end
    if kind == "state" or kind == "living_state" then return "living_state" end
    if kind == "move" or kind == "living_move" then return "living_move" end
    return "living_ambient"
end

local function lwi_intentPriority(owner)
    if NPCIntentArbiterBridge and NPCIntentArbiterBridge.Config and NPCIntentArbiterBridge.Config.priorities then
        return tonumber(NPCIntentArbiterBridge.Config.priorities[owner])
    end
    return nil
end

local function lwi_requestIntent(chr, brain, kind, reason, ttlMs, cooldownMs)
    if not (NPCIntentArbiterBridge and NPCIntentArbiterBridge.Request) then return true end
    if not brain then return false end
    local owner = lwi_intentOwner(kind)
    return NPCIntentArbiterBridge.Request(chr, brain, owner, reason or owner, {
        priority = lwi_intentPriority(owner),
        ttlMs = ttlMs,
        cooldownMs = cooldownMs
    }) == true
end

local function lwi_checkIntent(chr, brain, kind, reason, ttlMs)
    if not (NPCIntentArbiterBridge and NPCIntentArbiterBridge.Check) then return true end
    if not brain then return false end
    local owner = lwi_intentOwner(kind)
    return NPCIntentArbiterBridge.Check(chr, brain, owner, reason or owner, {
        priority = lwi_intentPriority(owner),
        ttlMs = ttlMs
    }) == true
end

local function lwi_markIntentTasks(tasks, kind, reason)
    if NPCIntentArbiterBridge and NPCIntentArbiterBridge.MarkTasks then
        return NPCIntentArbiterBridge.MarkTasks(tasks, lwi_intentOwner(kind), reason)
    end
    return tasks
end

local function lwi_taskLooksLikeCombat(action)
    if lwi_isCombatAction(action) then return true end
    action = tostring(action or ""):lower()
    return action == "targetspotted" or action == "target_spotted" or action == "targetsighted" or action == "target_sighted" or action == "combat" or action == "keepdistance" or action == "meleefallback"
end

local function lwi_stateLooksCombat(value)
    value = tostring(value or ""):lower()
    return value == "attack" or value == "combat" or value == "keepdistance" or value == "reloadcover" or value == "meleefallback" or value == "emergencydefense" or value == "searchenemy" or value == "recoverpath"
end

local function lwi_hasCombatContext(chr, brain, currentAction)
    if not brain then return false end
    if lwi_taskLooksLikeCombat(currentAction or lwi_getAction(chr)) then return true end
    if brain.currentThreat or brain.radioThreat or brain.enemy or brain.target then return true end
    if brain.fsm and (brain.fsm.currentThreat or brain.fsm.enemy or brain.fsm.target or lwi_stateLooksCombat(brain.fsm.state) or lwi_stateLooksCombat(brain.fsm.mode)) then return true end
    if lwi_stateLooksCombat(brain.state) or lwi_stateLooksCombat(brain.mode) or lwi_stateLooksCombat(brain.directorState) then return true end
    local living = brain.ai and brain.ai.living
    local now = lwi_nowMs()
    if living and living.lastCombatMs and now - living.lastCombatMs < (tonumber(NPCLivingWorldIntentBridge.Config.combatGraceMs) or 5200) then return true end
    return false
end

local function lwi_squareRoom(square)
    if not (square and square.getRoom) then return nil end
    local ok, room = pcall(function() return square:getRoom() end)
    if ok then return room end
    return nil
end

local function lwi_squareBuilding(square)
    if not (square and square.getBuilding) then return nil end
    local ok, building = pcall(function() return square:getBuilding() end)
    if ok then return building end
    return nil
end

local function lwi_squareContextAllowed(chr, square)
    if not (chr and square) then return false end
    local from = chr.getSquare and chr:getSquare() or nil
    if not from then return true end
    local fromRoom = lwi_squareRoom(from)
    local toRoom = lwi_squareRoom(square)
    if fromRoom ~= toRoom then
        return false
    end
    local fromBuilding = lwi_squareBuilding(from)
    local toBuilding = lwi_squareBuilding(square)
    if fromBuilding ~= toBuilding then
        return false
    end
    if NPCMovementStabilityBridge and NPCMovementStabilityBridge.IsSquareBlocked then
        local ok, blocked = pcall(function() return NPCMovementStabilityBridge.IsSquareBlocked(square, chr) end)
        if ok and blocked == true then return false end
    end
    return true
end

local function lwi_moveHistoryCount(history, now, window)
    local count = 0
    local kept = {}
    for _, entry in pairs(history or {}) do
        if entry and entry.t and now - entry.t <= window then
            kept[#kept + 1] = entry
            count = count + 1
        end
    end
    return count, kept
end

local function lwi_registerLivingMove(chr, task, kind)
    if not (chr and task and task.x and task.y) then return true end
    if not lwi_allowAutonomousMove(kind) then return false end
    local brain = lwi_brain(chr)
    local living = brain and NPCLivingWorldIntentBridge.GetLiving(brain, chr) or nil
    if not living then return true end
    local now = lwi_nowMs()
    if lwi_livingSuppressed(living, now) then return false end
    if not lwi_requestIntent(chr, brain, kind or "living_move", task.directorReason or "living move", 9000) then return false end

    local repeatMs = tonumber(NPCLivingWorldIntentBridge.Config.livingMoveRepeatMs) or 24000
    local repeatRadius = tonumber(NPCLivingWorldIntentBridge.Config.livingMoveRepeatRadius) or 1.35
    if living.lastLivingMoveX and living.lastLivingMoveY and living.lastLivingMoveAtMs and now - living.lastLivingMoveAtMs < repeatMs then
        if lwi_dist(living.lastLivingMoveX, living.lastLivingMoveY, task.x, task.y) <= repeatRadius then
            lwi_suppressLiving(living, now, math.floor((tonumber(NPCLivingWorldIntentBridge.Config.livingStressSuppressMs) or 18000) * 0.75), "repeat move target")
            return false
        end
    end

    local window = tonumber(NPCLivingWorldIntentBridge.Config.livingMoveLoopWindowMs) or 22000
    local maxMoves = tonumber(NPCLivingWorldIntentBridge.Config.livingMoveLoopMax) or 2
    local count, kept = lwi_moveHistoryCount(living.livingMoveHistory, now, window)
    living.livingMoveHistory = kept
    if count >= maxMoves then
        lwi_suppressLiving(living, now, tonumber(NPCLivingWorldIntentBridge.Config.livingStressSuppressMs) or 18000, "living move loop guard")
        return false
    end

    living.livingMoveHistory[#living.livingMoveHistory + 1] = {x = tonumber(task.x), y = tonumber(task.y), z = tonumber(task.z), t = now, kind = kind or task.directorReason}
    living.lastLivingMoveX = tonumber(task.x)
    living.lastLivingMoveY = tonumber(task.y)
    living.lastLivingMoveZ = tonumber(task.z)
    living.lastLivingMoveAtMs = now
    task.livingMoveIntent = true
    task.arriveDist = math.max(tonumber(task.arriveDist) or 0.9, 0.95)
    return true
end

local function lwi_needValue(brain, key)
    if not brain then return 0 end
    local needs = brain.needs
    if type(needs) ~= "table" and type(brain.ai) == "table" then needs = brain.ai.needs end
    if type(needs) ~= "table" then return 0 end
    return tonumber(needs[key] or 0) or 0
end

function NPCLivingWorldIntentBridge.EnsurePersonality(brain, chr)
    if not brain then return nil end
    brain.ai = brain.ai or {}
    brain.ai.living = brain.ai.living or {}
    local living = brain.ai.living
    if living.personality then return living.personality end

    local seed = lwi_seedNumber(chr, brain)
    local archetypes = {"disciplined", "cautious", "greedy", "aggressive", "medic", "wanderer"}
    living.personality = archetypes[(seed % #archetypes) + 1]
    living.seed = seed
    living.createdAt = lwi_nowHours()
    return living.personality
end

function NPCLivingWorldIntentBridge.GetLiving(brain, chr)
    if not brain then return nil end
    NPCLivingWorldIntentBridge.EnsurePersonality(brain, chr)
    brain.ai = brain.ai or {}
    brain.ai.living = brain.ai.living or {}
    return brain.ai.living
end

function NPCLivingWorldIntentBridge.RememberDanger(chr, brain, x, y, z, kind, weight, reason)
    return lwi_rememberDanger(chr, brain, x, y, z, kind, weight, reason)
end

function NPCLivingWorldIntentBridge.GetNearestRememberedDanger(chr, brain, radius)
    local living = brain and brain.ai and brain.ai.living
    return lwi_nearestRememberedDanger(chr, living, lwi_nowMs(), radius)
end

function NPCLivingWorldIntentBridge.UpdateCombatMemory(chr, brain, threat, currentAction)
    if not brain then return end
    local living = NPCLivingWorldIntentBridge.GetLiving(brain, chr)
    if not living then return end

    local now = lwi_nowMs()
    if threat and threat.x and threat.y then
        living.lastCombatMs = now
        living.postCombatUntilMs = now + (NPCLivingWorldIntentBridge.Config.postCombatWindowMs or 18000)
        living.lastCombatX = tonumber(threat.x)
        living.lastCombatY = tonumber(threat.y)
        living.lastCombatZ = tonumber(threat.z) or (chr and chr.getZ and chr:getZ()) or 0
        living.lastCombatKind = threat.kind
        living.postCombatDone = nil
        lwi_rememberDanger(chr, brain, living.lastCombatX, living.lastCombatY, living.lastCombatZ, threat.kind or "combat", 0.55, "living intent: remembered contact")
        return
    end

    if lwi_isCombatAction(currentAction) then
        living.lastCombatMs = now
        living.postCombatUntilMs = now + (NPCLivingWorldIntentBridge.Config.postCombatWindowMs or 18000)
        if chr and chr.getX then
            living.lastCombatX = living.lastCombatX or chr:getX()
            living.lastCombatY = living.lastCombatY or chr:getY()
            living.lastCombatZ = living.lastCombatZ or chr:getZ()
        end
        living.postCombatDone = nil
    end
end

function NPCLivingWorldIntentBridge.HasRecentCombat(brain, now)
    local living = brain and brain.ai and brain.ai.living
    if not living then return false end
    now = now or lwi_nowMs()
    return living.postCombatUntilMs ~= nil and now <= living.postCombatUntilMs
end

local function lwi_canDecide(living, key, now, cooldown)
    if not living then return false end
    key = key or "decision"
    now = now or lwi_nowMs()
    cooldown = tonumber(cooldown) or NPCLivingWorldIntentBridge.Config.decisionCooldownMs or 2400
    local nextKey = "next_" .. key .. "_ms"
    if living[nextKey] and now < living[nextKey] then return false end
    living[nextKey] = now + cooldown
    return true
end

local function lwi_setIntent(living, state, reason, now, ttlMs)
    if not living or not state then return nil end
    now = now or lwi_nowMs()
    living.intentState = state
    living.intentReason = reason
    living.intentUntilMs = now + (tonumber(ttlMs) or 6500)
    return state, reason
end

local function lwi_pickWorldState(director, brain, personality, programName, now)
    if not director or not director.States then return nil end
    local states = director.States
    local program = tostring(programName or lwi_programName(brain))

    if program == "Looter" or personality == "greedy" then
        return states.LootArea, "living intent: scavenge nearby supplies"
    end
    if program == "Raider" or program == "Thief" or personality == "aggressive" then
        return states.PatrolArea, "living intent: sweep the block"
    end
    if personality == "medic" then
        return states.GuardArea, "living intent: watch for wounded allies"
    end
    if personality == "cautious" then
        return states.SearchEnemy, "living intent: check suspicious area"
    end
    if personality == "wanderer" then
        return states.PatrolArea, "living intent: roam with purpose"
    end

    if (math.floor((now or lwi_nowMs()) / 1000) + (brain and tonumber(brain.id or 0) or 0)) % 3 == 0 then
        return states.PatrolArea, "living intent: patrol nearby"
    end
    return nil
end

local lwi_assessSupplyNeeds

function NPCLivingWorldIntentBridge.SuggestState(director, runtime, chr, brain, threat, health, order, programName)
    if not (director and director.States and chr and brain) then return nil end
    if threat then return nil end

    local currentAction = runtime and runtime.currentAction and runtime.currentAction(chr) or lwi_getAction(chr)
    if lwi_isCombatAction(currentAction) or lwi_hasCombatContext(chr, brain, currentAction) then return nil end

    local living = NPCLivingWorldIntentBridge.GetLiving(brain, chr)
    if not living then return nil end
    if lwi_emergencyStabilization() then return nil end
    local now = lwi_nowMs()
    if lwi_livingSuppressed(living, now) or lwi_underPathStress() then return nil end
    local personality = NPCLivingWorldIntentBridge.EnsurePersonality(brain, chr)
    local explicitOrder = lwi_hasExplicitOrder(brain)
    local playerOwned = lwi_hasPlayerMaster(brain)

    if not explicitOrder and not playerOwned then
        if not lwi_checkIntent(chr, brain, "living_state", "living state suggestion", 5600) then return nil end
    end

    if living.intentState and living.intentUntilMs and now <= living.intentUntilMs and not explicitOrder then
        return living.intentState, living.intentReason or "living intent"
    end

    if not lwi_canDecide(living, "state", now, NPCLivingWorldIntentBridge.Config.decisionCooldownMs) then
        return nil
    end
    if not explicitOrder and not playerOwned then
        if not lwi_requestIntent(chr, brain, "living_state", "living state suggestion", 6200) then return nil end
    end

    if NPCLivingWorldIntentBridge.HasRecentCombat(brain, now) then
        if tonumber(health or 1) < 0.86 and director.States.HealSelf then
            return lwi_setIntent(living, director.States.HealSelf, "living intent: patch up after fight", now, 7000)
        end
        if runtime and runtime.hasReloadableFirearm and runtime.hasReloadableFirearm(brain) and director.States.ReloadWeapon then
            return lwi_setIntent(living, director.States.ReloadWeapon, "living intent: reload after fight", now, 6500)
        end
        if not explicitOrder and not playerOwned and (personality == "greedy" or lwi_programName(brain) == "Looter" or lwi_programName(brain) == "Raider") and director.States.LootArea then
            return lwi_setIntent(living, director.States.LootArea, "living intent: loot after fight", now, 7000)
        end
        return nil
    end

    if explicitOrder or playerOwned then return nil end

    local supplyNeed = lwi_assessSupplyNeeds(chr, brain, living, personality, programName)
    if supplyNeed and supplyNeed.need and director.States.LootArea then
        return lwi_setIntent(living, director.States.LootArea, supplyNeed.reason or "living economy: search supplies", now, 9000)
    end

    local food = math.max(lwi_needValue(brain, "food"), lwi_needValue(brain, "hunger"))
    local water = math.max(lwi_needValue(brain, "water"), lwi_needValue(brain, "thirst"))
    local rest = math.max(lwi_needValue(brain, "rest"), lwi_needValue(brain, "fatigue"))
    if (food >= (NPCLivingWorldIntentBridge.Config.survivalNeedLimit or 0.78) or water >= (NPCLivingWorldIntentBridge.Config.survivalNeedLimit or 0.78)) and director.States.EatDrink then
        return lwi_setIntent(living, director.States.EatDrink, "living intent: eat and drink", now, 9000)
    end
    if rest >= (NPCLivingWorldIntentBridge.Config.restNeedLimit or 0.84) and director.States.SleepRest then
        return lwi_setIntent(living, director.States.SleepRest, "living intent: rest", now, 9000)
    end

    if lwi_programName(brain) == "BaseGuard" or brain.homeBaseZoneType or brain.baseZoneType then
        return nil
    end

    local state, reason = lwi_pickWorldState(director, brain, personality, programName, now)
    if state then return lwi_setIntent(living, state, reason, now, 8000) end
    return nil
end

local function lwi_timeTask(anim, time, reason)
    return {action = "Time", anim = anim or "ShiftWeight", time = time or 100, livingIntent = true, directorReason = reason or "living intent"}
end

local function lwi_faceTask(x, y, reason, time)
    if not x or not y then return nil end
    return {action = "FaceLocation", anim = "Idle", x = x, y = y, time = time or 80, livingIntent = true, directorReason = reason or "living intent"}
end

local function lwi_itemText(item)
    if not item then return "" end
    local parts = {}
    if item.getFullType then
        local ok, value = pcall(function() return item:getFullType() end)
        if ok and value then parts[#parts + 1] = value end
    end
    if item.getType then
        local ok, value = pcall(function() return item:getType() end)
        if ok and value then parts[#parts + 1] = value end
    end
    if item.getDisplayName then
        local ok, value = pcall(function() return item:getDisplayName() end)
        if ok and value then parts[#parts + 1] = value end
    end
    return tostring(table.concat(parts, " ")):lower()
end

local function lwi_callBool(item, name)
    if not (item and name and item[name]) then return false end
    local ok, value = pcall(function() return item[name](item) end)
    return ok and value == true
end

local function lwi_textHasAny(text, words)
    if not text then return false end
    for _, word in ipairs(words or {}) do
        if word and word ~= "" and string.find(text, word, 1, true) then return true end
    end
    return false
end

local function lwi_itemMatchesNeed(item, need)
    if not item then return false end
    need = tostring(need or "any"):lower()
    if need == "" or need == "any" or need == "all" then return true end

    local text = lwi_itemText(item)
    local isFood = lwi_callBool(item, "IsFood") or lwi_callBool(item, "isFood")
    local isWeapon = lwi_callBool(item, "IsWeapon") or lwi_callBool(item, "isWeapon")

    if need == "ammo" then
        return lwi_textHasAny(text, {"ammo", "bullet", "bullets", "round", "rounds", "shell", "shells", "cartridge", "magazine", "clip", "boxof", "box of"})
    elseif need == "medical" or need == "meds" or need == "medicine" then
        return lwi_textHasAny(text, {"bandage", "alcohol", "disinfect", "antibiotic", "painkiller", "suture", "splint", "firstaid", "first aid", "medkit", "tweezers", "cotton", "pills"})
    elseif need == "food" then
        return isFood or lwi_textHasAny(text, {"canned", "food", "bread", "chips", "meat", "fish", "soup", "beans", "cereal", "chocolate", "fruit", "vegetable", "mre"})
    elseif need == "water" or need == "drink" then
        return lwi_textHasAny(text, {"water", "bottle", "canteen", "pop", "soda", "juice", "milk", "drink", "beverage", "mug", "teacup"})
    elseif need == "weapon" then
        return isWeapon or lwi_textHasAny(text, {"pistol", "revolver", "shotgun", "rifle", "gun", "knife", "axe", "bat", "machete", "spear", "katana", "hammer", "crowbar", "club", "blade"})
    elseif need == "gear" or need == "armor" then
        return lwi_textHasAny(text, {"vest", "helmet", "armor", "armour", "bag", "backpack", "satchel", "belt", "holster", "mask", "gloves", "boots"})
    elseif need == "smokes" then
        return lwi_textHasAny(text, {"cigarette", "lighter", "matches", "tobacco"})
    elseif need == "valuables" then
        return lwi_textHasAny(text, {"money", "gold", "silver", "diamond", "ring", "necklace", "bracelet", "watch", "jewellery", "jewelry", "creditcard", "wallet"})
    elseif need == "supply" or need == "supplies" or need == "survival" then
        return lwi_itemMatchesNeed(item, "ammo") or lwi_itemMatchesNeed(item, "medical") or lwi_itemMatchesNeed(item, "food") or lwi_itemMatchesNeed(item, "water") or lwi_itemMatchesNeed(item, "weapon") or lwi_itemMatchesNeed(item, "gear")
    end

    return true
end

local function lwi_itemNeedScore(item, need)
    if not lwi_itemMatchesNeed(item, need) then return 0 end
    need = tostring(need or "any"):lower()
    local text = lwi_itemText(item)
    if need == "ammo" and lwi_textHasAny(text, {"box", "magazine", "clip"}) then return 1.35 end
    if need == "medical" and lwi_textHasAny(text, {"bandage", "firstaid", "medkit"}) then return 1.35 end
    if need == "weapon" and lwi_textHasAny(text, {"rifle", "shotgun", "pistol", "revolver"}) then return 1.3 end
    if need == "water" and lwi_textHasAny(text, {"water", "canteen"}) then return 1.25 end
    return 1.0
end

local function lwi_findContainerSquare(chr, radius, need)
    if not (chr and chr.getX and getCell) then return nil end
    if lwi_underPathStress() then return nil end
    local brain = lwi_brain(chr)
    radius = math.min(tonumber(radius) or NPCLivingWorldIntentBridge.Config.lootScanRadius or 5, NPCLivingWorldIntentBridge.Config.lootScanRadius or 5)

    if NPCLootTargetCacheBridge and NPCLootTargetCacheBridge.FindContainerSquare then
        local ok, square = pcall(function()
            return NPCLootTargetCacheBridge.FindContainerSquare(chr, radius, {
                brain = brain,
                need = need or "any",
                ttlMs = 5400,
                maxSquareChecks = 120,
                maxObjectChecks = 14,
                maxItemChecks = tonumber(NPCLivingWorldIntentBridge.Config.needContainerScanItemLimit) or 85,
                squareFilter = function(candidateChr, candidateSquare)
                    return lwi_squareContextAllowed(candidateChr, candidateSquare)
                end
            })
        end)
        if ok and square then return square end
    end

    local cell = getCell()
    if not cell then return nil end
    local bx = math.floor(chr:getX())
    local by = math.floor(chr:getY())
    local bz = math.floor(chr:getZ())
    local wantNeed = need ~= nil and tostring(need) ~= "" and tostring(need) ~= "any"
    local bestSquare = nil
    local bestScore = 0
    local inspectedItems = 0
    local itemLimit = tonumber(NPCLivingWorldIntentBridge.Config.needContainerScanItemLimit) or 85

    for r = 0, radius do
        for dx = -r, r do
            for dy = -r, r do
                if r == 0 or math.abs(dx) == r or math.abs(dy) == r then
                    local square = cell:getGridSquare(bx + dx, by + dy, bz)
                    if square and lwi_squareContextAllowed(chr, square) and not (brain and NPCMovementStabilityBridge and NPCMovementStabilityBridge.IsBadTarget and NPCMovementStabilityBridge.IsBadTarget(brain, square:getX(), square:getY(), square:getZ())) then
                        local objects = square:getObjects()
                        if objects then
                            for i = 0, math.min(objects:size() - 1, 13) do
                                local obj = objects:get(i)
                                local container = obj and obj.getContainer and obj:getContainer() or nil
                                if container and (not container.isEmpty or not container:isEmpty()) then
                                    if not wantNeed then return square end
                                    local items = nil
                                    if container.getItems then
                                        local ok, got = pcall(function() return container:getItems() end)
                                        if ok then items = got end
                                    end
                                    if items then
                                        local squareScore = 0
                                        for j = 0, items:size() - 1 do
                                            inspectedItems = inspectedItems + 1
                                            squareScore = squareScore + lwi_itemNeedScore(items:get(j), need)
                                            if inspectedItems >= itemLimit then break end
                                        end
                                        if squareScore > 0 then
                                            local distPenalty = math.max(0, r) * 0.05
                                            local score = squareScore - distPenalty
                                            if score > bestScore then
                                                bestScore = score
                                                bestSquare = square
                                            end
                                        end
                                    end
                                end
                                if inspectedItems >= itemLimit then break end
                            end
                        end
                    end
                end
                if inspectedItems >= itemLimit then break end
            end
            if inspectedItems >= itemLimit then break end
        end
        if bestSquare and r >= 2 then return bestSquare end
        if inspectedItems >= itemLimit then break end
    end
    return bestSquare
end

local function lwi_moveToSquareTask(chr, square, walkType, endurance)
    if not (chr and square and NPCUtils and NPCUtils.GetMoveTask) then return nil end
    local sx = square:getX()
    local sy = square:getY()
    local sz = square:getZ()
    local dist = NPCUtils.DistTo and NPCUtils.DistTo(chr:getX(), chr:getY(), sx + 0.5, sy + 0.5) or 9999
    local task = NPCUtils.GetMoveTask(endurance or 0, sx, sy, sz, walkType or "Walk", dist, false)
    if task then
        task.livingIntent = true
        task.directorReason = "living intent: move to inspect"
        if not lwi_registerLivingMove(chr, task, "inspect") then return nil end
    end
    return task
end

local function lwi_lootTask(square, reason, need, maxItems)
    if not square then return nil end
    return {
        action = "LootItems",
        anim = "Loot",
        time = 100,
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
        livingIntent = true,
        lootNeed = need,
        lootMaxItems = maxItems,
        directorReason = reason or "living intent: inspect supplies"
    }
end


local function lwi_getInventoryItems(chr)
    local inv = chr and chr.getInventory and chr:getInventory() or nil
    if not inv then return nil end
    local ok, items = pcall(function() return inv:getItems() end)
    if ok then return items end
    return nil
end

local function lwi_primaryItem(chr)
    if not (chr and chr.getPrimaryHandItem) then return nil end
    local ok, item = pcall(function() return chr:getPrimaryHandItem() end)
    if ok then return item end
    return nil
end

local function lwi_isRangedItem(item)
    if not item then return false end
    if lwi_callBool(item, "isAimedFirearm") or lwi_callBool(item, "IsAimedFirearm") then return true end
    local text = lwi_itemText(item)
    return lwi_textHasAny(text, {"pistol", "revolver", "shotgun", "rifle", "firearm", "gun"})
end

lwi_assessSupplyNeeds = function(chr, brain, living, personality, program)
    if not (chr and brain) then return nil end
    local now = lwi_nowMs()
    living = living or NPCLivingWorldIntentBridge.GetLiving(brain, chr)
    if not living then return nil end

    local cooldown = tonumber(NPCLivingWorldIntentBridge.Config.needAssessCooldownMs) or 7200
    if living.supplyNeed and living.supplyNeedUntilMs and now < living.supplyNeedUntilMs then
        return living.supplyNeed
    end
    if living.next_supply_assess_ms and now < living.next_supply_assess_ms then
        return nil
    end
    living.next_supply_assess_ms = now + cooldown

    local counts = {ammo = 0, medical = 0, food = 0, water = 0, weapon = 0, gear = 0, smokes = 0, valuables = 0}
    local items = lwi_getInventoryItems(chr)
    if items then
        local max = math.min(items:size() - 1, 80)
        for i = 0, max do
            local item = items:get(i)
            for key, _ in pairs(counts) do
                if lwi_itemMatchesNeed(item, key) then counts[key] = counts[key] + 1 end
            end
        end
    end

    local health = nil
    if chr and chr.getHealth then
        local ok, got = pcall(function() return tonumber(chr:getHealth()) end)
        if ok then health = got end
    end
    if health == nil then health = tonumber(brain.health or (brain.fsm and brain.fsm.health)) end
    health = tonumber(health) or 1
    if health > 1 and health <= 5 then health = health / 5 end
    if health > 1 then health = 1 end
    if health < 0 then health = 0 end
    local primary = lwi_primaryItem(chr)
    local hasRanged = lwi_isRangedItem(primary)
    local foodNeed = math.max(lwi_needValue(brain, "food"), lwi_needValue(brain, "hunger"))
    local waterNeed = math.max(lwi_needValue(brain, "water"), lwi_needValue(brain, "thirst"))
    local programName = tostring(program or lwi_programName(brain) or "")

    local need = nil
    local reason = nil
    local urgency = 0

    if hasRanged and counts.ammo <= (tonumber(NPCLivingWorldIntentBridge.Config.lowAmmoCount) or 2) then
        need, reason, urgency = "ammo", "living economy: search for ammunition", 0.85
    end
    if health < 0.72 and counts.medical <= (tonumber(NPCLivingWorldIntentBridge.Config.lowMedicalCount) or 1) and urgency < 0.95 then
        need, reason, urgency = "medical", "living economy: search for medical supplies", 0.95
    end
    if foodNeed >= 0.72 and counts.food <= (tonumber(NPCLivingWorldIntentBridge.Config.lowFoodCount) or 1) and urgency < 0.75 then
        need, reason, urgency = "food", "living economy: search for food", 0.75
    end
    if waterNeed >= 0.70 and counts.water <= (tonumber(NPCLivingWorldIntentBridge.Config.lowWaterCount) or 1) and urgency < 0.78 then
        need, reason, urgency = "water", "living economy: search for water", 0.78
    end
    if not primary and counts.weapon <= 0 and urgency < 0.82 then
        need, reason, urgency = "weapon", "living economy: search for a weapon", 0.82
    end
    if (programName == "Looter" or programName == "Raider" or personality == "greedy") and not need then
        if counts.ammo <= 3 then
            need, reason, urgency = "ammo", "living economy: stock up ammunition", 0.45
        elseif counts.medical <= 1 then
            need, reason, urgency = "medical", "living economy: stock up medicine", 0.42
        elseif counts.food <= 1 then
            need, reason, urgency = "food", "living economy: stock up food", 0.4
        elseif counts.gear <= 0 and lwi_rand(4) == 0 then
            need, reason, urgency = "gear", "living economy: look for useful gear", 0.35
        elseif lwi_rand(5) == 0 then
            need, reason, urgency = "valuables", "living economy: look for valuables", 0.3
        end
    end

    if not need then
        living.supplyNeed = nil
        living.lastSupplyCounts = counts
        return nil
    end

    living.supplyNeed = {
        need = need,
        reason = reason,
        urgency = urgency,
        counts = counts,
        assessedAtMs = now
    }
    living.supplyNeedUntilMs = now + math.max(8000, cooldown * 2)
    living.lastSupplyCounts = counts
    return living.supplyNeed
end

local function lwi_planSupplyNeedTasks(chr, brain, living, personality, program, profile, options)
    if not (chr and brain and chr.getX) then return nil end
    if NPCLivingWorldIntentBridge.Config and NPCLivingWorldIntentBridge.Config.allowAutonomousLootNeeds == false then return nil end
    options = options or {}
    living = living or NPCLivingWorldIntentBridge.GetLiving(brain, chr)
    if not living then return nil end
    local now = lwi_nowMs()
    if lwi_livingSuppressed(living, now) or lwi_underPathStress() or lwi_hasCombatContext(chr, brain) then return nil end
    local cooldown = tonumber(options.cooldownMs) or tonumber(NPCLivingWorldIntentBridge.Config.needLootScanCooldownMs) or 26000
    if not lwi_canDecide(living, options.key or "supply_need_loot", now, cooldown) then return nil end

    local supply = lwi_assessSupplyNeeds(chr, brain, living, personality, program)
    if not (supply and supply.need) then return nil end

    local radius = tonumber(options.radius) or tonumber(NPCLivingWorldIntentBridge.Config.needLootRadius) or 8
    local square = lwi_findContainerSquare(chr, radius, supply.need)
    if not square then
        living.lastSupplyNeedMiss = supply.need
        living.lastSupplyNeedMissAtMs = now
        return nil
    end

    local tasks = {}
    local dist = lwi_dist(chr:getX(), chr:getY(), square:getX() + 0.5, square:getY() + 0.5)
    if dist > 1.85 then
        local move = lwi_moveToSquareTask(chr, square, profile and profile.walkType or "Walk", profile and profile.endurance or 0)
        if move then
            move.supplyNeed = supply.need
            move.directorReason = supply.reason or "living economy: move to supplies"
            tasks[#tasks + 1] = move
        end
    else
        local loot = lwi_lootTask(square, supply.reason or "living economy: take needed supplies", supply.need, tonumber(options.maxItems) or tonumber(NPCLivingWorldIntentBridge.Config.needLootMaxItems) or 5)
        if loot then
            loot.supplyNeed = supply.need
            tasks[#tasks + 1] = loot
        end
    end

    if #tasks > 0 then
        living.lastSupplyNeed = supply.need
        living.lastSupplyNeedReason = supply.reason
        living.lastSupplyNeedAtMs = now
        return tasks
    end
    return nil
end

local function lwi_normKey(value)
    if value == nil then return nil end
    value = tostring(value)
    if value == "" or value == "nil" or value == "false" then return nil end
    return value
end

local function lwi_groupKey(brain)
    if not brain then return nil end
    return lwi_normKey(brain.worldGroupId)
        or lwi_normKey(brain.groupId)
        or lwi_normKey(brain.physicalGroupId)
        or lwi_normKey(brain.squadId)
end

local function lwi_sideKey(brain)
    if not brain then return nil end
    return lwi_normKey(brain.clan)
        or lwi_normKey(brain.patrolColor)
        or lwi_normKey(brain.factionSide)
        or lwi_normKey(brain.side)
        or lwi_normKey(brain.faction)
end

local function lwi_isSpecialNonCombatBrain(brain)
    return brain and (brain.blackMarket == true or brain.blackMarketNPC == true or brain.trader == true or brain.noSquadSupport == true)
end

local function lwi_areEnemies(a, b)
    if not (a and b) then return false end
    if NPCFactionBridge and NPCFactionBridge.IsEnabled and NPCFactionBridge.AreBrainsEnemies then
        local ok, enemies = pcall(function() return NPCFactionBridge.AreBrainsEnemies(a, b) end)
        if ok and enemies == true then return true end
    end
    if a.battleEnemyGroupId and b.worldGroupId and tostring(a.battleEnemyGroupId) == tostring(b.worldGroupId) then return true end
    if b.battleEnemyGroupId and a.worldGroupId and tostring(b.battleEnemyGroupId) == tostring(a.worldGroupId) then return true end
    if a.roadPatrol and b.roadPatrol and a.patrolColor and b.patrolColor and tostring(a.patrolColor) ~= tostring(b.patrolColor) then return true end
    if a.clan and b.clan and tostring(a.clan) ~= tostring(b.clan) and (a.hostile == true or b.hostile == true) then return true end
    return false
end

local function lwi_areAllies(a, b)
    if not (a and b) then return false end
    if lwi_isSpecialNonCombatBrain(a) or lwi_isSpecialNonCombatBrain(b) then return false end
    if lwi_areEnemies(a, b) then return false end

    local ag = lwi_groupKey(a)
    local bg = lwi_groupKey(b)
    if ag and bg and ag == bg then return true end

    local as = lwi_sideKey(a)
    local bs = lwi_sideKey(b)
    if as and bs and as == bs then return true end

    if a.mercenaryHired == true and b.mercenaryHired == true then
        local am = a.master or a.mercenaryHiredBy
        local bm = b.master or b.mercenaryHiredBy
        if am and bm and tostring(am) == tostring(bm) then return true end
    end

    return false
end

local function lwi_resolveCachedCharacter(data)
    if not data then return nil end
    if data.character then return data.character end
    local id = data.id
    if NPCZombieCacheBridge and NPCZombieCacheBridge.Cache then
        return NPCZombieCacheBridge.Cache[id]
            or NPCZombieCacheBridge.Cache[tostring(id)]
            or NPCZombieCacheBridge.Cache[tonumber(id)]
    end
    return nil
end

local function lwi_isCharacterAlive(chr)
    if not chr then return false end
    if chr.isDead then
        local ok, dead = pcall(function() return chr:isDead() end)
        if ok and dead == true then return false end
    end
    if chr.getHealth then
        local ok, health = pcall(function() return tonumber(chr:getHealth()) end)
        if ok and health and health <= 0.01 then return false end
    end
    return true
end

local function lwi_health01(chr, brain)
    local h = nil
    if chr and chr.getHealth then
        local ok, got = pcall(function() return tonumber(chr:getHealth()) end)
        if ok then h = got end
    end
    if h == nil and brain then h = tonumber(brain.health or (brain.fsm and brain.fsm.health)) end
    h = tonumber(h) or 1
    if h > 1 and h <= 5 then h = h / 5 end
    if h > 1 then h = 1 end
    if h < 0 then h = 0 end
    return h
end

local function lwi_isWoundedBrain(brain)
    if not brain then return false end
    if NPCWounded and NPCWounded.IsDowned then
        local ok, downed = pcall(function() return NPCWounded.IsDowned(brain) end)
        if ok and downed == true then return true, true end
    end
    if brain.wounded == true or brain.woundedDowned == true or brain.woundedState == "downed" or brain.woundedState == "evacuating" then
        return true, brain.woundedDowned == true or brain.woundedState == "downed"
    end
    return false, false
end

local function lwi_isLeaderBrain(brain)
    if not brain then return false end
    if brain.leader == true or brain.isFactionLeader == true or brain.commandAura == true then return true end
    local role = tostring(brain.role or brain.tacticalRole or ""):lower()
    return role == "leader" or role == "base_commander" or role == "commander" or role == "officer"
end

local function lwi_moveToPointTask(chr, x, y, z, walkType, endurance, closeDistance, reason)
    if not (chr and x and y and NPCUtils and NPCUtils.GetMoveTask) then return nil end
    local dist = lwi_dist(chr:getX(), chr:getY(), x, y)
    local task = NPCUtils.GetMoveTask(endurance or 0, x, y, z or chr:getZ(), walkType or "Walk", closeDistance or dist, false)
    if task then
        task.livingIntent = true
        task.squadSupport = true
        task.directorReason = reason or "squad support"
        if not lwi_registerLivingMove(chr, task, "squad") then return nil end
    end
    return task
end

local function lwi_faceAllyTask(ally, reason, time)
    if not (ally and ally.x and ally.y) then return nil end
    local task = lwi_faceTask(ally.x, ally.y, reason or "squad support", time or 55)
    if task then task.squadSupport = true end
    return task
end

local function lwi_nearbySquadSummary(chr, brain, radius)
    local out = {
        allies = {},
        count = 0,
        sumX = 0,
        sumY = 0,
        leader = nil,
        wounded = nil,
        nearest = nil
    }
    if not (chr and brain and chr.getX and chr.getY) then return out end

    local x = chr:getX()
    local y = chr:getY()
    local z = chr:getZ()
    radius = tonumber(radius) or NPCLivingWorldIntentBridge.Config.squadSupportRadius or 13
    local nearby = nil
    if NPCSpatialIndexBridge and NPCSpatialIndexBridge.GetNearbyNPCs then
        nearby = NPCSpatialIndexBridge.GetNearbyNPCs(x, y, z, radius)
    elseif NPCZombieCacheBridge and NPCZombieCacheBridge.CacheLightB then
        nearby = NPCZombieCacheBridge.CacheLightB
    end
    if not nearby then return out end

    local selfId = lwi_charId(chr, brain)
    for _, data in pairs(nearby) do
        local dataId = data and (data.id or data.uid) or nil
        if data and tostring(dataId or "") ~= tostring(selfId or "") then
            local allyBrain = data.brain
            local allyChr = lwi_resolveCachedCharacter(data)
            if allyChr and not allyBrain and NPCBrainData and NPCBrainData.Get then
                local ok, got = pcall(function() return NPCBrainData.Get(allyChr) end)
                if ok then allyBrain = got end
            end
            if allyBrain and allyChr and lwi_isCharacterAlive(allyChr) and lwi_areAllies(brain, allyBrain) then
                local ax = tonumber(data.x) or (allyChr.getX and allyChr:getX())
                local ay = tonumber(data.y) or (allyChr.getY and allyChr:getY())
                local az = tonumber(data.z) or (allyChr.getZ and allyChr:getZ()) or z
                local dist = lwi_dist(x, y, ax, ay)
                local ally = {id=dataId, x=ax, y=ay, z=az, dist=dist, brain=allyBrain, chr=allyChr, health=lwi_health01(allyChr, allyBrain)}
                local wounded, downed = lwi_isWoundedBrain(allyBrain)
                ally.wounded = wounded
                ally.downed = downed
                out.count = out.count + 1
                out.sumX = out.sumX + ax
                out.sumY = out.sumY + ay
                out.allies[#out.allies + 1] = ally
                if not out.nearest or dist < out.nearest.dist then out.nearest = ally end
                if lwi_isLeaderBrain(allyBrain) and (not out.leader or dist < out.leader.dist) then out.leader = ally end
                if wounded or downed or ally.health < 0.42 then
                    local priority = (downed and 1000 or 0) + math.floor((1 - ally.health) * 100) - math.floor(dist * 2)
                    if not out.wounded or priority > out.wounded.priority then
                        ally.priority = priority
                        out.wounded = ally
                    end
                end
            end
        end
    end

    if out.count > 0 then
        out.centerX = out.sumX / out.count
        out.centerY = out.sumY / out.count
        out.centerZ = z
    end
    return out
end

local function lwi_shouldRescue(personality, program, wounded)
    if not wounded then return false end
    if wounded.downed == true then return true end
    if personality == "medic" or personality == "disciplined" or personality == "cautious" then return true end
    program = tostring(program or "")
    return program == "BaseGuard" or program == "CompanionGuard" or program == "Raider" or program == "Looter"
end

local function lwi_tryStabilizeAlly(helperBrain, ally)
    if not (ally and ally.brain) then return false end
    if not (ally.downed == true or ally.brain.woundedDowned == true or ally.brain.woundedState == "downed") then return false end
    local now = lwi_nowMs()
    ally.brain.ai = ally.brain.ai or {}
    ally.brain.ai.living = ally.brain.ai.living or {}
    if ally.brain.ai.living.lastSquadStabilizedAt and now - ally.brain.ai.living.lastSquadStabilizedAt < 12000 then return false end

    local changed = false
    if NPCWounded and NPCWounded.MarkStabilized then
        local ok, done = pcall(function() return NPCWounded.MarkStabilized(ally.brain, nil, "stabilized by squadmate") end)
        changed = ok and done == true
    else
        ally.brain.woundedDowned = false
        ally.brain.woundedStabilized = true
        ally.brain.woundedState = "stabilized"
        changed = true
    end

    ally.brain.ai.living.lastSquadStabilizedAt = now
    ally.brain.ai.living.lastSquadHelperId = helperBrain and (helperBrain.persistentId or helperBrain.id or helperBrain.uid) or nil
    if ally.chr and NPCWounded and NPCWounded.ApplyLocalState then pcall(function() NPCWounded.ApplyLocalState(ally.chr, ally.brain) end) end
    if ally.chr and NPCBrainData and NPCBrainData.Update then pcall(function() NPCBrainData.Update(ally.chr, ally.brain) end) end
    return changed
end

function NPCLivingWorldIntentBridge.PlanSquadSupportTasks(director, runtime, chr, brain, state, reason, threat, options)
    if not (chr and brain) then return nil end
    if threat then return nil end
    if lwi_isSpecialNonCombatBrain(brain) then return nil end
    if lwi_emergencyStabilization() then return nil end

    local living = NPCLivingWorldIntentBridge.GetLiving(brain, chr)
    if not living then return nil end
    local now = lwi_nowMs()
    local personality = NPCLivingWorldIntentBridge.EnsurePersonality(brain, chr)
    local program = tostring(options and options.program or lwi_programName(brain) or "")
    local profile = options and options.profile or nil
    local explicitOrder = lwi_hasExplicitOrder(brain)
    local playerOwned = lwi_hasPlayerMaster(brain)

    local summary = nil
    local supportRadius = tonumber(options and options.radius) or NPCLivingWorldIntentBridge.Config.squadSupportRadius or 13

    if lwi_canDecide(living, "squad_support", now, NPCLivingWorldIntentBridge.Config.squadSupportCooldownMs) then
        summary = lwi_nearbySquadSummary(chr, brain, supportRadius)
        local wounded = summary.wounded
        if wounded and lwi_shouldRescue(personality, program, wounded) and not (brain.wounded == true or brain.woundedDowned == true) then
            local tasks = {}
            local rescueDist = NPCLivingWorldIntentBridge.Config.woundedRescueDistance or 1.65
            local guardDist = NPCLivingWorldIntentBridge.Config.woundedGuardDistance or 4.25
            if wounded.dist > rescueDist then
                local move = lwi_moveToPointTask(chr, wounded.x, wounded.y, wounded.z, profile and profile.walkType or "Walk", profile and profile.endurance or 0, wounded.dist, "squad support: move to wounded ally")
                if move then tasks[#tasks + 1] = move end
                if wounded.dist <= guardDist then
                    local face = lwi_faceAllyTask(wounded, "squad support: keep eyes on wounded ally", 45)
                    if face then tasks[#tasks + 1] = face end
                end
                if #tasks > 0 then
                    if not lwi_requestIntent(chr, brain, "squad_rescue", "squad support: moving to wounded ally", 9000) then return nil end
                    living.intentState = state
                    living.intentReason = "squad support: moving to wounded ally"
                    living.lastSquadSupportAt = now
                    return lwi_markIntentTasks(tasks, "squad_rescue", "squad support: moving to wounded ally")
                end
            else
                local face = lwi_faceAllyTask(wounded, "squad support: stabilize wounded ally", 55)
                if face then tasks[#tasks + 1] = face end
                tasks[#tasks + 1] = lwi_timeTask("BandageRightArm", 125 + lwi_rand(65), "squad support: stabilize wounded ally")
                if not lwi_requestIntent(chr, brain, "squad_rescue", "squad support: stabilize wounded ally", 9000) then return nil end
                lwi_tryStabilizeAlly(brain, wounded)
                living.lastSquadSupportAt = now
                living.lastSquadSupportKind = "rescue"
                return lwi_markIntentTasks(tasks, "squad_rescue", "squad support: stabilize wounded ally")
            end
        end
    end

    if explicitOrder or playerOwned then return nil end
    if program == "BaseGuard" or program == "CompanionGuard" then return nil end
    if not lwi_canDecide(living, "squad_cohesion", now, NPCLivingWorldIntentBridge.Config.squadCohesionCooldownMs) then return nil end

    summary = summary or lwi_nearbySquadSummary(chr, brain, tonumber(options and options.cohesionRadius) or NPCLivingWorldIntentBridge.Config.squadCohesionRadius or 15)
    if summary.count <= 0 then return nil end

    local target = nil
    local targetReason = nil
    if summary.leader and not lwi_isLeaderBrain(brain) and summary.leader.dist > (NPCLivingWorldIntentBridge.Config.squadLeaderDistance or 8.5) then
        target = summary.leader
        targetReason = "squad cohesion: rejoin leader"
    elseif summary.centerX and summary.centerY then
        local centerDist = lwi_dist(chr:getX(), chr:getY(), summary.centerX, summary.centerY)
        if centerDist > (NPCLivingWorldIntentBridge.Config.squadCentroidDistance or 10.5) then
            target = {x=summary.centerX, y=summary.centerY, z=summary.centerZ or chr:getZ(), dist=centerDist}
            targetReason = "squad cohesion: close formation gap"
        elseif NPCLivingWorldIntentBridge.HasRecentCombat(brain, now) and summary.nearest and summary.nearest.dist > 6.5 then
            target = summary.nearest
            targetReason = "squad cohesion: regroup after fight"
        end
    end

    if target and target.x and target.y then
        local move = lwi_moveToPointTask(chr, target.x, target.y, target.z or chr:getZ(), profile and profile.walkType or "Walk", profile and profile.endurance or 0, target.dist, targetReason)
        if move then
            if not lwi_requestIntent(chr, brain, "squad_cohesion", targetReason or "squad cohesion", 9000) then return nil end
            living.lastSquadCohesionAt = now
            return lwi_markIntentTasks({move}, "squad_cohesion", targetReason or "squad cohesion")
        end
    end

    if NPCLivingWorldIntentBridge.HasRecentCombat(brain, now) and summary.nearest and summary.nearest.dist <= 4.5 then
        local face = lwi_faceAllyTask(summary.nearest, "squad cohesion: check squadmate after fight", 45)
        if face then
            if not lwi_requestIntent(chr, brain, "squad_cohesion", "squad cohesion: check squadmate after fight", 7000) then return nil end
            living.lastSquadCohesionAt = now
            return lwi_markIntentTasks({face, lwi_timeTask((personality == "medic") and "BandageRightArm" or "ShiftWeight", 80 + lwi_rand(45), "squad cohesion: check squadmate after fight")}, "squad_cohesion", "squad cohesion: check squadmate after fight")
        end
    end

    return nil
end

local function lwi_planDangerMemoryTasks(chr, brain, living, personality, program, profile)
    if not (chr and brain and living) then return nil end
    if NPCLivingWorldIntentBridge.Config and NPCLivingWorldIntentBridge.Config.allowDangerMemoryMovement == false then return nil end
    local now = lwi_nowMs()
    if lwi_livingSuppressed(living, now) or lwi_underPathStress() or lwi_hasCombatContext(chr, brain) then return nil end
    if not lwi_canDecide(living, "danger_awareness", now, NPCLivingWorldIntentBridge.Config.dangerAwareCooldownMs) then return nil end

    local danger = lwi_nearestRememberedDanger(chr, living, now, NPCLivingWorldIntentBridge.Config.dangerWatchRadius)
    if not danger then return nil end

    local tasks = {}
    local close = danger.dist <= (NPCLivingWorldIntentBridge.Config.dangerCloseRadius or 5.75)
    local cautious = personality == "cautious" or personality == "medic" or personality == "disciplined" or tostring(program or "") == "BaseGuard"
    local aggressive = personality == "aggressive" or tostring(program or "") == "Raider"

    local face = lwi_faceTask(danger.x, danger.y, close and "living intent: watch remembered danger" or "living intent: check remembered danger", 70)
    if face then
        face.worldTrace = true
        face.dangerMemory = true
        tasks[#tasks + 1] = face
    end

    local anim = "ShiftWeight"
    local time = 90
    local traceReason = "living intent: remember dangerous place"
    if close and cautious then
        anim = "PullAtCollar"
        time = 110
        traceReason = "living intent: cautious near remembered danger"
    elseif aggressive then
        anim = "ShiftWeight"
        time = 105
        traceReason = "living intent: prepare near remembered danger"
    elseif personality == "greedy" then
        anim = "LootLow"
        time = 85
        traceReason = "living intent: check aftermath"
    end

    local wait = lwi_timeTask(anim, time + lwi_rand(35), traceReason)
    wait.worldTrace = true
    wait.dangerMemory = true
    tasks[#tasks + 1] = wait

    living.lastDangerObservedAt = now
    living.lastDangerObservedX = danger.x
    living.lastDangerObservedY = danger.y
    return tasks
end


local function lwi_baseData(chr)
    if not (chr and NPCBaseClient) then return nil, nil end
    if NPCBaseClient.GetBase then
        local ok, base = pcall(function() return NPCBaseClient.GetBase(chr) end)
        if ok and base then return base.id, base end
    end
    if NPCBaseClient.GetBaseClosest then
        local ok, baseId, base = pcall(function() return NPCBaseClient.GetBaseClosest(chr) end)
        if ok and base then return baseId, base end
    end
    return nil, nil
end

local function lwi_squareForRecord(chr, record)
    if not (chr and record and record.x and record.y) then return nil end
    local cell = (chr.getCell and chr:getCell()) or (getCell and getCell()) or nil
    if not (cell and cell.getGridSquare) then return nil end
    return cell:getGridSquare(math.floor(record.x), math.floor(record.y), math.floor(record.z or (chr.getZ and chr:getZ()) or 0))
end

local function lwi_nearestBaseRecord(chr, base, bucketName, radius, validator)
    if not (chr and base and bucketName and chr.getX and chr.getY) then return nil end
    local bucket = base[bucketName]
    if type(bucket) ~= "table" then return nil end

    local x = chr:getX()
    local y = chr:getY()
    local best = nil
    local bestDist = 99999
    local scanned = 0
    local limit = tonumber(NPCLivingWorldIntentBridge.Config.baseRecordScanLimit) or 28
    radius = tonumber(radius) or NPCLivingWorldIntentBridge.Config.baseWorkRadius or 34

    for _, record in pairs(bucket) do
        if record and record.x and record.y then
            scanned = scanned + 1
            if scanned > limit then break end
            local dist = lwi_dist(x, y, record.x + 0.5, record.y + 0.5)
            if dist <= radius and dist < bestDist then
                local ok = true
                if validator then ok = validator(record, dist) == true end
                if ok then
                    best = record
                    bestDist = dist
                end
            end
        end
    end

    if best then
        best._livingDist = bestDist
    end
    return best
end

local function lwi_baseCenter(base, chr)
    if base and base.x and base.y and base.x2 and base.y2 then
        return (base.x + base.x2) / 2, (base.y + base.y2) / 2, (chr and chr.getZ and chr:getZ()) or 0
    end
    if chr and chr.getX then return chr:getX(), chr:getY(), chr:getZ() end
    return nil, nil, 0
end

local function lwi_basePerimeterPoint(base, chr, living, now)
    local cx, cy, cz = lwi_baseCenter(base, chr)
    if not (base and base.x and base.y and base.x2 and base.y2 and cx and cy) then return cx, cy, cz end

    local margin = tonumber(NPCLivingWorldIntentBridge.Config.basePatrolMargin) or 2.5
    local seed = tonumber(living and living.seed) or 0
    local roll = (seed + math.floor((now or lwi_nowMs()) / 5000)) % 4
    local t = ((seed * 37 + math.floor((now or lwi_nowMs()) / 7000)) % 100) / 100
    local x, y

    if roll == 0 then
        x = base.x + margin + (base.x2 - base.x - margin * 2) * t
        y = base.y + margin
    elseif roll == 1 then
        x = base.x2 - margin
        y = base.y + margin + (base.y2 - base.y - margin * 2) * t
    elseif roll == 2 then
        x = base.x + margin + (base.x2 - base.x - margin * 2) * t
        y = base.y2 - margin
    else
        x = base.x + margin
        y = base.y + margin + (base.y2 - base.y - margin * 2) * t
    end

    return x, y, cz
end

local function lwi_markBaseTask(task, duty, reason)
    if not task then return nil end
    task.livingIntent = true
    task.baseDailyLife = true
    task.baseDuty = duty
    task.directorReason = reason or task.directorReason or "base daily life"
    return task
end

local function lwi_moveToBaseRecordTask(chr, record, profile, reason, closeDistance)
    if not (chr and record and record.x and record.y and NPCUtils and NPCUtils.GetMoveTask) then return nil end
    local x = record.x + 0.5
    local y = record.y + 0.5
    local z = record.z or (chr.getZ and chr:getZ()) or 0
    local dist = lwi_dist(chr:getX(), chr:getY(), x, y)
    local task = NPCUtils.GetMoveTask(profile and profile.endurance or 0, x, y, z, profile and profile.walkType or "Walk", closeDistance or dist, false)
    if task and not lwi_registerLivingMove(chr, task, "base") then return nil end
    return lwi_markBaseTask(task, "move", reason or "base daily life: move to work spot")
end

local function lwi_moveToBasePointTask(chr, x, y, z, profile, reason, closeDistance)
    if not (chr and x and y and NPCUtils and NPCUtils.GetMoveTask) then return nil end
    local dist = lwi_dist(chr:getX(), chr:getY(), x, y)
    local task = NPCUtils.GetMoveTask(profile and profile.endurance or 0, x, y, z or chr:getZ(), profile and profile.walkType or "Walk", closeDistance or dist, false)
    if task and not lwi_registerLivingMove(chr, task, "base patrol") then return nil end
    return lwi_markBaseTask(task, "patrol", reason or "base daily life: patrol base")
end

local function lwi_baseWorkAtRecordTasks(chr, record, profile, anim, reason, closeDistance, time)
    local tasks = {}
    if not (chr and record) then return tasks end
    local dist = lwi_dist(chr:getX(), chr:getY(), record.x + 0.5, record.y + 0.5)
    if dist > (closeDistance or 1.75) then
        local move = lwi_moveToBaseRecordTask(chr, record, profile, reason, closeDistance or dist)
        if move then tasks[#tasks + 1] = move end
    else
        local face = lwi_faceTask(record.x + 0.5, record.y + 0.5, reason, 55)
        if face then tasks[#tasks + 1] = lwi_markBaseTask(face, "face", reason) end
        tasks[#tasks + 1] = lwi_markBaseTask(lwi_timeTask(anim or "LootLow", time or (95 + lwi_rand(45)), reason), "work", reason)
    end
    return tasks
end

local function lwi_planBaseDailyLifeTasks(chr, brain, living, personality, program, profile, options)
    if not (chr and brain and living) then return nil end
    if NPCLivingWorldIntentBridge.Config and NPCLivingWorldIntentBridge.Config.allowAutonomousBaseLifeMovement == false then return nil end
    if lwi_hasExplicitOrder(brain) or lwi_hasPlayerMaster(brain) then return nil end

    local now = lwi_nowMs()
    if lwi_livingSuppressed(living, now) or lwi_underPathStress() or lwi_hasCombatContext(chr, brain) then return nil end
    if not lwi_canDecide(living, "base_daily_life", now, tonumber(options and options.baseCooldownMs) or NPCLivingWorldIntentBridge.Config.baseDailyLifeCooldownMs) then return nil end

    local baseId, base = lwi_baseData(chr)
    if not base then return nil end
    local tasks = {}
    local seed = lwi_seedNumber(chr, brain)
    local role = tostring(brain.role or brain.tacticalRole or ""):lower()
    local hour = getGameTime and getGameTime():getHour() or math.floor(lwi_nowHours() % 24)
    local roll = (seed + math.floor(now / 2400)) % 10

    if personality == "medic" then roll = (roll + 1) % 10 end
    if role == "guard" or role == "sentry" or program == "BaseGuard" then roll = (roll + 2) % 10 end
    if hour >= 0 and hour < 7 then roll = 8 end

    local record = nil
    local reason = nil

    if roll == 0 then
        if not lwi_canDecide(living, "base_work", now, NPCLivingWorldIntentBridge.Config.baseWorkCooldownMs) then return nil end
        record = lwi_nearestBaseRecord(chr, base, "containers", nil, function(rec) return rec.items ~= nil end)
        if record then
            local work = lwi_baseWorkAtRecordTasks(chr, record, profile, "Loot", "base daily life: sort supplies", 1.75, 105 + lwi_rand(45))
            for _, task in pairs(work) do tasks[#tasks + 1] = task end
            living.lastBaseDuty = "sort_supplies"
            living.lastBaseId = baseId
            return tasks
        end
    elseif roll == 1 then
        if not lwi_canDecide(living, "base_work", now, NPCLivingWorldIntentBridge.Config.baseWorkCooldownMs) then return nil end
        record = lwi_nearestBaseRecord(chr, base, "generators")
        if record then
            local work = lwi_baseWorkAtRecordTasks(chr, record, profile, (personality == "disciplined") and "BlowtorchHigh" or "Refuel", "base daily life: inspect generator", 1.85, 115 + lwi_rand(50))
            for _, task in pairs(work) do tasks[#tasks + 1] = task end
            living.lastBaseDuty = "generator_check"
            living.lastBaseId = baseId
            return tasks
        end
    elseif roll == 2 then
        if not lwi_canDecide(living, "base_work", now, NPCLivingWorldIntentBridge.Config.baseWorkCooldownMs) then return nil end
        record = lwi_nearestBaseRecord(chr, base, "blood")
        if record then
            local work = lwi_baseWorkAtRecordTasks(chr, record, profile, "Rake", "base daily life: clean around base", 1.65, 120 + lwi_rand(50))
            for _, task in pairs(work) do tasks[#tasks + 1] = task end
            living.lastBaseDuty = "cleanup"
            living.lastBaseId = baseId
            return tasks
        end
    elseif roll == 3 then
        if not lwi_canDecide(living, "base_work", now, NPCLivingWorldIntentBridge.Config.baseWorkCooldownMs) then return nil end
        record = lwi_nearestBaseRecord(chr, base, "farms") or lwi_nearestBaseRecord(chr, base, "waterSources")
        if record then
            local work = lwi_baseWorkAtRecordTasks(chr, record, profile, (base.farms and record.id and base.farms[record.id]) and "PourWateringCan" or "FillBucket", "base daily life: check water and plants", 1.8, 105 + lwi_rand(45))
            for _, task in pairs(work) do tasks[#tasks + 1] = task end
            living.lastBaseDuty = "water_plants"
            living.lastBaseId = baseId
            return tasks
        end
    elseif roll == 4 then
        if not lwi_canDecide(living, "base_work", now, NPCLivingWorldIntentBridge.Config.baseWorkCooldownMs) then return nil end
        record = lwi_nearestBaseRecord(chr, base, "deadbodies") or lwi_nearestBaseRecord(chr, base, "graves")
        if record then
            local work = lwi_baseWorkAtRecordTasks(chr, record, profile, "LootLow", "base daily life: clear the yard", 1.75, 95 + lwi_rand(40))
            for _, task in pairs(work) do tasks[#tasks + 1] = task end
            living.lastBaseDuty = "corpse_detail"
            living.lastBaseId = baseId
            return tasks
        end
    elseif roll == 5 or roll == 6 then
        if not lwi_canDecide(living, "base_patrol", now, NPCLivingWorldIntentBridge.Config.basePatrolCooldownMs) then return nil end
        local px, py, pz = lwi_basePerimeterPoint(base, chr, living, now)
        if px and py then
            local dist = lwi_dist(chr:getX(), chr:getY(), px, py)
            if dist > 4.0 then
                local move = lwi_moveToBasePointTask(chr, px, py, pz, profile, "base daily life: patrol perimeter", dist)
                if move then tasks[#tasks + 1] = move end
            else
                local face = lwi_faceTask(px, py, "base daily life: watch perimeter", 70)
                if face then tasks[#tasks + 1] = lwi_markBaseTask(face, "watch", "base daily life: watch perimeter") end
                tasks[#tasks + 1] = lwi_markBaseTask(lwi_timeTask((personality == "aggressive") and "ShiftWeight" or "ShiftWeight", 110 + lwi_rand(45), "base daily life: stand watch"), "watch", "base daily life: stand watch")
            end
            if #tasks > 0 then
                living.lastBaseDuty = "perimeter"
                living.lastBaseId = baseId
                return tasks
            end
        end
    elseif roll == 7 then
        if not lwi_canDecide(living, "base_social", now, NPCLivingWorldIntentBridge.Config.baseSocialCooldownMs) then return nil end
        local socialAnim = "Smoke"
        if personality == "cautious" then socialAnim = "ChewNails"
        elseif personality == "medic" then socialAnim = "BandageRightArm"
        elseif personality == "disciplined" then socialAnim = "ShiftWeight"
        elseif personality == "wanderer" then socialAnim = "WipeBrow" end
        tasks[#tasks + 1] = lwi_markBaseTask(lwi_timeTask(socialAnim, 120 + lwi_rand(65), "base daily life: off-duty moment"), "social", "base daily life: off-duty moment")
        living.lastBaseDuty = "social"
        living.lastBaseId = baseId
        return tasks
    else
        local cx, cy = lwi_baseCenter(base, chr)
        local face = lwi_faceTask(cx, cy, "base daily life: check camp", 60)
        if face then tasks[#tasks + 1] = lwi_markBaseTask(face, "camp_check", "base daily life: check camp") end
        tasks[#tasks + 1] = lwi_markBaseTask(lwi_timeTask((hour >= 0 and hour < 7) and "Sit" or "ShiftWeight", 95 + lwi_rand(45), "base daily life: quiet watch"), "camp_check", "base daily life: quiet watch")
        living.lastBaseDuty = "camp_check"
        living.lastBaseId = baseId
        return tasks
    end

    if #tasks > 0 then return tasks end
    return nil
end

function NPCLivingWorldIntentBridge.PlanAmbientTasks(director, runtime, chr, brain, state, reason, threat, uTick)
    if not (chr and brain) then return nil end
    if threat or lwi_hasCombatContext(chr, brain) then return nil end

    local living = NPCLivingWorldIntentBridge.GetLiving(brain, chr)
    if not living then return nil end
    if lwi_emergencyStabilization() then return nil end
    local now = lwi_nowMs()
    if lwi_livingSuppressed(living, now) then return nil end
    if not lwi_requestIntent(chr, brain, "living_ambient", reason or "living ambient", 6200) then return nil end
    local tasks = {}
    local personality = NPCLivingWorldIntentBridge.EnsurePersonality(brain, chr)

    local squadTasks = NPCLivingWorldIntentBridge.PlanSquadSupportTasks(director, runtime, chr, brain, state, reason, threat, {program = lwi_programName(brain)})
    if squadTasks and #squadTasks > 0 then return squadTasks end

    if NPCLivingWorldIntentBridge.HasRecentCombat(brain, now) then
        if not lwi_canDecide(living, "postcombat_ambient", now, NPCLivingWorldIntentBridge.Config.ambientCooldownMs) then return nil end
        local supplyTasks = lwi_planSupplyNeedTasks(chr, brain, living, personality, lwi_programName(brain), {walkType = "Walk", endurance = 0}, {key = "postcombat_supply", cooldownMs = 9000, radius = NPCLivingWorldIntentBridge.Config.needLootRadius, maxItems = NPCLivingWorldIntentBridge.Config.needLootMaxItems})
        if supplyTasks and #supplyTasks > 0 then return supplyTasks end
        local fx = living.lastCombatX or (chr.getX and chr:getX() + 2) or nil
        local fy = living.lastCombatY or (chr.getY and chr:getY()) or nil
        local face = lwi_faceTask(fx, fy, "living intent: scan after fight", 70)
        if face then tasks[#tasks + 1] = face end
        local anim = "WipeBrow"
        if personality == "disciplined" or personality == "aggressive" then anim = "ShiftWeight"
        elseif personality == "cautious" then anim = "PullAtCollar"
        elseif personality == "greedy" then anim = "LootLow" end
        local recover = lwi_timeTask(anim, 85 + lwi_rand(55), "living intent: recover after fight")
        recover.worldTrace = true
        tasks[#tasks + 1] = recover
        if lwi_canDecide(living, "danger_trace", now, NPCLivingWorldIntentBridge.Config.dangerTraceCooldownMs) and living.lastCombatX and living.lastCombatY then
            lwi_rememberDanger(chr, brain, living.lastCombatX, living.lastCombatY, living.lastCombatZ, living.lastCombatKind or "combat", 0.35, "living intent: marked recent fight")
            living.lastTraceX = living.lastCombatX
            living.lastTraceY = living.lastCombatY
            living.lastTraceKind = living.lastCombatKind or "combat"
            living.lastTraceAtMs = now
        end
        living.postCombatDone = true
        return tasks
    end

    local dangerTasks = lwi_planDangerMemoryTasks(chr, brain, living, personality, lwi_programName(brain), nil)
    if dangerTasks and #dangerTasks > 0 then return dangerTasks end

    local program = lwi_programName(brain)
    local baseLike = program == "BaseGuard" or brain.homeBaseZoneType or brain.baseZoneType
    if baseLike then
        local baseSupplyTasks = lwi_planSupplyNeedTasks(chr, brain, living, personality, program, {walkType = "Walk", endurance = 0}, {key = "base_supply_need", cooldownMs = NPCLivingWorldIntentBridge.Config.needLootScanCooldownMs, radius = math.min(7, NPCLivingWorldIntentBridge.Config.needLootRadius or 8), maxItems = NPCLivingWorldIntentBridge.Config.needLootMaxItems})
        if baseSupplyTasks and #baseSupplyTasks > 0 then return baseSupplyTasks end
        local baseTasks = lwi_planBaseDailyLifeTasks(chr, brain, living, personality, program, {walkType = "Walk", endurance = 0}, {baseCooldownMs = NPCLivingWorldIntentBridge.Config.baseAmbientCooldownMs})
        if baseTasks and #baseTasks > 0 then return baseTasks end
        if not lwi_canDecide(living, "base_ambient", now, NPCLivingWorldIntentBridge.Config.baseAmbientCooldownMs) then return nil end
        local roll = (lwi_seedNumber(chr, brain) + math.floor(now / 1000)) % 6
        if roll == 0 then tasks[#tasks + 1] = lwi_markBaseTask(lwi_timeTask("Smoke", 160, "living intent: base downtime"), "social", "living intent: base downtime")
        elseif roll == 1 then tasks[#tasks + 1] = lwi_markBaseTask(lwi_timeTask("ShiftWeight", 120, "living intent: check weapon"), "watch", "living intent: check weapon")
        elseif roll == 2 then tasks[#tasks + 1] = lwi_markBaseTask(lwi_timeTask("LootLow", 95, "living intent: sort supplies"), "supplies", "living intent: sort supplies")
        elseif roll == 3 then tasks[#tasks + 1] = lwi_markBaseTask(lwi_timeTask("WipeBrow", 100, "living intent: work around base"), "work", "living intent: work around base")
        else tasks[#tasks + 1] = lwi_markBaseTask(lwi_timeTask("ShiftWeight", 120, "living intent: stand watch"), "watch", "living intent: stand watch") end
        return tasks
    end

    local supplyTasks = lwi_planSupplyNeedTasks(chr, brain, living, personality, program, {walkType = "Walk", endurance = 0}, {key = "ambient_supply_need", cooldownMs = NPCLivingWorldIntentBridge.Config.needLootScanCooldownMs, radius = NPCLivingWorldIntentBridge.Config.needLootRadius, maxItems = NPCLivingWorldIntentBridge.Config.needLootMaxItems})
    if supplyTasks and #supplyTasks > 0 then return supplyTasks end

    if not lwi_canDecide(living, "ambient", now, NPCLivingWorldIntentBridge.Config.ambientCooldownMs) then return nil end
    local roll = (lwi_seedNumber(chr, brain) + math.floor(now / 1500)) % 7
    if personality == "greedy" or program == "Looter" then roll = 1 end

    if roll == 1 or roll == 2 then
        if lwi_canDecide(living, "lootscan", now, NPCLivingWorldIntentBridge.Config.lootScanCooldownMs) then
            local square = nil
            if runtime and runtime.findContainerSquare then
                square = runtime.findContainerSquare(chr, math.min(6, NPCLivingWorldIntentBridge.Config.lootScanRadius or 7))
            else
                square = lwi_findContainerSquare(chr, math.min(6, NPCLivingWorldIntentBridge.Config.lootScanRadius or 7))
            end
            if square then
                local dist = lwi_dist(chr:getX(), chr:getY(), square:getX() + 0.5, square:getY() + 0.5)
                if dist > 1.8 then
                    local move = lwi_moveToSquareTask(chr, square, "Walk", 0)
                    if move then tasks[#tasks + 1] = move end
                else
                    tasks[#tasks + 1] = lwi_lootTask(square, "living intent: scavenge visible supplies")
                end
                if #tasks > 0 then return tasks end
            end
        end
    end

    local faceX = chr.getX and chr:getX() + (lwi_rand(7) - 3) or nil
    local faceY = chr.getY and chr:getY() + (lwi_rand(7) - 3) or nil
    if roll == 0 or personality == "cautious" then
        local face = lwi_faceTask(faceX, faceY, "living intent: check surroundings", 70)
        if face then tasks[#tasks + 1] = face end
        tasks[#tasks + 1] = lwi_timeTask("PullAtCollar", 90, "living intent: listen")
    elseif roll == 3 or personality == "disciplined" then
        tasks[#tasks + 1] = lwi_timeTask("ShiftWeight", 105, "living intent: maintain weapon")
    elseif roll == 4 or personality == "medic" then
        tasks[#tasks + 1] = lwi_timeTask("BandageRightArm", 110, "living intent: check bandages")
    elseif roll == 5 then
        tasks[#tasks + 1] = lwi_timeTask("Smoke", 150, "living intent: take a breath")
    else
        tasks[#tasks + 1] = lwi_timeTask("ShiftWeight", 100, "living intent: watch the street")
    end

    return tasks
end

function NPCLivingWorldIntentBridge.PlanProgramTasks(chr, tasks, profile, options)
    tasks = tasks or {}
    if not chr then return false end
    local brain = lwi_brain(chr)
    if not brain then return false end
    if lwi_hasExplicitOrder(brain) and lwi_hasPlayerMaster(brain) then return false end

    local living = NPCLivingWorldIntentBridge.GetLiving(brain, chr)
    if not living then return false end
    if lwi_emergencyStabilization() then return false end
    local now = lwi_nowMs()
    if lwi_livingSuppressed(living, now) or lwi_hasCombatContext(chr, brain) then return false end
    if not lwi_requestIntent(chr, brain, "living_ambient", "program living task", 6200) then return false end
    local program = tostring(options and options.program or lwi_programName(brain) or "")
    local personality = NPCLivingWorldIntentBridge.EnsurePersonality(brain, chr)

    local squadTasks = NPCLivingWorldIntentBridge.PlanSquadSupportTasks(nil, nil, chr, brain, nil, nil, nil, {program = program, profile = profile})
    if squadTasks and #squadTasks > 0 then
        for _, task in pairs(squadTasks) do tasks[#tasks + 1] = task end
        return true
    end

    local dangerTasks = lwi_planDangerMemoryTasks(chr, brain, living, personality, program, profile)
    if dangerTasks and #dangerTasks > 0 then
        for _, task in pairs(dangerTasks) do tasks[#tasks + 1] = task end
        return true
    end

    if program == "BaseGuard" or (options and options.allowBaseLife == true) or brain.homeBaseZoneType or brain.baseZoneType then
        local baseTasks = lwi_planBaseDailyLifeTasks(chr, brain, living, personality, program, profile, options)
        if baseTasks and #baseTasks > 0 then
            for _, task in pairs(baseTasks) do tasks[#tasks + 1] = task end
            return true
        end
    end

    local supplyTasks = lwi_planSupplyNeedTasks(chr, brain, living, personality, program, profile, {key = "program_supply_need", cooldownMs = NPCLivingWorldIntentBridge.Config.needLootScanCooldownMs, radius = tonumber(options and options.lootRadius) or NPCLivingWorldIntentBridge.Config.needLootRadius, maxItems = NPCLivingWorldIntentBridge.Config.needLootMaxItems})
    if supplyTasks and #supplyTasks > 0 then
        for _, task in pairs(supplyTasks) do tasks[#tasks + 1] = task end
        return true
    end

    if not lwi_canDecide(living, "program", now, tonumber(options and options.cooldownMs) or NPCLivingWorldIntentBridge.Config.ambientCooldownMs) then
        return false
    end

    local allowLoot = options and options.allowLoot ~= false
    if allowLoot and (program == "Looter" or program == "Raider" or personality == "greedy") and lwi_canDecide(living, "program_lootscan", now, NPCLivingWorldIntentBridge.Config.lootScanCooldownMs) then
        local square = lwi_findContainerSquare(chr, tonumber(options and options.lootRadius) or 6)
        if square then
            local dist = lwi_dist(chr:getX(), chr:getY(), square:getX() + 0.5, square:getY() + 0.5)
            if dist > 1.8 then
                local move = lwi_moveToSquareTask(chr, square, profile and profile.walkType or "Walk", profile and profile.endurance or 0)
                if move then tasks[#tasks + 1] = move end
            else
                tasks[#tasks + 1] = lwi_lootTask(square, "living intent: scavenge between fights")
            end
            return #tasks > 0
        end
    end

    local roll = (lwi_seedNumber(chr, brain) + math.floor(now / 1000)) % 5
    if roll == 0 then
        tasks[#tasks + 1] = lwi_timeTask("ShiftWeight", 110, "living intent: check weapon")
    elseif roll == 1 then
        local face = lwi_faceTask(chr:getX() + (lwi_rand(9) - 4), chr:getY() + (lwi_rand(9) - 4), "living intent: scan street", 70)
        if face then tasks[#tasks + 1] = face end
        tasks[#tasks + 1] = lwi_timeTask("ShiftWeight", 95, "living intent: watch for movement")
    elseif roll == 2 then
        tasks[#tasks + 1] = lwi_timeTask("LootLow", 80, "living intent: check pockets")
    elseif roll == 3 then
        tasks[#tasks + 1] = lwi_timeTask("WipeBrow", 100, "living intent: recover")
    else
        tasks[#tasks + 1] = lwi_timeTask(options and options.fallbackAnim or "ShiftWeight", 120, "living intent: pause with purpose")
    end

    return #tasks > 0
end
