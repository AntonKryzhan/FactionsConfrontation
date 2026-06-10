-- NPCContractsClientBridge.lua
-- Context menu + HUD notifications for faction contracts.

require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCLegacyGlobalsBridge"
NPCContractsClientBridge = NPCContractsClientBridge or {}

local BCC_LEGACY_TEXT_PREFIX = NPCLegacyContractBridge.Text.prefix

local function bcc_text(key)
    return getText(BCC_LEGACY_TEXT_PREFIX .. tostring(key or ""))
end
NPCContractsClientBridge.active = NPCContractsClientBridge.active or nil
NPCContractsClientBridge._syncRequested = NPCContractsClientBridge._syncRequested or false

local function bcc_baseCaptureProvider()
    return NPCBaseCaptureUIBridge or NPCBaseCaptureUI or NPCLegacyGlobalsBridge.Get("BaseCaptureUI")
end

local function bcc_settingBool(name, defaultValue)
    if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then
        local ok, value = pcall(function() return NPCLegacySettingsBridge.GetBool(name, defaultValue == true) end)
        if ok and value ~= nil then return value == true end
    end
    return defaultValue == true
end

local function bcc_dist(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return math.sqrt(dx * dx + dy * dy)
end

local function bcc_nearBase()
    local provider = bcc_baseCaptureProvider()
    if provider and provider.FindNearbyBase then
        local ok, base, dist = pcall(function() return provider.FindNearbyBase() end)
        if ok and base then return base, dist end
    end
    return nil, nil
end

local function bcc_baseId(base)
    if not base then return nil end
    return base.baseId or base.id
end

local function bcc_player()
    return getPlayer() or getSpecificPlayer(0)
end

local function bcc_halo(text, r, g, b)
    local player = bcc_player()
    if HaloTextHelper and player and text then
        HaloTextHelper.addText(player, tostring(text), r or 180, g or 230, b or 255)
    end
end

local function bcc_resourceLabel(resource, fallback)
    if resource then
        local key = BCC_LEGACY_TEXT_PREFIX .. "Menu_Resource_" .. tostring(resource)
        local label = getText(key)
        if label and label ~= key then return label end
    end
    return tostring(fallback or resource or bcc_text("Menu_Resource"))
end

local function bcc_contractText(contract)
    if not contract then return bcc_text("Menu_NoActiveContract") end
    if contract.type == "supply" then
        return bcc_text("Menu_ActiveDeliver") .. " " .. tostring(contract.deliveredAmount or 0) .. "/" .. tostring(contract.requiredAmount or 0) .. " " .. bcc_resourceLabel(contract.resource, contract.resourceLabel) .. " " .. bcc_text("Menu_To") .. " " .. tostring(contract.baseName or bcc_text("Menu_BaseLower"))
    elseif contract.type == "recon" then
        return bcc_text("Menu_ActiveScout") .. " " .. tostring(contract.targetKind or bcc_text("Menu_Target")) .. " " .. bcc_text("Menu_Near") .. " " .. tostring(contract.x or "?") .. ", " .. tostring(contract.y or "?")
    elseif contract.type == "recover" then
        return bcc_text("Menu_ActiveRecover") .. " " .. tostring(contract.targetKind or bcc_text("Menu_Target")) .. " " .. bcc_text("Menu_Near") .. " " .. tostring(contract.x or "?") .. ", " .. tostring(contract.y or "?")
    end
    return tostring(contract.text or contract.title or bcc_text("Menu_ActiveContract"))
end

local function bcc_canCompleteRecon(contract, player)
    if not contract or contract.type ~= "recon" or not player then return false end
    if not player.getX or not player.getY then return false end
    local radius = tonumber(contract.completeRadius) or 28
    return bcc_dist(player:getX(), player:getY(), contract.x, contract.y) <= radius + 4
end

local function bcc_canCompleteRecover(contract, player)
    if not contract or contract.type ~= "recover" or not player then return false end
    if not player.getX or not player.getY then return false end
    local radius = tonumber(contract.completeRadius) or 18
    return bcc_dist(player:getX(), player:getY(), contract.x, contract.y) <= radius + 4
end

function NPCContractsClientBridge.RequestContract(player, base, contractType)
    if not player or not base then return end
    sendClientCommand(player, 'NPCContracts', 'RequestContract', {
        baseId = bcc_baseId(base),
        contractType = contractType or "auto"
    })
end

function NPCContractsClientBridge.CompleteContract(player)
    if not player then return end
    sendClientCommand(player, 'NPCContracts', 'CompleteContract', {})
end

function NPCContractsClientBridge.AbandonContract(player)
    if not player then return end
    sendClientCommand(player, 'NPCContracts', 'AbandonContract', {})
end

function NPCContractsClientBridge.OnFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    if not bcc_settingBool("Contract_Enabled", true) then return end
    local player = getSpecificPlayer(playerNum)
    if not player then return end

    local active = NPCContractsClientBridge.active
    if active and active.status == "active" and bcc_canCompleteRecon(active, player) then
        context:addOption(bcc_text("Menu_CompleteReconContract"), player, NPCContractsClientBridge.CompleteContract)
    elseif active and active.status == "active" and bcc_canCompleteRecover(active, player) then
        context:addOption(bcc_text("Menu_RecoverContractObjective"), player, NPCContractsClientBridge.CompleteContract)
    end

    local base = bcc_nearBase()
    if not base then
        if active and active.status == "active" then
            local root = context:addOption(bcc_text("Menu_FactionContract"))
            local menu = context:getNew(context)
            context:addSubMenu(root, menu)
            menu:addOption(bcc_contractText(active), player, function() bcc_halo(bcc_contractText(active), 180, 230, 255) end)
            menu:addOption(bcc_text("Menu_AbandonContract"), player, NPCContractsClientBridge.AbandonContract)
        end
        return
    end

    local root = context:addOption(bcc_text("Menu_FactionContract"))
    local menu = context:getNew(context)
    context:addSubMenu(root, menu)

    if active and active.status == "active" then
        menu:addOption(bcc_contractText(active), player, function() bcc_halo(bcc_contractText(active), 180, 230, 255) end)
        if active.type == "recon" and bcc_canCompleteRecon(active, player) then
            menu:addOption(bcc_text("Menu_CompleteReconContract"), player, NPCContractsClientBridge.CompleteContract)
        elseif active.type == "recover" and bcc_canCompleteRecover(active, player) then
            menu:addOption(bcc_text("Menu_RecoverContractObjective"), player, NPCContractsClientBridge.CompleteContract)
        end
        menu:addOption(bcc_text("Menu_AbandonContract"), player, NPCContractsClientBridge.AbandonContract)
    else
        menu:addOption(bcc_text("Menu_RequestAvailableContract"), player, NPCContractsClientBridge.RequestContract, base, "auto")
        menu:addOption(bcc_text("Menu_RequestSupplyContract"), player, NPCContractsClientBridge.RequestContract, base, "supply")
        menu:addOption(bcc_text("Menu_RequestReconContract"), player, NPCContractsClientBridge.RequestContract, base, "recon")
        menu:addOption(bcc_text("Menu_RequestRecoverContract"), player, NPCContractsClientBridge.RequestContract, base, "recover")
    end
end

function NPCContractsClientBridge.OnServerCommand(module, command, args)
    if not NPCLegacyContractBridge.IsModule(module, "NPCContracts", "contracts") then return end
    if command == "Active" then
        NPCContractsClientBridge.active = args
        if args and args.text then bcc_halo(args.text, 140, 240, 160) end
    elseif command == "Clear" then
        NPCContractsClientBridge.active = nil
    elseif command == "Result" then
        if args and args.text then bcc_halo(args.text, args.r, args.g, args.b) end
    end
end

local function bcc_onTick()
    if NPCContractsClientBridge._syncRequested then return end
    local player = bcc_player()
    if not player then return end
    NPCContractsClientBridge._syncRequested = true
    sendClientCommand(player, 'NPCContracts', 'RequestSync', {})
end

function NPCContractsClientBridge.Install()
    if NPCContractsClientBridge._installed then return end
    NPCContractsClientBridge._installed = true
    Events.OnFillWorldObjectContextMenu.Add(NPCContractsClientBridge.OnFillWorldObjectContextMenu)
    Events.OnServerCommand.Add(NPCContractsClientBridge.OnServerCommand)
    if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.RegisterTickJob then
        NPCWorkSchedulerBridge.RegisterTickJob("NPCContractsClientBridge.SyncBootstrap", bcc_onTick, "ui", 30, 1)
    elseif Events and Events.OnTick then
        Events.OnTick.Add(bcc_onTick)
    end
end
