NPCActionShootBridge = NPCActionShootBridge or {}
require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCZombieLifecycleClassifierBridge"
pcall(require, "NPCCore/NPCBeliefStateBridge")
pcall(require, "NPCCore/NPCExperienceLedgerBridge")
pcall(require, "NPCCore/NPCAdaptiveLearningBridge")
pcall(require, "NPCCore/NPCInfluenceFieldBridge")

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

local function bshot_dist2(a, b)
    if not (a and b and a.getX and b.getX) then return 999999 end
    local dx = (tonumber(a:getX()) or 0) - (tonumber(b:getX()) or 0)
    local dy = (tonumber(a:getY()) or 0) - (tonumber(b:getY()) or 0)
    return dx * dx + dy * dy
end

local function bshot_sameFloor(a, b)
    if not (a and b and a.getZ and b.getZ) then return true end
    return math.floor(tonumber(a:getZ()) or 0) == math.floor(tonumber(b:getZ()) or 0)
end


local function bshot_getBrain(character)
    if not character or not NPCBrainData or not NPCBrainData.Get then return nil end
    local ok, brain = pcall(function()
        return NPCBrainData.Get(character)
    end)
    if ok and type(brain) == "table" then return brain end
    return nil
end

local function bshot_getWeapon(brain, slot)
    if type(brain) ~= "table" or type(brain.weapons) ~= "table" then return nil end
    if slot == nil then return nil end
    return brain.weapons[slot] or brain.weapons[tostring(slot)] or brain.weapons[tonumber(slot) or -1]
end

local function bshot_characterId(character)
    if character and NPCUtils and NPCUtils.GetCharacterID then
        local ok, id = pcall(function() return NPCUtils.GetCharacterID(character) end)
        if ok and id ~= nil then return id end
    end
    return character and tostring(character) or nil
end

local function bshot_safeWakeEveryone()
    if NPCPlayerClient and NPCPlayerClient.WakeEveryone then
        pcall(function() NPCPlayerClient.WakeEveryone() end)
    end
end

local function bshot_safeDistance(a, b)
    if not (a and b and a.getX and b.getX) then return 999 end
    if NPCUtils and NPCUtils.DistTo then
        local ok, dist = pcall(function() return NPCUtils.DistTo(a:getX(), a:getY(), b:getX(), b:getY()) end)
        if ok and tonumber(dist) then return tonumber(dist) end
    end
    return math.sqrt(bshot_dist2(a, b))
end

local function bshot_accuracyLevel(defaultValue)
    local section = SandboxVars and SandboxVars[NPC_ACTION_SHOOT_LEGACY_KEYS.sandboxSection] or nil
    return tonumber(section and section.General_OverallAccuracy) or tonumber(defaultValue) or 3
end

local function bshot_hitModel(defaultValue)
    local section = SandboxVars and SandboxVars[NPC_ACTION_SHOOT_LEGACY_KEYS.sandboxSection] or nil
    return tonumber(section and section.General_HitModel) or tonumber(defaultValue) or 1
end

local function bshot_instanceItem(name)
    if not name or name == "" then return nil end
    if NPCCompatibilityBridge and NPCCompatibilityBridge.InstanceItem then
        local ok, item = pcall(function() return NPCCompatibilityBridge.InstanceItem(name) end)
        if ok and item then return item end
    end
    if InventoryItemFactory and InventoryItemFactory.CreateItem then
        local ok, item = pcall(function() return InventoryItemFactory.CreateItem(name) end)
        if ok then return item end
    end
    return nil
end

local function bshot_rand(max)
    if ZombRand then return ZombRand(max) end
    return math.random(0, math.max(1, tonumber(max) or 1) - 1)
end

local function bshot_isLiveHumanTarget(target)
    if not target then return false end
    if instanceof and instanceof(target, "IsoPlayer") then return true end
    return IsLiveNPC(target) == true
end

local function zas_nowMs()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then return math.floor(getGameTime():getWorldAgeHours() * 3600000) end
    return 0
end

local function zas_loadLevel()
    if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.GetLoadState then
        local ok, state = pcall(function() return NPCWorkSchedulerBridge.GetLoadState(false) end)
        if ok and state then return tonumber(state.level) or 0, tonumber(state.zoom) or 1 end
    end
    return 0, 1
end

local function zas_settingBool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        return NPCLegacySettingsBridge.GetBool(name, defaultValue == true)
    end
    local vars = SandboxVars and SandboxVars[NPCLegacyContractBridge.Sandbox.ext] or nil
    local value = vars and vars[name]
    if value == nil then return defaultValue == true end
    return value == true or value == 1 or value == "true"
