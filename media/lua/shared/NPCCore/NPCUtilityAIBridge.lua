-- NPCUtilityAIBridge.lua
-- Neutral shared backend for utility AI needs, morale and autonomous task scoring.

require "NPCCore/NPCLegacyContractBridge"

NPCUtilityAIBridge = NPCUtilityAIBridge or {}
local NPC_UTILITY_LEGACY_KEYS = {
    npcFlag = NPCLegacyContractBridge.Key("FLAG"),
    programNPC = NPCLegacyContractBridge.Key("FLAG")
}

NPCUtilityAIBridge.VERSION = "2026-05-02-rescue-utility-ai-1"

NPCUtilityAIBridge.Config = NPCUtilityAIBridge.Config or {
    memorySeconds = 120,
    needsEnabled = true,
    lowHealth = 0.36,
    criticalHealth = 0.22,
    fearFlee = 0.78,
    moraleHold = 0.42,
    minimumGunDistance = 5.5,
    idealGunDistance = 11.0,
    autonomyDelayHours = 0.035,
    hungerLimit = 0.74,
    waterLimit = 0.78,
    restLimit = 0.82,
    boredomLimit = 0.65,
    needsTickHours = 0.018,
    foodRatePerHour = 0.030,
    waterRatePerHour = 0.040,
    restRatePerHour = 0.028,
    boredomRatePerHour = 0.025,
    combatNeedMultiplier = 1.8,
    combatRestMultiplier = 2.1,
    threatFearMultiplier = 1.0,
    threatMoraleLossMultiplier = 1.0,
    holdFireCooldownSeconds = 2.0,
    returnFireSeconds = 8.0,
    dangerCloseDistance = 7.0,
    defensiveDistance = 9.0,
    suppressDistance = 32.0,
    suppressBurstMax = 4,
    suppressionSeconds = 3.5,
    suppressionReturnFireDistance = 8.0
}

NPCUtilityAIBridge.Progression = NPCUtilityAIBridge.Progression or {
    maxLevel = 30,
    maxSkill = 10
}

if NPCLegacySettingsBridge and NPCLegacySettingsBridge.ApplyUtilityAI then
    NPCLegacySettingsBridge.ApplyUtilityAI(NPCUtilityAIBridge)
end

local bua_skillKeys = {"combat", "scavenge", "medicine", "fitness", "teamwork"}

local function bua_nowHours()
    if getGameTime then return getGameTime():getWorldAgeHours() or 0 end
    return 0
end

local function bua_nowMs()
    if getTimestampMs then return getTimestampMs() end
    return math.floor(bua_nowHours() * 3600000)
end

local function bua_clamp(v, minv, maxv)
    v = tonumber(v)
    if v == nil then return minv end
    if v < minv then return minv end
    if v > maxv then return maxv end
    return v
end

local function bua_dist(x1, y1, x2, y2)
    if not x1 or not y1 or not x2 or not y2 then return 99999 end
    local dx = x1 - x2
    local dy = y1 - y2
    return math.sqrt(dx * dx + dy * dy)
end

local function bua_xpNext(level)
    level = math.max(1, tonumber(level) or 1)
    return 100 + ((level - 1) * 65)
end

local function bua_skillNeed(level)
    level = math.max(0, tonumber(level) or 0)
    return 60 + (level * 45)
end

local function bua_getBrain(chr)
    if not chr or not NPCBrainData or not NPCBrainData.Get then return nil end
    local ok, brain = pcall(function() return NPCBrainData.Get(chr) end)
    if ok then return brain end
    return nil
end

local function bua_isAlive(chr)
    if not chr then return false end
    local ok, dead = pcall(function() return chr:isDead() end)
    if ok and dead then return false end
    ok, dead = pcall(function() return chr:isAlive() end)
    if ok and dead == false then return false end
    return true
end

local function bua_emptyWeaponSlot()
    return {bulletsLeft=0, magCount=0, ammoCount=0}
end

local function bua_copySlot(slot)
    if type(slot) ~= "table" then return slot end
    local ret = {}
    for k, v in pairs(slot) do ret[k] = v end
    return ret
end

local function bua_weaponNamed(slot)
    return type(slot) == "table" and slot.name and slot.name ~= "" and slot.name ~= "null" and slot.name ~= "Base.BareHands"
end

local function bua_slotCanShootOrReload(slot)
    if not bua_weaponNamed(slot) then return false end
    if tonumber(slot.bulletsLeft or 0) and tonumber(slot.bulletsLeft or 0) > 0 then return true end
    if tonumber(slot.magCount or 0) and tonumber(slot.magCount or 0) > 0 then return true end
    if tonumber(slot.ammoCount or 0) and tonumber(slot.ammoCount or 0) > 0 then return true end
    return false
