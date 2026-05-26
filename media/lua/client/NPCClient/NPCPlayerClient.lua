require "NPCCore/NPCLegacyContractBridge"

NPCPlayerClient = NPCPlayerClient or {}

local PlayerClient = NPCPlayerClient
local originalPanicIncreaseValue = nil

local function isServerOnly()
    return isServer and isServer()
end

local function safeWorld()
    if getWorld then
        return getWorld()
    end
end

local function currentGameMode()
    local world = safeWorld()
    if world and world.getGameMode then
        return world:getGameMode()
    end
    return "SinglePlayer"
end

local function listSize(list)
    if list and list.size then
        return list:size()
    end
    return 0
end

local function listGet(list, index)
    if list and list.get then
        return list:get(index)
    end
end

local function characterId(character)
    if NPCUtils and NPCUtils.GetCharacterID then
        return NPCUtils.GetCharacterID(character)
    end
    if character and character.getOnlineID then
        local ok, id = pcall(function()
            return character:getOnlineID()
        end)
        if ok and id ~= nil then
            return id
        end
    end
end

local function playerModData()
    if GetNPCModDataPlayers then
        local ok, data = pcall(GetNPCModDataPlayers)
        if ok and type(data) == "table" then
            data.OnlinePlayers = data.OnlinePlayers or {}
            return data
        end
    end
    return { OnlinePlayers = {} }
end

local function distanceManhattan(ax, ay, bx, by)
    if NPCUtils and NPCUtils.DistToManhattan then
        return NPCUtils.DistToManhattan(ax, ay, bx, by)
    end
    return math.abs((ax or 0) - (bx or 0)) + math.abs((ay or 0) - (by or 0))
end

local function localPlayer()
    if getPlayer then
        return getPlayer()
    end
end

local NPC_PLAYER_LEGACY_SANDBOX = NPCLegacyContractBridge.Sandbox.main

local NPC_PLAYER_COMMANDS = {
    resetKills = NPCLegacyContractBridge.Command("RESET_KILLS")
}

local function safeSend(player, moduleName, commandName, payload)
    if player and sendClientCommand then
        sendClientCommand(player, moduleName, commandName, payload or {})
        return true
    end
    return false
end

local function playerClientGetLegacyNumber(name)
    local vars = SandboxVars and SandboxVars[NPC_PLAYER_LEGACY_SANDBOX] or nil
    if vars and vars[name] ~= nil then
        return vars[name]
    end
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        local ok, value = pcall(function() return NPCLegacySettingsBridge.GetNumber(name) end)
        if ok and value ~= nil then return value end
    end
    return nil
end

function PlayerClient.IsGhost(player)
    if not player then
        return false
    end

    local gmd = playerModData()
    local id = characterId(player)
    local record = id and gmd.OnlinePlayers and gmd.OnlinePlayers[id]
    if record then
        return record.isGhost == true
    end
    return false
end

function PlayerClient.GetPlayers()
    local gamemode = currentGameMode()
    if gamemode == "Multiplayer" and getOnlinePlayers then
        return getOnlinePlayers()
    end
    if IsoPlayer and IsoPlayer.getPlayers then
        return IsoPlayer.getPlayers()
    end
end

function PlayerClient.GetPlayerById(id)
    local playerList = PlayerClient.GetPlayers()
    for i = 0, listSize(playerList) - 1 do
        local player = listGet(playerList, i)
        if player and characterId(player) == id then
            return player
        end
    end
end

function PlayerClient.GetMasterPlayer(npc)
    if currentGameMode() ~= "Multiplayer" then
        return localPlayer()
    end

    local masterId
    if npc and NPCEntity and NPCEntity.GetMaster then
        masterId = tonumber(NPCEntity.GetMaster(npc))
    end

    if masterId and masterId >= 0 and getPlayerByOnlineID then
        local ok, player = pcall(getPlayerByOnlineID, masterId)
        if ok and player then
            return player
        end
    end

    return localPlayer()
end

function PlayerClient.WakeEveryone()
    local playerList = PlayerClient.GetPlayers()
    for i = 0, listSize(playerList) - 1 do
        local player = listGet(playerList, i)
        if player and player.forceAwake then
            player:forceAwake()
        end
    end
end

function PlayerClient.UpdateOnlinePlayerPayload()
    if isServerOnly() then
        return false
    end

    local player = localPlayer()
    if not player then
        return false
    end

    local payload = {}
    payload.id = characterId(player)
    payload.name = player.getDisplayName and player:getDisplayName() or nil
    payload.isGhost = player.isGhostMode and player:isGhostMode() or false

    if NPCFactionBridge and NPCFactionBridge.UpdateLocalPlayerTimer then
        NPCFactionBridge.UpdateLocalPlayerTimer(player)
    end

    if NPCFactionBridge and NPCFactionBridge.BuildPlayerPayload then
        local factionData = NPCFactionBridge.BuildPlayerPayload(player)
        if type(factionData) == "table" then
            for key, value in pairs(factionData) do
                payload[key] = value
            end
        end
    end

    return safeSend(player, "Players", "PlayerUpdate", payload)
