-- NPCWoundedServerBridge.lua
-- Neutral server backend for wounded ally state, stabilization and evacuation orders.

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

local NPC_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
local NPC_SYNC_COMMAND_MODULE = "NPCCommands"
local NPC_SYNC_UPDATE_PART_COMMAND = NPCLegacyContractBridge.Command("UPDATE_PART") or ("Update" .. NPCLegacyContractBridge.Token .. "Part")
if not isServer() then return end

require "NPCCore/NPCWoundedBridge"
require "NPCCore/NPCLoyaltyBridge"

NPCWoundedServerBridge = NPCWoundedServerBridge or {}

local function npcwounded_setDebugMarker(gmd, marker)
    local runtime = NPCServerRuntime
    local setter = runtime and runtime.SetDebugMarker or NPC_LEGACY_GLOBALS.Get("SetDebugMarker")
    if setter then return setter(gmd, marker) end
    return false
end

local function bws_halo(player, text, r, g, b)
    if player and text then sendServerCommand(player, 'NPCWounded', 'Result', {text=text, r=r or 230, g=g or 220, b=b or 160}) end
end

local function bws_now()
    return NPCWoundedBridge and NPCWoundedBridge.NowHours and NPCWoundedBridge.NowHours() or 0
end

local function bws_playerId(player)
    if NPCWoundedBridge and NPCWoundedBridge.PlayerId then return NPCWoundedBridge.PlayerId(player) end
    if NPCUtils and NPCUtils.GetCharacterID then
        local ok, id = pcall(function() return NPCUtils.GetCharacterID(player) end)
        if ok and id ~= nil then return id end
    end
    return nil
end

local function bws_queueKey(gmd, id)
    if not (gmd and gmd.Queue and id) then return nil end
    if gmd.Queue[id] then return id end
    if gmd.Queue[tostring(id)] then return tostring(id) end
    for key, brain in pairs(gmd.Queue) do
        if brain and (tostring(brain.id) == tostring(id) or tostring(brain.uid) == tostring(id) or tostring(brain.persistentId) == tostring(id)) then
            return key
        end
    end
    return nil
end

local function bws_takeMedicalItem(player)
    if not (NPCWoundedBridge and NPCWoundedBridge.RequireMedicalItem and NPCWoundedBridge.RequireMedicalItem()) then return true end
    if not (player and player.getInventory) then return false end
    local inv = player:getInventory()
    if not inv then return false end
    local types = {"Base.Bandage", "Base.AlcoholBandage", "Base.FirstAidKit", "Base.SutureNeedle", "Base.Disinfectant"}
    for _, itemType in ipairs(types) do
        if inv.getItemCountFromTypeRecurse and (tonumber(inv:getItemCountFromTypeRecurse(itemType)) or 0) > 0 then
            if NPCWoundedBridge.ConsumeMedicalItem and NPCWoundedBridge.ConsumeMedicalItem() and inv.RemoveOneOf then
                local ok = pcall(function() inv:RemoveOneOf(itemType, true) end)
                if not ok then pcall(function() inv:RemoveOneOf(itemType, false) end) end
            end
            return true
        end
    end
    return false
end

local function bws_nearestBase(gmd, x, y)
    if not (gmd and gmd.BaseCamps and x and y) then return nil end
    local best = nil
    local bestDist = nil
    local maxDist = NPCWoundedBridge and NPCWoundedBridge.EvacuationBaseRadius and NPCWoundedBridge.EvacuationBaseRadius() or 2600
    for _, base in pairs(gmd.BaseCamps) do
        local bx = tonumber(base.x)
        local by = tonumber(base.y)
        if bx and by then
            local dx = bx - x
            local dy = by - y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist <= maxDist and (not bestDist or dist < bestDist) then
                best = base
                bestDist = dist
            end
        end
    end
    return best
end

