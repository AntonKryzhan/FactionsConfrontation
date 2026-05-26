-- NPCRadioInterceptClientBridge.lua
-- Context menu and notifications for player-facing radio intercepts.

require "NPCCore/NPCLegacyContractBridge"
NPCRadioInterceptClientBridge = NPCRadioInterceptClientBridge or {}

local NPC_RADIO_LEGACY_TEXT_PREFIX = NPCLegacyContractBridge.Text.prefix

local function bric_key(name)
    return NPC_RADIO_LEGACY_TEXT_PREFIX .. tostring(name or "")
end

local function bric_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        local ok, value = pcall(function() return NPCLegacySettingsBridge.GetBool(name, defaultValue == true) end)
        if ok and value ~= nil then return value == true end
    end
    return defaultValue == true
end

local function bric_number(name, defaultValue, minValue, maxValue)
    local value = defaultValue
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        local ok, got = pcall(function() return NPCLegacySettingsBridge.GetNumber(name, defaultValue, minValue, maxValue) end)
        if ok and got ~= nil then value = got end
    end
    value = tonumber(value) or tonumber(defaultValue) or 0
    if minValue and value < minValue then value = minValue end
    if maxValue and value > maxValue then value = maxValue end
    return value
end

local function bric_player()
    return getPlayer() or getSpecificPlayer(0)
end

local function bric_console(text)
    if not text then return false end
    print("[NPCRadio] [Radio] " .. tostring(text))
    return true
end

local function bric_makeMessage(line)
    local message = {}
    function message:getTextWithPrefix() return line end
    function message:getAuthor() return "Radio" end
    function message:setText(value) line = tostring(value or line) end
    return message
end

local bric_chatColorIndex = 0
local bric_chatColors = {
    "<RGB:0.55,0.85,1.0>",
    "<RGB:0.55,1.0,0.55>",
    "<RGB:1.0,0.83,0.35>",
    "<RGB:1.0,0.55,0.55>",
    "<RGB:0.78,0.65,1.0>",
    "<RGB:0.45,1.0,0.85>"
}

local function bric_colorizeChatLine(line)
    bric_chatColorIndex = bric_chatColorIndex + 1
    if bric_chatColorIndex > #bric_chatColors then bric_chatColorIndex = 1 end
    return bric_chatColors[bric_chatColorIndex] .. tostring(line or "")
end

local function bric_ru(key, fallback, ...)
    local value = nil
    if getText then
        local ok, translated = pcall(getText, key)
        if ok and translated and tostring(translated) ~= tostring(key) then
            value = tostring(translated)
        end
    end
    value = value or tostring(fallback or "")

    local args = {...}
    for i = 1, #args do
        value = string.gsub(value, "%%" .. tostring(i), tostring(args[i] or ""))
    end
    return value
end

local function bric_ruSide(meta)
    if meta and meta.ruKey then return bric_ru(meta.ruKey, meta.ruFallback or meta.en or "?") end
    return bric_ru(bric_key("RadioSide_Open"), "obshchiy diapazon")
end

local function bric_gameLanguage()
    if getText then
        local ok, probe = pcall(getText, bric_key("RadioLangProbe"))
        if ok and probe then
            probe = tostring(probe)
            if probe == "RU" then return "ru" end
            if probe == "EN" then return "en" end
        end
    end

    if getCore then
        local ok, lang = pcall(function()
            local core = getCore()
            if core and core.getOptionLanguageName then return core:getOptionLanguageName() end
            if core and core.getOptionLanguage then return core:getOptionLanguage() end
            return nil
        end)
        if ok and lang then
            lang = string.lower(tostring(lang))
            if string.find(lang, "ru", 1, true) or string.find(lang, "russian", 1, true) then return "ru" end
        end
    end

    return "en"
end

local function bric_chatLanguage()
    local mode = math.floor(bric_number("RadioIntercept_ChatLanguage", 1, 1, 4) + 0.5)
    if mode == 2 then return "en" end
    if mode == 3 then return "ru" end
    if mode == 4 then return "both" end
    return bric_gameLanguage()
end

local function bric_applyLanguage(line)
    line = tostring(line or "")
    local mode = bric_chatLanguage()
    if mode == "both" then return line end

    local en, localized = string.match(line, "^(.*)%s+/%s+(.+)$")
    if not en or not localized then return line end

    if mode == "ru" then return localized end
    return en
end

local function bric_findGeneralChatTab(chat)
    if not (chat and chat.tabs) then return nil end

    for _, tab in ipairs(chat.tabs) do
        if tab and tab.chatStreams then
            for _, stream in ipairs(tab.chatStreams) do
                if stream and (stream.name == "general" or stream.command == "/all ") then
                    return tab
                end
            end
        end
    end

    return chat.defaultTab or chat.chatText or chat.tabs[1]
end

local function bric_rebuildChatText(chatText)
    if not (chatText and chatText.chatTextLines) then return end

    local newText = ""
    for i, value in ipairs(chatText.chatTextLines) do
        local line = tostring(value or "")
        if i == #chatText.chatTextLines then
            line = string.gsub(line, "  $", "")
        end
        newText = newText .. line
    end
    chatText.text = newText
end

local function bric_blinkChatTab(chat, chatText)
    if not (chat and chatText and chat.panel and chat.panel.blinkTabs and chat.chatText) then return end
    if not chatText.tabTitle or not chat.chatText.tabTitle or chatText.tabTitle == chat.chatText.tabTitle then return end

    for _, blinkedTab in ipairs(chat.panel.blinkTabs) do
        if blinkedTab == chatText.tabTitle then return end
    end
    table.insert(chat.panel.blinkTabs, chatText.tabTitle)
end

