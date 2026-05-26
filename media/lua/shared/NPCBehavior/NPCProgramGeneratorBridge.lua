NPCProgramGeneratorBridge = NPCProgramGeneratorBridge or {}

require "NPCCore/NPCLegacyContractBridge"

local NPC_PROGRAM_LEGACY_ENTITY_GLOBAL = NPCLegacyContractBridge.Key("FLAG")

local function npcEntityCall(name, ...)
    local entity = NPCEntity or (_G and _G[NPC_PROGRAM_LEGACY_ENTITY_GLOBAL]) or nil
    local fn = entity and entity[name]
    if type(fn) ~= "function" then return nil end
    return fn(...)
end

local function getItem(bandit, itemTypeTab, cnt)
    return NPCProgramHelpersBridge.GetItem(bandit, itemTypeTab, cnt)
end

function NPCProgramGeneratorBridge.Refuel(bandit, generator)
    local tasks = {}

    local itemType = "Base.PetrolCan"

    -- return with carnister
    local inventory = bandit:getInventory()
    if inventory:getItemCountFromTypeRecurse(itemType) > 0 then
        local dist = NPCUtils.DistTo(bandit:getX(), bandit:getY(), generator:getX() + 0.5, generator:getY() + 0.5)
        if dist > 0.90 then
            table.insert(tasks, NPCUtils.GetMoveTask(0, generator:getX(), generator:getY(), generator:getZ(), "Walk", dist, false))
            return tasks
        else
            if generator:isActivated() then
                local task = {action="GeneratorToggle", anim="LootLow", x=generator:getX(), y=generator:getY(), z=generator:getZ(), status=false}
                table.insert(tasks, task)
                return tasks
            else
                local task1 = {action="Equip", itemPrimary=itemType}
                table.insert(tasks, task1)

                local task2 = {action="GeneratorRefill", anim="Refuel", x=generator:getX(), y=generator:getY(), z=generator:getZ(), status=false}
                table.insert(tasks, task2)

                local task3 = {action="Equip", itemPrimary=npcEntityCall("GetBestWeapon", bandit)}
                table.insert(tasks, task3)

                -- turn on the generator back, but not if the square is already powered
                -- this is likely to be a backup generator and we do not want redundancy
                if not generator:getSquare():haveElectricity() then
                    local task = {action="GeneratorToggle", anim="LootLow", x=generator:getX(), y=generator:getY(), z=generator:getZ(), status=true}
                    table.insert(tasks, task)
                end

                return tasks
            end
        end
    end
    
    -- go get carnister
    local task = getItem(bandit, {itemType}, 1)
    if task then
        table.insert(tasks, task)
    end
    return tasks
end

function NPCProgramGeneratorBridge.Repair(bandit, generator)
    local tasks = {}

    local itemType = "Base.ElectronicsScrap"

    local condition = generator:getCondition()
    local cnt = math.ceil((100 - condition) / 5)

    -- return with electronics
    local inventory = bandit:getInventory()
    local has = inventory:getItemCountFromTypeRecurse(itemType)
    if inventory:getItemCountFromTypeRecurse(itemType) >= cnt then
        local dist = NPCUtils.DistTo(bandit:getX(), bandit:getY(), generator:getX() + 0.5, generator:getY() + 0.5)
        if dist > 0.90 then
            table.insert(tasks, NPCUtils.GetMoveTask(0, generator:getX(), generator:getY(), generator:getZ(), "Walk", dist, false))
            return tasks
        else
            if generator:isActivated() then
                local task = {action="GeneratorToggle", anim="LootLow", x=generator:getX(), y=generator:getY(), z=generator:getZ(), status=false}
                table.insert(tasks, task)
                return tasks
            else
                local task = {action="Equip", itemPrimary=itemType}
                table.insert(tasks, task)

                local task = {action="GeneratorFix", anim="LootLow", x=generator:getX(), y=generator:getY(), z=generator:getZ()}
                table.insert(tasks, task)

                local task = {action="Equip", itemPrimary=npcEntityCall("GetBestWeapon", bandit)}
                table.insert(tasks, task)

                -- turn on the generator back, but not if the square is already powered
                -- this is likely to be a backup generator and we do not want redundancy
                if not generator:getSquare():haveElectricity() and condition > 99 then
                    local task = {action="GeneratorToggle", anim="LootLow", x=generator:getX(), y=generator:getY(), z=generator:getZ(), status=true}
                    table.insert(tasks, task)
                end

                return tasks
            end
        end
    end
    
    -- go get electronics
    local task = getItem(bandit, {itemType}, cnt)
    if task then
        table.insert(tasks, task)
    end

    return tasks
end
