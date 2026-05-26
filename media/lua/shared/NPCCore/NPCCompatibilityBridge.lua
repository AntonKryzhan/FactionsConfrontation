NPCCompatibilityBridge = NPCCompatibilityBridge or {}

require "NPCCore/NPCLegacyContractBridge"

local NPC_COMPAT_LEGACY_OPTIONS_ID = NPCLegacyContractBridge.Sandbox.main
local NPC_COMPAT_EQUIP_EVENT_KEYS = {
    guard = NPCLegacyContractBridge.Keys.EQUIP_EVENT_GUARD,
    guardHand = NPCLegacyContractBridge.Keys.EQUIP_EVENT_GUARD_HAND,
    guardItem = NPCLegacyContractBridge.Keys.EQUIP_EVENT_GUARD_ITEM,
    guardAt = NPCLegacyContractBridge.Keys.EQUIP_EVENT_GUARD_AT,
    error = NPCLegacyContractBridge.Keys.EQUIP_EVENT_ERROR,
    errorHand = NPCLegacyContractBridge.Keys.EQUIP_EVENT_ERROR_HAND,
    errorAt = NPCLegacyContractBridge.Keys.EQUIP_EVENT_ERROR_AT
}

-- compatibility wrappers

local getGameVersion = function()
    return getCore():getGameVersion():getMajor()
end

NPCCompatibilityBridge.GetGameVersion = getGameVersion

local legacyItemMap = {}
legacyItemMap["Base.WineOpen"]                  = "Base.WineEmpty"
legacyItemMap["Base.BaseballBat_Nails"]         = "Base.BaseballBatNails"
legacyItemMap["Base.BaseballBat_RailSpike"]     = "Base.BaseballBatNails"
legacyItemMap["Base.BaseballBat_Sawblade"]      = "Base.BaseballBatNails"
legacyItemMap["Base.BaseballBat_Spiked"]        = "Base.BaseballBatNails"
legacyItemMap["Base.WaterBottle"]               = "Base.WaterBottleFull"
legacyItemMap["Base.Whiskey"]                   = "Base.WhiskeyFull"
legacyItemMap["Base.Plank_Nails"]               = "Base.PlankNail"
legacyItemMap["Base.BaconBits"]                 = "farming.BaconBits"
legacyItemMap["Base.SpearShort"]                = "Base.WoodenLance"
legacyItemMap["Base.GuitarElectric"]            = "Base.GuitarElectricRed"
legacyItemMap["Base.HandShovel"]                = "farming.HandShovel"
legacyItemMap["Base.BroccoliBagSeed2"]          = "farming.BroccoliBagSeed"
legacyItemMap["Base.CabbageBagSeed2"]           = "farming.CabbageBagSeed"
legacyItemMap["Base.CarrotBagSeed2"]            = "farming.CarrotBagSeed"
legacyItemMap["Base.PotatoBagSeed2"]            = "farming.PotatoBagSeed"
legacyItemMap["Base.RedRadishBagSeed2"]         = "farming.RedRadishBagSeed"
legacyItemMap["Base.StrewberrieBagSeed2"]       = "farming.StrewberrieBagSeed"
legacyItemMap["Base.TomatoBagSeed2"]            = "farming.TomatoBagSeed"
legacyItemMap["Base.CigaretteSingle"]           = "Base.Cigarettes"
legacyItemMap["Base.WateredCan"]                = "farming.WateredCan"
legacyItemMap["Base.TireIron"]                  = "Base.LugWrench"
legacyItemMap["Base.Ratchet"]                   = "Base.Wrench"
legacyItemMap["Base.LightBulbBox"]              = "Base.LightBulb"
legacyItemMap["Base.Toolbox_Mechanic"]          = "Base.Toolbox"
legacyItemMap["Base.Bag_Satchel_Medical"]       = "Base.Bag_Satchel"
legacyItemMap["Base.GuitarElectricBass"]        = "Base.GuitarElectricBassBlack"
legacyItemMap["Base.PiePumpkin"]                = "Base.PieApple"
legacyItemMap["Base.CakeCarrot"]                = "Base.PieApple"
legacyItemMap["Base.EggOmlette"]                = "Base.Pancakes"
legacyItemMap["Base.PiePumpkin"]                = "Base.PieApple"
legacyItemMap["Base.PiePumpkin"]                = "Base.PieApple"



