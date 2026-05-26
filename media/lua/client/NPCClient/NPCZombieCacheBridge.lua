-- NPCZombieCacheBridge.lua
-- Neutral client bridge for the legacy legacy zombie cache client module.

-- Zombie cache
require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCZombieCacheBridge = NPCZombieCacheBridge or {}

local NPC_ZOMBIE_CACHE_LEGACY_LIGHT_FLAG = "is" .. NPCLegacyContractBridge.Token

-- consists of IsoZombie instances
NPCZombieCacheBridge.Cache = NPCZombieCacheBridge.Cache or {}

-- cache light consists of only necessary properties for fast manipulation
-- this cache has all zombies and bandits
NPCZombieCacheBridge.CacheLight = NPCZombieCacheBridge.CacheLight or {}

-- this cache has all zombies without bandits
NPCZombieCacheBridge.CacheLightZ = NPCZombieCacheBridge.CacheLightZ or {}

-- this cache has all bandit without zombies
NPCZombieCacheBridge.CacheLightB = NPCZombieCacheBridge.CacheLightB or {}

-- used for adaptive perofmance
NPCZombieCacheBridge.LastSize = 0

local NPC_ZOMBIE_CACHE_LEGACY_KEYS = {
    flag = NPCLegacyContractBridge.Key("FLAG")
}

local function bz_isNPCZombie(zombie)
    if not (zombie and zombie.getVariableBoolean) then return false end
    return zombie:getVariableBoolean(NPC_ZOMBIE_CACHE_LEGACY_KEYS.flag) == true
end

local function bz_suppressZombieSounds(zombie)
    if NPCEntity and NPCEntity.SurpressZombieSounds then
        return NPCEntity.SurpressZombieSounds(zombie)
    end
end

local function bz_getAverageFPS()
    if getAverageFPS then
        local ok, fps = pcall(function() return getAverageFPS() end)
        if ok and fps then return tonumber(fps) or 60 end
    end
    return 60
end

