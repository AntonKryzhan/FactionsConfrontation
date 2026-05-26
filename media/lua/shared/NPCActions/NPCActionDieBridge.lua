NPCActionDieBridge = NPCActionDieBridge or {}
require "NPCCore/NPCLegacyGlobalsBridge"

local NPC_ACTION_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
NPCEntity = NPCEntity or NPC_ACTION_LEGACY_GLOBALS.Get("Entity")


local function sayDeathLine(zombie, task)
    if not NPCEntity or not NPCEntity.Say then return end
    if task and task.fire == true then
        NPCEntity.Say(zombie, "BURN", true)
    else
        NPCEntity.Say(zombie, "DRAGDOWN", true)
    end
end

local function getFakeAttacker()
    local cell = getCell()
    if cell and cell.getFakeZombieForHit then
        return cell:getFakeZombieForHit()
    end
    return nil
end

function NPCActionDieBridge.OnStart(zombie, task)
    if not zombie then return true end
    if zombie.clearAttachedItems then zombie:clearAttachedItems() end
    sayDeathLine(zombie, task)
    return true
end

function NPCActionDieBridge.OnWorking(zombie, task)
    if not zombie or not task then return true end
    if task.anim and zombie:getBumpType() ~= task.anim then return true end
    return false
end

function NPCActionDieBridge.OnComplete(zombie, task)
    if not zombie then return true end
    if zombie.setHealth then zombie:setHealth(0) end
    if zombie.clearAttachedItems then zombie:clearAttachedItems() end
    if ZombieOnGroundState and zombie.changeState then
        zombie:changeState(ZombieOnGroundState.instance())
    end
    local attacker = getFakeAttacker()
    if attacker and zombie.setAttackedBy then zombie:setAttackedBy(attacker) end
    if zombie.becomeCorpse then zombie:becomeCorpse() end
    return true
end
