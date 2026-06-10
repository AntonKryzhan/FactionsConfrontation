-- NPCBountyServerBridge.lua
-- Neutral server-side bounty records, checkpoint integration support and lightweight hunter retargeting.

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

local NPC_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
if isClient and isClient() then return end

require "NPCCore/NPCBountyBridge"
require "NPCCore/NPCFactionBridge"
require "NPCCore/NPCWeaponsBridge"
require "NPCCore/NPCCreatorBridge"
require "NPCServer/NPCWorldDirector"
require "NPCServer/NPCWorldDirectorBridge"

NPCBountyServerBridge = NPCBountyServerBridge or {}
NPCBountyServerBridge._tick = NPCBountyServerBridge._tick or 0
local function npcserver_setDebugMarker(gmd, marker)
    local runtime = NPCServerRuntime
    local setter = runtime and runtime.SetDebugMarker or NPC_LEGACY_GLOBALS.Get("SetDebugMarker")
    if setter then return setter(gmd, marker) end
    return false
end


local function bbs_halo(player, text, r, g, b)
    if player and text then sendServerCommand(player, 'NPCBounty', 'Result', {text=text, r=r or 255, g=g or 210, b=b or 90}) end
end

local function bbs_sync(player)
    if not (NPCBountyBridge and player) then return end
    local gmd = GetNPCModData()
    local payload = NPCBountyBridge.BuildPayload(gmd, player)
    sendServerCommand(player, 'NPCBounty', 'State', payload)
end

function NPCBountyServerBridge.SyncPlayer(player)
    bbs_sync(player)
end

local function bbs_syncAll(reason)
    local worldRulesServer = NPCWorldRulesServer or (NPCLegacyGlobalsBridge and NPCLegacyGlobalsBridge.Get and NPCLegacyGlobalsBridge.Get("WorldRulesServer"))
    if worldRulesServer and worldRulesServer.SyncAll then
        worldRulesServer.SyncAll(reason or "bounty_sync")
        return
    end
    if getOnlinePlayers then
        local ok, players = pcall(function() return getOnlinePlayers() end)
        if ok and players and players.size and players.get then
            for i=0, players:size()-1 do
                local p = players:get(i)
                if p then bbs_sync(p) end
            end
            return
        end
    end
end

local function bbs_setMarker(gmd, marker)
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

local function bbs_updateBountyMarker(gmd, rec, side, sideRec)
    if not (NPCBountyBridge and gmd and rec and sideRec) then return end
    local marker = NPCBountyBridge.MakeBountyMarker(rec, side, sideRec)
    if marker then bbs_setMarker(gmd, marker) end
end

local function bbs_removeBountyMarker(gmd, pid, side)
    if not (gmd and pid and side) then return end
    local id = "bounty_" .. tostring(pid) .. "_" .. tostring(side)
    if gmd.DebugMapMarkers then gmd.DebugMapMarkers[id] = nil end
    if NPCNetContract and NPCNetContract.SendDebugMapRemove then
        NPCNetContract.SendDebugMapRemove(id)
    else
        sendServerCommand('NPCDebugMap', 'Remove', {id=id})
    end
end

local function bbs_side(value)
    if NPCFactionBridge and NPCFactionBridge.NormalizeSide then return NPCFactionBridge.NormalizeSide(value) end
    value = tostring(value or ""):lower()
    if value == "red" or value == "green" or value == "blue" or value == "black" then return value end
    return nil
end

