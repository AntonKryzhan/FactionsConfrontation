NPCActionShootBridge = NPCActionShootBridge or {}
require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCLegacyContractBridge"

local NPC_ACTION_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
NPCEntity = NPCEntity or NPC_ACTION_LEGACY_GLOBALS.Get("Entity")
NPCUtils = NPCUtils or NPC_ACTION_LEGACY_GLOBALS.Get("Utils")
NPCCompatibilityBridge = NPCCompatibilityBridge or NPC_ACTION_LEGACY_GLOBALS.Get("Compatibility")
NPCBrainData = NPCBrainData or NPC_ACTION_LEGACY_GLOBALS.Get("Brain")
NPCPlayerClient = NPCPlayerClient or NPC_ACTION_LEGACY_GLOBALS.Get("PlayerClient")
NPCZombieCacheBridge = NPCZombieCacheBridge or NPC_ACTION_LEGACY_GLOBALS.Get("ZombieCache")
NPCFactionBridge = NPCFactionBridge or NPC_ACTION_LEGACY_GLOBALS.Get("Faction")
NPCSpyBridge = NPCSpyBridge or NPC_ACTION_LEGACY_GLOBALS.Get("Spy")
NPCSpatialIndexBridge = NPCSpatialIndexBridge or NPC_ACTION_LEGACY_GLOBALS.Get("SpatialIndex")

local NPC_ACTION_SHOOT_LEGACY_KEYS = {
    liveFlag = NPCLegacyContractBridge.Key("FLAG"),
    formerNPCZombie = NPCLegacyContractBridge.Key("FORMER_ZOMBIE"),
    isNPC = NPCLegacyContractBridge.Key("IS_FLAG"),
    shotAggroPathAt = NPCLegacyContractBridge.Key("SHOT_AGGRO_PATH_AT"),
    primary = NPCLegacyContractBridge.Key("PRIMARY"),
    secondary = NPCLegacyContractBridge.Key("SECONDARY"),
    sandboxSection = NPCLegacyContractBridge.Sandbox.main
}


local function IsFormerNPCZombie(target)
    if not target or not instanceof or not instanceof(target, "IsoZombie") then return false end
    if target:getVariableBoolean(NPC_ACTION_SHOOT_LEGACY_KEYS.formerNPCZombie) then return true end
    local md = target:getModData()
    return md and md[NPC_ACTION_SHOOT_LEGACY_KEYS.formerNPCZombie] == true
end

local function IsLiveNPC(target)
    if not target or not instanceof or not instanceof(target, "IsoZombie") then return false end
    if IsFormerNPCZombie(target) then return false end
    return target:getVariableBoolean(NPC_ACTION_SHOOT_LEGACY_KEYS.liveFlag) == true
end

local function zas_nowMs()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then return math.floor(getGameTime():getWorldAgeHours() * 3600000) end
    return 0
end

local function zas_pathZombieToShooter(zombie, shooter, cooldownMs)
    if not zombie or not shooter then return end
    local md = zombie:getModData()
    if not md then return end

    local now = zas_nowMs()
    cooldownMs = tonumber(cooldownMs) or 900
    if md[NPC_ACTION_SHOOT_LEGACY_KEYS.shotAggroPathAt] and now - md[NPC_ACTION_SHOOT_LEGACY_KEYS.shotAggroPathAt] < cooldownMs then return end

    md[NPC_ACTION_SHOOT_LEGACY_KEYS.shotAggroPathAt] = now

    -- Same PZ 41 MP movement warning as in movement-stability module: a normal
    -- zombie can already be in WalkTowardState after setTarget()/addAggro(), and
    -- adding path2 through pathToLocationF() floods the client log. In B41 the
    -- target/aggro assignment above is enough; keep explicit pathing for newer
    -- builds only.
    if NPCCompatibilityBridge and NPCCompatibilityBridge.GetGameVersion and NPCCompatibilityBridge.GetGameVersion() < 42 then
        return
    end

    pcall(function()
        zombie:pathToLocationF(shooter:getX() + 0.5, shooter:getY() + 0.5, shooter:getZ())
    end)
end

