-- NPCLeadersServerBridge.lua
-- Neutral server backend for faction leader / base commander assignment and death consequences.

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

local NPC_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
if isClient and isClient() then return end

require "NPCCore/NPCLeadersBridge"

NPCLeadersServerBridge = NPCLeadersServerBridge or {}
local function npcserver_setDebugMarker(gmd, marker)
    local runtime = NPCServerRuntime
    local setter = runtime and runtime.SetDebugMarker or NPC_LEGACY_GLOBALS.Get("SetDebugMarker")
    if setter then return setter(gmd, marker) end
    return false
end

local leaders_baseCampSystem = NPCBaseCampSystem or (NPCLegacyGlobalsBridge and NPCLegacyGlobalsBridge.Get and NPCLegacyGlobalsBridge.Get("BaseCampSystem"))
local leaders_bountyServer = NPCBountyServer or (NPCLegacyGlobalsBridge and NPCLegacyGlobalsBridge.Get and NPCLegacyGlobalsBridge.Get("BountyServer"))


local function bls_halo(player, text, r, g, b)
    if player and text then sendServerCommand(player, 'NPCLeaders', 'Result', {text=text, r=r or 255, g=g or 225, b=b or 120}) end
end

local function bls_setMarker(gmd, marker)
    if not (gmd and marker and marker.id) then return end
    if not npcserver_setDebugMarker(gmd, marker) then
        gmd.DebugMapMarkers = gmd.DebugMapMarkers or {}
        gmd.DebugMapMarkers[tostring(marker.id)] = marker
        if NPCNetContract and NPCNetContract.SendDebugMapUpdate then
            NPCNetContract.SendDebugMapUpdate(marker)
        else
            sendServerCommand('NPCDebugMap', 'Update', marker)
        end
    end
end

local function bls_removeLeaderMarker(gmd, leader)
    if not (gmd and leader and leader.id) then return end
    local id = "leader_" .. tostring(leader.id)
    if not (gmd.DebugMapMarkers and gmd.DebugMapMarkers[id]) then return end
    gmd.DebugMapMarkers[id] = nil
    if NPCNetContract and NPCNetContract.SendDebugMapRemove then
        NPCNetContract.SendDebugMapRemove(id)
    else
        sendServerCommand('NPCDebugMap', 'Remove', {id=id})
    end
end

local function bls_updateLeaderMarker(gmd, leader)
    if not (NPCLeadersBridge and leader) then return end
    local marker = nil
    if NPCLeadersBridge.MakeLeaderMarkerIfVisible then
        marker = NPCLeadersBridge.MakeLeaderMarkerIfVisible(gmd, leader)
    elseif NPCLeadersBridge.MakeLeaderMarker then
        marker = NPCLeadersBridge.MakeLeaderMarker(leader)
    end
    if marker then
        bls_setMarker(gmd, marker)
    else
        bls_removeLeaderMarker(gmd, leader)
    end
end

local function bls_updateGroupMarker(gmd, group)
    if not (gmd and group and group.id) then return end
    local marker = gmd.DebugMapMarkers and gmd.DebugMapMarkers[tostring(group.id)] or nil
    if not marker then return end
    if NPCLeadersBridge and NPCLeadersBridge.MarkerFields then NPCLeadersBridge.MarkerFields(marker, group) end
    marker.updatedAt = NPCLeadersBridge and NPCLeadersBridge.NowHours and NPCLeadersBridge.NowHours() or marker.updatedAt
    bls_setMarker(gmd, marker)
end

local function bls_now()
    if NPCLeadersBridge and NPCLeadersBridge.NowHours then return NPCLeadersBridge.NowHours() end
    if getGameTime then
        local ok, value = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok and value then return tonumber(value) or 0 end
    end
    return 0
end

local function bls_rand(maxValue)
    maxValue = math.floor(tonumber(maxValue) or 0)
    if maxValue <= 0 then return 0 end
    if ZombRand then
        local ok, value = pcall(function() return ZombRand(maxValue) end)
        if ok and value ~= nil then return tonumber(value) or 0 end
    end
    return math.random(0, maxValue - 1)
end

