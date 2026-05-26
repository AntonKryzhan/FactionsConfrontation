require "NPCClient/NPCUpdateBridge"
local NPCUpdateBridge = NPCUpdateBridge

local uTick = 0

local function OnNPCUpdate(zombie)
    uTick = NPCUpdateBridge.OnNPCUpdate(zombie, uTick) or uTick
end

local function OnHitZombie(zombie, attacker, bodyPartType, handWeapon)
    return NPCUpdateBridge.OnHitZombie(zombie, attacker, bodyPartType, handWeapon)
end

local function OnZombieDead(zombie)
    return NPCUpdateBridge.OnZombieDead(zombie)
end

Events.OnZombieUpdate.Add(OnNPCUpdate)
Events.OnHitZombie.Add(OnHitZombie)
Events.OnZombieDead.Add(OnZombieDead)
