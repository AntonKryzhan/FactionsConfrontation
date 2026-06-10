NPCActionLootWeaponsBridge = NPCActionLootWeaponsBridge or {}
require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCPersistentNPCBridge"

local NPC_ACTION_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
NPCEntity = NPCEntity or NPC_ACTION_LEGACY_GLOBALS.Get("Entity")
NPCBrainData = NPCBrainData or NPC_ACTION_LEGACY_GLOBALS.Get("Brain")


local function zaLootWeaponsAnyItem(item)
    return item ~= nil
end

local function zaLootWeaponsCollect(container)
    local items = ArrayList and ArrayList.new and ArrayList.new() or nil
    if not container or not items then return nil end
    local ok = pcall(function() container:getAllEvalRecurse(zaLootWeaponsAnyItem, items) end)
    if ok then return items end
    return nil
end

local function zaLootWeaponsRemove(container, wanted)
    if not container or not wanted then return false end
    local all = zaLootWeaponsCollect(container)
    if not all then return false end

    local removed = false
    for _, fullType in pairs(wanted) do
        for i = all:size() - 1, 0, -1 do
            local item = all:get(i)
            local okName, itemType = pcall(function() return item:getFullType() end)
            if okName and itemType == fullType then
                pcall(function() container:Remove(item) end)
                if container.removeItemOnServer then pcall(function() container:removeItemOnServer(item) end) end
                removed = true
            end
        end
    end
    return removed
end

local function zaLootWeaponsApply(zombie, task)
    if not zombie or not task or not task.toAdd then return end
    if not (NPCEntity and NPCEntity.GetWeapons and NPCEntity.SetWeapons) then return end
    local weapons = NPCEntity.GetWeapons(zombie) or {}
    for slot, data in pairs(task.toAdd) do
        weapons[slot] = data
    end
    NPCEntity.SetWeapons(zombie, weapons)

    if NPCBrainData and NPCBrainData.Get and NPCEntity.ForceSyncPart then
        local brain = NPCBrainData.Get(zombie)
        if brain and brain.id then
            local payload = {id=brain.id, weapons=weapons}
            if NPCPersistentNPCBridge then
                if NPCPersistentNPCBridge.BuildInventoryLite then
                    local okInventory, inventoryLite = pcall(function() return NPCPersistentNPCBridge.BuildInventoryLite(zombie) end)
                    if okInventory then
                        brain.inventoryLite = inventoryLite
                        payload.inventoryLite = inventoryLite
                    end
                end
                if NPCPersistentNPCBridge.BuildAmmoLite then
                    local okAmmo, ammo = pcall(function() return NPCPersistentNPCBridge.BuildAmmoLite(zombie, brain) end)
                    if okAmmo then
                        brain.ammo = ammo
                        payload.ammo = ammo
                    end
                end
                if NPCPersistentNPCBridge.BuildCurrentWeapon then
                    local okWeapon, currentWeapon = pcall(function() return NPCPersistentNPCBridge.BuildCurrentWeapon(zombie) end)
                    if okWeapon then
                        brain.currentWeapon = currentWeapon
                        payload.currentWeapon = currentWeapon
                    end
                end
            end
            NPCEntity.ForceSyncPart(zombie, payload)
        end
    end
end

local function zaLootWeaponsTryContainer(zombie, container, task)
    if not container or not task or not task.toRemove then return false end
    local empty = false
    if container.isEmpty then
        local ok, value = pcall(function() return container:isEmpty() end)
        empty = ok and value == true
    end
    if empty then return false end
    local removed = zaLootWeaponsRemove(container, task.toRemove)
    if removed then zaLootWeaponsApply(zombie, task) end
    return removed
end

local function zaLootWeaponsSquare(task)
    if not task or not getCell or task.x == nil or task.y == nil or task.z == nil then return nil end
    local cell = getCell()
    if not cell then return nil end
    return cell:getGridSquare(task.x, task.y, task.z)
end

local function zaLootWeaponsFace(zombie, task)
    if zombie and task and task.x and task.y and zombie.faceLocation then
        pcall(function() zombie:faceLocation(task.x, task.y) end)
    end
end

local function zaLootWeaponsAnimate(zombie, task)
    if not zombie or not task or not task.anim then return end
    local ok, bump = pcall(function() return zombie:getBumpType() end)
    if not ok or bump ~= task.anim then pcall(function() zombie:setBumpType(task.anim) end) end
end


NPCActionLootWeaponsBridge.OnStart = function(zombie, task)
    return true
end

NPCActionLootWeaponsBridge.OnWorking = function(zombie, task)
    zaLootWeaponsFace(zombie, task)
    if not task or (tonumber(task.time) or 0) <= 0 then return true end
    zaLootWeaponsAnimate(zombie, task)
    return false
end

NPCActionLootWeaponsBridge.OnComplete = function(zombie, task)
    local square = zaLootWeaponsSquare(task)
    if not square then return true end

    local bodies = square.getStaticMovingObjects and square:getStaticMovingObjects() or nil
    if bodies then
        for i = 0, bodies:size() - 1 do
            local object = bodies:get(i)
            if instanceof and instanceof(object, "IsoDeadBody") then
                local container = object.getContainer and object:getContainer() or nil
                if zaLootWeaponsTryContainer(zombie, container, task) then return true end
            end
        end
    end

    local objects = square.getObjects and square:getObjects() or nil
    if objects then
        for i = 0, objects:size() - 1 do
            local object = objects:get(i)
            local container = object and object.getContainer and object:getContainer() or nil
            if zaLootWeaponsTryContainer(zombie, container, task) then return true end
        end
    end

    return true
end
