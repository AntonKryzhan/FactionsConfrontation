-- Neutral brain director bridge.
-- Compatibility backend for media/lua/shared/brain-director bridge.lua.

require "NPCCore/NPCLegacyContractBridge"
require "NPCBehavior/NPCIntentArbiterBridge"
require "NPCBehavior/NPCLivingWorldIntentBridge"
require "NPCCore/NPCWorldRoutineBridge"
require "NPCCore/NPCLootTargetCacheBridge"
require "NPCCore/NPCPostCombatLootBridge"
pcall(require, "NPCCore/NPCSpatialIndexBridge")

NPCBrainDirectorBridge = NPCBrainDirectorBridge or {}
local NPC_BRAIN_DIRECTOR_LEGACY_KEYS = {
    programNPC = NPCLegacyContractBridge.Key("FLAG")
}
NPCBrainDirectorBridge.Version = 452

function NPCBrainDirectorBridge.CreateDefaultStates()
    return {
        Idle = "Idle",
        Moving = "Moving",
        FollowPlayer = "FollowPlayer",
        GuardPlayer = "GuardPlayer",
        HoldPosition = "HoldPosition",
        GuardArea = "GuardArea",
        PatrolArea = "PatrolArea",
        LootArea = "LootArea",
        ReturnToBase = "ReturnToBase",
        HealSelf = "HealSelf",
        ReloadWeapon = "ReloadWeapon",
        ReloadCover = "ReloadCover",
        EatDrink = "EatDrink",
        SleepRest = "SleepRest",
        EmergencyDefense = "EmergencyDefense",
        Flee = "Flee",
        SearchEnemy = "SearchEnemy",
        FlankEnemy = "FlankEnemy",
        TacticalCover = "TacticalCover",
        SuppressEnemy = "SuppressEnemy",
        HoldAngle = "HoldAngle",
        BoundForward = "BoundForward",
        InvestigateNoise = "InvestigateNoise",
        LookAround = "LookAround",
        Attack = "Attack",
        MeleeFallback = "MeleeFallback",
        DefendBase = "DefendBase",
        KeepDistance = "KeepDistance",
        Regroup = "Regroup",
        RecoverPath = "RecoverPath",
        Disabled = "Disabled",
        Dead = "Dead"
    }
end

function NPCBrainDirectorBridge.CreateDefaultConfig()
    return {
        followDistance = 4.0,
        guardPlayerDistance = 5.5,
        holdRadius = 2.5,
        guardRadius = 10.0,
        patrolRadius = 18.0,
        defendRadius = 14.0,
        lootScanRadius = 12,
        fleeDistance = 9.0,
        keepDistance = 4.0,
        searchRadius = 12.0,
        tacticalRadioSearchRadius = 46.0,
        humanizedSearchPause = 65,
        meleeApproachCooldownMs = 1500,
        meleeApproachSameTargetMs = 2400,
        meleeApproachMaxDist = 6.5
    }
end

function NPCBrainDirectorBridge.ApplyDefaults(director)
    if not director then return end

    director.VERSION = "2026-05-31-stage311-single-arbiter-cache"
    director.States = director.States or NPCBrainDirectorBridge.CreateDefaultStates()
    director.Config = director.Config or NPCBrainDirectorBridge.CreateDefaultConfig()

    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.ApplyBrainDirector then
        NPCLegacySettingsBridge.ApplyBrainDirector(director)
    end
end


function NPCBrainDirectorBridge.Now()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then return math.floor(getGameTime():getWorldAgeHours() * 3600000) end
    return 0
end

function NPCBrainDirectorBridge.WorldAgeHours()
    if getGameTime then return getGameTime():getWorldAgeHours() end
    return 0
end

function NPCBrainDirectorBridge.Dist2(x1, y1, x2, y2)
    local dx = x1 - x2
    local dy = y1 - y2
    return dx * dx + dy * dy
end

function NPCBrainDirectorBridge.Dist(x1, y1, x2, y2)
    return math.sqrt(NPCBrainDirectorBridge.Dist2(x1, y1, x2, y2))
end

function NPCBrainDirectorBridge.GetStrictOrderName(brain)
    if not (brain and NPCOrderContract and NPCOrderContract.GetStrictOrderName) then return nil end
    local ok, name = pcall(function() return NPCOrderContract.GetStrictOrderName(brain) end)
    if ok then return name end
    return nil
end

function NPCBrainDirectorBridge.GetStrictLeash(brain, kind, fallback)
    if NPCOrderContract and NPCOrderContract.GetStrictLeash then
        local ok, leash = pcall(function() return NPCOrderContract.GetStrictLeash(brain, kind) end)
        if ok and tonumber(leash) then return tonumber(leash) end
    end
    return fallback
end

function NPCBrainDirectorBridge.StrictStateForOrder(director, brain, strictOrderName)
    if not director or not strictOrderName then return nil end
    if strictOrderName == "Follow" or strictOrderName == "FallBack" or strictOrderName == "Return" then
        return director.States.FollowPlayer
    end
    if strictOrderName == "Hold" then return director.States.HoldPosition end
    if strictOrderName == "Guard" then
        if brain and brain.master then return director.States.GuardPlayer end
        return director.States.GuardArea
    end
    return nil
end

function NPCBrainDirectorBridge.PlayerCommandStateForOrder(director, brain, orderName)
    if not director then return nil end
    orderName = NPCOrderContract and NPCOrderContract.NormalizeOrderName and NPCOrderContract.NormalizeOrderName(orderName) or tostring(orderName or "")
    if orderName == "Follow" or orderName == "FallBack" then return director.States.FollowPlayer end
    if orderName == "Hold" then return director.States.HoldPosition end
    if orderName == "Guard" then
        if brain and brain.master then return director.States.GuardPlayer end
        return director.States.GuardArea
    end
    if orderName == "Patrol" then return director.States.PatrolArea end
    if orderName == "Loot" or orderName == "LootHouse" or orderName == "LootBodies" or orderName == "LootBodiesGear" or orderName == "LootBodiesClothing" or orderName == "LootBodiesWeapons" or orderName == "LootBodiesAmmo" or orderName == "LootBodiesMedical" or orderName == "LootBodiesSupplies" or orderName == "RearmHere" then return director.States.LootArea end
    if orderName == "Return" then return director.States.HoldPosition end
    return nil
end

function NPCBrainDirectorBridge.GetPlayerCommandOrderName(brain)
    if not (brain and NPCOrderContract and NPCOrderContract.IsPlayerCommandedOrderActive and NPCOrderContract.Get) then return nil end
    local ok, active = pcall(function() return NPCOrderContract.IsPlayerCommandedOrderActive(brain) end)
    if not ok or active ~= true then return nil end
    local okOrder, order = pcall(function() return NPCOrderContract.Get(brain) end)
    if not okOrder or type(order) ~= "table" then return nil end
    return NPCOrderContract.NormalizeOrderName(order.name)
end

function NPCBrainDirectorBridge.IsStrictCloseDefenseThreat(threat)
    if not threat then return false end
    local dist = tonumber(threat.dist)
    return dist ~= nil and dist <= 1.35
end

function NPCBrainDirectorBridge.GetBrain(chr)
    if not chr or not NPCBrainData or not NPCBrainData.Get then return nil end

    local ok, brain = pcall(function()
        return NPCBrainData.Get(chr)
    end)

    if ok then return brain end
    return nil
end

function NPCBrainDirectorBridge.IsAlive(chr)
    if not chr then return false end

    local ok, dead = pcall(function()
        return chr:isDead()
    end)
    if ok and dead then return false end

    ok, dead = pcall(function()
        return chr:isAlive()
    end)
    if ok and dead == false then return false end

    return true
end

function NPCBrainDirectorBridge.Health01(chr)
    if not chr then return 0 end

    local ok, health = pcall(function()
        return chr:getHealth()
    end)

    if not ok or health == nil then return 1 end

    health = tonumber(health) or 1
    if health > 1 then health = health / 100 end
    if health < 0 then return 0 end
    if health > 1 then return 1 end
    return health
end

function NPCBrainDirectorBridge.CurrentTask(bandit)
    if not bandit or not NPCEntity or not NPCEntity.GetTask then return nil end

    local ok, task = pcall(function()
        return NPCEntity.GetTask(bandit)
    end)

    if ok then return task end
    return nil
end

function NPCBrainDirectorBridge.CurrentAction(bandit)
    local task = NPCBrainDirectorBridge.CurrentTask(bandit)
    if task then return task.action end
    return nil
end

function NPCBrainDirectorBridge.HasActionTask(bandit)
    if not bandit or not NPCEntity or not NPCEntity.HasActionTask then return false end

    local ok, ret = pcall(function()
        return NPCEntity.HasActionTask(bandit)
    end)

    return ok and ret == true
end

function NPCBrainDirectorBridge.IsCombatAction(action)
    return action == "Shoot"
        or action == "Aim"
        or action == "Hit"
        or action == "Shove"
        or action == "Reload"
end

function NPCBrainDirectorBridge.FirstTaskAction(tasks)
    if tasks and #tasks > 0 and type(tasks[1]) == "table" then
        return tasks[1].action
    end
    return nil
end

function NPCBrainDirectorBridge.GetProgramName(brain)
    if brain and brain.program then return brain.program.name end
    return nil
end

function NPCBrainDirectorBridge.GetOrder(brain)
    if not brain then return nil end

    local order = brain.order or brain.directorOrder
    if type(order) == "table" then
        return order.name or order.action or order.type or order.mode
    end

    return order
end

function NPCBrainDirectorBridge.NormalizeOrder(order)
    if not order then return nil end

    order = tostring(order):lower()

    if order == "follow" or order == "followme" or order == "follow_me" then return "follow" end
    if order == "hold" or order == "holdposition" or order == "hold_position" then return "hold" end
    if order == "guard" or order == "guardarea" or order == "guard_area" then return "guard" end
    if order == "patrol" or order == "patrolarea" or order == "patrol_area" then return "patrol" end
    if order == "loot" or order == "lootarea" or order == "loot_area" then return "loot" end
    if order == "return" or order == "returntobase" or order == "return_to_base" then return "return" end
    if order == "free" or order == "freeroam" or order == "free_roam" then return "free" end
    if order == "sleep" or order == "rest" or order == "sleeprest" then return "sleep" end
    if order == "eat" or order == "drink" or order == "eatdrink" then return "eat" end
    if order == "donotshoot" or order == "do_not_shoot" or order == "no_fire" then return "no_fire" end
    if order == "meleeonly" or order == "use_melee_only" then return "melee_only" end

    return order
end

function NPCBrainDirectorBridge.OrderPoint(brain, key)
    if not brain then return nil end

    local order = brain.order
    if type(order) == "table" then
        local p = order[key] or order.anchor or order.point or order.target or order.position
        if type(p) == "table" and p.x and p.y then
            return tonumber(p.x), tonumber(p.y), tonumber(p.z) or 0
        end
        if order.x and order.y then
            return tonumber(order.x), tonumber(order.y), tonumber(order.z) or 0
        end
    end

    return nil
end

function NPCBrainDirectorBridge.Anchor(brain, bandit, key)
    local x, y, z = NPCBrainDirectorBridge.OrderPoint(brain, key)
    if x and y then return x, y, z end

    local direct = brain and key and brain[key]
    if type(direct) == "table" and direct.x and direct.y then
        return tonumber(direct.x), tonumber(direct.y), tonumber(direct.z) or 0
    end

    if key == "returnPoint" and brain and type(brain.homeBaseZone) == "table" and brain.homeBaseZone.x and brain.homeBaseZone.y then
        return tonumber(brain.homeBaseZone.x), tonumber(brain.homeBaseZone.y), tonumber(brain.homeBaseZone.z) or 0
    end

    local p = brain and (brain.homeBase or brain.homeBaseZone or brain.base or brain.guardPoint or brain.holdPoint or brain.returnPoint or brain.patrolPoint)
    if type(p) == "table" and p.x and p.y then
        return tonumber(p.x), tonumber(p.y), tonumber(p.z) or 0
    end

    if brain and brain.debugCoords and brain.debugCoords.x and brain.debugCoords.y then
        return tonumber(brain.debugCoords.x), tonumber(brain.debugCoords.y), tonumber(brain.debugCoords.z) or 0
    end

    if brain and brain.bornCoords and brain.bornCoords.x and brain.bornCoords.y then
        return tonumber(brain.bornCoords.x), tonumber(brain.bornCoords.y), tonumber(brain.bornCoords.z) or 0
    end

    if bandit then
        return bandit:getX(), bandit:getY(), bandit:getZ()
    end

    return nil
end

function NPCBrainDirectorBridge.FormationAnchor(brain, bandit, key)
    local order = brain and brain.order or nil
    local anchor = type(order) == "table" and (order[key] or order.anchor or order.point or order.target or order.position) or nil
    if type(anchor) == "table" and anchor.x and anchor.y and NPCFormationSlotsBridge and NPCFormationSlotsBridge.GetAnchorSlotPoint then
        local ok, sx, sy, sz = pcall(function()
            return NPCFormationSlotsBridge.GetAnchorSlotPoint(anchor, brain, bandit, order.formation or "close", order.followDistance or 2.0)
        end)
        if ok and sx and sy then return sx, sy, sz or tonumber(anchor.z) or 0 end
    end
    return NPCBrainDirectorBridge.Anchor(brain, bandit, key)
end

function NPCBrainDirectorBridge.ZonePoint(brain, key)
    local p = brain and brain[key]
    if type(p) == "table" and p.x and p.y then
        return tonumber(p.x), tonumber(p.y), tonumber(p.z) or 0
    end
    return nil
end

function NPCBrainDirectorBridge.MoveToZoneIfFar(runtime, bandit, brain, key, state, reason, radius, walkType)
    if not runtime or not bandit then return nil end

    local x, y, z = NPCBrainDirectorBridge.ZonePoint(brain, key)
    if not x or not y then return nil end

    local dist = runtime.dist(bandit:getX(), bandit:getY(), x, y)
    if dist > (tonumber(radius) or 3.0) then
        return {runtime.moveToState(bandit, state, reason, x, y, z, walkType or "Walk", true)}
    end
    return nil
end

function NPCBrainDirectorBridge.IsSquareUsable(x, y, z, mover)
    local cell = getCell()
    if not cell then return false end

    local square = cell:getGridSquare(math.floor(x), math.floor(y), math.floor(z or 0))
    if not square then return false end

    if NPCMovementStabilityBridge and NPCMovementStabilityBridge.IsSquareBlocked then
        return not NPCMovementStabilityBridge.IsSquareBlocked(square, mover)
    end

    local ok, water = pcall(function()
        if IsoFlagType and IsoFlagType.water then
            return square:Is(IsoFlagType.water)
        end
        return false
    end)
    if ok and water then return false end

    local solid = false
    ok, solid = pcall(function()
        return square:isSolid()
    end)
    if ok and solid then return false end

    local solidTrans = false
    ok, solidTrans = pcall(function()
        return square:isSolidTrans()
    end)
    if ok and solidTrans then return false end

    return true
end

