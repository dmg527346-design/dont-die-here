local InputHints=require(game:GetService('ReplicatedStorage'):WaitForChild('InputHints'))
-- Van reward panels (Daily + Timed). Presentation only: the server (ReplicatedStorage.VanRewards) owns
-- streaks, playtime, claims and grants; this script shows state, plays the opening and asks to claim.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Tween=game:GetService('TweenService')
local Run=game:GetService('RunService')
local GS=game:GetService('GuiService')
local UIS=game:GetService('UserInputService')
local CAS=game:GetService('ContextActionService')
local PPS=game:GetService('ProximityPromptService')
local p=Players.LocalPlayer
local UI=require(RS:WaitForChild('NeonUI'))
local Audio=require(RS:WaitForChild('GameplayAudio'))
local CameraGuard=require(RS:WaitForChild('CameraInputGuard'))
-- Reward sounds: a dedicated set (Roblox-licensed ProSoundEffects / APM audio, playable in any game), used
-- only here so claiming feels different from everything else. Each cue is its own Sound, preloaded once.
local SFX_IDS={
 panelOpen={9116394545,.6},  -- soft magic chime cluster
 cardReady={9126073001,.5},  -- bright bell ding (a slot unlocked / ready toast)
 giftWhoosh={9126229255,.7}, -- fast airy whoosh as the gift flies out of the panel
 giftLand={9120873380,.55},  -- wooden box thunk on the floor
 giftSparkle={9126076030,.35},-- tiny sparkle burst on landing
 holdOpen={9125805579,.7},   -- rising whoosh build-up when you open it
 shakeTick={9126073318,.45}, -- bell ding, pitched up every shake (tension)
 burstLid={9120873624,.8},   -- chest lid flies open
 burstMagic={9116395089,.8}, -- big cluster of magic chimes
 itemPop={9126073001,.6},    -- each reward popping out (pitch climbs per item)
 coins={9113704038,.7},      -- coins pouring while tokens count up
 rare={9119447936,.7},       -- sparkle bell tree
 epic={1846266827,.6},       -- short fanfare
 legendary={92456794490177,.65},-- big win sting
 collect={9113728042,.75},   -- cash register
 collectShimmer={9116418035,.5},-- falling shimmer as the loot flies off
}
local SFX={}
do
 local SoundService=game:GetService('SoundService')
 local group=SoundService:FindFirstChild('GameplayUI')
 local folder=Instance.new('Folder');folder.Name='VanRewardSounds';folder.Parent=SoundService
 local list={}
 for name,cfg in SFX_IDS do
  local sd=Instance.new('Sound');sd.Name=name;sd.SoundId='rbxassetid://'..cfg[1];sd.Volume=cfg[2];sd.Parent=folder
  if group and group:IsA('SoundGroup')then sd.SoundGroup=group end
  SFX[name]=sd;table.insert(list,sd)
 end
 task.spawn(function()pcall(function()game:GetService('ContentProvider'):PreloadAsync(list)end)end)
end
-- pitch: playback speed (1 = normal); overlapping plays use a clone so rapid cues never cut each other off
local function sfx(name,pitch)
 local base=SFX[name];if not base then return end
 local sd=base.IsPlaying and base:Clone()or base
 if sd~=base then sd.Parent=base.Parent;sd.Ended:Once(function()sd:Destroy()end)end
 sd.PlaybackSpeed=pitch or 1;sd.TimePosition=0;sd:Play()
end
local colors=UI.Color
-- Layout (tune by screenshot) ------------------------------------------------------------------
local MAX_W,MAX_H,MARGIN,SIDE,HEADER_H,FOOTER_H=900,440,12,20,82,60
local DAY_CARD_W,DAY_GAP,SLOT_CARD_W,SLOT_GAP=112,10,128,10
local NEAR_DISTANCE=12
-- Motion ---------------------------------------------------------------------------------------
local SLIDE_IN,SLIDE_OUT,ROWS_START,ROW_STAGGER,POP_TIME=.36,.2,.18,.05,.26
local BOX_DROP,SHAKE_PULSES,MIN_BUILDUP,LAND_PAUSE=.55,4,2.2,.35
-- Ray strength per rarity: commons glow, legendaries blaze.
local RAY_ALPHA={common=.72,rare=.58,epic=.45,legendary=.3}
-- Art: the shop's own offer illustrations double as reward icons.
local ICON={tokens='rbxassetid://116174307880260',revives='rbxassetid://122888744965333',instantWin='rbxassetid://111911305328601'}
local NAMES={tokens='TOKENS',revives='REVIVE TOKEN',instantWin='INSTANT WIN'}
local ORDER={'tokens','revives','instantWin'}
local RARITY={
 common={Color3.fromRGB(190,200,214),'COMMON'},rare={Color3.fromRGB(80,176,255),'RARE'},
 epic={Color3.fromRGB(196,112,255),'EPIC'},legendary={Color3.fromRGB(255,204,70),'LEGENDARY'},
}
local KIND={
 Daily={title='DAILY REWARDS',sub='Claim once a day. Your streak keeps growing forever.',a=Color3.fromRGB(255,200,70),b=Color3.fromRGB(255,110,150),glyph='GIFT'},
 Timed={title='TIMED REWARDS',sub='Rewards unlock while you play, up to 6 hours per session.',a=Color3.fromRGB(80,220,255),b=Color3.fromRGB(140,110,255),glyph='TIME'},
}
local function rarityOf(r)return RARITY[r and r.rarity or 'common']or RARITY.common end
local function fmt(s)
 s=math.max(0,math.floor(s))
 local h,m,sec=s//3600,(s%3600)//60,s%60
 if h>0 then return string.format('%d:%02d:%02d',h,m,sec)end
 return string.format('%02d:%02d',m,sec)
