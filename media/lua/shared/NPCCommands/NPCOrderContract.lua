-- Neutral order contract for friendly NPC command state.
-- Compatibility facade: media/lua/shared/legacy NPCOrders.lua

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCRuntimeCacheBridge"
require "NPCCore/NPCLegacySettingsBridge"
require "NPCCore/NPCIdentityBridge"
require "NPCCore/NPCUtilityAIBridge"
require "NPCBehavior/NPCBrainDataBridge"
require "NPCCore/NPCEntityState"

NPCOrderContract = NPCOrderContract or {}

NPCOrderContract.FLAG_FOLLOW = 1
NPCOrderContract.FLAG_HOLD = 2
NPCOrderContract.FLAG_GUARD = 4
NPCOrderContract.FLAG_PATROL = 8
NPCOrderContract.FLAG_LOOT = 16
NPCOrderContract.FLAG_RETURN = 32
NPCOrderContract.FLAG_HOLD_FIRE = 64
NPCOrderContract.FLAG_DEFENSIVE_FIRE = 128
NPCOrderContract.FLAG_FIRE_AT_WILL = 256
NPCOrderContract.FLAG_MELEE_ONLY = 512
NPCOrderContract.FLAG_SILENT = 1024
NPCOrderContract.FLAG_LOOT_HOUSE = 2048
NPCOrderContract.FLAG_FLANK = 4096
NPCOrderContract.FLAG_ENCIRCLE = 8192
NPCOrderContract.FLAG_BACK_TO_BACK = 16384
NPCOrderContract.FLAG_TAKE_COVER = 32768
NPCOrderContract.FLAG_ADVANCE = 65536
NPCOrderContract.FLAG_FALL_BACK = 131072
NPCOrderContract.FLAG_WATCH_SECTOR = 262144

function NPCOrderContract.HasFlag(mask, flag)
    if NPCRuntimeCacheBridge and NPCRuntimeCacheBridge.MaskHas then
        return NPCRuntimeCacheBridge.MaskHas(mask, flag)
    end
    mask = tonumber(mask) or 0
    flag = tonumber(flag) or 0
    if flag <= 0 then return false end
    local div = math.floor(mask / flag)
    return (div % 2) >= 1
end

function NPCOrderContract.MakeOrderMask(order, fireMode, silent)
    local mask = 0
    order = tostring(order or "")
    fireMode = tostring(fireMode or "")
    if order == "FollowPlayer" or order == "follow" then mask = mask + NPCOrderContract.FLAG_FOLLOW end
    if order == "HoldPosition" or order == "hold" then mask = mask + NPCOrderContract.FLAG_HOLD end
    if order == "GuardArea" or order == "guard" then mask = mask + NPCOrderContract.FLAG_GUARD end
    if order == "PatrolArea" or order == "patrol" then mask = mask + NPCOrderContract.FLAG_PATROL end
    if order == "LootArea" or order == "loot" then mask = mask + NPCOrderContract.FLAG_LOOT end
    if order == "LootHouse" or order == "loot_house" or order == "search_house" then mask = mask + NPCOrderContract.FLAG_LOOT_HOUSE end
    if order == "Flank" or order == "flank" or order == "flank_point" then mask = mask + NPCOrderContract.FLAG_FLANK end
    if order == "Encircle" or order == "encircle" or order == "surround" then mask = mask + NPCOrderContract.FLAG_ENCIRCLE end
    if order == "BackToBack" or order == "back_to_back" or order == "all_around_defense" then mask = mask + NPCOrderContract.FLAG_BACK_TO_BACK end
    if order == "TakeCover" or order == "take_cover" then mask = mask + NPCOrderContract.FLAG_TAKE_COVER end
    if order == "Advance" or order == "advance" then mask = mask + NPCOrderContract.FLAG_ADVANCE end
    if order == "FallBack" or order == "fall_back" or order == "fallback" then mask = mask + NPCOrderContract.FLAG_FALL_BACK end
    if order == "WatchSector" or order == "watch_sector" then mask = mask + NPCOrderContract.FLAG_WATCH_SECTOR end
    if order == "ReturnToBase" or order == "return" then mask = mask + NPCOrderContract.FLAG_RETURN end
    if fireMode == "HoldFire" or fireMode == "hold" or fireMode == "hold_fire" then mask = mask + NPCOrderContract.FLAG_HOLD_FIRE end
    if fireMode == "Defensive" or fireMode == "defensive" or fireMode == "fire_if_attacked" or fireMode == "ReturnFire" or fireMode == "return_fire" then mask = mask + NPCOrderContract.FLAG_DEFENSIVE_FIRE end
    if fireMode == "FireAtWill" or fireMode == "free" or fireMode == "fire_at_will" then mask = mask + NPCOrderContract.FLAG_FIRE_AT_WILL end
    if fireMode == "MeleeOnly" or fireMode == "melee" or fireMode == "melee_only" then mask = mask + NPCOrderContract.FLAG_MELEE_ONLY end
    if silent == true or fireMode == "silent" then mask = mask + NPCOrderContract.FLAG_SILENT end
    return mask
end

NPCOrderContract.Version = 1

