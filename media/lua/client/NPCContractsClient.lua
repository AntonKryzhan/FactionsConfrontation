require "NPCClient/NPCContractsClientBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCContractsClient = NPCLegacyGlobalsBridge.InstallAlias("ContractsClient", NPCContractsClient, "NPCContractsClient")

for key, value in pairs(NPCContractsClient) do
    if NPCContractsClientBridge[key] == nil then
        NPCContractsClientBridge[key] = value
    end
end

setmetatable(NPCContractsClient, {
    __index = NPCContractsClientBridge,
    __newindex = function(_, key, value)
        NPCContractsClientBridge[key] = value
    end
})

NPCContractsClient.RequestContract = NPCContractsClientBridge.RequestContract
NPCContractsClient.CompleteContract = NPCContractsClientBridge.CompleteContract
NPCContractsClient.AbandonContract = NPCContractsClientBridge.AbandonContract
NPCContractsClient.OnFillWorldObjectContextMenu = NPCContractsClientBridge.OnFillWorldObjectContextMenu
NPCContractsClient.OnServerCommand = NPCContractsClientBridge.OnServerCommand
NPCContractsClient.Install = NPCContractsClientBridge.Install

NPCContractsClient.Install()
