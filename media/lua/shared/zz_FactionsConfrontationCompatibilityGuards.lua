-- Factions Confrontation compatibility guards.
-- Stage 385: keep noisy third-party script/recipe/distribution issues from
-- turning into persistent console errors while leaving the owning mods intact.

FactionsConfrontationCompatibilityGuards = FactionsConfrontationCompatibilityGuards or {}

local function fc_safeAddMetalworkingXP(player, amount)
    if not (player and player.getXp and Perks) then return end
    local perk = Perks.MetalWelding or Perks.MetalWelding2 or Perks.Mechanics
    if not perk then return end
    pcall(function()
        local xp = player:getXp()
        if xp and xp.AddXP then xp:AddXP(perk, amount or 0) end
    end)
end

-- Scrap/blacksmithing packs sometimes reference LuaGiveXP = Give50MWXP, but
-- some workshop builds ship the recipe without the Lua function.  Defining this
-- no-op-safe XP hook prevents RecipeManager from spamming the console.
if type(Give50MWXP) ~= "function" then
    function Give50MWXP(recipe, ingredients, result, player)
        fc_safeAddMetalworkingXP(player, 50)
    end
end

local function fc_isDistributionContainer(t)
    return type(t) == "table" and (type(t.items) == "table" or type(t.junk) == "table" or t.rolls ~= nil)
end

local function fc_cleanDistributionItems(items)
    if type(items) ~= "table" then return {} end
    local cleaned = {}
    local i = 1
    while i <= #items do
        local item = items[i]
        local weight = tonumber(items[i + 1])
        if type(item) == "string" and item ~= "" and weight ~= nil then
            cleaned[#cleaned + 1] = item
            cleaned[#cleaned + 1] = weight
        end
        i = i + 2
    end
    return cleaned
end

local function fc_cleanDistributionContainer(container)
    if type(container) ~= "table" then return nil end
    if container.rolls ~= nil then container.rolls = tonumber(container.rolls) or 0 end
    if container.items ~= nil then container.items = fc_cleanDistributionItems(container.items) end
    if type(container.junk) == "table" then
        if container.junk.rolls ~= nil then container.junk.rolls = tonumber(container.junk.rolls) or 0 end
        if container.junk.items ~= nil then container.junk.items = fc_cleanDistributionItems(container.junk.items) end
    end
    if container.rolls == nil and container.items == nil and container.junk == nil then return nil end
    if container.rolls == nil then container.rolls = 0 end
    if container.items == nil then container.items = {} end
    return container
end

function FactionsConfrontationCompatibilityGuards.RepairLaboratoryDistribution()
    if type(SuburbsDistributions) ~= "table" then return end

    local room = SuburbsDistributions["laboratory"]
    if room == nil then
        SuburbsDistributions["laboratory"] = { all = { rolls = 0, items = {} } }
        return
    end

    if fc_isDistributionContainer(room) then
        local cleaned = fc_cleanDistributionContainer(room) or { rolls = 0, items = {} }
        SuburbsDistributions["laboratory"] = { all = cleaned }
        return
    end

    if type(room) ~= "table" then
        SuburbsDistributions["laboratory"] = { all = { rolls = 0, items = {} } }
        return
    end

    local any = false
    for key, value in pairs(room) do
        if type(value) == "table" then
            local cleaned = fc_cleanDistributionContainer(value)
            if cleaned then
                room[key] = cleaned
                any = true
            else
                room[key] = nil
            end
        else
            room[key] = nil
        end
    end

    if not any then
        room.all = { rolls = 0, items = {} }
    elseif room.all == nil then
        room.all = { rolls = 0, items = {} }
    end
end

FactionsConfrontationCompatibilityGuards.RepairLaboratoryDistribution()

if Events and Events.OnGameBoot and type(Events.OnGameBoot.Add) == "function" then
    Events.OnGameBoot.Add(FactionsConfrontationCompatibilityGuards.RepairLaboratoryDistribution)
end
