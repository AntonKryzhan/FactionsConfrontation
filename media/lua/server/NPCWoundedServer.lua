-- NPCWoundedServer.lua
-- Stage 311 compatibility facade.
-- The authoritative wounded server command handler lives in
-- NPCServer/NPCWoundedServerBridge.lua.  This file intentionally does not
-- register Events.OnClientCommand, preventing double handling of wounded orders.

if isClient and isClient() then return end

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCServer/NPCWoundedServerBridge"

NPCWoundedServer = NPCWoundedServerBridge or NPCWoundedServer or {}
NPCLegacyGlobalsBridge.InstallAlias("WoundedServer", NPCWoundedServer, "NPCWoundedServer")
