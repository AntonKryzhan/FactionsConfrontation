-- NPCFactionDocsBridge.lua
-- Neutral shared backend for faction papers and daily checkpoint passwords. Stage 366 adds physical document items without adding disguise mechanics or UI boards.

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

-- MP-safe physical representation: vanilla paper tagged with ModData.
-- This avoids introducing extra media/scripts files that can desync hosted MP servers.
local BFD_GENERIC_DOC_ITEM = "Base.SheetPaper2"
local BFD_LEGACY_PHYSICAL_DOC_ITEMS = {
    red = {faction_pass = "FactionsConfrontation.RedFactionPass", convoy_order = "FactionsConfrontation.RedConvoyOrder", stolen_badge = "FactionsConfrontation.RedStolenBadge", forged_papers = "FactionsConfrontation.RedForgedPapers"},
    green = {faction_pass = "FactionsConfrontation.GreenFactionPass", convoy_order = "FactionsConfrontation.GreenConvoyOrder", stolen_badge = "FactionsConfrontation.GreenStolenBadge", forged_papers = "FactionsConfrontation.GreenForgedPapers"},
    blue = {faction_pass = "FactionsConfrontation.BlueFactionPass", convoy_order = "FactionsConfrontation.BlueConvoyOrder", stolen_badge = "FactionsConfrontation.BlueStolenBadge", forged_papers = "FactionsConfrontation.BlueForgedPapers"},
    black = {faction_pass = "FactionsConfrontation.BlackFactionPass", convoy_order = "FactionsConfrontation.BlackConvoyOrder", stolen_badge = "FactionsConfrontation.BlackStolenBadge", forged_papers = "FactionsConfrontation.BlackForgedPapers"}
}

local BFD_ITEM_TO_DOC = {}
for bfdItemSide, bfdSideItems in pairs(BFD_LEGACY_PHYSICAL_DOC_ITEMS) do
    for bfdItemDocType, bfdItemFullType in pairs(bfdSideItems) do
        BFD_ITEM_TO_DOC[bfdItemFullType] = {side = bfdItemSide, docType = bfdItemDocType}
    end
end

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

function NPCFactionDocsBridge.PhysicalDocumentsEnabled()
    return bfd_bool("Documents_PhysicalItemsEnabled", true)
end

function NPCFactionDocsBridge.PhysicalCheckpointUseEnabled()
    return bfd_bool("Documents_PhysicalCheckpointUseEnabled", true)
end

function NPCFactionDocsBridge.ConsumeFailedPhysicalDocuments()
    return bfd_bool("Documents_PhysicalConsumeOnFail", true)
end

function NPCFactionDocsBridge.PhysicalItemType(side, docType)
    if not bfd_side(side) then return nil end
    return BFD_GENERIC_DOC_ITEM
end

local function bfd_itemFullType(item)
    if not item then return nil end
    if item.getFullType then
        local ok, ft = pcall(function() return item:getFullType() end)
        if ok and ft then return tostring(ft) end
    end
    if item.getModule and item.getType then
        local ok, ft = pcall(function() return tostring(item:getModule()) .. "." .. tostring(item:getType()) end)
        if ok and ft then return ft end
    end
    return nil
end

local function bfd_itemModData(item)
    if item and item.getModData then
        local ok, md = pcall(function() return item:getModData() end)
        if ok then return md end
    end
    return nil
end

