-- Factions Confrontation compatibility guards.
-- Stage 397: reliable early-load version of the Stage 385 guards.

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

if type(Give50MWXP) ~= "function" then
    function Give50MWXP(recipe, ingredients, result, player)
        fc_safeAddMetalworkingXP(player, 50)
    end
end

local function fc_cleanDistributionItems(items)
    if type(items) ~= "table" then return {} end
    local cleaned = {}
    local i = 1
    local guard = 0
    while i <= #items do
        local item = items[i]
        local weight = tonumber(items[i + 1])
        if type(item) == "string" and item ~= "" and weight ~= nil then
            cleaned[#cleaned + 1] = item
            cleaned[#cleaned + 1] = weight
        end
        i = i + 2
        guard = guard + 1
        if guard > 4096 then break end
    end
    return cleaned
end

local function fc_cleanDistributionContainer(container)
    if type(container) ~= "table" then return nil end
    local rolls = tonumber(container.rolls)
    local items = fc_cleanDistributionItems(container.items)
    local cleaned = { rolls = rolls or 0, items = items }
    if type(container.junk) == "table" then
        cleaned.junk = {
            rolls = tonumber(container.junk.rolls) or 0,
            items = fc_cleanDistributionItems(container.junk.items)
        }
    end
    return cleaned
end

local function fc_isDistributionContainer(t)
    return type(t) == "table" and (type(t.items) == "table" or type(t.junk) == "table" or t.rolls ~= nil)
end

function FactionsConfrontationCompatibilityGuards.RepairLaboratoryDistribution()
    if type(SuburbsDistributions) ~= "table" then return false end

    local room = SuburbsDistributions["laboratory"]
    if room == nil or type(room) ~= "table" then
        SuburbsDistributions["laboratory"] = { all = { rolls = 0, items = {} } }
        return true
    end

    if fc_isDistributionContainer(room) then
        SuburbsDistributions["laboratory"] = { all = fc_cleanDistributionContainer(room) or { rolls = 0, items = {} } }
        return true
    end

    local repaired = {}
    local any = false
    for key, value in pairs(room) do
        if type(key) == "string" and type(value) == "table" then
            local cleaned = fc_cleanDistributionContainer(value)
            if cleaned then
                repaired[key] = cleaned
                any = true
            end
        end
    end

    if not any then
        repaired.all = { rolls = 0, items = {} }
    elseif repaired.all == nil then
        repaired.all = { rolls = 0, items = {} }
    end
    SuburbsDistributions["laboratory"] = repaired
    return true
end

local function fc_runCompatibilityRepairs()
    if FactionsConfrontationCompatibilityGuards and FactionsConfrontationCompatibilityGuards.RepairLaboratoryDistribution then
        FactionsConfrontationCompatibilityGuards.RepairLaboratoryDistribution()
    end
end

fc_runCompatibilityRepairs()

if Events then
    if Events.OnGameBoot and type(Events.OnGameBoot.Add) == "function" then Events.OnGameBoot.Add(fc_runCompatibilityRepairs) end
    if Events.OnInitGlobalModData and type(Events.OnInitGlobalModData.Add) == "function" then Events.OnInitGlobalModData.Add(fc_runCompatibilityRepairs) end
    if Events.OnLoad and type(Events.OnLoad.Add) == "function" then Events.OnLoad.Add(fc_runCompatibilityRepairs) end
end