end

local function bua_stripFireTasks(brain)
    if not brain or type(brain.tasks) ~= "table" then return false end

    local changed = false
    local clean = {}
    for _, task in ipairs(brain.tasks) do
        local action = task and task.action
        if action == "Shoot" or action == "Aim" or action == "Reload" then
            changed = true
        elseif task and (action == "Equip" or action == "Unequip") and (not task.itemPrimary or task.itemPrimary == "" or task.itemPrimary == "null") then
            changed = true
        elseif task then
            table.insert(clean, task)
        end
    end

    if changed then brain.tasks = clean end
    return changed
end

function NPCUtilityAIBridge.InitProgress(brain)
    if not brain then return nil end

    brain.ai = brain.ai or {}
    brain.ai.level = math.max(1, tonumber(brain.ai.level or brain.rbLevel or 1) or 1)
    brain.ai.xp = math.max(0, tonumber(brain.ai.xp or brain.rbXp or 0) or 0)
    brain.ai.xpNext = math.max(1, tonumber(brain.ai.xpNext or brain.rbXpNext or bua_xpNext(brain.ai.level)) or 1)
    brain.ai.skills = brain.ai.skills or brain.rbSkills or {}
    brain.ai.skillXp = brain.ai.skillXp or brain.rbSkillXp or {}

    for _, key in ipairs(bua_skillKeys) do
        brain.ai.skills[key] = bua_clamp(brain.ai.skills[key], 0, NPCUtilityAIBridge.Progression.maxSkill or 10)
        brain.ai.skillXp[key] = math.max(0, tonumber(brain.ai.skillXp[key] or 0) or 0)
    end

    brain.rbLevel = brain.ai.level
    brain.rbXp = brain.ai.xp
    brain.rbXpNext = brain.ai.xpNext
    brain.rbSkills = brain.ai.skills
    brain.rbSkillXp = brain.ai.skillXp

    return brain.ai.skills
end

function NPCUtilityAIBridge.SkillLevel(brain, skill)
    local skills = NPCUtilityAIBridge.InitProgress(brain)
    if not skills then return 0 end
    return tonumber(skills[skill or "teamwork"] or 0) or 0
end

function NPCUtilityAIBridge.SkillFactor(brain, skill)
    local maxSkill = NPCUtilityAIBridge.Progression.maxSkill or 10
    if maxSkill <= 0 then return 0 end
    return bua_clamp(NPCUtilityAIBridge.SkillLevel(brain, skill) / maxSkill, 0, 1)
end

function NPCUtilityAIBridge.AddXP(brain, skill, amount, reason)
    if not brain then return false end
    skill = skill or "teamwork"
    amount = math.max(0, tonumber(amount) or 0)
    amount = amount * ((NPCUtilityAIBridge.Progression and NPCUtilityAIBridge.Progression.xpMultiplier) or 1.0)
    if amount <= 0 then return false end

    local skills = NPCUtilityAIBridge.InitProgress(brain)
    if not skills[skill] then skill = "teamwork" end

    brain.ai.xp = (brain.ai.xp or 0) + amount
    brain.ai.skillXp[skill] = (brain.ai.skillXp[skill] or 0) + amount
    brain.ai.lastXpReason = reason
    brain.ai.lastXpAmount = amount
    brain.ai.lastXpSkill = skill
    brain.ai.lastXpAt = bua_nowHours()

    local changed = false
    while brain.ai.xp >= brain.ai.xpNext and brain.ai.level < (NPCUtilityAIBridge.Progression.maxLevel or 30) do
        brain.ai.xp = brain.ai.xp - brain.ai.xpNext
        brain.ai.level = brain.ai.level + 1
        brain.ai.xpNext = bua_xpNext(brain.ai.level)
        brain.ai.levelUps = (brain.ai.levelUps or 0) + 1
        changed = true
    end

    local current = skills[skill] or 0
    local need = bua_skillNeed(current)
    while brain.ai.skillXp[skill] >= need and current < (NPCUtilityAIBridge.Progression.maxSkill or 10) do
        brain.ai.skillXp[skill] = brain.ai.skillXp[skill] - need
        current = current + 1
        skills[skill] = current
        brain.ai.skillUps = (brain.ai.skillUps or 0) + 1
        changed = true
        need = bua_skillNeed(current)
    end

    brain.rbLevel = brain.ai.level
    brain.rbXp = brain.ai.xp
    brain.rbXpNext = brain.ai.xpNext
    brain.rbSkills = brain.ai.skills
    brain.rbSkillXp = brain.ai.skillXp

    return changed