NPCOrderContract.Names = {
    Auto = "Auto",
    Follow = "Follow",
    Hold = "Hold",
    Guard = "Guard",
    Patrol = "Patrol",
    Loot = "Loot",
    LootHouse = "LootHouse",
    Flank = "Flank",
    Encircle = "Encircle",
    BackToBack = "BackToBack",
    TakeCover = "TakeCover",
    Advance = "Advance",
    FallBack = "FallBack",
    WatchSector = "WatchSector",
    Return = "Return"
}

NPCOrderContract.FireModes = {
    FireAtWill = "FireAtWill",
    Defensive = "Defensive",
    HoldFire = "HoldFire",
    MeleeOnly = "MeleeOnly",
    ReturnFire = "ReturnFire",
    DangerClose = "DangerClose",
    Suppress = "Suppress"
}

NPCOrderContract.DefensiveShootDistance = 8

if NPCLegacySettingsBridge and NPCLegacySettingsBridge.ApplyOrders then
    NPCLegacySettingsBridge.ApplyOrders(NPCOrderContract)
end

NPCOrderContract.Formations = {
    Close = "close",
    Ring = "ring",
    Wide = "wide",
    Line = "line",
    Wedge = "wedge"
}

function NPCOrderContract.Now()
    if NPCIdentityBridge and NPCIdentityBridge.GetWorldAgeHours then
        return NPCIdentityBridge.GetWorldAgeHours()
    end

    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then
            return gt:getWorldAgeHours()
        end
    end

    return 0
end

function NPCOrderContract.Ensure(brain)
    if not brain then return nil end

    if not brain.order then
        brain.order = {}
    elseif type(brain.order) == "string" then
        brain.order = {name=brain.order}
    end

    if not brain.order.name then brain.order.name = NPCOrderContract.Names.Auto end
    if not brain.order.source then brain.order.source = "system" end
    if not brain.order.issued then brain.order.issued = NPCOrderContract.Now() end
    if not brain.order.priority then brain.order.priority = 10 end
    if not brain.order.fireMode then brain.order.fireMode = NPCOrderContract.FireModes.FireAtWill end
    if not brain.order.formation then brain.order.formation = NPCOrderContract.Formations.Close end
    if not brain.order.anchor and brain.debugCoords then
        brain.order.anchor = {
            x=brain.debugCoords.x,
            y=brain.debugCoords.y,
            z=brain.debugCoords.z or 0
        }
    end

    if not brain.sim then brain.sim = {} end
    brain.sim.order = brain.order.name
    brain.sim.fireMode = brain.order.fireMode
    brain.sim.orderUpdated = brain.order.issued

    if not brain.debug then brain.debug = {} end
    brain.debug.order = brain.order.name
    brain.debug.fireMode = brain.order.fireMode

    return brain.order
end

function NPCOrderContract.Get(brain)
    if not brain then return nil end
    return NPCOrderContract.Ensure(brain)
end

function NPCOrderContract.GetName(brain)
    local order = NPCOrderContract.Get(brain)
    return order and order.name or NPCOrderContract.Names.Auto
end

function NPCOrderContract.GetFireMode(brain)
    local order = NPCOrderContract.Get(brain)

    -- Stage 442: once an NPC is hired, the player's fire-mode command is
    -- authoritative. Utility/autonomy may still advise normal NPCs, but it
    -- must not silently override HoldFire/Defensive/ReturnFire/etc for
    -- player-commanded mercenaries.
    if NPCOrderContract.IsPlayerCommandedMercenary and NPCOrderContract.IsPlayerCommandedMercenary(brain) then
        return NPCOrderContract.NormalizeFireMode(order and order.fireMode or NPCOrderContract.FireModes.FireAtWill)
    end

    if NPCUtilityAIBridge and NPCUtilityAIBridge.GetFireMode then
        local mode = NPCUtilityAIBridge.GetFireMode(brain)
        if mode == "hold" then return NPCOrderContract.FireModes.HoldFire end
        if mode == "melee_only" then return NPCOrderContract.FireModes.MeleeOnly end
        if mode == "return_fire" then return NPCOrderContract.FireModes.ReturnFire end
        if mode == "danger_close" then return NPCOrderContract.FireModes.DangerClose end
        if mode == "suppress" then return NPCOrderContract.FireModes.Suppress end
    end

    return order and order.fireMode or NPCOrderContract.FireModes.FireAtWill
end

function NPCOrderContract.ApplyPlayerCommandAuthority(brain, master, reason)
    if type(brain) ~= "table" then return brain end
    brain.commandAuthority = "player"
    brain.playerCommandAuthority = true
    brain.worldCommandDisabled = true
    brain.worldDirectorDisabled = true
    brain.livingWorldDisabled = true
    brain.autonomousWorldDisabled = true
    brain.commandAuthorityReason = reason or brain.commandAuthorityReason or "hired_mercenary"
    brain.master = master or brain.master or brain.mercenaryHiredBy
    brain.mercenary = true
    brain.mercenaryHired = true
    brain.relationshipToPlayer = "hired_bodyguard"
    brain.hostile = false
    brain.friendly = true
    brain.factionSide = "blue"
    brain.faction = "blue"
    brain.side = "blue"
    brain.patrolColor = "blue"
    brain.factionState = "hired_blue_bodyguard"
    local currentOrderName = type(brain.order) == "table" and tostring(brain.order.name or "") or ""
    if currentOrderName == "Hold" or currentOrderName == "Guard" then
        brain.program = {name="CompanionGuard", stage="Prepare"}
    else
        brain.program = {name="Companion", stage="Prepare"}
    end

    brain.roadPatrol = false
    brain.checkpointGuard = false
    brain.checkpointId = nil
    brain.baseOwnedRole = nil
    brain.homeBaseZoneType = nil
    brain.baseZoneType = nil
    brain.strategicActivityType = nil
    brain.strategicActivityState = nil
    brain.strategicActivityId = nil
    brain.strategicActivityTargetBaseId = nil
    brain.strategicActivityTargetGroupId = nil
    brain.economyMissionId = nil
    brain.targetBaseId = nil
    brain.targetClass = nil
    brain.battleEnemyGroupId = nil
    brain.enemyGroupId = nil
    brain.inBattle = false
    brain.virtualBattle = false

    brain.currentThreat = nil
    brain.lastThreat = nil
    brain.targetId = nil
    brain.targetKind = nil
    brain.target = nil
    brain.enemy = nil
    brain.combatTarget = nil
    if type(brain.fsm) == "table" then
        brain.fsm.targetId = nil
        brain.fsm.targetKind = nil
        brain.fsm.currentThreat = nil
        brain.fsm.lastThreat = nil
        brain.fsm.target = nil
    end
    return brain
