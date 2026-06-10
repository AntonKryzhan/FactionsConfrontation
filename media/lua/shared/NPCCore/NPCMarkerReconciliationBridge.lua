-- NPCMarkerReconciliationBridge.lua
-- Runtime-only marker reconciliation helpers for NPC, group and leader debug-map markers.

NPCMarkerReconciliationBridge = NPCMarkerReconciliationBridge or {}
NPCMarkerReconciliationBridge.Version = 1

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCIdentityReconciliationBridge"

NPCMarkerReconciliationBridge.DefaultServerBudget = NPCMarkerReconciliationBridge.DefaultServerBudget or 160
NPCMarkerReconciliationBridge.DefaultClientBudget = NPCMarkerReconciliationBridge.DefaultClientBudget or 220
NPCMarkerReconciliationBridge.DefaultLeaderTtlHours = NPCMarkerReconciliationBridge.DefaultLeaderTtlHours or 2.0

local function mr_nowHours()
    if NPCIdentityBridge and NPCIdentityBridge.GetWorldAgeHours then
        local ok, value = pcall(function() return NPCIdentityBridge.GetWorldAgeHours() end)
        if ok and value then return tonumber(value) or 0 end
    end
    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then
            local ok, value = pcall(function() return gt:getWorldAgeHours() end)
            if ok and value then return tonumber(value) or 0 end
        end
    end
    return 0
end

local function mr_nonempty(value)
    if value == nil then return nil end
    local text = tostring(value)
    if text == "" or text == "nil" or text == "false" then return nil end
    return text
end

local function mr_number(value, fallback)
    local n = tonumber(value)
    if n == nil then return fallback end
    return n
end

local function mr_markerType(marker)
    if type(marker) ~= "table" then return nil end
    return tostring(marker.markerType or marker.kind or "")
end

local function mr_markerId(id, marker)
    return mr_nonempty(id or (marker and (marker.id or marker.uid or marker.groupId)))
end

local function mr_groupId(id, marker)
    if type(marker) ~= "table" then return mr_nonempty(id) end
    return mr_nonempty(marker.groupId or marker.worldGroupId or marker.attachedGroupId or (mr_markerType(marker) == "group" and (marker.id or id) or nil))
end

local function mr_hasCoords(marker)
    if type(marker) ~= "table" then return false end
    return mr_number(marker.x, nil) ~= nil and mr_number(marker.y, nil) ~= nil
end

local function mr_isRemovedState(state)
    if state == nil then return false end
    state = string.lower(tostring(state))
    return state == "dead"
        or state == "removed"
        or state == "lost"
        or state == "expired"
        or state == "despawned"
        or state == "cleanup"
end

local function mr_getGroup(gmd, groupId)
    if not (gmd and groupId and type(gmd.VirtualGroups) == "table") then return nil end
    local sid = tostring(groupId)
    return gmd.VirtualGroups[sid] or gmd.VirtualGroups[groupId]
end

local function mr_groupMemberCount(group)
    if type(group) ~= "table" then return 0 end
    if type(group.members) == "table" then return #group.members end
    return mr_number(group.count or group.memberCount or group.size, 0) or 0
end

local function mr_groupHasQueuedBrain(gmd, groupId, group)
    if not (gmd and groupId and type(gmd.Queue) == "table") then return false end
    local gid = tostring(groupId)
    if type(group) == "table" and type(group.physicalIds) == "table" then
        for _, runtimeId in ipairs(group.physicalIds) do
            if NPCIdentityReconciliationBridge and NPCIdentityReconciliationBridge.FindQueueBrain then
                local brain = NPCIdentityReconciliationBridge.FindQueueBrain(gmd, runtimeId, nil)
                if type(brain) == "table" then return true end
            elseif gmd.Queue[tostring(runtimeId)] or gmd.Queue[tonumber(runtimeId)] then
                return true
            end
        end
    end
    for _, brain in pairs(gmd.Queue) do
        if type(brain) == "table" and tostring(brain.worldGroupId or brain.groupId or "") == gid then return true end
    end
    return false
end

