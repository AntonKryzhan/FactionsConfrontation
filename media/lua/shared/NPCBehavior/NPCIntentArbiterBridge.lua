-- NPCIntentArbiterBridge.lua
-- Runtime-only intent ownership guard for materialized NPCs.
-- Keeps combat, player orders, rescue/regroup, base life and living-world
-- ambient tasks from competing for the same NPC in the same short window.

NPCIntentArbiterBridge = NPCIntentArbiterBridge or {}

NPCIntentArbiterBridge.VERSION = "2026-05-31-stage311-single-owner-arbiter"

NPCIntentArbiterBridge.Config = NPCIntentArbiterBridge.Config or {
    defaultTtlMs = 3500,
    combatTtlMs = 5600,
    playerOrderTtlMs = 5200,
    livingTtlMs = 7600,
    movementTtlMs = 9000,
    sameOwnerRefreshMs = 900,
    lowPriorityOwnerBlockMs = 2600,
    priorities = {
        dead = 100,
        combat = 95,
        emergency = 92,
        player_order = 88,
        self_preserve = 76,
        active_task = 68,
        wounded_rescue = 62,
        squad_rescue = 62,
        squad_cohesion = 50,
        regroup = 48,
        danger_memory = 42,
        post_combat = 40,
        base_life = 34,
        supply_need = 31,
        world_routine = 32,
        living_move = 28,
        living_state = 26,
        living_ambient = 22,
        ambient = 20
    }
}

local function ia_nowMs()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then return math.floor((getGameTime():getWorldAgeHours() or 0) * 3600000) end
    return 0
end

local function ia_norm(value)
    if value == nil then return nil end
    value = tostring(value)
    if value == "" or value == "nil" or value == "false" then return nil end
    return value
end

local function ia_priority(owner, fallback)
    owner = ia_norm(owner) or "ambient"
    local priorities = NPCIntentArbiterBridge.Config.priorities or {}
    return tonumber(priorities[owner]) or tonumber(fallback) or 20
end

local function ia_ttl(owner, fallback)
    owner = ia_norm(owner) or "ambient"
    if owner == "combat" or owner == "emergency" then return tonumber(fallback) or tonumber(NPCIntentArbiterBridge.Config.combatTtlMs) or 5600 end
    if owner == "player_order" then return tonumber(fallback) or tonumber(NPCIntentArbiterBridge.Config.playerOrderTtlMs) or 5200 end
    if owner == "living_move" or owner == "world_routine" or owner == "squad_rescue" or owner == "squad_cohesion" or owner == "base_life" or owner == "supply_need" then
        return tonumber(fallback) or tonumber(NPCIntentArbiterBridge.Config.movementTtlMs) or 9000
    end
    if string.sub(owner, 1, 6) == "living" or owner == "ambient" or owner == "post_combat" or owner == "danger_memory" then
        return tonumber(fallback) or tonumber(NPCIntentArbiterBridge.Config.livingTtlMs) or 7600
    end
    return tonumber(fallback) or tonumber(NPCIntentArbiterBridge.Config.defaultTtlMs) or 3500
end

local function ia_ensure(brain)
    if not brain then return nil end
    brain.ai = brain.ai or {}
    brain.ai.intentArbiter = brain.ai.intentArbiter or {}
    return brain.ai.intentArbiter
end

local function ia_current(arbiter, now)
    if not arbiter then return nil end
    now = now or ia_nowMs()
    if arbiter.currentOwner and arbiter.currentUntilMs and now <= arbiter.currentUntilMs then
        return arbiter.currentOwner, tonumber(arbiter.currentPriority) or 0, arbiter.currentReason
    end
    arbiter.currentOwner = nil
    arbiter.currentPriority = nil
    arbiter.currentReason = nil
    arbiter.currentUntilMs = nil
    return nil
end

local function ia_actionLooksCombat(action)
    action = tostring(action or ""):lower()
    return action == "shoot" or action == "aim" or action == "hit" or action == "shove" or action == "reload"
        or action == "targetspotted" or action == "target_spotted" or action == "targetsighted" or action == "target_sighted"
        or action == "combat" or action == "keepdistance" or action == "meleefallback" or action == "emergencydefense"
end

local function ia_stateLooksCombat(state)
    state = tostring(state or ""):lower()
    return state == "attack" or state == "combat" or state == "keepdistance" or state == "reloadcover"
        or state == "meleefallback" or state == "emergencydefense" or state == "searchenemy" or state == "recoverpath"
end

local function ia_orderName(brain)
    if not brain then return nil end
    local order = brain.order or brain.directorOrder
    if type(order) == "table" then order = order.name or order.action or order.type or order.mode end
    order = ia_norm(order)
    if not order then return nil end
    order = tostring(order):lower()
    if order == "free" or order == "freeroam" or order == "free_roam" then return nil end
    return order
end

local function ia_hasPlayerMaster(brain)
    return brain and (brain.master ~= nil or brain.mercenaryHired == true or brain.hired == true)
end

function NPCIntentArbiterBridge.Get(brain)
    return ia_ensure(brain)
end

function NPCIntentArbiterBridge.Current(brain)
    local arbiter = ia_ensure(brain)
    local owner, priority, reason = ia_current(arbiter, ia_nowMs())
    return owner, priority, reason
end