end

function NPCOrderContract.IsPlayerCommandedMercenary(brain)
    if type(brain) ~= "table" then return false end
    if brain.commandAuthority == "player" or brain.playerCommandAuthority == true then return true end
    if brain.worldCommandDisabled == true and NPCOrderContract.IsHiredMercenary and NPCOrderContract.IsHiredMercenary(brain) then return true end
    return false
end

function NPCOrderContract.Set(brain, name, data)
    if not brain then return nil end

    data = data or {}

    local order = NPCOrderContract.Ensure(brain)
    order.name = name or NPCOrderContract.Names.Auto
    order.source = data.source or "player"
    order.issued = NPCOrderContract.Now()
    brain.ai = brain.ai or {}
    brain.ai.orderSequence = (tonumber(brain.ai.orderSequence) or 0) + 1
    order.sequence = brain.ai.orderSequence
    order.priority = data.priority or order.priority or 10

    if data.master then order.master = data.master end
    if data.commandAuthority == "player" or data.playerCommandAuthority == true or data.playerCommand == true then
        order.commandAuthority = "player"
        order.playerCommand = true
        order.source = "player"
        order.playerCommandMode = data.playerCommandMode or order.playerCommandMode or "direct"
        NPCOrderContract.ApplyPlayerCommandAuthority(brain, data.master, data.commandAuthorityReason or data.interruptReason or "player_order")
    end
    if data.anchor then
        order.anchor = {
            x=tonumber(data.anchor.x),
            y=tonumber(data.anchor.y),
            z=tonumber(data.anchor.z) or 0,
            facingAngle=tonumber(data.anchor.facingAngle or data.facingAngle)
        }
    end

    if data.followDistance then order.followDistance = tonumber(data.followDistance) end
    if data.formation then order.formation = data.formation end
    if data.fireMode then order.fireMode = data.fireMode end
    if data.tactical then order.tactical = data.tactical end
    if data.note then order.note = data.note end
    if data.sticky == true then
        order.sticky = true
        order.stickySequence = order.sequence
        order.stickyReason = data.stickyReason or data.interruptReason or "player_order"
    elseif data.sticky == false then
        order.sticky = nil
        order.stickySequence = nil
        order.stickyReason = nil
    end
    if data.strict == true then
        order.strict = true
        order.strictSequence = order.sequence
        order.strictReason = data.strictReason or data.stickyReason or data.interruptReason or "player_order"
    elseif data.strict == false then
        order.strict = nil
        order.strictSequence = nil
        order.strictReason = nil
    end
    if type(data.leash) == "table" then
        order.leash = {
            follow=tonumber(data.leash.follow),
            guard=tonumber(data.leash.guard),
            hold=tonumber(data.leash.hold),
            combat=tonumber(data.leash.combat)
        }
    end
    if data.immediateReapply == true then
        local seconds = tonumber(data.immediateReapplySeconds) or 3
        if seconds < 0.5 then seconds = 0.5 end
        if seconds > 6 then seconds = 6 end
        order.immediateReapply = true
        order.immediateReapplySequence = order.sequence
        order.immediateReapplyUntil = order.issued + (seconds / 3600)
        order.immediateReapplyReason = data.immediateReapplyReason or data.interruptReason or "player_order"
    elseif data.immediateReapply == false then
        order.immediateReapply = nil
        order.immediateReapplySequence = nil
        order.immediateReapplyUntil = nil
        order.immediateReapplyReason = nil
    end
    if data.interrupt == true then
        local interruptSeconds = tonumber(data.interruptSeconds) or 8
        if interruptSeconds < 1 then interruptSeconds = 1 end
        if interruptSeconds > 30 then interruptSeconds = 30 end
        order.interrupt = true
        order.interruptIssued = order.issued
        order.interruptUntil = order.issued + (interruptSeconds / 3600)
        order.interruptReason = data.interruptReason or "player_order"
    end

    if not order.fireMode then order.fireMode = NPCOrderContract.FireModes.FireAtWill end

    if not brain.sim then brain.sim = {} end
    brain.sim.order = order.name
    brain.sim.fireMode = order.fireMode
    brain.sim.formation = order.formation
    brain.sim.orderUpdated = order.issued

    if brain.ai then
        brain.ai.lastOrderAt = order.issued
        brain.ai.lastManualOrder = order.name
    end

    if not brain.debug then brain.debug = {} end
    brain.debug.order = order.name
    brain.debug.fireMode = order.fireMode
    brain.debug.formation = order.formation

    return order
