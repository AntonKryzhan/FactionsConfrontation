require "NPCCore/NPCLegacySettingsBridge"
require "NPCCore/NPCUtilityCore"
require "NPCCore/NPCBlackMarketBridge"
require "NPCCore/NPCWeaponsBridge"
require "NPCCore/NPCHealthRegenBridge"
require "NPCCore/NPCEntityState"
require "NPCCore/NPCFactionBridge"
require "NPCCore/NPCLoyaltyBridge"
require "NPCBehavior/NPCBrainDataBridge"
-- Stage 372: hired mercenaries no longer depend on the shared NPCOrderContract dispatch path.

-- Neutral mercenary contract backend.
-- Compatibility entry point remains legacy mercenary API.

-- Blue neutral mercenary layer.
-- Blue squads are neutral elite contractors until a player hires them.

require "NPCCore/NPCLegacyContractBridge"

NPCMercenaryContract = NPCMercenaryContract or {}
NPCMercenaryContract.Version = 1

local function bm_setting(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.Get then
        return NPCLegacySettingsBridge.Get(name, defaultValue)
    end
    local vars = SandboxVars and SandboxVars[NPCLegacyContractBridge.Sandbox.ext] or nil
    if vars and vars[name] ~= nil then return vars[name] end
    return defaultValue
end

local function bm_settingBool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        return NPCLegacySettingsBridge.GetBool(name, defaultValue)
    end
    local value = bm_setting(name, defaultValue)
    if value == true or value == 1 or value == "true" then return true end
    if value == false or value == 0 or value == "false" then return false end
    return defaultValue == true
end

local function bm_settingNumber(name, defaultValue, minValue, maxValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        return NPCLegacySettingsBridge.GetNumber(name, defaultValue, minValue, maxValue)
    end
    local value = tonumber(bm_setting(name, defaultValue)) or tonumber(defaultValue) or 0
    if minValue ~= nil and value < minValue then value = minValue end
    if maxValue ~= nil and value > maxValue then value = maxValue end
    return value
end

local function bm_copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = bm_copy(v) end
    return out
end

local function bm_nowMs()
    if getTimestampMs then
        local ok, value = pcall(function() return getTimestampMs() end)
        if ok and tonumber(value) then return tonumber(value) end
    end
    if getGameTime then
        local ok, value = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok and tonumber(value) then return math.floor((tonumber(value) or 0) * 3600000) end
    end
    return 0
end

local function bm_normalizeOrderName(name)
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

local function bm_isMovementOrder(name)
    name = bm_normalizeOrderName(name)
    return name == "Follow" or name == "Hold" or name == "Guard" or name == "Patrol" or name == "Loot"
        or name == "LootHouse" or name == "Return" or name == "RearmHere"
        or name == "Advance" or name == "FallBack" or name == "TakeCover" or name == "Flank"
        or name == "Encircle" or name == "BackToBack" or name == "WatchSector"
        or string.find(name, "LootBodies", 1, true) ~= nil
end

local function bm_normalizeFireMode(mode)
    mode = tostring(mode or "")
    if mode == "" or mode == "nil" then return nil end
    if mode == "HoldFire" or mode == "hold" or mode == "hold_fire" then return "HoldFire" end
    if mode == "MeleeOnly" or mode == "melee" or mode == "melee_only" then return "MeleeOnly" end
    if mode == "Defensive" or mode == "defensive" or mode == "fire_if_attacked" then return "Defensive" end
    if mode == "ReturnFire" or mode == "return_fire" then return "ReturnFire" end
    if mode == "DangerClose" or mode == "danger_close" then return "DangerClose" end
    if mode == "Suppress" or mode == "suppress" then return "Suppress" end
    if mode == "FireAtWill" or mode == "free" or mode == "fire_at_will" then return "FireAtWill" end
    return mode
end

local function bm_isStrictMercenaryOrderName(name)
    name = bm_normalizeOrderName(name)
    return name == "Follow" or name == "Hold" or name == "Guard" or name == "FallBack" or name == "Return"
end

local function bm_isPlayerMercenaryOrderName(name)
    name = bm_normalizeOrderName(name)
    return name == "Follow" or name == "Hold" or name == "Guard" or name == "Patrol" or name == "Loot" or name == "LootHouse"
        or name == "LootBodies" or name == "LootBodiesGear" or name == "LootBodiesClothing" or name == "LootBodiesWeapons"
        or name == "LootBodiesAmmo" or name == "LootBodiesMedical" or name == "LootBodiesSupplies" or name == "RearmHere"
        or name == "Flank" or name == "Encircle" or name == "BackToBack" or name == "TakeCover" or name == "Advance"
        or name == "FallBack" or name == "WatchSector" or name == "Return"
end

local function bm_isPointMercenaryOrderName(name)
    name = bm_normalizeOrderName(name)
    return name == "Hold" or name == "Guard" or name == "Patrol" or name == "Loot" or name == "LootHouse"
        or name == "LootBodies" or name == "LootBodiesGear" or name == "LootBodiesClothing" or name == "LootBodiesWeapons"
        or name == "LootBodiesAmmo" or name == "LootBodiesMedical" or name == "LootBodiesSupplies" or name == "RearmHere"
        or name == "Return" or name == "Flank" or name == "Encircle" or name == "BackToBack" or name == "TakeCover"
        or name == "Advance" or name == "FallBack" or name == "WatchSector"
end

local function bm_isPlayerCommandedMercenaryBrain(brain)
    if type(brain) ~= "table" then return false end
    if brain.commandAuthority == "player" or brain.playerCommandAuthority == true then return true end
    return brain.mercenaryHired == true and brain.worldCommandDisabled == true
end

local function bm_isMercenaryTacticalOrderName(name)
    name = bm_normalizeOrderName(name)
    return name == "Flank" or name == "Encircle" or name == "BackToBack" or name == "TakeCover" or name == "Advance" or name == "FallBack" or name == "WatchSector"
end

local function bm_getMercenaryTacticalProfile(name)
    name = bm_normalizeOrderName(name)
    if name == "TakeCover" then return {mode="cover", stationary=true, allowCombat=true, combatRange=8.0, chaseRange=1.6, settle=1.35} end
    if name == "WatchSector" then return {mode="watch", stationary=true, allowCombat=true, combatRange=16.0, chaseRange=1.25, settle=1.35} end
    if name == "BackToBack" then return {mode="all_around", stationary=true, allowCombat=true, combatRange=10.0, chaseRange=1.25, settle=1.20} end
    if name == "Flank" then return {mode="flank", stationary=false, allowCombat=true, combatRange=10.0, chaseRange=2.0, settle=1.55} end
    if name == "Encircle" then return {mode="encircle", stationary=false, allowCombat=true, combatRange=10.0, chaseRange=1.75, settle=1.45} end
    if name == "Advance" then return {mode="advance", stationary=false, allowCombat=true, combatRange=12.0, chaseRange=2.2, settle=1.55} end
    if name == "FallBack" then return {mode="fallback", stationary=false, allowCombat=true, combatRange=5.0, chaseRange=1.4, settle=1.75} end
    return nil
end

local function bm_nowHours()
    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then
            local ok, value = pcall(function() return gt:getWorldAgeHours() end)
            if ok and tonumber(value) then return tonumber(value) end
        end
    end
    return 0
end

local function bm_setMercenaryDirectOrder(brain, orderName, data, hardInterrupt, strictOrder, playerCommandOrder, interruptSeconds, orderFollowDistance)
    if type(brain) ~= "table" then return nil end
    data = data or {}
    brain.ai = brain.ai or {}

    orderName = bm_normalizeOrderName(orderName or (brain.order and brain.order.name) or "Follow")
    strictOrder = strictOrder == true
    playerCommandOrder = playerCommandOrder ~= false
    local nowHour = bm_nowHours()
    local order = type(brain.order) == "table" and bm_copy(brain.order) or {}

    brain.ai.mercenaryDirectOrderSequence = (tonumber(brain.ai.mercenaryDirectOrderSequence) or 0) + 1
    order.name = orderName
    order.source = "mercenary_direct"
    order.commandAuthority = "player"
    order.playerCommand = true
    order.playerCommandMode = "mercenary_direct"
    order.mercenaryDirect = true
    order.directMercenaryOrder = true
    order.master = data.master or brain.master or brain.mercenaryHiredBy
    order.issued = nowHour
    order.sequence = brain.ai.mercenaryDirectOrderSequence
    order.priority = tonumber(data.priority) or (strictOrder and 135 or 125)
    order.note = data.note or "mercenary direct order"

    if orderName == "Follow" then
        order.anchor = nil
        order.targetType = "player"
        order.anchorMode = "player"
        order.cursorAnchor = nil
    elseif data.anchor then
        local ax = tonumber(data.anchor.x)
        local ay = tonumber(data.anchor.y)
        if ax and ay then
            order.anchor = {
                x=ax,
                y=ay,
                z=tonumber(data.anchor.z) or 0,
                facingAngle=tonumber(data.anchor.facingAngle or data.facingAngle)
            }
            order.targetType = "point"
            order.anchorMode = data.anchorMode or data.targetType or "cursor"
            order.cursorAnchor = true
        end
    elseif hardInterrupt == true and bm_isPointMercenaryOrderName(orderName) then
        order.anchor = nil
        order.targetType = "point"
        order.anchorMode = data.anchorMode or data.targetType or "missing"
        order.cursorAnchor = nil
    end

    if data.fireMode ~= nil then order.fireMode = bm_normalizeFireMode(data.fireMode) end
    if not order.fireMode then order.fireMode = "FireAtWill" end
    if data.formation ~= nil then order.formation = data.formation end
    if not order.formation then order.formation = "close" end
    if data.tactical ~= nil then order.tactical = data.tactical end
    if orderName == "Follow" and orderFollowDistance == nil then orderFollowDistance = 0.95 end
    if orderFollowDistance ~= nil then order.followDistance = tonumber(orderFollowDistance) or order.followDistance end

    if hardInterrupt == true then
        local seconds = tonumber(interruptSeconds) or 8
        if seconds < 1 then seconds = 1 end
        if seconds > 30 then seconds = 30 end
        order.interrupt = true
        order.interruptIssued = nowHour
        order.interruptUntil = nowHour + (seconds / 3600)
        order.interruptReason = "mercenary direct order"
    else
        order.interrupt = false
        order.interruptUntil = nil
        order.interruptReason = nil
    end

    if strictOrder then
        order.strict = true
        order.sticky = true
        order.strictSequence = order.sequence
        order.stickySequence = order.sequence
        order.strictReason = "mercenary direct strict order"
        order.stickyReason = "mercenary direct player order lock"
        order.leash = (orderName == "Follow") and {follow=3.6, guard=10.0, hold=3.0, combat=4.0} or {follow=6.5, guard=10.0, hold=3.0, combat=6.5}
        order.immediateReapply = true
        order.immediateReapplySequence = order.sequence
        order.immediateReapplyUntil = nowHour + (3.8 / 3600)
        order.immediateReapplyReason = "mercenary direct immediate order"
    elseif playerCommandOrder then
        order.strict = nil
        order.strictSequence = nil
        order.strictReason = nil
        order.sticky = nil
        order.stickySequence = nil
        order.stickyReason = nil
        order.leash = nil
        order.immediateReapply = true
        order.immediateReapplySequence = order.sequence
        order.immediateReapplyUntil = nowHour + (2.4 / 3600)
        order.immediateReapplyReason = "mercenary direct immediate player order"
    end

    order.dispatchMode = "mercenary_direct"
    order.forceImmediate = true
    order.forceManualOrderNow = true
    order.watchdogIntervalMs = tonumber(order.watchdogIntervalMs) or (orderName == "Follow" and 240 or 320)

    brain.order = order
    brain.commandAuthority = "player"
    brain.playerCommandAuthority = true
    brain.mercenaryDirectOrders = true
    brain.orderSystem = "mercenary_direct"
    brain.fireMode = order.fireMode or brain.fireMode
    brain.rbFireMode = brain.fireMode or brain.rbFireMode
    brain.sim = brain.sim or {}
    brain.sim.order = order.name
    brain.sim.fireMode = order.fireMode
    brain.sim.formation = order.formation
    brain.sim.orderUpdated = order.issued
    brain.debug = brain.debug or {}
    brain.debug.order = order.name
    brain.debug.fireMode = order.fireMode
    brain.debug.formation = order.formation
    brain.ai.lastOrderAt = order.issued
    brain.ai.lastManualOrder = order.name
    brain.ai.mercenaryDirectOrderName = order.name
    brain.ai.mercenaryDirectOrderAt = order.issued
    brain.ai.mercenaryDirectDispatch = true
    return order
end

local function bm_applyDispatchFields(brain, order, orderName, data, hardInterrupt, playerCommandOrder)
    if type(brain) ~= "table" then return end
    data = data or {}
    orderName = bm_normalizeOrderName(orderName or (order and order.name))
    brain.ai = brain.ai or {}

    local revision = tonumber(data.orderRevision or data.groupOrderRevision or data.orderBatchRevision)
    if not revision then
        revision = (tonumber(brain.ai.mercenaryLocalOrderRevision) or 0) + 1
        brain.ai.mercenaryLocalOrderRevision = revision
    end
    local batchId = data.orderBatchId or data.groupOrderBatchId or (data.master and (tostring(data.master) .. ":" .. tostring(revision))) or tostring(revision)
    local nowMs = tonumber(data.orderIssuedMs) or bm_nowMs()

    brain.mercenaryOrderRevision = revision
    brain.mercenaryOrderBatchId = batchId
    brain.mercenaryOrderIssuedMs = nowMs
    brain.orderRevision = revision
    brain.groupOrderRevision = revision
    brain.groupOrderBatchId = batchId

    brain.ai.mercenaryOrderRevision = revision
    brain.ai.mercenaryOrderBatchId = batchId
    brain.ai.mercenaryOrderName = orderName
    brain.ai.mercenaryOrderIssuedMs = nowMs
    brain.ai.forceManualOrderNow = true
    brain.ai.lastGenerateTaskFrameTick = nil
    brain.ai.manualOrderConsumedIssued = nil
    brain.ai.manualOrderConsumedSequence = nil
    brain.ai.manualOrderConsumedAtMs = nil
    brain.ai.orderDispatchMode = "immediate_group"
    brain.ai.orderDispatchReason = hardInterrupt and "hard_interrupt" or "soft_overlay"

    if order then
        order.orderRevision = revision
        order.groupOrderRevision = revision
        order.orderBatchId = batchId
        order.groupOrderBatchId = batchId
        order.dispatchMode = "immediate_group"
        order.playerCommand = order.playerCommand or playerCommandOrder == true
        order.commandAuthority = order.commandAuthority or "player"
        order.source = order.source or "player"
        order.forceImmediate = true
        order.forceManualOrderNow = true
        order.watchdogIntervalMs = tonumber(order.watchdogIntervalMs) or (orderName == "Follow" and 260 or 360)
        if bm_isMovementOrder(orderName) then
            order.interrupt = hardInterrupt ~= false
            order.interruptIssued = order.interruptIssued or order.issued or (bm_nowHours())
            order.interruptUntil = order.interruptUntil or ((order.interruptIssued or 0) + ((orderName == "Follow" and 10 or 6) / 3600))
            order.interruptReason = order.interruptReason or "mercenary immediate dispatch"
        end
        if orderName == "Follow" then
            order.immediateReapply = true
            order.immediateReapplySeconds = math.max(tonumber(order.immediateReapplySeconds) or 0, 6)
            order.immediateReapplyUntil = math.max(tonumber(order.immediateReapplyUntil) or 0, (bm_nowHours()) + (6 / 3600))
            order.immediateReapplyReason = order.immediateReapplyReason or "bodyguard follow responsiveness"
            order.followDistance = tonumber(order.followDistance) or 0.95
        end
    end
end

local function bm_playerId(player)
    if not player then return nil end
    if NPCUtilityCore and NPCUtilityCore.GetCharacterID then
        local ok, id = pcall(function() return NPCUtilityCore.GetCharacterID(player) end)
        if ok and id ~= nil then return id end
    end
    if player.getOnlineID then
        local ok, id = pcall(function() return player:getOnlineID() end)
        if ok and id ~= nil then return id end
    end
    if player.getUsername then
        local ok, name = pcall(function() return player:getUsername() end)
        if ok and name then return name end
    end
    return nil
end

local function bm_playerName(player)
    if not player then return nil end
    if player.getUsername then
        local ok, name = pcall(function() return player:getUsername() end)
        if ok and name then return name end
    end
    if player.getDisplayName then
        local ok, name = pcall(function() return player:getDisplayName() end)
        if ok and name then return name end
    end
    return tostring(bm_playerId(player) or "player")
end

local function bm_weaponScore(w)
    if not w or not w.name then return -1 end
    local mag = tonumber(w.magSize) or 0
    local delay = tonumber(w.shotDelay) or 30
    return (mag * 4) + math.max(0, 60 - delay)
end

local function bm_bestWeapon(pool)
    if not pool or #pool == 0 then return nil end
    local best = nil
    local bestScore = -1
    for _, w in pairs(pool) do
        local score = bm_weaponScore(w)
        if score > bestScore then
            best = w
            bestScore = score
        end
    end
    return bm_copy(best)
end

local function bm_pickMercenaryWeapon(pool, slot)
    if not pool or #pool == 0 then return nil end
    if NPCCreatorBridge and NPCCreatorBridge.PickBalancedFirearm then
        local wave = {eliteLoadout=true, mercenaryElite=true, hasRifleChance=88, rifleMagCount=4, hasPistolChance=70, pistolMagCount=3}
        return bm_copy(NPCCreatorBridge.PickBalancedFirearm(pool, wave, slot))
    end
    return bm_bestWeapon(pool)
end

local function bm_ensureWeapons(member)
    member.weapons = member.weapons or {}
    member.weapons.melee = member.weapons.melee or "Base.Axe"
    member.weapons.primary = member.weapons.primary or {name=false, magSize=0, bulletsLeft=0, magCount=0}
    member.weapons.secondary = member.weapons.secondary or {name=false, magSize=0, bulletsLeft=0, magCount=0}
    return member.weapons
end

local function bm_addUnique(list, value)
    if not value then return end
    if type(list) ~= "table" then return end
    for _, v in pairs(list) do
        if v == value then return end
    end
    table.insert(list, value)
end

NPCMercenaryContract.GoldJewelry = NPCMercenaryContract.GoldJewelry or {
    "Base.GoldRing", "Base.Ring_Gold", "Base.RingGold", "Base.Ring_Left_Gold", "Base.Ring_Right_Gold",
    "Base.Ring_Right_MiddleFinger_Gold", "Base.Ring_Left_MiddleFinger_Gold",
    "Base.Ring_Right_RingFinger_Gold", "Base.Ring_Left_RingFinger_Gold",
    "Base.Ring_Right_MiddleFinger_GoldDiamond", "Base.Ring_Left_MiddleFinger_GoldDiamond",
    "Base.Ring_Right_RingFinger_GoldDiamond", "Base.Ring_Left_RingFinger_GoldDiamond",
    "Base.Ring_Right_MiddleFinger_GoldRuby", "Base.Ring_Left_MiddleFinger_GoldRuby",
    "Base.Ring_Right_RingFinger_GoldRuby", "Base.Ring_Left_RingFinger_GoldRuby",
    "Base.Necklace_Gold", "Base.Necklace_GoldRuby", "Base.Necklace_GoldDiamond",
    "Base.NecklaceLong_Gold", "Base.NecklaceLong_GoldDiamond",
    "Base.Bracelet_ChainRightGold", "Base.Bracelet_ChainLeftGold",
    "Base.Bracelet_BangleRightGold", "Base.Bracelet_BangleLeftGold",
    "Base.Earring_LoopLrg_Gold", "Base.Earring_LoopMed_Gold", "Base.Earring_LoopSmall_Gold",
    "Base.Earring_LoopLrg_Gold_Both", "Base.Earring_LoopMed_Gold_Both",
    "Base.Earring_LoopSmall_Gold_Both", "Base.Earring_LoopSmall_Gold_Top",
    "Base.Earring_Stud_Gold_Both",
    "Base.BellyButton_DangleGold", "Base.BellyButton_DangleGoldRuby",
    "Base.BellyButton_RingGold", "Base.BellyButton_RingGoldDiamond", "Base.BellyButton_RingGoldRuby",
    "Base.BellyButton_StudGold", "Base.BellyButton_StudGoldDiamond",
    "Base.NoseRing_Gold", "Base.NoseStud_Gold",
    "Base.WristWatch_Left_ClassicGold", "Base.WristWatch_Right_ClassicGold"
}

NPCMercenaryContract.SilverJewelry = NPCMercenaryContract.SilverJewelry or {
    "Base.SilverRing", "Base.Ring_Silver", "Base.RingSilver", "Base.Ring_Left_Silver", "Base.Ring_Right_Silver",
    "Base.Ring_Right_MiddleFinger_Silver", "Base.Ring_Left_MiddleFinger_Silver",
    "Base.Ring_Right_RingFinger_Silver", "Base.Ring_Left_RingFinger_Silver",
    "Base.Ring_Right_MiddleFinger_SilverDiamond", "Base.Ring_Left_MiddleFinger_SilverDiamond",
    "Base.Ring_Right_RingFinger_SilverDiamond", "Base.Ring_Left_RingFinger_SilverDiamond",
    "Base.Necklace_Silver", "Base.Necklace_SilverSapphire", "Base.Necklace_SilverCrucifix", "Base.Necklace_SilverDiamond",
    "Base.NecklaceLong_Silver", "Base.NecklaceLong_SilverDiamond", "Base.NecklaceLong_SilverEmerald", "Base.NecklaceLong_SilverSapphire",
    "Base.Bracelet_ChainRightSilver", "Base.Bracelet_ChainLeftSilver",
    "Base.Bracelet_BangleRightSilver", "Base.Bracelet_BangleLeftSilver",
    "Base.Earring_LoopLrg_Silver", "Base.Earring_LoopMed_Silver", "Base.Earring_LoopSmall_Silver",
    "Base.Earring_LoopLrg_Silver_Both", "Base.Earring_LoopMed_Silver_Both",
    "Base.Earring_LoopSmall_Silver_Both", "Base.Earring_LoopSmall_Silver_Top",
    "Base.Earring_Stud_Silver_Both",
    "Base.BellyButton_DangleSilver", "Base.BellyButton_DangleSilverDiamond",
    "Base.BellyButton_RingSilver", "Base.BellyButton_RingSilverAmethyst", "Base.BellyButton_RingSilverDiamond", "Base.BellyButton_RingSilverRuby",
    "Base.BellyButton_StudSilver", "Base.BellyButton_StudSilverDiamond",
    "Base.NoseRing_Silver", "Base.NoseStud_Silver"
}

NPCMercenaryContract.HireResources = {
    [1] = {type="gold", label="gold jewelry", items=NPCMercenaryContract.GoldJewelry},
    [2] = {type="silver", label="silver jewelry", items=NPCMercenaryContract.SilverJewelry}
}

NPCMercenaryContract.EliteArmor = {
    "Base.Vest_BulletPolice",
    "Base.Hat_Army",
    "Base.HolsterDouble",
    "Base.Bag_ALICEpack_Army"
}

NPCMercenaryContract.EliteLoot = {
    "Base.Bandage",
    "Base.AlcoholBandage",
    "Base.PillsBeta",
    "Base.WaterBottle"
}

function NPCMercenaryContract.IsEnabled()
    return bm_settingBool("Mercenary_Enabled", true)
end

function NPCMercenaryContract.IsHireEnabled()
    return NPCMercenaryContract.IsEnabled() and bm_settingBool("Mercenary_HireEnabled", true)
end

function NPCMercenaryContract.IsEliteEnabled()
    return NPCMercenaryContract.IsEnabled() and bm_settingBool("Mercenary_EliteOnBlue", true)
end

function NPCMercenaryContract.GetHireResource()
    local idx = math.floor(bm_settingNumber("Mercenary_HireResource", 1, 1, 2))
    return NPCMercenaryContract.HireResources[idx] or NPCMercenaryContract.HireResources[1]
end

function NPCMercenaryContract.GetGoldJewelryCost()
    return math.floor(bm_settingNumber("Mercenary_GoldJewelryCost", 2, 0, 100))
end

function NPCMercenaryContract.AllowSilverPayment()
    return bm_settingBool("Mercenary_AllowSilverPayment", true)
end

function NPCMercenaryContract.GetSilverJewelryCost()
    return math.floor(bm_settingNumber("Mercenary_SilverJewelryCost", 6, 0, 300))
end

function NPCMercenaryContract.GetHireCostCount()
    return NPCMercenaryContract.GetGoldJewelryCost()
end

function NPCMercenaryContract.GetHireCostLabel()
    local gold = NPCMercenaryContract.GetGoldJewelryCost()
    local silver = NPCMercenaryContract.GetSilverJewelryCost()
    if NPCMercenaryContract.AllowSilverPayment() then
        return tostring(gold) .. " x gold jewelry or " .. tostring(silver) .. " x silver jewelry"
    end
    return tostring(gold) .. " x gold jewelry"
end

function NPCMercenaryContract.GetBlueRoadPatrolChance()
    return bm_settingNumber("Mercenary_BlueRoadPatrolChance", 25, 0, 100)
end

function NPCMercenaryContract.GetBlueGroupChance()
    return bm_settingNumber("Mercenary_BlueGroupChance", 10, 0, 100)
end

function NPCMercenaryContract.RollBlueRoadPatrol()
    if not NPCMercenaryContract.IsEnabled() then return false end
    local chance = NPCMercenaryContract.GetBlueRoadPatrolChance()
    if chance <= 0 then return false end
    local roll = ZombRand and ZombRand(10000) or math.random(0, 9999)
    return chance >= 100 or roll < math.floor(chance * 100)
end

function NPCMercenaryContract.RollBlueGroup()
    if not NPCMercenaryContract.IsEnabled() then return false end
    local chance = NPCMercenaryContract.GetBlueGroupChance()
    if chance <= 0 then return false end
    local roll = ZombRand and ZombRand(10000) or math.random(0, 9999)
    return chance >= 100 or roll < math.floor(chance * 100)
end

function NPCMercenaryContract.ApplyEliteToMember(member)
    if NPCBlackMarketBridge and NPCBlackMarketBridge.IsNPCBrain and NPCBlackMarketBridge.IsNPCBrain(member) then return member end
    if not (NPCMercenaryContract.IsEliteEnabled() and type(member) == "table") then return member end
    if member.mercenaryElite == true then return member end

    member.mercenary = true
    member.mercenaryElite = true
    member.elite = true
    member.role = member.role or "Mercenary Elite"
    member.tacticalRole = member.tacticalRole or "elite_bodyguard"
    member.relationshipToPlayer = member.relationshipToPlayer or "neutral"
    member.hostile = false
    member.factionSide = "blue"
    member.faction = "blue"
    member.side = "blue"
    member.patrolColor = "blue"
    member.factionState = member.factionState or "blue_mercenary"

    local eliteHealth = bm_settingNumber("Mercenary_EliteHealth", 4.0, 1.0, 10.0)
    member.health = math.max(tonumber(member.health) or 0, eliteHealth)
    member.maxHealth = math.max(tonumber(member.maxHealth) or 0, member.health)
    member.accuracyBoost = math.max(tonumber(member.accuracyBoost) or 1, bm_settingNumber("Mercenary_AccuracyBoost", 1.75, 1.0, 5.0))
    member.morale = math.max(tonumber(member.morale) or 0, 0.96)
    member.fear = math.min(tonumber(member.fear) or 1, 0.08)
    member.discipline = math.max(tonumber(member.discipline) or 0, 0.94)
    member.aggression = math.max(tonumber(member.aggression) or 0, 0.55)

    member.skills = member.skills or {}
    for _, key in ipairs({"aiming", "reloading", "firearms", "strength", "fitness", "maintenance", "medical", "teamwork"}) do
        member.skills[key] = math.max(tonumber(member.skills[key]) or 0, 7)
    end

    local weapons = bm_ensureWeapons(member)
    local primaryPool = nil
    local secondaryPool = nil
    if NPCWeaponsBridge and NPCWeaponsBridge.GetSpawnPrimary then primaryPool = NPCWeaponsBridge.GetSpawnPrimary(nil) elseif NPCWeaponsBridge then primaryPool = NPCWeaponsBridge.Primary end
    if NPCWeaponsBridge and NPCWeaponsBridge.GetSpawnSecondary then secondaryPool = NPCWeaponsBridge.GetSpawnSecondary(nil) elseif NPCWeaponsBridge then secondaryPool = NPCWeaponsBridge.Secondary end

    if not (weapons.primary and weapons.primary.name) then
        weapons.primary = bm_pickMercenaryWeapon(primaryPool, "primary") or {name="Base.AssaultRifle", magName="Base.556Clip", magSize=30, bulletsLeft=30, magCount=0, shotDelay=12}
    end
    if weapons.primary and weapons.primary.name then
        weapons.primary.magSize = tonumber(weapons.primary.magSize) or 30
        weapons.primary.bulletsLeft = weapons.primary.magSize
        weapons.primary.magCount = math.max(tonumber(weapons.primary.magCount) or 0, math.floor(bm_settingNumber("Mercenary_PrimaryMagCount", 8, 0, 50)))
    end

    if not (weapons.secondary and weapons.secondary.name) then
        weapons.secondary = bm_pickMercenaryWeapon(secondaryPool, "secondary") or {name="Base.Pistol", magName="Base.9mmClip", magSize=15, bulletsLeft=15, magCount=0, shotDelay=35}
    end
    if weapons.secondary and weapons.secondary.name then
        weapons.secondary.magSize = tonumber(weapons.secondary.magSize) or 15
        weapons.secondary.bulletsLeft = weapons.secondary.magSize
        weapons.secondary.magCount = math.max(tonumber(weapons.secondary.magCount) or 0, math.floor(bm_settingNumber("Mercenary_SecondaryMagCount", 4, 0, 50)))
    end

    if not weapons.melee or weapons.melee == "Base.BareHands" then
        weapons.melee = "Base.Axe"
    end

    member.inventory = member.inventory or {}
    member.loot = member.loot or {}
    member.baseGear = member.baseGear or {}
    member.baseGearWear = member.baseGearWear or {}

    for _, itemType in ipairs(NPCMercenaryContract.EliteArmor) do
        bm_addUnique(member.inventory, itemType)
        bm_addUnique(member.loot, itemType)
        bm_addUnique(member.baseGearWear, itemType)
    end
    for _, itemType in ipairs(NPCMercenaryContract.EliteLoot) do
        bm_addUnique(member.inventory, itemType)
    end

    return member
end

local function bm_restockWeapon(weapon, fallbackMagCount)
    if type(weapon) ~= "table" then return end
    if not weapon.name then return end
    local magSize = tonumber(weapon.magSize) or 0
    if magSize <= 0 then magSize = 1 end
    weapon.magSize = magSize
    weapon.bulletsLeft = magSize
    weapon.magCount = math.max(tonumber(weapon.magCount) or 0, tonumber(fallbackMagCount) or 0)
end

function NPCMercenaryContract.RestockAndHealBrain(brain, bandit)
    if type(brain) ~= "table" then return brain end

    local weapons = bm_ensureWeapons(brain)
    bm_restockWeapon(weapons.primary, math.floor(bm_settingNumber("Mercenary_PrimaryMagCount", 8, 0, 50)))
    bm_restockWeapon(weapons.secondary, math.floor(bm_settingNumber("Mercenary_SecondaryMagCount", 4, 0, 50)))

    local maxHealth = tonumber(brain.maxHealth) or tonumber(brain.health) or 3.0
    if NPCHealthRegenBridge and NPCHealthRegenBridge.ResolveMaxHealth then
        maxHealth = NPCHealthRegenBridge.ResolveMaxHealth(brain)
    elseif NPCHealthRegenBridge and NPCHealthRegenBridge.NormalizeSpawnHealth then
        maxHealth = NPCHealthRegenBridge.NormalizeSpawnHealth(maxHealth)
    end
    brain.maxHealth = maxHealth
    brain.health = maxHealth

    brain.wounded = nil
    brain.woundedDowned = nil
    brain.woundedStabilized = nil
    brain.woundedState = nil
    brain.woundedReason = nil
    brain.woundedAt = nil
    brain.woundedExpiresAt = nil
    brain.woundedForPlayerId = nil
    brain.woundedForPlayerName = nil
    brain.woundedX = nil
    brain.woundedY = nil
    brain.woundedZ = nil
    brain.woundedStabilizedAt = nil
    brain.woundedEvacuating = nil
    brain.woundedEvacuatedAt = nil
    brain.woundedEvacTarget = nil
    brain.woundedEvacBaseId = nil
    brain.woundedAbandoned = nil
    brain.woundedAbandonedAt = nil

    brain.regen = brain.regen or {}
    brain.regen.lastHealth = maxHealth
    brain.regen.lastDamageAt = 0
    brain.regen.nextRegenAt = 0
    brain.regen.lastRegenAt = getTimestampMs and getTimestampMs() or 0

    if bandit then
        if bandit.setHealth then pcall(function() bandit:setHealth(maxHealth) end) end
        if NPCEntityState and NPCEntityState.SetWeapons then pcall(function() NPCEntityState.SetWeapons(bandit, weapons) end) end
        if NPCBrainDataBridge and NPCBrainDataBridge.Update then pcall(function() NPCBrainDataBridge.Update(bandit, brain) end) end
    end

    return brain
end

function NPCMercenaryContract.ApplyEliteToBrain(brain)
    return NPCMercenaryContract.ApplyEliteToMember(brain)
end

function NPCMercenaryContract.ApplyEliteToZombie(zombie)
    if not (zombie and NPCBrainDataBridge and NPCBrainDataBridge.Get) then return nil end
    local brain = NPCBrainDataBridge.Get(zombie)
    if not brain then return nil end

    NPCMercenaryContract.ApplyEliteToBrain(brain)
    if zombie.setHealth and brain.health then pcall(function() zombie:setHealth(brain.health) end) end
    if NPCEntityState and NPCEntityState.SetWeapons then pcall(function() NPCEntityState.SetWeapons(zombie, brain.weapons) end) end
    if NPCEntityState and NPCEntityState.SetInventory then pcall(function() NPCEntityState.SetInventory(zombie, brain.inventory) end) end
    if NPCEntityState and NPCEntityState.SetLoot then pcall(function() NPCEntityState.SetLoot(zombie, brain.loot) end) end
    NPCBrainDataBridge.Update(zombie, brain)
    return brain
end

function NPCMercenaryContract.ApplyEliteToGroup(group)
    if not (NPCMercenaryContract.IsEliteEnabled() and type(group) == "table") then return group end

    group.mercenary = true
    group.mercenaryElite = true
    group.hostile = false
    group.friendly = true
    group.factionSide = "blue"
    group.faction = "blue"
    group.side = "blue"
    group.patrolColor = "blue"
    group.state = group.state or "blue_mercenary_patrol"
    group.program = group.program or {name="Looter", stage="Prepare"}
    if group.program.name == "Raider" or group.program.name == NPCLegacyContractBridge.Program("RAIDER") then group.program.name = "Looter" end

    if type(group.members) == "table" then
        for _, member in pairs(group.members) do
            NPCMercenaryContract.ApplyEliteToMember(member)
        end
    end

    return group
end

function NPCMercenaryContract.IsBlueMercenaryBrain(brain)
    if not brain then return false end
    if NPCBlackMarketBridge and NPCBlackMarketBridge.IsNPCBrain and NPCBlackMarketBridge.IsNPCBrain(brain) then return false end
    if brain.blackMarket == true or brain.blackMarketNPC == true or brain.blackMarketService == true or brain.special == "BlackMarket" then return false end
    if NPCBlackMarketBridge and NPCBlackMarketBridge.IsNoCombatBrain and NPCBlackMarketBridge.IsNoCombatBrain(brain) then return false end
    local side = nil
    if NPCFactionBridge and NPCFactionBridge.GetBrainSide then side = NPCFactionBridge.GetBrainSide(brain) end
    side = side or brain.factionSide or brain.faction or brain.side or brain.patrolColor
    return side == "blue" or brain.mercenary == true
end

function NPCMercenaryContract.IsHiredBy(brain, player)
    local pid = bm_playerId(player)
    if not (brain and pid) then return false end
    return brain.mercenaryHired == true and tostring(brain.mercenaryHiredBy or brain.master) == tostring(pid)
end

function NPCMercenaryContract.ApplyPlayerCommandAuthorityToBrain(brain, pid, reason)
    if type(brain) ~= "table" then return brain end
    brain.commandAuthority = "player"
    brain.playerCommandAuthority = true
    brain.worldCommandDisabled = true
    brain.worldDirectorDisabled = true
    brain.livingWorldDisabled = true
    brain.autonomousWorldDisabled = true
    brain.commandAuthorityReason = reason or brain.commandAuthorityReason or "mercenary_direct"
    brain.master = pid or brain.master or brain.mercenaryHiredBy
    local currentOrderName = type(brain.order) == "table" and tostring(brain.order.name or "") or ""
    brain.program = (currentOrderName == "Hold" or currentOrderName == "Guard") and {name="CompanionGuard", stage="Prepare"} or {name="Companion", stage="Prepare"}
    brain.hostile = false
    brain.friendly = true
    brain.relationshipToPlayer = "hired_bodyguard"
    brain.factionState = "hired_blue_bodyguard"
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
    brain.mercenary = true
    brain.mercenaryHired = true
    brain.mercenaryHiredBy = brain.mercenaryHiredBy or pid
    brain.isPlayerGuard = true
    brain.followPlayer = pid or brain.followPlayer
    brain.guardPlayer = nil
    return brain
end

function NPCMercenaryContract.ApplyPlayerCommandAuthorityToGroup(group, pid, reason)
    if type(group) ~= "table" then return group end
    group.commandAuthority = "player"
    group.playerCommandAuthority = true
    group.worldCommandDisabled = true
    group.worldDirectorDisabled = true
    group.livingWorldDisabled = true
    group.autonomousWorldDisabled = true
    group.commandAuthorityReason = reason or group.commandAuthorityReason or "mercenary_hired"
    group.master = pid or group.master or group.mercenaryHiredBy
    group.mercenary = true
    group.mercenaryHired = true
    group.mercenaryHiredBy = group.mercenaryHiredBy or pid
    group.isPlayerGuard = true
    group.followPlayer = pid or group.followPlayer
    group.guardPlayer = nil
    group.hostile = false
    group.friendly = true
    group.factionSide = "blue"
    group.faction = "blue"
    group.side = "blue"
    group.patrolColor = "blue"
    group.state = "player_commanded"
    group.program = {name="Companion", stage="Prepare"}
    group.roadPatrol = false
    group.checkpointGuard = false
    group.checkpointId = nil
    group.baseOwnedRole = nil
    group.strategicActivityType = nil
    group.strategicActivityState = nil
    group.strategicActivityId = nil
    group.strategicActivityTargetBaseId = nil
    group.strategicActivityTargetGroupId = nil
    group.economyMissionId = nil
    group.targetBaseId = nil
    group.targetClass = nil
    group.battleEnemyGroupId = nil
    group.enemyGroupId = nil
    group.inBattle = false
    group.virtualBattle = false
    if type(group.members) == "table" then
        for _, member in pairs(group.members) do
            NPCMercenaryContract.ApplyPlayerCommandAuthorityToBrain(member, pid, reason)
        end
    end
    return group
end

function NPCMercenaryContract.ReleaseBrain(brain, player, data)
    if type(brain) ~= "table" then return brain end
    data = data or {}
    local pid = bm_playerId(player) or data.master
    if pid and brain.mercenaryHiredBy and tostring(brain.mercenaryHiredBy) ~= tostring(pid) then return brain end

    brain.master = false
    brain.mercenary = true
    brain.mercenaryHired = false
    brain.mercenaryHiredBy = false
    brain.mercenaryHiredByName = false
    brain.commandAuthority = false
    brain.playerCommandAuthority = false
    brain.worldCommandDisabled = false
    brain.worldDirectorDisabled = false
    brain.livingWorldDisabled = false
    brain.autonomousWorldDisabled = false
    brain.commandAuthorityReason = false
    brain.isPlayerGuard = false
    brain.followPlayer = false
    brain.guardPlayer = false
    brain.relationshipToPlayer = "neutral"
    brain.hostile = false
    brain.tasks = {}
    if brain.fsm then
        brain.fsm.targetId = nil
        brain.fsm.targetKind = nil
        brain.fsm.currentThreat = nil
        brain.fsm.lastThreat = nil
    end
    brain.currentThreat = nil
    brain.lastThreat = nil
    brain.targetId = nil
    brain.targetKind = nil
    brain.inBattle = false
    brain.virtualBattle = false
    brain.factionSide = "blue"
    brain.faction = "blue"
    brain.side = "blue"
    brain.patrolColor = "blue"
    brain.factionState = "blue_mercenary"
    brain.program = {name="Looter", stage="Prepare"}
    brain.order = false
    brain.fireMode = false
    brain.rbFireMode = false
    brain.loyaltyForPlayerId = false
    brain.loyaltyForPlayerName = false

    return brain
end

function NPCMercenaryContract.ReleaseGroup(gmd, group, player, data)
    if type(group) ~= "table" then return group end
    data = data or {}
    local pid = bm_playerId(player) or data.master
    if pid and group.mercenaryHiredBy and tostring(group.mercenaryHiredBy) ~= tostring(pid) then return group end

    group.master = false
    group.mercenary = true
    group.mercenaryHired = false
    group.mercenaryHiredBy = false
    group.mercenaryHiredByName = false
    group.commandAuthority = false
    group.playerCommandAuthority = false
    group.worldCommandDisabled = false
    group.worldDirectorDisabled = false
    group.livingWorldDisabled = false
    group.autonomousWorldDisabled = false
    group.commandAuthorityReason = false
    group.isPlayerGuard = false
    group.followPlayer = false
    group.guardPlayer = false
    group.hostile = false
    group.friendly = true
    group.factionSide = "blue"
    group.faction = "blue"
    group.side = "blue"
    group.patrolColor = "blue"
    group.state = "blue_mercenary_group"
    group.program = {name="Looter", stage="Prepare"}
    group.order = false
    group.fireMode = false
    group.rbFireMode = false
    group.loyaltyForPlayerId = false
    group.loyaltyForPlayerName = false
    group.updatedAt = getGameTime and getGameTime():getWorldAgeHours() or group.updatedAt

    if type(group.members) == "table" then
        for _, member in pairs(group.members) do
            NPCMercenaryContract.ReleaseBrain(member, player, data)
        end
    end

    return group
end

function NPCMercenaryContract.HireBrain(brain, player, data)
    if type(brain) ~= "table" then return brain end
    data = data or {}
    NPCMercenaryContract.ApplyEliteToBrain(brain)

    local pid = bm_playerId(player) or data.master
    brain.master = pid
    brain.mercenary = true
    brain.mercenaryHired = true
    brain.mercenaryHiredBy = pid
    brain.mercenaryHiredByName = bm_playerName(player) or data.masterName
    brain.relationshipToPlayer = "hired_bodyguard"
    brain.hostile = false
    brain.tasks = {}
    if brain.fsm then
        brain.fsm.targetId = nil
        brain.fsm.targetKind = nil
        brain.fsm.currentThreat = nil
        brain.fsm.lastThreat = nil
    end
    brain.currentThreat = nil
    brain.lastThreat = nil
    brain.targetId = nil
    brain.targetKind = nil
    brain.factionSide = "blue"
    brain.faction = "blue"
    brain.side = "blue"
    brain.patrolColor = "blue"
    brain.factionState = "hired_blue_bodyguard"
    brain.program = {name="Companion", stage="Prepare"}
    NPCMercenaryContract.ApplyPlayerCommandAuthorityToBrain(brain, pid, "hire")

    bm_setMercenaryDirectOrder(brain, "Follow", {
        master=pid,
        fireMode="Defensive",
        formation=data.formation or "close",
        followDistance=data.followDistance or 0.95,
        note="hired mercenary direct follow"
    }, true, true, true, 10, data.followDistance or 0.95)

    brain.fireMode = brain.order and brain.order.fireMode or brain.fireMode
    brain.rbFireMode = brain.fireMode or brain.rbFireMode

    if NPCLoyaltyBridge and NPCLoyaltyBridge.OnHired then
        NPCLoyaltyBridge.OnHired(brain, player)
    end

    return brain
end

function NPCMercenaryContract.HireGroup(gmd, group, player, data)
    if type(group) ~= "table" then return group end
    data = data or {}
    NPCMercenaryContract.ApplyEliteToGroup(group)

    local pid = bm_playerId(player) or data.master
    group.mercenary = true
    group.mercenaryHired = true
    group.mercenaryHiredBy = pid
    group.mercenaryHiredByName = bm_playerName(player) or data.masterName
    group.isPlayerGuard = true
    group.followPlayer = pid
    group.guardPlayer = nil
    group.hostile = false
    group.friendly = true
    group.factionSide = "blue"
    group.faction = "blue"
    group.side = "blue"
    group.patrolColor = "blue"
    group.state = "hired_blue_bodyguards"
    group.program = {name="Companion", stage="Prepare"}
    NPCMercenaryContract.ApplyPlayerCommandAuthorityToGroup(group, pid, "hire")
    group.order = {
        name="Follow",
        source="mercenary_direct",
        master=pid,
        commandAuthority="player",
        playerCommand=true,
        playerCommandMode="mercenary_direct",
        mercenaryDirect=true,
        directMercenaryOrder=true,
        priority=120,
        fireMode="Defensive",
        formation=data.formation or "close",
        followDistance=data.followDistance or 0.95,
        sticky=true,
        strict=true,
        leash={follow=6.5, guard=10.0, hold=3.0, combat=6.5}
    }
    group.updatedAt = getGameTime and getGameTime():getWorldAgeHours() or group.updatedAt

    if type(group.members) == "table" then
        for index, member in pairs(group.members) do
            if type(member) == "table" and member.memberIndex == nil then member.memberIndex = tonumber(index) or member.memberIndex end
            NPCMercenaryContract.HireBrain(member, player, data)
        end
    end

    if NPCLoyaltyBridge and NPCLoyaltyBridge.EnsureGroup then
        NPCLoyaltyBridge.EnsureGroup(group, player)
    end

    return group
end

function NPCMercenaryContract.ApplyOrderToBrain(brain, player, data)
    if type(brain) ~= "table" then return brain end
    data = data or {}

    local pid = bm_playerId(player) or data.master
    local prevOrder = type(brain.order) == "table" and brain.order or {}
    local explicitOrder = data.orderName ~= nil or data.name ~= nil
    local orderName = bm_normalizeOrderName(data.orderName or data.name or prevOrder.name or "Follow")
    local softOnly = not explicitOrder
        and (data.fireMode ~= nil or data.formation ~= nil or data.followDistance ~= nil)
        and data.anchor == nil
        and data.tactical == nil
    local normalizedFireMode = data.fireMode
    if normalizedFireMode ~= nil then
        normalizedFireMode = bm_normalizeFireMode(normalizedFireMode)
        data.fireMode = normalizedFireMode
    end
    local fireModeCommand = normalizedFireMode ~= nil
    local fireModeInterrupt = fireModeCommand and (normalizedFireMode == "HoldFire" or normalizedFireMode == "MeleeOnly")
    local hardInterrupt = explicitOrder or fireModeInterrupt

    brain.master = pid or brain.master
    brain.mercenary = true
    brain.mercenaryHired = true
    brain.mercenaryHiredBy = brain.mercenaryHiredBy or pid
    brain.hostile = false
    if hardInterrupt then
        brain.tasks = {}
        brain.ai = brain.ai or {}
        brain.ai.manualOrderConsumedIssued = nil
        brain.ai.manualOrderConsumedAtMs = nil
        brain.ai.lastGenerateTaskFrameTick = nil
        brain.ai.forceManualOrderNow = true
        if brain.fsm then
            brain.fsm.targetId = nil
            brain.fsm.targetKind = nil
            brain.fsm.currentThreat = nil
            brain.fsm.lastThreat = nil
            brain.fsm.target = nil
        end
        brain.currentThreat = nil
        brain.lastThreat = nil
        brain.targetId = nil
        brain.targetKind = nil
        brain.target = nil
        brain.enemy = nil
        brain.combatTarget = nil
        brain.radioThreat = nil
        brain._threatCache = nil
        brain._combatTargetCache = nil
        brain.ai = brain.ai or {}
        brain.ai.manualControlUntil = (bm_nowHours()) + ((tonumber(data.interruptSeconds) or 12) / 3600)
        brain.ai.lastManualHardOrderAt = bm_nowHours()
    end
    brain.factionSide = "blue"
    brain.faction = "blue"
    brain.side = "blue"
    brain.patrolColor = "blue"
    NPCMercenaryContract.ApplyPlayerCommandAuthorityToBrain(brain, pid, "player_order")

    if explicitOrder and orderName == "Follow" then
        brain.holdPoint = nil
        brain.guardPoint = nil
        brain.patrolPoint = nil
        brain.returnPoint = nil
    end

    if bm_isPointMercenaryOrderName(orderName) and data.anchor and data.anchor.x and data.anchor.y then
        local anchorCopy = bm_copy(data.anchor)
        if orderName == "Hold" then
            brain.holdPoint = anchorCopy
        elseif orderName == "Guard" then
            brain.guardPoint = anchorCopy
        elseif orderName == "Patrol" then
            brain.patrolPoint = anchorCopy
        elseif orderName == "Return" then
            brain.returnPoint = anchorCopy
            brain.holdPoint = anchorCopy
        elseif orderName == "Loot" or orderName == "LootHouse" or tostring(orderName or ""):find("LootBodies", 1, true) or orderName == "RearmHere" then
            brain.lootPoint = anchorCopy
            brain.storagePoint = brain.storagePoint or anchorCopy
        end
    end

    if orderName == "Loot" or orderName == "LootHouse" then
        NPCMercenaryContract.RestockAndHealBrain(brain)
    end
    local programName = "Companion"
    if orderName == "Hold" or orderName == "Guard" then programName = "CompanionGuard" end
    if hardInterrupt or not brain.program then
        brain.program = {name=programName, stage="Prepare"}
    elseif brain.program and brain.program.name ~= programName and not softOnly then
        brain.program = {name=programName, stage="Prepare"}
    end
    local strictOrder = explicitOrder and bm_isStrictMercenaryOrderName(orderName)
    local playerCommandOrder = explicitOrder and bm_isPlayerMercenaryOrderName(orderName)
    if softOnly and bm_isPlayerCommandedMercenaryBrain(brain) then playerCommandOrder = true end
    local stickyOrder = strictOrder == true
    local interruptSeconds = tonumber(data.interruptSeconds) or (hardInterrupt and (stickyOrder and 30 or 18) or 8)
    local orderFollowDistance = data.followDistance
    if orderName == "Follow" and orderFollowDistance == nil then orderFollowDistance = 0.95 end
    if softOnly and (data.formation ~= nil or data.followDistance ~= nil) then
        brain.tasks = {}
        brain.ai = brain.ai or {}
        brain.ai.forceManualOrderNow = true
        brain.ai.manualOrderConsumedIssued = nil
        brain.ai.manualOrderConsumedSequence = nil
        brain.ai.lastGenerateTaskFrameTick = nil
    end

    do
        local appliedOrder = bm_setMercenaryDirectOrder(brain, orderName, data, hardInterrupt, strictOrder, playerCommandOrder, interruptSeconds, orderFollowDistance)
        if appliedOrder and playerCommandOrder then
            appliedOrder.source = "mercenary_direct"
            appliedOrder.commandAuthority = "player"
            appliedOrder.playerCommand = true
            appliedOrder.playerCommandMode = "mercenary_direct"
            brain.commandAuthority = "player"
            brain.playerCommandAuthority = true
            brain.ai = brain.ai or {}
            brain.ai.playerCommandOrderSequence = tonumber(appliedOrder.sequence) or brain.ai.playerCommandOrderSequence
            brain.ai.playerCommandOrderName = appliedOrder.name
            brain.ai.playerCommandOrderAt = bm_nowHours()
            if bm_isMercenaryTacticalOrderName(appliedOrder.name) then
                appliedOrder.playerTactical = true
                appliedOrder.tacticalMode = appliedOrder.name
                appliedOrder.tacticalSticky = true
                appliedOrder.watchdogIntervalMs = 500
                local profile = bm_getMercenaryTacticalProfile(appliedOrder.name)
                if profile then
                    appliedOrder.tacticalProfile = profile.mode
                    appliedOrder.tacticalStationary = profile.stationary == true
                    appliedOrder.tacticalCombatRange = tonumber(profile.combatRange)
                    appliedOrder.tacticalChaseRange = tonumber(profile.chaseRange)
                    appliedOrder.tacticalSettle = tonumber(profile.settle)
                end
                brain.ai.playerTacticalOrderSequence = tonumber(appliedOrder.sequence) or brain.ai.playerTacticalOrderSequence
                brain.ai.playerTacticalOrderName = appliedOrder.name
                brain.ai.playerTacticalOrderAt = bm_nowHours()
                brain.ai.forceManualOrderNow = true
                brain.ai.lastGenerateTaskFrameTick = nil
            end
        end
        if appliedOrder then
            bm_applyDispatchFields(brain, appliedOrder, orderName, data, hardInterrupt, playerCommandOrder)
        end
        if appliedOrder and data.manualLoot == true then
            appliedOrder.manualLoot = true
            appliedOrder.manualSupplyLoot = data.manualSupplyLoot == true
            appliedOrder.lootBodiesOnly = data.lootBodiesOnly == true
            appliedOrder.lootEquipUpgrades = data.lootEquipUpgrades == true
            appliedOrder.lootTakeWeapons = data.lootTakeWeapons ~= false
            appliedOrder.lootTakeAmmo = data.lootTakeAmmo ~= false
            appliedOrder.lootTakeArmor = data.lootTakeArmor ~= false
            appliedOrder.lootTakeClothing = data.lootTakeClothing ~= false
            appliedOrder.lootTakeMedical = data.lootTakeMedical ~= false
            appliedOrder.lootTakeFood = data.lootTakeFood ~= false
            appliedOrder.lootMaxItems = tonumber(data.lootMaxItems)
            appliedOrder.lootMaxContainers = tonumber(data.lootMaxContainers)
            appliedOrder.lootRadius = tonumber(data.lootRadius)
        elseif appliedOrder then
            appliedOrder.manualLoot = nil
            appliedOrder.manualSupplyLoot = nil
            appliedOrder.lootBodiesOnly = nil
            appliedOrder.lootEquipUpgrades = nil
            appliedOrder.lootTakeWeapons = nil
            appliedOrder.lootTakeAmmo = nil
            appliedOrder.lootTakeArmor = nil
            appliedOrder.lootTakeClothing = nil
            appliedOrder.lootTakeMedical = nil
            appliedOrder.lootTakeFood = nil
            appliedOrder.lootMaxItems = nil
            appliedOrder.lootMaxContainers = nil
            appliedOrder.lootRadius = nil
        end
        if appliedOrder and strictOrder then
            brain.ai = brain.ai or {}
            brain.ai.strictPlayerOrderSequence = tonumber(appliedOrder.sequence) or brain.ai.strictPlayerOrderSequence
            brain.ai.strictPlayerOrderName = appliedOrder.name
            brain.ai.strictPlayerOrderAt = bm_nowHours()
            brain.ai.strictOrderImmediateSequence = tonumber(appliedOrder.sequence) or brain.ai.strictOrderImmediateSequence
            brain.ai.strictOrderImmediateName = appliedOrder.name
            brain.ai.strictOrderImmediateUntil = tonumber(appliedOrder.immediateReapplyUntil) or (bm_nowHours() + (3.2 / 3600))
            brain.ai.strictOrderImmediateReason = "mercenary direct immediate order"
            brain.ai.forceManualOrderNow = true
            brain.ai.lastGenerateTaskFrameTick = nil
        elseif appliedOrder and explicitOrder and not strictOrder then
            if not playerCommandOrder then
                appliedOrder.immediateReapply = nil
                appliedOrder.immediateReapplySequence = nil
                appliedOrder.immediateReapplyUntil = nil
                appliedOrder.immediateReapplyReason = nil
            end
            if brain.ai then
                brain.ai.strictOrderImmediateSequence = nil
                brain.ai.strictOrderImmediateName = nil
                brain.ai.strictOrderImmediateUntil = nil
                brain.ai.strictOrderImmediateReason = nil
                if not playerCommandOrder then brain.ai.forceManualOrderNow = false end
            end
        end
        if not hardInterrupt and brain.order then
            brain.order.interrupt = false
            brain.order.interruptUntil = nil
            brain.order.interruptReason = nil
        end
    end

    brain.fireMode = brain.order and brain.order.fireMode or brain.fireMode
    brain.rbFireMode = brain.fireMode or brain.rbFireMode

    if NPCLoyaltyBridge and NPCLoyaltyBridge.OnOrder then
        NPCLoyaltyBridge.OnOrder(brain, player, data)
    end

    return brain
end

function NPCMercenaryContract.ApplyOrderToGroup(group, player, data)
    if type(group) ~= "table" then return group end
    data = data or {}
    local pid = bm_playerId(player) or data.master
    group.master = pid
    group.mercenaryHired = true
    group.mercenaryHiredBy = group.mercenaryHiredBy or pid
    group.isPlayerGuard = true
    local prevOrder = type(group.order) == "table" and group.order or {}
    local explicitOrder = data.orderName ~= nil or data.name ~= nil
    local orderName = bm_normalizeOrderName(data.orderName or data.name or prevOrder.name or "Follow")
    local normalizedFireMode = data.fireMode
    if normalizedFireMode ~= nil then
        normalizedFireMode = bm_normalizeFireMode(normalizedFireMode)
        data.fireMode = normalizedFireMode
    end
    local fireModeCommand = normalizedFireMode ~= nil
    local fireModeInterrupt = fireModeCommand and (normalizedFireMode == "HoldFire" or normalizedFireMode == "MeleeOnly")
    local hardInterrupt = explicitOrder or fireModeInterrupt
    local strictOrder = explicitOrder and bm_isStrictMercenaryOrderName(orderName)
    local playerCommandOrder = explicitOrder and bm_isPlayerMercenaryOrderName(orderName)
    if not playerCommandOrder and (data._groupOnly == true or fireModeCommand) and NPCMercenaryContract.IsPlayerCommandedGroup and NPCMercenaryContract.IsPlayerCommandedGroup(group) then playerCommandOrder = true end
    local programName = (orderName == "Hold" or orderName == "Guard") and "CompanionGuard" or "Companion"
    if hardInterrupt or not group.program then
        group.program = {name=programName, stage="Prepare"}
    elseif group.program and group.program.name ~= programName and explicitOrder then
        group.program = {name=programName, stage="Prepare"}
    end
    if orderName == "Follow" then
        group.followPlayer = pid
        group.guardPlayer = nil
        group.holdPoint = nil
        group.guardPoint = nil
        group.patrolPoint = nil
        group.returnPoint = nil
    elseif orderName == "Hold" or orderName == "Guard" then
        group.guardPlayer = pid
        group.followPlayer = nil
    elseif bm_isMercenaryTacticalOrderName(orderName) then
        group.guardPlayer = pid
        group.followPlayer = nil
    end
    group.order = bm_copy(prevOrder)
    for k, v in pairs(data) do
        if v ~= nil and string.sub(tostring(k), 1, 1) ~= "_" then group.order[k] = bm_copy(v) end
    end
    if orderName == "Follow" and data.followDistance == nil then group.order.followDistance = 0.95 end
    group.order.master = pid
    group.order.name = orderName
    if orderName == "Follow" then
        group.order.anchor = nil
        group.order.targetType = "player"
        group.order.anchorMode = "player"
        group.order.cursorAnchor = nil
    elseif bm_isPointMercenaryOrderName(orderName) and data.anchor then
        group.order.anchor = bm_copy(data.anchor)
        group.order.targetType = "point"
        group.order.anchorMode = data.anchorMode or data.targetType or "cursor"
        group.order.cursorAnchor = true
    end
    if playerCommandOrder then
        group.order.source = "mercenary_direct"
        group.order.commandAuthority = "player"
        group.order.playerCommand = true
        group.order.playerCommandMode = "mercenary_direct"
        group.order.mercenaryDirect = true
        group.order.directMercenaryOrder = true
        group.commandAuthority = "player"
        group.playerCommandAuthority = true
        group.worldCommandDisabled = true
        group.worldDirectorDisabled = true
        if bm_isMercenaryTacticalOrderName(orderName) then
            group.order.playerTactical = true
            group.order.tacticalMode = orderName
            group.order.tacticalSticky = true
            group.order.watchdogIntervalMs = 520
            local profile = bm_getMercenaryTacticalProfile(orderName)
            if profile then
                group.order.tacticalProfile = profile.mode
                group.order.tacticalStationary = profile.stationary == true
                group.order.tacticalCombatRange = tonumber(profile.combatRange)
                group.order.tacticalChaseRange = tonumber(profile.chaseRange)
                group.order.tacticalSettle = tonumber(profile.settle)
            end
        end
    end
    if bm_isPointMercenaryOrderName(orderName) and data.anchor and data.anchor.x and data.anchor.y then
        local anchorCopy = bm_copy(data.anchor)
        if orderName == "Hold" then
            group.holdPoint = anchorCopy
        elseif orderName == "Guard" then
            group.guardPoint = anchorCopy
        elseif orderName == "Patrol" then
            group.patrolPoint = anchorCopy
        elseif orderName == "Return" then
            group.returnPoint = anchorCopy
            group.holdPoint = anchorCopy
        elseif orderName == "Loot" or orderName == "LootHouse" or tostring(orderName or ""):find("LootBodies", 1, true) or orderName == "RearmHere" then
            group.lootPoint = anchorCopy
            group.storagePoint = group.storagePoint or anchorCopy
        end
    end
    local interruptSeconds = tonumber(data.interruptSeconds) or (hardInterrupt and (strictOrder and 30 or 18) or 8)
    local orderIssued = bm_nowHours()
    group.order.issued = orderIssued
    if hardInterrupt then
        group.order.interrupt = true
        group.order.interruptIssued = orderIssued
        group.order.interruptUntil = orderIssued + (interruptSeconds / 3600)
        group.order.interruptReason = "mercenary order"
    else
        group.order.interrupt = false
        group.order.interruptUntil = nil
        group.order.interruptReason = nil
    end
    if strictOrder then
        group.order.strict = true
        group.order.sticky = true
        group.order.strictReason = "mercenary strict player order"
        group.order.stickyReason = "mercenary player order lock"
        group.order.leash = (orderName == "Follow") and {follow=3.6, guard=9.5, hold=2.8, combat=4.0} or {follow=5.5, guard=9.5, hold=2.8, combat=12.0}
    elseif explicitOrder then
        group.order.strict = nil
        group.order.sticky = nil
        group.order.strictReason = nil
        group.order.stickyReason = nil
        group.order.leash = nil
    end
    local revision = tonumber(data.orderRevision or data.groupOrderRevision or data.orderBatchRevision)
    if revision then
        group.orderRevision = revision
        group.groupOrderRevision = revision
        group.groupOrderBatchId = data.orderBatchId or data.groupOrderBatchId or group.groupOrderBatchId
        group.order.orderRevision = revision
        group.order.groupOrderRevision = revision
        group.order.orderBatchId = data.orderBatchId or data.groupOrderBatchId or group.order.orderBatchId
        group.order.dispatchMode = "mercenary_direct"
        group.order.mercenaryDirect = true
        group.order.directMercenaryOrder = true
        group.order.forceImmediate = true
        group.order.watchdogIntervalMs = tonumber(group.order.watchdogIntervalMs) or (orderName == "Follow" and 240 or 320)
    end
    group.updatedAt = getGameTime and getGameTime():getWorldAgeHours() or group.updatedAt

    if data._groupOnly ~= true and type(group.members) == "table" then
        for index, member in pairs(group.members) do
            if type(member) == "table" and member.memberIndex == nil then member.memberIndex = tonumber(index) or member.memberIndex end
            NPCMercenaryContract.ApplyOrderToBrain(member, player, data)
        end
    end
    if NPCLoyaltyBridge and NPCLoyaltyBridge.EnsureGroup then
        NPCLoyaltyBridge.EnsureGroup(group, player)
    end
    return group
end

local function bm_inventory(playerOrInv)
    if playerOrInv and playerOrInv.getInventory then
        local ok, inv = pcall(function() return playerOrInv:getInventory() end)
        if ok and inv then return inv end
    end
    return playerOrInv
end

local function bm_countItems(inv, itemTypes)
    inv = bm_inventory(inv)
    if not (inv and inv.getItemCountFromTypeRecurse and type(itemTypes) == "table") then return 0 end
    local total = 0
    for _, fullType in ipairs(itemTypes) do
        local ok, count = pcall(function() return inv:getItemCountFromTypeRecurse(fullType) end)
        if ok and count then total = total + (tonumber(count) or 0) end
    end
    return total
end

local function bm_paymentTypeSet(itemTypes)
    local out = {}
    if type(itemTypes) == "table" then
        for _, fullType in ipairs(itemTypes) do
            if fullType ~= nil then
                out[string.lower(tostring(fullType))] = true
                local short = tostring(fullType):match("%.([^%.]+)$")
                if short then out[string.lower(short)] = true end
            end
        end
    end
    return out
end

local function bm_itemText(item, method)
    if not (item and method) then return nil end

    local ok, value = false, nil
    if method == "getFullType" and item.getFullType then
        ok, value = pcall(function() return item:getFullType() end)
    elseif method == "getType" and item.getType then
        ok, value = pcall(function() return item:getType() end)
    elseif method == "getName" and item.getName then
        ok, value = pcall(function() return item:getName() end)
    elseif method == "getDisplayName" and item.getDisplayName then
        ok, value = pcall(function() return item:getDisplayName() end)
    end
    if ok and value ~= nil then return tostring(value) end

    local fn = nil
    local okFn = pcall(function() fn = item[method] end)
    if not (okFn and fn) then return nil end
    ok, value = pcall(function() return fn(item) end)
    if ok and value ~= nil then return tostring(value) end
    return nil
end

local function bm_itemContainer(item)
    if not item then return nil end
    if item.getContainer then
        local ok, container = pcall(function() return item:getContainer() end)
        if ok and container then return container end
    end
    if item.getOutermostContainer then
        local ok, container = pcall(function() return item:getOutermostContainer() end)
        if ok and container then return container end
    end
    return nil
end

local function bm_nestedContainer(item)
    if not item then return nil end
    if item.getInventory then
        local ok, container = pcall(function() return item:getInventory() end)
        if ok and container then return container end
    end
    if item.getItemContainer then
        local ok, container = pcall(function() return item:getItemContainer() end)
        if ok and container then return container end
    end
    return nil
end

local function bm_itemUnitCount(item)
    if not item then return 1 end

    if item.getCount then
        local ok, count = pcall(function() return item:getCount() end)
        count = ok and math.floor(tonumber(count) or 0) or 0
        if count > 1 then return count end
    end
    if item.getCurrentUses then
        local ok, count = pcall(function() return item:getCurrentUses() end)
        count = ok and math.floor(tonumber(count) or 0) or 0
        if count > 1 then return count end
    end
    if item.getUses then
        local ok, count = pcall(function() return item:getUses() end)
        count = ok and math.floor(tonumber(count) or 0) or 0
        if count > 1 then return count end
    end

    return 1
end

local function bm_isJewelryType(text)
    text = string.lower(tostring(text or ""))
    return string.find(text, "ring", 1, true)
        or string.find(text, "necklace", 1, true)
        or string.find(text, "bracelet", 1, true)
        or string.find(text, "earring", 1, true)
        or string.find(text, "wristwatch", 1, true)
        or string.find(text, "bellybutton", 1, true)
        or string.find(text, "nose", 1, true)
        or string.find(text, "кольц", 1, true)
        or string.find(text, "цеп", 1, true)
        or string.find(text, "ожерел", 1, true)
        or string.find(text, "браслет", 1, true)
        or string.find(text, "серь", 1, true)
        or string.find(text, "час", 1, true)
        or string.find(text, "украшен", 1, true)
        or string.find(text, "пирсинг", 1, true)
end

local function bm_paymentItemMatches(item, itemTypes, kind)
    if not item then return false end
    local set = bm_paymentTypeSet(itemTypes)
    local fullType = bm_itemText(item, "getFullType")
    local itemType = bm_itemText(item, "getType")
    local name = bm_itemText(item, "getName") or ""
    local displayName = bm_itemText(item, "getDisplayName") or ""
    local text = tostring(fullType or "") .. " " .. tostring(itemType or "") .. " " .. tostring(name or "") .. " " .. tostring(displayName or "")
    local lowFull = string.lower(tostring(fullType or ""))
    local lowType = string.lower(tostring(itemType or ""))

    if set[lowFull] or set[lowType] then return true end
    if itemType and set[string.lower("Base." .. tostring(itemType))] then return true end

    local lowText = string.lower(text)
    local isGold = string.find(lowText, "gold", 1, true) or string.find(lowText, "золот", 1, true)
    local isSilver = string.find(lowText, "silver", 1, true) or string.find(lowText, "сереб", 1, true)
    if kind == "gold" and not isGold then return false end
    if kind == "silver" and not isSilver then return false end
    return bm_isJewelryType(lowText)
end

local function bm_paymentItemKey(item)
    if not item then return nil end
    if item.getID then
        local ok, id = pcall(function() return item:getID() end)
        if ok and id ~= nil then return "id:" .. tostring(id) end
    end
    return nil
end

local function bm_addPaymentItem(out, seenItems, item, container, itemTypes, kind)
    if not item then return end

    local key = bm_paymentItemKey(item)
    if seenItems then
        if seenItems[item] then return end
        if key and seenItems[key] then return end
    end

    if bm_paymentItemMatches(item, itemTypes, kind) then
        if seenItems then
            seenItems[item] = true
            if key then seenItems[key] = true end
        end
        out[#out + 1] = {item=item, container=bm_itemContainer(item) or container}
    end
end

local function bm_collectPaymentItemsFromContainer(container, itemTypes, kind, out, seen, depth, seenItems)
    if not container or not container.getItems then return end
    depth = tonumber(depth) or 0
    if depth > 5 then return end
    seen = seen or {}
    seenItems = seenItems or {}
    local key = tostring(container)
    if seen[key] then return end
    seen[key] = true

    local okItems, items = pcall(function() return container:getItems() end)
    if not (okItems and items and items.size and items.get) then return end

    local size = 0
    local okSize, gotSize = pcall(function() return items:size() end)
    if okSize then size = tonumber(gotSize) or 0 end
    for i = 0, size - 1 do
        local okGet, item = pcall(function() return items:get(i) end)
        if okGet and item then
            bm_addPaymentItem(out, seenItems, item, container, itemTypes, kind)
            local nested = bm_nestedContainer(item)
            if nested then bm_collectPaymentItemsFromContainer(nested, itemTypes, kind, out, seen, depth + 1, seenItems) end
        end
    end
end

local function bm_collectPaymentItemsFromWornItems(player, itemTypes, kind, out, seenItems)
    if not (player and player.getWornItems) then return end
    local okWorn, worn = pcall(function() return player:getWornItems() end)
    if not (okWorn and worn) then return end
    local inv = nil
    if player.getInventory then
        local okInv, gotInv = pcall(function() return player:getInventory() end)
        if okInv then inv = gotInv end
    end

    local size = 0
    if worn.size then
        local okSize, gotSize = pcall(function() return worn:size() end)
        if okSize then size = tonumber(gotSize) or 0 end
    end

    for i = 0, size - 1 do
        local item = nil
        if worn.getItemByIndex then
            local ok, got = pcall(function() return worn:getItemByIndex(i) end)
            if ok then item = got end
        end
        if not item and worn.get then
            local ok, wornItem = pcall(function() return worn:get(i) end)
            if ok and wornItem then
                if wornItem.getItem then
                    local okItem, got = pcall(function() return wornItem:getItem() end)
                    if okItem then item = got end
                else
                    item = wornItem
                end
            end
        end
        bm_addPaymentItem(out, seenItems, item, inv, itemTypes, kind)
    end
end

local function bm_collectPaymentItems(playerOrInv, itemTypes, kind)
    local out = {}
    local seenItems = {}
    local inv = playerOrInv
    if playerOrInv and playerOrInv.getInventory then
        local okInv, gotInv = pcall(function() return playerOrInv:getInventory() end)
        if okInv and gotInv then inv = gotInv end
        bm_collectPaymentItemsFromWornItems(playerOrInv, itemTypes, kind, out, seenItems)
    end
    bm_collectPaymentItemsFromContainer(inv, itemTypes, kind, out, {}, 0, seenItems)
    return out
end

local function bm_countPaymentItems(inv, itemTypes, kind)
    local exactTotal = bm_countItems(inv, itemTypes)
    local collected = bm_collectPaymentItems(inv, itemTypes, kind)
    if #collected > 0 then
        local total = 0
        for _, entry in ipairs(collected) do
            total = total + bm_itemUnitCount(entry and entry.item)
        end
        if total > 0 then return math.max(total, exactTotal) end
    end
    return exactTotal
end

local function bm_removeItems(inv, itemTypes, count, kind)
    local remaining = tonumber(count) or 0
    if remaining <= 0 then return true end

    local payInv = bm_inventory(inv)
    local collected = bm_collectPaymentItems(inv, itemTypes, kind)
    for _, entry in ipairs(collected) do
        if remaining <= 0 then return true end

        local item = entry and entry.item
        local stackCount = bm_itemUnitCount(item)
        local container = entry and entry.container or payInv
        local removed = false

        if item and stackCount > 1 and item.setCount then
            local take = math.min(remaining, stackCount)
            if take < stackCount then
                local ok = pcall(function() item:setCount(stackCount - take) end)
                if ok then
                    remaining = remaining - take
                    removed = true
                end
            end
        end

        if item and not removed then
            if container and container.Remove then
                local ok = pcall(function() container:Remove(item) end)
                if ok then removed = true end
            end
            if not removed and payInv and payInv.Remove then
                local ok = pcall(function() payInv:Remove(item) end)
                if ok then removed = true end
            end
            if removed then remaining = remaining - math.max(1, stackCount) end
        end
    end
    if remaining <= 0 then return true end

    if not (payInv and payInv.getItemCountFromTypeRecurse and payInv.RemoveOneOf and type(itemTypes) == "table") then return false end
    for _, fullType in ipairs(itemTypes) do
        while remaining > 0 do
            local before = 0
            local okCount, current = pcall(function() return payInv:getItemCountFromTypeRecurse(fullType) end)
            if not okCount or not current or tonumber(current) <= 0 then break end
            before = tonumber(current) or 0

            local removed = false
            local ok = pcall(function() payInv:RemoveOneOf(fullType, true) end)
            if ok and (tonumber(payInv:getItemCountFromTypeRecurse(fullType)) or 0) < before then removed = true end
            if not removed then
                before = tonumber(payInv:getItemCountFromTypeRecurse(fullType)) or 0
                ok = pcall(function() payInv:RemoveOneOf(fullType, false) end)
                if ok and (tonumber(payInv:getItemCountFromTypeRecurse(fullType)) or 0) < before then removed = true end
            end
            if not removed then break end
            remaining = remaining - 1
        end
        if remaining <= 0 then return true end
    end

    return remaining <= 0
end

function NPCMercenaryContract.GetPaymentCounts(player)
    if not player then return {gold=0, silver=0} end
    local gold = bm_countPaymentItems(player, NPCMercenaryContract.GoldJewelry, "gold")
    local silver = 0
    if NPCMercenaryContract.AllowSilverPayment() then
        silver = bm_countPaymentItems(player, NPCMercenaryContract.SilverJewelry, "silver")
    end
    return {gold=gold, silver=silver}
end

function NPCMercenaryContract.HasPayment(player)
    local goldCost = NPCMercenaryContract.GetGoldJewelryCost()
    if goldCost <= 0 then return true end
    if NPCMercenaryContract.AllowSilverPayment() and NPCMercenaryContract.GetSilverJewelryCost() <= 0 then return true end

    if not player then return false end
    local counts = NPCMercenaryContract.GetPaymentCounts(player)
    if (tonumber(counts.gold) or 0) >= goldCost then return true end

    if NPCMercenaryContract.AllowSilverPayment() then
        local silverCost = NPCMercenaryContract.GetSilverJewelryCost()
        if silverCost <= 0 then return true end
        if (tonumber(counts.silver) or 0) >= silverCost then return true end
    end

    return false
end

function NPCMercenaryContract.TakePayment(player)
    local goldCost = NPCMercenaryContract.GetGoldJewelryCost()
    if goldCost <= 0 then return true, "free" end
    if NPCMercenaryContract.AllowSilverPayment() and NPCMercenaryContract.GetSilverJewelryCost() <= 0 then return true, "free" end

    if not (player and player.getInventory) then return false, "no_player" end
    local inv = player:getInventory()
    if not inv then return false, "no_inventory" end

    if bm_countPaymentItems(player, NPCMercenaryContract.GoldJewelry, "gold") >= goldCost then
        if bm_removeItems(player, NPCMercenaryContract.GoldJewelry, goldCost, "gold") then return true, "gold" end
    end

    if NPCMercenaryContract.AllowSilverPayment() then
        local silverCost = NPCMercenaryContract.GetSilverJewelryCost()
        if silverCost <= 0 then return true, "free" end
        if bm_countPaymentItems(player, NPCMercenaryContract.SilverJewelry, "silver") >= silverCost then
            if bm_removeItems(player, NPCMercenaryContract.SilverJewelry, silverCost, "silver") then return true, "silver" end
        end
    end

    return false, "not_enough"
end
