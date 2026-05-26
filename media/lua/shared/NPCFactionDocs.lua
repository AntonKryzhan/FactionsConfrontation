-- Legacy compatibility facade for the neutral NPC backend.
-- Compatibility facade for the neutral faction documents backend.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCFactionDocsBridge"

NPCLegacyGlobalsBridge.InstallAlias("FactionDocs", NPCFactionDocsBridge)
