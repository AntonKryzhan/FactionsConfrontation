-- NPCContractsBridge.lua
-- Neutral shared backend for player-facing faction contracts: base supply delivery and recon objectives.
-- Designed as a lightweight interactive layer over existing bases, map markers and base supply donations.

require "NPCCore/NPCLegacyGlobalsBridge"

NPCContractsBridge = NPCContractsBridge or {}

local BC_RESOURCES = {"food", "medical", "ammo", "fuel", "materials", "weapons", "armor", "magazines"}
local function bc_spyProvider()
    return NPCSpyBridge or NPCLegacyGlobalsBridge.Get("Spy") or nil
end

local BC_RESOURCE_LABEL = {
    food = "Food",
    medical = "Medical",
    ammo = "Ammo",
    fuel = "Fuel",
    materials = "Materials",
    weapons = "Weapons",
    armor = "Armor",
    magazines = "Magazines"
}

local BC_BASE_TYPE_RESOURCE = {
    hospital = "medical",
    clinic = "medical",
    shop = "food",
    grocery = "food",
    police = "ammo",
    fire = "fuel",
    warehouse = "materials",
    school = "food",
    office = "materials"
}

local function bc_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        local ok, value = pcall(function() return NPCLegacySettingsBridge.GetBool(name, defaultValue == true) end)
        if ok and value ~= nil then return value == true end
    end
    return defaultValue == true
end

local function bc_num(name, defaultValue, minValue, maxValue)
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

local function bc_now()
    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then
            local ok, value = pcall(function() return gt:getWorldAgeHours() end)
            if ok and value then return tonumber(value) or 0 end
        end
    end
    return os.time and (os.time() / 3600) or 0
end

local function bc_playerId(player)
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

local function bc_playerName(player)
    if not player then return "player" end
    if player.getUsername then
        local ok, name = pcall(function() return player:getUsername() end)
        if ok and name then return tostring(name) end
    end
    if player.getFullName then
        local ok, name = pcall(function() return player:getFullName() end)
        if ok and name then return tostring(name) end
    end
    return "player"
end

local function bc_side(value)
    if NPCFactionBridge and NPCFactionBridge.NormalizeSide then
        local side = NPCFactionBridge.NormalizeSide(value)
        if side then return side end
    end
    value = tostring(value or ""):lower()
    if value == "friendly" then return "green" end
    if value == "hostile" then return "red" end
    if value == "red" or value == "green" or value == "blue" or value == "black" then return value end
    return nil
end

local function bc_playerSide(player)
    if NPCFactionBridge and NPCFactionBridge.GetPlayerSide then
        local ok, side = pcall(function() return NPCFactionBridge.GetPlayerSide(player) end)
        if ok and side then return bc_side(side) or "blue" end
    end
    return "blue"
end

local function bc_baseSide(base)
    if not base then return nil end
    return bc_side(base.owner or base.captureTeam or base.factionSide or base.faction or base.side)
end

local function bc_groupSide(group)
    if not group then return nil end
    return bc_side(group.factionSide or group.faction or group.side or group.patrolColor)
end

local function bc_sideLabel(side)
    if NPCFactionBridge and NPCFactionBridge.GetSideLabel then
        local ok, label = pcall(function() return NPCFactionBridge.GetSideLabel(side) end)
        if ok and label then return tostring(label) end
    end
    return tostring(side or "unknown")
end

