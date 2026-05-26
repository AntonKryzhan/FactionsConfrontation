-- NPCBountyBridge.lua
-- Neutral bounty layer backend for players.
-- Bounties are virtual faction records: they do not change the real player side, but they can make a faction hunt the player and block checkpoints.

NPCBountyBridge = NPCBountyBridge or {}
NPCBountyBridge.Version = 1

local BB_SIDES = {"red", "green", "blue"}

local function bb_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        local ok, value = pcall(function() return NPCLegacySettingsBridge.GetBool(name, defaultValue == true) end)
        if ok and value ~= nil then return value == true end
    end
    return defaultValue == true
end

local function bb_num(name, defaultValue, minValue, maxValue)
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

local function bb_now()
    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then
            local ok, value = pcall(function() return gt:getWorldAgeHours() end)
            if ok and value then return tonumber(value) or 0 end
        end
    end
    return os.time and (os.time() / 3600) or 0
end

local function bb_rand(maxValue)
    maxValue = math.floor(tonumber(maxValue) or 0)
    if maxValue <= 0 then return 0 end
    if ZombRand then
        local ok, value = pcall(function() return ZombRand(maxValue) end)
        if ok and value ~= nil then return tonumber(value) or 0 end
    end
    return math.random(0, maxValue - 1)
end

local function bb_clamp(value, minValue, maxValue)
    value = tonumber(value) or 0
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function bb_side(side)
    if NPCFactionBridge and NPCFactionBridge.NormalizeSide then
        local s = NPCFactionBridge.NormalizeSide(side)
        if s then return s end
    end
    side = tostring(side or ""):lower()
    if side == "red" or side == "green" or side == "blue" or side == "black" then return side end
    return nil
end

local function bb_sideLabel(side)
    if NPCFactionBridge and NPCFactionBridge.GetSideLabel then
        local ok, label = pcall(function() return NPCFactionBridge.GetSideLabel(side) end)
        if ok and label then return tostring(label) end
    end
    return tostring(side or "faction")
end

function NPCBountyBridge.IsEnabled()
    return bb_bool("Bounty_Enabled", true)
end

function NPCBountyBridge.HitValue()
    return bb_num("Bounty_HitValue", 3, 0, 100)
end

function NPCBountyBridge.KillValue()
    return bb_num("Bounty_KillValue", 18, 0, 200)
end

function NPCBountyBridge.OwnFactionKillBonus()
    return bb_num("Bounty_OwnFactionKillBonus", 20, 0, 200)
end

function NPCBountyBridge.AlertThreshold()
    return bb_num("Bounty_AlertThreshold", 18, 1, 999)
end

function NPCBountyBridge.WantedThreshold()
    return bb_num("Bounty_WantedThreshold", 30, 1, 999)
end

function NPCBountyBridge.HuntedThreshold()
    return bb_num("Bounty_HuntedThreshold", 55, 1, 999)
end

function NPCBountyBridge.KillOnSightThreshold()
    return bb_num("Bounty_KillOnSightThreshold", 80, 1, 999)
end

function NPCBountyBridge.DurationHours()
    return bb_num("Bounty_DurationHours", 72, 1, 720)
end

function NPCBountyBridge.HitCooldownHours()
    return bb_num("Bounty_HitCooldownMinutes", 2, 0, 60) / 60
end

function NPCBountyBridge.DecayPerDay()
    return bb_num("Bounty_DecayPerDay", 6, 0, 200)
end

function NPCBountyBridge.CheckpointBlocksAt()
    return bb_num("Bounty_CheckpointBlockThreshold", NPCBountyBridge.AlertThreshold(), 1, 999)
end

function NPCBountyBridge.HunterRetargetEnabled()
    return bb_bool("Bounty_HunterRetargetEnabled", true)
end

function NPCBountyBridge.HunterRadius()
    return bb_num("Bounty_HunterRetargetRadius", 2400, 100, 10000)
end

function NPCBountyBridge.HunterMaxGroups()
    return math.floor(bb_num("Bounty_HunterMaxGroupsPerFaction", 2, 0, 8))
end

function NPCBountyBridge.NowHours()
    return bb_now()
end

function NPCBountyBridge.PlayerId(player)
    if not player then return nil end
    if NPCUtils and NPCUtils.GetCharacterID then
        local ok, id = pcall(function() return NPCUtils.GetCharacterID(player) end)
        if ok and id ~= nil then return id end
    end
    if player.getOnlineID then
        local ok, id = pcall(function() return player:getOnlineID() end)
        if ok and id ~= nil then return id end
    end
    if player.getUsername then
        local ok, name = pcall(function() return player:getUsername() end)
        if ok and name then return tostring(name) end
    end
    return nil
