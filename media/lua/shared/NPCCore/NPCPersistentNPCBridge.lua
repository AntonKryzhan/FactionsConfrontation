local legacyPersistentNPC = NPCPersistentNPCBridge
NPCPersistentNPCBridge = NPCPersistentNPCBridge or legacyPersistentNPC or {}

NPCPersistentNPCBridge.Version = 4
NPCPersistentNPCBridge.Enabled = NPCPersistentNPCBridge.Enabled ~= false
NPCPersistentNPCBridge.MaxInventoryLite = NPCPersistentNPCBridge.MaxInventoryLite or 36
NPCPersistentNPCBridge.MaxProfiles = NPCPersistentNPCBridge.MaxProfiles or 500
NPCPersistentNPCBridge.KeepDeadHours = NPCPersistentNPCBridge.KeepDeadHours or (24 * 7)

local function bpnpc_now()
    if NPCIdentityBridge and NPCIdentityBridge.GetWorldAgeHours then
        return NPCIdentityBridge.GetWorldAgeHours()
    end
    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then return gt:getWorldAgeHours() end
    end
    return 0
end

local function bpnpc_enabled()
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        return NPCLegacySettingsBridge.GetBool("Persistent_Enabled", NPCPersistentNPCBridge.Enabled ~= false)
    end
    return NPCPersistentNPCBridge.Enabled ~= false
end

local function bpnpc_copy(value, depth)
    depth = depth or 0
    if depth > 8 then return nil end
    if type(value) ~= "table" then return value end
    local ret = {}
    for k, v in pairs(value) do
        local tk, tv = type(k), type(v)
        if (tk == "string" or tk == "number" or tk == "boolean") and tv ~= "function" and tv ~= "userdata" and tv ~= "thread" then
            if tv == "table" then
                ret[k] = bpnpc_copy(v, depth + 1)
            else
                ret[k] = v
            end
        end
    end
    return ret
end

