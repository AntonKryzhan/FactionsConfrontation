-- NPCWorldRoutineBridge.lua
-- Sticky macro-routine layer for ordinary materialized NPCs.
-- Keeps autonomous NPCs from task-thrashing by choosing a short-lived
-- world routine: sweep block -> enter/search building -> loot -> leave.

require "NPCCore/NPCLootTargetCacheBridge"

NPCWorldRoutineBridge = NPCWorldRoutineBridge or {}

NPCWorldRoutineBridge.VERSION = "2026-05-31-stage311-world-routine-cache"

NPCWorldRoutineBridge.Config = NPCWorldRoutineBridge.Config or {
    decisionCooldownMs = 7200,
    routineTtlMs = 42000,
    failedTargetCooldownMs = 42000,
    targetScanRadius = 13,
    portalScanRadius = 6,
    sweepRadius = 18,
    lootArriveDist = 1.8,
    portalArriveDist = 1.7,
    postCombatPriorityMs = 15000,
    maxContainerScanObjects = 16,
    maxSquareChecks = 180,
    maxPortalChecks = 120
}

local function wr_nowMs()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then return math.floor((getGameTime():getWorldAgeHours() or 0) * 3600000) end
    return 0
end

local function wr_dist2(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return dx * dx + dy * dy
end

local function wr_dist(x1, y1, x2, y2)
    return math.sqrt(wr_dist2(x1, y1, x2, y2))
end

local function wr_rand(max)
    max = tonumber(max) or 1
    if max <= 0 then return 0 end
    if ZombRand then return ZombRand(max) end
    return math.floor(wr_nowMs() % max)
end

local function wr_isExplicitOrder(brain)
    if not brain then return false end
    local order = brain.order or brain.directorOrder
    if type(order) == "table" then
        local name = order.name or order.action or order.type or order.mode
        return name ~= nil and tostring(name) ~= "" and tostring(name):lower() ~= "free"
    end
    return order ~= nil and tostring(order) ~= "" and tostring(order):lower() ~= "free"
end

local function wr_isPlayerOwned(brain)
    if not brain then return false end
    return brain.master ~= nil or brain.mercenaryHired == true or brain.hired == true or brain.isPlayerGuard == true
end

local function wr_isBaseBound(brain)
    if not brain then return false end
    return brain.homeBaseZoneType ~= nil or brain.baseZoneType ~= nil or tostring((brain.program and brain.program.name) or "") == "BaseGuard"
end

local function wr_programName(brain)
    if brain and brain.program and brain.program.name then return tostring(brain.program.name) end
    if brain and brain.programName then return tostring(brain.programName) end
    return ""
end

local function wr_canAutonomy(chr, brain, threat)
    if not chr or not brain or threat then return false end
    if wr_isPlayerOwned(brain) or wr_isExplicitOrder(brain) then return false end
    if wr_isBaseBound(brain) then return false end
    local program = wr_programName(brain)
    if program == "Companion" or program == "CompanionGuard" or program == "BlackMarket" then return false end
    if NPCOrderContract and NPCOrderContract.CanAggro and not NPCOrderContract.CanAggro(brain) then return false end
    return true
end

local function wr_squareKey(x, y, z)
    if not x or not y then return nil end
    return tostring(math.floor(tonumber(x) or 0)) .. ":" .. tostring(math.floor(tonumber(y) or 0)) .. ":" .. tostring(math.floor(tonumber(z) or 0))
end

local function wr_getRoutine(brain)
    if not brain then return nil end
    brain.ai = brain.ai or {}
    brain.ai.worldRoutine = brain.ai.worldRoutine or {failed = {}}
    return brain.ai.worldRoutine
end

local function wr_getCell()
    if getCell then return getCell() end
    return nil
end

local function wr_getSquare(x, y, z)
    local cell = wr_getCell()
    if not cell or not cell.getGridSquare then return nil end
    local ok, square = pcall(function() return cell:getGridSquare(math.floor(x), math.floor(y), math.floor(z or 0)) end)
    if ok then return square end
    return nil
end

local function wr_getBuilding(square)
    if not square or not square.getBuilding then return nil end
    local ok, building = pcall(function() return square:getBuilding() end)
    if ok then return building end
    return nil
end

local function wr_sameBuilding(a, b)
    if not a or not b then return false end
    local ba = wr_getBuilding(a)
    local bb = wr_getBuilding(b)
    return ba ~= nil and bb ~= nil and ba == bb
end

local function wr_hasUsefulContainer(square)
    if not square or not square.getObjects then return false end
    local ok, objects = pcall(function() return square:getObjects() end)
    if not ok or not objects then return false end
    local maxObjects = math.min(objects:size() - 1, tonumber(NPCWorldRoutineBridge.Config.maxContainerScanObjects) or 16)
    for i = 0, maxObjects do
        local object = objects:get(i)
        local container = object and object.getContainer and object:getContainer() or nil
        if container then
            local empty = false
            pcall(function() empty = container:isEmpty() == true end)
            if not empty then return true end
        end
    end
    return false
end

local function wr_isFailed(routine, key, now)
    if not (routine and key) then return false end
    local failed = routine.failed or {}
    local untilMs = tonumber(failed[key]) or 0
    return untilMs > (now or wr_nowMs())
end

local function wr_markFailed(routine, key, now)
    if not (routine and key) then return end
    routine.failed = routine.failed or {}
    routine.failed[key] = (now or wr_nowMs()) + (tonumber(NPCWorldRoutineBridge.Config.failedTargetCooldownMs) or 42000)
end

local function wr_findContainerSquare(chr, routine, radius)
    if not (chr and chr.getX and chr.getY and chr.getZ) then return nil end
    radius = tonumber(radius) or NPCWorldRoutineBridge.Config.targetScanRadius or 13
    local now = wr_nowMs()

    if NPCLootTargetCacheBridge and NPCLootTargetCacheBridge.FindContainerSquare then
        local brain = nil
        local square = nil
        local ok = pcall(function()
            square = NPCLootTargetCacheBridge.FindContainerSquare(chr, radius, {
                brain = brain,
                need = "any",
                ttlMs = 6200,
                maxSquareChecks = tonumber(NPCWorldRoutineBridge.Config.maxSquareChecks) or 180,
                maxObjectChecks = tonumber(NPCWorldRoutineBridge.Config.maxContainerScanObjects) or 16,
                squareFilter = function(_, candidate)
                    local key = wr_squareKey(candidate:getX(), candidate:getY(), candidate:getZ())
                    return not wr_isFailed(routine, key, now)
                end
            })
        end)
        if ok and square then return square end
    end

    local cell = wr_getCell()
    if not cell then return nil end
    local bx = math.floor(chr:getX())
    local by = math.floor(chr:getY())
    local bz = math.floor(chr:getZ())
    local checks = 0
    local maxChecks = tonumber(NPCWorldRoutineBridge.Config.maxSquareChecks) or 180
    local seed = wr_rand(4)

    for r = 1, radius do
        for dx = -r, r do
            for dy = -r, r do
                if checks >= maxChecks then return nil end
                if math.abs(dx) == r or math.abs(dy) == r then
                    checks = checks + 1
                    local sx = bx + dx
                    local sy = by + dy
                    if ((sx + sy + seed) % 2) == 0 then
                        local key = wr_squareKey(sx, sy, bz)
                        if not wr_isFailed(routine, key, now) then
                            local square = cell:getGridSquare(sx, sy, bz)
                            if square and wr_hasUsefulContainer(square) then return square end
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function wr_isWindow(object)
    if not object then return false end
    if instanceof then
        local ok, result = pcall(function() return instanceof(object, "IsoWindow") end)
        if ok and result == true then return true end
    end
    return object.IsOpen ~= nil and object.ToggleWindow ~= nil
end

local function wr_windowOpen(object)
    if not object or not object.IsOpen then return false end
    local ok, open = pcall(function() return object:IsOpen() == true end)
    return ok and open == true
end

local function wr_windowSmashed(object)
    if not object or not object.isSmashed then return false end
    local ok, smashed = pcall(function() return object:isSmashed() == true end)
    return ok and smashed == true
end

local function wr_findWindowPortal(chr, targetSquare)
    if not (chr and targetSquare) then return nil end
    if NPCLootTargetCacheBridge and NPCLootTargetCacheBridge.FindWindowPortal then
        local ok, portal = pcall(function()
            return NPCLootTargetCacheBridge.FindWindowPortal(chr, targetSquare, {
                radius = tonumber(NPCWorldRoutineBridge.Config.portalScanRadius) or 6,
                maxChecks = tonumber(NPCWorldRoutineBridge.Config.maxPortalChecks) or 120,
                ttlMs = 9000
            })
        end)
        if ok and portal then return portal end
    end

    local cell = wr_getCell()
    if not cell then return nil end
    local bx = math.floor(chr:getX())
    local by = math.floor(chr:getY())
    local tx = targetSquare:getX()
    local ty = targetSquare:getY()
    local tz = targetSquare:getZ()
    local radius = tonumber(NPCWorldRoutineBridge.Config.portalScanRadius) or 6
    local maxChecks = tonumber(NPCWorldRoutineBridge.Config.maxPortalChecks) or 120
    local checks = 0
    local best = nil
    local bestScore = nil

    for r = 1, radius do
        for dx = -r, r do
            for dy = -r, r do
                if checks >= maxChecks then return best end
                if math.abs(dx) == r or math.abs(dy) == r then
                    checks = checks + 1
                    local square = cell:getGridSquare(tx + dx, ty + dy, tz)
                    if square and square.getObjects then
                        local ok, objects = pcall(function() return square:getObjects() end)
                        if ok and objects then
                            for i = 0, objects:size() - 1 do
                                local object = objects:get(i)
                                if wr_isWindow(object) then
                                    local sx = square:getX()
                                    local sy = square:getY()
                                    local score = wr_dist2(bx, by, sx, sy) + wr_dist2(tx, ty, sx, sy) * 0.35
                                    if not bestScore or score < bestScore then
                                        bestScore = score
                                        best = {x = sx, y = sy, z = square:getZ(), open = wr_windowOpen(object), smashed = wr_windowSmashed(object)}
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end

local function wr_moveTask(runtime, chr, state, reason, x, y, z, walkType, arriveDist)
    if not (runtime and runtime.moveToState and x and y) then return nil end
    local task = runtime.moveToState(chr, state, reason, x, y, z or (chr.getZ and chr:getZ()) or 0, walkType or "Walk", true)
    task.livingIntent = true
    task.livingMoveIntent = true
    task.worldRoutine = true
    task.directorReason = reason or task.directorReason or "world routine"
    task.arriveDist = tonumber(arriveDist) or task.arriveDist or 1.7
    task.pathThrottleMs = math.max(tonumber(task.pathThrottleMs) or 0, 2400)
    task.sameTargetPathThrottleMs = math.max(tonumber(task.sameTargetPathThrottleMs) or 0, 9000)
    return task
end

local function wr_faceTask(x, y, reason, time)
    if not x or not y then return nil end
    return {action = "FaceLocation", x = x, y = y, time = time or 30, director = true, livingIntent = true, worldRoutine = true, directorReason = reason or "world routine inspect"}
end

local function wr_timeTask(anim, time, reason)
    return {action = "Time", anim = anim or "ShiftWeight", time = time or 90, director = true, livingIntent = true, worldRoutine = true, directorReason = reason or "world routine"}
end

local function wr_chooseSweepPoint(chr, brain, routine)
    local ax = chr:getX()
    local ay = chr:getY()
    local az = chr:getZ()
    if brain and brain.patrolPoint and brain.patrolPoint.x and brain.patrolPoint.y then
        ax = tonumber(brain.patrolPoint.x) or ax
        ay = tonumber(brain.patrolPoint.y) or ay
        az = tonumber(brain.patrolPoint.z) or az
    end
    local radius = tonumber(NPCWorldRoutineBridge.Config.sweepRadius) or 18
    local angle = ((tonumber(routine.seed) or wr_rand(628)) + wr_rand(157)) / 100
    local dist = 7 + wr_rand(math.max(4, radius - 6))
    return ax + math.cos(angle) * dist, ay + math.sin(angle) * dist, az
end

local function wr_startRoutine(chr, brain, routine, kind, reason, now)
    routine.kind = kind
    routine.reason = reason or kind
    routine.startedAtMs = now
    routine.untilMs = now + (tonumber(NPCWorldRoutineBridge.Config.routineTtlMs) or 42000)
    routine.phase = "start"
    routine.seed = wr_rand(100000)
    routine.targetKey = nil
    routine.targetX = nil
    routine.targetY = nil
    routine.targetZ = nil
    routine.portalOpened = nil
    routine.completed = nil
end

local function wr_isRoutineExpired(routine, now)
    if not routine or not routine.kind then return true end
    return routine.untilMs ~= nil and now > routine.untilMs
end

function NPCWorldRoutineBridge.SuggestState(director, runtime, chr, brain, threat, health, order, programName)
    if not (director and director.States and wr_canAutonomy(chr, brain, threat)) then return nil end
    local routine = wr_getRoutine(brain)
    if not routine then return nil end
    local now = wr_nowMs()
    if routine.nextStateSuggestMs and now < routine.nextStateSuggestMs then return nil end
    routine.nextStateSuggestMs = now + 2600

    if wr_isRoutineExpired(routine, now) then
        local living = brain.ai and brain.ai.living or nil
        if living and living.postCombatUntilMs and now <= living.postCombatUntilMs + (tonumber(NPCWorldRoutineBridge.Config.postCombatPriorityMs) or 15000) then
            wr_startRoutine(chr, brain, routine, "scavenge", "routine: scavenge after fight", now)
        else
            local program = tostring(programName or wr_programName(brain))
            if program == "Looter" or program == "Raider" or program == "Thief" or wr_rand(3) == 0 then
                wr_startRoutine(chr, brain, routine, "scavenge", "routine: search building", now)
            else
                wr_startRoutine(chr, brain, routine, "sweep", "routine: sweep block", now)
            end
        end
    end

    if routine.kind == "scavenge" then return director.States.LootArea, routine.reason or "routine: search building" end
    if routine.kind == "sweep" then return director.States.PatrolArea, routine.reason or "routine: sweep block" end
    return nil
end

local function wr_planScavenge(director, runtime, chr, brain, routine, now)
    if not (director and runtime and chr and routine) then return nil end
    local state = director.States.LootArea or "LootArea"
    local targetSquare = nil
    if routine.targetX and routine.targetY then
        targetSquare = wr_getSquare(routine.targetX, routine.targetY, routine.targetZ or (chr.getZ and chr:getZ()) or 0)
        if targetSquare and not wr_hasUsefulContainer(targetSquare) and routine.phase ~= "exit" then targetSquare = nil end
    end
    if not targetSquare then
        targetSquare = wr_findContainerSquare(chr, routine, NPCWorldRoutineBridge.Config.targetScanRadius)
        if targetSquare then
            routine.targetX = targetSquare:getX()
            routine.targetY = targetSquare:getY()
            routine.targetZ = targetSquare:getZ()
            routine.targetKey = wr_squareKey(routine.targetX, routine.targetY, routine.targetZ)
            routine.phase = "approach"
            routine.startedAtMs = now
            routine.untilMs = now + (tonumber(NPCWorldRoutineBridge.Config.routineTtlMs) or 42000)
        else
            wr_startRoutine(chr, brain, routine, "sweep", "routine: no nearby loot, sweep block", now)
            return nil
        end
    end

    if routine.startedAtMs and now - routine.startedAtMs > 18000 and wr_dist(chr:getX(), chr:getY(), routine.targetX, routine.targetY) > 4.0 then
        wr_markFailed(routine, routine.targetKey, now)
        if NPCLootTargetCacheBridge and NPCLootTargetCacheBridge.MarkFailed then
            pcall(function() NPCLootTargetCacheBridge.MarkFailed(brain, routine.targetX, routine.targetY, routine.targetZ, NPCWorldRoutineBridge.Config.failedTargetCooldownMs) end)
        end
        wr_startRoutine(chr, brain, routine, "sweep", "routine: blocked building, try another target", now)
        return nil
    end

    local tasks = {}
    local targetX = routine.targetX + 0.5
    local targetY = routine.targetY + 0.5
    local targetZ = routine.targetZ or chr:getZ()
    local dist = wr_dist(chr:getX(), chr:getY(), targetX, targetY)
    local currentSquare = wr_getSquare(chr:getX(), chr:getY(), chr:getZ())
    local needEntry = targetSquare and currentSquare and wr_getBuilding(targetSquare) ~= nil and not wr_sameBuilding(currentSquare, targetSquare)

    if routine.phase == "exit" then
        local ex, ey, ez = wr_chooseSweepPoint(chr, brain, routine)
        tasks[#tasks + 1] = wr_moveTask(runtime, chr, director.States.PatrolArea or state, "routine: leave searched building", ex, ey, ez, "Walk", 2.0)
        routine.completed = true
        routine.kind = nil
        routine.phase = nil
        return tasks
    end

    if needEntry then
        local portal = wr_findWindowPortal(chr, targetSquare)
        if portal then
            local portalDist = wr_dist(chr:getX(), chr:getY(), portal.x + 0.5, portal.y + 0.5)
            if portalDist > (tonumber(NPCWorldRoutineBridge.Config.portalArriveDist) or 1.7) then
                tasks[#tasks + 1] = wr_moveTask(runtime, chr, state, "routine: approach building entry", portal.x, portal.y, portal.z, "Walk", 1.7)
                return tasks
            end
            if not routine.portalOpened and not portal.open and not portal.smashed then
                tasks[#tasks + 1] = {action = "OpenWindow", anim = "WindowOpen", time = 35, x = portal.x, y = portal.y, z = portal.z, director = true, livingIntent = true, worldRoutine = true, directorReason = "routine: try window entry"}
                routine.portalOpened = true
                return tasks
            end
            if routine.portalOpened and not routine.portalSmashed and not portal.open and not portal.smashed and now - (routine.startedAtMs or now) > 5200 then
                tasks[#tasks + 1] = {action = "SmashWindow", anim = "WindowSmash", time = 45, x = portal.x, y = portal.y, z = portal.z, director = true, livingIntent = true, worldRoutine = true, directorReason = "routine: force blocked window"}
                routine.portalSmashed = true
                return tasks
            end
        end
    end

    if dist > (tonumber(NPCWorldRoutineBridge.Config.lootArriveDist) or 1.8) then
        tasks[#tasks + 1] = wr_moveTask(runtime, chr, state, "routine: move to search container", routine.targetX, routine.targetY, targetZ, "Walk", 1.8)
        return tasks
    end

    tasks[#tasks + 1] = wr_faceTask(targetX + wr_rand(3) - 1, targetY + wr_rand(3) - 1, "routine: check shelves", 25)
    tasks[#tasks + 1] = {action = "LootItems", anim = "Loot", time = 115, x = routine.targetX, y = routine.targetY, z = targetZ, director = true, livingIntent = true, worldRoutine = true, directorState = state, directorReason = "routine: loot searched container"}
    tasks[#tasks + 1] = wr_timeTask("LootLow", 65, "routine: inspect room")
    routine.phase = "exit"
    routine.startedAtMs = now
    return tasks
end

local function wr_planSweep(director, runtime, chr, brain, routine, now)
    if not (director and runtime and chr and routine) then return nil end
    local state = director.States.PatrolArea or "PatrolArea"
    if not routine.targetX or not routine.targetY or wr_dist(chr:getX(), chr:getY(), routine.targetX, routine.targetY) < 2.2 then
        if routine.phase == "inspect" then
            local tasks = {wr_faceTask(chr:getX() + wr_rand(5) - 2, chr:getY() + wr_rand(5) - 2, "routine: watch street", 35), wr_timeTask("ShiftWeight", 80, "routine: brief overwatch")}
            routine.kind = nil
            routine.phase = nil
            return tasks
        end
        local x, y, z = wr_chooseSweepPoint(chr, brain, routine)
        routine.targetX = x
        routine.targetY = y
        routine.targetZ = z
        routine.phase = "move"
        routine.startedAtMs = now
    end
    if routine.phase == "move" then
        routine.phase = "inspect"
        return {wr_moveTask(runtime, chr, state, "routine: sweep next block", routine.targetX, routine.targetY, routine.targetZ or chr:getZ(), "Walk", 2.1)}
    end
    return nil
end

function NPCWorldRoutineBridge.PlanTasks(director, runtime, chr, brain, state, reason, threat, uTick)
    if not wr_canAutonomy(chr, brain, threat) then return nil end
    local currentAction = runtime and runtime.currentAction and runtime.currentAction(chr) or nil
    if currentAction == "Shoot" or currentAction == "Aim" or currentAction == "Hit" or currentAction == "Shove" or currentAction == "Reload" then return nil end

    local routine = wr_getRoutine(brain)
    if not routine then return nil end
    local now = wr_nowMs()
    if routine.nextPlanMs and now < routine.nextPlanMs then return nil end
    routine.nextPlanMs = now + (tonumber(NPCWorldRoutineBridge.Config.decisionCooldownMs) or 7200)

    if wr_isRoutineExpired(routine, now) then
        NPCWorldRoutineBridge.SuggestState(director, runtime, chr, brain, threat, nil, nil, wr_programName(brain))
    end

    if routine.kind == "scavenge" then
        local tasks = wr_planScavenge(director, runtime, chr, brain, routine, now)
        if tasks and #tasks > 0 then return tasks end
    elseif routine.kind == "sweep" then
        local tasks = wr_planSweep(director, runtime, chr, brain, routine, now)
        if tasks and #tasks > 0 then return tasks end
    end

    return nil
end
