NPCLegacyContractBridge = NPCLegacyContractBridge or {}

local TOKEN = NPCLegacyContractBridge.Token or "FactionConfrontation"
local PLURAL = NPCLegacyContractBridge.Plural or "FactionsConfrontation"

NPCLegacyContractBridge.Token = TOKEN
NPCLegacyContractBridge.Plural = PLURAL

local function put(tbl, upper, lower, value)
    tbl[upper] = tbl[upper] or value
    if lower then tbl[lower] = tbl[lower] or value end
end

local Keys = NPCLegacyContractBridge.Keys or {}
put(Keys, "FLAG", "flag", TOKEN)
Keys.liveFlag = Keys.liveFlag or Keys.FLAG
put(Keys, "IS_FLAG", "isFlag", "Is" .. TOKEN)
Keys.isNPC = Keys.isNPC or Keys.IS_FLAG
put(Keys, "BLACK_MARKET", "blackMarket", TOKEN .. "BlackMarket")
put(Keys, "FORMER_ZOMBIE", "formerNPCZombie", TOKEN .. "FormerNPCZombie")
put(Keys, "FORMER_ZOMBIE_AT", "formerNPCZombieAt", TOKEN .. "FormerNPCZombieAt")
put(Keys, "FORMER_ZOMBIE_SIDE", "formerNPCZombieSide", TOKEN .. "FormerNPCZombieSide")
put(Keys, "RUNTIME_ID", "runtimeId", TOKEN .. "RuntimeId")
put(Keys, "PERSISTENT_ID", "persistentId", TOKEN .. "PersistentId")
put(Keys, "WORLD_GROUP_ID", "worldGroupId", TOKEN .. "WorldGroupId")
put(Keys, "PROGRAM", "program", TOKEN .. "Program")
put(Keys, "RUNTIME_REMOVED", "runtimeRemoved", TOKEN .. "RuntimeRemoved")
put(Keys, "RUNTIME_REMOVE_REASON", "runtimeRemoveReason", TOKEN .. "RuntimeRemoveReason")
put(Keys, "RUNTIME_REMOVED_AT", "runtimeRemovedAt", TOKEN .. "RuntimeRemovedAt")
put(Keys, "PRIMARY", "primary", TOKEN .. "Primary")
put(Keys, "PRIMARY_TYPE", "primaryType", TOKEN .. "PrimaryType")
put(Keys, "SECONDARY", "secondary", TOKEN .. "Secondary")
put(Keys, "WALK_TYPE", "walkType", TOKEN .. "WalkType")
put(Keys, "TARGET", "target", TOKEN .. "Target")
put(Keys, "TORCH", "torch", TOKEN .. "Torch")
put(Keys, "VISUAL_SIG", "visualSig", TOKEN .. "VisualsAppliedSig")
put(Keys, "VISUAL_AT", "visualAt", TOKEN .. "VisualsApplyAt")
put(Keys, "ZOMBIE_PATH_AT", "zombiePathAt", TOKEN .. "Zombie" .. TOKEN .. "PathAt")
put(Keys, "ZOMBIE_PATH_KEY", "zombiePathKey", TOKEN .. "Zombie" .. TOKEN .. "PathKey")
put(Keys, "ZOMBIE_PATH_DENIED_AT", "zombiePathDeniedAt", TOKEN .. "Zombie" .. TOKEN .. "PathDeniedAt")
put(Keys, "ZOMBIE_DAMAGE_AT", "zombieDamageAt", TOKEN .. "ZombieDamageAt")
put(Keys, "SHOT_AGGRO_PATH_AT", "shotAggroPathAt", TOKEN .. "ShotAggroPathAt")
put(Keys, "IMMEDIATE_ANIM", "immediateAnim", TOKEN .. "ImmediateAnim")
put(Keys, "BLACK_MARKET_PROP", "blackMarketProp", TOKEN .. "BlackMarketWorldProp")
put(Keys, "RADIO_SUPPLY_CACHE", "radioSupplyCache", TOKEN .. "RadioSupplyCache")
put(Keys, "RADIO_SUPPLY_CACHE_TIER", "radioSupplyCacheTier", TOKEN .. "RadioSupplyCacheTier")
put(Keys, "RADIO_SUPPLY_CACHE_ITEMS", "radioSupplyCacheItems", TOKEN .. "RadioSupplyCacheItems")
put(Keys, "RADIO_SUPPLY_CACHE_AT", "radioSupplyCacheAt", TOKEN .. "RadioSupplyCacheAt")
put(Keys, "EQUIP_EVENT_GUARD", "equipEventGuard", TOKEN .. "EquipEventGuard")
put(Keys, "EQUIP_EVENT_GUARD_HAND", "equipEventGuardHand", TOKEN .. "EquipEventGuardHand")
put(Keys, "EQUIP_EVENT_GUARD_ITEM", "equipEventGuardItem", TOKEN .. "EquipEventGuardItem")
put(Keys, "EQUIP_EVENT_GUARD_AT", "equipEventGuardAt", TOKEN .. "EquipEventGuardAt")
put(Keys, "EQUIP_EVENT_ERROR", "equipEventError", TOKEN .. "EquipEventError")
put(Keys, "EQUIP_EVENT_ERROR_HAND", "equipEventErrorHand", TOKEN .. "EquipEventErrorHand")
put(Keys, "EQUIP_EVENT_ERROR_AT", "equipEventErrorAt", TOKEN .. "EquipEventErrorAt")
NPCLegacyContractBridge.Keys = Keys

