require "NPCCore/NPCLegacyContractBridge"

NPCTrueCrawlCompatBridge = NPCTrueCrawlCompatBridge or {}
local NPC_TRUECRAWL_LEGACY_KEYS = {
    npcFlag = NPCLegacyContractBridge.Key("FLAG")
}

local function HasTrueCrawl()
    if not getActivatedMods then return false end
    local ok, mods = pcall(getActivatedMods)
    if not ok or not mods or type(mods.contains) ~= "function" then return false end
    return mods:contains("TrueCrawl") == true
end

local function OnZombieUpdate(zombie)
    if not SandboxVars or not SandboxVars.TrueCrawl then return end
    if not SandboxVars.TrueCrawl.StealhModeEnable == true then return end
    if not SandboxVars.TrueCrawl.StealhModeServer == false then return end

    -- prevents TrueCrawl modification of useless status for NPC survivors.
    if zombie and zombie:getVariableBoolean(NPC_TRUECRAWL_LEGACY_KEYS.npcFlag) then return end

    if SandboxVars.TrueCrawl.StealhModeEnable == true then
        if SandboxVars.TrueCrawl.StealhModeServer == false then
            if TC_Stealth == true then
                zombie:setUseless(true)
            elseif TC_Stealth == false then
                zombie:setUseless(false)
            end
        end
    end
end

function NPCTrueCrawlCompatBridge.OnZombieUpdate(zombie)
    return OnZombieUpdate(zombie)
end

function NPCTrueCrawlCompatBridge.Install()
    if not HasTrueCrawl() then return false end

    if SandboxVars and SandboxVars.TrueCrawl then
        SandboxVars.TrueCrawl.StealhModeEnable = false
    end

    print("TrueCrawl patched successfully!")
    return true
end
