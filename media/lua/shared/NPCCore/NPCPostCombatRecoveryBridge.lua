-- NPCPostCombatRecoveryBridge.lua
-- Stage 370: post-combat recovery, reload, loot integration and regroup discipline.
--
-- Advisory layer only. It does not change network commands, task names or save roots.
-- It coordinates existing Bandage/Reload/LootItems/Move tasks after combat so NPCs do
-- not remain in empty combat-idle, forget to reload, or scatter after looting.

NPCPostCombatRecoveryBridge = NPCPostCombatRecoveryBridge or {}
NPCPostCombatRecoveryBridge.VERSION = "2026-06-01-stage373-post-combat-recovery-order-continuity-1"

pcall(require, "NPCCore/NPCPostCombatLootBridge")
pcall(require, "NPCCore/NPCMovementStabilityBridge")
pcall(require, "NPCCore/NPCOrderContinuityBridge")

NPCPostCombatRecoveryBridge.Config = NPCPostCombatRecoveryBridge.Config or {
    enabled = true,
    recentCombatMs = 76000,
    contactQuietMs = 4600,
    recoveryThinkMs = 1800,
    urgentHealth = 0.36,
    bandageHealth = 0.58,
    reloadDelayMs = 900,
    regroupDelayMs = 2200,
    lootDelayMs = 5200,
    lootAfterManualMs = 1400,
    inspectCooldownMs = 7600,
    maxRegroupDistance = 7.5,
    followRecoverDistance = 4.6,
    companionAutoLoot = false
}

local function pcr_nowMs()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then
        local ok, hours = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok and hours then return math.floor((tonumber(hours) or 0) * 3600000) end
    end
    return 0
end

local function pcr_rand(n)
    n = tonumber(n) or 1
    if n <= 1 then return 0 end
    if ZombRand then return ZombRand(n) end
    return math.random(0, n - 1)
end

