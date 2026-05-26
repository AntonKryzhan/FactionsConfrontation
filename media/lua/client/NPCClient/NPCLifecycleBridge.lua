-- NPCLifecycleBridge.lua
-- Neutral client bridge for the legacy legacy lifecycle client module.

-- Lightweight persistent simulation layer for legacy item module.
-- It tracks stable state/order/watchdog information without replacing existing AI programs.

require "NPCCore/NPCLegacyGlobalsBridge"
NPCLifecycleBridge = NPCLifecycleBridge or {}

NPCLifecycleBridge.Enabled = true
NPCLifecycleBridge.UpdateIntervalMs = 3000
NPCLifecycleBridge.SendIntervalMs = 10000
NPCLifecycleBridge.HeavyPayloadIntervalMs = 30000
NPCLifecycleBridge.MaxStateUpdatesPerRun = 18
NPCLifecycleBridge.MoveEpsilon = 0.25
NPCLifecycleBridge.StuckTicksThreshold = 5

NPCLifecycleBridge._lastUpdate = NPCLifecycleBridge._lastUpdate or 0
NPCLifecycleBridge._runtime = NPCLifecycleBridge._runtime or {}
NPCLifecycleBridge._lastSent = NPCLifecycleBridge._lastSent or {}

local function banditLifecycleSafeCall(defaultValue, fn)
    local ok, result = pcall(fn)
    if ok then return result end
    return defaultValue
end

local function banditLifecycleGetHealth(zombie, brain)
    local health = banditLifecycleSafeCall(nil, function()
        if zombie and zombie.getHealth then
            return zombie:getHealth()
        end
        return nil
    end)

    if health then return health end
    return brain and brain.health or nil
end

local function banditLifecycleHasTarget(zombie)
    return banditLifecycleSafeCall(false, function()
        if zombie and zombie.getTarget then
            return zombie:getTarget() ~= nil
        end
        return false
    end)
end

local function banditLifecycleIsDead(zombie)
    return banditLifecycleSafeCall(false, function()
        if zombie and zombie.isDead then
            return zombie:isDead()
        end
        return false
    end)
end

local function banditLifecycleProgramName(brain)
    if brain and brain.program and brain.program.name then
        return brain.program.name
    end
    return nil
end

local function banditLifecycleProgramStage(brain)
    if brain and brain.program and brain.program.stage then
        return brain.program.stage
    end
    return nil
end

function NPCLifecycleBridge.ResolveState(zombie, brain, moved)
    if banditLifecycleIsDead(zombie) then
        return "Dead"
    end

    if brain then
        if brain.sleeping then return "Sleeping" end
        if brain.aiming or banditLifecycleHasTarget(zombie) then return "Combat" end
        if brain.moving or moved then return "Moving" end
        if brain.stationary then return "Stationary" end

        local programName = banditLifecycleProgramName(brain)
        local programStage = banditLifecycleProgramStage(brain)
        if programName and programStage then
            return tostring(programName) .. ":" .. tostring(programStage)
        elseif programName then
            return tostring(programName)
        end
    end

    return "Idle"
end

