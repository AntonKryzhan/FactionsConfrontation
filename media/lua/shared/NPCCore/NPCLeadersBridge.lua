-- NPCLeadersBridge.lua
-- Neutral shared backend for faction leader / base commander state.
-- Leaders are virtual roles attached to existing bases and groups. They do not spawn extra NPCs by themselves.

NPCLeadersBridge = NPCLeadersBridge or {}
NPCLeadersBridge.Version = 1

require "NPCCore/NPCWeaponsBridge"

local BL_SIDES = {"red", "green", "blue"}

local function bl_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        local ok, value = pcall(function() return NPCLegacySettingsBridge.GetBool(name, defaultValue == true) end)
        if ok and value ~= nil then return value == true end
    end
    return defaultValue == true
end

local function bl_num(name, defaultValue, minValue, maxValue)
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

local function bl_now()
    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then
            local ok, value = pcall(function() return gt:getWorldAgeHours() end)
            if ok and value then return tonumber(value) or 0 end
        end
    end
    return os.time and (os.time() / 3600) or 0
end

local function bl_rand(maxValue)
    maxValue = math.floor(tonumber(maxValue) or 0)
    if maxValue <= 0 then return 0 end
    if ZombRand then
        local ok, value = pcall(function() return ZombRand(maxValue) end)
        if ok and value ~= nil then return tonumber(value) or 0 end
    end
    return math.random(0, maxValue - 1)
end

local function bl_clamp(value, minValue, maxValue)
    value = tonumber(value) or 0
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function bl_side(side)
    if NPCFactionBridge and NPCFactionBridge.NormalizeSide then
        local s = NPCFactionBridge.NormalizeSide(side)
        if s then return s end
    end
    side = tostring(side or ""):lower()
    if side == "red" or side == "green" or side == "blue" then return side end
    return nil
end

local function bl_sideLabel(side)
    if NPCFactionBridge and NPCFactionBridge.GetSideLabel then
        local ok, label = pcall(function() return NPCFactionBridge.GetSideLabel(side) end)
        if ok and label then return tostring(label) end
    end
    return tostring(side or "faction")
end

function NPCLeadersBridge.IsEnabled()
    return bl_bool("Leader_Enabled", true)
end

function NPCLeadersBridge.BaseCommandersEnabled()
    return bl_bool("Leader_BaseCommandersEnabled", true)
end

function NPCLeadersBridge.SquadLeadersEnabled()
    return bl_bool("Leader_SquadLeadersEnabled", true)
end

function NPCLeadersBridge.ReplacementHours()
    return bl_num("Leader_ReplacementHours", 24, 1, 240)
end

function NPCLeadersBridge.BaseDeathReadinessPenalty()
    return bl_num("Leader_BaseDeathReadinessPenalty", 18, 0, 100)
end

function NPCLeadersBridge.BaseDeathMoralePenalty()
    return bl_num("Leader_BaseDeathMoralePenalty", 0.18, 0, 1)
end

function NPCLeadersBridge.BountyBonus()
    return bl_num("Leader_KillBountyBonus", 35, 0, 300)
end

function NPCLeadersBridge.MaxGroupLeadersPerSide()
    return math.floor(bl_num("Leader_MaxGroupLeadersPerSide", 8, 0, 100))
end

function NPCLeadersBridge.RadioWeight()
    return bl_num("Leader_RadioWeight", 3, 0, 20)
end

function NPCLeadersBridge.NowHours()
    return bl_now()
end

function NPCLeadersBridge.Side(side)
    return bl_side(side)
end

function NPCLeadersBridge.SideLabel(side)
    return bl_sideLabel(side)
end

function NPCLeadersBridge.EnsureData(gmd)
    if not gmd then return nil end
    gmd.NPCLeadersBridge = gmd.NPCLeadersBridge or {}
    local data = gmd.NPCLeadersBridge
    data.nextLeaderId = tonumber(data.nextLeaderId) or 1
    data.leaders = data.leaders or {}
    data.byBase = data.byBase or {}
    data.byGroup = data.byGroup or {}
    data.bySide = data.bySide or {}
    data.history = data.history or {}
    data.stats = data.stats or {created=0, killed=0, replaced=0, groups=0, bases=0}
    if not gmd.DebugMapMarkers then gmd.DebugMapMarkers = {} end
    return data
end