local function bws_syncBrain(id, brain)
    if not (id and brain) then return end
    sendServerCommand(NPC_SYNC_COMMAND_MODULE, NPC_SYNC_UPDATE_PART_COMMAND, {
        id=brain.id or id,
        hostile=brain.hostile,
        program=brain.program,
        order=brain.order,
        fireMode=brain.fireMode,
        rbFireMode=brain.rbFireMode,
        tasks=brain.tasks,
        health=brain.health,
        relationshipToPlayer=brain.relationshipToPlayer,
        wounded=brain.wounded,
        woundedDowned=brain.woundedDowned,
        woundedStabilized=brain.woundedStabilized,
        woundedEvacuating=brain.woundedEvacuating,
        woundedAbandoned=brain.woundedAbandoned,
        woundedState=brain.woundedState,
        woundedAt=brain.woundedAt,
        woundedExpiresAt=brain.woundedExpiresAt,
        woundedForPlayerId=brain.woundedForPlayerId,
        woundedForPlayerName=brain.woundedForPlayerName,
        woundedX=brain.woundedX,
        woundedY=brain.woundedY,
        woundedZ=brain.woundedZ,
        woundedEvacTarget=brain.woundedEvacTarget,
        loyalty=brain.loyalty,
        mercenaryLoyalty=brain.mercenaryLoyalty,
        loyaltyState=brain.loyaltyState,
        loyaltyForPlayerId=brain.loyaltyForPlayerId,
        loyaltyForPlayerName=brain.loyaltyForPlayerName,
        loyaltyReason=brain.loyaltyReason,
        loyaltyUpdatedAt=brain.loyaltyUpdatedAt,
        lastLoyaltyDelta=brain.lastLoyaltyDelta,
        lastLoyaltyReason=brain.lastLoyaltyReason,
        mercenaryHired=brain.mercenaryHired,
        mercenaryHiredBy=brain.mercenaryHiredBy,
        isPlayerGuard=brain.mercenaryHired == true
    })
end

local function bws_npcMarkerId(id)
    if id == nil then return nil end
    local sid = tostring(id)
    if sid == "" or sid == "nil" then return nil end
    if string.sub(sid, 1, 4) == "npc:" then return sid end
    return "npc:" .. sid
end

local function bws_isNpcMarker(marker)
    return type(marker) == "table" and tostring(marker.markerType or "") == "npc"
end

local function bws_sendDebugRemove(id)
    if not id then return end
    if NPCNetContract and NPCNetContract.SendDebugMapRemove then
        NPCNetContract.SendDebugMapRemove(id)
    else
        sendServerCommand('NPCDebugMap', 'Remove', {id=tostring(id)})
    end
end

local function bws_updateMarker(gmd, id, brain, args)
    if not (gmd and id and brain) then return end
    gmd.DebugMapMarkers = gmd.DebugMapMarkers or {}
    local markerId = bws_npcMarkerId(id)
    if not markerId then return end

    local marker = gmd.DebugMapMarkers[markerId]
    local oldMarkerId = nil
    if not bws_isNpcMarker(marker) then
        local legacyId = tostring(id)
        local legacy = gmd.DebugMapMarkers[legacyId]
        if bws_isNpcMarker(legacy) then
            marker = legacy
            oldMarkerId = legacyId
        end
    end
    if not marker then
        marker = {
            id=markerId,
            markerType="npc",
            runtimeId=tostring(id),
            x=tonumber(args and args.x) or tonumber(brain.woundedX) or tonumber(brain.x) or 0,
            y=tonumber(args and args.y) or tonumber(brain.woundedY) or tonumber(brain.y) or 0,
            z=tonumber(args and args.z) or tonumber(brain.woundedZ) or tonumber(brain.z) or 0,
            name=brain.fullname or brain.name or "Wounded ally"
        }
        gmd.DebugMapMarkers[markerId] = marker
    end
    marker.id = markerId
    marker.markerType = "npc"
    marker.runtimeId = tostring(id)
    marker.groupId = brain.worldGroupId or brain.groupId or marker.groupId
    marker.worldGroupId = marker.groupId
    if oldMarkerId and oldMarkerId ~= markerId and bws_isNpcMarker(gmd.DebugMapMarkers[oldMarkerId]) then
        gmd.DebugMapMarkers[oldMarkerId] = nil
        bws_sendDebugRemove(oldMarkerId)
    end
    if args and args.x and args.y then
        marker.x = tonumber(args.x) or marker.x
        marker.y = tonumber(args.y) or marker.y
        marker.z = tonumber(args.z) or marker.z or 0
    end
    marker.hostile = false
    marker.friendly = true
    marker.factionSide = "blue"
    marker.faction = "blue"
    marker.side = "blue"
    marker.patrolColor = "blue"
    marker.mercenaryHired = brain.mercenaryHired
    marker.mercenaryHiredBy = brain.mercenaryHiredBy
    marker.isPlayerGuard = brain.mercenaryHired == true
    marker.wounded = brain.wounded
    marker.woundedDowned = brain.woundedDowned
    marker.woundedState = brain.woundedState
    marker.woundedForPlayerId = brain.woundedForPlayerId
    marker.woundedExpiresAt = brain.woundedExpiresAt
    if NPCLoyaltyBridge and NPCLoyaltyBridge.MarkerFields then
        NPCLoyaltyBridge.MarkerFields(marker, brain)
    end
    marker.name = brain.wounded and ((brain.fullname or brain.name or "Mercenary") .. " [wounded]") or marker.name
    marker.updatedAt = bws_now()
    if not npcwounded_setDebugMarker(gmd, marker) then
        gmd.DebugMapMarkers[markerId] = marker
        if NPCNetContract and NPCNetContract.SendDebugMapUpdate then
            NPCNetContract.SendDebugMapUpdate(marker)
        else
            sendServerCommand('NPCDebugMap', 'Update', marker)
        end
    end
