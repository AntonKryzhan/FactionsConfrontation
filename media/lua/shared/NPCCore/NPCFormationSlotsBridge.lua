-- NPCFormationSlotsBridge.lua
-- Neutral shared backend for formation slot planner.

NPCFormationSlotsBridge=NPCFormationSlotsBridge or {}; NPCFormationSlotsBridge.VERSION="2026-06-08-stage370-bodyguard-follow-slots"; NPCFormationSlotsBridge.Config=NPCFormationSlotsBridge.Config or {enabled=true,slotSpacing=1.8,personalSpace=1.25,maxSlots=18}
local function nset(k,d,mi,ma) if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetNumber then return NPCLegacySettingsBridge.GetNumber(k,d,mi,ma) end return tonumber(d) or 0 end; local function bset(k,d) if NPCLegacySettingsBridge and NPCLegacySettingsBridge.GetBool then return NPCLegacySettingsBridge.GetBool(k,d==true) end return d==true end
function NPCFormationSlotsBridge.ApplySettings() local c=NPCFormationSlotsBridge.Config; c.enabled=bset('FormationSlots_Enabled',c.enabled~=false); c.slotSpacing=nset('FormationSlots_SlotSpacing',c.slotSpacing,.5,5); c.personalSpace=nset('FormationSlots_PersonalSpace',c.personalSpace,.2,5); c.maxSlots=nset('FormationSlots_MaxSlots',c.maxSlots,2,64) end
local function positiveSlotNumber(v)
    local n = tonumber(v)
    if n and n ~= 0 then return math.floor(math.abs(n)) end
    if type(v) == "string" then
        local suffix = v:match("(%d+)%s*$")
        if suffix then
            n = tonumber(suffix)
            if n and n > 0 then return math.floor(n) end
        end
    end
    return nil
end
local function id(b,br)
    if br then
        local n = positiveSlotNumber(br.memberIndex) or positiveSlotNumber(br.slotIndex) or positiveSlotNumber(br.formationIndex) or positiveSlotNumber(br.mercenarySlotIndex)
        if n then return n end
        n = positiveSlotNumber(br.id) or positiveSlotNumber(br.uid) or positiveSlotNumber(br.persistentId) or positiveSlotNumber(br.runtimeId)
        if n then return n end
    end
    if NPCUtils and NPCUtils.GetCharacterID then
        local ok,v=pcall(function() return NPCUtils.GetCharacterID(b) end)
        local n = ok and positiveSlotNumber(v) or nil
        if n then return n end
    end
    return 1
end
local function gslot(idx,base,step,a) local golden=2.399963229728653; idx=math.max(1,tonumber(idx) or 1); local ring=math.floor((idx-1)/8); local radius=(tonumber(base) or 1.0)+ring*(tonumber(step) or .65); local aa=(tonumber(a) or 0)+(idx-1)*golden; return aa,radius end
function NPCFormationSlotsBridge.GetSlotPoint(player,br,b,formation,distance) if not NPCFormationSlotsBridge.Config.enabled or not player then return nil end; local idx=((math.max(1,id(b,br))-1)%(NPCFormationSlotsBridge.Config.maxSlots or 18))+1; local row=math.floor((idx-1)/2)+1; local side=(idx%2==0) and 1 or -1; local a=0; if player.getDirectionAngle then local ok,v=pcall(function() return player:getDirectionAngle() end); if ok and v then a=math.rad(tonumber(v) or 0) end end; local backX,backY=-math.cos(a),-math.sin(a); local rightX,rightY=-math.sin(a),math.cos(a); local spacing=NPCFormationSlotsBridge.Config.slotSpacing or 1.8; local back=(tonumber(distance) or 3)+row*.85; local lat=side*spacing*row; formation=tostring(formation or 'close'); if formation=='ring' or formation=='bodyguard' then local aa,radius=gslot(idx,tonumber(distance) or 3,spacing*1.2,a); return player:getX()+math.cos(aa)*radius, player:getY()+math.sin(aa)*radius, player:getZ() end; if formation=='line' then back=tonumber(distance) or 3; lat=(idx-9)*spacing elseif formation=='wedge' then back=(tonumber(distance) or 3)+row*1.2; lat=side*row*spacing*1.15 elseif formation=='wide' then lat=side*row*spacing*1.65; back=back+row*.4 end; return player:getX()+backX*back+rightX*lat, player:getY()+backY*back+rightY*lat, player:getZ() end

