require "NPCBehavior/NPCBrainDataBridge"
require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCCompatibilityBridge"
require "NPCCore/NPCUtilityCore"

NPCCore = NPCCore or {}
NPCEntityState = NPCEntityState or {}
local Entity = NPCEntityState

local NPC_ENTITY_LEGACY_KEYS = {
    commandUpdatePart = NPCLegacyContractBridge.Command("UPDATE_PART_COMMAND"),
    programNPC = NPCLegacyContractBridge.Key("FLAG"),
    sandboxSection = NPCLegacyContractBridge.Sandbox and NPCLegacyContractBridge.Sandbox.main,
    speechTextPrefix = NPCLegacyContractBridge.Text and (NPCLegacyContractBridge.Text.prefix .. "Speech_")
}

-- Neutral entity-state implementation for NPC runtime state.
-- This file owns task queues, brain flags, inventory/death-drop sync,
-- speech and visual-damage helpers without depending on the historical
-- public table name.

Entity.SoundTab = Entity.SoundTab or {}
Entity.CustomSpeechSoundsEnabled = false

local function npcRegisterSpeech(alias, prefix, randMax, chance, length)
    Entity.SoundTab[alias] = Entity.SoundTab[alias] or {
        prefix = prefix,
        randMax = randMax or 1,
        chance = chance or 100,
        length = length or 2
    }
end

local function npcSpeechTextMissing(line, key)
    if not line or line == "" then return true end
    if key and (line == key or line == ("!" .. key .. "!")) then return true end
    if key and string.find(tostring(line), tostring(key), 1, true) then return true end
    return false
end

local NPC_SPEECH_FALLBACK_CAPTIONS = {
    SPOTTED = "Contact!",
    SPOTED = "Contact!",
    HIT = "I am hit!",
    DEAD = "I am down!",
    DEATH = "Target down!",
    RELOADING = "Reloading!",
    BREACH = "Breach!",
    CAR = "Out of the vehicle!",
    BURN = "Fire on me!",
    DRAGDOWN = "They are on me!",
    INSIDE = "Target inside!",
    OUTSIDE = "Target outside!",
    UPSTAIRS = "Check upstairs!",
    KITCHEN = "Check the kitchen!",
    BATHROOM = "Check the bathroom!",
    DEFENDER_SPOTTED = "Stop! This is a secured area!",
    DEFENDER_SPOT = "Stop! This is a secured area!",
    THIEF_SPOTTED = "Drop your gear!",
    THIEF_SPOT = "Drop your gear!"
}

npcRegisterSpeech("SPOTTED", "ZSSpotted_", 6, 45, 2)
npcRegisterSpeech("SPOTED", "ZSSpotted_", 6, 45, 2)
npcRegisterSpeech("HIT", "ZSHit_", 14, 100, 2)
npcRegisterSpeech("DEAD", "ZSDead_", 6, 100, 3)
npcRegisterSpeech("DEATH", "ZSDeath_", 8, 45, 2)
npcRegisterSpeech("RELOADING", "ZSReloading_", 6, 70, 2)
npcRegisterSpeech("BREACH", "ZSBreach_", 6, 65, 2)
npcRegisterSpeech("CAR", "ZSCar_", 6, 55, 2)
npcRegisterSpeech("BURN", "ZSBurn_", 3, 100, 2)
npcRegisterSpeech("DRAGDOWN", "ZSDragdown_", 3, 100, 2)
npcRegisterSpeech("INSIDE", "ZSInside_", 3, 55, 2)
npcRegisterSpeech("OUTSIDE", "ZSOutside_", 3, 55, 2)
npcRegisterSpeech("UPSTAIRS", "ZSUpstairs_", 1, 55, 2)
npcRegisterSpeech("KITCHEN", "ZSRoom_Kitchen_", 1, 45, 2)
npcRegisterSpeech("BATHROOM", "ZSRoom_Bathroom_", 1, 45, 2)
npcRegisterSpeech("DEFENDER_SPOTTED", "ZSDefender_Spot_", 4, 70, 3)
npcRegisterSpeech("DEFENDER_SPOT", "ZSDefender_Spot_", 4, 70, 3)
npcRegisterSpeech("THIEF_SPOTTED", "ZSThief_Spot_", 6, 70, 3)
npcRegisterSpeech("THIEF_SPOT", "ZSThief_Spot_", 6, 70, 3)

