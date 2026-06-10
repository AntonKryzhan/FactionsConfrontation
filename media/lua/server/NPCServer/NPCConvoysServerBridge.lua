-- NPCConvoysServerBridge.lua
-- Neutral server command layer and movement ticks for lightweight interactive supply convoys.

if isClient and isClient() then return end

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCConvoysBridge"
require "NPCCore/NPCDiagnosticsBridge"
require "NPCServer/NPCFactionDocsServerBridge"
require "NPCServer/NPCWorldDirector"
require "NPCServer/NPCWorldDirectorBridge"

NPCConvoysServerBridge = NPCConvoysServerBridge or {}

local function bcvs_say(player, text)
    if player and player.Say and text then pcall(function() player:Say(text) end) end
end

local function bcvs_halo(player, text, r, g, b)
    if player and text then
        sendServerCommand(player, 'NPCConvoys', 'Result', {text=text, r=r or 180, g=g or 230, b=b or 255})
    end
end

local function bcvs_ensure(gmd)
    if not gmd then return end
    if not gmd.DebugMapMarkers then gmd.DebugMapMarkers = {} end
    if NPCConvoysBridge and NPCConvoysBridge.EnsureData then NPCConvoysBridge.EnsureData(gmd) end
end

local function bcvs_setMarker(gmd, marker)
    if not gmd or not marker or not marker.id then return end
    if not gmd.DebugMapMarkers then gmd.DebugMapMarkers = {} end
    gmd.DebugMapMarkers[tostring(marker.id)] = marker
    if NPCNetContract and NPCNetContract.SendDebugMapUpdate then
        NPCNetContract.SendDebugMapUpdate(marker)
    else
        sendServerCommand('NPCDebugMap', 'Update', marker)
    end
end

local function bcvs_removeMarker(gmd, markerId)
    if not gmd or not markerId then return end
    if gmd.DebugMapMarkers then gmd.DebugMapMarkers[tostring(markerId)] = nil end
    if NPCNetContract and NPCNetContract.SendDebugMapRemove then
        NPCNetContract.SendDebugMapRemove(tostring(markerId))
    else
        sendServerCommand('NPCDebugMap', 'Remove', {id=tostring(markerId)})
    end
end

