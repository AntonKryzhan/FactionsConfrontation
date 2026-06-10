-- NPCSignalsServerBridge.lua
-- Neutral server-side execution for signal items and field commands.

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

local NPC_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
local NPC_SYNC_COMMAND_MODULE = "NPCCommands"
local NPC_SYNC_UPDATE_PART_COMMAND = NPCLegacyContractBridge.Command("UPDATE_PART") or ("Update" .. NPCLegacyContractBridge.Token .. "Part")
if isClient and isClient() then return end

require "NPCCore/NPCSignalsBridge"
require "NPCCommands/NPCMercenaryContract"

NPCSignalsServerBridge = NPCSignalsServerBridge or {}
local function npcserver_setDebugMarker(gmd, marker)
    local runtime = NPCServerRuntime
    local setter = runtime and runtime.SetDebugMarker or NPC_LEGACY_GLOBALS.Get("SetDebugMarker")
    if setter then return setter(gmd, marker) end
    return false
end


local function bss_halo(player, text, r, g, b)
    if player and text then sendServerCommand(player, 'NPCSignals', 'Result', {text=text, r=r or 180, g=g or 230, b=b or 255}) end
end

local function bss_now()
    return NPCSignalsBridge and NPCSignalsBridge.NowHours and NPCSignalsBridge.NowHours() or 0
end

local function bss_playerId(player)
    if NPCSignalsBridge and NPCSignalsBridge.PlayerId then return NPCSignalsBridge.PlayerId(player) end
    if NPCUtils and NPCUtils.GetCharacterID then
        local ok, id = pcall(function() return NPCUtils.GetCharacterID(player) end)
        if ok and id ~= nil then return id end
    end
    return nil
end

local function bss_anchor(player, args)
    local x = tonumber(args and args.x)
    local y = tonumber(args and args.y)
    local z = tonumber(args and args.z) or 0
    if not x and player and player.getX then x = player:getX() end
    if not y and player and player.getY then y = player:getY() end
    if player and player.getZ and not z then z = player:getZ() end
    return {x=x or 0, y=y or 0, z=z or 0}
end

local function bss_setMarker(gmd, marker)
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

local function bss_syncBrain(id, brain)
    if not (id and brain) then return end
    sendServerCommand(NPC_SYNC_COMMAND_MODULE, NPC_SYNC_UPDATE_PART_COMMAND, {
        id=brain.id or id,
        master=brain.master,
        hostile=brain.hostile,
        program=brain.program,
        order=brain.order,
        fireMode=brain.order and brain.order.fireMode or brain.fireMode,
        rbFireMode=brain.rbFireMode,
        tasks=brain.tasks,
        factionSide=brain.factionSide,
        faction=brain.faction,
        side=brain.side,
        patrolColor=brain.patrolColor,
        mercenary=brain.mercenary,
        mercenaryHired=brain.mercenaryHired,
        mercenaryHiredBy=brain.mercenaryHiredBy,
        mercenaryHiredByName=brain.mercenaryHiredByName,
        isPlayerGuard=brain.mercenaryHired == true
    })
end

local function bss_isHiredBy(groupOrBrain, player)
    if not groupOrBrain then return false end
    if NPCMercenaryContract and NPCMercenaryContract.IsHiredBy and groupOrBrain.program then
        local ok, result = pcall(function() return NPCMercenaryContract.IsHiredBy(groupOrBrain, player) end)
        if ok and result == true then return true end
    end
    local pid = tostring(bss_playerId(player) or "")
    if pid == "" then return false end
    return groupOrBrain.mercenaryHired == true and tostring(groupOrBrain.mercenaryHiredBy or groupOrBrain.master or "") == pid
end

local function bss_signalOrder(action, anchor)
    local cfg = NPCSignalsBridge and NPCSignalsBridge.Action and NPCSignalsBridge.Action(action) or nil
    cfg = cfg or {}
    return {
        orderName=cfg.orderName or "Follow",
        name=cfg.orderName or "Follow",
        fireMode=cfg.fireMode,
        formation=cfg.formation,
        followDistance=cfg.followDistance,
        anchor=anchor,
        source="signal",
        signalAction=action
    }
end

local function bss_applyToHired(gmd, player, action, anchor)
    if not (gmd and NPCMercenaryContract and NPCMercenaryContract.ApplyOrderToBrain) then return 0, 0 end
    local count = 0
    local groups = 0
    local data = bss_signalOrder(action, anchor)

    if type(gmd.Queue) == "table" then
        for id, brain in pairs(gmd.Queue) do
            if type(brain) == "table" and bss_isHiredBy(brain, player) then
                NPCMercenaryContract.ApplyOrderToBrain(brain, player, data)
                gmd.Queue[id] = brain
                bss_syncBrain(id, brain)
                count = count + 1
            end
        end
    end

    if type(gmd.VirtualGroups) == "table" and NPCMercenaryContract.ApplyOrderToGroup then
        for gid, group in pairs(gmd.VirtualGroups) do
            if type(group) == "table" and bss_isHiredBy(group, player) then
                NPCMercenaryContract.ApplyOrderToGroup(group, player, data)
                group.updatedAt = bss_now()
                gmd.VirtualGroups[gid] = group
                groups = groups + 1
                local marker = gmd.DebugMapMarkers and gmd.DebugMapMarkers[tostring(gid)]
                if marker then
                    marker.order = data.orderName
                    marker.signalAction = action
                    marker.updatedAt = bss_now()
                    bss_setMarker(gmd, marker)
                end
            end
        end
    end

    return count, groups
