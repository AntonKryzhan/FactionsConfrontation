-- NPCPrisonerBridge.lua
-- Interactive prisoner / interrogation layer for legacy NPC runtime.
-- Designed as a lightweight first step: only surrendered or badly wounded NPCs can be taken prisoner.

NPCPrisonerBridge = NPCPrisonerBridge or {}

local function bp_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        local ok, value = pcall(function() return NPCLegacySettingsBridge.GetBool(name, defaultValue == true) end)
        if ok and value ~= nil then return value == true end
    end
    return defaultValue == true
end

local function bp_num(name, defaultValue, minValue, maxValue)
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

local function bp_now()
    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then return gt:getWorldAgeHours() end
    end
    return 0
end

local function bp_playerId(player)
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

local function bp_playerName(player)
    if not player then return nil end
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

local function bp_side(value)
    if NPCFactionBridge and NPCFactionBridge.NormalizeSide then
        return NPCFactionBridge.NormalizeSide(value)
    end
    if value == "red" or value == "green" or value == "blue" or value == "black" then return value end
    if value == "friendly" then return "green" end
    return value
end

local function bp_brainSide(brain)
    if NPCFactionBridge and NPCFactionBridge.GetBrainSide then
        local ok, side = pcall(function() return NPCFactionBridge.GetBrainSide(brain) end)
        if ok and side then return bp_side(side) end
    end
    return bp_side(brain and (brain.factionSide or brain.faction or brain.side or brain.patrolColor))
end

local function bp_playerSide(player)
    if NPCFactionBridge and NPCFactionBridge.GetPlayerSide then
        local ok, side = pcall(function() return NPCFactionBridge.GetPlayerSide(player) end)
        if ok and side then return bp_side(side) end
    end
    return "blue"
end