Entity.SoundStopList = Entity.SoundStopList or {}
table.insert(Entity.SoundStopList, "BeginRemoveBarricadePlank")
table.insert(Entity.SoundStopList, "BlowTorch")
table.insert(Entity.SoundStopList, "GeneratorAddFuel")
table.insert(Entity.SoundStopList, "GeneratorRepair")
table.insert(Entity.SoundStopList, "GetWaterFromTapMetalBig")

Entity.VisualDamage = {}

Entity.VisualDamage.Melee = {"ZedDmg_BACK_Slash", "ZedDmg_BellySlashLeft", "ZedDmg_BellySlashRight", "ZedDmg_BELLY_Slash", 
                             "ZedDmg_ChestSlashLeft", "ZedDmg_CHEST_Slash", "ZedDmg_FaceSkullLeft", "ZedDmg_FaceSkullRight", 
                             "ZedDmg_HeadSlashCentre01", "ZedDmg_HeadSlashCentre02", "ZedDmg_HeadSlashCentre03", "ZedDmg_HeadSlashLeft01", 
                             "ZedDmg_HeadSlashLeft02", "ZedDmg_HeadSlashLeft03", "ZedDmg_HeadSlashLeftBack01", "ZedDmg_HeadSlashLeftBack02", 
                             "ZedDmg_HeadSlashRight01", "ZedDmg_HeadSlashRight02", "ZedDmg_HeadSlashRight03", "ZedDmg_HeadSlashRightBack01", 
                             "ZedDmg_HeadSlashRightBack02", "ZedDmg_HEAD_Skin", "ZedDmg_HEAD_Slash", "ZedDmg_Mouth01", 
                             "ZedDmg_Mouth02", "ZedDmg_MouthLeft", "ZedDmg_MouthRight", "ZedDmg_NoChin", 
                             "ZedDmg_NoEarLeft", "ZedDmg_NoEarRight", "ZedDmg_NoNose", "ZedDmg_ShoulderSlashLeft", 
                             "ZedDmg_ShoulderSlashRight", "ZedDmg_SkullCap", "ZedDmg_SkullUpLeft", "ZedDmg_SkullUpRight"}

Entity.VisualDamage.Gun = {"ZedDmg_BulletBelly01", "ZedDmg_BulletBelly02", "ZedDmg_BulletBelly03", "ZedDmg_BulletChest01", 
                           "ZedDmg_BulletChest02", "ZedDmg_BulletChest03", "ZedDmg_BulletChest04", "ZedDmg_BulletFace01",
                           "ZedDmg_BulletFace02", "ZedDmg_BulletForehead01", "ZedDmg_BulletForehead02", "ZedDmg_BulletForehead03",
                           "ZedDmg_BulletLeftTemple", "ZedDmg_BulletRightTemple", "ZedDmg_BELLY_Bullet", "ZedDmg_BELLY_Shotgun",
                           "ZedDmg_CHEST_Bullet", "ZedDmg_CHEST_Shotgun", "ZedDmg_HEAD_Bullet", "ZedDmg_HEAD_Shotgun",
                           "ZedDmg_ShotgunBelly", "ZedDmg_ShotgunChestCentre", "ZedDmg_ShotgunChestLeft", "ZedDmg_ShotgunChestRight",
                           "ZedDmg_ShotgunFaceFull", "ZedDmg_ShotgunFaceLeft", "ZedDmg_ShotgunFaceRight", "ZedDmg_ShotgunLeft",
                           "ZedDmg_ShotgunRight"}

Entity.Engine = true

local function predicateAll(item)
    return true
