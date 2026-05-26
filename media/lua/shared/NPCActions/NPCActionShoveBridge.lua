NPCActionShoveBridge = NPCActionShoveBridge or {}
require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCLegacyContractBridge"

local NPC_ACTION_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
NPCEntity = NPCEntity or NPC_ACTION_LEGACY_GLOBALS.Get("Entity")
NPCUtils = NPCUtils or NPC_ACTION_LEGACY_GLOBALS.Get("Utils")
NPCBrainData = NPCBrainData or NPC_ACTION_LEGACY_GLOBALS.Get("Brain")
NPCPlayerClient = NPCPlayerClient or NPC_ACTION_LEGACY_GLOBALS.Get("PlayerClient")
NPCZombieCacheBridge = NPCZombieCacheBridge or NPC_ACTION_LEGACY_GLOBALS.Get("ZombieCache")
NPCFactionBridge = NPCFactionBridge or NPC_ACTION_LEGACY_GLOBALS.Get("Faction")
NPCSpyBridge = NPCSpyBridge or NPC_ACTION_LEGACY_GLOBALS.Get("Spy")

local NPC_ACTION_SHOVE_LEGACY_KEYS = {
    liveFlag = NPCLegacyContractBridge.Key("FLAG"),
    formerNPCZombie = NPCLegacyContractBridge.Key("FORMER_ZOMBIE")
}


local function IsFormerNPCZombie(target)
    if not target or not instanceof or not instanceof(target, "IsoZombie") then return false end
    if target:getVariableBoolean(NPC_ACTION_SHOVE_LEGACY_KEYS.formerNPCZombie) then return true end
    local md = target:getModData()
    return md and md[NPC_ACTION_SHOVE_LEGACY_KEYS.formerNPCZombie] == true
end

local function IsLiveNPC(target)
    if not target or not instanceof or not instanceof(target, "IsoZombie") then return false end
    if IsFormerNPCZombie(target) then return false end
    return target:getVariableBoolean(NPC_ACTION_SHOVE_LEGACY_KEYS.liveFlag) == true
end


local function bff_sameValue(a, b)
    return a ~= nil and b ~= nil and tostring(a) == tostring(b)
end

local function bff_groupId(brain)
    if type(brain) ~= "table" then return nil end
    return brain.worldGroupId or brain.groupId or brain.homeGroupId
end

local function bff_sameSquad(a, b)
    if not (type(a) == "table" and type(b) == "table") then return false end
    if bff_sameValue(a.id, b.id) then return true end
    if bff_sameValue(a.uid or a.persistentId, b.uid or b.persistentId) then return true end
    if bff_sameValue(bff_groupId(a), bff_groupId(b)) then return true end
    return false
end

local function bff_isFriendlyLiveNPC(attackerBrain, targetBrain, target)
    if not IsLiveNPC(target) then return false end
    if not attackerBrain then return true end
    if not targetBrain then return true end
    if bff_sameSquad(attackerBrain, targetBrain) then return true end
    if NPCFactionBridge and NPCFactionBridge.IsEnabled and NPCFactionBridge.IsEnabled() and NPCFactionBridge.AreBrainsEnemies then
        local ok, enemies = pcall(function() return NPCFactionBridge.AreBrainsEnemies(attackerBrain, targetBrain) end)
        if ok then return enemies ~= true end
    end
    if attackerBrain.clan ~= nil and targetBrain.clan ~= nil and attackerBrain.clan == targetBrain.clan then return true end
    if attackerBrain.hostile ~= nil and targetBrain.hostile ~= nil and attackerBrain.hostile == targetBrain.hostile then return true end
    return false
end

local function CanShoveTarget(attackerBrain, targetBrain, target)
    if IsFormerNPCZombie(target) then return true end
    if target and instanceof and instanceof(target, "IsoZombie") and not IsLiveNPC(target) then return true end
    if bff_isFriendlyLiveNPC(attackerBrain, targetBrain, target) then return false end

    if targetBrain and NPCFactionBridge and NPCFactionBridge.IsEnabled and NPCFactionBridge.IsEnabled() and NPCFactionBridge.AreBrainsEnemies then
        return NPCFactionBridge.AreBrainsEnemies(attackerBrain, targetBrain)
    end

    if target and instanceof and instanceof(target, "IsoPlayer") then
        if attackerBrain and attackerBrain.spy == true and attackerBrain.spyDefected ~= true and NPCSpyBridge and NPCSpyBridge.PlayerId and tostring(attackerBrain.spyForPlayerId or "") == tostring(NPCSpyBridge.PlayerId(target) or "") then return false end
        if NPCSpyBridge and NPCSpyBridge.ShouldHoldFireAgainstPlayer and NPCSpyBridge.ShouldHoldFireAgainstPlayer(attackerBrain, target) then return false end
        if NPCFactionBridge and NPCFactionBridge.IsEnabled and NPCFactionBridge.IsEnabled() and NPCFactionBridge.CanBrainAttackPlayer then
            return NPCFactionBridge.CanBrainAttackPlayer(attackerBrain, target)
        end
        return attackerBrain and attackerBrain.hostile == true
    end

    if IsLiveNPC(target) and not targetBrain then return false end
    if not targetBrain or not targetBrain.clan then return false end
    if not attackerBrain then return false end
    return attackerBrain.clan ~= targetBrain.clan or (attackerBrain.hostile and not targetBrain.hostile)
