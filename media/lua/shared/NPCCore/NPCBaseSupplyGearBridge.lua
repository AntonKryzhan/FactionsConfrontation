-- NPCBaseSupplyGearBridge.lua
-- Neutral shared helper for rebuilding donated weapon kits on materialized NPCs.
-- attachments on materialized NPCs. Safe fallback: if a part cannot be
-- restored, the base weapon is still created normally.

NPCBaseSupplyGearBridge = NPCBaseSupplyGearBridge or {}
NPCBaseSupplyGearBridge.Version = 1

local function bbsg_copy(value, depth)
    depth = depth or 0
    if depth > 5 then return nil end
    if type(value) ~= "table" then return value end
    local ret = {}
    for k, v in pairs(value) do
        local tk = type(k)
        local tv = type(v)
        if (tk == "string" or tk == "number" or tk == "boolean") and tv ~= "function" and tv ~= "userdata" and tv ~= "thread" then
            if tv == "table" then ret[k] = bbsg_copy(v, depth + 1) else ret[k] = v end
        end
    end
    return ret
end

local function bbsg_lower(value)
    if not value then return "" end
    return string.lower(tostring(value))
end

local function bbsg_shortType(fullType)
    local value = tostring(fullType or "")
    local _, _, short = string.find(value, "%.([^%.]+)$")
    return short or value
end

local function bbsg_instance(fullType)
    if not fullType or fullType == "" or fullType == false then return nil end
    if NPCCompatibilityBridge and NPCCompatibilityBridge.InstanceItem then
        local ok, item = pcall(function() return NPCCompatibilityBridge.InstanceItem(fullType) end)
        if ok and item then return item end
    end
    if InventoryItemFactory and InventoryItemFactory.CreateItem then
        local ok, item = pcall(function() return InventoryItemFactory.CreateItem(fullType) end)
        if ok and item then return item end
    end
    return nil
end

local function bbsg_partMountsOn(part, weapon, kit)
    if not part or not weapon then return false end
    local mountText = bbsg_lower(kit and kit.mountOn)
    if mountText == "" and part.getMountOn then
        local ok, mount = pcall(function() return part:getMountOn() end)
        if ok and mount then mountText = bbsg_lower(mount) end
    end
    if mountText == "" then return true end

    local weaponFull = nil
    local weaponShort = nil
    local okFull, full = pcall(function() return weapon:getFullType() end)
    if okFull then weaponFull = full end
    local okType, wtype = pcall(function() return weapon:getType() end)
    if okType then weaponShort = wtype end
    weaponFull = weaponFull or (kit and kit.weaponFullType) or (kit and kit.fullType)
    weaponShort = weaponShort or bbsg_shortType(weaponFull)

    return string.find(mountText, bbsg_lower(weaponFull), 1, true) ~= nil
        or string.find(mountText, bbsg_lower(weaponShort), 1, true) ~= nil
end

local function bbsg_applyCondition(item, condition, maxCondition)
    if not item then return end
    local c = tonumber(condition)
    local max = tonumber(maxCondition)
    if c and item.setCondition then pcall(function() item:setCondition(c) end) end
    if max and item.setConditionMax then pcall(function() item:setConditionMax(max) end) end
end

function NPCBaseSupplyGearBridge.FindKit(brain, fullType, slot)
    if type(brain) ~= "table" then return nil end
    fullType = tostring(fullType or "")

    local weapon = nil
    if type(brain.weapons) == "table" then
        if slot and type(brain.weapons[slot]) == "table" then
            weapon = brain.weapons[slot]
        end
        if not weapon then
            for _, key in ipairs({"primary", "secondary", "melee"}) do
                local candidate = brain.weapons[key]
                if type(candidate) == "table" and tostring(candidate.name or "") == fullType then
                    weapon = candidate
                    slot = key
                    break
                elseif type(candidate) == "string" and tostring(candidate) == fullType then
                    slot = key
                    break
                end
            end
        end
    end

    if type(weapon) == "table" and type(weapon.baseSupplyKit) == "table" then
        return bbsg_copy(weapon.baseSupplyKit)
    end

    if type(brain.baseGearWeaponKits) == "table" then
        if slot and type(brain.baseGearWeaponKits[slot]) == "table" then
            return bbsg_copy(brain.baseGearWeaponKits[slot])
        end
        for _, kit in pairs(brain.baseGearWeaponKits) do
            if type(kit) == "table" and tostring(kit.fullType or "") == fullType then
                return bbsg_copy(kit)
            end
        end
    end

    if type(brain.baseGear) == "table" and type(brain.baseGear.weaponKit) == "table" then
        local kit = brain.baseGear.weaponKit
        if tostring(kit.fullType or "") == fullType then return bbsg_copy(kit) end
    end

    return nil
end

function NPCBaseSupplyGearBridge.ApplyKitToItem(item, kit)
    if not item or type(kit) ~= "table" then return item end

    bbsg_applyCondition(item, kit.condition, kit.maxCondition)

    local loadedAmmo = tonumber(kit.loadedAmmo)
    if loadedAmmo and loadedAmmo > 0 and item.setCurrentAmmoCount then
        pcall(function() item:setCurrentAmmoCount(loadedAmmo) end)
    end

    if type(kit.attachments) == "table" and item.attachWeaponPart then
        local used = {}
        for _, partInfo in ipairs(kit.attachments) do
            if type(partInfo) == "table" and partInfo.fullType then
                local partType = tostring(partInfo.partType or "")
                if partType == "" or not used[partType] then
                    local part = bbsg_instance(partInfo.fullType)
                    if part then
                        bbsg_applyCondition(part, partInfo.condition, partInfo.maxCondition)
                        if bbsg_partMountsOn(part, item, partInfo) then
                            local ok = pcall(function() item:attachWeaponPart(part) end)
                            if ok and partType ~= "" then used[partType] = true end
                        end
                    end
                end
            end
        end
    end

    return item
end

function NPCBaseSupplyGearBridge.InstanceItem(fullType, brainOrZombie, slot)
    local item = bbsg_instance(fullType)
    if not item then return nil end

    local brain = brainOrZombie
    if brainOrZombie and brainOrZombie.getModData and NPCBrainData and NPCBrainData.Get then
        local ok, b = pcall(function() return NPCBrainData.Get(brainOrZombie) end)
        if ok then brain = b end
    end

    local kit = NPCBaseSupplyGearBridge.FindKit(brain, fullType, slot)
    if kit then
        NPCBaseSupplyGearBridge.ApplyKitToItem(item, kit)
    end

    return item
end

print("[NPCBaseSupplyGearBridge] Firearms Jay weapon kit helper enabled")
