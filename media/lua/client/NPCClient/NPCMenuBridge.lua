-- Neutral client world-context menu bridge.
-- The legacy legacy menu table remains exported by the facade for compatibility.

require "NPCCore/NPCLegacyGlobalsBridge"
NPCMenuBridge = NPCLegacyGlobalsBridge.InstallAlias("Menu", NPCMenuBridge, "NPCMenuBridge")

require "NPCCore/NPCLegacyContractBridge"

local NPC_MENU_LEGACY_KEYS = NPCLegacyContractBridge.Keys
local NPC_MENU_LEGACY_COMMANDS = NPCLegacyContractBridge.Commands
local NPC_MENU_BASE_PLACEMENT_PROVIDER = "NPCBasePlacementsBridge"
local NPC_MENU_LEGACY_TEXT_PREFIX = NPCLegacyContractBridge.Text.prefix

local function bm_menuPlayerId(player)
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

local function bm_menuGroupId(brain)
    if not brain then return nil end
    return brain.worldGroupId or brain.groupId
end

local function bm_menuReadZombieId(zombie, modKey, varKey)
    if not zombie then return nil end
    local md = zombie.getModData and zombie:getModData() or nil
    if md and md[modKey] ~= nil and tostring(md[modKey]) ~= "" and tostring(md[modKey]) ~= "nil" then return md[modKey] end
    if varKey and zombie.getVariableString then
        local ok, value = pcall(function() return zombie:getVariableString(varKey) end)
        if ok and value ~= nil and tostring(value) ~= "" and tostring(value) ~= "nil" then return value end
    end
    return nil
end


local function bm_menuIsNPCZombie(zombie)
    if not (zombie and zombie.getVariableBoolean) then return false end
    local ok, result = pcall(function() return zombie:getVariableBoolean(NPC_MENU_LEGACY_KEYS.flag) end)
    return ok and result == true
end

local function bm_menuSay(player, text)
    if player and player.Say and text then pcall(function() player:Say(text) end) end
end

local function bm_menuSendClientCommand(player, module, command, args)
    if not sendClientCommand then return false end
    local ok = pcall(function() sendClientCommand(player, module, command, args or {}) end)
    if ok then return true end
    ok = pcall(function() sendClientCommand(module, command, args or {}) end)
    return ok == true
end

local function bm_menuIsMultiplayer()
    if not getWorld then return false end
    local world = getWorld()
    if not (world and world.getGameMode) then return false end
    return tostring(world:getGameMode()) == "Multiplayer"
end

local function bm_menuBrainSide(brain)
    if NPCFactionBridge and NPCFactionBridge.GetBrainSide then
        local ok, side = pcall(function() return NPCFactionBridge.GetBrainSide(brain) end)
        if ok and side then return side end
    end
    return brain and (brain.factionSide or brain.faction or brain.side or brain.patrolColor)
end

local function bm_menuBuildNPCArgs(bandit, brain)
    local args = {}
    if brain then
        args.id = brain.id or brain.runtimeId
        args.runtimeId = brain.runtimeId or brain.id
        args.uid = brain.uid
        args.persistentId = brain.persistentId
        args.groupId = bm_menuGroupId(brain)
        args.brainSide = bm_menuBrainSide(brain)
        args.mercenary = brain.mercenary == true
        args.mercenaryHired = brain.mercenaryHired == true
        args.fullname = brain.fullname or brain.name
    end
    if bandit then
        args.runtimeId = args.runtimeId or bm_menuReadZombieId(bandit, NPC_MENU_LEGACY_KEYS.runtimeId, NPC_MENU_LEGACY_KEYS.runtimeId)
        args.persistentId = args.persistentId or bm_menuReadZombieId(bandit, NPC_MENU_LEGACY_KEYS.persistentId, NPC_MENU_LEGACY_KEYS.persistentId)
        args.groupId = args.groupId or bm_menuReadZombieId(bandit, NPC_MENU_LEGACY_KEYS.worldGroupId, NPC_MENU_LEGACY_KEYS.worldGroupId)
        if not args.id and NPCUtils and NPCUtils.GetCharacterID then
            local ok, id = pcall(function() return NPCUtils.GetCharacterID(bandit) end)
            if ok and id ~= nil then args.id = id end
        end
        if bandit.getX then args.x = bandit:getX() end
        if bandit.getY then args.y = bandit:getY() end
        if bandit.getZ then args.z = bandit:getZ() end
    end
    args.id = args.id or args.runtimeId or args.persistentId
    return args
end