end

function NPCBountyBridge.PlayerName(player)
    if not player then return "player" end
    if player.getUsername then
        local ok, name = pcall(function() return player:getUsername() end)
        if ok and name then return tostring(name) end
    end
    if player.getDisplayName then
        local ok, name = pcall(function() return player:getDisplayName() end)
        if ok and name then return tostring(name) end
    end
    return tostring(NPCBountyBridge.PlayerId(player) or "player")
end

function NPCBountyBridge.State(value)
    value = tonumber(value) or 0
    if value >= NPCBountyBridge.KillOnSightThreshold() then return "kill_on_sight" end
    if value >= NPCBountyBridge.HuntedThreshold() then return "hunted" end
    if value >= NPCBountyBridge.WantedThreshold() then return "wanted" end
    if value >= NPCBountyBridge.AlertThreshold() then return "suspect" end
    return "clean"
end

function NPCBountyBridge.EnsureData(gmd)
    if not gmd then return nil end
    gmd.NPCBountyBridge = gmd.NPCBountyBridge or {}
    gmd.NPCBountyBridge.players = gmd.NPCBountyBridge.players or {}
    gmd.NPCBountyBridge.history = gmd.NPCBountyBridge.history or {}
    gmd.NPCBountyBridge.stats = gmd.NPCBountyBridge.stats or {reports=0, kills=0, hunters=0, expired=0}
    if not gmd.DebugMapMarkers then gmd.DebugMapMarkers = {} end
    return gmd.NPCBountyBridge
end

function NPCBountyBridge.EnsurePlayerRecord(gmd, player)
    local data = NPCBountyBridge.EnsureData(gmd)
    local pid = tostring(NPCBountyBridge.PlayerId(player) or "")
    if not data or pid == "" then return nil, nil end
    local rec = data.players[pid] or {}
    rec.playerId = pid
    rec.playerName = NPCBountyBridge.PlayerName(player)
    rec.bySide = rec.bySide or {}
    rec.updatedAt = bb_now()
    data.players[pid] = rec
    return rec, pid
end

function NPCBountyBridge.GetPlayerRecord(gmd, player)
    local data = NPCBountyBridge.EnsureData(gmd)
    local pid = tostring(NPCBountyBridge.PlayerId(player) or "")
    if not data or pid == "" then return nil end
    return data.players[pid]
end

function NPCBountyBridge.GetSideRecord(gmd, player, side)
    local rec = NPCBountyBridge.GetPlayerRecord(gmd, player)
    side = bb_side(side)
    if not rec or not side or type(rec.bySide) ~= "table" then return nil end
    return rec.bySide[side]
end

function NPCBountyBridge.IsSideRecordActive(sideRec, threshold)
    if type(sideRec) ~= "table" then return false end
    local value = tonumber(sideRec.value) or 0
    threshold = tonumber(threshold) or NPCBountyBridge.WantedThreshold()
    if value < threshold then return false end
    local expiresAt = tonumber(sideRec.expiresAt)
    if expiresAt and expiresAt > 0 and expiresAt <= bb_now() then return false end
    return true
end

function NPCBountyBridge.IsWantedByFaction(gmd, player, side, threshold)
    local sideRec = NPCBountyBridge.GetSideRecord(gmd, player, side)
    return NPCBountyBridge.IsSideRecordActive(sideRec, threshold or NPCBountyBridge.WantedThreshold())
end

function NPCBountyBridge.Add(gmd, player, side, amount, reason, extra)
    if not NPCBountyBridge.IsEnabled() then return nil end
    side = bb_side(side)
    if not side or side == "black" then return nil end
    amount = tonumber(amount) or 0
    if amount == 0 then return nil end

    local rec, pid = NPCBountyBridge.EnsurePlayerRecord(gmd, player)
    if not rec then return nil end
    rec.bySide[side] = rec.bySide[side] or {side=side, value=0, state="clean"}
    local sideRec = rec.bySide[side]
    local before = tonumber(sideRec.value) or 0
    local after = bb_clamp(before + amount, 0, 999)
    sideRec.value = after
    sideRec.state = NPCBountyBridge.State(after)
    sideRec.reason = reason or sideRec.reason
    sideRec.lastDelta = after - before
    sideRec.updatedAt = bb_now()
    sideRec.expiresAt = bb_now() + NPCBountyBridge.DurationHours()
    sideRec.playerId = pid
    sideRec.playerName = rec.playerName
    if player and player.getX then
        sideRec.lastKnownX = math.floor(player:getX())
        sideRec.lastKnownY = math.floor(player:getY())
        sideRec.lastKnownZ = player.getZ and player:getZ() or 0
    elseif extra then
        sideRec.lastKnownX = tonumber(extra.x) or sideRec.lastKnownX
        sideRec.lastKnownY = tonumber(extra.y) or sideRec.lastKnownY
        sideRec.lastKnownZ = tonumber(extra.z) or sideRec.lastKnownZ
    end
    rec.updatedAt = sideRec.updatedAt
    rec.lastSide = side
    rec.lastState = sideRec.state
    rec.lastValue = sideRec.value
    local data = NPCBountyBridge.EnsureData(gmd)
    if data and data.stats then
        data.stats.reports = (tonumber(data.stats.reports) or 0) + 1
    end
    return sideRec, rec
