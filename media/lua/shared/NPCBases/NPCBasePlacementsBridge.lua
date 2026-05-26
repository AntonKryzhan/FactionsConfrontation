NPCBasePlacementsBridge = NPCBasePlacementsBridge or {}

local function bbp_retired()
    return false
end

local function bbp_noWorldEdit()
    return false
end

function NPCBasePlacementsBridge.AllowWorldDecoration()
    return false
end

function NPCBasePlacementsBridge.IsRetired()
    return true
end

function NPCBasePlacementsBridge.Matress(x, y, z)
    return bbp_noWorldEdit()
end

function NPCBasePlacementsBridge.IsoObject(sprite, x, y, z)
    return bbp_noWorldEdit()
end

function NPCBasePlacementsBridge.IsoThumpable(sprite, x, y, z)
    return bbp_noWorldEdit()
end

function NPCBasePlacementsBridge.IsoDoor(sprite, x, y, z)
    return bbp_noWorldEdit()
end

function NPCBasePlacementsBridge.IsoWindow(sprite, x, y, z)
    return bbp_noWorldEdit()
end

function NPCBasePlacementsBridge.IsoCurtain(sprite, x, y, z)
    return bbp_noWorldEdit()
end

function NPCBasePlacementsBridge.IsoLightSwitch(sprite, x, y, z)
    return bbp_noWorldEdit()
end

function NPCBasePlacementsBridge.IsoGenerator(sprite, x, y, z)
    return bbp_noWorldEdit()
end

function NPCBasePlacementsBridge.Container(sprite, x, y, z, items)
    return bbp_noWorldEdit()
end

function NPCBasePlacementsBridge.WaterContainer(sprite, x, y, z, items)
    return bbp_noWorldEdit()
end

function NPCBasePlacementsBridge.Fireplace(sprite, x, y, z, items)
    return bbp_noWorldEdit()
end

function NPCBasePlacementsBridge.Fridge(sprite, x, y, z)
    return bbp_noWorldEdit()
end

function NPCBasePlacementsBridge.Journal(title, story, x, y, z)
    return bbp_noWorldEdit()
end

function NPCBasePlacementsBridge.Item(item, x, y, z, q)
    return bbp_noWorldEdit()
end

function NPCBasePlacementsBridge.Blood(x, y, z, q)
    return bbp_noWorldEdit()
end

function NPCBasePlacementsBridge.Body(x, y, z, q)
    return bbp_noWorldEdit()
end