end

local function ShovePlayer(attacker, player)
    if not attacker or not player then return end
    local facing = player:isFacingObject(attacker, 0.5)

    player:clearVariable("BumpFallType")
    player:setBumpType("stagger")

    if NPCUtils and NPCUtils.NPCRand and NPCUtils.NPCRand(3) == 1 then
        player:setBumpFall(true)
    else
        player:setBumpFall(false)
    end

    if facing then
        player:setBumpFallType("pushedFront")
    else
        player:setBumpFallType("pushedBehind")
    end
end

local function ShoveZombie(attacker, zombie)
    if not attacker or not zombie then return end
    local facing = zombie:isFacingObject(attacker, 0.5)
    if facing then
        zombie:setBumpType("ZombiePushedFront")
    else
        zombie:setBumpType("ZombiePushedBack")
    end
end

local function GetEnemy(task)
    if not task then return nil end
    if NPCZombieCacheBridge and NPCZombieCacheBridge.Cache and task.eid then
        local enemy = NPCZombieCacheBridge.Cache[task.eid]
        if enemy then return enemy end
    end
    if NPCPlayerClient and NPCPlayerClient.GetPlayerById and task.eid then
        return NPCPlayerClient.GetPlayerById(task.eid)
    end
    return nil
end

local function GetBrain(character)
    if NPCBrainData and NPCBrainData.Get then
        return NPCBrainData.Get(character)
    end
    return nil
end

local function UpdateTask(character, task)
    if NPCEntity and NPCEntity.UpdateTask then
        NPCEntity.UpdateTask(character, task)
    end
end

function NPCActionShoveBridge.OnStart(character, task)
    if not character or not task then return true end

    local enemy = GetEnemy(task)
    if enemy then
        local brainActor = GetBrain(character)
        local brainEnemy = GetBrain(enemy)
        if not CanShoveTarget(brainActor, brainEnemy, enemy) then return true end
    end

    local anim = "Shove"
    task.anim = anim
    UpdateTask(character, task)
    character:setBumpType(anim)

    return true
end

function NPCActionShoveBridge.OnWorking(character, task)
    if not character or not task then return true end

    if task.x and task.y then
        character:faceLocation(task.x, task.y)
    end

    local bumpType = character:getBumpType()
    if bumpType ~= task.anim then return false end

    if not task.hit and task.time and task.time <= 40 then
        task.hit = true

        local asn = character:getActionStateName()
        if asn == "getup" or asn == "getup-fromonback" or asn == "getup-fromonfront" or asn == "getup-fromsitting"
                 or asn == "staggerback" or asn == "staggerback-knockeddown" or asn == "falldown" then return false end

        local brainActor = GetBrain(character)
        local enemy = NPCZombieCacheBridge and NPCZombieCacheBridge.Cache and task.eid and NPCZombieCacheBridge.Cache[task.eid] or nil
        if enemy then
            local brainEnemy = GetBrain(enemy)
            if CanShoveTarget(brainActor, brainEnemy, enemy) then
                ShoveZombie(character, enemy)
            end
        end

        if NPCPlayerClient and NPCPlayerClient.GetPlayers and NPCUtils and NPCUtils.GetCharacterID then
            local playerList = NPCPlayerClient.GetPlayers()
            if playerList then
                for i=0, playerList:size()-1 do
                    local player = playerList:get(i)
                    if player then
                        local eid = NPCUtils.GetCharacterID(player)
                        if player:isAlive() and eid == task.eid and CanShoveTarget(brainActor, nil, player) then
                            ShovePlayer(character, player)
                        end
                    end
                end
            end
        end
    end
    return false
end

function NPCActionShoveBridge.OnComplete(character, task)
    return true
end
