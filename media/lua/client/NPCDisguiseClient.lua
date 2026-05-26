require "NPCClient/NPCDisguiseClientBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCDisguiseClient = NPCLegacyGlobalsBridge.InstallAlias("DisguiseClient", NPCDisguiseClient, "NPCDisguiseClient")

for key, value in pairs(NPCDisguiseClient) do
    if NPCDisguiseClientBridge[key] == nil then
        NPCDisguiseClientBridge[key] = value
    end
end

setmetatable(NPCDisguiseClient, {
    __index = NPCDisguiseClientBridge,
    __newindex = function(_, key, value)
        NPCDisguiseClientBridge[key] = value
    end
})

NPCDisguiseClient.Set = NPCDisguiseClientBridge.Set
NPCDisguiseClient.Clear = NPCDisguiseClientBridge.Clear
NPCDisguiseClient.AddMenu = NPCDisguiseClientBridge.AddMenu
NPCDisguiseClient.OnServerCommand = NPCDisguiseClientBridge.OnServerCommand
NPCDisguiseClient.Install = NPCDisguiseClientBridge.Install

NPCDisguiseClient.Install()
