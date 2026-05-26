require "NPCActions/NPCActionFaceLocationBridge"

ZombieActions = ZombieActions or {}

ZombieActions.FaceLocation = ZombieActions.FaceLocation or {}

ZombieActions.FaceLocation.onStart = function(zombie, task)
    return NPCActionFaceLocationBridge.OnStart(zombie, task)
end

ZombieActions.FaceLocation.onWorking = function(zombie, task)
    return NPCActionFaceLocationBridge.OnWorking(zombie, task)
end

ZombieActions.FaceLocation.onComplete = function(zombie, task)
    return NPCActionFaceLocationBridge.OnComplete(zombie, task)
end