local function bm_menuHireMercenaryLocal(player, bandit, brain)
    if not (NPCMercenaryContract and NPCMercenaryContract.IsHireEnabled and NPCMercenaryContract.IsHireEnabled()) then return false end
    if not brain then return false end

    local targetSide = bm_menuBrainSide(brain)
    if targetSide ~= "blue" and brain.mercenary ~= true then
        bm_menuSay(player, "Only blue mercenary squads can be hired.")
        return false
    end

    local pid = bm_menuPlayerId(player)
    if not pid then return false end

    local gmd = GetNPCModData and GetNPCModData() or nil
    local groupId = bm_menuGroupId(brain)
    if groupId then groupId = tostring(groupId) end
    local group = gmd and gmd.VirtualGroups and groupId and gmd.VirtualGroups[groupId] or nil

    if group and group.mercenaryHiredBy and tostring(group.mercenaryHiredBy) ~= tostring(pid) then
        bm_menuSay(player, "This mercenary squad is already hired.")
        return false
    end

    local alreadyHired = (group and group.mercenaryHiredBy and tostring(group.mercenaryHiredBy) == tostring(pid))
        or (brain.mercenaryHiredBy and tostring(brain.mercenaryHiredBy) == tostring(pid))

    if not alreadyHired then
        local paid = NPCMercenaryContract.TakePayment and NPCMercenaryContract.TakePayment(player)
        if not paid then
            bm_menuSay(player, "Need payment: " .. tostring(NPCMercenaryContract.GetHireCostLabel and NPCMercenaryContract.GetHireCostLabel() or "jewelry"))
            return false
        end
    end

    if group and NPCMercenaryContract.HireGroup then
        NPCMercenaryContract.HireGroup(gmd, group, player, {formation="close", followDistance=3.0})
        gmd.VirtualGroups[groupId] = group
    end

    local changed = 0
    if gmd and gmd.Queue then
        for qid, qbrain in pairs(gmd.Queue) do
            local sameGroup = groupId and bm_menuGroupId(qbrain) and tostring(bm_menuGroupId(qbrain)) == groupId
            local sameTarget = qbrain == brain or tostring(qbrain.id or qid) == tostring(brain.id or "")
            if sameGroup or sameTarget then
                NPCMercenaryContract.HireBrain(qbrain, player, {formation="close", followDistance=3.0})
                gmd.Queue[qid] = qbrain
                changed = changed + 1
            end
        end
    end

    if not brain.mercenaryHiredBy or tostring(brain.mercenaryHiredBy) ~= tostring(pid) then
        NPCMercenaryContract.HireBrain(brain, player, {formation="close", followDistance=3.0})
        changed = changed + 1
    end

    if bandit and NPCBrainData and NPCBrainData.Update then NPCBrainData.Update(bandit, brain) end
    if bandit and NPCEntity and NPCEntity.ForceSyncPart then
        NPCEntity.ForceSyncPart(bandit, {
            id=brain.id,
            master=brain.master,
            hostile=brain.hostile,
            program=brain.program,
            order=brain.order,
            fireMode=brain.fireMode,
            rbFireMode=brain.rbFireMode,
            tasks=brain.tasks,
            relationshipToPlayer=brain.relationshipToPlayer,
            mercenary=brain.mercenary,
            mercenaryHired=brain.mercenaryHired,
            mercenaryHiredBy=brain.mercenaryHiredBy
        })
    end

    bm_menuSay(player, alreadyHired and "Mercenaries are already under your command." or "Mercenary squad hired.")
    return changed > 0
end

local function bm_text(key)
    key = tostring(key or "")
    if string.sub(key, 1, 5) == "IGUI_" then return getText(key) end
    return getText(NPC_MENU_LEGACY_TEXT_PREFIX .. key)
end

local function bm_menuIsAdmin()
    return isAdmin and isAdmin()
end

local function bm_sideLabel(side)
    local key = NPC_MENU_LEGACY_TEXT_PREFIX .. "Side_" .. tostring(side or "none")
    local label = getText(key)
    if label and label ~= key then return label end
    if NPCFactionBridge and NPCFactionBridge.GetSideLabel then return NPCFactionBridge.GetSideLabel(side) end
    return tostring(side or "none")
end

local function bm_menuIsHiredByPlayer(brain, player)
    if not brain then return false end
    local pid = bm_menuPlayerId(player)
    return pid ~= nil and brain.mercenaryHiredBy ~= nil and tostring(brain.mercenaryHiredBy) == tostring(pid)
end

local function bm_menuObjectSquare(obj)
    if obj and obj.getSquare then
        local ok, sq = pcall(function() return obj:getSquare() end)
        if ok and sq then return sq end
    end
    return nil
end

local function bm_menuClickedSquare(worldobjects, player)
    if NPCCompatibilityBridge and NPCCompatibilityBridge.GetClickedSquare then
        local ok, sq = pcall(function() return NPCCompatibilityBridge.GetClickedSquare() end)
        if ok and sq then return sq end
    end

    if type(worldobjects) == "table" then
        for _, obj in ipairs(worldobjects) do
            local sq = bm_menuObjectSquare(obj)
            if sq then return sq end
        end
    end

    if player and player.getSquare then
        local ok, sq = pcall(function() return player:getSquare() end)
        if ok and sq then return sq end
    end
    return nil
end

local function bm_menuGetSquareZombie(square, worldobjects)
    if not square then return nil end
    local checks = {square}

    if type(worldobjects) == "table" then
        for _, obj in ipairs(worldobjects) do
            if obj and obj.getVariableBoolean then
                local ok, isNPC = pcall(function() return bm_menuIsNPCZombie(obj) end)
                if ok and isNPC == true then return obj end
            end
            local sq = bm_menuObjectSquare(obj)
            if sq then table.insert(checks, sq) end
        end
    end
    if square.getS then
        local ok, sq = pcall(function() return square:getS() end)
        if ok and sq then table.insert(checks, sq) end
    end
    if square.getW then
        local ok, sq = pcall(function() return square:getW() end)
        if ok and sq then table.insert(checks, sq) end
    end
    if square.getN then
        local ok, sq = pcall(function() return square:getN() end)
        if ok and sq then table.insert(checks, sq) end
    end
    if square.getE then
        local ok, sq = pcall(function() return square:getE() end)
        if ok and sq then table.insert(checks, sq) end
    end

    for _, sq in ipairs(checks) do
        if sq and sq.getZombie then
            local ok, zombie = pcall(function() return sq:getZombie() end)
            if ok and zombie and zombie.getVariableBoolean and bm_menuIsNPCZombie(zombie) then return zombie end
        end
    end

    local cell = getCell and getCell() or nil
    if not (cell and cell.getZombieList and square.getX and square.getY) then return nil end

    local sx = square:getX()
    local sy = square:getY()
    local sz = square:getZ()
    local nearest = nil
    local nearestDist = 999999
    local okList, zombies = pcall(function() return cell:getZombieList() end)
    if not (okList and zombies and zombies.size) then return nil end

    for i = 0, zombies:size() - 1 do
        local zombie = zombies:get(i)
        if zombie and zombie.getVariableBoolean and bm_menuIsNPCZombie(zombie) then
            local zx = zombie:getX()
            local zy = zombie:getY()
            local zz = zombie.getZ and zombie:getZ() or sz
            if math.abs((zz or 0) - (sz or 0)) <= 0.5 then
                local dx = zx - sx
                local dy = zy - sy
                local dist = dx * dx + dy * dy
                if dist < nearestDist and dist <= 6.25 then
                    nearest = zombie
                    nearestDist = dist
                end
            end
        end
    end

    return nearest
end

