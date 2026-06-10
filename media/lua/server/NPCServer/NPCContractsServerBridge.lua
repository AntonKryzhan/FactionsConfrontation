-- NPCContractsServerBridge.lua
-- Neutral server command backend for player faction contracts.

if isClient and isClient() then return end

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCContractsBridge"
require "NPCCore/NPCDiagnosticsBridge"
require "NPCServer/NPCWorldDirector"
require "NPCServer/NPCWorldDirectorBridge"

NPCContractsServerBridge = NPCContractsServerBridge or {}

local function bcs_say(player, text)
    if player and player.Say and text then pcall(function() player:Say(text) end) end
end

local function bcs_halo(player, text, r, g, b)
    if player and text then
        sendServerCommand(player, 'NPCContracts', 'Result', {text=text, r=r or 180, g=g or 230, b=b or 255})
    end
end

local function bcs_ensure(gmd)
    if not gmd then return end
    if not gmd.DebugMapMarkers then gmd.DebugMapMarkers = {} end
    if NPCContractsBridge and NPCContractsBridge.EnsureData then NPCContractsBridge.EnsureData(gmd) end
end

local function bcs_setMarker(gmd, marker)
    if not gmd or not marker or not marker.id then return end
    if not gmd.DebugMapMarkers then gmd.DebugMapMarkers = {} end
    marker.updatedAt = NPCContractsBridge and NPCContractsBridge.NowHours and NPCContractsBridge.NowHours() or 0
    gmd.DebugMapMarkers[tostring(marker.id)] = marker
    if NPCNetContract and NPCNetContract.SendDebugMapUpdate then
        NPCNetContract.SendDebugMapUpdate(marker)
    else
        sendServerCommand('NPCDebugMap', 'Update', marker)
    end
end

local function bcs_removeMarker(gmd, markerId)
    if not gmd or not markerId then return end
    if gmd.DebugMapMarkers then gmd.DebugMapMarkers[tostring(markerId)] = nil end
    if NPCNetContract and NPCNetContract.SendDebugMapRemove then
        NPCNetContract.SendDebugMapRemove(tostring(markerId))
    else
        sendServerCommand('NPCDebugMap', 'Remove', {id=tostring(markerId)})
    end
end

local function bcs_sendActive(player, contract)
    if not player then return end
    if contract and contract.status == "active" then
        sendServerCommand(player, 'NPCContracts', 'Active', contract)
    else
        sendServerCommand(player, 'NPCContracts', 'Clear', {})
    end
end

