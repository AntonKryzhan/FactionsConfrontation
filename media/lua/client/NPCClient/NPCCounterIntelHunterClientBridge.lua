-- NPCCounterIntelHunterClientBridge.lua
-- Client notifications for server-side counterintelligence hunter waves.

if isServer() then return end

NPCCounterIntelHunterClientBridge = NPCCounterIntelHunterClientBridge or {}

local function cihc_player()
    if getPlayer then
        local ok, player = pcall(function() return getPlayer() end)
        if ok then return player end
    end
    return nil
end

local function cihc_halo(text, r, g, b)
    local player = cihc_player()
    if not (player and text) then return end
    if player.setHaloNote then
        pcall(function() player:setHaloNote(tostring(text), tonumber(r) or 255, tonumber(g) or 80, tonumber(b) or 80, 260) end)
    end
end

function NPCCounterIntelHunterClientBridge.OnServerCommand(module, command, args)
    if module ~= "NPCCounterIntelHunter" then return end
    args = args or {}
    if command == "Result" then
        cihc_halo(args.text or "Counterintelligence activity detected.", args.r, args.g, args.b)
    end
end

function NPCCounterIntelHunterClientBridge.Install()
    if NPCCounterIntelHunterClientBridge.__installed then return end
    NPCCounterIntelHunterClientBridge.__installed = true
    Events.OnServerCommand.Add(NPCCounterIntelHunterClientBridge.OnServerCommand)
end

NPCCounterIntelHunterClientBridge.Install()
