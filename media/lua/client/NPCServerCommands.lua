ZSClient = ZSClient or {}
ZSClient.Commands = ZSClient.Commands or {}

require "NPCClient/NPCClientCommandBridge"

if NPCClientCommandBridge and NPCClientCommandBridge.Install then
    NPCClientCommandBridge.Install(ZSClient)
end