local function bric_tryISChat(line)
    if not (ISChat and ISChat.instance and line) then return false end

    local chat = ISChat.instance
    local chatText = bric_findGeneralChatTab(chat)
    if not chatText then return false end

    chatText.chatTextLines = chatText.chatTextLines or {}
    chatText.chatMessages = chatText.chatMessages or {}

    local scrolledToBottom = true
    if chatText.getScrollHeight and chatText.getHeight then
        local vscroll = chatText.vscroll
        scrolledToBottom = (chatText:getScrollHeight() <= chatText:getHeight()) or (vscroll and vscroll.pos == 1)
    end

    local displayLine = bric_colorizeChatLine(line)

    if ISChat.maxLine and #chatText.chatTextLines > ISChat.maxLine then
        local newLines = {}
        for i, value in ipairs(chatText.chatTextLines) do
            if i ~= 1 then table.insert(newLines, value) end
        end
        table.insert(newLines, displayLine .. "  ")
        chatText.chatTextLines = newLines
    else
        table.insert(chatText.chatTextLines, displayLine .. "  ")
    end

    table.insert(chatText.chatMessages, bric_makeMessage(line))
    bric_rebuildChatText(chatText)

    if chatText.paginate then chatText:paginate() end
    if scrolledToBottom and chatText.setYScroll then chatText:setYScroll(-10000) end
    bric_blinkChatTab(chat, chatText)

    return true
end

local function bric_trim(value)
    value = tostring(value or "")
    value = string.gsub(value, "^%s+", "")
    value = string.gsub(value, "%s+$", "")
    return value
end

local function bric_short(value, limit)
    value = tostring(value or "")
    limit = tonumber(limit) or 140
    if #value <= limit then return value end
    return string.sub(value, 1, math.max(1, limit - 3)) .. "..."
end

local function bric_num(text, pattern)
    local value = tostring(text or ""):match(pattern)
    return tonumber(value)
end

local bric_sideOrder = {"red", "green", "blue", "black"}
local bric_sideMeta = {
    red = {tag="RED", en="Red", ruKey=bric_key("RadioSide_Red"), ruFallback="krasnye", freq=143.70, counter="Red"},
    green = {tag="GREEN", en="Green", ruKey=bric_key("RadioSide_Green"), ruFallback="zelenye", freq=152.30, counter="Green"},
    blue = {tag="BLUE", en="Blue / Neutral", ruKey=bric_key("RadioSide_Blue"), ruFallback="sinie / neytraly", freq=161.50, counter="Blue / Neutral"},
    black = {tag="BLACK", en="Black / Rogue", ruKey=bric_key("RadioSide_Black"), ruFallback="chernye / rogue", freq=171.90, counter="Black / Rogue"}
}

local function bric_sideMetaFor(side)
    if side and bric_sideMeta[side] then return bric_sideMeta[side] end
    return {tag="OPEN", en="Open band", ruKey=bric_key("RadioSide_Open"), ruFallback="obshchiy diapazon", freq=0, counter=""}
end

local function bric_sideFromFrequency(freq)
    freq = tonumber(freq)
    if not freq then return nil end
    local bestSide = nil
    local bestDiff = 999
    for _, side in ipairs(bric_sideOrder) do
        local meta = bric_sideMeta[side]
        local diff = math.abs(freq - meta.freq)
        if diff < bestDiff then
            bestDiff = diff
            bestSide = side
        end
    end
    if bestDiff <= 1.25 then return bestSide end
    return nil
end

local function bric_sideFromText(text, freq)
    local byFreq = bric_sideFromFrequency(freq)
    if byFreq then return byFreq end

    local lower = string.lower(tostring(text or ""))
    if string.find(lower, "black", 1, true) or string.find(lower, "rogue", 1, true) then return "black" end
    if string.find(lower, "blue", 1, true) or string.find(lower, "neutral", 1, true) then return "blue" end
    if string.find(lower, "green", 1, true) then return "green" end
    if string.find(lower, "red", 1, true) then return "red" end
    return nil
end

local function bric_filterRu(filter)
    filter = tostring(filter or "")
    if filter == "narrow" then return bric_ru(bric_key("RadioFilter_Narrow"), "uzkiy") end
    if filter == "wide" then return bric_ru(bric_key("RadioFilter_Wide"), "shirokiy") end
    return filter
end

local function bric_onOffRu(value)
    value = tostring(value or "")
    if value == "ON" then return bric_ru(bric_key("RadioOn"), "VKL") end
    if value == "OFF" then return bric_ru(bric_key("RadioOff"), "VYKL") end
    return value
end

local function bric_signalLine(signal, noise, lock)
    signal = tonumber(signal)
    noise = tonumber(noise)
    lock = tonumber(lock)
    if lock == nil then return nil end

    local en = ""
    local ru = ""
    if lock >= 70 then
        en = "strong lock; map intel is likely reliable"
        ru = bric_ru(bric_key("RadioSignal_Strong"), "silnyy zakhvat; dannym na karte mozhno doveryat")
    elseif lock >= 40 then
        en = "usable lock; map intel is approximate"
        ru = bric_ru(bric_key("RadioSignal_Usable"), "rabochiy zakhvat; tochka na karte primernaya")
    elseif lock >= 20 then
        en = "weak lock; treat map intel as uncertain"
        ru = bric_ru(bric_key("RadioSignal_Weak"), "slabyy zakhvat; tochka mozhet byt netochnoy")
    else
        en = "no usable lock; this is mostly static or unreliable"
        ru = bric_ru(bric_key("RadioSignal_None"), "zakhvata net; eto shum ili nenadezhnye dannye")
    end

    return "[SIGNAL] S" .. tostring(signal or "?") .. " N" .. tostring(noise or "?") .. " L" .. tostring(lock or "?") .. ": " .. en .. " / " .. bric_ru(bric_key("RadioTag_Signal"), "[SIGNAL]") .. " S" .. tostring(signal or "?") .. " N" .. tostring(noise or "?") .. " L" .. tostring(lock or "?") .. ": " .. ru
end

local function bric_bestCounterIntel(text)
    text = tostring(text or "")
    if not string.find(text, "counterintel", 1, true) then return nil end

    local best = nil
    for _, side in ipairs(bric_sideOrder) do
        local meta = bric_sideMeta[side]
        local heat, burned = string.match(text, meta.counter .. "%s+heat%s+(%d+)%s+burned%s+(%d+)m")
        if not heat then heat = string.match(text, meta.counter .. "%s+heat%s+(%d+)") end
        heat = tonumber(heat)
        burned = tonumber(burned)
        if heat then
            local score = heat + ((burned and burned > 0) and 1000 or 0)
            if not best or score > best.score then
                best = {side=side, heat=heat, burned=burned, score=score}
            end
        end
    end

    if not best then return nil end
    if not (best.burned and best.burned > 0) and best.heat < 50 then return nil end
    return best