local function bm_menuBrainHiredByPlayer(brain, player)
    if not brain then return false end
    local pid = bm_menuPlayerId(player)
    if not pid then return false end
    if brain.mercenaryHiredBy ~= nil and tostring(brain.mercenaryHiredBy) == tostring(pid) then return true end
    if brain.master ~= nil and tostring(brain.master) == tostring(pid) and (brain.mercenaryHired == true or brain.relationshipToPlayer == "hired_bodyguard" or brain.factionState == "hired_blue_bodyguard") then return true end
    return false
end

local function bm_menuFindNearbyHiredMercenary(player, square, worldobjects)
    if not player then return nil, nil end

    local direct = bm_menuGetSquareZombie(square, worldobjects)
    if direct then
        local brain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(direct) or nil
        if bm_menuBrainHiredByPlayer(brain, player) then return direct, brain end
    end

    local px = nil
    local py = nil
    local pz = nil
    if square and square.getX then
        px = square:getX()
        py = square:getY()
        pz = square:getZ()
    elseif player and player.getX then
        px = player:getX()
        py = player:getY()
        pz = player.getZ and player:getZ() or 0
    end
    if not (px and py) then return nil, nil end

    local cell = getCell and getCell() or nil
    if not (cell and cell.getZombieList) then return nil, nil end

    local okList, zombies = pcall(function() return cell:getZombieList() end)
    if not (okList and zombies and zombies.size) then return nil, nil end

    local nearest = nil
    local nearestBrain = nil
    local nearestDist = 999999
    for i = 0, zombies:size() - 1 do
        local zombie = zombies:get(i)
        if zombie and zombie.getVariableBoolean and bm_menuIsNPCZombie(zombie) then
            local brain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(zombie) or nil
            if bm_menuBrainHiredByPlayer(brain, player) then
                local zz = zombie.getZ and zombie:getZ() or pz
                if math.abs((tonumber(zz) or 0) - (tonumber(pz) or 0)) <= 1.0 then
                    local dx = zombie:getX() - px
                    local dy = zombie:getY() - py
                    local dist = dx * dx + dy * dy
                    if dist < nearestDist and dist <= 64.0 then
                        nearest = zombie
                        nearestBrain = brain
                        nearestDist = dist
                    end
                end
            end
        end
    end

    return nearest, nearestBrain
end

function NPCMenuBridge.HasHiredMercenaries(player)
    local pid = bm_menuPlayerId(player)
    if not pid then return false end
    local gmd = GetNPCModData and GetNPCModData() or nil
    if not gmd then return false end

    if gmd.Queue then
        for _, brain in pairs(gmd.Queue) do
            if brain and brain.mercenaryHiredBy and tostring(brain.mercenaryHiredBy) == tostring(pid) then return true end
        end
    end
    if gmd.VirtualGroups then
        for _, group in pairs(gmd.VirtualGroups) do
            if group and group.mercenaryHiredBy and tostring(group.mercenaryHiredBy) == tostring(pid) then return true end
        end
    end

    local cell = getCell and getCell() or nil
    if cell and cell.getZombieList then
        local okList, zombies = pcall(function() return cell:getZombieList() end)
        if okList and zombies and zombies.size then
            for i = 0, zombies:size() - 1 do
                local zombie = zombies:get(i)
                if zombie and zombie.getVariableBoolean and bm_menuIsNPCZombie(zombie) then
                    local brain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(zombie) or nil
                    if bm_menuBrainHiredByPlayer(brain, player) then return true end
                end
            end
        end
    end
    return false
end

function NPCMenuBridge.BribeSpy(player, bandit)
    if not bandit then return end
    local brain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(bandit) or nil
    if not brain then return end
    local runtimeId = brain.id or (NPCUtils and NPCUtils.GetCharacterID and NPCUtils.GetCharacterID(bandit))
    local payment = NPCSpyBridge and NPCSpyBridge.CountPayment and NPCSpyBridge.CountPayment(player) or nil
    sendClientCommand(player, 'NPCCommands', 'BribeSpy', {
        id = runtimeId,
        runtimeId = runtimeId,
        uid = brain.uid,
        persistentId = brain.persistentId,
        groupId = bm_menuGroupId(brain),
        x = bandit.getX and bandit:getX() or brain.x,
        y = bandit.getY and bandit:getY() or brain.y,
        z = bandit.getZ and bandit:getZ() or brain.z,
        clientGold = payment and payment.gold or nil,
        clientSilver = payment and payment.silver or nil
    })
end


local function bm_menuAttachMercenaryPaymentSnapshot(args, player)
    if not args then return args end
    if NPCMercenaryContract and NPCMercenaryContract.GetPaymentCounts then
        local ok, counts = pcall(function() return NPCMercenaryContract.GetPaymentCounts(player) end)
        if ok and type(counts) == "table" then
            args.clientPaymentGoldCount = tonumber(counts.gold) or 0
            args.clientPaymentSilverCount = tonumber(counts.silver) or 0
        end
    end
    if NPCMercenaryContract and NPCMercenaryContract.HasPayment then
        local ok, hasPayment = pcall(function() return NPCMercenaryContract.HasPayment(player) end)
        if ok then args.clientPaymentOk = hasPayment == true end
    end
    return args
end

function NPCMenuBridge.HireMercenaryGroup(player, banditOrArgs)
    if not banditOrArgs then return end

    local args = nil
    local bandit = nil
    local brain = nil

    if type(banditOrArgs) == "table" and not banditOrArgs.getModData then
        args = banditOrArgs
    else
        bandit = banditOrArgs
        brain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(bandit) or nil
        args = bm_menuBuildNPCArgs(bandit, brain)
    end

    if not bm_menuIsMultiplayer() then
        if bandit and brain then bm_menuHireMercenaryLocal(player, bandit, brain) end
        return
    end

    if not (args and (args.id or args.runtimeId or args.persistentId or args.groupId or (args.x and args.y))) then
        bm_menuSay(player, "Mercenary target is not synchronized yet. Reopen the menu closer to the NPC.")
        return
    end

    bm_menuAttachMercenaryPaymentSnapshot(args, player)

    print("[NPCMercenary] hire click id=" .. tostring(args.id) .. " runtime=" .. tostring(args.runtimeId) .. " pid=" .. tostring(args.persistentId) .. " group=" .. tostring(args.groupId) .. " x=" .. tostring(args.x) .. " y=" .. tostring(args.y) .. " gold=" .. tostring(args.clientPaymentGoldCount) .. " silver=" .. tostring(args.clientPaymentSilverCount) .. " clientPayment=" .. tostring(args.clientPaymentOk))
    if not bm_menuSendClientCommand(player, 'NPCCommands', 'HireMercenaryGroup', args) then
        bm_menuSay(player, "Mercenary hire command could not be sent.")
    end
