require "NPCServer/NPCIntelDossierServerBridge"

NPCIntelDossierServer = NPCIntelDossierServerBridge

if NPCIntelDossierServer and NPCIntelDossierServer.Install then
    NPCIntelDossierServer.Install()
end