end

local function zas_settingNumber(name, defaultValue, minValue, maxValue)
    local value
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        value = NPCLegacySettingsBridge.GetNumber(name, defaultValue, minValue, maxValue)
    else
        local vars = SandboxVars and SandboxVars[NPCLegacyContractBridge.Sandbox.ext] or nil
        value = tonumber(vars and vars[name]) or tonumber(defaultValue) or 0
        if minValue ~= nil and value < minValue then value = minValue end
        if maxValue ~= nil and value > maxValue then value = maxValue end
    end
    return value
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
    if not zas_settingBool("ZombieNPC_AggroEnabled", true) then return end

    radius = math.min(tonumber(radius) or 12, zas_settingNumber("ZombieNPC_HearingRadius", 36, 4, 120))
    local maxTouched = math.min(8, zas_settingNumber("ZombieNPC_MaxTargetRefreshPerTick", 10, 1, 80))
    local level = zas_loadLevel()
    if level >= 3 then
        radius = math.min(radius, 6)
        maxTouched = 2
    elseif level >= 2 then
        radius = math.min(radius, 7)
        maxTouched = 3
    elseif level >= 1 then
        radius = math.min(radius, 9)
        maxTouched = 5
    end
    local touched = 0

    local function touchZombie(zombie)
        if not zombie or zombie == shooter then return false end
        if not instanceof or not instanceof(zombie, "IsoZombie") then return false end
        if zombie.getVariableBoolean and zombie:getVariableBoolean(NPC_ACTION_SHOOT_LEGACY_KEYS.liveFlag) then return false end
        if zombie.isAlive and not zombie:isAlive() then return false end

        pcall(function() zombie:setTarget(shooter) end)
        pcall(function() zombie:setAttackedBy(shooter) end)
        if zombie.addAggro then
            pcall(function() zombie:addAggro(shooter, 3.0) end)
        end
        zas_pathZombieToShooter(zombie, shooter, 1200)
        touched = touched + 1
        return touched >= maxTouched
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

local function bshot_ownerId(brain)
    if type(brain) ~= "table" then return nil end
    return brain.mercenaryHiredBy or brain.master or brain.followPlayer or brain.ownerPlayerId or brain.hiredByPlayerId
end

local function bshot_playerId(player)
    if not player then return nil end
    if player.getOnlineID then
        local ok, value = pcall(function() return player:getOnlineID() end)
        if ok and value ~= nil then return tostring(value) end
    end
    if player.getUsername then
        local ok, value = pcall(function() return player:getUsername() end)
        if ok and value ~= nil and tostring(value) ~= "" then return tostring(value) end
    end
    if player.getDisplayName then
        local ok, value = pcall(function() return player:getDisplayName() end)
        if ok and value ~= nil and tostring(value) ~= "" then return tostring(value) end
    end
    return nil
end

local function bshot_sameOwner(a, b)
    local ao = bshot_ownerId(a)
    local bo = bshot_ownerId(b)
    return ao ~= nil and bo ~= nil and tostring(ao) == tostring(bo)
end

local function bshot_isOwnerPlayer(attackerBrain, player)
    local owner = bshot_ownerId(attackerBrain)
    local pid = bshot_playerId(player)
    return owner ~= nil and pid ~= nil and tostring(owner) == tostring(pid)
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
    if NPCFactionBridge and NPCFactionBridge.IsBrainRogueBreakdown and NPCFactionBridge.IsBrainRogueBreakdown(attackerBrain) then return false end
    if not targetBrain then return false end
    if bshot_sameOwner(attackerBrain, targetBrain) then return true end
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
        if bshot_isOwnerPlayer(attackerBrain, target) then return false end
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

local function bshot_isNpcLikeZombie(victim)
    if NPCZombieLifecycleClassifierBridge and NPCZombieLifecycleClassifierBridge.IsNPCLikeZombie then
        local ok, value = pcall(function() return NPCZombieLifecycleClassifierBridge.IsNPCLikeZombie(victim) end)
        if ok then return value == true end
    end
    if not victim or not instanceof or not instanceof(victim, "IsoZombie") then return false end
    return IsLiveNPC(victim) or IsFormerNPCZombie(victim) or IsArmedNpcZombieResidue(victim)
end