local function bbs_dist(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return math.sqrt(dx * dx + dy * dy)
end

local function bbs_now()
    if NPCBountyBridge and NPCBountyBridge.NowHours then return NPCBountyBridge.NowHours() end
    if getGameTime then
        local ok, value = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok then return tonumber(value) or 0 end
    end
    return os.time and os.time() / 3600 or 0
end

local function bbs_players()
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

local function bbs_playerById()
    local out = {}
    for _, player in ipairs(bbs_players()) do
        local id = NPCBountyBridge and NPCBountyBridge.PlayerId and NPCBountyBridge.PlayerId(player) or nil
        if id ~= nil then out[tostring(id)] = player end
    end
    return out
end

local function bbs_worldDirector()
    local director = NPCWorldDirectorServer or NPCWorldDirector or (NPC_LEGACY_GLOBALS and NPC_LEGACY_GLOBALS.Get and NPC_LEGACY_GLOBALS.Get("WorldDirector"))
    if type(director) ~= "table" or not director.EnsureData then return nil end
    return director
end

local function bbs_copyWeapon(w)
    if type(w) ~= "table" then return w end
    local out = {}
    for k, v in pairs(w) do out[k] = v end
    return out
end

local function bbs_weaponScore(w)
    if type(w) ~= "table" or not w.name then return -1 end
    local mag = tonumber(w.magSize or w.clipSize or w.maxAmmo) or 0
    local delay = tonumber(w.shotDelay) or 30
    local text = string.lower(tostring(w.name or "") .. " " .. tostring(w.magName or w.magazine or ""))
    local score = (mag * 4) + math.max(0, 70 - delay)
    if string.find(text, "assault", 1, true) or string.find(text, "rifle", 1, true) then score = score + 45 end
    if string.find(text, "lmg", 1, true) or string.find(text, "m249", 1, true) or string.find(text, "m60", 1, true) then score = score + 80 end
    if string.find(text, "sniper", 1, true) or string.find(text, "308", 1, true) then score = score + 36 end
    if string.find(text, "shotgun", 1, true) then score = score + 12 end
    return score
end

local function bbs_bestWeapon(pool)
    if type(pool) ~= "table" or #pool <= 0 then return nil end
    local best, bestScore = nil, -1
    for _, w in pairs(pool) do
        local score = bbs_weaponScore(w)
        if score > bestScore then
            best, bestScore = w, score
        end
    end
    return bbs_copyWeapon(best)
end

local function bbs_pickHunterWeapon(pool, slot)
    if type(pool) ~= "table" or #pool <= 0 then return nil end
    if NPCCreatorBridge and NPCCreatorBridge.PickBalancedFirearm then
        local wave = {eliteLoadout=true, mercenaryElite=true, hasRifleChance=100, rifleMagCount=8, hasPistolChance=100, pistolMagCount=5}
        local ok, picked = pcall(function() return NPCCreatorBridge.PickBalancedFirearm(pool, wave, slot) end)
        if ok and picked then return bbs_copyWeapon(picked) end
    end
    return bbs_bestWeapon(pool)
end

local function bbs_ensureWeapons(member)
    member.weapons = member.weapons or {}
    member.weapons.melee = member.weapons.melee or "Base.Axe"
    member.weapons.primary = member.weapons.primary or {name=false, magSize=0, bulletsLeft=0, magCount=0}
    member.weapons.secondary = member.weapons.secondary or {name=false, magSize=0, bulletsLeft=0, magCount=0}
    return member.weapons
end

local function bbs_addUnique(list, value)
    if type(list) ~= "table" or not value then return end
    for _, v in pairs(list) do
        if v == value then return end
    end
    table.insert(list, value)
end

local BBS_HUNTER_ARMOR = {
    "Base.Vest_BulletArmy",
    "Base.Vest_BulletPolice",
    "Base.Hat_ArmyHelmet",
    "Base.HolsterDouble",
    "Base.Bag_ALICEpack_Army",
    "Base.Gloves_LeatherGlovesBlack",
    "Base.Shoes_ArmyBoots"
}

local BBS_HUNTER_SUPPORT = {
    "Base.Bandage",
    "Base.AlcoholBandage",
    "Base.PillsBeta",
    "Base.WaterBottle"
}

local function bbs_applyHunterLoadout(member, group, index)
    if type(member) ~= "table" then return member end
    member.bountyHunter = true
    member.eliteUnit = true
    member.unitLevel = math.max(tonumber(member.unitLevel) or 0, 9)
    member.unitStars = math.max(tonumber(member.unitStars) or 0, 3)
    member.role = index == 1 and "bounty_hunter_leader" or "bounty_hunter"
    member.tacticalRole = index == 1 and "hunter_leader" or "assault_hunter"
    member.displayTitle = "Hunter"
    member.nameplateTitle = "Hunter"
    member.hostile = true
    member.factionSide = group.factionSide or group.side
    member.faction = group.factionSide or group.side
    member.side = group.side
    member.patrolColor = group.patrolColor or group.side
    member.program = {name="Raider", stage="Prepare"}
    member.order = {
        name="Advance",
        source="bounty_hunter",
        fireMode="FireAtWill",
        priority=98,
        sticky=true,
        anchor={x=group.targetX, y=group.targetY, z=group.targetZ or 0},
        note="Hunt bounty target"
    }
    member.accuracyBoost = math.max(tonumber(member.accuracyBoost) or 1, 1.95)
    member.health = math.max(tonumber(member.health) or 0, 4.85)
    member.maxHealth = math.max(tonumber(member.maxHealth) or 0, member.health)
    member.morale = math.max(tonumber(member.morale) or 0, 0.98)
    member.discipline = math.max(tonumber(member.discipline) or 0, 0.96)
    member.aggression = math.max(tonumber(member.aggression) or 0, 0.82)
    member.fear = math.min(tonumber(member.fear) or 1, 0.04)
    member.preferCover = true
    member.preferRoads = true
    member.roadBias = true
    member.behaviorStyle = "bounty_hunter_elite"
    member.skills = member.skills or {}
    for _, key in ipairs({"aiming", "reloading", "firearms", "strength", "fitness", "maintenance", "teamwork"}) do
        member.skills[key] = math.max(tonumber(member.skills[key]) or 0, 8)
    end

    local weapons = bbs_ensureWeapons(member)
    local primaryPool = nil
    local secondaryPool = nil
    if NPCWeaponsBridge and NPCWeaponsBridge.GetSpawnPrimary then primaryPool = NPCWeaponsBridge.GetSpawnPrimary(nil) elseif NPCWeaponsBridge then primaryPool = NPCWeaponsBridge.Primary end
    if NPCWeaponsBridge and NPCWeaponsBridge.GetSpawnSecondary then secondaryPool = NPCWeaponsBridge.GetSpawnSecondary(nil) elseif NPCWeaponsBridge then secondaryPool = NPCWeaponsBridge.Secondary end
    local primary = bbs_pickHunterWeapon(primaryPool, "primary") or {name="Base.AssaultRifle", magName="Base.556Clip", magSize=30, bulletsLeft=30, magCount=0, shotDelay=12}
    if primary and primary.name then
        weapons.primary = primary
        weapons.primary.magSize = tonumber(weapons.primary.magSize) or 30
        weapons.primary.bulletsLeft = weapons.primary.magSize
        weapons.primary.magCount = math.max(tonumber(weapons.primary.magCount) or 0, 8)
    end
    local secondary = bbs_pickHunterWeapon(secondaryPool, "secondary") or {name="Base.Pistol", magName="Base.9mmClip", magSize=15, bulletsLeft=15, magCount=0, shotDelay=35}
    if secondary and secondary.name then
        weapons.secondary = secondary
        weapons.secondary.magSize = tonumber(weapons.secondary.magSize) or 15
        weapons.secondary.bulletsLeft = weapons.secondary.magSize
        weapons.secondary.magCount = math.max(tonumber(weapons.secondary.magCount) or 0, 5)
    end
    if not weapons.melee or weapons.melee == "Base.BareHands" then weapons.melee = "Base.Axe" end

    member.inventory = member.inventory or {}
    member.loot = member.loot or {}
    member.baseGearWear = member.baseGearWear or {}
    for _, itemType in ipairs(BBS_HUNTER_ARMOR) do
        bbs_addUnique(member.inventory, itemType)
        bbs_addUnique(member.loot, itemType)
        bbs_addUnique(member.baseGearWear, itemType)
    end
    for _, itemType in ipairs(BBS_HUNTER_SUPPORT) do
        bbs_addUnique(member.inventory, itemType)
    end
    return member
end

local function bbs_retargetHunterMembers(group)
    if type(group) ~= "table" or type(group.members) ~= "table" then return end
    for i, member in pairs(group.members) do
        if type(member) == "table" then
            bbs_applyHunterLoadout(member, group, tonumber(i) or 1)
            member.bountyTargetPlayerId = group.bountyTargetPlayerId
            member.bountyTargetPlayerName = group.bountyTargetPlayerName
            if member.order then
                member.order.anchor = {x=group.targetX, y=group.targetY, z=group.targetZ or 0}
            end
        end
    end
end

local function bbs_tryMaterializeHunter(director, group, player)
    if not (director and group and player) then return false end
    group.anchorMaterializeAtGroup = true
    group.anchorSpawnRadius = 18
    group.anchorRoadRadius = 56
    local safe, result = false, false
    if director.MaterializeGroup then
        safe, result = pcall(function() return director.MaterializeGroup(group, player) end)
    elseif NPCWorldDirectorBridge and NPCWorldDirectorBridge.MaterializeGroup then
        safe, result = pcall(function() return NPCWorldDirectorBridge.MaterializeGroup(director, group, player) end)
    end
    return safe == true and result == true
end

local function bbs_updateGroupMarker(gmd, group)
    if not (gmd and group and group.id) then return end
    gmd.DebugMapMarkers = gmd.DebugMapMarkers or {}
    local marker = gmd.DebugMapMarkers and gmd.DebugMapMarkers[tostring(group.id)] or nil
    if not marker and NPCWorldDirectorBridge and NPCWorldDirectorBridge.BuildVirtualGroupMarker then
        marker = NPCWorldDirectorBridge.BuildVirtualGroupMarker(group)
    end
    marker = marker or {id=tostring(group.id), markerType="group"}
    marker.x = group.x
    marker.y = group.y
    marker.z = group.z or 0
    marker.name = group.name or marker.name or "Hunter team"
    marker.displayName = marker.name
    marker.markerType = "group"
    marker.virtual = group.virtual ~= false
    marker.active = group.activated == true
    marker.hostile = true
    marker.count = group.count
    marker.bountyHunter = group.bountyHunter == true
    marker.bountySide = group.bountySide or group.factionSide or group.side
    marker.bountyState = group.bountyState
    marker.bountyAmount = group.bountyAmount
    marker.bountyTargetPlayerId = group.bountyTargetPlayerId
    marker.bountyTargetPlayerName = group.bountyTargetPlayerName
    marker.targetX = group.targetX
    marker.targetY = group.targetY
    marker.state = group.state
    marker.updatedAt = group.updatedAt or (NPCBountyBridge and NPCBountyBridge.NowHours and NPCBountyBridge.NowHours() or 0)
    if NPCBountyBridge and NPCBountyBridge.MarkerFields then NPCBountyBridge.MarkerFields(marker, group) end
    bbs_setMarker(gmd, marker)
end

function NPCBountyServerBridge.DispatchHuntersFor(player, side, sideRec)
    if not (NPCBountyBridge and NPCBountyBridge.HunterRetargetEnabled and NPCBountyBridge.HunterRetargetEnabled()) then return 0 end
    if not (player and player.getX and sideRec and NPCBountyBridge.IsSideRecordActive(sideRec, NPCBountyBridge.HuntedThreshold())) then return 0 end
    local gmd = GetNPCModData()
    if not (gmd and type(gmd.VirtualGroups) == "table") then return 0 end
    side = bbs_side(side)
    if not side or side == "blue" or side == "black" then return 0 end
    local px = player:getX()
    local py = player:getY()
    local radius = NPCBountyBridge.HunterRadius()
    local maxGroups = NPCBountyBridge.HunterMaxGroups()
    if maxGroups <= 0 then return 0 end

    local candidates = {}
    for id, group in pairs(gmd.VirtualGroups) do
        if type(group) == "table" and not group.activated and not group.mercenary and (tonumber(group.count) or 0) > 0 then
            local gs = bbs_side(group.factionSide or group.side or group.patrolColor)
            if gs == side then
                local d = bbs_dist(group.x, group.y, px, py)
                if d <= radius then candidates[#candidates + 1] = {id=id, group=group, dist=d} end
            end
        end
    end
    table.sort(candidates, function(a, b) return (a.dist or 0) < (b.dist or 0) end)

    local changed = 0
    local pid = NPCBountyBridge.PlayerId(player)
    local pname = NPCBountyBridge.PlayerName(player)
    for i=1, math.min(#candidates, maxGroups) do
        local item = candidates[i]
        local group = item.group
        group.bountyHunter = true
        group.eliteUnit = true
        group.unitLevel = math.max(tonumber(group.unitLevel) or 0, 9)
        group.unitStars = math.max(tonumber(group.unitStars) or 0, 3)
        group.bountySide = side
        group.bountyState = sideRec.state
        group.bountyAmount = math.floor((tonumber(sideRec.value) or 0) + 0.5)
        group.bountyTargetPlayerId = pid
        group.bountyTargetPlayerName = pname
        group.targetX = math.floor(px)
        group.targetY = math.floor(py)
        group.targetZ = player.getZ and player:getZ() or 0
        group.routeX = group.targetX
        group.routeY = group.targetY
        group.routeZ = group.targetZ
        group.targetClass = "bounty_hunt"
        group.state = tostring(side) .. "_bounty_hunt_tracking"
        group.program = {name="Raider", stage="Prepare"}
        group.speed = math.max(tonumber(group.speed) or 0, 180)
        group.roadBias = true
        group.preferRoads = true
        group.hostile = true
        group.patrolColor = side
        group.factionSide = side
        group.faction = side
        group.side = side
        group.displayTitle = "Hunter"
        group.name = tostring(side):sub(1, 1):upper() .. tostring(side):sub(2) .. " hunter team"
        group.updatedAt = NPCBountyBridge.NowHours()
        if type(group.members) == "table" then
            for idx, member in pairs(group.members) do
                if type(member) == "table" then
                    member.bountyHunter = true
                    member.bountyTargetPlayerId = pid
                    member.bountyTargetPlayerName = pname
                    member.bountySide = side
                    member.bountyState = sideRec.state
                    member.bountyAmount = group.bountyAmount
                    bbs_applyHunterLoadout(member, group, tonumber(idx) or 1)
                end
            end
        end
        gmd.VirtualGroups[item.id] = group
        bbs_updateGroupMarker(gmd, group)
        changed = changed + 1
    end
    if changed > 0 then
        local data = NPCBountyBridge.EnsureData(gmd)
        if data and data.stats then data.stats.hunters = (tonumber(data.stats.hunters) or 0) + changed end
    end
    return changed
end

function NPCBountyServerBridge.ReportHostileAction(player, args)
    if not (NPCBountyBridge and NPCBountyBridge.IsEnabled and NPCBountyBridge.IsEnabled()) then return end
    local gmd = GetNPCModData()
    local victimSide = bbs_side(args and args.victimSide)
    if not victimSide then return end
    local killed = args and args.killed == true
    local sideRec, rec = NPCBountyBridge.ReportHostileAction(gmd, player, victimSide, killed, args)
    if not sideRec or not rec then return end
    bbs_updateBountyMarker(gmd, rec, victimSide, sideRec)
    bbs_sync(player)
    if NPCBountyBridge.IsSideRecordActive(sideRec, NPCBountyBridge.HuntedThreshold()) then
        NPCBountyServerBridge.DispatchHuntersFor(player, victimSide, sideRec)
    end
    if sideRec.lastDelta and sideRec.lastDelta > 0 and sideRec.value >= NPCBountyBridge.WantedThreshold() then
        bbs_halo(player, tostring(rec.playerName or "You") .. " wanted by " .. tostring(victimSide) .. " faction. Bounty " .. tostring(math.floor(sideRec.value + 0.5)) .. ".", 255, 170, 60)
    end
    if TransmitNPCModData then TransmitNPCModData() end
end

function NPCBountyServerBridge.Status(player)
    local gmd = GetNPCModData()
    if NPCBountyBridge and NPCBountyBridge.Decay then NPCBountyBridge.Decay(gmd) end
    bbs_sync(player)
    local payload = NPCBountyBridge and NPCBountyBridge.BuildPayload and NPCBountyBridge.BuildPayload(gmd, player) or nil
    bbs_halo(player, payload and payload.text or "No active bounty.", 255, 225, 120)
end

function NPCBountyServerBridge.Refresh(player)
    local gmd = GetNPCModData()
    local data = NPCBountyBridge and NPCBountyBridge.EnsureData and NPCBountyBridge.EnsureData(gmd) or nil
    if not data or type(data.players) ~= "table" then return end
    NPCBountyBridge.Decay(gmd)
    local pid = tostring(NPCBountyBridge.PlayerId(player) or "")
    local rec = data.players[pid]
    if rec and type(rec.bySide) == "table" then
        for side, sideRec in pairs(rec.bySide) do
            if NPCBountyBridge.IsSideRecordActive(sideRec, 1) then
                bbs_updateBountyMarker(gmd, rec, side, sideRec)
                if NPCBountyBridge.IsSideRecordActive(sideRec, NPCBountyBridge.HuntedThreshold()) then
                    NPCBountyServerBridge.DispatchHuntersFor(player, side, sideRec)
                end
            else
                bbs_removeBountyMarker(gmd, pid, side)
            end
        end
    end
    bbs_sync(player)
    if TransmitNPCModData then TransmitNPCModData() end
end

function NPCBountyServerBridge.OnClientCommand(module, command, player, args)
    if not NPCLegacyContractBridge.IsModule(module, "NPCBounty", "bounty") then return end
    if command == "ReportHostileAction" then
        NPCBountyServerBridge.ReportHostileAction(player, args or {})
    elseif command == "Status" then
        NPCBountyServerBridge.Status(player)
    elseif command == "Refresh" then
        NPCBountyServerBridge.Refresh(player)
    end
end

function NPCBountyServerBridge.UpdateHunterGroups()
    if not (NPCBountyBridge and NPCBountyBridge.IsEnabled and NPCBountyBridge.IsEnabled()) then return 0 end
    local gmd = GetNPCModData and GetNPCModData() or nil
    if not (gmd and type(gmd.VirtualGroups) == "table") then return 0 end
    local director = bbs_worldDirector()
    if not director then return 0 end
    local playersById = bbs_playerById()
    local now = bbs_now()
    local changed = 0

    for id, group in pairs(gmd.VirtualGroups) do
        if type(group) == "table" and group.bountyHunter == true and (tonumber(group.count) or 0) > 0 then
            local player = playersById[tostring(group.bountyTargetPlayerId or "")]
            if player and player.getX and player.getY then
                local px, py = player:getX(), player:getY()
                local pz = player.getZ and player:getZ() or 0
                group.targetX = math.floor(px)
                group.targetY = math.floor(py)
                group.targetZ = pz
                group.routeX = group.targetX
                group.routeY = group.targetY
                group.routeZ = group.targetZ
                group.targetClass = "bounty_hunt"
                group.hostile = true
                group.roadBias = true
                group.preferRoads = true
                group.speed = math.max(tonumber(group.speed) or 0, 190)
                group.state = group.activated and tostring(group.bountySide or group.side or "red") .. "_bounty_hunt_materialized" or tostring(group.bountySide or group.side or "red") .. "_bounty_hunt_tracking"
                group.updatedAt = now
                bbs_retargetHunterMembers(group)

                if group.virtual ~= false and not group.activated then
                    local gx = tonumber(group.preciseX or group.x) or 0
                    local gy = tonumber(group.preciseY or group.y) or 0
                    local dist = bbs_dist(gx, gy, px, py)
                    local last = tonumber(group.bountyLastMoveAt) or now
                    local dt = math.max(0, now - last)
                    if dt > 0 and dist > 72 then
                        local step = math.min(dist - 64, (tonumber(group.speed) or 190) * dt)
                        if step > 1 then
                            local nx = gx + ((px - gx) / math.max(0.001, dist)) * step
                            local ny = gy + ((py - gy) / math.max(0.001, dist)) * step
                            group.preciseX = nx
                            group.preciseY = ny
                            group.x = math.floor(nx)
                            group.y = math.floor(ny)
                        end
                    end
                    group.bountyLastMoveAt = now

                    local newDist = bbs_dist(group.x, group.y, px, py)
                    if newDist <= 92 then
                        if bbs_tryMaterializeHunter(director, group, player) then
                            group = gmd.VirtualGroups[tostring(id)] or group
                            group.bountyHunter = true
                            group.bountyState = group.bountyState or "hunted"
                            group.state = tostring(group.bountySide or group.side or "red") .. "_bounty_hunt_materialized"
                            group.targetX = math.floor(px)
                            group.targetY = math.floor(py)
                            group.targetZ = pz
                            bbs_retargetHunterMembers(group)
                        end
                    end
                end

                gmd.VirtualGroups[tostring(id)] = group
                bbs_updateGroupMarker(gmd, group)
                changed = changed + 1
            end
        end
    end

    if changed > 0 and TransmitNPCModData then TransmitNPCModData() end
    return changed
end

function NPCBountyServerBridge.OnTick()
    NPCBountyServerBridge._tick = (tonumber(NPCBountyServerBridge._tick) or 0) + 1
    if (NPCBountyServerBridge._tick % 180) ~= 0 then return end
    NPCBountyServerBridge.UpdateHunterGroups()
end

local function bbs_everyTenMinutes()
    if not (NPCBountyBridge and NPCBountyBridge.IsEnabled and NPCBountyBridge.IsEnabled()) then return end
    local gmd = GetNPCModData()
    if not gmd then return end
    local changed = NPCBountyBridge.Decay(gmd)
    if changed and changed > 0 then
        bbs_syncAll("bounty_decay")
        if TransmitNPCModData then TransmitNPCModData() end
    end
end

function NPCBountyServerBridge.Install()
    if NPCBountyServerBridge._installed then return end
    Events.OnClientCommand.Add(NPCBountyServerBridge.OnClientCommand)
    Events.EveryTenMinutes.Add(bbs_everyTenMinutes)
    Events.OnTick.Add(NPCBountyServerBridge.OnTick)
    NPCBountyServerBridge._installed = true
end

NPCBountyServerBridge.Install()