end

function NPCMenuBridge.TakePrisoner(player, bandit)
    if not bandit then return end
    local brain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(bandit) or nil
    if not brain then return end
    sendClientCommand(player, 'NPCCommands', 'TakePrisoner', {
        id = brain.id or (NPCUtils and NPCUtils.GetCharacterID and NPCUtils.GetCharacterID(bandit)),
        groupId = bm_menuGroupId(brain)
    })
end

function NPCMenuBridge.InterrogatePrisoner(player, bandit)
    if not bandit then return end
    local brain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(bandit) or nil
    if not brain then return end
    sendClientCommand(player, 'NPCCommands', 'InterrogatePrisoner', {
        id = brain.id or (NPCUtils and NPCUtils.GetCharacterID and NPCUtils.GetCharacterID(bandit)),
        groupId = bm_menuGroupId(brain)
    })
end

function NPCMenuBridge.ReleasePrisoner(player, bandit)
    if not bandit then return end
    local brain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(bandit) or nil
    if not brain then return end
    sendClientCommand(player, 'NPCCommands', 'ReleasePrisoner', {
        id = brain.id or (NPCUtils and NPCUtils.GetCharacterID and NPCUtils.GetCharacterID(bandit)),
        groupId = bm_menuGroupId(brain)
    })
end

function NPCMenuBridge.MercenaryOrder(player, square, orderName, fireMode, formation, followDistance, groupId)
    local args = {
        orderName = orderName,
        fireMode = fireMode,
        formation = formation,
        followDistance = followDistance,
        groupId = groupId
    }
    if square then
        args.x = square:getX()
        args.y = square:getY()
        args.z = square:getZ()
    elseif player then
        args.x = player:getX()
        args.y = player:getY()
        args.z = player:getZ()
    end
    if player and player.getDirectionAngle then
        local ok, angle = pcall(function() return player:getDirectionAngle() end)
        if ok and angle then args.facingAngle = tonumber(angle) end
    end
    print("[NPCMercenary] order click group=" .. tostring(args.groupId) .. " order=" .. tostring(args.orderName) .. " fire=" .. tostring(args.fireMode) .. " formation=" .. tostring(args.formation) .. " x=" .. tostring(args.x) .. " y=" .. tostring(args.y))
    if not bm_menuSendClientCommand(player, 'NPCCommands', 'MercenaryGroupOrder', args) then
        bm_menuSay(player, "Mercenary order command could not be sent.")
    end
end

