-- NPCTacticalRadioBridge.lua
-- Neutral squad communication and tactical maneuver layer for NPC runtime.
--
-- Safety contract:
-- 1. Does not replace legacy Shoot/Hit/Reload code.
-- 2. Does not force pathToCharacter or direct target assignment.
-- 3. Works as a low-risk tactical coordinator: shared contacts, squad roles,
--    fire discipline, cover/overwatch/flank movement hints.

require "NPCCore/NPCTacticalCoverBridge"

NPCTacticalRadioBridge = NPCTacticalRadioBridge or {}
NPCTacticalRadioBridge.VERSION = "2026-05-03-squad-dynamics"

NPCTacticalRadioBridge.Config = NPCTacticalRadioBridge.Config or {
    enabled = true,
    contactMemorySeconds = 55,
    reportCooldownMs = 750,
    maneuverCooldownMs = 3600,
    fireDeferCooldownMs = 2800,
    fireDeferMs = 1500,
    roleReassignMs = 16000,
    reservationSeconds = 9,
    shareRange = 88,
    closeDanger = 5.5,
    flankStartDistance = 7.5,
    flankMaxDistance = 42,
    flankSideDistance = 9.0,
    flankBackDistance = 11.0,
    coverDistance = 6.5,
    coverSearchRadius = 7,
    overwatchDistance = 16.0,
    assaultAdvanceDistance = 4.0,
    friendlyFireCorridor = 0.92,
    friendlyFireMaxRange = 34,
    minSquadForFlank = 2,
    maxContactsPerChannel = 8,
    maxSquadSharedContacts = 5,
    stuckManeuverRetryMs = 1400,
    flankEnabled = true,
    friendlyFireCheck = true,
    coverEnabled = true,
    coverSearchRadius2 = 8
}

if NPCLegacySettingsBridge and NPCLegacySettingsBridge.ApplyTacticalRadio then
    NPCLegacySettingsBridge.ApplyTacticalRadio(NPCTacticalRadioBridge)
end

local tacticalCoverProvider = NPCTacticalCoverBridge and NPCTacticalCoverBridge.Resolve and NPCTacticalCoverBridge.Resolve() or nil
if tacticalCoverProvider and tacticalCoverProvider.Config and NPCTacticalRadioBridge.Config then
    tacticalCoverProvider.Config.enabled = NPCTacticalRadioBridge.Config.enabled ~= false and NPCTacticalRadioBridge.Config.coverEnabled ~= false
    tacticalCoverProvider.Config.searchRadius = NPCTacticalRadioBridge.Config.coverSearchRadius2 or NPCTacticalRadioBridge.Config.coverSearchRadius or tacticalCoverProvider.Config.searchRadius
    tacticalCoverProvider.Config.closeDanger = NPCTacticalRadioBridge.Config.closeDanger or tacticalCoverProvider.Config.closeDanger
    tacticalCoverProvider.Config.flankSideDistance = NPCTacticalRadioBridge.Config.flankSideDistance or tacticalCoverProvider.Config.flankSideDistance
    tacticalCoverProvider.Config.flankBackDistance = NPCTacticalRadioBridge.Config.flankBackDistance or tacticalCoverProvider.Config.flankBackDistance
    tacticalCoverProvider.Config.coverDistance = NPCTacticalRadioBridge.Config.coverDistance or tacticalCoverProvider.Config.coverDistance
    tacticalCoverProvider.Config.overwatchDistance = NPCTacticalRadioBridge.Config.overwatchDistance or tacticalCoverProvider.Config.overwatchDistance
    tacticalCoverProvider.Config.friendlyFireCorridor = NPCTacticalRadioBridge.Config.friendlyFireCorridor or tacticalCoverProvider.Config.friendlyFireCorridor
    tacticalCoverProvider.Config.friendlyFireMaxRange = NPCTacticalRadioBridge.Config.friendlyFireMaxRange or tacticalCoverProvider.Config.friendlyFireMaxRange
end

NPCTacticalRadioBridge.Channels = NPCTacticalRadioBridge.Channels or {}
NPCTacticalRadioBridge.Reservations = NPCTacticalRadioBridge.Reservations or {}

local function btr_nowMs()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then return math.floor((getGameTime():getWorldAgeHours() or 0) * 3600000) end
    return 0
end

local function btr_nowHours()
    if getGameTime then return getGameTime():getWorldAgeHours() or 0 end
    return 0
end

local function btr_clamp(v, minv, maxv)
    v = tonumber(v)
    if v == nil then return minv end
    if v < minv then return minv end
    if v > maxv then return maxv end
    return v
end

local function btr_dist2(x1, y1, x2, y2)
    local dx = (x1 or 0) - (x2 or 0)
    local dy = (y1 or 0) - (y2 or 0)
    return dx * dx + dy * dy
end

local function btr_dist(x1, y1, x2, y2)
    return math.sqrt(btr_dist2(x1, y1, x2, y2))
end

local function btr_id(chr)
    if not chr then return nil end
    if NPCUtils and NPCUtils.GetCharacterID then
        local ok, id = pcall(function() return NPCUtils.GetCharacterID(chr) end)
        if ok and id then return tostring(id) end
    end
    if NPCUtils and NPCUtils.GetZombieID then
        local ok, id = pcall(function() return NPCUtils.GetZombieID(chr) end)
        if ok and id then return tostring(id) end
    end
    return tostring(chr)
end