local function bpnpc_first(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if v ~= nil then return v end
    end
    return nil
end

local function bpnpc_uidOf(value)
    if type(value) == "table" then
        return value.uid or value.persistentId or value.id
    end
    return value
end

local function bpnpc_tableCount(tbl)
    local n = 0
    if type(tbl) == "table" then
        for _, _ in pairs(tbl) do n = n + 1 end
    end
    return n
end

local function bpnpc_normalizeLocation(x, y, z, fallback)
    x = tonumber(x)
    y = tonumber(y)
    z = tonumber(z) or 0
    if x and y then return {x = x, y = y, z = z} end
    if type(fallback) == "table" and tonumber(fallback.x) and tonumber(fallback.y) then
        return {x = tonumber(fallback.x), y = tonumber(fallback.y), z = tonumber(fallback.z) or 0}
    end
    return nil
end

local function bpnpc_applyFields(dst, src, fields)
    if type(dst) ~= "table" or type(src) ~= "table" then return dst end
    for _, key in ipairs(fields) do
        if src[key] ~= nil then
            if type(src[key]) == "table" then
                dst[key] = bpnpc_copy(src[key])
            else
                dst[key] = src[key]
            end
        end
    end
    return dst
end

local BPNPC_MEMBER_FIELDS = {
    "female", "femaleChance", "voice", "outfit", "appearanceSeed", "faceProfile", "skinTexture", "skinColor", "hairStyle", "hairColor", "beardStyle", "beardColor",
    "clan", "faction", "hostile", "relationship", "relationshipToPlayer", "master", "eatBody", "accuracyBoost",
    "professionArchetype", "professionCategory", "appearanceStyle", "cinematicAppearance", "behaviorTags",
    "health", "maxHealth", "endurance", "infection", "weapons", "inventory", "inventoryLite", "loot", "key",
    "baseGear", "baseGearWear", "baseGearWeaponKits", "baseGearWeaponParts", "baseGearMagazines", "baseGearBaseId",
    "currentWeapon", "ammo", "role", "tacticalRole", "homeBaseId", "homeBase", "homeBaseZoneId", "homeBaseZoneType",
    "homeBaseZone", "baseZoneId", "baseZoneType", "baseDuty", "baseDutyState", "baseDutyReason", "baseDutyGroupId", "baseDutyOwner",
    "guardPoint", "patrolPoint", "medicalPoint", "restPoint", "foodPoint", "ammoPoint", "storagePoint", "returnPoint", "lastTask", "order", "fireMode",
    "program", "programName", "programStage", "state", "fsm", "sim", "watchdog", "debug", "dna",
    "mercenary", "mercenaryElite", "mercenaryHired", "mercenaryHiredBy", "mercenaryHiredByName", "mercenarySquadLeader", "mercenarySquadLeaderName",
    "spy", "spyForPlayerId", "spyForPlayerName", "spyOriginalSide", "spyBribedAt", "spyState", "spyDefected", "spyDefectedAt", "spySabotage", "spyAlliedGroup", "spyPaymentKind", "spyDefectionReason",
    "needs", "stock", "skills", "xp", "morale", "fear", "aggression", "discipline", "lastKnownEnemyPosition",
    "roadPatrol", "roadBias", "preferRoads", "patrolColor", "encounterId", "inBattle", "virtualBattle", "battleId", "enemyGroupId", "battleEnemyGroupId"
}

local function bpnpc_memberKey(member)
    if type(member) ~= "table" then return nil end
    local uid = member.uid or member.persistentId
    if uid ~= nil then return tostring(uid) end
    if member.id ~= nil then return "id:" .. tostring(member.id) end
    if member.runtimeId ~= nil then return "runtime:" .. tostring(member.runtimeId) end
    return nil
end

local function bpnpc_applyGroupMercenaryState(member, group)
    if type(member) ~= "table" or type(group) ~= "table" then return member end
    if not (group.mercenaryHired == true or group.isPlayerGuard == true or group.followPlayer ~= nil) then return member end

    local order = type(group.order) == "table" and group.order or nil
    local owner = group.mercenaryHiredBy or group.followPlayer or group.master or (order and order.master)
    member.master = owner or member.master
    member.mercenary = true
    member.mercenaryHired = true
    member.mercenaryHiredBy = owner or member.mercenaryHiredBy
    member.mercenaryHiredByName = group.mercenaryHiredByName or member.mercenaryHiredByName
    member.isPlayerGuard = true
    member.followPlayer = owner or member.followPlayer
    member.guardPlayer = nil
    member.hostile = false
    member.friendly = true
    member.relationshipToPlayer = member.relationshipToPlayer or "hired_bodyguard"
    member.factionSide = "blue"
    member.faction = "blue"
    member.side = "blue"
    member.patrolColor = "blue"
    member.factionState = member.factionState or "hired_blue_bodyguard"
    member.program = bpnpc_copy(group.program or member.program or {name="Companion", stage="Prepare"})
    member.order = bpnpc_copy(order or member.order or {name="Follow", master=owner, fireMode="Defensive", formation="close", followDistance=3.0})
    if member.order then
        member.order.name = member.order.name or "Follow"
        member.order.master = member.order.master or owner
        member.order.fireMode = member.order.fireMode or "Defensive"
        member.order.formation = member.order.formation or "close"
        member.order.followDistance = member.order.followDistance or 3.0
    end
    member.fireMode = member.order and member.order.fireMode or member.fireMode or "Defensive"
    member.rbFireMode = member.fireMode or member.rbFireMode
    return member
end

local function bpnpc_compactGroupMembers(group)
    if type(group) ~= "table" or type(group.members) ~= "table" then return false end

    local compact = {}
    local byKey = {}
    local changed = false

    for _, member in ipairs(group.members) do
        if type(member) == "table" then
            local key = bpnpc_memberKey(member)
            local existing = key and byKey[key] or nil
            if existing then
                bpnpc_applyFields(existing, member, BPNPC_MEMBER_FIELDS)
                if member.uid ~= nil then existing.uid = member.uid end
                if member.persistentId ~= nil then existing.persistentId = member.persistentId end
                if member.memberIndex ~= nil and existing.memberIndex == nil then existing.memberIndex = member.memberIndex end
                changed = true
            else
                compact[#compact + 1] = member
                if key then byKey[key] = member end
            end
        else
            changed = true
        end
    end

    if changed or #compact ~= #group.members then
        group.members = compact
        if #compact > 0 then group.count = #compact end
        return true
    end

    return false
end

local function bpnpc_getProfileRaw(gmd, uid)
    if not (gmd and uid) then return nil end
    uid = tostring(uid)
    return (gmd.PersistentNPCs and gmd.PersistentNPCs[uid]) or (gmd.Registry and gmd.Registry[uid])
end

local function bpnpc_cloneProfileForMember(profile)
    if type(profile) ~= "table" then return nil end
    if profile.dead then return nil end
    local member = {}
    bpnpc_applyFields(member, profile, BPNPC_MEMBER_FIELDS)
    member.uid = profile.uid
    member.persistentId = profile.persistentId or profile.uid
    member.fullname = profile.name or profile.fullname or member.fullname
    member.name = profile.name or profile.fullname or member.name
    member.memberIndex = profile.memberIndex
    member.groupId = profile.groupId or profile.worldGroupId
    member.worldGroupId = profile.worldGroupId or profile.groupId
    member.born = profile.born or profile.created
    member.bornCoords = bpnpc_copy(profile.bornCoords or profile.location)
    return member
end

function NPCPersistentNPCBridge.EnsureData(gmd)
    if not gmd then return nil end
    if not gmd.Registry then gmd.Registry = {} end
    if not gmd.PersistentNPCs then gmd.PersistentNPCs = {} end
    if not gmd.PersistentGroups then gmd.PersistentGroups = {} end
    if not gmd.PersistentRuntimeToUID then gmd.PersistentRuntimeToUID = {} end
    if not gmd.PersistentUIDToRuntime then gmd.PersistentUIDToRuntime = {} end
    if not gmd.DeadRegistry then gmd.DeadRegistry = {} end
    if not gmd.NextPersistentId then gmd.NextPersistentId = 1 end

    local oldVersion = tonumber(gmd.PersistentNPCVersion) or 0
    if oldVersion < NPCPersistentNPCBridge.Version then
        for uid, record in pairs(gmd.Registry) do
            if type(record) == "table" and (record.uid or uid) and not gmd.PersistentNPCs[tostring(record.uid or uid)] then
                local copy = bpnpc_copy(record)
                copy.uid = tostring(copy.uid or uid)
                copy.persistentId = copy.persistentId or copy.uid
                copy.version = NPCPersistentNPCBridge.Version
                copy.updated = copy.updated or bpnpc_now()
                gmd.PersistentNPCs[copy.uid] = copy
            end
        end
        gmd.PersistentNPCVersion = NPCPersistentNPCBridge.Version
    end

    local now = bpnpc_now()
    if not gmd.PersistentLastPrune or now - (tonumber(gmd.PersistentLastPrune) or 0) > 1.0 then
        gmd.PersistentLastPrune = now
        if NPCPersistentNPCBridge.PruneProfiles then NPCPersistentNPCBridge.PruneProfiles(gmd) end
    end

    return gmd
end

function NPCPersistentNPCBridge.GetProfile(gmd, uid)
    NPCPersistentNPCBridge.EnsureData(gmd)
    return bpnpc_getProfileRaw(gmd, uid)
end
function NPCPersistentNPCBridge.ClearRuntimeLinks(gmd)
    if not gmd then return false end
    NPCPersistentNPCBridge.EnsureData(gmd)

    gmd.PersistentRuntimeToUID = {}
    gmd.PersistentUIDToRuntime = {}
    if gmd.RuntimeToUID then gmd.RuntimeToUID = {} end
    if gmd.UIDToRuntime then gmd.UIDToRuntime = {} end

    local changed = false
    local now = bpnpc_now()
    for uid, profile in pairs(gmd.PersistentNPCs or {}) do
        if type(profile) == "table" and not profile.dead then
            if profile.runtimeId ~= nil or profile.id ~= nil or profile.virtual ~= true then
                profile.runtimeId = nil
                profile.id = nil
                profile.virtual = true
                profile.updated = now
                profile.version = NPCPersistentNPCBridge.Version
                if gmd.Registry then gmd.Registry[tostring(uid)] = bpnpc_copy(profile) end
                changed = true
            end
        end
    end

    return changed
end


function NPCPersistentNPCBridge.BuildInventoryLite(zombie, brain)
    if brain and type(brain.inventoryLite) == "table" and bpnpc_tableCount(brain.inventoryLite) > 0 then
        return bpnpc_copy(brain.inventoryLite)
    end

    local lite = {}
    local counts = {}
    if zombie and zombie.getInventory then
        local ok, items = pcall(function()
            local inv = zombie:getInventory()
            return inv and inv:getItems() or nil
        end)
        if ok and items then
            local size = 0
            local okSize, itemCount = pcall(function() return items:size() end)
            if okSize and itemCount then size = tonumber(itemCount) or 0 end
            if size > 0 then
                for i = 0, size - 1 do
                    local item = nil
                    local okItem, gotItem = pcall(function() return items:get(i) end)
                    if okItem then item = gotItem end
                    if item then
                        local ft = nil
                        local cond = nil
                        local maxCond = nil
                        pcall(function() ft = item:getFullType() end)
                        pcall(function() cond = item:getCondition() end)
                        pcall(function() maxCond = item:getConditionMax() end)
                        if ft then
                            if not counts[ft] then counts[ft] = {fullType = ft, count = 0} end
                            counts[ft].count = counts[ft].count + 1
                            if cond ~= nil then counts[ft].condition = cond end
                            if maxCond ~= nil then counts[ft].maxCondition = maxCond end
                        end
                    end
                end
            end
        end
    end

    local n = 0
    for _, item in pairs(counts) do
        n = n + 1
        lite[#lite + 1] = item
        if n >= (tonumber(NPCPersistentNPCBridge.MaxInventoryLite) or 36) then break end
    end

    if #lite > 0 then return lite end
    return bpnpc_copy(brain and brain.inventory or {})
end

function NPCPersistentNPCBridge.BuildAmmoLite(zombie, brain)
    if brain and type(brain.ammo) == "table" and bpnpc_tableCount(brain.ammo) > 0 then return bpnpc_copy(brain.ammo) end
    local ammo = {}
    local invLite = NPCPersistentNPCBridge.BuildInventoryLite(zombie, brain)
    if type(invLite) == "table" then
        for _, item in ipairs(invLite) do
            local ft = item.fullType or item.type or item[1]
            if ft then
                local s = tostring(ft):lower()
                if string.find(s, "ammo") or string.find(s, "bullet") or string.find(s, "shell") or string.find(s, "magazine") or string.find(s, "round") then
                    ammo[tostring(ft)] = tonumber(item.count or item[2]) or 1
                end
            end
        end
    end
    return ammo
end

function NPCPersistentNPCBridge.BuildCurrentWeapon(zombie, brain)
    local src = brain and brain.currentWeapon or nil
    if type(src) == "table" and src.fullType then return bpnpc_copy(src) end
    local item = nil
    if zombie and zombie.getPrimaryHandItem then
        pcall(function() item = zombie:getPrimaryHandItem() end)
    end
    if not item then return bpnpc_copy(src) end
    local out = {}
    pcall(function() out.fullType = item:getFullType() end)
    pcall(function() out.condition = item:getCondition() end)
    pcall(function() out.maxCondition = item:getConditionMax() end)
    pcall(function() out.currentAmmo = item:getCurrentAmmoCount() end)
    pcall(function() out.maxAmmo = item:getMaxAmmo() end)
    pcall(function() out.containsClip = item:isContainsClip() end)
    pcall(function() out.haveChamber = item:isRoundChambered() end)
    if not out.fullType then return nil end
    return out
end

local function bpnpc_readVisual(zombie, brain)
    local out = {}
    if brain then
        out.female = brain.female
        out.voice = brain.voice
        out.outfit = brain.outfit
        out.appearanceSeed = brain.appearanceSeed
        out.faceProfile = brain.faceProfile
        out.skinTexture = brain.skinTexture
        out.skinColor = bpnpc_copy(brain.skinColor)
        out.hairStyle = brain.hairStyle
        out.hairColor = bpnpc_copy(brain.hairColor)
        out.beardStyle = brain.beardStyle
        out.beardColor = bpnpc_copy(brain.beardColor)
    end
    if zombie then
        pcall(function() out.female = zombie:isFemale() end)
        local visuals = nil
        pcall(function() visuals = zombie:getHumanVisual() end)
        if visuals then
            pcall(function() out.hairStyle = out.hairStyle or visuals:getHairModel() end)
            pcall(function() out.beardStyle = out.beardStyle or visuals:getBeardModel() end)
            local hairColor = nil
            local beardColor = nil
            local skinColor = nil
            pcall(function() hairColor = visuals:getHairColor() end)
            pcall(function() beardColor = visuals:getBeardColor() end)
            pcall(function() skinColor = visuals:getSkinColor() end)
            if skinColor and not out.skinColor then
                out.skinColor = {r = skinColor:getRedFloat(), g = skinColor:getGreenFloat(), b = skinColor:getBlueFloat()}
            end
            if hairColor and not out.hairColor then
                out.hairColor = {r = hairColor:getRedFloat(), g = hairColor:getGreenFloat(), b = hairColor:getBlueFloat()}
            end
            if beardColor and not out.beardColor then
                out.beardColor = {r = beardColor:getRedFloat(), g = beardColor:getGreenFloat(), b = beardColor:getBlueFloat()}
            end
        end
    end
    return out
end

local function bpnpc_enrich(profile, brain, zombie)
    if not profile then return profile end
    if brain then
        profile.name = bpnpc_first(brain.fullname, brain.name, profile.name, profile.fullname)
        profile.fullname = profile.name or profile.fullname
        profile.faction = bpnpc_first(brain.clan, brain.faction, profile.faction)
        profile.clan = bpnpc_first(brain.clan, profile.clan, profile.faction)
        profile.hostile = bpnpc_first(brain.hostile, profile.hostile)
        profile.relationshipToPlayer = bpnpc_first(brain.relationshipToPlayer, brain.relationship, profile.relationshipToPlayer, profile.hostile and "hostile" or "friendly")
        profile.master = bpnpc_first(brain.master, profile.master)
        profile.health = bpnpc_first(brain.health, profile.health)
        profile.maxHealth = bpnpc_first(brain.maxHealth, profile.maxHealth, profile.health)
        profile.endurance = bpnpc_first(brain.endurance, profile.endurance)
        profile.infection = bpnpc_first(brain.infection, profile.infection)
        profile.weapons = bpnpc_copy(bpnpc_first(brain.weapons, profile.weapons))
        profile.inventory = bpnpc_copy(bpnpc_first(brain.inventory, profile.inventory))
        profile.inventoryLite = bpnpc_copy(bpnpc_first(brain.inventoryLite, profile.inventoryLite))
        profile.loot = bpnpc_copy(bpnpc_first(brain.loot, profile.loot))
        profile.key = bpnpc_copy(bpnpc_first(brain.key, profile.key))
        profile.currentWeapon = bpnpc_copy(bpnpc_first(brain.currentWeapon, profile.currentWeapon))
        profile.ammo = bpnpc_copy(bpnpc_first(brain.ammo, profile.ammo))
        profile.role = bpnpc_first(brain.role, brain.job, profile.role)
        profile.tacticalRole = bpnpc_first(brain.tacticalRole, brain.radioRole, profile.tacticalRole)
        profile.homeBaseId = bpnpc_first(brain.homeBaseId, brain.baseId, profile.homeBaseId)
        profile.homeBase = bpnpc_copy(bpnpc_first(brain.homeBase, brain.base, profile.homeBase))
        profile.homeBaseZoneId = bpnpc_first(brain.homeBaseZoneId, profile.homeBaseZoneId)
        profile.homeBaseZoneType = bpnpc_first(brain.homeBaseZoneType, profile.homeBaseZoneType)
        profile.homeBaseZone = bpnpc_copy(bpnpc_first(brain.homeBaseZone, profile.homeBaseZone))
        profile.baseZoneId = bpnpc_first(brain.baseZoneId, profile.baseZoneId)
        profile.baseZoneType = bpnpc_first(brain.baseZoneType, profile.baseZoneType)
        profile.baseDuty = bpnpc_first(brain.baseDuty, profile.baseDuty)
        profile.baseDutyState = bpnpc_first(brain.baseDutyState, profile.baseDutyState)
        profile.baseDutyReason = bpnpc_first(brain.baseDutyReason, profile.baseDutyReason)
        profile.baseDutyGroupId = bpnpc_first(brain.baseDutyGroupId, profile.baseDutyGroupId)
        profile.baseDutyOwner = bpnpc_first(brain.baseDutyOwner, profile.baseDutyOwner)
        profile.guardPoint = bpnpc_copy(bpnpc_first(brain.guardPoint, profile.guardPoint))
        profile.patrolPoint = bpnpc_copy(bpnpc_first(brain.patrolPoint, profile.patrolPoint))
        profile.medicalPoint = bpnpc_copy(bpnpc_first(brain.medicalPoint, profile.medicalPoint))
        profile.restPoint = bpnpc_copy(bpnpc_first(brain.restPoint, profile.restPoint))
        profile.foodPoint = bpnpc_copy(bpnpc_first(brain.foodPoint, profile.foodPoint))
        profile.ammoPoint = bpnpc_copy(bpnpc_first(brain.ammoPoint, profile.ammoPoint))
        profile.storagePoint = bpnpc_copy(bpnpc_first(brain.storagePoint, profile.storagePoint))
        profile.returnPoint = bpnpc_copy(bpnpc_first(brain.returnPoint, profile.returnPoint))
        profile.lastKnownEnemyPosition = bpnpc_copy(bpnpc_first(brain.lastKnownEnemyPosition, brain.lastKnownThreatPosition, brain.ai and brain.ai.lastKnownEnemyPosition, profile.lastKnownEnemyPosition))
        profile.needs = bpnpc_copy(bpnpc_first(brain.needs, brain.ai and brain.ai.needs, profile.needs))
        profile.stock = bpnpc_copy(bpnpc_first(brain.stock, brain.ai and brain.ai.stock, profile.stock))
        profile.skills = bpnpc_copy(bpnpc_first(brain.skills, brain.ai and brain.ai.skills, profile.skills))
        profile.xp = bpnpc_copy(bpnpc_first(brain.xp, brain.ai and brain.ai.xp, profile.xp))
        profile.morale = bpnpc_first(brain.morale, brain.ai and brain.ai.morale, profile.morale)
        profile.fear = bpnpc_first(brain.fear, brain.ai and brain.ai.fear, profile.fear)
        profile.aggression = bpnpc_first(brain.aggression, brain.ai and brain.ai.aggression, profile.aggression)
        profile.discipline = bpnpc_first(brain.discipline, brain.ai and brain.ai.discipline, profile.discipline)
        profile.order = bpnpc_copy(bpnpc_first(brain.order, profile.order))
        profile.fireMode = bpnpc_first((brain.order and brain.order.fireMode), brain.fireMode, profile.fireMode)
        profile.program = bpnpc_copy(bpnpc_first(brain.program, profile.program))
        profile.sim = bpnpc_copy(bpnpc_first(brain.sim, profile.sim))
        profile.fsm = bpnpc_copy(bpnpc_first(brain.fsm, profile.fsm))
        profile.watchdog = bpnpc_copy(bpnpc_first(brain.watchdog, profile.watchdog))
        profile.debug = bpnpc_copy(bpnpc_first(brain.debug, profile.debug))
        profile.dna = bpnpc_copy(bpnpc_first(brain.dna, profile.dna))
        profile.state = bpnpc_first(brain.state, brain.sim and brain.sim.state, profile.state)
        profile.lastTask = bpnpc_copy(bpnpc_first(brain.lastTask, profile.lastTask))
        profile.roadPatrol = bpnpc_first(brain.roadPatrol, profile.roadPatrol)
        profile.roadBias = bpnpc_first(brain.roadBias, profile.roadBias)
        profile.preferRoads = bpnpc_first(brain.preferRoads, profile.preferRoads)
        profile.patrolColor = bpnpc_first(brain.patrolColor, profile.patrolColor)
        profile.encounterId = bpnpc_first(brain.encounterId, profile.encounterId)
        profile.inBattle = bpnpc_first(brain.inBattle, brain.virtualBattle, profile.inBattle)
        profile.virtualBattle = bpnpc_first(brain.virtualBattle, profile.virtualBattle)
        profile.battleId = bpnpc_first(brain.battleId, profile.battleId)
        profile.enemyGroupId = bpnpc_first(brain.battleEnemyGroupId, brain.enemyGroupId, profile.enemyGroupId)
        profile.battleEnemyGroupId = bpnpc_first(brain.battleEnemyGroupId, brain.enemyGroupId, profile.battleEnemyGroupId)
        profile.permanent = bpnpc_first(brain.permanent, profile.permanent)
        profile.eatBody = bpnpc_first(brain.eatBody, profile.eatBody)
        profile.accuracyBoost = bpnpc_first(brain.accuracyBoost, profile.accuracyBoost)
    end

    local visual = bpnpc_readVisual(zombie, brain)
    bpnpc_applyFields(profile, visual, {"female", "voice", "outfit", "appearanceSeed", "faceProfile", "skinTexture", "skinColor", "hairStyle", "hairColor", "beardStyle", "beardColor"})

    return profile
end

local function bpnpc_commitProfile(gmd, profile)
    if not (gmd and profile and profile.uid) then return nil end
    NPCPersistentNPCBridge.EnsureData(gmd)
    local uid = tostring(profile.uid)
    profile.uid = uid
    profile.persistentId = profile.persistentId or uid
    profile.updated = profile.updated or bpnpc_now()
    profile.version = NPCPersistentNPCBridge.Version
    gmd.PersistentNPCs[uid] = profile
    gmd.Registry[uid] = bpnpc_copy(profile)
    if profile.runtimeId then
        local rid = tostring(profile.runtimeId)
        gmd.PersistentRuntimeToUID[rid] = uid
        gmd.PersistentUIDToRuntime[uid] = rid
        if gmd.RuntimeToUID then gmd.RuntimeToUID[rid] = uid end
        if gmd.UIDToRuntime then gmd.UIDToRuntime[uid] = rid end
    end
    return profile
end

function NPCPersistentNPCBridge.TouchFromSnapshot(gmd, snapshot, brain, zombie)
    if not (gmd and snapshot and snapshot.uid) then return nil end
    if not bpnpc_enabled() then return nil end
    NPCPersistentNPCBridge.EnsureData(gmd)

    local uid = tostring(snapshot.uid)
    local old = bpnpc_getProfileRaw(gmd, uid) or {}
    local profile = bpnpc_copy(old) or {}
    bpnpc_applyFields(profile, snapshot, BPNPC_MEMBER_FIELDS)

    profile.uid = uid
    profile.persistentId = bpnpc_first(snapshot.persistentId, profile.persistentId, uid)
    profile.runtimeId = bpnpc_first(snapshot.runtimeId, snapshot.id, profile.runtimeId)
    profile.id = bpnpc_first(snapshot.id, profile.id)
    profile.name = bpnpc_first(snapshot.fullname, snapshot.name, profile.name, profile.fullname)
    profile.fullname = profile.name or profile.fullname
    profile.faction = bpnpc_first(snapshot.clan, snapshot.faction, profile.faction)
    profile.clan = bpnpc_first(snapshot.clan, profile.clan, profile.faction)
    profile.relationshipToPlayer = bpnpc_first(snapshot.relationshipToPlayer, snapshot.relationship, profile.relationshipToPlayer, snapshot.hostile and "hostile" or nil)
    profile.location = bpnpc_normalizeLocation(snapshot.x, snapshot.y, snapshot.z, profile.location)
    if profile.location then
        profile.x = profile.location.x
        profile.y = profile.location.y
        profile.z = profile.location.z
    end
    profile.bornCoords = bpnpc_copy(bpnpc_first(snapshot.bornCoords, profile.bornCoords, profile.location))
    profile.groupId = bpnpc_first(snapshot.groupId, snapshot.worldGroupId, profile.groupId)
    profile.worldGroupId = bpnpc_first(snapshot.worldGroupId, snapshot.groupId, profile.worldGroupId)
    profile.memberIndex = bpnpc_first(snapshot.memberIndex, profile.memberIndex)
    profile.created = bpnpc_first(profile.created, snapshot.born, snapshot.created, bpnpc_now())
    profile.updated = bpnpc_now()
    profile.virtual = snapshot.virtual == true
    profile.permanent = bpnpc_first(snapshot.permanent, profile.permanent)

    profile = bpnpc_enrich(profile, brain, zombie)
    if zombie then
        profile.currentWeapon = NPCPersistentNPCBridge.BuildCurrentWeapon(zombie, brain) or profile.currentWeapon
        profile.ammo = NPCPersistentNPCBridge.BuildAmmoLite(zombie, brain)
        profile.inventoryLite = NPCPersistentNPCBridge.BuildInventoryLite(zombie, brain)
    end

    if old.dead and not snapshot.dead then
        profile.dead = false
        profile.revivedAt = profile.updated
    elseif snapshot.dead == true then
        profile.dead = true
        profile.deathAt = old.deathAt or profile.updated
    else
        profile.dead = false
    end

    return bpnpc_commitProfile(gmd, profile)
end

function NPCPersistentNPCBridge.TouchFromRuntime(gmd, brain, runtimeId, zombie)
    if not (gmd and brain) then return nil end
    if NPCIdentityBridge and NPCIdentityBridge.BuildSnapshot then
        local snapshot = NPCIdentityBridge.BuildSnapshot(gmd, brain, runtimeId or brain.id)
        return NPCPersistentNPCBridge.TouchFromSnapshot(gmd, snapshot, brain, zombie)
    end

    local uid = brain.uid or brain.persistentId
    if not uid and NPCIdentityBridge and NPCIdentityBridge.NewUID then
        uid = NPCIdentityBridge.NewUID(gmd)
        brain.uid = uid
        brain.persistentId = uid
    end
    if not uid then return nil end
    return NPCPersistentNPCBridge.TouchFromSnapshot(gmd, {uid = uid, persistentId = uid, id = runtimeId or brain.id, runtimeId = runtimeId or brain.id}, brain, zombie)
end

function NPCPersistentNPCBridge.TouchVirtualMember(gmd, member, group, index)
    if not (gmd and member and group) then return nil end
    if not bpnpc_enabled() then return nil end
    NPCPersistentNPCBridge.EnsureData(gmd)
    local uid = member.uid or member.persistentId
    if not uid and NPCIdentityBridge and NPCIdentityBridge.NewUID then
        uid = NPCIdentityBridge.NewUID(gmd)
        member.uid = uid
        member.persistentId = uid
    end
    if not uid then return nil end

    local old = bpnpc_getProfileRaw(gmd, uid) or {}
    local profile = bpnpc_copy(old) or {}
    bpnpc_applyGroupMercenaryState(member, group)
    bpnpc_applyFields(profile, member, BPNPC_MEMBER_FIELDS)

    profile.uid = tostring(uid)
    profile.persistentId = member.persistentId or profile.persistentId or uid
    profile.name = bpnpc_first(member.fullname, member.name, profile.name, profile.fullname)
    profile.fullname = profile.name or profile.fullname
    profile.faction = bpnpc_first(member.clan, member.faction, group.clanId, profile.faction)
    profile.clan = bpnpc_first(member.clan, group.clanId, profile.clan, profile.faction)
    profile.hostile = bpnpc_first(group.hostile, member.hostile, profile.hostile)
    profile.relationshipToPlayer = bpnpc_first(member.relationshipToPlayer, member.relationship, profile.relationshipToPlayer, profile.hostile and "hostile" or "friendly")
    profile.health = bpnpc_first(member.health, profile.health)
    profile.maxHealth = bpnpc_first(member.maxHealth, member.health, profile.maxHealth, profile.health)
    profile.location = bpnpc_normalizeLocation(group.x, group.y, group.z, profile.location)
    if profile.location then
        profile.x = profile.location.x
        profile.y = profile.location.y
        profile.z = profile.location.z
    end
    profile.groupId = group.id
    profile.worldGroupId = group.id
    profile.memberIndex = index or member.memberIndex or profile.memberIndex
    profile.state = bpnpc_first(group.state, member.state, profile.state, "virtual")
    profile.created = profile.created or member.born or group.createdAt or bpnpc_now()
    profile.updated = bpnpc_now()
    profile.dead = old.dead == true or member.dead == true
    profile.virtual = true
    profile.version = NPCPersistentNPCBridge.Version

    member.uid = profile.uid
    member.persistentId = profile.persistentId
    member.memberIndex = profile.memberIndex

    return bpnpc_commitProfile(gmd, profile)
end

function NPCPersistentNPCBridge.RestoreGroupMembers(gmd, group)
    if not (gmd and group and group.id) then return false end
    NPCPersistentNPCBridge.EnsureData(gmd)
    local groupId = tostring(group.id)
    local record = gmd.PersistentGroups and gmd.PersistentGroups[groupId]
    local changed = false

    if type(group.members) ~= "table" then
        group.members = {}
        changed = true
    end
    changed = bpnpc_compactGroupMembers(group) or changed

    local byUid = {}
    for _, member in ipairs(group.members) do
        if type(member) == "table" then
            local uid = member.uid or member.persistentId
            if uid then byUid[tostring(uid)] = member end
        end
    end

    if record and type(record.memberUids) == "table" then
        local restoredSeen = {}
        for i, uid in ipairs(record.memberUids) do
            local suid = uid ~= nil and tostring(uid) or nil
            if suid and not restoredSeen[suid] then
                restoredSeen[suid] = true
                local profile = bpnpc_getProfileRaw(gmd, uid)
                if profile and not profile.dead then
                    local existing = byUid[suid]
                    if existing then
                        NPCPersistentNPCBridge.ApplyProfileToMember(gmd, existing)
                        bpnpc_applyGroupMercenaryState(existing, group)
                        existing.memberIndex = existing.memberIndex or i
                    else
                        local member = bpnpc_cloneProfileForMember(profile)
                        if member then
                            bpnpc_applyGroupMercenaryState(member, group)
                            member.memberIndex = member.memberIndex or i
                            table.insert(group.members, member)
                            byUid[suid] = member
                            changed = true
                        end
                    end
                end
            elseif suid then
                changed = true
            end
        end
    end

    for i, member in ipairs(group.members) do
        if type(member) == "table" then
            if not member.memberIndex then member.memberIndex = i end
            if not member.worldGroupId then member.worldGroupId = group.id end
            if not member.groupId then member.groupId = group.id end
            if member.uid or member.persistentId then
                NPCPersistentNPCBridge.ApplyProfileToMember(gmd, member)
                bpnpc_applyGroupMercenaryState(member, group)
            else
                bpnpc_applyGroupMercenaryState(member, group)
                NPCPersistentNPCBridge.TouchVirtualMember(gmd, member, group, i)
                changed = true
            end
        end
    end
    changed = bpnpc_compactGroupMembers(group) or changed

    if record then
        group.count = #group.members > 0 and #group.members or group.count or record.count
        group.x = group.x or record.x
        group.y = group.y or record.y
        group.z = group.z or record.z or 0
        group.homeBaseId = group.homeBaseId or record.homeBaseId
        group.program = group.program or bpnpc_copy(record.program)
        group.roadPatrol = group.roadPatrol or record.roadPatrol
        group.patrolColor = group.patrolColor or record.patrolColor
        group.inBattle = group.inBattle or record.inBattle
        group.enemyGroupId = group.enemyGroupId or record.enemyGroupId
    end

    return changed or #group.members > 0
end

function NPCPersistentNPCBridge.RegisterGroup(gmd, group)
    if not (gmd and group and group.id) then return nil end
    if not bpnpc_enabled() then return nil end
    NPCPersistentNPCBridge.EnsureData(gmd)
    NPCPersistentNPCBridge.RestoreGroupMembers(gmd, group)
    bpnpc_compactGroupMembers(group)

    local members = {}
    local memberSeen = {}
    if type(group.members) == "table" then
        for i, member in ipairs(group.members) do
            bpnpc_applyGroupMercenaryState(member, group)
            local profile = NPCPersistentNPCBridge.TouchVirtualMember(gmd, member, group, i)
            local uid = profile and profile.uid and tostring(profile.uid) or nil
            if uid and not profile.dead and not memberSeen[uid] then
                memberSeen[uid] = true
                members[#members + 1] = profile.uid
            end
        end
    end

    local id = tostring(group.id)
    local record = gmd.PersistentGroups[id] or {}
    record.id = id
    record.memberUids = members
    record.count = #members > 0 and #members or group.count
    record.faction = group.clanId or group.faction or record.faction
    record.hostile = group.hostile
    record.x = group.x
    record.y = group.y
    record.z = group.z or 0
    record.location = {x = group.x, y = group.y, z = group.z or 0}
    record.state = group.state
    record.program = bpnpc_copy(group.program or record.program)
    record.homeBaseId = group.homeBaseId or group.baseId or record.homeBaseId
    record.roadPatrol = group.roadPatrol or false
    record.patrolColor = group.patrolColor
    record.inBattle = group.inBattle or false
    record.enemyGroupId = group.enemyGroupId
    record.updated = bpnpc_now()
    record.version = NPCPersistentNPCBridge.Version
    gmd.PersistentGroups[id] = record
    return record
end

function NPCPersistentNPCBridge.ApplyProfileToMember(gmd, member)
    if not (gmd and member) then return member end
    NPCPersistentNPCBridge.EnsureData(gmd)
    local uid = bpnpc_uidOf(member)
    local profile = uid and bpnpc_getProfileRaw(gmd, uid) or nil
    if not profile or profile.dead then return member end

    bpnpc_applyFields(member, profile, BPNPC_MEMBER_FIELDS)
    member.uid = profile.uid or member.uid
    member.persistentId = profile.persistentId or profile.uid or member.persistentId
    member.fullname = profile.name or profile.fullname or member.fullname
    member.name = profile.name or profile.fullname or member.name
    member.clan = profile.clan or profile.faction or member.clan
    member.health = profile.health or member.health
    member.maxHealth = profile.maxHealth or member.maxHealth or member.health
    member.groupId = profile.groupId or profile.worldGroupId or member.groupId
    member.worldGroupId = profile.worldGroupId or profile.groupId or member.worldGroupId
    member.homeBaseId = profile.homeBaseId or member.homeBaseId
    member.homeBase = bpnpc_copy(profile.homeBase or member.homeBase)
    member.lastTask = bpnpc_copy(profile.lastTask or member.lastTask)
    return member
end

function NPCPersistentNPCBridge.ApplyProfileToBrain(gmd, brain, zombie, member)
    if not (gmd and brain) then return brain end
    NPCPersistentNPCBridge.EnsureData(gmd)

    local uid = brain.uid or brain.persistentId or (member and (member.uid or member.persistentId))
    if not uid then return brain end
    local profile = bpnpc_getProfileRaw(gmd, uid)
    if not profile or profile.dead then return brain end

    bpnpc_applyFields(brain, profile, BPNPC_MEMBER_FIELDS)
    brain.uid = profile.uid or uid
    brain.persistentId = profile.persistentId or profile.uid or uid
    brain.fullname = profile.name or profile.fullname or brain.fullname
    brain.clan = profile.clan or profile.faction or brain.clan
    brain.relationshipToPlayer = profile.relationshipToPlayer or brain.relationshipToPlayer
    brain.relationship = profile.relationshipToPlayer or brain.relationship
    brain.health = profile.health or brain.health
    brain.maxHealth = profile.maxHealth or brain.maxHealth or brain.health
    brain.worldGroupId = profile.worldGroupId or profile.groupId or brain.worldGroupId
    brain.groupId = profile.groupId or profile.worldGroupId or brain.groupId

    if not brain.ai then brain.ai = {} end
    brain.ai.needs = bpnpc_copy(profile.needs or brain.ai.needs)
    brain.ai.stock = bpnpc_copy(profile.stock or brain.ai.stock)
    brain.ai.skills = bpnpc_copy(profile.skills or brain.ai.skills)
    brain.ai.xp = bpnpc_copy(profile.xp or brain.ai.xp)
    brain.ai.morale = profile.morale or brain.ai.morale
    brain.ai.fear = profile.fear or brain.ai.fear
    brain.ai.aggression = profile.aggression or brain.ai.aggression
    brain.ai.discipline = profile.discipline or brain.ai.discipline

    if profile.order then
        brain.order = bpnpc_copy(profile.order)
    elseif profile.fireMode then
        if not brain.order or type(brain.order) ~= "table" then brain.order = {name = "Auto"} end
        brain.order.fireMode = profile.fireMode
    end

    if zombie and zombie.setHealth and brain.health then
        pcall(function() zombie:setHealth(brain.health) end)
    end

    return brain
end

function NPCPersistentNPCBridge.BuildRuntimeUpdate(zombie, brain)
    if not brain then return nil end
    local x, y, z = nil, nil, nil
    if brain.debugCoords then
        x = brain.debugCoords.x
        y = brain.debugCoords.y
        z = brain.debugCoords.z
    elseif brain.x and brain.y then
        x = brain.x
        y = brain.y
        z = brain.z
    end

    return {
        fullname = brain.fullname,
        name = brain.fullname,
        female = brain.female,
        voice = brain.voice,
        outfit = brain.outfit,
        appearanceSeed = brain.appearanceSeed,
        faceProfile = brain.faceProfile,
        skinTexture = brain.skinTexture,
        skinColor = bpnpc_copy(brain.skinColor),
        hairStyle = brain.hairStyle,
        hairColor = bpnpc_copy(brain.hairColor),
        beardStyle = brain.beardStyle,
        beardColor = bpnpc_copy(brain.beardColor),
        clan = brain.clan,
        hostile = brain.hostile,
        master = brain.master,
        permanent = brain.permanent,
        maxHealth = brain.maxHealth,
        endurance = brain.endurance,
        infection = brain.infection,
        role = brain.role,
        tacticalRole = brain.tacticalRole,
        relationshipToPlayer = brain.relationshipToPlayer or brain.relationship,
        homeBase = bpnpc_copy(brain.homeBase or brain.base),
        homeBaseId = brain.homeBaseId or brain.baseId,
        homeBaseZoneId = brain.homeBaseZoneId,
        homeBaseZoneType = brain.homeBaseZoneType,
        homeBaseZone = bpnpc_copy(brain.homeBaseZone),
        baseZoneId = brain.baseZoneId,
        baseZoneType = brain.baseZoneType,
        baseDuty = brain.baseDuty,
        baseDutyState = brain.baseDutyState,
        baseDutyReason = brain.baseDutyReason,
        baseDutyGroupId = brain.baseDutyGroupId,
        baseDutyOwner = brain.baseDutyOwner,
        guardPoint = bpnpc_copy(brain.guardPoint),
        patrolPoint = bpnpc_copy(brain.patrolPoint),
        medicalPoint = bpnpc_copy(brain.medicalPoint),
        restPoint = bpnpc_copy(brain.restPoint),
        foodPoint = bpnpc_copy(brain.foodPoint),
        ammoPoint = bpnpc_copy(brain.ammoPoint),
        storagePoint = bpnpc_copy(brain.storagePoint),
        returnPoint = bpnpc_copy(brain.returnPoint),
        currentWeapon = NPCPersistentNPCBridge.BuildCurrentWeapon(zombie, brain),
        ammo = NPCPersistentNPCBridge.BuildAmmoLite(zombie, brain),
        inventoryLite = NPCPersistentNPCBridge.BuildInventoryLite(zombie, brain),
        weapons = bpnpc_copy(brain.weapons),
        inventory = bpnpc_copy(brain.inventory),
        loot = bpnpc_copy(brain.loot),
        key = bpnpc_copy(brain.key),
        needs = bpnpc_copy(brain.needs or (brain.ai and brain.ai.needs)),
        stock = bpnpc_copy(brain.stock or (brain.ai and brain.ai.stock)),
        skills = bpnpc_copy(brain.skills or (brain.ai and brain.ai.skills)),
        xp = bpnpc_copy(brain.xp or (brain.ai and brain.ai.xp)),
        morale = brain.morale or (brain.ai and brain.ai.morale),
        fear = brain.fear or (brain.ai and brain.ai.fear),
        aggression = brain.aggression or (brain.ai and brain.ai.aggression),
        discipline = brain.discipline or (brain.ai and brain.ai.discipline),
        lastKnownEnemyPosition = bpnpc_copy(brain.lastKnownEnemyPosition or (brain.ai and brain.ai.lastKnownEnemyPosition)),
        order = bpnpc_copy(brain.order),
        fireMode = brain.order and brain.order.fireMode or brain.fireMode,
        program = bpnpc_copy(brain.program),
        sim = bpnpc_copy(brain.sim),
        fsm = bpnpc_copy(brain.fsm),
        watchdog = bpnpc_copy(brain.watchdog),
        debug = bpnpc_copy(brain.debug),
        dna = bpnpc_copy(brain.dna),
        state = brain.state or (brain.sim and brain.sim.state),
        lastTask = bpnpc_copy(brain.lastTask or (brain.tasks and brain.tasks[1])),
        location = bpnpc_normalizeLocation(x, y, z, brain.bornCoords),
        roadPatrol = brain.roadPatrol or false,
        roadBias = brain.roadBias or false,
        preferRoads = brain.preferRoads or false,
        patrolColor = brain.patrolColor,
        encounterId = brain.encounterId,
        inBattle = brain.inBattle or brain.virtualBattle or false,
        virtualBattle = brain.virtualBattle or false,
        battleId = brain.battleId,
        enemyGroupId = brain.battleEnemyGroupId or brain.enemyGroupId,
        battleEnemyGroupId = brain.battleEnemyGroupId or brain.enemyGroupId
    }
end

function NPCPersistentNPCBridge.MarkDead(gmd, uidOrBrain)
    if not gmd then return end
    NPCPersistentNPCBridge.EnsureData(gmd)
    local uid = bpnpc_uidOf(uidOrBrain)
    if not uid then return end
    uid = tostring(uid)
    local now = bpnpc_now()
    local profile = bpnpc_getProfileRaw(gmd, uid) or {uid = uid, persistentId = uid}
    if type(uidOrBrain) == "table" then profile = bpnpc_enrich(profile, uidOrBrain) end
    if NPCDiagnosticsBridge and NPCDiagnosticsBridge.Log then
        NPCDiagnosticsBridge.Log("PERSISTENT_DEAD", "NPCPersistentNPCBridge.MarkDead writing dead persistent profile", {uid=uid, runtimeId=profile.runtimeId, persistentId=profile.persistentId, groupId=profile.groupId or profile.worldGroupId}, "persistent-dead:" .. tostring(uid), true)
    end
    profile.dead = true
    profile.deathAt = profile.deathAt or now
    profile.updated = now
    profile.version = NPCPersistentNPCBridge.Version
    gmd.PersistentNPCs[uid] = profile
    gmd.Registry[uid] = bpnpc_copy(profile)
    gmd.DeadRegistry[uid] = {uid = uid, deathAt = profile.deathAt, groupId = profile.groupId or profile.worldGroupId}
    if profile.runtimeId then
        local rid = tostring(profile.runtimeId)
        if gmd.PersistentRuntimeToUID then gmd.PersistentRuntimeToUID[rid] = nil end
        if gmd.RuntimeToUID then gmd.RuntimeToUID[rid] = nil end
    end
end

function NPCPersistentNPCBridge.IsDead(gmd, uidOrBrain)
    if not gmd then return false end
    NPCPersistentNPCBridge.EnsureData(gmd)
    local uid = bpnpc_uidOf(uidOrBrain)
    if not uid then return false end
    local profile = bpnpc_getProfileRaw(gmd, tostring(uid))
    if profile and profile.dead then return true end
    return gmd.DeadRegistry and gmd.DeadRegistry[tostring(uid)] ~= nil
end

function NPCPersistentNPCBridge.PruneProfiles(gmd)
    if not (gmd and gmd.PersistentNPCs) then return end
    local maxProfiles = tonumber(NPCPersistentNPCBridge.MaxProfiles) or 500
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        maxProfiles = NPCLegacySettingsBridge.GetNumber("Persistent_MaxProfiles", maxProfiles, 50, 10000)
    end
    if maxProfiles <= 0 then return end

    local total = bpnpc_tableCount(gmd.PersistentNPCs)
    local now = bpnpc_now()
    local keepDeadHours = tonumber(NPCPersistentNPCBridge.KeepDeadHours) or (24 * 7)

    for uid, profile in pairs(gmd.PersistentNPCs) do
        if type(profile) == "table" and profile.dead and profile.deathAt and now - tonumber(profile.deathAt) > keepDeadHours then
            gmd.PersistentNPCs[uid] = nil
            if gmd.Registry then gmd.Registry[uid] = nil end
            if gmd.DeadRegistry then gmd.DeadRegistry[uid] = nil end
            total = total - 1
        end
    end

    if total <= maxProfiles then return end

    local dead = {}
    for uid, profile in pairs(gmd.PersistentNPCs) do
        if type(profile) == "table" and profile.dead then
            dead[#dead + 1] = {uid = uid, t = tonumber(profile.updated or profile.deathAt) or 0}
        end
    end
    table.sort(dead, function(a, b) return a.t < b.t end)
    local removeNeed = total - maxProfiles
    for i = 1, math.min(removeNeed, #dead) do
        local uid = dead[i].uid
        gmd.PersistentNPCs[uid] = nil
        if gmd.Registry then gmd.Registry[uid] = nil end
        if gmd.DeadRegistry then gmd.DeadRegistry[uid] = nil end
    end
end
