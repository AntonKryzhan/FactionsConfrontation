require "TimedActions/ISBaseTimedAction"

-- Emits a lightweight hook after a player timed action completes.
-- Guarded to avoid stacking wrappers if the file is loaded more than once.

if ISBaseTimedAction and not ISBaseTimedAction.__AKOnPerformHook then
    local originalPerform = ISBaseTimedAction.perform

    ISBaseTimedAction.perform = function(self)
        originalPerform(self)

        if triggerEvent then
            triggerEvent("OnTimedActionPerform", self)
        end
    end

    ISBaseTimedAction.__AKOnPerformHook = true
end