end

function NPCUtilityAIBridge.AddRateLimitedXP(brain, key, skill, amount, cooldownHours, reason)
    if not brain then return false end
    brain.ai = brain.ai or {}
    brain.ai.xpCooldowns = brain.ai.xpCooldowns or {}
    key = key or skill or "generic"
    local now = bua_nowHours()
    if now - (brain.ai.xpCooldowns[key] or 0) < (cooldownHours or 0.01) then return false end
    brain.ai.xpCooldowns[key] = now
    return NPCUtilityAIBridge.AddXP(brain, skill, amount, reason)
end

function NPCUtilityAIBridge.IsPlayerGuardBrain(brain)
    if not brain then return false end
    return brain.mercenaryHired == true
        or brain.isPlayerGuard == true
        or brain.followPlayer == true
        or brain.guardPlayer == true
end

function NPCUtilityAIBridge.GetFireMode(brain)
    if not brain then return "fire_at_will" end

    local mode = brain.rbFireMode
    if not mode and brain.order then
        if type(brain.order) == "table" then
            mode = brain.order.fireMode
        elseif type(brain.order) == "string" then
            mode = brain.order
        end
    end

    mode = tostring(mode or "fire_at_will")

    if mode == "HoldFire" or mode == "hold_fire" or mode == "hold" or mode == "no_fire" then return "hold" end
    if mode == "MeleeOnly" or mode == "melee_only" then return "melee_only" end
    if mode == "Defensive" or mode == "ReturnFire" or mode == "return_fire" or mode == "returnfire" then return "return_fire" end
    if mode == "DangerClose" or mode == "danger_close" then return "danger_close" end
    if mode == "Suppress" or mode == "suppress" or mode == "suppressive_fire" then return "suppress" end
    if mode == "FireAtWill" or mode == "fire_at_will" or mode == "Auto" then return "fire_at_will" end

    return "fire_at_will"
end

function NPCUtilityAIBridge.IsPlayerGuardSuppressing(brain)
    if not NPCUtilityAIBridge.IsPlayerGuardBrain(brain) then return false end
    return NPCUtilityAIBridge.GetFireMode(brain) == "suppress"
end

function NPCUtilityAIBridge.IsSuppressedByPlayerGuard(brain)
    if not brain or not brain.ai then return false end
    if brain.ai.suppressedByPlayerGuard ~= true then return false end
    local untilMs = tonumber(brain.ai.suppressedUntilMs or 0) or 0
    if untilMs <= bua_nowMs() then
        brain.ai.suppressedByPlayerGuard = nil
        brain.ai.suppressedUntilMs = nil
        brain.ai.suppressionLevel = nil
        brain.ai.suppressedSourceId = nil
        return false
    end
    return true
end

function NPCUtilityAIBridge.ApplySuppressionFire(shooterBrain, target, targetBrain, dist)
    if not NPCUtilityAIBridge.IsPlayerGuardSuppressing(shooterBrain) then return false end
    if not targetBrain and target and NPCBrainData and NPCBrainData.Get then
        targetBrain = NPCBrainData.Get(target)
    end
    if not targetBrain then return false end
    if NPCUtilityAIBridge.IsPlayerGuardBrain(targetBrain) then return false end

    if NPCFactionBridge and NPCFactionBridge.IsEnabled and NPCFactionBridge.IsEnabled() and NPCFactionBridge.AreBrainsEnemies then
        local okEnemy, isEnemy = pcall(function() return NPCFactionBridge.AreBrainsEnemies(shooterBrain, targetBrain) end)
        if okEnemy and isEnemy == false then return false end
    elseif shooterBrain and targetBrain and shooterBrain.clan and targetBrain.clan and shooterBrain.clan == targetBrain.clan then
        return false
    end

    local maxDist = NPCUtilityAIBridge.Config.suppressDistance or 32
    dist = tonumber(dist or maxDist) or maxDist
    if dist > maxDist + 2 then return false end

    local nowMs = bua_nowMs()
    local baseSeconds = NPCUtilityAIBridge.Config.suppressionSeconds or 3.5
    local nearBonus = math.max(0, (maxDist - dist) / math.max(1, maxDist)) * 1.5
    local durationMs = math.floor((baseSeconds + nearBonus) * 1000)

    NPCUtilityAIBridge.Ensure(targetBrain)
    targetBrain.ai.suppressedByPlayerGuard = true
    targetBrain.ai.suppressedUntilMs = math.max(tonumber(targetBrain.ai.suppressedUntilMs or 0) or 0, nowMs + durationMs)
    targetBrain.ai.suppressedSourceId = shooterBrain and (shooterBrain.id or shooterBrain.uid or shooterBrain.persistentId) or targetBrain.ai.suppressedSourceId
    targetBrain.ai.suppressionLevel = bua_clamp((tonumber(targetBrain.ai.suppressionLevel or 0) or 0) + 0.35, 0, 1)
    targetBrain.ai.lastEnemyFireAt = bua_nowHours()
    targetBrain.ai.lastThreatAt = bua_nowHours()
    targetBrain.inBattle = true
    targetBrain.virtualBattle = true

    if shooterBrain and shooterBrain.debugCoords then
        targetBrain.radioThreat = {
            x = shooterBrain.debugCoords.x,
            y = shooterBrain.debugCoords.y,
            z = shooterBrain.debugCoords.z or 0,
            kind = "bandit",
            dist = dist,
            suppression = true
        }
    end

    if target and NPCBrainData and NPCBrainData.Update then
        pcall(function() NPCBrainData.Update(target, targetBrain) end)
    end
    return true