local function btr_getBrain(chr)
    if not chr or not NPCBrainData or not NPCBrainData.Get then return nil end
    local ok, brain = pcall(function() return NPCBrainData.Get(chr) end)
    if ok then return brain end
    return nil
end

local function btr_isAlive(chr)
    if not chr then return false end
    local ok, dead = pcall(function() return chr:isDead() end)
    if ok and dead then return false end
    ok, dead = pcall(function() return chr:isAlive() end)
    if ok and dead == false then return false end
    return true
end

local function btr_kindIsHuman(kind)
    kind = tostring(kind or ""):lower()
    return kind == "bandit" or kind == "player" or kind == "survivor" or kind == "npc" or kind == "human"
end

local function btr_bool(v)
    return v == true or v == 1 or v == "true"
end

function NPCTacticalRadioBridge.GroupKey(brain)
    if not brain then return "nogroup" end
    if brain.worldGroupId then return "wg:" .. tostring(brain.worldGroupId) end
    if brain.groupId then return "wg:" .. tostring(brain.groupId) end
    if brain.physicalGroupId then return "pg:" .. tostring(brain.physicalGroupId) end
    if brain.encounterId and brain.patrolColor then return "enc:" .. tostring(brain.encounterId) .. ":" .. tostring(brain.patrolColor) end
    if brain.patrolColor then return "patrol:" .. tostring(brain.patrolColor) .. ":" .. tostring(brain.clan or 0) end
    return "clan:" .. tostring(brain.clan or 0) .. ":" .. tostring(brain.hostile and 1 or 0)
end

function NPCTacticalRadioBridge.Ensure(brain)
    if not brain then return nil end
    brain.radio = brain.radio or {}
    brain.radio.enabled = brain.radio.enabled ~= false
    brain.radio.role = brain.radio.role or nil
    brain.radio.lastSharedThreat = brain.radio.lastSharedThreat or nil
    return brain.radio
end

local function btr_channel(key)
    key = key or "nogroup"
    local ch = NPCTacticalRadioBridge.Channels[key]
    if not ch then
        ch = {contacts={}, createdAt=btr_nowMs(), rev=0, plan={}, members={}}
        NPCTacticalRadioBridge.Channels[key] = ch
    end
    ch.contacts = ch.contacts or {}
    ch.members = ch.members or {}
    ch.plan = ch.plan or {}
    return ch
end

local function btr_isSameSquad(a, b)
    if not a or not b then return false end
    if a.worldGroupId and b.worldGroupId and tostring(a.worldGroupId) == tostring(b.worldGroupId) then return true end
    if a.groupId and b.groupId and tostring(a.groupId) == tostring(b.groupId) then return true end
    if a.physicalGroupId and b.physicalGroupId and tostring(a.physicalGroupId) == tostring(b.physicalGroupId) then return true end
    if a.encounterId and b.encounterId and tostring(a.encounterId) == tostring(b.encounterId) and tostring(a.patrolColor or "") == tostring(b.patrolColor or "") then return true end
    if a.patrolColor and b.patrolColor and tostring(a.patrolColor) == tostring(b.patrolColor) and a.clan and b.clan and a.clan == b.clan then return true end
    if a.clan and b.clan and a.clan == b.clan and a.hostile == b.hostile then return true end
    return false
end

local function btr_isFriendly(brain, otherBrain)
    if NPCFactionBridge and NPCFactionBridge.IsEnabled and NPCFactionBridge.IsEnabled() and NPCFactionBridge.AreBrainsEnemies then
        if NPCFactionBridge.AreBrainsEnemies(brain, otherBrain) then return false end
    end
    return btr_isSameSquad(brain, otherBrain)
end

local function btr_memberKey(bandit, brain)
    return tostring((brain and (brain.persistentId or brain.uid or brain.id)) or btr_id(bandit) or "unknown")
end

local function btr_trimChannel(ch, now)
    if not ch or not ch.contacts then return end
    local maxAge = (NPCTacticalRadioBridge.Config.contactMemorySeconds or 55) * 1000
    local count = 0
    for id, c in pairs(ch.contacts) do
        if not c or now - (c.reportedAt or 0) > maxAge then
            ch.contacts[id] = nil
        else
            count = count + 1
        end
    end

    local maxContacts = NPCTacticalRadioBridge.Config.maxContactsPerChannel or 8
    while count > maxContacts do
        local oldestId, oldestAt
        for id, c in pairs(ch.contacts) do
            if c and (not oldestAt or (c.reportedAt or 0) < oldestAt) then
                oldestId = id
                oldestAt = c.reportedAt or 0
            end
        end
        if not oldestId then break end
        ch.contacts[oldestId] = nil
        count = count - 1
    end

    if ch.members then
        for id, m in pairs(ch.members) do
            if not m or now - (m.updatedAt or 0) > 25000 then
                ch.members[id] = nil
            end
        end
    end
end

local function btr_cleanupReservations(now)
    local maxAge = (NPCTacticalRadioBridge.Config.reservationSeconds or 9) * 1000
    for k, r in pairs(NPCTacticalRadioBridge.Reservations) do
        if not r or now - (r.at or 0) > maxAge then
            NPCTacticalRadioBridge.Reservations[k] = nil
        end
    end
end

local function btr_squareUsable(x, y, z)
    local cell = getCell()
    if not cell then return false end
    local sq = cell:getGridSquare(math.floor(x), math.floor(y), math.floor(z or 0))
    if not sq then return false end

    local ok, solid = pcall(function() return sq:isSolid() end)
    if ok and solid then return false end
    ok, solid = pcall(function() return sq:isSolidTrans() end)
    if ok and solid then return false end
    ok, solid = pcall(function()
        if IsoFlagType and IsoFlagType.water then return sq:Is(IsoFlagType.water) end
        return false
    end)
    if ok and solid then return false end
    return true