end

local function bss_use(player, args)
    if not (NPCSignalsBridge and NPCSignalsBridge.IsEnabled and NPCSignalsBridge.IsEnabled()) then return end
    local action = tostring(args and args.action or "")
    local gmd = GetNPCModData()
    local data = NPCSignalsBridge.EnsureData(gmd)
    if not data then return end

    local ok, reason, waitHours = NPCSignalsBridge.CanUse(gmd, player, action)
    if not ok then
        data.stats.denied = (tonumber(data.stats.denied) or 0) + 1
        if reason == "missing_item" then
            local cfg = NPCSignalsBridge.Action(action)
            bss_halo(player, "You need a " .. tostring(cfg and cfg.signalLabel or "signal item") .. ".", 255, 180, 80)
        elseif reason == "cooldown" then
            local minutes = math.max(1, math.ceil((tonumber(waitHours) or 0) * 60))
            bss_halo(player, "Field signal cooldown: " .. tostring(minutes) .. " min.", 255, 180, 80)
        else
            bss_halo(player, "Field signal unavailable.", 255, 180, 80)
        end
        return
    end

    if not NPCSignalsBridge.TakeSignalItem(player, action) then
        bss_halo(player, "Could not use signal item.", 255, 180, 80)
        return
    end

    local anchor = bss_anchor(player, args)
    local cfg = NPCSignalsBridge.Action(action) or {}
    local marker = NPCSignalsBridge.MakeMarker(gmd, action, player, anchor.x, anchor.y, anchor.z, {signalOrder=cfg.orderName, signalFireMode=cfg.fireMode})
    if marker then bss_setMarker(gmd, marker) end

    local npcCount, groupCount = bss_applyToHired(gmd, player, action, anchor)
    NPCSignalsBridge.SetCooldown(gmd, player)
    data.stats.used = (tonumber(data.stats.used) or 0) + 1
    data.stats[action] = (tonumber(data.stats[action]) or 0) + 1

    local text = tostring(cfg.markerLabel or cfg.signalLabel or action) .. " signal sent: " .. tostring(npcCount) .. " NPC / " .. tostring(groupCount) .. " groups responded."
    if action == "post" then text = "Temporary post marked: " .. tostring(npcCount) .. " NPC / " .. tostring(groupCount) .. " groups assigned." end
    NPCSignalsBridge.AddHistory(gmd, player, action, text)
    bss_halo(player, text, 180, 230, 255)
    if player and player.Say then pcall(function() player:Say(text) end) end
    TransmitNPCModData()
end

function NPCSignalsServerBridge.SendHistory(player)
    local gmd = GetNPCModData()
    local text = NPCSignalsBridge and NPCSignalsBridge.HistoryText and NPCSignalsBridge.HistoryText(gmd, player) or "No field signals used yet."
    bss_halo(player, text, 180, 230, 255)
end

function NPCSignalsServerBridge.Cleanup()
    local gmd = GetNPCModData()
    if not (gmd and NPCSignalsBridge and NPCSignalsBridge.Cleanup) then return end
    local before = {}
    if gmd.NPCSignalsBridge and type(gmd.NPCSignalsBridge.activeMarkers) == "table" then
        for id, _ in pairs(gmd.NPCSignalsBridge.activeMarkers) do before[tostring(id)] = true end
    end
    local removed = NPCSignalsBridge.Cleanup(gmd)
    if removed and removed > 0 then
        if gmd.NPCSignalsBridge and type(gmd.NPCSignalsBridge.activeMarkers) == "table" then
            for id, _ in pairs(gmd.NPCSignalsBridge.activeMarkers) do before[tostring(id)] = nil end
        end
        for id, _ in pairs(before) do
            local remover = NPC_LEGACY_GLOBALS.Get("RemoveDebugMarker")
            if remover then
                remover(gmd, id)
            else
                if gmd.DebugMapMarkers then gmd.DebugMapMarkers[id] = nil end
                if NPCNetContract and NPCNetContract.SendDebugMapRemove then
                    NPCNetContract.SendDebugMapRemove(id)
                else
                    sendServerCommand('NPCDebugMap', 'Remove', {id=id})
                end
            end
        end
        TransmitNPCModData()
    end
end

function NPCSignalsServerBridge.OnClientCommand(module, command, player, args)
    if not NPCLegacyContractBridge.IsModule(module, "NPCSignals", "signals") then return end
    if command == "Use" then
        bss_use(player, args or {})
    elseif command == "History" then
        NPCSignalsServerBridge.SendHistory(player)
    end
end

function NPCSignalsServerBridge.Install()
    if NPCSignalsServerBridge._installed then return end
    NPCSignalsServerBridge._installed = true
    Events.OnClientCommand.Add(NPCSignalsServerBridge.OnClientCommand)
    Events.EveryTenMinutes.Add(NPCSignalsServerBridge.Cleanup)
end

NPCSignalsServerBridge.Install()
