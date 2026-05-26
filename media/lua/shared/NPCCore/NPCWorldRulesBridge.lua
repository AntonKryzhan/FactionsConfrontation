-- NPCWorldRulesBridge.lua
-- Neutral require target for world-rules callers. Keeps the legacy legacy NPCWorldRules facade as an alias.

require "NPCCore/NPCLegacyContractBridge"
require "NPCWorldRules"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCWorldRulesBridge = NPCWorldRulesBridge or NPCWorldRules or NPCWorldRules or {}
NPCWorldRules = NPCWorldRules or NPCWorldRulesBridge
NPCLegacyGlobalsBridge.InstallAlias("WorldRules", NPCWorldRulesBridge, "NPCWorldRulesBridge")

return NPCWorldRulesBridge