local function bc_dist(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return math.sqrt(dx * dx + dy * dy)
end

local function bc_same(a, b)
    if a == nil or b == nil then return false end
    return tostring(a) == tostring(b)
end

local function bc_baseName(base)
    return tostring(base and (base.name or base.title or base.baseName or ("Base " .. tostring(base.id or "?"))) or "base")
end

local function bc_resourceValue(base, resource)
    if not base or not resource then return 0 end
    if type(base.stock) == "table" and base.stock[resource] ~= nil then return tonumber(base.stock[resource]) or 0 end
    if type(base.donatedStock) == "table" and base.donatedStock[resource] ~= nil then return tonumber(base.donatedStock[resource]) or 0 end

    local suffix = string.upper(string.sub(resource, 1, 1)) .. string.sub(resource, 2)
    local stockKey = "stock" .. suffix
    local donatedKey = "donated" .. suffix
    return tonumber(base[stockKey] or base[donatedKey]) or 0
end

local function bc_pickSupplyResource(base)
    local preferred = BC_BASE_TYPE_RESOURCE[tostring(base and (base.baseType or base.type or base.kind) or "")]
    if preferred and bc_resourceValue(base, preferred) < bc_num("Contract_PreferredResourceSoftCap", 18, 0, 10000) then
        return preferred
    end

    local best = nil
    local bestScore = 999999
    for _, resource in ipairs(BC_RESOURCES) do
        local score = bc_resourceValue(base, resource)
        if score < bestScore then
            bestScore = score
            best = resource
        end
    end
    return best or "food"
end

local function bc_addReconCandidate(candidates, kind, name, x, y, z, side, sourceId)
    x = tonumber(x)
    y = tonumber(y)
    if not x or not y then return end
    candidates[#candidates + 1] = {
        kind = kind,
        name = tostring(name or kind),
        x = x,
        y = y,
        z = tonumber(z) or 0,
        side = bc_side(side),
        sourceId = sourceId
    }
end

local function bc_collectReconCandidates(gmd, player, base)
    local out = {}
    if not gmd then return out end

    local playerSide = bc_playerSide(player)
    local baseX = base and base.x or (player and player.getX and player:getX()) or 0
    local baseY = base and base.y or (player and player.getY and player:getY()) or 0
    local searchRadius = bc_num("Contract_ReconSearchRadius", 2600, 200, 10000)

    if type(gmd.BaseCamps) == "table" then
        for _, target in pairs(gmd.BaseCamps) do
            if target and target.x and target.y and not bc_same(target.id, base and base.id) then
                local side = bc_baseSide(target)
                local enemy = side and side ~= playerSide
                if NPCFactionBridge and NPCFactionBridge.IsEnemySide and side and playerSide then
                    enemy = NPCFactionBridge.IsEnemySide(playerSide, side)
                end
                if enemy and bc_dist(baseX, baseY, target.x, target.y) <= searchRadius then
                    bc_addReconCandidate(out, "base", bc_baseName(target), target.x, target.y, target.z, side, target.id)
                end
            end
        end
    end

    if type(gmd.VirtualGroups) == "table" then
        for gid, group in pairs(gmd.VirtualGroups) do
            if group and group.x and group.y and (tonumber(group.count) or 0) > 0 then
                local side = bc_groupSide(group)
                local enemy = side and side ~= playerSide
                if NPCFactionBridge and NPCFactionBridge.IsEnemySide and side and playerSide then
                    enemy = NPCFactionBridge.IsEnemySide(playerSide, side)
                end
                if enemy and bc_dist(baseX, baseY, group.x, group.y) <= searchRadius then
                    bc_addReconCandidate(out, "patrol", group.name or ("Enemy patrol " .. tostring(gid)), group.x, group.y, group.z, side, gid)
                end
            end
        end
    end

    if type(gmd.DebugMapMarkers) == "table" then
        for mid, marker in pairs(gmd.DebugMapMarkers) do
            if marker and marker.x and marker.y and (marker.markerType == "group" or marker.markerType == "base" or marker.markerType == "economy_mission") then
                local side = bc_side(marker.factionSide or marker.faction or marker.side or marker.owner)
                local enemy = side and side ~= playerSide
                if NPCFactionBridge and NPCFactionBridge.IsEnemySide and side and playerSide then
                    enemy = NPCFactionBridge.IsEnemySide(playerSide, side)
                end
                if enemy and bc_dist(baseX, baseY, marker.x, marker.y) <= searchRadius then
                    bc_addReconCandidate(out, marker.markerType == "base" and "base" or "patrol", marker.name or tostring(marker.markerType), marker.x, marker.y, marker.z, side, mid)
                end
            end
        end
    end

    table.sort(out, function(a, b)
        return bc_dist(baseX, baseY, a.x, a.y) < bc_dist(baseX, baseY, b.x, b.y)
    end)

    return out
end

local function bc_pickCandidate(candidates)
    if not candidates or #candidates <= 0 then return nil end
    local maxPick = math.min(#candidates, 5)
    local index = 1
    if ZombRand then index = 1 + ZombRand(maxPick) end
    return candidates[index]
end

local function bc_nextId(gmd)
    NPCContractsBridge.EnsureData(gmd)
    local data = gmd.ContractStats
    local nextId = tonumber(data.nextId) or 1
    data.nextId = nextId + 1
    return nextId
end

function NPCContractsBridge.IsEnabled()
    return bc_bool("Contract_Enabled", true)
end

function NPCContractsBridge.ContractsEnabled()
    return NPCContractsBridge.IsEnabled()
end

function NPCContractsBridge.ResourceLabel(resource)
    return BC_RESOURCE_LABEL[resource] or tostring(resource or "resource")
end

function NPCContractsBridge.NowHours()
    return bc_now()
end

function NPCContractsBridge.PlayerId(player)
    return bc_playerId(player)
end

function NPCContractsBridge.EnsureData(gmd)
    if not gmd then return end
    if type(gmd.PlayerContracts) ~= "table" then gmd.PlayerContracts = {} end
    if type(gmd.ContractStats) ~= "table" then gmd.ContractStats = {nextId=1, completed=0, failed=0, abandoned=0} end
    if type(gmd.ContractReputation) ~= "table" then gmd.ContractReputation = {} end
end

function NPCContractsBridge.FindBaseById(gmd, baseId)
    if not gmd or not baseId then return nil end
    local id = tostring(baseId)
    if type(gmd.BaseCamps) == "table" then
        for _, base in pairs(gmd.BaseCamps) do
            if type(base) == "table" and (bc_same(base.id, id) or bc_same(base.baseId, id) or bc_same("BASE_" .. tostring(base.id), id)) then
                return base
            end
        end
    end
    return nil
end

function NPCContractsBridge.CanUseBase(base, player)
    if not NPCContractsBridge.IsEnabled() then return false end
    if not base or not base.x or not base.y then return false end
    local owner = bc_baseSide(base)
    if owner == "black" then return false end
    if not owner then return true end

    local playerSide = bc_playerSide(player)
    if playerSide == "black" then return false end
    if NPCFactionBridge and NPCFactionBridge.IsEnemySide and playerSide then
        return not NPCFactionBridge.IsEnemySide(playerSide, owner)
    end
    return playerSide == "blue" or playerSide == owner
end

function NPCContractsBridge.GetActive(gmd, player)
    NPCContractsBridge.EnsureData(gmd)
    local pid = bc_playerId(player)
    if not pid then return nil end
    local contract = gmd.PlayerContracts[tostring(pid)] or gmd.PlayerContracts[pid]
    if contract and contract.status == "active" then return contract end
    return nil
end

function NPCContractsBridge.IsExpired(contract)
    return contract and contract.expiresAt and bc_now() >= tonumber(contract.expiresAt)
end

function NPCContractsBridge.BuildSupplyContract(gmd, player, base)
    if not gmd or not player or not base then return nil end
    local id = bc_nextId(gmd)
    local pid = bc_playerId(player)
    local resource = bc_pickSupplyResource(base)
    local required = math.floor(bc_num("Contract_SupplyRequiredAmount", 5, 1, 200))
    local baseSide = bc_baseSide(base) or bc_playerSide(player)
    local title = "Supply: " .. NPCContractsBridge.ResourceLabel(resource)
    local contract = {
        id = "CONTRACT_" .. tostring(id),
        markerId = "CONTRACT_MARKER_" .. tostring(id),
        type = "supply",
        status = "active",
        playerId = pid,
        playerName = bc_playerName(player),
        side = baseSide,
        baseId = tostring(base.id or base.baseId),
        baseName = bc_baseName(base),
        baseX = math.floor(tonumber(base.x) or 0),
        baseY = math.floor(tonumber(base.y) or 0),
        baseZ = tonumber(base.z) or 0,
        x = math.floor(tonumber(base.x) or 0),
        y = math.floor(tonumber(base.y) or 0),
        z = tonumber(base.z) or 0,
        resource = resource,
        resourceLabel = NPCContractsBridge.ResourceLabel(resource),
        requiredAmount = required,
        deliveredAmount = 0,
        rewardFavor = math.floor(bc_num("Contract_RewardFavor", 3, 0, 1000)),
        createdAt = bc_now(),
        expiresAt = bc_now() + bc_num("Contract_ExpireHours", 24, 1, 240),
        title = title,
        text = "Deliver " .. tostring(required) .. " " .. NPCContractsBridge.ResourceLabel(resource) .. " to " .. bc_baseName(base) .. "."
    }
    return contract
end

function NPCContractsBridge.BuildReconContract(gmd, player, base)
    if not gmd or not player or not base then return nil end
    local candidates = bc_collectReconCandidates(gmd, player, base)
    local target = bc_pickCandidate(candidates)
    if not target then return nil end

    local id = bc_nextId(gmd)
    local pid = bc_playerId(player)
    local radius = bc_num("Contract_ReconCompleteRadius", 28, 5, 200)
    local title = "Recon: " .. tostring(target.kind)
    local contract = {
        id = "CONTRACT_" .. tostring(id),
        markerId = "CONTRACT_MARKER_" .. tostring(id),
        type = "recon",
        status = "active",
        playerId = pid,
        playerName = bc_playerName(player),
        side = bc_baseSide(base) or bc_playerSide(player),
        baseId = tostring(base.id or base.baseId),
        baseName = bc_baseName(base),
        baseX = math.floor(tonumber(base.x) or 0),
        baseY = math.floor(tonumber(base.y) or 0),
        baseZ = tonumber(base.z) or 0,
        x = math.floor(tonumber(target.x) or 0),
        y = math.floor(tonumber(target.y) or 0),
        z = tonumber(target.z) or 0,
        targetKind = target.kind,
        targetName = target.name,
        targetSide = target.side,
        targetSourceId = target.sourceId,
        completeRadius = radius,
        rewardFavor = math.floor(bc_num("Contract_RewardFavor", 3, 0, 1000)),
        createdAt = bc_now(),
        expiresAt = bc_now() + bc_num("Contract_ExpireHours", 24, 1, 240),
        title = title,
        text = "Scout suspected " .. tostring(target.kind) .. " of " .. bc_sideLabel(target.side) .. " near " .. tostring(math.floor(target.x)) .. ", " .. tostring(math.floor(target.y)) .. "."
    }
    return contract
end

function NPCContractsBridge.CreateContract(gmd, player, base, preferredType)
    if not NPCContractsBridge.CanUseBase(base, player) then return nil, "base_unavailable" end

    local contract = nil
    preferredType = tostring(preferredType or "auto")

    if preferredType == "supply" then
        contract = NPCContractsBridge.BuildSupplyContract(gmd, player, base)
    elseif preferredType == "recon" then
        contract = NPCContractsBridge.BuildReconContract(gmd, player, base)
    else
        local supplyChance = bc_num("Contract_SupplyChance", 60, 0, 100)
        if (not ZombRand) or ZombRand(100) < supplyChance then
            contract = NPCContractsBridge.BuildSupplyContract(gmd, player, base)
        end
        if not contract then contract = NPCContractsBridge.BuildReconContract(gmd, player, base) end
        if not contract then contract = NPCContractsBridge.BuildSupplyContract(gmd, player, base) end
    end

    if not contract then return nil, "no_contract" end

    NPCContractsBridge.EnsureData(gmd)
    gmd.PlayerContracts[tostring(contract.playerId)] = contract
    return contract, nil
end

function NPCContractsBridge.MakeMarker(contract)
    if not contract or not contract.markerId then return nil end
    return {
        id = contract.markerId,
        markerType = "contract",
        contractId = contract.id,
        contractType = contract.type,
        contractStatus = contract.status,
        x = contract.x,
        y = contract.y,
        z = contract.z or 0,
        name = contract.title or "Faction contract",
        side = contract.side,
        factionSide = contract.side,
        faction = contract.side,
        owner = contract.side,
        resource = contract.resource,
        resourceLabel = contract.resourceLabel,
        requiredAmount = contract.requiredAmount,
        deliveredAmount = contract.deliveredAmount,
        targetKind = contract.targetKind,
        targetSide = contract.targetSide,
        completeRadius = contract.completeRadius,
        friendly = true,
        hostile = false,
        updatedAt = bc_now()
    }
end

function NPCContractsBridge.AddReputation(gmd, contract)
    if not gmd or not contract or not contract.playerId then return 0 end
    NPCContractsBridge.EnsureData(gmd)
    local pid = tostring(contract.playerId)
    local side = tostring(contract.side or "neutral")
    gmd.ContractReputation[pid] = gmd.ContractReputation[pid] or {}
    local current = tonumber(gmd.ContractReputation[pid][side]) or 0
    local gain = tonumber(contract.rewardFavor) or 0
    gmd.ContractReputation[pid][side] = current + gain
    return gain
end

function NPCContractsBridge.Complete(gmd, player, contract, reason)
    if not gmd or not contract then return false, "no_contract" end
    contract.status = "completed"
    contract.completedAt = bc_now()
    contract.completedReason = reason or contract.type
    NPCContractsBridge.AddReputation(gmd, contract)
    NPCContractsBridge.EnsureData(gmd)
    gmd.ContractStats.completed = (tonumber(gmd.ContractStats.completed) or 0) + 1
    if contract.playerId then gmd.PlayerContracts[tostring(contract.playerId)] = contract end
    return true, nil
end

function NPCContractsBridge.Fail(gmd, contract, reason)
    if not gmd or not contract then return false end
    contract.status = reason or "failed"
    contract.completedAt = bc_now()
    NPCContractsBridge.EnsureData(gmd)
    if contract.status == "abandoned" then
        gmd.ContractStats.abandoned = (tonumber(gmd.ContractStats.abandoned) or 0) + 1
    else
        gmd.ContractStats.failed = (tonumber(gmd.ContractStats.failed) or 0) + 1
    end
    if contract.playerId then gmd.PlayerContracts[tostring(contract.playerId)] = contract end
    return true
end

function NPCContractsBridge.ApplySupplyDonation(gmd, player, base, counts)
    local contract = NPCContractsBridge.GetActive(gmd, player)
    if not contract or contract.type ~= "supply" then return nil end
    if NPCContractsBridge.IsExpired(contract) then
        NPCContractsBridge.Fail(gmd, contract, "expired")
        return {status="expired", contract=contract}
    end
    if not bc_same(contract.baseId, base and (base.id or base.baseId)) then return nil end

    local amount = tonumber(counts and counts[contract.resource]) or 0
    if amount <= 0 then return nil end

    contract.deliveredAmount = math.min(tonumber(contract.requiredAmount) or 0, (tonumber(contract.deliveredAmount) or 0) + amount)
    if contract.deliveredAmount >= (tonumber(contract.requiredAmount) or 1) then
        NPCContractsBridge.Complete(gmd, player, contract, "supply")
        return {status="completed", contract=contract, added=amount}
    end
    return {status="progress", contract=contract, added=amount}
end

function NPCContractsBridge.CanCompleteRecon(contract, player)
    if not contract or contract.type ~= "recon" or not player then return false end
    if not player.getX or not player.getY then return false end
    local radius = tonumber(contract.completeRadius) or bc_num("Contract_ReconCompleteRadius", 28, 5, 200)
    return bc_dist(player:getX(), player:getY(), contract.x, contract.y) <= radius
end

function NPCContractsBridge.TryCompleteActive(gmd, player)
    local contract = NPCContractsBridge.GetActive(gmd, player)
    if not contract then return nil, "no_active_contract" end
    if NPCContractsBridge.IsExpired(contract) then
        NPCContractsBridge.Fail(gmd, contract, "expired")
        return contract, "expired"
    end
    if contract.type == "recon" then
        if not NPCContractsBridge.CanCompleteRecon(contract, player) then
            local completedBySpy = false
            local spyProvider = bc_spyProvider()
            if spyProvider and spyProvider.CanCompleteReconFromIntel then
                local ok, value = pcall(function() return spyProvider.CanCompleteReconFromIntel(gmd, player, contract) end)
                completedBySpy = ok and value == true
            end
            if not completedBySpy then return contract, "too_far" end
            contract.completedBySpyIntel = true
        end
        NPCContractsBridge.Complete(gmd, player, contract, contract.completedBySpyIntel and "spy_recon" or "recon")
        return contract, nil
    elseif contract.type == "supply" then
        if (tonumber(contract.deliveredAmount) or 0) >= (tonumber(contract.requiredAmount) or 1) then
            NPCContractsBridge.Complete(gmd, player, contract, "supply")
            return contract, nil
        end
        return contract, "supply_incomplete"
    end
    return contract, "unsupported_type"
end