end

local function npcSafeInt(value, defaultValue, minValue, maxValue)
    local n = tonumber(value)
    if not n then n = tonumber(defaultValue) or 0 end
    n = math.floor(n)
    if minValue ~= nil and n < minValue then n = minValue end
    if maxValue ~= nil and n > maxValue then n = maxValue end
    return n
end

local function npcSetMagazineAmmo(mag, ammoCount, maxAmmo)
    if not mag then return end

    local max = npcSafeInt(maxAmmo, 0, 0, 500)
    if mag.getMaxAmmo then
        local ok, itemMax = pcall(function() return mag:getMaxAmmo() end)
        if ok and tonumber(itemMax) and tonumber(itemMax) > 0 then
            max = npcSafeInt(itemMax, max, 0, 500)
        end
    end

    local ammo = npcSafeInt(ammoCount, 0, 0, max)
    if max > 0 and mag.setCurrentAmmoCount then
        pcall(function() mag:setCurrentAmmoCount(ammo) end)
    end
end
                        

function Entity.ForceSyncPart(zombie, syncData)
    sendClientCommand(getPlayer(), 'NPCCommands', NPC_ENTITY_LEGACY_KEYS.commandUpdatePart, syncData)
end

local function entityRouteTask(zombie, task, source)
    if not task then return nil end
    if NPCActionRouterBridge and NPCActionRouterBridge.FilterAddTask then
        local ok, routed = pcall(function()
            return NPCActionRouterBridge.FilterAddTask(zombie, task, source)
        end)
        if ok then return routed end
    end
    return task
end

function Entity.AddTask(zombie, task)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        task = entityRouteTask(zombie, task, "entity_add")
        if not task then return false end

        if #brain.tasks > 9 then
            print ("[WARN] Task queue too big, flushing!")
            if NPCActionRouterBridge and NPCActionRouterBridge.OnTasksCleared then
                pcall(function() NPCActionRouterBridge.OnTasksCleared(zombie, brain, brain.tasks, "queue_overflow") end)
            end
            brain.tasks = {}
        end
    
        if NPCActionRouterBridge and NPCActionRouterBridge.ShouldPrependTask and NPCActionRouterBridge.ShouldPrependTask(task) then
            table.insert(brain.tasks, 1, task)
        else
            table.insert(brain.tasks, task)
        end
        -- NPCBrainDataBridge.Update(zombie, brain)
        return true
    end
    return false
end

function Entity.AddTaskFirst(zombie, task)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        task = entityRouteTask(zombie, task, "entity_add_first")
        if not task then return false end

        if #brain.tasks > 9 then
            print ("[WARN] Task queue too big, flushing!")
            if NPCActionRouterBridge and NPCActionRouterBridge.OnTasksCleared then
                pcall(function() NPCActionRouterBridge.OnTasksCleared(zombie, brain, brain.tasks, "queue_overflow") end)
            end
            brain.tasks = {}
        end

        table.insert(brain.tasks, 1, task)
        -- NPCBrainDataBridge.Update(zombie, brain)
        return true
    end
    return false
end

function Entity.GetTask(zombie)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        if #brain.tasks > 0 then
            return brain.tasks[1]
        end
    end
    return nil
end

function Entity.HasTask(zombie)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        if #brain.tasks > 0 then
            return true
        end
    end
    return false
end

function Entity.HasTaskType(zombie, taskType)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        if #brain.tasks > 0 and brain.tasks[1].action == taskType then
            return true
        end
    end
    return false
end

function Entity.HasMoveTask(zombie)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        for _, task in pairs(brain.tasks) do
            if task.action == "Move" or task.action == "GoTo" then
                return true
            end
        end
    end
    return false
end

function Entity.HasActionTask(zombie)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        for _, task in pairs(brain.tasks) do
            if task.action ~= "Move" and task.action ~= "GoTo" then
                return true
            end
        end
    end
    return false
end