end

local function btr_squareBlocks(x, y, z)
    local cell = getCell()
    if not cell then return false end
    local sq = cell:getGridSquare(math.floor(x), math.floor(y), math.floor(z or 0))
    if not sq then return false end

    local ok, solid = pcall(function() return sq:isSolid() end)
    if ok and solid then return true end
    ok, solid = pcall(function() return sq:isSolidTrans() end)
    if ok and solid then return true end

    ok, solid = pcall(function()
        local objects = sq:getObjects()
        if not objects then return false end
        for i=0, objects:size()-1 do
            local obj = objects:get(i)
            if obj then
                local props = obj:getProperties()
                if props then
                    if IsoFlagType then
                        if IsoFlagType.solid and props:Is(IsoFlagType.solid) then return true end
                        if IsoFlagType.solidtrans and props:Is(IsoFlagType.solidtrans) then return true end
                        if IsoFlagType.collideN and props:Is(IsoFlagType.collideN) then return true end
                        if IsoFlagType.collideW and props:Is(IsoFlagType.collideW) then return true end
                    end
                    local name = tostring(obj:getSpriteName() or ""):lower()
                    if name:find("wall") or name:find("fence") or name:find("counter") or name:find("crate") or name:find("shelf") then
                        return true
                    end
                end
            end
        end
        return false
    end)
    return ok and solid == true
end

local function btr_coverScore(x, y, z, threat)
    if not threat then return 0 end
    if not btr_squareUsable(x, y, z) then return -10000 end

    local score = 0
    local tx, ty = threat.x or x, threat.y or y
    local dx = x - tx
    local dy = y - ty
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.01 then len = 1 end
    local ux, uy = dx / len, dy / len

    -- Cover is best when there is a blocking tile between candidate and threat.
    local bx = x - ux
    local by = y - uy
    if btr_squareBlocks(bx, by, z) then score = score + 8 end
    if btr_squareBlocks(x + 1, y, z) then score = score + 1 end
    if btr_squareBlocks(x - 1, y, z) then score = score + 1 end
    if btr_squareBlocks(x, y + 1, z) then score = score + 1 end
    if btr_squareBlocks(x, y - 1, z) then score = score + 1 end

    local d = btr_dist(x, y, tx, ty)
    if d < (NPCTacticalRadioBridge.Config.closeDanger or 5.5) then score = score - 10 end
    if d > (NPCTacticalRadioBridge.Config.flankMaxDistance or 42) + 8 then score = score - 4 end
    return score
end

local function btr_findBestAround(x, y, z, radius, threat, reservationKey, ownerId)
    radius = radius or 5
    local bx = math.floor(x)
    local by = math.floor(y)
    local bz = math.floor(z or 0)
    local bestX, bestY, bestZ, bestScore
    local now = btr_nowMs()
    btr_cleanupReservations(now)

    for r=0, radius do
        for dx=-r, r do
            for dy=-r, r do
                if r == 0 or math.abs(dx) == r or math.abs(dy) == r then
                    local sx = bx + dx
                    local sy = by + dy
                    if btr_squareUsable(sx, sy, bz) then
                        local reserved = false
                        if reservationKey then
                            for key, res in pairs(NPCTacticalRadioBridge.Reservations) do
                                if res and res.key == reservationKey and res.owner ~= ownerId then
                                    if btr_dist2(res.x, res.y, sx, sy) < 2.25 then
                                        reserved = true
                                        break
                                    end
                                end
                            end
                        end
                        if not reserved then
                            local score = btr_coverScore(sx, sy, bz, threat) - btr_dist(sx, sy, x, y) * 0.15
                            if not bestScore or score > bestScore then
                                bestScore = score
                                bestX, bestY, bestZ = sx, sy, bz
                            end
                        end
                    end
                end
            end
        end
    end

    return bestX, bestY, bestZ, bestScore
end

local function btr_unitFromThreat(bandit, threat)
    local bx, by = bandit:getX(), bandit:getY()
    local dx = bx - threat.x
    local dy = by - threat.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.05 then
        local id = tonumber(btr_id(bandit)) or ZombRand(1000)
        local a = (id % 628) / 100
        dx, dy, len = math.cos(a), math.sin(a), 1
    end
    return dx / len, dy / len
end

function NPCTacticalRadioBridge.CountNearbySquad(bandit, brain, radius)
    if not bandit or not brain then return 1 end
    radius = radius or NPCTacticalRadioBridge.Config.shareRange or 88
    local bx, by, bz = bandit:getX(), bandit:getY(), bandit:getZ()
    local count = 1

    local nearby = nil
    if NPCSpatialIndexBridge and NPCSpatialIndexBridge.GetNearbyNPCs then
        nearby = NPCSpatialIndexBridge.GetNearbyNPCs(bx, by, bz, radius)
    elseif NPCZombieCacheBridge and NPCZombieCacheBridge.CacheLightB then
        nearby = NPCZombieCacheBridge.CacheLightB
    end
    if not nearby then return count end

    local myId = btr_id(bandit)
    for _, data in pairs(nearby) do
        if data and data.brain and tostring(data.id or "") ~= tostring(myId or "") then
            if data.z == bz and btr_isFriendly(brain, data.brain) and btr_dist(bx, by, data.x, data.y) <= radius then
                count = count + 1
            end
        end
    end
    return count
