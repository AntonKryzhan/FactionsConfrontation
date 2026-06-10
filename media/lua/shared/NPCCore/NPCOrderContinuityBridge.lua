-- NPCOrderContinuityBridge.lua
-- Stage 373: player-order continuity and squad return-to-formation polish.
--
-- Advisory runtime layer only. It does not add network commands, task names,
-- save roots, damage contracts or Java hooks. The goal is to keep hired/ordered
-- NPCs from being stolen by stale tactical, memory or post-combat ambience after
-- the player has given Follow/Hold/Guard-style orders, while still allowing
-- urgent healing, reload and explicit loot/rearm orders.

NPCOrderContinuityBridge = NPCOrderContinuityBridge or {}
NPCOrderContinuityBridge.VERSION = "2026-06-01-stage373-order-continuity-1"

pcall(require, "NPCBehavior/NPCBehaviorBridge")
pcall(require, "NPCCore/NPCPostCombatLootBridge")

NPCOrderContinuityBridge.Config = NPCOrderContinuityBridge.Config or {
    enabled = true,
    debug = false,
    quietAfterThreatMs = 3600,
    orderStateHoldMs = 7200,
    orderThinkMs = 850,
    returnToLeaderDistance = 6.0,
    hardReturnDistance = 10.5,
    guardResumeDistance = 7.5,
    holdResumeDistance = 5.0,
    taskPathThrottleMs = 1250,
    taskSameTargetThrottleMs = 5200,
    blockAmbientLootMs = 11000,
    manualLootGraceMs = 45000,
    staleTacticalMs = 9000
}

local function oco_nowMs()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then
        local ok, hours = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok and hours then return math.floor((tonumber(hours) or 0) * 3600000) end
    end
    return 0
end

local function oco_debug(msg)
    if NPCOrderContinuityBridge.Config.debug == true then
        print("[NPCOrderContinuity] " .. tostring(msg))
    end
end

local function oco_orderObject(brain)
    if type(brain) ~= "table" then return nil end
    return brain.order or brain.directorOrder or brain.mercenaryOrder
end

function NPCOrderContinuityBridge.OrderName(brain)
    local order = oco_orderObject(brain)
    if type(order) == "table" then
        return tostring(order.name or order.orderName or order.action or order.type or order.mode or "")
    end
    if order ~= nil then return tostring(order) end
    return ""
end

function NPCOrderContinuityBridge.NormalizeOrder(name)
    name = tostring(name or ""):lower()
    name = name:gsub("%s+", "")
    name = name:gsub("_", "")
    name = name:gsub("%-", "")
    if name == "follow" or name == "followme" or name == "bodyguard" then return "follow" end
    if name == "guard" or name == "guardarea" or name == "guardhere" or name == "guardplayer" then return "guard" end
    if name == "hold" or name == "holdposition" or name == "holdhere" then return "hold" end
    if name == "patrol" or name == "patrolarea" then return "patrol" end
    if name == "return" or name == "returntobase" then return "return" end
    if name == "loot" or name == "lootarea" then return "loot" end
    return name
end

local function oco_orderName(brain)
    return NPCOrderContinuityBridge.NormalizeOrder(NPCOrderContinuityBridge.OrderName(brain))
end

local function oco_state(brain)
    if type(brain) ~= "table" then return nil end
    brain._orderContinuity = brain._orderContinuity or {}
    return brain._orderContinuity
end

function NPCOrderContinuityBridge.IsPlayerControlled(brain)
    if type(brain) ~= "table" then return false end
    if brain.master ~= nil or brain.mercenaryHired == true or brain.hired == true or brain.isPlayerGuard == true then return true end
    if brain.mercenaryHiredBy ~= nil or brain.relationshipToPlayer == "hired_bodyguard" or brain.relationshipToPlayer == "companion" then return true end
    local order = oco_orderObject(brain)
    if type(order) == "table" then
        if order.source == "player" or order.playerId or order.master or order.followPlayer or order.manual == true then return true end
        local name = NPCOrderContinuityBridge.NormalizeOrder(order.name or order.orderName or order.action or order.type or order.mode)
        return name == "follow" or name == "guard" or name == "hold" or name == "patrol" or name == "return" or name == "loot"
    end
    local name = NPCOrderContinuityBridge.NormalizeOrder(order)
    return name == "follow" or name == "guard" or name == "hold" or name == "patrol" or name == "return" or name == "loot"
