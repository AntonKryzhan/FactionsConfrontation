-- NPCWounded.lua
-- Lightweight wounded allies and evacuation layer for hired mercenaries.
-- Does not register new items; can optionally consume existing medical items.

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCLegacySettingsBridge"
require "NPCCommands/NPCMercenaryContract"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCWounded = NPCLegacyGlobalsBridge.InstallAlias("Wounded", NPCWounded, "NPCWounded")
NPCBrainData = NPCBrainData or {}
NPCWounded.Version = 2
local NPC_WOUNDED_LEGACY_KEYS = {
    npcFlag = NPCLegacyContractBridge.Key("FLAG")
}

local function bw_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        local ok, value = pcall(function() return NPCLegacySettingsBridge.GetBool(name, defaultValue == true) end)
        if ok and value ~= nil then return value == true end
    end
    return defaultValue == true
end

local function bw_num(name, defaultValue, minValue, maxValue)
    local value = defaultValue
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        local ok, got = pcall(function() return NPCLegacySettingsBridge.GetNumber(name, defaultValue, minValue, maxValue) end)
        if ok and got ~= nil then value = got end
    end
    value = tonumber(value) or tonumber(defaultValue) or 0
    if minValue ~= nil and value < minValue then value = minValue end
    if maxValue ~= nil and value > maxValue then value = maxValue end
    return value
end

local function bw_now()
    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then
            local ok, value = pcall(function() return gt:getWorldAgeHours() end)
            if ok and value then return tonumber(value) or 0 end
        end
    end
    return os.time and (os.time() / 3600) or 0
end

local function bw_playerId(player)
    if not player then return nil end
    if NPCUtils and NPCUtils.GetCharacterID then
        local ok, id = pcall(function() return NPCUtils.GetCharacterID(player) end)
        if ok and id ~= nil then return id end
    end
    if player.getOnlineID then
        local ok, id = pcall(function() return player:getOnlineID() end)
        if ok and id ~= nil then return id end
    end
    return nil
end

local function bw_playerName(player)
    if not player then return nil end
    if player.getUsername then
        local ok, value = pcall(function() return player:getUsername() end)
        if ok and value then return value end
    end
    if player.getDisplayName then
        local ok, value = pcall(function() return player:getDisplayName() end)
        if ok and value then return value end
    end
    return tostring(bw_playerId(player) or "player")
end

function NPCWounded.IsEnabled()
    return bw_bool("Wounded_Enabled", true)
end

function NPCWounded.DownChance()
    return bw_num("Wounded_DownChance", 65, 0, 100)
end

function NPCWounded.HealthThreshold()
    return bw_num("Wounded_HealthThreshold", 0.28, 0.01, 0.95)
end

function NPCWounded.DownedHealth()
    return bw_num("Wounded_DownedHealth", 0.22, 0.01, 0.95)
end

function NPCWounded.StabilizedHealth()
    return bw_num("Wounded_StabilizedHealth", 0.48, 0.05, 1.0)
end

function NPCWounded.BleedoutMinutes()
    return bw_num("Wounded_BleedoutMinutes", 45, 0, 1440)
end

function NPCWounded.RequireMedicalItem()
    return bw_bool("Wounded_RequireMedicalItem", false)
end

function NPCWounded.ConsumeMedicalItem()
    return bw_bool("Wounded_ConsumeMedicalItem", false)
end

function NPCWounded.EvacuationBaseRadius()
    return bw_num("Wounded_EvacuationBaseRadius", 2600, 100, 10000)
end

function NPCWounded.NowHours()
    return bw_now()
end

function NPCWounded.PlayerId(player)
    return bw_playerId(player)
end

function NPCWounded.IsHiredBy(brain, player)
    if type(brain) ~= "table" then return false end
    if brain.mercenaryHired ~= true then return false end
    local pid = bw_playerId(player)
    if not pid then return false end
    return brain.mercenaryHiredBy ~= nil and tostring(brain.mercenaryHiredBy) == tostring(pid)
end

function NPCWounded.IsEligibleBrain(brain, player)
    if not NPCWounded.IsEnabled() then return false end
    if type(brain) ~= "table" then return false end
    if brain.prisoner == true then return false end
    if brain.woundedAbandoned == true then return false end
    if player then return NPCWounded.IsHiredBy(brain, player) end
    return brain.mercenaryHired == true
end

function NPCWounded.IsDowned(brain)
    return type(brain) == "table" and brain.wounded == true and brain.woundedDowned == true and brain.woundedState == "downed"
end