end

function NPCTacticalRadioBridge.Role(bandit, brain)
    local radio = NPCTacticalRadioBridge.Ensure(brain)
    if not radio then return "assault" end

    local now = btr_nowMs()
    if radio.role and now - (radio.roleAssignedAt or 0) < (NPCTacticalRadioBridge.Config.roleReassignMs or 16000) then
        brain.tacticalRole = radio.role
        return radio.role
    end

    local id = tonumber(btr_id(bandit)) or ZombRand(9999)
    local groupSalt = 0
    local key = NPCTacticalRadioBridge.GroupKey(brain)
    for i=1, #key do groupSalt = groupSalt + string.byte(key, i) end
    local v = (id + groupSalt) % 7

    if brain.role == "medic" then radio.role = "support"
    elseif brain.role == "sniper" then radio.role = "overwatch"
    elseif v == 0 then radio.role = "leader"
    elseif v == 1 then radio.role = "flank_left"
    elseif v == 2 then radio.role = "flank_right"
    elseif v == 3 then radio.role = "support"
    elseif v == 4 then radio.role = "overwatch"
    elseif v == 5 then radio.role = "assault"
    else radio.role = "point" end

    radio.roleAssignedAt = now
    brain.tacticalRole = radio.role
    return radio.role
end

function NPCTacticalRadioBridge.Tick(bandit, brain, uTick, threat)
    if NPCTacticalRadioBridge.Config and NPCTacticalRadioBridge.Config.enabled == false then return end
    if not bandit or not brain then return end
    local radio = NPCTacticalRadioBridge.Ensure(brain)
    if not radio or radio.enabled == false then return end

    local now = btr_nowMs()
    local groupKey = NPCTacticalRadioBridge.GroupKey(brain)
    local ch = btr_channel(groupKey)
    btr_trimChannel(ch, now)

    local id = btr_memberKey(bandit, brain)
    local role = NPCTacticalRadioBridge.Role(bandit, brain)
    ch.members[id] = {
        id = id,
        x = bandit:getX(),
        y = bandit:getY(),
        z = bandit:getZ(),
        role = role,
        hp = brain.fsm and brain.fsm.health or nil,
        updatedAt = now
    }

    radio.squadCount = NPCTacticalRadioBridge.CountNearbySquad(bandit, brain, NPCTacticalRadioBridge.Config.shareRange or 88)
    radio.groupKey = groupKey
    if threat and btr_kindIsHuman(threat.kind) then
        radio.lastDirectThreat = threat
    end
end

function NPCTacticalRadioBridge.ReportContact(bandit, brain, enemy, kind, dist, confidence)
    if NPCTacticalRadioBridge.Config and NPCTacticalRadioBridge.Config.enabled == false then return false end
    if not bandit or not brain or not enemy then return false end
    if not btr_isAlive(enemy) then return false end

    local radio = NPCTacticalRadioBridge.Ensure(brain)
    if not radio or radio.enabled == false or brain.radioSilent then return false end

    kind = tostring(kind or "unknown"):lower()
    local humanContact = btr_kindIsHuman(kind)
    if kind == "zombie" then humanContact = false end
    if not humanContact and kind ~= "zombie" then kind = "unknown" end

    local now = btr_nowMs()
    local enemyId = btr_id(enemy) or "unknown"
    radio.lastReportAt = radio.lastReportAt or {}
    local reportKey = tostring(enemyId) .. ":" .. kind
    if now - (radio.lastReportAt[reportKey] or 0) < (NPCTacticalRadioBridge.Config.reportCooldownMs or 750) then
        return false
    end
    radio.lastReportAt[reportKey] = now

    local groupKey = NPCTacticalRadioBridge.GroupKey(brain)
    local ch = btr_channel(groupKey)
    btr_trimChannel(ch, now)

    local bx, by, bz = bandit:getX(), bandit:getY(), bandit:getZ()
    local ex, ey, ez = enemy:getX(), enemy:getY(), enemy:getZ()
    if NPCSpyBridge and NPCSpyBridge.DistortRadioContact then
        local ok, nx, ny, nz, confMul = pcall(function() return NPCSpyBridge.DistortRadioContact(brain, ex, ey, ez, kind) end)
        if ok and nx and ny then
            ex, ey, ez = nx, ny, nz or ez
            confidence = (tonumber(confidence) or 1) * (tonumber(confMul) or 1)
        end
    end
    dist = tonumber(dist) or btr_dist(bx, by, ex, ey)

    local contact = ch.contacts[enemyId] or {}
    contact.id = enemyId
    contact.kind = kind
    contact.human = humanContact
    contact.x = ex
    contact.y = ey
    contact.z = ez
    contact.dist = dist
    contact.reportedAt = now
    contact.reportedAtHours = btr_nowHours()
    contact.sourceId = btr_id(bandit)
    contact.sourceX = bx
    contact.sourceY = by
    contact.sourceZ = bz
    contact.confidence = btr_clamp(confidence or (humanContact and 1.0 or 0.45), 0, 1)
    contact.groupKey = groupKey
    contact.reportCount = (contact.reportCount or 0) + 1
    contact.enemyGroupId = nil

    local enemyBrain = btr_getBrain(enemy)
    if enemyBrain then
        contact.enemyGroupId = enemyBrain.worldGroupId or enemyBrain.groupId or enemyBrain.physicalGroupId
        contact.enemyClan = enemyBrain.clan
        contact.enemyPatrolColor = enemyBrain.patrolColor
    end

    ch.contacts[enemyId] = contact
    ch.lastContact = contact
    ch.rev = (ch.rev or 0) + 1
    ch.updatedAt = now

    radio.lastContact = contact
    brain.lastKnownEnemyPosition = {x=ex, y=ey, z=ez, kind=kind, source="radio_report", updated=btr_nowHours()}

    if NPCUtilityAIBridge and NPCUtilityAIBridge.RememberThreat then
        pcall(function()
            NPCUtilityAIBridge.RememberThreat(brain, {
                id=enemyId, x=ex, y=ey, z=ez, kind=kind, dist=dist, score=contact.confidence
            })
        end)
    end

    if humanContact then
        brain.inBattle = true
        brain.virtualBattle = true
        ch.plan.currentEnemyId = enemyId
        ch.plan.enemyX = ex
        ch.plan.enemyY = ey
        ch.plan.enemyZ = ez
        ch.plan.updatedAt = now

        if NPCSquadDynamicsBridge and NPCSquadDynamicsBridge.Tick then
            pcall(function()
                NPCSquadDynamicsBridge.Tick(bandit, brain, nil, {
                    id = enemyId, x = ex, y = ey, z = ez, kind = kind, dist = dist, target = enemy, confidence = contact.confidence
                })
            end)
        end
    end

    return true
