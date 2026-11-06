-- Quest Log screen (QUEST_LOG_PLAN section 9). Presentation only: the server (ReplicatedStorage.Quests) owns
-- progress, rolls, claims and grants. This script shows the state, asks to claim and plays the reveal.
-- Open it from anywhere on the client:  PlayerGui.QuestLog.Open:Fire('daily'|'weekly'|'achievements')
-- The van terminal prompt (QuestsRewardsPrompt) and the lobby QUESTS button both use that event.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Tween=game:GetService('TweenService')
local Run=game:GetService('RunService')
local GS=game:GetService('GuiService')
local UIS=game:GetService('UserInputService')
local CAS=game:GetService('ContextActionService')
local PPS=game:GetService('ProximityPromptService')
local SoundService=game:GetService('SoundService')
local Http=game:GetService('HttpService')
local p=Players.LocalPlayer
local UI=require(RS:WaitForChild('NeonUI'))
local Shop=require(RS:WaitForChild('LobbyShopCatalog'))
local colors=UI.Color

-- Look ------------------------------------------------------------------------------------------
local MAX_W,MAX_H,MARGIN=900,520,12
local ORANGE,PURPLE=Color3.fromRGB(255,140,40),Color3.fromRGB(150,80,255)
local READY_GOLD=Color3.fromRGB(255,208,86)
local DONE_GREEN=Color3.fromRGB(52,222,104)
-- 3D quest icons (models/questcos/icons/<key>_512.png). Filled in after upload; empty = letter badge.
local ICONS={
 pickup='rbxassetid://84560132411318',selling='rbxassetid://93403394110277',locked_room='rbxassetid://102076404075662',hiding='rbxassetid://72746676117383',chase='rbxassetid://97997479722518',revive='rbxassetid://97437381948321',secrets='rbxassetid://121191513340922',no_death='rbxassetid://96152066675808',maps='rbxassetid://88665940601534',party='rbxassetid://93311567878566',boat='rbxassetid://137827771884096',achievements='rbxassetid://91859657031763',weekly_chest='rbxassetid://113977879393115',daily='rbxassetid://82192372407203',quests='rbxassetid://117099885163223',
}
local REWARD_ICON={tokens='rbxassetid://116174307880260',revives='rbxassetid://122888744965333'}
local TABS={
 {key='daily',label='TODAY',icon='daily'},
 {key='weekly',label='THIS WEEK',icon='weekly_chest'},
 {key='achievements',label='LIFETIME GOALS',icon='achievements'},
 {key='event',label='HALLOWEEN',icon='quests',event=true}, -- hidden unless state.event.enabled (EventConfig)
}
local TAB_SUB={
 daily='Finish a goal, then press CLAIM REWARD to collect it. New goals every day.',
 weekly='Finish a goal, then press CLAIM REWARD. Finish 4 to open the Weekly Chest.',
 achievements='Goals that never reset. Each has 5 stages; stage 5 gives a title.',
 event='Halloween event! Earn Candy Corn and spend it at the pumpkin cart.',
}

local ROMAN={'I','II','III','IV','V'}

-- Sounds: reuse the van reward set when it exists (VanRewardsClient makes it), so claims sound the same.
local function sfx(name,pitch)
 local folder=SoundService:FindFirstChild('VanRewardSounds');local base=folder and folder:FindFirstChild(name)
 if not base or not base:IsA('Sound')then return end
 local sd=base.IsPlaying and base:Clone()or base
 if sd~=base then sd.Parent=folder;sd.Ended:Once(function()sd:Destroy()end)end
 sd.PlaybackSpeed=pitch or 1;sd.TimePosition=0;sd:Play()
end

-- Remotes and state ------------------------------------------------------------------------------
local function remote(name)
 local f=RS:FindFirstChild('Quests');return f and f:FindFirstChild(name)
end
local MOCK=Run:IsStudio()and script:GetAttribute('Mock')==true and RS:FindFirstChild('Quests')==nil
local state,timeOffset=nil,0
local function eventOn()return state~=nil and type(state.event)=='table'and state.event.enabled==true end
local function serverNow()return os.time()+timeOffset end
local readyBefore={} -- quest keys that were ready in the last state (for the completion toast)
local onState -- forward: redraw hook
local onMastery -- forward: mastery HUD hook (old state, new state)
local drawBoards -- forward: lobby + van mastery boards

local function keyOf(tab,q)return tab..':'..tostring(q.id)end
local function collectReady(s)
 local out={}
 if type(s)~='table'then return out end
 for _,tab in {'daily','weekly'}do
  local t=s[tab];if type(t)=='table'and type(t.quests)=='table'then
   for _,q in t.quests do if q.ready and not q.claimed then out[keyOf(tab,q)]=q end end
  end
 end
 if type(s.achievements)=='table'then for _,a in s.achievements do if a.ready then out['ach:'..tostring(a.id)]=a end end end
 return out
end
local toast -- forward
local function setState(s,fromPush)
 if type(s)~='table'then return end
 -- A slow reply must never roll back a newer push: the server bumps rev on every quest write.
 if state and type(s.rev)=='number'and type(state.rev)=='number'and s.rev<state.rev then return end
 if type(s.serverTime)=='number'then timeOffset=s.serverTime-os.time()end
 local ready=collectReady(s)
 if fromPush and state then
  for k,q in ready do if not readyBefore[k]and q.text then toast(q.text)end end
 end
 local old=state
 readyBefore=ready;state=s
 p:SetAttribute('QuestReadyCount',tonumber(s.readyCount)or 0) -- lobby button badge + van terminal read this
 if onState then onState()end
 if onMastery then onMastery(old,s)end
end