function NPCWounded.IsWounded(brain)
    return type(brain) == "table" and brain.wounded == true
end

function NPCWounded.RollDown()
    local chance = NPCWounded.DownChance()
    if chance <= 0 then return false end
    if chance >= 100 then return true end
    local roll = ZombRand and ZombRand(10000) or math.random(0, 9999)
    return roll < math.floor(chance * 100)
end

function NPCWounded.MarkDowned(brain, player, x, y, z, reason)
    if type(brain) ~= "table" then return false end
    local now = bw_now()
    local bleedoutHours = NPCWounded.BleedoutMinutes() / 60
    local pid = bw_playerId(player) or brain.mercenaryHiredBy or brain.master

    brain.wounded = true
    brain.woundedDowned = true
    brain.woundedState = "downed"
    brain.woundedReason = reason or "heavy wound"
    brain.woundedAt = now
    brain.woundedLastStateAt = now
    brain.woundedNoDespawn = true
    brain.woundedKeepRuntime = true
    brain.noZombieTarget = true
    brain.noAggro = true
    brain.infection = 0
    brain.woundedExpiresAt = bleedoutHours > 0 and (now + bleedoutHours) or nil
    brain.woundedForPlayerId = pid
    brain.woundedForPlayerName = bw_playerName(player) or brain.mercenaryHiredByName
    brain.woundedX = tonumber(x) or brain.x
    brain.woundedY = tonumber(y) or brain.y
    brain.woundedZ = tonumber(z) or brain.z or 0
    brain.health = math.max(tonumber(brain.health) or 0, NPCWounded.DownedHealth())
    brain.maxHealth = math.max(tonumber(brain.maxHealth) or 0, brain.health or NPCWounded.DownedHealth())
    brain.hostile = false
    brain.tasks = {}
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
    brain.program = {name="CompanionGuard", stage="Prepare"}
    brain.order = brain.order or {}
    brain.order.name = "Hold"
    brain.order.master = pid
    brain.order.fireMode = "HoldFire"
    brain.order.anchor = {x=brain.woundedX, y=brain.woundedY, z=brain.woundedZ}
    brain.fireMode = "HoldFire"
    brain.rbFireMode = "HoldFire"
    brain.relationshipToPlayer = "wounded_ally"
    return true
end

function NPCWounded.MarkStabilized(brain, player, reason)
    if type(brain) ~= "table" then return false end
    local now = bw_now()
    local pid = bw_playerId(player) or brain.woundedForPlayerId or brain.mercenaryHiredBy or brain.master

    brain.wounded = true
    brain.woundedDowned = false
    brain.woundedStabilized = true
    brain.woundedState = "stabilized"
    brain.woundedStabilizedAt = now
    brain.woundedReason = reason or brain.woundedReason or "stabilized"
    brain.health = math.max(tonumber(brain.health) or 0, NPCWounded.StabilizedHealth())
    brain.hostile = false
    brain.tasks = {}
    brain.program = {name="Companion", stage="Prepare"}
    brain.order = brain.order or {}
    brain.order.name = "Follow"
    brain.order.master = pid
    brain.order.fireMode = brain.order.fireMode or "Defensive"
    brain.order.formation = brain.order.formation or "close"
    brain.order.followDistance = brain.order.followDistance or 3.0
    brain.fireMode = brain.order.fireMode
    brain.rbFireMode = brain.fireMode
    brain.relationshipToPlayer = "stabilized_ally"
    return true
end

function NPCWounded.MarkEvacuating(brain, player, anchor)
    if type(brain) ~= "table" then return false end
    NPCWounded.MarkStabilized(brain, player, "evacuating")
    brain.woundedState = "evacuating"
    brain.woundedEvacuating = true
    brain.woundedEvacuatedAt = nil
    brain.woundedEvacTarget = anchor
    brain.relationshipToPlayer = "evacuating_ally"

    if NPCMercenaryContract and NPCMercenaryContract.ApplyOrderToBrain then
        NPCMercenaryContract.ApplyOrderToBrain(brain, player, {
            orderName="Return",
            anchor=anchor,
            fireMode="Defensive",
            formation="close",
            followDistance=3.0
        })
    else
        brain.order = brain.order or {}
        brain.order.name = "Return"
        brain.order.master = bw_playerId(player) or brain.master
        brain.order.anchor = anchor
        brain.order.fireMode = "Defensive"
        brain.program = {name="Companion", stage="Prepare"}
    end
    brain.wounded = true
    brain.woundedState = "evacuating"
    brain.woundedEvacuating = true
    return true
end

