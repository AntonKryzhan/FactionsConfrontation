-- NPCHealthRegenBridge.lua
-- Neutral shared backend for health regeneration.

NPCHealthRegenBridge = NPCHealthRegenBridge or {}

NPCHealthRegenBridge.MinSpawnHealth = 3.0
NPCHealthRegenBridge.DefaultMaxHealth = 3.0
NPCHealthRegenBridge.HardMaxHealth = 4.0
NPCHealthRegenBridge.RegenDelayMs = 5500
NPCHealthRegenBridge.RegenRatePerSecond = 0.35
NPCHealthRegenBridge.HealthEpsilon = 0.002

local function bhr_nowMs()
    if getTimestampMs then return getTimestampMs() end
    if getGameTime then return math.floor((getGameTime():getWorldAgeHours() or 0) * 3600000) end
    return 0
end

local function bhr_clamp(value, low, high)
    value = tonumber(value) or low
    if value < low then return low end
    if value > high then return high end
    return value
end

local function bhr_getHealth(character)
    if not character or not character.getHealth then return nil end
    local ok, health = pcall(function() return character:getHealth() end)
    if not ok then return nil end
    return tonumber(health)
end

local function bhr_setHealth(character, health)
    if not character or not character.setHealth then return false end
    local ok = pcall(function() character:setHealth(health) end)
    return ok == true
end

function NPCHealthRegenBridge.ResolveMaxHealth(brain)
    local health = nil
    if brain then
        health = tonumber(brain.maxHealth) or tonumber(brain.health)
    end
    health = health or NPCHealthRegenBridge.DefaultMaxHealth
    if health < NPCHealthRegenBridge.MinSpawnHealth then
        health = NPCHealthRegenBridge.MinSpawnHealth
    end
    if health > NPCHealthRegenBridge.HardMaxHealth then
        health = NPCHealthRegenBridge.HardMaxHealth
    end
    return health
end

function NPCHealthRegenBridge.NormalizeSpawnHealth(health)
    health = tonumber(health) or NPCHealthRegenBridge.DefaultMaxHealth
    if health < NPCHealthRegenBridge.MinSpawnHealth then
        health = NPCHealthRegenBridge.MinSpawnHealth
    end
    if health > NPCHealthRegenBridge.HardMaxHealth then
        health = NPCHealthRegenBridge.HardMaxHealth
    end
    return health
end

function NPCHealthRegenBridge.ApplySpawnHealth(character, brain)
    brain = brain or (NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(character)) or nil

    local maxHealth = NPCHealthRegenBridge.ResolveMaxHealth(brain)
    if brain then
        brain.maxHealth = maxHealth
        brain.health = maxHealth
        brain.regen = brain.regen or {}
        brain.regen.lastHealth = maxHealth
        brain.regen.lastDamageAt = 0
        brain.regen.nextRegenAt = 0
        brain.regen.lastRegenAt = bhr_nowMs()
    end

    bhr_setHealth(character, maxHealth)
    return maxHealth
end

function NPCHealthRegenBridge.MarkDamaged(character)
    local brain = (NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(character)) or nil
    if not brain then return end

    local now = bhr_nowMs()
    local health = bhr_getHealth(character) or brain.health or NPCHealthRegenBridge.ResolveMaxHealth(brain)

    brain.regen = brain.regen or {}
    brain.regen.lastDamageAt = now
    brain.regen.nextRegenAt = now + NPCHealthRegenBridge.RegenDelayMs
    brain.regen.lastRegenAt = now
    brain.regen.lastHealth = health
    brain.health = health
end

function NPCHealthRegenBridge.Update(character, brain)
    if not character then return end
    if character.isDead and character:isDead() then return end
    if character.isAlive and not character:isAlive() then return end
    if character.isOnFire and character:isOnFire() then return end

    brain = brain or (NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(character)) or nil
    if not brain then return end

    local currentHealth = bhr_getHealth(character)
    if not currentHealth or currentHealth <= 0 then return end

    local maxHealth = NPCHealthRegenBridge.ResolveMaxHealth(brain)
    brain.maxHealth = maxHealth

    if currentHealth > maxHealth then
        currentHealth = maxHealth
        bhr_setHealth(character, currentHealth)
    end

    local now = bhr_nowMs()
    brain.regen = brain.regen or {}

    if not brain.regen.lastHealth then
        brain.regen.lastHealth = currentHealth
    end
    if not brain.regen.lastRegenAt then
        brain.regen.lastRegenAt = now
    end
    if not brain.regen.nextRegenAt then
        brain.regen.nextRegenAt = now
    end

    if currentHealth < brain.regen.lastHealth - NPCHealthRegenBridge.HealthEpsilon then
        brain.regen.lastDamageAt = now
        brain.regen.nextRegenAt = now + NPCHealthRegenBridge.RegenDelayMs
        brain.regen.lastRegenAt = now
        brain.regen.lastHealth = currentHealth
        brain.health = currentHealth
        return
    end

    if NPCHealthRegenBridge.AutoRegenEnabled == false then
        brain.health = currentHealth
        brain.regen.lastHealth = currentHealth
        brain.regen.lastRegenAt = now
        return
    end

    if currentHealth >= maxHealth - NPCHealthRegenBridge.HealthEpsilon then
        if currentHealth < maxHealth then
            bhr_setHealth(character, maxHealth)
            currentHealth = maxHealth
        end
        brain.health = maxHealth
        brain.regen.lastHealth = maxHealth
        brain.regen.lastRegenAt = now
        return
    end

    if now < brain.regen.nextRegenAt then
        brain.health = currentHealth
        brain.regen.lastHealth = currentHealth
        return
    end

    local dt = now - (brain.regen.lastRegenAt or now)
    if dt < 0 then dt = 0 end
    if dt > 1000 then dt = 1000 end

    local delta = NPCHealthRegenBridge.RegenRatePerSecond * (dt / 1000)
    if delta <= 0 then delta = NPCHealthRegenBridge.RegenRatePerSecond * 0.05 end

    local newHealth = currentHealth + delta
    if newHealth > maxHealth then newHealth = maxHealth end

    if newHealth > currentHealth then
        bhr_setHealth(character, newHealth)
        brain.health = newHealth
        brain.regen.lastHealth = newHealth
    else
        brain.health = currentHealth
        brain.regen.lastHealth = currentHealth
    end
    brain.regen.lastRegenAt = now
end
