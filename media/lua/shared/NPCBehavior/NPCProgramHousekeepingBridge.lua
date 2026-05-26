NPCProgramHousekeepingBridge = NPCProgramHousekeepingBridge or {}

require "NPCCore/NPCLegacyContractBridge"

local NPC_PROGRAM_LEGACY_ENTITY_GLOBAL = NPCLegacyContractBridge.Key("FLAG")

local function npcEntityCall(name, ...)
    local entity = NPCEntity or (_G and _G[NPC_PROGRAM_LEGACY_ENTITY_GLOBAL]) or nil
    local fn = entity and entity[name]
    if type(fn) ~= "function" then return nil end
    return fn(...)
end

local DEFAULT_TRASH = {
    "Base.BeerCanEmpty",
    "Base.PopEmpty",
    "Base.Pop2Empty",
    "Base.Pop3Empty",
    "Base.WineEmpty",
    "Base.WineEmpty2",
    "Base.BeerEmpty",
    "Base.WaterBottleEmpty",
    "Base.BleechEmpty",
    "Base.RemouladeEmpty",
    "Base.WhiskeyEmpty",
    "Base.PopBottleEmpty",
    "Base.RippedSheetsDirty",
    "Base.TinCanEmpty",
    "Base.UnusableWood",
    "Base.UnusableMetal",
}

local function getItem(bandit, itemTypeTab, cnt)
    return NPCProgramHelpersBridge.GetItem(bandit, itemTypeTab, cnt)
end

local function housekeepingTable(housekeeping)
    if housekeeping then return housekeeping end
    if NPCPrograms then
        NPCPrograms.Housekeeping = NPCPrograms.Housekeeping or {}
        return NPCPrograms.Housekeeping
    end
    return NPCProgramHousekeepingBridge
end

function NPCProgramHousekeepingBridge.ApplyDefaults(housekeeping)
    housekeeping = housekeepingTable(housekeeping)
    housekeeping.trash = {}
    for _, itemType in ipairs(DEFAULT_TRASH) do
        table.insert(housekeeping.trash, itemType)
    end
    return housekeeping.trash
end

local function ensureTrash(housekeeping)
    housekeeping = housekeepingTable(housekeeping)
    if not housekeeping.trash or #housekeeping.trash == 0 then
        NPCProgramHousekeepingBridge.ApplyDefaults(housekeeping)
    end
    return housekeeping.trash
end

function NPCProgramHousekeepingBridge.PredicateTrash(item)
    for _, itemType in pairs(ensureTrash()) do
        if item:getFullType() == itemType then
	        return true
        end
    end
    return false
end

function NPCProgramHousekeepingBridge.CleanBlood(bandit)
    local tasks = {}

    local square = NPCBaseClient.GetBlood(bandit)
    if not square then return tasks end

    local inventory = bandit:getInventory()

    itemMopType = "Base.Broom"
    itemBleachType = "Base.Bleach"

    local itemMop = inventory:getItemFromType(itemMopType)
    local itemBleach = inventory:getItemFromType(itemBleachType)

    if itemMop and itemBleach then
        local dist = NPCUtils.DistTo(bandit:getX(), bandit:getY(), square:getX() + 0.5, square:getY() + 0.5)
        if dist > 0.80 then
            -- bandit:addLineChatElement(("go clean blood"), 1, 1, 1)
            table.insert(tasks, NPCUtils.GetMoveTask(0, square:getX(), square:getY(), square:getZ(), "Walk", dist, false))
            return tasks
        else
            -- bandit:addLineChatElement(("clean blood"), 1, 1, 1)
            local task1 = {action="Equip", itemPrimary=itemMopType}
            table.insert(tasks, task1)

            local task2 = {action="CleanBlood", anim="Rake", itemType=itemMopType, x=square:getX(), y=square:getY(), z=square:getZ(), time=300}
            table.insert(tasks, task2)

            local task3 = {action="Equip", itemPrimary=npcEntityCall("GetBestWeapon", bandit)}
            table.insert(tasks, task3)

            return tasks
        end
    end

    -- get tools
    local itemType
    if not itemBleach then itemType = itemBleachType end
    if not itemMop then itemType = itemMopType end

    if itemType then
        local task = getItem(bandit, {itemType}, 1)
        if task then
            table.insert(tasks, task)
        end
    end

    return tasks
end

