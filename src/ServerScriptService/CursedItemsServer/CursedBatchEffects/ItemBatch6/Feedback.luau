-- Funny-feedback contract shared by ItemBatch6 / ItemBatch7 (CursedA build 2026-10-27).
-- Server sets attributes on the player; clients render them:
--   FaceBeat ('grin'|'gasp'|'pucker'|'frown') + FaceBeatUntil (server time): the game's shared face-beat contract
--     (close-up choices, van gear). VoiceMouthClient draws the mouth, CharacterMotionClient adds wide eyes + tiny pupils
--     for 'gasp'. Every client draws it, so teammates see the face.
--   ReactPop/ReactPopShake/ReactPopAt (the Monsters build's pop renderer in CurseEffectsClient): the popping word + jolt.
--   ItemReact (key) + ItemReactAt (server time): CurseEffectsClient.ItemBatch6Client adds that key's soft colour wash
--     and camera hop / wobble for that player only.
local M={}
M.KEYS={'FaceBeat','FaceBeatUntil','ItemReact','ItemReactAt'}
-- Popping word + camera jolt per reaction key, shown by CurseEffectsClient's ReactPop renderer (shared with the
-- Monsters build: ReactPop text, ReactPopShake 0..1, ReactPopAt server time). An empty word = jolt/tint only.
M.TEXT={
 FoamCheer={'WOOOO! #1!',0},
 BobbleBoing={'BOING!',0},
 JellySplat={'SPLORT!',0},
 CartCheer={'NICE!',0},
 BathGrab={'bloop',0},
 HicSmall={'hic!',0},
 Hiccup={'HIC!',0},
 BubblePop={'POP!',0.75},
 ToastGrab={'tick... tick...',0},
 ToastDing={'DING!',1},
 YoyoZip={'THWIP!',0.75},
 YoyoCaught={'THWIP!',0.62},
 YoyoBonk={'BONK!',0.75},
 YoyoSleepy={'z Z z',0},
 BoxIn={'shh...',0},
 BoxHidden={'HIDDEN',0},
 BoxKicked={'THUNK!',1},
 BoxKick={'KICK!',0.5},
 BoxCollapse={'RUN!',1},
 BoxSquashed={'squashed...',0},
 FogPuff={'PSHHH!',0.5},
 FogWheeze={'pfft...',0},
 LunchSnap={'CHOMP!',1},
 LunchChomp={'CHOMP!',0.5},
 DustyAdopt={'Dusty adopted you!',0},
 DustyGulp={'GULP!',0},
 DustyPanic={'EEK!',0.75},
 DustyDeliver={'PTOO! In the cart!',0},
 SockAdopt={'psst... hi!',0},
 PagerStart={'BZZT!',0.75},
 PagerCollected={'ORDER UP!',0},
 PagerCancelled={'CANCELLED!',1},
 PassGrab={'HALL PASS!',0},
 PassWhistle={'TWEEET!',1},
 PassTardy={'TARDY!',0},
 IdolLift={'TREASURE!',0},
 IdolDark={'',0.62},
 IdolWake={'...it woke up',1},
 CrownOn={'CROWNED!',0}, -- was 'ALL HAIL!' (owner 2026-10-27: avoid any misreading)
}
local function now()return workspace:GetServerTimeNow()end
-- A one-shot face for `seconds` (overrides any held face for that time).
function M.Face(p,mood,seconds)
 p:SetAttribute('FaceBeat',mood);p:SetAttribute('FaceBeatUntil',now()+(seconds or 1.5))
end
-- A held face (refreshed at 4 Hz while an item is held): never cuts a different, still-running face short.
function M.Hold(p,mood)
 local t=now();local cur=p:GetAttribute('FaceBeat');local untilAt=p:GetAttribute('FaceBeatUntil')or 0
 if cur~=mood and untilAt>t+.05 then return end
 p:SetAttribute('FaceBeat',mood);p:SetAttribute('FaceBeatUntil',math.max(untilAt,t+.5))
end
-- A screen reaction for the player's own client plus an optional face everyone sees.
function M.React(p,key,mood,seconds)
 if not p or not p.Parent then return end
 if mood then M.Face(p,mood,seconds)end
 local pop=M.TEXT[key]
 if pop and(pop[1]~=''or pop[2]>0)then
  p:SetAttribute('ReactPop',pop[1]~=''and pop[1]or nil);p:SetAttribute('ReactPopShake',pop[2]);p:SetAttribute('ReactPopAt',now())
 end
 p:SetAttribute('ItemReact',key);p:SetAttribute('ItemReactAt',now())
end
function M.Clear(p)
 for _,k in ipairs(M.KEYS)do p:SetAttribute(k,nil)end
end
return M
