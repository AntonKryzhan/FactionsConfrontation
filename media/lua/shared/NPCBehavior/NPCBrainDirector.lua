-- NPCBrainDirector.lua
-- Safe full-state FSM / utility layer for neutral NPC runtime.
--
-- Safety contract:
-- 1. Does not modify ZAShoot.lua, ZAHit.lua or legacy weapon shoot program.
-- 2. Does not clear brain.tasks.
-- 3. Does not replace Shoot/Hit/Reload/Aim tasks.
-- 4. Does not use direct zombie target assignment or pathToCharacter on legacy NPC NPC.
-- 5. May only add low-priority movement/recovery/idle/utility tasks when the
--    legacy combat, healing, preservation and collision managers produced no task.

NPCBrainDirector = NPCBrainDirector or {}

require "NPCBehavior/NPCBrainDirectorBridge"

NPCBrainDirectorBridge.ApplyDefaults(NPCBrainDirector)

local bbd_runtime = NPCBrainDirectorBridge.CreateRuntime(NPCBrainDirector)

function NPCBrainDirector.InferState(bandit, brain, generatedTasks)
    return NPCBrainDirectorBridge.InferState(NPCBrainDirector, bbd_runtime, bandit, brain, generatedTasks)
end

function NPCBrainDirector.EvaluateDesiredState(bandit, brain, threat, stuck)
    return NPCBrainDirectorBridge.EvaluateDesiredState(NPCBrainDirector, bbd_runtime, bandit, brain, threat, stuck)
end

function NPCBrainDirector.Observe(bandit, uTick, generatedTasks)
    return NPCBrainDirectorBridge.Observe(NPCBrainDirector, bbd_runtime, bandit, uTick, generatedTasks)
end

function NPCBrainDirector.ExecuteState(bandit, brain, state, reason, threat)
    return NPCBrainDirectorBridge.ExecuteState(NPCBrainDirector, bbd_runtime, bandit, brain, state, reason, threat)
end

function NPCBrainDirector.PlanSafeTask(bandit, uTick)
    return NPCBrainDirectorBridge.PlanSafeTask(NPCBrainDirector, bbd_runtime, bandit, uTick)
end

-- Compatibility shim for older calls. Safe mode never requests task reset.
function NPCBrainDirector.Evaluate(bandit, uTick)
    return NPCBrainDirectorBridge.Evaluate(NPCBrainDirector, bbd_runtime, bandit, uTick)
end

function NPCBrainDirector.OnTasksQueued(bandit, decision, tasks)
    return NPCBrainDirectorBridge.OnTasksQueued(NPCBrainDirector, bbd_runtime, bandit, decision, tasks)
end

function NPCBrainDirector.GetDebugState(brain)
    return NPCBrainDirectorBridge.GetDebugState(NPCBrainDirector, bbd_runtime, brain)
end