end

function NPCTacticalRadioBridge.GetSharedThreat(bandit, brain, maxDist)
    if NPCTacticalRadioBridge.Config and NPCTacticalRadioBridge.Config.enabled == false then return nil end
    if not bandit or not brain then return nil end
    local radio = NPCTacticalRadioBridge.Ensure(brain)
    if not radio or radio.enabled == false or brain.radioSilent then return nil end

    local groupKey = NPCTacticalRadioBridge.GroupKey(brain)
    local ch = NPCTacticalRadioBridge.Channels[groupKey]
    if not ch or not ch.contacts then return nil end

    local now = btr_nowMs()
    btr_trimChannel(ch, now)

    local bx, by, bz = bandit:getX(), bandit:getY(), bandit:getZ()
    local myId = btr_id(bandit)
    maxDist = tonumber(maxDist or 48) or 48
    local best, bestScore
    local maxShared = NPCTacticalRadioBridge.Config.maxSquadSharedContacts or 5
    local considered = 0

    for id, c in pairs(ch.contacts) do
        if c and c.x and c.y and c.z == bz and c.sourceId ~= myId then
            local ageMs = now - (c.reportedAt or 0)
            local ageSec = ageMs / 1000
            local memory = NPCTacticalRadioBridge.Config.contactMemorySeconds or 55
            if ageSec <= memory then
                local d = btr_dist(bx, by, c.x, c.y)
                local sourceDist = btr_dist(bx, by, c.sourceX or c.x, c.sourceY or c.y)
                -- No map-wide telepathy: squad members only receive a report if they are
                -- close enough to the reporting ally or already close enough to the contact area.
                if d <= maxDist and (sourceDist <= (NPCTacticalRadioBridge.Config.shareRange or 88) or d <= 22) then
                    considered = considered + 1
                    local score = (c.confidence or 0.5) * (1 - (ageSec / memory)) + (1 / math.max(1, d))
                    if c.human then score = score + 0.25 end
                    if ch.plan and ch.plan.currentEnemyId and tostring(ch.plan.currentEnemyId) == tostring(c.id) then score = score + 0.08 end
                    if not bestScore or score > bestScore then
                        bestScore = score
                        best = {
                            id = c.id,
                            x = c.x,
                            y = c.y,
                            z = c.z,
                            dist = d,
                            kind = c.kind or "unknown",
                            radio = true,
                            confidence = c.confidence or 0.5,
                            reportedAge = ageSec,
                            sourceId = c.sourceId,
                            sourceX = c.sourceX,
                            sourceY = c.sourceY,
                            sourceZ = c.sourceZ,
                            groupKey = groupKey,
                            enemyGroupId = c.enemyGroupId,
                            target = nil
                        }
                    end
                    if considered >= maxShared then break end
                end
            end
        end
    end

    if best then
        radio.lastSharedThreat = best
        brain.radioThreat = best
        brain.lastKnownEnemyPosition = {x=best.x, y=best.y, z=best.z, kind=best.kind, source="radio", updated=btr_nowHours()}
    end

    return best
end

local function btr_makeThreatFromEnemy(bandit, enemy, kind, dist)
    if not bandit or not enemy then return nil end
    return {
        id = btr_id(enemy),
        x = enemy:getX(),
        y = enemy:getY(),
        z = enemy:getZ(),
        dist = dist or btr_dist(bandit:getX(), bandit:getY(), enemy:getX(), enemy:getY()),
        kind = kind or "bandit",
        radio = false,
        target = enemy,
        confidence = 1.0
    }
end

