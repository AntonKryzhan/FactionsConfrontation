-- NPCBlackMarketServerBridge.lua
-- Neutral server backend for static black market service objects.
-- This file deliberately does not spawn IsoZombie/IsoGameCharacter traders.
require "NPCCore/NPCLegacyContractBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

local NPC_LEGACY_GLOBALS = NPCLegacyGlobalsBridge
if not isServer() then return end

require "NPCCore/NPCBlackMarketBridge"

require "NPCCore/NPCLegacyContractBridge"

NPCBlackMarketServerBridge = NPCBlackMarketServerBridge or {}
local function npcserver_setDebugMarker(gmd, marker)
    local runtime = NPCServerRuntime
    local setter = runtime and runtime.SetDebugMarker or NPC_LEGACY_GLOBALS.Get("SetDebugMarker")
    if setter then return setter(gmd, marker) end
    return false
end


local function halo(p,t,r,g,b)
    if p and t then sendServerCommand(p,'NPCBlackMarket','Result',{text=t,r=r or 220,g=g or 210,b=b or 120}) end
end

local function setMarker(gmd,m)
    if not (gmd and m and m.id) then return end
    if not npcserver_setDebugMarker(gmd,m) then
        gmd.DebugMapMarkers=gmd.DebugMapMarkers or {}
        gmd.DebugMapMarkers[tostring(m.id)]=m
        if NPCNetContract and NPCNetContract.SendDebugMapUpdate then NPCNetContract.SendDebugMapUpdate(m) else sendServerCommand('NPCDebugMap','Update',m) end
    end
end

local function removeMarker(gmd,id)
    if gmd and id then
        if gmd.DebugMapMarkers then gmd.DebugMapMarkers[tostring(id)]=nil end
        if NPCNetContract and NPCNetContract.SendDebugMapRemove then NPCNetContract.SendDebugMapRemove(id) else sendServerCommand('NPCDebugMap','Remove',{id=id}) end
    end
end

local function syncMarker(gmd,c)
    local m=NPCBlackMarketBridge.MakeMarker(c)
    if m then setMarker(gmd,m) end
end

