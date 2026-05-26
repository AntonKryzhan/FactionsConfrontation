require "NPCBehavior/NPCBehaviorBridge"
require "NPCCore/NPCLegacyContractBridge"

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

    -- deadbodies
    for z=0, 2 do
        for y=-12, 12 do
            for x=-12, 12 do
                local square = cell:getGridSquare(bandit:getX() + x, bandit:getY() + y, z)
                if square then
                    local body = square:getDeadBody()
                    if body then

                        -- we found one body, but there my be more bodies on that square and we need to check all
                        local objects = square:getStaticMovingObjects()
                        for i=0, objects:size()-1 do
                            local object = objects:get(i)
                            if instanceof (object, "IsoDeadBody") then
                                local body = object
                                container = body:getContainer()
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

    -- containers in rooms
    local room = bandit:getSquare():getRoom()
    if room then
        local roomDef = room:getRoomDef()
        for x=roomDef:getX(), roomDef:getX2() do
            for y=roomDef:getY(), roomDef:getY2() do
                local square = cell:getGridSquare(x, y, roomDef:getZ())
                if square then
                    local objects = square:getObjects()
                    for i=0, objects:size() - 1 do
                        local object = objects:get(i)
                        local container = object:getContainer()
                        if container and not container:isEmpty() then
                            local subTasks = NPCPrograms.Container.WeaponLoot(bandit, object, container)
                            if #subTasks > 0 then
                                for _, subTask in pairs(subTasks) do
                                    table.insert(tasks, subTask)
                                end
                                return "Prepare"
                            end

                            --[[local subTasks = legacy container loot program(bandit, object, container)
                            if #subTasks > 0 then
                                for _, subTask in pairs(subTasks) do
                                    table.insert(tasks, subTask)
                                end
                                return "Prepare"
                            end]]
                        end
                    end
                end
            end
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
    -- follow the player.
    local minDist = 2
    local dx, dy, dz = nil, nil, nil
    local followDistance = order and tonumber(order.followDistance) or nil
    local formation = order and order.formation or "close"
    local strictFollow = order and order.name == "Follow" and brain and brain.mercenaryHired == true

    if strictFollow then
        minDist = 1.35
        if formation == "wide" then
            followDistance = math.min(followDistance or 4.0, 4.0)
        elseif formation == "line" or formation == "wedge" or formation == "ring" or formation == "bodyguard" then
            followDistance = math.min(followDistance or 3.0, 3.0)
        else
            followDistance = math.min(followDistance or 2.0, 2.0)
        end
    end

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
    elseif NPCFormationSlotsBridge and NPCFormationSlotsBridge.GetSlotPoint then
        dx, dy, dz = NPCFormationSlotsBridge.GetSlotPoint(master, brain, bandit, formation or "close", followDistance or 3.0)
        if not strictFollow then minDist = 1.4 end
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

    local slotDist = NPCUtils.DistTo(bandit:getX(), bandit:getY(), dx, dy)
    if strictFollow then
        local masterDist = NPCUtils.DistTo(bandit:getX(), bandit:getY(), master:getX(), master:getY())
        if masterDist > 10 then
            walkType = "Run"
            endurance = -0.07
            if brain then
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
        if NPCEntity and NPCEntity.ForceStationary then NPCEntity.ForceStationary(bandit, false) end
        table.insert(tasks, NPCUtils.GetMoveTask(endurance, dx, dy, dz or master:getZ(), walkType, slotDist, false))
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

    -- If at guardpost, switch to the CompanionGuard program unless a direct player
    -- order needs the mobile director logic below.
    local atGuardpost = NPCPost.At(bandit, "guard")
    if atGuardpost and orderName ~= "Patrol" and orderName ~= "Loot" and orderName ~= "Return" then
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

    if master:isRunning() or master:isSprinting() or vehicle or dist > 10 then
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

    if NPCProgramCompanionBridge.IsStrictFollowOrder(brain, order) then
        nextStage = NPCProgramCompanionBridge.TryFollowSlot(bandit, master, brain, order, tasks, endurance, walkType)
        if nextStage then return {status=true, next=nextStage, tasks=tasks} end

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