end

function NPCUtilityAIBridge.NormalizeBrainWeapons(brain)
    if not brain then return false end

    local changed = false
    brain.weapons = brain.weapons or {}

    for _, slot in ipairs({"primary", "secondary"}) do
        local weapon = brain.weapons[slot]
        if type(weapon) ~= "table" then
            if weapon and weapon ~= "" and weapon ~= "null" and weapon ~= "Base.BareHands" then
                brain.weapons[slot] = {name=weapon, bulletsLeft=0, magCount=0, ammoCount=0}
                changed = true
            elseif weapon ~= nil then
                brain.weapons[slot] = bua_emptyWeaponSlot()
                changed = true
            else
                brain.weapons[slot] = bua_emptyWeaponSlot()
            end
        else
            weapon.bulletsLeft = tonumber(weapon.bulletsLeft or 0) or 0
            weapon.magCount = tonumber(weapon.magCount or 0) or 0
            weapon.ammoCount = tonumber(weapon.ammoCount or 0) or 0
        end
    end

    if type(brain.weapons.melee) == "table" then
        brain.weapons.melee = brain.weapons.melee.name or "Base.BareHands"
        changed = true
    end

    if not brain.weapons.melee or brain.weapons.melee == "" or brain.weapons.melee == "null" then
        brain.weapons.melee = "Base.BareHands"
        changed = true
    end

    return changed
end

function NPCUtilityAIBridge.HasUsableFirearm(brain)
    if not brain then return false end
    NPCUtilityAIBridge.NormalizeBrainWeapons(brain)
    return bua_slotCanShootOrReload(brain.weapons.primary) or bua_slotCanShootOrReload(brain.weapons.secondary)
end

function NPCUtilityAIBridge.RestoreLockedWeapons(brain)
    if not brain or not brain.ai then return false end
    if not brain.ai.weaponLock then return false end

    brain.weapons = brain.weapons or {}
    local lock = brain.ai.weaponLock

    if lock.primary and not bua_weaponNamed(brain.weapons.primary) then
        brain.weapons.primary = bua_copySlot(lock.primary)
    end
    if lock.secondary and not bua_weaponNamed(brain.weapons.secondary) then
        brain.weapons.secondary = bua_copySlot(lock.secondary)
    end
    if lock.melee and (not brain.weapons.melee or brain.weapons.melee == "Base.BareHands") then
        brain.weapons.melee = lock.melee
    end

    brain.ai.weaponLock = nil
    return true
end

function NPCUtilityAIBridge.ApplyFireModeWeaponLocks(brain)
    if not brain then return false end

    NPCUtilityAIBridge.NormalizeBrainWeapons(brain)
    brain.ai = brain.ai or {}

    local mode = NPCUtilityAIBridge.GetFireMode(brain)
    brain.ai.fireMode = mode
    brain.rbFireMode = mode

    if mode == "hold" or mode == "melee_only" then
        brain.ai.weaponLock = brain.ai.weaponLock or {}
        if bua_weaponNamed(brain.weapons.primary) then
            brain.ai.weaponLock.primary = brain.ai.weaponLock.primary or bua_copySlot(brain.weapons.primary)
            brain.weapons.primary = bua_emptyWeaponSlot()
        end
        if bua_weaponNamed(brain.weapons.secondary) then
            brain.ai.weaponLock.secondary = brain.ai.weaponLock.secondary or bua_copySlot(brain.weapons.secondary)
            brain.weapons.secondary = bua_emptyWeaponSlot()
        end
        -- HoldFire and MeleeOnly suppress firearms only. Melee remains available so
        -- NPCs can still defend themselves at contact distance without breaking
        -- the player's no-shoot command.
        bua_stripFireTasks(brain)
        return true
    end

    return NPCUtilityAIBridge.RestoreLockedWeapons(brain)