function NPCBrainDirectorBridge.FindFreeAround(x, y, z, radius, mover)
    local cell = getCell()
    if not cell then return nil end

    local bx = math.floor(x)
    local by = math.floor(y)
    local bz = math.floor(z or 0)
    radius = radius or 5

    local bestX, bestY, bestZ = nil, nil, nil
    local bestScore = -1000000
    local mx = mover and mover:getX() or x
    local my = mover and mover:getY() or y

    for r=0, radius do
        for dx=-r, r do
            for dy=-r, r do
                if r == 0 or math.abs(dx) == r or math.abs(dy) == r then
                    local sx = bx + dx
                    local sy = by + dy
                    if NPCBrainDirectorBridge.IsSquareUsable(sx, sy, bz, mover) then
                        local score = -NPCBrainDirectorBridge.Dist2(sx, sy, x, y) * 0.75 - NPCBrainDirectorBridge.Dist2(sx, sy, mx, my) * 0.08 - r * 0.1
                        if NPCRoadNavBridge and NPCRoadNavBridge.ScorePoint then
                            local okScore, zoneScore, class = pcall(function()
                                return NPCRoadNavBridge.ScorePoint(sx, sy)
                            end)
                            if okScore and zoneScore then
                                if class == "road" then score = score + 4
                                elseif class == "town" then score = score + 1.5
                                elseif class == "blocked" then score = score - 12 end
                            end
                        end
                        if score > bestScore then
                            bestScore = score
                            bestX = sx
                            bestY = sy
                            bestZ = bz
                        end
                    end
                end
            end
        end
        if bestX and r >= 2 then return bestX, bestY, bestZ end
    end

    return bestX, bestY, bestZ
end

function NPCBrainDirectorBridge.OffsetPoint(x, y, z, radius, seed)
    seed = seed or ZombRand(628)
    local angle = (seed % 628) / 100
    local r = radius or 6
    local tx = x + math.cos(angle) * r
    local ty = y + math.sin(angle) * r

    local fx, fy, fz = NPCBrainDirectorBridge.FindFreeAround(tx, ty, z, 5)
    if fx and fy then return fx, fy, fz end

    return x, y, z
end

function NPCBrainDirectorBridge.GetStrictOrderSequence(brain)
    local order = brain and brain.order or nil
    if type(order) == "table" and tonumber(order.sequence) then return tonumber(order.sequence) end
    if brain and brain.ai and tonumber(brain.ai.orderSequence) then return tonumber(brain.ai.orderSequence) end
    return 0
end

function NPCBrainDirectorBridge.StabilizeStrictSlot(brain, key, anchorX, anchorY, anchorZ, targetX, targetY, targetZ, opts)
    if not (brain and key and targetX and targetY) then return targetX, targetY, targetZ end

    brain.ai = brain.ai or {}
    brain.ai.strictOrderSlots = brain.ai.strictOrderSlots or {}
    local slots = brain.ai.strictOrderSlots
    local now = NPCBrainDirectorBridge.Now()
    local seq = NPCBrainDirectorBridge.GetStrictOrderSequence(brain)
    opts = opts or {}

    local anchorDelta = tonumber(opts.anchorDelta) or 0.75
    local targetDelta = tonumber(opts.targetDelta) or 0.95
    local maxAgeMs = tonumber(opts.maxAgeMs) or 1800
    local zDelta = tonumber(opts.zDelta) or 0.35
    local slot = slots[key]

    if slot and slot.seq == seq and slot.x and slot.y then
        local anchorMoved = false
        if anchorX and anchorY and slot.ax and slot.ay then
            anchorMoved = NPCBrainDirectorBridge.Dist2(anchorX, anchorY, slot.ax, slot.ay) > anchorDelta * anchorDelta
            if anchorZ and slot.az then
                anchorMoved = anchorMoved or math.abs((tonumber(anchorZ) or 0) - (tonumber(slot.az) or 0)) > zDelta
            end
        end

        local targetMoved = NPCBrainDirectorBridge.Dist2(targetX, targetY, slot.x, slot.y) > targetDelta * targetDelta
        local expired = now > 0 and tonumber(slot.at) and maxAgeMs > 0 and (now - tonumber(slot.at)) > maxAgeMs
        if not anchorMoved and not targetMoved and not expired then
            return slot.x, slot.y, slot.z or targetZ
        end
    end

    slots[key] = {
        seq = seq,
        x = targetX,
        y = targetY,
        z = targetZ,
        ax = anchorX,
        ay = anchorY,
        az = anchorZ,
        at = now
    }
    return targetX, targetY, targetZ
end

function NPCBrainDirectorBridge.FollowFormationPoint(player, brain, bandit)
    local order = brain and brain.order or nil
    if NPCFormationSlotsBridge and (NPCFormationSlotsBridge.GetPlayerFollowSlotPoint or NPCFormationSlotsBridge.GetSlotPoint) then
        local okSlot, sx, sy, sz = pcall(function()
            local formation = type(order) == "table" and order.formation or "close"
            local followDistance = type(order) == "table" and order.followDistance or 3.0
            if NPCFormationSlotsBridge.GetPlayerFollowSlotPoint and brain and (brain.mercenaryHired == true or brain.relationshipToPlayer == "hired_bodyguard" or brain.factionState == "hired_blue_bodyguard") then
                return NPCFormationSlotsBridge.GetPlayerFollowSlotPoint(player, brain, bandit, formation, followDistance)
            end
            return NPCFormationSlotsBridge.GetSlotPoint(player, brain, bandit, formation, followDistance)
        end)
        if okSlot and sx and sy then
            local fx, fy, fz = NPCBrainDirectorBridge.FindFreeAround(sx, sy, sz or player:getZ(), 4, bandit)
            if fx and fy then return fx, fy, fz end
            return sx, sy, sz or player:getZ()
        end
    end
    if type(order) ~= "table" then
        return NPCBrainDirectorBridge.OffsetPoint(player:getX(), player:getY(), player:getZ(), 2.5 + ZombRand(3), NPCUtils.GetCharacterID(bandit) or ZombRand(628))
    end

    local formation = tostring(order.formation or "close")
    local rawIdx = brain and (brain.memberIndex or brain.slotIndex or brain.formationIndex or brain.id or brain.uid or brain.runtimeId) or nil
    local idx = tonumber(rawIdx)
    if not idx and type(rawIdx) == "string" then idx = tonumber(rawIdx:match("(%d+)%s*$")) end
    if not idx and NPCUtils and NPCUtils.GetCharacterID then
        local ok, rawId = pcall(function() return NPCUtils.GetCharacterID(bandit) end)
        if ok then
            idx = tonumber(rawId)
            if not idx and type(rawId) == "string" then idx = tonumber(rawId:match("(%d+)%s*$")) end
        end
    end
    idx = math.max(1, math.abs(tonumber(idx) or ZombRand(999) or 1))
    local distance = tonumber(order.followDistance) or 3.0
    local row = math.floor((idx - 1) / 2) + 1
    local side = ((idx % 2) == 0) and 1 or -1
    local px = player:getX()
    local py = player:getY()
    local pz = player:getZ()
    local angle = 0
    if player.getDirectionAngle then
        local ok, a = pcall(function() return player:getDirectionAngle() end)
        if ok and a then angle = math.rad(tonumber(a) or 0) end
    end

    local backX = -math.cos(angle)
    local backY = -math.sin(angle)
    local rightX = -math.sin(angle)
    local rightY = math.cos(angle)
    local back = distance + row * 0.8
    local lateral = side * (formation == "wide" and 2.4 or 1.35) * row

    if formation == "line" then
        back = distance
        lateral = (idx - 2) * 1.8
    elseif formation == "wedge" then
        back = distance + row * 1.25
        lateral = side * row * 1.6
    elseif formation == "wide" then
        back = distance + row * 1.1
    end

    local tx = px + backX * back + rightX * lateral
    local ty = py + backY * back + rightY * lateral
    local fx, fy, fz = NPCBrainDirectorBridge.FindFreeAround(tx, ty, pz, 4)
    if fx and fy then return fx, fy, fz end
    return tx, ty, pz
end


local function nbd_nowMs()
    if getTimestampMs then
        local ok, value = pcall(function() return getTimestampMs() end)
        if ok and tonumber(value) then return tonumber(value) end
    end
    if getGameTime then
        local ok, value = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok and tonumber(value) then return math.floor((tonumber(value) or 0) * 3600000) end
    end
    return 0
end

local function nbd_threatAlive(threat)
    if not threat then return true end
    local target = threat.target
    if not target or not target.isAlive then return true end
    local ok, alive = pcall(function() return target:isAlive() end)
    return (not ok) or alive ~= false
end

local function nbd_cachedThreat(brain, maxDist)
    local cache = type(brain) == "table" and brain._threatCache or nil
    if type(cache) ~= "table" then return nil, false end
    local now = nbd_nowMs()
    local ttl = 360
    if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.GetLoadState then
        local okLoad, load = pcall(function() return NPCWorkSchedulerBridge.GetLoadState(false) end)
        local level = okLoad and load and tonumber(load.level) or 0
        if level >= 3 then
            ttl = 780
        elseif level >= 2 then
            ttl = 560
        elseif level >= 1 then
            ttl = 440
        end
    end
    if now <= 0 or now - (tonumber(cache.ms) or 0) > ttl then return nil, false end
    if cache.maxDist and maxDist and tonumber(cache.maxDist) and tonumber(cache.maxDist) + 0.1 < tonumber(maxDist) then return nil, false end
    if not nbd_threatAlive(cache.threat) then return nil, false end
    return cache.threat, true
end

local function nbd_storeThreatCache(brain, maxDist, threat)
    if type(brain) ~= "table" then return threat end
    brain._threatCache = {ms = nbd_nowMs(), maxDist = maxDist, threat = threat}
    return threat
end

function NPCBrainDirectorBridge.FindNearestThreat(bandit, brain, maxDist, tacticalRadioSearchRadius)
    maxDist = maxDist or 28
    if NPCOrderContract and NPCOrderContract.CanAggro and not NPCOrderContract.CanAggro(brain) then
        if type(brain) == "table" then brain._threatCache = nil end
        return nil
    end

    local cached, hasCached = nbd_cachedThreat(brain, maxDist)
    if hasCached then return cached end

    if NPCAIVisionBridge and NPCAIVisionBridge.FindNearestThreat then
        local ok, threat = pcall(function()
            return NPCAIVisionBridge.FindNearestThreat(bandit, brain, maxDist, true)
        end)

        if ok then
            if threat then
                return nbd_storeThreatCache(brain, maxDist, threat)
            end
            if NPCTacticalRadioBridge and NPCTacticalRadioBridge.GetSharedThreat then
                local okRadio, radioThreat = pcall(function()
                    return NPCTacticalRadioBridge.GetSharedThreat(bandit, brain, tacticalRadioSearchRadius or maxDist or 46)
                end)
                if okRadio and radioThreat then return nbd_storeThreatCache(brain, maxDist, radioThreat) end
            end
            return nbd_storeThreatCache(brain, maxDist, nil)
        end
    end

    if not bandit or not NPCZombieCacheBridge or not NPCZombieCacheBridge.CacheLight then return nbd_storeThreatCache(brain, maxDist, nil) end

    local bx = bandit:getX()
    local by = bandit:getY()
    local bz = bandit:getZ()
    local best = nil
    local bestD2 = maxDist * maxDist

    local nearby = NPCZombieCacheBridge.CacheLight
    local nearbyCount = nil
    if NPCSpatialIndexBridge and NPCSpatialIndexBridge.GetNearbyAllInto then
        nearby = NPCBrainDirectorBridge._threatScratch or {}
        NPCBrainDirectorBridge._threatScratch = nearby
        local _, n = NPCSpatialIndexBridge.GetNearbyAllInto(nearby, bx, by, bz, maxDist, 96)
        nearbyCount = tonumber(n) or 0
        if NPCPerformanceTelemetryBridge and NPCPerformanceTelemetryBridge.Record then
            pcall(function() NPCPerformanceTelemetryBridge.Record("spatial_threat_query", 1) end)
        end
    elseif NPCSpatialIndexBridge and NPCSpatialIndexBridge.GetNearbyAll then
        nearby = NPCSpatialIndexBridge.GetNearbyAll(bx, by, bz, maxDist)
    end

    local function considerThreat(id, data)
        id = data and (data.id or id) or id
        if data and data.z == bz then
            local d2 = NPCBrainDirectorBridge.Dist2(bx, by, data.x, data.y)
            if d2 > 0.01 and d2 < bestD2 then
                local target = NPCZombieCacheBridge.Cache and NPCZombieCacheBridge.Cache[id]
                if target and NPCBrainDirectorBridge.IsAlive(target) then
                    local tBrain = data.brain or NPCBrainDirectorBridge.GetBrain(target)
                    local enemy = false
                    local kind = "zombie"

                    if not tBrain or not tBrain.clan then
                        enemy = true
                        kind = "zombie"
                    elseif brain and tBrain and brain.roadPatrol and tBrain.roadPatrol and brain.patrolColor and tBrain.patrolColor and brain.patrolColor ~= tBrain.patrolColor then
                        enemy = true
                        kind = "bandit"
                    elseif brain and tBrain and brain.battleEnemyGroupId and tBrain.worldGroupId and tostring(brain.battleEnemyGroupId) == tostring(tBrain.worldGroupId) then
                        enemy = true
                        kind = "bandit"
                    elseif NPCFactionBridge and NPCFactionBridge.IsEnabled and NPCFactionBridge.IsEnabled() and NPCFactionBridge.AreBrainsEnemies and NPCFactionBridge.AreBrainsEnemies(brain, tBrain) then
                        enemy = true
                        kind = "bandit"
                    elseif (not NPCFactionBridge or not NPCFactionBridge.IsEnabled or not NPCFactionBridge.IsEnabled()) and brain and brain.clan ~= tBrain.clan and (brain.hostile or tBrain.hostile) then
                        enemy = true
                        kind = "bandit"
                    end

                    if enemy then
                        local visible = true
                        local ok, canSee = pcall(function()
                            return bandit:CanSee(target)
                        end)
                        if ok then visible = canSee end

                        if visible then
                            bestD2 = d2
                            best = {
                                id = id,
                                x = data.x,
                                y = data.y,
                                z = data.z,
                                dist = math.sqrt(d2),
                                kind = kind,
                                target = target
                            }
                        end
                    end
                end
            end
        end
    end

    if nearbyCount then
        for i = 1, nearbyCount do
            considerThreat(nearby[i] and nearby[i].id or i, nearby[i])
        end
    else
        for id, data in pairs(nearby) do
            considerThreat(id, data)
        end
    end

    if best and NPCTacticalRadioBridge and NPCTacticalRadioBridge.ReportContact then
        pcall(function()
            NPCTacticalRadioBridge.ReportContact(bandit, brain, best.target, best.kind, best.dist, 1.0)
        end)
        return nbd_storeThreatCache(brain, maxDist, best)
    end

    if NPCTacticalRadioBridge and NPCTacticalRadioBridge.GetSharedThreat then
        local ok, radioThreat = pcall(function()
            return NPCTacticalRadioBridge.GetSharedThreat(bandit, brain, tacticalRadioSearchRadius or maxDist or 46)
        end)
        if ok and radioThreat then return nbd_storeThreatCache(brain, maxDist, radioThreat) end
    end

    return nbd_storeThreatCache(brain, maxDist, best)
end

function NPCBrainDirectorBridge.IsIndirectThreat(threat)
    if not threat then return false end
    if threat.memoryOnly == true then return true end
    if threat.canSee == false and threat.heard == true then return true end
    if threat.canSee == false and not threat.target then return true end
    return false
end

