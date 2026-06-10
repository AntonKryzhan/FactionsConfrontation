require "NPCBehavior/NPCBehaviorBridge"
require "NPCCore/NPCLootTargetCacheBridge"
require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCPostCombatLootBridge"
require "NPCCore/NPCSquadDynamicsBridge"

NPCProgramCompanionBridge = NPCProgramCompanionBridge or {}

local Bridge = NPCBehaviorBridge
local NPC_COMPANION_LEGACY_KEYS = {
    immediateAnim = NPCLegacyContractBridge.Keys.IMMEDIATE_ANIM
}

local function npcSandboxBool(name, fallback)
    if Bridge and Bridge.GetSandboxBool then return Bridge.GetSandboxBool(name, fallback) end
    local vars = SandboxVars and SandboxVars[NPCLegacyContractBridge.Sandbox.main] or nil
    if vars and vars[name] ~= nil then return vars[name] == true end
    return fallback == true
end

local function npcCompanionNowMs()
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

local function npcCompanionDist2(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return dx * dx + dy * dy
end

local function npcCompanionResolveFreeFollowSlot(master, dx, dy, dz)
    if not (master and dx and dy) then return dx, dy, dz end
    local cell = getCell and getCell() or nil
    if not cell then return dx, dy, dz end

    local z = math.floor(tonumber(dz) or (master.getZ and master:getZ()) or 0)
    local cx = math.floor(tonumber(dx) or 0)
    local cy = math.floor(tonumber(dy) or 0)
    local bestSquare = nil
    local bestScore = nil

    for r = 0, 2 do
        for ox = -r, r do
            for oy = -r, r do
                if r == 0 or math.abs(ox) == r or math.abs(oy) == r then
                    local square = cell:getGridSquare(cx + ox, cy + oy, z)
                    local free = false
                    if square then
                        local ok, value = pcall(function() return square:isFree(false) end)
                        free = (not ok) or value == true
                    end
                    if free then
                        local sx = square:getX() + 0.5
                        local sy = square:getY() + 0.5
                        local score = npcCompanionDist2(sx, sy, dx, dy)
                        if master.getX and master.getY then
                            local md = math.sqrt(npcCompanionDist2(sx, sy, master:getX(), master:getY()))
                            if md < 0.55 or md > 3.8 then score = score + 8 end
                        end
                        if not bestScore or score < bestScore then
                            bestScore = score
                            bestSquare = square
                        end
                    end
                end
            end
        end
        if bestSquare and r >= 1 then break end
    end

    if bestSquare then
        return bestSquare:getX() + 0.5, bestSquare:getY() + 0.5, bestSquare:getZ()
    end
    return dx, dy, dz
end

local function npcCompanionStabilizeStrictFollowSlot(brain, master, dx, dy, dz, leaderDriven)
    if not (brain and master and dx and dy) then return dx, dy, dz end
    brain.ai = brain.ai or {}
    local seq = 0
    if type(brain.order) == "table" and tonumber(brain.order.sequence) then seq = tonumber(brain.order.sequence) end
    local key = leaderDriven and "strictLeaderFollowSlot" or "strictFollowSlot"
    local slot = brain.ai[key]
    local nowMs = npcCompanionNowMs()
    local anchorDelta = leaderDriven and 0.95 or 0.28
    local targetDelta = leaderDriven and 1.15 or 0.38
    local maxAgeMs = leaderDriven and 1400 or 520

    if type(slot) == "table" and slot.seq == seq and slot.x and slot.y then
        local anchorMoved = false
        if slot.mx and slot.my then
            anchorMoved = npcCompanionDist2(slot.mx, slot.my, master:getX(), master:getY()) > anchorDelta * anchorDelta
        end
        local targetMoved = npcCompanionDist2(slot.x, slot.y, dx, dy) > targetDelta * targetDelta
        local expired = nowMs > 0 and tonumber(slot.at) and (nowMs - tonumber(slot.at)) > maxAgeMs
        if not anchorMoved and not targetMoved and not expired then
            return slot.x, slot.y, slot.z or dz
        end
    end

    brain.ai[key] = {
        seq = seq,
        x = dx,
        y = dy,
        z = dz,
        mx = master:getX(),
        my = master:getY(),
        mz = master:getZ(),
        at = nowMs
    }
    return dx, dy, dz
end

NPCProgramCompanionBridge.Init = function(bandit)
end

NPCProgramCompanionBridge.GetCapabilities = function()
    -- capabilities are program decided
    local capabilities = {}
    capabilities.melee = true
    capabilities.shoot = true
    capabilities.smashWindow = false
    capabilities.openDoor = true
    capabilities.breakDoor = false
    capabilities.breakObjects = false
    capabilities.unbarricade = false
    capabilities.disableGenerators = false
    capabilities.sabotageCars = false
    return capabilities
end

NPCProgramCompanionBridge.Prepare = function(bandit)
    local tasks = {}
    local world = getWorld()
    local cm = world:getClimateManager()
    local dls = cm:getDayLightStrength()

    local weapons = NPCEntity.GetWeapons(bandit)
    local primary = NPCEntity.GetBestWeapon(bandit)

    NPCEntity.ForceStationary(bandit, false)
    NPCEntity.SetWeapons(bandit, weapons)

    local secondary
    if npcSandboxBool("General_CarryTorches", false) and dls < 0.3 then
        secondary = "Base.HandTorch"
    end

    if weapons.secondary.name then
        local task1 = {action="Unequip", time=100, itemPrimary=weapons.secondary.name}
        table.insert(tasks, task1)
    end

    local task2 = {action="Equip", itemPrimary=primary, itemSecondary=secondary}
    table.insert(tasks, task2)

    return {status=true, next="Follow", tasks=tasks}
end



-- Stage 25 routes mercenary search, tactical point and mobile orders through
-- NPCBehaviorBridge. The public function names remain in this file so old
-- program dispatch, stale tasks and external calls keep their current contract.

NPCProgramCompanionBridge.TryLootHouseOrder = function(bandit, brain, order, tasks, endurance)
    if NPCBehaviorBridge and NPCBehaviorBridge.CompanionTryLootHouseOrder then
        return NPCBehaviorBridge.CompanionTryLootHouseOrder(bandit, brain, order, tasks, endurance)
    end
    return nil
end

NPCProgramCompanionBridge.TryTacticalPointOrder = function(bandit, brain, order, tasks, endurance)
    if NPCBehaviorBridge and NPCBehaviorBridge.CompanionTryTacticalPointOrder then
        return NPCBehaviorBridge.CompanionTryTacticalPointOrder(bandit, brain, order, tasks, endurance)
    end
    return nil
end

NPCProgramCompanionBridge.TryMobileOrder = function(bandit, brain, orderName, tasks)
    if NPCBehaviorBridge and NPCBehaviorBridge.CompanionTryMobileOrder then
        return NPCBehaviorBridge.CompanionTryMobileOrder(bandit, brain, orderName, tasks)
    end
    return nil
end

function NPCProgramCompanionBridge.IsPlayerCommandOrder(brain, order)
    if not (brain and order and NPCOrderContract and NPCOrderContract.IsPlayerCommandedOrderActive) then return false end
    local ok, active = pcall(function() return NPCOrderContract.IsPlayerCommandedOrderActive(brain) end)
    return ok and active == true
end

NPCProgramCompanionBridge.TryVehicleSync = function(bandit, master, vehicle, dist, tasks)
    if not npcSandboxBool("General_EnterVehicles", false) then return nil end

    if vehicle then
        if dist < 2.2 then
            local bvehicle = bandit:getVehicle()
            if bvehicle then
                bandit:changeState(ZombieOnGroundState.instance())
                return "Follow"
            else
                print ("ENTER VEH")
                local vx = bandit:getForwardDirection():getX()
                local vy = bandit:getForwardDirection():getY()
                local forwardVector = Vector3f.new(vx, vy, 0)

                for seat=1, 10 do
                    if vehicle:isSeatInstalled(seat) and not vehicle:isSeatOccupied(seat) then
                        bandit:enterVehicle(vehicle, seat, forwardVector)
                        bandit:playSound("VehicleDoorOpen")
                        break
                    end
                end
            end
        end
    else
        local bvehicle = bandit:getVehicle()
        if bvehicle then
            print ("EXIT VEH")
            -- After exiting the vehicle, the companion is in the ongroundstate.
            -- Additionally he is under the car. This is fixed in NPC update loop. 
            bandit:setVariable(NPC_COMPANION_LEGACY_KEYS.immediateAnim, true)
            bvehicle:exit(bandit)
            bandit:playSound("VehicleDoorClose")
        end
    end

    return nil
end

NPCProgramCompanionBridge.TryProtectMaster = function(bandit, dist, tasks, endurance)
    if dist < 20 then
        local enemy
        local closestZombie = NPCUtils.GetClosestZombieLocation(bandit)
        local closestNPC = NPCUtils.GetClosestEnemyNPCLocation(bandit)
        local closestEnemy = closestZombie

        if closestNPC.dist < closestZombie.dist then 
            closestEnemy = closestNPC
            enemy = NPCZombieCacheBridge.Cache[closestEnemy.id]
        end

        if closestEnemy.dist < 8 then
            -- We are trying to save the player, so the friendly should act with high motivation
            -- that translates to running pace (even despite limping) and minimal endurance loss.

            local closeSlow = true
            if enemy then
                local weapon = enemy:getPrimaryHandItem()
                if weapon and weapon:IsWeapon() then
                    local weaponType = WeaponType.getWeaponType(weapon)
                    if weaponType == WeaponType.firearm or weaponType == WeaponType.handgun then
                        closeSlow = false
                    end
                end
            end

            table.insert(tasks, NPCUtils.GetMoveTask(endurance, closestEnemy.x, closestEnemy.y, closestEnemy.z, "Run", closestEnemy.dist, closeSlow))
            return "Follow"
        end
    end

    return nil
end

NPCProgramCompanionBridge.TryLootWeapons = function(bandit, cell, tasks)
    if not NPCEntity.IsOutOfAmmo(bandit) then return nil end

    local brain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(bandit) or nil
    if brain and (brain.master ~= nil or brain.mercenaryHired == true or brain.mercenaryHiredBy ~= nil or brain.isPlayerGuard == true or (brain.relationshipToPlayer == "hired_bodyguard" or brain.relationshipToPlayer == "companion")) then
        local order = NPCBehaviorBridge and NPCBehaviorBridge.CompanionGetOrder and NPCBehaviorBridge.CompanionGetOrder(brain) or brain.order
        local manualAllowed = NPCPostCombatLootBridge and NPCPostCombatLootBridge.IsManualLootOrder and NPCPostCombatLootBridge.IsManualLootOrder(order)
        if manualAllowed ~= true then return nil end
    end

    -- Stage 311: prefer shared building/container cache before doing any room-wide scan.
    if NPCLootTargetCacheBridge and NPCLootTargetCacheBridge.FindContainerSquare then
        local ok, square = pcall(function()
            return NPCLootTargetCacheBridge.FindContainerSquare(bandit, 10, {need = "ammo", ttlMs = 5200, maxSquareChecks = 110, maxObjectChecks = 12, maxItemChecks = 45})
        end)
        if ok and square then
            local objects = square:getObjects()
            if objects then
                for i=0, math.min(objects:size() - 1, 11) do
                    local object = objects:get(i)
                    local container = object and object.getContainer and object:getContainer() or nil
                    if container and not container:isEmpty() then
                        local subTasks = NPCPrograms.Container.WeaponLoot(bandit, object, container)
                        if #subTasks > 0 then
                            for _, subTask in pairs(subTasks) do
                                table.insert(tasks, subTask)
                            end
                            return "Prepare"
                        end
                    end
                end
            end
        end
    end

    -- deadbodies: bounded ring scan, not a full 25x25x3 sweep every decision.
    local bx = math.floor(bandit:getX())
    local by = math.floor(bandit:getY())
    local bz = math.floor(bandit:getZ())
    local checks = 0
    for r=0, 8 do
        for x=-r, r do
            for y=-r, r do
                if checks >= 120 then break end
                if r == 0 or math.abs(x) == r or math.abs(y) == r then
                    checks = checks + 1
                    local square = cell:getGridSquare(bx + x, by + y, bz)
                    if square then
                        local body = square:getDeadBody()
                        if body then
                            local objects = square:getStaticMovingObjects()
                            if objects then
                                for i=0, objects:size()-1 do
                                    local object = objects:get(i)
                                    if instanceof (object, "IsoDeadBody") then
                                        local body = object
                                        local container = body:getContainer()
                                        if container and not container:isEmpty() then
                                            local subTasks = NPCPrograms.Container.WeaponLoot(bandit, body, container)
                                            if #subTasks > 0 then
                                                for _, subTask in pairs(subTasks) do
                                                    table.insert(tasks, subTask)
                                                end
                                                return "Prepare"
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
            if checks >= 120 then break end
        end
        if checks >= 120 then break end
    end

    -- containers in current room only; shared cache handles broader building scans.
    local square = bandit:getSquare()
    local room = square and square:getRoom() or nil
    if room then
        local roomDef = room:getRoomDef()
        local inspected = 0
        for x=roomDef:getX(), roomDef:getX2() do
            for y=roomDef:getY(), roomDef:getY2() do
                if inspected >= 80 then break end
                local square = cell:getGridSquare(x, y, roomDef:getZ())
                if square then
                    inspected = inspected + 1
                    local objects = square:getObjects()
                    if objects then
                        for i=0, math.min(objects:size() - 1, 11) do
                            local object = objects:get(i)
                            local container = object and object.getContainer and object:getContainer() or nil
                            if container and not container:isEmpty() then
                                local subTasks = NPCPrograms.Container.WeaponLoot(bandit, object, container)
                                if #subTasks > 0 then
                                    for _, subTask in pairs(subTasks) do
                                        table.insert(tasks, subTask)
                                    end
                                    return "Prepare"
                                end
                            end
                        end
                    end
                end
            end
            if inspected >= 80 then break end
        end
    end

    return nil
end

NPCProgramCompanionBridge.TryGuardpost = function(bandit, tasks, endurance, walkType, dist)
    -- If there is a guardpost in the vicinity, take it.
    local guardpost = NPCPost.GetClosestFree(bandit, "guard", 40)
    if guardpost then
        table.insert(tasks, NPCUtils.GetMoveTask(endurance, guardpost.x, guardpost.y, guardpost.z, walkType, dist, false))
        return "Follow"
    end

    return nil
end

NPCProgramCompanionBridge.TryFishing = function(bandit, cell, tasks, endurance)
    local gameTime = getGameTime()
    local hour = gameTime:getHour()
    if (hour >= 4 and hour < 6) or (hour >= 18 and hour < 21) then
        local vectors = {}
        table.insert(vectors, {x=0, y=-1}) --12
        table.insert(vectors, {x=1, y=-1}) -- 1.30
        table.insert(vectors, {x=1, y=0}) -- 3
        table.insert(vectors, {x=1, y=1}) -- 4.30
        table.insert(vectors, {x=0, y=1}) -- 6
        table.insert(vectors, {x=-1, y=1}) -- 7.30
        table.insert(vectors, {x=-1, y=0}) -- 9
        table.insert(vectors, {x=-1, y=-1}) -- 10.30
        
        local bx = bandit:getX()
        local by = bandit:getY()
        local wx
        local wy
        local wd = 31
        local wsquare
        for _, vector in pairs(vectors) do
            for i=1, 30 do
                local x = bx + vector.x * i
                local y = by + vector.y * i
                local square = cell:getGridSquare(x, y, 0)
                if square and NPCUtils.IsWater(square) then
                    if i < wd then
                        wx, wy, wd = x, y, i
                        wsquare = square
                        break
                    end
                end
            end
        end

        if wx and wy then
            local asquare = AdjacentFreeTileFinder.Find(wsquare, bandit)
            if asquare then
                local tx = asquare:getX() + 0.5
                local ty = asquare:getY() + 0.5

                local dist = NPCUtils.DistTo(bx, by, tx, ty)
                if dist < 1.0 then
                    print ("should fish")
                    local task = {action="Fishing", time=1000, x=wx, y=wy}
                    table.insert(tasks, task)
                    return "Follow"
                else
                    table.insert(tasks, NPCUtils.GetMoveTask(endurance, tx, ty, 0, "Run", dist, false))
                    return "Follow"
                end
            end
        end
    end

    return nil
end

NPCProgramCompanionBridge.TryForaging = function(bandit, cm, tasks)
    -- companion foraging
    local dls = cm:getDayLightStrength()
    local rain = cm:getRainIntensity()
    local fog = cm:getFogIntensity()
    local zoneData = forageSystem.getForageZoneAt(bandit:getX(), bandit:getY())

    local inZone = false
    local zone = getWorld():getMetaGrid():getZoneAt(bandit:getX(), bandit:getY(), 0)
    if zone then
        local zoneType = zone:getType()
        if zoneType == "Forest" or zoneType == "DeepForest" or zoneType == "Vegitation" or zoneType == "FarmLand" then
            inZone = true
        end
    end

    if false and zoneData and inZone and dls > 0.8 and rain < 0.3 and fog < 0.2 then
        local month = getGameTime():getMonth() + 1
        local timeOfDay = forageSystem.getTimeOfDay() or "isDay"
        local weatherType = forageSystem.getWeatherType() or "isNormal"
        local lootTable = forageSystem.lootTables[zoneData.name][month][timeOfDay][weatherType]
        
        local itemType, catName = forageSystem.pickRandomItemType(lootTable)
        if itemType and catName then
            local item = NPCCompatibilityBridge.InstanceItem(itemType)
            if instanceof (item, "Food") then
                item:getProteins()
                item:getCalories()
                item:getCarbohydrates()
                item:isSpice()

                print ("found: " .. itemType)
                local task = {action="Drop", anim="Forage", itemType=itemType, time=400}
                table.insert(tasks, task)

                -- local task2 = {action="Single", anim="Eat", time=400}
                -- table.insert(tasks, task2)
                -- local task3 = {action="Single", anim="Eat", time=400}
                -- table.insert(tasks, task3)
                return "Follow"
            end
        end
    end

    return nil
end

NPCProgramCompanionBridge.TryHomeBaseTasks = function(bandit, cm, tasks)
    -- companion homebase tasks

    -- companion generator maintenance
    -- FIXME: change to NOT
    if getWorld():isHydroPowerOn() then 
        local generator = NPCBaseClient.GetGenerator(bandit)
        if generator then
            local condition = generator:getCondition()
            if condition < 60 or (condition <=95 and not generator:isActivated()) then
                local subTasks = NPCPrograms.Generator.Repair(bandit, generator)
                if #subTasks > 0 then
                    for _, subTask in pairs(subTasks) do
                        table.insert(tasks, subTask)
                    end
                    return "Follow"
                end
            end

            local fuel = generator:getFuel()
            if fuel < 40 then
                local subTasks = NPCPrograms.Generator.Refuel(bandit, generator)
                if #subTasks > 0 then
                    for _, subTask in pairs(subTasks) do
                        table.insert(tasks, subTask)
                    end
                    return "Follow"
                end
            end
        end
    end

    -- gardening
    -- TODO: remove weed

    -- farming
    if not cm:isRaining() then
        local plant = NPCBaseClient.GetFarm(bandit)
        if plant and plant.waterNeeded > 0 and plant.waterLvl < 100 then
            local subTasks = NPCPrograms.Farm.Water(bandit, plant)
            if #subTasks > 0 then
                for _, subTask in pairs(subTasks) do
                    table.insert(tasks, subTask)
                end
                return "Follow"
            end
        end
    end

    -- unload collected food to fridge
    local subTasks
    subTasks = NPCPrograms.Misc.ReturnFood(bandit)
    if #subTasks > 0 then
        for _, subTask in pairs(subTasks) do
            table.insert(tasks, subTask)
        end
        return "Follow"
    end

    -- self
    subTasks = NPCPrograms.Self.Wash(bandit)
    if #subTasks > 0 then
        for _, subTask in pairs(subTasks) do
            table.insert(tasks, subTask)
        end
        return "Follow"
    end
    

    -- housekeeping
    subTasks = NPCPrograms.Housekeeping.FillGraves(bandit)
    if #subTasks > 0 then
        for _, subTask in pairs(subTasks) do
            table.insert(tasks, subTask)
        end
        return "Follow"
    end

    subTasks = NPCPrograms.Housekeeping.RemoveCorpses(bandit)
    if #subTasks > 0 then
        for _, subTask in pairs(subTasks) do
            table.insert(tasks, subTask)
        end
        return "Follow"
    end

    subTasks = NPCPrograms.Housekeeping.RemoveTrash(bandit)
    if #subTasks > 0 then
        for _, subTask in pairs(subTasks) do
            table.insert(tasks, subTask)
        end
        return "Follow"
    end

    subTasks = NPCPrograms.Housekeeping.CleanBlood(bandit)
    if #subTasks > 0 then
        for _, subTask in pairs(subTasks) do
            table.insert(tasks, subTask)
        end
        return "Follow"
    end

    return nil
end

NPCProgramCompanionBridge.TryFollowSlot = function(bandit, master, brain, order, tasks, endurance, walkType)
    -- Follow the player, or for hired squads let the squad leader follow the
    -- player while other members walk by short local slots around the leader.
    local minDist = 2
    local dx, dy, dz = nil, nil, nil
    local followDistance = order and tonumber(order.followDistance) or nil
    local formation = order and order.formation or "close"
    local strictFollow = order and order.name == "Follow" and brain and brain.mercenaryHired == true
    local leaderDriven = false
    local leaderPoint = nil

    -- Stage 370: player Follow is a bodyguard formation, not a direct run into
    -- the player's tile.  Formation changes are allowed while moving; the target
    -- slot is refreshed frequently so guards walk shoulder-to-shoulder with the
    -- player instead of lagging behind or piling into one point.
    -- Stage 446/370: player-commanded Follow must be a player-anchored
    -- bodyguard formation around the player.  The old leader-driven helper can use stale
    -- squad-channel leader coordinates and make mercenaries spread around the
    -- map instead of converging to the player's formation slots.
    if strictFollow and not (order and (order.commandAuthority == "player" or order.playerCommand == true or order.source == "player")) and NPCSquadDynamicsBridge and NPCSquadDynamicsBridge.GetLeaderFollowPoint then
        local ok, point = pcall(function()
            return NPCSquadDynamicsBridge.GetLeaderFollowPoint(bandit, brain, master, order)
        end)
        if ok and point and point.x and point.y then
            leaderDriven = true
            leaderPoint = point
            dx, dy, dz = point.x, point.y, point.z
            minDist = tonumber(point.arriveDist) or 1.15
            if point.walkType then walkType = point.walkType end
            if point.catchUp == true then endurance = -0.07 end
        elseif ok and point and point.isLeader == true then
            -- The leader keeps the old player-follow behavior. Followers will
            -- use this leader's position as their locomotion anchor.
            leaderDriven = false
        end
    end

    if strictFollow then
        -- Tight bodyguard follow.  The arrival radius stays below one tile so
        -- walking guards keep correcting their shoulder slot while the player moves.
        minDist = leaderDriven and math.max(minDist, 1.15) or 0.72
        followDistance = tonumber(followDistance) or 0.95
        if followDistance < 0.75 then followDistance = 0.75 end
        if followDistance > 2.4 then followDistance = 2.4 end
    end

    if not (dx and dy) then
        if order and (order.name == "Hold" or order.name == "Guard") and order.anchor and order.anchor.x and order.anchor.y then
            if NPCFormationSlotsBridge and NPCFormationSlotsBridge.GetAnchorSlotPoint then
                dx, dy, dz = NPCFormationSlotsBridge.GetAnchorSlotPoint(order.anchor, brain, bandit, formation or "close", followDistance or 2.0)
            end
            if not (dx and dy) then
                dx = tonumber(order.anchor.x)
                dy = tonumber(order.anchor.y)
                dz = tonumber(order.anchor.z) or master:getZ()
            end
            minDist = 1.0
        elseif NPCFormationSlotsBridge then
            if strictFollow and NPCFormationSlotsBridge.GetPlayerFollowSlotPoint then
                dx, dy, dz = NPCFormationSlotsBridge.GetPlayerFollowSlotPoint(master, brain, bandit, formation or "close", followDistance or 3.0)
            elseif NPCFormationSlotsBridge.GetSlotPoint then
                dx, dy, dz = NPCFormationSlotsBridge.GetSlotPoint(master, brain, bandit, formation or "close", followDistance or 3.0)
            end
            if not strictFollow then minDist = 1.4 end
        end
    end

    if not (dx and dy) then
        local id = NPCUtils.GetCharacterID(bandit)

        local theta = master:getDirectionAngle() * math.pi / 180
        local lx = 3 * math.cos(theta)
        local ly = 3 * math.sin(theta)

        dx = master:getX() - lx
        dy = master:getY() - ly
        dz = master:getZ()
        dx = dx + ((math.abs(id) % 10) - 5) / 10
        dy = dy + ((math.abs(id) % 11) - 5) / 10
    end

    if strictFollow and dx and dy then
        if not leaderDriven then
            dx, dy, dz = npcCompanionResolveFreeFollowSlot(master, dx, dy, dz)
        end
        dx, dy, dz = npcCompanionStabilizeStrictFollowSlot(brain, master, dx, dy, dz, leaderDriven)
    end

    local slotDist = NPCUtils.DistTo(bandit:getX(), bandit:getY(), dx, dy)
    if strictFollow then
        local masterDist = NPCUtils.DistTo(bandit:getX(), bandit:getY(), master:getX(), master:getY())
        local mustCatchUp = masterDist > 3.8 or slotDist > (leaderDriven and 2.10 or 1.15)
        if leaderDriven and leaderPoint then
            mustCatchUp = leaderPoint.catchUp == true or slotDist > math.max(2.45, (tonumber(leaderPoint.arriveDist) or 1.35) + 1.10)
        end
        if mustCatchUp then
            walkType = (leaderDriven and leaderPoint and leaderPoint.walkType) or "Run"
            endurance = -0.07
            local hasActiveThreat = brain and (brain.currentThreat or brain.radioThreat or brain.squadPlanThreat or brain.targetId)
            if brain and (not leaderDriven or not hasActiveThreat) then
                brain.target = nil
                brain.targetId = nil
                brain.targetKind = nil
                brain.currentThreat = nil
                brain.lastThreat = nil
                if brain.fsm then
                    brain.fsm.targetId = nil
                    brain.fsm.targetKind = nil
                    brain.fsm.currentThreat = nil
                    brain.fsm.lastThreat = nil
                end
            end
        end
    end
    if slotDist > minDist then
        if strictFollow and brain then
            brain.ai = brain.ai or {}
            local nowMs = getTimestampMs and getTimestampMs() or 0
            local pathKey = leaderDriven and "leaderFollowSlotPathAtMs" or "followSlotPathAtMs"
            local xKey = leaderDriven and "leaderFollowSlotTargetX" or "followSlotTargetX"
            local yKey = leaderDriven and "leaderFollowSlotTargetY" or "followSlotTargetY"
            local lastMs = tonumber(brain.ai[pathKey]) or 0
            local lastX = tonumber(brain.ai[xKey])
            local lastY = tonumber(brain.ai[yKey])
            local targetDelta = leaderDriven and ((NPCSquadDynamicsBridge and NPCSquadDynamicsBridge.Config and tonumber(NPCSquadDynamicsBridge.Config.leaderFollowerSlotTargetDelta)) or 0.85) or 0.36
            local movedTarget = (not lastX or not lastY) or (NPCUtils and NPCUtils.DistTo and NPCUtils.DistTo(lastX, lastY, dx, dy) or 999) > targetDelta
            local minInterval = (walkType == "Run" or slotDist > 2.2) and 180 or 360
            if leaderDriven then
                minInterval = (walkType == "Run" or (leaderPoint and leaderPoint.catchUp == true)) and 620 or ((NPCSquadDynamicsBridge and NPCSquadDynamicsBridge.Config and tonumber(NPCSquadDynamicsBridge.Config.leaderFollowerSlotCooldownMs)) or 1050)
            end
            if nowMs > 0 and lastMs > 0 and (nowMs - lastMs) < minInterval and movedTarget ~= true then
                local hasMoveTask = false
                if NPCEntity and NPCEntity.HasMoveTask then
                    local okMove, retMove = pcall(function() return NPCEntity.HasMoveTask(bandit) end)
                    hasMoveTask = okMove and retMove == true
                end
                if hasMoveTask then
                    return "Follow"
                end
                -- No active move task is present. Do not replace required
                -- follow locomotion with a short Time/Idle task: that can leave
                -- the character facing the player while the old run animation is
                -- still active. Fall through and create a fresh Move task.
                if NPCEntity and NPCEntity.SetMoving then pcall(function() NPCEntity.SetMoving(bandit, false) end) end
            end
            brain.ai[pathKey] = nowMs
            brain.ai[xKey] = dx
            brain.ai[yKey] = dy
        end
        if NPCEntity and NPCEntity.ForceStationary then NPCEntity.ForceStationary(bandit, false) end
        local task = NPCUtils.GetMoveTask(endurance, dx, dy, dz or master:getZ(), walkType, slotDist, false)
        if strictFollow then
            task.arriveDist = math.max(tonumber(task.arriveDist) or 0, minDist, 0.68)
            task.strictFollowSlot = true
            task.bodyguardFollow = true
            task.pathThrottleMs = task.pathThrottleMs or ((walkType == "Run") and 180 or 360)
            task.sameTargetPathThrottleMs = task.sameTargetPathThrottleMs or ((walkType == "Run") and 520 or 900)
        end
        if leaderDriven then
            task.squadSupport = true
            task.leaderDrivenFollow = true
            task.leaderId = leaderPoint and leaderPoint.leaderId or nil
            task.pathThrottleMs = (walkType == "Run") and 950 or 1350
            task.sameTargetPathThrottleMs = (walkType == "Run") and 3200 or 5200
            task.arriveDist = math.max(tonumber(task.arriveDist) or 0, minDist)
            task.noRecoveryReplan = true
        end
        table.insert(tasks, task)
        return "Follow"
    end

    if order and (order.name == "Hold" or order.name == "Guard") and NPCEntity and NPCEntity.ForceStationary then
        NPCEntity.ForceStationary(bandit, true)
    end

    return nil
end

NPCProgramCompanionBridge.TryIdle = function(bandit, tasks)
    -- nothing to do, play idle anims
    local subTasks = NPCPrograms.Idle(bandit)
    if #subTasks > 0 then
        for _, subTask in pairs(subTasks) do
            table.insert(tasks, subTask)
        end
        return "Follow"
    end

    return nil
end

NPCProgramCompanionBridge.IsStrictFollowOrder = function(brain, order)
    if not (brain and order and order.name == "Follow") then return false end
    if brain.mercenaryHired == true then return true end
    if brain.relationshipToPlayer == "hired_bodyguard" then return true end
    if brain.factionState == "hired_blue_bodyguard" then return true end
    return false
end

NPCProgramCompanionBridge.Follow = function(bandit)
    local tasks = {}
    local world = getWorld()
    local cm = world:getClimateManager()
    local cell = getCell()
    -- local weapons = NPC weapon lookup(bandit)
 
    local brain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(bandit) or nil
    local order = brain and ((NPCOrderContract and NPCOrderContract.Get and NPCOrderContract.Get(brain)) or brain.order) or nil
    local orderName = order and order.name or nil
    local playerCommandOrder = NPCProgramCompanionBridge.IsPlayerCommandOrder(brain, order)
    local strictFollowOrder = NPCProgramCompanionBridge.IsStrictFollowOrder(brain, order)

    -- If at guardpost, switch to the CompanionGuard program unless a direct player
    -- order needs the mobile director logic below. Stage 431: strict Follow must
    -- never be converted into a guard-post assignment, otherwise hired NPCs look
    -- like they ignored the player's command.
    local atGuardpost = NPCPost.At(bandit, "guard")
    if atGuardpost and not strictFollowOrder and orderName ~= "Patrol" and orderName ~= "Loot" and orderName ~= "Return" and orderName ~= "RearmHere" and orderName ~= "LootBodies" then
        NPCEntity.SetProgram(bandit, "CompanionGuard", {})
        return {status=true, next="Prepare", tasks=tasks}
    end
    
    -- Companion logic depends on one of the players who is the master od the companion
    -- if there is no master, there is nothing to do.
    local master = NPCBehaviorBridge and NPCBehaviorBridge.GetMasterPlayer and NPCBehaviorBridge.GetMasterPlayer(bandit) or nil
    if not master then
        local task = {action="Time", anim="Shrug", time=200}
        table.insert(tasks, task)
        return {status=true, next="Follow", tasks=tasks}
    end
    
    -- update walktype
    local walkType = "Walk"
    local endurance = 0.00
    local vehicle = master:getVehicle()
    local dist = NPCUtils.DistTo(bandit:getX(), bandit:getY(), master:getX(), master:getY())

    local strictOrder = strictFollowOrder
    if master:isRunning() or master:isSprinting() or vehicle or (strictOrder and dist > 2.4) or dist > 10 then
        walkType = "Run"
        endurance = -0.07
    elseif master:isSneaking() and dist < 12 then
        walkType = "SneakWalk"
        endurance = -0.01
    end

    local outOfAmmo = NPCEntity.IsOutOfAmmo(bandit)
    if master:isAiming() and not outOfAmmo and dist < 8 then
        walkType = "WalkAim"
        endurance = 0
    end

    local health = bandit:getHealth()
    if health < 0.4 then
        walkType = "Limp"
        endurance = 0
    end 

    local nextStage = NPCProgramCompanionBridge.TryMobileOrder(bandit, brain, orderName, tasks)
    if nextStage then return {status=true, next=nextStage, tasks=tasks} end
   
    -- If the player is in the vehicle, the companion should join him.
    -- If the player exits the vehicle, so should the companion.
    nextStage = NPCProgramCompanionBridge.TryVehicleSync(bandit, master, vehicle, dist, tasks)
    if nextStage then return {status=true, next=nextStage, tasks=tasks} end

    if strictOrder then
        nextStage = NPCProgramCompanionBridge.TryFollowSlot(bandit, master, brain, order, tasks, endurance, walkType)
        if nextStage then return {status=true, next=nextStage, tasks=tasks} end

        nextStage = NPCProgramCompanionBridge.TryIdle(bandit, tasks)
        if nextStage then return {status=true, next=nextStage, tasks=tasks} end

        return {status=true, next="Follow", tasks=tasks}
    end

    if playerCommandOrder then
        nextStage = NPCProgramCompanionBridge.TryIdle(bandit, tasks)
        if nextStage then return {status=true, next=nextStage, tasks=tasks} end
        return {status=true, next="Follow", tasks=tasks}
    end

    -- Companions intention is to generally stay with the player
    -- however, if the enemy is close, the companion should engage
    -- but only if player is not too far, kind of a proactive defense.
    nextStage = NPCProgramCompanionBridge.TryProtectMaster(bandit, dist, tasks, endurance)
    if nextStage then return {status=true, next=nextStage, tasks=tasks} end
    
    -- look for guns
    nextStage = NPCProgramCompanionBridge.TryLootWeapons(bandit, cell, tasks)
    if nextStage then return {status=true, next=nextStage, tasks=tasks} end

    nextStage = NPCProgramCompanionBridge.TryGuardpost(bandit, tasks, endurance, walkType, dist)
    if nextStage then return {status=true, next=nextStage, tasks=tasks} end

    -- companion fishing
    nextStage = NPCProgramCompanionBridge.TryFishing(bandit, cell, tasks, endurance)
    if nextStage then return {status=true, next=nextStage, tasks=tasks} end

    nextStage = NPCProgramCompanionBridge.TryForaging(bandit, cm, tasks)
    if nextStage then return {status=true, next=nextStage, tasks=tasks} end

    nextStage = NPCProgramCompanionBridge.TryHomeBaseTasks(bandit, cm, tasks)
    if nextStage then return {status=true, next=nextStage, tasks=tasks} end

    -- ideas: read book, 
    --[[
    ram database
        - fridge locations
        - contents of all containers in the base
            - updated on each container item add/remove
            - container existance verified periodically
        - base coordinates
            -- updated once on base creation - when items put to fridge
        - lua objects [farms, barrels]
            -- updated periodically in certain range from base
        - generator locations
            -- updated on player start / stop / connect / disconnect
        - world items
            -- updated when walking on square


    , heal crops, fix car, chop tree, saw logs, 
    
    itemless:
    move rotten to composter, sleep, use toilet, eat something, drink something]]

    nextStage = NPCProgramCompanionBridge.TryFollowSlot(bandit, master, brain, order, tasks, endurance, walkType)
    if nextStage then return {status=true, next=nextStage, tasks=tasks} end

    nextStage = NPCProgramCompanionBridge.TryIdle(bandit, tasks)
    if nextStage then return {status=true, next=nextStage, tasks=tasks} end

    return {status=true, next="Follow", tasks=tasks}
end
