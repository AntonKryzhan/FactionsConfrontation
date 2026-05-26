NPCActionBandageBridge = NPCActionBandageBridge or {}
require "NPCCore/NPCLegacyGlobalsBridge"

local NPC_ACTION_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
NPCUtils = NPCUtils or NPC_ACTION_LEGACY_GLOBALS.Get("Utils")


local bandageTargets = {
    {part=BodyPartType.Foot_R, anim="BandageRightLeg"},
    {part=BodyPartType.Foot_L, anim="BandageLeftLeg"},
    {part=BodyPartType.LowerLeg_R, anim="BandageRightLeg"},
    {part=BodyPartType.LowerLeg_L, anim="BandageLeftLeg"},
    {part=BodyPartType.UpperLeg_R, anim="BandageRightLeg"},
    {part=BodyPartType.UpperLeg_L, anim="BandageLeftLeg"},
    {part=BodyPartType.Groin, anim="BandageLowerBody"},
    {part=BodyPartType.Neck, anim="BandageHead"},
    {part=BodyPartType.Head, anim="BandageHead"},
    {part=BodyPartType.Torso_Lower, anim="BandageLowerBody"},
    {part=BodyPartType.Torso_Upper, anim="BandageUpperBody"},
    {part=BodyPartType.UpperArm_R, anim="BandageRightArm"},
    {part=BodyPartType.UpperArm_L, anim="BandageLeftArm"},
    {part=BodyPartType.ForeArm_R, anim="BandageRightArm"},
    {part=BodyPartType.ForeArm_L, anim="BandageLeftArm"},
    {part=BodyPartType.Hand_R, anim="BandageRightArm"},
    {part=BodyPartType.Hand_L, anim="BandageLeftArm"}
}

local function getCharacterIndexSeed(zombie)
    if not zombie then return 0 end
    if not NPCUtils or type(NPCUtils.GetCharacterID) ~= "function" then return 0 end

    local ok, characterId = pcall(function()
        return NPCUtils.GetCharacterID(zombie)
    end)
    if ok and type(characterId) == "number" then return characterId end
    return 0
end

local function getTargetIndex(zombie)
    if #bandageTargets == 0 then return 1 end
    return 1 + math.abs(getCharacterIndexSeed(zombie)) % #bandageTargets
end

local function getBandageTarget(zombie)
    return bandageTargets[getTargetIndex(zombie)] or bandageTargets[1]
end

local function setBumpAnimation(zombie, animationName)
    if not zombie or not animationName or type(zombie.setBumpType) ~= "function" then return end

    pcall(function()
        zombie:setBumpType(animationName)
    end)
end

local function getCurrentBump(zombie)
    if not zombie or type(zombie.getBumpType) ~= "function" then return nil end

    local ok, bump = pcall(function()
        return zombie:getBumpType()
    end)
    if ok then return bump end
    return nil
end

local function setRecoveredHealth(zombie)
    if not zombie or type(zombie.setHealth) ~= "function" then return end

    pcall(function()
        zombie:setHealth(2)
    end)
end

local function addBandageVisual(zombie, target)
    if not zombie or not target or not target.part then return end
    if type(zombie.addVisualBandage) ~= "function" then return end

    pcall(function()
        zombie:addVisualBandage(target.part, true)
    end)
end

local function applyBandageResult(zombie)
    if not zombie then return end
    local target = getBandageTarget(zombie)
    setRecoveredHealth(zombie)
    addBandageVisual(zombie, target)
end

function NPCActionBandageBridge.OnStart(zombie, task)
    if not zombie then return true end

    local target = getBandageTarget(zombie)
    if target then
        setBumpAnimation(zombie, target.anim)
    end
    return true
end

function NPCActionBandageBridge.OnWorking(zombie, task)
    if not zombie or not task then return true end
    if task.anim and getCurrentBump(zombie) ~= task.anim then return true end
    return false
end

function NPCActionBandageBridge.OnComplete(zombie, task)
    applyBandageResult(zombie)
    return true
end
