-- Neutral brain director bridge.
-- Compatibility backend for media/lua/shared/brain-director bridge.lua.

require "NPCCore/NPCLegacyContractBridge"

NPCBrainDirectorBridge = NPCBrainDirectorBridge or {}
local NPC_BRAIN_DIRECTOR_LEGACY_KEYS = {
    programNPC = NPCLegacyContractBridge.Key("FLAG")
}
NPCBrainDirectorBridge.Version = 1

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
        humanizedSearchPause = 65
    }
end

function NPCBrainDirectorBridge.ApplyDefaults(director)
    if not director then return end

    director.VERSION = "2026-05-03-base-zone-duty"
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

function NPCBrainDirectorBridge.FollowFormationPoint(player, brain, bandit)
    local order = brain and brain.order or nil
    if NPCFormationSlotsBridge and NPCFormationSlotsBridge.GetSlotPoint then
        local okSlot, sx, sy, sz = pcall(function()
            return NPCFormationSlotsBridge.GetSlotPoint(player, brain, bandit, type(order) == "table" and order.formation or "close", type(order) == "table" and order.followDistance or 3.0)
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
    local idx = tonumber(brain.memberIndex) or tonumber(brain.id) or (NPCUtils.GetCharacterID(bandit) or ZombRand(999))
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


function NPCBrainDirectorBridge.FindNearestThreat(bandit, brain, maxDist, tacticalRadioSearchRadius)
    if NPCOrderContract and NPCOrderContract.CanAggro and not NPCOrderContract.CanAggro(brain) then return nil end
    if NPCAIVisionBridge and NPCAIVisionBridge.FindNearestThreat then
        local ok, threat = pcall(function()
            return NPCAIVisionBridge.FindNearestThreat(bandit, brain, maxDist or 28, true)
        end)

        if ok and threat then
            return threat
        end
    end

    if not bandit or not NPCZombieCacheBridge or not NPCZombieCacheBridge.CacheLight then return nil end

    maxDist = maxDist or 28
    local bx = bandit:getX()
    local by = bandit:getY()
    local bz = bandit:getZ()
    local best = nil
    local bestD2 = maxDist * maxDist

    local nearby = NPCZombieCacheBridge.CacheLight
    if NPCSpatialIndexBridge and NPCSpatialIndexBridge.GetNearbyAll then
        nearby = NPCSpatialIndexBridge.GetNearbyAll(bx, by, bz, maxDist)
    end

    for id, data in pairs(nearby) do
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

    if best and NPCTacticalRadioBridge and NPCTacticalRadioBridge.ReportContact then
        pcall(function()
            NPCTacticalRadioBridge.ReportContact(bandit, brain, best.target, best.kind, best.dist, 1.0)
        end)
        return best
    end

    if NPCTacticalRadioBridge and NPCTacticalRadioBridge.GetSharedThreat then
        local ok, radioThreat = pcall(function()
            return NPCTacticalRadioBridge.GetSharedThreat(bandit, brain, tacticalRadioSearchRadius or maxDist or 46)
        end)
        if ok and radioThreat then return radioThreat end
    end

    return best
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
    if NPCSpatialIndexBridge and NPCSpatialIndexBridge.GetNearbyNPCs then
        nearby = NPCSpatialIndexBridge.GetNearbyNPCs(bx, by, bz, radius)
    elseif NPCSpatialIndexBridge then
        local legacyNearby = NPCSpatialIndexBridge["GetNearby" .. NPCLegacyContractBridge.Plural]
        if legacyNearby then nearby = legacyNearby(bx, by, bz, radius) end
    end

    for _, data in pairs(nearby) do
        if data and data.z == bz and data.brain and data.brain.clan == brain.clan then
            local d2 = NPCBrainDirectorBridge.Dist2(bx, by, data.x, data.y)
            if d2 > 0.01 and d2 < r2 then
                count = count + 1
            end
        end
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
    local cell = getCell()
    if not cell then return nil end

    local bx = math.floor(bandit:getX())
    local by = math.floor(bandit:getY())
    local bz = math.floor(bandit:getZ())
    radius = radius or director.Config.lootScanRadius

    for r=0, radius do
        for dx=-r, r do
            for dy=-r, r do
                if r == 0 or math.abs(dx) == r or math.abs(dy) == r then
                    local square = cell:getGridSquare(bx + dx, by + dy, bz)
                    if square then
                        local objects = square:getObjects()
                        if objects then
                            for i=0, objects:size() - 1 do
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

function NPCBrainDirectorBridge.EvaluateDesiredState(director, runtime, bandit, brain, threat, stuck)
    if not director or not runtime then return nil, "no runtime" end
    if not bandit or not brain then return director.States.Disabled, "no brain" end
    if not runtime.isAlive(bandit) then return director.States.Dead, "dead" end

    local order = runtime.normalizeOrder(runtime.getOrder(brain))
    local programName = runtime.getProgramName(brain)
    if NPCOrderContract and NPCOrderContract.CanAggro and not NPCOrderContract.CanAggro(brain) then threat = nil end
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
    if threat and NPCSpyBridge and NPCSpyBridge.TryDefectOnThreat then
        local ok, defected = pcall(function() return NPCSpyBridge.TryDefectOnThreat(bandit, brain, threat) end)
        if ok and defected then threat = nil end
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
    local followDistance = tonumber(order.followDistance) or director.Config.followDistance
    local dist = runtime.dist(bandit:getX(), bandit:getY(), player:getX(), player:getY())
    if dist > followDistance then
        local tx, ty, tz = runtime.followFormationPoint(player, brain, bandit)
        return {runtime.moveToState(bandit, director.States.FollowPlayer, "follow master formation", tx, ty, tz, "Run", true)}
    end

    return {runtime.idleTask("near master")}
end

function NPCBrainDirectorBridge.HandleGuardPlayer(director, runtime, bandit, brain)
    if not director or not runtime then return {} end

    local player = runtime.masterPlayer(bandit, brain)
    if not player then return NPCBrainDirectorBridge.HandleIdle(director, runtime, bandit, brain, director.States.Idle, "no guarded player") end

    local dist = runtime.dist(bandit:getX(), bandit:getY(), player:getX(), player:getY())
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

    brain.holdPoint = brain.holdPoint or {x=bandit:getX(), y=bandit:getY(), z=bandit:getZ()}
    local x, y, z = runtime.formationAnchor(brain, bandit, "holdPoint")
    local dist = runtime.dist(bandit:getX(), bandit:getY(), x, y)

    if dist > director.Config.holdRadius then
        return {runtime.moveToState(bandit, director.States.HoldPosition, "return to hold point", x, y, z, "Run", true)}
    end

    return {runtime.idleTask("hold position")}
end

function NPCBrainDirectorBridge.HandleGuardArea(director, runtime, bandit, brain, state, radius)
    if not director or not runtime then return {} end

    local x, y, z = runtime.formationAnchor(brain, bandit, "guardPoint")
    local dist = runtime.dist(bandit:getX(), bandit:getY(), x, y)
    radius = radius or director.Config.guardRadius

    if dist > radius then
        return {runtime.moveToState(bandit, state or director.States.GuardArea, "return to guarded area", x, y, z, "Run", true)}
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
            local style = "Run"
            if squadPoint.mode == "suppress" or squadPoint.mode == "cover" or state == director.States.HoldAngle or state == director.States.SuppressEnemy then
                style = "Walk"
            end
            return {runtime.moveToState(bandit, state, squadPoint.reason or fallbackReason or "squad dynamic move", squadPoint.x, squadPoint.y, squadPoint.z or bandit:getZ(), style, false)}
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
        return {runtime.moveToState(bandit, director.States.KeepDistance, "keep firearm distance", fx, fy, fz, "Run", false)}
    end

    return {}
end

function NPCBrainDirectorBridge.HandleRegroup(director, runtime, bandit, brain)
    if not director or not runtime then return {} end

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

    elseif state == director.States.Attack
        or state == director.States.EmergencyDefense
        or state == director.States.MeleeFallback then
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
            NPCSquadDynamicsBridge.Tick(bandit, brain, uTick, brain.radioThreat)
        end)
    end

    -- Never interfere with active combat/actions.
    if runtime.hasActionTask(bandit) then return tasks end

    local currentAction = runtime.currentAction(bandit)
    if runtime.isCombatAction(currentAction) then return tasks end

    local now = runtime.now()
    local threat = runtime.findNearestThreat(bandit, brain, 18)
    if threat and NPCSpyBridge and NPCSpyBridge.TryDefectOnThreat then
        local ok, defected = pcall(function() return NPCSpyBridge.TryDefectOnThreat(bandit, brain, threat) end)
        if ok and defected then threat = nil end
    end
    local stuck = runtime.updateWatchdog(bandit, brain, now)
    local state, reason = director.EvaluateDesiredState(bandit, brain, threat, stuck)

    -- Non-combat spacing gets a chance before normal idle only.
    if state == director.States.Idle and uTick % 9 == 0 and runtime.countNearbyFriends(bandit, brain, 1.1) > 0 then
        state = director.States.Regroup
        reason = "group spacing"
    end

    runtime.setState(brain, state, reason, now)

    if state == director.States.Idle and NPCSquadDynamicsBridge and NPCSquadDynamicsBridge.GetAmbientTask then
        local okAmbient, ambientSpec = pcall(function()
            return NPCSquadDynamicsBridge.GetAmbientTask(bandit, brain, uTick)
        end)
        if okAmbient and ambientSpec and runtime.handleSquadDynamicTask then
            local ambientTasks = runtime.handleSquadDynamicTask(bandit, brain, ambientSpec)
            if ambientTasks and #ambientTasks > 0 then return ambientTasks end
        end
    end

    local planned = director.ExecuteState(bandit, brain, state, reason, threat)
    if planned and #planned > 0 then
        return planned
    end

    return tasks
end