NPCCompatibilityBridge.LegacyItemMap = legacyItemMap

NPCCompatibilityBridge.GetLegacyItem = function(itemFullType)
    if getGameVersion() < 42 then
        local map = NPCCompatibilityBridge.LegacyItemMap
        if map[itemFullType] then
            return map[itemFullType]
        end
    end
    return itemFullType
end

NPCCompatibilityBridge.GetClickedSquare = function()
    if getGameVersion() >= 42 then
        local fetch = ISWorldObjectContextMenu.fetchVars
        return fetch.clickedSquare
    else
        return clickedSquare
    end
end

NPCCompatibilityBridge.GetGuardpostKey = function()
    if getGameVersion() >= 42 then
        local options = PZAPI.ModOptions:getOptions(NPC_COMPAT_LEGACY_OPTIONS_ID)
        return options:getOption("POSTS"):getValue()
    else
        return getCore():getKey("POSTS")
    end
end

NPCCompatibilityBridge.InstanceItem = function(itemFullType)
    if not itemFullType or itemFullType == "" or itemFullType == false then
        return nil
    end

    if getGameVersion() >= 42 then
        local ok, item = pcall(function()
            return instanceItem(itemFullType)
        end)
        if ok then
            return item
        end
        return nil
    else
        local itemFullTypeLegacy = NPCCompatibilityBridge.GetLegacyItem(itemFullType) or itemFullType
        if not itemFullTypeLegacy or itemFullTypeLegacy == "" or itemFullTypeLegacy == false then
            return nil
        end

        local ok, item = pcall(function()
            return InventoryItemFactory.CreateItem(itemFullTypeLegacy)
        end)
        if ok and item then
            return item
        end

        if itemFullTypeLegacy ~= itemFullType then
            ok, item = pcall(function()
                return InventoryItemFactory.CreateItem(itemFullType)
            end)
            if ok then
                return item
            end
        end

        return nil
    end
end

NPCCompatibilityBridge.Splash = function(bandit, item, zombie)
    if getGameVersion() >= 42 then
        local splatNo = item:getSplatNumber()
        for i=0, splatNo do
            bandit:splatBlood(3, 0.3)
        end
        bandit:splatBloodFloorBig()
        bandit:playBloodSplatterSound()
    else
        SwipeStatePlayer.splash(bandit, item, zombie)
    end
end

NPCCompatibilityBridge.PlayerVoiceSound = function(player, sound)
    if getGameVersion() >= 42 then
        player:playerVoiceSound(sound)
    else
        -- not implemented
    end
end

local function bc_isTheStarActive()
    if not getActivatedMods then return false end
    local ok, active = pcall(function()
        local mods = getActivatedMods()
        return mods and mods:contains("TheStar")
    end)
    return ok and active == true
end

local function bc_isIsoPlayer(character)
    if not character or not instanceof then return false end
    local ok, result = pcall(function()
        return instanceof(character, "IsoPlayer")
    end)
    return ok and result == true
end

local function bc_recordEquipGuard(character, hand, item, reason)
    local md = nil
    pcall(function()
        md = character and character:getModData() or nil
    end)
    if md then
        md[NPC_COMPAT_EQUIP_EVENT_KEYS.guard] = tostring(reason or "guarded")
        md[NPC_COMPAT_EQUIP_EVENT_KEYS.guardHand] = tostring(hand or "unknown")
        md[NPC_COMPAT_EQUIP_EVENT_KEYS.guardItem] = item and item.getFullType and item:getFullType() or tostring(item)
        md[NPC_COMPAT_EQUIP_EVENT_KEYS.guardAt] = getTimestampMs and getTimestampMs() or 0
    end
end

NPCCompatibilityBridge.IsTheStarActive = bc_isTheStarActive
NPCCompatibilityBridge.IsIsoPlayer = bc_isIsoPlayer

NPCCompatibilityBridge.SafeSetPrimaryHandItem = function(character, item)
    if not character then return false end
    local current = nil
    pcall(function()
        current = character:getPrimaryHandItem()
    end)
    if current == item then return true end

    local ok, err = pcall(function()
        character:setPrimaryHandItem(item)
    end)
    if not ok then
        local md = nil
        pcall(function()
            md = character:getModData()
        end)
        if md then
            md[NPC_COMPAT_EQUIP_EVENT_KEYS.error] = tostring(err)
            md[NPC_COMPAT_EQUIP_EVENT_KEYS.errorHand] = "primary"
            md[NPC_COMPAT_EQUIP_EVENT_KEYS.errorAt] = getTimestampMs and getTimestampMs() or 0
        end
        return false
    end
    return true
