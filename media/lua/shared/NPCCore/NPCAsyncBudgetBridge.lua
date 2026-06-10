-- NPCAsyncBudgetBridge.lua
-- Cooperative background budget lane for non-critical runtime maintenance.
--
-- This is not a thread system and it must not own visible NPC movement,
-- spawning, materialization, network contracts or save writes. Jobs are small
-- resumable maintenance tasks that prepare or compact runtime caches.

NPCAsyncBudgetBridge = NPCAsyncBudgetBridge or {}

NPCAsyncBudgetBridge.VERSION = "2026-06-02-stage360-fps-tuned-async-lane-1"
NPCAsyncBudgetBridge.Config = NPCAsyncBudgetBridge.Config or {
    enabled = true,
    maxJobsPerTick = 1,
    maxStepsPerJob = 32,
    maxQueuedJobs = 24,
    minIntervalTicks = 6,
    highLoadIntervalTicks = 12,
    disableOnCriticalLoad = true,
    debug = false
}
NPCAsyncBudgetBridge.Queue = NPCAsyncBudgetBridge.Queue or {}
NPCAsyncBudgetBridge.Index = NPCAsyncBudgetBridge.Index or {}
NPCAsyncBudgetBridge.Head = NPCAsyncBudgetBridge.Head or 1
NPCAsyncBudgetBridge.Tick = NPCAsyncBudgetBridge.Tick or 0

local function bab_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        return NPCLegacySettingsBridge.GetBool(name, defaultValue == true)
    end
    return defaultValue == true
end

local function bab_number(name, defaultValue, minValue, maxValue)
    local value = defaultValue
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        value = NPCLegacySettingsBridge.GetNumber(name, defaultValue, minValue, maxValue)
    end
    value = tonumber(value) or tonumber(defaultValue) or 0
    if minValue ~= nil and value < minValue then value = minValue end
    if maxValue ~= nil and value > maxValue then value = maxValue end
    return value
end

function NPCAsyncBudgetBridge.ApplySettings()
    local c = NPCAsyncBudgetBridge.Config
    c.enabled = bab_bool("AsyncBudget_Enabled", c.enabled ~= false)
    c.maxJobsPerTick = bab_number("AsyncBudget_MaxJobsPerTick", c.maxJobsPerTick or 1, 0, 32)
    c.maxStepsPerJob = bab_number("AsyncBudget_MaxStepsPerJob", c.maxStepsPerJob or 32, 1, 5000)
    c.maxQueuedJobs = bab_number("AsyncBudget_MaxQueuedJobs", c.maxQueuedJobs or 24, 1, 512)
    c.minIntervalTicks = bab_number("AsyncBudget_MinIntervalTicks", c.minIntervalTicks or 6, 1, 600)
    c.highLoadIntervalTicks = bab_number("AsyncBudget_HighLoadIntervalTicks", c.highLoadIntervalTicks or 12, 1, 1200)
    c.disableOnCriticalLoad = bab_bool("AsyncBudget_DisableOnCriticalLoad", c.disableOnCriticalLoad ~= false)
    c.debug = bab_bool("AsyncBudget_Debug", c.debug == true)
end

local function bab_log(msg)
    if NPCAsyncBudgetBridge.Config and NPCAsyncBudgetBridge.Config.debug then
        print("[NPCAsyncBudgetBridge] " .. tostring(msg))
    end
end

