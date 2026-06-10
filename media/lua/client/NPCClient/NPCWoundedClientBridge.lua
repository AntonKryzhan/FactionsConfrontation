-- NPCWoundedClientBridge.lua
-- Client-side detection and context menu for wounded hired mercenaries.

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCWoundedBridge"
require "NPCCore/NPCLegacySettingsBridge"
require "NPCCore/NPCCompatibilityBridge"
require "NPCCore/NPCZombieLifecycleClassifierBridge"

NPCWoundedClientBridge = NPCWoundedClientBridge or {}
local NPC_WOUNDED_CLIENT_LEGACY_KEYS = {
    npcFlag = NPCLegacyContractBridge.Key("FLAG")
}
local NPC_WOUNDED_CLIENT_LEGACY_TEXT_PREFIX = NPCLegacyContractBridge.Text.prefix

local function bwc_text(key)
    return getText(NPC_WOUNDED_CLIENT_LEGACY_TEXT_PREFIX .. tostring(key or ""))
end

local function bwc_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        local ok, value = pcall(function() return NPCLegacySettingsBridge.GetBool(name, defaultValue == true) end)
        if ok and value ~= nil then return value == true end
    end
    return defaultValue == true
end

local function bwc_player(playerNum)
    return getSpecificPlayer(playerNum or 0) or getPlayer()
end

local function bwc_playerId(player)
    if NPCWoundedBridge and NPCWoundedBridge.PlayerId then return NPCWoundedBridge.PlayerId(player) end
    if NPCUtils and NPCUtils.GetCharacterID then
        local ok, id = pcall(function() return NPCUtils.GetCharacterID(player) end)
        if ok and id ~= nil then return id end
    end
    return nil
end

local function bwc_zombieFromSquare(square)
    if not square then return nil end
    local zombie = square:getZombie()
    if zombie then return zombie end
    local squareS = square:getS()
    if squareS then
        zombie = squareS:getZombie()
        if zombie then return zombie end
    end
    local squareW = square:getW()
    if squareW then
        zombie = squareW:getZombie()
        if zombie then return zombie end
    end
    if square.getN then
        local squareN = square:getN()
        if squareN then
            zombie = squareN:getZombie()
            if zombie then return zombie end
        end
    end
    if square.getE then
        local squareE = square:getE()
        if squareE then
            zombie = squareE:getZombie()
            if zombie then return zombie end
        end
    end
    return nil
end

local function bwc_clickedSquare(worldobjects)
    if NPCCompatibilityBridge and NPCCompatibilityBridge.GetClickedSquare then
        local ok, sq = pcall(function() return NPCCompatibilityBridge.GetClickedSquare() end)
        if ok and sq then return sq end
    end
    if type(worldobjects) == "table" then
        for _, obj in ipairs(worldobjects) do
            if obj and obj.getSquare then
                local ok, sq = pcall(function() return obj:getSquare() end)
                if ok and sq then return sq end
            end
        end
    end
    local player = getPlayer()
    if player and player.getSquare then return player:getSquare() end
    return nil
end

local function bwc_brainId(bandit, brain)
    if brain and brain.id then return brain.id end
    if bandit and NPCUtils and NPCUtils.GetCharacterID then
        local ok, id = pcall(function() return NPCUtils.GetCharacterID(bandit) end)
        if ok and id ~= nil then return id end
    end
    return nil
end

local function bwc_send(player, bandit, command)
    if not (player and bandit) then return end
    local brain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(bandit) or nil
    local id = bwc_brainId(bandit, brain)
    if not id then return end
    sendClientCommand(player, 'NPCWounded', command, {
        id=id,
        groupId=brain and (brain.worldGroupId or brain.groupId) or nil,
        x=bandit:getX(),
        y=bandit:getY(),
        z=bandit:getZ()
    })
end

function NPCWoundedClientBridge.Stabilize(player, bandit)
    bwc_send(player, bandit, "Stabilize")
end

function NPCWoundedClientBridge.Evacuate(player, bandit)
    bwc_send(player, bandit, "Evacuate")
end

function NPCWoundedClientBridge.Abandon(player, bandit)
    bwc_send(player, bandit, "Abandon")
end

local function bwc_halo(text, r, g, b)
    local player = getPlayer() or getSpecificPlayer(0)
    if HaloTextHelper and player and text then
        HaloTextHelper.addText(player, tostring(text), r or 230, g or 220, b or 160)
    end
end

