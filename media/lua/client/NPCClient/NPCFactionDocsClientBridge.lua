require "NPCCore/NPCLegacyContractBridge"
NPCFactionDocsClientBridge = NPCFactionDocsClientBridge or {}

local function faction_docs_player()
    return getPlayer() or getSpecificPlayer(0)
end

local function faction_docs_halo(text, r, g, b)
    local player = faction_docs_player()
    if HaloTextHelper and player and text then
        HaloTextHelper.addText(player, tostring(text), r or 180, g or 230, b or 255)
    end
end

function NPCFactionDocsClientBridge.RequestStatus(player)
    player = player or faction_docs_player()
    if not player then return end
    sendClientCommand(player, 'NPCFactionDocs', 'RequestStatus', {})
end

function NPCFactionDocsClientBridge.OnServerCommand(module, command, args)
    if not NPCLegacyContractBridge.IsModule(module, "NPCFactionDocs", "factionDocs") then return end
    if command == "Result" and args and args.text then
        faction_docs_halo(args.text, args.r, args.g, args.b)
    end
end

function NPCFactionDocsClientBridge.Install()
    Events.OnServerCommand.Add(NPCFactionDocsClientBridge.OnServerCommand)
end
