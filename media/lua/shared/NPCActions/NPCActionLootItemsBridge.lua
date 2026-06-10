NPCActionLootItemsBridge = NPCActionLootItemsBridge or {}
require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCPersistentNPCBridge"
require "NPCCore/NPCPostCombatLootBridge"

local NPC_ACTION_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
NPCEntity = NPCEntity or NPC_ACTION_LEGACY_GLOBALS.Get("Entity")
NPCBrainData = NPCBrainData or NPC_ACTION_LEGACY_GLOBALS.Get("Brain")


local function acceptAnyItem(item)
    return item ~= nil
end

local function faceTask(zombie, task)
    if zombie and task and task.x and task.y then
        zombie:faceLocation(task.x, task.y)
    end
end

local function refreshDeathItems(zombie)
    if NPCEntity and NPCEntity.UpdateItemsToSpawnAtDeath then
        NPCEntity.UpdateItemsToSpawnAtDeath(zombie)
    end
end

local function syncRuntimeLootState(zombie)
    if not zombie then return end
    refreshDeathItems(zombie)

    local brain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(zombie) or nil
    if not brain then return end

    if NPCPersistentNPCBridge then
        if NPCPersistentNPCBridge.BuildInventoryLite then
            local okInventory, inventoryLite = pcall(function() return NPCPersistentNPCBridge.BuildInventoryLite(zombie) end)
            if okInventory then brain.inventoryLite = inventoryLite end
        end
        if NPCPersistentNPCBridge.BuildAmmoLite then
            local okAmmo, ammo = pcall(function() return NPCPersistentNPCBridge.BuildAmmoLite(zombie, brain) end)
            if okAmmo then brain.ammo = ammo end
        end
        if NPCPersistentNPCBridge.BuildCurrentWeapon then
            local okWeapon, currentWeapon = pcall(function() return NPCPersistentNPCBridge.BuildCurrentWeapon(zombie, brain) end)
            if okWeapon then brain.currentWeapon = currentWeapon end
        end
        if NPCPersistentNPCBridge.BuildWornLite then
            local okWorn, wornLite = pcall(function() return NPCPersistentNPCBridge.BuildWornLite(zombie, brain) end)
            if okWorn then
                brain.wornLite = wornLite
                brain.gearLite = wornLite
            end
        end
    end

    if NPCEntity and NPCEntity.ForceSyncPart and brain.id then
        NPCEntity.ForceSyncPart(zombie, {id=brain.id, weapons=brain.weapons, inventory=brain.inventory, inventoryLite=brain.inventoryLite, wornLite=brain.wornLite, gearLite=brain.gearLite, loot=brain.loot, currentWeapon=brain.currentWeapon, ammo=brain.ammo})
    end
end

local function getTaskSquare(task)
    if not task or not task.x or not task.y then return nil end
    local cell = getCell()
    if not cell then return nil end
    return cell:getGridSquare(task.x, task.y, task.z or 0)
end

local function collectContainerItems(container, task)
    local items = ArrayList.new()
    if not container then return items end

    local prioritized = task and (task.postCombatLoot or task.manualSupplyLoot or task.lootMaxItems or task.lootEquipUpgrades or task.lootNeed)
    local maxScan = nil
    if prioritized then
        maxScan = tonumber(task.lootMaxScanItems) or math.max((tonumber(task.lootMaxItems) or 8) * 4, 24)
        maxScan = math.max(8, math.min(maxScan, 80))
    end

    if prioritized and container.getItems then
        local okDirect, direct = pcall(function() return container:getItems() end)
        if okDirect and direct then
            local n = math.min(tonumber(direct:size()) or 0, maxScan or 32)
            for i = 0, n - 1 do
                local item = direct:get(i)
                if item then items:add(item) end
            end
            return items
        end
    end

    if container.getAllEvalRecurse then
        if prioritized and maxScan then
            local added = 0
            pcall(function()
                container:getAllEvalRecurse(function(item)
                    if not item or added >= maxScan then return false end
                    added = added + 1
                    return true
                end, items)
            end)
        else
            container:getAllEvalRecurse(acceptAnyItem, items)
        end
    end
    return items
end

local function transferItem(container, inventory, item)
    if not container or not inventory or not item then return false end
    container:Remove(item)
    if container.removeItemOnServer then
        container:removeItemOnServer(item)
    end
    inventory:AddItem(item)
    return true
end