function NPCWoundedClientBridge.OnHitZombie(zombie, attacker, bodyPartType, handWeapon)
    if NPCZombieLifecycleClassifierBridge and NPCZombieLifecycleClassifierBridge.IsLiveNPC then
        local okLive, live = pcall(function() return NPCZombieLifecycleClassifierBridge.IsLiveNPC(zombie) end)
        if okLive and live ~= true then return end
    end
    if not (NPCWoundedBridge and NPCWoundedBridge.TryMarkDowned) then return end
    local ok, downed, brain = pcall(function() return NPCWoundedBridge.TryMarkDowned(zombie, attacker) end)
    if not ok or not downed or not brain then return end
    if zombie and zombie.Say then pcall(function() zombie:Say("WOUNDED") end) end
    local id = bwc_brainId(zombie, brain)
    local player = attacker and attacker.isLocalPlayer and attacker:isLocalPlayer() and attacker or getPlayer()
    if player and id then
        sendClientCommand(player, 'NPCWounded', 'Downed', {
            id=id,
            groupId=brain.worldGroupId or brain.groupId,
            x=zombie:getX(),
            y=zombie:getY(),
            z=zombie:getZ(),
            wounded=true,
            woundedState="downed"
        })
    end
end

function NPCWoundedClientBridge.OnZombieUpdate(zombie)
    if not (NPCWoundedBridge and zombie and zombie.getVariableBoolean and zombie:getVariableBoolean(NPC_WOUNDED_CLIENT_LEGACY_KEYS.npcFlag)) then return end
    local brain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(zombie) or nil
    if not brain or not NPCWoundedBridge.IsWounded(brain) then return end
    NPCWoundedBridge.ApplyLocalState(zombie, brain)
    if NPCWoundedBridge.IsDowned(brain) then
        NPCWoundedBridge.ApplyBleedout(zombie, brain)
        if NPCEntity and NPCEntity.ClearTasks and NPCEntity.AddTask then
            local current = NPCEntity.GetTask and NPCEntity.GetTask(zombie) or nil
            if not current or current.woundedDowned ~= true then
                local tasks = NPCWoundedBridge.PlanTasks(zombie, brain)
                if tasks and #tasks > 0 then
                    NPCEntity.ClearTasks(zombie)
                    for _, task in ipairs(tasks) do NPCEntity.AddTask(zombie, task) end
                end
            end
        end
    end
end

function NPCWoundedClientBridge.OnFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    if test or not bwc_bool("Wounded_Enabled", true) then return end
    local player = bwc_player(playerNum)
    if not player then return end
    local square = bwc_clickedSquare(worldobjects)
    local zombie = bwc_zombieFromSquare(square)
    if not (zombie and zombie.getVariableBoolean and zombie:getVariableBoolean(NPC_WOUNDED_CLIENT_LEGACY_KEYS.npcFlag)) then return end
    local brain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(zombie) or nil
    if not (NPCWoundedBridge and NPCWoundedBridge.IsWounded and NPCWoundedBridge.IsWounded(brain)) then return end
    if not NPCWoundedBridge.IsHiredBy(brain, player) then return end

    local label = brain.fullname or brain.name or "Wounded ally"
    local state = tostring(brain.woundedState or "wounded")
    local root = context:addOption(label .. " [" .. state .. "]")
    local menu = context:getNew(context)
    context:addSubMenu(root, menu)

    if brain.woundedDowned == true then
        menu:addOption(bwc_text("Menu_StabilizeWound"), player, NPCWoundedClientBridge.Stabilize, zombie)
    end
    menu:addOption(bwc_text("Menu_EvacuateToNearestBase"), player, NPCWoundedClientBridge.Evacuate, zombie)
    menu:addOption(bwc_text("Menu_AbandonWoundedAlly"), player, NPCWoundedClientBridge.Abandon, zombie)
end

function NPCWoundedClientBridge.OnServerCommand(module, command, args)
    if not NPCLegacyContractBridge.IsModule(module, "NPCWounded", "wounded") then return end
    if command == "Result" and args and args.text then
        bwc_halo(args.text, args.r, args.g, args.b)
    end
end

function NPCWoundedClientBridge.Install()
    if NPCWoundedClientBridge._installed then return end
    NPCWoundedClientBridge._installed = true
    Events.OnHitZombie.Add(NPCWoundedClientBridge.OnHitZombie)
    Events.OnZombieUpdate.Add(NPCWoundedClientBridge.OnZombieUpdate)
    Events.OnFillWorldObjectContextMenu.Add(NPCWoundedClientBridge.OnFillWorldObjectContextMenu)
    Events.OnServerCommand.Add(NPCWoundedClientBridge.OnServerCommand)
end