end

local function bric_counterIntelLine(text)
    local best = bric_bestCounterIntel(text)
    if not best then return nil end

    local meta = bric_sideMetaFor(best.side)
    if best.burned and best.burned > 0 then
        return "[WARNING][" .. meta.tag .. "] " .. meta.en .. " channel is burned for " .. tostring(best.burned) .. " min; reduce scans or enable radio silence. / " .. bric_ru(bric_key("RadioWarn_Burned"), "[VNIMANIE][%1] kanal skomprometirovan na %2 min; menshe skaniruy ili vklyuchi radiomolchanie", bric_ruSide(meta), tostring(best.burned))
    end

    return "[WARNING][" .. meta.tag .. "] " .. meta.en .. " counterintel heat is " .. tostring(best.heat) .. "; repeated scans may expose you. / " .. bric_ru(bric_key("RadioWarn_Heat"), "[VNIMANIE][%1] nagrev kontrrazvedki %2; chastye skany mogut tebya raskryt", bric_ruSide(meta), tostring(best.heat))
end

local function bric_radioSilenceLine(text)
    text = tostring(text or "")
    if string.find(text, "radio silence ON", 1, true) then
        return "[RADIO SILENCE] Active: safer, but passive monitoring is limited. / " .. bric_ru(bric_key("RadioSilence_Active"), "[RADIOMOLCHANIE] Aktivno: bezopasnee, no passivnyy monitoring ogranichen")
    end
    return nil
end

local function bric_mapLine(text, side)
    text = tostring(text or "")
    local meta = bric_sideMetaFor(side)
    if string.find(text, "Map marker added", 1, true) then
        return "[MAP][" .. meta.tag .. "] Fresh intel marker added; open the map and check the new faction-colored marker. / " .. bric_ru(bric_key("RadioMap_Fresh"), "[KARTA][%1] dobavlen svezhiy marker razvedki; otkroy kartu i ishchi novyy marker tsveta fraktsii", bric_ruSide(meta))
    end

    local x, y = string.match(text, "near%s+(%d+),(%d+)")
    if x and y then
        return "[MAP][" .. meta.tag .. "] Approximate grid " .. tostring(x) .. "," .. tostring(y) .. "; use it as a search area, not an exact position. / " .. bric_ru(bric_key("RadioMap_Grid"), "[KARTA][%1] primernaya setka %2,%3; eto rayon poiska, ne tochnaya pozitsiya", bric_ruSide(meta), tostring(x), tostring(y))
    end

    return nil
end