local function bcs_num(name, defaultValue, minValue, maxValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        local ok, value = pcall(function() return NPCLegacySettingsBridge.GetNumber(name, defaultValue, minValue, maxValue) end)
        if ok and value ~= nil then return tonumber(value) or defaultValue end
    end
    return tonumber(defaultValue) or 0
end

local function bcs_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        local ok, value = pcall(function() return NPCLegacySettingsBridge.GetBool(name, defaultValue == true) end)
        if ok and value ~= nil then return value == true end
    end
    return defaultValue == true
end

local function bcs_dist(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return math.sqrt(dx * dx + dy * dy)
end

local function bcs_players()
    local out = {}
    if getOnlinePlayers then
        local ok, list = pcall(function() return getOnlinePlayers() end)
        if ok and list and list.size and list.get then
            for i = 0, list:size() - 1 do
                local okPlayer, player = pcall(function() return list:get(i) end)
                if okPlayer and player then out[#out + 1] = player end
            end
        end
    end
    if #out == 0 and getPlayer then
        local ok, player = pcall(function() return getPlayer() end)
        if ok and player then out[#out + 1] = player end
    end
    return out
end

local function bcs_worldDirector()
    local director = NPCWorldDirectorServer or NPCWorldDirector
    if type(director) == "table" and director.EnsureData then return director end
    return nil
end

local function bcs_findSquareNear(x, y, z, radius)
    if not getCell then return nil end
    local cell = getCell()
    if not cell or not cell.getGridSquare then return nil end
    x = math.floor(tonumber(x) or 0)
    y = math.floor(tonumber(y) or 0)
    z = tonumber(z) or 0
    radius = math.max(0, math.floor(tonumber(radius) or 0))
    for r = 0, radius do
        for dx = -r, r do
            for dy = -r, r do
                if math.abs(dx) == r or math.abs(dy) == r then
                    local ok, square = pcall(function() return cell:getGridSquare(x + dx, y + dy, z) end)
                    if ok and square then return square, x + dx, y + dy, z end
                end
            end
        end
    end
    return nil
end

local function bcs_inventoryItem(fullType)
    if not InventoryItemFactory then return nil end
    local ok, item = pcall(function() return InventoryItemFactory.CreateItem(fullType) end)
    if ok and item then return item end
    return nil
end

local function bcs_markObjectiveItem(item, contract)
    if not (item and item.getModData and contract) then return end
    local ok, md = pcall(function() return item:getModData() end)
    if ok and type(md) == "table" then
        md.contractObjective = true
        md.contractObjectiveId = contract.id
        md.contractType = contract.type
        md.contractSide = contract.side
        md.contractTargetSide = contract.targetSide
        md.contractObjectiveKind = contract.objectiveKind or "intel_package"
    end
end

local function bcs_markIntelDossier(item, contract)
    if not (item and item.getModData and contract) then return end
    local ok, md = pcall(function() return item:getModData() end)
    if ok and type(md) == "table" then
        md.FactionsConfrontationIntelDossier = true
        md.fcIntelKind = tostring(contract.targetSide or "encrypted")
        md.fcIntelSide = tostring(contract.targetSide or "")
        md.fcIntelSource = "contract_objective"
        md.fcIntelSourceId = tostring(contract.id or "")
        md.fcIntelCreatedAt = NPCContractsBridge.NowHours and NPCContractsBridge.NowHours() or 0
        md.fcIntelSellable = true
    end
end

local function bcs_placeObjectivePackage(gmd, contract)
    if not (gmd and contract and contract.type == "recover") then return false end
    if contract.physicalObjectivePlaced == true then return false end
    if not bcs_bool("Contract_PhysicalObjectivesEnabled", true) then return false end
    local square = bcs_findSquareNear(contract.x, contract.y, contract.z or 0, bcs_num("Contract_PhysicalObjectiveSearchRadius", 10, 0, 40))
    if not square or not square.AddWorldInventoryItem then return false end
    local container = bcs_inventoryItem("Base.Plasticbag") or bcs_inventoryItem("Base.Handbag") or bcs_inventoryItem("Base.Bag_Schoolbag")
    if not container then return false end
    bcs_markObjectiveItem(container, contract)
    local inv = nil
    if container.getInventory then
        local okInv, gotInv = pcall(function() return container:getInventory() end)
        if okInv then inv = gotInv end
    end
    if inv and inv.AddItem then
        local okDossier, dossier = pcall(function() return inv:AddItem("Base.SheetPaper2") end)
        if okDossier and dossier then bcs_markIntelDossier(dossier, contract) end
        pcall(function() inv:AddItem("Base.SheetPaper2") end)
    end
    local ox = 0.25 + ((ZombRand and ZombRand(45) or 15) / 100.0)
    local oy = 0.25 + ((ZombRand and ZombRand(45) or 15) / 100.0)
    local okWorld = pcall(function() square:AddWorldInventoryItem(container, ox, oy, 0) end)
    if not okWorld then return false end
    contract.physicalObjectivePlaced = true
    contract.physicalObjectiveState = "placed"
    contract.physicalObjectivePlacedAt = NPCContractsBridge.NowHours and NPCContractsBridge.NowHours() or 0
    return true
end

local function bcs_contractGuardWave(contract, count)
    count = math.max(1, tonumber(count) or 2)
    return {
        enabled = true,
        enemyBehaviour = 2,
        firstDay = 0,
        lastDay = 99999,
        groupSize = count,
        clanId = 13,
        hasPistolChance = 55,
        pistolMagCount = 2,
        hasRifleChance = 25,
        rifleMagCount = 1
    }
end


local function bcs_groupExists(gmd, groupId)
    return groupId ~= nil and gmd and type(gmd.VirtualGroups) == "table" and gmd.VirtualGroups[tostring(groupId)] ~= nil
end

local function bcs_reconcilePhysicalGuardState(gmd, contract)
    if type(contract) ~= "table" then return false end
    local groupId = contract.physicalGuardGroupId
    if groupId and not bcs_groupExists(gmd, groupId) then
        contract.physicalGuardGroupId = nil
        contract.physicalGuardState = "virtual"
        contract.physicalGuardReconciledAt = NPCContractsBridge.NowHours and NPCContractsBridge.NowHours() or 0
        return true
    end
    if (contract.physicalGuardState == "materialized" or contract.physicalGuardState == "materializing") and not groupId then
        contract.physicalGuardState = "virtual"
        contract.physicalGuardReconciledAt = NPCContractsBridge.NowHours and NPCContractsBridge.NowHours() or 0
        return true
    end
    return false
end

local function bcs_applyContractGuardFields(member, group, contract, index)
    if type(member) ~= "table" then return member end
    member.contractObjectiveGuard = true
    member.contractId = tostring(contract.id or "")
    member.displayTitle = index == 1 and "Contract Guard" or "Objective Guard"
    member.nameplateTitle = member.displayTitle
    member.unitLevel = index == 1 and 5 or 4
    member.unitStars = index == 1 and 2 or 1
    member.eliteUnit = false
    member.role = "contract_guard"
    member.tacticalRole = "guard"
    member.program = {name="Raider", stage="Prepare"}
    member.order = {name="Guard", source="contract_physical", fireMode="FireAtWill", priority=70, sticky=false, anchor={x=contract.x, y=contract.y, z=contract.z or 0}, note="Guard contract objective"}
    member.factionSide = group.side
    member.faction = group.side
    member.side = group.side
    member.patrolColor = group.side
    member.preferCover = true
    member.preferRoads = false
    return member
end

local function bcs_spawnContractGuardGroup(gmd, contract, player)
    if not (gmd and contract and player and contract.type == "recover") then return false end
    bcs_reconcilePhysicalGuardState(gmd, contract)
    if bcs_groupExists(gmd, contract.physicalGuardGroupId) then return false end
    if contract.physicalGuardState == "materialized" then return false end
    if not bcs_bool("Contract_PhysicalGuardsEnabled", true) then return false end
    local director = bcs_worldDirector()
    if not director then return false end
    if not (NPCWorldDirectorBridge and NPCWorldDirectorBridge.PrepareVirtualMember) then return false end
    local minCount = math.floor(bcs_num("Contract_PhysicalGuardMin", 1, 0, 8))
    local maxCount = math.floor(bcs_num("Contract_PhysicalGuardMax", 3, minCount, 10))
    if maxCount <= 0 then return false end
    local span = math.max(0, maxCount - minCount)
    local count = minCount + (span > 0 and (ZombRand and ZombRand(span + 1) or 0) or 0)
    if count <= 0 then return false end
    if NPCWorldDirectorBridge.ClampGroupSize then count = NPCWorldDirectorBridge.ClampGroupSize(count, 1, 8) end
    local groupId = "COG" .. tostring(contract.id or tostring(ZombRand and ZombRand(999999) or os.time()))
    local side = contract.targetSide or "red"
    local wave = bcs_contractGuardWave(contract, count)
    local group = {
        id = groupId,
        x = math.floor(tonumber(contract.x) or 0),
        y = math.floor(tonumber(contract.y) or 0),
        z = tonumber(contract.z) or 0,
        preciseX = tonumber(contract.x) or 0,
        preciseY = tonumber(contract.y) or 0,
        clanId = wave.clanId,
        count = count,
        hostile = true,
        program = {name="Raider", stage="Prepare"},
        members = {},
        virtual = true,
        activated = false,
        createdAt = NPCContractsBridge.NowHours and NPCContractsBridge.NowHours() or 0,
        updatedAt = NPCContractsBridge.NowHours and NPCContractsBridge.NowHours() or 0,
        state = "contract_objective_guard",
        spawnClass = "contract_guard",
        targetX = contract.x,
        targetY = contract.y,
        targetZ = contract.z or 0,
        targetClass = "contract_objective",
        speed = 0,
        patrolColor = side,
        factionSide = side,
        faction = side,
        side = side,
        contractObjectiveGuardGroup = true,
        contractId = tostring(contract.id or ""),
        displayTitle = "Contract Guards",
        name = "Contract objective guards"
    }
    for i = 1, count do
        local member = nil
        local okMember, gotMember = pcall(function()
            return NPCWorldDirectorBridge.PrepareVirtualMember(director, gmd, wave, groupId, i, side, false)
        end)
        if okMember then member = gotMember end
        if type(member) ~= "table" then member = {} end
        if NPCIdentityBridge and NPCIdentityBridge.NewUID then
            member.uid = member.uid or NPCIdentityBridge.NewUID(gmd)
            member.persistentId = member.persistentId or member.uid
        end
        member.worldGroupId = groupId
        member.groupId = groupId
        member.memberIndex = i
        bcs_applyContractGuardFields(member, group, contract, i)
        group.members[#group.members + 1] = member
    end
    group.count = #group.members
    if group.count <= 0 then return false end
    gmd.VirtualGroups = gmd.VirtualGroups or {}
    gmd.VirtualGroups[groupId] = group
    contract.physicalGuardGroupId = groupId
    contract.physicalGuardState = "materializing"
    if NPCPersistentNPCBridge and NPCPersistentNPCBridge.RegisterGroup then pcall(function() NPCPersistentNPCBridge.RegisterGroup(gmd, group) end) end
    local ok = false
    if director.MaterializeGroup then
        ok = pcall(function() return director.MaterializeGroup(group, player) end)
    elseif NPCWorldDirectorBridge.MaterializeGroup then
        ok = pcall(function() return NPCWorldDirectorBridge.MaterializeGroup(director, group, player) end)
    end
    if ok then
        contract.physicalGuardState = "materialized"
        contract.physicalGuardMaterializedAt = NPCContractsBridge.NowHours and NPCContractsBridge.NowHours() or 0
        if NPCDiagnosticsBridge and NPCDiagnosticsBridge.LogRiskAction then
            NPCDiagnosticsBridge.LogRiskAction("contracts", "guards_materialized", {contractId=contract.id, groupId=groupId, type=contract.type, x=contract.targetX, y=contract.targetY, guards=group.count}, "contract-guards:" .. tostring(contract.id), true)
        end
        bcs_halo(player, "Contract objective contact: guards spotted nearby.", 255, 180, 90)
        return true
    end
    contract.physicalGuardState = "virtual"
    return false
end

local function bcs_materializeNearbyContracts(gmd)
    if not (gmd and NPCContractsBridge and NPCContractsBridge.IsEnabled and NPCContractsBridge.IsEnabled()) then return 0 end
    if not bcs_bool("Contract_PhysicalObjectivesEnabled", true) then return 0 end
    NPCContractsBridge.EnsureData(gmd)
    local radius = bcs_num("Contract_PhysicalSpawnDistance", 90, 20, 240)
    local maxPerTick = math.floor(bcs_num("Contract_PhysicalMaxMaterializePerTick", 1, 0, 8))
    if maxPerTick <= 0 then return 0 end
    local made = 0
    local reconciled = 0
    for _, contract in pairs(gmd.PlayerContracts or {}) do
        if type(contract) == "table" and bcs_reconcilePhysicalGuardState(gmd, contract) then reconciled = reconciled + 1 end
        if made >= maxPerTick then break end
        if type(contract) == "table" and contract.status == "active" and contract.type == "recover" then
            for _, player in ipairs(bcs_players()) do
                if player and player.getX and player.getY and bcs_dist(player:getX(), player:getY(), contract.x, contract.y) <= radius then
                    local changed = false
                    if bcs_placeObjectivePackage(gmd, contract) then changed = true end
                    if bcs_spawnContractGuardGroup(gmd, contract, player) then changed = true end
                    if changed then made = made + 1 end
                    break
                end
            end
        end
    end
    return made + reconciled
end

local function bcs_sync(player)
    if not (NPCContractsBridge and NPCContractsBridge.IsEnabled and NPCContractsBridge.IsEnabled()) then return end
    local gmd = GetNPCModData()
    bcs_ensure(gmd)
    local contract = NPCContractsBridge.GetActive(gmd, player)
    bcs_sendActive(player, contract)
end

local function bcs_request(player, args)
    if not (NPCContractsBridge and NPCContractsBridge.IsEnabled and NPCContractsBridge.IsEnabled()) then return end
    if type(args) ~= "table" then return end

    local gmd = GetNPCModData()
    bcs_ensure(gmd)

    local active = NPCContractsBridge.GetActive(gmd, player)
    if active then
        if NPCContractsBridge.IsExpired(active) then
            NPCContractsBridge.Fail(gmd, active, "expired")
            bcs_removeMarker(gmd, active.markerId)
            bcs_sendActive(player, nil)
        else
            bcs_sendActive(player, active)
            bcs_halo(player, "Contract already active: " .. tostring(active.text or active.title), 255, 220, 120)
            return
        end
    end

    local base = NPCContractsBridge.FindBaseById(gmd, args.baseId)
    if not base then
        bcs_halo(player, "No contract base found nearby.", 255, 120, 80)
        return
    end
    if not NPCContractsBridge.CanUseBase(base, player) then
        bcs_halo(player, "This base will not work with you.", 255, 120, 80)
        return
    end

    local contract, err = NPCContractsBridge.CreateContract(gmd, player, base, args.contractType)
    if not contract then
        bcs_halo(player, "No contract available: " .. tostring(err or "none"), 255, 120, 80)
        return
    end

    local marker = NPCContractsBridge.MakeMarker(contract)
    if marker then bcs_setMarker(gmd, marker) end
    bcs_sendActive(player, contract)
    bcs_halo(player, tostring(contract.text or "Faction contract accepted."), 140, 240, 160)
    bcs_say(player, tostring(contract.text or "Faction contract accepted."))
    TransmitNPCModData()
end

local function bcs_complete(player, args)
    if not (NPCContractsBridge and NPCContractsBridge.IsEnabled and NPCContractsBridge.IsEnabled()) then return end

    local gmd = GetNPCModData()
    bcs_ensure(gmd)

    local contract, err = NPCContractsBridge.TryCompleteActive(gmd, player)
    if not contract then
        bcs_halo(player, "No active contract.", 255, 120, 80)
        bcs_sendActive(player, nil)
        return
    end

    if err then
        if err == "too_far" then
            if contract and contract.type == "recover" then
                bcs_halo(player, "Move closer to the physical contract objective.", 255, 180, 80)
            else
                bcs_halo(player, "Recon target is still too far away.", 255, 180, 80)
            end
        elseif err == "supply_incomplete" then
            bcs_halo(player, "Supply contract is not complete yet.", 255, 180, 80)
        elseif err == "expired" then
            bcs_removeMarker(gmd, contract.markerId)
            bcs_halo(player, "Contract expired.", 255, 120, 80)
            bcs_sendActive(player, nil)
        else
            bcs_halo(player, "Contract cannot be completed: " .. tostring(err), 255, 120, 80)
        end
        return
    end

    bcs_removeMarker(gmd, contract.markerId)
    bcs_sendActive(player, nil)
    local completeText = contract.completedBySpyIntel and "Recon complete by spy intel. Favor gained with " or "Contract complete. Favor gained with "
    if contract.type == "recover" then completeText = "Contract package recovered. Favor gained with " end
    bcs_halo(player, completeText .. tostring(contract.side or "faction") .. ".", 120, 255, 120)
    local factionDocsServer = NPCFactionDocsServer or (NPCLegacyGlobalsBridge and NPCLegacyGlobalsBridge.Get and NPCLegacyGlobalsBridge.Get("FactionDocsServer"))
    if factionDocsServer and factionDocsServer.GrantIntelReward then
        factionDocsServer.GrantIntelReward(player, contract.side, "contract")
    end
    bcs_say(player, "Contract complete.")
    TransmitNPCModData()
end

local function bcs_abandon(player, args)
    if not (NPCContractsBridge and NPCContractsBridge.IsEnabled and NPCContractsBridge.IsEnabled()) then return end
    local gmd = GetNPCModData()
    bcs_ensure(gmd)

    local contract = NPCContractsBridge.GetActive(gmd, player)
    if not contract then
        bcs_sendActive(player, nil)
        bcs_halo(player, "No active contract.", 255, 180, 80)
        return
    end

    NPCContractsBridge.Fail(gmd, contract, "abandoned")
    bcs_removeMarker(gmd, contract.markerId)
    bcs_sendActive(player, nil)
    bcs_halo(player, "Contract abandoned.", 255, 180, 80)
    TransmitNPCModData()
end

function NPCContractsServerBridge.OnClientCommand(module, command, player, args)
    if not NPCLegacyContractBridge.IsModule(module, "NPCContracts", "contracts") then return end
    if command == "RequestSync" then
        bcs_sync(player)
    elseif command == "RequestContract" then
        bcs_request(player, args)
    elseif command == "CompleteContract" then
        bcs_complete(player, args)
    elseif command == "AbandonContract" then
        bcs_abandon(player, args)
    end
end

function NPCContractsServerBridge.OnSupplyDonation(player, base, counts)
    if not (NPCContractsBridge and NPCContractsBridge.IsEnabled and NPCContractsBridge.IsEnabled()) then return nil end
    local gmd = GetNPCModData()
    bcs_ensure(gmd)

    local result = NPCContractsBridge.ApplySupplyDonation(gmd, player, base, counts)
    if not result or not result.contract then return nil end

    local contract = result.contract
    if result.status == "completed" then
        bcs_removeMarker(gmd, contract.markerId)
        bcs_sendActive(player, nil)
        bcs_halo(player, "Supply contract complete. Favor gained with " .. tostring(contract.side or "faction") .. ".", 120, 255, 120)
        local factionDocsServer = NPCFactionDocsServer or (NPCLegacyGlobalsBridge and NPCLegacyGlobalsBridge.Get and NPCLegacyGlobalsBridge.Get("FactionDocsServer"))
        if factionDocsServer and factionDocsServer.GrantIntelReward then
            factionDocsServer.GrantIntelReward(player, contract.side, "contract")
        end
        bcs_say(player, "Supply contract complete.")
    elseif result.status == "progress" then
        local marker = NPCContractsBridge.MakeMarker(contract)
        if marker then bcs_setMarker(gmd, marker) end
        bcs_sendActive(player, contract)
        bcs_halo(player, "Contract progress: " .. tostring(contract.deliveredAmount) .. "/" .. tostring(contract.requiredAmount) .. " " .. tostring(contract.resourceLabel or contract.resource) .. ".", 170, 230, 255)
    elseif result.status == "expired" then
        bcs_removeMarker(gmd, contract.markerId)
        bcs_sendActive(player, nil)
        bcs_halo(player, "Contract expired.", 255, 120, 80)
    end

    TransmitNPCModData()
    return result
end

local function bcs_everyTenMinutes()
    if not (NPCContractsBridge and NPCContractsBridge.IsEnabled and NPCContractsBridge.IsEnabled()) then return end
    local gmd = GetNPCModData()
    bcs_ensure(gmd)
    local changed = bcs_materializeNearbyContracts(gmd)
    if changed and changed > 0 then TransmitNPCModData() end
end

function NPCContractsServerBridge.Install()
    if NPCContractsServerBridge._installed then return end
    Events.OnClientCommand.Add(NPCContractsServerBridge.OnClientCommand)
    Events.EveryTenMinutes.Add(bcs_everyTenMinutes)
    NPCContractsServerBridge._installed = true
end

NPCContractsServerBridge.Install()
