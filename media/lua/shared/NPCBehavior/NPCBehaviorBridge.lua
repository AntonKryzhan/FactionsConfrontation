NPCBehaviorBridge = NPCBehaviorBridge or {}

require "NPCCore/NPCLegacyContractBridge"

local Bridge = NPCBehaviorBridge

local NPC_BEHAVIOR_LEGACY_SANDBOX = NPCLegacyContractBridge.Sandbox.main
local NPC_BEHAVIOR_LEGACY_KEYS = {
    primaryType = NPCLegacyContractBridge.Keys.PRIMARY_TYPE
}

function Bridge.GetLegacySandbox()
    if not SandboxVars then return nil end
    return SandboxVars[NPC_BEHAVIOR_LEGACY_SANDBOX]
end

function Bridge.GetSandboxBool(name, fallback)
    local vars = Bridge.GetLegacySandbox()
    if vars and vars[name] ~= nil then return vars[name] == true end
    return fallback == true
end

function Bridge.GetSandboxNumber(name, fallback)
    local vars = Bridge.GetLegacySandbox()
    local value = vars and vars[name] or nil
    value = tonumber(value)
    if value == nil then return tonumber(fallback) or 0 end
    return value
end

function Bridge.GetPrimaryWeaponType(bandit)
    if not bandit or not bandit.getVariableString then return nil end
    return bandit:getVariableString(NPC_BEHAVIOR_LEGACY_KEYS.primaryType)
end

local function copyDefaults(defaults, overrides)
    local out = {}
    for key, value in pairs(defaults) do
        out[key] = value
    end
    if overrides then
        for key, value in pairs(overrides) do
            out[key] = value
        end
    end
    return out
end

local function safeNumber(value, fallback)
    local number = tonumber(value)
    if number == nil then return fallback end
    return number
end

local function safeCall(fn, fallback)
    if type(fn) ~= "function" then return fallback end
    local ok, result = pcall(fn)
    if not ok then return fallback end
    return result
end

local DEFAULT_CAPABILITIES = {
    melee = true,
    shoot = true,
    smashWindow = true,
    openDoor = true,
    breakDoor = true,
    breakObjects = true,
    unbarricade = true,
    disableGenerators = false,
    sabotageCars = false
}

function Bridge.Capabilities(overrides)
    return copyDefaults(DEFAULT_CAPABILITIES, overrides)
end

function Bridge.Result(nextStage, tasks, status)
    return {status = status ~= false, next = nextStage, tasks = tasks or {}}
end

function Bridge.GetDayLightStrength()
    local world = getWorld and getWorld() or nil
    if not world or not world.getClimateManager then return 1 end

    local climate = world:getClimateManager()
    if not climate or not climate.getDayLightStrength then return 1 end

    return safeNumber(climate:getDayLightStrength(), 1)
end

function Bridge.GetCurrentHour()
    local gameTime = getGameTime and getGameTime() or nil
    if not gameTime or not gameTime.getHour then return 12 end
    return safeNumber(gameTime:getHour(), 12)
end

function Bridge.GetWeapons(bandit)
    if not bandit or not NPCEntity or not NPCEntity.GetWeapons then return {primary = {}, secondary = {}} end
    return NPCEntity.GetWeapons(bandit) or {primary = {}, secondary = {}}
end

function Bridge.GetBestWeapon(bandit)
    if not bandit or not NPCEntity or not NPCEntity.GetBestWeapon then return nil end
    return NPCEntity.GetBestWeapon(bandit)
end

function Bridge.SetStationaryAndWeapons(bandit, stationary)
    if not bandit or not NPCEntity then return end
    if NPCEntity.ForceStationary then NPCEntity.ForceStationary(bandit, stationary == true) end
    if NPCEntity.SetWeapons and NPCEntity.GetWeapons then NPCEntity.SetWeapons(bandit, NPCEntity.GetWeapons(bandit)) end
end

function Bridge.ShouldCarryTorch(bandit, daylight)
    if not Bridge.GetSandboxBool("General_CarryTorches", false) then return false end
    if safeNumber(daylight, 1) >= 0.3 then return false end

    if not bandit or not bandit.getVariableString then return true end
    local hands = Bridge.GetPrimaryWeaponType(bandit)
    return hands == nil or hands == "" or hands == "barehand" or hands == "onehanded" or hands == "handgun"
end

function Bridge.PrepareArmed(bandit, options)
    local tasks = {}
    options = options or {}

    Bridge.SetStationaryAndWeapons(bandit, options.stationary == true)

    local weapons = Bridge.GetWeapons(bandit)
    local primary = Bridge.GetBestWeapon(bandit)
    local secondary
    if Bridge.ShouldCarryTorch(bandit, Bridge.GetDayLightStrength()) then
        secondary = "Base.HandTorch"
    end

    if weapons.primary and weapons.primary.name and weapons.secondary and weapons.secondary.name then
        table.insert(tasks, {action = "Unequip", time = 100, itemPrimary = weapons.secondary.name})
    end

    table.insert(tasks, {action = "Equip", itemPrimary = primary, itemSecondary = secondary})

    if options.returnEmptyTasks then
        tasks = {}
    end

    return Bridge.Result(options.next or "Operate", tasks)
end

function Bridge.GetPrimaryHands(bandit)
    return Bridge.GetPrimaryWeaponType(bandit)
end

function Bridge.GetHealth(bandit)
    if not bandit or not bandit.getHealth then return 1 end
    return safeNumber(bandit:getHealth(), 1)
end

function Bridge.WalkProfile(bandit, options)
    options = options or {}

    local daylight = Bridge.GetDayLightStrength()
    local walkType = options.defaultWalkType or "Run"
    local endurance = safeNumber(options.defaultEndurance, 0)
    local secondary

    if daylight < 0.3 then
        if Bridge.ShouldCarryTorch(bandit, daylight) then
            secondary = "Base.HandTorch"
        end

        if Bridge.GetSandboxBool("General_SneakAtNight", false) then
            if NPCEntity and NPCEntity.IsDNA and NPCEntity.IsDNA(bandit, "sneak") then
                walkType = options.nightSneakWalkType or "SneakWalk"
                endurance = safeNumber(options.nightSneakEndurance, 0)
            end
        end
    end

    if Bridge.GetHealth(bandit) < 0.8 then
        walkType = options.limpWalkType or "Limp"
        endurance = safeNumber(options.limpEndurance, 0)
    end

    return {walkType = walkType, endurance = endurance, secondary = secondary, daylight = daylight}
end

function Bridge.InventoryItemCount(bandit, predicate)
    if not bandit or not bandit.getInventory then return 0 end
    local inventory = bandit:getInventory()
    if not inventory or not inventory.getAllEvalRecurse then return 0 end
    if not ArrayList or not ArrayList.new then return 0 end

    local items = ArrayList.new()
    inventory:getAllEvalRecurse(predicate or function() return true end, items)
    if items and items.size then return items:size() end
    return 0
end

function Bridge.GetClosestPlayerBase(bandit)
    if not NPCBaseClient or not NPCBaseClient.GetBaseClosest then return nil, nil end
    return NPCBaseClient.GetBaseClosest(bandit)
end

function Bridge.GetClosestBaseContainer(bandit, baseId)
    if not baseId or not NPCBaseClient or not NPCBaseClient.GetContainerClosest then return nil, nil end
    return NPCBaseClient.GetContainerClosest(bandit, baseId)
end

function Bridge.FirstContainerItem(containerData)
    if not containerData or type(containerData.items) ~= "table" then return nil, nil end

    for itemType, count in pairs(containerData.items) do
        if itemType then
            return itemType, count
        end
    end
    return nil, nil
end

function Bridge.GetGridSquare(x, y, z)
    local cell = getCell and getCell() or nil
    if not cell or not cell.getGridSquare then return nil end
    if x == nil or y == nil then return nil end
    return cell:getGridSquare(x, y, z or 0)
end

function Bridge.FindAdjacentSquare(square, bandit)
    if not square or not AdjacentFreeTileFinder or not AdjacentFreeTileFinder.Find then return nil end
    return AdjacentFreeTileFinder.Find(square, bandit)
end

function Bridge.DistanceToSquareCenter(bandit, square)
    if not bandit or not square or not square.getX or not NPCUtils or not NPCUtils.DistTo then return 9999 end
    return NPCUtils.DistTo(bandit:getX(), bandit:getY(), square:getX() + 0.5, square:getY() + 0.5)
end