local function bric_interceptTopicLine(body, side, freq, isMonitor)
    body = tostring(body or "")
    local lower = string.lower(body)
    local meta = bric_sideMetaFor(side)
    local freqText = freq and (string.format("%.2f MHz", tonumber(freq) or 0)) or "unknown frequency"
    local sourceEn = isMonitor and "PASSIVE" or "INTERCEPT"
    local sourceRu = isMonitor and bric_ru(bric_key("RadioSource_Passive"), "PASSIVNO") or bric_ru(bric_key("RadioSource_Intercept"), "PEREKHVAT")

    if string.find(lower, "encrypted", 1, true) then
        local progress = string.match(body, "Decoder progress%s+(%d+)%%")
        if progress then
            return "[" .. sourceEn .. "][ENCRYPTED][" .. meta.tag .. "] " .. freqText .. ": encrypted traffic, decoder " .. tostring(progress) .. "%. Keep scanning this band to decode. / " .. bric_ru(bric_key("RadioTopic_EncryptedProgress"), "[%1][SHIFR][%2] %3: shifrovannyy trafik, dekoder %4%%. Prodolzhay slushat etot diapazon dlya rasshifrovki", sourceRu, bric_ruSide(meta), freqText, tostring(progress))
        end
        return "[" .. sourceEn .. "][ENCRYPTED][" .. meta.tag .. "] " .. freqText .. ": encrypted traffic detected. / " .. bric_ru(bric_key("RadioTopic_Encrypted"), "[%1][SHIFR][%2] %3: obnaruzhen shifrovannyy trafik", sourceRu, bric_ruSide(meta), freqText)
    end

    if string.find(lower, "static", 1, true) or string.find(lower, "no useful", 1, true) then
        return "[STATIC][" .. meta.tag .. "] " .. freqText .. ": no useful intelligence. Retune, change filter, or try later. / " .. bric_ru(bric_key("RadioTopic_Static"), "[POMEKHI][%1] %2: poleznoy razvedki net. Perenastroy chastotu, filtr ili poprobuy pozzhe", bric_ruSide(meta), freqText)
    end

    if string.find(lower, "password", 1, true) then
        local password = string.match(body, "password:%s*([^%.]+)")
        if password then
            return "[" .. sourceEn .. "][PASSWORD][" .. meta.tag .. "] Checkpoint password leaked: " .. bric_short(bric_trim(password), 48) .. ". / " .. bric_ru(bric_key("RadioTopic_PasswordValue"), "[%1][PAROL][%2] perekhvachen parol KPP: %3.", sourceRu, bric_ruSide(meta), bric_short(bric_trim(password), 48))
        end
        return "[" .. sourceEn .. "][PASSWORD][" .. meta.tag .. "] Password/code traffic intercepted. / " .. bric_ru(bric_key("RadioTopic_Password"), "[%1][PAROL][%2] perekhvachen parol ili kodovyy obmen", sourceRu, bric_ruSide(meta))
    end

    if string.find(lower, "leader", 1, true) or string.find(lower, "command traffic", 1, true) then
        return "[" .. sourceEn .. "][LEADER][" .. meta.tag .. "] Leader or command activity detected; use the map marker as an approximate lead. / " .. bric_ru(bric_key("RadioTopic_Leader"), "[%1][LIDER][%2] obnaruzhena aktivnost lidera ili komandovaniya; marker na karte primernyy", sourceRu, bric_ruSide(meta))
    end

    if string.find(lower, "supply cache", 1, true) or string.find(lower, "hidden stash", 1, true) then
        local count = string.match(body, "Cache prepared:[^,]+,%s*(%d+)%s+items")
        local tier = string.match(body, "Cache prepared:%s*([^,%.]+)")
        if count and tier then
            return "[" .. sourceEn .. "][CACHE][" .. meta.tag .. "] Supply cache prepared: " .. bric_trim(tier) .. ", " .. tostring(count) .. " item(s). Search the marked existing container. / " .. bric_ru(bric_key("RadioTopic_CachePrepared"), "[%1][SKHRON][%2] skhron podgotovlen: %3, predmetov: %4. Ishchi otmechennyy konteyner.", sourceRu, bric_ruSide(meta), bric_trim(tier), tostring(count))
        end
        if string.find(lower, "cache lead was old", 1, true) then
            return "[" .. sourceEn .. "][CACHE][" .. meta.tag .. "] Old supply cache lead; marker points to an existing container, but reward loot was not confirmed. / " .. bric_ru(bric_key("RadioTopic_CacheOld"), "[%1][SKHRON][%2] staryy signal skhrona; marker vedet k konteyneru, no prizovyy lut ne podtverzhden.", sourceRu, bric_ruSide(meta))
        end
        return "[" .. sourceEn .. "][CACHE][" .. meta.tag .. "] Hidden supply cache lead detected; check the marked existing container. / " .. bric_ru(bric_key("RadioTopic_Cache"), "[%1][SKHRON][%2] poymana zatsepka na skhron; prover otmechennyy konteyner.", sourceRu, bric_ruSide(meta))
    end

    if string.find(lower, "base transmission", 1, true) then
        return "[" .. sourceEn .. "][BASE][" .. meta.tag .. "] Base radio traffic detected; check the map marker for the base area. / " .. bric_ru(bric_key("RadioTopic_Base"), "[%1][BAZA][%2] poyman radioobmen bazy; smotri marker rayona bazy na karte", sourceRu, bric_ruSide(meta))
    end

    if string.find(lower, "convoy", 1, true) then
        return "[" .. sourceEn .. "][CONVOY][" .. meta.tag .. "] Convoy traffic detected; marker shows a moving or recent route lead. / " .. bric_ru(bric_key("RadioTopic_Convoy"), "[%1][KONVOY][%2] poyman obmen konvoya; marker pokazyvaet marshrut ili nedavniy sled", sourceRu, bric_ruSide(meta))
    end

    if string.find(lower, "checkpoint", 1, true) then
        return "[" .. sourceEn .. "][CHECKPOINT][" .. meta.tag .. "] Checkpoint traffic detected; expect guards or controlled access nearby. / " .. bric_ru(bric_key("RadioTopic_Checkpoint"), "[%1][KPP][%2] poyman obmen KPP; ryadom vozmozhna okhrana ili kontrol prokhoda", sourceRu, bric_ruSide(meta))
    end

    if string.find(lower, "spy relay", 1, true) then
        if string.find(lower, "compromised", 1, true) then
            return "[" .. sourceEn .. "][SPY][" .. meta.tag .. "] Compromised spy relay; treat this intel as suspicious. / " .. bric_ru(bric_key("RadioTopic_SpyCompromised"), "[%1][SHPION][%2] skomprometirovannyy kanal shpiona; svedeniya podozritelnye", sourceRu, bric_ruSide(meta))
        end
        return "[" .. sourceEn .. "][SPY][" .. meta.tag .. "] Spy relay intel received; check the map marker and verify on site. / " .. bric_ru(bric_key("RadioTopic_Spy"), "[%1][SHPION][%2] polucheny dannye shpiona; prover marker na karte i podtverzhday na meste", sourceRu, bric_ruSide(meta))
    end

    if string.find(lower, "bounty", 1, true) or string.find(lower, "wanted", 1, true) then
        return "[" .. sourceEn .. "][BOUNTY][" .. meta.tag .. "] Bounty broadcast intercepted; the marked grid is the last known area. / " .. bric_ru(bric_key("RadioTopic_Bounty"), "[%1][NAGRADA][%2] perekhvachena okhotnichya svodka; otmechennaya zona - poslednee izvestnoe mesto", sourceRu, bric_ruSide(meta))
    end

    if string.find(lower, "signal may be old", 1, true) or string.find(lower, "breaks before confirmation", 1, true) then
        return "[" .. sourceEn .. "][UNRELIABLE][" .. meta.tag .. "] Partial or stale traffic; use the marker only as a hint. / " .. bric_ru(bric_key("RadioTopic_Unreliable"), "[%1][NENADEZHNO][%2] nepolnyy ili ustarevshiy obmen; marker tolko kak podskazka", sourceRu, bric_ruSide(meta))
    end

    return "[" .. sourceEn .. "][INTEL][" .. meta.tag .. "] Readable faction traffic received; check map markers for action. / " .. bric_ru(bric_key("RadioTopic_Intel"), "[%1][RAZVEDKA][%2] poluchen chitaemyy perekhvat fraktsii; dlya deystviy smotri markery na karte", sourceRu, bric_ruSide(meta))
end

