-- NPCHeatWantedClientBridge.lua
-- Client state cache and halo notifications for unified heat/wanted layer.

if isServer() then return end

require "NPCCore/NPCHeatWantedBridge"

NPCHeatWantedClientBridge = NPCHeatWantedClientBridge or {}

local function hwc_player()
    if getPlayer then
        local ok, player = pcall(function() return getPlayer() end)
        if ok then return player end
    end
    return nil
end

local function hwc_halo(text, r, g, b)
    local player = hwc_player()
    if not (player and text) then return end
    if HaloTextHelper then
        pcall(function() HaloTextHelper.addText(player, tostring(text), tonumber(r) or 255, tonumber(g) or 190, tonumber(b) or 80) end)
    elseif player.setHaloNote then
        pcall(function() player:setHaloNote(tostring(text), tonumber(r) or 255, tonumber(g) or 190, tonumber(b) or 80, 260) end)
    end
end

function NPCHeatWantedClientBridge.OnServerCommand(module, command, args)
    if module ~= "NPCHeatWanted" then return end
    args = args or {}
    if command == "State" then
        if NPCHeatWantedBridge and NPCHeatWantedBridge.ApplyStatePayload then
            NPCHeatWantedBridge.ApplyStatePayload(hwc_player(), args)
        end
    elseif command == "Result" then
        hwc_halo(args.text or "Wanted heat updated.", args.r, args.g, args.b)
    end
end

function NPCHeatWantedClientBridge.Install()
    if NPCHeatWantedClientBridge.__installed then return end
    NPCHeatWantedClientBridge.__installed = true
    Events.OnServerCommand.Add(NPCHeatWantedClientBridge.OnServerCommand)
end

NPCHeatWantedClientBridge.Install()