end

function NPCOrderContract.SetFireMode(brain, fireMode, data)
    data = data or {}
    data.fireMode = fireMode or NPCOrderContract.FireModes.FireAtWill

    if brain and NPCUtilityAIBridge and NPCUtilityAIBridge.GetFireMode then
        brain.rbFireMode = data.fireMode
    end

    local order = NPCOrderContract.Ensure(brain)
    return NPCOrderContract.Set(brain, order.name or NPCOrderContract.Names.Auto, data)
end

NPCOrderContract.SetForNPC = function(bandit, name, data)
    if not (bandit and NPCBrainDataBridge) then return nil end

    local brain = NPCBrainDataBridge.Get(bandit)
    if not brain then return nil end

    data = data or {}
    local order = NPCOrderContract.Set(brain, name, data)

    if name == NPCOrderContract.Names.Follow then
        if NPCEntityState and NPCEntityState.ForceStationary then NPCEntityState.ForceStationary(bandit, false) end
        if NPCEntityState and NPCEntityState.SetProgram then NPCEntityState.SetProgram(bandit, "Companion", {}) end
    elseif name == NPCOrderContract.Names.Hold or name == NPCOrderContract.Names.Guard then
        if NPCEntityState and NPCEntityState.SetProgram then NPCEntityState.SetProgram(bandit, "CompanionGuard", {}) end
    elseif NPCOrderContract.IsTacticalPointOrder and NPCOrderContract.IsTacticalPointOrder(name) then
        if NPCEntityState and NPCEntityState.ForceStationary then NPCEntityState.ForceStationary(bandit, false) end
        if NPCEntityState and NPCEntityState.SetProgram then NPCEntityState.SetProgram(bandit, "Companion", {}) end
    end

    NPCBrainDataBridge.Update(bandit, brain)
    return brain, order
end


function NPCOrderContract.IsTacticalPointOrderName(name)
    name = tostring(name or "")
    return name == NPCOrderContract.Names.Flank
        or name == NPCOrderContract.Names.Encircle
        or name == NPCOrderContract.Names.BackToBack
        or name == NPCOrderContract.Names.TakeCover
        or name == NPCOrderContract.Names.Advance
        or name == NPCOrderContract.Names.FallBack
        or name == NPCOrderContract.Names.WatchSector
end

function NPCOrderContract.IsTacticalPointOrder(value)
    if type(value) == "table" then value = value.name end
    return NPCOrderContract.IsTacticalPointOrderName(value)
end

function NPCOrderContract.IsFollow(brain)
    return NPCOrderContract.GetName(brain) == NPCOrderContract.Names.Follow
end

function NPCOrderContract.IsHold(brain)
    return NPCOrderContract.GetName(brain) == NPCOrderContract.Names.Hold
end

function NPCOrderContract.IsGuard(brain)
    return NPCOrderContract.GetName(brain) == NPCOrderContract.Names.Guard
end

function NPCOrderContract.IsStationary(brain)
    local name = NPCOrderContract.GetName(brain)
    return name == NPCOrderContract.Names.Hold or name == NPCOrderContract.Names.Guard
end

function NPCOrderContract.GetAnchor(brain, bandit)
    local order = NPCOrderContract.Get(brain)
    if order and order.anchor and order.anchor.x and order.anchor.y then
        return tonumber(order.anchor.x), tonumber(order.anchor.y), tonumber(order.anchor.z) or 0
    end

    if bandit then
        return bandit:getX(), bandit:getY(), bandit:getZ()
    end

    return nil
end

NPCOrderContract.SetAnchorFromNPC = function(brain, bandit)
    if not (brain and bandit) then return end

    local order = NPCOrderContract.Ensure(brain)
    order.anchor = {x=bandit:getX(), y=bandit:getY(), z=bandit:getZ()}
end

NPCOrderContract[NPCLegacyContractBridge.Member("setFor")] = NPCOrderContract.SetForNPC
NPCOrderContract[NPCLegacyContractBridge.Member("setAnchorFrom")] = NPCOrderContract.SetAnchorFromNPC

function NPCOrderContract.IsHiredMercenary(brain)
    if not brain then return false end
    return brain.mercenaryHired == true
        or brain.isPlayerGuard == true
        or brain.relationshipToPlayer == "hired_bodyguard"
        or brain.factionState == "hired_blue_bodyguard"
end

function NPCOrderContract.IsStrictHoldFire(brain)
    if not NPCOrderContract.IsHiredMercenary(brain) then return false end
    local fireMode = NPCOrderContract.GetFireMode(brain)
    return fireMode == NPCOrderContract.FireModes.HoldFire
end

