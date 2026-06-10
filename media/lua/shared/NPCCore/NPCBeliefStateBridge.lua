-- NPCBeliefStateBridge.lua
-- Lightweight Bayesian belief layer for combat, path and cover confidence.
-- Stages 339-342: runtime belief state feeding Brain/Router/Actions without replacing deterministic AI.

NPCBeliefStateBridge = NPCBeliefStateBridge or {}

NPCBeliefStateBridge.VERSION = "2026-05-31-stage339-bayesian-belief-layer-1"

NPCBeliefStateBridge.Config = NPCBeliefStateBridge.Config or {
    enabled = true,
    enemyPrior = 0.35,
    enemyMin = 0.02,
    enemyMax = 0.98,
    visibleLikelihood = 0.92,
    memoryLikelihood = 0.68,
    lineBlockedLikelihood = 0.40,
    sameFloorBonus = 0.08,
    recentDamageBonus = 0.12,
    decayHalfLifeMs = 5200,
    activeEnemyThreshold = 0.24,
    pathPrior = 0.76,
    pathSuccessBoost = 0.07,
    pathFailPenalty = 0.17,
    stuckPenalty = 0.22,
    pathMin = 0.05,
    pathMax = 0.98,
    coverPrior = 0.55,
    coverSuccessBoost = 0.08,
    coverFailPenalty = 0.10,
    maxRecentBeliefs = 64
}

local function bbelief_nowMs()
    if getTimestampMs then
        local ok, value = pcall(function() return getTimestampMs() end)
        if ok and value then return tonumber(value) or 0 end
    end
    if getGameTime then
        local ok, value = pcall(function() return getGameTime():getWorldAgeHours() end)
        if ok and value then return math.floor((tonumber(value) or 0) * 3600000) end
    end
    return os.time() * 1000
end

local function bbelief_clamp(value, lo, hi)
    value = tonumber(value) or 0
    if lo ~= nil and value < lo then return lo end
    if hi ~= nil and value > hi then return hi end
    return value
end