function NPCTacticalRadioBridge.GetManeuverPoint(bandit, brain, threat)
    if not bandit or not brain or not threat or not threat.x or not threat.y then return nil end
    if NPCTacticalRadioBridge.Config and NPCTacticalRadioBridge.Config.enabled == false then return nil end
    local radio = NPCTacticalRadioBridge.Ensure(brain)
    if not radio then return nil end

    local kind = tostring(threat.kind or ""):lower()
    if not btr_kindIsHuman(kind) then return nil end

    local now = btr_nowMs()
    if now - (radio.lastManeuverAt or 0) < (NPCTacticalRadioBridge.Config.maneuverCooldownMs or 3600) then
        local retry = NPCTacticalRadioBridge.Config.stuckManeuverRetryMs or 1400
        if not (brain.fsm and brain.fsm.stuck and now - (radio.lastManeuverAt or 0) > retry) then
            return nil
        end
    end

    local dist = tonumber(threat.dist or btr_dist(bandit:getX(), bandit:getY(), threat.x, threat.y)) or 9999
    if dist < (NPCTacticalRadioBridge.Config.closeDanger or 5.5) then return nil end
    if dist > (NPCTacticalRadioBridge.Config.flankMaxDistance or 42) + 10 then return nil end

    local squadCount = radio.squadCount or NPCTacticalRadioBridge.CountNearbySquad(bandit, brain, NPCTacticalRadioBridge.Config.shareRange or 88)
    local role = NPCTacticalRadioBridge.Role(bandit, brain)
    if NPCTacticalRadioBridge.Config and NPCTacticalRadioBridge.Config.flankEnabled == false then
        if role == "flank_left" or role == "flank_right" then
            role = "assault"
        end
    end
    if squadCount < (NPCTacticalRadioBridge.Config.minSquadForFlank or 2) and (role == "flank_left" or role == "flank_right") then
        role = "assault"
    end

    local coverProvider = NPCTacticalCoverBridge and NPCTacticalCoverBridge.Resolve and NPCTacticalCoverBridge.Resolve() or nil
    if coverProvider and coverProvider.GetPoint and NPCTacticalRadioBridge.Config.coverEnabled ~= false then
        local okCover, coverPoint = pcall(function()
            return coverProvider.GetPoint(bandit, brain, threat, role)
        end)
        if okCover and coverPoint and coverPoint.x and coverPoint.y then
            radio.lastManeuverAt = now
            radio.currentManeuver = coverPoint.reason or "cover tactical move"
            radio.pendingManeuverThreat = nil
            brain.tacticalManeuver = coverPoint.reason or "cover tactical move"
            brain.tacticalRole = role
            brain.tacticalCoverScore = coverPoint.score
            return coverPoint
        end
    end

    local ux, uy = btr_unitFromThreat(bandit, threat)
    local px, py = -uy, ux
    local tx, ty, reason

    if role == "flank_left" or role == "leader" then
        tx = threat.x + ux * (NPCTacticalRadioBridge.Config.flankBackDistance or 11.0) + px * (NPCTacticalRadioBridge.Config.flankSideDistance or 9.0)
        ty = threat.y + uy * (NPCTacticalRadioBridge.Config.flankBackDistance or 11.0) + py * (NPCTacticalRadioBridge.Config.flankSideDistance or 9.0)
        reason = "radio flank left"
    elseif role == "flank_right" then
        tx = threat.x + ux * (NPCTacticalRadioBridge.Config.flankBackDistance or 11.0) - px * (NPCTacticalRadioBridge.Config.flankSideDistance or 9.0)
        ty = threat.y + uy * (NPCTacticalRadioBridge.Config.flankBackDistance or 11.0) - py * (NPCTacticalRadioBridge.Config.flankSideDistance or 9.0)
        reason = "radio flank right"
    elseif role == "support" then
        tx = bandit:getX() + ux * (NPCTacticalRadioBridge.Config.coverDistance or 6.5) + px * (((tonumber(btr_id(bandit)) or 0) % 2 == 0) and 4.0 or -4.0)
        ty = bandit:getY() + uy * (NPCTacticalRadioBridge.Config.coverDistance or 6.5) + py * (((tonumber(btr_id(bandit)) or 0) % 2 == 0) and 4.0 or -4.0)
        reason = "radio support cover"
    elseif role == "overwatch" then
        tx = threat.x + ux * (NPCTacticalRadioBridge.Config.overwatchDistance or 16.0) + px * (((tonumber(btr_id(bandit)) or 0) % 2 == 0) and 4.5 or -4.5)
        ty = threat.y + uy * (NPCTacticalRadioBridge.Config.overwatchDistance or 16.0) + py * (((tonumber(btr_id(bandit)) or 0) % 2 == 0) and 4.5 or -4.5)
        reason = "radio overwatch angle"
    elseif role == "point" then
        tx = bandit:getX() + ux * (NPCTacticalRadioBridge.Config.assaultAdvanceDistance or 4.0) + px * (((tonumber(btr_id(bandit)) or 0) % 2 == 0) and 1.5 or -1.5)
        ty = bandit:getY() + uy * (NPCTacticalRadioBridge.Config.assaultAdvanceDistance or 4.0) + py * (((tonumber(btr_id(bandit)) or 0) % 2 == 0) and 1.5 or -1.5)
        reason = "radio bound forward"
    else
        tx = bandit:getX() + ux * (NPCTacticalRadioBridge.Config.coverDistance or 6.5) + px * (((tonumber(btr_id(bandit)) or 0) % 2 == 0) and 2.0 or -2.0)
        ty = bandit:getY() + uy * (NPCTacticalRadioBridge.Config.coverDistance or 6.5) + py * (((tonumber(btr_id(bandit)) or 0) % 2 == 0) and 2.0 or -2.0)
        reason = "radio take cover"
    end

    local reservationKey = tostring(threat.id or "threat") .. ":" .. NPCTacticalRadioBridge.GroupKey(brain)
    local owner = btr_memberKey(bandit, brain)
    local fx, fy, fz = btr_findBestAround(tx, ty, threat.z or bandit:getZ(), NPCTacticalRadioBridge.Config.coverSearchRadius or 7, threat, reservationKey, owner)
    if not fx or not fy then return nil end

    radio.lastManeuverAt = now
    radio.currentManeuver = reason
    radio.pendingManeuverThreat = nil
    brain.tacticalManeuver = reason
    brain.tacticalRole = role

    NPCTacticalRadioBridge.Reservations[reservationKey .. ":" .. owner] = {key=reservationKey, owner=owner, x=fx, y=fy, z=fz or bandit:getZ(), at=now, role=role}

    return {
        x = fx,
        y = fy,
        z = fz or bandit:getZ(),
        reason = reason,
        role = role,
        threat = threat
    }
