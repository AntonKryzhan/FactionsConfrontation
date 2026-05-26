require "NPCClient/NPCEffectsBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

local legacyEffects = NPCLegacyGlobalsBridge.Get("Effects")
NPCEffectsBridge = NPCEffectsBridge or legacyEffects or {}
NPCLegacyGlobalsBridge.InstallAlias("Effects", NPCEffectsBridge, "NPCEffectsBridge")

if type(legacyEffects) == "table" then
    for key, value in pairs(legacyEffects) do
        if NPCEffectsBridge[key] == nil then
            NPCEffectsBridge[key] = value
        end
    end
end

NPCLegacyGlobalsBridge.InstallAlias("Effects", NPCEffectsBridge, "NPCEffectsBridge")
