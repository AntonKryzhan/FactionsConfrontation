require "NPCCore/NPCLegacyContractBridge"

-- NPCModOptionsBridge.lua
-- Neutral bridge for legacy client mod-options registration.

NPCModOptionsBridge = NPCModOptionsBridge or {}
local NPC_MOD_OPTIONS_LEGACY_TITLE = NPCLegacyContractBridge.Plural
NPCModOptionsBridge.OPTIONS = NPCModOptionsBridge.OPTIONS or {}

NPCModOptionsBridge.key_data_POSTS = NPCModOptionsBridge.key_data_POSTS or {
    key = Keyboard.KEY_G,
    name = "POSTS",
}

function NPCModOptionsBridge.Register()
    if ModOptions and ModOptions.getInstance then
        ModOptions:getInstance(NPCModOptionsBridge.OPTIONS, NPC_MOD_OPTIONS_LEGACY_TITLE, NPC_MOD_OPTIONS_LEGACY_TITLE)

        local category = "[" .. NPC_MOD_OPTIONS_LEGACY_TITLE .. "]"
        ModOptions:AddKeyBinding(category, NPCModOptionsBridge.key_data_POSTS)
    end
end

function NPCModOptionsBridge.InitModOptions()
end

function NPCModOptionsBridge.Install()
    NPCModOptionsBridge.Register()
    if Events and Events.OnGameStart then
        Events.OnGameStart.Add(NPCModOptionsBridge.InitModOptions)
    end
end

return NPCModOptionsBridge