end

function NPCTacticalRadioBridge.ShouldUseManeuver(bandit, brain, threat)
    if NPCTacticalRadioBridge.Config and NPCTacticalRadioBridge.Config.enabled == false then return false end
    if not threat then return false end
    local kind = tostring(threat.kind or ""):lower()
    if not btr_kindIsHuman(kind) then return false end
    local dist = tonumber(threat.dist or 999) or 999
    if dist < (NPCTacticalRadioBridge.Config.closeDanger or 5.5) then return false end
    if dist > (NPCTacticalRadioBridge.Config.flankMaxDistance or 42) + 10 then return false end

    local radio = NPCTacticalRadioBridge.Ensure(brain)
    local squadCount = radio and radio.squadCount or NPCTacticalRadioBridge.CountNearbySquad(bandit, brain, NPCTacticalRadioBridge.Config.shareRange or 88)
    local role = NPCTacticalRadioBridge.Role(bandit, brain)
    local coverProvider = NPCTacticalCoverBridge and NPCTacticalCoverBridge.Resolve and NPCTacticalCoverBridge.Resolve() or nil
    if coverProvider and coverProvider.IsExposed and NPCTacticalRadioBridge.Config.coverEnabled ~= false then
        local okExposed, exposed = pcall(function() return coverProvider.IsExposed(bandit, threat) end)
        if okExposed and exposed and (role == "support" or role == "overwatch" or role == "assault" or role == "point") then
            return true
        end
    end
    if NPCTacticalRadioBridge.Config and NPCTacticalRadioBridge.Config.flankEnabled == false then
        return threat.radio == true and (role == "support" or role == "overwatch")
    end
    if squadCount < (NPCTacticalRadioBridge.Config.minSquadForFlank or 2) then
        return threat.radio == true and (role == "support" or role == "overwatch")
    end
    if role == "flank_left" or role == "flank_right" or role == "support" or role == "overwatch" or role == "leader" or role == "point" or threat.radio then
        return true
    end
    return false
end

function NPCTacticalRadioBridge.ChooseTacticalState(bandit, brain, threat, states)
    if not states or not NPCTacticalRadioBridge.ShouldUseManeuver(bandit, brain, threat) then return nil end
    local role = NPCTacticalRadioBridge.Role(bandit, brain)
    local dist = tonumber(threat and threat.dist or 999) or 999
    if dist < (NPCTacticalRadioBridge.Config.closeDanger or 5.5) then return nil end

    local coverProvider = NPCTacticalCoverBridge and NPCTacticalCoverBridge.Resolve and NPCTacticalCoverBridge.Resolve() or nil
    if coverProvider and coverProvider.IsExposed and NPCTacticalRadioBridge.Config.coverEnabled ~= false then
        local okExposed, exposed = pcall(function() return coverProvider.IsExposed(bandit, threat) end)
        if okExposed and exposed and (role == "support" or role == "assault") then
            return states.TacticalCover, threat.radio and "radio exposed shared contact" or "exposed to line of fire"
        end
    end

    if role == "flank_left" or role == "flank_right" or role == "leader" then
        return states.FlankEnemy, threat.radio and "radio flank shared contact" or "radio flank direct contact"
    elseif role == "support" then
        return states.SuppressEnemy or states.TacticalCover, threat.radio and "radio support shared contact" or "radio support direct contact"
    elseif role == "overwatch" then
        return states.HoldAngle or states.TacticalCover, threat.radio and "radio overwatch shared contact" or "radio overwatch direct contact"
    elseif role == "point" then
        return states.BoundForward or states.TacticalCover, threat.radio and "radio bound shared contact" or "radio bound direct contact"
    elseif threat.radio then
        return states.SearchEnemy, "radio search shared contact"
    end
    return nil
end

