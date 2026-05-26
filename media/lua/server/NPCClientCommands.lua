--
-- Compatibility facade for the legacy server command dispatcher.
-- The implementation now lives in NPCServer/NPCClientCommandsServerBridge.lua.
--

require "NPCServer/NPCClientCommandsServerBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

local npcLegacyServerRuntimeName = NPCLegacyGlobalsBridge.ResolveLegacyName("ServerRuntime")

NPCServerRuntime = NPCClientCommandsServerBridge and NPCClientCommandsServerBridge.NPCServerRuntime or NPCServerRuntime
NPCServerRuntime = NPCLegacyGlobalsBridge.InstallAlias("ServerRuntime", NPCServerRuntime or (NPCClientCommandsServerBridge and NPCClientCommandsServerBridge[npcLegacyServerRuntimeName]), "NPCServerRuntime")