local function lootItemText(item)
    if not item then return "" end
    local parts = {}
    if item.getFullType then
        local ok, value = pcall(function() return item:getFullType() end)
        if ok and value then parts[#parts + 1] = tostring(value) end
    end
    if item.getType then
        local ok, value = pcall(function() return item:getType() end)
        if ok and value then parts[#parts + 1] = tostring(value) end
    end
    if item.getDisplayName then
        local ok, value = pcall(function() return item:getDisplayName() end)
        if ok and value then parts[#parts + 1] = tostring(value) end
    end
    return string.lower(table.concat(parts, " "))
end

local function lootItemFullType(item)
    if not item or not item.getFullType then return nil end
    local ok, value = pcall(function() return item:getFullType() end)
    if ok then return value end
    return nil
end

local function lootIsWeapon(item, text)
    if not item then return false end
    if item.IsWeapon then
        local ok, value = pcall(function() return item:IsWeapon() end)
        if ok and value == true then return true end
    end
    if instanceof and instanceof(item, "HandWeapon") then return true end
    text = text or lootItemText(item)
    return string.find(text, "rifle", 1, true) ~= nil
        or string.find(text, "pistol", 1, true) ~= nil
        or string.find(text, "shotgun", 1, true) ~= nil
        or string.find(text, "gun", 1, true) ~= nil
        or string.find(text, "knife", 1, true) ~= nil
        or string.find(text, "machete", 1, true) ~= nil
        or string.find(text, "axe", 1, true) ~= nil
        or string.find(text, "bat", 1, true) ~= nil
end

local function lootIsFirearm(item, text)
    if item then
        if item.isAimedFirearm then
            local ok, value = pcall(function() return item:isAimedFirearm() end)
            if ok and value == true then return true end
        end
        if item.isRanged then
            local ok, value = pcall(function() return item:isRanged() end)
            if ok and value == true then return true end
        end
    end
    text = text or lootItemText(item)
    return string.find(text, "rifle", 1, true) ~= nil
        or string.find(text, "pistol", 1, true) ~= nil
        or string.find(text, "shotgun", 1, true) ~= nil
        or string.find(text, "revolver", 1, true) ~= nil
end

local function lootIsAmmo(item, text)
    text = text or lootItemText(item)
    return string.find(text, "ammo", 1, true) ~= nil
        or string.find(text, "bullet", 1, true) ~= nil
        or string.find(text, "shell", 1, true) ~= nil
        or string.find(text, "round", 1, true) ~= nil
        or string.find(text, "magazine", 1, true) ~= nil
        or string.find(text, "clip", 1, true) ~= nil
end

local function lootIsMedical(item, text)
    text = text or lootItemText(item)
    return string.find(text, "bandage", 1, true) ~= nil
        or string.find(text, "disinfect", 1, true) ~= nil
        or string.find(text, "suture", 1, true) ~= nil
        or string.find(text, "firstaid", 1, true) ~= nil
        or string.find(text, "pills", 1, true) ~= nil
end

local function lootIsFoodWater(item, text)
    if item then
        if item.IsFood then
            local ok, value = pcall(function() return item:IsFood() end)
            if ok and value == true then return true end
        end
        if item.isWaterSource then
            local ok, value = pcall(function() return item:isWaterSource() end)
            if ok and value == true then return true end
        end
    end
    text = text or lootItemText(item)
    return string.find(text, "water", 1, true) ~= nil
        or string.find(text, "canned", 1, true) ~= nil
        or string.find(text, "food", 1, true) ~= nil
        or string.find(text, "soda", 1, true) ~= nil
        or string.find(text, "chips", 1, true) ~= nil
end

local function lootArmorScore(item, text)
    if not item then return 0 end
    local score = 0
    if item.getBiteDefense then
        local ok, value = pcall(function() return item:getBiteDefense() end)
        if ok then score = score + (tonumber(value) or 0) end
    end
    if item.getScratchDefense then
        local ok, value = pcall(function() return item:getScratchDefense() end)
        if ok then score = score + ((tonumber(value) or 0) * 0.65) end
    end
    if item.getBulletDefense then
        local ok, value = pcall(function() return item:getBulletDefense() end)
        if ok then score = score + ((tonumber(value) or 0) * 1.2) end
    end
    if score > 0 then return score end
    text = text or lootItemText(item)
    if string.find(text, "vest", 1, true) then return 55 end
    if string.find(text, "armor", 1, true) or string.find(text, "armour", 1, true) then return 50 end
    if string.find(text, "helmet", 1, true) then return 40 end
    if string.find(text, "jacket", 1, true) then return 22 end
    if string.find(text, "leather", 1, true) then return 18 end
    return 0
end

local function lootBodyLocation(item)
    if not item or not item.getBodyLocation then return nil end
    local ok, location = pcall(function() return item:getBodyLocation() end)
    if not ok or not location then return nil end
    location = tostring(location)
    if location == "" or location == "None" or location == "null" then return nil end
    return location
end

local function lootConditionScore(item)
    if not item then return 0 end
    local condition = nil
    local maxCondition = nil
    if item.getCondition then
        local ok, value = pcall(function() return item:getCondition() end)
        if ok then condition = tonumber(value) end
    end
    if item.getConditionMax then
        local ok, value = pcall(function() return item:getConditionMax() end)
        if ok then maxCondition = tonumber(value) end
    end
    if condition and maxCondition and maxCondition > 0 then
        return math.max(0, math.min(1, condition / maxCondition)) * 18
    end
    if condition then return math.max(0, math.min(condition, 20)) * 0.6 end
    return 0
end

local function lootNumericItemValue(item, getterName, weight)
    if not item or not getterName or not item[getterName] then return 0 end
    local ok, value = pcall(function() return item[getterName](item) end)
    if not ok then return 0 end
    return (tonumber(value) or 0) * (weight or 1)
end

local function lootWearPenalty(item)
    if not item then return 0 end
    local penalty = 0
    penalty = penalty + math.min(12, math.max(0, lootNumericItemValue(item, "getDirtyness", 0.08)))
    penalty = penalty + math.min(14, math.max(0, lootNumericItemValue(item, "getBloodLevel", 0.07)))
    return penalty
end

local function lootClothingScore(item, text)
    if not item then return 0 end
    local location = lootBodyLocation(item)
    if not location then return 0 end

    text = text or lootItemText(item)
    local score = 18 + lootConditionScore(item)
    score = score + lootArmorScore(item, text)
    score = score + lootNumericItemValue(item, "getInsulation", 10)
    score = score + lootNumericItemValue(item, "getWindresistance", 8)
    score = score + lootNumericItemValue(item, "getWaterResistance", 0.25)

    local loc = string.lower(location)
    if string.find(loc, "torso", 1, true) or string.find(loc, "jacket", 1, true) then score = score + 10 end
    if string.find(loc, "head", 1, true) then score = score + 8 end
    if string.find(loc, "feet", 1, true) or string.find(loc, "shoes", 1, true) then score = score + 8 end
    if string.find(loc, "hands", 1, true) or string.find(loc, "gloves", 1, true) then score = score + 6 end
    if string.find(loc, "legs", 1, true) or string.find(loc, "pants", 1, true) then score = score + 6 end
    if string.find(loc, "back", 1, true) then score = score + 10 end

    if string.find(text, "bulletproof", 1, true) or string.find(text, "kevlar", 1, true) then score = score + 28 end
    if string.find(text, "military", 1, true) or string.find(text, "police", 1, true) then score = score + 12 end
    if string.find(text, "boots", 1, true) then score = score + 10 end
    if string.find(text, "bag", 1, true) or string.find(text, "backpack", 1, true) then score = score + 16 end
    if string.find(text, "jacket", 1, true) or string.find(text, "coat", 1, true) then score = score + 8 end

    score = score - lootWearPenalty(item)
    if score < 0 then return 0 end
    return score
end

local function lootWeaponScore(item, text)
    if not item or not lootIsWeapon(item, text) then return 0 end
    local score = lootIsFirearm(item, text) and 120 or 78
    if item.getMaxDamage then
        local ok, value = pcall(function() return item:getMaxDamage() end)
        if ok then score = score + ((tonumber(value) or 0) * 18) end
    end
    if item.getMinDamage then
        local ok, value = pcall(function() return item:getMinDamage() end)
        if ok then score = score + ((tonumber(value) or 0) * 8) end
    end
    if item.getMaxRange then
        local ok, value = pcall(function() return item:getMaxRange() end)
        if ok then score = score + ((tonumber(value) or 0) * 1.5) end
    end
    if item.getCondition then
        local ok, value = pcall(function() return item:getCondition() end)
        if ok then score = score + ((tonumber(value) or 0) * 0.4) end
    end
    return score
end

local function lootCandidateScore(zombie, item, task)
    if not item then return 0 end
    if not task or not (task.postCombatLoot or task.lootMaxItems or task.lootEquipUpgrades or task.lootNeed) then return 1 end
    local text = lootItemText(item)
    local weaponScore = lootWeaponScore(item, text)
    if weaponScore > 0 then
        if task.lootTakeWeapons == false then return 0 end
        return weaponScore
    end
    if lootIsAmmo(item, text) then
        if task.lootTakeAmmo == false then return 0 end
        return 76
    end
    local clothingScore = lootClothingScore(item, text)
    if clothingScore > 0 then
        if task.lootTakeArmor == false or task.lootTakeClothing == false then return 0 end
        return 52 + clothingScore
    end
    if lootIsMedical(item, text) then
        if task.lootTakeMedical == false then return 0 end
        return 54
    end
    if lootIsFoodWater(item, text) then
        if task.lootTakeFood == false then return 0 end
        return 34
    end
    if task.postCombatLoot or task.manualSupplyLoot then return 0 end
    return 10
end

local function lootBuildWeaponSlot(item, fullType)
    local slot = {name = fullType, fullType = fullType}
    if item.getMagazineType then
        local ok, value = pcall(function() return item:getMagazineType() end)
        if ok and value then slot.magName = value end
    end
    if item.getAmmoType then
        local ok, value = pcall(function() return item:getAmmoType() end)
        if ok and value then slot.ammoName = value end
    end
    if item.getCurrentAmmoCount then
        local ok, value = pcall(function() return item:getCurrentAmmoCount() end)
        if ok then slot.bulletsLeft = tonumber(value) or slot.bulletsLeft end
    end
    if item.getMaxAmmo then
        local ok, value = pcall(function() return item:getMaxAmmo() end)
        if ok then slot.magSize = tonumber(value) or slot.magSize end
    end
    if item.getCondition then
        local ok, value = pcall(function() return item:getCondition() end)
        if ok then slot.condition = tonumber(value) or slot.condition end
    end
    return slot
end

local function lootTryEquipBetterWeapon(zombie, item)
    if not zombie or not item then return false end
    local text = lootItemText(item)
    if not lootIsWeapon(item, text) then return false end
    local candidateScore = lootWeaponScore(item, text)
    local current = zombie.getPrimaryHandItem and zombie:getPrimaryHandItem() or nil
    local currentScore = lootWeaponScore(current, current and lootItemText(current) or "")
    if current and candidateScore <= currentScore + 8 then return false end

    local equipped = false
    if zombie.setPrimaryHandItem then
        local ok = pcall(function() zombie:setPrimaryHandItem(item) end)
        equipped = ok == true
    end
    if not equipped then return false end

    local brain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(zombie) or nil
    if brain and NPCEntity and NPCEntity.GetWeapons and NPCEntity.SetWeapons then
        local fullType = lootItemFullType(item)
        if fullType then
            local weapons = NPCEntity.GetWeapons(zombie) or brain.weapons or {}
            if lootIsFirearm(item, text) then
                weapons.primary = lootBuildWeaponSlot(item, fullType)
            else
                weapons.melee = fullType
            end
            NPCEntity.SetWeapons(zombie, weapons)
            brain.currentWeapon = lootBuildWeaponSlot(item, fullType)
        end
    end
    return true
end

local function lootTryEquipBetterArmor(zombie, item)
    if not zombie or not item or not zombie.setWornItem then return false end
    local location = lootBodyLocation(item)
    if not location then return false end

    local score = lootClothingScore(item)
    if score <= 0 then return false end

    local current = nil
    if zombie.getWornItem then
        pcall(function() current = zombie:getWornItem(location) end)
    end
    local currentScore = current and lootClothingScore(current) or 0
    if current and score <= currentScore + 4 then return false end

    local okWear = pcall(function() zombie:setWornItem(location, item) end)
    if okWear and zombie.resetModelNextFrame then pcall(function() zombie:resetModelNextFrame() end) end
    return okWear == true
end

local function lootTryEquipUpgrades(zombie, item, task)
    if not task or task.lootEquipUpgrades ~= true then return false end
    local changed = false
    if lootTryEquipBetterWeapon(zombie, item) then changed = true end
    if lootTryEquipBetterArmor(zombie, item) then changed = true end
    return changed
end

local function transferContainerItems(container, inventory, zombie, task)
    if not container or not inventory then return false end
    local empty = false
    if container.isEmpty then
        local okEmpty, isEmpty = pcall(function() return container:isEmpty() end)
        empty = okEmpty and isEmpty == true
    end
    if empty then return false end

    local changed = false
    local items = collectContainerItems(container, task)
    local ranked = {}
    local prioritized = task and (task.postCombatLoot or task.lootMaxItems or task.lootEquipUpgrades or task.lootNeed)

    for j=0, items:size() - 1 do
        local item = items:get(j)
        if prioritized then
            local score = lootCandidateScore(zombie, item, task)
            if score > 0 then ranked[#ranked + 1] = {item = item, score = score, order = j} end
        else
            if transferItem(container, inventory, item) then
                changed = true
            end
        end
    end

    if prioritized then
        table.sort(ranked, function(a, b)
            if a.score == b.score then return a.order < b.order end
            return a.score > b.score
        end)
        local maxItems = tonumber(task and task.lootMaxItems) or #ranked
        if maxItems < 1 then maxItems = 1 end
        for i=1, math.min(maxItems, #ranked) do
            local item = ranked[i].item
            if transferItem(container, inventory, item) then
                lootTryEquipUpgrades(zombie, item, task)
                changed = true
            end
        end
    end

    return changed
end

local function lootNowMs()
    if getTimestampMs then
        local ok, value = pcall(function() return getTimestampMs() end)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return 0
end

local function isPlayerLootTask(task)
    return task and (task.playerLootOrder == true or task.manualPlayerLoot == true or task.playerCommand == true or task.source == "player")
end

NPCActionLootItemsBridge.OnStart = function(zombie, task)
    if isPlayerLootTask(task) then
        task._playerLootStartedMs = lootNowMs()
        task._playerLootLimitMs = math.max(500, math.min(2600, (tonumber(task.time) or 80) * 18))
    end
    return true
end

NPCActionLootItemsBridge.OnWorking = function(zombie, task)
    if not zombie or not task then return true end
    faceTask(zombie, task)
    if task.time and task.time <= 0 then return true end
    if isPlayerLootTask(task) then
        local now = lootNowMs()
        local started = tonumber(task._playerLootStartedMs) or now
        local limit = tonumber(task._playerLootLimitMs) or 1400
        if now > 0 and started > 0 and now - started >= limit then return true end
    end
    if task.anim and zombie:getBumpType() ~= task.anim then
        zombie:setBumpType(task.anim)
    end
    return false
end

NPCActionLootItemsBridge.OnComplete = function(zombie, task)
    if isPlayerLootTask(task) and zombie and zombie.setBumpType and task and task.anim then
        local ok, bump = pcall(function() return zombie:getBumpType() end)
        if ok and bump == task.anim then pcall(function() zombie:setBumpType("Idle") end) end
    end
    local square = getTaskSquare(task)
    local inventory = zombie and zombie.getInventory and zombie:getInventory() or nil
    if not square or not inventory then return true end

    local changed = false

    local maxContainers = tonumber(task and task.lootMaxContainers) or ((task and (task.manualSupplyLoot or task.postCombatLoot)) and 2 or 99)
    if maxContainers < 1 then maxContainers = 1 end
    local scannedContainers = 0

    if not (task and task.lootContainersOnly == true) then
        local bodies = square.getStaticMovingObjects and square:getStaticMovingObjects() or nil
        if bodies then
            for i=0, bodies:size() - 1 do
                if scannedContainers >= maxContainers then break end
                local object = bodies:get(i)
                if instanceof and instanceof(object, "IsoDeadBody") then
                    local container = object and object.getContainer and object:getContainer() or nil
                    if container then
                        scannedContainers = scannedContainers + 1
                        if transferContainerItems(container, inventory, zombie, task) then changed = true end
                    end
                end
            end
        end
    end

    if not (task and task.lootBodiesOnly == true) then
        local objects = square:getObjects()
        if objects then
            for i=0, objects:size() - 1 do
                if scannedContainers >= maxContainers then break end
                local object = objects:get(i)
                local container = object and object.getContainer and object:getContainer() or nil
                if container then
                    scannedContainers = scannedContainers + 1
                    if transferContainerItems(container, inventory, zombie, task) then changed = true end
                end
            end
        end
    end

    if changed then syncRuntimeLootState(zombie) end
    if NPCPostCombatLootBridge and NPCPostCombatLootBridge.MarkHouseLootFinished and task and task.houseLoot then
        local brain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(zombie) or nil
        pcall(function() NPCPostCombatLootBridge.MarkHouseLootFinished(zombie, brain, changed) end)
    end
    if NPCPostCombatLootBridge and NPCPostCombatLootBridge.MarkLootFinished and task and task.postCombatLoot then
        local brain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(zombie) or nil
        pcall(function() NPCPostCombatLootBridge.MarkLootFinished(zombie, brain, changed) end)
    end
    if NPCPostCombatLootBridge and NPCPostCombatLootBridge.MarkManualLootFinished and task and task.manualSupplyLoot then
        local brain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(zombie) or nil
        pcall(function() NPCPostCombatLootBridge.MarkManualLootFinished(zombie, brain, changed) end)
    end
    return true
end
