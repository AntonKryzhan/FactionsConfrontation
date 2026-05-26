-- NPCStrategicAIBridge.lua
-- Shared virtual strategy helper for base assignment, logistics readiness and
-- abstract battles. It is intentionally data-only: no spawning/materialization
-- and no full ModData transmit from here.

require "NPCCore/NPCLegacyGlobalsBridge"

local legacyStrategicAI = NPCStrategicAIBridge
NPCStrategicAIBridge = NPCStrategicAIBridge or legacyStrategicAI or {}
NPCStrategicAIBridge.Version = 1
NPCStrategicAIBridge.BASE_ASSIGN_RADIUS = NPCStrategicAIBridge.BASE_ASSIGN_RADIUS or 5200
NPCStrategicAIBridge.BATTLE_SUPPLY_AMMO_PER_FIGHTER = NPCStrategicAIBridge.BATTLE_SUPPLY_AMMO_PER_FIGHTER or 0.35
NPCStrategicAIBridge.BATTLE_SUPPLY_MEDICAL_PER_LOSS = NPCStrategicAIBridge.BATTLE_SUPPLY_MEDICAL_PER_LOSS or 0.30
local function bsai_baseCampProvider()
    return NPCBaseCampServerBridge or NPCLegacyGlobalsBridge.Get("BaseCampSystem") or nil
end

local function bsai_factionEconomyProvider()
    return NPCFactionEconomyServerBridge or NPCLegacyGlobalsBridge.Get("FactionEconomy") or nil
end

local function bsai_baseSupplyProvider()
    return NPCBaseSupplyServerBridge or NPCLegacyGlobalsBridge.Get("BaseSupply") or nil
end

local function bsai_nowHours()
    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then
            local ok, value = pcall(function() return gt:getWorldAgeHours() end)
            if ok and value then return tonumber(value) or 0 end
        end
    end
    return 0
end

local function bsai_rand(maxValue)
    maxValue = tonumber(maxValue) or 0
    if maxValue <= 0 then return 0 end
    if ZombRand then return ZombRand(maxValue) end
    return math.random(0, maxValue - 1)
end

local function bsai_clamp(value, minValue, maxValue)
    value = tonumber(value) or 0
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function bsai_count(tbl)
    local count = 0
    if type(tbl) ~= "table" then return 0 end
    for _, _ in pairs(tbl) do count = count + 1 end
    return count
end

local function bsai_len(tbl)
    if type(tbl) ~= "table" then return 0 end
    local count = 0
    for _, _ in ipairs(tbl) do count = count + 1 end
    return count
end

