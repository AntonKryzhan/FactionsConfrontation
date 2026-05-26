NPCPersistenceClient = NPCPersistenceClient or {}

local function getGMD()
    if GetNPCModData then
        local ok, gmd = pcall(GetNPCModData)
        if ok then
            return gmd
        end
    end
    return nil
end

local function canRestoreBrain(gmdBrain, cache)
    if not gmdBrain or not gmdBrain.permanent or gmdBrain.inVehicle then
        return false
    end
    if not gmdBrain.id and not gmdBrain.brainId then
        -- Queue keys are used as IDs by the caller; absence here is not fatal.
        return true
    end
    return true
end

function NPCPersistenceClient.Check()
    local gmd = getGMD()
    if not gmd or not gmd.Queue then
        return
    end

    local cache = NPCZombieCacheBridge and NPCZombieCacheBridge.CacheLightB or nil
    if not cache then
        return
    end

    local player = getSpecificPlayer and getSpecificPlayer(0) or nil
    if not player or not sendClientCommand then
        return
    end

    local cell = getCell and getCell() or nil
    if not cell or not cell.getGridSquare then
        return
    end

    for id, gmdBrain in pairs(gmd.Queue) do
        if canRestoreBrain(gmdBrain, cache) and not cache[id] then
            local born = gmdBrain.bornCoords
            if born and born.x and born.y and born.z then
                local square = cell:getGridSquare(born.x, born.y, born.z)
                if square then
                    sendClientCommand(player, "NPCCommands", "SpawnRestore", gmdBrain)
                end
            end
        end
    end
end

function NPCPersistenceClient.Install()
    if NPCPersistenceClient._installed then
        return
    end
    NPCPersistenceClient._installed = true
    if Events and Events.EveryOneMinute and Events.EveryOneMinute.Add then
        Events.EveryOneMinute.Add(NPCPersistenceClient.Check)
    end
end

return NPCPersistenceClient
