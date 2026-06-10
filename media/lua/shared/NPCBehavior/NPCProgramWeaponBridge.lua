NPCProgramWeaponBridge = NPCProgramWeaponBridge or {}

require "NPCBehavior/NPCBehaviorBridge"
require "NPCCore/NPCLegacyContractBridge"

local Bridge = NPCBehaviorBridge
local NPC_WEAPON_LEGACY_ENTITY_GLOBAL = NPCLegacyContractBridge.Keys.FLAG
local NPC_WEAPON_LEGACY_LIVE_FLAG = NPCLegacyContractBridge.Key("FLAG")

local function weaponTargetKind(target)
    if instanceof and instanceof(target, "IsoPlayer") then return "player" end
    if instanceof and instanceof(target, "IsoZombie") then
        if target.getVariableBoolean and target:getVariableBoolean(NPC_WEAPON_LEGACY_LIVE_FLAG) then return "bandit" end
        return "zombie"
    end
    return "bandit"
end

local function npcEntityCall(name, ...)
    local entity = NPCEntity or (_G and _G[NPC_WEAPON_LEGACY_ENTITY_GLOBAL]) or nil
    local fn = entity and entity[name]
    if type(fn) ~= "function" then return nil end
    return fn(...)
end

local function weapon_nowMs()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then return math.floor(getGameTime():getWorldAgeHours() * 3600000) end
    return 0
end

local function weapon_sameTarget(brain, targetId, now)
    if not brain or not targetId then return false end
    local combat = brain.combat or brain.fsm or nil
    if not combat then return false end
    local current = combat.keepAimTargetId or combat.targetId
    local untilMs = tonumber(combat.keepAimUntil) or 0
    return current ~= nil and tostring(current) == tostring(targetId) and now <= untilMs
end

local function weapon_markAim(brain, targetId, now, holdMs)
    if not brain or not targetId then return end
    brain.combat = brain.combat or {}
    brain.combat.keepAimTargetId = targetId
    brain.combat.keepAimUntil = now + (tonumber(holdMs) or 1800)
end

function NPCProgramWeaponBridge.Switch(bandit, itemName)
    local tasks = {}
    bandit:clearAttachedItems()

    -- check what is equippped that needs to be deattached
    local old = bandit:getPrimaryHandItem()
    if old then
        local task = {action="Unequip", time=100, itemPrimary=old:getFullType()}
        table.insert(tasks, task)
    end

    -- grab new weapon
    local new = NPCCompatibilityBridge.InstanceItem(itemName)
    if new then
        local task = {action="Equip", itemPrimary=itemName}
        table.insert(tasks, task)
    end
    return tasks
end

function NPCProgramWeaponBridge.Aim(bandit, enemyCharacter, slot)
    local tasks = {}

    if Bridge and Bridge.HasClearShot and not Bridge.HasClearShot(bandit, enemyCharacter) then
        return tasks
    end

    local dist = NPCUtils.DistTo(bandit:getX(), bandit:getY(), enemyCharacter:getX(), enemyCharacter:getY())
    local targetId = NPCUtils.GetCharacterID(enemyCharacter)
    local brain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(bandit) or nil
    local now = weapon_nowMs()
    local stableAim = weapon_sameTarget(brain, targetId, now)
    local aimTimeMin = Bridge and Bridge.GetSandboxNumber and Bridge.GetSandboxNumber("General_GunReflexMin", 18) or 18
    local aimTimeSurp = math.floor(dist * 5)
    if dist <= 2.25 then
        aimTimeSurp = math.floor(aimTimeSurp * 0.35)
        aimTimeMin = math.min(aimTimeMin, 8)
    elseif stableAim then
        aimTimeSurp = math.floor(aimTimeSurp * 0.45)
        aimTimeMin = math.min(aimTimeMin, 10)
    end

    if instanceof(enemyCharacter, "IsoZombie") then
        aimTimeSurp = math.floor(aimTimeSurp / 2)
    else
        -- player handicap
        aimTimeSurp = aimTimeSurp + 10
    end
    if npcEntityCall("IsDNA", bandit, "slow") then
        aimTimeSurp = aimTimeSurp + 11
    end

    if aimTimeMin + aimTimeSurp > 0 then

        local anim
        local sound
        local asn = enemyCharacter:getActionStateName()
        local down = enemyCharacter:isProne() or enemyCharacter:isBumpFall() or asn == "onground" or asn == "getup"
        if slot == "primary" then
            sound = "M14BringToBear"
            if dist < 2.5 and down then
                anim = "AimRifleLow"
            elseif stableAim then
                anim = "AimRifle"
            else
                anim = "IdleToAimRifle"
            end
        else
            sound = "M9BringToBear"
            if dist < 2.5 and down then
                anim = "AimPistolLow"
            elseif stableAim then
                anim = "AimPistol"
            else
                anim = "IdleToAimPistol"
            end
        end

        weapon_markAim(brain, targetId, now, 2600)
        local targetKind = weaponTargetKind(enemyCharacter)
        local task = {action="Aim", anim=anim, sound=sound, x=enemyCharacter:getX(), y=enemyCharacter:getY(), z=enemyCharacter:getZ(), time=math.max(4, aimTimeMin + aimTimeSurp), eid=targetId, targetId=targetId, targetKind=targetKind}
        table.insert(tasks, task)
    end
    return tasks
