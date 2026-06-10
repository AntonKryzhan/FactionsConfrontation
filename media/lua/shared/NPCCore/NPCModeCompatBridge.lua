-- NPCModeCompatBridge.lua
-- Singleplayer/COOP/dedicated compatibility layer for local server runtime.
-- In Project Zomboid singleplayer is neither isServer() nor isClient(); server-side
-- systems must still receive NPC client/server commands locally.

NPCModeCompatBridge = NPCModeCompatBridge or {}

if NPCModeCompatBridge._loaded then return end
NPCModeCompatBridge._loaded = true

NPCModeCompatBridge.OriginalSendClientCommand = NPCModeCompatBridge.OriginalSendClientCommand or sendClientCommand
NPCModeCompatBridge.OriginalSendServerCommand = NPCModeCompatBridge.OriginalSendServerCommand or sendServerCommand
NPCModeCompatBridge.OriginalGetOnlinePlayers = NPCModeCompatBridge.OriginalGetOnlinePlayers or getOnlinePlayers
NPCModeCompatBridge._dispatchingClient = false
NPCModeCompatBridge._dispatchingServer = false

function NPCModeCompatBridge.IsSinglePlayerRuntime()
    local server = false
    local client = false
    if isServer then
        local ok, value = pcall(function() return isServer() end)
        server = ok and value == true
    end
    if isClient then
        local ok, value = pcall(function() return isClient() end)
        client = ok and value == true
    end
    return not server and not client
end

function NPCModeCompatBridge.IsServerRuntime()
    if isClient then
        local ok, value = pcall(function() return isClient() end)
        if ok and value == true then return false end
    end
    if isServer then
        local ok, value = pcall(function() return isServer() end)
        if ok and value == true then return true end
    end
    return NPCModeCompatBridge.IsSinglePlayerRuntime()
end

local function npc_mode_isNPCModule(module)
    if module == nil then return false end
    local text = tostring(module)
    if string.sub(text, 1, 3) == "NPC" then return true end
    if text == "NPCLoyalty" then return true end
    return false
end

function NPCModeCompatBridge.IsNPCModule(module)
    return npc_mode_isNPCModule(module)
end

local function npc_mode_getLocalPlayer()
    if getSpecificPlayer then
        local ok, player = pcall(function() return getSpecificPlayer(0) end)
        if ok and player then return player end
    end
    if getPlayer then
        local ok, player = pcall(function() return getPlayer() end)
        if ok and player then return player end
    end
    return nil
end

function NPCModeCompatBridge.GetLocalPlayer()
    return npc_mode_getLocalPlayer()
end

local function npc_mode_makePlayerList(player)
    local list = { _player = player }
    function list:size()
        return self._player and 1 or 0
    end
    function list:get(index)
        if tonumber(index) == 0 then return self._player end
        return nil
    end
    return list
end

function NPCModeCompatBridge.GetOnlinePlayers()
    local original = NPCModeCompatBridge.OriginalGetOnlinePlayers
    if original then
        local ok, list = pcall(original)
        if ok and list and list.size then
            local okSize, size = pcall(function() return list:size() end)
            if okSize and tonumber(size) and tonumber(size) > 0 then return list end
        end
    end
    if NPCModeCompatBridge.IsSinglePlayerRuntime() then
        return npc_mode_makePlayerList(npc_mode_getLocalPlayer())
    end
    return nil
end

function NPCModeCompatBridge.DispatchClientCommand(module, command, player, args)
    if not npc_mode_isNPCModule(module) then return false end
    if NPCModeCompatBridge._dispatchingClient then return false end
    NPCModeCompatBridge._dispatchingClient = true
    local ok = false
    if NPCClientCommandsServerBridge and NPCClientCommandsServerBridge.DispatchClientCommand then
        ok = pcall(function()
            NPCClientCommandsServerBridge.DispatchClientCommand(module, command, player or npc_mode_getLocalPlayer(), args or {})
        end)
    end
    if (not ok) and triggerEvent then
        ok = pcall(function()
            triggerEvent("OnClientCommand", module, command, player or npc_mode_getLocalPlayer(), args or {})
        end)
    end
    NPCModeCompatBridge._dispatchingClient = false
    return ok == true
end

function NPCModeCompatBridge.DispatchServerCommand(module, command, args)
    if not npc_mode_isNPCModule(module) then return false end
    if NPCModeCompatBridge._dispatchingServer then return false end
    NPCModeCompatBridge._dispatchingServer = true
    local ok = false
    if NPCNetContract and NPCNetContract.DispatchServerCommand then
        ok = pcall(function()
            NPCNetContract.DispatchServerCommand(module, command, args or {})
        end)
    end
    if (not ok) and triggerEvent then
        ok = pcall(function()
            triggerEvent("OnServerCommand", module, command, args or {})
        end)
    end
    NPCModeCompatBridge._dispatchingServer = false
    return ok == true
end

function NPCModeCompatBridge.Install()
    if NPCModeCompatBridge._installed then return end
    NPCModeCompatBridge._installed = true

    if not NPCModeCompatBridge.IsSinglePlayerRuntime() then
        return
    end

    getOnlinePlayers = function()
        return NPCModeCompatBridge.GetOnlinePlayers()
    end

    sendClientCommand = function(a, b, c, d)
        local original = NPCModeCompatBridge.OriginalSendClientCommand
        local player, module, command, args
        if type(b) == "string" and type(c) == "string" then
            player = a
            module = b
            command = c
            args = d
        else
            player = npc_mode_getLocalPlayer()
            module = a
            command = b
            args = c
        end

        if npc_mode_isNPCModule(module) then
            if NPCModeCompatBridge.DispatchClientCommand(module, command, player, args) then return end
        end

        if original then
            if type(b) == "string" and type(c) == "string" then
                return original(a, b, c, d)
            end
            return original(a, b, c)
        end
    end

    sendServerCommand = function(a, b, c, d)
        local original = NPCModeCompatBridge.OriginalSendServerCommand
        local module, command, args
        if type(b) == "string" and type(c) == "string" then
            module = b
            command = c
            args = d
        else
            module = a
            command = b
            args = c
        end

        if npc_mode_isNPCModule(module) then
            if NPCModeCompatBridge.DispatchServerCommand(module, command, args) then return end
        end

        if original then
            if type(b) == "string" and type(c) == "string" then
                return original(a, b, c, d)
            end
            return original(a, b, c)
        end
    end
end

NPCModeCompatBridge.Install()