local function bshot_fakeZombieForKill()
    if getCell and getCell() and getCell().getFakeZombieForHit then
        return getCell():getFakeZombieForHit()
    end
    return nil
end

local function bshot_killVictim(attacker, victim)
    if not victim then return end

    local npcLike = bshot_isNpcLikeZombie(victim)
    local killer = nil

    if NPCZombieLifecycleClassifierBridge and NPCZombieLifecycleClassifierBridge.GetSafeKillSource then
        local ok, safeKiller, class = pcall(function()
            return NPCZombieLifecycleClassifierBridge.GetSafeKillSource(attacker, victim, bshot_fakeZombieForKill)
        end)
        if ok then
            killer = safeKiller
            npcLike = class ~= "ordinary_zombie" and class ~= "non_zombie" and class ~= "black_market"
        end
    end

    if not killer then
        local md = victim.getModData and victim:getModData() or nil
        if md then
            if npcLike then
                md.NPCKeepCorpse = true
                md.NPCCorpseFromNPCCombat = true
                md.NPCCorpseDeathAt = getTimestampMs and getTimestampMs() or 0
            else
                md.NPCKeepCorpse = nil
                md.NPCCorpseFromNPCCombat = nil
                md.NPCCorpseDeathAt = nil
            end
        end
        killer = npcLike and attacker or bshot_fakeZombieForKill()
    end

    if not killer then killer = attacker end

    if npcLike then
        local md = victim.getModData and victim:getModData() or nil
        if md then
            md.NPCKeepCorpse = true
            md.NPCLootableCorpse = true
            md.NPCCorpseFromNPCCombat = true
            md.NPCCorpseDeathAt = getTimestampMs and getTimestampMs() or 0
        end
        if NPCEntity and NPCEntity.UpdateItemsToSpawnAtDeath then pcall(function() NPCEntity.UpdateItemsToSpawnAtDeath(victim) end) end
    end

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

    local brain = liveNPC and bshot_getBrain(victim) or nil
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


local function bshot_recordOutcome(shooter, victim, hit, data)
    local brainShooter = bshot_getBrain(shooter)
    data = data or {}
    if victim and victim.getX and shooter and shooter.getX then
        local dx = (tonumber(victim:getX()) or 0) - (tonumber(shooter:getX()) or 0)
        local dy = (tonumber(victim:getY()) or 0) - (tonumber(shooter:getY()) or 0)
        data.dist2 = dx * dx + dy * dy
    end
    if NPCExperienceLedgerBridge and NPCExperienceLedgerBridge.RecordShot then
        pcall(function() NPCExperienceLedgerBridge.RecordShot(brainShooter, shooter, victim, hit == true, data) end)
    end
    if NPCInfluenceFieldBridge and NPCInfluenceFieldBridge.InjectShot then
        pcall(function() NPCInfluenceFieldBridge.InjectShot(shooter, victim, hit == true, data) end)
    end
    if NPCBeliefStateBridge and NPCBeliefStateBridge.UpdateEnemy and victim then
        pcall(function()
            NPCBeliefStateBridge.UpdateEnemy(brainShooter, shooter, victim, {
                detected = true,
                visible = true,
                lineClear = data.blocked ~= true,
                sameFloor = true,
                dist = data.dist,
                ttlMs = hit and 7000 or 3600
            })
        end)
    end
end

local function bshot_accuracyThreshold(shooter, victim, brainShooter)
    local dist = bshot_safeDistance(victim, shooter)
    if dist <= 1.45 then return 99 end
    if dist <= 2.25 then return 94 end
    if dist <= 3.25 then return 86 end
    local accuracyBoost = tonumber(brainShooter and brainShooter.accuracyBoost) or 1
    if accuracyBoost <= 0 then accuracyBoost = 1 end
    local accuracyLevel = bshot_accuracyLevel(3)
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
    local threshold = 100 / (1 + accuracyCoeff * (dist - 1) / accuracyBoost)
    if brainShooter and brainShooter.combat and brainShooter.combat.keepAimTargetId then
        local now = getTimestampMs and getTimestampMs() or 0
        local holdUntil = tonumber(brainShooter.combat.keepAimUntil) or 0
        if holdUntil > now then threshold = threshold + 6 end
    end
    if brainShooter and brainShooter.ai and (tonumber(brainShooter.ai.enemyConfidence) or 0) > 0.65 then
        threshold = threshold + 4
    end
    if dist <= 4.5 and threshold < 72 then threshold = 72 end

    -- Stage 337: NPC-vs-NPC firefights need a modest floor so open-field battles
    -- do not become endless visual shooting with no resolved damage.
    if IsLiveNPC(victim) then
        local victimBrain = bshot_getBrain(victim)
        if CanDamageTarget(brainShooter, victimBrain, victim) then
            if dist <= 12 and threshold < 64 then threshold = 64 end
            if dist <= 20 and threshold < 48 then threshold = 48 end
        end
    end
    return threshold
