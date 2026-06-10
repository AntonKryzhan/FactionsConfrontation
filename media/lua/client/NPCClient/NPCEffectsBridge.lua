-- NPCEffectsBridge.lua
-- Neutral client bridge for the legacy legacy effects client module.

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCLegacyGlobalsBridge"
pcall(require, "NPCCore/NPCRenderReliefBridge")
NPCEffectsBridge = NPCEffectsBridge or {}

NPCEffectsBridge.tab = {}
NPCEffectsBridge.tick = 0
NPCEffectsBridge._compactTick = 0

local function npc_effects_stat(name, amount)
    if NPCUpdateBridge and NPCUpdateBridge.IncRuntimeOptimizationStat then
        NPCUpdateBridge.IncRuntimeOptimizationStat(name, amount)
    end
end

function NPCEffectsBridge.QueueCount()
    local count = 0
    for _, effect in pairs(NPCEffectsBridge.tab) do
        if effect ~= nil then count = count + 1 end
    end
    return count
end

function NPCEffectsBridge.CompactQueue()
    local compact = {}
    for _, effect in pairs(NPCEffectsBridge.tab) do
        if effect ~= nil then table.insert(compact, effect) end
    end
    NPCEffectsBridge.tab = compact
    return #compact
end

NPCEffectsBridge.Add = function(effect)

    local queued = #NPCEffectsBridge.tab
    if NPCRenderReliefBridge and NPCRenderReliefBridge.ShouldCullClientEffect then
        local okCull, cull = pcall(function() return NPCRenderReliefBridge.ShouldCullClientEffect(effect, queued) end)
        if okCull and cull == true then
            npc_effects_stat("effects_queue_culled")
            return
        end
    end

    npc_effects_stat("effects_queue_added")
    table.insert(NPCEffectsBridge.tab, effect)
end

NPCEffectsBridge.Process = function()
    if isServer() then return end

    NPCEffectsBridge.tick = NPCEffectsBridge.tick + 1
    if NPCEffectsBridge.tick >= 16 then
        NPCEffectsBridge.tick = 0
    end

    local queued = #NPCEffectsBridge.tab
    local processBudget = 999999
    local processInterval = 2
    if NPCRenderReliefBridge and NPCRenderReliefBridge.GetClientEffectProcessBudget then
        local okBudget, budget, interval = pcall(function() return NPCRenderReliefBridge.GetClientEffectProcessBudget(queued) end)
        if okBudget then
            processBudget = tonumber(budget) or processBudget
            processInterval = math.max(1, tonumber(interval) or processInterval)
        end
    end

    if NPCEffectsBridge.tick % processInterval ~= 1 then
        npc_effects_stat("effects_process_deferred")
        return
    end

    if queued > 120 then
        NPCEffectsBridge._compactTick = (NPCEffectsBridge._compactTick or 0) + 1
        if NPCEffectsBridge._compactTick >= 8 then
            NPCEffectsBridge._compactTick = 0
            queued = NPCEffectsBridge.CompactQueue()
        end
    end

    local processed = 0
    local cell = getCell()
    for i, effect in pairs(NPCEffectsBridge.tab) do
        processed = processed + 1
        if processed > processBudget then
            npc_effects_stat("effects_process_budget_stop")
            break
        end

        local square = cell:getGridSquare(effect.x, effect.y, effect.z)
        if square then

            if not effect.repCnt then effect.repCnt = 1 end
            if not effect.rep then effect.rep = 1 end

            if not effect.frame then 

                local dummy = IsoObject.new(square, "")

                dummy:setOffsetX(effect.offset)
                dummy:setOffsetY(effect.offset)

                -- square:AddTileObject(dummy)
                square:AddSpecialObject(dummy)
                if effect.frameRnd then
                    effect.frame = 1 + ZombRand(effect.frameCnt)
                else
                    effect.frame = 1
                end

                effect.object = dummy

                if effect.r and effect.g and effect.g then
                    effect.object:setCustomColor(effect.r, effect.g, effect.b, 0)
                end

            end
            
            if effect.frame > effect.frameCnt and effect.rep >= effect.repCnt then
                square:RemoveTileObject(effect.object)
                NPCEffectsBridge.tab[i] = nil
                npc_effects_stat("effects_completed")
            else
                if effect.frame > effect.frameCnt then
                    effect.rep = effect.rep + 1
                    effect.frame = 1
                end

                local frameStr = string.format("%03d", effect.frame)
                local alpha = (effect.repCnt - effect.rep + 1) / effect.repCnt
                local sprite = effect.object:getSprite()
                
                if sprite then
                    effect.object:getSprite():LoadFrameExplicit("media/textures/FX/" .. effect.name .. "/" .. frameStr .. ".png")
                    --effect.object:setAlpha(alpha)
                    effect.frame = effect.frame + 1
                end
            end
        else
            NPCEffectsBridge.tab[i] = nil
            npc_effects_stat("effects_removed_missing_square")
        end
    end
end

local onServerCommand = function(mod, command, args)
    if NPCLegacyContractBridge.IsModule(mod, "NPCEffects", "effects") then
        NPCEffectsBridge[command](args)
    end
end

Events.OnServerCommand.Add(onServerCommand)
Events.OnTick.Add(NPCEffectsBridge.Process)

NPCLegacyGlobalsBridge.InstallAlias("Effects", NPCEffectsBridge, "NPCEffectsBridge")
