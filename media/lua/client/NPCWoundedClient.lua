require "NPCClient/NPCWoundedClientBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCWoundedClient = NPCLegacyGlobalsBridge.InstallAlias("WoundedClient", NPCWoundedClient, "NPCWoundedClient")

for key, value in pairs(NPCWoundedClient) do
    if NPCWoundedClientBridge[key] == nil then
        NPCWoundedClientBridge[key] = value
    end
end

setmetatable(NPCWoundedClient, {
    __index = NPCWoundedClientBridge,
    __newindex = function(_, key, value)
        NPCWoundedClientBridge[key] = value
    end
})

NPCWoundedClient.Stabilize = NPCWoundedClientBridge.Stabilize
NPCWoundedClient.Evacuate = NPCWoundedClientBridge.Evacuate
NPCWoundedClient.Abandon = NPCWoundedClientBridge.Abandon
NPCWoundedClient.OnHitZombie = NPCWoundedClientBridge.OnHitZombie
NPCWoundedClient.OnZombieUpdate = NPCWoundedClientBridge.OnZombieUpdate
NPCWoundedClient.OnFillWorldObjectContextMenu = NPCWoundedClientBridge.OnFillWorldObjectContextMenu
NPCWoundedClient.OnServerCommand = NPCWoundedClientBridge.OnServerCommand
NPCWoundedClient.Install = NPCWoundedClientBridge.Install

NPCWoundedClient.Install()