end

local function bshot_fastZombieHit(shooter, item, victim)
    local brainShooter = bshot_getBrain(shooter)
    local victimBrain = bshot_getBrain(victim)
    if not CanDamageTarget(brainShooter, victimBrain, victim) then
        bshot_recordOutcome(shooter, victim, false, {dist=bshot_safeDistance(victim, shooter), reason="friendly_fire_blocked"})
        return true
    end
    local accuracyThreshold = bshot_accuracyThreshold(shooter, victim, brainShooter)
    local didHit = bshot_rand(100) < accuracyThreshold
    if didHit then
        bshot_safeWakeEveryone()
        victim:setAttackedBy(shooter)
        if victim.setHitFromBehind and shooter.isBehind then victim:setHitFromBehind(shooter:isBehind(victim)) end
        if victim.setHitAngle and shooter.getForwardDirection then victim:setHitAngle(shooter:getForwardDirection()) end
        if victim.setPlayerAttackPosition and victim.testDotSide then victim:setPlayerAttackPosition(victim:testDotSide(shooter)) end
        local pointBlank = bshot_dist2(shooter, victim) <= 9.0
        ApplyNPCWeaponDamage(shooter, item, victim, pointBlank and 1.25 or 0.85, true)
        if victim.addBlood then victim:addBlood(pointBlank and 0.55 or 0.35) end
        if victim.getHealth and victim:getHealth() <= 0 then bshot_killVictim(shooter, victim) end
    end
    bshot_recordOutcome(shooter, victim, didHit, {dist=bshot_safeDistance(victim, shooter), accuracy=accuracyThreshold})
    return true
end