function NPCProgramHousekeepingBridge.RemoveTrash(bandit)
    local tasks = {}

    local trashcan = NPCBaseClient.GetTrashcan(bandit)
    if not trashcan then return tasks end

    -- put trash in the trashcan
    local inventory = bandit:getInventory()
    local items = ArrayList.new()
    inventory:getAllEvalRecurse(NPCPrograms.Housekeeping.PredicateTrash, items)
    if items:size() >= 7 then
        local item = items:get(0)
        local itemType = item:getFullType()
        local square = trashcan:getSquare()
        local asquare = AdjacentFreeTileFinder.Find(square, bandit)
        if asquare then
            local dist = NPCUtils.DistTo(bandit:getX(), bandit:getY(), asquare:getX() + 0.5, asquare:getY() + 0.5)
            if dist > 0.90 then
                -- bandit:addLineChatElement(("go to throw away trash"), 1, 1, 1)
                table.insert(tasks, NPCUtils.GetMoveTask(0, asquare:getX(), asquare:getY(), asquare:getZ(), "Walk", dist, false))
                return tasks
            else
                for i=0, items:size()-1 do
                    -- bandit:addLineChatElement(("throw away trash"), 1, 1, 1)
                    local item = items:get(i)
                    local itemType = item:getFullType()
                    local task = {action="PutInContainer", anim="Loot", itemType=itemType, x=square:getX(), y=square:getY(), z=square:getZ()}
                    table.insert(tasks, task)
                end
                return tasks
            end
        end
    end

    -- collect trash
    local task = getItem(bandit, ensureTrash(), 1)
    if task then
        table.insert(tasks, task)
    end

    return tasks
end

function NPCProgramHousekeepingBridge.FillGraves(bandit)
    local tasks = {}

    local grave = NPCBaseClient.GetGrave(bandit, true)
    if not grave then return tasks end

    -- fill grave
    local itemType = "Base.Shovel"
    local inventory = bandit:getInventory()
    if inventory:getItemCountFromTypeRecurse(itemType) > 0 then
        local dist = NPCUtils.DistTo(bandit:getX(), bandit:getY(), grave:getX() + 0.5, grave:getY() + 0.5)
        if dist > 0.90 then
            table.insert(tasks, NPCUtils.GetMoveTask(0, grave:getX(), grave:getY(), grave:getZ(), "Walk", dist, false))
            return tasks
        else
            local task1 = {action="Equip", itemPrimary=itemType}
            table.insert(tasks, task1)

            local task = {action="FillGrave", anim="DigShovel", sound="Shoveling", itemType=itemType, time=400, x=grave:getX(), y=grave:getY(), z=grave:getZ()}
            table.insert(tasks, task)

            local task3 = {action="Equip", itemPrimary=npcEntityCall("GetBestWeapon", bandit)}
            table.insert(tasks, task3)

            return tasks
        end
    end

    -- go take shovel
    local itemType = "Base.Shovel"
    local task = getItem(bandit, {itemType}, 1)
    if task then
        table.insert(tasks, task)
    end

    return tasks
end

function NPCProgramHousekeepingBridge.RemoveCorpses(bandit)
    local tasks = {}

    local grave = NPCBaseClient.GetGrave(bandit, false)
    if not grave then return tasks end

    -- return with deadbody
    local itemType = "Base.CorpseMale"
    local inventory = bandit:getInventory()
    if inventory:getItemCountFromTypeRecurse(itemType) > 0 then
        local dist = NPCUtils.DistTo(bandit:getX(), bandit:getY(), grave:getX() + 0.5, grave:getY() + 0.5)
        if dist > 0.90 then
            table.insert(tasks, NPCUtils.GetMoveTask(0, grave:getX(), grave:getY(), grave:getZ(), "Walk", dist, false))
            return tasks
        else
            local task = {action="BuryCorpse", anim="LootLow", sound="BodyHitGround", x=grave:getX(), y=grave:getY(), z=grave:getZ()}
            table.insert(tasks, task)
            return tasks
        end
    end
    
    -- go take deadbody
    local deadbody = NPCBaseClient.GetDeadbody(bandit)
    if not deadbody then return tasks end

    local square = obj
    local dist = NPCUtils.DistTo(bandit:getX(), bandit:getY(), deadbody:getX() + 0.5, deadbody:getY() + 0.5)
    if dist > 0.90 then
        table.insert(tasks, NPCUtils.GetMoveTask(0, deadbody:getX(), deadbody:getY(), deadbody:getZ(), "Walk", dist, false))
        return tasks
    else
        local task = {action="PickUpBody", anim="LootLow", itemType=itemType, x=deadbody:getX(), y=deadbody:getY(), z=deadbody:getZ()}
        table.insert(tasks, task)
        return tasks
    end

    return tasks
end