function NPCIntentArbiterBridge.Check(chr, brain, owner, reason, options)
    if not brain then return false end
    options = options or {}
    owner = ia_norm(owner) or "ambient"
    local now = tonumber(options.nowMs) or ia_nowMs()
    local arbiter = ia_ensure(brain)
    if not arbiter then return false end

    local priority = ia_priority(owner, options.priority)
    local currentOwner, currentPriority = ia_current(arbiter, now)

    if currentOwner and currentOwner ~= owner then
        if currentPriority > priority then return false end
        if currentPriority == priority and string.sub(owner, 1, 6) == "living" then return false end
    end

    if currentOwner == owner and arbiter.lastClaimAtMs and now - arbiter.lastClaimAtMs < (tonumber(NPCIntentArbiterBridge.Config.sameOwnerRefreshMs) or 900) then
        return true
    end

    local cooldowns = arbiter.ownerCooldowns
    if cooldowns and cooldowns[owner] and now < cooldowns[owner] then
        return false
    end

    return true
end

function NPCIntentArbiterBridge.Request(chr, brain, owner, reason, options)
    if not NPCIntentArbiterBridge.Check(chr, brain, owner, reason, options) then return false end
    options = options or {}
    owner = ia_norm(owner) or "ambient"
    local now = tonumber(options.nowMs) or ia_nowMs()
    local arbiter = ia_ensure(brain)
    if not arbiter then return false end

    local priority = ia_priority(owner, options.priority)
    local ttl = ia_ttl(owner, options.ttlMs)
    arbiter.currentOwner = owner
    arbiter.currentPriority = priority
    arbiter.currentReason = reason or owner
    arbiter.currentUntilMs = now + ttl
    arbiter.lastClaimAtMs = now
    arbiter.claimCount = (tonumber(arbiter.claimCount) or 0) + 1
    arbiter.lastOwner = owner
    arbiter.lastReason = reason
    arbiter.lastPriority = priority
    arbiter.lastAtMs = now

    if chr and chr.getX then
        arbiter.lastX = chr:getX()
        arbiter.lastY = chr:getY()
        arbiter.lastZ = chr:getZ()
    end

    local cooldown = tonumber(options.cooldownMs)
    if cooldown and cooldown > 0 then
        arbiter.ownerCooldowns = arbiter.ownerCooldowns or {}
        arbiter.ownerCooldowns[owner] = now + cooldown
    end

    return true
end

function NPCIntentArbiterBridge.UpdateContext(chr, brain, context)
    if not brain then return false end
    context = context or {}
    local currentAction = context.currentAction
    if type(currentAction) == "function" then
        local ok, got = pcall(function() return currentAction(chr) end)
        if ok then currentAction = got else currentAction = nil end
    end

    if brain.dead == true or brain.isDead == true then
        return NPCIntentArbiterBridge.Request(chr, brain, "dead", "dead brain", {ttlMs = 12000})
    end

    if context.threat or brain.currentThreat or brain.enemy or brain.target or (brain.fsm and (brain.fsm.currentThreat or brain.fsm.enemy or brain.fsm.target)) or ia_actionLooksCombat(currentAction) or ia_stateLooksCombat(brain.state) or ia_stateLooksCombat(brain.mode) or (brain.fsm and (ia_stateLooksCombat(brain.fsm.state) or ia_stateLooksCombat(brain.fsm.mode))) then
        return NPCIntentArbiterBridge.Request(chr, brain, "combat", context.reason or "combat context", {ttlMs = context.ttlMs or NPCIntentArbiterBridge.Config.combatTtlMs})
    end

    if ia_orderName(brain) or ia_hasPlayerMaster(brain) then
        return NPCIntentArbiterBridge.Request(chr, brain, "player_order", context.reason or "explicit order", {ttlMs = context.ttlMs or NPCIntentArbiterBridge.Config.playerOrderTtlMs})
    end

    local health = tonumber(context.health or brain.health or (brain.fsm and brain.fsm.health))
    if health and health > 1 and health <= 5 then health = health / 5 end
    if health and health < 0.36 then
        return NPCIntentArbiterBridge.Request(chr, brain, "self_preserve", "low health", {ttlMs = 4200})
    end

    ia_current(ia_ensure(brain), ia_nowMs())
    return false
end

function NPCIntentArbiterBridge.AllowLiving(chr, brain, owner, reason, options)
    if not brain then return false end
    options = options or {}
    owner = owner or "living_ambient"
    if NPCIntentArbiterBridge.UpdateContext(chr, brain, {currentAction = options.currentAction, threat = options.threat, health = options.health}) then
        local currentOwner = NPCIntentArbiterBridge.Current(brain)
        if currentOwner ~= owner and currentOwner ~= "ambient" then return false end
    end
    return NPCIntentArbiterBridge.Check(chr, brain, owner, reason, options)
end

function NPCIntentArbiterBridge.MarkTask(task, owner, reason)
    if not task then return nil end
    task.intentOwner = owner
    task.intentReason = reason or task.intentReason or task.directorReason
    return task
end

function NPCIntentArbiterBridge.MarkTasks(tasks, owner, reason)
    if type(tasks) ~= "table" then return tasks end
    for _, task in pairs(tasks) do
        if type(task) == "table" then NPCIntentArbiterBridge.MarkTask(task, owner, reason) end
    end
    return tasks
end
