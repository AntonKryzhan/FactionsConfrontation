-- NPCIntelDossierServerBridge.lua
-- Server hooks for passive enemy-base intelligence dossier progress.

if isClient and isClient() then return end

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCIntelDossierBridge"

NPCIntelDossierServerBridge = NPCIntelDossierServerBridge or {}

local function bids_halo(player, text, r, g, b)
    if player and text and sendServerCommand then
        sendServerCommand(player, 'NPCIntelDossier', 'Result', {text=text, r=r or 180, g=g or 230, b=b or 255})
    end
end

local function bids_players()
    local out = {}
    if getOnlinePlayers then
        local okList, list = pcall(function() return getOnlinePlayers() end)
        if okList and list and list.size and list.get then
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

function NPCIntelDossierServerBridge.EveryTenMinutes()
    if not (NPCIntelDossierBridge and NPCIntelDossierBridge.IsEnabled and NPCIntelDossierBridge.IsEnabled()) then return end
    local gmd = GetNPCModData and GetNPCModData() or nil
    if not (gmd and type(gmd.BaseCamps) == "table") then return end
    local changed = false
    for _, player in ipairs(bids_players()) do
        for _, base in pairs(gmd.BaseCamps) do
            local result = NPCIntelDossierBridge.TryGrantBaseProbe(gmd, player, base)
            if result then
                changed = true
                if result.text then bids_halo(player, result.text, 190, 230, 120) end
            end
        end
    end
    if changed and TransmitNPCModData then TransmitNPCModData() end
end

function NPCIntelDossierServerBridge.OnClientCommand(module, command, player, args)
    if not NPCLegacyContractBridge.IsModule(module, "NPCIntelDossier", "intelDossier") then return end
    if command == "Status" then
        local gmd = GetNPCModData and GetNPCModData() or nil
        local counts = NPCIntelDossierBridge and NPCIntelDossierBridge.CountSellable and NPCIntelDossierBridge.CountSellable(player) or {total=0}
        bids_halo(player, "Intel dossiers in inventory: " .. tostring(counts.total or 0) .. ".", 180, 230, 255)
    end
end

function NPCIntelDossierServerBridge.Install()
    if NPCIntelDossierServerBridge.__installed then return end
    NPCIntelDossierServerBridge.__installed = true
    Events.EveryTenMinutes.Add(NPCIntelDossierServerBridge.EveryTenMinutes)
    Events.OnClientCommand.Add(NPCIntelDossierServerBridge.OnClientCommand)
end