end

function NPCUtilityAIBridge.CanShoot(brain)
    local mode = NPCUtilityAIBridge.GetFireMode(brain)
    return mode ~= "hold" and mode ~= "melee_only"
end

function NPCUtilityAIBridge.CanShootAtDistance(brain, dist)
    if not NPCUtilityAIBridge.CanShoot(brain) then return false end

    local mode = NPCUtilityAIBridge.GetFireMode(brain)
    dist = tonumber(dist or 9999) or 9999

    if NPCUtilityAIBridge.IsSuppressedByPlayerGuard(brain) and not NPCUtilityAIBridge.IsPlayerGuardBrain(brain) then
        return dist <= (NPCUtilityAIBridge.Config.suppressionReturnFireDistance or 8.0)
    end

    if mode == "return_fire" then
        local now = bua_nowHours()
        local last = brain and brain.ai and (brain.ai.lastDamagedAt or brain.ai.lastEnemyFireAt or brain.ai.lastThreatAt) or 0
        return (now - (last or 0)) * 3600 <= (NPCUtilityAIBridge.Config.returnFireSeconds or 8) or dist <= (NPCUtilityAIBridge.Config.defensiveDistance or 9)
    elseif mode == "danger_close" then
        return dist <= (NPCUtilityAIBridge.Config.dangerCloseDistance or 7)
    elseif mode == "suppress" then
        return dist <= (NPCUtilityAIBridge.Config.suppressDistance or 32)
    end

    return true
end

function NPCUtilityAIBridge.Ensure(brain, bandit)
    if not brain then return nil end

    brain.ai = brain.ai or {}
    brain.ai.profile = brain.ai.profile or {}
    brain.ai.needs = brain.ai.needs or {}
    brain.ai.stock = brain.ai.stock or {}

    NPCUtilityAIBridge.InitProgress(brain)
    NPCUtilityAIBridge.NormalizeBrainWeapons(brain)

    local p = brain.ai.profile
    p.fear = bua_clamp(p.fear or brain.fear or 0.18, 0, 1)
    p.morale = bua_clamp(p.morale or brain.morale or 0.62, 0, 1)
    p.aggression = bua_clamp(p.aggression or brain.aggression or (brain.hostile and 0.70 or 0.42), 0, 1)
    p.discipline = bua_clamp(p.discipline or 0.55 + (NPCUtilityAIBridge.SkillFactor(brain, "teamwork") * 0.25), 0, 1)

    local n = brain.ai.needs
    n.food = bua_clamp(n.food or 0.10, 0, 1)
    n.water = bua_clamp(n.water or 0.10, 0, 1)
    n.rest = bua_clamp(n.rest or 0.10, 0, 1)
    n.boredom = bua_clamp(n.boredom or 0.15, 0, 1)
    n.duty = bua_clamp(n.duty or 0.45, 0, 1)

    if bandit and not brain.ai.home then
        brain.ai.home = {
            x = bandit:getX(),
            y = bandit:getY(),
            z = bandit:getZ()
        }
    end

    brain.debug = brain.debug or {}
    brain.debug.utilityAI = true
    brain.debug.utilityVersion = NPCUtilityAIBridge.VERSION

    return brain.ai
end


local function bua_threatStillEnemy(brain, threat)
    if not threat then return false end
    local kind = threat.kind or threat.targetKind
    if kind == "player" and NPCFactionBridge and NPCFactionBridge.IsEnabled and NPCFactionBridge.IsEnabled() and NPCFactionBridge.CanBrainAttackPlayer then
        local player = nil
        if NPCPlayerClient and NPCPlayerClient.GetPlayerById then
            player = NPCPlayerClient.GetPlayerById(threat.id or threat.targetId or threat.eid)
        end
        if player then
            return NPCFactionBridge.CanBrainAttackPlayer(brain, player) == true
        end
    end
    return true
end

