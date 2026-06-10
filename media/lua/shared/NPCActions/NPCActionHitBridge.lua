NPCActionHitBridge = NPCActionHitBridge or {}
require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCZombieLifecycleClassifierBridge"

local NPC_ACTION_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
NPCEntity = NPCEntity or NPC_ACTION_LEGACY_GLOBALS.Get("Entity")
NPCUtils = NPCUtils or NPC_ACTION_LEGACY_GLOBALS.Get("Utils")
NPCCompatibilityBridge = NPCCompatibilityBridge or NPC_ACTION_LEGACY_GLOBALS.Get("Compatibility")
NPCBrainData = NPCBrainData or NPC_ACTION_LEGACY_GLOBALS.Get("Brain")
NPCPlayerClient = NPCPlayerClient or NPC_ACTION_LEGACY_GLOBALS.Get("PlayerClient")
NPCZombieCacheBridge = NPCZombieCacheBridge or NPC_ACTION_LEGACY_GLOBALS.Get("ZombieCache")
NPCFactionBridge = NPCFactionBridge or NPC_ACTION_LEGACY_GLOBALS.Get("Faction")
NPCSpyBridge = NPCSpyBridge or NPC_ACTION_LEGACY_GLOBALS.Get("Spy")

local NPC_ACTION_HIT_LEGACY_KEYS = {
    liveFlag = NPCLegacyContractBridge.Key("FLAG"),
    formerNPCZombie = NPCLegacyContractBridge.Key("FORMER_ZOMBIE"),
    isNPC = NPCLegacyContractBridge.Key("IS_FLAG"),
    primary = NPCLegacyContractBridge.Key("PRIMARY"),
    secondary = NPCLegacyContractBridge.Key("SECONDARY")
}


local function IsFormerNPCZombie(target)
    if not target or not instanceof or not instanceof(target, "IsoZombie") then return false end
    if target:getVariableBoolean(NPC_ACTION_HIT_LEGACY_KEYS.formerNPCZombie) then return true end
    local md = target:getModData()
    return md and md[NPC_ACTION_HIT_LEGACY_KEYS.formerNPCZombie] == true
end

local function IsLiveNPC(target)
    if not target or not instanceof or not instanceof(target, "IsoZombie") then return false end
    if IsFormerNPCZombie(target) then return false end
    return target:getVariableBoolean(NPC_ACTION_HIT_LEGACY_KEYS.liveFlag) == true
end

local function IsArmedNpcZombieResidue(target)
    if not target or not instanceof or not instanceof(target, "IsoZombie") then return false end
    if IsLiveNPC(target) or IsFormerNPCZombie(target) then return true end

    local primary = target:getPrimaryHandItem()
    if primary then return true end

    local secondary = target:getSecondaryHandItem()
    if secondary then return true end

    local primaryName = target:getVariableString(NPC_ACTION_HIT_LEGACY_KEYS.primary)
    if primaryName and primaryName ~= "" then return true end

    local secondaryName = target:getVariableString(NPC_ACTION_HIT_LEGACY_KEYS.secondary)
    if secondaryName and secondaryName ~= "" then return true end

    local md = target:getModData()
    return md and md[NPC_ACTION_HIT_LEGACY_KEYS.isNPC] == true
end


local function bff_sameValue(a, b)
    return a ~= nil and b ~= nil and tostring(a) == tostring(b)
end

local function bff_groupId(brain)
    if type(brain) ~= "table" then return nil end
    return brain.worldGroupId or brain.groupId or brain.homeGroupId
end

local function bff_ownerId(brain)
    if type(brain) ~= "table" then return nil end
    return brain.mercenaryHiredBy or brain.master or brain.followPlayer or brain.ownerPlayerId or brain.hiredByPlayerId
end

local function bff_playerId(player)
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

local function bff_sameOwner(a, b)
    local ao = bff_ownerId(a)
    local bo = bff_ownerId(b)
    return ao ~= nil and bo ~= nil and tostring(ao) == tostring(bo)