function Entity.UpdateTask(zombie, task)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        local removed = brain.tasks and brain.tasks[1] or nil
        table.remove(brain.tasks, 1)
        if NPCActionRouterBridge and NPCActionRouterBridge.OnTaskRemoved then
            pcall(function() NPCActionRouterBridge.OnTaskRemoved(zombie, brain, removed, "update_task") end)
        end
        task = entityRouteTask(zombie, task, "entity_update")
        if task then table.insert(brain.tasks, 1, task) end
        --NPCBrainDataBridge.Update(zombie, brain)
    end
end

function Entity.RemoveTask(zombie)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        local removed = brain.tasks and brain.tasks[1] or nil
        table.remove(brain.tasks, 1)
        if NPCActionRouterBridge and NPCActionRouterBridge.OnTaskRemoved then
            pcall(function() NPCActionRouterBridge.OnTaskRemoved(zombie, brain, removed, "remove_task") end)
        end
        -- NPCBrainDataBridge.Update(zombie, brain)
    end
end

function Entity.ClearTasks(zombie)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        local oldTasks = brain.tasks
        local newtasks = {}
        for _, task in pairs(brain.tasks) do
            if task.lock == true then
                table.insert(newtasks, task)
            end
        end

        brain.tasks = newtasks
        if NPCActionRouterBridge and NPCActionRouterBridge.OnTasksCleared then
            pcall(function() NPCActionRouterBridge.OnTasksCleared(zombie, brain, oldTasks, "clear_tasks") end)
        end
        -- NPCBrainDataBridge.Update(zombie, brain)
    end

    local emitter = zombie:getEmitter()
    local stopList = Entity.SoundStopList

    for _, stopSound in pairs(stopList) do
        if emitter:isPlaying(stopSound) then
            emitter:stopSoundByName(stopSound)
        end
    end
end

function Entity.ClearMoveTasks(zombie)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        local oldTasks = brain.tasks
        local newtasks = {}
        for _, task in pairs(brain.tasks) do
            if task.action ~= "Move" and task.action ~= "GoTo" then
                table.insert(newtasks, task)
            end
        end

        brain.tasks = newtasks
        if NPCActionRouterBridge and NPCActionRouterBridge.OnTasksCleared then
            pcall(function() NPCActionRouterBridge.OnTasksCleared(zombie, brain, oldTasks, "clear_move_tasks") end)
        end
        -- NPCBrainDataBridge.Update(zombie, brain)
    end
end

function Entity.ClearOtherTasks(zombie, exception)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        local newtasks = {}
        for _, task in pairs(brain.tasks) do
            if task.lock == true or task.action == exception then
                table.insert(newtasks, task)
            end
        end

        brain.tasks = newtasks
        -- NPCBrainDataBridge.Update(zombie, brain)
    end
end

function Entity.UpdateEndurance(zombie, delta)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        if not brain.endurance then brain.endurance = 1.00 end
        brain.endurance = brain.endurance + delta
        if brain.endurance < 0 then brain.endurance = 0 end
        if brain.endurance > 1 then brain.endurance = 1 end
        -- NPCBrainDataBridge.Update(zombie, brain)
    end
end

function Entity.GetInfection(zombie)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        if not brain.infection then brain.infection = 0 end
        return brain.infection
    end
    return nil
end

function Entity.UpdateInfection(zombie, delta)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        if not brain.infection then brain.infection = 0 end
        brain.infection = brain.infection + delta
        -- if brain.infection > 90 then print (brain.infection) end
        -- NPCBrainDataBridge.Update(zombie, brain)
    end
end

function Entity.ForceStationary(zombie, stationary)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        brain.stationary = stationary
        -- NPCBrainDataBridge.Update(zombie, brain)
    end
end

function Entity.IsForceStationary(zombie)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        return brain.stationary
    end
end

function Entity.SetNearFire(zombie, nearFire)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        brain.nearFire = nearFire
        -- NPCBrainDataBridge.Update(zombie, brain)
    end
end

function Entity.IsNearFire(zombie)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        return brain.nearFire
    end