local function zas_rememberNpcShot(shooter, radius)
    if not shooter then return end
    NPCZombieCacheBridge = NPCZombieCacheBridge or {}
    NPCZombieCacheBridge.ShotMemory = NPCZombieCacheBridge.ShotMemory or {}

    local id = NPCUtils and NPCUtils.GetCharacterID and NPCUtils.GetCharacterID(shooter) or nil
    if not id then return end

    local now = zas_nowMs()
    radius = tonumber(radius) or 36
    NPCZombieCacheBridge.ShotMemory[tostring(id)] = {
        x = shooter:getX(),
        y = shooter:getY(),
        z = shooter:getZ(),
        radius = radius,
        untilMs = now + 6500
    }
end

local function zas_aggroNearbyZombiesToShot(shooter, radius)
    if not shooter then return end

    radius = math.min(tonumber(radius) or 12, 12)
    local touched = 0

    local function touchZombie(zombie)
        if not zombie or zombie == shooter then return false end
        if not instanceof or not instanceof(zombie, "IsoZombie") then return false end
        if zombie.getVariableBoolean and zombie:getVariableBoolean(NPC_ACTION_SHOOT_LEGACY_KEYS.liveFlag) then return false end
        if zombie.isAlive and not zombie:isAlive() then return false end

        pcall(function() zombie:setTarget(shooter) end)
        pcall(function() zombie:setAttackedBy(shooter) end)
        if zombie.addAggro then
            pcall(function() zombie:addAggro(shooter, 2.0) end)
        end
        zas_pathZombieToShooter(zombie, shooter, 1200)
        touched = touched + 1
        return touched >= 10
    end

    if NPCSpatialIndexBridge and NPCSpatialIndexBridge.GetNearbyZombiesInto then
        local scratch = NPCActionShootBridge._shotAggroScratch or {}
        NPCActionShootBridge._shotAggroScratch = scratch
        for i = 1, #scratch do scratch[i] = nil end
        local list, count = NPCSpatialIndexBridge.GetNearbyZombiesInto(scratch, shooter:getX(), shooter:getY(), shooter:getZ(), radius)
        count = tonumber(count) or (list and #list) or 0
        for i = 1, count do
            if touchZombie(list[i]) then return end
        end
        return
    end

    if not getCell then return end
    local cell = getCell()
    if not cell then return end

    local sx = math.floor(shooter:getX())
    local sy = math.floor(shooter:getY())
    local sz = math.floor(shooter:getZ())
    local radius2 = radius * radius

    for dx = -radius, radius do
        for dy = -radius, radius do
            if dx * dx + dy * dy <= radius2 then
                local square = cell:getGridSquare(sx + dx, sy + dy, sz)
                if square and touchZombie(square:getZombie()) then return end
            end
        end
    end
end

local function IsArmedNpcZombieResidue(target)
    if not target or not instanceof or not instanceof(target, "IsoZombie") then return false end
    if IsLiveNPC(target) or IsFormerNPCZombie(target) then return true end

    local primary = target:getPrimaryHandItem()
    if primary then return true end

    local secondary = target:getSecondaryHandItem()
    if secondary then return true end

    local primaryName = target:getVariableString(NPC_ACTION_SHOOT_LEGACY_KEYS.primary)
    if primaryName and primaryName ~= "" then return true end

    local secondaryName = target:getVariableString(NPC_ACTION_SHOOT_LEGACY_KEYS.secondary)
    if secondaryName and secondaryName ~= "" then return true end

    local md = target:getModData()
    return md and md[NPC_ACTION_SHOOT_LEGACY_KEYS.isNPC] == true
end


local function bshot_sameValue(a, b)
    return a ~= nil and b ~= nil and tostring(a) == tostring(b)
end

local function bshot_groupId(brain)
    if type(brain) ~= "table" then return nil end
    return brain.worldGroupId or brain.groupId or brain.homeGroupId
end

local function bshot_isSameSquad(a, b)
    if not (type(a) == "table" and type(b) == "table") then return false end
    if bshot_sameValue(a.id, b.id) then return true end
    if bshot_sameValue(a.uid or a.persistentId, b.uid or b.persistentId) then return true end
    if bshot_sameValue(bshot_groupId(a), bshot_groupId(b)) then return true end
    return false
end

local function bshot_isFriendlyLiveNPC(attackerBrain, targetBrain, target)
    if not IsLiveNPC(target) then return false end
    if not attackerBrain then return true end
    if not targetBrain then return true end
    if bshot_isSameSquad(attackerBrain, targetBrain) then return true end
    if NPCFactionBridge and NPCFactionBridge.IsEnabled and NPCFactionBridge.IsEnabled() and NPCFactionBridge.AreBrainsEnemies then
        local ok, enemies = pcall(function() return NPCFactionBridge.AreBrainsEnemies(attackerBrain, targetBrain) end)
        if ok then return enemies ~= true end
    end
    if attackerBrain.clan ~= nil and targetBrain.clan ~= nil and attackerBrain.clan == targetBrain.clan then return true end
    if attackerBrain.hostile ~= nil and targetBrain.hostile ~= nil and attackerBrain.hostile == targetBrain.hostile then return true end
    return false
end

local function CanDamageTarget(attackerBrain, targetBrain, target)
    if IsFormerNPCZombie(target) then return true end
    if target and instanceof and instanceof(target, "IsoZombie") and not IsLiveNPC(target) then return true end
    if bshot_isFriendlyLiveNPC(attackerBrain, targetBrain, target) then return false end

    if targetBrain and NPCFactionBridge and NPCFactionBridge.IsEnabled and NPCFactionBridge.IsEnabled() and NPCFactionBridge.AreBrainsEnemies then
        return NPCFactionBridge.AreBrainsEnemies(attackerBrain, targetBrain)
    end

    if target and instanceof and instanceof(target, "IsoPlayer") then
        if attackerBrain and attackerBrain.spy == true and attackerBrain.spyDefected ~= true and NPCSpyBridge and NPCSpyBridge.PlayerId and tostring(attackerBrain.spyForPlayerId or "") == tostring(NPCSpyBridge.PlayerId(target) or "") then return false end
        if NPCSpyBridge and NPCSpyBridge.ShouldHoldFireAgainstPlayer and NPCSpyBridge.ShouldHoldFireAgainstPlayer(attackerBrain, target) then return false end
        if NPCFactionBridge and NPCFactionBridge.IsEnabled and NPCFactionBridge.IsEnabled() and NPCFactionBridge.CanBrainAttackPlayer then
            return NPCFactionBridge.CanBrainAttackPlayer(attackerBrain, target)
        end
        return attackerBrain and attackerBrain.hostile == true
    end

    if IsLiveNPC(target) and not targetBrain then return false end
    if not targetBrain or not targetBrain.clan then return false end
    if not attackerBrain then return false end
    return attackerBrain.clan ~= targetBrain.clan or (attackerBrain.hostile and not targetBrain.hostile)
end


local function CanCompleteShootTask(attackerBrain, task)
    if not task or task.targetKind ~= "player" then return true end
    if not (NPCPlayerClient and NPCPlayerClient.GetPlayerById) then return true end
    local player = NPCPlayerClient.GetPlayerById(task.targetId or task.eid)
    if not player then return true end
    return CanDamageTarget(attackerBrain, nil, player) == true
end

local function bshot_killVictim(attacker, victim)
    if not victim then return end
    local md = victim.getModData and victim:getModData() or nil
    if md then
        md.NPCKeepCorpse = true
        md.NPCCorpseFromNPCCombat = true
        md.NPCCorpseDeathAt = getTimestampMs and getTimestampMs() or 0
    end
    local killer = attacker
    if not killer and getCell and getCell() then killer = getCell():getFakeZombieForHit() end
    if killer then
        victim:Kill(killer, true)
    elseif victim.Kill then
        victim:Kill(nil, true)
    end
end

local function ApplyNPCWeaponDamage(attacker, item, victim, fallbackDamage, allowArmedResidue)
    if not victim or not instanceof or not instanceof(victim, "IsoZombie") then return end
    local formerNPCZombie = IsFormerNPCZombie(victim)
    local liveNPC = IsLiveNPC(victim)
    local zombieFallback = allowArmedResidue == true
    local armedResidue = zombieFallback and IsArmedNpcZombieResidue(victim)
    if not liveNPC and not formerNPCZombie and not armedResidue and not zombieFallback then return end

    local brain = liveNPC and NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(victim) or nil
    local health = tonumber(victim:getHealth()) or tonumber(brain and brain.health) or 1
    local damage = tonumber(fallbackDamage) or 0.35

    if item then
        local ok, maxDamage = pcall(function() return item:getMaxDamage() end)
        if ok and tonumber(maxDamage) and tonumber(maxDamage) > 0 then
            damage = math.max(damage, tonumber(maxDamage) * 0.85)
        end
    end

    if formerNPCZombie then damage = math.max(damage, 0.45) end
    local newHealth = health - damage
    if brain then
        brain.health = newHealth
        if brain.regen then
            local now = getTimestampMs and getTimestampMs() or 0
            brain.regen.lastHealth = newHealth
            brain.regen.lastDamageAt = now
            brain.regen.nextRegenAt = now + 5500
        end
    end

    victim:setAttackedBy(attacker)
    if newHealth <= 0 then
        victim:setHealth(0)
        bshot_killVictim(attacker, victim)
    else
        victim:setHealth(newHealth)
    end
end

local function Hit(shooter, item, victim)

    -- Clone the shooter to create a temporary IsoPlayer
    local tempShooter = NPCUtils.CloneIsoPlayer(shooter)

    -- Calculate the distance between the shooter and the victim
    local dist = NPCUtils.DistTo(victim:getX(), victim:getY(), tempShooter:getX(), tempShooter:getY())

    -- Determine accuracy based on SandboxVars and shooter clan
    local brainShooter = NPCBrainData.Get(shooter)
    local accuracyBoost = tonumber(brainShooter and brainShooter.accuracyBoost) or 1
    if accuracyBoost <= 0 then accuracyBoost = 1 end
    local accuracyLevel = SandboxVars[NPC_ACTION_SHOOT_LEGACY_KEYS.sandboxSection].General_OverallAccuracy
    local accuracyCoeff = 0.11
    if accuracyLevel == 1 then
        accuracyCoeff = 0.5
    elseif accuracyLevel == 2 then
        accuracyCoeff = 0.22
    elseif accuracyLevel == 3 then
        accuracyCoeff = 0.11
    elseif accuracyLevel == 4 then
        accuracyCoeff = 0.06
    elseif accuracyLevel == 5 then
        accuracyCoeff = 0.028
    end

    local accuracyThreshold = 100 / (1 + accuracyCoeff * (dist - 1) / accuracyBoost)

    -- Warning, this is not perfect, local player mand remote players will not generate the same 
    -- random number.
    if ZombRand(100) < accuracyThreshold then
        NPCPlayerClient.WakeEveryone()
        
        if instanceof(victim, 'IsoPlayer') and SandboxVars[NPC_ACTION_SHOOT_LEGACY_KEYS.sandboxSection].General_HitModel == 2 then
            PlayerDamageModel.BulletHit(tempShooter, victim)
        else
            if instanceof(victim, "IsoPlayer") and (victim:isSprinting() or (victim:isRunning() and ZombRand(12) == 1)) then
                victim:clearVariable("BumpFallType")
                victim:setBumpType("stagger")
                victim:setBumpFall(true)
                victim:setBumpFallType("pushedBehind")
                ApplyNPCWeaponDamage(shooter, item, victim, 0.75)
            else
                victim:setHitFromBehind(shooter:isBehind(victim))

                if instanceof(victim, "IsoZombie") then
                    victim:setHitAngle(shooter:getForwardDirection())
                    victim:setPlayerAttackPosition(victim:testDotSide(shooter))
                end

                local healthBefore = instanceof(victim, "IsoZombie") and tonumber(victim:getHealth()) or nil
                victim:Hit(item, tempShooter, 6, false, 1, false)
                victim:setAttackedBy(shooter)
                ApplyNPCWeaponDamage(shooter, item, victim, 0.75)
                if instanceof(victim, "IsoZombie") and not IsLiveNPC(victim) then
                    local healthAfter = tonumber(victim:getHealth())
                    if not healthBefore or not healthAfter or healthAfter >= healthBefore then
                        ApplyNPCWeaponDamage(shooter, item, victim, 0.75, true)
                    end
                end
                if not (instanceof(victim, "IsoZombie") and (IsLiveNPC(victim) or IsFormerNPCZombie(victim))) then
                    local bodyDamage = victim:getBodyDamage()
                    if bodyDamage then
                        local health = bodyDamage:getOverallBodyHealth()
                        health = health + 8
                        if health > 100 then health = 100 end
                        bodyDamage:setOverallBodyHealth(health)
                    end
                end
            end

            victim:addBlood(0.6)

            NPCCompatibilityBridge.Splash(victim, item, tempShooter)
            
            if instanceof(victim, "IsoPlayer") then
                NPCCompatibilityBridge.PlayerVoiceSound(victim, "PainFromFallHigh")
            end

            if victim:getHealth() <= 0 then bshot_killVictim(shooter, victim) end
        end
    else
        -- Custom miss audio is intentionally disabled in the neutral sound-strip stage.
    end

    -- Clean up the temporary player after use
    tempShooter:removeFromWorld()
    tempShooter = nil

    return true
end

local vehicleParts = {
    [1] = {name="HeadlightLeft", dmg=18, sndHit="BreakGlassItem", sndDest="SmashWindow"},
    [2] = {name="HeadlightRight", dmg=18, sndHit="BreakGlassItem", sndDest="SmashWindow"},
    [3] = {name="HeadlightRearLeft", dmg=18, sndHit="BreakGlassItem", sndDest="SmashWindow"},
    [4] = {name="HeadlightRearRight", dmg=18, sndHit="BreakGlassItem", sndDest="SmashWindow"},
    [5] = {name="Windshield", dmg=20, sndHit="BreakGlassItem", sndDest="SmashWindow"},
    [6] = {name="WindshieldRear", dmg=20, sndHit="BreakGlassItem", sndDest="SmashWindow"},
    [7] = {name="WindowFrontRight", dmg=20, sndHit="BreakGlassItem", sndDest="SmashWindow"},
    [8] = {name="WindowFrontLeft", dmg=20, sndHit="BreakGlassItem", sndDest="SmashWindow"},
    [9] = {name="WindowRearRight", dmg=20, sndHit="BreakGlassItem", sndDest="SmashWindow"},
    [10] = {name="WindowRearLeft", dmg=20, sndHit="BreakGlassItem", sndDest="SmashWindow"},
    [11] = {name="WindowMiddleLeft", dmg=20, sndHit="BreakGlassItem", sndDest="SmashWindow"},
    [12] = {name="WindowMiddleRight", dmg=20, sndHit="BreakGlassItem", sndDest="SmashWindow"},
    [13] = {name="DoorFrontRight", dmg=10, sndHit="HitVehiclePartWithWeapon", sndDest="HitVehiclePartWithWeapon"},
    [14] = {name="DoorFrontLeft", dmg=10, sndHit="HitVehiclePartWithWeapon", sndDest="HitVehiclePartWithWeapon"},
    [15] = {name="DoorRearRight", dmg=10, sndHit="HitVehiclePartWithWeapon", sndDest="HitVehiclePartWithWeapon"},
    [16] = {name="DoorRearLeft", dmg=10, sndHit="HitVehiclePartWithWeapon", sndDest="HitVehiclePartWithWeapon"},
    [17] = {name="EngineDoor", dmg=10, sndHit="HitVehiclePartWithWeapon", sndDest="HitVehiclePartWithWeapon"},
    [18] = {name="TireFrontRight", dmg=8, sndHit="VehicleTireExplode", sndDest="VehicleTireExplode"},
    [19] = {name="TireFrontLeft", dmg=8, sndHit="VehicleTireExplode", sndDest="VehicleTireExplode"},
    [20] = {name="TireRearLeft", dmg=8, sndHit="VehicleTireExplode", sndDest="VehicleTireExplode"},
    [21] = {name="TireRearRight", dmg=8, sndHit="VehicleTireExplode", sndDest="VehicleTireExplode"}
}

local sounds = {
    ["WoodDoor"] = "HitBarricadePlank",
    ["MetalDoor"] = "HitBarricadeMetal",
}
-- Bresenham's line of fire to detect what needs to destroyed between shooter and target

local function thump (object, thumper)
    local health = object:getHealth()
    print ("thumpable health: " .. object:getHealth())
    health = health - 20
    if health < 0 then health = 0 end
    if health == 0 then
        object:destroy()
    else
        object:setHealth(health)
        object:Thump(thumper)
    end
end

local function ManageLineOfFire (shooter, victim)
    local cell = getCell()

    local x0 = math.floor(shooter:getX())
    local y0 = math.floor(shooter:getY())
    local x1 = math.floor(victim:getX())
    local y1 = math.floor(victim:getY())
    local z = victim:getZ()

    local dx = math.abs(x1 - x0)
    local dy = math.abs(y1 - y0)
    local sx = (x0 < x1) and 1 or -1
    local sy = (y0 < y1) and 1 or -1
    local err = dx - dy

    local cx, cy, cz = x0, y0, z

    local function checkWindow(square, shooter)
        local window = square:getWindow()
        if window then
            if (window:getNorth() and (y0 < cy or y1 < cy)) or 
               (not window:getNorth() and (x0 < cx or x1 < cx)) then
                local barricade = window:getBarricadeOnSameSquare()
                if not barricade then
                    barricade = window:getBarricadeOnOppositeSquare()
                end
                local smash = false
                if barricade then
                    if barricade:isMetal() then
                        barricade:Thump(shooter)
                        square:playSound("HitBarricadeMetal")
                        return true
                    else -- wood
                        barricade:Thump(shooter)
                        local p = barricade:getNumPlanks()
                        if p >= 2 then
                            square:playSound("HitBarricadePlank")
                            return true
                        end
                    end
                end
                if not window:isSmashed() then
                    square:playSound("SmashWindow")
                    window:smashWindow()
                end
            end
        end
        return false
    end

    local function checkDoor(square, shooter)
        local snds = sounds
        local door = square:getIsoDoor()
        if door and not door:IsOpen() then
            if (door:getNorth() and (y0 < cy or y1 < cy)) or 
               (not door:getNorth() and (x0 < cx or x1 < cx)) then
                -- small chance to shoot through a small window in door
                if ZombRand(10) > 1 then 
                    local sprite = door:getSprite()
                    local props = sprite:getProperties()
                    if props:Is("DoorSound") then
                        doorSound = props:Val("DoorSound")
                        if snds[doorSound] then
                            square:playSound(snds[doorSound])
                        end
                    end

                    thump(door, shooter)
                    
                    return true
                end
            end
        end
        return false
    end

    local function checkVehicle(square, shooter)
        local player = getPlayer()
        local vp = vehicleParts
        local vehicle = square:getVehicleContainer()
        if vehicle then
            local partRandom = ZombRand(30)
            local vehiclePart
            local dmg
            if vp[partRandom] then
                vehiclePart = vehicle:getPartById(vp[partRandom].name)
                if vehiclePart and vehiclePart:getInventoryItem() then
                    
                    local vehiclePartId = vehiclePart:getId()

                    local dmg = vp[partRandom].dmg
                    vehiclePart:damage(dmg)

                    if vehiclePart:getCondition() <= 0 then
                        vehiclePart:setInventoryItem(nil)
                        square:playSound(vp[partRandom].sndDest)
                    else
                        square:playSound(vp[partRandom].sndHit)
                        return true
                    end

                    vehicle:updatePartStats()
                    
                    local args = {x=square:getX(), y=square:getY(), id=vehiclePartId, dmg=dmg}
                    sendClientCommand(player, 'NPCCommands', 'VehiclePartDamage', args)
                    
                end
            end
        end
        return false
    end

    while true do
        
        local square = cell:getGridSquare(cx, cy, cz)
        if square then

            local obstacle
            -- manage window obstacle
            obstacle = checkWindow(square, shooter)
            if obstacle then return false end

            -- manage for door obstacle
            obstacle = checkDoor(square, shooter)
            if obstacle then return false end

            -- manage vehicle obstacle
            obstacle = checkVehicle(square, shooter)
            if obstacle then return false end
            
        end

        if cx == x1 and cy == y1 then break end
        local e2 = 2 * err
        if e2 > -dy then
            err = err - dy
            cx = cx + sx
        end
        if e2 < dx then
            err = err + dx
            cy = cy + sy
        end
    end
    
    -- no bullet stop
    return true
end


local function ManageLineOfFire2 (shooter, victim)
    local cell = getCell()
    local player = getPlayer()
    local vp = vehicleParts
    local x0 = math.floor(shooter:getX())
    local y0 = math.floor(shooter:getY())
    local x1 = math.floor(victim:getX())
    local y1 = math.floor(victim:getY())

    if x0 > x1 then x0, x1 = x1, x0 end
    if y0 > y1 then y0, y1 = y1, y0 end

    local dx = x1 - x0
    local dy = y1 - y0
    local D = 2 * dy - dx
    local y = y0
    
    for x = x0, x1 do
        -- for sx = -1, 1 do
            -- for sy = -1, 1 do

                local square = cell:getGridSquare(x, y, 0)

                if square then

                    local sx = square:getX()
                    local sy = square:getY()
                    -- smash windows
                    local window = square:getWindow()
                    if window and not window:isSmashed() then
                        square:playSound("SmashWindow")
                        window:smashWindow()
                    end

                    local vehicle = square:getVehicleContainer()
                    if vehicle then
                        local partRandom = ZombRand(30)
                        local vehiclePart
                        local dmg
                        if vp[partRandom] then
                            vehiclePart = vehicle:getPartById(vp[partRandom].name)
                            if vehiclePart and vehiclePart:getInventoryItem() then
                                
                                local vehiclePartId = vehiclePart:getId()

                                local dmg = vp[partRandom].dmg
                                vehiclePart:damage(dmg)

                                local gothrough = true
                                if vehiclePart:getCondition() <= 0 then
                                    vehiclePart:setInventoryItem(nil)
                                    square:playSound(vp[partRandom].sndDest)
                                else
                                    square:playSound(vp[partRandom].sndHit)
                                    gothrough = false
                                end

                                vehicle:updatePartStats()
                                
                                local args = {x=square:getX(), y=square:getY(), id=vehiclePartId, dmg=dmg}
                                sendClientCommand(player, 'NPCCommands', 'VehiclePartDamage', args)
                                
                                if not gothrough then return end
                            end
                        end
                    end

                    -- cant shoot through the closed door (although bandits can see through them)
                    local door = square:getIsoDoor()
                    if door and not door:IsOpen() then
                        if door:getNorth() then
                            if y0 < sy or y1 < sy then
                                return false
                            end
                        end
                    end
                end
            -- end
        -- end

        if D > 0 then
            y = y + 1
            D = D - 2 * dx
        end
        D = D + 2 * dy
    end



    return true
end


local function bshot_playShotSound(shooter, item, weapon)
    if not shooter then return end
    local sound = weapon and weapon.shotSound
    if (not sound or sound == "" or sound == false) and item and item.getSwingSound then
        local ok, swing = pcall(function() return item:getSwingSound() end)
        if ok and swing and swing ~= "" then sound = swing end
    end
    if not sound or sound == "" or sound == false then sound = "M9Shoot" end

    pcall(function() shooter:playSound(sound) end)
    local square = shooter.getSquare and shooter:getSquare() or nil
    if square and square.playSound then
        pcall(function() square:playSound(sound) end)
    end
    local emitter = shooter.getEmitter and shooter:getEmitter() or nil
    if emitter and emitter.playSound then
        pcall(function() emitter:playSound(sound) end)
    end
end

ZombieActions = type(ZombieActions) == "table" and ZombieActions or {}
ZombieActions.Shoot = ZombieActions.Shoot or {}
NPCActionShootBridge.OnStart = function(zombie, task)
    if NPCEntity and NPCEntity.SetAim then
        pcall(function() NPCEntity.SetAim(zombie, true) end)
    end
    zombie:setBumpType(task.anim)
    return true
end

NPCActionShootBridge.OnWorking = function(zombie, task)
    if NPCEntity and NPCEntity.SetAim then
        pcall(function() NPCEntity.SetAim(zombie, true) end)
    end
    zombie:faceLocationF(task.x, task.y)

    if task.time <= 0 then return true end

    if zombie:getBumpType() ~= task.anim then 
        zombie:setBumpType(task.anim)
    end

    return false
end


local function ResolveShootTaskTarget(task)
    if not task then return nil end
    local targetId = task.targetId or task.eid
    if targetId == nil then return nil end

    if task.targetKind == "player" and NPCPlayerClient and NPCPlayerClient.GetPlayerById then
        local ok, player = pcall(function() return NPCPlayerClient.GetPlayerById(targetId) end)
        if ok then return player end
    end

    if NPCZombieCacheBridge and NPCZombieCacheBridge.Cache then
        local target = NPCZombieCacheBridge.Cache[targetId] or NPCZombieCacheBridge.Cache[tostring(targetId)]
        if target then return target end
    end

    return nil
end

local function HasClearShotForTask(shooter, task)
    local target = ResolveShootTaskTarget(task)
    if not target then return true end
    if not target.isAlive or not target:isAlive() then return false end
    if NPCUtils and NPCUtils.LineClear then
        local ok, clear = pcall(function() return NPCUtils.LineClear(shooter, target) end)
        if ok and clear == false then return false end
    end
    if shooter and target and shooter.getZ and target.getZ and math.floor(tonumber(shooter:getZ()) or 0) ~= math.floor(tonumber(target:getZ()) or 0) then
        return false
    end
    return true
end

NPCActionShootBridge.OnComplete = function(zombie, task)

    if NPCEntity and NPCEntity.SetAim then
        pcall(function() NPCEntity.SetAim(zombie, true) end)
    end

    local bumpType = zombie:getBumpType()
    if bumpType ~= task.anim then return true end

    local shooter = zombie
    local cell = shooter:getSquare():getCell()

    -- local item = InventoryItemFactory.CreateItem("Base.AssaultRifle2")
    -- ATROShoot(shooter, item)

    local brainShooter = NPCBrainData.Get(shooter)
    if not CanCompleteShootTask(brainShooter, task) then
        return true
    end
    if not HasClearShotForTask(shooter, task) then
        return true
    end

    local weapon = brainShooter.weapons[task.slot]
    if not weapon then return true end
    weapon.bulletsLeft = math.max(0, (tonumber(weapon.bulletsLeft) or 0) - 1)
    NPCEntity.UpdateItemsToSpawnAtDeath(shooter)

    local shotItem = NPCCompatibilityBridge.InstanceItem(weapon.name)
    NPCCompatibilityBridge.StartMuzzleFlash(shooter)
    bshot_playShotSound(shooter, shotItem, weapon)

    --[[local te = FBORenderTracerEffects.getInstance()
    te:addEffect(shooter, 24)

    local test = shooter:getAnimationPlayer()
    local test2 = test:isReady()]]
    
    -- this adds world sound that attract zombies, it must be on cooldown
    -- otherwise too many sounds disorient zombies. 
    if not brainShooter.sound or brainShooter.sound == 0 then
        addSound(getPlayer(), shooter:getX(), shooter:getY(), shooter:getZ(), 40, 100)
        zas_rememberNpcShot(shooter, 40)
        zas_aggroNearbyZombiesToShot(shooter, 18)
        brainShooter.sound = 1
        -- legacy brain update(shooter, brainShooter)
    end

    for dx=-2, 2 do
        for dy=-2, 2 do
            local square = cell:getGridSquare(task.x + dx, task.y + dy, task.z)

            if square then
                local victim

                local testPlayer = square:getPlayer()
                if testPlayer and CanDamageTarget(brainShooter, nil, testPlayer) then
                    victim = testPlayer
                end

                if not victim and math.abs(dx) <= 1 and math.abs(dy) <= 1 then
                    local testVictim = square:getZombie()

                    if testVictim then
                        local brainVictim = NPCBrainData.Get(testVictim)
                        if CanDamageTarget(brainShooter, brainVictim, testVictim) then 
                            victim = testVictim
                        end
                    end
                end
                
                if victim then
                    if NPCUtils.GetCharacterID(shooter) ~= NPCUtils.GetCharacterID(victim) then 
                        local res = ManageLineOfFire(shooter, victim)
                        local finalCheck = NPCUtils.LineClear(shooter, victim)
                        if res and finalCheck then
                            Hit(shooter, shotItem or NPCCompatibilityBridge.InstanceItem(weapon.name), victim)
                        end
                        zombie:setBumpDone(true)
                        return true
                        
                    end
                end
            end
        end
    end


    return true
end