function NPCOrderContract.NormalizeFireMode(fireMode)
    fireMode = tostring(fireMode or "")
    if fireMode == "hold" or fireMode == "HoldFire" or fireMode == "hold_fire" or fireMode == "no_fire" then return NPCOrderContract.FireModes.HoldFire end
    if fireMode == "melee_only" or fireMode == "MeleeOnly" or fireMode == "melee" then return NPCOrderContract.FireModes.MeleeOnly end
    if fireMode == "return_fire" or fireMode == "returnfire" or fireMode == "ReturnFire" then return NPCOrderContract.FireModes.ReturnFire end
    if fireMode == "defensive" or fireMode == "Defensive" or fireMode == "fire_if_attacked" then return NPCOrderContract.FireModes.Defensive end
    if fireMode == "danger_close" or fireMode == "DangerClose" then return NPCOrderContract.FireModes.DangerClose end
    if fireMode == "suppress" or fireMode == "Suppress" or fireMode == "suppressive_fire" then return NPCOrderContract.FireModes.Suppress end
    if fireMode == "fire_at_will" or fireMode == "FireAtWill" or fireMode == "Auto" or fireMode == "" then return NPCOrderContract.FireModes.FireAtWill end
    return fireMode
end

function NPCOrderContract.IsRecentlyProvoked(brain, seconds)
    if type(brain) ~= "table" or type(brain.ai) ~= "table" then return false end
    local now = NPCOrderContract.Now()
    seconds = tonumber(seconds) or 8
    local last = tonumber(brain.ai.lastDamagedAt or 0) or 0
    local enemyFire = tonumber(brain.ai.lastEnemyFireAt or 0) or 0
    local closeThreat = tonumber(brain.ai.lastCloseThreatAt or 0) or 0
    local newest = math.max(last, enemyFire, closeThreat)
    if newest <= 0 or now < newest then return false end
    return (now - newest) * 3600 <= seconds
end

function NPCOrderContract.GetFireDisciplineScanRadius(brain)
    if not NPCOrderContract.IsHiredMercenary(brain) then return nil end
    local fireMode = NPCOrderContract.NormalizeFireMode(NPCOrderContract.GetFireMode(brain))
    local strictRange = NPCOrderContract.GetStrictCombatRange(brain)
    local radius = nil
    if fireMode == NPCOrderContract.FireModes.HoldFire then
        radius = 1.65
    elseif fireMode == NPCOrderContract.FireModes.MeleeOnly then
        radius = 2.35
    elseif fireMode == NPCOrderContract.FireModes.ReturnFire then
        radius = NPCOrderContract.IsRecentlyProvoked(brain, 8) and 8.0 or 3.5
    elseif fireMode == NPCOrderContract.FireModes.Defensive then
        radius = 8.0
    elseif fireMode == NPCOrderContract.FireModes.DangerClose then
        radius = 7.0
    elseif fireMode == NPCOrderContract.FireModes.Suppress then
        radius = 24.0
    end
    if strictRange and radius then return math.min(radius, strictRange) end
    return radius or strictRange
end

function NPCOrderContract.CanEngageAtDistance(brain, dist, mode)
    if not NPCOrderContract.IsHiredMercenary(brain) then return true end
    dist = tonumber(dist or 9999) or 9999
    mode = NPCOrderContract.NormalizeFireMode(mode or NPCOrderContract.GetFireMode(brain))
    local strictRange = NPCOrderContract.GetStrictCombatRange(brain)
    if strictRange and dist > strictRange then return false end
    if mode == NPCOrderContract.FireModes.HoldFire then return dist <= 1.35 end
    if mode == NPCOrderContract.FireModes.MeleeOnly then return dist <= 2.35 end
    if mode == NPCOrderContract.FireModes.ReturnFire then
        if NPCOrderContract.IsRecentlyProvoked(brain, 8) then return dist <= 8.0 end
        return dist <= 3.5
    end
    if mode == NPCOrderContract.FireModes.Defensive then return dist <= 8.0 end
    if mode == NPCOrderContract.FireModes.DangerClose then return dist <= 7.0 end
    if mode == NPCOrderContract.FireModes.Suppress then return dist <= 24.0 end
    return true
end

function NPCOrderContract.AllowsChaseAtDistance(brain, dist, mode)
    if not NPCOrderContract.IsHiredMercenary(brain) then return true end
    dist = tonumber(dist or 9999) or 9999
    mode = NPCOrderContract.NormalizeFireMode(mode or NPCOrderContract.GetFireMode(brain))
    if mode == NPCOrderContract.FireModes.HoldFire then return dist <= 1.05 end
    if mode == NPCOrderContract.FireModes.MeleeOnly then return dist <= 1.8 end
    if mode == NPCOrderContract.FireModes.ReturnFire then return dist <= 2.0 end
    if mode == NPCOrderContract.FireModes.Defensive then return dist <= 2.5 end
    if mode == NPCOrderContract.FireModes.Suppress then return dist <= 2.0 end
    if mode == NPCOrderContract.FireModes.DangerClose then return dist <= 5.0 end
    return true
end