function Bridge.MoveTaskToSquare(bandit, square, walkType, endurance, closeSlow)
    if not square or not square.getX or not NPCUtils or not NPCUtils.GetMoveTask then return nil end
    local dist = Bridge.DistanceToSquareCenter(bandit, square)
    return NPCUtils.GetMoveTask(endurance or 0, square:getX(), square:getY(), square:getZ(), walkType or "Walk", dist, closeSlow == true)
end

function Bridge.IsAtSameZ(bandit, square)
    if not bandit or not square or not bandit.getZ or not square.getZ then return false end
    return bandit:getZ() == square:getZ()
end

function Bridge.MakeContainerLootTask(containerData, square, itemType, count)
    if not containerData or not square or not itemType then return nil end

    local action = "TakeFromContainer"
    local anim = "Loot"
    if containerData.type == "floor" then
        action = "PickUp"
        anim = "LootLow"
    end

    return {
        action = action,
        anim = anim,
        itemType = itemType,
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
        cnt = count
    }
end

function Bridge.MakeMoveOrLootTask(bandit, containerData, itemType, count, walkType, endurance)
    if not containerData or not itemType then return nil end

    local square = Bridge.GetGridSquare(containerData.x, containerData.y, containerData.z)
    if not square then return nil end

    local adjacent = Bridge.FindAdjacentSquare(square, bandit)
    if not adjacent then return nil end

    local dist = Bridge.DistanceToSquareCenter(bandit, adjacent)
    if dist > 0.90 or not Bridge.IsAtSameZ(bandit, adjacent) then
        return Bridge.MoveTaskToSquare(bandit, adjacent, walkType, endurance, false)
    end

    return Bridge.MakeContainerLootTask(containerData, square, itemType, count)
end

function Bridge.GetPlayers()
    if NPCPlayerClient and NPCPlayerClient.GetPlayers then return NPCPlayerClient.GetPlayers() end
    return nil
end

function Bridge.ForEachVisiblePlayer(callback)
    if type(callback) ~= "function" then return end
    local playerList = Bridge.GetPlayers()
    if not playerList or not playerList.size or not playerList.get then return end

    for i = 0, playerList:size() - 1 do
        local player = playerList:get(i)
        if player and (not NPCPlayerClient or not NPCPlayerClient.IsGhost or not NPCPlayerClient.IsGhost(player)) then
            callback(player)
        end
    end
end

function Bridge.SayToVisiblePlayers(bandit, token)
    if not bandit or not token or not NPCEntity or not NPCEntity.Say then return end
    Bridge.ForEachVisiblePlayer(function()
        NPCEntity.Say(bandit, token)
    end)
end

function Bridge.EscapeTaskAwayFromClosestPlayer(bandit, options)
    options = options or {}
    if not bandit or not NPCUtils or not NPCUtils.GetClosestPlayerLocation or not NPCUtils.GetMoveTask then return nil end

    local closest = NPCUtils.GetClosestPlayerLocation(bandit)
    if not closest or not closest.x or not closest.y then return nil end

    local deltaX = safeNumber(options.deltaX, 100)
    local deltaY = safeNumber(options.deltaY, 100)
    local hour = Bridge.GetCurrentHour()

    if hour < 6 then
        deltaX = -deltaX
    elseif hour < 12 then
        deltaY = -deltaY
    elseif hour < 18 then
        deltaX = -deltaX
        deltaY = -deltaY
    end

    local profile = Bridge.WalkProfile(bandit, {defaultWalkType = options.walkType or "Run", defaultEndurance = options.endurance or -0.03})
    return NPCUtils.GetMoveTask(profile.endurance, closest.x + deltaX, closest.y + deltaY, closest.z or 0, profile.walkType, options.closeDistance or 12, false)
end

function Bridge.SetSleeping(bandit, sleeping)
    if NPCEntity and NPCEntity.SetSleeping then NPCEntity.SetSleeping(bandit, sleeping == true) end
end

function Bridge.ClearTasks(bandit)
    if NPCEntity and NPCEntity.ClearTasks then NPCEntity.ClearTasks(bandit) end
end

function Bridge.SetProgram(bandit, name, args)
    if NPCEntity and NPCEntity.SetProgram then NPCEntity.SetProgram(bandit, name, args or {}) end
end

function Bridge.SyncBrainState(bandit, overrides)
    if not bandit or not NPCBrainData or not NPCBrainData.Get or not NPCEntity or not NPCEntity.ForceSyncPart then return end

    local brain = NPCBrainData.Get(bandit)
    if not brain then return end

    local syncData = {
        id = brain.id,
        sleeping = brain.sleeping,
        program = brain.program
    }
    if overrides then
        for key, value in pairs(overrides) do
            syncData[key] = value
        end
    end

    NPCEntity.ForceSyncPart(bandit, syncData)
end

function Bridge.SwitchProgram(bandit, name, args, sleeping)
    if sleeping ~= nil then Bridge.SetSleeping(bandit, sleeping == true) end
    Bridge.ClearTasks(bandit)
    Bridge.SetProgram(bandit, name, args or {})
    Bridge.SyncBrainState(bandit, {sleeping = sleeping == nil and nil or sleeping == true})
end

function Bridge.TryMattressAtNPC(bandit)
    if not bandit or not bandit.getX or not NPCBasePlacementsBridge or not NPCBasePlacementsBridge.Matress then return end
    safeCall(function()
        NPCBasePlacementsBridge.Matress(bandit:getX(), bandit:getY(), bandit:getZ())
    end, nil)
end

Bridge[NPCLegacyContractBridge.Member("tryMattressAt")] = Bridge.TryMattressAtNPC

function Bridge.DefenderSchedule()
    local hour = Bridge.GetCurrentHour()
    if (hour >= 0 and hour < 7) or (hour >= 13 and hour < 14) then
        return {sleeping = true, spotDist = 10}
    end
    return {sleeping = false, spotDist = 30}
end

local GUARD_IDLE_ANIMS = {
    "Cough",
    "ChewNails",
    "Smoke",
    "PullAtCollar",
    "Sneeze",
    "WipeBrow",
    "WipeHead"
}

function Bridge.GuardIdleTask()
    local roll = ZombRand and ZombRand(30) or 29
    local anim = GUARD_IDLE_ANIMS[roll + 1] or "ShiftWeight"
    return {action = "Time", anim = anim, time = 200}
end

function Bridge.IsOutside(bandit)
    if not bandit or not bandit.isOutside then return false end
    return bandit:isOutside() == true
end

function Bridge.GetSquare(character)
    if not character or not character.getSquare then return nil end
    return character:getSquare()
end

function Bridge.GetBuilding(square)
    if not square or not square.getBuilding then return nil end
    return square:getBuilding()
end

function Bridge.SameBuilding(squareA, squareB)
    local buildingA = Bridge.GetBuilding(squareA)
    local buildingB = Bridge.GetBuilding(squareB)
    if not buildingA or not buildingB then return false end
    if buildingA.getID and buildingB.getID then
        return buildingA:getID() == buildingB:getID()
    end
    return buildingA == buildingB
end

function Bridge.FindBuildingIntruder(bandit, baseSpotDist)
    local banditSquare = Bridge.GetSquare(bandit)
    if not banditSquare then return nil, baseSpotDist end

    local foundPlayer
    local foundSpotDist = baseSpotDist or 30

    Bridge.ForEachVisiblePlayer(function(player)
        if foundPlayer then return end

        local playerSquare = Bridge.GetSquare(player)
        if not playerSquare or not playerSquare.isOutside or playerSquare:isOutside() then return end
        if not Bridge.SameBuilding(playerSquare, banditSquare) then return end

        local spotDist = baseSpotDist or 30
        if player.isSneaking and player:isSneaking() then spotDist = spotDist - 3 end

        if NPCUtils and NPCUtils.DistTo then
            local dist = NPCUtils.DistTo(player:getX(), player:getY(), bandit:getX(), bandit:getY())
            if dist <= spotDist then
                foundPlayer = player
                foundSpotDist = spotDist
            end
        end
    end)

    return foundPlayer, foundSpotDist
end

function Bridge.ReactToDefenderIntruder(bandit)
    if NPCEntity and NPCEntity.IsHostile and NPCEntity.IsHostile(bandit) and NPCEntity.Say then
        NPCEntity.Say(bandit, "DEFENDER_SPOTTED")
    end
    Bridge.SwitchProgram(bandit, "Raider", {}, false)
end

function Bridge.IsOutOfAmmo(bandit)
    if not bandit or not NPCEntity or not NPCEntity.IsOutOfAmmo then return false end
    return NPCEntity.IsOutOfAmmo(bandit) == true
end