end

local function bff_isOwnerPlayer(attackerBrain, player)
    local owner = bff_ownerId(attackerBrain)
    local pid = bff_playerId(player)
    return owner ~= nil and pid ~= nil and tostring(owner) == tostring(pid)
end

local function bff_sameSquad(a, b)
    if not (type(a) == "table" and type(b) == "table") then return false end
    if bff_sameValue(a.id, b.id) then return true end
    if bff_sameValue(a.uid or a.persistentId, b.uid or b.persistentId) then return true end
    if bff_sameValue(bff_groupId(a), bff_groupId(b)) then return true end
    return false
end

local function bff_isFriendlyLiveNPC(attackerBrain, targetBrain, target)
    if not IsLiveNPC(target) then return false end
    if not attackerBrain then return true end
    if NPCFactionBridge and NPCFactionBridge.IsBrainRogueBreakdown and NPCFactionBridge.IsBrainRogueBreakdown(attackerBrain) then return false end
    if not targetBrain then return true end
    if bff_sameOwner(attackerBrain, targetBrain) then return true end
    if bff_sameSquad(attackerBrain, targetBrain) then return true end
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
    if bff_isFriendlyLiveNPC(attackerBrain, targetBrain, target) then return false end

    if targetBrain and NPCFactionBridge and NPCFactionBridge.IsEnabled and NPCFactionBridge.IsEnabled() and NPCFactionBridge.AreBrainsEnemies then
        return NPCFactionBridge.AreBrainsEnemies(attackerBrain, targetBrain)
    end

    if target and instanceof and instanceof(target, "IsoPlayer") then
        if bff_isOwnerPlayer(attackerBrain, target) then return false end
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

local function ResolveHitTaskTarget(task)
    if not task then return nil end
    local targetId = task.targetId or task.eid
    if targetId == nil then return nil end

    if NPCZombieCacheBridge and NPCZombieCacheBridge.Cache then
        local enemy = NPCZombieCacheBridge.Cache[targetId] or NPCZombieCacheBridge.Cache[tostring(targetId)]
        if enemy then return enemy end
    end

    if NPCPlayerClient and NPCPlayerClient.GetPlayerById then
        local ok, player = pcall(function() return NPCPlayerClient.GetPlayerById(targetId) end)
        if ok and player then return player end
    end

    return nil
end

local function RefreshHitTaskTarget(bandit, task)
    local enemy = ResolveHitTaskTarget(task)
    if not enemy then return nil end
    if enemy.isAlive then
        local okAlive, alive = pcall(function() return enemy:isAlive() end)
        if okAlive and alive == false then return nil end
    end
    if enemy.getX and enemy.getY then
        task.x = enemy:getX()
        task.y = enemy:getY()
        task.z = enemy.getZ and enemy:getZ() or task.z
    end
    return enemy
end


local function GetMeleeStrikeRange(item, task)
    local taskRange = task and tonumber(task.meleeStrikeRange) or nil
    if taskRange and taskRange > 0 then return taskRange end

    local maxRange = 1.1
    if item and item.getMaxRange then
        local okRange, value = pcall(function() return item:getMaxRange() end)
        if okRange and tonumber(value) then maxRange = tonumber(value) end
    end

    if maxRange < 0.70 then return math.max(0.48, maxRange - 0.05) end
    if maxRange < 1.15 then return math.max(0.62, maxRange - 0.18) end
    return math.max(0.78, maxRange - 0.25)
end

local function IsTargetInMeleeStrikeRange(attacker, target, item, task)
    if not (attacker and target and target.getX and target.getY and attacker.getX and attacker.getY) then return false end
    if target.getZ and attacker.getZ and math.floor(target:getZ() or 0) ~= math.floor(attacker:getZ() or 0) then return false end
    local dx = (target:getX() or 0) - (attacker:getX() or 0)
    local dy = (target:getY() or 0) - (attacker:getY() or 0)
    local range = GetMeleeStrikeRange(item, task)
    if task then task.meleeStrikeRange = range end
    return dx * dx + dy * dy <= range * range