function NPCOrderContract.IsFireModeCombatTaskAllowed(brain, task, dist, mode)
    if not NPCOrderContract.IsHiredMercenary(brain) then return true end
    if type(task) ~= "table" then return true end

    local action = tostring(task.action or "")
    local directorState = tostring(task.directorState or task.state or "")
    local combatLike = task.combatMove == true
        or task.meleeApproach == true
        or task.targetId ~= nil
        or task.targetKind ~= nil
        or action == "Shoot"
        or action == "Aim"
        or action == "Hit"
        or action == "Shove"
        or action == "Reload"
        or directorState == "SearchEnemy"
        or directorState == "MeleeFallback"
        or directorState == "SuppressEnemy"
        or directorState == "CombatMemory"

    if not combatLike then return true end

    dist = tonumber(dist or 9999) or 9999
    mode = NPCOrderContract.NormalizeFireMode(mode or NPCOrderContract.GetFireMode(brain))

    if mode == NPCOrderContract.FireModes.HoldFire then
        if action == "Shoot" or action == "Aim" or action == "Reload" then return false end
        if action == "Hit" or action == "Shove" then return dist <= 1.35 end
        return dist <= 1.05
    end

    if mode == NPCOrderContract.FireModes.MeleeOnly then
        if action == "Shoot" or action == "Aim" or action == "Reload" then return false end
        if action == "Hit" or action == "Shove" then return dist <= 2.35 end
        return dist <= 1.8
    end

    if mode == NPCOrderContract.FireModes.ReturnFire then
        if action == "Shoot" or action == "Aim" or action == "Reload" then
            return NPCOrderContract.CanEngageAtDistance(brain, dist, mode) == true
        end
        return NPCOrderContract.AllowsChaseAtDistance(brain, dist, mode) == true
    end

    if mode == NPCOrderContract.FireModes.Defensive then
        if action == "Shoot" or action == "Aim" or action == "Reload" then
            return NPCOrderContract.CanEngageAtDistance(brain, dist, mode) == true
        end
        return NPCOrderContract.AllowsChaseAtDistance(brain, dist, mode) == true
    end

    if mode == NPCOrderContract.FireModes.Suppress then
        -- Suppression means fire from command position; do not convert it into
        -- melee rush/chase when firing is not currently possible.
        if action == "Hit" or action == "Shove" or task.meleeApproach == true or directorState == "MeleeFallback" then return false end
        if action == "Move" or action == "GoTo" then return false end
        return NPCOrderContract.CanEngageAtDistance(brain, dist, mode) == true
    end

    if mode == NPCOrderContract.FireModes.DangerClose then
        return NPCOrderContract.CanEngageAtDistance(brain, dist, mode) == true
    end

    return true
end

function NPCOrderContract.IsManualInterruptActive(brain)
    if not NPCOrderContract.IsHiredMercenary(brain) then return false end
    local order = NPCOrderContract.Get(brain)
    if type(order) ~= "table" or order.interrupt ~= true then return false end

    local now = NPCOrderContract.Now()
    local untilHour = tonumber(order.interruptUntil or order.forceUntil)
    if untilHour and untilHour > now then return true end

    local issued = tonumber(order.interruptIssued or order.issued)
    if issued and now >= issued and now - issued < (8 / 3600) then return true end
    return false
end
function NPCOrderContract.NormalizeOrderName(name)
    name = tostring(name or "")
    if name == "Follow" or name == "follow" or name == "FollowPlayer" then return "Follow" end
    if name == "Hold" or name == "hold" or name == "HoldPosition" then return "Hold" end
    if name == "Guard" or name == "guard" or name == "GuardArea" or name == "GuardPlayer" then return "Guard" end
    if name == "Patrol" or name == "patrol" or name == "PatrolArea" then return "Patrol" end
    if name == "Loot" or name == "loot" or name == "LootArea" then return "Loot" end
    if name == "LootHouse" or name == "loot_house" or name == "search_house" then return "LootHouse" end
    if name == "LootBodies" or name == "LootBodiesGear" or name == "LootBodiesClothing" or name == "LootBodiesWeapons" or name == "LootBodiesAmmo" or name == "LootBodiesMedical" or name == "LootBodiesSupplies" then return name end
    if name == "RearmHere" or name == "rearm" or name == "rearm_here" then return "RearmHere" end
    if name == "Flank" or name == "flank" or name == "flank_point" then return "Flank" end
    if name == "Encircle" or name == "encircle" or name == "surround" then return "Encircle" end
    if name == "BackToBack" or name == "back_to_back" or name == "all_around_defense" then return "BackToBack" end
    if name == "TakeCover" or name == "take_cover" then return "TakeCover" end
    if name == "Advance" or name == "advance" then return "Advance" end
    if name == "FallBack" or name == "fall_back" or name == "fallback" then return "FallBack" end
    if name == "WatchSector" or name == "watch_sector" then return "WatchSector" end
    if name == "Return" or name == "ReturnToBase" or name == "return" then return "Return" end
    return name
end

function NPCOrderContract.IsStrictPlayerOrderName(name)
    name = NPCOrderContract.NormalizeOrderName(name)
    return name == "Follow" or name == "Hold" or name == "Guard" or name == "FallBack" or name == "Return"
end

function NPCOrderContract.IsPlayerCommandOrderName(name)
    name = NPCOrderContract.NormalizeOrderName(name)
    return name == "Follow"
        or name == "Hold"
        or name == "Guard"
        or name == "Patrol"
        or name == "Loot"
        or name == "LootHouse"
        or name == "LootBodies"
        or name == "LootBodiesGear"
        or name == "LootBodiesClothing"
        or name == "LootBodiesWeapons"
        or name == "LootBodiesAmmo"
        or name == "LootBodiesMedical"
        or name == "LootBodiesSupplies"
        or name == "RearmHere"
        or name == "Flank"
        or name == "Encircle"
        or name == "BackToBack"
        or name == "TakeCover"
        or name == "Advance"
        or name == "FallBack"
        or name == "WatchSector"
        or name == "Return"
end