function NPCUtilityAIBridge.RememberThreat(brain, detection)
    if not brain or not detection then return end
    NPCUtilityAIBridge.Ensure(brain)

    brain.ai.lastThreat = {
        id = detection.id,
        x = detection.x,
        y = detection.y,
        z = detection.z,
        kind = detection.kind,
        dist = detection.dist,
        score = detection.score,
        seenAt = bua_nowMs()
    }
    brain.ai.lastThreatAt = bua_nowHours()

    if detection.kind and detection.kind ~= "zombie" and detection.kind ~= "zed" and detection.kind ~= "undead" then
        brain.inBattle = true
        brain.virtualBattle = true
        brain.ai.inHumanBattle = true
    end
end

function NPCUtilityAIBridge.GetRememberedThreat(brain)
    if not brain or not brain.ai or not brain.ai.lastThreat then return nil end

    local last = brain.ai.lastThreat
    if not bua_threatStillEnemy(brain, last) then
        brain.ai.lastThreat = nil
        brain.ai.lastThreatAt = nil
        brain.ai.inHumanBattle = false
        return nil
    end
    if bua_nowMs() - (last.seenAt or 0) > (NPCUtilityAIBridge.Config.memorySeconds or 120) * 1000 then
        brain.ai.lastThreat = nil
        return nil
    end

    return last
end

function NPCUtilityAIBridge.MarkDamaged(bandit, attacker)
    local brain = bua_getBrain(bandit)
    if not brain then return end

    NPCUtilityAIBridge.Ensure(brain, bandit)
    local now = bua_nowHours()
    brain.ai.lastDamagedAt = now
    brain.ai.profile.fear = bua_clamp((brain.ai.profile.fear or 0) + 0.18, 0, 1)
    brain.ai.profile.morale = bua_clamp((brain.ai.profile.morale or 0.5) - 0.06, 0, 1)

    if attacker and bua_isAlive(attacker) then
        local kind = "unknown"
        if instanceof(attacker, "IsoPlayer") then
            kind = "player"
        elseif attacker.getVariableBoolean and attacker:getVariableBoolean(NPC_UTILITY_LEGACY_KEYS.npcFlag) then
            kind = "bandit"
        elseif instanceof(attacker, "IsoZombie") then
            kind = "zombie"
        end
        NPCUtilityAIBridge.RememberThreat(brain, {
            id = NPCUtils and NPCUtils.GetCharacterID and NPCUtils.GetCharacterID(attacker) or nil,
            x = attacker:getX(), y = attacker:getY(), z = attacker:getZ(), kind = kind,
            dist = bua_dist(bandit:getX(), bandit:getY(), attacker:getX(), attacker:getY())
        })
    end
end

function NPCUtilityAIBridge.Update(bandit, brain, uTick, threat)
    if not brain then return nil end
    NPCUtilityAIBridge.Ensure(brain, bandit)

    local now = bua_nowHours()
    local ai = brain.ai
    local p = ai.profile
    local n = ai.needs

    if NPCUtilityAIBridge.Config.needsEnabled ~= false and now >= (ai.nextNeedsAt or 0) then
        local dt = math.max(0.001, now - (ai.lastNeedsAt or now))
        ai.lastNeedsAt = now
        ai.nextNeedsAt = now + (NPCUtilityAIBridge.Config.needsTickHours or 0.018)

        local activeThreat = threat or NPCUtilityAIBridge.GetRememberedThreat(brain)
        local combatMul = activeThreat and (NPCUtilityAIBridge.Config.combatNeedMultiplier or 1.8) or 1.0
        local restMul = activeThreat and (NPCUtilityAIBridge.Config.combatRestMultiplier or 2.1) or 1.0

        n.food = bua_clamp(n.food + dt * (NPCUtilityAIBridge.Config.foodRatePerHour or 0.030) * combatMul, 0, 1)
        n.water = bua_clamp(n.water + dt * (NPCUtilityAIBridge.Config.waterRatePerHour or 0.040) * combatMul, 0, 1)
        n.rest = bua_clamp(n.rest + dt * (NPCUtilityAIBridge.Config.restRatePerHour or 0.028) * restMul, 0, 1)
        n.boredom = bua_clamp(n.boredom + dt * (activeThreat and -0.05 or (NPCUtilityAIBridge.Config.boredomRatePerHour or 0.025)), 0, 1)
        n.duty = bua_clamp(n.duty + dt * (activeThreat and 0.12 or -0.01), 0, 1)
    end

    threat = threat or NPCUtilityAIBridge.GetRememberedThreat(brain)
    if threat then
        local closeAdd = threat.dist and math.max(0, 0.22 - (threat.dist * 0.012)) or 0.05
        if threat.kind == "zombie" then closeAdd = closeAdd * 0.75 end
        closeAdd = closeAdd * (NPCUtilityAIBridge.Config.threatFearMultiplier or 1.0)
        p.fear = bua_clamp(p.fear + closeAdd, 0, 1)
        p.morale = bua_clamp(p.morale - closeAdd * 0.25 * (NPCUtilityAIBridge.Config.threatMoraleLossMultiplier or 1.0), 0, 1)
        ai.lastThreatAt = now
        if threat.kind and threat.kind ~= "zombie" and threat.kind ~= "zed" and threat.kind ~= "undead" then
            brain.inBattle = true
            brain.virtualBattle = true
            ai.inHumanBattle = true
        end
    else
        p.fear = bua_clamp(p.fear - 0.015, 0, 1)
        p.morale = bua_clamp(p.morale + 0.006, 0, 1)
        if ai.inHumanBattle and now - (ai.lastThreatAt or 0) > 0.012 then
            brain.inBattle = false
            brain.virtualBattle = false
            ai.inHumanBattle = false
        end
    end

    NPCUtilityAIBridge.ApplyFireModeWeaponLocks(brain)

    brain.debug.fear = p.fear
    brain.debug.morale = p.morale
    brain.debug.aggression = p.aggression
    brain.debug.fireMode = NPCUtilityAIBridge.GetFireMode(brain)
    brain.debug.suppressedByPlayerGuard = NPCUtilityAIBridge.IsSuppressedByPlayerGuard(brain)

    return ai
