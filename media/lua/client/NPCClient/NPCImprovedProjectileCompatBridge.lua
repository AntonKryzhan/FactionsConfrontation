NPCImprovedProjectileCompatBridge = NPCImprovedProjectileCompatBridge or {}

local function HasImprovedProjectile()
    if not getActivatedMods then return false end
    local ok, mods = pcall(getActivatedMods)
    if not ok or not mods or type(mods.contains) ~= "function" then return false end
    return mods:contains("ImprovedProjectile") == true
end

function NPCImprovedProjectileCompatBridge.InitCurrentInfoPatched(player, weapon)
    if player and instanceof(player, 'IsoPlayer') and player:isLocalPlayer() then
        if ImprovedProjectile.isValid and weapon and currWeapon and weapon == currWeapon then return end

        ImprovedProjectile:initCurrInfo(player, weapon)
        currWeapon = weapon
    end
end

function NPCImprovedProjectileCompatBridge.InitExplosiveInfoPatched(player, weapon)
    if player and instanceof(player, 'IsoPlayer') and player:isLocalPlayer() then
        if weapon and ImprovedProjectile.exploInfo["weaponName"] and ImprovedProjectile.exploInfo["weaponName"] == weapon:getFullType() then
            if isClient() and (weapon:getModData().SpriteCLOSED and weapon:getWeaponSprite() == weapon:getModData().SpriteCLOSED) then
                sendClientCommand("IPPJ", "clearPhysicsObject", {player:getOnlineID(), weapon:getFullType()})
            end
            return
        end

        if weapon and instanceof(weapon, "HandWeapon") then
            local savedInfo = weapon:getModData().IPPJSaveInfo
            if savedInfo then
                weapon:setMinRange(savedInfo[1])
                weapon:setMaxRange(savedInfo[2])
                weapon:setMaxHitCount(savedInfo[3])
                weapon:setSwingSound(savedInfo[4])
                weapon:getModData().IPPJSaveInfo = nil
                weapon:getModData().IPPJPresetType = nil
            end
        end

        ImprovedProjectile:initExploInfo(player, weapon)
        if isClient() and ImprovedProjectile.isValidExplo and ImprovedProjectile.exploInfo["physicsObject"] then
            sendClientCommand("IPPJ", "clearPhysicsObject", {player:getOnlineID(), weapon:getFullType()})
        end
    end
end

function NPCImprovedProjectileCompatBridge.Install()
    if not HasImprovedProjectile() then return false end
    if not Events or not Events.OnEquipPrimary or type(Events.OnEquipPrimary.Add) ~= "function" then return false end

    local old_add = Events.OnEquipPrimary.Add
    Events.OnEquipPrimary.Add = function(func)
        -- intentionally suppressed while ImprovedProjectile files register their original equip hooks
    end

    require "ImprovedProjectile_00_options"
    require "ImprovedProjectile_01_main"
    require "ImprovedProjectile_02_init"
    require "ImprovedProjectile_03_blockcheck"
    require "ImprovedProjectile_04_crosshair"
    require "ImprovedProjectile_05_explosive"

    Events.OnEquipPrimary.Add = old_add
    Events.OnEquipPrimary.Add(initCurrInfoPatched)
    Events.OnEquipPrimary.Add(initExploInfoPatched)

    return true
end