local Commands = NPCLegacyContractBridge.Commands or {}
put(Commands, "REMOVE", "remove", TOKEN .. "Remove")
put(Commands, "FLUSH", "flush", TOKEN .. "Flush")
put(Commands, "UPDATE_PART_COMMAND", "updatePartCommand", TOKEN .. "UpdatePart")
put(Commands, "UPDATE_PART", "updatePart", "Update" .. TOKEN .. "Part")
put(Commands, "REMOVE_OBJECTS", "removeObjects", "Remove" .. TOKEN .. "Objects")
put(Commands, "TELEPORT_OBJECTS", "teleportObjects", "Teleport" .. TOKEN .. "Objects")
put(Commands, "INCREMENT_KILLS", "incrementKills", "Increment" .. TOKEN .. "Kills")
put(Commands, "RESET_KILLS", "resetKills", "Reset" .. TOKEN .. "Kills")
NPCLegacyContractBridge.Commands = Commands

local Programs = NPCLegacyContractBridge.Programs or {}
put(Programs, "RAIDER", "raider", TOKEN)
NPCLegacyContractBridge.Programs = Programs

NPCLegacyContractBridge.Modules = NPCLegacyContractBridge.Modules or {
    baseCamp = TOKEN .. "BaseCamp",
    baseSupply = TOKEN .. "BaseSupply",
    blackMarket = TOKEN .. "BlackMarket",
    bounty = TOKEN .. "Bounty",
    checkpoints = TOKEN .. "Checkpoints",
    contracts = TOKEN .. "Contracts",
    convoys = TOKEN .. "Convoys",
    debugMap = TOKEN .. "DebugMap",
    disguise = TOKEN .. "Disguise",
    effects = TOKEN .. "Effects",
    faction = TOKEN .. "Faction",
    factionDocs = TOKEN .. "FactionDocs",
    leaders = TOKEN .. "Leaders",
    loyalty = TOKEN .. "Loyalty",
    radioIntercept = TOKEN .. "RadioIntercept",
    signals = TOKEN .. "Signals",
    sim = TOKEN .. "Sim",
    wounded = TOKEN .. "Wounded",
    worldRules = TOKEN .. "WorldRules"
}

NPCLegacyContractBridge.ModData = NPCLegacyContractBridge.ModData or {
    data = TOKEN,
    players = TOKEN .. "Players",
    bandits = PLURAL
}

NPCLegacyContractBridge.Sandbox = NPCLegacyContractBridge.Sandbox or {
    main = PLURAL,
    ext = PLURAL .. "Ext"
}

NPCLegacyContractBridge.Text = NPCLegacyContractBridge.Text or {
    prefix = "IGUI_" .. PLURAL .. "_"
}

NPCLegacyContractBridge.Items = NPCLegacyContractBridge.Items or {
    propaneTorch = PLURAL .. ".PropaneTorch",
    wateringCan = PLURAL .. ".WateringCan",
    bucket = PLURAL .. ".Bucket"
}

NPCLegacyContractBridge.Outfits = NPCLegacyContractBridge.Outfits or {
    generic = TOKEN,
    early = TOKEN .. "_Early",
    mid = TOKEN .. "_Mid",
    late = TOKEN .. "_Late",
    brita = "Brita_" .. TOKEN,
    brita2 = "Brita_" .. TOKEN .. "_2"
}

NPCLegacyContractBridge.WorldRuleFields = NPCLegacyContractBridge.WorldRuleFields or {
    lastSyncReason = TOKEN .. "WorldRulesLastSyncReason",
    lastSyncAt = TOKEN .. "WorldRulesLastSyncAt"
}