local function bric_scanResultLines(text)
    text = tostring(text or "")
    local isMonitor = false
    local freq, signal, noise, lock, body = string.match(text, "^Radio%s+([%d%.]+)%s+MHz%s+S(%d+)%s+N(%d+)%s+L(%d+):%s*(.*)$")
    if not freq then
        freq, signal, noise, lock, body = string.match(text, "^Radio monitor%s+([%d%.]+)%s+MHz%s+S(%d+)%s+N(%d+)%s+L(%d+):%s*(.*)$")
        isMonitor = freq ~= nil
    end
    if not freq then return nil end

    freq = tonumber(freq)
    signal = tonumber(signal)
    noise = tonumber(noise)
    lock = tonumber(lock)
    body = bric_trim(body or "")

    local side = bric_sideFromText(body, freq)
    local lines = {}
    lines[#lines + 1] = bric_interceptTopicLine(body, side, freq, isMonitor)

    local sig = bric_signalLine(signal, noise, lock)
    if sig then lines[#lines + 1] = sig end

    local map = bric_mapLine(body, side)
    if map then lines[#lines + 1] = map end

    local warn = bric_counterIntelLine(body)
    if warn then lines[#lines + 1] = warn end

    return lines
end

local function bric_receiverLines(text)
    text = tostring(text or "")
    local lines = {}

    if string.find(text, "Radio requirement disabled", 1, true) then
        lines[#lines + 1] = "[STATUS] Physical radio requirement disabled; intercept tools are available without a radio item. / " .. bric_ru(bric_key("RadioStatus_ReqDisabled"), "[STATUS] Trebovanie fizicheskoy ratsii otklyucheno; perekhvat dostupen bez predmeta-ratsii")
    elseif string.find(text, "Radio ready", 1, true) then
        lines[#lines + 1] = "[STATUS] Radio device is ready. / " .. bric_ru(bric_key("RadioStatus_Ready"), "[STATUS] Radioustroystvo gotovo")
    elseif string.find(text, "Radio is off", 1, true) then
        lines[#lines + 1] = "[STATUS] Radio is off or has no power. / " .. bric_ru(bric_key("RadioStatus_Off"), "[STATUS] Radio vyklyucheno ili bez pitaniya")
    end

    if string.find(text, "Radio monitor enabled", 1, true) then
        lines[#lines + 1] = "[MONITOR] Passive monitoring enabled; it will listen automatically, but increases exposure over time. / " .. bric_ru(bric_key("RadioMonitor_Enabled"), "[MONITORING] Passivnyy monitoring vklyuchen; on slushaet avtomaticheski, no so vremenem povyshaet risk obnaruzheniya")
    elseif string.find(text, "Radio monitor disabled", 1, true) then
        lines[#lines + 1] = "[MONITOR] Passive monitoring disabled. / " .. bric_ru(bric_key("RadioMonitor_Disabled"), "[MONITORING] Passivnyy monitoring vyklyuchen")
    end

    local freq = bric_num(text, "Receiver%s+([%d%.]+)%s*MHz")
    if freq then
        local side = bric_sideFromFrequency(freq)
        local meta = bric_sideMetaFor(side)
        local gain = bric_num(text, "gain%s+(%d+)")
        local squelch = bric_num(text, "squelch%s+(%d+)")
        local filter = string.match(text, "filter%s+(%a+)") or "?"
        local monitor = string.match(text, "monitor%s+(ON)") or string.match(text, "monitor%s+(OFF)") or "?"
        local nextMin = bric_num(text, "next%s+(%d+)m")

        local en = "[RECEIVER][" .. meta.tag .. "] " .. string.format("%.2f MHz", freq) .. ": monitor " .. tostring(monitor) .. ", gain " .. tostring(gain or "?") .. ", squelch " .. tostring(squelch or "?") .. ", filter " .. tostring(filter)
        if nextMin then en = en .. ", next passive check in " .. tostring(nextMin) .. " min" end
        local ru = bric_ru(bric_key("RadioReceiver_Status"), "[PRIEMNIK][%1] %2 MHz: monitoring %3, usilenie %4, shumoporog %5, filtr %6", bric_ruSide(meta), string.format("%.2f", freq), bric_onOffRu(monitor), tostring(gain or "?"), tostring(squelch or "?"), bric_filterRu(filter))
        if nextMin then ru = ru .. ", " .. bric_ru(bric_key("RadioReceiver_Next"), "sleduyushchiy passivnyy skan cherez %1 min", tostring(nextMin)) end
        lines[#lines + 1] = en .. ". / " .. ru .. "."

        local s = bric_num(text, "last%s+S(%d+)")
        local n = bric_num(text, "last%s+S%d+%s+N(%d+)")
        local l = bric_num(text, "last%s+S%d+%s+N%d+%s+L(%d+)")
        local sig = bric_signalLine(s, n, l)
        if sig then lines[#lines + 1] = sig end
    end

    local warn = bric_counterIntelLine(text)
    if warn then lines[#lines + 1] = warn end

    local silence = bric_radioSilenceLine(text)
    if silence then lines[#lines + 1] = silence end

    if #lines > 0 then return lines end
    return nil
end

local function bric_summaryLines(text)
    text = tostring(text or "")
    local freq = bric_num(text, "Radio summary:%s+([%d%.]+)%s*MHz")
    local monitor = string.match(text, "monitor%s+(ON)") or string.match(text, "monitor%s+(OFF)") or "?"
    local history = bric_num(text, "history%s+(%d+)")
    local events = bric_num(text, "events%s+(%d+)")
    local markers = bric_num(text, "markers%s+(%d+)")
    local s = bric_num(text, "S(%d+)")
    local n = bric_num(text, "S%d+%s+N(%d+)")
    local l = bric_num(text, "S%d+%s+N%d+%s+L(%d+)")

    local lines = {}
    local ruFreq = tostring(freq and string.format("%.2f MHz", freq) or bric_ru(bric_key("RadioFreq_Unknown"), "chastota neizvestna"))
    lines[#lines + 1] = "[SUMMARY] " .. tostring(freq and string.format("%.2f MHz", freq) or "unknown frequency") .. ": monitor " .. tostring(monitor) .. ", history " .. tostring(history or 0) .. ", events " .. tostring(events or 0) .. ", map markers " .. tostring(markers or 0) .. ". / " .. bric_ru(bric_key("RadioSummary_Line"), "[SVODKA] %1: monitoring %2, istoriya %3, sobytiya %4, markery karty %5.", ruFreq, bric_onOffRu(monitor), tostring(history or 0), tostring(events or 0), tostring(markers or 0))

    local sig = bric_signalLine(s, n, l)
    if sig then lines[#lines + 1] = sig end

    local silence = bric_radioSilenceLine(text)
    if silence then lines[#lines + 1] = silence end

    return lines
end

local function bric_decoderLines(text)
    text = tostring(text or "")
    local body = bric_trim(string.gsub(text, "^Radio decoder:%s*", ""))
    return {"[DECODER] " .. body .. ". / " .. bric_ru(bric_key("RadioDecoder_Line"), "[DEKODER] status dekodera: %1.", body)}
end

local function bric_historyLines(text)
    text = tostring(text or "")
    local count = 0
    for _ in string.gmatch(text, "%d+%)%s*%[") do count = count + 1 end
    if count <= 0 and string.find(text, "No radio intercepts stored", 1, true) then
        return {"[HISTORY] No stored intercepts yet. / " .. bric_ru(bric_key("RadioHistory_Empty"), "[ISTORIYA] Sokhranennykh perekhvatov poka net")}
    end
    if count <= 0 then count = 1 end

    local lines = {}
    lines[#lines + 1] = "[HISTORY] " .. tostring(count) .. " stored intercept(s). Newest entries are first; match faction color and marker names on the map. / " .. bric_ru(bric_key("RadioHistory_Count"), "[ISTORIYA] sokhraneno perekhvatov: %1. Novye zapisi idut pervymi; sveryay tsvet fraktsii i nazvaniya markerov na karte.", tostring(count))

    local x, y = string.match(text, "near%s+(%d+),(%d+)")
    if x and y then
        lines[#lines + 1] = "[MAP] History mentions grid " .. tostring(x) .. "," .. tostring(y) .. "; use it as an old lead unless a fresh marker exists. / " .. bric_ru(bric_key("RadioHistory_Grid"), "[KARTA] v istorii est setka %1,%2; eto staraya zatsepka, esli net svezhego markera.", tostring(x), tostring(y))
    end

    return lines
end

local function bric_cooldownLines(text)
    local minutes = bric_num(text, "cooldown:%s+(%d+)%s+min") or bric_num(text, "cooldown%s+(%d+)%s+min")
    if minutes then
        return {"[SCAN WAIT] Scanner cooldown " .. tostring(minutes) .. " min. Use receiver status or map while waiting. / " .. bric_ru(bric_key("RadioScanWait"), "[OZHIDANIE] perezaryadka skanera %1 min. Poka zhdi, smotri status priemnika ili kartu.", tostring(minutes))}
    end
    return nil
end

local function bric_simpleLines(text)
    text = tostring(text or "")
    local minutes = bric_num(text, "Radio silence active:%s+(%d+)%s+min")
    if minutes then
        return {"[RADIO SILENCE] Active for " .. tostring(minutes) .. " more min; scans are blocked but exposure is safer. / " .. bric_ru(bric_key("RadioSilence_Timer"), "[RADIOMOLCHANIE] aktivno eshche %1 min; skany zablokirovany, no risk nizhe.", tostring(minutes))}
    end

    minutes = bric_num(text, "Duration%s+(%d+)%s+min")
    if string.find(text, "Radio silence enabled", 1, true) then
        local extra = minutes and (" Duration " .. tostring(minutes) .. " min.") or ""
        return {"[RADIO SILENCE] Enabled." .. extra .. " Passive monitoring stopped and heat reduced. / " .. bric_ru(bric_key("RadioSilence_Enabled"), "[RADIOMOLCHANIE] vklyucheno.%1 Passivnyy monitoring ostanovlen, nagrev snizhen.", minutes and (" " .. bric_ru(bric_key("RadioDuration"), "Dlitelnost %1 min.", tostring(minutes))) or "")}
    end
    if string.find(text, "Radio silence disabled", 1, true) then
        return {"[RADIO SILENCE] Disabled; normal radio activity restored. / " .. bric_ru(bric_key("RadioSilence_Disabled"), "[RADIOMOLCHANIE] vyklyucheno; obychnaya radiorabota vosstanovlena")}
    end
    if string.find(text, "Radio intercept history cleared", 1, true) then
        return {"[HISTORY] Radio intercept history cleared. / " .. bric_ru(bric_key("RadioHistory_Cleared"), "[ISTORIYA] Istoriya radioperekhvatov ochishchena")}
    end
    if string.find(text, "No radio or walkie-talkie found", 1, true) or string.find(text, "You need a radio", 1, true) then
        return {"[RADIO] You need a radio or walkie-talkie to intercept traffic. / " .. bric_ru(bric_key("RadioNeedItem"), "[RADIO] Dlya perekhvata nuzhna ratsiya ili walkie-talkie")}
    end
    if string.find(text, "Radio must be turned on", 1, true) then
        return {"[RADIO] Turn on and power the radio before scanning. / " .. bric_ru(bric_key("RadioNeedPower"), "[RADIO] Vklyuchi i zapitay radio pered skanirovaniem")}
    end
    if string.find(text, "unavailable", 1, true) then
        return {"[RADIO] Radio function unavailable right now. / " .. bric_ru(bric_key("RadioUnavailable"), "[RADIO] Radiofunktsiya seychas nedostupna")}
    end

    return nil
end

local function bric_buildDisplayLines(text)
    local raw = bric_trim(text)
    if raw == "" then return {"[NOTICE] Empty radio message. / " .. bric_ru(bric_key("RadioNotice_Empty"), "[SOOBSHCHENIE] Pustoe radiosoobshchenie")} end

    local lines = nil

    if string.find(raw, "^Radio%s+[%d%.]+%s+MHz%s+S%d+%s+N%d+%s+L%d+:") or string.find(raw, "^Radio monitor%s+[%d%.]+%s+MHz%s+S%d+%s+N%d+%s+L%d+:") then
        lines = bric_scanResultLines(raw)
    elseif string.find(raw, "^Radio summary:") then
        lines = bric_summaryLines(raw)
    elseif string.find(raw, "^Radio decoder:") then
        lines = bric_decoderLines(raw)
    elseif string.find(raw, "^%d+%)%s*%[") or string.find(raw, "No radio intercepts stored", 1, true) then
        lines = bric_historyLines(raw)
    elseif string.find(raw, "Receiver%s+[%d%.]+%s*MHz") or string.find(raw, "Radio monitor enabled", 1, true) or string.find(raw, "Radio monitor disabled", 1, true) or string.find(raw, "Radio requirement disabled", 1, true) or string.find(raw, "Radio ready", 1, true) or string.find(raw, "Radio is off", 1, true) then
        lines = bric_receiverLines(raw)
    elseif string.find(raw, "Radio scan cooldown", 1, true) then
        lines = bric_cooldownLines(raw)
    else
        lines = bric_simpleLines(raw)
    end

    if type(lines) == "table" and #lines > 0 then return lines end
    return {"[NOTICE] Unrecognized radio packet received; raw details were kept in the console log. / " .. bric_ru(bric_key("RadioNotice_Unrecognized"), "[SOOBSHCHENIE] Poluchen neraspoznannyy radiopaket; syrye detali ostavleny tolko v konsoli")}
end

local function bric_haloPreview(text)
    local lines = bric_buildDisplayLines(text)
    if type(lines) ~= "table" or not lines[1] then return tostring(text or "") end
    local value = bric_applyLanguage(tostring(lines[1]))
    value = string.gsub(value, "%[SIGNAL%].*$", "")
    value = string.gsub(value, "%s+/%s+", " / ")
    return bric_short(bric_trim(value), 180)
end

local function bric_chat(text)
    if not text then return false end
    local lines = bric_buildDisplayLines(text)
    local shown = false
    for _, value in ipairs(lines) do
        if bric_tryISChat("[Radio] " .. bric_applyLanguage(value)) then shown = true end
    end
    bric_console(text)
    return shown
end

local function bric_halo(text, r, g, b)
    local player = bric_player()
    if HaloTextHelper and player and text then
        HaloTextHelper.addText(player, bric_haloPreview(text), r or 180, g or 230, b or 255)
    end
    bric_chat(text)
end

function NPCRadioInterceptClientBridge.Scan(player)
    player = player or bric_player()
    if not player then return end
    sendClientCommand(player, 'NPCRadioIntercept', 'Scan', {})
end

function NPCRadioInterceptClientBridge.TuneScan(player, side)
    player = player or bric_player()
    if not player then return end
    local args = {}
    if side then
        args.side = tostring(side)
        if NPCRadioInterceptBridge and NPCRadioInterceptBridge.SideFrequency then
            args.frequency = NPCRadioInterceptBridge.SideFrequency(side)
        end
    end
    sendClientCommand(player, 'NPCRadioIntercept', 'TuneScan', args)
end

function NPCRadioInterceptClientBridge.Status(player)
    player = player or bric_player()
    if not player then return end
    sendClientCommand(player, 'NPCRadioIntercept', 'Status', {})
end

function NPCRadioInterceptClientBridge.History(player)
    player = player or bric_player()
    if not player then return end
    sendClientCommand(player, 'NPCRadioIntercept', 'History', {})
end

function NPCRadioInterceptClientBridge.Summary(player)
    player = player or bric_player()
    if not player then return end
    sendClientCommand(player, 'NPCRadioIntercept', 'Summary', {})
end

function NPCRadioInterceptClientBridge.ClearHistory(player)
    player = player or bric_player()
    if not player then return end
    sendClientCommand(player, 'NPCRadioIntercept', 'ClearHistory', {})
end

function NPCRadioInterceptClientBridge.RadioSilence(player, enabled)
    player = player or bric_player()
    if not player then return end
    sendClientCommand(player, 'NPCRadioIntercept', 'RadioSilence', {enabled=enabled == true})
end

function NPCRadioInterceptClientBridge.ReceiverStatus(player)
    player = player or bric_player()
    if not player then return end
    sendClientCommand(player, 'NPCRadioIntercept', 'ReceiverStatus', {})
end

function NPCRadioInterceptClientBridge.DecoderStatus(player)
    player = player or bric_player()
    if not player then return end
    sendClientCommand(player, 'NPCRadioIntercept', 'DecoderStatus', {})
end

function NPCRadioInterceptClientBridge.ReceiverScan(player)
    player = player or bric_player()
    if not player then return end
    sendClientCommand(player, 'NPCRadioIntercept', 'ReceiverScan', {})
end

function NPCRadioInterceptClientBridge.ReceiverAdjust(player, action, value)
    player = player or bric_player()
    if not player then return end
    sendClientCommand(player, 'NPCRadioIntercept', 'ReceiverAdjust', {action=action, value=value})
end

function NPCRadioInterceptClientBridge.ReceiverMonitor(player, enabled)
    player = player or bric_player()
    if not player then return end
    sendClientCommand(player, 'NPCRadioIntercept', 'ReceiverMonitor', {enabled=enabled == true})
end

function NPCRadioInterceptClientBridge.OnFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    if test or not bric_bool("RadioIntercept_Enabled", true) then return end
    local player = getSpecificPlayer(playerNum) or bric_player()
    if not player then return end

    local root = context:addOption(getText(bric_key("Menu_RadioIntercept")))
    local menu = context:getNew(context)
    context:addSubMenu(root, menu)
    menu:addOption(getText(bric_key("Menu_RadioStatus")), player, NPCRadioInterceptClientBridge.Status)
    menu:addOption(getText(bric_key("Menu_RadioSummary")), player, NPCRadioInterceptClientBridge.Summary)
    menu:addOption(getText(bric_key("Menu_ScanTunedRadio")), player, NPCRadioInterceptClientBridge.TuneScan, nil)

    local receiver = menu:addOption(getText(bric_key("Menu_RadioReceiverControls")))
    local receiverMenu = context:getNew(context)
    context:addSubMenu(receiver, receiverMenu)
    receiverMenu:addOption(getText(bric_key("Menu_ReceiverStatus")), player, NPCRadioInterceptClientBridge.ReceiverStatus)
    receiverMenu:addOption(getText(bric_key("Menu_ReceiverDecoderStatus")), player, NPCRadioInterceptClientBridge.DecoderStatus)
    receiverMenu:addOption(getText(bric_key("Menu_ReceiverScan")), player, NPCRadioInterceptClientBridge.ReceiverScan)
    receiverMenu:addOption(getText(bric_key("Menu_ReceiverMonitorStart")), player, NPCRadioInterceptClientBridge.ReceiverMonitor, true)
    receiverMenu:addOption(getText(bric_key("Menu_ReceiverMonitorStop")), player, NPCRadioInterceptClientBridge.ReceiverMonitor, false)
    receiverMenu:addOption(getText(bric_key("Menu_RadioSilenceStart")), player, NPCRadioInterceptClientBridge.RadioSilence, true)
    receiverMenu:addOption(getText(bric_key("Menu_RadioSilenceStop")), player, NPCRadioInterceptClientBridge.RadioSilence, false)

    local tune = receiverMenu:addOption(getText(bric_key("Menu_ReceiverTune")))
    local tuneMenu = context:getNew(context)
    context:addSubMenu(tune, tuneMenu)
    tuneMenu:addOption("+1.00 MHz", player, NPCRadioInterceptClientBridge.ReceiverAdjust, "freqDelta", 1.00)
    tuneMenu:addOption("+0.10 MHz", player, NPCRadioInterceptClientBridge.ReceiverAdjust, "freqDelta", 0.10)
    tuneMenu:addOption("+0.01 MHz", player, NPCRadioInterceptClientBridge.ReceiverAdjust, "freqDelta", 0.01)
    tuneMenu:addOption("-0.01 MHz", player, NPCRadioInterceptClientBridge.ReceiverAdjust, "freqDelta", -0.01)
    tuneMenu:addOption("-0.10 MHz", player, NPCRadioInterceptClientBridge.ReceiverAdjust, "freqDelta", -0.10)
    tuneMenu:addOption("-1.00 MHz", player, NPCRadioInterceptClientBridge.ReceiverAdjust, "freqDelta", -1.00)

    local presets = receiverMenu:addOption(getText(bric_key("Menu_ReceiverPresets")))
    local presetsMenu = context:getNew(context)
    context:addSubMenu(presets, presetsMenu)
    presetsMenu:addOption(getText(bric_key("Menu_ScanRedBand")), player, NPCRadioInterceptClientBridge.ReceiverAdjust, "side", "red")
    presetsMenu:addOption(getText(bric_key("Menu_ScanGreenBand")), player, NPCRadioInterceptClientBridge.ReceiverAdjust, "side", "green")
    presetsMenu:addOption(getText(bric_key("Menu_ScanBlueBand")), player, NPCRadioInterceptClientBridge.ReceiverAdjust, "side", "blue")
    presetsMenu:addOption(getText(bric_key("Menu_ScanBlackBand")), player, NPCRadioInterceptClientBridge.ReceiverAdjust, "side", "black")

    local gain = receiverMenu:addOption(getText(bric_key("Menu_ReceiverGain")))
    local gainMenu = context:getNew(context)
    context:addSubMenu(gain, gainMenu)
    gainMenu:addOption("+10", player, NPCRadioInterceptClientBridge.ReceiverAdjust, "gainDelta", 10)
    gainMenu:addOption("-10", player, NPCRadioInterceptClientBridge.ReceiverAdjust, "gainDelta", -10)

    local squelch = receiverMenu:addOption(getText(bric_key("Menu_ReceiverSquelch")))
    local squelchMenu = context:getNew(context)
    context:addSubMenu(squelch, squelchMenu)
    squelchMenu:addOption("+10", player, NPCRadioInterceptClientBridge.ReceiverAdjust, "squelchDelta", 10)
    squelchMenu:addOption("-10", player, NPCRadioInterceptClientBridge.ReceiverAdjust, "squelchDelta", -10)

    local filter = receiverMenu:addOption(getText(bric_key("Menu_ReceiverFilter")))
    local filterMenu = context:getNew(context)
    context:addSubMenu(filter, filterMenu)
    filterMenu:addOption(getText(bric_key("Menu_ReceiverFilterWide")), player, NPCRadioInterceptClientBridge.ReceiverAdjust, "setFilter", "wide")
    filterMenu:addOption(getText(bric_key("Menu_ReceiverFilterNarrow")), player, NPCRadioInterceptClientBridge.ReceiverAdjust, "setFilter", "narrow")
    receiverMenu:addOption(getText(bric_key("Menu_ReceiverReset")), player, NPCRadioInterceptClientBridge.ReceiverAdjust, "reset", true)

    local band = menu:addOption(getText(bric_key("Menu_ScanFactionFrequencies")))
    local bandMenu = context:getNew(context)
    context:addSubMenu(band, bandMenu)
    bandMenu:addOption(getText(bric_key("Menu_ScanRedBand")), player, NPCRadioInterceptClientBridge.TuneScan, "red")
    bandMenu:addOption(getText(bric_key("Menu_ScanGreenBand")), player, NPCRadioInterceptClientBridge.TuneScan, "green")
    bandMenu:addOption(getText(bric_key("Menu_ScanBlueBand")), player, NPCRadioInterceptClientBridge.TuneScan, "blue")
    bandMenu:addOption(getText(bric_key("Menu_ScanBlackBand")), player, NPCRadioInterceptClientBridge.TuneScan, "black")

    menu:addOption(getText(bric_key("Menu_LegacyWideScan")), player, NPCRadioInterceptClientBridge.Scan)
    menu:addOption(getText(bric_key("Menu_KnownIntercepts")), player, NPCRadioInterceptClientBridge.History)
    menu:addOption(getText(bric_key("Menu_ClearIntercepts")), player, NPCRadioInterceptClientBridge.ClearHistory)
end

function NPCRadioInterceptClientBridge.OnServerCommand(module, command, args)
    if not NPCLegacyContractBridge.IsModule(module, "NPCRadioIntercept", "radioIntercept") then return end
    if command == "Result" and args and args.text then
        bric_halo(args.text, args.r, args.g, args.b)
    end
end

Events.OnFillWorldObjectContextMenu.Add(NPCRadioInterceptClientBridge.OnFillWorldObjectContextMenu)
Events.OnServerCommand.Add(NPCRadioInterceptClientBridge.OnServerCommand)