local function bbelief_dist2(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return dx * dx + dy * dy
end

local function bbelief_pos(chr)
    if not chr then return nil end
    local x = chr.getX and chr:getX() or nil
    local y = chr.getY and chr:getY() or nil
    local z = chr.getZ and chr:getZ() or 0
    if x == nil or y == nil then return nil end
    return {x=tonumber(x) or 0, y=tonumber(y) or 0, z=tonumber(z) or 0}
end

local function bbelief_charId(chr)
    if not chr then return nil end
    if NPCUtils and NPCUtils.GetCharacterID then
        local ok, id = pcall(function() return NPCUtils.GetCharacterID(chr) end)
        if ok and id ~= nil then return tostring(id) end
    end
    if NPCUtils and NPCUtils.GetZombieID then
        local ok, id = pcall(function() return NPCUtils.GetZombieID(chr) end)
        if ok and id ~= nil then return tostring(id) end
    end
    return tostring(chr)
end

local function bbelief_targetHash(taskOrPos)
    if type(taskOrPos) ~= "table" then return nil end
    if taskOrPos.x == nil or taskOrPos.y == nil then return nil end
    return tostring(math.floor(tonumber(taskOrPos.x) or 0)) .. ":" .. tostring(math.floor(tonumber(taskOrPos.y) or 0)) .. ":" .. tostring(math.floor(tonumber(taskOrPos.z) or 0))
end

local function bbelief_decay(value, ageMs, halfLifeMs)
    value = tonumber(value) or 0
    ageMs = math.max(0, tonumber(ageMs) or 0)
    halfLifeMs = math.max(1, tonumber(halfLifeMs) or 1)
    if ageMs <= 0 then return value end
    local factor = 0.5 ^ (ageMs / halfLifeMs)
    return value * factor
end

local function bbelief_bayes(prior, likelihood, falseLikelihood)
    prior = bbelief_clamp(prior, 0.001, 0.999)
    likelihood = bbelief_clamp(likelihood, 0.001, 0.999)
    falseLikelihood = bbelief_clamp(falseLikelihood or (1 - likelihood), 0.001, 0.999)
    local p = prior * likelihood
    local q = (1 - prior) * falseLikelihood
    if p + q <= 0 then return prior end
    return p / (p + q)
end

function NPCBeliefStateBridge.Get(brain)
    if type(brain) ~= "table" then return nil end
    brain.ai = brain.ai or {}
    brain.ai.beliefState = brain.ai.beliefState or {
        version = NPCBeliefStateBridge.VERSION,
        enemy = {},
        path = {},
        cover = {},
        line = {},
        recent = {}
    }
    return brain.ai.beliefState
end

function NPCBeliefStateBridge.Decay(brain, now)
    local state = NPCBeliefStateBridge.Get(brain)
    if not state then return nil end
    now = now or bbelief_nowMs()
    local cfg = NPCBeliefStateBridge.Config
    local enemy = state.enemy
    if enemy and enemy.updatedAt then
        local age = now - (tonumber(enemy.updatedAt) or now)
        enemy.confidence = bbelief_clamp(bbelief_decay(enemy.confidence, age, cfg.decayHalfLifeMs), cfg.enemyMin, cfg.enemyMax)
        enemy.updatedAt = now
    end
    return state
end

function NPCBeliefStateBridge.UpdateEnemy(brain, observer, target, evidence)
    if NPCBeliefStateBridge.Config.enabled ~= true then return nil end
    if not (brain and observer) then return nil end
    evidence = evidence or {}
    local state = NPCBeliefStateBridge.Get(brain)
    if not state then return nil end
    local cfg = NPCBeliefStateBridge.Config
    local now = bbelief_nowMs()
    NPCBeliefStateBridge.Decay(brain, now)

    local old = state.enemy or {}
    local prior = tonumber(old.confidence) or tonumber(brain.ai and brain.ai.enemyConfidence) or cfg.enemyPrior
    local visible = evidence.visible == true or evidence.detected == true
    local remembered = evidence.memory == true
    local lineClear = evidence.lineClear
    local sameFloor = evidence.sameFloor
    local recentDamage = evidence.recentDamage == true or evidence.underFire == true

    local likelihood = visible and cfg.visibleLikelihood or (remembered and cfg.memoryLikelihood or 0.44)
    if lineClear == false then likelihood = math.min(likelihood, cfg.lineBlockedLikelihood) end
    if sameFloor == true then likelihood = math.min(0.98, likelihood + cfg.sameFloorBonus) end
    if recentDamage then likelihood = math.min(0.98, likelihood + cfg.recentDamageBonus) end

    local confidence = bbelief_bayes(prior, likelihood, 1 - likelihood)
    confidence = bbelief_clamp(confidence, cfg.enemyMin, cfg.enemyMax)

    local pos = bbelief_pos(target)
    state.enemy = {
        id = evidence.targetId or bbelief_charId(target) or old.id,
        kind = evidence.kind or old.kind,
        x = pos and pos.x or evidence.x or old.x,
        y = pos and pos.y or evidence.y or old.y,
        z = pos and pos.z or evidence.z or old.z,
        dist = evidence.dist or old.dist,
        confidence = confidence,
        visible = visible,
        lineClear = lineClear,
        updatedAt = now,
        expiresAt = now + math.max(1200, tonumber(evidence.ttlMs) or 6200)
    }

    brain.ai = brain.ai or {}
    brain.ai.enemyConfidence = math.max(tonumber(brain.ai.enemyConfidence) or 0, confidence)
    brain.ai.enemyConfidenceUntilMs = math.max(tonumber(brain.ai.enemyConfidenceUntilMs) or 0, state.enemy.expiresAt)
    return state.enemy
end

function NPCBeliefStateBridge.GetEnemyConfidence(brain)
    local state = NPCBeliefStateBridge.Get(brain)
    if not state then return 0 end
    NPCBeliefStateBridge.Decay(brain)
    local enemy = state.enemy
    if not enemy then return tonumber(brain.ai and brain.ai.enemyConfidence) or 0 end
    local now = bbelief_nowMs()
    if enemy.expiresAt and now > tonumber(enemy.expiresAt) then return 0 end
    return tonumber(enemy.confidence) or 0
end

function NPCBeliefStateBridge.HasActiveEnemy(brain, threshold)
    threshold = tonumber(threshold) or tonumber(NPCBeliefStateBridge.Config.activeEnemyThreshold) or 0.24
    return NPCBeliefStateBridge.GetEnemyConfidence(brain) >= threshold
end

function NPCBeliefStateBridge.NotePathResult(brain, taskOrPos, success, detail)
    if NPCBeliefStateBridge.Config.enabled ~= true then return nil end
    local state = NPCBeliefStateBridge.Get(brain)
    if not state then return nil end
    local key = bbelief_targetHash(taskOrPos)
    if not key then return nil end
    local cfg = NPCBeliefStateBridge.Config
    local path = state.path[key] or {confidence=cfg.pathPrior, success=0, fail=0, stuck=0}
    if success == true then
        path.success = (tonumber(path.success) or 0) + 1
        path.confidence = bbelief_clamp((tonumber(path.confidence) or cfg.pathPrior) + cfg.pathSuccessBoost, cfg.pathMin, cfg.pathMax)
    else
        path.fail = (tonumber(path.fail) or 0) + 1
        if detail == "stuck" or detail == "no_progress" or detail == "lease_expired" then
            path.stuck = (tonumber(path.stuck) or 0) + 1
            path.confidence = bbelief_clamp((tonumber(path.confidence) or cfg.pathPrior) - cfg.stuckPenalty, cfg.pathMin, cfg.pathMax)
        else
            path.confidence = bbelief_clamp((tonumber(path.confidence) or cfg.pathPrior) - cfg.pathFailPenalty, cfg.pathMin, cfg.pathMax)
        end
    end
    path.updatedAt = bbelief_nowMs()
    state.path[key] = path
    return path
end

function NPCBeliefStateBridge.GetPathConfidence(brain, taskOrPos)
    local state = NPCBeliefStateBridge.Get(brain)
    if not state then return tonumber(NPCBeliefStateBridge.Config.pathPrior) or 0.76 end
    local key = bbelief_targetHash(taskOrPos)
    if not key or not state.path[key] then return tonumber(NPCBeliefStateBridge.Config.pathPrior) or 0.76 end
    return tonumber(state.path[key].confidence) or tonumber(NPCBeliefStateBridge.Config.pathPrior) or 0.76
end

function NPCBeliefStateBridge.NoteCoverResult(brain, coverKey, success)
    if not coverKey then return nil end
    local state = NPCBeliefStateBridge.Get(brain)
    if not state then return nil end
    local cfg = NPCBeliefStateBridge.Config
    local cover = state.cover[coverKey] or {confidence=cfg.coverPrior, success=0, fail=0}
    if success == true then
        cover.success = (tonumber(cover.success) or 0) + 1
        cover.confidence = bbelief_clamp((tonumber(cover.confidence) or cfg.coverPrior) + cfg.coverSuccessBoost, 0.02, 0.98)
    else
        cover.fail = (tonumber(cover.fail) or 0) + 1
        cover.confidence = bbelief_clamp((tonumber(cover.confidence) or cfg.coverPrior) - cfg.coverFailPenalty, 0.02, 0.98)
    end
    cover.updatedAt = bbelief_nowMs()
    state.cover[tostring(coverKey)] = cover
    return cover
end

function NPCBeliefStateBridge.TaskReliabilityModifier(brain, task)
    if not task then return 0 end
    local pathConfidence = NPCBeliefStateBridge.GetPathConfidence(brain, task)
    if pathConfidence < 0.30 then return -6 end
    if pathConfidence < 0.50 then return -3 end
    if pathConfidence > 0.88 then return 2 end
    return 0
end