function NPCMenuBridge.AddMercenaryOrdersMenu(context, player, square, groupId)
    if not (NPCMercenaryContract and NPCMercenaryContract.IsHireEnabled and NPCMercenaryContract.IsHireEnabled()) then return end
    if not groupId and not NPCMenuBridge.HasHiredMercenaries(player) then return end

    local root = context:addOption(groupId and bm_text("Menu_ThisMercenarySquadOrders") or bm_text("Menu_MercenaryBodyguardOrders"))
    local menu = context:getNew(context)
    context:addSubMenu(root, menu)

    menu:addOption(bm_text("Menu_FollowMe"), player, NPCMenuBridge.MercenaryOrder, square, "Follow", nil, nil, nil, groupId)
    menu:addOption(bm_text("Menu_MoveHoldHere"), player, NPCMenuBridge.MercenaryOrder, square, "Hold", nil, nil, nil, groupId)
    menu:addOption(bm_text("Menu_GuardHere"), player, NPCMenuBridge.MercenaryOrder, square, "Guard", nil, nil, nil, groupId)
    menu:addOption(bm_text("Menu_GuardHere") .. " - " .. bm_text("Menu_FormationWide"), player, NPCMenuBridge.MercenaryOrder, square, "Guard", nil, "wide", 5.0, groupId)
    menu:addOption(bm_text("Menu_GuardHere") .. " - " .. bm_text("Menu_FormationLine"), player, NPCMenuBridge.MercenaryOrder, square, "Guard", nil, "line", 4.0, groupId)
    menu:addOption(bm_text("Menu_PatrolThisArea"), player, NPCMenuBridge.MercenaryOrder, square, "Patrol", nil, nil, nil, groupId)
    menu:addOption(bm_text("Menu_LootThisArea"), player, NPCMenuBridge.MercenaryOrder, square, "Loot", nil, nil, nil, groupId)
    menu:addOption(bm_text("Menu_LootThisHouse"), player, NPCMenuBridge.MercenaryOrder, square, "LootHouse", nil, nil, nil, groupId)
    menu:addOption(bm_text("Menu_ReturnToThisPoint"), player, NPCMenuBridge.MercenaryOrder, square, "Return", nil, nil, nil, groupId)

    local tacticalRoot = menu:addOption(bm_text("Menu_TacticalOrders"))
    local tacticalMenu = menu:getNew(menu)
    menu:addSubMenu(tacticalRoot, tacticalMenu)
    tacticalMenu:addOption(bm_text("Menu_TacticalFlank"), player, NPCMenuBridge.MercenaryOrder, square, "Flank", nil, "wide", 5.0, groupId)
    tacticalMenu:addOption(bm_text("Menu_TacticalEncircle"), player, NPCMenuBridge.MercenaryOrder, square, "Encircle", nil, "ring", 4.0, groupId)
    tacticalMenu:addOption(bm_text("Menu_TacticalBackToBack"), player, NPCMenuBridge.MercenaryOrder, square, "BackToBack", nil, "ring", 2.4, groupId)
    tacticalMenu:addOption(bm_text("Menu_TacticalTakeCover"), player, NPCMenuBridge.MercenaryOrder, square, "TakeCover", nil, "wide", 4.0, groupId)
    tacticalMenu:addOption(bm_text("Menu_TacticalAdvance"), player, NPCMenuBridge.MercenaryOrder, square, "Advance", nil, "wedge", 4.0, groupId)
    tacticalMenu:addOption(bm_text("Menu_TacticalFallBack"), player, NPCMenuBridge.MercenaryOrder, square, "FallBack", nil, "line", 4.0, groupId)
    tacticalMenu:addOption(bm_text("Menu_TacticalWatchSector"), player, NPCMenuBridge.MercenaryOrder, square, "WatchSector", nil, "line", 4.0, groupId)

    local fireRoot = menu:addOption(bm_text("Menu_FireDiscipline"))
    local fireMenu = menu:getNew(menu)
    menu:addSubMenu(fireRoot, fireMenu)
    fireMenu:addOption(bm_text("Menu_FireAtWill"), player, NPCMenuBridge.MercenaryOrder, square, nil, "FireAtWill", nil, nil, groupId)
    fireMenu:addOption(bm_text("Menu_DefensiveFire"), player, NPCMenuBridge.MercenaryOrder, square, nil, "Defensive", nil, nil, groupId)
    fireMenu:addOption(bm_text("Menu_HoldFire"), player, NPCMenuBridge.MercenaryOrder, square, nil, "HoldFire", nil, nil, groupId)
    fireMenu:addOption(bm_text("Menu_MeleeOnly"), player, NPCMenuBridge.MercenaryOrder, square, nil, "MeleeOnly", nil, nil, groupId)
    fireMenu:addOption(bm_text("Menu_ReturnFire"), player, NPCMenuBridge.MercenaryOrder, square, nil, "ReturnFire", nil, nil, groupId)
    fireMenu:addOption(bm_text("Menu_DangerClose"), player, NPCMenuBridge.MercenaryOrder, square, nil, "DangerClose", nil, nil, groupId)
    fireMenu:addOption(bm_text("Menu_Suppress"), player, NPCMenuBridge.MercenaryOrder, square, nil, "Suppress", nil, nil, groupId)

    local formRoot = menu:addOption(bm_text("Menu_Formation"))
    local formMenu = menu:getNew(menu)
    menu:addSubMenu(formRoot, formMenu)
    formMenu:addOption(bm_text("Menu_FormationClose"), player, NPCMenuBridge.MercenaryOrder, square, nil, nil, "close", 3.0, groupId)
    formMenu:addOption(bm_text("Menu_BodyguardRing"), player, NPCMenuBridge.MercenaryOrder, square, nil, nil, "ring", 3.0, groupId)
    formMenu:addOption(bm_text("Menu_FormationWide"), player, NPCMenuBridge.MercenaryOrder, square, nil, nil, "wide", 5.0, groupId)
    formMenu:addOption(bm_text("Menu_FormationLine"), player, NPCMenuBridge.MercenaryOrder, square, nil, nil, "line", 4.0, groupId)
    formMenu:addOption(bm_text("Menu_FormationWedge"), player, NPCMenuBridge.MercenaryOrder, square, nil, nil, "wedge", 4.0, groupId)
end


function NPCMenuBridge.SetPlayerFaction(player, side)
    if NPCFactionBridge and NPCFactionBridge.SetPlayerSide then
        NPCFactionBridge.SetPlayerSide(player, side, "manual_menu")
    end
end

function NPCMenuBridge.AddPlayerFactionMenu(context, player)
    if not (NPCFactionBridge and NPCFactionBridge.IsEnabled and NPCFactionBridge.IsEnabled()) then return end
    if not NPCFactionBridge.IsMenuEnabled() then return end

    local current = NPCFactionBridge.GetPlayerSide(player)
    local root = context:addOption(bm_text("Menu_PlayerFaction") .. ": " .. bm_sideLabel(current))
    local menu = context:getNew(context)
    context:addSubMenu(root, menu)

    menu:addOption(bm_text("Side_red"), player, NPCMenuBridge.SetPlayerFaction, "red")
    menu:addOption(bm_text("Side_green"), player, NPCMenuBridge.SetPlayerFaction, "green")
    menu:addOption(bm_text("Menu_BlueNeutral"), player, NPCMenuBridge.SetPlayerFaction, "blue")
    menu:addOption(bm_text("Menu_BlackRogue"), player, NPCMenuBridge.SetPlayerFaction, "black")
end