function NPCTacticalRadioBridge.WantsManeuverBeforeFire(bandit, brain, enemy, kind, dist)
    if NPCTacticalRadioBridge.Config and NPCTacticalRadioBridge.Config.enabled == false then return false end
    if not bandit or not brain or not enemy then return false end
    kind = tostring(kind or ""):lower()
    if not btr_kindIsHuman(kind) then return false end
    if brain.radioSilent then return false end
    if NPCTacticalRadioBridge.Config and NPCTacticalRadioBridge.Config.flankEnabled == false then return false end

    local radio = NPCTacticalRadioBridge.Ensure(brain)
    if not radio then return false end
    local now = btr_nowMs()
    if now < (radio.deferFireUntil or 0) then return false end
    if now - (radio.lastFireDeferAt or 0) < (NPCTacticalRadioBridge.Config.fireDeferCooldownMs or 2800) then return false end
    if now - (radio.lastManeuverAt or 0) < (NPCTacticalRadioBridge.Config.maneuverCooldownMs or 3600) then return false end

    local threat = btr_makeThreatFromEnemy(bandit, enemy, kind, dist)
    if not NPCTacticalRadioBridge.ShouldUseManeuver(bandit, brain, threat) then return false end

    local role = NPCTacticalRadioBridge.Role(bandit, brain)
    if NPCSquadDynamicsBridge and NPCSquadDynamicsBridge.GetRoleOverride then
        local okDyn, dynRole = pcall(function()
            return NPCSquadDynamicsBridge.GetRoleOverride(bandit, brain, threat)
        end)
        if okDyn and dynRole then
            if dynRole == "suppress" then
                return false
            end
            role = dynRole
        end
    end
    if role ~= "flank_left" and role ~= "flank_right" and role ~= "support" and role ~= "overwatch" and role ~= "leader" and role ~= "point" and role ~= "cover" then
        return false
    end

    local squadCount = radio.squadCount or NPCTacticalRadioBridge.CountNearbySquad(bandit, brain, NPCTacticalRadioBridge.Config.shareRange or 88)
    if squadCount < (NPCTacticalRadioBridge.Config.minSquadForFlank or 2) then return false end

    radio.lastFireDeferAt = now
    radio.deferFireUntil = now + (NPCTacticalRadioBridge.Config.fireDeferMs or 1500)
    radio.pendingManeuverThreat = threat
    brain.radioThreat = threat
    brain.tacticalRole = role
    brain.tacticalManeuver = "prepare " .. tostring(role)

    pcall(function()
        NPCTacticalRadioBridge.ReportContact(bandit, brain, enemy, kind, dist, 1.0)
    end)

    return true
end

function NPCTacticalRadioBridge.CanFire(bandit, brain, enemy)
    if NPCTacticalRadioBridge.Config and NPCTacticalRadioBridge.Config.friendlyFireCheck == false then return true end
    if not bandit or not enemy then return true end

    local coverProvider = NPCTacticalCoverBridge and NPCTacticalCoverBridge.Resolve and NPCTacticalCoverBridge.Resolve() or nil
    if coverProvider and coverProvider.CanFire and NPCTacticalRadioBridge.Config.coverEnabled ~= false then
        local okCover, clear = pcall(function() return coverProvider.CanFire(bandit, brain, enemy) end)
        if okCover and clear == false then return false end
    end

    if not NPCSpatialIndexBridge or not NPCSpatialIndexBridge.GetNearbyNPCs then return true end

    local bx, by, bz = bandit:getX(), bandit:getY(), bandit:getZ()
    local ex, ey, ez = enemy:getX(), enemy:getY(), enemy:getZ()
    if NPCSpyBridge and NPCSpyBridge.DistortRadioContact then
        local ok, nx, ny, nz, confMul = pcall(function() return NPCSpyBridge.DistortRadioContact(brain, ex, ey, ez, kind) end)
        if ok and nx and ny then
            ex, ey, ez = nx, ny, nz or ez
            confidence = (tonumber(confidence) or 1) * (tonumber(confMul) or 1)
        end
    end
    if bz ~= ez then return true end

    local vx = ex - bx
    local vy = ey - by
    local len2 = vx * vx + vy * vy
    if len2 < 1 then return true end
    local len = math.sqrt(len2)
    if len > (NPCTacticalRadioBridge.Config.friendlyFireMaxRange or 34) then return true end

    local nearby = NPCSpatialIndexBridge.GetNearbyNPCs(bx, by, bz, len + 2)
    local myId = btr_id(bandit)
    for _, data in pairs(nearby) do
        if data and data.brain and data.z == bz and tostring(data.id or "") ~= tostring(myId or "") then
            if btr_isFriendly(brain, data.brain) then
                local wx = data.x - bx
                local wy = data.y - by
                local proj = (wx * vx + wy * vy) / len2
                if proj > 0.08 and proj < 0.92 then
                    local closestX = bx + vx * proj
                    local closestY = by + vy * proj
                    local sideDist = btr_dist(data.x, data.y, closestX, closestY)
                    if sideDist <= (NPCTacticalRadioBridge.Config.friendlyFireCorridor or 0.92) then
                        brain.radio = brain.radio or {}
                        brain.radio.fireHoldReason = "friendly line of fire"
                        brain.radio.lastFriendlyFireBlockAt = btr_nowMs()
                        return false
                    end
                end
            end
        end
    end

    return true
end

function NPCTacticalRadioBridge.Debug(brain)
    if not brain then return end
    brain.debug = brain.debug or {}
    brain.debug.radio = true
    brain.debug.radioRole = brain.tacticalRole or (brain.radio and brain.radio.role)
    brain.debug.radioManeuver = brain.tacticalManeuver or (brain.radio and brain.radio.currentManeuver)
    brain.debug.radioSquad = brain.radio and brain.radio.squadCount or nil
    brain.debug.radioFireHold = brain.radio and brain.radio.fireHoldReason or nil
    brain.debug.radioThreat = brain.radioThreat and (tostring(brain.radioThreat.kind) .. "@" .. tostring(math.floor(brain.radioThreat.dist or 0))) or nil
    brain.debug.tacticalCoverScore = brain.tacticalCoverScore
    local coverProvider = NPCTacticalCoverBridge and NPCTacticalCoverBridge.Resolve and NPCTacticalCoverBridge.Resolve() or nil
    if coverProvider and coverProvider.Debug then pcall(function() coverProvider.Debug(brain) end) end
end