function NPCBrainDirectorBridge.InfluenceStimulus(bandit, brain)
    if not bandit or not brain then return nil end
    if not NPCInfluenceFieldBridge or not NPCInfluenceFieldBridge.GetLocalStimulus then return nil end
    local ok, stimulus = pcall(function()
        return NPCInfluenceFieldBridge.GetLocalStimulus(bandit:getX(), bandit:getY())
    end)
    if not ok or not stimulus then return nil end
    stimulus.z = stimulus.z or bandit:getZ()
    stimulus.dist = NPCBrainDirectorBridge.Dist(bandit:getX(), bandit:getY(), stimulus.x, stimulus.y)
    stimulus.updated = NPCBrainDirectorBridge.WorldAgeHours()
    return stimulus
end

function NPCBrainDirectorBridge.CountNearbyFriends(bandit, brain, radius)
    if not bandit or not brain or not NPCZombieCacheBridge or not NPCZombieCacheBridge.CacheLightB then return 0 end

    local bx = bandit:getX()
    local by = bandit:getY()
    local bz = bandit:getZ()
    local r2 = radius * radius
    local count = 0

    local nearby = NPCZombieCacheBridge.CacheLightB
    local nearbyCount = nil
    if NPCSpatialIndexBridge and NPCSpatialIndexBridge.GetNearbyNPCsInto then
        nearby = NPCBrainDirectorBridge._friendScratch or {}
        NPCBrainDirectorBridge._friendScratch = nearby
        local _, n = NPCSpatialIndexBridge.GetNearbyNPCsInto(nearby, bx, by, bz, radius, 64)
        nearbyCount = tonumber(n) or 0
        if NPCPerformanceTelemetryBridge and NPCPerformanceTelemetryBridge.Record then
            pcall(function() NPCPerformanceTelemetryBridge.Record("spatial_friend_query", 1) end)
        end
    elseif NPCSpatialIndexBridge and NPCSpatialIndexBridge.GetNearbyNPCs then
        nearby = NPCSpatialIndexBridge.GetNearbyNPCs(bx, by, bz, radius)
    elseif NPCSpatialIndexBridge then
        local legacyNearby = NPCSpatialIndexBridge["GetNearby" .. NPCLegacyContractBridge.Plural]
        if legacyNearby then nearby = legacyNearby(bx, by, bz, radius) end
    end

    local function considerFriend(data)
        if data and data.z == bz and data.brain and data.brain.clan == brain.clan then
            local d2 = NPCBrainDirectorBridge.Dist2(bx, by, data.x, data.y)
            if d2 > 0.01 and d2 < r2 then
                count = count + 1
            end
        end
    end

    if nearbyCount then
        for i = 1, nearbyCount do considerFriend(nearby[i]) end
    else
        for _, data in pairs(nearby) do considerFriend(data) end
    end

    return count
end

function NPCBrainDirectorBridge.UpdateWatchdog(bandit, brain, now)
    brain.fsm = brain.fsm or {}
    local fsm = brain.fsm
    fsm.watchdog = fsm.watchdog or {}

    local action = NPCBrainDirectorBridge.CurrentAction(bandit)
    local task = NPCBrainDirectorBridge.CurrentTask(bandit)
    local watchdog = fsm.watchdog

    if action ~= "Move" and action ~= "GoTo" then
        watchdog.startedAt = nil
        watchdog.x = nil
        watchdog.y = nil
        watchdog.dist2 = nil
        watchdog.angle = nil
        watchdog.spinScore = 0
        fsm.stuck = false
        return false
    end

    local x = bandit:getX()
    local y = bandit:getY()
    local dist2 = nil
    if task and task.x and task.y then
        dist2 = NPCBrainDirectorBridge.Dist2(x, y, task.x, task.y)
    end

    local angle = nil
    local okAngle, gotAngle = pcall(function()
        return bandit:getDirectionAngle()
    end)
    if okAngle then angle = gotAngle end

    if not watchdog.startedAt then
        watchdog.startedAt = now
        watchdog.progressAt = now
        watchdog.x = x
        watchdog.y = y
        watchdog.dist2 = dist2
        watchdog.angle = angle
        watchdog.spinScore = 0
        fsm.stuck = false
        return false
    end

    local moved2 = NPCBrainDirectorBridge.Dist2(x, y, watchdog.x or x, watchdog.y or y)
    local progressed = false
    if dist2 and watchdog.dist2 and dist2 < watchdog.dist2 - 0.10 then
        progressed = true
    elseif moved2 > 0.06 then
        progressed = true
    end

    if progressed then
        watchdog.startedAt = now
        watchdog.progressAt = now
        watchdog.x = x
        watchdog.y = y
        watchdog.dist2 = dist2
        watchdog.angle = angle
        watchdog.spinScore = math.max(0, (watchdog.spinScore or 0) - 1)
        fsm.stuck = false
        return false
    end

    if angle and watchdog.angle then
        local delta = math.abs(angle - watchdog.angle) % 360
        if delta > 180 then delta = 360 - delta end
        if delta > 85 and moved2 < 0.02 then
            watchdog.spinScore = (watchdog.spinScore or 0) + 1
        end
    end
    watchdog.angle = angle

    local elapsed = now - (watchdog.progressAt or watchdog.startedAt or now)
    local stuckFast = elapsed > 3200 and moved2 < 0.04
    local stuckSpin = (watchdog.spinScore or 0) >= 3 and elapsed > 1400
    local stuckNoProgress = elapsed > 4600 and dist2 and watchdog.dist2 and dist2 >= watchdog.dist2 - 0.05

    watchdog.x = x
    watchdog.y = y
    watchdog.dist2 = dist2 or watchdog.dist2

    if stuckFast or stuckSpin or stuckNoProgress then
        watchdog.stuckCount = (watchdog.stuckCount or 0) + 1
        watchdog.lastReason = stuckSpin and "spin loop" or "no path progress"
        fsm.stuck = true
        fsm.stuckCount = watchdog.stuckCount
        fsm.watchdogReason = watchdog.lastReason
        return true
    end

    fsm.stuck = false
    return false
end

function NPCBrainDirectorBridge.SetState(brain, state, reason, now)
    brain.fsm = brain.fsm or {}

    if brain.fsm.state ~= state then
        brain.fsm.previousState = brain.fsm.state
        brain.fsm.stateSince = now
        brain.fsm.transitions = (brain.fsm.transitions or 0) + 1
    end

    brain.fsm.state = state
    brain.fsm.reason = reason
    brain.fsm.updatedAt = now
    brain.state = state
    brain.reason = reason
end

function NPCBrainDirectorBridge.BaseZoneType(brain)
    if not brain then return nil end
    local zt = brain.homeBaseZoneType or brain.baseZoneType
    if zt then return tostring(zt) end
    return nil
end

function NPCBrainDirectorBridge.HasExplicitOrder(brain)
    local order = NPCBrainDirectorBridge.NormalizeOrder(NPCBrainDirectorBridge.GetOrder(brain))
    return order ~= nil and order ~= "" and order ~= "free"
end

function NPCBrainDirectorBridge.BaseDutyState(director, brain, health)
    if not director or not director.States then return nil end
    if not brain or brain.master or brain.mercenaryHired then return nil end
    if brain.inBattle or brain.virtualBattle then return nil end
    if NPCBrainDirectorBridge.HasExplicitOrder(brain) then return nil end

    local zt = NPCBrainDirectorBridge.BaseZoneType(brain)
    if not zt then return nil end

    if health and health < 0.70 then return director.States.HealSelf, "base duty: medical fallback" end
    if zt == "medical" then return director.States.HealSelf, "base duty: medical zone" end
    if zt == "ammo" then return director.States.ReloadWeapon, "base duty: ammo zone" end
    if zt == "food" then return director.States.EatDrink, "base duty: food zone" end
    if zt == "sleep" then return director.States.SleepRest, "base duty: sleep zone" end
    if zt == "storage" then return director.States.LootArea, "base duty: storage zone" end
    if zt == "guard" then return director.States.DefendBase, "base duty: guard post" end
    if zt == "patrol" then return director.States.PatrolArea, "base duty: patrol route" end
    if zt == "command" then return director.States.GuardArea, "base duty: command post" end
    if zt == "staging" then return director.States.ReturnToBase, "base duty: staging area" end

    return nil
end

function NPCBrainDirectorBridge.HasLoadedFirearm(brain)
    if not brain or not brain.weapons then return false end

    for _, slot in ipairs({"primary", "secondary"}) do
        local weapon = brain.weapons[slot]
        if weapon and weapon.name and tonumber(weapon.bulletsLeft or 0) and tonumber(weapon.bulletsLeft or 0) > 0 then
            return true
        end
    end

    return false
end

function NPCBrainDirectorBridge.ReloadSlot(brain)
    if not brain or not brain.weapons then return nil end

    for _, slot in ipairs({"primary", "secondary"}) do
        local weapon = brain.weapons[slot]
        if weapon and weapon.name then
            local bulletsLeft = tonumber(weapon.bulletsLeft or 0) or 0
            local magCount = tonumber(weapon.magCount or 0) or 0
            if bulletsLeft <= 0 and magCount > 0 then
                return slot
            end
        end
    end

    return nil
end

function NPCBrainDirectorBridge.HasReloadableFirearm(brain)
    return NPCBrainDirectorBridge.ReloadSlot(brain) ~= nil
end

function NPCBrainDirectorBridge.HasMelee(brain)
    return brain and brain.weapons and brain.weapons.melee ~= nil
end

function NPCBrainDirectorBridge.MakeTask(action, anim, time)
    return {action=action, anim=anim, time=time or 120, director=true}
end