end

function Entity.SetSleeping(zombie, sleeping)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        brain.sleeping = sleeping
        -- NPCBrainDataBridge.Update(zombie, brain)
    end
end

function Entity.IsSleeping(zombie)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        return brain.sleeping
    end
end

local function entity_nowMs()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then return math.floor(getGameTime():getWorldAgeHours() * 3600000) end
    return 0
end

function Entity.SetAim(zombie, aim)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        local now = entity_nowMs()
        if aim == true then
            brain.aim = true
            brain.aimStickyUntil = now + 2600
        else
            if brain.aimStickyUntil and now < brain.aimStickyUntil then return end
            brain.aim = false
            brain.aimStickyUntil = nil
        end
        -- NPCBrainDataBridge.Update(zombie, brain)
    end
end

function Entity.IsAim(zombie)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        if brain.aim == true then return true end
        if brain.aimStickyUntil and entity_nowMs() < brain.aimStickyUntil then return true end
        return false
    end
end

function Entity.SetMoving(zombie, moving)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        brain.moving = moving
        -- NPCBrainDataBridge.Update(zombie, brain)
    end
end

function Entity.IsMoving(zombie)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        return brain.moving
    end
end

function Entity.SetCapabilities(zombie, capabilities)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        brain.capabilities = capabilities
        -- NPCBrainDataBridge.Update(zombie, brain)
    end
end

function Entity.Can(zombie, capability)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain and brain.program then
        local programName = Entity.NormalizeProgramName and Entity.NormalizeProgramName(brain.program.name) or brain.program.name
        local program = ZombiePrograms and (ZombiePrograms[programName] or ZombiePrograms[brain.program.name]) or nil
        local capabilities = program and program.GetCapabilities and program.GetCapabilities() or nil
        if capabilities then
            if capabilities[capability] then return true end
        end
    end
    return false
end

function Entity.IsDNA(zombie, feature)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        if brain.dna then
            if brain.dna[feature] then return true end
        end
    end
    return false
end

-- Functions that require brain sync below

-- NPC ownership
function Entity.GetMaster(zombie)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        return brain.master
    end
end

function Entity.SetMaster(zombie, master)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        brain.master = master
        -- NPCBrainDataBridge.Update(zombie, brain)
        -- sendClientCommand(getPlayer(), 'NPCCommands', 'NPC update', brain)
    end
end

-- NPC programs
function Entity.NormalizeProgramName(program)
    if program == NPC_ENTITY_LEGACY_KEYS.programNPC then return "Raider" end
    return program
end

function Entity.GetProgram(zombie)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        return brain.program
    end
end

function Entity.SetProgram(zombie, program, programParams)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        brain.program = {}
        brain.program.name = Entity.NormalizeProgramName(program)
        brain.program.stage = "Prepare"

        -- NPCBrainDataBridge.Update(zombie, brain)
    end
    -- sendClientCommand(getPlayer(), 'NPCCommands', 'NPC update', brain)
end

function Entity.SetProgramStage(zombie, stage)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        brain.program.stage = stage
        -- NPCBrainDataBridge.Update(zombie, brain)
    end
    -- sendClientCommand(getPlayer(), 'NPCCommands', 'NPC update', brain)
end

-- NPC hostility
function Entity.SetHostile(zombie, hostile)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        brain.hostile = hostile
        -- NPCBrainDataBridge.Update(zombie, brain)
    end
end

function Entity.IsHostile(zombie)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        return brain.hostile
    end
end

-- NPC weapons
function Entity.GetWeapons(zombie)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        return brain.weapons
    end
end

function Entity.GetBestWeapon(zombie)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        local weapons = brain.weapons
        if weapons.primary.bulletsLeft > 0 or weapons.primary.magCount > 0 then
            return weapons.primary.name
        elseif weapons.secondary.bulletsLeft > 0 or weapons.secondary.magCount > 0 then
            return weapons.secondary.name
        else
            return weapons.melee
        end
    end
end