function NPCMenuBridge.MakeProcedure (player, square)
    local cell = getCell()

    local sx = square:getX()
    local sy = square:getY()
    local sz = square:getZ()

    local w = 44
    local h = 44

    local lines = {}

    table.insert(lines, "require \"MysteryPlacements\"\n")
    table.insert(lines, "\n")
    table.insert(lines, "function ProcMedicalTent (sx, sy, sz)\n")
    
    for x = 0, w do
        for y = 0, h do
            for z = 0, 4 do
                local square = cell:getGridSquare(sx + x, sy + y, sz + z)
                if square then
                    local objects = square:getObjects()

                    for i=0, objects:size()-1 do
                        local object = objects:get(i)
                        if object then

                            local objectType = object:getType()
                            local spriteName = object:getSprite():getName()
                            local spriteProps = object:getSprite():getProperties()

                            local isSolidFloor = spriteProps:Is(IsoFlagType.solidfloor)
                            local isAttachedFloor = spriteProps:Is(IsoFlagType.attachedFloor)
                            local isExterior = spriteProps:Is(IsoFlagType.exterior)
                            local isCanBeRemoved = spriteProps:Is(IsoFlagType.canBeRemoved)
                            
                            if spriteName then
                                --[[if isSolidFloor and isExterior and not isAttachedFloor then
                                    --nature floor - skip it
                                    print ("nature floor")
                                elseif objectType == IsoObjectType.tree then
                                    print ("tree")

                                elseif isCanBeRemoved == true then
                                    print ("grass")

                                elseif isSolidFloor or isAttachedFloor then
                                    --floors
                                    table.insert(lines, "\t" .. NPC_MENU_BASE_PLACEMENT_PROVIDER .. ".IsoObject (\"" .. spriteName .. "\", sx + " .. tostring(x) .. ", sy + " .. tostring(y) .. ", sz + " .. tostring(z) .. ")\n")
                                
                                elseif false and objectType == IsoObjectType.wall then
                                    -- walls 
                                    table.insert(lines, "\t" .. NPC_MENU_BASE_PLACEMENT_PROVIDER .. ".IsoThumpable (\"" .. spriteName .. "\", sx + " .. tostring(x) .. ", sy + " .. tostring(y) .. ", sz + " .. tostring(z) .. ")\n")
                                ]]
                                if instanceof(object, 'IsoDoor') then
                                    -- door
                                    table.insert(lines, "\t" .. NPC_MENU_BASE_PLACEMENT_PROVIDER .. ".IsoDoor (\"" .. spriteName .. "\", sx + " .. tostring(x) .. ", sy + " .. tostring(y) .. ", sz + " .. tostring(z) .. ")\n")

                                elseif instanceof(object, 'IsoWindow') then
                                    -- window
                                    table.insert(lines, "\t" .. NPC_MENU_BASE_PLACEMENT_PROVIDER .. ".IsoWindow (\"" .. spriteName .. "\", sx + " .. tostring(x) .. ", sy + " .. tostring(y) .. ", sz + " .. tostring(z) .. ")\n")

                                else
                                    -- special objects?
                                    table.insert(lines, "\t" .. NPC_MENU_BASE_PLACEMENT_PROVIDER .. ".IsoObject (\"" .. spriteName .. "\", sx + " .. tostring(x) .. ", sy + " .. tostring(y) .. ", sz + " .. tostring(z) .. ")\n")
                                    
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    local fileWriter = getFileWriter("test6.txt", true, true)
    table.insert(lines, "end\n\n")

    local output = ""
    for k, v in pairs(lines) do
        output = output .. v
    end
    print (output)
    fileWriter:write(output)
    fileWriter:close()
                            
end

function NPCMenuBridge.SpawnGroup (player, waveId)
    if not bm_menuIsAdmin() then return end

    local waveData = NPCScheduler.GetWaveDataAll()
    local wave = waveData[waveId]
    wave.spawnDistance = 3
    NPCScheduler.SpawnWave(player, wave)
end

function NPCMenuBridge.SpawnGroupFar (player, waveId)
    if not bm_menuIsAdmin() then return end

    local waveData = NPCScheduler.GetWaveDataAll()
    local wave = waveData[waveId]
    wave.spawnDistance = 50
    NPCScheduler.SpawnWave(player, wave)
end

function NPCMenuBridge.SpawnDefenders (player, square)
    if not bm_menuIsAdmin() then return end

    NPCScheduler.SpawnDefenders(player, 1, 15)
end

function NPCMenuBridge.RaiseDefences (player, square)
    NPCScheduler.RaiseDefences(square:getX(), square:getY())
end

function NPCMenuBridge.SpawnCivilian (player, square)
    NPCScheduler.SpawnCivilian(player)
end

function NPCMenuBridge.BaseballMatch (player, square)
    NPCScheduler.BaseballMatch(player)
end

function NPCMenuBridge.ClearSpace (player, square)
    NPCBaseGroupPlacementsBridge.ClearSpace (player:getX(), player:getY(), player:getZ(), 50, 50)
end

function NPCMenuBridge.BroadcastTV (player, square)
    NPCScheduler.BroadcastTV(square:getX(), square:getY())
end

function NPCMenuBridge.TestAction (player, square, zombie)

    local task = {action="Time", anim="DanceHipHop3", time=400}
    NPCEntity.AddTask(zombie, task)
end

function NPCMenuBridge.Zombify (player, zombie)
    local task = {action="Zombify", anim="Faint", time=400}
    NPCEntity.AddTask(zombie, task)
end

function NPCMenuBridge.SpawnBase (player, square, sceneNo)
    if not bm_menuIsAdmin() then return end

    NPCScheduler.SpawnBase(player, sceneNo)
end

function NPCMenuBridge.CheckFloor (player, square)
    local canPlace = NPCBaseGroupPlacementsBridge.CheckSpace(square:getX(), square:getY(), 32, 32)
    print ("CANPLACE: " .. tostring(canPlace))
end

function NPCMenuBridge.ShowBrain (player, square, zombie)
    local gmd = GetNPCModData()

    local bcnt = 0
    for k, v in pairs(gmd.Queue) do
        bcnt = bcnt + 1
    end

    -- add breakpoint below to see data
    local brain = NPCBrainData.Get(zombie)
    local moddata = zombie:getModData()
    local id = NPCUtils.GetCharacterID(zombie)
    local daysPassed = NPCScheduler.DaysSinceApo()
    local isUseless = zombie:isUseless()
    local isNPC = bm_menuIsNPCZombie(zombie)
    local walktype = zombie:getVariableString("zombieWalkType")
    local walktype2 = zombie:getVariableString(NPC_MENU_LEGACY_KEYS.walkType)
    local isNPCTarget = zombie:getVariableString(NPC_MENU_LEGACY_KEYS.target)
    local walktype2 = zombie:getVariableString(NPC_MENU_LEGACY_KEYS.walkType)
    local primary = zombie:getVariableString(NPC_MENU_LEGACY_KEYS.primary)
    local primaryType = zombie:getVariableString(NPC_MENU_LEGACY_KEYS.primaryType)
    local secondary = zombie:getVariableString(NPC_MENU_LEGACY_KEYS.secondary)
    local outfit = zombie:getOutfitName()
    local ans = zombie:getActionStateName()
    local under = zombie:isUnderVehicle()
    local veh = zombie:getVehicle()
    local health = zombie:getHealth()
    local zx = zombie:getX()
    local zy = zombie:getY()
    local hv = zombie:getHumanVisual()
    local bv = hv:getBodyVisuals()
    local moddata = zombie:getModData()
    local target = zombie:getTarget()
    local animator = zombie:getAdvancedAnimator()
    local inventory = zombie:getInventory()
    -- local astate = zombie:getAnimationDebug()
    local waveData = NPCScheduler.GetWaveDataForDay(daysPassed)
    local baseData = NPCBaseClient.data