function NPCAsyncBudgetBridge.Schedule(name, fn, opts)
    if type(name) ~= "string" or name == "" or type(fn) ~= "function" then return false end
    opts = opts or {}
    if opts.critical == true or opts.visible == true then
        bab_log("rejected critical job " .. tostring(name))
        return false
    end

    local idx = NPCAsyncBudgetBridge.Index[name]
    local job = idx and NPCAsyncBudgetBridge.Queue[idx] or nil
    if not job then
        local maxQueued = tonumber(NPCAsyncBudgetBridge.Config.maxQueuedJobs) or 24
        if #NPCAsyncBudgetBridge.Queue >= maxQueued then
            bab_log("queue full, drop " .. tostring(name))
            return false
        end
        job = {name = name, cursor = 1}
        NPCAsyncBudgetBridge.Queue[#NPCAsyncBudgetBridge.Queue + 1] = job
        NPCAsyncBudgetBridge.Index[name] = #NPCAsyncBudgetBridge.Queue
    end

    job.fn = fn
    job.cursor = tonumber(job.cursor) or 1
    job.budget = tonumber(opts.budget) or job.budget or tonumber(NPCAsyncBudgetBridge.Config.maxStepsPerJob) or 32
    local minInterval = tonumber(NPCAsyncBudgetBridge.Config.minIntervalTicks) or 6
    job.interval = math.max(1, minInterval, tonumber(opts.interval) or job.interval or minInterval)
    job.nextTick = math.max(0, tonumber(opts.nextTick) or job.nextTick or 0)
    job.enabled = true
    return true
end

function NPCAsyncBudgetBridge.Cancel(name)
    name = tostring(name or "")
    local idx = NPCAsyncBudgetBridge.Index[name]
    if not idx then return false end
    local job = NPCAsyncBudgetBridge.Queue[idx]
    if job then
        job.enabled = false
        job.fn = nil
    end
    NPCAsyncBudgetBridge.Index[name] = nil
    return true
end

function NPCAsyncBudgetBridge.ProcessBudget()
    NPCAsyncBudgetBridge.Tick = (NPCAsyncBudgetBridge.Tick or 0) + 1
    local tick = NPCAsyncBudgetBridge.Tick
    if tick % 180 == 1 then
        NPCAsyncBudgetBridge.ApplySettings()
    end
    local cfg = NPCAsyncBudgetBridge.Config or {}
    if not (cfg.enabled ~= false) then return 0 end

    local minInterval = math.max(1, tonumber(cfg.minIntervalTicks) or 6)
    local loadLevel = 0
    if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.GetLoadLevel then
        local ok, level = pcall(function() return NPCWorkSchedulerBridge.GetLoadLevel(false) end)
        if ok then loadLevel = tonumber(level) or 0 end
    end
    if cfg.disableOnCriticalLoad ~= false and loadLevel >= 2 then
        return 0
    end
    if loadLevel >= 1 then
        minInterval = math.max(minInterval, tonumber(cfg.highLoadIntervalTicks) or minInterval)
    end
    if minInterval > 1 and (tick % minInterval) ~= 0 then
        return 0
    end

    local queue = NPCAsyncBudgetBridge.Queue
    if type(queue) ~= "table" or #queue == 0 then return 0 end
    local processed = 0
    local maxJobs = tonumber(NPCAsyncBudgetBridge.Config.maxJobsPerTick) or 1
    if maxJobs <= 0 then return 0 end

    local scans = 0
    while processed < maxJobs and scans < #queue do
        local head = tonumber(NPCAsyncBudgetBridge.Head) or 1
        if head > #queue then head = 1 end
        NPCAsyncBudgetBridge.Head = head + 1
        scans = scans + 1

        local job = queue[head]
        if job and job.enabled ~= false and type(job.fn) == "function" then
            local interval = math.max(1, tonumber(job.interval) or 1)
            local nextTick = tonumber(job.nextTick) or 0
            if tick >= nextTick and (interval <= 1 or (tick % interval) == 0) then
                local steps = math.max(1, tonumber(job.budget) or tonumber(NPCAsyncBudgetBridge.Config.maxStepsPerJob) or 32)
                local ok, doneOrErr = pcall(job.fn, job, steps, tick)
                processed = processed + 1
                if not ok then
                    print("[NPCAsyncBudgetBridge] job failed: " .. tostring(job.name) .. " / " .. tostring(doneOrErr))
                    job.enabled = false
                    job.fn = nil
                    NPCAsyncBudgetBridge.Index[job.name] = nil
                elseif doneOrErr == true then
                    job.enabled = false
                    job.fn = nil
                    NPCAsyncBudgetBridge.Index[job.name] = nil
                end
            end
        end
    end

    return processed
end

function NPCAsyncBudgetBridge.OnTick()
    NPCAsyncBudgetBridge.ProcessBudget()
end

NPCAsyncBudgetBridge.ApplySettings()

if not NPCAsyncBudgetBridge._registered then
    NPCAsyncBudgetBridge._registered = true
    if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.RegisterTickJob then
        NPCWorkSchedulerBridge.RegisterTickJob("NPCAsyncBudgetBridge.Process", NPCAsyncBudgetBridge.ProcessBudget, "system", 6, 1)
    elseif Events and Events.OnTick then
        Events.OnTick.Add(NPCAsyncBudgetBridge.OnTick)
    end
end
