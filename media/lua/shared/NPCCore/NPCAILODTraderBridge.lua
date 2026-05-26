-- NPCAILODTraderBridge.lua
-- Neutral shared backend for LOD trader.

require "NPCCore/NPCWorkSchedulerBridge"

NPCAILODTraderBridge = NPCAILODTraderBridge or {}
NPCAILODTraderBridge.VERSION = "2026-05-24-safe-lod-trader-governed"
NPCAILODTraderBridge.LOD_FULL, NPCAILODTraderBridge.LOD_HIGH, NPCAILODTraderBridge.LOD_MEDIUM, NPCAILODTraderBridge.LOD_LOW, NPCAILODTraderBridge.LOD_PROXY = 0,1,2,3,4
NPCAILODTraderBridge.Config = NPCAILODTraderBridge.Config or {enabled=true,npcFullRadius=42,npcHighRadius=90,npcMediumRadius=180,npcLowRadius=320,proxyUpdateSeconds=14,useCriticality=true,debugLog=false}
NPCAILODTraderBridge._tick = NPCAILODTraderBridge._tick or 0
local function nset(k,d,mi,ma) if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then return NPCLegacySettingsBridge.GetNumber(k,d,mi,ma) end return tonumber(d) or 0 end
local function bset(k,d) if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then return NPCLegacySettingsBridge.GetBool(k,d==true) end return d==true end
function NPCAILODTraderBridge.ApplySettings()
 local c=NPCAILODTraderBridge.Config; c.enabled=bset('AILOD_Enabled',c.enabled~=false); c.npcFullRadius=nset('AILOD_NPCFullRadius',c.npcFullRadius,5,1000); c.npcHighRadius=nset('AILOD_NPCHighRadius',c.npcHighRadius,c.npcFullRadius,1500); c.npcMediumRadius=nset('AILOD_NPCMediumRadius',c.npcMediumRadius,c.npcHighRadius,2500); c.npcLowRadius=nset('AILOD_NPCLowRadius',c.npcLowRadius,c.npcMediumRadius,5000); c.proxyUpdateSeconds=nset('AILOD_ProxyUpdateSeconds',c.proxyUpdateSeconds,1,600); c.useCriticality=bset('AILOD_UseCriticality',c.useCriticality~=false); c.debugLog=bset('AILOD_DebugLog',c.debugLog==true)
end
local function d2(x1,y1,x2,y2) local dx=(tonumber(x1)or 0)-(tonumber(x2)or 0); local dy=(tonumber(y1)or 0)-(tonumber(y2)or 0); return dx*dx+dy*dy end
function NPCAILODTraderBridge.GetNearestPlayerDistance(x,y)
 local best=nil
 if getOnlinePlayers then local ok,ps=pcall(function() return getOnlinePlayers() end); if ok and ps then for i=0,ps:size()-1 do local p=ps:get(i); if p and p.getX and not(p.isDead and p:isDead()) then local dd=d2(x,y,p:getX(),p:getY()); if not best or dd<best then best=dd end end end end end
 if not best and getNumActivePlayers and getSpecificPlayer then for i=0,getNumActivePlayers()-1 do local p=getSpecificPlayer(i); if p and p.getX then local dd=d2(x,y,p:getX(),p:getY()); if not best or dd<best then best=dd end end end end
 if not best and getSpecificPlayer then local p=getSpecificPlayer(0); if p and p.getX then best=d2(x,y,p:getX(),p:getY()) end end
 return best and math.sqrt(best) or 999999
end
local function important(brain) return brain and (brain.mercenaryHired or brain.hired or brain.isPlayerGuard or brain.master or brain.inBattle or brain.targetId or brain.radioThreat) end
function NPCAILODTraderBridge.ScoreNPC(bandit,brain,threat)
 if not bandit or not bandit.getX then return 0,999999 end; local dist=NPCAILODTraderBridge.GetNearestPlayerDistance(bandit:getX(),bandit:getY()); local c=NPCAILODTraderBridge.Config; local s=0
 if dist<=c.npcFullRadius then s=s+100 elseif dist<=c.npcHighRadius then s=s+70 elseif dist<=c.npcMediumRadius then s=s+40 elseif dist<=c.npcLowRadius then s=s+15 end
 if threat then s=s+100 end; if important(brain) then s=s+80 end; if brain and brain.fsm and (brain.fsm.state=='Attack' or brain.fsm.state=='Flee' or brain.fsm.state=='EmergencyDefense') then s=s+50 end
 return s,dist
