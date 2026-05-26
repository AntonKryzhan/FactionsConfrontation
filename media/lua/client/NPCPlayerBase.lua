require "NPCClient/NPCBaseClient"
require "NPCCore/NPCLegacyGlobalsBridge"

local previous = NPCLegacyGlobalsBridge.Get("PlayerBase")
NPCBaseClient = NPCLegacyGlobalsBridge.InstallAlias("PlayerBase", NPCBaseClient, "NPCBaseClient")

if type(previous) == "table" then
    if previous.data and not next(NPCBaseClient.data or {}) then
        NPCBaseClient.data = previous.data
    end
    if previous.const then
        NPCBaseClient.const = previous.const
    end
end

if Events and Events.OnTick and not NPCBaseClient.__updateHookInstalled then
    Events.OnTick.Add(NPCBaseClient.Update)
    NPCBaseClient.__updateHookInstalled = true
end