local function mr_findLeaderRecord(gmd, leaderId)
    if not (gmd and leaderId) then return nil end
    local sid = tostring(leaderId)
    if NPCLeadersBridge and NPCLeadersBridge.EnsureData then
        local ok, data = pcall(function() return NPCLeadersBridge.EnsureData(gmd) end)
        if ok and type(data) == "table" and type(data.leaders) == "table" then
            for _, leader in pairs(data.leaders) do
                if type(leader) == "table" and tostring(leader.id or "") == sid then return leader end
            end
        end
    end
    local data = gmd.NPCLeadersBridge or gmd.NPCLeaders or gmd.Leaders
    if type(data) == "table" then
        local leaders = data.leaders or data
        for _, leader in pairs(leaders) do
            if type(leader) == "table" and tostring(leader.id or "") == sid then return leader end
        end
    end
    return nil
end

local function mr_leaderAlive(leader)
    if type(leader) ~= "table" then return nil end
    if leader.dead == true or leader.removed == true then return false end
    if mr_isRemovedState(leader.state or leader.leaderState or leader.status) then return false end
    return true
end

local function mr_markerHasLiveRuntime(gmd, marker)
    if NPCIdentityReconciliationBridge and NPCIdentityReconciliationBridge.MarkerHasLiveRuntime then
        local ok, live = pcall(function() return NPCIdentityReconciliationBridge.MarkerHasLiveRuntime(gmd, marker) end)
        if ok then return live == true end
    end
    return false
end

local function mr_cleanGroupName(name, groupId)
    if name == nil then return nil end
    local text = tostring(name or "")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    if text == "" or text == "nil" or text == "false" then return nil end
    local gid = tostring(groupId or "")
    if gid ~= "" and text == gid then return nil end
    if string.match(text, "^P%d+%s+BBC%d+$") or string.match(text, "^BBC%d+$") or string.match(text, "^WG%d+$") or string.match(text, "^CP%d+$") or string.match(text, "^SG%d+$") then return nil end
    text = string.gsub(text, "%s+P%d+%s+BBC%d+$", "")
    text = string.gsub(text, "%s+BBC%d+$", "")
    text = string.gsub(text, "%s+WG%d+$", "")
    text = string.gsub(text, "%s+CP%d+$", "")
    text = string.gsub(text, "%s+SG%d+$", "")
    if gid ~= "" then text = string.gsub(text, "%s+" .. gid .. "$", "") end
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    if text == "" or string.lower(text) == "npc group" then return nil end
    if string.match(text, "^NPC Group%s*") then return nil end
    return text
end

local function mr_groupSideLabel(group)
    local side = tostring(group and (group.factionSide or group.side or group.faction or group.patrolColor) or "")
    side = string.lower(side)
    if side == "red" then return "Red" end
    if side == "green" then return "Green" end
    if side == "blue" then return "Blue" end
    if group and group.hostile == true then return "Red" end
    return "Green"
end

local function mr_groupDisplayName(group, groupId, preferred)
    local cleaned = mr_cleanGroupName(preferred or (group and group.name), groupId)
    if cleaned then return cleaned end
    local sideLabel = mr_groupSideLabel(group)
    if group and (group.mercenary or group.mercenaryElite or sideLabel == "Blue") then
        if group.mercenaryHired then return "Hired blue mercenaries" end
        return "Blue mercenaries"
    end
    if group and group.inBattle then return "Battle: " .. sideLabel .. " patrol" end
    if group and (group.checkpointId or group.targetClass == "checkpoint_road_patrol" or group.state == "checkpoint_patrol") then return sideLabel .. " checkpoint patrol" end
    if group and group.roadPatrol then return sideLabel .. " road patrol" end
    if group and (group.homeBaseId or group.state == "base_patrol" or group.targetClass == "base_guard") then return sideLabel .. " base patrol" end
    return sideLabel .. " patrol"
end