end
function NPCAILODTraderBridge.GetNPCLOD(bandit,brain,threat)
 if not NPCAILODTraderBridge.Config.enabled then return NPCAILODTraderBridge.LOD_FULL,999,0 end; local s,dist=NPCAILODTraderBridge.ScoreNPC(bandit,brain,threat); local c=NPCAILODTraderBridge.Config
 if s>=90 or dist<=c.npcFullRadius then return NPCAILODTraderBridge.LOD_FULL,s,dist elseif s>=55 or dist<=c.npcHighRadius then return NPCAILODTraderBridge.LOD_HIGH,s,dist elseif s>=25 or dist<=c.npcMediumRadius then return NPCAILODTraderBridge.LOD_MEDIUM,s,dist elseif dist<=c.npcLowRadius then return NPCAILODTraderBridge.LOD_LOW,s,dist end
 return NPCAILODTraderBridge.LOD_PROXY,s,dist
end
function NPCAILODTraderBridge.GetThinkInterval(lod,sub) if lod==0 then return 1 elseif lod==1 then return sub=='combat' and 2 or 3 elseif lod==2 then return sub=='combat' and 5 or 8 elseif lod==3 then return sub=='combat' and 12 or 24 end return 999999 end
local function key(bandit,brain) if brain and (brain.id or brain.uid) then return tostring(brain.id or brain.uid) end; if NPCUtils and NPCUtils.GetCharacterID then local ok,id=pcall(function() return NPCUtils.GetCharacterID(bandit) end); if ok and id then return tostring(id) end end; return tostring(bandit) end
function NPCAILODTraderBridge.ShouldRunNPC(bandit,brain,sub,tick,threat)
 if not NPCAILODTraderBridge.Config.enabled then return true,0 end; local lod=NPCAILODTraderBridge.GetNPCLOD(bandit,brain,threat); if lod==NPCAILODTraderBridge.LOD_PROXY then return false,lod end; local int=NPCAILODTraderBridge.GetThinkInterval(lod,sub or 'brain'); tick=tonumber(tick) or NPCAILODTraderBridge._tick or 0; local seed=0; local k=key(bandit,brain); for i=1,string.len(k) do seed=seed+string.byte(k,i) end; return ((tick+seed)%math.max(1,int))==0,lod
end
function NPCAILODTraderBridge.GetGroupLOD(g) if not g or not g.x then return 4,999999 end; if g.inBattle or g.activated then return 1,0 end; local dist=NPCAILODTraderBridge.GetNearestPlayerDistance(g.x,g.y); local c=NPCAILODTraderBridge.Config; if dist<=c.npcHighRadius then return 1,dist elseif dist<=c.npcMediumRadius then return 2,dist elseif dist<=c.npcLowRadius then return 3,dist end; return 4,dist end
function NPCAILODTraderBridge.ShouldUpdateVirtualGroup(g,worldAge) if not NPCAILODTraderBridge.Config.enabled or (g and g.inBattle) then return true end; local lod=NPCAILODTraderBridge.GetGroupLOD(g); local sec=NPCAILODTraderBridge.Config.proxyUpdateSeconds or 14; if lod==1 then sec=math.max(2,sec*.35) elseif lod==2 then sec=math.max(4,sec*.75) elseif lod==3 then sec=math.max(8,sec*1.5) else sec=math.max(10,sec*3) end; worldAge=tonumber(worldAge) or (getGameTime and getGameTime():getWorldAgeHours() or 0); local last=tonumber(g and g.lodLastUpdate) or 0; if worldAge-last>=sec/3600 then if g then g.lodLastUpdate=worldAge end; return true end; return false end
local function tick() NPCAILODTraderBridge._tick=(NPCAILODTraderBridge._tick or 0)+1; if NPCAILODTraderBridge._tick%300==1 then NPCAILODTraderBridge.ApplySettings() end end
NPCAILODTraderBridge.ApplySettings(); if NPCWorkSchedulerBridge and NPCWorkSchedulerBridge.RegisterTickJob and not NPCAILODTraderBridge._registered then NPCAILODTraderBridge._registered=true; NPCWorkSchedulerBridge.RegisterTickJob("NPCAILODTraderBridge", tick, "system", 1) elseif Events and Events.OnTick and not NPCAILODTraderBridge._registered then NPCAILODTraderBridge._registered=true; Events.OnTick.Add(tick) end