end
local function short(s)
 s=math.floor(s);if s>=3600 then local h=s/3600;return(h==math.floor(h)and string.format('%d HR',h)or string.format('%.1f HR',h))end
 return string.format('%d MIN',math.max(1,s//60))
end
local function items(reward)
 local out={}
 if type(reward)~='table'then return out end
 for _,key in ORDER do local n=tonumber(reward[key])if n and n>0 then table.insert(out,{key=key,amount=n})end end
 return out
end
-- Remotes and state ------------------------------------------------------------------------------
local remotes
local function getRemotes()
 if remotes and remotes.Parent then return remotes end
 remotes=RS:FindFirstChild('VanRewards');return remotes
end
local state,stateClock=nil,0 -- state as last received, and os.clock() at receipt (for local ticking)
local timeOffset=0
local function serverNow()return os.time()+timeOffset end
local function session()
 if not state or not state.timed then return 0 end
 local t=state.timed;return math.min(t.maxSeconds or 21600,(t.sessionSeconds or 0)+(os.clock()-stateClock))
end
local function setState(s)
 if type(s)~='table'then return end
 -- A slow claim reply must not roll back a newer StateChanged push.
 -- Same-second snapshots are ordered by progress (claims and playtime only grow within a day/session).
 local function score(x)
  local n=0
  if type(x.timed)=='table'then for _,sl in x.timed.slots or{}do if sl.claimed then n+=1 end end end
  if type(x.daily)=='table'and not x.daily.canClaim then n+=1 end
  return n*1e6+(type(x.timed)=='table'and x.timed.sessionSeconds or 0)
 end
 if state and state.serverTime and s.serverTime and(s.serverTime<state.serverTime or s.serverTime==state.serverTime and score(s)<score(state))then return end
 state=s;stateClock=os.clock()
 if s.serverTime then timeOffset=s.serverTime-os.time()end
end
-- Studio-only mock so the panels can be previewed before the server is installed.
local mock
if Run:IsStudio()then
 local function r(t,v,i,rar)return{tokens=t,revives=v,instantWin=i,rarity=rar}end
 local claimedSlots,streak,canClaim={},4,true -- streak = today's day (server semantics)
 local start=os.clock()-25*60
 local slots={}
 for _,slot in require(RS.RewardsConfig).TimedSlots do
  table.insert(slots,{slot.id,slot.at,require(RS.RewardsConfig).Timed(slot.id)})
 end
 local function dayReward(d)local c=(d-1)%7+1;local cyc=(d-1)//7;return r(({30,40,50,65,80,100,130})[c]+math.min(cyc,14)*5,(c==4 or c==7)and 1 or 0,0,c==7 and 'epic'or c>=5 and 'rare'or 'common')end
 local function build()
  local track={};local first=(streak-1)//7*7+1
  for d=first,first+6 do table.insert(track,{day=d,reward=dayReward(d),claimed=d<streak or(d==streak and not canClaim)})end
  local played=os.clock()-start;local list={}
  for _,s in slots do table.insert(list,{id=s[1],at=s[2],reward=s[3],claimed=claimedSlots[s[1]]==true,ready=played>=s[2]})end
  local nextSlot=false;for _,s in list do if not s.claimed and not nextSlot then nextSlot={id=s.id,at=s.at,reward=s.reward,remainingSeconds=math.max(0,s.at-played)}end end
  return{serverTime=os.time(),daily={streak=streak,canClaim=canClaim,nextClaimAt=os.time()+(canClaim and 0 or 3600*5+333),track=track},
   timed={sessionSeconds=played,maxSeconds=21600,slots=list},teaser={daily={day=streak+(canClaim and 0 or 1),reward=dayReward(streak+(canClaim and 0 or 1)),rarePossible=true},timed=nextSlot}}
 end
 mock={
  GetState=function()return{ok=true,state=build()}end,
  Claim=function(kind,id)
   task.wait(.35)
   if kind=='daily'then if not canClaim then return{ok=false,reason='Already claimed today.'}end;canClaim=false;return{ok=true,reward=dayReward(streak),state=build()}end
   for _,s in slots do if s[1]==id then if claimedSlots[id]then return{ok=false,reason='Already claimed.'}end;if os.clock()-start<s[2]then return{ok=false,reason='Not ready yet.'}end;claimedSlots[id]=true;return{ok=true,reward=s[3],state=build()}end end
   return{ok=false,reason='Unknown reward.'}
  end,
 }
end
local function useMock()return mock~=nil and getRemotes()==nil and script:GetAttribute('Mock')==true end
local function fetchState()
 if useMock()then return mock.GetState().state end
 local r=getRemotes();local fn=r and r:FindFirstChild('GetState');if not fn then return nil end
 local ok,s=pcall(function()return fn:InvokeServer()end)
 if not ok or type(s)~='table'then return nil end
 -- GetState answers {ok,state}; StateChanged and Claim carry the state itself.
 if s.ok~=nil then return s.ok and s.state or nil end
 return s
end
-- One refresh in flight at a time, at most every 5 s (the midnight check runs 4x a second).
local refreshing,lastRefresh=false,-math.huge
local onRefreshed -- set once render exists
local function refreshSoon()
 if refreshing or os.clock()-lastRefresh<5 then return end
 refreshing=true;lastRefresh=os.clock()
 task.spawn(function()
  local s=fetchState();refreshing=false
  if s then setState(s);if onRefreshed then onRefreshed()end end
 end)
end
-- Daily `streak` is today's day: the day to claim when canClaim, or the day already claimed today.
local function todayDay()return state and state.daily and math.max(1,state.daily.streak or 1)or 1 end
local function claim(kind,id)
 if useMock()then return mock.Claim(kind,id)end
 local r=getRemotes();local fn=r and r:FindFirstChild('Claim');if not fn then return{ok=false,reason='Rewards are unavailable right now.'}end
 local ok,res=pcall(function()return fn:InvokeServer(kind,id)end)
 if not ok or type(res)~='table'then return{ok=false,reason='Rewards are unavailable right now.'}end
 return res
end
-- Screen -------------------------------------------------------------------------------------------
local gui=Instance.new('ScreenGui');gui.Name='VanRewards';gui.ResetOnSpawn=false;gui.DisplayOrder=135;gui.IgnoreGuiInset=true;gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling;gui.Parent=p:WaitForChild('PlayerGui')
local backdrop=UI.backdrop(gui,.5)
local panel=UI.plate(gui,'Panel',24);panel.AnchorPoint=Vector2.new(.5,.5);panel.Position=UDim2.fromScale(.5,.5);panel.Visible=false
local headerIcon=Instance.new('Frame');headerIcon.Name='HeaderIcon';headerIcon.Position=UDim2.fromOffset(SIDE,18);headerIcon.Size=UDim2.fromOffset(50,50);headerIcon.BackgroundColor3=Color3.new(1,1,1);headerIcon.Parent=panel
UI.corner(headerIcon,UDim.new(1,0));UI.stroke(headerIcon,colors.ink,2.5,0)
local headerGradient=Instance.new('UIGradient');headerGradient.Rotation=90;headerGradient.Parent=headerIcon
local headerGlyph=UI.text(headerIcon,'Glyph','',UI.Font.Display,15,colors.text);headerGlyph.Size=UDim2.fromScale(1,1);headerGlyph.TextXAlignment=Enum.TextXAlignment.Center;UI.outline(headerGlyph,1.6)
local title=UI.text(panel,'Title','',UI.Font.Display,32);title.Position=UDim2.fromOffset(SIDE+62,14);title.Size=UDim2.new(1,-330,0,36);UI.fit(title,18,32);UI.outline(title,2)
local subtitle=UI.text(panel,'Subtitle','',UI.Font.Bold,15,Color3.fromRGB(214,216,228));subtitle.Position=UDim2.fromOffset(SIDE+62,50);subtitle.Size=UDim2.new(1,-330,0,20);UI.fit(subtitle,11,15);UI.outline(subtitle,1.2,.3)
local pill=UI.text(panel,'Pill','',UI.Font.Display,17,colors.gold);pill.AnchorPoint=Vector2.new(1,0);pill.Position=UDim2.new(1,-70,0,26);pill.Size=UDim2.fromOffset(0,36);pill.AutomaticSize=Enum.AutomaticSize.X
pill.TextXAlignment=Enum.TextXAlignment.Center;pill.BackgroundTransparency=0;pill.BackgroundColor3=colors.pill;UI.corner(pill,UDim.new(1,0));UI.stroke(pill,Color3.fromRGB(70,70,86),1.5,0)
do local pd=Instance.new('UIPadding');pd.PaddingLeft=UDim.new(0,16);pd.PaddingRight=UDim.new(0,16);pd.Parent=pill end
local divider=Instance.new('Frame');divider.Name='Divider';divider.BorderSizePixel=0;divider.BackgroundColor3=Color3.new(1,1,1);divider.BackgroundTransparency=.9;divider.Position=UDim2.fromOffset(SIDE,HEADER_H-6);divider.Size=UDim2.new(1,-SIDE*2,0,1);divider.Parent=panel
-- Session bar (Timed only): playtime toward the 6 hour cap with a notch per reward.
local bar=Instance.new('Frame');bar.Name='SessionBar';bar.BackgroundColor3=colors.cardLow;bar.BorderSizePixel=0;bar.Position=UDim2.fromOffset(SIDE,HEADER_H+8);bar.Size=UDim2.new(1,-SIDE*2,0,14);bar.Parent=panel
UI.corner(bar,UDim.new(1,0));UI.stroke(bar,Color3.fromRGB(60,60,76),1.5,0)
local barFill=Instance.new('Frame');barFill.Name='Fill';barFill.BorderSizePixel=0;barFill.BackgroundColor3=Color3.new(1,1,1);barFill.Size=UDim2.fromScale(0,1);barFill.Parent=bar;UI.corner(barFill,UDim.new(1,0))
local barGradient=Instance.new('UIGradient');barGradient.Parent=barFill
local list=Instance.new('ScrollingFrame');list.Name='Rewards';list.BackgroundTransparency=1;list.BorderSizePixel=0;list.ScrollBarThickness=5;list.ScrollBarImageColor3=Color3.fromRGB(150,150,170)
list.ScrollingDirection=Enum.ScrollingDirection.X;list.Selectable=false;list.AutomaticCanvasSize=Enum.AutomaticSize.X;list.CanvasSize=UDim2.new();list.Parent=panel
local row=Instance.new('UIListLayout');row.FillDirection=Enum.FillDirection.Horizontal;row.Padding=UDim.new(0,DAY_GAP);row.SortOrder=Enum.SortOrder.LayoutOrder;row.VerticalAlignment=Enum.VerticalAlignment.Center;row.Parent=list
do local pd=Instance.new('UIPadding');pd.PaddingLeft=UDim.new(0,8);pd.PaddingRight=UDim.new(0,8);pd.PaddingTop=UDim.new(0,10);pd.PaddingBottom=UDim.new(0,10);pd.Parent=list end
local footer=Instance.new('Frame');footer.Name='Footer';footer.BackgroundTransparency=1;footer.Parent=panel
local footerText=UI.text(footer,'Teaser','',UI.Font.Display,21,colors.gold);footerText.Size=UDim2.new(1,-250,1,0);footerText.TextYAlignment=Enum.TextYAlignment.Center;UI.fit(footerText,12,21);UI.outline(footerText,1.8)
local footerHint=UI.text(footer,'Hint','',UI.Font.Bold,13,Color3.fromRGB(200,202,216));footerHint.Size=UDim2.new(1,-250,0,16);footerHint.Position=UDim2.new(0,0,1,-16);UI.fit(footerHint,10,13);UI.outline(footerHint,1,.35)
local mainButton=UI.button(footer,'Claim','CLAIM','buy');mainButton.AnchorPoint=Vector2.new(1,.5);mainButton.Position=UDim2.new(1,0,.5,0);mainButton.Size=UDim2.fromOffset(220,48)
local closeButton=UI.closeButton(panel,'Close',50);closeButton.Position=UDim2.new(1,-30,0,30);closeButton.Modal=true
-- Opening scene ------------------------------------------------------------------------------------
local scene=Instance.new('Frame');scene.Name='Opening';scene.BackgroundColor3=Color3.new(0,0,0);scene.BackgroundTransparency=1;scene.Size=UDim2.new(1,0,1,0);scene.Visible=false;scene.ZIndex=50;scene.Parent=gui
local flash=Instance.new('Frame');flash.Name='Flash';flash.BackgroundColor3=Color3.new(1,1,1);flash.BackgroundTransparency=1;flash.Size=UDim2.fromScale(1,1);flash.ZIndex=80;flash.Parent=scene
local stage=Instance.new('Frame');stage.Name='Stage';stage.BackgroundTransparency=1;stage.AnchorPoint=Vector2.new(.5,.5);stage.Position=UDim2.fromScale(.5,.5);stage.Size=UDim2.fromOffset(520,520);stage.ZIndex=51;stage.Parent=scene
local stageScale=Instance.new('UIScale');stageScale.Parent=stage
local rays=Instance.new('Frame');rays.Name='Rays';rays.BackgroundTransparency=1;rays.AnchorPoint=Vector2.new(.5,.5);rays.Position=UDim2.fromScale(.5,.5);rays.Size=UDim2.fromOffset(10,10);rays.ZIndex=51;rays.Parent=stage
local rayParts={}
for i=1,12 do
 local r=Instance.new('Frame');r.Name='Ray';r.AnchorPoint=Vector2.new(.5,.5);r.Position=UDim2.fromScale(.5,.5);r.Size=UDim2.fromOffset(46,760);r.Rotation=i*15;r.BorderSizePixel=0;r.BackgroundColor3=Color3.new(1,1,1);r.BackgroundTransparency=1;r.ZIndex=51;r.Parent=rays
 local g=Instance.new('UIGradient');g.Rotation=90;g.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.5,.15),NumberSequenceKeypoint.new(1,1)});g.Parent=r
 table.insert(rayParts,r)
end
local halos={}
for i,s in {300,230,170}do
 local h=Instance.new('Frame');h.Name='Halo';h.AnchorPoint=Vector2.new(.5,.5);h.Position=UDim2.fromScale(.5,.5);h.Size=UDim2.fromOffset(s,s);h.BackgroundColor3=Color3.new(1,1,1);h.BackgroundTransparency=1;h.ZIndex=52;h.Parent=stage;UI.corner(h,UDim.new(1,0));halos[i]=h
end
local ring=Instance.new('Frame');ring.Name='Shockwave';ring.AnchorPoint=Vector2.new(.5,.5);ring.Position=UDim2.fromScale(.5,.5);ring.Size=UDim2.fromOffset(60,60);ring.BackgroundTransparency=1;ring.ZIndex=53;ring.Parent=stage;UI.corner(ring,UDim.new(1,0))
local ringStroke=UI.stroke(ring,Color3.new(1,1,1),8,1)
-- The gift box: body + ribbon, a lid (with bow) that flies off, all frames so it can squash and shake.
local box=Instance.new('Frame');box.Name='Box';box.BackgroundTransparency=1;box.AnchorPoint=Vector2.new(.5,.5);box.Position=UDim2.fromScale(.5,.56);box.Size=UDim2.fromOffset(220,200);box.ZIndex=55;box.Parent=stage
local boxScale=Instance.new('UIScale');boxScale.Parent=box
local function block(parent,name,pos,size,color,z,radius)
 local f=Instance.new('Frame');f.Name=name;f.Position=pos;f.Size=size;f.BackgroundColor3=color;f.BorderSizePixel=0;f.ZIndex=z;f.Parent=parent
 if radius then UI.corner(f,radius)end;return f