local function bfd_scanInventoryItems(container, out, depth)
    if not container or depth > 3 then return out end
    local items = nil
    if container.getItems then
        local ok, got = pcall(function() return container:getItems() end)
        if ok then items = got end
    end
    if not items or not items.size or not items.get then return out end
    local size = 0
    local okSize, gotSize = pcall(function() return items:size() end)
    if okSize then size = tonumber(gotSize) or 0 end
    for i = 0, size - 1 do
        local okItem, item = pcall(function() return items:get(i) end)
        if okItem and item then
            out[#out + 1] = item
            if item.getInventory then
                local okInv, inv = pcall(function() return item:getInventory() end)
                if okInv and inv then bfd_scanInventoryItems(inv, out, depth + 1) end
            end
        end
    end
    return out
end

local function bfd_playerInventory(player)
    if player and player.getInventory then
        local ok, inv = pcall(function() return player:getInventory() end)
        if ok then return inv end
    end
    return nil
end

local function bfd_removeItem(item, rootInventory)
    if not item then return false end
    if item.getContainer then
        local okContainer, container = pcall(function() return item:getContainer() end)
        if okContainer and container and container.Remove then
            local okRemove = pcall(function() container:Remove(item) end)
            if okRemove then return true end
        end
    end
    if rootInventory and rootInventory.Remove then
        local ok = pcall(function() rootInventory:Remove(item) end)
        if ok then return true end
    end
    return false
end

function NPCFactionDocsBridge.AddPhysicalDocument(gmd, player, doc)
    if not NPCFactionDocsBridge.PhysicalDocumentsEnabled() then return nil end
    if not (player and doc) then return nil end
    local inv = bfd_playerInventory(player)
    if not inv or not inv.AddItem then return nil end
    local fullType = NPCFactionDocsBridge.PhysicalItemType(doc.side, doc.docType)
    if not fullType then return nil end
    local ok, item = pcall(function() return inv:AddItem(fullType) end)
    if not ok or not item then return nil end
    local md = bfd_itemModData(item)
    if md then
        md.FactionsConfrontationDoc = true
        md.fcDocId = tostring(doc.id or "")
        md.fcDocSide = tostring(doc.side or "")
        md.fcDocType = tostring(doc.docType or "")
        md.fcDocSource = tostring(doc.source or "")
        md.fcDocCreatedAt = tonumber(doc.createdAt) or bfd_now()
        md.fcDocExpiresAt = tonumber(doc.expiresAt) or 0
        md.fcDocFailChance = tonumber(doc.failChance) or (BFD_DOC_TYPES[bfd_docType(doc.docType)] and BFD_DOC_TYPES[bfd_docType(doc.docType)].failChance or 0)
    end
    doc.physicalItemType = fullType
    doc.physicalGranted = true
    if gmd then
        local data = NPCFactionDocsBridge.EnsureData(gmd)
        if data and data.stats then data.stats.physicalDocsGranted = (tonumber(data.stats.physicalDocsGranted) or 0) + 1 end
    end
    return item
end

function NPCFactionDocsBridge.FindPhysicalDocument(player, side)
    if not NPCFactionDocsBridge.PhysicalCheckpointUseEnabled() then return nil end
    local inv = bfd_playerInventory(player)
    if not inv then return nil end
    side = bfd_side(side)
    if not side then return nil end
    local items = bfd_scanInventoryItems(inv, {}, 0)
    local now = bfd_now()
    local best = nil
    for _, item in ipairs(items) do
        local fullType = bfd_itemFullType(item)
        local md = bfd_itemModData(item)
        local meta = nil
        if md and md.FactionsConfrontationDoc == true and bfd_side(md.fcDocSide) == side then
            meta = {side = side, docType = bfd_docType(md.fcDocType)}
        else
            meta = fullType and BFD_ITEM_TO_DOC[fullType] or nil
        end
        if meta and meta.side == side then
            local docType = bfd_docType(meta.docType)
            local expiresAt = md and tonumber(md.fcDocExpiresAt) or nil
            if not expiresAt or expiresAt <= 0 or now < expiresAt then
                local rec = {
                    id = md and md.fcDocId or fullType,
                    side = side,
                    docType = docType,
                    label = bfd_docLabel(docType),
                    physical = true,
                    item = item,
                    itemType = fullType,
                    failChance = md and tonumber(md.fcDocFailChance) or (BFD_DOC_TYPES[docType] and BFD_DOC_TYPES[docType].failChance or 0),
                    expiresAt = expiresAt,
                    uses = md and tonumber(md.fcDocUses) or 0
                }
                best = rec
                if docType == "faction_pass" or docType == "convoy_order" then return rec end
            elseif NPCFactionDocsBridge.ConsumeFailedPhysicalDocuments() then
                bfd_removeItem(item, inv)
            end
        end
    end
    return best
end

function NPCFactionDocsBridge.HasPhysicalDocument(player, side)
    return NPCFactionDocsBridge.FindPhysicalDocument(player, side) ~= nil
end

function NPCFactionDocsBridge.EnsureData(gmd)
    if not gmd then return nil end
    gmd.NPCFactionDocsBridge = gmd.NPCFactionDocsBridge or {}
    gmd.NPCFactionDocsBridge.playerDocs = gmd.NPCFactionDocsBridge.playerDocs or {}
    gmd.NPCFactionDocsBridge.learnedPasswords = gmd.NPCFactionDocsBridge.learnedPasswords or {}
    gmd.NPCFactionDocsBridge.dailyPasswords = gmd.NPCFactionDocsBridge.dailyPasswords or {}
    gmd.NPCFactionDocsBridge.stats = gmd.NPCFactionDocsBridge.stats or {docsGranted=0, physicalDocsGranted=0, passwordsLearned=0, documentPasses=0, physicalDocumentPasses=0, passwordPasses=0, denied=0}
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
    NPCFactionDocsBridge.AddPhysicalDocument(gmd, player, doc)
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
    local physicalDoc = NPCFactionDocsBridge.FindPhysicalDocument(player, side)
    local doc = physicalDoc or NPCFactionDocsBridge.ValidDocument(gmd, player, side)
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
        if doc.physical and doc.item then
            local md = bfd_itemModData(doc.item)
            if md then md.fcDocCompromised = true; md.fcDocCompromisedAt = doc.compromisedAt end
            if NPCFactionDocsBridge.ConsumeFailedPhysicalDocuments() then bfd_removeItem(doc.item, bfd_playerInventory(player)) end
        end
        return false, "document_failed", doc
    end
    doc.uses = (tonumber(doc.uses) or 0) + 1
    doc.lastUsedAt = bfd_now()
    if doc.physical and doc.item then
        local md = bfd_itemModData(doc.item)
        if md then md.fcDocUses = doc.uses; md.fcDocLastUsedAt = doc.lastUsedAt end
        data.stats.physicalDocumentPasses = (tonumber(data.stats.physicalDocumentPasses) or 0) + 1
    else
        data.stats.documentPasses = (tonumber(data.stats.documentPasses) or 0) + 1
    end
    return true, doc.physical and "physical_document" or "document", doc
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
    if NPCFactionDocsBridge.PhysicalCheckpointUseEnabled() then
        local inv = bfd_playerInventory(player)
        if inv then
            local foundPhysical = {}
            local nowPhysical = bfd_now()
            for _, item in ipairs(bfd_scanInventoryItems(inv, {}, 0)) do
                local fullType = bfd_itemFullType(item)
                local meta = fullType and BFD_ITEM_TO_DOC[fullType] or nil
                if meta then
                    local md = bfd_itemModData(item)
                    local exp = md and tonumber(md.fcDocExpiresAt) or nil
                    if not exp or exp <= 0 or nowPhysical < exp then
                        local key = tostring(meta.side) .. ":" .. tostring(meta.docType)
                        if not foundPhysical[key] then
                            table.insert(parts, bfd_sideLabel(meta.side) .. " physical " .. bfd_docLabel(meta.docType))
                            foundPhysical[key] = true
                        end
                    end
                end
            end
        end
    end
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
