require "NPCBehavior/NPCProgramRaiderBridge"
require "NPCCore/NPCLegacyContractBridge"

_G["NPCProgram" .. NPCLegacyContractBridge.Token .. "Bridge"] = NPCProgramRaiderBridge