function NPCBrainDirectorBridge.IdleTask(director, reason)
    local anims = {"ShiftWeight", "WipeBrow", "PullAtCollar", "ChewNails", "Cough"}
    local anim = anims[1 + ZombRand(#anims)]
    local task = NPCBrainDirectorBridge.MakeTask("Time", anim, 80 + ZombRand(80))
    task.directorState = director and director.States and director.States.Idle or "Idle"
    task.directorReason = reason or "idle"
    return task
end

function NPCBrainDirectorBridge.GetMoveTask(bandit, x, y, z, walkType, closeSlow)
    local bx = bandit:getX()
    local by = bandit:getY()
    local dist = NPCBrainDirectorBridge.Dist(bx, by, x, y)

    if NPCUtils and NPCUtils.GetMoveTask then
        local ok, task = pcall(function()
            return NPCUtils.GetMoveTask(0.01, x, y, z, walkType or "Run", dist, closeSlow)
        end)

        if ok and task then
            task.director = true
            return task
        end
    end

    return {
        action = "GoTo",
        time = 50,
        endurance = 0.01,
        x = x,
        y = y,
        z = z,
        walkType = walkType or "Run",
        closeSlow = closeSlow,
        director = true
    }
end

function NPCBrainDirectorBridge.MasterPlayer(bandit, brain)
    if NPCPlayerClient and NPCPlayerClient.GetMasterPlayer then
        local ok, master = pcall(function()
            return NPCPlayerClient.GetMasterPlayer(bandit)
        end)
        if ok and master then return master end
    end

    if brain and brain.master and NPCPlayerClient and NPCPlayerClient.GetPlayerById then
        local ok, master = pcall(function()
            return NPCPlayerClient.GetPlayerById(brain.master)
        end)
        if ok and master then return master end
    end

    if getPlayer then return getPlayer() end
    return nil
end

function NPCBrainDirectorBridge.MoveToState(bandit, state, reason, x, y, z, walkType, closeSlow)
    local brain = NPCBrainDirectorBridge.GetBrain(bandit)
    local finalX = x
    local finalY = y
    local finalZ = z or bandit:getZ()

    if NPCRoadNavBridge and NPCRoadNavBridge.AdjustMoveTarget and brain then
        local adjustedX, adjustedY, adjustedZ = NPCRoadNavBridge.AdjustMoveTarget(bandit, brain, state, reason, x, y, z or bandit:getZ())
        x = adjustedX or x
        y = adjustedY or y
        z = adjustedZ or z
        finalX = x
        finalY = y
        finalZ = z or bandit:getZ()
    end

    local chained = false
    if NPCRoadNavBridge and NPCRoadNavBridge.GetChainedMoveTarget and brain then
        local chainX, chainY, chainZ, isChained, routeX, routeY, routeZ = NPCRoadNavBridge.GetChainedMoveTarget(bandit, brain, state, reason, x, y, z or bandit:getZ())
        if isChained then
            x = chainX or x
            y = chainY or y
            z = chainZ or z
            finalX = routeX or finalX
            finalY = routeY or finalY
            finalZ = routeZ or finalZ
            chained = true
        end
    end

    local resolvedByWatchdog = false
    if NPCMovementStabilityBridge and NPCMovementStabilityBridge.ResolveMoveTarget and brain then
        local okResolve, rx, ry, rz, changed = pcall(function()
            return NPCMovementStabilityBridge.ResolveMoveTarget(bandit, brain, state, reason, x, y, z or bandit:getZ())
        end)
        if okResolve and rx and ry then
            x = rx
            y = ry
            z = rz or z
            resolvedByWatchdog = changed == true
        end
    end

    local task = NPCBrainDirectorBridge.GetMoveTask(bandit, x, y, z or bandit:getZ(), walkType or "Run", closeSlow)
    task.directorState = state
    task.directorReason = reason
    if brain and (brain.master ~= nil or brain.mercenaryHired == true or brain.hired == true or brain.isPlayerGuard == true) then
        local order = type(brain.order) == "table" and brain.order or nil
        if order and (order.source == "player" or order.master ~= nil or order.interrupt == true) then
            task.playerOrder = true
            task.allowOrderTeleport = true
            task.orderName = order.name
            task.orderIssued = order.issued
            task.orderTeleportAfterMs = task.orderTeleportAfterMs or 950
        end
    end
    if resolvedByWatchdog then task.watchdogResolvedTarget = true end
    if brain and (brain.roadPatrol or brain.roadBias or brain.preferRoads) then
        task.roadBiased = true
        task.roadPatrol = brain.roadPatrol or false
    end
    if chained then
        task.roadChained = true
        task.roadFinalX = finalX
        task.roadFinalY = finalY
        task.roadFinalZ = finalZ
    end
    return task
end

function NPCBrainDirectorBridge.ReloadTasks(bandit, brain, state, reason)
    local slot = NPCBrainDirectorBridge.ReloadSlot(brain)
    if not slot then return nil end

    if NPCPrograms and NPCPrograms.Weapon and NPCPrograms.Weapon.Reload then
        local ok, tasks = pcall(function()
            return NPCPrograms.Weapon.Reload(bandit, slot)
        end)
        if ok and tasks and #tasks > 0 then
            for _, task in pairs(tasks) do
                task.directorState = state
                task.directorReason = reason
            end
            return tasks
        end
    end

    return {
        {
            action = "Reload",
            anim = "ReloadRifle",
            slot = slot,
            time = 90,
            director = true,
            directorState = state,
            directorReason = reason
        }
    }
end

function NPCBrainDirectorBridge.FindContainerSquare(director, bandit, radius)
    if not bandit then return nil end
    radius = radius or (director and director.Config and director.Config.lootScanRadius) or 8

    if NPCLootTargetCacheBridge and NPCLootTargetCacheBridge.FindContainerSquare then
        local brain = NPCBrainDirectorBridge.GetBrain(bandit)
        local ok, square = pcall(function()
            return NPCLootTargetCacheBridge.FindContainerSquare(bandit, radius, {
                brain = brain,
                need = "any",
                ttlMs = 5200,
                maxSquareChecks = 150,
                maxObjectChecks = 16
            })
        end)
        if ok and square then return square end
    end

    local cell = getCell()
    if not cell then return nil end

    local bx = math.floor(bandit:getX())
    local by = math.floor(bandit:getY())
    local bz = math.floor(bandit:getZ())

    for r=0, radius do
        for dx=-r, r do
            for dy=-r, r do
                if r == 0 or math.abs(dx) == r or math.abs(dy) == r then
                    local square = cell:getGridSquare(bx + dx, by + dy, bz)
                    if square then
                        local objects = square:getObjects()
                        if objects then
                            for i=0, math.min(objects:size() - 1, 15) do
                                local obj = objects:get(i)
                                local container = obj and obj:getContainer()
                                if container and not container:isEmpty() then
                                    return square
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return nil
end


function NPCBrainDirectorBridge.InferState(director, runtime, bandit, brain, generatedTasks)
    if not director or not runtime then return nil, "no runtime" end
    if not bandit or not brain then return director.States.Disabled, "no brain" end
    if not runtime.isAlive(bandit) then return director.States.Dead, "dead" end

    local action = runtime.firstTaskAction(generatedTasks) or runtime.currentAction(bandit)
    local order = runtime.normalizeOrder(runtime.getOrder(brain))
    local programName = runtime.getProgramName(brain)
    if NPCOrderContract and NPCOrderContract.CanAggro and not NPCOrderContract.CanAggro(brain) and (action == "Shoot" or action == "Aim" or action == "Hit" or action == "Shove" or action == "Reload") then
        action = nil
    end
    local health = runtime.health01(bandit)

    if action == "Shoot" or action == "Aim" then
        return director.States.Attack, "legacy combat task"
    elseif action == "Hit" or action == "Shove" then
        return director.States.EmergencyDefense, "legacy melee task"
    elseif action == "Reload" then
        return director.States.ReloadWeapon, "legacy reload task"
    elseif action == "Move" or action == "GoTo" then
        if order == "follow" or programName == "Companion" then
            return director.States.FollowPlayer, "legacy follow movement"
        elseif order == "guard" or programName == "BaseGuard" or programName == "CompanionGuard" then
            return director.States.GuardArea, "legacy guard movement"
        elseif order == "loot" or programName == "Looter" then
            return director.States.LootArea, "legacy looter movement"
        elseif order == "return" then
            return director.States.ReturnToBase, "legacy return movement"
        end
        return director.States.Moving, "legacy movement"
    elseif health < 0.45 then
        return director.States.HealSelf, "low health observed"
    elseif order == "follow" or programName == "Companion" then
        return director.States.FollowPlayer, "order/program"
    elseif order == "hold" then
        return director.States.HoldPosition, "order"
    elseif order == "guard" or programName == "CompanionGuard" then
        if brain.master and not (brain.order and brain.order.anchor and brain.order.anchor.x) then return director.States.GuardPlayer, "bodyguard order/program" end
        return director.States.GuardArea, "order/program"
    elseif order == "patrol" then
        return director.States.PatrolArea, "order"
    elseif order == "loot" or programName == "Looter" then
        return director.States.LootArea, "order/program"
    elseif order == "return" then
        return director.States.ReturnToBase, "order"
    elseif order == "sleep" then
        return director.States.SleepRest, "order"
    elseif order == "eat" then
        return director.States.EatDrink, "order"
    elseif programName == "BaseGuard" then
        return director.States.DefendBase, "program"
    elseif programName == "Raider" or programName == NPC_BRAIN_DIRECTOR_LEGACY_KEYS.programNPC or programName == "Thief" then
        return director.States.PatrolArea, "program"
    end

    return director.States.Idle, "idle"
end

function NPCBrainDirectorBridge.IsWoundedLocked(brain)
    return type(brain) == "table" and brain.wounded == true and brain.woundedDowned == true and brain.woundedState == "downed"
end

function NPCBrainDirectorBridge.IsNonCombatAction(action)
    if action == nil then return false end
    if NPCBrainDirectorBridge.IsCombatAction(action) then return false end
    action = tostring(action)
    return action == "Time"
        or action == "FaceLocation"
        or action == "Loot"
        or action == "LootLow"
        or action == "Forage"
        or action == "Sleep"
        or action == "Smoke"
        or action == "Eat"
        or action == "Drink"
        or action == "Bandage"
end

function NPCBrainDirectorBridge.ClearNonCombatTaskForThreat(bandit, brain, threat)
    if not (bandit and brain and threat) then return false end
    if not NPCEntity then return false end
    local task = NPCEntity.GetTask and NPCEntity.GetTask(bandit) or nil
    local action = task and task.action or NPCBrainDirectorBridge.CurrentAction(bandit)
    if not NPCBrainDirectorBridge.IsNonCombatAction(action) then return false end
    if NPCEntity.ClearTasks then NPCEntity.ClearTasks(bandit) end
    brain.squadReactiveAt = NPCBrainDirectorBridge.Now()
    brain.squadReactiveReason = "threat interrupted non-combat action"
    return true
end

function NPCBrainDirectorBridge.IsPlayerControlled(brain)
    if not brain then return false end
    if brain.master ~= nil or brain.mercenaryHired == true or brain.hired == true or brain.isPlayerGuard == true then return true end
    local order = brain.order or brain.directorOrder
    if type(order) == "table" then
        local name = order.name or order.action or order.type or order.mode
        return name ~= nil and tostring(name) ~= "" and tostring(name):lower() ~= "free"
    end
    return order ~= nil and tostring(order) ~= "" and tostring(order):lower() ~= "free"
end

function NPCBrainDirectorBridge.IntentOwnerForState(director, brain, state, reason, threat)
    if not director then return "ambient", 20, 3500 end
    reason = tostring(reason or "")
    local lowerReason = reason:lower()
    if state == director.States.Dead or state == director.States.Disabled then return "dead", 100, 12000 end
    if NPCBrainDirectorBridge.IsPlayerControlled(brain) then return "player_order", 88, 5200 end
    if threat or state == director.States.Attack or state == director.States.EmergencyDefense or state == director.States.KeepDistance or state == director.States.MeleeFallback or state == director.States.ReloadCover or state == director.States.SearchEnemy then
        return "combat", 95, 5600
    end
    if state == director.States.RecoverPath then return "active_task", 68, 4200 end
    if state == director.States.Regroup or lowerReason:find("squad", 1, true) or lowerReason:find("cohesion", 1, true) then return "squad_cohesion", 50, 9000 end
    if state == director.States.DefendBase or lowerReason:find("base", 1, true) then return "base_life", 34, 9000 end
    if lowerReason:find("routine", 1, true) or lowerReason:find("scavenge", 1, true) or lowerReason:find("sweep", 1, true) then return "world_routine", 32, 12000 end
    if state == director.States.LootArea or lowerReason:find("supply", 1, true) or lowerReason:find("loot", 1, true) then return "supply_need", 31, 9000 end
    if state == director.States.PatrolArea then return "living_move", 28, 9000 end
    return "living_ambient", 22, 6200
end

function NPCBrainDirectorBridge.RequestIntentOwner(director, runtime, bandit, brain, state, reason, threat)
    if not brain then return false, "no brain" end
    if not (NPCIntentArbiterBridge and NPCIntentArbiterBridge.Request) then return true, "no arbiter" end
    local owner, priority, ttlMs = NPCBrainDirectorBridge.IntentOwnerForState(director, brain, state, reason, threat)
    local ok = NPCIntentArbiterBridge.Request(bandit, brain, owner, reason or owner, {
        priority = priority,
        ttlMs = ttlMs
    })
    return ok == true, owner
end

function NPCBrainDirectorBridge.MarkIntentTasks(director, brain, tasks, state, reason, threat)
    if not tasks then return tasks end
    if NPCIntentArbiterBridge and NPCIntentArbiterBridge.MarkTasks then
        local owner = NPCBrainDirectorBridge.IntentOwnerForState(director, brain, state, reason, threat)
        return NPCIntentArbiterBridge.MarkTasks(tasks, owner, reason)
    end
    return tasks
end

function NPCBrainDirectorBridge.EvaluateDesiredState(director, runtime, bandit, brain, threat, stuck)
    if not director or not runtime then return nil, "no runtime" end
    if not bandit or not brain then return director.States.Disabled, "no brain" end
    if not runtime.isAlive(bandit) then return director.States.Dead, "dead" end
    if NPCBrainDirectorBridge.IsWoundedLocked(brain) then return director.States.Disabled, "wounded downed" end

    local order = runtime.normalizeOrder(runtime.getOrder(brain))
    local programName = runtime.getProgramName(brain)
    if NPCOrderContract and NPCOrderContract.CanAggro and not NPCOrderContract.CanAggro(brain) then
        if not NPCBrainDirectorBridge.IsStrictCloseDefenseThreat(threat) then threat = nil end
    end
    if threat and NPCOrderContract and NPCOrderContract.ShouldIgnoreThreatForStrictOrder and NPCOrderContract.ShouldIgnoreThreatForStrictOrder(brain, threat) then
        threat = nil
    end
    local health = runtime.health01(bandit)
    local humanAwareness = nil
    if NPCHumanizedAIBridge and NPCHumanizedAIBridge.UpdateAwareness then
        local okHuman, h = pcall(function()
            return NPCHumanizedAIBridge.UpdateAwareness(bandit, brain, threat)
        end)
        if okHuman then humanAwareness = h end
    end

    if NPCUtilityAIBridge and NPCUtilityAIBridge.Update then
        pcall(function()
            NPCUtilityAIBridge.Update(bandit, brain, nil, threat)
        end)
    end

    if stuck then return director.States.RecoverPath, "path watchdog" end

    local strictOrderName = NPCBrainDirectorBridge.GetStrictOrderName(brain)
    if strictOrderName then
        if NPCBrainDirectorBridge.IsStrictCloseDefenseThreat(threat) then
            return director.States.EmergencyDefense, "strict order close defense"
        end
        if threat and health < 0.35 then
            return director.States.Flee, "strict order low health threat"
        end
        local strictState = NPCBrainDirectorBridge.StrictStateForOrder(director, brain, strictOrderName)
        if strictState then
            return strictState, "strict " .. tostring(strictOrderName) .. " discipline"
        end
    end

    local playerCommandOrderName = NPCBrainDirectorBridge.GetPlayerCommandOrderName(brain)
    if playerCommandOrderName then
        if NPCBrainDirectorBridge.IsStrictCloseDefenseThreat(threat) then
            return director.States.EmergencyDefense, "player command close defense"
        end
        if threat and health < 0.35 then
            return director.States.Flee, "player command low health threat"
        end
        local commandState = NPCBrainDirectorBridge.PlayerCommandStateForOrder(director, brain, playerCommandOrderName)
        if commandState then
            return commandState, "player command " .. tostring(playerCommandOrderName)
        end
    end

    if threat and runtime.isIndirectThreat(threat) and (not threat.dist or threat.dist > 1.35) then
        local suffix = "last known threat"
        if humanAwareness and humanAwareness.lastStimulus then suffix = humanAwareness.lastStimulus end
        return director.States.SearchEnemy, "investigate " .. tostring(suffix)
    end

    if threat and threat.canSee == true and threat.memoryOnly ~= true and threat.dist and threat.dist > 14 and humanAwareness and humanAwareness.awarenessState ~= "combat" and humanAwareness.awarenessState ~= "alert" then
        return director.States.SearchEnemy, "verify distant contact"
    end

    if NPCSquadDynamicsBridge and NPCSquadDynamicsBridge.ChooseState then
        local ok, squadState, squadReason = pcall(function()
            return NPCSquadDynamicsBridge.ChooseState(bandit, brain, threat, director.States)
        end)
        if ok and squadState then
            return squadState, squadReason or "squad dynamic maneuver"
        end
    end

    if threat and NPCTacticalRadioBridge and NPCTacticalRadioBridge.ChooseTacticalState then
        local ok, tacticalState, tacticalReason = pcall(function()
            return NPCTacticalRadioBridge.ChooseTacticalState(bandit, brain, threat, director.States)
        end)
        if ok and tacticalState then
            return tacticalState, tacticalReason or "radio tactical maneuver"
        end
    end

    if NPCUtilityAIBridge and NPCUtilityAIBridge.EvaluateTacticalState then
        local ok, utilityState, utilityReason = pcall(function()
            return NPCUtilityAIBridge.EvaluateTacticalState(bandit, brain, threat, health)
        end)
        if ok and utilityState and director.States[utilityState] then
            return director.States[utilityState], utilityReason or "utility tactical"
        end
    end

    if threat and threat.dist <= 1.35 then
        return director.States.EmergencyDefense, "enemy in bite range"
    end

    if threat and health < 0.35 then
        return director.States.Flee, "low health with threat"
    end

    if threat and runtime.hasLoadedFirearm(brain) and threat.dist < director.Config.keepDistance then
        return director.States.KeepDistance, "preserve firearm distance"
    end

    if threat and runtime.hasLoadedFirearm(brain) then
        return director.States.Attack, "legacy firearm attack"
    end

    if threat and runtime.hasReloadableFirearm(brain) then
        return director.States.ReloadCover, "reload with nearby threat"
    end

    if threat and runtime.hasMelee(brain) then
        return director.States.MeleeFallback, "legacy melee fallback"
    end

    if health < 0.45 then
        return director.States.HealSelf, "low health"
    end

    if runtime.hasReloadableFirearm(brain) then
        return director.States.ReloadWeapon, "proactive reload"
    end

    if not threat and runtime.worldRoutineSuggestState then
        local routineState, routineReason = runtime.worldRoutineSuggestState(bandit, brain, threat, health, order, programName)
        if routineState then return routineState, routineReason or "world routine" end
    end

    if not threat and runtime.livingSuggestState then
        local livingState, livingReason = runtime.livingSuggestState(bandit, brain, threat, health, order, programName)
        if livingState then return livingState, livingReason or "living intent" end
    end

    if not threat and (not order or order == "") then
        local stimulus = runtime.influenceStimulus(bandit, brain)
        if stimulus and stimulus.dist and stimulus.dist > 2.0 then
            brain.fsm = brain.fsm or {}
            brain.fsm.lastKnownEnemyPosition = stimulus
            brain.radioThreat = brain.radioThreat or stimulus
            return director.States.SearchEnemy, "investigate influence field"
        end
    end

    if order == "follow" or programName == "Companion" then
        return director.States.FollowPlayer, "follow"
    elseif order == "hold" then
        return director.States.HoldPosition, "hold"
    elseif order == "guard" or programName == "CompanionGuard" then
        if brain.master then return director.States.GuardPlayer, "bodyguard guard" end
        return director.States.GuardArea, "guard"
    elseif order == "patrol" then
        return director.States.PatrolArea, "patrol"
    elseif order == "loot" or programName == "Looter" then
        return director.States.LootArea, "loot"
    elseif order == "return" then
        return director.States.ReturnToBase, "return"
    elseif order == "sleep" then
        return director.States.SleepRest, "sleep"
    elseif order == "eat" then
        return director.States.EatDrink, "eat"
    end

    if not threat and NPCGOAPLiteBridge and NPCGOAPLiteBridge.SuggestState then
        local okPlan, planState, planReason = pcall(function() return NPCGOAPLiteBridge.SuggestState(bandit, brain, director.States) end)
        if okPlan and planState then return planState, planReason or "goap-lite" end
    end

    local baseState, baseReason = runtime.baseDutyState(brain, health)
    if baseState then
        return baseState, baseReason or "base zone duty"
    end

    if NPCUtilityAIBridge and NPCUtilityAIBridge.EvaluateAutonomyState then
        local ok, utilityState, utilityReason = pcall(function()
            return NPCUtilityAIBridge.EvaluateAutonomyState(bandit, brain, order, programName)
        end)
        if ok and utilityState and director.States[utilityState] then
            return director.States[utilityState], utilityReason or "utility autonomy"
        end
    end

    if programName == "BaseGuard" then
        return director.States.DefendBase, "defend base"
    elseif programName == "Raider" or programName == NPC_BRAIN_DIRECTOR_LEGACY_KEYS.programNPC or programName == "Thief" then
        return director.States.PatrolArea, "roaming combat program"
    end

    return director.States.Idle, "idle"
end

function NPCBrainDirectorBridge.Observe(director, runtime, bandit, uTick, generatedTasks)
    if not director or not runtime then return nil end

    local brain = runtime.getBrain(bandit)
    if not brain then return nil end

    local now = runtime.now()
    local threat = runtime.findNearestThreat(bandit, brain, 28)
    if NPCOrderContract and NPCOrderContract.CanAggro and not NPCOrderContract.CanAggro(brain) then threat = nil end
    if threat and NPCOrderContract and NPCOrderContract.ShouldIgnoreThreatForStrictOrder and NPCOrderContract.ShouldIgnoreThreatForStrictOrder(brain, threat) then threat = nil end
    if threat and NPCSpyBridge and NPCSpyBridge.TryDefectOnThreat then
        local ok, defected = pcall(function() return NPCSpyBridge.TryDefectOnThreat(bandit, brain, threat) end)
        if ok and defected then threat = nil end
    end
    if runtime.livingUpdateCombatMemory then
        runtime.livingUpdateCombatMemory(bandit, brain, threat)
    end
    if threat and NPCInfluenceFieldBridge and NPCInfluenceFieldBridge.InjectBrainThreat then
        pcall(function() NPCInfluenceFieldBridge.InjectBrainThreat(bandit, brain, threat) end)
    end
    local state, reason = NPCBrainDirectorBridge.InferState(director, runtime, bandit, brain, generatedTasks)

    brain.fsm = brain.fsm or {}
    brain.fsm.health = runtime.health01(bandit)
    brain.fsm.order = runtime.normalizeOrder(runtime.getOrder(brain))
    brain.fsm.programName = runtime.getProgramName(brain)
    brain.fsm.currentTask = runtime.currentAction(bandit)
    brain.fsm.generatedTask = runtime.firstTaskAction(generatedTasks)
    brain.fsm.hasLoadedFirearm = runtime.hasLoadedFirearm(brain)
    brain.fsm.hasReloadableFirearm = runtime.hasReloadableFirearm(brain)
    brain.fsm.hasMelee = runtime.hasMelee(brain)
    brain.fsm.nearFriends = runtime.countNearbyFriends(bandit, brain, 4)

    if threat then
        brain.fsm.targetId = threat.id
        brain.fsm.targetKind = threat.kind
        brain.fsm.targetDist = threat.dist
        brain.fsm.targetMemoryOnly = threat.memoryOnly == true
        brain.fsm.targetCanSee = threat.canSee
        brain.fsm.targetHeard = threat.heard
        brain.fsm.lastKnownEnemyPosition = {x=threat.x, y=threat.y, z=threat.z, updated=runtime.worldAgeHours(), kind=threat.kind, memoryOnly=threat.memoryOnly == true, canSee=threat.canSee, heard=threat.heard}
        brain.targetId = threat.id
        brain.targetKind = threat.kind
        brain.targetDist = threat.dist
    else
        brain.fsm.targetId = nil
        brain.fsm.targetKind = nil
        brain.fsm.targetDist = nil
        brain.fsm.targetMemoryOnly = nil
        brain.fsm.targetCanSee = nil
        brain.fsm.targetHeard = nil
        brain.targetId = nil
        brain.targetKind = nil
        brain.targetDist = nil
    end

    if NPCHumanizedAIBridge and NPCHumanizedAIBridge.UpdateAwareness then
        pcall(function()
            NPCHumanizedAIBridge.UpdateAwareness(bandit, brain, threat)
        end)
    end

    if NPCUtilityAIBridge and NPCUtilityAIBridge.Update then
        pcall(function()
            NPCUtilityAIBridge.Update(bandit, brain, uTick, threat)
        end)
    end
    if NPCTacticalRadioBridge and NPCTacticalRadioBridge.Tick then
        pcall(function()
            NPCTacticalRadioBridge.Tick(bandit, brain, uTick, threat)
        end)
    end
    if NPCSquadDynamicsBridge and NPCSquadDynamicsBridge.Tick then
        pcall(function()
            NPCSquadDynamicsBridge.Tick(bandit, brain, uTick, threat)
        end)
    end
    if NPCSquadDynamicsBridge and NPCSquadDynamicsBridge.Debug then
        pcall(function()
            NPCSquadDynamicsBridge.Debug(brain)
        end)
    end
    if NPCTacticalRadioBridge and NPCTacticalRadioBridge.Debug then
        pcall(function()
            NPCTacticalRadioBridge.Debug(brain)
        end)
    end

    local stuck = runtime.updateWatchdog(bandit, brain, now)
    if stuck and state ~= director.States.Attack and state ~= director.States.EmergencyDefense then
        state = director.States.RecoverPath
        reason = "path watchdog observed"
    end

    runtime.setState(brain, state, reason, now)

    return brain.fsm
end

function NPCBrainDirectorBridge.HandleIdle(director, runtime, bandit, brain, state, reason)
    if not runtime or not runtime.idleTask then return {} end
    return {runtime.idleTask(reason or "idle")}
end

function NPCBrainDirectorBridge.HandleFollowPlayer(director, runtime, bandit, brain)
    if not director or not runtime then return {} end

    local player = runtime.masterPlayer(bandit, brain)
    if not player then return NPCBrainDirectorBridge.HandleIdle(director, runtime, bandit, brain, director.States.Idle, "no master") end

    local order = brain.order or {}
    local strictOrderName = NPCBrainDirectorBridge.GetStrictOrderName(brain)
    local strictFollow = strictOrderName == "Follow" or strictOrderName == "FallBack" or strictOrderName == "Return"
    local followDistance = tonumber(order.followDistance) or director.Config.followDistance
    if strictFollow then
        followDistance = tonumber(order.followDistance) or 0.95
        if followDistance < 0.75 then followDistance = 0.75 end
        if followDistance > 2.4 then followDistance = 2.4 end
    end
    local dist = runtime.dist(bandit:getX(), bandit:getY(), player:getX(), player:getY())
    local zdist = math.abs((tonumber(bandit:getZ()) or 0) - (tonumber(player:getZ()) or 0))
    local tx, ty, tz = runtime.followFormationPoint(player, brain, bandit)
    if strictFollow and tx and ty then
        tx, ty, tz = NPCBrainDirectorBridge.StabilizeStrictSlot(brain, "followPlayer", player:getX(), player:getY(), player:getZ(), tx, ty, tz, {
            anchorDelta = (player:isRunning() or player:isSprinting()) and 0.45 or 0.28,
            targetDelta = (player:isRunning() or player:isSprinting()) and 0.55 or 0.38,
            maxAgeMs = (player:isRunning() or player:isSprinting()) and 420 or 650
        })
    end
    local slotDist = tx and ty and runtime.dist(bandit:getX(), bandit:getY(), tx, ty) or dist
    local leash = NPCBrainDirectorBridge.GetStrictLeash(brain, "follow", 3.6) or 3.6
    local moveThreshold = strictFollow and ((player:isRunning() or player:isSprinting()) and 0.95 or 0.72) or followDistance
    if dist > followDistance or slotDist > moveThreshold or (strictFollow and (dist > leash or zdist > 0.35)) then
        local walkType = "Run"
        if strictFollow and dist <= 2.6 and slotDist <= 1.65 and zdist <= 0.35 and not (player:isRunning() or player:isSprinting()) then
            walkType = player:isSneaking() and "SneakWalk" or "Walk"
        end
        local task = runtime.moveToState(bandit, director.States.FollowPlayer, strictFollow and "strict follow master stable slot" or "follow master formation", tx, ty, tz, walkType, true)
        if strictFollow then
            task.strictPlayerOrder = true
            task.strictOrderName = strictOrderName
            local arrive = tonumber(task.arriveDist) or 0.95
            if arrive < 0.68 then arrive = 0.68 end
            if arrive > 1.05 then arrive = 1.05 end
            task.arriveDist = arrive
        end
        return {task}
    end

    return {runtime.idleTask(strictFollow and "strict near master" or "near master")}
end

function NPCBrainDirectorBridge.HandleGuardPlayer(director, runtime, bandit, brain)
    if not director or not runtime then return {} end

    local player = runtime.masterPlayer(bandit, brain)
    if not player then return NPCBrainDirectorBridge.HandleIdle(director, runtime, bandit, brain, director.States.Idle, "no guarded player") end

    local strictGuard = NPCBrainDirectorBridge.GetStrictOrderName(brain) == "Guard"
    local dist = runtime.dist(bandit:getX(), bandit:getY(), player:getX(), player:getY())
    local zdist = math.abs((tonumber(bandit:getZ()) or 0) - (tonumber(player:getZ()) or 0))
    if strictGuard then
        local order = brain.order or {}
        local guardRadius = tonumber(order.followDistance) or 3.5
        if guardRadius < 2.5 then guardRadius = 2.5 end
        if guardRadius > 6.0 then guardRadius = 6.0 end
        local tx, ty, tz = runtime.offsetPoint(player:getX(), player:getY(), player:getZ(), guardRadius, (NPCUtils.GetCharacterID(bandit) or 1) * 17)
        if tx and ty then
            tx, ty, tz = NPCBrainDirectorBridge.StabilizeStrictSlot(brain, "guardPlayer", player:getX(), player:getY(), player:getZ(), tx, ty, tz, {
                anchorDelta = 1.15,
                targetDelta = 1.35,
                maxAgeMs = 3200
            })
        end
        local slotDist = tx and ty and runtime.dist(bandit:getX(), bandit:getY(), tx, ty) or dist
        local leash = NPCBrainDirectorBridge.GetStrictLeash(brain, "guard", 9.5) or 9.5
        if dist > leash or slotDist > 1.80 or zdist > 0.35 then
            local task = runtime.moveToState(bandit, director.States.GuardPlayer, "strict guard player stable perimeter", tx, ty, tz, dist > 4.0 and "Run" or "Walk", true)
            task.strictPlayerOrder = true
            task.strictOrderName = "Guard"
            local arrive = tonumber(task.arriveDist) or 1.05
            if arrive < 0.95 then arrive = 0.95 end
            if arrive > 1.20 then arrive = 1.20 end
            task.arriveDist = arrive
            return {task}
        end
        return {runtime.idleTask("strict guard player")}
    end

    if dist > director.Config.guardPlayerDistance then
        local tx, ty, tz = runtime.offsetPoint(player:getX(), player:getY(), player:getZ(), 4 + ZombRand(3), (NPCUtils.GetCharacterID(bandit) or 1) * 17)
        return {runtime.moveToState(bandit, director.States.GuardPlayer, "guard player perimeter", tx, ty, tz, "Run", true)}
    end

    if ZombRand(3) == 0 then
        local tx, ty, tz = runtime.offsetPoint(player:getX(), player:getY(), player:getZ(), 3 + ZombRand(4), ZombRand(628))
        return {runtime.moveToState(bandit, director.States.GuardPlayer, "shift guard angle", tx, ty, tz, "Walk", true)}
    end

    return {runtime.idleTask("guard player")}
end

function NPCBrainDirectorBridge.HandleHoldPosition(director, runtime, bandit, brain)
    if not director or not runtime then return {} end

    local strictHold = NPCBrainDirectorBridge.GetStrictOrderName(brain) == "Hold"
    if strictHold and NPCOrderContract and NPCOrderContract.GetAnchor then
        local ax, ay, az = NPCOrderContract.GetAnchor(brain, bandit)
        if ax and ay then brain.holdPoint = {x=ax, y=ay, z=az or bandit:getZ()} end
    end
    brain.holdPoint = brain.holdPoint or {x=bandit:getX(), y=bandit:getY(), z=bandit:getZ()}
    local x, y, z = runtime.formationAnchor(brain, bandit, "holdPoint")
    local dist = runtime.dist(bandit:getX(), bandit:getY(), x, y)
    local zdist = math.abs((tonumber(bandit:getZ()) or 0) - (tonumber(z) or 0))
    local radius = director.Config.holdRadius
    if strictHold then radius = math.min(NPCBrainDirectorBridge.GetStrictLeash(brain, "hold", 2.2) or 2.2, 2.2) end

    if dist > radius or (strictHold and zdist > 0.35) then
        local task = runtime.moveToState(bandit, director.States.HoldPosition, strictHold and "strict return to hold point" or "return to hold point", x, y, z, dist > 4 and "Run" or "Walk", true)
        if strictHold then
            task.strictPlayerOrder = true
            task.strictOrderName = "Hold"
            task.arriveDist = math.min(tonumber(task.arriveDist) or 0.9, 0.7)
        end
        return {task}
    end

    return {runtime.idleTask(strictHold and "strict hold position" or "hold position")}
end

function NPCBrainDirectorBridge.HandleGuardArea(director, runtime, bandit, brain, state, radius)
    if not director or not runtime then return {} end

    local strictGuard = NPCBrainDirectorBridge.GetStrictOrderName(brain) == "Guard"
    local x, y, z = runtime.formationAnchor(brain, bandit, "guardPoint")
    local dist = runtime.dist(bandit:getX(), bandit:getY(), x, y)
    local zdist = math.abs((tonumber(bandit:getZ()) or 0) - (tonumber(z) or 0))
    radius = radius or director.Config.guardRadius
    if strictGuard then radius = math.min(NPCBrainDirectorBridge.GetStrictLeash(brain, "guard", radius) or radius, 4.0) end

    if dist > radius or (strictGuard and zdist > 0.35) then
        local task = runtime.moveToState(bandit, state or director.States.GuardArea, strictGuard and "strict return to guarded area" or "return to guarded area", x, y, z, dist > 6 and "Run" or "Walk", true)
        if strictGuard then
            task.strictPlayerOrder = true
            task.strictOrderName = "Guard"
            local arrive = tonumber(task.arriveDist) or 0.95
            if arrive < 0.85 then arrive = 0.85 end
            if arrive > 1.05 then arrive = 1.05 end
            task.arriveDist = arrive
        end
        return {task}
    end

    if strictGuard then
        return {runtime.idleTask("strict guard area")}
    end

    if ZombRand(4) == 0 then
        local tx, ty, tz = runtime.offsetPoint(x, y, z, 2 + ZombRand(math.max(3, math.floor(radius / 2))), ZombRand(628))
        return {runtime.moveToState(bandit, state or director.States.GuardArea, "patrol guarded area", tx, ty, tz, "Walk", true)}
    end

    return {runtime.idleTask("guard area")}
end

function NPCBrainDirectorBridge.HandlePatrolArea(director, runtime, bandit, brain)
    if not director or not runtime then return {} end

    brain.fsm = brain.fsm or {}

    if NPCSquadDynamicsBridge and NPCSquadDynamicsBridge.GetPatrolPoint then
        local okSquad, squadPoint = pcall(function()
            return NPCSquadDynamicsBridge.GetPatrolPoint(bandit, brain, director.Config.patrolRadius)
        end)
        if okSquad and squadPoint and squadPoint.x and squadPoint.y then
            local distSq = runtime.dist(bandit:getX(), bandit:getY(), squadPoint.x, squadPoint.y)
            if distSq > (tonumber(squadPoint.arriveDist) or 1.9) then
                local task = runtime.moveToState(bandit, squadPoint.mode == "regroup" and director.States.Regroup or director.States.PatrolArea, squadPoint.reason or "cohesive squad patrol", squadPoint.x, squadPoint.y, squadPoint.z or bandit:getZ(), squadPoint.mode == "regroup" and "Walk" or "Walk", true)
                task.squadSupport = true
                task.arriveDist = tonumber(squadPoint.arriveDist) or 1.9
                task.pathThrottleMs = 1800
                task.sameTargetPathThrottleMs = 6500
                return {task}
            end
            return {{
                action = "FaceLocation",
                x = squadPoint.x + 2 - ZombRand(5),
                y = squadPoint.y + 2 - ZombRand(5),
                time = 20 + ZombRand(24),
                director = true,
                directorState = director.States.PatrolArea,
                directorReason = "hold squad patrol sector"
            }}
        end
    end

    if brain.roadPatrol and NPCRoadNavBridge and NPCRoadNavBridge.FindPatrolPoint then
        local patrol = brain.fsm.patrol or {}
        local now = runtime.worldAgeHours()
        if not patrol.x or runtime.dist(bandit:getX(), bandit:getY(), patrol.x, patrol.y) < 3 or (patrol.expire and now > patrol.expire) then
            local point = NPCRoadNavBridge.FindPatrolPoint(bandit, brain, director.Config.patrolRadius + 24)
            if point then
                patrol = {x=point.x, y=point.y, z=point.z or bandit:getZ(), expire=now + 0.45, road=true, roadPatrol=true}
                brain.fsm.patrol = patrol
                brain.fsm.roadChain = nil
            end
        end
        if patrol.x then
            return {runtime.moveToState(bandit, director.States.PatrolArea, "road patrol chain waypoint", patrol.x, patrol.y, patrol.z or bandit:getZ(), "Walk", true)}
        end
    end

    if NPCRoadNavBridge and NPCRoadNavBridge.ShouldReturnToRoad and NPCRoadNavBridge.ShouldReturnToRoad(bandit, brain) then
        local road = NPCRoadNavBridge.FindLoadedTownOrRoadAround(bandit:getX(), bandit:getY(), bandit:getZ(), 90)
        if road then
            brain.fsm.patrol = {x=road.x, y=road.y, z=road.z or bandit:getZ(), expire=runtime.worldAgeHours() + 0.22, road=true}
            return {runtime.moveToState(bandit, director.States.PatrolArea, "return to road/town", road.x, road.y, road.z or bandit:getZ(), "Run", true)}
        end
    end

    local patrol = brain.fsm.patrol or {}
    local now = runtime.worldAgeHours()
    if not patrol.x or runtime.dist(bandit:getX(), bandit:getY(), patrol.x, patrol.y) < 2 or (patrol.expire and now > patrol.expire) then
        local ax, ay, az = runtime.anchor(brain, bandit, "patrolPoint")
        local tx, ty, tz = runtime.offsetPoint(ax, ay, az, 5 + ZombRand(math.floor(director.Config.patrolRadius)), ZombRand(628))
        if NPCRoadNavBridge and NPCRoadNavBridge.AdjustMoveTarget then
            local adjustedX, adjustedY, adjustedZ = NPCRoadNavBridge.AdjustMoveTarget(bandit, brain, director.States.PatrolArea, "patrol waypoint", tx, ty, tz)
            tx = adjustedX or tx
            ty = adjustedY or ty
            tz = adjustedZ or tz
        end
        patrol = {x=tx, y=ty, z=tz, expire=now + 0.35}
        brain.fsm.patrol = patrol
    end
    return {runtime.moveToState(bandit, director.States.PatrolArea, "patrol waypoint", patrol.x, patrol.y, patrol.z or bandit:getZ(), "Walk", true)}
end

function NPCBrainDirectorBridge.HandleLootArea(director, runtime, bandit, brain)
    if not director or not runtime then return {} end

    local moveToStorage = runtime.moveToZoneIfFar(bandit, brain, "storagePoint", director.States.LootArea, "move to base storage", 4.0, "Walk")
    if moveToStorage then return moveToStorage end

    local square = runtime.findContainerSquare(bandit, director.Config.lootScanRadius)
    if square then
        local sx, sy, sz = square:getX(), square:getY(), square:getZ()
        local dist = runtime.dist(bandit:getX(), bandit:getY(), sx + 0.5, sy + 0.5)

        if dist > 1.8 then
            return {runtime.moveToState(bandit, director.States.LootArea, "move to loot container", sx, sy, sz, "Walk", true)}
        end

        return {{
            action = "LootItems",
            anim = "Loot",
            time = 120,
            x = sx,
            y = sy,
            z = sz,
            director = true,
            directorState = director.States.LootArea,
            directorReason = "loot nearby container"
        }}
    end

    return NPCBrainDirectorBridge.HandlePatrolArea(director, runtime, bandit, brain)
end

function NPCBrainDirectorBridge.HandleReturnToBase(director, runtime, bandit, brain)
    if not director or not runtime then return {} end

    local x, y, z = runtime.formationAnchor(brain, bandit, "returnPoint")
    local dist = runtime.dist(bandit:getX(), bandit:getY(), x, y)

    if dist > 2.5 then
        return {runtime.moveToState(bandit, director.States.ReturnToBase, "return to base", x, y, z, "Run", true)}
    end

    return {runtime.idleTask("at base")}
end

function NPCBrainDirectorBridge.HandleHealSelf(director, runtime, bandit, brain)
    if not director or not runtime then return {} end

    local moveToMedical = runtime.moveToZoneIfFar(bandit, brain, "medicalPoint", director.States.HealSelf, "move to base medical zone", 3.0, "Walk")
    if moveToMedical then return moveToMedical end

    if runtime.health01(bandit) < 0.90 or runtime.baseZoneType(brain) == "medical" then
        return {{
            action = "Bandage",
            anim = "BandageRightArm",
            time = 180,
            director = true,
            directorState = director.States.HealSelf,
            directorReason = "heal self"
        }}
    end

    return {runtime.idleTask("health stable")}
end

function NPCBrainDirectorBridge.HandleReload(director, runtime, bandit, brain, state, reason)
    if not director or not runtime then return {} end

    if (state or director.States.ReloadWeapon) == director.States.ReloadWeapon then
        local moveToAmmo = runtime.moveToZoneIfFar(bandit, brain, "ammoPoint", director.States.ReloadWeapon, "move to base ammo zone", 3.0, "Walk")
        if moveToAmmo then return moveToAmmo end
    end

    local tasks = runtime.reloadTasks(bandit, brain, state or director.States.ReloadWeapon, reason or "reload weapon")
    if tasks then return tasks end
    return {runtime.idleTask("no reload needed")}
end

function NPCBrainDirectorBridge.HandleEatDrink(director, runtime, bandit, brain)
    if not director or not runtime then return {} end

    local moveToFood = runtime.moveToZoneIfFar(bandit, brain, "foodPoint", director.States.EatDrink, "move to base food zone", 3.0, "Walk")
    if moveToFood then return moveToFood end

    brain.needs = brain.needs or {}
    brain.needs.food = math.min(1, tonumber(brain.needs.food or 0) + 0.25)
    brain.needs.water = math.min(1, tonumber(brain.needs.water or 0) + 0.25)
    if NPCUtilityAIBridge and NPCUtilityAIBridge.ConsumeNeed then
        pcall(function()
            NPCUtilityAIBridge.ConsumeNeed(brain, "food", 0.35)
            NPCUtilityAIBridge.AddRateLimitedXP(brain, "teamwork_eat", "teamwork", 1, 0.05, "eat_drink")
        end)
    end

    return {{
        action = "Time",
        anim = "ChewNails",
        time = 120,
        director = true,
        directorState = director.States.EatDrink,
        directorReason = "eat/drink placeholder"
    }}
end

function NPCBrainDirectorBridge.HandleSleepRest(director, runtime, bandit, brain)
    if not director or not runtime then return {} end

    local moveToRest = runtime.moveToZoneIfFar(bandit, brain, "restPoint", director.States.SleepRest, "move to base sleep zone", 3.0, "Walk")
    if moveToRest then return moveToRest end

    brain.needs = brain.needs or {}
    brain.needs.rest = math.min(1, tonumber(brain.needs.rest or 0) + 0.25)
    if NPCUtilityAIBridge and NPCUtilityAIBridge.ConsumeNeed then
        pcall(function()
            NPCUtilityAIBridge.ConsumeNeed(brain, "rest", 0.35)
            NPCUtilityAIBridge.AddRateLimitedXP(brain, "fitness_rest", "fitness", 1, 0.05, "rest")
        end)
    end

    return {{
        action = "Time",
        anim = "Exhausted",
        time = 180,
        director = true,
        directorState = director.States.SleepRest,
        directorReason = "rest"
    }}
end

function NPCBrainDirectorBridge.HandleFlee(director, runtime, bandit, brain, threat)
    if not director or not runtime then return {} end

    if not threat then
        local last = brain.fsm and brain.fsm.lastKnownEnemyPosition
        if last then threat = {x=last.x, y=last.y, z=last.z or bandit:getZ(), dist=runtime.dist(bandit:getX(), bandit:getY(), last.x, last.y)} end
    end
    if not threat then return runtime.handlePatrolArea(bandit, brain) end

    local dx = bandit:getX() - threat.x
    local dy = bandit:getY() - threat.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.01 then len = 1 end

    if NPCTacticalCostFieldBridge and NPCTacticalCostFieldBridge.FindSaferPoint then
        local okSafe, safe = pcall(function() return NPCTacticalCostFieldBridge.FindSaferPoint(bandit, brain, threat, "flee") end)
        if okSafe and safe and safe.x and safe.y then
            local sx, sy, sz = runtime.findFreeAround(safe.x, safe.y, safe.z or bandit:getZ(), 4, bandit)
            if sx and sy then return {runtime.moveToState(bandit, director.States.Flee, "flee by tactical cost", sx, sy, sz, "Run", false)} end
        end
    end
    local tx = bandit:getX() + (dx / len) * director.Config.fleeDistance
    local ty = bandit:getY() + (dy / len) * director.Config.fleeDistance
    local fx, fy, fz = runtime.findFreeAround(tx, ty, bandit:getZ(), 5)
    if fx and fy then
        return {runtime.moveToState(bandit, director.States.Flee, "flee from threat", fx, fy, fz, "Run", false)}
    end

    return {runtime.idleTask("no flee route")}
end

function NPCBrainDirectorBridge.HandleSearchEnemy(director, runtime, bandit, brain)
    if not director or not runtime then return {} end

    if NPCSquadDynamicsBridge and NPCSquadDynamicsBridge.GetSearchPoint then
        local ok, point = pcall(function()
            return NPCSquadDynamicsBridge.GetSearchPoint(bandit, brain)
        end)
        if ok and point and point.x and point.y then
            local tasks = {runtime.moveToState(bandit, director.States.SearchEnemy, point.reason or "squad search last contact", point.x, point.y, point.z or bandit:getZ(), "Walk", true)}
            if point.inspectAnim then
                tasks[#tasks + 1] = {
                    action = "FaceLocation",
                    x = point.x + 2 - ZombRand(5),
                    y = point.y + 2 - ZombRand(5),
                    time = 18,
                    director = true,
                    directorState = director.States.SearchEnemy,
                    directorReason = point.reason or "squad search last contact",
                    squadDynamic = true
                }
                tasks[#tasks + 1] = {
                    action = "Time",
                    anim = point.inspectAnim,
                    time = point.inspectTime or 95,
                    director = true,
                    directorState = director.States.SearchEnemy,
                    directorReason = point.reason or "squad search last contact",
                    squadDynamic = true
                }
            end
            return tasks
        end
    end

    local last = nil
    if NPCAIVisionBridge and NPCAIVisionBridge.GetLastKnownEnemyPosition then
        local okLast, sensedLast = pcall(function()
            return NPCAIVisionBridge.GetLastKnownEnemyPosition(brain)
        end)
        if okLast then last = sensedLast end
    end
    if not last then last = brain.fsm and brain.fsm.lastKnownEnemyPosition end
    if not last and brain.radioThreat then last = brain.radioThreat end
    if last and last.x and last.y then
        local point = nil
        if NPCHumanizedAIBridge and NPCHumanizedAIBridge.GetInvestigationPoint then
            local okPoint, p = pcall(function()
                return NPCHumanizedAIBridge.GetInvestigationPoint(bandit, brain, last)
            end)
            if okPoint then point = p end
        end

        local tx = last.x
        local ty = last.y
        local tz = last.z or bandit:getZ()
        local searchReason = "search last known enemy position"
        if point and point.x and point.y then
            tx = point.x
            ty = point.y
            tz = point.z or tz
            searchReason = point.reason or searchReason
        end

        local dist = runtime.dist(bandit:getX(), bandit:getY(), tx, ty)
        if dist > 2.5 then
            local sx, sy, sz = runtime.findFreeAround(tx, ty, tz, 5, bandit)
            sx = sx or tx
            sy = sy or ty
            sz = sz or tz
            local task = runtime.moveToState(bandit, director.States.SearchEnemy, searchReason, sx, sy, sz, last.memoryOnly and "Walk" or "Run", true)
            task.arriveDist = math.max(task.arriveDist or 0.9, 2.0)
            task.searchMemoryOnly = last.memoryOnly == true
            task.investigationStage = point and point.stage or nil
            return {task}
        else
            local faceX = (last.x or tx) + 2 - ZombRand(5)
            local faceY = (last.y or ty) + 2 - ZombRand(5)
            return {
                {
                    action = "FaceLocation",
                    x = faceX,
                    y = faceY,
                    time = 18 + ZombRand(16),
                    director = true,
                    directorState = director.States.SearchEnemy,
                    directorReason = "look around last contact",
                    searchMemoryOnly = last.memoryOnly == true
                },
                {
                    action = "Time",
                    anim = "ShiftWeight",
                    time = director.Config.humanizedSearchPause or 65,
                    director = true,
                    directorState = director.States.SearchEnemy,
                    directorReason = "pause and listen",
                    searchMemoryOnly = last.memoryOnly == true
                }
            }
        end
    end

    return runtime.handlePatrolArea(bandit, brain)
end

function NPCBrainDirectorBridge.HandleTacticalRadioMove(director, runtime, bandit, brain, threat, state, fallbackReason)
    if not director or not runtime then return {} end

    if NPCSquadDynamicsBridge and NPCSquadDynamicsBridge.GetManeuverPoint then
        local okSquad, squadPoint = pcall(function()
            return NPCSquadDynamicsBridge.GetManeuverPoint(bandit, brain, threat)
        end)
        if okSquad and squadPoint and squadPoint.x and squadPoint.y then
            if squadPoint.holdOnly then
                return {{
                    action = "FaceLocation",
                    x = (squadPoint.threat and squadPoint.threat.x) or squadPoint.x,
                    y = (squadPoint.threat and squadPoint.threat.y) or squadPoint.y,
                    time = 22,
                    director = true,
                    directorState = state,
                    directorReason = squadPoint.reason or fallbackReason or "hold covering angle"
                }}
            end
            local style = "Run"
            if squadPoint.mode == "suppress" or squadPoint.mode == "cover" or squadPoint.mode == "regroup" or state == director.States.HoldAngle or state == director.States.SuppressEnemy then
                style = "Walk"
            end
            local task = runtime.moveToState(bandit, state, squadPoint.reason or fallbackReason or "squad dynamic move", squadPoint.x, squadPoint.y, squadPoint.z or bandit:getZ(), style, false)
            task.squadSupport = true
            task.arriveDist = tonumber(squadPoint.arriveDist) or 1.8
            task.pathThrottleMs = 1600
            task.sameTargetPathThrottleMs = 6200
            return {task}
        end
    end

    if NPCTacticalRadioBridge and NPCTacticalRadioBridge.GetManeuverPoint then
        local radio = brain and brain.radio or nil
        local tacticalThreat = threat or brain.radioThreat or (radio and radio.pendingManeuverThreat)
        local oldRequested = brain and brain.tacticalRequestedState or nil
        if brain then brain.tacticalRequestedState = state end
        local ok, point = pcall(function()
            return NPCTacticalRadioBridge.GetManeuverPoint(bandit, brain, tacticalThreat)
        end)
        if brain then brain.tacticalRequestedState = oldRequested end
        if ok and point and point.x and point.y then
            local style = "Run"
            if state == director.States.HoldAngle or state == director.States.SuppressEnemy or point.mode == "overwatch" or point.mode == "suppress" then
                style = "Walk"
            end
            return {runtime.moveToState(bandit, state, point.reason or fallbackReason or "radio tactical move", point.x, point.y, point.z or bandit:getZ(), style, false)}
        end
    end
    if NPCTacticalCostFieldBridge and NPCTacticalCostFieldBridge.FindSaferPoint then
        local okSafe, safe = pcall(function() return NPCTacticalCostFieldBridge.FindSaferPoint(bandit, brain, threat or brain.radioThreat, "cover") end)
        if okSafe and safe and safe.x and safe.y then return {runtime.moveToState(bandit, state, "tactical cost field", safe.x, safe.y, safe.z or bandit:getZ(), "Walk", false)} end
    end
    return NPCBrainDirectorBridge.HandleSearchEnemy(director, runtime, bandit, brain)
end

function NPCBrainDirectorBridge.HandleKeepDistance(director, runtime, bandit, brain, threat)
    if not director or not runtime then return {} end
    if not threat then return runtime.handlePatrolArea(bandit, brain) end

    local dx = bandit:getX() - threat.x
    local dy = bandit:getY() - threat.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.01 then len = 1 end

    local tx = bandit:getX() + (dx / len) * 3.5
    local ty = bandit:getY() + (dy / len) * 3.5
    local fx, fy, fz = runtime.findFreeAround(tx, ty, bandit:getZ(), 4)
    if fx and fy then
        local task = runtime.moveToState(bandit, director.States.KeepDistance, "keep firearm distance", fx, fy, fz, "Run", false)
        task.combatMove = true
        task.pathThrottleMs = 650
        task.sameTargetPathThrottleMs = 1600
        return {task}
    end

    return {}
end

local function bbd_nowMs()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then return math.floor(getGameTime():getWorldAgeHours() * 3600000) end
    return 0
end

function NPCBrainDirectorBridge.HandleMeleeFallback(director, runtime, bandit, brain, threat)
    if not (director and runtime and bandit and brain and threat and threat.x and threat.y) then return {} end

    local melee = brain.weapons and brain.weapons.melee or nil
    if not melee then return {} end

    local bx = bandit:getX()
    local by = bandit:getY()
    local bz = bandit:getZ()
    local dist = tonumber(threat.dist) or runtime.dist(bx, by, threat.x, threat.y)
    local maxRange = 0.95
    local okItem, item = pcall(function() return NPCCompatibilityBridge and NPCCompatibilityBridge.InstanceItem and NPCCompatibilityBridge.InstanceItem(melee) or nil end)
    if okItem and item and item.getMaxRange then
        maxRange = math.max(0.75, tonumber(item:getMaxRange()) or 1.1)
    end

    local strikeRange
    if maxRange < 0.70 then
        strikeRange = math.max(0.48, maxRange - 0.05)
    elseif maxRange < 1.15 then
        strikeRange = math.max(0.62, maxRange - 0.18)
    else
        strikeRange = math.max(0.78, maxRange - 0.25)
    end

    -- Release-quality rule: do not path-spam around a nearby zombie. The legacy
    -- Hit/Shove layer owns the actual strike; the director only performs a rare,
    -- bounded approach when the NPC is clearly outside melee reach.
    local closeEnough = math.max(strikeRange + 0.35, 1.28)
    if dist <= closeEnough then return {} end
    if dist > (tonumber(director.Config.meleeApproachMaxDist) or 6.5) then return {} end

    brain.fsm = brain.fsm or {}
    local now = bbd_nowMs()
    local tid = tostring(threat.id or threat.uid or threat.x .. ":" .. threat.y)
    local sameThreat = brain.fsm.meleeApproachTargetId == tid
    local cooldown = sameThreat and (tonumber(director.Config.meleeApproachSameTargetMs) or 2400) or (tonumber(director.Config.meleeApproachCooldownMs) or 1500)
    if brain.fsm.meleeApproachAt and now - tonumber(brain.fsm.meleeApproachAt) < cooldown then return {} end

    local dx = bx - threat.x
    local dy = by - threat.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.01 then len = 1 end
    local desired = math.max(0.82, math.min(1.25, strikeRange * 0.88))
    local tx = threat.x + (dx / len) * desired
    local ty = threat.y + (dy / len) * desired
    local tz = threat.z or bz

    local fx, fy, fz = runtime.findFreeAround(tx, ty, tz, 2)
    if fx and fy then
        tx, ty, tz = fx, fy, fz or tz
    end

    brain.fsm.meleeApproachAt = now
    brain.fsm.meleeApproachTargetId = tid
    brain.fsm.meleeApproachX = tx
    brain.fsm.meleeApproachY = ty

    local task = runtime.moveToState(bandit, director.States.MeleeFallback, "bounded melee approach", tx, ty, tz, dist > 2.8 and "Run" or "Walk", false)
    task.arriveDist = math.max(0.82, math.min(1.25, strikeRange + 0.12))
    task.meleeApproach = true
    task.combatMove = true
    task.noRecoveryReplan = true
    task.targetId = threat.id
    task.targetKind = threat.kind
    task.pathThrottleMs = 1800
    task.sameTargetPathThrottleMs = 3800
    return {task}
end

function NPCBrainDirectorBridge.HandleRegroup(director, runtime, bandit, brain)
    if not director or not runtime then return {} end

    if NPCSquadDynamicsBridge and NPCSquadDynamicsBridge.GetRegroupPoint then
        local ok, point = pcall(function() return NPCSquadDynamicsBridge.GetRegroupPoint(bandit, brain) end)
        if ok and point and point.x and point.y then
            local task = runtime.moveToState(bandit, director.States.Regroup, point.reason or "group spacing", point.x, point.y, point.z or bandit:getZ(), "Walk", true)
            task.squadSupport = true
            task.arriveDist = tonumber(point.arriveDist) or 1.8
            task.pathThrottleMs = 1800
            task.sameTargetPathThrottleMs = 6500
            return {task}
        end
    end

    local tx, ty, tz = runtime.offsetPoint(bandit:getX(), bandit:getY(), bandit:getZ(), 1.5 + ZombRand(2), ZombRand(628))
    return {runtime.moveToState(bandit, director.States.Regroup, "group spacing", tx, ty, tz, "Walk", true)}
end

function NPCBrainDirectorBridge.HandleRecoverPath(director, runtime, bandit, brain)
    if not director or not runtime then return {} end

    if NPCMovementStabilityBridge and NPCMovementStabilityBridge.FindRecoverySquare then
        local ok, square = pcall(function()
            return NPCMovementStabilityBridge.FindRecoverySquare(bandit, runtime.currentTask(bandit))
        end)
        if ok and square then
            return {runtime.moveToState(bandit, director.States.RecoverPath, "unstuck local recovery", square:getX(), square:getY(), square:getZ(), "Walk", false)}
        end
    end

    local tx, ty, tz = runtime.offsetPoint(bandit:getX(), bandit:getY(), bandit:getZ(), 2 + ZombRand(3), ZombRand(628))
    return {runtime.moveToState(bandit, director.States.RecoverPath, "unstuck sidestep", tx, ty, tz, "Walk", false)}
end

function NPCBrainDirectorBridge.HandleSquadDynamicTask(director, runtime, bandit, brain, spec)
    if not director or not runtime then return nil end
    if not spec then return nil end

    local state = director.States[spec.state or "Idle"] or director.States.Idle
    local reason = spec.reason or "squad ambient"

    if spec.kind == "sequence" and spec.tasks then
        local out = {}
        for _, sub in ipairs(spec.tasks) do
            local subState = director.States[sub.state or spec.state or "Idle"] or state
            local subReason = sub.reason or reason
            if sub.kind == "move" and sub.x and sub.y then
                out[#out + 1] = runtime.moveToState(bandit, subState, subReason, sub.x, sub.y, sub.z or bandit:getZ(), sub.walkType or "Walk", true)
            elseif sub.kind == "face" and sub.x and sub.y then
                out[#out + 1] = {
                    action = "FaceLocation",
                    x = sub.x,
                    y = sub.y,
                    time = sub.time or 18,
                    director = true,
                    directorState = subState,
                    directorReason = subReason,
                    squadDynamic = true
                }
            elseif sub.kind == "time" then
                out[#out + 1] = {
                    action = "Time",
                    anim = sub.anim or "ChewNails",
                    time = sub.time or 100,
                    director = true,
                    directorState = subState,
                    directorReason = subReason,
                    squadDynamic = true
                }
            end
        end
        if #out > 0 then return out end
    elseif spec.kind == "move" and spec.x and spec.y then
        return {runtime.moveToState(bandit, state, reason, spec.x, spec.y, spec.z or bandit:getZ(), spec.walkType or "Walk", true)}
    elseif spec.kind == "face" and spec.x and spec.y then
        return {{
            action = "FaceLocation",
            x = spec.x,
            y = spec.y,
            time = spec.time or 18,
            director = true,
            directorState = state,
            directorReason = reason,
            squadDynamic = true
        }}
    elseif spec.kind == "time" then
        return {{
            action = "Time",
            anim = spec.anim or "ChewNails",
            time = spec.time or 100,
            director = true,
            directorState = state,
            directorReason = reason,
            squadDynamic = true
        }}
    end

    return nil
end


function NPCBrainDirectorBridge.CreateRuntime(director)
    local runtime = {}

    runtime.isAlive = NPCBrainDirectorBridge.IsAlive
    runtime.firstTaskAction = NPCBrainDirectorBridge.FirstTaskAction
    runtime.currentAction = NPCBrainDirectorBridge.CurrentAction
    runtime.currentTask = NPCBrainDirectorBridge.CurrentTask
    runtime.normalizeOrder = NPCBrainDirectorBridge.NormalizeOrder
    runtime.getOrder = NPCBrainDirectorBridge.GetOrder
    runtime.getProgramName = NPCBrainDirectorBridge.GetProgramName
    runtime.health01 = NPCBrainDirectorBridge.Health01
    runtime.isIndirectThreat = NPCBrainDirectorBridge.IsIndirectThreat
    runtime.hasLoadedFirearm = NPCBrainDirectorBridge.HasLoadedFirearm
    runtime.hasReloadableFirearm = NPCBrainDirectorBridge.HasReloadableFirearm
    runtime.hasMelee = NPCBrainDirectorBridge.HasMelee
    runtime.influenceStimulus = NPCBrainDirectorBridge.InfluenceStimulus
    runtime.baseZoneType = NPCBrainDirectorBridge.BaseZoneType
    runtime.getBrain = NPCBrainDirectorBridge.GetBrain
    runtime.now = NPCBrainDirectorBridge.Now
    runtime.worldAgeHours = NPCBrainDirectorBridge.WorldAgeHours
    runtime.countNearbyFriends = NPCBrainDirectorBridge.CountNearbyFriends
    runtime.updateWatchdog = NPCBrainDirectorBridge.UpdateWatchdog
    runtime.setState = NPCBrainDirectorBridge.SetState
    runtime.hasActionTask = NPCBrainDirectorBridge.HasActionTask
    runtime.isCombatAction = NPCBrainDirectorBridge.IsCombatAction
    runtime.dist = NPCBrainDirectorBridge.Dist
    runtime.masterPlayer = NPCBrainDirectorBridge.MasterPlayer
    runtime.followFormationPoint = NPCBrainDirectorBridge.FollowFormationPoint
    runtime.offsetPoint = NPCBrainDirectorBridge.OffsetPoint
    runtime.findFreeAround = NPCBrainDirectorBridge.FindFreeAround
    runtime.formationAnchor = NPCBrainDirectorBridge.FormationAnchor
    runtime.anchor = NPCBrainDirectorBridge.Anchor

    runtime.livingSuggestState = function(bandit, brain, threat, health, order, programName)
        if not (NPCLivingWorldIntentBridge and NPCLivingWorldIntentBridge.SuggestState) then return nil end
        local ok, state, reason = pcall(function()
            return NPCLivingWorldIntentBridge.SuggestState(director, runtime, bandit, brain, threat, health, order, programName)
        end)
        if ok then return state, reason end
        return nil
    end

    runtime.livingPlanAmbientTasks = function(bandit, brain, state, reason, threat, uTick)
        if not (NPCLivingWorldIntentBridge and NPCLivingWorldIntentBridge.PlanAmbientTasks) then return nil end
        local ok, tasks = pcall(function()
            return NPCLivingWorldIntentBridge.PlanAmbientTasks(director, runtime, bandit, brain, state, reason, threat, uTick)
        end)
        if ok then return tasks end
        return nil
    end

    runtime.worldRoutineSuggestState = function(bandit, brain, threat, health, order, programName)
        if not (NPCWorldRoutineBridge and NPCWorldRoutineBridge.SuggestState) then return nil end
        local ok, state, reason = pcall(function()
            return NPCWorldRoutineBridge.SuggestState(director, runtime, bandit, brain, threat, health, order, programName)
        end)
        if ok then return state, reason end
        return nil
    end

    runtime.worldRoutinePlanTasks = function(bandit, brain, state, reason, threat, uTick)
        if not (NPCWorldRoutineBridge and NPCWorldRoutineBridge.PlanTasks) then return nil end
        local ok, tasks = pcall(function()
            return NPCWorldRoutineBridge.PlanTasks(director, runtime, bandit, brain, state, reason, threat, uTick)
        end)
        if ok then return tasks end
        return nil
    end

    runtime.livingUpdateCombatMemory = function(bandit, brain, threat)
        if NPCLivingWorldIntentBridge and NPCLivingWorldIntentBridge.UpdateCombatMemory then
            pcall(function()
                NPCLivingWorldIntentBridge.UpdateCombatMemory(bandit, brain, threat, runtime.currentAction(bandit))
            end)
        end
    end

    runtime.findNearestThreat = function(bandit, brain, maxDist)
        local config = director and director.Config or {}
        return NPCBrainDirectorBridge.FindNearestThreat(bandit, brain, maxDist, config.tacticalRadioSearchRadius)
    end

    runtime.baseDutyState = function(brain, health)
        return NPCBrainDirectorBridge.BaseDutyState(director, brain, health)
    end

    runtime.idleTask = function(reason)
        return NPCBrainDirectorBridge.IdleTask(director, reason)
    end

    runtime.moveToState = function(bandit, state, reason, x, y, z, walkType, closeSlow)
        return NPCBrainDirectorBridge.MoveToState(bandit, state, reason, x, y, z, walkType, closeSlow)
    end

    runtime.findContainerSquare = function(bandit, radius)
        return NPCBrainDirectorBridge.FindContainerSquare(director, bandit, radius)
    end

    runtime.reloadTasks = function(bandit, brain, state, reason)
        return NPCBrainDirectorBridge.ReloadTasks(bandit, brain, state, reason)
    end

    runtime.moveToZoneIfFar = function(bandit, brain, key, state, reason, radius, walkType)
        return NPCBrainDirectorBridge.MoveToZoneIfFar(runtime, bandit, brain, key, state, reason, radius, walkType)
    end

    return NPCBrainDirectorBridge.AttachRuntimeHandlers(director, runtime)
end

function NPCBrainDirectorBridge.AttachRuntimeHandlers(director, runtime)
    if not director or not runtime then return runtime end

    runtime.handleIdle = function(bandit, brain, state, reason)
        return NPCBrainDirectorBridge.HandleIdle(director, runtime, bandit, brain, state, reason)
    end

    runtime.handleFollowPlayer = function(bandit, brain)
        return NPCBrainDirectorBridge.HandleFollowPlayer(director, runtime, bandit, brain)
    end

    runtime.handleGuardPlayer = function(bandit, brain)
        return NPCBrainDirectorBridge.HandleGuardPlayer(director, runtime, bandit, brain)
    end

    runtime.handleHoldPosition = function(bandit, brain)
        return NPCBrainDirectorBridge.HandleHoldPosition(director, runtime, bandit, brain)
    end

    runtime.handleGuardArea = function(bandit, brain, state, radius)
        return NPCBrainDirectorBridge.HandleGuardArea(director, runtime, bandit, brain, state, radius)
    end

    runtime.handlePatrolArea = function(bandit, brain)
        return NPCBrainDirectorBridge.HandlePatrolArea(director, runtime, bandit, brain)
    end

    runtime.handleLootArea = function(bandit, brain)
        return NPCBrainDirectorBridge.HandleLootArea(director, runtime, bandit, brain)
    end

    runtime.handleReturnToBase = function(bandit, brain)
        return NPCBrainDirectorBridge.HandleReturnToBase(director, runtime, bandit, brain)
    end

    runtime.handleHealSelf = function(bandit, brain)
        return NPCBrainDirectorBridge.HandleHealSelf(director, runtime, bandit, brain)
    end

    runtime.handleReload = function(bandit, brain, state, reason)
        return NPCBrainDirectorBridge.HandleReload(director, runtime, bandit, brain, state, reason)
    end

    runtime.handleEatDrink = function(bandit, brain)
        return NPCBrainDirectorBridge.HandleEatDrink(director, runtime, bandit, brain)
    end

    runtime.handleSleepRest = function(bandit, brain)
        return NPCBrainDirectorBridge.HandleSleepRest(director, runtime, bandit, brain)
    end

    runtime.handleFlee = function(bandit, brain, threat)
        return NPCBrainDirectorBridge.HandleFlee(director, runtime, bandit, brain, threat)
    end

    runtime.handleSearchEnemy = function(bandit, brain)
        return NPCBrainDirectorBridge.HandleSearchEnemy(director, runtime, bandit, brain)
    end

    runtime.handleTacticalRadioMove = function(bandit, brain, threat, state, fallbackReason)
        return NPCBrainDirectorBridge.HandleTacticalRadioMove(director, runtime, bandit, brain, threat, state, fallbackReason)
    end

    runtime.handleKeepDistance = function(bandit, brain, threat)
        return NPCBrainDirectorBridge.HandleKeepDistance(director, runtime, bandit, brain, threat)
    end

    runtime.handleMeleeFallback = function(bandit, brain, threat)
        return NPCBrainDirectorBridge.HandleMeleeFallback(director, runtime, bandit, brain, threat)
    end

    runtime.handleRegroup = function(bandit, brain)
        return NPCBrainDirectorBridge.HandleRegroup(director, runtime, bandit, brain)
    end

    runtime.handleRecoverPath = function(bandit, brain)
        return NPCBrainDirectorBridge.HandleRecoverPath(director, runtime, bandit, brain)
    end

    runtime.handleSquadDynamicTask = function(bandit, brain, spec)
        return NPCBrainDirectorBridge.HandleSquadDynamicTask(director, runtime, bandit, brain, spec)
    end

    return runtime
end

function NPCBrainDirectorBridge.ExecuteState(director, runtime, bandit, brain, state, reason, threat)
    if not director or not runtime then return {} end
    if not state then return {} end

    if state == director.States.Idle then
        return runtime.handleIdle(bandit, brain, state, reason)

    elseif state == director.States.Moving then
        return {}

    elseif state == director.States.FollowPlayer then
        return runtime.handleFollowPlayer(bandit, brain)

    elseif state == director.States.GuardPlayer then
        return runtime.handleGuardPlayer(bandit, brain)

    elseif state == director.States.HoldPosition then
        return runtime.handleHoldPosition(bandit, brain)

    elseif state == director.States.GuardArea then
        return runtime.handleGuardArea(bandit, brain, state, director.Config.guardRadius)

    elseif state == director.States.PatrolArea then
        return runtime.handlePatrolArea(bandit, brain)

    elseif state == director.States.LootArea then
        return runtime.handleLootArea(bandit, brain)

    elseif state == director.States.ReturnToBase then
        return runtime.handleReturnToBase(bandit, brain)

    elseif state == director.States.HealSelf then
        return runtime.handleHealSelf(bandit, brain)

    elseif state == director.States.ReloadWeapon then
        return runtime.handleReload(bandit, brain, state, "reload weapon")

    elseif state == director.States.ReloadCover then
        if threat then
            local coverTasks = runtime.handleTacticalRadioMove(bandit, brain, threat, director.States.TacticalCover, "reload behind cover")
            if coverTasks and #coverTasks > 0 then return coverTasks end
            if threat.dist < 8 then
                return runtime.handleKeepDistance(bandit, brain, threat)
            end
        end
        return runtime.handleReload(bandit, brain, state, "reload behind distance")

    elseif state == director.States.EatDrink then
        return runtime.handleEatDrink(bandit, brain)

    elseif state == director.States.SleepRest then
        return runtime.handleSleepRest(bandit, brain)

    elseif state == director.States.Flee then
        return runtime.handleFlee(bandit, brain, threat)

    elseif state == director.States.SearchEnemy then
        return runtime.handleSearchEnemy(bandit, brain)

    elseif state == director.States.FlankEnemy then
        return runtime.handleTacticalRadioMove(bandit, brain, threat, state, "radio flank")

    elseif state == director.States.TacticalCover then
        return runtime.handleTacticalRadioMove(bandit, brain, threat, state, "radio cover")

    elseif state == director.States.SuppressEnemy then
        return runtime.handleTacticalRadioMove(bandit, brain, threat, state, "radio suppress")

    elseif state == director.States.HoldAngle then
        return runtime.handleTacticalRadioMove(bandit, brain, threat, state, "radio hold angle")

    elseif state == director.States.BoundForward then
        return runtime.handleTacticalRadioMove(bandit, brain, threat, state, "radio bound forward")

    elseif state == director.States.DefendBase then
        local moveToGuard = runtime.moveToZoneIfFar(bandit, brain, "guardPoint", director.States.DefendBase, "move to base guard post", director.Config.defendRadius, "Run")
        if moveToGuard then return moveToGuard end
        return runtime.handleGuardArea(bandit, brain, state, director.Config.defendRadius)

    elseif state == director.States.KeepDistance then
        return runtime.handleKeepDistance(bandit, brain, threat)

    elseif state == director.States.Regroup then
        return runtime.handleRegroup(bandit, brain)

    elseif state == director.States.RecoverPath then
        return runtime.handleRecoverPath(bandit, brain)

    elseif state == director.States.MeleeFallback then
        return runtime.handleMeleeFallback(bandit, brain, threat)

    elseif state == director.States.Attack
        or state == director.States.EmergencyDefense then
        -- Legacy combat managers already own Shoot/Hit/Shove/Reload. Keep safe.
        return {}

    elseif state == director.States.Disabled
        or state == director.States.Dead then
        return {}
    end

    return {}
end


function NPCBrainDirectorBridge.Evaluate(director, runtime, bandit, uTick)
    if not director or not runtime then
        return {state=nil, reason="no runtime", priority=0, resetTasks=false}
    end

    local brain = runtime.getBrain(bandit)
    if not brain then
        return {state=director.States.Disabled, reason="no brain", priority=0, resetTasks=false}
    end

    local threat = runtime.findNearestThreat(bandit, brain, 18)
    if threat and NPCSpyBridge and NPCSpyBridge.TryDefectOnThreat then
        local ok, defected = pcall(function() return NPCSpyBridge.TryDefectOnThreat(bandit, brain, threat) end)
        if ok and defected then threat = nil end
    end
    local now = runtime.now()
    if NPCIntentArbiterBridge and NPCIntentArbiterBridge.UpdateContext then
        pcall(function()
            NPCIntentArbiterBridge.UpdateContext(bandit, brain, {
                threat = threat,
                currentAction = runtime.currentAction,
                health = runtime.health01(bandit),
                reason = "brain director evaluate"
            })
        end)
    end
    local stuck = runtime.updateWatchdog(bandit, brain, now)
    local state, reason = director.EvaluateDesiredState(bandit, brain, threat, stuck)
    runtime.setState(brain, state, reason, now)

    return {state=state, reason=reason, priority=0, resetTasks=false}
end

function NPCBrainDirectorBridge.OnTasksQueued(director, runtime, bandit, decision, tasks)
    -- Safe compatibility no-op.
end

function NPCBrainDirectorBridge.GetDebugState(director, runtime, brain)
    if not brain then return "NoBrain" end
    local state = tostring((brain.fsm and brain.fsm.state) or brain.state or "Unknown")
    if brain.squadDynamicReason then
        return state .. " / " .. tostring(brain.squadDynamicReason)
    end
    if brain.debugSquad then
        return state .. " / " .. tostring(brain.debugSquad)
    end
    return state
end

function NPCBrainDirectorBridge.PlanSafeTask(director, runtime, bandit, uTick)
    local tasks = {}

    if not director or not runtime then return tasks end

    local brain = runtime.getBrain(bandit)
    if not brain then return tasks end

    if NPCBrainScheduler and NPCBrainScheduler.ShouldThink then
        local okThink, shouldThink = pcall(function() return NPCBrainScheduler.ShouldThink(bandit, brain, uTick, "brain", brain.radioThreat or brain.currentThreat) end)
        if okThink and shouldThink == false then return tasks end
    end

    if NPCUtilityAIBridge and NPCUtilityAIBridge.Update then
        pcall(function()
            NPCUtilityAIBridge.Update(bandit, brain, uTick)
        end)
    end
    if NPCTacticalRadioBridge and NPCTacticalRadioBridge.Tick then
        pcall(function()
            NPCTacticalRadioBridge.Tick(bandit, brain, uTick, brain.radioThreat)
        end)
    end
    if NPCSquadDynamicsBridge and NPCSquadDynamicsBridge.Tick then
        pcall(function()
            NPCSquadDynamicsBridge.Tick(bandit, brain, uTick, brain.radioThreat or brain.currentThreat or brain.squadPlanThreat)
        end)
    end

    if NPCBrainDirectorBridge.IsWoundedLocked(brain) then return tasks end

    local now = runtime.now()
    local threat = runtime.findNearestThreat(bandit, brain, 18) or brain.radioThreat or brain.squadPlanThreat
    if threat then
        NPCBrainDirectorBridge.ClearNonCombatTaskForThreat(bandit, brain, threat)
    end

    -- Never interfere with active combat/actions.
    if runtime.hasActionTask(bandit) then return tasks end

    local currentAction = runtime.currentAction(bandit)
    if runtime.isCombatAction(currentAction) then return tasks end
    if NPCIntentArbiterBridge and NPCIntentArbiterBridge.UpdateContext then
        pcall(function()
            NPCIntentArbiterBridge.UpdateContext(bandit, brain, {
                threat = threat,
                currentAction = runtime.currentAction,
                health = runtime.health01(bandit),
                reason = "brain director safe task"
            })
        end)
    end
    if threat and NPCSpyBridge and NPCSpyBridge.TryDefectOnThreat then
        local ok, defected = pcall(function() return NPCSpyBridge.TryDefectOnThreat(bandit, brain, threat) end)
        if ok and defected then threat = nil end
    end
    if runtime.livingUpdateCombatMemory then
        runtime.livingUpdateCombatMemory(bandit, brain, threat)
    end
    local stuck = runtime.updateWatchdog(bandit, brain, now)
    local state, reason = director.EvaluateDesiredState(bandit, brain, threat, stuck)

    -- Non-combat spacing gets a chance before normal idle only.
    if state == director.States.Idle and uTick % 9 == 0 and runtime.countNearbyFriends(bandit, brain, 1.1) > 0 then
        state = director.States.Regroup
        reason = "group spacing"
    end

    runtime.setState(brain, state, reason, now)

    local intentOk, intentOwner = NPCBrainDirectorBridge.RequestIntentOwner(director, runtime, bandit, brain, state, reason, threat)
    if intentOk == false then return tasks end

    if not threat
        and state ~= director.States.HealSelf
        and state ~= director.States.ReloadWeapon
        and state ~= director.States.ReloadCover
        and NPCPostCombatLootBridge
        and NPCPostCombatLootBridge.PlanTasks then
        local okPostLoot, postLootTasks = pcall(function()
            return NPCPostCombatLootBridge.PlanTasks(bandit, brain, runtime, {state = director.States.LootArea})
        end)
        if okPostLoot and postLootTasks and #postLootTasks > 0 then
            return NPCBrainDirectorBridge.MarkIntentTasks(director, brain, postLootTasks, director.States.LootArea, "post-combat corpse loot", threat)
        end
    end

    if not threat and intentOwner == "world_routine" and runtime.worldRoutinePlanTasks then
        local routineTasks = runtime.worldRoutinePlanTasks(bandit, brain, state, reason, threat, uTick)
        if routineTasks and #routineTasks > 0 then return NPCBrainDirectorBridge.MarkIntentTasks(director, brain, routineTasks, state, reason, threat) end
    end

    local livingAmbientAllowed = intentOwner ~= "world_routine"
        and (state == director.States.Idle or state == director.States.GuardArea or state == director.States.DefendBase)
    if not threat and livingAmbientAllowed and runtime.livingPlanAmbientTasks then
        local livingTasks = runtime.livingPlanAmbientTasks(bandit, brain, state, reason, threat, uTick)
        if livingTasks and #livingTasks > 0 then return NPCBrainDirectorBridge.MarkIntentTasks(director, brain, livingTasks, state, reason, threat) end
    end

    if not threat and state == director.States.Idle and intentOwner ~= "world_routine" and NPCSquadDynamicsBridge and NPCSquadDynamicsBridge.GetAmbientTask then
        local okAmbient, ambientSpec = pcall(function()
            return NPCSquadDynamicsBridge.GetAmbientTask(bandit, brain, uTick)
        end)
        if okAmbient and ambientSpec and runtime.handleSquadDynamicTask then
            local ambientTasks = runtime.handleSquadDynamicTask(bandit, brain, ambientSpec)
            if ambientTasks and #ambientTasks > 0 then return NPCBrainDirectorBridge.MarkIntentTasks(director, brain, ambientTasks, state, reason, threat) end
        end
    end

    local planned = director.ExecuteState(bandit, brain, state, reason, threat)
    if planned and #planned > 0 then
        return NPCBrainDirectorBridge.MarkIntentTasks(director, brain, planned, state, reason, threat)
    end

    return tasks
end