local function bl_nextId(data, kind)
    local n = tonumber(data.nextLeaderId) or 1
    data.nextLeaderId = n + 1
    return tostring(kind or "leader") .. "_" .. tostring(n)
end

local function bl_state(leader)
    if not leader then return "missing" end
    if leader.dead == true or leader.state == "dead" then return "dead" end
    if leader.state then return tostring(leader.state) end
    return "active"
end

function NPCLeadersBridge.IsLeaderAlive(leader)
    return leader and leader.dead ~= true and bl_state(leader) ~= "dead"
end


local function bl_groupAlive(gmd, groupId)
    if not (gmd and gmd.VirtualGroups and groupId) then return nil end
    local group = gmd.VirtualGroups[tostring(groupId)]
    if type(group) ~= "table" then return nil end
    if group.dead == true or group.destroyed == true or group.removed == true then return nil end
    local count = tonumber(group.count or group.memberCount or group.membersCount or 0) or 0
    if count <= 0 and type(group.members) == "table" then count = #group.members end
    if count <= 0 then return nil end
    return group
end

local function bl_findBase(gmd, baseId)
    if not (gmd and gmd.BaseCamps and baseId) then return nil end
    local sid = tostring(baseId)
    local direct = gmd.BaseCamps[sid]
    if type(direct) == "table" then return direct end
    for _, base in pairs(gmd.BaseCamps) do
        if type(base) == "table" and tostring(base.id or "") == sid then return base end
    end
    return nil
end

function NPCLeadersBridge.ResolveVisibleGroupId(gmd, leader)
    if not (gmd and leader and NPCLeadersBridge.IsLeaderAlive(leader)) then return nil end

    local groupId = leader.groupId or (leader.kind == "squad_leader" and leader.ownerId) or nil
    if bl_groupAlive(gmd, groupId) then return tostring(groupId) end

    local base = bl_findBase(gmd, leader.baseId or (leader.kind == "base_commander" and leader.ownerId) or nil)
    if base then
        local garrisonId = base.garrisonGroupId or base.homeGroupId or base.guardGroupId
        if bl_groupAlive(gmd, garrisonId) then return tostring(garrisonId) end
    end

    return nil
end

function NPCLeadersBridge.ShouldShowLeaderMarker(gmd, leader)
    return NPCLeadersBridge.ResolveVisibleGroupId(gmd, leader) ~= nil
end

function NPCLeadersBridge.MakeLeaderMarkerIfVisible(gmd, leader)
    local groupId = NPCLeadersBridge.ResolveVisibleGroupId(gmd, leader)
    if not groupId then return nil end
    local marker = NPCLeadersBridge.MakeLeaderMarker(leader)
    if marker then
        marker.groupId = marker.groupId or groupId
        marker.attachedGroupId = groupId
        marker.virtual = true
        marker.active = false
    end
    return marker
end

local function bl_name(side, kind, id)
    local title = kind == "base_commander" and "Commander" or "Leader"
    local sideName = bl_sideLabel(side)
    return sideName .. " " .. title .. " " .. tostring(id or "")
end

local function bl_title(kind)
    if kind == "base_commander" then return "Base commander" end
    if kind == "squad_leader" then return "Squad leader" end
    return "Faction leader"
end

local BL_LEADER_ARCHETYPES = {
    {id="military_commander", outfits={"Veteran", "PrivateMilitia", "ArmyCamoGreen", "ArmyCamoDesert", "PoliceRiot"}, melee={"Base.Machete", "Base.Katana", "Base.Axe"}, rifle=true, pistol=true, health=4.5, accuracy=1.55, femaleChance=8},
    {id="suited_operator", outfits={"Trader", "Generic01", "Generic02", "Police", "Veteran"}, melee={"Base.Knife", "Base.Machete"}, rifle=false, pistol=true, health=4.2, accuracy=1.65, femaleChance=15},
    {id="punk_warlord", outfits={"Punk", "Rocker", "Biker", "Thug", "Redneck"}, melee={"Base.Machete", "Base.BaseballBatNails", "Base.Axe"}, rifle=true, pistol=true, health=4.8, accuracy=1.35, femaleChance=25},
    {id="field_commando", outfits={"Ghillie", "Survivalist03", "PrivateMilitia", "Hunter", "ArmyCamoGreen"}, melee={"Base.HuntingKnife", "Base.Machete", "Base.HandAxe"}, rifle=true, pistol=true, health=4.6, accuracy=1.7, femaleChance=10}
}

