-- Neutral client command bridge.
-- Compatibility facade: media/lua/client/legacy server-command facade

NPCClientCommandBridge = NPCClientCommandBridge or {}
NPCClientCommandBridge.Version = 1

require "NPCCore/NPCLegacyContractBridge"

local NPC_LEGACY_KEYS = NPCLegacyContractBridge.Keys

ZSClient = ZSClient or {}
ZSClient.Commands = ZSClient.Commands or {}
ZSClient.NPCCommands = ZSClient.Commands

function NPCClientCommandBridge.NormalizeModule(module)
    if module == "NPCCommands" then return "Commands" end
    if module == "NPCPlayers" then return "Players" end
    if module == "NPCSim" then return NPCLegacyContractBridge.Modules.sim end
    return module
end

local function npcclient_nowMs()
    if getTimestampMs then
        local ok, value = pcall(function() return getTimestampMs() end)
        if ok and value then return tonumber(value) or 0 end
    end
    if getGameTime then
        local ok, value = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok and value then return math.floor((tonumber(value) or 0) * 3600000) end
    end
    return 0
end

local function npcclient_mercTelemetryText(args, nowMs)
    if type(args) ~= "table" then return "" end
    local parts = {}
    if args.clientTraceId ~= nil then parts[#parts + 1] = "trace=" .. tostring(args.clientTraceId) end
    if args.clientEvent ~= nil then parts[#parts + 1] = "event=" .. tostring(args.clientEvent) end
    if args.orderRevision ~= nil or args.groupOrderRevision ~= nil then parts[#parts + 1] = "revision=" .. tostring(args.orderRevision or args.groupOrderRevision) end
    local clientSendMs = tonumber(args.clientSendMs)
    local serverReceiveMs = tonumber(args.serverReceiveMs)
    local orderAcceptedMs = tonumber(args.orderAcceptedMs)
    local serverFlushMs = tonumber(args.serverFlushMs)
    local now = tonumber(nowMs) or npcclient_nowMs()
    if clientSendMs and now > 0 then parts[#parts + 1] = "clientTotalMs=" .. tostring(math.floor(now - clientSendMs)) end
    if clientSendMs and serverReceiveMs then parts[#parts + 1] = "clientToServerMs=" .. tostring(math.floor(serverReceiveMs - clientSendMs)) end
    if serverReceiveMs and orderAcceptedMs then parts[#parts + 1] = "serverAcceptMs=" .. tostring(math.floor(orderAcceptedMs - serverReceiveMs)) end
    if orderAcceptedMs and serverFlushMs then parts[#parts + 1] = "serverFlushMs=" .. tostring(math.floor(serverFlushMs - orderAcceptedMs)) end
    if #parts == 0 then return "" end
    return " " .. table.concat(parts, " ")
end

function NPCClientCommandBridge.UpdateVehicle(args)
    for i=0, 100 do
        local vehicleList = getCell():getVehicles()
        for i=0, vehicleList:size()-1 do
            local vehicle = vehicleList:get(i)
            if vehicle and vehicle:getId() == args.id then
                if vehicle:hasLightbar() then 
                    if args.lightbar then
                        vehicle:setLightbarLightsMode(args.lightbar)
                    end
                    if args.siren then
                        vehicle:setLightbarSirenMode(args.siren)
                    end
                end 
                
                if args.alarm then
                    vehicle:setAlarmed(true)
                    vehicle:triggerAlarm()
                end
                return
            end
        end
    end
end

local function npcclient_nonEmptyId(value)
    if value == nil then return nil end
    local sid = tostring(value)
    if sid == "" or sid == "nil" or sid == "false" then return nil end
    return sid
end

local function npcclient_addIdCandidate(list, seen, value)
    local sid = npcclient_nonEmptyId(value)
    if not sid or seen[sid] then return end
    seen[sid] = true
    list[#list + 1] = sid
end

local function npcclient_idCandidatesFromPayload(args)
    local list = {}
    local seen = {}
    if type(args) == "table" then
        npcclient_addIdCandidate(list, seen, args.id)
        npcclient_addIdCandidate(list, seen, args.runtimeId)
        npcclient_addIdCandidate(list, seen, args.brainId)
        npcclient_addIdCandidate(list, seen, args.uid)
        npcclient_addIdCandidate(list, seen, args.persistentId)
        npcclient_addIdCandidate(list, seen, args.zombieId)
        if NPC_LEGACY_KEYS then
            npcclient_addIdCandidate(list, seen, args[NPC_LEGACY_KEYS.runtimeId])
            npcclient_addIdCandidate(list, seen, args[NPC_LEGACY_KEYS.RUNTIME_ID])
            npcclient_addIdCandidate(list, seen, args[NPC_LEGACY_KEYS.persistentId])
            npcclient_addIdCandidate(list, seen, args[NPC_LEGACY_KEYS.PERSISTENT_ID])
        end
    else
        npcclient_addIdCandidate(list, seen, args)
    end
    return list, seen
end

local function npcclient_brainMatchesIdSet(brain, fallbackId, ids, idSet)
    if type(brain) ~= "table" then return false end
    local values = {
        fallbackId,
        brain.id,
        brain.runtimeId,
        brain.uid,
        brain.persistentId
    }
    if NPC_LEGACY_KEYS then
        values[#values + 1] = brain[NPC_LEGACY_KEYS.runtimeId]
        values[#values + 1] = brain[NPC_LEGACY_KEYS.RUNTIME_ID]
        values[#values + 1] = brain[NPC_LEGACY_KEYS.persistentId]
        values[#values + 1] = brain[NPC_LEGACY_KEYS.PERSISTENT_ID]
    end
    for _, value in ipairs(values) do
        local sid = npcclient_nonEmptyId(value)
        if sid and idSet and idSet[sid] then return true end
    end
    return false
end

local function npcclient_groupMatchesPayload(brain, args)
    if type(brain) ~= "table" or type(args) ~= "table" then return false end
    local groupId = args.groupId or args.worldGroupId
    if not groupId and NPC_LEGACY_KEYS then
        groupId = args[NPC_LEGACY_KEYS.worldGroupId] or args[NPC_LEGACY_KEYS.WORLD_GROUP_ID]
    end
    local brainGroup = brain.worldGroupId or brain.groupId
    if not brainGroup and NPC_LEGACY_KEYS then
        brainGroup = brain[NPC_LEGACY_KEYS.worldGroupId] or brain[NPC_LEGACY_KEYS.WORLD_GROUP_ID]
    end
    if groupId and brainGroup and tostring(groupId) == tostring(brainGroup) then return true end
    return false
end

local function npcclient_positionMatchesPayload(candidate, args)
    if not (candidate and type(args) == "table" and args.x and args.y and candidate.getX and candidate.getY) then return false end
    local zx = tonumber(candidate:getX())
    local zy = tonumber(candidate:getY())
    local zz = candidate.getZ and tonumber(candidate:getZ()) or 0
    local x = tonumber(args.x)
    local y = tonumber(args.y)
    local z = tonumber(args.z)
    if not (zx and zy and x and y) then return false end
    if z ~= nil and math.abs((z or 0) - (zz or 0)) > 1.0 then return false end
    local dx = zx - x
    local dy = zy - y
    return (dx * dx + dy * dy) <= 49
end

local function npcclient_getNPCByPayload(args)
    if not (NPCZombieCacheBridge and NPCZombieCacheBridge.Cache) then return nil end

    local ids, idSet = npcclient_idCandidatesFromPayload(args)
    for _, id in ipairs(ids) do
        local bandit = NPCZombieCacheBridge.Cache[id] or NPCZombieCacheBridge.Cache[tostring(id)]
        if bandit then return bandit end

        local nid = tonumber(id)
        if nid and NPCZombieCacheBridge.Cache[nid] then return NPCZombieCacheBridge.Cache[nid] end
    end

    for cacheId, candidate in pairs(NPCZombieCacheBridge.Cache) do
        local brain = candidate and NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(candidate) or nil
        if npcclient_brainMatchesIdSet(brain, cacheId, ids, idSet) then
            return candidate
        end
    end

    for _, candidate in pairs(NPCZombieCacheBridge.Cache) do
        local brain = candidate and NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(candidate) or nil
        if npcclient_groupMatchesPayload(brain, args) and npcclient_positionMatchesPayload(candidate, args) then
            return candidate
        end
    end

    return nil
end

local function npcclient_getNPCById(id)
    return npcclient_getNPCByPayload({id = id})
end

local function npcclient_mergeQueuedBrain(gmd, id, args)
    if not (gmd and gmd.Queue and id and type(args) == "table") then return end

    local key = id
    if not gmd.Queue[key] and gmd.Queue[tostring(id)] then key = tostring(id) end
    local nid = tonumber(id)
    if not gmd.Queue[key] and nid and gmd.Queue[nid] then key = nid end

    if not gmd.Queue[key] then
        for qid, brain in pairs(gmd.Queue) do
            if brain and (tostring(brain.id or qid) == tostring(id) or tostring(brain.uid or "") == tostring(id) or tostring(brain.persistentId or "") == tostring(id)) then
                key = qid
                break
            end
        end
    end

    if not gmd.Queue[key] then gmd.Queue[key] = {id=id} end
    for k, v in pairs(args) do
        if k ~= "id" then gmd.Queue[key][k] = v end
    end
end

local function npcclient_worldAgeHours()
    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then
            local ok, value = pcall(function() return gt:getWorldAgeHours() end)
            if ok and tonumber(value) then return tonumber(value) end
        end
    end
    return 0
end

local function npcclient_isOrderInterruptActive(args, brain)
    local order = nil
    if type(args) == "table" and type(args.order) == "table" then order = args.order end
    if not order and type(brain) == "table" and type(brain.order) == "table" then order = brain.order end
    if type(order) ~= "table" then return false end
    local untilHour = tonumber(order.interruptUntil or order.forceUntil)
    if untilHour and untilHour > npcclient_worldAgeHours() then return true end
    if order.interrupt == true then
        local issued = tonumber(order.interruptIssued or order.issued)
        local now = npcclient_worldAgeHours()
        if issued and now >= issued and now - issued < (8 / 3600) then return true end
    end
    return false
end

local function npcclient_isCombatAction(action)
    action = tostring(action or "")
    return action == "Shoot" or action == "Aim" or action == "Hit" or action == "Shove" or action == "Reload" or action == "FaceTarget"
end

local function npcclient_orderToken(args, brain)
    local order = type(args) == "table" and type(args.order) == "table" and args.order or (type(brain) == "table" and brain.order or nil)
    local revision = tonumber((type(args) == "table" and (args.orderRevision or args.groupOrderRevision or args.mercenaryOrderRevision)) or (type(brain) == "table" and (brain.orderRevision or brain.groupOrderRevision or brain.mercenaryOrderRevision)) or (order and (order.orderRevision or order.groupOrderRevision)))
    if revision then return "r:" .. tostring(revision) end
    local sequence = tonumber(order and order.sequence) or tonumber(args and args.orderSequence) or tonumber(args and args.sequence)
    if sequence then return "s:" .. tostring(sequence) end
    local issued = tonumber(order and (order.interruptIssued or order.issued)) or 0
    return "i:" .. tostring(issued)
end

local function npcclient_queueImmediateMercenaryOrderTask(bandit, brain, args, source)
    if not (bandit and type(brain) == "table" and brain.mercenaryHired == true) then return false end
    local order = type(args) == "table" and type(args.order) == "table" and args.order or brain.order
    if type(order) ~= "table" then return false end
    if order.source ~= "player" and order.commandAuthority ~= "player" and order.playerCommand ~= true and brain.commandAuthority ~= "player" then return false end
    if not (NPCUpdateBridge and NPCUpdateBridge.QueueImmediateMercenaryOrderTask and NPCUpdateBridge.EnqueueGeneratedTasks) then return false end

    brain.ai = brain.ai or {}
    local token = npcclient_orderToken(args, brain)
    local nowMs = getTimestampMs and getTimestampMs() or 0
    if token and brain.ai.clientMercenaryImmediateToken == token and nowMs > 0 and (nowMs - (tonumber(brain.ai.clientMercenaryImmediateAtMs) or 0)) < 220 then
        return true
    end

    local tasks = {}
    local okQueued, queued = pcall(function() return NPCUpdateBridge.QueueImmediateMercenaryOrderTask(bandit, brain, order, tasks) end)
    if okQueued and queued == true and #tasks > 0 then
        local okEnqueue = pcall(function() NPCUpdateBridge.EnqueueGeneratedTasks(bandit, brain, tasks, source or "client_order_dispatch") end)
        if okEnqueue then
            if args and (args.clientTraceId ~= nil or args.serverReceiveMs ~= nil) then
                print("[NPCMercenaryTelemetry] client immediate task queued source=" .. tostring(source or "client_order_dispatch") .. " id=" .. tostring(args.id) .. " order=" .. tostring(order and order.name) .. npcclient_mercTelemetryText(args, nowMs))
            end
            brain.ai.clientMercenaryImmediateToken = token
            brain.ai.clientMercenaryImmediateAtMs = nowMs
            brain.ai.forceManualOrderNow = false
            if NPCBrainData and NPCBrainData.Update then pcall(function() NPCBrainData.Update(bandit, brain) end) end
            return true
        end
    end
    return false
end

local function npcclient_interruptMercenaryOrder(bandit, brain, args, previousTask)
    if not (bandit and type(brain) == "table") then return end
    if brain.mercenaryHired ~= true then return end
    if not npcclient_isOrderInterruptActive(args, brain) then return end

    brain.ai = brain.ai or {}
    local order = type(args) == "table" and type(args.order) == "table" and args.order or brain.order
    local revision = tonumber((type(args) == "table" and (args.orderRevision or args.groupOrderRevision or args.mercenaryOrderRevision)) or (order and (order.orderRevision or order.groupOrderRevision)) or brain.orderRevision or brain.groupOrderRevision or brain.mercenaryOrderRevision)
    local sequence = tonumber(order and order.sequence) or tonumber(args and args.orderSequence) or tonumber(args and args.sequence)
    local issued = tonumber(order and (order.interruptIssued or order.issued)) or 0
    local token = revision and ("r:" .. tostring(revision)) or (sequence and ("s:" .. tostring(sequence)) or ("i:" .. tostring(issued)))
    local nowMs = getTimestampMs and getTimestampMs() or 0
    if brain.ai.clientMercenaryInterruptToken == token and nowMs > 0 and (nowMs - (tonumber(brain.ai.clientMercenaryInterruptAtMs) or 0)) < 1800 then
        brain.ai.forceManualOrderNow = true
        return
    end
    brain.ai.clientMercenaryInterruptToken = token
    brain.ai.clientMercenaryInterruptAtMs = nowMs

    local currentTask = previousTask or (brain.tasks and brain.tasks[1]) or nil
    if currentTask and (currentTask.action == "Die" or currentTask.action == "Zombify") then
        if type(brain.tasks) ~= "table" or #brain.tasks == 0 then brain.tasks = {currentTask} end
        return
    end

    local clearCombat = args == nil or args.clearCombat ~= false
    local name = tostring(order and order.name or "")
    local lightMoveOrder = name == "Follow" or name == "Patrol" or name == "Return"

    if NPCEntity and NPCEntity.ClearTasks then pcall(function() NPCEntity.ClearTasks(bandit) end) end
    brain.tasks = {}
    brain.ai.forceManualOrderNow = true
    brain.ai.manualOrderConsumedIssued = nil
    brain.ai.manualOrderConsumedSequence = nil
    brain.ai.manualOrderConsumedRevision = nil
    brain.ai.lastGenerateTaskFrameTick = nil

    if clearCombat then
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
        if bandit.setTarget then pcall(function() bandit:setTarget(nil) end) end
        if bandit.setAttackedBy then pcall(function() bandit:setAttackedBy(nil) end) end
        if not lightMoveOrder and bandit.clearAggroList then pcall(function() bandit:clearAggroList() end) end
    end

    if NPCEntity and NPCEntity.SetAim then pcall(function() NPCEntity.SetAim(bandit, false) end) end
    if NPCEntity and NPCEntity.SetMoving then pcall(function() NPCEntity.SetMoving(bandit, false) end) end
    if bandit.setBumpDone then pcall(function() bandit:setBumpDone(true) end) end
    -- Do not force ZombieIdleState here.  A hard state swap on every squad
    -- order was visible as a micro-swap and also increased B41 path2 churn.
end

local function npcclient_applyNPCPart(args, options)
    if type(args) ~= "table" then return nil, nil end
    options = options or {}
    local ids = npcclient_idCandidatesFromPayload(args)
    local id = args.id or ids[1]
    if id then
        local bandit = npcclient_getNPCByPayload(args)

        -- update now, or if not loaded update gmd so it gets right when loaded later
        if bandit then
            local brain = NPCBrainData.Get(bandit)
            if brain then
                local previousTask = brain.tasks and brain.tasks[1] or nil
                for k, v in pairs(args) do
                    if k ~= "id" then
                        brain[k] = v
                    end
                end
                npcclient_interruptMercenaryOrder(bandit, brain, args, previousTask)
                if options.deferImmediate ~= true then
                    npcclient_queueImmediateMercenaryOrderTask(bandit, brain, args, "client_order_dispatch")
                end
                NPCBrainData.Update(bandit, brain)
                return bandit, brain
            end
        else
            local gmd = GetNPCModData()
            npcclient_mergeQueuedBrain(gmd, id, args)
        end
    end
    return nil, nil
end

local function npcclient_orderQueue()
    if not ZSClient.MercenaryOrderQueue then ZSClient.MercenaryOrderQueue = {} end
    if not ZSClient.MercenaryOrderQueueById then ZSClient.MercenaryOrderQueueById = {} end
    return ZSClient.MercenaryOrderQueue, ZSClient.MercenaryOrderQueueById
end

local function npcclient_queueMercenaryOrderPart(args)
    if type(args) ~= "table" or args.id == nil then return end
    local queue, byId = npcclient_orderQueue()
    local key = tostring(args.id)
    local idx = byId[key]
    if idx and queue[idx] then
        queue[idx] = args
    else
        queue[#queue + 1] = args
        byId[key] = #queue
    end
end

function NPCClientCommandBridge.UpdateNPCPart(args)
    if type(args) == "table" and args.mercenaryOrderAsync == true and args.urgentMercenaryOrder ~= true then
        npcclient_queueMercenaryOrderPart(args)
        return
    end
    npcclient_applyNPCPart(args)
end

local function npcclient_applyMercenaryDirectOrderPart(args, options)
    if type(args) ~= "table" then return nil, nil end
    options = options or {}
    args.directMercenaryOrder = true
    args.orderSystem = "mercenary_direct"
    if type(args.order) == "table" then
        args.order.source = "mercenary_direct"
        args.order.commandAuthority = "player"
        args.order.playerCommand = true
        args.order.playerCommandMode = "mercenary_direct"
        args.order.mercenaryDirect = true
        args.order.directMercenaryOrder = true
        args.order.dispatchMode = "mercenary_direct"
        args.order.forceImmediate = true
    end

    local ids = npcclient_idCandidatesFromPayload(args)
    local id = args.id or ids[1]
    if not id then return nil, nil end

    local bandit = npcclient_getNPCByPayload(args)
    if not bandit then
        local gmd = GetNPCModData()
        npcclient_mergeQueuedBrain(gmd, id, args)
        return nil, nil
    end

    local brain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(bandit) or nil
    if type(brain) ~= "table" then return nil, nil end
    local previousTask = brain.tasks and brain.tasks[1] or nil
    for k, v in pairs(args) do
        if k ~= "id" then brain[k] = v end
    end
    brain.mercenaryDirectOrders = true
    brain.orderSystem = "mercenary_direct"
    brain.commandAuthority = "player"
    brain.playerCommandAuthority = true
    if type(brain.order) == "table" then
        brain.order.source = "mercenary_direct"
        brain.order.commandAuthority = "player"
        brain.order.playerCommand = true
        brain.order.playerCommandMode = "mercenary_direct"
        brain.order.mercenaryDirect = true
        brain.order.directMercenaryOrder = true
        brain.order.dispatchMode = "mercenary_direct"
        brain.order.forceImmediate = true
    end

    if NPCUpdateBridge and NPCUpdateBridge.ApplyMercenaryFireModeEquipment and type(brain.order) == "table" then
        pcall(function() NPCUpdateBridge.ApplyMercenaryFireModeEquipment(bandit, brain, brain.order) end)
    end

    npcclient_interruptMercenaryOrder(bandit, brain, args, previousTask)
    if options.deferImmediate ~= true then
        npcclient_queueImmediateMercenaryOrderTask(bandit, brain, args, "mercenary_direct_order")
    end
    NPCBrainData.Update(bandit, brain)
    return bandit, brain
end

function NPCClientCommandBridge.MercenaryDirectOrderBatch(args)
    if type(args) ~= "table" or type(args.entries) ~= "table" then return end
    local receivedMs = npcclient_nowMs()
    if args.clientTraceId ~= nil or args.serverReceiveMs ~= nil then
        print("[NPCMercenaryTelemetry] client batch received entries=" .. tostring(#args.entries) .. npcclient_mercTelemetryText(args, receivedMs))
    end
    local immediate = {}
    for _, entry in ipairs(args.entries) do
        if type(entry) == "table" then
            if args.applyTogether == true then entry.applyTogether = true end
            if args.orderRevision and not entry.orderRevision then entry.orderRevision = args.orderRevision end
            if args.groupOrderRevision and not entry.groupOrderRevision then entry.groupOrderRevision = args.groupOrderRevision end
            if args.orderBatchId and not entry.orderBatchId then entry.orderBatchId = args.orderBatchId end
            if args.groupOrderBatchId and not entry.groupOrderBatchId then entry.groupOrderBatchId = args.groupOrderBatchId end
            if args.clientTraceId and not entry.clientTraceId then entry.clientTraceId = args.clientTraceId end
            if args.clientSendMs and not entry.clientSendMs then entry.clientSendMs = args.clientSendMs end
            if args.clientOrderSeq and not entry.clientOrderSeq then entry.clientOrderSeq = args.clientOrderSeq end
            if args.clientEvent and not entry.clientEvent then entry.clientEvent = args.clientEvent end
            if args.serverReceiveMs and not entry.serverReceiveMs then entry.serverReceiveMs = args.serverReceiveMs end
            if args.orderAcceptedMs and not entry.orderAcceptedMs then entry.orderAcceptedMs = args.orderAcceptedMs end
            if args.serverFlushMs and not entry.serverFlushMs then entry.serverFlushMs = args.serverFlushMs end
            entry.urgentMercenaryOrder = true
            entry.mercenaryOrderAsync = false
            entry.forceImmediateOrder = true
            entry.directMercenaryOrder = true
            entry.orderSystem = "mercenary_direct"
            local bandit, brain = npcclient_applyMercenaryDirectOrderPart(entry, {deferImmediate=true})
            if bandit and brain then immediate[#immediate + 1] = {bandit=bandit, brain=brain, args=entry} end
        end
    end
    for _, item in ipairs(immediate) do
        npcclient_queueImmediateMercenaryOrderTask(item.bandit, item.brain, item.args, "mercenary_direct_order_batch")
    end
end

function NPCClientCommandBridge.MercenaryOrderBatch(args)
    if type(args) == "table" and (args.directMercenaryOrder == true or args.orderSystem == "mercenary_direct") then
        return NPCClientCommandBridge.MercenaryDirectOrderBatch(args)
    end
    if type(args) ~= "table" or type(args.entries) ~= "table" then return end
    local immediate = {}
    for _, entry in ipairs(args.entries) do
        if type(entry) == "table" then
            if args.applyTogether == true then entry.applyTogether = true end
            if args.orderRevision and not entry.orderRevision then entry.orderRevision = args.orderRevision end
            if args.groupOrderRevision and not entry.groupOrderRevision then entry.groupOrderRevision = args.groupOrderRevision end
            if args.orderBatchId and not entry.orderBatchId then entry.orderBatchId = args.orderBatchId end
            if args.groupOrderBatchId and not entry.groupOrderBatchId then entry.groupOrderBatchId = args.groupOrderBatchId end
            if args.clientTraceId and not entry.clientTraceId then entry.clientTraceId = args.clientTraceId end
            if args.clientSendMs and not entry.clientSendMs then entry.clientSendMs = args.clientSendMs end
            if args.clientOrderSeq and not entry.clientOrderSeq then entry.clientOrderSeq = args.clientOrderSeq end
            if args.clientEvent and not entry.clientEvent then entry.clientEvent = args.clientEvent end
            if args.serverReceiveMs and not entry.serverReceiveMs then entry.serverReceiveMs = args.serverReceiveMs end
            if args.orderAcceptedMs and not entry.orderAcceptedMs then entry.orderAcceptedMs = args.orderAcceptedMs end
            if args.serverFlushMs and not entry.serverFlushMs then entry.serverFlushMs = args.serverFlushMs end
            if entry.urgentMercenaryOrder == true or entry.mercenaryOrderAsync == false or args.urgentMercenaryOrder == true then
                entry.urgentMercenaryOrder = true
                entry.mercenaryOrderAsync = false
                local bandit, brain = npcclient_applyNPCPart(entry, {deferImmediate = true})
                if bandit and brain then immediate[#immediate + 1] = {bandit=bandit, brain=brain, args=entry} end
            else
                entry.mercenaryOrderAsync = true
                npcclient_queueMercenaryOrderPart(entry)
            end
        end
    end
    for _, item in ipairs(immediate) do
        npcclient_queueImmediateMercenaryOrderTask(item.bandit, item.brain, item.args, "client_order_batch")
    end
end

function NPCClientCommandBridge.RemoveSpyPayment(args)
    local player = getSpecificPlayer and getSpecificPlayer(0) or getPlayer()
    if player and NPCSpyBridge and NPCSpyBridge.TakePayment then
        pcall(function() NPCSpyBridge.TakePayment(player) end)
    end
end

local function npcclient_idSet(ids)
    local set = {}
    if type(ids) == "table" then
        for _, id in pairs(ids) do
            if id ~= nil then set[tostring(id)] = true end
        end
    elseif ids ~= nil then
        set[tostring(ids)] = true
    end
    return set
end

local function npcclient_removeQueueEntry(gmd, id)
    if not (gmd and gmd.Queue and id ~= nil) then return end

    gmd.Queue[id] = nil
    gmd.Queue[tostring(id)] = nil
    local nid = tonumber(id)
    if nid then gmd.Queue[nid] = nil end
end

local function npcclient_nearPoint(zombie, args)
    local x = tonumber(args.x)
    local y = tonumber(args.y)
    if not x or not y then return true end

    local radius = tonumber(args.radius) or 48
    if radius <= 0 then return true end

    local dx = zombie:getX() - x
    local dy = zombie:getY() - y
    return (dx * dx + dy * dy) <= (radius * radius)
end

local function npcclient_isFormerNPCZombie(zombie)
    local md = zombie:getModData()
    if md and (md[NPC_LEGACY_KEYS.FORMER_ZOMBIE] or md[NPC_LEGACY_KEYS.IS_FLAG] or md[NPC_LEGACY_KEYS.RUNTIME_ID] or md[NPC_LEGACY_KEYS.PERSISTENT_ID] or md[NPC_LEGACY_KEYS.WORLD_GROUP_ID] or md[NPC_LEGACY_KEYS.PROGRAM]) then return true end

    local okVar, var = pcall(function() return zombie:getVariableBoolean(NPC_LEGACY_KEYS.FORMER_ZOMBIE) end)
    if okVar and var then return true end

    local okRuntime, runtimeId = pcall(function() return zombie:getVariableString(NPC_LEGACY_KEYS.RUNTIME_ID) end)
    if okRuntime and runtimeId and runtimeId ~= "" then return true end

    local okPersistent, persistentId = pcall(function() return zombie:getVariableString(NPC_LEGACY_KEYS.PERSISTENT_ID) end)
    if okPersistent and persistentId and persistentId ~= "" then return true end

    local okGroup, groupId = pcall(function() return zombie:getVariableString(NPC_LEGACY_KEYS.WORLD_GROUP_ID) end)
    if okGroup and groupId and groupId ~= "" then return true end

    return false
end

local function npcclient_getZombieRuntimeId(zombie)
    if not (zombie and NPCUtils and NPCUtils.GetCharacterID) then return nil end

    local ok, id = pcall(function() return NPCUtils.GetCharacterID(zombie) end)
    if ok then return id end

    return nil
end

local function npcclient_nonEmpty(value)
    if value == nil then return nil end
    local text = tostring(value)
    if text == "" or text == "nil" or text == "false" then return nil end
    return text
end

local function npcclient_getZombieServiceId(zombie, mdKey, variableName)
    if not zombie then return nil end

    local md = zombie:getModData()
    local value = md and md[mdKey] or nil
    value = npcclient_nonEmpty(value)
    if value then return value end

    local ok, var = pcall(function() return zombie:getVariableString(variableName) end)
    if ok then return npcclient_nonEmpty(var) end

    return nil
end

local function npcclient_setHasEntries(set)
    if type(set) ~= "table" then return false end
    for _, _ in pairs(set) do return true end
    return false
end

local function npcclient_isCleanupFormerNPCZombie(zombie)
    if not zombie then return false end

    local md = zombie:getModData()
    if md and md[NPC_LEGACY_KEYS.FORMER_ZOMBIE] then return true end

    local okFormer, former = pcall(function() return zombie:getVariableBoolean(NPC_LEGACY_KEYS.FORMER_ZOMBIE) end)
    if okFormer and former then return true end

    local okNPC, isNPC = pcall(function() return zombie:getVariableBoolean(NPC_LEGACY_KEYS.FLAG) end)
    if okNPC and isNPC then return false end

    if npcclient_getZombieServiceId(zombie, NPC_LEGACY_KEYS.RUNTIME_ID, NPC_LEGACY_KEYS.RUNTIME_ID) then return true end
    if npcclient_getZombieServiceId(zombie, NPC_LEGACY_KEYS.PERSISTENT_ID, NPC_LEGACY_KEYS.PERSISTENT_ID) then return true end
    if npcclient_getZombieServiceId(zombie, NPC_LEGACY_KEYS.WORLD_GROUP_ID, NPC_LEGACY_KEYS.WORLD_GROUP_ID) then return true end

    return false
end

local function npcclient_matchesCleanupScope(zombie, args, runtimeId, runtimeIdSet, persistentIdSet)
    args = args or {}

    if runtimeId and runtimeIdSet and runtimeIdSet[tostring(runtimeId)] then return true end

    local persistentId = npcclient_getZombieServiceId(zombie, NPC_LEGACY_KEYS.PERSISTENT_ID, NPC_LEGACY_KEYS.PERSISTENT_ID)
    if persistentId and persistentIdSet and persistentIdSet[tostring(persistentId)] then return true end

    local requestedGroupId = args.groupId or args.worldGroupId
    local hasPersistentIds = npcclient_setHasEntries(persistentIdSet)
    if requestedGroupId ~= nil then
        local objectGroupId = npcclient_getZombieServiceId(zombie, NPC_LEGACY_KEYS.WORLD_GROUP_ID, NPC_LEGACY_KEYS.WORLD_GROUP_ID)
        if objectGroupId and tostring(objectGroupId) == tostring(requestedGroupId) then return true end
        return false
    end

    if hasPersistentIds then return false end
    if npcclient_setHasEntries(runtimeIdSet) then return false end

    return true
end

local function npcclient_shouldKeepDeadNPCCorpse(zombie, args)
    if not zombie then return false end
    local md = zombie.getModData and zombie:getModData() or nil
    if not md then return false end
    if not (md.NPCKeepCorpse == true or md.NPCLootableCorpse == true or md.NPCCorpseFromNPCCombat == true) then return false end
    if args and (args.forceCorpseCleanup == true or args.forceRemoveCorpse == true or args.blackMarketStaticCleanup == true) then return false end
    local isDead = false
    local okDead, deadValue = pcall(function() return zombie:isDead() end)
    if okDead and deadValue == true then isDead = true end
    local okAlive, aliveValue = pcall(function() return zombie:isAlive() end)
    if okAlive and aliveValue == false then isDead = true end
    return isDead == true
end

local function npcclient_removeZombieObject(zombie, args)
    if not zombie then return false end
    if npcclient_shouldKeepDeadNPCCorpse(zombie, args) then return false end

    if NPCBrainData and NPCBrainData.Remove then
        pcall(function() NPCBrainData.Remove(zombie) end)
    end

    pcall(function() zombie:setVariable(NPC_LEGACY_KEYS.FLAG, false) end)
    pcall(function() zombie:setVariable(NPC_LEGACY_KEYS.PRIMARY, "") end)
    pcall(function() zombie:setVariable(NPC_LEGACY_KEYS.SECONDARY, "") end)
    pcall(function() zombie:clearAttachedItems() end)
    pcall(function() zombie:removeFromWorld() end)
    pcall(function() zombie:removeFromSquare() end)

    return true
end

local function npcclient_removeNPCObjectsNow(args)
    args = args or {}

    local idSet = npcclient_idSet(args.ids or args.id)
    local persistentIdSet = npcclient_idSet(args.persistentIds or args.persistentId)
    local hasIds = false
    for _, _ in pairs(idSet) do
        hasIds = true
        break
    end

    local gmd = GetNPCModData()
    if hasIds then
        for id, _ in pairs(idSet) do
            npcclient_removeQueueEntry(gmd, id)
        end
    end

    local cell = getCell()
    if not cell then return end

    local zombieList = cell:getZombieList()
    if not zombieList then return end

    local removed = {}
    for i = zombieList:size() - 1, 0, -1 do
        local zombie = zombieList:get(i)
        if zombie then
            local remove = false
            local runtimeId = npcclient_getZombieRuntimeId(zombie)

            local queueActive = runtimeId and gmd and gmd.Queue and (gmd.Queue[runtimeId] or gmd.Queue[tostring(runtimeId)] or (tonumber(runtimeId) and gmd.Queue[tonumber(runtimeId)]))

            if runtimeId and idSet[tostring(runtimeId)] and (not args.formerOnly or not queueActive) then
                remove = true
            elseif args.formerOnly and not queueActive and npcclient_nearPoint(zombie, args) and npcclient_isCleanupFormerNPCZombie(zombie) and npcclient_matchesCleanupScope(zombie, args, runtimeId, idSet, persistentIdSet) then
                remove = true
            end

            if remove and npcclient_removeZombieObject(zombie, args) and runtimeId then
                table.insert(removed, tostring(runtimeId))
            end
        end
    end

    if NPCZombieCacheBridge then
        for _, id in ipairs(removed) do
            if NPCZombieCacheBridge.Cache then NPCZombieCacheBridge.Cache[id] = nil end
            if NPCZombieCacheBridge.CacheLight then NPCZombieCacheBridge.CacheLight[id] = nil end
            if NPCZombieCacheBridge.CacheLightB then NPCZombieCacheBridge.CacheLightB[id] = nil end
            if NPCZombieCacheBridge.CacheLightZ then NPCZombieCacheBridge.CacheLightZ[id] = nil end
        end
    end
end

local NPC_CLIENT_LEGACY_STATE = NPCLegacyContractBridge.State
ZSClient._removeNPCObjectQueue = ZSClient._removeNPCObjectQueue or ZSClient[NPC_CLIENT_LEGACY_STATE.removeObjectQueue] or {ids = {}, order = {}, head = 1, ticks = 0}
ZSClient[NPC_CLIENT_LEGACY_STATE.removeObjectQueue] = ZSClient._removeNPCObjectQueue

local function npcclient_batchRemoveEnabled(args)
    if not args or args.immediate or args.formerOnly or args.blackMarketStaticCleanup then return false end
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool and not NPCLegacySettingsBridge.GetBool("Net_BatchedRemove" .. NPCLegacyContractBridge.Token .. "Objects", true) then return false end

    local idSet = npcclient_idSet(args.ids or args.id)
    for _, _ in pairs(idSet) do
        return true
    end

    return false
end

local function npcclient_queueRemoveNPCObjects(args)
    if not npcclient_batchRemoveEnabled(args) then return false end

    local q = ZSClient._removeNPCObjectQueue
    if not q then
        q = {ids = {}, order = {}, head = 1, ticks = 0}
        ZSClient._removeNPCObjectQueue = q
        ZSClient[NPC_CLIENT_LEGACY_STATE.removeObjectQueue] = q
    end

    local idSet = npcclient_idSet(args.ids or args.id)
    local added = 0
    for id, _ in pairs(idSet) do
        local sid = tostring(id)
        if sid ~= "" and not q.ids[sid] then
            q.ids[sid] = true
            q.order[#q.order + 1] = sid
            added = added + 1
        end
    end

    if added <= 0 then return false end
    q.reason = tostring(args.reason or q.reason or "batched_remove_bandit_objects")
    q.x = tonumber(args.x) or q.x
    q.y = tonumber(args.y) or q.y
    q.z = tonumber(args.z) or q.z
    return true
end

local function npcclient_removeBatchIntervalTicks()
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        return math.max(1, NPCLegacySettingsBridge.GetNumber("Net_RemoveObjectsBatchIntervalTicks", 6, 1, 300))
    end
    return 6
end

local function npcclient_removeBatchMaxIds()
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        return math.max(1, NPCLegacySettingsBridge.GetNumber("Net_RemoveObjectsMaxIdsPerBatch", 96, 1, 1000))
    end
    return 96
end

function ZSClient.FlushRemoveNPCObjectQueue(force)
    local q = ZSClient._removeNPCObjectQueue
    if not q or type(q.order) ~= "table" then return 0 end

    q.ticks = (tonumber(q.ticks) or 0) + 1
    local interval = npcclient_removeBatchIntervalTicks()
    if not force and (q.ticks % interval) ~= 0 then return 0 end

    local maxIds = npcclient_removeBatchMaxIds()
    local ids = {}

    while #ids < maxIds and #q.order > 0 do
        local id = table.remove(q.order, 1)
        if id and q.ids[id] then
            q.ids[id] = nil
            ids[#ids + 1] = id
        end
    end

    q.head = 1

    if #ids <= 0 then return 0 end

    npcclient_removeNPCObjectsNow({
        ids = ids,
        reason = tostring(q.reason or "batched_remove_bandit_objects"),
        batched = true,
        x = q.x,
        y = q.y,
        z = q.z
    })
    return #ids
end

ZSClient._formerNPCCleanupScopes = ZSClient._formerNPCCleanupScopes or ZSClient[NPC_CLIENT_LEGACY_STATE.formerCleanupScopes] or {}
ZSClient[NPC_CLIENT_LEGACY_STATE.formerCleanupScopes] = ZSClient._formerNPCCleanupScopes
ZSClient._formerNPCCleanupTick = ZSClient._formerNPCCleanupTick or ZSClient[NPC_CLIENT_LEGACY_STATE.formerCleanupTick] or 0
ZSClient[NPC_CLIENT_LEGACY_STATE.formerCleanupTick] = ZSClient._formerNPCCleanupTick

local function npcclient_registerFormerNPCCleanupScope(args)
    if not (args and args.formerOnly) then return false end

    local hasScope = args.groupId ~= nil or args.worldGroupId ~= nil or args.persistentIds ~= nil or args.persistentId ~= nil or args.ids ~= nil or args.id ~= nil
    if not hasScope then return false end

    local scopes = ZSClient._formerNPCCleanupScopes
    local tick = tonumber(ZSClient._formerNPCCleanupTick) or 0
    local scope = {}
    for k, v in pairs(args) do scope[k] = v end
    scope.expiresTick = tick + 1800
    scope.radius = tonumber(scope.radius) or 160
    scope.reason = tostring(scope.reason or "former_bandit_delayed_cleanup")

    local key = tostring(scope.groupId or scope.worldGroupId or "") .. ":" .. tostring(scope.x or "") .. ":" .. tostring(scope.y or "") .. ":" .. tostring(scope.reason or "")
    for _, existing in ipairs(scopes) do
        local existingKey = tostring(existing.groupId or existing.worldGroupId or "") .. ":" .. tostring(existing.x or "") .. ":" .. tostring(existing.y or "") .. ":" .. tostring(existing.reason or "")
        if existingKey == key then
            existing.expiresTick = scope.expiresTick
            existing.radius = scope.radius
            existing.persistentIds = scope.persistentIds or existing.persistentIds
            existing.persistentId = scope.persistentId or existing.persistentId
            existing.ids = scope.ids or existing.ids
            existing.id = scope.id or existing.id
            return true
        end
    end

    scopes[#scopes + 1] = scope
    while #scopes > 32 do
        table.remove(scopes, 1)
    end

    return true
end

function ZSClient.FlushFormerNPCCleanupScopes(force)
    local scopes = ZSClient._formerNPCCleanupScopes
    if type(scopes) ~= "table" or #scopes <= 0 then return 0 end

    local tick = tonumber(ZSClient._formerNPCCleanupTick) or 0
    if not force and (tick % 15) ~= 0 then return 0 end

    local processed = 0
    for i = #scopes, 1, -1 do
        local scope = scopes[i]
        if not scope or (scope.expiresTick and tick > tonumber(scope.expiresTick)) then
            table.remove(scopes, i)
        else
            npcclient_removeNPCObjectsNow(scope)
            processed = processed + 1
        end
    end

    return processed
end

function NPCClientCommandBridge.RemoveNPCObjects(args)
    args = args or {}
    if args.formerOnly then
        npcclient_registerFormerNPCCleanupScope(args)
    end
    if npcclient_queueRemoveNPCObjects(args) then
        return
    end
    npcclient_removeNPCObjectsNow(args)
end

local function npcclient_teleportIdSet(args)
    local set = {}
    local function add(value)
        if value == nil then return end
        local sid = tostring(value)
        if sid == "" or sid == "nil" or sid == "false" then return end
        set[sid] = true
    end
    if type(args) == "table" then
        add(args.id)
        add(args.runtimeId)
        add(args.persistentId)
        add(args.uid)
        add(args.zombieId)
        if type(args.ids) == "table" then
            for _, value in pairs(args.ids) do add(value) end
        end
    end
    return set
end

local function npcclient_findNPCForTeleport(entry)
    if type(entry) ~= "table" then return nil end

    local ids = npcclient_teleportIdSet({
        id = entry.id,
        runtimeId = entry.runtimeId,
        persistentId = entry.persistentId,
        uid = entry.uid,
        zombieId = entry.zombieId
    })

    for id, _ in pairs(ids) do
        local bandit = npcclient_getNPCById(id)
        if bandit then return bandit end
    end

    local wantedGroup = entry.groupId or entry.worldGroupId
    local cell = getCell and getCell() or nil
    local list = cell and cell.getZombieList and cell:getZombieList() or nil
    if not (list and list.size and list.get) then return nil end

    local size = 0
    local okSize, gotSize = pcall(function() return list:size() end)
    if okSize then size = tonumber(gotSize) or 0 end

    for i=0, size - 1 do
        local zombie = list:get(i)
        if zombie then
            local runtimeId = npcclient_getZombieRuntimeId(zombie)
            if runtimeId and ids[tostring(runtimeId)] then return zombie end

            local persistentId = npcclient_getZombieServiceId(zombie, NPC_LEGACY_KEYS.PERSISTENT_ID, NPC_LEGACY_KEYS.PERSISTENT_ID)
            if persistentId and ids[tostring(persistentId)] then return zombie end

            local groupId = npcclient_getZombieServiceId(zombie, NPC_LEGACY_KEYS.WORLD_GROUP_ID, NPC_LEGACY_KEYS.WORLD_GROUP_ID)
            if wantedGroup and groupId and tostring(wantedGroup) == tostring(groupId) then
                if not entry.persistentId then return zombie end
                if persistentId and tostring(persistentId) == tostring(entry.persistentId) then return zombie end
            end
        end
    end

    return nil
end

local function npcclient_applyNPCTeleport(entry)
    if type(entry) ~= "table" then return false end
    local x = tonumber(entry.x)
    local y = tonumber(entry.y)
    local z = tonumber(entry.z) or 0
    if not x or not y then return false end

    local bandit = npcclient_findNPCForTeleport(entry)
    local brain = nil
    if bandit and NPCBrainData and NPCBrainData.Get then
        local ok, got = pcall(function() return NPCBrainData.Get(bandit) end)
        if ok then brain = got end
    end

    if bandit then
        if NPCEntity and NPCEntity.ClearTasks then pcall(function() NPCEntity.ClearTasks(bandit) end) end
        if bandit.setTarget then pcall(function() bandit:setTarget(nil) end) end
        if bandit.setAttackedBy then pcall(function() bandit:setAttackedBy(nil) end) end
        if bandit.clearAggroList then pcall(function() bandit:clearAggroList() end) end
        if bandit.setX then pcall(function() bandit:setX(x) end) end
        if bandit.setY then pcall(function() bandit:setY(y) end) end
        if bandit.setZ then pcall(function() bandit:setZ(z) end) end
    end

    if type(brain) == "table" then
        brain.x = x
        brain.y = y
        brain.z = z
        brain.debugCoords = {x=x, y=y, z=z}
        brain.currentThreat = nil
        brain.lastThreat = nil
        brain.targetId = nil
        brain.targetKind = nil
        brain.tasks = {}
        brain.isPlayerGuard = true
        if brain.fsm then
            brain.fsm.targetId = nil
            brain.fsm.targetKind = nil
            brain.fsm.currentThreat = nil
            brain.fsm.lastThreat = nil
        end
        if bandit and NPCBrainData and NPCBrainData.Update then
            pcall(function() NPCBrainData.Update(bandit, brain) end)
        end
    end

    local gmd = GetNPCModData and GetNPCModData() or nil
    if gmd and gmd.Queue then
        local set = npcclient_teleportIdSet(entry)
        for qid, queuedBrain in pairs(gmd.Queue) do
            local match = false
            if set[tostring(qid)] then match = true end
            if queuedBrain then
                if queuedBrain.id and set[tostring(queuedBrain.id)] then match = true end
                if queuedBrain.uid and set[tostring(queuedBrain.uid)] then match = true end
                if queuedBrain.persistentId and set[tostring(queuedBrain.persistentId)] then match = true end
                local groupId = entry.groupId or entry.worldGroupId
                local brainGroup = queuedBrain.worldGroupId or queuedBrain.groupId
                if groupId and brainGroup and tostring(groupId) == tostring(brainGroup) and (not entry.persistentId or tostring(entry.persistentId) == tostring(queuedBrain.persistentId or queuedBrain.uid or "")) then match = true end
            end
            if match and type(queuedBrain) == "table" then
                queuedBrain.x = x
                queuedBrain.y = y
                queuedBrain.z = z
                queuedBrain.debugCoords = {x=x, y=y, z=z}
                queuedBrain.currentThreat = nil
                queuedBrain.lastThreat = nil
                queuedBrain.targetId = nil
                queuedBrain.targetKind = nil
                queuedBrain.tasks = {}
                queuedBrain.isPlayerGuard = true
                gmd.Queue[qid] = queuedBrain
            end
        end
    end

    return bandit ~= nil
end

function NPCClientCommandBridge.TeleportNPCObjects(args)
    args = args or {}
    local objects = args.objects
    if type(objects) ~= "table" then
        objects = {args}
    end

    for _, entry in pairs(objects) do
        npcclient_applyNPCTeleport(entry)
    end
end


local function npcclient_playerId(player)
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

local function npcclient_idSet(args)
    local set = {}
    local function add(value)
        if value == nil then return end
        local sid = tostring(value)
        if sid == "" or sid == "nil" or sid == "false" then return end
        set[sid] = true
    end
    if type(args) == "table" then
        add(args.id)
        add(args.runtimeId)
        add(args.persistentId)
        add(args.uid)
        add(args.zombieId)
        if type(args.ids) == "table" then
            for _, value in pairs(args.ids) do add(value) end
        end
    end
    return set
end

local function npcclient_brainMatchesHireResult(brain, id, args, set)
    if not brain then return false end
    local values = {id, brain.id, brain.runtimeId, brain.uid, brain.persistentId, brain[NPC_LEGACY_KEYS.RUNTIME_ID], brain[NPC_LEGACY_KEYS.PERSISTENT_ID]}
    for _, value in ipairs(values) do
        if value ~= nil and set[tostring(value)] then return true end
    end
    local groupId = args and (args.groupId or args.worldGroupId)
    local brainGroup = brain.worldGroupId or brain.groupId
    if groupId and brainGroup and tostring(groupId) == tostring(brainGroup) then return true end
    return false
end

local function npcclient_applyMercenaryHireToBrain(brain, args, player)
    if not brain then return end
    local pid = args.mercenaryHiredBy or npcclient_playerId(player)
    brain.mercenary = true
    brain.mercenaryHired = true
    brain.mercenaryHiredBy = pid
    brain.hostile = false
    brain.relationshipToPlayer = "companion"
    brain.factionSide = "blue"
    brain.faction = "blue"
    brain.side = "blue"
    brain.patrolColor = "blue"
    brain.program = {name="Companion", stage="Prepare"}
    brain.order = brain.order or {}
    brain.order.name = "Follow"
    brain.order.source = "hire_result"
    brain.order.master = pid
    brain.order.priority = 95
    brain.order.fireMode = brain.order.fireMode or "Defensive"
    brain.order.formation = brain.order.formation or "close"
    brain.order.followDistance = brain.order.followDistance or 3.0
    brain.fireMode = brain.order.fireMode
    brain.rbFireMode = brain.fireMode
end


local function npcclient_takeMercenaryPayment(args, player)
    if not (args and args.takeClientPayment == true and player and NPCMercenaryContract and NPCMercenaryContract.TakePayment) then return end
    local okCall, paid, kind = pcall(function() return NPCMercenaryContract.TakePayment(player) end)
    print("[NPCMercenary] client payment removal ok=" .. tostring(okCall and paid == true) .. " kind=" .. tostring(kind))
end

function NPCClientCommandBridge.MercenaryHireResult(args)
    args = args or {}
    local player = getPlayer and getPlayer() or nil
    if args.clientTraceId ~= nil or args.serverReceiveMs ~= nil then
        print("[NPCMercenaryTelemetry] client hire result ok=" .. tostring(args.ok == true) .. npcclient_mercTelemetryText(args, npcclient_nowMs()))
    end
    if args.message and player and player.Say then pcall(function() player:Say(tostring(args.message)) end) end
    if args.ok ~= true then return end
    npcclient_takeMercenaryPayment(args, player)

    local set = npcclient_idSet(args)
    local gmd = GetNPCModData and GetNPCModData() or nil
    if gmd and gmd.Queue then
        for id, brain in pairs(gmd.Queue) do
            if npcclient_brainMatchesHireResult(brain, id, args, set) then
                npcclient_applyMercenaryHireToBrain(brain, args, player)
                gmd.Queue[id] = brain
            end
        end
    end

    local cell = getCell and getCell() or nil
    local list = cell and cell.getZombieList and cell:getZombieList() or nil
    if not (list and list.size and list.get and NPCBrainData and NPCBrainData.Get) then return end

    local x = tonumber(args.x)
    local y = tonumber(args.y)
    local z = tonumber(args.z)
    local size = 0
    local okSize, gotSize = pcall(function() return list:size() end)
    if okSize then size = tonumber(gotSize) or 0 end

    for i = 0, size - 1 do
        local okGet, zombie = pcall(function() return list:get(i) end)
        if okGet and zombie and zombie.getVariableBoolean and zombie:getVariableBoolean(NPC_LEGACY_KEYS.FLAG) then
            local brain = NPCBrainData.Get(zombie)
            local matched = npcclient_brainMatchesHireResult(brain, nil, args, set)
            if not matched and x and y and zombie.getX and zombie.getY then
                local zx = tonumber(zombie:getX())
                local zy = tonumber(zombie:getY())
                local zz = zombie.getZ and tonumber(zombie:getZ()) or 0
                if zx and zy and (z == nil or math.abs((tonumber(z) or 0) - (zz or 0)) <= 1.0) then
                    local dx = zx - x
                    local dy = zy - y
                    matched = (dx * dx + dy * dy) <= 36
                end
            end
            if matched then
                npcclient_applyMercenaryHireToBrain(brain, args, player)
                NPCBrainData.Update(zombie, brain)
            end
        end
    end
end


function NPCClientCommandBridge.OnServerCommand(module, command, args)
    local clientModule = NPCClientCommandBridge.NormalizeModule(module)
    if ZSClient[clientModule] and ZSClient[clientModule][command] then
        local argStr = ""
        if type(args) == "table" then
            for k, v in pairs(args) do
                argStr = argStr .. " " .. k .. "=" .. tostring(v)
            end
        end
        -- print ("client received " .. module .. "." .. command .. " "  .. argStr)
        ZSClient[clientModule][command](args)
    end
end

local function npcclient_flushMercenaryOrderQueue()
    local queue = ZSClient and ZSClient.MercenaryOrderQueue or nil
    if type(queue) ~= "table" or #queue == 0 then return end
    if not ZSClient.MercenaryOrderQueueById then ZSClient.MercenaryOrderQueueById = {} end

    local limit = 4
    local budgetMs = 4
    local started = getTimestampMs and getTimestampMs() or 0
    local processed = 0

    while #queue > 0 and processed < limit do
        local entry = table.remove(queue, 1)
        if entry and entry.id ~= nil then
            ZSClient.MercenaryOrderQueueById[tostring(entry.id)] = nil
            npcclient_applyNPCPart(entry)
            processed = processed + 1
        end
        if started > 0 and getTimestampMs and (getTimestampMs() - started) >= budgetMs then
            break
        end
    end

    ZSClient.MercenaryOrderQueueById = {}
    for i, entry in ipairs(queue) do
        if entry and entry.id ~= nil then
            ZSClient.MercenaryOrderQueueById[tostring(entry.id)] = i
        end
    end
end

function NPCClientCommandBridge.OnTick()
    ZSClient._formerNPCCleanupTick = (tonumber(ZSClient._formerNPCCleanupTick) or tonumber(ZSClient[NPC_CLIENT_LEGACY_STATE.formerCleanupTick]) or 0) + 1
    ZSClient[NPC_CLIENT_LEGACY_STATE.formerCleanupTick] = ZSClient._formerNPCCleanupTick
    if ZSClient and ZSClient.FlushRemoveNPCObjectQueue then
        ZSClient.FlushRemoveNPCObjectQueue(false)
    end
    if ZSClient and ZSClient.FlushFormerNPCCleanupScopes then
        ZSClient.FlushFormerNPCCleanupScopes(false)
    end
    npcclient_flushMercenaryOrderQueue()
end

-- NPCClientCommandBridge legacy command helper aliases for compatibility with old callers.
local NPC_CLIENT_COMMAND_LEGACY_TOKEN = NPCLegacyContractBridge.Token or ("Ban" .. "dit")
NPCClientCommandBridge["Update" .. NPC_CLIENT_COMMAND_LEGACY_TOKEN .. "Part"] = NPCClientCommandBridge.UpdateNPCPart
NPCClientCommandBridge["Remove" .. NPC_CLIENT_COMMAND_LEGACY_TOKEN .. "Objects"] = NPCClientCommandBridge.RemoveNPCObjects
NPCClientCommandBridge["Teleport" .. NPC_CLIENT_COMMAND_LEGACY_TOKEN .. "Objects"] = NPCClientCommandBridge.TeleportNPCObjects
ZSClient["FlushRemove" .. NPC_CLIENT_COMMAND_LEGACY_TOKEN .. "ObjectQueue"] = ZSClient.FlushRemoveNPCObjectQueue
ZSClient["FlushFormer" .. NPC_CLIENT_COMMAND_LEGACY_TOKEN .. "CleanupScopes"] = ZSClient.FlushFormerNPCCleanupScopes

function NPCClientCommandBridge.Install(target)
    ZSClient = target or ZSClient or {}
    ZSClient.Commands = ZSClient.Commands or {}
ZSClient.NPCCommands = ZSClient.Commands
    ZSClient.Commands.UpdateVehicle = NPCClientCommandBridge.UpdateVehicle
    ZSClient.Commands[NPCLegacyContractBridge.Commands.updatePart] = NPCClientCommandBridge.UpdateNPCPart
    ZSClient.Commands.MercenaryOrderBatch = NPCClientCommandBridge.MercenaryOrderBatch
    ZSClient.Commands.MercenaryDirectOrderBatch = NPCClientCommandBridge.MercenaryDirectOrderBatch
    ZSClient.Commands.RemoveSpyPayment = NPCClientCommandBridge.RemoveSpyPayment
    ZSClient.Commands[NPCLegacyContractBridge.Commands.removeObjects] = NPCClientCommandBridge.RemoveNPCObjects
    ZSClient.Commands[NPCLegacyContractBridge.Commands.teleportObjects] = NPCClientCommandBridge.TeleportNPCObjects
    ZSClient.Commands.MercenaryHireResult = NPCClientCommandBridge.MercenaryHireResult

    if NPCClientCommandBridge._installed then return end
    NPCClientCommandBridge._installed = true
    if Events and Events.OnServerCommand and Events.OnServerCommand.Add then
        Events.OnServerCommand.Add(NPCClientCommandBridge.OnServerCommand)
    end
    if Events and Events.OnTick and Events.OnTick.Add then
        Events.OnTick.Add(NPCClientCommandBridge.OnTick)
    end
end