function NPCWounded.MarkAbandoned(brain, player)
    if type(brain) ~= "table" then return false end
    brain.wounded = true
    brain.woundedDowned = false
    brain.woundedAbandoned = true
    brain.woundedState = "abandoned"
    brain.woundedAbandonedAt = bw_now()
    brain.woundedAbandonedBy = bw_playerId(player) or brain.master
    brain.relationshipToPlayer = "abandoned_wounded"
    brain.tasks = {}
    brain.order = brain.order or {}
    brain.order.name = "Hold"
    brain.order.fireMode = "HoldFire"
    brain.fireMode = "HoldFire"
    brain.rbFireMode = "HoldFire"
    return true
end

function NPCWounded.TryMarkDowned(bandit, attacker)
    if not (NPCWounded.IsEnabled() and bandit and bandit.getHealth) then return false end
    if not (bandit.getVariableBoolean and bandit:getVariableBoolean(NPC_WOUNDED_LEGACY_KEYS.npcFlag)) then return false end
    local brain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(bandit) or nil
    if not NPCWounded.IsEligibleBrain(brain, attacker) then return false end
    if NPCWounded.IsWounded(brain) then return false end

    local health = tonumber(bandit:getHealth()) or 1
    if health > NPCWounded.HealthThreshold() then return false end
    if not NPCWounded.RollDown() then return false end

    NPCWounded.MarkDowned(brain, attacker, bandit:getX(), bandit:getY(), bandit:getZ(), "combat wound")
    local minHealth = NPCWounded.DownedHealth()
    if health < minHealth then bandit:setHealth(minHealth) end
    if bandit.setTarget then bandit:setTarget(nil) end
    if bandit.setAttackedBy then pcall(function() bandit:setAttackedBy(nil) end) end
    if bandit.clearAggroList then pcall(function() bandit:clearAggroList() end) end
    if bandit.setUseless then bandit:setUseless(true) end
    if bandit.setReanim then pcall(function() bandit:setReanim(false) end) end
    local md = bandit.getModData and bandit:getModData() or nil
    if md then
        md.NPCWounded = true
        md.NPCWoundedState = "downed"
        md.NPCNoRuntimeCleanup = true
        md.NPCKeepCorpse = true
    end
    if NPCBrainData and NPCBrainData.Update then NPCBrainData.Update(bandit, brain) end
    return true, brain
end

function NPCWounded.ApplyLocalState(bandit, brain)
    if not (bandit and type(brain) == "table") then return end
    if NPCWounded.IsDowned(brain) then
        local minHealth = NPCWounded.DownedHealth()
        if bandit.getHealth and (tonumber(bandit:getHealth()) or 0) < minHealth then
            bandit:setHealth(minHealth)
        end
        brain.woundedNoDespawn = true
        brain.woundedKeepRuntime = true
        brain.noZombieTarget = true
        brain.noAggro = true
        brain.infection = 0
        if bandit.setTarget then bandit:setTarget(nil) end
        if bandit.setTargetSeenTime then bandit:setTargetSeenTime(0) end
        if bandit.setAttackedBy then pcall(function() bandit:setAttackedBy(nil) end) end
        if bandit.clearAggroList then pcall(function() bandit:clearAggroList() end) end
        if bandit.setUseless then bandit:setUseless(true) end
        if bandit.setReanim then pcall(function() bandit:setReanim(false) end) end
        if bandit.setWalkType then bandit:setWalkType("Limp") end
    elseif brain.woundedStabilized or brain.woundedEvacuating then
        local minHealth = NPCWounded.StabilizedHealth()
        if bandit.getHealth and (tonumber(bandit:getHealth()) or 0) < minHealth then
            bandit:setHealth(minHealth)
        end
        if bandit.setUseless then bandit:setUseless(false) end
        if bandit.setWalkType then bandit:setWalkType("Limp") end
    end
end

function NPCWounded.ApplyBleedout(bandit, brain)
    if not NPCWounded.IsDowned(brain) then return false end
    local minutes = NPCWounded.BleedoutMinutes()
    if minutes <= 0 then return false end
    if bandit and bandit.getHealth and bandit.setHealth then
        local h = tonumber(bandit:getHealth()) or NPCWounded.DownedHealth()
        bandit:setHealth(math.max(0.02, h - (0.002 / math.max(1, minutes))))
    end
    return true
end

function NPCWounded.PlanTasks(bandit, brain)
    if not NPCWounded.IsDowned(brain) then return nil end
    return {{action="Time", anim="Faint", lock=true, time=900, wounded=true, woundedDowned=true, noInterrupt=true}}
end