local function bl_hash(value)
    local text = tostring(value or "")
    local h = 0
    for i=1, #text do
        h = (h + string.byte(text, i) * i) % 7919
    end
    return h
end

local function bl_pick(list, seed)
    if type(list) ~= "table" or #list <= 0 then return nil end
    local idx = (math.abs(tonumber(seed) or 0) % #list) + 1
    return list[idx]
end

local function bl_copyWeapon(weapon)
    if type(weapon) ~= "table" then return weapon end
    if NPCWeaponsBridge and NPCWeaponsBridge.Copy then
        local ok, copied = pcall(function() return NPCWeaponsBridge.Copy(weapon) end)
        if ok and copied then return copied end
    end
    local copied = {}
    for k, v in pairs(weapon) do copied[k] = v end
    return copied
end

local function bl_pickWeapon(pool, seed)
    if type(pool) ~= "table" or #pool <= 0 then return nil end
    return bl_copyWeapon(pool[(math.abs(tonumber(seed) or 0) % #pool) + 1])
end

local function bl_primaryPool()
    if NPCWeaponsBridge and NPCWeaponsBridge.GetSpawnPrimary then
        local ok, pool = pcall(function() return NPCWeaponsBridge.GetSpawnPrimary(nil) end)
        if ok and type(pool) == "table" then return pool end
    end
    return NPCWeaponsBridge and NPCWeaponsBridge.Primary or nil
end

local function bl_secondaryPool()
    if NPCWeaponsBridge and NPCWeaponsBridge.GetSpawnSecondary then
        local ok, pool = pcall(function() return NPCWeaponsBridge.GetSpawnSecondary(nil) end)
        if ok and type(pool) == "table" then return pool end
    end
    return NPCWeaponsBridge and NPCWeaponsBridge.Secondary or nil
end

function NPCLeadersBridge.LeaderArchetype(leader)
    local seed = bl_hash((leader and leader.id or "") .. ":" .. tostring(leader and leader.side or "") .. ":" .. tostring(leader and leader.kind or ""))
    local archetype = BL_LEADER_ARCHETYPES[(seed % #BL_LEADER_ARCHETYPES) + 1]
    if leader and leader.kind == "base_commander" then
        if leader.side == "green" or leader.side == "blue" then archetype = BL_LEADER_ARCHETYPES[1] end
        if leader.side == "red" and seed % 2 == 0 then archetype = BL_LEADER_ARCHETYPES[3] end
    end
    return archetype, seed
end


function NPCLeadersBridge.ApplyLeaderSquadIdentityToMember(member, leader, index)
    if type(member) ~= "table" or not leader then return member end
    local archetype, seed = NPCLeadersBridge.LeaderArchetype(leader)
    archetype = archetype or BL_LEADER_ARCHETYPES[1]
    seed = seed + (tonumber(index) or 1) * 29

    member.role = member.role or "base_guard"
    member.tacticalRole = member.tacticalRole == "leader" and "bodyguard" or (member.tacticalRole or "bodyguard")
    member.leaderEscort = true
    member.leaderArchetype = archetype.id
    member.factionSide = leader.side or member.factionSide
    member.faction = leader.side or member.faction
    member.side = leader.side or member.side
    member.patrolColor = leader.side or member.patrolColor
    member.health = math.max(tonumber(member.health) or 3.0, math.max(3.8, (tonumber(archetype.health) or 4.3) - 0.2))
    member.maxHealth = member.health
    member.accuracyBoost = math.max(tonumber(member.accuracyBoost) or 1, math.max(1.2, (tonumber(archetype.accuracy) or 1.45) - 0.12))
    member.femaleChance = tonumber(archetype.femaleChance) or member.femaleChance or 10
    member.outfit = bl_pick(archetype.outfits, seed) or member.outfit or "Veteran"
    member.weapons = type(member.weapons) == "table" and member.weapons or {}
    member.weapons.melee = bl_pick(archetype.melee, seed + 3) or member.weapons.melee or "Base.Machete"

    if archetype.rifle then
        local primary = bl_pickWeapon(bl_primaryPool(), seed + 11)
        if type(primary) == "table" then
            primary.magCount = math.max(tonumber(primary.magCount) or 0, 2)
            member.weapons.primary = primary
        end
    end
    if archetype.pistol then
        local secondary = bl_pickWeapon(bl_secondaryPool(), seed + 23)
        if type(secondary) == "table" then
            secondary.magCount = math.max(tonumber(secondary.magCount) or 0, 2)
            member.weapons.secondary = secondary
        end
    end

    member.preferCover = true
    member.baseElite = true
    return member
end

function NPCLeadersBridge.ApplyLeaderIdentityToMember(member, leader, index)
    if type(member) ~= "table" or not leader then return member end
    local archetype, seed = NPCLeadersBridge.LeaderArchetype(leader)
    archetype = archetype or BL_LEADER_ARCHETYPES[1]
    seed = seed + (tonumber(index) or 1) * 17
    leader.leaderArchetype = leader.leaderArchetype or archetype.id

    NPCLeadersBridge.MarkBrainAsLeader(member, leader)
    member.role = "leader"
    member.tacticalRole = "leader"
    member.leaderArchetype = archetype.id
    member.factionSide = leader.side or member.factionSide
    member.faction = leader.side or member.faction
    member.side = leader.side or member.side
    member.patrolColor = leader.side or member.patrolColor
    member.health = math.max(tonumber(member.health) or 3.0, tonumber(archetype.health) or 4.3)
    member.maxHealth = member.health
    member.accuracyBoost = math.max(tonumber(member.accuracyBoost) or 1, tonumber(archetype.accuracy) or 1.45)
    member.femaleChance = tonumber(archetype.femaleChance) or member.femaleChance or 10
    member.outfit = bl_pick(archetype.outfits, seed) or member.outfit or "Veteran"
    member.weapons = type(member.weapons) == "table" and member.weapons or {}
    member.weapons.melee = bl_pick(archetype.melee, seed + 3) or member.weapons.melee or "Base.Machete"

    if archetype.rifle then
        local primary = bl_pickWeapon(bl_primaryPool(), seed + 11)
        if type(primary) == "table" then
            primary.magCount = math.max(tonumber(primary.magCount) or 0, 2)
            member.weapons.primary = primary
        end
    end
    if archetype.pistol then
        local secondary = bl_pickWeapon(bl_secondaryPool(), seed + 23)
        if type(secondary) == "table" then
            secondary.magCount = math.max(tonumber(secondary.magCount) or 0, 3)
            member.weapons.secondary = secondary
        end
    end

    member.leaderPriorityTarget = true
    member.preferCover = true
    member.commandAura = true
    return member
end

function NPCLeadersBridge.MakeLeader(gmd, kind, side, x, y, z, ownerId, ownerName)
    local data = NPCLeadersBridge.EnsureData(gmd)
    side = bl_side(side)
    if not data or not side then return nil end
    local id = bl_nextId(data, kind)
    local leader = {
        id = id,
        kind = tostring(kind or "leader"),
        side = side,
        factionSide = side,
        title = bl_title(kind),
        name = bl_name(side, kind, id),
        x = math.floor(tonumber(x) or 0),
        y = math.floor(tonumber(y) or 0),
        z = tonumber(z) or 0,
        ownerId = ownerId,
        ownerName = ownerName,
        state = "active",
        influence = 100,
        createdAt = bl_now(),
        updatedAt = bl_now()
    }
    data.leaders[id] = leader
    data.bySide[side] = data.bySide[side] or {}
    data.bySide[side][id] = true
    if data.stats then data.stats.created = (tonumber(data.stats.created) or 0) + 1 end
    return leader
end

function NPCLeadersBridge.ApplyBaseFields(base, leader)
    if not base then return end
    if leader then
        base.commanderId = leader.id
        base.commanderName = leader.name
        base.commanderSide = leader.side
        base.commanderState = bl_state(leader)
        base.commanderInfluence = leader.influence or 100
        base.commanderUpdatedAt = leader.updatedAt or bl_now()
    else
        base.commanderId = nil
        base.commanderName = nil
        base.commanderSide = nil
        base.commanderState = nil
        base.commanderInfluence = nil
    end
end

function NPCLeadersBridge.EnsureBaseCommander(gmd, base)
    if not (NPCLeadersBridge.IsEnabled() and NPCLeadersBridge.BaseCommandersEnabled()) then return nil end
    local data = NPCLeadersBridge.EnsureData(gmd)
    if not (data and base and base.id and base.x and base.y) then return nil end
    local side = bl_side(base.owner or base.captureTeam or base.factionSide or base.side)
    if not side then return nil end

    local existingId = data.byBase[tostring(base.id)] or base.commanderId
    local existing = existingId and data.leaders[tostring(existingId)] or nil
    if existing and NPCLeadersBridge.IsLeaderAlive(existing) and bl_side(existing.side) == side then
        existing.x = math.floor(tonumber(base.x) or existing.x or 0)
        existing.y = math.floor(tonumber(base.y) or existing.y or 0)
        existing.z = tonumber(base.z) or existing.z or 0
        existing.ownerId = tostring(base.id)
        existing.ownerName = base.name
        existing.updatedAt = bl_now()
        data.byBase[tostring(base.id)] = existing.id
        NPCLeadersBridge.ApplyBaseFields(base, existing)
        return existing
    end

    if existing and not NPCLeadersBridge.IsLeaderAlive(existing) then
        local deadAt = tonumber(existing.deadAt or existing.updatedAt or bl_now()) or bl_now()
        if bl_now() - deadAt < NPCLeadersBridge.ReplacementHours() then
            NPCLeadersBridge.ApplyBaseFields(base, existing)
            return existing
        end
    end

    local leader = NPCLeadersBridge.MakeLeader(gmd, "base_commander", side, base.x, base.y, base.z or 0, tostring(base.id), base.name)
    if not leader then return nil end
    leader.baseId = tostring(base.id)
    data.byBase[tostring(base.id)] = leader.id
    if data.stats then
        data.stats.bases = (tonumber(data.stats.bases) or 0) + 1
        if existing then data.stats.replaced = (tonumber(data.stats.replaced) or 0) + 1 end
    end
    NPCLeadersBridge.ApplyBaseFields(base, leader)
    return leader
end

function NPCLeadersBridge.MarkBrainAsLeader(brain, leader)
    if not (brain and leader) then return brain end
    brain.leader = true
    brain.isFactionLeader = true
    brain.leaderId = leader.id
    brain.leaderName = leader.name
    brain.leaderRole = leader.kind
    brain.leaderTitle = leader.title
    brain.leaderSide = leader.side
    brain.leaderState = bl_state(leader)
    brain.leaderInfluence = leader.influence or 100
    return brain
end

function NPCLeadersBridge.EnsureGroupLeader(gmd, group, groupId)
    if not (NPCLeadersBridge.IsEnabled() and NPCLeadersBridge.SquadLeadersEnabled()) then return nil end
    local data = NPCLeadersBridge.EnsureData(gmd)
    if not (data and group) then return nil end
    groupId = tostring(groupId or group.id or "")
    if groupId == "" then return nil end
    local side = bl_side(group.factionSide or group.side or group.patrolColor or group.faction)
    if not side then return nil end

    local leaderId = data.byGroup[groupId] or group.leaderId
    local leader = leaderId and data.leaders[tostring(leaderId)] or nil
    if not (leader and NPCLeadersBridge.IsLeaderAlive(leader)) then
        leader = NPCLeadersBridge.MakeLeader(gmd, "squad_leader", side, group.x, group.y, group.z or 0, groupId, group.name)
        if not leader then return nil end
        leader.groupId = groupId
        data.byGroup[groupId] = leader.id
        if data.stats then data.stats.groups = (tonumber(data.stats.groups) or 0) + 1 end
    end

    leader.x = math.floor(tonumber(group.x) or leader.x or 0)
    leader.y = math.floor(tonumber(group.y) or leader.y or 0)
    leader.z = tonumber(group.z) or leader.z or 0
    leader.side = side
    leader.factionSide = side
    leader.updatedAt = bl_now()

    group.leader = true
    group.leaderId = leader.id
    group.leaderName = leader.name
    group.leaderRole = leader.kind
    group.leaderSide = leader.side
    group.leaderState = bl_state(leader)
    group.leaderInfluence = leader.influence or 100

    if type(group.members) == "table" then
        local first = group.members[1]
        if type(first) == "table" then
            NPCLeadersBridge.ApplyLeaderIdentityToMember(first, leader, 1)
        end
    end
    return leader
end

function NPCLeadersBridge.ApplyBaseDeathPenalty(base)
    if not base then return false end
    local now = bl_now()
    local cooldown = NPCWorldRules and NPCWorldRules.LeaderPenaltyCooldownHours and NPCWorldRules.LeaderPenaltyCooldownHours() or 0
    if cooldown > 0 and tonumber(base.lastCommanderDeathPenaltyAt or 0) > 0 and now - tonumber(base.lastCommanderDeathPenaltyAt) < cooldown then
        base.commanderState = "dead"
        base.commanderDeadAt = now
        base.leaderCrisisUntil = now + NPCLeadersBridge.ReplacementHours()
        base.commanderPenaltySkipped = true
        base.commanderPenaltyReason = "cooldown"
        base.updatedAt = now
        return false
    end

    local penalty = NPCLeadersBridge.BaseDeathReadinessPenalty()
    local moralePenalty = NPCLeadersBridge.BaseDeathMoralePenalty()
    local names = {"garrisonReadiness", "defenseReadiness", "logisticsReadiness", "medicalReadiness", "foodReadiness", "ammoReadiness"}
    for _, name in ipairs(names) do
        if base[name] ~= nil then base[name] = bl_clamp((tonumber(base[name]) or 0) - penalty, 0, 100) end
    end
    base.commanderState = "dead"
    base.commanderDeadAt = now
    base.leaderCrisisUntil = now + NPCLeadersBridge.ReplacementHours()
    base.leaderMoralePenalty = moralePenalty
    base.zoneNeedSummary = "commander_down"
    base.lastCommanderDeathPenaltyAt = now
    base.commanderPenaltySkipped = nil
    base.commanderPenaltyReason = nil
    if type(base.zones) == "table" then
        for _, zone in pairs(base.zones) do
            if type(zone) == "table" and zone.readiness ~= nil then
                zone.readiness = bl_clamp((tonumber(zone.readiness) or 0) - math.floor(penalty * 0.5), 0, 100)
            end
        end
    end
    return true
end

function NPCLeadersBridge.MarkLeaderKilled(gmd, player, args)
    local data = NPCLeadersBridge.EnsureData(gmd)
    if not data then return nil end
    args = args or {}
    local leaderId = args.leaderId or args.victimLeaderId
    local leader = leaderId and data.leaders[tostring(leaderId)] or nil
    if not leader and args.baseId and data.byBase[tostring(args.baseId)] then leader = data.leaders[tostring(data.byBase[tostring(args.baseId)])] end
    if not leader and args.groupId and data.byGroup[tostring(args.groupId)] then leader = data.leaders[tostring(data.byGroup[tostring(args.groupId)])] end
    if not leader then return nil end
    if leader.dead == true or leader.state == "dead" then return leader end

    leader.dead = true
    leader.state = "dead"
    leader.deadAt = bl_now()
    leader.updatedAt = bl_now()
    leader.killedByPlayerId = args.playerId
    leader.killedByPlayerName = args.playerName
    leader.killerX = tonumber(args.x)
    leader.killerY = tonumber(args.y)
    leader.reason = "killed"
    data.history[#data.history + 1] = {leaderId=leader.id, side=leader.side, kind=leader.kind, event="killed", at=leader.deadAt, playerName=args.playerName}
    if #data.history > 60 then table.remove(data.history, 1) end
    if data.stats then data.stats.killed = (tonumber(data.stats.killed) or 0) + 1 end

    if leader.baseId and gmd.BaseCamps and gmd.BaseCamps[tostring(leader.baseId)] then
        local base = gmd.BaseCamps[tostring(leader.baseId)]
        NPCLeadersBridge.ApplyBaseDeathPenalty(base)
        NPCLeadersBridge.ApplyBaseFields(base, leader)
    end
    if leader.groupId and gmd.VirtualGroups and gmd.VirtualGroups[tostring(leader.groupId)] then
        local group = gmd.VirtualGroups[tostring(leader.groupId)]
        group.leaderState = "dead"
        group.leaderDeadAt = leader.deadAt
        group.leaderInfluence = 0
        gmd.VirtualGroups[tostring(leader.groupId)] = group
    end
    return leader
end

function NPCLeadersBridge.MakeLeaderMarker(leader)
    if not leader then return nil end
    return {
        id = "leader_" .. tostring(leader.id),
        markerType = "leader",
        x = leader.x,
        y = leader.y,
        z = leader.z or 0,
        name = leader.name,
        leader = true,
        isFactionLeader = true,
        leaderId = leader.id,
        leaderName = leader.name,
        leaderRole = leader.kind,
        leaderTitle = leader.title,
        leaderSide = leader.side,
        leaderState = bl_state(leader),
        leaderInfluence = leader.influence or 0,
        leaderArchetype = leader.leaderArchetype,
        factionSide = leader.side,
        faction = leader.side,
        side = leader.side,
        baseId = leader.baseId,
        groupId = leader.groupId,
        dead = leader.dead == true,
        updatedAt = leader.updatedAt or bl_now()
    }
end

function NPCLeadersBridge.MarkerFields(marker, subject)
    if not (marker and subject) then return marker end
    if subject.commanderId then
        marker.commanderId = subject.commanderId
        marker.commanderName = subject.commanderName
        marker.commanderSide = subject.commanderSide
        marker.commanderState = subject.commanderState
        marker.commanderInfluence = subject.commanderInfluence
    end
    if subject.leader or subject.isFactionLeader or subject.leaderId then
        marker.leader = true
        marker.isFactionLeader = subject.isFactionLeader == true or subject.leader == true
        marker.leaderId = subject.leaderId
        marker.leaderName = subject.leaderName
        marker.leaderRole = subject.leaderRole
        marker.leaderTitle = subject.leaderTitle
        marker.leaderSide = subject.leaderSide or subject.factionSide or subject.side
        marker.leaderState = subject.leaderState or "active"
        marker.leaderInfluence = subject.leaderInfluence or 100
        marker.leaderArchetype = subject.leaderArchetype
    end
    return marker
end

function NPCLeadersBridge.BuildStatusPayload(gmd)
    local data = NPCLeadersBridge.EnsureData(gmd)
    local payload = {bySide={}, text="No faction leaders tracked."}
    if not data or type(data.leaders) ~= "table" then return payload end
    local parts = {}
    for _, leader in pairs(data.leaders) do
        if type(leader) == "table" then
            local side = bl_side(leader.side) or "unknown"
            payload.bySide[side] = payload.bySide[side] or {active=0, dead=0, base=0, squad=0}
            if NPCLeadersBridge.IsLeaderAlive(leader) then payload.bySide[side].active = payload.bySide[side].active + 1 else payload.bySide[side].dead = payload.bySide[side].dead + 1 end
            if leader.kind == "base_commander" then payload.bySide[side].base = payload.bySide[side].base + 1 end
            if leader.kind == "squad_leader" then payload.bySide[side].squad = payload.bySide[side].squad + 1 end
        end
    end
    for _, side in ipairs(BL_SIDES) do
        local r = payload.bySide[side]
        if r and (r.active > 0 or r.dead > 0) then
            parts[#parts + 1] = bl_sideLabel(side) .. " leaders " .. tostring(r.active) .. " active / " .. tostring(r.dead) .. " dead"
        end
    end
    if #parts > 0 then payload.text = table.concat(parts, " | ") end
    payload.updatedAt = bl_now()
    return payload
end

function NPCLeadersBridge.GetRadioCandidates(gmd)
    local data = NPCLeadersBridge.EnsureData(gmd)
    local out = {}
    if not data or type(data.leaders) ~= "table" then return out end
    for _, leader in pairs(data.leaders) do
        if type(leader) == "table" and leader.x and leader.y then
            local state = bl_state(leader)
            local text
            if state == "dead" then
                text = bl_sideLabel(leader.side) .. " command traffic: " .. tostring(leader.name or "leader") .. " is down. Units reporting command disruption near " .. tostring(math.floor(tonumber(leader.x) or 0)) .. "," .. tostring(math.floor(tonumber(leader.y) or 0)) .. "."
            else
                text = bl_sideLabel(leader.side) .. " command traffic: " .. tostring(leader.name or "leader") .. " coordinating " .. tostring(leader.kind or "forces") .. " near " .. tostring(math.floor(tonumber(leader.x) or 0)) .. "," .. tostring(math.floor(tonumber(leader.y) or 0)) .. "."
            end
            out[#out + 1] = {kind="leader", side=leader.side, x=leader.x, y=leader.y, text=text, weight=NPCLeadersBridge.RadioWeight(), data=leader}
        end
    end
    return out
end
