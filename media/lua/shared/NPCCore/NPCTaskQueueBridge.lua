-- NPCTaskQueueBridge.lua
-- Cooperative task queue: spreads server-side work across ticks without unsafe OS threads.

require "NPCCore/NPCLegacySettingsBridge"
require "NPCCore/NPCStreamingRuntimeBridge"
require "NPCCore/NPCWorkSchedulerBridge"

NPCTaskQueueBridge = NPCTaskQueueBridge or {}

NPCTaskQueueBridge.Enabled = NPCTaskQueueBridge.Enabled ~= false
NPCTaskQueueBridge.Queues = NPCTaskQueueBridge.Queues or {high={}, normal={}, low={}}
NPCTaskQueueBridge.Head = NPCTaskQueueBridge.Head or {high=1, normal=1, low=1}
NPCTaskQueueBridge.Budget = NPCTaskQueueBridge.Budget or {high=6, normal=12, low=18}
NPCTaskQueueBridge.Tick = NPCTaskQueueBridge.Tick or 0

local function btq_settingBool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        return NPCLegacySettingsBridge.GetBool(name, defaultValue == true)
    end
    return defaultValue == true
end

local function btq_settingNumber(name, defaultValue, minValue, maxValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        return NPCLegacySettingsBridge.GetNumber(name, defaultValue, minValue, maxValue)
    end
    local value = tonumber(defaultValue) or 0
    if minValue ~= nil and value < minValue then value = minValue end
    if maxValue ~= nil and value > maxValue then value = maxValue end
    return value
end

local function btq_normalPriority(priority)
    priority = tostring(priority or "normal")
    if priority == "high" or priority == "low" then return priority end
    return "normal"
end

local function btq_compact(priority)
    local queue = NPCTaskQueueBridge.Queues[priority]
    local head = tonumber(NPCTaskQueueBridge.Head[priority]) or 1
    if head <= 64 then return end
    local newQueue = {}
    for i = head, #queue do
        table.insert(newQueue, queue[i])
    end
    NPCTaskQueueBridge.Queues[priority] = newQueue
    NPCTaskQueueBridge.Head[priority] = 1
end

function NPCTaskQueueBridge.ApplySettings()
    NPCTaskQueueBridge.Enabled = btq_settingBool("Runtime_TaskQueueEnabled", NPCTaskQueueBridge.Enabled ~= false)
    NPCTaskQueueBridge.Budget.high = btq_settingNumber("Runtime_TaskQueueHighBudget", NPCTaskQueueBridge.Budget.high or 6, 0, 200)
    NPCTaskQueueBridge.Budget.normal = btq_settingNumber("Runtime_TaskQueueNormalBudget", NPCTaskQueueBridge.Budget.normal or 12, 0, 300)
    NPCTaskQueueBridge.Budget.low = btq_settingNumber("Runtime_TaskQueueLowBudget", NPCTaskQueueBridge.Budget.low or 18, 0, 500)
end

function NPCTaskQueueBridge.Enqueue(fn, priority, label)
    if type(fn) ~= "function" then return false end
    priority = btq_normalPriority(priority)
    table.insert(NPCTaskQueueBridge.Queues[priority], {fn=fn, label=label or priority})
    return true
end

function NPCTaskQueueBridge.EnqueueCall(target, methodName, args, priority, label)
    if type(target) ~= "table" or type(target[methodName]) ~= "function" then return false end
    args = args or {}
    return NPCTaskQueueBridge.Enqueue(function()
        local unpacker = unpack or (table and table.unpack)
        return target[methodName](unpacker(args))
    end, priority, label or methodName)
end

function NPCTaskQueueBridge.PendingCount(priority)
    if priority then
        priority = btq_normalPriority(priority)
        local head = tonumber(NPCTaskQueueBridge.Head[priority]) or 1
        return math.max(0, #NPCTaskQueueBridge.Queues[priority] - head + 1)
    end
    return NPCTaskQueueBridge.PendingCount("high") + NPCTaskQueueBridge.PendingCount("normal") + NPCTaskQueueBridge.PendingCount("low")
end

function NPCTaskQueueBridge.ProcessPriority(priority)
    priority = btq_normalPriority(priority)
    local budget = tonumber(NPCTaskQueueBridge.Budget[priority]) or 0
    if NPCStreamingRuntimeBridge and NPCStreamingRuntimeBridge.AdjustTaskBudget then
        budget = NPCStreamingRuntimeBridge.AdjustTaskBudget(priority, budget)
    end
    if budget <= 0 then return 0 end

    local queue = NPCTaskQueueBridge.Queues[priority]
    local head = tonumber(NPCTaskQueueBridge.Head[priority]) or 1
    local processed = 0

    while head <= #queue and processed < budget do
        local task = queue[head]
        queue[head] = false
        head = head + 1
        processed = processed + 1
        if task and type(task.fn) == "function" then
            local ok, err = pcall(task.fn)
            if not ok then
                print("[NPCTaskQueueBridge] task failed: " .. tostring(task.label or priority) .. " / " .. tostring(err))
            end
        end
    end

    NPCTaskQueueBridge.Head[priority] = head
    btq_compact(priority)
    return processed
end

function NPCTaskQueueBridge.ProcessTick()
    if not NPCTaskQueueBridge.Enabled then return end
    NPCTaskQueueBridge.Tick = (NPCTaskQueueBridge.Tick or 0) + 1
    if NPCTaskQueueBridge.Tick % 60 == 1 then
        NPCTaskQueueBridge.ApplySettings()
    end
    NPCTaskQueueBridge.ProcessPriority("high")
    NPCTaskQueueBridge.ProcessPriority("normal")
    NPCTaskQueueBridge.ProcessPriority("low")
end

NPCTaskQueueBridge.ApplySettings()

if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.RegisterTickJob and not NPCTaskQueueBridge._registered then
    NPCTaskQueueBridge._registered = true
    NPCWorkSchedulerBridge.RegisterTickJob("NPCTaskQueueBridge", NPCTaskQueueBridge.ProcessTick, "persistent", 1)
elseif Events and Events.OnTick and not NPCTaskQueueBridge._registered then
    NPCTaskQueueBridge._registered = true
    Events.OnTick.Add(NPCTaskQueueBridge.ProcessTick)
end
