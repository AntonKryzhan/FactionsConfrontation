require "NPCCore/NPCGlobalData"
require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCGlobalDataStore = NPCLegacyGlobalsBridge.InstallAlias("GlobalData", NPCGlobalDataStore, "NPCGlobalDataStore")
NPCGlobalDataPlayersStore = NPCLegacyGlobalsBridge.InstallAlias("GlobalDataPlayers", NPCGlobalDataPlayersStore, "NPCGlobalDataPlayersStore")
NPCGMD = NPCLegacyGlobalsBridge.InstallAlias("GMD", NPCGMD, "NPCGMD")

local NPC_GMD_LEGACY_FUNCTIONS = NPCLegacyContractBridge.Functions

-- Compatibility facade for the historical global ModData layer.
-- Implementation lives in NPCGlobalData so newer systems can use neutral
-- state contracts while existing runtime code keeps the same API and keys.

function NPCGMD.IsClientSafeSyncReady(...)
    return NPCGlobalData.IsClientSafeSyncReady(...)
end

function InitNPCModData(...)
    return NPCGlobalData.InitNPCModData(...)
end

function LoadNPCModData(...)
    return NPCGlobalData.LoadNPCModData(...)
end

_G[NPC_GMD_LEGACY_FUNCTIONS.initModData] = function(...)
    return InitNPCModData(...)
end

_G[NPC_GMD_LEGACY_FUNCTIONS.loadModData] = function(...)
    return LoadNPCModData(...)
end

_G[NPC_GMD_LEGACY_FUNCTIONS.getModData] = function(...)
    return NPCGlobalData.GetNPCModData(...)
end

_G[NPC_GMD_LEGACY_FUNCTIONS.getModDataPlayers] = function(...)
    return NPCGlobalData.GetNPCModDataPlayers(...)
end

_G[NPC_GMD_LEGACY_FUNCTIONS.transmitModData] = function(...)
    return NPCGlobalData.TransmitNPCModData(...)
end

_G[NPC_GMD_LEGACY_FUNCTIONS.transmitModDataPlayers] = function(...)
    return NPCGlobalData.TransmitNPCModDataPlayers(...)
end

function GetNPCModData(...)
    return NPCGlobalData.GetNPCModData(...)
end

function GetNPCModDataPlayers(...)
    return NPCGlobalData.GetNPCModDataPlayers(...)
end

function TransmitNPCModData(...)
    return NPCGlobalData.TransmitNPCModData(...)
end

function TransmitNPCModDataPlayers(...)
    return NPCGlobalData.TransmitNPCModDataPlayers(...)
end

local function bgmd_installLegacyEvents()
    if NPCGMD._eventsInstalled then return end
    NPCGMD._eventsInstalled = true

    Events.OnInitGlobalModData.Add(InitNPCModData)
    Events.OnReceiveGlobalModData.Add(LoadNPCModData)
    Events.OnCreatePlayer.Add(NPCGlobalData.OnCreatePlayer)
end

bgmd_installLegacyEvents()