end

function NPCBountyBridge.ReportHostileAction(gmd, player, victimSide, killed, victimBrain)
    if not NPCBountyBridge.IsEnabled() then return nil end
    victimSide = bb_side(victimSide)
    if not victimSide or victimSide == "black" then return nil end

    local rec = NPCBountyBridge.GetPlayerRecord(gmd, player)
    local sideRec = rec and rec.bySide and rec.bySide[victimSide] or nil
    local now = bb_now()
    if not killed and sideRec and tonumber(sideRec.lastHitReportAt) and now - tonumber(sideRec.lastHitReportAt) < NPCBountyBridge.HitCooldownHours() then
        return nil
    end

    local amount = killed and NPCBountyBridge.KillValue() or NPCBountyBridge.HitValue()
    local playerSide = NPCFactionBridge and NPCFactionBridge.GetPlayerSide and NPCFactionBridge.GetPlayerSide(player) or nil
    if killed and playerSide and bb_side(playerSide) == victimSide then
        amount = amount + NPCBountyBridge.OwnFactionKillBonus()
    end
    local reason = killed and "killed_" .. tostring(victimSide) or "attacked_" .. tostring(victimSide)
    sideRec, rec = NPCBountyBridge.Add(gmd, player, victimSide, amount, reason, {victimId = victimBrain and victimBrain.id})
    if sideRec then
        if killed then sideRec.lastKillReportAt = now else sideRec.lastHitReportAt = now end
    end
    local data = NPCBountyBridge.EnsureData(gmd)
    if data and killed and data.stats then data.stats.kills = (tonumber(data.stats.kills) or 0) + 1 end
    return sideRec, rec
end

function NPCBountyBridge.Decay(gmd)
    local data = NPCBountyBridge.EnsureData(gmd)
    if not data or type(data.players) ~= "table" then return 0 end
    local now = bb_now()
    local decayPerHour = NPCBountyBridge.DecayPerDay() / 24
    local changed = 0
    for pid, rec in pairs(data.players) do
        if type(rec) == "table" and type(rec.bySide) == "table" then
            for side, sideRec in pairs(rec.bySide) do
                if type(sideRec) == "table" then
                    local last = tonumber(sideRec.lastDecayAt or sideRec.updatedAt or now) or now
                    local elapsed = math.max(0, now - last)
                    if elapsed > 0 and decayPerHour > 0 then
                        local before = tonumber(sideRec.value) or 0
                        local after = bb_clamp(before - elapsed * decayPerHour, 0, 999)
                        if math.floor(after + 0.5) ~= math.floor(before + 0.5) then changed = changed + 1 end
                        sideRec.value = after
                        sideRec.state = NPCBountyBridge.State(after)
                    end
                    sideRec.lastDecayAt = now
                    if (tonumber(sideRec.value) or 0) <= 0.5 or (tonumber(sideRec.expiresAt) or 0) <= now then
                        rec.bySide[side] = nil
                        data.stats.expired = (tonumber(data.stats.expired) or 0) + 1
                        changed = changed + 1
                    end
                end
            end
        end
    end
    return changed
end

