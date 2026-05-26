-- NPCFactionDocsBridge.lua
-- Neutral shared backend for virtual faction papers and daily checkpoint passwords. Does not add physical items or change player faction.

NPCFactionDocsBridge = NPCFactionDocsBridge or {}

local BFD_PASSWORD_WORDS = {
    "River", "Ash", "Bridge", "Lantern", "Cedar", "Delta", "North", "Harbor",
    "Signal", "Iron", "Field", "Winter", "Road", "Shelter", "Beacon", "Market"
}

local BFD_DOC_TYPES = {
    faction_pass = {label="faction pass", pass=true, failChance=0},
    convoy_order = {label="convoy order", pass=true, failChance=0},
    stolen_badge = {label="stolen badge", pass=true, failChance=18},
    forged_papers = {label="forged papers", pass=true, failChance=12}
}

local function bfd_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        local ok, value = pcall(function() return NPCLegacySettingsBridge.GetBool(name, defaultValue == true) end)
        if ok and value ~= nil then return value == true end
    end
    return defaultValue == true
end

local function bfd_num(name, defaultValue, minValue, maxValue)
    local value = defaultValue
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        local ok, got = pcall(function() return NPCLegacySettingsBridge.GetNumber(name, defaultValue, minValue, maxValue) end)
        if ok and got ~= nil then value = got end
    end
    value = tonumber(value) or tonumber(defaultValue) or 0
    if minValue ~= nil and value < minValue then value = minValue end
    if maxValue ~= nil and value > maxValue then value = maxValue end
    return value
end

local function bfd_now()
    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then
            local ok, value = pcall(function() return gt:getWorldAgeHours() end)
            if ok and value then return tonumber(value) or 0 end
        end
    end
    return os.time and (os.time() / 3600) or 0
end

local function bfd_rand(maxValue)
    maxValue = math.floor(tonumber(maxValue) or 0)
    if maxValue <= 0 then return 0 end
    if ZombRand then
        local ok, value = pcall(function() return ZombRand(maxValue) end)
        if ok and value ~= nil then return tonumber(value) or 0 end
    end
    return math.random(0, maxValue - 1)
end

local function bfd_side(side)
    if NPCFactionBridge and NPCFactionBridge.NormalizeSide then
        local s = NPCFactionBridge.NormalizeSide(side)
        if s then return s end
    end
    side = tostring(side or ""):lower()
    if side == "red" or side == "green" or side == "blue" or side == "black" then return side end
    return nil
end

local function bfd_playerId(player)
    if not player then return nil end
    if NPCUtils and NPCUtils.GetCharacterID then
        local ok, id = pcall(function() return NPCUtils.GetCharacterID(player) end)
        if ok and id ~= nil then return id end
    end
    if player.getOnlineID then
        local ok, id = pcall(function() return player:getOnlineID() end)
        if ok and id ~= nil then return id end
    end
    return nil
end

local function bfd_playerName(player)
    if not player then return nil end
    if player.getUsername then
        local ok, name = pcall(function() return player:getUsername() end)
        if ok and name then return tostring(name) end
    end
    if player.getDisplayName then
        local ok, name = pcall(function() return player:getDisplayName() end)
        if ok and name then return tostring(name) end
    end
    return nil
end

local function bfd_docType(docType)
    docType = tostring(docType or "")
    if BFD_DOC_TYPES[docType] then return docType end
    return "faction_pass"
end

local function bfd_docLabel(docType)
    docType = bfd_docType(docType)
    return BFD_DOC_TYPES[docType] and BFD_DOC_TYPES[docType].label or tostring(docType)
end

local function bfd_sideLabel(side)
    if NPCFactionBridge and NPCFactionBridge.GetSideLabel then
        local ok, label = pcall(function() return NPCFactionBridge.GetSideLabel(side) end)
        if ok and label then return tostring(label) end
    end
    return tostring(side or "faction")
end

function NPCFactionDocsBridge.IsEnabled()
    return bfd_bool("Documents_Enabled", true)
end

function NPCFactionDocsBridge.DocumentHours()
    return bfd_num("Documents_DocumentHours", 72, 1, 10080)
end

function NPCFactionDocsBridge.PasswordHours()
    return bfd_num("Documents_PasswordHours", 24, 1, 240)
end

function NPCFactionDocsBridge.IntelRewardChance()
    return bfd_num("Documents_IntelRewardChance", 55, 0, 100)
end

function NPCFactionDocsBridge.ForgedFailChance()
    return bfd_num("Documents_ForgedFailChance", 12, 0, 100)
end

function NPCFactionDocsBridge.EnsureData(gmd)
    if not gmd then return nil end
    gmd.NPCFactionDocsBridge = gmd.NPCFactionDocsBridge or {}
    gmd.NPCFactionDocsBridge.playerDocs = gmd.NPCFactionDocsBridge.playerDocs or {}
    gmd.NPCFactionDocsBridge.learnedPasswords = gmd.NPCFactionDocsBridge.learnedPasswords or {}
    gmd.NPCFactionDocsBridge.dailyPasswords = gmd.NPCFactionDocsBridge.dailyPasswords or {}
    gmd.NPCFactionDocsBridge.stats = gmd.NPCFactionDocsBridge.stats or {docsGranted=0, passwordsLearned=0, documentPasses=0, passwordPasses=0, denied=0}
    gmd.NPCFactionDocsBridge.nextId = tonumber(gmd.NPCFactionDocsBridge.nextId) or 1
    return gmd.NPCFactionDocsBridge