function NPCLifecycleBridge.Update()
    if not NPCLifecycleBridge.Enabled then return end
    if isServer and isServer() then return end
    if not (NPCZombieCacheBridge and NPCZombieCacheBridge.CacheLightB) then return end

    local player = getSpecificPlayer and getSpecificPlayer(0) or getPlayer()
    if not player then return end

    local now = getTimeInMillis()
    if now - NPCLifecycleBridge._lastUpdate < NPCLifecycleBridge.UpdateIntervalMs then return end
    NPCLifecycleBridge._lastUpdate = now

    local gmd = GetNPCModData and GetNPCModData() or nil
    local sentThisRun = 0
    local maxSends = tonumber(NPCLifecycleBridge.MaxStateUpdatesPerRun) or 18
    local heavyInterval = tonumber(NPCLifecycleBridge.HeavyPayloadIntervalMs) or 30000
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        maxSends = NPCLegacySettingsBridge.GetNumber("Net_LifecycleStateUpdatesPerRun", maxSends, 1, 500)
        heavyInterval = NPCLegacySettingsBridge.GetNumber("Net_LifecycleHeavyPayloadSeconds", heavyInterval / 1000, 5, 600) * 1000
    end
    if NPCIdentityBridge and NPCIdentityBridge.EnsureGlobalData then
        NPCIdentityBridge.EnsureGlobalData(gmd)
    end

    for id, light in pairs(NPCZombieCacheBridge.CacheLightB) do
        if light and light.x and light.y then
            local zombie = NPCZombieCacheBridge.Cache and NPCZombieCacheBridge.Cache[id] or nil
            local brain = light.brain
            if not brain and zombie and NPCBrainData then
                brain = NPCBrainData.Get(zombie)
            end

            if brain then
                if NPCIdentityBridge and NPCIdentityBridge.EnsureBrain then
                    brain = NPCIdentityBridge.EnsureBrain(brain, gmd, id, false)
                end

                local runtime = NPCLifecycleBridge._runtime[id] or {}
                local dx = runtime.x and math.abs(light.x - runtime.x) or 999
                local dy = runtime.y and math.abs(light.y - runtime.y) or 999
                local moved = dx > NPCLifecycleBridge.MoveEpsilon or dy > NPCLifecycleBridge.MoveEpsilon

                if moved then
                    runtime.stuckTicks = 0
                    runtime.lastMove = now
                else
                    runtime.stuckTicks = (runtime.stuckTicks or 0) + 1
                end

                runtime.x = light.x
                runtime.y = light.y
                runtime.z = light.z or 0

                if NPCOrderContract and NPCOrderContract.Ensure then
                    NPCOrderContract.Ensure(brain)
                end

                local state = NPCLifecycleBridge.ResolveState(zombie, brain, moved)
                local order = brain.order and brain.order.name or brain.sim and brain.sim.order or "Auto"
                local fireMode = brain.order and brain.order.fireMode or brain.sim and brain.sim.fireMode or "FireAtWill"
                local stuck = false
                if state == "Moving" and runtime.stuckTicks >= NPCLifecycleBridge.StuckTicksThreshold then
                    stuck = true
                end

                if not brain.sim then brain.sim = {} end
                brain.sim.state = state
                brain.sim.order = order
                brain.sim.fireMode = fireMode
                brain.sim.programName = banditLifecycleProgramName(brain)
                brain.sim.programStage = banditLifecycleProgramStage(brain)
                brain.sim.updated = NPCIdentityBridge and NPCIdentityBridge.GetWorldAgeHours and NPCIdentityBridge.GetWorldAgeHours() or 0

                if not brain.watchdog then brain.watchdog = {} end
                brain.watchdog.stuck = stuck
                brain.watchdog.stuckTicks = runtime.stuckTicks or 0
                brain.watchdog.lastMove = runtime.lastMove or now

                if not brain.debug then brain.debug = {} end
                brain.debug.state = state
                brain.debug.order = order
                brain.debug.fireMode = fireMode
                brain.debug.watchdog = stuck

                brain.debugCoords = {x=light.x, y=light.y, z=light.z or 0}
                brain.debugUpdated = brain.sim.updated

                if zombie and NPCBrainData then
                    NPCBrainData.Update(zombie, brain)
                end

                if gmd and gmd.Queue and gmd.Queue[id] then
                    gmd.Queue[id] = brain
                end

                if NPCIdentityBridge and NPCIdentityBridge.TouchRegistry then
                    NPCIdentityBridge.TouchRegistry(gmd, brain)
                end

                NPCLifecycleBridge._runtime[id] = runtime

                local lastSent = NPCLifecycleBridge._lastSent[id]
                local shouldSend = false
                if not lastSent then
                    shouldSend = true
                elseif now - lastSent.t >= NPCLifecycleBridge.SendIntervalMs then
                    shouldSend = true
                elseif lastSent.state ~= state or lastSent.order ~= order or lastSent.fireMode ~= fireMode or lastSent.stuck ~= stuck then
                    shouldSend = true
                end

                if shouldSend and sentThisRun < maxSends then
                    local heavySync = not lastSent or now - (tonumber(lastSent.heavyT) or 0) >= heavyInterval or lastSent.order ~= order or lastSent.fireMode ~= fireMode
                    NPCLifecycleBridge._lastSent[id] = {t=now, heavyT=heavySync and now or (lastSent and lastSent.heavyT or 0), state=state, order=order, fireMode=fireMode, stuck=stuck}
                    sentThisRun = sentThisRun + 1

                    local payload = {
                        id=id,
                        uid=brain.uid,
                        persistentId=brain.persistentId,
                        x=light.x,
                        y=light.y,
                        z=light.z or 0,
                        health=banditLifecycleGetHealth(zombie, brain),
                        maxHealth=brain.maxHealth,
                        state=state,
                        reason=brain.reason,
                        order=order,
                        fireMode=fireMode,
                        factionSide=brain.factionSide,
                        faction=brain.faction,
                        factionState=brain.factionState,
                        factionReason=brain.factionReason,
                        factionShoot=brain.factionShoot,
                        programName=banditLifecycleProgramName(brain),
                        programStage=banditLifecycleProgramStage(brain),
                        worldGroupId=brain.worldGroupId,
                        groupId=brain.groupId,
                        stuck=stuck,
                        stuckTicks=runtime.stuckTicks or 0,
                        lastMove=runtime.lastMove or now
                    }

                    if heavySync then
                        payload.currentTask = brain.tasks and brain.tasks[1] or nil
                        payload.lastTask = brain.lastTask
                        payload.weapons = brain.weapons
                        payload.inventory = brain.inventory
                        payload.loot = brain.loot
                        payload.homeBase = brain.homeBase
                        payload.homeBaseId = brain.homeBaseId
                        payload.fsm = brain.fsm

                        if NPCPersistentNPCBridge and NPCPersistentNPCBridge.BuildRuntimeUpdate and (not NPCWorkSchedulerBridge or not NPCWorkSchedulerBridge.AllowPersistent or NPCWorkSchedulerBridge.AllowPersistent(brain.uid or brain.persistentId or id)) then
                            local extra = NPCPersistentNPCBridge.BuildRuntimeUpdate(zombie, brain)
                            if type(extra) == "table" then
                                for k, v in pairs(extra) do
                                    payload[k] = v
                                end
                            end
                        end
                    end

                    sendClientCommand(player, 'NPCSim', 'StateUpdate', payload)
                end
            end
        end
    end
end

Events.OnTick.Add(NPCLifecycleBridge.Update)

NPCLegacyGlobalsBridge.InstallAlias("Lifecycle", NPCLifecycleBridge, "NPCLifecycleBridge")