end

function NPCOrderContinuityBridge.IsManualLootOrder(brain)
    if type(brain) ~= "table" then return false end
    local order = oco_orderObject(brain)
    if NPCPostCombatLootBridge and NPCPostCombatLootBridge.IsManualLootOrder then
        local ok, manual = pcall(function() return NPCPostCombatLootBridge.IsManualLootOrder(order) end)
        if ok and manual == true then return true end
    end
    local raw = tostring(NPCOrderContinuityBridge.OrderName(brain) or ""):lower()
    raw = raw:gsub("%s+", "")
    raw = raw:gsub("_", "")
    raw = raw:gsub("%-", "")
    if raw == "rearmhere" or raw == "rearm" then return true end
    if raw:find("lootbodies", 1, true) == 1 then return true end
    if raw:find("checkcorpses", 1, true) == 1 then return true end
    if raw:find("corpse", 1, true) ~= nil and raw:find("loot", 1, true) ~= nil then return true end
    if type(order) == "table" and (order.manualLoot == true or order.manualSupplyLoot == true or order.lootBodies == true or order.rearm == true) then return true end
    return false
end

local function oco_health01(chr)
    if not (chr and chr.getHealth) then return 1 end
    local ok, health = pcall(function() return chr:getHealth() end)
    if not ok then return 1 end
    health = tonumber(health) or 1
    if health > 1 then health = health / 100 end
    if health < 0 then return 0 end
    if health > 1 then return 1 end
    return health
end

local function oco_hasReloadableFirearm(brain, runtime)
    if runtime and runtime.hasReloadableFirearm then
        local ok, value = pcall(function() return runtime.hasReloadableFirearm(brain) end)
        if ok and value == true then return true end
    end
    return false
end

local function oco_master(chr, brain, runtime)
    if runtime and runtime.masterPlayer then
        local ok, player = pcall(function() return runtime.masterPlayer(chr, brain) end)
        if ok and player then return player end
    end
    if NPCBehaviorBridge and NPCBehaviorBridge.GetMasterPlayer then
        local ok, player = pcall(function() return NPCBehaviorBridge.GetMasterPlayer(chr) end)
        if ok and player then return player end
    end
    if brain and brain.master ~= nil and getSpecificPlayer then
        local idx = tonumber(brain.master)
        if idx then
            local ok, player = pcall(function() return getSpecificPlayer(idx) end)
            if ok and player then return player end
        end
    end
    return nil
end

local function oco_dist(chr, target)
    if not (chr and target and target.getX and target.getY) then return 9999 end
    local dx = (tonumber(chr:getX()) or 0) - (tonumber(target:getX()) or 0)
    local dy = (tonumber(chr:getY()) or 0) - (tonumber(target:getY()) or 0)
    return math.sqrt(dx * dx + dy * dy)
end

local function oco_currentState(brain)
    if not brain then return "" end
    return tostring((brain.fsm and brain.fsm.state) or brain.state or "")
end

local function oco_isTacticalState(state)
    state = tostring(state or "")
    return state == "SearchEnemy"
        or state == "TacticalCover"
        or state == "HoldAngle"
        or state == "FlankEnemy"
        or state == "SuppressEnemy"
        or state == "BoundForward"
        or state == "Regroup"
end

function NPCOrderContinuityBridge.NotifyOrderContext(chr, brain, orderName)
    if NPCOrderContinuityBridge.Config.enabled == false or type(brain) ~= "table" then return nil end
    local st = oco_state(brain)
    local now = oco_nowMs()
    local normalized = NPCOrderContinuityBridge.NormalizeOrder(orderName or NPCOrderContinuityBridge.OrderName(brain))
    if st.orderName ~= normalized then
        st.orderName = normalized
        st.orderChangedAt = now
        st.returnHoldUntil = now + (tonumber(NPCOrderContinuityBridge.Config.orderStateHoldMs) or 7200)
        st.lastDecoratedAt = 0
        if normalized == "loot" or NPCOrderContinuityBridge.IsManualLootOrder(brain) then
            st.manualLootUntil = now + (tonumber(NPCOrderContinuityBridge.Config.manualLootGraceMs) or 45000)
        end
        oco_debug("order=" .. tostring(normalized))
    end
    return st