local function mr_refreshGroupMarker(marker, group, groupId, gmd)
    if type(marker) ~= "table" or type(group) ~= "table" then return false end
    local changed = false
    local count = mr_groupMemberCount(group)
    local active = group.activated == true
    local queued = mr_groupHasQueuedBrain(gmd, groupId, group)

    if active and not queued and group.spawnPending ~= true then
        active = false
    end

    local virtual = group.virtual ~= false
    if not active and group.spawnPending ~= true then virtual = true end

    local function set(key, value)
        if marker[key] ~= value then marker[key] = value changed = true end
    end

    set("id", tostring(marker.id or group.id or groupId))
    set("groupId", tostring(groupId or group.id or marker.groupId))
    set("markerType", "group")
    set("x", math.floor(mr_number(group.x, marker.x) or 0))
    set("y", math.floor(mr_number(group.y, marker.y) or 0))
    set("z", math.floor(mr_number(group.z, marker.z) or 0))
    set("targetX", group.targetX)
    set("targetY", group.targetY)
    set("state", group.state or marker.state or "roaming")
    set("count", count)
    set("memberCount", count)
    set("active", active)
    set("virtual", virtual)
    set("spawnPending", group.spawnPending == true)
    set("spawnQueued", mr_number(group.spawnQueued, 0) or 0)
    set("leader", group.leader == true or group.isFactionLeader == true or group.leaderId ~= nil)
    set("isFactionLeader", group.isFactionLeader == true or group.leaderId ~= nil)
    set("leaderId", group.leaderId)
    set("leaderName", group.leaderName)
    set("leaderRole", group.leaderRole)
    set("leaderSide", group.leaderSide)
    set("leaderState", group.leaderState)
    set("name", mr_groupDisplayName(group, groupId, marker.name))
    set("displayName", marker.name)
    set("updatedAt", group.updatedAt or marker.updatedAt or mr_nowHours())
    set("markerReconciledAt", mr_nowHours())
    return changed
end

function NPCMarkerReconciliationBridge.ReconcileServerMarker(gmd, id, marker, opts)
    opts = opts or {}
    if type(marker) ~= "table" then return "remove", nil, "not_table" end
    if not mr_hasCoords(marker) then return "remove", nil, "invalid_coords" end

    local mtype = mr_markerType(marker)
    if mtype == "npc" then
        if not mr_markerHasLiveRuntime(gmd, marker) then return "remove", nil, "dead_npc_marker" end
        marker.markerReconciledAt = mr_nowHours()
        return "keep", marker, nil
    end

    if mtype == "group" then
        local groupId = mr_groupId(id, marker)
        local group = mr_getGroup(gmd, groupId)
        if type(group) ~= "table" then return "remove", nil, "missing_group" end
        if group.removed == true or group.deleted == true or mr_groupMemberCount(group) <= 0 then return "remove", nil, "empty_group" end
        local changed = mr_refreshGroupMarker(marker, group, groupId, gmd)
        return changed and "update" or "keep", marker, nil
    end

    if mtype == "leader" then
        if mr_isRemovedState(marker.leaderState or marker.state or marker.status) or marker.dead == true then
            return "remove", nil, "dead_leader"
        end
        local attachedGroupId = mr_nonempty(marker.attachedGroupId or marker.groupId)
        if attachedGroupId then
            local group = mr_getGroup(gmd, attachedGroupId)
            if type(group) ~= "table" or mr_groupMemberCount(group) <= 0 or group.removed == true or group.deleted == true then
                return "remove", nil, "missing_leader_group"
            end
            if gmd and type(gmd.DebugMapMarkers) == "table" and type(gmd.DebugMapMarkers[tostring(attachedGroupId)]) == "table" then
                return "remove", nil, "duplicate_attached_leader"
            end
        end
        local leaderId = mr_nonempty(marker.leaderId or marker.id)
        if leaderId and string.sub(leaderId, 1, 7) == "leader_" then leaderId = string.sub(leaderId, 8) end
        local leader = mr_findLeaderRecord(gmd, leaderId)
        local alive = mr_leaderAlive(leader)
        if alive == false then return "remove", nil, "leader_not_alive" end
        if alive == nil and marker.updatedAt then
            local ttl = mr_number(opts.leaderTtlHours, NPCMarkerReconciliationBridge.DefaultLeaderTtlHours)
            if ttl and ttl > 0 and mr_nowHours() - (mr_number(marker.updatedAt, 0) or 0) > ttl then
                return "remove", nil, "leader_ttl"
            end
        end
        marker.markerReconciledAt = mr_nowHours()
        return "keep", marker, nil
    end

    return "keep", marker, nil
end