end

function NPCProgramWeaponBridge.Shoot(bandit, enemyCharacter, slot)
    local tasks = {}

    if not bandit or not enemyCharacter then return tasks end
    if Bridge and Bridge.HasClearShot and not Bridge.HasClearShot(bandit, enemyCharacter) then
        return tasks
    end

    local brain = NPCBrainData.Get(bandit)
    if not brain or not brain.weapons or not brain.weapons[slot] then return tasks end

    local weapon = brain.weapons[slot]
    if not weapon or not weapon.name then return tasks end

    local weaponItem = NPCCompatibilityBridge.InstanceItem(weapon.name)

    local dist = NPCUtils.DistTo(bandit:getX(), bandit:getY(), enemyCharacter:getX(), enemyCharacter:getY())
    local targetId = NPCUtils.GetCharacterID(enemyCharacter)
    local now = weapon_nowMs()
    weapon_markAim(brain, targetId, now, 3200)
    local shotDelay = tonumber(weapon.shotDelay) or 30
    local firingtime = shotDelay + math.floor(dist ^ 1.1)
    if dist <= 2.25 then
        firingtime = math.max(5, math.floor(firingtime * 0.42))
    elseif weapon_sameTarget(brain, targetId, now) then
        firingtime = math.max(7, math.floor(firingtime * 0.70))
    end
    if npcEntityCall("IsDNA", bandit, "slow") then
        firingtime = firingtime + 3
    end

    local bullets = 1
    local mode = nil
    if weaponItem and weaponItem.getFireMode then
        local ok, value = pcall(function() return weaponItem:getFireMode() end)
        if ok then mode = value end
    end
    if dist < 6 and mode == "Auto" then
        bullets = 2 + ZombRand(4)
    end

    if NPCUtilityAIBridge and NPCUtilityAIBridge.IsPlayerGuardSuppressing and NPCUtilityAIBridge.IsPlayerGuardSuppressing(brain) then
        local suppressMax = tonumber(NPCUtilityAIBridge.Config and NPCUtilityAIBridge.Config.suppressBurstMax) or 4
        local wanted = slot == "primary" and suppressMax or math.max(2, suppressMax - 1)
        if mode == "Auto" then wanted = wanted + ZombRand(2) end
        local available = tonumber(weapon.bulletsLeft or 0) or 0
        if available > 0 then
            bullets = math.max(bullets, wanted)
            bullets = math.min(bullets, available)
        end
    end

    local anim
    local asn = enemyCharacter:getActionStateName()
    local down = enemyCharacter:isProne() or enemyCharacter:isBumpFall() or asn == "onground" or asn == "getup"
    if slot == "primary" then
        if dist < 2.5 and down then
            anim = "AimRifleLow"
        else
            anim = "AimRifle"
        end
    else
        if dist < 2.5 and down then
            anim = "AimPistolLow"
        else
            anim = "AimPistol"
        end
    end

    local targetKind = weaponTargetKind(enemyCharacter)
    local task = {action="Shoot", anim=anim, time=firingtime, slot=slot, x=enemyCharacter:getX(), y=enemyCharacter:getY(), z=enemyCharacter:getZ(), eid=targetId, targetId=targetId, targetKind=targetKind}
    table.insert(tasks, task)
    for i=2, bullets do
        local task = {action="Shoot", anim=anim, time=4, slot=slot, x=enemyCharacter:getX(), y=enemyCharacter:getY(), z=enemyCharacter:getZ(), eid=targetId, targetId=targetId, targetKind=targetKind}
        table.insert(tasks, task)
    end

    return tasks
end

function NPCProgramWeaponBridge.Reload(bandit, slot)
    local tasks = {}

    local brain = NPCBrainData.Get(bandit)
    if not brain or not brain.weapons or not brain.weapons[slot] then return tasks end

    local weapon = brain.weapons[slot]

    local soundEject
    local soundInsert
    if slot == "primary" then
        soundEject = "M14EjectAmmo"
        soundInsert = "M14InsertAmmo"
    else
        soundEject = "M9EjectAmmo"
        soundInsert = "M9InsertAmmo"
    end

    if not weapon.magName then
        if (tonumber(weapon.magCount) or 0) > 0 and (tonumber(weapon.magSize) or 0) > 0 then
            local task = {action="Reload", anim="ReloadRifle", slot=slot, sound=soundInsert, time=90}
            table.insert(tasks, task)
        end
        return tasks
    end

    local task = {action="Drop", itemType=weapon.magName, anim="UnloadRifle", sound=soundEject, time=90}
    table.insert(tasks, task)

    local task = {action="Reload", anim="ReloadRifle", slot=slot, sound=soundInsert, time=90}
    table.insert(tasks, task)

    return tasks
end