end

function NPCMenuBridge.NPCFlush(player)
    if not bm_menuIsAdmin() then return end

    local args = {a=1}
    sendClientCommand(player, 'NPCCommands', NPC_MENU_LEGACY_COMMANDS.flush, args)
end

-- NPCMenuBridge legacy menu aliases for compatibility with old extensions.
local NPC_MENU_LEGACY_TOKEN = "Ban" .. "dit"
NPCMenuBridge[NPC_MENU_LEGACY_TOKEN .. "Flush"] = NPCMenuBridge.NPCFlush

function NPCMenuBridge.ResetGenerator (player, generator)
    generator:setFuel(20)
    generator:setCondition(50)
end

function NPCMenuBridge.RegenerateBase (player)
    NPCBaseClient.Regenerate(player)
end

function NPCMenuBridge.SwitchProgram(player, bandit, program)
    local brain = NPCBrainData.Get(bandit)
    if brain then
        local args = {
            id = brain.id or (NPCUtils and NPCUtils.GetCharacterID and NPCUtils.GetCharacterID(bandit)),
            groupId = bm_menuGroupId(brain),
            program = program
        }

        if getWorld and getWorld():getGameMode() == "Multiplayer" then
            sendClientCommand(player, 'NPCCommands', 'SwitchProgram', args)
            return
        end

        local pid = bm_menuPlayerId(player)
        brain.master = program == "Looter" and false or pid
        brain.program = {}
        brain.program.name = program
        brain.program.stage = "Prepare"
        brain.hostile = false
        brain.tasks = {}
        if program == "Companion" or program == "CompanionGuard" then
            brain.relationshipToPlayer = "companion"
            brain.order = brain.order or {}
            brain.order.name = program == "CompanionGuard" and "Guard" or "Follow"
            brain.order.source = "neutral_join"
            brain.order.master = pid
            brain.order.priority = 90
            brain.order.fireMode = brain.order.fireMode or "Defensive"
            brain.order.formation = brain.order.formation or "close"
            brain.order.followDistance = brain.order.followDistance or 3.0
            brain.fireMode = brain.order.fireMode
            brain.rbFireMode = brain.fireMode
        else
            brain.relationshipToPlayer = "neutral"
            brain.order = false
            brain.fireMode = false
            brain.rbFireMode = false
        end
        NPCBrainData.Update(bandit, brain)

        local syncData = {}
        syncData.id = args.id
        syncData.master = brain.master
        syncData.hostile = brain.hostile
        syncData.program = brain.program
        syncData.order = brain.order
        syncData.fireMode = brain.fireMode
        syncData.rbFireMode = brain.rbFireMode
        syncData.tasks = brain.tasks
        syncData.relationshipToPlayer = brain.relationshipToPlayer
        NPCEntity.ForceSyncPart(bandit, syncData)
    end
end

