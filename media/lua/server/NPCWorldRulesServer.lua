-- NPCWorldRulesServer.lua
-- Stage 311 compatibility facade.
-- NPCServer/NPCWorldRulesServerBridge.lua is the single authoritative command
-- handler.  This facade keeps old references working without registering a
-- second Events.OnClientCommand listener.

if isClient and isClient() then return end

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCServer/NPCWorldRulesServerBridge"

NPCWorldRulesServer = NPCWorldRulesServerBridge or NPCWorldRulesServer or {}
NPCLegacyGlobalsBridge.InstallAlias("WorldRulesServer", NPCWorldRulesServer, "NPCWorldRulesServer")