function Entity.IsOutOfAmmo(zombie)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        local weapons = brain.weapons
        if weapons.primary.bulletsLeft == 0 and weapons.primary.magCount == 0 and weapons.secondary.bulletsLeft == 0 and weapons.secondary.magCount == 0 then
            return true
        end
    end
    return false
end

function Entity.SetWeapons(zombie, weapons)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        brain.weapons = weapons
        -- NPCBrainDataBridge.Update(zombie, brain)
        Entity.UpdateItemsToSpawnAtDeath(zombie)
        -- sendClientCommand(getPlayer(), 'NPCCommands', 'NPC update', brain)
    end
end

-- Inventory
function Entity.SetInventory(zombie, inventory)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        brain.inventory = inventory
        -- NPCBrainDataBridge.Update(zombie, brain)
        Entity.UpdateItemsToSpawnAtDeath(zombie)
        -- sendClientCommand(getPlayer(), 'NPCCommands', 'NPC update', brain)
    end
end

function Entity.Has(zombie, item)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        for _, i in pairs(brain.inventory) do
            if i == item then return true end
        end
    end
    return false
end

-- NPC loot inventory
function Entity.SetLoot(zombie, loot)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        brain.loot = loot
        -- NPCBrainDataBridge.Update(zombie, brain)
        Entity.UpdateItemsToSpawnAtDeath(zombie)
    end
    -- sendClientCommand(getPlayer(), 'NPCCommands', 'NPC update', brain)
end

function Entity.AddLoot(zombie, item)
    local brain = NPCBrainDataBridge.Get(zombie)
    if brain then
        table.insert(brain.loot, item)
    end
end