function Bridge.IsDNA(bandit, marker)
    if not bandit or not marker or not NPCEntity or not NPCEntity.IsDNA then return false end
    return NPCEntity.IsDNA(bandit, marker) == true
end

function Bridge.PrepareEquipOnly(bandit, options)
    local tasks = {}
    options = options or {}

    Bridge.SetStationaryAndWeapons(bandit, options.stationary == true)

    local primary = Bridge.GetBestWeapon(bandit)
    local secondary
    if Bridge.ShouldCarryTorch(bandit, Bridge.GetDayLightStrength()) then
        secondary = "Base.HandTorch"
    end

    table.insert(tasks, {action = "Equip", itemPrimary = primary, itemSecondary = secondary})
    return Bridge.Result(options.next or "Operate", tasks)
end

function Bridge.GetBrain(bandit)
    if not bandit or not NPCBrainData or not NPCBrainData.Get then return nil end
    return NPCBrainData.Get(bandit)
end

function Bridge.GetOrder(brain)
    if not brain then return nil end
    if NPCOrderContract and NPCOrderContract.Get then
        local order = NPCOrderContract.Get(brain)
        if order then return order end
    end
    return brain.order
end

function Bridge.IsHoldOrGuardOrder(order)
    if not order or not order.name then return false end
    if order.name ~= "Hold" and order.name ~= "Guard" then return false end
    return order.anchor and order.anchor.x and order.anchor.y
end

function Bridge.ResolveAnchorSlot(order, brain, bandit)
    if not Bridge.IsHoldOrGuardOrder(order) then return nil end

    local anchor = order.anchor
    local tx = safeNumber(anchor.x, bandit and bandit.getX and bandit:getX() or 0)
    local ty = safeNumber(anchor.y, bandit and bandit.getY and bandit:getY() or 0)
    local tz = safeNumber(anchor.z, bandit and bandit.getZ and bandit:getZ() or 0)

    if NPCFormationSlotsBridge and NPCFormationSlotsBridge.GetAnchorSlotPoint then
        local sx, sy, sz = NPCFormationSlotsBridge.GetAnchorSlotPoint(anchor, brain, bandit, order.formation or "close", order.followDistance or 2.0)
        tx = sx or tx
        ty = sy or ty
        tz = sz or tz
    end

    return {x = tx, y = ty, z = tz}
end

function Bridge.GuardAnchorMoveTask(bandit, brain, order)
    if not bandit or not NPCUtils or not NPCUtils.DistTo or not NPCUtils.GetMoveTask then return nil, false end

    local point = Bridge.ResolveAnchorSlot(order, brain, bandit)
    if not point then return nil, false end

    local dist = NPCUtils.DistTo(bandit:getX(), bandit:getY(), point.x, point.y)
    if dist > 1.4 then
        if NPCEntity and NPCEntity.ForceStationary then NPCEntity.ForceStationary(bandit, false) end
        return NPCUtils.GetMoveTask(-0.01, point.x, point.y, point.z, dist > 6 and "Run" or "Walk", dist, false), true
    end

    if NPCEntity and NPCEntity.ForceStationary then NPCEntity.ForceStationary(bandit, true) end
    return nil, true
end

function Bridge.HasGuardPost(bandit)
    if not bandit or not NPCPost or not NPCPost.At then return false end
    return NPCPost.At(bandit, "guard") == true
end

function Bridge.GetClosestZombieLocation(bandit)
    if not bandit or not NPCUtils or not NPCUtils.GetClosestZombieLocation then return {dist = 9999} end
    return NPCUtils.GetClosestZombieLocation(bandit) or {dist = 9999}
end

function Bridge.GetClosestEnemyNPCLocation(bandit)
    if not bandit or not NPCUtils then return {dist = 9999} end
    if NPCUtils.GetClosestEnemyNPCLocation then
        return NPCUtils.GetClosestEnemyNPCLocation(bandit) or {dist = 9999}
    end
    local legacyClosest = NPCUtils["GetClosestEnemy" .. NPCLegacyContractBridge.Token .. "Location"]
    if legacyClosest then
        return legacyClosest(bandit) or {dist = 9999}
    end
    return {dist = 9999}
end

Bridge[NPCLegacyContractBridge.Member("getClosestEnemyLocation")] = Bridge.GetClosestEnemyNPCLocation

function Bridge.GetClosestEnemyPlayerLocation(bandit, includeInvisible)
    if not bandit or not NPCUtils then return {dist = 9999} end
    if NPCUtils.GetClosestEnemyPlayerLocation then
        return NPCUtils.GetClosestEnemyPlayerLocation(bandit, includeInvisible == true) or {dist = 9999}
    end
    if NPCUtils.GetClosestPlayerLocation then
        return NPCUtils.GetClosestPlayerLocation(bandit, includeInvisible == true) or {dist = 9999}
    end
    return {dist = 9999}
end

function Bridge.GetEnemyCharacter(target)
    if not target or not target.id then return nil end
    if target.kind == "bandit" then
        if NPCZombieCacheBridge and NPCZombieCacheBridge.Cache then return NPCZombieCacheBridge.Cache[target.id] end
        return nil
    end
    if target.kind == "player" and NPCPlayerClient and NPCPlayerClient.GetPlayerById then
        return NPCPlayerClient.GetPlayerById(target.id)
    end
    return nil
end


function Bridge.AreOnSameBuildingLayer(a, b)
    if not (a and b and a.getSquare and b.getSquare) then return true end
    local squareA = Bridge.GetSquare(a)
    local squareB = Bridge.GetSquare(b)
    if not (squareA and squareB) then return true end

    local buildingA = Bridge.GetBuilding(squareA)
    local buildingB = Bridge.GetBuilding(squareB)
    if buildingA or buildingB then
        if not (buildingA and buildingB and Bridge.SameBuilding(squareA, squareB)) then return false end
    end
    return true
end

function Bridge.HasClearShot(shooter, target)
    if not (shooter and target) then return false end
    if shooter.getZ and target.getZ and math.floor(tonumber(shooter:getZ()) or 0) ~= math.floor(tonumber(target:getZ()) or 0) then
        return false
    end
    if NPCUtils and NPCUtils.LineClear then
        local ok, clear = pcall(function() return NPCUtils.LineClear(shooter, target) end)
        if ok and clear == false then return false end
    end
    return true
end

function Bridge.IsManualFireControlOrder(order)
    local name = order and order.name or order
    return name == "Hold" or name == "Guard" or name == "LootHouse" or name == "TakeCover" or name == "WatchSector" or name == "BackToBack"
end

function Bridge.SetCompanionStationary(bandit, stationary)
    if NPCEntity and NPCEntity.ForceStationary then NPCEntity.ForceStationary(bandit, stationary == true) end
end

function Bridge.SelectCombatTarget(bandit, options)
    options = options or {}

    local zombie = Bridge.GetClosestZombieLocation(bandit)
    zombie.kind = "zombie"
    local enemyNPC = Bridge.GetClosestEnemyNPCLocation(bandit)
    enemyNPC.kind = "bandit"
    local enemyPlayer = Bridge.GetClosestEnemyPlayerLocation(bandit, options.includeInvisible == true)
    enemyPlayer.kind = "player"

    local target = zombie
    if safeNumber(enemyNPC.dist, 9999) < safeNumber(target.dist, 9999) then
        target = enemyNPC
    end

    local playerHandicap = safeNumber(options.playerHandicap, 6)
    if enemyPlayer.id and safeNumber(enemyPlayer.dist, 9999) + playerHandicap < safeNumber(enemyNPC.dist, 9999)
            and safeNumber(enemyPlayer.dist, 9999) < safeNumber(zombie.dist, 9999) then
        target = enemyPlayer
    end

    target.enemy = Bridge.GetEnemyCharacter(target)
    return target
end

function Bridge.IsArmedWithFirearm(character)
    if not character or not character.getPrimaryHandItem or not WeaponType then return false end
    local weapon = character:getPrimaryHandItem()
    if not weapon or not weapon.IsWeapon or not weapon:IsWeapon() then return false end
    if not WeaponType.getWeaponType then return false end
    local weaponType = WeaponType.getWeaponType(weapon)
    return weaponType == WeaponType.firearm or weaponType == WeaponType.handgun
end

function Bridge.ShouldCloseSlow(enemy)
    if not enemy then return true end
    return not Bridge.IsArmedWithFirearm(enemy)
end

function Bridge.GetCharacterId(bandit)
    if not bandit or not NPCUtils or not NPCUtils.GetCharacterID then return 0 end
    return safeNumber(NPCUtils.GetCharacterID(bandit), 0)