NPCLegacyContractBridge.State = NPCLegacyContractBridge.State or {
    removeObjectQueue = "_remove" .. TOKEN .. "ObjectQueue",
    formerCleanupScopes = "_former" .. TOKEN .. "CleanupScopes",
    formerCleanupTick = "_former" .. TOKEN .. "CleanupTick"
}

local Functions = NPCLegacyContractBridge.Functions or {}
Functions.initModData = Functions.initModData or ("Init" .. TOKEN .. "ModData")
Functions.loadModData = Functions.loadModData or ("Load" .. TOKEN .. "ModData")
Functions.getModData = Functions.getModData or ("Get" .. TOKEN .. "ModData")
Functions.getModDataPlayers = Functions.getModDataPlayers or ("Get" .. TOKEN .. "ModDataPlayers")
Functions.transmitModData = Functions.transmitModData or ("Transmit" .. TOKEN .. "ModData")
Functions.transmitModDataPlayers = Functions.transmitModDataPlayers or ("Transmit" .. TOKEN .. "ModDataPlayers")
NPCLegacyContractBridge.Functions = Functions

local Members = NPCLegacyContractBridge.Members or {}
Members.removeLoadedObjects = Members.removeLoadedObjects or ("RemoveLoaded" .. TOKEN .. "Objects")
Members.flushFormerCleanupScopes = Members.flushFormerCleanupScopes or ("FlushFormer" .. TOKEN .. "CleanupScopes")
Members.requestObjectCleanup = Members.requestObjectCleanup or ("Request" .. TOKEN .. "ObjectCleanup")
Members.makeFallback = Members.makeFallback or ("MakeFallback" .. TOKEN)
Members.makeFromWave = Members.makeFromWave or ("Make" .. TOKEN .. "FromWave")
Members.tryMattressAt = Members.tryMattressAt or ("TryMattressAt" .. TOKEN)
Members.getClosestEnemyLocation = Members.getClosestEnemyLocation or ("GetClosestEnemy" .. TOKEN .. "Location")
Members.buildBridgeNearResult = Members.buildBridgeNearResult or ("BuildBridgeNear" .. TOKEN .. "Result")
Members.setFor = Members.setFor or ("SetFor" .. TOKEN)
Members.setAnchorFrom = Members.setAnchorFrom or ("SetAnchorFrom" .. TOKEN)
Members.applyTasks = Members.applyTasks or ("Apply" .. TOKEN .. "Tasks")
Members.onPlayerHit = Members.onPlayerHit or ("OnPlayerHit" .. TOKEN)
Members.getNearbyInto = Members.getNearbyInto or ("GetNearby" .. PLURAL .. "Into")
Members.getNearby = Members.getNearby or ("GetNearby" .. PLURAL)
Members.getClosestLocation = Members.getClosestLocation or ("GetClosest" .. TOKEN .. "Location")
Members.getClosestLocationFast = Members.getClosestLocationFast or ("GetClosest" .. TOKEN .. "LocationFast")
Members.countNearby = Members.countNearby or ("CountNearby" .. PLURAL)
Members.rand = Members.rand or (TOKEN .. "Rand")
NPCLegacyContractBridge.Members = Members

function NPCLegacyContractBridge.Key(name)
    return Keys and Keys[name]
end

function NPCLegacyContractBridge.Command(name)
    return Commands and Commands[name]
end

function NPCLegacyContractBridge.FunctionName(name)
    return NPCLegacyContractBridge.Functions and NPCLegacyContractBridge.Functions[name]
end

function NPCLegacyContractBridge.Item(name)
    return NPCLegacyContractBridge.Items and NPCLegacyContractBridge.Items[name]
end

function NPCLegacyContractBridge.Outfit(name)
    return NPCLegacyContractBridge.Outfits and NPCLegacyContractBridge.Outfits[name]
end

function NPCLegacyContractBridge.WorldRuleField(name)
    return NPCLegacyContractBridge.WorldRuleFields and NPCLegacyContractBridge.WorldRuleFields[name]
end

function NPCLegacyContractBridge.Member(name)
    return NPCLegacyContractBridge.Members and NPCLegacyContractBridge.Members[name]
end

function NPCLegacyContractBridge.Program(name)
    return Programs and Programs[name]
end

function NPCLegacyContractBridge.Module(name)
    return NPCLegacyContractBridge.Modules and NPCLegacyContractBridge.Modules[name]
end

function NPCLegacyContractBridge.IsModule(module, neutralModule, legacyName)
    if module == neutralModule then return true end
    local legacyModule = NPCLegacyContractBridge.Module(legacyName)
    return legacyModule ~= nil and module == legacyModule
end
