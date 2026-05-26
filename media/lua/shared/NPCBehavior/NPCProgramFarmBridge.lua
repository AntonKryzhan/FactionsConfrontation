NPCProgramFarmBridge = NPCProgramFarmBridge or {}

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

local function farmTable(farm)
    if farm then return farm end
    if NPCPrograms then
        NPCPrograms.Farm = NPCPrograms.Farm or {}
        return NPCPrograms.Farm
    end
    return NPCProgramFarmBridge
end

function NPCProgramFarmBridge.ApplyDefaults(farm)
    farm = farmTable(farm)
    farm.fillables = {}
    if NPCCompatibilityBridge.GetGameVersion() < 42 then
        table.insert(farm.fillables, "farming.WateredCanFull")
        table.insert(farm.fillables, "farming.WateredCan")
    else
        table.insert(farm.fillables, "Base.WateredCan")
    end
    return farm.fillables
end

local function ensureFillables(farm)
    farm = farmTable(farm)
    if not farm.fillables or #farm.fillables == 0 then
        NPCProgramFarmBridge.ApplyDefaults(farm)
    end
    return farm.fillables
end

function NPCProgramFarmBridge.PredicateFillable(item)
    for _, itemType in pairs(ensureFillables()) do
        local d = item:getFullType()
        if item:getFullType() == itemType then
	        return true
        end
    end
    return false
end

function NPCProgramFarmBridge.Water(bandit, plant)
    local tasks = {}

    local farm = NPCBaseClient.GetFarm(bandit)
    if not farm then return tasks end

    -- water plants
    local inventory = bandit:getInventory()
    local items = ArrayList.new()
    inventory:getAllEvalRecurse(NPCProgramFarmBridge.PredicateFillable, items)
    if items:size() > 0 then
        local item = items:get(0)

        local itemType = item:getFullType()
        local water = item:getUsedDelta()
        if water > 0 then
            local dist = NPCUtils.DistTo(bandit:getX(), bandit:getY(), farm.x + 0.5, farm.y + 0.5)
            if dist > 0.80 then
                table.insert(tasks, NPCUtils.GetMoveTask(0, farm.x, farm.y, farm.z, "Walk", dist, false))
                return tasks
            else
                local task1 = {action="Equip", itemPrimary=itemType}
                table.insert(tasks, task1)

                local task2 = {action="WaterFarm", anim="PourWateringCan", itemType=itemType, x=farm.x, y=farm.y, z=farm.z}
                table.insert(tasks, task2)

                local task3 = {action="Equip", itemPrimary=npcEntityCall("GetBestWeapon", bandit)}
                table.insert(tasks, task3)

                return tasks
            end
        else
            local source = NPCBaseClient.GetWaterSource(bandit)
            if source then
                local square = source:getSquare()
                local asquare = AdjacentFreeTileFinder.Find(square, bandit)
                if asquare then
                    local dist = NPCUtils.DistTo(bandit:getX(), bandit:getY(), asquare:getX() + 0.5, asquare:getY() + 0.5)
                    if dist > 0.90 then
                        table.insert(tasks, NPCUtils.GetMoveTask(0, asquare:getX(), asquare:getY(), asquare:getZ(), "Walk", dist, false))
                        return tasks
                    else
                        local task1 = {action="Equip", itemPrimary=itemType}
                        table.insert(tasks, task1)
        
                        local task2 = {action="FillWater", anim="FillBucket", time=400, itemType=itemType, x=square:getX(), y=square:getY(), z=square:getZ()}
                        table.insert(tasks, task2)
        
                        local task3 = {action="Equip", itemPrimary=npcEntityCall("GetBestWeapon", bandit)}
                        table.insert(tasks, task3)

                        return tasks
                    end
                end
            end
        end
    end

    -- go get watering can
    local task = getItem(bandit, ensureFillables(), 1)
    if task then
        table.insert(tasks, task)
    end

    return tasks
end

function NPCProgramFarmBridge.Heal(bandit)
    
end
