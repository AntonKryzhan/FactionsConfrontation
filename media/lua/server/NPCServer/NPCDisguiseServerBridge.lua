-- NPCDisguiseServerBridge.lua
-- Neutral server-side persistence/sync for faction disguise state.

if isClient and isClient() then return end

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCDisguiseBridge"

NPCDisguiseServerBridge = NPCDisguiseServerBridge or {}

local function bds_playerId(player, args)
    if args and args.id ~= nil then return args.id end
    if NPCUtils and NPCUtils.GetCharacterID then
        local ok, id = pcall(function() return NPCUtils.GetCharacterID(player) end)
        if ok and id ~= nil then return id end
    end
    if player and player.getOnlineID then
        local ok, id = pcall(function() return player:getOnlineID() end)
        if ok and id ~= nil then return id end
    end
    return nil
end

local function bds_now()
    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then
            local ok, value = pcall(function() return gt:getWorldAgeHours() end)
            if ok and value then return tonumber(value) or 0 end
        end
    end
    return os.time and (os.time() / 3600) or 0
end

local function bds_side(side)
    if NPCDisguiseBridge and NPCDisguiseBridge.NormalizeSide then return NPCDisguiseBridge.NormalizeSide(side) end
    if NPCFactionBridge and NPCFactionBridge.NormalizeSide then return NPCFactionBridge.NormalizeSide(side) end
    side = tostring(side or ""):lower()
    if side == "red" or side == "green" or side == "blue" or side == "black" then return side end
    return nil
end

function NPCDisguiseServerBridge.SetDisguise(player, args)
    if type(args) ~= "table" then return end
    local id = bds_playerId(player, args)
    if id == nil then return end

    local gmd = GetNPCModDataPlayers()
    if not gmd.OnlinePlayers then gmd.OnlinePlayers = {} end

    local current = gmd.OnlinePlayers[id] or gmd.OnlinePlayers[tostring(id)] or {}
    current.id = id
    current.name = args.name or current.name

    local side = bds_side(args.side or args.disguiseSide)
    if not side then
        current.disguise = nil
        current.disguiseSide = nil
        current.disguiseExpiresAt = nil
        current.disguiseReason = nil
        current.disguiseCompromised = nil
        current.disguiseCompromisedUntil = nil
        current.disguiseUpdatedAt = bds_now()
    else
        current.disguise = {
            side = side,
            expiresAt = tonumber(args.expiresAt or args.disguiseExpiresAt),
            reason = args.reason or args.disguiseReason,
            compromised = args.compromised == true or args.disguiseCompromised == true,
            compromisedUntil = tonumber(args.compromisedUntil or args.disguiseCompromisedUntil),
            updatedAt = tonumber(args.updatedAt or args.disguiseUpdatedAt) or bds_now()
        }
        current.disguiseSide = current.disguise.side
        current.disguiseExpiresAt = current.disguise.expiresAt
        current.disguiseReason = current.disguise.reason
        current.disguiseCompromised = current.disguise.compromised == true
        current.disguiseCompromisedUntil = current.disguise.compromisedUntil
        current.disguiseUpdatedAt = current.disguise.updatedAt
    end

    gmd.OnlinePlayers[id] = current
    gmd.OnlinePlayers[tostring(id)] = current

    sendServerCommand(player, 'NPCDisguise', 'State', {
        id = id,
        name = current.name,
        side = current.disguiseSide,
        expiresAt = current.disguiseExpiresAt,
        reason = current.disguiseReason,
        compromised = current.disguiseCompromised == true,
        compromisedUntil = current.disguiseCompromisedUntil,
        updatedAt = current.disguiseUpdatedAt
    })
    TransmitNPCModDataPlayers()
end

function NPCDisguiseServerBridge.OnClientCommand(module, command, player, args)
    if not NPCLegacyContractBridge.IsModule(module, "NPCDisguise", "disguise") then return end
    if command == "SetDisguise" then
        NPCDisguiseServerBridge.SetDisguise(player, args)
    end
end

function NPCDisguiseServerBridge.Install()
    if NPCDisguiseServerBridge._installed then return end
    Events.OnClientCommand.Add(NPCDisguiseServerBridge.OnClientCommand)
    NPCDisguiseServerBridge._installed = true
end

NPCDisguiseServerBridge.Install()