end

function Bridge.DeterministicOffset(bandit)
    local id = math.abs(Bridge.GetCharacterId(bandit))
    return ((id % 10) - 5) / 10, ((id % 11) - 5) / 10
end

function Bridge.SpeakTargetContext(bandit, target)
    if not bandit or not target or not target.x or not target.y or not target.z then return end
    if not NPCEntity or not NPCEntity.Say then return end

    local targetSquare = Bridge.GetGridSquare(target.x, target.y, target.z)
    local banditSquare = Bridge.GetSquare(bandit)
    if not targetSquare or not banditSquare then return end

    local targetBuilding = Bridge.GetBuilding(targetSquare)
    local banditBuilding = Bridge.GetBuilding(banditSquare)

    if targetBuilding and not banditBuilding then
        NPCEntity.Say(bandit, "INSIDE")
        return
    end

    if not targetBuilding and banditBuilding then
        NPCEntity.Say(bandit, "OUTSIDE")
        return
    end

    if targetBuilding and banditBuilding then
        if bandit.getZ and bandit:getZ() < safeNumber(target.z, 0) then
            NPCEntity.Say(bandit, "UPSTAIRS")
            return
        end

        local room = targetSquare.getRoom and targetSquare:getRoom() or nil
        local roomName = room and room.getName and room:getName() or nil
        if roomName == "kitchen" then
            NPCEntity.Say(bandit, "ROOM_KITCHEN")
        elseif roomName == "bathroom" then
            NPCEntity.Say(bandit, "ROOM_BATHROOM")
        end
    end
end

function Bridge.MakeApproachTargetTask(bandit, target, walkType, endurance, closeSlow)
    if not target or not target.x or not target.y or target.z == nil then return nil end
    if not NPCUtils or not NPCUtils.GetMoveTask then return nil end

    local dx, dy = Bridge.DeterministicOffset(bandit)
    return NPCUtils.GetMoveTask(endurance or 0, target.x + dx, target.y + dy, target.z, walkType or "Run", safeNumber(target.dist, 9999), closeSlow ~= false)
end

function Bridge.IdleTasks(bandit)
    if not NPCPrograms or not NPCPrograms.Idle then return {} end
    return NPCPrograms.Idle(bandit) or {}
end

function Bridge.FaceThreatOrIdleTasks(bandit, distance)
    local tasks = {}
    local target = Bridge.SelectCombatTarget(bandit, {playerHandicap = 9999})
    if target and target.x and target.y and safeNumber(target.dist, 9999) < safeNumber(distance, 12) then
        table.insert(tasks, {action = "FaceLocation", x = target.x, y = target.y, time = 100})
        return tasks
    end

    local idleTasks = Bridge.IdleTasks(bandit)
    for _, task in pairs(idleTasks) do
        table.insert(tasks, task)
    end
    return tasks
end


function Bridge.PushTasks(tasks, source)
    if not tasks or not source then return tasks or {} end
    for _, task in pairs(source) do
        table.insert(tasks, task)
    end
    return tasks
end

function Bridge.MakeTimeTask(anim, time)
    return {action = "Time", anim = anim or "ShiftWeight", time = time or 100}
end

function Bridge.IsHostileSurrenderAllowed()
    return Bridge.GetSandboxBool("General_Surrender", false)
end

function Bridge.IsHostileRunAwayAllowed()
    return Bridge.GetSandboxBool("General_RunAway", false)
end

function Bridge.HostileHealthEscapeLimit(bandit)
    if Bridge.IsDNA(bandit, "coward") then return 1.7 end
    return 0.7
end

function Bridge.ShouldHostileEscape(bandit)
    if not Bridge.IsHostileRunAwayAllowed() then return false end
    return Bridge.GetHealth(bandit) < Bridge.HostileHealthEscapeLimit(bandit)
end

function Bridge.DropWeaponItemAtFeet(bandit, itemType)
    if not bandit or not itemType then return false end
    local square = Bridge.GetSquare(bandit)
    if not square or not square.AddWorldInventoryItem then return false end
    if not NPCCompatibilityBridge or not NPCCompatibilityBridge.InstanceItem then return false end

    local item = NPCCompatibilityBridge.InstanceItem(itemType)
    if not item then return false end
    square:AddWorldInventoryItem(item, ZombRandFloat and ZombRandFloat(0.2, 0.8) or 0.5, ZombRandFloat and ZombRandFloat(0.2, 0.8) or 0.5, 0)
    return true
end

function Bridge.DropHostileWeaponsForSurrender(bandit)
    if not bandit then return false end
    if NPCCompatibilityBridge and NPCCompatibilityBridge.SafeSetPrimaryHandItem then
        NPCCompatibilityBridge.SafeSetPrimaryHandItem(bandit, nil)
    end

    local weapons = Bridge.GetWeapons(bandit)
    local changed = false

    if weapons.melee then
        if Bridge.DropWeaponItemAtFeet(bandit, weapons.melee) then
            weapons.melee = nil
            changed = true
        end
    end

    if weapons.primary and weapons.primary.name then
        if Bridge.DropWeaponItemAtFeet(bandit, weapons.primary.name) then
            weapons.primary = nil
            changed = true
        end
    end

    if weapons.secondary and weapons.secondary.name then
        if Bridge.DropWeaponItemAtFeet(bandit, weapons.secondary.name) then
            weapons.secondary = nil
            changed = true
        end
    end

    if changed and NPCEntity and NPCEntity.SetWeapons then
        NPCEntity.SetWeapons(bandit, weapons)
    end
    return changed
end

function Bridge.HostileSurrenderResult(bandit, tasks)
    if not Bridge.IsHostileSurrenderAllowed() then return nil end
    if Bridge.GetHealth(bandit) >= 0.16 then return nil end

    Bridge.DropHostileWeaponsForSurrender(bandit)
    return Bridge.Result("Surrender", tasks or {})
end

function Bridge.HostileWalkProfile(bandit)
    local profile = Bridge.WalkProfile(bandit, {
        defaultWalkType = "Run",
        defaultEndurance = -0.06,
        nightSneakWalkType = "SneakWalk",
        nightSneakEndurance = 0,
        limpWalkType = "Limp",
        limpEndurance = 0
    })

    if bandit and bandit.isInARoom and bandit:isInARoom() then
        if Bridge.IsOutOfAmmo(bandit) then
            profile.walkType = "Run"
        else
            profile.walkType = "WalkAim"
        end
    end

    return profile
end

function Bridge.IsGeneratorCutoffAllowed(bandit)
    if not Bridge.GetSandboxBool("General_GeneratorCutoff", false) then return false end
    return Bridge.IsOutside(bandit)
end

function Bridge.IsVehicleSabotageAllowed()
    return Bridge.GetSandboxBool("General_SabotageVehicles", false)
end

function Bridge.FindNearbyActiveGenerator(bandit, radius)
    if not Bridge.IsGeneratorCutoffAllowed(bandit) then return nil end
    if not bandit or not bandit.getX or not bandit.getY then return nil end
    local cell = getCell and getCell() or nil
    if not cell or not cell.getGridSquare then return nil end

    radius = radius or 10
    local bx = bandit:getX()
    local by = bandit:getY()
    for z = 0, 1 do
        for y = -radius, radius do
            for x = -radius, radius do
                local square = cell:getGridSquare(bx + x, by + y, z)
                local generator = square and square.getGenerator and square:getGenerator() or nil
                if generator and generator.isActivated and generator:isActivated() then
                    return square, generator
                end
            end
        end
    end
    return nil
end

function Bridge.FindNearbySabotageVehicle(bandit, radius)
    if not Bridge.IsVehicleSabotageAllowed() then return nil end
    if not bandit or not bandit.getX or not bandit.getY then return nil end
    local cell = getCell and getCell() or nil
    if not cell or not cell.getGridSquare then return nil end

    radius = radius or 10
    local bx = bandit:getX()
    local by = bandit:getY()
    for z = 0, 1 do
        for y = -radius, radius do
            for x = -radius, radius do
                local square = cell:getGridSquare(bx + x, by + y, z)
                local vehicle = square and square.getVehicleContainer and square:getVehicleContainer() or nil
                if vehicle and vehicle.isHotwired and vehicle:isHotwired() and (not vehicle.getDriver or not vehicle:getDriver()) then
                    return square, vehicle
                end
            end
        end
    end
    return nil
end