local function mockState()
 local function q(id,text,hint,icon,pr,tg,tok,rev,claimed)
  return {id=id,text=text,hint=hint,icon=icon,progress=pr,target=tg,reward={tokens=tok,revives=rev},ready=pr>=tg and not claimed,claimed=claimed}
 end
 local day=86400
 return {serverTime=os.time(),rev=1,dailyEndsAt=(os.time()//day+1)*day,weeklyEndsAt=(os.time()//day+4)*day,readyCount=3,pinned='d_key_m',
  daily={rerolled=false,quests={
   q('d_pickup_s','Pick up 15 cursed items','Anything you can grab counts.','pickup',15,15,40,0,false),
   q('d_key_m','Unlock a locked room','Locked doors need a key from the same floor.','locked_room',0,1,60,0,false),
   q('d_clear_h','Clear 4 levels','Sell enough to meet the quota, then leave in the van.','maps',1,4,90,0,false)},
   bonus={done=1,target=3,ready=false,claimed=false,reward={tokens=50,revives=1}}},
  weekly={quests={
   q('w_sell','Sell $25,000 of loot','Team sells count for everyone in the van.','selling',25000,25000,150,0,false),
   q('w_hide','Hide in 20 wardrobes','Monsters cannot open them any more.','hiding',20,20,120,0,true),
   q('w_cruise','Clear 3 Cruise levels','The ship comes up in the map rotation.','boat',1,3,160,1,false),
   q('w_party','Clear 5 levels in a party','Two or more players in the run.','party',2,5,140,0,false),
   q('w_secret','Find 3 secrets','Look behind paintings and under beds.','secrets',0,3,150,0,false)},
   chest={done=1,target=4,ready=false,claimed=false,reward={tokens=300,revives=2}}},
  achievements={
   {id='collector',name='Collector',icon='pickup',count=262,tier=1,targets={50,250,1000,3000,10000},rewards={50,100,200,300,500},title='CURSED COLLECTOR',ready=true},
   {id='survivor',name='Survivor',icon='no_death',count=41,tier=1,targets={10,50,150,400,1000},rewards={50,100,200,300,500},title='SEASONED SURVIVOR',ready=false},
   {id='deepdiver',name='Deep Diver',icon='maps',count=8,tier=2,targets={3,5,8,12,20},rewards={50,120,220,350,600},title='ABYSS WALKER',ready=true},
   {id='locksmith',name='Locksmith',icon='locked_room',count=500,tier=5,targets={5,25,75,200,500},rewards={50,100,200,300,500},title='MASTER LOCKSMITH',ready=false},
  },
  mastery={done=1,target=10,ready=false,claimed=false,tag='[Haunted]'}}
end

local function fetch()
 if MOCK then setState(mockState());return true end
 local f=remote('GetState');if not f then return false end
 local ok,res=pcall(function()return f:InvokeServer()end)
 if ok and type(res)=='table'and res.ok then setState(res.state);return true end
 return false
end

-- GUI skeleton -----------------------------------------------------------------------------------
local pg=p:WaitForChild('PlayerGui')
local gui=Instance.new('ScreenGui');gui.Name='QuestLog';gui.DisplayOrder=136;gui.ResetOnSpawn=false;gui.IgnoreGuiInset=true
gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets;gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling;gui.Enabled=false;gui.Parent=pg
local openEvent=Instance.new('BindableEvent');openEvent.Name='Open';openEvent.Parent=gui
local backdrop=UI.backdrop(gui,.45)
local holder,plate=UI.plate(gui,'Panel',22)
holder.AnchorPoint=Vector2.new(.5,.5);holder.ZIndex=2
local close=UI.closeButton(holder,'Close',46);close.Position=UDim2.new(1,-6,0,6)

local header=Instance.new('Frame');header.Name='Header';header.BackgroundTransparency=1;header.Parent=plate
local title=UI.text(header,'Title','QUEST LOG',UI.Font.Display,30);UI.outline(title,2);UI.fit(title,18,32)
local titleGrad=Instance.new('UIGradient');titleGrad.Color=ColorSequence.new(ORANGE,PURPLE);titleGrad.Parent=title
local sub=UI.text(header,'Sub','',UI.Font.Body,15,colors.muted);UI.fit(sub,11,15)
local timer=UI.text(header,'Reset','',UI.Font.Bold,15,READY_GOLD);timer.TextXAlignment=Enum.TextXAlignment.Right;UI.fit(timer,11,16)

local tabBar=Instance.new('Frame');tabBar.Name='Tabs';tabBar.BackgroundTransparency=1;tabBar.Parent=plate
local tabList=Instance.new('UIListLayout');tabList.FillDirection=Enum.FillDirection.Horizontal;tabList.Padding=UDim.new(0,8);tabList.SortOrder=Enum.SortOrder.LayoutOrder;tabList.Parent=tabBar
local tabButtons={}

local body=Instance.new('ScrollingFrame');body.Name='Body';body.BackgroundTransparency=1;body.BorderSizePixel=0;body.ScrollBarThickness=6
body.ScrollBarImageColor3=PURPLE;body.AutomaticCanvasSize=Enum.AutomaticSize.Y;body.CanvasSize=UDim2.new();body.ScrollingDirection=Enum.ScrollingDirection.Y
body.Selectable=false;body.Parent=plate
local bodyList=Instance.new('UIListLayout');bodyList.Padding=UDim.new(0,8);bodyList.SortOrder=Enum.SortOrder.LayoutOrder;bodyList.Parent=body
local bodyPad=Instance.new('UIPadding');bodyPad.PaddingTop=UDim.new(0,6);bodyPad.PaddingBottom=UDim.new(0,8);bodyPad.PaddingLeft=UDim.new(0,6);bodyPad.PaddingRight=UDim.new(0,12);bodyPad.Parent=body

local footer=Instance.new('Frame');footer.Name='Footer';footer.BackgroundTransparency=1;footer.Parent=plate
local strip=Instance.new('Frame');strip.Name='Bonus';strip.BackgroundColor3=colors.card;strip.Parent=footer;UI.corner(strip,14)
local stripStroke=UI.stroke(strip,colors.greyDark,2,0)
local stripText=UI.text(strip,'Text','',UI.Font.Bold,16);UI.fit(stripText,8,17)
local stripPips=Instance.new('Frame');stripPips.Name='Pips';stripPips.BackgroundTransparency=1;stripPips.Parent=strip
local pipList=Instance.new('UIListLayout');pipList.FillDirection=Enum.FillDirection.Horizontal;pipList.Padding=UDim.new(0,4);pipList.VerticalAlignment=Enum.VerticalAlignment.Center;pipList.Parent=stripPips
local stripClaim=UI.button(strip,'Claim','CLAIM REWARD','use')
local claimAll=UI.button(footer,'ClaimAll','COLLECT ALL','buy')

local loading=UI.text(plate,'Loading','Loading quests...',UI.Font.Bold,18,colors.muted);loading.TextXAlignment=Enum.TextXAlignment.Center
loading.Size=UDim2.fromScale(1,1);loading.Visible=false;loading.ZIndex=5
local retry=UI.button(plate,'Retry','RETRY','muted');retry.AnchorPoint=Vector2.new(.5,.5);retry.Position=UDim2.new(.5,0,.5,44);retry.Size=UDim2.fromOffset(160,48);retry.Visible=false;retry.ZIndex=6

-- Layout ------------------------------------------------------------------------------------------
local compact=false
local phone=false -- touch screens: smaller panel, slimmer rows, tabs and footer
local InputHints=require(game:GetService('ReplicatedStorage'):WaitForChild('InputHints'))
local function layout()
 local cam=workspace.CurrentCamera;local view=cam and cam.ViewportSize or Vector2.new(1280,720)
 local inset=gui.AbsoluteSize.Magnitude>0 and gui.AbsoluteSize or view
 compact=inset.Y<430 or inset.X<560
 phone=compact and InputHints.Get()=='touch'
 local w=math.min(MAX_W,inset.X-MARGIN*2-(compact and 0 or 40))
 if phone then w=math.min(w,math.floor(inset.X*.84))end
 local h=math.min(MAX_H,inset.Y-MARGIN*2)
 holder.Size=UDim2.fromOffset(w,h);holder.Position=UDim2.fromScale(.5,.5)
 local side=compact and 12 or 20
 local headH=compact and 34 or 70
 close.Position=compact and UDim2.new(1,-30,0,30)or UDim2.new(1,-6,0,6);close.Size=UDim2.fromOffset(compact and 44 or 46,compact and 44 or 46)
 sub.Visible=not compact
 header.Position=UDim2.fromOffset(side,compact and 6 or 10);header.Size=UDim2.new(1,-side*2-40,0,headH)
 title.Position=UDim2.new();title.Size=UDim2.new(.6,0,0,compact and 28 or 38)
 sub.Position=UDim2.fromOffset(0,compact and 28 or 40);sub.Size=UDim2.new(.62,0,0,compact and 18 or 22)
 timer.AnchorPoint=Vector2.new(1,0);timer.Position=UDim2.new(1,compact and -20 or 0,0,compact and 4 or 12);timer.Size=UDim2.new(.38,0,0,22)
 local tabY=(compact and 6 or 10)+headH
 local tabH=phone and 32 or compact and 44 or 46
 tabBar.Position=UDim2.fromOffset(side,tabY);tabBar.Size=UDim2.new(1,-side*2-(compact and 46 or 0),0,tabH)
 local shownTabs=0;for _,t in TABS do if not t.event or eventOn()then shownTabs+=1 end end
 for key,b in tabButtons do b.Visible=key~='event'or eventOn();b.Size=UDim2.new(1/math.max(1,shownTabs),-6,1,0)end
 local footH=phone and 42 or compact and 58 or 64
 footer.AnchorPoint=Vector2.new(0,1);footer.Position=UDim2.new(0,side,1,-(compact and 8 or 12));footer.Size=UDim2.new(1,-side*2,0,footH)
 local bodyTop=tabY+tabH+8
 body.Position=UDim2.fromOffset(side-6,bodyTop);body.Size=UDim2.new(1,-side*2+12,1,-bodyTop-footH-(compact and 14 or 20))
 local allW=compact and 140 or 190
 claimAll.AnchorPoint=Vector2.new(1,.5);claimAll.Position=UDim2.fromScale(1,.5);claimAll.Size=UDim2.new(0,allW,1,-6)
 strip.Position=UDim2.new();strip.Size=UDim2.new(1,-allW-10,1,0)
 stripText.Position=UDim2.fromOffset(compact and 8 or 14,4);stripText.Size=UDim2.new(.52,compact and -8 or -14,1,-8)
 stripPips.AnchorPoint=Vector2.new(0,.5);stripPips.Position=UDim2.new(.54,0,.5,0);stripPips.Size=UDim2.new(.16,0,0,20)
 stripClaim.AnchorPoint=Vector2.new(1,.5);stripClaim.Position=UDim2.new(1,-6,.5,0);stripClaim.Size=UDim2.new(.26,-6,1,-12)
end

-- Small builders -----------------------------------------------------------------------------------
local function iconBadge(parent,key,size)
 local f=Instance.new('Frame');f.Name='Icon';f.Size=UDim2.fromOffset(size,size);f.BackgroundColor3=colors.cardLow;f.Parent=parent;UI.corner(f,math.floor(size*.24))
 local id=ICONS[key or '']
 if id and id~=''then
  local img=Instance.new('ImageLabel');img.BackgroundTransparency=1;img.Size=UDim2.fromScale(1,1);img.Image=id;img.ScaleType=Enum.ScaleType.Fit;img.Parent=f
 else
  local g=Instance.new('UIGradient');g.Rotation=45;g.Color=ColorSequence.new(PURPLE,ORANGE);g.Parent=f
  local t=UI.text(f,'Glyph',string.upper(string.sub(tostring(key or '?'),1,1)),UI.Font.Display,math.floor(size*.5));t.Size=UDim2.fromScale(1,1)
  t.TextXAlignment=Enum.TextXAlignment.Center;UI.outline(t,2)
 end
 return f
end
local function rewardChips(parent,reward,height)
 local row=Instance.new('Frame');row.Name='Reward';row.BackgroundTransparency=1;row.AutomaticSize=Enum.AutomaticSize.X;row.Size=UDim2.fromOffset(0,height);row.Parent=parent
 local tag=UI.text(row,'Label','REWARD',UI.Font.Bold,math.floor(height*.42),READY_GOLD);tag.AutomaticSize=Enum.AutomaticSize.X;tag.Size=UDim2.fromOffset(0,height);tag.LayoutOrder=0
 local l=Instance.new('UIListLayout');l.FillDirection=Enum.FillDirection.Horizontal;l.Padding=UDim.new(0,6);l.VerticalAlignment=Enum.VerticalAlignment.Center;l.HorizontalAlignment=Enum.HorizontalAlignment.Right;l.Parent=row
 for i,key in {'tokens','revives'}do
  local n=type(reward)=='table'and tonumber(reward[key])or 0
  if n>0 then
   local chip=Instance.new('Frame');chip.Name=key;chip.LayoutOrder=i;chip.BackgroundColor3=colors.pill;chip.AutomaticSize=Enum.AutomaticSize.X;chip.Size=UDim2.fromOffset(0,height);chip.Parent=row
   UI.corner(chip,UDim.new(1,0))
   local cl=Instance.new('UIListLayout');cl.FillDirection=Enum.FillDirection.Horizontal;cl.Padding=UDim.new(0,4);cl.VerticalAlignment=Enum.VerticalAlignment.Center;cl.Parent=chip
   local pad=Instance.new('UIPadding');pad.PaddingLeft=UDim.new(0,4);pad.PaddingRight=UDim.new(0,10);pad.Parent=chip
   local img=Instance.new('ImageLabel');img.BackgroundTransparency=1;img.Size=UDim2.fromOffset(height-4,height-4);img.Image=REWARD_ICON[key];img.Parent=chip
   local t=UI.text(chip,'N',tostring(n),UI.Font.Display,math.floor(height*.62));t.AutomaticSize=Enum.AutomaticSize.X;t.Size=UDim2.fromOffset(0,height);t.LayoutOrder=2;UI.outline(t,1.5)
  end
 end
 return row
end
local function progressBar(parent,frac,complete)
 local bar=Instance.new('Frame');bar.Name='Bar';bar.BackgroundColor3=colors.cardLow;bar.Parent=parent;UI.corner(bar,UDim.new(1,0))
 local fill=Instance.new('Frame');fill.Name='Fill';fill.BackgroundColor3=Color3.new(1,1,1);fill.Size=UDim2.fromScale(math.clamp(frac,0,1),1);fill.Parent=bar
 UI.corner(fill,UDim.new(1,0))
 local g=Instance.new('UIGradient');g.Color=complete and ColorSequence.new(READY_GOLD,Color3.fromRGB(255,160,40))or ColorSequence.new(PURPLE,ORANGE);g.Parent=fill
 if frac<=0 then fill.Visible=false end
 return bar,fill
end
local function fmtNum(n)
 n=math.floor(tonumber(n)or 0)
 if n>=1e6 then return string.format('%.1fM',n/1e6)elseif n>=1e4 then return string.format('%dk',n//1000)end
 local s=tostring(n);local out=s:reverse():gsub('(%d%d%d)','%1,'):reverse();return(out:gsub('^,',''))
end
local function fmtTime(s)
 s=math.max(0,math.floor(s));local d,h,m=s//86400,(s%86400)//3600,(s%3600)//60
 if d>0 then return string.format('%dd %dh',d,h)elseif h>0 then return string.format('%dh %dm',h,m)end
 return string.format('%dm %ds',m,s%60)
end

-- Pulse on READY rims: one shared loop, only while open.
local pulsing={}
Run.RenderStepped:Connect(function()
 if not gui.Enabled then return end
 local a=(math.sin(os.clock()*4)+1)/2
 for s in pulsing do if s.Parent then s.Transparency=.05+a*.45 else pulsing[s]=nil end end
end)

-- Claim reveal ---------------------------------------------------------------------------------------
local busy=false
local function burst(over,reward)
 -- Rays + sparkle + floating amount over the card that was claimed. Visual only (the server already granted).
 sfx('coins');task.delay(.15,function()sfx('rare')end)
 local fx=Instance.new('Frame');fx.Name='Burst';fx.BackgroundTransparency=1;fx.ZIndex=30
 fx.AnchorPoint=Vector2.new(.5,.5);fx.Size=UDim2.fromOffset(40,40)
 local ap,as=over.AbsolutePosition-plate.AbsolutePosition,over.AbsoluteSize
 fx.Position=UDim2.fromOffset(ap.X+as.X/2,ap.Y+as.Y/2);fx.Parent=plate
 for i=1,10 do
  local ray=Instance.new('Frame');ray.BackgroundColor3=READY_GOLD;ray.BorderSizePixel=0;ray.AnchorPoint=Vector2.new(.5,1)
  ray.Position=UDim2.fromScale(.5,.5);ray.Size=UDim2.fromOffset(6,10);ray.Rotation=i*36;ray.ZIndex=30;ray.Parent=fx;UI.corner(ray,3)
  Tween:Create(ray,TweenInfo.new(.45,Enum.EasingStyle.Quart),{Size=UDim2.fromOffset(4,90),BackgroundTransparency=1}):Play()
 end
 local amount=type(reward)=='table'and tonumber(reward.tokens)or 0
 local revs=type(reward)=='table'and tonumber(reward.revives)or 0
 local words={}
 if amount>0 then table.insert(words,'+'..amount..' TOKENS')end
 if revs>0 then table.insert(words,'+'..revs..' REVIVE')end
 local candy=type(reward)=='table'and tonumber(reward.candyCorn)or 0
 if candy>0 then table.insert(words,'+'..candy..' CANDY CORN')end
 if type(reward)=='table'and type(reward.cosmeticIds)=='table'and #reward.cosmeticIds>0 then table.insert(words,'+ NEW COSMETIC')end
 if type(reward)=='table'and reward.tag then table.insert(words,tostring(reward.tag)..' TAG')end
 local label=UI.text(fx,'Amount',table.concat(words,'  '),UI.Font.Display,26,READY_GOLD)
 label.AnchorPoint=Vector2.new(.5,.5);label.Position=UDim2.fromScale(.5,.5);label.Size=UDim2.fromOffset(320,40);label.TextXAlignment=Enum.TextXAlignment.Center;label.ZIndex=31;UI.outline(label,2.5)
 Tween:Create(label,TweenInfo.new(1.1,Enum.EasingStyle.Quad),{Position=UDim2.new(.5,0,.5,-70),TextTransparency=1}):Play()
 task.delay(1.2,function()fx:Destroy()end)
end
local redraw -- forward
local function claim(tab,key,cardFrame)
 if busy then return end
 local f=remote('Claim')
 if not f and not MOCK then return end
 busy=true;p:SetAttribute('VanRewardHold',true)
 local ok,res
 if MOCK then
  ok,res=true,{ok=true,reward={tokens=60},state=state}
  task.wait(.25)
 else
  ok,res=pcall(function()return f:InvokeServer(tab,key)end)
 end
 if ok and type(res)=='table'and res.ok then
  if cardFrame and cardFrame.Parent then burst(cardFrame,res.reward)end
  if res.state then setState(res.state)end
 else
  sfx('cardReady',.7)
  if cardFrame and cardFrame.Parent then
   local note=UI.text(cardFrame,'Error',type(res)=='table'and res.reason or'Could not claim. Try again.',UI.Font.Bold,14,colors.red)
   note.Size=UDim2.new(1,-20,0,18);note.Position=UDim2.new(0,10,1,-20);note.ZIndex=12;task.delay(2.5,function()note:Destroy()end)
  end
  fetch()
 end
 task.delay(1.3,function()p:SetAttribute('VanRewardHold',nil)end)
 busy=false
end
local pendingAll={} -- ClaimAll request id per tab, kept until a definite answer
local function claimAllNow(tab)
 if busy then return end
 local f=remote('ClaimAll');if not f and not MOCK then return end
 busy=true;p:SetAttribute('VanRewardHold',true)
 local ok,res
 if MOCK then ok,res=true,{ok=true,reward={tokens=100},state=state}else
  -- One request id per press: an ambiguous retry of the same press must get the same frozen set back.
  -- Reuse the id until the server gives a definite answer, so a retry after a lost reply replays the same claim.
  pendingAll[tab]=pendingAll[tab]or Http:GenerateGUID(false)
  local requestId=pendingAll[tab]
  ok,res=pcall(function()return f:InvokeServer(tab,requestId)end)
 end
 if ok and type(res)=='table'and res.retry~=true then pendingAll[tab]=nil end
 if ok and type(res)=='table'and res.ok then
  -- Chain short bursts over every ready card, then one summed banner over the button.
  local cards={}
  for _,c in body:GetChildren()do if c:GetAttribute('Ready')then table.insert(cards,c)end end
  for i,c in cards do task.delay((i-1)*.22,function()if c.Parent then burst(c,nil)end end)end
  task.delay(#cards*.22,function()burst(claimAll,res.reward)end)
  if res.state then setState(res.state)end
 else
  sfx('cardReady',.7);fetch()
 end
 task.delay(1.6,function()p:SetAttribute('VanRewardHold',nil)end)
 busy=false
end
local function reroll(key)
 if busy then return end
 local f=remote('Reroll');if not f then return end
 busy=true
 local ok,res=pcall(function()return f:InvokeServer(key)end)
 if ok and type(res)=='table'and res.ok and res.state then setState(res.state)else fetch()end
 busy=false
end
local function pin(id)
 local f=remote('Pin');if not f then return end
 task.spawn(function()
  local ok,res=pcall(function()return f:InvokeServer(id)end)
  if ok and type(res)=='table'and res.ok and res.state then setState(res.state)end
 end)
end

-- Cards ------------------------------------------------------------------------------------------------
local current='daily'
local firstFocus=nil
local function card(order,height)
 local c=Instance.new('Frame');c.Name='Card'..order;c.LayoutOrder=order;c.BackgroundColor3=colors.card;c.Size=UDim2.new(1,0,0,height);c.Parent=body
 UI.corner(c,16)
 local g=Instance.new('UIGradient');g.Rotation=90;g.Color=ColorSequence.new(Color3.new(1,1,1),Color3.fromRGB(200,200,210));g.Parent=c
 return c
end
local function actionButton(parent,text,kind,width,height)
 local b=UI.button(parent,'Action',text,kind)
 b.AnchorPoint=Vector2.new(1,.5);b.Size=UDim2.fromOffset(width,height);b.Position=UDim2.new(1,-12,.5,0);b.ZIndex=4
 return b
end
local function questCard(tab,q,i,canReroll)
 local h=phone and 50 or compact and 70 or 84
 local c=card(i,h)
 local rim=UI.stroke(c,colors.greyDark,2.5,0)
 local iconSize=phone and 34 or h-20
 local icon=iconBadge(c,q.icon,iconSize);icon.Position=UDim2.fromOffset(phone and 8 or 10,phone and 8 or 10)
 local btnW,btnH=phone and 86 or compact and 104 or 128,phone and 32 or compact and 44 or 46
 local left=iconSize+(phone and 16 or 22)
 local name=UI.text(c,'Name',tostring(q.text or q.id),UI.Font.Bold,phone and 13 or compact and 16 or 18);UI.fit(name,phone and 9 or 12,phone and 13 or compact and 16 or 19)
 name.Position=UDim2.fromOffset(left,phone and 4 or compact and 6 or 8);name.Size=UDim2.new(1,-left-btnW-170,0,compact and 22 or 24)
 if not compact and q.hint then
  local hint=UI.text(c,'Hint',tostring(q.hint),UI.Font.Body,13,colors.muted);UI.fit(hint,10,13)
  hint.Position=UDim2.fromOffset(left,32);hint.Size=UDim2.new(1,-left-btnW-120,0,16)
 end
 local target=math.max(1,tonumber(q.target)or 1);local progress=math.min(target,tonumber(q.progress)or 0)
 local bar=progressBar(c,progress/target,q.ready or q.claimed)
 bar.Position=UDim2.new(0,left,1,phone and -14 or compact and -22 or -24);bar.Size=UDim2.new(1,-left-btnW-120,0,phone and 7 or compact and 10 or 12)
 local count=UI.text(c,'Count','Done '..fmtNum(progress)..' of '..fmtNum(target),UI.Font.Bold,13,colors.muted)
 count.AnchorPoint=Vector2.new(0,.5);count.Position=UDim2.new(1,-btnW-110,1,phone and -11 or compact and -17 or -18);count.Size=UDim2.fromOffset(90,phone and 14 or 18);if phone then UI.fit(count,8,11)end
 local chips=rewardChips(c,q.reward,phone and 18 or compact and 24 or 28);chips.AnchorPoint=Vector2.new(1,0);chips.Position=UDim2.new(1,-btnW-22,0,phone and 4 or compact and 6 or 10)
 if q.claimed then
  c.BackgroundTransparency=.35;rim.Color=DONE_GREEN;rim.Transparency=.4
  local stamp=UI.text(c,'Stamp','COLLECTED ✓',UI.Font.Display,phone and 13 or 18,DONE_GREEN);stamp.AnchorPoint=Vector2.new(1,.5);stamp.Position=UDim2.new(1,-16,.5,0)
  stamp.Size=UDim2.fromOffset(btnW,30);stamp.TextXAlignment=Enum.TextXAlignment.Center;UI.outline(stamp,2)
 elseif q.ready then
  c:SetAttribute('Ready',true);rim.Color=READY_GOLD;pulsing[rim]=true
  local b=actionButton(c,'CLAIM REWARD','use',btnW,btnH)
  b.Activated:Connect(function()claim(tab,q.claimKey or q.id,c)end)
  firstFocus=firstFocus or b
 elseif canReroll then
  local b=actionButton(c,'SWAP GOAL','muted',btnW,btnH)
  b:SetAttribute('RerollKey',q.claimKey or q.id)
  b.Activated:Connect(function()reroll(q.claimKey or q.id)end)
 else
  local pinned=state and state.pinned==q.id
  local b=actionButton(c,pinned and'TRACKING'or'TRACK','muted',btnW,btnH)
  if pinned then b.BackgroundColor3=PURPLE end
  b.Activated:Connect(function()pin(not pinned and q.id or nil)end)
 end
 return c
end
local function chainCard(a,i)
 local h=phone and 56 or compact and 74 or 92
 local c=card(i,h)
 local rim=UI.stroke(c,colors.greyDark,2.5,0)
 local iconSize=phone and 36 or h-20
 local icon=iconBadge(c,a.icon,iconSize);icon.Position=UDim2.fromOffset(phone and 8 or 10,phone and 10 or 10)
 local left=iconSize+(phone and 16 or 22)
 local btnW,btnH=compact and 104 or 128,compact and 44 or 46
 local tier=math.clamp(tonumber(a.tier)or 0,0,5)
 local targets=type(a.targets)=='table'and a.targets or{}
 local nextT=tonumber(targets[math.min(5,tier+1)])or 1
 local name=UI.text(c,'Name',string.upper(tostring(a.name or a.id)),UI.Font.Display,compact and 17 or 20)
 UI.outline(name,1.5);name.Position=UDim2.fromOffset(left,compact and 6 or 8);name.Size=UDim2.new(.45,0,0,compact and 22 or 26)
 -- Five tier pips: filled = claimed, gold = ready to claim.
 local pips=Instance.new('Frame');pips.Name='Tiers';pips.BackgroundTransparency=1;pips.Position=UDim2.new(.45,left,0,compact and 9 or 12);pips.Size=UDim2.fromOffset(130,18);pips.Parent=c
 local pl=Instance.new('UIListLayout');pl.FillDirection=Enum.FillDirection.Horizontal;pl.Padding=UDim.new(0,4);pl.Parent=pips
 for t=1,5 do
  local pip=Instance.new('TextLabel');pip.Size=UDim2.fromOffset(22,18);pip.Text=tostring(t);pip.FontFace=UI.Font.Bold;pip.TextSize=11;pip.Parent=pips;UI.corner(pip,5)
  pip.BackgroundColor3=t<=tier and PURPLE or(t==tier+1 and a.ready and READY_GOLD or colors.cardLow)
  pip.TextColor3=t<=tier and colors.text or(t==tier+1 and a.ready and colors.ink or colors.muted)
 end
 local done=tier>=5
 local count=math.floor(tonumber(a.count)or 0)
 local bar=progressBar(c,done and 1 or count/math.max(1,nextT),done or a.ready)
 bar.Position=UDim2.new(0,left,1,compact and -24 or -28);bar.Size=UDim2.new(1,-left-btnW-260,0,compact and 10 or 12)
 local cnt=UI.text(c,'Count',done and'ALL 5 STAGES DONE'or('Stage '..(tier+1)..' of 5 · Done '..fmtNum(count)..' of '..fmtNum(nextT)),UI.Font.Bold,13,colors.muted)
 cnt.AnchorPoint=Vector2.new(1,.5);cnt.Position=UDim2.new(1,-btnW-22,1,compact and -19 or -22);cnt.Size=UDim2.fromOffset(230,18);cnt.TextXAlignment=Enum.TextXAlignment.Right
 if not compact and a.title then
  local t=UI.text(c,'TitlePreview','Stage 5 prize: the '..tostring(a.title)..' title',UI.Font.Body,13,done and READY_GOLD or colors.muted);UI.fit(t,10,13)
  t.Position=UDim2.fromOffset(left,36);t.Size=UDim2.new(1,-left-btnW-30,0,16)
 end
 if a.ready and not done then
  c:SetAttribute('Ready',true);rim.Color=READY_GOLD;pulsing[rim]=true
  local rewards=type(a.rewards)=='table'and a.rewards or{}
  local chips=rewardChips(c,type(a.reward)=='table'and a.reward or{tokens=rewards[tier+1]},compact and 24 or 28);chips.AnchorPoint=Vector2.new(1,0);chips.Position=UDim2.new(1,-btnW-22,0,compact and 6 or 10)
  local b=actionButton(c,'CLAIM STAGE '..(tier+1),'use',btnW,btnH)
  b.Activated:Connect(function()claim('achievements',a.claimKey or a.id,c)end)
  firstFocus=firstFocus or b
 elseif done then
  rim.Color=PURPLE
  local stamp=UI.text(c,'Stamp','ALL DONE',UI.Font.Display,18,READY_GOLD);stamp.AnchorPoint=Vector2.new(1,.5);stamp.Position=UDim2.new(1,-16,.5,0)
  stamp.Size=UDim2.fromOffset(btnW,30);stamp.TextXAlignment=Enum.TextXAlignment.Center;UI.outline(stamp,2)
 end
 return c
end
local function masteryCard(m)
 -- Haunted Mastery: the single hardest reward. Requirement shown in full before anyone starts.
 local h=compact and 80 or 96
 local c=card(0,h)
 local rim=UI.stroke(c,PURPLE,3,0)
 local g=c:FindFirstChildOfClass('UIGradient');if g then g.Color=ColorSequence.new(Color3.fromRGB(70,40,110),Color3.fromRGB(30,22,44))end
 c.BackgroundColor3=Color3.new(1,1,1)
 local tag=UI.text(c,'Tag',tostring(m.tag or'[Haunted]'),UI.Font.Display,compact and 24 or 30,Color3.fromRGB(210,255,220));UI.outline(tag,2.5)
 tag.Position=UDim2.fromOffset(16,compact and 6 or 8);tag.Size=UDim2.new(.5,0,0,compact and 30 or 36)
 local tg=Instance.new('UIGradient');tg.Color=ColorSequence.new(Color3.fromRGB(200,255,210),Color3.fromRGB(120,200,150));tg.Parent=tag
 local req=UI.text(c,'Req','Finish all 10 lifetime goals through stage 5 to earn this tag',UI.Font.Bold,14,colors.muted);UI.fit(req,10,14)
 req.Position=UDim2.fromOffset(16,compact and 36 or 46);req.Size=UDim2.new(1,-180,0,18)
 local done,target=math.floor(tonumber(m.done)or 0),math.max(1,tonumber(m.target)or 10)
 local bar=progressBar(c,done/target,m.ready or m.claimed);bar.Position=UDim2.new(0,16,1,compact and -18 or -22);bar.Size=UDim2.new(1,-180,0,10)
 local btnW,btnH=compact and 104 or 128,compact and 44 or 46
 if m.claimed then
  local s=UI.text(c,'Stamp','YOURS!',UI.Font.Display,20,READY_GOLD);s.AnchorPoint=Vector2.new(1,.5);s.Position=UDim2.new(1,-16,.5,0);s.Size=UDim2.fromOffset(btnW,30)
  s.TextXAlignment=Enum.TextXAlignment.Center;UI.outline(s,2)
 elseif m.ready then
  c:SetAttribute('Ready',true);rim.Color=READY_GOLD;pulsing[rim]=true
  local b=actionButton(c,'CLAIM TAG','use',btnW,btnH);b.Activated:Connect(function()claim('mastery',m.claimKey or'mastery',c)end)
  firstFocus=firstFocus or b
 else
  local s=UI.text(c,'Count',done..' of '..target..' goals',UI.Font.Display,20,colors.text);s.AnchorPoint=Vector2.new(1,.5);s.Position=UDim2.new(1,-16,.5,0)
  s.Size=UDim2.fromOffset(btnW,30);s.TextXAlignment=Enum.TextXAlignment.Center;UI.outline(s,2)
 end
end

-- Mastery look shared by the HUD card, the level-up banner and the boards (bronze, silver, gold, master bands).
local BAND={{3,Color3.fromRGB(205,140,80),'BRONZE'},{6,Color3.fromRGB(200,214,228),'SILVER'},{9,READY_GOLD,'GOLD'},{10,Color3.fromRGB(120,255,200),'MASTER'}}
local function bandOf(level)
 for _,b in BAND do if level<=b[1] then return b[2],b[3] end end
 return BAND[#BAND][2],BAND[#BAND][3]
end
local function masteryColor(m)
 local c=type(m.color)=='table'and m.color or{255,255,255}
 return Color3.fromRGB(tonumber(c[1])or 255,tonumber(c[2])or 255,tonumber(c[3])or 255)
end
local function levelBadge(parent,level,size,complete)
 local col=level>0 and(bandOf(level))or colors.cardLow
 local ring=Instance.new('Frame');ring.Name='Level';ring.Size=UDim2.fromOffset(size,size);ring.BackgroundColor3=colors.cardLow;ring.Parent=parent;UI.corner(ring,UDim.new(1,0))
 UI.stroke(ring,col,math.max(2,math.floor(size*.08)),0)
 local lv=UI.text(ring,'Lv','LV',UI.Font.Bold,math.floor(size*.2),colors.muted);lv.Size=UDim2.new(1,0,.3,0);lv.Position=UDim2.fromScale(0,.12);lv.TextXAlignment=Enum.TextXAlignment.Center
 local n=UI.text(ring,'N',complete and'MAX'or tostring(level),UI.Font.Display,math.floor(size*(complete and .3 or .44)),level>0 and col or colors.muted)
 n.Size=UDim2.new(1,0,.55,0);n.Position=UDim2.fromScale(0,.36);n.TextXAlignment=Enum.TextXAlignment.Center;UI.outline(n,1.5)
 return ring
end
-- Footer strip: daily bonus / weekly chest / nothing on achievements.
local stripConn
local function drawFooter()
 if stripConn then stripConn:Disconnect();stripConn=nil end
 for _,x in stripPips:GetChildren()do if x:IsA('GuiObject')then x:Destroy()end end
 local readyHere=0
 local list=state and state[current]
 if current~='achievements'and type(list)=='table'and type(list.quests)=='table'then
  for _,q in list.quests do if q.ready and not q.claimed then readyHere+=1 end end
 elseif current=='achievements'and state and type(state.achievements)=='table'then
  for _,a in state.achievements do if a.ready then readyHere+=1 end end
 elseif current=='event'and eventOn()and type(state.event.quests)=='table'then
  for _,q in state.event.quests do if q.ready and not q.claimed then readyHere+=1 end end
 end
 claimAll.Text=readyHere>0 and('COLLECT ALL ('..readyHere..')')or'COLLECT ALL'
 claimAll.Active=readyHere>1;claimAll.AutoButtonColor=false;claimAll.Visible=true
 claimAll.BackgroundColor3=readyHere>1 and colors.green or colors.grey
 local extra=current=='daily'and type(list)=='table'and list.bonus or current=='weekly'and type(list)=='table'and list.chest or nil
 strip.Visible=extra~=nil
 if not extra then return end
 local doneN,target=math.floor(tonumber(extra.done)or 0),math.max(1,tonumber(extra.target)or 3)
 local r=type(extra.reward)=='table'and extra.reward or{}
 local parts={}
 if (tonumber(r.tokens)or 0)>0 then table.insert(parts,r.tokens..' TOKENS')end
 if (tonumber(r.revives)or 0)>0 then table.insert(parts,r.revives..' REVIVE')end
 stripText.Text=(current=='daily'and'★ FINISH ALL 3 TODAY  ·  'or'★ FINISH 4 FOR THE WEEKLY CHEST  ·  ')..table.concat(parts,' + ')..(current=='weekly'and' + A COSMETIC'or'')
 for i=1,target do
  local pip=Instance.new('Frame');pip.Size=UDim2.fromOffset(16,16);pip.BackgroundColor3=i<=doneN and READY_GOLD or colors.cardLow;pip.Parent=stripPips;UI.corner(pip,4)
 end
 stripStroke.Color=extra.ready and READY_GOLD or colors.greyDark;pulsing[stripStroke]=extra.ready and true or nil
 if extra.claimed then stripClaim.Text='COLLECTED ✓';stripClaim.Active=false;stripClaim.BackgroundColor3=colors.grey
 elseif extra.ready then stripClaim.Text='CLAIM REWARD';stripClaim.Active=true;stripClaim.BackgroundColor3=colors.gold
 else stripClaim.Text='Done '..doneN..' of '..target;stripClaim.Active=false;stripClaim.BackgroundColor3=colors.grey end
 stripConn=stripClaim.Activated:Connect(function()
  if extra.ready and not extra.claimed then claim(current,extra.claimKey or(current=='daily'and'bonus'or'chest'),strip)end
 end)
end

local function tabReady(key)
 if not state then return 0 end
 local n=0
 if key=='event'then
  if eventOn()and type(state.event.quests)=='table'then for _,q in state.event.quests do if q.ready and not q.claimed then n+=1 end end end
  return n
 end
 if key=='achievements'then
  if type(state.achievements)=='table'then for _,a in state.achievements do if a.ready then n+=1 end end end
  if type(state.mastery)=='table'and state.mastery.ready then n+=1 end
 else
  local t=state[key]
  if type(t)=='table'then
   if type(t.quests)=='table'then for _,q in t.quests do if q.ready and not q.claimed then n+=1 end end end
   local extra=t.bonus or t.chest;if type(extra)=='table'and extra.ready and not extra.claimed then n+=1 end
  end
 end
 return n
end

redraw=function()
 for _,c in body:GetChildren()do if c:IsA('GuiObject')then c:Destroy()end end
 table.clear(pulsing);firstFocus=nil
 sub.Text=TAB_SUB[current]or''
 for key,b in tabButtons do
  local on=key==current
  b.BackgroundColor3=on and PURPLE or colors.pill
  local badge=b:FindFirstChild('Badge');local n=tabReady(key)
  if badge then badge.Visible=n>0;local t=badge:FindFirstChild('N');if t then t.Text=tostring(n)end end
 end
 loading.Visible=state==nil;retry.Visible=false
 if not state then return end
 if current=='event'and not eventOn()then current='daily'end
 if current=='event'then
  local ev=state.event
  local head=card(0,compact and 50 or 58);local hs=UI.stroke(head,ORANGE,3,0)
  local g=head:FindFirstChildOfClass('UIGradient');if g then g.Color=ColorSequence.new(Color3.fromRGB(90,40,10),Color3.fromRGB(40,16,40))end;head.BackgroundColor3=Color3.new(1,1,1)
  local candy=UI.text(head,'Candy','CANDY CORN  '..fmtNum(ev.candyCorn or 0),UI.Font.Display,compact and 20 or 24,Color3.fromRGB(255,200,90));UI.outline(candy,2)
  candy.Position=UDim2.fromOffset(16,0);candy.Size=UDim2.new(.6,0,1,0)
  local ends=UI.text(head,'Ends',ev.endsAt and('Ends in '..fmtTime(ev.endsAt-serverNow()))or'',UI.Font.Bold,14,colors.muted)
  ends.AnchorPoint=Vector2.new(1,0);ends.Position=UDim2.new(1,-16,0,0);ends.Size=UDim2.new(.38,0,1,0);ends.TextXAlignment=Enum.TextXAlignment.Right
  hs.Transparency=0
  if type(ev.quests)=='table'then for i,q in ev.quests do questCard('event',q,i,false)end end
  if type(ev.shop)=='table'then
   for i,item in ev.shop do
    local o=Shop and Shop.ById[item.id]
    local c=card(100+i,compact and 64 or 76);UI.stroke(c,PURPLE,2,0)
    local icon=Instance.new('ImageLabel');icon.BackgroundTransparency=1;icon.Size=UDim2.fromOffset(compact and 52 or 62,compact and 52 or 62);icon.Position=UDim2.fromOffset(8,6)
    icon.Image=o and(o.image or Shop.OfferImages[item.id])or'';icon.Parent=c
    local name=UI.text(c,'Name',o and o.name or tostring(item.id),UI.Font.Bold,compact and 16 or 18);name.Position=UDim2.fromOffset(compact and 70 or 80,0);name.Size=UDim2.new(.5,0,1,0)
    local owned=item.owned==true
    local b=actionButton(c,owned and'OWNED'or(tostring(item.price)..' CANDY'),owned and'muted'or'use',compact and 120 or 140,compact and 44 or 46)
    b.Active=not owned
    b.Activated:Connect(function()
     if owned or busy then return end
     local f=remote('EventBuy');if not f then return end
     busy=true
     local ok,res=pcall(function()return f:InvokeServer(item.id)end)
     if ok and type(res)=='table'and res.ok then burst(c,{cosmeticIds={item.id}});if res.state then setState(res.state)end else sfx('cardReady',.7);fetch()end
     busy=false
    end)
   end
  end
 elseif current=='achievements'then
  if type(state.mastery)=='table'then masteryCard(state.mastery)end
  if type(state.achievements)=='table'then for i,a in state.achievements do chainCard(a,i)end end
 else
  local t=state[current]
  if type(t)=='table'and type(t.quests)=='table'then
   local canReroll=current=='daily'and not t.rerolled
   for i,q in t.quests do questCard(current,q,i,canReroll and not q.ready and not q.claimed and(tonumber(q.progress)or 0)==0)end
  end
 end
 drawFooter()
 local cells={};for _,c in body:GetChildren()do if c:IsA('Frame')then
  -- popRows wants cells holding a 'Card' with a 'Pop' scale: wrap the visual in place.
  local pop=Instance.new('UIScale');pop.Name='Pop';pop.Parent=c
  table.insert(cells,c)
 end end
 for _,c in cells do local pop=c:FindFirstChild('Pop');if pop then pop.Scale=.85;Tween:Create(pop,TweenInfo.new(.22,Enum.EasingStyle.Back,Enum.EasingDirection.Out,0,false,.03*c.LayoutOrder),{Scale=1}):Play()end end
end
onState=function()if gui.Enabled then redraw()end end

for i,tdef in TABS do
 local b=UI.button(tabBar,'Tab_'..tdef.key,tdef.label,'muted');b.LayoutOrder=i;b.Size=UDim2.new(1/#TABS,-6,1,0)
 local badge=Instance.new('Frame');badge.Name='Badge';badge.AnchorPoint=Vector2.new(.5,.5);badge.Position=UDim2.new(1,-6,0,4);badge.Size=UDim2.fromOffset(24,24)
 badge.BackgroundColor3=colors.red;badge.Visible=false;badge.ZIndex=6;badge.Parent=b;UI.corner(badge,UDim.new(1,0));UI.stroke(badge,colors.text,2,0)
 local n=UI.text(badge,'N','0',UI.Font.Display,14);n.Size=UDim2.fromScale(1,1);n.TextXAlignment=Enum.TextXAlignment.Center;n.ZIndex=7
 b.Activated:Connect(function()if current~=tdef.key then current=tdef.key;sfx('cardReady',1.3);redraw()end end)
 tabButtons[tdef.key]=b
end
claimAll.Activated:Connect(function()if claimAll.Active then claimAllNow(current)end end)
retry.Activated:Connect(function()retry.Visible=false;loading.Text='Loading quests...';task.spawn(function()if not fetch()then loading.Text='Quests are unavailable right now.';retry.Visible=true end end)end)

-- Open / close -----------------------------------------------------------------------------------------
local isOpen=false
local ACTION='QuestLogControls'
local function cycleTab(dir)
 local idx=1;for i,t in TABS do if t.key==current then idx=i end end
 for _=1,#TABS do idx=(idx-1+dir)%#TABS+1;if not TABS[idx].event or eventOn()then break end end
 current=TABS[idx].key;sfx('cardReady',1.3);redraw()
 UI.SelectWhenReady(function()return firstFocus or tabButtons[current]end)
end
local closeLog -- forward
local function onAction(_,inputState,input)
 if inputState~=Enum.UserInputState.Begin then return Enum.ContextActionResult.Sink end
 local k=input.KeyCode
 if k==Enum.KeyCode.ButtonB or k==Enum.KeyCode.Escape then closeLog()
 elseif k==Enum.KeyCode.ButtonL1 then cycleTab(-1)
 elseif k==Enum.KeyCode.ButtonR1 then cycleTab(1)
 elseif k==Enum.KeyCode.ButtonY then if claimAll.Active then claimAllNow(current)end
 elseif k==Enum.KeyCode.ButtonX then
  local sel=GS.SelectedObject;local key=sel and sel:GetAttribute('RerollKey')
  if key then reroll(key)end
 end
 return Enum.ContextActionResult.Sink
end
local tick
local function openLog(tab)
 if tab and(tab=='daily'or tab=='weekly'or tab=='achievements'or tab=='event')then current=tab end
 if isOpen then redraw();return end
 isOpen=true;p:SetAttribute('QuestLogOpen',true)
 gui.Enabled=true;layout();UI.FocusAcquire('QuestLog',gui)
 UI.showBackdrop(backdrop,true);UI.slideIn(holder,UDim2.fromScale(.5,.5),.34);sfx('panelOpen')
 redraw()
 CAS:BindActionAtPriority(ACTION,onAction,false,Enum.ContextActionPriority.High.Value+50,
  Enum.KeyCode.ButtonB,Enum.KeyCode.Escape,Enum.KeyCode.ButtonL1,Enum.KeyCode.ButtonR1,Enum.KeyCode.ButtonY,Enum.KeyCode.ButtonX)
 UIS.MouseIconEnabled=true
 task.spawn(function()
  if not fetch()and not state then loading.Text='Quests are unavailable right now.';retry.Visible=true end
  UI.SelectWhenReady(function()return firstFocus or tabButtons[current]end)
 end)
 tick=task.spawn(function()
  while isOpen do
   if state then
    local ends=current=='weekly'and state.weeklyEndsAt or current=='daily'and state.dailyEndsAt or nil
    timer.Text=ends and('Resets in '..fmtTime(ends-serverNow()))or''
   end
   task.wait(1)
  end
 end)
end
closeLog=function()
 if not isOpen then return end
 isOpen=false;p:SetAttribute('QuestLogOpen',nil)
 CAS:UnbindAction(ACTION)
 if GS.SelectedObject and GS.SelectedObject:IsDescendantOf(gui)then GS.SelectedObject=nil end
 UI.showBackdrop(backdrop,false)
 local t=UI.slideOut(holder,.2)
 t.Completed:Once(function()if not isOpen then gui.Enabled=false end end)
 UI.FocusRelease('QuestLog')
end
close.Activated:Connect(closeLog)
backdrop.Activated:Connect(closeLog)
openEvent.Event:Connect(openLog)
gui:GetPropertyChangedSignal('AbsoluteSize'):Connect(function()if isOpen then layout();redraw()end end)

-- The van terminal prompt opens the log (RecoveryModels builds QuestsRewardsPrompt like the other two).
PPS.PromptTriggered:Connect(function(prompt)
 if(prompt.Name=='QuestsRewardsPrompt'or prompt.Name=='QuestBoardPrompt'or prompt.Name=='EventStallPrompt')and not InputHints.ConfirmTap()then return end -- phones: a real tap, not a camera swipe
 if prompt.Name=='QuestsRewardsPrompt'or prompt.Name=='QuestBoardPrompt'then openLog('daily')end
 if prompt.Name=='EventStallPrompt'then openLog('event')end
end)
-- Studio test API (never in live servers): open/close/state without clicking.
if Run:IsStudio()then
 local api=Instance.new('BindableFunction');api.Name='QuestLogTestApi';api.Parent=gui
 api.OnInvoke=function(cmd,arg)
  if cmd=='open'then openLog(arg)elseif cmd=='close'then closeLog()elseif cmd=='state'then return state end
  return isOpen
 end
end

-- Completion toast (top centre, queued, never stacks) -----------------------------------------------------
local toastGui=Instance.new('ScreenGui');toastGui.Name='QuestToast';toastGui.DisplayOrder=137;toastGui.ResetOnSpawn=false
toastGui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets;toastGui.Parent=pg
local queue,showing={},false
local function showNext()
 if showing or #queue==0 then return end
 showing=true
 local text=table.remove(queue,1)
 local holderT,plateT=UI.plate(toastGui,'Toast',16)
 holderT.AnchorPoint=Vector2.new(.5,0);holderT.Size=UDim2.fromOffset(compact and 300 or 380,64);holderT.Position=UDim2.new(.5,0,0,-80)
 local ic=iconBadge(plateT,'quests',44);ic.Position=UDim2.fromOffset(10,10)
 local a=UI.text(plateT,'Head','GOAL DONE!',UI.Font.Display,18,READY_GOLD);UI.outline(a,2);a.Position=UDim2.fromOffset(64,8);a.Size=UDim2.new(1,-74,0,22)
 local b=UI.text(plateT,'Body',text..'  ·  open QUESTS to claim your reward',UI.Font.Bold,14);UI.fit(b,10,14);b.Position=UDim2.fromOffset(64,32);b.Size=UDim2.new(1,-74,0,22)
 sfx('cardReady')
 Tween:Create(holderT,TweenInfo.new(.35,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Position=UDim2.new(.5,0,0,14)}):Play()
 task.delay(3,function()
  local t=Tween:Create(holderT,TweenInfo.new(.25,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{Position=UDim2.new(.5,0,0,-80)});t:Play()
  t.Completed:Wait();holderT:Destroy();showing=false;showNext()
 end)
end
toast=function(text)
 if #queue>=4 then return end
 table.insert(queue,tostring(text));showNext()
end

-- Mastery HUD (PC and console only; touch screens keep the boards): a small card on screen (top right, under the quota
-- bar, above the run-save tag) showing the mastery you last moved, its level and the
-- bar to the next level. Points pop out of the bar and a level-up drops a banner; the full view is on the mastery boards.
local hudGui=Instance.new('ScreenGui');hudGui.Name='MasteryHud';hudGui.DisplayOrder=120;hudGui.ResetOnSpawn=false
hudGui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets;hudGui.Enabled=false;hudGui.Parent=pg
local hud=Instance.new('TextButton');hud.Name='Card';hud.Text='';hud.AutoButtonColor=false;hud.Selectable=false;hud.Active=false;hud.AnchorPoint=Vector2.new(1,0)
hud.BackgroundTransparency=1;hud.Parent=hudGui
-- Card face (owner 2026-10-25, second pass): the lobby buttons' chrome, shared with the rank card (HudCardStyle).
local cardStyle=require(game:GetService('ReplicatedStorage'):WaitForChild('HudCardStyle')).Build(hud,'MASTERY')
local hudBadgeHolder=cardStyle.socket
local hudName=UI.text(hud,'Name','',UI.Font.Display,15);UI.outline(hudName,1.5)
local hudCount=UI.text(hud,'Count','',UI.Font.Bold,12,colors.muted);hudCount.TextXAlignment=Enum.TextXAlignment.Right
local function sliceBar(parent,name,image)
 local i=Instance.new('ImageLabel');i.Name=name;i.BackgroundTransparency=1;i.Image=image;i.ScaleType=Enum.ScaleType.Slice;i.SliceCenter=Rect.new(48,23,464,25);i.SliceScale=.25;i.Parent=parent
 return i
end
-- Consoles (owner 2026-10-25): 30% bigger on a TV, matching the rank card above it (MainMenuClient TV_SCALE).
if GS:IsTenFootInterface()then local tv=Instance.new('UIScale');tv.Scale=1.3;tv.Parent=hud end
local hudBar=sliceBar(hud,'Bar','rbxassetid://90113844865582')
local hudFill=sliceBar(hudBar,'Fill','rbxassetid://137368694415108');hudFill.Size=UDim2.fromScale(0,1)
local hudMinFill=Instance.new('UISizeConstraint');hudMinFill.MinSize=Vector2.new(24,0);hudMinFill.Parent=hudFill -- keeps both rounded ends
local hudBoost=UI.text(hud,'Boost','',UI.Font.Bold,10,Color3.fromRGB(150,255,220));hudBoost.TextXAlignment=Enum.TextXAlignment.Center
hudBoost.BackgroundColor3=Color3.fromRGB(10,24,26);hudBoost.BackgroundTransparency=.1;UI.corner(hudBoost,UDim.new(0,6));UI.stroke(hudBoost,Color3.fromRGB(70,230,190),1.5,0)
-- The level sits on the bottom row; the socket shows the monster's portrait from the mastery boards instead.
local hudLevel=UI.text(hud,'Level','',UI.Font.Bold,11,Color3.fromRGB(150,255,220));hudLevel.TextXAlignment=Enum.TextXAlignment.Left
local portrait -- defined with the mastery boards below
local hudFocus,hudBadge=nil,nil
-- In a mission the quota/timer strip (RecoveryQuota) runs across the top: sit just below its lowest visible piece.
local function hudTop(small)
 local quota=p:GetAttribute('MissionActive')==true and pg:FindFirstChild('RecoveryQuota')
 if not(quota and quota:IsA('ScreenGui')and quota.Enabled)then
  -- Lobby on computer / console: the rank card owns the top-right corner (MainMenuClient QuickPlay.RankCard); sit under it.
  local qp=pg:FindFirstChild('QuickPlay');local card=qp and qp.Enabled and qp:FindFirstChild('RankCard')
  if card and card.Visible and card.AbsoluteSize.Y>0 then return math.floor(card.AbsolutePosition.Y+card.AbsoluteSize.Y-hudGui.AbsolutePosition.Y+8)end
  return small and 44 or 56
 end
 local bottom=0
 for _,d in quota:GetDescendants()do
  if d:IsA('GuiObject')and d.Visible and d.AbsoluteSize.Y>0 and d.AbsoluteSize.Y<200 then bottom=math.max(bottom,d.AbsolutePosition.Y+d.AbsoluteSize.Y)end
 end
 local shift=quota.AbsolutePosition.Y-hudGui.AbsolutePosition.Y -- both ScreenGuis use their own origin
 return math.max(small and 44 or 56,math.floor(bottom+shift+6))
end
local function hudLayout()
 local small=phone or InputHints.Get()=='touch'
 local w,h=small and 260 or 330,small and 68 or 84
 hud.Size=UDim2.fromOffset(w,h);hud.Position=UDim2.new(1,-12,0,hudTop(small))
 -- round socket for the portrait, 7 px in from the card's edges
 cardStyle.Layout(h,h+4) -- round socket 7 px in; the MASTERY tag sits in the top border over the text column
 local x=h+4 -- text starts right after the socket
 -- Three rows on the plank (name / bar / level + count), text kept clear of the plank's top and bottom edges.
 local s=h/84;local right=math.floor(14*s)
 hudName.Position=UDim2.fromOffset(x,math.floor(18*s));hudName.Size=UDim2.new(1,-x-right,0,math.floor(16*s));hudName.TextYAlignment=Enum.TextYAlignment.Center;UI.fit(hudName,10,small and 12 or 15)
 hudBar.Position=UDim2.new(0,x,0,math.floor(38*s));hudBar.Size=UDim2.new(1,-x-right,0,math.max(10,math.floor(12*s)))
 local rowY,rowH=math.floor(55*s),math.floor(13*s)
 hudLevel.Position=UDim2.fromOffset(x,rowY);hudLevel.Size=UDim2.fromOffset(math.floor(56*s),rowH);hudLevel.TextSize=math.floor(11*s)
 hudCount.Position=UDim2.fromOffset(x+math.floor(56*s),rowY);hudCount.Size=UDim2.new(1,-x-math.floor(56*s)-right,0,rowH);hudCount.TextSize=math.floor(11*s)
 -- The daily double tag hangs under the plank, in words a player understands.
 hudBoost.AnchorPoint=Vector2.new(1,0);hudBoost.Position=UDim2.new(1,-right,1,-2);hudBoost.Size=UDim2.new(1,-x-right+math.floor(30*s),0,math.floor(18*s));hudBoost.TextSize=math.floor(10*s)
end
local function pickFocus(s)
 local list=type(s)=='table'and s.masteries or nil
 if type(list)~='table'then return nil end
 local byId={};for _,m in list do byId[m.id]=m end
 if hudFocus and byId[hudFocus]then return byId[hudFocus]end
 if type(s.masteryLast)=='table'and byId[s.masteryLast.id]and not byId[s.masteryLast.id].complete then return byId[s.masteryLast.id]end
 local best,bestFrac=nil,-1
 for _,m in list do
  if not m.complete then
   local f=((tonumber(m.count)or 0)-(tonumber(m.floor)or 0))/math.max(1,(tonumber(m.nextTarget)or 1)-(tonumber(m.floor)or 0))
   if f>bestFrac then best,bestFrac=m,f end
  end
 end
 return best or list[1]
end
local function hudDraw(animate)
 local m=pickFocus(state)
 if not m then hudGui.Enabled=false;return end
 hudFocus=m.id
 local tint=masteryColor(m)
 if hudBadge then hudBadge:Destroy()end
 hudBadge=Instance.new('Frame');hudBadge.Name='Portrait';hudBadge.BackgroundTransparency=1;hudBadge.Size=UDim2.fromScale(1,1);hudBadge.Parent=hudBadgeHolder
 local disc=Instance.new('CanvasGroup');disc.Name='Disc';disc.BackgroundColor3=Color3.fromRGB(34,70,70);disc.Size=UDim2.fromScale(1,1);disc.Parent=hudBadge;UI.corner(disc,UDim.new(1,0))
 if portrait then
  local vp=portrait(disc,m.id,m.creatureKind);vp.Position=UDim2.fromScale(0,0);vp.Size=UDim2.fromScale(1,1);vp.Ambient=Color3.fromRGB(255,255,255)
  UI.corner(vp,UDim.new(1,0)) -- the 3D portrait is cut by the round socket (owner 2026-10-25: the stand poked out the bottom)
  -- Head-and-shoulders crop, centred in the round socket (the board's camera frames the whole body for a tall tile).
  -- The collector portrait is a pile of loot, so it keeps the whole pile in view.
  local mdl,cam=vp:FindFirstChildOfClass('Model'),vp.CurrentCamera
  if mdl and cam then
   local box,size=mdl:GetBoundingBox();local bust=m.kind=='monster'
   local at=box.Position+Vector3.new(0,bust and size.Y*.22 or 0,0);local r=math.max(size.X,size.Y)*(bust and .3 or .5)
   cam.CFrame=CFrame.lookAt(at+mdl:GetPivot().LookVector*(r/math.tan(math.rad(cam.FieldOfView/2))),at)
  end
 end
 if m.complete then -- mastered: the crowned ring around the portrait
  local crown=Instance.new('ImageLabel');crown.Name='MaxRing';crown.BackgroundTransparency=1;crown.Image='rbxassetid://115125938026119';crown.AnchorPoint=Vector2.new(.5,.5)
  crown.Position=UDim2.fromScale(.5,.5);crown.Size=UDim2.fromScale(1.45,1.45);crown.ZIndex=3;crown.Parent=hudBadge
 end
 hudLevel.Text=m.complete and''or('LV '..(tonumber(m.level)or 0))
 hudName.Text=string.upper(tostring(m.name));hudName.TextColor3=tint
 local count,floorV,nextV=tonumber(m.count)or 0,tonumber(m.floor)or 0,math.max(1,tonumber(m.nextTarget)or 1)
 local frac=m.complete and 1 or math.clamp((count-floorV)/math.max(1,nextV-floorV),0,1)
 hudCount.Text=m.complete and'MASTERED'or(fmtNum(count)..' / '..fmtNum(nextV)..' '..string.upper(tostring(m.unit or'')))
 cardStyle.SetAccent(m.complete and READY_GOLD or tint)
 local boost=type(state.masteryBoost)=='table'and tonumber(state.masteryBoost.left)or 0
 hudBoost.Text='';hudBoost.Visible=false -- the daily double tag is not shown on the card (user, 2026-10-22)
 hudFill.Visible=frac>0
 if animate then Tween:Create(hudFill,TweenInfo.new(.45,Enum.EasingStyle.Quad),{Size=UDim2.fromScale(frac,1)}):Play()else hudFill.Size=UDim2.fromScale(frac,1)end
end
-- Phones and tablets never get the mastery card or banner, even with a keyboard, mouse or controller attached:
-- the device decides, not the last input. Consoles and PCs keep them; boards work on every device.
local function masteryUiAllowed()
 return not InputHints.IsMobile()
end
local HIDE_FOR={'QuestLogOpen','VanShopOpen','AppearanceOpen','VanRewardsOpen','MapOpen','AdminPowersPanelOpen','AdminPassPanelOpen','InLobbyCircle'}
-- In a mission the card only appears for a few seconds when a mastery actually moves (user request 2026-10-22);
-- the lobby keeps it on screen.
local MISSION_SHOW_SECONDS=2.5
local hudShowUntil=0
local function hudVisible()
 if not masteryUiAllowed()or UI.IsFocused()then return false end -- any NeonUI panel (van shops, rewards, gift revive...)
 if p:GetAttribute('MissionActive')==true and os.clock()>hudShowUntil then return false end
 for _,a in HIDE_FOR do if p:GetAttribute(a)then return false end end
 return true
end
-- Mission pop-in (2026-10-22): the card bounces in from the right with a puff burst, a shockwave ring and sparkles around
-- the portrait; every further point gives a smaller puff; when its seconds are up it slides back out instead of vanishing.
local cardScale=Instance.new('UIScale');cardScale.Name='PopScale';cardScale.Parent=hud
local cardOut=false
local function puff(big)
 if not hudGui.Enabled or hudBadgeHolder.AbsoluteSize.X<1 then return end
 local base=hudBadgeHolder.AbsolutePosition+hudBadgeHolder.AbsoluteSize/2-hudGui.AbsolutePosition
 local m=pickFocus(state);local tint=m and masteryColor(m)or READY_GOLD
 local ring=Instance.new('Frame');ring.Name='PuffRing';ring.AnchorPoint=Vector2.new(.5,.5);ring.Position=UDim2.fromOffset(base.X,base.Y);ring.Size=UDim2.fromOffset(20,20);ring.BackgroundTransparency=1;ring.ZIndex=20;ring.Parent=hudGui
 Instance.new('UICorner',ring).CornerRadius=UDim.new(1,0)
 local rs=Instance.new('UIStroke');rs.Color=READY_GOLD;rs.Thickness=4;rs.Parent=ring
 local reach=big and 150 or 105
 Tween:Create(ring,TweenInfo.new(.5,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Size=UDim2.fromOffset(reach,reach)}):Play()
 Tween:Create(rs,TweenInfo.new(.5,Enum.EasingStyle.Quad),{Transparency=1,Thickness=1}):Play()
 task.delay(.55,function()ring:Destroy()end)
 local n=big and 12 or 8
 for i=1,n do
  local a=(i/n)*math.pi*2+math.random()*.5
  local dist=(big and 55 or 38)+math.random()*25
  local s=10+math.random()*12
  local f=Instance.new('Frame');f.Name='Puff';f.AnchorPoint=Vector2.new(.5,.5);f.Position=UDim2.fromOffset(base.X,base.Y);f.Size=UDim2.fromOffset(s*.4,s*.4)
  f.BackgroundColor3=i%3==0 and Color3.new(1,1,1)or i%3==1 and tint or READY_GOLD;f.BackgroundTransparency=.05;f.BorderSizePixel=0;f.ZIndex=19;f.Parent=hudGui
  Instance.new('UICorner',f).CornerRadius=UDim.new(1,0)
  local to=base+Vector2.new(math.cos(a),math.sin(a))*dist
  Tween:Create(f,TweenInfo.new(.55+math.random()*.2,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{Position=UDim2.fromOffset(to.X,to.Y),Size=UDim2.fromOffset(s,s),BackgroundTransparency=1}):Play()
  task.delay(.8,function()f:Destroy()end)
 end
 for i=1,big and 4 or 2 do
  local st=Instance.new('TextLabel');st.Name='Sparkle';st.BackgroundTransparency=1;st.Text='✦';st.Font=Enum.Font.GothamBold;st.TextSize=20;st.TextColor3=Color3.fromRGB(255,245,200);st.AnchorPoint=Vector2.new(.5,.5)
  st.Position=UDim2.fromOffset(base.X+math.random(-48,48),base.Y+math.random(-36,36));st.Rotation=math.random(0,90);st.ZIndex=21;st.Parent=hudGui
  local sc=Instance.new('UIScale');sc.Scale=0;sc.Parent=st
  Tween:Create(sc,TweenInfo.new(.25,Enum.EasingStyle.Back,Enum.EasingDirection.Out,0,true,i*.06),{Scale=1.4}):Play()
  Tween:Create(st,TweenInfo.new(.55,Enum.EasingStyle.Linear,Enum.EasingDirection.Out,0,false,i*.06),{Rotation=st.Rotation+90}):Play()
  task.delay(.85,function()st:Destroy()end)
 end
 sfx('giftSparkle',big and 1 or 1.15)
end
local function cardIntro()
 cardOut=false
 hud.AnchorPoint=Vector2.new(0,0);cardScale.Scale=.7
 Tween:Create(hud,TweenInfo.new(.45,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{AnchorPoint=Vector2.new(1,0)}):Play()
 Tween:Create(cardScale,TweenInfo.new(.5,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()
 sfx('itemPop',1.15)
 task.delay(.3,function()puff(true)end)
end
local function refreshHud()
 local want=state~=nil and type(state.masteries)=='table'and hudVisible()
 if not want and hudGui.Enabled and p:GetAttribute('MissionActive')==true and masteryUiAllowed()then
  if cardOut then return end
  cardOut=true
  local t=Tween:Create(hud,TweenInfo.new(.3,Enum.EasingStyle.Back,Enum.EasingDirection.In),{AnchorPoint=Vector2.new(0,0)});t:Play()
  t.Completed:Once(function()if cardOut then hudGui.Enabled=false;hud.AnchorPoint=Vector2.new(1,0);cardOut=false end end)
  return
 end
 if want and cardOut then cardOut=false;hud.AnchorPoint=Vector2.new(1,0)end
 hudGui.Enabled=want
 if hudGui.Enabled then hudLayout();hudDraw(false)end
end
for _,attr in HIDE_FOR do p:GetAttributeChangedSignal(attr):Connect(refreshHud)end
p:GetAttributeChangedSignal('MissionActive'):Connect(refreshHud)
local function popPoints(n)
 local t=UI.text(hud,'Pop','+'..n,UI.Font.Display,20,READY_GOLD);UI.outline(t,2)
 t.AnchorPoint=Vector2.new(1,.5);t.Position=UDim2.new(1,-8,0,hudBar.Position.Y.Offset);t.Size=UDim2.fromOffset(60,24);t.TextXAlignment=Enum.TextXAlignment.Right;t.ZIndex=5
 Tween:Create(t,TweenInfo.new(1,Enum.EasingStyle.Quad),{Position=UDim2.new(1,-8,0,hudBar.Position.Y.Offset-30),TextTransparency=1}):Play()
 task.delay(1.05,function()t:Destroy()end)
 local s=Instance.new('UIScale');s.Scale=1.08;s.Parent=hud;Tween:Create(s,TweenInfo.new(.3,Enum.EasingStyle.Back),{Scale=1}):Play();task.delay(.35,function()s:Destroy()end)
end
-- Level-up banner: top centre, below the goal toast, queued.
local bannerQueue,bannerShowing={},false
local function nextBanner()
 if bannerShowing or #bannerQueue==0 then return end
 if not masteryUiAllowed()then table.clear(bannerQueue);return end
 bannerShowing=true
 local info=table.remove(bannerQueue,1)
 local holderB,plateB=UI.plate(toastGui,'MasteryBanner',18)
 holderB.AnchorPoint=Vector2.new(.5,0);holderB.Size=UDim2.fromOffset(compact and 320 or 420,compact and 76 or 88);holderB.Position=UDim2.new(.5,0,0,-100)
 local col=bandOf(info.level)
 local badge=levelBadge(plateB,info.level,compact and 56 or 66,info.complete);badge.Position=UDim2.fromOffset(10,(compact and 10 or 11))
 local x=(compact and 56 or 66)+20
 local head=UI.text(plateB,'Head',info.complete and(string.upper(info.name)..' MASTERED!')or(string.upper(info.name)..'  ·  LEVEL '..info.level),UI.Font.Display,compact and 17 or 21,col)
 UI.outline(head,2);head.Position=UDim2.fromOffset(x,compact and 8 or 10);head.Size=UDim2.new(1,-x-10,0,compact and 24 or 28);UI.fit(head,11,compact and 17 or 21)
 local words={}
 if info.tokens>0 then table.insert(words,'+'..info.tokens..' TOKENS')end
 if info.revives>0 then table.insert(words,'+'..info.revives..' REVIVE')end
 if info.title then table.insert(words,'MONSTER MASTER TITLE')end
 local body=UI.text(plateB,'Body',table.concat(words,'   '),UI.Font.Display,compact and 15 or 18,READY_GOLD);UI.outline(body,1.5)
 body.Position=UDim2.fromOffset(x,compact and 36 or 42);body.Size=UDim2.new(1,-x-10,0,compact and 22 or 26);UI.fit(body,10,compact and 15 or 18)
 sfx('coins');if info.complete then task.delay(.15,function()sfx('rare')end)end
 Tween:Create(holderB,TweenInfo.new(.4,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Position=UDim2.new(.5,0,0,compact and 84 or 92)}):Play()
 task.delay(info.complete and 4 or 3,function()
  local t=Tween:Create(holderB,TweenInfo.new(.25,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{Position=UDim2.new(.5,0,0,-100)});t:Play()
  t.Completed:Wait();holderB:Destroy();bannerShowing=false;nextBanner()
 end)
end
onMastery=function(old,new)
 if type(new)~='table'or type(new.masteries)~='table'then refreshHud();return end
 local before={};if type(old)=='table'and type(old.masteries)=='table'then for _,m in old.masteries do before[m.id]=m end end
 local moved,gained=nil,0
 for _,m in new.masteries do
  local was=before[m.id]
  if was then
   local d=(tonumber(m.count)or 0)-(tonumber(was.count)or 0)
   if d>0 then moved=m;gained=d end
   for l=(tonumber(was.level)or 0)+1,(tonumber(m.level)or 0)do
    local complete=l>=(tonumber(m.maxLevel)or 10)
    local tokens=tonumber(m.levelReward and m.levelReward.tokens)or 0
    local revives=complete and(tonumber(m.completeReward and m.completeReward.revives)or 0)or 0
    if #bannerQueue<6 then table.insert(bannerQueue,{name=tostring(m.name),level=l,complete=complete,tokens=tokens,revives=revives})end
   end
  end
 end
 local grandNow=type(new.grandMastery)=='table'and new.grandMastery.claimed
 local grandWas=type(old)=='table'and type(old.grandMastery)=='table'and old.grandMastery.claimed
 if grandNow and not grandWas and type(old)=='table'then table.insert(bannerQueue,{name='Monster Master',level=10,complete=true,tokens=0,revives=0,title=true})end
 if moved then hudFocus=moved.id;hudShowUntil=os.clock()+MISSION_SHOW_SECONDS end
 local wasShown=hudGui.Enabled and not cardOut
 refreshHud()
 if drawBoards then drawBoards()end
 if moved and hudGui.Enabled then
  popPoints(gained);hudDraw(true)
  if not wasShown and p:GetAttribute('MissionActive')==true then cardIntro()else puff(false)end
 end
 nextBanner()
end
gui:GetPropertyChangedSignal('AbsoluteSize'):Connect(function()if hudGui.Enabled then hudLayout()end end)

-- Mastery boards: the lobby's MasteryBoard (beside the leaderboard) and the van's VanMasteryBoard. Every player sees
-- their own six masteries: the monster itself (ReplicatedStorage.MasteryPortraits), level, ten level pips, the bar to
-- the next level, the next reward, today's 2x boost and the road to the Monster Master title.
local Portraits=RS:WaitForChild('MasteryPortraits',10)
local boards={} -- face part -> {gui, tiles, header refs}
local BOARD_FONT=Enum.Font.FredokaOne
local INK=Color3.fromRGB(5,5,8)
local function bText(parent,name,text,x,y,w,h,color,max,align)
 local t=Instance.new('TextLabel');t.Name=name;t.Text=text;t.BackgroundTransparency=1;t.Font=BOARD_FONT;t.TextScaled=true;t.TextColor3=color or colors.text
 t.TextXAlignment=align or Enum.TextXAlignment.Left;t.Position=UDim2.fromScale(x,y);t.Size=UDim2.fromScale(w,h);t.Parent=parent
 local k=Instance.new('UITextSizeConstraint');k.MaxTextSize=max or 200;k.Parent=t
 local o=Instance.new('UIStroke');o.Color=INK;o.Thickness=3;o.ApplyStrokeMode=Enum.ApplyStrokeMode.Contextual;o.Parent=t
 return t
end
local function bFrame(parent,name,x,y,w,h,color,radius)
 local f=Instance.new('Frame');f.Name=name;f.BackgroundColor3=color;f.BorderSizePixel=0;f.Position=UDim2.fromScale(x,y);f.Size=UDim2.fromScale(w,h);f.Parent=parent
 if radius then local c=Instance.new('UICorner');c.CornerRadius=radius;c.Parent=f end
 return f
end
function portrait(parent,id,kind) -- assigns the local declared above the mastery card
 local vp=Instance.new('ViewportFrame');vp.Name='Portrait';vp.BackgroundTransparency=1;vp.Position=UDim2.fromScale(.02,.06);vp.Size=UDim2.fromScale(.36,.88)
 vp.Ambient=Color3.fromRGB(225,225,235);vp.LightColor=Color3.fromRGB(255,245,230);vp.LightDirection=Vector3.new(-.4,-1,-.8);vp.Parent=parent
 local src=Portraits and Portraits:FindFirstChild(kind or(id=='m_collector'and'Collector')or'')
 if not src then return vp end
 local m=src:Clone();m:PivotTo(CFrame.new());m.Parent=vp
 local box,size=m:GetBoundingBox()
 local cam=Instance.new('Camera');cam.FieldOfView=28;cam.Parent=vp;vp.CurrentCamera=cam
 local front=m:GetPivot().LookVector
 local dist=math.max(size.Y,size.X*1.1,size.Z)/2/math.tan(math.rad(14))*1.08
 local at=box.Position
 cam.CFrame=CFrame.lookAt(at+front*dist+Vector3.new(0,size.Y*.08,0),at)
 return vp
end
local function buildBoard(face)
 local gui=Instance.new('SurfaceGui');gui.Name='MasteryBoardUI';gui.Adornee=face;gui.Face=Enum.NormalId.Front;gui.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize
 gui.CanvasSize=Vector2.new(1600,math.floor(1600*face.Size.Y/math.max(.1,face.Size.X)));gui.LightInfluence=0;gui.Brightness=1.4;gui.ResetOnSpawn=false
 gui.ZOffset=1;gui.Parent=pg
 local bg=bFrame(gui,'Back',0,0,1,1,Color3.new(1,1,1),UDim.new(0,40))
 local fill=Instance.new('UIGradient');fill.Rotation=90;fill.Color=ColorSequence.new(Color3.fromRGB(38,26,58),Color3.fromRGB(10,9,16));fill.Parent=bg
 local rim=Instance.new('UIStroke');rim.Thickness=12;rim.Color=Color3.new(1,1,1);rim.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;rim.Parent=bg
 local rg=Instance.new('UIGradient');rg.Color=ColorSequence.new(READY_GOLD,PURPLE);rg.Rotation=30;rg.Parent=rim
 local ui={gui=gui,tiles={}}
 local title=bText(bg,'Title','MASTERIES',.035,.025,.5,.115,Color3.new(1,1,1),180)
 local tg=Instance.new('UIGradient');tg.Rotation=90;tg.Color=ColorSequence.new(Color3.fromRGB(255,236,150),Color3.fromRGB(255,150,40));tg.Parent=title
 bText(bg,'Sub','ESCAPE MONSTERS  ·  COLLECT LOOT  ·  EVERY LEVEL PAYS 25 TOKENS',.037,.142,.6,.045,colors.muted,60)
 bText(bg,'TotalLabel','YOUR TOTAL LEVEL',.6,.03,.365,.04,colors.muted,50,Enum.TextXAlignment.Right)
 ui.total=bText(bg,'Total','0 / 60',.6,.068,.365,.085,colors.text,140,Enum.TextXAlignment.Right)
 ui.boost=bFrame(bg,'Boost',.62,.158,.345,.048,DONE_GREEN,UDim.new(1,0))
 ui.boostText=bText(ui.boost,'Text','',.04,.08,.92,.84,INK,48,Enum.TextXAlignment.Center);ui.boostText:FindFirstChildOfClass('UIStroke').Enabled=false
 local list=type(state)=='table'and state.masteries or {}
 for i,m in list do
  if i>6 then break end
  local col,row=(i-1)%3,math.floor((i-1)/3)
  local tile=bFrame(bg,'Tile'..i,.03+col*.317,.225+row*.322,.302,.3,Color3.new(1,1,1),UDim.new(0,28))
  local tint=masteryColor(m)
  local tf=Instance.new('UIGradient');tf.Rotation=90;tf.Color=ColorSequence.new(tint:Lerp(Color3.fromRGB(20,18,30),.78),Color3.fromRGB(12,11,18));tf.Parent=tile
  local stroke=Instance.new('UIStroke');stroke.Thickness=6;stroke.Color=tint;stroke.Transparency=.25;stroke.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;stroke.Parent=tile
  local halo=bFrame(tile,'Halo',.04,.12,.32,.76,tint,UDim.new(1,0));halo.BackgroundTransparency=.7
  portrait(tile,m.id,m.creatureKind)
  local ring=bFrame(tile,'Level',.025,.6,.15,.36,Color3.fromRGB(14,12,20),UDim.new(1,0));ring.SizeConstraint=Enum.SizeConstraint.RelativeYY;ring.Size=UDim2.fromScale(.36,.36)
  local rs=Instance.new('UIStroke');rs.Thickness=5;rs.Color=colors.cardLow;rs.Parent=ring
  local lv=bText(ring,'Lv','LV',.1,.1,.8,.26,colors.muted,40,Enum.TextXAlignment.Center)
  local n=bText(ring,'N','0',.1,.32,.8,.56,colors.text,90,Enum.TextXAlignment.Center)
  bText(tile,'Name',string.upper(tostring(m.name)),.4,.07,.57,.17,tint,90)
  local pips=Instance.new('Frame');pips.Name='Pips';pips.BackgroundTransparency=1;pips.Position=UDim2.fromScale(.4,.29);pips.Size=UDim2.fromScale(.57,.1);pips.Parent=tile
  local pl=Instance.new('UIListLayout');pl.FillDirection=Enum.FillDirection.Horizontal;pl.Padding=UDim.new(.012,0);pl.Parent=pips
  local pipList={}
  for l=1,math.max(1,tonumber(m.maxLevel)or 10)do
   local pip=Instance.new('Frame');pip.Size=UDim2.fromScale(.088,1);pip.BackgroundColor3=colors.cardLow;pip.BorderSizePixel=0;pip.Parent=pips
   local pc=Instance.new('UICorner');pc.CornerRadius=UDim.new(.3,0);pc.Parent=pip;pipList[l]=pip
  end
  local bar=bFrame(tile,'Bar',.4,.45,.57,.12,Color3.fromRGB(8,8,12),UDim.new(1,0))
  local barFill=bFrame(bar,'Fill',0,0,0,1,Color3.new(1,1,1),UDim.new(1,0))
  local bfg=Instance.new('UIGradient');bfg.Color=ColorSequence.new(tint,READY_GOLD);bfg.Parent=barFill
  local count=bText(tile,'Count','',.4,.6,.57,.15,colors.text,80)
  local nextR=bText(tile,'Next','',.4,.78,.57,.13,READY_GOLD,60)
  ui.tiles[m.id]={tile=tile,stroke=stroke,ring=rs,n=n,lv=lv,pips=pipList,fill=barFill,count=count,nextR=nextR,tint=tint}
 end
 local foot=bFrame(bg,'Footer',.03,.885,.94,.085,Color3.fromRGB(20,16,30),UDim.new(0,24))
 local fs=Instance.new('UIStroke');fs.Thickness=5;fs.Color=READY_GOLD;fs.Transparency=.35;fs.Parent=foot
 ui.grandText=bText(foot,'Grand','MONSTER MASTER TITLE',.025,.15,.45,.7,READY_GOLD,70)
 local stars=Instance.new('Frame');stars.Name='Stars';stars.BackgroundTransparency=1;stars.Position=UDim2.fromScale(.48,.18);stars.Size=UDim2.fromScale(.28,.64);stars.Parent=foot
 local sl=Instance.new('UIListLayout');sl.FillDirection=Enum.FillDirection.Horizontal;sl.Padding=UDim.new(.02,0);sl.HorizontalAlignment=Enum.HorizontalAlignment.Center;sl.Parent=stars
 ui.stars={}
 for s=1,6 do local st=bText(stars,'Star'..s,'★',0,0,.14,1,colors.cardLow,80,Enum.TextXAlignment.Center);ui.stars[s]=st end
 ui.grandCount=bText(foot,'Count','0 / 6 MASTERED',.77,.15,.205,.7,colors.text,60,Enum.TextXAlignment.Right)
 return ui
end
local function drawBoard(ui)
 if type(state)~='table'or type(state.masteries)~='table'then return end
 local total,maxTotal=0,0
 for _,m in state.masteries do
  local level,maxLevel=math.floor(tonumber(m.level)or 0),math.max(1,math.floor(tonumber(m.maxLevel)or 10))
  total+=level;maxTotal+=maxLevel
  local t=ui.tiles[m.id]
  if t then
   local band=level>0 and(bandOf(level))or colors.cardLow
   t.ring.Color=m.complete and READY_GOLD or band
   t.n.Text=m.complete and'MAX'or tostring(level);t.n.TextColor3=level>0 and band or colors.muted
   for l,pip in t.pips do pip.BackgroundColor3=l<=level and(bandOf(l))or colors.cardLow end
   local count,floorV,nextV=tonumber(m.count)or 0,tonumber(m.floor)or 0,math.max(1,tonumber(m.nextTarget)or 1)
   local frac=m.complete and 1 or math.clamp((count-floorV)/math.max(1,nextV-floorV),0,1)
   t.fill.Size=UDim2.fromScale(frac,1);t.fill.Visible=frac>0
   local unit=string.upper(tostring(m.unit or''))
   t.count.Text=m.complete and(fmtNum(count)..' '..unit)or(fmtNum(count)..' / '..fmtNum(nextV)..' '..unit)
   if m.complete then
    t.nextR.Text='★ MASTERED ★';t.stroke.Color=READY_GOLD;t.stroke.Transparency=0;t.stroke.Thickness=9
   else
    local tokens=tonumber(m.levelReward and m.levelReward.tokens)or 25
    local revive=level+1>=maxLevel and(tonumber(m.completeReward and m.completeReward.revives)or 0)or 0
    t.nextR.Text='LEVEL '..(level+1)..':  +'..tokens..' TOKENS'..(revive>0 and('  +'..revive..' REVIVE')or'')
    t.stroke.Color=t.tint;t.stroke.Transparency=hudFocus==m.id and 0 or .25;t.stroke.Thickness=hudFocus==m.id and 8 or 6
   end
  end
 end
 ui.total.Text=total..' / '..maxTotal
 local boost=type(state.masteryBoost)=='table'and state.masteryBoost or{}
 local left=tonumber(boost.left)or 0
 ui.boost.BackgroundColor3=left>0 and DONE_GREEN or colors.cardLow
 ui.boostText.TextColor3=left>0 and INK or colors.muted
 ui.boostText.Text=left>0 and('2X BOOST  ·  '..left..' OF '..tostring(boost.limit or 5)..' LEFT TODAY')or('2X BOOST BACK IN '..(boost.resetAt and fmtTime(boost.resetAt-serverNow())or'A DAY'))
 local grand=type(state.grandMastery)=='table'and state.grandMastery or{}
 local done,target=math.floor(tonumber(grand.done)or 0),math.max(1,math.floor(tonumber(grand.target)or 6))
 for s,st in ui.stars do st.TextColor3=s<=done and READY_GOLD or colors.cardLow;st.Visible=s<=target end
 ui.grandText.Text=grand.claimed and'MONSTER MASTER  ·  TITLE UNLOCKED!'or'MONSTER MASTER TITLE'
 ui.grandCount.Text=done..' / '..target..' MASTERED'
end
local function boardFaces()
 local out={}
 local lobby=workspace:FindFirstChild('LobbyWorld');local lb=lobby and lobby:FindFirstChild('MasteryBoard')
 local lf=lb and lb:FindFirstChild('MasteryFace',true);if lf then table.insert(out,lf)end
 local camp=workspace:FindFirstChild('RecoveryCamp');local vf=camp and camp:FindFirstChild('VanMasteryBoard',true)
 if vf then table.insert(out,vf)end
 return out
end
drawBoards=function()
 if type(state)~='table'or type(state.masteries)~='table'then return end
 local live={}
 for _,face in boardFaces()do
  live[face]=true
  local ui=boards[face]
  if not ui or not ui.gui.Parent then ui=buildBoard(face);boards[face]=ui end
  drawBoard(ui)
 end
 for face,ui in boards do if not live[face]then ui.gui:Destroy();boards[face]=nil end end
end
task.spawn(function()while true do task.wait(2);drawBoards()end end) -- the van board appears with each mission's camp
-- Once a second: the quota strip appears and resizes after joining, and the input device or a panel can change.
task.spawn(function()while true do task.wait(1)
 local want=state~=nil and type(state.masteries)=='table'and hudVisible()
 if want~=hudGui.Enabled then refreshHud()elseif want then hudLayout()end
end end)

-- Van terminal face (RecoveryModels builds QuestsRewardsTerminal; edits here are local, so every player sees
-- their own progress on the same panel) ------------------------------------------------------------------
local faces={}
local function trackFace(x)if x.Name=='QuestsRewardsTerminal'and x:IsA('BasePart')then faces[x]=true end end
for _,x in workspace:GetDescendants()do trackFace(x)end
workspace.DescendantAdded:Connect(trackFace)
local function drawFaces()
 for t in faces do
  if not t:IsDescendantOf(workspace)then faces[t]=nil
  else
   local frame=t:FindFirstChild('RewardFace')and t.RewardFace:FindFirstChild('Frame')
   if frame then
    local ready=state and tonumber(state.readyCount)or 0
    local st=frame:FindFirstChild('Status')
    if st then
     local text=not state and'DAILY + WEEKLY QUESTS'or ready>0 and(ready..' READY TO CLAIM!')
      or('NEW QUESTS IN '..fmtTime((tonumber(state.dailyEndsAt)or serverNow())-serverNow()))
     if st.Text~=text then st.Text=text end
     st.TextTransparency=ready>0 and(math.sin(os.clock()*4)+1)*.18 or 0
    end
    local list=state and type(state.daily)=='table'and state.daily.quests
    for i=1,3 do
     local bar=frame:FindFirstChild('Bar'..i);local fill=bar and bar:FindFirstChild('Fill')
     if fill then
      local q=type(list)=='table'and list[i]
      local frac=q and math.clamp((tonumber(q.progress)or 0)/math.max(1,tonumber(q.target)or 1),0,1)or 0
      fill.Size=UDim2.fromScale(frac,1);fill.Visible=frac>0
      fill.BackgroundColor3=q and q.claimed and DONE_GREEN or Color3.new(1,1,1)
     end
    end
   end
  end
 end
end
task.spawn(function()while true do if next(faces)then drawFaces()end;task.wait(.1)end end)

-- Wiring to the server -------------------------------------------------------------------------------------
task.spawn(function()
 if MOCK then setState(mockState());return end
 local folder=RS:WaitForChild('Quests',60);if not folder then return end
 local changed=folder:WaitForChild('StateChanged',30)
 if changed and changed:IsA('RemoteEvent')then changed.OnClientEvent:Connect(function(s)setState(s,true)end)end
 for _=1,5 do if fetch()then break end;task.wait(3)end
end)