local function bz_getNumber(name, defaultValue, minValue, maxValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        return NPCLegacySettingsBridge.GetNumber(name, defaultValue, minValue, maxValue)
    end
    local value = tonumber(defaultValue) or 0
    if minValue ~= nil and value < minValue then value = minValue end
    if maxValue ~= nil and value > maxValue then value = maxValue end
    return value
end

local function bz_getCacheSkip(zombieListSize)
    local skip = bz_getNumber("AIWork_ZombieCacheBaseInterval", 4, 1, 120)
    local highSkip = bz_getNumber("AIWork_ZombieCacheHighInterval", 8, skip, 240)
    local criticalSkip = bz_getNumber("AIWork_ZombieCacheCriticalInterval", 12, highSkip, 480)
    local highZombies = bz_getNumber("AIWork_HighZombies", 220, 1, 3000)
    local criticalZombies = bz_getNumber("AIWork_CriticalZombies", 380, 1, 5000)
    local lowFPS = bz_getNumber("AIWork_LowFPS", 42, 5, 240)
    local criticalFPS = bz_getNumber("AIWork_CriticalFPS", 28, 5, 240)
    local fps = bz_getAverageFPS()

    if zombieListSize >= criticalZombies or fps <= criticalFPS then
        return math.max(1, math.floor(criticalSkip))
    end
    if zombieListSize >= highZombies or fps <= lowFPS then
        return math.max(1, math.floor(highSkip))
    end
    return math.max(1, math.floor(skip))
end

-- rebuids cache
local UpdateZombieCache = function(numberTicks)
    -- if true then return end 
    if isServer() then return end

    if not (NPCEntity and NPCEntity.Engine) then return end

    -- ts = getTimestampMs()
    -- if not numberTicks % 4 == 1 then return end

    local silenceStates = {"hitreaction", "hitreaction-hit", "hitreaction-gettingup", "hitreaction-knockeddown", "climbfence", "climbwindow"}

    -- adaptive performance: rebuilding the light cache scans the loaded zombie
    -- list, so stretch the rebuild interval only when the scene is already heavy.
    local cell = getCell()
    local zombieList = cell:getZombieList()
    local zombieListSize = zombieList:size()
    local skip = bz_getCacheSkip(zombieListSize)
    if numberTicks % skip ~= 0 then return end

    -- local ts = getTimestampMs()
    -- limit zombie map to player surrondings, helps performance
    -- local mr = 40
    local mr = math.ceil(100 - (zombieListSize / 4))
    if mr < 60 then mr = 60 end
    -- print ("MR: " .. mr)
    local player = getPlayer()
    if not player then return end
    local px = player:getX()
    local py = player:getY()

    -- prepare local cache vars
    local cache = {}
    local cacheLight = {}
    local cacheLightB = {}
    local cacheLightZ = {}

    for i = 0, zombieListSize - 1 do

        local zombie = zombieList:get(i)

        if not NPCCompatibilityBridge.IsReanimatedForGrappleOnly(zombie) then

            local id = NPCUtils.GetZombieID(zombie)

            cache[id] = zombie

            local zx, zy, zz = zombie:getX(), zombie:getY(), zombie:getZ()

            if math.abs(px - zx) < mr and math.abs(py - zy) < mr then
                local light = {id = id, x = zx, y = zy, z = zz}

                if bz_isNPCZombie(zombie) then
                    light[NPC_ZOMBIE_CACHE_LEGACY_LIGHT_FLAG] = true
                    light.brain = NPCBrainData.Get(zombie)
                    if NPCBlackMarketBridge and NPCBlackMarketBridge.IsNoCombatBrain and NPCBlackMarketBridge.IsNoCombatBrain(light.brain) then
                        light.noZombieTarget = true
                    end
                    cacheLightB[id] = light

                    -- zombies in hitreaction state are not processed by onzombieupdate
                    -- so we need to make them shut their zombie sound here too
                    -- logically this does not fit here, should be a separate process
                    -- but it's here due to performance optimization to avoid additional iteration
                    -- over zombieList
                    if math.abs(px - zx) < 12 and math.abs(py - zy) < 12 then
                        local asn = zombie:getActionStateName()
                        for _, ss in pairs(silenceStates) do
                            if asn == ss then
                                bz_suppressZombieSounds(zombie)
                                break
                            end
                        end

                        if asn == "bumped" then
                            local btype = zombie:getBumpType()
                            if btype and (btype == "ClimbWindow" or btype == "ClimbFence" or btype == "ClimbFenceEnd") then
                                bz_suppressZombieSounds(zombie)
                            end
                        end
                    end
                else
                    light[NPC_ZOMBIE_CACHE_LEGACY_LIGHT_FLAG] = false
                    cacheLightZ[id] = light
                end

                cacheLight[id] = light
            end
        end

    end

    -- recreate global cache vars with new findings
    NPCZombieCacheBridge.Cache = cache
    NPCZombieCacheBridge.CacheLight = cacheLight
    NPCZombieCacheBridge.CacheLightB = cacheLightB
    NPCZombieCacheBridge.CacheLightZ = cacheLightZ
    NPCZombieCacheBridge.LastSize = zombieListSize

    -- print ("BZ:" .. (getTimestampMs() - ts))
end 

-- returns IsoZombie by id
NPCZombieCacheBridge.GetInstanceById = function(id)
    if NPCZombieCacheBridge.Cache[id] then
        return NPCZombieCacheBridge.Cache[id]
    end
    return nil
end

-- returns all cache
NPCZombieCacheBridge.GetAll = function()
    return NPCZombieCacheBridge.CacheLight
end

-- returns all cached zombies
NPCZombieCacheBridge.GetAllZ = function()
    return NPCZombieCacheBridge.CacheLightZ
end

-- returns all cached bandits
NPCZombieCacheBridge.GetAllB = function()
    return NPCZombieCacheBridge.CacheLightB
end

-- returns size of zombie cache
NPCZombieCacheBridge.GetAllCnt = function()
    return NPCZombieCacheBridge.LastSize
end

Events.OnTick.Add(UpdateZombieCache)

NPCLegacyGlobalsBridge.InstallAlias("ZombieCache", NPCZombieCacheBridge, "NPCZombieCacheBridge")