local function Hit(shooter, item, victim)

    if not (shooter and victim and shooter.getX and victim.getX) then return true end

    if instanceof and instanceof(victim, "IsoZombie") then
        return bshot_fastZombieHit(shooter, item, victim)
    end

    local brainShooter = bshot_getBrain(shooter)
    local victimBrain = bshot_getBrain(victim)
    if not CanDamageTarget(brainShooter, victimBrain, victim) then
        bshot_recordOutcome(shooter, victim, false, {dist=bshot_safeDistance(victim, shooter), reason="friendly_fire_blocked"})
        return true
    end

    -- Clone the shooter to create a temporary IsoPlayer
    local tempShooter = NPCUtils and NPCUtils.CloneIsoPlayer and NPCUtils.CloneIsoPlayer(shooter) or nil
    if not tempShooter then return true end

    -- Calculate the distance between the shooter and the victim
    local dist = bshot_safeDistance(victim, tempShooter)

    -- Determine accuracy based on SandboxVars and shooter clan
    local accuracyBoost = tonumber(brainShooter and brainShooter.accuracyBoost) or 1
    if accuracyBoost <= 0 then accuracyBoost = 1 end
    local accuracyLevel = bshot_accuracyLevel(3)
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
    if brainShooter and brainShooter.combat and brainShooter.combat.keepAimTargetId then
        local now = getTimestampMs and getTimestampMs() or 0
        local holdUntil = tonumber(brainShooter.combat.keepAimUntil) or 0
        if holdUntil > now then accuracyThreshold = accuracyThreshold + 6 end
    end
    if brainShooter and brainShooter.ai and (tonumber(brainShooter.ai.enemyConfidence) or 0) > 0.65 then
        accuracyThreshold = accuracyThreshold + 4
    end
    if bshot_isLiveHumanTarget(victim) then
        if dist <= 8 and accuracyThreshold < 68 then accuracyThreshold = 68 end
        if dist <= 12 and accuracyThreshold < 58 then accuracyThreshold = 58 end
        if dist <= 20 and accuracyThreshold < 45 then accuracyThreshold = 45 end
    end

    -- Warning, this is not perfect, local player mand remote players will not generate the same 
    -- random number.
    local didHit = bshot_rand(100) < accuracyThreshold
    if didHit then
        bshot_safeWakeEveryone()
        
        if instanceof(victim, 'IsoPlayer') and bshot_hitModel(1) == 2 and PlayerDamageModel and PlayerDamageModel.BulletHit then
            pcall(function() PlayerDamageModel.BulletHit(tempShooter, victim) end)
        else
            if instanceof(victim, "IsoPlayer") and (victim:isSprinting() or (victim:isRunning() and bshot_rand(12) == 1)) then
                if victim.clearVariable then victim:clearVariable("BumpFallType") end
                if victim.setBumpType then victim:setBumpType("stagger") end
                if victim.setBumpFall then victim:setBumpFall(true) end
                if victim.setBumpFallType then victim:setBumpFallType("pushedBehind") end
                ApplyNPCWeaponDamage(shooter, item, victim, 0.75)
            else
                if victim.setHitFromBehind and shooter.isBehind then victim:setHitFromBehind(shooter:isBehind(victim)) end

                if instanceof(victim, "IsoZombie") then
                    if victim.setHitAngle and shooter.getForwardDirection then victim:setHitAngle(shooter:getForwardDirection()) end
                    if victim.setPlayerAttackPosition and victim.testDotSide then victim:setPlayerAttackPosition(victim:testDotSide(shooter)) end
                end

                local healthBefore = instanceof(victim, "IsoZombie") and tonumber(victim:getHealth()) or nil
                if victim.Hit then pcall(function() victim:Hit(item, tempShooter, 6, false, 1, false) end) end
                if victim.setAttackedBy then victim:setAttackedBy(shooter) end
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

            if victim.addBlood then victim:addBlood(0.6) end

            if NPCCompatibilityBridge and NPCCompatibilityBridge.Splash then pcall(function() NPCCompatibilityBridge.Splash(victim, item, tempShooter) end) end
            
            if instanceof(victim, "IsoPlayer") then
                if NPCCompatibilityBridge and NPCCompatibilityBridge.PlayerVoiceSound then pcall(function() NPCCompatibilityBridge.PlayerVoiceSound(victim, "PainFromFallHigh") end) end
            end

            if victim.getHealth and victim:getHealth() <= 0 then bshot_killVictim(shooter, victim) end
        end
    else
        -- Custom miss audio is intentionally disabled in the neutral sound-strip stage.
    end

    bshot_recordOutcome(shooter, victim, didHit, {dist=dist, accuracy=accuracyThreshold})

    -- Clean up the temporary player after use
    if tempShooter.removeFromWorld then pcall(function() tempShooter:removeFromWorld() end) end
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
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool and NPCLegacySettingsBridge.GetBool("Debug_NPCShotThump", false) then
        print ("thumpable health: " .. object:getHealth())
    end
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
    if not (shooter and victim and shooter.getX and victim.getX and getCell) then return true end
    local cell = getCell()
    if not cell then return true end

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
                if bshot_rand(10) > 1 then 
                    local sprite = door:getSprite()
                    local props = sprite and sprite:getProperties() or nil
                    if props and props:Is("DoorSound") then
                        local doorSound = props:Val("DoorSound")
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
            local partRandom = bshot_rand(30)
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
                    if player and sendClientCommand then pcall(function() sendClientCommand(player, 'NPCCommands', 'VehiclePartDamage', args) end) end
                    
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


local function bshot_lineOfFireCacheKey(shooter, victim)
    if not (shooter and victim and shooter.getX and victim.getX) then return nil end
    local sid = bshot_characterId(shooter) or tostring(shooter)
    local tid = bshot_characterId(victim) or tostring(victim)
    local sx = math.floor((tonumber(shooter:getX()) or 0) * 2)
    local sy = math.floor((tonumber(shooter:getY()) or 0) * 2)
    local tx = math.floor((tonumber(victim:getX()) or 0) * 2)
    local ty = math.floor((tonumber(victim:getY()) or 0) * 2)
    local z = math.floor(tonumber(victim.getZ and victim:getZ() or 0) or 0)
    return tostring(sid) .. ":" .. tostring(tid) .. ":" .. tostring(sx) .. ":" .. tostring(sy) .. ":" .. tostring(tx) .. ":" .. tostring(ty) .. ":" .. tostring(z)
end

