-- NPCEffectsBridge.lua
-- Neutral client bridge for the legacy legacy effects client module.

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCLegacyGlobalsBridge"
NPCEffectsBridge = NPCEffectsBridge or {}

NPCEffectsBridge.tab = {}
NPCEffectsBridge.tick = 0

NPCEffectsBridge.Add = function(effect)

    table.insert(NPCEffectsBridge.tab, effect)
end

NPCEffectsBridge.Process = function()
    if isServer() then return end

    NPCEffectsBridge.tick = NPCEffectsBridge.tick + 1
    if NPCEffectsBridge.tick >= 16 then
        NPCEffectsBridge.tick = 0
    end

    if NPCEffectsBridge.tick % 2 == 0 then return end

    local cell = getCell()
    for i, effect in pairs(NPCEffectsBridge.tab) do

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