function NPCBountyBridge.BuildPayload(gmd, player)
    local rec = NPCBountyBridge.GetPlayerRecord(gmd, player)
    local payload = {bySide={}, updatedAt=bb_now(), text="No active bounty."}
    if not rec or type(rec.bySide) ~= "table" then return payload end
    payload.playerId = rec.playerId
    payload.playerName = rec.playerName
    local parts = {}
    for side, sideRec in pairs(rec.bySide) do
        if type(sideRec) == "table" and NPCBountyBridge.IsSideRecordActive(sideRec, 1) then
            payload.bySide[side] = {
                side = side,
                value = math.floor((tonumber(sideRec.value) or 0) + 0.5),
                state = sideRec.state,
                reason = sideRec.reason,
                expiresAt = sideRec.expiresAt,
                lastKnownX = sideRec.lastKnownX,
                lastKnownY = sideRec.lastKnownY
            }
            parts[#parts + 1] = bb_sideLabel(side) .. " " .. tostring(payload.bySide[side].state) .. " " .. tostring(payload.bySide[side].value)
        end
    end
    if #parts > 0 then payload.text = "Bounty: " .. table.concat(parts, " / ") end
    return payload
end

function NPCBountyBridge.ApplyStatePayload(player, args)
    player = player or (getPlayer and getPlayer() or nil)
    if not player or type(args) ~= "table" then return end
    local md = player.getModData and player:getModData() or nil
    if not md then return end
    md.NPCBountyBridge = {
        bySide = args.bySide or {},
        updatedAt = args.updatedAt or bb_now(),
        text = args.text,
        playerId = args.playerId,
        playerName = args.playerName
    }
end

function NPCBountyBridge.GetLocalSideRecord(player, side)
    player = player or (getPlayer and getPlayer() or nil)
    local md = player and player.getModData and player:getModData() or nil
    local bounty = md and md.NPCBountyBridge or nil
    local bySide = bounty and bounty.bySide or nil
    side = bb_side(side)
    if type(bySide) ~= "table" or not side then return nil end
    return bySide[side]
end

function NPCBountyBridge.IsLocalWantedBySide(player, side, threshold)
    local rec = NPCBountyBridge.GetLocalSideRecord(player, side)
    if type(rec) ~= "table" then return false end
    local value = tonumber(rec.value) or 0
    threshold = tonumber(threshold) or NPCBountyBridge.WantedThreshold()
    if value < threshold then return false end
    local expiresAt = tonumber(rec.expiresAt)
    if expiresAt and expiresAt > 0 and expiresAt <= bb_now() then return false end
    return true
end

function NPCBountyBridge.ShouldFactionHuntPlayer(observerSide, player, brain)
    if not NPCBountyBridge.IsEnabled() then return false end
    observerSide = bb_side(observerSide)
    if not observerSide or observerSide == "blue" or observerSide == "black" then return false end
    return NPCBountyBridge.IsLocalWantedBySide(player, observerSide, NPCBountyBridge.WantedThreshold())
end

function NPCBountyBridge.MakeBountyMarker(playerOrRec, side, sideRec)
    side = bb_side(side)
    if not side or type(sideRec) ~= "table" then return nil end
    local pid = sideRec.playerId or (type(playerOrRec) == "table" and playerOrRec.playerId) or "player"
    local x = tonumber(sideRec.lastKnownX)
    local y = tonumber(sideRec.lastKnownY)
    if not x or not y then return nil end
    local state = tostring(sideRec.state or NPCBountyBridge.State(sideRec.value))
    return {
        id = "bounty_" .. tostring(pid) .. "_" .. tostring(side),
        markerType = "bounty",
        name = bb_sideLabel(side) .. " bounty: " .. tostring(sideRec.playerName or pid),
        x = x,
        y = y,
        z = tonumber(sideRec.lastKnownZ) or 0,
        factionSide = side,
        side = side,
        bounty = true,
        bountySide = side,
        bountyState = state,
        bountyAmount = math.floor((tonumber(sideRec.value) or 0) + 0.5),
        bountyPlayerId = pid,
        bountyPlayerName = sideRec.playerName,
        bountyExpiresAt = sideRec.expiresAt,
        hostile = side == "red",
        friendly = false,
        active = true,
        updatedAt = sideRec.updatedAt or bb_now()
    }
end

function NPCBountyBridge.MarkerFields(marker, data)
    if not (marker and type(data) == "table") then return marker end
    marker.bounty = data.bounty
    marker.bountyHunter = data.bountyHunter
    marker.bountySide = data.bountySide or data.factionSide or data.side
    marker.bountyState = data.bountyState
    marker.bountyAmount = data.bountyAmount
    marker.bountyPlayerId = data.bountyPlayerId or data.bountyTargetPlayerId
    marker.bountyPlayerName = data.bountyPlayerName or data.bountyTargetPlayerName
    marker.bountyExpiresAt = data.bountyExpiresAt
    marker.bountyTargetPlayerId = data.bountyTargetPlayerId
    marker.bountyTargetPlayerName = data.bountyTargetPlayerName
    return marker
end