local function ManageLineOfFireCached(shooter, victim, ttlMs)
    local key = bshot_lineOfFireCacheKey(shooter, victim)
    if not key then return ManageLineOfFire(shooter, victim) end
    local now = zas_nowMs()
    ttlMs = tonumber(ttlMs) or 420
    local level = zas_loadLevel()
    if level >= 3 then ttlMs = ttlMs * 3 elseif level >= 2 then ttlMs = ttlMs * 2 end
    local cache = NPCActionShootBridge._lineOfFireCache or {items={}, count=0}
    if not cache.items then cache.items = {}; cache.count = 0 end
    local entry = cache.items[key]
    if entry and entry.ms and now - entry.ms <= ttlMs then
        return entry.clear == true
    end
    if (tonumber(cache.count) or 0) > 96 then
        cache.items = {}
        cache.count = 0
    end
    local clear = ManageLineOfFire(shooter, victim) == true
    if not cache.items[key] then cache.count = (tonumber(cache.count) or 0) + 1 end
    cache.items[key] = {ms=now, clear=clear}
    NPCActionShootBridge._lineOfFireCache = cache
    return clear
end


local function ManageLineOfFire2 (shooter, victim)
    if not (shooter and victim and shooter.getX and victim.getX and getCell) then return true end
    local cell = getCell()
    if not cell then return true end
    local player = getPlayer and getPlayer() or nil
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
                        local partRandom = bshot_rand(30)
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
                                if player and sendClientCommand then pcall(function() sendClientCommand(player, 'NPCCommands', 'VehiclePartDamage', args) end) end
                                
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

    local level = zas_loadLevel()
    pcall(function() shooter:playSound(sound) end)
    if level >= 2 then return end
    local square = shooter.getSquare and shooter:getSquare() or nil
    if square and square.playSound then
        pcall(function() square:playSound(sound) end)
    end
    if level >= 1 then return end
    local emitter = shooter.getEmitter and shooter:getEmitter() or nil
    if emitter and emitter.playSound then
        pcall(function() emitter:playSound(sound) end)
    end
end

ZombieActions = type(ZombieActions) == "table" and ZombieActions or {}
ZombieActions.Shoot = ZombieActions.Shoot or {}
NPCActionShootBridge.OnStart = function(zombie, task)
    if not (zombie and task) then return true end
    if NPCEntity and NPCEntity.SetAim then
        pcall(function() NPCEntity.SetAim(zombie, true) end)
    end
    if zombie.setBumpType then zombie:setBumpType(task.anim) end
    return true
end

local RefreshShootTaskTarget

local function bshot_lineClearCacheKey(shooter, target)
    if not shooter or not target then return nil end
    local sid = bshot_characterId(shooter) or tostring(shooter)
    local tid = bshot_characterId(target) or tostring(target)
    local sx = shooter.getX and math.floor((tonumber(shooter:getX()) or 0) * 2) or 0
    local sy = shooter.getY and math.floor((tonumber(shooter:getY()) or 0) * 2) or 0
    local tx = target.getX and math.floor((tonumber(target:getX()) or 0) * 2) or 0
    local ty = target.getY and math.floor((tonumber(target:getY()) or 0) * 2) or 0
    return tostring(sid) .. ":" .. tostring(tid) .. ":" .. tostring(sx) .. ":" .. tostring(sy) .. ":" .. tostring(tx) .. ":" .. tostring(ty)
end

local function bshot_lineClearCached(shooter, target, ttlMs)
    if not (NPCUtils and NPCUtils.LineClear) then return true end
    local key = bshot_lineClearCacheKey(shooter, target)
    if not key then return true end

    local now = zas_nowMs()
    ttlMs = tonumber(ttlMs) or 260
    local cache = NPCActionShootBridge._lineClearCache or {items={}, count=0}
    if not cache.items then cache.items = {}; cache.count = 0 end
    local entry = cache.items[key]
    if entry and entry.ms and now - entry.ms <= ttlMs then
        return entry.clear == true
    end

    if (tonumber(cache.count) or 0) > 96 then
        cache.items = {}
        cache.count = 0
    end

    local ok, clear = pcall(function() return NPCUtils.LineClear(shooter, target) end)
    local value = ok and clear == true
    if not value and bshot_isLiveHumanTarget(target) and bshot_sameFloor(shooter, target) and bshot_dist2(shooter, target) <= 625 then
        local okSee, canSee = pcall(function() return shooter:CanSee(target) end)
        if okSee and canSee == true then value = true end
    end
    if not cache.items[key] then cache.count = (tonumber(cache.count) or 0) + 1 end
    cache.items[key] = {ms=now, clear=value}
    NPCActionShootBridge._lineClearCache = cache
    return value
end