end

function NPCFactionDocsBridge.PlayerId(player)
    return bfd_playerId(player)
end

function NPCFactionDocsBridge.GetDailyPassword(gmd, side)
    if not NPCFactionDocsBridge.IsEnabled() then return nil end
    local data = NPCFactionDocsBridge.EnsureData(gmd)
    side = bfd_side(side)
    if not data or not side then return nil end
    local now = bfd_now()
    local current = data.dailyPasswords[side]
    if type(current) == "table" and current.expiresAt and now < tonumber(current.expiresAt) then return current end
    local idx = 1 + bfd_rand(#BFD_PASSWORD_WORDS)
    current = {
        side = side,
        password = BFD_PASSWORD_WORDS[idx] or "River",
        createdAt = now,
        expiresAt = now + NPCFactionDocsBridge.PasswordHours()
    }
    data.dailyPasswords[side] = current
    return current
end

function NPCFactionDocsBridge.GrantDocument(gmd, player, side, docType, source, hours)
    if not NPCFactionDocsBridge.IsEnabled() then return nil end
    local data = NPCFactionDocsBridge.EnsureData(gmd)
    local pid = bfd_playerId(player)
    side = bfd_side(side)
    if not data or not pid or not side then return nil end
    docType = bfd_docType(docType)
    data.playerDocs[tostring(pid)] = data.playerDocs[tostring(pid)] or {}
    local id = "doc_" .. tostring(data.nextId)
    data.nextId = (tonumber(data.nextId) or 1) + 1
    local doc = {
        id = id,
        playerId = pid,
        playerName = bfd_playerName(player),
        side = side,
        docType = docType,
        label = bfd_docLabel(docType),
        source = source or "unknown",
        createdAt = bfd_now(),
        expiresAt = bfd_now() + (tonumber(hours) or NPCFactionDocsBridge.DocumentHours()),
        uses = 0
    }
    data.playerDocs[tostring(pid)][id] = doc
    data.stats.docsGranted = (tonumber(data.stats.docsGranted) or 0) + 1
    return doc
end

function NPCFactionDocsBridge.GrantPassword(gmd, player, side, source, hours)
    if not NPCFactionDocsBridge.IsEnabled() then return nil end
    local data = NPCFactionDocsBridge.EnsureData(gmd)
    local pid = bfd_playerId(player)
    side = bfd_side(side)
    if not data or not pid or not side then return nil end
    local pass = NPCFactionDocsBridge.GetDailyPassword(gmd, side)
    if not pass then return nil end
    data.learnedPasswords[tostring(pid)] = data.learnedPasswords[tostring(pid)] or {}
    local rec = {
        side = side,
        password = pass.password,
        source = source or "unknown",
        learnedAt = bfd_now(),
        expiresAt = math.min(tonumber(pass.expiresAt) or (bfd_now() + NPCFactionDocsBridge.PasswordHours()), bfd_now() + (tonumber(hours) or NPCFactionDocsBridge.PasswordHours()))
    }
    data.learnedPasswords[tostring(pid)][side] = rec
    data.stats.passwordsLearned = (tonumber(data.stats.passwordsLearned) or 0) + 1
    return rec
end

function NPCFactionDocsBridge.ValidDocument(gmd, player, side)
    local data = NPCFactionDocsBridge.EnsureData(gmd)
    local pid = bfd_playerId(player)
    side = bfd_side(side)
    if not data or not pid or not side then return nil end
    local docs = data.playerDocs[tostring(pid)]
    if type(docs) ~= "table" then return nil end
    local now = bfd_now()
    local best = nil
    for id, doc in pairs(docs) do
        if type(doc) == "table" then
            if doc.expiresAt and now >= tonumber(doc.expiresAt) then
                docs[id] = nil
            elseif doc.compromised == true then
                docs[id] = nil
            elseif bfd_side(doc.side) == side then
                best = doc
                if doc.docType == "faction_pass" or doc.docType == "convoy_order" then return doc end
            end
        end
    end
    return best
end

function NPCFactionDocsBridge.KnownPassword(gmd, player, side)
    local data = NPCFactionDocsBridge.EnsureData(gmd)
    local pid = bfd_playerId(player)
    side = bfd_side(side)
    if not data or not pid or not side then return nil end
    local byPlayer = data.learnedPasswords[tostring(pid)]
    if type(byPlayer) ~= "table" then return nil end
    local rec = byPlayer[side]
    if type(rec) ~= "table" then return nil end
    if rec.expiresAt and bfd_now() >= tonumber(rec.expiresAt) then
        byPlayer[side] = nil
        return nil
    end
    return rec
end

function NPCFactionDocsBridge.UseDocumentAtCheckpoint(gmd, player, checkpoint)
    if not NPCFactionDocsBridge.IsEnabled() then return false, "disabled" end
    local data = NPCFactionDocsBridge.EnsureData(gmd)
    local side = checkpoint and bfd_side(checkpoint.side or checkpoint.checkpointSide)
    local doc = NPCFactionDocsBridge.ValidDocument(gmd, player, side)
    if not doc then
        if data then data.stats.denied = (tonumber(data.stats.denied) or 0) + 1 end
        return false, "no_document"
    end
    local docType = bfd_docType(doc.docType)
    local failChance = tonumber(doc.failChance)
    if failChance == nil then
        failChance = BFD_DOC_TYPES[docType] and BFD_DOC_TYPES[docType].failChance or 0
    end
    if docType == "forged_papers" then failChance = math.max(failChance, NPCFactionDocsBridge.ForgedFailChance()) end
    if failChance > 0 and bfd_rand(100) < failChance then
        doc.compromised = true
        doc.compromisedAt = bfd_now()
        return false, "document_failed", doc
    end
    doc.uses = (tonumber(doc.uses) or 0) + 1
    doc.lastUsedAt = bfd_now()
    data.stats.documentPasses = (tonumber(data.stats.documentPasses) or 0) + 1
    return true, "document", doc
end

function NPCFactionDocsBridge.UsePasswordAtCheckpoint(gmd, player, checkpoint)
    if not NPCFactionDocsBridge.IsEnabled() then return false, "disabled" end
    local data = NPCFactionDocsBridge.EnsureData(gmd)
    local side = checkpoint and bfd_side(checkpoint.side or checkpoint.checkpointSide)
    local known = NPCFactionDocsBridge.KnownPassword(gmd, player, side)
    if not known then
        if data then data.stats.denied = (tonumber(data.stats.denied) or 0) + 1 end
        return false, "no_password"
    end
    local current = NPCFactionDocsBridge.GetDailyPassword(gmd, side)
    if not current or tostring(current.password) ~= tostring(known.password) then
        return false, "wrong_password", known
    end
    data.stats.passwordPasses = (tonumber(data.stats.passwordPasses) or 0) + 1
    return true, "password", known
end

function NPCFactionDocsBridge.GrantIntelReward(gmd, player, side, source)
    if not NPCFactionDocsBridge.IsEnabled() then return nil end
    if bfd_rand(100) >= NPCFactionDocsBridge.IntelRewardChance() then return nil end
    side = bfd_side(side) or ((bfd_rand(2) == 0) and "red" or "green")
    local roll = bfd_rand(100)
    if roll < 45 then
        return {kind="password", data=NPCFactionDocsBridge.GrantPassword(gmd, player, side, source or "intel")}
    elseif roll < 80 then
        return {kind="document", data=NPCFactionDocsBridge.GrantDocument(gmd, player, side, "faction_pass", source or "intel")}
    elseif roll < 92 then
        return {kind="document", data=NPCFactionDocsBridge.GrantDocument(gmd, player, side, "convoy_order", source or "intel")}
    elseif roll < 97 then
        return {kind="document", data=NPCFactionDocsBridge.GrantDocument(gmd, player, side, "stolen_badge", source or "intel")}
    end
    return {kind="document", data=NPCFactionDocsBridge.GrantDocument(gmd, player, side, "forged_papers", source or "intel")}
end

function NPCFactionDocsBridge.DescribeReward(reward)
    if not reward or not reward.data then return nil end
    if reward.kind == "password" then
        return "Password learned for " .. bfd_sideLabel(reward.data.side) .. ": " .. tostring(reward.data.password)
    end
    return "Document acquired: " .. bfd_sideLabel(reward.data.side) .. " " .. tostring(reward.data.label or reward.data.docType)
end

function NPCFactionDocsBridge.StatusText(gmd, player)
    local data = NPCFactionDocsBridge.EnsureData(gmd)
    local pid = bfd_playerId(player)
    if not data or not pid then return "No faction papers." end
    local parts = {}
    local docs = data.playerDocs[tostring(pid)]
    local now = bfd_now()
    if type(docs) == "table" then
        for id, doc in pairs(docs) do
            if type(doc) == "table" and doc.compromised == true then
                docs[id] = nil
            elseif type(doc) == "table" and doc.expiresAt and now < tonumber(doc.expiresAt) then
                table.insert(parts, bfd_sideLabel(doc.side) .. " " .. tostring(doc.label or doc.docType))
            elseif type(doc) == "table" then
                docs[id] = nil
            end
        end
    end
    local passwords = data.learnedPasswords[tostring(pid)]
    if type(passwords) == "table" then
        for side, rec in pairs(passwords) do
            if type(rec) == "table" and rec.expiresAt and now < tonumber(rec.expiresAt) then
                table.insert(parts, bfd_sideLabel(side) .. " password: " .. tostring(rec.password))
            elseif type(rec) == "table" then
                passwords[side] = nil
            end
        end
    end
    if #parts <= 0 then return "No valid faction papers or passwords." end
    return table.concat(parts, " / ")
end
