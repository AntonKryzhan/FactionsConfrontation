require "NPCCore/NPCLegacyContractBridge"

NPCActionCleanBloodBridge = NPCActionCleanBloodBridge or {}
require "NPCCore/NPCLegacyGlobalsBridge"

local NPC_ACTION_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
NPCEntity = NPCEntity or NPC_ACTION_LEGACY_GLOBALS.Get("Entity")
NPCCompatibilityBridge = NPCCompatibilityBridge or NPC_ACTION_LEGACY_GLOBALS.Get("Compatibility")


local function getActorInventory(actor)
    if actor and type(actor.getInventory) == "function" then
        return actor:getInventory()
    end
    return nil
end

local function refreshDeathDrops(actor)
    if NPCEntity and type(NPCEntity.UpdateItemsToSpawnAtDeath) == "function" then
        NPCEntity.UpdateItemsToSpawnAtDeath(actor)
    end
end

local function faceActionTarget(actor, task)
    if actor and task and task.x and task.y and type(actor.faceLocation) == "function" then
        actor:faceLocation(task.x, task.y)
    end
end

local function stopActorSounds(actor)
    local emitter = actor and type(actor.getEmitter) == "function" and actor:getEmitter() or nil
    if emitter and type(emitter.stopAll) == "function" then
        emitter:stopAll()
    end
end

local function getActionSquare(actor, task)
    if not task or not task.x or not task.y then return nil end

    local cell = nil
    if actor and type(actor.getCell) == "function" then
        cell = actor:getCell()
    end
    if not cell and getCell then
        cell = getCell()
    end
    if not cell or type(cell.getGridSquare) ~= "function" then return nil end

    return cell:getGridSquare(task.x, task.y, task.z or 0)
end

local function setPrimaryHandItem(actor, item)
    if not actor then return end
    if NPCCompatibilityBridge and type(NPCCompatibilityBridge.SafeSetPrimaryHandItem) == "function" then
        NPCCompatibilityBridge.SafeSetPrimaryHandItem(actor, item)
    end
end

local function holdCleaningItem(actor, inventory, item, itemType)
    if not actor or not item then return end

    setPrimaryHandItem(actor, item)
    if type(actor.setVariable) == "function" then
        actor:setVariable(NPCLegacyContractBridge.Key("PRIMARY"), itemType or item:getType())
        actor:setVariable(NPCLegacyContractBridge.Key("PRIMARY_TYPE"), "twohanded")
    end
    if inventory then inventory:Remove(item) end
    refreshDeathDrops(actor)
end

local function restorePrimaryItem(actor)
    local inventory = getActorInventory(actor)
    local item = actor and type(actor.getPrimaryHandItem) == "function" and actor:getPrimaryHandItem() or nil
    if not inventory or not item then return end

    inventory:AddItem(item)
    setPrimaryHandItem(actor, nil)
    refreshDeathDrops(actor)
end

local function consumeBleachDose(actor)
    local inventory = getActorInventory(actor)
    local bleach = inventory and inventory:getItemFromType("Bleach") or nil
    if not bleach then return end

    if type(bleach.getThirstChange) == "function" and type(bleach.setThirstChange) == "function" then
        bleach:setThirstChange(bleach:getThirstChange() + 0.05)
        if bleach:getThirstChange() > -0.05 and type(bleach.Use) == "function" then
            bleach:Use()
        end
    elseif type(bleach.Use) == "function" then
        bleach:Use()
    end
end

local function playCleanSound(actor)
    if actor and type(actor.playSound) == "function" then
        actor:playSound("CleanBloodScrub")
    end
end

function NPCActionCleanBloodBridge.OnStart(zombie, task)
    if not zombie or not task or not task.itemType then return true end

    local inventory = getActorInventory(zombie)
    local item = inventory and inventory:getItemFromType(task.itemType) or nil
    if item then
        holdCleaningItem(zombie, inventory, item, task.itemType)
        playCleanSound(zombie)
    end
    return true
end

function NPCActionCleanBloodBridge.OnWorking(zombie, task)
    if not zombie or not task then return true end

    faceActionTarget(zombie, task)
    if task.time and task.time <= 0 then return true end

    if task.anim and type(zombie.getBumpType) == "function" and zombie:getBumpType() ~= task.anim then
        playCleanSound(zombie)
        if type(zombie.setBumpType) == "function" then
            zombie:setBumpType(task.anim)
        end
    end
    return false
end

function NPCActionCleanBloodBridge.OnComplete(zombie, task)
    stopActorSounds(zombie)

    local square = getActionSquare(zombie, task)
    if square and type(square.removeBlood) == "function" then
        square:removeBlood(false, false)
    end

    consumeBleachDose(zombie)
    restorePrimaryItem(zombie)
    return true
end