function NPCFormationSlotsBridge.GetPlayerFollowSlotPoint(player,br,b,formation,distance) if not NPCFormationSlotsBridge.Config.enabled or not player then return nil end; local idx=((math.max(1,id(b,br))-1)%(NPCFormationSlotsBridge.Config.maxSlots or 18))+1; formation=tostring(formation or 'close'); local a=0; if player.getDirectionAngle then local ok,v=pcall(function() return player:getDirectionAngle() end); if ok and v then a=math.rad(tonumber(v) or 0) end end; local rightX,rightY=-math.sin(a),math.cos(a); local frontX,frontY=math.cos(a),math.sin(a); local base=tonumber(distance) or .95; if base<.75 then base=.75 elseif base>2.4 then base=2.4 end; local close={{-.58,-.08},{.58,-.08},{-.72,-.72},{.72,-.72},{-.88,.48},{.88,.48},{0,-1.05},{0,.82}}; if formation=='ring' or formation=='bodyguard' then local aa,radius=gslot(idx,math.max(.85,base),.34,a); return player:getX()+math.cos(aa)*radius, player:getY()+math.sin(aa)*radius, player:getZ() end; if formation=='line' then local line=(((idx-1)%7)-3)*.72; return player:getX()+rightX*line-frontX*.18, player:getY()+rightY*line-frontY*.18, player:getZ() end; if formation=='wedge' then local row=math.floor((idx-1)/2)+1; local side=(idx%2==0) and 1 or -1; return player:getX()-frontX*(.35+row*.45)+rightX*side*(.55+row*.35), player:getY()-frontY*(.35+row*.45)+rightY*side*(.55+row*.35), player:getZ() end; if formation=='wide' then local row=math.floor((idx-1)/2)+1; local side=(idx%2==0) and 1 or -1; return player:getX()-frontX*(.25+row*.35)+rightX*side*(.95+row*.55), player:getY()-frontY*(.25+row*.35)+rightY*side*(.95+row*.55), player:getZ() end; local pair=close[((idx-1)%#close)+1]; local side=pair[1]*(base/.95); local front=pair[2]*(base/.95); return player:getX()+rightX*side+frontX*front, player:getY()+rightY*side+frontY*front, player:getZ() end
function NPCFormationSlotsBridge.GetAnchorSlotPoint(anchor,br,b,formation,distance) if not NPCFormationSlotsBridge.Config.enabled or type(anchor)~='table' or not (anchor.x and anchor.y) then return nil end; local idx=((math.max(1,id(b,br))-1)%(NPCFormationSlotsBridge.Config.maxSlots or 18))+1; local row=math.floor((idx-1)/2)+1; local side=(idx%2==0) and 1 or -1; local a=math.rad(tonumber(anchor.facingAngle) or 0); local backX,backY=-math.cos(a),-math.sin(a); local rightX,rightY=-math.sin(a),math.cos(a); local spacing=NPCFormationSlotsBridge.Config.slotSpacing or 1.8; local base=tonumber(distance) or 2.0; local back=row*.65; local lat=side*spacing*row; formation=tostring(formation or 'close'); if formation=='ring' or formation=='bodyguard' then local aa,radius=gslot(idx,math.max(1.4,base),spacing*1.1,a); return tonumber(anchor.x)+math.cos(aa)*radius, tonumber(anchor.y)+math.sin(aa)*radius, tonumber(anchor.z) or 0 end; if formation=='line' then back=0; lat=side*spacing*row elseif formation=='wedge' then back=row*1.1; lat=side*row*spacing*1.15 elseif formation=='wide' then lat=side*row*spacing*1.85; back=row*.9 else back=row*.55; lat=side*spacing*math.max(1,row*.7) end; return tonumber(anchor.x)+backX*back+rightX*lat, tonumber(anchor.y)+backY*back+rightY*lat, tonumber(anchor.z) or 0 end
NPCFormationSlotsBridge.ApplySettings()