local function bls_getPlayers()
    local out = {}
    if getOnlinePlayers then
        local ok, players = pcall(function() return getOnlinePlayers() end)
        if ok and players then
            local size = 0
            pcall(function() size = players:size() end)
            for i = 0, math.max(0, size - 1) do
                local okp, player = pcall(function() return players:get(i) end)
                if okp and player then out[#out + 1] = player end
            end
        end
    end
    if #out <= 0 and getPlayer then
        local ok, player = pcall(function() return getPlayer() end)
        if ok and player then out[#out + 1] = player end
    end
    return out
end

local function bls_distSq(ax, ay, bx, by)
    ax = tonumber(ax) or 0
    ay = tonumber(ay) or 0
    bx = tonumber(bx) or 0
    by = tonumber(by) or 0
    local dx = ax - bx
    local dy = ay - by
    return dx * dx + dy * dy
end

local function bls_findBase(gmd, baseId)
    if not (gmd and gmd.BaseCamps and baseId) then return nil end
    local sid = tostring(baseId)
    local direct = gmd.BaseCamps[sid]
    if type(direct) == "table" then return direct end
    for _, base in pairs(gmd.BaseCamps) do
        if type(base) == "table" and tostring(base.id or "") == sid then return base end
    end
    return nil
end

local function bls_groupExists(gmd, groupId)
    if not (gmd and gmd.VirtualGroups and groupId) then return false end
    local group = gmd.VirtualGroups[tostring(groupId)]
    if type(group) ~= "table" then return false end
    if group.dead == true or group.destroyed == true or group.removed == true then return false end
    return true
end

local function bls_sideHostile(side)
    return tostring(side or "") == "red"
end

local function bls_applyHumanLeaderAnimationProfile(member)
    if type(member) ~= "table" then return member end
    member.humanNPC = true
    member.forceHumanAnimation = true
    member.noZombieAnimation = true
    member.preferHumanAnimation = true
    member.walkType = member.walkType or "Walk"
    member.defaultWalkType = member.defaultWalkType or "Walk"
    member.infection = 0
    member.sound = 0
    member.eatBody = false
    member.crawler = false
    member.knockedDown = false
    member.fakeDead = false
    member.fallOnFront = false
    member.sitting = false
    member.dna = member.dna or {}
    member.dna.slow = false
    member.dna.blind = false
    member.dna.sneak = false
    member.dna.unfit = false
    member.dna.coward = false
    return member
end

local function bls_repairLeaderRuntimeBrain(gmd, brain, leader)
    if not (brain and leader) then return false end
    local changed = false
    if NPCLeadersBridge and NPCLeadersBridge.EnsureLeaderHumanName then
        changed = NPCLeadersBridge.EnsureLeaderHumanName(leader) == true or changed
    end
    local name = leader.name or brain.fullname or brain.name
    if brain.leaderName ~= name then brain.leaderName = name; changed = true end
    if brain.leader == true or brain.isFactionLeader == true or brain.role == "leader" then
        if brain.fullname ~= name then brain.fullname = name; changed = true end
        if brain.name ~= name then brain.name = name; changed = true end
    end
    bls_applyHumanLeaderAnimationProfile(brain)
    return changed
end

local function bls_guardCount()
    local minValue = 2
    local maxValue = 4
    if NPCLeadersBridge and NPCLeadersBridge.PhysicalGuardMin then minValue = NPCLeadersBridge.PhysicalGuardMin() end
    if NPCLeadersBridge and NPCLeadersBridge.PhysicalGuardMax then maxValue = NPCLeadersBridge.PhysicalGuardMax() end
    minValue = math.max(0, math.floor(tonumber(minValue) or 0))
    maxValue = math.max(minValue, math.floor(tonumber(maxValue) or minValue))
    if maxValue <= minValue then return minValue end
    return minValue + bls_rand((maxValue - minValue) + 1)
end

local function bls_makeLeaderMember(leader, base)
    local member = {
        role = "leader",
        tacticalRole = "leader",
        program = "BaseGuard",
        baseId = leader.baseId or (base and base.id),
        homeBaseId = leader.baseId or (base and base.id),
        homeBase = base and {x=base.x, y=base.y, z=base.z or 0} or nil,
        factionSide = leader.side,
        faction = leader.side,
        side = leader.side,
        patrolColor = leader.side
    }
    if NPCLeadersBridge and NPCLeadersBridge.EnsureLeaderHumanName then
        NPCLeadersBridge.EnsureLeaderHumanName(leader)
    end
    if NPCLeadersBridge and NPCLeadersBridge.ApplyLeaderIdentityToMember then
        NPCLeadersBridge.ApplyLeaderIdentityToMember(member, leader, 1)
    end
    member.fullname = leader.name or member.fullname or member.name
    member.name = member.fullname
    member.displayName = member.fullname
    member.displayTitle = leader.kind == "base_commander" and "Faction Commander" or "Faction Leader"
    member.nameplateTitle = member.displayTitle
    member.unitLevel = 10
    member.unitStars = 3
    member.eliteUnit = true
    member.commandUnit = true
    member.leaderPhysical = true
    member.physicalLeader = true
    member.commanderPhysical = true
    member.preferCover = true
    member.guardBase = true
    bls_applyHumanLeaderAnimationProfile(member)
    return member
end

local function bls_makeLeaderGuard(leader, base, index)
    local member = {
        role = "base_guard",
        tacticalRole = "bodyguard",
        program = "BaseGuard",
        baseId = leader.baseId or (base and base.id),
        homeBaseId = leader.baseId or (base and base.id),
        homeBase = base and {x=base.x, y=base.y, z=base.z or 0} or nil,
        factionSide = leader.side,
        faction = leader.side,
        side = leader.side,
        patrolColor = leader.side
    }
    if NPCLeadersBridge and NPCLeadersBridge.ApplyLeaderSquadIdentityToMember then
        NPCLeadersBridge.ApplyLeaderSquadIdentityToMember(member, leader, index)
    end
    member.displayTitle = "Commander Guard"
    member.nameplateTitle = member.displayTitle
    member.unitLevel = index == 2 and 7 or 6
    member.unitStars = 2
    member.eliteUnit = false
    member.commanderEscort = true
    member.leaderEscort = true
    member.guardBase = true
    bls_applyHumanLeaderAnimationProfile(member)
    return member
end

local function bls_makePhysicalLeaderGroup(gmd, leader, base)
    if not (gmd and leader and base) then return nil end
    local guardCount = bls_guardCount()
    local members = { bls_makeLeaderMember(leader, base) }
    for i = 1, guardCount do
        members[#members + 1] = bls_makeLeaderGuard(leader, base, i + 1)
    end

    if NPCLeadersBridge and NPCLeadersBridge.EnsureLeaderHumanName then
        NPCLeadersBridge.EnsureLeaderHumanName(leader)
    end
    local groupId = "LDR_" .. tostring(leader.id or tostring(base.id or "base"))
    local now = bls_now()
    local group = {
        id = groupId,
        x = tonumber(base.x) or tonumber(leader.x) or 0,
        y = tonumber(base.y) or tonumber(leader.y) or 0,
        z = tonumber(base.z) or tonumber(leader.z) or 0,
        count = #members,
        hostile = bls_sideHostile(leader.side),
        program = {name="BaseGuard", stage="CommanderGuard"},
        members = members,
        virtual = true,
        activated = false,
        createdAt = now,
        updatedAt = now,
        state = "leader_guard",
        spawnClass = "leader_commander",
        targetX = tonumber(base.x) or tonumber(leader.x) or 0,
        targetY = tonumber(base.y) or tonumber(leader.y) or 0,
        targetZ = tonumber(base.z) or tonumber(leader.z) or 0,
        targetClass = "base_command",
        speed = 0,
        factionSide = leader.side,
        faction = leader.side,
        side = leader.side,
        patrolColor = leader.side,
        homeBaseId = tostring(base.id or leader.baseId or ""),
        originBaseId = tostring(base.id or leader.baseId or ""),
        baseOwnedGlobalSquad = true,
        baseOwnedRole = "commander_guard",
        routeOwnerBaseId = tostring(base.id or leader.baseId or ""),
        leader = true,
        isFactionLeader = true,
        leaderId = leader.id,
        leaderName = leader.name,
        leaderRole = leader.kind,
        leaderTitle = leader.title,
        leaderSide = leader.side,
        leaderState = leader.state or "active",
        leaderInfluence = leader.influence or 100,
        leaderArchetype = leader.leaderArchetype,
        physicalLeaderGroup = true,
        displayTitle = "Faction Commander",
        unitLevel = 10,
        unitStars = 3,
        eliteUnit = true
    }
    if NPCLeadersBridge and NPCLeadersBridge.MarkerFields then NPCLeadersBridge.MarkerFields(group, leader) end
    return group
end


local function bls_reconcilePhysicalLeaderState(gmd, leader, base)
    if type(leader) ~= "table" then return false end
    local changed = false
    if leader.physicalGroupId and not bls_groupExists(gmd, leader.physicalGroupId) then
        leader.physicalGroupId = nil
        leader.physicalMaterializedAt = nil
        leader.updatedAt = bls_now()
        changed = true
    end
    if base and base.commanderPhysicalGroupId and not bls_groupExists(gmd, base.commanderPhysicalGroupId) then
        base.commanderPhysicalGroupId = nil
        base.commanderPhysicalAt = nil
        changed = true
    end
    return changed
end

local function bls_materializeLeaderGroup(gmd, leader, base, player)
    if not (gmd and leader and base and player and NPCLeadersBridge and NPCLeadersBridge.IsLeaderAlive and NPCLeadersBridge.IsLeaderAlive(leader)) then return false end
    if bls_groupExists(gmd, leader.physicalGroupId or leader.groupId) then return false end

    local now = bls_now()
    local retryAt = tonumber(leader.physicalRetryAt or 0) or 0
    if retryAt > 0 and now < retryAt then return false end

    local group = bls_makePhysicalLeaderGroup(gmd, leader, base)
    if not group then return false end

    gmd.VirtualGroups = gmd.VirtualGroups or {}
    gmd.VirtualGroups[tostring(group.id)] = group
    if NPCIdentityBridge and NPCIdentityBridge.TouchVirtualGroup then
        pcall(function() NPCIdentityBridge.TouchVirtualGroup(gmd, group) end)
    end
    if NPCPersistentNPCBridge and NPCPersistentNPCBridge.RegisterGroup then
        pcall(function() NPCPersistentNPCBridge.RegisterGroup(gmd, group) end)
    end

    local director = NPCWorldDirector
    local ok = false
    if director and director.MaterializeGroup then
        local safe, result = pcall(function() return director.MaterializeGroup(group, player) end)
        ok = safe and result == true
    elseif director and NPCWorldDirectorBridge and NPCWorldDirectorBridge.MaterializeGroup then
        local safe, result = pcall(function() return NPCWorldDirectorBridge.MaterializeGroup(director, group, player) end)
        ok = safe and result == true
    end
    if ok then
        leader.physicalGroupId = group.id
        leader.physicalMaterializedAt = now
        NPCLeadersServerBridge.RepairPhysicalLeaderRuntimeBrains()
        leader.physicalRetryAt = nil
        leader.updatedAt = now
        base.commanderPhysicalGroupId = group.id
        base.commanderPhysicalAt = now
        return true
    end

    leader.physicalRetryAt = now + (NPCLeadersBridge.PhysicalRetryHours and NPCLeadersBridge.PhysicalRetryHours() or 0.35)
    leader.updatedAt = now
    gmd.VirtualGroups[tostring(group.id)] = nil
    return false
end

function NPCLeadersServerBridge.MaterializePhysicalLeaders()
    if not (NPCLeadersBridge and NPCLeadersBridge.IsEnabled and NPCLeadersBridge.IsEnabled()) then return 0 end
    if not (NPCLeadersBridge.PhysicalLeadersEnabled and NPCLeadersBridge.PhysicalLeadersEnabled()) then return 0 end
    local gmd = GetNPCModData()
    if not gmd then return 0 end
    local data = NPCLeadersBridge.EnsureData(gmd)
    if not (data and type(data.leaders) == "table") then return 0 end

    local players = bls_getPlayers()
    if #players <= 0 then return 0 end

    local distance = NPCLeadersBridge.PhysicalSpawnDistance and NPCLeadersBridge.PhysicalSpawnDistance() or 120
    local distanceSq = distance * distance
    local maxCount = NPCLeadersBridge.PhysicalMaxMaterializePerTick and NPCLeadersBridge.PhysicalMaxMaterializePerTick() or 1
    if maxCount <= 0 then return 0 end

    local materialized = 0
    local reconciled = 0
    for _, player in ipairs(players) do
        if materialized >= maxCount then break end
        local px = player.getX and player:getX() or nil
        local py = player.getY and player:getY() or nil
        if px and py then
            for _, leader in pairs(data.leaders) do
                if materialized >= maxCount then break end
                if type(leader) == "table" and leader.kind == "base_commander" and NPCLeadersBridge.IsLeaderAlive(leader) then
                    local base = bls_findBase(gmd, leader.baseId or leader.ownerId)
                    if bls_reconcilePhysicalLeaderState(gmd, leader, base) then reconciled = reconciled + 1 end
                    if base and base.x and base.y and not bls_groupExists(gmd, leader.physicalGroupId) then
                        if bls_distSq(px, py, base.x, base.y) <= distanceSq then
                            if bls_materializeLeaderGroup(gmd, leader, base, player) then
                                materialized = materialized + 1
                                bls_updateLeaderMarker(gmd, leader)
                            end
                        end
                    end
                end
            end
        end
    end
    if (materialized > 0 or reconciled > 0) and TransmitNPCModData then TransmitNPCModData() end
    return materialized + reconciled
end

function NPCLeadersServerBridge.RepairPhysicalLeaderRuntimeBrains()
    if not (NPCLeadersBridge and NPCLeadersBridge.EnsureLeaderHumanName) then return 0 end
    local gmd = GetNPCModData()
    if not gmd then return 0 end
    local data = NPCLeadersBridge.EnsureData(gmd)
    if not (data and type(data.leaders) == "table") then return 0 end
    local changed = 0

    for _, leader in pairs(data.leaders) do
        if type(leader) == "table" and NPCLeadersBridge.EnsureLeaderHumanName(leader) then changed = changed + 1 end
    end

    if type(gmd.Queue) == "table" then
        for _, brain in pairs(gmd.Queue) do
            if type(brain) == "table" and brain.leaderId then
                local leader = data.leaders[tostring(brain.leaderId)]
                if leader and bls_repairLeaderRuntimeBrain(gmd, brain, leader) then changed = changed + 1 end
            end
        end
    end

    if type(gmd.VirtualGroups) == "table" then
        for _, group in pairs(gmd.VirtualGroups) do
            if type(group) == "table" then
                if group.leaderId then
                    local leader = data.leaders[tostring(group.leaderId)]
                    if leader then
                        if NPCLeadersBridge.EnsureLeaderHumanName(leader) then changed = changed + 1 end
                        if group.leaderName ~= leader.name then group.leaderName = leader.name; changed = changed + 1 end
                    end
                end
                if type(group.members) == "table" then
                    for _, member in ipairs(group.members) do
                        if type(member) == "table" and member.leaderId then
                            local leader = data.leaders[tostring(member.leaderId)]
                            if leader and bls_repairLeaderRuntimeBrain(gmd, member, leader) then changed = changed + 1 end
                        end
                    end
                end
            end
        end
    end

    if changed > 0 and TransmitNPCModData then TransmitNPCModData() end
    return changed
end

function NPCLeadersServerBridge.EnsureWorldLeaders()
    if not (NPCLeadersBridge and NPCLeadersBridge.IsEnabled and NPCLeadersBridge.IsEnabled()) then return 0 end
    local gmd = GetNPCModData()
    if not gmd then return 0 end
    NPCLeadersBridge.EnsureData(gmd)
    local changed = 0
    changed = changed + NPCLeadersServerBridge.RepairPhysicalLeaderRuntimeBrains()

    if NPCLeadersBridge.BaseCommandersEnabled() and type(gmd.BaseCamps) == "table" then
        for _, base in pairs(gmd.BaseCamps) do
            if type(base) == "table" then
                local before = base.commanderId
                local leader = NPCLeadersBridge.EnsureBaseCommander(gmd, base)
                if leader then
                    bls_updateLeaderMarker(gmd, leader)
                    if leaders_baseCampSystem and leaders_baseCampSystem.SendBaseMarker then pcall(function() leaders_baseCampSystem.SendBaseMarker(base) end) end
                    if before ~= base.commanderId then changed = changed + 1 end
                end
            end
        end
    end

    if NPCLeadersBridge.SquadLeadersEnabled() and type(gmd.VirtualGroups) == "table" then
        local sideCounts = {}
        for groupId, group in pairs(gmd.VirtualGroups) do
            if type(group) == "table" and not group.mercenaryHired then
                local side = NPCLeadersBridge.Side(group.factionSide or group.side or group.patrolColor or group.faction)
                if side then
                    sideCounts[side] = sideCounts[side] or 0
                    if sideCounts[side] < NPCLeadersBridge.MaxGroupLeadersPerSide() then
                        local before = group.leaderId
                        local leader = NPCLeadersBridge.EnsureGroupLeader(gmd, group, groupId)
                        if leader then
                            sideCounts[side] = sideCounts[side] + 1
                            gmd.VirtualGroups[groupId] = group
                            bls_updateLeaderMarker(gmd, leader)
                            bls_updateGroupMarker(gmd, group)
                            if before ~= group.leaderId then changed = changed + 1 end
                        end
                    end
                end
            end
        end
    end

    if changed > 0 and TransmitNPCModData then TransmitNPCModData() end
    return changed
end

function NPCLeadersServerBridge.ReportLeaderKilled(player, args)
    if not (NPCLeadersBridge and NPCLeadersBridge.IsEnabled and NPCLeadersBridge.IsEnabled()) then return end
    local gmd = GetNPCModData()
    if not gmd then return end
    args = args or {}
    args.playerId = args.playerId or (NPCBountyBridge and NPCBountyBridge.PlayerId and NPCBountyBridge.PlayerId(player))
    args.playerName = args.playerName or (NPCBountyBridge and NPCBountyBridge.PlayerName and NPCBountyBridge.PlayerName(player))
    if player and player.getX then
        args.x = args.x or player:getX()
        args.y = args.y or player:getY()
    end
    local leader = NPCLeadersBridge.MarkLeaderKilled(gmd, player, args)
    if not leader then return end

    bls_updateLeaderMarker(gmd, leader)
    if leader.baseId and gmd.BaseCamps and gmd.BaseCamps[tostring(leader.baseId)] and leaders_baseCampSystem and leaders_baseCampSystem.SendBaseMarkers then
        pcall(function() leaders_baseCampSystem.SendBaseMarkers(gmd.BaseCamps[tostring(leader.baseId)], true) end)
    end

    if NPCBountyBridge and NPCBountyBridge.Add and player and leader.side then
        local sideRec, rec = NPCBountyBridge.Add(gmd, player, leader.side, NPCLeadersBridge.BountyBonus(), "killed_leader", {leaderId=leader.id})
        if sideRec and rec and NPCBountyBridge.MakeBountyMarker then
            local marker = NPCBountyBridge.MakeBountyMarker(rec, leader.side, sideRec)
            if marker then bls_setMarker(gmd, marker) end
        end
        if sideRec and leaders_bountyServer and leaders_bountyServer.DispatchHuntersFor and NPCBountyBridge.IsSideRecordActive(sideRec, NPCBountyBridge.HuntedThreshold()) then
            pcall(function() leaders_bountyServer.DispatchHuntersFor(player, leader.side, sideRec) end)
        end
    end

    bls_halo(player, tostring(leader.name or "Faction leader") .. " eliminated. " .. tostring(NPCLeadersBridge.SideLabel(leader.side)) .. " command disrupted.", 255, 120, 60)
    if TransmitNPCModData then TransmitNPCModData() end
end

function NPCLeadersServerBridge.Status(player)
    local gmd = GetNPCModData()
    NPCLeadersServerBridge.EnsureWorldLeaders()
    local payload = NPCLeadersBridge and NPCLeadersBridge.BuildStatusPayload and NPCLeadersBridge.BuildStatusPayload(gmd) or {text="No leader data."}
    sendServerCommand(player, 'NPCLeaders', 'State', payload)
    bls_halo(player, payload.text or "No leader data.", 255, 225, 120)
end

function NPCLeadersServerBridge.Refresh(player)
    local gmd = GetNPCModData()
    NPCLeadersServerBridge.EnsureWorldLeaders()
    local data = NPCLeadersBridge and NPCLeadersBridge.EnsureData and NPCLeadersBridge.EnsureData(gmd) or nil
    if data and type(data.leaders) == "table" then
        for _, leader in pairs(data.leaders) do bls_updateLeaderMarker(gmd, leader) end
    end
    NPCLeadersServerBridge.Status(player)
end

function NPCLeadersServerBridge.OnClientCommand(module, command, player, args)
    if not NPCLegacyContractBridge.IsModule(module, "NPCLeaders", "leaders") then return end
    if command == "ReportLeaderKilled" then
        NPCLeadersServerBridge.ReportLeaderKilled(player, args or {})
    elseif command == "Status" then
        NPCLeadersServerBridge.Status(player)
    elseif command == "Refresh" then
        NPCLeadersServerBridge.Refresh(player)
    end
end

function NPCLeadersServerBridge.EveryTenMinutes()
    NPCLeadersServerBridge.EnsureWorldLeaders()
    NPCLeadersServerBridge.MaterializePhysicalLeaders()
end

function NPCLeadersServerBridge.OnTick(tick)
    tick = tonumber(tick) or 0
    if tick % 300 ~= 0 then return end
    NPCLeadersServerBridge.MaterializePhysicalLeaders()
end

function NPCLeadersServerBridge.Install()
    if NPCLeadersServerBridge._installed then return end
    Events.OnClientCommand.Add(NPCLeadersServerBridge.OnClientCommand)
    Events.EveryTenMinutes.Add(NPCLeadersServerBridge.EveryTenMinutes)
    Events.OnTick.Add(NPCLeadersServerBridge.OnTick)
    NPCLeadersServerBridge._installed = true
end

NPCLeadersServerBridge.Install()