end

function NPCOrderContinuityBridge.Update(chr, brain, threat, runtime)
    if NPCOrderContinuityBridge.Config.enabled == false or not (chr and brain) then return nil end
    local st = NPCOrderContinuityBridge.NotifyOrderContext(chr, brain)
    local now = runtime and runtime.now and runtime.now() or oco_nowMs()
    if threat then
        st.lastThreatAt = now
        st.lastThreatX = tonumber(threat.x)
        st.lastThreatY = tonumber(threat.y)
        st.lastThreatZ = tonumber(threat.z) or (chr.getZ and chr:getZ()) or 0
        st.returnHoldUntil = math.max(tonumber(st.returnHoldUntil) or 0, now + (tonumber(NPCOrderContinuityBridge.Config.quietAfterThreatMs) or 3600))
    elseif NPCOrderContinuityBridge.IsPlayerControlled(brain) then
        local order = st.orderName or oco_orderName(brain)
        if order == "follow" or order == "guard" or order == "hold" then
            local quiet = tonumber(NPCOrderContinuityBridge.Config.quietAfterThreatMs) or 3600
            if now - (tonumber(st.lastThreatAt) or 0) >= quiet then
                st.returnHoldUntil = math.max(tonumber(st.returnHoldUntil) or 0, now + (tonumber(NPCOrderContinuityBridge.Config.orderStateHoldMs) or 7200))
            end
        end
    end

    local state = oco_currentState(brain)
    if oco_isTacticalState(state) then
        st.lastTacticalState = state
        st.lastTacticalAt = now
    end
    return st
end


function NPCOrderContinuityBridge.NotifyManualLootFinished(chr, brain, changed, task)
    if NPCOrderContinuityBridge.Config.enabled == false or type(brain) ~= "table" then return nil end
    local st = oco_state(brain)
    local now = oco_nowMs()
    st.manualLootFinishedAt = now
    st.manualLootUntil = 0
    st.returnHoldUntil = math.max(tonumber(st.returnHoldUntil) or 0, now + 4200)
    st.nextThinkAt = 0
    return st
end

function NPCOrderContinuityBridge.ShouldBlockAmbientLoot(chr, brain, threat, runtime)
    if NPCOrderContinuityBridge.Config.enabled == false then return false end
    if threat then return true end
    if not NPCOrderContinuityBridge.IsPlayerControlled(brain) then return false end
    if NPCOrderContinuityBridge.IsManualLootOrder(brain) then return false end
    if brain and (brain.allowCompanionPostCombatLoot == true or brain.autoPostCombatLoot == true) then return false end
    local order = oco_orderName(brain)
    if order ~= "follow" and order ~= "guard" and order ~= "hold" and order ~= "patrol" then return false end
    local st = oco_state(brain)
    local now = runtime and runtime.now and runtime.now() or oco_nowMs()
    if now < (tonumber(st.manualLootUntil) or 0) then return false end
    if now < (tonumber(st.returnHoldUntil) or 0) then return true end
    local blockMs = tonumber(NPCOrderContinuityBridge.Config.blockAmbientLootMs) or 11000
    if now - (tonumber(st.orderChangedAt) or 0) < blockMs then return true end
    return true
end