NPCActionShootBridge.OnWorking = function(zombie, task)
    if not (zombie and task) then return true end
    if NPCEntity and NPCEntity.SetAim then
        pcall(function() NPCEntity.SetAim(zombie, true) end)
    end

    if task.targetId or task.eid then
        local target = RefreshShootTaskTarget(zombie, task, false)
        if not target then return true end
    end
    if zombie.faceLocationF and task.x and task.y then zombie:faceLocationF(task.x, task.y) end

    if (tonumber(task.time) or 0) <= 0 then return true end

    local bumpType = zombie.getBumpType and zombie:getBumpType() or nil
    if bumpType ~= task.anim and zombie.setBumpType then 
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
        if ok and player then return player end
    end

    if NPCZombieCacheBridge and NPCZombieCacheBridge.Cache then
        local target = NPCZombieCacheBridge.Cache[targetId] or NPCZombieCacheBridge.Cache[tostring(targetId)]
        if target then return target end
    end

    if task.targetKind ~= "player" and NPCPlayerClient and NPCPlayerClient.GetPlayerById then
        local ok, player = pcall(function() return NPCPlayerClient.GetPlayerById(targetId) end)
        if ok and player then return player end
    end

    return nil
end

RefreshShootTaskTarget = function(shooter, task, force)
    if not force and task then
        local now = zas_nowMs()
        local last = tonumber(task._lastTargetRefreshMs) or 0
        if task._liveTarget and now - last < 120 then
            return task._liveTarget
        end
        task._lastTargetRefreshMs = now
    end

    local target = ResolveShootTaskTarget(task)
    if not target then return nil end
    if target.isAlive then
        local okAlive, alive = pcall(function() return target:isAlive() end)
        if okAlive and alive == false then return nil end
    end
    if shooter and target and shooter.getZ and target.getZ and math.floor(tonumber(shooter:getZ()) or 0) ~= math.floor(tonumber(target:getZ()) or 0) then
        return nil
    end
    if target.getX and target.getY then
        task.x = target:getX()
        task.y = target:getY()
        task.z = target.getZ and target:getZ() or task.z
    end
    task._liveTarget = target
    return target
end

local function bshot_pointBlankClear(shooter, target)
    if not (shooter and target and shooter.getX and target.getX) then return false end
    if shooter.getZ and target.getZ and math.floor(tonumber(shooter:getZ()) or 0) ~= math.floor(tonumber(target:getZ()) or 0) then return false end
    local dx = (tonumber(shooter:getX()) or 0) - (tonumber(target:getX()) or 0)
    local dy = (tonumber(shooter:getY()) or 0) - (tonumber(target:getY()) or 0)
    local d2 = dx * dx + dy * dy
    if d2 > 2.25 then return false end
    if d2 <= 0.65 then return true end
    if NPCMovementStabilityBridge and NPCMovementStabilityBridge.CanStepBetween and shooter.getSquare and target.getSquare then
        local ok, clear = pcall(function() return NPCMovementStabilityBridge.CanStepBetween(shooter, shooter:getSquare(), target:getSquare()) end)
        if ok then return clear == true end
    end
    return bshot_lineClearCached(shooter, target, 180) == true
end

local function bshot_markShotAim(brain, task)
    if type(brain) ~= "table" or type(task) ~= "table" then return end
    brain.combat = brain.combat or {}
    local now = zas_nowMs()
    brain.combat.keepAimTargetId = task.targetId or task.eid or brain.combat.keepAimTargetId
    brain.combat.keepAimUntil = now + 2400
end

local function HasClearShotForTask(shooter, task)
    if not (task and (task.targetId or task.eid)) then return true end
    local target = RefreshShootTaskTarget(shooter, task, true)
    if not target then return false end
    if bshot_pointBlankClear and bshot_pointBlankClear(shooter, target) then return true end
    if not bshot_lineClearCached(shooter, target, 320) then return false end
    return true
end