local function pcr_dist2(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return dx * dx + dy * dy
end

local function pcr_dist(x1, y1, x2, y2)
    return math.sqrt(pcr_dist2(x1, y1, x2, y2))
end

local function pcr_health01(chr)
    if not chr or not chr.getHealth then return 1 end
    local ok, value = pcall(function() return chr:getHealth() end)
    if not ok then return 1 end
    value = tonumber(value) or 1
    if value > 1 then value = value / 100 end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function pcr_living(brain)
    if not brain then return nil end
    brain.ai = brain.ai or {}
    brain.ai.living = brain.ai.living or {}
    return brain.ai.living
end

local function pcr_isPlayerControlled(brain)
    if not brain then return false end
    if brain.master ~= nil or brain.mercenaryHired == true or brain.hired == true or brain.isPlayerGuard == true then return true end
    local order = type(brain.order) == "table" and brain.order or nil
    if order and (order.source == "player" or order.playerId or order.master or order.followPlayer) then return true end
    return false
end

local function pcr_orderName(brain)
    if not brain then return nil end
    local order = brain.order or brain.directorOrder
    if type(order) == "table" then return tostring(order.name or order.orderName or order.action or order.type or order.mode or "") end
    if order ~= nil then return tostring(order) end
    return nil
end

local function pcr_normalizeOrder(order)
    order = tostring(order or ""):lower()
    if order == "follow" or order == "followme" or order == "follow_me" then return "follow" end
    if order == "guard" or order == "guardarea" or order == "guard_area" then return "guard" end
    if order == "hold" or order == "holdposition" or order == "hold_position" then return "hold" end
    if order == "loot" or order == "lootarea" or order == "loot_area" then return "loot" end
    return order
end

local function pcr_hasFreshMemory(brain, now)
    local focus = brain and brain.squadMemory and brain.squadMemory.focus or nil
    if focus and focus.at then
        local quiet = tonumber(NPCPostCombatRecoveryBridge.Config.contactQuietMs) or 4500
        local confidence = tonumber(focus.confidence) or 0
        if confidence >= 0.45 and now - (tonumber(focus.at) or 0) < quiet then return true end
    end
    local fsm = brain and brain.fsm or nil
    local last = fsm and fsm.lastKnownEnemyPosition or nil
    if last and last.updated and getGameTime then
        local ok, hours = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok and hours then
            local ageMs = math.max(0, (tonumber(hours) or 0) - (tonumber(last.updated) or 0)) * 3600000
            if ageMs < (tonumber(NPCPostCombatRecoveryBridge.Config.contactQuietMs) or 4500) then return true end
        end
    end
    return false
end

local function pcr_recentCombat(brain, living, now)
    if not brain then return false end
    now = now or pcr_nowMs()
    living = living or pcr_living(brain)
    local ttl = tonumber(NPCPostCombatRecoveryBridge.Config.recentCombatMs) or 76000
    if living and living.lastCombatMs and now - (tonumber(living.lastCombatMs) or 0) <= ttl then return true end
    if living and living.postCombatRecoveryLastThreatMs and now - (tonumber(living.postCombatRecoveryLastThreatMs) or 0) <= ttl then return true end
    local focus = brain.squadMemory and brain.squadMemory.focus or nil
    if focus and focus.at and now - (tonumber(focus.at) or 0) <= ttl then return true end
    return false
end

local function pcr_hasReloadableFirearm(brain, runtime)
    if runtime and runtime.hasReloadableFirearm then
        local ok, value = pcall(function() return runtime.hasReloadableFirearm(brain) end)
        if ok and value == true then return true end
    end
    if not (brain and brain.weapons) then return false end
    for _, slot in ipairs({"primary", "secondary"}) do
        local weapon = brain.weapons[slot]
        if weapon and weapon.name then
            local left = tonumber(weapon.bulletsLeft or 0) or 0
            local mags = tonumber(weapon.magCount or 0) or 0
            if left <= 0 and mags > 0 then return true end
        end
    end
    return false
end

local function pcr_hasLoadedFirearm(brain, runtime)
    if runtime and runtime.hasLoadedFirearm then
        local ok, value = pcall(function() return runtime.hasLoadedFirearm(brain) end)
        if ok and value == true then return true end
    end
    if not (brain and brain.weapons) then return false end
    for _, slot in ipairs({"primary", "secondary"}) do
        local weapon = brain.weapons[slot]
        if weapon and weapon.name and (tonumber(weapon.bulletsLeft or 0) or 0) > 0 then return true end
    end
    return false
end

local function pcr_masterPlayer(chr, brain, runtime)
    if runtime and runtime.masterPlayer then
        local ok, player = pcall(function() return runtime.masterPlayer(chr, brain) end)
        if ok and player then return player end
    end
    if brain and brain.master and getSpecificPlayer then
        local idx = tonumber(brain.master)
        if idx then
            local ok, player = pcall(function() return getSpecificPlayer(idx) end)
            if ok and player then return player end
        end
    end
    return nil
end

function NPCPostCombatRecoveryBridge.Update(chr, brain, threat, runtime)
    if NPCPostCombatRecoveryBridge.Config.enabled == false then return nil end
    if not (chr and brain) then return nil end
    local living = pcr_living(brain)
    local now = runtime and runtime.now and runtime.now() or pcr_nowMs()
    if threat and threat.x and threat.y then
        living.lastCombatMs = now
        living.postCombatRecoveryLastThreatMs = now
        living.postCombatRecoveryX = tonumber(threat.x)
        living.postCombatRecoveryY = tonumber(threat.y)
        living.postCombatRecoveryZ = tonumber(threat.z) or (chr.getZ and chr:getZ()) or 0
        living.postCombatRecoveryContactKind = tostring(threat.kind or threat.targetKind or "threat")
    end
    return living
end

function NPCPostCombatRecoveryBridge.ChooseState(chr, brain, threat, states, runtime)
    if NPCPostCombatRecoveryBridge.Config.enabled == false or not states then return nil end
    if threat then return nil end
    local living = pcr_living(brain)
    local now = runtime and runtime.now and runtime.now() or pcr_nowMs()
    if not pcr_recentCombat(brain, living, now) then return nil end

    local nextThink = tonumber(living.postCombatRecoveryNextThinkMs) or 0
    if now < nextThink then return nil end

    local health = pcr_health01(chr)
    if health <= (tonumber(NPCPostCombatRecoveryBridge.Config.urgentHealth) or 0.36) then
        return states.HealSelf, "post-combat urgent self aid"
    end
    if health <= (tonumber(NPCPostCombatRecoveryBridge.Config.bandageHealth) or 0.58) and now >= (tonumber(living.postCombatHealNextMs) or 0) then
        return states.HealSelf, "post-combat self aid"
    end

    if pcr_hasReloadableFirearm(brain, runtime) and now >= (tonumber(living.postCombatReloadNextMs) or 0) then
        return states.ReloadWeapon, "post-combat reload"
    end

    if pcr_hasFreshMemory(brain, now) then return nil end

    if NPCPostCombatLootBridge and NPCPostCombatLootBridge.PlanTasks and now >= (tonumber(living.postCombatLootGateMs) or 0) then
        local orderBlocksAmbientLoot = false
        if NPCOrderContinuityBridge and NPCOrderContinuityBridge.ShouldBlockAmbientLoot then
            local okBlock, blocked = pcall(function() return NPCOrderContinuityBridge.ShouldBlockAmbientLoot(chr, brain, nil, runtime) end)
            orderBlocksAmbientLoot = okBlock and blocked == true
        end
        local playerControlled = pcr_isPlayerControlled(brain)
        if not orderBlocksAmbientLoot and (not playerControlled or brain.allowCompanionPostCombatLoot == true or NPCPostCombatRecoveryBridge.Config.companionAutoLoot == true) then
            return states.LootArea, "post-combat gear check"
        end
    end

    local order = pcr_normalizeOrder(pcr_orderName(brain))
    if order == "follow" and pcr_isPlayerControlled(brain) then
        return states.FollowPlayer, "post-combat regroup with leader"
    elseif order == "guard" then
        return states.GuardArea, "post-combat resume guard"
    elseif order == "hold" then
        return states.HoldPosition, "post-combat hold sector"
    end

    return nil
end

local function pcr_markTasks(tasks, reason)
    if type(tasks) ~= "table" then return tasks end
    for _, task in ipairs(tasks) do
        if type(task) == "table" then
            task.postCombatRecovery = true
            task.director = task.director ~= false
            task.directorReason = task.directorReason or reason or "post-combat recovery"
            if task.action == "Move" or task.action == "GoTo" then
                task.recoveryMove = true
                task.closeSlow = task.closeSlow ~= false
                task.engineAssist = true
                task.smoothTurn = task.smoothTurn ~= false
            end
        end
    end
    return tasks
end

local function pcr_buildInspectTask(chr, brain, living, now)
    if not living or now < (tonumber(living.postCombatInspectNextMs) or 0) then return nil end
    living.postCombatInspectNextMs = now + (tonumber(NPCPostCombatRecoveryBridge.Config.inspectCooldownMs) or 7600) + pcr_rand(1200)
    local x = (living.postCombatRecoveryX or (chr and chr.getX and chr:getX()))
    local y = (living.postCombatRecoveryY or (chr and chr.getY and chr:getY()))
    local anims = {"AimRifleLow", "ShiftWeight", "WipeBrow"}
    local anim = anims[1 + pcr_rand(#anims)]
    return {{
        action = "Time",
        anim = anim,
        time = 72 + pcr_rand(45),
        director = true,
        livingIntent = true,
        postCombatRecovery = true,
        faceX = x,
        faceY = y,
        directorState = "LookAround",
        directorReason = "post-combat sector check"
    }}
end

local function pcr_buildRegroupTask(chr, brain, runtime, living, now)
    if not (chr and brain and runtime) then return nil end
    if now < (tonumber(living.postCombatRegroupNextMs) or 0) then return nil end
    local order = pcr_normalizeOrder(pcr_orderName(brain))
    if order ~= "follow" then return nil end
    local player = pcr_masterPlayer(chr, brain, runtime)
    if not (player and player.getX and player.getY) then return nil end
    local dist = pcr_dist(chr:getX(), chr:getY(), player:getX(), player:getY())
    local maxDist = tonumber(NPCPostCombatRecoveryBridge.Config.maxRegroupDistance) or 7.5
    if dist < maxDist then return nil end
    living.postCombatRegroupNextMs = now + (tonumber(NPCPostCombatRecoveryBridge.Config.regroupDelayMs) or 2200) + pcr_rand(700)
    local tx, ty, tz = player:getX(), player:getY(), player:getZ()
    if runtime.followFormationPoint then
        local ok, fx, fy, fz = pcall(function() return runtime.followFormationPoint(player, brain, chr) end)
        if ok and fx and fy then tx, ty, tz = fx, fy, fz or tz end
    end
    if runtime.moveToState then
        local task = runtime.moveToState(chr, "FollowPlayer", "post-combat regroup", tx, ty, tz, dist > 9 and "Run" or "Walk", true)
        return pcr_markTasks({task}, "post-combat regroup")
    end
    return pcr_markTasks({{action = "Move", x = tx, y = ty, z = tz, walkType = dist > 9 and "Run" or "Walk", arriveDist = tonumber(NPCPostCombatRecoveryBridge.Config.followRecoverDistance) or 4.6, director = true, directorState = "FollowPlayer", directorReason = "post-combat regroup"}}, "post-combat regroup")
end

function NPCPostCombatRecoveryBridge.PlanTasks(chr, brain, runtime, opts)
    if NPCPostCombatRecoveryBridge.Config.enabled == false then return nil end
    if not (chr and brain and runtime) then return nil end
    local threat = opts and opts.threat or nil
    if threat then return nil end

    local living = pcr_living(brain)
    local now = runtime.now and runtime.now() or pcr_nowMs()
    if not pcr_recentCombat(brain, living, now) then return nil end

    local interval = tonumber(NPCPostCombatRecoveryBridge.Config.recoveryThinkMs) or 1800
    if now < (tonumber(living.postCombatRecoveryNextThinkMs) or 0) then return nil end
    living.postCombatRecoveryNextThinkMs = now + interval + pcr_rand(700)

    local currentAction = runtime.currentAction and runtime.currentAction(chr) or nil
    if currentAction == "Shoot" or currentAction == "Aim" or currentAction == "Hit" or currentAction == "Shove" then return nil end

    local health = pcr_health01(chr)
    if health <= (tonumber(NPCPostCombatRecoveryBridge.Config.bandageHealth) or 0.58) and now >= (tonumber(living.postCombatHealNextMs) or 0) then
        living.postCombatHealNextMs = now + 9000 + pcr_rand(3000)
        if runtime.handleHealSelf then
            local tasks = runtime.handleHealSelf(chr, brain)
            if tasks and #tasks > 0 then return pcr_markTasks(tasks, "post-combat self aid") end
        end
        return pcr_markTasks({{action = "Bandage", time = 820, director = true, directorState = "HealSelf", directorReason = "post-combat self aid"}}, "post-combat self aid")
    end

    if pcr_hasReloadableFirearm(brain, runtime) and now >= (tonumber(living.postCombatReloadNextMs) or 0) then
        living.postCombatReloadNextMs = now + 5600 + pcr_rand(1800)
        if runtime.reloadTasks then
            local tasks = runtime.reloadTasks(chr, brain, "ReloadWeapon", "post-combat reload")
            if tasks and #tasks > 0 then return pcr_markTasks(tasks, "post-combat reload") end
        end
    end

    local regroup = pcr_buildRegroupTask(chr, brain, runtime, living, now)
    if regroup and #regroup > 0 then return regroup end

    if not pcr_hasFreshMemory(brain, now) and NPCPostCombatLootBridge and NPCPostCombatLootBridge.PlanTasks then
        local orderBlocksAmbientLoot = false
        if NPCOrderContinuityBridge and NPCOrderContinuityBridge.ShouldBlockAmbientLoot then
            local okBlock, blocked = pcall(function() return NPCOrderContinuityBridge.ShouldBlockAmbientLoot(chr, brain, nil, runtime) end)
            orderBlocksAmbientLoot = okBlock and blocked == true
        end
        local playerControlled = pcr_isPlayerControlled(brain)
        local allowLoot = (not orderBlocksAmbientLoot) and ((not playerControlled) or brain.allowCompanionPostCombatLoot == true or NPCPostCombatRecoveryBridge.Config.companionAutoLoot == true)
        if allowLoot and now >= (tonumber(living.postCombatLootGateMs) or 0) then
            if living.manualLootChangedAt and now - (tonumber(living.manualLootChangedAt) or 0) < (tonumber(NPCPostCombatRecoveryBridge.Config.lootAfterManualMs) or 1400) then
                living.postCombatLootGateMs = now + (tonumber(NPCPostCombatRecoveryBridge.Config.lootAfterManualMs) or 1400)
            else
                living.postCombatLootGateMs = now + (tonumber(NPCPostCombatRecoveryBridge.Config.lootDelayMs) or 5200) + pcr_rand(1400)
                local okLoot, lootTasks = pcall(function()
                    return NPCPostCombatLootBridge.PlanTasks(chr, brain, runtime, {state = "LootArea"})
                end)
                if okLoot and lootTasks and #lootTasks > 0 then return pcr_markTasks(lootTasks, "post-combat gear check") end
            end
        end
    end

    if not pcr_hasLoadedFirearm(brain, runtime) and not pcr_hasReloadableFirearm(brain, runtime) then
        local inspect = pcr_buildInspectTask(chr, brain, living, now)
        if inspect and #inspect > 0 then return inspect end
    end

    return nil
end

function NPCPostCombatRecoveryBridge.NotifyLootFinished(chr, brain, changed, task)
    local living = pcr_living(brain)
    if not living then return end
    local now = pcr_nowMs()
    living.postCombatRecoveryNextThinkMs = now + 450 + pcr_rand(400)
    if changed then
        living.postCombatRecoveryLootChangedAt = now
        living.postCombatReloadNextMs = now + (tonumber(NPCPostCombatRecoveryBridge.Config.reloadDelayMs) or 900)
        living.postCombatRegroupNextMs = now + (tonumber(NPCPostCombatRecoveryBridge.Config.regroupDelayMs) or 2200)
    end
    if task and task.manualSupplyLoot then living.manualLootChangedAt = changed and now or living.manualLootChangedAt end
end

return NPCPostCombatRecoveryBridge