local function bp_dist(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return math.sqrt(dx * dx + dy * dy)
end

local function bp_addCandidate(list, kind, name, x, y, z, side, target)
    x = tonumber(x)
    y = tonumber(y)
    if not x or not y then return end
    list[#list + 1] = {
        kind = kind,
        name = tostring(name or kind),
        x = x,
        y = y,
        z = tonumber(z) or 0,
        side = side,
        target = target
    }
end

local function bp_collectCandidates(gmd, brain, player)
    local candidates = {}
    if not gmd then return candidates end

    local px = player and player.getX and player:getX() or brain.x or 0
    local py = player and player.getY and player:getY() or brain.y or 0
    local playerSide = bp_playerSide(player)

    if type(gmd.BaseCamps) == "table" then
        for _, base in pairs(gmd.BaseCamps) do
            if type(base) == "table" and base.x and base.y then
                local owner = bp_side(base.owner or base.captureTeam)
                if owner and owner ~= playerSide then
                    bp_addCandidate(candidates, "base", base.name or ("Base " .. tostring(base.id or "?")), base.x, base.y, base.z, owner, base)
                end
            end
        end
    end

    if type(gmd.VirtualGroups) == "table" then
        for gid, group in pairs(gmd.VirtualGroups) do
            if type(group) == "table" and group.x and group.y and (tonumber(group.count) or 0) > 0 then
                local side = bp_side(group.factionSide or group.faction or group.side or group.patrolColor)
                if side and side ~= playerSide then
                    local name = group.name or ("Enemy group " .. tostring(gid))
                    bp_addCandidate(candidates, "patrol", name, group.x, group.y, group.z, side, group)
                end
            end
        end
    end

    if type(gmd.DebugMapMarkers) == "table" then
        for _, marker in pairs(gmd.DebugMapMarkers) do
            if type(marker) == "table" and marker.x and marker.y then
                local mt = marker.markerType
                if mt == "group" or mt == "base" or mt == "economy_mission" then
                    local side = bp_side(marker.factionSide or marker.faction or marker.side or marker.owner or marker.patrolColor)
                    if side and side ~= playerSide then
                        bp_addCandidate(candidates, mt == "base" and "base" or "patrol", marker.name or tostring(mt), marker.x, marker.y, marker.z, side, marker)
                    end
                end
            end
        end
    end

    table.sort(candidates, function(a, b)
        return bp_dist(px, py, a.x, a.y) < bp_dist(px, py, b.x, b.y)
    end)

    return candidates
end

local function bp_pickCandidate(candidates)
    if #candidates <= 0 then return nil end
    local maxPick = math.min(#candidates, 5)
    local idx = 1
    if ZombRand then idx = 1 + ZombRand(maxPick) end
    return candidates[idx]
end

local function bp_noiseCoord(value, noise)
    value = tonumber(value) or 0
    noise = math.floor(tonumber(noise) or 0)
    if noise <= 0 or not ZombRand then return math.floor(value) end
    return math.floor(value + ZombRand(-noise, noise + 1))
end

local function bp_sideLabel(side)
    if NPCFactionBridge and NPCFactionBridge.GetSideLabel then
        local ok, label = pcall(function() return NPCFactionBridge.GetSideLabel(side) end)
        if ok and label then return tostring(label) end
    end
    return tostring(side or "unknown")
end

function NPCPrisonerBridge.IsEnabled()
    return bp_bool("Prisoner_Enabled", true)
end

function NPCPrisonerBridge.HealthThreshold()
    return bp_num("Prisoner_HealthThreshold", 0.20, 0.01, 1.00)
end

function NPCPrisonerBridge.IsSurrenderedBrain(brain)
    if not brain then return false end
    if brain.prisoner == true then return true end
    if brain.surrendered == true then return true end
    if brain.program and brain.program.stage == "Surrender" then return true end
    if brain.sim and (brain.sim.state == "Surrender" or brain.sim.order == "Surrender") then return true end
    local health = tonumber(brain.health)
    if health and health <= NPCPrisonerBridge.HealthThreshold() then return true end
    return false
end

function NPCPrisonerBridge.CanTakeBrain(brain, player)
    if not NPCPrisonerBridge.IsEnabled() then return false end
    if not brain or brain.prisoner == true then return false end
    if brain.mercenaryHired == true or brain.mercenaryHiredBy ~= nil then return false end
    if brain.spyDefected == true then return false end
    if brain.program and (brain.program.name == "Companion" or brain.program.name == "CompanionGuard") then return false end
    if not NPCPrisonerBridge.IsSurrenderedBrain(brain) then return false end
    local side = bp_brainSide(brain)
    local playerSide = bp_playerSide(player)
    if side and playerSide and side == playerSide then return false end
    return true
end

function NPCPrisonerBridge.CanInterrogateBrain(brain, player)
    if not NPCPrisonerBridge.IsEnabled() then return false end
    if not brain or brain.prisoner ~= true then return false end
    local pid = bp_playerId(player)
    if brain.prisonerForPlayerId ~= nil and pid ~= nil and tostring(brain.prisonerForPlayerId) ~= tostring(pid) then return false end
    local cooldown = bp_num("Prisoner_InterrogateCooldownMinutes", 180, 0, 10080) / 60
    local last = tonumber(brain.prisonerInterrogatedAt) or -999999
    return bp_now() - last >= cooldown
end

function NPCPrisonerBridge.MarkPrisoner(brain, player)
    if not brain then return false end
    local pid = bp_playerId(player)
    brain.prisoner = true
    brain.prisonerForPlayerId = pid
    brain.prisonerForPlayerName = bp_playerName(player)
    brain.prisonerOriginalSide = brain.prisonerOriginalSide or bp_brainSide(brain)
    brain.prisonerTakenAt = bp_now()
    brain.prisonerState = "captured"
    brain.hostile = false
    brain.factionShoot = false
    brain.weapons = {}
    brain.currentWeapon = nil
    brain.ammo = nil
    brain.order = {name="Hold", fireMode="HoldFire"}
    brain.fireMode = "HoldFire"
    if not brain.program or type(brain.program) ~= "table" then brain.program = {} end
    brain.program.name = "Raider"
    brain.program.stage = "Surrender"
    if not brain.sim then brain.sim = {} end
    brain.sim.order = "Surrender"
    brain.sim.fireMode = "HoldFire"
    brain.sim.state = "Surrender"
    return true
end

function NPCPrisonerBridge.ReleasePrisoner(brain, player)
    if not brain then return false end
    brain.prisoner = false
    brain.prisonerReleasedAt = bp_now()
    brain.prisonerState = "released"
    brain.hostile = false
    brain.factionShoot = false
    brain.order = {name="Flee", fireMode="HoldFire"}
    brain.fireMode = "HoldFire"
    if not brain.program or type(brain.program) ~= "table" then brain.program = {} end
    brain.program.name = "Looter"
    brain.program.stage = "Prepare"
    if not brain.sim then brain.sim = {} end
    brain.sim.order = "Flee"
    brain.sim.fireMode = "HoldFire"
    brain.sim.state = "Released"
    return true
end

function NPCPrisonerBridge.PruneIntel(gmd)
    if not gmd then return end
    if type(gmd.PrisonerIntel) ~= "table" then gmd.PrisonerIntel = {} end
    local maxIntel = math.floor(bp_num("Prisoner_MaxIntelMarkers", 50, 0, 500))
    local now = bp_now()
    local ttl = bp_num("Prisoner_IntelMarkerHours", 24, 0, 240)

    local kept = {}
    for _, intel in ipairs(gmd.PrisonerIntel) do
        local expired = ttl > 0 and intel.createdAt and now - tonumber(intel.createdAt) > ttl
        if not expired then kept[#kept + 1] = intel end
    end
    while maxIntel > 0 and #kept > maxIntel do
        local old = table.remove(kept, 1)
        if old and old.markerId and gmd.DebugMapMarkers then gmd.DebugMapMarkers[tostring(old.markerId)] = nil end
    end
    gmd.PrisonerIntel = kept
end

function NPCPrisonerBridge.MakeIntelMarker(gmd, intel)
    if not gmd or not intel or not intel.x or not intel.y then return nil end
    if type(gmd.DebugMapMarkers) ~= "table" then gmd.DebugMapMarkers = {} end
    local id = "intel_" .. tostring(intel.playerId or "p") .. "_" .. tostring(math.floor((intel.createdAt or bp_now()) * 1000))
    if ZombRand then id = id .. "_" .. tostring(ZombRand(100000)) end
    local marker = {
        id = id,
        markerType = "intel",
        x = intel.x,
        y = intel.y,
        z = intel.z or 0,
        name = intel.title or "Interrogation intel",
        hostile = false,
        friendly = true,
        factionSide = intel.side,
        faction = intel.side,
        side = intel.side,
        intelKind = intel.kind,
        intelFalse = intel.falseInfo == true,
        intelConfidence = intel.confidence,
        updatedAt = bp_now()
    }
    gmd.DebugMapMarkers[id] = marker
    intel.markerId = id
    return marker
end

function NPCPrisonerBridge.InterrogateBrain(gmd, brain, player)
    if not NPCPrisonerBridge.CanInterrogateBrain(brain, player) then return nil, "Cannot interrogate this prisoner now." end
    if not gmd then return nil, "No world data." end

    NPCPrisonerBridge.PruneIntel(gmd)

    local candidates = bp_collectCandidates(gmd, brain, player)
    local target = bp_pickCandidate(candidates)
    local falseChance = bp_num("Prisoner_LieChance", 20, 0, 100)
    local falseInfo = ZombRand and ZombRand(100) < falseChance or false
    local noise = bp_num("Prisoner_IntelNoiseTiles", 24, 0, 300)

    local px = player and player.getX and player:getX() or brain.x or 0
    local py = player and player.getY and player:getY() or brain.y or 0
    local intel = {
        createdAt = bp_now(),
        playerId = bp_playerId(player),
        playerName = bp_playerName(player),
        prisonerId = brain.id,
        prisonerName = brain.fullname,
        sourceSide = bp_brainSide(brain),
        confidence = falseInfo and "low" or "medium"
    }

    if target and not falseInfo then
        intel.kind = target.kind
        intel.side = target.side
        intel.x = bp_noiseCoord(target.x, noise)
        intel.y = bp_noiseCoord(target.y, noise)
        intel.z = target.z or 0
        intel.title = "Intel: " .. tostring(target.kind) .. " / " .. bp_sideLabel(target.side)
        intel.text = "Intel: " .. bp_sideLabel(target.side) .. " " .. tostring(target.kind) .. " near " .. tostring(intel.x) .. ", " .. tostring(intel.y) .. "."
    else
        local fakeNoise = math.max(80, noise * 4)
        intel.kind = "rumor"
        intel.side = bp_brainSide(brain) or "red"
        intel.x = bp_noiseCoord(px, fakeNoise)
        intel.y = bp_noiseCoord(py, fakeNoise)
        intel.z = 0
        intel.falseInfo = true
        intel.title = "Intel: unreliable rumor"
        intel.text = "Intel: unreliable rumor near " .. tostring(intel.x) .. ", " .. tostring(intel.y) .. ". It may be false."
    end

    brain.prisonerInterrogatedAt = bp_now()
    brain.prisonerState = "interrogated"
    brain.prisonerIntelCount = (tonumber(brain.prisonerIntelCount) or 0) + 1

    if type(gmd.PrisonerIntel) ~= "table" then gmd.PrisonerIntel = {} end
    gmd.PrisonerIntel[#gmd.PrisonerIntel + 1] = intel

    return intel, nil
end