end

local function bws_update(gmd, key, brain, id, player, args)
    gmd.Queue[key] = brain
    bws_syncBrain(id or key, brain)
    bws_updateMarker(gmd, id or key, brain, args)
    if TransmitNPCModData then TransmitNPCModData() end
end

function NPCWoundedServerBridge.Downed(player, args)
    if not (NPCWoundedBridge and NPCWoundedBridge.IsEnabled and NPCWoundedBridge.IsEnabled()) then return end
    local gmd = GetNPCModData()
    if not (gmd and gmd.Queue and args and args.id) then return end
    local key = bws_queueKey(gmd, args.id)
    local brain = key and gmd.Queue[key] or nil
    if not brain then return end
    if not NPCWoundedBridge.IsEligibleBrain(brain, player) then return end
    NPCWoundedBridge.MarkDowned(brain, player, args.x, args.y, args.z, "combat wound")
    if NPCLoyaltyBridge and NPCLoyaltyBridge.OnWounded then
        NPCLoyaltyBridge.OnWounded(brain, player)
    end
    bws_update(gmd, key, brain, args.id, player, args)
    bws_halo(player, "Ally is heavily wounded.", 255, 190, 80)
end

function NPCWoundedServerBridge.Stabilize(player, args)
    local gmd = GetNPCModData()
    if not (gmd and gmd.Queue and args and args.id) then return end
    local key = bws_queueKey(gmd, args.id)
    local brain = key and gmd.Queue[key] or nil
    if not brain then return end
    if not NPCWoundedBridge.IsHiredBy(brain, player) then return end
    if not NPCWoundedBridge.IsWounded(brain) then return end
    if not bws_takeMedicalItem(player) then
        bws_halo(player, "Need bandage or medical supplies.", 255, 110, 80)
        return
    end
    NPCWoundedBridge.MarkStabilized(brain, player, "stabilized by player")
    brain.woundedStabilizedCount = (tonumber(brain.woundedStabilizedCount) or 0) + 1
    if NPCLoyaltyBridge and NPCLoyaltyBridge.OnStabilized then
        NPCLoyaltyBridge.OnStabilized(brain, player)
    end
    bws_update(gmd, key, brain, args.id, player, args)
    bws_halo(player, "Wounded ally stabilized.", 120, 255, 140)
end