end

function PlayerClient.HandlePanic(player)
    if isServerOnly() or not player then
        return false
    end

    local bodyDamage = player.getBodyDamage and player:getBodyDamage()
    local stats = player.getStats and player:getStats()
    if not bodyDamage or not stats then
        return false
    end

    if originalPanicIncreaseValue == nil and bodyDamage.getPanicIncreaseValue then
        originalPanicIncreaseValue = bodyDamage:getPanicIncreaseValue()
    end

    if stats.getPanic and stats:getPanic() < 3 then
        if originalPanicIncreaseValue ~= nil and bodyDamage.setPanicIncreaseValue then
            bodyDamage:setPanicIncreaseValue(originalPanicIncreaseValue)
        end
        return true
    end

    local px, py = player:getX(), player:getY()
    local seeDistance = 0
    if player.getSeeNearbyCharacterDistance then
        seeDistance = player:getSeeNearbyCharacterDistance()
    end
    local panicRadius = seeDistance + 2.0
    local onlyFriendlies = false
    local zombieList = NPCZombieCacheBridge and NPCZombieCacheBridge.CacheLight or {}

    for _, zombie in pairs(zombieList) do
        if zombie then
            local dist = distanceManhattan(zombie.x, zombie.y, px, py)
            if dist <= panicRadius then
                if zombie.brain and not zombie.brain.hostile then
                    onlyFriendlies = true
                else
                    onlyFriendlies = false
                    break
                end
            end
        end
    end

    if onlyFriendlies then
        if bodyDamage.setPanicIncreaseValue then
            bodyDamage:setPanicIncreaseValue(0.0)
        end
        if stats.setPanic then
            stats:setPanic(0)
        end
    else
        if originalPanicIncreaseValue ~= nil and bodyDamage.setPanicIncreaseValue then
            bodyDamage:setPanicIncreaseValue(originalPanicIncreaseValue)
        end
        originalPanicIncreaseValue = nil
    end

    return true
end

function PlayerClient.RecalculateStunlock(player)
    if not player or not player.setVariable then
        return false
    end

    local speed = playerClientGetLegacyNumber("General_StunlockHitSpeed")
    if speed ~= nil then
        player:setVariable("StunlockHitSpeed", speed)
    end

    if NPCFactionBridge and NPCFactionBridge.UpdateLocalPlayerTimer then
        NPCFactionBridge.UpdateLocalPlayerTimer(player)
    end
    return true
end

function PlayerClient.ResetNpcKills(player)
    if isServerOnly() or not player then
        return false
    end
    return safeSend(player, "Commands", NPC_PLAYER_COMMANDS.resetKills, { id = 0 })
end

function PlayerClient.UpdateVisitedBuilding()
    if isServerOnly() then
        return false
    end

    local player = localPlayer()
    local building = player and player.getBuilding and player:getBuilding()
    local buildingDef = building and building.getDef and building:getDef()
    if not buildingDef then
        return false
    end

    local bid = NPCUtils and NPCUtils.GetBuildingID and NPCUtils.GetBuildingID(buildingDef) or nil
    if not bid then
        return false
    end

    local worldAgeHours = 0
    if getGameTime then
        local gameTime = getGameTime()
        if gameTime and gameTime.getWorldAgeHours then
            worldAgeHours = gameTime:getWorldAgeHours()
        end
    end

    return safeSend(player, "Commands", "UpdateVisitedBuilding", { bid = bid, wah = worldAgeHours })
end

function PlayerClient.InstallEvents()
    if PlayerClient.__eventsInstalled then
        return false
    end

    if Events and Events.EveryOneMinute then
        Events.EveryOneMinute.Add(PlayerClient.UpdateOnlinePlayerPayload)
    end
    if Events and Events.OnPlayerUpdate then
        Events.OnPlayerUpdate.Add(PlayerClient.HandlePanic)
        Events.OnPlayerUpdate.Add(PlayerClient.RecalculateStunlock)
    end
    if Events and Events.OnPlayerDeath then
        Events.OnPlayerDeath.Add(PlayerClient.ResetNpcKills)
    end
    if Events and Events.EveryTenMinutes then
        Events.EveryTenMinutes.Add(PlayerClient.UpdateVisitedBuilding)
    end

    PlayerClient.__eventsInstalled = true
    return true
end

PlayerClient.InstallEvents()