end
local body=block(box,'Body',UDim2.new(.5,-90,1,-130),UDim2.fromOffset(180,130),Color3.new(1,1,1),56,UDim.new(0,18));UI.stroke(body,colors.ink,4,0)
local bodyGradient=Instance.new('UIGradient');bodyGradient.Rotation=90;bodyGradient.Parent=body
block(body,'RibbonV',UDim2.new(.5,-17,0,0),UDim2.new(0,34,1,0),Color3.fromRGB(255,214,90),57)
local shine=block(body,'Shine',UDim2.fromOffset(14,12),UDim2.fromOffset(18,60),Color3.new(1,1,1),57,UDim.new(1,0));shine.BackgroundTransparency=.65
local lid=Instance.new('Frame');lid.Name='Lid';lid.BackgroundTransparency=1;lid.AnchorPoint=Vector2.new(.5,1);lid.Position=UDim2.new(.5,0,1,-122);lid.Size=UDim2.fromOffset(206,96);lid.ZIndex=58;lid.Parent=box
local lidTop=block(lid,'Top',UDim2.new(0,0,1,-50),UDim2.new(1,0,0,50),Color3.new(1,1,1),58,UDim.new(0,14));UI.stroke(lidTop,colors.ink,4,0)
local lidGradient=Instance.new('UIGradient');lidGradient.Rotation=90;lidGradient.Parent=lidTop
block(lidTop,'RibbonV',UDim2.new(.5,-19,0,0),UDim2.new(0,38,1,0),Color3.fromRGB(255,214,90),59)
for side=-1,1,2 do
 local loop=block(lid,'BowLoop',UDim2.new(.5,side*34-26,0,4),UDim2.fromOffset(52,40),Color3.fromRGB(255,214,90),59,UDim.new(1,0));loop.Rotation=side*-22;UI.stroke(loop,colors.ink,4,0)
end
local knot=block(lid,'Knot',UDim2.new(.5,-14,0,14),UDim2.fromOffset(28,28),Color3.fromRGB(255,236,150),60,UDim.new(1,0));UI.stroke(knot,colors.ink,4,0)
local lidScale=Instance.new('UIScale');lidScale.Parent=lid
local caption=UI.text(scene,'Caption','',UI.Font.Display,34,colors.text);caption.AnchorPoint=Vector2.new(.5,0);caption.Position=UDim2.new(.5,0,.08,0);caption.Size=UDim2.new(.9,0,0,46);caption.TextXAlignment=Enum.TextXAlignment.Center;caption.ZIndex=70;UI.fit(caption,18,40);UI.outline(caption,2.5)
local tease=UI.text(scene,'Tease','',UI.Font.Display,22,colors.gold);tease.AnchorPoint=Vector2.new(.5,0);tease.Position=UDim2.new(.5,0,.08,52);tease.Size=UDim2.new(.9,0,0,30);tease.TextXAlignment=Enum.TextXAlignment.Center;tease.ZIndex=70;UI.fit(tease,12,22);UI.outline(tease,1.4)
local rarityBanner=UI.text(scene,'Rarity','',UI.Font.Display,44,colors.text);rarityBanner.AnchorPoint=Vector2.new(.5,.5);rarityBanner.Position=UDim2.new(.5,0,.5,-170);rarityBanner.Size=UDim2.fromOffset(520,60);rarityBanner.TextXAlignment=Enum.TextXAlignment.Center;rarityBanner.ZIndex=72;rarityBanner.Visible=false;UI.fit(rarityBanner,24,52);UI.outline(rarityBanner,3)
local rarityScale=Instance.new('UIScale');rarityScale.Parent=rarityBanner
local loot=Instance.new('Frame');loot.Name='Loot';loot.BackgroundTransparency=1;loot.AnchorPoint=Vector2.new(.5,.5);loot.Position=UDim2.fromScale(.5,.5);loot.Size=UDim2.new(.94,0,0,220);loot.ZIndex=70;loot.Parent=scene
local lootRow=Instance.new('UIListLayout');lootRow.FillDirection=Enum.FillDirection.Horizontal;lootRow.HorizontalAlignment=Enum.HorizontalAlignment.Center;lootRow.Padding=UDim.new(0,18);lootRow.VerticalAlignment=Enum.VerticalAlignment.Center;lootRow.SortOrder=Enum.SortOrder.LayoutOrder;lootRow.Parent=loot
local collect=UI.button(scene,'Collect','COLLECT','use');collect.AnchorPoint=Vector2.new(.5,1);collect.Position=UDim2.new(.5,0,1,-28);collect.Size=UDim2.fromOffset(240,56);collect.ZIndex=75;collect.Visible=false
local sparkles=Instance.new('Frame');sparkles.Name='Sparkles';sparkles.BackgroundTransparency=1;sparkles.Size=UDim2.fromScale(1,1);sparkles.ZIndex=74;sparkles.Parent=scene
-- Toast: a playtime reward is ready while the panel is closed (teases a trip back to the van).
local toast=Instance.new('Frame');toast.Name='ReadyToast';toast.AnchorPoint=Vector2.new(.5,0);toast.Position=UDim2.new(.5,0,0,-90);toast.Size=UDim2.fromOffset(360,62);toast.BackgroundColor3=colors.plate;toast.Visible=false;toast.Parent=gui
UI.corner(toast,UDim.new(1,0));local toastRim=UI.stroke(toast,KIND.Timed.a,3,0)
local toastIcon=Instance.new('ImageLabel');toastIcon.Name='Icon';toastIcon.BackgroundTransparency=1;toastIcon.Position=UDim2.fromOffset(8,7);toastIcon.Size=UDim2.fromOffset(48,48);toastIcon.ScaleType=Enum.ScaleType.Crop;toastIcon.Parent=toast;UI.corner(toastIcon,UDim.new(1,0))
local toastText=UI.text(toast,'Text','',UI.Font.Display,18,colors.text);toastText.Position=UDim2.fromOffset(66,8);toastText.Size=UDim2.new(1,-84,0,26);UI.fit(toastText,11,18);UI.outline(toastText,1.3)
local toastSub=UI.text(toast,'Sub','Open TIMED REWARDS in the van',UI.Font.Body,13,colors.muted);toastSub.Position=UDim2.fromOffset(66,34);toastSub.Size=UDim2.new(1,-84,0,18);UI.fit(toastSub,9,13)
-- Panel logic ---------------------------------------------------------------------------------------
local open,kind,activeTerminal,busy=false,'Daily',nil,false
local tweens={};local animationToken=0;local previousFocus;local entranceStart=-math.huge
local cardRefs={} -- id -> {card,status,claim,fill} for live ticking without rebuilding
local function cancelTweens()for _,t in tweens do t:Cancel()end;table.clear(tweens)end
local function play(o,info,props)local t=Tween:Create(o,info,props);t:Play();return t end
local function anim(o,info,props)local t=play(o,info,props);table.insert(tweens,t);return t end
local function platform()
 return InputHints.Get()
end
local function selectable(o)
 if not(o and o:IsA('GuiObject')and o.Selectable and o:IsDescendantOf(game))then return false end
 local x=o;while x and not x:IsA('LayerCollector')do if x:IsA('GuiObject')and not x.Visible then return false end;x=x.Parent end
 return x~=nil and x.Enabled
end
local function selectSafe(o)if o==nil or selectable(o)then GS.SelectedObject=o end end
local function nearTerminal()
 local ch=p.Character;local root=ch and ch:FindFirstChild('HumanoidRootPart');local h=ch and ch:FindFirstChildOfClass('Humanoid')
 return root~=nil and h~=nil and h.Health>0 and not p:GetAttribute('RoundDead')and activeTerminal~=nil and activeTerminal.Parent~=nil and(root.Position-activeTerminal.Position).Magnitude<NEAR_DISTANCE