end

function NPCUtilityAIBridge.EvaluateTacticalState(bandit, brain, threat, health)
    if not brain then return nil end
    NPCUtilityAIBridge.Update(bandit, brain, nil, threat)

    local ai = brain.ai
    local p = ai and ai.profile or {}
    health = bua_clamp(health or 1, 0, 1)
    threat = threat or NPCUtilityAIBridge.GetRememberedThreat(brain)

    if not threat then return nil end

    local dist = tonumber(threat.dist or 9999) or 9999

    if NPCUtilityAIBridge.IsSuppressedByPlayerGuard(brain) and not NPCUtilityAIBridge.IsPlayerGuardBrain(brain) then
        if dist <= (NPCUtilityAIBridge.Config.dangerCloseDistance or 7.0) then
            return "KeepDistance", "suppressed by player guard at close range"
        end
        return "TacticalCover", "suppressed by player guard"
    end

    local usableGun = NPCUtilityAIBridge.HasUsableFirearm(brain)
    local canShoot = NPCUtilityAIBridge.CanShootAtDistance(brain, dist)

    if health <= (NPCUtilityAIBridge.Config.criticalHealth or 0.22) then
        return "Flee", "critical health utility flee"
    end

    if health < (NPCUtilityAIBridge.Config.lowHealth or 0.36) and (p.fear or 0) > 0.45 then
        return "Flee", "low health utility flee"
    end

    if (p.fear or 0) >= (NPCUtilityAIBridge.Config.fearFlee or 0.78) and (p.morale or 0.5) < (NPCUtilityAIBridge.Config.moraleHold or 0.42) then
        return "Flee", "fear/morale utility flee"
    end

    if usableGun and canShoot and dist < (NPCUtilityAIBridge.Config.minimumGunDistance or 5.5) then
        return "KeepDistance", "utility preserve gun distance"
    end

    if not usableGun and brain.weapons and ((brain.weapons.primary and (brain.weapons.primary.magCount or 0) > 0) or (brain.weapons.secondary and (brain.weapons.secondary.magCount or 0) > 0)) then
        return "ReloadCover", "utility reload under threat"
    end

    if threat.kind ~= "zombie" and threat.kind ~= "zed" and threat.kind ~= "undead" then
        return nil
    end

    return nil
end