local function contactList(gmd)
    local d=NPCBlackMarketBridge.EnsureData(gmd)
    local list={}
    for _,c in pairs(d.contacts or {}) do
        if type(c)=="table" and c.blackMarketStatus ~= "closed" then list[#list+1]=c end
    end
    return list
end

local function syncContacts(p)
    local gmd=GetNPCModData()
    sendServerCommand(p,'NPCBlackMarket','Contacts',{contacts=contactList(gmd)})
end

local function syncContactsAll()
    local players = getOnlinePlayers and getOnlinePlayers() or nil
    if players and players.size and players.get then
        for i=0, players:size()-1 do
            local p = players:get(i)
            if p then syncContacts(p) end
        end
    end
end



local function bbms_nowHours()
    if getGameTime then
        local gt = getGameTime()
        if gt and gt.getWorldAgeHours then
            local ok, value = pcall(function() return gt:getWorldAgeHours() end)
            if ok and value ~= nil then return tonumber(value) or 0 end
        end
    end
    return os.time and (os.time() / 3600) or 0
end

local function bbms_num(name, defaultValue, minValue, maxValue)
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

local function bbms_rand(minValue, maxValue)
    minValue = math.floor(tonumber(minValue) or 0)
    maxValue = math.floor(tonumber(maxValue) or minValue)
    if maxValue <= minValue then return minValue end
    if ZombRand then
        local ok, value = pcall(function() return ZombRand(minValue, maxValue) end)
        if ok and value ~= nil then return tonumber(value) or minValue end
        ok, value = pcall(function() return minValue + ZombRand(maxValue - minValue) end)
        if ok and value ~= nil then return tonumber(value) or minValue end
    end
    return minValue + math.random(0, maxValue - minValue - 1)
end

local function bbms_dist(x1, y1, x2, y2)
    local dx = (tonumber(x1) or 0) - (tonumber(x2) or 0)
    local dy = (tonumber(y1) or 0) - (tonumber(y2) or 0)
    return math.sqrt(dx * dx + dy * dy)
end

local function bbms_materializeRadius()
    return bbms_num("BlackMarket_StaticDrawRadius", 70, 8, 180)
end

local function bbms_virtualHomeRadius()
    return bbms_num("BlackMarket_VirtualHomeRadius", 900, 80, 3000)
end

local function bbms_virtualStepRadius()
    return bbms_num("BlackMarket_VirtualStepRadius", 28, 6, 120)
end

local function bbms_virtualMoveHours()
    return bbms_num("BlackMarket_VirtualMoveMinutes", 8, 2, 120) / 60
end

local function bbms_anyPlayerNear(x, y, radius)
    local players = getOnlinePlayers and getOnlinePlayers() or nil
    if not (players and players.size and players.get) then return false end
    local okSize, count = pcall(function() return players:size() end)
    if not okSize then return false end
    for i = 0, (tonumber(count) or 0) - 1 do
        local okGet, player = pcall(function() return players:get(i) end)
        if okGet and player and player.getX and player.getY then
            local okPos, px, py = pcall(function() return player:getX(), player:getY() end)
            if okPos and bbms_dist(x, y, px, py) <= radius then return true end
        end
    end
    return false
end

local function bbms_normalizeVirtualContact(contact)
    if type(contact) ~= "table" then return end
    contact.blackMarketStaticObject = true
    contact.blackMarketVirtualObject = true
    if contact.blackMarketHomeX == nil then contact.blackMarketHomeX = math.floor(tonumber(contact.x) or 0) end
    if contact.blackMarketHomeY == nil then contact.blackMarketHomeY = math.floor(tonumber(contact.y) or 0) end
    if contact.blackMarketHomeZ == nil then contact.blackMarketHomeZ = tonumber(contact.z) or 0 end
    if contact.blackMarketHomeRadius == nil then contact.blackMarketHomeRadius = bbms_virtualHomeRadius() end
    if contact.blackMarketNextMoveAt == nil then contact.blackMarketNextMoveAt = bbms_nowHours() + bbms_virtualMoveHours() end
end

local function bbms_inHome(contact, x, y)
    local radius = tonumber(contact.blackMarketHomeRadius) or bbms_virtualHomeRadius()
    return bbms_dist(contact.blackMarketHomeX or contact.x, contact.blackMarketHomeY or contact.y, x, y) <= radius
end

local function bbms_pickVirtualTarget(contact)
    local hx = tonumber(contact.blackMarketHomeX) or tonumber(contact.x) or 0
    local hy = tonumber(contact.blackMarketHomeY) or tonumber(contact.y) or 0
    local radius = tonumber(contact.blackMarketHomeRadius) or bbms_virtualHomeRadius()
    local target = nil

    if NPCRoadNavBridge and NPCRoadNavBridge.FindNearbyWorldRoadPoint then
        local ok, got = pcall(function() return NPCRoadNavBridge.FindNearbyWorldRoadPoint(hx, hy, radius, 120) end)
        if ok and got and got.x and got.y and bbms_inHome(contact, got.x, got.y) then target = got end
    end

    if not target then
        for _ = 1, 24 do
            local tx = hx + bbms_rand(-radius, radius + 1)
            local ty = hy + bbms_rand(-radius, radius + 1)
            if bbms_inHome(contact, tx, ty) then
                target = {x = tx, y = ty, z = tonumber(contact.blackMarketHomeZ) or tonumber(contact.z) or 0}
                break
            end
        end
    end

    if target then
        contact.blackMarketTargetX = math.floor(tonumber(target.x) or hx)
        contact.blackMarketTargetY = math.floor(tonumber(target.y) or hy)
        contact.blackMarketTargetZ = tonumber(target.z) or tonumber(contact.blackMarketHomeZ) or tonumber(contact.z) or 0
    end
end

local function bbms_stepToward(contact)
    local x = tonumber(contact.x) or tonumber(contact.blackMarketHomeX) or 0
    local y = tonumber(contact.y) or tonumber(contact.blackMarketHomeY) or 0
    local z = tonumber(contact.z) or tonumber(contact.blackMarketHomeZ) or 0
    local tx = tonumber(contact.blackMarketTargetX)
    local ty = tonumber(contact.blackMarketTargetY)
    if not tx or not ty or bbms_dist(x, y, tx, ty) < 4 then
        bbms_pickVirtualTarget(contact)
        tx = tonumber(contact.blackMarketTargetX)
        ty = tonumber(contact.blackMarketTargetY)
    end
    if not tx or not ty then return false end

    local candidate = nil
    local stepRadius = bbms_virtualStepRadius()
    if NPCRoadNavBridge and NPCRoadNavBridge.FindNearbyWorldRoadStepToward then
        local ok, got = pcall(function() return NPCRoadNavBridge.FindNearbyWorldRoadStepToward(x, y, tx, ty, stepRadius, 80) end)
        if ok and got and got.x and got.y then candidate = got end
    end

    if not candidate then
        local dx = tx - x
        local dy = ty - y
        local len = math.sqrt(dx * dx + dy * dy)
        if len < 1 then return false end
        local step = math.min(stepRadius, len)
        candidate = {x = x + (dx / len) * step, y = y + (dy / len) * step, z = z}
    end

    local nx = math.floor((tonumber(candidate.x) or x) + 0.5)
    local ny = math.floor((tonumber(candidate.y) or y) + 0.5)
    local nz = tonumber(candidate.z) or z
    if not bbms_inHome(contact, nx, ny) then
        bbms_pickVirtualTarget(contact)
        return false
    end
    if bbms_anyPlayerNear(nx, ny, bbms_materializeRadius()) then
        return false
    end

    if nx == math.floor(x) and ny == math.floor(y) then return false end
    contact.x = nx
    contact.y = ny
    contact.z = nz
    contact.blackMarketVirtual = true
    contact.blackMarketMaterialized = false
    contact.blackMarketLastVirtualMoveAt = bbms_nowHours()
    contact.updatedAt = contact.blackMarketLastVirtualMoveAt
    return true
end

local function updateVirtualContacts(gmd)
    local d = NPCBlackMarketBridge.EnsureData(gmd)
    if not (d and type(d.contacts) == "table") then return 0 end
    local changed = 0
    local now = bbms_nowHours()
    local holdRadius = bbms_materializeRadius()
    for _, contact in pairs(d.contacts or {}) do
        if type(contact) == "table" and contact.blackMarketStatus ~= "closed" then
            bbms_normalizeVirtualContact(contact)
            local visible = bbms_anyPlayerNear(contact.x, contact.y, holdRadius)
            if visible then
                if contact.blackMarketVirtual ~= false or contact.blackMarketMaterialized ~= true then changed = changed + 1 end
                contact.blackMarketVirtual = false
                contact.blackMarketMaterialized = true
                contact.blackMarketNextMoveAt = now + bbms_virtualMoveHours()
            else
                if contact.blackMarketVirtual ~= true or contact.blackMarketMaterialized ~= false then changed = changed + 1 end
                contact.blackMarketVirtual = true
                contact.blackMarketMaterialized = false
                if now >= (tonumber(contact.blackMarketNextMoveAt) or 0) then
                    if bbms_stepToward(contact) then changed = changed + 1 end
                    contact.blackMarketNextMoveAt = now + bbms_virtualMoveHours()
                end
            end
        end
    end
    return changed
end

local function safeZombieId(zombie)
    if not zombie then return nil end
    if zombie.getOnlineID then
        local ok, id = pcall(function() return zombie:getOnlineID() end)
        if ok and id ~= nil then return id end
    end
    if zombie.getID then
        local ok, id = pcall(function() return zombie:getID() end)
        if ok and id ~= nil then return id end
    end
    return nil
end

local function safeVar(zombie, name)
    if not (zombie and zombie.getVariableString) then return nil end
    local ok, value = pcall(function() return zombie:getVariableString(name) end)
    if ok and value and value ~= "" then return tostring(value) end
    return nil
end

local function brainMarksBlackMarket(brain)
    if type(brain) ~= "table" then return false end
    if brain.blackMarket == true or brain.blackMarketNPC == true or brain.blackMarketService == true or brain.special == "BlackMarket" then return true end
    if brain.blackMarketContact == true or brain.blackMarketContactId ~= nil then return true end
    if type(brain.program) == "table" and (brain.program.name == "BlackMarket" or brain.program.name == "BlackMarketPrepare") then return true end
    if tostring(brain.factionState or "") == "black_market_service" then return true end
    if tostring(brain.factionSide or "") == "black_market" or tostring(brain.factionSide or "") == "black_market_service" then return true end
    return false
end

local function zombieMarksBlackMarket(gmd, zombie)
    if not zombie then return false end
    local md = zombie.getModData and zombie:getModData() or nil
    if type(md) == "table" then
        if md.NPCBlackMarketBridge == true or md.BlackMarketNPC == true or md.BlackMarketService == true then return true end
        if md.BlackMarketId ~= nil or md.blackMarketId ~= nil or md.blackMarketContactId ~= nil then return true end
    end
    if safeVar(zombie, NPCLegacyContractBridge.Keys.BLACK_MARKET) == "true" then return true end
    if safeVar(zombie, "BlackMarketId") ~= nil then return true end
    local brain = NPCBrainData and NPCBrainData.Get and NPCBrainData.Get(zombie) or nil
    if brainMarksBlackMarket(brain) then return true end
    local zid = safeZombieId(zombie)
    if gmd and zid and type(gmd.Queue) == "table" then
        brain = gmd.Queue[zid] or gmd.Queue[tostring(zid)] or (tonumber(zid) and gmd.Queue[tonumber(zid)])
        if brainMarksBlackMarket(brain) then return true end
    end
    return false
end

local function removeZombieObject(zombie)
    if not zombie then return false end
    if NPCBrainData and NPCBrainData.Remove then pcall(function() NPCBrainData.Remove(zombie) end) end
    pcall(function() zombie:setVariable(NPCLegacyContractBridge.Key("BLACK_MARKET"), false) end)
    pcall(function() zombie:setVariable("BlackMarketId", "") end)
    pcall(function() zombie:setVariable(NPCLegacyContractBridge.Key("FLAG"), false) end)
    pcall(function() zombie:setVariable(NPCLegacyContractBridge.Key("PRIMARY"), "") end)
    pcall(function() zombie:setVariable(NPCLegacyContractBridge.Key("SECONDARY"), "") end)
    pcall(function() zombie:clearAttachedItems() end)
    pcall(function() zombie:removeFromWorld() end)
    pcall(function() zombie:removeFromSquare() end)
    return true
end

local function cleanupLegacyBlackMarketNPCs(gmd)
    local removed = 0
    if gmd and type(gmd.Queue) == "table" then
        for id, brain in pairs(gmd.Queue) do
            if brainMarksBlackMarket(brain) then
                gmd.Queue[id] = nil
                removed = removed + 1
                removeMarker(gmd, tostring(id))
            end
        end
    end
    local cell = getCell and getCell() or nil
    local list = cell and cell.getZombieList and cell:getZombieList() or nil
    if list and list.size and list.get then
        local size = 0
        local okSize, gotSize = pcall(function() return list:size() end)
        if okSize then size = tonumber(gotSize) or 0 end
        for i = size - 1, 0, -1 do
            local okGet, zombie = pcall(function() return list:get(i) end)
            if okGet and zombie and zombieMarksBlackMarket(gmd, zombie) then
                local id = safeZombieId(zombie)
                if id and gmd and gmd.Queue then
                    gmd.Queue[id] = nil
                    gmd.Queue[tostring(id)] = nil
                    if tonumber(id) then gmd.Queue[tonumber(id)] = nil end
                end
                if removeZombieObject(zombie) then removed = removed + 1 end
                if id then
                    sendServerCommand('NPCCommands', NPCLegacyContractBridge.Commands.REMOVE_OBJECTS, {ids={id}, runtimeCleanup=true, blackMarketStaticCleanup=true})
                    removeMarker(gmd, tostring(id))
                end
            end
        end
    end
    return removed
end

local function contactFor(p,args)
    local gmd=GetNPCModData()
    local x=p and p.getX and p:getX() or 0
    local y=p and p.getY and p:getY() or 0
    local radius=NPCBlackMarketBridge.StaticPlayerRadius and NPCBlackMarketBridge.StaticPlayerRadius() or 8
    local c=NPCBlackMarketBridge.GetContact(gmd,args and args.contactId)
    if c then
        local dx=(tonumber(c.x) or 0)-(tonumber(x) or 0)
        local dy=(tonumber(c.y) or 0)-(tonumber(y) or 0)
        if math.sqrt(dx*dx+dy*dy)<=radius+2 then return gmd,c end
        return gmd,nil
    end
    return gmd, NPCBlackMarketBridge.NearestContact(gmd,x,y,radius)
end

local function pay(p,action)
    local res,amt=NPCBlackMarketBridge.DealCost(action)
    if not res then return false,"Unknown deal." end
    if amt<=0 then return true,"free" end
    if NPCBlackMarketBridge.CountItems(p,res)<amt then return false,"Need "..NPCBlackMarketBridge.PriceText(action).."." end
    if not NPCBlackMarketBridge.TakeItems(p,res,amt) then return false,"Payment failed." end
    return true,"paid"
end

local function payoff(gmd,p,side)
    if not (NPCBountyBridge and NPCBountyBridge.GetSideRecord and NPCBountyBridge.Add) then return false,"Bounty unavailable." end
    side=NPCBlackMarketBridge.NormalizeSide(side)
    local rec=NPCBountyBridge.GetSideRecord(gmd,p,side)
    if not rec or (tonumber(rec.value) or 0)<=0 then return false,"No active bounty with "..NPCBlackMarketBridge.SideLabel(side).."." end
    local before=tonumber(rec.value) or 0
    NPCBountyBridge.Add(gmd,p,side,-NPCBlackMarketBridge.BountyReduction(),"black_market_payoff")
    local afterRec=NPCBountyBridge.GetSideRecord(gmd,p,side)
    local after=afterRec and (tonumber(afterRec.value) or 0) or 0
    if after<=0.5 then
        removeMarker(gmd,"bounty_"..tostring(NPCBountyBridge.PlayerId(p)).."_"..tostring(side))
    elseif NPCBountyBridge.MakeBountyMarker then
        local pr=NPCBountyBridge.GetPlayerRecord(gmd,p)
        local m=NPCBountyBridge.MakeBountyMarker(pr,side,afterRec)
        if m then setMarker(gmd,m) end
    end
    if NPCWorldRulesServer and NPCWorldRulesServer.SyncAfterConsequence then
        NPCWorldRulesServer.SyncAfterConsequence(p,"black_market_bounty_payoff",{side=side,before=before,after=after})
    elseif NPCBountyServer and NPCBountyServer.SyncPlayer then
        NPCBountyServer.SyncPlayer(p)
    end
    return true,"Bounty reduced for "..NPCBlackMarketBridge.SideLabel(side)..": "..tostring(math.floor(before+0.5)).." -> "..tostring(math.floor(after+0.5)).."."
end

local function leaderTip(gmd,side)
    if not (gmd and gmd.NPCLeadersBridge and type(gmd.NPCLeadersBridge.leaders)=="table") then return false,"No leader rumors." end
    side=NPCBlackMarketBridge.NormalizeSide(side)
    for _,l in pairs(gmd.NPCLeadersBridge.leaders) do
        if type(l)=="table" and l.state~="dead" and NPCBlackMarketBridge.NormalizeSide(l.side)==side then
            local m=nil
            if NPCLeadersBridge and NPCLeadersBridge.MakeLeaderMarker then m=NPCLeadersBridge.MakeLeaderMarker(l) end
            if m then setMarker(gmd,m) end
            return true,"Leader rumor: "..tostring(l.name or l.id).." near "..tostring(math.floor(tonumber(l.x) or 0))..","..tostring(math.floor(tonumber(l.y) or 0)).."."
        end
    end
    return false,"No living leader contact for "..NPCBlackMarketBridge.SideLabel(side).."."
end

function NPCBlackMarketServerBridge.Deal(p,args)
    if not (NPCBlackMarketBridge and NPCBlackMarketBridge.IsEnabled()) then return end
    local action=tostring(args and args.action or "")
    local side=NPCBlackMarketBridge.NormalizeSide(args and args.side)
    local gmd,c=contactFor(p,args or {})
    if not c then halo(p,"No black market service object nearby.",255,120,70); return end
    local ok,msg=pay(p,action)
    if not ok then halo(p,msg,255,120,70); return end
    side=side or c.blackMarketSide or c.sourceSide
    local success=false
    if action=="forged_papers" or action=="stolen_badge" then
        local doc=NPCFactionDocsBridge and NPCFactionDocsBridge.GrantDocument and NPCFactionDocsBridge.GrantDocument(gmd,p,side,action,"black_market")
        success=doc~=nil
        msg=success and ("Bought "..tostring(doc.label or action).." for "..NPCBlackMarketBridge.SideLabel(side)..".") or "Document deal failed."
        if success and NPCWorldRules and NPCWorldRules.IsBountyActive and NPCWorldRules.IsBountyActive(gmd,p,side,NPCWorldRules.GetBountyThresholdForCheckpoint()) then msg=msg.." Warning: active bounty can still block checkpoints." end
    elseif action=="password" then
        local pass=NPCFactionDocsBridge and NPCFactionDocsBridge.GrantPassword and NPCFactionDocsBridge.GrantPassword(gmd,p,side,"black_market")
        success=pass~=nil
        msg=success and ("Bought password for "..NPCBlackMarketBridge.SideLabel(side)..": "..tostring(pass.password)..".") or "Password deal failed."
        if success and NPCWorldRules and NPCWorldRules.IsBountyActive and NPCWorldRules.IsBountyActive(gmd,p,side,NPCWorldRules.GetBountyThresholdForCheckpoint()) then msg=msg.." Warning: active bounty can still block checkpoints." end
    elseif action=="bounty_payoff" then
        success,msg=payoff(gmd,p,side)
    elseif action=="leader_tip" then
        success,msg=leaderTip(gmd,side)
    else
        msg="Unknown black market deal."
    end
    NPCBlackMarketBridge.RecordTrade(gmd,p,c,action,side,success and "success" or "failed")
    c.updatedAt=getGameTime and getGameTime():getWorldAgeHours() or c.updatedAt
    syncMarker(gmd,c)
    halo(p,msg, success and 190 or 255, success and 230 or 130, success and 120 or 80)
    syncContacts(p)
    if success and action~="bounty_payoff" and NPCWorldRulesServer and NPCWorldRulesServer.SyncAfterConsequence then
        NPCWorldRulesServer.SyncAfterConsequence(p,"black_market_"..tostring(action),{side=side})
    end
    if TransmitNPCModData then TransmitNPCModData() end
end

function NPCBlackMarketServerBridge.Status(p)
    local gmd=GetNPCModData()
    cleanupLegacyBlackMarketNPCs(gmd)
    NPCBlackMarketBridge.EnsureContacts(gmd)
    if NPCBlackMarketBridge.RebalanceContacts then NPCBlackMarketBridge.RebalanceContacts(gmd, 2) end
    updateVirtualContacts(gmd)
    halo(p,NPCBlackMarketBridge.StatusText(gmd,p),230,220,150)
    syncContacts(p)
end

function NPCBlackMarketServerBridge.Refresh(p)
    local gmd=GetNPCModData()
    cleanupLegacyBlackMarketNPCs(gmd)
    NPCBlackMarketBridge.EnsureContacts(gmd)
    if NPCBlackMarketBridge.RebalanceContacts then NPCBlackMarketBridge.RebalanceContacts(gmd, 2) end
    updateVirtualContacts(gmd)
    local d=NPCBlackMarketBridge.EnsureData(gmd)
    for _,c in pairs(d.contacts or {}) do syncMarker(gmd,c) end
    syncContacts(p)
    if TransmitNPCModData then TransmitNPCModData() end
end

function NPCBlackMarketServerBridge.OnClientCommand(module,command,p,args)
    if not (NPCLegacyContractBridge and NPCLegacyContractBridge.IsModule and NPCLegacyContractBridge.IsModule(module, 'NPCBlackMarket', 'blackMarket')) then return end
    if command=='Deal' then NPCBlackMarketServerBridge.Deal(p,args or {})
    elseif command=='Status' then NPCBlackMarketServerBridge.Status(p)
    elseif command=='Refresh' then NPCBlackMarketServerBridge.Refresh(p)
    elseif command=='NPCDead' then return end
end

local function everyTen()
    if not (NPCBlackMarketBridge and NPCBlackMarketBridge.IsEnabled()) then return end
    local gmd=GetNPCModData()
    local removed=NPCBlackMarketBridge.Cleanup(gmd)
    removed = (tonumber(removed) or 0) + cleanupLegacyBlackMarketNPCs(gmd)
    NPCBlackMarketBridge.EnsureContacts(gmd)
    local rebalanced = NPCBlackMarketBridge.RebalanceContacts and NPCBlackMarketBridge.RebalanceContacts(gmd, 2) or 0
    local moved = updateVirtualContacts(gmd)
    local d=NPCBlackMarketBridge.EnsureData(gmd)
    for _,c in pairs(d.contacts or {}) do syncMarker(gmd,c) end
    syncContactsAll()
    if ((tonumber(removed) or 0) > 0 or (tonumber(moved) or 0) > 0 or (tonumber(rebalanced) or 0) > 0) and TransmitNPCModData then TransmitNPCModData() end
end

local cleanupTick = 0
local function onTick()
    cleanupTick = cleanupTick + 1
    if cleanupTick % 900 ~= 0 then return end
    cleanupLegacyBlackMarketNPCs(GetNPCModData())
end

function NPCBlackMarketServerBridge.Install()
    if NPCBlackMarketServerBridge.__installed then return end
    NPCBlackMarketServerBridge.__installed = true
    Events.OnClientCommand.Add(NPCBlackMarketServerBridge.OnClientCommand)
    Events.EveryTenMinutes.Add(everyTen)
    Events.OnTick.Add(onTick)
end
