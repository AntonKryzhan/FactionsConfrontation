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
    if NPCUtilityAIBridge and NPCUtilityAIBridge.GetFireMode then
        local mode = NPCUtilityAIBridge.GetFireMode(brain)
        if mode == "hold" then return NPCOrderContract.FireModes.HoldFire end
        if mode == "melee_only" then return NPCOrderContract.FireModes.MeleeOnly end
        if mode == "return_fire" then return NPCOrderContract.FireModes.ReturnFire end
        if mode == "danger_close" then return NPCOrderContract.FireModes.DangerClose end
        if mode == "suppress" then return NPCOrderContract.FireModes.Suppress end
    end

    local order = NPCOrderContract.Get(brain)
    return order and order.fireMode or NPCOrderContract.FireModes.FireAtWill
end

function NPCOrderContract.Set(brain, name, data)
    if not brain then return nil end

    data = data or {}

    local order = NPCOrderContract.Ensure(brain)
    order.name = name or NPCOrderContract.Names.Auto
    order.source = data.source or "player"
    order.issued = NPCOrderContract.Now()
    order.priority = data.priority or order.priority or 10

    if data.master then order.master = data.master end
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

function NPCOrderContract.CanAggro(brain)
    return not NPCOrderContract.IsStrictHoldFire(brain)
end

function NPCOrderContract.CanShoot(brain)
    if NPCUtilityAIBridge and NPCUtilityAIBridge.CanShoot then
        return NPCUtilityAIBridge.CanShoot(brain)
    end

    local fireMode = NPCOrderContract.GetFireMode(brain)
    return fireMode ~= NPCOrderContract.FireModes.HoldFire and fireMode ~= NPCOrderContract.FireModes.MeleeOnly
end

function NPCOrderContract.CanShootAtDistance(brain, dist)
    if NPCUtilityAIBridge and NPCUtilityAIBridge.CanShootAtDistance then
        return NPCUtilityAIBridge.CanShootAtDistance(brain, dist)
    end

    if not NPCOrderContract.CanShoot(brain) then return false end

    local fireMode = NPCOrderContract.GetFireMode(brain)
    if fireMode == NPCOrderContract.FireModes.Defensive or fireMode == NPCOrderContract.FireModes.ReturnFire then
        return dist and dist <= NPCOrderContract.DefensiveShootDistance
    elseif fireMode == NPCOrderContract.FireModes.DangerClose then
        return dist and dist <= 7
    elseif fireMode == NPCOrderContract.FireModes.Suppress then
        return dist and dist <= 32
    end

    return true
end

function NPCOrderContract.CanMelee(brain)
    if NPCOrderContract.IsStrictHoldFire(brain) then return false end
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