end

local function bff_isNpcLikeZombie(victim)
    if NPCZombieLifecycleClassifierBridge and NPCZombieLifecycleClassifierBridge.IsNPCLikeZombie then
        local ok, value = pcall(function() return NPCZombieLifecycleClassifierBridge.IsNPCLikeZombie(victim) end)
        if ok then return value == true end
    end
    if not victim or not instanceof or not instanceof(victim, "IsoZombie") then return false end
    return IsLiveNPC(victim) or IsFormerNPCZombie(victim) or IsArmedNpcZombieResidue(victim)
end

local function bff_fakeZombieForKill()
    if getCell and getCell() and getCell().getFakeZombieForHit then
        return getCell():getFakeZombieForHit()
    end
    return nil
end

local function bff_killVictim(attacker, victim)
    if not victim then return end

    local npcLike = bff_isNpcLikeZombie(victim)
    local killer = nil

    if NPCZombieLifecycleClassifierBridge and NPCZombieLifecycleClassifierBridge.GetSafeKillSource then
        local ok, safeKiller, class = pcall(function()
            return NPCZombieLifecycleClassifierBridge.GetSafeKillSource(attacker, victim, bff_fakeZombieForKill)
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
        killer = npcLike and attacker or bff_fakeZombieForKill()
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

local function ApplyNPCMeleeDamage(attacker, item, victim, fallbackDamage, allowArmedResidue)
    if not victim or not instanceof or not instanceof(victim, "IsoZombie") then return end
    local formerNPCZombie = IsFormerNPCZombie(victim)
    local liveNPC = IsLiveNPC(victim)
    local zombieFallback = allowArmedResidue == true
    local armedResidue = zombieFallback and IsArmedNpcZombieResidue(victim)
    if not liveNPC and not formerNPCZombie and not armedResidue and not zombieFallback then return end

    local brain = liveNPC and NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(victim) or nil
    local health = tonumber(victim:getHealth()) or tonumber(brain and brain.health) or 1
    local damage = tonumber(fallbackDamage) or 0.18

    if item then
        local fullType = item.getFullType and item:getFullType() or nil
        if fullType == "Base.BareHands" then
            damage = 0.08
        else
            local ok, maxDamage = pcall(function() return item:getMaxDamage() end)
            if ok and tonumber(maxDamage) and tonumber(maxDamage) > 0 then
                damage = math.max(damage, tonumber(maxDamage) * 0.45)
            end
        end
    end

    if formerNPCZombie then damage = math.max(damage, 0.16) end
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
        bff_killVictim(attacker, victim)
    else
        victim:setHealth(newHealth)
    end
end

local function Hit(attacker, item, victim)
    -- Clone the attacker to create a temporary IsoPlayer
    local tempAttacker = NPCUtils.CloneIsoPlayer(attacker)

    -- Calculate distance between attacker and victim
    local dist = NPCUtils.DistTo(victim:getX(), victim:getY(), tempAttacker:getX(), tempAttacker:getY())
    local range = item:getMaxRange()
    if dist < range + 0.5 then
        NPCPlayerClient.WakeEveryone()

        local hitSound
        local veh = victim:getVehicle()
        
        if veh then
            hitSound = "HitVehicleWindowWithWeapon"
        else
            local chainsaw = tempAttacker:isPrimaryEquipped("AuthenticZClothing.Chainsaw")
            if chainsaw then
                hitSound = "BloodSplatter"
            else
                hitSound = item:getZombieHitSound()
            end
            if instanceof(victim, "IsoPlayer") and (victim:isSprinting() or (victim:isRunning() and ZombRand(6) == 1)) then
                victim:clearVariable("BumpFallType")
                victim:setBumpType("stagger")
                victim:setBumpFall(true)
                victim:setBumpFallType("pushedBehind")
                ApplyNPCMeleeDamage(attacker, item, victim, 0.18)
            else
                victim:setHitFromBehind(attacker:isBehind(victim))

                if instanceof(victim, "IsoZombie") then
                    victim:setHitAngle(attacker:getForwardDirection())
                    victim:setPlayerAttackPosition(victim:testDotSide(attacker))
                end

                if item:getFullType() == "Base.BareHands" and instanceof(victim, "IsoPlayer") then
                    PlayerDamageModel.BareHandHit(attacker, victim)
                    --local meleeItem = instanceItem("Base.Pencil")
                    --victim:Hit(meleeItem, getCell():getFakeZombieForHit(), 0.01, false, 0.01, false)
                    --[[local bodyDamage = victim:getBodyDamage()
                    if bodyDamage then
                        local health = bodyDamage:getOverallBodyHealth()
                        health = health - 5
                        bodyDamage:setOverallBodyHealth(health)
                    end]]
                else
                    local healthBefore = instanceof(victim, "IsoZombie") and tonumber(victim:getHealth()) or nil
                    victim:Hit(item, tempAttacker, 0.5, false, 1, false)
                    ApplyNPCMeleeDamage(attacker, item, victim, 0.18)
                    if instanceof(victim, "IsoZombie") and not IsLiveNPC(victim) then
                        local healthAfter = tonumber(victim:getHealth())
                        if not healthBefore or not healthAfter or healthAfter >= healthBefore then
                            ApplyNPCMeleeDamage(attacker, item, victim, 0.18, true)
                        end
                    end
                end
                victim:setAttackedBy(attacker)
                --[[
                local bodyDamage = victim:getBodyDamage()
                if bodyDamage then
                    local health = bodyDamage:getOverallBodyHealth()
                    health = health + 12
                    if health > 100 then health = 100 end
                    bodyDamage:setOverallBodyHealth(health)
                end]]
            end
            victim:addBlood(0.6)
            
            NPCCompatibilityBridge.Splash(victim, item, tempAttacker)
                
            if instanceof(victim, "IsoPlayer") then
                NPCCompatibilityBridge.PlayerVoiceSound(victim, "PainFromFallHigh")
            end

            if victim:getHealth() <= 0 then 
                bff_killVictim(attacker, victim)
            end
        end
        victim:playSound(hitSound)
        -- addSound(getPlayer(), victim:getX(), victim:getY(), victim:getZ(), 4, 50)
    end

    -- Clean up the temporary player after use
    tempAttacker:removeFromWorld()
    tempAttacker = nil
end

ZombieActions = type(ZombieActions) == "table" and ZombieActions or {}
ZombieActions.Hit = ZombieActions.Hit or {}
NPCActionHitBridge.OnStart = function(bandit, task)
    local anim 
    local sound

    local enemy = RefreshHitTaskTarget(bandit, task)
    if not enemy then return true end
    local brainNPC = NPCBrainData.Get(bandit)
    local enemyBrain = NPCBrainData.Get(enemy)
    if not CanDamageTarget(brainNPC, enemyBrain, enemy) then return true end
    
    local prone = enemy:isProne() or enemy:getActionStateName() == "onground" or enemy:getActionStateName() == "sitonground" or enemy:getActionStateName() == "climbfence" 
    local meleeItem = NPCCompatibilityBridge.InstanceItem(task.weapon)
    if not IsTargetInMeleeStrikeRange(bandit, enemy, meleeItem, task) then
        if task.x and task.y then bandit:faceLocation(task.x, task.y) end
        return true
    end
    local meleeItemType = WeaponType.getWeaponType(meleeItem)

    local sound = meleeItem:getSwingSound()
    if bandit:isPrimaryEquipped("AuthenticZClothing.Chainsaw") then
        local emitter = bandit:getEmitter()
        emitter:stopSoundByName("ChainsawIdle")
        sound = "ChainsawAttack1"
    end

    if prone then
        if ZombRand(2) == 0 and task.weapon ~= "Base.BareHands" then
            anim = "Attack2HFloor"
        else
            anim = "Attack2HStamp"
            sound = "AttackStomp"
        end
    else

        local attacks
        if task.weapon == "Base.BareHands" or meleeItemType == WeaponType.barehand then
            attacks = {"AttackBareHands1", "AttackBareHands2", "AttackBareHands3", "AttackBareHands4", "AttackBareHands5", "AttackBareHands6"}
        elseif meleeItemType == WeaponType.twohanded then
            attacks = {"Attack2H1", "Attack2H2", "Attack2H3", "Attack2H4"}
        -- elseif meleeItemType == WeaponType.heavy then
        --    attacks = {"Attack2HHeavy1", "Attack2HHeavy2"}
        elseif meleeItemType == WeaponType.onehanded then
            attacks = {"Attack1H1", "Attack1H2", "Attack1H3", "Attack1H4", "Attack1H5"}
        elseif meleeItemType == WeaponType.spear then
            attacks = {"AttackS1", "AttackS2"}
        elseif meleeItemType == WeaponType.chainsaw then
            attacks = {"AttackChainsaw1", "AttackChainsaw2"}
        else -- two handed / knife ?
            attacks = {"Attack2H1", "Attack2H2", "Attack2H3", "Attack2H4"}
        end

        if attacks then 
            anim = attacks[1+ZombRand(#attacks)]

        end
    end

    if sound then
        bandit:playSound(sound)
    end

    if anim then
        task.anim = anim
        NPCEntity.UpdateTask(bandit, task)
        bandit:setBumpType(anim)
    else
        return false
    end
    return true
end

NPCActionHitBridge.OnWorking = function(bandit, task)
    local currentEnemy = RefreshHitTaskTarget(bandit, task)
    if not currentEnemy then return true end
    bandit:faceLocation(task.x, task.y)
    local itemForRange = NPCCompatibilityBridge.InstanceItem(task.weapon)
    if not IsTargetInMeleeStrikeRange(bandit, currentEnemy, itemForRange, task) then return true end
    local bumpType = bandit:getBumpType()

    if bumpType ~= task.anim then return false end
    
    if not task.hit and task.time <= 50 then

        task.hit = true

        local asn = bandit:getActionStateName()
        -- print ("HIT AS:" .. asn)
        if asn == "getup" or asn == "getup-fromonback" or asn == "getup-fromonfront" or asn == "getup-fromsitting"
                 or asn =="staggerback" or asn == "staggerback-knockeddown" then return false end

        NPCEntity.UpdateTask(bandit, task)

        local item = NPCCompatibilityBridge.InstanceItem(task.weapon)
        local enemy = ResolveHitTaskTarget(task)
        local brainNPC = NPCBrainData.Get(bandit)
        if enemy and instanceof(enemy, "IsoZombie") then 
            local brainEnemy = NPCBrainData.Get(enemy)
            if CanDamageTarget(brainNPC, brainEnemy, enemy) then 
                Hit (bandit, item, enemy)
                if task.weapon ~= "AuthenticZClothing.Chainsaw" then return false end
            end
        end

        local player = (enemy and instanceof(enemy, "IsoPlayer")) and enemy or NPCPlayerClient.GetPlayerById(task.eid)
        if player then
            local eid = NPCUtils.GetCharacterID(player)
            local requestedId = task.targetId or task.eid
            if player:isAlive() and tostring(eid) == tostring(requestedId) and CanDamageTarget(brainNPC, nil, player) then
                Hit (bandit, item, player)
                if task.weapon ~= "AuthenticZClothing.Chainsaw" then return false end
            end
        end

        return false

    end
    
    return false
end

NPCActionHitBridge.OnComplete = function(bandit, task)
    return true
end