-- This translates weapons, loot, inventory to actual items to be
-- spawned at NPC death
function Entity.UpdateItemsToSpawnAtDeath(zombie)
    if not NPCUtilityCore.IsController(zombie) then return end
    
    local brain = NPCBrainDataBridge.Get(zombie)
    if not brain or not brain.weapons then return end

    local weapons = brain.weapons
    weapons.primary = weapons.primary or {}
    weapons.secondary = weapons.secondary or {}
    --zombie:setPrimaryHandItem(nil)
    --zombie:resetEquippedHandsModels()
    zombie:clearItemsToSpawnAtDeath()

    -- keyring / id
    if brain.fullname then
        NPCCompatibilityBridge.AddId(zombie, brain.fullname)
    end

    local deathDropSeen = {}
    local function addDeathItem(item)
        if not item then return false end
        local key = tostring(item)
        if item.getID then
            local ok, id = pcall(function() return item:getID() end)
            if ok and id ~= nil then key = "id:" .. tostring(id) end
        elseif item.getFullType then
            local ok, fullType = pcall(function() return item:getFullType() end)
            if ok and fullType then key = "type:" .. tostring(fullType) .. ":" .. tostring(item) end
        end
        if deathDropSeen[key] then return false end
        deathDropSeen[key] = true
        zombie:addItemToSpawnAtDeath(item)
        return true
    end

    -- update inventory
    local inventory = zombie:getInventory()
    local items = ArrayList.new()
    inventory:getAllEvalRecurse(predicateAll, items)
    for i=0, items:size()-1 do
        addDeathItem(items:get(i))
    end

    -- Stage 396: preserve the actual live weapon items as death loot. Some
    -- materialized NPCs shoot with hand/attached items that are not present in
    -- the inventory recursion, and the old code skipped recreated primary guns
    -- when it detected an attached model. Add real hand/attached objects first,
    -- then keep the existing fallback reconstruction below.
    if zombie.getPrimaryHandItem then
        local ok, item = pcall(function() return zombie:getPrimaryHandItem() end)
        if ok then addDeathItem(item) end
    end
    if zombie.getSecondaryHandItem then
        local ok, item = pcall(function() return zombie:getSecondaryHandItem() end)
        if ok then addDeathItem(item) end
    end
    local function getAttachedItemSafe(location)
        if not zombie.getAttachedItem or not location then return nil end
        -- Stage 398: never query non-vanilla/invalid attachment names here.
        -- PZ 41 throws a Java RuntimeException for unknown locations such as
        -- "Back" before Lua can handle it cleanly, which spammed console errors
        -- every time death loot was refreshed for checkpoint guards.
        local ok, item = pcall(function() return zombie:getAttachedItem(location) end)
        if ok then return item end
        return nil
    end

    if zombie.getAttachedItem then
        for _, location in ipairs({"Rifle On Back", "Holster Right", "Holster Left", "Belt Right", "Belt Left"}) do
            addDeathItem(getAttachedItemSafe(location))
        end
    end

    -- update weapons that the NPC has
    if weapons.melee and weapons.melee ~= "Base.BareHands" then 
        local item = NPCCompatibilityBridge.InstanceItem(weapons.melee)
        if item then
            if item.setCondition then
                pcall(function() item:setCondition(1+ZombRand(10)) end)
            end
            addDeathItem(item)
        end
    end

    if weapons.primary then
        if weapons.primary.name then

            if weapons.primary.magName then
                local mag = NPCCompatibilityBridge.InstanceItem(weapons.primary.magName)
                if mag then
                    npcSetMagazineAmmo(mag, weapons.primary.bulletsLeft, weapons.primary.magSize)
                    addDeathItem(mag)
                end

                local attachedBack = getAttachedItemSafe("Rifle On Back")
                if not attachedBack then
                    local gun = NPCCompatibilityBridge.InstanceItem(weapons.primary.name)
                    if gun then
                        gun:setCondition(3+ZombRand(15))
                        -- gun:setClip(nil)
                        addDeathItem(gun)
                    end
                end

                for i=1, npcSafeInt(weapons.primary.magCount, 0, 0, 100) do
                    local mag = NPCCompatibilityBridge.InstanceItem(weapons.primary.magName)
                    if mag then
                        npcSetMagazineAmmo(mag, weapons.primary.magSize, weapons.primary.magSize)
                        addDeathItem(mag)
                    end
                end
            end
        end
    end

    if weapons.secondary then
        if weapons.secondary.name then

            if weapons.secondary.magName then
                local mag = NPCCompatibilityBridge.InstanceItem(weapons.secondary.magName)
                if mag then
                    npcSetMagazineAmmo(mag, weapons.secondary.bulletsLeft, weapons.secondary.magSize)
                    addDeathItem(mag)
                end

                local attachedHolster = getAttachedItemSafe("Holster Right")
                if not attachedHolster then
                    local gun = NPCCompatibilityBridge.InstanceItem(weapons.secondary.name)
                    if gun then
                        -- gun:setClip(nil)
                        gun:setCondition(3+ZombRand(22))
                        addDeathItem(gun)
                    end
                end

                for i=1, npcSafeInt(weapons.secondary.magCount, 0, 0, 100) do
                    local mag = NPCCompatibilityBridge.InstanceItem(weapons.secondary.magName)
                    if mag then
                        npcSetMagazineAmmo(mag, weapons.secondary.magSize, weapons.secondary.magSize)
                        addDeathItem(mag)
                    end
                end
            end
        end
    end

    -- update loot items that the bandit has
    local loot = brain.loot
    if loot then
        for _, itemType in pairs(brain.loot) do
            local item = NPCCompatibilityBridge.InstanceItem(itemType)
            if item then
                if item:IsDrainable() then
                    item:setUses(1+ZombRand(2))
                elseif item:IsWeapon() then
                    item:setCondition(1+ZombRand(3))
                end
                addDeathItem(item)
            end
        end
    end
end

function Entity.SurpressZombieSounds(bandit)
    NPCCompatibilityBridge.SurpressZombieSounds(bandit)
end

function Entity.PickVoice(zombie)
    local maleOptions = {"1", "2", "3", "4"} -- , "14", "16", "18", "21"}
    local femaleOptions = {"3"}

    if zombie:isFemale() then
        return NPCUtilityCore.Choice(femaleOptions)
    else
        return NPCUtilityCore.Choice(maleOptions)
    end