function NPCMenuBridge.WorldContextMenuPre(playerID, context, worldobjects, test)
    local world = getWorld()
    local gamemode = world:getGameMode()
    local player = getSpecificPlayer(playerID)
    local square = bm_menuClickedSquare(worldobjects, player)
    local generator = nil
    if square and square.getGenerator then
        local ok, gen = pcall(function() return square:getGenerator() end)
        if ok then generator = gen end
    end

    NPCMenuBridge.AddPlayerFactionMenu(context, player)
    NPCMenuBridge.AddMercenaryOrdersMenu(context, player, square)
    if NPCBaseCaptureUIBridge and NPCBaseCaptureUIBridge.AddContextMenu then
        NPCBaseCaptureUIBridge.AddContextMenu(context, player)
    end

    local zombie = bm_menuGetSquareZombie(square, worldobjects)
    local hiredZombie, hiredBrain = bm_menuFindNearbyHiredMercenary(player, square, worldobjects)
    if hiredZombie then zombie = hiredZombie end
    
    -- Player options
    if zombie and bm_menuIsNPCZombie(zombie) then
        local brain = hiredZombie == zombie and hiredBrain or NPCBrainData.Get(zombie)
        if brain then
            local isBlueMerc = NPCMercenaryContract and NPCMercenaryContract.IsBlueMercenaryBrain and NPCMercenaryContract.IsBlueMercenaryBrain(brain)
            local banditOption = nil
            local banditMenu = nil

            if NPCPrisonerBridge and brain.prisoner == true then
                banditOption = context:addOption((brain.fullname or bm_text("Menu_Prisoner")) .. " [" .. bm_text("Menu_StatusPrisoner") .. "]")
                banditMenu = context:getNew(context)
                context:addSubMenu(banditOption, banditMenu)
                if NPCPrisonerBridge.CanInterrogateBrain and NPCPrisonerBridge.CanInterrogateBrain(brain, player) then
                    banditMenu:addOption(bm_text("Menu_InterrogateForIntel"), player, NPCMenuBridge.InterrogatePrisoner, zombie)
                end
                banditMenu:addOption(bm_text("Menu_ReleasePrisoner"), player, NPCMenuBridge.ReleasePrisoner, zombie)
            elseif NPCPrisonerBridge and NPCPrisonerBridge.CanTakeBrain and NPCPrisonerBridge.CanTakeBrain(brain, player) then
                banditOption = context:addOption((brain.fullname or bm_text("Menu_SurrenderedEnemy")) .. " [" .. bm_text("Menu_StatusSurrendered") .. "]")
                banditMenu = context:getNew(context)
                context:addSubMenu(banditOption, banditMenu)
                banditMenu:addOption(bm_text("Menu_TakePrisoner"), player, NPCMenuBridge.TakePrisoner, zombie)
            elseif NPCSpyBridge and NPCSpyBridge.CanBribeBrain and NPCSpyBridge.CanBribeBrain(brain, player) then
                banditOption = context:addOption((brain.fullname or bm_text("Menu_Enemy")) .. " [" .. bm_text("Menu_StatusEnemy") .. "]")
                banditMenu = context:getNew(context)
                context:addSubMenu(banditOption, banditMenu)
                local spyCost = NPCSpyBridge.GetPaymentLabel and NPCSpyBridge.GetPaymentLabel() or "jewelry"
                banditMenu:addOption(bm_text("Menu_RecruitAsSpyFor") .. " " .. tostring(spyCost), player, NPCMenuBridge.BribeSpy, zombie)
            elseif isBlueMerc then
                banditOption = context:addOption((brain.fullname or bm_text("Menu_BlueMercenary")) .. " [" .. bm_text("Menu_StatusMercenary") .. "]")
                banditMenu = context:getNew(context)
                context:addSubMenu(banditOption, banditMenu)
                if bm_menuIsHiredByPlayer(brain, player) then
                    banditMenu:addOption(bm_text("Menu_OrdersForThisSquad"), player, NPCMenuBridge.MercenaryOrder, square, "Follow", nil, nil, nil, bm_menuGroupId(brain))
                    NPCMenuBridge.AddMercenaryOrdersMenu(banditMenu, player, square, bm_menuGroupId(brain))
                else
                    local cost = NPCMercenaryContract and NPCMercenaryContract.GetHireCostLabel and NPCMercenaryContract.GetHireCostLabel() or "resources"
                    banditMenu:addOption(bm_text("Menu_HireSquadFor") .. " " .. tostring(cost), player, NPCMenuBridge.HireMercenaryGroup, bm_menuBuildNPCArgs(zombie, brain))
                end
            elseif not brain.hostile and (tonumber(brain.clan) or 0) > 0 then
                local programName = brain.program and brain.program.name or "Looter"
                banditOption = context:addOption(brain.fullname or bm_text("Menu_BlueNeutral"))
                banditMenu = context:getNew(context)

                if programName == "Looter" then
                    context:addSubMenu(banditOption, banditMenu)
                    banditMenu:addOption(bm_text("Menu_JoinMe"), player, NPCMenuBridge.SwitchProgram, zombie, "Companion")
                elseif programName == "Companion" or programName == "CompanionGuard" then
                    context:addSubMenu(banditOption, banditMenu)
                    banditMenu:addOption(bm_text("Menu_LeaveMe"), player, NPCMenuBridge.SwitchProgram, zombie, "Looter")
                end
            end
        end
    end

    -- Admin spawn options
    if bm_menuIsAdmin() then
        local spawnOption = context:addOption(bm_text("Menu_Spawn" .. NPCLegacyContractBridge.Plural .. "Here"))
        local spawnMenu = context:getNew(context)
        context:addSubMenu(spawnOption, spawnMenu)
        for i=1, 16 do
            spawnMenu:addOption(bm_text("Menu_Wave") .. " " .. tostring(i), player, NPCMenuBridge.SpawnGroup, i)
        end

        local spawnOptionFar = context:addOption(bm_text("Menu_Spawn" .. NPCLegacyContractBridge.Plural .. "Far"))
        local spawnMenuFar = context:getNew(context)
        context:addSubMenu(spawnOptionFar, spawnMenuFar)
        for i=1, 16 do
            spawnMenuFar:addOption(bm_text("Menu_Wave") .. " " .. tostring(i), player, NPCMenuBridge.SpawnGroupFar, i)
        end

        context:addOption(bm_text("Menu_Spawn" .. NPCLegacyContractBridge.Token .. "Defenders"), player, NPCMenuBridge.SpawnDefenders, square)

        local spawnBaseOption = context:addOption(bm_text("Menu_Spawn" .. NPCLegacyContractBridge.Token .. "BaseFar"))
        local spawnBaseMenu = context:getNew(context)
        context:addSubMenu(spawnBaseOption, spawnBaseMenu)
        for i=1, 2 do
            spawnBaseMenu:addOption(bm_text("Menu_Base") .. " " .. tostring(i), player, NPCMenuBridge.SpawnBase, square, i)
        end

        context:addOption(bm_text("Menu_RemoveAll" .. NPCLegacyContractBridge.Plural), player, NPCMenuBridge.NPCFlush, square)
    end
    
    -- Debug options
    if isDebugEnabled() then
        print (NPCUtils.GetCharacterID(player))
        print (player:getHoursSurvived() / 24)
        print ("SPAWN BOOST: " .. NPCScheduler.GetDensityScore(player, 120) .. "%")
        context:addOption("[DGB] " .. bm_text("Menu_DebugMakeProcedure"), player, NPCMenuBridge.MakeProcedure, square)
        context:addOption("[DGB] " .. bm_text("Menu_DebugPlacePlane"), player, NPCMenuBridge.PlacePlane, square)

        if zombie then
            print ("this is zombie index: " .. NPCUtils.GetCharacterID(zombie))
            print ("this zombie dir is: " .. zombie:getDirectionAngle())
            context:addOption("[DGB] " .. bm_text("Menu_DebugShowBrain"), player, NPCMenuBridge.ShowBrain, square, zombie)
            context:addOption("[DGB] " .. bm_text("Menu_DebugTestAction"), player, NPCMenuBridge.TestAction, square, zombie)
            context:addOption("[DGB] " .. bm_text("Menu_DebugZombify"), player, NPCMenuBridge.Zombify, zombie)

          
        end

        -- context:addOption("[DGB] NPC UI", player, ShowCustomizationUI)

        -- context:addOption("[DGB] NPC Diagnostics", player, NPCMenuBridge.RemoveAlllegacy NPCs)
        -- context:addOption("[DGB] Clear Space", player, NPCMenuBridge.ClearSpace, square)
        -- context:addOption("[DGB] Regenerate base", player, NPCMenuBridge.RegenerateBase)
        -- context:addOption("[DGB] Raise Defences", player, NPCMenuBridge.RaiseDefences, square)
        -- context:addOption("[DGB] Emergency TC Broadcast", player, NPCMenuBridge.BroadcastTV, square)
        
        -- if generator then
        --    context:addOption("[DGB] Reset generator", player, NPCMenuBridge.ResetGenerator, generator)
        -- end

    end
end

Events.OnPreFillWorldObjectContextMenu.Add(NPCMenuBridge.WorldContextMenuPre)