function NPCMarkerReconciliationBridge.ReconcileServerMarkers(gmd, opts)
    if not (gmd and type(gmd.DebugMapMarkers) == "table") then return 0 end
    opts = opts or {}
    local limit = mr_number(opts.maxMarkers or opts.limit, NPCMarkerReconciliationBridge.DefaultServerBudget)
    local sendRemove = opts.sendRemove
    local sendUpdate = opts.sendUpdate
    local changed = 0
    local scanned = 0
    local removeIds = {}
    local updateIds = {}

    for id, marker in pairs(gmd.DebugMapMarkers) do
        if scanned >= limit then break end
        scanned = scanned + 1
        local action, reconciled = NPCMarkerReconciliationBridge.ReconcileServerMarker(gmd, id, marker, opts)
        if action == "remove" then
            removeIds[#removeIds + 1] = tostring(id)
        elseif action == "update" and type(reconciled) == "table" then
            gmd.DebugMapMarkers[tostring(id)] = reconciled
            updateIds[#updateIds + 1] = tostring(id)
        end
    end

    for _, id in ipairs(removeIds) do
        gmd.DebugMapMarkers[id] = nil
        if sendRemove then pcall(function() sendRemove(id) end) end
        changed = changed + 1
    end

    for _, id in ipairs(updateIds) do
        if sendUpdate and type(gmd.DebugMapMarkers[id]) == "table" then
            pcall(function() sendUpdate(gmd.DebugMapMarkers[id]) end)
        end
        changed = changed + 1
    end

    gmd.MarkerReconciliation = type(gmd.MarkerReconciliation) == "table" and gmd.MarkerReconciliation or {}
    gmd.MarkerReconciliation.lastAt = mr_nowHours()
    gmd.MarkerReconciliation.lastReason = tostring(opts.reason or "marker_reconcile")
    gmd.MarkerReconciliation.lastChanged = changed
    gmd.MarkerReconciliation.version = NPCMarkerReconciliationBridge.Version
    return changed
end

function NPCMarkerReconciliationBridge.ReconcileClientMarkers(markers, opts)
    if type(markers) ~= "table" then return 0 end
    opts = opts or {}
    local limit = mr_number(opts.maxMarkers or opts.limit, NPCMarkerReconciliationBridge.DefaultClientBudget)
    local now = mr_nowHours()
    local leaderTtl = mr_number(opts.leaderTtlHours, NPCMarkerReconciliationBridge.DefaultLeaderTtlHours)
    local changed = 0
    local scanned = 0
    local removeIds = {}

    for id, marker in pairs(markers) do
        if scanned >= limit then break end
        scanned = scanned + 1
        if type(marker) ~= "table" or not mr_hasCoords(marker) then
            removeIds[#removeIds + 1] = tostring(id)
        else
            local mtype = mr_markerType(marker)
            if mtype == "npc" and marker.dead == true then
                removeIds[#removeIds + 1] = tostring(id)
            elseif mtype == "leader" then
                local attachedGroupId = mr_nonempty(marker.attachedGroupId or marker.groupId)
                if marker.dead == true or mr_isRemovedState(marker.leaderState or marker.state or marker.status) then
                    removeIds[#removeIds + 1] = tostring(id)
                elseif attachedGroupId and type(markers[tostring(attachedGroupId)]) == "table" then
                    removeIds[#removeIds + 1] = tostring(id)
                elseif leaderTtl and leaderTtl > 0 and marker.updatedAt and now - (mr_number(marker.updatedAt, 0) or 0) > leaderTtl then
                    removeIds[#removeIds + 1] = tostring(id)
                end
            elseif mtype == "group" then
                local count = mr_number(marker.count or marker.memberCount, nil)
                if marker.dead == true then
                    removeIds[#removeIds + 1] = tostring(id)
                elseif marker.active == true and count ~= nil and count <= 0 and marker.spawnPending ~= true then
                    marker.active = false
                    marker.virtual = true
                    marker.markerReconciledGhost = true
                    marker.markerReconciledAt = now
                    changed = changed + 1
                elseif marker.active == true and marker.virtual ~= false and marker.spawnPending ~= true and marker.physicalIds == nil and marker.runtimeId == nil then
                    marker.markerReconciledAt = now
                end
            end
        end
    end

    for _, id in ipairs(removeIds) do
        markers[id] = nil
        changed = changed + 1
    end

    return changed
end

return NPCMarkerReconciliationBridge
