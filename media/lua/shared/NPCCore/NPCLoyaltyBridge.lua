-- NPCLoyaltyBridge.lua
-- Neutral shared backend for mercenary loyalty state and marker fields.

require "NPCCore/NPCLegacyGlobalsBridge"
require "NPCCore/NPCLegacyContractBridge"

NPCLoyaltyBridge = NPCLoyaltyBridge or {}
NPCLoyaltyBridge.Version = 1
local function bl_mercenaryProvider()
    return NPCMercenaryContract or NPCLegacyGlobalsBridge.Get("Mercenary") or nil
end

local function bl_setting(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.Get then
        return NPCLegacySettingsBridge.Get(name, defaultValue)
    end
    local vars = SandboxVars and SandboxVars[NPCLegacyContractBridge.Sandbox.ext] or nil
    if vars and vars[name] ~= nil then return vars[name] end
    return defaultValue
end

local function bl_bool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        return NPCLegacySettingsBridge.GetBool(name, defaultValue == true)
    end
    local value = bl_setting(name, defaultValue)
    if value == true or value == 1 or value == "true" then return true end
    if value == false or value == 0 or value == "false" then return false end
    return defaultValue == true
end

local function bl_num(name, defaultValue, minValue, maxValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then
        return NPCLegacySettingsBridge.GetNumber(name, defaultValue, minValue, maxValue)
    end
    local value = tonumber(bl_setting(name, defaultValue)) or tonumber(defaultValue) or 0
    if minValue ~= nil and value < minValue then value = minValue end
    if maxValue ~= nil and value > maxValue then value = maxValue end
    return value
end

local function bl_clamp(value, minValue, maxValue)
    value = tonumber(value) or 0
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function bl_copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = bl_copy(v) end
    return out
end

function NPCLoyaltyBridge.IsEnabled()
    return bl_bool("Loyalty_Enabled", true)
end

function NPCLoyaltyBridge.Initial()
    return bl_num("Loyalty_Initial", 55, 0, 100)
end

function NPCLoyaltyBridge.Max()
    return bl_num("Loyalty_Max", 100, 1, 100)
end

function NPCLoyaltyBridge.Min()
    return bl_num("Loyalty_Min", 0, 0, 99)
end

function NPCLoyaltyBridge.HireBonus()
    return bl_num("Loyalty_HireBonus", 6, -100, 100)
end

function NPCLoyaltyBridge.StabilizeBonus()
    return bl_num("Loyalty_StabilizeBonus", 12, -100, 100)
end

function NPCLoyaltyBridge.EvacuateBonus()
    return bl_num("Loyalty_EvacuateBonus", 8, -100, 100)
end

function NPCLoyaltyBridge.AbandonPenalty()
    return bl_num("Loyalty_AbandonPenalty", -30, -100, 0)
end

function NPCLoyaltyBridge.AbandonWitnessPenalty()
    return bl_num("Loyalty_AbandonWitnessPenalty", -12, -100, 0)
end

function NPCLoyaltyBridge.WoundedPenalty()
    return bl_num("Loyalty_WoundedPenalty", -3, -100, 0)
end

function NPCLoyaltyBridge.CommandPenalty()
    return bl_num("Loyalty_CommandPenalty", -0.25, -20, 20)
end

function NPCLoyaltyBridge.NowHours()
    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then return gt:getWorldAgeHours() end
    end
    return 0
end

function NPCLoyaltyBridge.PlayerId(player)
    if not player then return nil end
    if NPCUtils and NPCUtils.GetCharacterID then
        local ok, id = pcall(function() return NPCUtils.GetCharacterID(player) end)
        if ok and id ~= nil then return id end
    end
    if player.getOnlineID then
        local ok, id = pcall(function() return player:getOnlineID() end)
        if ok and id ~= nil then return id end
    end
    if player.getUsername then
        local ok, name = pcall(function() return player:getUsername() end)
        if ok and name then return name end
    end
    return nil
end

function NPCLoyaltyBridge.PlayerName(player)
    if not player then return nil end
    if player.getUsername then
        local ok, name = pcall(function() return player:getUsername() end)
        if ok and name then return name end
    end
    if player.getDisplayName then
        local ok, name = pcall(function() return player:getDisplayName() end)
        if ok and name then return name end
    end
    return tostring(NPCLoyaltyBridge.PlayerId(player) or "player")
end

function NPCLoyaltyBridge.State(value)
    value = tonumber(value) or NPCLoyaltyBridge.Initial()
    if value >= 82 then return "devoted" end
    if value >= 66 then return "loyal" end
    if value >= 45 then return "steady" end
    if value >= 25 then return "shaky" end
    return "resentful"
end

function NPCLoyaltyBridge.IsHiredBy(brain, player)
    if not brain then return false end
    local mercenaryProvider = bl_mercenaryProvider()
    if mercenaryProvider and mercenaryProvider.IsHiredBy then
        local ok, result = pcall(function() return mercenaryProvider.IsHiredBy(brain, player) end)
        if ok and result == true then return true end
    end
    local pid = NPCLoyaltyBridge.PlayerId(player)
    if not pid then return false end
    return brain.mercenaryHired == true and tostring(brain.mercenaryHiredBy or brain.master or "") == tostring(pid)
end

function NPCLoyaltyBridge.EnsureBrain(brain, player)
    if not (NPCLoyaltyBridge.IsEnabled() and type(brain) == "table") then return brain end
    local pid = NPCLoyaltyBridge.PlayerId(player) or brain.mercenaryHiredBy or brain.master
    if not pid then return brain end

    brain.mercenaryLoyalty = bl_clamp(brain.mercenaryLoyalty or NPCLoyaltyBridge.Initial(), NPCLoyaltyBridge.Min(), NPCLoyaltyBridge.Max())
    brain.loyalty = true
    brain.loyaltyForPlayerId = brain.loyaltyForPlayerId or pid
    brain.loyaltyForPlayerName = brain.loyaltyForPlayerName or NPCLoyaltyBridge.PlayerName(player) or brain.mercenaryHiredByName
    brain.loyaltyState = NPCLoyaltyBridge.State(brain.mercenaryLoyalty)
    brain.loyaltyUpdatedAt = NPCLoyaltyBridge.NowHours()
    brain.loyaltyEvents = tonumber(brain.loyaltyEvents) or 0
    return brain
end

function NPCLoyaltyBridge.ApplyBrainModifiers(brain)
    if not (NPCLoyaltyBridge.IsEnabled() and type(brain) == "table" and brain.mercenaryLoyalty) then return brain end
    local value = tonumber(brain.mercenaryLoyalty) or NPCLoyaltyBridge.Initial()
    if value >= 80 then
        brain.morale = math.max(tonumber(brain.morale) or 0, 0.90)
        brain.discipline = math.max(tonumber(brain.discipline) or 0, 0.86)
        brain.fear = math.min(tonumber(brain.fear) or 1, 0.18)
    elseif value >= 65 then
        brain.morale = math.max(tonumber(brain.morale) or 0, 0.78)
        brain.discipline = math.max(tonumber(brain.discipline) or 0, 0.74)
        brain.fear = math.min(tonumber(brain.fear) or 1, 0.32)
    elseif value < 25 then
        brain.morale = math.min(tonumber(brain.morale) or 0.45, 0.42)
        brain.discipline = math.min(tonumber(brain.discipline) or 0.45, 0.40)
        brain.fear = math.max(tonumber(brain.fear) or 0, 0.62)
    elseif value < 45 then
        brain.morale = math.min(tonumber(brain.morale) or 0.55, 0.58)
        brain.discipline = math.min(tonumber(brain.discipline) or 0.55, 0.58)
        brain.fear = math.max(tonumber(brain.fear) or 0, 0.42)
    end
    return brain
end

function NPCLoyaltyBridge.Add(brain, player, amount, reason)
    if not (NPCLoyaltyBridge.IsEnabled() and type(brain) == "table") then return brain end
    NPCLoyaltyBridge.EnsureBrain(brain, player)
    local before = tonumber(brain.mercenaryLoyalty) or NPCLoyaltyBridge.Initial()
    local after = bl_clamp(before + (tonumber(amount) or 0), NPCLoyaltyBridge.Min(), NPCLoyaltyBridge.Max())
    brain.mercenaryLoyalty = after
    brain.loyaltyState = NPCLoyaltyBridge.State(after)
    brain.loyaltyReason = reason or brain.loyaltyReason
    brain.loyaltyUpdatedAt = NPCLoyaltyBridge.NowHours()
    brain.loyaltyEvents = (tonumber(brain.loyaltyEvents) or 0) + 1
    brain.lastLoyaltyDelta = after - before
    brain.lastLoyaltyReason = reason
    NPCLoyaltyBridge.ApplyBrainModifiers(brain)
    return brain
end

function NPCLoyaltyBridge.OnHired(brain, player)
    if not (NPCLoyaltyBridge.IsEnabled() and type(brain) == "table") then return brain end
    NPCLoyaltyBridge.EnsureBrain(brain, player)
    if not brain.loyaltyHiredAt then
        brain.loyaltyHiredAt = NPCLoyaltyBridge.NowHours()
        NPCLoyaltyBridge.Add(brain, player, NPCLoyaltyBridge.HireBonus(), "hired")
    end
    return brain
end

function NPCLoyaltyBridge.OnOrder(brain, player, data)
    if not (NPCLoyaltyBridge.IsEnabled() and type(brain) == "table") then return brain end
    NPCLoyaltyBridge.EnsureBrain(brain, player)
    local amount = NPCLoyaltyBridge.CommandPenalty()
    if data and (data.orderName == "Guard" or data.orderName == "Hold" or data.formation) then
        amount = amount * 0.5
    end
    if amount ~= 0 then NPCLoyaltyBridge.Add(brain, player, amount, "order") end
    return brain
end

function NPCLoyaltyBridge.OnWounded(brain, player)
    return NPCLoyaltyBridge.Add(brain, player, NPCLoyaltyBridge.WoundedPenalty(), "wounded")
end

function NPCLoyaltyBridge.OnStabilized(brain, player)
    return NPCLoyaltyBridge.Add(brain, player, NPCLoyaltyBridge.StabilizeBonus(), "stabilized")
end

function NPCLoyaltyBridge.OnEvacuated(brain, player)
    return NPCLoyaltyBridge.Add(brain, player, NPCLoyaltyBridge.EvacuateBonus(), "evacuated")
end

function NPCLoyaltyBridge.OnAbandoned(brain, player)
    return NPCLoyaltyBridge.Add(brain, player, NPCLoyaltyBridge.AbandonPenalty(), "abandoned")
end

function NPCLoyaltyBridge.EnsureGroup(group, player)
    if not (NPCLoyaltyBridge.IsEnabled() and type(group) == "table") then return group end
    local pid = NPCLoyaltyBridge.PlayerId(player) or group.mercenaryHiredBy or group.master
    group.loyalty = true
    group.loyaltyForPlayerId = group.loyaltyForPlayerId or pid
    group.loyaltyUpdatedAt = NPCLoyaltyBridge.NowHours()
    if type(group.members) == "table" then
        local total = 0
        local count = 0
        for _, member in pairs(group.members) do
            if type(member) == "table" then
                NPCLoyaltyBridge.EnsureBrain(member, player)
                total = total + (tonumber(member.mercenaryLoyalty) or NPCLoyaltyBridge.Initial())
                count = count + 1
            end
        end
        if count > 0 then
            group.mercenaryLoyalty = math.floor((total / count) + 0.5)
            group.loyaltyState = NPCLoyaltyBridge.State(group.mercenaryLoyalty)
        end
    else
        group.mercenaryLoyalty = group.mercenaryLoyalty or NPCLoyaltyBridge.Initial()
        group.loyaltyState = NPCLoyaltyBridge.State(group.mercenaryLoyalty)
    end
    return group
end

function NPCLoyaltyBridge.Summary(gmd, player)
    local pid = tostring(NPCLoyaltyBridge.PlayerId(player) or "")
    if pid == "" then return {count=0, average=0, loyal=0, shaky=0, resentful=0, text="No player id."} end
    local total = 0
    local count = 0
    local devoted = 0
    local loyal = 0
    local steady = 0
    local shaky = 0
    local resentful = 0
    if gmd and type(gmd.Queue) == "table" then
        for _, brain in pairs(gmd.Queue) do
            if type(brain) == "table" and brain.mercenaryHired == true and tostring(brain.mercenaryHiredBy or brain.master or "") == pid then
                NPCLoyaltyBridge.EnsureBrain(brain, player)
                local value = tonumber(brain.mercenaryLoyalty) or NPCLoyaltyBridge.Initial()
                local state = NPCLoyaltyBridge.State(value)
                total = total + value
                count = count + 1
                if state == "devoted" then devoted = devoted + 1
                elseif state == "loyal" then loyal = loyal + 1
                elseif state == "steady" then steady = steady + 1
                elseif state == "shaky" then shaky = shaky + 1
                else resentful = resentful + 1 end
            end
        end
    end
    local average = count > 0 and math.floor((total / count) + 0.5) or 0
    local text = "Mercenary loyalty: " .. tostring(count) .. " hired, avg " .. tostring(average) .. ". Devoted " .. tostring(devoted) .. ", loyal " .. tostring(loyal) .. ", steady " .. tostring(steady) .. ", shaky " .. tostring(shaky) .. ", resentful " .. tostring(resentful) .. "."
    return {count=count, average=average, devoted=devoted, loyal=loyal, steady=steady, shaky=shaky, resentful=resentful, text=text}
end

function NPCLoyaltyBridge.ApplyToHired(gmd, player, amount, reason, exceptId)
    if not (NPCLoyaltyBridge.IsEnabled() and gmd and type(gmd.Queue) == "table") then return 0 end
    local pid = tostring(NPCLoyaltyBridge.PlayerId(player) or "")
    if pid == "" then return 0 end
    local changed = 0
    for id, brain in pairs(gmd.Queue) do
        if type(brain) == "table" and tostring(id) ~= tostring(exceptId or "") and brain.mercenaryHired == true and tostring(brain.mercenaryHiredBy or brain.master or "") == pid then
            NPCLoyaltyBridge.Add(brain, player, amount, reason)
            gmd.Queue[id] = brain
            changed = changed + 1
        end
    end
    return changed
end

function NPCLoyaltyBridge.WillAcceptOrder(brain, player, data)
    if not NPCLoyaltyBridge.IsEnabled() then return true end
    if not bl_bool("Loyalty_AllowRefuseRiskyOrders", false) then return true end
    if not NPCLoyaltyBridge.IsHiredBy(brain, player) then return true end
    NPCLoyaltyBridge.EnsureBrain(brain, player)
    local value = tonumber(brain.mercenaryLoyalty) or NPCLoyaltyBridge.Initial()
    local threshold = bl_num("Loyalty_RefuseThreshold", 18, 0, 100)
    if value >= threshold then return true end
    local orderName = data and (data.orderName or data.name) or ""
    if orderName == "Follow" or orderName == "Hold" then return true end
    local chance = bl_num("Loyalty_RefuseChance", 35, 0, 100)
    local roll = ZombRand and ZombRand(100) or math.random(0, 99)
    return roll >= chance
end

function NPCLoyaltyBridge.MarkerFields(marker, brainOrGroup)
    if not (marker and type(brainOrGroup) == "table") then return marker end
    marker.loyalty = brainOrGroup.loyalty
    marker.mercenaryLoyalty = brainOrGroup.mercenaryLoyalty
    marker.loyaltyState = brainOrGroup.loyaltyState
    marker.loyaltyForPlayerId = brainOrGroup.loyaltyForPlayerId
    marker.loyaltyUpdatedAt = brainOrGroup.loyaltyUpdatedAt
    return marker
end