function NPCOrderContinuityBridge.ChooseState(chr, brain, threat, states, runtime)
    if NPCOrderContinuityBridge.Config.enabled == false or not (chr and brain and states) then return nil end
    if threat then return nil end
    if not NPCOrderContinuityBridge.IsPlayerControlled(brain) then return nil end
    if NPCOrderContinuityBridge.IsManualLootOrder(brain) then return nil end

    local now = runtime and runtime.now and runtime.now() or oco_nowMs()
    local st = oco_state(brain)
    local nextThink = tonumber(st.nextThinkAt) or 0
    if now < nextThink then return nil end
    st.nextThinkAt = now + (tonumber(NPCOrderContinuityBridge.Config.orderThinkMs) or 850)

    local quiet = tonumber(NPCOrderContinuityBridge.Config.quietAfterThreatMs) or 3600
    if now - (tonumber(st.lastThreatAt) or 0) < quiet then return nil end

    local health = oco_health01(chr)
    if health < 0.42 then return nil end
    if oco_hasReloadableFirearm(brain, runtime) then return nil end

    local order = st.orderName or oco_orderName(brain)
    local curState = oco_currentState(brain)
    local master = oco_master(chr, brain, runtime)
    local dist = master and oco_dist(chr, master) or 9999

    if order == "follow" then
        if dist >= (tonumber(NPCOrderContinuityBridge.Config.hardReturnDistance) or 10.5) then
            return states.Regroup or states.FollowPlayer, "order continuity hard regroup"
        end
        if dist >= (tonumber(NPCOrderContinuityBridge.Config.returnToLeaderDistance) or 6.0)
            or oco_isTacticalState(curState)
            or curState == "LootArea" then
            return states.FollowPlayer, "order continuity follow"
        end
    elseif order == "guard" then
        if dist < 999 and dist >= (tonumber(NPCOrderContinuityBridge.Config.guardResumeDistance) or 7.5) and brain.master then
            return states.GuardPlayer or states.FollowPlayer, "order continuity guard player"
        end
        if oco_isTacticalState(curState) or curState == "LootArea" then
            if brain.master then return states.GuardPlayer or states.GuardArea, "order continuity guard" end
            return states.GuardArea, "order continuity guard area"
        end
    elseif order == "hold" then
        if oco_isTacticalState(curState) or curState == "LootArea" then
            return states.HoldPosition, "order continuity hold"
        end
    end

    return nil
end

function NPCOrderContinuityBridge.DecorateTask(task, chr, brain, state, reason, threat)
    if NPCOrderContinuityBridge.Config.enabled == false or type(task) ~= "table" then return task end
    local action = tostring(task.action or "")
    if action ~= "Move" and action ~= "GoTo" then return task end
    if not NPCOrderContinuityBridge.IsPlayerControlled(brain) then return task end
    local order = oco_orderName(brain)
    if order ~= "follow" and order ~= "guard" and order ~= "hold" and order ~= "patrol" then return task end

    task.orderContinuity = true
    task.director = task.director ~= false
    task.naturalMotion = task.naturalMotion ~= false
    task.smoothTurn = task.smoothTurn ~= false
    task.engineAssist = task.engineAssist ~= false
    task.noHardFace = task.noHardFace ~= false
    task.closeSlow = task.closeSlow ~= false
    task.pathThrottleMs = math.max(tonumber(task.pathThrottleMs) or 0, tonumber(NPCOrderContinuityBridge.Config.taskPathThrottleMs) or 1250)
    task.sameTargetPathThrottleMs = math.max(tonumber(task.sameTargetPathThrottleMs) or 0, tonumber(NPCOrderContinuityBridge.Config.taskSameTargetThrottleMs) or 5200)
    if order == "follow" or state == "FollowPlayer" or state == "Regroup" then
        task.arriveDist = math.max(tonumber(task.arriveDist) or 0.8, 0.95)
        task.engineAssistSoftRetargetRadius = math.max(tonumber(task.engineAssistSoftRetargetRadius) or 0, 3.2)
        task.engineAssistSoftRetargetHoldMs = math.max(tonumber(task.engineAssistSoftRetargetHoldMs) or 0, 4600)
    elseif order == "hold" or order == "guard" then
        task.arriveDist = math.max(tonumber(task.arriveDist) or 0.85, 1.05)
        task.engineAssistSoftRetargetRadius = math.max(tonumber(task.engineAssistSoftRetargetRadius) or 0, 2.6)
        task.engineAssistSoftRetargetHoldMs = math.max(tonumber(task.engineAssistSoftRetargetHoldMs) or 0, 5200)
    end
    task.directorReason = task.directorReason or reason or "order continuity"
    return task
end

function NPCOrderContinuityBridge.DecorateTasks(tasks, chr, brain, state, reason, threat)
    if type(tasks) ~= "table" then return tasks end
    for _, task in ipairs(tasks) do
        NPCOrderContinuityBridge.DecorateTask(task, chr, brain, state, reason, threat)
    end
    return tasks
end

return NPCOrderContinuityBridge