local function bsai_dist(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return math.sqrt(dx * dx + dy * dy)
end

function NPCStrategicAIBridge.GetGroupSide(group)
    if type(group) ~= "table" then return nil end
    if group.convoyFaction == "green" or group.convoyFaction == "red" then return group.convoyFaction end
    if group.patrolColor == "green" or group.patrolColor == "red" then return group.patrolColor end
    if group.faction == "green" or group.faction == "red" then return group.faction end
    if group.hostile == false then return "green" end
    if group.hostile == true then return "red" end
    local first = type(group.members) == "table" and group.members[1] or nil
    if type(first) == "table" then
        if first.convoyFaction == "green" or first.convoyFaction == "red" then return first.convoyFaction end
        if first.patrolColor == "green" or first.patrolColor == "red" then return first.patrolColor end
        if first.faction == "green" or first.faction == "red" then return first.faction end
        if first.hostile == false then return "green" end
        if first.hostile == true then return "red" end
    end
    return nil
end

function NPCStrategicAIBridge.GetOtherSide(side)
    if side == "green" then return "red" end
    if side == "red" then return "green" end
    return nil
end

function NPCStrategicAIBridge.GetBaseCamps(gmd)
    local baseSystem = bsai_baseCampProvider()
    if baseSystem and baseSystem.GetBaseCamps then
        local ok, camps = pcall(function() return baseSystem.GetBaseCamps() end)
        if ok and type(camps) == "table" then return camps end
    end
    return gmd and gmd.BaseCamps or {}
end

function NPCStrategicAIBridge.GetBaseById(gmd, baseId)
    if not baseId then return nil end
    local camps = NPCStrategicAIBridge.GetBaseCamps(gmd)
    return camps and camps[tostring(baseId)] or nil
end

function NPCStrategicAIBridge.FindNearestBase(gmd, x, y, side, maxDist, allowAny)
    local best = nil
    local bestDist = tonumber(maxDist) or 999999
    for _, base in pairs(NPCStrategicAIBridge.GetBaseCamps(gmd) or {}) do
        if type(base) == "table" and base.x and base.y then
            local owner = base.owner or base.captureTeam
            if allowAny or not side or owner == side then
                local d = bsai_dist(x, y, base.x, base.y)
                if d < bestDist then
                    best = base
                    bestDist = d
                end
            end
        end
    end
    return best, bestDist
end

function NPCStrategicAIBridge.EnsureGroupBase(gmd, group, maxDist)
    if type(group) ~= "table" or group.activated then return false end
    if not group.x or not group.y then return false end

    local side = NPCStrategicAIBridge.GetGroupSide(group)
    local current = NPCStrategicAIBridge.GetBaseById(gmd, group.homeBaseId or group.missionOriginBaseId or group.originBaseId)
    if current and side and current.owner and current.owner ~= side then current = nil end

    local base = current
    local dist = nil
    if not base then
        base, dist = NPCStrategicAIBridge.FindNearestBase(gmd, group.x, group.y, side, maxDist or NPCStrategicAIBridge.BASE_ASSIGN_RADIUS, false)
    end
    if not base then
        base, dist = NPCStrategicAIBridge.FindNearestBase(gmd, group.x, group.y, nil, maxDist or NPCStrategicAIBridge.BASE_ASSIGN_RADIUS, true)
    end
    if not base then return false end

    local changed = tostring(group.homeBaseId or "") ~= tostring(base.id or "")
    group.homeBaseId = base.id
    group.homeBase = {x=base.x, y=base.y, z=base.z or 0}
    group.homeBaseOwner = base.owner
    group.homeBaseDist = math.floor((dist or bsai_dist(group.x, group.y, base.x, base.y)) + 0.5)
    group.baseAssignedAt = group.baseAssignedAt or bsai_nowHours()

    if type(group.members) == "table" then
        for _, member in pairs(group.members) do
            if type(member) == "table" then
                member.homeBaseId = member.homeBaseId or base.id
                member.homeBase = member.homeBase or {x=base.x, y=base.y, z=base.z or 0}
                member.homeBaseOwner = member.homeBaseOwner or base.owner
                member.baseAssignedAt = member.baseAssignedAt or bsai_nowHours()
            end
        end
    end

    return changed
end

function NPCStrategicAIBridge.EnsureAllGroupsAssigned(gmd)
    if not gmd or type(gmd.VirtualGroups) ~= "table" then return false end
    local changed = false
    for groupId, group in pairs(gmd.VirtualGroups) do
        if NPCStrategicAIBridge.EnsureGroupBase(gmd, group) then
            gmd.VirtualGroups[groupId] = group
            changed = true
        end
    end
    return changed
end

local function bsai_weaponRecordScore(record)
    if type(record) ~= "table" then return 0, 0, 0 end
    if not record.name or record.name == false then return 0, 0, 0 end

    local score = 0
    local ammo = 0
    local parts = 0
    local name = string.lower(tostring(record.name or ""))

    if string.find(name, "rifle", 1, true) or string.find(name, "shotgun", 1, true) or string.find(name, "smg", 1, true) then
        score = score + 24
    elseif string.find(name, "pistol", 1, true) or string.find(name, "revolver", 1, true) then
        score = score + 16
    else
        score = score + 10
    end

    local magCount = tonumber(record.magCount) or 0
    local bulletsLeft = tonumber(record.bulletsLeft) or 0
    local magSize = tonumber(record.magSize) or 0
    ammo = ammo + magCount + math.floor(bulletsLeft / math.max(1, math.max(6, magSize)))
    score = score + math.min(18, magCount * 2.5) + math.min(8, bulletsLeft * 0.12)

    local kit = record.baseSupplyKit
    if type(kit) == "table" then
        parts = tonumber(kit.attachmentCount) or bsai_len(kit.attachments)
        score = score + math.min(22, parts * 4)
        score = score + math.min(10, (tonumber(kit.condition) or 0) * 0.35)
    end

    return score, ammo, parts
end

local function bsai_memberWeaponScore(member)
    local score = 0
    local ammo = 0
    local parts = 0
    local weapons = member and member.weapons or nil
    if type(weapons) == "table" then
        local s, a, p = bsai_weaponRecordScore(weapons.primary)
        score = score + s
        ammo = ammo + a
        parts = parts + p
        s, a, p = bsai_weaponRecordScore(weapons.secondary)
        score = score + s * 0.75
        ammo = ammo + a
        parts = parts + p
        if type(weapons.melee) == "string" and weapons.melee ~= "" then score = score + 5 end
    end

    if type(member.baseGearWeaponParts) == "table" then
        parts = math.max(parts, bsai_len(member.baseGearWeaponParts))
        score = score + math.min(12, bsai_len(member.baseGearWeaponParts) * 2)
    end
    if type(member.baseGearWeaponKits) == "table" then
        for _, kit in pairs(member.baseGearWeaponKits) do
            if type(kit) == "table" then
                parts = parts + (tonumber(kit.attachmentCount) or bsai_len(kit.attachments))
                score = score + math.min(12, (tonumber(kit.attachmentCount) or bsai_len(kit.attachments)) * 2)
            end
        end
    end

    return score, ammo, parts
end

local function bsai_memberArmorScore(member)
    local score = 0
    if type(member.baseGearWear) == "table" then score = score + math.min(16, bsai_len(member.baseGearWear) * 4) end
    if member.baseGear and member.baseGear.armor then score = score + 10 end
    if member.baseGear and member.baseGear.clothing then score = score + 2 end
    return score
end

local function bsai_skillScore(member)
    local score = 0
    local skills = member and (member.skills or (member.ai and member.ai.skills)) or nil
    if type(skills) == "table" then
        for _, key in ipairs({"aiming", "reloading", "firearms", "strength", "fitness", "sneak", "maintenance", "medical"}) do
            score = score + math.min(10, tonumber(skills[key]) or 0)
        end
    end
    score = score + math.min(18, ((tonumber(member.accuracyBoost) or 1) - 1) * 12)
    return score
end

local function bsai_healthFactor(member)
    local health = tonumber(member and member.health) or tonumber(member and member.maxHealth) or 3.0
    local maxHealth = tonumber(member and member.maxHealth) or nil
    local ratio
    if maxHealth and maxHealth > 0 then
        ratio = health / maxHealth
    elseif health > 20 then
        ratio = health / 100
    else
        ratio = health / 4.0
    end
    return bsai_clamp(ratio, 0.25, 1.20)
end

local function bsai_needFactor(member)
    local needs = member and (member.needs or (member.ai and member.ai.needs)) or nil
    if type(needs) ~= "table" then return 1.0, 1.0 end
    local food = bsai_clamp(needs.food or needs.hunger or 0, 0, 1)
    local water = bsai_clamp(needs.water or needs.thirst or 0, 0, 1)
    local rest = bsai_clamp(needs.rest or needs.fatigue or 0, 0, 1)
    local supply = 1.0 - math.max(food, water) * 0.30
    local endurance = 1.0 - rest * 0.20
    return bsai_clamp(supply * endurance, 0.50, 1.05), math.max(food, water, rest)
end

function NPCStrategicAIBridge.EvaluateMember(member)
    if type(member) ~= "table" then return {power=0} end
    local weaponScore, ammoScore, partScore = bsai_memberWeaponScore(member)
    local armorScore = bsai_memberArmorScore(member)
    local skillScore = bsai_skillScore(member)
    local healthFactor = bsai_healthFactor(member)
    local needFactor, needPressure = bsai_needFactor(member)
    local morale = bsai_clamp(tonumber(member.morale or (member.ai and member.ai.morale)) or 0.55, 0, 1)
    local fear = bsai_clamp(tonumber(member.fear or (member.ai and member.ai.fear)) or 0.18, 0, 1)
    local discipline = bsai_clamp(tonumber(member.discipline) or 0.50, 0, 1)
    local aggression = bsai_clamp(tonumber(member.aggression) or 0.40, 0, 1)
    local moraleFactor = bsai_clamp(0.78 + morale * 0.32 + discipline * 0.18 + aggression * 0.10 - fear * 0.28, 0.45, 1.35)

    local raw = 8 + weaponScore + armorScore + skillScore * 0.55
    local power = raw * healthFactor * needFactor * moraleFactor
    return {
        power = math.max(1, power),
        weaponScore = weaponScore,
        armorScore = armorScore,
        skillScore = skillScore,
        ammoScore = ammoScore,
        partScore = partScore,
        healthFactor = healthFactor,
        needFactor = needFactor,
        needPressure = needPressure,
        moraleFactor = moraleFactor
    }
end

function NPCStrategicAIBridge.GetBaseReadiness(base, fighterCount)
    local stock = base and base.stock or {}
    fighterCount = math.max(1, tonumber(fighterCount) or 1)

    local foodWater = ((tonumber(stock.food) or 0) + (tonumber(stock.water) or 0)) / fighterCount
    local ammo = ((tonumber(stock.ammo) or 0) + (tonumber(stock.magazines) or 0) * 2) / fighterCount
    local armory = ((tonumber(stock.weapons) or 0) * 5 + (tonumber(stock.armor) or 0) * 3 + (tonumber(stock.weaponParts) or 0) * 2 + (tonumber(stock.maintenance) or 0)) / fighterCount
    local medical = (tonumber(stock.medical) or 0) / fighterCount

    local supplyFactor = bsai_clamp(0.72 + math.min(0.28, foodWater / 30), 0.58, 1.12)
    local ammoFactor = bsai_clamp(0.62 + math.min(0.42, ammo / 18), 0.45, 1.28)
    local armoryFactor = bsai_clamp(0.76 + math.min(0.36, armory / 25), 0.55, 1.30)
    local medicalFactor = bsai_clamp(0.86 + math.min(0.16, medical / 8), 0.70, 1.12)

    local status = base and base.economy and base.economy.status or nil
    if status == "critical" then
        supplyFactor = supplyFactor * 0.78
        ammoFactor = ammoFactor * 0.88
    elseif status == "low" then
        supplyFactor = supplyFactor * 0.90
    end

    return {
        supplyFactor = supplyFactor,
        ammoFactor = ammoFactor,
        armoryFactor = armoryFactor,
        medicalFactor = medicalFactor,
        foodWater = foodWater,
        ammo = ammo,
        armory = armory,
        medical = medical,
        status = status or "ok"
    }
end

function NPCStrategicAIBridge.EvaluateGroupCombatPower(gmd, group)
    if type(group) ~= "table" then return {power=0, count=0} end
    if gmd then NPCStrategicAIBridge.EnsureGroupBase(gmd, group) end

    local count = tonumber(group.count) or bsai_len(group.members)
    if count <= 0 then count = 1 end

    local total = 0
    local weaponScore = 0
    local armorScore = 0
    local ammoScore = 0
    local needPressure = 0
    local memberCount = 0

    if type(group.members) == "table" and bsai_count(group.members) > 0 then
        for _, member in pairs(group.members) do
            if type(member) == "table" then
                local eval = NPCStrategicAIBridge.EvaluateMember(member)
                total = total + eval.power
                weaponScore = weaponScore + (eval.weaponScore or 0)
                armorScore = armorScore + (eval.armorScore or 0)
                ammoScore = ammoScore + (eval.ammoScore or 0)
                needPressure = needPressure + (eval.needPressure or 0)
                memberCount = memberCount + 1
            end
        end
    end

    if memberCount <= 0 then
        total = count * 16
        memberCount = count
    end

    local base = gmd and NPCStrategicAIBridge.GetBaseById(gmd, group.homeBaseId or group.missionOriginBaseId or group.originBaseId) or nil
    local readiness = NPCStrategicAIBridge.GetBaseReadiness(base, count)
    local missionBonus = 1.0
    if group.economyMissionId then
        if group.missionType == "raid" then missionBonus = 1.08 end
        if group.missionType == "capture" or group.missionType == "retake" then missionBonus = 1.12 end
        if group.missionType == "reinforce" then missionBonus = 1.06 end
    end

    local baseFactor = readiness.supplyFactor * readiness.ammoFactor * readiness.armoryFactor * readiness.medicalFactor
    baseFactor = bsai_clamp(baseFactor, 0.25, 2.15)
    local power = total * baseFactor * missionBonus

    group.strategic = {
        version = NPCStrategicAIBridge.Version,
        power = math.floor(power + 0.5),
        rawPower = math.floor(total + 0.5),
        count = count,
        memberCount = memberCount,
        weaponScore = math.floor(weaponScore + 0.5),
        armorScore = math.floor(armorScore + 0.5),
        ammoScore = math.floor(ammoScore + 0.5),
        needPressure = math.floor((needPressure / math.max(1, memberCount)) * 100 + 0.5) / 100,
        readiness = readiness,
        homeBaseId = group.homeBaseId,
        updatedAt = bsai_nowHours()
    }
    group.strategicPower = group.strategic.power
    group.combatReadiness = math.floor(baseFactor * 100 + 0.5)
    group.supplyReadiness = math.floor(readiness.supplyFactor * 100 + 0.5)
    group.ammoReadiness = math.floor(readiness.ammoFactor * 100 + 0.5)
    group.armoryReadiness = math.floor(readiness.armoryFactor * 100 + 0.5)
    return group.strategic
end

function NPCStrategicAIBridge.ApplyBaseBattleConsumption(gmd, group, fighterCount, casualties)
    if not gmd or type(group) ~= "table" then return false end
    local base = NPCStrategicAIBridge.GetBaseById(gmd, group.homeBaseId or group.missionOriginBaseId or group.originBaseId)
    if not base or type(base.stock) ~= "table" then return false end
    fighterCount = math.max(1, tonumber(fighterCount) or tonumber(group.count) or 1)
    casualties = math.max(0, tonumber(casualties) or 0)

    base.stock.ammo = math.max(0, (tonumber(base.stock.ammo) or 0) - fighterCount * NPCStrategicAIBridge.BATTLE_SUPPLY_AMMO_PER_FIGHTER)
    base.stock.medical = math.max(0, (tonumber(base.stock.medical) or 0) - casualties * NPCStrategicAIBridge.BATTLE_SUPPLY_MEDICAL_PER_LOSS)
    base.stock.food = math.max(0, (tonumber(base.stock.food) or 0) - fighterCount * 0.05)
    base.stock.water = math.max(0, (tonumber(base.stock.water) or 0) - fighterCount * 0.06)

    local factionEconomy = bsai_factionEconomyProvider()
    if factionEconomy and factionEconomy.SyncBaseStockFields then
        factionEconomy.SyncBaseStockFields(base)
    end
    local baseSupply = bsai_baseSupplyProvider()
    if baseSupply and baseSupply.SyncBaseFields then
        baseSupply.SyncBaseFields(base)
    end
    local baseSystem = bsai_baseCampProvider()
    if baseSystem and baseSystem.SendBaseMarker then
        baseSystem.SendBaseMarker(base)
    end
    return true
end

function NPCStrategicAIBridge.ApplyBattleStress(group, casualties)
    if type(group) ~= "table" then return false end
    casualties = math.max(0, tonumber(casualties) or 0)
    for _, member in pairs(group.members or {}) do
        if type(member) == "table" then
            member.needs = member.needs or {}
            member.needs.food = bsai_clamp((tonumber(member.needs.food) or 0) + 0.025 + casualties * 0.015, 0, 1)
            member.needs.water = bsai_clamp((tonumber(member.needs.water) or 0) + 0.030 + casualties * 0.015, 0, 1)
            member.needs.rest = bsai_clamp((tonumber(member.needs.rest) or 0) + 0.020 + casualties * 0.010, 0, 1)
            member.morale = bsai_clamp((tonumber(member.morale) or 0.55) - casualties * 0.05, 0, 1)
            member.fear = bsai_clamp((tonumber(member.fear) or 0.18) + casualties * 0.04, 0, 1)
        end
    end
    return true
end

function NPCStrategicAIBridge.RollVirtualBattleLoss(gmd, defender, attacker)
    if type(defender) ~= "table" or type(attacker) ~= "table" then return 0 end
    local defenderCount = tonumber(defender.count) or bsai_len(defender.members)
    local attackerCount = tonumber(attacker.count) or bsai_len(attacker.members)
    if defenderCount <= 0 or attackerCount <= 0 then return 0 end

    local attackEval = NPCStrategicAIBridge.EvaluateGroupCombatPower(gmd, attacker)
    local defendEval = NPCStrategicAIBridge.EvaluateGroupCombatPower(gmd, defender)
    local atk = math.max(1, tonumber(attackEval.power) or 1)
    local def = math.max(1, tonumber(defendEval.power) or 1)
    local ratio = atk / math.max(1, atk + def)

    local readinessPenalty = 0
    if defendEval.readiness then
        if (defendEval.readiness.status == "critical") then readinessPenalty = readinessPenalty + 10 end
        if (tonumber(defendEval.readiness.ammoFactor) or 1) < 0.75 then readinessPenalty = readinessPenalty + 8 end
        if (tonumber(defendEval.readiness.supplyFactor) or 1) < 0.75 then readinessPenalty = readinessPenalty + 6 end
    end

    local chance = 8 + ratio * 62 + readinessPenalty
    if attacker.missionType == "raid" or attacker.missionType == "capture" or attacker.missionType == "retake" then chance = chance + 4 end
    if defender.inBattle then chance = chance + 2 end

    local losses = 0
    if bsai_rand(100) < chance then losses = losses + 1 end
    if defenderCount > 3 and (ratio > 0.58 or bsai_rand(100) < chance * 0.42) then losses = losses + 1 end
    if defenderCount > 7 and ratio > 0.67 and bsai_rand(100) < 35 then losses = losses + 1 end
    if losses > defenderCount then losses = defenderCount end

    NPCStrategicAIBridge.ApplyBaseBattleConsumption(gmd, attacker, attackerCount, 0)
    NPCStrategicAIBridge.ApplyBaseBattleConsumption(gmd, defender, defenderCount, losses)
    NPCStrategicAIBridge.ApplyBattleStress(attacker, 0)
    NPCStrategicAIBridge.ApplyBattleStress(defender, losses)

    defender.lastStrategicBattlePower = def
    attacker.lastStrategicBattlePower = atk
    defender.lastStrategicBattleRatio = math.floor(ratio * 100 + 0.5)
    attacker.lastStrategicBattleRatio = math.floor(ratio * 100 + 0.5)
    return losses
end

function NPCStrategicAIBridge.ResumeGroupState(group)
    if type(group) ~= "table" then return "roaming" end
    if group.economyMissionId then return "eco_" .. tostring(group.missionType or "mission") end
    if group.targetClass == "base_capture" then return "assaulting_base" end
    if group.roadPatrol then return group.hostile and "red_road_patrol" or "green_road_patrol" end
    if group.homeBaseId then return "base_patrol" end
    return "roaming"
end

function NPCStrategicAIBridge.BuildMarkerFields(marker, group)
    if type(marker) ~= "table" or type(group) ~= "table" then return marker end
    marker.homeBaseId = group.homeBaseId
    marker.homeBaseOwner = group.homeBaseOwner
    marker.strategicPower = group.strategicPower
    marker.combatReadiness = group.combatReadiness
    marker.supplyReadiness = group.supplyReadiness
    marker.ammoReadiness = group.ammoReadiness
    marker.armoryReadiness = group.armoryReadiness
    if type(group.strategic) == "table" then
        marker.needPressure = group.strategic.needPressure
        marker.weaponScore = group.strategic.weaponScore
        marker.armorScore = group.strategic.armorScore
        marker.ammoScore = group.strategic.ammoScore
    end
    return marker
end

print("[NPCStrategicAIBridge] Virtual base assignment, readiness and abstract battle scoring enabled")