function Bridge.MoveToWorldObjectTask(bandit, square, profile, closeDistance)
    if not square then return nil end
    if not NPCUtils or not NPCUtils.GetMoveTask then return nil end
    local x = square:getX()
    local y = square:getY()
    local z = square:getZ()
    local dist = NPCUtils.DistTo and NPCUtils.DistTo(bandit:getX(), bandit:getY(), x, y) or closeDistance or 12
    return NPCUtils.GetMoveTask(profile and profile.endurance or 0, x, y, z, profile and profile.walkType or "Run", closeDistance or dist, false)
end

function Bridge.TryHostileServiceOpportunity(bandit, profile, tasks)
    if not tasks then tasks = {} end

    local genSquare = Bridge.FindNearbyActiveGenerator(bandit, 10)
    if genSquare then
        local task = Bridge.MoveToWorldObjectTask(bandit, genSquare, profile, 12)
        if task then table.insert(tasks, task) end
        return "TurnOffGenerator"
    end

    local vehicleSquare = Bridge.FindNearbySabotageVehicle(bandit, 10)
    if vehicleSquare then
        local task = Bridge.MoveToWorldObjectTask(bandit, vehicleSquare, profile, 12)
        if task then table.insert(tasks, task) end
        return "SabotageVehicle"
    end

    return nil
end

function Bridge.WaterBridgeCandidate(bandit, target)
    if not Bridge.GetSandboxBool("General_BuildBridge", false) then return nil end
    if not (bandit and target and target.x and target.y and NPCUtils and NPCUtils.Bresenham and NPCUtils.IsWater) then return nil end
    local cell = getCell and getCell() or nil
    if not cell then return nil end

    local path = NPCUtils.Bresenham(math.floor(bandit:getX() + 0.5), math.floor(bandit:getY() + 0.5), math.floor(target.x + 0.5), math.floor(target.y + 0.5))
    local last = nil
    for _, coords in pairs(path or {}) do
        local square = cell:getGridSquare(coords.x, coords.y, 0)
        if square then
            if NPCUtils.IsWater(square) then
                return last, coords
            end
            last = coords
        end
    end
    return nil
end

function Bridge.TryWaterBridgeApproach(bandit, target, profile, tasks)
    local last = Bridge.WaterBridgeCandidate(bandit, target)
    if not last or not last.x or not last.y then return nil end
    if not (NPCUtils and NPCUtils.GetMoveTask) then return nil end

    table.insert(tasks, NPCUtils.GetMoveTask(profile and profile.endurance or 0, last.x, last.y, 0, profile and profile.walkType or "Run", target and target.dist or 12, false))
    if math.floor(bandit:getX()) == last.x and math.floor(bandit:getY()) == last.y then
        return "BuildBridge"
    end
    return "Follow"
end

function Bridge.HostileCombatMoveStage(bandit, profile, tasks)
    local target = Bridge.SelectCombatTarget(bandit, {playerHandicap = 6})
    if not (target and target.x and target.y and target.z) then
        table.insert(tasks, Bridge.MakeTimeTask("Shrug", 200))
        return "Follow"
    end

    Bridge.SpeakTargetContext(bandit, target)

    local minDist = 2
    if Bridge.IsOutOfAmmo(bandit) then minDist = 0.5 end
    if safeNumber(target.dist, 9999) <= minDist then return "Follow" end

    local bridgeStage = Bridge.TryWaterBridgeApproach(bandit, target, profile, tasks)
    if bridgeStage then return bridgeStage end

    local task = Bridge.MakeApproachTargetTask(bandit, target, profile and profile.walkType or "Run", profile and profile.endurance or 0, Bridge.ShouldCloseSlow(target.enemy))
    if task then table.insert(tasks, task) end
    return "Follow"
end

function Bridge.DisableGeneratorAtCurrentSquare(bandit, tasks)
    local square = Bridge.GetSquare(bandit)
    local generator = square and square.getGenerator and square:getGenerator() or nil
    if generator and generator.isActivated and generator:isActivated() then
        table.insert(tasks, Bridge.MakeTimeTask("LootLow", 40))
        table.insert(tasks, Bridge.MakeTimeTask("LootLow", 40))
        generator:setActivated(false)
        if square.playSound then square:playSound("WorldEventElectricityShutdown") end
    end
    return Bridge.Result("Follow", tasks)
end

local VEHICLE_SABOTAGE_PARTS = {"TireRearLeft", "Battery", "TireFrontRight", "TireRearRight", "TireFrontLeft"}

function Bridge.GetVehicleSabotagePart(vehicle)
    if not vehicle or not vehicle.getPartById then return nil end
    for _, partId in ipairs(VEHICLE_SABOTAGE_PARTS) do
        local part = vehicle:getPartById(partId)
        if part and part.getInventoryItem and part:getInventoryItem() then
            return part
        end
    end
    return nil
end

function Bridge.FindVehicleSabotageAction(bandit, radius, walkType)
    local cell = getCell and getCell() or nil
    if not (cell and bandit and bandit.getX and bandit.getY) then return nil, false end
    radius = radius or 12
    local bx = bandit:getX()
    local by = bandit:getY()
    for y = -radius, radius do
        for x = -radius, radius do
            local square = cell:getGridSquare(bx + x, by + y, 0)
            local vehicle = square and square.getVehicleContainer and square:getVehicleContainer() or nil
            if vehicle and vehicle.isHotwired and vehicle:isHotwired() and (not vehicle.getDriver or not vehicle:getDriver()) then
                local part = Bridge.GetVehicleSabotagePart(vehicle)
                if not part then
                    if vehicle.setHotwired then vehicle:setHotwired(false) end
                    return nil, false
                end

                local area = part.getArea and part:getArea() or nil
                local dist = area and vehicle.getAreaDist and vehicle:getAreaDist(area, bandit) or 9999
                local minDist = area == "Engine" and 5.4 or 3.1
                local vx = square:getX()
                local vy = square:getY()
                if dist > minDist then
                    return {action = "Move", vehiclePartArea = area, time = 50, x = vx, y = vy, z = 0, walkType = walkType or "Run"}, true
                end

                local partSquare = part.getSquare and part:getSquare() or square
                return {
                    action = "VehicleAction",
                    subaction = "Uninstall",
                    id = part.getId and part:getId() or nil,
                    area = area,
                    vx = vx,
                    vy = vy,
                    px = partSquare:getX(),
                    py = partSquare:getY(),
                    time = 250
                }, true
            end
        end
    end
    return nil, false
end

function Bridge.HostileSabotageVehicleResult(bandit, tasks, walkType)
    local task, found = Bridge.FindVehicleSabotageAction(bandit, 12, walkType or "Run")
    if task then table.insert(tasks, task) end
    if found then return Bridge.Result("SabotageVehicle", tasks) end
    return Bridge.Result("Follow", tasks)
end

function Bridge.BuildBridgeNearNPCResult(bandit, tasks)
    local cell = getCell and getCell() or nil
    if not (cell and bandit and bandit.getX and bandit.getY and NPCUtils and NPCUtils.IsWater) then
        return Bridge.Result("Follow", tasks)
    end

    for dx = -1, 1 do
        for dy = -1, 1 do
            local square = cell:getGridSquare(bandit:getX() + dx, bandit:getY() + dy, bandit:getZ())
            if square and NPCUtils.IsWater(square) then
                table.insert(tasks, {action = "Equip", itemPrimary = "Base.Hammer", itemSecondary = nil})
                table.insert(tasks, {action = "BuildFloor", anim = "HammerLow", sound = "Hammering", x = square:getX(), y = square:getY(), time = 500})
                return Bridge.Result("BuildBridge", tasks)
            end
        end
    end
    return Bridge.Result("Follow", tasks)
end

Bridge[NPCLegacyContractBridge.Member("buildBridgeNearResult")] = Bridge.BuildBridgeNearNPCResult

function Bridge.GetMasterPlayer(bandit)
    if not bandit then return nil end
    if NPCPlayerClient and NPCPlayerClient.GetMasterPlayer then
        local ok, player = pcall(function() return NPCPlayerClient.GetMasterPlayer(bandit) end)
        if ok and player then return player end
    end

    local masterId = nil
    if NPCEntity and NPCEntity.GetMaster then
        local ok, value = pcall(function() return NPCEntity.GetMaster(bandit) end)
        if ok then masterId = tonumber(value) end
    end
    if masterId and masterId >= 0 and getPlayerByOnlineID then
        local ok, player = pcall(getPlayerByOnlineID, masterId)
        if ok and player then return player end
    end
    if getPlayer then return getPlayer() end
    return nil
end

function Bridge.DistanceBetweenCharacters(a, b)
    if not (a and b and NPCUtils and NPCUtils.DistTo) then return 9999 end
    return NPCUtils.DistTo(a:getX(), a:getY(), b:getX(), b:getY())
