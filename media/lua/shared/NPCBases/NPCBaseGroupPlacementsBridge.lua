NPCBaseGroupPlacementsBridge = NPCBaseGroupPlacementsBridge or {}

local function bbg_noWorldEdit()
    return false
end

function NPCBaseGroupPlacementsBridge.AllowWorldDecoration()
    return false
end

function NPCBaseGroupPlacementsBridge.IsRetired()
    return true
end

function NPCBaseGroupPlacementsBridge.CheckSpace(x, y, w, h)
    return false
end

function NPCBaseGroupPlacementsBridge.ClearSpace(x, y, z, w, h)
    return bbg_noWorldEdit()
end

function NPCBaseGroupPlacementsBridge.Junk(x, y, z, w, h, intensity)
    return bbg_noWorldEdit()
end

function NPCBaseGroupPlacementsBridge.Papers(x, y, z, w, h, intensity)
    return bbg_noWorldEdit()
end

function NPCBaseGroupPlacementsBridge.Item(item, x, y, z, w, h, intensity)
    return bbg_noWorldEdit()
end

function NPCBaseGroupPlacementsBridge.Blood(x, y, z, w, h, intensity)
    return bbg_noWorldEdit()
end