NPCActionShootBridge.OnComplete = function(zombie, task)

    if not (zombie and task) then return true end

    if NPCEntity and NPCEntity.SetAim then
        pcall(function() NPCEntity.SetAim(zombie, true) end)
    end

    local bumpType = zombie.getBumpType and zombie:getBumpType() or nil
    if bumpType ~= task.anim then return true end

    local shooter = zombie
    local directTarget = RefreshShootTaskTarget(shooter, task, true)
    if (task.targetId or task.eid) and not directTarget then return true end

    local shooterSquare = shooter.getSquare and shooter:getSquare() or nil
    local cell = shooterSquare and shooterSquare.getCell and shooterSquare:getCell() or (getCell and getCell() or nil)
    if not cell then return true end

    -- local item = InventoryItemFactory.CreateItem("Base.AssaultRifle2")
    -- ATROShoot(shooter, item)

    local brainShooter = bshot_getBrain(shooter)
    if not brainShooter then
        if zombie.setBumpDone then zombie:setBumpDone(true) end
        return true
    end
    bshot_markShotAim(brainShooter, task)
    if not CanCompleteShootTask(brainShooter, task) then
        return true
    end
    if not HasClearShotForTask(shooter, task) then
        if directTarget then bshot_recordOutcome(shooter, directTarget, false, {blocked=true, reason="no_clear_shot"}) end
        return true
    end

    local weapon = bshot_getWeapon(brainShooter, task.slot)
    if not weapon then return true end
    weapon.bulletsLeft = math.max(0, (tonumber(weapon.bulletsLeft) or 0) - 1)
    local nowShot = zas_nowMs()
    if not brainShooter._lastShotDeathItemsAt or nowShot - brainShooter._lastShotDeathItemsAt > 1000 then
        if NPCEntity and NPCEntity.UpdateItemsToSpawnAtDeath then pcall(function() NPCEntity.UpdateItemsToSpawnAtDeath(shooter) end) end
        brainShooter._lastShotDeathItemsAt = nowShot
    end

    local shotItem = bshot_instanceItem(weapon.name)
    if NPCCompatibilityBridge and NPCCompatibilityBridge.StartMuzzleFlash then pcall(function() NPCCompatibilityBridge.StartMuzzleFlash(shooter) end) end
    bshot_playShotSound(shooter, shotItem, weapon)

    -- this adds world sound that attract zombies, it must be on cooldown
    -- otherwise too many sounds disorient zombies.
    if not brainShooter.sound or brainShooter.sound == 0 then
        local level = zas_loadLevel()
        local configuredHearing = zas_settingNumber("ZombieNPC_HearingRadius", 36, 4, 120)
        local soundRadius = level >= 3 and math.min(configuredHearing, 20) or (level >= 2 and math.min(configuredHearing, 28) or configuredHearing)
        if addSound then
            local soundOwner = getPlayer and getPlayer() or shooter
            pcall(function() addSound(soundOwner, shooter:getX(), shooter:getY(), shooter:getZ(), soundRadius, 100) end)
        end
        zas_rememberNpcShot(shooter, soundRadius)
        zas_aggroNearbyZombiesToShot(shooter, level >= 2 and math.min(soundRadius, 18) or math.min(soundRadius, 28))
        brainShooter.sound = 1
        -- legacy brain update(shooter, brainShooter)
    end

    if directTarget and bshot_characterId(shooter) ~= bshot_characterId(directTarget) then
        local brainVictim = bshot_getBrain(directTarget)
        if CanDamageTarget(brainShooter, brainVictim, directTarget) then
            local pointBlank = bshot_pointBlankClear(shooter, directTarget)
            local res = pointBlank or ManageLineOfFireCached(shooter, directTarget, 420)
            local finalCheck = pointBlank or bshot_lineClearCached(shooter, directTarget, 520)
            if res and finalCheck then
                Hit(shooter, shotItem or bshot_instanceItem(weapon.name), directTarget)
                if zombie.setBumpDone then zombie:setBumpDone(true) end
                return true
            end
        end
    end

    if task.targetId or task.eid then
        if zombie.setBumpDone then zombie:setBumpDone(true) end
        return true
    end

    --[[local te = FBORenderTracerEffects.getInstance()
    te:addEffect(shooter, 24)

    local test = shooter:getAnimationPlayer()
    local test2 = test:isReady()]]
    
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
                        local brainVictim = bshot_getBrain(testVictim)
                        if CanDamageTarget(brainShooter, brainVictim, testVictim) then 
                            victim = testVictim
                        end
                    end
                end
                
                if victim then
                    if bshot_characterId(shooter) ~= bshot_characterId(victim) then 
                        local pointBlank = bshot_pointBlankClear(shooter, victim)
                        local res = pointBlank or ManageLineOfFireCached(shooter, victim, 360)
                        local finalCheck = pointBlank or bshot_lineClearCached(shooter, victim, 420)
                        if res and finalCheck then
                            Hit(shooter, shotItem or bshot_instanceItem(weapon.name), victim)
                        end
                        if zombie.setBumpDone then zombie:setBumpDone(true) end
                        return true
                        
                    end
                end
            end
        end
    end


    return true
end