local function bcvs_num(name, defaultValue, minValue, maxValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        local ok, value = pcall(function() return NPCLegacySettingsBridge.GetNumber(name, defaultValue, minValue, maxValue) end)
        if ok and value ~= nil then return tonumber(value) or defaultValue end
    end
    return tonumber(defaultValue) or 0
end

local function bcvs_dist(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return math.sqrt(dx * dx + dy * dy)
end

local function bcvs_players()
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

local function bcvs_worldDirector()
    local director = NPCWorldDirectorServer or NPCWorldDirector
    if type(director) == "table" and director.EnsureData then return director end
    return nil
end

local function bcvs_waveForConvoy(convoy, count)
    count = math.max(1, tonumber(count) or 2)
    local hostile = convoy and convoy.objective == "raid"
    return {
        enabled = true,
        enemyBehaviour = hostile and 2 or 7,
        firstDay = 0,
        lastDay = 99999,
        groupSize = count,
        clanId = hostile and 13 or 1,
        hasPistolChance = hostile and 65 or 35,
        pistolMagCount = hostile and 3 or 2,
        hasRifleChance = hostile and 45 or 20,
        rifleMagCount = hostile and 2 or 1
    }
end


local function bcvs_groupExists(gmd, groupId)
    return groupId ~= nil and gmd and type(gmd.VirtualGroups) == "table" and gmd.VirtualGroups[tostring(groupId)] ~= nil
end

local function bcvs_reconcilePhysicalState(gmd, convoy)
    if type(convoy) ~= "table" then return false end
    local groupId = convoy.physicalGuardGroupId
    if groupId and not bcvs_groupExists(gmd, groupId) then
        convoy.physicalGuardGroupId = nil
        convoy.physicalState = "virtual"
        convoy.physicalMaterialized = false
        convoy.physicalReconciledAt = NPCConvoysBridge.NowHours and NPCConvoysBridge.NowHours() or 0
        return true
    end
    if (convoy.physicalState == "materialized" or convoy.physicalState == "materializing") and not groupId then
        convoy.physicalState = "virtual"
        convoy.physicalMaterialized = false
        convoy.physicalReconciledAt = NPCConvoysBridge.NowHours and NPCConvoysBridge.NowHours() or 0
        return true
    end
    return false
end

local function bcvs_applyConvoyMemberFields(member, group, convoy, index)
    if type(member) ~= "table" then return member end
    local level = convoy.objective == "raid" and 5 or 3
    local stars = level >= 5 and 2 or 1
    member.convoyGuard = true
    member.convoyId = tostring(convoy.id or "")
    member.displayTitle = index == 1 and "Convoy Courier" or "Convoy Guard"
    member.nameplateTitle = member.displayTitle
    member.unitLevel = level
    member.unitStars = stars
    member.eliteUnit = false
    member.role = index == 1 and "convoy_courier" or "convoy_guard"
    member.tacticalRole = index == 1 and "courier" or "guard"
    member.program = {name=convoy.objective == "raid" and "Raider" or "BaseGuard", stage="Prepare"}
    member.order = {name="Guard", source="convoy_physical", fireMode=convoy.objective == "raid" and "FireAtWill" or "Defensive", priority=72, sticky=false, anchor={x=convoy.x, y=convoy.y, z=convoy.z or 0}, note="Protect convoy cargo"}
    member.factionSide = group.side
    member.faction = group.side
    member.side = group.side
    member.patrolColor = group.side
    member.convoyCargoResource = convoy.cargoResource
    member.preferRoads = true
    member.roadBias = true
    member.preferCover = true
    return member
end

local function bcvs_spawnConvoyPhysicalGroup(gmd, convoy, player)
    if not (gmd and convoy and player and NPCConvoysBridge and NPCConvoysBridge.IsPhysicalEnabled and NPCConvoysBridge.IsPhysicalEnabled()) then return false end
    bcvs_reconcilePhysicalState(gmd, convoy)
    if bcvs_groupExists(gmd, convoy.physicalGuardGroupId) then return false end
    if convoy.physicalState == "materialized" then return false end
    local director = bcvs_worldDirector()
    if not director then return false end
    if not (NPCWorldDirectorBridge and NPCWorldDirectorBridge.PrepareVirtualMember) then return false end

    local minCount, maxCount = 2, 5
    if NPCConvoysBridge.PhysicalGuardRange then
        local okRange, gotMin, gotMax = pcall(function() return NPCConvoysBridge.PhysicalGuardRange() end)
        if okRange then
            minCount = tonumber(gotMin) or minCount
            maxCount = tonumber(gotMax) or maxCount
        end
    end
    local span = math.max(0, maxCount - minCount)
    local count = minCount + (span > 0 and ZombRand(span + 1) or 0)
    if convoy.objective == "escort" then count = math.max(1, count - 1) end
    if NPCWorldDirectorBridge.ClampGroupSize then count = NPCWorldDirectorBridge.ClampGroupSize(count, 1, 8) end
    local groupId = "CVG" .. tostring(convoy.id or tostring(ZombRand(999999)))
    local side = convoy.side or convoy.factionSide or "red"
    local wave = bcvs_waveForConvoy(convoy, count)
    local group = {
        id = groupId,
        x = math.floor(tonumber(convoy.x) or 0),
        y = math.floor(tonumber(convoy.y) or 0),
        z = tonumber(convoy.z) or 0,
        preciseX = tonumber(convoy.x) or 0,
        preciseY = tonumber(convoy.y) or 0,
        clanId = wave.clanId,
        count = count,
        hostile = convoy.objective == "raid",
        program = {name=convoy.objective == "raid" and "Raider" or "BaseGuard", stage="Prepare"},
        members = {},
        virtual = true,
        activated = false,
        createdAt = NPCConvoysBridge.NowHours and NPCConvoysBridge.NowHours() or 0,
        updatedAt = NPCConvoysBridge.NowHours and NPCConvoysBridge.NowHours() or 0,
        state = convoy.objective == "raid" and "enemy_convoy_guard" or "friendly_convoy_guard",
        spawnClass = "convoy_guard",
        targetX = convoy.destX,
        targetY = convoy.destY,
        targetZ = convoy.destZ or 0,
        routeX = convoy.routeX or convoy.destX,
        routeY = convoy.routeY or convoy.destY,
        routeZ = convoy.destZ or 0,
        targetClass = "convoy_route",
        speed = tonumber(convoy.speedTilesPerHour) or 92,
        roadBias = true,
        preferRoads = true,
        patrolColor = side,
        factionSide = side,
        faction = side,
        side = side,
        convoyGuardGroup = true,
        convoyId = tostring(convoy.id or ""),
        convoyObjective = convoy.objective,
        convoyCargoResource = convoy.cargoResource,
        displayTitle = convoy.objective == "raid" and "Enemy Convoy" or "Convoy Escort",
        name = convoy.objective == "raid" and "Enemy convoy guard" or "Convoy escort team"
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
        bcvs_applyConvoyMemberFields(member, group, convoy, i)
        group.members[#group.members + 1] = member
    end
    group.count = #group.members
    if group.count <= 0 then return false end

    gmd.VirtualGroups = gmd.VirtualGroups or {}
    gmd.VirtualGroups[groupId] = group
    convoy.physicalGuardGroupId = groupId
    convoy.physicalState = "materializing"
    convoy.physicalMaterializedAt = NPCConvoysBridge.NowHours and NPCConvoysBridge.NowHours() or 0

    if NPCPersistentNPCBridge and NPCPersistentNPCBridge.RegisterGroup then pcall(function() NPCPersistentNPCBridge.RegisterGroup(gmd, group) end) end
    local ok = false
    if director.MaterializeGroup then
        ok = pcall(function() return director.MaterializeGroup(group, player) end)
    elseif NPCWorldDirectorBridge.MaterializeGroup then
        ok = pcall(function() return NPCWorldDirectorBridge.MaterializeGroup(director, group, player) end)
    end
    if ok then
        convoy.physicalState = "materialized"
        convoy.physicalMaterialized = true
        if NPCDiagnosticsBridge and NPCDiagnosticsBridge.LogRiskAction then
            NPCDiagnosticsBridge.LogRiskAction("convoys", "physical_materialized", {convoyId=convoy.id, groupId=groupId, side=convoy.side, objective=convoy.objective, x=convoy.x, y=convoy.y, guards=group.count}, "convoy-materialized:" .. tostring(convoy.id), true)
        end
        bcvs_halo(player, "Convoy contact: physical escort spotted nearby.", convoy.objective == "raid" and 255 or 140, convoy.objective == "raid" and 120 or 240, 120)
        return true
    end
    convoy.physicalState = "virtual"
    return false
end

local function bcvs_materializeNearbyConvoys(gmd)
    if not (gmd and NPCConvoysBridge and NPCConvoysBridge.IsPhysicalEnabled and NPCConvoysBridge.IsPhysicalEnabled()) then return 0 end
    local data = NPCConvoysBridge.EnsureData(gmd)
    if not data then return 0 end
    local radius = NPCConvoysBridge.PhysicalSpawnDistance and NPCConvoysBridge.PhysicalSpawnDistance() or 96
    local maxPerTick = math.floor(bcvs_num("Convoy_PhysicalMaxMaterializePerTick", 1, 0, 8))
    if maxPerTick <= 0 then return 0 end
    local made = 0
    local reconciled = 0
    for _, convoy in pairs(data.active or {}) do
        if type(convoy) == "table" and bcvs_reconcilePhysicalState(gmd, convoy) then reconciled = reconciled + 1 end
        if made >= maxPerTick then break end
        if type(convoy) == "table" and (convoy.status == "active" or convoy.status == "arrived") and not convoy.physicalGuardGroupId then
            for _, player in ipairs(bcvs_players()) do
                if player and player.getX and player.getY and bcvs_dist(player:getX(), player:getY(), convoy.x, convoy.y) <= radius then
                    if bcvs_spawnConvoyPhysicalGroup(gmd, convoy, player) then
                        made = made + 1
                    end
                    break
                end
            end
        end
    end
    return made + reconciled
end

local function bcvs_sendActive(player)
    if not player then return end
    local gmd = GetNPCModData()
    bcvs_ensure(gmd)
    local op, convoy = NPCConvoysBridge.GetActiveOperation(gmd, player)
    if op and convoy then
        local copy = {}
        for k, v in pairs(convoy) do copy[k] = v end
        copy.operationText = NPCConvoysBridge.OperationText(op, convoy)
        sendServerCommand(player, 'NPCConvoys', 'Active', copy)
    else
        sendServerCommand(player, 'NPCConvoys', 'Clear', {})
    end
end

local function bcvs_requestOperation(player, args)
    if not (NPCConvoysBridge and NPCConvoysBridge.IsEnabled and NPCConvoysBridge.IsEnabled()) then return end
    if type(args) ~= "table" then return end

    local gmd = GetNPCModData()
    bcvs_ensure(gmd)

    local base = NPCConvoysBridge.FindBaseById(gmd, args.baseId)
    if not base then
        bcvs_halo(player, "No convoy base found nearby.", 255, 120, 80)
        return
    end
    if not NPCConvoysBridge.CanUseBase(base, player) then
        bcvs_halo(player, "This base will not organize convoys with you.", 255, 120, 80)
        return
    end

    local convoy, err = NPCConvoysBridge.CreateFromBase(gmd, player, base, args.objective or args.mode or "escort")
    if not convoy then
        if err == "operation_active" then
            bcvs_halo(player, "Convoy operation already active.", 255, 220, 120)
        elseif err == "too_many" then
            bcvs_halo(player, "Too many active convoys in the world.", 255, 180, 80)
        else
            bcvs_halo(player, "No convoy operation available: " .. tostring(err or "none"), 255, 120, 80)
        end
        bcvs_sendActive(player)
        return
    end

    local marker = NPCConvoysBridge.MakeMarker(convoy)
    if marker then bcvs_setMarker(gmd, marker) end
    bcvs_sendActive(player)
    bcvs_halo(player, tostring(convoy.text or "Convoy operation started."), 140, 240, 160)
    bcvs_say(player, tostring(convoy.text or "Convoy operation started."))
    TransmitNPCModData()
end

local function bcvs_completeEscort(player, args)
    if not (NPCConvoysBridge and NPCConvoysBridge.IsEnabled and NPCConvoysBridge.IsEnabled()) then return end
    local gmd = GetNPCModData()
    bcvs_ensure(gmd)

    local convoy, err = NPCConvoysBridge.CompleteEscort(gmd, player)
    if err then
        if err == "not_arrived" then
            bcvs_halo(player, "Convoy has not reached its destination yet.", 255, 180, 80)
        elseif err == "too_far" then
            bcvs_halo(player, "Move closer to the convoy to complete escort.", 255, 180, 80)
        else
            bcvs_halo(player, "No escort convoy to complete.", 255, 120, 80)
        end
        bcvs_sendActive(player)
        return
    end

    bcvs_removeMarker(gmd, convoy.markerId)
    bcvs_sendActive(player)
    bcvs_halo(player, "Convoy delivered: " .. tostring(convoy.cargoAmount or 0) .. " " .. tostring(convoy.cargoLabel or convoy.cargoResource or "cargo") .. ". Favor gained.", 120, 255, 120)
    if NPCFactionDocsServerBridge and NPCFactionDocsServerBridge.GrantIntelReward then
        NPCFactionDocsServerBridge.GrantIntelReward(player, convoy.side or convoy.factionSide, "convoy_escort")
    end
    bcvs_say(player, "Convoy delivered.")
    TransmitNPCModData()
end

local function bcvs_raidConvoy(player, args)
    if not (NPCConvoysBridge and NPCConvoysBridge.IsEnabled and NPCConvoysBridge.IsEnabled()) then return end
    local gmd = GetNPCModData()
    bcvs_ensure(gmd)

    local convoy, err = NPCConvoysBridge.RaidConvoy(gmd, player, args and args.convoyId or nil)
    if err then
        if err == "too_far" then
            bcvs_halo(player, "Move closer to the convoy before raiding.", 255, 180, 80)
        elseif err == "not_enemy" then
            bcvs_halo(player, "This convoy is not a valid enemy target.", 255, 180, 80)
        elseif err == "failed" and convoy then
            bcvs_halo(player, "Raid failed. The convoy is still moving.", 255, 120, 80)
            local marker = NPCConvoysBridge.MakeMarker(convoy)
            if marker then bcvs_setMarker(gmd, marker) end
        else
            bcvs_halo(player, "No enemy convoy nearby.", 255, 120, 80)
        end
        bcvs_sendActive(player)
        return
    end

    bcvs_removeMarker(gmd, convoy.markerId)
    bcvs_sendActive(player)
    local lootText = tostring(convoy.lootItemsGiven or 0) .. " loot item(s)"
    if convoy.physicalCargo == true then
        bcvs_halo(player, "Convoy raided: cargo package dropped nearby (" .. lootText .. ").", 120, 255, 120)
    else
        bcvs_halo(player, "Convoy raided: seized " .. lootText .. ".", 120, 255, 120)
    end
    if NPCFactionDocsServerBridge and NPCFactionDocsServerBridge.GrantIntelReward then
        NPCFactionDocsServerBridge.GrantIntelReward(player, convoy.side or convoy.factionSide, "convoy_raid")
    end
    bcvs_say(player, "Convoy raided.")
    TransmitNPCModData()
end

local function bcvs_sync(player)
    if not (NPCConvoysBridge and NPCConvoysBridge.IsEnabled and NPCConvoysBridge.IsEnabled()) then return end
    bcvs_sendActive(player)
end

function NPCConvoysServerBridge.OnClientCommand(module, command, player, args)
    if not NPCLegacyContractBridge.IsModule(module, "NPCConvoys", "convoys") then return end
    if command == "RequestSync" then
        bcvs_sync(player)
    elseif command == "RequestOperation" then
        bcvs_requestOperation(player, args)
    elseif command == "CompleteEscort" then
        bcvs_completeEscort(player, args)
    elseif command == "RaidConvoy" then
        bcvs_raidConvoy(player, args)
    end
end

local function bcvs_everyTenMinutes()
    if not (NPCConvoysBridge and NPCConvoysBridge.IsEnabled and NPCConvoysBridge.IsEnabled()) then return end
    local gmd = GetNPCModData()
    bcvs_ensure(gmd)
    local changed = NPCConvoysBridge.Tick(gmd)
    local physicalChanged = bcvs_materializeNearbyConvoys(gmd)
    for _, convoy in ipairs(changed or {}) do
        if convoy.status == "expired" or convoy.status == "completed" or convoy.status == "raided" then
            bcvs_removeMarker(gmd, convoy.markerId)
        else
            local marker = NPCConvoysBridge.MakeMarker(convoy)
            if marker then bcvs_setMarker(gmd, marker) end
        end
    end
    if (changed and #changed > 0) or (physicalChanged and physicalChanged > 0) then TransmitNPCModData() end
end

function NPCConvoysServerBridge.Install()
    if NPCConvoysServerBridge._installed then return end
    Events.OnClientCommand.Add(NPCConvoysServerBridge.OnClientCommand)
    Events.EveryTenMinutes.Add(bcvs_everyTenMinutes)
    NPCConvoysServerBridge._installed = true
end

NPCConvoysServerBridge.Install()
