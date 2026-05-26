-- NPCCharacterScreenBridge.lua
-- Neutral bridge for the legacy character-screen NPC kill counter patch.

require "ISUI/ISCharacterScreen"
require "NPCCore/NPCLegacyContractBridge"

NPCCharacterScreenBridge = NPCCharacterScreenBridge or {}

local NPC_CHARACTER_SCREEN_LEGACY_TEXT_PREFIX = NPCLegacyContractBridge.Text.prefix
local NPC_CHARACTER_SCREEN_LEGACY_KILL_LABEL = NPC_CHARACTER_SCREEN_LEGACY_TEXT_PREFIX .. NPCLegacyContractBridge.Plural .. "_Killed"

function NPCCharacterScreenBridge.GetPlayer()
    if not getPlayer then return nil end

    local ok, player = pcall(getPlayer)
    if not ok then return nil end
    return player
end

function NPCCharacterScreenBridge.GetCharacterId(player)
    if not player then return nil end
    if not NPCUtils or type(NPCUtils.GetCharacterID) ~= "function" then return nil end

    local ok, id = pcall(NPCUtils.GetCharacterID, player)
    if not ok then return nil end
    return id
end

function NPCCharacterScreenBridge.GetNpcKillCount()
    if type(GetNPCModData) ~= "function" then return 0 end

    local ok, gmd = pcall(GetNPCModData)
    if not ok or not gmd or type(gmd.Kills) ~= "table" then return 0 end

    local id = NPCCharacterScreenBridge.GetCharacterId(NPCCharacterScreenBridge.GetPlayer())
    if not id then return 0 end

    return tonumber(gmd.Kills[id]) or 0
end

function NPCCharacterScreenBridge.GetKillLabel()
    if type(getText) ~= "function" then return "Hostile NPCs neutralized" end

    local text = getText(NPC_CHARACTER_SCREEN_LEGACY_KILL_LABEL)
    if not text or text == NPC_CHARACTER_SCREEN_LEGACY_KILL_LABEL then
        return "Hostile NPCs neutralized"
    end
    return text
end

function NPCCharacterScreenBridge.KillCounterEnabled()
    return SandboxVars
        and SandboxVars[NPCLegacyContractBridge.Sandbox.main]
        and SandboxVars[NPCLegacyContractBridge.Sandbox.main].General_KillCounter == true
end

function NPCCharacterScreenBridge.Render(screen)
    local original = ISCharacterScreen.render_AKKillCounterOriginal
    if type(original) == "function" then
        original(screen)
    end

    if not NPCCharacterScreenBridge.KillCounterEnabled() then return end

    local textManager = getTextManager and getTextManager()
    if not textManager then return end

    local smallFont = textManager:getFontFromEnum(UIFont.Small)
    local smallFontHgt = smallFont and smallFont:getLineHeight() or 14
    local offset = 0

    local clock = UIManager and UIManager.getClock and UIManager.getClock()
    if clock and clock:isDateVisible() then
        offset = smallFontHgt
    end

    local h = screen:getHeight() - 24
    screen:drawTextRight(NPCCharacterScreenBridge.GetKillLabel(), 115, h + offset, 1, 1, 1, 1, UIFont.Small)
    screen:drawText(tostring(NPCCharacterScreenBridge.GetNpcKillCount()), 125, h + offset, 1, 1, 1, 0.5, UIFont.Small)
    screen:setHeightAndParentHeight(h + offset + 24)
end

function NPCCharacterScreenBridge.Install()
    if not ISCharacterScreen then return end
    if not ISCharacterScreen.render_AKKillCounterOriginal then
        ISCharacterScreen.render_AKKillCounterOriginal = ISCharacterScreen.render
    end

    ISCharacterScreen.render = function(self)
        return NPCCharacterScreenBridge.Render(self)
    end
end

return NPCCharacterScreenBridge