end

function Entity.Say(zombie, phrase, force)
    local brain = NPCBrainDataBridge.Get(zombie)
    if not brain then return end

    if not force and brain.speech and brain.speech > 0 then return end
    if force and zombie.getEmitter then pcall(function() zombie:getEmitter():stopAll() end) end

    local player = getPlayer and getPlayer() or nil
    if not (player and player.getX and player.getY and zombie and zombie.getX and zombie.getY) then return end
    local dist = NPCUtilityCore.DistTo(player:getX(), player:getY(), zombie:getX(), zombie:getY())

    if dist <= 14 then
        local voice

        local sex = "Male"
        if zombie:isFemale() then
            sex = "Female"
        end

        if brain.voice then
            voice = brain.voice
        else
            -- if voice was not assigned on spawn then preserve backward compatibility
            if zombie:isFemale() then
                voice = 3
            else
                voice = 1 + math.abs(brain.id or 1) % 5
                if voice > 4 then voice = 1 end
            end
        end

        local phraseKey = tostring(phrase or "RADIO")
        local config = Entity.SoundTab[phraseKey] or Entity.SoundTab[string.upper(phraseKey)]
        local length = 2
        local sound = nil
        local shouldSpeak = true
        if config then
            shouldSpeak = ZombRand(100) < config.chance
            sound = config.prefix .. sex .. "_" .. voice .. "_" .. tostring(1 + ZombRand(config.randMax))
            length = config.length or length
        else
            sound = phraseKey
        end

        if shouldSpeak then
            -- text captions stay enabled even when the custom voice pack is disabled or absent.
            local legacySandbox = SandboxVars and SandboxVars[NPC_ENTITY_LEGACY_KEYS.sandboxSection]
            local captionsEnabled = legacySandbox == nil or legacySandbox.General_Captions ~= false
            if captionsEnabled and zombie.addLineChatElement then
                local text = config and (NPC_ENTITY_LEGACY_KEYS.speechTextPrefix .. sound) or nil
                local line = text and getText and getText(text) or nil
                if npcSpeechTextMissing(line, text) then
                    line = NPC_SPEECH_FALLBACK_CAPTIONS[string.upper(phraseKey)] or phraseKey or "..."
                end
                if brain.hostile then
                    zombie:addLineChatElement(line, 0.8, 0.1, 0.1)
                else
                    zombie:addLineChatElement(line, 0.1, 0.8, 0.1)
                end
            end

            -- audible speech is optional and disabled unless the custom speech pack is present.
            if config and Entity.CustomSpeechSoundsEnabled and legacySandbox and legacySandbox.General_Speak then
                zombie:getEmitter():playVocals(sound)
            end

            brain.speech = length

            addSound(getPlayer(), zombie:getX(), zombie:getY(), zombie:getZ(), 5, 50)
        end
    end

end

function Entity.AddVisualDamage(bandit, handWeapon)
    
    if handWeapon then
        -- Stage 448: live human NPCs should not accumulate vanilla zombie damage
        -- body visuals. In long NPC-vs-NPC firefights those visuals can overwrite the
        -- human outfit presentation and make actors look like they lost their clothes.
        local brain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(bandit) or nil
        if brain and (brain.humanNPC == true or brain.forceHumanAnimation == true or brain.noZombieAnimation == true or brain.worldDirector == true or brain.mercenaryHired == true) then
            return
        end
        local itemVisual
        local weaponType = WeaponType.getWeaponType(handWeapon)
        if weaponType == WeaponType.firearm or weaponType == WeaponType.handgun then
            itemVisual = NPCUtilityCore.Choice(Entity.VisualDamage.Gun)
        else
            itemVisual = NPCUtilityCore.Choice(Entity.VisualDamage.Melee)
        end

        bandit:addVisualDamage(itemVisual)
    end
end

NPCCore.EntityState = Entity