end

function Bridge.CompanionMovementProfile(bandit, master)
    local walkType = "Walk"
    local endurance = 0.00
    local vehicle = master and master.getVehicle and master:getVehicle() or nil
    local dist = Bridge.DistanceBetweenCharacters(bandit, master)

    if master and ((master.isRunning and master:isRunning()) or (master.isSprinting and master:isSprinting()) or vehicle or dist > 10) then
        walkType = "Run"
        endurance = -0.07
    elseif master and master.isSneaking and master:isSneaking() and dist < 12 then
        walkType = "SneakWalk"
        endurance = -0.01
    end

    if master and master.isAiming and master:isAiming() and not Bridge.IsOutOfAmmo(bandit) and dist < 8 then
        walkType = "WalkAim"
        endurance = 0
    end

    if Bridge.GetHealth(bandit) < 0.4 then
        walkType = "Limp"
        endurance = 0
    end

    return {walkType = walkType, endurance = endurance, vehicle = vehicle, dist = dist}
end

function Bridge.IsHiredMercenaryBrain(brain)
    if not brain then return false end
    if brain.mercenaryHired == true then return true end
    if brain.relationshipToPlayer == "hired_bodyguard" then return true end
    if brain.factionState == "hired_blue_bodyguard" then return true end
    return false
end

function Bridge.ClearThreatMemory(brain)
    if not brain then return end
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

-- Stage 25 companion order and formation helpers.
-- These helpers intentionally keep the old task/action contracts while moving
-- the decision code out of ZombiePrograms.Companion.

local function companionSquareBuilding(square)
    if not square then return nil end
    local ok, building = pcall(function() return square:getBuilding() end)
    if ok then return building end
    return nil
end

local function companionSquareRoom(square)
    if not square then return nil end
    local ok, room = pcall(function() return square:getRoom() end)
    if ok then return room end
    return nil
end

local function companionOrderCacheKey(prefix, order, anchor)
    anchor = anchor or (order and order.anchor) or {}
    local name = order and order.name or ""
    local ax = tonumber(anchor.x) or 0
    local ay = tonumber(anchor.y) or 0
    local az = tonumber(anchor.z) or 0
    local x = math.floor(ax * 10 + 0.5)
    local y = math.floor(ay * 10 + 0.5)
    local z = math.floor(az * 10 + 0.5)
    if tostring(prefix) == "housepos" then
        x = math.floor(ax / 5 + 0.5)
        y = math.floor(ay / 5 + 0.5)
        z = math.floor(az + 0.5)
    end
    return tostring(prefix) .. ":" .. tostring(name) .. ":" .. tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)
end

local function companionCacheGet(cacheName, key)
    Bridge[cacheName] = Bridge[cacheName] or {keys = {}}
    return Bridge[cacheName][key]
end

