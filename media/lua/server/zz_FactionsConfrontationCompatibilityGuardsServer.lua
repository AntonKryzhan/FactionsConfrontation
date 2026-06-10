-- Stage 385 server-side compatibility pass.
-- Shared guards define the implementation; this late server file calls it after
-- server-side distribution tables from other mods had a chance to load.

local function fc_runCompatibilityRepairs()
    if type(FactionsConfrontationCompatibilityGuards) == "table"
        and type(FactionsConfrontationCompatibilityGuards.RepairLaboratoryDistribution) == "function" then
        FactionsConfrontationCompatibilityGuards.RepairLaboratoryDistribution()
    end
end

fc_runCompatibilityRepairs()

if Events and Events.OnGameBoot and type(Events.OnGameBoot.Add) == "function" then
    Events.OnGameBoot.Add(fc_runCompatibilityRepairs)
end