function NPCUtilityAIBridge.EvaluateAutonomyState(bandit, brain, orderName, programName)
    if not brain then return nil end
    NPCUtilityAIBridge.Update(bandit, brain)

    if brain.master or brain.rescueOwner then return nil end
    if brain.roadPatrol then return "PatrolArea", "road patrol autonomy" end

    local order = orderName and tostring(orderName):lower() or nil
    if order and order ~= "auto" and order ~= "free" and order ~= "freeroam" and order ~= "idle" then return nil end

    local now = bua_nowHours()
    brain.ai.lastOrderAt = brain.ai.lastOrderAt or now
    if now - brain.ai.lastOrderAt < (NPCUtilityAIBridge.Config.autonomyDelayHours or 0.035) then return nil end

    local n = brain.ai.needs or {}
    if (n.rest or 0) >= (NPCUtilityAIBridge.Config.restLimit or 0.82) then
        return "SleepRest", "utility autonomy rest"
    end
    if (n.food or 0) >= (NPCUtilityAIBridge.Config.hungerLimit or 0.74) or (n.water or 0) >= (NPCUtilityAIBridge.Config.waterLimit or 0.78) then
        return "EatDrink", "utility autonomy eat/drink"
    end
    if (n.boredom or 0) >= (NPCUtilityAIBridge.Config.boredomLimit or 0.65) then
        if NPCUtilityAIBridge.SkillFactor(brain, "scavenge") >= 0.15 or ZombRand(3) == 0 then
            return "LootArea", "utility autonomy search supplies"
        end
        return "PatrolArea", "utility autonomy patrol"
    end

    if programName == "Raider" or programName == NPC_UTILITY_LEGACY_KEYS.programNPC or programName == "Thief" or not programName then
        if ZombRand(5) == 0 then return "LootArea", "utility occasional search supplies" end
        return "PatrolArea", "utility roaming autonomy"
    end

    return nil
end

function NPCUtilityAIBridge.ConsumeNeed(brain, kind, amount)
    if not brain then return end
    NPCUtilityAIBridge.Ensure(brain)
    amount = tonumber(amount or 0.25) or 0.25

    local n = brain.ai.needs
    if kind == "food" then
        n.food = bua_clamp(n.food - amount, 0, 1)
        n.water = bua_clamp(n.water - amount * 0.5, 0, 1)
    elseif kind == "rest" then
        n.rest = bua_clamp(n.rest - amount, 0, 1)
        n.boredom = bua_clamp(n.boredom + amount * 0.2, 0, 1)
    elseif kind == "loot" then
        n.boredom = bua_clamp(n.boredom - amount, 0, 1)
        n.duty = bua_clamp(n.duty + amount * 0.2, 0, 1)
    elseif kind == "patrol" then
        n.boredom = bua_clamp(n.boredom - amount * 0.5, 0, 1)
        n.rest = bua_clamp(n.rest + amount * 0.1, 0, 1)
    end
end

function NPCUtilityAIBridge.OnTasksQueued(bandit, brain, tasks)
    if not brain or not tasks then return end
    NPCUtilityAIBridge.Ensure(brain, bandit)

    for _, task in ipairs(tasks) do
        local action = task and task.action
        if action == "Shoot" or action == "Aim" or action == "Hit" or action == "Shove" then
            NPCUtilityAIBridge.AddRateLimitedXP(brain, "combat", "combat", 2, 0.004, action)
        elseif action == "Bandage" then
            NPCUtilityAIBridge.AddRateLimitedXP(brain, "medicine", "medicine", 3, 0.010, action)
        elseif action == "LootItems" or action == "LootWeapons" or action == "TakeFromContainer" then
            NPCUtilityAIBridge.AddRateLimitedXP(brain, "scavenge", "scavenge", 3, 0.012, action)
            NPCUtilityAIBridge.ConsumeNeed(brain, "loot", 0.12)
            brain.ai.stock = brain.ai.stock or {}
            local category = "tools"
            if action == "LootWeapons" then
                category = "weapons"
            else
                local roll = ZombRand(5)
                if roll == 0 then category = "food"
                elseif roll == 1 then category = "medical"
                elseif roll == 2 then category = "ammo"
                elseif roll == 3 then category = "tools"
                else category = "supplies" end
            end
            brain.ai.stock[category] = (brain.ai.stock[category] or 0) + 1
            brain.rbStock = brain.ai.stock
        elseif action == "Move" or action == "GoTo" then
            NPCUtilityAIBridge.AddRateLimitedXP(brain, "fitness", "fitness", 1, 0.020, action)
        end
    end
end

function NPCUtilityAIBridge.OnMovementStuck(bandit, brain, task)
    if not brain then return end
    NPCUtilityAIBridge.Ensure(brain, bandit)

    local key = "none"
    if task and task.x and task.y then
        key = tostring(math.floor(task.x)) .. ":" .. tostring(math.floor(task.y)) .. ":" .. tostring(math.floor(task.z or 0))
    end

    brain.ai.stuck = brain.ai.stuck or {}
    if brain.ai.stuck.key ~= key then
        brain.ai.stuck.key = key
        brain.ai.stuck.count = 0
    end
    brain.ai.stuck.count = (brain.ai.stuck.count or 0) + 1
    brain.ai.stuck.lastAt = bua_nowHours()

    if brain.ai.stuck.count >= 3 then
        brain.fsm = brain.fsm or {}
        brain.fsm.patrol = nil
        brain.fsm.roadChain = nil
    end
end