end
local function rewardChips(parent,reward,size,z)
 -- Small icon + amount stack shown on a card (the tease of what's inside).
 local holder=Instance.new('Frame');holder.Name='Loot';holder.BackgroundTransparency=1;holder.Size=UDim2.new(1,0,0,size);holder.ZIndex=z;holder.Parent=parent
 local l=Instance.new('UIListLayout');l.FillDirection=Enum.FillDirection.Horizontal;l.HorizontalAlignment=Enum.HorizontalAlignment.Center;l.Padding=UDim.new(0,-10);l.Parent=holder
 local list_=items(reward)
 for i,it in list_ do
  local icon=Instance.new('ImageLabel');icon.Name=it.key;icon.LayoutOrder=i;icon.BackgroundColor3=colors.ink;icon.Size=UDim2.fromOffset(i==1 and size or size*.72,i==1 and size or size*.72);icon.Image=ICON[it.key];icon.ScaleType=Enum.ScaleType.Crop;icon.ZIndex=z+(#list_-i);icon.Parent=holder
  UI.corner(icon,UDim.new(1,0));UI.stroke(icon,colors.ink,2,0)
 end
 return holder
end
local function rewardLine(reward)
 local parts={};for _,it in items(reward)do table.insert(parts,(it.key=='tokens'and('+'..it.amount)or('+'..it.amount..' '..(it.key=='revives'and 'REVIVE'or 'WIN'))))end
 return table.concat(parts,'  ')
end
local phone=false -- set by layout(): touch screens get small wrapping cards
local function layout()
 local v=gui.AbsoluteSize;local w=math.min(MAX_W,v.X-MARGIN*2);local h=math.min(MAX_H,v.Y-MARGIN*2)
 phone=platform()=='touch'
 if phone then w=math.min(w,math.floor(v.X*.84))end
 panel.Size=UDim2.fromOffset(w,h)
 list.ScrollingDirection=phone and Enum.ScrollingDirection.Y or Enum.ScrollingDirection.X
 list.AutomaticCanvasSize=phone and Enum.AutomaticSize.Y or Enum.AutomaticSize.X
 row.Wraps=phone;row.HorizontalAlignment=phone and Enum.HorizontalAlignment.Center or Enum.HorizontalAlignment.Left
 row.VerticalAlignment=phone and Enum.VerticalAlignment.Top or Enum.VerticalAlignment.Center
 local compact=h<430 or w<560
 local header=compact and 64 or HEADER_H
 headerIcon.Size=UDim2.fromOffset(compact and 38 or 50,compact and 38 or 50);headerIcon.Position=UDim2.fromOffset(SIDE,compact and 13 or 18)
 local textX=SIDE+(compact and 48 or 62);local reserve=pill.AbsoluteSize.X+112
 title.Position=UDim2.fromOffset(textX,compact and 9 or 16);title.Size=UDim2.new(1,-(textX+reserve),0,compact and 28 or 34)
 subtitle.Visible=not compact or h>=360;subtitle.Position=UDim2.fromOffset(textX,compact and 36 or 50);subtitle.Size=UDim2.new(1,-(textX+reserve),0,compact and 16 or 20)
 pill.Position=UDim2.new(1,-66,0,compact and 15 or 26);pill.Size=UDim2.fromOffset(0,compact and 30 or 36);pill.TextSize=compact and 14 or 16
 divider.Position=UDim2.fromOffset(SIDE,header-6)
 local barH=kind=='Timed'and 26 or 0
 bar.Visible=kind=='Timed';bar.Position=UDim2.fromOffset(SIDE,header+8)
 local footH=compact and 54 or FOOTER_H
 footer.Position=UDim2.new(0,SIDE,1,-footH-10);footer.Size=UDim2.new(1,-SIDE*2,0,footH)
 mainButton.Size=UDim2.fromOffset(compact and 170 or 220,compact and 42 or 48)
 footerText.Size=UDim2.new(1,-(mainButton.Size.X.Offset+16),1,-16);footerHint.Size=UDim2.new(1,-(mainButton.Size.X.Offset+16),0,16)
 list.Position=UDim2.fromOffset(SIDE-8,header+barH+2);list.Size=UDim2.new(1,-(SIDE-8)*2,1,-(header+barH+footH+16))
 return compact
end
local render,close,startOpening,finishOpening,dropGift,endScene
local gifts={} -- [kind..':'..slotId] = dropped, unopened gift in the van (this player's world only)
local function giftKey(kind,id)return kind..':'..tostring(id)end
local focusCard -- defined below; picks the card controller focus lands on
local function cardFrame(cell,accent,claimable)
 local card=Instance.new('Frame');card.Name='Card';card.AnchorPoint=Vector2.new(.5,.5);card.Position=UDim2.fromScale(.5,.5);card.Size=UDim2.fromScale(1,1);card.BackgroundColor3=Color3.new(1,1,1);card.BorderSizePixel=0;card.Parent=cell
 UI.corner(card,16);local rim=UI.stroke(card,accent,claimable and 3 or 1.5,claimable and 0 or .45);rim.Name='Rim'
 local tint=Instance.new('UIGradient');tint.Rotation=90;tint.Color=ColorSequence.new(accent:Lerp(colors.cardLow,claimable and .35 or .7),colors.card);tint.Parent=card
 local pop=Instance.new('UIScale');pop.Name='Pop';pop.Parent=card
 return card,rim
end
local function statusTag(card,text,color,textColor)
 local t=UI.text(card,'Tag',text,UI.Font.Title,12,textColor or colors.ink);t.AnchorPoint=Vector2.new(.5,1);t.Position=UDim2.new(.5,0,1,phone and -4 or -8);t.Size=UDim2.new(1,phone and -8 or -16,0,phone and 20 or 24)
 t.TextXAlignment=Enum.TextXAlignment.Center;t.BackgroundTransparency=0;t.BackgroundColor3=color;UI.corner(t,UDim.new(1,0));UI.fit(t,9,13);return t
end
-- Locked cards stay readable (that's the tease); claimed ones dim further.
local LOCK_SHADE,CLAIMED_SHADE=.68,.45
local function lockShade(card)
 local s=Instance.new('Frame');s.Name='LockShade';s.Size=UDim2.fromScale(1,1);s.BackgroundColor3=Color3.new(0,0,0);s.BackgroundTransparency=LOCK_SHADE;s.ZIndex=4;s.Parent=card;UI.corner(s,16)
 return s
end
-- Card sizing: fill the row when it fits (7 days / 9 slots), otherwise scroll at the minimum width.
local CARD_MIN_W,CARD_MAX_W,CARD_MIN_H,CARD_MAX_H=112,176,168,230
local function cardSize(count,gap)
 if phone then
  -- Phone: five small cards per row, two rows in view, scrolling down.
  local per=math.max(3,math.min(5,count));local cw=math.floor((list.AbsoluteSize.X-12-(per-1)*gap)/per)
  return math.min(cw,120),math.max(84,math.floor((list.AbsoluteSize.Y-gap-6)/2))
 end
 local w=math.floor((list.AbsoluteSize.X-16-(count-1)*gap)/math.max(1,count))
 return math.clamp(w,CARD_MIN_W,CARD_MAX_W),math.clamp(list.AbsoluteSize.Y-24,CARD_MIN_H,CARD_MAX_H)
end
-- Heading, reward art, amount and rarity, centred in the space above the bottom tag/button.
local function cardContent(card,headText,headColor,reward,w,h)
 local r=rarityOf(reward)
 if phone then
  -- Small phone card: heading, art, amount; the rarity line is dropped.
  local head=UI.text(card,'Head',headText,UI.Font.Display,13,headColor);head.Position=UDim2.fromOffset(4,4);head.Size=UDim2.new(1,-8,0,15);head.TextXAlignment=Enum.TextXAlignment.Center;UI.fit(head,8,13);UI.outline(head,1)
  local icon=math.clamp(h-4-15-2-14-2-28,20,40)
  local chips=rewardChips(card,reward,icon,3);chips.Position=UDim2.fromOffset(0,21)
  local amt=UI.text(card,'Amount',rewardLine(reward),UI.Font.Display,12,colors.gold);amt.Position=UDim2.fromOffset(4,21+icon+1);amt.Size=UDim2.new(1,-8,0,14);amt.TextXAlignment=Enum.TextXAlignment.Center;UI.fit(amt,7,12);UI.outline(amt,1)
  return
 end
 local icon=math.clamp(math.floor(w*.56),46,92)
 local block=26+icon+8+30+16
 local top=math.max(8,math.floor((h-44-block)/2))
 local head=UI.text(card,'Head',headText,UI.Font.Display,18,headColor);head.Position=UDim2.fromOffset(6,top);head.Size=UDim2.new(1,-12,0,22);head.TextXAlignment=Enum.TextXAlignment.Center;UI.fit(head,10,18);UI.outline(head,1.3)
 local chips=rewardChips(card,reward,icon,3);chips.Position=UDim2.fromOffset(0,top+26)
 local amt=UI.text(card,'Amount',rewardLine(reward),UI.Font.Display,17,colors.gold);amt.Position=UDim2.fromOffset(6,top+26+icon+6);amt.Size=UDim2.new(1,-12,0,30);amt.TextXAlignment=Enum.TextXAlignment.Center;UI.fit(amt,9,17);UI.outline(amt,1.2)
 local rar=UI.text(card,'Rarity',r[2],UI.Font.Title,12,r[1]:Lerp(Color3.new(1,1,1),.25));rar.Position=UDim2.fromOffset(6,top+26+icon+38);rar.Size=UDim2.new(1,-12,0,14);rar.TextXAlignment=Enum.TextXAlignment.Center;UI.fit(rar,8,12);UI.outline(rar,1)
end
local function onCardActivated(id)
 if busy or not open then return end
 if kind=='Daily'then
  if not(state and state.daily and state.daily.canClaim)then Audio.Play('UiError');return end
  -- Past UTC midnight the card on screen is stale (new day or reset streak): refresh before opening.
  if(state.daily.nextClaimAt or math.huge)-serverNow()<=0 then refreshSoon();return end
  dropGift('daily',nil)
 else
  local slot;for _,s in state.timed.slots do if s.id==id then slot=s end end
  if not slot or slot.claimed or session()<slot.at then Audio.Play('UiError');return end
  dropGift('timed',slot.id)
 end
end
local function makeClickable(card,id,label)
 local b=UI.button(card,'Claim_'..tostring(id),label,'use');b.AnchorPoint=Vector2.new(.5,1);b.Position=UDim2.new(.5,0,1,phone and -4 or -8);b.Size=UDim2.new(1,phone and -8 or -16,0,phone and 22 or 32);b.ZIndex=6
 b.Activated:Connect(function()Audio.Play('UiClick');onCardActivated(id)end)
 -- Ready cards bob and glow so the eye finds them first.
 local rim=card:FindFirstChild('Rim')
 if rim then table.insert(tweens,play(rim,TweenInfo.new(.7,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,-1,true),{Thickness=5}))end
 return b
end
render=function()
 if not state then return end
 local compact=layout()
 local focus=GS.SelectedObject;local focusName=focus and focus:IsDescendantOf(list)and focus.Name
 for _,x in list:GetChildren()do if x:IsA('GuiObject')then x:Destroy()end end
 table.clear(cardRefs)
 local k=KIND[kind]
 title.Text=k.title;subtitle.Text=k.sub;headerGlyph.Text=k.glyph;headerGradient.Color=ColorSequence.new(k.a,k.b)
 barGradient.Color=ColorSequence.new(k.a,k.b)
 local cells={}
 local cardH=math.max(150,list.AbsoluteSize.Y-24)
 if kind=='Daily'then
  local d=state.daily
  local day=todayDay()
  local done=d.canClaim and day-1 or day
  pill.Text=done==0 and 'START YOUR STREAK'or('STREAK  '..done..(done==1 and ' DAY'or ' DAYS'))
  row.Padding=UDim.new(0,DAY_GAP)
  for i,entry in d.track or{}do
   local today=not entry.claimed and d.canClaim and entry.day==day
   local r=rarityOf(entry.reward);local accent=today and k.a or r[1]
   local cw,ch=cardSize(#d.track,DAY_GAP)
   local cell=Instance.new('Frame');cell.Name='Day_'..entry.day;cell.LayoutOrder=i;cell.BackgroundTransparency=1;cell.Size=UDim2.fromOffset(cw,ch);cell.Parent=list;table.insert(cells,cell)
   local card=cardFrame(cell,accent,today)
   local big=(entry.day%7)==0
   cardContent(card,big and('DAY '..entry.day..' ★')or('DAY '..entry.day),today and colors.text or big and colors.gold or colors.text,entry.reward,cw,ch)
   if entry.claimed then lockShade(card).BackgroundTransparency=CLAIMED_SHADE;statusTag(card,'CLAIMED',colors.green).ZIndex=5
   elseif today and gifts[giftKey('daily',nil)]then statusTag(card,'IN THE VAN!',k.a).ZIndex=5
   elseif today then makeClickable(card,entry.day,'CLAIM!')
   else lockShade(card);statusTag(card,entry.day==day+1 and 'TOMORROW'or 'LOCKED',colors.grey,colors.text).ZIndex=5 end
   cardRefs[entry.day]={card=card}
  end
  if d.canClaim then
   footerText.Text='Day '..day..' is ready: '..(state.teaser and state.teaser.daily and rewardLine(state.teaser.daily.reward)or 'open your gift!')
   mainButton.Text='CLAIM DAY '..day;mainButton.Visible=not gifts[giftKey('daily',nil)]
  else
   mainButton.Visible=false
  end
  footerHint.Text='Miss a day and the streak starts again at day 1.'
 else
  local t=state.timed
  row.Padding=UDim.new(0,SLOT_GAP)
  for i,slot in t.slots or{}do
   local r=rarityOf(slot.reward);local ready=not slot.claimed and session()>=slot.at
   local accent=ready and k.a or r[1]
   local cw,ch=cardSize(#t.slots,SLOT_GAP)
   local cell=Instance.new('Frame');cell.Name='Slot_'..slot.id;cell.LayoutOrder=i;cell.BackgroundTransparency=1;cell.Size=UDim2.fromOffset(cw,ch);cell.Parent=list;table.insert(cells,cell)
   local card=cardFrame(cell,accent,ready)
   cardContent(card,short(slot.at),colors.text,slot.reward,cw,ch)
   local ref={card=card,slot=slot}
   if slot.claimed then lockShade(card).BackgroundTransparency=CLAIMED_SHADE;statusTag(card,'CLAIMED',colors.green).ZIndex=5
   elseif ready and gifts[giftKey('timed',slot.id)]then statusTag(card,'IN THE VAN!',k.a).ZIndex=5
   elseif ready then ref.claim=makeClickable(card,slot.id,'CLAIM!')
   else
    lockShade(card)
    -- Progress strip + live countdown on locked slots.
    local track=Instance.new('Frame');track.Name='Progress';track.AnchorPoint=Vector2.new(.5,1);track.Position=UDim2.new(.5,0,1,phone and -27 or -38);track.Size=UDim2.new(1,phone and -12 or -20,0,phone and 4 or 8);track.BackgroundColor3=colors.cardLow;track.ZIndex=5;track.Parent=card;UI.corner(track,UDim.new(1,0))
    local fill=Instance.new('Frame');fill.Name='Fill';fill.BackgroundColor3=k.a;fill.Size=UDim2.fromScale(0,1);fill.ZIndex=6;fill.Parent=track;UI.corner(fill,UDim.new(1,0))
    ref.fill=fill;ref.status=statusTag(card,'',colors.grey,colors.text);ref.status.ZIndex=5
   end
   cardRefs[slot.id]=ref
  end
  local nextSlot=state.teaser and state.teaser.timed
  local readyCount=0;for _,s in t.slots or{}do if not s.claimed and session()>=s.at and not gifts[giftKey('timed',s.id)]then readyCount+=1 end end
  mainButton.Visible=readyCount>0;mainButton.Text=readyCount>1 and('CLAIM ('..readyCount..')')or 'CLAIM'
  footerHint.Text='Playtime keeps counting through missions. Up to 6 hours each session.'
 end
 -- Rebuilds (15 s pushes, slots turning ready) keep controller focus on the same button, or the main button.
 if focusName then local again=list:FindFirstChild(focusName,true);if again and again:IsA('GuiButton')then selectSafe(again)else task.defer(function()if open then focusCard(true)end end)end end
 -- Cards pop in left to right on a fresh open (a single row, so NeonUI.popRows' per-row stagger doesn't apply).
 if os.clock()-entranceStart<.05 then
  for i,cell in cells do local card=cell:FindFirstChild('Card');local pop=card and card:FindFirstChild('Pop')
   if pop then pop.Scale=0;anim(pop,TweenInfo.new(POP_TIME,Enum.EasingStyle.Back,Enum.EasingDirection.Out,0,false,ROWS_START+(i-1)*ROW_STAGGER),{Scale=1})end end
 end
end
-- Live ticking: countdowns, progress bars, footer teaser, and flipping slots to ready without a rebuild storm.
local function tick()
 if not state then return end
 if open and not busy then
  if kind=='Daily'then
   local d=state.daily
   if not d.canClaim then
    local left=(d.nextClaimAt or 0)-serverNow()
    local nextR=state.teaser and state.teaser.daily
    footerText.Text='Next gift in '..fmt(left)..(nextR and('   •   Tomorrow: '..rewardLine(nextR.reward))or '')
   end
   -- UTC midnight: claimed -> new gift, or an unclaimed old day -> the server resets the streak. Refresh either way.
   if(d.nextClaimAt or 0)-serverNow()<=0 then refreshSoon()end
  else
   local t=state.timed;local played=session()
   pill.Text='PLAYED  '..fmt(played)..' / 6:00:00'
   barFill.Size=UDim2.fromScale(math.clamp(played/(t.maxSeconds or 21600),0,1),1)
   local flip=false
   for _,ref in cardRefs do
    if ref.fill and ref.slot then
     local prevAt=0;for _,s in t.slots do if s.at<ref.slot.at and s.at>prevAt then prevAt=s.at end end
     ref.fill.Size=UDim2.fromScale(math.clamp((played-prevAt)/math.max(1,ref.slot.at-prevAt),0,1),1)
     ref.status.Text='IN '..fmt(ref.slot.at-played)
     if played>=ref.slot.at then flip=true end
    end
   end
   local nextSlot;for _,s in t.slots do if not s.claimed and played<s.at and(not nextSlot or s.at<nextSlot.at)then nextSlot=s end end
   local readyCount=0;for _,s in t.slots do if not s.claimed and played>=s.at then readyCount+=1 end end
   if readyCount>0 then footerText.Text=readyCount==1 and 'A reward is ready to open!'or(readyCount..' rewards are ready to open!')
   elseif nextSlot then footerText.Text='Next: '..rewardLine(nextSlot.reward)..' in '..fmt(nextSlot.at-played)
   else footerText.Text='All rewards claimed this session. Come back next session!'end
   if flip then sfx('cardReady',1.1);render()end
  end
 end
end
-- World panels: live status text and a pulse when something is ready (teases from across the van).
local worldPulse={}
-- The mission van is generated at runtime (RecoveryModels.Van), wherever its parent is: track terminals as they appear.
local terminals={}
local function track(x)
 if(x.Name=='DailyRewardsTerminal'or x.Name=='TimedRewardsTerminal')and x:IsA('BasePart')then terminals[x]=true end
end
for _,x in workspace:GetDescendants()do track(x)end
workspace.DescendantAdded:Connect(track)
local function worldPanels()
 local out={}
 for t in terminals do
  if not t:IsDescendantOf(workspace)then terminals[t]=nil;worldPulse[t]=nil
  else local k=t:GetAttribute('RewardKind');if k then out[k]=out[k]or{};table.insert(out[k],t)end end
 end
 return out
end
local function setWorld(t,text,ready)
 local face=t:FindFirstChild('RewardFace');local frame=face and face:FindFirstChild('Frame');if not frame then return end
 local st=frame:FindFirstChild('Status');if st and st.Text~=text then st.Text=text end
 local glow=frame:FindFirstChild('IconGlow')
 if glow and worldPulse[t]~=ready then
  worldPulse[t]=ready
  if glow:GetAttribute('Pulsing')then glow:SetAttribute('Pulsing',false)end
  if ready then
   glow:SetAttribute('Pulsing',true)
   task.spawn(function()
    while glow.Parent and glow:GetAttribute('Pulsing')do
     play(glow,TweenInfo.new(.6,Enum.EasingStyle.Sine),{Size=UDim2.fromOffset(250,250),BackgroundTransparency=.45});task.wait(.6)
     play(glow,TweenInfo.new(.6,Enum.EasingStyle.Sine),{Size=UDim2.fromOffset(210,210),BackgroundTransparency=.72});task.wait(.6)
    end
   end)
  end
 end
end
local lastReady=-1
local function worldTick()
 if not state then return end
 local panels=worldPanels()
 if panels.Daily then
  local d=state.daily
  if(d.nextClaimAt or 0)-serverNow()<=0 then refreshSoon()end
  local text=d.canClaim and('DAY '..todayDay()..' READY!')or('NEXT IN '..fmt((d.nextClaimAt or 0)-serverNow()))
  for _,t in panels.Daily do setWorld(t,text,d.canClaim==true)end
 end
 if panels.Timed then
  local played=session();local readyCount,nextSlot=0,nil
  for _,s in state.timed.slots or{}do if not s.claimed then if played>=s.at then readyCount+=1 elseif not nextSlot or s.at<nextSlot.at then nextSlot=s end end end
  local text=readyCount>0 and(readyCount..' READY TO OPEN!')or nextSlot and('NEXT IN '..fmt(nextSlot.at-played))or 'ALL CLAIMED'
  for _,t in panels.Timed do setWorld(t,text,readyCount>0)end
  -- HUD toast the moment a new playtime reward becomes ready while the panel is closed.
  if lastReady>=0 and readyCount>lastReady and not open then
   local newest;for _,s in state.timed.slots do if not s.claimed and played>=s.at then newest=s end end
   if newest then
    local first=items(newest.reward)[1]
    toastIcon.Image=first and ICON[first.key]or '';toastText.Text='Playtime reward ready: '..rewardLine(newest.reward);toastRim.Color=rarityOf(newest.reward)[1]
    toast.Visible=true;toast.Position=UDim2.new(.5,0,0,-90);sfx('cardReady');task.delay(.15,function()sfx('giftSparkle',1.2)end)
    play(toast,TweenInfo.new(.45,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Position=UDim2.new(.5,0,0,58)})
    task.delay(4.5,function()local t=play(toast,TweenInfo.new(.3,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{Position=UDim2.new(.5,0,0,-90)});t.Completed:Wait();if toast.Position.Y.Offset<0 then toast.Visible=false end end)
   end
  end
  lastReady=readyCount
 end
end
-- Opening sequence -----------------------------------------------------------------------------------
local raysSpin=0
Run.RenderStepped:Connect(function(dt)if scene.Visible then raysSpin=(raysSpin+dt*22)%360;rays.Rotation=raysSpin end end)
local function burstSparkles(color,count)
 local c=scene.AbsoluteSize/2;local center=Vector2.new(c.X,stage.AbsolutePosition.Y-scene.AbsolutePosition.Y+stage.AbsoluteSize.Y*.5)
 for i=1,count do
  local s=Instance.new('Frame');s.Name='Spark';s.AnchorPoint=Vector2.new(.5,.5);s.BorderSizePixel=0;local size=math.random(8,18);s.Size=UDim2.fromOffset(size,size);s.Rotation=45
  s.BackgroundColor3=(i%3==0)and Color3.new(1,1,1)or color;s.Position=UDim2.fromOffset(center.X,center.Y);s.ZIndex=74;s.Parent=sparkles;UI.corner(s,UDim.new(0,3))
  local a=math.rad(i/count*360+math.random(-10,10));local dist=math.random(180,380)
  local target=UDim2.fromOffset(center.X+math.cos(a)*dist,center.Y+math.sin(a)*dist)
  local life=math.random(55,95)/100
  play(s,TweenInfo.new(life,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Position=target,Rotation=45+math.random(-180,180)})
  play(s,TweenInfo.new(life*.6,Enum.EasingStyle.Quad,Enum.EasingDirection.In,0,false,life*.4),{BackgroundTransparency=1,Size=UDim2.fromOffset(2,2)})
  task.delay(life+.05,function()s:Destroy()end)
 end
end
local function resetScene(k)
 for _,x in loot:GetChildren()do if x:IsA('GuiObject')then x:Destroy()end end
 for _,x in sparkles:GetChildren()do x:Destroy()end
 scene.BackgroundTransparency=1;flash.BackgroundTransparency=1;collect.Visible=false;rarityBanner.Visible=false;caption.Text='';tease.Text=''
 for _,r in rayParts do r.BackgroundTransparency=1;r.BackgroundColor3=Color3.new(1,1,1)end
 for _,h in halos do h.BackgroundTransparency=1;h.BackgroundColor3=k.a end
 ringStroke.Transparency=1;ring.Size=UDim2.fromOffset(60,60)
 bodyGradient.Color=ColorSequence.new(k.a,k.b:Lerp(Color3.new(0,0,0),.25));lidGradient.Color=ColorSequence.new(k.a:Lerp(Color3.new(1,1,1),.25),k.a)
 box.Visible=true;box.Rotation=0;box.Position=UDim2.new(.5,0,-.6,0);boxScale.Scale=1
 lid.Position=UDim2.new(.5,0,1,-122);lid.Rotation=0;lidScale.Scale=1;for _,x in lid:GetDescendants()do if x:IsA('Frame')then x.BackgroundTransparency=0 elseif x:IsA('UIStroke')then x.Transparency=0 end end
 for _,x in body:GetDescendants()do if x:IsA('Frame')and x.Name~='Shine'then x.BackgroundTransparency=0 end end;body.BackgroundTransparency=0
 for _,x in box:GetDescendants()do if x:IsA('UIStroke')then x.Transparency=0 end end
 stageScale.Scale=math.clamp(math.min(scene.AbsoluteSize.X/620,scene.AbsoluteSize.Y/700),.55,1.15)
end
local function revealLoot(reward,color,token)
 local list_=items(reward)
 for i,it in list_ do
  local chip=Instance.new('Frame');chip.Name='Item_'..it.key;chip.LayoutOrder=i;chip.BackgroundTransparency=1;chip.Size=UDim2.fromOffset(180,220);chip.ZIndex=70;chip.Parent=loot
  local inner=Instance.new('Frame');inner.Name='Inner';inner.AnchorPoint=Vector2.new(.5,.5);inner.Position=UDim2.new(.5,0,.5,-120);inner.Size=UDim2.fromScale(1,1);inner.BackgroundTransparency=1;inner.ZIndex=70;inner.Parent=chip
  local sc=Instance.new('UIScale');sc.Scale=0;sc.Parent=inner
  local icon=Instance.new('ImageLabel');icon.Name='Icon';icon.AnchorPoint=Vector2.new(.5,0);icon.Position=UDim2.fromScale(.5,0);icon.Size=UDim2.fromOffset(140,140);icon.Image=ICON[it.key];icon.ScaleType=Enum.ScaleType.Crop;icon.BackgroundColor3=colors.ink;icon.ZIndex=71;icon.Parent=inner
  UI.corner(icon,UDim.new(1,0));UI.stroke(icon,color,4,0)
  local amount=UI.text(inner,'Amount','+0',UI.Font.Display,38,colors.gold);amount.Position=UDim2.fromOffset(0,146);amount.Size=UDim2.new(1,0,0,34);amount.TextXAlignment=Enum.TextXAlignment.Center;amount.ZIndex=72;UI.outline(amount,2)
  local name=UI.text(inner,'Name',NAMES[it.key]..(it.amount>1 and it.key~='tokens'and 'S'or ''),UI.Font.Title,14,colors.text);name.Position=UDim2.fromOffset(0,182);name.Size=UDim2.new(1,0,0,20);name.TextXAlignment=Enum.TextXAlignment.Center;name.ZIndex=72;UI.fit(name,9,14);UI.outline(name,1.2)
  task.delay((i-1)*.16,function()
   if animationToken~=token or not chip.Parent then return end
   play(sc,TweenInfo.new(.45,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1})
   play(inner,TweenInfo.new(.5,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Position=UDim2.fromScale(.5,.5)})
   sfx('itemPop',1+(i-1)*.18)
   if it.key=='tokens'then sfx('coins')end
   -- Count up so big numbers feel big.
   local v=Instance.new('NumberValue');v.Value=0
   v.Changed:Connect(function(x)amount.Text='+'..math.floor(x+.5)end)
   local t=play(v,TweenInfo.new(it.key=='tokens'and .9 or .3,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Value=it.amount})
   t.Completed:Connect(function()amount.Text='+'..it.amount;v:Destroy();if it.key=='tokens'then sfx('giftSparkle',1.4)end
    local punch=Instance.new('UIScale');punch.Parent=amount;punch.Scale=1.35;play(punch,TweenInfo.new(.25,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1})end)
  end)
 end
 return #list_
end
local function waitOrToken(seconds,token)task.wait(seconds);return animationToken==token end
startOpening=function(claimKind,slotId)
 if busy then return end
 busy=true;animationToken+=1;local token=animationToken
 p:SetAttribute('VanRewardsOpen',true) -- keeps the cursor free for COLLECT even when the panel itself is closed
 p:SetAttribute('VanRewardHold',true) -- MainMenuClient's '+N TOKENS' toast waits for COLLECT
 local k=KIND[kind]
 -- Preview of what's inside (the tease): the card's reward, without rarity colours yet.
 local preview
 local dayNumber=todayDay()
 if claimKind=='daily'then preview=state.teaser and state.teaser.daily and state.teaser.daily.reward
  for _,e in state.daily.track or{}do if e.day==dayNumber then preview=e.reward end end
 else for _,s in state.timed.slots do if s.id==slotId then preview=s.reward end end end
 -- 1) The panel leaves.
 cancelTweens();mainButton.Visible=false
 UI.slideOut(panel,SLIDE_OUT)
 task.delay(SLIDE_OUT+.02,function()if animationToken==token then panel.Visible=false end end)
 -- 2) The server claim runs during the build-up; the reveal waits for its answer.
 local result
 -- Apply the committed state the moment it arrives, not after the animation (keeps the playtime clock honest).
 task.spawn(function()local r=claim(claimKind,slotId);if type(r)=='table'and r.state then setState(r.state)end;result=r end)
 resetScene(k)
 scene.Visible=true
 play(scene,TweenInfo.new(.3),{BackgroundTransparency=.25})
 caption.Text=claimKind=='daily'and('DAY '..dayNumber..' GIFT')or 'PLAYTIME REWARD'
 -- Only day 7 has a random extra (the Instant Win roll); every other gift is exactly what the card showed.
 -- Previews are exact (the server rolls deterministically), so the tease names the real contents.
 local jackpot=claimKind=='daily'and dayNumber%7==0
 tease.Text=jackpot and 'BIG BOX DAY!  What could be inside?'or 'What could be inside?'
 -- 3) Box drops in and squashes on landing.
 play(box,TweenInfo.new(BOX_DROP,Enum.EasingStyle.Bounce,Enum.EasingDirection.Out),{Position=UDim2.fromScale(.5,.56)})
 sfx('giftWhoosh',.9)
 if not waitOrToken(BOX_DROP*.6,token)then return end
 play(boxScale,TweenInfo.new(.08),{Scale=.92});task.wait(.08);play(boxScale,TweenInfo.new(.25,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1})
 if not waitOrToken(LAND_PAUSE,token)then return end
 for i,h in halos do play(h,TweenInfo.new(.4,Enum.EasingStyle.Sine,Enum.EasingDirection.Out,0,false,i*.05),{BackgroundTransparency=.82+i*.03})end
 -- 4) Anticipation: shakes that grow, glow that swells; keep shaking until the server answers.
 local started=os.clock();local pulse=0
 -- No timeout: a slow save (retries can take 20 s+) still ends in the real reveal, never a false failure.
 while animationToken==token and(pulse<SHAKE_PULSES or result==nil)do
  if pulse>=6 and result==nil and not collect.Visible then
   -- Slow save: say so, and offer a way out on every platform (the grant still lands server-side).
   caption.Text='SAVING YOUR REWARD…';tease.Text='Still saving. You can close this; the panel updates when it finishes.'
   collect.Text='CLOSE';collect.Visible=true;if platform()=='pad'then selectSafe(collect)end
  end
  pulse+=1;local power=math.min(pulse,5)
  sfx('shakeTick',.8+math.min(pulse,8)*.09)
  play(boxScale,TweenInfo.new(.12,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Scale=1+power*.035})
  for j=1,4 do box.Rotation=((j%2==0)and -1 or 1)*(3+power*2.2);task.wait(.045)end
  box.Rotation=0
  play(boxScale,TweenInfo.new(.18,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1})
  for i,h in halos do play(h,TweenInfo.new(.25),{BackgroundTransparency=math.max(.45,.85-power*.08+i*.04)})end
  for _,r in rayParts do play(r,TweenInfo.new(.25),{BackgroundTransparency=math.max(.55,.95-power*.08)})end
  task.wait(math.max(.12,.36-pulse*.06))
 end
 if animationToken~=token then return end
 while result==nil and os.clock()-started<MIN_BUILDUP do task.wait()end
 if not result or not result.ok then
  -- Failure: red flash, shake, message, back to the panel.
  Audio.Play('UiError')
  for _,h in halos do h.BackgroundColor3=colors.red end
  for j=1,6 do box.Position=UDim2.new(.5,(j%2==0)and -10 or 10,.56,0);task.wait(.04)end;box.Position=UDim2.fromScale(.5,.56)
  caption.Text='COULDN\'T OPEN';tease.Text=(result and result.reason)or 'Try again in a moment.'
  task.wait(1.6);if animationToken~=token then return end
  busy=false;scene.Visible=false;p:SetAttribute('VanRewardHold',nil);if not open then p:SetAttribute('VanRewardsOpen',false)end
  if open then panel.Visible=true;entranceStart=os.clock();render();UI.slideIn(panel,UDim2.fromScale(.5,.5),SLIDE_IN)end
  return
 end
 collect.Visible=false
 local reward=result.reward or preview or{}
 local r=rarityOf(reward)
 -- 5) Payoff: rarity colour floods in, the lid blasts off, flash, shockwave, rays, sparkles.
 for _,h in halos do play(h,TweenInfo.new(.15),{BackgroundColor3=r[1]})end
 for _,ray in rayParts do ray.BackgroundColor3=r[1]end
 play(boxScale,TweenInfo.new(.14,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{Scale=.86});task.wait(.14)
 if animationToken~=token then return end
 sfx('burstLid');sfx('burstMagic')
 local sting=reward.rarity=='legendary'and'legendary'or reward.rarity=='epic'and'epic'or reward.rarity=='rare'and'rare'or nil
 if sting then task.delay(.2,function()sfx(sting)end)end
 flash.BackgroundTransparency=.15;play(flash,TweenInfo.new(.55,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{BackgroundTransparency=1})
 play(boxScale,TweenInfo.new(.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1.06})
 play(lid,TweenInfo.new(.55,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Position=UDim2.new(.5,140,1,-420),Rotation=38})
 play(lidScale,TweenInfo.new(.55),{Scale=.7})
 for _,x in lid:GetDescendants()do local info=TweenInfo.new(.4,Enum.EasingStyle.Quad,Enum.EasingDirection.In,0,false,.2)
  if x:IsA('Frame')then play(x,info,{BackgroundTransparency=1})elseif x:IsA('UIStroke')then play(x,info,{Transparency=1})end end
 ringStroke.Color=r[1];ringStroke.Transparency=0;ring.Size=UDim2.fromOffset(60,60)
 play(ring,TweenInfo.new(.6,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Size=UDim2.fromOffset(620,620)});play(ringStroke,TweenInfo.new(.6,Enum.EasingStyle.Quad),{Transparency=1})
 for _,ray in rayParts do play(ray,TweenInfo.new(.3),{BackgroundTransparency=RAY_ALPHA[reward.rarity]or .72})end
 -- The halo flares with the burst, then settles back so the loot stays readable.
 task.delay(.45,function()if animationToken==token then for i,h in halos do play(h,TweenInfo.new(.5,Enum.EasingStyle.Quad),{BackgroundTransparency=.88+i*.03})end end end)
 burstSparkles(r[1],reward.rarity=='legendary'and 34 or reward.rarity=='epic'and 26 or 18)
 rarityBanner.Text=r[2]..'!';rarityBanner.TextColor3=r[1];rarityBanner.Visible=true;rarityScale.Scale=2.2
 play(rarityScale,TweenInfo.new(.4,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1})
 caption.Text='';tease.Text=''
 -- The opened box sinks away so the loot owns the screen.
 task.delay(.35,function()
  if animationToken~=token then return end
  play(box,TweenInfo.new(.4,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{Position=UDim2.fromScale(.5,.75)})
  for _,x in box:GetDescendants()do if x:IsA('Frame')then play(x,TweenInfo.new(.35),{BackgroundTransparency=1})elseif x:IsA('UIStroke')then play(x,TweenInfo.new(.35),{Transparency=1})end end;play(body,TweenInfo.new(.35),{BackgroundTransparency=1})
 end)
 if not waitOrToken(.3,token)then return end
 local n=revealLoot(reward,r[1],token)
 if not waitOrToken(.5+n*.16,token)then return end
 collect.Visible=true;collect.Text='COLLECT';local cs=collect:FindFirstChild('Press');if cs then cs.Scale=0;play(cs,TweenInfo.new(.35,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1})end
 if platform()=='pad'then selectSafe(collect)end
 -- Auto-collect after a while so a player who walks away isn't stuck in the scene.
 task.delay(8,function()if animationToken==token and busy and collect.Visible then finishOpening()end end)
end
finishOpening=function()
 if not busy or not collect.Visible then return end
 if collect.Text=='CLOSE'then if open then close()else endScene()end;return end
 collect.Visible=false;animationToken+=1;local token=animationToken
 p:SetAttribute('VanRewardHold',nil)
 sfx('collect');task.delay(.1,function()sfx('collectShimmer')end);task.delay(.25,function()sfx('coins',1.1)end)
 -- Loot flies up toward the balance pill, the scene fades, the panel returns with the card ticked.
 for i,chip in loot:GetChildren()do if chip:IsA('Frame')then local inner=chip:FindFirstChild('Inner')
  if inner then play(inner,TweenInfo.new(.4,Enum.EasingStyle.Quart,Enum.EasingDirection.In,0,false,i*.05),{Position=UDim2.new(.5,0,-3,0)})
   for _,x in inner:GetDescendants()do if x:IsA('ImageLabel')then play(x,TweenInfo.new(.35,Enum.EasingStyle.Quad,Enum.EasingDirection.In,0,false,.1+i*.05),{ImageTransparency=1,BackgroundTransparency=1})elseif x:IsA('TextLabel')then play(x,TweenInfo.new(.3,Enum.EasingStyle.Quad,Enum.EasingDirection.In,0,false,.1),{TextTransparency=1})end end
  end end end
 play(rarityScale,TweenInfo.new(.25,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{Scale=0})
 for _,r in rayParts do play(r,TweenInfo.new(.35),{BackgroundTransparency=1})end
 for _,h in halos do play(h,TweenInfo.new(.35),{BackgroundTransparency=1})end
 play(scene,TweenInfo.new(.45),{BackgroundTransparency=1})
 task.wait(.5);if animationToken~=token then return end
 scene.Visible=false;busy=false
 if not open then p:SetAttribute('VanRewardsOpen',false)end
 if open and nearTerminal()then
  panel.Visible=true;entranceStart=os.clock();render();table.insert(tweens,UI.slideIn(panel,UDim2.fromScale(.5,.5),SLIDE_IN))
  task.defer(function()if open then focusCard(platform()=='pad')end end)
 elseif open then close()end
end
collect.Activated:Connect(finishOpening)
-- Physical claim -------------------------------------------------------------------------------------
-- CLAIM drops a real gift box out of the panel onto the van floor with a floating pop-up over it. The
-- reward is only claimed (server) when the player walks over and holds E on the box; then the opening plays.
local GIFT_DROP,GIFT_FORWARD,GIFT_HOLD=.75,3.4,.45
local SPARKLE='rbxasset://textures/particles/sparkles_main.dds'
endScene=function()
 animationToken+=1;busy=false;scene.Visible=false;p:SetAttribute('VanRewardHold',nil)
 if not open then p:SetAttribute('VanRewardsOpen',false)end
end
local function giftLabel(claimKind,slotId)
 if claimKind=='daily'then
  local d=todayDay();local reward;for _,e in state.daily.track or{}do if e.day==d then reward=e.reward end end
  return 'DAY '..d..' GIFT',reward
 end
 for _,s in state.timed.slots or{}do if s.id==slotId then return short(s.at)..' REWARD',s.reward end end
 return 'REWARD',nil
end
local function floorBelow(pos,ignore)
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances=ignore
 local hit=workspace:Raycast(pos+Vector3.new(0,2,0),Vector3.new(0,-30,0),params)
 return hit and hit.Position.Y or pos.Y-4
end
local mutedPrompts={} -- terminal prompts disabled on this client while a gift waits near them
local function syncPanelPrompts()
 local want={}
 for _,g in gifts do if g.model.PrimaryPart then
  for t in terminals do local pr=t:FindFirstChildOfClass('ProximityPrompt');if pr and(t.Position-g.model.PrimaryPart.Position).Magnitude<8 then want[pr]=true end end
 end end
 for pr in want do if not mutedPrompts[pr]then mutedPrompts[pr]=pr.Enabled;pr.Enabled=false end end
 for pr,was in mutedPrompts do if not want[pr]then if pr.Parent then pr.Enabled=was end;mutedPrompts[pr]=nil end end
end
local function removeGift(key,burst)
 local g=gifts[key];gifts[key]=nil;if not g then return end
 task.defer(syncPanelPrompts)
 local m=g.model
 if burst and m.PrimaryPart then
  local a=Instance.new('Attachment');a.Parent=m.PrimaryPart
  local e=Instance.new('ParticleEmitter');e.Texture=SPARKLE;e.Color=ColorSequence.new(g.color);e.LightEmission=1;e.Size=NumberSequence.new(.6,0);e.Speed=NumberRange.new(10,18);e.SpreadAngle=Vector2.new(180,180);e.Lifetime=NumberRange.new(.4,.7);e.Rate=0;e.Parent=a;e:Emit(40)
  for _,x in m:GetDescendants()do if x:IsA('BasePart')then play(x,TweenInfo.new(.25),{Transparency=1})elseif x:IsA('BillboardGui')then x.Enabled=false end end
  task.delay(.8,function()m:Destroy()end)
 else m:Destroy() end
end
dropGift=function(claimKind,slotId)
 local key=giftKey(claimKind,slotId);local terminal=activeTerminal
 if gifts[key]or not terminal then return end
 local title,preview=giftLabel(claimKind,slotId)
 local r=rarityOf(preview);local k=KIND[claimKind=='daily'and 'Daily'or 'Timed']
 local m=Instance.new('Model');m.Name='VanRewardGift'
 local ribbon=Color3.fromRGB(255,214,90)
 local function blk(name,size,cf,color,shape)
  local x=Instance.new('Part');x.Name=name;x.Size=size;x.CFrame=cf;x.Color=color;x.Material=Enum.Material.SmoothPlastic;x.Anchored=true;x.CanCollide=false;x.CanTouch=false;x.CanQuery=true
  if shape then x.Shape=shape end;x.Parent=m;return x
 end
 local body=blk('Body',Vector3.new(1.7,1.3,1.7),CFrame.new(),k.a)
 blk('RibbonX',Vector3.new(1.74,1.32,.34),CFrame.new(),ribbon);blk('RibbonZ',Vector3.new(.34,1.32,1.74),CFrame.new(),ribbon)
 blk('Lid',Vector3.new(1.9,.38,1.9),CFrame.new(0,.82,0),k.b)
 blk('LidRibbonX',Vector3.new(1.94,.4,.36),CFrame.new(0,.82,0),ribbon);blk('LidRibbonZ',Vector3.new(.36,.4,1.94),CFrame.new(0,.82,0),ribbon)
 for side=-1,1,2 do blk('Bow',Vector3.new(.6,.6,.6),CFrame.new(side*.32,1.2,0),ribbon,Enum.PartType.Ball)end
 m.PrimaryPart=body
 local light=Instance.new('PointLight');light.Color=r[1];light.Brightness=2.2;light.Range=11;light.Parent=body
 local att=Instance.new('Attachment');att.Parent=body
 local sp=Instance.new('ParticleEmitter');sp.Texture=SPARKLE;sp.Color=ColorSequence.new(r[1]);sp.LightEmission=1;sp.Size=NumberSequence.new(.35,0);sp.Rate=10;sp.Speed=NumberRange.new(1,3);sp.SpreadAngle=Vector2.new(180,180);sp.Lifetime=NumberRange.new(.8,1.4);sp.Parent=att
 -- The pop-up over the box: what it is, what's inside, how to open it.
 local bb=Instance.new('BillboardGui');bb.Name='GiftPopup';bb.Size=UDim2.fromOffset(300,124);bb.StudsOffset=Vector3.new(0,2.9,0);bb.AlwaysOnTop=false;bb.MaxDistance=70;bb.LightInfluence=0;bb.Parent=body
 local card=Instance.new('Frame');card.Size=UDim2.fromScale(1,1);card.BackgroundColor3=colors.plate;card.BackgroundTransparency=.08;card.Parent=bb;UI.corner(card,16);UI.stroke(card,r[1],3,0)
 local pop=Instance.new('UIScale');pop.Scale=0;pop.Parent=card
 local t1=UI.text(card,'Title',title,UI.Font.Display,24,colors.text);t1.Position=UDim2.fromOffset(10,8);t1.Size=UDim2.new(1,-20,0,36);t1.TextXAlignment=Enum.TextXAlignment.Center;UI.fit(t1,16,30);UI.outline(t1,1.8)
 local t2=UI.text(card,'Inside',"WHAT'S INSIDE?",UI.Font.Display,20,colors.gold);t2.Position=UDim2.fromOffset(10,46);t2.Size=UDim2.new(1,-20,0,32);t2.TextXAlignment=Enum.TextXAlignment.Center;UI.fit(t2,14,26);UI.outline(t2,1.5)
 local hint=platform()=='pad'and 'HOLD X TO OPEN'or platform()=='touch'and 'TAP AND HOLD TO OPEN'or 'HOLD E TO OPEN'
 local t3=UI.text(card,'Hint',hint,UI.Font.Title,13,r[1]:Lerp(Color3.new(1,1,1),.35));t3.Position=UDim2.fromOffset(10,86);t3.Size=UDim2.new(1,-20,0,26);t3.TextXAlignment=Enum.TextXAlignment.Center;UI.fit(t3,10,16);UI.outline(t3,1.1)
 local hintConnection=InputHints.Changed:Connect(function()
  t3.Text=platform()=='pad'and 'HOLD X TO OPEN'or platform()=='touch'and 'TAP AND HOLD TO OPEN'or 'HOLD E TO OPEN'
 end)
 m.Destroying:Once(function()hintConnection:Disconnect()end)
 local prompt=Instance.new('ProximityPrompt');prompt.Name='VanRewardGiftPrompt';prompt.ActionText='Open gift';prompt.ObjectText=title;prompt.HoldDuration=GIFT_HOLD;prompt.MaxActivationDistance=9;prompt.RequiresLineOfSight=false
 prompt.KeyboardKeyCode=Enum.KeyCode.E;prompt.GamepadKeyCode=Enum.KeyCode.ButtonX;prompt.Exclusivity=Enum.ProximityPromptExclusivity.AlwaysShow;prompt.Parent=body
 -- Spawn at the panel face, arc out and land on the floor in front of it.
 local face=terminal.CFrame*CFrame.new(0,0,-.5)
 local ground=terminal.Position+terminal.CFrame.LookVector*GIFT_FORWARD
 local floorY=floorBelow(ground,{m,p.Character})
 local yaw=CFrame.Angles(0,math.rad(math.random(-25,25)),0)
 local final=CFrame.new(ground.X,floorY+.66,ground.Z)*yaw
 m:PivotTo(face);m.Parent=workspace
 gifts[key]={model=m,color=r[1],terminal=terminal}
 sfx('giftWhoosh')
 task.spawn(function()
  local start=os.clock()
  while m.Parent do
   local a=math.min(1,(os.clock()-start)/GIFT_DROP)
   local pos=face.Position:Lerp(final.Position,a)+Vector3.new(0,math.sin(a*math.pi)*2.4,0)
   m:PivotTo(CFrame.new(pos)*yaw*CFrame.Angles(0,(1-a)*math.pi*2,0))
   if a>=1 then break end
   task.wait()
  end
  if not m.Parent then return end
  syncPanelPrompts()
  -- Landing: thump, a little bounce, then the pop-up springs open and gently bobs.
  sfx('giftLand');sfx('giftSparkle')
  play(pop,TweenInfo.new(.4,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1})
  local t=0
  while m.Parent do
   t+=task.wait()
   local bounce=t<.5 and math.abs(math.sin(t*12))*(.5-t)*.6 or 0
   m:PivotTo(final*CFrame.new(0,bounce+math.sin(t*2)*.06,0)*CFrame.Angles(0,math.sin(t*.8)*.12,0))
   bb.StudsOffset=Vector3.new(0,2.9+math.sin(t*2.4)*.12,0)
  end
 end)
 prompt.Triggered:Connect(function(who)
  if who~=p or busy then return end
  sfx('holdOpen')
  removeGift(key,true)
  startOpening(claimKind,slotId)
 end)
 if open then close()end
end
-- A gift left behind disappears with its van (mission over); the reward stays claimable at the panel.
task.spawn(function()
 while true do
  task.wait(1)
  for key,g in gifts do if not g.terminal.Parent or not g.model.Parent then removeGift(key,false)end end
  -- Claimed elsewhere (another server) or the day rolled over: tidy the box away.
  if state then
   if gifts[giftKey('daily',nil)]and not state.daily.canClaim then removeGift(giftKey('daily',nil),false)end
   for _,s in state.timed.slots or{}do if s.claimed and gifts[giftKey('timed',s.id)]then removeGift(giftKey('timed',s.id),false)end end
  end
 end
end)

onRefreshed=function()if open and not busy then render()end end
-- Open / close ----------------------------------------------------------------------------------------
close=function()
 if not open then return end
 open=false;p:SetAttribute('VanRewardsOpen',false)
 if busy then
  -- Mid-opening: the claim is already in flight on the server; just tidy the screen.
  busy=false;animationToken+=1;scene.Visible=false;p:SetAttribute('VanRewardHold',nil)
 end
 animationToken+=1;local token=animationToken
 cancelTweens();Audio.Play('UiClose');CameraGuard.Mute(.4)
 UI.slideOut(panel,SLIDE_OUT);UI.showBackdrop(backdrop,false)
 UI.FocusRelease('VanRewards')
 if GS.SelectedObject and GS.SelectedObject:IsDescendantOf(gui)then GS.SelectedObject=nil;if selectable(previousFocus)then GS.SelectedObject=previousFocus end end
 task.delay(SLIDE_OUT+.02,function()if animationToken==token then panel.Visible=false end end)
end
-- Controller focus on open: the most recently unlocked reward that can be claimed; if none is claimable,
-- the next one still to unlock (or the last card when everything is claimed). Always scrolled into view.
local function pickCell()
 local cells={};for _,c in list:GetChildren()do if c:IsA('Frame')and c:FindFirstChild('Card')then table.insert(cells,c)end end
 table.sort(cells,function(a,b)return a.LayoutOrder<b.LayoutOrder end)
 local claimable,nextLocked
 for _,c in cells do
  local button=c.Card:FindFirstChildWhichIsA('GuiButton')
  local tag=c.Card:FindFirstChild('Tag')
  if button then claimable=c
  elseif not nextLocked and not(tag and tag.Text=='CLAIMED')then nextLocked=c end
 end
 return claimable or nextLocked or cells[#cells]
end
focusCard=function(select)
 local cell=pickCell()
 if cell then
  local x=cell.AbsolutePosition.X-list.AbsolutePosition.X+list.CanvasPosition.X
  list.CanvasPosition=Vector2.new(math.max(0,x-list.AbsoluteSize.X/2+cell.AbsoluteSize.X/2),0)
 end
 if not select then return end
 -- Re-resolved every frame: the cards are rebuilt right after opening (the list settles to its real size).
 UI.SelectWhenReady(function()
  if not open or busy then return nil end
  local c=pickCell();if not c then return closeButton end
  local card=c.Card
  if not card.Selectable then card.Selectable=true;UI.selection(card,16)end
  return card:FindFirstChildWhichIsA('GuiButton')or card
 end)
end
local function show(terminal)
 if open or busy then return end
 activeTerminal=terminal;if not nearTerminal()then return end
 kind=terminal:GetAttribute('RewardKind')=='Timed'and 'Timed'or 'Daily'
 local s=fetchState()
 if not s then Audio.Play('UiError');return end
 if not nearTerminal()then return end
 setState(s)
 open=true;animationToken+=1;previousFocus=GS.SelectedObject;p:SetAttribute('VanRewardsOpen',true);cancelTweens()
 UI.FocusAcquire('VanRewards',gui)
 panel.Visible=true;entranceStart=os.clock();render()
 list.CanvasPosition=Vector2.zero
 -- Scroll the claimable (or next) card into view.
 task.defer(function()
  if not open then return end
  focusCard(platform()=='pad')
 end)
 table.insert(tweens,UI.slideIn(panel,UDim2.fromScale(.5,.5),SLIDE_IN));table.insert(tweens,UI.showBackdrop(backdrop,true))
 sfx('panelOpen')
end
mainButton.Activated:Connect(function()
 Audio.Play('UiClick')
 if kind=='Daily'then onCardActivated(nil)
 else
  local played=session()
  for _,s in state.timed.slots do if not s.claimed and played>=s.at and not gifts[giftKey('timed',s.id)]then onCardActivated(s.id);return end end
 end
end)
closeButton.Activated:Connect(function()if busy then return end;Audio.Play('UiClick');close()end)
PPS.PromptTriggered:Connect(function(prompt,who)
 if(prompt.Name=='DailyRewardsPrompt'or prompt.Name=='TimedRewardsPrompt')and(not who or who==p)and InputHints.ConfirmTap()then show(prompt.Parent)end -- phones: a real tap, not a camera swipe
end)
CAS:BindActionAtPriority('VanRewardsClose',function(_,inputState)
 if not open and not busy then return Enum.ContextActionResult.Pass end
 -- During the reveal Esc/B collects; while still waiting on the save it dismisses (the claim keeps going
 -- on the server and StateChanged brings the result).
 if inputState==Enum.UserInputState.Begin then if busy and collect.Visible then finishOpening()else close()end end
 return Enum.ContextActionResult.Sink
end,false,6000,Enum.KeyCode.Escape,Enum.KeyCode.ButtonB)
local function hookChanged(r)
 local ev=r:FindFirstChild('StateChanged')or r:WaitForChild('StateChanged',10)
 if ev and ev:IsA('RemoteEvent')then ev.OnClientEvent:Connect(function(s)setState(s);if open and not busy then render()end end)end
end
if getRemotes()then task.spawn(hookChanged,getRemotes())else RS.ChildAdded:Connect(function(c)if c.Name=='VanRewards'then remotes=c;task.spawn(hookChanged,c)end end)end
-- Background: keep a fresh copy of state for the world panels and the ready toast.
task.spawn(function()
 while true do
  if not state or os.clock()-stateClock>60 then local s=fetchState();if s then setState(s)end end
  task.wait(10)
 end
end)
local acc,worldAcc=0,0
Run.Heartbeat:Connect(function(dt)
 acc+=dt;worldAcc+=dt
 if acc>=.25 then acc=0;tick();if open and not busy and not nearTerminal()then close()end end
 if worldAcc>=1 then worldAcc=0;worldTick()end
end)
p.CharacterRemoving:Connect(function()if open then close()end end)
gui:GetPropertyChangedSignal('AbsoluteSize'):Connect(function()if open and not busy then render()end end)
pill:GetPropertyChangedSignal('AbsoluteSize'):Connect(function()if open and not busy then layout()end end)
-- Card sizes come from the list's real size, which settles a frame after the panel first lays out.
local lastListSize=Vector2.zero
list:GetPropertyChangedSignal('AbsoluteSize'):Connect(function()
 if open and not busy and(list.AbsoluteSize-lastListSize).Magnitude>2 then lastListSize=list.AbsoluteSize;render()end
end)
if Run:IsStudio()then local preview=Instance.new('BindableEvent');preview.Name='PreviewVanRewards';preview.Parent=script;preview.Event:Connect(show)end
