NPCActionReloadBridge = NPCActionReloadBridge or {}
require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCPersistentNPCBridge"

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
        local magSize = tonumber(weapon.magSize) or 0
        if magSize <= 0 then magSize = (task and task.slot == "secondary") and 15 or 30; weapon.magSize = magSize end
        local magCount = tonumber(weapon.magCount) or 0
        if magCount <= 0 and weapon.stage448AmmoBoost == true then
            weapon.magCount = (task and task.slot == "secondary") and 8 or 12
            magCount = tonumber(weapon.magCount) or 0
        end
        weapon.bulletsLeft = magSize
        weapon.magCount = math.max(0, magCount - 1)
        refreshDeathItems(zombie)

        if NPCEntity and NPCEntity.ForceSyncPart and brain and brain.id then
            local payload = {id=brain.id, weapons=brain.weapons}
            if NPCPersistentNPCBridge and NPCPersistentNPCBridge.BuildAmmoLite then
                local okAmmo, ammo = pcall(function() return NPCPersistentNPCBridge.BuildAmmoLite(zombie, brain) end)
                if okAmmo then
                    brain.ammo = ammo
                    payload.ammo = ammo
                end
            end
            if NPCPersistentNPCBridge and NPCPersistentNPCBridge.BuildCurrentWeapon then
                local okWeapon, currentWeapon = pcall(function() return NPCPersistentNPCBridge.BuildCurrentWeapon(zombie, brain) end)
                if okWeapon then
                    brain.currentWeapon = currentWeapon
                    payload.currentWeapon = currentWeapon
                end
            end
            NPCEntity.ForceSyncPart(zombie, payload)
        end
    end

    return true
end
