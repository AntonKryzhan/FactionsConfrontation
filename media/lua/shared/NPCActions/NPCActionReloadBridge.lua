NPCActionReloadBridge = NPCActionReloadBridge or {}
require "NPCCore/NPCLegacyGlobalsBridge"

local NPC_ACTION_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
NPCEntity = NPCEntity or NPC_ACTION_LEGACY_GLOBALS.Get("Entity")
NPCBrainData = NPCBrainData or NPC_ACTION_LEGACY_GLOBALS.Get("Brain")


local function getBumpTypeSafe(zombie)
    if not zombie or type(zombie.getBumpType) ~= "function" then return nil end

    local ok, bump = pcall(function() return zombie:getBumpType() end)
    if ok then return bump end
    return nil
end

local function getBrain(zombie)
    if not NPCBrainData or type(NPCBrainData.Get) ~= "function" then return nil end
    if not zombie then return nil end

    local ok, brain = pcall(function() return NPCBrainData.Get(zombie) end)
    if ok then return brain end
    return nil
end

local function getWeaponForSlot(brain, task)
    if not brain or type(brain) ~= "table" then return nil end
    if not brain.weapons or type(brain.weapons) ~= "table" then return nil end
    if not task or task.slot == nil then return nil end

    return brain.weapons[task.slot]
end

local function refreshDeathItems(zombie)
    if NPCEntity and type(NPCEntity.UpdateItemsToSpawnAtDeath) == "function" and zombie then
        NPCEntity.UpdateItemsToSpawnAtDeath(zombie)
    end
end

function NPCActionReloadBridge.OnStart(zombie, task)
    return true
end

function NPCActionReloadBridge.OnWorking(zombie, task)
    if not task or not task.anim then return true end

    local bump = getBumpTypeSafe(zombie)
    if bump == nil then return true end

    if bump ~= task.anim then return true end
    return false
end

function NPCActionReloadBridge.OnComplete(zombie, task)
    local brain = getBrain(zombie)
    local weapon = getWeaponForSlot(brain, task)

    if weapon then
        weapon.bulletsLeft = weapon.magSize
        weapon.magCount = (weapon.magCount or 0) - 1
        refreshDeathItems(zombie)
    end

    return true
end
