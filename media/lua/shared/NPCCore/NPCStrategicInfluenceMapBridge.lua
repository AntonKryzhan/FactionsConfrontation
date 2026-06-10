-- NPCStrategicInfluenceMapBridge.lua
-- Lightweight composite influence scoring for virtual war targets.
-- Lower scores are better targets for the existing world-director selectors.

NPCStrategicInfluenceMapBridge = NPCStrategicInfluenceMapBridge or {}
NPCStrategicInfluenceMapBridge.VERSION = "2026-06-02-stage382-strategic-influence-1"

local function sim_dist(a, b)
    if not (a and b and a.x and a.y and b.x and b.y) then return 999999 end
    local dx = (tonumber(a.x) or 0) - (tonumber(b.x) or 0)
    local dy = (tonumber(a.y) or 0) - (tonumber(b.y) or 0)
    return math.sqrt(dx * dx + dy * dy)
end

local function sim_owner(base)
    if not base then return nil end
    local owner = base.owner or base.captureTeam or base.commanderSide
    owner = tostring(owner or "")
    if owner == "" or owner == "nil" then return nil end
    return owner:lower()
end

local function sim_sideLogistics(gmd, side)
    local war = gmd and gmd.WorldDirector and gmd.WorldDirector.strategicWar or nil
    local logistics = war and war.logistics or nil
    local data = logistics and logistics[side] or nil
    if type(data) ~= "table" then return nil end
    return data
end

local function sim_countActiveOps(gmd, side, key)
    local n = 0
    for _, group in pairs(gmd and gmd.VirtualGroups or {}) do
        if type(group) == "table" and not group.activated and group[key] == true then
            local gs = tostring(group.side or group.factionSide or group.patrolColor or (group.hostile and "red" or "green")):lower()
            if gs == side then n = n + 1 end
        end
    end
    return n
end

function NPCStrategicInfluenceMapBridge.CountSideBases(gmd, side)
    local n = 0
    for _, base in pairs(gmd and gmd.BaseCamps or {}) do
        if type(base) == "table" and sim_owner(base) == side then n = n + 1 end
    end
    return n
end

function NPCStrategicInfluenceMapBridge.SelectPressureSide(director, gmd, war, redGroups, greenGroups)
    local redBases = NPCStrategicInfluenceMapBridge.CountSideBases(gmd, "red")
    local greenBases = NPCStrategicInfluenceMapBridge.CountSideBases(gmd, "green")
    if redBases < greenBases then return "red" end
    if greenBases < redBases then return "green" end
    redGroups = tonumber(redGroups) or 0
    greenGroups = tonumber(greenGroups) or 0
    if redGroups + 1 < greenGroups then return "red" end
    if greenGroups + 1 < redGroups then return "green" end
    local last = war and (war.lastInfluencePressureSide or war.lastFlankSide or war.lastPressureSide) or nil
    return last == "red" and "green" or "red"
end

function NPCStrategicInfluenceMapBridge.ScoreTargetBase(director, gmd, side, base, context)
    if not (base and base.x and base.y and side) then return nil end
    context = context or {}
    local other = side == "red" and "green" or "red"
    local owner = sim_owner(base)
    local front = context.front
    local fromRecord = context.fromRecord or context.origin or front
    local ownAnchor = context.ownAnchor
    local enemyAnchor = context.enemyAnchor

    local score = 0
    if front then score = score + sim_dist(base, front) * (context.flank and 0.26 or 0.72) end
    if fromRecord then score = score + sim_dist(base, fromRecord) * (context.flank and 0.10 or 0.18) end
    if ownAnchor then score = score + sim_dist(base, ownAnchor) * (context.flank and 0.06 or 0.12) end
    if enemyAnchor then score = score - sim_dist(base, enemyAnchor) * (context.flank and 0.14 or 0.04) end

    if owner == other then score = score - (context.flank and 360 or 260) end
    if owner == nil then score = score - 80 end
    if base.captureTeam == side then score = score - 220 end
    if base.status == "contested" or base.status == "siege_contested" then score = score - 180 end

    local defense = tonumber(base.virtualGarrisonPower) or tonumber(base.defensePower) or 0
    local readiness = math.min(tonumber(base.defenseReadiness) or 70, tonumber(base.ammoReadiness) or 70, tonumber(base.logisticsReadiness) or 70)
    score = score + defense * (context.flank and 0.30 or 0.55)
    score = score + readiness * (context.flank and 0.85 or 1.35)
    if defense < 75 or readiness < 45 then score = score - (context.flank and 420 or 220) end

    local logistics = sim_sideLogistics(gmd, side)
    if logistics then
        local supply = tonumber(logistics.supply) or 80
        local ammo = tonumber(logistics.ammo) or 80
        local morale = tonumber(logistics.morale) or 80
        local readinessAvg = (supply + ammo + morale) / 3
        if readinessAvg < 45 then score = score + (45 - readinessAvg) * 18 end
        if context.flank and readinessAvg > 70 then score = score - (readinessAvg - 70) * 9 end
    end

    -- Encourage side pressure and avoid a single static straight front line.
    if context.flank and front and ownAnchor and enemyAnchor then
        local ax = (tonumber(enemyAnchor.x) or 0) - (tonumber(ownAnchor.x) or 0)
        local ay = (tonumber(enemyAnchor.y) or 0) - (tonumber(ownAnchor.y) or 0)
        local bx = (tonumber(base.x) or 0) - (tonumber(front.x) or 0)
        local by = (tonumber(base.y) or 0) - (tonumber(front.y) or 0)
        local cross = math.abs(ax * by - ay * bx) / math.max(1, math.sqrt(ax * ax + ay * ay))
        score = score - math.min(cross, 900) * 0.18
    end

    return score
end

function NPCStrategicInfluenceMapBridge.ScoreFrontTarget(director, gmd, side, base, front, fromRecord)
    return NPCStrategicInfluenceMapBridge.ScoreTargetBase(director, gmd, side, base, {front = front, fromRecord = fromRecord, flank = false})
end

function NPCStrategicInfluenceMapBridge.ScoreFlankTarget(director, gmd, side, base, war)
    if not war then return nil end
    return NPCStrategicInfluenceMapBridge.ScoreTargetBase(director, gmd, side, base, {
        front = war.front,
        ownAnchor = side == "red" and war.redAnchor or war.greenAnchor,
        enemyAnchor = side == "red" and war.greenAnchor or war.redAnchor,
        flank = true
    })
end

function NPCStrategicInfluenceMapBridge.ShouldSpawnFlank(director, gmd, side)
    local maxActive = tonumber(director and director.STRATEGIC_FLANK_OPERATION_MAX_ACTIVE_PER_SIDE) or 3
    local active = sim_countActiveOps(gmd, side, "strategicFlankOperation")
    if active >= maxActive then return false end
    local logistics = sim_sideLogistics(gmd, side)
    if logistics and ((tonumber(logistics.supply) or 100) < 30 or (tonumber(logistics.ammo) or 100) < 28) then return false end
    return true
end

return NPCStrategicInfluenceMapBridge