function NPCOrderContract.IsPlayerCommandedOrderActive(brain)
    if not NPCOrderContract.IsPlayerCommandedMercenary(brain) then return false end
    local order = NPCOrderContract.Get(brain)
    if type(order) ~= "table" then return false end
    if order.source ~= "player" and order.commandAuthority ~= "player" and order.playerCommand ~= true then return false end
    return NPCOrderContract.IsPlayerCommandOrderName(order.name)
end

function NPCOrderContract.IsPlayerCommandTacticalOrderName(name)
    name = NPCOrderContract.NormalizeOrderName(name)
    return name == "Flank"
        or name == "Encircle"
        or name == "BackToBack"
        or name == "TakeCover"
        or name == "Advance"
        or name == "FallBack"
        or name == "WatchSector"
end

function NPCOrderContract.IsPlayerCommandLootOrderName(name)
    name = NPCOrderContract.NormalizeOrderName(name)
    return name == "Loot"
        or name == "LootHouse"
        or name == "LootBodies"
        or name == "LootBodiesGear"
        or name == "LootBodiesClothing"
        or name == "LootBodiesWeapons"
        or name == "LootBodiesAmmo"
        or name == "LootBodiesMedical"
        or name == "LootBodiesSupplies"
        or name == "RearmHere"
end

function NPCOrderContract.IsPlayerCommandedTacticalOrderActive(brain)
    if not NPCOrderContract.IsPlayerCommandedMercenary(brain) then return false end
    local order = NPCOrderContract.Get(brain)
    if type(order) ~= "table" then return false end
    if order.source ~= "player" and order.commandAuthority ~= "player" and order.playerCommand ~= true then return false end
    return NPCOrderContract.IsPlayerCommandTacticalOrderName(order.name)
end

function NPCOrderContract.GetPlayerCommandTacticalProfile(name)
    name = NPCOrderContract.NormalizeOrderName(name)
    if name == "TakeCover" then
        return {mode="cover", stationary=true, allowCombat=true, combatRange=8.0, chaseRange=1.6, settle=1.35}
    elseif name == "WatchSector" then
        return {mode="watch", stationary=true, allowCombat=true, combatRange=16.0, chaseRange=1.25, settle=1.35}
    elseif name == "BackToBack" then
        return {mode="all_around", stationary=true, allowCombat=true, combatRange=10.0, chaseRange=1.25, settle=1.20}
    elseif name == "Flank" then
        return {mode="flank", stationary=false, allowCombat=true, combatRange=10.0, chaseRange=2.0, settle=1.55}
    elseif name == "Encircle" then
        return {mode="encircle", stationary=false, allowCombat=true, combatRange=10.0, chaseRange=1.75, settle=1.45}
    elseif name == "Advance" then
        return {mode="advance", stationary=false, allowCombat=true, combatRange=12.0, chaseRange=2.2, settle=1.55}
    elseif name == "FallBack" then
        return {mode="fallback", stationary=false, allowCombat=true, combatRange=5.0, chaseRange=1.4, settle=1.75}
    end
    return nil
end

function NPCOrderContract.GetPlayerCommandTacticalCombatRange(brain)
    local order = NPCOrderContract.Get(brain)
    if type(order) ~= "table" then return nil end
    local profile = NPCOrderContract.GetPlayerCommandTacticalProfile(order.name)
    if not profile then return nil end
    local fireRange = NPCOrderContract.GetFireDisciplineScanRadius(brain)
    local range = tonumber(profile.combatRange) or 8.0
    if fireRange then range = math.min(range, tonumber(fireRange) or range) end
    return range
end

function NPCOrderContract.IsStickyPlayerOrderActive(brain)
    if not NPCOrderContract.IsHiredMercenary(brain) then return false end
    local order = NPCOrderContract.Get(brain)
    if type(order) ~= "table" then return false end
    if order.source ~= "player" or order.sticky ~= true then return false end
    local name = NPCOrderContract.NormalizeOrderName(order.name)
    if name == "" or name == "Auto" then return false end
    return NPCOrderContract.IsStrictPlayerOrderName(name)
end

function NPCOrderContract.IsStrictPlayerOrderActive(brain)
    if not NPCOrderContract.IsHiredMercenary(brain) then return false end
    local order = NPCOrderContract.Get(brain)
    if type(order) ~= "table" then return false end
    if order.source ~= "player" and order.master == nil and order.commandAuthority ~= "player" and brain.commandAuthority ~= "player" then return false end
    local name = NPCOrderContract.NormalizeOrderName(order.name)
    if not NPCOrderContract.IsStrictPlayerOrderName(name) then return false end
    if order.strict == true or order.sticky == true or order.interrupt == true then return true end
    return false
end

function NPCOrderContract.GetStrictOrderName(brain)
    if not NPCOrderContract.IsStrictPlayerOrderActive(brain) then return nil end
    local order = NPCOrderContract.Get(brain)
    return order and NPCOrderContract.NormalizeOrderName(order.name) or nil
end

function NPCOrderContract.GetStrictLeash(brain, kind)
    local order = NPCOrderContract.Get(brain)
    local leash = type(order) == "table" and type(order.leash) == "table" and order.leash or nil
    kind = tostring(kind or "")
    if leash and tonumber(leash[kind]) then return tonumber(leash[kind]) end
    if kind == "follow" then return 6.5 end
    if kind == "guard" then return 9.5 end
    if kind == "hold" then return 2.8 end
    if kind == "combat" then return 12.0 end
    return nil