local function companionCacheSet(cacheName, key, value)
    Bridge[cacheName] = Bridge[cacheName] or {keys = {}}
    local cache = Bridge[cacheName]
    if cache[key] == nil then
        cache.keys[#cache.keys + 1] = key
        if #cache.keys > 18 then
            local oldKey = table.remove(cache.keys, 1)
            if oldKey then cache[oldKey] = nil end
        end
    end
    cache[key] = value or false
    return cache[key]
end

local function companionSquareIsFree(square)
    if not square then return false end
    local ok, free = pcall(function() return square:isFree(false) end)
    if ok then return free == true end
    return true
end

local function companionSquareObjects(square)
    if not square or not square.getObjects then return nil end
    local ok, objects = pcall(function() return square:getObjects() end)
    if ok then return objects end
    return nil
end

local function companionObjectLooksLikeStairs(object)
    if not object or not object.getSprite then return false end
    local sprite = object:getSprite()
    if not sprite or not sprite.getName then return false end
    local ok, name = pcall(function() return sprite:getName() end)
    if not ok or not name then return false end
    name = tostring(name):lower()
    return string.find(name, "stairs", 1, true) ~= nil or string.find(name, "stair", 1, true) ~= nil
end

local function companionHasStairs(square)
    local objects = companionSquareObjects(square)
    if not objects then return false end
    for i = 0, objects:size() - 1 do
        if companionObjectLooksLikeStairs(objects:get(i)) then return true end
    end
    return false
end

local function companionSquareDoor(square)
    if not square or not square.getIsoDoor then return nil end
    local ok, door = pcall(function() return square:getIsoDoor() end)
    if ok then return door end
    return nil
end

local function companionSquareWindow(square)
    if not square or not square.getWindow then return nil end
    local ok, window = pcall(function() return square:getWindow() end)
    if ok then return window end
    return nil
end

function Bridge.CompanionFindHousePositions(anchor, bandit, order)
    local cell = getCell and getCell() or nil
    if not cell then return nil end

    local cacheKey = companionOrderCacheKey("housepos", order, anchor)
    local cached = companionCacheGet("_CompanionHousePositionsCache", cacheKey)
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end

    local ax = math.floor(tonumber(anchor and anchor.x) or (bandit and bandit.getX and bandit:getX()) or 0)
    local ay = math.floor(tonumber(anchor and anchor.y) or (bandit and bandit.getY and bandit:getY()) or 0)
    local az = math.floor(tonumber(anchor and anchor.z) or (bandit and bandit.getZ and bandit:getZ()) or 0)
    local radius = 15
    local targetBuilding = nil

    for z = az, az + 2 do
        for r = 0, radius do
            for x = ax - r, ax + r do
                for y = ay - r, ay + r do
                    if math.abs(x - ax) == r or math.abs(y - ay) == r then
                        local square = cell:getGridSquare(x, y, z)
                        local building = companionSquareBuilding(square)
                        if building then
                            targetBuilding = building
                            break
                        end
                    end
                end
                if targetBuilding then break end
            end
            if targetBuilding then break end
        end
        if targetBuilding then break end
    end

    if not targetBuilding then
        companionCacheSet("_CompanionHousePositionsCache", cacheKey, false)
        return nil
    end

    local positions = {}
    local fallback = {}
    for z = az, az + 2 do
        for x = ax - radius, ax + radius do
            for y = ay - radius, ay + radius do
                local square = cell:getGridSquare(x, y, z)
                if square and companionSquareBuilding(square) == targetBuilding and companionSquareRoom(square) then
                    local sx = square:getX()
                    local sy = square:getY()
                    local sz = square:getZ()
                    local free = companionSquareIsFree(square)
                    if free then
                        local score = 18
                        local faceX, faceY = ax, ay
                        local role = "interior"
                        local room = companionSquareRoom(square)
                        local roomName = room and room.getName and tostring(room:getName() or "") or ""
                        roomName = string.lower(roomName)

                        if sz > az then score = score + 8 end
                        if roomName == "bathroom" or roomName == "closet" then score = score - 8 end
                        if roomName == "kitchen" or roomName == "livingroom" or roomName == "bedroom" then score = score + 2 end
                        if companionHasStairs(square) then
                            score = score + 12
                            role = "stairs"
                        end

                        for dx = -1, 1 do
                            for dy = -1, 1 do
                                if math.abs(dx) + math.abs(dy) == 1 then
                                    local ns = cell:getGridSquare(sx + dx, sy + dy, sz)
                                    local sameBuilding = ns and companionSquareBuilding(ns) == targetBuilding
                                    local outside = ns and ns.isOutside and ns:isOutside()
                                    if not sameBuilding or outside then
                                        score = score + 18
                                        faceX = sx + dx * 5
                                        faceY = sy + dy * 5
                                        role = "window"
                                    elseif ns and not companionSquareIsFree(ns) then
                                        score = score + 3
                                    end
                                    if ns and companionSquareWindow(ns) then
                                        score = score + 14
                                        faceX = sx + dx * 5
                                        faceY = sy + dy * 5
                                        role = "window"
                                    end
                                    local door = ns and companionSquareDoor(ns) or nil
                                    if door then
                                        score = score + 10
                                        faceX = sx + dx * 4
                                        faceY = sy + dy * 4
                                        if role ~= "window" then role = "door" end
                                    end
                                end
                            end
                        end

                        local dist = NPCUtils and NPCUtils.DistTo and NPCUtils.DistTo(sx, sy, ax, ay) or 0
                        score = score - dist * 0.06
                        positions[#positions + 1] = {square = square, score = score, faceX = faceX, faceY = faceY, role = role}
                    else
                        fallback[#fallback + 1] = {square = square, score = 1, faceX = ax, faceY = ay, role = "fallback"}
                    end
                end
            end
        end
    end

    local list = #positions > 0 and positions or fallback
    if #list == 0 then
        companionCacheSet("_CompanionHousePositionsCache", cacheKey, false)
        return nil
    end

    table.sort(list, function(a, b) return (a.score or 0) > (b.score or 0) end)
    return companionCacheSet("_CompanionHousePositionsCache", cacheKey, list)
end

function Bridge.CompanionFindHouseSquares(anchor, bandit, order)
    local positions = Bridge.CompanionFindHousePositions(anchor, bandit, order)
    if not positions then return nil end
    local squares = {}
    for _, position in ipairs(positions) do
        if position.square then squares[#squares + 1] = position.square end
    end
    return squares
end

function Bridge.CompanionRestockForOrder(bandit, brain, order)
    if not (bandit and brain and order) then return end
    local restockKey = tostring(order.issued or 0)
    if brain.mercenarySearchRestockAt ~= restockKey then
        if NPCMercenaryContract and NPCMercenaryContract.RestockAndHealBrain then
            NPCMercenaryContract.RestockAndHealBrain(brain, bandit)
        end
        brain.mercenarySearchRestockAt = restockKey
    end
end

function Bridge.CompanionTryLootHouseOrder(bandit, brain, order, tasks, endurance)
    if not (bandit and brain and order and order.name == "LootHouse") then return nil end
    if not Bridge.IsHiredMercenaryBrain(brain) then return nil end
    tasks = tasks or {}

    Bridge.CompanionRestockForOrder(bandit, brain, order)

    local positions = Bridge.CompanionFindHousePositions(order.anchor, bandit, order)
    if not positions or #positions == 0 then
        table.insert(tasks, Bridge.MakeTimeTask("Shrug", 120))
        return "Follow"
    end

    local idx = Bridge.CompanionMemberIndex(bandit, brain)
    local top = math.min(#positions, 18)
    local position = positions[((idx - 1) % top) + 1]
    if not (position and position.square) then return nil end

    local square = position.square
    local tx = square:getX() + 0.5
    local ty = square:getY() + 0.5
    local tz = square:getZ()
    local dist = NPCUtils and NPCUtils.DistTo and NPCUtils.DistTo(bandit:getX(), bandit:getY(), tx, ty) or 9999
    local zdist = math.abs((tonumber(bandit:getZ()) or 0) - (tonumber(tz) or 0))

    brain.tacticalHouseSlot = {
        issued = order.issued,
        x = tx,
        y = ty,
        z = tz,
        role = position.role,
        faceX = position.faceX,
        faceY = position.faceY
    }

    if dist > 0.95 or zdist > 0.2 then
        Bridge.SetCompanionStationary(bandit, false)
        if NPCUtils and NPCUtils.GetMoveTask then
            local walkType = dist > 10 and "Run" or "Walk"
            table.insert(tasks, NPCUtils.GetMoveTask(endurance or 0, tx, ty, tz, walkType, dist, false))
        end
        return "Follow"
    end

    Bridge.SetCompanionStationary(bandit, true)

    local faceX = position.faceX or tx
    local faceY = position.faceY or ty
    if math.abs(faceX - tx) > 0.1 or math.abs(faceY - ty) > 0.1 then
        table.insert(tasks, {action = "FaceLocation", anim = "Idle", x = faceX, y = faceY, time = 100})
    end

    local role = position.role or "interior"
    if role == "window" then
        if idx % 3 == 0 then
            table.insert(tasks, Bridge.MakeTimeTask("AimRifle", 110))
        else
            table.insert(tasks, Bridge.MakeTimeTask("ShiftWeight", 130))
        end
    elseif role == "stairs" or role == "door" then
        if idx % 2 == 0 then
            table.insert(tasks, Bridge.MakeTimeTask("AimRifleLow", 100))
        else
            table.insert(tasks, Bridge.MakeTimeTask("ShiftWeight", 140))
        end
    else
        local variant = idx % 4
        if variant == 0 then
            table.insert(tasks, Bridge.MakeTimeTask("Smoke", 180))
        elseif variant == 1 then
            table.insert(tasks, Bridge.MakeTimeTask("ReloadRifle", 120))
        else
            table.insert(tasks, Bridge.MakeTimeTask("ShiftWeight", 160))
        end
    end
    return "Follow"
end

local function companionAtan2(y, x)
    if math.atan2 then return math.atan2(y, x) end
    x = tonumber(x) or 0
    y = tonumber(y) or 0
    if x > 0 then return math.atan(y / x) end
    if x < 0 and y >= 0 then return math.atan(y / x) + math.pi end
    if x < 0 and y < 0 then return math.atan(y / x) - math.pi end
    if y > 0 then return math.pi / 2 end
    if y < 0 then return -math.pi / 2 end
    return 0
end

function Bridge.CompanionMemberIndex(bandit, brain)
    local value = brain and (brain.memberIndex or brain.slotIndex or brain.id or brain.uid) or nil
    value = tonumber(value)
    if not value and NPCUtils and NPCUtils.GetCharacterID then
        local ok, id = pcall(function() return NPCUtils.GetCharacterID(bandit) end)
        if ok then value = tonumber(id) end
    end
    value = math.abs(value or 1)
    return ((math.max(1, value) - 1) % 18) + 1
end

function Bridge.CompanionOrderAnchor(order, bandit)
    local anchor = order and order.anchor or nil
    local x = tonumber(anchor and anchor.x) or (bandit and bandit.getX and bandit:getX()) or nil
    local y = tonumber(anchor and anchor.y) or (bandit and bandit.getY and bandit:getY()) or nil
    local z = tonumber(anchor and anchor.z) or (bandit and bandit.getZ and bandit:getZ()) or 0
    if not (x and y) then return nil end
    return {x = x, y = y, z = z, facingAngle = tonumber(anchor and anchor.facingAngle)}
end

function Bridge.CompanionOrderAngle(order, anchor, bandit, master)
    local a = tonumber(anchor and anchor.facingAngle)
    if a then return math.rad(a) end
    if master and anchor and master.getX and master.getY then
        local dx = (tonumber(anchor.x) or master:getX()) - master:getX()
        local dy = (tonumber(anchor.y) or master:getY()) - master:getY()
        if math.abs(dx) > 0.05 or math.abs(dy) > 0.05 then return companionAtan2(dy, dx) end
    end
    if bandit and bandit.getDirectionAngle then
        local ok, v = pcall(function() return bandit:getDirectionAngle() end)
        if ok and v then return math.rad(tonumber(v) or 0) end
    end
    return 0
end

function Bridge.CompanionIsSquareFree(square)
    if not square then return false end
    local ok, free = pcall(function() return square:isFree(false) end)
    if ok then return free == true end
    return true
end

function Bridge.CompanionCoverScore(square, ax, ay)
    if not square or not Bridge.CompanionIsSquareFree(square) then return nil end
    local score = 0
    if companionSquareRoom(square) then score = score + 5 end
    local sx = square:getX()
    local sy = square:getY()
    local sz = square:getZ()
    local cell = getCell and getCell() or nil
    if cell then
        for dx = -1, 1 do
            for dy = -1, 1 do
                if math.abs(dx) + math.abs(dy) == 1 then
                    local ns = cell:getGridSquare(sx + dx, sy + dy, sz)
                    if ns and not Bridge.CompanionIsSquareFree(ns) then score = score + 3 end
                    if ns and companionSquareRoom(ns) then score = score + 1 end
                end
            end
        end
    end
    local dist = NPCUtils and NPCUtils.DistTo and NPCUtils.DistTo(sx, sy, ax, ay) or 0
    score = score - (dist * 0.15)
    return score
end

function Bridge.CompanionCoverCandidates(anchor, order)
    local cell = getCell and getCell() or nil
    if not (cell and anchor) then return nil end
    local cacheKey = companionOrderCacheKey("cover", order, anchor)
    local cached = companionCacheGet("_CompanionTacticalCoverCache", cacheKey)
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end

    local ax = math.floor(tonumber(anchor.x) or 0)
    local ay = math.floor(tonumber(anchor.y) or 0)
    local az = math.floor(tonumber(anchor.z) or 0)
    local candidates = {}
    for r = 2, 8 do
        for x = ax - r, ax + r do
            for y = ay - r, ay + r do
                if math.abs(x - ax) == r or math.abs(y - ay) == r then
                    local square = cell:getGridSquare(x, y, az)
                    local score = Bridge.CompanionCoverScore(square, ax, ay)
                    if score then
                        candidates[#candidates + 1] = {square = square, score = score}
                    end
                end
            end
        end
    end
    if #candidates == 0 then
        companionCacheSet("_CompanionTacticalCoverCache", cacheKey, false)
        return nil
    end
    table.sort(candidates, function(a, b) return (a.score or 0) > (b.score or 0) end)
    return companionCacheSet("_CompanionTacticalCoverCache", cacheKey, candidates)
end

function Bridge.CompanionFindCover(anchor, bandit, brain, master, order)
    local candidates = Bridge.CompanionCoverCandidates(anchor, order)
    if not candidates or #candidates == 0 then return nil end
    local idx = Bridge.CompanionMemberIndex(bandit, brain)
    local pick = candidates[((idx - 1) % math.min(#candidates, 12)) + 1]
    if pick and pick.square then return pick.square:getX() + 0.5, pick.square:getY() + 0.5, pick.square:getZ() end
    return nil
end

function Bridge.CompanionTacticalSlot(orderName, order, bandit, brain, master)
    local anchor = Bridge.CompanionOrderAnchor(order, bandit)
    if not anchor then return nil end
    local idx = Bridge.CompanionMemberIndex(bandit, brain)
    local row = math.floor((idx - 1) / 2) + 1
    local side = (idx % 2 == 0) and 1 or -1
    local a = Bridge.CompanionOrderAngle(order, anchor, bandit, master)
    local fwdX, fwdY = math.cos(a), math.sin(a)
    local rightX, rightY = -math.sin(a), math.cos(a)
    local ax, ay, az = tonumber(anchor.x), tonumber(anchor.y), tonumber(anchor.z) or 0
    local tx, ty, tz = ax, ay, az
    local fx, fy = ax + fwdX * 10, ay + fwdY * 10
    orderName = tostring(orderName or "")

    if orderName == "Flank" then
        local flank = 3.2 + row * 1.45
        local depth = 0.6 + row * 0.35
        tx = ax + rightX * side * flank - fwdX * depth
        ty = ay + rightY * side * flank - fwdY * depth
        fx, fy = ax, ay
    elseif orderName == "Encircle" then
        local ring = math.floor((idx - 1) / 8)
        local pos = (idx - 1) % 8
        local radius = 3.2 + ring * 1.4
        local aa = a + pos * (math.pi * 2 / 8)
        tx = ax + math.cos(aa) * radius
        ty = ay + math.sin(aa) * radius
        fx, fy = ax, ay
    elseif orderName == "BackToBack" then
        local ring = math.floor((idx - 1) / 8)
        local pos = (idx - 1) % 8
        local radius = 1.35 + ring * 0.85
        local aa = a + pos * (math.pi * 2 / 8)
        tx = ax + math.cos(aa) * radius
        ty = ay + math.sin(aa) * radius
        fx = tx + math.cos(aa) * 10
        fy = ty + math.sin(aa) * 10
    elseif orderName == "TakeCover" then
        local cx, cy, cz = Bridge.CompanionFindCover(anchor, bandit, brain, master, order)
        if cx and cy then
            tx, ty, tz = cx, cy, cz or az
            fx, fy = ax, ay
        else
            tx = ax - fwdX * (1.6 + row * 0.65) + rightX * side * (1.4 + row * 0.8)
            ty = ay - fwdY * (1.6 + row * 0.65) + rightY * side * (1.4 + row * 0.8)
            fx, fy = ax, ay
        end
    elseif orderName == "Advance" then
        tx = ax - fwdX * (1.3 + row * 0.9) + rightX * side * row * 1.25
        ty = ay - fwdY * (1.3 + row * 0.9) + rightY * side * row * 1.25
        fx, fy = ax + fwdX * 12, ay + fwdY * 12
    elseif orderName == "FallBack" then
        tx = ax + rightX * side * row * 1.35
        ty = ay + rightY * side * row * 1.35
        fx, fy = ax + fwdX * 10, ay + fwdY * 10
    elseif orderName == "WatchSector" then
        tx = ax + rightX * side * row * 1.45 - fwdX * 0.35
        ty = ay + rightY * side * row * 1.45 - fwdY * 0.35
        fx, fy = ax + fwdX * 14, ay + fwdY * 14
    end

    return tx, ty, tz, fx, fy
end

function Bridge.CompanionTryTacticalPointOrder(bandit, brain, order, tasks, endurance)
    if not (bandit and brain and order and order.name) then return nil end
    if not Bridge.IsHiredMercenaryBrain(brain) then return nil end
    if not (NPCOrderContract and NPCOrderContract.IsTacticalPointOrder and NPCOrderContract.IsTacticalPointOrder(order)) then return nil end
    tasks = tasks or {}

    local master = Bridge.GetMasterPlayer(bandit)
    local tx, ty, tz, fx, fy = Bridge.CompanionTacticalSlot(order.name, order, bandit, brain, master)
    if not (tx and ty) then return nil end

    local dist = NPCUtils and NPCUtils.DistTo and NPCUtils.DistTo(bandit:getX(), bandit:getY(), tx, ty) or 0
    local zdist = math.abs((tonumber(bandit:getZ()) or 0) - (tonumber(tz) or 0))
    local walkType = "Walk"
    if order.name == "Flank" or order.name == "Advance" or order.name == "FallBack" then walkType = "Run" end
    if dist > 8 then walkType = "Run" end

    if dist > 1.25 or zdist > 0.2 then
        Bridge.SetCompanionStationary(bandit, false)
        if NPCUtils and NPCUtils.GetMoveTask then
            table.insert(tasks, NPCUtils.GetMoveTask(endurance or 0, tx, ty, tz or bandit:getZ(), walkType, dist, false))
        end
        return "Follow"
    end

    Bridge.SetCompanionStationary(bandit, true)

    if fx and fy then
        table.insert(tasks, {action = "FaceLocation", anim = "Idle", x = fx, y = fy, time = 100})
    end

    local id = Bridge.CompanionMemberIndex(bandit, brain)
    if order.name == "BackToBack" or order.name == "WatchSector" then
        if id % 3 == 0 then
            table.insert(tasks, Bridge.MakeTimeTask("AimRifle", 90))
        else
            table.insert(tasks, Bridge.MakeTimeTask("ShiftWeight", 100))
        end
    elseif order.name == "TakeCover" then
        if id % 2 == 0 then
            table.insert(tasks, Bridge.MakeTimeTask("LootLow", 80))
        else
            table.insert(tasks, Bridge.MakeTimeTask("AimRifleLow", 80))
        end
    else
        table.insert(tasks, Bridge.MakeTimeTask("ShiftWeight", 100))
    end

    return "Follow"
end

function Bridge.CompanionGetOrder(brain)
    if not brain then return nil end
    return (NPCOrderContract and NPCOrderContract.Get and NPCOrderContract.Get(brain)) or brain.order
end

function Bridge.CompanionTryDirectorOrder(bandit, brain, orderName, tasks)
    if not (orderName == "Patrol" or orderName == "Loot" or orderName == "Return") then return nil end

    local state = nil
    if orderName == "Patrol" then state = NPCBrainDirector and NPCBrainDirector.States and NPCBrainDirector.States.PatrolArea
    elseif orderName == "Loot" then state = NPCBrainDirector and NPCBrainDirector.States and NPCBrainDirector.States.LootArea
    elseif orderName == "Return" then state = NPCBrainDirector and NPCBrainDirector.States and NPCBrainDirector.States.ReturnToBase end

    if state and NPCBrainDirector and NPCBrainDirector.ExecuteState then
        local ok, directorTasks = pcall(function() return NPCBrainDirector.ExecuteState(bandit, brain, state, "mercenary player order", nil) end)
        if ok and directorTasks and #directorTasks > 0 then
            for _, task in pairs(directorTasks) do
                table.insert(tasks, task)
            end
            return "Follow"
        end
    end

    return nil
end

function Bridge.CompanionTryMobileOrder(bandit, brain, orderName, tasks)
    tasks = tasks or {}
    local order = Bridge.CompanionGetOrder(brain)

    local tacticalStage = Bridge.CompanionTryTacticalPointOrder(bandit, brain, order, tasks, 0)
    if tacticalStage then return tacticalStage end

    if orderName == "LootHouse" then
        return Bridge.CompanionTryLootHouseOrder(bandit, brain, order, tasks, 0)
    end

    if orderName == "Loot" and Bridge.IsHiredMercenaryBrain(brain) and order then
        Bridge.CompanionRestockForOrder(bandit, brain, order)
    end

    return Bridge.CompanionTryDirectorOrder(bandit, brain, orderName, tasks)
end
