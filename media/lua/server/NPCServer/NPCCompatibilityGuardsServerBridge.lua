-- Stage 397 server-side compatibility pass for third-party distribution tables.

pcall(require, "NPCCompatibilityGuardsRuntime")

local function fc_runCompatibilityRepairsServer()
    if type(FactionsConfrontationCompatibilityGuards) == "table"
        and type(FactionsConfrontationCompatibilityGuards.RepairLaboratoryDistribution) == "function" then
        FactionsConfrontationCompatibilityGuards.RepairLaboratoryDistribution()
    end
end

fc_runCompatibilityRepairsServer()

if Events then
    if Events.OnGameBoot and type(Events.OnGameBoot.Add) == "function" then Events.OnGameBoot.Add(fc_runCompatibilityRepairsServer) end
    if Events.OnInitGlobalModData and type(Events.OnInitGlobalModData.Add) == "function" then Events.OnInitGlobalModData.Add(fc_runCompatibilityRepairsServer) end
    if Events.OnLoad and type(Events.OnLoad.Add) == "function" then Events.OnLoad.Add(fc_runCompatibilityRepairsServer) end
end
