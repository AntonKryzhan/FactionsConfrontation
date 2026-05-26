require "NPCClient/NPCConvoysClientBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCConvoysClient = NPCLegacyGlobalsBridge.InstallAlias("ConvoysClient", NPCConvoysClient, "NPCConvoysClient")

for key, value in pairs(NPCConvoysClient) do
    if NPCConvoysClientBridge[key] == nil then
        NPCConvoysClientBridge[key] = value
    end
end

setmetatable(NPCConvoysClient, {
    __index = NPCConvoysClientBridge,
    __newindex = function(_, key, value)
        NPCConvoysClientBridge[key] = value
    end
})

NPCConvoysClient.RequestOperation = NPCConvoysClientBridge.RequestOperation
NPCConvoysClient.CompleteEscort = NPCConvoysClientBridge.CompleteEscort
NPCConvoysClient.RaidConvoy = NPCConvoysClientBridge.RaidConvoy
NPCConvoysClient.OnFillWorldObjectContextMenu = NPCConvoysClientBridge.OnFillWorldObjectContextMenu
NPCConvoysClient.OnServerCommand = NPCConvoysClientBridge.OnServerCommand
NPCConvoysClient.Install = NPCConvoysClientBridge.Install

NPCConvoysClient.Install()