end

function NPCOrderContract.GetStrictCombatRange(brain)
    if not NPCOrderContract.IsStrictPlayerOrderActive(brain) then return nil end
    local name = NPCOrderContract.GetStrictOrderName(brain)
    local fireMode = NPCOrderContract.GetFireMode(brain)
    if fireMode == NPCOrderContract.FireModes.HoldFire then return 1.65 end
    if fireMode == NPCOrderContract.FireModes.MeleeOnly then return 2.2 end
    if name == "Hold" then return 10.0 end
    if name == "Guard" then return 12.0 end
    if name == "Follow" then return 6.5 end
    if name == "FallBack" or name == "Return" then return 5.5 end
    return NPCOrderContract.GetStrictLeash(brain, "combat") or 12.0
end

function NPCOrderContract.GetStrictChaseBoundary(brain)
    if not NPCOrderContract.IsStrictPlayerOrderActive(brain) then return nil end
    local name = NPCOrderContract.GetStrictOrderName(brain)
    local range = NPCOrderContract.GetStrictCombatRange(brain)
    if name == "Follow" then return math.min(tonumber(range) or 6.5, 6.5) end
    if name == "Guard" then return math.min(tonumber(range) or 10.5, 10.5) end
    if name == "Hold" then return math.min(tonumber(range) or 7.0, 7.0) end
    if name == "FallBack" or name == "Return" then return math.min(tonumber(range) or 4.5, 4.5) end
    return tonumber(range) or NPCOrderContract.GetStrictLeash(brain, "combat") or 9.0
end

function NPCOrderContract.ShouldIgnoreThreatForStrictOrder(brain, threat)
    if not NPCOrderContract.IsStrictPlayerOrderActive(brain) then return false end
    if type(threat) ~= "table" then return false end
    local dist = tonumber(threat.dist)
    if not dist then return false end
    local limit = NPCOrderContract.GetStrictCombatRange(brain)
    if not limit then return false end
    return dist > limit
end


function NPCOrderContract.CanAggro(brain)
    if NPCOrderContract.IsManualInterruptActive(brain) then return false end
    local fireMode = NPCOrderContract.NormalizeFireMode(NPCOrderContract.GetFireMode(brain))
    if fireMode == NPCOrderContract.FireModes.HoldFire then return false end
    if fireMode == NPCOrderContract.FireModes.ReturnFire then return NPCOrderContract.IsRecentlyProvoked(brain, 8) end
    return true
end

function NPCOrderContract.CanShoot(brain)
    if NPCOrderContract.IsManualInterruptActive(brain) then return false end

    -- Player-commanded mercenaries obey their order fire mode first. Utility
    -- scoring must not re-enable shooting after HoldFire/MeleeOnly.
    local fireMode = NPCOrderContract.NormalizeFireMode(NPCOrderContract.GetFireMode(brain))
    if fireMode == NPCOrderContract.FireModes.HoldFire or fireMode == NPCOrderContract.FireModes.MeleeOnly then return false end

    if NPCOrderContract.IsPlayerCommandedMercenary and NPCOrderContract.IsPlayerCommandedMercenary(brain) then
        return true
    end

    if NPCUtilityAIBridge and NPCUtilityAIBridge.CanShoot then
        return NPCUtilityAIBridge.CanShoot(brain)
    end

    return true
end

function NPCOrderContract.CanShootAtDistance(brain, dist)
    if not NPCOrderContract.CanShoot(brain) then return false end

    dist = tonumber(dist or 9999) or 9999
    local strictRange = NPCOrderContract.GetStrictCombatRange(brain)
    if strictRange and dist > strictRange then return false end

    local utilityAllowed = nil
    if NPCUtilityAIBridge and NPCUtilityAIBridge.CanShootAtDistance then
        utilityAllowed = NPCUtilityAIBridge.CanShootAtDistance(brain, dist)
        if utilityAllowed == false then return false end
    end

    local fireMode = NPCOrderContract.NormalizeFireMode(NPCOrderContract.GetFireMode(brain))
    if fireMode == NPCOrderContract.FireModes.Defensive then
        return dist <= NPCOrderContract.DefensiveShootDistance
    elseif fireMode == NPCOrderContract.FireModes.ReturnFire then
        if NPCOrderContract.IsRecentlyProvoked(brain, 8) then return dist <= NPCOrderContract.DefensiveShootDistance end
        return dist <= 3.5
    elseif fireMode == NPCOrderContract.FireModes.DangerClose then
        return dist <= 7
    elseif fireMode == NPCOrderContract.FireModes.Suppress then
        return dist <= 32
    end

    return true
end

function NPCOrderContract.CanMelee(brain)
    if NPCOrderContract.IsManualInterruptActive(brain) then return false end
    -- HoldFire suppresses firearms and voluntary aggro. Melee remains available
    -- only through distance-gated close-defense checks in the combat layer.
    return true
end

function NPCOrderContract.Export(brain)
    local order = NPCOrderContract.Get(brain)
    if not order then return nil end

    local out = {}
    for k, v in pairs(order) do
        if type(v) == "table" then
            out[k] = {}
            for tk, tv in pairs(v) do
                out[k][tk] = tv
            end
        else
            out[k] = v
        end
    end
    return out
end

NPCCommands = NPCCommands or {}
NPCCommands.OrderContract = NPCOrderContract