end

NPCCompatibilityBridge.SafeSetSecondaryHandItem = function(character, item)
    if not character then return false end
    local current = nil
    pcall(function()
        current = character:getSecondaryHandItem()
    end)
    if current == item then return true end

    -- TheStar/WCI equip events are guarded on the client side in ModPatches/TheStar.lua.
    -- Do not block the actual NPC hand state here: some NPC actions legitimately
    -- need a secondary item, and pcall below prevents a third-party event crash from
    -- escaping into the NPC update loop.
    if bc_isTheStarActive() and not bc_isIsoPlayer(character) then
        bc_recordEquipGuard(character, "secondary", item, "TheStar non-player OnEquipSecondary protected")
    end

    local ok, err = pcall(function()
        character:setSecondaryHandItem(item)
    end)
    if not ok then
        local md = nil
        pcall(function()
            md = character:getModData()
        end)
        if md then
            md[NPC_COMPAT_EQUIP_EVENT_KEYS.error] = tostring(err)
            md[NPC_COMPAT_EQUIP_EVENT_KEYS.errorHand] = "secondary"
            md[NPC_COMPAT_EQUIP_EVENT_KEYS.errorAt] = getTimestampMs and getTimestampMs() or 0
        end
        return false
    end
    return true
end

NPCCompatibilityBridge.StartMuzzleFlash = function(shooter)
    if getGameVersion() >= 42 then
        local square = shooter:getSquare()
        shooter:startMuzzleFlash() -- it does not work in b42 apparently, so here is how to do this now:
        shooter:setMuzzleFlashDuration(getTimestampMs())
        local lightSource = IsoLightSource.new(square:getX(), square:getY(), square:getZ(), 0.8, 0.8, 0.7, 18, 2)
        getCell():addLamppost(lightSource)
    else
        shooter:startMuzzleFlash()
    end
end

NPCCompatibilityBridge.IsReanimatedForGrappleOnly = function(zombie)
    if getGameVersion() >= 42 then
        return zombie:isReanimatedForGrappleOnly()
    else
        return false
    end
end

NPCCompatibilityBridge.AddZombiesInOutfit = function(x, y, z, outfit, femaleChance, crawler, isFallOnFront, isFakeDead, knockedDown, isInvulnerable, isSitting, health)
    local zombieList
    if getGameVersion() >= 42 then
        zombieList = addZombiesInOutfit(x, y, z, 1, outfit, femaleChance, crawler, isFallOnFront, isFakeDead, knockedDown, isInvulnerable, isSitting, health)
    else
        zombieList = addZombiesInOutfit(x, y, z, 1, outfit, femaleChance, crawler, isFallOnFront, isFakeDead, knockedDown, health)
    end
    return zombieList
end

NPCCompatibilityBridge.AddId = function(zombie, fullname)
    if getGameVersion() >= 42 then
        local itemName = "Base.IDcard"
        if zombie:isFemale() then itemName = "Base.IDcard_Female" end
        local item = instanceItem(itemName)
        item:setName("ID Card:" .. fullname)
        zombie:addItemToSpawnAtDeath(item)
    else
        local item = InventoryItemFactory.CreateItem("Base.KeyRing")
        item:setName(fullname .. " Key Ring")
        zombie:addItemToSpawnAtDeath(item)
    end
end

NPCCompatibilityBridge.SurpressZombieSounds = function(bandit)
    if getGameVersion() >= 42 then
        bandit:getEmitter():stopSoundByName(bandit:getVoiceSoundName())
        bandit:getEmitter():stopSoundByName(bandit:getBiteSoundName())
    else
        bandit:getEmitter():stopSoundByName("MaleZombieCombined")
        bandit:getEmitter():stopSoundByName("FemaleZombieCombined")
    end
end

NPCCompatibilityBridge.HaveRoofFull = function(square)
    if getGameVersion() >= 42 then
        return square:haveRoofFull()
    else
        return true
    end
end