function NPCWoundedServerBridge.Evacuate(player, args)
    local gmd = GetNPCModData()
    if not (gmd and gmd.Queue and args and args.id) then return end
    local key = bws_queueKey(gmd, args.id)
    local brain = key and gmd.Queue[key] or nil
    if not brain then return end
    if not NPCWoundedBridge.IsHiredBy(brain, player) then return end
    if not NPCWoundedBridge.IsWounded(brain) then return end

    local x = tonumber(args.x) or tonumber(brain.woundedX) or tonumber(brain.x) or 0
    local y = tonumber(args.y) or tonumber(brain.woundedY) or tonumber(brain.y) or 0
    local base = bws_nearestBase(gmd, x, y)
    local anchor = nil
    if base then
        anchor = {x=tonumber(base.x) or x, y=tonumber(base.y) or y, z=tonumber(base.z) or 0, baseId=base.id}
    elseif player and player.getX then
        anchor = {x=player:getX(), y=player:getY(), z=player:getZ()}
    else
        anchor = {x=x, y=y, z=tonumber(args.z) or 0}
    end
    NPCWoundedBridge.MarkEvacuating(brain, player, anchor)
    brain.woundedEvacBaseId = base and base.id or nil
    if NPCLoyaltyBridge and NPCLoyaltyBridge.OnEvacuated then
        NPCLoyaltyBridge.OnEvacuated(brain, player)
    end
    bws_update(gmd, key, brain, args.id, player, args)
    if base then
        bws_halo(player, "Evacuating wounded ally to nearest base.", 150, 230, 255)
    else
        bws_halo(player, "No base nearby. Wounded ally ordered to fall back.", 255, 210, 120)
    end
end

function NPCWoundedServerBridge.Abandon(player, args)
    local gmd = GetNPCModData()
    if not (gmd and gmd.Queue and args and args.id) then return end
    local key = bws_queueKey(gmd, args.id)
    local brain = key and gmd.Queue[key] or nil
    if not brain then return end
    if not NPCWoundedBridge.IsHiredBy(brain, player) then return end
    if not NPCWoundedBridge.IsWounded(brain) then return end
    NPCWoundedBridge.MarkAbandoned(brain, player)
    if NPCLoyaltyBridge and NPCLoyaltyBridge.OnAbandoned then
        NPCLoyaltyBridge.OnAbandoned(brain, player)
        if NPCLoyaltyBridge.ApplyToHired then
            NPCLoyaltyBridge.ApplyToHired(gmd, player, NPCLoyaltyBridge.AbandonWitnessPenalty and NPCLoyaltyBridge.AbandonWitnessPenalty() or -12, "abandoned ally", key)
            local pid = NPCLoyaltyBridge.PlayerId and NPCLoyaltyBridge.PlayerId(player) or nil
            if pid and type(gmd.Queue) == "table" then
                for qid, other in pairs(gmd.Queue) do
                    if tostring(qid) ~= tostring(key) and type(other) == "table" and other.mercenaryHired == true and tostring(other.mercenaryHiredBy or other.master or "") == tostring(pid) then
                        bws_syncBrain(qid, other)
                    end
                end
            end
        end
    end
    bws_update(gmd, key, brain, args.id, player, args)
    bws_halo(player, "Wounded ally abandoned. Mercenary loyalty decreased.", 255, 120, 90)
end

function NPCWoundedServerBridge.OnClientCommand(module, command, player, args)
    if not NPCLegacyContractBridge.IsModule(module, "NPCWounded", "wounded") then return end
    args = args or {}
    if command == "Downed" then
        NPCWoundedServerBridge.Downed(player, args)
    elseif command == "Stabilize" then
        NPCWoundedServerBridge.Stabilize(player, args)
    elseif command == "Evacuate" then
        NPCWoundedServerBridge.Evacuate(player, args)
    elseif command == "Abandon" then
        NPCWoundedServerBridge.Abandon(player, args)
    end
end

function NPCWoundedServerBridge.Install()
    if NPCWoundedServerBridge._installed then return end
    NPCWoundedServerBridge._installed = true
    Events.OnClientCommand.Add(NPCWoundedServerBridge.OnClientCommand)
end

NPCWoundedServerBridge.Install()
