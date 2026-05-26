-- Neutral compatibility shim for Firearms B41 Revamped on multiplayer servers.
-- Some Firearms recipe callbacks live in client Lua files only.  Dedicated/hosted
-- servers validate recipe callback names during LoadedAfterLua, so missing globals
-- produce large error dumps even when the game remains playable.  These fallbacks
-- are intentionally small and are replaced automatically if the weapon mod defines
-- the real functions later in the load order.

local function bfrc_items_size(items)
    if not items or not items.size then return 0 end
    local ok, size = pcall(function() return items:size() end)
    if ok and size then return size end
    return 0
end

local function bfrc_items_get(items, index)
    if not items or not items.get then return nil end
    local ok, item = pcall(function() return items:get(index) end)
    if ok then return item end
    return nil
end

local function bfrc_is_aimed_firearm(item)
    if not item or not item.isAimedFirearm then return false end
    local ok, result = pcall(function() return item:isAimedFirearm() end)
    return ok and result or false
end

local function bfrc_transfer_weapon_data(source, result)
    if source and result and JFAUtil and JFAUtil.TransferWeapData then
        pcall(function() JFAUtil.TransferWeapData(source, result) end)
    end
end

local function bfrc_first_firearm(items)
    for i=0, bfrc_items_size(items)-1 do
        local item = bfrc_items_get(items, i)
        if bfrc_is_aimed_firearm(item) then
            return item
        end
    end
    return nil
end

if not onImprovisedSilencer_OnCreate then
    function onImprovisedSilencer_OnCreate(items, result, player)
        if not player or not player.getInventory then return end
        local inv = player:getInventory()
        if not inv then return end

        for i=0, bfrc_items_size(items)-1 do
            local item = bfrc_items_get(items, i)
            if item and item.getType and item:getType() == "HandTorch" and item.getUsedDelta and item:getUsedDelta() > 0 then
                local battery = inv:AddItem("Base.Battery")
                if battery and battery.setUsedDelta then
                    battery:setUsedDelta(item:getUsedDelta())
                end
            end
        end
    end
end

if not onSawnOff_OnCreate then
    function onSawnOff_OnCreate(items, result, player)
        local firearm = bfrc_first_firearm(items)
        if firearm then
            bfrc_transfer_weapon_data(firearm, result)
        end
    end
end

if not onRemoveMagWell_OnCreate then
    function onRemoveMagWell_OnCreate(items, result, player)
        onSawnOff_OnCreate(items, result, player)
        if player and player.getInventory then
            local inv = player:getInventory()
            if inv then inv:AddItem("Base.RifleMagWell") end
        end
    end
end

local function bfrc_recipe_true()
    return true
end

local function bfrc_recipe_noop(items, result, player)
    local firearm = bfrc_first_firearm(items)
    if firearm and result then
        bfrc_transfer_weapon_data(firearm, result)
    end
end

local trueCallbacks = {
    "JAY_CanDeployBayonet",
    "JAY_CanExtendBayonet",
    "JAY_CanExtendGunStock",
    "JAY_CanFixBayonet",
    "JAY_CanHolsterAsPistol",
    "JAY_CanHolsterAsRifle",
    "JAY_CanRemoveBayonet",
    "JAY_CanRetractBayonet",
    "JAY_CanRetractGunStock",
    "JAY_CanUndeployBayonet",
    "JAY_InsertGunLightBattery_Test",
    "JAY_RemoveGunLightBattery_Test",
    "JAY_UnhideSling_Test_Camo",
    "JAY_UnhideSling_Test_Leather",
    "JAY_UnhideSling_Test_Olive",
    "JAY_UnhideSling_Test_Standard"
}

for _, name in ipairs(trueCallbacks) do
    if _G[name] == nil then
        _G[name] = bfrc_recipe_true
    end
end

local noopCallbacks = {
    "JAY_DeployBayonet_Recipe",
    "JAY_ExtendBayonet_Recipe",
    "JAY_ExtendGunStock_Recipe",
    "JAY_FixBayonet_Recipe",
    "JAY_HideSling_Recipe",
    "JAY_HolsterAsPistol_Recipe",
    "JAY_HolsterAsRifle_Recipe",
    "JAY_InsertGunLightBattery_Recipe",
    "JAY_RemoveBayonet_Recipe",
    "JAY_RemoveGunLightBattery_Recipe",
    "JAY_RetractBayonet_Recipe",
    "JAY_RetractGunStock_Recipe",
    "JAY_UndeployBayonet_Recipe"
}

for _, name in ipairs(noopCallbacks) do
    if _G[name] == nil then
        _G[name] = bfrc_recipe_noop
    end
end
