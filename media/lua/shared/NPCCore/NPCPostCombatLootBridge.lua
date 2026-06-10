NPCPostCombatLootBridge = NPCPostCombatLootBridge or {}

NPCPostCombatLootBridge.Version = 4
NPCPostCombatLootBridge.Config = NPCPostCombatLootBridge.Config or {
    enabled = true,
    scanRadius = 8,
    arriveDistance = 1.8,
    cooldownMs = 26000,
    claimMs = 9000,
    minPostCombatDelayMs = 2600,
    postCombatGraceMs = 52000,
    maxSquaresPerScan = 96,
    maxBodiesPerSquare = 4,
    maxItemsPerLoot = 7,
    manualLootTargetCacheMs = 6200,
    houseLootTargetCacheMs = 6200,
    manualLootMissCooldownMs = 2200,
    houseLootMissCooldownMs = 2600,
    maxItemsPerContainerScore = 22
}

local function pcl_nowMs()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then return math.floor(getGameTime():getWorldAgeHours() * 3600000) end
    return 0
end

local function pcl_dist2(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return dx * dx + dy * dy
end

local function pcl_configNumber(key, fallback, minValue, maxValue)
    local value = fallback
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        local ok, got = pcall(function() return NPCLegacySettingsBridge.GetNumber("PostCombatLoot_" .. tostring(key), fallback, minValue, maxValue) end)
        if ok and got ~= nil then value = got end
    end
    value = tonumber(value) or tonumber(fallback) or 0
    if minValue and value < minValue then value = minValue end
    if maxValue and value > maxValue then value = maxValue end
    return value
end

local function pcl_configBool(key, fallback)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        local ok, got = pcall(function() return NPCLegacySettingsBridge.GetBool("PostCombatLoot_" .. tostring(key), fallback) end)
        if ok and got ~= nil then return got == true end
    end
    return fallback == true
end

local function pcl_isEnabled()
    if NPCPostCombatLootBridge.Enabled == false then return false end
    return pcl_configBool("Enabled", NPCPostCombatLootBridge.Config.enabled ~= false)
end

local function pcl_getLiving(brain)
    if not brain then return nil end
    brain.ai = brain.ai or {}
    brain.ai.living = brain.ai.living or {}
    return brain.ai.living
end

local function pcl_programName(brain)
    local program = brain and brain.program
    if type(program) == "table" then return tostring(program.name or program.program or "") end
    return tostring(brain and (brain.programName or brain.job or brain.role) or "")
end

local function pcl_isPlayerOwned(brain)
    if not brain then return false end
    if brain.master or brain.followPlayer or brain.guardPlayer or brain.isPlayerGuard then return true end
    if brain.mercenaryHired == true or brain.mercenaryHiredBy ~= nil then return true end
    local order = type(brain.order) == "table" and brain.order or nil
    if order and (order.master or order.followPlayer or order.playerId) then return true end
    return false
end

local function pcl_itemText(item)
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

local function pcl_isWeapon(item, text)
    if not item then return false end
    if item.IsWeapon then
        local ok, value = pcall(function() return item:IsWeapon() end)
        if ok and value == true then return true end
    end
    if instanceof and instanceof(item, "HandWeapon") then return true end
    text = text or pcl_itemText(item)
    return string.find(text, "rifle", 1, true) ~= nil
        or string.find(text, "pistol", 1, true) ~= nil
        or string.find(text, "shotgun", 1, true) ~= nil
        or string.find(text, "gun", 1, true) ~= nil
        or string.find(text, "knife", 1, true) ~= nil
        or string.find(text, "machete", 1, true) ~= nil
        or string.find(text, "axe", 1, true) ~= nil
        or string.find(text, "bat", 1, true) ~= nil
end

local function pcl_isFirearm(item, text)
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
    text = text or pcl_itemText(item)
    return string.find(text, "rifle", 1, true) ~= nil
        or string.find(text, "pistol", 1, true) ~= nil
        or string.find(text, "shotgun", 1, true) ~= nil
        or string.find(text, "firearm", 1, true) ~= nil
        or string.find(text, "revolver", 1, true) ~= nil
end

local function pcl_isAmmo(item, text)
    text = text or pcl_itemText(item)
    return string.find(text, "ammo", 1, true) ~= nil
        or string.find(text, "bullet", 1, true) ~= nil
        or string.find(text, "shell", 1, true) ~= nil
        or string.find(text, "round", 1, true) ~= nil
        or string.find(text, "magazine", 1, true) ~= nil
        or string.find(text, "clip", 1, true) ~= nil
end

local function pcl_isMedical(item, text)
    text = text or pcl_itemText(item)
    return string.find(text, "bandage", 1, true) ~= nil
        or string.find(text, "disinfect", 1, true) ~= nil
        or string.find(text, "alcohol", 1, true) ~= nil
        or string.find(text, "suture", 1, true) ~= nil
        or string.find(text, "firstaid", 1, true) ~= nil
        or string.find(text, "pills", 1, true) ~= nil
end

local function pcl_isFoodWater(item, text)
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
    text = text or pcl_itemText(item)
    return string.find(text, "water", 1, true) ~= nil
        or string.find(text, "canned", 1, true) ~= nil
        or string.find(text, "food", 1, true) ~= nil
        or string.find(text, "soda", 1, true) ~= nil
        or string.find(text, "chips", 1, true) ~= nil
end

local function pcl_armorScore(item, text)
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
    text = text or pcl_itemText(item)
    if string.find(text, "vest", 1, true) then return 55 end
    if string.find(text, "armor", 1, true) or string.find(text, "armour", 1, true) then return 50 end
    if string.find(text, "helmet", 1, true) then return 40 end
    if string.find(text, "jacket", 1, true) then return 22 end
    if string.find(text, "leather", 1, true) then return 18 end
    return 0
end

local function pcl_bodyLocation(item)
    if not item or not item.getBodyLocation then return nil end
    local ok, location = pcall(function() return item:getBodyLocation() end)
    if not ok or not location then return nil end
    location = tostring(location)
    if location == "" or location == "None" or location == "null" then return nil end
    return location
end

local function pcl_conditionScore(item)
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

local function pcl_numericItemValue(item, getterName, weight)
    if not item or not getterName or not item[getterName] then return 0 end
    local ok, value = pcall(function() return item[getterName](item) end)
    if not ok then return 0 end
    return (tonumber(value) or 0) * (weight or 1)
end

local function pcl_wearPenalty(item)
    if not item then return 0 end
    local penalty = 0
    penalty = penalty + math.min(12, math.max(0, pcl_numericItemValue(item, "getDirtyness", 0.08)))
    penalty = penalty + math.min(14, math.max(0, pcl_numericItemValue(item, "getBloodLevel", 0.07)))
    return penalty
end

local function pcl_clothingScore(item, text)
    if not item then return 0 end
    local location = pcl_bodyLocation(item)
    if not location then return 0 end

    text = text or pcl_itemText(item)
    local score = 18 + pcl_conditionScore(item)
    score = score + pcl_armorScore(item, text)
    score = score + pcl_numericItemValue(item, "getInsulation", 10)
    score = score + pcl_numericItemValue(item, "getWindresistance", 8)
    score = score + pcl_numericItemValue(item, "getWaterResistance", 0.25)

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

    score = score - pcl_wearPenalty(item)
    if score < 0 then return 0 end
    return score
end

function NPCPostCombatLootBridge.ScoreItem(item)
    if not item then return 0 end
    local text = pcl_itemText(item)
    if pcl_isWeapon(item, text) then
        local score = pcl_isFirearm(item, text) and 120 or 82
        if item.getMaxDamage then
            local ok, value = pcall(function() return item:getMaxDamage() end)
            if ok then score = score + ((tonumber(value) or 0) * 18) end
        end
        if item.getMaxRange then
            local ok, value = pcall(function() return item:getMaxRange() end)
            if ok then score = score + ((tonumber(value) or 0) * 1.5) end
        end
        return score
    end
    if pcl_isAmmo(item, text) then return 76 end
    local clothing = pcl_clothingScore(item, text)
    if clothing > 0 then return 52 + clothing end
    if pcl_isMedical(item, text) then return 54 end
    if pcl_isFoodWater(item, text) then return 34 end
    return 0
end

local function pcl_containerItemsBounded(container, maxItems)
    if not container then return nil end
    maxItems = math.max(1, math.min(tonumber(maxItems) or 24, 80))
    if ArrayList and ArrayList.new and container.getItems then
        local okDirect, direct = pcall(function() return container:getItems() end)
        if okDirect and direct then
            local items = ArrayList.new()
            local n = math.min(tonumber(direct:size()) or 0, maxItems)
            for i = 0, n - 1 do
                local item = direct:get(i)
                if item then items:add(item) end
            end
            return items
        end
    end
    if not (container.getAllEvalRecurse and ArrayList and ArrayList.new) then return nil end
    local items = ArrayList.new()
    local added = 0
    local ok = pcall(function()
        container:getAllEvalRecurse(function(item)
            if not item or added >= maxItems then return false end
            added = added + 1
            return true
        end, items)
    end)
    if ok then return items end
    return nil
end

local function pcl_containerScore(container, maxItems)
    local items = pcl_containerItemsBounded(container, maxItems or pcl_configNumber("MaxItemsPerContainerScore", NPCPostCombatLootBridge.Config.maxItemsPerContainerScore, 8, 80))
    if not items then return 0, 0 end
    local score = 0
    local count = 0
    local size = tonumber(items:size()) or 0
    local maxScan = math.min(size, tonumber(maxItems) or pcl_configNumber("MaxItemsPerContainerScore", NPCPostCombatLootBridge.Config.maxItemsPerContainerScore, 8, 80))
    for i = 0, maxScan - 1 do
        local item = items:get(i)
        local itemScore = NPCPostCombatLootBridge.ScoreItem(item)
        if itemScore > 0 then
            score = score + itemScore
            count = count + 1
        end
    end
    return score, count
end

local function pcl_squareHasHostileBody(square)
    if not square or not square.getStaticMovingObjects then return nil, 0, 0 end
    local bodies = square:getStaticMovingObjects()
    if not bodies then return nil, 0, 0 end
    local bestBody = nil
    local bestScore = 0
    local bestCount = 0
    local maxBodies = pcl_configNumber("MaxBodiesPerSquare", NPCPostCombatLootBridge.Config.maxBodiesPerSquare, 1, 20)
    local n = math.min(tonumber(bodies:size()) or 0, maxBodies)
    for i = 0, n - 1 do
        local object = bodies:get(i)
        if instanceof and instanceof(object, "IsoDeadBody") then
            local container = object.getContainer and object:getContainer() or nil
            local score, count = pcl_containerScore(container, 28)
            if score > bestScore then
                bestBody = object
                bestScore = score
                bestCount = count
            end
        end
    end
    return bestBody, bestScore, bestCount
end

local function pcl_squareHasManualSupply(square, bodiesOnly, containersOnly)
    if not square then return nil, 0, 0 end
    local bestObject = nil
    local bestScore = 0
    local bestCount = 0

    local function consider(object)
        local container = object and object.getContainer and object:getContainer() or nil
        local score, count = pcl_containerScore(container, 28)
        if score > bestScore then
            bestObject = object
            bestScore = score
            bestCount = count
        end
    end

    if containersOnly ~= true then
        local bodies = square.getStaticMovingObjects and square:getStaticMovingObjects() or nil
        if bodies then
            local maxBodies = pcl_configNumber("MaxBodiesPerSquare", NPCPostCombatLootBridge.Config.maxBodiesPerSquare, 1, 20)
            local n = math.min(tonumber(bodies:size()) or 0, maxBodies)
            for i = 0, n - 1 do
                local object = bodies:get(i)
                if instanceof and instanceof(object, "IsoDeadBody") then consider(object) end
            end
        end
    end

    if bodiesOnly == true then return bestObject, bestScore, bestCount end

    local objects = square.getObjects and square:getObjects() or nil
    if objects then
        local n = math.min(tonumber(objects:size()) or 0, 14)
        for i = 0, n - 1 do
            local object = objects:get(i)
            consider(object)
        end
    end

    return bestObject, bestScore, bestCount
end

local function pcl_findManualSupplySquareAround(cx, cy, cz, radius, originX, originY, bodiesOnly)
    if not getCell then return nil end
    local cell = getCell()
    if not cell then return nil end
    radius = math.floor(tonumber(radius) or 7)
    cz = math.floor(tonumber(cz) or 0)
    local best = nil
    local checked = 0
    local maxSquares = pcl_configNumber("MaxSquaresPerScan", NPCPostCombatLootBridge.Config.maxSquaresPerScan, 24, 500)

    for r = 0, radius do
        for dx = -r, r do
            for dy = -r, r do
                if r == 0 or math.abs(dx) == r or math.abs(dy) == r then
                    checked = checked + 1
                    if checked > maxSquares then return best end
                    local sx = math.floor((tonumber(cx) or 0) + dx)
                    local sy = math.floor((tonumber(cy) or 0) + dy)
                    local square = cell:getGridSquare(sx, sy, cz)
                    if square then
                        local object, score, count = pcl_squareHasManualSupply(square, bodiesOnly == true)
                        if object and score > 0 then
                            local distancePenalty = pcl_dist2(originX or cx, originY or cy, sx + 0.5, sy + 0.5) * 0.65
                            local total = score - distancePenalty + (count * 4)
                            if not best or total > best.score then
                                best = {square = square, object = object, score = total, itemScore = score, itemCount = count, x = sx, y = sy, z = cz, bodiesOnly = bodiesOnly == true}
                            end
                        end
                    end
                end
            end
        end
    end

    return best
end

local function pcl_findCorpseSquareAround(cx, cy, cz, radius, originX, originY)
    if not getCell then return nil end
    local cell = getCell()
    if not cell then return nil end
    radius = math.floor(tonumber(radius) or NPCPostCombatLootBridge.Config.scanRadius or 8)
    cz = math.floor(tonumber(cz) or 0)
    local best = nil
    local checked = 0
    local maxSquares = pcl_configNumber("MaxSquaresPerScan", NPCPostCombatLootBridge.Config.maxSquaresPerScan, 24, 500)

    for r = 0, radius do
        for dx = -r, r do
            for dy = -r, r do
                if r == 0 or math.abs(dx) == r or math.abs(dy) == r then
                    checked = checked + 1
                    if checked > maxSquares then return best end
                    local sx = math.floor((tonumber(cx) or 0) + dx)
                    local sy = math.floor((tonumber(cy) or 0) + dy)
                    local square = cell:getGridSquare(sx, sy, cz)
                    if square then
                        local body, score, count = pcl_squareHasHostileBody(square)
                        if body and score > 0 then
                            local distancePenalty = pcl_dist2(originX or cx, originY or cy, sx + 0.5, sy + 0.5) * 0.65
                            local total = score - distancePenalty + (count * 4)
                            if not best or total > best.score then
                                best = {square = square, body = body, score = total, itemScore = score, itemCount = count, x = sx, y = sy, z = cz}
                            end
                        end
                    end
                end
            end
        end
    end

    return best
end

function NPCPostCombatLootBridge.IsManualLootOrder(order)
    if type(order) ~= "table" then return false end
    local name = NPCOrderContract and NPCOrderContract.NormalizeOrderName and NPCOrderContract.NormalizeOrderName(order.name or order.orderName) or tostring(order.name or order.orderName or "")
    if order.manualLoot == true then return true end
    if NPCOrderContract and NPCOrderContract.IsPlayerCommandLootOrderName then return NPCOrderContract.IsPlayerCommandLootOrderName(name) end
    return name == "RearmHere" or name == "LootBodies" or name == "LootAreaManual"
end

function NPCPostCombatLootBridge.FindManualLootTarget(chr, brain, order)
    if not (chr and chr.getX and brain and NPCPostCombatLootBridge.IsManualLootOrder(order)) then return nil end
    if not pcl_isPlayerOwned(brain) then return nil end

    brain.ai = brain.ai or {}
    local living = pcl_getLiving(brain)
    local now = pcl_nowMs()
    if living and living.manualLootNextMs and now < tonumber(living.manualLootNextMs) then return nil end

    local orderKey = tostring(order.issued or 0) .. ":" .. tostring(order.name or order.orderName or "") .. ":" .. tostring(order.lootBodiesOnly == true)
    local cached = living and living.manualLootTargetCache or nil
    if cached and cached.key == orderKey and cached.expiresMs and now < tonumber(cached.expiresMs) and cached.target and cached.target.square then
        return cached.target
    end

    local anchor = type(order.anchor) == "table" and order.anchor or nil
    local cx = tonumber(anchor and anchor.x) or (chr.getX and chr:getX()) or 0
    local cy = tonumber(anchor and anchor.y) or (chr.getY and chr:getY()) or 0
    local cz = tonumber(anchor and anchor.z) or (chr.getZ and chr:getZ()) or 0
    local radius = tonumber(order.lootRadius) or 7
    if radius < 2 then radius = 2 end
    if radius > 18 then radius = 18 end
    local bodiesOnly = order.lootBodiesOnly == true or tostring(order.name or "") == "LootBodies"

    local target = pcl_findManualSupplySquareAround(cx, cy, cz, radius, chr:getX(), chr:getY(), bodiesOnly)
    if target and living then
        living.manualLootTargetCache = {
            key = orderKey,
            expiresMs = now + pcl_configNumber("ManualLootTargetCacheMs", NPCPostCombatLootBridge.Config.manualLootTargetCacheMs, 800, 12000),
            target = target
        }
    elseif living then
        living.manualLootNextMs = now + pcl_configNumber("ManualLootMissCooldownMs", NPCPostCombatLootBridge.Config.manualLootMissCooldownMs, 500, 9000)
        living.manualLootLastMissIssued = order.issued
        living.manualLootTargetCache = nil
    end
    return target
end

function NPCPostCombatLootBridge.BuildManualLootTask(chr, brain, order, target)
    if not (target and target.square and NPCPostCombatLootBridge.IsManualLootOrder(order)) then return nil end
    local name = tostring(order.name or order.orderName or "RearmHere")
    return {
        action = "LootItems",
        anim = "Loot",
        time = target.bodiesOnly and 80 or 65,
        x = target.square:getX(),
        y = target.square:getY(),
        z = target.square:getZ(),
        playerOrder = true,
        source = "player",
        commandAuthority = "player",
        playerCommand = true,
        playerLootOrder = true,
        manualOrder = true,
        manualPlayerLoot = true,
        manualSupplyLoot = true,
        orderName = name,
        orderIssued = order.issued,
        lootBodiesOnly = target.bodiesOnly == true,
        lootEquipUpgrades = order.lootEquipUpgrades ~= false,
        lootTakeWeapons = order.lootTakeWeapons ~= false,
        lootTakeAmmo = order.lootTakeAmmo ~= false,
        lootTakeArmor = order.lootTakeArmor ~= false,
        lootTakeClothing = order.lootTakeClothing ~= false,
        lootTakeMedical = order.lootTakeMedical ~= false,
        lootTakeFood = order.lootTakeFood ~= false,
        lootMaxItems = tonumber(order.lootMaxItems) or (target.bodiesOnly and 7 or 9),
        lootMaxContainers = tonumber(order.lootMaxContainers) or (target.bodiesOnly and 2 or 1),
        lootMaxScanItems = 36,
        directorState = "LootArea",
        directorReason = "manual player supply order"
    }
end


local function pcl_stableSlotNumber(value)
    local n = tonumber(value)
    if n and n ~= 0 then return math.floor(math.abs(n)) end
    if type(value) == "string" then
        local suffix = value:match("(%d+)%s*$")
        if suffix then
            n = tonumber(suffix)
            if n and n > 0 then return math.floor(n) end
        end
    end
    return nil
end

local function pcl_brainMemberIndex(brain)
    local value = nil
    if type(brain) == "table" then
        value = pcl_stableSlotNumber(brain.memberIndex) or pcl_stableSlotNumber(brain.slotIndex) or pcl_stableSlotNumber(brain.formationIndex) or pcl_stableSlotNumber(brain.mercenarySlotIndex)
        if not value then value = pcl_stableSlotNumber(brain.id) or pcl_stableSlotNumber(brain.uid) or pcl_stableSlotNumber(brain.persistentId) or pcl_stableSlotNumber(brain.runtimeId) end
    end
    value = math.abs(value or 1)
    return ((math.max(1, value) - 1) % 18) + 1
end

local function pcl_squareBuilding(square)
    if not square or not square.getBuilding then return nil end
    local ok, building = pcall(function() return square:getBuilding() end)
    if ok then return building end
    return nil
end

function NPCPostCombatLootBridge.FindHouseLootTarget(chr, brain, order, positions)
    if not (chr and chr.getX and brain and order and tostring(order.name or order.orderName or "") == "LootHouse") then return nil end
    if not pcl_isPlayerOwned(brain) then return nil end
    if type(positions) ~= "table" or #positions == 0 then return nil end

    local living = pcl_getLiving(brain)
    local now = pcl_nowMs()
    if living and living.houseLootNextMs and now < tonumber(living.houseLootNextMs) then return nil end

    local houseKey = tostring(order.issued or 0) .. ":" .. tostring(pcl_brainMemberIndex(brain))
    local cached = living and living.houseLootTargetCache or nil
    if cached and cached.key == houseKey and cached.expiresMs and now < tonumber(cached.expiresMs) and cached.target and cached.target.square then
        return cached.target
    end

    local targetBuilding = nil
    for _, position in ipairs(positions) do
        local building = pcl_squareBuilding(position and position.square)
        if building then
            targetBuilding = building
            break
        end
    end
    if not targetBuilding then return nil end

    local candidates = {}
    local checked = 0
    local maxPositions = math.min(#positions, 28)
    for i = 1, maxPositions do
        local position = positions[i]
        local square = position and position.square or nil
        if square and pcl_squareBuilding(square) == targetBuilding then
            checked = checked + 1
            local object, itemScore, itemCount = pcl_squareHasManualSupply(square, false, true)
            if object and itemScore > 0 then
                local sx = square:getX()
                local sy = square:getY()
                local distancePenalty = pcl_dist2(chr:getX(), chr:getY(), sx + 0.5, sy + 0.5) * 0.45
                local roleBonus = 0
                local role = tostring(position.role or "")
                if role == "interior" then roleBonus = 8 elseif role == "stairs" then roleBonus = 4 end
                candidates[#candidates + 1] = {
                    square = square,
                    object = object,
                    score = itemScore - distancePenalty + (itemCount * 4) + roleBonus,
                    itemScore = itemScore,
                    itemCount = itemCount,
                    x = sx,
                    y = sy,
                    z = square:getZ(),
                    houseLoot = true,
                    containersOnly = true,
                    role = position.role,
                    faceX = position.faceX,
                    faceY = position.faceY
                }
            end
        end
    end

    if #candidates == 0 then
        if living then
            living.houseLootNextMs = now + pcl_configNumber("HouseLootMissCooldownMs", NPCPostCombatLootBridge.Config.houseLootMissCooldownMs, 500, 9000)
            living.houseLootLastMissIssued = order.issued
            living.houseLootTargetCache = nil
        end
        return nil
    end

    table.sort(candidates, function(a, b)
        if a.score == b.score then return (a.itemCount or 0) > (b.itemCount or 0) end
        return (a.score or 0) > (b.score or 0)
    end)

    local pickCount = math.min(#candidates, 6)
    local idx = pcl_brainMemberIndex(brain)
    local phase = 0
    if living then
        local issuedKey = tostring(order.issued or 0)
        if living.houseLootIssued ~= issuedKey then
            living.houseLootIssued = issuedKey
            living.houseLootStartedMs = now
        end
        phase = math.floor(math.max(0, now - (tonumber(living.houseLootStartedMs) or now)) / 6200)
    end
    local target = candidates[((idx + phase - 2) % pickCount) + 1]
    if target and living then
        living.houseLootTargetCache = {
            key = houseKey,
            expiresMs = now + pcl_configNumber("HouseLootTargetCacheMs", NPCPostCombatLootBridge.Config.houseLootTargetCacheMs, 800, 12000),
            target = target
        }
    end
    return target
end

function NPCPostCombatLootBridge.BuildHouseLootTask(chr, brain, order, target)
    if not (target and target.square and order and tostring(order.name or order.orderName or "") == "LootHouse") then return nil end
    return {
        action = "LootItems",
        anim = "Loot",
        time = 65,
        x = target.square:getX(),
        y = target.square:getY(),
        z = target.square:getZ(),
        playerOrder = true,
        source = "player",
        commandAuthority = "player",
        playerCommand = true,
        playerLootOrder = true,
        manualOrder = true,
        manualPlayerLoot = true,
        manualSupplyLoot = true,
        houseLoot = true,
        lootContainersOnly = true,
        orderName = "LootHouse",
        orderIssued = order.issued,
        lootBodiesOnly = false,
        lootEquipUpgrades = true,
        lootTakeWeapons = true,
        lootTakeAmmo = true,
        lootTakeArmor = order.lootTakeArmor ~= false,
        lootTakeClothing = order.lootTakeClothing ~= false,
        lootTakeMedical = order.lootTakeMedical ~= false,
        lootTakeFood = order.lootTakeFood ~= false,
        lootMaxItems = tonumber(order.lootMaxItems) or 7,
        lootMaxContainers = tonumber(order.lootMaxContainers) or 1,
        lootMaxScanItems = 36,
        directorState = "LootArea",
        directorReason = "manual house loot supply order"
    }
end

function NPCPostCombatLootBridge.MarkManualLootFinished(chr, brain, changed)
    local living = pcl_getLiving(brain)
    local now = pcl_nowMs()
    if living then
        living.manualLootDoneMs = now
        living.manualLootNextMs = now + (changed and 1200 or 3200)
        living.manualLootTargetCache = nil
        if changed then living.manualLootChangedAt = now end
    end
end

function NPCPostCombatLootBridge.MarkHouseLootFinished(chr, brain, changed)
    local living = pcl_getLiving(brain)
    local now = pcl_nowMs()
    if living then
        living.houseLootDoneMs = now
        living.houseLootNextMs = now + (changed and 1400 or 3400)
        living.houseLootTargetCache = nil
        if changed then living.houseLootChangedAt = now end
    end
end

function NPCPostCombatLootBridge.FindCorpseSquare(chr, brain)
    if not chr or not chr.getX then return nil end
    local living = brain and brain.ai and brain.ai.living or nil
    local radius = pcl_configNumber("ScanRadius", NPCPostCombatLootBridge.Config.scanRadius, 2, 24)
    local cx = chr:getX()
    local cy = chr:getY()
    local cz = chr:getZ()
    local best = pcl_findCorpseSquareAround(cx, cy, cz, radius, cx, cy)

    if living and living.lastCombatX and living.lastCombatY then
        local combat = pcl_findCorpseSquareAround(living.lastCombatX, living.lastCombatY, living.lastCombatZ or cz, math.min(radius, 7), cx, cy)
        if combat and ((not best) or combat.score > best.score) then best = combat end
    end

    return best
end

local function pcl_hasRecentCombat(brain, living, now)
    if NPCLivingWorldIntentBridge and NPCLivingWorldIntentBridge.HasRecentCombat then
        local ok, value = pcall(function() return NPCLivingWorldIntentBridge.HasRecentCombat(brain, now) end)
        if ok and value == true then return true end
    end
    if not living or not living.lastCombatMs then return false end
    local grace = pcl_configNumber("PostCombatGraceMs", NPCPostCombatLootBridge.Config.postCombatGraceMs, 5000, 180000)
    return now - (tonumber(living.lastCombatMs) or 0) <= grace
end

local function pcl_shouldLoot(chr, brain, living, now)
    if not pcl_isEnabled() then return false end
    if not chr or not brain then return false end
    if pcl_isPlayerOwned(brain) and brain.allowCompanionPostCombatLoot ~= true then return false end
    if brain.blackMarket or brain.blackMarketNPC or brain.prisoner then return false end
    if living and living.postCombatLootNextMs and now < tonumber(living.postCombatLootNextMs) then return false end
    if living and living.postCombatLootClaimUntilMs and now < tonumber(living.postCombatLootClaimUntilMs) then return false end

    local recent = pcl_hasRecentCombat(brain, living, now)
    local program = string.lower(pcl_programName(brain))
    local looterRole = program == "looter" or program == "raider" or program == "thief" or brain.baseOwnedRole == "raid" or brain.tacticalRole == "raider"
    if not recent and not looterRole then return false end

    if living and living.lastCombatMs then
        local delay = pcl_configNumber("MinDelayMs", NPCPostCombatLootBridge.Config.minPostCombatDelayMs, 0, 15000)
        if now - (tonumber(living.lastCombatMs) or 0) < delay then return false end
    end

    return true
end

function NPCPostCombatLootBridge.PlanTasks(chr, brain, runtime, opts)
    local living = pcl_getLiving(brain)
    local now = pcl_nowMs()
    if not pcl_shouldLoot(chr, brain, living, now) then return nil end

    local target = NPCPostCombatLootBridge.FindCorpseSquare(chr, brain)
    if not target or not target.square then
        if living then living.postCombatLootNextMs = now + pcl_configNumber("CooldownMs", NPCPostCombatLootBridge.Config.cooldownMs, 5000, 180000) end
        return nil
    end

    local tx = target.square:getX()
    local ty = target.square:getY()
    local tz = target.square:getZ()
    local dist2 = pcl_dist2(chr:getX(), chr:getY(), tx + 0.5, ty + 0.5)
    local arrive = pcl_configNumber("ArriveDistance", NPCPostCombatLootBridge.Config.arriveDistance, 0.8, 5.0)
    local state = opts and opts.state or (runtime and runtime.States and runtime.States.LootArea) or "LootArea"
    local reason = "post-combat corpse loot"

    if living then
        living.postCombatLootClaimUntilMs = now + pcl_configNumber("ClaimMs", NPCPostCombatLootBridge.Config.claimMs, 2000, 60000)
        living.postCombatLootNextMs = now + pcl_configNumber("CooldownMs", NPCPostCombatLootBridge.Config.cooldownMs, 5000, 180000)
        living.postCombatLootX = tx
        living.postCombatLootY = ty
        living.postCombatLootZ = tz
        living.postCombatLootReason = reason
    end

    if dist2 > arrive * arrive then
        if runtime and runtime.moveToState then
            return {runtime.moveToState(chr, state, reason, tx, ty, tz, "Walk", true)}
        end
        return {{action = "Move", x = tx, y = ty, z = tz, walkType = "Walk", director = true, directorState = state, directorReason = reason, postCombatLoot = true}}
    end

    return {{
        action = "LootItems",
        anim = "Loot",
        time = 135,
        x = tx,
        y = ty,
        z = tz,
        director = true,
        livingIntent = true,
        postCombatLoot = true,
        lootBodiesOnly = true,
        lootEquipUpgrades = true,
        lootTakeWeapons = true,
        lootTakeAmmo = true,
        lootTakeArmor = true,
        lootTakeMedical = true,
        lootTakeFood = true,
        lootMaxItems = pcl_configNumber("MaxItemsPerLoot", NPCPostCombatLootBridge.Config.maxItemsPerLoot, 1, 24),
        directorState = state,
        directorReason = reason
    }}
end

function NPCPostCombatLootBridge.MarkLootFinished(chr, brain, changed)
    local living = pcl_getLiving(brain)
    local now = pcl_nowMs()
    if living then
        living.postCombatLootDoneMs = now
        living.postCombatLootClaimUntilMs = nil
        if changed then living.postCombatLootChangedAt = now end
    end
end
